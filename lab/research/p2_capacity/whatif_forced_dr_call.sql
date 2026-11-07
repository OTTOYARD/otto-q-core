-- What-if for a lab day only (capacity_day.py --lab-sql): a scenario's forced demand-response call actually fires.
--
-- dr_event_cascade and heat_wave carry grid_overrides.force_dr_call_hour (14 and 15) and dr_required_cap_kw (400 and
-- 800), and nothing in the engine reads either key (2026-11-06, every routine's source searched): their calls come only
-- from twin.ottoq_sim_maybe_ignite_dr_call's temperature-driven hazard, which on the lab's September days did not fire
-- (FINDINGS G518). Here the igniter fires the scenario's call at its hour, once per run, with the scenario's figure as the
-- reduction the igniter's own draw stands for (0433: the call caps grid import at the prior hour's mean less the
-- reduction); its duration is the igniter's own draw. Nothing else changes.
DO $whatif$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_maybe_ignite_dr_call(uuid,uuid,timestamp with time zone,numeric,bigint)'::regprocedure);
  c_roll constant text := $a$  v_roll := ottoq_sim_seeded_random(p_seed, 'dr_ignite');
  IF v_roll >= v_prob THEN RETURN NULL; END IF;$a$;
  c_roll_new constant text := $b$  v_roll := ottoq_sim_seeded_random(p_seed, 'dr_ignite');
  -- lab what-if (G518): the scenario's forced call fires at its hour, once per run
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs r JOIN ottoq_sim_scenarios s ON s.scenario_code = r.scenario_code
              WHERE r.sim_run_id = p_sim_run_id
                AND (s.grid_overrides->>'force_dr_call_hour')::int = v_hour)
     AND NOT EXISTS (SELECT 1 FROM ottoq_dr_calls c WHERE c.sim_run_id = p_sim_run_id) THEN
    v_roll := -1;
  END IF;
  IF v_roll >= v_prob THEN RETURN NULL; END IF;$b$;
  c_cap constant text := $c$  v_cap_kw  := 50 + ottoq_sim_seeded_random(p_seed, 'dr_cap') * 350;$c$;
  c_cap_new constant text := $d$  v_cap_kw  := 50 + ottoq_sim_seeded_random(p_seed, 'dr_cap') * 350;
  -- lab what-if (G518): a forced call's reduction is the scenario's dr_required_cap_kw
  SELECT COALESCE((s.grid_overrides->>'dr_required_cap_kw')::numeric, v_cap_kw) INTO v_cap_kw
    FROM ottoq_sim_runs r JOIN ottoq_sim_scenarios s ON s.scenario_code = r.scenario_code
   WHERE r.sim_run_id = p_sim_run_id AND (s.grid_overrides->>'force_dr_call_hour')::int = v_hour;
  v_cap_kw := COALESCE(v_cap_kw, 50 + ottoq_sim_seeded_random(p_seed, 'dr_cap') * 350);$d$;
BEGIN
  IF (length(v_def) - length(replace(v_def, c_roll, ''))) / length(c_roll) <> 1
     OR (length(v_def) - length(replace(v_def, c_cap, ''))) / length(c_cap) <> 1 THEN
    RAISE EXCEPTION 'forced-call what-if: an anchor is not found exactly once in twin.ottoq_sim_maybe_ignite_dr_call';
  END IF;
  EXECUTE replace(replace(v_def, c_roll, c_roll_new), c_cap, c_cap_new);
END
$whatif$;
