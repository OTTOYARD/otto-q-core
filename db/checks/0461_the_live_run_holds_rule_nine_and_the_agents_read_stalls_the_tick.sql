-- 0461  **Run 78c0624c read end to end: rule 9 held on every departure; the agent's read stalls one world step in seven;
--        a cabin clean a charger fault cut short is never done; the plan still charges cars on chargers the depot no
--        longer has; and what the agent layer could become.** -> G485, G486; G459 (a decision); the agent study (§7).
--        Chase, 2026-10-23 at about 10:25 PM CT: "Okay a run has started. Analyze everything, and ensure that everything
--        functions correctly and optimally. Also, study the agent layer and see if there is any opportunity for growth
--        and expansion with intelligence there."
--        Run 78c0624c-ff52-4594-8e54-9da254d4d867: busy_day at the twin depot (rule 8), seed 7698677070606373320, live
--        playback at 3x, started 2026-10-24 03:18:55 UTC (10:18 PM CT on 10-23). Read against gxdrcyphqjzjsuhxuqtg,
--        read-only, between 03:28 and 04:17 UTC (10:28 and 11:17 PM CT): from sim 13:33 to sim 16:15. Every figure below
--        names the moment it was read; the run was still going at the last read.
--
-- ══ §1 RULE 9 HELD (reproduce: (1)) ═════════════════════════════════════════════════════════════════════════════════════
--
--   By sim 16:15 (04:16:41 UTC), 87 cars had left since the run began, none below its target less one (G244's one rule;
--   the lowest 99%), and none with a service open on its visit. One left with a service CANCELLED that should have been
--   done: car 12cb06f0, whose cabin clean a charger fault cut short (§3, G486). Six cars at 100% with a wash or a deep
--   clean owed sat parked from as early as sim 13:16 rather than leave; the bay line took them as bays freed (§4).
--
-- ══ §2 CHARGING: THE POSTS ARE THE WALL, AND FAULTS TAKE A QUARTER OF THEM AT A TIME (reproduce: (2)) ════════════════════
--
--   122 charges had closed by sim 16:15 and 18 of them ended in a charger fault (14.8%; 11 of 85, 12.9%, at sim 14:40),
--   the calibrated mix (fault.communication_dropout, station_hardware, session_aborted_other, connector_cable,
--   thermal_emergency, ground_fault_safety; drawn repairs 10 to 631 minutes). At sim 14:40 (03:45 UTC) 7 of the 30 posts
--   were faulted and the other 23 all occupied, and 31 cars waited at the gate for a post: a mean 30 minutes, the longest
--   61, 18 past the 30-minute contract wait, the lowest at 44%. Every faulted charge's car was re-queued and plugged in
--   again (12cb06f0: faulted at 14:20:09 on W-23, plugged into E-29 at 14:24:53). Rule 9 names what this is: a capacity
--   finding, whose answers are more posts, fewer faults, a post freed the moment its car is done and better ordering of
--   who is served next, never shorter charges. Nothing here asks for a change; the fault mix is the research wing's.
--
-- ══ §3 THE CLEANING ARMS: 122 CLEANS, AND ONE THAT A FAULT CUT SHORT IS NEVER DONE (G486; reproduce: (3)) ═══════════════
--
--   By sim 16:15 the posts' arms had done 122 cabin cleans. Five tidies had been cancelled by sim 15:00: four were alert
--   tidies the triage cleared (right), and one was a routine the arm had begun on 12cb06f0 at W-23 at 14:18:27 when the
--   charger faulted (14:20:09). The completion step cancelled it when the arm's cycle ran out with the car off the post
--   (0764: not a need, so not sent to a technician), and because the starter records the routine once a visit, as it
--   begins (meta.arm_routine = 'cleaned'), and the completion step hands the starter only cars with no routine recorded,
--   the arm of E-29 never cleaned it: the car charged there from 14:24:53 and left at 16:08 at 100%, its visit reading
--   charge done, readiness_check done, interior_inspection done, interior_tidy cancelled. Chase's call (0765, G484) is
--   that every charging car is cleaned. 0767 makes the next post's arm clean it.
--
-- ══ §4 THE BAYS (reproduce: (4)) ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The wash and detail lanes pull a waiting car in as a bay frees, booking or not: 0d43459d (a wash owed, no booking)
--   was seated in Wash Bay 01 at 15:04, and a24e3f67 in Wash Bay 02 at 14:57, hours ahead of its 18:22 booking. So the
--   calendar's long idle windows (Wash Bay 01 free from 15:45 to 21:32 in the plan at sim 14:55) are not idle bays. The
--   service bays are the wall (G430, open, Chase's decision): at sim 14:55, 23 service bookings held, two active, and
--   preventive maintenance booked as late as 01:06-02:58 the next day.
--
-- ══ §5 THE PLAN STILL CHARGES CARS ON CHARGERS THE DEPOT NO LONGER HAS (G459; reproduce: (5)) ═══════════════════════════
--
--   0763 retired every standard charger at the twin depot (0 l2 stalls), but ottoq_plan_visit_itinerary still picks a
--   charge by its fixed rule (an L2 at 11 kW above 45%). At sim 15:00, 59 of the run's cars carried a planned L2 leg,
--   a mean 4.6 hours long, and 45 of them were in fact fast-charging. Every leg after it is planned from its end, so a car
--   whose fast charge ends at 15:31 is planned to wash at 21:52 (ebd4669f), and the owner app's ready-by reads the same
--   legs (G454). The bays do not wait for those holds (§4), so throughput barely moves, which is what the arms showed.
--   The fix was built, applied and held off: 0745's dial itinerary_charge_on_clock plans the charge on the kind of
--   charger the car can use at the depot and times it on the learned clock. 0459 §4 held it off on one arm at the depot
--   as it was then (10 posts and 30 L2: arm 121, 142 departures against arm 93's 159). At 40 posts and no L2, the depot
--   it was built for, arm 120 had 208 departures against arm 95's 205. The depot is now 30 posts and no L2. Switching it
--   on at the twin depot is Chase's call under rule 12, and this file recommends it.
--
-- ══ §6 TICK HEALTH (G485; reproduce: (6), (7)) ════════════════════════════════════════════════════════════════════════════
--
--   No world, decide or operator step failed (no sim_tick_failed event by sim 15:00). Two things slow the beat:
--   (a) THE AGENT'S READ HOLDS THE RUN'S ROW (G485). Of the run's 545 world steps to 04:16:22 UTC, the 78 that began
--       within 9 s of an agent pass's start took a mean 6,071 ms against 1,574 for the other 467: about 351 s of the run's
--       3,432 s (10.2%) waited behind the agent. Sampled on live every 50 ms (pg_stat_clear_snapshot() before each sample;
--       without it pg_stat_activity is read once per transaction and every holder showed 'COMMIT'): at 03:38:27.46-32.05
--       and 03:36:49.38-54.04 UTC the metronome waited on a transactionid with a tuple lock on ottoq_sim_runs, blocked by
--       PostgREST running ottoq_agent_board. The board calls ottoq_predict_arrivals, which records an
--       'ottoq.arrival_forecast' event; its key check (fk_ottoq_events_sim_run) holds the run's row FOR KEY SHARE until the
--       board's transaction ends, about 6.6 s later (ottoq_agent_charge_queue_board alone took 6,567 ms, timed on live at
--       03:41 UTC), and the world step's first statement takes that row FOR UPDATE, which G490 shows must stay. A census of
--       every function the board reaches, five calls deep, finds that one writer and no other. 0766 has the board read the
--       same forecast without writing it.
--   (b) THE METRONOME RESTS ONCE A MINUTE. pg_cron runs CALL ottoq_demo_metronome(50) each minute; it ticks for 50 s and
--       returns, so each minute has a gap of 10-12 s with no tick (50 gaps over 8 s in 3,432 s, 564 s in all, 16.4%). In
--       live playback the next tick advances by the real time since the last, so the run loses no sim time, only grain:
--       that tick moves the world 35-54 sim-s at once instead of about 20. Not changed. A budget of 57 s would close most
--       of it (pg_cron starts a late run as soon as the one before ends), and it is a schedule's argument, so it is listed
--       for Chase, not made.
--
-- ══ §7 THE AGENT LAYER (reproduce: (8)) ══════════════════════════════════════════════════════════════════════════════════
--
--   What it did on this run by 04:16:41 UTC: 90 passes, every one consulted (the wake gate is in shadow, agent_wake_enabled
--   0), 3 answered by no model (the fallback), 2.25 million tokens, a mean 32.2 s a pass (p95 47.3 s, read at 03:57 UTC on
--   60 passes). 8 passes changed something; the other 82 advised or echoed. Its one lever that moves cars, the charge
--   order: 83 orders, 75 refused by the kernel's check, 3 accepted, 5 taken in part. Graded in hindsight
--   (ottoq_charge_order_hindsight, the twin depot, the 3 days to 04:00 UTC): of 21 orders the check took, 15 were right,
--   5 wrong and 1 neutral; of 93 it refused with a decision to make, 59 were right and 34 were wins it missed. The
--   check is conservative, which is the safe side (a refusal keeps the kernel's own order).
--   The wake gate's shadow record says what switching it on would do: it would have woken on 3 of the 90 passes, and 7
--   of the 8 passes that changed something are among the 87 it would have skipped. So the gate as built would save about
--   95% of the tokens and lose nearly everything the agent contributes: its triggers (a new departure, a new contract
--   breach, a stranded car, a scout's finding, a charger-count jump) are not the moments the agent's orders are taken.
--   What could grow, in order of what it buys (each is a recommendation, rule 10: a person decides, and none runs a test):
--   1. The read stops stalling the tick (0766, built). Every agent pass today costs the world a 5-7 s freeze.
--   2. A wake gate that wakes on what the agent acts on. Wake when the charge line's order would change: a car joining
--      or leaving the head of the line, a post freeing with cars waiting, a car crossing its contract wait. The record
--      to tune it is already kept (ottoq_agent_pass_evidence.wake against outcome_class); ship it shadowed, compare.
--   3. The charge-queue board is the cost of the read: 6.6 s of 6.8, and its parts sum to 2.0 s (the line state 1.6 s,
--      the kernel's order twice at 0.12 s), so most of it is the per-car clock and target calls over 24 cars. Computing
--      the line once per beat and handing it to both the kernel and the board would halve the agent's latency.
--   4. Tell the agent why its order was refused. 75 of 83 refused, and the board carries the last order's status but
--      not the futures in which the kernel's order beat it. A refusal reason per order (which cars, how many minutes)
--      is the cheapest way for the agent to propose orders the check takes.
--   5. A lever where the wall is: the service bays (§4). The agent has no say in the bay line today. A bay-order
--      proposal checked by the same kind of futures the charge order is would be the next lever, after G430 settles the
--      bays' capacity.
--   6. One shift brief instead of three or four directives a pass: most directives repeat (632 a run in 32 shapes,
--      measured before this run); an exception queue that names each new problem once would be read.
--   7. Owner agents (rule 11): OTTO-Command through the gateway (0721 and the gateway, pending), after the agent
--      registry (0702, pending, in the security group).
--   8. Model reliability: 3 of 90 passes unanswered, p95 47 s; a second model on the same board, scored on the same
--      hindsight, is the measurement that says whether a different model helps (docs/AGENT_ARCHITECTURE.md's four
--      tests for a second agent).
--
-- ══ §8 WHAT IS BUILT, WHAT IS ASKED ═══════════════════════════════════════════════════════════════════════════════════════
--
--   Built, tested on the scratch PostgreSQL over the live bodies (md5-pinned), PENDING Chase's paste:
--     0766 (G485): the board reads the arrival forecast without writing it. 20 tests.
--     0767 (G486): a cabin clean a charger fault cut short is done at the car's next post. 17 tests.
--   Asked of Chase: itinerary_charge_on_clock on at the twin depot (§5); the metronome's 57-second budget (§6 (b));
--   which of §7's items to build first.

-- (1) rule 9 on every departure since the run began
WITH r AS (SELECT sim_run_id, sim_clock_start FROM public.ottoq_sim_runs
            WHERE sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867')
SELECT count(*) AS departures,
       count(*) FILTER (WHERE d.soc_at_dispatch_pct < public.ottoq_effective_target_soc_at(d.vehicle_id, d.dispatched_at) - 1)
         AS below_target_less_one,
       min(d.soc_at_dispatch_pct) AS lowest_soc
  FROM public.ottoq_vehicle_dispatches d, r
 WHERE d.sim_run_id = r.sim_run_id AND d.dispatched_at > r.sim_clock_start;

-- (2) the charges and the line
SELECT s.status::text, coalesce(s.stopped_reason, '') AS reason, count(*)
  FROM public.ocpp_sessions s WHERE s.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' GROUP BY 1, 2 ORDER BY 3 DESC;
SELECT count(*) AS waiting, round(avg(k.wait_min)) AS mean_wait, round(max(k.wait_min)) AS longest,
       count(*) FILTER (WHERE k.wait_min > 30) AS past_30, min(round(k.soc)) AS lowest_soc
  FROM public.ottoq_sim_runs r,
       public.ottoq_charge_queue_kernel_order(r.sim_run_id, r.depot_id, r.sim_clock_current) k
 WHERE r.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867';

-- (3) the arms' cleans, and the routine a fault cut short
SELECT a->>'status' AS status, COALESCE((a->>'arm_routine')::boolean, false) AS routine,
       a->'interrupted'->0->>'reason' AS interrupted, count(*)
  FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
 WHERE vn.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND a->>'svc' = 'interior_tidy'
 GROUP BY 1, 2, 3 ORDER BY 4 DESC;

-- (4) the wash bays' calendar and who is in them
SELECT COALESCE(s.display_name, s.stall_code) AS bay, b.purpose, b.state, b.need_atom, left(b.vehicle_id::text, 8) AS car,
       lower(b.during) AS t0, upper(b.during) AS t1
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
 WHERE b.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND s.stall_type::text = 'wash_bay'
   AND b.state IN ('held', 'active')
 ORDER BY s.stall_code, lower(b.during);

-- (5) the plan's L2 legs at a depot with no L2
SELECT count(DISTINCT l.vehicle_id) FILTER (WHERE l.status = 'planned') AS cars_with_a_planned_l2_leg,
       round(avg(extract(epoch FROM l.planned_end_sim - l.planned_start_sim) / 3600.0)
             FILTER (WHERE l.status = 'planned'), 1) AS mean_hours,
       (SELECT count(*) FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111'
                                           AND stall_type::text = 'l2') AS l2_stalls
  FROM public.ottoq_itinerary_legs l
 WHERE l.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' AND l.leg_type = 'charge_l2';
SELECT arm_id, buildout->>'buildout_code' AS build, scorecard->'rule9'->>'departures' AS departures
  FROM public.ottoq_throughput_sweep_arms WHERE arm_id IN (93, 95, 120, 121) ORDER BY arm_id;

-- (6) the world steps near an agent pass, and the minute's rest
WITH passes AS (SELECT p.recorded_at - make_interval(secs => COALESCE(p.total_ms, 0) / 1000.0) AS ps
                  FROM public.ottoq_agent_pass_evidence p
                 WHERE p.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867'),
t AS (SELECT l.tick_compute_ms, l.real_started_at,
             l.real_started_at - lag(l.real_ended_at) OVER (ORDER BY l.tick_seq) AS gap,
             EXISTS (SELECT 1 FROM passes p WHERE l.real_started_at BETWEEN p.ps AND p.ps + interval '9 seconds') AS near
        FROM public.ottoq_tick_clock_log l WHERE l.sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867')
SELECT near, count(*), round(avg(tick_compute_ms)) AS mean_ms,
       count(*) FILTER (WHERE gap > interval '8 seconds') AS gaps_over_8s,
       round(extract(epoch FROM sum(gap) FILTER (WHERE gap > interval '8 seconds'))) AS gap_s
  FROM t GROUP BY near;

-- (7) the lock, sampled: run while an agent pass is due (about every 30 s); the RAISE carries the report and rolls back
DO $$
DECLARE t0 timestamptz := clock_timestamp(); r record; v_out text := ''; v_mpid int;
BEGIN
  WHILE clock_timestamp() - t0 < interval '40 seconds' LOOP
    PERFORM pg_stat_clear_snapshot();
    SELECT pid INTO v_mpid FROM pg_stat_activity
     WHERE query LIKE 'CALL public.ottoq_demo_metronome%' AND state = 'active' LIMIT 1;
    FOR r IN SELECT a.wait_event_type, ab.usename,
                    (regexp_match(ab.query, '"(public|twin|ottoq)"\."([a-z0-9_]+)"'))[2] AS holder,
                    round(extract(epoch FROM clock_timestamp() - ab.xact_start)::numeric, 1) AS held_s
               FROM pg_stat_activity a CROSS JOIN LATERAL unnest(pg_blocking_pids(a.pid)) bp(pid)
               JOIN pg_stat_activity ab ON ab.pid = bp.pid
              WHERE a.pid = v_mpid AND a.wait_event_type = 'Lock' LOOP
      v_out := v_out || chr(10) || to_char(clock_timestamp(), 'HH24:MI:SS.MS') || ' ' || coalesce(r.usename, '?') || '/'
               || coalesce(r.holder, '?') || ' xact ' || r.held_s || 's';
    END LOOP;
    PERFORM pg_sleep(0.1);
  END LOOP;
  RAISE EXCEPTION 'metronome lock waits:%', v_out;
END $$;

-- (8) the agent's passes, its orders, and what the wake gate would have done
SELECT count(*) AS passes, count(*) FILTER (WHERE outcome_class = 'changed_state') AS changed_state,
       count(*) FILTER (WHERE (wake->>'would_wake')::boolean) AS would_wake,
       count(*) FILTER (WHERE (wake->>'would_wake')::boolean IS NOT TRUE AND outcome_class = 'changed_state')
         AS changed_on_a_pass_the_gate_would_skip,
       count(*) FILTER (WHERE model_answered IS NULL) AS unanswered,
       sum(COALESCE((usage->>'prompt_tokens')::bigint, 0) + COALESCE((usage->>'completion_tokens')::bigint, 0)) AS tokens
  FROM public.ottoq_agent_pass_evidence WHERE sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867';
SELECT status, count(*) FROM public.ottoq_agent_charge_orders
 WHERE sim_run_id = '78c0624c-ff52-4594-8e54-9da254d4d867' GROUP BY 1;
SELECT taken, outcome, count(*) FROM public.ottoq_charge_order_hindsight
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND graded_at > now() - interval '3 days'
 GROUP BY 1, 2 ORDER BY 1, 2;
