-- 0313  **I TOLD CHASE THE TWIN COCKPIT WAS "A FAÇADE WIRED TO NOTHING". IT IS LIVE, AND THIS IS THE
--       RETRACTION.** Asked whether the twin UI carries OTTO-Q decision streams, I answered no and
--       said the cockpit *"never reads `ottoq_decisions`"*. **Measured: it polls
--       `ottoq_activity_feed` — the engine's own decision feed — every 4 seconds, scoped to the
--       active run, and that RPC returns a full 200 rows for a real run right now.** The cockpit
--       touches **25+ engine objects**. My grep matched only `.from('literal')` and
--       `functions.invoke('literal')`, and the entire live surface goes through a different client
--       (`ottoQClient`) with `rpc(...)`, so I measured the one dead path and reported it as the whole.
--
--       **Fourth negative-claim error of the day, and the worst of them**, because the previous three
--       were caught inside check files before anyone read them and this one went to Chase as a
--       headline he asked for. Same shape every time: *an assertion about what does not exist, made
--       from having looked in one place.*
--
--       **The learning loop is the one that genuinely has never run — and my mechanism for that was
--       wrong too.** §3.
--
-- Read-only. Measured 2026-09-21 ~17:2x UTC (12:2x CT).
--
-- ══ 1. WHAT THE COCKPIT ACTUALLY READS ═════════════════════════════════════
--
-- `ottoyarddepot-sim` (LIVE per `SYSTEM_TOPOLOGY.md` §9, the in-house r3f renderer + OTTO-TWIN
-- cockpit). Engine objects referenced in `src/`, by count:
--
--   ottoq_twin_snapshot        17      ottoq_external_proposals    6
--   ottoq_intelligence_stack   11      ottoq_arm_timings           6
--   ottoq_sim_runs              9      ottoq_vehicle_dispatches    5
--   ottoq_sim_lane_capacity     8      ottoq_activity_feed         5
--   ottoq_set_playback          6      ottoq_rule_evaluations      4
--   ottoq_ocpp_chargers         6      ottoq_decide_tick           4
--   … plus ottoq_start_demo_run, ottoq_policy_params, ottoq_telemetry_packets,
--     ottoq_visit_needs, ottoq_vehicle_wear, ottoq_twin_depot_layout, and more.
--
-- **The decision stream specifically.** `src/hooks/useActivityFeed.ts` calls
-- `ottoQ.rpc("ottoq_activity_feed", { p_sim_run_id, p_limit: 200 })` on a **4-second** interval
-- (`POLL_MS = 4000`), and `src/components/tabs/TwinDecisionLogTab.tsx` renders it with per-context
-- badges keyed to the engine's own `resolved_action_context` vocabulary — `orchestrator_agent`,
-- `task_start`, `stall_assignment`, `shield_override`, `wash_dispatch`, `service_dispatch`.
--
-- **Verified live, not read from source:** `ottoq_activity_feed(p_sim_run_id, 200)` against run
-- `b4d5f76d` returns **200 rows** — it saturates the limit. The feed is not merely wired, it is full.
--
-- **AND THE TAB IS NOT NAÏVE ABOUT ITS OWN HISTORY**, which is the detail that should have warned me
-- off the façade reading: its comments document that this strip *"used to lie"* because migration
-- `0346` joined the fire log on a key present on 0 of 112 rows, and it now refuses to name a solver
-- the feed did not report. That is a component that has already been through one honesty pass.
--
-- ══ 2. WHAT IS ACTUALLY DEAD — SMALLER, AND A REAL USER-VISIBLE BUG ═══════
--
-- One legacy path, **four call sites, every one cast `(supabase as any)`**:
--
--   src/lib/runPersistence.ts:70    insert  -> simulation_runs   (saveRun)
--   src/store/historyStore.ts:46    select  -> simulation_runs   (fetchRuns)
--   src/store/historyStore.ts:60    delete  -> simulation_runs
--   src/store/historyStore.ts:68    update  -> simulation_runs   (rename)
--
-- **`simulation_runs` exists on NEITHER Supabase project** — not `gxdrc…` (engine), not `ycsis…`
-- (MVP), and no table matching `simulation` exists on the engine at all. So **Run History, run
-- compare, save, rename and delete are all non-functional**: `saveRun` console-errors and returns
-- before its success toast, `fetchRuns` always yields an empty list.
--
-- **AND THE MECHANISM IS THE `as any`.** The generated `src/integrations/supabase/types.ts` contains
-- **exactly one table — `simulation_runs` — and zero `ottoq_*` objects.** So the type generation is
-- pointed at something that is not this engine, the whole live surface is untyped by necessity, and
-- the one table the types DO describe is the one that does not exist. Four `as any` casts then
-- guaranteed the compiler could never say so. **A generated type file is only a guard if it is
-- generated against the database the app actually talks to.**
--
-- ══ 2a. AND IT IS WORSE THAN A MISSING TABLE: A MISSING *PROJECT* ═════════
--
-- `src/lib/ottoQClient.ts` says so in its own header: the generated client in
-- `src/integrations/supabase/client.ts` points at **`hfjaofyfxsyniohdfacg`**, not at the engine.
-- **That project does not exist in this organization.** `list_projects` returns exactly three:
-- `ycsisvozzgmisboumfqc` (MVP), `sovyxwtrqfmizelrammm` (Fleet Dashboard, INACTIVE) and
-- `gxdrcyphqjzjsuhxuqtg` (otto-q-core). `SYSTEM_TOPOLOGY.md` §5.2 already called `hfjao…` dead; this
-- adds that it is not merely dead but **absent from the org**, so `simulation_runs` is not a table
-- someone dropped — it is a table on a database nobody here can reach. `VITE_SUPABASE_URL` is read
-- from `.env`, so what a deployed build talks to is whatever Lovable holds.
--
-- ══ 2b. THE FIX IS AN RPC, NOT A TABLE — AND THE GRANTS SAY WHY ═══════════
--
-- I was about to justify anon write access by pointing at `ottoq_start_demo_run`, which the cockpit
-- calls. **Checked instead of assumed, and the assumption was wrong:** that function is
-- `service_role` ONLY. Measured grants on the engine:
--
--   ottoq_activity_feed        SECURITY DEFINER   anon, authenticated, service_role
--   ottoq_twin_snapshot        SECURITY DEFINER   authenticated, service_role
--   ottoq_decide_tick          SECURITY DEFINER   authenticated, service_role
--   ottoq_start_demo_run       SECURITY DEFINER   **service_role only**
--   ottoq_sim_stop_and_reset   SECURITY DEFINER   **service_role only**
--
-- And `anon` holds only `SELECT` on `ottoq_policy_params` — **no INSERT anywhere**. So the engine's
-- posture is a deliberate gradient: anon reads the decision feed, authenticated reads state,
-- service_role changes the world. **A bare table with anon INSERT would be the first hole in it**,
-- which is why the run-history fix belongs behind SECURITY DEFINER RPCs on the engine project,
-- mirroring how every other cockpit write already works. Specified, deliberately **not built in this
-- pass** — it needs a table, four RPCs, a grant decision, the four app call sites and a regenerated
-- type file, and half of that is worse than none.
--
-- **AND IT SURFACED AN ADJACENT UNKNOWN worth its own look:** `ottoQ` is constructed with the ANON
-- key and `persistSession: false`, so it never authenticates — yet `ottoq_twin_snapshot` (17
-- references, the cockpit's most-used object) and `ottoq_decide_tick` require `authenticated`.
-- Whether those calls succeed in the deployed cockpit is **not established here** and is not assumed
-- either way; it is the next thing to measure about this UI.
--
-- ══ 3. THE LEARNING LOOP: BUILT, NEVER RUN — AND MY FIRST MECHANISM WAS WRONG ══
--
-- I first said *"no function writes `model_parameters`"*. **False.** `edge-functions/otto-q-api`
-- carries the full surface: `getModelParameters`, `getAllModelParameters`,
-- **`updateModelParameters`** (writes `parameters`, `version`, `performance_metrics`), and
-- **`recordPredictionOutcome`** → `prediction_outcomes`. I had grepped `pg_proc` only, and an edge
-- function is not a database function. **The writer exists. It has simply never been used.** Measured:
--
--   model_parameters, all 6 groups   charge_duration · service_duration · arrival_time
--                                    demand_peak · depot_projection · risk_assessment
--   version                          **v1**, every one
--   tuned_by                         **'seed'**, every one
--   last_tuned_at                    **NEVER** (NULL), every one
--   performance_metrics populated    **0 of 6**
--   updated_at > created_at          **0 of 6** — not one row touched since insert
--   prediction_outcomes              **1 row**, for the engine's whole life
--
-- **So the loop is complete as an API and has never closed once.** One prediction outcome was ever
-- recorded; no parameter has ever been tuned; no performance metric has ever been written.
--
-- **AND THE DEEPER REASON IS THAT ITS INPUTS DO NOT SURVIVE**, which no amount of calling
-- `updateModelParameters` would fix. `ottoq_prime` has written dials **1,351 times across 6 keys, and
-- every single write is `scope_type='run'`** — zero at depot scope, zero at global. A run-scoped
-- policy row dies with its run. So the agent's choices, and the outcomes they produced, are gone
-- before anything could correlate them. **`ottoq_ab_pair` is the only function that both reads run
-- outcomes and writes policy, and it is setting up A/B arms, not learning from them.**
--
-- **What exists today is a within-run CONTROL loop** — board → dials → engine → board — which is
-- real and works. What does not exist is any mechanism by which run N+1 is better than run N.
--
-- ══ 4. SO THE ORDER OF WORK IS THE REVERSE OF WHAT I TOLD CHASE ════════════
--
-- I said *"the UI gap looks larger than the learning gap."* **Backwards.** The UI gap is four call
-- sites and a mis-pointed type generation; the decision stream it was supposed to be missing has been
-- live all along. The learning gap is architectural: **the inputs a learner would need are purged
-- with every run**, so the first move is not a learner at all — it is an evidence-class ledger that
-- makes (dials in force, outcome) pairs outlive their run, exactly as `0340` did for cuOpt when
-- `cuopt_invocation_log` kept losing its own history.
--
-- **AND THE TRAP TO AVOID IS ALREADY DOCUMENTED.** `0146` established that the baselines do not pay
-- the L1 shield, so a learner rewarded on `throughput_per_hr` would learn to prefer whichever
-- configuration checks least. A reanalysis pass must hold the shield constant and score safety and
-- throughput together, or it will industrialise that defect instead of avoiding it.
--
-- **NOT CLAIMED:** that the cockpit's decision log is *complete* — only that it is live, full, and
-- polling. It polls at 4 s rather than streaming because **there is no `supabase_realtime`
-- publication on this database at all**, which was the one part of my original answer that held.

SELECT 'twin cockpit -> decision stream' AS subject,
       'LIVE: ottoq_activity_feed via ottoQ.rpc every 4s, 200 rows on b4d5f76d' AS verdict,
       'my "never reads ottoq_decisions" is RETRACTED -- grep missed the rpc client' AS note
UNION ALL
SELECT 'twin cockpit -> realtime',
       'POLLS, does not stream: no supabase_realtime publication exists',
       'the one part of the original answer that stands'
UNION ALL
SELECT 'twin cockpit -> run history',
       'BROKEN: simulation_runs exists on neither project; 4 call sites, all (supabase as any)',
       'generated types.ts describes exactly that one absent table and zero ottoq_ objects'
UNION ALL
SELECT 'learning loop',
       'BUILT, NEVER CLOSED: 6 param groups all v1/seed/last_tuned_at NULL, 0 metrics, prediction_outcomes=1',
       'writer EXISTS in otto-q-api -- my "no function writes it" is retracted; pg_proc is not the whole engine'
UNION ALL
SELECT 'why learning cannot work yet',
       '1,351 agent dial writes, 100% scope_type=run -- the inputs purge with the run',
       'an evidence-class (dials, outcome) ledger is the prerequisite, per 0340''s precedent';

-- OPEN-ITEM: RETRACTION. I told Chase the twin cockpit was "a facade wired to nothing" and that it "never reads ottoq_decisions". It is LIVE: src/hooks/useActivityFeed.ts polls ottoq_activity_feed via ottoQ.rpc every 4 seconds scoped to the active run, TwinDecisionLogTab renders it against the engine's own resolved_action_context vocabulary, the RPC returns a saturating 200 rows for run b4d5f76d, and the cockpit touches 25+ engine objects. My grep matched only .from('literal') and functions.invoke('literal') while the entire live surface uses a different client with rpc(), so I measured the one dead path and reported it as the whole -- the fourth negative-claim-from-one-place error of the day and the only one that reached Chase. WHAT IS ACTUALLY DEAD is smaller and is a real user-visible bug: four call sites (runPersistence.ts:70, historyStore.ts:46/60/68), all cast (supabase as any), against simulation_runs -- which exists on NEITHER project -- so Run History, compare, save, rename and delete are all non-functional; and the generated types.ts describes exactly that one absent table and zero ottoq_ objects, so the type generation is pointed at the wrong database and the as any casts guaranteed the compiler could never say so. THE LEARNING LOOP is the one that has never run, and my mechanism for that was also wrong: otto-q-api DOES carry updateModelParameters and recordPredictionOutcome, so "no function writes model_parameters" is retracted (pg_proc is not the whole engine). Measured instead: all 6 parameter groups are v1 with tuned_by='seed', last_tuned_at NULL, performance_metrics populated on 0 of 6, updated_at > created_at on 0 of 6, and prediction_outcomes holds 1 row for the engine's life. The deeper blocker is that its inputs do not survive: ottoq_prime has written dials 1,351 times across 6 keys and EVERY write is scope_type='run', so choices and outcomes are purged before anything could correlate them. So the order of work is the reverse of what I told Chase -- the UI gap is four call sites, the learning gap is architectural, and the prerequisite is an evidence-class (dials in force, outcome) ledger per 0340's precedent, scored with the shield held constant so it does not industrialise 0146's defect. Tracked as G115.
