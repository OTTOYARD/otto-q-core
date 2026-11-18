-- 0498  **OTTO-TIRE's two jobs work on the twin depot. On the first check run a worn set was replaced in a 12-minute seat,
--        and a rotation was seated for one minute because two doors admitted its car in one tick. 0844 fixed that, and
--        on the second run the rotation had its full seat.**
--        Production database, 2026-11-17 23:39 UTC to 2026-11-18 00:10 UTC (5:39 to 6:10 PM CT). Rule 8: the twin depot.
--        Rule 12: two demo runs started to see the change working, read, and stopped; no pair, no sweep. One seed:
--        readings, not ranges.
--
-- ══ (1) THE CHANGE ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0842 (ledger 20261117233648, 5:36 PM CT): tire_replacement (tread under 3.0 mm) and tire_rotation (every 2,190 h) are
--   service-bay services of their own, required on the visit, seated for 12 minutes when nothing else is owed there,
--   credited at the bay exit with the tread reset to 8.0 mm and the rotation quarter restarted. Chase, 2026-11-17: "The
--   tire robot stall needs to be for worn out tires and rotations (scheduled quarterly, and only occurs a few times per
--   simulation run)." 0843 (20261117235604) and 0844 (20261117235645) were applied between the two runs.
--
-- ══ (2) CHECK RUN 1: 0dc17f83 (busy_day on 89ac9e74's seed, 2431887468006319286) ═════════════════════════════════════
--
--   Started by me through public.ottoq_operator_start_run('busy_day', seed, 'operator_demo'), live at 8x, read to sim
--   15:33, stopped through public.ottoq_sim_stop_and_reset at 23:53:06 UTC. The seeding drew 1 worn car of 116
--   (Waymo-AV-038, 2.9 mm) and 1 rotation due at the draw (Waymo-AV-006, ratio 1.000), as 0842's V7 read on this seed.
--   - Waymo-AV-038, a boot car with no visit, was seated by the needs card for tire_replacement at sim 14:07:51 in
--     NASH-SVC-01 until 14:19:51 (720 s). At the exit its tread read 8.0 mm and its last rotation 14:19:51. The bay exit
--     credited the seat's own need (0458's bay_need), since its visit held no tire atom.
--   - Waymo-AV-006 washed, charged to 100%, then owed the rotation on its visit (required, not riding along). At sim
--     15:12:39 the needs card booked NASH-SVC-02 for it, 12 minutes, and in the same tick section (5) admitted it again
--     and released the card's booking to 15:12:39-15:12:40. The twin refused the second command and confirmed the first:
--     in the bay 15:13:31 to 15:14:48, the rotation credited at 15:14:31. 1 of the run's 5 service-bay admissions was
--     doubled. 0844 is the fix.
--
-- ══ (3) CHECK RUN 2: eb4e90ca (the same seed, after 0843 and 0844) ═══════════════════════════════════════════════════
--
--   Started and played the same way at 23:57 UTC, read to sim 15:40, stopped at 00:10:12 UTC.
--   - Waymo-AV-038: seated at 14:05:16 for 720 s, tread 8.0 mm after, last rotation 14:17:16.
--   - Waymo-AV-006: its 12-minute booking on NASH-SVC-02, planned for 15:36, was activated early: in the bay 15:27:14 to
--     15:40:23, the seat's timer ending 15:39:14, the rotation done at 15:39:14, its last rotation 15:39:14, its tread
--     unchanged at 4.3 mm, then staged for departure. While it sat there the snapshot's bay_seat.work read
--     ["tire_rotation"] (0843).
--   - No car was admitted twice (Q2).
--
-- ══ (4) WHAT IS NOT VERIFIED, AND WHAT IS OPEN ═══════════════════════════════════════════════════════════════════════
--
--   (a) Two runs of one seed, the morning only (to sim 15:40, 9:40 AM CT). No rotation fell due during either run and
--       none rode along: on this seed no car with a rotation within 14 days of due had other service-bay work.
--   (b) Boot cars have no visit, so their tire need lives on the needs card alone, and the departure test reads the
--       visit. Both runs seated AV-038 before it could leave; a run whose bays were busy might not. Not measured.
--       MEASURED AND CLOSED 2026-11-18 (0845, ledger 20261118010216, 7:02 PM CT on 11-17). It was a real gap: a charged
--       car with a worn set and no visit was departure-clear. AV-038 was not protected by luck in dispatch, as I first
--       said; it began each run at 89% against a 100% target, so the departure recheck sent it to charge (14:06:50 on
--       0dc17f83, 14:04:21 on eb4e90ca) and the needs card seated it for the tires from there. Closing the door alone
--       would have stranded such a car: the recheck had no remedy for card-only work, and the needs card seats only cars
--       waiting for service; and with the bays busy the service flow's 0468 need gate and the deploy gate would have
--       released it every tick. 0845 closes all three, and its probe reproduced each before and showed it closed after.
--       The same shape holds for any must-do the card raises on a car with no visit; only the tire jobs are closed (G554).
--       A demo run after the apply (e0c4962f, the same seed, 7:06 to 7:20 PM CT) let 65 cars leave by sim 14:59 against
--       66 on eb4e90ca, seated both tire cars as before, and erred nowhere; no car took the new path on this seed.
--   (c) The flat-tyre path (tow truck, a parking spot) is not modeled.
--
-- ══ THE QUERIES ══════════════════════════════════════════════════════════════════════════════════════════════════════

-- Q1: each run's service-bay admissions, with their bookings (doubles show as two commands at one issued_at)
SELECT left(c.sim_run_id::text, 8) AS run, v.display_name, c.issued_at, c.payload ->> 'need' AS need, c.status,
       (SELECT jsonb_agg(jsonb_build_object('stall', s.stall_code, 'src', to_jsonb(b) ->> 'source', 'state', b.state,
                                            'sec', round(EXTRACT(EPOCH FROM (upper(b.during) - lower(b.during))))))
          FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
         WHERE b.vehicle_id = c.vehicle_id AND b.sim_run_id = c.sim_run_id AND lower(b.during) = c.issued_at
           AND s.stall_type::text = 'service_bay') AS bookings
  FROM public.ottoq_vehicle_commands c JOIN public.vehicles v ON v.id = c.vehicle_id
 WHERE c.sim_run_id IN ('0dc17f83-dc5b-451e-a548-3e1c32f5f36c', 'eb4e90ca-4927-462d-8089-f7938aeb2218')
   AND c.command_type = 'enter_service'
 ORDER BY 1, c.issued_at;

-- Q2: doubled admissions per run
SELECT left(sim_run_id::text, 8) AS run, count(*) FILTER (WHERE n > 1) AS doubled, count(*) AS ticks
  FROM (SELECT sim_run_id, vehicle_id, issued_at, count(*) AS n FROM public.ottoq_vehicle_commands
         WHERE sim_run_id IN ('0dc17f83-dc5b-451e-a548-3e1c32f5f36c', 'eb4e90ca-4927-462d-8089-f7938aeb2218')
           AND command_type = 'enter_service' GROUP BY 1, 2, 3) d
 GROUP BY 1;

-- Q3: the rotation car's moves on each run
SELECT left(e.sim_run_id::text, 8) AS run, e.sim_clock_at, e.payload -> 'diff' -> 'current_state' ->> 'to' AS state_to
  FROM public.ottoq_events e JOIN public.vehicles v ON v.id = e.entity_id
 WHERE v.display_name = 'Waymo-AV-006' AND v.home_depot_id = '11111111-1111-1111-1111-111111111111'
   AND e.sim_run_id IN ('0dc17f83-dc5b-451e-a548-3e1c32f5f36c', 'eb4e90ca-4927-462d-8089-f7938aeb2218')
   AND e.event_type = 'vehicle.state_changed' AND e.payload -> 'diff' ? 'current_state'
   AND e.sim_clock_at > '2026-11-17 15:00+00'
 ORDER BY 1, 2;
