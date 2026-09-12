# Round 38 — three predictions, three confirmations, and 0255 was necessary but not sufficient

**Fired** 2026-09-12 (UTC): 13:40 `grid_smoke/239001/6t`, 13:43 `grid_smoke/424242/6t`,
13:47 `busy_day/314159/12t`, 14:01 `busy_day/171717/12t`, 14:15 `normal_day/171717/12t`,
14:29 `busy_day/424242/12t`, 14:43 `busy_day/171717/24t`, 15:03 `busy_day/424242/24t`,
15:23 `busy_day/171717/48t` (a), 15:55 `busy_day/171717/48t` (b). Jobids 554–563.

**Judged** 2026-09-12 16:45–16:55 UTC (11:45–11:55 AM CT). Three predictions committed
in `db/checks/0176` at 14:30 UTC — after the 12t/24t pairs had begun but **before the two
48t pairs that test them fired** (15:23, 15:55). `0174`'s earlier prediction 2 was
falsified before the round could judge it (`0175`) and is not re-judged here.

Atoms compared **by name** — `fp, h_cmd, h_dec, h_evt, h_bkg, h_nrg, h_prop, h_defr,
h_cal, h_rule, h_rcl, h_sdr, ticks, endst` — against the arm objects' 19 keys; `boot`,
`clock`, `complete`, `run`, `wsec` are not atoms.

## Internal result: ten of ten

Every pair: **0 of 14 atoms differing between arms.** `wsec` present and agreeing on
all ten. Nothing was in flight and nothing was `running` when judged.

## Prediction 3 (the control) — CONFIRMED

Eight columns — both grid, all six flagship 12t/24t — moved **0 of 14 atoms** from
round 37, matched pair-to-pair by (depot, seed, ticks, scenario) and compared on every
atom, not only `fp`. `fp` references held exactly: `b8606125…` (314159), `9c28854e…`
(171717, every horizon), `7a14aa52…` (424242). 0255 touched nothing it should not have.

**But this is streak 1, not streak 4.** 0255 was `forces_recert=TRUE` and moved the
floor to `2026-09-12 13:06:22.289808`; every canon below it was voided by construction.
Round 38 re-earned all eight at streak 1 above the new floor. The values did not move;
the streak restarted. Both are true and only the second one counts.

## Prediction 1 — CONFIRMED, exactly

The two 48t pairs each passed internally and **disagree with each other on `endst`
alone** — 13 of 14 atoms byte-identical, `h_sdr` through `h_bkg` included. Within
`endst`, on **`world` alone**; the other six sub-keys agree. `wsec` names **`vehicles`
alone**:

```
wsec section    15:23             15:55             agree
vehicles        95ad8811a68c…     507a0f24ded9…     NO
stalls          3e03db4aa74a…     (same)            yes
bess            d06508b990e4…     (same)            yes
chargers        4895c66ad941…     (same)            yes
need_profile    b24639271b27…     (same)            yes
n (row counts)  {bess 1, stalls 158, vehicles 116, chargers 40, need_profile 116}   yes
```

Row counts identical: a **value** change, not a row change. The same shape round 37
produced, and the shape `0176` said 0255 alone would leave behind.

## Prediction 2 — CONFIRMED, exactly

Flagship fleet after the 15:55 pair, `0176 §6.1`:

```
last_state_change                 state     n    domain
2026-09-02 02:00:00+00            offline   96   SIM   (02:00 + 48 × 30 min — 0255's value)
2026-09-12 15:55:00.134421+00     offline   20   WALL  (job 563's transaction start)
```

Same 96/20 split `0176` measured after the 14:15 pair, at the predicted clock. One
UPDATE, one expression, two stored values: 0255's sim-domain write landed on 96
vehicles and the BEFORE trigger `log_vehicle_state_change` re-stamped the 20 whose old
value already equalled the new one — the `0061` equal-value guard, whose sim-clock
branch asks for `status='running'` while both teardown routes flip the status first.

## Verdict on 0255

**Necessary and not sufficient.** It did exactly what it claimed — the teardown's own
write is in the sim domain, and 96 of 116 vehicles prove it — and it could not reach
the trigger that overwrites a subset afterwards. That is not a failure of 0255; it is
the finding `0176` predicted before the data existed. `0256` applies.

## Coverage, stated plainly

`ottoq_cert_coverage()`: **nine of nine OK**, ages 0.9 h to 3.1 h. As round 37 said and
this round proves again: `busy_day/171717/48t` is OK on coverage and **failed its bar**.
Coverage means exercised. The matrix means agreed.

## Where this leaves the matrix

Flagship **six of seven**, every column at **streak 1** above the 13:06:22 floor.
`0256` is `forces_recert=TRUE` and will move the floor again, so round 39 is streak 1
for all seven and round 40 is the first that can reach `V1_DEMO_PLAN`'s stopping rule
(7/7 across two consecutive rounds). The 48-tick column is **not certified**.
