-- migration-version: 20260819054500
-- migration-name:    canonical_kpis
-- 0044 — THE FIVE CANONICAL KPIs (CLAUDE.md 2.9) + the reproducibility key
--
-- Run 2 / Phase C6. Verified on the C3 scratch instance (db/checks/
-- 0044_kpi_certification.sql). NOT YET APPLIED TO PRODUCTION.
--
-- Five views over the EXISTING substrate — dispatches, bookings, energy
-- snapshots, events, tasks, cost attribution — identical across every policy
-- and pack, plus ottoq_kpi_five(run) assembling all five deterministically.
-- ottoq_run_archives is EXTENDED (not paralleled) with the reproducibility key
-- (policy_name, pack_id, scenario_seed, config_hash).
--
-- KPI definitions are stated in each view's COMMENT; where a definition had to
-- choose a substrate reading, the choice and its bias are stated rather than
-- hidden. Additive only: no existing object altered beyond two new columns on
-- ottoq_run_archives. Views are relkind 'v' — invisible to the purge walker
-- (it scans relkind='r') and carry no run-scope registry duty.

-- ============================================================================
-- KPI 1 — asset_hours_available_per_day
-- ============================================================================
CREATE OR REPLACE VIEW public.ottoq_kpi_asset_hours_available_per_day
  WITH (security_invoker = true) AS
SELECT d.sim_run_id,
       date_trunc('day', d.dispatched_at)::date AS day,
       round(SUM(
         EXTRACT(EPOCH FROM (COALESCE(d.actual_return_at,
                                      d.scheduled_return_at) - d.dispatched_at))
       )::numeric / 3600.0, 2) AS asset_hours_available,
       count(DISTINCT d.vehicle_id) AS assets_counted
  FROM public.ottoq_vehicle_dispatches d
 GROUP BY d.sim_run_id, date_trunc('day', d.dispatched_at)::date;
COMMENT ON VIEW public.ottoq_kpi_asset_hours_available_per_day IS
  'KPI 1 (2.9): hours assets were out doing work, per day — sum of dispatch '
  'durations from ottoq_vehicle_dispatches (actual return preferred, scheduled '
  'as fallback for still-open dispatches; bias: counts deployed hours only, '
  'not ready-idle hours at the depot).';

-- ============================================================================
-- KPI 2 — service_point_turns_per_point_per_day
-- ============================================================================
CREATE OR REPLACE VIEW public.ottoq_kpi_service_point_turns
  WITH (security_invoker = true) AS
SELECT b.sim_run_id,
       date_trunc('day', lower(b.during))::date AS day,
       count(*) FILTER (WHERE b.state IN ('done','released','interrupted'))
         AS turns_completed,
       count(DISTINCT b.stall_id) AS points_used,
       round(count(*) FILTER (WHERE b.state IN ('done','released','interrupted'))::numeric
             / GREATEST(1, count(DISTINCT b.stall_id)), 2)
         AS turns_per_point_per_day
  FROM public.ottoq_stall_bookings b
 GROUP BY b.sim_run_id, date_trunc('day', lower(b.during))::date;
COMMENT ON VIEW public.ottoq_kpi_service_point_turns IS
  'KPI 2 (2.9): completed booking turns per service point per day, from the '
  'forward calendar (ottoq_stall_bookings). A turn = a booking that reached a '
  'terminal used state; denominator = points actually used that day (bias: '
  'idle points do not dilute the figure — state it when quoting).';

-- ============================================================================
-- KPI 3 — peak_site_kw, 15-minute rolling (matches demand billing)
-- ============================================================================
CREATE OR REPLACE VIEW public.ottoq_kpi_peak_site_kw
  WITH (security_invoker = true) AS
WITH rolling AS (
  SELECT s.sim_run_id, s."timestamp",
         avg(s.grid_import_kw) OVER (
           PARTITION BY s.sim_run_id, s.depot_id
           ORDER BY s."timestamp"
           RANGE BETWEEN interval '15 minutes' PRECEDING AND CURRENT ROW
         ) AS kw_15min
    FROM public.site_energy_snapshots s
)
SELECT sim_run_id,
       round(max(kw_15min)::numeric, 1) AS peak_site_kw_15min,
       count(*) AS snapshots
  FROM rolling
 GROUP BY sim_run_id;
COMMENT ON VIEW public.ottoq_kpi_peak_site_kw IS
  'KPI 3 (2.9): maximum 15-minute rolling average of grid import — the demand-'
  'billing reading. Cross-check column site_energy_snapshots.peak_demand_kw_15min '
  'exists from the twin; this view recomputes from raw snapshots so the KPI '
  'never depends on a writer having maintained a derived column.';

-- ============================================================================
-- KPI 4 — touch_events_per_turn
-- ============================================================================
CREATE OR REPLACE VIEW public.ottoq_kpi_touch_events_per_turn
  WITH (security_invoker = true) AS
WITH touches AS (
  SELECT e.sim_run_id, count(*) AS n
    FROM public.ottoq_events e
   WHERE e.actor_type IN ('command_center_operator','depot_staff','technician',
                          'charging_tech','cleaning_tech','maintenance_tech',
                          'yard_supervisor','ops_manager')
   GROUP BY e.sim_run_id
), overrides AS (
  SELECT d.sim_run_id, count(*) AS n
    FROM public.ottoq_decisions d
   WHERE d.overridden OR d.override_id IS NOT NULL
   GROUP BY d.sim_run_id
), confirms AS (
  SELECT NULL::uuid AS sim_run_id, count(*) AS n
    FROM public.schedule_tasks t
   WHERE t.confirmed_by_user_id IS NOT NULL OR t.tech_override_at IS NOT NULL
), turns AS (
  SELECT b.sim_run_id,
         count(*) FILTER (WHERE b.state IN ('done','released','interrupted')) AS n
    FROM public.ottoq_stall_bookings b
   GROUP BY b.sim_run_id
)
SELECT t.sim_run_id,
       COALESCE(tc.n,0) + COALESCE(o.n,0)
         + CASE WHEN t.sim_run_id IS NULL THEN COALESCE(c.n,0) ELSE 0 END AS touch_events,
       t.n AS turns,
       round((COALESCE(tc.n,0) + COALESCE(o.n,0))::numeric / GREATEST(1, t.n), 3)
         AS touch_events_per_turn
  FROM turns t
  LEFT JOIN touches tc ON tc.sim_run_id IS NOT DISTINCT FROM t.sim_run_id
  LEFT JOIN overrides o ON o.sim_run_id IS NOT DISTINCT FROM t.sim_run_id
  LEFT JOIN confirms c ON true;
COMMENT ON VIEW public.ottoq_kpi_touch_events_per_turn IS
  'KPI 4 (2.9): human interventions per asset-turn. Touch = signed events from '
  'human actor types + overridden decisions (+ production task confirmations '
  'for the NULL-run production row). Turns = KPI-2 completed bookings. The '
  'actor-type list is the current vocabulary; C7''s canonical touch_event type '
  'will supersede this enumeration.';

-- ============================================================================
-- KPI 5 — p95_time_to_service (recall-complete -> first op active)
-- ============================================================================
CREATE OR REPLACE VIEW public.ottoq_kpi_p95_time_to_service
  WITH (security_invoker = true) AS
WITH pairs AS (
  SELECT d.sim_run_id, d.vehicle_id, d.actual_return_at,
         (SELECT min(lower(b.during))
            FROM public.ottoq_stall_bookings b
           WHERE b.sim_run_id = d.sim_run_id
             AND b.vehicle_id = d.vehicle_id
             AND lower(b.during) >= d.actual_return_at) AS first_op_at
    FROM public.ottoq_vehicle_dispatches d
   WHERE d.actual_return_at IS NOT NULL
)
SELECT sim_run_id,
       round((percentile_cont(0.95) WITHIN GROUP
              (ORDER BY EXTRACT(EPOCH FROM (first_op_at - actual_return_at))/60.0)
             )::numeric, 1) AS p95_time_to_service_min,
       count(*) FILTER (WHERE first_op_at IS NOT NULL) AS returns_measured,
       count(*) FILTER (WHERE first_op_at IS NULL) AS returns_unserved
  FROM pairs
 GROUP BY sim_run_id;
COMMENT ON VIEW public.ottoq_kpi_p95_time_to_service IS
  'KPI 5 (2.9): p95 minutes from recall-complete (dispatch actual_return_at) '
  'to first operation active (first forward-calendar window opening at/after '
  'return). returns_unserved is reported, never silently dropped.';

-- ============================================================================
-- The reproducibility key on the EXISTING runs machinery (extend, not parallel)
-- ============================================================================
ALTER TABLE public.ottoq_run_archives
  ADD COLUMN IF NOT EXISTS pack_id     text NOT NULL DEFAULT 'robotaxi',
  ADD COLUMN IF NOT EXISTS config_hash text;
COMMENT ON COLUMN public.ottoq_run_archives.config_hash IS
  '0044: md5 of the canonicalized run config (jsonb sorted-key text). With '
  '(policy, pack_id, random_seed) this is the C6 reproducibility key.';

CREATE INDEX IF NOT EXISTS idx_run_archives_repro_key
  ON public.ottoq_run_archives (policy, pack_id, random_seed, config_hash);

-- Stamp helper: every solver/decide execution lands here keyed
-- (policy_name, pack_id, scenario_seed, config_hash).
CREATE OR REPLACE FUNCTION public.ottoq_run_archive_stamp(
  p_run uuid, p_pack text DEFAULT 'robotaxi', p_config jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions' AS $fn$
DECLARE v_hash text; v_key jsonb;
BEGIN
  v_hash := md5(COALESCE(p_config::text, (SELECT r.payload::text FROM ottoq_sim_runs r
                                           WHERE r.sim_run_id = p_run), ''));
  UPDATE ottoq_run_archives
     SET pack_id = p_pack, config_hash = v_hash
   WHERE sim_run_id = p_run;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'run % is not archived; archive it first (no parallel table)', p_run;
  END IF;
  SELECT jsonb_build_object('sim_run_id', p_run, 'policy_name', a.policy,
                            'pack_id', a.pack_id, 'scenario_seed', a.random_seed,
                            'config_hash', a.config_hash)
    INTO v_key FROM ottoq_run_archives a WHERE a.sim_run_id = p_run;
  RETURN v_key;
END;
$fn$;

-- ============================================================================
-- The assembly: run ID in -> five KPIs out, deterministic.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_kpi_five(p_run uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions' AS $fn$
  SELECT jsonb_build_object(
    'sim_run_id', p_run,
    'run_key', (SELECT jsonb_build_object(
                  'policy_name', a.policy, 'pack_id', a.pack_id,
                  'scenario_seed', a.random_seed, 'config_hash', a.config_hash,
                  'scenario', a.scenario)
                  FROM public.ottoq_run_archives a WHERE a.sim_run_id = p_run),
    'asset_hours_available_per_day',
      COALESCE((SELECT jsonb_object_agg(day, asset_hours_available ORDER BY day)
         FROM public.ottoq_kpi_asset_hours_available_per_day WHERE sim_run_id = p_run), '{}'::jsonb),
    'service_point_turns_per_point_per_day',
      COALESCE((SELECT jsonb_object_agg(day, turns_per_point_per_day ORDER BY day)
         FROM public.ottoq_kpi_service_point_turns WHERE sim_run_id = p_run), '{}'::jsonb),
    'peak_site_kw',
      (SELECT peak_site_kw_15min FROM public.ottoq_kpi_peak_site_kw WHERE sim_run_id = p_run),
    'touch_events_per_turn',
      (SELECT touch_events_per_turn FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id = p_run),
    'p95_time_to_service_min',
      (SELECT p95_time_to_service_min FROM public.ottoq_kpi_p95_time_to_service WHERE sim_run_id = p_run)
  );
$fn$;
COMMENT ON FUNCTION public.ottoq_kpi_five(uuid) IS
  'Run ID in, five canonical KPIs out (2.9), deterministic: pure SQL over '
  'committed views, no clock reads, stable ordering. The credibility rule: no '
  'number ships without a run ID — this is the function that enforces the shape.';

