-- 0323  **`agent_calls_with_no_l1_rules = 4,248 of 4,248` is the most alarming figure in the
--       intelligence layer, it is quoted in CLAUDE.md rule 6 as "the one path where an AI changes
--       engine state is still the one path the L1 shield does not gate", and it counts the wrong
--       thing. The number is real. The sentence built on it is not.**
--
--       No migration. Findings and one correction to CLAUDE.md, plus the specification for the
--       asynchronous-advice build that `0415` left open.
--
--       Measured 2026-09-22 05:30 UTC (12:30 AM CT), after `0414` and `0415`.
--
-- ══ §1 WHAT THE COUNTER ACTUALLY COUNTS ═══════════════════════════════════════
--
-- It counts ledger rows where `role='agent'` and `detail->>'l1_rules_evaluated' = 0`. Every Nemotron
-- row qualifies, so it reads 4,248 of 4,248. What those rows record is the agent choosing an
-- **assignment OBJECTIVE** — `readiness_first`, `throughput_first` or `energy_balanced` — at
-- `action_context='task_start'`.
--
-- **An objective is a ranking preference, not a state change**, and the edge code says so in the
-- function that implements it (`_shared/agent_solver_chain.ts`, `assignmentPairCost`):
--
--     Bounded agent influence over the assignment LP.
--     The directive changes ranking only. Compatibility and one-vehicle/one-stall
--     constraints remain structural in the LP, and the deterministic L1 shield
--     still decides whether any returned assignment can be enacted.
--
-- So the directive cannot move a vehicle, book a stall or start a charge. It can only reorder
-- candidates that something else then has to approve. **A gate placed on a preference would have
-- nothing to refuse** — the same structural point `0192` made about the nine unevaluated codes being
-- invariants over transitions rather than starts.
--
-- ══ §2 WHERE THE AGENT *CAN* CHANGE STATE, AND WHETHER THAT IS GATED ══════════
--
-- Two paths, and both are now judged:
--
--   **(a) Dial writes.** `ottoq_prime` writes six dials through `ottoq_policy_set`.
--        `AI.001.agent_dial_within_envelope` evaluates every one at `policy_write` — **557
--        evaluations** — and `0414` made the envelope ENFORCING rather than advisory, so an
--        out-of-envelope request is now clamped as well as logged.
--
--   **(b) Proposals.** The directive's output reaches the world only as rows in
--        `ottoq_external_proposals`, submitted through `ottoq_proposer_submit_batch` and disposed by
--        the kernel. Measured on the disposition ledger: `forward_lex` proposals were **refused 611
--        times and superseded 3,493 times**; enacted 36. The kernel disposes agent-influenced
--        proposals exactly as it disposes everyone else's.
--
-- **THE HONEST SENTENCE, and it should replace rule 6's:** *"The agent's dial writes are judged at
-- `policy_write` and, since `0414`, clamped to the declared envelope. The agent's objective directive
-- is not rule-judged, because it is a ranking preference whose every output is disposed by the kernel.
-- `agent_calls_with_no_l1_rules` counts the second and reads as though it were the first."*
--
-- **WHAT IS STILL FAIR TO WORRY ABOUT, stated so this does not read as an all-clear.** The shield that
-- disposes those proposals is weak where it matters: `db/checks/0263` §1 found four of the five
-- `stall_assignment` codes are charge-specific and cannot judge a parking hold, and the fifth
-- (`HW.004.stall_single_vehicle`) says in its own description that a partial unique index enforces it
-- rather than the probe. So agent-influenced assignments are gated **exactly as weakly as every other
-- proposer's** — which is G44 and `0263`, not a new AI-specific hole. The counter should be retired or
-- renamed, and the real concern is the strength of `stall_assignment`, for everyone.
--
-- ══ §3 NINE PROBE POINTS, NOT SIX — CLAUDE.md 2.5 IS STALE AGAIN ══════════════
--
-- 2.5 currently instructs readers to quote *"twenty-one of thirty declared rules, at six decision
-- points"*, re-derived by `0273` on 2026-09-20. Measured today from `ottoq_rule_evaluations`:
--
--     action_context          codes   evaluations
--     ---------------------   -----   -----------
--     task_start                 13       347,620
--     vehicle_state_change        1        22,542
--     stall_state_change          1        21,368
--     stall_assignment            5        20,380
--     charge_session_start        5        12,940
--     redeployment                6        11,034
--     bess_dispatch               1           669
--     policy_write                1           557
--     bess_state_change           1           207
--
-- **Nine.** `0321` already measured nine earlier tonight; this confirms it independently after two
-- migrations. The three 2.5 omits are the state-change probes — `vehicle_state_change`,
-- `stall_state_change`, `bess_state_change` — which sit in the row-level trigger functions
-- (`ottoq_vehicles_state_change`, `ottoq_stalls_state_change`, `ottoq_bess_units_state_change`) rather
-- than in a decide-path caller, which is plausibly why every census that walked the decide path missed
-- them. They are not marginal: **44,117 evaluations between them, more than `stall_assignment` and
-- `charge_session_start` combined.**
--
-- **Do not read this as coverage improving.** It is the same shield measured more completely, and the
-- three new points carry ONE code each. The count that matters is unchanged: `stall_assignment` still
-- has five codes of which `0263` showed four cannot judge a parking hold.
--
-- ══ §4 A DEAD SAFETY WRAPPER ══════════════════════════════════════════════════
--
-- `public.ottoq_shield_and_log(...)` probes the shield at a caller-supplied `action_context` for a
-- vehicle — the general-purpose gate — and **no database function calls it.** Zero callers,
-- comment-stripped. The eight live probe sites all call `ottoq_shield_probe` directly.
--
-- This is not asserted to be a defect: it may be intended for an edge-function caller, and a
-- convenience wrapper with no caller is harmless in itself. It IS a trap, because it reads like the
-- place a new decision point would be wired, and anything wired through it today would be the only
-- caller of an untested path. Worth either a caller or a deprecation note; not worth a migration.
--
-- ══ §5 THE ASYNCHRONOUS-ADVICE BUILD, SPECIFIED ═══════════════════════════════
--
-- `0415` fixed the measurement; the architecture is still synchronous. Measured, from the corrected
-- view: **4,248 agent decisions, mean DECISION latency 22,596 ms, max 199,290 ms, and 1,024 (24%) over
-- one 30-second tick.** The consequence is visible in the handoffs — four carry
-- `"skipped": "run is not active"`, i.e. the agent's advice arrived after the run it was advising had
-- finished — and in `0322`'s 2,735 fallbacks.
--
-- **The defect is not the latency. It is that nothing declares how long advice stays valid.** A
-- directive computed against the frame at tick N is applied at tick N+k with no k recorded and no
-- bound on it. That is the same shape as a hazard with no denominator (`0413`) and a status word
-- spanning two states (`0415`): a quantity used as though it were a different quantity.
--
-- The build, in the order this repo's own doctrine implies:
--
--   1. **Advice carries provenance.** Every directive records the `tick_seq` and `sim_clock` of the
--      frame it was computed from, alongside the tick it was applied at. Cheap, and nothing can be
--      decided without it.
--   2. **MEASURE staleness, enforce nothing** — CLAUDE.md 2.9a's blind-spot promotion doctrine applied
--      to advice instead of a determinism atom. Publish the distribution of applied-minus-computed
--      ticks. `decisions_over_one_tick` (1,024) is the crude version of this and is already in the view.
--   3. **Then declare a validity window** and refuse advice older than it, falling back to the
--      deterministic path — which already happens, just for the wrong reason (a timeout rather than a
--      staleness judgement). The fallback is not new machinery; it is the machinery that exists,
--      triggered by a measurement instead of by an exception.
--   4. **Only then decouple the beat**: the agent runs continuously and deposits fresh advice, the tick
--      reads the newest valid advice and never waits. That is Chase's *"all seeing and optimizing eye
--      that is always looking"* — and it is unreachable before step 3, because a continuously-running
--      agent with no staleness gate deposits stale advice faster.
--
-- **Steps 1-3 are DB-side and testable. Step 4 is an edge-function and tick-loop change.** None of it
-- is done here, deliberately: `0415` §5 records why I will not redeploy the one working external
-- solver path on an untested change overnight, and the same holds with more force for the tick.

\echo '=== 0323 §1 — what the alarming counter counts, and what it does not ==='
SELECT provider, role, ledger_rows, captured_decisions, calls,
       agent_calls_with_no_l1_rules,
       avg_decision_latency_ms, decisions_over_one_tick
  FROM public.ottoq_intelligence_ledger
 ORDER BY ledger_rows DESC;
-- nemotron: 4,248 of 4,248 -- every row, because every row is an OBJECTIVE, not a state change.

\echo '=== 0323 §2 — where the agent can actually change state, and the gate on each ==='
SELECT 'dial writes'  AS path,
       (SELECT count(*) FROM public.ottoq_rule_evaluations
         WHERE action_context='policy_write') AS shield_evaluations,
       'AI.001 at policy_write; 0414 made the envelope enforcing' AS gate
UNION ALL
SELECT 'proposals',
       (SELECT count(*) FROM public.ottoq_proposal_disposition_ledger
         WHERE source IN ('forward_lex','cuopt') AND status IN ('refused','superseded')),
       'kernel disposal -- weak at stall_assignment for EVERY proposer (db/checks/0263)';

\echo '=== 0323 §3 — nine probe points; CLAUDE.md 2.5 still says six ==='
SELECT action_context, count(DISTINCT rule_code) AS codes, count(*) AS evaluations
  FROM public.ottoq_rule_evaluations
 GROUP BY 1 ORDER BY evaluations DESC;
-- The three 2.5 omits are the row-level state-change triggers: 44,117 evaluations between them,
-- more than stall_assignment and charge_session_start combined. One code each -- coverage is not
-- better than it was, it is measured more completely.

\echo '=== 0323 §4 — a general shield wrapper with no database caller ==='
SELECT 'public.ottoq_shield_and_log' AS wrapper,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname NOT IN ('pg_catalog','information_schema')
           AND p.proname <> 'ottoq_shield_and_log'
           AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),
                 '--[^' || chr(10) || ']*','','g') LIKE '%ottoq_shield_and_log%') AS db_callers;
-- Zero. Either give it a caller or deprecate it; anything wired through it would be its first.
