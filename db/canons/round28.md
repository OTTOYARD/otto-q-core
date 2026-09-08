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

## The stake is larger than four migrations (db/checks/0143)

Task #56 Part A — "the deterministic core is done" — was declared met by
`db/checks/0113` after round 17, item by item, and properly. But it was met
against **six** enforced atoms. Since then 0205, 0217 and 0219 promoted `h_rule`,
`h_rcl` and `h_sdr` to enforced, and 0225 extended the matrix from comparing nine
to comparing **fourteen**. The sentence in task #56 never changed; what it
asserts did.

Every Part A clause holds at the new bar except one: *"every canon stable across
at least two rounds"* has had **one** round at fourteen atoms. **Round 28 is the
second.**

So this round re-establishes Part A at the standard the certification now
actually enforces. That is a consequence of predictions 1 and 3 both holding —
**not a fourth prediction**, because stating it as one would double-count the
same evidence.

Not re-shown here and recorded as a gap: *"inter-pair reproducible"*, which 0113
met on two twin-pair columns at six atoms. Round 28's schedule has no twin pairs,
so it will not be re-shown at fourteen.

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

`db/evidence/r28_g_fn_baseline.md` — **all 304 rows**, captured 16:23:39 UTC.
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

---

# Results

**Recorded as each column lands, not reconstructed afterwards.** Nothing above
this heading has been edited since the first column fired at 16:35 UTC.

## Verified before reading any column

| | expected | measured 16:56:53 UTC | |
|---|---|---|---|
| recert floor | `2026-09-07 21:36:53.363037` | `2026-09-07 21:36:53.363037` | held |
| `ottoq_cert_lineage_orphans()` | 22 | 22 | held |

The floor has not moved through four migrations, which is 0226's whole claim:
0225, 0227 and 0228 all landed as `forces_recert FALSE` after it and none of
them reset a streak.

## Columns as they land

| col | scenario / seed / ticks | fired | secs | r27 | Δ | streak | verdict |
|---|---|---|---|---|---|---|---|
| a | `busy_day` / 314159 / 12 | 16:35:00 | **356** | 358 | −2 | 3 → **4** | pass, no atom moved |
| b | `busy_day` / 171717 / 12 | 16:49:00 | **361** | 376 | −15 | 3 → **4** | pass, no atom moved |
| c | `normal_day` / 171717 / 12 | 17:03:00 | **342** | 358 | −16 | 3 → **4** | pass, no atom moved |
| d | `busy_day` / 424242 / 12 | 17:17:00 | **218** | 364 | **−146** | 3 → **4** | pass, no atom moved |
| e | `busy_day` / 171717 / **24** | 17:31:00 | **783** | 560 | **+223** | 4 → **5** | pass, no atom moved |
| f | `busy_day` / 424242 / **24** | 18:01:00 | **868** | 551 | **+317** | 3 → **4** | pass, no atom moved |
| g | `busy_day` / 171717 / 12, instrumented | 18:25:00 | **330** | — | — | — | instrumented; not comparable |

### How "no atom moved" is established, and why it is not a hand-diff

`consecutive_passes` increments only when `on_canon` is true, and since 0225
`on_canon` compares **all fourteen** atoms the pair enforces rather than nine.
So a streak going 3 → 4 *is* the assertion that every one of the fourteen
matched the canon. Round 27 was judged by hand-diffing hashes out of the matrix;
that is no longer the stronger instrument, and 0225 is the reason.

Column a's `canon_fp` reads `803698f332adc0d0…`, which is round 27 column a's
committed `fp 803698f3`, so the two instruments agree where they overlap.

### Prediction 3 — judged, and it holds

Six flagship columns green at the floor, from zero before the window:

| depot / scenario / seed / ticks | pairs | streak | green |
|---|---|---|---|
| `busy_day` / 171717 / 24 | 4 | 4 | **true** |
| `busy_day` / 424242 / 24 | 3 | 3 | **true** |
| `busy_day` / 171717 / 12 | 4 | 4 | **true** |
| `busy_day` / 314159 / 12 | 7 | 4 | **true** |
| `busy_day` / 424242 / 12 | 3 | 3 | **true** |
| `normal_day` / 171717 / 12 | 3 | 3 | **true** |

**Six, not seven and not five** — which is what prediction 3 required in both
directions, since *more* than six would have meant the comparison came out
looser than intended. The seventh row the matrix returns is `grid_smoke` on
depot `aacd0bb0…`: streak 1, **green false**, `canon_sdr` NULL. That is the
fixture, it is not flagship, and 0225's P3 was rewritten specifically to stop
judging it.

### Prediction 2 — NOT yet judged, and the two columns in hand do not settle it

Two of the four 12-tick columns are in: 356 and 361, running mean **358.5**
against round 27's four-column mean of 364.

That is **inside the 350–370 s zone this file declared "not resolvable" before
the round started**, and above the 344–354 band prediction 2 committed to. It is
not a judgement yet — c and d are still to come and round 27's own 12-tick
columns spread 358–376. But the shape so far is the one the prediction warned
about rather than the one it hoped for, and the per-column deltas are −2 and −15
against a predicted −16 each: **one column moved about as predicted and the
other barely moved at all.**

Judgement waits for d at 17:17 UTC (12:17 PM CT).

### Column c lands at 342 s, and d now has an arithmetic gate

c came in **16 s under round 27's 358** — the exact point estimate prediction 2
named, on the one column where it landed. The three deltas are **−2, −15, −16**
against a predicted −16 each: one column matched, one nearly, one barely moved.

Three-column running mean **353.0** against round 27's 364.0.

**Stated before d runs, so it cannot be fitted afterwards.** The band is on the
FOUR-column mean, so with 1,059 s banked over three columns:

| for the four-column mean to be | d must land |
|---|---|
| ≤ 354 s (inside the band) | **≤ 357 s** |
| ≥ 344 s (inside the band) | **≥ 317 s** |
| = 351.75 s | d = 348 s, i.e. round 27's d minus the same 16 |

So **d between 317 and 357 s puts the mean inside 344–354**, and round 27's d
was 364.

**AND THE BAND BEING HIT WOULD STILL NOT BE A HIT.** This file committed, before
the round started, that *"if round 28's 12-tick mean lands anywhere in 350–370 s,
the honest report is 'no measurable change', not a hit"* — and 350–354 is inside
**both** the band and the not-resolvable zone. That overlap was written down in
advance precisely so it could not be resolved in our favour after the fact. It
resolves toward **not resolvable**. A mean of 351.75 would mean 0227's effect is
real in direction and below this instrument's resolution in size, which is a
weaker claim than prediction 2 made and is the one the evidence supports.

The only outcome that resolves cleanly is d landing **below 317** (mean under
344, effect larger than predicted and outside the noise zone) or **above 357**
(mean over 354, prediction 2 falsified outright).

### PREDICTION 2 — JUDGED, AND FALSIFIED. The mean is not the finding.

| col | r28 | r27 | Δ |
|---|---|---|---|
| a | 356 | 358 | −2 |
| b | 361 | 376 | −15 |
| c | 342 | 358 | −16 |
| **d** | **218** | 364 | **−146** |
| **mean** | **319.25** | **364.00** | **−44.75 (−12.3%)** |

**319.25 is outside 344–354, so prediction 2 is falsified** — by the rule this
file committed before the round, applied without adjustment. It is falsified on
the *low* side: the effect is larger than predicted, not smaller. It is also
outside the 350–370 "not resolvable" zone, so unlike the three-column position
recorded above, this one is resolvable.

**And the mean is the wrong statistic here.** Sorted, the deltas are
−146, −16, −15, −2. The **median is −15.5, which is prediction 2's point
estimate of −16 almost exactly**, and three of the four columns sit within 1 s
of it. One column moved **eight times** more than the other three.

So the honest split, and it is two findings rather than one:

1. **On a, b and c, prediction 2's per-column point estimate was right** — a
   ~16 s saving, which is what 0227's arithmetic predicted (17.5 ms × ~1,024
   calls = 17.9 s, minus what an index cannot remove).
2. **Column d's −146 s is not 0227 and must not be attributed to it.** Nothing
   in 0227's premise scales to 146 s on one seed and 16 s on three others. It is
   an unexplained outlier and it is recorded as one.

**The averaged claim "0227 removed 45 s from a 12-tick pair" is therefore not
available**, even though the arithmetic supports it and it flatters the change.
0227 is credited with what three columns agree on and d is quarantined until
explained. G27's whole lesson is that this kind of wall-clock arithmetic is the
weakest instrument in the building, and G19 burned four wrong guesses reasoning
from structure — so no mechanism is proposed here.

**What would explain it, as things to test rather than findings:** d ran fourth,
so `ocpp_sessions` was at its largest and 0227's index replaces a Seq Scan whose
cost grows with the table — which predicts a saving that *increases* across a, b,
c, d, and −2/−15/−16/−146 does increase, though not smoothly enough for that
alone. Round 27's d was measured at 364 s (`round27.md` line 345, −165 from 529)
against a smaller table. Both are checkable; neither is checked here.

Note that d's pair is fully conclusive — `inconclusive_pairs` 0, history `PPPP`,
streak 3 → 4, and `canon_fp e418e4f0` / `canon_evt 6453c09b` / `canon_sdr
6fd75365` all unchanged. **It did the same logical work and produced the same
fourteen hashes in 40% of the time**, which is what makes the outlier a real
measurement rather than a short arm. That check was run before the number was
believed, because `db/checks/0143` exists about a short arm being mistaken for a
fast one.

### Column e ran long, and `cron.job_run_details` said it was finished

At 17:42 UTC `cron.job_run_details` showed `r28_e_busy_171717_24` as
**`succeeded`, `1` second**. That is a lie of the instrument, not a result, and
it is the exact artefact the protocol names: the cron command is two statements
(`SET statement_timeout …; SELECT ottoq_determinism_pair(…)`) and the row
reports the first one. Columns a–d show real durations because their rows were
updated on completion; e's had not been, because **e had not completed.**

`pg_stat_activity` — the only authority on whether a pair is in flight —
showed at 17:42:

```
pid 3546817 | active | started 17:31:00 | elapsed 725 s | wait_event_type NULL
SET statement_timeout TO '25min'; SELECT public.ottoq_determinism_pair(171717, 24, 'busy_d…
```

**725 s against round 27's 560 s, still running, and not waiting on anything.**
`wait_event_type` NULL means it is computing, not blocked on a lock or on I/O.

Recorded now, in flight, because a number taken from the cron row would have
been 1 second and would have been wrong by three orders of magnitude.

**One sample against the contention hypothesis.** The `-146 s` on column d was
quarantined above as unexplained, and shared-database contention (`G26`) was
offered as a candidate — `ottoq-demo-metronome` runs every minute on this
database, with `ottoq-depot-tick` and `ottoq-run-governor` every two. But at
17:42 the certification pair was **the only non-idle backend in the database.**
Those jobs complete in under a second each, so they seldom overlap a pair at
all. That is one instant, not a distribution, and it does not refute G26 as an
architectural finding — but it is evidence against contention explaining d, and
it is recorded here rather than left out because it weakens a hypothesis I had
already put in writing.

**The shape across the round is now the thing to explain, not d alone:**

| col | ticks | r28 | r27 | Δ |
|---|---|---|---|---|
| a | 12 | 356 | 358 | −2 |
| b | 12 | 361 | 376 | −15 |
| c | 12 | 342 | 358 | −16 |
| d | 12 | **218** | 364 | **−146** |
| e | 24 | **≥725, in flight** | 560 | **≥ +165** |

A column that ran 40% fast is followed by one running at least 30% slow. Whatever
this is, "0227 made pairs faster" does not describe it, and the mean of the four
12-tick columns describes it even less. This is why d was quarantined rather
than averaged.

### Column e finished at 783 s, and the variance is now the finding

e completed at ~17:44 (cron row updated to **783 s**; `pg_stat_activity` clean at
17:50 with zero pairs in flight). Streak **4 → 5**, green, `canon_fp 92b02f8b`
unchanged — so prediction 1 holds on all five columns so far.

| col | ticks | r28 | r27 | Δ |
|---|---|---|---|---|
| a | 12 | 356 | 358 | −2 |
| b | 12 | 361 | 376 | −15 |
| c | 12 | 342 | 358 | −16 |
| d | 12 | **218** | 364 | **−146 (−40%)** |
| e | 24 | **783** | 560 | **+223 (+40%)** |

**Five pairs produced byte-identical hashes to their canons and their wall-clock
times swung ±40%.** The logical work is provably identical — that is what
fourteen matching atoms means — so every second of this spread is something
outside the computation. Round 28's real result is not prediction 2; it is that
**this instrument has a run-to-run spread far larger than the effect any of
these migrations was predicted to have**, which retroactively weakens every
duration claim in rounds 26 and 27 that rested on differences of 10–20 s.

### PRE-REGISTERED, before f runs at 18:01

f is `busy_day/424242/24t`, round 27's **551 s** — the other 24-tick column, and
the discriminator between two very different stories:

| f lands | reading |
|---|---|
| **≈ 730–830 s** | 24-tick pairs are **uniformly** slower in round 28. That points at **0228**, the only applied change in the engine's path, whose cost is one `depots` primary-key lookup **per emitted event** and therefore scales with event count — twice as many at 24 ticks. round28.md predicted "none, or a shade slower" for 0228; +40% would falsify that prediction, and it would be a real finding rather than noise. |
| **≈ 530–570 s** | e is a one-off outlier exactly like d, in the opposite direction. Then the finding is **unexplained bimodal variance in the harness**, not any migration, and the 12-tick mean question becomes moot because the instrument cannot resolve 16 s. |
| anywhere else | neither story; record and do not reach. |

**The 0228 story has a problem that must be stated now rather than after the
number:** if 0228's per-event lookup cost +223 s at 24 ticks, it should cost
roughly **+110 s at 12 ticks** — and the 12-tick columns got *faster*, by 2, 15
and 16 s. So the clean version of the 0228 hypothesis is already contradicted by
a, b and c. It survives only in some form where the cost is superlinear in event
count. That is written down **before** f so the hypothesis cannot be quietly
reshaped to fit whatever arrives.

### A measurement error I made, recorded

The 17:50 check asked `pg_stat_activity` for `query LIKE '%ottoq_determinism_pair%'`
and got **1 row with `elapsed_s` 0** — which was *the query itself*, matching its
own text, because that check dropped the `pid <> pg_backend_pid()` filter the
17:42 check had. Had I read it as written, e would have been recorded as still
running. Re-run with the filter it returns **0**. The rule that saved it is the
same one that caught the cron row: a number that disagrees with another
instrument gets checked before it gets used.

### What this does NOT threaten

`r28_g`'s value at 18:25 is **call counts**, not wall-clock, and counts do not
vary with how long a pair takes. G21b's caller attribution and G27's 12-tick
load-meter count are unaffected by anything on this page.

### Column f: 868 s. BOTH pre-registered bands missed, so neither story is claimed

f completed at 868 s against round 27's 551 — **+317 s, +57.5%**. Streak
**3 → 4**, green, `PPPP`, `inconclusive_pairs` 0, and `canon_fp e418e4f0` /
`canon_evt 8dc37f82` / `canon_sdr f2587dbc` / `canon_rule 726f6769` all
unchanged. Zero pairs in flight at 18:18, so no collision with g.

**PREDICTION 1 HOLDS ON ALL SIX COLUMNS. Not one atom moved anywhere in round 28.**

The pre-registration above named 730–830 for "24-tick uniformly slower, points at
0228" and 530–570 for "e was an outlier". **868 is outside both.** The rule that
file committed was *"anywhere else | neither story; record and do not reach"*,
and it is applied here as written: **the 0228 story is not claimed**, even though
f being slow is superficially friendly to it and the temptation to widen the band
by 38 seconds is obvious. The band was set before the number and the number
missed it.

### The statistic that does survive: the 24t:12t cost ratio nearly doubled

Both 24-tick columns are far slower and all four 12-tick columns are same-or-
faster. That separates cleanly by tick count, and the ratio states it without
needing either story:

| | 12t mean | 24t mean | **24t / 12t** |
|---|---|---|---|
| round 27 | 364.00 | 555.50 | **1.526** |
| round 28 | 319.25 | 825.50 | **2.586** |
| round 28, excluding d | 353.00 | 825.50 | **2.339** |

**Doubling the horizon used to cost 1.53x. It now costs 2.34–2.59x.** The finding
is robust to dropping column d entirely, so it does not rest on the one column
already quarantined.

A ratio above 2.0 means **something in the tick loop is superlinear in tick
count** — the shape of a query whose cost grows with data the run itself is
writing, so tick N scans what ticks 1..N-1 produced. That is O(n²) in ticks and
quadruples when ticks double. It is exactly the shape `0227` was written to fix
for `ocpp_sessions`, which raises the obvious question of whether there is a
second one.

**That is a candidate mechanism and it is NOT a finding.** G19 burned four wrong
guesses reasoning from structure and `db/checks/0139` closed refusing to name a
caller without a measurement. No migration is drafted, no table is named.

**And the clean 0228 hypothesis stays contradicted**, as pre-stated: a per-event
cost would slow 12-tick pairs by roughly half what it slows 24-tick ones, and the
12-tick columns got *faster*.

### This makes `r28_g` considerably more valuable than it was

`r27_g` is instrumented at **24 ticks**; `r28_g` at **12**. Together they give
per-function call counts at both horizons, so every function gets a measured
scaling ratio. **A function scaling ~2x is linear in ticks and innocent; one
scaling ~4x is the superlinear term and is the thing to fix.** That is a direct
test of the paragraph above, from data captured for other reasons.

Two confounds, recorded before the numbers so they cannot be forgotten
afterwards: `r27_g` ran **before** 0225–0228 were applied, so a difference may be
a migration rather than the horizon; and `r27_g`'s baseline held only fourteen
hand-picked rows, so the comparison is available only for functions appearing in
both captures. `r28_g`'s baseline is the full 304 rows, which is why the next
round will not have the second problem.

## `r28_g`'s baseline re-verified 17:10 UTC — not one counter moved

The 16:23:39 capture claimed validity until g fires on the grounds that
`track_functions` is `'none'` globally and only g's own session sets it. Checked
rather than assumed, 47 minutes and **three certification pairs** later:

| | baseline 16:23:39 | live 17:10 | |
|---|---|---|---|
| `SHOW track_functions` | `none` | `none` | — |
| rows in the view | 304 | 304 | identical |
| `public.ottoq_policy_get` | 15,634,388 | 15,634,388 | identical |
| `twin.ottoq_sim_compute_charger_load_kw` | 1,130 | 1,130 | identical |

Three pairs ran between the two readings and moved **nothing**, which is the
property the baseline rests on, now measured instead of argued. Same check
r27_g's baseline passed across 91 minutes and a container restart.

Note for the diff: the load meter lives in the **`twin`** schema, not `public`.
Its 1,130 lifetime calls are `2` from the `r25_g` era — when `track_functions`
was `'pl'`, which does not count SQL functions, and is exactly what blinded
`db/checks/0129` — plus `r27_g`'s counted **1,128** at 24 ticks. So the 12-tick
count g produces will be the first ever taken with the meter actually visible.


---

## Column g — the instrumented column, and what it found

330 s at `track_functions='all'`. Not comparable to a, b, c, d as a duration
(round 27's instrumented column carried +52% overhead), but its **call counts**
are the point and they do not vary with wall clock.

Full write-up in `db/checks/0144`. Two findings closed:

### G27 — CLOSED

| | calls |
|---|---|
| `twin.ottoq_sim_compute_charger_load_kw` at **12** ticks (r28_g) | **1,004** |
| same at **24** ticks (r27_g) | 1,128 |
| **ratio** | **1.12x** |

**Not 2.0x.** 0223's predicted scaling assumed the meter is called once per
tick; it is very nearly independent of tick count. The per-call arithmetic did
not under-deliver — the assumption underneath it was wrong.

And `db/checks/0130` **derived** ~1,024 calls at 12 ticks without counting them.
Measured 1,004 — **right to within 2.0%**. That derived figure was treated with
suspicion for two rounds and did not deserve it; recorded here because the
correction runs in our disfavour.

### G21b — SOLVED, and it is the same defect class as 0145

`ottoq_policy_get`: **4,894,867 calls, 199,648 ms self time, in one 12-tick
pair.** The pair took 330 s, so that is **60.5% of the entire pair in one
function**, and 85.96% of all function calls made.

The caller is **not** among the 64 in the static census. Every one of them, at
its theoretical maximum (measured invocations × static mentions), sums to
**42,461** — **115x short**. `db/checks/0139` refused to name a caller from that
census and called the shape "a function called from SQL the profiler cannot
attribute." Measured now, not suspected.

It is one view, `public.ottoq_approach_band`, whose first CTE is:

```sql
WITH r AS MATERIALIZED (
    SELECT rr.sim_run_id, rr.depot_id, rr.sim_clock_current,
        GREATEST(ottoq_policy_get(rr.sim_run_id,'approach_freeze_minutes',10),0),
        GREATEST(ottoq_policy_get(rr.sim_run_id,'approach_horizon_minutes',30),1),
        GREATEST(ottoq_policy_get(rr.sim_run_id,'approach_stale_heartbeat_sec',90),1)
      FROM ottoq_sim_runs rr
     WHERE rr.depot_id IS NOT NULL          -- no run scope. EVERY run, ever.
)
```

**831 runs scanned, 1 needed. 2,493 calls per evaluation where 3 suffice.
99.88% waste.** The consumer already filters by run and vehicle and takes one
row — but `MATERIALIZED` is an optimisation fence, so the predicate cannot reach
the CTE, and 96,120 of 96,121 rows are built and discarded.

**Not established, and not to be implied:** that this explains the 24t:12t ratio
moving from 1.53 to 2.34–2.59. It is the right *shape* — cost proportional to a
table the runs themselves grow — but `ottoq_sim_runs` grew only ~4% between the
rounds, which is not obviously enough. The mechanism is confirmed; its
sufficiency for the superlinearity is a separate question and is not answered.

**No fix is drafted.** Three candidate shapes and their pre-flight requirements
are in 0144. The view is read on the decide path, so any change must prove the
four 12-tick canons unmoved before it goes near a round.
