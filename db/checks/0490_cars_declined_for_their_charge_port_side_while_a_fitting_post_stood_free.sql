-- 0490  Cars declined for their charge-port side while a post that fits them stood free (0824), and the first run after
--       the fix (0825).
--
-- Twin depot 11111111-1111-1111-1111-111111111111, scenario busy_day, one run each side of the fix. Single readings.
--
-- §1 BEFORE THE FIX. Run a95e51a3 (seed 4132971756675130561), decisions written after 0824's apply
--    (2026-11-13 04:42:22 UTC) to the run's end (05:34:00 UTC; sim 16:33 to 23:30 UTC). Read 05:39 to 05:41 UTC.
--
--      decisions                                     19,370
--      seats on a post with an arm side                 109   (63 left-arm, 46 right-arm)
--      declines waits_for_a_post_on_its_charge_port_side
--                                                     4,454   on 44 cars, in 219 ticks, a mean 20.3 cars a tick
--        by the proposer declined:  forward_lex 3,403 (40 cars) · cuopt 994 (14 cars) · greedy_constrained 57 (12 cars)
--      in those 219 ticks, left-arm posts taken by the calendar:  mean 8.30 of 15 (min 0, max 15)
--        ticks with a left-arm post free                208 of 219
--      of the 44 cars: seated later                      28   mean 103.6 sim minutes after the first decline, max 288.5
--                      not seated before the run ended   16
--
--    WHAT IT SAYS. 0824 declined an external proposer's wrong-side post as an abstention, and the charge step asks the
--    kernel's own proposer only when no external proposal exists (ottoq_honour_reservation_proposal's COALESCE). So the
--    car was not offered the free post that fits it. This was a wait with no cause in capacity: CLAUDE.md rule 9.
--    0489 read the first 12 minutes and saw only that every seat made was on the right side; it did not look at the
--    cars that were not seated. **A rule that refuses is checked by what happens to the refused, not by the seats.**
--    WHAT IT DOES NOT SAY. "Free by the calendar" is one of the three gates of CLAUDE.md Part 3 (pointer, calendar,
--    charger not faulted); the pointer and the fault state at each tick were not read. The 103.6 minutes is from a
--    car's first decline to its next seat; part of it can be an ordinary wait in the line.
--    The 0820 decline (waits_for_a_fast_charger_post_for_its_cabin_clean) fired 0 times on this run.
--
-- §2 AFTER THE FIX (0825, applied 05:42:56 UTC). See the end of this file.

-- §1 queries (run a95e51a3; its engine rows are purged by the next demo start, so these read 0 after that)
WITH d AS (SELECT * FROM public.ottoq_decisions
            WHERE sim_run_id = 'a95e51a3-d8a2-47b1-86a0-ff3bdd5e0538' AND created_at > '2026-11-13 04:42:22+00'),
decl AS (SELECT entity_id, min(sim_clock) first_decl, count(*) n FROM d
          WHERE proposed_action::text LIKE '%waits_for_a_post_on_its_charge_port_side%' GROUP BY 1),
seat AS (SELECT d.entity_id, d.sim_clock, public.ottoq_stall_arm_side(NULLIF(d.enacted_action->>'stall_id','')::uuid) side
           FROM d WHERE d.enacted_action->>'stall_id' IS NOT NULL
                    AND public.ottoq_stall_arm_side(NULLIF(d.enacted_action->>'stall_id','')::uuid) IS NOT NULL),
w AS (SELECT c.entity_id, c.first_decl,
             (SELECT min(s.sim_clock) FROM seat s WHERE s.entity_id = c.entity_id AND s.sim_clock >= c.first_decl) seated FROM decl c)
SELECT (SELECT count(*) FROM d) decisions, (SELECT count(*) FROM seat) seats,
       (SELECT sum(n) FROM decl) declines, (SELECT count(*) FROM decl) cars_declined,
       (SELECT count(*) FROM w WHERE seated IS NOT NULL) seated_after,
       (SELECT round(avg(extract(epoch FROM seated - first_decl) / 60)::numeric, 1) FROM w WHERE seated IS NOT NULL) mean_wait_min,
       (SELECT round(max(extract(epoch FROM seated - first_decl) / 60)::numeric, 1) FROM w WHERE seated IS NOT NULL) max_wait_min;

WITH d AS (SELECT entity_id, sim_clock, tick_seq FROM public.ottoq_decisions
            WHERE sim_run_id = 'a95e51a3-d8a2-47b1-86a0-ff3bdd5e0538' AND created_at > '2026-11-13 04:42:22+00'
              AND proposed_action::text LIKE '%waits_for_a_post_on_its_charge_port_side%'),
ticks AS (SELECT tick_seq, min(sim_clock) t, count(DISTINCT entity_id) cars FROM d GROUP BY 1),
st AS (SELECT s.id, public.ottoq_stall_arm_side(s.id) side FROM stalls s
        WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'dcfc'),
busy AS (SELECT k.tick_seq, k.cars, st.side,
                count(DISTINCT st.id) FILTER (WHERE EXISTS (
                  SELECT 1 FROM ottoq_stall_bookings b
                   WHERE b.sim_run_id = 'a95e51a3-d8a2-47b1-86a0-ff3bdd5e0538' AND b.stall_id = st.id
                     AND b.state IN ('held','active','done','interrupted') AND b.during @> k.t)) taken   -- sim clock, never now()
           FROM ticks k CROSS JOIN st GROUP BY 1, 2, 3)
SELECT side, count(*) ticks, round(avg(taken), 2) mean_taken_of_15, count(*) FILTER (WHERE taken < 15) ticks_with_a_free_post,
       round(avg(cars), 2) mean_cars_declined
  FROM busy GROUP BY 1 ORDER BY 1;
