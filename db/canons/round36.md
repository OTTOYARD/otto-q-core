# Round 36 — the purge prediction, confirmed

**Fired** 2026-09-09 at 14:10, 14:24, 14:38, 14:52, 15:06 and 15:26 UTC
(9:10–10:26 AM CT), jobids 536–541. Six columns, flagship depot.

**Judged** 2026-09-12 03:35 UTC (2026-09-11 10:35 PM CT) — **59 hours late**, and
the lateness is part of the record, not a footnote: this session was stopped by a
weekly usage limit from 16:10 UTC on 09-09 until 03:31 UTC on 09-12. Nothing
cert-related ran in between. The recurring jobs (metronome, depot-tick,
run-governor, retention-nightly) kept running and succeeded throughout.

Naming the firing times rather than a window, per round 32's lesson: *a window is
not a name.*

## The prediction

Committed in `db/checks/0166` at ~13:50 UTC, **before the first pair fired**, and
read from that file rather than restated from memory:

> Six of six pass, zero of fourteen atoms differ between arms, zero of fourteen
> move from round 35 on any column. `fp` and `endst` included.

## The verdict: CONFIRMED, exactly as written

| column | fired | outcome | equal | complete | atoms differing A↔B | atoms moved from r35 |
|---|---|---|---|---|---|---|
| busy_day/314159/12t  | 14:10 | passed | true | true | 0 of 14 | 0 of 14 |
| busy_day/171717/12t  | 14:24 | passed | true | true | 0 of 14 | 0 of 14 |
| normal_day/171717/12t| 14:38 | passed | true | true | 0 of 14 | 0 of 14 |
| busy_day/424242/12t  | 14:52 | passed | true | true | 0 of 14 | 0 of 14 |
| busy_day/171717/24t  | 15:06 | passed | true | true | 0 of 14 | 0 of 14 |
| busy_day/424242/24t  | 15:26 | passed | true | true | 0 of 14 | 0 of 14 |

The fourteen atoms compared by name, not by counting keys: `fp, h_cmd, h_dec,
h_evt, h_bkg, h_nrg, h_prop, h_defr, h_cal, h_rule, h_rcl, h_sdr, ticks, endst`.

**A correction to my own first query, recorded because it nearly became a
finding.** Comparing *every* key of `arm_a` against `arm_b` returns 18 keys and
one difference. The four extra keys are `boot`, `clock`, `complete` and `run`,
and the differing one is `run` — the run id, which is *supposed* to differ
between arms. Read carelessly that is "1 of 18 atoms differ" and a false alarm.
The atom list is enumerated explicitly above for that reason.

`fp` matched 0166's recorded reference values exactly:
`b8606125…` (314159), `9c28854e…` (171717, all three horizons),
`7a14aa52…` (424242).

## What this establishes

Between round 35 and round 36 the database lost **millions of rows across 729
historical runs** — `ottoq_rule_evaluations` drained of every doomed row,
`ottoq_events` partially — from two passes of `ottoq_retention_purge_runs`
(`db/checks/0165`). Not one of fourteen atoms moved on any of six columns.

Run-scoping is therefore **demonstrated by deletion, not asserted by reading the
source.** The 0145/0053/0054/0177 defect class was unscoped reads of run-scoped
tables, and all five known instances were found by inspection. A purge is the
experiment those findings imply, and it found no sixth instance. That is the
precondition for ever purging the calendar.

## What this does NOT establish, stated plainly

**The matrix is not green right now, and "streak 3" is not a present-tense
claim.** `ottoq_cert_coverage()` (new, 0252) reports **all nine registered
columns OVERDUE** as of 03:33 UTC on 09-12 — ages 59.4 h to 92.5 h against
max_ages of 6 h and 24 h. A canon records that two pairs agreed when they ran; it
says nothing about whether the column is still being exercised. Round 36 earned
its third consecutive agreement on six columns **as of 2026-09-09**; the correct
statement today is that those canons are stale and owe a round.

And the seventh column did not pass its bar at all — see `db/checks/0169`.
