# Lane A margin inputs: the prices that turn measured differences into dollars

**Found by direct search, 2026-09-29, for Lane A (prove the throughput and the money).** Recorded as a Hermes deliverable
would be (CLAUDE.md rule 3): each claim, the date or version it applies to, and its URL. Nothing here is a result. A
dollar figure is always *measured twin delta x one of these prices*, and the delta carries its run IDs
(`ottoq_throughput_sweep_pairs`). A customer's own prices replace these.

## 1. Electricity: already in the database, sourced 2026-07-09

`public.ottoq_depot_tariffs` holds Nashville Electric Service **GSA Part 3** for the twin depot (contract demand 1-5 MW).
Demand is billed on the non-coincident peak, i.e. the highest 30-consecutive-minute kW in the month: **$21.40/kW** summer
(first 1,000 kW) and $21.78 above that; **$20.34** and $20.73 in winter and the transition months. The energy base is
**4.785 c/kWh**, before TVA's monthly fuel-cost adjustment (~2.8-4 c/kWh). The fixed charge is $2,091.71 a month.
Source: https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/gsa-123.pdf (retrieved
2026-07-09). `ottoq_dial_arm_metrics` already prices each arm with it (`demand_charge_usd_month`, `site_cost_usd_per_day`).
The EVC schedule (no demand charge, 21.773 c/kWh flat) is the alternative the row's provenance names.

## 2. Revenue a robotaxi earns: what an hour of uptime is worth

| Claim | Applies to | Source |
|---|---|---|
| Waymo's annualized revenue run rate: **$350 million** | December 2025, reported by Bloomberg | The Driverless Digest, "Waymo's 2025 Year in Review", 2025-12-31, https://www.thedriverlessdigest.com/p/waymos-2025-year-in-review-the-year |
| Waymo fleet: **~2,500 vehicles** | November 2025 | same |
| **450,000+ weekly paid rides** | 2025-12-08 | same |

**Derived:** $350M / 2,500 vehicles = **~$140,000 per vehicle-year**, or **~$384 per vehicle-day**. $350M / (450k x 52)
= **~$15 per ride**, at ~26 rides per vehicle-day.

To price an extra deployed car-hour, divide by the hours a car is deployed per day, which the twin measures
(`deployed_car_hours`). **Confidence: medium.** The source is a run rate reported second-hand, in a scale-up year, for one
operator. Use it as a range, e.g. $15-25 per deployed hour, and never as a point.

## 3. What a robotaxi costs: the capital lens on uptime

| Claim | Applies to | Source |
|---|---|---|
| A converted Jaguar I-PACE robotaxi costs **~$150,000-$200,000**. A purpose-built successor costs **~$75,000-$100,000**. | 2025-2026 estimates, not company-published | X post (Bearly AI), https://x.com/bearlyai/status/2060776487159275809; Chris Paxton, "The First Mass-Produced Robotaxi Is Here", https://itcanthink.substack.com/p/the-first-mass-produced-robotaxi |

**Confidence: low-medium** (secondary estimates). This is the other lens on uptime: the fleet needed for the same rides.
Per the plan, it is **never added** to the revenue lens.

## 4. What a fast charger costs to install: the capital lens on charger turns

| Claim | Applies to | Source |
|---|---|---|
| 350 kW DCFC hardware: **$140,000** (range $128,000-$150,000) | 2019 dollars (ICCT, Nicholas 2019; RMI) | INL/RPT-22-68598, "Breakdown of Electric Vehicle Supply Equipment Installation Costs", Schey, Chu and Smart, Idaho National Laboratory, **August 2022**, §3.2.2 Table 3. Retrieved via https://inldigitallibrary.inl.gov/sites/sti/sti/Sort_63124.pdf |
| 350 kW DCFC installation, one unit per site: **$65,984** (labor $27,840, materials $37,700, permit $290, taxes $154), $189/kW | 2019 dollars | same, §3.2.3 Table 5 ("The cost per unit decreases as more units per site are installed") |

**Derived:** about **$206,000 per 350 kW charger installed** (2019 dollars, single unit; less per unit on a multi-unit
site). The robotic arm is **not** included. Its cost is OTTO-CHARGE's to state.

The build-out's power assumption is cross-checked by `docs/research/answers/R-4-grid-oversubscription-ratio.md` (sourced
2026-08-24): depots with certified load management size their service at ~30-50% of charger nameplate. `dcfc20` allows
3,600 kW of DC against 7,000 kW of nameplate (51%). `dcfc20_grid_today` allows 1,800 kW (26%).

## 5. Still open

- **Labor rate** (for touches avoided): BLS OEWS May 2024, occupation 49-3023, Nashville-Davidson-Murfreesboro-Franklin
  (`https://www.bls.gov/oes/2024/may/oes_34980.htm`). The BLS site refused automated fetches on 2026-09-29, so this is
  to be read by hand.
- **Land** (cars turned per acre): not searched yet.
- **Contract penalties** for late cars: none are public (`docs/research/answers/R-10-fleet-uptime-sla-terms.md` §Q4).
  The lateness lever stays in hours, not dollars.
