-- 0486  **The twin depot has no L2; and a car to charge is cleaned during its charge, on its first run.**
--        (0821 seen working; four open items of db/checks/0485 closed; one reading of mine corrected)
--        Production, 2026-11-12, 20:25-21:35 UTC (2:25 to 3:35 PM CT). Rule 8: the twin depot.
--        Rule 12: one demo run to show a finished change working; no pair, no sweep. Single runs: readings, not ranges.
--
-- ══ (1) A READING OF MINE, CORRECTED: THERE IS NO L2 AT THE TWIN DEPOT ══════════════════════════════════════════════════
--
--   Chase, 2026-11-12: "I thought we switched all chargers from L2 to DCFC Robotic arm chargers?" Yes. 0763 did.
SELECT s.stall_type::text, s.stall_kind, count(*) FROM public.stalls s
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' GROUP BY 1, 2 ORDER BY 1, 2;
--     dcfc/charging 30 · wash_bay 3 · service_bay 2 · staging 113 (12 inspection) · parking/retired 10 · l2 0
--   0820 §3 and §4, its applied note ("with L2s standing free"), db/checks/0485 §1 to §3 and both PRs spoke of a car
--   that could have taken a free L2, and of two doors that can seat on one. None of it can happen here. I wrote it
--   from 0820's source and did not read the depot's stalls. So, of 0485's open items:
--     - "the stranded-recharge door and the auto-assign can still seat on an L2": NOT APPLICABLE at this depot.
--     - "the cost of one stop, not two": NO car is kept from an L2, because there is none. 0820's two L2 guards are
--       not reached (0 declines on both runs). They stay, for a depot that has L2s.
--
-- ══ (2) WHAT RUN 0e3cc3c2 DID SHOW, READ TO ITS END: SIX OF TEN CABIN STOPS WERE A SECOND TRIP ═════════════════════════
--
--   10 stops, all done, waits 0.3 to 8.7 minutes. 6 were cars that had charged on a post in the same visit and were
--   sent to another post 0.3 to 0.5 minutes after the charge ended. Each went arrived_at_gate -> charging_dcfc with no
--   deep-clean atom on its visit. 0820 (c) wrote the atom only for a staged_awaiting_service car, after the charge
--   step. 0821 writes it before the charge step, for a car at the gate, parked or charging.
--
-- ══ (3) RUN 02ca304f (busy_day, operator_demo, live at 8x; started 20:25 UTC after 0821; ended 21:34:00 UTC) ═══════════
--
--                                               0e3cc3c2 (before 0821)    02ca304f (after 0821)
--     cabin stops seated                        10                        8
--     of them a second trip after a charge      6                         2
--     cabin cleans done during the charge       14 at the end + 7 running 39 (15 of them raised by the needs card)
--     cabin work seated in a wash bay           0                         0
--   Different seeds. Not a pair. The direction is what the change was built for; the size is one run's.
--   THE TWO SECOND TRIPS THAT REMAIN. One read: car c3333333-0003 charged 16:53 to 17:52 with no clean on its visit,
--   and was seated for a stop at 19:46. The needs card had not raised the clean during the charge, or 0821 (a) would
--   have written it. Why the card raised it later is NOT established. The other was not read.
--
-- ══ (4) A STOP'S DECISION ROW NOW SAYS WHAT ITS POST'S CHARGER WAS (0485 §2's open item) ═══════════════════════════════
SELECT to_char(d.sim_clock, 'HH24:MI') AS seated_sim, d.entity_id AS car, d.context_frame->>'cabin_stop_post_charger' AS charger,
       d.context_frame->>'wait_min' AS wait_min,
       (SELECT s.stall_code FROM public.stalls s WHERE s.id = (d.proposed_action->>'stall_id')::uuid) AS post
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = '02ca304f-fa79-4ca5-bac5-62661646860a' AND d.proposed_action->>'source' = 'cabin_post_stop'
   AND d.outcome_status = 'enacted' ORDER BY d.sim_clock;
--   7 of the 8 stops stood on a post whose charger read Faulted when the car was seated (posts 15, 06, 06, 06, 05, 05
--   and one more); 1 stood on an Available post. So a faulted post is taken first, as 0820 says, on a live run.
--   Waits: 1.1 to 112.7 minutes. Four waited 30 to 47 minutes and one 112.7. A car with no charge to do waits when no
--   post is free, faulted or not. That is queueing (rule 9), and it is a capacity reading, as db/checks/0484 §4 was.
--
-- ══ (5) THE TWIN ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   CHECKED: the twin's test for a cabin stop on a faulted post FAILS with its change taken out (the car is drawn on
--   DCFC-06, not its own post DCFC-01) and passes with it. That was not checked when ottoyarddepot-sim #167 went up.
--   NOT SEEN: the live view on such a stop. A watcher on the headless view ran from sim 14:46 to the run's end and
--   caught no stop with its arm out. At 8x the headless view lags the run, as it did for db/checks/0484 §5 (e).
--
-- ══ (6) WHAT IS OPEN ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Two second trips remain (§3). One is a clean the card raised after the charge; the cause is not established.
--   (b) A clean written late in a charge may not finish before the charge does (0821 §5). Not measured.
--   (c) A cabin stop can wait a long time for a post on a busy day (§4): 112.7 minutes once.
--   (d) The live view on a faulted-post stop (§5).
