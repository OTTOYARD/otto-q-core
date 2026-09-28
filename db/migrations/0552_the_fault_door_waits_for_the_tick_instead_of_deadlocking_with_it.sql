-- migration-version: 20260928170009
-- migration-name:    the_fault_door_waits_for_the_tick_instead_of_deadlocking_with_it
--
-- 0552  **The cockpit's charger-fault door waits for the tick instead of deadlocking with it.** (G285)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Every tick of a live run is one transaction that begins by locking the run's row:
--   `ottoq_sim_advance_tick_world` opens with `SELECT ... FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id FOR UPDATE`
--   (the metronome calls it first in each tick and commits after the decide step). The tick then writes sessions,
--   chargers, stalls and vehicles. The cockpit's fault door, `ottoq_twin_inject_charger_fault`, reads the run's row
--   without a lock and then writes the same kinds of rows: since 0550 it stops the charger's session through
--   `twin.ottoq_sim_stop_charge_session`, which updates the session row and then inserts an OCPP message. That insert's
--   foreign key to `ottoq_sim_runs` takes a KEY SHARE lock on the run's row, which the tick's FOR UPDATE refuses. The
--   door holds a session the tick is about to advance and waits for the run's row; the tick holds the run's row and
--   waits for the session. Postgres kills one of them, and it is the door:
--     - job 777 (check 0408): the first attempt, 15:19 UTC, deadlocked; the retry succeeded. Before 0550 the door
--       touched no session, so it met the tick only at the reassignment guard's INSERT into `ottoq_ops_approvals`, the
--       same foreign key.
--     - job 778 (check 0409): the attempts at 16:56:00 and 16:57:00 UTC both deadlocked, in
--       `ottoq_sim_emit_ocpp` → INSERT INTO ottoq_ocpp_messages → `SELECT 1 FROM ONLY "public"."ottoq_sim_runs" ... FOR
--       KEY SHARE`. Since 0550 the door works on the rows the tick advances every few seconds, so it now loses almost
--       every time. The job was unscheduled after the second failure.
--   The cockpit's button reaches the same door through `otto-twin-control`, so an operator pressing it during a live run
--   gets an error and no fault. `twin.ottoq_report_charger_fault`, the depot tech's "confirm a fault" path, has the
--   same order: it writes the charger and the stall and only then meets the run's row through the reassignment guard.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Both doors take the run's row FOR UPDATE first, as the tick does. A door called during a tick waits for that tick
--   to commit, then runs on its committed state; the next tick waits for the door. One lock order, so no cycle. The door
--   reads the run's sim clock after the wait, so it stamps the fault on the clock the world has reached.
--   (a) `public.ottoq_twin_inject_charger_fault`: its opening read of the run becomes `... FOR UPDATE`.
--   (b) `twin.ottoq_report_charger_fault`: its read of the depot's running run becomes `... FOR UPDATE`, before it
--       writes the charger.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════════
--
--   No arm calls either door (V2 asserts it, as 0550 V2 did). The lock changes when a door runs, not what it does.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - The general rule: any door that writes into a live run takes the run's row first. The other public.ottoq_twin_*
--     functions that write are the card dealers (called inside the tick) and the calibration refit (no run). Doors
--     outside that name space (vehicle commands, approvals) are not swept here.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0552 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: the two functions are the ones measured (2026-09-28 16:59 UTC, definitions) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)'::regprocedure))
     <> '643fd2715b049cce44ccda02ff3181b5' THEN
    RAISE EXCEPTION '0552 P2: public.ottoq_twin_inject_charger_fault is not the function measured';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_report_charger_fault(uuid,text,text,text)'::regprocedure))
     <> '4ef997087de3fd6e6f166953ca9b64af' THEN
    RAISE EXCEPTION '0552 P2: twin.ottoq_report_charger_fault is not the function measured';
  END IF;
  -- the tick's first statement is the lock this file matches
  IF regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure),
       '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g')
     !~ 'BEGIN\s+v_tick_t0 := clock_timestamp\(\);\s+SELECT \* INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id FOR UPDATE;' THEN
    RAISE EXCEPTION '0552 P2: the world tick no longer opens by locking the run''s row';
  END IF;
END $premises$;

-- ── V2: the premise of forces_recert FALSE (§3), asserted before anything is written ──
DO $unreachable$
DECLARE v_callers text[];
BEGIN
  WITH src AS (
    SELECT n.nspname || '.' || p.proname AS fn,
           regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g') AS body
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prokind IN ('f', 'p'))
  SELECT array_agg(fn ORDER BY fn) INTO v_callers
    FROM src
   WHERE (strpos(body, 'ottoq_twin_inject_charger_fault') > 0 AND fn <> 'public.ottoq_twin_inject_charger_fault')
      OR (strpos(body, 'ottoq_report_charger_fault') > 0 AND fn NOT IN ('twin.ottoq_report_charger_fault', 'public.ottoq_twin_inject_charger_fault'));
  IF v_callers IS NOT NULL THEN
    RAISE EXCEPTION '0552 V2: the fault doors have callers in the engine (%); forces_recert FALSE does not hold', v_callers;
  END IF;
END $unreachable$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0552_pre', 'function', f.sch, f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('public', 'ottoq_twin_inject_charger_fault', 'public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)'),
               ('twin',   'ottoq_report_charger_fault',      'twin.ottoq_report_charger_fault(uuid,text,text,text)')
       ) AS f(sch, obj, sig);

-- ── (a) the door takes the run's row first ──
DO $door$
DECLARE v_def text; n int;
  c_old CONSTANT text := E'  SELECT sim_run_id, depot_id, status, sim_clock_current INTO v_run\n'
    || E'    FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;\n';
  c_new CONSTANT text := E'  -- 0552 (G285): the run''s row first, FOR UPDATE, as the tick takes it. A door called during a tick waits for the\n'
    || E'  -- tick to commit instead of deadlocking with it over the sessions and stalls both write.\n'
    || E'  SELECT sim_run_id, depot_id, status, sim_clock_current INTO v_run\n'
    || E'    FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id\n'
    || E'     FOR UPDATE;\n';
BEGIN
  v_def := pg_get_functiondef('public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0552 door: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $door$;

-- ── (b) the tech's confirm path takes the depot's running run first ──
DO $report$
DECLARE v_def text; n int;
  c_old CONSTANT text := E'  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM ottoq_sim_runs\n'
    || E'   WHERE depot_id = v_depot AND status=''running'' ORDER BY started_at DESC LIMIT 1;\n';
  c_new CONSTANT text := E'  -- 0552 (G285): the run''s row first, FOR UPDATE, as the tick takes it, before the charger and the stall.\n'
    || E'  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM ottoq_sim_runs\n'
    || E'   WHERE depot_id = v_depot AND status=''running'' ORDER BY started_at DESC LIMIT 1\n'
    || E'     FOR UPDATE;\n';
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_report_charger_fault(uuid,text,text,text)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0552 report: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $report$;

-- ── V1 (comment-stripped): each door's first lock is the run's row ──
DO $verify$
DECLARE v_src text;
BEGIN
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF v_src !~ 'BEGIN\s+SELECT sim_run_id, depot_id, status, sim_clock_current INTO v_run\s+FROM public\.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id\s+FOR UPDATE;' THEN
    RAISE EXCEPTION '0552 V1: the door does not open by locking the run''s row';
  END IF;
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('twin.ottoq_report_charger_fault(uuid,text,text,text)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF v_src !~ 'ORDER BY started_at DESC LIMIT 1\s+FOR UPDATE;\s+v_clock := COALESCE\(v_clock, now\(\)\);\s+UPDATE ottoq_ocpp_chargers' THEN
    RAISE EXCEPTION '0552 V1: the confirm path does not lock the run''s row before it writes the charger';
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0552_the_fault_door_waits_for_the_tick_instead_of_deadlocking_with_it', false, false,
  'G285: public.ottoq_twin_inject_charger_fault and twin.ottoq_report_charger_fault take the run''s row FOR UPDATE '
  'first, as ottoq_sim_advance_tick_world does, so a door called during a tick waits for it instead of deadlocking '
  'with it (the door wrote sessions and stalls, then met the run''s row through a foreign key; the tick held the row and '
  'wanted the session: check 0409, job 778, two deadlocks). FALSE because no arm calls either door (V2).', now())
ON CONFLICT (name) DO NOTHING;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0552_pre' as it is.

COMMIT;
