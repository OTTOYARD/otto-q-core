# R-8 — Market figures for the pitch deck (slide 4 and slide 14)

**Filed:** 2026-08-25 · **Answered:** 2026-08-25 · **Status:** final (sources verified 2026-08-25)

Deck guardrail honored throughout: one mono attribution line per figure, primary-first, and
`NOT FOUND` written where no defensible single number exists. Labels: **(a)** primary/official
(government lab, grid operator, regulator, OEM filing), **(b)** standards/academic, **(c)** trade
press/analyst, **(d)** inference. Stale figures are flagged for replacement rather than reused.

---

## Q1 — Data-center competition for the same megawatts (slide 4, stat 3)

### 1. US data-center load growth (the deck-ready number)

**4.4% of total U.S. electricity in 2023 → projected 6.7% to 12% by 2028.** That is the
LBNL/DOE figure and it is the cleanest, most-citable stat. In energy terms: **325–580 TWh/yr by
2030** (LBNL 2024 Report).

- Source: Lawrence Berkeley National Laboratory / U.S. DOE, "2024 United States Data Center Energy
  Usage Report" (Dec 2024) — https://eta.lbl.gov/publications/united-states-data-center-energy-2025 (a)
  (also the 2025 Update at the same URL).
- Corroborating range (wider, higher ceiling): EPRI puts data centers at **9–17% of U.S.
  electricity by 2030** (from ~4–5% today), with nominal capacity growing from **35–44 GW (2024) to
  56 / 96 / 132 GW (Low/Med/High) by 2030**. Source: EPRI "Powering Intelligence" load-growth
  analysis — https://powering-intelligence.epri.com/load-growth.html (a)
- The "tripled over the past decade, projected to double or triple by 2028" phrasing is from the
  DOE/LBNL release and is the strongest single-sentence deck hook. (a)

### 2. Interconnection-queue congestion tied to data centers

- **ERCOT Q1 2026: 198 GW of large load applied for interconnection, 86 GW under review — roughly
  equal to ERCOT's current peak load.** Source: Ascend Analytics, "Can US Interconnection Queues
  Survive Data Center-Driven Load Growth?" — https://www.ascendanalytics.com/blog/large-load-interconnection-queues-data-center-grid-access (c)
- **CenterPoint Energy (Texas): 700% increase in large-load interconnection requests, from 1 GW to
  8 GW, between late 2023 and late 2024.** Source: CenterPoint via Renewable Energy World —
  https://www.renewableenergyworld.com/energy-business/new-project-development/a-fundamental-shift-centerpoint-sees-700-increase-in-data-center-interconnection-request-queue/ (c)
- **Grid Strategies (2025): aggregated utility forecasts show ~90 GW of new data-center load by
  2030** — and their benchmark review suggests this may be **overstated by ~25 GW (40%)**, a useful
  honesty caveat for the deck. Source: Grid Strategies "National Load Growth Report 2025" —
  https://gridstrategiesllc.com/wp-content/uploads/Grid-Strategies-National-Load-Growth-Report-2025.pdf (a/c)

### 3. $/MW-month or $/kW premium signal

**NOT FOUND as a clean, citable single number.** The premium exists qualitatively (large loads now
committing to firm capacity, PJM creating Non-Capacity-Backed-Load + backstop procurement, ERCOT
SB6 curtailment obligations), but no primary source publishes a defensible "$/kW premium vs 2–3
years ago" figure I would put in front of an evaluator. Do **not** carry a specific $/kW premium
onto slide 4 without a named source; leave it as qualitative ("data centers are outbidding fleets
for firm capacity") or drop it. (d) — the absence is documented, not the number.

---

## Q2 — Interconnection queue duration, one clean citable number (slide 4, stat 1)

**There is no clean published median for *large-load* (customer) interconnection timelines.** What
exists is generator-queue data, and the request explicitly warns against misapplying it. The honest
answer:

- **Generator interconnection (the number that *does* exist): median >5 years from request to
  commercial operation (2025); median >3 years from request to interconnection agreement (2025).**
  Source: LBNL, "Queued Up" — https://emp.lbl.gov/queues (a). **This is a *generation* figure — do
  not use it for load without labeling it as generator-queue.**
- **Large-load / data-center interconnection: no single median published.** The defensible range is
  RMI's "several months to several years" (already in R-4) plus GridLab/Elevate's **5–10 years** for
  the transmission+generation buildout that a large load often triggers. Source: GridLab/Elevate via
  Camus.energy, "Why Does It Take So Long to Connect a Data Center to the Grid?" (July 2025) —
  https://www.camus.energy/blog/why-does-it-take-so-long-to-connect-a-data-center-to-the-grid (c)
- **Recommendation for the deck:** use "**5–10 years to energize a new large load**" (GridLab/Elevate)
  and attribute it, OR keep R-4's "several months to several years" — but do **not** put the LBNL
  "~5 years" generator median on a slide without the word "generator." A single undifferentiated
  "5-year interconnection" stat would be the exact mislabel the request guards against.

---

## Q3 — MW per site at fleet scale (slide 4, stat 2)

The 2–20 MW class claim is supported. Named figures:

- **Voltera (Waymo's charging-infrastructure partner) "typically builds sites of 5 MW or larger."**
  One disclosed site: **7.7 MW, growing to ~12 MW over time.** Source: Voltera via Renewable Energy
  World, "Home fleet home: an EV charging Q&A with Voltera" —
  https://www.renewableenergyworld.com/electric-vehicle/ev-charging/home-fleet-home-an-ev-charging-qa-with-voltera-power/ (c)
- **Robotaxi core depot (24 bays): 4–8 MW at peak.** Source: published operator estimates via
  Joule Labs / AV Fleet Tech —
  https://www.joulelabs.com/robotaxi-charging-infrastructure · https://avfleettech.com/av-fleet-charging-economics/ (c)
- Waymo's charging provider is Terawatt Infrastructure ($300M expansion financing, 2025) —
  https://www.evinfrastructurenews.com/ev-fleet-charging/waymo-charging-provider-300m-expansion-financing (c)

**Recommendation:** slide 4 stat 2 can read "**a single AV depot draws 4–8 MW; fleet-charging hubs
are built at 5 MW+ (Voltera/Waymo)**" with both attributions.

---

## Q4 — Modality sizing figures (slide 14)

One number per modality, sourced and dated. `NOT FOUND` where no defensible public figure exists.

| Modality | Figure | Source (date) | Label |
|---|---|---|---|
| **Robotaxi** | **~1,500 vehicles** in commercial service (Waymo, over SF/LA/Austin/Phoenix); third-party puts it at ~3,000 by March 2026 | Waymo blog "Scaling our fleet through U.S. manufacturing" (May 2025) — https://waymo.com/blog/2025/05/scaling-our-fleet-through-us-manufacturing · sqmagazine "Robotaxi Statistics 2026" | (a) / (c) |
| **AV freight** | **~30 trucks total, ~10 driverless** (Aurora); **~20 driverless** (Kodiak); Gatik = first driverless-at-scale (60,000 orders) | Fleet Rabbit "Autonomous Truck Fleet Management 2026" — https://fleetrabbit.com/blogs/post/autonomous-truck-fleet-management-2026 | (c) |
| **Last-mile delivery robots** | **2,000+ active robots** (Serve Robotics, largest US sidewalk fleet) / **2,700+** (Starship) | Serve Robotics press release (Dec 2025) — https://investors.serverobotics.com · Micromobility.io | (a) / (c) |
| **Commercial UAS deliveries/yr** | **>2.5M cumulative commercial deliveries, ~1M in the last 12 months, one delivery every ~30 s** (Zipline); PwC ~5M B2C drone deliveries worldwide (2024) | CNBC (July 2026) — https://www.cnbc.com/2026/07/14/zipline-drone-delivery-tesla-uber-waymo-executives.html · PwC | (a/c) |
| **Autonomous mining haulage** | **1,000+ Komatsu FrontRunner autonomous trucks commissioned** (April 2026); Caterpillar targeting 2,000+ by 2030; EACON (China) 2,000+; global >1,000 (2022) | Komatsu press (Apr 2026) — https://www.komatsu.com/en-us/newsroom/2026/komatsu-becomes-first-oem-to-commission-1000-ultra-class-autonomous-haul-trucks · IM-Mining | (a) / (c) |
| **Port/yard automation** | **~76 major container terminals fully/partially automated (~8.3% of terminals, 2025)**; Outrider (yard trucks) taking orders for 2026–27, no public fleet count | Port Economics Mgmt (2025) — https://porteconomicsmanagement.org/pemp/contents/part6/terminal-automation/ · Outrider press | (a/c) |
| **Defense unmanned systems** | **US Army ~7,000–10,000 small UAS platforms** (estimate; 7,362 RQ-11 Ravens figure is stale 2014) | militarydronepro.com · Wikipedia (US military UAVs) | (c) — **flag as soft** |

**Modality notes for the deck author:**

1. **Robotaxi** — use Waymo's own "over 1,500 vehicles" (primary) rather than the third-party
   ~3,000, unless you add a second attribution. The ~3,000 is a reasonable current estimate but is
   not Waymo-disclosed.
2. **AV freight** — the honest number is "tens of trucks, not hundreds." Aurora (30/10) + Kodiak
   (20) + Gatik. Do not imply hundreds of revenue-service autonomous trucks; that is not yet true.
3. **Commercial UAS** — Zipline dominates and its numbers are the most citable (2.5M cumulative,
   ~1M in last 12 mo). Wing and Matternet publish smaller/opaque figures; use Zipline as the anchor.
4. **Mining** — Komatsu's 1,000 (April 2026, primary) is the strongest single figure; the ~3,000+
   global total (adding Cat ~700 + EACON 2,000) is defensible but mixes primary and trade-press, so
   label it.
5. **Port/yard** — "~76 automated terminals" is the cleanest; note Outrider's yard-truck count is
   not public (capacity-constrained 2025, orders for 2026–27).
6. **Defense** — **the weakest cell.** The 7,000–10,000 small-UAS figure is a third-party estimate
   and the 7,362 RQ-11 figure is 2014-vintage. If slide 14 needs a defense number, flag it as an
   estimate or write NOT FOUND; do not present it as precise.

---

## Open items

1. **$/kW premium for large loads** (Q1.3) — no clean primary number; leave qualitative or drop.
2. **Large-load interconnection median** (Q2) — no single published median exists; the ~5-yr figure
   is generator-queue only and must be labeled if used.
3. **Defense fielded counts** (Q4) — no current primary figure; all public numbers are estimates or
   stale. Highest risk of a misattributed deck stat.
4. **Waymo current fleet** — "over 1,500" is primary but ~1 year old (May 2025); re-verify before a
   time-sensitive deck. Third-party ~3,000 (March 2026) is newer but not OEM-confirmed.
