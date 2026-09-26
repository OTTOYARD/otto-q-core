-- migration-version: 20260926115429
-- migration-name:    the_solar_canopies_soiling_was_shared_by_every_run_so_an_arm_inherited_the_panels_the_last_run_left
--
-- 0479  **The solar canopies' soiling was depot state every run shared, so each arm inherited the panels the run
--       before it left, and neither the dial pairs nor the canon compared like with like.** `db/checks/0361` §8.
--       FINDINGS G214.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The overnight recall experiment's pairs (3a2c5fa1) made identical recall decisions in both arms, 1,123 each with
--   no field differing, and identical dispatches and charge sessions, yet their energy atoms differed from tick 7 on.
--   The first difference is site net load, 543 against 545 kW, and it is solar alone: building and EV load are
--   equal, and arm B's solar is a constant 96.0% of arm A's at every half hour. On the same canopy at the same sim
--   time, with the same irradiance, temperature and weather, arm A records soiling_factor 0.9082 and arm B 0.8724.
--
--   Across the eleven overnight pairs, the soiling each arm started with (canopy_1): four pairs 0.85 / 0.85 and equal
--   solar; four with arm B dirtier (0.9854 / 0.9496, 0.9139 / 0.8781, 0.9840 / 0.9482, 0.9125 / 0.8767); three with
--   arm B cleaner (0.85 / 0.9854 twice, 0.85 / 0.9840). The energy experiment b66fa99c's sixth pair, the one its p-value needed,
--   is one where the treatment arm started cleaner.
--
--   The canon, too: verdicts 273 and 280 of the G211 window differ in 12 energy commands even with the day plan's
--   solve_ms removed, and their arms started at different soiling (273: 0.9771-0.9854 against 0.9679-0.9762).
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `twin.ottoq_sim_advance_weather_and_solar` reads each canopy's soiling from `ottoq_canopy_state.current_soiling`,
--   one row per canopy per depot, drifts it (down about 0.075% a tick when dry, floored at 0.85, up 0.03 a rainy
--   tick, capped at 1.0) and writes it back. Nothing scopes the row to a run and nothing resets it, so every run at
--   the twin depot, live, certification arm or dial arm, starts from whatever the previous run left. Two arms of one
--   pair run back to back in one transaction, so arm B starts where arm A ended: equal only while the soiling is
--   pinned at its 0.85 floor. A seed that rains lifts it, and the next arm inherits the lift. `public.ottoq_bess_day_plan`
--   forecasts solar from the same row's average, so the plan inherits it too.
--
--   The precipitation chain the same function samples was scoped to its run by 0134, with the zero-uuid idiom. The
--   soiling state beside it was not.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   A new `twin.ottoq_sim_canopy_soiling(run, depot, canopy, at, inclusive)` returns a canopy's soiling as the run
--   last recorded it in `ottoq_solar_output` (its own rows, registered run-scoped), and 0.85 when the run has no row
--   yet: the dry-weather floor the drift settles at, which is where every twin-depot canon column has certified. With
--   no run it reads the depot row, as before. The solar step and the day plan read it instead of the depot row. The
--   depot row is still written each tick, as the latest value any run recorded, and read only outside a run.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Tick path: solar output, and every energy decision downstream of it, moves wherever a run started off the floor
--   or its weather rained.
--
--   PREDICTED: (a) every arm starts at soiling 0.85 whatever ran before it; (b) a dial pair's two arms record equal
--   solar at every tick; (c) a canon column certifies after a run that rained; (d) a column whose arms started at the
--   floor and never rained lands on its previous digests.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0479 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the bodies this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_weather_and_solar(uuid,uuid,timestamp with time zone)'::regprocedure))
     <> 'eec389ee4db34215750bb61260f9ef11' THEN
    RAISE EXCEPTION '0479 P2: twin.ottoq_sim_advance_weather_and_solar is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure))
     <> '110ab09eb1d47961316e2ca910348608' THEN
    RAISE EXCEPTION '0479 P2: public.ottoq_bess_day_plan is not the body this file patches';
  END IF;
  -- the helper is new, the output table is still run-scoped, and it still records the soiling it applied
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_sim_canopy_soiling')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry r
                     WHERE r.table_name = 'ottoq_solar_output' AND r.column_name = 'sim_run_id' AND r.class = 'engine')
     OR position('ROUND(v_new_soiling::numeric, 4)' IN pg_get_functiondef('twin.ottoq_sim_advance_weather_and_solar(uuid,uuid,timestamp with time zone)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0479 P2: the helper exists, or ottoq_solar_output is no longer run-scoped, or no longer records soiling';
  END IF;
  -- nothing else reads the shared soiling
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE p.prosrc ~ 'current_soiling' AND n.nspname !~ '^pg_temp'
         AND n.nspname || '.' || p.proname NOT IN ('twin.ottoq_sim_advance_weather_and_solar', 'public.ottoq_bess_day_plan',
                                                   'twin.ottoq_grid_fixture_create')) > 0 THEN
    RAISE EXCEPTION '0479 P2: another function reads ottoq_canopy_state.current_soiling';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0479_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('twin.ottoq_sim_advance_weather_and_solar(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure);

-- ── the run's own soiling ──
CREATE FUNCTION twin.ottoq_sim_canopy_soiling(p_sim_run_id uuid, p_depot_id uuid, p_canopy_code text,
                                             p_at timestamptz, p_inclusive boolean DEFAULT false)
RETURNS numeric
LANGUAGE sql STABLE
SET search_path = pg_catalog, public
AS $fn$
  /* 0479 (G214): a canopy's soiling as this run last recorded it, so no run inherits the panels another run left.
     A run with no row yet starts at 0.85, the dry-weather floor the drift settles at, where every twin-depot canon
     column has certified. With no run, the depot row, as before. p_inclusive also counts a row at p_at itself. */
  SELECT CASE
    WHEN p_sim_run_id IS NULL THEN
      (SELECT c.current_soiling FROM public.ottoq_canopy_state c
        WHERE c.depot_id = p_depot_id AND c.canopy_code = p_canopy_code)
    ELSE COALESCE(
      (SELECT o.soiling_factor FROM public.ottoq_solar_output o
        WHERE o.sim_run_id = p_sim_run_id AND o.depot_id = p_depot_id AND o.canopy_code = p_canopy_code
          AND o.sim_clock_at <= p_at AND (p_inclusive OR o.sim_clock_at < p_at)
        ORDER BY o.sim_clock_at DESC LIMIT 1),
      0.85)
  END
$fn$;

COMMENT ON FUNCTION twin.ottoq_sim_canopy_soiling(uuid, uuid, text, timestamptz, boolean) IS
  '0479 (G214): a canopy''s soiling as the run last recorded it in ottoq_solar_output, 0.85 before its first row, '
  'the depot row outside a run. The solar step and the BESS day plan read it, never the shared depot row.';

REVOKE ALL ON FUNCTION twin.ottoq_sim_canopy_soiling(uuid, uuid, text, timestamptz, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_canopy_soiling(uuid, uuid, text, timestamptz, boolean) TO service_role;

-- ── the solar step reads it ──
DO $patch_solar$
DECLARE
  v_def  text := pg_get_functiondef('twin.ottoq_sim_advance_weather_and_solar(uuid,uuid,timestamp with time zone)'::regprocedure);
  v_pat1 text := $p$v_new_soiling      NUMERIC;$p$;
  v_new1 text := $r$v_new_soiling      NUMERIC;
  v_prev_soiling     NUMERIC;$r$;
  v_pat2 text := $p$IF v_precip_mm >= 1\.0 THEN\s+v_new_soiling := LEAST\(1\.00, v_canopy\.current_soiling \+ 0\.03\);$p$;
  v_new2 text := $r$-- 0479 (G214): this run's own soiling, never the depot row another run left behind
    v_prev_soiling := twin.ottoq_sim_canopy_soiling(p_sim_run_id, p_depot_id, v_canopy.canopy_code, p_sim_clock_now);
    IF v_precip_mm >= 1.0 THEN
      v_new_soiling := LEAST(1.00, v_prev_soiling + 0.03);$r$;
  v_pat3 text := $p$v_canopy\.current_soiling - 0\.0005 \* \(1 \+ ottoq_sim_seeded_random\(v_seed, 'so:' \|\| v_canopy\.canopy_code\)\)\);$p$;
  v_new3 text := $r$v_prev_soiling - 0.0005 * (1 + ottoq_sim_seeded_random(v_seed, 'so:' || v_canopy.canopy_code)));$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat1, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0479: the soiling declaration matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat2, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0479: the rain branch matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat3, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0479: the dry branch matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat1, v_new1);
  v_def := regexp_replace(v_def, v_pat2, v_new2);
  v_def := regexp_replace(v_def, v_pat3, v_new3);
  EXECUTE v_def;
END $patch_solar$;

-- ── the day plan's solar forecast reads it ──
DO $patch_plan$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure);
  v_pat text := $p$SELECT COALESCE\(sum\(c\.nameplate_ac_kw\), 0\), COALESCE\(avg\(c\.current_soiling\), 1\) INTO v_ac, v_soil$p$;
  v_new text := $r$SELECT COALESCE(sum(c.nameplate_ac_kw), 0),
         -- 0479 (G214): the run's own soiling, as the solar step reads it
         COALESCE(avg(twin.ottoq_sim_canopy_soiling(p_sim_run_id, p_depot_id, c.canopy_code, p_sim_clock, true)), 1) INTO v_ac, v_soil$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0479: the day plan''s soiling read matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_plan$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_w  text := pg_get_functiondef('twin.ottoq_sim_advance_weather_and_solar(uuid,uuid,timestamp with time zone)'::regprocedure);
  v_dp text := pg_get_functiondef('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure);
  v_h  regprocedure := 'twin.ottoq_sim_canopy_soiling(uuid,uuid,text,timestamp with time zone,boolean)'::regprocedure;
  v_row numeric;
BEGIN
  -- V1: the helper is stable, returns numeric, and only service_role (and its owner) may call it.
  IF (SELECT provolatile FROM pg_proc WHERE oid = v_h) <> 's'
     OR pg_get_function_result(v_h) <> 'numeric'
     OR has_function_privilege('anon', v_h, 'EXECUTE') OR has_function_privilege('authenticated', v_h, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_h, 'EXECUTE') THEN
    RAISE EXCEPTION '0479 V1: the helper is not what this file creates';
  END IF;
  -- V2: the solar step reads the helper once and the shared row nowhere, and still writes the row.
  IF (SELECT count(*) FROM regexp_matches(v_w, 'v_canopy\.current_soiling', 'g')) <> 0
     OR (SELECT count(*) FROM regexp_matches(v_w, $x$v_prev_soiling := twin\.ottoq_sim_canopy_soiling\(p_sim_run_id, p_depot_id, v_canopy\.canopy_code, p_sim_clock_now\);$x$, 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_w, 'v_prev_soiling', 'g')) <> 4
     OR (SELECT count(*) FROM regexp_matches(v_w, 'SET current_soiling = v_new_soiling', 'g')) <> 1 THEN
    RAISE EXCEPTION '0479 V2: the solar step is not the body this file writes';
  END IF;
  -- V3: the day plan reads the helper once, inclusive, and the shared row nowhere.
  IF (SELECT count(*) FROM regexp_matches(v_dp, $x$avg\(twin\.ottoq_sim_canopy_soiling\(p_sim_run_id, p_depot_id, c\.canopy_code, p_sim_clock, true\)\)$x$, 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_dp, 'current_soiling', 'g')) <> 0 THEN
    RAISE EXCEPTION '0479 V3: the day plan is not the body this file writes';
  END IF;
  -- V4: a run with no row starts at 0.85, and outside a run the depot row is read.
  SELECT c.current_soiling INTO v_row FROM public.ottoq_canopy_state c
   WHERE c.depot_id = '11111111-1111-1111-1111-111111111111' AND c.canopy_code = 'canopy_1';
  IF twin.ottoq_sim_canopy_soiling(gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'canopy_1', now()) <> 0.85
     OR twin.ottoq_sim_canopy_soiling(NULL, '11111111-1111-1111-1111-111111111111', 'canopy_1', now()) IS DISTINCT FROM v_row THEN
    RAISE EXCEPTION '0479 V4: the helper does not start a run at 0.85, or does not read the depot row outside one';
  END IF;
  -- V5: no overload appeared, and the patched functions kept their grants.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_weather_and_solar') <> 1
     OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'public' AND p.proname = 'ottoq_bess_day_plan') <> 1
     OR (SELECT count(*) FROM pg_proc WHERE proname = 'ottoq_sim_canopy_soiling') <> 1 THEN
    RAISE EXCEPTION '0479 V5: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_advance_weather_and_solar(uuid,uuid,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_sim_advance_weather_and_solar(uuid,uuid,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)', 'EXECUTE') THEN
    RAISE EXCEPTION '0479 V5: a grant moved';
  END IF;
END $verify$;

-- Rollback: restore both functions from ottoq_schema_snapshots label '0479_pre' (CREATE OR REPLACE; grants kept),
-- then DROP FUNCTION twin.ottoq_sim_canopy_soiling(uuid, uuid, text, timestamptz, boolean).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0479_the_solar_canopies_soiling_was_shared_by_every_run_so_an_arm_inherited_the_panels_the_last_run_left', true,
  'Tick path: twin.ottoq_sim_advance_weather_and_solar and public.ottoq_bess_day_plan read a canopy''s soiling from '
  'the run''s own ottoq_solar_output rows (0.85 before the first), not the shared ottoq_canopy_state row. Solar '
  'output and the energy decisions downstream move wherever a run started off the floor or its weather rained.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
