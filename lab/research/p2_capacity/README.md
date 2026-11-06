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

### While cars wait for a charge, a working post is almost never free (three lab days)

`post_idle_while_waiting.sql` rebuilds every post and every waiting car tick by tick (posts from `stall.state_changed`,
cars from `vehicle.state_changed`): the cars parked or at the gate whose charge has not begun, against the posts with no
car, no reservation and no session, split by whether the post's last session ended in a fault. Read 2026-11-06 between
03:49 and 03:50 UTC, with same-tick events in the order they were written (`event_seq`; a first read at 03:19-03:24
ordered them by `event_id`, a random uuid, and read 115-245 free post-minutes past the first tick).

| day | car-minutes parked or at the gate before the first charge | post-minutes free after a fault while a car waited | post-minutes free, no fault, while a car waited (of them, the day's first tick) |
|---|---:|---:|---:|
| 116 cars, 12 h, seed 171717 | 3,330 | 800 | 200 (150) |
| 150 cars, 12 h, seed 171717 | 6,015 | 1,130 | 215 (150) |
| 116 cars, 24 h, seed 171717 | 3,820 | 965 | 220 (150) |

Past the first tick (38 to 49 cars at the gate and all 30 posts free), a working post stood free while a car waited one or
two posts at a time, 50 to 70 post-minutes a day: the engine seats a car on a working post almost as soon as it frees.
The posts that stood free while cars waited were posts whose charger had faulted, until the repair (counted to the next
car plugging in, so an upper bound). So at the posts the perfect day's gain (E5: rescheduling only the posts takes 24,332
car-minutes to ready to 18,614 at 116 cars) is the order in which cars get a post, not posts left idle, and charger faults
are the posts' loss. A first pass of this measure read 2,500 post-minutes "empty while cars waited" at 116 cars: it counted
cars still driving home (a visit opens when the car is called, before it arrives) and posts in repair as free.

### The exit-first charge key, off for a day (one day, seed 171717)

`normal_day_116_171717_exit0` is the 116-car 12-hour day with `charge_order_exit_first` at 0 (0781's key, which within each
owner's own cars charges first those whose charge is their way out), against the same day with the twin depot's setting:
257 cars left against 253, 34 of 77 cars with a due time on time against 38 of 85, and from 9 AM to 5 PM 92% charged within
the contract wait against 93%, gate to leaving 70 minutes at the median either way (read 2026-11-06 04:31 UTC). The owners'
rows move further (Waymo 103 cars left against 95, Zoox 71 against 74), but a change re-draws the day after the first
returns, so one day each cannot separate the key from the draw: no case to change the setting on this.

### A lab day commits after every tick (2026-11-06)

Until now a lab day ran in one transaction with a savepoint a tick, and its late ticks slowed as the day's row versions
and subtransactions piled up: a 24-hour 150-car day took 9,252 s, while the same engine's tick at that day's end, in a
fresh transaction, took 474 ms. `capacity_day.py` now commits after the set-up and after every tick, as production does
(`--one-transaction` keeps the old mode). Checked before any other day used it: normal_day, 116 cars, seed 424242, run
both ways, gives the same four fingerprints (`day_fingerprint.sql`: energy commands `580be767`, snapshots `bd8fc12d`,
sessions `c33289e1`, visits `c9e50316`) in 414 s against 1,080 s, beside three other running days (read 2026-11-06
04:38 UTC). A container restart still redoes the whole day: the replica is cloned anew and the results file is written at
the end.

### The capacity curve on whole days (2026-11-06; read between 04:55 and 05:17 UTC)

Normal days of 24 hours from 6 AM CT, the twin depot as built (30 fast-charger posts, 2 service bays, 3 wash bays), two
seeds a fleet size. Arrivals from 9 AM to 5 AM next day (`steady_state.py --skip-h 3 --tail-h 1`, G520's phantom visits
left out); afternoon fleet out read hour by hour (`uptime_by_hour.sql`, distinct cars); resources over the whole day from
the lab day's own record.

| fleet, seed | visits an hour | charged within the 30-minute contract wait | wait p50 / p95 | gate to leaving p50 / p95 | 1-7 PM out at work (asked 87%) | cars inside, 1-7 PM | service bays busy | posts busy |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 116, 171717 | 19.8 | 91% | 5 / 35 min | 85 / 490 min | 68% | 38 | 74% | 48% |
| 116, 424242 | 18.3 | 78% | 15 / 60 min | 105 / 485 min | 65% | 41 | 60% | 48% |
| 150, 171717 | 22.3 | 62% | 20 / 95 min | 100 / 495 min | 69% | 47 | 74% | 58% |
| 150, 424242 | 19.8 | 64% | 20 / 151 min | 140 / 585 min | 61% | 58 | 80% | 55% |
| 200, 171717 | 22.7 | 39% | 98 / 310 min | 140 / 718 min | 59% | 82 | 93% | 72% |
| 200, 424242 | 22.4 | 37% | 110 / 330 min | 165 / 720 min | 56% | 89 | 93% | 67% |

- **The depot handles about 19 to 23 visits an hour, and comfortably up to about 116 cars.** At 116 cars 78-91% of the
  cars that charge do so within the 30-minute contract wait, the median wait 5-15 minutes. At 150 cars the same depot
  takes 20-22 visits an hour and 62-64% are within the wait (the 95th-percentile wait 1.5-2.5 hours); at 200 cars 22-23
  an hour, 37-39% within it, a median wait over 1.5 hours and a 95th-percentile over 5.
- **More cars still put more cars to work, by less each time.** Out at work in the afternoon: about 77 cars at 116,
  98 at 150 and 115 at 200, against the work side's ask of 87% of the fleet (101, 131, 174). The mornings keep up at 116
  and 150 (80-84% out against 85%); at 200 they fall to 74-78%.
- **The wall is the two service bays.** The constraint board names them in 20 to 39 of each day's 48 half-hour samples,
  and at 200 cars they are 93% busy over the whole day, nights included; the posts are 67-72% busy then, full at the
  afternoon peak. Charging to 100% (rule 9) and the posts' fault repairs set the rest (see the post-time section above).
- **The busy day is a stress test of the bays, and they fail it at today's 116 cars.** `busy_day` (diagnostic trouble
  codes at 7 times the rate, 85% of cars starting soiled) at 116 cars, 12 hours: by noon 96 cars sit charged (99-100%)
  waiting for the two service bays, 71 owing mechanical preventive maintenance and 37 a sensor calibration, which no car
  leaves without (rule 9); 111 of the 116 cars are still in the depot at 6 PM, and 147 of 150 at 150 cars. The demo runs
  at the twin depot run this scenario.

Two seeds a size and one depot build: a reading of where the curve bends, not a range. The levers it points to, none of
them a lever on a vehicle (rules 9 and 13): a third service bay (on a 12-hour day at 200 cars it moved the wall to the
posts, above), fewer charger faults, and the order in which cars get a post (the perfect day, E5).
