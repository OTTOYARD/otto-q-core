-- 0395  **G252: KPI 2 counted a booking the car outlived as a turn, and a charge still running at the day's end as no
--       turn at all. So a dial that sizes bookings correctly lost "turns" it never lost, and G240's experiment would have
--       been refused on its guardrail tonight: turns per point read -4.66% over its three pairs against a 2% margin,
--       in arms that did exactly the same things.**
--
--       Written on 2026-09-27 (13:50-14:30 UTC, 8:50-9:30 AM CT), from G240's three counted pairs (experiment 143a11c7:
--       pairs 76, 78, 80) and the day's full-day operator runs. Read-only.

-- ══ §1 THE ARMS ARE THE SAME WORLD, AND ONLY TURNS PER POINT MOVES ═════════════════════════════════════════════════

\echo '=== 0395 §1 — G240''s counted pairs: what the arms did, control (A) against treatment (B) ==='
SELECT p.pair_id, k, p.metrics_a->>k AS control, p.metrics_b->>k AS treatment
  FROM public.ottoq_dial_pair_ledger p,
       unnest(ARRAY['charge_sessions','deploys','trips_completed','vehicles_turned_around','throughput_per_hr',
                    'peak_site_kw','p95_time_to_service_min','service_point_turns_per_point_per_day']) AS k
 WHERE p.experiment_id = '143a11c7-6740-4624-b747-e145f3533e60'
 ORDER BY k, p.pair_id;
-- READ (2026-09-27 13:55 UTC): per pair (76 / 78 / 80), both arms: charge sessions 90/90, 81/81, 86/86; deploys 52/52,
--   58/58, 51/51; trips 116/116, 122/122, 115/115; throughput per hour identical; peak kW identical; cars turned around
--   62/62, 47/46, 54/54. Turns per point per day: 1.74 -> 1.64, 1.72 -> 1.71, 1.57 -> 1.45. The one KPI that moved is
--   the one that counts calendar rows.

-- ══ §2 WHY: A TURN WAS A BOOKING IN STATE `done` ══════════════════════════════════════════════════════════════════
--
--   `ottoq_kpi_service_point_turns` (0183) counted `state = 'done'`. Two booking fates decide the difference here:
--   `done`/`window_elapsed_occupied` -- the window ran out with the car still on the stall, which is G240's own defect
--   (a booking shorter than its charge) -- counted as a completed turn although the car stayed; and `released`/
--   `run_stopped` -- the run's teardown closing a booking still in progress at 5 PM -- counted as none. The control's
--   too-short windows elapse under charging cars all day (48-51 per arm); the treatment's windows cover the charge,
--   so for the charges still running at the horizon (identical in both arms) its bookings are still open at teardown.

\echo '=== 0395 §2 — charge bookings by how they ended, and the charges running at the day''s end ==='
WITH arms AS (
  SELECT p.pair_id, 'A_control' AS arm, p.run_a AS run FROM public.ottoq_dial_pair_ledger p
   WHERE p.experiment_id = '143a11c7-6740-4624-b747-e145f3533e60'
  UNION ALL
  SELECT p.pair_id, 'B_treatment', p.run_b FROM public.ottoq_dial_pair_ledger p
   WHERE p.experiment_id = '143a11c7-6740-4624-b747-e145f3533e60')
SELECT a.pair_id, a.arm,
       (SELECT count(*) FROM public.ocpp_sessions s JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
         WHERE s.sim_run_id = a.run AND (s.ended_at IS NULL OR s.ended_at >= r.sim_clock_current - interval '1 minute')) AS charges_running_at_end,
       count(*) FILTER (WHERE b.release_reason = 'window_elapsed_occupied') AS done_window_elapsed_occupied,
       count(*) FILTER (WHERE b.release_reason = 'charge_session_completed') AS done_with_the_charge,
       count(*) FILTER (WHERE b.release_reason = 'run_stopped') AS released_by_teardown
  FROM arms a JOIN public.ottoq_stall_bookings b ON b.sim_run_id = a.run AND b.purpose IN ('charge_dcfc', 'charge_l2')
 GROUP BY a.pair_id, a.arm, a.run ORDER BY 1, 2;
-- READ (2026-09-27 14:05 UTC): charges running at the end 37/37, 36/36, 28/28 -- the same in both arms of every pair.
--   Window elapsed under the car: control 48, 48, 51 against treatment 8, 23, 7. Done with the charge: 16, 19, 18
--   against 45, 30, 50. Released by the teardown: 23, 26, 16 against 34, 40, 27. Over all bookings the KPI counted 193,
--   188, 179 turns in the control and 182, 174, 165 in the treatment, with 59/70, 69/85, 66/78 released by teardown.

-- ══ §3 WHAT THE VERDICT WOULD HAVE DONE ══════════════════════════════════════════════════════════════════════════
--
--   Turns per point carries reward weight +0.3, so it is a guardrail of every dial experiment: `ottoq_dial_experiment
--   _verdict` returns `guardrail_breach` -- terminal, no promotion -- when the treatment wins its primary and any
--   reward KPI's mean relative change is worse than `guardrail_margin_pct` (2 for 143a11c7). Over the three counted pairs
--   it is -5.75%, -0.58%, -7.64%, mean -4.66%. Three more wins on the primary tonight (6 of 6, p = 0.0156 <= 0.025)
--   would have concluded G240 as a guardrail breach on a counting artifact. The energy replication 82c5568b is not
--   exposed: its dial moves the battery, and turns per point is identical in both arms of all four of its pairs.

-- ══ §4 A TURN IS A CAR LEAVING A SERVICE POINT ═══════════════════════════════════════════════════════════════════
--
--   The signed event stream records every move: `vehicle.state_changed` with `current_stall_id` in its diff. A departure
--   (`from` set) is the end of an occupancy -- a completed turn of that point -- whatever the calendar says. The run's
--   teardown also moves every parked car off its stall, always to `offline` and at the run's final clock; that is the
--   depot being cleared, not a turn. Neither a seed nor anything mid-run writes such a departure on these runs.

\echo '=== 0395 §4(a) — departures: the teardown''s are all to offline at the final clock, and nothing is in the first minute ==='
SELECT left(r.sim_run_id::text, 8) AS run, r.run_by,
       count(*) FILTER (WHERE e.sim_clock_at >= r.sim_clock_current) AS at_final_clock,
       count(*) FILTER (WHERE e.sim_clock_at >= r.sim_clock_current
                          AND e.payload->'diff'->'current_state'->>'to' IS DISTINCT FROM 'offline') AS at_final_clock_not_offline,
       count(*) FILTER (WHERE e.payload->'diff'->'current_state'->>'to' = 'offline' AND e.sim_clock_at < r.sim_clock_current) AS offline_before_end,
       count(*) FILTER (WHERE e.sim_clock_at <= r.sim_clock_start + interval '1 minute') AS in_first_minute,
       count(*) AS departures
  FROM public.ottoq_sim_runs r JOIN public.ottoq_events e ON e.sim_run_id = r.sim_run_id
 WHERE left(r.sim_run_id::text, 8) IN ('e58909eb', '2c05249e', '6ddd827e', '4bc19d29', 'c4afb873')
   AND (e.event_type || '') = 'vehicle.state_changed' AND e.payload->'diff'->'current_stall_id'->>'from' IS NOT NULL
 GROUP BY r.sim_run_id, r.run_by ORDER BY 1;
-- READ (2026-09-27 14:12 UTC): at the final clock 64 (each arm of pair 76), 106 (6ddd827e), 106 (4bc19d29), 83
--   (c4afb873), every one to `offline`; 0 offline departures before the end; 0 in the first minute of any run.

\echo '=== 0395 §4(b) — turns per point, as booked (0183) and as driven (departures, teardown excluded) ==='
WITH runs AS (
  SELECT p.pair_id::text AS pair, 'A' AS arm, p.run_a AS run FROM public.ottoq_dial_pair_ledger p
   WHERE p.experiment_id = '143a11c7-6740-4624-b747-e145f3533e60'
  UNION ALL
  SELECT p.pair_id::text, 'B', p.run_b FROM public.ottoq_dial_pair_ledger p
   WHERE p.experiment_id = '143a11c7-6740-4624-b747-e145f3533e60'
  UNION ALL
  SELECT 'full_day', left(r.sim_run_id::text, 8), r.sim_run_id FROM public.ottoq_sim_runs r
   WHERE left(r.sim_run_id::text, 8) IN ('6ddd827e', '4bc19d29', 'c4afb873')),
dep AS (
  SELECT e.sim_run_id, (e.payload->'diff'->'current_stall_id'->>'from')::uuid AS stall_id,
         COALESCE(e.payload->'diff'->'current_state'->>'to' = 'offline', false) AS teardown
    FROM runs x JOIN public.ottoq_events e ON e.sim_run_id = x.run
   WHERE (e.event_type || '') = 'vehicle.state_changed' AND e.payload->'diff'->'current_stall_id'->>'from' IS NOT NULL),
phys AS (SELECT sim_run_id, count(*) FILTER (WHERE NOT teardown) AS turns, count(DISTINCT stall_id) AS points
           FROM dep GROUP BY 1),
booked AS (SELECT b.sim_run_id, count(*) FILTER (WHERE b.state = 'done') AS turns, count(DISTINCT b.stall_id) AS points
             FROM runs x JOIN public.ottoq_stall_bookings b ON b.sim_run_id = x.run GROUP BY 1)
SELECT x.pair, x.arm, bk.turns AS booked_turns, bk.points AS booked_points,
       round(bk.turns::numeric / GREATEST(1, bk.points), 2) AS as_booked,
       ph.turns AS driven_turns, ph.points AS occupied_points,
       round(ph.turns::numeric / GREATEST(1, ph.points), 2) AS as_driven
  FROM runs x JOIN booked bk ON bk.sim_run_id = x.run JOIN phys ph ON ph.sim_run_id = x.run
 ORDER BY x.pair, x.arm;
-- READ (2026-09-27 14:20 UTC): as driven, pair 76 is 2.42 in both arms and pair 80 2.19 in both; pair 78 is 2.44
--   against 2.60 -- 266 against 265 departures, on 109 stalls against 102: the treatment turned the same cars over on
--   fewer stalls, a real difference and in its favour per point. Points occupied equal points booked in all nine runs,
--   so the denominator does not move; the numerator does, everywhere: the booked count was 72% of the driven one on the
--   arms (193 of 269) and 86-90% on the full days (6ddd827e 498 of 577 -> 3.74 as booked, 4.34 as driven; 4bc19d29 463
--   of 515 -> 3.36 against 3.73; c4afb873 176 of 221 -> 1.25 against 1.57).

-- ══ §5 NOT G195 ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The question this check started from was whether G240's longer windows made G195's calendar leak costlier. They do
--   not: of the charge bookings the calendar counts as holding (held, active, done, interrupted), 1 in the control and
--   2 in the treatment outlast their car's departure, each by 0.2 minutes -- the tick. The hour-long L2 tail past a
--   charge's stop is the car still parked on its charger, which the booking correctly covers until it leaves. G195
--   stays what it was: parking holds and the departure sweep's dial.

-- ══ §6 THE FIX: 0527 ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   KPI 2's numerator becomes the driven count (§4), its denominator the stalls a car occupied that day; the booking
--   columns stay beside it as the audit, with `bookings_done` reproducing 0183's numerator exactly. forces_recert FALSE
--   (no certification atom reads a KPI); forces_dial_restart NULL, because it changes what every experiment's guardrail
--   measures and a pair counted before it cannot be compared with one after. It goes in with 0526 (G251), which also
--   restarts the dial experiments, so they restart once, and tonight's window collects on the engine and the metric
--   they will be judged by.
