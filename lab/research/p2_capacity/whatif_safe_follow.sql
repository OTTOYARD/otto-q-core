-- What-if for a lab day only (capacity_day.py --lab-sql): G519's fix, as a candidate for a migration.
--
-- With energy_mpc_follow at 1, public.ottoq_energy_orchestrate follows the newest 'ready' plan in ottoq_energy_plan for
-- the current step, clamped only to the battery's power, floor and ceiling. It does not read v_dr_active, so a
-- demand-response call that comes after the plan was made gets no answer from the battery in this mode, and nothing
-- bounds the plan's age (FINDINGS G519). The change, two anchored edits:
--   (1) a live call is the day plan's: plan-follow is skipped while v_dr_active, so the day-plan path (0435) defends
--       the call's cap with the battery (`discharge_dr`), and the next plan made after the call starts from the battery
--       the call left;
--   (2) a plan is followed only while fresh: no more than 3 steps after its start (15 minutes at the lab's step), then
--       the day plan again. The lab's planner writes a plan before every tick (step 0), so (2) changes nothing on a day
--       its planner keeps up; it matters for a planner that falls behind or stops.
-- Nothing else in the function changes. v_dr_active is computed before the FR-1 branch.
DO $whatif$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  c_gate constant text := $a$  IF ottoq_policy_get(p_sim_run_id, 'energy_mpc_follow', 0) >= 0.5 THEN$a$;
  c_gate_new constant text := $b$  IF ottoq_policy_get(p_sim_run_id, 'energy_mpc_follow', 0) >= 0.5
     AND NOT v_dr_active THEN   -- lab what-if (G519): a live call is the day plan's$b$;
  c_step constant text := $c$      IF v_step >= 0 AND v_step < v_plan.horizon_steps AND v_step+1 <= array_length(v_plan.bess_setpoint_kw,1) THEN$c$;
  c_step_new constant text := $d$      IF v_step >= 0 AND v_step < v_plan.horizon_steps AND v_step+1 <= array_length(v_plan.bess_setpoint_kw,1)
         AND v_step < 3 THEN   -- lab what-if (G519): a plan is followed only while fresh$d$;
BEGIN
  IF (length(v_def) - length(replace(v_def, c_gate, ''))) / length(c_gate) <> 1
     OR (length(v_def) - length(replace(v_def, c_step, ''))) / length(c_step) <> 1 THEN
    RAISE EXCEPTION 'safe-follow what-if: an anchor is not found exactly once in public.ottoq_energy_orchestrate';
  END IF;
  EXECUTE replace(replace(v_def, c_gate, c_gate_new), c_step, c_step_new);
END
$whatif$;
