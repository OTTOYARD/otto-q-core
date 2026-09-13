# Round 42 — the pre-round record, written BEFORE the first pair fired

**Status: IN FLIGHT.** This file is the "before" half, committed at 2026-09-13 14:40 UTC
(9:40 AM CT), four minutes before `r42_a` fired. The judgement goes below the line once the
six pairs land. It is written now, in advance, because round 42 exists to test a prediction
and a prediction recorded after the result is not a prediction.

## Why this round is different

Every previous round asked one question: does the engine still reproduce its canons. This
one asks a second, and it is the first real test of `0266`: **does the split hold when the
world changes underneath a stable engine?**

Between round 41 and this round the world changed by a lot, deliberately:

| | |
|---|---|
| `0266` applied 13:56:34 UTC (`20260913135634`) | `canon_endst` becomes the run's OWN end state; the four `fgn` sections move to the new `ottoq_cert_residue` |
| `0267` applied 14:14:38 UTC (`20260913141438`) | the FK `0260` never gave `ottoq_proposer_fire_log` — the blocking run-scope defect that had been making the retention purge REFUSE |
| the observed purge pass, 14:16–14:25 UTC | **7,300,205 rows deleted** across 7 tables and 939 doomed runs (`db/checks/0201`) |
| `0268` applied 14:29:59 UTC (`20260913142959`) | the lineage row `0267` omitted; the recert floor, which `0267` had moved to its own apply time, is restored to `2026-09-12 16:50:23.319089+00` |

All three migrations are classified `forces_recert = FALSE`, with the argument stated in
each. The floor is therefore **unmoved from round 41's**, and that is deliberate: round 42
is a CONTINUITY test. At a floor of 14:14:38 every column would start a fresh streak and
this round would prove nothing.

## The prediction, stated before the fact

Recorded in `db/checks/0196` (the design) and `db/checks/0201` §2 (the measurement):

- **P1 — every ENGINE column holds.** All nine must still match the canons recorded before
  the purge and stay green. `busy_day/171717/48t` goes 6 → 7. **If an engine column moves,
  the split is drawn in the wrong place and `0266` is wrong.** That is the falsifier and it
  is the reason this round is worth running.
- **P2 — the RESIDUE column MOVES, and names `legs`.** Flagship foreign live legs went
  **9 → 0** in the purge (the same nine `db/checks/0193` §2 named — run `9291ec6d`'s
  pre-janitor backlog). So `endst.legs.fgn` differs from canon `2d1315b9` and
  `sections_moved` should read `legs`.
- **P3 — the two grid columns do not move at all**, in either instrument. The purge touched
  no foreign live rows at `aacd0bb0`: both already read `canon_fgn 13e2e154`,
  `sections_moved NULL`, `history SSS`.

## The "before" state, measured at 14:38–14:40 UTC

Engine columns (`ottoq_cert_matrix` at the floor) — nine, all green:

| depot | seed | ticks | scenario | pairs | streak | history | canon_endst |
|---|---|---|---|---|---|---|---|
| 11111111 | 171717 | 48 | busy_day | 6 | 6 | PPPPPP | `5a3ec345` |
| 11111111 | 171717 | 24 | busy_day | 3 | 3 | PPP | `dc344d68` |
| 11111111 | 424242 | 24 | busy_day | 3 | 3 | PPP | `7fb3eca5` |
| 11111111 | 171717 | 12 | busy_day | 3 | 3 | PPP | `8b5a0ad4` |
| 11111111 | 314159 | 12 | busy_day | 3 | 3 | PPP | `660898c9` |
| 11111111 | 424242 | 12 | busy_day | 3 | 3 | PPP | `4f1879cf` |
| 11111111 | 171717 | 12 | normal_day | 3 | 3 | PPP | `d801f3ce` |
| aacd0bb0 | 239001 | 6 | grid_smoke | 3 | 3 | PPP | `f37e1d96` |
| aacd0bb0 | 424242 | 6 | grid_smoke | 3 | 3 | PPP | `92c84f61` |

Residue columns (`ottoq_cert_residue` at the floor) — flagship all `2d1315b9` /
`sections_moved = legs`; grid both `13e2e154` / `NULL`, `history SSS`.

And the rest of `scripts/round-report.sql`, run end to end for the first time since
`ottoq_cert_residue` came into existence — §3, §4, §4b and §5 had **never been executed**
against a live database before this:

| section | result |
|---|---|
| §3 endst shape | **0 violations over 30 pairs examined.** The denominator matters: `0 of 0` would be UNKNOWN, not clean (`db/checks/0198` C1b) |
| §4 fingerprint | `ottoq_boot_state_fingerprint` matches the `0266` pin `90d490c2…` |
| §4b the untagged half | every column shows exactly **1** distinct value for `chargers`, `calibration` and `world`. This is the door `db/checks/0193` blocker (i) says the split does not close — measured shut today, and not guaranteed shut |
| §5 replay pairs | **0 above the recert floor.** All nine predate it, which is the coincidence `0266`'s G48 predicate removes the dependence on |

## The round

Scheduled 14:34 UTC by `scripts/schedule-round.sql` with `v_round := 42`, six columns,
slots at the 14-minute floor (12-tick pairs measured 129 s and 24-tick 268 s over the last
six runs, so `ceil(s × 1.35 / 60)` is 3 and 7 minutes — the floor dominates and there is no
collision risk):

| job | fires UTC | CT |
|---|---|---|
| `r42_a_busy_314159_12` | 14:44 | 9:44 AM |
| `r42_b_busy_171717_12` | 14:58 | 9:58 AM |
| `r42_c_normal_171717_12` | 15:12 | 10:12 AM |
| `r42_d_busy_424242_12` | 15:26 | 10:26 AM |
| `r42_e_busy_171717_24` | 15:40 | 10:40 AM |
| `r42_f_busy_424242_24` | 15:54 | 10:54 AM |

**AND FOUR MORE, ADDED 14:47 UTC — because the committed script schedules a NARROWER round
than rounds actually run.** `scripts/schedule-round.sql`'s `v_cols` holds six flagship
columns. Round 41 ran **ten pairs across nine columns**: those six, plus both grid columns
and the 48-tick column TWICE (0193's proof needs two consecutive 48t pairs that agree with
each other, not merely with the canon). Scheduling only `v_cols` would have left the
48-tick column — our longest streak at 6, and the one the outward claim rests on — and both
grid columns unrefreshed, while the round still read as complete:

| job | fires UTC | CT | budget |
|---|---|---|---|
| `r42_g_grid_239001_6` | 16:08 | 11:08 AM | 120 s |
| `r42_h_grid_424242_6` | 16:14 | 11:14 AM | 120 s |
| `r42_i_busy_171717_48` | 16:20 | 11:20 AM | 3600 s, 60-min timeout |
| `r42_j_busy_171717_48` | 16:36 | 11:36 AM | 3600 s, 60-min timeout |

Parameters copied from the commands round 41 actually ran (`cron.job_run_details`), not
retyped from memory: grid depot `aacd0bb0-2d02-d101-72cc-33f70e950bc8`, the same
`sim_start` `2026-09-01 02:00:00+00` as the flagship. Ten pairs, nine columns, last pair
ends ~16:45 UTC (11:45 AM CT). **So P1 IS tested on all nine and P3 IS tested.**

### Two defects in `scripts/schedule-round.sql`, found by using it

1. **`v_cols` is six of nine.** The script cannot schedule the round the project actually
   runs. Whoever ran rounds 39–41 must have edited the constant or scheduled by hand; the
   committed default silently drops the 48-tick and grid columns.
2. **The grid columns cannot be sized at all.** The slot comes from the slowest of the last
   six runs of that tick count, with rows under 60 s discarded as in-flight artefacts (the
   round-25 trap, documented in the script's own header). The grid fixture is *designed* to
   finish in seconds (`0153`: "a tiny depot-shaped world so a cert pair runs in seconds"),
   so **every legitimate grid run is discarded** — measured: 13 runs in the window, `max`
   returns NULL — and the script falls back to a 30-minute slot for a 30-second pair. It
   costs wall clock only, which is the safe direction, but the filter cannot tell a fast
   fixture from an in-flight row and for this column it is always wrong.

Neither is fixed here; fixing a scheduling constant under time pressure is exactly what
round 25 did wrong. Recorded for its own change.

---

## INTERIM — pair `a` landed 14:46 UTC, and it is the decisive one

`r42_a_busy_314159_12`, one pair, `validation_status = passed`. Read against the table
above, which was committed before it fired:

| | predicted | measured |
|---|---|---|
| **P1** engine column holds | `canon_endst` stays `660898c9`, green, streak 3 → 4 | `660898c9`, **green**, streak **4**, history `PPPP` ✅ |
| **P2** residue moves, names `legs` | `canon_fgn` leaves `2d1315b9`; `sections_moved` = `legs` | `canon_fgn` → **`13e2e154`**, `sections_moved` = **`legs`**, history `...S` ✅ |

**P1 is the one that mattered and it held.** The engine reproduced a canon recorded BEFORE
the purge, byte-identical, from a world 7,300,205 rows lighter. The falsifier this round
was built around — an engine column moving — did not fire.

### The mechanism, read from the pair's own `endst` rather than inferred

```
legs.fgn         {"h": "d41d8cd98f00b204e9800998ecf8427e", "n": 0}
bookings.fgn     {"h": "d41d8cd98f00b204e9800998ecf8427e", "n": 0}
visit_needs.fgn  {"h": "d41d8cd98f00b204e9800998ecf8427e", "n": 0}
dispatches.fgn   {"h": "d41d8cd98f00b204e9800998ecf8427e", "n": 0}
legs.vis         {"h": "fb1d896a0900d740447d57f2cdb7f195", "n": 685}
```

`d41d8cd98f00b204e9800998ecf8427e` is the md5 of the empty string. All four foreign
sections are now genuinely empty — the nine legs are gone and nothing replaced them — while
the run's own 685 legs are untouched. That is the split doing exactly what `0266` claims:
the half that other runs write went to zero, the half this run writes did not move.

**And an unplanned consistency check falls out of it.** The flagship's new `canon_fgn`
`13e2e154` is the SAME value both grid columns have carried all along. It has to be: four
empty sections hash identically regardless of depot, and the grid depot has never had
foreign residue. Two independently-derived columns agreeing on the empty case is a check
nobody wrote and it passes.

### What is NOT yet judged

- **P3** (both grid columns unmoved in either instrument) — not tested until `r42_g`/`r42_h`
  at 16:08/16:14 UTC.
- **P1 on the other eight columns** — each is tested only when its own pair runs. One column
  holding is not nine.
- **`0193`'s separate proof** — `r42_i` and `r42_j` (16:20, 16:36) are two consecutive 48t
  pairs that must agree with EACH OTHER, not merely with the canon.
- The seven flagship columns that have not re-run still show `canon_fgn 2d1315b9`, because
  their newest pair is still pre-purge. They will move to `13e2e154` as each runs. That is
  expected, and it is the residue column reporting a real change in the world — not drift.

## JUDGEMENT — 2026-09-13 16:49 UTC (11:49 AM CT). All three predictions held.

Ten jobs, ten `succeeded`, 20 arm rows. Nothing in flight at judging (`pg_stat_activity` =
0 non-idle pair queries, 0 running runs — the cron log is not the authority and was not
consulted for this). The ten `r42_*` jobs were unscheduled before this section was written.

### §1 ENGINE — nine of nine green, every canon unchanged

| depot | seed | t | scenario | pairs | streak | history | canon_endst | before |
|---|---|---|---|---|---|---|---|---|
| 11111111 | 171717 | 48 | busy_day | 8 | **8** | PPPPPPPP | `5a3ec345` | `5a3ec345` ✅ |
| 11111111 | 171717 | 24 | busy_day | 4 | 4 | PPPP | `dc344d68` | `dc344d68` ✅ |
| 11111111 | 424242 | 24 | busy_day | 4 | 4 | PPPP | `7fb3eca5` | `7fb3eca5` ✅ |
| 11111111 | 171717 | 12 | busy_day | 4 | 4 | PPPP | `8b5a0ad4` | `8b5a0ad4` ✅ |
| 11111111 | 314159 | 12 | busy_day | 4 | 4 | PPPP | `660898c9` | `660898c9` ✅ |
| 11111111 | 424242 | 12 | busy_day | 4 | 4 | PPPP | `4f1879cf` | `4f1879cf` ✅ |
| 11111111 | 171717 | 12 | normal_day | 4 | 4 | PPPP | `d801f3ce` | `d801f3ce` ✅ |
| aacd0bb0 | 239001 | 6 | grid_smoke | 4 | 4 | PPPP | `f37e1d96` | `f37e1d96` ✅ |
| aacd0bb0 | 424242 | 6 | grid_smoke | 4 | 4 | PPPP | `92c84f61` | `92c84f61` ✅ |

`stale = false` and `inconclusive_pairs = 0` on all nine.

**P1 HELD.** Every engine canon was RE-DERIVED, not merely preserved, from a world
7,300,205 rows lighter than when it was recorded. The falsifier — an engine column moving —
did not fire on any column.

**One correction to my own pre-round text, and it is mine.** P1 said the 48-tick streak goes
"6 → 7". It went 6 → **8**, because when I widened the round I added TWO 48t pairs, not one.
Worse, the first version of this file said in one place that 48t would gain a pair and in
another that it was "not in this round" and "keeps its streak of 6 without adding to it" —
a straight contradiction, written by me, surviving into a committed pre-round record. The
CANON claim (`5a3ec345` unchanged) is what P1 was actually about and it is untouched by
this; the arithmetic around it was wrong in both directions before the round even started.
Recorded rather than quietly corrected, because a prediction file whose own numbers
disagree is worth less than one that admits it.

### §2 RESIDUE — moved on all seven flagship columns, named `legs`, and ONLY there

| depot | column | canon_fgn before → after | streak | history | sections_moved |
|---|---|---|---|---|---|
| 11111111 | all seven | `2d1315b9` → **`13e2e154`** | 48t: 2, others: 1 | 48t `......SS`, others `...S` | **`legs`** |
| aacd0bb0 | both grid | `13e2e154` → `13e2e154` | **4** | `SSSS` | `NULL` |

**P2 HELD** and **P3 HELD**. The purge moved the residue column on exactly the seven
columns whose depot lost foreign rows, named the right section, and moved neither
instrument on the two grid columns — whose residue streak instead grew 3 → 4, because
nothing about them changed.

The flagship's new `13e2e154` is the same value grid has always carried: four empty
sections hash identically regardless of depot. Two independently derived columns agree on
the empty case — a check nobody wrote.

### §3–§5 and 0193's separate proof

| check | result |
|---|---|
| §3 `endst` shape | **0 violations over 40 pairs** (30 before the round, 40 after — the denominator grew with the round, so this is a real clean) |
| §4 fingerprint | matches the `0266` pin `90d490c2…` |
| §5 replay pairs above the floor | **0** |
| **0193** — `r42_i` and `r42_j`, two consecutive 48t pairs | **agree with EACH OTHER** on all thirteen compared atoms plus `endst` whole: 2 pairs, 1 distinct value |

0193's bar is stricter than the canon comparison and is the one that matters for the
48-tick claim: two pairs run 16 minutes apart, both reproducing the same fourteen atoms,
not merely both matching a stored hash.

### What this round establishes, stated exactly

**Nine of nine engine columns reproduced canons recorded before a 7.3-million-row deletion,
while the hygiene column moved on precisely the seven columns the deletion touched and
stayed still on the two it did not.** That is `0266`'s split tested against the largest
deliberate change to this database's contents to date, and it is drawn in the right place.

What it does NOT establish: that the engine is deterministic in general (that is what every
round tests, and this one adds one more round of evidence to each column, no more); that
the space the purge freed has been returned (it has not — G23's VACUUM/REINDEX is still
open); or anything about the columns' behaviour under a purge that touches `visit_needs` or
`dispatches`, which are not in the retention allowlist and whose `fgn` sections have
therefore never been exercised by a purge at all.
