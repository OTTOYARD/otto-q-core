-- 0485  **Cabin stops on faulted posts, and one stop for a charge and a clean, on their first run.** (0820 seen working)
--        Production, 2026-11-12, 16:34-16:44 UTC (10:34 to 10:44 AM CT). Rule 8: the twin depot.
--        Rule 12: one demo run to show a finished change working; no pair, no sweep. A single run: readings, not ranges.
--
-- ══ (1) RUN 0e3cc3c2 (busy_day, operator_demo, live at 8x; started 16:34:26 UTC, 9 seconds after 0820) ═════════════════
--
--   Read at 16:43:33 UTC, sim 15:12 of a day that began at sim 14:00 (72 sim minutes):
--     - cabin stops: 4 seated, 4 ended with the clean done by the post's arm (10.8 minutes each). NONE waited the
--       90-minute floor. Their waits were 1.2, 2.1, 8.7 and 1.2 minutes. On run 56d8465f, before 0820, every stop
--       waited 90.4 to 93.7 minutes (db/checks/0484 §2). The two runs are different seeds and are not a pair.
--     - each post was freed 4 to 23 seconds after its arm was home, and was used again: two stops each on
--       NASH-DCFC-STALL-21 and NASH-DCFC-STALL-30.
--     - interior deep cleans: 19 done, all by a post's arm (15 during a charge, 4 on a cabin stop), 9 under way at a
--       post, 4 pending. None in a wash bay: 0 detail legs there.
--     - no car with a deep clean to start was charging on an L2. 4 such cars were waiting to charge, the longest 23
--       minutes.
--     - no fast-charger post held a car that did not point back at it (the G121 shape).
SELECT to_char(d.sim_clock, 'HH24:MI:SS') AS seated_sim, left(d.entity_id::text, 8) AS car, d.outcome_status,
       d.context_frame->>'waited_the_floor' AS waited_the_floor, d.context_frame->>'wait_min' AS wait_min,
       (SELECT s.stall_code FROM public.stalls s WHERE s.id = (d.proposed_action->>'stall_id')::uuid) AS post
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = '0e3cc3c2-708d-48d9-84c0-22539f6439d3' AND d.proposed_action->>'source' = 'cabin_post_stop'
 ORDER BY d.sim_clock;
--
-- ══ (2) WHAT THIS READING DOES AND DOES NOT ESTABLISH ══════════════════════════════════════════════════════════════════
--
--   ESTABLISHED: the stops no longer queue behind the charge line. NASH-DCFC-STALL-30's charger read Faulted at the
--   reading, with two stops done on it and no car on it.
--   NOT ESTABLISHED: that each post's charger was Faulted at the moment its stop was seated. The decision row does not
--   record the charger's state, and the signed event stream carries no charger state change for these two chargers.
--   NASH-DCFC-STALL-21 held a charging car at the reading, so it was Available at some point. 0820's V3 is the
--   evidence that a faulted post is taken (staged, rolled back). A stop's decision row should carry its post's charger
--   state; that is a small change and is not made here.
--   NOT SEEN: the charge step declining a proposer's answer for a car with a clean to do (0 such decisions). The
--   kernel's own proposer never offered such a car an L2, which is the first of 0820's two guards doing the work.
--
-- ══ (3) THE COST OF "ONE STOP, NOT TWO", NOT YET MEASURED ══════════════════════════════════════════════════════════════
--
--   A car with a charge and a clean to do now waits for a fast post where it could have taken a free L2. On this
--   reading 4 cars were in that line, the longest 23 minutes. How much longer than before that is, per car and per
--   owner (rule 14), needs the run's end and a run to compare, and is not claimed here.
