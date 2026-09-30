# Lane A: how long each service takes, calibrated to public data

**Found by direct search, 2026-09-29 evening CT, for Lane A.** Recorded as a Hermes deliverable would be (CLAUDE.md
rule 3): each claim, the date or version it applies to, and its URL. Chase, 2026-09-29, 8:20 PM CT: *"All services take
certain amounts of time. You have to calibrate that."* Every throughput, charger-count and uptime number the twin shows
rests on these times, so they are fixed before any of those numbers is shown to a customer or an investor.

**What is not here:** prices. Car wash and detailing prices are out of scope (Chase, same message). The electricity
tariff is a separate item (task 26).

## 1. Summary

| Service | Twin today | Public range | Decision | Confidence |
|---|---|---|---|---|
| **Fast charge, Tesla Model Y LR** | 22.5 min (10-80%), 25.3 (80-100%) | 27 min (10-80%, EV Database); 29.2 / 27.2 from its measured curve | **Calibrate to the measured curve** | High to 90%, medium above |
| **Fast charge, Jaguar I-PACE** | 56.3 / 63.3 min, on a 75 kWh battery | 45 min (10-80%) on 84.7 kWh usable, 104 kW (EV Database) | **Calibrate: fitted to 45 min** | Medium to 80%, low above |
| **Fast charge, Zoox** | 50.7 / 57.0 min at 135 kWh, 200 kW | 133 kWh (Zoox). Charge power not published by Zoox; 100 kW per one secondary source | **133 kWh, 100 kW, typical curve** | Low (R-20) |
| Exterior wash | 8-10 min | 6-10 min in-bay automatic; 2.5-5 rollover | Keep | Medium |
| Sensor calibration | 30 min (18 floor) | 30 min-2 h static; 60-90 typical for a forward camera; 60-75 per radar | **Raise to 60 (30-120)** | Medium |
| Software update | 30 min | Tesla: installs "can take upwards of an hour"; the car cannot be driven meanwhile | Keep 30, runs while charging | Medium-low |
| Mechanical PM | 40 min (23-60) | Tire rotation 15-30 min; with brake inspection and filter, 40-60 | Keep | Medium-low |
| Interior tidy / inspection | 3-5 min | Rental turn: "a quick vacuum, wipe down"; a one-minute check | Keep | Low |
| Interior deep clean | 20 min (12-35) | No robotaxi source found | Keep | Low |
| Sensor clean, walkaround, triage, readiness, item retrieval, remote diagnostics | 3-12 min | No public source found | Keep | Low (engineering estimates) |

"Keep" means the twin's value already sits inside the public range, or no public source exists to move it. In both
cases the value now carries a confidence instead of passing as a fact. Services that run **while the car charges**
(cabin, exterior and digital work) add no time to a visit unless they outlast the charge. That is why the charge is
where calibration matters most.

## 2. The charge: the biggest time in every visit

### 2.1 Why the last 20% matters here

Rule 9: every car charges to 100%. On a fast charger the power falls steeply above 80%. So the time to 100%, not the
familiar 10-80% figure, decides how long a car holds a charger and how many chargers a depot needs.

### 2.2 What the twin does today

`public.ottoq_sim_compute_charge_rate` gives every car one taper shape: 85-100% of the lower of the car's and the
charger's maximum up to 20% charge, falling in a straight line to 22% of it at 80%, then to 8% at 100%. It is scaled by
the car's maximum power, so a car with a low maximum tapers from the same fraction as a car with a high one. The effect
is that it charges a 250 kW Model Y too fast, and slow-peak or large-battery cars far too slowly:

| Battery (as the twin holds it) | Twin 10-80% | Twin 80-100% | Twin 20-100% |
|---|---|---|---|
| Model Y, 75 kWh, 250 kW | 22.5 | 25.3 | 46.0 |
| I-PACE, 75 kWh, 100 kW | 56.3 | 63.3 | 115.0 |
| Zoox, 135 kWh, 200 kW | 50.7 | 57.0 | 103.5 |

(25 C, full state of health, a 350 kW charger, integrated by `public.ottoq_estimate_charge_minutes` itself.)

### 2.3 The data

| Claim | Applies to | Source |
|---|---|---|
| 99 fast-charge curves (power vs. state of charge) digitized from Fastned and InsideEVs. 20 run from 12% or below to 98% or above, which is what shows the last 20%. Licence CC BY 4.0. | Curves accessed Feb-Jul 2025; published 2025-11-08 | figshare, doi:10.6084/m9.figshare.30570653.v1, https://figshare.com/articles/dataset/Digitized_Electric_Vehicle_Fast-Charging_Profiles_by_Model_Power_vs_SOC_SOE_CSV_Format_Version_1/30570653 |
| Tesla Model Y Long Range measured on a Fastned 300 kW charger: 220 kW at 10%, 182 at 20%, 105 at 50%, 73 at 70%, 48.5 at 80%, 34.6 at 90% (the curve ends at 90%) | same dataset, file "Tesla Model Y Long Range_300kW" | same |
| Model Y Long Range RWD: **75.0 kWh usable, 250 kW, 10-80% in 27 min**, 124 kW average | Feb 2024 - Feb 2025 | EV Database, https://ev-database.org/car/2186/Tesla-Model-Y-Long-Range-RWD (retrieved 2026-09-30) |
| Jaguar I-PACE EV400: **84.7 kWh usable, 104 kW, 10-80% in 45 min**, 83 kW average | 2020-2023 and 2023-2025 (identical) | EV Database, https://ev-database.org/car/1287/Jaguar-I-Pace-EV400 and https://ev-database.org/car/1812/Jaguar-I-Pace-EV400 (retrieved 2026-09-30) |
| I-PACE: 100 kW maximum on Fastned, 90 kWh battery; curve published as an image only | 2020+ | Fastned, https://www.fastnedcharging.com/en/brands-overview/jaguar (retrieved 2026-09-30) |
| Zoox robotaxi: **133 kWh battery**, "16 hours of continuous operation per charge" | Unveiling, 2020-12-15 (updated 2024-04-03) | electrive, https://www.electrive.com/2020/12/15/robotaxi-unveiled-by-amazons-zoox/ |
| Zoox: "DC fast charging up to 100 kW via CCS1", 11 kW AC | Undated; **secondary, not from Zoox** | EV Car Latest, https://evcarlatest.com/zoox-robotaxi/ (the page did not render its text to a fetch; seen in search results 2026-09-30) |

### 2.4 The method

A battery accepts a certain power **per kWh of its usable capacity** at each state of charge, and a car or charger
caps that. So the calibrated rate is:

> power at charge *s* = the lowest of: the charger's maximum, the car's maximum, and usable kWh x the battery's
> acceptance at *s* (kW per kWh)

It is then multiplied by today's temperature, state-of-health and noise factors, which do not change. There are three
acceptance curves, each from its best available evidence:

- **Model Y LR: measured.** Its own Fastned curve, in kW per usable kWh, to 90%. Above 90% it follows the median tail
  below, because the measured curve stops at 90%.
- **I-PACE: fitted.** No measured I-PACE curve is public as data. The car's 104 kW holds to 50%, which fits the common
  report that its rate "drops" around 50%. It then tapers to a fitted value at 80% and follows the median tail. The one
  fitted number, 0.332 kW per kWh at 80% (28.1 kW), makes 10-80% equal EV Database's 45 minutes.
- **Every other battery: typical.** The median kW per usable kWh over every curve in the dataset that covers that
  state of charge. The car's own maximum then binds wherever it is lower. This is used for Zoox, and for the handful of
  Cybercab, Zeekr and newer I-PACE AV cars.

**The median tail:** over the 20 curves measured to 98% or above, power relative to its value at 80% is 0.93 at 85%,
0.84 at 90%, 0.66 at 95% and 0.31 at 100%. Across those 20, the 80-100% time is 0.92 times the 10-80% time at the
median, with a middle half of 0.62-1.27.

### 2.5 The result

Nominal conditions as in 2.2. Reproduced by `2026-09-30-lane-a-charge-curve-fit.py`, next to this file:

| Battery | 10-80% | 80-100% | **20-100%** | Twin today, 20-100% |
|---|---|---|---|---|
| Tesla Model Y LR, 75 kWh, 250 kW (measured) | 29.2 | 27.2 | **54.2** | 46.0 |
| Jaguar I-PACE, 84.7 kWh, 104 kW (fitted) | 45.1 | 49.3 | **89.5** | 115.0 |
| Zoox, 133 kWh, 100 kW (typical) | 55.9 | 21.3 | **69.2** | 103.5 |
| *Zoox, 133 kWh, 200 kW (if Zoox's real figure is higher)* | *32.1* | *21.2* | *49.3* | |

**What it means:**
- The twin charged Model Ys about 15% too fast.
- It charged I-PACEs (the largest group) about 22% too slowly and Zoox cars about 33% too slowly, counting the
  last 20% that rule 9 requires.
- Across the twin's fleet, calibrated charges are shorter on average. So the twin overstated how long cars hold a
  charger, and with it how many chargers a depot needs.
- **Any charger count or throughput figure measured before this calibration is superseded, not refined.**

### 2.6 Confidence, and what would change it

- Model Y to 90%: **high** (measured, and within 8% of EV Database's independent 27 min). Model Y above 90%: **medium**
  (median tail).
- I-PACE: **medium** to 80% (one published time, fitted), **low** above 80%. The fit puts the whole taper after 50%,
  which makes its tail slow: 28 kW at 80%. A curve that tapers earlier would meet the same 45 minutes with a faster
  tail. The range is roughly 25-50 min for 80-100%. **R-20 asks for a measured I-PACE curve.**
- Zoox: **low**. Zoox has not published its fast-charge power. 100 kW is the only figure found and is secondary, so
  it is used as the **conservative** choice: slower charging makes OTTO-Q's charger count look worse, not better.
  **R-20 asks for Zoox's own figure.**

## 3. Vehicle facts the calibration corrects

| Vehicle (twin row) | Twin today | Calibrated | Source |
|---|---|---|---|
| Waymo I-Pace (40 cars) | 75.00 kWh, 100 kW | **84.7 kWh usable, 104 kW** | EV Database, 2.3 |
| Jaguar I-PACE AV (4) | 90.00 kWh, no max | **84.7 kWh usable, 104 kW** | EV Database, 2.3 (90 is the gross pack) |
| Zoox Robotaxi (30) | 135.00 kWh, 200 kW | **133 kWh, 100 kW** | electrive (133); 100 kW low confidence |
| Zoox VH6 (4) | 133.00 kWh, no max | **133 kWh, 100 kW** | same |
| Tesla Model Y (32) | 75.00 kWh, 250 kW | unchanged | EV Database, 2.3 |
| Tesla Cybercab (4), Zeekr RT AV (2) | 75 / 100 kWh, no max | unchanged. Typical curve, capped by whatever maximum the charge code already assumes for a car with none | not found; R-20 |

## 4. The other services

| Claim | Applies to | Source |
|---|---|---|
| In-bay automatic car wash: 6-10 min per car. Touchless in-bay systems can finish in under 3 min (15-20 cars an hour). Rollover (5 brushes): 2.5-5 min | Industry guides, retrieved 2026-09-30 | Car Wash Advisory, https://www.carwashadvisory.com/learning/types-of-car-washes ; Starwash, https://mystarwash.com/touchless-car-wash-machine ; Broadway Equipment, https://www.broadwayequipment.com/rollover-car-wash/ |
| Static ADAS camera calibration: 30 min to 2 h in a workshop, typically 60-90 min for a forward camera. A single radar statically: 60-75 min. Dynamic adds 30-60 min of driving | 2026 guide | ADAS Line, https://adasline.com/guide/adas-calibration-time/ (retrieved 2026-09-30) |
| Tesla software updates: installation "can take upwards of an hour", and the car cannot be driven during installation | Tesla owner documentation as summarized; Tesla's manual page refused automated retrieval | TechRadar, https://www.techradar.com/how-to/how-to-update-your-tesla ; Tesla Model Y Owner's Manual, https://www.tesla.com/ownersmanual/modely/en_kr/GUID-A5A60CB3-7659-4B08-B2FD-AFD12C2D6EE1.html |
| Tire rotation: 15-30 min. EVs rotate every 5,000-8,000 miles, brake inspections at the same interval | 2026 guides | Michelin, https://www.michelinman.com/auto/auto-tips-and-advice/tire-maintenance/tire-rotation ; Kia EV9 schedule, https://www.emichkia.com/kia-ev9-service-schedule |
| Rental turn cleaning: "a quick vacuum, wipe down with disinfectant"; interior is the bottleneck and varies most | 2026 industry article | Oxmaint, https://oxmaint.com/industries/fleet-management/rental-car-fleet-maintenance-turnaround-guide-2026 |
| Waymo depots employ dedicated cleaning staff who inspect and clean sensors (lidar stopped to clean). No per-car minutes published | 2025-2026 reporting | Bay Area Current, https://bayareacurrent.com/theres-a-lot-of-cleaning-up-poop-a-depot-worker-on-the-human-labor-behind-waymos-autonomous-vehicles/ |

**The one change:** sensor calibration goes from 30 minutes (18-minute floor) to **60 (30-120)**. It is the only
non-charge time with a published range that the twin sits outside the typical part of. It occupies one of the depot's
two service bays, so it matters for bay throughput. Everything else stays and is labelled with its confidence.

## 5. What this changes downstream

- The charge curve changes session physics, so every canon column needs recertification. That is correct: the
  certified day was measured against uncalibrated charges.
- Night 1 (2026-09-29, 11 PM - 6 AM CT) runs **before** calibration and stays in the record as such. Customer-facing
  numbers come from calibrated nights only.
- The margin ledger, the frontier and the Value tab carry the calibration's migration in their provenance, so a
  pre-calibration number cannot be shown as a calibrated one.

## 6. Open (R-20)

`docs/research/requests/R-20-fast-charge-curves-for-the-twins-robotaxis.md`: the Zoox, I-PACE, Cybercab and Zeekr
fast-charge curves, from the manufacturer or a measured source.
