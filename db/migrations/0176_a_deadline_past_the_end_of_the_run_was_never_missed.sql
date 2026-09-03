-- =====================================================================
-- 0176  A deadline past the end of the run was never missed
-- =====================================================================
-- FOUND BY: the corrected 0169 grid smoke (db/checks/0084 §6). Two of
-- its sixteen assertions came back red on a run where the engine did
-- nothing wrong.
--
--   assets_made_their_due_time  FALSE - "0 on time, 0 late, 3 stranded"
--
-- All three of those visits carry dispatch_due_at = 2026-09-01 12:00:00
-- UTC. The run's horizon ends at 05:00:00 UTC. A deadline SEVEN HOURS
-- past the end of the run was counted as missed.
--
-- This is the third instance of one defect shape, and the fix is the
-- one 0170 already established:
--   0170  returns_unserved counted work due beyond the horizon
--   0172  a return stamped after the run ended never happened
--   0176  a dispatch deadline beyond the horizon was never missed
--
-- The rule, stated once: a run may only be judged on what it had time
-- to do. Work whose deadline lies past sim_clock_current is REPORTED
-- (due_beyond_horizon) rather than counted as failure - the same
-- anti-vacuity discipline the power-cap and injected-fault checks
-- already follow. A check that cannot pass on a short run is as useless
-- as one that cannot fail: both train the reader to ignore red.
--
-- WHAT THIS DOES NOT FIX, stated rather than buried
-- ---------------------------------------------------------------------
-- end_soc reads public.vehicles.current_soc, which is LIVE SHARED WORLD
-- STATE and not run-scoped - the trap recorded in db/checks/0080 §4.4.
-- Called inside the pair transaction it happens to be right; called
-- later against an archived run it silently reports whichever run last
-- touched the fleet. Both 'stranded' and 'no_charge_needed' depend on
-- it. This is the 0145/0053 defect class (unscoped reads of run-scoped
-- tables) and it deserves its own migration, not a hurried one: the
-- obvious run-scoped substitute, ottoq_telemetry_packets, is ordered by
-- created_at - a WALL CLOCK column - and trading an unscoped read for a
-- wall-clock ordering is not a fix (0144, 0051). So it is left in
-- place and made VISIBLE instead: the function now names its own
-- provenance in end_soc_source, so no reader can quote 'stranded'
-- without seeing where the number came from.
--
-- forces_recert = false. Read-only KPI function; touches no engine
-- function, no tick path, no rule. Nothing in the decide path calls it.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ottoq_kpi_dispatch_readiness(p_run uuid)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH h AS (
    SELECT r.sim_clock_current AS horizon
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run),
  v AS (
    SELECT vn.visit_id, vn.vehicle_id, vn.dispatch_due_at AS due,
           COALESCE(vn.target_soc, public.ottoq_default_target_soc()) AS tgt
      FROM public.ottoq_visit_needs vn, h
     WHERE vn.sim_run_id = p_run
       AND vn.dispatch_due_at IS NOT NULL
       /* 0176: only what the run had time to do */
       AND vn.dispatch_due_at <= h.horizon),
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
                           WHERE vn2.sim_run_id = p_run AND vn2.dispatch_due_at IS NULL),
    /* 0176: the deadlines this run could not have met, reported not counted */
    'due_beyond_horizon',(SELECT count(*) FROM public.ottoq_visit_needs vn3, h
                           WHERE vn3.sim_run_id = p_run
                             AND vn3.dispatch_due_at > h.horizon),
    'horizon',           (SELECT horizon FROM h),
    'end_soc_source',    'public.vehicles.current_soc - LIVE SHARED STATE, not run-scoped. Correct only while the run that wrote it is the last to have touched the fleet. See db/checks/0080 4.4 and migration 0176 header.')
    FROM r;
$function$;

COMMENT ON FUNCTION public.ottoq_kpi_dispatch_readiness(uuid) IS
  'Did the assets make their due time? 0176: only visits due at or before the run''s own horizon are judged; the rest are reported as due_beyond_horizon rather than counted late or stranded. end_soc still reads live fleet state - the function names that in end_soc_source rather than hiding it.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('a_deadline_past_the_end_of_the_run_was_never_missed', false,
        'Read-only KPI function. ottoq_kpi_dispatch_readiness judged a visit against a dispatch_due_at that could lie beyond the run''s own sim_clock_current - on the 0169 grid smoke, three visits due at 12:00 UTC were counted stranded by a run that ended at 05:00 UTC. Third instance of the shape 0170 and 0172 closed: a run may only be judged on what it had time to do. Deadlines past the horizon are now reported as due_beyond_horizon. Touches no engine function and no tick path. Separately, end_soc still reads live shared vehicles.current_soc (the 0080 4.4 trap); not fixed here because the run-scoped substitute is wall-clock ordered, so it is declared in end_soc_source instead and queued as its own migration.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
