# R-6 — Time-of-use window clock hours, and Georgia Power's hours-use energy blocks

**Filed:** 2026-08-24 · **Answered:** 2026-08-25 · **Status:** final (sources verified 2026-08-25)

All clock hours below are read **directly from each utility's own tariff PDF**, not third-party
databases. Where a figure could not be read from a primary source it is marked `NOT FOUND`. The
headline finding: **the APS E-35 on-peak window currently assumed in the repo (16:00–19:00) is
wrong — the tariff says 11:00 a.m.–9:00 p.m. weekdays.** That is a 10-hour on-peak window vs a
3-hour assumption, and it is exactly the kind of error R-6 exists to catch.

---

## Q1 — On-peak / off-peak clock hours per schedule

### APS E-35 — Extra Large General Service, Time-of-Use (Arizona)

| Window | Hours | Days | Seasonal? |
|---|---|---|---|
| On-Peak | **11:00 a.m. – 9:00 p.m.** | Monday–Friday | No (year-round) |
| Off-Peak | All remaining hours | — | — |

- **The repo's `16:00–19:00 weekdays` assumption is WRONG.** Primary source, verbatim: "On-Peak
  hours 11:00 a.m. - 9:00 p.m. Monday through Friday. Off-Peak hours: All remaining hours."
- No holiday exclusion appears in the tariff's TIME PERIODS section.
- Demand charge is split On-Peak ($19.795/kW) vs Off-Peak ($2.979/kW) at secondary voltage — a
  ~6.6× spread, so the window length matters enormously.
- Source: APS Rate Schedule E-35, A.C.C. No. 6166, Revision 19, effective 2024-03-08 (Decision
  No. 79293).
  https://www.aps.com/-/media/APS/APSCOM-PDFs/Utility/Regulatory-and-Legal/Regulatory-Plan-Details-Tariffs/Business/TOU-Business-NonRes-Plans/e35_TimeOfUseExtraLarge.ashx?la=en
- Time zone: Arizona = Mountain Standard Time year-round (no DST). `America/Phoenix`.

### SCE TOU-8 — Large Power (California)

Verbatim from the tariff's "Applicable rate time periods" table:

| TOU Period | Summer — Weekdays | Winter — Weekdays | Summer — Weekend/Holiday | Winter — Weekend/Holiday |
|---|---|---|---|---|
| On-Peak | **4 p.m. – 9 p.m.** | N/A | N/A | N/A |
| Mid-Peak | N/A | **4 p.m. – 9 p.m.** | 4 p.m. – 9 p.m. | 4 p.m. – 9 p.m. |
| Off-Peak | All other hours | 9 p.m. – 8 a.m. | All other hours | 9 p.m. – 8 a.m. |
| Super-Off-Peak | N/A | **8 a.m. – 4 p.m.** | N/A | 8 a.m. – 4 p.m. |

- **On-peak exists only in summer, and only weekdays.** In winter there is no on-peak; the evening
  window becomes *mid-peak*, and winter weekdays get a *super-off-peak* 8 a.m.–4 p.m. — the
  cheapest hours of the year.
- Demand charge is "Summer On-Peak and Winter Weekdays (4–9pm)" — i.e. the demand ratchet applies
  to the 4–9 pm weekday window in BOTH seasons even though winter 4–9 pm is *mid-peak* for energy.
- Source: SCE Schedule TOU-8 (combined TOU-8-RTP tariff PDF), "Applicable rate time periods."
  https://www.sce.com/sites/default/files/custom-files/ELECTRIC_SCHEDULES_TOU-8-RTP.pdf
- Time zone: `America/Los_Angeles` (PST/PDT). The tariff table is keyed to "HOUR ENDING @ PST."

### LADWP A-2B — Large Commercial & Multi-Family Service, 4.8 kV (Los Angeles)

| Period | Hours | Days | Hours/week |
|---|---|---|---|
| High Peak | **1:00 p.m. – 4:59 p.m.** | Monday–Friday | 20 |
| Low Peak | **10:00 a.m. – 12:59 p.m. + 5:00 p.m. – 7:59 p.m.** | Monday–Friday | 30 |
| Base | **8:00 p.m. – 9:59 a.m. + all day Sat & Sun** | — | 118 |

- Two seasons: High season (June–September) and Low season (October–May). The *clock hours do not
  change* between seasons; the *rates* change (high-peak demand charge $10.00/kW summer vs $4.75/kW
  winter).
- High-peak energy charge is summer $0.06322/kWh vs winter $0.05688/kWh — the window is the same;
  only the price level shifts.
- Source: LADWP "Commercial Electric Rates — How Time-of-Use Works" (the A-2B table on the
  Standard Commercial/Industrial Rates page confirms the same 3-period structure and the seasonal
  rate split).
  https://www.ladwp.com/account/understanding-your-rates/commercial-electric-rates
- Time zone: `America/Los_Angeles` (PST/PDT).

### NV Energy LGS-2 — Large General Service 2 (Southern Nevada)

| Period | Hours | Days | Seasonal? |
|---|---|---|---|
| On-Peak | **3:01 p.m. – 9:00 p.m.** | Daily (all 7 days) | Summer only (June–Sept) |
| Off-Peak | All other hours | — | — |
| Winter (Oct–May) | **All hours off-peak** | — | — |

- Verbatim: "Summer Period (June – September) On-Peak 3:01 p.m. – 9:00 p.m. Daily; Off-Peak All
  Other Hours. Winter Period (October – May) All Winter Hours [off-peak]."
- Note the on-peak window is **daily, not weekdays** — it includes weekends, unlike APS/SCE/LADWP.
- Time periods are "based upon Pacific Standard Time/Pacific Daylight Time."
- Demand is measured on a **15-minute** interval ("fifteen minute period of maximum use") — this is
  the daily demand charge R-5 flagged.
- Source: NV Energy Schedule LGS-2, Tariff No. 1-B, PUCN Sheet No. 15A, Special Condition 2
  (TOU Periods), effective 2024-01-01.
  https://www.nvenergy.com/publish/content/dam/nvenergy/brochures_arch/about-nvenergy/rates-regulatory/electric-schedules-south/LGS_2_South.pdf
- Time zone: `America/Los_Angeles` (Pacific; Nevada observes PDT).

### NES GSA-3 — General Power, >1,000 kW (Nashville)

- **GSA-3 has NO time-of-use window.** It is a flat demand + flat seasonal-energy schedule. The
  only on-peak/off-peak language anywhere in the GSA tariff is an operational note that seasonal
  customers "may arrange for seasonal testing of equipment during offpeak hours" — there is no TOU
  pricing.
- Structure: demand charge $21.40/kW (first 1,000 kW) / $21.78/kW (excess) in summer; $20.34 /
  $20.73 in winter and transition; energy charge ~4.785¢/kWh (first 150,000 kWh) / 3.883¢/kWh
  (additional), flat within each season. Billing demand floor = 30% of prior-12-month peak.
- Source: NES Schedule GSA (effective October 2024), https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/gsa-123.pdf
- Time zone: `America/Chicago` (Central).

### NES EVC — Electric Vehicle Charging Power Rate (Nashville)

| Season (billing months) | On-peak hours |
|---|---|
| Apr–Oct (summer shoulder) | **1 p.m. – 7 p.m.** |
| Nov–Mar (winter) | **4 a.m. – 10 a.m.** |

- On-peak applies **every day** EXCEPT Saturdays, Sundays, Nov 1, and six named federal holidays
  (New Year's Day, Memorial Day, Independence Day, Labor Day, Thanksgiving, Christmas) — those are
  all off-peak.
- **Energy rate is 21.773¢/kWh in BOTH on-peak and off-peak** — the EVC schedule has a TOU *clock*
  but no TOU *price differential*. This corrects R-5, which reported "23.279¢ on-peak" and implied
  an on/off-peak split. The real structure is: $100.00/mo customer charge + flat 21.773¢/kWh, with
  a demand ceiling of 50–5,000 kW and no separate demand charge. (The on-peak/off-peak clock exists
  in the tariff but prices the same, likely for future TVA adjustment differentiation.)
- Source: NES Schedule EVC (effective October 2024), https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/evc.pdf
- Time zone: `America/Chicago` (Central).

---

## Q2 — Georgia Power PLL-18 declining energy blocks

Read verbatim from the primary PLL-18 tariff (effective April 2025 billing month). This is the
**"Energy Charge Including Demand Charge"** — PLL-18 folds the demand charge into the declining
energy blocks rather than billing a separate per-kW demand charge on top.

### The block table (single table, no seasonal split on energy)

| Block boundary | $/kWh |
|---|---|
| First 3,000 kWh (within 200 hrs × billing demand) | **18.9430¢** |
| Next 7,000 kWh (within 200 hrs × demand) | **17.1794¢** |
| Next 190,000 kWh (within 200 hrs × demand) | **14.6526¢** |
| Over 200,000 kWh (within 200 hrs × demand) | **11.2968¢** |
| kWh in excess of 200 hrs and ≤ 400 hrs × billing demand | **1.9458¢** |
| kWh in excess of 400 hrs and ≤ 600 hrs × billing demand | **1.4671¢** |
| kWh in excess of 600 hrs × billing demand | **1.1010¢** |

*(Third-party Nectar figures cited in R-5 — "11.30–18.94¢/kWh" — are close but the primary tariff
is authoritative: 11.2968 / 14.6526 / 17.1794 / 18.9430¢ for the first-200-hours energy blocks.)*

### Seasonal?

- The **energy blocks are NOT seasonal** — one block table year-round.
- What IS seasonal is the **billing demand determination** (the ratchet): June–September billing
  demand = greatest of (current, 95% of prior summer peak, 60% of prior winter peak); October–May =
  greater of (95% of summer peak, 60% of winter peak). This is the 95%/60% ratchet R-5 reported.

### "Hours use of demand" — the tariff's own words

The tariff does not define "hours use of demand" as a standalone formula; it expresses the
boundaries directly as "200 hours times the billing demand", "400 hours times the billing demand",
"600 hours times the billing demand." The implied definition: **hours-use = kWh ÷ billing demand**
(in kW), i.e. the number of hours the billing-demand level would have to run to accumulate the
month's kWh. The declining blocks reward high load factor: a customer that runs more hours at the
same demand pushes kWh into the ~1–2¢ tail blocks.

### Minimum-bill demand ($13.63/kW) — additive, not a demand-charge-on-top

The minimum monthly bill is: **$256.00 basic service charge + $13.63 per kW of billing demand** +
excess kVAR + ECCR + DSM + fuel + franchise fee. So the $13.63/kW is a **minimum-bill floor**, not
an additional charge above the energy-including-demand blocks. It interacts with the blocks only as
a floor: the customer pays the greater of (a) the declining-block energy charge, or (b) the minimum
bill. In practice, a low-load-factor customer with high demand and little energy pays the floor.

- Basic service charge: $256.00/mo.
- Excess reactive demand: $0.42/kVAR (power factor below 95%).
- Source: Georgia Power Schedule PLL-18, effective with bills rendered for April 2025.
  https://www.georgiapower.com/content/dam/georgia-power/pdfs/business-pdfs/tariffs/2025/pll-18.pdf
- Time zone: `America/New_York` (Eastern). Billing demand on a **30-minute** interval.

---

## Q3 — Confirming NV Energy LGS-2 $/kW (R-5 flagged it as third-party)

**Confirmed and corrected from the primary Statement of Rates PDF.** R-5's "~$2.68 third-party"
figure (from Nectar Climate) is wrong; the actual LGS-2 demand charge is far higher.

LGS-2, Secondary Distribution Voltage (the common 300–999 kW class):

| Charge | Rate |
|---|---|
| Basic Service Charge | $122.40/mo |
| Demand — Summer On-Peak | **$13.43/kW** |
| Demand — All Winter Hours | **$1.65/kW** |
| Facilities Charge | $3.45/kW |
| Consumption — Summer On-Peak | 12.932¢/kWh |
| Consumption — Summer Off-Peak | 5.754¢/kWh |
| Consumption — All Winter Hours | 6.922¢/kWh |

Other LGS-2 voltage tiers (for completeness): Primary Distribution — demand $12.93/kW summer
on-peak / $1.25 winter, basic $207.70/mo, facilities $3.40/kW. Transmission — demand $14.54/kW
summer on-peak / $1.15 winter, basic $182.00/mo, facilities per-dollar-of-investment basis.

- The demand charge is **seasonally split** (summer on-peak vs winter), consistent with the TOU
  window in Q1, and is the **daily** 15-minute demand charge R-5 noted — a shape the portable
  tariff object supports but had not been exercised against. Las Vegas can now be seeded from these
  primary figures.
- Source: NV Energy Statement of Rates (southern), PUCN Sheet No. 10B, Schedule LGS-2.
  https://www.nvenergy.com/publish/content/dam/nvenergy/brochures_arch/about-nvenergy/rates-regulatory/electric-schedules-south/StatementofRates.pdf

---

## Open items

1. **APS E-35 holiday exclusions** — the E-35 tariff PDF's TIME PERIODS section names no holidays;
   whether APS applies a holiday exception elsewhere in the schedule is `NOT FOUND` from the pages
   read. Assume no holiday exclusion until a fuller tariff read confirms otherwise.
2. **Georgia Power PLL-18 tail-block split** — the 400–600 hrs block is 1.4671¢ and the >600 hrs
   block is 1.1010¢ (two distinct blocks); the PDF layout made the boundary slightly ambiguous in
   one spot. Re-verify the exact 400/600-hour boundary text before hard-coding (block values
   themselves are unambiguous).
3. **SCE TOU-8 summer weekday "on-peak" vs "mid-peak"** — the tariff table shows on-peak summer
   weekdays 4–9 pm and mid-peak N/A for summer; note the SCE "time-related demand" charge labels
   the winter weekday 4–9 pm window as the demand-bearing window despite it being *mid-peak* for
   energy. This subtlety (energy on-peak vs demand-on-peak windows diverging in winter) is worth a
   model-level flag.
