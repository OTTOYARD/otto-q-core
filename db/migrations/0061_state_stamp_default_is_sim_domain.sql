-- migration-version: 20260820190000
-- migration-name:    state_stamp_default_is_sim_domain
-- 0061 — C7 FOLLOW-UP #15, found by re-certification #15 (post-0060 arms
-- c5dbc377 vs 943936c5: 19/20 identical, sole divergence sim-min 600 — the
-- last tick). 0060 HOLDS completely: the command streams are byte-paired in
-- run-relative time for the entire run, the vehicle-state stream is paired for
-- 312 of 313 transitions, and the frame digest shows exactly ONE differing
-- vehicle in one tick.
--
-- The residue is a single extra transition in arm B: vehicle 964bd583,
-- charge_complete_holding -> staged_for_departure, correctly ordered ahead of
-- acba173d's identical transition (which both arms make). A membership
-- difference in a cap-limited release, not an ordering difference.
--
-- ROOT CAUSE — 0057's guard has a BLIND SPOT, and this is the exact case that
-- exposes it. 0057 stopped the trigger clobbering callers that pass a stamp
-- DIFFERENT from the stored one. But a caller passing the SAME value is
-- indistinguishable, inside a BEFORE UPDATE trigger, from a caller passing
-- nothing — and that is precisely what happens when a vehicle changes state
-- TWICE IN ONE TICK: the second write carries the same sim clock the first one
-- stored, the guard reads it as "unset", and NOW() — a REAL clock — is written
-- into last_state_change. Two decide-path fairness cursors and the service-flow
-- release cursor ORDER BY that column, so wall-clock ordering re-enters through
-- the one door 0057 left open.
--
-- MEASURED, from the event payload of the divergent write: 964bd583 went
-- charging_l2 -> charge_complete_holding -> staged_for_departure inside tick 20,
-- and its last_state_change came out of that second write as
--   to   2026-08-20T18:06:36.269616+00  (wall clock)
--   from 2026-08-21T04:05:32.269186+00  (the run's own sim clock, tick 20)
-- The cap-limited release cursor then admitted a different member set per arm.
--
-- THE FIX: the trigger's DEFAULT stamp becomes sim-domain whenever the
-- vehicle's depot has a RUNNING sim run, so the equal-value case re-stamps the
-- identical sim clock (a no-op) instead of a wall clock. Production behavior is
-- unchanged by construction: a depot with no running sim run still falls back
-- to NOW(), exactly as before 0057 and 0061. Nothing about scheduling semantics
-- moves.
--
-- SWEEP: every non-internal trigger function in the database was checked for
-- `NEW.<col> := now()/clock_timestamp()` writes. Four exist. Only this one
-- writes a column that anything ORDERs BY — public.update_timestamp and the two
-- update_updated_at_column variants write `updated_at`, which the 0060 ORDER BY
-- census confirmed is never an ordering key and which the frame digest does not
-- score. Reviewed, deliberately unchanged.
--
-- Same self-verifying in-place mechanism as 0054-0060. Pre-image pin:
--   public.log_vehicle_state_change b171ab3116a6286475d60dc1074ddb31

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := E'    IF NEW.last_state_change IS NOT DISTINCT FROM OLD.last_state_change THEN\n      NEW.last_state_change = NOW();\n    END IF;';
  v_new text := E'    /* ══════════ 0061: THE 0057 GUARD HAD A BLIND SPOT ══════════\n'
             || E'       A caller that passes the SAME stamp the row already holds is, inside a\n'
             || E'       BEFORE UPDATE trigger, indistinguishable from one that passes nothing —\n'
             || E'       and that is exactly what happens when a vehicle changes state TWICE IN\n'
             || E'       ONE TICK: the second write carries the same sim clock the first stored,\n'
             || E'       the guard reads "unset", and NOW() (a REAL clock) lands in the column two\n'
             || E'       decide-path fairness cursors and the service-flow release cursor ORDER BY.\n'
             || E'       Measured (re-cert #15, arms c5dbc377/943936c5, 19/20, sole divergence\n'
             || E'       sim-min 600): vehicle 964bd583 went charging_l2 -> charge_complete_holding\n'
             || E'       -> staged_for_departure inside tick 20, and that second write stamped\n'
             || E'       2026-08-20T18:06:36 (wall clock) over the run''s own 2026-08-21T04:05:32\n'
             || E'       (sim clock); the cap-limited release cursor then admitted a different\n'
             || E'       member set in each arm.\n'
             || E'       The default stamp is now SIM-DOMAIN whenever this vehicle''s depot has a\n'
             || E'       RUNNING sim run, so the equal-value case re-stamps the identical sim clock\n'
             || E'       (a no-op) instead of a wall clock. Production is unchanged: a depot with no\n'
             || E'       running sim run still falls back to NOW(), exactly as before. */\n'
             || E'    IF NEW.last_state_change IS NOT DISTINCT FROM OLD.last_state_change THEN\n'
             || E'      NEW.last_state_change = COALESCE(\n'
             || E'        (SELECT r.sim_clock_current FROM public.ottoq_sim_runs r\n'
             || E'          WHERE r.status = ''running''\n'
             || E'            AND r.depot_id = COALESCE(NEW.current_depot_id, NEW.home_depot_id)\n'
             || E'          ORDER BY r.started_at DESC, r.sim_run_id\n'
             || E'          LIMIT 1),\n'
             || E'        NOW());\n'
             || E'    END IF;';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'public' AND pr.proname = 'log_vehicle_state_change';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'b171ab3116a6286475d60dc1074ddb31' THEN
    RAISE EXCEPTION '0061: pre-image md5 % != pinned b171ab3116a6286475d60dc1074ddb31', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0061: anchor occurs % times (need 1)', v_cnt;
  END IF;
  EXECUTE replace(v_src, v_old, v_new);
  RAISE NOTICE '0061 patched public.log_vehicle_state_change -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'log_vehicle_state_change');
END
$do$;
