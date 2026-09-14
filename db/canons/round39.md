# Round 39 — three predictions, three confirmations, and 0256 is sufficient

Judged 2026-09-12 20:50 UTC against `db/checks/0183`, committed 16:58 UTC — before the first
pair fired at 17:40 UTC. Jobids 564–573, 17:40–19:55 UTC, ten pairs, all `succeeded`, last
ended 20:03:16 UTC. Nothing in flight at judging (`pg_stat_activity`), zero running runs.

Tree under test: 0256 (`20260912165023`, forces_recert TRUE, floor `2026-09-12 16:50:23.319089`),
0257 (`20260912165137`, FALSE), 0258 (`20260912165243`, FALSE). Nothing else applied between
round 38's last pair (15:55 UTC) and this round.

## Internal result: ten of ten

Every pair `outcome = passed`, `equal = true`; every arm run `validation_status = passed`.
Atoms compared by name — `fp, h_cmd, h_dec, h_evt, h_bkg, h_nrg, h_prop, h_defr, h_cal,
h_rule, h_rcl, h_sdr, ticks, endst`; `boot, clock, complete, run, wsec` are not atoms.

## Prediction 1 — CONFIRMED, exactly

The two `busy_day/171717/48t` pairs (19:23 and 19:55 UTC) agree **with each other** on all
fourteen atoms and on every `wsec` section:

| | 19:23 (`e92856e4`/`90d174ae`) | 19:55 (`f760cd9a`/`73dea632`) |
|---|---|---|
| `fp` | `9c28854e976c8572f2cc1bf4717f85b0` | same |
| `endst.world` | `3715ff59163937dc31cfa74bca98bddc` | same |
| `wsec.vehicles` | `b7d9f803d87bf62d5fd1f1084bfcf056` | same |
| all 13 named atoms | identical | identical |

Rounds 37 and 38 had both 48t pairs pass internally and disagree on `endst.world` with `wsec`
naming `vehicles`. That disagreement is gone. The matrix reads the 48t column **green**,
history `PPPPPP`, `consecutive_passes 2` — the first column with two agreeing pairs above the
16:50:23 floor, because it is the only column that runs twice per round.

## Prediction 2 — CONFIRMED, exactly

After the 19:55 pair (`db/checks/0176` §6.1, re-run 20:47 UTC):

| depot | state | `last_state_change` | n |
|---|---|---|---|
| Nashville Flagship | offline | `2026-09-02 02:00:00+00` | **116** |

One value, sim domain, 02:00 + 48 × 30 min. The 96/20 split of rounds 37–38 is 116/0. No row
carries a 2026-09-12 timestamp. (Grid depot, for the record: 4 vehicles at
`2026-09-01 05:00:00+00` = 02:00 + 6 × 30 min, the same shape.)

## Prediction 3 — CONFIRMED, exactly

Round 39 vs round 38, per column, `arm_a` atoms compared by name and `wsec` compared whole:

| column | atoms moved | `wsec` | `endst.world` 38 → 39 |
|---|---|---|---|
| grid_smoke/239001/6t | 0 of 14 | same | `4926be34…` → same |
| grid_smoke/424242/6t | 0 of 14 | same | `e51fb295…` → same |
| busy_day/314159/12t | 0 of 14 | same | `107033e2…` → same |
| busy_day/171717/12t | 0 of 14 | same | `a9f8a0ae…` → same |
| normal_day/171717/12t | 0 of 14 | same | `53f751e4…` → same |
| busy_day/424242/12t | 0 of 14 | same | `527393ea…` → same |
| busy_day/171717/24t | 0 of 14 | same | `abccb09b…` → same |
| busy_day/424242/24t | 0 of 14 | same | `26b6c892…` → same |
| **busy_day/171717/48t** | **1 of 14 (`endst`)** | `combined, vehicles` moved | `42accd1f…` → `3715ff59…` |

The eight columns whose teardown runs after their atoms are captured did not move at all. The
one column whose natural-completion teardown is what 0256 changed moved on exactly the atom
0256 was built to change, and only there. That is the shape of a fix that did one thing.

## Verdict on 0256

**Sufficient.** 0255 was necessary and not sufficient (round 38); 0256 completes it. The
BEFORE trigger's equal-value fallback now resolves the run through the `ottoq.sim_run_id` GUC
at the natural-completion teardown, status-independent, and the wall clock no longer reaches
a hashed column on that route. `forces_recert TRUE` was the right classification: the 48t
canon moved, as it had to, and nothing else did.

## Coverage, stated plainly

All nine columns ran; 9/9 OK on coverage. The 48t bar (`0193`: two consecutive pairs agree)
is met for the first time since the 13:06 floor.

## Where this leaves the matrix

Flagship seven of seven passing; **48t at streak 2 above the 16:50:23 floor, the other six
at streak 1**; grid two of two at streak 1. Every column is at least streak 1 above the
floor 0256 set. V1_DEMO_PLAN's stopping rule is 7/7 agreeing across two consecutive rounds:
round 40 is the first round that can meet it. Nothing is certified off this round.

## What follows this round (the window)

0259 (`ottoq_proposer_precedence`; forces_recert FALSE, A2 proved 14,779 historical winners
unchanged) and 0260 (`ottoq_proposer_fire_log`; FALSE, new objects only) are applied in this
window, before round 40 is scheduled. Round 40 therefore tests two things at once: the
streak-2 stopping rule, and the FALSE classification of both migrations. If any column moves
in round 40, the classification was wrong and the migration that moved it is convicted
before anything else happens.
