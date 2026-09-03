# Round 11 canons — 2026-09-03

Depot `11111111-1111-1111-1111-111111111111` (flagship), pinned sim start
`2026-09-01 02:00:00+00`, proposer quiesced by 0152. Engine as of **0177**.

**Twelve pairs, six columns, two each. Not one hash moved.**

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg | rec |
|---|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `04177a2a` | `5328154a` | `0bf42b3c` | `8dcf8918` | 0 |
| busy_day | 314159 | 12 | `773fd6dc` | `ad492891` | `4274369c` | `2b271f2f` | 0 |
| normal_day | 171717 | 12 | `78ece09b` | `c36a99c1` | `2838c66c` | `5512b237` | 0 |
| busy_day | 171717 | 24 | `ec5c38aa` | `8221f656` | `096b099e` | `da9c269c` | 0 |
| busy_day | 424242 | 12 | `16aabc27` | `f1224a98` | `5a227276` | `0cac7e0b` | 3 |
| busy_day | 424242 | 24 | `ac1dc757` | `3adcc2dc` | `37ed2670` | `c5ef0ab3` | 14 |

Every column: `pairs = 2`, all four hashes single-valued across both pairs
(`count(distinct) = 1` each), `outcome = passed` on every run. Identical to
round 10 in every cell.

## 0177's prediction, and why it was the strict kind

Published in `db/checks/0087` **before** the round fired:

> ALL SIX COLUMNS MUST REPRODUCE ROUND 10 EXACTLY — all four hashes, every
> column. There is NO "expected to move" column this round. ANY moved hash is
> 0177's and is a defect to REVERT.

It held on all 24 hash comparisons. The reasoning it rested on is worth keeping:
`ottoq_determinism_pair` primes every arm explicitly at 0.70 immediately after
starting it, so the cold-start branch 0177 rewrote is not reachable from the
certification path. A round with no permitted movement is a real test precisely
because there is nowhere for a regression to hide as "expected".

## What this round established that round 10 could not

**Four columns are now stable across TWO round boundaries** (8 → 10 → 11):
`busy_day 171717/12t`, `busy_day 314159/12t`, `normal_day 171717/12t`,
`busy_day 171717/24t`. Two boundaries is the bar roadmap item A actually asks
for; before today no column had met it.

**The two 0179 canons reproduced.** `round10.md` recorded them as "a first
observation, not a stable one". They now have a second independent
confirmation, at 3 and 14 deferrals respectively, so that caveat is discharged
— by evidence, not by restating it.

## Task #47 — counted exactly, and NOT closed

`normal_day 171717/12t` carries a proposed bar of **eight** consecutive pairs
reproducing its canon. The precise count:

- **6 consecutive pairs** on canon `c36a99c1`, zero non-passing
- streak began **2026-09-02 4:28 PM CT**
- 40 pairs on this column all-time, across canons that moved legitimately with
  engine migrations

Six is not eight. Two further pairs were fired at 16:21 and 16:41 UTC to reach
the bar honestly rather than round up to it. The task stays open until they
land and reproduce.

## A process finding: never compute a cron slot from a remembered time

Five of this round's twelve pairs did not fire at all on the first attempt.
Their slots were computed from an **assumed** clock (~09:55 UTC) when the real
time was ~11:40 UTC — PR #155 merged nearly two hours after the last clock
read, and the clock was never re-read before deriving the schedule. The slots
were already in the past when created, so pg_cron silently queued them for the
following day.

The failure mode is quiet in a specific way: `cron.job_run_details` has **no
row at all** for such a job, and `status = null` is indistinguishable at a
glance from "scheduled, not yet fired". Nothing errors. Nothing is stranded.
The round simply comes up short and the reason is invisible unless the missing
columns are counted.

The re-schedule derives every slot from `now()` inside the statement and
asserts `fire_utc > now()` **per row**, so the check is structural rather than
remembered:

```sql
WITH now_utc AS (SELECT date_trunc('minute', now() AT TIME ZONE 'UTC') AS t), ...
SELECT s.job, s.fire_utc > (SELECT t FROM now_utc) AS is_in_the_future,
       cron.schedule(...)
```

Recorded as a standing rule, not an anecdote: **a cron slot is derived from the
database clock at the moment of scheduling, never from a time carried in
memory.** CLAUDE.md rule 7 already says `pg_cron` evaluates in UTC; this is its
companion — the UTC value must also be *current*.

## What is still not covered

- **Two pairs per column.** Enough for inter-pair reproducibility, not a
  statistical claim.
- **One depot.** 0177 unblocks the two-lane cadence but no second-depot pair
  has been run yet.
- Round 12 is the first that could give these six columns a **third** boundary.
