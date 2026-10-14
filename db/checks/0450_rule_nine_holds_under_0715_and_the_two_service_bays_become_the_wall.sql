-- 0450  **Rule 9 holds under 0715, and on busy_day's compressed intervals the two service bays become the depot's
--        wall.** A live run on the twin depot, after 0715, against the same world before it: no car left with required
--        work open in either, 0715 put 128 maintenance and calibration jobs on 104 cars that the run before it never
--        required, and departures fell from 208 to 161 because the two service bays cannot clear them. The agent layer
--        ran serially and inside its lease; the certified canon cannot see 0715 at all. -> G439, G440, G441.
--        Run c5f4ff34 started 2026-10-14 16:42:4x UTC and stopped by the governor at 17:50:00 UTC (12:50 PM CT).
--        Measured 2026-10-14, read-only, from 17:52:15 UTC to 17:54:51 UTC (each query's now(), and the shell clock).
--
-- ══ §1 THE PAIR, AND WHAT IT CAN AND CANNOT SAY (reproduce: (1)) ══════════════════════════════════════════════════════
--
--                                   02ac27b3 (before 0715)            c5f4ff34 (after 0715)
--     started by                    ottoq_operator_start_run          the same, with the sim start passed explicitly
--     scenario / seed               busy_day / 305838298283560562     the same
--     sim clock start               2026-10-13 13:00 UTC              the same (so the same world draw: world_day0
--                                                                      arrival 3.232961615 in both payloads)
--     playback                      live 8x from tick 1               live 8x from tick 1 (set in the start's own
--                                                                      transaction, see §6)
--     run dials                     wake gate on, lease 120 s, the    the same, set the same way
--                                   agentic arm's 13 auto dials
--     engine hash                   b576b67a                          9b561d56
--     stopped                       540 sim-minute ceiling, sim       the same ceiling, sim 22:15:31 (the governor runs
--                                   22:07:46, 848 ticks, 65.8 min     every 2 minutes), 779 ticks, 67.2 real min
--
--   Between the two engine hashes: 0715 (forces_recert TRUE), and 0718, 0706 and 0719 (all classified FALSE/FALSE: no
--   certified twin output changes), plus the nightly refits the kernel's seating reads (G387). Live playback ties each
--   tick's sim length to the database's load, so the same seed draws a different world after the first tick (0416):
--   this is two live readings, not a paired measurement. What it can say is where the difference is mechanical and
--   large against that floor (0416's same-seed pair differed by 1.4 points of uptime and 11 minutes of median
--   turnaround); §3's departure and asset-hour drops are 23% and 19%, and §2 shows the mechanism directly.
--
-- ══ §2 0715 DOES WHAT IT SAYS (reproduce: (2)) ═════════════════════════════════════════════════════════════════════
--
--                                                         02ac27b3      c5f4ff34
--     atoms tagged interval_due (0715's own tag)          0             128 on 104 cars
--       mechanical_pm done / pending at the stop          -             14 / 87
--       sensor_calibration done / pending at the stop     -             3 / 24
--     all mechanical_pm atoms, done / pending              11 / 30       15 / 90
--     all sensor_calibration atoms, done / pending          2 / 13        4 / 25
--     departures                                           208           161
--       from a visit (the rest are cars staged at boot)    124           80
--       left with a required atom open                     0             0
--       left after a triage check cleared a need           7             1
--       left from a visit below 99% charge                 0             0
--     scout interval_due_departure                         1             0
--     scout departed_below_target                          0             0
--
--   "Left with a required atom open" counts must_do atoms not done, and does not count an atom cancelled with
--   cleared_by_triage true: a triage check found the need was not there (the cabin did not need a tidy), which is
--   not a service skipped. All 8 such cancellations read that way.
--
-- ══ §3 THE PRICE ON THE TWIN: THE SERVICE BAYS ARE THE WALL (reproduce: (3)) ════════════════════════════════════════
--
--                                                         02ac27b3      c5f4ff34
--     asset hours available (KPI 1)                        206.51        167.57      -18.9%
--     departures                                           208           161         -22.6%
--     cars stranded at the stop with required work open    79            96
--       waiting on mechanical_pm                           21            74
--       waiting on sensor_calibration                      5             18
--       waiting on a charge                                71            66
--       waiting on readiness_check (always last)           79            96
--     must-do completion (service KPI)                     62.2%         58.8%
--     service point turns per point per day (KPI 2)        4.72          4.33
--
--   This is rule 9 reporting a capacity finding, as 0715 §4 said it would. busy_day compresses the maintenance and
--   calibration intervals about a hundredfold (pm_km_scale 0.01, calib_h_scale 0.02 in this run's
--   scenario_overrides), so 104 of 116 cars came due inside nine sim-hours, and two service bays at 40-60 minutes a
--   job finished 17 of the 128. Chase kept the compression on 2026-10-14 ("All services must be completed before
--   vehicle leaves depot"; 0715's header records it), so the wall is the stress test and not a defect: no car left
--   with work owed, and the cars that could not be served waited. What it says about a real depot is nothing yet: a
--   real interval is about 8,000 km, not 78. The research wing's two levers, neither taken here: realistic intervals (a
--   world change, recorded in ottoq_evidence_regimes), or a service-bay count to measure against.
--
-- ══ §4 WHAT DID NOT GET WORSE, AND WHY NOT TO QUOTE IT (reproduce: (3)) ═════════════════════════════════════════════
--
--                                                         02ac27b3      c5f4ff34
--     returns unserved at the horizon                      40            17
--     p95 time to service, min                             321.3         278.2
--     p50 time to service, min                             31.0          81.7
--     charge wait p95 / waiting at the horizon             322.5 / 49    280.1 / 20
--     contract-wait breaches (findings / cars)             137 / 107     118 / 92
--     on-time readiness for cars with a due time           66.7%         67.3%
--     peak site kW / 15-min demand kW                      828.4 / 998.4 804.3 / 954.9
--
--   Fewer cars left, so fewer came back: a smaller flow through the same chargers waits less at the tail. None of
--   these is an improvement 0715 made, and the horizons differ by 7.75 sim-minutes. Quote §2 and §3; quote this table
--   only beside them.
--
-- ══ §5 THE AGENT LAYER (reproduce: (4), (5)) ═══════════════════════════════════════════════════════════════════════
--
--                                                         02ac27b3          c5f4ff34
--     agent version                                       v29, then v30      v30
--     passes / consulted                                   320 / 24          239 / 26
--     consult total, p50 / p90 / max, s                    49.7 / 73.9 / 95.0  70.1 / 97.9 / 101.0
--     model answered (consults)                            ultra 22, super 2  ultra 21, super 4, none 1
--     outcome classes                                      solver_only 296,   solver_only 213, echo 14,
--                                                          echo 17, advisory  advisory 10, fallback 1,
--                                                          6, no_effect 1     no_effect 1
--     directives issued                                    89                 55
--     charge orders graded, all refused by the check       24                 19
--     CP-SAT (forward_lex) enacted / abstained             27 / 756           20 / 578
--     cpsat_service calls, p50 / max ms                    347, 20 / 193      259, 20 / 345
--     tokens                                               652,772            680,013
--
--   Every pass ran inside the 120-second in-flight lease (the longest consult, 101 s). The model's own latency rose:
--   the NVIDIA endpoint took a median 70 s per consult against 50 s the day before. That is the endpoint, not the
--   engine: the tick never waits on the agent (2.5, 0332), and the solver-only passes, which call no model, kept their
--   1.7 s median.
--
--   THREE PASSES "OVERLAP" BY THE EVIDENCE TIMESTAMPS, AND NONE RAN CONCURRENTLY. A pass's start here is its evidence
--   row's recorded_at minus its total_ms. The three pairs touch at the chain boundary by 0.09 s, 0.15 s and 1.12 s.
--   The in-flight lease (ottoq_agent_chain_claim, read 2026-10-14) is released when the previous chain's decision row
--   exists in ottoq_decisions, and the edge function writes that decision before it writes its evidence row; so a new
--   chain can claim between the two writes. Read per pair: the previous decision was written 33 ms and 6.2 s before
--   the next pass started in two of them; in the third the next pass's start is 22 ms before the previous decision,
--   which is the edge function's own start before it called the claim, and its claim could only succeed after that
--   decision existed. One of the three is a consult following a consult (703 -> 704); the other two follow into
--   solver-only passes. Do not quote "3 overlapping agent passes" without this paragraph.
--
-- ══ §6 TICKS AND THE START RACE (reproduce: (6), (7)) ══════════════════════════════════════════════════════════════
--
--                                                         02ac27b3      c5f4ff34
--     ticks / real minutes                                 848 / 65.8    779 / 67.2
--     tick compute p50 / p95 / max, ms                      918 / 1,749 / 7,839   749 / 1,812 / 7,563
--     mean sim advance per tick, s                          38.8          42.8
--
--   0715 adds no visible tick cost: the derive planner it changes runs once per arrival.
--
--   How the first two attempts at this pair went wrong is a finding (G441). ottoq_operator_start_run commits the run
--   with playback 'fixed', and the caller sets live playback in a second call; a tick that lands between the two
--   advances the clock a fixed 30 minutes. 703616ed and 1f325969 (both mine, started by two separate SQL calls)
--   took that 30-minute first step, so their worlds left the baseline's at tick 1, and the sim start defaulted to
--   today's date, which is a different world draw. Measured over the twin depot's runs with a tick log: of 44
--   operator_demo starts, 39 had a live first tick and 5 a fixed one, every one of the 5 a two-step start whose
--   playback came 6 s or more after the start (3bb6c77a, 63cdee1b, 57188f55, 703616ed, 1f325969). The twin app's
--   edge function sets playback within a few hundred milliseconds and has not lost the race in this data; research
--   starts have. Yesterday's 57188f55, one of 0440 §14's "before" runs, is one of them, which 0440 already treated as
--   unpaired. The rule for research runs until the start takes the playback itself: start and set playback in ONE
--   statement, as c5f4ff34 was (reproduce (7) shows the form), and pass the sim start explicitly.
--   OPEN-ITEM: ottoq_operator_start_run does not take the playback mode, so a two-step start races the first tick (G441)
--
--   And a second start-path finding (G440): the first attempt at c5f4ff34's predecessor failed with 40P01 deadlock
--   detected, ottoq_sim_mark_stopped (called by ottoq_sim_stop_and_reset from ottoq_sim_run_scenario, from the
--   operator door) waiting on a row lock in ottoq_sim_runs held by the running tick, which waited on the start. The
--   retry a few seconds later succeeded. To the app this is a "scenario start failed" toast once in a while.
--   OPEN-ITEM: an operator start can deadlock against the running run's tick (40P01) and fail once (G440)
--
-- ══ §7 THE CERTIFIED CANON CANNOT SEE 0715 (reproduce: (8)) ═════════════════════════════════════════════════════════
--
--   The recertification after 0715 (9 of 9 cells, 14:44-15:09 UTC) and the one before it (2026-10-13 20:27-20:52 UTC)
--   ran the same six twin-depot cells. In every arm on both sides: zero atoms tagged interval_due, and the
--   mechanical_pm / sensor_calibration atoms per arm identical before and after (busy_day 171717 at 12/24/48 ticks:
--   3, 3, 5 before and 3, 3, 6 after; the 48-tick arm's one extra is the observer's draw, not 0715's tag). The canon's
--   pairs run without scenario overrides (scenario_overrides absent from their payloads), so the intervals are the
--   need profile's 6,500-9,500 km and 181-319 h, and 24 sim-hours never reach one. So the certified, byte-identical
--   verdict covers a departure branch it never exercises: a regression that let a due car leave would pass every
--   canon cell. The canon's other metrics moved between the two days (tasks completed 590 -> 605 on the 48-tick cell),
--   and that is the nightly refits (G387), not 0715: no 0715 tag fired.
--   OPEN-ITEM: no canon cell exercises the maintenance and calibration departure branch 0715 built (G439)
--
-- ══ QUERIES ══

-- (1) the pair's identity
SELECT sim_run_id, status, started_at, ended_at, sim_clock_start, sim_clock_current, tick_count, random_seed,
       payload ->> 'playback_mode' AS mode, payload ->> 'speed_x' AS speed,
       payload -> 'boot_draw' -> 'world_day0' ->> 'arrival' AS world_arrival, failure_reason
  FROM public.ottoq_sim_runs
 WHERE sim_run_id IN ('02ac27b3-fe50-42b1-bf1b-82ac2a50445f', 'c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd');

-- (2) 0715's tags and the departures (one run at a time)
WITH r(id) AS (VALUES ('c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd'::uuid)),
atoms AS (SELECT vn.visit_id, vn.vehicle_id, a FROM public.ottoq_visit_needs vn,
            jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a WHERE vn.sim_run_id = (SELECT id FROM r)),
d AS (SELECT dispatch_id, vehicle_id, dispatched_at, soc_at_dispatch_pct FROM public.ottoq_vehicle_dispatches
       WHERE sim_run_id = (SELECT id FROM r)),
dv AS (SELECT d.*, v.atoms FROM d LEFT JOIN LATERAL (
         SELECT vn.atoms FROM public.ottoq_visit_needs vn WHERE vn.sim_run_id = (SELECT id FROM r)
            AND vn.vehicle_id = d.vehicle_id AND vn.arrived_at <= d.dispatched_at ORDER BY vn.arrived_at DESC LIMIT 1) v ON true)
SELECT (SELECT count(*) FROM atoms WHERE a ? 'interval_due') AS tagged,
       (SELECT count(DISTINCT vehicle_id) FROM atoms WHERE a ? 'interval_due') AS tagged_cars,
       (SELECT jsonb_object_agg(k, n) FROM (SELECT a ->> 'svc' || ':' || COALESCE(a ->> 'status', 'pending') k, count(*) n
          FROM atoms WHERE a ? 'interval_due' GROUP BY 1) x) AS tagged_by_status,
       count(*) AS departures, count(*) FILTER (WHERE dv.atoms IS NOT NULL) AS from_a_visit,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(dv.atoms, '[]'::jsonb)) a
          WHERE COALESCE(a ->> 'must_do', 'false') = 'true' AND COALESCE(a ->> 'status', 'pending') <> 'done'
            AND NOT (a ->> 'status' = 'cancelled' AND COALESCE(a ->> 'cleared_by_triage', 'false') = 'true'))) AS left_with_required_open,
       count(*) FILTER (WHERE dv.atoms IS NOT NULL AND dv.soc_at_dispatch_pct < 99) AS from_a_visit_below_99
  FROM dv;

-- (3) the KPIs (one run at a time) and what stranded cars waited on
SELECT public.ottoq_kpi_five('c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd') - 'provenance' AS five,
       public.ottoq_kpi_service_completion('c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd') AS service,
       public.ottoq_kpi_charge_wait('c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd') AS charge_wait,
       public.ottoq_kpi_dispatch_readiness('c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd') AS readiness;
SELECT f.sim_run_id, x.svc, count(*) AS cars
  FROM public.ottoq_vehicle_scout_findings f CROSS JOIN LATERAL jsonb_array_elements_text(f.detail -> 'open_must_do') x(svc)
 WHERE f.scout = 'stranded_open_must_do'
   AND f.sim_run_id IN ('02ac27b3-fe50-42b1-bf1b-82ac2a50445f', 'c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd')
 GROUP BY 1, 2 ORDER BY 1, 3 DESC;

-- (4) the agent layer (one run at a time)
WITH r(id) AS (VALUES ('c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd'::uuid)),
e AS (SELECT * FROM public.ottoq_agent_pass_evidence WHERE sim_run_id = (SELECT id FROM r))
SELECT count(*) AS passes, count(*) FILTER (WHERE consulted) AS consulted,
       percentile_cont(ARRAY[0.5, 0.9, 1.0]) WITHIN GROUP (ORDER BY total_ms) FILTER (WHERE consulted) AS consult_ms,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY total_ms) FILTER (WHERE NOT consulted) AS solver_only_p50_ms,
       sum((usage ->> 'total_tokens')::numeric) AS tokens,
       sum(COALESCE((levers ->> 'directives_issued')::int, 0)) AS directives,
       (SELECT jsonb_object_agg(coalesce(outcome_class, 'null'), n) FROM (SELECT outcome_class, count(*) n FROM e GROUP BY 1) x) AS classes,
       (SELECT jsonb_object_agg(source || ':' || status, n) FROM (SELECT source, status, count(*) n
          FROM public.ottoq_external_proposals WHERE sim_run_id = (SELECT id FROM r) GROUP BY 1, 2) x) AS proposals,
       (SELECT jsonb_object_agg(provider, n) FROM (SELECT provider, count(*) n
          FROM public.ottoq_model_call_ledger WHERE sim_run_id = (SELECT id FROM r) GROUP BY 1) x) AS ledger
  FROM e;

-- (5) the "overlaps", and the decision that released each lease
WITH e AS (SELECT pass_id, consulted, outcome_class, trigger_tick, recorded_at,
                  recorded_at - make_interval(secs => total_ms / 1000.0) AS t0
             FROM public.ottoq_agent_pass_evidence WHERE sim_run_id = 'c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd')
SELECT a.pass_id, a.t0, b.pass_id AS prev_pass, b.recorded_at AS prev_evidence_at, b.trigger_tick AS prev_trigger,
       (SELECT max(d.created_at) FROM public.ottoq_decisions d
         WHERE d.sim_run_id = 'c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd' AND d.resolved_action_context = 'orchestrator_agent'
           AND COALESCE(CASE WHEN COALESCE(d.context_frame ->> 'agent_chain_trigger_tick', '') ~ '^[0-9]+$'
                             THEN (d.context_frame ->> 'agent_chain_trigger_tick')::bigint END, d.tick_seq) = b.trigger_tick) AS prev_decision_at
  FROM e a JOIN e b ON b.pass_id <> a.pass_id AND b.t0 < a.t0 AND b.recorded_at > a.t0
 ORDER BY a.t0;

-- (6) tick timing (one run at a time)
SELECT count(*) AS ticks, percentile_cont(ARRAY[0.5, 0.95]) WITHIN GROUP (ORDER BY tick_compute_ms) AS p50_p95_ms,
       max(tick_compute_ms) AS max_ms, round(avg(sim_advance_s), 1) AS mean_advance_s,
       round(extract(epoch FROM max(real_ended_at) - min(real_started_at)) / 60, 1) AS real_min
  FROM public.ottoq_tick_clock_log WHERE sim_run_id = 'c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd';

-- (7) the start race: first-tick playback mode by who started the run (twin depot), and the one-statement start
SELECT r.run_by, l.playback_mode AS first_tick_mode, count(*) AS runs
  FROM public.ottoq_tick_clock_log l JOIN public.ottoq_sim_runs r USING (sim_run_id)
 WHERE l.tick_seq = 1 AND r.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- The research form (not run by this file; it starts a run):
--   WITH s AS (SELECT public.ottoq_operator_start_run('busy_day', <seed>::bigint, 'operator_demo', '<sim start>'::timestamptz) r)
--   SELECT public.ottoq_set_playback((r ->> 'sim_run_id')::uuid, 'live', 8), ... FROM s;

-- (8) the canon arms before and after 0715: interval_due tags and maintenance/calibration atoms
WITH arms AS (SELECT arm_a_run AS r, scenario, seed, ticks, certified_at > '2026-10-14 14:43:27+00' AS post
                FROM public.ottoq_determinism_verdict_ledger
               WHERE certified_at > '2026-10-13 20:20+00' AND depot_id = '11111111-1111-1111-1111-111111111111')
SELECT arms.scenario, arms.seed, arms.ticks, arms.post,
       (SELECT count(*) FROM public.ottoq_visit_needs vn, jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
         WHERE vn.sim_run_id = arms.r AND a ? 'interval_due') AS tagged,
       (SELECT count(*) FROM public.ottoq_visit_needs vn, jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
         WHERE vn.sim_run_id = arms.r AND a ->> 'svc' IN ('mechanical_pm', 'sensor_calibration')) AS pm_calib_atoms,
       (SELECT payload ? 'scenario_overrides' FROM public.ottoq_sim_runs s WHERE s.sim_run_id = arms.r) AS has_overrides
  FROM arms ORDER BY 1, 2, 3, 4;
