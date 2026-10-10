# Robotaxi crashes that reach a depot, and how temperature costs range: NHTSA's reports and two published curves

**Date:** 2026-10-10 CT (files read 2026-10-10 05:52-05:57 UTC, 12:52-12:57 AM CT). **By:** Claude Code (build track),
by direct download and search under CLAUDE.md rule 3. No research agents were used. Every external figure carries its
file or page, its date and its URL. The twin side is measured read-only on the twin depot (`11111111-…`) in
[db/checks/0434](../../../db/checks/0434_half_of_waymos_reported_crashes_end_in_a_tow_and_the_twin_counts_the_cold_twice.sql).
This is Part A, items 2 (NHTSA crash reports) and 4 (fitted temperature effects), of the twin data contract review
(2026-10-08). It follows the CPUC note of the same day ([2026-10-10-cpuc-waymo-q2-2026-duty-cycle.md](2026-10-10-cpuc-waymo-q2-2026-duty-cycle.md)).

## The answer in short

1. **More than half of Waymo's reported crashes end with the car towed.** NHTSA's public crash reports for automated
   driving systems (incidents from April 2025 to August 2026) hold 1,211 Waymo reports; in **647 (53.4%) the Waymo
   vehicle was towed**. 87.1% were property damage only, 46.1% happened with the Waymo stopped, and 2 were fatal.
   Combined with the CPUC filing's 10.3 collisions per million miles, that is **about 5.5 tow-ins per million miles**.
   The twin tows 0.23 per million miles (0.09 on busy_day), about a 24th (G408).
2. **8.2% of them happened in parking lots, and those read like a depot's hazards:** barrier arms closing on the car,
   the roof sensor striking a carport, bollards and curbs while reversing, the underside on a sloped exit. The twin
   depot has barrier-arm gates and 12-14 ft canopies, and records no clearance under any structure (G409).
3. **The twin counts the cold, and the heat, twice.** Geotab's published curve (4,200 EVs): range peaks at 115% of
   rated at 21.5 °C, falls to 54% at -15 °C, and stays at or above 100% from 10 to 31 °C. The twin's driving physics
   alone already tracks it: 44% of its 21.5 °C range at -15 °C (Geotab: 47% of its peak), and at least 87% from 10 to
   31 °C (Geotab: at least 87%). The hand-set climate drain on top takes the twin to 27% at -15 °C and 73% at 31 °C.
   It barely fires today (the twin's runs are September days, 10-29 °C), so it moves nothing yet (G410).
4. **The fast-charging cold penalty cannot be fitted from what is published.** Recurrent: about 9 minutes longer at
   0 °F, with no baseline, charge window or curve. The twin's charge clock already learns air temperature from the
   twin's own sessions (0632, G374).

## 1. NHTSA's crash reports

| | |
|---|---|
| Publisher | NHTSA, Standing General Order 2021-01 incident reports, automated driving systems |
| File | [SGO-2021-01_Incident_Reports_ADS.csv](https://static.nhtsa.gov/odi/ffdd/sgo-2021-01/SGO-2021-01_Incident_Reports_ADS.csv), 2,581,860 bytes, sha256 `f856d0b9cedc5f4447515c200eeacdff5d4cabf63003dcac207385eb466ff7f5`, downloaded 2026-10-10 |
| Definitions | [SGO-2021-01_Data_Element_Definitions.pdf](https://static.nhtsa.gov/odi/ffdd/sgo-2021-01/SGO-2021-01_Data_Element_Definitions.pdf), sha256 `c92e1bec238e757867d67ea5bf0b26f4a3e9223d0b92a9a7ce76d446518f4fa4` |
| Coverage | 1,478 report rows, 1,437 report ids (the latest version of each is used), incidents April 2025 to August 2026 (August partial). Earlier years sit in a separate archive (`.../sgo-2021-01/Archive-2021-2025/`), not read here. NHTSA's own caution: report data may be incomplete or unverified. |

**Waymo, 1,211 reports** (by state: CA 732, AZ 196, TX 166, GA 65, FL 30, TN 9, others 12):

| | Reports | Share |
|---|---|---|
| The Waymo vehicle towed (`Was Any Vehicle Towed?` begins "Yes Subject Vehicle") | 647 | **53.4%** |
| Property damage only, no injury reported | 1,055 | 87.1% |
| Waymo stopped / parked before the crash | 558 / 117 | 46.1% / 9.7% |
| Street / intersection / **parking lot** / highway | 870 / 220 / **99** / 17 | 71.8% / 18.2% / **8.2%** / 1.4% |
| Fatal | 2 | 0.2% |
| No one in the driver's seat (`Driver / Operator Type` = None) | 1,154 | 95.3% |

**The 99 in parking lots.** 54 of them ended with the Waymo towed. 38 at 0 mph, 29 above 0 and up to 5 mph, 32 faster. The
objects the narratives name most: barrier 18, curb 16, gate 8, pole 5, bollard 4, wall 4. Examples, from the
narratives (locations redacted by NHTSA): a car yields at closed barrier arms, follows the car ahead through, and the
arms lower onto it (AZ, June 2026, 2 mph); the roof sensor strikes a carport while the car moves under it for a drop-off
(AZ, June 2026, twice); the car reverses toward a curb beside bollards (AZ, August 2026, 3 mph); the underside meets the
pavement on a sloped exit between lots (TX, July 2026, 9 mph).

**Against the CPUC filing.** NHTSA's file holds 183 Waymo reports in California for incidents in April-June 2026; the
CPUC filing for the same quarter has 291 collision rows, every one carrying an NHTSA report id (redacted). The two
cannot be reconciled from public data. The tow share above is NHTSA's (all states, 15 months); the collision rate is
CPUC's (California, one quarter); the 5.5 tow-ins per million miles combines them and is an estimate, not a measurement.

## 2. What it means for the twin

- **The twin under-delivers towed cars about 24 times** (G408). `twin.ottoq_sim_maybe_incident` fires 5e-7 incidents
  per mile, and 45% of its kinds require a tow (moderate collision, electrical breakdown, tire, stranded, major): 0.23
  tow-ins per million miles, x0.4 on busy_day. At the real rate a twin run of about 5,800 miles meets a tow-in about
  once in 31 runs, so the leverage on any one run stays small; it matters for a multi-week claim about body or
  inspection bay demand.
- **The depot's own hazards are in the parking-lot narratives** (G409). The twin depot's two gates carry barrier arms
  and ALPR, its metal canopies over the perimeter staging stalls are 12 ft and its solar canopies 14 ft
  (`ottoq_site_structures.height_ft`, the top of the structure). No structure records the clearance beneath it, and no
  vehicle class records its height with sensors. A depot laid out for robotaxis needs both, and a gate protocol that
  admits one car per arm cycle.

## 3. Temperature

| Source | Claim | Version / date | URL |
|---|---|---|---|
| Geotab | 4,200 connected BEVs, 5.2 million trips, 102 make/model/years. Range peaks at **115% of rated at 21.5 °C (70 °F)**; **54% of rated at -15 °C (5 °F)**; **100% or more from 10 to 31 °C (50-88 °F)**. The full curve is a chart with no published points. | page published 2025-10-30, read 2026-10-10 | https://www.geotab.com/blog/ev-range/ |
| Recurrent | 200,000+ charging sessions, 4,296 cars: charging at 0 °F takes **about 9 minutes longer on average, not including time to warm the battery if it is very cold**. No baseline, charge window or per-temperature points. | page dated 2024-01-18, read 2026-10-10 | https://www.recurrentauto.com/research/study-ev-charging-speeds-in-cold-temperatures |

**The twin against Geotab.** `twin.ottoq_sim_compute_discharge_rate` draws a drive power from speed, a cabin heat or
cooling load of 0.5 kW plus 0.15 kW per °C beyond 5 °C either side of 22 °C (at most 5 kW), a 0.3 kW always-on AV load,
and a battery factor of +2% per °C below 5 °C and +1.5% per °C above 35 °C. On top, `ottoq_twin_arrival_soc_drain`
adds 8 battery points per hour out at full heat stress (day mean 38 °C and up, from 28 °C) and 12 at full cold stress
(day mean -10 °C and down, from 5 °C). For a Waymo I-Pace at normal_day's mean duty (55 km/h, 62.5% of the time
moving), range relative to the twin's own 21.5 °C:

| Day mean | Twin physics only | Twin with the climate drain | Geotab, relative to its 21.5 °C peak |
|---|---|---|---|
| -15 °C | 43.9% | 27.0% | 47.0% |
| 0 °C | 67.0% | 50.9% | — |
| 10 °C | 87.2% | 87.2% | ≥ 87.0% |
| 31 °C | 92.3% | 73.1% | ≥ 87.0% |
| 35 °C | 85.6% | 54.6% | — |

The physics alone sits on all three of Geotab's published points; the drain pulls both ends well below them. Geotab's
fleet is not a robotaxi fleet (doors open at every stop, longer idle with the cabin conditioned), so the physics agreeing
is a check, not a fit. Over the twin depot's 76 runs of the last 7 days the drain averaged 0.03 points per hour (day
means 10.1-28.9 °C; every run starts on 2026-09-01), so removing it changes nothing measured this week. It would change
any winter or July scenario.

## 4. What to build, and what not to

- **Drop the climate drain's temperature terms** (G410), with an evidence regime row, before any winter or high-summer
  scenario runs. Keep the physics. Not tonight: nothing the twin runs this week is in those months.
- **Raise the tow-in rate with the collision rate** (G408): one change to the twin's world, recorded as an evidence
  regime, using the filing's 10.3 collisions per million miles and NHTSA's 53.4% towed.
- **Give the yard a clearance** (G409): a clearance under each canopy and gate, and a height per vehicle class with its
  sensors, so the depot layout can be checked and the twin can refuse a stall a car cannot reach. A design input for
  the site layer; no number in the twin moves for it.
- **Do not fit the charge side to Recurrent's figure.** It has no baseline. The twin learns its own.
