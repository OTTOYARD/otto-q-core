-- migration-version: 20260914105135
-- migration-name:    0300_three_dials_whose_floor_is_on_the_other_side_of_the_assignment
--
-- 0300  THREE DIALS WHOSE FLOOR IS ON THE OTHER SIDE OF THE ASSIGNMENT
--
-- Three more of the 15. Each extends derivation 5 from 0299 -- the bound is not
-- at the read site, it is on the thing the dial is compared with or the thing
-- the dial stands in for.
--
-- ---------------------------------------------------------------------------
-- TWO GATES COMPARED AGAINST A QUANTITY THE CONSUMER ITSELF FLOORS AT ZERO
--
--   deploy_gate_patience_min   min 0  no ceiling  dflt 45
--   deploy_gate_hard_cap_min   min 0  no ceiling  dflt 240
--
-- twin.ottoq_sim_advance_service_flow holds a vehicle at the deploy gate and
-- tests the hold against both dials:
--
--     v_held_min := GREATEST(0, EXTRACT(EPOCH FROM (p_sim_clock_now - v_since))/60.0);
--     ...
--     IF v_held_min >= v_hardcap THEN                    -- force release
--     IF v_held_min >= v_patience_dep THEN ...           -- escalate
--
-- The CONSUMER floors v_held_min at 0 itself. So for any dial value <= 0 the
-- comparison is true from the first tick of the hold and stays true, and every
-- such value behaves identically -- min 0 is the smallest one that says
-- anything. Neither has a ceiling: a hold that never reaches the number simply
-- never fires, which is a real setting, not an error.
--
-- WHAT THE CATALOG STILL CANNOT SAY, and this is the second instance of G61's
-- class: these two have an INVARIANT BETWEEN THEM. Patience is meant to
-- escalate before the hard cap force-releases, so patience <= hard cap. The
-- catalog holds one min and one max per key and has no way to express a
-- relation between two keys, so nothing stops an agent setting patience 300
-- and hard cap 60 -- which would escalate nothing, because the release fires
-- first. Recorded in both descriptions; tracked with G61.
--
-- ---------------------------------------------------------------------------
-- A FALLBACK INHERITS THE DOMAIN OF THE BRANCH IT FALLS BACK FROM
--
--   yard_default_units   min 0  no ceiling  dflt 120
--
-- public.ottoq_itin_travel_leg assigns the SAME variable twice:
--
--     v_units := sqrt( (tx - fx)^2 + (ty - fy)^2 );          -- when both ends have coordinates
--     ...
--     v_units := ottoq_policy_get(p_sim_run_id, 'yard_default_units', 120);   -- when they do not
--     ...
--     v_metres := v_units * v_scale;
--
-- The first producer is a Euclidean distance and CANNOT be negative. The dial
-- is the stand-in for that same quantity when coordinates are missing, so a
-- negative value would give v_units something its other producer can never
-- produce, and would then multiply through into negative metres. min 0, by the
-- same reasoning 0299 used for a CHECK constraint: the dial inherits the domain
-- of the thing it defaults for.
--
-- NOT claimed: that a negative would break the engine. It would not -- the leg
-- duration ends at v_secs := GREATEST(5.0, (v_metres / v_speed) + v_overhead),
-- so a sufficiently negative distance is absorbed into a 5-second floor. That
-- absorption is why this needed the sibling-branch argument and not a clamp:
-- the clamp is too far downstream and too weak to bound the dial.
--
-- ---------------------------------------------------------------------------
-- WHERE THIS LEAVES THE EFFORT
--
-- 92 dials were unwritable through ottoq_policy_set when this started; after
-- this file, 12. The twelve that remain are NOT waiting on more of the same
-- reading -- they are the ones where no bound exists to be read, and the
-- reasons are enumerated in db/checks/0228. The next move for most of them is
-- NOT a tighter derivation but a NULL/NULL catalog row, which would make them
-- writable while imposing nothing. That is a new convention (no catalog row has
-- a NULL min today) and it gets its own file.
--
-- forces_recert = FALSE. Catalog inserts only; ottoq_policy_get never reads the
-- catalog (P3). No live rows exist for any of the three (P0), so nothing in
-- force can move. Probe writes are discarded by a savepoint (A4).
--
-- EXPECTED EFFECT, PREDICTED BEFORE APPLYING
--   ottoq_policy_param_catalog rows              145 -> 148
--   ottoq_policy_catalog_gap, read_uncatalogued   15 ->  12
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0300 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0300 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0300 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0300 P-: nothing in flight';
END $inflight$;

-- P0. THREE UNCATALOGUED, NO LIVE ROWS.
DO $p0$
DECLARE v_cat int; v_live int;
  v_keys text[] := ARRAY['deploy_gate_patience_min','deploy_gate_hard_cap_min','yard_default_units'];
BEGIN
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog WHERE param_key = ANY (v_keys);
  IF v_cat <> 0 THEN
    RAISE EXCEPTION '0300 P0: % of the three are already catalogued', v_cat;
  END IF;
  SELECT count(*) INTO v_live FROM public.ottoq_policy_params WHERE param_key = ANY (v_keys);
  IF v_live <> 0 THEN
    RAISE EXCEPTION '0300 P0: % live rows exist for these keys; the derivation assumed '
                    'the caller fallback is the only value in force', v_live;
  END IF;
  RAISE NOTICE '0300 P0: three uncatalogued, zero live rows';
END $p0$;

-- P1. EVERY DERIVATION PINNED. The two gates rest on the consumer flooring
-- v_held_min at 0 AND on the two comparisons; the yard fallback rests on the
-- sibling sqrt branch assigning the same variable. If any of the eight moves,
-- the bound in this file is no longer read off anything.
DO $p1$
DECLARE r record; v_hits int; v_n int := 0;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('twin','ottoq_sim_advance_service_flow','the consumer floors held-minutes at 0',
       'v_held_min := GREATEST(0, EXTRACT(EPOCH FROM (p_sim_clock_now - v_since))/60.0);'),
      ('twin','ottoq_sim_advance_service_flow','the hard-cap comparison',
       'IF v_held_min >= v_hardcap THEN'),
      ('twin','ottoq_sim_advance_service_flow','the patience comparison',
       'IF v_held_min >= v_patience_dep THEN v_esc_gate := v_esc_gate + 1; END IF;'),
      ('twin','ottoq_sim_advance_service_flow','the patience read',
       'v_patience_dep := COALESCE(ottoq_policy_get(p_sim_run_id,''deploy_gate_patience_min'',45),45);'),
      ('twin','ottoq_sim_advance_service_flow','the hard-cap read',
       'v_hardcap      := COALESCE(ottoq_policy_get(p_sim_run_id,''deploy_gate_hard_cap_min'',240),240);'),
      ('public','ottoq_itin_travel_leg','the sqrt branch that cannot be negative',
       'v_units := sqrt( (tx - fx)^2 + (ty - fy)^2 );'),
      ('public','ottoq_itin_travel_leg','the fallback branch this dial is',
       'v_units := ottoq_policy_get(p_sim_run_id, ''yard_default_units'', 120);'),
      ('public','ottoq_itin_travel_leg','the multiply that carries the sign through',
       'v_metres := v_units * v_scale;')
    ) AS t(nsp, fn, what, frag)
  LOOP
    SELECT count(*) INTO v_hits
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = r.nsp AND p.proname = r.fn AND position(r.frag in p.prosrc) > 0;
    IF v_hits <> 1 THEN
      RAISE EXCEPTION '0300 P1: %.% no longer contains % (found %)', r.nsp, r.fn, r.what, v_hits;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 8 THEN
    RAISE EXCEPTION '0300 P1: pinned % sites, expected 8', v_n;
  END IF;
  RAISE NOTICE '0300 P1: all eight derivation sites still say what this file copied';
END $p1$;

-- P1b. ONE READ SITE EACH -- a bound read off one site is wrong if another
-- reads the same key differently.
DO $p1b$
DECLARE r record; v_reads int;
BEGIN
  FOR r IN SELECT unnest(ARRAY['deploy_gate_patience_min','deploy_gate_hard_cap_min',
                               'yard_default_units']) AS k
  LOOP
    SELECT count(*) INTO v_reads
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
           LATERAL regexp_matches(p.prosrc,
             'ottoq_policy_get\s*\(\s*[^,]+,\s*''' || r.k || '''', 'g')
     WHERE n.nspname IN ('public','ottoq','twin');
    IF v_reads <> 1 THEN
      RAISE EXCEPTION '0300 P1b: % is read at % sites, not 1', r.k, v_reads;
    END IF;
  END LOOP;
  RAISE NOTICE '0300 P1b: one read site each';
END $p1b$;

-- P2. THE SETTER REFUSES ALL THREE RIGHT NOW.
DO $p2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000030000cc'::uuid;
  r record; v_r jsonb; v_refused int := 0;
BEGIN
  FOR r IN SELECT unnest(ARRAY['deploy_gate_patience_min','deploy_gate_hard_cap_min',
                               'yard_default_units']) AS k
  LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, r.k, 1, '0300_probe');
    IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'unknown_param' THEN
      RAISE EXCEPTION '0300 P2: the setter did NOT refuse % -- it answered %', r.k, v_r;
    END IF;
    v_refused := v_refused + 1;
  END LOOP;
  IF v_refused <> 3 THEN
    RAISE EXCEPTION '0300 P2: only % refusals, expected 3', v_refused;
  END IF;
  RAISE NOTICE '0300 P2: ottoq_policy_set refuses all three (unknown_param)';
END $p2$;

-- P3. forces_recert=false, executed.
DO $p3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get'
     AND p.prosrc ~ 'ottoq_policy_param_catalog';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0300 P3: ottoq_policy_get reads the catalog; not forces_recert=false';
  END IF;
  RAISE NOTICE '0300 P3: the read path still ignores the catalog';
END $p3$;

-- ===========================================================================
-- THE CHANGE
-- ===========================================================================

INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, affects)
VALUES
  ('deploy_gate_patience_min',
   '0300: sim-minutes a vehicle may be held at the deploy gate before the hold '
   'is escalated (config.flagged_issue). Floor 0 read off the CONSUMER, not the '
   'read site: twin.ottoq_sim_advance_service_flow computes v_held_min := '
   'GREATEST(0, ...) and tests v_held_min >= this, so every value <= 0 fires '
   'from the first tick and behaves identically. No ceiling -- a patience the '
   'hold never reaches simply never escalates, which is a setting, not an error. '
   'INVARIANT THE CATALOG CANNOT EXPRESS (G61): this should stay <= '
   'deploy_gate_hard_cap_min, or the force-release fires first and nothing is '
   'ever escalated. Per-key bounds cannot say that.',
   45, 0, NULL, 'twin.ottoq_sim_advance_service_flow'),

  ('deploy_gate_hard_cap_min',
   '0300: sim-minutes after which a deploy-gate hold is force-released rather '
   'than waited out -- the anti-deadlock bound, longer than any bounded demo. '
   'Same floor derivation as deploy_gate_patience_min: compared against a '
   'v_held_min the consumer floors at 0, so every value <= 0 releases '
   'immediately and identically. No ceiling. INVARIANT THE CATALOG CANNOT '
   'EXPRESS (G61): should stay >= deploy_gate_patience_min.',
   240, 0, NULL, 'twin.ottoq_sim_advance_service_flow'),

  ('yard_default_units',
   '0300: the plan-unit distance public.ottoq_itin_travel_leg assumes for a leg '
   'when one end has no coordinates. Floor 0 by DOMAIN INHERITANCE, the same '
   'shape 0299 used for a CHECK constraint: the function assigns v_units twice, '
   'once from sqrt((tx-fx)^2 + (ty-fy)^2) -- a Euclidean distance that cannot be '
   'negative -- and once from this dial, and then multiplies it into v_metres. A '
   'negative would give the variable a value its other producer can never '
   'produce. NOT claimed: that a negative breaks anything -- the leg ends at '
   'GREATEST(5.0, metres/speed + overhead), which absorbs it. That absorption is '
   'exactly why the floor had to come from the sibling branch rather than from a '
   'clamp. No ceiling: a long default leg is slow, not illegal.',
   120, 0, NULL, 'public.ottoq_itin_travel_leg');

-- ===========================================================================
-- ASSERTIONS
-- ===========================================================================

-- A1. The counts predicted before this file ran.
DO $a1$
DECLARE v_rows int; v_cat int; v_gap int;
BEGIN
  SELECT count(*) INTO v_rows FROM public.ottoq_policy_param_catalog
   WHERE description LIKE '0300:%';
  IF v_rows <> 3 THEN
    RAISE EXCEPTION 'A1 FAILED: % rows tagged 0300, expected 3', v_rows;
  END IF;
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog;
  IF v_cat <> 148 THEN
    RAISE EXCEPTION 'A1 FAILED: catalog holds % rows, predicted 148', v_cat;
  END IF;
  SELECT count(*) INTO v_gap FROM public.ottoq_policy_catalog_gap
   WHERE status = 'read_uncatalogued';
  IF v_gap <> 12 THEN
    RAISE EXCEPTION 'A1 FAILED: gap is %, predicted 12', v_gap;
  END IF;
  RAISE NOTICE 'A1 OK: catalog 145 -> 148, gap 15 -> 12';
END $a1$;

-- A2. All three floor at 0 and none has a ceiling.
DO $a2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000030000cc'::uuid;
  v_r jsonb; r record; v_n int := 0;
BEGIN
  BEGIN
    FOR r IN
      SELECT c.param_key, c.min_value, c.max_value
        FROM public.ottoq_policy_param_catalog c
       WHERE c.description LIKE '0300:%'
       ORDER BY c.param_key
    LOOP
      IF r.min_value <> 0 OR r.max_value IS NOT NULL THEN
        RAISE EXCEPTION 'A2 FAILED: % is %..%, but every dial in 0300 is 0..NULL '
                        'and the header says so', r.param_key, r.min_value, r.max_value;
      END IF;
      v_r := public.ottoq_policy_set('run', v_scratch, r.param_key, -1, '0300_proof');
      IF COALESCE((v_r->>'applied')::numeric, -999) <> 0
         OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
        RAISE EXCEPTION 'A2 FAILED: % below 0 must clamp to 0 and say so: %', r.param_key, v_r;
      END IF;
      v_r := public.ottoq_policy_set('run', v_scratch, r.param_key, 99999, '0300_proof');
      IF COALESCE((v_r->>'applied')::numeric, -1) <> 99999
         OR COALESCE((v_r->>'clamped')::boolean, true) THEN
        RAISE EXCEPTION 'A2 FAILED: % has no ceiling and must not clamp at 99999: %',
                        r.param_key, v_r;
      END IF;
      v_n := v_n + 1;
    END LOOP;
    IF v_n <> 3 THEN
      RAISE EXCEPTION 'A2 FAILED: tested % dials, the file inserted 3', v_n;
    END IF;
    RAISE EXCEPTION 'A2_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A2_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A2 OK: all three floor at 0, none has a ceiling; scratch writes discarded';
END $a2$;

-- A3. NO RESIDUE.
DO $a3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE scope_id = '00000000-0000-0000-0000-0000030000cc'::uuid
      OR updated_by IN ('0300_probe','0300_proof');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A3 FAILED: % probe row(s) survived', v_n;
  END IF;
  RAISE NOTICE 'A3 OK: no probe rows survived';
END $a3$;
