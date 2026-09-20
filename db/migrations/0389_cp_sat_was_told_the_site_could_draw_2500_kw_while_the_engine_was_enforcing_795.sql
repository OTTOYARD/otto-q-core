-- migration-version: 20260920194102
-- migration-name:    cp_sat_was_told_the_site_could_draw_2500_kw_while_the_engine_was_enforcing_795
--
-- 0389  THE SITE POWER CAP CP-SAT PLANS AGAINST IS A CONSTANT IN TWO PLACES, AND THE
--       ENGINE'S OWN LIVE CAP IS A THIRD NUMBER NEITHER OF THEM READS.
--
-- `forces_recert` **FALSE**. One new read-only function and one new read-only assertion.
-- No existing object is altered, no schema changes, nothing on the tick path, no data
-- written. Safe to apply while a run is live, and one is
-- (`1efeb1cd-f9b6-4515-8e61-2e5a04121112`). Nothing calls the new function until the
-- companion edge-function and bridge changes land, so applying this file alone cannot
-- change a single proposal.
--
-- ══ 1. WHAT WAS MEASURED ═══════════════════════════════════════════════════
--
-- Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), live run
-- `1efeb1cd-f9b6-4515-8e61-2e5a04121112` (busy_day, seed 101959, sim clock 01:24 UTC).
--
-- The CP-SAT proposer takes a `site` descriptor. `solvers/cpsat/model.py:773` spends
-- `power_cap_kw_hard` as a genuine CP-SAT **cumulative resource capacity**:
--
--     m.AddCumulative(power_intervals, power_demands, site["power_cap_kw_hard"])
--
-- so that number is not documentation, it is the constraint. `power_soft_target_kw` is
-- the threshold the second objective term penalises excursions above (`model.py:776`).
-- Both arrive from outside the database, from two places, and both are constants:
--
--   edge-functions/_shared/cpsat_agent_chain.ts   power_cap_kw_hard 2500, soft 1620
--   bridge/sites/nashville-flagship.json          power_cap_kw_hard 2500, soft 1620
--
-- **The engine was enforcing 795 kW at the same moment.** The cuOpt edge function reads
-- `public.ottoq_active_charge_cap_kw(run, depot, clock)` before it proposes
-- (`ottoq-cuopt-propose/index.ts:382`), and the live fire record for this run at
-- 19:31:10 carries:
--
--   energy.cap_kw        **795**
--   energy.proposed_kw   1568.4
--   energy.over_cap_kw   773.4
--
-- That function's own comment names what the value is: *"this value is the site power cap
-- the decide path plans against."* It is the MPC-issued `charge_cap_kw` energy command,
-- with a horizon, so it moves during a run.
--
-- **So the two proposers are handed different worlds.** cuOpt is told 795. CP-SAT is told
-- 2500 — 3.1x the cap actually in force — and 1620 as a soft target that is itself
-- 2.0x the hard cap the engine will enforce. A CP-SAT plan is therefore free to be
-- feasible in its own model and over the site cap in fact.
--
-- ══ 2. WHAT THIS IS NOT ════════════════════════════════════════════════════
--
-- **Not an observed violation.** No enacted CP-SAT plan is known to have breached the live
-- cap, and this file does not claim one: 2500 is permissive, and a permissive cap only
-- bites on a frame big enough to reach it. On the run measured, CP-SAT planned 1 row at a
-- `site_peak_kw` of **19**, three orders of magnitude under either number. The defect is
-- that nothing prevents it, not that it happened.
--
-- **Not the constants being wrong as constants.** 2500 is `depots.service_max_kw` and 1620
-- is `dcfc_max_concurrent_kw` × (1 − `dcfc_safety_margin_pct`/100); both are correctly
-- derived and `bridge/sites/nashville-flagship.json` documents that derivation honestly.
-- They are the site's STRUCTURAL limits. The defect is that a structural limit was used
-- where a live limit exists, and the live one is lower.
--
-- **Not a claim that the modelling parameters are readable.** `dcfc_cooldown_min`,
-- `move_duration_min`, `path_capacity`, `cold_start_below_c`, `cold_start_penalty_min` and
-- `onpeak_window_min` are NOT in the database — the site file says so in as many words for
-- each one, and BUILD_QUEUE #5 records that the SQL engine holds no cooldown anywhere.
-- This function therefore returns them as DECLARED constants carrying the same provenance
-- strings, and says in `_source` that it declared rather than read them. Inventing a
-- lookup for a value that does not exist would be worse than a documented constant.
--
-- ══ 3. THE RULE THIS ENCODES ═══════════════════════════════════════════════
--
-- One authority for the cap, and it is the engine's. Concretely:
--
--   hard := LEAST(service_max_kw, COALESCE(live_charge_cap_kw, service_max_kw))
--   soft := LEAST(hard, dcfc_max_concurrent_kw × (1 − safety_margin_pct/100))
--
-- **This can only ever tighten, never loosen**, and that is deliberate. With no live cap in
-- force it returns 2500 / 1620 — byte-identical to the two constants it replaces — so
-- adopting it cannot regress any existing behaviour. It differs from today only when the
-- engine itself has issued a cap, which is exactly when the constants are wrong.
--
-- A zero cap is returned AS ZERO. The MPC may legitimately command no charging, and
-- `bridge/proposer_bridge.py:277` already turns the resulting INFEASIBLE into
-- `status='empty'` with `error='solver declined the frame'` rather than a traceback, so the
-- truthful value is safe to return and a floored one would let a charge through against a
-- cap of nothing.

BEGIN;

-- ══ P0. PREFLIGHT ══════════════════════════════════════════════════════════
DO $p0$
DECLARE v_missing text;
BEGIN
  --: the inputs this function is built on must exist, or it is guessing.
  SELECT string_agg(x, ', ') INTO v_missing FROM (
    SELECT 'public.ottoq_active_charge_cap_kw' AS x
     WHERE to_regprocedure('public.ottoq_active_charge_cap_kw(uuid,uuid,timestamptz)') IS NULL
    UNION ALL
    SELECT 'depots.service_max_kw' WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name='depots' AND column_name='service_max_kw')
    UNION ALL
    SELECT 'depots.dcfc_max_concurrent_kw' WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name='depots' AND column_name='dcfc_max_concurrent_kw')
    UNION ALL
    SELECT 'depots.dcfc_safety_margin_pct' WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name='depots' AND column_name='dcfc_safety_margin_pct')
  ) s;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0389 P0: missing input(s): %', v_missing USING ERRCODE='42883';
  END IF;

  --: 0389 asserts it reproduces the constants when no cap is in force. If the twin
  --: depot's structural numbers have moved, the assertion in P2 is about different
  --: numbers and must be re-derived rather than silently pass.
  IF NOT EXISTS (
    SELECT 1 FROM public.depots
     WHERE id = '11111111-1111-1111-1111-111111111111'
       AND service_max_kw = 2500 AND dcfc_max_concurrent_kw = 1800
       AND dcfc_safety_margin_pct = 10.0) THEN
    RAISE EXCEPTION '0389 P0: the twin depot no longer reads 2500/1800/10.0; P2''s '
                    'no-cap equivalence assertion is stated against those values and '
                    'must be re-derived before this file is applied'
      USING ERRCODE='22023';
  END IF;
END $p0$;

-- ══ P1. THE DESCRIPTOR ═════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_build_site_descriptor(
  p_depot_id   uuid,
  p_sim_run_id uuid        DEFAULT NULL,
  p_sim_clock  timestamptz DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_svc      numeric;
  v_dcfc     numeric;
  v_margin   numeric;
  v_derived  numeric;   -- the structural DCFC-concurrency target (1620 here)
  v_live     numeric;   -- the engine's live cap, or NULL when none is in force
  v_clock    timestamptz;
  v_hard     numeric;
  v_soft     numeric;
BEGIN
  IF p_depot_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_build_site_descriptor: p_depot_id is required'
      USING ERRCODE='22023';
  END IF;

  SELECT d.service_max_kw, d.dcfc_max_concurrent_kw, d.dcfc_safety_margin_pct
    INTO v_svc, v_dcfc, v_margin
    FROM public.depots d WHERE d.id = p_depot_id;
  IF v_svc IS NULL THEN
    --: A missing depot, or a depot with no declared service limit, must not be
    --: answered with a default. The caller falls back to its own constant and says
    --: so; a silent 2500 here would be the very defect this file closes.
    RAISE EXCEPTION 'ottoq_build_site_descriptor: depot % has no service_max_kw', p_depot_id
      USING ERRCODE='22023';
  END IF;

  v_derived := round(COALESCE(v_dcfc, v_svc) * (1 - COALESCE(v_margin, 0) / 100.0));

  --: THE LIVE CAP. Only askable with a run and a clock: it is a run-scoped energy
  --: command with a horizon, so "the cap now" is meaningless without both. When the
  --: caller has neither, the structural limits stand and `_source` says so.
  IF p_sim_run_id IS NOT NULL THEN
    v_clock := COALESCE(p_sim_clock,
                        (SELECT r.sim_clock_current FROM public.ottoq_sim_runs r
                          WHERE r.sim_run_id = p_sim_run_id));
    IF v_clock IS NOT NULL THEN
      v_live := public.ottoq_active_charge_cap_kw(p_sim_run_id, p_depot_id, v_clock);
    END IF;
  END IF;

  --: TIGHTEN ONLY. LEAST against the service limit means a bad energy command cannot
  --: raise the cap above the wire, and COALESCE means its absence cannot lower it.
  --:
  --: FLOOR, AND THE FLOOR IS NOT COSMETIC. `solvers/cpsat/model.py:773-774` spends
  --: these two straight into `AddCumulative(...)` and `NewIntVar(0, hard, ...)`, and
  --: OR-Tools 9.15.6755 REFUSES a non-integral bound outright:
  --:   TypeError: Domain(arg0: int, arg1: int) -- Invoked with: 0, 659.5
  --: The constants this replaces were 2500 and 1620, both integral, so the defect could
  --: only ever appear once a live cap bound -- and the live cap is an MPC setpoint that
  --: is routinely fractional (659.5 kW when this file was applied). Returning numeric
  --: here would have crashed the solver on the first tick that tightened it. FLOOR, not
  --: round, because rounding a cap upward hands the solver headroom the engine will not
  --: honour.
  v_hard := floor(LEAST(v_svc, COALESCE(v_live, v_svc)));
  --: The soft target is a penalty threshold, not a limit, so it is clamped to the hard
  --: cap: a soft target ABOVE the hard cap (today: 1620 against a live 795) makes the
  --: peak-excursion term unreachable and silently deletes the objective's second half.
  v_soft := floor(LEAST(v_hard, v_derived));

  RETURN jsonb_build_object(
    'power_cap_kw_hard',     v_hard,
    'power_soft_target_kw',  v_soft,
    --: DECLARED, not read. Each string is the provenance already committed in
    --: bridge/sites/nashville-flagship.json; none of these five values exists anywhere
    --: in this database, and 0389 does not pretend otherwise.
    'dcfc_cooldown_min',     18,
    'move_duration_min',     4,
    'path_capacity',         2,
    'cold_start_below_c',    5,
    'cold_start_penalty_min', 12,
    --: NES GSA-3 has no time-of-use window -- the demand charge is the non-coincident
    --: 30-minute peak -- so an empty window is the truthful declaration, not a gap.
    'onpeak_window_min',     jsonb_build_array(0, 0),
    '_source', jsonb_build_object(
      'depot_id',            p_depot_id,
      'sim_run_id',          p_sim_run_id,
      'resolved_at_clock',   v_clock,
      'service_max_kw',      v_svc,
      'dcfc_target_kw',      v_derived,
      'live_charge_cap_kw',  v_live,
      'cap_source',          CASE WHEN v_live IS NULL THEN 'depots.service_max_kw'
                                  ELSE 'ottoq_active_charge_cap_kw' END,
      'cap_is_zero',         (v_hard = 0),
      'tightened_by_live_cap', (v_live IS NOT NULL AND v_live < v_svc),
      'declared_not_read',   jsonb_build_array(
                               'dcfc_cooldown_min', 'move_duration_min', 'path_capacity',
                               'cold_start_below_c', 'cold_start_penalty_min',
                               'onpeak_window_min'),
      'why',                 '0389: the live charge cap is the cap the decide path '
                             'enforces; the structural limits are the ceiling it can '
                             'never exceed. LEAST of both, so this can only tighten.'));
END $fn$;

COMMENT ON FUNCTION public.ottoq_build_site_descriptor(uuid, uuid, timestamptz) IS
  '0389. The `site` descriptor the CP-SAT proposer plans against, derived rather than '
  'hardcoded. power_cap_kw_hard is spent as a CP-SAT cumulative capacity '
  '(solvers/cpsat/model.py AddCumulative), so it is a constraint, not documentation. '
  'Was a constant 2500/1620 in edge-functions/_shared/cpsat_agent_chain.ts and '
  'bridge/sites/nashville-flagship.json while ottoq_active_charge_cap_kw read 795 for the '
  'same tick. Tightens only: with no live cap in force it returns exactly the constants it '
  'replaces. Reads nothing run-scoped it does not scope, writes nothing. The five '
  'modelling parameters are DECLARED -- they exist nowhere in this database -- and '
  '_source.declared_not_read names them so a reader is never misled about which half was '
  'measured.';

-- ══ P2. THE ASSERTION ══════════════════════════════════════════════════════
-- A named, re-runnable check rather than a one-off DO block, because the property it
-- proves -- "the descriptor never exceeds the engine's own cap" -- is exactly the kind of
-- thing that regresses quietly when someone edits the arithmetic.

CREATE OR REPLACE FUNCTION public.ottoq_assert_site_descriptor(
  p_depot_id   uuid DEFAULT '11111111-1111-1111-1111-111111111111',
  p_sim_run_id uuid DEFAULT NULL)
RETURNS TABLE(check_code text, passed boolean, detail text)
LANGUAGE plpgsql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_no_run jsonb;
  v_live   jsonb;
  v_svc    numeric;
  v_cap    numeric;
BEGIN
  SELECT d.service_max_kw INTO v_svc FROM public.depots d WHERE d.id = p_depot_id;
  v_no_run := public.ottoq_build_site_descriptor(p_depot_id, NULL, NULL);

  check_code := 'no_cap_reproduces_structural_limits';
  passed := (v_no_run->>'power_cap_kw_hard')::numeric = v_svc;
  detail := 'hard=' || (v_no_run->>'power_cap_kw_hard')
         || ' service_max_kw=' || COALESCE(v_svc::text,'-')
         || ' (adopting the descriptor with no live cap must change nothing)';
  RETURN NEXT;

  check_code := 'soft_never_exceeds_hard';
  passed := (v_no_run->>'power_soft_target_kw')::numeric
            <= (v_no_run->>'power_cap_kw_hard')::numeric;
  detail := 'soft=' || (v_no_run->>'power_soft_target_kw')
         || ' hard=' || (v_no_run->>'power_cap_kw_hard');
  RETURN NEXT;

  --: The one an editor is most likely to break, and the one OR-Tools punishes hardest:
  --: a fractional bound is a TypeError inside the solver, not a bad plan.
  check_code := 'both_power_values_are_integral';
  passed := (v_no_run->>'power_cap_kw_hard') !~ '[.]'
        AND (v_no_run->>'power_soft_target_kw') !~ '[.]';
  detail := 'hard=' || (v_no_run->>'power_cap_kw_hard')
         || ' soft=' || (v_no_run->>'power_soft_target_kw')
         || ' (model.py NewIntVar/AddCumulative refuse a non-integral bound)';
  RETURN NEXT;

  check_code := 'every_key_the_solver_requires_is_present';
  passed := (SELECT bool_and(v_no_run ? k) FROM unnest(ARRAY[
              'power_cap_kw_hard','power_soft_target_kw','dcfc_cooldown_min',
              'move_duration_min','path_capacity','cold_start_below_c',
              'cold_start_penalty_min','onpeak_window_min']) k);
  detail := 'proposer/orchestrate.py requires power_soft_target_kw explicitly; '
         || 'solvers/cpsat/model.py requires power_cap_kw_hard';
  RETURN NEXT;

  IF p_sim_run_id IS NOT NULL THEN
    v_live := public.ottoq_build_site_descriptor(
                p_depot_id, p_sim_run_id,
                (SELECT r.sim_clock_current FROM public.ottoq_sim_runs r
                  WHERE r.sim_run_id = p_sim_run_id));
    v_cap := NULLIF(v_live->'_source'->>'live_charge_cap_kw','')::numeric;

    check_code := 'live_cap_binds_when_present';
    passed := v_cap IS NULL
              OR (v_live->>'power_cap_kw_hard')::numeric <= v_cap;
    detail := 'live_charge_cap_kw=' || COALESCE(v_cap::text,'(none in force)')
           || ' hard=' || (v_live->>'power_cap_kw_hard')
           || ' cap_source=' || (v_live->'_source'->>'cap_source');
    RETURN NEXT;

    check_code := 'live_values_are_integral_too';
    passed := (v_live->>'power_cap_kw_hard') !~ '[.]'
          AND (v_live->>'power_soft_target_kw') !~ '[.]';
    detail := 'hard=' || (v_live->>'power_cap_kw_hard')
           || ' soft=' || (v_live->>'power_soft_target_kw')
           || ' from live cap ' || COALESCE(v_cap::text,'(none)')
           || ' -- the fractional case is the ONLY one the constants never exercised';
    RETURN NEXT;

    check_code := 'descriptor_never_loosens';
    passed := (v_live->>'power_cap_kw_hard')::numeric
              <= (v_no_run->>'power_cap_kw_hard')::numeric;
    detail := 'live hard=' || (v_live->>'power_cap_kw_hard')
           || ' <= structural hard=' || (v_no_run->>'power_cap_kw_hard');
    RETURN NEXT;
  END IF;
END $fn$;

COMMENT ON FUNCTION public.ottoq_assert_site_descriptor(uuid, uuid) IS
  '0389. Re-runnable assertions over ottoq_build_site_descriptor. The load-bearing one is '
  '`no_cap_reproduces_structural_limits`: it is what makes adopting the descriptor a '
  'no-op wherever no live cap is in force, which is why the change is safe to make on a '
  'live run.';

-- ══ P3. POSTFLIGHT — the assertions must pass before this commits ══════════
DO $p3$
DECLARE r record; v_fail text := '';
BEGIN
  FOR r IN SELECT * FROM public.ottoq_assert_site_descriptor(
                          '11111111-1111-1111-1111-111111111111',
                          (SELECT sr.sim_run_id FROM public.ottoq_sim_runs sr
                            WHERE sr.depot_id='11111111-1111-1111-1111-111111111111'
                              AND sr.status='running'
                              AND COALESCE(sr.run_by,'') <> 'cert_harness'
                            ORDER BY sr.started_at DESC LIMIT 1))
  LOOP
    RAISE NOTICE '0389 P3 %: % — %', r.check_code,
      CASE WHEN r.passed THEN 'PASS' ELSE 'FAIL' END, r.detail;
    IF NOT r.passed THEN v_fail := v_fail || r.check_code || ' '; END IF;
  END LOOP;
  IF v_fail <> '' THEN
    RAISE EXCEPTION '0389 P3: assertion(s) failed: %', v_fail USING ERRCODE='23514';
  END IF;
END $p3$;

COMMIT;
