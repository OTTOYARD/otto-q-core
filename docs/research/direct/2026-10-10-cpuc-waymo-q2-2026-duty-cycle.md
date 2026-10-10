# What Waymo's California filing says about a robotaxi's day, and where the twin stands against it

**Date:** 2026-10-10 CT (files read 2026-10-10 05:18-05:45 UTC, 12:18-12:45 AM CT). **By:** Claude Code (build track),
by direct download under CLAUDE.md rule 3. No research agents were used. Every external figure carries its file, its
period and its URL. The twin side is measured read-only on the twin depot (`11111111-…`) in
[db/checks/0433](../../../db/checks/0433_cpuc_says_a_waymo_charges_every_50_miles_and_busy_day_charges_every_18.sql).
This is Part A, item 5, of the twin data contract review (2026-10-08), and it answers the Oct 6 note's
[§2A](2026-10-06-av-world-models-and-data-integrations.md) instruction: *"Read the real columns before designing the fit."*

## The answer in short

1. **No fit is possible from this filing.** Waymo redacted every per-trip, per-charger and per-session column, and
   the whole stoppage data set. What is left is three monthly totals (trips, miles by period, hours waiting), the
   count of charging sessions and the count of chargers. So the CPUC data gives **fleet means and one lower bound**,
   not distributions. Nothing goes into the calibration corpus from it (a corpus row forces a recertification, and no
   twin function would read a single mean).
2. **The real numbers, Apr-Jun 2026, Waymo's California deployment program:** 4,220,075 trips over 28,143,284 miles,
   all electric. **6.67 miles per trip, of which 41.1% carried no passenger** (26.3% between trips, 14.8% to the
   pickup). **16.6 minutes waiting** between a drop-off and the next accepted trip. **566,282 charging sessions on 324
   chargers: 19.2 sessions per charger per day, and at least 49.7 deployment miles per session.**
3. **The twin brackets that number, by scenario.** Without busy_day's stress profile (normal_day, and the
   certification and research pairs, which start without it, G219), the twin drives **47-52 miles per charging
   session**, right at the real fleet's floor. With the profile (the operator's busy_day), it drives **18.2**. The
   profile drains every car 30 battery points per hour it is out, on top of driving, by design: busy_day is the
   depot's stress case. Read any operator busy_day figure as a stress-world figure.
4. **The twin's physics is light on energy per mile, and its stress drain is heavy.** The twin's Waymo I-Pace uses
   **25.6-27.9 kWh per 100 miles** from the battery without the profile and **109.5** with it. EPA rates the 2021
   Jaguar I-Pace EV400 at **44 kWh per 100 miles** at the wall (which includes charging losses the twin's battery-side
   figure does not). So physics alone is lighter than a real I-Pace, and the stress world is about 2.5 times heavier.
5. **A recording defect found on the way (G406):** the dispatch ledger's `miles_driven` counts each telemetry packet
   as one minute of driving, and packets come once per tick. The KPI tab's "miles" reads 2-68% of the miles the cars
   drove, depending on the tick length.
6. **The twin's collision rate is about a 25th of the filing's.** 291 collisions over 28.1 million miles, all reported
   to NHTSA: **10.3 per million miles** (0.92 with an injury flag). The twin fires 0.41 per million miles, and busy_day
   0.16. It recorded none in 440,000 miles this week. The filing cannot say how many crashes sent a car to a depot.

## 1. The source

| | |
|---|---|
| Publisher | California Public Utilities Commission, AV programs quarterly reporting ([page](https://www.cpuc.ca.gov/regulatory-services/licensing/transportation-licensing-and-analysis-branch/autonomous-vehicle-programs/quarterly-reporting), read 2026-10-10) |
| File | Waymo LLC, Driverless Deployment, Q2 2026 (2026-04-01 to 2026-06-30), filed 2026-08-03: [waymo-deployment-2026q2.zip](https://www.cpuc.ca.gov/-/media/cpuc-website/divisions/consumer-protection-and-enforcement-division/documents/tlab/av-programs/waymo-deployment-2026q2.zip), 64,195,863 bytes, sha256 `8897db0608f9a8ba051b841a6e29112ee042a75e0fcfa6e2f98aa420d89b89c8` as downloaded 2026-10-10 |
| Dictionary | [cpuc-av-deployment-data-template-and-dictionary-av-pd---v2.xlsx](https://www.cpuc.ca.gov/-/media/cpuc-website/divisions/consumer-protection-and-enforcement-division/documents/tlab/av-programs/cpuc-av-deployment-data-template-and-dictionary-av-pd---v2.xlsx), sha256 `9e1d69f5bccb685666b92917e25ab6e5321f2324834af5884ad9d2b072fc6e06` |
| Operator id | TCPID `PSG0038152` |

**Definitions, quoted from the dictionary:**

- Period 1 VMT: *"Vehicle miles traveled since the last trip while the vehicle is neither carrying passengers nor en
  route to picking up a passenger."* This is where a trip to a depot or charger lands.
- Period 2 VMT: *"Vehicle miles traveled between the point where the vehicle was when it accepted a trip to the point
  where it picked up the passenger."*
- Period 3 VMT: *"Vehicle miles traveled between the pick-up point and the drop-off point."*
- TotalWaiting: *"The total amount of time vehicles waited between ending one passenger trip and initiating the next
  passenger trip, expressed as a monthly total in hours"*; it *"begins after end of previous trip's Period 3 (passenger
  drop off) to beginning of next trip's Period 2 (request accepted, vehicle en route to next passenger)."* So it holds
  every minute between trips, depot and charging time included; the filing does not split it.
- Charging, from the filing's own reference key: *"EV charging data reflects charging data for Waymo's entire
  passenger service fleet, including vehicles operating under both Pilot and Deployment programs ... it is not
  reasonably feasible to apportion charging sessions by the trips provided."*

**What is redacted** (each cell reads `Redacted`): on every trip, its dates and times, every VMT field, the vehicle,
the tracts and zips; on every charger, its id, tract, power, type, load-serving entity and rate; on every session,
its id, charger, start and duration; the fleet stoppage counts and times; and the whole stoppage-incident file
(*"Data set redacted"*). The incident and complaint file keeps its yes/no flags (section 4).

## 2. The numbers

| Month (2026) | Trips | Miles (all electric) | No passenger | Of which between trips | Miles per trip | Waiting per trip |
|---|---|---|---|---|---|---|
| April | 1,416,158 | 9,414,525 | 40.7% | 26.1% | 6.65 | 16.7 min |
| May | 1,454,991 | 9,704,968 | 40.7% | 26.3% | 6.67 | 16.0 min |
| June | 1,348,926 | 9,023,791 | 41.9% | 26.4% | 6.69 | 17.1 min |
| **Q2** | **4,220,075** | **28,143,285** | **41.1%** | **26.3%** | **6.67** | **16.6 min** |

Per trip: 1.75 miles between trips, 0.99 to the pickup, 3.93 with the rider. 1.58 passengers per trip. Per day over
the 91 days: 46,374 trips and 309,267 miles.

**Charging:** 566,282 sessions (rows in the sessions file) on 324 chargers (rows in the chargers file) over 91 days:
**19.2 sessions per charger per day**, 6,223 a day fleet-wide, 7.45 deployment trips per session. Since the sessions
cover the pilot program's cars too and the miles do not, **28,143,285 / 566,282 = 49.7 is a floor on miles per
session**, not an estimate of it.

**What this cannot give:** a driving speed (trip times are redacted), so not the share of time a car is moving; a
fleet size, so not miles or sessions per car per day; and the energy per session or the charger power, so not
kWh per mile.

## 3. The twin against it

Measured on the twin depot's runs of the 7 days to 2026-10-10 (db/checks/0433). The runs are not independent
observations (pairs share seeds, G153): these are levels to compare, not rates with ranges.

| | Waymo CA, Q2 2026 | Twin, no profile: normal_day | Twin, no profile: busy_day pairs | Twin, busy_day with profile (operator) |
|---|---|---|---|---|
| Runs / sim hours | — | 4 / 24 | 24 / 264 | 32 / 565 |
| Minutes out per return | — | 132 | 150 | 42 |
| Miles per return (from the cars' own speeds) | — | 48.5 | 54.0 | 23.3 |
| **Miles per charging session** | **≥ 49.7** | **46.7** | **51.6** | **18.2** |
| Sessions per charger per day | 19.2 | 10.6 | 6.7 | 12.0 |
| Battery points per hour out | — | 5.5 | 6.3 | 41.3 |
| Waymo I-Pace, kWh per 100 miles (battery) | EPA 44 at the wall (2021 I-Pace EV400) | 25.6 | 27.9 | 109.5 |

**Reading it:**

- **The physics world sits at the real floor; the stress world charges 2.7 times as often per mile.** The floor is a
  floor, so the real fleet may drive much further per session; the filing cannot say.
- **The stress drain is declared, not a defect.** busy_day's template sets `soc_on_arrival {shift -30}`; since 0486
  (G219) that is 30 battery points per hour out, drawn as power. It is what makes busy_day's charger line real, and it
  is why 71 of 76 twin-depot runs this week describe a heavier world than Waymo's California fleet. What it should
  not be is the world a real-fleet KPI is quoted from.
- **The physics is light against EPA.** 25.6-27.9 kWh per 100 miles from the battery against 44 at the wall. Part
  of that gap is charging loss (EPA counts it, the twin's battery-side figure does not); the twin's always-on AV load
  is also 0.3 kW (`twin.ottoq_sim_compute_discharge_rate`). Neither part is measured here, so the gap is stated, not
  split.
- **Chargers turn faster in California.** 19.2 sessions per charger per day against 6.7-12.0 in the twin. 35 of the
  twin depot's 45 chargers are 19.2 kW L2 units and 10 are 350 kW fast chargers (`ottoq_ocpp_chargers`), and Waymo's
  charger types are redacted, so the gap may be in the kind of charger as much as in the tempo, and nothing here
  says which.

## 4. Collisions (Part A, item 6, first read)

The incident and complaint file keeps its yes/no flags, so it can be counted. Streamed across its seven parts
(4,888,011 rows; 2,064 carry any content, the rest are blank):

| | Q2 2026 | Per million miles |
|---|---|---|
| Rows flagging a collision | 291 (63 of them at a pickup or drop-off) | **10.3** |
| ... with another motor vehicle | 258 | 9.2 |
| ... with an injury flag (possible, minor or severe) | 26 | 0.92 |
| ... severe | 2 | 0.07 |
| ... fatal | 0 | 0 |
| Citations | 1,238 (977 issued by SFMTA) | — |
| Safety complaints | 281 | — |

All 291 collision rows carry an NHTSA Standing General Order 2021-01 report id (redacted), so these are the crashes
Waymo reported to NHTSA. The dictionary counts one incident per row: *"A single collision may be entered in more than 1
field if multiple actors were involved."*

**The twin fires any incident at 5e-7 per mile** (`twin.ottoq_sim_maybe_incident`, its comment: *"DMV-calibrated ... 1
per 2M miles"*), 82% of them collisions: **0.41 collisions per million miles, about a 25th of the filing's**, and
busy_day's profile multiplies that by 0.4. Over the 7 days to 2026-10-10 the twin depot drove about 440,000 miles and
recorded no incident (0.15 expected at its rate; about 4.5 at the filing's).

**What the filing cannot say is the part a depot needs:** how many of the 291 brought the car in, and for what work.
That share, not the crash count, sets body and inspection bay demand. NHTSA's own reports give it: the Waymo was towed
in 53.4% of its 1,211 reports ([the NHTSA note](2026-10-10-nhtsa-crash-reports-and-temperature-curves.md)). And even at the filing's rate a twin run of about 5,800
miles meets a collision about once in 17 runs, so the leverage on any single run is small.

## 5. What to build, and what not to

- **Fix the miles ledger (G406).** Accumulate each tick's miles on the dispatch as its energy already is, so the KPI
  tab, the off-site window and the arrival webhook's odometer read what the cars drove. Twin-only, no decision reads
  it.
- **Do not put the CPUC means in the corpus.** One mean per quarter is a target to check against, not a distribution
  to deal from. Re-read the next quarter's filing (Jul-Sep 2026, due about November) the same way and compare.
- **Raise the twin's collision rate to the filing's (G408) with the next change to the twin's world, not alone.** It
  needs a second number the filing lacks (the share of crashes that bring a car in), which NHTSA's reports supply
  (53.4% towed), and at the real rate a run sees a tow-in about once in 31 runs.
- **Give the research wing a third world, later, if a question needs it:** busy_day's arrivals without the 30-point
  drain, so a result can be read at the real fleet's miles per session. Not built tonight: no open question asks
  for it yet, and a new scenario template changes nothing until a pair runs in it.
