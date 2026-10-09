-- 0427  **Charges under way: measured, a better forecast rehearsed against the decisions, and not built.**
--        The check's self-review (12:55 UTC, 7:55 AM CT) ranked "charges already under way" first: they explained 26%
--        of what made its verdicts wrong, moved 15 of 43 decisions, and ended a mean 0.84 minutes later than it expected,
--        missing by 6.55 over 6,062 charges. This reads that area to the bottom: what the error is, which forecast fixes
--        it out of sample, and whether that forecast makes the check's decisions right more often. It does not, so
--        nothing was built; what it found instead is that the check cannot yet tell a better order from a worse one.
--
--        Written 2026-10-09, 8:25-9:00 AM CT. Read-only. Twin depot 11111111-…. Two runs on the current clock
--        (b2efcc07, 64251eb8): 20 decisions, 18 with a right answer. Single readings, not ranges.
--
-- ══ §1 A THIRD OF THE AREA IS A RETIRED CLOCK (reproduce: (1)) ══
--
--   The review's window holds three runs. Running-charge forecasts that ended inside their window, per run and kind
--   (minutes, real end minus forecast; the standing grades, ottoq_charge_order_grades):
--
--                       clock                    kind   charges   bias     mean miss   minutes missed
--     d9d49732          charge_time_v1 (0619)    dcfc      623   -14.68      18.23        11,354
--                                                l2      1,355    +2.58       4.81         6,513
--     b2efcc07          charge_time_v2 (fit 3)   dcfc      814    +6.06       6.57         5,347
--                                                l2      1,432    +3.04       5.41         7,748
--     64251eb8          charge_time_v2 (5, 6)    dcfc      721    +2.08       4.50         3,245
--                                                l2      1,117    -0.07       4.91         5,486
--
--   d9d49732's fast chargers, timed by a clock that 0622 replaced, carry 29% of every minute missed (45% with its L2).
--   The running part's share of verdict mass per run: 29.0% (10 of 23 decisions moved), 16.7% (1 of 9), 27.3% (4 of
--   11). So the rank survives the dead era; the size of the miss does not. "Charges" here are (order, charger) pairs:
--   one charge is read once per order that saw it running, so the counts overstate independent charges about 15x.
--
-- ══ §2 WHAT THE MISS IS, ON THE CURRENT CLOCK (reproduce: (2), (3)) ══
--
--   (a) A charge that has been running is slower than a fresh one from the same battery. The remaining part's time
--       against the clock's time for a charge starting at that battery (log ratio; completed charges, the meter's own
--       battery reading at the order; battery under 95%):
--
--         minutes charging      <10     10-20    20-30    30-60     60+
--         fast                 +0.131   +0.239   +0.301   +0.304   +0.391
--         L2                   +0.119   +0.201   +0.266   +0.321   +0.283
--
--       The twin's physics says why (ottoq_sim_compute_charge_rate, twin.ottoq_sim_advance_charge_sessions): the battery
--       warms 5 °C for each 10 minutes of charging, up to 15 °C at 30 minutes, and above 35 °C the rate falls 2% a
--       degree; and an L2 charger halves its rate above 95%. The clock corrects a charge under way by one number per
--       kind (its session level a: +0.093 fast, +0.109 L2), so fast charges still ran short of it at every stage
--       (+0.083 to +0.205 after the correction).
--   (b) The futures sample a charge's end far narrower than charges end. Against the spread the check's futures draw
--       from (0.140 fast, 0.169-0.171 L2):
--
--                          kind   z spread   inside the 80% band   ended later than the band
--         64251eb8         fast     2.13          59.5%                    32.0%
--                          L2       2.44          68.2%                    12.9%
--         b2efcc07         fast     2.28          36.1%                    58.3%
--                          L2       2.60          58.0%                    28.5%
--
--       The clock fits that spread on each completed charge cut at a quarter, a half and three quarters of its battery
--       range, so it rarely sees the slow last few percent; an order catches a charge at a random minute, and the last
--       few percent are where a charge spends its minutes.
--   (c) Not the cause: the car's battery reading is a whole number (vehicles.current_soc is an integer; the twin writes
--       ROUND(x, 1) into it). It is off a mean 0.11-0.17 points; timing from the meter's exact reading instead moves
--       the mean miss by +0.01 to +0.12 minutes.
--   (d) Not a cure: how the done part ran. The clock's fitted slope is 0.025 (fast) and 0 (L2, clamped); out of sample
--       the done part's pace correlates 0.20 and -0.23 with the rest. The charge's power now against the clock's
--       expectation explains 2.4% of the fast miss and 21% of the L2 miss below 95%.
--
-- ══ §3 FORECASTS TRIED, OUT OF SAMPLE (reproduce: (4)) ══
--
--   Fitted on the fine-tick completed charges recorded before b2efcc07 began (2026-10-09 02:50 UTC); scored on every
--   running charge at the graded orders of b2efcc07 and 64251eb8 (mean miss in minutes / bias):
--
--                                               fast 64251eb8   fast b2efcc07   L2 64251eb8    L2 b2efcc07
--     the check as it is                         4.50 / +2.08    6.57 / +6.06    4.91 / -0.07   5.41 / +3.04
--     a level per 10 minutes charging, spread    5.18 / -1.00    5.73 / +4.18    5.05 / +1.75   6.24 / +4.73
--       by remaining length (80% band held)      (80.9%)         (72.4%)         (70.6%)        (54.4%)
--     the run's own running misses, in the run   4.87 / +1.25    6.95 / +6.23    5.93 / +3.53   6.41 / +4.78
--     a learned power curve x the charge's own   3.76 / +1.96    4.10 / +2.69    5.69 / +0.37   5.96 / +0.27
--       recent power
--
--   The learned curve is each make's mean power by 5% of battery, cool (under 15 minutes charging) or hot, from the
--   chargers' own meter readings (Power.Active.Import against SoC): Tesla fast from 136 kW at 25% to 23 kW at 95%; the
--   I-PACE flat near 95 kW to 50% and 16 kW at 95%; Zoox near 95 kW to 80% and 52 kW at 95%; L2 14-17 kW, halving
--   above 95%; a hot battery 8-15% slower. The clock's base model assumes 85%, 55% and 30% of the lesser of charger
--   and car. Integrated from the battery now and scaled by the charge's last five power readings against the curve,
--   it cuts the fast miss 16% and 38% and its bias to +2 to +3 minutes. It does nothing for L2. The mean, not the
--   median, is the power to integrate: minutes in a band are energy over the time-averaged power.
--
-- ══ §4 THE DECISIONS, REHEARSED (reproduce: (5)) ══
--
--   Each graded decision of the two runs was replayed through the check's own futures (12, its seed) three ways: as
--   recorded; with every running fast charge's end replaced by the learned curve's; and that with the spread its
--   misses show (0.27). The replay reproduces every stored verdict (12/12, 8/12, 8/12 on the first three).
--
--                          orders   as recorded         the curve                    the curve and its spread
--     right refusals          9     9 refused           7 (469 taken 12/12,          8 (606 taken 10/12)
--                                                          606 taken 11/12)
--     wrong take (479)        1     taken 10/12         refused 6/12                 refused 7/12
--     missed wins             8     none taken          none taken                   none taken
--     neutral takes           2     taken               no difference in seats       no difference in seats
--     decisions right        18     9                   8                            9
--
--   A better forecast of when chargers free up does not make the check's decisions right more often. Not built: the
--   rule of G385 holds (rehearse a fix against the decisions it is meant to change before building it). The curve
--   is kept, with these numbers, for where a minute of ready time is the product: the agent's board (0641's plan per
--   car) and any future readiness promise.
--
-- ══ §5 WHY: THE CHECK CANNOT YET TELL A BETTER ORDER FROM A WORSE ONE (reproduce: (6)) ══
--
--   On the 18 decisions with a right answer:
--   - its expected future agreed with hindsight on 9 (5 of the 8 winners, 4 of the 10 losers);
--   - the share of futures an order won averaged 0.448 for the orders that won in hindsight and 0.558 for those that
--     lost: AUC 0.35 (28 of 80 pairs), Brier 0.343 against 0.247 for the base rate. On 18 decisions that interval
--     includes 0.5: no evidence it tells them apart, not proof it reads them backwards;
--   - the outcome followed the run: the agent's orders lost 7 of 8 on b2efcc07 and won 7 of 10 on 64251eb8;
--   - the stakes were real, not ties: hindsight decided all four orders read by minutes late over 15 due cars, the
--     missed win 608 by 255.5 minutes and the wrong take 479 by 196.9; and in those windows 0 to 2 of the 15 due cars
--     were ready on time in either order (G383).
--   The self-review ranks the five inputs by their exact Shapley share of the gap between forecast and hindsight. That
--   share is what PERFECT knowledge of an input would change. A forecast that is merely better does not approach it,
--   and a comparison that is at chance cannot be ranked into accuracy one input at a time.
--
-- ══ §6 WHAT FOLLOWS ══
--
--   (a) G388: charges under way, as measured here; the learned curve rehearsed and not built.
--   (b) G389: the check's comparison is at chance on the current clock. The next work is its discrimination, not its
--       inputs: which of the comparison's keys decides close orders, whether a refusal-by-default bar (0.80 of 12) is
--       the right shape for a comparison this noisy, and how many decisions a claim needs (18 is not enough to say more
--       than "not yet").
--   (c) G390: the self-review ranks over a window that can hold a retired model's orders. It should read each area by
--       the forecast model that made the orders (the snapshot carries it) and say when the latest model's share
--       disagrees with the window's.

-- (1) The running forecasts per run and kind, and the running part's verdict share per run
WITH o AS (
  SELECT g.order_id, g.sim_run_id, s.state, g.realized
    FROM public.ottoq_charge_order_grades g
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = g.order_id
   WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.realized IS NOT NULL
     AND g.graded_at >= '2026-10-02 12:55:00.140408+00'
), c AS (
  SELECT o.order_id, o.sim_run_id, ch ->> 'k' AS kind, (ch ->> 'free')::numeric AS f_free,
         (o.realized #>> ARRAY['chargers', ch ->> 'id', 'free'])::numeric AS r_free,
         COALESCE((o.realized #>> ARRAY['chargers', ch ->> 'id', 'cen'])::boolean, true) AS cen,
         o.state #>> '{models,charge_time_model}' AS clock_model, o.state #>> '{models,charge_time}' AS clock_est
    FROM o CROSS JOIN LATERAL jsonb_array_elements(o.state -> 'chargers') ch
   WHERE COALESCE((ch ->> 'free')::numeric, 0) > 0
)
SELECT left(sim_run_id::text, 8) AS run, string_agg(DISTINCT COALESCE(clock_model, 'v1') || '#' || clock_est, ' ') AS clocks, kind,
       count(*) FILTER (WHERE NOT cen) AS n, round(avg(r_free - f_free) FILTER (WHERE NOT cen), 2) AS bias,
       round(avg(abs(r_free - f_free)) FILTER (WHERE NOT cen), 2) AS mean_miss,
       round(sum(abs(r_free - f_free)) FILTER (WHERE NOT cen), 0) AS minutes_missed
  FROM c GROUP BY sim_run_id, kind ORDER BY 1, 3;

WITH a AS (
  SELECT a.order_id, a.sim_run_id, p.key AS part, (p.value ->> 'cmp')::numeric AS cmp
    FROM public.ottoq_charge_order_attributions a
    JOIN public.ottoq_charge_order_grades g ON g.order_id = a.order_id
    CROSS JOIN LATERAL jsonb_each(a.shapley) p
   WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.graded_at >= '2026-10-02 12:55:00.140408+00'
), r AS (
  SELECT left(sim_run_id::text, 8) AS run, part, count(DISTINCT order_id) AS orders, round(sum(abs(cmp)), 2) AS mass,
         count(*) FILTER (WHERE abs(cmp) >= 0.5) AS moved
    FROM a GROUP BY 1, 2
)
SELECT run, part, orders, mass, moved, round(mass / NULLIF(sum(mass) OVER (PARTITION BY run), 0), 3) AS share_in_run
  FROM r ORDER BY run, mass DESC;

-- (2) The remaining part against the clock for a fresh charge, by minutes charging (current clock, completed charges)
WITH m AS (SELECT jsonb_build_object('params', f.params) AS mdl FROM public.ottoq_charge_clock_fits f WHERE f.fit_id = 6),
o AS (
  SELECT g.order_id, g.sim_run_id, g.sim_clock, s.state, g.realized
    FROM public.ottoq_charge_order_grades g JOIN public.ottoq_charge_order_snapshots s ON s.order_id = g.order_id
   WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.realized IS NOT NULL
     AND g.sim_run_id IN ('b2efcc07-e47e-40e2-9411-907e913a3976', '64251eb8-e5fb-4f7d-af25-9f4ddf5d3768')
), c AS (
  SELECT o.order_id, o.sim_run_id, o.sim_clock, ch ->> 'k' AS kind, (ch ->> 'id')::uuid AS stall_id, (ch ->> 'car')::uuid AS car,
         (ch ->> 'free')::numeric AS f_free, (o.realized #>> ARRAY['chargers', ch ->> 'id', 'free'])::numeric AS r_free
    FROM o CROSS JOIN LATERAL jsonb_array_elements(o.state -> 'chargers') ch
   WHERE COALESCE((ch ->> 'free')::numeric, 0) > 0 AND ch ? 'car'
     AND NOT COALESCE((o.realized #>> ARRAY['chargers', ch ->> 'id', 'cen'])::boolean, true)
), j AS (
  SELECT c.*, l.session_id, l.started_at AS st, l.ended_at AS en, l.battery_kwh AS bat, l.charger_kw AS ckw, l.vehicle_kw AS vkw,
         mv.t_now, mv.soc_now
    FROM c JOIN LATERAL (
      SELECT * FROM public.ottoq_charge_duration_ledger l
       WHERE l.sim_run_id = c.sim_run_id AND l.stall_id = c.stall_id AND l.vehicle_id = c.car
         AND l.started_at <= c.sim_clock AND (l.ended_at IS NULL OR l.ended_at >= c.sim_clock)
       ORDER BY l.started_at DESC LIMIT 1) l ON true
    LEFT JOIN LATERAL (
      SELECT mm.sim_clock_at AS t_now, (mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric AS soc_now
        FROM public.ottoq_ocpp_messages mm
       WHERE mm.ocpp_session_id = l.session_id AND mm.message_type = 'MeterValues'
         AND (mm.payload -> 'sampledValue' -> 1 ->> 'measurand') = 'SoC' AND mm.sim_clock_at <= c.sim_clock
       ORDER BY mm.message_at DESC LIMIT 1) mv ON true
   WHERE l.stopped_reason = 'completed'
), z AS (
  SELECT j.kind, j.soc_now, j.f_free, j.r_free, extract(epoch FROM (j.t_now - j.st)) / 60.0 AS done_min,
         extract(epoch FROM (j.en - j.t_now)) / 60.0 AS rem_min,
         public.ottoq_charge_minutes_estimate(j.bat, j.soc_now, 100, j.ckw, j.vkw) AS b_rem,
         (public.ottoq_charge_clock((SELECT mdl FROM m), j.kind,
            public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model), j.bat, j.soc_now, 100, j.ckw, j.vkw, NULL) ->> 'f')::numeric AS f_rem
    FROM j JOIN public.vehicles v ON v.id = j.car
   WHERE j.soc_now IS NOT NULL AND j.soc_now < 95 AND j.t_now > j.st AND j.en > j.t_now
)
SELECT kind, CASE WHEN done_min < 10 THEN 'a <10' WHEN done_min < 20 THEN 'b 10-20' WHEN done_min < 30 THEN 'c 20-30'
                  WHEN done_min < 60 THEN 'd 30-60' ELSE 'e 60+' END AS minutes_charging,
       count(*) AS n, round(avg(ln(rem_min / b_rem) - f_rem), 3) AS against_fresh, round(avg(ln(r_free / f_free)), 3) AS against_check
  FROM z WHERE b_rem >= 1 AND rem_min > 0 AND r_free > 0.5 AND f_free > 0.5 GROUP BY 1, 2 ORDER BY 1, 2;

-- (3) Where the real ends fell against the spread the futures draw from
WITH o AS (
  SELECT g.order_id, g.sim_run_id, s.state, g.realized
    FROM public.ottoq_charge_order_grades g JOIN public.ottoq_charge_order_snapshots s ON s.order_id = g.order_id
   WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.realized IS NOT NULL
     AND g.sim_run_id IN ('b2efcc07-e47e-40e2-9411-907e913a3976', '64251eb8-e5fb-4f7d-af25-9f4ddf5d3768')
), c AS (
  SELECT o.sim_run_id, ch ->> 'k' AS kind, (ch ->> 'free')::numeric AS f_free, (ch ->> 'sd')::numeric AS sd,
         (o.realized #>> ARRAY['chargers', ch ->> 'id', 'free'])::numeric AS r_free,
         COALESCE((o.realized #>> ARRAY['chargers', ch ->> 'id', 'cen'])::boolean, true) AS cen
    FROM o CROSS JOIN LATERAL jsonb_array_elements(o.state -> 'chargers') ch
   WHERE COALESCE((ch ->> 'free')::numeric, 0) > 0
)
SELECT left(sim_run_id::text, 8) AS run, kind, count(*) FILTER (WHERE NOT cen) AS n, round(avg(sd) FILTER (WHERE NOT cen), 3) AS spread,
       round(stddev(ln(r_free / f_free) / sd) FILTER (WHERE NOT cen AND r_free > 0.5 AND sd > 0), 2) AS z_spread,
       round(avg((abs(ln(r_free / f_free) / sd) <= 1.2816)::int) FILTER (WHERE NOT cen AND r_free > 0.5 AND sd > 0), 3) AS inside_80,
       round(avg((ln(r_free / f_free) / sd > 1.2816)::int) FILTER (WHERE NOT cen AND r_free > 0.5 AND sd > 0), 3) AS later_than_band
  FROM c GROUP BY 1, 2 ORDER BY 1, 2;

-- (4) The learned power curve x the charge's own recent power, fitted before b2efcc07, scored on its running charges
WITH s AS (
  SELECT l.session_id, l.charger_type AS kind, v.vehicle_class_code AS cls, l.started_at AS st
    FROM public.ottoq_charge_duration_ledger l JOIN public.vehicles v ON v.id = l.vehicle_id
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.stopped_reason = 'completed'
     AND l.charger_type IN ('dcfc', 'l2') AND l.recorded_at < '2026-10-09 02:50:00+00' AND l.recorded_at >= '2026-10-03'
     AND COALESCE(l.tick_minutes, 99) <= 1
), p AS (
  SELECT s.kind, s.cls, (floor((mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric / 5) * 5)::int AS sb,
         CASE WHEN extract(epoch FROM (mm.sim_clock_at - s.st)) / 60.0 < 15 THEN 'cool' ELSE 'hot' END AS heat,
         (mm.payload -> 'sampledValue' -> 0 ->> 'value')::float8 AS kw
    FROM s JOIN public.ottoq_ocpp_messages mm ON mm.ocpp_session_id = s.session_id
   WHERE mm.message_type = 'MeterValues' AND (mm.payload -> 'sampledValue' -> 0 ->> 'measurand') = 'Power.Active.Import'
), curve AS (
  SELECT kind, cls, heat, sb, avg(kw) AS kw FROM p GROUP BY 1, 2, 3, 4 HAVING count(*) >= 20
), o AS (
  SELECT g.order_id, g.sim_run_id, g.sim_clock, s.state, g.realized
    FROM public.ottoq_charge_order_grades g JOIN public.ottoq_charge_order_snapshots s ON s.order_id = g.order_id
   WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.realized IS NOT NULL
     AND g.sim_run_id IN ('b2efcc07-e47e-40e2-9411-907e913a3976', '64251eb8-e5fb-4f7d-af25-9f4ddf5d3768')
), c AS (
  SELECT o.order_id, o.sim_run_id, o.sim_clock, ch ->> 'k' AS kind, (ch ->> 'id')::uuid AS stall_id, (ch ->> 'car')::uuid AS car,
         (ch ->> 'free')::float8 AS f_free, (o.realized #>> ARRAY['chargers', ch ->> 'id', 'free'])::float8 AS r_free
    FROM o CROSS JOIN LATERAL jsonb_array_elements(o.state -> 'chargers') ch
   WHERE COALESCE((ch ->> 'free')::numeric, 0) > 0 AND ch ? 'car'
     AND NOT COALESCE((o.realized #>> ARRAY['chargers', ch ->> 'id', 'cen'])::boolean, true)
     AND (o.realized #>> ARRAY['chargers', ch ->> 'id', 'free'])::float8 > 0.25
), t AS (
  SELECT c.*, l.battery_kwh AS bat, v.vehicle_class_code AS cls, extract(epoch FROM (c.sim_clock - l.started_at)) / 60.0 AS e,
         mv.soc_now, mv.kw_now
    FROM c JOIN LATERAL (
      SELECT * FROM public.ottoq_charge_duration_ledger l
       WHERE l.sim_run_id = c.sim_run_id AND l.stall_id = c.stall_id AND l.vehicle_id = c.car
         AND l.started_at <= c.sim_clock AND (l.ended_at IS NULL OR l.ended_at >= c.sim_clock)
       ORDER BY l.started_at DESC LIMIT 1) l ON true
    JOIN public.vehicles v ON v.id = c.car
    CROSS JOIN LATERAL (
      SELECT (array_agg(z.soc ORDER BY z.at DESC))[1] AS soc_now, avg(z.kw) AS kw_now
        FROM (SELECT mm.message_at AS at, (mm.payload -> 'sampledValue' -> 1 ->> 'value')::float8 AS soc,
                     (mm.payload -> 'sampledValue' -> 0 ->> 'value')::float8 AS kw
                FROM public.ottoq_ocpp_messages mm
               WHERE mm.ocpp_session_id = l.session_id AND mm.message_type = 'MeterValues'
                 AND (mm.payload -> 'sampledValue' -> 1 ->> 'measurand') = 'SoC' AND mm.sim_clock_at <= c.sim_clock
               ORDER BY mm.message_at DESC LIMIT 5) z) mv
), u AS (
  SELECT t.*, x.rem,
         (SELECT cx.kw FROM curve cx WHERE cx.kind = t.kind AND cx.cls = t.cls AND cx.heat = CASE WHEN t.e >= 15 THEN 'hot' ELSE 'cool' END
           ORDER BY abs(cx.sb - floor(t.soc_now / 5) * 5) LIMIT 1) AS kw_curve_now
    FROM t CROSS JOIN LATERAL (
      SELECT sum((t.bat / 100.0) * (LEAST(b.sb + 5, 100) - GREATEST(b.sb, t.soc_now)) / NULLIF(COALESCE(ch.kw, cc.kw, cn.kw), 0) * 60) AS rem
        FROM generate_series(0, 95, 5) b(sb)
        LEFT JOIN curve ch ON ch.kind = t.kind AND ch.cls = t.cls AND ch.sb = b.sb AND ch.heat = CASE WHEN t.e >= 15 THEN 'hot' ELSE 'cool' END
        LEFT JOIN curve cc ON cc.kind = t.kind AND cc.cls = t.cls AND cc.sb = b.sb AND cc.heat = CASE WHEN t.e >= 15 THEN 'cool' ELSE 'hot' END
        LEFT JOIN LATERAL (SELECT cx.kw FROM curve cx WHERE cx.kind = t.kind AND cx.cls = t.cls ORDER BY abs(cx.sb - b.sb), cx.heat LIMIT 1) cn ON true
       WHERE b.sb + 5 > t.soc_now) x
   WHERE t.soc_now IS NOT NULL AND t.soc_now < 100 AND t.kw_now > 0
)
SELECT kind, left(sim_run_id::text, 8) AS run, count(*) AS n,
       round(avg(r_free - f_free)::numeric, 2) AS bias_check, round(avg(abs(r_free - f_free))::numeric, 2) AS miss_check,
       round(avg(r_free - rem * kw_curve_now / kw_now)::numeric, 2) AS bias_curve,
       round(avg(abs(r_free - rem * kw_curve_now / kw_now))::numeric, 2) AS miss_curve
  FROM u WHERE rem > 0 GROUP BY 1, 2 ORDER BY 1, 2;

-- (5) The decisions, rehearsed: run once per batch (LIMIT 3 OFFSET 0, 3, ..., 18; each call is a fresh session and the
--     MCP client times out at 60 s). The temporary roll is the stored rollout's (ottoq_charge_order_verdict_v2 over 12
--     futures) with the stored schedule; only the state's running fast chargers change.
CREATE FUNCTION pg_temp.roll(p_state jsonb, p_order jsonb, p_futures int, p_seed text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  v_n int := GREATEST(1, LEAST(COALESCE(p_futures, 12), 64));
  k0 jsonb; a0 jsonb; k jsonb; a jsonb; c jsonb; c0 jsonb; s int;
  v_w int := 0; v_t int := 0; v_l int := 0;
BEGIN
  k0 := public.ottoq_charge_line_schedule(p_state, NULL, 0, p_seed, false);
  a0 := public.ottoq_charge_line_schedule(p_state, p_order, 0, p_seed, false);
  c0 := public.ottoq_charge_line_compare(k0, a0);
  IF (k0 -> 'first') = (a0 -> 'first') THEN
    RETURN jsonb_build_object('same_first_seats', true, 'futures', 1, 'wins', 0, 'ties', 1, 'losses', 0,
                              'point', c0 || jsonb_build_object('kernel', k0 - 'first', 'agent', a0 - 'first'));
  END IF;
  FOR s IN 0 .. v_n - 1 LOOP
    IF s = 0 THEN c := c0;
    ELSE
      k := public.ottoq_charge_line_schedule(p_state, NULL, s, p_seed, false);
      a := public.ottoq_charge_line_schedule(p_state, p_order, s, p_seed, false);
      c := public.ottoq_charge_line_compare(k, a);
    END IF;
    IF (c ->> 'cmp')::int > 0 THEN v_w := v_w + 1; ELSIF (c ->> 'cmp')::int < 0 THEN v_l := v_l + 1; ELSE v_t := v_t + 1; END IF;
  END LOOP;
  RETURN jsonb_build_object('same_first_seats', false, 'futures', v_n, 'wins', v_w, 'ties', v_t, 'losses', v_l,
                            'point', c0 || jsonb_build_object('kernel', k0 - 'first', 'agent', a0 - 'first'));
END $f$;

CREATE TEMP TABLE curve AS
WITH s AS (
  SELECT l.session_id, l.charger_type AS kind, v.vehicle_class_code AS cls, l.started_at AS st
    FROM public.ottoq_charge_duration_ledger l JOIN public.vehicles v ON v.id = l.vehicle_id
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.stopped_reason = 'completed'
     AND l.charger_type = 'dcfc' AND l.recorded_at < '2026-10-09 02:50:00+00' AND l.recorded_at >= '2026-10-03'
     AND COALESCE(l.tick_minutes, 99) <= 1
), p AS (
  SELECT s.kind, s.cls, (floor((mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric / 5) * 5)::int AS sb,
         CASE WHEN extract(epoch FROM (mm.sim_clock_at - s.st)) / 60.0 < 15 THEN 'cool' ELSE 'hot' END AS heat,
         (mm.payload -> 'sampledValue' -> 0 ->> 'value')::float8 AS kw
    FROM s JOIN public.ottoq_ocpp_messages mm ON mm.ocpp_session_id = s.session_id
   WHERE mm.message_type = 'MeterValues' AND (mm.payload -> 'sampledValue' -> 0 ->> 'measurand') = 'Power.Active.Import'
)
SELECT kind, cls, heat, sb, avg(kw) AS kw FROM p GROUP BY 1, 2, 3, 4 HAVING count(*) >= 20;

CREATE FUNCTION pg_temp.rem(p_run uuid, p_stall uuid, p_car uuid, p_clock timestamptz) RETURNS float8 LANGUAGE sql STABLE AS $f$
  WITH l AS (SELECT * FROM public.ottoq_charge_duration_ledger l
              WHERE l.sim_run_id = p_run AND l.stall_id = p_stall AND l.vehicle_id = p_car
                AND l.started_at <= p_clock AND (l.ended_at IS NULL OR l.ended_at >= p_clock)
              ORDER BY l.started_at DESC LIMIT 1),
  t AS (SELECT l.battery_kwh AS bat, v.vehicle_class_code AS cls, extract(epoch FROM (p_clock - l.started_at)) / 60.0 AS e,
               mv.soc_now, mv.kw_now
          FROM l JOIN public.vehicles v ON v.id = l.vehicle_id
          CROSS JOIN LATERAL (
            SELECT (array_agg(z.soc ORDER BY z.at DESC))[1] AS soc_now, avg(z.kw) AS kw_now
              FROM (SELECT mm.message_at AS at, (mm.payload -> 'sampledValue' -> 1 ->> 'value')::float8 AS soc,
                           (mm.payload -> 'sampledValue' -> 0 ->> 'value')::float8 AS kw
                      FROM public.ottoq_ocpp_messages mm
                     WHERE mm.ocpp_session_id = l.session_id AND mm.message_type = 'MeterValues'
                       AND (mm.payload -> 'sampledValue' -> 1 ->> 'measurand') = 'SoC' AND mm.sim_clock_at <= p_clock
                     ORDER BY mm.message_at DESC LIMIT 5) z) mv)
  SELECT CASE WHEN t.soc_now IS NULL OR t.soc_now >= 100 OR t.kw_now IS NULL OR t.kw_now <= 0 THEN NULL ELSE
         (SELECT sum((t.bat / 100.0) * (LEAST(b.sb + 5, 100) - GREATEST(b.sb, t.soc_now))
                     / NULLIF(COALESCE(ch.kw, cc.kw, cn.kw), 0) * 60)
            FROM generate_series(0, 95, 5) b(sb)
            LEFT JOIN curve ch ON ch.kind = 'dcfc' AND ch.cls = t.cls AND ch.sb = b.sb AND ch.heat = CASE WHEN t.e >= 15 THEN 'hot' ELSE 'cool' END
            LEFT JOIN curve cc ON cc.kind = 'dcfc' AND cc.cls = t.cls AND cc.sb = b.sb AND cc.heat = CASE WHEN t.e >= 15 THEN 'cool' ELSE 'hot' END
            LEFT JOIN LATERAL (SELECT cx.kw FROM curve cx WHERE cx.cls = t.cls ORDER BY abs(cx.sb - b.sb), cx.heat LIMIT 1) cn ON true
           WHERE b.sb + 5 > t.soc_now)
         * (SELECT cx.kw FROM curve cx WHERE cx.cls = t.cls AND cx.heat = CASE WHEN t.e >= 15 THEN 'hot' ELSE 'cool' END
             ORDER BY abs(cx.sb - floor(t.soc_now / 5) * 5) LIMIT 1) / t.kw_now END
    FROM t
$f$;

WITH o AS (
  SELECT g.order_id, g.sim_run_id, g.outcome, g.p_win AS p_win_stored, g.taken, s.state, s.seed, s.agent_order, s.sim_clock,
         CASE WHEN g.outcome IN ('right_take', 'missed_win') THEN 1 WHEN g.outcome IN ('wrong_take', 'right_refusal') THEN 0 END AS y
    FROM public.ottoq_charge_order_grades g JOIN public.ottoq_charge_order_snapshots s ON s.order_id = g.order_id
   WHERE g.sim_run_id IN ('b2efcc07-e47e-40e2-9411-907e913a3976', '64251eb8-e5fb-4f7d-af25-9f4ddf5d3768') AND g.decision
   ORDER BY g.order_id
   LIMIT 3 OFFSET 0
), m AS (
  SELECT o.*,
         (SELECT jsonb_agg(CASE WHEN x.value ->> 'k' = 'dcfc' AND x.value ? 'car' AND (x.value ->> 'free')::float8 > 0
                                     AND pg_temp.rem(o.sim_run_id, (x.value ->> 'id')::uuid, (x.value ->> 'car')::uuid, o.sim_clock) IS NOT NULL
                                THEN x.value || jsonb_build_object('free', round(pg_temp.rem(o.sim_run_id, (x.value ->> 'id')::uuid, (x.value ->> 'car')::uuid, o.sim_clock)::numeric, 2))
                                ELSE x.value END ORDER BY x.o)
            FROM jsonb_array_elements(o.state -> 'chargers') WITH ORDINALITY x(value, o)) AS ch1
    FROM o
), r AS (
  SELECT m.order_id, m.sim_run_id, m.outcome, m.y, m.p_win_stored, m.taken,
         public.ottoq_charge_order_verdict_v2(pg_temp.roll(m.state, m.agent_order, 12, m.seed), 0.8) AS v0,
         public.ottoq_charge_order_verdict_v2(pg_temp.roll(m.state || jsonb_build_object('chargers', m.ch1), m.agent_order, 12, m.seed), 0.8) AS v1,
         public.ottoq_charge_order_verdict_v2(pg_temp.roll(m.state || jsonb_build_object('chargers',
             (SELECT jsonb_agg(CASE WHEN c.value ->> 'k' = 'dcfc' AND c.value ? 'car' THEN c.value || jsonb_build_object('sd', 0.27) ELSE c.value END ORDER BY c.o)
                FROM jsonb_array_elements(m.ch1) WITH ORDINALITY c(value, o))), m.agent_order, 12, m.seed), 0.8) AS v2
    FROM m
)
SELECT left(sim_run_id::text, 8) AS run, order_id, outcome, y, p_win_stored, taken,
       (v0 ->> 'take')::boolean AS take0, (v0 ->> 'wins') || '/' || (v0 ->> 'futures') AS w0,
       (v1 ->> 'take')::boolean AS take1, (v1 ->> 'wins') || '/' || (v1 ->> 'futures') AS w1,
       (v2 ->> 'take')::boolean AS take2, (v2 ->> 'wins') || '/' || (v2 ->> 'futures') AS w2
  FROM r ORDER BY order_id;

-- (6) Does the check tell a better order from a worse one? Its share of futures won, its expected future, and hindsight
WITH d AS (
  SELECT g.order_id, left(g.sim_run_id::text, 8) AS run, g.outcome, g.p_win, (g.expected ->> 'cmp')::int AS exp_cmp,
         (g.hindsight ->> 'cmp')::int AS hind_cmp, g.hindsight ->> 'by' AS decided_by, (g.hindsight ->> 'd_late')::numeric AS d_late,
         CASE WHEN g.outcome IN ('right_take', 'missed_win') THEN 1 WHEN g.outcome IN ('wrong_take', 'right_refusal') THEN 0 END AS y
    FROM public.ottoq_charge_order_grades g
   WHERE g.decision AND g.sim_run_id IN ('b2efcc07-e47e-40e2-9411-907e913a3976', '64251eb8-e5fb-4f7d-af25-9f4ddf5d3768')
)
SELECT count(*) FILTER (WHERE y IS NOT NULL) AS judged,
       count(*) FILTER (WHERE y IS NOT NULL AND (exp_cmp > 0) = (y = 1)) AS expected_future_agrees,
       round(avg(p_win) FILTER (WHERE y = 1), 3) AS p_win_winners, round(avg(p_win) FILTER (WHERE y = 0), 3) AS p_win_losers,
       round(avg((p_win - y) ^ 2) FILTER (WHERE y IS NOT NULL), 3) AS brier,
       round((avg(y) FILTER (WHERE y IS NOT NULL) * (1 - avg(y) FILTER (WHERE y IS NOT NULL))), 3) AS brier_of_base_rate,
       (SELECT round(avg(CASE WHEN w.p_win > l.p_win THEN 1.0 WHEN w.p_win = l.p_win THEN 0.5 ELSE 0 END), 3)
          FROM d w JOIN d l ON w.y = 1 AND l.y = 0) AS auc
  FROM d;
