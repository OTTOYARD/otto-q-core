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

Arrivals from 9 AM to 5 PM, past the start-up and early enough to finish (`steady_state.py`; **corrected 2026-11-06
06:12 UTC to wait from the gate**, the first reading, from the call home, in brackets: see "The queue wait runs from the
gate" below):

| 12-hour normal day | arrivals an hour | charged within the contract's 30 minutes, from the gate (from the call) | wait p50 / p95 from the gate (min) | gate to leaving p50 / p95 (min) |
|---|---:|---:|---:|---:|
| 116 cars, seed 171717 | 20.4 | 143 of 144, 99% (93%) | 0 / 20 | 65 / 145 |
| 116 cars, seed 424242 | 18.1 | 123 of 137, 90% (80%) | 0 / 50 | 85 / 165 |
| 150 cars, seed 171717 | 21.8 | 154 of 167, 92% (84%) | 0 / 39 | 80 / 160 |
| 116 cars with a third service bay, seed 171717 | 19.4 | 137 of 139, 99% (94%) | 0 / 16 | 70 / 139 |
| **200 cars, seed 171717** | 25.8 | 111 of 155, 72% (63%) | 10 / 140 | 100 / 220 |

The two seeds at 116 cars differ by as much as 116 and 150 cars do on one seed: one day per point is a reading, not a
curve. More seeds and whole days are running.

### The first wall is the two service bays, between 150 and 200 cars (12-hour days, seed 171717)

| | 116 cars | 150 cars | 200 cars | 250 cars |
|---|---:|---:|---:|---:|
| visits in the 12 hours / left ready by 6 PM | 292 / 253 | 324 / 272 | 379 / 282 | 410 / 296 |
| still in the depot at 6 PM | 39 | 52 | 97 | 114 |
| busy: service bays / charging posts / wash bays | 68% / 57% / 43% | 57% / 68% / 49% | **96%** / 77% / 56% | 89% / 75% / 71% |
| the wall the constraint board named most often | service bays | posts | **service bays** | **service bays** |
| 9 AM-5 PM arrivals charged within the contract's 30 minutes, from the gate (first reading, from the call) | 99% (93%) | 92% (84%) | **72%** (63%) | **60%** (58%) |
| 9 AM-5 PM gate to leaving, median / p95 (min; corrected, the first reading was from the call) | 65 / 145 | 80 / 160 | 100 / 220 | 90 / 310 |
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

Corrected 2026-11-06 06:12 UTC: the wait and the door from the gate (the first reading, from the call home, in brackets).

| fleet, seed | visits an hour | charged within the 30-minute contract wait, from the gate (from the call) | wait p50 / p95 from the gate | gate to leaving p50 / p95 | 1-7 PM out at work (asked 87%) | cars inside, 1-7 PM | service bays busy | posts busy |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 116, 171717 | 19.8 | 99% (91%) | 0 / 20 min | 80 / 481 min | 68% | 38 | 74% | 48% |
| 116, 424242 | 18.3 | 91% (78%) | 3 / 45 min | 95 / 475 min | 65% | 41 | 60% | 48% |
| 150, 171717 | 22.3 | 72% (62%) | 10 / 90 min | 90 / 488 min | 69% | 47 | 74% | 58% |
| 150, 424242 | 19.8 | 70% (64%) | 10 / 140 min | 135 / 580 min | 61% | 58 | 80% | 55% |
| 200, 171717 | 22.7 | 43% (39%) | 93 / 295 min | 135 / 690 min | 59% | 82 | 93% | 72% |
| 200, 424242 | 22.4 | 40% (37%) | 103 / 318 min | 160 / 713 min | 56% | 89 | 93% | 67% |

- **The depot handles about 19 to 23 visits an hour, and comfortably up to about 116 cars.** At 116 cars 91-99% of the
  cars that charge do so within the 30-minute contract wait from the gate, the median wait under 3 minutes and the
  95th percentile 20-45. At 150 cars the same depot takes 20-22 visits an hour and 70-72% are within the wait (the
  95th-percentile wait 1.5-2.3 hours); at 200 cars 22-23 an hour, 40-43% within it, a median wait of 1.5-1.7 hours and
  a 95th percentile about 5. (First reading, from the call home: 78-91%, 62-64% and 37-39%.)
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

**A third service bay, on whole days** (seed 171717, read 2026-11-06 05:27-05:31 UTC):

| | 150 cars, 2 bays | 150 cars, 3 bays | 200 cars, 2 bays | 200 cars, 3 bays |
|---|---:|---:|---:|---:|
| cars that left in the day | 466 | 488 | 464 | 474 |
| visits an hour, 9 AM-5 AM arrivals | 22.3 | 23.1 | 22.7 | 23.1 |
| charged within the contract wait, from the gate (from the call) | 72% (62%) | 62% (56%) | 43% (39%) | 43% (40%) |
| 1-7 PM out at work | 69% | 67% | 59% | 63% |
| service bays busy | 74% | 65% | 93% | 85% |
| the wall named most (of 48) | service bays 27 | posts 21 | service bays 37 | posts 24 |

A third bay lets 22 more cars out of the day at 150 cars (+4.7%) and 10 at 200 (+2.2%), and moves the wall to the posts at
both sizes; at 150 the cars it lets through then wait longer for a post (62% within the contract wait from the gate
against 72%; 56% against 62% from the call). So the depot's next 50 cars need the posts as well as the bays: a third bay alone buys a few percent. One seed each.

### The queue wait runs from the gate, not from the call home (corrected 2026-11-06, read 06:12 UTC)

Every wait in this file before 2026-11-06 06:12 UTC was measured from the moment the visit opened to the car's plug-in.
**A visit opens when the car is called home, not when it reaches the gate.** On the 116-car 12-hour day (seed 171717,
`ottoq_cap_normal_day_116_171717`, run `d6955d8e`) 228 of 292 visits open while the car is driving home, 38 at the gate
and 26 on a charger (the boot); the 225 that reach the gate before leaving take 10.1 minutes to get there on average, 5
at the median and up to 60. The only way into the depot from the road is the gate (`en_route_to_depot` ->
`arrived_at_gate`, 498 of 505 such transitions on the 150-car whole day; the other 7 go offline). The contract's limit is
the wait in the depot's charge queue: the engine holds a car against it with its own wait clock
(`ottoq_contract_queue_wait_min` against `ottoq_charge_wait_min`), which starts at the gate. So the first readings
counted the drive home as queueing, which understated how many cars charge within the contract wait.

`steady_state.py` and `capacity_day.py` now read the wait from the car's first arrival at the gate after the call and
not after it left (a car already in the depot when its visit opened is at the gate from the start); both keep the first
measure beside it (`*_from_call`, `wait_*`), and `steady_state.py` reads the door from the gate (`gate_door_*`) beside
the scorecard's own door, which runs from the call. The tables above are corrected in place, the first readings in
brackets. What moved:

- **116 cars: 91-99% charge within the contract wait from the gate** (78-91% from the call), the median wait under 3
  minutes. The depot serves 116 cars comfortably.
- **150 cars: 70-72%** (62-64%); **200 cars: 40-43%** (37-39%). The curve still bends between 116 and 150 cars; the
  drive home is 7-10 minutes a visit, so the correction matters most where the waits are short.
- The "gate to leaving" columns were the scorecard's door from the call; they are now from the gate (5-15 minutes
  shorter at the median).

Nothing in the engine reads these figures: the error was the research wing's, in two readers, and it was found tracing
why short charges seemed to wait as long as long ones (they did not; much of their "wait" was the drive). The same
error was in the perfect-day model (`lab/research/p2_perfect_day/`), which let work start at the call.
