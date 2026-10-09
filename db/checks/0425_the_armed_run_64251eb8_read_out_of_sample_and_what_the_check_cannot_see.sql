-- 0425  **The armed run 64251eb8 on b2efcc07's seed: the new stack read out of sample, and what the check cannot see.**
--        The first run on the batch 0630-0641 and agent v27: busy_day, seed 5920364814268136782, the operator's start
--        door, live playback at 3x, 6:05-7:20 AM CT on 2026-10-09, stopped at sim 17:00 and graded. Its forecasts are
--        out of sample for everything the batch fitted on b2efcc07. The arrivals got better at every horizon and the
--        fast-charge clock much better; the L2 clock got worse (G386). The check took 1 of the agent's 100 orders and
--        refused 10 for cause, and in what really happened 7 of those 10 would have won: every one decided on due
--        times, and the check's futures see one due car in nine, because a car coming home is not known to be due
--        until it reaches the gate (G385). The kernel's own line still left low batteries waiting about two hours
--        (G384, built as 0642 and live from 7:32 AM CT).
--
--        Written 2026-10-09, 7:40-8:00 AM CT. Read-only. Twin depot 11111111-…. One run: single readings, not ranges.
--
-- ══ §1 THE RUN (reproduce: (1)) ══
--
--   954 ticks, 240.9 sim-minutes, 11:05:48-12:20:46 UTC. 100 orders from the agent (v27 on all 101 passes): 89 the
--   kernel's own order (same_as_kernel), 1 taken (partial, wins_most_futures), 10 refused for cause (5
--   not_enough_futures_won, 5 worse_in_expected_future). The agent's call: 101 calls, a mean 46.0 s (median 44.8, p95
--   76.1, longest 94.6), slower than b2efcc07's; the CP-SAT leg 100 calls at a mean 19 ms.
--
-- ══ §2 THE GRADES (reproduce: (2)) ══
--
--   Graded 90 sim-minutes after each order against what really happened, with the kernel's own order from the same
--   moment. Scored decisions (the check took or refused for cause):
--
--                 scored   right take   missed win   right refusal   wrong take   Brier   base rate   Brier at base   mean p_win
--     64251eb8      10         0            7              3              0        0.351     0.700        0.210          0.433
--     b2efcc07       8         0            1              6              1        0.332     0.125        0.109          0.604
--
--   In one world the check refused correctly six times in seven; in the other it refused seven winners in ten. Its win
--   probability tracks neither (0.433 where 0.700 won, 0.604 where 0.125 did), so the bar it is held to (10 of 12
--   futures) is deciding on a number that does not yet discriminate. §3 is the largest reason.
--
-- ══ §3 THE CHECK DOES NOT KNOW WHICH ARRIVING CARS WILL BE DUE (G385; reproduce: (3)) ══
--
--   The twin draws a returning car's urgency when it reaches the gate (seeded: immediate dispatch with probability 0.30
--   by day, an overnight hold with 0.75 between 22:00 and 04:00, due 45 minutes after arrival; migration 0200). The
--   check's state carries every car coming home with imm false and no due time, so its futures hold no due car among
--   them. Per graded order whose window ran to its end:
--
--                 orders   due at the depot   due among the     due in the        due in        arrivals in    of them   due share   unseen
--                          at the order       inbound (state)   expected future   hindsight     the window     due       of arrivals
--     64251eb8      63          1.30              0.00              1.30              11.43         39.81        10.11      25.4%      88.6%
--     b2efcc07      87          0.83              0.00              0.83              11.06         39.16        10.23      26.0%      92.5%
--
--   So the check's first two terms (cars ready by their due time, then minutes late) are computed over about one due
--   car in nine. All 7 of 64251eb8's missed wins were decided in hindsight on those terms (6 on lateness, 1 on cars on
--   time). The next build: the futures draw each arriving car's urgency the way the depot's own history shows it (the
--   share by hour, and the due offset), the same draw for both sides of a future so it cancels where the orders agree,
--   and the expected future carries the expected share. Filed as G385.
--
-- ══ §4 THE ARRIVALS BY HORIZON, OUT OF SAMPLE (0633, 0634; reproduce: (4)) ══
--
--   64251eb8's orders were made with 0633's spread and 0634's drain, both fitted on b2efcc07; b2efcc07's stored
--   forecasts carry the spread before 0633. Forecast arrivals that arrived, z from the forecast's own spread:
--
--                         arrivals (returns)    bias, min      mean miss, min    inside the 80% band    late past 3 sd
--     horizon             64251eb8  b2efcc07    64251  b2efc   64251  b2efc      64251eb8  b2efcc07      64251  b2efc
--     under 10              368      508        +0.40  +0.02    0.72   0.45       83.4%     50.4%            7     35
--     10-30                 791    1,095        +0.26  -0.56    0.91   0.94       86.6%     79.1%           10      1
--     30-60               1,206    1,586        -0.39  -1.11    1.70   1.65       90.7%     91.9%           12      0
--     60+                   348      469        -1.51  -1.97    2.61   2.48       95.7%     94.0%            2      0
--     all (101 / 100)     2,741    3,703        -0.23  -0.88    1.44   1.37       89.2%     82.6%           31     36
--
--   The band now holds the near arrivals (50.4% -> 83.4% under 10 minutes) and the early bias past an hour is smaller
--   (-1.97 -> -1.51). It is now too wide past 30 minutes (90.7-95.7% inside an 80% band): the walk 0633 fitted on one
--   run grows the spread faster than this run needed. Not acted on from one run.
--
-- ══ §5 THE CHARGE CLOCK, OUT OF SAMPLE (0632, 0636; reproduce: (5)) ══
--
--                 kind   charges   inside the 80% band   mean z   rms z    actual / forecast   rms log ratio
--     64251eb8    dcfc     230          62.6%            +0.58    2.27         1.053              0.209
--     b2efcc07    dcfc     272          26.5%            +2.35    4.58         1.159              0.286
--     64251eb8    l2       109          54.1%            -0.98    1.24         0.892              0.145
--     b2efcc07    l2       146          80.8%            -0.17    1.02         0.981              0.116
--
--   Fast charges: much closer (the air temperature level and the spread by length together). L2: worse, and biased:
--   L2 charges came in 11% shorter than the clock forecast, and the narrower spread 0636 gave long L2 charges (x0.90
--   at 120-240 minutes, x0.86 past 240) leaves more of them outside. Two things moved between the runs and this does
--   not separate them: the air temperature level (0632), which the twin's physics applies to both kinds, and the
--   nightly refit at 11:22 UTC, which ran inside 64251eb8 (6:22 AM CT), so its orders read two fits. Filed as G386,
--   to be answered with the clock's own trial (ottoq_charge_clock_trial) before anything changes.
--
-- ══ §6 FAULTS ══
--
--   Real faults inside the graded windows: 58 in 63 (0.92 an order) on 64251eb8, 106 in 87 (1.22) on b2efcc07. The
--   grade does not store how many faults each sampled future drew (the per-future summary carries no draw count), so
--   0635's draws are not compared with these here.
--
-- ══ §7 THE KERNEL'S OWN LINE (G384; reproduce: (6)) ══
--
--   The longest wait each car waiting for a charger had reached at any order, from the order snapshots (the cursor's
--   own wait, read every pass; a lower bound on its full wait), by its battery:
--
--                 battery       cars   mean longest wait   longest   over 30   over 60   over 90
--     64251eb8    under 45%      21          121.6            238       16        15        15
--     64251eb8    45-80%         82           75.7            180       66        46        35
--     64251eb8    80% and up      4           81.2             99        4         4         1
--     b2efcc07    under 45%      20          108.1            239       15        12        11
--     b2efcc07    45-80%         80           88.2            183       63        52        45
--     b2efcc07    80% and up      7           73.1             93        7         5         2
--
--   This is the kernel's order before 0642, in two worlds of one seed: low batteries waited about two hours, 15 of 21
--   past 90 minutes. 72b09010 (started 7:32 AM CT, the same seed and start clock) is the first run under 0642 and is
--   read against these rows.
--
-- ══ §8 NEXT ══
--
--   Read 72b09010 against §7 and §2 (low-battery waits, cars past their contract wait, due cars on time, and how often
--   the check's verdicts are right). Build G385 (urgency in the futures). Answer G386 with the clock's own trial.

-- (1) the run, its orders and the calls
SELECT r.random_seed::text AS seed, r.scenario_code, r.tick_count, round(extract(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0, 1) AS sim_min,
       r.started_at, r.ended_at, r.status,
       (SELECT jsonb_object_agg(k, n) FROM (SELECT o.status || ':' || COALESCE(o.projection ->> 'reason', '?') AS k, count(*) AS n
                                              FROM public.ottoq_agent_charge_orders o WHERE o.sim_run_id = r.sim_run_id GROUP BY 1) z) AS orders,
       (SELECT jsonb_object_agg(provider, jsonb_build_object('n', n, 'mean_ms', m, 'p50_ms', p50, 'p95_ms', p95, 'max_ms', mx))
          FROM (SELECT provider, count(*) AS n, round(avg(latency_ms)) AS m,
                       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_ms)) AS p50,
                       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)) AS p95, max(latency_ms) AS mx
                  FROM public.ottoq_model_call_ledger l WHERE l.sim_run_id = r.sim_run_id GROUP BY 1) x) AS calls,
       (SELECT jsonb_object_agg(COALESCE(v, '?'), n) FROM (SELECT d.context_frame ->> 'agent_version' AS v, count(*) AS n FROM public.ottoq_decisions d
           WHERE d.sim_run_id = r.sim_run_id AND d.resolved_action_context = 'orchestrator_agent' GROUP BY 1) z) AS agent_versions
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '64251eb8-e5fb-4f7d-af25-9f4ddf5d3768';

-- (2) the grades, and the check's win probability against them
SELECT left(h.sim_run_id::text, 8) AS run,
       (SELECT jsonb_object_agg(outcome, n) FROM (SELECT outcome, count(*) AS n FROM public.ottoq_charge_order_hindsight x WHERE x.sim_run_id = h.sim_run_id GROUP BY 1) o) AS outcomes,
       count(*) FILTER (WHERE y IS NOT NULL) AS scored,
       round(avg(power(p_win - y, 2)) FILTER (WHERE y IS NOT NULL)::numeric, 3) AS brier,
       round(avg(y)::numeric, 3) AS base_rate, round((avg(y) * (1 - avg(y)))::numeric, 3) AS brier_base,
       round(avg(p_win) FILTER (WHERE y IS NOT NULL)::numeric, 3) AS mean_p
  FROM (SELECT h.sim_run_id, h.p_win, CASE WHEN h.outcome IN ('right_take', 'missed_win') THEN 1
                                           WHEN h.outcome IN ('right_refusal', 'wrong_take') THEN 0 END AS y
          FROM public.ottoq_charge_order_hindsight h
         WHERE h.sim_run_id IN ('64251eb8-e5fb-4f7d-af25-9f4ddf5d3768', 'b2efcc07-e47e-40e2-9411-907e913a3976') AND h.decision) h
 GROUP BY h.sim_run_id;

-- (3) due cars: what the check's state and expected future hold against what the window really held (G385)
WITH g AS (
  SELECT h.sim_run_id, h.order_id, h.outcome, h.decision,
         (h.expected #>> '{kernel,with_due}')::int AS exp_due, (h.hindsight #>> '{kernel,with_due}')::int AS real_due,
         h.hindsight ->> 'by' AS real_by,
         (SELECT count(*) FROM jsonb_array_elements(COALESCE(s.state -> 'cars', '[]')) c WHERE COALESCE((c.value ->> 'imm')::boolean, false)) AS state_due_here,
         (SELECT count(*) FROM jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]')) c WHERE COALESCE((c.value ->> 'imm')::boolean, false)) AS state_due_inbound,
         (SELECT count(*) FROM jsonb_each(COALESCE(h.realized -> 'inbound', '{}')) c WHERE COALESCE((c.value ->> 'arrived')::boolean, false)) AS real_arrived,
         (SELECT count(*) FROM jsonb_each(COALESCE(h.realized -> 'inbound', '{}')) c
           WHERE COALESCE((c.value ->> 'arrived')::boolean, false) AND COALESCE((c.value ->> 'imm')::boolean, false)) AS real_arrived_due,
         (SELECT count(*) FROM jsonb_array_elements(COALESCE(h.realized -> 'appeared', '[]')) c) AS appeared,
         (SELECT count(*) FROM jsonb_array_elements(COALESCE(h.realized -> 'appeared', '[]')) c WHERE COALESCE((c.value ->> 'imm')::boolean, false)) AS appeared_due
    FROM public.ottoq_charge_order_hindsight h JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
   WHERE h.sim_run_id IN ('64251eb8-e5fb-4f7d-af25-9f4ddf5d3768', 'b2efcc07-e47e-40e2-9411-907e913a3976') AND h.observed_min >= h.window_min - 1
)
SELECT left(sim_run_id::text, 8) AS run, count(*) AS orders,
       round(avg(state_due_here), 2) AS due_here_at_order, round(avg(state_due_inbound), 2) AS due_inbound_in_state,
       round(avg(exp_due), 2) AS due_in_expected_future, round(avg(real_due), 2) AS due_in_hindsight,
       round(avg(real_arrived), 2) AS arrived_per_window, round(avg(real_arrived_due), 2) AS arrived_due_per_window,
       round(sum(real_arrived_due + appeared_due)::numeric / NULLIF(sum(real_arrived + appeared), 0), 3) AS due_share_of_arrivals,
       round(1 - sum(exp_due)::numeric / NULLIF(sum(real_due), 0), 3) AS due_unseen_share,
       count(*) FILTER (WHERE outcome = 'missed_win') AS missed_wins,
       count(*) FILTER (WHERE outcome = 'missed_win' AND real_by IN ('on_time', 'lateness')) AS missed_wins_on_due_terms
  FROM g GROUP BY sim_run_id;

-- (4) the forecast arrivals by horizon (0633's spread out of sample on 64251eb8)
WITH ar AS (
  SELECT h.sim_run_id, h.order_id, s.sim_clock AS clock, ib.value AS e, s.state -> 'recall' AS rc,
         (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
         (ib.value ->> 'eta')::float8 AS fc, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip, ib.value ->> 'id' AS vid
    FROM public.ottoq_charge_order_hindsight h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
   WHERE h.sim_run_id IN ('64251eb8-e5fb-4f7d-af25-9f4ddf5d3768', 'b2efcc07-e47e-40e2-9411-907e913a3976') AND ib.value ->> 'src' = 'forecast'
     AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
), g AS (
  SELECT ar.*, public.ottoq_inbound_arrival_z(ar.e, ar.rc, ar.act) AS z, ar.fc - ar.trip AS hz,
         ar.vid || '@' || to_char(date_trunc('minute', ar.clock + make_interval(secs => ar.act * 60) + interval '30 seconds'),
                                  'YYYY-MM-DD HH24:MI') AS ret
    FROM ar
)
SELECT left(sim_run_id::text, 8) AS run,
       CASE WHEN hz <= 0.001 THEN '0 at or past rung' WHEN hz < 10 THEN '1 under 10' WHEN hz < 30 THEN '2 10-30'
            WHEN hz < 60 THEN '3 30-60' ELSE '4 60+' END AS horizon,
       count(*) AS arrivals, count(DISTINCT ret) AS returns, round(avg(act - fc)::numeric, 2) AS bias_min,
       round(avg(abs(act - fc))::numeric, 2) AS mae_min, round(avg((abs(z) <= 1.2816)::int)::numeric, 3) AS in_band,
       count(*) FILTER (WHERE z IS NULL) AS unscored, count(*) FILTER (WHERE z > 3) AS late3, count(*) FILTER (WHERE z < -3) AS early3
  FROM g GROUP BY ROLLUP (1, 2) ORDER BY 1, 2;

-- (5) the charge clock's band and bias by kind (0632 and 0636 out of sample on 64251eb8)
SELECT left(h.sim_run_id::text, 8) AS run, k.key AS kind,
       sum((k.value ->> 'n_z')::int) AS charges_scored,
       round(sum((k.value ->> 'in_band')::numeric) / NULLIF(sum((k.value ->> 'n_z')::numeric), 0), 3) AS in_band_share,
       round(sum((k.value ->> 'sum_z')::numeric) / NULLIF(sum((k.value ->> 'n_z')::numeric), 0), 3) AS mean_z,
       round(sqrt(sum((k.value ->> 'sum_z2')::numeric) / NULLIF(sum((k.value ->> 'n_z')::numeric), 0)), 3) AS rms_z,
       round(exp(sum((k.value ->> 'sum_lr')::numeric) / NULLIF(sum((k.value ->> 'n')::numeric), 0)), 3) AS actual_over_forecast,
       round(sqrt(sum((k.value ->> 'sum_lr2')::numeric) / NULLIF(sum((k.value ->> 'n')::numeric), 0)), 4) AS rms_log_ratio
  FROM public.ottoq_charge_order_grades h
  CROSS JOIN LATERAL jsonb_each(COALESCE(h.forecast -> 'charge_times', '{}'::jsonb)) k
 WHERE h.sim_run_id IN ('64251eb8-e5fb-4f7d-af25-9f4ddf5d3768', 'b2efcc07-e47e-40e2-9411-907e913a3976')
   AND h.observed_min >= h.window_min - 1 AND jsonb_typeof(k.value) = 'object'
 GROUP BY 1, 2 ORDER BY 1, 2;

-- (6) the longest wait each waiting car reached at any order, by battery (the kernel's line, G384)
WITH c AS (
  SELECT s.sim_run_id, x.value ->> 'id' AS id, (x.value ->> 'soc')::numeric AS soc, (x.value ->> 'w')::numeric AS w
    FROM public.ottoq_charge_order_snapshots s CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'cars', '[]')) x
   WHERE s.sim_run_id IN ('64251eb8-e5fb-4f7d-af25-9f4ddf5d3768', 'b2efcc07-e47e-40e2-9411-907e913a3976')
), per AS (
  SELECT sim_run_id, id, min(soc) AS soc, max(w) AS longest_wait_seen FROM c GROUP BY 1, 2
)
SELECT left(sim_run_id::text, 8) AS run,
       CASE WHEN soc < 45 THEN 'under 45' WHEN soc < 80 THEN '45-80' ELSE '80 and over' END AS battery,
       count(*) AS cars, round(avg(longest_wait_seen), 1) AS mean_longest_wait, round(max(longest_wait_seen), 0) AS max_wait,
       count(*) FILTER (WHERE longest_wait_seen > 30) AS over_30, count(*) FILTER (WHERE longest_wait_seen > 60) AS over_60,
       count(*) FILTER (WHERE longest_wait_seen > 90) AS over_90
  FROM per GROUP BY 1, 2 ORDER BY 1, 2;
