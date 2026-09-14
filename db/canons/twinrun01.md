# Twin run 01 — the end-to-end proof, predicted before it is run

**Status: PRE-RUN.** Written 2026-09-14 20:45 UTC (3:45 PM CT), while round 44's
48-tick pair is still executing. A prediction recorded after the result is not a
prediction, and this run exists to answer a question Chase asked directly:

> "We need to make sure OTTO-Q works end to end when we start a new sim run in
> OTTO-Twin."

The judgement goes below the line, after the run.

## What is being proved, and what is NOT

**Proved:** that a run started through the door the Twin UI actually calls moves
the whole chain — world in, need derived, recall decided, agent offered a say,
kernel disposed, shield consulted, calendar booked, command emitted, SDR written
— and that the run **armed its own agent layer** without anyone doing it by hand.

**Not proved, and the watcher says so in its own notes:** that a consumer takes
delivery of anything (hop 14 cannot pass — the twin executes commands in-process),
and that the engine is deterministic (that is the certification's job, and the
certification deliberately runs with the proposer OFF, tagged `0152_cert_quiesce`).

## The procedure, fixed in advance

1. Confirm **every** `r44_*` job is unscheduled and `pg_stat_activity` shows no
   pair. That is the only authority; it is what cost round 43 two pairs.
2. Apply `0325` then `0327` per `scripts/APPLYING.md`.
3. `SELECT public.ottoq_sim_run_scenario(...)` — the function
   `otto-twin-control`'s `POST /scenarios/start` calls. **Not**
   `twin.ottoq_sim_start_run`: the point is to use the UI's door.
4. Let pg_cron job 12 (`ottoq-demo-metronome`, every minute) advance it. No
   manual ticking — a hand-driven run proves the hand, not the engine.
5. Run `scripts/watch-run.sql` at roughly 5 and 15 minutes.

## The predictions, each with its falsifier

**P1 — hop 1 reads `armed`.** `0323` injected the arming call into both start
doors and the live bodies were verified to carry it (call present, receipt
written, `cert_harness` guard ahead of the call). Twenty runs have started since
`0323` applied and **all twenty were `cert_harness`, so the receipt has never
once been written**. This is the first firing of that path.
*Falsifier:* `(NO RECEIPT)` means the substitution did not reach the door the UI
uses; `REFUSED` means `ottoq_agentic_arm` raised, and the note carries the reason.

**P2 — hop 5 stops reading 0 of N.** The measured baseline is **0 of 117 active
dispatches carrying a forecast**, and every one of those 117 belongs to a
completed or aborted run — orphans nothing ticks. `0321` put a per-tick refresh
into `twin.ottoq_sim_advance_deployed_telemetry`, so a LIVE run should give its
active dispatches an ETA within a tick or two.
*Falsifier:* still 0 of N after ten ticks with active dispatches present means
`0321`'s S1 substitution is not on the live tick path, and I must say so plainly
rather than explain it away. **This is the one prediction I most want to be
wrong about early**, because it is the only part of the forecast work that live
traffic has never exercised.

**P3 — hop 6 shows more than one distinct ETA under a `computed:*` label.** A
computed forecast that holds one value is a constant wearing a computation's
name — the exact defect `0320` was written for, and the check the distinct-count
column exists to make.
*Falsifier:* `computed:distance_over_speed` with `1 distinct min`.

**P4 — hop 8 is NOT required to be non-zero, and a zero there is not a failure.**
Armed is not fired. The in-database proposers (`greedy_constrained`,
`ottoq_service_priority`) write on their own tick and should appear; the external
CP-SAT bridge writes `forward_lex` and fires from GitHub Actions on the default
branch only, at the documented 5-minute floor, so it may or may not catch this
run. Recorded so that a later reader cannot turn a silent proposer into a claim
in either direction.

**P5 — hop 14 reads 0 of N, and that is CORRECT.** Stated here so it is not read
as a regression when it happens. `0325` adds the dock for energy commands; a
consumer for either dock is still unbuilt (G70, G8).

## What would make me stop the run rather than finish it

* Any `r44_*` job still scheduled, or any pair in `pg_stat_activity`.
* A second run appearing — `ottoq_sim_start_run`'s one-world guard is global with
  no depot predicate, so two runs anywhere on the instance is an outage, not a
  race.
* `0325` or `0327` failing a precondition. The file stops; I do not "fix it
  forward" mid-window.

---

## THE JUDGEMENT — 2026-09-14 21:45 UTC (4:45 PM CT)

**Run `34ffb2d9-bcc6-4232-bbfc-d2c4d51e4ec5`**, `busy_day`, seed 909090,
`run_by='otto_twin'`, started 21:43:32 UTC through `public.ottoq_sim_run_scenario`
— the function `otto-twin-control`'s `POST /scenarios/start` calls. Advanced by
pg_cron job 12, not by hand. Read at tick 7.

**All five predictions held.** The chain moves end to end.

| hop | | reading |
|---|---|---|
| 0 | RUN | busy_day seed=909090 running, 7 ticks, clock 09-15 01:13 |
| 1 | **ARM** | **armed** — all three dials verified set on the run itself |
| 2 | world: telemetry | 205 packets, 201 positioned, 71 vehicles |
| 3 | world: energy commands | 14 — bess_setpoint_kw, charge_cap_kw |
| 4 | need: visit needs | 66 — open=40 in_progress=26 |
| 5 | **FORECAST coverage** | **14/14**, all stamped, newest stamp = the run's own clock |
| 6 | FORECAST provenance | computed:distance_over_speed=56 (**14 distinct**), fixture:prime_deployment=15 (1 distinct) |
| 7 | recall | 205 decisions, naive_threshold_v1 |
| 8 | **AGENT proposals** | 19 — greedy_constrained: 8 enacted, 8 pending, 3 superseded |
| 9 | AGENT deferrals | 32 |
| 10 | KERNEL disposed | 420 — (no source)=360, inspect_seam=30, reservation_honoured=18, **greedy_constrained=9**, deterministic_fallback=2 |
| 11 | SHIELD | 1,118 evaluations, 1 refusal |
| 12 | ASSET bookings | 315 |
| 13 | ASSET commands | 175 — begin_charge, proceed_to_stall, stage |
| 14 | OUTBOUND delivered | **0/175** — correct, and predicted |
| 15 | OUTCOME SDRs | 50 |

### P1 — hop 1 reads `armed`: **HELD.**

`payload->'agentic_arm' = {"ok": true}`, and the receipt is not a claim: read
back through `ottoq_policy_get` on this run, `proposer_frame_facts=1`,
`proposer_hold_enabled=1`, `cuopt_first_refusal_max_defers=1`. Before 0323,
across 1,147 runs, no database function and no edge function had ever called
`ottoq_agentic_arm`. **This is the first run in the engine's life to arm itself
at the door**, and the twenty certification runs since 0323 correctly refused.

### P2 — hop 5 stops reading 0 of N: **HELD, and this was the one that mattered.**

**14 of 14 active dispatches carry a forecast**, every one stamped, newest stamp
equal to the run's own sim clock. The pre-0321 baseline was **0 of 68** — and
every one of those 68 was an orphan of a completed or aborted run, which is why
this could not be settled without a live run. **0321's per-tick refresh is on
the live path.** The forecast work is now proven on live traffic, not only on
completed traffic (db/checks/0245).

### P3 — a `computed:*` label holding more than one value: **HELD.**

`computed:distance_over_speed` = 56 rows over **14 distinct** minute values, and
`fixture:prime_deployment` = 15 rows over exactly **1** — which is correct, it is
a fixture constant. The distinct-value column separates a real computation from a
constant wearing a computation's name in the same glance, which is what it was
added for.

### P4 — hop 8 not required to be non-zero: **it was non-zero, and disposed.**

19 proposals from `greedy_constrained` — 8 enacted, 8 pending, 3 superseded — and
hop 10 attributes **9 disposed decisions to `greedy_constrained`**. 32 deferrals:
32 ticks where the kernel held a seat for a proposer before deciding itself.
**"Agents propose, solver disposes" is measured here, not asserted.**

### P5 — hop 14 reads 0 of N and that is correct: **HELD.**

0 of 175. Predicted in advance precisely so it could not be misread: the twin
executes a command in-process and never takes delivery. G70 is unmoved by this
run and was never going to be.

---

## WHAT THE RUN ALSO SHOWED, unprompted

**1. `ottoq_agentic_arm` does not arm the cuOpt post path, and the name invites
the opposite reading.** Measured on this run: `cuopt_propose_enabled = 0`. There
is no run-scoped row — it resolves from the **global** tier, set to 0 on 09-02 by
`0152_deterministic_only`, whose catalog entry says in its own words: *"global
tier is 0 - the deterministic core runs alone. Re-enable per run with a
run-scoped 1."* Arming sets three dials and that is not one of them.

Given the standing decision to cut cuOpt this is the RIGHT state, not a defect —
and the dial gates `cuopt_refresh` and the `cron_tick` orchestrate-tick edge post
specifically, neither of which is the in-database proposer that produced hop 8's
19 proposals, nor the external CP-SAT bridge. But "armed" must not be read as
"every proposer path is open", and this file is where that is written down.

**2. Attribution is still the weak column.** Hop 10: 360 of 420 disposed
decisions carry no `source` in `enacted_action`, i.e. 86% — consistent with G67's
~87% fleet-wide. The 60 that do carry one are the only decisions attributable to
anything at all. The hop's own note says this; it is the reason the source
breakdown, not the total, is the number to read.

**3. The two doors have different scenario libraries.** `ottoq_sim_run_scenario`
resolves against `ottoq_sim_scenarios WHERE status='available'` — ten scenarios,
and `bench_busy_day` is not among them. The certification's door,
`twin.ottoq_sim_start_run`, runs `bench_*` scenarios the UI cannot reach. Not a
defect; worth knowing before anyone assumes a scenario name works at both doors.
This run used `busy_day`, the flagship scenario, with a seed no canon uses.

---

## SECOND READING — tick 23, sim clock 09-15 09:13 (21:50 UTC)

Everything deepened, and one hop changed in a way the file predicted.

| hop | tick 7 | tick 23 |
|---|---|---|
| 5 FORECAST coverage | 14/14 | **0/0** — see below |
| 6 provenance | 2 labels | 3: computed=78 (**13 distinct**), fixture=15 (1), booking_plan:secured=1 (1) |
| 8 AGENT proposals | 19 | 15 in the working set, **9 enacted**, and a SECOND proposer appears (`ottoq_service_priority`) |
| 9 AGENT deferrals | 32 | **58** |
| 10 KERNEL disposed | 420, 9 from the proposer | **1,769, 70 from the proposer** |
| 11 SHIELD | 1,118 evals, 1 refusal | **3,267 evals, 13 refusals** |
| 13 ASSET commands | 175, 3 types | **444**, 5 types (adds `enter_service`, `enter_wash`) |
| 15 OUTCOME SDRs | 50 | **227** |

**Hop 5 reading `0/0` here is the case the watcher's own note was written for, and
it is not a regression.** The sim clock is 09:13 — morning, fleet in depot, no
dispatch currently `active`. `0/0` is not `0/N`: the hop can only speak while
vehicles are out. Hop 6 is the check that the forecast kept working through the
interval — 78 rows now carry `computed:distance_over_speed` across 13 distinct
values, up from 56 across 14 — those are dispatches that have since completed.

**The proposer's influence grew with the run**, which is the reading that matters
for "agents propose, solver disposes": 9 → **70** disposed decisions attributed to
`greedy_constrained`, and 32 → **58** ticks where the kernel held a seat open
before deciding itself. A second proposer, `ottoq_service_priority`, entered with
2 pending.

**The shield is being asked, and refusing.** 3,267 evaluations against 1,769
decisions — 1.8 evaluations per decision — and 13 refusals. `db/checks/0146`
convicted baseline policies that evaluated NO rules while looking productive;
this is the opposite reading and it is why hop 11 is compared against hop 10
rather than read alone.

---

## HOW THE RUN ENDED — 21:48 UTC, 25 ticks, 11.1 real minutes

`status='completed'`, and the engine recorded WHY on the row rather than leaving
it to be inferred:

```
failure_reason: run_governor: reached the 540 sim-minute ceiling
```

**That is the right behaviour and it is worth saying so.** A demo run that stops
without a recorded reason is indistinguishable from one that died; this one names
the governor and the ceiling. The scenario's declared window was 24 sim-hours
(21:43 → 21:43); the governor is what ends it early, by design, not a fault.

The run's own numbers: `time_scale` 60, `tick_interval_seconds` 30 →
`tick_minutes_actual` **30.0**, so 25 ticks advanced the sim clock 750 minutes,
21:43 → 10:13.

**AND ONE WRINKLE, recorded because it is this repo's recurring defect class in
miniature.** The message says the run "reached the 540 sim-minute ceiling", and
the clock shows **750** sim-minutes elapsed — 210 minutes, i.e. 7 ticks, past the
number the message names. The metronome advances in batches (`CALL
ottoq_demo_metronome(50)`) and checks ceilings between batches, so overshooting a
ceiling by part of a batch is expected mechanically. What is not ideal is that
the sentence reads as "it stopped AT 540" to anyone who does not go and measure
the clock.

Not a defect in the orchestration and not fixed here: it is a message that
describes a slightly different quantity from the one that governed, which is the
same shape as `0320`'s ETA label and `0231`'s ledger comment. Logged for the
backlog, not silently absorbed.

**Nothing about this weakens the end-to-end result.** The chain ran, the run armed
itself, the forecast covered every active dispatch, the proposer's influence grew
tick over tick, and the run ended for a declared, recorded reason.
