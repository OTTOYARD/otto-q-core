-- 0423  **The first armed run after 0628, graded, and the production path run end to end on the twin depot (0629).**
--        Chase asked for the agent to be on whenever a run is active and when real vehicle data flows (2026-10-08, the
--        evening CT), and asked to test it. Two runs answer it. b2efcc07, an operator's busy_day run, armed as every
--        operator run is, gives the first out-of-sample reading of the check's forecasts after 0627/0628: they miss a
--        car's arrival by 1.37 minutes on average with 82.6% inside the 80% band, and the band is wrong in a way that
--        has a shape. It is too narrow for cars due within 10 minutes (50.4% inside) and too wide past 30 minutes
--        (91.9-94.0%), where the cars also come home 1-2 minutes early. Cars already at their rung at the order are not
--        scored at all (G371). c4ee1572 is a production session started on the twin depot with the sim feed: it armed
--        itself at the start (0629), the agent passed once each 2-minute tick, the solver chain completed every pass,
--        no car was held at the gate, and every write under the agent's name was refused.
--
--        Written 2026-10-08, 11:35 PM CT. Read-only. Twin depot 11111111-…. One run each: single readings, not ranges.
--
-- ══ §1 THE TEST RUN (reproduce: (1)) ══
--
--   b2efcc07: busy_day, seed 5920364814268136782, operator_demo, started 02:50:44 UTC (9:50 PM CT on the 8th) by the
--   app's own start door at 3x, stopped by its stop door at 04:11:02 UTC (11:11 PM CT) for grading: 1,108 ticks, sim
--   13:00-17:00 on world day 2026-10-08 (240.8 sim-minutes, a mean tick of 0.21 sim-minutes), 128 dispatches and 115
--   returns. 0629 was applied mid-run (03:37:33 UTC) and changed nothing for it: the agent's next two passes wrote as
--   before and were refused nothing.
--
--   The agent passed 136 times (Nemotron Ultra and Super: mean 32.5 s, p50 28.0 s, p95 53.5 s, max 89.6 s; every one
--   handed to CP-SAT, mean 17 ms) and sent 136 charge orders. The check:
--
--     same as the kernel's order                127   (93.4%; d9d49732: 86 of 109, 78.9%)
--     refused, not enough futures won             5
--     refused, worse in the expected future       2
--     taken (wins most futures)                   2   one accepted (12 of 12, sim 13:03), one partial (10 of 12, 13:26)
--
-- ══ §2 THE CHECK AGAINST HINDSIGHT (reproduce: (2)) ══
--
--   All 136 graded (the nightly grader on demand at 04:22 UTC, after both runs had stopped; it skips while any run
--   runs). The agent's order differed from the kernel's in a way that mattered 9 times:
--
--     right refusal 6, missed win 1        the check turned down 7 and was right on 6
--     wrong take 1, neutral take 1         it took 2: one made things worse, one changed nothing
--     no decision 101, no decision that mattered 26
--
--   So the agent's differing order won in hindsight once in the 8 that can be scored (12.5%), and the check kept the
--   kernel's order 7 times. Its win probability is still overconfident: a Brier score of 0.332 on those 8 against
--   0.109 for the base rate (d9d49732: 0.258 against 0.238, G353-G355). Eight decisions are too few to say more; what
--   they say is that the gate's decisions were mostly right and its probabilities were not.
--
-- ══ §3 THE ARRIVALS, OUT OF SAMPLE, BY HOW FAR AHEAD (G371; reproduce: (3)) ══
--
--   Every car at work an order forecast home that came home inside the order's window, from the forecast the check
--   itself made at the order (state.inbound: eta, esd, trip, the drain it used, 0628), scored by
--   ottoq_inbound_arrival_z against what happened: 3,703 arrivals, 100 returns.
--
--     horizon (minutes to the rung)    arrivals   bias, min   abs error, min   inside 80% band   past 3 spreads late / early
--     at or past the rung (0)              45       +0.61          0.61            not scored         -
--     under 10                            508       +0.02          0.45            50.4%              35 / 9
--     10 to 30                          1,095       -0.56          0.94            79.1%               1 / 0
--     30 to 60                          1,586       -1.11          1.65            91.9%               0 / 0
--     60 and more                         469       -1.97          2.48            94.0%               0 / 0
--     all                               3,703       -0.88          1.371           82.6%              36 / 9
--
--   (a) The band's width grows too fast with the horizon. The futures give a car's arrival a log spread of
--       sqrt(dsd^2 + (asd / hz)^2): in minutes, the class drain's spread times the horizon, plus the drive's 0.17. The
--       error grows more slowly than that: a car's battery does not drain at one rate for an hour, it drains in rides
--       and waits, and over a few minutes that swings far more than the level's spread, while over an hour it averages
--       out. So the band is half as wide as it should be under 10 minutes and wider than it should be past 30.
--   (b) The late cars under 10 minutes are not the drive home this time. The 36 arrivals past 3 spreads late are 24
--       returns: the recall came a mean 0.70 minutes after the forecast's crossing, the car turned home at the recall
--       (0.00), and the drive took 1.54 minutes against 1.24: 1.00 minute late in all, at a mean horizon of 3.1
--       minutes. The kernel looks at each car every tick (median 0.18 sim-minutes between its recall decisions), so the
--       lateness is the battery reaching the rung later, not the kernel seeing it late.
--   (c) Past 30 minutes cars come home 1.1-2.0 minutes early on average. Not explained here: a drain that quickens
--       through the run, other calls home above the fit's rate, or both.
--   (d) A car already at or below its rung when the order is made is forecast home after the drive alone, and
--       ottoq_inbound_arrival_z returns no score for it (45 arrivals, a mean 0.61 minutes late): the review and the
--       gates count it nowhere.
--
--   Against d9d49732's recomputed gate (0422: 1.577 minutes, 88.4% inside) this run reads 1.371 and 82.6%. They are
--   different worlds and the first is a recomputation, so they are not a pair.
--
-- ══ §4 THE PRODUCTION PATH, END TO END (0629; reproduce: (4)) ══
--
--   c4ee1572: ottoq_production_start on the twin depot at 04:11:42 UTC (11:11 PM CT), the sim feed (depots.feed_mode
--   'sim'), the depot just reset by b2efcc07's stop; stopped by ottoq_production_stop at 04:22:05 UTC (11:22 PM CT).
--
--     armed at the start          12 run dials, all written by 'production_start'; the arming report 'armed', 7 of 7,
--                                 the two hold keys at their required 0; the start event production.session_started
--                                 says 'armed (0629)' and lists the one setting it inherited under an agent's name
--                                 (energy_reserve_shave = 1 at the twin depot, by the promoter on 2026-09-26, G370)
--     the driver                  6 ticks from the ottoq-depot-tick cron (2 minutes), and the agent claimed each one
--                                 within seconds: 6 passes (04:12:16 ... 04:22:06), Nemotron Ultra, max 25.6 s, so
--                                 every pass landed inside its tick; the CP-SAT handoff completed on every pass
--     the board                   carries production: {live: true, dials: read_only} with its note
--     the agent's own writes      none attempted: 0 set_policy, 0 ops_action, 0 rejected in 6 passes
--     a write under its name      sent once each by hand on the live session: the run dial, the ops action and a depot
--                                 dial were refused, production_never_self_tunes (production_run, production_run,
--                                 depot_hosts_a_live_production_session), AI.001 judged each, nothing was written
--     the order                   2 charge orders, both the kernel's own order (refused, same_as_kernel); the order's
--                                 life 3 ticks (4.30 and 4.98 minutes at a session-average tick of 1.43 and 1.66
--                                 minutes, which tends to 2.0 and 6.0 as the session runs)
--     gate holds                  0 deferral rows
--
--   With the depot reset every car was offline at the start, so this proves the start, the arming, the driver, the
--   board and the refusals, not the handling of cars. That waits on vehicle data.
--
-- ══ §5 WHAT IS LEFT ══
--
--   G371: give the futures a spread that grows with the square root of the horizon as well as the level's linear
--   one (a battery that drains in rides and waits), fitted from the depot's own returns, and score a car already at
--   its rung with the drive's own spread; then find the long-horizon early bias. G370: a person's call. G366 and G369
--   as before. And the check's win probability (§2) stays overconfident until the futures it rolls are calibrated,
--   which is what G371 is for. Nothing here changes when a car goes out, comes back or how full it charges (rule 9).

-- (1) the run, its orders and how the check answered them
SELECT r.random_seed::text AS seed, r.tick_count, round(extract(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0, 1) AS sim_min,
       (SELECT jsonb_object_agg(k, n) FROM (SELECT o.status || ':' || COALESCE(o.projection ->> 'reason', '?') AS k, count(*) AS n
                                              FROM public.ottoq_agent_charge_orders o WHERE o.sim_run_id = r.sim_run_id GROUP BY 1) z) AS orders,
       (SELECT jsonb_object_agg(provider, jsonb_build_object('n', n, 'mean_ms', m, 'p95_ms', p95))
          FROM (SELECT provider, count(*) AS n, round(avg(latency_ms)) AS m,
                       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)) AS p95
                  FROM public.ottoq_model_call_ledger l WHERE l.sim_run_id = r.sim_run_id GROUP BY 1) x) AS calls
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'b2efcc07-e47e-40e2-9411-907e913a3976';

-- (2) the grades, and the check's probability against them
SELECT (SELECT jsonb_object_agg(outcome, n) FROM (SELECT outcome, count(*) AS n FROM public.ottoq_charge_order_hindsight
                                                   WHERE sim_run_id = 'b2efcc07-e47e-40e2-9411-907e913a3976' GROUP BY 1) o) AS outcomes,
       d.scored, d.brier, d.base_rate, d.brier_base
  FROM (SELECT count(*) FILTER (WHERE y IS NOT NULL) AS scored,
               round(avg(power(p_win - y, 2)) FILTER (WHERE y IS NOT NULL)::numeric, 3) AS brier,
               round(avg(y)::numeric, 3) AS base_rate, round((avg(y) * (1 - avg(y)))::numeric, 3) AS brier_base
          FROM (SELECT h.p_win, CASE WHEN h.outcome IN ('right_take', 'missed_win') THEN 1
                                     WHEN h.outcome IN ('right_refusal', 'wrong_take') THEN 0 END AS y
                  FROM public.ottoq_charge_order_hindsight h
                 WHERE h.sim_run_id = 'b2efcc07-e47e-40e2-9411-907e913a3976' AND h.decision) q) d;

-- (3) the arrivals by horizon, from the forecasts the check made
WITH ar AS (
  SELECT h.order_id, s.sim_clock AS clock, ib.value AS e, s.state -> 'recall' AS rc,
         (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
         (ib.value ->> 'eta')::float8 AS fc, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip, ib.value ->> 'id' AS vid
    FROM public.ottoq_charge_order_hindsight h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
   WHERE h.sim_run_id = 'b2efcc07-e47e-40e2-9411-907e913a3976' AND ib.value ->> 'src' = 'forecast'
     AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
), g AS (
  SELECT ar.*, public.ottoq_inbound_arrival_z(ar.e, ar.rc, ar.act) AS z, ar.fc - ar.trip AS hz,
         ar.vid || '@' || to_char(date_trunc('minute', ar.clock + make_interval(secs => ar.act * 60) + interval '30 seconds'),
                                  'YYYY-MM-DD HH24:MI') AS ret
    FROM ar
)
SELECT CASE WHEN hz <= 0.001 THEN '0 at or past rung' WHEN hz < 10 THEN '1 under 10' WHEN hz < 30 THEN '2 10-30'
            WHEN hz < 60 THEN '3 30-60' ELSE '4 60+' END AS horizon,
       count(*) AS arrivals, count(DISTINCT ret) AS returns, round(avg(act - fc)::numeric, 2) AS bias_min,
       round(avg(abs(act - fc))::numeric, 2) AS mae_min, round(avg((abs(z) <= 1.2816)::int)::numeric, 3) AS in_band,
       count(*) FILTER (WHERE z IS NULL) AS unscored, count(*) FILTER (WHERE z > 3) AS late3, count(*) FILTER (WHERE z < -3) AS early3
  FROM g GROUP BY 1 ORDER BY 1;

-- (4) the production session
SELECT r.started_at, r.ended_at, r.tick_count, r.failure_reason,
       (SELECT count(*) FROM public.ottoq_policy_params p WHERE p.scope_type = 'run' AND p.scope_id = r.sim_run_id
                                                            AND p.updated_by = 'production_start') AS dials_by_start,
       (SELECT count(*) FROM public.ottoq_policy_params p WHERE p.scope_type = 'run' AND p.scope_id = r.sim_run_id
                                                            AND public.ottoq_is_agent_actor(p.updated_by)) AS dials_by_agent,
       (SELECT count(*) FROM public.ottoq_decisions d WHERE d.sim_run_id = r.sim_run_id
                                                     AND d.resolved_action_context = 'orchestrator_agent') AS agent_passes,
       (SELECT count(*) FROM public.ottoq_decisions d, jsonb_array_elements(COALESCE(d.enacted_action -> 'applied', '[]'::jsonb)) a
         WHERE d.sim_run_id = r.sim_run_id AND d.resolved_action_context = 'orchestrator_agent'
           AND a ->> 'type' IN ('set_policy', 'ops_action')) AS agent_dial_moves,
       (SELECT count(*) FROM public.ottoq_cuopt_deferrals c WHERE c.sim_run_id = r.sim_run_id) AS gate_holds,
       (SELECT string_agg(o.order_id || ' ' || o.status || ' ' || COALESCE(o.projection ->> 'reason', '?'), ', ' ORDER BY o.order_id)
          FROM public.ottoq_agent_charge_orders o WHERE o.sim_run_id = r.sim_run_id) AS orders,
       (SELECT e.payload ->> 'agents' FROM public.ottoq_events e WHERE e.sim_run_id = r.sim_run_id
                                                               AND e.event_type = 'production.session_started') AS start_event
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'c4ee1572-1a21-42a9-ba98-ad64dae85535';
