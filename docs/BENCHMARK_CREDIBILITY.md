# Why greedy beats OTTO-Q on our own benchmark — and why that is a fact about the benchmark

**Question from the founder:** the last committed four-policy comparison shows a naive greedy
scheduler beating OTTO-Q on throughput. Is that a real finding about our edge, or an artifact?

**Answer: it is an artifact, and the artifact is bigger than the A/B comparison.** Every
committed scenario and every conformance pack in this repository has a site power cap that is
**arithmetically unreachable**. Nothing we have ever run has been power-constrained. Under
abundance, a myopic greedy scheduler is close to correct, and OTTO-Q's triage logic is pure
overhead.

This document is deliberately unflattering where the evidence is unflattering. Two claims made
earlier in this repo are corrected at the end.

---

## 1. Under the scenario's own weights, greedy does not merely win — it dominates

`solvers/cpsat/scenario_canonical.json` declares `objective_weights`. The comparison harness
computes the raw metrics but **never applies the weights**, which is why the committed artifact
reports six unweighted numbers and no verdict. Applying them:

```
weights: tardiness_per_min 10 | onpeak_kw_min 1 | peak_excess_per_kw 20 | per_move 15
site:    soft target 700 kW | hard cap 1000 kW | on-peak window 240–420 min

       policy |  tardy | onpeak kW·min | peak kW | excess | moves | WEIGHTED COST
       greedy |      0 |             0 |     402 |      0 |     9 |           135
        cpsat |    118 |           816 |     436 |      0 |     9 |          2131
  otto_q_asis |    395 |          2166 |     392 |      0 |     9 |          6251
         fifo |    621 |          2995 |     340 |      0 |     9 |          9340
```

**We do not lose narrowly on one axis and win on another. We lose on both live terms.** The
earlier reading — "OTTO-Q wins on peak kW" — was true of the raw peak number (392 vs greedy's
402) and worthless, because the peak term only charges for *excess over the soft target* and
nobody comes near it.

**Why greedy also wins the energy term:** greedy finishes the entire workload by minute 227,
and the on-peak window does not open until minute 240. It pays zero on-peak cost by being
fast, not by being smart. In this scenario **throughput and energy cost are perfectly aligned**,
so there is no trade for a sophisticated scheduler to make.

**Term-by-term, this objective has two dead terms out of four:**

| term | weight | spread across policies | live? |
|---|---|---|---|
| tardiness | 10 | 0 … 621 | yes |
| on-peak kW·min | 1 | 0 … 2995 | yes |
| **peak excess** | **20 (heaviest)** | **0 … 0** | **dead** |
| moves | 15 | 9 … 9 | dead (routing is identical by construction) |

## 2. The power cap cannot bind in ANY committed scenario or pack

Sum the rated draw of every point, assume all of them run flat out at once, and compare to the
cap. If that number is below the cap, no scheduler can ever violate it and no scheduler can
ever earn credit for respecting it.

| scenario / pack | max simultaneous installed draw | cap | can it bind? |
|---|---|---|---|
| `scenario_canonical.json` | 622 kW | 700 soft / 1000 hard | **no** |
| `scenario_24h.json` | 622 kW | 700 soft / 1000 hard | **no** |
| `site_alpha.json` | 1612 kW | 2200 soft / 3000 hard | **no** |
| pack `mining` | 600 kW | 3000 | **no** |
| pack `robotaxi` | 1652 kW | 3000 | **no** |
| pack `vertiport` | 1400 kW | 3000 | **no** |
| pack `yard-logistics` | 1524 kW | 3000 | **no** |

Site Alpha is the starkest: **53% of its hard cap, 73% of its soft target, with every charger
at full rate simultaneously.** Its committed runs report `cap_violation_kw_min: 0` and peak
site load of 676–680 kW against a 3000 kW cap — 23%.

**This is backwards from how real depots are built.** A real site installs more charger
capacity than its service drop can carry and manages the difference — that is the entire reason
smart charging, load management and demand-charge optimisation exist. Our scenarios install
less than the drop and then congratulate the scheduler for not exceeding it.

## 3. What this does and does not say about OTTO-Q

**It does not vindicate OTTO-Q.** On the only benchmark we have, we lose, and the loss is real
within that benchmark's terms.

**It does not condemn OTTO-Q either.** The benchmark cannot discriminate an energy-aware
scheduler from a myopic one, because it contains no scarcity to arbitrage. Every dimension the
strategy is supposed to exploit — a binding power cap, tariff cost, thermal state, pack
degradation, BESS charge/discharge, forward grid position — is either absent from the model or
structurally inert.

**One real insight does survive, and it is worth keeping.** `OttoQAsIsPolicy` orders by
lowest-SoC-first and prefers DCFC below 55%. That is a **risk-management** heuristic: it triages
the most depleted assets first. Triage pays when points or power are scarce and you must choose
who waits. It costs when both are abundant, because it delays nearly-ready assets in favour of
deeply discharged ones and buys nothing. **The measured 395 minutes of tardiness is the price of
triage in a world with nothing to triage.** That is a genuine, defensible statement about when
our policy helps — and it is the opposite of a marketing claim.

## 4. Two corrections to claims already in this repository

**(a) "Zero power-cap violations" across four conformance packs is vacuous.** It appears in
`CONFORMANCE_FINDINGS.md` as evidence the kernel holds the site constraint. Per §2 above, no
pack can reach its cap, so that result was guaranteed by arithmetic before the scheduler ran.
The *verifier* is still not vacuous — `test_verifier_catches_power_cap_breach` constructs a
deliberate breach and asserts rejection, so the check works. What is vacuous is the *pack runs
passing it*. Corrected in place rather than deleted.

**(b) "OTTO-Q wins on peak kW" — withdrawn.** I reported this from the raw peak column. The
objective charges only for excess above the soft target, which is zero for every policy, so the
raw peak difference has no economic meaning in this scenario.

## 5. What a discriminating benchmark requires

Stated as requirements rather than as a scenario, because **it is trivially easy to build a
scenario that makes OTTO-Q win, and such a scenario would be worth nothing.** The parameters
must come from real depot economics, not be chosen for the result.

1. **A binding power cap** — the cap must sit *below* installed charger capacity, as real sites
   are built. Until then the heaviest-weighted term in the objective is dead.
2. **A real tariff, not a binary window** — energy cost and demand charges in currency, so
   "shift 200 kW off-peak" has a number attached.
3. **Cost terms for the dimensions the strategy claims** — pack degradation as a function of
   C-rate and SoC band, thermal derate, and BESS charge/discharge with round-trip loss. None
   exist in the model today.
4. **Arrival pressure that exceeds service capacity for part of the horizon**, so triage is
   forced. The canonical scenario has 12 assets for 6 charge points.
5. **The weighted objective reported as one number**, so a policy comparison has a verdict
   rather than six columns that can be read either way.

**Open question for the founder, and the reason this stops here:** items 1–3 need real numbers —
the actual service-drop capacity relative to installed chargers at a target site, the tariff and
demand-charge structure, and a defensible degradation model. Inventing them would produce a
benchmark that proves whatever it was tuned to prove.
