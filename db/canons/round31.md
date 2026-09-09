# Round 31 — 2026-09-08/09 (in progress; first pair fired 10:42 PM CT / 03:42 UTC)

Flagship depot `11111111-…`, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced,
arm budget 900 s. Six columns, slots derived by `scripts/schedule-round.sql` from the last
six runs of each tick count (12-tick slowest 360 s → the 14-minute floor; 24-tick 868 s →
20 min).

**Why this round exists:** migration **0238** (G41, `db/checks/0156`) is `forces_recert TRUE`.
It made the external-proposal selector's order total on content, because `created_at` defaults
to `now()` — the *transaction* timestamp — and a certification pair runs both arms and every
tick in one transaction, so `ORDER BY created_at DESC` sorted nothing and `LIMIT 1` returned
index-scan order. The recert floor moved `2026-09-07 21:36:53` → **`2026-09-09 03:15:07`**, and
every canon streak reset with it.

## The prediction, written at 03:5x UTC with two of six columns in

0238's own header said this:

> *Nothing DEFINED changes — every outcome this alters was undefined before it. But the decide
> path's observable behaviour can move, and a canon that was standing on index-scan order should
> be made to say so out loud.*

Two columns are in and **both reproduce the pre-0238 canon byte for byte**:

| column | atom | before 0238 | round 31 | |
|---|---|---|---|---|
| busy_day / 314159 / 12 | `fp` | `803698f3…` | `803698f3…` | same |
| | `h_dec` | `9abdb4af…` | `9abdb4af…` | same |
| | `h_prop` | `a79c1095…` | `a79c1095…` | same |
| busy_day / 171717 / 12 | `fp` | `92b02f8b…` | `92b02f8b…` | same |
| | `h_dec` | `cf2f44e2…` | `cf2f44e2…` | same |
| | `h_prop` | `0046879e…` | `0046879e…` | same |

**PREDICTION: the remaining four columns (normal_day/171717/12, busy_day/424242/12,
busy_day/171717/24, busy_day/424242/24) will also reproduce their pre-0238 canon exactly.**

Recorded before the evidence so it can be wrong. The reasoning: on these worlds the tie either
never arose, or the index handed back the same row on both sides of the change. If a column DOES
move, that is the more interesting outcome — it means the selector's undefined order was
genuinely deciding something, and the pre-0238 canon for that column was an artefact of heap
layout rather than of the engine.

Either way the recert was correct to force. **The guarantee changed even where the values did
not, and there is no way to know which without running it.** A fix that costs no canon churn is
the good case, not the wasted one.

## Wall clock, and a note on the slots

| pair | slot sized for | actual |
|---|---|---|
| r31_a busy/314159/12 | 14 min | **132 s** |
| r31_b busy/171717/12 | 14 min | **124 s** |

The scheduler sized 12-tick slots from a 360 s worst case and the pairs are running at ~130 s.
That is G29 (`db/checks/0144`, migration 0229 — `policy_get` 4.89M → 35,498 calls) landing in
the arc, and it means round 31 spends roughly 70 minutes of wall clock waiting in slots sized
for an engine that no longer exists. `scripts/schedule-round.sql`'s own header predicts exactly
this failure mode for the 24-tick columns and argues, correctly, that a slot too SHORT puts two
pairs on one depot and contaminates both while a slot too LONG costs only time. Left alone.

## Verdicts — SIX OF SIX PASSED, and the prediction is CONFIRMED

Round complete 2026-09-09 05:0x UTC. `pg_stat_activity` reports zero pairs in flight and no
`r31_` job incomplete, which is the authority — `cron.job_run_details` reports a two-statement
job as `succeeded` in ~1 s while it is still running.

| pair | column | outcome | wall clock | `fp` | `h_dec` | `h_prop` |
|---|---|---|---|---|---|---|
| r31_a | busy_day / 314159 / 12 | **passed** | 132 s | `803698f3` | `9abdb4af` | `a79c1095` |
| r31_b | busy_day / 171717 / 12 | **passed** | 124 s | `92b02f8b` | `cf2f44e2` | `0046879e` |
| r31_c | normal_day / 171717 / 12 | **passed** | 126 s | `92b02f8b` | `37624cdd` | `779e5a74` |
| r31_d | busy_day / 424242 / 12 | **passed** | 127 s | `e418e4f0` | `47757095` | `029cad7d` |
| r31_e | busy_day / 171717 / 24 | **passed** | 228 s | `92b02f8b` | `0360adc9` | `0046879e` |
| r31_f | busy_day / 424242 / 24 | **passed** | 223 s | `e418e4f0` | `35148055` | `aabef458` |

### The prediction, judged

Compared per atom, latest pre-0238 run against latest post-0238 run, for every column:

**Zero atoms moved. Six columns × fourteen atoms — `fp`, `h_cmd`, `h_dec`, `h_evt`, `h_bkg`,
`h_nrg`, `h_prop`, `h_defr`, `h_cal`, `h_rule`, `h_rcl`, `h_sdr`, `ticks`, `endst` — all
identical to the pre-0238 canon.**

So the prediction written above, before the last four columns landed, holds exactly. **0238 cost
no canon churn.** Making the external-proposal selector total on content changed nothing any
column had previously observed — on these six worlds the undefined order either never arose or
the index happened to return the same row on both sides of the change.

That is the good outcome and it is worth being precise about what it does and does not say. It
does NOT say the tie was harmless: `db/checks/0156` proved the selector flipping on demand, and
inside a certification `created_at` is frozen so the order was genuinely undecided. It says these
six worlds did not happen to exercise it. The recert was still correct to force — **the guarantee
changed even where the values did not, and there is no way to learn which without running it.**

### A methodology note, because the first answer I computed was wrong

The first comparison query aggregated the pre-0238 side with `min()` per atom, grouped by column.
Where a column had more than one distinct pre-0238 canon inside the lookback window (314159/12 has
fourteen run-rows spanning more engine history), `min()` mixed atoms from *different* runs into a
composite "prior canon" that had never existed, and the column duly reported a mismatch.

It reported `busy_day/314159/12` as moved. It had not. The per-atom check against the LATEST
pre-0238 run shows all thirteen identical, and the corrected sweep above shows zero movement
across all six.

Recorded because the failure mode is subtle and will recur: **when comparing against "the canon",
name WHICH run you mean.** An aggregate over a window that spans an engine change is not a canon,
it is a composite of several, and it will manufacture findings that do not exist.
