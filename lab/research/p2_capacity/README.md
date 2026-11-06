# How many cars the twin depot can serve, safely and comfortably (frontier Phase 2, the capacity curve)

Chase, 2026-11-05: *"a massive metric for us will be how many vehicles we can safely/comfortably service throughout the
day/month. Each stop or vehicle integrated means more revenue for us."*

"Safely" is rule 9 and the engine already holds it by construction: no car leaves below its charge target or with a
service it needs still open (`ottoq_departure_clear`, 0543), so a busier depot does not send cars out short; it makes
them wait. "Comfortably" is therefore a waiting question, read against what the owners signed: every contract allows
30 minutes from arrival to a charger (`ottoq_fleet_operator_slas.max_queue_wait_minutes`) and expects a 45-minute visit.

| file | what |
|---|---|
| `grow_fleet.sql` | `lab.grow_fleet(depot, n)`: the twin's own cars cloned round-robin to n (deterministic ids, the twin's owner mix), inside a lab replica only |
| `capacity_day.py` | one lab depot-day at fleet n, run as the engine's own throughput sweep arm runs a day (0568/0572), scored by its scorecard (0567) plus each owner's contract waits and, every half hour, the constraint board's wall (0783) |
| `sweep.sh` | the matrix (scenarios x fleets x seeds), four days at a time, each replica kept for E5 |
| `report.py` | the capacity curve from `results.jsonl` |
| `whatif_reserve_no_surge_jump.sql` | a what-if for one lab day (`capacity_day.py --lab-sql FILE`, recorded with its md5): the battery's reserve does not rise at a surge (G517) |

Each day: the twin depot as built today (30 robotic DCFC posts, 3 wash bays, 2 service bays, 113 staging spaces, one
3,000 kWh battery), 12 hours from 6 AM CT at 5 sim-minutes a tick (the sweeps' own window), the deterministic core alone
(cuOpt and the agent quiesced), OTTO-Q's seat, the twin depot's dials as production has them.

## What it found

### A 12-hour lab day measures the start-up wave, not steady operations (2026-11-05)

The first days ran the sweep arms' own window: 12 hours from 6 AM CT. Read hour by hour (seed 171717), that window is a
transient. The day starts with the whole fleet at the depot and most of it needing a charge at once: 91 visits "arrive"
in the 6 AM hour at 116 cars and 106 at 150, and about half of each wait past the contract's 30 minutes (43 of 89 and 52
of 105 charged; on seed 424242, 42 of 94). After that, most cars come back only once inside the window, as the morning
wave returns. The work side asks for 97-104 cars out in the afternoon at 116 cars and gets 73-86, and 125-135 at 150
and gets 98-109; and afternoon arrivals barely move with the fleet (28.7 an hour at 116 cars, 29.2 at 150, 1 PM to 6 PM).
So the 12-hour days are kept as a stress test of the start-up wave, and the capacity curve proper is read on whole days
(288 ticks, `jobs_2026-11-05c.txt`).

Arrivals from 9 AM to 5 PM, past the start-up and early enough to finish (`steady_state.py`):

| 12-hour normal day | arrivals an hour | charged within the contract's 30 minutes | wait p50 / p95 (min) | gate to leaving p50 / p95 (min) |
|---|---:|---:|---:|---:|
| 116 cars, seed 171717 | 20.4 | 134 of 144 (93%) | 5 / 35 | 70 / 150 |
| 116 cars, seed 424242 | 18.1 | 110 of 137 (80%) | 10 / 57 | 90 / 181 |
| 150 cars, seed 171717 | 21.8 | 141 of 167 (84%) | 10 / 55 | 85 / 165 |
| 116 cars with a third service bay, seed 171717 | 19.4 | 131 of 139 (94%) | 5 / 35 | 75 / 144 |
| **200 cars, seed 171717** | 25.8 | 97 of 155 (63%) | 20 / 145 | 105 / 225 |

The two seeds at 116 cars differ by as much as 116 and 150 cars do on one seed: one day per point is a reading, not a
curve. More seeds and whole days are running.

### The first wall is the two service bays, between 150 and 200 cars (12-hour days, seed 171717)

| | 116 cars | 150 cars | 200 cars | 250 cars |
|---|---:|---:|---:|---:|
| visits in the 12 hours / left ready by 6 PM | 292 / 253 | 324 / 272 | 379 / 282 | 410 / 296 |
| still in the depot at 6 PM | 39 | 52 | 97 | 114 |
| busy: service bays / charging posts / wash bays | 68% / 57% / 43% | 57% / 68% / 49% | **96%** / 77% / 56% | 89% / 75% / 71% |
| the wall the constraint board named most often | service bays | posts | **service bays** | **service bays** |
| 9 AM-5 PM arrivals charged within the contract's 30 minutes | 93% | 84% | **63%** | **58%** |
| 9 AM-5 PM gate to leaving, median / p95 (min) | 70 / 150 | 85 / 165 | 105 / 225 | 100 / 316 |
| fleet out at work / asked for by the work side (9 AM-5 PM) | 75.6% / 85.8% | 76.4% / 85.7% | 71.6% / 85.8% | 67.6% / 85.9% |

From 200 to 250 cars the depot let out 14 more cars in the 12 hours and held 17 more at 6 PM; under six in ten of the
day's arrivals got a charger within the contract's 30 minutes, the slowest twentieth took over five hours from the gate
to leaving, and the fleet out at work fell to 68% of the cars against 86% asked.

### A third service bay at 200 cars moves the wall to the posts (one day, seed 171717)

| 200 cars, 12 hours | two service bays | three service bays (`svc3`) |
|---|---:|---:|
| visits / left ready by 6 PM / still in the depot | 379 / 282 / 97 | 375 / 281 / 94 |
| busy: service bays / posts / wash bays | 96% / 77% / 56% | 80% / 78% / 62% |
| the wall the constraint board named most often | service bays (14 of 24 samples) | posts (15) |
| 9 AM-5 PM arrivals charged within the contract's 30 minutes | 97 of 155 (63%) | 123 of 171 (72%) |
| 9 AM-5 PM wait p50 / p95, gate to leaving p50 (min) | 20 / 145, 105 | 15 / 130, 95 |
| fleet out at work / asked (9 AM-5 PM) | 71.6% / 85.8% | 74.6% / 85.8% |
| post time lost to charger faults | 9.4% (19 faults) | 5.1% (16 faults) |

The third bay takes the service bays off the wall (96% to 80% busy) and the posts become it; the day's arrivals got
chargers sooner (63% to 72% within the contract wait) and the fleet out at work rose 3 points, but the 12 hours let out
the same number of cars, because what limits a 12-hour day is the 6 AM wave. And this day drew fewer charger faults (5.1%
of post time against 9.4%), so part of the gain may be the faults' luck, not the bay: one day each, a reading.
Charger faults are a capacity lever of their own: 5-13% of post time on these days (1.5-3.9 of the 30 posts, on
average), so a fault rate halved is worth about one to two posts.

From 150 to 200 cars the depot let out 10 more cars in the day and held 45 more at 6 PM; the two service bays ran 96%
busy, and a third of the cars arriving in the day waited past the contract for a charger. The posts' 77% is a day's
average of a different thing: read hour by hour on the 200-car day, the posts were charging 75-89% of every hour, and
charger faults took a further 9.4% of post time (2,024 post-minutes in 19 faults; 13.1% at 116 cars and 7.9% at 150, from
each faulted session to its repair), so what is left is the minutes between one car leaving a post and the next plugging
in. At midday (11 AM-2 PM arrivals, 26-34 an hour) the posts are full too, and that is when the waits come (a mean of 33-79
minutes). Whether a third service bay moves the wall is the next lab day
(`normal_day_200_171717_svc3`); the whole-day runs read the same curve past the start-up wave.
