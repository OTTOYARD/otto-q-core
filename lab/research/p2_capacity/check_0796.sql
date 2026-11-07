-- lab/research/p2_capacity/check_0796.sql -- LAB ONLY: 0796 executed on a copy of the day that found G514.
-- Run: createdb -T ottoq_cap_normal_day_116_171717 ottoq_lab_0796, then psql -d ottoq_lab_0796 -f this file.
\set ON_ERROR_STOP on
\pset footer off
CREATE TEMP TABLE before AS
SELECT o.* FROM public.ottoq_visit_outcomes((SELECT sim_run_id FROM ottoq_sim_runs WHERE run_by = 'ab_harness'
                                              ORDER BY started_at DESC LIMIT 1)) o;
SELECT 'before' AS side, (public.ottoq_throughput_scorecard((SELECT sim_run_id FROM ottoq_sim_runs WHERE run_by = 'ab_harness'
        ORDER BY started_at DESC LIMIT 1)) -> 'rule9') AS rule9;
\i db/migrations/0796_the_scorecard_does_not_count_a_service_done_on_a_second_try_as_left_open.sql
CREATE TEMP TABLE after AS
SELECT o.* FROM public.ottoq_visit_outcomes((SELECT sim_run_id FROM ottoq_sim_runs WHERE run_by = 'ab_harness'
                                              ORDER BY started_at DESC LIMIT 1)) o;
SELECT 'after' AS side, (public.ottoq_throughput_scorecard((SELECT sim_run_id FROM ottoq_sim_runs WHERE run_by = 'ab_harness'
        ORDER BY started_at DESC LIMIT 1)) -> 'rule9') AS rule9;
\echo '== rows that differ, before against after (only the open count of the one visit may move)'
SELECT b.visit_id, b.needed_open_at_departure AS open_before, a.needed_open_at_departure AS open_after,
       (to_jsonb(b) - 'needed_open_at_departure') = (to_jsonb(a) - 'needed_open_at_departure') AS rest_equal
  FROM before b FULL JOIN after a USING (visit_id)
 WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(a);
SELECT count(*) AS visits, count(*) FILTER (WHERE to_jsonb(b) = to_jsonb(a)) AS identical
  FROM before b JOIN after a USING (visit_id);
