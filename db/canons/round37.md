# Round 37 — six columns held, and the seventh named its carrier

**Fired** 2026-09-12 (UTC): 04:05 `grid_smoke/239001/6t`, 04:08 `grid_smoke/424242/6t`,
04:12 `busy_day/314159/12t`, 04:26 `busy_day/171717/12t`, 04:40 `normal_day/171717/12t`,
04:54 `busy_day/424242/12t`, 05:08 `busy_day/171717/24t`, 05:28 `busy_day/424242/24t`,
05:48 `busy_day/171717/48t` (a), 06:20 `busy_day/171717/48t` (b). Jobids 544–553.

**Judged** 2026-09-12 07:05–07:15 UTC (2:05–2:15 AM CT). Prediction committed in
`db/checks/0170` at ~04:00, before the first pair fired.

Ten pairs, all nine registered columns. Atoms compared **by name** — `fp, h_cmd,
h_dec, h_evt, h_bkg, h_nrg, h_prop, h_defr, h_cal, h_rule, h_rcl, h_sdr, ticks,
endst` — not by counting keys: `arm_a` now holds 19 keys and five of them
(`boot`, `clock`, `complete`, `run`, `wsec`) are not atoms, `run` differing by design.

## Internal result: ten of ten

Every pair: `outcome=passed`, `equal=true`, `complete=true`, **0 of 14 atoms
differing between arms**, 0 atoms missing. `wsec` present on all ten with its
`combined` self-check populated, and both arms agreeing on it in all ten — the
first evidence toward eventually promoting it from MEASURED to ENFORCED.

## Prediction 1 — CONFIRMED

Six flagship 12t/24t columns, **0 of 14 atoms moved from round 36**. `fp` matched
0170's committed references exactly: `b8606125…` (314159), `9c28854e…` (171717, all
horizons), `7a14aa52…` (424242). Those six columns are now at **three consecutive
agreeing rounds** (35 → 36 → 37) above the `2026-09-09 09:46:27.088143` floor.

## Prediction 2 — held, and nothing was claimed about canon

Both grid columns passed internally. 0170 deliberately declined to predict their
atom values, so nothing is judged against a canon here.

## Prediction 3 — half right, and the important half WRONG

**Right:** the divergence reproduced exactly as predicted. Both 48t pairs passed
internally and disagree with each other on **`endst` alone** — 13 of 14 atoms
identical — and within `endst`, on **`world` alone**, six of seven sub-keys agreeing.

**Wrong, and it is the falsifiable half:** 0170 predicted `wsec` would name `bess`
or `stalls`. It named **`vehicles`**.

```
wsec section    05:48                             06:20                             agree
vehicles        aae9b73da32ee3a4ac051539bfdf1846  6018dec523efaad332233e7703723bfe  NO
stalls          3e03db4aa74a4655b6bb10f20b450a48  (same)                            yes
bess            d06508b990e4780f947ca04afea56f5c  (same)                            yes
chargers        4895c66ad941383fbc0dff3b0db9ed57  (same)                            yes
need_profile    b24639271b27f6a93f99c8886a57fd94  (same)                            yes
n (row counts)  {bess 1, stalls 158, vehicles 116, chargers 40, need_profile 116}   yes
```

0170 wrote in advance that a `vehicles` answer "means my narrowing is WRONG, and the
0169 argument that twelve agreeing streams exclude those sections has a hole I have
not found… the most informative outcome, and must be written up as such, not quietly
absorbed." It is written up as such in `db/checks/0173`, and the hole is named:
**I reasoned about which tables the streams cover and never asked which writes
happen outside the streams entirely.** A teardown is not a decision, so no stream
hash can see it.

Row counts identical on every section, so this was a **value** change, not a row
change — which the instrument reported in the same call.

## The carrier, convicted the same session

`db/checks/0173` has the full chain. In one sentence: `ottoq_sim_advance_tick` calls
`ottoq_sim_release_depot` on natural completion (`0102`'s teardown), that function
stamps `last_state_change = now()` on every vehicle, and `ottoq_world_fingerprint`
hashes that column. Measured: all 116 vehicles carry the single value
`2026-09-12 06:20:00.190665` — the wall-clock instant the 06:20 job fired.

Two properties explain everything the verdicts showed:
* **`now()` is the TRANSACTION timestamp.** Both arms share one transaction, so both
  receive the identical stamp — the pair cannot fail on it, ever.
* **The teardown fires only when the sim clock reaches the scenario end**, 24 sim-hours,
  which at 30 sim-minutes per tick is **exactly 48 ticks**. The 12t and 24t arms exit
  on tick count first, so their `last_state_change` keeps sim-clock values — which is
  why those six columns reproduce across three rounds and only the seventh does not.

## Coverage, stated plainly

`ottoq_cert_coverage()` after this round: **nine of nine OK**, ages 0.9 h to 3.1 h
against max_ages of 6 h and 24 h. Zero OVERDUE, zero MISSING, zero UNREGISTERED —
against all nine OVERDUE twelve hours earlier.

**And that is exactly the sentence not to quote on its own.** Coverage answers *has
this column been exercised recently*. The matrix answers *did the pairs agree*.
`busy_day/171717/48t` is **OK on coverage and FAILED its bar** — fresh, and wrong.
Neither instrument alone means certified, and a reader glancing at nine green OKs
would conclude the opposite of the truth. The gap is recorded in `db/checks/0173`.

**The 48-tick column is NOT certified and the flagship matrix remains SIX OF SEVEN.**
Its two pairs agreed internally and disagreed with each other, which is precisely
what `0193`'s bar forbids. A named mechanism is progress, not a pass.
