# Round 41 — nothing the engine computes moved; one residue counter did, and it rebased six canons

Judged 2026-09-13 04:35 UTC against `db/canons/round40.md`. Jobids 588–597, ten pairs,
fired (UTC) 01:55 grid/239001/6t, 01:58 grid/424242/6t, 02:02 busy/314159/12t, 02:16
busy/171717/12t, 02:30 normal/171717/12t, 02:44 busy/424242/12t, 02:58 busy/171717/24t,
03:18 busy/424242/24t, 03:38 busy/171717/48t (a), 04:10 busy/171717/48t (b). All ten
`succeeded`; the last ended 04:18:27 UTC. Nothing in flight at judging
(`pg_stat_activity` = 0 non-idle engine queries), zero running runs. The ten `r41_*` cron
jobs were unscheduled before this file was written.

Tree under test: everything below the 0256 floor (`2026-09-12 16:50:23.319089`) plus
**0259** (`20260912205202`, FALSE) and **0260** (`20260912205301`, FALSE) — both already
tested by round 40 — plus the two applied in the 23:28 → 01:55 gap between round 40's last
pair and this round's first: **0261** (`20260912233647`, the proposer seat, forces_recert
FALSE) and **0262** (`20260913011239`, the `proposer_hold_enabled` catalog key,
forces_recert FALSE). Nothing else was applied.

Round 41 also ran after the first two live D3 proposer runs and the D2 A/B pairs on the
flagship depot (`run_by` = `proposer_demo`, `ab_harness`, 23:44 → 01:30 UTC). That is the
round's one finding.

## Internal result: ten of ten, twenty of twenty

Every pair `outcome = passed`, `equal = true`; all twenty arm runs `validation_status =
passed`. Atoms compared by name — `fp, h_cmd, h_dec, h_evt, h_bkg, h_nrg, h_prop, h_defr,
h_cal, h_rule, h_rcl, h_sdr, ticks, endst`.

| column | fired | arm a / arm b | `h_prop` | `endst` |
|---|---|---|---|---|
| grid_smoke/239001/6t | 01:55 | `6993b28d` / `8cb964c8` | `d41d8cd9` (empty) | `fc792a7b` |
| grid_smoke/424242/6t | 01:58 | `52305cd6` / `c02f464c` | `d41d8cd9` (empty) | `ef60bfa3` |
| busy_day/314159/12t | 02:02 | `1515d30d` / `2c64b792` | `a79c1095` | `147e1b1c` |
| busy_day/171717/12t | 02:16 | `1c6f3cf5` / `0e297ecb` | `0046879e` | `11243f0b` |
| normal_day/171717/12t | 02:30 | `8f6ab410` / `3600899e` | `779e5a74` | `b7baf8bd` |
| busy_day/424242/12t | 02:44 | `84b8437d` / `ec6fccdf` | `029cad7d` | `c3b0d1b5` |
| busy_day/171717/24t | 02:58 | `f2befde1` / `bfb23568` | `0046879e` | `e55821ca` |
| busy_day/424242/24t | 03:18 | `bf17b6b3` / `ba52c372` | `aabef458` | `343bd724` |
| busy_day/171717/48t (a) | 03:38 | `71df2232` / `dd5e1008` | `f260e51f` | `063e6d95` |
| busy_day/171717/48t (b) | 04:10 | `faf91985` / `722088d3` | `f260e51f` | `063e6d95` |

The two 48t pairs agree with each other on all fourteen atoms and on every `wsec` section
(`combined` `3715ff59…` both). The 0193 bar — two consecutive 48t pairs agreeing with each
other — is met for the **third** round running.

## Round 41 vs round 40, per column: one atom moved, and it is not an engine output

| column | atoms moved vs r40 | which |
|---|---|---|
| grid_smoke/239001/6t | **0 of 14** | — |
| grid_smoke/424242/6t | **0 of 14** | — |
| busy_day/314159/12t | **1 of 14** | `endst` |
| busy_day/171717/12t | **1 of 14** | `endst` |
| normal_day/171717/12t | **1 of 14** | `endst` |
| busy_day/424242/12t | **1 of 14** | `endst` |
| busy_day/171717/24t | **1 of 14** | `endst` |
| busy_day/424242/24t | **1 of 14** | `endst` |
| busy_day/171717/48t | **1 of 14** | `endst` |

`fp, h_cmd, h_dec, h_evt, h_bkg, h_nrg, h_prop, h_defr, h_cal, h_rule, h_rcl, h_sdr, ticks`
are byte-identical to round 40 in all nine columns. Every grid column is byte-identical on
all fourteen.

**The `endst` difference is one section, one number, identical in all six flagship columns:**

```
endst.legs.fgn.n :  13  (rounds 39 and 40)  ->  9  (round 41)
endst.legs.fgn.h :  d2ad01ee1d4004edb1c80f77545bfcb3 -> e2bd0e4a63dd26624def4368aff5c7ba
```

`fgn` is defined by `db/migrations/0125` as **other runs' rows still in live states — the
cross-run hazard set**. `endst.legs.fgn` therefore counts itinerary legs belonging to runs
that are not this arm, on vehicles homed at this depot, in `planned / active / in_progress`.
`bookings.fgn`, `visit_needs.fgn` and `dispatches.fgn` are 0 in every round-39/40/41 pair;
only the legs section moved.

Measured after the round: the flagship depot's foreign live legs are **9 rows, all from
`9291ec6d-12b2-4d44-b4f9-35d47f08e9da`** (`run_by = operator_demo`, started 2026-08-29,
run `status = completed`), all `status = planned`. The four that disappeared belonged to a
run whose legs were closed to `amended` by a later run's supersede. Every D2/D3 run from
last night left its own legs terminal (`amended` / `done`): `ccf48af1` 41 amended + 50 done,
`af2def1b` 15 amended, the eight `ab_harness` runs 17–18 amended each. So the demo and A/B
work did **not** leave live residue; it cleared four rows of somebody else's.

## Verdict on 0261 and 0262

**Both `forces_recert = FALSE` classifications hold.** 0261 moved the proposer seat into
declared data; 0262 registered one policy key in the catalog and classified it. Neither can
reach a certification arm with the proposer quiesced, and the measurement agrees: `h_prop`
and `h_defr` — the two atoms that would move if either had touched a cert arm's proposal or
deferral stream — are byte-identical to round 40 in all nine columns, and `h_prop` is the
empty hash in both grid columns exactly as before.

## The finding: the canon rebases when other runs' residue moves (G46)

Six flagship columns read `consecutive_passes = 1` after this round, down from 2, and
`green = false`. **Nothing in the engine changed.** `ottoq_cert_matrix` takes the most
recent pair as the canon and walks backwards while every atom matches, so a change in
`endst.legs.fgn` — a count of *other runs'* rows — breaks the streak and silently installs
a new canon carrying the new residue count.

That is a defect of the instrument, not of the engine, and it has teeth now that demo runs
on the flagship depot are routine:

1. **It cries wolf.** A D3 demo, an A/B pair, or any other run on the same depot can
   de-green every flagship column without touching a line of engine code.
2. **It rebases silently.** The canon now carries `fgn.n = 9`. The next round will rebase
   again if that number moves again. A streak built on a moving residue count is not a
   streak.
3. **The residue is real and nobody owns it.** Nine legs from a run that completed on
   2026-08-29 are still `planned` two weeks later. Nothing closes legs for a run that ended;
   this is G13's janitor gap, measured on the flagship depot for the first time.

`fgn` belongs in the fingerprint — 0125 put it there because unscoped reads of run-scoped
tables (the 0145 class) are exactly how foreign rows reach a run's decisions. The fix is
not to stop measuring it. Two candidates, to be designed and adversarially reviewed before
either is applied:

- **Retire the residue, then assert it stays zero.** Close the nine stale legs (a scoped
  `UPDATE` on legs whose run is not running), then have the pair report a non-zero foreign
  residue as `inconclusive` rather than passing and rebasing. A pair run on a dirty depot
  is not comparable to one run on a clean one, and `inconclusive` is the verdict the matrix
  already excludes from canon.
- **Split the atom.** Keep `fgn` in the verdict for arm-vs-arm equality (where it is
  cheap and correct) but judge the canon on the run's own sections, reporting `fgn`
  alongside. This is the G25 trap in reverse, so it needs the same care: an atom that is
  reported and not judged must be loud.

Either way the streak arithmetic must not be able to treat someone else's rows as an
engine change. Tracked as **G46**; round 42 is not scheduled until it is decided, because
another round now would just re-measure the same ambiguity.

## Coverage

`ottoq_cert_coverage()`: 9/9 columns registered and exercised. Two columns remain green on
their own terms — `grid_smoke/239001/6t` and `grid_smoke/424242/6t` at streak 3, and
`busy_day/171717/48t` reads streak 2 only because both of its round-41 pairs sit on the new
residue count.
