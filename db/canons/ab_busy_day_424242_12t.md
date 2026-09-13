# A/B canon — busy_day / 424242 / 12t, Nashville Flagship: OTTO-Q vs FIFO vs greedy

Judged 2026-09-13 00:21 UTC (7:21 PM CT) from `db/checks/0185` §1–§4. Four one-shot pairs,
`ottoq_ab_pair(424242, 12, 'busy_day', flagship, '2026-09-01 02:00+00', 900, a, b)`, fired
(UTC) 23:44 otto_q/fifo, 23:52 otto_q/greedy, 00:00 otto_q/otto_q, 00:08 otto_q/fifo again.
All four `succeeded` (124–132 s each); nothing in flight at judging; the `ab*` rows unscheduled
after. Tree: everything in `CERTIFICATION_STATUS.md` plus `0261` (`20260912233647`).

## The instrument first

| pair | group | arm a / arm b | outcome | `world_identical` |
|---|---|---|---|---|
| otto_q / otto_q (self-test) | `d025d7f9-143b-5f92-08c4-31a8bbe00498` | `36caa0c4` / `6a8c9662` | **passed — 0 of 15 atoms moved** | true |
| otto_q / fifo | `1e683534-d791-d4d0-8d6a-0614ba51fb5f` | `b175aa13` / `0b92aa42` | compared | true |
| otto_q / fifo, re-run | `1e683534-d791-d4d0-8d6a-0614ba51fb5f` | `c4687665` / `64489387` | compared | true |
| otto_q / greedy | `c7f1ae81-4248-7fba-15dc-1f1e44679f15` | `6f8980fd` / `4c5de6a5` | compared | true |

- **Self-test:** same seat on both arms at flagship scale, byte-identical on all fourteen
  certification atoms and on `h_arr`. The rig is an instrument.
- **Re-run (0185 §4):** the two otto_q/fifo pairs share group `1e683534`; for each seat every
  atom has exactly one distinct value across its two arms — `fp, h_cmd, h_dec, h_evt, h_bkg,
  h_nrg, h_prop, h_defr, h_cal, h_rule, h_rcl, h_sdr, ticks, endst, h_arr` all 1/1. **The
  comparison reproduces byte for byte.** Phase 1's stopping rule is met.
- **The otto_q arm is the canon:** `h_dec 47757095…` in all four pairs — identical to the
  certified busy_day/424242/12t column (`CERTIFICATION_STATUS.md`). An A/B arm at seat 0 is
  a certification arm by another name, and it lands on the canon.
- **The world did not diverge:** `h_arr 94b26079…` and 116 arrivals in every arm. Over these
  six sim hours nobody is re-deployed (`deploys_total 0`), so the arrival stream is the same
  116 vehicles on the same sim instants for all three seats. Differences below are therefore
  entirely what the seat decided about the same vehicles.

## Who decided each enacted stall assignment (the leak check)

Every arm carries 13 `gate_intake` decisions onto **staging** stalls with no source — the
arrival intake (verb `gate_intake`, ticks 1–2), a kernel step identical in all three arms.
`ottoq_ab_arm_atoms.stall_sources` counts them under `local_heuristic`, which is a labelling
artefact, not a leak; the reader (`0185` §1b) splits by verb. Charger assignments
(`assign_stall`), by source:

| arm | seat's own | reservation_honoured | reservation_broken | reservation_reassigned | OTTO-Q heuristic (no source) |
|---|---|---|---|---|---|
| otto_q | 57 `greedy_constrained` (10 DCFC, 47 L2) | 38 | 1 | 1 | **60** (4 DCFC, 56 L2) — seat 0's own in-tick rule |
| fifo | **125 `fifo`** (12 DCFC, 113 L2) | 37 | 2 | 0 | **0** |
| greedy | **122 `greedy`** (16 DCFC, 106 L2) | 37 | 1 | 1 | **0** |

Under a baseline seat, every non-reservation charger assignment is the seat's. The shield
refused the same six actions in every arm (`HW.005.vehicle_one_active_task` × 6, zero
safety-critical) — the seats did not generate extra refusals, and none of them were able to
propose past the rule.

## The scores (`ottoq_ab_runs`, one row per arm; deltas are baseline minus OTTO-Q)

| metric | otto_q | fifo | Δ fifo | greedy | Δ greedy | what it means |
|---|---|---|---|---|---|---|
| decisions_total | 1442 | 1487 | +45 | 1477 | +35 | decide-path decisions over 12 ticks; fewer is less churn |
| enacted_total | 1175 | 1221 | +46 | 1211 | +36 | decisions that became actions |
| overrides_total / safety_violations / critical | 6 / 6 / 0 | 6 / 6 / 0 | 0 | 6 / 6 / 0 | 0 | shield refusals — **identical** |
| energy_peak_kw (pct of 2,500 cap) | 456.6 (18.3%) | 451.7 (18.1%) | −4.9 | 476.1 (19.0%) | **+19.5** | peak concurrent charging |
| charge_sessions | 96 | 94 | −2 | 97 | +1 | sessions started |
| vehicles_cycled / trips | 116 / 116 | 116 / 116 | 0 | 116 / 116 | 0 | the same arrivals in every arm |
| **vehicles_turned_around** | 47 | 45 | −2 | **49** | +2 | arrived → staged_for_departure inside the window |
| **median_turnaround_min** | **150** | 180 | **+30** | 180 | **+30** | median arrival → ready-to-deploy |
| fleet_ready_pct at end | 42.24 | 40.52 | −1.72 | 43.97 | +1.73 | share of the 116 staged for departure at tick 12 |
| charge_complete_holding at end | **4** | 9 | +5 | 8 | +4 | vehicles idling on a finished charger |
| emergency_staged at end | 1 | 3 | +2 | 2 | +1 | |
| staged_awaiting_service at end | 35 | 32 | −3 | 31 | −4 | |
| throughput_per_hr (0230 `vehicles_served` / 6 h) | 15.67 | 15.67 | 0 | 15.50 | −0.17 | the scorer's served count is ~equal across seats |
| gate_backlog at end | 0 | 0 | 0 | 0 | 0 | |

`incidents_open`, `productive_deploys`, `unsafe_deploys` are NULL by design (no honest
definition in this rig). Run ids per arm are in the instrument table above and in
`ottoq_ab_runs` (`scored_at` 23:44–00:08 UTC).

## The honest reading

On this six-hour busy-day window, with the same 116 arrivals and the same shield, the three
seats are **close**, and the differences are the policy's and nothing else's:

- **OTTO-Q turns a vehicle around 30 minutes faster at the median** (150 vs 180 min for both
  baselines — a 17% shorter dwell), leaves **half as many vehicles parked on a finished
  charger** at the end (4 vs 8–9), and does it with **fewer decisions** (1442 vs 1477–1487).
- **Greedy readies two more vehicles by tick 12** (49 vs 47) and shows the highest ready share
  (44.0% vs 42.2%) — at the price of the **highest peak** (476 kW, +4% over OTTO-Q) and a
  slower median. Myopic "fastest plug first" buys a little end-of-window readiness with
  concurrency the headroom-aware seat declines to spend.
- **FIFO is slowest and readies the fewest** (45), at a marginally lower peak than OTTO-Q.
- **Safety is a wash**, as it must be when the shield is held constant: six identical refusals
  in every arm, zero safety-critical. No arm got to "win by checking nothing" (`0146`).

What this does **not** show: a large throughput gap. Six hours, 116 arrivals and zero
redeploys is a window where every seat can place every vehicle; the separation is in dwell
time and peak, not volume. A 24- or 48-tick comparison, where redeploys make the arrival
streams diverge and chargers saturate, is where the seats will separate on volume — and where
the `h_arr` atom will start to move, which this rig is built to report.

## Reproduce

```sql
SELECT public.ottoq_ab_pair(424242, 12, 'busy_day', '11111111-1111-1111-1111-111111111111'::uuid,
                            '2026-09-01 02:00:00+00'::timestamptz, 900, 'otto_q', 'fifo');
-- lands in group 1e683534-d791-d4d0-8d6a-0614ba51fb5f; db/checks/0185 §4 must then read 1 in every column
```
