-- 0422  **The futures drain each car at its own rate, read on live after 0628 (G365 and G367 fixed; G368 and G369).**
--        0628 is applied (20261009021006, 9:10 PM CT). Read back on live its gate is exact: on d9d49732's 2,503
--        forecast arrivals, which are 89 returns graded by 61 orders, out of sample, the mean absolute error 2.633 ->
--        1.577 minutes, the pinball loss over the reserve's nine deciles 1.0685 -> 0.6752, and 85.1% -> 88.4% inside
--        the 80% band. Zoox cars, every one late under the depot's one drain, now miss by a mean -1.25 minutes (was
--        +3.03). One run: single readings, not ranges. What the class drain does not fix it names. The late tail past 3
--        spreads grows, 11 -> 49 arrivals (4 -> 6 returns), because a sharper forecast puts a long drive home further
--        out, and those six returns are the drive home, not the battery (G368). And the self-review's list of areas
--        moved by one between the rehearsal and the apply with no change to its code: its 7-day window moved past part of
--        one run, and the area it ranked first went with it (G369).
--
--       Written 2026-10-08, 9:25 PM CT. Read-only. Twin depot 11111111-…; run d9d49732 (started 2026-10-08 13:53:16
--       UTC, 8:53 AM CT) and its 61 graded orders; the return fit through the run's start, as 0628's V1 and V2 compute
--       it; return_v1 estimate 10, written by 0628's V3 at 02:10:06 UTC.
--
-- ══ §1 THE GATE ON LIVE (reproduce: (1)) ══
--
--   Each car at work at an order that came home inside the order's window, forecast from the same battery (the recall
--   decision's own record at the order), its own reserve rung and the other calls home (0627), at the depot's one drain
--   (0627) and at its model's drain within its class (0628), each with that level's spread:
--
--                                              0627 (one drain)   0628 (each car's own)
--     mean absolute error, minutes                  2.633               1.577
--     pinball loss, nine deciles                    1.0685              0.6752
--     inside the 80% band                           85.1%               88.4%
--       below it / above it                         2.4% / 12.5%        3.2% / 8.4%
--     more than 5 minutes late / early (arrivals)   282 / 88            61 / 61
--     past 3 spreads late / early (arrivals)        11 / 2              49 / 2
--       late, in returns                            4                   6
--     mean minutes off, Tesla (878 arrivals)        -1.94               -0.25
--     mean minutes off, Waymo (1,006)               +0.28               +0.46
--     mean minutes off, Zoox (619)                  +3.03               -1.25
--
--   Every one of the 2,503 arrivals was drained at its model's level: the fit through the run's start has every model
--   of the twin's three classes over its floor of 10 returns. The figures are 0628 §1(g)'s rehearsal figures to the
--   last digit, so nothing in the database moved under the gate between the rehearsal and the apply.
--
-- ══ §2 THE FIT AT APPLY (reproduce: (2)) ══
--
--   return_v1 estimate 10 (usable; 1,615 returns over 20 runs, fine ticks; the depot's drain 0.716% a minute, log spread
--   0.092), the classes and models shrunk by n / (n + 20):
--
--     Tesla 0.7474 (479 returns, w 0.960, log spread 0.0482)   Model Y 0.7480 (430)   Cybercab 0.7513 (49)
--     Waymo 0.7191 (567, w 0.966, 0.0448)                      Waymo I-Pace 0.7202 (494)   Jaguar I-PACE AV 0.7203 (49)
--                                                              Zeekr RT AV 0.7074 (24)
--     Zoox 0.6476 (376, w 0.949, 0.0359)                       Zoox Robotaxi 0.6443 (333)   Zoox VH6 0.6476 (43)
--
--   The class spreads are 0.036-0.048 against the depot's 0.092: the pooled spread was mostly the gap between classes,
--   as G365 said. Within a class the models differ by at most 1.8% (the Zeekr against the I-Pace). The nightly refit
--   (`ottoq_fit_return_model`) writes these again each night from the depot's own returns; nothing here is a constant.
--
-- ══ §3 THE LATE TAIL IS THE DRIVE HOME (G368; reproduce: (1)) ══
--
--   The 49 arrivals past 3 spreads late are 6 returns of 6 cars. Split by their own dispatches, their drive home took a
--   mean 10.64 minutes longer than the forecast's, against 0.20 for every other arrival; the longest, a car called home
--   mid-shift on stale telemetry, drove 17.33 minutes longer than the forecast's 1.24. The futures give every car the
--   depot's typical drive home. The kernel knows each car's: `return_eta_minutes`, set when the car turns home
--   (distance over speed in the hour's traffic, `ottoq_computed_eta_minutes`) and refreshed for every car at work each
--   tick (`ottoq_refresh_return_eta`). The battery is not the cause: a car's drain so far does not predict the rest of
--   its shift (correlation 0.014, 0628 §1(f)). The self-review now says so in its own words when it sees it: a late
--   tail whose drive home carries half its minutes or more is titled "A few cars take far longer to drive home than its
--   futures sample", and its action is "forecast each car's drive home from where it is, not the depot's typical drive".
--   The graded orders here were made before 0627, so the review marks the arrivals built and says to grade the next
--   armed run's orders first; the drive home is what that grade will show, if it is still there.
--
-- ══ §4 THE REVIEW'S WINDOW MOVED AN AREA (G369; reproduce: (3)) ══
--
--   0628's V4 in the rehearsal (01:40 UTC, 8:40 PM CT) read 10 areas, 6 open, the air temperature ranked first. At the
--   apply and after it (02:13 UTC, 9:13 PM CT) the same code reads 9 areas, 5 open, and no air-temperature area. Read with
--   the rehearsal's window start (`p_since = 2026-10-02 01:40 UTC`) it reads 10 and 6 again, the air temperature first.
--   So the area came and went with the review's 7-day window, not with 0628. The only run at the window's edge between
--   the two readings is cde5a21c (2026-10-02 01:12-02:22 UTC, 201 charges; the runs before it on the 1st recorded none,
--   and no run is running now, so nothing entered the window's other end). Part of that one run held the air
--   temperature's slope over its bar. An area whose presence turns on part of one run is thin, and the review marks it
--   neither thin nor near its bar. The 7-day window is a reading of the calendar, not of the evidence: a fixed
--   number of the latest completed runs, or the bar's margin reported beside the area, would make the list stable. Not
--   built here: the review is a finding for a person (rule 10), and the next person to read it should know this.
--
-- ══ §5 WHAT IS LEFT ══
--
--   G368, the drive home: forecast each car's drive from where it is, as the kernel already does for a car turning home.
--   G366, the other calls home ran at half the fit's rate on d9d49732: one run, still to be confirmed on the next armed
--   run before anything is built. G369, the review's window. And the measurement every one of these waits on: an armed
--   run's orders graded under 0627 and 0628, which says whether the check's verdicts improve, not only its forecast.
--   None of this changes when a car goes out or comes back, or how full it charges (rule 9): the futures are the check's
--   forecast of the depot, and the recall decision and the tick path are untouched.

-- (1) the gate, as 0628's V2 computes it, out of sample on d9d49732
WITH k AS (
  SELECT x.j AS v_fit,
         jsonb_build_object('lam', round(COALESCE((x.j #>> '{params,other_per_work_hour}')::numeric, 0) / 60.0, 6),
                            'trip_o', COALESCE((x.j #>> '{params,trip_other_min}')::numeric, (x.j #>> '{params,trip_min}')::numeric, 0)) AS v_rc,
         COALESCE((x.j #>> '{params,trip_sd_min}')::float8, 0) AS v_asd
    FROM (SELECT jsonb_build_object('usable', true, 'params',
                   public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid, r.started_at, interval '21 days')) AS j
            FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92') x
), ar AS (
  SELECT h.order_id, s.sim_run_id AS run, s.sim_clock AS clock, (ib.value ->> 'id')::uuid AS vid,
         (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
         (ib.value ->> 'eta')::float8 AS fc, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip
    FROM public.ottoq_charge_order_hindsight h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
   WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND ib.value ->> 'src' = 'forecast'
     AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
     AND COALESCE((ib.value ->> 'esd')::float8, 0) > 0
), b AS (
  SELECT ar.*, rd.soc0, public.ottoq_recall_threshold_soc(ar.vid, ar.run, ar.clock)::float8 AS thr,
         public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who,
         ar.vid::text || '@' || to_char(date_trunc('minute', ar.clock + make_interval(secs => ar.act * 60) + interval '30 seconds'),
                                        'YYYY-MM-DD HH24:MI') AS ret,
         dd.drive
    FROM ar
    JOIN public.vehicles v ON v.id = ar.vid
    CROSS JOIN LATERAL (SELECT r.soc_override::float8 AS soc0 FROM public.ottoq_recall_decisions r
                         WHERE r.sim_run_id = ar.run AND r.vehicle_id = ar.vid AND r.decided_at_sim <= ar.clock
                           AND r.inputs ? 'reserve'
                         ORDER BY r.decided_at_sim DESC LIMIT 1) rd
    LEFT JOIN LATERAL (SELECT extract(epoch FROM (d.actual_return_at - d.returning_started_at))::float8 / 60.0 AS drive
                         FROM public.ottoq_vehicle_dispatches d
                        WHERE d.vehicle_id = ar.vid AND d.sim_run_id = ar.run AND d.dispatched_at <= ar.clock
                          AND d.actual_return_at > ar.clock AND d.returning_started_at IS NOT NULL
                        ORDER BY d.dispatched_at DESC LIMIT 1) dd ON true
   WHERE ar.act > ar.trip AND ar.fc > ar.trip
), f AS (
  SELECT b.*, (k.v_fit #>> '{params,drain_pct_per_min}')::float8 AS dr0,
         COALESCE((k.v_fit #>> '{params,drain_log_sd}')::float8, 0) AS ds0,
         (c.cd ->> 'dr')::float8 AS dr1, COALESCE((c.cd ->> 'dsd')::float8, 0) AS ds1, c.cd ->> 'lvl' AS lvl
    FROM b CROSS JOIN k CROSS JOIN LATERAL (SELECT public.ottoq_return_car_drain(k.v_fit, b.who) AS cd) c
   WHERE b.thr IS NOT NULL
), h2 AS (
  SELECT f.*, GREATEST((f.soc0 - f.thr) / f.dr0, 0) AS hz0, GREATEST((f.soc0 - f.thr) / f.dr1, 0) AS hz1 FROM f WHERE f.dr0 > 0 AND f.dr1 > 0
), g AS (
  SELECT h2.*, h2.act - h2.trip - h2.hz0 AS e0, h2.act - h2.trip - h2.hz1 AS e1,
         sqrt(h2.ds0 ^ 2 + (k.v_asd / GREATEST(h2.hz0, 0.25)) ^ 2) AS sd0, sqrt(h2.ds1 ^ 2 + (k.v_asd / GREATEST(h2.hz1, 0.25)) ^ 2) AS sd1,
         public.ottoq_inbound_arrival_z(jsonb_build_object('eta', h2.hz0 + h2.trip, 'trip', h2.trip,
                                          'esd', sqrt(h2.ds0 ^ 2 + (k.v_asd / GREATEST(h2.hz0, 0.25)) ^ 2)), k.v_rc, h2.act) AS z0,
         public.ottoq_inbound_arrival_z(jsonb_build_object('eta', h2.hz1 + h2.trip, 'trip', h2.trip,
                                          'esd', sqrt(h2.ds1 ^ 2 + (k.v_asd / GREATEST(h2.hz1, 0.25)) ^ 2)), k.v_rc, h2.act) AS z1
    FROM h2 CROSS JOIN k
)
SELECT count(*) AS n, count(DISTINCT ret) AS returns,
       count(DISTINCT ret) FILTER (WHERE z0 > 3) AS late_returns_0627, count(DISTINCT ret) FILTER (WHERE z1 > 3) AS late_returns_0628,
       round(avg(drive - trip) FILTER (WHERE z1 > 3)::numeric, 2) AS late_drive_over, round(avg(drive - trip) FILTER (WHERE abs(z1) <= 3)::numeric, 2) AS rest_drive_over,
       round(max(drive - trip) FILTER (WHERE z1 > 3)::numeric, 2) AS late_drive_over_max,
       round(avg(abs(e0))::numeric, 3) AS mae_0627, round(avg(abs(e1))::numeric, 3) AS mae_0628,
       round(avg((abs(z0) <= 1.2816)::int)::numeric, 3) AS band_0627, round(avg((abs(z1) <= 1.2816)::int)::numeric, 3) AS band_0628,
       round(avg((z0 < -1.2816)::int)::numeric, 3) AS below_0627, round(avg((z1 < -1.2816)::int)::numeric, 3) AS below_0628,
       round(avg((z0 > 1.2816)::int)::numeric, 3) AS above_0627, round(avg((z1 > 1.2816)::int)::numeric, 3) AS above_0628,
       count(*) FILTER (WHERE z0 > 3) AS late_0627, count(*) FILTER (WHERE z1 > 3) AS late_0628,
       count(*) FILTER (WHERE z0 < -3) AS early_0627, count(*) FILTER (WHERE z1 < -3) AS early_0628,
       count(*) FILTER (WHERE e0 > 5) AS over5_late_0627, count(*) FILTER (WHERE e1 > 5) AS over5_late_0628,
       count(*) FILTER (WHERE e0 < -5) AS over5_early_0627, count(*) FILTER (WHERE e1 < -5) AS over5_early_0628,
       (SELECT round(avg(CASE WHEN x.act >= x.q0 THEN x.u * (x.act - x.q0) ELSE (1 - x.u) * (x.q0 - x.act) END)::numeric, 4)
          FROM (SELECT q.act, u.u, q.trip + q.hz0 * exp(public.ottoq_normal_quantile(u.u) * q.sd0) AS q0 FROM g q
                 CROSS JOIN (VALUES (0.1), (0.2), (0.3), (0.4), (0.5), (0.6), (0.7), (0.8), (0.9)) u(u)) x) AS pinball_0627,
       (SELECT round(avg(CASE WHEN x.act >= x.q1 THEN x.u * (x.act - x.q1) ELSE (1 - x.u) * (x.q1 - x.act) END)::numeric, 4)
          FROM (SELECT q.act, u.u, q.trip + q.hz1 * exp(public.ottoq_normal_quantile(u.u) * q.sd1) AS q1 FROM g q
                 CROSS JOIN (VALUES (0.1), (0.2), (0.3), (0.4), (0.5), (0.6), (0.7), (0.8), (0.9)) u(u)) x) AS pinball_0628,
       (SELECT string_agg(format('%s %s %s -> %s', c.cls, c.n, c.m0, c.m1), ', ' ORDER BY c.cls)
          FROM (SELECT who ->> 'cls' AS cls, count(*) AS n, round(avg(e0)::numeric, 2) AS m0, round(avg(e1)::numeric, 2) AS m1 FROM g GROUP BY 1) c) AS by_class,
       (SELECT string_agg(format('%s %s', l.lvl, l.n), ', ' ORDER BY l.lvl) FROM (SELECT lvl, count(*) AS n FROM g GROUP BY lvl) l) AS drained_at
  FROM g;

-- (2) the fit at apply: return_v1's drains by class and by model
SELECT e.j -> 'estimate_id' AS estimate_id, e.j -> 'usable' AS usable, e.j -> 'fitted_at' AS fitted_at,
       e.j #> '{params,drain_pct_per_min}' AS drain, e.j #> '{params,drain_log_sd}' AS drain_log_sd,
       e.j #> '{params,n_returns}' AS n_returns, e.j #> '{params,population}' AS population,
       e.j #> '{params,drain_by}' AS drain_by
  FROM (SELECT public.ottoq_learned_estimate('11111111-1111-1111-1111-111111111111'::uuid, 'return_v1') AS j) e;

-- (3) the review now and with the rehearsal's window start: the area that came and went with the window
SELECT w.since, jsonb_array_length(r.v -> 'improvement_areas') AS areas, r.v ->> 'areas_open' AS open,
       (SELECT string_agg((a.value ->> 'rank') || ' ' || (a.value ->> 'area') || ' (' || (a.value ->> 'status') || ')', ', '
                          ORDER BY (a.value ->> 'rank')::int)
          FROM jsonb_array_elements(r.v -> 'improvement_areas') a) AS ranked
  FROM (VALUES (now() - interval '7 days'), (timestamptz '2026-10-02 01:40:00+00')) w(since)
 CROSS JOIN LATERAL (SELECT public.ottoq_arbiter_self_assessment_v3('11111111-1111-1111-1111-111111111111'::uuid, w.since, false) AS v) r;
