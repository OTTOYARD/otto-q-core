-- 0489  The first seats under charge_port_side_routing (migration 0824), read on the run that was live at the apply.
--
-- Run a95e51a3 (operator_demo, busy_day), twin depot 11111111-1111-1111-1111-111111111111. 0824 was applied at
-- 2026-11-13 04:42:22 UTC with this run live. Read at 2026-11-13 04:54:05 UTC (2026-11-12, 10:54 PM CT), 11 min 43 s
-- after the apply; the run's sim clock was 18:10.
--
-- WHAT WAS READ. Decisions of that run written after the apply (4,146), and of them the ones that enacted a post
-- with an arm side (49).
--
--   vehicle kind      inlet        posts taken since the apply
--   Jaguar I-PACE     left         12, all left-arm
--   Tesla Model Y     left          9, all left-arm
--   Zeekr (Ojai)      left          1, left-arm
--   Zoox              either side  23, all right-arm
--   Tesla Cybercab    rear          4, all right-arm
--
--   22 of 22 left-port seats are on left-arm posts. 27 of 27 seats of cars that fit both sides are on right-arm
--   posts, so the side preference (0824 (d)) held every time it was asked. 22 proposals were declined with
--   waits_for_a_post_on_its_charge_port_side.
--
-- WHAT THIS IS NOT. It is 12 minutes of one run. It says the rule is followed; it does not say what the rule costs.
-- The wait of left-port cars for 15 posts against the same run without the rule is not measured here, and one live
-- run cannot measure it (CLAUDE.md 2.5, the live twin's noise floor). The 11 left-port cars that stood on right-arm
-- posts at the apply were seated before it and were not moved.

WITH applied AS (SELECT '2026-11-13 04:42:22+00'::timestamptz AS t),
     d AS (SELECT d.* FROM public.ottoq_decisions d, applied a
            WHERE d.sim_run_id = 'a95e51a3-d8a2-47b1-86a0-ff3bdd5e0538' AND d.created_at > a.t)
SELECT (public.ottoq_vehicle_port_profile(d.entity_id)).profile_key AS vehicle_kind,
       public.ottoq_stall_arm_side(NULLIF(d.enacted_action->>'stall_id', '')::uuid) AS arm_side,
       d.outcome_status, count(*) AS n
  FROM d
 WHERE d.enacted_action->>'stall_id' IS NOT NULL
   AND public.ottoq_stall_arm_side(NULLIF(d.enacted_action->>'stall_id', '')::uuid) IS NOT NULL
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

WITH applied AS (SELECT '2026-11-13 04:42:22+00'::timestamptz AS t)
SELECT count(*) AS declined_for_side
  FROM public.ottoq_decisions d, applied a
 WHERE d.sim_run_id = 'a95e51a3-d8a2-47b1-86a0-ff3bdd5e0538' AND d.created_at > a.t
   AND (d.proposed_action::text LIKE '%waits_for_a_post_on_its_charge_port_side%'
        OR d.enacted_action::text LIKE '%waits_for_a_post_on_its_charge_port_side%');
