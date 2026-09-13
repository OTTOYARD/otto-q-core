# AGENT_HARNESS — what an agent may do here, measured

*Written 2026-09-13 05:10 UTC (12:10 AM CT) against the live `otto-q-core`
database (`gxdrcyphqjzjsuhxuqtg`) and the committed tree at `e415ff4`. Every
number below has the query that produces it at the bottom. An outside assessment
of this layer prompted the page; where that assessment and the measurement differ,
the measurement wins and the difference is named.*

## The one-sentence shape

OTTO-Q has **two agent seats, not one**, and they are governed differently
because they do different kinds of damage:

| | the configuration seat | the physical seat |
|---|---|---|
| what an agent submits | policy dial values, named ops actions | stall assignments, service sequencing |
| where | `edge-functions/ottoq-orchestrator-agent` (244 lines) | `public.ottoq_submit_external_proposal` — the door |
| bounded by | a 6-knob whitelist, hard range clamp + drift limit, 3 whitelisted ops actions | the L1 shield (**20 of 29 active rule codes**, at four probe points — `db/checks/0192`) and the stall calendar's EXCLUDE constraint |
| out-of-bounds goes to | the human queue, `ottoq_ops_approvals` (**50,397 rows**) | a refusal row in `ottoq_decisions` with rule codes |
| is the safety shield in the path? | **no** — a dial change is not a physical effect (2026-07-30 audit) | **yes, always** — the shield disposes every row |
| in the certification verdict? | indirectly (dials are run-scoped policy) | **directly**: `h_prop` and `h_defr` are 2 of the 14 atoms |

Both seats are real and both are bounded. The distinction matters for claims: the
configuration seat is a **bounded harness around a knob-turner**; the physical
seat is **propose/dispose over physical acts**, and it is the one a depot
operator actually cares about.

## What is measured, at the pull

**The physical seat — 15,370 proposals, five sources, and who was followed:**

| source | context | proposals | enacted | first → last |
|---|---|---|---|---|
| `greedy_constrained` (the local path's own proposer) | stall_assignment | 12,569 | **4,153** | 08-29 → 09-13 |
| `ottoq_service_priority` | service_sequencing | 2,335 | **0** | 08-29 → 09-13 |
| `agent_probe` | service_sequencing | 240 | 40 | 09-09 |
| `cuopt` (NVIDIA) | stall_assignment | 136 | 27 | 08-29 → **08-30** |
| `forward_lex` (CP-SAT, via `bridge/proposer_bridge.py`) | stall_assignment | 90 | **0** | 09-13 |

Read the last two rows carefully, because they are the honest part:

- **cuOpt's last proposal reached the door on 2026-08-30.** That matches
  `SOLVER_STATE.md` §9's finding that the NVIDIA endpoint has not been called
  since. 136 proposals landed; 27 were enacted. (The `cuopt_invocation_log`'s much
  larger count is *invocations*, including gate refusals — never quote it as
  proposals.)
- **The CP-SAT proposer has been heard 90 times and followed zero times.** All 90
  rows are from last night's two live runs (`af2def1b`, `ccf48af1`): 67 superseded,
  23 pending, 0 enacted. `db/checks/0186` and `demo/D3_RUNBOOK.md` §5 say exactly
  why — the decision frame does not carry the three facts the selector filters on,
  and nothing protects the stall a proposer names for the one tick its vehicle is
  held. Those are `0263` and `0264`, in flight.
- **`ottoq_service_priority` is a *certified* proposer with 2,335 proposals over
  15 days and not one enactment.** Root-caused the same night in `db/checks/0188`,
  and the answer is not a dead seat: the seat IS wired (`ottoq_decide_tick` line
  965 calls the selector for `service_sequencing`), its proposals ARE consumed —
  **446 decisions name it as the enacted action's source** — and every one of those
  446 carries `outcome_status = 'noop_no_candidate'`, set by the branch at line 1029
  whose comment reads *"NO BAY -> DO NOT ENTER ONE"*. The flagship depot has **two
  service bays**, and they are busy: **1,725 bookings in three days**, taken by the
  bay loop §(4b), which runs **earlier in the same tick**. So the proposer is heard,
  consumed, and physically unable to be followed.

  That is the same defect as the CP-SAT proposer's 90-and-zero, on a different
  resource, and it sharpens the founder's own premise. "The proposer is most useful
  under contention" is right — and **under contention the proposer is exactly who
  loses, because it is asked last.** Whatever `0264` settles for charge stalls
  should be resource-generic for this reason.

**One caveat on the word "enacted", found while root-causing the above.** The
lifecycle closer credits a proposal only when, at the same tick and for the same
entity, `d.enacted_action->>'source' = p.source`. Measured over three days, 24,953
enacted `task_start` decisions carry no `source` key at all, and several
`stall_assignment` paths write a *path* name rather than a proposer name
(`reservation_honoured` 5,742, `inspect_seam` 9,132, `needs_card` 892). Those paths
owe no proposal credit — they consumed a reservation or a seam, not a proposal — so
nothing is miscounted today. But the rule means any future proposer whose consuming
path rewrites or drops `source` will read as "0 enacted" while being followed every
tick. Credit by proposal id would be immune; credit by string match is not. Read an
enactment count as *credit*, not as *influence*, until that changes.

**The enforcement is in the database, not in the agent's own wrapper.** Measured
with `has_table_privilege` / `has_function_privilege`:

| role | INSERT on proposals | INSERT on bookings | EXECUTE the door |
|---|---|---|---|
| `anon` | no | no | **no** |
| `authenticated` | **no** | **no** | yes |
| `service_role` | yes | yes | yes |

So an agent holding a user token **can propose and cannot write** — not by
convention, by privilege. `service_role` is the trusted server key and is the
honest caveat: anything holding it can write directly, which is why the bridge
holds no INSERT at all and a test pins that (`grep`-level assertion in
`bridge/test_proposer_bridge.py`).

**The dial limits are declared data, not code:** `ottoq_policy_param_catalog` has
**66 parameters, and all 66 carry a min and/or max**. `ottoq_policy_set` refuses a
key that is not in the catalog (that refusal is what migration `0262` existed to
fix) and clamps a value outside the range — measured in `0262`'s own assertion A2,
where a requested 5 became 1.

**Replay, not trust:** `forward_lex` and `llm_advisor` are deliberately **not** in
`ottoq_certified_proposers` (3 rows: `cuopt`, `greedy_constrained`,
`ottoq_service_priority`). A nondeterministic proposer reaches a certified run only
by record-and-replay (`0237`/`0239`); `ottoq_proposal_replay` holds **84** rows.
That is the mechanism that lets us consume a solver which, by its vendor's own
documentation, cannot promise byte-identical output (`docs/research/answers/R-12`).

## What we may claim today, and what we may not

Adopting the two-tier framing from the outside assessment, with our numbers:

**True today, and defensible under hostile questioning:**

> OTTO-Q combines a deterministic depot-orchestration kernel with a bounded agent
> harness: agents propose, a certified deterministic core disposes, every proposal
> and every refusal is a ledger row, and a run replays byte-identically across
> fourteen independent checks.

Each clause is backed: 15,370 proposals / 4,220 enacted / refusals in
`ottoq_decisions`; the fourteen atoms and the canon matrix in
`CERTIFICATION_STATUS.md`; 50,397 rows in the human approval queue; privilege
table above.

**Not true yet, and not to be said:**

- *"Closed-loop"* / *"adaptive replanning"* — the loop is closed for the local
  path's own proposer and for cuOpt (both have enactments). It is **not** closed
  for the new CP-SAT or LLM proposers: 90 heard, 0 followed. Say so.
- *"Self-learning"* — `intent/learn.py` exists and **deliberately refuses** to
  train on run outcomes, because the twin replays OTTO-Q's own decisions and would
  tune the objective against our own bugs. That is a documented choice, not a
  missing feature, and it is the opposite of a learning claim.
- *"A 29-rule safety shield"* — the catalogue declares 29 active; the shield
  evaluates 20 of them at four probe points (`db/checks/0192`). Say twenty, name the
  four, and say that six critical invariants are written and unwired. A safety
  reviewer asks this before they ask anything about throughput.
- *"Production-proven"*, *quantified savings*, *"guaranteed optimal"* — every
  number on this page is a **twin** number. The D2 A/B result (median turnaround
  150 min vs 180 for FIFO and greedy) is labelled "demonstrated in simulation",
  carries its run ids, and re-runs byte-identically. That is the strongest form of
  it available until a site runs.
- *"The intelligence service orchestrates"* — `ottoq-intelligence`'s `/orchestrate`
  and `/assign` endpoints **return `{"status": "not_implemented"}`**
  (`app/main.py:151` for `/assign`, `:157` for `/orchestrate`). The orchestration that exists is in the kernel and in
  the edge functions, not in that service.

## Three corrections to the outside assessment

1. **The harness it describes is the *configuration* seat, and the safety shield is
   not in that path.** Whitelisted dials, clamps, drift limits and the human
   approval queue are all real and all in `ottoq-orchestrator-agent` — but that
   agent turns knobs and requests named ops actions. A dial is not a physical act,
   so the shield does not evaluate it. The shield governs the *other* seat.
   Saying "the agent is shielded" without that split overstates it in the one place
   a diligence question would land.
2. **"The forward proposer still requires live integration" was true yesterday and
   is not true today.** It submitted 90 rows through the production door last
   night. The accurate statement is sharper and more useful: *integrated and heard,
   never yet followed* — with the two named reasons and the two migrations that fix
   them.
3. **The limits live in the database, not in the agent wrapper.** This matters more
   than it sounds: a guardrail implemented inside the agent's own code is bypassed
   by anything that does not go through that code. A guardrail implemented as a
   privilege (`authenticated` cannot INSERT), a catalog (66 clamped parameters), a
   constraint (the bookings EXCLUDE) and a shield inside the tick holds for *every*
   caller, including a future agent nobody has written yet.

Everything else in the assessment matches what is in the tree, including its own
correction that learning and retries are capabilities rather than prerequisites,
and its note that the committed production posture disables the agent by default.

## The gaps, named and ranked

1. **A proposal cannot win a stall** (`0263` + `0264`, in flight). Until this lands,
   "agents propose, kernel disposes" is provable for two proposers and aspirational
   for the two new ones.
2. **No agent-facing door.** There is a *database* door; there is no published API
   an outside agent can call to read depot state, submit a proposal, and read back
   what the kernel decided. That is what would make this a harness other people's
   agents can enter — and it would turn the twin into a scoring rig for third-party
   optimizers.
3. **G47, now root-caused (`db/checks/0188`): the proposer is asked after the
   resource is gone.** Two service bays, booked 1,725 times in three days by an
   earlier section of the same tick; the service proposer's 446 consumptions all
   land on "no bay". Fix candidates, in increasing risk: make `0264`'s one-tick
   resource hold generic rather than stall-specific; or show §(5) what §(4b) booked
   so it abstains honestly instead of proposing into a wall; or reorder the tick
   (a recert and a behaviour change for one lane — last resort).
4. **Refusal reasons do not reach the next proposal.** Reason codes are recorded
   (`ottoq_decisions`), and nothing feeds them back into a proposer's next solve.
   The assessment is right that this is unwired; the sequencing argument for doing
   it *after* (1) is that a proposer which is never followed has nothing to learn
   from.

## How to re-derive every number here

```sql
-- the physical seat, by source and context (the main table above)
SELECT source, action_context, count(*) AS proposals,
       count(*) FILTER (WHERE status = 'enacted') AS enacted,
       min(created_at)::date AS first_seen, max(created_at)::date AS last_seen
  FROM public.ottoq_external_proposals GROUP BY 1, 2 ORDER BY 1, 3 DESC;

-- the human queue, the dial catalog, the whitelist, the replays
SELECT (SELECT count(*) FROM public.ottoq_ops_approvals)                          AS approvals,
       (SELECT count(*) FROM public.ottoq_policy_param_catalog)                    AS dials,
       (SELECT count(*) FROM public.ottoq_policy_param_catalog
         WHERE min_value IS NOT NULL OR max_value IS NOT NULL)                     AS dials_with_limits,
       (SELECT count(*) FROM public.ottoq_certified_proposers)                     AS certified,
       (SELECT count(*) FROM public.ottoq_proposal_replay)                         AS replays;

-- who may write what (the privilege table)
SELECT r.rolname,
       has_table_privilege(r.rolname, 'public.ottoq_external_proposals', 'INSERT') AS insert_proposals,
       has_table_privilege(r.rolname, 'public.ottoq_stall_bookings', 'INSERT')     AS insert_bookings,
       has_function_privilege(r.rolname,
         'public.ottoq_submit_external_proposal(uuid,uuid,text,text,uuid,jsonb,text,integer)',
         'EXECUTE')                                                               AS may_propose
  FROM pg_roles r WHERE r.rolname IN ('anon', 'authenticated', 'service_role');
```

`db/checks/0189` is the standing version of the first query: run it after every
certification round and every demo, because it separates the two kinds of zero —
`NEVER HEARD` (the door took the proposal and the selector refused it) from
`ASKED AND NEVER FOLLOWED` (the selector returned it and physical reality overruled
it). Conflating those two is what cost the first live D3 run.

The certification side is re-derived by `CERTIFICATION_STATUS.md`'s own block; the
90-heard-0-followed measurement is `db/checks/0186`; G47's root cause is
`db/checks/0188`; the canon's current state and the one open defect in the
instrument are `db/canons/round41.md` and `db/checks/0187`.
