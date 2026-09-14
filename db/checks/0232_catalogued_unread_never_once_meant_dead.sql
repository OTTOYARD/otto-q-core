-- db/checks/0232
-- "catalogued_unread" NEVER ONCE MEANT DEAD, AND I REPEATED THE CLAIM THAT IT DID
--
-- 0307 fixed the dial audit so it can see a view, and left five dials in
-- `catalogued_unread` -- the status this repo has been treating as a DELETE
-- LIST. I then checked all five before deleting anything.
--
-- NOT ONE OF THE FIVE IS A DIAL FOR A COMPONENT THAT DOES NOT EXIST.
-- All five are LIVE components that ignore a control surface they declare.
--
-- ===========================================================================
-- A. THE FIVE, MEASURED 2026-09-14
--
-- 1. cuopt_contention_min            111 LIVE ROWS, default 2, range 1..20
--    affects: "ottoq_demo_metronome contention gate"
--    public.ottoq_demo_metronome EXISTS (6,409 chars), HAS A CRON JOB, and
--    READS OTHER DIALS (ottoq_policy_get appears in its body) -- but does NOT
--    read cuopt_contention_min. A scheduled function that consults the policy
--    layer, skipping the one dial named after it, while 111 rows sit in force
--    doing nothing.
--
-- 2-4. reopt_cooldown_min / reopt_max_per_tick / reopt_min_eta_min
--    affects: "reservation_reopt", 0 live rows each
--    ottoq.ottoq_reoptimize_reservation_book EXISTS (5,591 chars) and IS
--    CALLED FROM public.ottoq_sim_decide_and_dispatch -- a TICK function, so it
--    runs in the decide path. It reads NONE of its three dials, and
--    `ottoq_policy_get` does not appear in its body AT ALL. Three catalogued,
--    bounded, settable knobs for a live decide-path component that consults no
--    policy whatsoever.
--
-- 5. wash_cadence_cycles             0 live rows, default 3
--    affects: "service"
--    The DIAL is unread, but wash cadence as a CONCEPT is read by EIGHT
--    functions including ottoq.ottoq_derive_visit_needs and
--    public.ottoq_recall_naive_threshold_v1 -- from vehicles.config, not from
--    the policy layer.
--
-- ===========================================================================
-- B. SO THE STATUS NAME IS THE DEFECT
--
-- `catalogued_unread` conflates two situations that call for OPPOSITE actions:
--
--   (a) the component does not exist        -> DELETE the catalog row
--   (b) the component exists and ignores it -> WIRE THE DIAL UP
--
-- The natural reading of "unread" is (a). In this database the answer is (b),
-- five times out of five. Deleting on that reading would remove the declared
-- control surface of a cron-scheduled function and a decide-path function, and
-- CEMENT the hardcoding it was hiding.
--
-- This is the same shape as 0307 itself, one layer up. 0307 fixed an instrument
-- that could not see a category of READER. This is an instrument whose CATEGORY
-- NAME asserts a cause it never measured. Neither is a wrong number; both are a
-- right number answering the wrong question, which is the defect class that has
-- cost this build more than any other (0098, 0137/0139/0216, 0145/0146, 0227,
-- 0231, 0296, 0304, 0307).
--
-- ===========================================================================
-- C. AND I PROPAGATED THE CLAIM INSTEAD OF CHECKING IT
--
-- 0307's header states that the three reopt_* rows "document a reservation
-- re-optimizer that does not exist in this database." THAT IS FALSE. I took it
-- from the six-dimension audit's read_bypass finding 2 and wrote it into a
-- migration header without measuring it -- in the same file whose entire
-- subject is an instrument that reported something as absent because it had not
-- looked properly.
--
-- 0307's executable content is unaffected: its A4 asserts the LIST of five key
-- names, which is correct, and it deletes nothing. The applied SQL stands. A
-- correction footer is appended to 0307 rather than editing its body, per the
-- precedent 0301 set -- the file that ran is the file that is committed.
--
-- The audit was right that the reopt_* knobs are four literals. It was wrong
-- that the component is absent. The first half is the actionable half and I
-- should have kept only that.
--
-- ===========================================================================
-- D. WHAT TO DO WITH EACH, now that the cause is known
--
--   cuopt_contention_min   Decide WITH the cuOpt cut (task #116). If the
--                          metronome's contention gate stays, wire the dial;
--                          if the gate goes, delete the row AND the 111 param
--                          rows -- in that order, because 0305's FK now
--                          RESTRICTs deleting a catalog row that is in force.
--   reopt_*  (x3)          G66 (task #131), literals half. The component is
--                          live in the decide path and reads no policy at all,
--                          so wiring it is a behaviour change:
--                          forces_recert = TRUE, own cert window.
--   wash_cadence_cycles    Decide which source of truth wins, vehicles.config
--                          or the policy layer. Two sources of truth is the
--                          G54 class. Until then the row is a claim the engine
--                          does not honour.
--
-- NOTHING IS DELETED, and on this evidence nothing should be deleted yet.
--
-- ===========================================================================
-- E. RE-MEASURE -- the triage, not just the list

SELECT g.param_key, g.live_rows, c.affects
  FROM public.ottoq_policy_catalog_gap g
  JOIN public.ottoq_policy_param_catalog c USING (param_key)
 WHERE g.status = 'catalogued_unread'
 ORDER BY g.live_rows DESC, g.param_key;

-- for each named component: does it EXIST, is it REACHABLE, and does it read
-- the policy layer at all? A 'true' in exists with 'false' in reads_its_dial is
-- case (b) -- wire it up, do not delete the row.
SELECT n.nspname||'.'||p.proname                       AS component,
       length(p.prosrc)                                 AS src_len,
       (p.prosrc ~ 'ottoq_policy_get')                  AS reads_any_dial,
       (p.prosrc ~ 'cuopt_contention_min')              AS reads_contention_dial,
       (p.prosrc ~ 'reopt_')                            AS reads_reopt_dials,
       COALESCE((SELECT string_agg(n2.nspname||'.'||p2.proname, ', ')
                   FROM pg_proc p2 JOIN pg_namespace n2 ON n2.oid = p2.pronamespace
                  WHERE n2.nspname IN ('public','ottoq','twin')
                    AND p2.proname <> p.proname
                    AND p2.prosrc ~ p.proname), '(no in-database caller)') AS callers,
       (SELECT count(*) FROM cron.job j WHERE j.command ~ p.proname) AS cron_jobs
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.proname IN ('ottoq_demo_metronome','ottoq_reoptimize_reservation_book')
 ORDER BY 1;

-- wash cadence: read everywhere, just not from the policy layer
SELECT 'wash cadence readers (not via the dial)' AS what,
       string_agg(DISTINCT n.nspname||'.'||p.proname, ', ') AS fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc ~ 'wash_cadence';
