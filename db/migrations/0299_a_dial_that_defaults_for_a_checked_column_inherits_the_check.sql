-- migration-version: 20260914104618
-- migration-name:    0299_a_dial_that_defaults_for_a_checked_column_inherits_the_check
--
-- 0299  A DIAL THAT DEFAULTS FOR A CHECK-CONSTRAINED COLUMN INHERITS THE CHECK
--
-- Four more of the 19 dials ottoq_policy_set refuses. Two new derivations, one
-- of which is the strongest kind available: a bound copied off a database
-- constraint rather than off code.
--
-- ---------------------------------------------------------------------------
-- DERIVATION 4 -- THE CHECK CONSTRAINT ON THE COLUMN THE DIAL DEFAULTS FOR
--
--   vehicle_target_soc_default   min 20  max 100  dflt 100
--
-- public.ottoq_default_target_soc says of itself, in its own body:
--
--   -- THE one answer to "how full is full". Every fallback in the codebase
--   -- points here. Takes no run id on purpose: this is the fleet-wide default,
--   -- and a run or depot that wants something else sets vehicles.target_soc or
--   -- the visit's target_soc, both of which win over this.
--
-- So the dial is the fleet-wide default for the quantity vehicles.target_soc
-- holds -- and that column carries
--
--   vehicles_target_soc_check  CHECK ((target_soc >= 20) AND (target_soc <= 100))
--
-- A dial value outside 20..100 would be a fleet-wide default that no individual
-- vehicle could legally be set to. 20..100 is therefore not a judgement about
-- what is sensible; it is the constraint the database already enforces on the
-- same number, lifted to the dial that stands in for it. P1 pins both the
-- constraint and the comment that ties them together.
--
-- This is the first bound in the whole catalogue effort read off a CONSTRAINT
-- rather than off a clamp, a comparison, or an RNG range. It is also the only
-- state-of-charge dial with a floor above 0, and the difference is real rather
-- than an inconsistency: dcfc_target_soc_day/night and l2_target_soc (all
-- catalogued 0..100 by 0286) are CEILINGS FOR A PLUG, where 0 legitimately
-- means "do not charge", while this one is a TARGET A VEHICLE MUST BE ABLE TO
-- HOLD.
--
-- ---------------------------------------------------------------------------
-- DERIVATION 5 -- A FLOOR APPLIED TO THE RESULT STILL BOUNDS THE DIAL
--
--   overnight_recall_max_per_tick   min 0  no ceiling  dflt 24
--   overnight_drain_concurrency     min 0  no ceiling  dflt 3
--
-- Neither is clamped at the read site. Both are clamped one line later, on the
-- RESULT, and that is enough -- because it collapses a whole half-line of dial
-- values onto one behaviour.
--
--   ottoq.ottoq_plan_dispatch_tick:
--     v_cap := LEAST(p_to_recall, GREATEST(0, v_free_intake),
--                    GREATEST(1, CEIL(<dial> * COALESCE(p_tick_minutes_actual,30) / 30.0))::int);
--
--   Every dial value <= 0 yields GREATEST(1, <= 0) = 1, at ANY tick length.
--   So 0 is the smallest distinguishable value and nothing below it says
--   anything new. 0 and 1 are NOT the same, which is why the floor is 0 and not
--   1: at a 60-minute tick, dial 0 gives 1 and dial 1 gives 2.
--
--   ottoq.ottoq_plan_overnight_drain_admissions:
--     v_admit := GREATEST(0, v_drain_cap - v_draining);
--
--   With v_draining >= 0, every cap <= 0 admits nothing, identically. Floor 0.
--
-- NO CEILING for either, and that is a measurement too. The recall cap is one
-- of three arguments to a LEAST whose other two are real quantities -- how many
-- were asked for, and how many intake spaces are free -- so a large dial is
-- bounded by the world, not by the code. The drain cap is bounded by how many
-- are already draining. Inventing a ceiling would be inventing a constraint the
-- engine does not have; 0291 set that precedent and it holds here.
--
-- ---------------------------------------------------------------------------
-- DERIVATION 3 AGAIN -- ONE MORE PERCENTAGE
--
--   topoff_threshold_soc   min 0  max 100  dflt 90
--
-- ottoq.ottoq_plan_opportunistic_charges compares it with
-- `AND v.current_soc < v_thresh` -- a state-of-charge percentage, the same
-- scale the three ottoq_target_soc_cap dials already carry at 0..100 (0286).
-- 0 offers a top-off to nothing; 100 offers one to everything short of full.
--
-- A NOTE ON ITS CALLERS, because a prosrc grep gets this wrong. Searching for
-- 'ottoq_topoff_threshold_soc(' returns two functions, but the second --
-- public.ottoq_target_soc_cap -- only mentions it in a COMMENT distinguishing
-- itself from it. The single real caller is ottoq.ottoq_plan_opportunistic_
-- charges. This file therefore pins the COMPARISON, which is code, and not a
-- caller count, which a grep cannot tell from prose. (Same lesson as 0294's
-- A1: prosrc includes comments.)
--
-- ---------------------------------------------------------------------------
-- TWO LIVE ROWS, BOTH GLOBAL, BOTH EQUAL TO THEIR FALLBACK
--
--   topoff_threshold_soc        90   'a_car_below_ninety_in_the_depot_gets_topped_off'
--   vehicle_target_soc_default 100   'a_full_charge_is_one_hundred_percent_and_has_one_home'
--
-- Written before the catalog existed, by the same class of path as 0298's
-- three (G62). Both equal their caller fallback and both sit inside the bounds
-- imposed here, so nothing in force moves -- P0 asserts it, A3 re-reads both
-- afterwards with an impossible caller default of -1.
--
-- forces_recert = FALSE. Catalog inserts only; ottoq_policy_get never reads the
-- catalog (P3). Probe writes are discarded by a savepoint (A4 checks).
--
-- EXPECTED EFFECT, PREDICTED BEFORE APPLYING
--   ottoq_policy_param_catalog rows              141 -> 145
--   ottoq_policy_catalog_gap, read_uncatalogued   19 ->  15
--   values in force                            unchanged (A3)
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0299 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0299 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0299 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0299 P-: nothing in flight';
END $inflight$;

-- P0. FOUR UNCATALOGUED; EXACTLY TWO LIVE ROWS, BOTH ALREADY IN RANGE.
DO $p0$
DECLARE
  v_cat int; r record; v_n_live int := 0;
  v_keys text[] := ARRAY['vehicle_target_soc_default','topoff_threshold_soc',
                         'overnight_recall_max_per_tick','overnight_drain_concurrency'];
BEGIN
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog
   WHERE param_key = ANY (v_keys);
  IF v_cat <> 0 THEN
    RAISE EXCEPTION '0299 P0: % of the four are already catalogued', v_cat;
  END IF;
  FOR r IN
    SELECT pp.param_key, pp.param_value FROM public.ottoq_policy_params pp
     WHERE pp.param_key = ANY (v_keys)
  LOOP
    v_n_live := v_n_live + 1;
    IF r.param_key = 'vehicle_target_soc_default'
       AND (r.param_value < 20 OR r.param_value > 100) THEN
      RAISE EXCEPTION '0299 P0: vehicle_target_soc_default holds % in force, outside '
                      'the 20..100 that vehicles_target_soc_check already enforces '
                      'on the column it defaults for', r.param_value;
    END IF;
    IF r.param_key = 'topoff_threshold_soc'
       AND (r.param_value < 0 OR r.param_value > 100) THEN
      RAISE EXCEPTION '0299 P0: topoff_threshold_soc holds % in force, outside 0..100',
                      r.param_value;
    END IF;
    IF r.param_key IN ('overnight_recall_max_per_tick','overnight_drain_concurrency')
       AND r.param_value < 0 THEN
      RAISE EXCEPTION '0299 P0: % holds % in force, below the 0 floor', r.param_key, r.param_value;
    END IF;
  END LOOP;
  IF v_n_live <> 2 THEN
    RAISE EXCEPTION '0299 P0: % live rows for these four, expected exactly 2 '
                    '(topoff_threshold_soc and vehicle_target_soc_default). '
                    'A different set means re-reading before cataloguing.', v_n_live;
  END IF;
  RAISE NOTICE '0299 P0: four uncatalogued, two live rows, both already in range';
END $p0$;

-- P1. THE CONSTRAINT, THE COMMENT THAT TIES THE DIAL TO IT, AND THE THREE
-- CODE SITES. vehicle_target_soc_default's bound rests on a CHECK and on the
-- function's own claim to be that column's default; both are pinned, because
-- either one changing invalidates the derivation.
DO $p1$
DECLARE v_chk text; v_n int;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_chk
    FROM pg_constraint
   WHERE conrelid = 'public.vehicles'::regclass AND conname = 'vehicles_target_soc_check';
  IF v_chk IS DISTINCT FROM 'CHECK (((target_soc >= 20) AND (target_soc <= 100)))' THEN
    RAISE EXCEPTION '0299 P1: vehicles_target_soc_check is now %, not the 20..100 '
                    'this file copied into the catalog', COALESCE(v_chk, '(absent)');
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_default_target_soc'
     AND position('depot that wants something else sets vehicles.target_soc or the visit''s' in p.prosrc) > 0
     AND position('SELECT public.ottoq_policy_get(NULL, ''vehicle_target_soc_default'', 100);' in p.prosrc) > 0;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0299 P1: ottoq_default_target_soc no longer both reads the dial '
                    'and claims to be vehicles.target_soc''s default; the constraint '
                    'derivation does not transfer without that claim';
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_topoff_threshold_soc'
     AND position('SELECT public.ottoq_policy_get(NULL, ''topoff_threshold_soc'', 90);' in p.prosrc) > 0;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0299 P1: ottoq_topoff_threshold_soc no longer reads the dial as read';
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_opportunistic_charges'
     AND position('AND v.current_soc < v_thresh' in p.prosrc) > 0;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0299 P1: the top-off comparison against vehicles.current_soc is gone; '
                    'the 0..100 scale was read off it';
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick'
     AND position('GREATEST(1, CEIL(' in p.prosrc) > 0
     AND position('ottoq_policy_get(p_sim_run_id,''overnight_recall_max_per_tick'',24)' in p.prosrc) > 0;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0299 P1: the GREATEST(1, CEIL(...)) that collapses every '
                    'overnight_recall_max_per_tick <= 0 onto 1 is gone';
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_overnight_drain_admissions'
     AND position('v_admit := GREATEST(0, v_drain_cap - v_draining);' in p.prosrc) > 0;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0299 P1: the GREATEST(0, cap - draining) that floors '
                    'overnight_drain_concurrency is gone';
  END IF;

  RAISE NOTICE '0299 P1: the constraint, the claim, and all four code sites still stand';
END $p1$;

-- P2. THE SETTER REFUSES ALL FOUR RIGHT NOW.
DO $p2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029900cc'::uuid;
  r record; v_r jsonb; v_refused int := 0;
BEGIN
  FOR r IN SELECT unnest(ARRAY['vehicle_target_soc_default','topoff_threshold_soc',
      'overnight_recall_max_per_tick','overnight_drain_concurrency']) AS k
  LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, r.k, 1, '0299_probe');
    IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'unknown_param' THEN
      RAISE EXCEPTION '0299 P2: the setter did NOT refuse % -- it answered %', r.k, v_r;
    END IF;
    v_refused := v_refused + 1;
  END LOOP;
  IF v_refused <> 4 THEN
    RAISE EXCEPTION '0299 P2: only % refusals, expected 4', v_refused;
  END IF;
  RAISE NOTICE '0299 P2: ottoq_policy_set refuses all four (unknown_param)';
END $p2$;

-- P3. forces_recert=false, executed.
DO $p3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get'
     AND p.prosrc ~ 'ottoq_policy_param_catalog';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0299 P3: ottoq_policy_get reads the catalog; not forces_recert=false';
  END IF;
  RAISE NOTICE '0299 P3: the read path still ignores the catalog';
END $p3$;

-- ===========================================================================
-- THE CHANGE
-- ===========================================================================

INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, affects)
VALUES
  ('vehicle_target_soc_default',
   '0299: the fleet-wide answer to "how full is full", read by public.'
   'ottoq_default_target_soc, which every other fallback in the engine points at. '
   'BOUNDS COPIED FROM A CONSTRAINT, not from code: the function''s own comment '
   'says a run or depot that wants something else sets vehicles.target_soc, and '
   'that column carries vehicles_target_soc_check CHECK (target_soc >= 20 AND '
   'target_soc <= 100). A dial outside 20..100 would be a fleet-wide default no '
   'individual vehicle could legally hold. The only SoC dial with a floor above '
   '0, and deliberately so: dcfc_target_soc_day/night and l2_target_soc are '
   'plug CEILINGS where 0 means "do not charge"; this is a target a vehicle must '
   'be able to hold. Live GLOBAL row = 100.',
   100, 20, 100, 'public.ottoq_default_target_soc'),

  ('topoff_threshold_soc',
   '0299: the state of charge BELOW which a vehicle already in the depot is '
   'offered an opportunistic top-off. 0..100 read off the comparison in its one '
   'real caller, ottoq.ottoq_plan_opportunistic_charges: AND v.current_soc < '
   'v_thresh -- the same SoC percentage scale as the three ottoq_target_soc_cap '
   'dials (0286). 0 offers a top-off to nothing, 100 to everything short of '
   'full. Distinct from vehicle_target_soc_default, which is how full the '
   'top-off then fills it. NOTE: a prosrc grep reports two callers; the second, '
   'public.ottoq_target_soc_cap, only names it in a comment. Live GLOBAL row = 90.',
   90, 0, 100, 'ottoq.ottoq_plan_opportunistic_charges'),

  ('overnight_recall_max_per_tick',
   '0299: how many vehicles the overnight surplus recall may claim in one '
   'nominal 30-minute tick; ottoq.ottoq_plan_dispatch_tick scales it by the '
   'actual tick length. Floor 0 derived from a clamp on the RESULT rather than '
   'the read: GREATEST(1, CEIL(dial * tick_min / 30.0)) collapses every value '
   '<= 0 onto 1 at any tick length, so 0 is the smallest value that says '
   'anything -- and 0 differs from 1, which is why the floor is not 1 (at a '
   '60-minute tick, 0 gives 1 and 1 gives 2). NO CEILING: the dial is one of '
   'three arguments to a LEAST whose others are how many were asked for and how '
   'many intake spaces are free, so a large value is bounded by the world, not '
   'by the code.',
   24, 0, NULL, 'ottoq.ottoq_plan_dispatch_tick'),

  ('overnight_drain_concurrency',
   '0299: how many vehicles may be in the overnight drain at once. Floor 0 from '
   'the same result-clamp shape: ottoq.ottoq_plan_overnight_drain_admissions '
   'computes v_admit := GREATEST(0, v_drain_cap - v_draining), so with '
   'v_draining >= 0 every cap <= 0 admits nothing, identically. NO CEILING in '
   'the code -- admissions are bounded by how many are already draining.',
   3, 0, NULL, 'ottoq.ottoq_plan_overnight_drain_admissions');

-- ===========================================================================
-- ASSERTIONS
-- ===========================================================================

-- A1. The counts predicted before this file ran.
DO $a1$
DECLARE v_rows int; v_cat int; v_gap int;
BEGIN
  SELECT count(*) INTO v_rows FROM public.ottoq_policy_param_catalog
   WHERE description LIKE '0299:%';
  IF v_rows <> 4 THEN
    RAISE EXCEPTION 'A1 FAILED: % rows tagged 0299, expected 4', v_rows;
  END IF;
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog;
  IF v_cat <> 145 THEN
    RAISE EXCEPTION 'A1 FAILED: catalog holds % rows, predicted 145', v_cat;
  END IF;
  SELECT count(*) INTO v_gap FROM public.ottoq_policy_catalog_gap
   WHERE status = 'read_uncatalogued';
  IF v_gap <> 15 THEN
    RAISE EXCEPTION 'A1 FAILED: gap is %, predicted 15', v_gap;
  END IF;
  RAISE NOTICE 'A1 OK: catalog 141 -> 145, gap 19 -> 15';
END $a1$;

-- A2. EVERY BOUND FIRES AT ITS OWN NUMBER. Two have ceilings and two do not,
-- so both branches are exercised by construction.
DO $a2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029900cc'::uuid;
  v_r jsonb; r record; v_n int := 0; v_capped int := 0; v_open int := 0;
BEGIN
  BEGIN
    FOR r IN
      SELECT c.param_key, c.min_value, c.max_value
        FROM public.ottoq_policy_param_catalog c
       WHERE c.description LIKE '0299:%'
       ORDER BY c.param_key
    LOOP
      v_r := public.ottoq_policy_set('run', v_scratch, r.param_key,
                                     r.min_value - 1, '0299_proof');
      IF COALESCE((v_r->>'applied')::numeric, -999) <> r.min_value
         OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
        RAISE EXCEPTION 'A2 FAILED: % below its floor must clamp to % and say so: %',
                        r.param_key, r.min_value, v_r;
      END IF;
      IF r.max_value IS NULL THEN
        v_open := v_open + 1;
        v_r := public.ottoq_policy_set('run', v_scratch, r.param_key, 99999, '0299_proof');
        IF COALESCE((v_r->>'applied')::numeric, -1) <> 99999
           OR COALESCE((v_r->>'clamped')::boolean, true) THEN
          RAISE EXCEPTION 'A2 FAILED: % has no ceiling and must not clamp at 99999: %',
                          r.param_key, v_r;
        END IF;
      ELSE
        v_capped := v_capped + 1;
        v_r := public.ottoq_policy_set('run', v_scratch, r.param_key,
                                       r.max_value + 1, '0299_proof');
        IF COALESCE((v_r->>'applied')::numeric, -1) <> r.max_value
           OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
          RAISE EXCEPTION 'A2 FAILED: % has a ceiling of % and must clamp to it: %',
                          r.param_key, r.max_value, v_r;
        END IF;
      END IF;
      v_n := v_n + 1;
    END LOOP;
    IF v_n <> 4 OR v_capped <> 2 OR v_open <> 2 THEN
      RAISE EXCEPTION 'A2 FAILED: tested % dials (% capped, % open), expected 4 (2, 2). '
                      'Both branches must be exercised or half this test is decoration.',
                      v_n, v_capped, v_open;
    END IF;
    RAISE EXCEPTION 'A2_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A2_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A2 OK: 2 capped dials clamp at both ends, 2 open dials clamp only below';
END $a2$;

-- A3. NOTHING IN FORCE MOVED, read back with an impossible caller default.
DO $a3$
DECLARE v_topoff numeric; v_target numeric;
BEGIN
  v_topoff := public.ottoq_policy_get(NULL, 'topoff_threshold_soc',       -1);
  v_target := public.ottoq_policy_get(NULL, 'vehicle_target_soc_default', -1);
  IF v_topoff IS DISTINCT FROM 90 THEN
    RAISE EXCEPTION 'A3 FAILED: topoff_threshold_soc in force is %, was 90', v_topoff;
  END IF;
  IF v_target IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION 'A3 FAILED: vehicle_target_soc_default in force is %, was 100', v_target;
  END IF;
  RAISE NOTICE 'A3 OK: both live globals still read 90 / 100 from their stored rows';
END $a3$;

-- A4. NO RESIDUE.
DO $a4$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE scope_id = '00000000-0000-0000-0000-0000029900cc'::uuid
      OR updated_by IN ('0299_probe','0299_proof');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: % probe row(s) survived', v_n;
  END IF;
  RAISE NOTICE 'A4 OK: no probe rows survived';
END $a4$;
