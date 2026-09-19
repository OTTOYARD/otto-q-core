-- migration-version: 20260919000001
-- migration-name:    the_charge_stall_was_reserved_before_any_solver_could_see_it
--
-- 0339  CP-SAT WAS MADE THE PRIMARY PROPOSER AND HAS PROPOSED NOTHING SINCE,
--       BECAUSE THE CHARGE STALL IS RESERVED BEFORE THE VEHICLE ARRIVES.
--
-- Measured 2026-09-19 against this engine, and the number is zero:
--
--   * 0335 (2026-09-16) moved `forward_lex` to rank 0 -- the primary
--     deterministic assignment proposer named in CLAUDE.md 2.5.
--   * public.ottoq_proposer_fire_log since then: 75 forward_lex fires,
--     ALL status='empty', effective_source NULL, n_submitted 0. The last
--     forward_lex proposal of any kind was 2026-09-14 09:23:34 UTC, two days
--     BEFORE it became primary.
--   * In 74 of those 75 fires `n_in_serviceable_state` equals
--     `fire->>'n_vehicles_held'` EXACTLY -- 11/11, 13/13, 16/16, 18/18, 22/22.
--     Every serviceable vehicle was already holding a charge place, so
--     `_plannable_in` dropped the entire population and the module returned
--     "no plannable vehicles in frame".
--   * Same window: source='cuopt' produced 2,578 proposals and 92 enactments.
--     100% of enacted assignment proposals came from the fallback and none
--     from the declared primary.
--
-- THE CAUSE IS NOT IN THE SOLVER, THE FRAME, OR THE HOLD. It is here.
-- ottoq.ottoq_sim_prearrival_contracts BACKSTOP 2 reserves a dcfc/l2 stall for
-- every `en_route_to_depot` vehicle with an open charge atom, ~40 minutes before
-- it arrives, by `ORDER BY` a CASE on urgency and SoC. By the time the vehicle
-- reaches `arrived_at_gate` -- the ONLY state the proposer treats as serviceable
-- and the only state ottoq_decide_tick's assignment cursors read -- the scarcest
-- resource on the site is already allocated. So:
--
--   * the proposer frame marks it holds_charge_place and skips it (0265/0287);
--   * ottoq_cuopt_first_refusal_arm declines to open a seat for it, by the SAME
--     dcfc/l2 predicate -- so 0337's "first refusal before greedy dispatch"
--     window can never catch it, because the reservation predates the window;
--   * the L1 shield never probes the choice, because no decision row is made.
--
-- This is the second time this function has been caught pre-empting the decide
-- path. Its own BACKSTOP 2 comment records the first: the staging `ORDER BY` was
-- ASC, "handed every inbound car a perimeter stall before it had even arrived",
-- and "beat decide_tick's correct temp-first picker every time". That was fixed
-- for STAGING and left in place for CHARGE.
--
-- WHAT THIS FILE DOES, and deliberately no more. It adds one run-scoped policy
-- key, `prearrival_charge_yields_to_solver`, DEFAULT 0 = today's behaviour
-- exactly. When a run sets it to 1, BACKSTOP 2 skips the dcfc/l2 branch and
-- falls through to the staging branch it already has: the arriving vehicle still
-- gets a place to wait -- physical necessity, not an optimisation -- and the
-- charge assignment is left to the gate, where the proposer seat, the shield
-- probe and the `arrived_at_gate` cursor all already exist. Nothing is deleted;
-- the greedy contract remains the fallback it should always have been.
--
-- It composes with 0287 rather than working around it: ottoq_reserve_stall on a
-- STAGING stall yields reserved_stall_type='staging', which 0287 already taught
-- the frame not to count as a charge place. So a yielded vehicle is plannable by
-- construction, with no change to the frame, the hold, the selector or the
-- disposer.
--
-- ottoq_agentic_arm grants the key on an armed Twin run, and
-- ottoq_agentic_arming raises its attestation from six required keys to seven,
-- so a run cannot read "armed" while the primary proposer is being starved.
-- Production sessions and certification arms are untouched: neither calls
-- ottoq_agentic_arm, so both keep the 0 default.
--
-- forces_recert: TRUE. Which stall a vehicle is assigned, and by whom, changes
-- on any run that sets the key.

DO $preflight$
DECLARE v_jobs text; v_pairs int; v_runs int; v_src text;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0339 P-: certification jobs are scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN RAISE EXCEPTION '0339 P-: % certification pair(s) are active', v_pairs; END IF;

  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_runs > 0 THEN RAISE EXCEPTION '0339 P-: % Twin run(s) are active', v_runs; END IF;

  -- P1: the three functions this file patches must exist at the shapes it anchors on.
  IF to_regprocedure('ottoq.ottoq_sim_prearrival_contracts(uuid,timestamptz)') IS NULL
     OR to_regprocedure('public.ottoq_agentic_arm(uuid,text)') IS NULL
     OR to_regprocedure('public.ottoq_agentic_arming(uuid)') IS NULL THEN
    RAISE EXCEPTION '0339 P1: a patch target is missing';
  END IF;

  -- P2: the key must not already exist, so this file cannot silently re-point a
  -- dial some other migration owns.
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
              WHERE param_key='prearrival_charge_yields_to_solver') THEN
    RAISE EXCEPTION '0339 P2: prearrival_charge_yields_to_solver already exists';
  END IF;

  -- P3: the charge branch this file gates must be present exactly once, and the
  -- staging fallback it falls through to must be present too. If either anchor
  -- has moved, the diagnosis above was written against a different function.
  SELECT p.prosrc INTO v_src FROM pg_proc p
   WHERE p.oid='ottoq.ottoq_sim_prearrival_contracts(uuid,timestamptz)'::regprocedure;
  IF (length(v_src)-length(replace(v_src, E'    IF v_has_charge THEN\n', '')))
       / length(E'    IF v_has_charge THEN\n') <> 1 THEN
    RAISE EXCEPTION '0339 P3a: the charge-branch anchor is not present exactly once';
  END IF;
  IF v_src NOT LIKE '%AND s.stall_type = ''staging''%'
     OR v_src NOT LIKE '%THE PERIMETER IS A LONG HOLD, NOT A FRONT DOOR.%' THEN
    RAISE EXCEPTION '0339 P3b: the staging fallback anchor is absent';
  END IF;
END $preflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0339-pre', 'function', n.nspname,
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('ottoq.ottoq_sim_prearrival_contracts(uuid,timestamptz)'::regprocedure,
                 'public.ottoq_agentic_arm(uuid,text)'::regprocedure,
                 'public.ottoq_agentic_arming(uuid)'::regprocedure);

INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, affects)
VALUES
  ('prearrival_charge_yields_to_solver',
   'When 1, ottoq_sim_prearrival_contracts does NOT pre-reserve a dcfc/l2 stall for an en_route_to_depot vehicle; it reserves staging only and leaves the charge assignment to the gate, where the proposer seat, the L1 shield probe and the arrived_at_gate cursor exist. 0 keeps the pre-2026-09-19 greedy pre-arrival contract.',
   0, 0, 1,
   'ottoq.ottoq_sim_prearrival_contracts; ottoq_agentic_arm; ottoq_agentic_arming');

-- ── 1. the pre-arrival contract learns to yield ──────────────────────────────
DO $contract$
DECLARE d text; old text; new text; n int;
BEGIN
  d := pg_get_functiondef('ottoq.ottoq_sim_prearrival_contracts(uuid,timestamptz)'::regprocedure);

  old := E'  v_has_charge boolean; v_ttl int; v_eta_min numeric;\n';
  new := E'  v_has_charge boolean; v_ttl int; v_eta_min numeric;\n'
      || E'  --: 0339. 0 = pre-reserve the charge stall from en_route (the original\n'
      || E'  --: behaviour); 1 = reserve staging only and let the gate decide.\n'
      || E'  v_yield_to_solver int := 0;\n';
  n := (length(d)-length(replace(d,old,'')))/length(old);
  IF n = 1 THEN
    d := replace(d, old, new);
  ELSIF d NOT LIKE '%v_yield_to_solver int := 0;%' THEN
    RAISE EXCEPTION '0339 C1: declare anchor occurs % times', n;
  END IF;

  old := E'  IF v_depot IS NULL THEN RETURN 0; END IF;\n';
  new := E'  IF v_depot IS NULL THEN RETURN 0; END IF;\n'
      || E'\n'
      || E'  --: 0339. Read once per call, at RUN scope, so a single beat cannot see\n'
      || E'  --: the dial change halfway through its own loop.\n'
      || E'  v_yield_to_solver := COALESCE(public.ottoq_policy_get(\n'
      || E'    p_sim_run_id, ''prearrival_charge_yields_to_solver'', 0), 0)::int;\n';
  n := (length(d)-length(replace(d,old,'')))/length(old);
  IF n = 1 THEN
    d := replace(d, old, new);
  ELSIF d NOT LIKE '%prearrival_charge_yields_to_solver%' THEN
    RAISE EXCEPTION '0339 C2: depot-guard anchor occurs % times', n;
  END IF;

  old := E'    IF v_has_charge THEN\n';
  new := E'    --: 0339. THE GATE. When the run yields, v_stall stays NULL here and\n'
      || E'    --: the staging fallback below takes over -- the vehicle still gets a\n'
      || E'    --: place to wait, and the charge assignment reaches the proposer,\n'
      || E'    --: the shield and the disposer instead of being settled by this\n'
      || E'    --: ORDER BY forty minutes before the vehicle arrives.\n'
      || E'    IF v_has_charge AND v_yield_to_solver = 0 THEN\n';
  n := (length(d)-length(replace(d,old,'')))/length(old);
  IF n = 1 THEN
    d := replace(d, old, new);
  ELSIF d NOT LIKE '%IF v_has_charge AND v_yield_to_solver = 0 THEN%' THEN
    RAISE EXCEPTION '0339 C3: charge-branch anchor occurs % times', n;
  END IF;

  EXECUTE d;
END $contract$;

-- ── 2. an armed Twin run grants the key ──────────────────────────────────────
DO $arm$
DECLARE d text; old text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_agentic_arm(uuid,text)'::regprocedure);
  old := E'      (''cuopt_first_refusal_max_defers'', 6::numeric)\n';
  n := (length(d)-length(replace(d,old,'')))/length(old);
  IF n = 1 THEN
    EXECUTE replace(d, old,
      E'      (''cuopt_first_refusal_max_defers'', 6::numeric),\n'
   || E'      (''prearrival_charge_yields_to_solver'', 1::numeric)\n');
  ELSIF d NOT LIKE '%(''prearrival_charge_yields_to_solver'', 1::numeric)%' THEN
    RAISE EXCEPTION '0339 R1: arm VALUES anchor occurs % times', n;
  END IF;
END $arm$;

-- ── 3. the attestation counts seven, not six ─────────────────────────────────
DO $arming$
DECLARE d text; old text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_agentic_arming(uuid)'::regprocedure);
  old := E'      (''cuopt_first_refusal_max_defers'', 1::numeric,\n'
      || E'       ''0152 set the global tier to 0; without a run row nothing is ever armed'')\n';
  n := (length(d)-length(replace(d,old,'')))/length(old);
  IF n = 1 THEN
    EXECUTE replace(d, old,
      E'      (''cuopt_first_refusal_max_defers'', 1::numeric,\n'
   || E'       ''0152 set the global tier to 0; without a run row nothing is ever armed''),\n'
   || E'      (''prearrival_charge_yields_to_solver'', 1::numeric,\n'
   || E'       ''0339: the charge stall is not reserved before the primary proposer can see it'')\n');
  ELSIF d NOT LIKE '%prearrival_charge_yields_to_solver%' THEN
    RAISE EXCEPTION '0339 A0: arming VALUES anchor occurs % times', n;
  END IF;
END $arming$;

DO $assertions$
DECLARE d text; v_arming jsonb; v_run uuid;
BEGIN
  -- A1. The gate is in the contract, and it gates the CHARGE branch only: the
  -- staging fallback must still be unconditional, or a yielding run would leave
  -- arriving vehicles with nowhere to wait.
  SELECT p.prosrc INTO d FROM pg_proc p
   WHERE p.oid='ottoq.ottoq_sim_prearrival_contracts(uuid,timestamptz)'::regprocedure;
  IF d NOT LIKE '%IF v_has_charge AND v_yield_to_solver = 0 THEN%' THEN
    RAISE EXCEPTION '0339 A1a: the charge branch is not gated';
  END IF;
  IF d NOT LIKE '%IF v_stall IS NULL THEN%' OR d NOT LIKE '%AND s.stall_type = ''staging''%' THEN
    RAISE EXCEPTION '0339 A1b: the staging fallback is no longer reachable';
  END IF;
  IF strpos(d,'prearrival_charge_yields_to_solver') > strpos(d,'IF v_has_charge AND v_yield_to_solver') THEN
    RAISE EXCEPTION '0339 A1c: the dial is read after it is spent';
  END IF;

  -- A2. DEFAULT 0 IS THE WHOLE SAFETY ARGUMENT, so assert it three ways: the
  -- catalog row, the variable initialiser, and an actual resolution for a run
  -- that was never armed.
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key='prearrival_charge_yields_to_solver'
                    AND default_value=0 AND min_value=0 AND max_value=1) THEN
    RAISE EXCEPTION '0339 A2a: the catalog row is not default 0 / range 0..1';
  END IF;
  IF d NOT LIKE '%v_yield_to_solver int := 0;%' THEN
    RAISE EXCEPTION '0339 A2b: the local default is not 0';
  END IF;
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE COALESCE(r.run_by,'') = 'cert_harness' ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NOT NULL
     AND COALESCE(public.ottoq_policy_get(v_run,'prearrival_charge_yields_to_solver',0),0) <> 0 THEN
    RAISE EXCEPTION '0339 A2c: a certification run resolves the key non-zero';
  END IF;

  -- A3. The arm grants it and the attestation requires it, so "armed" and
  -- "the primary proposer can see a candidate" cannot disagree.
  SELECT p.prosrc INTO d FROM pg_proc p WHERE p.oid='public.ottoq_agentic_arm(uuid,text)'::regprocedure;
  IF d NOT LIKE '%(''prearrival_charge_yields_to_solver'', 1::numeric)%' THEN
    RAISE EXCEPTION '0339 A3a: the arm does not grant the key';
  END IF;
  SELECT p.prosrc INTO d FROM pg_proc p WHERE p.oid='public.ottoq_agentic_arming(uuid)'::regprocedure;
  IF d NOT LIKE '%prearrival_charge_yields_to_solver%' THEN
    RAISE EXCEPTION '0339 A3b: the attestation does not require the key';
  END IF;

  -- A4. The attestation must actually COUNT seven now. Evaluated, not read: a
  -- key added to the VALUES list but unreachable would pass A3b and fail here.
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    v_arming := public.ottoq_agentic_arming(v_run);
    IF (v_arming->>'required')::int <> 7 THEN
      RAISE EXCEPTION '0339 A4: the attestation requires % keys, expected 7',
        v_arming->>'required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_arming->'keys') k
                    WHERE k->>'param_key' = 'prearrival_charge_yields_to_solver') THEN
      RAISE EXCEPTION '0339 A4b: the new key is not in the attestation keys array';
    END IF;
  END IF;
END $assertions$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0339_the_charge_stall_was_reserved_before_any_solver_could_see_it', true,
  'The pre-arrival contract can now yield the dcfc/l2 reservation so the primary CP-SAT proposer receives a non-empty instance at the gate. Which stall a vehicle gets, and which layer chose it, changes on any run that sets prearrival_charge_yields_to_solver=1 -- which ottoq_agentic_arm now does. Recertification required.',
  now())
ON CONFLICT(name) DO NOTHING;
