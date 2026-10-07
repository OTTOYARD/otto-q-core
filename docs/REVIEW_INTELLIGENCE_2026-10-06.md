# OTTO-Q intelligence audit: 2026-10-06

Chase asked, 2026-10-06: *"do an audit pass of OTTO-Q overall and make sure we're not missing anything and it's truly
hyper intelligent and learns from itself and finds intelligent proposals. And orchestration."*

Written 9:30 PM – 10:45 PM CT. Every figure comes from read-only queries on committed rows, with its run and its
moment. Most figures are from **run fd6ed035** (the run Chase watched: busy_day at the twin depot, 116 cars, sim
8:00 AM – 1:50 PM CT, started 1:50 PM CT, completed). Ledger figures are partitioned by day before they are quoted
(CLAUDE.md rule 6's standing test), and the last day is quoted. Rules 8, 9 and 10 bind everything below: one depot, no
short charging, no experiments in production.

---

## The answer in plain language

**The safety and the orchestration hold. The intelligence is thinner than the stack makes it look, and OTTO-Q does not
yet learn from itself.**

1. **It did not waste a working charger.** Cars queued at the gate for the whole run, but every working charger was in
   use or had a car on its way. The free charger time was charger faults. The queue is a capacity limit, not a bad
   decision. Two independent measurements agree.
2. **Its fast chargers spend a third of their sessions on the slow end of the charge curve.** 23 of 70 DCFC sessions
   started at 80% or more. This is the largest orchestration lever found, and it needs no shorter charge.
3. **The solvers' offers were refused because another OTTO-Q path took the stall first, not because they were bad.**
   The planners do not see each other's picks inside a tick.
4. **The agent fell back on a third of its passes on 2026-10-06, because NVIDIA's endpoint refused (503, 429).** And
   the goal it sets was the same, readiness first, on every solver call that day. A choice that never changes adds no
   information.
5. **OTTO-Q grades itself, but it does not update itself.** The challenger grades decisions. No function updates the
   engine's estimates (charge times, return times, fault rates) from its own results. This is the main gap behind
   "learns from itself".

---

## 1. Orchestration: what the depot did with its chargers

**Cars waited at the gate in all 351 minutes of the run:** 37.3 on average, 57 at most. 155 waits, 84.4 minutes each
on average, 218.1 car-hours in all. That is the 32% "Waiting after arrival" on the new KPI board.

**But the chargers were full.** Per charger-minute while at least one car waited:

| | charger-minutes | a car on it | reserved, car on its way | free and unreserved |
|---|---:|---:|---:|---:|
| DCFC (10) | 3,510 | 3,003 (85.6%) | 96 (2.7%) | 411 (11.7%) |
| L2 (30) | 10,530 | 10,032 (95.3%) | 105 (1.0%) | 393 (3.7%) |

The 804 free charger-minutes match the run's **14 charger faults, which carried 753 minutes of repair**
(`ottoq_variability_cards.meta->>'repair_minutes'`, 10 to 138 minutes each). The challenger reached the same answer
on its own: `charger_faulted_while_cars_wait` 9 confirmed and 5 inconclusive, `charger_offerable_while_cars_wait` 3 of
3 refuted.

**A finished car leaves its charger at once:** 141 `charge_complete_holding` spells, 0.3 car-hours in all, 6 seconds
each on average.

**Every car left full and nothing was skipped:** 118 of 118 dispatches at 99% or more. 43 times a car staged to leave
had work open and went back to finish it. That is rule 9's recheck working.

**So the 40% waiting is capacity.** Under rule 9 the answers are more capacity, fewer faults and better order, never
shorter charges.

### The lever: fast chargers on the slow end of the curve

| fd6ed035 | sessions | median start SoC | started at 60%+ | started at 80%+ | average power |
|---|---:|---:|---:|---:|---:|
| DCFC | 70 | 49% | 29 | **23 (33%)** | **38.6 kW** |
| L2 | 106 | 64.5% | 57 | 46 | 8.1 kW |

(`ocpp_sessions`, joined to `stalls` at the twin depot.) Above 80% a car takes a small part of a fast charger's power,
and it holds the charger for the whole taper. Meanwhile an average of 37 cars waited at the gate, at 53% average SoC
on return. **Hypothesis for the research wing (rule 10), not measured as a gain:** send fast chargers to the cars
lowest on the curve and let L2 serve the cars near full. Every car still charges to 100%. Only the order and the
charger type change. This is rule 9's "better ordering of who is served next". The twin's own simple assigner already
does this (`twin.ottoq_sim_auto_charge_assign_tick`: DCFC below 50%, else L2). So the 23 high-SoC DCFC sessions come
from another path, and which one is the first thing to find.

---

## 2. Proposals: why the planners' offers were refused

`ottoq_proposal_disposition_ledger` on fd6ed035:

| proposer | real offers | used | refused | why refused | abstained |
|---|---:|---:|---:|---|---:|
| CP-SAT (`forward_lex`) | 49 | 0 | 48 | 24 stall occupied, 24 stall reserved | 535 |
| greedy (`greedy_constrained`) | 125 | 9 | 116 | stall reserved | 0 |
| service priority | 97 | 0 | 0 | 97 replaced by a newer or another offer | 0 |

**At the moment of the decision, 162 of the 164 refused offers named a stall that another car held.** The other 2
named the stall the car already held. From each stall's own event history:

- **CP-SAT, stall reserved (24):** the other car's hold was written a median **0.8 s before** the offer. The solver
  read its frame, then another path reserved the stall, then the offer arrived.
- **CP-SAT, stall occupied (24):** a car pulled in around the moment of the offer. In 15 of them it was after the offer.
- **Greedy (116):** the hold was written **in the same instant, after the offer**. Another path took the stall earlier
  in the same tick.
- In none of the 48 CP-SAT cases did the other car have a calendar booking on that stall before the decision. The
  hold was a pointer reservation (`stalls.reserved_by`), the gate the calendar cannot see.

**So the red "refused" beads in the stack are mostly OTTO-Q's own paths colliding inside a second.** The offers were
not unsafe. They were late.

**CP-SAT mostly has nothing to decide.** On 2026-10-06 (`ottoq_model_call_ledger`, live): 347 calls, **323 (93%)
with zero candidate rows**, 23 answered, 0 enacted. The depot was full, so its frame was empty. CP-SAT is not wrong
here, but on this scenario it is not doing work either.

**cuOpt has not been called since 2026-09-27 12:03 UTC.** Not once on fd6ed035, although the bridge set
`cuopt_propose_enabled = 1` for that run at 18:58:57 UTC. The cause is not established. On one depot it has no routing
problem to solve (rule 8), so this costs nothing yet. But the stack should not suggest that it runs.

---

## 3. The agent: what the AI layer added

`ottoq_model_call_ledger`, provider `nvidia_nemotron`, live, by day:

| day (UTC) | passes | answered | fell back | fallback share |
|---|---:|---:|---:|---:|
| 2026-09-30 | 555 | 537 | 18 | 3% |
| 2026-10-01 | 592 | 548 | 44 | 7% |
| 2026-10-02 | 611 | 581 | 30 | 5% |
| **2026-10-06** | **348** | **232** | **116** | **33%** |

**The 10-06 fallbacks are NVIDIA's hosted endpoint, not the agent:** 81 were HTTP 503 (service unavailable), 33 were
HTTP 429 (too many requests), and 2 timed out at 75 s. Each fallback kept the deterministic answer, so safety did not
move. But Chase saw it: "11 passes · 5 fell back".

**The goal never changed.** 346 of the 347 CP-SAT calls on 10-06 ran on `readiness_first` (the other carried no
objective), whether the agent answered or fell back. With the depot backlogged all day, readiness first is probably
the right goal. But an agent whose answer never changes is a constant, and a constant needs no model. `db/checks/0332` reached the same point from the other side: its advice
rarely differs from fresh advice.

**What would make it earn its place:** give it a decision that changes with the depot. Two candidates fit the rules: the
charger-type order in §1 when the queue is long, and the battery's afternoon reserve against the forecast peak in §5.
Each would be proposed, then disposed by the decide path, as today.

---

## 4. Learning: does OTTO-Q learn from itself?

**What exists:**

- **The challenger grades the engine's own decisions, read-only, every minute** (cron 765, `ottoq_challenger_tick`).
  On fd6ed035 it opened and closed 17 questions. That is rule 10's grading half.
- **The research wing's dial experiments** (`ottoq_learning_board`). Since `0540` they only recommend. A person ships a
  win as a certified change.
- **The weekly ingest refit** (cron 2, `ottoq_twin_ingest_refresh` / `ottoq_twin_refit_distribution`) refreshes
  *external* priors: EIA grid, NOAA weather.

**What does not exist: nothing updates the engine's own estimates from its own results.**

- `ottoq_estimate_charge_minutes` integrates the twin's own charge-rate function (`ottoq_sim_compute_charge_rate`,
  noise seed 0). The planner knows the simulator's physics exactly. A real depot will not give it that, so this path
  fails the swap test.
- The forecasters in `ottoq-intelligence` read fixed priors (`app/forecasters/priors_snapshot.json`).
- No function in `public`, `ottoq` or `twin` writes `ottoq_calibration_distributions`, `_profiles` or `_metrics` from
  run results. The only writers are the external ingest and refit.

**So the honest sentence is: OTTO-Q grades itself, but it does not yet learn.** Rule 10 says production *"overnight
... updates its estimates (how long charges take, when cars return, which chargers fault)"*. The grading half is built.
The estimate half is not.

**The data to learn from is already recorded.** fd6ed035 alone holds 58,487 OCPP `MeterValues` messages (real
charge curves per car), atom start and end times (service durations), dispatch and return times (trip lengths), and 14
fault records with repair times.

---

## 5. Smaller findings

- **The twin's OCPP log reports a faulted charger as available.** `twin.ottoq_sim_stop_charge_session` emits a
  `StatusNotification` with `connectorStatus = 'Available'` on every stop, the fault stops included. Only then does it
  set `ottoq_ocpp_chargers.station_state = 'Faulted'`. fd6ed035's log holds 136 `Available` notifications, 0 `Faulted`
  ones, and 14 faults. A real charger sends `Faulted`. A real CSMS would read this log as a free charger, so this is a
  swap-test gap at the protocol layer.
- **The archive cannot tell a faulted charger from a free one.** The stall record never leaves `available` or
  `occupied`, and the OCPP log says `Available` (above). §1 had to match fault repair times to free minutes by sum.
- **KPI 3's 15-minute window does not match this depot's bill.** CLAUDE.md 2.9 says the 15-minute peak *"matches
  demand billing"*. The twin depot's own tariff, NES GSA-3, bills 30 minutes (`demand_basis = 'NCP_30min'`). The KPI
  board now prices the 30-minute peak (`0611`). The five-KPI view is unchanged.
- **The sweep scorer counts short final windows.** `ottoq_arm_peak_profile` averages the run's last windows over less
  than 30 minutes. On fd6ed035 a 19.6-minute window sets its peak: 654.1 kW against 638.6 kW full-window, $315 a
  month. The board uses full windows. The scorer is unchanged, because both arms of its pairs end on the same tick.

---

## What I recommend, in order

| # | Move | Why first | What it needs |
|---|---|---|---|
| 1 | **Nightly estimate refit from the run's own records:** charge curves per model from `MeterValues`, service durations, return times, fault rates per charger. Each refit is a new calibration version. The planner's estimates read the version pinned to the run, and the challenger grades the forecast error each day. | It is the "learns from itself" Chase asked about, and rule 10's overnight learning. It also fixes the swap-test gap in `ottoq_estimate_charge_minutes`. | New tables, a refit job and a read path. Versions pinned per run keep determinism. A design review first. |
| 2 | **Dispose by intent:** when an offer's stall is taken, place the car on an equivalent offerable stall (same type, same capability) if one exists. Refuse only if none does. Also give all proposers one claim set per tick. | 162 of 164 refusals on fd6ed035 were collisions inside a second. Offers would count, and red would mean a real refusal. | A decide-path change. Forces recert. Chase's call. |
| 3 | **Charge-curve-aware charger order** (§1), tested by the research wing in the twin as a paired experiment. | 33% of DCFC sessions on the taper at 38.6 kW average, with 37 cars queued. No charge is shortened. | A paired twin experiment (rule 10), then a certified change if it wins. |
| 4 | **Agent resilience:** retry once with backoff on 429/503, and add a second endpoint. Then give the agent a decision that changes with the depot (§3). | 33% fallback on 10-06, all from the provider. And a constant goal adds nothing. | An edge-function change and a deploy. |
| 5 | **Emit `Faulted` on a fault stop**, and `Available` when the repair ends. | Protocol truth, and the archive can then tell faults from idle time. | A twin change. Check which atoms it moves before you apply it. |
| 6 | **A depot-grade charger-fault profile** as the base case, with today's public-network profile kept as a stress case. See `docs/research/direct/2026-10-06-av-world-models-and-data-integrations.md` §2C. | 753 repair-minutes on fd6ed035 cut about 5% of charger capacity while 37 cars queued. | Chase's decision. It changes every KPI and forces recert. |

**Built in this change:** the KPI board's monthly demand charge (`0611`): $12,988.60 a month at a 638.6 kW 30-minute
peak on fd6ed035, and $1,571.95 a month that the battery took off it.
