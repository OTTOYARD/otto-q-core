-- migration-version: 20260926170804
-- migration-name:    the_orphan_sweep_ends_a_twin_session_on_its_runs_clock
--
-- 0492  **The orphan sweep ends a twin charge session on its run's clock (G220).**
--
-- ══ §1 WHAT WAS WRONG (measured on 461c79fa, 0363) ════════════════════════════════════════════════════════════════
--
--   `public.ottoq_reconcile_charger_states` (every world tick) cancels an active twin session whose car no longer
--   points at the session's stall, with `ended_at = COALESCE(cs.ended_at, now())`. `now()` is the wall clock, and
--   every other time on a twin session is the sim clock (0326 §1's class). On 461c79fa, Zoox-AV-076's L2 session was
--   left by the exception handler at sim 9:37:35 AM and swept on the next tick at sim 9:38:03, and its `ended_at`
--   read the real clock, hours away from its own `started_at`. 9 of about 24,800 twin sessions carry such an end.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   A swept session with a run takes that run's `sim_clock_current`. A session with no run (never a twin session in
--   practice, since the sweep is limited to `TWIN-%` tokens) keeps `now()`. `updated_at` stays the wall clock: it is
--   the row's audit stamp, not a time in the session.
--
-- ══ §3 forces_recert TRUE ═══════════════════════════════════════════════════════════════════════════════════════
--
--   The sweep runs inside the certified world tick. A certified arm that sweeps a session now records a sim-clock
--   end, so the canon re-certifies.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0492 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_reconcile_charger_states(uuid)'::regprocedure))
     <> '70b0d76e2ce6bd63e88bf9aa274514dc' THEN
    RAISE EXCEPTION '0492 P2: public.ottoq_reconcile_charger_states is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0492_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_reconcile_charger_states(uuid)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_reconcile_charger_states(uuid)'::regprocedure);
  v_old text := $o$           ended_at       = COALESCE(cs.ended_at, now()),
$o$;
  v_new text := $n$           -- 0492 (G220): a twin session ends on its run's clock, not the wall clock.
           ended_at       = COALESCE(cs.ended_at,
                                     (SELECT r.sim_clock_current FROM ottoq_sim_runs r WHERE r.sim_run_id = cs.sim_run_id),
                                     now()),
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0492: the orphan sweep''s ended_at matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'public.ottoq_reconcile_charger_states(uuid)'::regprocedure;
  v_def text := pg_get_functiondef('public.ottoq_reconcile_charger_states(uuid)'::regprocedure);
BEGIN
  -- V1: the sweep's end reads the run's clock first, and the wall clock only for a session with no run.
  IF position('(SELECT r.sim_clock_current FROM ottoq_sim_runs r WHERE r.sim_run_id = cs.sim_run_id)' IN v_def) = 0
     OR position('COALESCE(cs.ended_at, now())' IN v_def) > 0 THEN
    RAISE EXCEPTION '0492 V1: the orphan sweep still ends a session on the wall clock';
  END IF;
  -- V2: the rest of the function is untouched (the three steps and the tether exemption).
  IF position('vehicle_departed_orphan_sweep' IN v_def) = 0 OR position('robotic_tether_stall_id' IN v_def) = 0
     OR position($x$SET station_state = 'Available'$x$ IN v_def) = 0 THEN
    RAISE EXCEPTION '0492 V2: the reconciler lost a step it should keep';
  END IF;
  -- V3: privileges and security definer kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
        <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0492 V3: ottoq_reconcile_charger_states''s privileges changed';
  END IF;
END $verify$;

-- Rollback: restore public.ottoq_reconcile_charger_states from ottoq_schema_snapshots label '0492_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0492_the_orphan_sweep_ends_a_twin_session_on_its_runs_clock', true,
  'ottoq_reconcile_charger_states ends a swept twin session on its run''s sim clock instead of now(). The sweep runs '
  'in the certified world tick.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
