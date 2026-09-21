-- 0317  **RETRACTION. "The cockpit's run-history path is broken" is false for the surface Chase
--       actually uses, and I told him so twice** — once in the merge-readiness verdict and again in
--       the status that followed it. The component carrying the broken call sites is imported by
--       nothing.
--
-- ══ WHAT WAS CLAIMED ═══════════════════════════════════════════════════════
--
-- That the cockpit's Run History (list / compare / save / rename / delete) is unreachable because
-- its generated Supabase client points at project `hfjaofyfxsyniohdfacg`, which is not in this
-- organization. The call sites named were `runPersistence.ts:70` and `historyStore.ts:46/60/68`,
-- all `.from('simulation_runs')`.
--
-- **Every one of those call sites is real, points where it was said to point, and is dead code.**
--
-- ══ WHAT IS ACTUALLY MOUNTED ═══════════════════════════════════════════════
--
--   src/components/layout/SidePanel.tsx:27
--     history: TwinHistoryTab,   // backend run-history ledger + compare
--
-- `TwinHistoryTab` reads `twin.runs(30)`, which is
-- `GET ${OTTOQ_SUPABASE_URL}/functions/v1/otto-twin-control/sim_runs?limit=30` — the edge function,
-- under **service_role**, against **otto-q-core**. Its own header comment says so: *"(ottoq_twin_run_list
-- via GET /sim_runs). Replaces the legacy client-engine..."* That path never touched the dead
-- project and was never affected by `0198`'s anon revoke.
--
-- The legacy chain is a closed loop with no entry point:
--
--   HistoryTab.tsx  ->  historyStore  ->  simulation_runs   (HistoryTab imported by NOTHING)
--   SimulationEngine ->  runPersistence ->  simulation_runs  (SimulationEngine imported by NOTHING;
--                                                             it appears only inside comments in
--                                                             rng.ts and sitePlan.ts)
--
-- ══ HOW I GOT IT WRONG, AND IT IS THE SAME MISTAKE FOR THE FOURTH TIME ═════
--
-- A grep found four call sites against a dead project ref. I checked that the ref was dead. **I did
-- not check whether anything reaches the file the call sites live in.** A call site is only a defect
-- if something can call it.
--
-- The running tally, all four inside two days:
--   (a) `0313` — "the cockpit never reads `ottoq_decisions`", from a grep matching only
--       `.from('literal')` while the live surface used `.rpc()` on a different client.
--   (b) "no function writes `model_parameters`" — false; `otto-q-api` has `updateModelParameters`.
--   (c) `0314` — "a demo run is never archived", from a `pg_proc` census that could not see the
--       edge function that archives it.
--   (d) this one.
--
-- **(a), (c) and (d) share one shape: the evidence was a search over ONE layer of a three-layer
-- system (database / edge function / client), and the answer lived in a different layer.** (a) and
-- (c) missed the edge function; this one missed the module graph. `0314` already drew the lesson as
-- *"pg_proc is not the whole engine"*; the general form is stronger and is what should be quoted:
-- **a negative claim needs a census of every layer that could contain the answer, and for client
-- code "does this file exist" is not the question — "does anything import it" is.**
--
-- **The one-line check that settles this class in a client repo**, and which I now run before
-- calling any component broken:
--
--     grep -rn "from '@/components/tabs/<Component>'" src/    # empty => unmounted, and dead code
--
-- ══ WHAT IS AND IS NOT FIXED ═══════════════════════════════════════════════
--
-- **Nothing needed fixing, and nothing was changed.** Run History works today.
--
-- **The dead code is deliberately NOT deleted.** `src/engine/rng.ts` describes `SimulationEngine` as
-- *"the client-side fallback that runs when the backend..."*, so the legacy chain may be an
-- intentional fallback rather than an oversight. Deleting a documented fallback on my own reading of
-- its import graph is exactly the kind of confident wrong move this file is retracting. Flagged for
-- Chase to decide, not removed.
--
-- **What remains true from the original finding:** four call sites do point at
-- `hfjaofyfxsyniohdfacg`, a project outside this organization. That is worth knowing — if anyone
-- ever re-mounts `HistoryTab`, it will fail. It is a latent trap, not a live defect, and those are
-- different things that must not be reported in the same words.

\echo '=== 0317 §1 — nothing to assert in the database; the evidence is the client module graph ==='
SELECT 'This retraction is about ottoyarddepot-sim, not otto-q-core.'          AS scope,
       'TwinHistoryTab -> twin.runs() -> otto-twin-control edge fn (service_role)' AS live_path,
       'HistoryTab -> historyStore -> simulation_runs (imported by nothing)'   AS dead_path;

\echo '=== 0317 §2 — the edge function IS the live path, and it is reachable ==='
SELECT p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE')         AS anon_direct,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname IN ('ottoq_twin_run_list','ottoq_twin_run_context')
 ORDER BY 1;
-- Both now hold anon too (0405), but that is BESIDE the point for this surface: TwinHistoryTab
-- reaches them through otto-twin-control under service_role and always could. 0405 did not fix run
-- history, because run history was not broken.

\echo '=== 0317 §3 — the run ledger the live path reads is populated ==='
SELECT count(*) AS archived_runs,
       count(*) FILTER (WHERE reason = 'operator_stop')            AS operator_stopped,
       to_char(max(archived_at), 'YYYY-MM-DD HH24:MI')             AS newest
  FROM public.ottoq_run_archives;
-- A history tab with nothing to show would be a different complaint; this is not that.
