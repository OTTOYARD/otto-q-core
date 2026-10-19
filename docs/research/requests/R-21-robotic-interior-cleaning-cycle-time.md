# R-21 — How long does a robot-arm interior clean of a passenger car take?

**Filed 2026-10-17 by Claude Code for 0746 (the twin's robotic wash lanes). Not blocking:** the twin runs on a labelled
assumption meanwhile (`docs/research/direct/2026-10-17-robotic-wash-and-interior-cycle-times.md` §2).

**Context.** A depot bay where an attendant opens the car's doors and a robot arm vacuums debris and wipes touch
surfaces, then the attendant closes the doors. The twin assumes 10.0 minutes for the robot and 1.5 for the attendant.
Direct search found descriptions of such robots (Tesla's "Cleaning Robot" at its Austin robotaxi hub; Ferrovial's Saroca)
but no time per vehicle.

**Questions (answer each with the source URL and its date; say "not published" where it is not):**

1. For any deployed or piloted robot-arm interior cleaner for passenger cars (Tesla's Austin hub robot, Ferrovial Saroca,
   or any other), the published or reported cycle time in minutes per vehicle, and what the cycle covers (vacuum only,
   vacuum and wipe, disinfect, glass).
2. For the same systems, whether a person opens and closes the doors, and how long that takes per car if stated.
3. For human rental-fleet or robotaxi interior turns (vacuum plus wipe-down, no shampoo), the time per car in minutes, as
   a comparison.
4. Any figure for how often a robot cycle needs a human to finish it (a share of cars), if published.

## Partial answers, by direct search, 2026-10-19 (for 0758)

Found while building 0758 (a fast charger's cleaning arm cleans the cabin while the car charges) and checked again on the
pages themselves between 8:47 and 8:50 AM CT (clocks read at 13:47:03 and 13:49:50 UTC), except where a line says the
page could not be opened. Recorded as a Hermes deliverable would be (CLAUDE.md rule 3): the claim, its date, its URL.
**R-21 stays open:** none of these is a measured robot-arm interior cycle for a passenger car.

| Q | Claim | Applies to | Source |
|---|---|---|---|
| 1 | A robot arm "that can fully clean a Cybercab cabin between rides in under two minutes", switching attachments to vacuum debris, pick up trash and wipe surfaces. **The two minutes is the outlet's own framing, attributed to no one:** the Texas filing lists only a "Cleaning Robot", and Tesla's 2025-01-31 video showed the robot with no time. | Teslarati, 2026-07-13 (byline Gene) | https://www.teslarati.com/tesla-cleaning-robot-cybercab-robotaxi-service/ |
| 1 | "A complete servicing cycle takes approximately 30 minutes": one arm plugs in a NACS or CCS cable, arms remove trash, store lost items, wipe surfaces and vacuum, cameras scan the exterior and cabin on entry. A car "might need just ten minutes" for a quick top-up, scan and tidy. **No time for the interior clean alone.** | Robotics & Automation News interview with Aseon Labs' CEO George Kalligeros, 2026-10-02 (Sam Francis) | https://roboticsandautomationnews.com/2026/10/02/aseon-ceo-the-opportunity-is-to-make-vehicle-servicing-as-autonomous-as-driving/105477/ |
| 1 | Robotic cleaners at a cleaning facility's parking spots that "can move along a track, such as a floor rail or an overhead gantry track", swapping vacuum and cleansing end effectors; with two per vehicle, "a dual robotic cleaning system may clean a vehicle in half the time it takes a single robotic cleaning system". **No time in minutes or seconds.** | US 12,686,365 B2, "Automated fleet-connected cleaning and inspection system", GM Cruise Holdings LLC, filed 2023-04-06, granted 2026-07-21 (dates as Google Patents lists them) | https://patents.google.com/patent/US12686365B2/en (the USPTO PDF, https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12686365, answered 403 on 2026-10-19) |
| 2 | Two door paths in the same patent: "a robotic cleaner next to the vehicle presses a door-opening button to open a vehicle door", or "the dispatch system sends a signal to the vehicle commanding the vehicle control module to open doors". | US 12,686,365 B2, as above | as above |
| 2 | Aseon's integration "coordinates arrival, door access and charging-port activation"; who opens the doors is not said. | Robotics & Automation News, 2026-10-02 | as above |
| 2 | Zoox's purpose-built robotaxi opens its doors automatically. | Core77; read through search results on 2026-10-19, its publication date not shown | https://www.core77.com/posts/138537/Amazons-Zoox-the-Worlds-First-Purpose-Designed-Robotaxi-Launches |
| 2 | Waymo pays gig workers to close doors riders leave open, and says its next vehicles close their own. | Fortune, 2026-02-25; read through search results on 2026-10-19 | https://fortune.com/2026/02/25/waymo-vehicles-doordash-gig-workers-close-doors/ |
| 3, 4 | Nothing new found. | | |

**What 0758 assumes meanwhile (ASSUMPTION — pending R-21):** an overhead arm at each fast-charger stall, 2.5 minutes in
the cabin on each side and 0.8 minutes of motion for both sides (the doors, the swings over the roof, the descents and the
retracts): 5.8 minutes a car, dials `cabin_robot_side_min` and `cabin_robot_motion_min`. The car's own powered doors open
on the depot's command inside the motion minutes (the patent's second path); a car whose doors need a person is not
modelled. Bracketed by the outlet's "under two minutes" for a whole cabin below it and Aseon's ten-minute "quick top-up,
scan and tidy" above it, and by Chase's brief, 2026-10-19: *"several minutes on each side while the average charge might
take around 15 to 30 minutes to top off to completion."* 0746's 10.0-minute robot in a wash bay (the interior lane, with
an attendant) is unchanged and is a different machine.
