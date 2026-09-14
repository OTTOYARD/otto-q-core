# Round 40 — the stopping rule is met, and two FALSE classifications hold

Judged 2026-09-12 23:29 UTC against `db/canons/round39.md`. Jobids 574–583, ten pairs,
fired (UTC) 21:05 grid/239001/6t, 21:08 grid/424242/6t, 21:12 busy/314159/12t, 21:26
busy/171717/12t, 21:40 normal/171717/12t, 21:54 busy/424242/12t, 22:08 busy/171717/24t,
22:28 busy/424242/24t, 22:48 busy/171717/48t (a), 23:20 busy/171717/48t (b). All ten
`succeeded`; the last ended 23:28:03 UTC. Nothing in flight at judging
(`pg_stat_activity`), zero running runs.

Tree under test: everything below the 0256 floor (`2026-09-12 16:50:23.319089`) plus
**0259** (`20260912205202`, forces_recert FALSE) and **0260** (`20260912205301`, FALSE),
both applied in the 20:52–20:53 UTC window between round 39's last pair and this round's
first. Nothing else was applied. Round 40 therefore tests two things at once: the
streak-2 stopping rule, and whether 0259/0260 were classified honestly.

## Internal result: ten of ten, twenty of twenty

Every pair `outcome = passed`, `equal = true`; all twenty arm runs `validation_status =
passed`. Atoms compared by name — `fp, h_cmd, h_dec, h_evt, h_bkg, h_nrg, h_prop, h_defr,
h_cal, h_rule, h_rcl, h_sdr, ticks, endst`; `boot, clock, complete, run, wsec` are not atoms.

## Round 40 vs round 39, per column: nothing moved

| column | fired r40 | fired r39 | atoms moved | `wsec` | `endst.world` |
|---|---|---|---|---|---|
| grid_smoke/239001/6t | 21:05 | 17:40 | **0 of 14** | same | `4926be34…` |
| grid_smoke/424242/6t | 21:08 | 17:43 | **0 of 14** | same | `e51fb295…` |
| busy_day/314159/12t | 21:12 | 17:47 | **0 of 14** | same | `107033e2…` |
| busy_day/171717/12t | 21:26 | 18:01 | **0 of 14** | same | `a9f8a0ae…` |
| normal_day/171717/12t | 21:40 | 18:15 | **0 of 14** | same | `53f751e4…` |
| busy_day/424242/12t | 21:54 | 18:29 | **0 of 14** | same | `527393ea…` |
| busy_day/171717/24t | 22:08 | 18:43 | **0 of 14** | same | `abccb09b…` |
| busy_day/424242/24t | 22:28 | 19:03 | **0 of 14** | same | `26b6c892…` |
| busy_day/171717/48t (a) | 22:48 | 19:23 / 19:55 | **0 of 14** vs both | same | `3715ff59…` |
| busy_day/171717/48t (b) | 23:20 | 19:23 / 19:55 | **0 of 14** vs both | same | `3715ff59…` |

The two round-40 48t pairs agree with each other on all fourteen atoms and on every
`wsec` section: yes — 22:48 (`b65c84a8`/`9f680f53`) and 23:20 (`a340144d`/`f8bd897c`), zero atoms apart, `wsec` byte-equal. The 0193 bar (two consecutive 48t pairs agree) is met for
the second round running.

## The 0176 §6.1 measurement, after the last pair

| depot | `last_state_change` | domain | n |
|---|---|---|---|
| Nashville Flagship | `2026-09-02 02:00:00+00` | SIM | **116** |

One value, sim domain, 02:00 + 48 × 30 min. No row carries a wall-clock timestamp.

## Verdict on 0259 and 0260

**Both classifications hold.** 0259 moved the proposal selector's first sort key into a
table and the hold gate onto a declared flag; 0260 added a ledger table and a batch door.
A2 of 0259 had already recomputed 14,779 historical winners and found none changed;
this round is the measurement in the engine itself: zero atoms moved in nine columns
over a tree that contains both migrations. `h_prop` — the atom that would have moved if
either had reached a certification arm's proposals — is byte-identical in every column.

## Coverage

`ottoq_cert_coverage()`: 9/9 columns OK, every one registered, every one exercised
inside its window.

## Where this leaves the matrix — the stopping rule

`ottoq_cert_matrix('2026-09-12 16:50:23.319089')`: flagship **seven of seven green at
consecutive_passes ≥ 2** (48t at 4 — two pairs per round for two rounds), grid two of two
at 2. V1_DEMO_PLAN Phase 0's stopping rule — *all seven flagship columns agree across two
consecutive rounds* — is met by rounds 39 and 40. `CERTIFICATION_STATUS.md` is written
off this round; the canon hashes, run ids and the open list are there.

## What follows

0261 (the A/B pair rig, forces_recert FALSE by three reversal-proven splices) applies in
the window after this judging. Round 41 measures that classification exactly as this
round measured 0259/0260: if any column moves, 0261 is convicted.
