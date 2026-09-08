# Round 27 — predictions, written 2026-09-08 12:45 UTC / 7:45 AM CT

**Written before round 26 finished and long before round 27 is scheduled**, so
that neither prediction can be tuned to a result. The schedule below is filled
in when the round is laid out; everything above it is fixed as of this commit.

The recertification for two migrations, both drafted and dry-run read-only
against the live catalog while round 26 was still running:

- **0223** — `twin.ottoq_sim_compute_charger_load_kw` hoists
  `ottoq_depot_running_run(p_depot_id)` out of a per-row filter into a
  `MATERIALIZED` CTE. Evidence: `db/checks/0130`.
- **0224** — `ottoq.ottoq_react_to_refusals` stops hardcoding
  `p_data_source:='production'` on rows it hands a sim run id. Evidence:
  `db/checks/0132`.

## Prediction 1 — no verdict atom moves, on any column

For **0224 this is proven, not predicted.** `h_evt` hashes
`event_type | entity | sim_clock_at` over `WHERE e.sim_run_id = v_run`.
`data_source` is in neither the hashed content, nor the ORDER BY, nor the
row-set predicate, and 0224 changes nothing else. Its P1 block asserts that
against the live `ottoq_determinism_pair` at apply time rather than against this
paragraph — so if someone widens `h_evt` before the migration lands, it refuses
rather than lying.

For **0223 it is a prediction**, resting on three things:

1. `ottoq_depot_running_run` is STABLE, which is the declaration that one
   evaluation per statement equals N. P1 asserts the volatility flag.
2. A2a evaluates it per row across all 44,312 flagship `ocpp_sessions` rows —
   passing `cs.depot_id`, a Var, so the planner cannot hoist it — and requires
   every one of those evaluations to equal the single hoisted value. It passed
   on the dry run.
3. A2b compares the CTE form against the flat form on a run key that selects
   real sessions, and refuses to pass if every probe sums to zero.

**If an atom moves, the migration is what gets reverted, not the canon.**

## Prediction 2 — the pair loses about 109 seconds

`db/checks/0130` measured the load meter at **195.4 s per 12-tick pair**, of
which **108.8 s** is 8,966,506 evaluations of a constant. 0223 removes that
108.8 s and leaves the rest.

The baseline is round 26's own numbers, not a remembered range — that mistake
is what made round 26's prediction 2 land 87 s wide:

| column | round 26 | predicted round 27 |
|---|---|---|
| a — `busy_day`/314159/12t | 537 s | ~428 s |
| b — `busy_day`/171717/12t | 533 s | ~424 s |
| c — `normal_day`/171717/12t | 477 s | ~368 s |
| d — `busy_day`/424242/12t | 529 s | ~420 s |
| mean | **519 s** | **~410 s** |

**The stated prediction is the mean: 519 s → about 410 s, ±30.** The ±30 is not
decoration; round 26's four columns spanned 60 s, so a single column landing
outside the band means nothing and the mean landing outside it means the
arithmetic is wrong.

24-tick columns are excluded from the prediction. The meter's cost scales with
ticks and the fingerprint's does not, so the 24-tick saving should be roughly
double — but that is an inference, and round 26's e and f are the first
post-0222 24-tick measurements this project has, so there is no baseline worth
predicting against yet.

## What would falsify each, stated as an action

| result | reading | action |
|---|---|---|
| an atom moves | one of the two arguments is wrong | revert that migration, keep the canon |
| mean lands ~410 | both fixes did what they claimed | sweep FIX 2 (the `ocpp_sessions` Seq Scan) next |
| mean lands ~519 | the hoist bought nothing on a pair | 0223 joins the two earlier fixes that measured beautifully and moved no clock; say so in this file and stop optimising the meter |
| mean lands between | partial | attribute before continuing — do not average it into a win |

## Schedule — laid out 2026-09-08 13:44 UTC, after 0223 and 0224 were applied

| | column | fires (UTC) | fires (CT) | slot |
|---|---|---|---|---|
| a | `busy_day` / 314159 / 12t | 13:55 | 8:55 AM | 17 min |
| b | `busy_day` / 171717 / 12t | 14:12 | 9:12 AM | 17 min |
| c | `normal_day` / 171717 / 12t | 14:29 | 9:29 AM | 17 min |
| d | `busy_day` / 424242 / 12t | 14:46 | 9:46 AM | 17 min |
| e | `busy_day` / 171717 / **24t** | 15:03 | 10:03 AM | 31 min |
| f | `busy_day` / 424242 / **24t** | 15:34 | 10:34 AM | 31 min |
| **g** | `busy_day` / 171717 / **24t**, **instrumented** | 15:52 | 10:52 AM | — |

**The slots are deliberately too generous, and the new lookback is why.** The
last-K-runs window added this morning takes the **max** of the last six runs of
each tick count, and six still reaches back past 0222: 754 s for 12-tick,
1,336 s for 24-tick. So the slots are sized for an engine two fixes ago, giving
17 and 31 minutes against pairs that should run ~7 and ~11.

That is the rule working, not failing. `scripts/schedule-round.sql` argues
max-of-K rather than mean-of-K precisely because a slot too SHORT puts two pairs
on one depot and contaminates both — which had to be fixed by hand mid-round 25
— while a slot too LONG costs only wall clock. I had four post-0222 12-tick
measurements in hand and the temptation to tighten by hand was real. Following
the committed rule instead is the point of having written it down.

After this round the window will hold six post-0222 runs and tighten on its own.

## g — the seventh column, and why it is not one of the six

`r27_g` repeats column e's world **instrumented**, and sits after f so it cannot
perturb the six that judge prediction 2. `r25_g` is the precedent.

It carries `track_functions='all'` — **not** `'pl'`, which is the setting `r25_g`
used and the reason `db/checks/0129` could not see what `0130` later found. `'pl'`
counts only procedural-language functions, and every hop of the load-meter chain
is a SQL function. The baseline snapshot of `pg_stat_user_functions` was taken at
**13:45:25 UTC**; no other session sets `track_functions`, so the delta across
`r27_g` is exactly that pair.

It answers G27 directly: **is `ottoq_determinism_pair`'s self time on a 24-tick
pair ~255 s, the same as the 12-tick pair `r25_g` measured, or ~500 s?** "Four
fixed calls" predicts the former. If it holds, the fingerprint is not where
round 26's extra 24-tick saving came from, and the buffer-cache hypothesis gets
its first real test in `ottoq_sim_advance_tick`'s per-tick time — 18.3 s per tick
pre-0222, per `0129`.

## What to record, per column

`db/checks/0134` (found while round 26 was running): the matrix compares nine
atoms and the pair enforces fourteen. So the round file is the only place four
of them are diffed across rounds. Record **all** of these per column, not the
eleven that were habit:

    fp  h_cmd  h_dec  h_evt  h_bkg  h_nrg  h_prop  h_defr  h_cal
    h_rule  h_rcl  h_sdr          <- carried/printed or absent in the matrix
    endst  (as md5(endst::text), arm A; assert arm B equal)

Round 26's `endst` table is the model: four columns, both rounds, identical —
which is what proved 0222 agreed with the function it replaced rather than
merely with itself.

## Results

### a — `busy_day` / 314159 / 12 ticks — **PASS**, 358 s

Fired 13:55:00 UTC (8:55 AM CT), ended 14:00:58, **358 s**.

**Prediction 1 holds on this column: nothing moved.** All fourteen atoms equal
between the arms, and every one of them equal to round 26's value — including
the four the matrix cannot see, which is the reason round 26's endst table
existed and why 0134 says to keep diffing them by hand.

| atom | arm A | arm B | vs round 26 |
|---|---|---|---|
| `fp` | `803698f3` | `803698f3` | = |
| `h_cmd` | `109e340b` | `109e340b` | = |
| `h_dec` | `9abdb4af` | `9abdb4af` | = |
| `h_evt` | `9c631343` | `9c631343` | = |
| `h_bkg` | `174b8835` | `174b8835` | = |
| `h_nrg` | `a9c6b693` | `a9c6b693` | = |
| `h_prop` | `a79c1095` | `a79c1095` | = |
| `h_defr` | `d41d8cd9` | `d41d8cd9` | = (empty-string md5 — no deferrals) |
| `h_cal` | `11a24626` | `11a24626` | = |
| `h_rule` | `fc69953b` | `fc69953b` | = |
| `h_rcl` | `0e67b89a` | `0e67b89a` | = |
| `h_sdr` | `a1f79c20` | `a1f79c20` | = |
| `endst` (md5) | `7b63e109` | `7b63e109` | = |
| `ticks` | 12 | 12 | = |

`h_evt` deserves a sentence of its own, because 0224 changed what goes into
`ottoq_events.data_source` and this atom hashes that table. It did not move, and
that is not luck: 0224's P1 block asserted against the live
`ottoq_determinism_pair` that `h_evt` hashes event_type, entity and sim_clock
over one run scope and never reads `data_source`. The prediction was made from
the verdict function's own body and the round agrees with it.

### Prediction 2 on column a: right about the direction, still wrong about the size

| | round 26 | predicted | round 27 | |
|---|---|---|---|---|
| a — `busy_day`/314159/12t | 537 s | ~428 s | **358 s** | **70 s faster than predicted** |

The per-column prediction was 537 − 109 = 428 s. It came in at 358 s, a saving of
**179 s** where 109 s was claimed — 1.64x the prediction, in the direction that
flatters the fix.

**One column is not a verdict on prediction 2** — the committed rule is that the
mean judges it, and a single column outside the band means nothing. But it is
worth naming now which way this is likely to go, before the other five land and
the temptation to explain them appears: the same shape as G27. Round 26's
24-tick columns also saved about 2.2x what the fingerprint arithmetic predicted,
and that anomaly is what `r27_g` was scheduled to measure. If b, c and d also
overshoot, then 0223 and 0222 are both cheaper than their own arithmetic says,
and the arithmetic — not the fixes — is what needs explaining. `r27_g`'s
`pg_stat_user_functions` diff is the instrument for that, and it is already
scheduled with `track_functions='all'` precisely so it can see SQL functions,
which is what blinded `0129`.


### b — `busy_day` / 171717 / 12 ticks — **PASS**, 376 s

Fired 14:12:00 UTC (9:12 AM CT), ended 14:18:16, **376 s**.

All thirteen atoms equal between the arms and equal to round 26 — and for the
eleven round 26 tabulated, equal to round 25 as well, so this column now has the
same values across three rounds and four migrations.

| atom | arm A | arm B | vs round 26 | vs round 25 |
|---|---|---|---|---|
| `fp` | `92b02f8b` | `92b02f8b` | = | = |
| `h_cmd` | `1ae7ba68` | `1ae7ba68` | = | = |
| `h_dec` | `cf2f44e2` | `cf2f44e2` | = | = |
| `h_evt` | `e16ad964` | `e16ad964` | = | = |
| `h_bkg` | `7146a8e1` | `7146a8e1` | = | = |
| `h_nrg` | `08f719af` | `08f719af` | = | = |
| `h_prop` | `0046879e` | `0046879e` | = | = |
| `h_defr` | `d41d8cd9` | `d41d8cd9` | = | = (empty-string md5) |
| `h_cal` | `11a24626` | `11a24626` | = | = |
| `h_rule` | `3e57f511` | `3e57f511` | = | = |
| `h_rcl` | `0a4ca4d3` | `0a4ca4d3` | = | = |
| `h_sdr` | `a2a35e03` | `a2a35e03` | = | = |
| `endst` (md5) | `c6424383` | `c6424383` | = | = |

### The mean after two columns

| column | round 26 | predicted | round 27 | actual saving | predicted saving |
|---|---|---|---|---|---|
| a — `busy_day`/314159/12t | 537 s | ~428 s | **358 s** | −179 | −109 |
| b — `busy_day`/171717/12t | 533 s | ~424 s | **376 s** | −157 | −109 |
| **mean so far** | **535 s** | **~426 s** | **367 s** | **−168** | **−109** |

**367 s against a predicted band of 380–440.** Two of six columns is not the
verdict — the committed rule is the mean over the four 12-tick columns — but the
mean is now below the band rather than one column being below it, and both
columns overshoot in the same direction by a similar factor (1.64x and 1.44x).

Recording the reading now, before c and d land, so that whatever they do the
prediction is judged against a number written down first: **if the four-column
mean finishes below 380 s, prediction 2 was wrong about the size and the
arithmetic behind it is what needs explaining, not the fix.** That is the same
sentence round 26 forced about the fingerprint, and it is the second time the
per-call arithmetic has under-predicted a hoisting fix by roughly the same
factor. `r27_g` at 15:52 UTC, instrumented with `track_functions='all'`, is the
instrument for it.

### c — `normal_day` / 171717 / 12 ticks — **PASS**, 358 s

Fired 14:29:00 UTC (9:29 AM CT), ended 14:34:58, **358 s** — the same second as
column a, from a different scenario and a different seed.

All thirteen atoms equal between the arms; `endst` md5 `81b46976`, which is
round 25's and round 26's value for this column.

| atom | arm A = arm B | vs round 26 |
|---|---|---|
| `fp` | `92b02f8b` | = |
| `h_cmd` | `5921ef70` | = |
| `h_dec` | `37624cdd` | = |
| `h_evt` | `ac672423` | = |
| `h_bkg` | `ed4a986c` | = |
| `h_nrg` | `17c9b12b` | = |
| `h_prop` | `779e5a74` | = |
| `h_defr` | `d41d8cd9` | = (empty-string md5) |
| `h_cal` | `11a24626` | = |
| `h_rule` | `5b1d1dfa` | = |
| `h_rcl` | `e4e41e69` | = |
| `h_sdr` | `e0dfbbe8` | = |
| `endst` (md5) | `81b46976` | = |

Worth one line on its own: `fp` here is `92b02f8b`, the **same fingerprint as
column b**, which is a different scenario on the same seed. That is not a
defect and it is not new — the fingerprint is a world-state hash and the two
columns start from the same seeded world; they diverge in what they then do,
which is what `h_cmd` (`1ae7ba68` vs `5921ef70`) and every other atom show.
Noting it because a reader scanning the two tables will see it and wonder.

### The mean after three columns

| column | round 26 | round 27 | Δ |
|---|---|---|---|
| a — `busy_day`/314159/12t | 537 s | **358 s** | −179 |
| b — `busy_day`/171717/12t | 533 s | **376 s** | −157 |
| c — `normal_day`/171717/12t | 477 s | **358 s** | −119 |
| **mean so far** | **516 s** | **364 s** | **−152** |

Predicted band for the four-column mean: **380–440 s**. Three columns in, the
mean is **364 s**, still below it. Column d at 14:46 UTC decides it: d would
have to run **398 s or more** to pull the mean back to 380, and no 12-tick
column in this round has come within 20 s of that.

So the falsification stated before the round is about to fire. Writing the
conclusion now, before d lands, so it is not written to fit:

> **Prediction 2 is going to be wrong about the size, in the direction that
> flatters the fix.** The mechanism was right — the pair got faster, on every
> column, by a lot. The arithmetic that turned the mechanism into 109 s was
> wrong, and it is the second time: G27 recorded round 26's 24-tick columns
> saving 2.2x what the fingerprint arithmetic predicted, and this is 1.4x.
> Two independent hoisting fixes have both beaten their own per-call
> arithmetic. That is a pattern in how the arithmetic is done, not luck in
> which functions were fixed, and `r27_g` at 15:52 UTC — instrumented with
> `track_functions='all'` — is the measurement that should explain it.

### d — `busy_day` / 424242 / 12 ticks — **PASS**, 364 s

Fired 14:46:00 UTC (9:46 AM CT), ended 14:52:04, **364 s**. Thirteen atoms equal
between the arms; `endst` md5 `2d6ea57e`, which is round 26's value.

| atom | arm A = arm B | vs round 26 |
|---|---|---|
| `fp` | `e418e4f0` | = |
| `h_cmd` | `76134009` | = |
| `h_dec` | `47757095` | = |
| `h_evt` | `6453c09b` | = |
| `h_bkg` | `8bc2877b` | = |
| `h_nrg` | `9917f7c3` | = |
| `h_prop` | `029cad7d` | = |
| `h_defr` | `d41d8cd9` | = (empty-string md5) |
| `h_cal` | `11a24626` | = |
| `h_rule` | `d56e09a3` | = |
| `h_rcl` | `f58ee562` | = |
| `h_sdr` | `6fd75365` | = |
| `endst` (md5) | `2d6ea57e` | = |

---

## THE VERDICT ON BOTH PREDICTIONS

### Prediction 1 — no verdict atom moves: **HELD, on all four columns**

Four columns x fourteen atoms = **fifty-six comparisons, zero movement**, and
every value equal to round 26's. That includes `h_rule`, `h_rcl`, `h_sdr` and
`endst` — the four `db/checks/0134` showed the matrix cannot see, and which
`db/checks/0135` (G28) has since shown were the *only* comparison actually
running for the last four days.

`h_evt` deserves the specific note: 0224 changed what `ottoq_events.data_source`
holds, and 0224's P1 asserted before the apply — against the live verdict
function — that `h_evt` never reads that column. Four columns later it has not
moved. The proof and the round agree.

### Prediction 2 — the pair loses about 109 seconds: **WRONG, and wrong in the direction that flatters the fix**

| column | round 26 | predicted | round 27 | actual saving |
|---|---|---|---|---|
| a — `busy_day`/314159/12t | 537 s | ~428 s | **358 s** | −179 |
| b — `busy_day`/171717/12t | 533 s | ~424 s | **376 s** | −157 |
| c — `normal_day`/171717/12t | 477 s | ~368 s | **358 s** | −119 |
| d — `busy_day`/424242/12t | 529 s | ~420 s | **364 s** | −165 |
| **mean** | **519 s** | **410 ± 30** | **364 s** | **−155** |

Predicted 109 s. Delivered **155 s — 1.42x the claim**, and the mean landed
**16 s below the bottom of the committed band**.

### The falsification table had no row for this, and that is the finding

The table written before the round listed three outcomes: the mean lands ~410
(both fixes did what they claimed), ~519 (the hoist bought nothing), or between
them (partial). **It did not have a row for "better than predicted."**

Reading it back: I enumerated the ways the fix could disappoint and none of the
ways it could over-deliver. That is not a falsification table, it is a risk
register wearing one. The outcome that actually happened arrived with no
pre-written action, which is exactly the state the table existed to prevent.

Recorded rather than patched — the table stays as it was written, above.

### What it means, and what it does not

It does **not** mean 0223 is better than advertised in some vague way. It means
**the arithmetic that converts a per-call measurement into a per-pair saving
under-predicts, and this is the second time**:

| fix | predicted saving | actual | factor |
|---|---|---|---|
| 0222, the boot fingerprint (round 26, 24-tick) | — | — | **2.2x** (G27) |
| 0223, the load-meter hoist (round 27, 12-tick) | 109 s | 155 s | **1.42x** |

Two unrelated fixes, both hoisting a call out of a per-row context, both beating
their own per-call maths. The most likely explanation is that hoisting removes
more than the call itself — it also removes whatever the planner had to do
around it per row — but **that is a hypothesis, not a finding**, and the number
is only ever wrong in our favour, which is precisely why it needs chasing rather
than enjoying.

`r27_g` at 15:52 UTC is the instrument: a seventh column with
`track_functions='all'`, against a `pg_stat_user_functions` baseline captured at
13:45:25. `db/checks/0136` Q8 establishes the same diff also answers G23(b), so
one measurement settles two open findings.

### The committed action

The table's nearest row — *"mean lands ~410 → sweep FIX 2 (the `ocpp_sessions`
Seq Scan) next"* — still applies, and more strongly than it would have at 410:
the fixes are clearly buying real time. **FIX 2 is already drafted as `0227`**,
measured at 17.5 ms and 2,751 buffers per call across ~1,024 calls a pair, with
its before-plan asserted so it refuses to apply if the premise does not hold.

### e — `busy_day` / 171717 / **24 ticks** — **PASS**, 560 s

Fired 15:03:00 UTC (10:03 AM CT), **560 s**. All thirteen atoms equal between
the arms and byte-identical to round 26 — which was itself byte-identical to
round 25. **This column has now produced the same fourteen values in three
consecutive rounds across six migrations.**

`fp 92b02f8b` · `h_cmd 050c4606` · `h_dec 0360adc9` · `h_evt b2230619` ·
`h_bkg 947a2316` · `h_nrg 4c5035fe` · `h_prop 0046879e` · `h_defr d41d8cd9` ·
`h_cal 11a24626` · `h_rule 9564b998` · `h_rcl fa8ab72c` · `h_sdr 957abcfb` ·
`endst 967124f1`

### And the duration constrains G27 — in the opposite direction from round 26

Round 26 left an anomaly (G27): 0222 fixed the boot fingerprint, which is
called **four times per pair regardless of tick count**, so its saving should
have been roughly the same absolute number of seconds at both horizons. It was
not — it removed 228 s from the 12-tick mean and **511 s** from the 24-tick
column, a ratio of **2.24**.

0223 is the opposite shape. The load meter is called **per tick** — about 1,024
calls in a 12-tick pair, *derived* as 8,966,506 evaluations ÷ 8,756 per call
(`db/checks/0130`), not counted directly — so a 24-tick pair should make about
twice as many and the saving *should* scale by about 2.0:

| fix | 12-tick saving | 24-tick saving | ratio | ratio the call count predicts |
|---|---|---|---|---|
| 0222 — boot fingerprint (round 25→26) | −228 s | −511 s | **2.24** | **1.0** (4 calls either way) |
| 0223 — load meter (round 26→27) | −155 s | −201 s | **1.30** | **2.0** (per tick) |

**Both fixes miss their predicted scaling, and they miss it in opposite
directions.** 0222 scaled with ticks when it should not have; 0223 scales with
ticks less than half as much as it should. A single explanation that covers both
is not obvious, and the hypothesis recorded earlier in this file — that hoisting
removes more than the call because it also removes what the planner did around
it per row — predicts *over*-scaling for 0223, which is not what happened.

So G27 is not one anomaly with two data points. It is two anomalies, and the
per-call arithmetic is wrong about *both* directions of tick-scaling.

**What would sharpen this, in order:**

1. **Column f at 15:34 UTC** — the other 24-tick column, different seed. If its
   saving also lands near 1.3x rather than 2.0x, the under-scaling is a property
   of the fix and not of one seed. One column is a reading; two is a pattern.
2. **`r27_g` at 15:52 UTC**, the instrumented column. Its
   `pg_stat_user_functions` diff gives per-function call counts and self-times
   over one complete 24-tick pair. It settles directly whether the load meter is
   actually called ~2x more often at 24 ticks than at 12 — which the whole
   "should scale 2.0" argument assumes and **nothing has yet measured**.

That last point is the honest one: the predicted 2.0 rests on an assumption
about call counts that has never been checked, and the instrument to check it
fires in forty minutes.

### f's prediction, committed 2026-09-08 15:27 UTC — before f fires at 15:34

**Correction to this heading as first committed.** It said "committed 15:36
UTC — while f is running" and that was wrong: the commit landed at **15:26:52
UTC**, seven minutes *before* f fired, not two minutes after. I misread my own
clock check. The error runs in the direction that understates the prediction —
this was committed before the pair started, not during it — and it is corrected
rather than quietly improved because a canon that misstates when its own
prediction was fixed is worth less than one that admits it.

The arithmetic, all of it already on this page:

* Round 27's 12-tick mean is **364 s** against round 26's **519 s** — a saving
  of **155 s**.
* Column e (24 ticks, seed 171717) went **761 s → 560 s**: a saving of
  **201 s**, which is **1.30x** the 12-tick saving.
* 0223's call count predicts **2.0x**, because the load meter is called per
  tick. e missed that by a factor of 1.5, in the direction that flatters
  nothing — it under-delivered.
* **Round 26's column f was 734 s.**

**PREDICTION: f lands at 533 s, and I will accept 520–550 s as confirming.**
That is 734 − 201, i.e. the same absolute saving column e produced. Scaling by
e's percentage instead (−26.4%) gives 540 s, inside the same band, so the two
readings of "behaves like e" do not need to be distinguished.

**What each outcome decides, stated before the number exists:**

| f lands at | reading |
|---|---|
| **520–550 s** | The 1.30x under-scaling is a property of **0223**, not of seed 171717. Two columns, two seeds, same shortfall. G27's second half is then a real question about the fix and not a sampling artefact. |
| **~424 s** (a 310 s saving, 2.0x) | Column **e was the outlier** and the call-count arithmetic is right after all. The seed matters more than the fix does, which would be its own finding and a worse one — it would mean a single 24-tick column cannot be used to reason about scaling at all. |
| **below ~500 s but well above 424** | Partial scaling. Neither story survives cleanly and the honest report is a range, not a ratio. |
| **above 600 s** | Something other than 0223 changed between the rounds, and the whole G27 line of reasoning needs re-grounding before it goes further. |

Note what this prediction does **not** cover, because the round-26 falsification
table made exactly this omission and it was recorded as a finding: **f coming in
*better* than 520 s.** That would mean the saving exceeded even column e's, and
it is not on the table above. Recording the gap here rather than pretending the
table is exhaustive.

Prediction 1 — no verdict atom moves — applies to f unchanged. Round 26's f
canon is the comparison, and it must match to the byte.

### g's prediction, committed 2026-09-08 15:43 UTC — before g fires at 15:52

> **Order note.** This section sits between f's *prediction* and f's *result*,
> which reads oddly. It is deliberate: this file is appended in the order
> things were actually known, and g's prediction had to be committed before g
> fired at 15:52, which was before f's 551 s was written up. Reordering would
> read better and would quietly destroy the one property that makes a
> prediction worth anything — that it was fixed before the answer existed.
> **f's result is the section after this one.**

g is `busy_day` / 171717 / **24 ticks** — the same scenario, seed and horizon as
column **e**, which landed at **560 s**. The only difference is that g's cron
command sets `track_functions = 'all'` in its own session.

**PREDICTION ON DURATION: 570–640 s.** Above e, because per-function
instrumentation is not free, and `ottoq_policy_get` alone is called ~2.4M times
in a *12*-tick pair — every one of which now takes a counter update. If g lands
*below* 560 s, the run-to-run noise is larger than the instrumentation cost and
neither number should be quoted to three digits.

**PREDICTION ON ATOMS: all fourteen identical to e.** `track_functions` is a
statistics setting. If any atom moves between e and g, the certification has a
problem far larger than G27, because it would mean an observability setting
changes the engine's output.

**What g's `pg_stat_user_functions` diff decides, and none of it is decided yet:**

| question | what the diff shows | why it cannot be answered without it |
|---|---|---|
| **G27** | `ottoq_determinism_pair`'s SELF time on a 24-tick pair — ~255 s (as on the 12-tick r25_g baseline, which is what "four fixed calls" predicts) or ~500 s | the whole "0222 should not have scaled with ticks" argument rests on the fingerprint being called four times regardless, and **nothing has measured that at 24 ticks** |
| **G27, other half** | `ottoq_sim_compute_charger_load_kw`'s call count at 24 ticks against the 12-tick figure | 0223's predicted 2.0× scaling assumes the load meter is called twice as often at 24 ticks. That assumption is **derived, never counted** (8,966,506 ÷ 8,756, `db/checks/0130`) |
| **G23(b)** | which functions actually cross `ottoq_stall_bookings`, by self-time | `pg_stat_statements` cannot answer it: reset 2026-07-30, it evicts, and bookings statements are 0.08% of its recorded blocks (`0136` Q7/Q8) |
| **G21b** | per-caller call counts, divided by the static mention counts in `db/checks/0139` Q6 | 64 functions mention `ottoq_policy_get` 179 times and **mentions are demonstrably not calls** — the mention leader has no loop at all |

The baseline is `scratchpad/g27_fn_before.txt`, captured 13:45:25 UTC and
re-verified row by row at 15:16 UTC after a container restart: not one counter
had moved in 91 minutes, and `SHOW track_functions` is `'none'` globally. So the
post-g delta is exactly g's pair — confirmed, not assumed.

**One measurement, three findings.** That is why g exists as a seventh column
rather than as a re-run of e.

### f — `busy_day` / 424242 / **24 ticks** — **PASS**, 551 s

Fired 15:34:00 UTC (10:34 AM CT), **551 s**, `arms_identical` true across all
fourteen atoms. Every value byte-identical to round 26's f, which was itself
byte-identical to round 25's. **This column has now produced the same fourteen
values in three consecutive rounds.**

`fp e418e4f0` · `h_cmd 8f232001` · `h_dec 35148055` · `h_evt 8dc37f82` ·
`h_bkg ea8a12e2` · `h_nrg c79957a5` · `h_prop aabef458` · `h_defr d41d8cd9` ·
`h_cal 11a24626` · `h_rule 726f6769` · `h_rcl 928262d2` · `h_sdr f2587dbc` ·
`endst b2c2dc8e`

**Prediction 1 (no verdict atom moves): HELD.** Six columns, fourteen atoms
each, zero movement across 0223 and 0224.

### The duration prediction MISSED — by one second

The band committed at 15:26:52 UTC, before f fired, was **520–550 s**, centred
on 533. **f landed at 551.** That is outside the band, and it is recorded as a
miss rather than rounded into a hit. One second is a trivial amount of time and
it is not a trivial amount of discipline: a band that gets widened after the
fact to admit the answer is not a band.

What makes it worth writing down rather than shrugging at: **the miss is on the
number, and the reading the band was built to select is the one that holds — and
holds harder.**

| f lands at | reading committed in advance | what happened |
|---|---|---|
| 520–550 s | under-scaling is a property of **0223**, not of seed 171717 | **this one, at 551** |
| ~424 s (2.0x) | column e was the outlier; a single 24-tick column can't ground scaling | no |
| 500–520 s | partial scaling; report a range not a ratio | no |
| >600 s | something other than 0223 changed; re-ground G27 | no |

### G27 after two columns per fix: both fixes miss, consistently, in opposite directions

Round 26's f was **734 s**, so f saved **183 s**. Against the 12-tick saving of
155 s that is a ratio of **1.18** — where 0223's per-tick call count predicts
**2.0**.

| fix | 12-tick saving | 24-tick: e | 24-tick: f | ratios | ratio the call count predicts |
|---|---|---|---|---|---|
| 0222 — boot fingerprint (r25→26) | −228 s | −511 s | −602 s | **2.24 / 2.64** | **1.0** (4 calls either way) |
| 0223 — load meter (r26→27) | −155 s | −201 s | −183 s | **1.30 / 1.18** | **2.0** (per tick) |

**The two columns of each fix agree with each other and disagree with the
prediction the same way.** 0222 over-scaled on both (2.24, 2.64) where it should
not have scaled at all; 0223 under-scaled on both (1.30, 1.18) where it should
have scaled by two. So the anomaly is **a property of each fix, not of a seed or
of one unlucky column** — which is exactly what column f was run to decide, and
it decides it in the direction that keeps G27 open.

And it kills the hypothesis this file floated earlier. "Hoisting removes more
than the call, because it also removes what the planner did around it per row"
predicts *over*-scaling for 0223. 0223 under-scales on both columns. Whatever
explains 0222 does not explain 0223, and a single mechanism covering both is now
harder to construct, not easier.

**This is still arithmetic about wall-clock, and wall-clock is the weakest
instrument in the building.** `r27_g` at 15:52 replaces it with per-function
call counts and self-times over one complete 24-tick pair — including the two
numbers this whole table assumes and nothing has ever counted: how many times
the boot fingerprint is called at 24 ticks, and how many times the load meter
is.
