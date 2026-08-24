# Battery-buffered site acquisition — does the thesis hold?

**The founder's proposition:** acquisition teams reject sites that cannot supply the whole peak
— need 8 MW, hold out for a 10 MW site. Instead, take a 3–5 MW site and install a 3–5 MW battery,
combining grid and battery to meet peak. The scheduler knows 30 vehicles are arriving in two
hours, so it can have the battery charged and ready rather than spiking the grid connection.

**Verdict: the thesis is sound, the economics are larger than expected, and there is one sizing
correction that would sink it if missed.** Every figure below comes from the NES tariff already
in our own database (`ottoq_depot_tariffs`, schedule `NES_GSA_3`, sourced from the NES
commercial-rate PDF, retrieved 2026-07-09) and the Tesla Megapack 2 XL already modelled in
`ottoq_bess_units`. Nothing here is invented.

---

## 1. What peak shaving is actually worth

NES GSA Part 3 covers contract demand 1,000–5,000 kW — exactly our depot class. Summer demand
charge is **$21.40/kW** on the first 1,000 kW and **$21.78/kW** beyond it.

| monthly peak | demand charge | per year |
|---|---|---|
| 8.0 MW | $173,860 | **$2,086,320** |
| 6.0 MW | $130,300 | $1,563,600 |
| 5.0 MW | $108,520 | $1,302,240 |
| 4.0 MW | $86,740 | $1,040,880 |

**Shaving 8 MW to 5 MW is worth $65,340/month — $784,080/year.** Every megawatt of peak avoided
is worth roughly **$261,000/year**, before counting the site-acquisition option value the founder
is actually after.

## 2. The ratchet is the strongest argument for a forward-looking scheduler

The tariff's billing floor is **30% of the higher of contract demand or the prior-12-month
peak**, and the demand basis is `NCP_30min` — the single highest 30-consecutive-minute average
in the billing month.

**One bad half-hour sets a floor for a year.** A single excursion to 8 MW establishes a 2,400 kW
billing floor, i.e. **a minimum of $51,892/month for the next twelve months — $622,704** — in
months the depot may never come close to that load again.

This is where OTTO-Q's value stops being a throughput argument and becomes an insurance
argument. A myopic scheduler that is *usually* fine and *occasionally* spikes is not slightly
worse than a forward-looking one; it is catastrophically worse, and the damage is not
recoverable within the year. **This is the failure mode a greedy policy cannot see, because the
cost lands months after the decision.**

## 3. The correction: size the battery by ENERGY, not power

This is the one place the proposition as stated would go wrong. A battery has two independent
ratings — how *hard* it can push (kW) and how *long* it can push (kWh). Covering a 3 MW deficit
needs 3 MW of discharge **and** 3 MW × the duration of the deficit in energy.

Megapack 2 XL as modelled: 3,000 kWh, 1,500 kW, usable window 10–95% → **2,550 kWh usable each**.

| cover 3 MW for | energy needed | packs by power | packs by energy | **actually need** |
|---|---|---|---|---|
| 1 h | 3,000 kWh | 2.0 | 1.2 | 2.0 |
| 2 h | 6,000 kWh | 2.0 | 2.4 | **2.4** |
| 3 h | 9,000 kWh | 2.0 | 3.5 | **3.5** |
| 4 h | 12,000 kWh | 2.0 | 4.7 | **4.7** |
| 5 h | 15,000 kWh | 2.0 | 5.9 | **5.9** |

**Beyond about 1.7 hours, energy — not power — sets the pack count.** "A 3 MW battery" sounds
like two Megapacks; covering a realistic four-hour evening return wave takes **about five**. Get
this wrong at acquisition and the site fails on its second bad evening, having passed every
power calculation.

**The practical consequence for site selection:** the question to ask of a candidate site is not
"how many MW" but "how many MW, for how many hours, how often" — a duty-cycle question, which is
precisely what the twin can answer from a modelled arrival wave.

## 4. Recharging is itself a scheduling problem, and a trap

The battery refills from the *same* constrained connection it exists to protect.

| refill | grid headroom | time |
|---|---|---|
| 6,250 kWh (2 h deficit, at 96% round-trip) | 4,500 kW (5 MW grid − 500 kW base) | 1.4 h |
| 12,500 kWh (4 h deficit) | 4,500 kW | 2.8 h |
| 12,500 kWh | 3,500 kW (higher base load) | 3.6 h |

Energy balance is comfortable overnight. **But the refill counts toward the monthly peak like
any other load.** Recharging at 4 MW while the depot draws 1 MW *is* a 5 MW peak — the battery
would set the very demand charge it was bought to avoid. A naive "recharge when empty"
controller defeats the entire investment.

So the battery does not remove the scheduling problem; **it converts a hard physical limit into
an optimisation problem with real money attached** — which is the strongest possible position
for us, because it is only solvable with the forward view of arrivals the founder describes.

## 5. A strategic finding that falls out of the tariff

> **CORRECTION 2026-08-24 (research answer R-5).** The EVC figure this section was built on is
> wrong, and the number that follows from it is withdrawn. EVC is **not** a flat 21.773 ¢/kWh.
> The current schedule is **$100/month customer charge + On-Peak 23.279 ¢/kWh + a lower Off-Peak
> tier**; 21.773 ¢ was the off-peak tier (or a prior vintage), not an all-hours rate. Source:
> NES EVC retail rate schedule, July 2024, via `docs/research/answers/R-5-demand-charge-structures-us.md`.
> The corrected crossover depends on the **on-peak/off-peak split of the depot's own load**, which
> is precisely what OTTO-Q schedules — so it is not a single number and must be computed per
> load shape. It is strictly *more* favourable to us than the old framing: the rate choice now
> depends on a quantity only a forward scheduler can produce. Recomputing it against a real
> Site Profile load shape is tracked as work, not asserted here.

NES also offers **EVC** — an EV-specific schedule with **no demand charge**. Against GSA-3's
~8.2 ¢/kWh all-in energy plus demand charges, the original break-even was computed as:

> ~~**160 equivalent full-load hours per month — a 22% load factor.**~~ **WITHDRAWN** — rests on
> the incorrect flat-rate assumption corrected above.

The *direction* of the argument survives and is unchanged:

- At **high** load factor, GSA-3 wins and demand charges dominate → peak shaving is worth the
  $261k/MW/yr.
- At **low** load factor, EVC wins, demand charges matter less, and the battery's economic case
  weakens → but the depot is also badly underused.

The tariff-selection crossover is therefore **an OTTO-Q output, not an input** — the provenance
note in our own tariff row says exactly this. A depot operator asking "which rate should I be on"
is asking a question only a scheduler with a load forecast can answer.

## 6. What is already built, and what is missing

**Already present** (do not rebuild): `ottoq_bess_units` with real Megapack specs including
round-trip efficiency and SoC floor/ceiling; `bess_snapshots` (61,471 rows); `ottoq_depot_tariffs`
with the real NES schedule and demand basis; `ottoq_tariff_windows`; `ottoq_grid_snapshots`
(5,083); `ottoq_solar_output` (18,784); `ottoq_energy_commands` (912); the `ottoq-energy-mpc`
bridge.

**Missing, and these are the gaps that matter:**

1. **`ottoq_energy_plan` is empty (0 rows).** This is the forward schedule — the artifact that
   would tell the battery what is coming. The thesis in §4 lives or dies here.
2. **No demand-charge term anywhere in a comparison objective.** The policy harness scores
   `peak_site_kw` as a bare number; the $21.78/kW that makes it matter is in the tariff table and
   never reaches the objective. **This alone explains why our A/B showed greedy winning.**
3. **No ratchet model.** The 12-month billing floor is the single largest downside risk in the
   tariff and nothing simulates it.
4. **No battery-buffered scenario.** Every committed scenario has an unreachable cap (see
   `BENCHMARK_CREDIBILITY.md`); none models a grid connection *smaller* than demand with a
   battery covering the gap — which is the entire proposition.

## 7. Recommended order

1. **Put the real tariff into the objective** — demand charge, energy by window, and the ratchet.
   The data is already in `ottoq_depot_tariffs`; this is wiring, not modelling.
2. **Build the battery-buffered scenario** — grid cap *below* installed charger capacity, BESS
   covering the gap. This is the first scenario we would have that can discriminate policies at
   all, and its parameters come from the founder's own acquisition thesis rather than being
   tuned for a result.
3. **Populate `ottoq_energy_plan`** as the forward schedule, so the arrival forecast reaches the
   battery instead of stopping at the scheduler.
4. **Then re-run the four-policy comparison.** With demand charges live and a binding cap, the
   comparison finally tests the thing we claim to be good at — and it may still say we are not.
   That result is worth having either way.
