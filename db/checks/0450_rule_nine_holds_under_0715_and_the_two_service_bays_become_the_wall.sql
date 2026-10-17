-- 0450  **Rule 9 holds under 0715, and on busy_day's compressed intervals the two service bays become the depot's
--        wall.** A live run on the twin depot after 0715, against a run on the same boot draw before it: no car that left
--        from a visit left with required work open, in either; 0715 required 82 maintenance and calibration jobs (on 73
--        cars) that the run before it never required, and departures during the run fell from 162 to 115 because the two
--        service bays cannot clear them. The agent layer held its lease; the certified canon cannot see 0715 at all.
--        -> G439, G440, G441; G430 updated.
--        Run c5f4ff34 started 2026-10-14 16:42:4x UTC and stopped by the governor at 17:50:00 UTC (12:50 PM CT).
--        Measured 2026-10-14, read-only, from 17:52:15 UTC to 17:54:51 UTC (each query's now(), and the shell clock).
--        CORRECTED the same day, 19:34:50 UTC (2:34 PM CT), after two independent refuters re-derived every number from
--        live with their own queries (96 claims; 43 confirmed as written). What changed is said where it changed, marked
--        "(corrected)": the new-work count (128 tagged, 82 new), the departures (46 pre-start rows in both totals), the
--        stranded-at-the-stop table (it had read the 4-hour scout instead of the stop), the calibration compression
--        (fiftyfold), the canon's cell count (seven) and its one unmentioned change, the CP-SAT abstentions, the
--        endpoint's own latency, the overlap estimate, the charge-order grades, the start-race census, and a second
--        deadlock.
--        ADDED the same day, §8 and (9): §5's 7.35-second decision insert is a foreign-key wait on the tick's FOR UPDATE
--        of the live run's row -> G490 (measured, and NOT changed: the wait keeps the decide step's close of the
--        proposals right), and the deadlock of §6 is traced to the stop door's order -> G440, built in db/migrations/0790
--        (pending).
--
-- ══ §1 THE PAIR, AND WHAT IT CAN AND CANNOT SAY (reproduce: (1)) ══════════════════════════════════════════════════════
--
--                                   02ac27b3 (before 0715)            c5f4ff34 (after 0715)
--     started by                    ottoq_operator_start_run          the same, with the sim start passed explicitly
--     scenario / seed               busy_day / 305838298283560562     the same
--     sim clock start               2026-10-13 13:00 UTC              the same, so the same boot draw (world_day0
--                                                                      arrival 3.232961615, prime fingerprint 0796b7cd)
--     playback                      live 8x from tick 1               live 8x from tick 1 (set in the start's own
--                                                                      transaction, see §6)
--     run dials                     wake gate on, lease 120 s, the    the same, set the same way
--                                   agentic arm's auto dials
--     engine                        started on fcd3faf0 (through      9b561d56 throughout
--                                   0562); 0707, 0708 and 0717 landed
--                                   mid-run (19:35, 19:52, 20:11 UTC);
--                                   archived as b576b67a
--     stopped                       540 sim-minute ceiling, sim       the same ceiling, sim 22:15:31 (the governor runs
--                                   22:07:46, 848 ticks, 65.8 min     every 2 minutes), 779 ticks, 67.2 real min
--
--   Between b576b67a and 9b561d56: 0715 (forces_recert TRUE), and 0718, 0706 and 0719 (all classified FALSE/FALSE), plus
--   the nightly refits the kernel's seating reads (G387). And the baseline itself ran on three engines (corrected: its
--   archived hash is stamped at archive time). Live playback ties each tick's sim length to the database's load, so the
--   worlds part at tick 1 itself (tick 1 advanced 284.4 s on 02ac27b3 and 64.1 s on c5f4ff34; corrected): only the boot
--   draw is shared. This is two live readings, not a paired measurement. What it can say is where the difference is
--   mechanical and large against that floor (0416's same-seed pair differed by 1.4 points of uptime and 11 minutes of
--   median turnaround): §3's drops are 29% and 19%, and §2 shows the mechanism directly.
--
-- ══ §2 0715 DOES WHAT IT SAYS (reproduce: (2)) ═════════════════════════════════════════════════════════════════════
--
--                                                         02ac27b3      c5f4ff34
--     atoms tagged interval_due (0715's own tag)          0             128 on 104 cars
--       of which (car, service) pairs the run before       -             82 on 73 cars (corrected: 46 of the 128,
--         did NOT require                                                on 44 cars, the baseline also required)
--       mechanical_pm done / pending at the stop          -             14 / 87
--       sensor_calibration done / pending at the stop     -             3 / 24
--     all mechanical_pm atoms, done / pending              11 / 30       15 / 90
--     all sensor_calibration atoms, done / pending          2 / 13        4 / 25
--     departures during the run (corrected)                162           115
--       from a visit                                       124           80
--       of cars staged at boot (no visit to read)          38            35
--       left from a visit with a required atom open        0             0
--       left from a visit after a triage check cleared a need 7          1
--       left from a visit below 99% charge                 0             0
--     the 46 pre-start rows in both runs' dispatch ledger  46            46   identical in car, time and SoC: cars out at
--                                                                            work when the run began, not departures
--     scout interval_due_departure                         1             0
--     scout departed_below_target                          0             0
--
--   "Required atom open" counts must_do atoms not done, and does not count an atom cancelled with cleared_by_triage
--   true: a triage check found the need was not there (the cabin did not need a tidy), which is not a service skipped.
--   All 8 such cancellations read that way.
--   What this does NOT cover (corrected): the 38 / 35 departures of cars staged at boot have no visit to read, and 0715
--   does not test wear at departure (ottoq_departure_clear reads atoms only). Indirectly none was due when it left: none
--   of the 29 boot visits at 13:00 carries a tag and wear accrues only while driving; but 29 of the test's 35 came back
--   with an interval_due job on their next visit. "No car left with required work open" is measured for departures
--   from a visit.
--
-- ══ §3 THE PRICE ON THE TWIN: THE SERVICE BAYS ARE THE WALL (reproduce: (3)) ════════════════════════════════════════
--
--                                                         02ac27b3      c5f4ff34
--     asset hours available (KPI 1)                        206.51        167.57      -18.9%
--     departures during the run                            162           115         -29.0%  (corrected)
--     cars at the stop with required work open             98            111         (corrected: visits closed
--       waiting on mechanical_pm                           30            90          run_completed, read at the stop;
--       waiting on sensor_calibration                      13            25          the first draft read the 4-hour
--       waiting on a charge                                87            57          scout's frozen lists)
--       waiting on readiness_check (always last)           98            111
--     must-do completion (service KPI)                     62.2%         58.8%
--     service point turns per point per day (KPI 2)        4.72          4.33
--
--   This is rule 9 reporting a capacity finding, as 0715 §4 said it would. busy_day compresses the maintenance interval
--   about a hundredfold and calibration about fiftyfold (pm_km_scale 0.01, calib_h_scale 0.02 in this run's
--   scenario_overrides; corrected), so 104 of 116 cars came due inside nine sim-hours, and two service bays at 40-60
--   minutes a job finished 17 of the 128 tagged jobs. The compression is kept by default (0715 §4); keeping it or
--   moving busy_day to realistic intervals is still Chase's call (G430; corrected: his sentence of the morning is about
--   completing services, not about the compression). Under it no car left from a visit with work owed, and the cars
--   that could not be served waited. What it says about a real depot is nothing yet: a real maintenance interval is
--   about 8,000 km, not 78. The research wing's two levers, neither taken here: realistic intervals (a world change,
--   recorded in ottoq_evidence_regimes), or a service-bay count to measure against.
--
-- ══ §4 THE REST OF THE KPIS: MIXED, AND NOT TO BE QUOTED ALONE (reproduce: (3)) ═════════════════════════════════════
--
--                                                         02ac27b3      c5f4ff34
--     returns unserved at the horizon                      40            17          better
--     p95 time to service, min                             321.3         278.2       better
--     p50 time to service, min                             31.0          81.7        worse, 2.6x
--     charge wait p50 / p95, min                           69.4 / 322.5  89.3 / 280.1  p50 worse, p95 better
--     waiting for a charge at the horizon                  49            20
--     touch events per turn                                0.607         0.74        worse
--     contract-wait breaches (findings / cars)             137 / 107     118 / 92
--     on-time readiness for cars with a due time           66.7%         67.3%
--     peak site kW / 15-min demand kW                      828.4 / 998.4 804.3 / 954.9
--
--   (Corrected: the first draft titled this table "what did not get worse" while a row in it got 2.6x worse, and left
--   out the charge-wait p50 and touch events.) Fewer cars left, so fewer came back: a smaller flow through the same
--   chargers waits less at the tail and more in the middle. None of these is an effect 0715 was built to have, and the
--   horizons differ by 7.75 sim-minutes. Quote §2 and §3; quote this table only beside them.
--
-- ══ §5 THE AGENT LAYER (reproduce: (4), (5)) ═══════════════════════════════════════════════════════════════════════
--
--                                                         02ac27b3          c5f4ff34
--     agent version                                       v29, then v30      v30
--     passes / consulted                                   320 / 24          239 / 26
--     consult, whole pass, p50 / p90 / max, s              49.7 / 73.9 / 95.0  70.1 / 97.9 / 101.0
--     the endpoint's own time (propose_ms), p50, s         38.6              58.3   (corrected)
--     consults with a failed model attempt                 3 of 24           9 of 26 (5 ultra timeouts near 75 s,
--                                                                             1 super timeout; the day before, 1)
--     model answered (consults)                            ultra 22, super 2  ultra 21, super 4, none 1
--     outcome classes                                      solver_only 296,   solver_only 213, echo 14,
--                                                          echo 17, advisory  advisory 10, fallback 1,
--                                                          6, no_effect 1     no_effect 1
--     directives issued                                    89                 55
--     agent charge orders recorded / graded                24 / 24            21 / 19 (906 and 907 never graded)
--       the agent's order was the kernel's own             17                 12
--       refused by the check (not enough futures won /     7 (4 / 3)          7 (3 / 4)
--         worse in the expected future)
--     CP-SAT (forward_lex) enacted / abstained / refused   27 / 756 / 8       20 / 569 / 9   (corrected: the first
--       for cause (stall reserved or occupied)                                draft compared 756 abstentions with
--                                                                             578 refusals of all kinds)
--     cpsat_service calls, p50 / max ms                    347, 20 / 193      259, 20 / 345
--     solver-only pass, p50, s                              1.58              1.67
--     tokens                                               652,772            680,013
--
--   Every pass ran inside the 120-second in-flight lease (the longest consult, 101 s). The model's own latency rose: the
--   endpoint's median went from 38.6 s to 58.3 s per consult, with six timeouts against one; the rest of a consulted
--   pass, about 11 s, did not change (corrected: the first draft quoted whole-pass time as the endpoint's). That is
--   the endpoint, not the engine: the tick never waits on the agent (2.5, 0332).
--
--   THE THREE "OVERLAPS" ARE AT CHAIN BOUNDARIES: NO TWO PASSES HELD THE LEASE AT ONCE, BUT THEIR FUNCTIONS DID OVERLAP
--   (corrected). The in-flight lease (ottoq_agent_chain_claim, read 2026-10-14) is released when the previous chain's
--   decision row exists in ottoq_decisions, or after its timeout (120 s here); the edge function then still writes a
--   prompt upsert and its evidence row. A pass's start estimated from its own decision row (decision created_at minus
--   total_ms, which total_ms precedes) puts the three boundary overlaps at no less than 0.205 s, 0.186 s and 1.186 s,
--   and in two of them (703 -> 704, 748 -> 749) the next function started before the previous decision insert began;
--   its claim, which comes after its wake check, could only succeed once that decision had committed. For 797 -> 798,
--   798 started during 797's 7.35-second decision insert. So claims and decisions are serial; the functions' first and
--   last moments are not. One of the three is a consult after a consult. And a 7.35-second decision insert on a
--   solver-only pass is its own question (solver-only decision inserts: p90 2.15 s on the baseline, 4.06 s here, 42 of
--   213 over a second).
--
-- ══ §6 TICKS, THE START RACE, AND A DEADLOCK (reproduce: (6), (7)) ═════════════════════════════════════════════════
--
--                                                         02ac27b3      c5f4ff34
--     ticks / real minutes                                 848 / 65.8    779 / 67.2
--     tick compute p50 / p95 / max, ms                      918 / 1,749 / 7,839   749 / 1,812 / 7,563
--     mean sim advance per tick, s                          38.8          42.8
--
--   0715 adds no visible tick cost: the derive planner it changes runs once per arrival.
--
--   The start race (G441). ottoq_operator_start_run commits the run with playback 'fixed', and the caller sets live
--   playback in a second call; a tick that lands between the two advances the clock a fixed 30 minutes. Over the twin
--   depot's runs with a tick log, 44 operator_demo starts: 39 had a live first tick and 5 a fixed one (corrected
--   breakdown): three two-step starts whose playback arrived after the first tick, which ran 6.1-7.6 s after the start,
--   and went live from tick 2 (3bb6c77a, 57188f55, 1f325969); and two starts that never set playback at all and ran
--   fixed throughout (63cdee1b, stopped 'restart_live_playback'; 703616ed, mine, whose sim start also defaulted to
--   today's date, a different boot draw). 1f325969 (mine) had the baseline's boot draw and differed only in its fixed
--   first tick. Yesterday's 57188f55, one of 0440 §14's "before" runs, is one of the three, which 0440 already treated as
--   unpaired. The twin app's edge function (otto-twin-control) makes the same two calls; set_playback records no
--   timestamp and run_by is 'operator_demo' for app and research starts alike, so this census cannot say whether the
--   app has lost the race (corrected: the first draft said it had not). The rule for research runs until the start takes
--   the playback itself: start and set playback in ONE statement, as c5f4ff34 was (reproduce (7) shows the form), and
--   pass the sim start explicitly.
--   OPEN-ITEM: ottoq_operator_start_run does not take the playback mode, so a two-step start races the first tick (G441)
--
--   The deadlock (G440), twice in three minutes, from the database's own log (read by a refuter): at 16:40:04.205 UTC
--   the operator start (ottoq_operator_start_run -> ottoq_sim_run_scenario -> ottoq_sim_stop_and_reset ->
--   ottoq_sim_mark_stopped, an UPDATE of the live run's ottoq_sim_runs row) and the metronome (CALL
--   ottoq_demo_metronome(50)) each waited on the other, and the start was the victim ("scenario start failed"; the retry
--   succeeded); at 16:42:42.981, at c5f4ff34's own one-statement start, the same cycle made the metronome's decide the
--   victim ("metronome decide 1f325969 failed: deadlock detected"). So it is a recurring cycle between the operator door
--   and the metronome, not a one-off, and either side can lose.
--   OPEN-ITEM: an operator start and the metronome deadlock on the live run's row (40P01); either side can fail (G440)
--
-- ══ §7 THE CERTIFIED CANON CANNOT SEE 0715 (reproduce: (8)) ═════════════════════════════════════════════════════════
--
--   The recertification after 0715 (9 of 9 cells, 14:44-15:09 UTC) and the one before it (2026-10-13 20:27-20:52 UTC)
--   ran the same seven twin-depot cells (corrected: busy_day 171717 / 314159 / 424242 at 12 ticks, 171717 and 424242 at
--   24, 171717 at 48, and normal_day 171717 at 12; the other two of the nine are grid_smoke on fixture depot aacd0bb0).
--   In every arm on both sides: zero atoms tagged interval_due. Maintenance and calibration atoms per cell were the same
--   in five cells (3, 3, 1, 5, 5) and changed in two: busy_day 171717/48 went 5 -> 6 and normal_day 171717/12 went 4 -> 3
--   (one calibration atom gone; corrected), both observer draws, not 0715's tag. The canon's pairs run without scenario
--   overrides (scenario_overrides absent from their payloads), so the intervals are the need profile's 6,500-9,500 km
--   and 181-319 h, and 24 sim-hours never reach one. So the certified, byte-identical verdict covers a departure branch
--   it never exercises: a regression that let a due car leave would pass every canon cell. The canon's other metrics
--   moved between the two days (tasks completed 590 -> 605 on the 48-tick cell). That is not 0715's tag path (no tag
--   fired); 0718, 0706, 0719 and the nightly refits (G387) all sit between, and which of them moved it is not measured
--   here (corrected: the first draft named the refits as the cause).
--   OPEN-ITEM: no canon cell exercises the maintenance and calibration departure branch 0715 built (G439)
--
-- ══ §8 THE 7.35-SECOND DECISION INSERT IS A FOREIGN-KEY WAIT ON THE TICK'S ROW LOCK (reproduce: (9)) ═════════════════
--
--   Added the same day, read-only, from the reads behind db/migrations/0790 §1 (b); (9) re-read at 20:34:50 UTC
--   (3:34 PM CT) and again, unchanged, at 23:09:23 UTC (6:09 PM CT). §5's open question has a mechanism. ottoq_decisions references ottoq_sim_runs; the world step took the
--   live run's row FOR UPDATE, the one row lock a foreign-key check (FOR KEY SHARE) waits on; and the metronome commits a
--   beat after its world and decide steps. So an agent decision insert begun during a beat waited for the beat's commit.
--   On c5f4ff34, the time from each decision's created_at to its pass's evidence row (an upper bound on the insert),
--   split by when the insert began:
--     inside a world step (ottoq_tick_clock_log)                    36   mean 4.14 s, p50 4.26, p90 6.16, max 8.13
--     in the 5 s after a decide beat's world step ended              27   mean 1.76 s, 12 over a second, max 7.345
--     the other 176                                                       mean 0.07 s, max 0.57, none over a second
--   The world step's logged end came a mean 0.48 s after the 36 began, so they waited for the commit, not the world step.
--   Pass 797's 7.345 s (trigger tick 359) began 0.78 s after tick 364's world step ended, inside that beat's decide step.
--   The beat's commit is not logged, so the second row's 5-second window is a bound, not a measurement. -> G490.
--   The wait is not removed by 0790: its first draft took the tick's lock FOR NO KEY UPDATE, and two refuters showed that
--   lets a proposal commit mid-beat, after which ottoq_decide_tick's A3 (line 1228) records the wrong proposal as enacted
--   in the evidence ledger (0790 §1 (b)). The fix needs one lock order for proposal writers or A3 scoped to the proposal
--   the kernel took, and an audit of the beat's set-based statements, first.
--   OPEN-ITEM: an insert that references the live run waits for the tick's FOR UPDATE on its row; the fix is gated on A3 (G490)
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
       WHERE sim_run_id = (SELECT id FROM r)   -- departures DURING the run: the 46 pre-start rows are cars already out
         AND dispatched_at >= (SELECT sim_clock_start FROM public.ottoq_sim_runs WHERE sim_run_id = (SELECT id FROM r))),
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
-- cars with required work open AT THE STOP (visits the run's end closed), by what they waited on
WITH v AS (SELECT * FROM public.ottoq_visit_needs
            WHERE sim_run_id IN ('02ac27b3-fe50-42b1-bf1b-82ac2a50445f', 'c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd')
              AND meta ->> 'close_reason' = 'run_completed'),
o AS (SELECT v.sim_run_id, v.vehicle_id, a ->> 'svc' AS svc FROM v, jsonb_array_elements(v.atoms) a
       WHERE COALESCE(a ->> 'must_do', 'false') = 'true' AND COALESCE(a ->> 'status', 'pending') <> 'done'
         AND NOT (a ->> 'status' = 'cancelled' AND COALESCE(a ->> 'cleared_by_triage', 'false') = 'true'))
SELECT sim_run_id, count(DISTINCT vehicle_id) AS cars_open,
       count(DISTINCT vehicle_id) FILTER (WHERE svc = 'mechanical_pm') AS pm,
       count(DISTINCT vehicle_id) FILTER (WHERE svc = 'sensor_calibration') AS calibration,
       count(DISTINCT vehicle_id) FILTER (WHERE svc = 'charge') AS charge,
       count(DISTINCT vehicle_id) FILTER (WHERE svc = 'readiness_check') AS readiness
  FROM o GROUP BY 1;
-- and the (car, service) pairs 0715 tagged that the run before it did not require
WITH b AS (SELECT DISTINCT vn.vehicle_id, a ->> 'svc' AS svc FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
            WHERE vn.sim_run_id = '02ac27b3-fe50-42b1-bf1b-82ac2a50445f' AND a ->> 'svc' IN ('mechanical_pm', 'sensor_calibration')
              AND a ->> 'must_do' = 'true'),
t AS (SELECT vn.vehicle_id, a ->> 'svc' AS svc FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
       WHERE vn.sim_run_id = 'c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd' AND a ? 'interval_due')
SELECT count(*) AS tagged, count(*) FILTER (WHERE (t.vehicle_id, t.svc) NOT IN (SELECT vehicle_id, svc FROM b)) AS new_pairs,
       count(DISTINCT t.vehicle_id) FILTER (WHERE (t.vehicle_id, t.svc) NOT IN (SELECT vehicle_id, svc FROM b)) AS new_pair_cars
  FROM t;

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

-- (9) the agent's decision inserts by when they began, and how long until their pass's evidence row (one run)
WITH r(id) AS (VALUES ('c5f4ff34-b7c2-446b-a8c5-13fbdd5cd9cd'::uuid)),
d AS (SELECT d.created_at,
             COALESCE(CASE WHEN COALESCE(d.context_frame ->> 'agent_chain_trigger_tick', '') ~ '^[0-9]+$'
                           THEN (d.context_frame ->> 'agent_chain_trigger_tick')::bigint END, d.tick_seq) AS trig
        FROM public.ottoq_decisions d
       WHERE d.sim_run_id = (SELECT id FROM r) AND d.resolved_action_context = 'orchestrator_agent'),
e AS (SELECT trigger_tick, recorded_at FROM public.ottoq_agent_pass_evidence WHERE sim_run_id = (SELECT id FROM r)),
j AS (SELECT d.created_at, extract(epoch FROM e.recorded_at - d.created_at) AS gap_s,
             (SELECT l FROM public.ottoq_tick_clock_log l WHERE l.sim_run_id = (SELECT id FROM r)
                 AND l.real_started_at <= d.created_at ORDER BY l.real_started_at DESC LIMIT 1) AS prev
        FROM d JOIN e ON e.trigger_tick = d.trig)
SELECT CASE WHEN created_at < (prev).real_ended_at THEN 'a inside a world step'
            WHEN created_at < (prev).real_ended_at + interval '5 s' AND (prev).tick_seq % 2 = 0
              THEN 'b within 5 s after a decide beat''s world step'
            ELSE 'c the rest' END AS began,
       count(*) AS n, round(avg(gap_s)::numeric, 2) AS mean_s,
       round(percentile_cont(0.9) WITHIN GROUP (ORDER BY gap_s)::numeric, 2) AS p90_s, round(max(gap_s)::numeric, 3) AS max_s,
       count(*) FILTER (WHERE gap_s > 1) AS over_1s
  FROM j GROUP BY 1 ORDER BY 1;
