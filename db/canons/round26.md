# Round 26 — 2026-09-08 (scheduled 11:35–13:22 UTC / 6:35–8:22 AM CT)

The recertification for five migrations applied 11:15–11:20 UTC: **0219** (h_sdr
enforced), **0213** (KPI-4 vocabulary), **0220** (schedule_task SDR emitter),
**0221** (the run-scope predicate), **0222** (the boot fingerprint).

Flagship depot `11111111-…`, pinned sim start `2026-09-01 02:00:00+00`, proposer
quiesced, arm budget 900 s.

## Slots, derived rather than chosen

First round scheduled by `scripts/schedule-round.sql`, which reads the slowest
completed run of each tick count from the last five days and multiplies by 1.35.
That gave **19-minute slots for 12-tick and 31 for 24-tick**, against the 16 and
26 hand-picked for round 25 — which collided mid-round and had to be moved by
hand.

| | column | fires (UTC) | fires (CT) |
|---|---|---|---|
| a | `busy_day` / 314159 / 12t | 11:35 | 6:35 AM |
| b | `busy_day` / 171717 / 12t | 11:54 | 6:54 AM |
| c | `normal_day` / 171717 / 12t | 12:13 | 7:13 AM |
| d | `busy_day` / 424242 / 12t | 12:32 | 7:32 AM |
| e | `busy_day` / 171717 / **24t** | 12:51 | 7:51 AM |
| f | `busy_day` / 424242 / **24t** | 13:22 | 8:22 AM |

The spacing is derived from **pre-0222** durations, so it is deliberately
generous: if 0222 does what it should, every pair finishes well inside its slot.
Erring that way costs wall clock and cannot corrupt a round.

## The two predictions, stated before the round runs

**1. No verdict atom moves, on any column.** Four of the five migrations touch
paths the certification exercises, and every one of them argues it is
output-identical rather than merely harmless:

- **0222** rewrites `ottoq_boot_state_fingerprint`, which computes the
  **enforced** `endst` atom. Its A2 recomputed the fingerprint on two real
  `(depot, run)` pairs — including one where *every* row is foreign, so the
  `fgn` branch ran at its widest — and got byte-identical answers.
- **0221** rewrites `ottoq_validate_assignment`, a decide-path function. The row
  set differs only on a booking carrying the all-zero sentinel uuid, and P1
  asserted there are none.
- **0219** enforces an atom that already agrees on all six columns.
- **0213** and **0220** touch a KPI view and a dormant trigger the pair cannot
  reach (0220's P2 asserted the twin's schedule materializer still has no
  callers).

If an atom moves, the argument is wrong somewhere and **the migration is what
gets reverted, not the canon.**

**2. The pair gets materially faster.** `ottoq_boot_state_fingerprint` measured
warm on flagship after 0222: **260.6 ms and 218.2 ms**, against ~64,000 ms
before — 250–290×. It is called four times a pair, so 255.3 s of a 700.7 s pair
should become about one second. The 12-tick columns should land near **450 s**
rather than 700–830.

That is a prediction, not a claim. Two earlier performance fixes on this task
measured beautifully in isolation and bought zero seconds on the pair; this one
is written down in advance so it can be wrong in public.

## Results

*(filled in as the columns land)*
