# R-7 — eVTOL and drone turnaround parameters for the multimodal scenario

**Filed:** 2026-08-24 by the build track (Claude Code)
**Blocks:** nothing — `solvers/cpsat/scenario_vertiport.json` runs today on labeled
engineering placeholders. This request replaces those placeholders with sourced figures.
Every current placeholder is scenario DATA: correcting it edits one JSON file, never the
solver.

## Context, non-technically

We now schedule three kinds of machines on one site — eVTOLs landing on pads above, ground
robotaxis charging below, cargo drones at the edge — against one electrical service. The
scheduling works; what is invented is the *numbers describing the aircraft*: how fast an
eVTOL charges, how long a pad must sit empty between aircraft, how tight the airline-style
schedule really is. Wrong numbers make the demo quantitatively wrong even when the mechanism
is right.

## Q1 — eVTOL charge/turnaround (per named aircraft where possible: Joby S4, Archer
Midnight, Beta ALIA, Lilium, Volocopter)

1. Usable battery capacity (kWh) and typical charge power accepted on the pad (kW) —
   nameplate and the sustained value if they differ.
2. Published or demonstrated **turnaround time** gate-to-gate (min), and the split between
   charging and everything else (passenger swap, inspection) where stated.
3. Charge-vs-**battery-swap**: which OEMs plan swap, swap duration, dock power draw.
4. Charging standard on the pad (CCS? MCS? proprietary?) and pad electrical rating (kW).

## Q2 — Pad occupancy and separation

1. Minimum time a pad is occupied per movement (land → depart), and any required
   **separation/clearance interval between successive aircraft on the same pad** (min) —
   our `min_gap_min` placeholder is 6 minutes.
2. Vertiport design guidance on pads-per-gate and pad-to-stand tug/taxi times, if any
   (FAA vertiport engineering brief EB-105 or successors; EASA PTS-VPT-DSN).

## Q3 — Schedule slack

For announced eVTOL route operations (e.g. Joby/Delta JFK, Archer/United, Dubai): planned
block times and frequency — anything that lets us infer the realistic `ready_by` slack after
landing (our placeholder: 65–85 minutes arrival-to-ready).

## Q4 — Cargo drone charging

For named platforms (Zipline P2, Wing, Matternet M2): battery kWh, charge power (kW),
charge-vs-swap practice, cycles per day. Placeholders: 8 kWh / 6 kW / opportunity charging.

## Q5 — Certification constraints that shape scheduling

Any regulatory minimums that act as scheduling constraints: post-flight inspection
intervals, battery temperature limits before fast charge (cold-soak after altitude?),
duty-cycle limits on pads. `NOT FOUND` is a useful answer per item.

## Answer format

`docs/research/answers/R-7-evtol-drone-turnaround.md`, conventions as R-1..R-6: units and a
source URL per figure; `NOT FOUND` where no defensible number exists; primary sources
(OEM spec sheets, FAA/EASA documents, operator filings) over trade press.
