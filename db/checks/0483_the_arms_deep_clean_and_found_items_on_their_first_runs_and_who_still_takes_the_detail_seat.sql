-- 0483  **The arm's deep clean and the found items on their first runs, and who still takes the detail seat.**
--        (0814, 0815 seen working; 0816 applied; one count of mine corrected)
--        Production, 2026-11-12, 04:31-09:19 UTC (10:31 PM CT on 2026-11-11 to 3:19 AM CT). Rule 8: the twin depot.
--        Rule 12: one demo run to show a finished change working; no pair, no sweep. Single runs: readings, not ranges.
--
-- ══ (1) RUN 893a0313 (busy_day, operator_demo, live at 8x; started 04:31:11 UTC, ended by hand 06:06:51 UTC at sim
--        23:10 of a day that began at sim 14:00, its 540 sim-minute ceiling; 855 ticks) ═══════════════════════════════════════════════════════════
--
--   The first run with 0814 (found items) and 0815 (the arm's deep clean) on. Chase asked for it on 2026-11-11
--   ("Yes to all three, go and execute"). The wash seat was 5.5 minutes until 05:35 UTC and 6.5 after (§4).
--     - FOUND ITEMS (0814): 6 found, 6 secured, none open. The arm's pause was 65.4 to 85.4 s, mean 76.3 s, inside the
--       60 to 90 s the twin's attendant takes. Kinds: card holder, earbuds, glasses, keys, phone.
--     - THE ARM'S DEEP CLEAN (0815): 28 detail legs done at a fast-charger post, each 10.8 minutes.
--     - WASH SEATS: 28 wash legs done, mean 5.63 minutes (4.74 to 6.94).
--     - 258 work atoms done by a post's cleaning arm in all.
SELECT count(*) AS items, count(*) FILTER (WHERE status = 'secured') AS secured,
       round(avg(pause_seconds)::numeric, 1) AS pause_s_mean, min(pause_seconds) AS pause_s_min, max(pause_seconds) AS pause_s_max
  FROM public.ottoq_cabin_found_items
 WHERE sim_run_id = '893a0313-eb78-43a0-ba2a-0ab00d85b673';

-- ══ (2) A COUNT OF MINE, CORRECTED: THE DETAIL SEAT WAS GIVEN 23 TIMES IN A WASH BAY ON THAT RUN, NOT 4 ═════════════
--
--   At 05:35 UTC I read "4 deep cleans done in the detail seat, 28 by the arm" from the visits' atoms, and 0816's
--   header quotes it. That counted deep-clean ATOMS closed in a bay. It did not count SEATS. Counted from the
--   itinerary's legs (a detail leg whose stall is a wash bay), the run gave 23 detail seats in a wash bay against 28
--   deep programs at a post. An atom count answers "which deep cleans did a bay do". It does not answer "how often did
--   a car take a detail seat". The 23, by what the car's visit said when it was seated:
--      5   no visit record at all (boot cars, sim 14:08 to 14:36). The needs card's cadence seated them.
--      4   a visit with its deep clean and its charge still to do (the seat came before the charge). 0816's case.
--     11   a visit whose deep clean was ALREADY DONE, 30 to 218 minutes before the seat
--      3   a visit with no deep-clean atom, its charge done
--   The last 14 were not seated for a cabin deep clean. NOT ESTABLISHED why each was a detail seat and not a wash
--   seat. The service flow writes in_detail_bay for a car flagged minor_cosmetic or wash_due as well as for a car
--   that wants a detail (twin.ottoq_sim_advance_service_flow, the CASE that picks the state), and no deep clean was
--   open on these cars, so the flag is the likely door. That is read from the source, not measured on these 14.
SELECT count(*) AS detail_seats_in_a_wash_bay,
       count(*) FILTER (WHERE NOT has_visit) AS no_visit,
       count(*) FILTER (WHERE has_visit AND deep_status IN ('pending', 'in_progress')) AS deep_open,
       count(*) FILTER (WHERE has_visit AND deep_status = 'done') AS deep_done_before_or_by_this_seat,
       count(*) FILTER (WHERE has_visit AND deep_status IS NULL) AS no_deep_atom
  FROM (SELECT l.leg_id,
               EXISTS (SELECT 1 FROM public.ottoq_visit_needs n
                        WHERE n.sim_run_id = l.sim_run_id AND n.vehicle_id = l.vehicle_id
                          AND n.arrived_at <= l.actual_start_sim) AS has_visit,
               (SELECT a->>'status' FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                 WHERE n.sim_run_id = l.sim_run_id AND n.vehicle_id = l.vehicle_id AND n.arrived_at <= l.actual_start_sim
                   AND a->>'svc' = 'interior_deep_clean' ORDER BY n.arrived_at DESC LIMIT 1) AS deep_status
          FROM public.ottoq_itinerary_legs l JOIN public.stalls s ON s.id = l.to_stall_id
         WHERE l.sim_run_id = '893a0313-eb78-43a0-ba2a-0ab00d85b673' AND l.leg_type = 'detail'
           AND s.stall_type::text = 'wash_bay' AND l.status = 'done') q;
--   (deep_status is read now, after the run. "done" for the 4 of 0816's case is the bay's own credit, so the query
--   puts them with the 11. The split of 4 and 11 above is from each atom's done_at against the leg's start.)

-- ══ (3) 0816, APPLIED AT 06:08:12 UTC, AND ITS FIRST RUN ════════════════════════════════════════════════════════════
--
--   0816 keeps the deep clean of a car that still has its charge to do for its post's arm, and puts a deep program cut
--   short by a charger fault back to pending before the starter runs. Run 5480be1f (busy_day, operator_demo, live at
--   8x) was started at 06:08:28 UTC. Read at 06:15:45 UTC, sim 14:57, 105 ticks:
--     - deep cleans: 13 done by a post's arm (each leg 10.8 minutes), 3 under way at a post, 3 pending. None done in a
--       detail seat.
--     - detail seats in a wash bay: 3 (sim 14:05, 14:13, 14:21), all cars with no visit record. None for a car with a
--       visit. At the same hour of run 893a0313 there were 6: the 5 cars with no visit, and 1 with a visit, seated
--       before its charge.
--     - wash seats: 12 done, mean 6.41 minutes (the seat is 6.5 since 05:35 UTC).
--     - found items: 5 found, 5 secured.
--   READ AGAIN at 07:10:28 UTC, sim 20:26 (6.4 sim hours, 703 ticks; the run played at 1x from 06:35:44 to 06:51:03
--   UTC and from 07:10:10 to 07:20:57 UTC, for filming, and at 8x otherwise):
--     - deep cleans: 26 atoms, all 26 done by a post's arm (26 legs at a post, mean 10.84 minutes). None open, and
--       none closed by a bay. On run 893a0313 it was 28 by the arm and 4 by a bay, with 2 open at its end.
--     - detail seats in a wash bay: 13. 3 were the cars with no visit record. 4 were cars whose deep clean a post's arm
--       had already done. 6 were cars with no deep-clean atom. NONE was a car with a deep clean and a charge still to
--       do, which is 0816's case (4 of 23 on run 893a0313).
--     - wash seats: 32 done, mean 6.45 minutes.
--     - found items: 12 found, 12 secured, mean pause 75.0 s.
--     - no deep program was cut short by a fault, so §2(e) of 0816 is not yet seen on a run.
--   AT ITS END. The run governor ended the run at 07:40:00 UTC, at the 540 sim-minute ceiling every demo run has (sim
--   23:10, 1,049 ticks). Run 893a0313 had reached the same ceiling when I ended it (sim 23:10, 855 ticks), so the two
--   runs are the same length. They are different seeds, so they are not a pair. Read at 09:18:56 UTC:
--     - deep cleans: 27 atoms, 26 done by a post's arm and 1 pending at the end. None closed by a bay.
--     - detail seats in a wash bay: 17. 3 were cars with no visit record, 7 were cars whose deep clean was already
--       done, 7 were cars with no deep-clean atom. None had a deep clean open, and none had its charge still to do.
--     - wash seats: 33 done, mean 6.44 minutes. Found items: 12 found, 12 secured, mean pause 75.0 s.
--     - no deep program was cut short by a fault.
--   ONE RUN. It shows the change at work on the cars it was written for: 0 of 17 seats against 4 of 23. The 14 seats
--   given to cars with a visit and no deep clean open are §5(b)'s question.

-- ══ (4) THE WASH SEAT IS 6.5 MINUTES AT THE TWIN DEPOT ══════════════════════════════════════════════════════════════
--
--   robotic_wash_min at the twin depot: 5.0 until 2026-11-12 04:31 UTC, 5.5 until 05:35:35 UTC, 6.5 after. Chase said
--   yes to a 4.5-minute program (the 5.5), and then asked for six-axis detail arms that come down their own tracks
--   after the gantry has stowed (ottoyarddepot-sim, docs/OTTO-WASH.md). That program is 5.5 minutes at nominal pace:
--   six passes in 180 s, and 147 s for the two arms to polish 24 places with no joint faster than a 1.75 m
--   collaborative arm's (an ASSUMPTION for this longer arm). Rule 9: the polish is not shortened to keep the seat, so
--   the seat is longer. Three wash bays at 6.5 minutes seat 27 cars an hour against 32 at 5.5. That is a capacity
--   reading for a person, not a reason to hurry an arm.
SELECT param_key, param_value, updated_by, updated_at
  FROM public.ottoq_policy_params
 WHERE param_key = 'robotic_wash_min' AND scope_type = 'depot' AND scope_id = '11111111-1111-1111-1111-111111111111';

-- ══ (5) WHAT IS OPEN ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) "No door opens in the wash bay" is true of the twin's machine in every seat: in a detail seat it holds, parked
--       and dry (cabin_hold). The engine still gives detail seats (§2), times them at 16.5 minutes and credits cabin
--       work to them. So a bay is held for cabin time in which nothing cleans a cabin. For a car with no visit, the
--       seat is the only door its cadence deep clean has (the arm reads a visit's atoms), so rule 9 keeps it.
--   (b) A DECISION FOR CHASE, not made here: a car flagged minor_cosmetic or wash_due is given a detail seat. With the
--       cabin cleaned at the post, should that seat be a wash seat (6.5 minutes), and what does a touchless bay do for
--       a cosmetic flag?
--   (c) 0816 §2(e), the deep program taken up at the next post after a charger fault, is proved by its self-test and
--       not yet seen on a run.
