# The four-policy comparison, with money — and OTTO-Q does not win

**2026-08-24.** The committed comparison has always reported tardiness, wait, peak kW, turns,
moves and makespan. **None of those is money.** `docs/BENCHMARK_CREDIBILITY.md` named that as the
reason "OTTO-Q wins on peak kW" had to be withdrawn: peak kW is not a bill, and nobody is charged
for it directly. Now that a tariff can turn a load curve into a bill (`sites/tariff.py`), the
comparison has a second axis for the first time.

The result is unflattering and it is the most useful thing in this document.

---

## The numbers

Reduced canonical scenario, seed 424242, 12 assets, billed on NES GSA-3 (Nashville):

| policy | total tardy min | peak kW | demand $ | **monthly $** | vs FIFO |
|---|---:|---:|---:|---:|---:|
| **fifo** | 621 | 340 | 6,035 | **8,162** | — |
| **otto_q_asis** | 395 | 392 | 7,340 | **9,467** | **+1,304** |
| **greedy** | 0 | 402 | 7,404 | **9,532** | +1,370 |
| **cpsat** | 118 | 436 | 7,565 | **9,693** | +1,531 |

> **FIFO is the cheapest policy on every site tested.** OTTO-Q as-is costs **$1,304/month more
> than doing the dumbest possible thing.**

## Why — and why it is not a bug

Tardiness and demand cost **pull in opposite directions.** Serving assets sooner means charging
more of them at once, which raises the peak interval the demand charge bills. FIFO is cheap
because it serializes: it never rushes, so it never stacks load.

**FIFO's low peak is an accident, not an optimisation.** It is not trying to be cheap; it is
trying to be simple, and cheapness falls out. That is precisely the finding: **no policy in the
comparison optimises for money, so the one that accidentally spreads load wins on money.**

## The frontier

A policy beaten on **both** axes is dominated — there is no weighting of the two objectives under
which you would choose it.

| | tardy min | monthly $ | verdict |
|---|---:|---:|---|
| fifo | 621 | 8,162 | Pareto-optimal (the cheap end) |
| greedy | 0 | 9,532 | Pareto-optimal (the fast end) |
| otto_q_asis | 395 | 9,467 | Pareto-optimal **but the position is bad** |
| cpsat | 118 | 9,693 | **DOMINATED** — greedy is faster *and* cheaper |

Two things to sit with:

**1. OTTO-Q as-is is technically on the frontier, but nobody would take its trade.** It gives up
**395 tardy-minutes** relative to greedy in order to save **$65/month**. That is not a tradeoff a
depot operator would accept. Being on the frontier is a low bar; being at a *useful point* on it
is the actual product.

**2. The CP-SAT prototype is strictly dominated.** Greedy beats it on tardiness (0 vs 118) *and*
on cost ($9,532 vs $9,693). The prototype solves a model that does not include the thing that
turns out to cost the most. That is a finding about the model, not about CP-SAT.

## What this says to do

The gap is not that our scheduler is bad at scheduling. It is that **it is optimising a quantity
nobody pays for.** Every policy here minimises time; the bill is set by concurrency. Until the
objective includes the tariff, a smarter scheduler will keep buying tardiness improvements with
the operator's money without anyone noticing.

Concretely:

1. **Put the tariff in the objective.** The weights in `site_alpha.json`
   (`peak_excess_per_kw`, `onpeak_kw_min`) are unitless numbers standing where dollars belong.
   `Tariff.bill()` produces dollars from a load curve; the objective should call it.
2. **Then re-run this comparison.** The point of the exercise is that OTTO-Q should be able to
   reach greedy's tardiness at something much closer to FIFO's bill — that is the whole claim of
   forward scheduling, and it is now falsifiable.
3. **Re-examine the CP-SAT model** in the same light before extending it.

## Honest scope

- **This scenario's peak never approaches any site's power cap**, so no policy is being rewarded
  for respecting a constraint that never binds (`docs/BENCHMARK_CREDIBILITY.md`). The cost
  differences here are pure demand-charge differences.
- **One day, billed as a month.** That is the standard way a demand charge is reasoned about —
  one interval sets the month — but a policy whose worst day happens once still pays all month,
  so this is a fair **ranking** and an indicative magnitude, not a forecast of a real bill.
- **The ratchet uses each policy's own peak as its history**, because the scenario has no
  12-month history. Neutral by construction: no policy is rewarded or punished for a past it
  never ran.
- **Wash and inspect routing is identical FCFS for every policy**, so this isolates the
  charge-assignment decision.
- The committed comparison artifact is **unchanged and still byte-for-byte identical**
  (`comparison_seed424242.json`, sha256 `913932af…`). Cost is a separate artifact,
  `cost_seed424242.json`, generated from the same runs.

## Reproducing

```bash
python3 policies/cost.py            # regenerate and compare against the artifact
python3 policies/cost.py --write    # rewrite it
```

Deterministic: same seed, same bytes, same sha256.
