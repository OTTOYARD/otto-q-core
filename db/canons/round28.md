# Round 28 — the recertification of 0225, 0226, 0227 and 0228

**Written 2026-09-08 15:50 UTC, before the migrations are applied and before a
single column of round 28 has been scheduled.** That is the point: a prediction
committed after the schedule exists is a prediction made with one eye on the
clock.

Round 27's numbers are the baseline (`db/canons/round27.md`):

| | 12-tick mean | 24-tick |
|---|---|---|
| round 26 | 519 s | e 761 s · f 734 s |
| round 27 | **364 s** | e **560 s** · f **551 s** |

## What round 28 recertifies

Four migrations, applied in one window in this order — `0226 → 0225 → 0227 →
0228` — for reasons set out in `db/canons/round27-apply-window.md`.

| migration | what it changes | duration prediction | canon prediction |
|---|---|---|---|
| **0226** | normalises the recert-floor join on both sides; adds `ottoq_cert_lineage_orphans()` | **none.** It is a read the pair never calls. | none |
| **0225** | `ottoq_cert_matrix` compares fourteen atoms instead of nine | **none.** A `STABLE` pure read called by nothing in the decide path. | none — but it changes what *counts as* a canon movement, which is the whole point |
| **0227** | adds `ocpp_sessions_runscope_load_idx` | **about −16 s on a 12-tick pair** (see below) | none — index only, no SQL changes, no result can differ |
| **0228** | `data_source` derived from `depots.feed_mode` instead of from whether a run id is set | **none, or a shade slower.** One `depots` primary-key lookup per emitted event. | none — `h_evt` reads neither `data_source` nor `depot_id`, asserted by 0228's own P1 against the live verdict function |

## PREDICTION 1 — no verdict atom moves, on any column

The same prediction that has now held for three consecutive rounds across
eleven migrations. Round 28's canons must be byte-identical to round 27's:

- `busy_day/314159/12t` — `fp 803698f3` (and the rest of round 27 column a)
- `busy_day/171717/24t` — `fp 92b02f8b · h_cmd 050c4606 · h_dec 0360adc9 · h_evt b2230619 · h_bkg 947a2316 · h_nrg 4c5035fe · h_prop 0046879e · h_defr d41d8cd9 · h_cal 11a24626 · h_rule 9564b998 · h_rcl fa8ab72c · h_sdr 957abcfb · endst 967124f1`
- `busy_day/424242/24t` — `fp e418e4f0 · h_cmd 8f232001 · h_dec 35148055 · h_evt 8dc37f82 · h_bkg ea8a12e2 · h_nrg c79957a5 · h_prop aabef458 · h_defr d41d8cd9 · h_cal 11a24626 · h_rule 726f6769 · h_rcl 928262d2 · h_sdr f2587dbc · endst b2c2dc8e`

**0228 is the one that could falsify it**, and it is the only one that touches a
path the engine runs. If `h_evt` moves, 0228's P1 was wrong about the verdict
function and that is a finding, not a nuisance.

## PREDICTION 2 — 0227 removes about 16 seconds from a 12-tick pair

Stated as a number, in advance, because rounds 26 and 27 have now both shown
that the per-call arithmetic is wrong and the direction of the error is not
predictable (G27).

0227's claim, from `db/checks/0130`: the load meter's scan costs **17.5 ms and
2,751 buffers per call**, and there are **~1,024 calls in a 12-tick pair** — a
figure that is *derived* (8,966,506 evaluations ÷ 8,756 per call), not counted.
17.5 ms × 1,024 = **17.9 s**, and the index cannot remove all of it, so:

> **0227 removes 10–20 s from the 12-tick mean. Round 28's 12-tick mean lands
> at 344–354 s, against round 27's 364 s.**

**The band is deliberately generous relative to the point estimate and it is
still probably wrong**, because that is what G27 says about this exact kind of
arithmetic — 0222 beat its prediction by 2.2×, 0223 missed its by 1.6× the other
way, and column f missed a band by one second. A 3–5% effect measured against
run-to-run spread of ±10 s (round 27's 12-tick columns were 358, 376, 358, 364)
may simply not be resolvable. **If round 28's 12-tick mean lands anywhere in
350–370 s, the honest report is "no measurable change", not a hit.**

## PREDICTION 3 — six flagship columns go green

Zero are green today (G28). After 0226 lowers the floor and 0225 widens the
comparison, the fourteen-atom streaks computed in `db/checks/0140` Q5 say:
`171717/24t` at 4, and `424242/24t`, `171717/12t`, `314159/12t`, `424242/12t`,
`normal_day/171717/12t` at 3 each — all six above `green`'s bar of 2.

This one is not really a prediction about round 28; it is verified in the apply
window itself. It is listed because if it does *not* happen, round 28 should not
be scheduled at all until it is understood.

## What would falsify each, as an action

| prediction | falsified by |
|---|---|
| 1 — no atom moves | any canon differing from round 27's, on any column. `h_evt` moving points at 0228; anything else points at a migration that was supposed to be inert |
| 2 — 0227 saves 10–20 s | a 12-tick mean outside 344–354 s. **And note that 350–370 s is the "not resolvable" zone, which overlaps the band** — that overlap is stated here rather than discovered afterwards |
| 3 — six columns green | fewer than six green after the window (G28 incomplete), or **more** than six (the comparison is looser than intended, which is the worse outcome) |

## Round 28 needs an instrumented **12-tick** column, and this is why

`r27_g` is instrumented at **24 ticks**. Its baseline came from `r25_g`, which
ran with `track_functions = 'pl'` — a setting that **does not count SQL-language
functions**, which is precisely what blinded `db/checks/0129`.

Consequence, recorded in `round27.md` before g finished: for plpgsql functions
the r27_g diff is a genuine 24-against-12 comparison, but for the two SQL
functions that matter — `ottoq_sim_compute_charger_load_kw` and
`ottoq_depot_running_run` — the baseline is a tracking artefact (2 calls where
`0130` derives ~1,024), so g yields their **absolute 24-tick counts** and no
ratio at all.

**So `r28_g` must be a 12-tick column with `track_functions='all'`**, giving the
first honest 12-tick count of the load meter. Only then does "the load meter is
called twice as often at 24 ticks as at 12" — the assumption underneath 0223's
entire predicted 2.0× scaling, and still unmeasured after two rounds of arguing
about it — become a measurement instead of an inference.

Concretely: schedule round 28's g as `busy_day / 171717 / 12` with the same
`SET track_functions TO 'all'` prefix r27_g uses, and capture a
`pg_stat_user_functions` snapshot immediately before it fires. **Capture the
FULL table this time, not fourteen hand-picked rows** — r27_g's baseline records
only the rows I thought would matter, which is why no delta is computable for
any function outside that list.

## Schedule — committed 2026-09-08 16:26 UTC, after the apply window

| column | scenario / seed / ticks | fires (UTC) | fires (CT) |
|---|---|---|---|
| a | `busy_day` / 314159 / 12 | 16:35 | 11:35 AM |
| b | `busy_day` / 171717 / 12 | 16:49 | 11:49 AM |
| c | `normal_day` / 171717 / 12 | 17:03 | 12:03 PM |
| d | `busy_day` / 424242 / 12 | 17:17 | 12:17 PM |
| e | `busy_day` / 171717 / **24** | 17:31 | 12:31 PM |
| f | `busy_day` / 424242 / **24** | 18:01 | 1:01 PM |
| **g** | `busy_day` / 171717 / **12**, `track_functions='all'` | **18:25** | **1:25 PM** |

**The 24-tick slot is 30 minutes for a pair that now runs ~555 s, and that is a
known defect left in deliberately.** `schedule-round.sql`'s lookback takes the
max of the last **K=6 runs** of each tick count — but a round holds four 12-tick
columns and only **two** 24-tick ones, so K=6 spans 1.5 rounds at 12 ticks and
**three** at 24. Round 28's 24-tick slot is therefore sized from a **1,293 s
round-25 pair**. The file's header claims the lookback adapts "in ONE round"; at
24 ticks it does not.

It was not tightened by hand. The asymmetry errs **long**, and that file's whole
argument is that long costs wall clock while short costs two contaminated pairs
— which is exactly what hand-tightening did in round 25. The fix is to make K
count rounds, and it needs its own change rather than a constant edited at the
end of an apply window. Recorded in the script.

One thing that *was* fixed: the lookback now excludes commands containing
`track_functions`, so an instrumented column can never size a future slot.
r27_g ran **851 s** against column e's 560 s on the same scenario, seed and
horizon — a +52% overhead that is mostly 13.2M counter updates — and without the
exclusion that would have been baked into every round from here on.

### `r28_g`'s baseline is captured, and this time it is the whole table

`db/baselines/r28_g_fn_baseline.md` — **all 304 rows**, captured 16:23:39 UTC.
Valid from capture until g fires because `track_functions` is `'none'` globally
and only g sets it, the same property verified row-by-row for r27_g across 91
minutes and a container restart.

And it already sharpens G21b before g runs: **`ottoq_policy_get` is 44x the next
function** (15,634,388 lifetime against `ottoq_sim_seeded_random`'s 356,072) and
roughly an order of magnitude more than every other tracked function combined.
That is the shape of a function called from SQL the profiler cannot attribute,
not from plpgsql bodies. Two ratios are written down in that file **as things to
test, not as findings** — 0139 spent its closing paragraph refusing to guess the
caller and this does not undo that.

**Nothing in this file is to be edited once the first column fires.** Results go
below a `## Results` heading, as in every previous round canon.
