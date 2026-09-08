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

### a — `busy_day` / 314159 / 12 ticks — **PASS**

Fired 11:35:00 UTC, ended 11:43:57, **537 s**, `equal true`. Every atom
byte-identical to the same column in round 25:

| atom | round 25 | round 26 a | |
|---|---|---|---|
| `fp` | `803698f3` | `803698f3` | = |
| `h_cmd` | `109e340b` | `109e340b` | = |
| `h_dec` | `9abdb4af` | `9abdb4af` | = |
| `h_evt` | `9c631343` | `9c631343` | = |
| `h_bkg` | `174b8835` | `174b8835` | = |
| `h_nrg` | `a9c6b693` | `a9c6b693` | = |
| `h_prop` | `a79c1095` | `a79c1095` | = |
| `h_cal` | `11a24626` | `11a24626` | = |
| `h_rule` | `fc69953b` | `fc69953b` | = |
| `h_rcl` | `0e67b89a` | `0e67b89a` | = |
| `h_sdr` | `a1f79c20` | `a1f79c20` | = |

The `round 25` column is round 25's **g** re-run (10:52 UTC), not its 08:25
pair-1: pair 1 predates 0218 and its `h_sdr` was the contaminated kind
(`0df9a909` vs `65ec044e`). Every other atom is identical in both.

**Prediction 1 holds on this column.** Five migrations — including 0222's
rewrite of the function that computes the *enforced* `endst` atom, and 0221's
rewrite of a decide-path function — moved nothing. This is also the first round
in which `h_sdr` could have failed the pair rather than merely been recorded
(0219 enforced it), and it did not.

**Prediction 2 — the mechanism is right to within 14%, the number I published
was wrong.** I wrote "near 450 s"; it landed at **537 s**. Both halves of that
deserve saying, because they call for opposite next actions.

The baseline, measured rather than remembered — every 12-tick flagship pair in
`cron.job_run_details` over the 30 hours before 0222, all uninstrumented:

```
822  832  720  731  643  819  777  749  758  649        (09-07 evening, rounds 22–24)
797  801  812  686  735  754                            (09-08 morning, round 25 a–d)
```

n = 16 · min **643** · max **832** · mean **755** · spread ±95 s round to round

Plus `r25_g` at **701 s**, the same column as `r26_a`, carrying
`track_functions='pl'` and `pg_stat_statements.track='all'`. That it beat the
same column's uninstrumented 812 s is the first thing to notice: **the noise on
this measurement is around ±90 s**, so no single-pair comparison settles
anything. The robust statement is the order statistic:

| | |
|---|---|
| pre-0222 12-tick, n=16, min | 643 s |
| pre-0222 12-tick, mean | 755 s |
| **r26_a** | **537 s** |
| vs. the mean | −218 s (−29%) |
| vs. the *fastest pair ever recorded* on this workload | −106 s |
| what the fingerprint arithmetic predicted | −255 s |
| what my published landing point said | ~450 s |

So the fix delivered **218 of the 255 seconds** it argued for — 86% of its own
prediction, and 537 s is below all sixteen pre-0222 measurements, which no
amount of ±90 s noise explains away. The 450 s figure was wrong because I
subtracted 255 from ~700 when the measured mean was 755. The mechanism held;
the arithmetic was done against a baseline I had not looked up.

That is worth separating out, because "the fix underdelivered" would mean going
back into `ottoq_boot_state_fingerprint`, and "I subtracted from the wrong
number" means the fingerprint is done and the next 439 s —
`ottoq_sim_decide_and_dispatch` at 388.7 s, per `db/checks/0129` — is where the
remaining time lives.

### b — `busy_day` / 171717 / 12 ticks — **PASS**

Fired 11:54:00 UTC, ended 12:02:53, **533 s**, `equal true`. Compared against
round 25's 08:46 pair on the same column, all eleven atoms:

| atom | round 25 (08:46) | round 26 b | |
|---|---|---|---|
| `fp` | `92b02f8b` | `92b02f8b` | = |
| `h_cmd` | `1ae7ba68` | `1ae7ba68` | = |
| `h_dec` | `cf2f44e2` | `cf2f44e2` | = |
| `h_evt` | `e16ad964` | `e16ad964` | = |
| `h_bkg` | `7146a8e1` | `7146a8e1` | = |
| `h_nrg` | `08f719af` | `08f719af` | = |
| `h_prop` | `0046879e` | `0046879e` | = |
| `h_cal` | `11a24626` | `11a24626` | = |
| `h_rule` | `3e57f511` | `3e57f511` | = |
| `h_rcl` | `0a4ca4d3` | `0a4ca4d3` | = |
| `h_sdr` | `a2a35e03` | `a2a35e03` | = |

Two columns, twenty-two atom comparisons, no movement.

**And the durations are doing something the prediction did not anticipate.**

| | round 25 | round 26 | |
|---|---|---|---|
| a — `busy_day`/314159/12t | 812 s | **537 s** | −275 |
| b — `busy_day`/171717/12t | 686 s | **533 s** | −153 |

The sixteen pre-0222 pairs spread **643–832 s**, a 189 s range. The two
post-0222 pairs are **537 and 533** — four seconds apart. Removing the
fingerprint did not only remove its mean, it removed most of the variance,
which fits the mechanism: a 1.36-million-row scan's cost depends on how much
of those tables the cache is holding, and that changes hour to hour. Nothing
else in the pair scans at that scale.

That is a claim about two data points and is written here so the remaining four
columns can contradict it.

### While the round runs — G21, from the capture that was already on disk

`db/checks/0130`. Ranking r25_g's statements by **calls** instead of seconds —
which `0129` never did — puts one statement first by a factor of four:

```
8,966,506 calls   108.8 s   SELECT sim_run_id FROM ottoq_sim_runs
                              WHERE depot_id = p_depot_id AND status = $2 …
```

It is `public.ottoq_depot_running_run`, called from
`twin.ottoq_sim_compute_charger_load_kw` on the right of its run-scope
comparison — so once per candidate `ocpp_sessions` row, **8,756 times per
call**, for a value that is constant across the call. The whole load meter is
**195.4 s of the 700.7 s pair**, which is ~36% of the 537 s pair we now have.

`0223` is drafted and every precondition and assertion has been dry-run against
the live catalog read-only. It waits for column f. Its prediction is written
the same way 0222's was, and this time against the measured baseline rather
than a remembered one.

### c — `normal_day` / 171717 / 12 ticks — **PASS**

Fired 12:13:00 UTC, **477 s**, `equal true`. All eleven atoms byte-identical to
round 25's 09:02 pair on the same column:

`fp 92b02f8b` · `h_cmd 5921ef70` · `h_dec 37624cdd` · `h_evt ac672423` ·
`h_bkg ed4a986c` · `h_nrg 17c9b12b` · `h_prop 779e5a74` · `h_cal 11a24626` ·
`h_rule 5b1d1dfa` · `h_rcl e4e41e69` · `h_sdr e0dfbbe8`

Three columns, thirty-three atom comparisons, no movement.

| | round 25 | round 26 | |
|---|---|---|---|
| a — `busy_day`/314159/12t | 812 s | **537 s** | −275 |
| b — `busy_day`/171717/12t | 686 s | **533 s** | −153 |
| c — `normal_day`/171717/12t | 735 s | **477 s** | −258 |

477 s is 166 s below the fastest of the sixteen pre-0222 pairs. The three
post-0222 12-tick pairs sit at 477–537 s (60 s apart) against a pre-0222 spread
of 643–832 (189 s apart), which keeps the variance claim from column b alive
for one more column.

A note on `fp`, since c and b share it (`92b02f8b`) across different scenarios:
that is expected, not a collision. `fp` is the world fingerprint taken after the
fleet reset and before the run, so it depends on (depot, seed, sim_start) and
not on the scenario. The scenario shows up in every atom downstream of it — and
`h_cmd`, `h_dec`, `h_evt` and the rest all differ between b and c, which is the
check that says so.

### d — `busy_day` / 424242 / 12 ticks — **PASS**

Fired 12:32:00 UTC, **529 s**, `equal true`. All eleven atoms byte-identical to
round 25's 09:18 pair:

`fp e418e4f0` · `h_cmd 76134009` · `h_dec 47757095` · `h_evt 6453c09b` ·
`h_bkg 8bc2877b` · `h_nrg 9917f7c3` · `h_prop 029cad7d` · `h_cal 11a24626` ·
`h_rule d56e09a3` · `h_rcl f58ee562` · `h_sdr 6fd75365`

## The four 12-tick columns, complete

**Forty-four atom comparisons. Not one moved.** Five migrations — two of them
rewriting functions the certification exercises on every tick, one of them the
function that computes an *enforced* atom — and the canon is untouched. That is
prediction 1, on every column it applies to.

| column | round 25 | round 26 | Δ |
|---|---|---|---|
| a — `busy_day`/314159 | 812 s | **537 s** | −275 |
| b — `busy_day`/171717 | 686 s | **533 s** | −153 |
| c — `normal_day`/171717 | 735 s | **477 s** | −258 |
| d — `busy_day`/424242 | 754 s | **529 s** | −225 |
| **mean** | **747 s** | **519 s** | **−228** |

**Prediction 2, judged.** The fingerprint arithmetic said 255 s. The measured
mean improvement is **228 s — 89% of what the fix argued for**, on four columns
rather than one. The published landing point of ~450 s was wrong; the mechanism
was not.

And the second-order effect, which was not predicted at all and is stated here
because it was noticed rather than forecast: **the spread collapsed.** The same
four columns spanned 686–812 s before (126 s) and span 477–537 s now (60 s).
Across all sixteen pre-0222 12-tick pairs the spread was 643–832 (189 s). The
mechanism fits — a 1.36-million-row scan's cost depends on how much of those
tables the buffer cache happens to hold, and nothing else in the pair scans at
that scale — but it is a post-hoc explanation of four data points and is
labelled as one.

## The two atoms the canon machinery cannot see — checked by hand

`db/checks/0134`, found while this round was running: `ottoq_cert_matrix`
compares nine atoms, the pair enforces fourteen, and **`h_sdr` and `endst` are
not carried by the matrix at all** while `h_rule` and `h_rcl` are carried,
printed and never compared. Until that is fixed the round file is the only place
those four are diffed, so they are diffed here.

`h_rule`, `h_rcl` and `h_sdr` are in each column's table above and all three
reproduce. That leaves `endst` and `h_defr`, recorded now:

| column | round 25 `endst` | round 26 `endst` | | `h_defr` |
|---|---|---|---|---|
| a — `busy_day`/314159/12t | `7b63e109` (10:52) | `7b63e109` | = | `d41d8cd9` |
| b — `busy_day`/171717/12t | `c6424383` (08:46) | `c6424383` | = | `d41d8cd9` |
| c — `normal_day`/171717/12t | `81b46976` (09:02) | `81b46976` | = | `d41d8cd9` |
| d — `busy_day`/424242/12t | `2d6ea57e` (09:18) | `2d6ea57e` | = | `d41d8cd9` |

(`endst` is a JSON object, so what is tabulated is `md5(endst::text)` of arm A;
arm B is identical on every row, which is what the pair already enforced.
`d41d8cd9` is the md5 of the empty string — the 0152 proposer quiesce holding on
every column.)

**This is the strongest single result of the round, and the matrix could not
have produced it.** 0222 rewrote `ottoq_boot_state_fingerprint` — the function
that computes `endst`. The pair only proves the rewritten function agrees with
*itself* across two arms. What this table proves is that it agrees with the
*old* function's answer, on four different worlds, after a change that removed
1,360,899 of the 1,360,915 rows it used to serialize.

Round 25's a-column value is taken from the 10:52 `r25_g` re-run rather than the
08:25 pair, for the same reason its `h_sdr` was: the 08:25 pair predates 0218.
