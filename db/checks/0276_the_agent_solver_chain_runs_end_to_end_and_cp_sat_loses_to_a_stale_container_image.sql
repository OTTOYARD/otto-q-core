-- 0276  THE AGENT SOLVER CHAIN RAN END TO END FOR THE FIRST TIME, CP-SAT WAS
--       CORRECTLY PREFERRED, AND IT LOST TO A CONTAINER IMAGE THAT PREDATES IT.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), demo run
-- `562bf027-6c74-4cb1-9d96-722af13b2fcc` (busy_day, seed 777777, speed 8.0), armed with
-- `ottoq_agentic_arm(run, 'claude-cpsat-first-light')`.
--
-- **This is the first run in this engine's history where the intelligence host was
-- reachable AND the agent chain was armed**, so it is the first time the chain's later
-- half has ever executed. Everything below is new information for that reason.
--
-- ══ 0. AND THE BUILD I PROPOSED WAS THE WRONG BUILD ═════════════════════════
--
-- I told Chase the fix was a new `ottoq_cpsat_refresh` mirroring `ottoq_cuopt_refresh`,
-- because a `pg_proc` search for anything invoking `ottoq-cpsat-propose` returned
-- nothing and no `*cpsat*` function exists. He approved it. **Reading the edge function
-- first is what stopped it**, and its own header says why:
--
--   "ottoq-cpsat-propose: internal bridge from the Nemotron agent handoff to the
--    deterministic CP-SAT proposer."
--
-- It requires `agent_handoff.chain_id` (400 without it) and a service-role bearer. It is
-- **the primary engine of an existing chain**, not a standalone tick proposer, and it
-- carries its own `queueCuOptFallback` routing to `ottoq_agent_solver_refresh`. The
-- invoker my search missed is another EDGE FUNCTION, `ottoq-orchestrator-agent`, which
-- no `prosrc` query can see. So the complete path already existed:
--
--   decide_and_dispatch -> ottoq_cuopt_refresh -> [agent_solver_chain_enabled >= 1]
--     -> pg_net POST ottoq-orchestrator-agent (Nemotron)
--     -> ottoq-cpsat-propose -> /assign -> ottoq_proposer_submit_batch
--     -> CP-SAT fails -> queueCuOptFallback -> cuOpt
--
-- **Building the refresh would have duplicated a working capability**, which rule 5
-- calls a failure outright. What was actually missing was a reachable host, three
-- secrets, and one `ottoq_agentic_arm` call.
--
-- ══ 1. AND FOUR DETERMINISM PAIRS PROVED NOTHING ABOUT ANY OF IT ════════════
--
-- I ran four pairs today and reported 12/12 each time, the last one framed as "the first
-- test of CP-SAT proposing inside the tick with the solver reachable". **It tested
-- nothing of the kind.** Every arm reads:
--
--   cuopt_propose_enabled        **0**
--   agent_solver_chain_enabled   **0**
--
-- That is the `0056` cert quiesce, and it is correct: cuOpt proposes over pg_net with
-- real-domain debounce, heartbeats and TTLs, so its fire/answer timing is wall-clock
-- physics rather than a function of the seed. `0056` measured it — same-seed arms, 33
-- invocations each, **50 against 47 right-of-first-refusal deferral holds**, and the
-- holds chose which vehicles waited a tick. A determinism-certified run must not
-- exercise it. `ottoq_agentic_arm` refuses `run_by='cert_harness'` for the same reason:
-- *"a proposer reaches a certification by record-and-replay, never by being armed into
-- one."*
--
-- **So the proposer path is structurally outside the determinism pair, and a green pair
-- says nothing about it. Validating it requires a demo run, which is what this is.**

SELECT r.sim_run_id, r.tick_count, r.status,
       public.ottoq_policy_get(r.sim_run_id,'agent_solver_chain_enabled',0) AS chain_enabled,
       public.ottoq_policy_get(r.sim_run_id,'cuopt_propose_enabled',1)      AS cuopt_enabled,
       public.ottoq_policy_get(r.sim_run_id,'orchestrator_agent_enabled',1) AS agent_enabled
  FROM public.ottoq_sim_runs r
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 ORDER BY r.started_at DESC LIMIT 4;

-- ══ 2. THE CHAIN WORKS, AND CP-SAT IS CORRECTLY PREFERRED ═══════════════════
--
-- Measured at tick 116 of the armed run:
--
--   delegated_to_agent_chain gate rows      **61**
--   nvidia_nemotron calls (role=agent)      **11**   all outcome='enacted'
--   nvidia_cuopt calls (role=proposer)       **1**   outcome='answered'
--   cpsat_service calls                      **0**
--   forward_lex disposition rows             **0**
--
-- And the agent's own handoff records exactly what happened:
--
--   "solver_handoff": {
--       "engine": "cuopt",
--       "status": "fallback",
--       "chain_id": "e7175a64-2e59-45b0-8e78-bcdc42c45313",
--       "directive": {"objective": "readiness_first",
--                     "why": "44 pending charge atoms and 61 readiness checks indicate
--                             readiness backlog; prioritize low-SoC vehicles ..."},
--       "fallback_reason": "intelligence /assign returned an invalid proposer envelope"
--   }
--
-- **Read that carefully, because almost all of it is good news.** Nemotron analysed the
-- frame, produced a defensible objective in plain language, routed to CP-SAT as the
-- PRIMARY engine, and when CP-SAT's answer failed validation it fell back to cuOpt and
-- the run continued. Every link in the chain did its job, including the failure path —
-- which is the link nobody ever exercises.
--
-- The rejection is the edge function's own contract check, and it is right to reject:
--
--   if (!result || !Array.isArray(result.rows) || !result.fire || typeof result.fire !== "object")
--     throw new Error("intelligence /assign returned an invalid proposer envelope");
--
-- `response.ok` was TRUE, so the host answered with HTTP 2xx and the wrong SHAPE.

SELECT m.provider, m.role, m.outcome, count(*) AS calls,
       round(avg(m.latency_ms)) AS avg_ms, max(m.latency_ms) AS max_ms,
       max(m.called_at)::timestamp(0) AS last_call
  FROM public.ottoq_model_call_ledger m
 WHERE m.sim_run_id = '562bf027-6c74-4cb1-9d96-722af13b2fcc'
 GROUP BY 1,2,3 ORDER BY 4 DESC;

SELECT g.abstained_reason, count(*) AS n, max(g.called_at)::timestamp(0) AS last
  FROM public.cuopt_invocation_log g
 WHERE g.sim_run_id = '562bf027-6c74-4cb1-9d96-722af13b2fcc'
 GROUP BY 1 ORDER BY 2 DESC;

-- ══ 3. THE CAUSE: THE CONTAINER PREDATES CP-SAT, AND ITS /health SAID SO ════
--
-- The box answered the bridge probe with:
--
--   {"ok":true,"service":"ottoq-intelligence","optimizers":["energy_mpc"]}
--
-- The current `app/main.py` returns:
--
--   {"ok":True,"service":"ottoq-intelligence","optimizers":["energy_mpc","cp_sat_forward_lex"]}
--
-- `ottoq-intelligence` commit **7923cf9** ("Serve CP-SAT as the primary assignment
-- optimizer", 2026-09-16) is what changed that line, and in the same commit it **created
-- `app/optimizers/assignment_cpsat.py`** and changed **`Dockerfile` and
-- `requirements.txt`** — the latter adding OR-Tools.
--
-- **So the deployed image predates CP-SAT entirely and does not even have OR-Tools
-- installed.** No secret, policy or edge-function change can fix it; the image has to be
-- rebuilt. `/assign` on that build answers 2xx with a pre-CP-SAT shape, which is
-- precisely the envelope the edge function refuses.
--
-- **AND THE HEALTH PAYLOAD WAS THE TELL, AN HOUR BEFORE I USED IT.** When the bridge
-- probe first came back I read `optimizers:["energy_mpc"]` and noted it as *"probably a
-- hardcoded list that hasn't been updated to include cpsat"* — dismissing the one field
-- that named the defect. It was not a stale list. It was the deployed build reporting its
-- own version, accurately, and I explained it away. Same shape as every other miss today:
-- an observation treated as noise because a cheaper story fit it.
--
-- ══ 4. G62 RE-MEASURED, AND IT IS WORSE ════════════════════════════════════
--
-- CLAUDE.md rule 6 records G62 as Nemotron averaging **30,394 ms** over 1,120 calls
-- against a 30-second beat, with 433 of 1,120 (39%) exceeding one tick — the mechanism
-- behind 721 `deterministic_fallback` decisions. On this run, with the chain armed:
--
--   nemotron mean latency   **32,872 ms**   (still above a 30-second beat)
--   nemotron max latency    **85,163 ms**   (nearly three ticks)
--
-- And the funnel is the sharper number:
--
--   **61 delegations -> 11 Nemotron calls -> 1 proposer answer**
--
-- Fifty of sixty-one delegations produced no recorded agent call at all, which is what a
-- 33-second agent on a 30-second beat looks like: the next tick delegates while the
-- previous call is still in flight. **G62's conclusion stands and this run strengthens
-- it — an advisory agent cannot be a synchronous dependency of a 30-second tick**, and
-- fixing the container will not change that. It will only change which solver answers
-- the 11.
--
-- ══ 5. WHAT IS AND IS NOT DONE ═════════════════════════════════════════════
--
--   DONE   all three secrets set (`OTTOQ_INTEL_URL`, `OTTOQ_INTEL_TOKEN`,
--          `OTTOQ_BRIDGE_TOKEN`) and the token VALIDATED — a POST through the MPC
--          bridge returned HTTP **422** with Pydantic field errors, meaning it passed
--          `require_token` and reached body validation. A 401 would have meant the
--          token was wrong; `/health` alone proves nothing, as it carries no auth guard.
--   DONE   the host is reachable from Supabase's network and is genuinely our service
--          (`"service":"ottoq-intelligence"` relayed back through the bridge probe).
--          It is NOT reachable from this container at any point: the egress proxy takes
--          only HTTPS CONNECT tunnels and the service is plain HTTP on 8080.
--   DONE   the agent chain arms cleanly and runs, with the cuOpt fallback exercised.
--   NOT    CP-SAT proposing. Blocked on a container rebuild from current `main`, which
--          needs shell access to the box that I do not have.
--
-- **And note what this does NOT invalidate.** `db/checks/0274` stands unchanged: the
-- CP-SAT prototype's four determinism pins and the four constructs cuOpt cannot express
-- are verified by running `solvers/cpsat/test_cpsat_prototype.py` LOCALLY, which needs no
-- host at all. What is blocked is CP-SAT proposing *in the engine*, not our evidence
-- about CP-SAT.

SELECT (SELECT count(*) FROM public.ottoq_model_call_ledger
         WHERE sim_run_id='562bf027-6c74-4cb1-9d96-722af13b2fcc'
           AND provider='cpsat_service')                       AS cpsat_calls_this_run,
       (SELECT count(*) FROM public.ottoq_proposal_disposition_ledger
         WHERE sim_run_id='562bf027-6c74-4cb1-9d96-722af13b2fcc'
           AND source='forward_lex')                           AS forward_lex_this_run,
       (SELECT count(*) FROM public.ottoq_proposal_disposition_ledger
         WHERE sim_run_id='562bf027-6c74-4cb1-9d96-722af13b2fcc')
                                                               AS all_dispositions_this_run;
