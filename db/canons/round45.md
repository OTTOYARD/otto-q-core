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

## THE JUDGEMENT

_(pending — written when the round lands)_
