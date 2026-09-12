-- migration-version: PENDING
-- migration-name: 0261_the_policy_is_what_proposes_the_kernel_disposes
-- ===========================================================================
-- 0261  THE POLICY IS WHAT PROPOSES; THE KERNEL DISPOSES  (Phase 1 / D2: the A/B pair)
-- ===========================================================================
-- probe:          db/checks/0145 (ottoq_ab_runs has one policy, one seed, no writer),
--                 db/checks/0146 (the baselines do not pay the shield), 0230 (the
--                 outcome scorer, "the measurement half only"), V1_DEMO_PLAN Phase 1,
--                 task #105.
-- forces_recert:  FALSE -- asserted, not assumed. The one certified-path function this
--                 touches, ottoq_sim_decide_and_dispatch, is changed by SPLICE, not by
--                 retyping: the live definition is cut at two unique markers and the
--                 old proposer block is wrapped in `IF v_seat = 0 THEN ... ELSE <baseline>
--                 END IF`. A1 proves the splice by REVERSING it -- removing the inserted
--                 text from the new definition must yield the pinned old definition byte
--                 for byte -- so seat 0, which is every run that has ever existed,
--                 executes the same statements it executed before. A2 proves no run has
--                 ever carried a seat and adds the CHECK that makes a seat run-scoped by
--                 construction, so a certification arm can never inherit one. A6 pins
--                 ottoq_decide_tick, ottoq_determinism_pair, ottoq_l2_optimize_assignments
--                 and ottoq.ottoq_world_fingerprint by md5. Round 41 is the measurement
--                 that confirms the classification, exactly as round 40 is for 0259/0260.
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT OR SCHEDULED. pg_stat_activity is the
-- only authority for in-flight; cron.job (r<NN>_* one-shot rows) for scheduled.
--
-- DRY RUN 2026-09-12 21:28 UTC, before apply, on a local PostgreSQL 16 loaded with the
-- LIVE column shapes of the sixteen tables this file reads (pulled from the catalog the
-- same hour, not from db/baseline, which predates G11's sim_clock_at and 0236's tick_seq):
-- all five functions and all four DO blocks compile with check_function_bodies on;
-- ottoq_ab_arm_atoms (a SQL-language body, so every column it names is resolved at
-- CREATE) and ottoq_ab_write_score ran end to end on a synthetic arm and wrote a row
-- with the intended NULLs; the splice block ran against a stand-in carrying the three
-- live markers, A1's reversal held, and the spliced function executed both the seat-0
-- path and the seat-1 path (the FIFO proposer wrote one proposal for one gate vehicle).
-- What a dry run cannot see: the live body's markers (P0 pins its md5; uniqueness was
-- measured live: 1/1/1), and A4/A5, which need the twin. Those run at apply.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS BUILDS, AND WHY IT HAS THIS SHAPE
-- ---------------------------------------------------------------------------
--
-- V1_DEMO_PLAN's D2 -- "OTTO-Q vs FIFO vs greedy on the identical world. Same seed,
-- same depot, same shield; only the policy differs" -- has never been run, and
-- db/checks/0146 showed why it must not be run as the engine stands: the policy
-- branch in ottoq_sim_decide_and_dispatch routes 'fifo' and 'greedy' to
-- ottoq_fifo_tick / ottoq_greedy_tick, which evaluate no rules and (greedy) never
-- touch the calendar. A number from that comparison would carry a run ID and would
-- measure the cost of safety, not the value of intelligence.
--
-- Read the live engine and the seam is already there. OTTO-Q's own stall policy is
-- NOT inside the disposer: it is `ottoq_l2_optimize_assignments` (source
-- greedy_constrained), a PROPOSER that writes ottoq_external_proposals before
-- ottoq_decide_tick runs, and ottoq_decide_tick then reads the winning proposal
-- through ottoq_l2_external_proposal, evaluates the 29-rule L1 shield on it, books
-- through the calendar, emits the commands and the SDRs. So:
--
--     the POLICY is what proposes;  the KERNEL (disposer + shield + calendar) disposes.
--
-- A baseline policy is therefore a baseline PROPOSER, and nothing else moves:
--
--   seat 0  otto_q   reservation reopt + cuOpt gate + first refusal +
--                    greedy_constrained + service_priority      (the text as it is)
--   seat 1  fifo     one proposer: gate vehicles in ARRIVAL order, first free
--                    compatible plug in stall_code order, no type preference
--   seat 2  greedy   one proposer: most-depleted vehicle first, the fastest plug
--                    it can take (highest connector_max_kw), myopic
--
-- Held constant for every seat: ottoq_decide_tick (so the shield, the safe defaults,
-- the site power gate 0132, the calendar 0067, the SDR terminus), the deploy path,
-- the twin, the seed, the calibration priors, the scenario, the boot world. The
-- reservation-honour path (a vehicle arriving on a booking it already holds) is
-- kernel too and stays; the in-tick heuristic `ottoq_l2_propose_stall_assignment`
-- stays as the shared fallback for a vehicle no proposer covered, and the verdict
-- MEASURES how often it fired per arm (`stall_sources`) rather than pretending it
-- did not.
--
-- The seat is a run-scoped policy param, `proposer_seat`, read once per decide tick.
-- It is set only by ottoq_ab_pair, on arms it creates with run_by = 'ab_harness'. A
-- CHECK constraint forbids any other scope, so no global or depot row can ever hand a
-- certification arm a baseline proposer.
--
-- THE VERDICT IS INVERTED, as C5 says it must be. ottoq_determinism_pair passes when
-- the arms are identical. ottoq_ab_pair passes when the arms are identical ON THE
-- WORLD -- boot fingerprint and calibration priors byte-equal, both arms complete --
-- and reports what the policy changed: h_dec, h_cmd, h_bkg, h_prop are EXPECTED to
-- differ and are printed side by side; if two different seats produce the same h_dec
-- the outcome is 'indistinguishable', a finding, not a failure. And the rig calibrates
-- itself: a pair with the SAME seat on both arms is a determinism pair in all but name
-- and must come back byte-identical on every atom (A4 runs one on the grid fixture and
-- refuses to commit if it does not).
--
-- Every arm is scored by 0230's ottoq_ab_score_run (outcome-based, coverage first) and
-- written to ottoq_ab_runs by the writer that 0230 said would come "once this has been
-- run against real arms". With the shield held constant, the rule-based columns
-- (safety_violations, overrides_total) are comparable for the first time; the outcome
-- columns (energy_peak_kw, peak_demand_pct_of_cap, charge_sessions) were always so.
-- Columns this rig cannot define honestly stay NULL, never 0 (0230's zero rule).
--
-- ---------------------------------------------------------------------------
-- P. NOTHING IN FLIGHT. pg_stat_activity only; cron.job for scheduled.
-- ---------------------------------------------------------------------------
DO $P$
DECLARE v_jobs text; v_n int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0261 P: certification jobs are still scheduled (%) -- migrations wait for the round', v_jobs;
  END IF;
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_sim_advance_tick%'
          OR query ILIKE '%ottoq_ab_pair%');
  IF v_n > 0 THEN
    RAISE EXCEPTION '0261 P: % pair(s) or tick(s) in flight', v_n;
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0261 P: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0261 P: nothing scheduled, nothing in flight';
END $P$;

-- ---------------------------------------------------------------------------
-- 1. Snapshot before replacing, and pin the body this was written against.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0261_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_decide_and_dispatch';

DO $P0$
DECLARE v_md5 text;
BEGIN
  SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_decide_and_dispatch';
  IF v_md5 <> '50b598790334cd6e910ad90faee6da48' THEN
    RAISE EXCEPTION '0261 P0: ottoq_sim_decide_and_dispatch body is % (expected 50b598790334cd6e910ad90faee6da48); it was changed since this file was written -- re-derive the splice markers before applying', v_md5;
  END IF;
END $P0$;

-- ---------------------------------------------------------------------------
-- 2. The seat is run-scoped BY CONSTRUCTION. A certification arm cannot inherit
--    a baseline proposer from a global or depot row, because no such row can exist.
-- ---------------------------------------------------------------------------
ALTER TABLE public.ottoq_policy_params
  ADD CONSTRAINT ottoq_policy_params_proposer_seat_run_scoped
  CHECK (param_key <> 'proposer_seat' OR scope_type = 'run');

-- ---------------------------------------------------------------------------
-- 3. The baseline proposers. One function, two seats, the SAME physical stall
--    filter greedy_constrained uses (free, unreserved or expired, charger Available
--    with a fresh heartbeat, inlet-compatible) so a baseline never proposes a plug
--    OTTO-Q could not, and the same requested_kw arithmetic so the site power gate
--    and the shield see comparable requests. Only the ORDER differs -- which is the
--    policy.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_l2_propose_seat(
  p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz, p_seat integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_source text; v_n int := 0; v_veh RECORD;
  v_stall_id uuid; v_stall_type text; v_conn_max numeric;
  v_used uuid[] := ARRAY[]::uuid[];
BEGIN
  v_source := CASE p_seat WHEN 1 THEN 'fifo' WHEN 2 THEN 'greedy' END;
  IF v_source IS NULL THEN
    RAISE EXCEPTION 'ottoq_l2_propose_seat: seat % is not a baseline proposer (1 = fifo, 2 = greedy; seat 0 is OTTO-Q and never reaches this function)', p_seat;
  END IF;

  -- fresh start each tick, exactly as greedy_constrained does for its own rows
  DELETE FROM ottoq_external_proposals
   WHERE sim_run_id = p_sim_run_id AND source = v_source AND action_context = 'stall_assignment';

  FOR v_veh IN
    SELECT v.id, v.current_soc, v.target_soc, v.inlet_type, v.inlet_max_kw, v.fleet_operator_id,
           v.last_state_change
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate'
       AND v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 0.5
     ORDER BY
       -- seat 1, FIFO: the order the vehicles reached the gate. last_state_change is
       -- the sim-clock instant of the arrival transition (twin domain, run-stable).
       CASE WHEN p_seat = 1 THEN v.last_state_change END ASC NULLS FIRST,
       -- seat 2, greedy: the most depleted vehicle picks first.
       CASE WHEN p_seat = 2 THEN v.current_soc END ASC,
       v.id
  LOOP
    SELECT s.id, s.stall_type, s.connector_max_kw
      INTO v_stall_id, v_stall_type, v_conn_max
      FROM stalls s
      JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type IN ('dcfc','l2')
       AND s.current_vehicle_id IS NULL
       AND NOT (s.id = ANY(v_used))
       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_sim_clock)
       AND c.station_state = 'Available'
       AND c.last_heartbeat_at >= p_sim_clock - INTERVAL '90 seconds'
       AND ( v_veh.inlet_type IS NULL
          OR s.connector_type = v_veh.inlet_type
          OR (s.connector_type = 'Multi' AND v_veh.inlet_type = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
          OR (s.connector_type = 'NACS'  AND v_veh.inlet_type IN ('NACS','Tesla_Proprietary')) )
     ORDER BY
       -- seat 2, greedy: the fastest plug this vehicle can take, myopically.
       CASE WHEN p_seat = 2 THEN COALESCE(s.connector_max_kw, 0) END DESC NULLS LAST,
       -- seat 1, FIFO: the first free plug, no optimisation (ottoq_fifo_tick's rule,
       -- with the run-stable key 0067 taught the engine to use).
       s.stall_code ASC, s.id ASC
     LIMIT 1;

    IF v_stall_id IS NULL THEN CONTINUE; END IF;
    v_used := array_append(v_used, v_stall_id);

    INSERT INTO ottoq_external_proposals
      (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal, source, status, created_at, expires_at)
    VALUES (p_sim_run_id, p_depot_id, 'stall_assignment', 'vehicle', v_veh.id,
      jsonb_build_object('abstain', false, 'resolved_action_context', 'stall_assignment', 'verb', 'assign_stall',
        'vehicle_id', v_veh.id, 'stall_id', v_stall_id, 'stall_type', v_stall_type,
        'requested_kw', ROUND((LEAST(COALESCE(v_conn_max,50), COALESCE(v_veh.inlet_max_kw,250))
            * CASE WHEN COALESCE(v_conn_max,50) <= 50 THEN 1.0
                   WHEN v_veh.current_soc < 55 THEN 0.85 WHEN v_veh.current_soc < 75 THEN 0.55 ELSE 0.30 END)::numeric, 1),
        'l2_engine', v_source,
        'rationale', jsonb_build_object('soc', v_veh.current_soc, 'optimizer', v_source, 'inlet', v_veh.inlet_type,
                                        'seat', p_seat, 'arrived_at', v_veh.last_state_change)),
      v_source, 'pending', now(), now() + INTERVAL '120 seconds');
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_l2_propose_seat(uuid, uuid, timestamptz, integer) IS
  '0261. The baseline stall proposers for the A/B pair: seat 1 = fifo (arrival order, first free compatible plug), seat 2 = greedy (most depleted first, fastest plug). Same stall filter and requested_kw arithmetic as greedy_constrained; only the order differs. Called from ottoq_sim_decide_and_dispatch when the run-scoped policy param proposer_seat is non-zero; the disposer (ottoq_decide_tick, the shield, the calendar) is untouched.';

-- ---------------------------------------------------------------------------
-- 4. THE SPLICE. The live definition of ottoq_sim_decide_and_dispatch is cut at two
--    unique markers and the proposer block between them is wrapped. Nothing is
--    retyped. A1 reverses the splice and demands the pinned body back.
-- ---------------------------------------------------------------------------
DO $splice$
DECLARE
  v_def text; v_new text;
  v_a text; v_b text; v_d text; v_open text; v_else text;
  v_pos_a int; v_pos_b int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure);

  v_a := E'    BEGIN\n      PERFORM ottoq_reoptimize_reservation_book(p_sim_run_id, v_run.sim_clock_current);';
  v_b := E'    BEGIN PERFORM ottoq_service_priority_propose(p_sim_run_id); EXCEPTION WHEN OTHERS THEN NULL; END;\n';
  v_d := 'v_fire_hb timestamptz; v_hb_window int;';

  IF (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 THEN
    RAISE EXCEPTION '0261 splice: marker A is not unique in ottoq_sim_decide_and_dispatch'; END IF;
  IF (length(v_def) - length(replace(v_def, v_b, ''))) / length(v_b) <> 1 THEN
    RAISE EXCEPTION '0261 splice: marker B is not unique in ottoq_sim_decide_and_dispatch'; END IF;
  IF (length(v_def) - length(replace(v_def, v_d, ''))) / length(v_d) <> 1 THEN
    RAISE EXCEPTION '0261 splice: the DECLARE marker is not unique in ottoq_sim_decide_and_dispatch'; END IF;

  v_pos_a := strpos(v_def, v_a);
  v_pos_b := strpos(v_def, v_b) + length(v_b);
  IF v_pos_b <= v_pos_a THEN
    RAISE EXCEPTION '0261 splice: marker B precedes marker A'; END IF;

  v_open := E'    /* 0261: THE PROPOSER SEAT. Seat 0 -- the default, and every run that has ever\n'
         || E'       existed -- is the block below, untouched. A non-zero seat is set run-scoped\n'
         || E'       by ottoq_ab_pair only (CHECK ottoq_policy_params_proposer_seat_run_scoped);\n'
         || E'       it replaces OTTO-Q''s proposers with ONE baseline proposer and leaves the\n'
         || E'       disposer -- ottoq_decide_tick, the shield, the calendar -- exactly as it is.\n'
         || E'       The policy is what proposes; the kernel disposes. */\n'
         || E'    v_seat := COALESCE(public.ottoq_policy_get(p_sim_run_id, ''proposer_seat'', 0), 0)::int;\n'
         || E'    IF v_seat = 0 THEN\n';
  v_else := E'    ELSE\n'
         || E'      BEGIN PERFORM public.ottoq_l2_propose_seat(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current, v_seat);\n'
         || E'      EXCEPTION WHEN OTHERS THEN RAISE WARNING ''proposer seat % failed: %'', v_seat, SQLERRM; END;\n'
         || E'    END IF;\n';

  v_new := substr(v_def, 1, v_pos_a - 1)
        || v_open
        || substr(v_def, v_pos_a, v_pos_b - v_pos_a)
        || v_else
        || substr(v_def, v_pos_b);
  v_new := replace(v_new, v_d, v_d || ' v_seat int; /* 0261 */');

  EXECUTE v_new;

  -- A1. REVERSE THE SPLICE. Remove exactly what was inserted from the live definition
  --     and demand the pre-splice definition back, byte for byte.
  v_new := pg_get_functiondef('public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure);
  IF replace(replace(replace(v_new, v_open, ''), v_else, ''), v_d || ' v_seat int; /* 0261 */', v_d) <> v_def THEN
    RAISE EXCEPTION '0261 A1 FAILED: reversing the splice does not return the pre-splice definition';
  END IF;
  IF (length(v_new) - length(replace(v_new, 'ottoq_l2_propose_seat', ''))) / length('ottoq_l2_propose_seat') <> 1 THEN
    RAISE EXCEPTION '0261 A1 FAILED: the baseline call was inserted % times',
      (length(v_new) - length(replace(v_new, 'ottoq_l2_propose_seat', ''))) / length('ottoq_l2_propose_seat');
  END IF;
  RAISE NOTICE '0261 A1: splice reversed to the pinned body; seat 0 executes the pre-0261 statements';
END $splice$;

-- ---------------------------------------------------------------------------
-- 5. The atoms of one arm: the fourteen the certification pair hashes, copied
--    expression for expression (the pair's own text is untouched; A6 pins it), plus
--    what an A/B needs and a determinism pair does not -- the arrival stream, the end
--    state of the fleet, which proposer each enacted stall assignment came from, and
--    which rules refused.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_ab_arm_atoms(p_depot uuid, p_run uuid)
RETURNS jsonb
LANGUAGE sql
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  -- not STABLE: ottoq_boot_state_fingerprint is called exactly as the certification
  -- pair calls it, and a read-only wrapper must not be the thing that forbids it.
  SELECT jsonb_build_object(
    'run', p_run, 'ticks', r.tick_count, 'clock', r.sim_clock_current,
    'fp', r.payload->>'world_fingerprint',
    'endst', public.ottoq_boot_state_fingerprint(p_depot, p_run),
    'h_cmd', (SELECT md5(COALESCE(string_agg(
        issued_at::text||'|'||vehicle_id::text||'|'||command_type||'|'||COALESCE(payload->>'stall_id','-')||'|'||status||'|'||COALESCE(reason_code,'-'),
        E'\n' ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status, COALESCE(reason_code,'-')), ''))
      FROM ottoq_vehicle_commands c WHERE c.sim_run_id = p_run),
    'h_dec', (SELECT md5(COALESCE(string_agg(
        sim_clock::text||'|'||tick_seq::text||'|'||action_context||'|'||entity_id::text||'|'||outcome_status
        ||'|'||COALESCE(enacted_action->>'verb', proposed_action->>'verb','-')||'|'||COALESCE(proposed_action->>'stall_id','-'),
        E'\n' ORDER BY sim_clock, tick_seq, action_context, entity_id, outcome_status,
                      COALESCE(enacted_action->>'verb', proposed_action->>'verb','-'), COALESCE(proposed_action->>'stall_id','-')), ''))
      FROM ottoq_decisions d WHERE d.sim_run_id = p_run),
    'h_evt', (SELECT md5(COALESCE(string_agg(
        event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                              THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||COALESCE(e.sim_clock_at::text,'-'),
        E'\n' ORDER BY event_type,
                      CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                           THEN '-' ELSE COALESCE(entity_id::text,'-') END, e.sim_clock_at), ''))
      FROM ottoq_events e WHERE e.sim_run_id = p_run),
    'h_bkg', (SELECT md5(COALESCE(string_agg(
        lower(during)::text||'|'||upper(during)::text||'|'||vehicle_id::text||'|'||stall_id::text||'|'||purpose||'|'||state,
        E'\n' ORDER BY lower(during), upper(during), vehicle_id, stall_id, purpose, state), ''))
      FROM ottoq_stall_bookings k WHERE k.sim_run_id = p_run),
    'h_nrg', (SELECT md5(COALESCE(string_agg(
        COALESCE(c.tick_seq::text,'-')||'|'||c.command_type||'|'||COALESCE(c.source,'-')
        ||'|'||COALESCE(c.setpoint_kw::text,'-')||'|'||COALESCE(c.horizon_min::text,'-')
        ||'|'||to_char(c.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')
        ||'|'||COALESCE(c.reason::text,'-'),
        E'\n' ORDER BY c.tick_seq, c.command_type, COALESCE(c.source,'-'), c.setpoint_kw, c.horizon_min, c.issued_at, c.reason::text), ''))
      FROM ottoq_energy_commands c WHERE c.sim_run_id = p_run),
    'h_prop', public.ottoq_hash_proposals(p_run),
    'h_defr', public.ottoq_hash_deferrals(p_run),
    'h_rule', public.ottoq_hash_rule_evaluations(p_run),
    'h_rcl',  public.ottoq_hash_recall_decisions(p_run),
    'h_sdr',  public.ottoq_hash_sdrs(p_run),
    -- the arrival stream: (vehicle, sim instant) of every gate arrival. Identical
    -- across arms until the policies' deploy decisions diverge; reported, not judged.
    'h_arr', (SELECT md5(COALESCE(string_agg(e.entity_id::text||'|'||e.sim_clock_at::text, E'\n'
                                             ORDER BY e.sim_clock_at, e.entity_id), ''))
                FROM ottoq_events e
               WHERE e.sim_run_id = p_run AND e.event_type = 'vehicle.state_changed'
                 AND e.payload->'diff'->'current_state'->>'to' = 'arrived_at_gate'),
    'n_arrivals', (SELECT count(*) FROM ottoq_events e
                    WHERE e.sim_run_id = p_run AND e.event_type = 'vehicle.state_changed'
                      AND e.payload->'diff'->'current_state'->>'to' = 'arrived_at_gate'),
    -- where each ENACTED stall assignment came from. 'local_heuristic' is the in-tick
    -- fallback (ottoq_l2_propose_stall_assignment), shared by every seat; its share is
    -- how much of the arm the seat did NOT decide.
    'stall_sources', COALESCE((SELECT jsonb_object_agg(src, n) FROM (
        SELECT COALESCE(d.proposed_action->>'source', 'local_heuristic') AS src, count(*) AS n
          FROM ottoq_decisions d
         WHERE d.sim_run_id = p_run AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
         GROUP BY 1) q), '{}'::jsonb),
    'decisions', COALESCE((SELECT jsonb_object_agg(action_context||'/'||outcome_status, n) FROM (
        SELECT action_context, outcome_status, count(*) AS n
          FROM ottoq_decisions d WHERE d.sim_run_id = p_run GROUP BY 1,2) q), '{}'::jsonb),
    'blocked', COALESCE((SELECT jsonb_object_agg(rule_code, n) FROM (
        SELECT rule_code, count(*) AS n FROM ottoq_rule_evaluations x
         WHERE x.sim_run_id = p_run AND x.passed = false GROUP BY 1) q), '{}'::jsonb),
    'proposals', COALESCE((SELECT jsonb_object_agg(source, n) FROM (
        SELECT source, count(*) AS n FROM ottoq_external_proposals p
         WHERE p.sim_run_id = p_run GROUP BY 1) q), '{}'::jsonb),
    -- the fleet at the END of the arm, read before teardown resets it
    'end', jsonb_build_object(
      'fleet', (SELECT count(*) FROM vehicles v2
                 WHERE v2.home_depot_id = p_depot AND v2.category = 'autonomous'),
      'by_state', COALESCE((SELECT jsonb_object_agg(st, n) FROM (
          SELECT v.current_state::text AS st, count(*) AS n
            FROM vehicles v WHERE v.home_depot_id = p_depot AND v.category = 'autonomous'
           GROUP BY 1) s), '{}'::jsonb))
  )
  FROM ottoq_sim_runs r WHERE r.sim_run_id = p_run;
$fn$;

COMMENT ON FUNCTION public.ottoq_ab_arm_atoms(uuid, uuid) IS
  '0261. One A/B arm''s atoms: the fourteen ottoq_determinism_pair hashes (same expressions, the pair''s text untouched), plus h_arr (the arrival stream), stall_sources (which proposer each enacted stall assignment came from; local_heuristic is the shared in-tick fallback), blocked (rule codes that refused), proposals by source, and the fleet''s end state. STABLE, read-only.';

-- ---------------------------------------------------------------------------
-- 6. The writer 0230 deferred. One ottoq_ab_runs row per arm, every column from a
--    run-scoped source, NULL where this rig has no honest definition.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_ab_write_score(
  p_group uuid, p_run uuid, p_policy text, p_atoms jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  r ottoq_sim_runs%ROWTYPE; v_score jsonb; v_id uuid;
  v_dec int; v_enacted int; v_over int; v_lat numeric;
  v_viol int; v_crit int;
  v_deploys int; v_trips int; v_cycled int; v_turned int; v_median numeric;
  v_fleet int; v_ready int; v_ready_or_dep int; v_gate int;
  v_hours numeric; v_served int;
BEGIN
  SELECT * INTO r FROM ottoq_sim_runs WHERE sim_run_id = p_run;
  IF NOT FOUND THEN RAISE EXCEPTION 'ottoq_ab_write_score: run % not found', p_run; END IF;
  v_score := public.ottoq_ab_score_run(p_run);

  SELECT count(*), count(*) FILTER (WHERE outcome_status = 'enacted'),
         count(*) FILTER (WHERE outcome_status = 'overridden_to_default'),
         round(avg(total_latency_ms)::numeric, 2)
    INTO v_dec, v_enacted, v_over, v_lat
    FROM ottoq_decisions WHERE sim_run_id = p_run;

  -- With the shield held constant across arms these two are comparable; 0146's
  -- objection was to arms that never evaluate a rule, and no seat-0/1/2 arm is one.
  SELECT count(*) FILTER (WHERE NOT passed),
         count(*) FILTER (WHERE NOT passed AND severity = 'safety_critical')
    INTO v_viol, v_crit
    FROM ottoq_rule_evaluations WHERE sim_run_id = p_run;

  WITH sc AS (
    SELECT e.entity_id, e.sim_clock_at, e.payload->'diff'->'current_state'->>'to' AS st
      FROM ottoq_events e
     WHERE e.sim_run_id = p_run AND e.event_type = 'vehicle.state_changed'
       AND e.payload->'diff' ? 'current_state'
  ), arr AS (
    SELECT entity_id, min(sim_clock_at) AS t_arr FROM sc WHERE st = 'arrived_at_gate' GROUP BY 1
  ), rdy AS (
    SELECT s.entity_id, min(s.sim_clock_at) AS t_rdy
      FROM sc s JOIN arr a ON a.entity_id = s.entity_id AND s.sim_clock_at > a.t_arr
     WHERE s.st = 'staged_for_departure' GROUP BY 1
  )
  SELECT (SELECT count(*) FROM sc WHERE st = 'deployed' AND sim_clock_at > r.sim_clock_start),
         (SELECT count(*) FROM sc WHERE st = 'arrived_at_gate'),
         (SELECT count(*) FROM arr),
         (SELECT count(*) FROM rdy),
         (SELECT round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM (x.t_rdy - a.t_arr)) / 60.0))::numeric, 1)
            FROM rdy x JOIN arr a USING (entity_id))
    INTO v_deploys, v_trips, v_cycled, v_turned, v_median;

  v_fleet := COALESCE((p_atoms->'end'->>'fleet')::int, 0);
  v_ready := COALESCE((p_atoms->'end'->'by_state'->>'staged_for_departure')::int, 0);
  v_ready_or_dep := v_ready + COALESCE((p_atoms->'end'->'by_state'->>'deployed')::int, 0)
                  + COALESCE((p_atoms->'end'->'by_state'->>'en_route_to_deployment')::int, 0);
  v_gate := COALESCE((p_atoms->'end'->'by_state'->>'arrived_at_gate')::int, 0);
  v_hours := NULLIF((v_score->'outcome'->>'sim_hours')::numeric, 0);
  v_served := (v_score->'outcome'->>'vehicles_served')::int;

  INSERT INTO ottoq_ab_runs
    (ab_group_id, sim_run_id, seed, policy, scenario_code, ticks,
     decisions_total, enacted_total, deploys_total, fleet_ready_pct,
     safety_violations, safety_critical_violations, overrides_total, avg_decision_latency_ms,
     energy_peak_kw, charge_sessions, incidents_open, scored_at,
     productive_deploys, unsafe_deploys, vehicles_turned_around, gate_backlog,
     throughput_per_hr, peak_demand_pct_of_cap, trips_completed, vehicles_cycled,
     median_turnaround_min, ready_or_deployed_pct)
  VALUES
    (p_group, p_run, r.random_seed, p_policy, r.scenario_code, r.tick_count,
     v_dec, v_enacted, v_deploys,
     CASE WHEN v_fleet > 0 THEN round(100.0 * v_ready / v_fleet, 2) END,
     v_viol, v_crit, v_over, v_lat,
     (v_score->'safety'->>'peak_concurrent_kw')::numeric,
     (v_score->'outcome'->>'charge_sessions')::int,
     NULL,                                   -- incidents_open: no honest definition here
     now(),
     NULL, NULL,                             -- productive/unsafe deploys: not defined by this rig
     v_turned, v_gate,
     CASE WHEN v_hours IS NOT NULL THEN round(v_served / v_hours, 2) END,
     (v_score->'safety'->>'pct_of_cap')::numeric,
     v_trips, v_cycled, v_median,
     CASE WHEN v_fleet > 0 THEN round(100.0 * v_ready_or_dep / v_fleet, 2) END)
  RETURNING ab_run_id INTO v_id;
  RETURN v_id;
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_ab_write_score(uuid, uuid, text, jsonb) IS
  '0261. The ottoq_ab_runs writer 0230 deferred. One row per A/B arm: decisions/enacted/overrides and rule-based safety counts (comparable now that every seat pays the same shield), 0230''s outcome peak and pct_of_cap, deploys/trips/turnarounds from the run''s own state-change events, the fleet end state from the arm''s atoms. incidents_open, productive_deploys and unsafe_deploys stay NULL: this rig has no honest definition for them, and a NULL is not a zero.';

-- ---------------------------------------------------------------------------
-- 7. THE PAIR. ottoq_determinism_pair's boot, quiesce, prime and tick loop, with a
--    seat per arm, run_by = 'ab_harness' (so the certification matrix, Posture A and
--    the metronome never see these as certification arms), and the inverted verdict.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_ab_pair(
  p_seed bigint, p_ticks integer, p_scenario text, p_depot uuid, p_sim_start timestamptz,
  p_arm_budget_s integer, p_seat_a text, p_seat_b text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_arm int; v_run uuid; v_t0 timestamptz;
  v_clock timestamptz; v_status text; v_ticks int;
  v_boot jsonb; v_h jsonb; v_arms jsonb[] := '{}';
  v_seats text[]; v_codes int[]; v_group uuid;
  v_scen_depot uuid; v_complete boolean; v_world boolean; v_same boolean; v_differs boolean;
  v_outcome text; v_vstatus text; v_verdict jsonb; v_ab uuid;
BEGIN
  v_seats := ARRAY[p_seat_a, p_seat_b];
  v_codes := ARRAY[CASE p_seat_a WHEN 'otto_q' THEN 0 WHEN 'fifo' THEN 1 WHEN 'greedy' THEN 2 END,
                   CASE p_seat_b WHEN 'otto_q' THEN 0 WHEN 'fifo' THEN 1 WHEN 'greedy' THEN 2 END];
  IF v_codes[1] IS NULL OR v_codes[2] IS NULL THEN
    RAISE EXCEPTION 'ab_pair: seats are otto_q | fifo | greedy (got %, %)', p_seat_a, p_seat_b USING ERRCODE = 'P0001';
  END IF;

  -- 0175: the pair and the scenario must name the same world.
  SELECT s.depot_id INTO v_scen_depot FROM public.ottoq_scenarios s
   WHERE s.scenario_code = p_scenario AND s.status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ab_pair: no active scenario %', p_scenario USING ERRCODE = 'P0001';
  END IF;
  IF v_scen_depot IS DISTINCT FROM p_depot THEN
    RAISE EXCEPTION 'ab_pair: scenario % is bound to depot %, but the pair was told to run depot %.',
      p_scenario, COALESCE(v_scen_depot::text, '(none)'), p_depot USING ERRCODE = 'P0001';
  END IF;

  -- The comparison key IS the group id: the same seed, horizon, scenario, depot,
  -- clock and seats always land in the same ottoq_ab_runs group, so a re-run adds
  -- rows a check can compare rather than a group nobody can find.
  v_group := md5('ab|'||p_seed||'|'||p_ticks||'|'||p_scenario||'|'||p_depot
                 ||'|'||to_char(p_sim_start AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS')  -- never ::text: it reads the session TimeZone
                 ||'|'||p_seat_a||'|'||p_seat_b)::uuid;

  FOR v_arm IN 1..2 LOOP
    PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);
    v_run := twin.ottoq_sim_start_run(p_scenario, p_sim_start, 60, p_seed, 'ab_harness');

    -- The deterministic core alone, as a certification arm runs it (0152), plus the
    -- dial-writing orchestrator agent quiesced (0112) -- it is not exempt for
    -- ab_harness the way it is for cert_harness -- plus the seat.
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_run, 'cuopt_propose_enabled', 0, '0261_ab_quiesce'),
           ('run', v_run, 'cuopt_first_refusal_max_defers', 0, '0261_ab_quiesce'),
           ('run', v_run, 'orchestrator_agent_enabled', 0, '0261_ab_quiesce'),
           ('run', v_run, 'proposer_seat', v_codes[v_arm], '0261_ab_seat')
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
      SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by;
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload, '{}'::jsonb)
                  || jsonb_build_object('proposer_seat', v_seats[v_arm], 'ab_group_id', v_group, 'ab_arm', v_arm)
     WHERE sim_run_id = v_run;

    BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, p_sim_start, 0.70);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'ab_pair arm % prime failed: %', v_arm, SQLERRM; END;

    v_boot := public.ottoq_boot_state_fingerprint(p_depot, v_run);

    v_t0 := clock_timestamp();
    LOOP
      SELECT sim_clock_current, status, tick_count INTO v_clock, v_status, v_ticks
        FROM ottoq_sim_runs WHERE sim_run_id = v_run;
      EXIT WHEN v_status <> 'running' OR v_ticks >= p_ticks;
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) >= p_arm_budget_s;
      PERFORM public.ottoq_sim_advance_tick(v_run);
    END LOOP;

    v_h := public.ottoq_ab_arm_atoms(p_depot, v_run)
        || jsonb_build_object('seat', v_seats[v_arm], 'boot', v_boot,
                              'h_cal', v_boot->'calibration'->>'h',
                              'complete', (SELECT tick_count >= p_ticks FROM ottoq_sim_runs WHERE sim_run_id = v_run),
                              'wall_s', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0))::numeric, 1));
    v_ab := public.ottoq_ab_write_score(v_group, v_run, v_seats[v_arm], v_h);
    v_h := v_h || jsonb_build_object('ab_run_id', v_ab);
    v_arms := v_arms || v_h;

    PERFORM public.ottoq_sim_stop_and_reset(v_run, 'ab_arm_complete');
  END LOOP;

  v_complete := COALESCE((v_arms[1]->>'complete')::boolean, false)
            AND COALESCE((v_arms[2]->>'complete')::boolean, false);
  -- IDENTICAL ON THE WORLD: the same boot image and the same priors. Enforced.
  v_world := (v_arms[1]->'boot') = (v_arms[2]->'boot')
         AND (v_arms[1]->>'h_cal') = (v_arms[2]->>'h_cal');
  v_same := (v_codes[1] = v_codes[2]);
  -- DIFFERENT ONLY BY WHAT THE POLICY DECIDED: the decision stream is the atom that
  -- names it. (A same-seat pair must agree on all fourteen; that is the self-test.)
  v_differs := NOT (
        (v_arms[1]->>'fp')    = (v_arms[2]->>'fp')
    AND (v_arms[1]->>'h_cmd') = (v_arms[2]->>'h_cmd')
    AND (v_arms[1]->>'h_dec') = (v_arms[2]->>'h_dec')
    AND (v_arms[1]->>'h_evt') = (v_arms[2]->>'h_evt')
    AND (v_arms[1]->>'h_bkg') = (v_arms[2]->>'h_bkg')
    AND (v_arms[1]->>'h_nrg') = (v_arms[2]->>'h_nrg')
    AND (v_arms[1]->>'h_prop') = (v_arms[2]->>'h_prop')
    AND (v_arms[1]->>'h_defr') = (v_arms[2]->>'h_defr')
    AND (v_arms[1]->>'h_cal')  = (v_arms[2]->>'h_cal')
    AND (v_arms[1]->>'h_rule') = (v_arms[2]->>'h_rule')
    AND (v_arms[1]->>'h_rcl')  = (v_arms[2]->>'h_rcl')
    AND (v_arms[1]->>'h_sdr')  = (v_arms[2]->>'h_sdr')
    AND (v_arms[1]->>'ticks')  = (v_arms[2]->>'ticks')
    AND (v_arms[1]->'endst')   = (v_arms[2]->'endst'));

  v_outcome := CASE
    WHEN NOT v_complete THEN 'inconclusive'
    WHEN NOT v_world    THEN 'invalid'            -- the arms did not boot from one world
    WHEN v_same AND NOT v_differs THEN 'passed'   -- self-test: same seat, byte-identical
    WHEN v_same AND v_differs     THEN 'failed'   -- self-test: same seat, diverged
    WHEN v_differs                THEN 'compared'
    ELSE                               'indistinguishable' END;
  -- validation_status on an ab_harness arm means THE INSTRUMENT WAS VALID, never
  -- that a policy won; the CHECK on the column allows only these four words.
  v_vstatus := CASE v_outcome WHEN 'inconclusive' THEN 'inconclusive'
                              WHEN 'invalid' THEN 'failed' WHEN 'failed' THEN 'failed'
                              ELSE 'passed' END;

  v_verdict := jsonb_build_object(
    'kind', 'ab_pair', 'outcome', v_outcome, 'complete', v_complete,
    'world_identical', v_world, 'same_seat', v_same, 'differs', v_differs,
    'seed', p_seed, 'ticks', p_ticks, 'scenario', p_scenario, 'depot', p_depot,
    'sim_start', p_sim_start, 'ab_group_id', v_group,
    'seat_a', p_seat_a, 'seat_b', p_seat_b,
    'moved', (SELECT COALESCE(jsonb_agg(k ORDER BY k), '[]'::jsonb) FROM unnest(ARRAY['fp','h_cmd','h_dec','h_evt','h_bkg','h_nrg','h_prop','h_defr','h_cal','h_rule','h_rcl','h_sdr','ticks','endst','h_arr']) k
               WHERE (v_arms[1]->k) IS DISTINCT FROM (v_arms[2]->k)),
    'arm_a', v_arms[1] - 'boot', 'arm_b', v_arms[2] - 'boot');

  UPDATE ottoq_sim_runs
     SET validation_status = v_vstatus, validation_notes = v_verdict::text
   WHERE sim_run_id IN ((v_arms[1]->>'run')::uuid, (v_arms[2]->>'run')::uuid);

  RETURN v_verdict;
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_ab_pair(bigint, integer, text, uuid, timestamptz, integer, text, text) IS
  '0261. The A/B pair: ottoq_determinism_pair''s boot, quiesce, prime and tick loop with a proposer seat per arm (otto_q | fifo | greedy), run_by = ab_harness, the orchestrator agent quiesced, both arms scored into ottoq_ab_runs under one deterministic ab_group_id. Verdict inverted: passes (valid) when the arms are identical on the world -- boot image and priors byte-equal, both complete -- and reports which atoms the policy moved. A same-seat pair is the self-test and must be byte-identical.';

-- ---------------------------------------------------------------------------
-- 8. Grants. Mutating rig functions: service_role and the owner only (G2).
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.ottoq_l2_propose_seat(uuid, uuid, timestamptz, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_ab_write_score(uuid, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_ab_pair(bigint, integer, text, uuid, timestamptz, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_l2_propose_seat(uuid, uuid, timestamptz, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_ab_write_score(uuid, uuid, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_ab_pair(bigint, integer, text, uuid, timestamptz, integer, text, text) TO service_role;
REVOKE ALL ON FUNCTION public.ottoq_ab_arm_atoms(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_ab_arm_atoms(uuid, uuid) TO service_role, authenticated;

-- ---------------------------------------------------------------------------
-- 9. Lineage.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
('0261_the_policy_is_what_proposes_the_kernel_disposes', false,
 'Phase 1 / D2. A run-scoped proposer seat (0 otto_q, 1 fifo, 2 greedy) read once per decide tick '
 'in ottoq_sim_decide_and_dispatch; seat 0 is the pre-0261 block verbatim (A1 reverses the splice '
 'to the pinned body). ottoq_l2_propose_seat (the baseline proposers), ottoq_ab_arm_atoms, '
 'ottoq_ab_write_score (the ottoq_ab_runs writer) and ottoq_ab_pair (the inverted-verdict pair, '
 'run_by ab_harness) are new objects. No certification arm can carry a seat (CHECK, A2). '
 'forces_recert FALSE: asserted by A1/A2/A6; round 41 measures it.');

-- ---------------------------------------------------------------------------
-- ASSERTIONS. A1 ran inside the splice. The rest here.
-- ---------------------------------------------------------------------------
DO $A$
DECLARE v_n int; v_md5 text; v_r jsonb; v_a jsonb; v_b jsonb; v_msg text;
BEGIN
  -- A2. No run has ever carried a seat, and no non-run scope can.
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params WHERE param_key = 'proposer_seat';
  IF v_n <> 0 THEN RAISE EXCEPTION '0261 A2 FAILED: % proposer_seat rows exist before the rig ran', v_n; END IF;
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('global', '00000000-0000-0000-0000-000000000000', 'proposer_seat', 1, '0261_A2_probe');
    RAISE EXCEPTION '0261 A2 FAILED: a global proposer_seat row was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;  -- the CHECK refused it, which is the point
  END;

  -- A3. The seat function refuses seat 0 and unknown seats.
  BEGIN
    PERFORM public.ottoq_l2_propose_seat('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', now(), 0);
    RAISE EXCEPTION '0261 A3 FAILED: seat 0 reached the baseline proposer';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg LIKE '0261 A3 FAILED%' THEN RAISE; END IF;
  END;

  -- A4. THE SELF-TEST. Same seat on both arms, on the grid fixture (seconds, 0153):
  --     the rig must come back byte-identical on every atom, or it is not an
  --     instrument and nothing it says about two DIFFERENT seats can be trusted.
  v_r := public.ottoq_ab_pair(239001, 6, 'grid_smoke', 'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid,
                              '2026-09-01 02:00:00+00'::timestamptz, 300, 'otto_q', 'otto_q');
  IF v_r->>'outcome' <> 'passed' THEN
    RAISE EXCEPTION '0261 A4 FAILED: same-seat grid pair is % (moved: %)', v_r->>'outcome', v_r->'moved';
  END IF;
  RAISE NOTICE '0261 A4: same-seat grid pair byte-identical (group %)', v_r->>'ab_group_id';

  -- A5. THE FIRST COMPARISON. otto_q vs fifo on the grid: valid on the world, and
  --     arm B never heard OTTO-Q's proposers.
  v_r := public.ottoq_ab_pair(239001, 6, 'grid_smoke', 'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid,
                              '2026-09-01 02:00:00+00'::timestamptz, 300, 'otto_q', 'fifo');
  IF v_r->>'outcome' NOT IN ('compared', 'indistinguishable') THEN
    RAISE EXCEPTION '0261 A5 FAILED: otto_q vs fifo grid pair is % (moved: %)', v_r->>'outcome', v_r->'moved';
  END IF;
  v_a := v_r->'arm_a'; v_b := v_r->'arm_b';
  IF COALESCE((v_b->'proposals'->>'greedy_constrained')::int, 0) <> 0
     OR COALESCE((v_b->'proposals'->>'ottoq_service_priority')::int, 0) <> 0 THEN
    RAISE EXCEPTION '0261 A5 FAILED: the fifo arm heard OTTO-Q proposers: %', v_b->'proposals';
  END IF;
  IF COALESCE((v_b->'stall_sources'->>'greedy_constrained')::int, 0) <> 0 THEN
    RAISE EXCEPTION '0261 A5 FAILED: the fifo arm enacted a greedy_constrained proposal: %', v_b->'stall_sources';
  END IF;
  RAISE NOTICE '0261 A5: otto_q vs fifo on the grid: outcome %, moved %, arm_a sources %, arm_b sources %, arm_b proposals %',
    v_r->>'outcome', v_r->'moved', v_a->'stall_sources', v_b->'stall_sources', v_b->'proposals';

  -- A6. Pins. The disposer, the certification pair, OTTO-Q's own proposer and the
  --     world fingerprint are the bodies this was written against.
  SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_decide_tick';
  IF v_md5 <> '47602bef21aebadce6dbd8a3b692ca8a' THEN RAISE EXCEPTION '0261 A6 FAILED: ottoq_decide_tick moved to %', v_md5; END IF;
  SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_determinism_pair';
  IF v_md5 <> '8a35b8c874fed154cc216140faec0274' THEN RAISE EXCEPTION '0261 A6 FAILED: ottoq_determinism_pair moved to %', v_md5; END IF;
  SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_l2_optimize_assignments';
  IF v_md5 <> '321a3ae4739557a0a67f8e4688d12a70' THEN RAISE EXCEPTION '0261 A6 FAILED: ottoq_l2_optimize_assignments moved to %', v_md5; END IF;
  SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_world_fingerprint';
  IF v_md5 <> '945fa4b9e7bfd0d1c027fd92dc85fa06' THEN RAISE EXCEPTION '0261 A6 FAILED: ottoq_world_fingerprint moved to %', v_md5; END IF;

  -- A7. The certification matrix cannot see an ab_harness arm; anon cannot run the rig.
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE run_by = 'ab_harness';
  IF v_n <> 4 THEN RAISE EXCEPTION '0261 A7 FAILED: expected 4 ab_harness arms from A4+A5, found %', v_n; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE run_by = 'cert_harness'
              AND payload ? 'proposer_seat') THEN
    RAISE EXCEPTION '0261 A7 FAILED: a certification arm carries a proposer_seat stamp';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_ab_pair(bigint, integer, text, uuid, timestamptz, integer, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION '0261 A7 FAILED: anon can execute ottoq_ab_pair'; END IF;
  IF has_function_privilege('anon', 'public.ottoq_l2_propose_seat(uuid, uuid, timestamptz, integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '0261 A7 FAILED: anon can execute ottoq_l2_propose_seat'; END IF;
  IF NOT has_function_privilege('service_role', 'public.ottoq_ab_pair(bigint, integer, text, uuid, timestamptz, integer, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION '0261 A7 FAILED: service_role cannot execute ottoq_ab_pair'; END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_ab_runs WHERE policy = 'fifo';
  IF v_n < 1 THEN RAISE EXCEPTION '0261 A7 FAILED: no fifo row reached ottoq_ab_runs'; END IF;
  RAISE NOTICE '0261 A7: 4 ab_harness arms, no cert arm stamped, grants as intended, ottoq_ab_runs has its first non-otto_q row';
END $A$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0261_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_sim_decide_and_dispatch', 'ottoq_l2_propose_seat', 'ottoq_ab_arm_atoms',
                     'ottoq_ab_write_score', 'ottoq_ab_pair');

SELECT p.proname, md5(p.prosrc) AS body_md5_post, length(p.prosrc) AS len_post
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_sim_decide_and_dispatch', 'ottoq_l2_propose_seat', 'ottoq_ab_arm_atoms',
                     'ottoq_ab_write_score', 'ottoq_ab_pair')
 ORDER BY 1;
