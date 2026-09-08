-- migration-version: 20260830042328
-- migration-name:    0110b_pair_verdict_within_status_vocabulary
--
-- ---------------------------------------------------------------------------
-- RECOVERED 2026-09-08, not authored then. This migration was applied to
-- gxdrcyphqjzjsuhxuqtg on 2026-08-30 04:23:28 UTC and never had a file. It is
-- one of exactly two changes Section A of the drift check named on the first
-- day the alarm was able to fire at all (see task G18); the other is 0121b.
--
-- The body below is VERBATIM from supabase_migrations.schema_migrations, which
-- stores the statements it was given. It is not a reconstruction.
--
-- WHAT IT DID: replaced public.ottoq_determinism_pair so the verdict it writes
-- into ottoq_sim_runs.validation_status stays inside that column's allowed
-- vocabulary ('passed'/'failed') instead of writing a value the CHECK refuses.
--
-- DO NOT RE-RUN. The function has been replaced many times since — 0125 added
-- the boot image, 0139 the end state, 0148 h_nrg, 0199 h_prop/h_defr, 0201
-- h_cal, 0203/0205 h_rule, 0206 h_rcl, 0217 h_sdr and the h_rcl enforcement.
-- Executing this file today would silently undo eleven migrations. It is
-- committed as the record of what happened, which is the whole point of
-- APPLYING.md's rule that the file is the only thing that can be read,
-- reviewed, reverted or blamed.
-- ---------------------------------------------------------------------------

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
