# Round 30 — recertifying 0229, and the first fix measured by call count

**Written 2026-09-08 20:46 UTC. Scheduled at 20:44, before any column fires.**
Jobs 497–501: a 20:50, b 21:00, c 21:10, d 21:20, **g 21:32 instrumented**.

## What changed

`0229`, applied 20:41:37 UTC. `public.ottoq_approach_band`'s first CTE went from
`AS MATERIALIZED` to `AS NOT MATERIALIZED` — one word — so the consumer's
`sim_run_id` predicate can finally reach the scan.

`db/checks/0144` measured what it was costing: **`ottoq_policy_get`, 4,894,867
calls and 199,648 ms of self time in one 12-tick pair — 60.5% of the pair.**

## THE MEASUREMENT THAT MATTERS IS THE CALL COUNT, NOT THE CLOCK

Round 28's lesson, in its own words: six pairs produced byte-identical hashes
while wall clock swung **±40%**. Judging a fix by pair duration on that
instrument is how `prediction 2` got falsified and how column d's −146 s got
quarantined. So round 30 leads with a counter, and `r30_g` exists for that reason.

**`db/evidence/r28_g_fn_after.md` is `r30_g`'s baseline unchanged** — verified at
20:44: 304 rows, 23,254,422 total calls, `ottoq_policy_get` 20,529,255, load
meter 2,134, all identical, `track_functions` still `'none'` globally. The same
file is "after" for one round and "before" for the next, which is only sound
because nothing between them can move a counter.

## PREDICTION 1 — no verdict atom moves, on any column

`0229` was classified `forces_recert FALSE` on the strength of an `EXCEPT` in
both directions: 120 rows, 12 semantic columns, zero differences either way.

**If any canon moves, that proof was insufficient and 0229 must be reverted.**
Not investigated, not explained away — reverted, because a view on the decide
path that changes a verdict is not a performance fix. The floor did not move at
apply time, so every column keeps its streak and a movement would show
immediately as a reset.

## PREDICTION 2 — `ottoq_policy_get` falls by at least 98%

Derived, not guessed:

| | |
|---|---|
| view evaluations per 12-tick pair (measured, `0144`) | ~1,963 |
| calls per evaluation, before | 2,493 (831 runs × 3) |
| calls per evaluation, after | **3** |
| view's contribution, after | **~5,889** |
| every plpgsql caller at its theoretical maximum (`0144` Q2) | ≤ 42,461 |
| **predicted total** | **under 100,000** |
| measured before | **4,894,867** |

> **`r30_g`'s `ottoq_policy_get` delta lands under 100,000, against 4,894,867.**

Falsified by anything above 100,000. **A number between 100,000 and 4,894,867
would be the interesting failure** — it would mean the predicate reaches the CTE
for the plan A3 asserted but not for every path the tick actually takes, and the
next question would be which caller still forces the scan.

## PREDICTION 3 — wall clock, stated last and stated weakly on purpose

Round 28's four 12-tick columns: **356, 361, 342, 218; mean 319.25.**

199,648 ms of self time in a single-threaded pair *is* wall clock, so it has to
come out somewhere. But the same instrument moved ±40% on identical work last
round, and `r30_g` is instrumented (`r27_g` carried +52% overhead).

> **The four-column 12-tick mean lands below 250 s.** No tighter band is offered,
> because this instrument has not earned one.

**No saving will be quoted as a headline figure from wall clock.** If prediction 2
holds and prediction 3 does not, the honest report is "the calls are gone and the
clock did not notice", and that is a finding about the instrument, not the fix.

## What is NOT being claimed

That `0229` explains round 28's 24t:12t cost ratio moving from 1.53 to 2.34–2.59.
`0144` declined to explain it and applying the fix does not change that. If the
ratio is still above 2.0 after this, the superlinearity has a second source.

Results below a `## Results` heading. Nothing above it is to be edited.

---

# Results

## The four 12-tick columns

| col | scenario / seed | r30 | r28 | Δ | streak | verdict |
|---|---|---|---|---|---|---|
| a | `busy_day` / 314159 | **124** | 356 | −232 | 6 → **7** | pass, no atom moved |
| b | `busy_day` / 171717 | **124** | 361 | −237 | 5 → **6** | pass, no atom moved |
| c | `normal_day` / 171717 | **116** | 342 | −226 | 4 → **5** | pass, no atom moved |
| d | `busy_day` / 424242 | **124** | 218 | −94 | 4 → **5** | pass, no atom moved |
| **mean** | | **122.00** | 319.25 | **−197.25 (−61.8%)** | | |

## PREDICTION 1 — HELD, on all four columns

Every one of the ten canon atoms the matrix returns is byte-identical to round
28 on every column — `fp`, `dec`, `cmd`, `evt`, `bkg`, `nrg`, `rule`, `rcl`,
`sdr`, `endst`. All four green, all histories unbroken, `inconclusive_pairs`
unchanged.

**0229 removed 62% of the pair and changed nothing the certification measures.**
That is the whole claim of the migration, and it is now a measurement rather than
an EXCEPT over 120 rows.

## PREDICTION 3 — MET, and by a wide margin

The band was *"the four-column 12-tick mean lands below 250 s"*, stated
deliberately loosely because the instrument had not earned a tighter one.
**122.00 s.** The arc, all measured on the same six columns:

| round | 12-tick mean | |
|---|---|---|
| 26 | 519.00 | |
| 27 | 364.00 | −29.9% |
| 28 | 319.25 | −12.3% |
| **30** | **122.00** | **−61.8%** |

**519 → 122 s is 4.25x, and the last step is more than the previous two combined.**

## The spread collapsed — and it does NOT mean what it looks like

| round | spread (max − min) |
|---|---|
| 27 | 18 s |
| 28 | **143 s** |
| **30** | **8 s** |

Round 30's 8-second spread across four columns is the tightest ever recorded, and
the temptation is to say the unscoped view was the source of round 28's ±40%
variance and 0229 has now removed it.

**That reading is wrong and the numbers above refute it.** The view was present,
unfixed, for round 27 as well — and round 27's spread was **18 s**. If the view
caused round 28's variance it would have caused round 27's too. It did not.

So **round 28 remains the outlier round, and why it was an outlier remains
unexplained** — exactly as `db/checks/0144` recorded before this fix was applied.
0229 made the pair much faster; it did not explain round 28, and column d's −146 s
stays quarantined. A finding that arrives conveniently packaged with the fix is
the one to check hardest.

## Still open, and unchanged by this round

The **24t:12t cost ratio**. Round 28 measured it at 2.34–2.59 against round 27's
1.53, and round 30 scheduled **no 24-tick column**, so the ratio is not
re-measured here. If the superlinearity is still present at the new speed it has a
second source, and that is the next thing to measure — not to theorise about.
