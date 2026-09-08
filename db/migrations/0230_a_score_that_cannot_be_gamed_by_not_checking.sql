-- migration-version: PENDING
-- migration-name:    a_score_that_cannot_be_gamed_by_not_checking
--
-- Part B groundwork. `public.ottoq_ab_score_run(uuid) RETURNS jsonb` — a
-- read-only scorer that measures a run's SAFETY FROM ITS OUTCOME, never from
-- whether the policy chose to check anything.
--
-- WHY THIS EXISTS (db/checks/0146). Only `ottoq_decide_tick` evaluates the
-- 52-rule L1 shield. `ottoq_fifo_tick`, `ottoq_greedy_tick`,
-- `ottoq_baseline_fifo` and greedy's two twin delegates evaluate NO rules at
-- all, and three of them never touch the stall calendar. So the obvious safety
-- metric — `count(ottoq_rule_evaluations WHERE passed = false)` — reports
-- **zero violations for a policy that never checked**, which is the most
-- flattering possible number for the least safe arm.
--
-- Every metric below is therefore computed from what the run LEFT BEHIND:
-- bookings, sessions, stall capabilities, the depot's own cap. A policy cannot
-- improve its score by skipping a check, because no score reads a check.
--
-- THE SECOND TRAP, AND WHY THE `coverage` BLOCK EXISTS. Outcome metrics have
-- their own zero problem: an arm that never books anything has zero incapable
-- bookings, trivially. `incapable_charge_bookings = 0` means one thing when
-- `bookings_total = 879` and something opposite when `bookings_total = 0`.
-- **So every safety figure ships next to the denominator that makes it
-- interpretable**, and `used_calendar` / `consulted_shield` state plainly
-- whether the arm participated in the mechanism at all. A zero with no
-- denominator is the same defect as a green with no comparison (G25, G28).
--
-- NOT a KPI view, and deliberately not wired to `ottoq_ab_runs` yet. This is
-- the measurement half; the writer and the paired rig come after, once this has
-- been run against real arms. Scoring and deciding stay separate objects.
--
-- SAFE BY CONSTRUCTION: `STABLE`, reads only, touches nothing the certification
-- path writes. It cannot move a canon. `forces_recert FALSE` accordingly, and
-- unlike 0229 that classification needs no argument — a read-only function that
-- no engine code calls cannot change engine behaviour.

CREATE OR REPLACE FUNCTION public.ottoq_ab_score_run(p_sim_run_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $fn$
WITH r AS (
  SELECT sim_run_id, depot_id, random_seed, scenario_code, tick_count,
         policy, status, sim_clock_start, sim_clock_current
    FROM public.ottoq_sim_runs
   WHERE sim_run_id = p_sim_run_id
),
bk AS (
  SELECT b.* FROM public.ottoq_stall_bookings b JOIN r ON b.sim_run_id = r.sim_run_id
),
sess AS (
  SELECT o.started_at,
         COALESCE(o.ended_at, o.started_at + interval '1 minute') AS ended_at,
         COALESCE(o.avg_power_kw, o.peak_power_kw, 0)             AS kw
    FROM public.ocpp_sessions o JOIN r ON o.sim_run_id = r.sim_run_id
   WHERE o.started_at IS NOT NULL
),
ev AS (
  SELECT started_at AS t,  kw AS d FROM sess
  UNION ALL
  SELECT ended_at   AS t, -kw AS d FROM sess
),
peak AS (
  SELECT max(sum(d) OVER (ORDER BY t, d DESC ROWS UNBOUNDED PRECEDING)) AS kw FROM ev
),
cap AS (SELECT d.service_max_kw AS kw FROM public.depots d JOIN r ON d.id = r.depot_id),
-- A charge booking onto a stall whose connector cannot serve the vehicle's
-- inlet. Counted only where BOTH sides declare their types; a NULL on either
-- side is unknown, not a pass, and is reported separately as `unverifiable`.
cap_check AS (
  SELECT
    count(*) FILTER (
      WHERE s.supported_inlet_types IS NOT NULL AND v.inlet_type IS NOT NULL
        AND NOT (v.inlet_type = ANY (s.supported_inlet_types)))        AS incapable,
    count(*) FILTER (
      WHERE s.supported_inlet_types IS NULL OR v.inlet_type IS NULL)   AS unverifiable,
    count(*)                                                           AS charge_bookings
  FROM bk
  JOIN public.stalls   s ON s.id = bk.stall_id
  JOIN public.vehicles v ON v.id = bk.vehicle_id
  WHERE bk.purpose ILIKE '%charg%'
)
SELECT jsonb_build_object(
  'run', jsonb_build_object(
     'sim_run_id', r.sim_run_id, 'seed', r.random_seed, 'scenario', r.scenario_code,
     'ticks', r.tick_count, 'depot', r.depot_id, 'policy', r.policy, 'status', r.status),

  -- Coverage FIRST, because it is what makes every zero below readable.
  'coverage', jsonb_build_object(
     'bookings_total',    (SELECT count(*) FROM bk),
     'charge_bookings',   (SELECT charge_bookings FROM cap_check),
     'rule_evals_total',  (SELECT count(*) FROM public.ottoq_rule_evaluations e
                            WHERE e.sim_run_id = r.sim_run_id),
     'charge_sessions',   (SELECT count(*) FROM sess),
     'used_calendar',     ((SELECT count(*) FROM bk) > 0),
     'consulted_shield',  ((SELECT count(*) FROM public.ottoq_rule_evaluations e
                             WHERE e.sim_run_id = r.sim_run_id) > 0)),

  'safety', jsonb_build_object(
     'incapable_charge_bookings',   (SELECT incapable     FROM cap_check),
     'unverifiable_charge_bookings',(SELECT unverifiable  FROM cap_check),
     'peak_concurrent_kw',          round((SELECT kw FROM peak)::numeric, 1),
     'site_cap_kw',                 (SELECT kw FROM cap),
     'pct_of_cap',                  round(100.0 * COALESCE((SELECT kw FROM peak),0)
                                          / NULLIF((SELECT kw FROM cap),0), 1),
     'cap_breached',                COALESCE((SELECT kw FROM peak) > (SELECT kw FROM cap), false),
     'booking_overlaps',            0,
     'overlaps_note',               'structurally 0: ottoq_stall_bookings carries EXCLUDE '
                                    'constraints. Read together with used_calendar — an arm '
                                    'that books nothing also overlaps nothing.'),

  'throughput', jsonb_build_object(
     'decisions',       (SELECT count(*) FROM public.ottoq_decisions d
                          WHERE d.sim_run_id = r.sim_run_id),
     'sdrs',            (SELECT count(*) FROM public.ottoq_service_detail_records x
                          WHERE x.sim_run_id = r.sim_run_id),
     'events',          (SELECT count(*) FROM public.ottoq_events v
                          WHERE v.sim_run_id = r.sim_run_id),
     'vehicles_booked', (SELECT count(DISTINCT vehicle_id) FROM bk),
     'bookings_by_purpose', COALESCE(
        (SELECT jsonb_object_agg(purpose, n)
           FROM (SELECT purpose, count(*) AS n FROM bk GROUP BY purpose) q), '{}'::jsonb))
)
FROM r;
$fn$;

COMMENT ON FUNCTION public.ottoq_ab_score_run(uuid) IS
  'Part B scorer. Measures a run''s safety from its OUTCOME, never from whether '
  'the policy checked anything -- db/checks/0146 established that only otto_q '
  'evaluates the L1 shield, so counting logged rule failures would score an '
  'unshielded baseline as perfectly safe. Every safety figure ships with the '
  'coverage denominator that makes it readable. STABLE and read-only.';

DO $A1$
DECLARE v_run uuid; j jsonb;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE status = 'completed' AND validation_notes IS NOT NULL
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION 'A1: no completed run to score against'; END IF;

  j := public.ottoq_ab_score_run(v_run);

  IF j IS NULL THEN RAISE EXCEPTION 'A1 FAILED: scorer returned NULL for %', v_run; END IF;
  IF NOT (j ? 'coverage' AND j ? 'safety' AND j ? 'throughput' AND j ? 'run') THEN
    RAISE EXCEPTION 'A1 FAILED: missing a top-level block: %', jsonb_object_keys(j);
  END IF;
  IF (j->'coverage'->>'bookings_total')::bigint IS NULL THEN
    RAISE EXCEPTION 'A1 FAILED: bookings_total is NULL, so no zero below it is readable';
  END IF;
  IF (j->'safety'->>'peak_concurrent_kw') IS NULL THEN
    RAISE EXCEPTION 'A1 FAILED: peak_concurrent_kw is NULL';
  END IF;
END $A1$;

DO $A2$
BEGIN
  -- An unknown run must return NULL, not a row of confident zeros. A scorer that
  -- invents a clean bill of health for a run that does not exist is worse than
  -- one that fails.
  IF public.ottoq_ab_score_run('00000000-0000-0000-0000-000000000000'::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'A2 FAILED: scorer returned non-NULL for a nonexistent run';
  END IF;
END $A2$;

INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'a_score_that_cannot_be_gamed_by_not_checking',
  now(),
  false,
  'Part B groundwork. Adds public.ottoq_ab_score_run(uuid), a STABLE read-only '
  'scorer measuring safety from a run''s outcome rather than from its logged rule '
  'evaluations -- db/checks/0146 showed only otto_q evaluates the L1 shield, so the '
  'obvious metric would score the least safe arm as flawless. Every safety figure '
  'carries its coverage denominator so a zero is readable. forces_recert FALSE: a '
  'read-only function no engine code calls cannot change engine behaviour.'
);
