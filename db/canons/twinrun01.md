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

## THE JUDGEMENT

_(pending — written when the run lands)_
