# Data integrations for the twin: what would add depth, and what would not

**Date:** 2026-10-06 CT (searches 2026-10-07 02:30–03:20 UTC). **By:** Claude Code (build track), by direct search
under CLAUDE.md rule 3. No research agents were used. Every external claim carries its URL and the date or
version it applies to. **Asked by Chase, 2026-10-06:** *"make sure we're not missing any data integrations that would
make our twin world more in depth, especially from the autonomous asset or vehicle perspective ... world training
models ... Wayve, Tensor, Motional, Nuro, NVIDIA ... If not, that's fine, I don't want wasteful excess."*

## The answer in short

1. **World models: do not integrate one now.** They generate camera and lidar scenes to train and test a car's
   driving. The twin models the depot (arrivals, stalls, chargers, bays, power), not pixels, and OTTO-Q decides
   recall, stall, service order and power, not steering. None of them would change a decision OTTO-Q makes.
   One is worth parking for later (NVIDIA Cosmos Reason, §1).
2. **Two public robotaxi sources are worth adding,** because they replace proxies the twin uses today:
   - **CPUC quarterly AV reports** give real robotaxi duty cycles (§2A).
   - **The Waymo safety-hub CSVs with NHTSA's crash reports** give real robotaxi incident rates, including in
     parking lots (§2B).
3. **One calibration to question before any new data:** the twin's charger faults come from public-network studies,
   not from a fleet-run depot (§2C). It is a lever on the 40% of fleet time cars spent waiting on run fd6ed035.
4. **Five rows in `external_factor_sources` describe feeds that do not run** (§3). Two point at an API that was not
   found to exist.
5. **Built from data already in the database:** the KPI board now prices the monthly demand charge on the depot's
   own NES tariff (otto-q-core migration 0611). On run fd6ed035 it is $12,989 a month, 56 times the run's energy bill.

## 1. World models and AV datasets

| Company | What it offers (date) | Can we get it? | Does it help OTTO-Q? |
|---|---|---|---|
| **Wayve** | GAIA-3: a 15B-parameter generative world model for driving validation, announced 2025-12-03 ([AV International](https://www.autonomousvehicleinternational.com/news/ai-sensor-fusion/wayves-gaia-3-generative-world-model-now-available-for-autonomous-driving-validation.html)). | No public API or licence was found. The announcement does not say who can use it. | No. It renders driving scenes. |
| **NVIDIA** | Cosmos world models (Predict, Transfer, Reason). [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/) (2025-10-24): commercial use allowed, NVIDIA claims no ownership of outputs, the licence ends if a guardrail is bypassed. Cosmos Reason 2 (8B VLM, "ready for commercial use") is a NIM on [build.nvidia.com](https://build.nvidia.com/nvidia/cosmos-reason2-8b/modelcard). | Yes. We already hold an NVIDIA API key (Nemotron, cuOpt). | **Not now.** Later, Cosmos Reason could read a cabin or stall camera image and name the service it needs (tidy, deep clean, item left). That needs real camera frames, which no depot sends yet. Park it with the Isaac track (CLAUDE.md 2.8). |
| **Tensor** | A personal L4 "Robocar" with an in-car VLM; deliveries planned for H2 2026 ([press release, 2026-03-23](https://digital-release.wowktv.com/business/press-releases/cision/20260323SF15917/tensor-debuts-worlds-first-personal-level-4-robocar-in-the-uk-at-the-european-av-summit)). | No world model or dataset is offered. | No. But Tensor reports to the CPUC pilot program (§2A). |
| **Motional** | nuScenes and nuPlan: free for academic use, commercial use needs a licence ([Motional](https://motional.com/nuscenes); [AWS Open Data registry, nuPlan](https://registry.opendata.aws/motional-nuplan/)). | Only with a commercial licence. | No. They describe on-road perception and planning. |
| **Nuro** | Licenses the Nuro Driver since September 2024. Lucid Gravity robotaxis with Uber from 2026 ([Nuro blog](https://www.nuro.ai/blog/one-model-all-roads-zero-shot-autonomy-in-tokyo); [Sacra](https://sacra.com/chat/h/4c627d27-0a2e-4083-bdf9-6239a8b007df/)). | No public dataset was found. | No. But Nuro reports to the CPUC pilot program (§2A). |

**Why the answer is no, in one sentence:** a world model predicts what the car's sensors see next, and nothing in
OTTO-Q's decision reads a sensor frame. The swap test (`ottoyarddepot-sim/AGENTS.md`) also argues against it: real
depot telemetry will be states and events, so a twin fed by generated video would test a path production never takes.

## 2. What would add depth, ranked by edge per hour

### A. CPUC quarterly AV reports: real robotaxi duty cycles (rank 1)

- **What:** California's AV passenger-service reports, posted as spreadsheets with labelled columns. The latest
  period is **2026-04-01 to 2026-06-30**. Waymo reports in the deployment program; **Nuro, Tensor, Waymo, WeRide and
  Zoox** report in the pilot program. The page was last updated 2026-08-18
  ([CPUC quarterly reporting](https://www.cpuc.ca.gov/regulatory-services/licensing/transportation-licensing-and-analysis-branch/autonomous-vehicle-programs/quarterly-reporting)).
- **Fields that matter to a depot** (quoted from the page): miles in passenger service; miles served by electric
  vehicles; miles from accepting a trip to the pickup point (empty miles); *"amount of time each vehicle waits between
  ending one passenger trip and initiating the next"* (daily average and monthly total); and, for deployment,
  *"stoppage events, i.e. situations where AVs have stopped and are not moving when they should be."*
- **What it replaces:** the twin's arrival and duty-cycle priors are `nyc_tlc` (human-driven yellow taxis, June 2024)
  and `nrel_fleet` (generic commercial fleets, *"encoded from NREL Fleet DNA published aggregate statistics"*, mean
  120 miles a day). Neither is a robotaxi.
- **The edge:** real robotaxi miles, empty miles and idle time decide when a car comes home and how empty it is.
  Stoppage events give a real rate for unplanned returns and for KPI 4 (touch events per turn).
- **How:** a quarterly file ingest into `ottoq_calibration_datasets` / `_distributions`, the same path as `nyc_tlc`.
- **Limits:** the data is per operator and per quarter, not per car-day, and it is California, not Nashville. Read the
  real columns before designing the fit.

### B. Waymo safety hub + NHTSA crash reports: real incident rates, parking lots included (rank 2)

- **Waymo:** 271.3M rider-only miles through June 2026, with four CSV downloads: rider-only miles by location, crashes
  with their NHTSA report IDs, collision counts against benchmarks, and the geographic split
  ([Waymo Safety Impact](https://waymo.com/safety/impact/), read 2026-10-07).
- **NHTSA Standing General Order:** CSV downloads, data dictionary dated **2026-09-15**, covering reports received
  through **2026-08-17** ([NHTSA SGO](https://www.nhtsa.gov/SGOCrashReporting);
  [data dictionary](https://static.nhtsa.gov/odi/ffdd/sgo-2021-01/SGO-2021-01_Data_Element_Definitions.pdf)). Field 52,
  Roadway Type, includes **"Parking Lot"** and **"Parking Garage"**. Pre-crash movement includes **"Parking
  Maneuver"**. Contact areas are recorded for the subject vehicle.
- **What it replaces:** `ca_dmv_av`, which is modelled, not fitted: *"Miles-per-disengagement modeled as lognormal
  (median 5000 mi, sigma=1.4); cause mix and severity mix from industry-aggregate published findings."*
- **The edge:** (1) a fitted crash rate per million miles drives the demand for sensor calibration and body work, which
  load the twin's two service bays; (2) the share of ADS crashes in parking lots and garages is a real in-depot
  incident rate, which the twin's traffic layer can be checked against.
- **How:** a monthly CSV ingest. Waymo's miles are the only public denominator, so the rate is Waymo's.

### C. Charger reliability: a depot-grade profile beside the public-network one (rank 3, a decision for Chase)

- **Today:** `charger_reliability` is *"a composite of published EV charger reliability studies (UC Berkeley 2022 Bay
  Area, JD Power EVX, ChargerHelp)"*: uptime beta(15,5), mean about 75%, and session success about 80%. Those are
  public networks. CLAUDE.md Part 3 records about 13.8% of charger-time lost to faults on a busy_day run, by design.
  On fd6ed035, 14 of 176 charge sessions (8.0%) stopped on a charger fault, DCFC were busy 85% and L2 95.2%.
- **The reference points:** federally funded public ports must average **more than 97% uptime a year**
  ([23 CFR 680.116](https://www.law.cornell.edu/cfr/text/23/680.116)). The DOE ChargeX consortium sets the same
  >97% goal, cut its members' visit failure rate 30% in the first half of 2025, and handed its KPI definitions to SAE
  J2836/5, planned for publication in December 2025 or January 2026
  ([INL, 2025-09-30](https://inl.gov/content/uploads/2023/07/ChargeX-Consortium-Overview-and-Accomplishments-9-30-25.pdf);
  publication not checked).
- **Why it matters:** a fleet-run depot with its own technicians is nearer the 97% floor than 75%. With chargers busy
  85–95%, a queue is very sensitive to lost capacity, so part of the 40% waiting on fd6ed035 may be the fault profile,
  not the orchestration. That has not been measured.
- **Proposal:** keep today's profile as a named stress case and add a depot-grade profile (≥97% port uptime) as the
  base case. It changes every KPI and forces recertification, so it is Chase's call. Also name the charger KPIs to
  match ChargeX / SAE J2836/5 once that standard is confirmed published.

### D. Not recommended now

- **Dragon Lake Parking dataset:** drone-tracked parking-lot trajectories, 3.5 h, 30 scenes, 1,216 vehicles, position,
  heading, speed and acceleration at 25 fps, 140 m × 80 m lot with about 400 stalls, published 2023-11-08, 8.02 GB
  ([Dryad](https://datadryad.org/dataset/doi:10.5061/dryad.tht76hf5b)). The licence was not shown on the page read.
  It could set in-depot speeds and gaps for the 3D layer, but no decision reads them. Use it only if the motion work
  needs numbers.
- **Robotaxi fleet sizes and rides a week:** the figures found (about 500,000 Waymo paid rides a week in Q1 2026,
  about 3,500 cars) came from secondary sites only, so they are not used here.

## 3. Feeds the registry says it has, which do not run

`public.external_factor_sources`, read 2026-10-07 03:00 UTC:

| Row | State | Finding |
|---|---|---|
| `tva.nashville.tariff` → `https://api.tva.gov/tariff/v1` | `is_active = true`, never polled | No such public API was found (search, 2026-10-07). The real tariff is already held: `ottoq_depot_tariffs`, NES GSA-3 from the NES PDF, retrieved 2026-07-09. |
| `tva.nashville.dr_events` → `https://api.tva.gov/dr/v1` | `is_active = true`, `fail_closed`, never polled | Same host, not found. |
| `openweather.nashville.primary` | degraded since 2026-04-18: *"missing required fields: temp_f, humidity_pct"* | `noaa_nws` (live refit 2026-10-04) already does this job. |
| `watttime.fleet.primary` → v2 `/index` | inactive, never polled | WattTime replaced API v2 with v3; v2 support was to end in June 2024 ([Carbon Aware SDK decision record](https://carbon-aware-sdk.greensoftware.foundation/docs/architecture/decisions/watt-time-v3)). |
| `nrel.solar_forecast.global` | inactive, never polled | Not used by anything. Endpoint not checked (developer.nrel.gov did not resolve from this container). |

**Proposal:** set the two TVA rows inactive with a note, or delete them, in a small migration, so the registry stops
saying the depot reads a live tariff it does not. Not done here: it is a production table and nothing reads these rows.

## 4. Built in this change, from data already in the database

The KPI board priced energy only. The depot's tariff rows (NES GSA-3, `ottoq_depot_tariffs`) also bill demand:
**$20.34 a kW** of the month's highest 30 minutes (October, "transition" season). Migration **0611** adds to
`ottoq_twin_kpi_board`: the highest full 30-minute grid draw, the same peak with the battery taken out, and both
monthly charges. Measured on run **fd6ed035** (busy_day, sim 8:00 AM – 1:50 PM CT):

| | value |
|---|---|
| grid energy bought | $229.92 (3,198 kWh at $0.0719) |
| highest 30-minute grid draw | 638.6 kW, from 18:20 UTC |
| monthly demand charge | **$12,988.60** |
| without the battery | 715.9 kW, $14,560.55 |
| battery's value on this peak | 77.3 kW, **$1,571.95 a month** |

Found on the way: the sweep scorer `ottoq_arm_peak_profile` also averages the run's last, shorter windows. On fd6ed035 a
final 19.6-minute window sets its peak (654.1 kW, $315 a month above the full-window figure). The board uses full
windows only. The scorer is not changed. It is the research wing's instrument, and both arms of its pairs end on the
same tick.
