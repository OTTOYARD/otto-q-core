# R-4 — Grid oversubscription ratio: installed charger kW vs service kW, binding limit, interconnection cost/lead time, battery-buffered case study

**Filed:** 2026-08-23 · **Answered:** 2026-08-24 · **Status:** final (sources verified 2026-08-24)

## Answers

### 1. The headline ratio (installed charger nameplate kW ÷ utility service kW)

No primary source publishes a per-sector ratio table; the defensible answer is a range assembled from operating data points. Central tendency: **service is sized at ~30–50% of the sum of charger nameplate, i.e. an oversubscription ratio of ~2:1 to ~3.4:1**, with a wider band of **~1.4:1 to ~7:1** (the ~7:1 extreme is battery-buffered).

Data points (units + source each):
- **Transit bus, US, 97-bus fleet (unnamed site):** unmanaged peak **4.7 MW** cut to **1.4 MW** daily max under smart charging, so the site used its existing connection — oversubscription **≈3.4:1** (4.7 ÷ 1.4 MW). Source: The Mobility House, "Mobility meets energy" (Dec 2021), https://www.mobilityhouse.com/usa_en/knowledge-center/article/mobility-meets-energy
- **Transit bus (general claim, same source):** energy management "reduces the necessary maximum connected load by **30 to 80 percent**" → service = 20–70% of nameplate, ratio **≈1.4:1 to 5:1**.
- **Truck/last-mile depot (vendor design example):** "install 10 DC chargers with 200 kW each" (2.0 MW nameplate); load management "reduce[s] required capacity by 50%" → ~1 MW service, ratio **2:1**. Source: Ampcontrol (Dec 2023), https://www.ampcontrol.io/post/planning-ev-fleet-charging-how-to-overcome-grid-constraints-when-installing-electric-truck-depots
- **Battery-buffered DCFC (retail, extreme):** FreeWire Boost Charger delivers **200 kW DC from a ≤27 kW AC input** (≈7.4:1). Source: InsideEVs (2022), https://insideevs.com/news/585263/freewire-boost-charger-200-flexible/

**Per-sector split (transit / last-mile / robotaxi / drayage / municipal): NOT FOUND** — no NREL/ICCT/CALSTART table breaks out installed-kW÷service-kW by those sectors. Closest machine-usable rule is the design simultaneity factor, e.g. "Fleet size × charger power × simultaneity factor," with **0.7** cited (50 buses × 50 kW × 0.7 = 1.75 MW). Source (vendor rule-of-thumb): https://buscmms.com/blog/electric-bus-charging-depot-planning-fleet-operators

### 2. Is oversubscription deliberate?

**Yes — deliberate and standard for multi-charger depots, but only when paired with certified load management.** Without active load management, the utility sizes for simultaneous full load, making oversubscription uneconomic or refused.

- Load management is itself safety-certified: Ampcontrol cites **UL 60730-1** as the basis on which operators may "oversubscribe breakers, transformers, and beyond." https://www.ampcontrol.io/post/planning-ev-fleet-charging-how-to-overcome-grid-constraints-when-installing-electric-truck-depots
- EPRI notes utilities may size on "the assumption that all vehicles are charging at the same time" — i.e. the default is **no** oversubscription unless load management is demonstrated. EPRI, "Interim Service Solutions and Timely Grid Connections," https://restservice.epri.com/publicdownload/000000003002030647/0/Product
- Design norm stated in trade press: "Depot power is sized from the aggregate charging load adjusted by a diversity factor, not from the sum of every charger's nameplate rating." https://prismecs.com/blog/driving-towards-sustainability-the-rise-of-electric-vehicles

Constraint that governs it: the utility interconnection/service agreement, plus the continuous-load code rule (chargers treated as continuous loads, branch circuit sized at 125%, **NEC 625.42**). Oversubscription is the **exception** under no load management and **standard practice** under certified load management.

### 3. What is the binding limit in practice?

**It is the utility service entrance / service transformer (utility-side), not the customer panel.** A single "site power cap" is the right first-order abstraction, but it really means *utility service capacity*, and for DCFC-heavy depots a second limit — the dedicated switchgear — sits just downstream.

- "Panel capacity and utility service capacity are distinct constraints. Available breaker slots do not guarantee that the utility service entrance, utility transformer, or distribution feeder has sufficient capacity." Source: National EV Charging Authority (code/design reference), https://nationalevchargingauthority.com/commercial-ev-charging-electrical-infrastructure/
- "DCFC units above 100 kW typically require dedicated switchgear, … and often a step-down transformer from utility medium voltage." (same source)
- "DC fast charging systems often require dedicated transformers, high-capacity switchgear, and upgraded utility connections." https://cyberswitching.com/electrical-requirements-for-level-2-and-dc-fast-charging/
- EPRI flags transformer-level headroom as the binding quantity: "transformers or other equipment could have less available capacity" than the headline service figure. https://restservice.epri.com/publicdownload/000000003002030647/0/Product

Modeling note: if OTTO-Q models one scalar "site power cap," it should be understood as **utility service/transformer rating**; a faithful two-level model adds the transformer thermal limit and (for >100 kW DCFC) switchgear rating. The panel is rarely binding because it is sized to match the service.

### 4. Load-management prevalence and the savings attributed to it

**Prevalence (a hard percentage): NOT FOUND** from a primary source. What is defensible: active load management is now the default for multi-charger depots — OCPP (Open Charge Point Protocol) smart charging is the de-facto mechanism, the DOE FEMP program *requires* smart charge management for federal fleets (https://www.energy.gov/cmei/femp/smart-charge-management-implementation-federal-fleets), and UL 60730-1 certifies the hardware (see Q2).

**Quantified savings (the higher-value number):**
- **$54,326/month** electricity-cost reduction ($651,912/yr; **$3.2M over 5 years**) from load management that dropped a 97-bus transit depot from 4.7 MW to 1.4 MW and avoided a grid upgrade. Source: The Mobility House, https://www.mobilityhouse.com/usa_en/knowledge-center/article/mobility-meets-energy
- Demand-charge reduction **$28.15 → $15.11 per kW/month** (~46%) via granular charger control. Source: Terawatt, https://www.terawattinfrastructure.com/blog/how-ev-fleet-operators-can-turn-energy-costs-into-an-advantage
- Vendor ranges (weaker, for triangulation only): "35–55%" electricity-cost cut, "$18k–$64k/yr per depot" (jointcharging.com); "20–30%" (equipmake.com).

The 30–80% connection-size reduction in Q1 is itself the strongest prevalence-adjacent figure: sites that adopt load management can — and routinely do — install 2–5× nameplate capacity relative to their service.

### 5. Interconnection upgrade cost and lead time (~1 MW, US metro)

**Lead time.** RMI's large-load interconnection guidance: the full process runs **"from several months to several years"** from initial request to energization. Source: RMI, "Understanding Large Load Interconnection," https://rmi.org/resources/understanding-large-load-interconnection/ . Supporting ranges: commercial 25 kW–5 MW interconnection **1–3 years** (queue-dependent; https://solarinfopath.com/interconnection-delays-causes-timelines/); approval alone **6–12+ months** for >1 MW (https://ea-global.us/navigating-utility-interconnection-for-commercial-solar-projects/); The Mobility House states grid-connection expansion "can easily take several years" (source in Q1).

**Cost.** ICCT / Black & Veatch (Oct 2025) put **front-of-the-meter (utility-side) costs at $2.5M–$2.9M** for US medium/heavy-duty truck charging facilities, "at most 31.2% of the total project budget" (totals: small $7.9M, medium $15.4M, large $15M). Source: ICCT, https://theicct.org/publication/the-cost-of-energizing-medium-and-heavy-duty-truck-charging-facilities-in-the-us-oct25/ . A contrasting lower bound from UCLA (Wang et al. 2023): utility-service upgrade cost **$17,500 per DCFC station** "regardless of charger rating levels." https://escholarship.org/content/qt1p49662g/qt1p49662g.pdf

**A defensible $/kW figure for exactly 1 MW: NOT FOUND** — the ICCT facilities are multi-MW truck depots (facility MW not stated on the page) and the $17.5k/station figure is small-site. The honest read for the battery-buffered thesis: a ~1 MW service/transformer upgrade in a US metro is plausibly **hundreds of thousands to low millions of dollars and 6–24+ months** — slow and expensive enough that storage commonly competes, but the exact 1 MW number is not published.

### 6. Battery-buffered charging in the field (the case study)

**Primary case study — Zenobē / National Express, Yardley Wood bus depot, Birmingham (UK).**
- **Site/problem:** National Express needed to charge **19 electric double-decker buses** at Yardley Wood Garage; **grid import capacity was restricted**, limiting how many buses could charge, and space was tight.
- **Sizing:** a **667 kWh battery energy storage system (BESS)** plus smart charging, occupying ~two car-parking spaces. BESS kW rating: **NOT FOUND** (page states kWh only).
- **Cost:** **NOT FOUND** — Zenobē financed it via OPEX ("grid upgrades being extremely expensive" is the stated motive; Zenobē financed the 19 bus batteries + charging infrastructure and removed battery-technology risk).
- **Did it work:** yes — it "overcame restricted grid capacity," charges the fleet overnight while the battery earns grid-services revenue by day, and became "a blueprint for National Express's other depots."
- Source: Zenobē, "National Express Yardley Wood," https://www.zenobe.com/case-studies/national-express-yardley-wood/

**Corroborating named sites (retail/fast-charging, not depot):**
- **FreeWire Boost Charger** at the **Phillips 66 flagship station near its Houston headquarters** (first US deployment, 2022): **160 kWh** integrated battery, up to **200 kW** output from a **≤27 kW AC** input — no utility upgrade. Sources: https://www.phillips66.com/newsroom/ultrafast-ev-charging-debuts-at-phillips-66-flagship-station/ ; https://insideevs.com/news/585263/freewire-boost-charger-200-flexible/
- **ADS-TEC ChargeBox** (deployed e.g. to fuel retailer Q8, 2025; a Ford dealer): **140 kWh** buffer, up to **320 kW** output, connects to existing 480 V grid "without a transformer station or grid upgrades." https://www.ads-tec-energy.com/us/ ; https://www.businesswire.com/news/home/20250401932726/en/

**Sizing datapoint (academic, not a field site):** for a city fast-charging station on a **150 kW** grid connection, a **50 kW / 125 kWh Li-ion** battery was sized to serve 100 kW charge points. https://www.sciencedirect.com/science/article/pii/S235214652030452X/pdf

## Open items

- Per-sector installed-kW÷service-kW table from a primary source (NREL/ICCT/CALSTART) — the single most valuable gap; likely requires synthesizing fleet-specific NREL data reports rather than a ready table.
- Exact 1 MW service-upgrade $/kW and calendar time in a specific US metro (utility tariff/service-study level data).
- Yardley Wood BESS kW rating and capital cost (Zenobē does not publish; would need a direct request or a UK trade-press figure).
- Load-management adoption rate as a hard percentage.
