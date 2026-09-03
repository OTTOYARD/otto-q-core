# Round 9 canons — 2026-09-02 / 03

Depot `11111111-1111-1111-1111-111111111111` (flagship), pinned sim start
`2026-09-01 02:00:00+00`, proposer quiesced by 0152.

The round opened by **0169** (`deferred_tick_budget` recorder, `forces_recert`),
with **0175** (depot/scenario same-world guard) applied before the pairs.

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg |
|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `04177a2a5d686032aa1c54fcac43f958` | `5328154a5f72e9e1bb6b10d177def459` | `0bf42b3cc1b2db78de9e91274d28b3df` | `8dcf8918702a18b9f20022b80dd24513` |

## Every one of these reproduces round 8 exactly

This is the first round in which the round-8 table was diffable, which was the
entire point of committing it. On this column, **all four hashes are byte-identical
to round 8**, across two independently fired pairs:

| pass | fired (CT) | runs | outcome | h_cmd | h_dec | h_bkg | h_nrg |
|---|---|---|---|---|---|---|---|
| 1 | 10:21 PM | `3085f1a3`, `9c96d5df` | passed, equal | held | held | held | held |
| 2 | 10:36 PM | `50edcbac`, `6c78b78e` | passed, equal | held | held | held | held |

`pairs_seen = 2`, `consecutive_passes = 2` → **green**. Pass 2 reproduced pass 1
*and* round 8 on every hash; no canon moved.

## 0169's published prediction, and which branch it took

Stated in `db/checks/0084` §8 **before** the pairs landed:

> `h_cmd`, `h_bkg`, `h_nrg` MUST NOT move. `h_dec` moves **if and only if** the
> recorder fired. If deferred rows are 0, all four canons must reproduce round 8
> exactly — and that result means the flagship never exceeds 20 qualifying
> candidates in a tick, i.e. `decide_seat_batch` has never bound anywhere.

The second branch is what happened. `recorder_rows = 0` on all four runs.

**So, said plainly: `decide_seat_batch` has never bound anywhere.** At 116 assets
the flagship's seating loop never has more than 20 qualifying candidates in a
tick. Two consequences, both worth stating:

1. **0169 is certified a no-op on the engine.** Four canons unmoved across two
   pairs is as strong as this harness gets.
2. **0169's new branch has still never executed, anywhere.** It is instrumentation
   for a condition that has not yet occurred. That is not a defect, but it is not
   a tested code path either, and it must not be described as one. Proving it can
   fire needs a contention fixture (more assets than points); the 4-asset grid
   never has two candidates in a tick, and `decide_seat_batch = 1` there changed
   nothing — self-consistently, since the override *was* resolving (verified
   directly: run → 1, global → 20, then removed).

## A timing alarm that was mine, and was wrong

Pass 1's first arm ran 480 s against round 8's measured 296–400 s band for this
column, and I flagged it as a possible cost of 0169's removal of `LIMIT 20`.

It is not. Both pairs show the same shape — **480 s / 200 s** and **448 s / 179 s** —
a ~2.5× spread between two arms doing *identical* work inside *one* transaction.
That is load and warm-up. The second arm of each pair is **faster** than the
round-8 band, and the canons are byte-identical, so nothing behavioural changed.
Recorded because the alarm was published before it was checked.

## What this column does not cover

One column of six. `busy_day/171717/24t`, `busy_day/314159/12t`,
`busy_day/424242/12t`, `busy_day/424242/24t` and `normal_day/171717/12t` were
**not** re-run against 0169. They carry round-8 canons and are not yet diffed
against the current engine. Round 9 is green on one column, not six — stated so
the table is not read as more than it is.

## The other five columns — fired overnight, 2026-09-03

Scheduled 10:57 PM CT to close the gap this file names above. Two passes per
column, flagship, same pinned sim start, `arm_budget 1800`:

| slot (UTC) | slot (CT) | column |
|---|---|---|
| 04:00 / 04:20 | 11:00 / 11:20 PM | busy_day 314159 12t |
| 04:40 / 05:00 | 11:40 PM / 12:00 AM | busy_day 424242 12t |
| 05:20 / 05:40 | 12:20 / 12:40 AM | normal_day 171717 12t |
| 06:00 / 06:25 | 1:00 / 1:25 AM | busy_day 171717 24t |
| 06:50 / 07:15 | 1:50 / 2:15 AM | busy_day 424242 24t |

Spaced 20 min (12t) and 25 min (24t) and **never overlapping**, because
`twin.ottoq_sim_start_run`'s "one world, one mover" guard explicitly EXCLUDES
`run_by = 'cert_harness'`: two cert pairs fired together would both tick the
same shared flagship fleet and contaminate each other. Tonight's 12-tick pairs
ran ~680 s, so the slots carry roughly 2x headroom.

Each job **unschedules itself** as the last statement of its own command, so a
session that dies overnight cannot leave ten daily-recurring pairs firing. A job
whose pair FAILS rolls back its own unschedule and stays — deliberate, so a
failure is visible rather than swept up.

`normal_day 171717 12t` is task #47's column: two corrected passes against a
proposed bar of eight. These two passes do not close it on their own and it is
not being closed unilaterally.

Results land in a successor file; this section is the plan, written before the
evidence, so it can be wrong.
