# R-20: Fast-charge curves for the twin's robotaxis

**Filed** 2026-09-30 by the build track (Claude Code), for Lane A. **Not blocking.** The calibration ships with the
best public evidence and labels its confidence. This request is to replace the two low-confidence pieces with measured
ones. **Status:** open.

## Why this is being asked

Rule 9 charges every car to 100%. So how long a car holds a fast charger, and how many chargers a depot needs, depend
on the whole curve, above 80% most of all. The twin's charge curves were calibrated on 2026-09-30 from a public dataset
of 99 measured curves and from EV Database
(`docs/research/direct/2026-09-30-lane-a-service-time-calibration.md`). Two of the twin's three large groups have no
measured curve:

- **Jaguar I-PACE** (40 of the twin's 116 cars, as Waymo's I-PACE; 4 more as I-PACE AV). The curve is fitted to EV
  Database's 45-minute 10-80% time. Above 80% it follows the dataset's median tail. The fit makes the 80-100% leg 49
  minutes, but a curve that tapers earlier would meet the same 45 minutes with a faster tail.
- **Zoox robotaxi** (34 cars). Zoox publishes 133 kWh and 16 hours per charge. No fast-charge power from Zoox was
  found. The twin uses 100 kW from one secondary site.

## Questions (each answer: the value, the model year or date it applies to, and a URL)

1. **I-PACE fast-charge curve:** power in kW at 10, 20, ..., 90, 95, 100% state of charge, on a charger rated
   100 kW or more. Ideally Fastned's published I-PACE curve as numbers (Fastned shows it as an image at
   https://www.fastnedcharging.com/en/brands-overview/jaguar), or a measured 0-100% session with timestamps. State
   whether it is a 2019-2020 car or a later one.
2. **I-PACE time from 80% to 100%** on DC, in minutes, from any measured source.
3. **Zoox robotaxi:** maximum DC charging power in kW and the connector, from Zoox, a Zoox filing (e.g. FMVSS or NHTSA
   exemption documents) or a first-hand report. If a charge time is published instead, give it with its start and
   end state of charge.
4. **Tesla Cybercab:** battery capacity in kWh and charging method and power (Tesla has described inductive
   charging). Date of the statement.
5. **Waymo's Zeekr-built vehicle (Waymo Ojai):** usable battery capacity and maximum DC charging power.
6. **Waymo's I-PACE fleet:** does Waymo run a software limit on DC charging power or the charge ceiling? Any public
   statement, with its date.

## What changes when answered

The I-PACE and Zoox curves in the calibration migration are replaced by the measured ones, labelled as a new
calibration, and the next overnight test re-measures the charger counts. Nothing is back-filled into an existing result.
