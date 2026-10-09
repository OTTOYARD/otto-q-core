-- 0419  **The charge clock's world changed at 0573, the clock could not see it, and now it can, and can find the next
--        one itself (0625, G359).** 0573 rebuilt the twin's fast-charge physics on 2026-09-30 at 11:53:08 UTC. The
--        clock (0622) went on learning from both sides of it: the Zoox fast-charge residual was +0.78 to +1.19 on the
--        three days before and -0.11 to -0.17 on every day since. Cut at the change, the clock's fast-charge error out of
--        sample falls on 5 of 5 runs (-23% to -55%), while cutting L2 at the same line helps 3 and costs 2, and the
--        departure dwell grades worse. The scan 0625 adds finds the change in the clock's own evidence before anything
--        records it, bounds it to a window that holds 0573, and marks 0573 among the migrations applied in it. Fitted
--        after the change alone, the clock's run spread on fast chargers falls from 0.184 to 0.055: most of what 0622
--        read as the day a run is having was the two worlds (G360 corrects what the self-review made of it). One fit per
--        run and one live record: single readings, not ranges.
--
--       Written 2026-10-08, 5:20 PM CT. Read-only. Twin depot 11111111-…; the five runs started 2026-10-02 to 10-08
--       (ae8a4908, fd6ed035, 0bbdcc07, 089f46bd, d9d49732 with baf29c05) and the charges of the 21 days before each.
--       Measured 3:40-4:40 PM CT against fit 1 (0622, 11:24 AM CT) before 0625 was written, and through 0625's own
--       functions after its apply (20261008214932, 4:49 PM CT; fit 3).
--
-- ══ §1 WHAT WAS MEASURED ══
--
--   The clock times a charge as 0614's base estimate times exp(f), f the sum of the levels it has learned (0622). A
--   charge's residual is the log of its real minutes over the base estimate, less f. Out of sample means a fit through
--   the moment the scored run began, scored on that run's completed charges as the agent's check times them (the run's
--   own charges so far, through ottoq_charge_clock_run_evidence). Fine ticks only (a tick of a minute or less), as the
--   clock fits.
--
-- ══ §2 THE BREAK, BY DAY (fast chargers, mean residual against fit 1; reproduce: (1)) ══
--
--                Zoox            Waymo           Tesla
--   09-27     35  +0.781      61  +0.051      51  -0.273
--   09-28    155  +1.051     178  +0.234     196  -0.013
--   09-29     14  +1.190      17  +0.313      28  +0.001
--   09-30     33  -0.135      31  +0.011      30  +0.023      0573 at 11:53:08 UTC
--   10-01     32  -0.141      40  -0.063      34  -0.018
--   10-02     47  -0.167      65  +0.063      49  +0.086
--   10-06     18  -0.136      19  -0.029      19  -0.013
--   10-07     49  -0.112      49  -0.042      42  +0.032
--   10-08     28  -0.112      29  +0.016      31  +0.037
--
--   On L2 the same days read -0.10 to +0.15 per class with no step at 09-30 (09-29's +0.04 to +0.15 is the day
--   before; 09-30 reads +0.01 to +0.04). 0573 changed the DC branch of ottoq_sim_compute_charge_rate (each battery's
--   own acceptance curve) and two cars' facts (the I-PACE to 84.7 kWh and 104 kW, the Zoox to 133 kWh and 100 kW); the
--   L2 branch is untouched and 19.2 kW is every car's limit on L2.
--
-- ══ §3 CUT AT THE CHANGE, OUT OF SAMPLE (reproduce: (2)) ══
--
--   Fast chargers, mean absolute log error, the 21-day fit against the same fit on the charges after 0573 alone:
--     run (fit through its start)     charges   21 days   cut     change   Zoox bias 21 days -> cut
--     ae8a4908  (10-02 16:31 UTC)          88    0.2472   0.1121   -55%     -0.345 -> -0.072
--     fd6ed035  (10-06 18:54)              56    0.1892   0.1060   -44%     -0.226 -> +0.012
--     0bbdcc07  (10-07 18:43)              65    0.1305   0.0866   -34%     -0.143 -> +0.014
--     089f46bd  (10-07 20:47)              51    0.1308   0.0854   -35%     -0.146 -> -0.014
--     d9d49732 + baf29c05 (10-08 13:53)    88    0.1098   0.0843   -23%     -0.131 -> -0.026   (0625's V2)
--   The gain shrinks as the change ages, as it should: the 3-day half-life buries old charges by itself, slowly.
--   ae8a4908 began 2.2 days after the change with 262 fast charges after it to learn from (257.9 effective), and
--   gained most: the cut clock carried the change as soon as it had enough to stand on.
--
--   L2, the same runs, cutting it at the same line too: 0.0928 -> 0.1069 (ae8a4908), 0.1020 -> 0.0992, 0.0893 ->
--   0.0902, 0.0978 -> 0.0937, 0.0852 -> 0.0760. Two worse, three better, no break by day: L2 is not cut (0625
--   records the change for fast chargers alone, and V1 asserts every L2 key unchanged).
--
--   And the departure dwell (0623/0624's return_v1), fitted on the evidence after 0573 alone, graded worse on
--   d9d49732's 61 orders: Brier by class 0.1011 -> 0.1091 against the base rate 0.1046, returns forecast over real
--   1.186 -> 1.324. Bay congestion moves the dwell (G358), not the charge curve, so a change is recorded per model and
--   return_v1 reads no record.
--
-- ══ §4 THE SCAN FINDS IT BY ITSELF (0625's V0 and V3; reproduce: (3)) ══
--
--   Over the charges since 2026-09-17, the run as the unit (a run's mean per class from 3 or more charges), every split
--   of the 30 runs with fast charges in recorded order:
--     fast chargers  q 777.2 on 3 classes   Zoox -1.140 (t -27.0)  Waymo -0.211 (t -6.4)  Tesla +0.089 (t 2.3)
--                    best split between 2026-09-29 19:16 and 09-30 02:47 UTC; the splits within max(2 df + 2, 5% of
--                    q) of it span 09-29 01:18:36 to 09-30 12:58:00, which holds 0573 (11:53:08). 17 migrations were
--                    applied in that window; two create or replace a function about charging: 0570
--                    (ottoq_charge_slack_min, the batch optimizer) and 0573 (ottoq_sim_compute_charge_rate).
--     L2             q 21.8 on 3 classes, largest shift 0.098: not named (the rule asks q >= 10 per class and a
--                    class past 0.15).
--   The best split sits nine hours before 0573 because the two small runs between (1ebae97a, 685621d5: 13 and 8 fast
--   charges, no Zoox past 3) carry Waymo and Tesla only, whose shifts are small; the window is what to read, and why
--   the scan reports one. After the record the scan starts at the change: fast chargers 647 charges, 14 runs, q 6.6,
--   largest shift 0.064, not named; L2 q 22.6, largest shift 0.099, not named.
--
-- ══ §5 WHAT THE TWO WORLDS WERE HIDING IN THE CLOCK'S STRUCTURE (0625's V1 and fit 3) ══
--
--                                      fit through d9d49732's start          at 0625's apply
--                                      21 days        cut at 0573            fit 1       fit 3
--   fast-charge pooled n                  1,305          559                  1,376        647
--   run spread (tau)                      0.184          0.055                0.186        0.046
--   run prior strength (k)                  -              -                  3.52        14.66
--   car's correlation across runs         0.284          0.548                0.273        0.694
--   car's correlation within a run        0.911          0.505                0.910        0.514
--
--   0622 §1(c) read a run spread of 0.19 as the day a run is having and an in-run correlation of 0.91-0.96 as a car's
--   condition carried from charge to charge. With the change cut out, the run spread is a quarter of that and the car's
--   own level across runs carries more than its in-run condition. The pre-change charges sat in different runs from
--   the post-change ones, so the two worlds read as runs that differ and as cars whose offsets do not hold across runs.
--   The clock now trusts a car's history more and a run's first charges less, which is what the twin's physics says it
--   should (each car's curve is a fixed battery, 0573).
--
-- ══ §6 WHAT THE SELF-REVIEW SAID, AND WHAT IT WAS (G360; reproduce: (4)) ══
--
--   0622's audit takes the residuals of the depot's fine-tick charges and asks, for each recorded variable, what share
--   of them it explains (adjusted eta squared). It does not take the run's level out first, though the clock itself
--   does (0622's run evidence). On the 7 days to 2026-10-08 21:00 UTC (12 runs), the share explained, as the audit
--   computes it and within runs (each run's mean taken out):
--                           fast chargers (458)                          L2 (613)
--                       fit 1           fit 3 (in sample)          fit 1          fit 3
--   run              0.215 / -0.022    0.327 / -0.022           0.271 / -0.018   0.272 / -0.018
--   air temperature  0.276 /  0.043    0.411 /  0.062           0.283 /  0.031   0.278 /  0.029
--   class            0.236 /  0.241    0.009 /  0.002          -0.001 / -0.002  -0.002 / -0.002
--   make and model   0.260 /  0.269    0.013 / -0.002          -0.005 / -0.004  -0.006 / -0.005
--   car              0.075 /  0.076   -0.048 / -0.041          -0.065 / -0.067  -0.063 / -0.064
--   mean |residual|  0.121             0.083                    0.089            0.089
--
--   Two different things were being reported as one kind of area. The class and model shares on fast chargers were
--   real (they hold within runs): levels gone stale across 0573, and fit 3 removes them. The air-temperature share was
--   mostly the run: a run is one day of weather, so its level and its temperature move together; within runs it is 3-6%.
--   The 6.2% on fast chargers under fit 3 is above the audit's 5% line and has a mechanism (the twin's battery
--   temperature derate on DC charging), so it is a small real variable the clock misses; the 28-41% the audit reports
--   is not. 0626 will judge the audit within runs.
--
-- ══ §7 CORRECTIONS ══
--
--   0625's header says its dry run ran at 23:52 UTC and that its section 1 was measured 20:40-23:30 UTC. Both are slips
--   for 21:35 UTC (4:35 PM CT) and 20:40-21:30 UTC (3:40-4:30 PM CT). Its §1(b) gives ae8a4908 "606 charges to learn
--   from": that is both kinds after the change; the fast charges were 262 (257.9 effective), as (2) returns. The
--   applied file is left as applied; the log row and this check carry the corrections.
--
-- ══ §8 REPRODUCE ══
--
--   Each runs inside the SQL editor's 58 s on live; (2) one run per call.

SET statement_timeout = '58s';

-- (1) the fast-charge residual by day and class, against fit 1 (0622's first fit)
WITH m AS (SELECT jsonb_build_object('params', f.params) AS j2 FROM public.ottoq_charge_clock_fits f WHERE f.fit_id = 1),
e AS (
  SELECT date_trunc('day', l.recorded_at)::date AS day, w.j ->> 'cls' AS cls,
         ln((l.duration_min / est.m)::numeric) - (public.ottoq_charge_clock(m.j2, l.charger_type, w.j, l.battery_kwh, l.soc_start,
                                                     l.soc_end, l.charger_kw, l.vehicle_kw, NULL) ->> 'f')::numeric AS res
    FROM m, public.ottoq_charge_duration_ledger l
    JOIN public.vehicles v ON v.id = l.vehicle_id
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                    l.vehicle_kw) AS m) est
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.recorded_at BETWEEN '2026-09-17' AND '2026-10-08 21:00+00'
     AND l.stopped_reason = 'completed' AND l.charger_type = 'dcfc' AND l.duration_min > 0 AND l.soc_end > l.soc_start
     AND est.m > 0 AND l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1)
SELECT e.day, jsonb_object_agg(e.cls, jsonb_build_array(e.n, e.mr) ORDER BY e.cls) AS cls_n_mean_residual
  FROM (SELECT day, cls, count(*) AS n, round(avg(res), 3) AS mr FROM e GROUP BY day, cls) e
 GROUP BY e.day ORDER BY e.day;

-- (2) one run out of sample: the clock through the run's start, uncut against cut at 0573 for fast chargers
--     (ae8a4908, fd6ed035, 0bbdcc07, 089f46bd one at a time; d9d49732 with baf29c05 through d9d49732's start)
SELECT public.ottoq_charge_clock_trial('11111111-1111-1111-1111-111111111111'::uuid,
         ARRAY(SELECT r.sim_run_id FROM public.ottoq_sim_runs r WHERE left(r.sim_run_id::text, 8) = 'ae8a4908'),
         NULL, '{}'::jsonb, '{"dcfc": "2026-09-30T11:53:08+00:00"}'::jsonb) -> 'by_kind' AS by_kind;

-- (3) the scan as V0 ran it, before the record: on live the record now exists and the scan starts at it by design, so
--     this is the scan's own query with the start fixed at 2026-09-17 and the record not read
WITH m AS MATERIALIZED (SELECT jsonb_build_object('params', f.params) AS j FROM public.ottoq_charge_clock_fits f WHERE f.fit_id = 1),
e AS MATERIALIZED (
  SELECT l.charger_type AS kind, l.sim_run_id::text AS run, l.recorded_at, w.j ->> 'cls' AS cls,
         ln((l.duration_min / est.m)::float8)
           - (public.ottoq_charge_clock(m.j, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                        l.vehicle_kw, NULL) ->> 'f')::float8 AS r
    FROM m, public.ottoq_charge_duration_ledger l
    JOIN public.vehicles v ON v.id = l.vehicle_id
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                    l.vehicle_kw) AS m) est
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.recorded_at > '2026-09-17'
     AND l.recorded_at <= '2026-10-08 21:00+00' AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2')
     AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0 AND l.tick_minutes IS NOT NULL
     AND l.tick_minutes <= 1 AND l.sim_run_id IS NOT NULL
), rc AS (
  SELECT e.kind, e.cls, e.run, count(*) AS n, avg(e.r) AS mr, min(e.recorded_at) AS t_first, max(e.recorded_at) AS t_last
    FROM e GROUP BY e.kind, e.cls, e.run HAVING count(*) >= 3
), rk AS (
  SELECT x.kind, x.run, x.t_first, x.t_last, row_number() OVER (PARTITION BY x.kind ORDER BY x.t_first, x.run) AS o
    FROM (SELECT rc.kind, rc.run, min(rc.t_first) AS t_first, max(rc.t_last) AS t_last FROM rc GROUP BY rc.kind, rc.run) x
), ru AS (
  SELECT rc.*, rk.o FROM rc JOIN rk USING (kind, run)
), st AS (
  SELECT sp.kind, sp.o AS s, ru.cls,
         count(*) FILTER (WHERE ru.o < sp.o) AS kb, count(*) FILTER (WHERE ru.o >= sp.o) AS ka,
         avg(ru.mr) FILTER (WHERE ru.o < sp.o) AS mb, avg(ru.mr) FILTER (WHERE ru.o >= sp.o) AS ma,
         sum(ru.mr * ru.mr) FILTER (WHERE ru.o < sp.o) AS qb, sum(ru.mr * ru.mr) FILTER (WHERE ru.o >= sp.o) AS qa
    FROM rk sp JOIN ru ON ru.kind = sp.kind WHERE sp.o > 1 GROUP BY sp.kind, sp.o, ru.cls
), tq AS (
  SELECT st.*, st.ma - st.mb AS shift,
         (st.ma - st.mb) / (GREATEST(sqrt(GREATEST(st.qb - st.kb * st.mb * st.mb + st.qa - st.ka * st.ma * st.ma, 0)
                                          / (st.kb + st.ka - 2)), 0.02) * sqrt(1.0 / st.kb + 1.0 / st.ka)) AS t
    FROM st WHERE st.kb >= 3 AND st.ka >= 3
), q AS (
  SELECT tq.kind, tq.s, sum(tq.t * tq.t) AS q, count(*) AS df, max(abs(tq.shift)) AS max_shift,
         jsonb_object_agg(tq.cls, jsonb_build_array(round(tq.shift::numeric, 3), round(tq.t::numeric, 1))) AS cls
    FROM tq GROUP BY tq.kind, tq.s
), best AS (
  SELECT DISTINCT ON (q.kind) q.* FROM q ORDER BY q.kind, q.q DESC, q.s
), near AS (
  SELECT q.kind, min(q.s) AS s_lo, max(q.s) AS s_hi FROM q JOIN best b USING (kind)
   WHERE q.q >= b.q - GREATEST(2 * b.df + 2, 0.05 * b.q) GROUP BY q.kind
)
SELECT b.kind, round(b.q::numeric, 1) AS q, b.df, round(b.max_shift::numeric, 3) AS max_shift, b.cls,
       (SELECT max(r.t_last) FROM rk r WHERE r.kind = b.kind AND r.o < n.s_lo) AS window_from,
       (SELECT r.t_first FROM rk r WHERE r.kind = b.kind AND r.o = n.s_hi) AS window_to
  FROM best b JOIN near n USING (kind) ORDER BY b.kind;

-- (4) the audit's shares, as it computes them and within runs, under fit 1 and fit 3, on the 7 days to 10-08 21:00 UTC
WITH mm AS (SELECT f.fit_id, jsonb_build_object('params', f.params) AS j2 FROM public.ottoq_charge_clock_fits f WHERE f.fit_id IN (1, 3)),
e AS (
  SELECT mm.fit_id, l.sim_run_id AS run, l.charger_type AS kind, w.j AS who, l.ambient_temp_c,
         ln((l.duration_min / est.m)::numeric) - (public.ottoq_charge_clock(mm.j2, l.charger_type, w.j, l.battery_kwh, l.soc_start,
                                                     l.soc_end, l.charger_kw, l.vehicle_kw, NULL) ->> 'f')::numeric AS res2
    FROM mm, public.ottoq_charge_duration_ledger l
    JOIN public.vehicles v ON v.id = l.vehicle_id
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                    l.vehicle_kw) AS m) est
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.recorded_at >= '2026-10-01 21:00+00'
     AND l.recorded_at <= '2026-10-08 21:00+00' AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2')
     AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0 AND l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1),
r AS (SELECT e.*, e.res2 - avg(e.res2) OVER (PARTITION BY e.fit_id, e.kind, e.run) AS rw FROM e),
cv AS (
  SELECT r.fit_id, r.kind, x.cov, x.val, r.res2, r.rw
    FROM r CROSS JOIN LATERAL (VALUES
      ('class', r.who ->> 'cls'), ('model', r.who ->> 'mdl'), ('vehicle', r.who ->> 'veh'), ('run', r.run::text),
      ('ambient_c', CASE WHEN r.ambient_temp_c IS NULL THEN 'unknown' ELSE (5 * floor(r.ambient_temp_c / 5))::int::text END)) x(cov, val)),
g0 AS (SELECT fit_id, kind, cov, val, count(*) AS n FROM cv GROUP BY 1, 2, 3, 4),
cv2 AS (SELECT cv.fit_id, cv.kind, cv.cov, CASE WHEN g0.n >= 5 THEN cv.val ELSE '(small)' END AS val, cv.res2, cv.rw
          FROM cv JOIN g0 USING (fit_id, kind, cov, val)),
g AS (SELECT fit_id, kind, cov, val, count(*) AS n, avg(res2) AS m, avg(rw) AS mw FROM cv2 GROUP BY 1, 2, 3, 4),
t AS (SELECT fit_id, kind, cov, count(*) AS n, avg(res2) AS m, avg(rw) AS mw,
             sum((res2 - (SELECT avg(c3.res2) FROM cv2 c3 WHERE c3.fit_id = cv2.fit_id AND c3.kind = cv2.kind AND c3.cov = cv2.cov)) ^ 2) AS sst,
             sum(rw ^ 2) AS sstw
        FROM cv2 GROUP BY 1, 2, 3),
b AS (SELECT g.fit_id, g.kind, g.cov, count(*) AS groups, sum(g.n * (g.m - t.m) ^ 2) AS ssb, sum(g.n * (g.mw - t.mw) ^ 2) AS ssbw
        FROM g JOIN t USING (fit_id, kind, cov) GROUP BY 1, 2, 3)
SELECT b.fit_id, b.kind, max(t.n) AS n,
       jsonb_object_agg(b.cov, jsonb_build_array(
         round((1 - (1 - b.ssb / NULLIF(t.sst, 0)) * (t.n - 1) / NULLIF(t.n - b.groups, 0))::numeric, 3),
         round((1 - (1 - b.ssbw / NULLIF(t.sstw, 0)) * (t.n - 1) / NULLIF(t.n - b.groups, 0))::numeric, 3))) AS share_and_within_run
  FROM b JOIN t USING (fit_id, kind, cov) GROUP BY b.fit_id, b.kind ORDER BY b.kind, b.fit_id;
