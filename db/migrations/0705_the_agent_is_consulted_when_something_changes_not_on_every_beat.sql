-- migration-version: PENDING
-- migration-name:    the_agent_is_consulted_when_something_changes_not_on_every_beat
--
-- 0705  **The agent is consulted when something changes, not on every beat.** A deterministic wake test decides, per
--        agent pass, whether anything the agent could act on has changed since it last answered: a charger fault or
--        repair, the charge line outgrowing the open chargers (or relieving), a vehicle emergency, a car newly past its
--        owner's contract wait, a demand-response call starting or ending, a new per-vehicle scout finding (0704), or a
--        heartbeat (30 sim-minutes by default). When nothing has, the edge function (v29) runs the solver on the
--        standing objective without a model call. SHIPPED IN SHADOW: with agent_wake_enabled at its default of 0 the
--        agent is consulted on every pass exactly as before, and every pass records what the test would have decided.
--        (Study 2026-10-13: AG-1 cadence, AV-1 value, the architecture verdict; db/checks/0442.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Measured 2026-10-13 at the twin depot (read-only; the study's agent lanes, adversarially verified):
--
--   (a) The agent is consulted on every even metronome beat while it owns the solver chain (ottoq_cuopt_refresh ->
--       net.http_post, one pass in flight at a time; ottoq_agent_chain_claim). On d3938f36 that was one pass per 8.5
--       ticks, each answering a board 6.4 ticks old, at a mean 37.8 s of model time (p95 68 s) against a solver that
--       answers in 17 ms.
--   (b) Since 2026-10-08, 14 of 766 passes changed engine state. The solver objective was readiness_first on 1,436 of
--       1,437 answered passes; 346 of 416 charge orders were the kernel's own order. The model is asked the same
--       question about the same depot many times in a row and gives the same answer.
--   (c) The hosted endpoint refused 23-50% of attempts on 2026-10-07 to 10-09 and answered 42% of 10-08's passes from
--       the fallback model at temperature 1.0. Every unnecessary call is load on the one thing that fails.
--
--   So the agent becomes event-driven, which is how the study's external evidence says a single coordinator earns its
--   place (consult it when its judgement can matter; let deterministic machinery run in between), and the solver keeps
--   its own cadence, because CP-SAT is called through the agent's pass while the agent owns the chain.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   1. public.ottoq_agent_wake(run) -- VOLATILE (it first runs the run's scouts so their findings are fresh; 0704).
--      Computes a fingerprint of what the agent can act on and compares it with the fingerprint stored on the run's
--      last CONSULTED pass that got an answer (ottoq_agent_pass_evidence, 0703; a fallback or failed pass does not
--      count, so an outage keeps the agent waking). Reasons, any of which wakes it:
--        first_consult, heartbeat (sim minutes since the last answer >= agent_wake_heartbeat_sim_min, default 30),
--        contention_onset / contention_relief (cars in the kernel's charge line vs dcfc/l2 stalls free by pointer and
--        not Faulted), charger_fault / charger_restored (Faulted OCPP chargers at the depot), emergency (cars at the
--        depot in tow_requested / emergency_staged), contract_wait (kernel-line cars past their owner's active contract
--        max_queue_wait_minutes), dr_change (an active or issued ottoq_dr_calls row for the run starts or ends),
--        scout_finding (more ACTIONABLE 0704 findings than at the last answer: stranded_open_must_do,
--        departed_below_target, legacy_task_residue -- not the departure findings about cars already gone, which on
--        busy_day arrive every couple of ticks and would wake the agent on almost every beat).
--      Returns {wake, would_wake, gate, reasons, fingerprint, last_consult, standing_objective, scan}. With the gate
--      off (agent_wake_enabled < 1, the default) wake is always true and would_wake says what the gate would have
--      done -- SHADOW MODE, so the saving is measured on real passes before anyone turns it on.
--      Total: any error returns wake = true with the error, so a broken wake test can only cost a model call.
--   2. Catalog rows agent_wake_enabled (0/1, default 0) and agent_wake_heartbeat_sim_min (5-240, default 30), both
--      agent_writable = false (rule 10: the agent does not decide how often it is asked).
--
--   NOT changed: when the agent's edge function is fired, the claim, the charge-order door, the solver chain, the
--   decide path. Turning the gate on is a run-scoped dial a person sets (or a later certified change makes default).
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   A new function called only by the agent's edge function, which is quiesced in certification arms; it writes only
--   0704's evidence table (through the scan). Two catalog rows whose defaults leave every run as it was.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Leave agent_wake_enabled at 0 (or set it to 0 on a run). Edge v29 treats a missing or failing wake function as
--   wake = true.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0705 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0704_every_car_has_a_deterministic_scout_and_the_agent_reads_what_they_find') THEN
    RAISE EXCEPTION '0705 P1: 0704 is not classified; apply in order';
  END IF;
  IF to_regprocedure('public.ottoq_agent_wake(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0705 P1: ottoq_agent_wake already exists';
  END IF;
  IF to_regclass('public.ottoq_agent_pass_evidence') IS NULL OR to_regclass('public.ottoq_dr_calls') IS NULL
     OR to_regclass('public.ottoq_ocpp_chargers') IS NULL
     OR to_regprocedure('public.ottoq_vehicle_scouts_scan(uuid)') IS NULL THEN
    RAISE EXCEPTION '0705 P1: a table or function the wake test reads is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
              WHERE param_key IN ('agent_wake_enabled', 'agent_wake_heartbeat_sim_min')) THEN
    RAISE EXCEPTION '0705 P1: a wake dial is already in the catalog';
  END IF;
END $premises$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_wake(p_sim_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_zero     constant uuid := '00000000-0000-0000-0000-000000000000';
  v_run      record;
  v_gate_on  boolean;
  v_hb_min   numeric;
  v_scan     jsonb;
  v_fp       jsonb;
  v_last     record;
  v_prev     jsonb;
  v_reasons  text[] := ARRAY[]::text[];
  v_waiting  integer; v_open integer; v_faulted integer; v_emerg integer; v_over integer; v_dr boolean; v_found bigint;
  v_min_ago  numeric;
  v_objective text;
BEGIN
  SELECT r.sim_run_id, r.depot_id, r.sim_clock_current, r.tick_count
    INTO v_run FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL OR v_run.depot_id IS NULL OR v_run.sim_clock_current IS NULL THEN
    RETURN jsonb_build_object('wake', true, 'would_wake', true, 'reasons', jsonb_build_array('run_unknown'));
  END IF;
  v_gate_on := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_wake_enabled', 0), 0) >= 1;
  v_hb_min  := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_wake_heartbeat_sim_min', 30), 30), 5);

  --: the scouts first, so a finding they make now can wake the agent now (0704; total, never raises)
  v_scan := public.ottoq_vehicle_scouts_scan(p_sim_run_id);

  --: the fingerprint: what the agent could act on, counted cheaply and deterministically
  SELECT count(*) INTO v_waiting
    FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
  SELECT count(*) INTO v_open
    FROM public.stalls s
    LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = v_run.depot_id AND s.stall_type::text IN ('dcfc', 'l2')
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL AND s.status::text = 'available'
     AND COALESCE(c.station_state, '') <> 'Faulted';
  SELECT count(*) INTO v_faulted
    FROM public.ottoq_ocpp_chargers c
   WHERE c.depot_id = v_run.depot_id AND c.station_state = 'Faulted' AND c.decommissioned_at IS NULL;
  SELECT count(*) INTO v_emerg
    FROM public.vehicles v
   WHERE v.home_depot_id = v_run.depot_id AND v.current_state::text IN ('tow_requested', 'emergency_staged');
  SELECT count(*) INTO v_over
    FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current) k
    JOIN public.vehicles v ON v.id = k.vehicle_id
    CROSS JOIN LATERAL (
      SELECT s.max_queue_wait_minutes FROM public.ottoq_fleet_operator_slas s
       WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status = 'active'
         AND s.effective_from <= v_run.sim_clock_current
         AND (s.effective_until IS NULL OR s.effective_until > v_run.sim_clock_current)
       ORDER BY s.version DESC LIMIT 1) sla
   WHERE sla.max_queue_wait_minutes IS NOT NULL AND k.wait_min > sla.max_queue_wait_minutes;
  SELECT EXISTS (SELECT 1 FROM public.ottoq_dr_calls c
                  WHERE c.depot_id = v_run.depot_id AND c.call_status IN ('active', 'issued')
                    AND c.expires_at > v_run.sim_clock_current
                    AND COALESCE(c.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero))
    INTO v_dr;
  --: only findings the agent can do something about in the depot NOW. A departure finding (interval_due_departure,
  --: same_trigger_rebound) is about a car already gone -- on busy_day there is one every couple of ticks, and waking
  --: the agent for each would wake it on almost every beat. contract_wait_breach is already counted by v_over.
  SELECT count(*) INTO v_found FROM public.ottoq_vehicle_scout_findings f
   WHERE f.sim_run_id = p_sim_run_id
     AND f.scout IN ('stranded_open_must_do', 'departed_below_target', 'legacy_task_residue');

  v_fp := jsonb_build_object('line_waiting', v_waiting, 'open_chargers', v_open,
                             'line_exceeds_open_chargers', v_waiting > v_open,
                             'faulted_chargers', v_faulted, 'emergencies', v_emerg,
                             'over_contract_wait', v_over, 'dr_active', v_dr, 'scout_actionable', v_found);

  --: the last pass that consulted the model AND got an answer; a fallback or failed pass does not reset the clock
  SELECT e.pass_id, e.recorded_tick, e.sim_clock, e.wake -> 'fingerprint' AS fp,
         e.answer -> 'solver' ->> 'objective' AS objective
    INTO v_last
    FROM public.ottoq_agent_pass_evidence e
   WHERE e.sim_run_id = p_sim_run_id AND e.consulted AND e.outcome_class NOT IN ('fallback', 'failed')
   ORDER BY e.pass_id DESC LIMIT 1;

  IF v_last.pass_id IS NULL THEN
    v_reasons := array_append(v_reasons, 'first_consult'::text);
  ELSE
    v_prev := COALESCE(v_last.fp, '{}'::jsonb);
    v_min_ago := round(extract(epoch FROM (v_run.sim_clock_current - v_last.sim_clock)) / 60.0, 1);
    IF v_last.sim_clock IS NULL OR v_min_ago >= v_hb_min THEN v_reasons := array_append(v_reasons, 'heartbeat'::text); END IF;
    IF (v_prev ->> 'line_exceeds_open_chargers') IS DISTINCT FROM (v_fp ->> 'line_exceeds_open_chargers') THEN
      v_reasons := array_append(v_reasons, CASE WHEN v_waiting > v_open THEN 'contention_onset' ELSE 'contention_relief' END::text);
    END IF;
    IF v_faulted > COALESCE((v_prev ->> 'faulted_chargers')::int, 0) THEN v_reasons := array_append(v_reasons, 'charger_fault'::text);
    ELSIF v_faulted < COALESCE((v_prev ->> 'faulted_chargers')::int, 0) THEN v_reasons := array_append(v_reasons, 'charger_restored'::text);
    END IF;
    IF v_emerg > COALESCE((v_prev ->> 'emergencies')::int, 0) THEN v_reasons := array_append(v_reasons, 'emergency'::text); END IF;
    IF v_over > COALESCE((v_prev ->> 'over_contract_wait')::int, 0) THEN v_reasons := array_append(v_reasons, 'contract_wait'::text); END IF;
    IF (v_prev ->> 'dr_active') IS DISTINCT FROM (v_fp ->> 'dr_active') THEN v_reasons := array_append(v_reasons, 'dr_change'::text); END IF;
    IF v_found > COALESCE((v_prev ->> 'scout_actionable')::bigint, 0) THEN v_reasons := array_append(v_reasons, 'scout_finding'::text); END IF;
  END IF;

  v_objective := CASE WHEN v_last.objective IN ('readiness_first', 'throughput_first', 'energy_balanced')
                      THEN v_last.objective ELSE 'readiness_first' END;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'wake',        (NOT v_gate_on) OR cardinality(v_reasons) > 0,
    'would_wake',  cardinality(v_reasons) > 0,
    'gate',        CASE WHEN v_gate_on THEN 'on' ELSE 'shadow' END,
    'reasons',     to_jsonb(v_reasons),
    'fingerprint', v_fp,
    'heartbeat_sim_min', v_hb_min,
    'last_consult', CASE WHEN v_last.pass_id IS NOT NULL THEN
                      jsonb_build_object('pass_id', v_last.pass_id, 'tick', v_last.recorded_tick,
                                         'sim_clock', v_last.sim_clock, 'sim_min_ago', v_min_ago) END,
    'standing_objective', v_objective,
    'tick', v_run.tick_count,
    'scan', jsonb_build_object('ok', v_scan -> 'ok', 'new', v_scan -> 'new', 'ms', v_scan -> 'ms')));
EXCEPTION WHEN OTHERS THEN
  --: total: a broken wake test can only cost a model call, never skip one silently
  RETURN jsonb_build_object('wake', true, 'would_wake', true, 'reasons', jsonb_build_array('wake_error'),
                            'error', SQLERRM);
END $fn$;

COMMENT ON FUNCTION public.ottoq_agent_wake(uuid) IS
'0705. Should the orchestrator agent be consulted on this pass? Runs the 0704 scouts, fingerprints what the agent can act on (charge line vs open chargers, faulted chargers, emergencies, cars past their contract wait, a DR call, scout findings) and compares it with the fingerprint on the run''s last answered consult, plus a sim-time heartbeat. agent_wake_enabled = 0 (default) is SHADOW: wake is always true and would_wake records the decision. Total: an error returns wake = true.';

REVOKE ALL ON FUNCTION public.ottoq_agent_wake(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_wake(uuid) TO service_role;

INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('agent_wake_enabled',
        '0705: when >= 1 the orchestrator agent is consulted only when public.ottoq_agent_wake finds a reason (a charger '
        'fault or repair, contention onset or relief, an emergency, a car newly past its contract wait, a DR call '
        'starting or ending, a new scout finding, or the heartbeat); on other passes edge v29 runs the solver on the '
        'standing objective without a model call. 0 (the default) is shadow: every pass consults, as before, and records '
        'what the gate would have decided. Set by a person, never by an agent (rule 10).',
        0, 0, 1, 'edge:ottoq-orchestrator-agent (v29) via ottoq_agent_wake (0705)', false),
       ('agent_wake_heartbeat_sim_min',
        '0705: with the wake gate on, the longest the agent goes unconsulted, in sim minutes, when nothing else changes.',
        30, 5, 240, 'ottoq_agent_wake (0705)', false);

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v$
DECLARE v_r jsonb;
BEGIN
  --: V1 an unknown run wakes (never silently skips)
  v_r := public.ottoq_agent_wake('00000000-0000-0000-0000-0000000000ff');
  IF NOT COALESCE((v_r ->> 'wake')::boolean, false) THEN
    RAISE EXCEPTION '0705 V1 FAILED: an unknown run did not wake: %', v_r;
  END IF;
  --: V2 the dials default to the old behaviour and the agent may not write them
  IF (SELECT default_value FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_wake_enabled') <> 0
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                 WHERE param_key IN ('agent_wake_enabled','agent_wake_heartbeat_sim_min') AND agent_writable) THEN
    RAISE EXCEPTION '0705 V2 FAILED: the wake dials are not as written';
  END IF;
  --: V3 the public key and a signed-in caller cannot call it
  IF has_function_privilege('anon', 'public.ottoq_agent_wake(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_agent_wake(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_agent_wake(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0705 V3 FAILED: grants are not as written';
  END IF;
  RAISE NOTICE '0705 V1-V3 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0705_the_agent_is_consulted_when_something_changes_not_on_every_beat', false, false,
  'Study 2026-10-13 (agent cadence; db/checks/0442): public.ottoq_agent_wake, called only by the agent''s edge function '
  '(quiesced in certification arms), writes only 0704''s evidence through the scan; two catalog rows whose defaults keep '
  'every run as it was (shadow mode). FALSE/FALSE.',
  now());

COMMIT;
