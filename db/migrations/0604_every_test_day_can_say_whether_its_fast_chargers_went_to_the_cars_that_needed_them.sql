-- migration-version: 20261002200316
-- migration-name:    every_test_day_can_say_whether_its_fast_chargers_went_to_the_cars_that_needed_them
--
-- 0604  **A read-only measure of charger fit: how much of a run's fast-charger time went to cars that were already
--       nearly full, how long the cars that arrived low waited on L2, and how often a car took the other kind of
--       charger from the one it asked for.** Overnight review 2026-09-30 (G315). Reading only: nothing the engine
--       reads changes.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase's second priority is fewer chargers with every car fully serviced. The lever is which car gets a fast charger:
--   a fast charger on a car at 90% delivers about 15 kW, which is what an L2 gives it, while a car at 25% on L2 waits
--   five hours for a charge a fast charger would finish in under one. Rule 9 is not in play: either way the car reaches
--   100%; the question is only how much fleet energy each charger-hour delivers.
--
--   Measured on night 1 (frontier_2026_09_29, seed 686364201590009433, busy_day, 10 fast chargers, 12 hours), the three
--   seats on the same seed and the same chargers:
--       seat     fast-charger hours on cars      fast-charger kWh   all charging kWh   visits served
--                that started at 80% or more
--       otto_q   43.5 of 84.0 h (52%)            2,038              5,639              118     (85a5d396)
--       fifo     34.4 of 84.9 h (41%)            2,131              5,905              102     (d038fb17)
--       greedy   27.0 of 97.2 h (28%)            2,722              6,683              141     (1edc847e)
--   OTTO-Q's seat spent the most fast-charger time on nearly full cars of the three, and delivered the least energy. 55
--   of its enacted fast-charger picks (51 of them at 80% or more) were cars whose own proposal said `wanted_type = 'l2'`,
--   and 21 of its L2 picks were cars that wanted a fast charger. Nothing reported any of this: the sweep's scorecard
--   counts fast-charger sessions and their mean kW, not who they went to.
--
-- ══ §2 WHAT THIS ADDS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_charger_fit_profile(run, depot, hi_soc 80, lo_soc 50)`, read-only, over the run's charging sessions at
--   the depot (rule 8's predicate), by stall type: sessions, session-hours, kWh, kWh per session-hour, and the sessions
--   and hours that started at or above hi_soc; the sessions that started below lo_soc and their average minutes; and,
--   from the run's enacted stall assignments, the fast-charger picks by cars that wanted L2 and the L2 picks by cars that
--   wanted a fast charger. A session still open is counted to the run's last energy sample (its horizon).
--   It is for the research wing to read any arm with, after the fact, including night 1's. It does not join a scorecard;
--   whether it should is Lane A's call (0577 shows the one-line merge).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: not already applied.
--   V1: on the latest twin run with a charging session, the profile's session count and kWh equal a direct count of that
--   run's sessions at the twin depot. V2: every percentage it reports lies in [0, 100].
--   Measured before applying (2026-09-30, 1:20 AM CT), the body run read-only on the live database: the table in §1.
--   Executed by tests/test_charger_fit_profile_sql.py.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: a new read-only function with no caller.
--
-- ROLLBACK: DROP FUNCTION public.ottoq_charger_fit_profile(uuid, uuid, numeric, numeric);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0604_every_test_day_can_say_whether_its_fast_chargers_went_to_the_cars_that_needed_them'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0604 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0604_every_test_day_can_say_whether_its_fast_chargers_went_to_the_cars_that_needed_them')
     OR to_regprocedure('public.ottoq_charger_fit_profile(uuid,uuid,numeric,numeric)') IS NOT NULL THEN
    RAISE EXCEPTION '0604 P1: already applied';
  END IF;
END $once$;

CREATE FUNCTION public.ottoq_charger_fit_profile(p_run uuid, p_depot uuid, p_hi_soc numeric DEFAULT 80,
                                                 p_lo_soc numeric DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0604 (G315): how a run matched cars to charger types. By stall type over the run's charging sessions at the depot:
   sessions, hours, kWh, kWh per session-hour, the sessions and hours that started at or above p_hi_soc, the sessions that
   started below p_lo_soc and their average minutes; and, from the run's enacted stall assignments, the fast-charger picks
   by cars that wanted L2 and the L2 picks by cars that wanted a fast charger. An open session counts to the run's last
   energy sample. Read-only. */
WITH hz AS (
  SELECT GREATEST(
           (SELECT max(e.timestamp) FROM site_energy_snapshots e WHERE e.sim_run_id = p_run AND e.depot_id = p_depot),
           (SELECT max(GREATEST(o.started_at, COALESCE(o.ended_at, o.started_at))) FROM ocpp_sessions o
             WHERE o.sim_run_id = p_run AND o.depot_id = p_depot)) AS t_end
), s AS (
  SELECT st.stall_type::text AS t, o.soc_start, COALESCE(o.energy_delivered_kwh, 0) AS kwh,
         EXTRACT(EPOCH FROM (GREATEST(o.started_at, COALESCE(o.ended_at, hz.t_end)) - o.started_at)) / 3600.0 AS h
    FROM ocpp_sessions o
    JOIN stalls st ON st.id = o.stall_id
   CROSS JOIN hz
   WHERE o.sim_run_id = p_run AND o.depot_id = p_depot AND st.depot_id = p_depot
     AND st.stall_type::text IN ('dcfc', 'l2')
), agg AS (
  SELECT s.t, count(*) AS n, sum(s.h) AS h, sum(s.kwh) AS kwh,
         count(*) FILTER (WHERE s.soc_start >= p_hi_soc) AS n_hi,
         COALESCE(sum(s.h) FILTER (WHERE s.soc_start >= p_hi_soc), 0) AS h_hi,
         count(*) FILTER (WHERE s.soc_start < p_lo_soc) AS n_lo,
         avg(s.h) FILTER (WHERE s.soc_start < p_lo_soc) AS h_lo
    FROM s GROUP BY s.t
), dec AS (
  SELECT count(*) FILTER (WHERE d.proposed_action->>'stall_type' = 'dcfc'
                            AND d.proposed_action->'rationale'->>'wanted_type' = 'l2') AS fast_wanted_l2,
         count(*) FILTER (WHERE d.proposed_action->>'stall_type' = 'l2'
                            AND d.proposed_action->'rationale'->>'wanted_type' = 'dcfc') AS l2_wanted_fast
    FROM ottoq_decisions d
   WHERE d.sim_run_id = p_run AND d.depot_id = p_depot
     AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
)
SELECT jsonb_build_object(
  'hi_soc_pct', p_hi_soc, 'lo_soc_pct', p_lo_soc, 'horizon', (SELECT hz.t_end FROM hz),
  'by_type', COALESCE((SELECT jsonb_object_agg(a.t, jsonb_build_object(
      'sessions', a.n, 'session_hours', round(a.h, 1), 'kwh', round(a.kwh, 0),
      'kw_per_session_hour', round(a.kwh / NULLIF(a.h, 0), 1),
      'sessions_from_hi_soc', a.n_hi, 'hours_from_hi_soc', round(a.h_hi, 1),
      'pct_hours_from_hi_soc', round(100 * a.h_hi / NULLIF(a.h, 0), 1),
      'sessions_from_lo_soc', a.n_lo, 'avg_min_from_lo_soc', round(a.h_lo * 60, 0)))
     FROM agg a), '{}'::jsonb),
  'sessions', (SELECT count(*) FROM s),
  'kwh_delivered', (SELECT round(COALESCE(sum(s.kwh), 0), 0) FROM s),
  'fast_picks_by_cars_wanting_l2', (SELECT dec.fast_wanted_l2 FROM dec),
  'l2_picks_by_cars_wanting_fast', (SELECT dec.l2_wanted_fast FROM dec))
$fn$;

COMMENT ON FUNCTION public.ottoq_charger_fit_profile(uuid, uuid, numeric, numeric) IS
'0604 (G315). How a run matched cars to charger types: by stall type, the hours and energy, the share of fast-charger hours '
'on cars that started nearly full, how long cars that arrived low waited on L2, and how often a car took the other kind of '
'charger from the one it asked for. Read-only; for reading any arm, including night 1''s.';
REVOKE ALL ON FUNCTION public.ottoq_charger_fit_profile(uuid, uuid, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_charger_fit_profile(uuid, uuid, numeric, numeric) TO authenticated, service_role;

-- ── V1: on a live twin run, the profile's sessions and kWh are the run's own ──
DO $v1$
DECLARE
  v_run uuid;
  p jsonb;
  v_n bigint;
  v_kwh numeric;
BEGIN
  SELECT o.sim_run_id INTO v_run
    FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id
   WHERE o.depot_id = '11111111-1111-1111-1111-111111111111' AND st.stall_type::text IN ('dcfc', 'l2')
     AND o.sim_run_id IS NOT NULL
   ORDER BY o.started_at DESC, o.sim_run_id
   LIMIT 1;
  IF v_run IS NULL THEN
    RAISE EXCEPTION '0604 V1: no twin run with a charging session to prove the profile against';
  END IF;
  SELECT count(*), round(COALESCE(sum(COALESCE(o.energy_delivered_kwh, 0)), 0), 0) INTO v_n, v_kwh
    FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id
   WHERE o.sim_run_id = v_run AND o.depot_id = '11111111-1111-1111-1111-111111111111'
     AND st.depot_id = '11111111-1111-1111-1111-111111111111' AND st.stall_type::text IN ('dcfc', 'l2');
  p := public.ottoq_charger_fit_profile(v_run, '11111111-1111-1111-1111-111111111111');
  IF (p ->> 'sessions')::bigint IS DISTINCT FROM v_n OR (p ->> 'kwh_delivered')::numeric IS DISTINCT FROM v_kwh THEN
    RAISE EXCEPTION '0604 V1: on run % the profile counts % sessions and % kWh, the run holds % and %', v_run,
      p ->> 'sessions', p ->> 'kwh_delivered', v_n, v_kwh;
  END IF;
  PERFORM set_config('ottoq.m0604_run', v_run::text, true);
END $v1$;

-- ── V2: every percentage in [0, 100] ──
DO $v2$
DECLARE
  p jsonb := public.ottoq_charger_fit_profile(current_setting('ottoq.m0604_run')::uuid, '11111111-1111-1111-1111-111111111111');
  k text;
BEGIN
  FOR k IN SELECT jsonb_object_keys(p -> 'by_type') LOOP
    IF (p #>> ARRAY['by_type', k, 'pct_hours_from_hi_soc'])::numeric NOT BETWEEN 0 AND 100 THEN
      RAISE EXCEPTION '0604 V2: % reports % percent of its hours from nearly full cars', k,
        p #>> ARRAY['by_type', k, 'pct_hours_from_hi_soc'];
    END IF;
  END LOOP;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0604_every_test_day_can_say_whether_its_fast_chargers_went_to_the_cars_that_needed_them', false, false,
  'G315, overnight review 2026-09-30. ottoq_charger_fit_profile(run, depot): by stall type, the hours and energy, the '
  'share of fast-charger hours on cars that started at 80% or more, how long cars that arrived below 50% waited on L2, '
  'and the picks of the other kind of charger. Night 1 seed 1: otto_q 52% of fast-charger hours on nearly full cars, '
  'fifo 41%, greedy 28%; energy delivered 5,639 / 5,905 / 6,683 kWh. Read-only, no caller.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
