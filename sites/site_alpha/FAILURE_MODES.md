# FAILURE_MODES.md — Site Alpha degradation report & anti-correlation curve

**Run 3, Phase C8 deliverable.** 2026-08-19. Everything below regenerates from
seed **424242**: `python3 sites/site_alpha/run_matrix.py` verifies both
committed artifacts byte-for-byte; `make_charts.py` re-renders the charts from
them. Every cell carries its own run ID (`SA-<sha12>` over the cell content).

## What this is — and honestly is not

This is the **offline pack harness** (CLAUDE.md: packs are data). The live twin
hosts only the robotaxi pack today; running Site Alpha *on the kernel* is
C11's conformance job. These numbers compare **policies under identical
worlds** (CRN: one seeded draw shared by every cell); they are not live-twin
throughput claims. `fifo`/`greedy` are deliberately **cap-blind** baselines —
under power scenarios their damage appears as `cap_violation_kw_min` while
cap-aware policies degrade in waiting time instead; both columns are reported.
`cpsat_alpha` cells all solved to **OPTIMAL** (status recorded per cell), so
its numbers are true optima of the stated objective, not budget artifacts.

## The site

3,000 kW cap · 28 points (10 DCFC 150 kW shared robotaxi|tractor, 8 L2, 2 wash,
1 calibration, 6 AMR pads, 1 swap dock) · three tenants: robotaxi_operator_A
(18 assets, overnight surge 1020–1200), yard_logistics_B (6 e-tractors, two
daytime waves, swap-or-DCFC), amr_fleet_C (24 AMRs × 2 opportunity visits).
72 visits per configuration. Classes registered in `ottoq_vehicle_classes` by
migration **0046** (data-only, post-merge).

## Degradation matrix (9 scenarios × 4 policies; `tug_unavailable` = N/A, stated)

Headline reading of `failure_matrix_seed424242.json` / `degradation_chart.svg`:

| Scenario (injection) | What happens |
|---|---|
| baseline | Site has designed slack: fifo/greedy/cpsat 0 tardy; as-is carries 28 min (its dcfc-first threshold sends two mid-SoC cars to L2 — the live cursor's real trade). |
| blocked_point | fifo pays 127 min (earliest-free choice walks into the thinner DCFC pool); **cpsat re-plans to 0** by re-mixing DCFC/L2. |
| overstay (+45 min on 30% of A) | fifo 101 / as-is 129; cpsat re-sequences to 0. |
| immobile_asset (2 × +120 min holds) | fifo 64 / as-is 92; greedy and cpsat absorb it. |
| mid_session_charger_fault (3 DCFC down at t=1100) | The worst myopic case: fifo 228, as-is 315; **cpsat 0** (shifts sessions ahead of the fault). |
| zone_power_loss (feeder loss: 350 kW for 1050–1230) | **The chart's answer to reservation-fragility:** cap-blind fifo/greedy violate by **11,673 kW·min** (as-is 11,581); cpsat holds **0 violations and 0 tardiness** by pre-charging and queueing through the window (p95 wait 42→140 min — the honest price, reported). |
| human_path_crossing (path closed 1100–1160) | Hits every policy (34–62 min) — move-ins cannot cross the closure; nobody dodges a physical block, planners just lose less. |
| swap_dock_jam (400–700) | Absorbed by all: tractors fall back to DCFC (the alternative-operation mechanism working as designed). |
| work_side_recall_refusal (25% of A refused, +90 min) | Absorbed by all policies at these levels; the refusal *mechanism* (first-class event → re-solve) is C9's deliverable and is exercised there. |

**One-line verdict:** myopic policies degrade wherever the failure interacts
with sequencing (faults, blocks, overstays); the solver re-plans them to zero
at these load levels; and under power loss the difference is categorical —
violate the cap or absorb it in queueing.

## Anti-correlation curve (`anticorrelation_seed424242.json` / `anticorrelation_curve.svg`)

cpsat_alpha, CRN-paired across configurations:

| Config | peak kW | turns | run ID |
|---|---|---|---|
| A+B+C | 680 | 72 | SA-ccf0d53d24e9 |
| A+B (no tenant C) | 560 | 24 | SA-8293b8615c93 |
| A+B+C, C phase-shifted +240 min | 584 | 72 | SA-ee437869c4a1 |

**The shared-infrastructure economics, quantified:** adding tenant C's
anti-correlated opportunity load **triples site turns (24 → 72) for +21% peak**
(560 → 680 kW) — and if C's window is phase-shifted away from A's overnight
surge, the same 3× turns costs **+4% peak** (584 kW). Demand-charge cost grows
sub-linearly with tenants precisely when their duty cycles anti-correlate;
that is the multi-tenant thesis, shown rather than argued. (as-is rows are in
the artifact for pairing: 676/660/684 kW — the myopic policy cannot exploit
the phase shift; the solver can.)

## Reproduction

```
python3 sites/site_alpha/run_matrix.py            # verify committed bytes
python3 sites/site_alpha/run_matrix.py --write    # regenerate artifacts
python3 sites/site_alpha/make_charts.py           # re-render SVGs
```

Determinism notes: policies consume no randomness; the one seeded draw is
shared by every cell; CP-SAT runs single-worker with a fixed seed and a
**deterministic-time** budget (all cells closed OPTIMAL well inside it), so
regeneration is byte-identical for the pinned ortools build. The matrix
runner exits non-zero if regeneration diverges from the committed artifacts.
