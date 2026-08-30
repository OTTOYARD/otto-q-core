-- migration-version: 20260830100000
-- migration-name:    the_one_command_determinism_check
-- 0110 -- folds the db/checks/0046 determinism instrument into one callable:
--
--     SELECT public.ottoq_determinism_pair(424242);           -- 12 ticks, busy_day
--     SELECT public.ottoq_determinism_pair(171717, 24);       -- 24 ticks
--
-- Runs two same-seed arms back to back (reset -> start_run -> prime -> synchronous tick
-- loop), captures the five canonical values per arm (world fingerprint + command / decision
-- / event / booking stream hashes, exactly the 0046 projections with their volatile-id
-- exclusions), tears each arm down, and returns the verdict. The verdict is ALSO stamped
-- into both run rows (validation_status = 'passed' | 'failed' -- the column's check
-- constraint allows only pending/passed/failed/inconclusive, a fact the FIRST exercise of
-- this function caught when a draft used invented statuses -- with the full hash verdict in
-- validation_notes) because a long pair outlives most client timeouts: fire the call, let
-- the client drop, read the verdict off the two newest cert_harness runs.
--
-- HARNESS ONLY. No engine behavior changes. Both arms run inside the caller's single
-- transaction -- the pair-14 rule (one now() per arm; a resumed arm shifts the REAL-domain
-- proposal TTLs) is satisfied by construction, and the whole pair shares one now(), which
-- matches how every certified pair since 0046 was measured. The claim it checks is the
-- scoped one recorded in db/checks/0046. Verdicts to date: pairs 13 (171717/12t),
-- 15 (424242/12t), 16 (424242/24t) all equal on all five values.
--
-- New function; nothing patched, so no pre-image pin. CREATE OR REPLACE is safe: the name
-- is new in this migration and any future change to it comes as its own numbered migration.

CREATE OR REPLACE FUNCTION public.ottoq_determinism_pair(
  p_seed bigint,
  p_ticks int DEFAULT 12,
  p_scenario text DEFAULT 'busy_day',
  p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
  p_sim_start timestamptz DEFAULT '2026-09-01 02:00:00+00'::timestamptz,
  p_arm_budget_s int DEFAULT 240
) RETURNS jsonb
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_arm int; v_run uuid; v_t0 timestamptz;
  v_clock timestamptz; v_status text; v_ticks int;
  v_h jsonb; v_arms jsonb[] := '{}';
  v_equal boolean; v_verdict jsonb;
BEGIN
  FOR v_arm IN 1..2 LOOP
    PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed);
    v_run := twin.ottoq_sim_start_run(p_scenario, p_sim_start, 60, p_seed, 'cert_harness');
    BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, p_sim_start, 0.70);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'determinism_pair arm % prime failed: %', v_arm, SQLERRM; END;

    v_t0 := clock_timestamp();
    LOOP
      SELECT sim_clock_current, status, tick_count INTO v_clock, v_status, v_ticks
        FROM ottoq_sim_runs WHERE sim_run_id = v_run;
      EXIT WHEN v_status <> 'running' OR v_ticks >= p_ticks;
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) >= p_arm_budget_s;
      PERFORM public.ottoq_sim_advance_tick(v_run);
    END LOOP;

    SELECT jsonb_build_object(
      'run', v_run, 'ticks', r.tick_count, 'clock', r.sim_clock_current,
      'fp', r.payload->>'world_fingerprint',
      'h_cmd', (SELECT md5(COALESCE(string_agg(
          issued_at::text||'|'||vehicle_id::text||'|'||command_type||'|'||COALESCE(payload->>'stall_id','-')||'|'||status||'|'||COALESCE(reason_code,'-'),
          E'\n' ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status), ''))
        FROM ottoq_vehicle_commands c WHERE c.sim_run_id = v_run),
      'h_dec', (SELECT md5(COALESCE(string_agg(
          sim_clock::text||'|'||tick_seq::text||'|'||action_context||'|'||entity_id::text||'|'||outcome_status
          ||'|'||COALESCE(enacted_action->>'verb', proposed_action->>'verb','-')||'|'||COALESCE(proposed_action->>'stall_id','-'),
          E'\n' ORDER BY sim_clock, tick_seq, action_context, entity_id, outcome_status,
                        COALESCE(enacted_action->>'verb', proposed_action->>'verb','-'), COALESCE(proposed_action->>'stall_id','-')), ''))
        FROM ottoq_decisions d WHERE d.sim_run_id = v_run),
      'h_evt', (SELECT md5(COALESCE(string_agg(
          event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                THEN '-' ELSE COALESCE(entity_id::text,'-') END,
          E'\n' ORDER BY event_type,
                        CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                             THEN '-' ELSE COALESCE(entity_id::text,'-') END), ''))
        FROM ottoq_events e WHERE e.sim_run_id = v_run),
      'h_bkg', (SELECT md5(COALESCE(string_agg(
          lower(during)::text||'|'||upper(during)::text||'|'||vehicle_id::text||'|'||stall_id::text||'|'||purpose||'|'||state,
          E'\n' ORDER BY lower(during), vehicle_id, stall_id, purpose, state), ''))
        FROM ottoq_stall_bookings k WHERE k.sim_run_id = v_run))
      INTO v_h
      FROM ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    v_arms := v_arms || v_h;

    PERFORM public.ottoq_sim_stop_and_reset(v_run, 'determinism_arm_complete');
  END LOOP;

  v_equal := (v_arms[1]->>'fp')    = (v_arms[2]->>'fp')
         AND (v_arms[1]->>'h_cmd') = (v_arms[2]->>'h_cmd')
         AND (v_arms[1]->>'h_dec') = (v_arms[2]->>'h_dec')
         AND (v_arms[1]->>'h_evt') = (v_arms[2]->>'h_evt')
         AND (v_arms[1]->>'h_bkg') = (v_arms[2]->>'h_bkg')
         AND (v_arms[1]->>'ticks') = (v_arms[2]->>'ticks');

  v_verdict := jsonb_build_object(
    'equal', v_equal, 'seed', p_seed, 'ticks', p_ticks, 'scenario', p_scenario,
    'arm_a', v_arms[1], 'arm_b', v_arms[2]);

  -- The verdict survives a dropped client: it lives on both run rows.
  UPDATE ottoq_sim_runs
     SET validation_status = CASE WHEN v_equal THEN 'passed' ELSE 'failed' END,
         validation_notes  = v_verdict::text
   WHERE sim_run_id IN ((v_arms[1]->>'run')::uuid, (v_arms[2]->>'run')::uuid);

  RETURN v_verdict;
END
$fn$;
