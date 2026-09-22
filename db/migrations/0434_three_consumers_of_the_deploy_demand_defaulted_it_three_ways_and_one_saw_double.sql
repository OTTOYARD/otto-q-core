-- migration-version: PENDING
-- migration-name:    three_consumers_of_the_deploy_demand_defaulted_it_three_ways_and_one_saw_double
--
-- 0434  **The work side's deploy demand is read by three engine functions, which resolved its default three
--       different ways. On busy_day the service flow saw exactly twice the demand the dispatcher deploys to,
--       all day, and fast-tracked every eligible vehicle past its optional services to meet it.**
--       Evidence: FINDINGS G162, `0432` §4.1, and the measurement below. Applied with `0433`, so one recert
--       sweep covers both.
--
-- ══ §1 THE THREE RESOLUTIONS, FROM SOURCE ═════════════════════════════════════
--
--   twin.ottoq_sim_auto_dispatch_tick   scenario target_deployed_fraction, else 0.90   (the DEPLOYER)
--                                        target = FLOOR(fleet x fraction(hour_ct, peak) x dispatch_rate_multiplier)
--   public.ottoq_decide_tick             scenario target_deployed_fraction, else 0.55
--   twin.ottoq_sim_advance_service_flow  a fixed 0.90, no scenario, no multiplier
--
-- The agent used to overwrite the dial at tick 1 and so papered over the disagreement; since `0432` it cannot.
--
-- ══ §2 WHAT IT COST, MEASURED ON RUN 7a42982a (busy_day, twin depot, 04:12-07:02 CT sim) ══════════════
--
--   service_flow's STEP 1.5 ("deploy-pressure fast-track past OPTIONAL wash") compares the dispatcher's own
--   deployed count with ITS target. busy_day's demand is 0.45; service_flow read 0.90. Hour by hour its target
--   is exactly double the dispatcher's -- 7:00 CT 75 vs 37, 10:00 100 vs 50, 17:00 104 vs 52 -- so, with
--   deployed tracking the dispatcher's target, "deploy pressure" was true all day:
--
--     44 twin.deploy_pressure_fasttrack events, 85 vehicles moved from charge_complete_holding to
--     staged_awaiting_service/need_deploy past their optional services, in the first three sim-hours.
--
--   Vehicles skipped optional work to meet a demand that did not exist, and were then staged for a release the
--   dispatcher never needed.
--
-- ══ §3 WHAT THIS DOES ═══════════════════════════════════════════════════════
--
--   (A) `public.ottoq_deploy_peak_fraction(run)` -- the dispatcher's resolution, verbatim: the run's dial, else
--       the scenario's target_deployed_fraction, else 0.90.
--   (B) `public.ottoq_deploy_target_now(run, depot, clock)` -- the dispatcher's target, verbatim:
--       FLOOR(autonomous fleet at depot x ottoq_deploy_target_fraction(hour CT, (A)) x dispatch_rate_multiplier).
--   (C) service_flow's pressure test reads (B). decide_tick's demand line reads (A) for its fraction (its own
--       formula otherwise unchanged -- it counts deployed by vehicle state, not dispatch, and carries no
--       multiplier; aligning those is a separate change). The dispatcher is not touched: it is the reference.
--   (D) G164. The agent's grounding block reads (A) and (B) instead of its own copy of the arithmetic, and
--       publishes `deploy_gap = target − deployed`. On run 7a42982a's first v19 pass the agent raised
--       `deploy_surge_catchup` "to clear the 67-vehicle service backlog" with deployed 4 above target 3, where
--       the dial -- the fraction of a POSITIVE deploy gap released per tick -- does nothing; edge function v20
--       tells it so. Not read by any certification path.
--   P3 proves (A) and (B) reproduce the dispatcher's own arithmetic, hour by hour, before anything moves.
--
-- ══ §4 forces_recert TRUE -- service_flow and decide_tick move in every cert arm whose scenario sets a demand. ══

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0434 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0434 P0: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0434 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: md5 guards (decide_tick is guarded at its POST-0433 body: this file applies after 0433) ──
DO $$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN SELECT n.nspname, p.proname, md5(p.prosrc) AS m FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE (n.nspname, p.proname) IN (('public','ottoq_decide_tick'), ('twin','ottoq_sim_advance_service_flow'),
                                             ('twin','ottoq_sim_auto_dispatch_tick'), ('public','ottoq_agent_board_grounding'))
  LOOP
    v_n := v_n + 1;
    IF (r.proname = 'ottoq_decide_tick'              AND r.m <> 'c6bff9868c8982744491e597cd7c3f49')
    OR (r.proname = 'ottoq_sim_advance_service_flow' AND r.m <> '7d6dddd76e5d8fe7aa9cb4d6cd6fdbd9')
    OR (r.proname = 'ottoq_sim_auto_dispatch_tick'   AND r.m <> 'e6cccbe3b00d69dd0e07cb3c24378778')
    OR (r.proname = 'ottoq_agent_board_grounding'    AND r.m <> '41d78cddb8d9dba0e91e9e46aa156ebf') THEN
      RAISE EXCEPTION '0434 P1: %.% prosrc md5 is % -- apply 0433 first, or it changed since this file read it',
        r.nspname, r.proname, r.m;
    END IF;
  END LOOP;
  IF v_n <> 4 THEN RAISE EXCEPTION '0434 P1: expected 4 functions, found %', v_n; END IF;
END $$;

-- ── P2: anchors ──
DO $$
DECLARE v_src text; v_n int; v_a text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_decide_tick';
  v_a := $a$ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',COALESCE(v_target_pct, 0.90))$a$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0434 P2: decide_tick demand anchor matched % times', v_n; END IF;

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_service_flow';
  v_a := $a$v_target   := FLOOR(v_fleet * ottoq_deploy_target_fraction(v_hour, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',0.90)));$a$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0434 P2: service_flow target anchor matched % times', v_n; END IF;
END $$;

-- ── (A) + (B): THE RESOLVERS ──
CREATE OR REPLACE FUNCTION public.ottoq_deploy_peak_fraction(p_sim_run_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $fn$
  -- 0434. The work side's peak deploy demand, resolved EXACTLY as twin.ottoq_sim_auto_dispatch_tick -- the
  -- function that actually deploys -- resolves it: the run's dial, else the run's scenario's
  -- target_deployed_fraction (scenario NULL -> 'normal_day'), else 0.90.
  SELECT public.ottoq_policy_get(p_sim_run_id, 'deploy_peak_fraction',
           COALESCE((SELECT (s.fleet_overrides->>'target_deployed_fraction')::numeric
                       FROM public.ottoq_sim_scenarios s
                      WHERE s.scenario_code = COALESCE((SELECT r.scenario_code FROM public.ottoq_sim_runs r
                                                         WHERE r.sim_run_id = p_sim_run_id), 'normal_day')
                      LIMIT 1), 0.90));
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_deploy_target_now(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $fn$
  -- 0434. The dispatcher's deploy target, verbatim: FLOOR(autonomous fleet at the depot x the hour-of-day
  -- fraction at the resolved peak x the scenario's dispatch_rate_multiplier).
  SELECT FLOOR(
           (SELECT count(*) FROM public.vehicles v WHERE v.category = 'autonomous' AND v.home_depot_id = p_depot_id)
         * public.ottoq_deploy_target_fraction(EXTRACT(HOUR FROM p_clock AT TIME ZONE 'America/Chicago')::int,
                                               public.ottoq_deploy_peak_fraction(p_sim_run_id))
         * COALESCE((SELECT (s.fleet_overrides->>'dispatch_rate_multiplier')::numeric
                       FROM public.ottoq_sim_scenarios s
                      WHERE s.scenario_code = COALESCE((SELECT r.scenario_code FROM public.ottoq_sim_runs r
                                                         WHERE r.sim_run_id = p_sim_run_id), 'normal_day')
                      LIMIT 1), 1.0))::integer;
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_deploy_peak_fraction(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ottoq_deploy_target_now(uuid, uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_deploy_peak_fraction(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_deploy_target_now(uuid, uuid, timestamptz) TO authenticated, service_role;

-- ── P3: THE RESOLVERS REPRODUCE THE DISPATCHER, for every scenario and every hour, before anything moves ──
DO $$
DECLARE v_bad int; v_run uuid; v_scn text;
BEGIN
  -- recompute the dispatcher's own arithmetic independently of the resolver, on the newest twin run (its real
  -- scenario, its real dial), for all 24 hours -- written out from twin.ottoq_sim_auto_dispatch_tick's lines, not
  -- from the resolver
  SELECT sim_run_id, scenario_code INTO v_run, v_scn FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE WARNING '0434 P3: no twin run to compare on; skipped'; RETURN; END IF;
  SELECT count(*) INTO v_bad
    FROM generate_series(0, 23) h,
         LATERAL (SELECT (SELECT count(*) FROM public.vehicles v
                           WHERE v.category = 'autonomous' AND v.home_depot_id = '11111111-1111-1111-1111-111111111111') AS fleet) f,
         LATERAL (SELECT s.fleet_overrides FROM public.ottoq_sim_scenarios s
                   WHERE s.scenario_code = COALESCE(v_scn, 'normal_day') LIMIT 1) s
   WHERE public.ottoq_deploy_target_now(v_run, '11111111-1111-1111-1111-111111111111',
           (date_trunc('day', now() AT TIME ZONE 'America/Chicago') + make_interval(hours => h)) AT TIME ZONE 'America/Chicago')
         IS DISTINCT FROM
         FLOOR(f.fleet * public.ottoq_deploy_target_fraction(h,
                 public.ottoq_policy_get(v_run, 'deploy_peak_fraction',
                   COALESCE((s.fleet_overrides->>'target_deployed_fraction')::numeric, 0.90)))
               * COALESCE((s.fleet_overrides->>'dispatch_rate_multiplier')::numeric, 1.0))::integer;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0434 P3: on run % (%) the resolver disagrees with the dispatcher''s arithmetic at % of 24 hours',
      v_run, v_scn, v_bad;
  END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0434_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname, p.proname) IN (('public','ottoq_decide_tick'), ('twin','ottoq_sim_advance_service_flow'));

-- ── (C): THE TWO CONSUMERS READ THE RESOLVERS ──
DO $$
DECLARE v_oid oid; v_def text; v_new text; v_a text; v_r text;
BEGIN
  SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_decide_tick';
  v_def := pg_get_functiondef(v_oid);
  v_a := $a$ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',COALESCE(v_target_pct, 0.90))$a$;
  v_r := $r$public.ottoq_deploy_peak_fraction(p_sim_run_id) /* 0434: the dispatcher's resolution, not this function's 0.55 */$r$;
  IF (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 THEN RAISE EXCEPTION '0434 (C): decide_tick anchor not unique'; END IF;
  v_new := replace(v_def, v_a, v_r);
  IF length(v_new) - length(v_def) <> length(v_r) - length(v_a) THEN RAISE EXCEPTION '0434 (C): decide_tick byte delta'; END IF;
  EXECUTE v_new;

  SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_service_flow';
  v_def := pg_get_functiondef(v_oid);
  v_a := $a$v_target   := FLOOR(v_fleet * ottoq_deploy_target_fraction(v_hour, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',0.90)));$a$;
  v_r := $r$v_target   := public.ottoq_deploy_target_now(p_sim_run_id, p_depot_id, p_sim_clock_now);  -- 0434: the dispatcher's target, not a fixed 0.90$r$;
  IF (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 THEN RAISE EXCEPTION '0434 (C): service_flow anchor not unique'; END IF;
  v_new := replace(v_def, v_a, v_r);
  IF length(v_new) - length(v_def) <> length(v_r) - length(v_a) THEN RAISE EXCEPTION '0434 (C): service_flow byte delta'; END IF;
  EXECUTE v_new;
END $$;

-- ── (D): THE AGENT'S GROUNDING READS THE RESOLVERS AND PUBLISHES THE GAP (G164) ──
DO $$
DECLARE v_oid oid; v_def text; v_new text; v_a1 text; v_r1 text; v_a2 text; v_r2 text;
BEGIN
  SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board_grounding';
  v_def := pg_get_functiondef(v_oid);
  v_a1 := $a$v_peak := ottoq_policy_get(p_sim_run_id, 'deploy_peak_fraction', COALESCE(v_target_pct, 0.90));$a$;
  v_r1 := $r$v_peak := public.ottoq_deploy_peak_fraction(p_sim_run_id);  -- 0434$r$;
  v_a2 := $a$'deploy_target_now', FLOOR(v_fleet * ottoq_deploy_target_fraction(v_hour, v_peak) * v_mult),$a$;
  v_r2 := $r$'deploy_target_now', public.ottoq_deploy_target_now(p_sim_run_id, p_depot_id, p_clock),
      'deploy_gap', public.ottoq_deploy_target_now(p_sim_run_id, p_depot_id, p_clock) - v_deployed,  -- 0434 / G164
      'deploy_gap_note', 'target minus deployed. deploy_surge_catchup releases a share of a POSITIVE gap per tick; '
                         'at a gap of 0 or less it does nothing.',$r$;
  IF (length(v_def) - length(replace(v_def, v_a1, ''))) / length(v_a1) <> 1
  OR (length(v_def) - length(replace(v_def, v_a2, ''))) / length(v_a2) <> 1 THEN
    RAISE EXCEPTION '0434 (D): a grounding anchor is not unique';
  END IF;
  v_new := replace(replace(v_def, v_a1, v_r1), v_a2, v_r2);
  IF length(v_new) - length(v_def) <> (length(v_r1) - length(v_a1)) + (length(v_r2) - length(v_a2)) THEN
    RAISE EXCEPTION '0434 (D): grounding byte delta';
  END IF;
  EXECUTE v_new;
END $$;

-- ── V1: no consumer resolves the demand on its own any more ──
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE (n.nspname, p.proname) IN (('public','ottoq_decide_tick'), ('twin','ottoq_sim_advance_service_flow'))
     AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ $re$ottoq_policy_get\([^)]*'deploy_peak_fraction'$re$;
  IF v_n <> 0 THEN RAISE EXCEPTION '0434 V1: % consumer(s) still resolve deploy_peak_fraction themselves', v_n; END IF;
END $$;

-- ── V2: the grounding's target equals the dispatcher's and carries the gap ──
DO $$
DECLARE v_run uuid; v_clock timestamptz; g jsonb;
BEGIN
  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND run_by NOT IN ('cert_harness','benchmark') AND tick_count > 50
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE WARNING '0434 V2: no twin demo run to probe; skipped'; RETURN; END IF;
  g := public.ottoq_agent_board_grounding(v_run, '11111111-1111-1111-1111-111111111111', v_clock) -> 'work_side_demand';
  IF (g->>'deploy_target_now')::int IS DISTINCT FROM public.ottoq_deploy_target_now(v_run, '11111111-1111-1111-1111-111111111111', v_clock)
     OR NOT g ? 'deploy_gap'
     OR (g->>'deploy_gap')::int IS DISTINCT FROM (g->>'deploy_target_now')::int - (g->>'deployed_now')::int THEN
    RAISE EXCEPTION '0434 V2: grounding work_side_demand is inconsistent: %', g;
  END IF;
END $$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0434_three_consumers_of_the_deploy_demand_defaulted_it_three_ways_and_one_saw_double',
  true,
  'G162. deploy_peak_fraction was resolved three ways: the dispatcher (scenario, else 0.90, with the dispatch '
  'multiplier), ottoq_decide_tick (scenario, else 0.55) and twin.ottoq_sim_advance_service_flow (a fixed 0.90). On '
  'busy_day (0.45) service_flow''s target was exactly twice the dispatcher''s at every hour, so its deploy-pressure '
  'fast-track fired all day: run 7a42982a, 04:12-07:02 CT, 44 events moving 85 vehicles past their optional '
  'services. ottoq_deploy_peak_fraction and ottoq_deploy_target_now reproduce the dispatcher verbatim (P3 proves it '
  'hour by hour); service_flow reads the target, decide_tick the fraction, and the agent''s grounding reads both and '
  'publishes deploy_gap (G164). TRUE: service_flow and decide_tick move in cert arms; the grounding is not read by one.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §5 AFTER APPLYING ═════════════════════════════════════════════════════════
--
-- On the next busy_day run: twin.deploy_pressure_fasttrack events should fall from ~15/sim-hour (7a42982a) to the
-- hours when deployed genuinely trails the dispatcher's own target.
--   SELECT count(*), sum((payload->>'fasttracked')::int) FROM ottoq_events
--    WHERE sim_run_id = '<run>' AND event_type = 'twin.deploy_pressure_fasttrack';
