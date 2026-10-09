-- 0418  **What a charged car has left to do decides when it leaves, and the check now reads it (0624, G356).** Out of
--        sample on run d9d49732's 61 graded orders, each car's chance of leaving inside the order's window scores a
--        Brier of 0.1011 on its class's curve against 0.1277 on 0623's one curve and 0.1046 for the run's base rate.
--        Across the eight twin runs of 2026-10-01 to 10-08, each fitted through its own start, the classes beat the
--        one curve on 8 of 8 runs at 10, 30 and 60 minutes. The class that helps least is the one that most needs a
--        better model: a car waiting on a bay leaves within about a minute of the bay finishing, and the bay finishes
--        when the bays' own queue lets it (G358, open). One run per score, and 78 distinct cars behind the 2,712
--        car-rows of the first: single readings, not ranges.
--
--       Written 2026-10-08, 3:55 PM CT. Read-only. Twin depot 11111111-…; the eight twin runs started 2026-10-01 to
--       10-08 (816bd28c, cde5a21c, ae8a4908, fd6ed035, 0bbdcc07, 089f46bd, d9d49732, baf29c05) and the charges of the
--       21 days before each. Measured 2:35-3:05 PM CT before 0624 was written, and through 0624's own functions after
--       its apply (20261008204412, 3:44 PM CT).
--
-- ══ §1 WHAT WAS MEASURED ════════════════════════════════════════════════════════════════════════════════════════════
--
--   A charged car's dwell is the minutes from its charge's end to its next departure (0623): a car that charged again
--   first, or was still parked when its run ended, is censored there. 0624 sorts each charge by what the car had left
--   to do when its charge ended, on its visit as of the charge's start (`ottoq_dwell_class`): 'clear' (nothing in a
--   bay), 'bay' (a must-do service that needs a bay still open) or 'boot' (no visit: in the depot since its run
--   began), and fits one Kaplan-Meier curve per class; 'new', clear and bay together, is the curve for a car out at
--   work whose next visit's work is not known. Each score below is a Brier score of the chance a car is gone by a
--   given minute, against whether it was, on curves fitted only from charges created before the scored run began.
--
-- ══ §2 THE SPLIT ════════════════════════════════════════════════════════════════════════════════════════════════════
--
--                        21 days before d9d49732 began          21 days to 0624's apply (fit #6)
--                        charges  left  median minutes          charges  left  median minutes
--   clear                    482   479      0.51                    553   549      0.50
--   bay                      399   261     67.95                    442   288     66.88
--   boot                     620   552      7.92                    721   653      9.03
--   new (clear + bay)        881   740      5.67                    995   837      4.25
--   one curve (0623)       1,501 1,292      7.28                  1,716 1,490      7.52
--
--   A clear car leaves at once: half within 0.51 minutes of its charge's end, 95% within 10.3, and only 3 of 482 not
--   seen to leave. A bay car leaves after its bay: its curve's median is an hour. One curve over both put its median
--   at 7.3 minutes, wrong for nearly every car it described.
--
-- ══ §3 OUT OF SAMPLE, ON d9d49732'S 61 GRADED ORDERS (0624's V2, reproduced after the apply by (2)) ══════════════════
--
--   2,712 car-rows whose charge's end was seen, 78 distinct cars (the orders are minutes apart and see the same cars).
--                                       by class      one curve      base rate
--   Brier, gone by the order's window   0.1011        0.1277         0.1046
--   departures expected / real          0.884         0.831
--   of those that left: under the curve's median for their stretch 0.562 (0.533); under its 80th percentile 0.800
--   (0.799); the expected future of the order that ran put 645 returns inside the window against 544 real (1.186).
--
--   By class (car-rows, left, Brier by class against one curve):
--     clear   798    798   0.0014 against 0.0875
--     boot  1,201  1,110   0.0905 against 0.1030
--     new      85     41   0.2344 against 0.2396
--     bay     628    441   0.2302 against 0.2106   the one class the split did not help on this run (§5)
--
-- ══ §4 ACROSS RUNS, EACH FITTED THROUGH ITS OWN START (reproduce: (3)) ═════════════════════════════════════════════
--
--   Each of the eight runs' charged cars, scored on whether it had left 10, 30 and 60 minutes after its charge ended
--   (a car still parked when its run ended before then is not scored there). Charge-weighted over the runs:
--     minutes  charges  one curve  by class  base rate   class beats one curve   class beats base rate
--       10      1,091    0.2491     0.1089    0.2451          8 of 8 runs            8 of 8
--       30      1,069    0.1954     0.0996    0.1890          8 of 8                 8 of 8
--       60      1,050    0.1466     0.0984    0.1355          8 of 8                 7 of 8 (not d9d49732)
--   By class at 30 minutes: clear 397 charges, 0.0948 -> 0.0002 (8 of 8 runs); bay 284, 0.3890 -> 0.1849 (8 of 8);
--   boot 388, 0.1566 -> 0.1390 (7 of 8). At 10 minutes boot gains nothing (0.2513 -> 0.2521, 4 of 8): a run-start car
--   leaves when the dispatcher pulls it, and the curve cannot see the pull coming. At 60 minutes bay gains on 6 of 8.
--
--   Per run (Brier one curve -> by class, at 10 / 30 / 60 minutes):
--     816bd28c  0.2530 -> 0.0945 / 0.2423 -> 0.0779 / 0.2400 -> 0.1357
--     cde5a21c  0.2498 -> 0.1015 / 0.1944 -> 0.1249 / 0.1394 -> 0.1146
--     ae8a4908  0.2491 -> 0.0783 / 0.2192 -> 0.1131 / 0.2048 -> 0.1269
--     fd6ed035  0.2497 -> 0.1146 / 0.1950 -> 0.1025 / 0.1198 -> 0.1064
--     0bbdcc07  0.2469 -> 0.0960 / 0.1656 -> 0.0792 / 0.1142 -> 0.0654
--     089f46bd  0.2466 -> 0.1096 / 0.1744 -> 0.0565 / 0.0920 -> 0.0557
--     d9d49732  0.2487 -> 0.1921 / 0.1638 -> 0.1276 / 0.0853 -> 0.0806
--     baf29c05  0.2473 -> 0.1369 / 0.1678 -> 0.1192 / 0.0895 -> 0.0643
--
-- ══ §5 THE BAY CARS (G358) ══════════════════════════════════════════════════════════════════════════════════════════
--
--   On every run with ten or more bay cars, the median bay car left within about a minute of its last bay service
--   being done; how long the bay took after the charge is what moves. Reproduce: (4).
--     21 days to 0624's apply, 10 runs:      left 0.37 to 1.02 minutes after the bay was done; bay done 19.2 to 87.5
--                                            minutes after the charge (d9d49732 19.2, baf29c05 27.1, 0bbdcc07 29.2,
--                                            cde5a21c 33.6, 4b0999db 34.3, 089f46bd 34.4, fd6ed035 38.1, ab534960 51.5,
--                                            816bd28c 63.6, ae8a4908 87.5)
--     21 days before d9d49732 began, 8 runs: left 0.39 to 1.02 minutes after; bay done 29.2 to 87.5 minutes after
--   CORRECTION to 0624 §1(a) and (d): they quote the first line (ten runs, 0.37 to 1.02, 19 to 88 minutes) beside the
--   counts of the second window (1,501 charges, 399 bay). In the second window it is eight runs, 0.39 to 1.02 and 29
--   to 88 minutes. The finding is the same in both: the bay car's dwell is the bay's own time, and that varies by run
--   by more than four to one. d9d49732's bays ran fastest of all (19.2 minutes), which is why its bay cars are the one
--   class that scored worse on its own curve than on the one curve (§3): the bay curve, fitted on slower runs,
--   expected 0.59 of their departures. A curve that reads the bay queue, or the run's own bay times so far, is G358.
--
-- ══ §6 WHAT FOLLOWS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   1. The next armed twin run on the twin depot runs the check with the class curves live (fit #6 is usable and
--      carries them; the dial `agent_charge_order_dwell_class` defaults to 1), and 0621's grader scores each order on
--      both curves (`dwell_by` beside `dwell_pooled`), so whether the classes still beat one curve is read order by
--      order, not assumed.
--   2. G358: the bay dwell follows the bays' congestion. Measured, not built.
--   3. The boot cars' 10-minute score: the dispatcher's pull is the dwell, and the check does not see it coming.
--   4. Nothing here is a finding for production: rule 10 holds; the research wing's measurements in the twin.
--
-- ══ §7 REPRODUCE ════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) the split, fitted through d9d49732's start (about 5 seconds; 0624's function, read-only)
SELECT k.key, k.value ->> 'n' AS charges, k.value ->> 'left' AS left, k.value ->> 'median_min' AS median_min,
       k.value ->> 'f_max' AS f_max, k.value ->> 'max_min' AS last_departure
  FROM jsonb_each(public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid,
                    (SELECT started_at FROM public.ottoq_sim_runs WHERE sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'),
                    interval '21 days') -> 'dwell_by') k
 ORDER BY k.key;

-- (2) 0624's V2 through the live functions: the 61 graded orders, each car on its class's curve and on one curve, the
--     curves fitted through the run's start (about 20 seconds)
WITH rt AS MATERIALIZED (
  SELECT jsonb_build_object('usable', true, 'estimate_id', NULL,
           'params', public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid,
                       (SELECT started_at FROM public.ottoq_sim_runs WHERE sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'),
                       interval '21 days')) AS j),
o AS (
  SELECT h.order_id, h.taken, h.sim_clock, h.observed_min, h.realized, s.state, s.seed, s.agent_order,
         CASE WHEN (s.state #>> '{models,charge_time_model}') = 'charge_time_v2'
              THEN (SELECT jsonb_build_object('params', f.params) FROM public.ottoq_charge_clock_fits f
                     WHERE f.fit_id = (s.state #>> '{models,charge_time}')::bigint)
              ELSE (SELECT jsonb_build_object('params', e.params) FROM public.ottoq_learned_estimates e
                     WHERE e.estimate_id = (s.state #>> '{models,charge_time}')::bigint) END AS ct
    FROM public.ottoq_charge_order_hindsight h JOIN public.ottoq_charge_order_snapshots s USING (order_id)
   WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'),
-- MATERIALIZED: inlined, the outflow would run once for every reference to aug below
a AS MATERIALIZED (
  SELECT o.*,
         public.ottoq_charge_line_outflow('d9d49732-cf28-42c3-aac9-9c3f606a2c92'::uuid, '11111111-1111-1111-1111-111111111111'::uuid,
                                          o.sim_clock, o.state, o.ct, (SELECT j FROM rt),
                                          public.ottoq_charge_clock_run_evidence(o.ct, 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'::uuid, o.sim_clock)) AS aug
    FROM o),
r AS MATERIALIZED (
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
f AS MATERIALIZED (
  SELECT r.order_id,
         public.ottoq_charge_order_forecast_errors(
           r.aug,
           (r.realized || jsonb_build_object('returns', r.ret))
           || jsonb_build_object('appeared', COALESCE((
                SELECT jsonb_agg(x.value ORDER BY x.o) FROM jsonb_array_elements(r.realized -> 'appeared') WITH ORDINALITY x(value, o)
                 WHERE NOT (r.ret ? (x.value ->> 'id'))), '[]'::jsonb)),
           public.ottoq_charge_line_schedule(r.aug, CASE WHEN r.taken THEN r.agent_order END, 0, r.seed, true)) -> 'outflow' AS fo
    FROM r
   WHERE jsonb_typeof(r.aug #> '{outflow,dwell_by}') = 'object'),
t AS (
  SELECT count(*) AS orders, sum((fo #>> '{dwell,seen}')::numeric) AS seen, sum((fo #>> '{dwell,left}')::numeric) AS lft,
         sum((fo #>> '{dwell,p_left}')::numeric) AS p_cls, sum((fo #>> '{dwell_pooled,p_left}')::numeric) AS p_one,
         sum((fo #>> '{dwell,brier}')::numeric) AS b_cls, sum((fo #>> '{dwell_pooled,brier}')::numeric) AS b_one,
         sum((fo #>> '{dwell,pit_n}')::numeric) AS pn, sum((fo #>> '{dwell,pit50}')::numeric) AS p50,
         sum((fo #>> '{dwell,pit80}')::numeric) AS p80, sum((fo ->> 'modelled')::numeric) AS modelled,
         sum((fo ->> 'real')::numeric) AS real
    FROM f)
SELECT t.orders, t.seen, t.lft AS left,
       round(t.b_cls / t.seen, 4) AS brier_class, round(t.b_one / t.seen, 4) AS brier_one_curve,
       round((t.lft / t.seen) * (1 - t.lft / t.seen), 4) AS brier_base_rate,
       round(t.p_cls / t.lft, 3) AS departures_expected_over_real, round(t.p_one / t.lft, 3) AS one_curve_expected_over_real,
       round(t.p50 / t.pn, 3) AS under_median, round(t.p80 / t.pn, 3) AS under_p80,
       round(t.modelled / t.real, 3) AS returns_forecast_over_real,
       (SELECT jsonb_object_agg(q.k, jsonb_build_array(q.seen, q.lft, round(q.bc / q.seen, 4), round(q.bp / q.seen, 4)))
          FROM (SELECT b.key AS k, sum((b.value ->> 'seen')::numeric) AS seen, sum((b.value ->> 'left')::numeric) AS lft,
                       sum((b.value ->> 'brier')::numeric) AS bc, sum((b.value ->> 'brier_pooled')::numeric) AS bp
                  FROM f CROSS JOIN LATERAL jsonb_each(f.fo -> 'dwell_by') b GROUP BY b.key) q) AS by_class_seen_left_class_one
  FROM t;

-- (3) across runs: each run's charges scored at 10, 30 and 60 minutes on the curves fitted through its start. Run in
--     two calls of four runs inside a 58-second limit (this one; then 0bbdcc07, 089f46bd, d9d49732, baf29c05)
WITH tr AS (
  SELECT x.sim_run_id, x.started_at FROM public.ottoq_sim_runs x
   WHERE x.depot_id = '11111111-1111-1111-1111-111111111111' AND left(x.sim_run_id::text, 8) IN ('816bd28c', 'cde5a21c', 'ae8a4908', 'fd6ed035')),
r AS (
  SELECT x.sim_run_id, COALESCE(x.sim_clock_current, x.sim_clock_start) AS run_end
    FROM public.ottoq_sim_runs x
   WHERE x.depot_id = '11111111-1111-1111-1111-111111111111' AND x.tick_count > 0
     AND x.sim_clock_current IS NOT NULL AND x.sim_clock_start IS NOT NULL
     AND extract(epoch FROM (x.sim_clock_current - x.sim_clock_start)) / 60.0 / x.tick_count <= 1),
s AS MATERIALIZED (
  SELECT os.sim_run_id, os.created_at, os.ended_at, r.run_end,
         (SELECT min(dd.dispatched_at) FROM public.ottoq_vehicle_dispatches dd
           WHERE dd.sim_run_id = os.sim_run_id AND dd.vehicle_id = os.vehicle_id AND dd.dispatched_at >= os.ended_at) AS next_out,
         (SELECT min(o2.started_at) FROM public.ocpp_sessions o2
           WHERE o2.sim_run_id = os.sim_run_id AND o2.vehicle_id = os.vehicle_id AND o2.started_at > os.ended_at) AS next_charge,
         (SELECT vn.atoms FROM public.ottoq_visit_needs vn
           WHERE vn.sim_run_id = os.sim_run_id AND vn.vehicle_id = os.vehicle_id AND vn.arrived_at <= os.started_at
           ORDER BY vn.arrived_at DESC, vn.created_at DESC LIMIT 1) AS atoms,
         (SELECT true FROM public.ottoq_visit_needs vn
           WHERE vn.sim_run_id = os.sim_run_id AND vn.vehicle_id = os.vehicle_id AND vn.arrived_at <= os.started_at LIMIT 1) AS has_visit
    FROM public.ocpp_sessions os JOIN r ON r.sim_run_id = os.sim_run_id
   WHERE os.stopped_reason = 'completed' AND os.ended_at IS NOT NULL AND os.vehicle_id IS NOT NULL
     AND os.created_at > (SELECT min(started_at) FROM tr) - interval '21 days'),
c AS (
  SELECT s.sim_run_id, s.created_at,
         CASE WHEN s.has_visit IS NULL THEN 'boot'
              WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(s.atoms) a
                            WHERE COALESCE((a ->> 'must_do')::boolean, false) AND a ->> 'concurrency' = 'bay'
                              AND COALESCE((a ->> 'done_at')::timestamptz, (a ->> 'closed_at')::timestamptz, 'infinity'::timestamptz) > s.ended_at)
              THEN 'bay' ELSE 'clear' END AS cls,
         GREATEST(extract(epoch FROM (CASE WHEN s.next_out IS NOT NULL AND (s.next_charge IS NULL OR s.next_out <= s.next_charge)
                                         THEN s.next_out ELSE LEAST(COALESCE(s.next_charge, s.run_end), s.run_end) END - s.ended_at)) / 60.0, 0)::float8 AS t,
         (s.next_out IS NOT NULL AND (s.next_charge IS NULL OR s.next_out <= s.next_charge)) AS ev
    FROM s),
trn AS (
  SELECT tr.sim_run_id AS test_run, c.cls, c.t, c.ev
    FROM tr JOIN c ON c.created_at > tr.started_at - interval '21 days' AND c.created_at <= tr.started_at),
g AS (
  SELECT test_run, k.cls, t, count(*) FILTER (WHERE ev) AS d, count(*) AS m
    FROM trn CROSS JOIN LATERAL (VALUES (trn.cls), ('all')) k(cls)
   GROUP BY test_run, k.cls, t),
rk AS (SELECT g.*, sum(g.m) OVER (PARTITION BY test_run, cls ORDER BY t DESC) AS at_risk FROM g),
km AS (SELECT rk.test_run, rk.cls, rk.t,
              sum(ln(GREATEST(1 - rk.d::float8 / rk.at_risk, 1e-12))) OVER (PARTITION BY test_run, cls ORDER BY t) AS ls FROM rk),
h AS (SELECT unnest(ARRAY[10, 30, 60])::float8 AS hz),
f AS (SELECT km.test_run, km.cls, h.hz, 1 - exp(COALESCE((SELECT k2.ls FROM km k2 WHERE k2.test_run = km.test_run AND k2.cls = km.cls AND k2.t <= h.hz
                                                       ORDER BY k2.t DESC LIMIT 1), 0)) AS fh
        FROM (SELECT DISTINCT test_run, cls FROM km) km CROSS JOIN h),
te AS (
  SELECT tr.sim_run_id AS test_run, c.cls, c.t, c.ev, h.hz,
         CASE WHEN c.ev AND c.t <= h.hz THEN 1 WHEN c.t > h.hz THEN 0 END AS y
    FROM tr JOIN c ON c.sim_run_id = tr.sim_run_id CROSS JOIN h),
sc AS (
  SELECT te.test_run, te.hz, te.cls, te.y, fc.fh AS p_cls, fa.fh AS p_all
    FROM te JOIN f fc ON fc.test_run = te.test_run AND fc.cls = te.cls AND fc.hz = te.hz
            JOIN f fa ON fa.test_run = te.test_run AND fa.cls = 'all' AND fa.hz = te.hz
   WHERE te.y IS NOT NULL),
agg AS (
  SELECT sc.test_run, sc.hz, count(*) AS n, avg(sc.y) AS rate,
         avg((sc.p_all - sc.y) ^ 2) AS b_all, avg((sc.p_cls - sc.y) ^ 2) AS b_cls,
         sum(sc.p_all) / NULLIF(sum(sc.y), 0) AS er_all, sum(sc.p_cls) / NULLIF(sum(sc.y), 0) AS er_cls
    FROM sc GROUP BY sc.test_run, sc.hz),
bycls AS (
  SELECT x.test_run, x.hz, jsonb_object_agg(x.cls, jsonb_build_array(x.n, round(x.rate::numeric, 3), round(x.b_all::numeric, 4), round(x.b_cls::numeric, 4))) AS j
    FROM (SELECT sc.test_run, sc.hz, sc.cls, count(*) AS n, avg(sc.y) AS rate,
                 avg((sc.p_all - sc.y) ^ 2) AS b_all, avg((sc.p_cls - sc.y) ^ 2) AS b_cls
            FROM sc GROUP BY sc.test_run, sc.hz, sc.cls) x
   GROUP BY x.test_run, x.hz)
SELECT left(agg.test_run::text, 8) AS run, agg.hz, agg.n, round(agg.rate::numeric, 3) AS rate,
       round(agg.b_all::numeric, 4) AS brier_pooled, round(agg.b_cls::numeric, 4) AS brier_class,
       round((agg.rate * (1 - agg.rate))::numeric, 4) AS brier_base,
       round(agg.er_all::numeric, 3) AS exp_real_pooled, round(agg.er_cls::numeric, 3) AS exp_real_class,
       bycls.j AS by_class_n_rate_pooled_class
  FROM agg JOIN bycls USING (test_run, hz) JOIN tr ON tr.sim_run_id = agg.test_run
 ORDER BY tr.started_at, agg.hz;

-- (4) the bay cars: how long after the charge the last bay service was done, and how long after that the car left, by
--     run (runs with ten or more). As written, the 21 days to 0624's apply; for the 21 days before d9d49732 began, put
--     its started_at in both places the apply's time appears
WITH r AS (
  SELECT x.sim_run_id FROM public.ottoq_sim_runs x
   WHERE x.depot_id = '11111111-1111-1111-1111-111111111111' AND x.tick_count > 0
     AND x.sim_clock_current IS NOT NULL AND x.sim_clock_start IS NOT NULL
     AND extract(epoch FROM (x.sim_clock_current - x.sim_clock_start)) / 60.0 / x.tick_count <= 1),
s AS MATERIALIZED (
  SELECT os.sim_run_id, os.vehicle_id, os.ended_at,
         (SELECT COALESCE(vn.atoms, '[]'::jsonb) FROM public.ottoq_visit_needs vn
           WHERE vn.sim_run_id = os.sim_run_id AND vn.vehicle_id = os.vehicle_id AND vn.arrived_at <= os.started_at
           ORDER BY vn.arrived_at DESC, vn.created_at DESC LIMIT 1) AS atoms,
         (SELECT min(dd.dispatched_at) FROM public.ottoq_vehicle_dispatches dd
           WHERE dd.sim_run_id = os.sim_run_id AND dd.vehicle_id = os.vehicle_id AND dd.dispatched_at >= os.ended_at) AS next_out
    FROM public.ocpp_sessions os JOIN r ON r.sim_run_id = os.sim_run_id
   WHERE os.stopped_reason = 'completed' AND os.ended_at IS NOT NULL AND os.vehicle_id IS NOT NULL
     AND os.created_at > '2026-10-08 20:44:12+00'::timestamptz - interval '21 days' AND os.created_at <= '2026-10-08 20:44:12+00'),
b AS (
  SELECT s.*, (SELECT max(COALESCE((a ->> 'done_at')::timestamptz, (a ->> 'closed_at')::timestamptz))
                 FROM jsonb_array_elements(s.atoms) a
                WHERE COALESCE((a ->> 'must_do')::boolean, false) AND a ->> 'concurrency' = 'bay') AS bay_done
    FROM s WHERE public.ottoq_dwell_class(s.atoms, s.ended_at) = 'bay'),
per AS (
  SELECT left(b.sim_run_id::text, 8) AS run, count(*) AS bay_charges,
         count(*) FILTER (WHERE b.next_out IS NOT NULL AND b.bay_done IS NOT NULL AND b.next_out >= b.bay_done) AS left_after_bay,
         round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (b.bay_done - b.ended_at)) / 60.0)::numeric, 1) AS bay_done_after_charge_min,
         round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (b.next_out - b.bay_done)) / 60.0)
                  FILTER (WHERE b.next_out IS NOT NULL AND b.bay_done IS NOT NULL AND b.next_out >= b.bay_done))::numeric, 2) AS left_after_bay_done_min
    FROM b GROUP BY 1)
SELECT (SELECT count(*) FROM s) AS charges, (SELECT count(*) FROM b) AS bay_charges,
       (SELECT jsonb_agg(per ORDER BY per.bay_done_after_charge_min) FROM per WHERE per.bay_charges >= 10) AS runs_10_plus;
