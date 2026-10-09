-- 0417  **0623 measured after its apply. Counting each car over its visit now and its next, the agent's charge order
--        beat the kernel's in hindsight on 10 of run d9d49732's 18 decisions, not 7. The check's expected future, now
--        with the outflow, names 8 of those 10 (it named 3 of 7), and its verdict agrees with hindsight on 10 of the 18
--        decisions (8 as graded) and 39 of 61 orders (39). It is more optimistic than it was: it calls the agent's
--        order better 13 times and is right 8. And the hindsight leak 0623 fixed (G357) moved no verdict.** One run, out
--        of sample: single readings, not ranges. (G355, G357 updated.)
--
--       Written 2026-10-08, 2:30 PM CT. Read-only. Twin depot 11111111-…, run d9d49732-cf28-42c3-aac9-9c3f606a2c92
--       (busy_day, seed 8950314943655796957, the agent's order through 0620's check; 0416), its 61 graded orders
--       (#357-#417), 18 of them decisions (the check weighed the agent's order against the kernel's and refused or took
--       it). 0623 applied as 20261008191129 (2:11 PM CT); measured 2:15-2:30 PM CT.
--
-- ══ §1 WHAT WAS MEASURED ════════════════════════════════════════════════════════════════════════════════════════════
--
--   Three readings of the same 61 orders. Each compares the check's expected future (scenario 0) with hindsight (the
--   same state with what happened put in, replayed both ways), on the sign of the comparison: agent's order better
--   (+1), worse (-1), no different (0). A verdict agrees when the two signs are equal.
--     (a) As graded (0621-0622): the hindsight rows as stored.
--     (b) Graded again with 0623's reader, on the stored state (no outflow): what the hindsight leak alone did.
--     (c) With the outflow: each stored state given the outflow as of its clock, the dwell and return cycle fitted
--         through the run's start (out of sample, as 0623's V2), so both futures send cars out and bring them back and
--         compare each car over two visits; hindsight is 0623's reader plus each modelled car's real departure and
--         return (V2's rule), put in for the appeared part.
--
-- ══ §2 THE LEAK COST NO VERDICT (G357) ══════════════════════════════════════════════════════════════════════════════
--
--   (b) against (a): all 61 hindsight verdicts identical. The 71 charge entries in 48 grades that a fault after the
--   cut had blanked were replayed on the check's own clock instead of their real minutes (at least the minutes they had
--   run), and on this run none of them changed which order came out better. The fix was owed on principle, a hindsight
--   that looks past its window is wrong whatever it costs, and on this run it cost nothing measurable.
--
-- ══ §3 THE CHECK WITH THE OUTFLOW ═══════════════════════════════════════════════════════════════════════════════════
--
--                                                     (a) as graded            (c) with the outflow
--   verdict agrees, all 61 orders                     39                       39
--     the 18 decisions                                8                        10
--     the 43 others (expected verdict 0)              31                       29
--   agent's order better in hindsight (decisions)     7 of 18                  10 of 18
--   check says agent better                           7, right 3               13, right 8
--   agent wins the check missed                       4                        2
--   check says agent worse                            11, right 5              5, right 2
--   the run's decisions as taken (2 taken)            right_refusal 10,        right_refusal 8,
--                                                     missed_win 6,            missed_win 8,
--                                                     right_take 1, wrong_take 1   right_take 2
--
--   (a) Hindsight moved on 11 orders, because the question moved: over two visits per car, an order that gets cars
--       out sooner is credited for it, where 0620's minutes over the visit now charged the cars it brought back against
--       it (0623 §1(d)). Toward the agent: 376, 385, 387, 388, 389 (decisions) and 392, 393 (others). Away: 363, 364
--       (decisions) and 384, 404 (others). #385, the run's one wrong take, is a right take on this objective.
--   (b) The check's expected verdict moved on 10 of the 18 decisions (366, 372, 376, 380, 383, 387, 388, 389, 416,
--       417), 8 of them toward the agent. It now sees most of the agent's wins (8 of 10, from 3 of 7) at 62% precision
--       (from 43%), and pays for it in optimism: 5 of its 13 "better" calls are wrong (364, 366, 371, 372, 416), and it
--       calls the agent worse only 5 times. Read it as a sharper and less cautious forecaster, not yet a better
--       decision: the take rule is unchanged, an order is taken only when it wins at least 10 of 12 sampled futures
--       (0620), and the expected future is one of the 12.
--   (c) Not measured here: how many of the 8 missed wins 0623's whole check would now take, and at what cost in
--       wrong takes. That needs the 12 futures per order (six times the schedules the measurement above ran, which
--       took about 6 seconds an order) or the next armed twin run, where the check runs with the outflow on every
--       order (return_v1 #4 is usable and carries the dwell, and the dial defaults to 1).
--   (d) The 43 others: the agent's order made the kernel's own seats in its window, or there was nothing to judge, so
--       the expected verdict is 0 by construction and agreement there only counts how often hindsight saw no
--       difference: 31 of 43 on the old objective, 29 on the new (392 and 393 moved off 0).
--
-- ══ §4 WHAT FOLLOWS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   1. The next armed twin run on the twin depot measures the take rule with the outflow live: its takes, wrong takes
--      and missed wins against this run's 2 takes, 1 wrong take and 6 missed wins (0 and 8 on the new objective), with
--      0621's grader and 0622's assessment reading it as they did this one.
--   2. The optimism has a likely cause already on the books: the dwell says how long the depot's charged cars stay, not
--      which car leaves when (G356, Brier 0.128 against the base rate's 0.105), so the expected future's departures
--      are spread right in aggregate and wrong car by car. A dwell conditioned on each car's open work is the next
--      build.
--   3. Nothing here is a finding for production: rule 10 holds, these are the research wing's measurements in the twin.
--
-- ══ §5 REPRODUCE ════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) as graded: agreement on all orders and on the decisions, and the outcomes
SELECT count(*) AS orders,
       count(*) FILTER (WHERE (h.expected ->> 'cmp') = (h.hindsight ->> 'cmp')) AS agree,
       count(*) FILTER (WHERE h.decision) AS decisions,
       count(*) FILTER (WHERE h.decision AND (h.expected ->> 'cmp') = (h.hindsight ->> 'cmp')) AS agree_on_decisions,
       count(*) FILTER (WHERE h.decision AND (h.hindsight ->> 'cmp') = '1') AS agent_wins_on_decisions
  FROM public.ottoq_charge_order_hindsight h
 WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92';

-- (2) graded again with 0623's reader, no outflow (G357 alone): about 20 orders per call inside a 58-second limit
WITH o AS (
  SELECT h.order_id, (h.hindsight ->> 'cmp')::int AS hc_graded, s.state, s.seed, s.agent_order,
         public.ottoq_charge_order_realized(h.order_id, h.window_min) AS rz
    FROM public.ottoq_charge_order_hindsight h JOIN public.ottoq_charge_order_snapshots s USING (order_id)
   WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND h.order_id BETWEEN 357 AND 377),
f AS (SELECT o.*, public.ottoq_charge_line_realize(o.state, o.rz,
                    ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults']) AS full FROM o)
SELECT f.order_id, f.hc_graded,
       (public.ottoq_charge_line_compare(public.ottoq_charge_line_schedule(f.full, NULL, 0, f.seed, true),
                                         public.ottoq_charge_line_schedule(f.full, f.agent_order, 0, f.seed, true)) ->> 'cmp')::int AS hc_now
  FROM f ORDER BY f.order_id;

-- (3) with the outflow, out of sample: about 6 orders per call inside a 58-second limit. Returns, per order:
--     [order, decision, taken, expected as graded, hindsight as graded, expected with the outflow, hindsight with it]
WITH rt AS MATERIALIZED (
  SELECT jsonb_build_object('usable', true, 'estimate_id', NULL,
           'params', public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid,
                       (SELECT started_at FROM public.ottoq_sim_runs WHERE sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'),
                       interval '21 days')) AS j),
o AS (
  SELECT h.order_id, h.decision, h.taken, h.sim_clock, h.observed_min, h.window_min,
         (h.expected ->> 'cmp')::int AS ec_graded, (h.hindsight ->> 'cmp')::int AS hc_graded,
         s.state, s.seed, s.agent_order,
         CASE WHEN (s.state #>> '{models,charge_time_model}') = 'charge_time_v2'
              THEN (SELECT jsonb_build_object('params', f.params) FROM public.ottoq_charge_clock_fits f
                     WHERE f.fit_id = (s.state #>> '{models,charge_time}')::bigint)
              ELSE (SELECT jsonb_build_object('params', e.params) FROM public.ottoq_learned_estimates e
                     WHERE e.estimate_id = (s.state #>> '{models,charge_time}')::bigint) END AS ct
    FROM public.ottoq_charge_order_hindsight h JOIN public.ottoq_charge_order_snapshots s USING (order_id)
   WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND h.order_id BETWEEN 357 AND 362),
a AS (
  SELECT o.*,
         public.ottoq_charge_line_outflow('d9d49732-cf28-42c3-aac9-9c3f606a2c92'::uuid, '11111111-1111-1111-1111-111111111111'::uuid,
                                          o.sim_clock, o.state, o.ct, (SELECT j FROM rt),
                                          public.ottoq_charge_clock_run_evidence(o.ct, 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'::uuid, o.sim_clock)) AS aug,
         public.ottoq_charge_order_realized(o.order_id, o.window_min) AS rz
    FROM o),
r AS (
  SELECT a.*,
         (SELECT COALESCE(jsonb_object_agg(c.id, jsonb_strip_nulls(jsonb_build_object(
                   'ce', CASE WHEN ce.at IS NOT NULL THEN round((extract(epoch FROM (ce.at - a.sim_clock)) / 60.0)::numeric, 2) END,
                   'left', CASE WHEN d.dispatched_at IS NOT NULL
                                THEN round((extract(epoch FROM (d.dispatched_at - a.sim_clock)) / 60.0)::numeric, 2) END,
                   'eta', CASE WHEN d.actual_return_at IS NOT NULL AND d.actual_return_at <= a.sim_clock + make_interval(secs => a.observed_min * 60)
                               THEN round((extract(epoch FROM (d.actual_return_at - a.sim_clock)) / 60.0)::numeric, 2) END,
                   'soc', CASE WHEN d.actual_return_at IS NOT NULL AND d.actual_return_at <= a.sim_clock + make_interval(secs => a.observed_min * 60)
                               THEN round(d.soc_at_return_pct, 1) END))), '{}'::jsonb)
            FROM (SELECT DISTINCT zz.id FROM (
                    SELECT x.value ->> 'id' AS id FROM jsonb_array_elements(a.aug -> 'cars') x
                    UNION ALL SELECT x.value ->> 'id' FROM jsonb_array_elements(a.aug -> 'inbound') x
                    UNION ALL SELECT x.value ->> 'car' FROM jsonb_array_elements(a.aug -> 'chargers') x WHERE x.value ? 'car'
                    UNION ALL SELECT x.value ->> 'id' FROM jsonb_array_elements(a.aug #> '{outflow,leaving}') x) zz
                   WHERE zz.id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') c
            LEFT JOIN LATERAL (SELECT dd.dispatched_at, dd.actual_return_at, dd.soc_at_return_pct FROM public.ottoq_vehicle_dispatches dd
                                WHERE dd.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND dd.vehicle_id = c.id::uuid
                                  AND dd.dispatched_at > a.sim_clock
                                  AND dd.dispatched_at <= a.sim_clock + make_interval(secs => a.observed_min * 60)
                                ORDER BY dd.dispatched_at LIMIT 1) d ON true
            LEFT JOIN LATERAL (SELECT max(dd.dispatched_at) AS at FROM public.ottoq_vehicle_dispatches dd
                                WHERE dd.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND dd.vehicle_id = c.id::uuid
                                  AND dd.dispatched_at <= a.sim_clock) lo ON true
            LEFT JOIN LATERAL (SELECT max(os.ended_at) AS at FROM public.ocpp_sessions os
                                WHERE os.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND os.vehicle_id = c.id::uuid
                                  AND os.stopped_reason = 'completed'
                                  AND os.ended_at <= COALESCE(d.dispatched_at, a.sim_clock + make_interval(secs => a.observed_min * 60))
                                  AND (lo.at IS NULL OR os.ended_at > lo.at)) ce ON true) AS ret
    FROM a),
z AS (
  SELECT r.order_id, r.decision, r.taken, r.ec_graded, r.hc_graded, r.aug, r.seed, r.agent_order,
         (r.rz || jsonb_build_object('returns', r.ret))
         || jsonb_build_object('appeared', COALESCE((
              SELECT jsonb_agg(x.value ORDER BY x.o) FROM jsonb_array_elements(r.rz -> 'appeared') WITH ORDINALITY x(value, o)
               WHERE NOT (r.ret ? (x.value ->> 'id'))), '[]'::jsonb)) AS rz2
    FROM r)
SELECT z.order_id, z.decision, z.taken, z.ec_graded, z.hc_graded,
       (public.ottoq_charge_line_compare(public.ottoq_charge_line_schedule(z.aug, NULL, 0, z.seed, true),
                                         public.ottoq_charge_line_schedule(z.aug, z.agent_order, 0, z.seed, true)) ->> 'cmp')::int AS ec_outflow,
       (SELECT (public.ottoq_charge_line_compare(public.ottoq_charge_line_schedule(q.fu, NULL, 0, z.seed, true),
                                                 public.ottoq_charge_line_schedule(q.fu, z.agent_order, 0, z.seed, true)) ->> 'cmp')::int
          FROM (SELECT public.ottoq_charge_line_realize(z.aug, z.rz2,
                         ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults']) AS fu) q) AS hc_outflow
  FROM z ORDER BY z.order_id;
