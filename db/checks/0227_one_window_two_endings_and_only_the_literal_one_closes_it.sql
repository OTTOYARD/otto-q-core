-- db/checks/0227
-- G64  ONE WINDOW, TWO ENDINGS, AND ONLY THE HARD-CODED ONE CLOSES IT
--
-- Found while reading twin.ottoq_sim_auto_dispatch_tick to derive a catalog
-- range for overnight_recall_end_hour (migration 0298). The dial is now
-- catalogued 0..23 WITH this caveat written into its own description row; the
-- code is NOT changed here, because changing it moves a tick path and that is
-- forces_recert=TRUE.
--
-- ===========================================================================
-- A. WHAT THE CODE ACTUALLY SAYS
--
-- twin.ottoq_sim_auto_dispatch_tick, lines 114-120:
--
--   v_recall_on := ottoq_policy_get(p_sim_run_id,'overnight_recall_enabled',1) > 0;
--   v_win_start := ottoq_policy_get(p_sim_run_id,'overnight_recall_start_hour',22)::int;
--   v_win_end   := ottoq_policy_get(p_sim_run_id,'overnight_recall_end_hour',3)::int;
--   v_hyst      := ottoq_policy_get(p_sim_run_id,'overnight_recall_hysteresis',2)::int;
--   ...
--   IF v_recall_on AND (v_hour >= v_win_start OR v_hour < 6) THEN
--                                                          ^^^
--                                               a literal, not v_win_end
--
-- v_win_end is NOT dead. It goes two other places:
--
--   line 126  p_win_end := v_win_end  ->  ottoq.ottoq_plan_dispatch_tick, whose
--             eligibility filter (its line 120) is
--                 AND ((p_hour >= p_win_end AND p_hour < p_win_start)
--                      OR NOT ottoq_is_overnight_holdout(v.id, ...))
--             -- so once p_hour reaches p_win_end the FIRST branch is true for
--             every vehicle and the per-vehicle holdout is never consulted.
--
--   line 157  'holdout_active', NOT (v_hour >= v_win_end AND v_hour < v_win_start)
--             -- the reported flag, computed from the same boundary.
--
-- So the overnight recall window has TWO endings:
--   * the hour the WINDOW CLOSES            = 6, a literal, not settable
--   * the hour the HOLDOUT STOPS APPLYING   = overnight_recall_end_hour, default 3
--
-- Between them -- 03:00 to 05:59 America/Chicago at the defaults -- the window
-- is open and the holdout is off, so recall is unfiltered.
--
-- ===========================================================================
-- B. THIS IS NOT THEORETICAL. MEASURED 2026-09-14 over the whole live event
--    stream (public.ottoq_events, event_type='twin.overnight_surplus_recall'):
--
--   hour_cst | holdout_active | events | vehicles recalled
--   ---------+----------------+--------+------------------
--       0    | true           |   97   |   482
--       1    | true           |    2   |     2
--       2    | true           |    6   |   140
--       3    | FALSE          |    2   |     3
--      22    | true           |  185   |  2841
--      23    | true           |  123   |  1070
--
-- The flag flips to false at EXACTLY hour 3 -- the dial's value -- while the
-- window is still open, and three vehicles have been recalled through the gap.
-- Hours 4 and 5 have no events yet; the exposure is bounded by how often the
-- twin runs in that band, not by anything in the code.
--
-- Small, but it is the boundary landing precisely where the source says it
-- would, which is the confirmation that matters.
--
-- ===========================================================================
-- C. WHAT IS AND IS NOT BEING CLAIMED
--
-- NOT claimed: that the unfiltered tail is a bug. "In the last three hours of
-- the window, recall everyone regardless of holdout" is a defensible policy and
-- nothing in the source says it was unintended. There is no comment either way.
--
-- Claimed, and sufficient on its own: ONE WINDOW HAS TWO BOUNDARIES, ONE
-- SETTABLE AND ONE HARD-CODED, AND ONLY THE HARD-CODED ONE CLOSES IT. The
-- consequences are all of the silent kind --
--
--   * setting overnight_recall_end_hour to 8 does NOT extend the window; it
--     widens the unfiltered tail from three hours to five;
--   * setting it to 6 does not shorten the window; it removes the tail;
--   * setting it to 22 does not close the window at 22; it makes the holdout
--     apply for the entire window;
--   * and the event stream's holdout_active reports the planner's boundary,
--     which is the one that is NOT closing the window -- so a reader checking
--     the events would conclude the window ended at 3.
--
-- A dial whose name says one thing and whose effect is another is exactly what
-- 0297 catalogued tech_approvals_required for, and this one is worse: it half
-- works, so it survives a casual test.
--
-- ===========================================================================
-- D. THE FIX, WHEN A CERT WINDOW EXISTS
--
-- Either
--   (a) replace the literal with the dial, so the window closes where the dial
--       says -- and REPORT the behaviour change, because the current 03:00-05:59
--       unfiltered tail disappears and recall volume in that band changes; or
--   (b) keep both boundaries and NAME them apart --
--       overnight_recall_window_end_hour (the gate, currently 6) and
--       overnight_holdout_end_hour (what this dial actually does) -- so the
--       split is declared instead of latent.
--
-- (b) is the smaller change and the more honest one: it preserves every
-- existing number and makes the two-boundary design visible. (a) is a
-- behaviour change that needs a paired run to quantify.
--
-- Either way it is forces_recert = TRUE and it does not ride along with a
-- catalog file.
--
-- ===========================================================================
-- E. THE GUARD THAT KEEPS THIS HONEST
--
-- 0298's P5 pins BOTH source lines. The day someone replaces the literal 6, or
-- changes the planner's p_win_end filter, that precondition fails -- so the
-- caveat written into overnight_recall_end_hour's catalog description cannot
-- quietly outlive the thing it describes.
--
-- Re-run this to re-measure section B:

SELECT (payload->>'hour_cst')::int      AS hour_cst,
       (payload->>'holdout_active')::boolean AS holdout_active,
       count(*)                          AS events,
       sum((payload->>'recalled')::int)  AS vehicles_recalled
  FROM public.ottoq_events
 WHERE event_type = 'twin.overnight_surplus_recall'
 GROUP BY 1, 2
 ORDER BY 1, 2;

-- And to re-confirm the split is still in the source:

SELECT 'gate closes on the literal 6' AS what,
       count(*) AS sites
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_auto_dispatch_tick'
   AND position('IF v_recall_on AND (v_hour >= v_win_start OR v_hour < 6) THEN' in p.prosrc) > 0
UNION ALL
SELECT 'planner gates the holdout on p_win_end', count(*)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick'
   AND position('AND ((p_hour >= p_win_end AND p_hour < p_win_start)' in p.prosrc) > 0;
