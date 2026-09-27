-- migration-version: 20260927002850
-- migration-name:    a_twin_command_records_when_it_executed
--
-- 0505  **A twin-executed command recorded that it executed 30 minutes after it was issued, whenever it actually
--       executed (G237).** `db/checks/0374` §6.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-27 on validation run b0fdc92b) ═════════════════════════════════════════
--
--   `twin.ottoq_sim_confirm_commands` executes an issued command in the tick it runs (`v_now`: it moves the car and
--   seats the stall there and then), but its executed branch stamped `confirmed_at` and `executed_at` with
--   `v_due := COALESCE(issued_at, v_now) + interval '30 minutes'` ("Determine due time: 30 sim-minutes after issue, or
--   configurable"). Its refusal branches stamp `v_now`, and so does the real acknowledgement path
--   (`ottoq_ack_vehicle_command`). On b0fdc92b all 281 executed commands (103 `begin_charge`, 88 `stage`, 76
--   `proceed_to_stall`, 11 `enter_wash`, 3 `enter_service`) read exactly 1,800 seconds from issue, one distinct value,
--   on a run that ticks about every 33 sim-seconds. So the column said something the twin never did, and sim and real
--   rows disagreed on what it means. 0308 §8 read `executed_at - issued_at` = 30:00 on a canon arm, whose tick is 30
--   sim-minutes, as "the confirm chain costs exactly one tick" (G112), and 0311 reported the column as a lag: the
--   constant, not a measurement. I made the same mistake reading recall appointments on b0fdc92b ("1 of 77 reached
--   after execution"; 28 of 77 from the issue time).
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The executed branch stamps `confirmed_at` and `executed_at` with `v_now`, the tick the command executed in, and the
--   due time is gone. Nothing else changes: what executes, when, and in what order is untouched.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   Neither column is in any certified digest (`h_cmd` hashes issued_at, vehicle, type, stall, status and reason), and
--   no engine function or view reads either one for a vehicle command: the only functions that name them write them
--   (`ottoq_ack_vehicle_command`, `ottoq.ottoq_emit_vehicle_command`, `ottoq_sim_release_depot`, and this one). The
--   cockpits do not read them either.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0505 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P1: no run is live (the world tick calls this; V3 plants its case on the depot's own rows, rolled back) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION '0505 P1: a run is live; apply between runs';
  END IF;
END $live$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure))
     <> '68d76e15913221bc6caec2fe9ac4e100' THEN
    RAISE EXCEPTION '0505 P2: twin.ottoq_sim_confirm_commands is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0505_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure);
  v_pairs text[][] := ARRAY[
    [$o1$  v_due       timestamptz;
$o1$, ''],
    [$o2$    -- Determine due time: 30 sim-minutes after issue, or configurable
    v_due := COALESCE(v_rec.issued_at, v_now) + interval '30 minutes';
$o2$, $n2$    -- 0505 (G237): no due time. This stamped confirmed_at and executed_at at issue + 30 sim-minutes while the
    -- command executed here, now: 281 of 281 on b0fdc92b read exactly 1,800 seconds. The real acknowledgement path
    -- stamps the moment it executes, and so does this.
$n2$],
    [$o3$             confirmed_at = v_due,
$o3$, $n3$             confirmed_at = v_now,
$n3$],
    [$o4$             executed_at = v_due
$o4$, $n4$             executed_at = v_now
$n4$]];
  i int; n int;
BEGIN
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0505: patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure;
  v_def text := pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure);
BEGIN
  -- V1: no due time left; the executed branch stamps v_now, and the refusal branches still do.
  IF position('v_due' IN v_def) > 0
     OR (length(v_def) - length(replace(v_def, 'executed_at = v_now', ''))) / length('executed_at = v_now') <> 1
     OR (length(v_def) - length(replace(v_def, 'confirmed_at = v_now', ''))) / length('confirmed_at = v_now') <> 5 THEN
    RAISE EXCEPTION '0505 V1: twin.ottoq_sim_confirm_commands is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer and search path kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f) <> 'postgres=X/postgres,service_role=X/postgres'
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_f) <> 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0505 V2: twin.ottoq_sim_confirm_commands''s privileges or settings changed';
  END IF;
END $verify$;

-- V3: the case, planted on the newest stopped operator run and rolled back. A car is sent `stage` to a free staging
-- stall through the command door at the run's clock, and the confirm step runs half a minute later, as the next world
-- tick would. The command must execute, stamped with the confirm step's clock, not issue + 30 minutes.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_clock timestamptz; v_car uuid; v_stall uuid; v_cmd uuid; c record;
  v_depot uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
  BEGIN
    SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.validation_status IS NULL AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0505 V3 FAILED: no stopped operator run to plant on'; END IF;
    -- only the planted command is the confirm step's to take
    UPDATE public.ottoq_vehicle_commands SET status = 'expired', reason_code = 'run_ended'
     WHERE sim_run_id = v_run AND status = 'issued';
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.home_depot_id = v_depot AND v.current_stall_id IS NULL ORDER BY v.id LIMIT 1;
    SELECT s.id INTO v_stall FROM public.stalls s
     WHERE s.depot_id = v_depot AND s.stall_type = 'staging' AND s.zone <> 'arrival_inspection'
       AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
       AND COALESCE((ottoq.ottoq_validate_assignment(v_car, s.id, 'stage', v_clock, v_run)->>'ok')::boolean, false)
     ORDER BY s.id LIMIT 1;
    IF v_car IS NULL OR v_stall IS NULL THEN RAISE EXCEPTION '0505 V3 FAILED: no car or stall to plant on'; END IF;
    v_cmd := ottoq.ottoq_emit_vehicle_command(v_run, v_depot, v_car, 'stage',
               jsonb_build_object('stall_id', v_stall, 'stall_type', 'staging'), v_clock);
    PERFORM twin.ottoq_sim_confirm_commands(v_run, v_clock + interval '30 seconds');
    SELECT status, issued_at, confirmed_at, executed_at INTO c FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd;
    IF c.status IS DISTINCT FROM 'executed'
       OR c.executed_at IS DISTINCT FROM v_clock + interval '30 seconds'
       OR c.confirmed_at IS DISTINCT FROM v_clock + interval '30 seconds' THEN
      RAISE EXCEPTION '0505 V3 FAILED: command % issued % confirmed % executed %', c.status, c.issued_at, c.confirmed_at, c.executed_at;
    END IF;
    RAISE EXCEPTION '0505 V3 PASSED: issued %, executed % (the confirm step''s clock)', c.issued_at, c.executed_at;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0505 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0505 V3: no verdict'); END IF;
END $v3$;

-- Rollback: restore twin.ottoq_sim_confirm_commands from ottoq_schema_snapshots label '0505_pre' (CREATE OR REPLACE,
-- ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0505_a_twin_command_records_when_it_executed', false,
  'twin.ottoq_sim_confirm_commands stamps confirmed_at and executed_at with the tick it executes a command in, not '
  'issued_at + 30 minutes. Neither column is in a certified digest or read by the engine; what executes and when is '
  'unchanged.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
