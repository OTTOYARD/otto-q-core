-- =====================================================================
-- 0158  The sixth KPI: did the asset make its due time?
--       READ-ONLY measure + one grid row. forces_recert = false.
--       APPLIED 2:5x PM CT Sep 2 (safe mid-round: no decide-path change).
-- =====================================================================
-- THE GAP, not a bug. ottoq_visit_needs.dispatch_due_at is populated on
-- about half of all visits (27,059 of 53,805 rows all-time; 53 of 118 on
-- the last flagship arm) and NOTHING read it for conformance:
--   * The five canonical KPIs (CLAUDE.md 2.9) carry no tardiness term,
--     though 2.5 names tardiness as an objective term.
--   * SLA.007.redeployment_readiness never mentions dispatch_due_at. It
--     counts open blocking rows in exceptions/schedule_tasks - a
--     different, older subsystem - inside BEGIN ... EXCEPTION WHEN
--     OTHERS THEN v_open_exceptions := 0, so if those tables are absent
--     it silently reports "no blockers".
--   * ottoq_sla_violations has ZERO rows, ever, and no sim_run_id, so
--     even if it fired it could not be tied to a run - which breaks
--     "no number ships without a run ID".
-- We have been certifying that the engine is REPRODUCIBLE and never once
-- measuring whether it is GOOD.
--
-- MEASURED on flagship arm 70b2227e (started 9:39 AM CT), which passed
-- every determinism check and counted toward round 7's six green:
--   visits with a due time  53
--   on time                 36
--   LATE                     9   p50 165 min, p95 297 min, max 345 min
--   needed no charge         8   (ended at or above target)
--   stranded                 0
--   on-time rate            80%
--
-- CORRECTION recorded, because the first cut of this measure was wrong
-- and the wrong number was the scarier one: counting the 8
-- no-charge-needed visits as misses gave "17 of 53 (32%)". They are not
-- misses - those vehicles arrived at or above target. The honest figure
-- is 9 of 53 late (17%), none stranded. The guard is in the function.
--
-- DEFINITION, stated so it can be argued with. For a visit with due time
-- D and target SoC T on vehicle X in run R:
--   ready_at := earliest ended_at among R's ocpp_sessions for X whose
--               soc_end >= T
--   on_time  := ready_at <= D          late := ready_at > D
--   no_charge_needed := no such session AND X ends the run >= T
--   stranded := no such session AND X ends the run < T
-- Naive and swappable (CLAUDE.md 2.7): it reads charging sessions only,
-- so a visit whose readiness turns on a non-energy operation is out of
-- scope until the SDR path carries per-operation completion. A
-- limitation recorded, not hidden.

CREATE OR REPLACE FUNCTION public.ottoq_kpi_dispatch_readiness(p_run uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH v AS (
    SELECT vn.visit_id, vn.vehicle_id, vn.dispatch_due_at AS due,
           COALESCE(vn.target_soc, public.ottoq_default_target_soc()) AS tgt
      FROM public.ottoq_visit_needs vn
     WHERE vn.sim_run_id = p_run AND vn.dispatch_due_at IS NOT NULL),
  r AS (
    SELECT v.*,
           (SELECT min(cs.ended_at) FROM public.ocpp_sessions cs
             WHERE cs.sim_run_id = p_run AND cs.vehicle_id = v.vehicle_id
               AND cs.soc_end >= v.tgt) AS ready_at,
           (SELECT ve.current_soc FROM public.vehicles ve WHERE ve.id = v.vehicle_id) AS end_soc
      FROM v)
  SELECT jsonb_build_object(
    'sim_run_id',        p_run,
    'visits_with_due',   count(*),
    'on_time',           count(*) FILTER (WHERE ready_at IS NOT NULL AND ready_at <= due),
    'late',              count(*) FILTER (WHERE ready_at IS NOT NULL AND ready_at >  due),
    'no_charge_needed',  count(*) FILTER (WHERE ready_at IS NULL AND end_soc >= tgt),
    'stranded',          count(*) FILTER (WHERE ready_at IS NULL AND end_soc <  tgt),
    'p50_late_min',      round(percentile_cont(0.5) WITHIN GROUP (
                               ORDER BY EXTRACT(epoch FROM ready_at - due)/60.0)
                               FILTER (WHERE ready_at > due)::numeric, 1),
    'p95_late_min',      round(percentile_cont(0.95) WITHIN GROUP (
                               ORDER BY EXTRACT(epoch FROM ready_at - due)/60.0)
                               FILTER (WHERE ready_at > due)::numeric, 1),
    'max_late_min',      round(max(EXTRACT(epoch FROM ready_at - due)/60.0)
                               FILTER (WHERE ready_at > due)::numeric, 1),
    'on_time_pct',       CASE WHEN count(*) FILTER (WHERE NOT (ready_at IS NULL AND end_soc >= tgt)) = 0 THEN NULL
                              ELSE round(100.0 * count(*) FILTER (WHERE ready_at IS NOT NULL AND ready_at <= due)
                                   / count(*) FILTER (WHERE NOT (ready_at IS NULL AND end_soc >= tgt)), 1) END,
    'visits_without_due',(SELECT count(*) FROM public.ottoq_visit_needs vn2
                           WHERE vn2.sim_run_id = p_run AND vn2.dispatch_due_at IS NULL))
    FROM r;
$function$;

-- The grid smoke prints readiness on every twenty-second run, so the
-- deadline is in front of us on each iteration instead of never.
CREATE OR REPLACE FUNCTION twin.ottoq_grid_smoke(
  p_seed bigint DEFAULT 424242, p_ticks integer DEFAULT 12,
  p_slug text DEFAULT 'grid-fixture'::text, p_scenario text DEFAULT 'grid_smoke'::text,
  p_sim_start timestamp with time zone DEFAULT '2026-09-01 02:00:00+00'::timestamp with time zone)
 RETURNS TABLE(check_code text, passed boolean, detail text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_depot uuid := md5('ottoq_grid_fixture:'||p_slug)::uuid;
  t0 timestamptz := clock_timestamp();
  v_arm uuid; v_secs numeric; v_rd jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE id = v_depot) THEN
    RAISE EXCEPTION 'grid fixture % does not exist - run twin.ottoq_grid_fixture_create(%)', p_slug, quote_literal(p_slug);
  END IF;
  PERFORM public.ottoq_determinism_pair(p_seed, p_ticks, p_scenario, v_depot, p_sim_start, 120);
  v_secs := round(EXTRACT(epoch FROM clock_timestamp() - t0)::numeric, 1);
  SELECT r.sim_run_id INTO v_arm FROM public.ottoq_sim_runs r
   WHERE r.depot_id = v_depot AND r.run_by = 'cert_harness'
   ORDER BY r.started_at DESC, r.sim_run_id DESC LIMIT 1;
  check_code := 'pair_wall_seconds'; passed := true;
  detail := v_secs||' s for two '||p_ticks||'-tick arms on '||p_slug||', seed '||p_seed||', arm '||v_arm::text; RETURN NEXT;

  RETURN QUERY SELECT a.check_code, a.passed, a.detail FROM twin.ottoq_grid_assert(v_arm) a;

  /* 0158: the deadline, every run. A run with no due times is reported as
     such rather than shown green - the same anti-vacuity rule as the
     power cap check. */
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

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_sixth_kpi_did_the_asset_make_its_due_time', false,
        'Read-only: ottoq_kpi_dispatch_readiness measures visits against ottoq_visit_needs.dispatch_due_at, which nothing read before - SLA.007 never mentions it and ottoq_sla_violations has zero rows and no sim_run_id. The grid smoke now prints readiness every run. No decide-path change.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
