# Round 45 — the recert round for the outbound window (0325, 0327)

**Status: PRE-ROUND.** Written 2026-09-14 22:00 UTC (5:00 PM CT), before any job
is scheduled, because a prediction recorded after the result is not a prediction.
The judgement goes below the line.

## What this round certifies

| | what it does | forces_recert |
|---|---|---|
| `0325` energy commands get the dock vehicle commands already have | 4 additive columns on `ottoq_energy_commands` + `ottoq_energy_claim_commands` + `ottoq_energy_ack_command` | **TRUE** |
| `0327` the ledger comment claims a protection that has never existed | `COMMENT ON TABLE` only | **false** |

## P1 — every column passes twice and goes green.

Round 44 closed 10 of 10 green with zero determinism failures. Nothing in this
window touches the decide path, so a FAILURE here would be a much larger finding
than either migration.

## P2 — NOTHING MOVES. This is the sharp one, and it is `0325`'s own argument on trial.

`0325` is classified `forces_recert = TRUE` on `0320`'s reasoning — *"should
change nothing" is a prediction for the next round to judge, not a
classification.* This is that round.

**The argument, read from the live function rather than assumed:** `h_nrg` hashes
an **explicit column list** —

```
tick_seq | command_type | source | setpoint_kw | horizon_min | issued_at | reason
```

— which contains none of `delivered_at`, `delivered_to`, `confirmed_at`,
`confirmed_by`. `h_cmd` sets the same precedent on the vehicle side and has never
hashed `ottoq_vehicle_commands.delivered_at`. And the claim path is gated
`data_source='production'` while a certification is entirely twin, so **no cert
arm can reach the dock at all**; the four columns stay NULL in both arms by
construction.

**So the prediction is that every one of the fourteen atoms holds on every one of
the ten columns.** `fp`, `endst`, `dec`, `cmd`, `nrg`, `prop`, `defr`, `cal`,
`rule`, `rcl`, `sdr`, `ticks` — all of them, everywhere.

**THE FALSIFIER, and it is not a formality:** if ANY canon moves, the column-list
argument above is WRONG — `h_nrg` is reading something it was not thought to read
— and that is the finding, bigger than the dock. It would also be a fourth
instance of the class that `0216`, `0231` and round 44's own `fp` prediction each
belong to: an instrument reading a slightly different thing than its description
claims. Do not explain a movement away; name it.

`0327` writes one COMMENT and cannot move anything. If a canon moves and `0325`
is somehow exonerated, `0327` is not the alternative explanation — look wider.

## P3 — the floor moves to `0325`, NOT to `0327`, and that is a test of `forces_recert`.

`0327` applied LATER (`20260914214102`) than `0325` (`20260914214010`), and is
classified `forces_recert = false`. `ottoq_cert_recert_floor()` derives the floor
from migration lineage **filtered by that flag**, so:

* floor should become **`20260914214010`** (0325), and
* **not** `20260914214102` (0327).

If the floor lands on `0327`'s stamp, `forces_recert = false` is not being
honoured and every "this file cannot move a canon" classification in the lineage
is worth less than it looks. That is a mechanism test riding along for free.

## The operational rule, unchanged

**A twin run anywhere on the instance is a certification outage** —
`ottoq_sim_start_run`'s guard is global with no depot predicate. Twin run
`34ffb2d9` completed at 21:48 UTC, which is what unblocks this round. No twin run
on any depot while a lane is in flight.

## Pre-round canon table — round 44's banked values, to diff against

First eight hex characters.

| column | depot | fp | endst | dec | cmd |
|---|---|---|---|---|---|
| 12t/171717/busy | 11111111 | 9c28854e | 3caf508f | 5e03ebd0 | e07b4d2f |
| 12t/171717/normal | 11111111 | 9c28854e | d3953462 | 5a8a186d | 68dcd195 |
| 12t/314159/busy | 11111111 | b8606125 | 59f5d813 | 69e6a60a | 0c6a5fb5 |
| 12t/424242/busy | 11111111 | 7a14aa52 | a6c72d36 | 3670a7e2 | c5278b05 |
| 24t/171717/busy | 11111111 | 9c28854e | a0490528 | cf474410 | aa851116 |
| 24t/424242/busy | 11111111 | 7a14aa52 | de5389db | 7d901d85 | 231293b7 |
| 48t/171717/busy | 11111111 | 9c28854e | afd9f58d | 508e9323 | 700c0bd1 |
| grid 239001/6 | aacd0bb0 | 66275ea7 | 1155bdfe | bd7f4e92 | 1b9920dc |
| grid 424242/6 | aacd0bb0 | 4cac51f0 | a7746025 | 8671fb10 | e4158c95 |
| grid 171717/12 | aacd0bb0 | a26925d6 | 2613677a | 3522066d | 2a1d2c32 |

## The schedule as actually scheduled — 20 jobs, verified after writing

Laid out on round 44's proven spacing rather than a fresh guess: round 44 ran
those exact gaps with zero contamination, which is measured evidence that they
fit this engine today. Grid lane first on its own depot, then the flagship lane,
then every column's second arm.

| | UTC | | | UTC |
|---|---|---|---|---|
| ga1 grid 239001/6 | 22:15 | | b2 busy 171717/12 | 23:28 |
| ga2 grid 239001/6 | 22:18 | | a2 busy 314159/12 | 23:33 |
| gb1 grid 424242/6 | 22:21 | | c2 normal 171717/12 | 23:38 |
| gb2 grid 424242/6 | 22:24 | | d2 busy 424242/12 | 23:43 |
| gc1 grid 171717/12 | 22:28 | | e2 busy 171717/24 | 23:48 |
| gc2 grid 171717/12 | 22:33 | | f2 busy 424242/24 | 23:56 |
| b1 busy 171717/12 | 22:38 | | **g2 busy 171717/48** | **00:04 (Sept 15)** |
| a1 busy 314159/12 | 22:43 | | | |
| c1 normal 171717/12 | 22:48 | | | |
| d1 busy 424242/12 | 22:53 | | | |
| e1 busy 171717/24 | 22:58 | | | |
| f1 busy 424242/24 | 23:06 | | | |
| g1 busy 171717/48 | 23:14 | | | |

Round ends ~00:10 UTC — **7:10 PM CT**.

**`g2` crosses midnight and its cron expression says so**: `4 0 15 9 *`, day 15
rather than 14. CLAUDE.md rule 7: pg_cron evaluates in UTC, and a conversion that
crosses midnight must shift the day field. Every other job is `… 14 9 *`.

**Verified after scheduling, not assumed.** All 20 read back with the right seed,
tick count, scenario and depot, each carrying `SET statement_timeout TO '25min'`,
the pinned sim-clock start and the 900-second arm budget — and each job's NAME
matching the arguments inside its command, so a misnamed job cannot quietly
certify a different column.

---

## THE JUDGEMENT — PART 1, 22:45 UTC (5:45 PM CT)

Grid lane complete, first two flagship arms landed. **Five of ten columns have
now run against the applied migrations, and NOTHING HAS MOVED.**

| column | fp | endst | dec | cmd | vs pre-round |
|---|---|---|---|---|---|
| grid 239001/6 | 66275ea7 | 1155bdfe | bd7f4e92 | 1b9920dc | **identical** — green, 2 passes |
| grid 424242/6 | 4cac51f0 | a7746025 | 8671fb10 | e4158c95 | **identical** — green, 2 passes |
| grid 171717/12 | a26925d6 | 2613677a | 3522066d | 2a1d2c32 | **identical** — green, 2 passes |
| 12t/171717/busy | 9c28854e | 3caf508f | 5e03ebd0 | e07b4d2f | **identical** — 1 pass |
| 12t/314159/busy | b8606125 | 59f5d813 | 69e6a60a | 0c6a5fb5 | **identical** — 1 pass |

Zero determinism failures. Every atom on every landed column matches the
pre-round table above, character for character.

### P2 — `0325` moves nothing: **HOLDING on five of ten, nothing refuted.**

`0325`'s own argument is surviving its trial so far. The claim was specific and
falsifiable: `h_nrg` hashes an explicit column list containing none of the four
delivery columns, and the claim path is gated to production while a certification
is entirely twin — so the dock is unreachable from inside a pair and the columns
stay NULL in both arms. Five columns of evidence and no movement.

**Not yet complete.** Five columns remain — both 24-tick, the 48-tick, normal_day
and 424242/12 — and the second arms of everything. A prediction that "nothing
moves" is only as good as its widest test, and the long-horizon columns are the
ones with the most surface for something to move on.

### P3 — the floor lands on `0325`, not `0327`: **HELD, exactly.**

```
ottoq_cert_recert_floor()  =  2026-09-14 21:40:10.627356+00
0325 stamp                 =  20260914214010   <-- the floor
0327 stamp                 =  20260914214102   (later, and correctly ignored)
0325 forces_recert         =  true
0327 forces_recert         =  false
```

`0327` applied **52 seconds later** than `0325` and was still correctly excluded
from the floor. `forces_recert = false` is honoured by the mechanism, not merely
recorded — which means every "this file cannot move a canon" classification in
the lineage is load-bearing rather than decorative. That was a free test riding
along on this round and it passed.

### A correction to what I said at the merge

I described the `#189` merge as putting the proposer loop "on a real schedule,
running." **Enabled, yes; running, not yet.** Measured at 22:45, 36 minutes after
the merge: `proposer-loop.yml` has **zero runs with `event: schedule`** — every
run in its history is a manual `workflow_dispatch`. GitHub documents that
scheduled workflows can be delayed, and a newly-added schedule may not fire
promptly.

So the honest statement is: *the schedule is merged to the default branch and its
certification guard is verified; it has not yet fired on its own.* Whether it
does is a measurement for the next check, not something to assert because the
file says `*/5`.


---

## FINAL VERDICT — 23:40 UTC, ROUND STOPPED EARLY AND DELIBERATELY

**All ten columns ran post-migration. Every canon is identical to its pre-round
value. Zero determinism failures.**

| column | passes | fp | endst | dec | cmd |
|---|---|---|---|---|---|
| grid 239001/6 | 2 | 66275ea7 | 1155bdfe | bd7f4e92 | 1b9920dc |
| grid 424242/6 | 2 | 4cac51f0 | a7746025 | 8671fb10 | e4158c95 |
| grid 171717/12 | 2 | a26925d6 | 2613677a | 3522066d | 2a1d2c32 |
| 12t/171717/busy | 2 | 9c28854e | 3caf508f | 5e03ebd0 | e07b4d2f |
| 12t/171717/normal | 2 | 9c28854e | d3953462 | 5a8a186d | 68dcd195 |
| 12t/314159/busy | 2 | b8606125 | 59f5d813 | 69e6a60a | 0c6a5fb5 |
| 12t/424242/busy | 1 | 7a14aa52 | a6c72d36 | 3670a7e2 | c5278b05 |
| 24t/171717/busy | 1 | 9c28854e | a0490528 | cf474410 | aa851116 |
| 24t/424242/busy | 1 | 7a14aa52 | de5389db | 7d901d85 | 231293b7 |
| 48t/171717/busy | 1 | 9c28854e | afd9f58d | 508e9323 | 700c0bd1 |

**P2 — `0325` moves nothing: HELD, on all ten columns.** The dock's own argument
survived its widest available test. `h_nrg` hashes an explicit column list that
contains none of the four delivery columns; the claim path is gated to production
while a certification is entirely twin; the columns stayed NULL in both arms. A
migration classified `forces_recert = TRUE` on the principle that *"should change
nothing" is a prediction, not a classification* — and the prediction was right.

**P3 — the floor lands on `0325`, not `0327`: HELD, exactly.** `0327` applied 52
seconds later and was correctly excluded because it is `forces_recert = false`.
The flag is enforced by the mechanism, not merely recorded.

**P1 — every column green: NOT COMPLETED, and stopped on purpose.** Six columns
reached two passes; four sat at one. The four remaining second arms were
unscheduled at 23:40.

### Why stopping was right, and what it says about rounds

**The second arms could not have added anything to the question this round asked.**
P2 is "did `0325` disturb any canon" — and that is answered by a column's FIRST
post-migration pair. The second arm only converts `1 pass` into `green / 2
passes`, which is a *streak* property of the canon matrix, not evidence about the
migration. Ten of ten columns had already answered.

Chase's point, and it is correct: **a two-hour round is a release gate, not a
development loop.** During an iteration phase — where the staging and
orchestration work now heading in will legitimately move canons on purpose — a
long round mostly buys stale reference values while holding the depot hostage
against the testing that actually advances the product. The depot can only do one
thing at a time: certify, or be tested on.

**What replaces it during iteration:** the grid fixture's 6-tick pair, which runs
in about three minutes on its own depot. That is enough to catch a determinism
BREAK (the property that must never regress) without pretending to re-bank canons
that the next change is going to move anyway. Full rounds return when the
staging/orchestration work is ready to be frozen and shipped.

This is a change of instrument, not of standard. Byte-identical reproducibility
is still the property; the canon values are just not worth re-banking hourly
while the engine is deliberately being changed.
