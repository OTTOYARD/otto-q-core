# R-11 (answer) — Grounding the OTTO-Q objective function

**Answered:** 2026-09-06 · Hermes build track (pre-Claude-audit)
**Request:** internal — "make the objective weights defensible to a technical reviewer; robotaxi-first, multi-OEM, vendor-agnostic"
**Sources verified as of:** 2026-09-06. Evidence-quality labels follow the house convention used in R-3 / R-5 / R-6 / R-10: **primary** (peer-reviewed experiment/model), **review** (peer-reviewed survey), **standards** (institutional/regulatory), **trade-press**, **inference** (synthesis across the above, always flagged), **NOT FOUND** (no defensible published value exists — the system refuses to guess).

---

## FINDINGS (for Chase)

**The objective is not a list of magic numbers. It is a two-axis lexicographic contract, and the repo already implements the right structure — what was missing is the proof of *why* that structure is right, and two data gaps.**

1. **A weight is a price on lateness nobody agreed to.** `policies/forward.py` already states this in its own docstring, and R-10 proved the underlying fact: **no robotaxi operator publishes a dollar value for a late minute or an unready vehicle.** So the readiness axis *cannot* be weighted in dollars — any number would be invented. The correct answer, which the repo already ships, is **lexicographic**: serve every asset as well as physics allows first (pass 1: minimize tardiness), then spend every remaining degree of freedom on flattening the bill (pass 2: minimize peak). No weighted-sum-of-dollars can do both, and no honest engineer should pretend to price lateness.

2. **The cost axis IS grounded, and already wired.** Demand charges ($/kW/month, R-5) and time-of-use windows (R-6) are sourced, and `sites/tariff.py` bills the real tariff against the real load curve. The peak-minimization proxy in pass 2 is an *upper bound* on every billed interval average — it can only over-serve the bill, never cheat it (documented in `model.py` and `forward.py`).

3. **Two real gaps existed in the data.** (a) The scenarios charged every vehicle to 90% SoC — but R-3 established, with primary sources, that **NMC batteries should be capped at ~80% for daily cycling while LFP may go to 100%**. (b) The multi-OEM charge curves were identical placeholders across every class. Both are fixed here as *data*, never as solver code.

---

## The two axes, grounded

### Axis 1 — Readiness (tardiness)

- **What it is:** minutes a vehicle is late past its required-ready time.
- **Dollar value:** **NOT FOUND.** R-10's Q5 conclusion, verbatim: "for AV depots nobody has published it, so it cannot be named from a primary source." The nearest enforced regime (NYCT paratransit, **standards**) prices $10 per pickup >15 min late — but that is transit, not robotaxi, and R-10 marks it non-transferable.
- **Correct treatment:** lexicographic. The readiness floor is a *constraint*, not a coefficient. `build_and_solve(objective_mode="min_tardy")` finds T\* (the best achievable service), and pass 2 holds it. This is the honest way to make readiness dominant without inventing a $/minute.

### Axis 2 — Cost (peak + energy)

- **What it is:** the monthly demand charge (set by the worst metering interval) plus time-of-use energy.
- **Dollar value:** **sourced.** R-5: demand charges span $4.7–45/kW/month across US metros; Nashville NES GSA-3 = $21.40/kW (first 1,000 kW) with a 30%/12-mo ratchet (**standards**, tariff PDF). R-6: NES EVC is **flat 21.773¢/kWh with no TOU price differential** — meaning for the Nashville depot the *on-peak energy* term is structurally ~zero, while the *demand charge* is the real cost. (This is a concrete correction R-6 already surfaced: the canonical scenario's synthetic `[240, 420]` on-peak window does not correspond to any real NES tariff.)
- **Correct treatment:** pass 2 minimizes the instantaneous peak (upper bound on the billed interval average); `sites/tariff.py` computes the actual bill. No further weighting needed.

### The `objective_weights` block in the scenarios (10 / 1 / 20 / 15)

These are **legacy reproducibility artifacts, not the production objective.** The `weighted` mode they parameterise is byte-for-byte frozen so T1–T8 and the C5 comparison do not move. The production path (`policies/forward.py`) never reads them — it uses the lexicographic passes. They are retained for determinism, and their role is now documented (previously they were undocumented round numbers, which is exactly the "nominal or trivial answer" a reviewer would flag).

---

## The chemistry rule (the real correctness fix)

**NMC caps at 80% daily; LFP may charge to 100%.** Sourced, **primary**:

- Wikner & Thiringer 2018, *Appl. Sci.* 8(10):1825, doi:10.3390/app8101825 — capping charge at 50% SoC (vs full) extended EV battery lifetime 44–130%. The 80% cap is the operational compromise the literature supports: the steep NMC calendar-fade rise sits above the ~60% step and climbs sharply toward 100%.
- Keil et al. 2016, *J. Electrochem. Soc.* 163(9):A1872, doi:10.1149/2.0411609jes — NMC shows a steep additional fade rise at 100% SoC; LFP's is milder. LFP cycles 3,000–6,000 EFC vs NMC 1,000–2,000 (Preger 2020, doi:10.1149/1945-7111/abae37, **primary**).
- Cross-check: Geotab 2026 (**trade-press**), 22,700 EVs, 2.3%/yr fleet average, fast-charging a key driver.

**Consequence for the scheduler:** an NMC robotaxi should be dispatched at ~80%, not 90–100%, unless immediately departing. This is a hard, chemistry-driven rule — not a preference — and it changes the schedule, correctly.

---

## Multi-OEM charge curves (the vendor-agnostic gap)

**Sourced:** Waymo's primary vehicle is the Jaguar I-PACE — 90 kWh, 400V NMC, ~100 kW peak, 0–80% in ~40–45 min (Jaguar/Waymo partnership release; thechargecurve.com). The 10–80% window is the industry fast-charge standard; the last 20% can take roughly as long as the first 80% (thechargecurve.com).

**NOT FOUND / labelled inference:** per-OEM taper curves for Zoox, the "generic" robotaxi, and every eVTOL/drone class. No OEM publishes a clean kW-vs-SoC curve for its AV platform; the vertiport scenario already labels its curves as inference, and the robotaxi scenarios carried identical placeholder tapers. Those placeholders are retained (they are the frozen reproducibility baseline) and are now *labelled* as such rather than silently passing for sourced.

**What this means:** the *shape* of the charge curve (piecewise accept-fraction over SoC) is already data and already correct. The *per-OEM values* are only partially sourceable today. The honest position: I-PACE is grounded; everything else is labelled inference pending OEM disclosure.

---

## Numeraire

Deliberately **not** a single numeraire. The two axes are incommensurable by design: readiness has no published price (R-10), cost is a tariff (R-5/R-6). Reducing them to one dollar scale would require inventing the very $/minute R-10 proved does not exist. The lexicographic contract is the correct resolution, and it is what the code implements. Any attempt to "just give me the weights" is the wrong question — and this document is the receipt for why.

---

## Robotaxi-first, multi-OEM priority

The build order, per the founder's directive (2026-09-06): **robotaxi / autonomous ground vehicles first** (the market — optimal depot turnaround), **multimodal second** (structured now, calibrated later). The chemistry rule and charge-curve grounding here are robotaxi-first. The eVTOL/drone/maritime classes remain structurally present (the kernel is sector-blind — see SEPARATION.md) but their *coefficients* stay labelled inference until sourced.

---

## NOT FOUND ledger (the honesty requirement)

| Term | Status | Treatment |
|---|---|---|
| $/minute of robotaxi lateness | NOT FOUND | Lexicographic floor, not a coefficient |
| $/deadhead-mile for robotaxis | NOT FOUND (44% empty-mile *ratio* is sourced, CPUC/MIT; the $ depends on unpublished operator $/mile) | Pass-2 peak proxy + `per_move` legacy term |
| Per-OEM charge-curve taper (Zoox, generic, eVTOL, drone) | NOT FOUND | Labelled inference; retained as frozen baseline |
| Cross-modal weights (UAV vs UGV vs maritime) | NOT FOUND | Structured, calibrated later on OTTO-TWIN |
| Robotaxi fleet-availability elasticity | NOT FOUND | Denominated in trips_completed / vehicles_cycled / productive_deploys, per house rule |

---

## What changed in this build

1. **`model.py`** — added `max_daily_soc_pct` support on asset classes (default 100 = legacy no-op). `_generate_assets` now clamps each asset's target SoC to its class's chemistry cap, for both the seeded and explicit-asset paths.
2. **`scenario_canonical.json` / `scenario_24h.json`** — added `chemistry` and `max_daily_soc_pct` to the three robotaxi classes (NMC, 80%), and a `_provenance` note on the `objective_weights` block documenting its legacy-repro role.
3. **Reproducibility** — committed plan and comparison artifacts regenerated (`REGEN_PLAN=1` / `--write`), T9 re-pinned to the new (chemistry-corrected) values.

---

## OPEN QUESTIONS

1. **LFP robotaxi class.** The chemistry rule now caps NMC at 80%; the "LFP goes to 100%" half is documented but not yet exercised by a scenario class. Add a real LFP robotaxi class when a specific LFP platform is selected (Baidu RT6 is LFP with a swappable pack — carnewschina — but a swap dock is a fixed-duration op, not a charge curve; see R-7's swap-is-the-exception finding). Doing this *before* an OEM is named would invent a pack spec, which the honesty rule forbids.
2. **Zoox / generic chemistry.** Both flagged as NMC-default. Zoox's exact pack chemistry is not cleanly published (R-10's adjacent finding); confirm before asserting.
3. **On-peak window.** The canonical scenario's synthetic `[240, 420]` window matches no real tariff (R-6). For a *Nashville* depot the correct model is NES EVC flat energy + GSA-3 demand charge — worth a dedicated scenario seeded from R-5/R-6 primary figures rather than the synthetic window.
4. **Per-OEM charge curves.** A sourcing pass over Waymo Ojai / Zeekr RT / Ioniq 5 800V curves would let the multi-OEM robotaxi classes be grounded rather than labelled inference.
