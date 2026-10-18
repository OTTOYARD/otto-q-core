# Robotic wash bays: how long a pull-through exterior wash and a robot interior clean take

**Found by direct search, 2026-10-17 between 6:59 and 7:10 PM CT.** Recorded the way a Hermes deliverable would be
(CLAUDE.md rule 3): each claim, the date or version it applies to, and its URL. Written for 0746, the twin's robotic wash
lanes.

Chase, 2026-10-17, evening CT: *"Washbay [can] be assumed as robotic. Both external and internal. Internal may rely on an
attendant, just opening doors for the vehicle. However, [once] open, a robotic arm [can] reach in [and] vacuum out any
debris and potentially wipe down or clean internally. And the external washbay will just act as a classic pull through
wash with potentially simplified steps or rinsing in drying steps to streamline the turnover process."*

The earlier calibration note (`2026-09-30-lane-a-service-time-calibration.md`, §1 and its sources table) already carries
the in-bay automatic range (6-10 minutes a car, rollover 2.5-5). This note adds what bears on a robotic lane.

## 1. What was found

| Claim | Applies to | Source |
|---|---|---|
| Touchless in-bay automatics "take 4-6 minutes for each car (10-15 cars per hour)"; short friction in-bay models "can wash 15-25 cars per hour at ~3 minutes per car"; "longer conveyors wash up to 50 cars per hour" | Equipment-maker blog, 2016-09-07 | Tommy Car Wash Systems, https://tommycarwash.com/blog/friction-vs-touchless-car-washes |
| "Most all of the machines available can do a basic wash in the 3 to 4 minute range"; "De facto industry standard for exterior carwash is now between three and four minutes" | Operator forum posts, 2018-02-21 and 2018-02-22 | Carwash Forum, https://carwashforum.com/goto/post?id=116728 |
| In-bay automatic: "The average time to complete this process is also about four minutes", the steps "to clean, shine and dry it" | Operator forum post, 2011-05-16 | Carwash Forum, https://carwashforum.com/goto/post?id=54681 |
| Conveyor tunnels: 12 m, 20-30 cars an hour; 18 m, 50-60; 30 m, 100-120 | Equipment maker, page © 2026 | KKE Wash Systems, https://kkewash.com/tunnel-car-wash-equipment |
| A robot arm that switches tools to "alternate between vacuuming left-behind debris, picking up trash from the cabin, and contact-cleaning surfaces", described in filings for Tesla's robotaxi hub in Austin as "Cleaning Robot", finished March 2026. **No time per vehicle given.** | News report of filings, 2026-07-12 | Not a Tesla App, https://www.notateslaapp.com/news/4424/tesla-robotaxi-hubs-start-adding-car-cleaning-robots |
| Saroca, Ferrovial's two-arm car-sharing robot: vacuums the interior, cleans the windshield, disinfects; can clean while the battery charges; targets "a 25% increase in the efficiency of the vehicle cleaning and maintenance processes". **No time per vehicle given.** | Company announcement, December 2020 (development project) | Ferrovial newsroom, https://newsroom.ferrovial.com/en/?p=100612 (seen through search results; the page itself answered 403) |
| Automated exterior and interior wash of a transport fleet "in less than 20 minutes" | Equipment maker, 2021-12-30; trucks and trailers, not cars | ISTOBAL, https://istobal.com/dk/blog/exterior-and-interior-wash-of-your-fleet-in-less-than-20-minutes/ |

No public source gives a measured cycle time for a robot-arm interior clean of a car. That gap is filed as
`docs/research/requests/R-21-robotic-interior-cleaning-cycle-time.md`.

## 2. What the twin assumes from it (0746, dial `wash_lane_physics` = 2)

| Lane | Steps | Minutes | Basis |
|---|---|---|---|
| Exterior, robotic pull-through | pull in 0.5, wash program 4.0 (pre-soak, wash, rinse, dry: Chase's simplified steps), pull out 0.5 | **5.0**, each car drawn 4.25-5.75 | The 3-4 minute basic program above, at its top end, plus the car driving itself in and out. ASSUMPTION for the in/out time. |
| Interior, door attendant and robot arm (with the exterior wash in the same bay) | pull in 0.5, attendant opens doors 1.0, robot vacuum and wipe 10.0, attendant closes doors 0.5, exterior program 4.0, pull out 0.5 | **16.5**, each car drawn 13.2-19.8 | **ASSUMPTION — pending R-21** for the robot's 10 minutes and the attendant's 1.5. The rest as above. |
| Service bay (not robotic) | unchanged | 40 × the twin's draw | The 2026-09-30 note. |

Today the twin's crews take 9 minutes for a wash and 25 for a detail (each drawn 0.7-1.3x), and two wash supervisors
gate three bays. With robotic lanes the attendant's work is about 1.5 minutes per interior car, so two attendants cannot
be the limit on three bays and the lane is gated by its bays alone.

## 3. What this note does not settle

- **The robot's interior time.** It is the one number here with no source, and the detail lane's throughput moves with
  it. 0746 records each seat's drawn minutes, so the arms can be re-read at another value once R-21 answers.
- **Tick granularity.** The twin moves in 5 sim-minute ticks, and a car leaves its bay on the first tick after its work
  ends. So a 5-minute wash holds its bay one tick or two, about 7.5 minutes on average, where a real lane turns as each
  car leaves. The twin therefore understates a short robotic cycle's throughput, against the robotic lane, and this
  should be quoted with any robotic-lane number.
- **Prices and capital cost** of robotic bays are out of scope, as in the 2026-09-30 note.
