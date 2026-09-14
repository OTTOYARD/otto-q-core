-- 0218  THE ARMING RITUAL HAD NO PERFORMER, SO THE LOOP BECAME ONE
--
-- Read-only. The fix this file records is in Python, not SQL
-- (bridge/proposer_bridge.py), because that is where the gap was.
--
-- ===========================================================================
-- THE GAP, RESTATED FROM 0214 AND THEN MEASURED ACROSS EVERY RUN
--
-- 0278 built public.ottoq_agentic_arm: one call, run scope, all-or-nothing,
-- every ottoq_policy_set receipt read rather than assumed, and a certification
-- arm refused outright with ERRCODE 42501. It is a good function. Nothing
-- called it.
--
-- The census below is the point. `proposer_frame_facts` has been readable by
-- ottoq_build_decision_frame since 0265 and has been set on exactly ONE run in
-- the database's life -- and that run is `proposer_facts_probe`, created at
-- 04:17 UTC on 2026-09-14 to MEASURE the blindness. Every run that actually
-- proposed was blind.

SELECT '1. every run that has ever carried a frame-facts row' AS section;
SELECT r.run_by, r.sim_run_id, r.status, p.param_value, p.updated_by, p.updated_at
  FROM public.ottoq_policy_params p
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = p.scope_id
 WHERE p.param_key = 'proposer_frame_facts'
 ORDER BY p.updated_at;

SELECT '2. the runs that actually proposed, and whether they were armed' AS section;
SELECT r.run_by,
       count(*)                                        AS runs,
       count(*) FILTER (WHERE a.verdict = 'armed')     AS armed,
       count(*) FILTER (WHERE a.verdict = 'unarmed')   AS unarmed,
       count(*) FILTER (WHERE a.verdict = 'partial')   AS partial,
       max(r.started_at)                               AS latest
  FROM public.ottoq_sim_runs r
  CROSS JOIN LATERAL (
    SELECT (public.ottoq_agentic_arming(r.sim_run_id)->>'verdict') AS verdict) a
 WHERE r.run_by LIKE 'proposer%'
 GROUP BY 1 ORDER BY 1;

SELECT '3. what the fire log already knew and nobody read' AS section;
-- The bridge has recorded `frame_facts_version` on every fire record since
-- 0265 (bridge/proposer_bridge.py:245, "feature-detected off the frame's own
-- selector block, never assumed and never configured"). The evidence that the
-- proposer was blind was therefore sitting in the ledger the whole time. A
-- field that is recorded and never asserted on is a field that documents a
-- defect instead of preventing one.
SELECT COALESCE(fire->>'frame_facts_version', '(null)') AS frame_facts_version,
       count(*) AS fire_rows, min(fired_at) AS first_seen, max(fired_at) AS last_seen
  FROM public.ottoq_proposer_fire_log
 GROUP BY 1 ORDER BY 2 DESC;

-- ===========================================================================
-- THE FIX, AND WHY IT IS TWO INDEPENDENT HALVES
--
-- bridge/proposer_bridge.py now does both of these on the live path, and the
-- separation is deliberate:
--
--   1. _arm_run()             calls ottoq_agentic_arm on the resolved run,
--                             once per run rather than once per fire, and
--                             refuses unless the run afterwards REPORTS
--                             verdict='armed'. ok:true is a claim about the
--                             call; the verdict is a claim about the run, and
--                             a partial arm cannot pass as a whole one.
--
--   2. _require_seeing_frame() reads selector.facts_version off the frame that
--                             actually came back and refuses to plan without
--                             it, raising BlindFrameError.
--
-- (2) does not trust (1). Arming is what was ASKED FOR; facts_version is what
-- ARRIVED; and the distance between those two is the entire finding of 0214.
-- Half a fix here would be a loop that arms and then plans against whatever it
-- gets, which is exactly the posture that produced 329 blind proposals.
--
-- Both are default-on. --no-arm and --allow-blind-frame exist for measurement
-- and are explicit, because this session has now found the same shape four
-- times: apparatus built, switch left off, nobody's job to flip it.
--
-- WHAT IT IS WORTH, measured at tick 4 on the flagship depot (0215):
--   blind frame   25 charge points offered to the solver
--   facts frame    0                (24 reserved_by the door, 1 charger faulted)
-- The solver was not choosing badly among scarce points. It was choosing among
-- points that were already gone, and the door refused every enactment it could
-- not honour -- which is why the shield held and the proposals simply died.
--
-- AND ARMING CLOSES A SECOND HOLE ON THE WAY PAST. _resolve_run refuses a
-- certification arm under --run auto, but an EXPLICIT --run <uuid> was only
-- guarded by the process-level _cert_in_flight check -- so a cert arm that was
-- not mid-transaction could be proposed into. ottoq_agentic_arm refuses
-- run_by='cert_harness' with 42501, so arming now guards that path too.

-- ===========================================================================
-- RESULTS, run 2026-09-14 ~06:40 UTC (1:40 AM CT), before the fix is exercised
--
-- Section 1 -- every run that has ever carried a proposer_frame_facts row:
--   ONE row. run_by = 'proposer_facts_probe', value 1, written 04:17:26 UTC
--   on 2026-09-14 by the probe created to measure the blindness.
--
-- Section 2 -- the runs that actually proposed:
--
--   run_by                 runs   armed  unarmed  partial   latest
--   proposer_live             6       0        6        0   2026-09-14 01:27
--   proposer_demo             2       0        0        2   2026-09-13 01:17
--   proposer_facts_probe      1       1        0        0   2026-09-14 04:17
--
--   Not one live run was armed. The two demo runs are `partial` -- they carry
--   proposer_hold_enabled and not the facts gate, which is 0214's shape again:
--   a multi-key ritual performed in part, by hand, and never checked.
--
-- Section 3 -- what the fire log already knew:
--
--   frame_facts_version   fire_rows   proposals   first_seen        last_seen
--   (null)                        4          90   2026-09-13 00:45  2026-09-13 01:32
--
--   ONE distinct value across every fire row this table has ever held, and it
--   is null. The bridge has recorded the field since 0265 precisely so the
--   frame contract could not be inferred -- and in the whole life of the
--   ledger it has never once been non-null. The measurement was right there,
--   correct, and load-bearing on nothing.
--
--   (The count is 4 rows / 90 proposals rather than 329 because of the OTHER
--   default-off in this family: the loop ran --via door, and the door route
--   writes no fire record at all. Fixed the same day; see the comment block in
--   .github/workflows/proposer-loop.yml and 0214's correction section. The
--   fire log is a sample of the fires, not a census of them, for everything
--   before 2026-09-14.)
--
-- ===========================================================================
-- THE PATTERN, NOW AT FIVE INSTANCES IN ONE SESSION
--
--   proposer_frame_facts     built 0265, never set anywhere   (this file)
--   proposer_seat            dispatched on, never catalogued  (0279)
--   the fire ledger          written only on --via batch      (0214 correction)
--   exec-digest's classifier exempted every $$ region         (scripts/)
--   ottoq_agentic_arm        built 0278, never called         (this file)
--
-- Every one is the same shape: the apparatus was built correctly and the
-- switch that makes it do anything was left off, with nobody named as the one
-- who flips it. The defect is never in the mechanism. It is in the absence of
-- a performer. Where a default can be on, this repo now puts it on and makes
-- the opt-out explicit and named.

-- ===========================================================================
-- THE GUARD'S PREDICATE, VERIFIED AGAINST THE LIVE FRAME BUILDER
-- 2026-09-14 ~06:50 UTC (1:50 AM CT). Read-only; ottoq_build_decision_frame
-- called twice at the same moment on the same depot, differing only in which
-- run id (and therefore which policy scope) it was asked for.
--
--   run                              facts_version  stalls  with `offerable`
--   09a1e9d1 proposer_facts_probe    1                 158               158
--   d775f104 proposer_live           (null)            158                 0
--
-- Identical world, identical stall count, and the unarmed run's frame carries
-- the `offerable` key on NOT ONE of its 158 stalls. That is exactly the
-- predicate _require_seeing_frame() tests, so an unarmed run is refused before
-- the solver ever sees a point, and an armed run is handed the door's own
-- verdict on every stall at the depot.
--
-- (offerable=true was 40 of 158 at this reading because the depot is idle --
-- no run is ticking, so nothing is reserved. The contention number that
-- matters is 0215's, taken under load at tick 4: 25 offered blind, 0 with the
-- facts. The gate's value is a function of contention, which is to say it is
-- largest exactly when scheduling matters.)
--
-- STILL UNPROVEN AT THIS WRITING, and named rather than glossed: no CP-SAT
-- fire has yet gone out against an armed frame. The DB half is proven above,
-- the Python half is unit-tested (bridge/test_proposer_bridge.py, six cases
-- covering both halves and the partial-arm refusal), and the two have not yet
-- met in a live fire. The first one will be the first non-blind proposal in
-- this engine's history, and the fire log will say so in a column that has
-- read null on every row it has ever held.
