-- 0459  **Overnight testing is stopped, and seven of the switches built since 2026-10-17 are on at the twin depot, so its
--        demo now runs them: the fast chargers' cleaning arm cleaned its first live car at sim 8:47 AM CT.** -> G478.
--        Chase, 2026-10-20, after seeing no cleaning arm and no doors in his 3:09 PM CT demo: "Stop overnight testing. We
--        are still building. No need to certify and test until everything is finished and we are not there. Go and build
--        and implement!" Writes and reads against gxdrcyphqjzjsuhxuqtg on 2026-10-20 between 3:46 and 4:16 PM CT (20:46:57
--        UTC, the first query's clock, to 21:16:42 UTC, the last's). No migration was applied; every write is named below
--        with the statement that undoes it.
--
-- ══ §1 WHY THE DEMO SHOWED NONE OF IT (reproduce: (1), (2)) ════════════════════════════════════════════════════════════
--
--   The published app had the code: its live build (otto-twin.lovable.app, main-DihDiuro.js and its chunks, fetched
--   2026-10-20 3:47 PM CT) carries the Q card's interior-clean words, the error boundary and the cleaning arm's keys from
--   ottoyarddepot-sim PR #146. What it draws comes from the engine, and the engine had every new switch off at the twin
--   depot. (1): Chase's run 0cdbfc72 (busy_day, 3:09-3:14 PM CT, 49 ticks) read all 17 switches added by 0726-0758 as
--   off; no row set any of them at depot or global scope. (2): its 16 interior tidies went to no arm (0 with
--   performed_by stall_cabin_robot), so the renderer, which moves an arm and opens a car's doors only while the snapshot
--   names an arm at work on that stall, had nothing to play. Every switch had been turned on only inside the research
--   wing's sweep cells (fixed_params), never for the demo.
--
-- ══ §2 OVERNIGHT TESTING STOPPED (3:59 PM CT; reproduce: (3)) ════════════════════════════════════════════════════════
--
--   SELECT cron.alter_job(784, active := false)   -- ottoq_sweep_window_open: opened the sweep window at 11 PM CT nightly
--   SELECT cron.alter_job(746, active := false)   -- ottoq-recert-runner: ran determinism pairs whenever no run was live
--   SELECT cron.alter_job(763, active := false)   -- the dial window's 2026-09-28 opener, which would fire every 28 Sep
--   Undo each with active := true. The runners (783 sweeps, 755 dial experiments) stay scheduled and idle: their windows'
--   dials are 0 (785 closed the sweep window at 6:00 AM CT, 762 the dial window at 5:41 AM CT) and nothing now opens them.
--   The 32 sweeps and 8 dial experiments keep status 'active' in their tables: pausing them is an UPDATE, held by the
--   Supabase connector for Chase's confirmation, and 0759's P0 reads those rows.
--
-- ══ §3 SEVEN SWITCHES ON (4:02 PM CT; reproduce: (4)) ══════════════════════════════════════════════════════════════
--
--   public.ottoq_policy_set('depot', '11111111-1111-1111-1111-111111111111', <key>, 1, 'Chase'), every result ok, each a
--   person's change made on Chase's instruction above. The evidence is the research wing's arms on seed
--   686364201590009433 (normal day, the twin answering in the tick), read 2026-10-20 between 4:00 and 4:01 PM CT; every
--   arm named here left 0 cars below target and 0 with needed work open.
--     twin_answer_in_tick           0735, G450: the twin carries out a command in the tick it is given; every research
--                                    cell had moved onto it (removing the lag bought 10 and 20 posts 10.7 and 29.2
--                                    car-hours, 0451 §12).
--     bay_activation_per_seat       0743, G457: each bay seat is its own; arm 118 served 210 visits against arm 95's 205.
--     bay_hold_follows_charge       0744, G458: a bay hold follows a charge that runs past its plan; arm 119 204 against 205.
--     bay_exit_closes_its_leg       0750, G464: every bay seat ends in its leg and service record; arm 122 matched arm 95
--                                    on every throughput figure, as bookkeeping should.
--     repair_needs_its_green_light  0753, G467: a repaired car waits for its technician's green-light at every door (in
--                                    the twin its technician answers 15-60 minutes after the repair, 92% approve); rule 9.
--     bay_release_reads_the_work    0757, G474: a bay seat that finished early is done (VERIFIED on six arms).
--     stall_cabin_robot             0758, G476: the fast charger's cleaning arm cleans the cabin during the charge.
--   Undo any one with ottoq_policy_set(..., 0, '<a person>').
--
-- ══ §4 HELD OFF, AND WHY ════════════════════════════════════════════════════════════════════════════════════════════
--
--     itinerary_charge_on_clock     0745, G459: at the depot as built (10 posts) arm 121 served 142 visits against arm
--                                    93's 159 and left 55 cars in the depot against 49. One arm, but too large to switch on
--                                    unread.
--     bay_order_uptime_first        0747, G461: on the busy day 11 fewer cars served and a PM's arrival-to-done median
--                                    165 -> 403 minutes (0452 §7).
--     ready_promise_record, ready_promise_refresh_min   0736/0742: research instrumentation; nothing an owner sees reads it.
--     dc_power_sharing, dc_power_managed, dc_power_first_reading, dc_power_by_need, site_cap_gate_metered
--                                    0726-0737: tested only at 40 posts on a 2,400 kW cabinet, where the held site served as
--                                    many visits as its control or more (arms 107, 112, 116, 117 against 95 and 115) at lower
--                                    peaks. As built the cap never binds (arm 93's peak 915 kW against 1,800), so they would
--                                    change nothing today; they belong with 0759's 20 posts, as one change.
--     wash_lane_physics             0746, G460/G475: whether the depot's wash lanes are robotic is Chase's equipment call.
--                                    Robotic lanes (2) met 22.0 more car-hours at 40 posts and served 7 fewer cars; crews
--                                    timed by their own work (1) met 16.0 fewer, because the catalog prices a deep clean at
--                                    20 minutes and the crews take 25 (G475, open).
--
-- ══ §5 WAITING ON CHASE'S CONFIRMATION AT THE CONNECTOR ═════════════════════════════════════════════════════════════
--
--   0603 (UPDATE of four schedule_tasks rows), 0749 (its checks DROP probe tables), 0755 (its third anchor reads as an
--   UPDATE of every car; preconditions passed read-only at 4:03 PM CT), the research pause (UPDATEs; needed by 0759's P0),
--   and 0759. The connector holds each for a person's confirmation; none is reworded or sent another way.
--
-- ══ §6 THE LIVE CHECK (run c6ec017d; reproduce: (5)-(8)) ═══════════════════════════════════════════════════════════
--
--   Started at 4:05 PM CT the way the app's Start does (otto-twin-control's startScenario): ottoq_operator_start_run
--   ('busy_day') then ottoq_set_playback(run, 'live', 3); the edge's fire-and-forget call to ottoq-feed-agents, which needs
--   the service key, was not made. (5): the run reads the seven as 1 and the held switches as 0. (6): car 7a138260 plugged
--   into NASH-DCFC-STALL-06 at sim 8:46 AM CT at 21%; its must-do tidy started at sim 8:47:25 by the stall's arm
--   (performed_by stall_cabin_robot, robot_stall_id the stall, ends_at started_at + 5.8 minutes), no technician. (7): by
--   4:16 PM CT, tick 127, sim 9:06 AM CT: 2 arm cleans done, 44 service records issued. The live view (the app's own code
--   on a dev server, pinned to the run) filmed DCFC-08's cycle: doors open at sim 8:55, the arm cleaning side A at 8:58,
--   home after (ottoyarddepot-sim docs/pr-shots/clean-arm-live, scripts/liveCleanShots.mjs). (8): rule 9 and the bay
--   switches are read when the run's day is done.
--
-- ══ QUERIES ═════════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) the switches Chase's run read
SELECT k, public.ottoq_policy_get('0cdbfc72-0c0b-4dc0-b3b8-c6fa00616122'::uuid, k, 0) AS read
  FROM unnest(ARRAY['dc_power_sharing','site_cap_gate_metered','dc_power_managed','dc_power_first_reading',
                    'twin_answer_in_tick','ready_promise_record','dc_power_by_need','ready_promise_refresh_min',
                    'bay_activation_per_seat','bay_hold_follows_charge','itinerary_charge_on_clock','wash_lane_physics',
                    'bay_order_uptime_first','bay_exit_closes_its_leg','repair_needs_its_green_light',
                    'bay_release_reads_the_work','stall_cabin_robot']) k;

-- (2) who did its interior work
SELECT a->>'svc' AS svc, count(*) AS atoms, string_agg(DISTINCT COALESCE(a->>'performed_by', '-'), ', ') AS performed_by
  FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
 WHERE vn.sim_run_id = '0cdbfc72-0c0b-4dc0-b3b8-c6fa00616122' AND a->>'svc' ILIKE 'interior%'
 GROUP BY 1 ORDER BY 1;

-- (3) the test openers
SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobid IN (746, 755, 761, 762, 763, 783, 784, 785) ORDER BY jobid;

-- (4) the twin depot's switches
SELECT param_key, param_value, updated_by, updated_at FROM public.ottoq_policy_params
 WHERE scope_type = 'depot' AND scope_id = '11111111-1111-1111-1111-111111111111' AND updated_at > '2026-10-20 20:00+00'
 ORDER BY param_key;

-- (5) what the live check read
SELECT k, public.ottoq_policy_get('c6ec017d-ec07-4762-8774-4129de1f4ad6'::uuid, k, 0) AS read
  FROM unnest(ARRAY['twin_answer_in_tick','bay_activation_per_seat','bay_hold_follows_charge','bay_exit_closes_its_leg',
                    'repair_needs_its_green_light','bay_release_reads_the_work','stall_cabin_robot',
                    'itinerary_charge_on_clock','bay_order_uptime_first','dc_power_sharing','wash_lane_physics']) k;

-- (6), (7) the arm's work on the live check
SELECT left(vn.vehicle_id::text, 8) AS car, a->>'status' AS status, s.stall_code, a->>'started_at' AS started_at,
       a->>'ends_at' AS ends_at, a->>'done_at' AS done_at
  FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
  LEFT JOIN public.stalls s ON s.id::text = a->>'robot_stall_id'
 WHERE vn.sim_run_id = 'c6ec017d-ec07-4762-8774-4129de1f4ad6' AND a->>'performed_by' = 'stall_cabin_robot'
 ORDER BY a->>'started_at';

-- (8) rule 9 at departure and the bay switches, once the day is done
SELECT public.ottoq_throughput_scorecard('c6ec017d-ec07-4762-8774-4129de1f4ad6'::uuid) -> 'rule9' AS rule9;
