-- =====================================================================
-- 0175  The pair and the scenario must name the same world
-- =====================================================================
-- FOUND BY: the 0169 grid smoke, fired 10:00 PM CT Sep 2, failing after
-- 170.1 s with `grid_assert: run <NULL> not found`.
--
-- WHAT ACTUALLY HAPPENED. twin.ottoq_grid_smoke takes a fixture slug AND
-- a scenario code as independent arguments. The slug decides the depot
-- it checks exists, resets, and fingerprints. The SCENARIO decides the
-- depot stamped onto the run row, because twin.ottoq_sim_start_run
-- writes `v_scenario.depot_id` and never sees the pair's p_depot.
-- Nothing made the two agree. The smoke was fired with slug
-- 'grid-0169-smoke' (a 6-point fixture) and scenario 'busy_day' (bound
-- to the flagship), so it spent 170 seconds ticking two arms of the
-- FLAGSHIP under a headline that said grid fixture, then failed only
-- because it went looking for its own arm by the fixture's depot id and
-- found nothing there.
--
-- WHY THE FAILURE WAS THE LUCKY OUTCOME. The obvious "fix" - look the
-- arm up by run id instead of by depot - would have made it pass. A
-- green wall of fixture assertions would then have been reporting on
-- the flagship. That is the defect class this codebase convicts: a
-- check that reports about a world it did not run.
--
-- THE CAUSE WAS ALREADY ON THE RECORD. 0153's own header names the
-- symptom - "The Benchmark depot failed as a pair target because three
-- of those were missing (scenario bound to the flagship, ...)" - and
-- 0153 opens by quoting Chase: "If we see scenario A go to grid B ...
-- that would be a success." Scenario A going to grid B is precisely
-- what the harness permitted. The fixture was built to dodge the
-- hazard; nothing forbade it.
--
-- THE FIX, in two places:
--   1. public.ottoq_determinism_pair refuses a scenario whose depot is
--      not the depot it was told to run, BEFORE either arm starts.
--   2. twin.ottoq_grid_smoke states the same refusal in fixture terms,
--      and takes the arm id from the pair's OWN RETURN VALUE instead of
--      re-querying by depot. The lookup that hid the mismatch is gone.
--
-- WHY forces_recert = false, and how to check it. The guard raises
-- before any arm is created; it cannot reach a run that starts, so it
-- cannot move a canon. The certified path is unaffected as a matter of
-- record: all 487 cert_harness runs to date used scenario busy_day
-- (415) or normal_day (72), both bound to the flagship, and flagship
-- pairs pass p_depot = the flagship - so the guard is a no-op there.
-- Checkable two ways, and both are run below in db/checks:
--   (a) SELECT scenario_code, count(*) FROM ottoq_sim_runs
--        WHERE run_by='cert_harness' GROUP BY 1;  -- busy_day/normal_day only
--   (b) fire a flagship pair after applying and confirm it still starts.
-- A guard that refused a real cert would fail (b) immediately.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. The pair refuses a world it was not asked to run.
--    Anchored edit: two anchors, each asserted to occur exactly once.
-- ---------------------------------------------------------------------
DO $do$
DECLARE
  v_src text;
  v_anchor_decl CONSTANT text := '  v_complete boolean; v_outcome text;';
  v_anchor_loop CONSTANT text := '  FOR v_arm IN 1..2 LOOP';
  v_guard CONSTANT text :=
$g$  /* 0175: THE PAIR AND THE SCENARIO MUST NAME THE SAME WORLD.
     p_depot drives the fleet reset and both fingerprints; the run row's
     depot comes from the scenario (twin.ottoq_sim_start_run reads
     v_scenario.depot_id). Nothing made them agree, so a pair could reset
     and fingerprint depot A while ticking depot B and never say so.
     Refused before either arm is created, so a mismatch costs nothing
     and this guard can never alter a canon. */
  SELECT s.depot_id INTO v_scen_depot
    FROM public.ottoq_scenarios s
   WHERE s.scenario_code = p_scenario AND s.status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'determinism_pair: no active scenario %', p_scenario
      USING ERRCODE = 'P0001';
  END IF;
  IF v_scen_depot IS DISTINCT FROM p_depot THEN
    RAISE EXCEPTION 'determinism_pair: scenario % is bound to depot %, but the pair was told to run depot %. The arms would tick one world and be fingerprinted against another.',
      p_scenario, COALESCE(v_scen_depot::text, '(none)'), p_depot
      USING ERRCODE = 'P0001';
  END IF;

$g$;
  v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_determinism_pair';
  IF v_src IS NULL THEN RAISE EXCEPTION '0175: ottoq_determinism_pair not found'; END IF;

  IF position('0175: THE PAIR AND THE SCENARIO' in v_src) > 0 THEN
    RAISE NOTICE '0175: guard already present in ottoq_determinism_pair; nothing to do';
    RETURN;
  END IF;

  -- count, not presence: a second occurrence would make replace() ambiguous
  v_n := (length(v_src) - length(replace(v_src, v_anchor_decl, ''))) / length(v_anchor_decl);
  IF v_n <> 1 THEN RAISE EXCEPTION '0175: declare anchor occurs % times, expected 1', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_anchor_loop, ''))) / length(v_anchor_loop);
  IF v_n <> 1 THEN RAISE EXCEPTION '0175: loop anchor occurs % times, expected 1', v_n; END IF;

  v_src := replace(v_src, v_anchor_decl, v_anchor_decl || E'\n  v_scen_depot uuid;');
  v_src := replace(v_src, v_anchor_loop, v_guard || v_anchor_loop);

  EXECUTE v_src;
  RAISE NOTICE '0175: ottoq_determinism_pair guarded';
END
$do$;

-- ---------------------------------------------------------------------
-- 2. The smoke says the same thing in fixture terms, and stops looking
--    its own arm up by a depot the run may not carry.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION twin.ottoq_grid_smoke(
  p_seed      bigint      DEFAULT 424242,
  p_ticks     integer     DEFAULT 12,
  p_slug      text        DEFAULT 'grid-fixture',
  p_scenario  text        DEFAULT 'grid_smoke',
  p_sim_start timestamptz DEFAULT '2026-09-01 02:00:00+00'
)
RETURNS TABLE(check_code text, passed boolean, detail text)
LANGUAGE plpgsql
AS $function$
DECLARE
  v_depot uuid := md5('ottoq_grid_fixture:'||p_slug)::uuid;
  t0 timestamptz := clock_timestamp();
  v_arm uuid; v_secs numeric; v_rd jsonb;
  v_scen_depot uuid; v_pair jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE id = v_depot) THEN
    RAISE EXCEPTION 'grid fixture % does not exist - run twin.ottoq_grid_fixture_create(%)', p_slug, quote_literal(p_slug);
  END IF;

  /* 0175: the slug and the scenario must name the same world. The fixture
     check above proves the DEPOT exists; it proves nothing about where the
     run will be stamped, which comes from the scenario. Fired with slug
     'grid-0169-smoke' and scenario 'busy_day', this function spent 170 s
     ticking the flagship and called it a grid smoke. Refused up front, for
     nothing, rather than discovered late or - worse - not at all. */
  SELECT s.depot_id INTO v_scen_depot
    FROM public.ottoq_scenarios s
   WHERE s.scenario_code = p_scenario AND s.status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'grid smoke: no active scenario %', p_scenario USING ERRCODE = 'P0001';
  END IF;
  IF v_scen_depot IS DISTINCT FROM v_depot THEN
    RAISE EXCEPTION 'grid smoke: fixture % is depot %, but scenario % is bound to depot %. This would run that world and report it as this one.',
      p_slug, v_depot, p_scenario, COALESCE(v_scen_depot::text, '(none)')
      USING ERRCODE = 'P0001';
  END IF;

  /* 0175: the arm comes from the pair's own return value. The previous
     lookup - most recent cert_harness run AT THIS DEPOT - is what made the
     mismatch invisible: it could only ever miss, never mislead, and the
     tempting repair (look up by run id) would have turned a loud failure
     into a green report about the wrong depot. arm_b is the second arm,
     which is what the old ORDER BY started_at DESC selected. */
  v_pair := public.ottoq_determinism_pair(p_seed, p_ticks, p_scenario, v_depot, p_sim_start, 120);
  v_secs := round(EXTRACT(epoch FROM clock_timestamp() - t0)::numeric, 1);
  v_arm  := (v_pair->'arm_b'->>'run')::uuid;
  IF v_arm IS NULL THEN
    RAISE EXCEPTION 'grid smoke: the pair returned no second arm (outcome %)', COALESCE(v_pair->>'outcome','(none)');
  END IF;

  check_code := 'pair_wall_seconds'; passed := true;
  detail := v_secs||' s for two '||p_ticks||'-tick arms on '||p_slug||', seed '||p_seed||', arm '||v_arm::text; RETURN NEXT;

  RETURN QUERY SELECT a.check_code, a.passed, a.detail FROM twin.ottoq_grid_assert(v_arm) a;

  /* 0158: the deadline, every run. A run with no due times is reported as
     such rather than shown green - the same anti-vacuity rule as the power
     cap check. */
  v_rd := public.ottoq_kpi_dispatch_readiness(v_arm);
  check_code := 'assets_made_their_due_time';
  passed := ((v_rd->>'late')::int = 0 AND (v_rd->>'stranded')::int = 0);
  detail := CASE WHEN (v_rd->>'visits_with_due')::int = 0
                 THEN 'NO DUE TIMES in this run - not evidence about readiness ('
                      ||COALESCE(v_rd->>'visits_without_due','0')||' visits carried none)'
                 ELSE COALESCE(v_rd->>'on_time','0')||' on time, '||COALESCE(v_rd->>'late','0')||' late'
                      ||COALESCE(' (p50 '||(v_rd->>'p50_late_min')||' min, max '||(v_rd->>'max_late_min')||' min)','')
                      ||', '||COALESCE(v_rd->>'stranded','0')||' stranded, '
                      ||COALESCE(v_rd->>'no_charge_needed','0')||' needed no charge; on-time '
                      ||COALESCE(v_rd->>'on_time_pct','-')||'%' END;
  RETURN NEXT;
  RETURN;
END;
$function$;

COMMENT ON FUNCTION twin.ottoq_grid_smoke(bigint, int, text, text, timestamptz) IS
  '0153/0175: run a certification pair on a grid fixture and assert point-A-to-point-B behaviour. The slug and the scenario must name the same depot - refused up front if not, because the run is stamped with the SCENARIO''s depot and would otherwise report one world as another. The arm id comes from the pair''s return value, never from a lookup by depot.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_pair_and_the_scenario_must_name_the_same_world', false,
        'Pre-flight guard only. ottoq_determinism_pair and twin.ottoq_grid_smoke now refuse a scenario whose bound depot is not the depot they were told to run; the refusal raises before any arm is created, so it cannot reach a run that starts and cannot move a canon. Found when the 0169 grid smoke was fired with slug grid-0169-smoke and scenario busy_day: it ticked two arms of the flagship for 170 s under a grid-fixture headline and failed only because it then looked for its own arm at the fixture depot. The smoke also stops looking the arm up by depot and reads it from the pair verdict, so the repair that would have made that run pass silently is no longer available. No-op on the certified path: all 487 cert_harness runs used busy_day or normal_day, both bound to the flagship.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
