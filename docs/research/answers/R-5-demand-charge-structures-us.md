# R-5 — Demand-charge structures beyond Nashville

**Answer date:** 2026-08-24
**Request:** docs/research/requests/R-5-demand-charge-structures-us.md
**Method:** utility tariff schedules (authoritative) > utility HTML tariff-summary pages > third-party databases (OpenEI / Nectar Climate), labelled per source. Every figure carries units + source URL. `NOT FOUND` where no defensible figure exists.

---

## Answers

### 1. How much do these structures vary? ($/kW/month for a 1–5 MW customer)

Demand-charge *level* spans roughly **$4.7/kW/mo (SRP) to ~$45/kW/mo (SCE TOU-8 combined)** — a ~10× spread — and the *shape* varies at least as much as the level.

| Metro | Utility / schedule | Demand charge (level, $/kW/mo) | Shape | Basis |
|---|---|---|---|---|
| Bay Area | PG&E E-19 (mandatory >499 kW) | Max-demand ≈ $24.75 + demand ≈ $14.79 (on-peak) | Two-part: monthly max-demand + demand; summer/winter max now equalized | 15-min |
| LA | SCE TOU-8 (mandatory >500 kW) | Facilities ≈ $24.7–26.1 + time-related on-peak ≈ $18.4–21.2 | Three-part: facilities + on-peak + winter mid-peak; voltage-tiered | 15-min |
| LA | LADWP A-2B (4.8 kV, >30 kW) | Facility $5.36 (12-mo) + High-Peak $10.00 / Low-Peak $3.75 (summer) | Facilities ratchet + TOU on-peak | 15-min |
| Phoenix | SRP E-36 General Service | Summer $4.73 · Summer-Peak (Jul/Aug) $7.13 · Winter $4.37 | Single seasonal demand + stretcher-block energy | 15-min (explicit) |
| Phoenix | APS E-35 Extra-Large TOU | On-Peak $19.795 · Off-Peak $2.979 | On/off-peak demand split | 15-min |
| Austin | Austin Energy Primary V1 (<3 MW) | $12.56 (+ $3.65/kW regulatory rider) | Single flat $/kW; no TOU demand; tiny energy + PSA rider | 15-min |
| Las Vegas | NV Energy LGS-2 (300–999 kW) | ~$2.68 facilities + TOU to ~$12.81 summer on-peak | Facilities + TOU demand; NEW 2025 daily $0.14/kW/day | 15-min |
| Miami | FPL GSLD-1 (500–1,999 kW) | $13.49 | Single flat $/kW + energy | 30-min |
| Atlanta | Georgia Power PLL-18 | $13.63 min-bill demand (energy-incl blocks); PLL-15 $11.15 | Demand baked into declining kWh blocks + min-demand; 95% summer ratchet | 30-min |
| Nashville | NES GSA-3 (already held) | $21.40 first 1,000 kW | Single $/kW + 30%/12-mo billing floor | 30-min NCP |

Sources: PG&E — CPUC filing https://docs.cpuc.ca.gov/PublishedDocs/Efile/G000/M496/K284/496284654.PDF (regulatory; tariff PDF authoritative) and https://www.pge.com/tariffs/en/rate-information/electric-rates.html · SCE — Schedule TOU-8 via https://www.sce.com/regulatory/tariff-books/rates-pricing-choices · LADWP — https://www.ladwp.com/account/customer-service/electric-rates/standard-commercial-industrial-rates · SRP — https://www.srpnet.com/price-plans/business-electric/general-service · APS — https://www.aps.com/…/e35_TimeOfUseExtraLarge.ashx · Austin — https://austinenergy.com/rates/commercial-rates · NV Energy — https://www.nvenergy.com/about-nvenergy/rates-regulatory/daily-demand · FPL — https://www.fpl.com/content/dam/fplgp/us/en/rates/pdf/bus-eff-may-2023.pdf · Georgia Power — https://www.georgiapower.com/content/dam/georgia-power/pdfs/business-pdfs/tariffs/2023/pll-15.pdf · NES — from `ottoq_depot_tariffs` (NES GSA-3 PDF).

**Shape differences that matter to a scheduler** (not just level):
- **Single flat $/kW** (Austin, SRP, FPL, Georgia Power) — only the billing-period max matters.
- **Facilities + time-related split** (SCE TOU-8) — the max and the *on-peak* max are billed separately, so on-peak excursions are penalised twice.
- **Facilities-ratchet + on-peak TOU** (LADWP) — a 12-month historical peak drives a permanent charge on top of on-peak.
- **On/off-peak split demand** (APS E-35, NV Energy LGS-2) — demand priced by when it occurs.
- **Energy-inclusive declining blocks with a demand floor** (Georgia Power) — there is no clean $/kWh; price depends on *hours-use of demand*.
- **Daily demand charge** (NV Energy, 2025) — a new per-day axis rather than per-month.

---

### 2. Which demand bases occur, and how common is each?

| Basis | Interval | Who uses it (observed) | How common |
|---|---|---|---|
| **NCP — non-coincident peak** | **15-min** | PG&E, SCE, LADWP, SRP, APS, Austin Energy, NV Energy | **Most common overall** — dominant in West/Southwest/Texas. CA IOUs are uniformly 15-min. |
| **NCP — non-coincident peak** | **30-min** | FPL, Georgia Power, NES | Strong **regional cluster in the Southeast** (FPL/TVA/Duke territory). |
| **Coincident peak (CP)** | varies | Appears in *transmission-level* riders (ERCOT 4CP, SCE TOU-8 sub-transmission coincident option) | **Rare for 1–5 MW distribution customers**; CP is a transmission cost-allocation concept, not the distribution demand basis. |
| **On-peak-only demand** | 15/30-min | SCE time-related, LADWP high-peak, APS E-35 on-peak, NV Energy TOU | **Very common, but almost always a *supplement*** to a max/facilities demand charge, not a stand-alone basis. |
| **Daily demand** | **15-min, per day** | NV Energy (2025, southern Nevada) | New and rare today; signals a direction. |

Precision that matters: **interval length is a hard regional split** — 15-min in the West/Southwest/Texas, 30-min in the Southeast (FPL, Georgia Power, NES). A scheduler hard-coding `NCP_30min` (Nashville's shape) will silently mis-model every California, Arizona, Texas and Nevada depot. Sources: FPL 30-min — https://www.fpl.com/blog/ask-the-expert/business/rates.html ("highest rate of usage during any 30-minute interval") · Georgia Power 30-min — https://www.georgiapower.com/business/billing-and-rates/business-rates.html · SRP 15-min — https://www.srpnet.com/price-plans/business-electric/general-service ("highest 15-minute demand during the billing cycle") · APS 15-min — https://www.aps.com/…/e32_Large.ashx ("averaged in a 15-minute period") · Austin 15-min — https://austinenergy.com/rates/commercial-rates (third-party confirmation: Nectar Climate) · NV Energy daily 15-min — https://www.nvenergy.com/about-nvenergy/rates-regulatory/daily-demand.

---

### 3. Ratchets — prevalence, percentages, look-back windows

- **Prevalence: common but not universal.** Observed ratchets/floors in this set: **Georgia Power** (95% summer / 60% winter — strongest seen), **LADWP** (Facilities Charge = "highest demand recorded in the last 12 months" — effectively a 100% / 12-mo floor), **Austin Energy** (summer billing-demand floor, tariff: "the June through September billed demand shall not [fall below a prior-summer fraction]"), **NES** (30% / 12-mo).
- **Typical percentage: 80–95%**, look-back **11–12 months**. Authoritative baseline — DOE/PNNL FEDS: "A typical demand ratchet uses **80%** of the peak demand occurring during the previous **11 months**" (https://feds.pnnl.gov/faq/what-demand-ratchet). Trade press corroborates up to ~90–95% (https://envigilance.com/blog/ratchet-clause/ ; https://tariform.com/blog/demand-charge-ratchets-explained).
- **Nashville's 30% / 12-mo is unusually lenient.** Most commercial tariffs ratchet at 80–95%; a 30% floor is at the very bottom of the observed range. The OTTO-Q model should expect ~2.7–3.2× the ratchet severity in Atlanta (95%) or on a LADWP facility charge than it currently sees in Nashville.
- Georgia Power ratchet source: https://www.georgiapower.com/content/dam/georgia-power/pdfs/business-pdfs/tariffs/2023/PLS-14.pdf ("Billing Demand shall be the greater of … 95% of the highest summer month") · LADWP source: https://www.ladwp.com/account/customer-service/electric-rates/standard-commercial-industrial-rates.

---

### 4. EV-specific schedules — how widespread are demand-charge-free EV tariffs?

**Widespread among the IOUs, but almost always with three caveats: separate meter, a time limit, and/or a subscription/capacity condition.**

| Utility | EV schedule | Demand charge? | Conditions / time limit | Source |
|---|---|---|---|---|
| NES (Nashville) | EVC | None | **Not flat** — $100/mo customer charge + On-Peak 23.279¢/kWh + Off-Peak tier. The "21.773¢ flat" in the request is the off-peak tier / prior vintage, not a flat rate. | https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2024/july/evc-july-2024-retail-rate-schedule.pdf |
| SCE | TOU-EV-7/8/9 | None (energy-only) | "Demand-charge holiday," time-limited (originally through 2024; trade press reports extension to ~2029). Separate EV meter. | NARUC https://pubs.naruc.org/pub/55C47758-1866-DAAC-99FB-FFA9E6574C2B ; trade press https://electricera.tech/resources/california-public-ev-charging-costs-demand-charges |
| SDG&E | EV-HP | None (subscription) | Fleet subscription; customer chooses kW capacity tier. | https://www.sdge.com/business/electric-vehicles/power-your-drive-for-fleets |
| PG&E | BEV-1 / BEV-2 | None (energy-only) | Separate EV meter required; monthly subscription/fee component. | https://www.pge.com/en/account/rate-plans/electric-vehicles.html |
| FPL | GSLD-1EV / GSD-1EV | Same $13.49/kW demand as GSLD-1 (not demand-charge-free) | EV variant of the standard schedule — **retains the demand charge**. | https://www.fpl.com/content/dam/fplgp/us/en/rates/pdf/bus-eff-may-2023.pdf |

Takeaways:
- Demand-charge-free EV rates exist at the three big CA IOUs (PG&E, SCE, SDG&E) and NES, but they are **introductory / time-limited** (SCE's explicit "holiday" with an expiry date) or **revenue-shifted** into a subscription fee (SDG&E EV-HP) or a higher per-kWh rate + customer charge (NES EVC).
- They are **not universally demand-charge-free** — FPL's EV variant keeps the demand charge.
- The common condition is a **separately metered EV service**; SDG&E adds a **capacity subscription tier**; none of the observed schedules imposes an explicit minimum **load-factor** requirement (NOT FOUND as a stated condition in any schedule reviewed).

---

### 5. Minimum portable tariff object field set

Designed around Q1–Q4, **not** around Nashville. Demand must be a *list* of priced components (because SCE has 2–3, LADWP has 3, APS has 2, Georgia Power has none but a demand floor), each carrying its own basis, interval and TOU window.

```
PortableTariff {
  // identity & applicability
  tariff_id, utility, schedule_code, effective_date, source_url, source_label,  // source_label: primary|regulatory|third-party
  customer_class, voltage_class, demand_min_kw, demand_max_kw,

  // fixed
  fixed_charge: { $/month, per: meter|delivery_point },

  // energy: a LIST of (season, tou_window, $/kWh) — covers flat, TOU, and blocks
  energy: [ { season: all|summer|winter, tou_window: all|on|mid|off|super_off,
              rate_per_kwh, // or: block: { first_kwh, per_kwh } for Georgia-Power-style
              block_hours_use: null } ],

  // demand: a LIST of components — the core of the object
  demand: [ {
      label,                       // e.g. "facilities", "time-related on-peak", "max demand"
      basis: NCP | CP | TOU,       // non-coincident | coincident | on-peak-only
      interval_min: 15 | 30 | 60 | daily,
      tou_window: all|on|mid|off|null,   // null when basis != TOU
      season: all|summer|winter|summer_peak,
      rate_per_kw,                 // $/kW per month (or per day if interval=daily)
      applies_over_kw: null|number // e.g. SRP "> 5 kW", NES "first 1,000 kW"
  } ],

  // ratchet / billing floor (nullable — absence = no ratchet)
  ratchet: { percent, lookback_months, basis_season: null|summer|winter } | null,

  // EV / demand-charge-free carve-out
  demand_charge_free: bool,
  demand_charge_free_expiry: date|null,   // SCE holiday end date
  separate_meter_required: bool,
  subscription_kw_tier: number|null,      // SDG&E EV-HP
  load_factor_condition: number|null,     // rarely stated; null = none

  // power factor (near-universal in large commercial)
  power_factor: { min_pct, charge_per_kvar } | null
}
```

Minimum fields that earn their keep across **all ten schedules** surveyed: `demand[]` (list, with `basis`/`interval_min`/`tou_window`/`season`/`rate_per_kw`), `energy[]` (list, seasonal+TOU), `fixed_charge`, `ratchet`, and `demand_charge_free` + `demand_charge_free_expiry`. The single field most likely to be *wrong* if omitted is **`interval_min`** (15 vs 30 changes the peak by ~half a charger's nameplate on a 30-min excursion) — it must be a first-class field, never a default.

## Open items

- PG&E E-19 and SCE TOU-8 exact current $/kW read from the tariff PDFs (524-blocked; values here are from a CPUC filing and the Schedule TOU-8 document respectively — flagged, tariff PDF authoritative).
- NV Energy LGS-2 $/kW is third-party (Nectar Climate); the LGS-2 tariff PDF should be read directly before the object is seeded with Las Vegas.
- Whether any EV schedule states an explicit load-factor condition: NOT FOUND — worth one targeted tariff read before finalizing the `load_factor_condition` field.
