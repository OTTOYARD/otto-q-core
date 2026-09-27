-- migration-version: 20260926221345
-- migration-name:    the_wait_for_a_charger_is_measured_beside_kpi_5
--
-- 0501  **KPI 5 could not see a queue for chargers (G233).** `db/checks/0371`.
--
-- ══ §1 WHAT WAS MISSING ═════════════════════════════════════════════════════════════════════════════════════════
--
--   KPI 5, `p95_time_to_service`, measures a recall's completion to the FIRST operation active (CLAUDE.md 2.9). On a
--   busy day that first operation is a digital or cabin task that starts at once, so on validation run `394e1e83` it
--   read 0.7 minutes while about 40 cars waited for a charger from 10:00 AM on. The KPI is right by its definition and
--   silent on the wait that decides a busy day. Its definition does not change here: the five stay the five.
--
-- ══ §2 WHAT THIS ADDS ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_kpi_charge_wait(p_run)`, a companion beside the five in the pattern of
--   `ottoq_kpi_dispatch_readiness`: for every visit of the run that arrived owing a charge, the time from its arrival to
--   its first charging session (before the car's next dispatch). A visit still owed at the run's clock is WAITING, and
--   its wait so far is a floor on its true wait, never a finished wait. Reported: visits, charged, waiting, and closed
--   without a session, the charged waits' p50/p95/max, the waiting visits' p50/max so far, and the p95 over both with
--   the waiting ones at their floor (itself a floor on the true p95).
--
--   Read on `394e1e83`: 135 visits, 92 charged (p50 16.2, p95 154.4, max 190.9 minutes), 42 waiting at the stop (p50
--   142.3, max 232.2 so far), 1 closed without a session, p95 floor over all 198.2 minutes.
--
-- ══ §3 forces_recert FALSE ══════════════════════════════════════════════════════════════════════════════════════
--
--   A new read-only function with no caller in the certified path.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0501 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the name is free ──
DO $premises$
BEGIN
  IF to_regprocedure('public.ottoq_kpi_charge_wait(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0501 P2: public.ottoq_kpi_charge_wait(uuid) already exists';
  END IF;
END $premises$;

CREATE FUNCTION public.ottoq_kpi_charge_wait(p_run uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0501 (G233): the wait for a charger, beside KPI 5 and not inside it. A visit counts when it
  -- arrived owing a charge. Its wait runs from its arrival to its first charging session before the
  -- car's next dispatch. A visit still owed at the run's clock is waiting, and its wait so far is a
  -- floor, never a finished wait.
  WITH h AS (
    SELECT r.sim_run_id AS run, r.sim_clock_current AS horizon
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run),
  v AS (
    SELECT vn.visit_id, vn.vehicle_id, vn.arrived_at,
           (SELECT a FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge' LIMIT 1) AS ca
      FROM public.ottoq_visit_needs vn, h
     WHERE vn.sim_run_id = h.run AND vn.arrived_at IS NOT NULL AND vn.arrived_at <= h.horizon
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge')),
  w AS (
    SELECT v.*, h.horizon,
           (SELECT min(o.started_at) FROM public.ocpp_sessions o
             WHERE o.sim_run_id = h.run AND o.vehicle_id = v.vehicle_id AND o.started_at >= v.arrived_at
               AND o.started_at < COALESCE((SELECT min(d.dispatched_at) FROM public.ottoq_vehicle_dispatches d
                                             WHERE d.sim_run_id = h.run AND d.vehicle_id = v.vehicle_id
                                               AND d.dispatched_at > v.arrived_at), 'infinity')) AS first_plug
      FROM v, h),
  x AS (
    SELECT w.*,
           CASE WHEN w.first_plug IS NOT NULL THEN 'charged'
                WHEN COALESCE(w.ca->>'status', 'open') NOT IN ('done','skipped','cancelled') THEN 'waiting'
                ELSE 'closed_without_a_session' END AS outcome,
           EXTRACT(epoch FROM COALESCE(w.first_plug, w.horizon) - w.arrived_at) / 60.0 AS m
      FROM w)
  SELECT jsonb_build_object(
    'sim_run_id',               p_run,
    'horizon',                  (SELECT horizon FROM h),
    'visits_owing_a_charge',    count(*),
    'charged',                  count(*) FILTER (WHERE outcome = 'charged'),
    'waiting_at_horizon',       count(*) FILTER (WHERE outcome = 'waiting'),
    'closed_without_a_session', count(*) FILTER (WHERE outcome = 'closed_without_a_session'),
    'p50_wait_min',             round(percentile_cont(0.5)  WITHIN GROUP (ORDER BY m) FILTER (WHERE outcome = 'charged')::numeric, 1),
    'p95_wait_min',             round(percentile_cont(0.95) WITHIN GROUP (ORDER BY m) FILTER (WHERE outcome = 'charged')::numeric, 1),
    'max_wait_min',             round((max(m) FILTER (WHERE outcome = 'charged'))::numeric, 1),
    'waiting_p50_so_far_min',   round(percentile_cont(0.5)  WITHIN GROUP (ORDER BY m) FILTER (WHERE outcome = 'waiting')::numeric, 1),
    'waiting_max_so_far_min',   round((max(m) FILTER (WHERE outcome = 'waiting'))::numeric, 1),
    'p95_wait_floor_min',       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY m) FILTER (WHERE outcome <> 'closed_without_a_session')::numeric, 1),
    'meaning', 'Minutes from a visit''s arrival to its first charging session, for visits that arrived owing a '
               'charge. The p50/p95/max are over visits that charged. A visit still owed at the horizon is waiting: '
               'its minutes so far are a floor on its wait, and p95_wait_floor_min, which counts them at that floor, '
               'is a floor on the true p95. A companion to KPI 5 (p95_time_to_service), whose definition is unchanged.')
    FROM x;
$function$;

-- The schema's default privileges also grant a new function to anon. ottoq_kpi_five is not anon's, and neither is
-- this.
REVOKE ALL ON FUNCTION public.ottoq_kpi_charge_wait(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_kpi_charge_wait(uuid) TO authenticated, service_role;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f regprocedure := 'public.ottoq_kpi_charge_wait(uuid)'::regprocedure;
  v_run uuid; j jsonb;
BEGIN
  -- V1: stable, security definer, the search path, and execute for authenticated and service_role only.
  IF (SELECT provolatile FROM pg_proc WHERE oid = v_f) <> 's' OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_f) <> 'search_path=twin, ottoq, public, extensions'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
        <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0501 V1: ottoq_kpi_charge_wait is not stable, security definer, or privileged as declared';
  END IF;
  -- V2: on the newest operator run the three outcomes (charged, waiting, closed without a session) sum to the visits.
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.validation_status IS NULL AND r.sim_clock_current IS NOT NULL ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    j := public.ottoq_kpi_charge_wait(v_run);
    IF (j->>'charged')::int + (j->>'waiting_at_horizon')::int + (j->>'closed_without_a_session')::int
       <> (j->>'visits_owing_a_charge')::int THEN
      RAISE EXCEPTION '0501 V2: the outcomes do not sum to the visits: %', j;
    END IF;
  END IF;
END $verify$;

-- Rollback: DROP FUNCTION public.ottoq_kpi_charge_wait(uuid).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0501_the_wait_for_a_charger_is_measured_beside_kpi_5', false,
  'New read-only public.ottoq_kpi_charge_wait(run): minutes from a visit''s arrival to its first charging session for '
  'visits owing a charge, with visits still waiting at the horizon counted at their floor. No caller in the certified '
  'path.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
