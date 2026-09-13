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

## JUDGEMENT

*(to be written when the six pairs have landed; unschedule the `r42_*` jobs first, then
read `scripts/round-report.sql` §1–§5 and record P1/P2/P3 against the table above)*
