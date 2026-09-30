# Lane A: what electricity costs the twin depot, from Nashville's published rates

**Found by direct search, 2026-09-29 evening CT, for Lane A's energy savings.** Recorded as a Hermes deliverable would
be (CLAUDE.md rule 3): each claim, the date or version it applies to, and its URL. Chase, 2026-09-29, 8:20 PM CT, put
energy savings first: *"energy savings (through Bess, solar, and forward planning/scheduling)"*.

## 1. The problem this fixes

The twin priced a day's energy from two sources that disagree:
- **Demand charges** from Nashville Electric Service's published GSA Part 3 rate, sourced 2026-07-09
  (`ottoq_depot_tariffs`).
- **Energy (per kWh)** from `ottoq_tariff_windows`: six time-of-use windows created 2026-05-28 with no source,
  running from $0.052 (midnight-6 AM) to $0.235 (summer 5-7 PM "super peak").

NES's large commercial rates have no such spread. So OTTO-Q's battery planned against prices that do not exist, and any
"energy saved" figure would have been measured in them.

## 2. The published rates (NES, all "Effective October 2024", posted as the April 2025 documents on the NES rates page)

| Claim | Source |
|---|---|
| **TGSA Part 3** (time-of-use, contract demand over 1,000 kW): energy **5.667 c/kWh on-peak, 4.209 off-peak** in summer (Jun-Sep); **5.204 / 4.539** in winter (Dec-Mar); **4.672 flat** in transition (Apr, May, Oct, Nov). On-peak: weekdays **1-7 PM** April-October and **4-10 AM** November-March, excluding six federal holidays; weekends are off-peak. Demand: **$21.40/kW** for the first 1,000 kW and **$21.78** above (summer); **$20.34 / $20.73** otherwise. The billing demand is the highest 30-minute kW in the month, the same as GSA-3. Service charge **$934.50** and TVA grid access **$636.87** a month (over 150,000 kWh a month). | https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/tgsa.pdf (retrieved 2026-09-30) |
| **GSA Part 3** (the same size, flat energy): **4.785 c/kWh**, the same demand charges, a $2,091.71 fixed charge | https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/gsa-123.pdf (sourced 2026-07-09, in `ottoq_depot_tariffs`) |
| **EVC** (separately metered EV charging, 50-5,000 kW): **21.773 c/kWh at every hour, no demand charge**, $100 a month | https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/evc.pdf (retrieved 2026-09-30) |
| Each rate's energy charge moves with TVA's monthly **fuel cost adjustment**. NES lists **2.515 c/kWh for September** on its rates page (stated for residential; applied here to both commercial rates, labelled) | https://www.nespower.com/rates/ (retrieved 2026-09-30) |

**What the depot pays per kWh, fuel adjustment included (TGSA-3, summer):** 8.182 c on-peak, 6.724 c off-peak. On EVC
it pays 24.288 c at every hour and no demand charge.

## 3. What the twin will use, and why

- **OTTO-Q plans against TGSA-3 plus the fuel adjustment** (migration 0574). A depot with a battery and a planner is on
  a time-of-use rate: the rate's hours are what forward scheduling can use. The twin's reader
  (`twin.ottoq_sim_current_tariff`) takes the highest active window for the hour and season. It maps March to its
  "shoulder" (NES: winter) and does not read the weekday mask, so it prices weekend hours as weekdays. Every sweep
  day is a Tuesday in September, so neither affects a result, and both are noted in the migration.
- **Each test day is billed on the cheapest NES rate it qualifies for**: TGSA-3, GSA-3 or EVC. A plain depot with
  spiky fast charging may well be cheapest on EVC, which has no demand charge. A depot that flattens its peaks is
  cheapest on TGSA-3. Comparing each on its own best rate keeps the savings claim conservative.
- **Where the money is:** at $21.40 a kW-month, a 1,000 kW peak costs $21,400 a month before any energy is bought. A
  30-day month at 6.7-8.2 c/kWh buys ~290,000 kWh for the same money. Flattening the peak is the largest lever, and
  it is what the battery and the forward plan do. Rule 9 still holds: no charge ends early, and a car that must leave
  soon charges at full speed.

**Break-even between TGSA-3 and EVC:** monthly demand charges of $21.40 x P against an energy premium of 16.1 c/kWh
(24.288 - ~8.2) x E. They cross at E / P = 133 kWh per kW of peak a month, a **~18% load factor**. Below it EVC is
cheaper; above it TGSA-3 is. So the load factor, a standard utility measure, decides the rate. It is also the one
number that shows how much flattening the peak is worth.
