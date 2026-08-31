-- migration-version: 20260831200000
-- migration-name:    the_site_limit_is_an_input
-- 0136 -- the power-publication boundary, enforced in the direction it was always written.
--
-- THE RULE THIS RESTORES. CLAUDE.md 2.5: "Real-time setpoint commands to physical inverters are
-- never issued by OTTO-Q directly"; production interfaces "publish forward demand schedules to
-- site controllers and vendor EMS." OTTO-Defense states it shorter: orchestrate, never actuate.
-- The site power limit is therefore an INPUT to the kernel, and the forward schedule is its
-- OUTPUT. Neither is a number our own simulated battery hands back to us.
--
-- WHAT WAS ACTUALLY WIRED. A same-tick closed loop through the simulator:
--     ottoq_energy_orchestrate  -- INSERT ottoq_energy_commands(command_type='charge_cap_kw')
--       -> twin.ottoq_sim_energy_controller marks it 'executed'
--         -> ottoq_active_charge_cap_kw reads it back
--           -> ottoq_effective_charge_cap_kw = LEAST(depots.service_max_kw, that)
--             -> ottoq_decide_tick plans against it  /* 0132 */
-- and the cap itself is computed as
--     v_charge_cap := GREATEST(50, v_demand_target - v_base_load + v_solar + v_bess_dispatch);
-- where v_bess_dispatch comes from ottoq_bess_units -- simulated SoC, temperature and power
-- limits. OTTO-Q wrote a number, the twin executed it, and the scheduler then obeyed its own
-- command as if it were a site constraint.
--
-- MEASURED, not asserted: 3,914 of 4,343 charge_cap_kw commands (90.1%) sit BELOW the depot's
-- real service limit of 2,500 kW, so the simulated battery -- not the utility service contract
-- -- was the binding site constraint in the overwhelming majority of ticks. The cap chattered
-- between roughly 1,270 and 812 kW every 30 sim-minutes as the battery flipped between
-- hold_reserve and charge_offpeak_reserve. Worked example, run 4837ed16 tick 4: demand_target
-- 1325 - base_load 54 + solar 0 = 1271, emitted cap 811.6 => v_bess_dispatch = -459.4 kW. A
-- simulated battery deciding to recharge removed 459 kW from the fleet's charging budget. That
-- produced 19,993 'deferred_site_power_cap' refusals across 51 runs -- up to 22.5% of decisions
-- in an affected run. Every one of those refusals was caused by our own simulation, not by the
-- site. The commands even tag themselves 'advisory': true in their reason payload while the
-- 0132 gate hard-enforces them.
--
-- PART A -- the cap becomes an input. ottoq_effective_charge_cap_kw is the smallest safe seam in
-- the system for this: exactly ONE caller (ottoq_decide_tick) and ZERO view dependents, verified
-- against pg_get_viewdef over every relkind in ('v','m'). It keeps its LEAST() shape and its
-- signature; only its second term changes, from "what our battery left us" to "what an external
-- party declared." The declared source is public.ottoq_dr_calls, which already exists and already
-- carries required_load_cap_kw / call_status / expires_at / depot_id, whose sim_run_id is
-- NULLABLE and whose data_source has no CHECK constraint -- so a production, externally-supplied
-- cap row lands in it with NO schema change. Verify, consolidate, extend; do not invent a table.
--
-- HONEST CONSEQUENCE, stated up front because it looks like a regression and is not. There are
-- no active DR calls today (all 4 rows are 'cleared'), so the effective cap becomes the flat
-- 2,500 kW service limit, while committed EV load in these scenarios runs 15-45 kW. The 0132
-- gate will therefore stop firing almost entirely and 'deferred_site_power_cap' will fall to
-- ~0. That is the correct answer, not a lost feature: a 2,500 kW service limit genuinely does
-- not bind at 45 kW of load, and the only reason it appeared to bind was the simulated battery
-- subtracting its own recharge draw from the fleet's budget. The constraint machinery is intact
-- and will bind again under Site Alpha (C8: 3,000 kW cap, 58 assets) where the load is real, or
-- the moment a real DR call or EMS-declared limit arrives.
--
-- PARTS B-E -- three cross-run reads in the energy path, the same defect class 0134 closed for
-- ottoq_solar_output and ottoq_weather_snapshots. Found by census, not by symptom:
--   * ottoq_l2_propose_bess reads ottoq_energy_commands filtered ONLY by depot_id, and it is
--     called from ottoq_decide_tick, so it is decision-affecting. Its tie-break is
--     `ORDER BY issued_at DESC, tick_seq DESC NULLS LAST, setpoint_kw DESC`, which silently
--     prefers the HIGHEST setpoint among every run sharing that issued_at/tick_seq. The
--     ottoq-demo-metronome cron creates runs on this same depot every minute, so a neighbouring
--     run can win that pick. It takes no p_sim_run_id parameter, so the run id is threaded
--     through the p_context jsonb it already parses (it reads p_context->>'now_ts' today) --
--     no signature change, no call-site contract break.
--     NOT the wall-clock hazard it first appeared to be: v_now defaults to now() only when the
--     caller omits now_ts, and ottoq_decide_tick does supply it, as v_clock -- the sim clock.
--     The default is left in place; it is unreachable on the only live path.
--   * ottoq_energy_orchestrate reads ottoq_dr_calls with no run filter AND no tie-break beyond
--     required_load_cap_kw ASC -- two calls at the same cap were heap order.
--   * ottoq_agent_board reads ottoq_energy_commands depot-wide for its 'bess_plan' display
--     field. Display-only (zero SQL callers; invoked over HTTP), fixed for totality.
-- All three use the 0020/0124 zero-uuid idiom so production rows (NULL run) keep matching a NULL
-- run, and all three gain a deterministic last-resort key per 0062/0063.
--
-- DELIBERATELY NOT DONE HERE, each recorded in db/checks/0056 with its evidence:
--   * depots.service_max_kw is NULL on 2 of 4 depots -- and LEAST() ignores NULLs, so those
--     depots run with NO cap at all and the 0132 gate is skipped entirely. They are precisely
--     the two feed_mode='external' depots a real site controller would feed. Filling them
--     requires their real utility service limits, which we do not have. Guessing a service
--     contract is exactly the class of invention this build forbids.
--   * The 19,993 existing refusals are unauditable: committed_kw_before / committed_kw_after are
--     NULL on every one of them.
--   * Rule EN.001 (grid capacity ceiling) and the 0132 gate are two independent power ceilings
--     that disagree -- the shield allowed an assignment with "headroom 1585.2 kW" that the gate
--     then refused. Reconciling them is a decision, not a patch.
--   * ottoq_energy_commands has RLS disabled while anon holds SELECT.
--
-- Pre-image pins, read live 2026-08-31 (each anchor asserted at exactly 1 occurrence):
--   public.ottoq_effective_charge_cap_kw  e3ff89e115d998972e0eeeed74eb2c43
--   public.ottoq_l2_propose_bess          a1e6bc36cd9fa714ea8fed8d75d38468
--   public.ottoq_energy_orchestrate       bd2ab36815e2d211d8b36c4e3b6c884e
--   public.ottoq_agent_board              33b52f4a8ebcac17a77da848551f3ded
--   public.ottoq_decide_tick              eb95bb65155eda720aff1af77ad2d210

CREATE FUNCTION pg_temp.ottoq_0136_patch(p_ns text, p_fn text, p_md5 text,
                                         p_old text, p_new text, p_expect int)
RETURNS void LANGUAGE plpgsql AS $helper$
DECLARE v_oid oid; v_src text; v_cnt int;
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = p_ns AND p.proname = p_fn AND p.prokind = 'f';
  v_src := pg_get_functiondef(v_oid);
  IF p_md5 IS NOT NULL AND md5(v_src) <> p_md5 THEN
    RAISE EXCEPTION '0136 abort: %.% drifted (md5 %)', p_ns, p_fn, md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, p_old, ''))) / length(p_old);
  IF v_cnt <> p_expect THEN
    RAISE EXCEPTION '0136 abort: %.% anchor found % times, expected %', p_ns, p_fn, v_cnt, p_expect;
  END IF;
  EXECUTE replace(v_src, p_old, p_new);
  IF pg_get_functiondef(v_oid) NOT LIKE '%/* 0136%' THEN
    RAISE EXCEPTION '0136 abort: %.% patch did not survive', p_ns, p_fn;
  END IF;
  RAISE NOTICE '0136: %.% patched.', p_ns, p_fn;
END
$helper$;

-- Part A pin assert. The rewrite below is a whole-body replacement, so the pin is checked here.
DO $pinA$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_effective_charge_cap_kw' AND p.prokind = 'f';
  IF v_md5 <> 'e3ff89e115d998972e0eeeed74eb2c43' THEN
    RAISE EXCEPTION '0136 abort: ottoq_effective_charge_cap_kw drifted (md5 %)', v_md5;
  END IF;
END
$pinA$;

CREATE OR REPLACE FUNCTION public.ottoq_effective_charge_cap_kw(
  p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz)
RETURNS numeric
LANGUAGE sql STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  /* 0136: THE SITE POWER LIMIT IS AN INPUT. The second term used to be
     ottoq_active_charge_cap_kw(), i.e. the cap OTTO-Q itself emitted and the twin executed --
     a closed loop in which the scheduler obeyed its own simulated battery. It is now the
     lowest externally-declared load cap in force: the utility service contract, further
     reduced by any active demand-response call. Run-scoped by the 0020/0124 zero-uuid idiom
     so production rows (NULL run) keep matching a NULL run, and tie-broken on dr_call_id per
     0062/0063 so two calls at the same cap cannot be decided by heap order.
     NULL still means "no cap" and skips the 0132 gate -- see db/checks/0056, which records the
     two depots where service_max_kw is NULL and the gate is therefore absent. */
  SELECT LEAST(
           (SELECT d.service_max_kw FROM public.depots d WHERE d.id = p_depot_id),
           (SELECT c.required_load_cap_kw
              FROM public.ottoq_dr_calls c
             WHERE c.depot_id = p_depot_id
               AND c.call_status IN ('active','issued')
               AND c.expires_at > p_sim_clock
               AND COALESCE(c.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                 = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
             ORDER BY c.required_load_cap_kw ASC, c.dr_call_id
             LIMIT 1)
         );
$fn$;

DO $apply$
BEGIN
  -- B. The decide-path BESS proposer stops reading other runs' setpoints.
  PERFORM pg_temp.ottoq_0136_patch(
    'public', 'ottoq_l2_propose_bess', 'a1e6bc36cd9fa714ea8fed8d75d38468',
    '    FROM ottoq_energy_commands' || chr(10) ||
    '   WHERE depot_id = p_depot_id' || chr(10) ||
    '     AND command_type = ''bess_setpoint_kw''',
    '    FROM ottoq_energy_commands' || chr(10) ||
    '   WHERE COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)' || chr(10) ||
    '       = COALESCE(NULLIF(p_context->>''sim_run_id'','''')::uuid,' || chr(10) ||
    '                  ''00000000-0000-0000-0000-000000000000''::uuid)  /* 0136 */' || chr(10) ||
    '     AND depot_id = p_depot_id' || chr(10) ||
    '     AND command_type = ''bess_setpoint_kw''',
    1);

  -- C. ...and the decide path supplies the run id it needs to do that.
  PERFORM pg_temp.ottoq_0136_patch(
    'public', 'ottoq_decide_tick', 'eb95bb65155eda720aff1af77ad2d210',
    'jsonb_build_object(''depot_id'',v_depot,''now_ts'',v_clock,',
    'jsonb_build_object(''depot_id'',v_depot,''now_ts'',v_clock,''sim_run_id'',p_sim_run_id,  /* 0136 */',
    1);

  -- D. The demand-response read is run-scoped and totally ordered.
  PERFORM pg_temp.ottoq_0136_patch(
    'public', 'ottoq_energy_orchestrate', 'bd2ab36815e2d211d8b36c4e3b6c884e',
    '  SELECT required_load_cap_kw INTO v_dr_cap FROM ottoq_dr_calls' || chr(10) ||
    '   WHERE depot_id = p_depot_id AND call_status IN (''active'',''issued'') AND expires_at > p_sim_clock' || chr(10) ||
    '   ORDER BY required_load_cap_kw ASC LIMIT 1;',
    '  SELECT required_load_cap_kw INTO v_dr_cap FROM ottoq_dr_calls' || chr(10) ||
    '   WHERE COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)' || chr(10) ||
    '       = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)  /* 0136 */' || chr(10) ||
    '     AND depot_id = p_depot_id AND call_status IN (''active'',''issued'') AND expires_at > p_sim_clock' || chr(10) ||
    '   ORDER BY required_load_cap_kw ASC, dr_call_id LIMIT 1;',
    1);

  -- E. Display-only totality: the agent board stops showing another run's battery plan.
  PERFORM pg_temp.ottoq_0136_patch(
    'public', 'ottoq_agent_board', '33b52f4a8ebcac17a77da848551f3ded',
    '      ''bess_plan'', (SELECT reason FROM ottoq_energy_commands' || chr(10) ||
    '          WHERE depot_id = v_depot AND command_type=''bess_setpoint_kw''' || chr(10) ||
    '          ORDER BY issued_at DESC LIMIT 1),',
    '      ''bess_plan'', (SELECT reason FROM ottoq_energy_commands' || chr(10) ||
    '          WHERE COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)' || chr(10) ||
    '              = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)  /* 0136 */' || chr(10) ||
    '            AND depot_id = v_depot AND command_type=''bess_setpoint_kw''' || chr(10) ||
    '          ORDER BY issued_at DESC, tick_seq DESC NULLS LAST, command_id DESC LIMIT 1),',
    1);

  RAISE NOTICE '0136 applied: the site limit is an input; three cross-run energy reads closed.';
END
$apply$;

-- Post-condition: five functions carry the marker; the decide path no longer reaches the
-- twin-derived cap; and the function that produced it is still present and untouched, because
-- the twin still models its battery BELOW the publication boundary.
DO $verify$
DECLARE v_n int; v_src text;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind = 'f'
     AND pg_get_functiondef(p.oid) LIKE '%/* 0136%';
  IF v_n <> 5 THEN RAISE EXCEPTION '0136 abort: % functions carry the marker, expected 5', v_n; END IF;

  /* Strip /* */ comments before testing: the new body DOCUMENTS what the second term used to
     be, so a bare LIKE cannot tell a comment from a call. Test the code, not the prose. */
  SELECT regexp_replace(pg_get_functiondef(p.oid), '/\*.*?\*/', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_effective_charge_cap_kw';
  IF v_src LIKE '%ottoq_active_charge_cap_kw%' THEN
    RAISE EXCEPTION '0136 abort: the decide path still CALLS the twin-derived cap';
  END IF;
  IF v_src NOT LIKE '%ottoq_dr_calls%' OR v_src NOT LIKE '%service_max_kw%' THEN
    RAISE EXCEPTION '0136 abort: the cap lost one of its two declared inputs';
  END IF;

  -- The producer stays: the twin keeps a battery, it just no longer constrains the scheduler.
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'ottoq_active_charge_cap_kw';
  IF NOT FOUND THEN RAISE EXCEPTION '0136 abort: ottoq_active_charge_cap_kw was deleted, not demoted'; END IF;

  -- No live reader of ottoq_energy_commands may remain unscoped.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind = 'f'
     AND p.proname NOT LIKE '%backup%'
     AND pg_get_functiondef(p.oid) LIKE '%ottoq_energy_commands%'
     AND pg_get_functiondef(p.oid) NOT LIKE '%sim_run_id%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0136 abort: % reader(s) of ottoq_energy_commands still lack run scoping', v_n;
  END IF;

  RAISE NOTICE '0136 verified: cap is an input, producer retained, no unscoped energy_commands reader.';
END
$verify$;
