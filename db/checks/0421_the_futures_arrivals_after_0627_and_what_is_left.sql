-- 0421  **The futures' arrivals after 0627, read on live, and what is left of their error (G363 fixed; G365-G367).**
--        0627 is applied (20261009002205, 7:22 PM CT). Read back on live its gate is exact: on d9d49732's 2,503
--        forecast arrivals, the late tail 104 -> 9, the early tail 68 -> 2, the mean absolute error 3.229 -> 2.633
--        minutes, 79.9% -> 85.1% inside the 80% band. In parts: each car's own reserve rung takes the late tail to 31
--        and the error to 2.633; the drive's own spread takes the late tail to 8; the other calls home take the early
--        tail to 2. Those arrivals are 89 returns seen by 61 orders, a mean of 28 orders each: in returns, late 29 -> 2
--        and early 13 -> 1. One run: single readings, not ranges. The band is not the whole story. 2.4% of the arrivals
--        fall below it and 12.5% above, against 10% each, and two things put them there. The futures drain every car at
--        one rate and the makes drain differently: out of sample, a drain per make takes the mean absolute error from
--        2.633 to 1.570 minutes (G365). And the other calls home ran at half the fit's rate on this run (G366). The fit
--        "through the run's start" that 0623, 0624 and 0627 grade against holds 33 of the run's own returns; taken out,
--        the gate reads the same within two arrivals (G367). The self-review now marks the arrivals built and ranks the
--        air temperature first. It cannot see G365 or G366 until an armed run's orders are graded under 0627.
--
--       Written 2026-10-08, 7:45 PM CT. Read-only. Twin depot 11111111-…; run d9d49732 (started 2026-10-08 13:53:16
--       UTC, 8:53 AM CT) and its 61 graded orders; the return fit through the run's start, as V1 and V2 compute it.
--
-- ══ §1 THE GATE, IN PARTS (reproduce: (1) and (1b)) ══
--
--   Each car at work at an order that came home inside the order's window, forecast four ways from the same battery
--   (the recall decision's own record at the order) and the order's own drain (0.7176% a minute, log spread 0.092):
--
--                                                     late    early   inside the   mean absolute
--                                                     z > 3   z < -3  80% band     error, minutes
--     0626's forecast: one reserve for all, 49.9%       104      68     79.9%        3.229
--     + each car's own reserve rung                      31      56     84.1%        2.633
--     + the drive's own spread, in minutes                8      56     85.0%        2.633
--     + the other calls home: 0627 as built               9       2     85.1%        2.633
--
--   The rung moves the forecast's median and so the error; the spread and the other calls only move where an arrival
--   falls in the forecast. 269 arrivals were forecast at a rung of 45 (a reserve of 15 on a margin-30 run) and came
--   home a mean 8.40 minutes after the old forecast and 1.61 after the new; the 2,234 at a rung of 50 -0.20 and +0.01.
--   The late tail grows by one with the other calls (8 -> 9): a forecast that can call a car home early puts more of
--   its probability early, so a late arrival reads later in it, never earlier.
--   0627 §1(c)'s probe before the build read 84.7% inside the band for the rung alone. The shipped function reads 84.1%
--   on each order's drain and 84.3% on the fit's (0.7170). The probe is not reproduced; its tails (31 and 56) are, and
--   so are V2's figures, exactly.
--
-- ══ §2 ARRIVALS ARE NOT RETURNS (reproduce: (2)) ══
--
--   A car at work is in every order's forecast until it comes home, so one return is graded by every order whose
--   window it fell in. The 2,503 arrivals are 89 returns of 88 cars, seen by a mean of 28 orders: 84 reserve returns
--   (2,412 arrivals), 4 on stale telemetry (88) and 1 on a rider's flag (3). In returns:
--     late tail    104 arrivals = 29 returns   ->  9 arrivals = 2 returns: 1 reserve return 4.3 minutes from its rung
--                                                  at the order, +3.2 minutes; 1 on stale telemetry, +9.6
--     early tail    68 arrivals = 13 returns   ->  2 arrivals = 1 return on stale telemetry, -13.9 minutes
--   The reserve returns fall 88.3% inside the band (mean error +0.52 minutes); the stale-telemetry returns 0 of 88.
--   Every rate in this file is over arrivals, as the gate reads them; G153's rule is why the counts are given in
--   returns as well.
--
-- ══ §3 THE EARLY TAIL IS NO LONGER A TEST; THE BAND'S EDGES ARE (reproduce: (2)) ══
--
--   With the other calls home at 0.001855 a minute and their drive at 1.63 minutes (the fit through the run's start),
--   the forecast gives every car at least 1 - exp(-0.001855 (t - 1.63)) of being home by t minutes. That passes
--   Phi(-3) = 0.00135 at t = 2.36, so only an arrival inside 2.36 minutes of its order can read below -3. The early
--   tail fell to 2 partly by construction. The early side's test is now the band's lower edge, and the band's two
--   edges do not hold: 2.44% of the arrivals fall below it and 12.47% above, against 10% each. By tenth of the
--   forecast's own probability (250 arrivals each if the forecast were right):
--     0626's   122  208  290  304  258  266  144  140  390  381
--     0627's    61   43  276  341  375  356  271   72  396  312
--   85.1% inside the band is too few below it and a few too many above. §4 and §5 are why.
--
-- ══ §4 THE MAKES DRAIN DIFFERENTLY (G365; reproduce: (3) and (4)) ══
--
--   The futures drain every working car at the depot's one rate. Each return once, the reserve returns more than 5
--   minutes from their rung at the order:
--     make            battery   returns   drain seen, % a minute   mean error   mean |error|   home after the forecast
--     Tesla Model Y   76.4 kWh     31          0.750                 -1.59         1.97          3 of 31
--     Jaguar I-PACE   85.2 kWh     34          0.716                 +0.21         1.21         19 of 34
--     Zoox            133 kWh      19          0.647                 +4.89         4.89         19 of 19
--   Every Zoox car came home after its forecast, by about 5 minutes. The source says why: twin.ottoq_sim_advance_
--   deployed_telemetry derives a working car's battery from the energy it has used over its battery's capacity, the
--   power from its speed, the air, its own consumption scalar (drawn at boot) and the out-drain (0486). A level per
--   make, per car and per run is the mechanism, the same shape as the charge clock's (0622).
--   Out of sample: the reserve returns of the 21 days before d9d49732 (fine ticks, the run's own taken out) give
--   Tesla 0.7513 (403 returns, log spread 0.046), Jaguar 0.7208 (480, 0.043) and Zoox 0.6443 (322, 0.030), against
--   0.7176 (0.092) pooled. Each make's own spread is a third to a half of the pooled one: the pooled spread is mostly
--   the gap between makes. Forecast at its make's drain, d9d49732's 2,503 arrivals:
--     mean absolute error   2.633 -> 1.570 minutes
--     Zoox                  5.17 -> 2.01 (mean +3.03 -> -1.27)
--     Tesla                 2.37 -> 1.55 (-1.94 -> -0.22)
--     Jaguar                1.30 -> 1.32 (+0.28 -> +0.45)
--   Not built. The build: return_v1 learns the drain per make (and per car where it has the returns), pooled toward
--   the depot's, and the inbound forecast and the outflow read each car's own, with its own spread.
--
-- ══ §5 THE OTHER CALLS HOME RAN AT HALF THE FIT'S RATE ON THIS RUN (G366; reproduce: (2), (5) and (5b)) ══
--
--                                                    other calls   hours at work   an hour   service  stale  rider  rest
--     the fit through the run's start, as fitted         172          1,545.6      0.1113      72      58      6     36
--     the same without the run's own returns             171          1,508.1      0.1134      72      57      6     36
--     run d9d49732                                          6            112.6      0.0533       0       5      1      0
--   Over the 2,503 arrivals the forecast expected 168.5 to come home on another call and 91 did (5 returns; (2)). On
--   the fit's runs the calls come at 0.174 an hour in a car's first 10 minutes out, 0.087 from 10 to 30 and 0.107
--   after ((5b)), so where a car is in its shift does not explain a run at half the rate: this run drew no
--   service-interval call at all. Not built. The build: the run's own rate, learned as it goes, the depot's rate its
--   prior and the run's own calls and hours at work its evidence.
--
-- ══ §6 THE FIT "THROUGH THE RUN'S START" HOLDS THE RUN'S OWN RETURNS (G367; reproduce: (6)) ══
--
--   ottoq_return_model_params cuts its evidence on each dispatch's created_at. A run creates its first dispatches in
--   the transaction that starts it, so they carry the run's started_at to the microsecond, and a fit through that
--   moment reads them, returns and all, though every return came later. d9d49732: 46 dispatches created at its start,
--   33 of them in the fit's evidence (32 reserve returns, 1 on stale telemetry), 33 of the fit's 1,409 ((6a), (6b)).
--   Without them:
--     drain 0.7170 -> 0.7176, its log spread 0.0931 -> 0.0924, the drive's spread 0.187 -> 0.182 minutes, the drive
--     after another call 1.63 -> 1.63, the other calls 0.1113 -> 0.1134 an hour
--   and the gate reads late 11, early 2, 85.1% inside the band, error 2.633 ((6c)): V2's verdict stands. The nightly
--   fit (through now()) is not touched: every return it reads has happened. Every back-dated fit is, and it is what
--   0623's, 0624's and 0627's gates call out of sample. The fix is a cut on what had happened by then, or the strict
--   inequality, which is enough for a fit through a run's own start. Not built.
--
-- ══ §7 THE REVIEW, READ AFTER THE APPLY (reproduce: (7)) ══
--
--   rank  status    impact  title
--      1  open       15.1%  The charge clock does not see the air temperature                          G361
--      2  open       15.1%  The charge clock is surer than the charges on fast chargers                G362
--      3  open       14.8%  Charger faults it never sampled moved its verdicts                         G364
--      4  open         -    Its simulator places a plug-in 11 minutes off, even given what happened
--      5  open         -    It never adds back a charger whose hold ends
--      6  open, thin   -    Taking none of these orders would have done better
--      7  open, thin   -    Its odds of winning predict no better than the base rate
--      8  built      24.3%  Cars it never saw coming moved its verdicts
--      9  built      23.9%  Charges under way ended sooner than it expected
--     10  built      21.9%  A few cars come home far from their forecast                               G363
--     11  built      15.1%  Some makes' charges on L2 chargers ran off its forecast
--   The arrivals' finding now ends "These orders were made before the futures called each car home at its own reserve
--   rung, with the other calls home beside it, so this is history until new orders are graded", and its action reads
--   "Grade the next armed run's orders". The review grades orders, and the 61 it holds were made before 0627: G365
--   and G366 were found by forecasting those orders' arrivals again, which the review does not do.
--
-- ══ §8 THE RUNG, CHECKED AGAIN (reproduce: (8)) ══
--
--   On the latest 50 recall decisions of each of the 152 twin runs of the 21 days, 7,600 of 7,600: the rung equals the
--   decision's own record, its reserve plus its margin. Three rungs occur: 40, 45 and 50.
--
-- ══ §9 REPRODUCE ══
--
--   Each runs inside the SQL editor's 58 s on live. (1), (1b), (2) and (6c) share their first steps.

SET statement_timeout = '58s';

-- (1) the gate in parts, out of sample (the fit through the run's start, as V2 computes it)
WITH fit AS MATERIALIZED (
  SELECT public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid, r.started_at, interval '21 days') AS p
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'
), rc AS MATERIALIZED (
  SELECT jsonb_build_object('lam', round(COALESCE((p ->> 'other_per_work_hour')::numeric, 0) / 60.0, 6),
                            'trip_o', COALESCE((p ->> 'trip_other_min')::numeric, (p ->> 'trip_min')::numeric, 0)) AS j,
         COALESCE((p ->> 'trip_sd_min')::float8, 0) AS asd
    FROM fit
), ar AS (
  SELECT h.order_id, s.sim_run_id AS run, s.sim_clock AS clock, ib.value AS e, (ib.value ->> 'id')::uuid AS vid,
         (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
         (ib.value ->> 'eta')::float8 AS fc, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip,
         (ib.value ->> 'esd')::float8 AS esd0, le.params AS mp
    FROM public.ottoq_charge_order_hindsight h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    JOIN public.ottoq_learned_estimates le ON le.estimate_id = (s.state #>> '{models,return}')::bigint
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
   WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND ib.value ->> 'src' = 'forecast'
     AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
     AND COALESCE((ib.value ->> 'esd')::float8, 0) > 0
), b AS (
  SELECT ar.*, rd.soc0, public.ottoq_recall_threshold_soc(ar.vid, ar.run, ar.clock)::float8 AS thr,
         (ar.mp ->> 'drain_pct_per_min')::float8 AS dr, COALESCE((ar.mp ->> 'drain_log_sd')::float8, 0) AS dsd
    FROM ar
    CROSS JOIN LATERAL (SELECT r.soc_override::float8 AS soc0 FROM public.ottoq_recall_decisions r
                         WHERE r.sim_run_id = ar.run AND r.vehicle_id = ar.vid AND r.decided_at_sim <= ar.clock
                           AND r.inputs ? 'reserve'
                         ORDER BY r.decided_at_sim DESC LIMIT 1) rd
   WHERE ar.act > ar.trip AND ar.fc > ar.trip
), f AS (
  SELECT b.*, GREATEST((b.soc0 - b.thr) / b.dr, 0) AS hz FROM b WHERE b.dr > 0 AND b.thr IS NOT NULL
), z AS (
  SELECT f.*,
         public.ottoq_inbound_arrival_z(f.e, NULL, f.act) AS z_old,
         public.ottoq_inbound_arrival_z(jsonb_build_object('eta', f.hz + f.trip, 'trip', f.trip, 'esd', f.esd0), NULL, f.act) AS z_rung,
         public.ottoq_inbound_arrival_z(jsonb_build_object('eta', f.hz + f.trip, 'trip', f.trip,
                                        'esd', sqrt(f.dsd ^ 2 + (rc.asd / GREATEST(f.hz, 0.25)) ^ 2)), NULL, f.act) AS z_sd,
         public.ottoq_inbound_arrival_z(jsonb_build_object('eta', f.hz + f.trip, 'trip', f.trip,
                                        'esd', sqrt(f.dsd ^ 2 + (rc.asd / GREATEST(f.hz, 0.25)) ^ 2)), rc.j, f.act) AS z_new
    FROM f CROSS JOIN rc
)
SELECT v.step, v.late, v.early, v.band, v.mae
  FROM (SELECT count(*) FILTER (WHERE z_old > 3) AS l0, count(*) FILTER (WHERE z_old < -3) AS e0,
               round(avg((abs(z_old) <= 1.2816)::int)::numeric, 4) AS b0,
               count(*) FILTER (WHERE z_rung > 3) AS l1, count(*) FILTER (WHERE z_rung < -3) AS e1,
               round(avg((abs(z_rung) <= 1.2816)::int) FILTER (WHERE z_rung IS NOT NULL)::numeric, 4) AS b1,
               count(*) FILTER (WHERE z_sd > 3) AS l2, count(*) FILTER (WHERE z_sd < -3) AS e2,
               round(avg((abs(z_sd) <= 1.2816)::int) FILTER (WHERE z_sd IS NOT NULL)::numeric, 4) AS b2,
               count(*) FILTER (WHERE z_new > 3) AS l3, count(*) FILTER (WHERE z_new < -3) AS e3,
               round(avg((abs(z_new) <= 1.2816)::int) FILTER (WHERE z_new IS NOT NULL)::numeric, 4) AS b3,
               round(avg(abs(act - fc))::numeric, 3) AS m0, round(avg(abs(act - trip - hz))::numeric, 3) AS m1
          FROM z) q
 CROSS JOIN LATERAL (VALUES ('1 0626''s forecast', q.l0, q.e0, q.b0, q.m0), ('2 + each car''s own rung', q.l1, q.e1, q.b1, q.m1),
                            ('3 + the drive''s own spread', q.l2, q.e2, q.b2, q.m1), ('4 + the other calls home', q.l3, q.e3, q.b3, q.m1))
       v(step, late, early, band, mae);

-- (1b) the rung's own effect by rung, and the rung alone on the fit's drain
WITH fit AS MATERIALIZED (
  SELECT public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid, r.started_at, interval '21 days') AS p
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'
), ar AS (
  SELECT s.sim_run_id AS run, s.sim_clock AS clock, (ib.value ->> 'id')::uuid AS vid,
         (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
         (ib.value ->> 'eta')::float8 AS fc, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip,
         (ib.value ->> 'esd')::float8 AS esd0, le.params AS mp
    FROM public.ottoq_charge_order_hindsight h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    JOIN public.ottoq_learned_estimates le ON le.estimate_id = (s.state #>> '{models,return}')::bigint
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
   WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND ib.value ->> 'src' = 'forecast'
     AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
     AND COALESCE((ib.value ->> 'esd')::float8, 0) > 0
), b AS MATERIALIZED (
  SELECT ar.*, rd.soc0, public.ottoq_recall_threshold_soc(ar.vid, ar.run, ar.clock)::float8 AS thr,
         (ar.mp ->> 'drain_pct_per_min')::float8 AS dr, (SELECT (fit.p ->> 'drain_pct_per_min')::float8 FROM fit) AS dr_fit
    FROM ar
    CROSS JOIN LATERAL (SELECT r.soc_override::float8 AS soc0 FROM public.ottoq_recall_decisions r
                         WHERE r.sim_run_id = ar.run AND r.vehicle_id = ar.vid AND r.decided_at_sim <= ar.clock
                           AND r.inputs ? 'reserve'
                         ORDER BY r.decided_at_sim DESC LIMIT 1) rd
   WHERE ar.act > ar.trip AND ar.fc > ar.trip
), f AS (
  SELECT b.*, GREATEST((b.soc0 - b.thr) / b.dr, 0) AS hz FROM b WHERE b.dr > 0 AND b.thr IS NOT NULL
)
SELECT 'rung ' || thr AS what, count(*) AS arrivals, round(avg(act - fc)::numeric, 2) AS mean_error_0626,
       round(avg(act - trip - hz)::numeric, 2) AS mean_error_0627, round(avg(abs(act - fc))::numeric, 2) AS mae_0626,
       round(avg(abs(act - trip - hz))::numeric, 2) AS mae_0627, NULL::numeric AS band
  FROM f GROUP BY thr
UNION ALL
SELECT 'the rung alone on the fit''s drain (' || round(max(dr_fit)::numeric, 4) || ')', count(*), NULL, NULL, NULL,
       round(avg(abs(act - trip - GREATEST((soc0 - thr) / dr_fit, 0)))::numeric, 3),
       round(avg((abs(public.ottoq_inbound_arrival_z(jsonb_build_object('eta', GREATEST((soc0 - thr) / dr_fit, 0) + trip, 'trip', trip,
                                                                         'esd', esd0), NULL, act)) <= 1.2816)::int)::numeric, 4)
  FROM f
ORDER BY 1;

-- (2) the forecast's tenths, its band's edges, and the tails and triggers in arrivals and in returns (0627 as built)
WITH fit AS MATERIALIZED (
  SELECT public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid, r.started_at, interval '21 days') AS p
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'
), rc AS MATERIALIZED (
  SELECT jsonb_build_object('lam', round(COALESCE((p ->> 'other_per_work_hour')::numeric, 0) / 60.0, 6),
                            'trip_o', COALESCE((p ->> 'trip_other_min')::numeric, (p ->> 'trip_min')::numeric, 0)) AS j,
         COALESCE((p ->> 'trip_sd_min')::float8, 0) AS asd
    FROM fit
), ar AS (
  SELECT h.order_id, s.sim_run_id AS run, s.sim_clock AS clock, ib.value AS e, (ib.value ->> 'id')::uuid AS vid,
         (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
         (ib.value ->> 'eta')::float8 AS fc, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip, le.params AS mp
    FROM public.ottoq_charge_order_hindsight h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    JOIN public.ottoq_learned_estimates le ON le.estimate_id = (s.state #>> '{models,return}')::bigint
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
   WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND ib.value ->> 'src' = 'forecast'
     AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
     AND COALESCE((ib.value ->> 'esd')::float8, 0) > 0
), b AS (
  SELECT ar.*, rd.soc0, public.ottoq_recall_threshold_soc(ar.vid, ar.run, ar.clock)::float8 AS thr,
         (ar.mp ->> 'drain_pct_per_min')::float8 AS dr, COALESCE((ar.mp ->> 'drain_log_sd')::float8, 0) AS dsd
    FROM ar
    CROSS JOIN LATERAL (SELECT r.soc_override::float8 AS soc0 FROM public.ottoq_recall_decisions r
                         WHERE r.sim_run_id = ar.run AND r.vehicle_id = ar.vid AND r.decided_at_sim <= ar.clock
                           AND r.inputs ? 'reserve'
                         ORDER BY r.decided_at_sim DESC LIMIT 1) rd
   WHERE ar.act > ar.trip AND ar.fc > ar.trip
), f AS (
  -- a return is the car and the minute it came home; its trigger is the one on the dispatch it was on at the order
  SELECT b.*, GREATEST((b.soc0 - b.thr) / b.dr, 0) AS hz,
         b.vid::text || '@' || to_char(date_trunc('minute', b.clock + make_interval(secs => b.act * 60) + interval '30 seconds'),
                                       'HH24:MI') AS ret,
         (SELECT d.return_trigger FROM public.ottoq_vehicle_dispatches d
           WHERE d.sim_run_id = b.run AND d.vehicle_id = b.vid AND d.dispatched_at <= b.clock
           ORDER BY d.dispatched_at DESC LIMIT 1) AS trig
    FROM b WHERE b.dr > 0 AND b.thr IS NOT NULL
), z AS MATERIALIZED (
  SELECT f.*,
         public.ottoq_inbound_arrival_z(f.e, NULL, f.act) AS z_old,
         public.ottoq_inbound_arrival_z(jsonb_build_object('eta', f.hz + f.trip, 'trip', f.trip,
                                        'esd', sqrt(f.dsd ^ 2 + (rc.asd / GREATEST(f.hz, 0.25)) ^ 2)), rc.j, f.act) AS z_new
    FROM f CROSS JOIN rc
)
SELECT 'tenths: 0626 | 0627' AS what, NULL AS tail, NULL AS trig,
       (SELECT string_agg(c::text, ' ' ORDER BY k) FROM (SELECT LEAST(floor(public.ottoq_normal_cdf(z_old) * 10), 9)::int AS k, count(*) AS c FROM z GROUP BY 1) q)
       || ' | ' ||
       (SELECT string_agg(c::text, ' ' ORDER BY k) FROM (SELECT LEAST(floor(public.ottoq_normal_cdf(z_new) * 10), 9)::int AS k, count(*) AS c FROM z GROUP BY 1) q)
       AS arrivals,
       'below the band ' || round(avg((z_new < -1.2816)::int)::numeric, 4) || ', above ' || round(avg((z_new > 1.2816)::int)::numeric, 4) AS returns,
       NULL AS mean_error_min, NULL AS mean_min_to_rung_or_band
  FROM z
UNION ALL
SELECT 'tail', CASE WHEN z_new > 3 THEN 'late' ELSE 'early' END, COALESCE(trig, '(none)'), count(*)::text, count(DISTINCT ret)::text,
       round(avg(act - trip - hz)::numeric, 1)::text, round(avg(hz)::numeric, 1)::text
  FROM z WHERE abs(z_new) > 3 GROUP BY 2, 3
UNION ALL
SELECT 'tail before 0627', CASE WHEN z_old > 3 THEN 'late' ELSE 'early' END, NULL, count(*)::text, count(DISTINCT ret)::text, NULL, NULL
  FROM z WHERE abs(z_old) > 3 GROUP BY 2
UNION ALL
SELECT 'trigger', NULL, COALESCE(trig, '(none)'), count(*)::text, count(DISTINCT ret)::text,
       round(avg(act - trip - hz)::numeric, 2)::text, round(avg((abs(z_new) <= 1.2816)::int)::numeric, 3)::text
  FROM z GROUP BY 3
UNION ALL
SELECT 'all', NULL, NULL, count(*)::text, count(DISTINCT ret)::text, count(DISTINCT vid)::text || ' cars', NULL FROM z
UNION ALL
-- the other calls home the forecast expected (before each car's reserve arrival) against those that came
SELECT 'other calls home', NULL, NULL,
       round(sum(1 - exp(-(rc.j ->> 'lam')::float8 * GREATEST(z.hz + z.trip - (rc.j ->> 'trip_o')::float8, 0)))::numeric, 1)::text || ' expected',
       count(*) FILTER (WHERE z.trig IS DISTINCT FROM 'low_soc_reserve')::text || ' came',
       count(DISTINCT z.ret) FILTER (WHERE z.trig IS DISTINCT FROM 'low_soc_reserve')::text || ' returns', NULL
  FROM z CROSS JOIN rc
ORDER BY 1, 2, 3;

-- (3) each return once, by make: reserve returns more than 5 minutes from their rung at the order
WITH ar AS (
  SELECT s.sim_run_id AS run, s.sim_clock AS clock, (ib.value ->> 'id')::uuid AS vid,
         (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
         (ib.value ->> 'eta')::float8 AS fc, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip, le.params AS mp
    FROM public.ottoq_charge_order_hindsight h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    JOIN public.ottoq_learned_estimates le ON le.estimate_id = (s.state #>> '{models,return}')::bigint
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
   WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND ib.value ->> 'src' = 'forecast'
     AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
     AND COALESCE((ib.value ->> 'esd')::float8, 0) > 0
), b AS (
  SELECT ar.*, rd.soc0, public.ottoq_recall_threshold_soc(ar.vid, ar.run, ar.clock)::float8 AS thr,
         (ar.mp ->> 'drain_pct_per_min')::float8 AS dr
    FROM ar
    CROSS JOIN LATERAL (SELECT r.soc_override::float8 AS soc0 FROM public.ottoq_recall_decisions r
                         WHERE r.sim_run_id = ar.run AND r.vehicle_id = ar.vid AND r.decided_at_sim <= ar.clock
                           AND r.inputs ? 'reserve'
                         ORDER BY r.decided_at_sim DESC LIMIT 1) rd
   WHERE ar.act > ar.trip AND ar.fc > ar.trip
), z AS MATERIALIZED (
  SELECT f.*, v.vehicle_class_code AS cls, v.battery_capacity_kwh AS kwh,
         (SELECT d.return_trigger FROM public.ottoq_vehicle_dispatches d
           WHERE d.sim_run_id = f.run AND d.vehicle_id = f.vid AND d.dispatched_at <= f.clock
           ORDER BY d.dispatched_at DESC LIMIT 1) AS trig,
         f.vid::text || '@' || to_char(date_trunc('minute', f.clock + make_interval(secs => f.act * 60) + interval '30 seconds'), 'HH24:MI') AS ret
    FROM (SELECT b.*, GREATEST((b.soc0 - b.thr) / b.dr, 0) AS hz FROM b WHERE b.dr > 0 AND b.thr IS NOT NULL) f
    JOIN public.vehicles v ON v.id = f.vid
), per_return AS (
  -- each return once: its arrivals' mean error, and the drain it showed from the order to its turn home
  SELECT cls, ret, avg(kwh) AS kwh, avg(act - trip - hz) AS err,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY (soc0 - thr) / NULLIF(act - trip, 0)) AS drain_seen
    FROM z WHERE trig = 'low_soc_reserve' AND hz > 5 GROUP BY cls, ret
)
SELECT cls, count(*) AS returns, round(avg(kwh)::numeric, 1) AS battery_kwh,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY drain_seen)::numeric, 4) AS drain_seen_pct_a_min,
       round(avg(err)::numeric, 2) AS mean_error_min, round(avg(abs(err))::numeric, 2) AS mean_abs_error_min,
       count(*) FILTER (WHERE err > 0) AS home_after_the_forecast
  FROM per_return GROUP BY cls ORDER BY cls;

-- (4) the drain per make, out of sample: the reserve returns of the 21 days before the run (fine ticks, the run's own
--     taken out), and d9d49732's arrivals forecast at their make's drain against the depot's one
WITH g AS (SELECT started_at FROM public.ottoq_sim_runs WHERE sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'),
a AS (
  SELECT v.vehicle_class_code AS cls, d.soc_at_dispatch_pct AS soc0,
         CASE WHEN (d.return_evidence ->> 'soc_at_decision') ~ '^[0-9]+(\.[0-9]+)?$' THEN (d.return_evidence ->> 'soc_at_decision')::numeric END AS soc_dec,
         extract(epoch FROM (d.returning_started_at - d.dispatched_at)) / 60.0 AS work_min
    FROM public.ottoq_vehicle_dispatches d
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
    JOIN public.vehicles v ON v.id = d.vehicle_id, g
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND d.created_at > g.started_at - interval '21 days'
     AND d.created_at <= g.started_at AND d.sim_run_id <> 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'
     AND d.actual_return_at IS NOT NULL AND d.returning_started_at IS NOT NULL AND d.return_trigger = 'low_soc_reserve'
     AND COALESCE(r.tick_count > 0 AND r.sim_clock_current IS NOT NULL AND r.sim_clock_start IS NOT NULL
                  AND extract(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0 / r.tick_count <= 1, false)
), dr AS MATERIALIZED (
  SELECT cls, ln(((soc0 - soc_dec) / work_min)::float8) AS ld FROM a WHERE soc_dec IS NOT NULL AND work_min >= 5 AND soc0 > soc_dec
), dm AS MATERIALIZED (
  SELECT cls, count(*) AS n, percentile_cont(0.5) WITHIN GROUP (ORDER BY ld) AS m FROM dr GROUP BY cls
), ds AS (
  SELECT dr.cls, 1.4826 * percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(dr.ld - dm.m)) AS lsd FROM dr JOIN dm USING (cls) GROUP BY dr.cls
), pooled AS (
  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY ld) AS m FROM dr
), ar AS (
  SELECT s.sim_run_id AS run, s.sim_clock AS clock, (ib.value ->> 'id')::uuid AS vid,
         (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
         (ib.value ->> 'eta')::float8 AS fc, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip, le.params AS mp
    FROM public.ottoq_charge_order_hindsight h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    JOIN public.ottoq_learned_estimates le ON le.estimate_id = (s.state #>> '{models,return}')::bigint
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
   WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND ib.value ->> 'src' = 'forecast'
     AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
     AND COALESCE((ib.value ->> 'esd')::float8, 0) > 0
), b AS MATERIALIZED (
  SELECT ar.*, rd.soc0, public.ottoq_recall_threshold_soc(ar.vid, ar.run, ar.clock)::float8 AS thr,
         (ar.mp ->> 'drain_pct_per_min')::float8 AS drn, v.vehicle_class_code AS cls
    FROM ar JOIN public.vehicles v ON v.id = ar.vid
    CROSS JOIN LATERAL (SELECT r.soc_override::float8 AS soc0 FROM public.ottoq_recall_decisions r
                         WHERE r.sim_run_id = ar.run AND r.vehicle_id = ar.vid AND r.decided_at_sim <= ar.clock
                           AND r.inputs ? 'reserve'
                         ORDER BY r.decided_at_sim DESC LIMIT 1) rd
   WHERE ar.act > ar.trip AND ar.fc > ar.trip
), e AS (
  SELECT b.*, GREATEST((b.soc0 - b.thr) / b.drn, 0) AS hz_one, GREATEST((b.soc0 - b.thr) / exp(dm.m), 0) AS hz_make
    FROM b JOIN dm USING (cls) WHERE b.thr IS NOT NULL
)
SELECT (SELECT round(exp(m)::numeric, 4) FROM pooled) AS pooled_drain,
       (SELECT jsonb_agg(jsonb_build_object('make', dm.cls, 'returns', dm.n, 'drain', round(exp(dm.m)::numeric, 4),
                                            'log_spread', round(ds.lsd::numeric, 4)) ORDER BY dm.cls) FROM dm JOIN ds USING (cls)) AS by_make,
       count(*) AS arrivals,
       round(avg(abs(act - trip - hz_one))::numeric, 3) AS mae_one_drain, round(avg(abs(act - trip - hz_make))::numeric, 3) AS mae_make_drain,
       (SELECT jsonb_object_agg(cls, jsonb_build_object('mae_one', m1, 'mae_make', m2, 'err_one', e1, 'err_make', e2)) FROM (
          SELECT cls, round(avg(abs(act - trip - hz_one))::numeric, 2) AS m1, round(avg(abs(act - trip - hz_make))::numeric, 2) AS m2,
                 round(avg(act - trip - hz_one)::numeric, 2) AS e1, round(avg(act - trip - hz_make)::numeric, 2) AS e2
            FROM e GROUP BY cls) q) AS by_make_error
  FROM e;

-- (5) the other calls home: the fit's population, the same without the run's own returns, and the run
WITH g AS (SELECT started_at FROM public.ottoq_sim_runs WHERE sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'),
x AS MATERIALIZED (
  SELECT d.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AS gate, d.created_at <= g.started_at AS before_start,
         d.return_trigger AS trig, extract(epoch FROM (d.returning_started_at - d.dispatched_at)) / 60.0 AS work_min,
         COALESCE(r.tick_count > 0 AND r.sim_clock_current IS NOT NULL AND r.sim_clock_start IS NOT NULL
                  AND extract(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0 / r.tick_count <= 1, false) AS fine
    FROM public.ottoq_vehicle_dispatches d JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id, g
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND d.created_at > g.started_at - interval '21 days'
     AND d.actual_return_at IS NOT NULL AND d.returning_started_at IS NOT NULL
     AND COALESCE(d.return_trigger, '') NOT IN ('prime_inbound', 'run_stopped')
), p AS (
  SELECT '1 the fit through the run''s start, as fitted' AS population, x.* FROM x WHERE x.before_start AND x.fine
  UNION ALL SELECT '2 the same, without the run''s own returns', x.* FROM x WHERE x.before_start AND x.fine AND NOT x.gate
  UNION ALL SELECT '3 run d9d49732', x.* FROM x WHERE x.gate
)
SELECT population, count(*) FILTER (WHERE trig IS DISTINCT FROM 'low_soc_reserve') AS other_calls,
       round((sum(GREATEST(work_min, 0)) / 60.0)::numeric, 1) AS hours_at_work,
       round((count(*) FILTER (WHERE trig IS DISTINCT FROM 'low_soc_reserve') / NULLIF(sum(GREATEST(work_min, 0)) / 60.0, 0))::numeric, 4) AS per_hour,
       count(*) FILTER (WHERE trig = 'service_interval_due') AS service_interval, count(*) FILTER (WHERE trig = 'comms_stale') AS stale_telemetry,
       count(*) FILTER (WHERE trig = 'rider_flag_cleaning') AS rider_flag,
       count(*) FILTER (WHERE trig NOT IN ('low_soc_reserve', 'service_interval_due', 'comms_stale', 'rider_flag_cleaning')) AS the_rest
  FROM p GROUP BY 1 ORDER BY 1;

-- (5b) where in a car's time out the other calls come, on the fit's population (as fitted)
WITH g AS (SELECT started_at FROM public.ottoq_sim_runs WHERE sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'),
d AS MATERIALIZED (
  SELECT d.return_trigger AS trig, extract(epoch FROM (d.returning_started_at - d.dispatched_at)) / 60.0 AS work_min
    FROM public.ottoq_vehicle_dispatches d JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id, g
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND d.created_at > g.started_at - interval '21 days'
     AND d.created_at <= g.started_at AND d.actual_return_at IS NOT NULL AND d.returning_started_at IS NOT NULL
     AND COALESCE(d.return_trigger, '') NOT IN ('prime_inbound', 'run_stopped')
     AND COALESCE(r.tick_count > 0 AND r.sim_clock_current IS NOT NULL AND r.sim_clock_start IS NOT NULL
                  AND extract(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0 / r.tick_count <= 1, false)
)
SELECT p.span, p.calls, round(p.hours::numeric, 1) AS hours_at_work, round((p.calls / NULLIF(p.hours, 0))::numeric, 3) AS per_hour
  FROM (SELECT '1 first 10 minutes out' AS span,
               count(*) FILTER (WHERE trig IS DISTINCT FROM 'low_soc_reserve' AND work_min <= 10) AS calls,
               sum(LEAST(GREATEST(work_min, 0), 10)) / 60.0 AS hours FROM d
        UNION ALL
        SELECT '2 10 to 30 minutes', count(*) FILTER (WHERE trig IS DISTINCT FROM 'low_soc_reserve' AND work_min > 10 AND work_min <= 30),
               sum(GREATEST(LEAST(work_min, 30) - 10, 0)) / 60.0 FROM d
        UNION ALL
        SELECT '3 after 30 minutes', count(*) FILTER (WHERE trig IS DISTINCT FROM 'low_soc_reserve' AND work_min > 30),
               sum(GREATEST(work_min - 30, 0)) / 60.0 FROM d) p
 ORDER BY 1;

-- (6a) the run's own dispatches in the fit through its start
SELECT count(*) AS dispatches, count(*) FILTER (WHERE d.created_at <= r.started_at) AS created_at_its_start,
       count(*) FILTER (WHERE d.created_at <= r.started_at AND d.actual_return_at IS NOT NULL AND d.returning_started_at IS NOT NULL
                          AND COALESCE(d.return_trigger, '') NOT IN ('prime_inbound', 'run_stopped')) AS in_the_fits_evidence
  FROM public.ottoq_vehicle_dispatches d JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
 WHERE d.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92';

-- (6b) the fit's figures through the run's start, as fitted and without the run's own returns
WITH g AS MATERIALIZED (SELECT started_at FROM public.ottoq_sim_runs WHERE sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92'),
a AS MATERIALIZED (
  SELECT d.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AS gate, d.return_trigger, d.soc_at_dispatch_pct AS soc0,
         CASE WHEN (d.return_evidence ->> 'soc_at_decision') ~ '^[0-9]+(\.[0-9]+)?$' THEN (d.return_evidence ->> 'soc_at_decision')::numeric END AS soc_dec,
         extract(epoch FROM (d.returning_started_at - d.dispatched_at)) / 60.0 AS work_min,
         extract(epoch FROM (d.actual_return_at - d.returning_started_at)) / 60.0 AS trip_min,
         COALESCE(r.tick_count > 0 AND r.sim_clock_current IS NOT NULL AND r.sim_clock_start IS NOT NULL
                  AND extract(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0 / r.tick_count <= 1, false) AS fine
    FROM public.ottoq_vehicle_dispatches d JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id, g
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND d.created_at > g.started_at - interval '21 days'
     AND d.created_at <= g.started_at AND d.actual_return_at IS NOT NULL AND d.returning_started_at IS NOT NULL
     AND COALESCE(d.return_trigger, '') NOT IN ('prime_inbound', 'run_stopped')
), v AS (SELECT 'as fitted' AS variant, a.* FROM a UNION ALL SELECT 'without d9d49732', a.* FROM a WHERE NOT a.gate),
d AS (SELECT * FROM v WHERE fine),
low AS (SELECT * FROM d WHERE return_trigger = 'low_soc_reserve' AND soc_dec IS NOT NULL),
tm AS (SELECT variant, percentile_cont(0.5) WITHIN GROUP (ORDER BY trip_min) AS m FROM low WHERE trip_min >= 0 GROUP BY variant),
dr AS (SELECT variant, ln(((soc0 - soc_dec) / work_min)::float8) AS ld FROM low WHERE work_min >= 5 AND soc0 > soc_dec),
dm AS (SELECT variant, percentile_cont(0.5) WITHIN GROUP (ORDER BY ld) AS m FROM dr GROUP BY variant)
SELECT tm.variant,
       (SELECT count(*) FROM d WHERE d.variant = tm.variant) AS n_returns,
       (SELECT count(*) FROM d WHERE d.variant = tm.variant AND d.gate) AS of_them_the_runs_own,
       round(exp(dm.m)::numeric, 4) AS drain,
       round((SELECT 1.4826 * percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(dr.ld - dm.m)) FROM dr WHERE dr.variant = tm.variant)::numeric, 4) AS drain_log_sd,
       round(tm.m::numeric, 2) AS trip_min,
       round((SELECT 1.4826 * percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(l.trip_min - tm.m)) FROM low l WHERE l.variant = tm.variant AND l.trip_min >= 0)::numeric, 3) AS trip_sd_min,
       round((SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY trip_min) FROM d WHERE d.variant = tm.variant AND d.return_trigger IS DISTINCT FROM 'low_soc_reserve' AND trip_min >= 0)::numeric, 2) AS trip_other_min,
       round((SELECT count(*) FILTER (WHERE return_trigger IS DISTINCT FROM 'low_soc_reserve') / NULLIF(sum(GREATEST(work_min, 0)) / 60.0, 0) FROM d WHERE d.variant = tm.variant)::numeric, 4) AS other_per_work_hour
  FROM tm JOIN dm USING (variant) ORDER BY 1;

-- (6c) the gate with the fit's three figures taken without them (drive spread 0.182, after another call 1.63, 0.1134 an hour)
WITH rc AS (SELECT jsonb_build_object('lam', round(0.1134 / 60.0, 6), 'trip_o', 1.63) AS j, 0.182::float8 AS asd),
ar AS (
  SELECT s.sim_run_id AS run, s.sim_clock AS clock, (ib.value ->> 'id')::uuid AS vid,
         (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
         (ib.value ->> 'eta')::float8 AS fc, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip, le.params AS mp
    FROM public.ottoq_charge_order_hindsight h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    JOIN public.ottoq_learned_estimates le ON le.estimate_id = (s.state #>> '{models,return}')::bigint
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
   WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND ib.value ->> 'src' = 'forecast'
     AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
     AND COALESCE((ib.value ->> 'esd')::float8, 0) > 0
), b AS (
  SELECT ar.*, rd.soc0, public.ottoq_recall_threshold_soc(ar.vid, ar.run, ar.clock)::float8 AS thr,
         (ar.mp ->> 'drain_pct_per_min')::float8 AS dr, COALESCE((ar.mp ->> 'drain_log_sd')::float8, 0) AS dsd
    FROM ar
    CROSS JOIN LATERAL (SELECT r.soc_override::float8 AS soc0 FROM public.ottoq_recall_decisions r
                         WHERE r.sim_run_id = ar.run AND r.vehicle_id = ar.vid AND r.decided_at_sim <= ar.clock
                           AND r.inputs ? 'reserve'
                         ORDER BY r.decided_at_sim DESC LIMIT 1) rd
   WHERE ar.act > ar.trip AND ar.fc > ar.trip
), z AS (
  SELECT f.*, public.ottoq_inbound_arrival_z(jsonb_build_object('eta', f.hz + f.trip, 'trip', f.trip,
                                        'esd', sqrt(f.dsd ^ 2 + (rc.asd / GREATEST(f.hz, 0.25)) ^ 2)), rc.j, f.act) AS z_new
    FROM (SELECT b.*, GREATEST((b.soc0 - b.thr) / b.dr, 0) AS hz FROM b WHERE b.dr > 0 AND b.thr IS NOT NULL) f CROSS JOIN rc
)
SELECT count(*) AS n, count(*) FILTER (WHERE z_new > 3) AS late, count(*) FILTER (WHERE z_new < -3) AS early,
       round(avg((abs(z_new) <= 1.2816)::int)::numeric, 4) AS band, round(avg(abs(act - trip - hz))::numeric, 3) AS mae
  FROM z;

-- (7) the review as it reads now (read-only: STABLE, no trial)
WITH a AS (SELECT public.ottoq_arbiter_self_assessment_v3('11111111-1111-1111-1111-111111111111'::uuid, now() - interval '7 days', false) AS j)
SELECT (x.value ->> 'rank')::int AS rank, x.value ->> 'status' AS status, x.value ->> 'thin' AS thin, x.value ->> 'impact' AS impact,
       x.value ->> 'part' AS part, x.value ->> 'title' AS title, x.value ->> 'action' AS action
  FROM a, jsonb_array_elements(a.j -> 'improvement_areas') x ORDER BY 1;

-- (8) the rung against the recall decision's own record: the latest 50 decisions of each twin run of the 21 days
SELECT count(*) AS decisions,
       count(*) FILTER (WHERE public.ottoq_recall_threshold_soc(d.vehicle_id, d.sim_run_id, d.decided_at_sim)
                        IS DISTINCT FROM (d.inputs ->> 'reserve')::numeric + (d.inputs ->> 'reserve_margin')::numeric) AS differ,
       count(DISTINCT d.sim_run_id) AS runs,
       string_agg(DISTINCT ((d.inputs ->> 'reserve')::numeric + (d.inputs ->> 'reserve_margin')::numeric)::text, ', ') AS rungs
  FROM public.ottoq_sim_runs x
 CROSS JOIN LATERAL (SELECT rd.vehicle_id, rd.sim_run_id, rd.decided_at_sim, rd.inputs FROM public.ottoq_recall_decisions rd
                      WHERE rd.sim_run_id = x.sim_run_id AND rd.inputs ? 'reserve' AND rd.inputs ? 'reserve_margin'
                      ORDER BY rd.decided_at_sim DESC LIMIT 50) d
 WHERE x.depot_id = '11111111-1111-1111-1111-111111111111' AND x.started_at >= now() - interval '21 days';
