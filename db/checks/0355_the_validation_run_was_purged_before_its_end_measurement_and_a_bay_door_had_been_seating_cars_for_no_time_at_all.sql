-- 0355  **The validation run after 0442–0450, what survives of it, and the bay door it exposed.**
--
--       Run `736406cf-05ee-448d-b529-0e04b074eddd`: busy_day, twin depot `11111111-…`, agent v21, recall v3 (0448),
--       governor 900 sim-minutes. Started 05:14 UTC 2026-09-23 (12:14 AM CT) and ended 07:08 UTC (2:08 AM CT) on
--       the governor ceiling after 1,910 ticks, sim 04:12 → 19:17 CT.
--
--       THE END-OF-RUN MEASUREMENT PLANNED HERE NEVER RAN. The session that owned it stopped before the run ended,
--       and run `689095e2` purged 736406cf's engine-class rows when it started at 19:12 UTC on 2026-09-25.
--       Readiness, the DR call, the day plan, charging by band and the five KPIs all read engine-class tables, so
--       none of them can be recomputed for this run. What survives:
--         §1  the run archive (`ottoq_run_archives`, the durable reproducibility key)
--         §2  the agent, from `ottoq_model_call_ledger` (class = 'evidence')
--         §3  the proposers, from the same ledger and `ottoq_proposal_disposition_ledger` (class = 'evidence')
--         §4  G191, measured while the run was live, 06:40–06:47 UTC, with the queries as run
--         §5  G191 reproduced on the surviving run `689095e2`
--
--       Lesson, and it is CLAUDE.md Part 3's own: cite the run, and measure it before anyone can start another.
--       A validation run's end state is engine-class data; the next demo start deletes it.

\set run '736406cf-05ee-448d-b529-0e04b074eddd'

-- ══ §1 THE ARCHIVE ═══════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0355 §1 — what the run archive kept ==='
SELECT reason, tick_count, sim_clock_start, sim_clock_end, engine_hash, metrics
  FROM public.ottoq_run_archives WHERE sim_run_id = :'run';
-- run_governor: reached the 900 sim-minute ceiling · 1,910 ticks · engine_hash c0fc6b00d0839f7996df301110d826d9
-- metrics: 182 dispatches · 270 charge sessions · 736 tasks completed · 38,212 commands issued · 438 refused ·
--          71,503 events · 84 vehicles simulated.

-- ══ §2 THE AGENT ═════════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0355 §2 — agent passes by outcome and cause ==='
SELECT outcome, source_kind, left(COALESCE(detail->>'model_error', '-'), 40) AS cause,
       count(*) AS n, round(avg(latency_ms)) AS mean_ms
  FROM public.ottoq_model_call_ledger
 WHERE sim_run_id = :'run' AND provider = 'nvidia_nemotron'
 GROUP BY 1, 2, 3 ORDER BY 1, n DESC;
-- 284 passes: 120 answered and enacted (mean 24.2 s, max 67.6 s); 164 fell back to the deterministic path.
-- Fallback causes: NVIDIA HTTP 429 (rate limited) 89, the 75-second deadline v21 added (G188) 40, HTTP 404 23
-- (all inside 06:03–06:07 UTC), HTTP 503 10, HTTP 500 2. So on this run the agent's model answered 42% of its
-- passes, and the largest single cause of silence is the provider's rate limit, not our code. The 73 backfilled
-- rows carry the 0452 apply instant as `called_at` (0356 §2): partition them on `sim_clock`.

-- ══ §3 THE PROPOSERS ═════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0355 §3a — the CP-SAT service ==='
SELECT outcome, http_status, count(*) AS n, sum(COALESCE(proposals_out, 0)) AS proposals, round(avg(latency_ms)) AS mean_ms
  FROM public.ottoq_model_call_ledger
 WHERE sim_run_id = :'run' AND provider = 'cpsat_service'
 GROUP BY 1, 2 ORDER BY n DESC;
-- solved_but_zero_proposals 270 (HTTP 200, mean 24 ms: an instance with nothing to place) · answered 11 with 17
-- proposals · HTTP 500 3 · enacted 1.

\echo '=== 0355 §3b — what the kernel did with each proposer''s rows ==='
SELECT source, abstained, status, count(*) AS n
  FROM public.ottoq_proposal_disposition_ledger WHERE sim_run_id = :'run'
 GROUP BY 1, 2, 3 ORDER BY 1, 2, n DESC;
-- forward_lex: 670 abstentions and 31 offers (16 refused, 14 superseded, 1 enacted).
-- greedy_constrained: 161 offers (44 enacted, 90 refused, 27 superseded).
-- The rank-0 proposer was enacted once in 1,910 ticks. G167's batch of 8 and 30-minute window stand.

-- ══ §4 G191 — A BAY DOOR THAT SEATED CARS FOR NO TIME, AND A NEED NOTHING COULD CREDIT (measured live) ═══════════
--
-- Found while measuring the cockpit's Events feed: three vehicles carried almost all of the run's
-- `ottoq.replan_escalated` events. The queries below were run against the live run at 06:40–06:47 UTC; the rows
-- they read are purged, so the numbers are recorded as returned.

\echo '=== 0355 §4a — who was escalated, and how often ==='
SELECT v.display_name, count(*) AS replan_escalated, min(e.sim_clock_at) AS first_sim, max(e.sim_clock_at) AS last_sim
  FROM public.ottoq_events e JOIN public.vehicles v ON v.id = e.entity_id
 WHERE e.sim_run_id = :'run' AND e.event_type = 'ottoq.replan_escalated'
 GROUP BY 1 ORDER BY 2 DESC;
-- Tesla-AV-062  459   09:58:32 → 21:10:40 UTC sim (4:58 AM → 4:10 PM CT)
-- Tesla-AV-054   92   19:08:09 → 21:10:40 UTC sim
-- Waymo-AV-019    1
-- Every one reads `attempts 3, max_attempts 3, doctrine bounded_replan_then_flag`: the bound fired 459 times for
-- one car and bounded nothing, because `ottoq_reopen_visit_atoms` stamps `meta.reopen_escalated` and nothing that
-- admits a car to a bay reads it.

\echo '=== 0355 §4b — every needs-card bay booking, by how it ended ==='
SELECT b.purpose, b.source, b.state, b.release_reason, count(*) AS n, count(DISTINCT b.vehicle_id) AS vehicles,
       round(avg(extract(epoch FROM (COALESCE(b.released_at, upper(b.during)) - lower(b.during))) / 60)::numeric, 2) AS avg_min
  FROM public.ottoq_stall_bookings b
 WHERE b.sim_run_id = :'run' AND b.purpose IN ('wash','detail','service')
 GROUP BY 1, 2, 3, 4 ORDER BY n DESC;
-- wash   needs_card   interrupted  bay_exit_before_planned_end   598 bookings, 12 vehicles, 0.95 min of 9 planned
-- detail needs_card   interrupted  bay_exit_before_planned_end     3 bookings,  3 vehicles, 0.85 min
-- Every other door ran its full window: bay_reservation_activated_early wash 9.31 min / detail 20.53,
-- bay_reconcile_twin_admit wash 8.71 / service 44.57. NOT ONE needs-card seat on this run lasted its booking.

\echo '=== 0355 §4c — one cycle of AV-062, event by event ==='
-- (the vehicle is b14db297-e308-4ce6-8cce-88edbafce40e; stall NASH-WSH-02 is 6277d0cc-…)
--   21:10:40  release_vacated_spaces: booking interrupted (bay_exit_before_planned_end, 0.80 of 9 min),
--             replan_escalated (attempts 3 of 3) — and in the SAME tick decide 4b books NASH-WSH-02 again
--   21:11:10  confirm_commands executes `enter_wash`: staged_awaiting_service → in_wash_bay; the service flow's
--             STEP 1 then sees no `service_ends_at`, calls it "null-timer stuck" and exits it in the same instant:
--             twin.service_completed {credited: [], bay_capable: [exterior_wash, sensor_clean], self_healed: true}
--   21:11:29  the booking is interrupted again, and rebooked again.
-- Two ticks per cycle, ~0.8 sim-minutes, for eleven sim-hours.

\echo '=== 0355 §4d — why the need never cleared ==='
SELECT c.display_name, c.must_do_now, c.wash_urgency, c.exterior_soil_level, c.last_wash_at, c.wash_due_at
  FROM public.ottoq_vehicle_needs_card c
 WHERE c.run_id = :'run' AND c.display_name IN ('Tesla-AV-062', 'Tesla-AV-054');
-- AV-062: must_do_now [exterior_wash], wash overdue (ratio 1.024), soil 1.0, last wash 2026-09-21 18:12 UTC.
-- AV-054: must_do_now [exterior_wash], wash overdue (ratio 1.282), soil 0.507.
-- AV-062's visit manifest (`ottoq_visit_needs` 2d9023a1-…, arrived 09:37 sim) has NO exterior_wash atom: its wash
-- fell due at 20:12 sim, eleven hours after the visit was derived. Its only open atoms were readiness_check (gate)
-- and a deferrable interior_deep_clean. The bay credits `bay_capable ∩ (outstanding atoms ∪ technician flag)`
-- (0009) = {exterior_wash, sensor_clean} ∩ {readiness_check, interior_deep_clean} = {}.
--
-- THE MECHANISM, two defects composed:
--   (1) `twin.ottoq_sim_confirm_commands` puts a car in a bay on `enter_wash` / `enter_service` and writes neither
--       `service_ends_at` nor `svc_step`. `twin.ottoq_sim_advance_service_flow` STEP 1 completes any in-bay car
--       whose timer is null. 0016 closed exactly this seam for `ottoq_activate_due_bay_reservations` ("turned a
--       38-minute service into 2 minutes"); the command door never got it. So every needs-card wash lasted one tick.
--   (2) The needs card (decide 4b) admits a car for a need read from its live condition; the bay credits only the
--       visit manifest and a named technician flag. A need that arose after the visit was derived is admitted and
--       can never be credited, so its wear is never reset and the card sends the car back on the next tick.
--   Each alone is survivable: (1) alone made washes one tick long but credited them; (2) alone would have cost one
--   full wash. Together they loop.

-- ══ §5 G191 ON THE SURVIVING RUN `689095e2` (busy_day, 506 ticks, 2026-09-25) ═══════════════════════════════════

\echo '=== 0355 §5 — the same door on a run that still exists ==='
SELECT c.command_type, c.status, c.payload->>'reason' AS why, count(*) AS n, count(DISTINCT c.vehicle_id) AS vehicles
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = '689095e2-b67f-4fa8-bac7-d59341bbe73b' AND c.command_type IN ('enter_wash', 'enter_service')
 GROUP BY 1, 2, 3 ORDER BY n DESC;
-- enter_wash executed, needs_card_wash: 17 commands for 6 vehicles; 8 `twin.bay_credit_none` exits; 18 bookings
-- interrupted on 7 vehicles. Shorter, and the same shape: repeated seats per vehicle, exits that credit nothing.
