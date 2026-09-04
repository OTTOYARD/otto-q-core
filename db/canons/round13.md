# Round 13 canons — 2026-09-04 (fired 6:16–8:19 PM CT, 2026-09-03)

Flagship depot, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced.
Engine as of **0184**. Six pairs, one per column.

**All six columns. All 24 hash cells identical to round 12. Not one moved.**

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg | vs r12 |
|---|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `04177a2a` | `5328154a` | `0bf42b3c` | `8dcf8918` | identical |
| busy_day | 314159 | 12 | `773fd6dc` | `ad492891` | `4274369c` | `2b271f2f` | identical |
| normal_day | 171717 | 12 | `78ece09b` | `c36a99c1` | `2838c66c` | `5512b237` | identical |
| busy_day | 424242 | 12 | `16aabc27` | `f1224a98` | `5a227276` | `0cac7e0b` | identical |
| busy_day | 171717 | 24 | `ec5c38aa` | `8221f656` | `096b099e` | `da9c269c` | identical |
| busy_day | 424242 | 24 | `ac1dc757` | `3adcc2dc` | `37ed2670` | `c5ef0ab3` | identical |

Every column: `pairs = 1`, all four hashes single-valued within the pair (arms
agree), `not_passed = 0`. Twelve arm rows, six launches, every job
self-unscheduled — `leftover_jobs = (none)`.

## THE PREDICTION HELD

Published in 0181's header at 22:58 UTC, before round 13 existed:

> ALL SIX COLUMNS MUST REPRODUCE ROUND 12 EXACTLY. A moved hash is 0181's and is
> a defect to REVERT, not a canon to re-baseline.

24 of 24. So `forces_recert = false` on 0181 was correct, and the argument
behind it is now tested rather than merely reasoned: `endst` hashes the dispatch
column 0181 changed, and it did not move, which is only possible if the teardown
write lands after the fingerprint is taken.

**Four round boundaries** (8 → 10 → 11 → 12 → 13) for the four columns unchanged
since round 8; three for the 424242 pair 0179 established.

## THE ROUND DOES EXERCISE 0181'S NEW BRANCH — a correction

At the 00:15 UTC check-in, with only the three 12-tick columns in,
`aborted_rows = 0`, and I recorded that round 13 would prove 0181 caused **no
regression** without exercising its abort branch. **That is superseded by the
final count.** The 24-tick columns produced them:

```
dispatches_r13         1404
aborted_r13               6      <- dispatches still out at the horizon
past_horizon_r13          0      <- the 0181 invariant
```

Six dispatches were still in flight when their runs stopped. Under the old
finalizer each would have been marked `completed` and stamped with the
transaction's wall clock. They are now `aborted` with `actual_return_at` NULL,
and **not one row in the round carries a return time past its run's horizon**.
So the round proves both halves: the new branch fires at flagship scale, and
nothing else moved.

## WHAT THE CORRECTED KPIs SAY, on runs created entirely after 0181–0184

These are not re-reads of old rows. Every run below was created after all four
migrations, at flagship scale.

| | round 13 | what the pre-fix definition would have said |
|---|---|---|
| KPI 2 turns_completed | **3,522** | 10,810 — **3.07x** |
| ...of the excess, closed by teardown | | 1,492 |
| KPI 1 asset-hours | **1,910.9** | 2,894.0 — **1.51x** |
| KPI 1 rows bounded by wall clock | **0** | — |
| KPI 4 touch_events_per_turn | **0.1670** | — |

KPI 1's remaining 983.1 clipped hours are the legitimate horizon-and-prime clamp,
not a wall clock: `horizon_source = run_horizon` on every row. That is 0182
working as designed rather than a residue of 0181.

## HARNESS NOTES

**Two corrections found by reading the ledger instead of the plan.** Both would
have invalidated the round.

`p_arm_budget_s` is **1800**, not the function default of 240. Round 12's exact
invocation was recovered from `cron.job_run_details`. Taking the default would
have bound a 24-tick arm against the budget, moved a hash, and had me revert a
correct fix.

The **8-minute / 14-minute cadence** recorded in task #55 is wrong and is
retired. Measured round-12 durations: 12-tick pairs ran 452–621 s, so 8-minute
spacing would have overlapped them. Round 12 actually used 20-minute slots for
12-tick and 25 for 24-tick. Round 13 used the same, and its own durations
confirm the choice:

```
23:16  608s    23:36  595s    23:56  585s
00:16  473s    00:36 1041s    01:01 1067s
```

The 24-tick pairs ran 1041 s and 1067 s — past round 12's 947–1019 s range and
comfortably inside a 25-minute slot, but well outside a 14-minute one.

**A pg_cron reporting artifact, resolved.** A multi-statement cron command logs
an intermediate `job_run_details` row — `succeeded`, ~1 s, `return_message =
SET` — which is UPDATED to the true duration and `1 row` on real completion.
Read at 23:17 that row said the first pair had succeeded in 1.1 seconds with no
arm rows, which reads exactly like a round that died on arrival. It had not:
one backend was active 156 s in, and `arm_rows = 0` is expected because the
harness commits both arms in a single transaction. Do not read the intermediate
row as a failure.
