# The four-policy comparison, with money — and OTTO-Q does not win

> **ADDENDUM 2026-08-24, same day — the conclusion below is superseded in the best way.**
> Investigating why an exact solver couldn't reach greedy's zero tardiness exposed an
> over-constraint in the model: parallel ops were forced to end *inside* the charge window,
> exiling ops-heavy assets to slow chargers (AV-05: 41 min of ops, 28 min of DCFC, pushed onto a
> 407-minute L2 session = **118 phantom tardy-minutes**). With that fixed, and a lexicographic
> objective added (tardiness first, then peak — `policies/forward.py`), the picture inverts:
>
> | policy | tardy min | peak kW | monthly $ | vs FIFO |
> |---|---:|---:|---:|---:|
> | fifo | 621 | 340 | 8,162 | — |
> | greedy | 0 | 402 | 9,532 | +1,370 |
> | cpsat (fixed model) | 0 | 440 | 8,161 | −2 |
> | **forward** | **0** | **160** | **5,282** | **−2,880** |
> | *provable ideal* | — | *89.8* | *4,045* | — |
>
> **Zero missed deadlines at $2,880/month below FIFO** — while FIFO misses 621 deadline-minutes.
> Forward sits at 1.31× the provable ideal; every myopic policy sits at 2.0–2.4×. The
> tardiness-vs-cost tradeoff this document diagnosed was real for myopic policies but was
> **never physics** for a forward scheduler: load can be spread flat *and* deadlines met, by a
> scheduler that already knows tonight's total demand. With the site's committed Megapack fleet,
> foresight-aimed dispatch holds the grid at **30.5 kW** ($2,779/mo) — with the honest caveat
> that three Megapacks (7,650 kWh usable) are hugely oversized for this reduced 12-asset day
> (651 kWh), so that last number shows the mechanism, not a sizing recommendation.
>
> The baseline regeneration this required (plan, comparison, cost, KPI-gate artifacts) was a
> **deliberate act**, recorded in the commit; T5 and two cost tests were rewritten to assert the
> corrected physics, each carrying its own history. The analysis below is preserved as written —
> it is the measurement that found the defect.

---

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

## How much of this is actually recoverable — the number that matters more

The gap between policies says one is better than another. It says nothing about how much *any*
of them leaves on the table. So: what would a perfect schedule bill?

There is a **provable lower bound** on the peak. Take any window `[s, e]`; every asset whose
entire feasible interval `[arrival, ready_by]` lies inside it must receive all its energy within
it — it cannot start earlier or finish later. So the average draw over that window is at least
(their energy) / (e − s), and the peak is at least the average. Maximising over all windows gives
a bound no feasible schedule can beat.

For this scenario: **89.8 kW**, set by the window 4–379 min, which must absorb 561 kWh in 6.25 h.

| policy | monthly $ | **left on the table** | × ideal |
|---|---:|---:|---:|
| *ideal (89.8 kW flat)* | **4,045** | — | 1.00 |
| fifo | 8,162 | **4,118** | 2.02 |
| otto_q_asis | 9,467 | **5,422** | 2.34 |
| greedy | 9,532 | 5,488 | 2.36 |
| cpsat | 9,693 | 5,649 | 2.40 |

> **Every policy bills between 2.0× and 2.4× the ideal.** OTTO-Q leaves **$5,422/month**
> unclaimed — and the entire spread *between* the four policies is $1,531.

**The inter-policy gap is about a quarter of the opportunity.** Framing this as "FIFO beats
OTTO-Q by $1,304" understates it by 4×. The real finding is that **all four policies are leaving
roughly $5,000/month on the table, because none of them is trying.**

The bound is deliberately conservative: achieving it would need perfectly interleaved fractional
charging, and real points deliver fixed kW, so the true optimum sits somewhere above 89.8 kW.
**The headroom above is therefore an understatement, never an overstatement** — the right
direction for a number used to decide whether work is worth doing.

## What this says to do

The gap is not that our scheduler is bad at scheduling. It is that **it is optimising a quantity
nobody pays for.** Every policy here minimises time; the bill is set by concurrency. Until the
objective includes the tariff, a smarter scheduler will keep buying tardiness improvements with
the operator's money without anyone noticing.

Concretely:

The headroom answers the "is it worth it" question directly: **yes, and by more than the
policy comparison suggested.**

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

```python
from policies.cost import peak_lower_bound, headroom
peak_lower_bound(scenario)   # the provable bound and its binding window
headroom(scenario)           # ideal bill, and what each policy leaves unclaimed
```

Deterministic: same seed, same bytes, same sha256.
