-- migration-version: 20260929183923
-- migration-name:    a_scorecard_that_counts_cars_served
--
-- 0565  **A scorecard that counts the cars a depot serves.** Lane A, phase 1. Chase, 2026-09-29: "I am very interested
--       in overall vehicle throughput, because that will be a large subscription or revenue opportunity ... SO as many
--       vehicles being serviced as possible will be ideal, ultimately ... that will be OTTO-Q's main orchestration
--       objective."
--
-- ══ §1 WHY: ottoq_ab_runs CANNOT CARRY A THROUGHPUT CLAIM (read 2026-09-29) ═════════════════════════════════════════
--
--   * fleet_ready_pct (ottoq_ab_write_score) is the cars staged for departure at the run's LAST tick over the fleet.
--     At the end of a full day they are out working, so it reads 0 on all 34 full-day otto_q arms. It answers "how many
--     sit ready right now", not "how many did the depot serve".
--   * safety_violations counts every failed rule evaluation, including advisory rules whose verdict nothing acts on
--     (0337, G149). It counts notes, not unsafe acts.
--   * Nothing in it says whether a car left fully charged with every needed service done (rule 9), how long a visit
--     took door to door, or whether the car left by its due time.
--
-- ══ §2 WHAT THIS BUILDS ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_visit_outcomes(run)          one row per visit: arrival, due, departure, door to door, on time,
--                                              charge out, needed work open at departure.
--   public.ottoq_throughput_scorecard(run)    the run's scorecard, throughput first. Deterministic: no clock reads and
--                                              stable ordering, so the two arms of a determinism pair must agree. A
--                                              KPI function it reuses that fails on a run is reported under kpi_errors
--                                              rather than failing the scorecard (ottoq_kpi_five fails on one August
--                                              production run, e8a0ba01: "field name must not be null").
--   public.ottoq_throughput_scores            evidence: a scorecard outlives the run it scores (0340's pattern -- no
--                                              FK to ottoq_sim_runs, registered class evidence, append-only).
--   public.ottoq_throughput_score_write(run)  writes one row. This file backfills every finished twin-depot run.
--
-- ══ §3 DEFINITIONS (they are the claim, so they are written down) ═════════════════════════════════════════════════
--
--   visit          a row of ottoq_visit_needs for the run.
--   departure      the vehicle's first dispatch at or after the visit's arrival and no later than its next visit's
--                  arrival. On the 48-tick busy_day canon, 0 of 217 visits re-arrive without leaving.
--   served         a visit with a departure inside the run's horizon. The headline is served visits per day.
--   in depot       no departure by the horizon. Counted, and kept out of every time percentile (censored).
--   on time        departure <= dispatch_due_at, over the served visits that carry a due time.
--   needed work open at departure
--                  a must_do atom not done by the departure. A done atom's time is closed_at (satisfied), done_at
--                  (credited) or ends_at (executed), per db/checks/0177 section 3. An atom triage cleared (status
--                  'cancelled' with cleared_by_triage, the verdict twin.ottoq_sim_advance_visit_atoms writes) was
--                  inspected and found not needed, so it is not open. Any other cancellation is.
--   tier group     the engine's visit archetypes, grouped: pass_through (D charge-and-go, A charge-clean-go,
--                  M pass-through/P triage, R rider-flag cleaning), full_service (C overnight, B full service,
--                  std_mixed), fault (E tech hold). This groups the generator's archetypes and is not yet a commercial
--                  tier. Phase 2 models the two tiers Chase set: full service with overnight parking, and on-demand
--                  pass-through where the fleet parks its own cars.
--   step_min       sim minutes per tick. Every time here is quantized to it. At the canon's 30 minutes a visit needs
--                  about three steps (arrive, plug, close) before it can leave, so read no time without it.
--
--   Rule 9 appears as two counts that must read 0: departures below target - 1, and departures with needed work open.
--
-- ══ §4 WHAT IT READS ON THE CANON DAY (busy_day, 48 ticks, 24 sim-hours, run ff680f5f, 2026-09-29) ══════════════════
--
--   217 visits by 116 cars. 119 served (82 distinct cars, a best hour of 12), and 98 in the depot at the 9 PM CT
--   horizon (the evening's returns). Rule 9 held: 0 left below 99%, 0 left with needed work open, 7 atoms cleared by
--   triage. Of the 93 visits with a due time, 56 left inside the day and 6 of those on time (10.7%). Door to door p50
--   was 540 minutes, and the 57 pass-through visits (charge-and-go and friends) served 24 at a p50 of 465 minutes.
--   Ten 350 kW fast chargers ran 67 sessions (6.7 per charger per day), plugged in 33% of the day at a mean 30.6 kW,
--   although the fleet accepts 100-250 kW (I-Pace 100, Model Y 250, Zoox 200) and the site peaked at 902 kW of its
--   2,250 kW usable. The median wait for a charger was 60 minutes, and L2 took 136 sessions. Measured on the same run:
--   all 67 fast-charge sessions last a whole multiple of the 30-minute step (30 of them exactly 30 minutes), a mean of
--   71 minutes plugged in, while the energy they delivered (mean 65% -> 99%) needs about 13 minutes at each car's peak
--   rate, somewhat more with the taper to 100%. So a fast charger is occupied several times longer than the charge
--   needs. The ceiling this reads is decision timing, not chargers and not grid power. NONE OF THIS IS A THROUGHPUT
--   CLAIM: phase 2 re-runs the day at a finer step before anything is quoted.
--
-- ══ §5 WHEN TO APPLY ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Any time. It creates three functions, one table, one trigger and one registry row, touches no existing object, and
--   the backfill skips live runs. Nothing in the engine or the determinism pair calls it, so forces_recert and
--   forces_dial_restart are FALSE.
--
-- ROLLBACK: DROP FUNCTION public.ottoq_throughput_score_write(uuid, text), public.ottoq_throughput_scorecard(uuid),
--   public.ottoq_visit_outcomes(uuid); DELETE FROM public.ottoq_run_scope_registry WHERE table_name =
--   'ottoq_throughput_scores'; DROP TABLE public.ottoq_throughput_scores; DROP FUNCTION
--   public.ottoq_throughput_scores_append_only(); DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0565_a_scorecard_that_counts_cars_served'.

BEGIN;

-- ── P1: the rows and functions the scorecard reads, and the one writer its triage definition depends on ──
DO $premises$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(t || '.' || c, ', ') INTO v_missing
    FROM (VALUES ('ottoq_visit_needs', 'visit_id'), ('ottoq_visit_needs', 'vehicle_id'),
                 ('ottoq_visit_needs', 'sim_run_id'), ('ottoq_visit_needs', 'archetype'),
                 ('ottoq_visit_needs', 'arrived_at'), ('ottoq_visit_needs', 'dispatch_due_at'),
                 ('ottoq_visit_needs', 'target_soc'), ('ottoq_visit_needs', 'atoms'),
                 ('ottoq_vehicle_dispatches', 'dispatch_id'), ('ottoq_vehicle_dispatches', 'vehicle_id'),
                 ('ottoq_vehicle_dispatches', 'sim_run_id'), ('ottoq_vehicle_dispatches', 'dispatched_at'),
                 ('ottoq_vehicle_dispatches', 'soc_at_dispatch_pct'),
                 ('ocpp_sessions', 'sim_run_id'), ('ocpp_sessions', 'stall_id'), ('ocpp_sessions', 'started_at'),
                 ('ocpp_sessions', 'ended_at'), ('ocpp_sessions', 'energy_delivered_kwh'),
                 ('ocpp_sessions', 'avg_power_kw'),
                 ('stalls', 'id'), ('stalls', 'depot_id'), ('stalls', 'stall_type'),
                 ('ottoq_sim_runs', 'sim_run_id'), ('ottoq_sim_runs', 'depot_id'), ('ottoq_sim_runs', 'status'),
                 ('ottoq_sim_runs', 'scenario_code'), ('ottoq_sim_runs', 'random_seed'),
                 ('ottoq_sim_runs', 'tick_count'), ('ottoq_sim_runs', 'policy'),
                 ('ottoq_sim_runs', 'tick_interval_seconds'), ('ottoq_sim_runs', 'time_scale'),
                 ('ottoq_sim_runs', 'sim_clock_start'), ('ottoq_sim_runs', 'sim_clock_current'),
                 ('ottoq_sim_runs', 'started_at'),
                 ('ottoq_run_archives', 'sim_run_id'), ('ottoq_run_archives', 'engine_hash'),
                 ('ottoq_run_archives', 'config_hash'),
                 ('ottoq_run_scope_registry', 'class'), ('ottoq_cert_lineage', 'forces_recert')) AS need(t, c)
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = need.t AND column_name = need.c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0565 P1: the scorecard reads columns that do not exist: %', v_missing;
  END IF;
  IF to_regprocedure('public.ottoq_kpi_charge_wait(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_kpi_five(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_kpi_service_completion(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_check_run_scope_registry()') IS NULL THEN
    RAISE EXCEPTION '0565 P1: a KPI function or the run-scope check the scorecard reuses is missing';
  END IF;
  -- "cancelled with cleared_by_triage means not needed" is only true while triage is the writer that says so.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_visit_atoms'
                    AND p.prosrc ~ $re$'status','cancelled'$re$ AND p.prosrc ~ 'cleared_by_triage') THEN
    RAISE EXCEPTION '0565 P1: twin.ottoq_sim_advance_visit_atoms no longer marks triage clears with cleared_by_triage';
  END IF;
END $premises$;

-- ── P2: not applied already ──
DO $fresh$
BEGIN
  IF to_regclass('public.ottoq_throughput_scores') IS NOT NULL
     OR to_regprocedure('public.ottoq_throughput_scorecard(uuid)') IS NOT NULL
     OR to_regprocedure('public.ottoq_visit_outcomes(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0565 P2: the scorecard already exists; this file has already been applied';
  END IF;
END $fresh$;

-- ── 1. one row per visit ──
CREATE FUNCTION public.ottoq_visit_outcomes(p_run uuid)
RETURNS TABLE (
  visit_id                 uuid,
  vehicle_id               uuid,
  archetype                text,
  tier_group               text,
  arrived_at               timestamptz,
  due_at                   timestamptz,
  departed_at              timestamptz,
  door_min                 numeric,
  on_time                  boolean,
  late_min                 numeric,
  soc_out                  numeric,
  target_soc               numeric,
  needed_open_at_departure integer,
  cleared_by_triage        integer,
  done_without_time        integer,
  in_depot_at_horizon      boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = twin, ottoq, public, extensions
AS $fn$
  WITH v AS (
    SELECT vn.visit_id, vn.vehicle_id, vn.archetype, vn.arrived_at, vn.dispatch_due_at, vn.target_soc, vn.atoms,
           lead(vn.arrived_at) OVER (PARTITION BY vn.vehicle_id ORDER BY vn.arrived_at, vn.visit_id) AS next_arrival
      FROM public.ottoq_visit_needs vn
     WHERE vn.sim_run_id = p_run
  ), d AS (
    SELECT v.visit_id, x.dispatched_at, x.soc_at_dispatch_pct
      FROM v
      LEFT JOIN LATERAL (
        SELECT dd.dispatched_at, dd.soc_at_dispatch_pct
          FROM public.ottoq_vehicle_dispatches dd
         WHERE dd.sim_run_id = p_run
           AND dd.vehicle_id = v.vehicle_id
           AND dd.dispatched_at >= v.arrived_at
           AND (v.next_arrival IS NULL OR dd.dispatched_at <= v.next_arrival)
         ORDER BY dd.dispatched_at, dd.dispatch_id
         LIMIT 1) x ON true
  ), a AS (
    SELECT v.visit_id,
           count(*) FILTER (
             WHERE COALESCE((e->>'must_do')::boolean, false)
               AND NOT (e->>'status' = 'cancelled' AND COALESCE((e->>'cleared_by_triage')::boolean, false))
               AND NOT (e->>'status' = 'done'
                        AND COALESCE((e->>'closed_at')::timestamptz, (e->>'done_at')::timestamptz,
                                     (e->>'ends_at')::timestamptz, '-infinity'::timestamptz) <= d.dispatched_at)
           ) AS open_n,
           count(*) FILTER (WHERE e->>'status' = 'cancelled'
                              AND COALESCE((e->>'cleared_by_triage')::boolean, false)) AS triage_n,
           count(*) FILTER (WHERE e->>'status' = 'done' AND e->>'closed_at' IS NULL
                              AND e->>'done_at' IS NULL AND e->>'ends_at' IS NULL) AS untimed_n
      FROM v
      JOIN d USING (visit_id)
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(v.atoms, '[]'::jsonb)) e
     GROUP BY v.visit_id
  )
  SELECT v.visit_id,
         v.vehicle_id,
         v.archetype,
         CASE WHEN v.archetype IN ('D_charge_and_go', 'A_charge_clean_go', 'M_pass_through_or_P_triage',
                                   'R_rider_flag_cleaning') THEN 'pass_through'
              WHEN v.archetype IN ('C_overnight', 'B_full_service', 'std_mixed') THEN 'full_service'
              WHEN v.archetype = 'E_tech_hold_fault' THEN 'fault'
              ELSE 'unclassified' END,
         v.arrived_at,
         v.dispatch_due_at,
         d.dispatched_at,
         round((extract(epoch FROM (d.dispatched_at - v.arrived_at)) / 60.0)::numeric, 1),
         CASE WHEN v.dispatch_due_at IS NULL OR d.dispatched_at IS NULL THEN NULL
              ELSE d.dispatched_at <= v.dispatch_due_at END,
         CASE WHEN v.dispatch_due_at IS NOT NULL AND d.dispatched_at > v.dispatch_due_at
              THEN round((extract(epoch FROM (d.dispatched_at - v.dispatch_due_at)) / 60.0)::numeric, 1) END,
         d.soc_at_dispatch_pct,
         v.target_soc,
         CASE WHEN d.dispatched_at IS NULL THEN NULL ELSE COALESCE(a.open_n, 0)::int END,
         COALESCE(a.triage_n, 0)::int,
         COALESCE(a.untimed_n, 0)::int,
         (d.dispatched_at IS NULL)
    FROM v
    JOIN d USING (visit_id)
    LEFT JOIN a USING (visit_id)
   ORDER BY v.arrived_at, v.visit_id;
$fn$;

-- ── 2. the run's scorecard ──
CREATE FUNCTION public.ottoq_throughput_scorecard(p_run uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = twin, ottoq, public, extensions
AS $fn$
DECLARE
  v_five   jsonb;
  v_wait   jsonb;
  v_svc    jsonb;
  v_errors jsonb := '{}'::jsonb;
  v_out    jsonb;
BEGIN
  -- The KPI functions this reuses are read as they are. One that fails on a run (ottoq_kpi_five raises "field name
  -- must not be null" on the August production run e8a0ba01) is reported under kpi_errors, never allowed to take the
  -- throughput numbers down with it.
  BEGIN v_five := public.ottoq_kpi_five(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('kpi_five', SQLERRM); END;
  BEGIN v_wait := public.ottoq_kpi_charge_wait(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('charge_wait', SQLERRM); END;
  BEGIN v_svc := public.ottoq_kpi_service_completion(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('service_completion', SQLERRM); END;

  WITH r AS (
    SELECT sr.sim_run_id, sr.depot_id, sr.scenario_code, sr.random_seed, sr.tick_count, sr.policy, sr.status,
           sr.sim_clock_start, sr.sim_clock_current,
           round((sr.tick_interval_seconds * COALESCE(sr.time_scale, 1) / 60.0)::numeric, 2) AS step_min,
           GREATEST(extract(epoch FROM (sr.sim_clock_current - sr.sim_clock_start)) / 3600.0, 0)::numeric AS horizon_h
      FROM public.ottoq_sim_runs sr
     WHERE sr.sim_run_id = p_run
  ), o AS (
    SELECT * FROM public.ottoq_visit_outcomes(p_run)
  ), s AS (
    SELECT * FROM o WHERE departed_at IS NOT NULL
  ), grp AS (
    SELECT g.tier_group,
           count(*)                                                       AS visits,
           count(*) FILTER (WHERE g.departed_at IS NOT NULL)              AS served,
           count(*) FILTER (WHERE g.in_depot_at_horizon)                  AS in_depot,
           percentile_cont(0.5)  WITHIN GROUP (ORDER BY g.door_min)       AS p50,
           percentile_cont(0.95) WITHIN GROUP (ORDER BY g.door_min)       AS p95,
           count(*) FILTER (WHERE g.due_at IS NOT NULL AND g.departed_at IS NOT NULL) AS due_served,
           count(*) FILTER (WHERE g.on_time)                              AS on_time
      FROM o g
     GROUP BY g.tier_group
  ), peak AS (
    SELECT COALESCE(max(n), 0) AS n
      FROM (SELECT (SELECT count(*) FROM s s2
                     WHERE s2.departed_at >= s1.departed_at
                       AND s2.departed_at <  s1.departed_at + interval '60 minutes') AS n
              FROM s s1) z
  ), sess AS (
    SELECT st.stall_type, x.stall_id, x.started_at, x.ended_at, x.energy_delivered_kwh, x.avg_power_kw
      FROM public.ocpp_sessions x
      JOIN public.stalls st ON st.id = x.stall_id
     WHERE x.sim_run_id = p_run AND x.started_at IS NOT NULL
  ), dc AS (
    SELECT count(*)                                                                          AS sessions,
           count(DISTINCT stall_id)                                                          AS chargers_used,
           sum(extract(epoch FROM (ended_at - started_at)) / 3600.0) FILTER (WHERE ended_at IS NOT NULL) AS hours,
           sum(energy_delivered_kwh)                                                         AS kwh,
           avg(avg_power_kw)                                                                 AS mean_kw,
           avg(extract(epoch FROM (ended_at - started_at)) / 60.0) FILTER (WHERE ended_at IS NOT NULL) AS mean_min
      FROM sess
     WHERE stall_type = 'dcfc'
  ), fleet AS (
    SELECT count(*) AS dcfc_at_depot FROM public.stalls st, r WHERE st.depot_id = r.depot_id AND st.stall_type = 'dcfc'
  ), ar AS (
    SELECT a.engine_hash, a.config_hash FROM public.ottoq_run_archives a WHERE a.sim_run_id = p_run LIMIT 1
  )
  SELECT jsonb_build_object(
    'sim_run_id', r.sim_run_id,
    'scorecard_version', '0565',
    'run', jsonb_build_object(
       'scenario', r.scenario_code, 'seed', r.random_seed, 'ticks', r.tick_count, 'policy', r.policy,
       'status', r.status, 'depot_id', r.depot_id, 'sim_start', r.sim_clock_start, 'horizon', r.sim_clock_current,
       'horizon_h', round(r.horizon_h, 2),
       'engine_hash', (SELECT engine_hash FROM ar), 'config_hash', (SELECT config_hash FROM ar)),
    'step_min', r.step_min,
    'throughput', jsonb_build_object(
       'visits',              (SELECT count(*) FROM o),
       'visits_served',       (SELECT count(*) FROM s),
       'vehicles_served',     (SELECT count(DISTINCT vehicle_id) FROM s),
       'in_depot_at_horizon', (SELECT count(*) FROM o WHERE in_depot_at_horizon),
       'served_per_day',      CASE WHEN r.horizon_h > 0
                                   THEN round((SELECT count(*) FROM s) * 24.0 / r.horizon_h, 1) END,
       'peak_hour_served',    (SELECT n FROM peak)),
    'by_tier_group', COALESCE((SELECT jsonb_object_agg(tier_group, jsonb_build_object(
       'visits', visits, 'served', served, 'in_depot', in_depot,
       'door_p50_min', round(p50::numeric, 0), 'door_p95_min', round(p95::numeric, 0),
       'due_served', due_served, 'on_time', on_time,
       'on_time_pct', CASE WHEN due_served > 0 THEN round(100.0 * on_time / due_served, 1) END)) FROM grp), '{}'::jsonb),
    'timeliness', jsonb_build_object(
       'door_p50_min', (SELECT round((percentile_cont(0.5)  WITHIN GROUP (ORDER BY door_min))::numeric, 0) FROM s),
       'door_p95_min', (SELECT round((percentile_cont(0.95) WITHIN GROUP (ORDER BY door_min))::numeric, 0) FROM s),
       'due_served',   (SELECT count(*) FROM s WHERE due_at IS NOT NULL),
       'on_time',      (SELECT count(*) FROM s WHERE on_time),
       'on_time_pct',  (SELECT CASE WHEN count(*) FILTER (WHERE due_at IS NOT NULL) > 0
                                    THEN round(100.0 * count(*) FILTER (WHERE on_time)
                                               / count(*) FILTER (WHERE due_at IS NOT NULL), 1) END FROM s),
       'late_p50_min', (SELECT round((percentile_cont(0.5)  WITHIN GROUP (ORDER BY late_min))::numeric, 0) FROM s
                         WHERE late_min IS NOT NULL),
       'late_p95_min', (SELECT round((percentile_cont(0.95) WITHIN GROUP (ORDER BY late_min))::numeric, 0) FROM s
                         WHERE late_min IS NOT NULL)),
    'rule9', jsonb_build_object(
       'departures',                  (SELECT count(*) FROM s),
       'left_below_target',           (SELECT count(*) FROM s
                                        WHERE soc_out IS NOT NULL AND soc_out < COALESCE(target_soc, 100) - 1),
       'left_with_needed_work_open',  (SELECT count(*) FROM s WHERE needed_open_at_departure > 0),
       'charge_unknown_at_departure', (SELECT count(*) FROM s WHERE soc_out IS NULL),
       'atoms_cleared_by_triage',     (SELECT COALESCE(sum(cleared_by_triage), 0) FROM o),
       'done_atoms_without_a_time',   (SELECT COALESCE(sum(done_without_time), 0) FROM o)),
    'fast_chargers', jsonb_build_object(
       'at_depot',                  (SELECT dcfc_at_depot FROM fleet),
       'used',                      dc.chargers_used,
       'sessions',                  dc.sessions,
       'turns_per_charger_per_day', CASE WHEN r.horizon_h > 0 AND (SELECT dcfc_at_depot FROM fleet) > 0
                                         THEN round(dc.sessions * 24.0 / r.horizon_h
                                                    / (SELECT dcfc_at_depot FROM fleet), 2) END,
       'busy_pct',                  CASE WHEN r.horizon_h > 0 AND (SELECT dcfc_at_depot FROM fleet) > 0
                                         THEN round(100.0 * COALESCE(dc.hours, 0)
                                                    / (r.horizon_h * (SELECT dcfc_at_depot FROM fleet)), 1) END,
       'mean_session_min',          round(dc.mean_min::numeric, 1),
       'mean_kw',                   round(dc.mean_kw::numeric, 1),
       'kwh_per_session_hour',      round((dc.kwh / NULLIF(dc.hours, 0))::numeric, 1)),
    'l2_sessions', (SELECT count(*) FROM sess WHERE stall_type = 'l2'),
    'charge_wait', v_wait,
    'service_completion', CASE WHEN v_svc IS NOT NULL THEN
                            jsonb_build_object('must_do', v_svc->'must_do', 'must_do_done', v_svc->'must_do_done',
                                               'pct', v_svc->'service_completion_pct') END,
    'kpi', CASE WHEN v_five IS NOT NULL THEN
             jsonb_build_object('peak_site_kw', v_five->'peak_site_kw',
                                'peak_site_kw_demand', v_five->'peak_site_kw_demand',
                                'touch_events_per_turn', v_five->'touch_events_per_turn',
                                'p95_time_to_service_min', v_five->'p95_time_to_service_min') END,
    'kpi_errors', v_errors,
    'comparability', jsonb_build_object(
       'all_policies', 'visits, dispatches and charge sessions: every arm''s vehicles produce them, because the policy only proposes and the kernel disposes (0261)',
       'rule', 'db/checks/0149: a comparative metric read from an artifact only one arm produces measures which arm it is'),
    'caveats', jsonb_build_array(
       format('Times are quantized to %s-minute steps. At 30 minutes a visit needs about three steps before it can leave.', r.step_min),
       'tier_group groups the generator''s visit archetypes. It is not yet a commercial tier.',
       'A visit still in the depot at the horizon is counted in in_depot_at_horizon and kept out of every time percentile.'))
    INTO v_out
  FROM r, dc;
  RETURN v_out;
END $fn$;

-- ── 3. the evidence table: a scorecard outlives the run it scores ──
CREATE TABLE public.ottoq_throughput_scores (
  score_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sim_run_id    uuid        NOT NULL,
  scenario_code text,
  random_seed   bigint,
  tick_count    integer,
  policy        text,
  step_min      numeric,
  scorecard     jsonb       NOT NULL,
  scorecard_md5 text        NOT NULL,
  origin        text        NOT NULL DEFAULT 'writer',
  scored_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ottoq_throughput_scores_run_idx ON public.ottoq_throughput_scores (sim_run_id);
CREATE INDEX ottoq_throughput_scores_key_idx ON public.ottoq_throughput_scores (scenario_code, random_seed, tick_count);

CREATE FUNCTION public.ottoq_throughput_scores_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_catalog AS $fn$
BEGIN
  RAISE EXCEPTION 'ottoq_throughput_scores is evidence and append-only: % is refused', TG_OP;
END $fn$;
CREATE TRIGGER trg_ottoq_throughput_scores_append_only
  BEFORE UPDATE OR DELETE ON public.ottoq_throughput_scores
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_throughput_scores_append_only();

ALTER TABLE public.ottoq_throughput_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_throughput_scores_read ON public.ottoq_throughput_scores
  FOR SELECT TO authenticated, service_role USING (true);
REVOKE ALL ON public.ottoq_throughput_scores FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_throughput_scores TO authenticated, service_role;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_throughput_scores', 'sim_run_id', 'evidence',
        '0565: one throughput scorecard per scored run. Evidence, not engine: phase 2 and the Margin Ledger quote throughput from it, so it must survive ottoq_purge_prior_runs. Deliberately carries NO foreign key to ottoq_sim_runs, as 0340''s ledger does not: check (b) asks for one from engine/stamp only.');

-- ── 4. the writer ──
CREATE FUNCTION public.ottoq_throughput_score_write(p_run uuid, p_origin text DEFAULT 'writer')
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = twin, ottoq, public, extensions
AS $fn$
DECLARE
  r    public.ottoq_sim_runs%ROWTYPE;
  v_sc jsonb;
  v_id bigint;
BEGIN
  SELECT * INTO r FROM public.ottoq_sim_runs WHERE sim_run_id = p_run;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ottoq_throughput_score_write: run % not found', p_run;
  END IF;
  v_sc := public.ottoq_throughput_scorecard(p_run);
  INSERT INTO public.ottoq_throughput_scores
    (sim_run_id, scenario_code, random_seed, tick_count, policy, step_min, scorecard, scorecard_md5, origin)
  VALUES (p_run, r.scenario_code, r.random_seed, r.tick_count, r.policy, (v_sc->>'step_min')::numeric,
          v_sc, md5(v_sc::text), COALESCE(p_origin, 'writer'))
  RETURNING score_id INTO v_id;
  RETURN v_id;
END $fn$;

-- ── grants: read like the KPI functions (authenticated, service_role); write for service_role only ──
REVOKE ALL ON FUNCTION public.ottoq_visit_outcomes(uuid)                FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ottoq_throughput_scorecard(uuid)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ottoq_throughput_score_write(uuid, text)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_throughput_scores_append_only()     FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_visit_outcomes(uuid)       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_throughput_scorecard(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_throughput_score_write(uuid, text) TO service_role;

COMMENT ON FUNCTION public.ottoq_visit_outcomes(uuid) IS
'0565. One row per visit of a run: arrival, due time, departure (the vehicle''s first dispatch at or after arrival and no later than its next visit), door-to-door minutes, on time, charge out, and needed work open at departure (a must_do atom not done by then; a triage clear is not open). Read-only; every arm produces the rows it reads.';
COMMENT ON FUNCTION public.ottoq_throughput_scorecard(uuid) IS
'0565. Run ID in, throughput scorecard out: visits served per day and per peak hour, door to door and on time by tier group, rule 9 as two counts that must read 0, fast-charger turns, busy share and power, charge wait, service completion and the KPIs that bear on throughput. Deterministic (no clock reads). Every time in it is quantized to step_min; read none without it.';
COMMENT ON TABLE public.ottoq_throughput_scores IS
'0565. Evidence: one row per scorecard written, append-only, class evidence in ottoq_run_scope_registry with no FK to ottoq_sim_runs, so a scorecard survives the purge of the run it scores. scorecard_md5 is md5(scorecard::text).';
COMMENT ON FUNCTION public.ottoq_throughput_score_write(uuid, text) IS
'0565. Scores one run into public.ottoq_throughput_scores and returns the row id. service_role only.';

-- ── 5. backfill every finished twin-depot run that still has its visits ──
DO $backfill$
DECLARE
  r   record;
  n   int := 0;
BEGIN
  FOR r IN SELECT sr.sim_run_id
             FROM public.ottoq_sim_runs sr
            WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
              AND sr.status NOT IN ('running', 'paused', 'initializing')
              AND EXISTS (SELECT 1 FROM public.ottoq_visit_needs v WHERE v.sim_run_id = sr.sim_run_id)
            ORDER BY sr.started_at, sr.sim_run_id
  LOOP
    PERFORM public.ottoq_throughput_score_write(r.sim_run_id, 'backfill_0565');
    n := n + 1;
  END LOOP;
  RAISE NOTICE '0565: backfilled % scorecard(s)', n;
END $backfill$;

-- ── V1: the objects are what they claim to be ──
DO $verify_catalog$
DECLARE
  v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.ottoq_visit_outcomes(uuid)', 'public.ottoq_throughput_scorecard(uuid)',
                              'public.ottoq_throughput_score_write(uuid,text)'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p
                    WHERE p.oid = to_regprocedure(v_fn) AND p.prosecdef
                      AND pg_get_userbyid(p.proowner) = 'postgres'
                      AND p.proconfig @> ARRAY['search_path=twin, ottoq, public, extensions']) THEN
      RAISE EXCEPTION '0565 V1: % is not a postgres-owned SECURITY DEFINER with a pinned search_path', v_fn;
    END IF;
    IF has_function_privilege('anon', to_regprocedure(v_fn), 'EXECUTE') THEN
      RAISE EXCEPTION '0565 V1: anon can execute %', v_fn;
    END IF;
  END LOOP;
  IF has_function_privilege('authenticated', 'public.ottoq_throughput_score_write(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_throughput_score_write(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_throughput_scorecard(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0565 V1: the scorecard grants are not read-for-authenticated, write-for-service_role';
  END IF;
  IF has_table_privilege('anon', 'public.ottoq_throughput_scores', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ottoq_throughput_scores', 'INSERT')
     OR has_table_privilege('service_role', 'public.ottoq_throughput_scores', 'DELETE') THEN
    RAISE EXCEPTION '0565 V1: ottoq_throughput_scores is writable, deletable or anon-readable';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_schema = 'public' AND table_name = 'ottoq_throughput_scores'
                    AND column_name = 'sim_run_id' AND class = 'evidence') THEN
    RAISE EXCEPTION '0565 V1: ottoq_throughput_scores is not registered class evidence';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry()
              WHERE table_name = 'ottoq_throughput_scores' AND severity = 'block') THEN
    RAISE EXCEPTION '0565 V1: the run-scope check blocks on ottoq_throughput_scores';
  END IF;
END $verify_catalog$;

-- ── V2: the scorecard adds up, and it is deterministic across a determinism pair's two arms ──
DO $verify_scorecards$
DECLARE
  s        record;
  v_sc     jsonb;
  v_sum    bigint;
  v_a      uuid;
  v_b      uuid;
  v_sc_a   jsonb;
  v_sc_b   jsonb;
  v_viol   text;
  v_runs   bigint;
BEGIN
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs sr
   WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
     AND sr.status NOT IN ('running', 'paused', 'initializing')
     AND EXISTS (SELECT 1 FROM public.ottoq_visit_needs v WHERE v.sim_run_id = sr.sim_run_id);
  IF (SELECT count(*) FROM public.ottoq_throughput_scores WHERE origin = 'backfill_0565') <> v_runs THEN
    RAISE EXCEPTION '0565 V2: backfilled % scorecards for % finished twin runs',
      (SELECT count(*) FROM public.ottoq_throughput_scores WHERE origin = 'backfill_0565'), v_runs;
  END IF;

  FOR s IN SELECT sim_run_id, scorecard, scorecard_md5 FROM public.ottoq_throughput_scores LOOP
    v_sc := s.scorecard;
    IF md5(v_sc::text) <> s.scorecard_md5 THEN
      RAISE EXCEPTION '0565 V2: run % stored a scorecard whose md5 does not match', s.sim_run_id;
    END IF;
    IF (v_sc #>> '{throughput,visits}')::bigint
       <> (v_sc #>> '{throughput,visits_served}')::bigint + (v_sc #>> '{throughput,in_depot_at_horizon}')::bigint THEN
      RAISE EXCEPTION '0565 V2: run % served + in depot <> visits', s.sim_run_id;
    END IF;
    SELECT COALESCE(sum((g.value->>'visits')::bigint), 0) INTO v_sum
      FROM jsonb_each(v_sc->'by_tier_group') g;
    IF v_sum <> (v_sc #>> '{throughput,visits}')::bigint THEN
      RAISE EXCEPTION '0565 V2: run % tier groups sum to % of % visits', s.sim_run_id, v_sum,
        (v_sc #>> '{throughput,visits}');
    END IF;
    IF NOT (v_sc->'kpi_errors') ? 'charge_wait'
       AND (v_sc->'charge_wait') IS DISTINCT FROM public.ottoq_kpi_charge_wait(s.sim_run_id) THEN
      RAISE EXCEPTION '0565 V2: run % charge_wait differs from ottoq_kpi_charge_wait', s.sim_run_id;
    END IF;
    IF (v_sc #>> '{rule9,left_below_target}')::bigint > 0
       OR (v_sc #>> '{rule9,left_with_needed_work_open}')::bigint > 0 THEN
      v_viol := COALESCE(v_viol || '; ', '') || format('%s: %s below target, %s with needed work open',
                  s.sim_run_id, v_sc #>> '{rule9,left_below_target}', v_sc #>> '{rule9,left_with_needed_work_open}');
    END IF;
  END LOOP;
  IF v_viol IS NOT NULL THEN
    -- A finding about the engine, not a defect in this file: reported, not refused.
    RAISE NOTICE '0565 V2 RULE 9 FINDING: %', v_viol;
  END IF;

  -- The newest passed determinism pair on the twin depot: both arms must score identically but for their run ids.
  SELECT a.sim_run_id, b.sim_run_id INTO v_a, v_b
    FROM public.ottoq_sim_runs a
    JOIN public.ottoq_sim_runs b
      ON b.scenario_code = a.scenario_code AND b.random_seed = a.random_seed AND b.tick_count = a.tick_count
     AND b.started_at = a.started_at AND b.sim_run_id > a.sim_run_id
   WHERE a.depot_id = '11111111-1111-1111-1111-111111111111' AND b.depot_id = a.depot_id
     AND a.run_by = 'cert_harness' AND b.run_by = 'cert_harness'
     AND a.validation_status = 'passed' AND b.validation_status = 'passed'
     AND EXISTS (SELECT 1 FROM public.ottoq_throughput_scores t WHERE t.sim_run_id = a.sim_run_id)
     AND EXISTS (SELECT 1 FROM public.ottoq_throughput_scores t WHERE t.sim_run_id = b.sim_run_id)
   ORDER BY a.tick_count DESC, a.started_at DESC
   LIMIT 1;
  IF v_a IS NULL THEN
    RAISE NOTICE '0565 V2: no passed determinism pair with visits survives on the twin depot; determinism unchecked here';
  ELSE
    SELECT scorecard INTO v_sc_a FROM public.ottoq_throughput_scores WHERE sim_run_id = v_a ORDER BY score_id LIMIT 1;
    SELECT scorecard INTO v_sc_b FROM public.ottoq_throughput_scores WHERE sim_run_id = v_b ORDER BY score_id LIMIT 1;
    v_sc_a := (v_sc_a - 'sim_run_id') || jsonb_build_object('charge_wait', (v_sc_a->'charge_wait') - 'sim_run_id');
    v_sc_b := (v_sc_b - 'sim_run_id') || jsonb_build_object('charge_wait', (v_sc_b->'charge_wait') - 'sim_run_id');
    IF v_sc_a IS DISTINCT FROM v_sc_b THEN
      RAISE EXCEPTION '0565 V2: the two arms of passed pair % / % score differently', v_a, v_b;
    END IF;
    RAISE NOTICE '0565 V2: pair % / % scores identically (% visits served of %)', v_a, v_b,
      v_sc_a #>> '{throughput,visits_served}', v_sc_a #>> '{throughput,visits}';
  END IF;
END $verify_scorecards$;

-- ── V3: append-only holds ──
DO $verify_append_only$
BEGIN
  BEGIN
    UPDATE public.ottoq_throughput_scores SET origin = origin WHERE score_id = (SELECT min(score_id) FROM public.ottoq_throughput_scores);
    IF FOUND THEN
      RAISE EXCEPTION '0565 V3: an UPDATE of ottoq_throughput_scores was allowed';
    END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'ottoq_throughput_scores is evidence and append-only%' THEN RAISE; END IF;
  END;
END $verify_append_only$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0565_a_scorecard_that_counts_cars_served', false, false,
  'Three new read functions (ottoq_visit_outcomes, ottoq_throughput_scorecard, ottoq_throughput_score_write), one evidence table and a registry row. They read finished runs; no engine path, runner or determinism pair calls them, so no certified digest can move and no dial experiment spans a changed engine.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
