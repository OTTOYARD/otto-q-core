# The Frontier Plan: Certified Intelligence

**Written the night of 2026-11-02 CT for Chase's go-ahead. Nothing in it is built yet.** Every number was read from the
engine tonight (the time is given beside it) or carries a source and URL (§9). Every item was checked against rules 8,
9, 10, 12, 13 and 14 (§7). Times are CT. Days in tables are UTC days, as the ledgers bucket them.

Chase's ask, 2026-11-02: *"determine how to create and build a smarter OTTO-Q model ... something no one else has done or
put together ... Start with what we have and what is built with Agents and Determinism, and then find out what we are
missing ... Make a list first, and then once we have a plan of attack, I'll give you the go-ahead to implement."*

---

## 0. The answer

OTTO-Q already has the rarest base in this field:

- a twin that replays byte-for-byte under a fixed seed;
- random draws keyed on seed, entity and time, so they stay the same when the policy changes;
- evidence ledgers that survive the demo-run purge;
- each owner's contract stored as data;
- a kernel that disposes of every proposal.

What it does not have is a way to **know** how good a decision is:

- **The judge is weak.** The check that judges the agent's charge orders is only weakly better than a coin at telling a
  better order from a worse one (§2.1).
- **The yardstick is unpriced.** It can call an order better while that order costs the owners uptime (§2.2).
- **The interlocks are hand-written.** One was found wrong tonight, from a screenshot (§2.5).
- **There is no absolute measure.** Nothing says how far a day was from the best possible day (§2.6).

**The edge: every decision OTTO-Q takes carries a certificate, and AI invents new kernel policies that can reach a depot
only by passing those certificates.** The certificates are:

- a promise with guaranteed coverage;
- a verdict with a bounded error rate;
- a safety supervisor that is synthesized and proven, not written by hand;
- a measured distance from the best possible day.

Each technique is published on its own: program search, anytime-valid statistics, conformal prediction, supervisory
control synthesis and information-relaxation bounds (§9). I found no depot or fleet orchestrator that combines them. That
is a claim about what I found, not a proof that nobody has.

OTTO-Q is unusually well placed to combine them, because each certificate needs a piece of the base it already has (§3).

I call this the **Certified Intelligence Loop**.

---

## 1. What exists today: agents and determinism

| Layer | What it does | Where |
|---|---|---|
| L1 shield | Rules evaluated at the engine's decision points; every evaluation logged | `ottoq_rules`, `ottoq_shield_probe` |
| Deterministic kernel | The decide path. 0642's charge line: a 90-minute floor, then the longest wait, then minutes of charge on the learned clock | `ottoq_decide_tick` |
| Proposers | cuOpt (NVIDIA hosted) and a CP-SAT service (OR-Tools pinned 9.15.6755); the Nemotron agent writes charge orders | `ottoq-intelligence`, the agent edge function |
| The check (the judge) | Samples 12 futures with the same draws for the agent's order and the kernel's, and takes the agent's order when it wins in at least 10. Also an owner guard (rule 14). | 0618, 0620, `ottoq_charge_order_verdict_v2`, `ottoq_charge_line_schedule` |
| Hindsight grading | Grades each checked order nightly against what actually happened (cron 787, 5:00–6:50 AM CT) | 0621, `ottoq_charge_order_hindsight` |
| Learned estimates | A charge clock per class, make and car; return and outflow curves; evidence regimes; a self-review | 0622–0628, 0630–0641 |
| Determinism | A 14-atom byte-identical verdict per pair. A stateless seeded RNG keyed on (seed, entity, sim-seconds) | `ottoq_determinism_pair`, `twin.ottoq_sim_seeded_random` |
| Evidence | Ledgers that survive `ottoq_purge_prior_runs` | `ottoq_model_call_ledger`, `ottoq_agent_charge_orders`, `ottoq_charge_order_snapshots`, `ottoq_charge_order_hindsight` |
| Contracts | 4 active owner SLAs, versioned | `ottoq_fleet_operator_slas` |

Engine size, read 10:27 PM CT: PostgreSQL 17.6, 34 GB, and 1,216 routines and 453 tables in `public`, `ottoq` and
`twin`.

**The agent architecture this plan extends** is `docs/AGENT_ARCHITECTURE.md` (2026-10-13):

- Layers L0–L7: the hard floor, vehicle truth, scouts, the kernel, the proposers, the disposer check, evidence, and the
  research wing.
- A four-condition gate any additional agent must pass before production: recorded and replayable, the disposer
  discriminates, an ablation beats the noise floor, registered.
- Its L7 research wing (deterministic agent-on/off replay, event-keyed RNG, AlphaEvolve-style heuristic search) is
  **designed and not built.** E1 and E6 build it. This plan does not replace that document; it adds the certificates the
  document's gate needs.

---

## 2. What is missing, measured tonight

### 2.1 The judge tells a better order from a worse one only weakly

Read at 10:45 PM CT with the repo's own instrument, `ottoq_disposer_discrimination` (0708). It covers every graded decision
at the twin depot since 2026-10-01: **364 decisions** (161 won in hindsight, 203 lost, 5 ties left out), graded from
2026-10-08 (9:46 AM CT) to 2026-10-26 (6:00 AM CT). They come from 24 runs but only **17 distinct (scenario, seed) keys**.

- **AUC 0.656**, 95% interval [0.599, 0.713]. 0.5 is a coin and 1.0 is perfect.
- **Brier score 0.239**, against **0.247** for always predicting the base rate: a skill of 0.031. The check's win
  probability tells us little more than how often the agent wins at all.
- **`discriminates = true`.** This is the first time the promotion gate's second condition
  (`docs/AGENT_ARCHITECTURE.md`) reads true. On 2026-10-13 it read AUC 0.534 [0.415, 0.653], over 91 decisions from 6
  keys.

**Do not treat the gate as passed yet.** Its interval assumes 364 independent decisions, and they come from 17 keys.
Decisions within a run share that run's world and futures; the instrument says so in its own caveat. So the interval is
optimistic. Phase 0 computes a key-clustered interval first.

The table below is my own count from the grades' outcome labels, which classify one decision differently from 0708 (162
won, against 161):

| futures the agent's order won (of 12) | decisions | agent won in hindsight |
|---|---|---|
| 0–2 | 56 | 9 (16%) |
| 3–6 | 173 | 74 (43%) |
| 7–9 | 98 | 55 (56%) |
| 10–12, the bar (taken) | 37 | 24 (65%) |

**Why.** Twelve futures make a twelve-coin estimate. At a true win rate of 0.5, its standard error is √(0.25/12) = 0.14.
The bar at 10 of 12 refuses most real wins and still lets in losses:

- 141 refused orders won in hindsight.
- 21 taken orders won.
- 11 taken orders lost.

This supersedes G389 (2026-10-09, AUC 0.35 on 18 decisions) and the gate's reading of 2026-10-13. On four times that
evidence the check does discriminate, but weakly, and on only 17 independent keys.

### 2.2 The yardstick can call an order better while it costs uptime

The check ranks futures lexicographically: on-time cars first, then lateness, then minutes past the contract wait, then
flow. Here is the level that decided each of the 141 refused orders that won in hindsight (read 10:28 PM CT):

| decided at | refused wins | on-time cars gained | mean minutes out at work, kernel's order minus agent's |
|---|---|---|---|
| on-time cars | 4 | 4 | +17.4 |
| lateness | 92 | 0 | +18.6 |
| contract wait | 40 | 0 | +11.1 |
| flow | 5 | 0 | −2.3 |

Only **4 of the 141 "missed wins" would have put one more car on time.** In the 92 that won on lateness, on-time cars were
equal, and the kernel's order kept cars out at work a mean **18.6 minutes longer** in the window.

"Minutes out at work" is `out_min` in `ottoq_charge_line_schedule`: minutes cars spend at work inside the window. The means
are over the decisions whose hindsight stores it (341 of 364).

A lexicographic chain has no exchange rate between its levels, so "the agent would have won" is not a well-posed question
until those levels are priced. **The owners' contracts carry limits but no prices.** `penalty_schedule` is `{}` in all
four SLAs. All four set a 30-minute queue wait, an 80% minimum at deployment and a 100% charge ceiling (read 10:38 PM CT).

### 2.3 The agent's orders almost never reach the depot

| UTC day | orders | taken (accepted + partial) |
|---|---|---|
| 2026-10-20 | 225 | 2 |
| 2026-10-21 | 232 | 0 |
| 2026-10-23 | 276 | 18 |
| 2026-10-24 | 240 | 9 |
| 2026-10-25 | 128 | 0 |
| 2026-11-03 | 17 | 0 |

That is **29 of 1,118 orders taken since 2026-10-20 (2.6%)**.

Per run, read 10:38 PM CT:

- The last full run, `763734d4` (first order 2026-10-25, 1:52 PM CT), took **0 of 128**.
- Tonight's `8c0b2e04` (first order 9:38 PM CT) has taken **0 of 17** so far.

1,658 of the 2,028 orders recorded since 2026-10-07 have a stored snapshot (`ottoq_charge_order_snapshots`, evidence). That
is the replay set for §5.

### 2.4 The agent sits in the wrong loop

Tonight's live calls (UTC day 2026-11-03, this evening CT): 24 calls, mean **20.7 s**, p95 31.5 s, 23 completed. On
`8c0b2e04` they produced 17 orders over 129 ticks, and none was taken.

The agent is fired asynchronously and never blocks a tick (0332), so this latency costs the tick nothing. But it is a
poor use of a 20-second language model to have it out-order a deterministic sort, in front of a judge that can barely see
its wins. What only a language model does well is unused: reading a situation, writing code, explaining.

`docs/AGENT_ARCHITECTURE.md` already points the same way: one coordinator, event-driven since 0705 and 0711, with narrow
specialists only where the input is unstructured.

### 2.5 The safety interlocks are hand-written, and their combinations are checked by eye

**G506, tonight.** On demo run `8c0b2e04`, two posts faulted while their cleaning arm was in the cabin. They kept their
cars **339 s and 309 s** on a dead post. The hold that kept them (0760) is correct for a charge that ends; it never asked
why the charge ended.

- Found from Chase's screenshot.
- Fixed in the engine by 0792 (applied 10:18 PM CT, PR #264).
- Fixed in the renderer by ottoyarddepot-sim PR #154.

This repo has recorded composition defects of the same kind before: G121, G122, `0333`. Nothing proves that the
interlocks, taken together, are safe and never deadlock.

### 2.6 There is no absolute measure

Every comparison is relative: the agent against the kernel, one arm against another. Nothing measures how far a day was
from the best achievable with what was known at the time. Without that measure:

- nothing ranks where the remaining value is: the charge order, the bay sequence, staging, or recall timing;
- nothing says when a piece is good enough to stop optimizing.

### 2.7 The lab is in production and runs at production's pace

- **It stalls the cron jobs.** A paired test blocks every `pg_cron` job while it runs (G141: a 13.6% cron outage,
  measured over seven days in September).
- **Live replay drifts.** Live playback ties each tick's sim length to database load, so the same seed draws a
  different world after the first tick (2.5, `0416`). A paired claim smaller than that noise floor needs a deterministic
  replay.
- **The lab is due to move.** Rule 10's decision of 2026-09-27 moves it out of production before real telemetry flows.
- **It is too slow for search.** Program search needs thousands of runs; today the lab runs one at a time.

### 2.8 Forecast bands are fitted by hand

The futures' spreads were fitted to observed returns (0630–0641). That followed G371, which found the 80% band covering
50.4% of cars due within 10 minutes on `b2efcc07`.

A fitted spread carries no coverage guarantee into the next regime, and the twin's world does change: `0625` records each
change.

---

## 3. The edge: the Certified Intelligence Loop

```
   invent policies (E6)  ──►  screen in the Lab, on exact counterfactual forks (E1)
          ▲                                      │
          │                                      ▼
   learn overnight              judge: per owner, anytime-valid, priced (E2, E7)
   (estimates only, rule 10)                     │
          ▲                                      ▼
          │                      prove safe: synthesized supervisor (E3)
   a person ships it                             │
   as a certified change  ◄──  measure the gap to the best possible day (E5)
   (rule 10)                    and publish promises with guaranteed coverage (E4)
```

| Certificate | What it says | How it is built | Item |
|---|---|---|---|
| Promise | "Car X is ready by 14:20, with 90% guaranteed coverage" | Split conformal prediction with adaptive conformal inference | E4 |
| Verdict | "Taking this order is no worse for any owner and better overall; false-take rate at most 5%" | An anytime-valid e-process over a priced, per-owner utility | E2, E7 |
| Safety | "No reachable state mates a faulted post or holds a car on one; no deadlock" | Supervisory control synthesis | E3 |
| Gap | "This day was within X% of the best achievable" | A clairvoyant CP-SAT bound, tightened with an information-relaxation penalty | E5 |
| Provenance | "Here is the certificate; re-check it yourself" | Hashed into the decision snapshot | E10 |

**Why OTTO-Q, and why few others can follow quickly:**

1. **Exact counterfactuals need a byte-identical twin whose draws are keyed on (seed, entity, time).** OTTO-Q has one.
   The leading GPU solver documents no determinism parameter for routing at all (`docs/research/answers/R-12`).
2. **Anytime-valid verdicts need common random numbers that survive a change of policy.** The twin has them by
   construction (C5 correction, `0052`).
3. **Per-owner certificates need each owner's contract as data.** There are 4 versioned SLAs today, missing only prices
   (§2.2).
4. **AI-invented policies are safe to try only behind a disposer that can refuse on the numbers.** Propose/dispose is
   already the architecture (2.5, `0618`).

**Where the depot market is.** In what I could find on 2026-11-03, depot players are automating the plug and the wash,
not certifying the decisions: Rocsys M1, Robodock and Joule Labs AURA (§9). The orchestration layer above that hardware is
where this plan works.

---

## 4. The list, in build order

Effort is in Claude Code sessions. **These are estimates, not measurements.**

### E1. The Lab, with time-travel forks (the enabler)

**What.** A research database outside production: Postgres 17 with the engine's schema and the twin depot's reference
data only. It holds no run data and no other depot (rule 8).

- **Unpaced.** Ticks advance as fast as the CPU allows, on a fixed tick length, so a seed draws the same world every
  time.
- **Parallel.** Several replicas run at once.
- **Time-travel forks.** At any tick, fork the run, change one decision and replay with the same world draws. Inside one
  client transaction this is a `SAVEPOINT` per fork point, with results read before `ROLLBACK TO SAVEPOINT`. Longer forks
  use `CREATE DATABASE … TEMPLATE`.
- **The fork carries the GUC hazard from `0329`/`0421`.** Every branch sets `ottoq.sim_run_id` itself.

**Why.**
- Moves the research lab out of production, as rule 10 decided, and ends G141's cron outage.
- Replaces the live noise floor (§2.7) with exact replays.
- Gives every other item its throughput.
- The forks are the novel part. Because draws are keyed on entity and time, not on sequence, a forked branch sees the
  same arrivals and faults. The difference between branches is therefore the exact effect of the decision, under the
  twin's world model. That gives exact credit assignment per decision, which E2, E5 and E6 all need.

**Builds on.**
- `ottoq_determinism_pair` already drives arms unpaced inside one transaction. That is the hard half (C5 correction).
- E1 is L7's "deterministic agent-on/off replay" from `docs/AGENT_ARCHITECTURE.md`, built and then extended with forks.

**First deliverable.** `lab/` in this repo: a Docker setup, the load scripts, a tick driver, a fork driver and three
acceptance tests.

**Done when:**
1. **Fidelity.** A Lab pair agrees with itself on all 14 atoms. A Lab arm reproduces the atom digests recomputed from a
   surviving production run's stored rows for the same scenario, seed and ticks, the way `0329`/`0330` recomputed them.
2. **Forks.** An unchanged branch reproduces the original byte-for-byte, and a changed branch differs only after the fork
   tick.
3. **Throughput.** Simulated depot-days per hour is measured and reported. It is the first number the Lab owes.

**Gates.** The research wing only (rule 10). Needs D2. Testing in the Lab needs D3.

**Effort.** 2–3 sessions.

### E2. The calibrated judge (the bottleneck)

**What.** The check, rebuilt as a statistical instrument. It has three parts.

1. **Price the yardstick.**
   - **Constraint layer, never priced:**
     - rule 9's needs (no car leaves short of target or with a needed service);
     - rule 14's owner guard, which exists today in `ottoq_charge_line_schedule`, `ottoq_charge_line_state` and
       `ottoq_charge_order_verdict_v2`;
     - no owner loses an on-time car.
   - **Priced layer, inside the constraints:** per-owner minutes of lateness, minutes past the contract wait, flow, and
     minutes out at work, at prices the owners' contracts set (D4).
2. **Compare sequentially, with an anytime-valid stopping rule.**
   - Paired futures with common draws, as now, plus antithetic pairs and stratification by fault count to cut variance.
   - Each futures sample is a bounded paired difference in utility, per owner.
   - A betting e-process (Waudby-Smith & Ramdas) decides. The judge takes the order when the depot's e-value reaches
     1/α **and** every owner's lower confidence bound is at least −ε (E7). It refuses when the confidence sequence rules
     out improvement, or when the futures budget runs out, which keeps the kernel's order.
   - Ville's inequality bounds the false-take rate at α, whenever the judge stops.
   - The budget counts futures, not wall-clock time. A wall clock inside a certified path is G15's defect class.
   - The stopping rule is a deterministic function of the seeded draws, so the verdict replays byte-for-byte.
3. **Calibrate the futures.** E4 supplies the futures' quantiles.

**State the guarantee exactly.** α bounds the false-take rate **with respect to the futures generator**. Whether that
generator matches the world is E4's job, and hindsight grading (0621) measures it. Quote the two together or not at all.

**Why.** The judge decides which of the agent's ideas reach the depot. Today it takes 2.6% of them and cannot tell good
from bad (§2.1–2.3). Every later item is judged by it.

**Builds on.** `ottoq_charge_line_schedule` (pure), the 1,658 stored snapshots and the hindsight JSON.

What the hindsight JSON stores for both orders, read 10:44 PM CT (all four depot components together: 323):

| Component | Level | Graded decisions that have it (of 364) |
|---|---|---|
| `on_time`, `late_sum`, `flow_sum` | depot | 364 |
| `out_min` | depot | 341 |
| `breach_sum` | depot | 323 |
| per-owner split | per owner | 24, the newest |

**So the depot-level yardstick can be re-priced offline, without a new run.** Re-pricing per owner needs the pure
scheduler re-run on the stored snapshots, which is also no new run.

**First deliverable.** A replay report: for the graded decisions, the verdict each candidate rule would have given and how
it fares in hindsight, under a grid of prices.

**Done when,** on the replay set:
- the new judge's false-take rate in hindsight is at most α, with a confidence bound;
- it takes more true wins than v2 at an equal or lower false-take rate;
- no taken order violates a constraint-layer rule;
- the promotion gate's condition 2 (0708) holds on a key-clustered interval, not only on the independent-decision one.

It then ships as a dial-gated migration, switched on at the twin depot under Chase's name, and one demo run checks it
working (rule 12).

**Effort.** 3–4 sessions.

### E3. The synthesized safety supervisor

**What.** Model the post cell as a discrete-event system in CIF (Eclipse ESCET). The model has six plants:

- the car;
- the charger: Available, Occupied, Faulted, under repair;
- the charge arm: stowed, approach, mate, latched, unlatch, extract, retract;
- the cleaning arm: home, deploy, in the cabin, return;
- the tether;
- the booking.

It has six requirements:

| | Requirement |
|---|---|
| R1 | No mate on a faulted charger. |
| R2 | A faulted post releases its car. This is G506. |
| R3 | The two arms never collide. |
| R4 | No car leaves with a needed service (rule 9). |
| R5 | No charge ends short of target except on a fault or an emergency (rule 9). |
| R6 | Nonblocking: from every reachable state the car can reach ready or re-queued. |

ESCET then synthesizes the maximally permissive, controllable, nonblocking supervisor. From it we generate three things:
1. **Runtime monitors** over `ottoq_events` and `ottoq_ocpp_messages`. They flag every trace the supervisor would have
   disabled. A monitor is a finding for a person, not a lever (rule 10).
2. **Conformance tests** for the engine's SQL holds and for the renderer's arm gates (`roboticService.ts`, `armGate.ts`).
3. **A diff between the supervisor's disabled events and the hand-written holds** (0543, 0760, 0792, …). Every
   difference is either a bug or a model error, and each one gets resolved.

**Why.** G506 was found from a screenshot. Synthesis finds combination errors by construction, before a car meets one.

**Kernel purity.** The synthesis tool, the monitor generator and the test generator are kernel. The post-cell model is
the robotaxi pack's data.

**First deliverable.** The G506 cell: one DCFC post with its charge arm and cleaning arm, R1–R6, the synthesis result,
and monitors replayed on run `8c0b2e04`.

**Done when:**
- The monitors flag DCFC-22 and DCFC-02 on `8c0b2e04` at the times `db/checks/0474` logged, and every other flag in that
  run is explained.
- The diff against the hand-written holds is empty or explained.
- The generated tests run in both repos' CI.

**Gates.** Needs only the go-ahead. It reads existing evidence and starts no runs.

**Effort.** 2–3 sessions.

### E4. Calibrated promises

**What.** Wrap the learned estimates in split conformal prediction:

- the charge clock (0622);
- returns and drain (0623, 0628);
- service durations.

The prediction is Mondrian by kind, horizon (under 10, 10–30, over 30 minutes) and make. It respects the evidence regimes
(0625): calibration uses only the current regime. Adaptive conformal inference (Gibbs & Candès) holds long-run coverage
under shift.

Every readiness promise then carries a coverage level, and the judge's futures (E2) sample from the calibrated quantiles
instead of hand-fitted spreads.

**Why.** "Ready by 14:20, 90%" is the sentence an owner's operations team plans around. It is also what makes E2's
guarantee mean something in the world.

**Done when:**
- On held-out runs, the 80% and 90% promises cover within ±3 points in every bin with enough samples.
- The under-10-minute arrival bin, where G371 read 50.4% at a nominal 80%, covers at nominal.

**Gates.** Production-safe. Rule 10 allows it as overnight learning of estimates: a promise is a readout, never a lever.

**Effort.** About 2 sessions.

### E5. The optimality certificate

**What.** For each finished twin run, a CP-SAT solve with perfect hindsight, run on the CP-SAT service (OR-Tools
9.15.6755) or in the Lab. It takes the run's realized arrivals, faults and durations and produces the best achievable day.
That day is a bound.

The bound is subject to:
- each stall serving one car at a time;
- the installed chargers, with no ceiling below them (rule 13);
- every rule-9 need, as a constraint;
- the priced per-owner utility from E2.

Two steps come out of it:
1. **Tighten the bound** with an information-relaxation penalty (Brown, Smith & Sun) built from the kernel's own value
   estimates. This is research-grade, and the plain clairvoyant bound is valid without it, only looser.
2. **Split the regret by decision type.** Re-solve with one type free and the others fixed to what the kernel did:
   charge order, bay sequence, staging, recall timing. The gap that each type closes is the regret it carries.

**Why.** It is the first absolute measure (§2.6). It ranks the next build by measured regret, and it is a claim almost no
operator can make: we know how far we are from perfect, per day and per owner.

**Done when:** the bound, the ratio of the kernel to the bound and the regret split are reported for the most recent
twin runs, per owner, each with its run ID.

**Gates.** Analysis of finished runs. It starts no run and no pair, so rule 12 is not touched. It runs off the
production database's CPU.

**Effort.** 2–3 sessions.

### E6. The policy inventor: AI writes the kernel's rules, and the rules are proven before they ship

**What.** LLM-driven program search over the kernel's **priority functions**. The first target is the charge line's sort
key, where 0642's key is the incumbent. Bay sequencing, staging choice and recall thresholds follow.

This is L7's "AlphaEvolve-style heuristic search" from `docs/AGENT_ARCHITECTURE.md`, which is designed and not built.
What this plan adds to it:
- the skeleton as the safety boundary;
- the three evaluation tiers;
- the certificates as the only way out of the Lab.

**The FunSearch skeleton is the safety boundary.** Only the key is evolved. The constraint layer is fixed code that the
search cannot touch: rule 9's needs, rule 14's owner guard and the shield. So the search can only reorder what the
constraints already allow.

Each candidate:
- is a pure SQL function with a fixed signature, `IMMUTABLE`, with no data writes and a size limit;
- is evolved with island models (FunSearch) and with the reasoning carried alongside the code (EoH);
- uses Claude, through the Anthropic API, as the mutation operator.

**Evaluation, in three tiers:**
1. The pure charge-line scheduler on the 1,658 snapshots, with E2's futures. Fast.
2. Full Lab days on training seeds.
3. Held-out seeds, never seen during the search. On them:
   - the determinism pair passes on all 14 atoms;
   - E7 gives a per-owner Pareto certificate;
   - rule 9 is audited with zero violations;
   - E5 measures how much of the regret closed.

Independent observations are distinct (scenario, seed) keys, never repeated arms (G153).

**Output.** A ranked set of candidates. Each is a dial-gated migration with its certificates attached, for a person to
ship (rule 10).

**Why.** This moves the language model from the hot path to the design loop. It is the pattern of AlphaEvolve's Borg
heuristic: interpretable code, in production, recovering an average of 0.7% of Google's worldwide compute (DeepMind,
2025-05-14). An evolved key runs at tick speed, replays byte-for-byte and passes through the shield, none of which an
online agent order can do.

**Done when,** either of these, both being results:
- an evolved key beats 0642's on held-out seeds, with a per-owner Pareto certificate and zero rule-9 violations; or
- the search shows, with E5's bound, that the incumbent is within ε of the best achievable.

**Gates.** Needs E1, E2 and E5, plus D2 and D3. It runs in the Lab only.

**Effort.** 4–6 sessions plus compute.

### E7. Per-owner Pareto certificates: rule 14 as mathematics

**What.** Every comparison reports a confidence sequence on each owner's utility difference: judge verdicts (E2), policy
promotions (E6) and past results restated. A change is certified when no owner's lower bound is below −ε and at least one
owner's lower bound is above zero.

**Why.** Rule 14 is enforced today as an ordering constraint. This makes it a measured guarantee that a multi-OEM depot
can show each customer, for example: *"Waymo's cars were not made worse by this change, at 95% confidence."*

**Effort.** About 1 session, built inside E2.

### E8. Agents at the edges

*Status 2026-11-05 (3:34 PM CT): D5 decided by Chase ("Okay I agree with you on all fronts. Begin building"). `0795` makes the per-tick order a background challenger (checked, kept and graded, never standing) and the wake gate is on at the twin depot, so the agent is consulted on exceptions plus a 30-sim-minute check-in (`db/checks/0480`). Items 1-4 below are the build list.*

**What.** Move the LLM agent from per-tick charge orders, where 2.6% are taken, to four jobs that need a language model:

1. **Exceptions.** On a fault, an owner request or an E3 monitor alarm, it reads the situation and drafts a plan into
   `ottoq_external_proposals`. The kernel disposes of it.
2. **Explanations.** It explains every verdict and promise in plain language to owners and operators, through
   OTTO-Command (rule 11).
3. **Contracts to terms.** It drafts an owner's typed SLA terms and price vector from contract text, for a person to
   confirm. This fills D4's gap.
4. **Mutation.** It is the mutation operator inside E6.

It stays on in production, proposing only (rule 10, `0629`). The per-tick orders retire once E6 ships a better kernel key,
or they stay on as a low-frequency challenger (D5).

This is L4 of `docs/AGENT_ARCHITECTURE.md` (one coordinator, narrow specialists for unstructured input), and any new
specialist still passes that document's four-condition gate.

**Effort.** About 2 sessions.

### E9. The self-calibrating twin

**What.** Simulation-based inference: neural posterior estimation (Cranmer, Brehmer & Louppe) over the twin's own
parameters. These are the fault rates per kind, arrival intensities, power derates and dwell curves, each fitted as a
posterior with its uncertainty, not as a point. A posterior predictive check runs each night and asks: is today's world
one the twin can produce?

**Why.** When real telemetry flows, the twin must be fitted to the real depot to stay a valid benchmark. Today's
calibration is quantile grids from public datasets.

**Gates.** The research wing only, with the Lab's throughput.

**Effort.** 3–4 sessions.

### E10. Proof-carrying decisions

**What.** Each enacted decision's snapshot carries its certificate:

- the shield evaluations, which are logged today;
- the verdict's e-value and stopping index;
- the promise's coverage and its calibration-set hash;
- the supervisor state;
- the model versions.

A verifier re-checks the certificate without trusting the engine.

CP-SAT proof logging is research-stage. VeriPB-style certificates exist for pseudo-Boolean and some CP reasoning, but on
2026-11-03 I found none for CP-SAT itself.

**Effort.** About 2 sessions, after E2, E3 and E4.

---

## 5. Plan of attack

Every phase commits in this repo's style: migration, check file, FINDINGS row, MIGRATION_LOG row, and a CI step for its
tests. Engine changes ship as dial-gated migrations, switched on at the twin depot under the name of the person who
decided them (rule 12).

### Phase 0: foundations. Needs only the go-ahead and D2.

These run in parallel. None touches production. Building the Lab runs a few simulated days inside it, never in production; Chase's go-ahead of 2026-11-03 ("Okay BEGIN", after the question was put to him) covers those runs:

0. **Re-read the promotion gate honestly.** Compute 0708's AUC interval clustered by (scenario, seed) key, by bootstrap
   over the 17 keys, and record it beside the independent-decision interval. Until then, the gate's condition 2 is
   "reads true on an optimistic interval", not "passed".
1. **E1 Lab bring-up.**
   - Load the engine schema and the twin depot's reference data.
   - Stub what is Supabase-only: `net` and `http` as no-ops, and `vault`. The deterministic kernel does not need them.
   - Replay the agent and solver calls from the ledger, or turn them off.
   - Then run the three acceptance tests: fidelity, forks and throughput.

   *Status 2026-11-04 (Chase: "Begin frontier build step 1", with the token in the session as `Supabase_Key`):
   built, D2(a). The lab is loaded from production's own catalog through the Management API's read-only
   endpoint, and matches production on every routine, table, trigger, index, policy, type, sequence, comment,
   ACL and cron job (6 semantically identical deparse round-trips aside); the twin depot's world fingerprint is
   production's exactly. Agent and solver calls are off (no outbound HTTP; cuOpt quiesced as in a certification
   arm). Throughput: one depot-day in 173 s on one stream (20.8 depot-days an hour), 54.6 an hour on four
   replicas; a pair costs more than its two arms, because both share one transaction. Forks reproduce. The fidelity
   test found an engine defect instead of a lab one: on today's engine a pair fails the end-state atom on a minted id,
   over 12 ticks and over a full depot-day (G510; `0794` passes both, and is in production since 2026-11-05 3:09 PM CT, Chase's approval). A production run's digests could not
   be compared: no pair has run on this engine. Report: `lab/engine/reports/e1_acceptance_2026-11-04.md`.*
2. **E2 replay harness.**
   - Re-price the depot-level hindsight under a grid of prices, for the 323 graded decisions whose hindsight stores all
     four components for both orders.
   - Re-run the pure scheduler on the stored snapshots for the per-owner split.
   - Report which verdicts flip with the price and which do not. This shows how much the judge's answer depends on the
     prices D4 has not yet set.

   *Status 2026-11-04: done, both halves. Depot totals: G508 (`db/checks/0476`). Per owner, in the lab (`0478`, G511):
   the lab re-grades all 370 past decisions exactly as production's grader did, and owner by owner most of the
   referee's wins move one owner's minutes onto another; of the 32 orders it took, 5 were good for every owner. The
   check's per-owner expectation is close to a coin, so E2 is built per owner (E7) on calibrated estimates (E4).*
3. **E3 v0.** Build the G506 cell in CIF, synthesize the supervisor and replay the monitors on `8c0b2e04`.

### Phase 1: the judge and the promises

*Status 2026-11-04: E2's first replay report is done (`db/checks/0479`, G512). Judged owner by owner, a referee that
lets no owner lose takes nothing: reordering the shared charge line was good for every owner in 35 of 370 past
decisions, and the referee's own futures never showed it in more than 8 of 12. Before E2 is built, its shape is a
decision for Chase: project an agent order so each owner keeps its places (rule 14's own form, as 0781 does), or move
the agent off per-tick orders (D5).*

- **E2 build.** The constraint layer, the priced layer, the sequential e-process, and antithetic and stratified futures.
  Measure each on the snapshot replay before building the next.
- **E7, inside E2.** The per-owner confidence sequences.
- **E4 build.** Conformal wrappers and coverage tables on held-out runs, with the quantiles fed into E2's futures.
- **Ship.** Dial-gated migrations, switched on at the twin depot, with one demo run per change to show it working
  (rule 12).

### Phase 2: the supervisor at full scope

Extend E3 from the post cell to the bays, the staging lanes and departure (rule 9's departure test, `0543`). Then:

- run the monitors nightly over the day's events;
- resolve the diff against every hand-written hold;
- run the generated conformance tests in the CI of both otto-q-core and ottoyarddepot-sim.

### Phase 3: the gap

Run E5 on finished runs:
- the clairvoyant bound first, then the penalty;
- the regret split by decision type and by owner.

The regret split ranks Phase 4's targets.

*Status 2026-11-05 (4:21 PM CT): the clairvoyant bound is built and run on the research lab's first full day
(`lab/research/p2_perfect_day/`, normal_day, 116 cars, 12 hours). Minutes from arrival to ready: 24,332 real, about 17,100
best found in the engine's own job order, 15,307 proven bound; holding every owner to no worse than the real day still
gives each owner 25-36% less (the gap is not a trade between owners). By lane, rescheduling the charging posts recovers more
of it than the bays, so Phase 4's first target stays the charge-line key. The battery's half: perfect foresight $1,085
against the day plan's $1,382 and no battery's $1,699 on the same day (each paying for its own peak; the older
fixed-target rule cost $2,225). The penalty (information relaxation) is not built;
more days and fleet sizes are running (`lab/research/p2_capacity/`).*

*Correction 9:36 PM CT on 2026-11-05: that first model gave each charge its session's length on a post, and a car holds its post about
5 minutes longer while the robot unplugs it (10% more post time). With the car's time on the post, solved like for like:
116 cars 24,332 real, 20,055 best found (18% less), 16,185 bound (33%); 150 cars 29,100 real, 25,188 found (13%), 18,935
bound (35%). The room is real and smaller than first published; the owner and lane figures above are the first model's
and are re-solved on the corrected one when the lab's cores are free (`lab/research/p2_perfect_day/README.md`).*

*Status 2026-11-05 (5:29 PM CT), the battery on a second day (seed 424242): planning on a typical day's shape (the other
lab day's load) closes 67-77% of the gap to perfect foresight on both days, and on the second day the day plan did not
lower the peak at all: the battery started 25% full, the plan holds a 600 kWh demand-response reserve from the first
minute of the day (no call came; needed only from 2 PM it costs nothing in hindsight), and its floor rises at every surge
(G517). The battery's build order is in `docs/AGENT_ARCHITECTURE.md` (where the agent earns its place, item 1).*

*Status 9:02 PM CT on 2026-11-05: the first step of that order is in production. 0797 holds the call reserve from 3 hours before the
window and lets the floor stop rising at every surge; switched on at the twin depot at 8:57 PM CT on 2026-11-05 after
three lab gates (at its defaults it reproduces a day exactly; on, the two lab days bill $1,301 and $1,295; on a day with
a 2 PM call every car is the same and the battery meets the call 85.5% full instead of 74.9%). Next in the order: the
planner that plans its own refill (`lab/research/p2_capacity/battery_lp.py`, proven in the lab loop).*

### Phase 4: the inventor. Needs D3.

E6 in the Lab, on the target with the most regret in Phase 3: the charge-line key unless E5 says otherwise.

Each candidate that passes all three tiers becomes a recommendation for a person to ship.

### Phase 5: agents, the self-calibrating twin, and proof-carrying decisions

E8, E9 and E10, in that order. E8 can start earlier, because explanations and contract drafting need nothing else.

**What Chase sees and when.** Each phase ends with a short report:
- what was built;
- what was measured, with run IDs;
- what was not verified;
- what is now on at the twin depot.

---

## 6. Decisions for Chase

| | Decision | Recommendation |
|---|---|---|
| D1 | **Go-ahead and order.** Phases 0→5 as above. | Start Phase 0 now. All three of its items stay out of production. |
| D2 | **Where the Lab runs.** *Decided 2026-11-03: in the working session, at no extra database cost (Option 1).* How it is loaded, as measured that morning: the production Postgres port is not reachable from the session (a CONNECT to :5432 timed out), so `pg_dump` over a connection string is not available; the Supabase Management API is reachable over HTTPS. (a) A Supabase access token as the environment secret `SUPABASE_ACCESS_TOKEN` (scoped to reading otto-q-core's database where the account offers scoped tokens), read in a new session, exports schema and reference data straight to files. (b) Without it: the engine rebuilt from `db/baseline` plus the later migrations, checked against production function by function through the existing read access; no bulk data. (c) A separate Supabase project for unattended runs later: Small ~$15, Medium ~$60, Large ~$110 a month, billed hourly, nothing while paused ([Supabase compute pricing](https://supabase.com/docs/guides/platform/manage-your-usage/compute), read 2026-11-03). Note: a `SUPABASE_ACCESS_TOKEN` for CI was declined on 2026-09-21 by decision (verify.yml); the one asked for here is for the session environment. | (a) for the full copy; (b) started without waiting. *2026-11-04: (a) done. The session's token (environment name `Supabase_Key`) reaches the Management API's read-only endpoint (`/database/query/read-only`, runs as `supabase_read_only_user`); the token itself can see all three projects, and `lab/engine/lib/prod_read.py` reads otto-q-core only.* |
| D3 | **A rule-12 exception for the Lab only.** Unattended runs and pairs in the Lab database, never in production, for E1's acceptance tests, E6 and E9. Plus a compute and API budget for E6. | Yes, scoped to the Lab, with a monthly cap you set. |
| D4 | **Owners' prices.** What a minute of lateness, a minute past the contract wait and a minute out at work are worth, per owner. The four SLAs carry none. | Set a default now (equal weights) for the Phase 0 replay, which reports the flips across prices. Then set real prices per owner, or have E8 draft them from contracts for you to confirm. |
| D5 | **The agent's role.** Keep per-tick charge orders, or move the agent to exceptions, explanations, contracts and mutation (E8). | Move it, and keep the per-tick orders as a low-frequency challenger until E6 ships a better key. |

---

## 7. Rule gates, checked item by item

| Rule | How the plan keeps it |
|---|---|
| 8, one site | Everything is at the twin depot `11111111-…`. The Lab loads that depot only. |
| 9, vehicle first | Rule 9 is a constraint layer in E2, a fixed skeleton in E6, and requirements R4 and R5 in E3. No item prices, shortens, skips or defers a vehicle's need. |
| 10, no experiments in production | Hypotheses and tests live in the Lab (E1, E6, E9). Production gets estimates (E4), monitors (E3) and an improved disposer (E2) as certified changes a person ships. The agent proposes only. |
| 12, no testing while building | Phases 0–3 start no run or pair. Each finished change goes on at the twin depot with one demo run. The Lab's tests wait for D3. |
| 13, no ceiling | E5's bound uses what is installed. Nothing adds a cap. |
| 14, owners | E2's owner guard is a constraint. E7 certifies per owner. No item trades one owner's car for another's. |
| 6, kernel purity and propose/dispose | The judge, synthesis, monitors, conformal wrapper, Lab and forks are kernel. The post-cell model is pack data. Agents and evolved code only propose. |
| 3, provenance | Every external claim in §9 carries a date and a URL. |

---

## 8. Bugs and gaps found on the way

| # | Finding | Status |
|---|---|---|
| 1 | **G506.** A faulted post kept its car while its cleaning arm worked (339 s and 309 s on `8c0b2e04`). | Engine fixed: 0792 applied 10:18 PM CT, PR #264. Renderer fixed in ottoyarddepot-sim PR #154, which needs merging and a Lovable Publish. |
| 2 | A faulted session's closing StatusNotification reads `Available`, and no frame marks the repair. A charger back end reading the stream would offer the post. | Open (`db/checks/0474` §5). |
| 3 | The closing OCPP frames carry no `charger_id`. | 0723, still pending. |
| 4 | The fault re-queue threshold `target − 5` in `twin.ottoq_sim_stop_charge_session` predates rule 9's 100%. 0543 still sends the car back to finish. | Open, low risk. |
| 5 | Between the release and the arm's exit, the engine does not hold the car for the arm; there is no robot "clear" signal. | Open. E3 models it. |
| 6 | The lexicographic yardstick: 137 of 141 "missed wins" gained no on-time car, and in the 92 decided at lateness the kernel's order had a mean 18.6 more out-at-work minutes (§2.2). | Open. E2. |
| 7 | The judge discriminates weakly: AUC 0.656 [0.599, 0.713], Brier 0.239 against 0.247 at the base rate. 0708's gate reads `discriminates = true` for the first time, but on an interval that assumes 364 independent decisions drawn from 17 keys (§2.1). | Open. Phase 0 computes a key-clustered interval, then E2. |
| 8 | The agent's take rate is 29 of 1,118 orders since 2026-10-20, and 0 of 128 on `763734d4` (§2.3). | Open. E2 and E8. |
| 9 | The contracts carry no prices: `penalty_schedule = {}` in all four SLAs. | Open. D4. |
| 10 | The research lab is inside production (G141; rule 10's decision of 2026-09-27). | Open. E1. |
| 11 | The renderer reads the layout per depot (`/depot/{id}/layout`, `src/lib/ottoTwin.ts:800`), never per run. A past run replays on today's charger build. | Open (ottoyarddepot-sim). |
| 12 | ottoyard-agent-context is stale: `10_KNOWN_ISSUES.md` and `11_BACKLOG.md` are dated 2026-08-08, nearly three months back. | Open. |
| 13 | Twin vehicle IDs share prefixes (`b2222222-0002…`), so prefix matches on IDs collide. Tonight's timeline queries had to be redone with full IDs. | Hazard; always match full IDs. |
| 14 | Idle cockpits drew the as-built chargers, not the twin's build. | Fixed by ottoyarddepot-sim PR #153 (merged). Needs a Lovable Publish. |
| 15 | Tonight's 17 orders from `8c0b2e04` are not yet graded. | Expected: cron 787 grades them tomorrow between 5:00 and 6:50 AM CT, if no run is live. |

---

## 9. Sources

Each source records the claim used, its version or date, and the URL. All were read 2026-11-03 through web search
results. One standing caveat: where a search returned an abstract or listing rather than the paper itself, only the
abstract-level claim is used.

| Claim used | Version / date | Source |
|---|---|---|
| AlphaEvolve found a Borg scheduling heuristic, in production, that recovers on average 0.7% of Google's worldwide compute. | DeepMind blog, 2025-05-14 | https://deepmind.google/blog/alphaevolve-a-gemini-powered-coding-agent-for-designing-advanced-algorithms/ |
| FunSearch pairs a frozen LLM with an evaluator that guards against confabulation. It evolves only the critical function inside a fixed skeleton, such as a greedy program's priority function, and found online bin-packing heuristics that beat baselines. | Romera-Paredes et al., *Nature* 625:468–475, 2023-12-14, DOI 10.1038/s41586-023-06924-6 | https://www.nature.com/articles/s41586-023-06924-6 |
| EoH evolves natural-language "thoughts" and code together. Its repo includes flow-shop scheduling and reports beating FunSearch on online bin packing with fewer LLM queries. | Liu et al., ICML 2024 (oral), arXiv 2401.02051 | https://arxiv.org/abs/2401.02051 · https://github.com/FeiLiu36/EoH |
| Betting confidence sequences for bounded means are anytime-valid through Ville's inequality and adapt to the unknown variance. | Waudby-Smith & Ramdas, JRSS-B discussion paper (RSS meeting May 2023), arXiv 2010.09686 | https://arxiv.org/abs/2010.09686 |
| Sequential A/B tests with E-variables keep Type-I error control under optional stopping. | Turner & Grünwald, CWI | https://ir.cwi.nl/pub/31674 |
| Adaptive conformal inference controls long-run miscoverage without assumptions on the data-generating process. | Gibbs & Candès, NeurIPS 2021, arXiv 2106.00170 | https://arxiv.org/abs/2106.00170 |
| Distribution-free, finite-sample guarantees on miscoverage and regret for robust predict-then-optimize policies, with a certified miscoverage–regret frontier. | Zhou & Zhu, arXiv 2510.07750 (ICML 2026 poster) | https://arxiv.org/abs/2510.07750 |
| Information relaxations bound stochastic dynamic programs by relaxing nonanticipativity with a penalty. Weak and strong duality hold. | Brown, Smith & Sun, *Operations Research* 58(4):785–801, 2010 | https://jimsmith.host.dartmouth.edu/wp-content/uploads/2022/04/Information_Relaxations_and_Duality_in_Stochastic_Dynamic_Programs.pdf |
| The regret algorithm evaluates every decision on all sampled scenarios. Tested on online packet scheduling and vehicle routing with time windows. | Bent & Van Hentenryck, AAAI 2004; book *Online Stochastic Combinatorial Optimization*, MIT Press 2006 | https://cdn.aaai.org/AAAI/2004/AAAI04-080.pdf |
| High Confidence Policy Improvement returns a policy below a user-chosen performance bound with probability at most a chosen level. | Thomas, Theocharous & Ghavamzadeh, ICML 2015, PMLR 37:2380–2388 | https://proceedings.mlr.press/v37/thomas15.html |
| CIF's symbolic synthesis computes the maximally permissive, controllable, nonblocking set of safe states. ESCET v4.0 dates from June 2024; the paper adds 23 industrial and academic benchmark models. Multi-level synthesis helps only somewhat. | Hendriks, Reniers, Fokkink & Oortwijn, arXiv 2511.04370 (Nov 2025) | https://arxiv.org/abs/2511.04370 · https://eclipse.dev/escet/about.html |
| A shield synthesized from a two-player safety game is the most permissive. Pre- and post-shielding with UPPAAL Stratego. | Brorholt, Jensen, Larsen, Lorber & Schilling, arXiv 2308.14424 | https://arxiv.org/abs/2308.14424 |
| The Simplex architecture: a verified baseline controller, and a decision module that switches away from an unverified advanced controller. This is the shape of propose/dispose. | Phan et al., Neural Simplex Architecture, arXiv 1908.00528 | https://arxiv.org/pdf/1908.00528.pdf |
| Simulation-based inference for simulators whose likelihoods are intractable. | Cranmer, Brehmer & Louppe, *PNAS* 117(48):30055–30062, 2020, arXiv 1911.01429 | https://arxiv.org/abs/1911.01429 |
| VeriPB proof logging certifies pseudo-Boolean and some CP reasoning. Full-CP proof logging is ongoing work. I found no CP-SAT-specific proof logging. | arXiv 2203.12275; CP 2024 | https://arxiv.org/abs/2203.12275 |
| Rocsys M1: robotic multi-bay hands-free charging for robotaxis, in pilot, with large-scale rollout from 2027. Its overhead mount allows cleaning and inspection during charging. | Electrek, 2026-04-29 | https://electrek.co/2026/04/29/rocsys-unveils-multi-bay-hands-free-robotaxi-charging-raises-13m/ |
| Robodock: autonomous depots for robotaxis, with charging robots and visual damage inspection. | 2026-02-23 | https://thelastdriverlicenseholder.com/2026/02/23/robodock-autonomous-depots-for-robotaxis/ |
| Joule Labs AURA: an autonomous robotic charging system for robotaxi fleets. | Joule Labs blog | https://www.joulelabs.com/blog/how-robotaxi-fleets-charge |

**Internal sources:**
- `docs/research/answers/R-12`: cuOpt's routing solver documents no seed and no determinism parameter.
- CLAUDE.md 2.5, 2.9a and the C5 correction: the determinism substrate and common random numbers.
- `db/checks/0474`: G506.
