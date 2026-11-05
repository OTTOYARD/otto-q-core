-- lab/research/p0_referee_per_owner/replay.sql -- run in the LAB database (never production).
-- Re-grades every decision of the referee's decision set (0475/0476: 370 graded decisions at the twin depot since
-- 2026-10-01), from the evidence production keeps (lib/export_decisions.py -> the lab's research schema), with the
-- grader's own pure functions, byte-identical in the lab to production's (ottoq_hindsight_code_md5 = 15da9f4c...).
--
-- For each decision, two re-grades:
--   0. AS RECORDED: the snapshot's state as stored. Compared with the stored grade, this says whether the lab
--      reproduces production's grader on that decision (exactly for grades written by today's grader code).
--   1. PER OWNER: the same state with each car's owner added (owner_guard and owners, exactly as
--      ottoq_charge_line_state adds them since 0784: vehicles.fleet_operator_id of the twin depot's autonomous cars).
--      The grader then also sums every quantity per owner (by_owner). Decisions recorded since 0784 already carry it.
--      Adding it must change nothing else: `owner_neutral` checks that every depot-level number is unchanged.
-- Twin depot only (rule 8). Rule 14: the per-owner reading is the point.
\set ON_ERROR_STOP on
DROP TABLE IF EXISTS research.referee_replay;
CREATE TABLE research.referee_replay AS
WITH own AS (
  SELECT COALESCE(jsonb_object_agg(ov.id::text, ov.fleet_operator_id), '{}'::jsonb) AS owners
    FROM public.vehicles ov
   WHERE ov.home_depot_id = '11111111-1111-1111-1111-111111111111' AND ov.category = 'autonomous'
), d AS (
  SELECT g.order_id, g.sim_run_id, g.sim_clock, g.code_md5, g.outcome, g.taken, g.p_win, g.wins, g.futures,
         g.expected AS e_stored, g.hindsight AS h_stored, g.realized, s.state, s.agent_order, s.seed,
         COALESCE((s.state ->> 'owner_guard')::boolean, false) AS recorded_with_owners,
         CASE WHEN COALESCE((s.state ->> 'owner_guard')::boolean, false) THEN s.state
              ELSE s.state || jsonb_build_object('owner_guard', true)
                           || CASE WHEN s.state ? 'owners' THEN '{}'::jsonb ELSE jsonb_build_object('owners', own.owners) END
         END AS state_o
    FROM research.ottoq_charge_order_grades g
    JOIN research.ottoq_charge_order_snapshots s USING (order_id), own
), r AS (
  SELECT d.*,
         public.ottoq_charge_line_realize(d.state,   d.realized, ARRAY['arrivals','appeared','charge_times','running','faults']) AS full0,
         public.ottoq_charge_line_realize(d.state_o, d.realized, ARRAY['arrivals','appeared','charge_times','running','faults']) AS full1
    FROM d
), s AS (
  SELECT r.*,
         public.ottoq_charge_line_schedule(r.state,   NULL,          0, r.seed, true) AS ek0,
         public.ottoq_charge_line_schedule(r.state,   r.agent_order, 0, r.seed, true) AS ea0,
         public.ottoq_charge_line_schedule(r.full0,   NULL,          0, r.seed, true) AS hk0,
         public.ottoq_charge_line_schedule(r.full0,   r.agent_order, 0, r.seed, true) AS ha0,
         public.ottoq_charge_line_schedule(r.state_o, NULL,          0, r.seed, true) AS ek1,
         public.ottoq_charge_line_schedule(r.state_o, r.agent_order, 0, r.seed, true) AS ea1,
         public.ottoq_charge_line_schedule(r.full1,   NULL,          0, r.seed, true) AS hk1,
         public.ottoq_charge_line_schedule(r.full1,   r.agent_order, 0, r.seed, true) AS ha1
    FROM r
)
SELECT s.order_id, s.sim_run_id, s.sim_clock, s.code_md5, s.code_md5 = public.ottoq_hindsight_code_md5() AS graded_by_todays_code,
       s.outcome, s.taken, s.p_win, s.wins, s.futures, s.recorded_with_owners,
       -- the grade as the grader writes it (ottoq_charge_order_grade_compute), recomputed
       (public.ottoq_charge_line_compare(s.ek0, s.ea0)
          || jsonb_build_object('kernel', s.ek0 - ARRAY['first','seats','return_seats'], 'agent', s.ea0 - ARRAY['first','seats','return_seats'])) = s.e_stored AS expected_reproduced,
       (public.ottoq_charge_line_compare(s.hk0, s.ha0)
          || jsonb_build_object('kernel', s.hk0 - ARRAY['first','seats','return_seats'], 'agent', s.ha0 - ARRAY['first','seats','return_seats'])) = s.h_stored AS hindsight_reproduced,
       ((public.ottoq_charge_line_compare(s.hk0, s.ha0)) ->> 'cmp')::int AS h_cmp_now,
       (s.h_stored ->> 'cmp')::int AS h_cmp_stored,
       ((public.ottoq_charge_line_compare(s.ek0, s.ea0)) ->> 'cmp')::int AS e_cmp_now,
       -- adding the owners changes no depot-level number (every key but by_owner, on all four sides)
       ((s.ek1 - 'by_owner') = (s.ek0 - 'by_owner') AND (s.ea1 - 'by_owner') = (s.ea0 - 'by_owner')
        AND (s.hk1 - 'by_owner') = (s.hk0 - 'by_owner') AND (s.ha1 - 'by_owner') = (s.ha0 - 'by_owner')) AS owner_neutral,
       s.ek1 -> 'by_owner' AS e_kernel_by_owner, s.ea1 -> 'by_owner' AS e_agent_by_owner,
       s.hk1 -> 'by_owner' AS h_kernel_by_owner, s.ha1 -> 'by_owner' AS h_agent_by_owner,
       s.hk0 - ARRAY['first','seats','return_seats','by_owner'] AS h_kernel, s.ha0 - ARRAY['first','seats','return_seats','by_owner'] AS h_agent
  FROM s;
ALTER TABLE research.referee_replay ADD PRIMARY KEY (order_id);
SELECT count(*) AS decisions,
       count(*) FILTER (WHERE graded_by_todays_code) AS graded_by_todays_code,
       count(*) FILTER (WHERE hindsight_reproduced) AS hindsight_reproduced,
       count(*) FILTER (WHERE graded_by_todays_code AND hindsight_reproduced) AS todays_code_and_reproduced,
       count(*) FILTER (WHERE expected_reproduced) AS expected_reproduced,
       count(*) FILTER (WHERE h_cmp_now = h_cmp_stored) AS same_hindsight_verdict,
       count(*) FILTER (WHERE owner_neutral) AS owner_neutral,
       count(*) FILTER (WHERE recorded_with_owners) AS recorded_with_owners
  FROM research.referee_replay;
