# The gap to the perfect day (frontier plan E5, first cut)

E5 in `docs/FRONTIER_PLAN_2026-11-03.md`: *"For each finished twin run, a CP-SAT solve with perfect hindsight ... It takes
the run's realized arrivals, faults and durations and produces the best achievable day. That day is a bound."* It is the
first absolute measure the research wing has: not "better than yesterday's engine" but "how far from the best any engine
could have done", per day and per owner. This cut runs on the lab's finished days (`lab/research/p2_capacity/`), whose
replicas keep every row of the run.

| file | what |
|---|---|
| `bound_ops.py` | the operations bound: CP-SAT (OR-Tools 9.15.6755, the CP-SAT service's pin) schedules every visit's place-holding work (its charge on a post, its bay work by lane) with perfect hindsight; three measures, each its own solve and bound (minutes in the depot, cars ready by their due time, minutes past the contract's queue wait); per owner (`--owners`) and with the regret split by lane (`--split`: bays held at the kernel's starts, then posts held) |
| `bound_energy.py` | the battery's bound: the cheapest bill with perfect foresight of the day's load (GLOP), priced as the battery's own day plan prices it (0435), beside the real plan's bill and the bill with no battery |

## How to read a bound

- A bound is a number no schedule can beat on that day's arrivals: if the kernel's day is at the bound, there is nothing
  left to win by deciding better, and the next gain is capacity, arrivals or rules (the frontier plan's E5 "why").
- The model relaxes the engine's own job order (a car's charge and bay work in any order), the technicians' pool and the
  staging spaces, so the bound can only be optimistic. A gap that survives the relaxation is real; a gap that the
  relaxation creates is not, and the per-lane split says where the gap sits.
- The arrivals are held as they happened. In a real depot a car that left sooner would also come back sooner; the bound
  is for this day's arrival stream.
- The battery's bound holds the cars' charging as it was (rule 13: the vehicles' needs set the load) and measures the
  battery's planning only.

## What it found

### Correction 2 (2026-11-06, solved 06:06-06:46 UTC, the last set 06:29-06:46): released at the gate, the service bays' whole load, a tick's readiness check, and the owners' immediate turnarounds kept first

Tracing why short charges seemed to wait as long as long ones on the lab days (they did not: much of their "wait" was
the drive home), the model turned out to hand the solver time the depot never had in four more places, and to ignore a
rule in a fifth. Every number in this file before this section is the earlier models'.

1. **It let work start at the call home.** A visit opens when its car is called home, not when it reaches the gate: on
   the 116-car day 228 of 292 visits open while the car drives, 10 minutes on average and up to 60. The solver could
   plug a car in while it was still on the road. Now no job starts before the car's first arrival at the gate after
   the call, and the contract wait (the `wait` measure) runs from there. The capacity readers carried the same error
   (G522, `lab/research/p2_capacity/README.md`).
2. **It dropped bay work no atom names.** A service booking carries no `need_atom`, and the needs card sends a car with
   an open trouble code (severity 3 or worse) to a service bay for a fault repair its visit's atoms do not list.
   Matched only to atoms, the model dropped 184 of 980 booked service-bay minutes at 116 cars and 344 of 824 at 150: a
   wall freer than the real one. Now every bay booking a visit held is a job.
3. **It closed a visit 3 minutes after its last job**, the readiness check's estimate, where 199 of the 234 visits that
   left the 116-car day were ready exactly 5 minutes after it (one tick). Now 5 (`--ready-min`).
4. **It let a visit with no place-holding work leave at its call.** Now every visit reaches the gate and passes its
   check.
5. **It let the solver plug in an owner's immediate dispatch later than the kernel did**, which rule 9 does not allow:
   an owner's immediate turnaround is honoured as asked, and the kernel serves it first. On the 116-car day the best
   schedule found plugged 11 of 81 in later, 618 minutes in all. `--immediate-first` holds every immediate dispatch to
   no later than the kernel served it.

Each correction applied on top of the ones before it, engine order, four workers, 120 s a solve (`bound_ops.jsonl`;
the published row's 116-car solve ran 180 s):

| minutes to ready, best found / proven bound | 116 cars, seed 171717 (real 24,332) | 150 cars, seed 171717 (real 29,100) |
|---|---:|---:|
| the published model (the car's time on its post, from the call) | 18,939 / 16,673 (-22% / -31%) | 23,546 / 19,428 (-19% / -33%) |
| ... immediates kept first (rule 9) | 19,286 / 16,750 | 24,193 / 19,724 |
| released at the gate (without rule 9's hold) | 20,694 / 18,640 | 25,495 / 21,447 |
| ... and every bay booking a job | 21,019 / 19,017 | |
| ... and a tick's readiness check, every visit through the gate | 21,805 / 19,810 (-10.4% / -18.6%) | 26,670 / 22,572 (-8.4% / -22.4%) |
| **all five (rule 9's hold too)** | **21,977 / 19,911 (-9.7% / -18.2%)** | **27,012 / 23,026 (-7.2% / -20.9%)** |
| all five, and no owner worse than the real day | 22,035 / 19,862 | none found in 120 s (UNKNOWN, not proven infeasible) |
| minutes past the contract wait from the gate: real / best / bound | 2,740 / 1,394 / 305 | 3,665 / 2,520 / 250 |

The first row's 150-car figures are the published model re-solved on four workers (published from two: 23,506 /
18,935). The 150-car "every bay booking" step was not solved on its own.

**What it says now.**

- **The room better decisions could win is about a tenth, not a fifth.** At 116 cars the best day found under rule 9
  is 9.7% better and no schedule can be more than 18% better; at 150 cars 7.2% better found and no schedule more than
  21%. The published reading (22% and 19% found, a third at most) is withdrawn. At 116 cars holding every owner to no
  worse still costs nothing (22,035); at 150 cars the solver found no such day in 120 s, which is not a proof that none
  exists.
- **At 116 cars most of it is the lab day's start-up.** A lab day begins at 6 AM with the whole fleet at the depot,
  which no overnight operation would ask of a depot (`lab/research/p2_capacity/README.md`). The cars that reached the
  gate in its first two hours carry 1,447 of the 2,355 minutes at 116 cars (13.8% of theirs), the rest of the day 908;
  at 150 cars the halves are even, 967 (8.0%) and 1,121. **Past the start-up the kernel is within 6.6% of the best day
  found, at both sizes** (`regret_split.py`, rule 9's hold on).
- **Where it sits** (116 cars, rule 9): waiting for a post 3,527 minutes real against 2,577 solved, for a service bay
  744 against 327, for a wash bay 655 against 32; at 150 cars 5,591 against 5,136, 279 against 75 and 1,152 against
  55. The solved day serves short and middle charges sooner (standard
  charges under 20 minutes wait 2 minutes from the gate instead of 12, 20-40 minutes 4.5 instead of 17, 40-60 minutes 10
  instead of 26) and long ones a little later (60-90 minutes 27 instead of 21, over 90 minutes 37 instead of 34); every
  owner waits less on average (at 150 cars the same shape: under 20 minutes 12 to 3, 20-40 minutes 25 to 10, over 90
  minutes 57 to 62). On the bays the real day's waits are a handful of long ones (five service-bay waits of 90
  to 170 minutes hold 680 of the 744; eight wash waits of 30 to 135 minutes about 420 of the 655), one of them a car
  owing a fault repair and a deep clean that waited for a full service bay while a wash bay stood free (G523).
- **The charge line's tie at the 6 AM boot decides no seat.** At the boot clock every waiting car has waited 0 minutes,
  so the kernel's ratio ties and the line falls back to lowest battery first; but the first tick runs 5 minutes in, when
  every boot car has waited and the ratio already favours short charges (on the 116-car day the first tick seated the 11
  immediate dispatches at the boot, then the rest from the shortest charge up, 16 to 47 minutes). Rehearsed before building anything, as the
  standing rule asks: not built.

### Correction (2026-11-06): a car holds its post after its charge, and the first model did not count it

The first solves below gave each charge its session's length on a post. On the lab days a car stays on its post until
the robot has unplugged it, about a tick after the session ends: 4.8 minutes a charge on average, 10% more post time
(12,470 session minutes against 13,740 post minutes at 116 cars; 14,945 against 16,375 at 150). So the first model
let a post take its next car sooner than the depot can, and its perfect day was too good. `bound_ops.py
--post-occupancy` gives each charge the minutes its car held the post (`SESSIONS_OCC_SQL`, from the stall's own
pointer). Solved like for like (engine order, door, one worker, 120 s; read 2026-11-06 03:30 UTC):

| 116 cars, seed 171717, minutes to ready | best found | proven bound |
|---|---:|---:|
| the real day | 24,332 | |
| first model (session on the post) | 18,043 (-25.8%) | 14,915 (-38.7%) |
| **the car's time on the post** | **20,055 (-17.6%)** | **16,185 (-33.5%)** |

| 150 cars, seed 171717, minutes to ready (read 2026-11-06 03:35 UTC) | best found | proven bound |
|---|---:|---:|
| the real day | 29,100 | |
| first model (session on the post) | 22,333 (-23.3%) | 17,505 (-39.8%) |
| **the car's time on the post** | **25,188 (-13.4%)** | **18,935 (-34.9%)** |

The gap is real and smaller: the best day found is 13-18% better, not the 28-30% the first model's solves found, and no
schedule can be more than a third better (33-35%). The first model's reading that the room does not shrink as the
depot fills is withdrawn: found, it fell from 17.6% at 116 cars to 13.4% at 150, while the bound held at a third; one
worker for 120 s is a weak search on the larger day, so neither says yet how the room moves with the fleet. What the first model said about owners (holding each to no
worse cost the best day almost nothing) and about where the gap sits (the charging posts' share is the larger) is
re-solved on the corrected model below; the tables after it are the first model's.

Re-solved on the corrected model, engine order, two workers, 120 s a solve (read 2026-11-06 05:35 UTC, `bound_ops.jsonl`):

| corrected model | 116 cars, seed 171717 | 150 cars, seed 171717 |
|---|---:|---:|
| minutes to ready: real / best found / proven bound | 24,332 / 18,991 (-22%) / 16,188 (-33%) | 29,100 / 23,506 (-19%) / 18,935 (-35%) |
| the same with no owner worse than the real day | 18,966 / 16,185 | 23,483 / 18,935 |
| due cars ready by their due time, real / best | 38 / 46 of 93 | 18 / 35 of 89 |
| minutes past the contract wait, real / best on its own / bound | 3,365 / 1,199 / 159 | 4,290 / 2,220 / 34 |
| each owner's own best (others free): Tesla / Waymo / Zoox | -33% / -29% / -40% | -32% / -32% / -42% |

Holding every owner to no worse still costs nothing, so that reading of the first model stands. Its lane split does not
carry over: holding either lane at the kernel's own starts, with each charge's real time on its post, is infeasible (the
real starts and the longer post times together overrun the posts at moments the session lengths hid), so which lane
carries more of the gap is not read on the corrected model; the post-idle measure says the posts' share is ordering.
And on the posts the gain is the order in which cars get one, not posts left idle: a working post almost never stood
free while a car waited (`lab/research/p2_capacity/post_idle_while_waiting.sql`).


### The first lab day (solved 2026-11-05 22:05-22:21 UTC = 4:05-4:21 PM CT)

normal_day at the twin depot as built today, 116 cars, seed 171717, 12 hours from 6 AM CT at 5-minute ticks, production's
engine (`ottoq_cap_normal_day_116_171717`, run `d6955d8e`); 292 visits. CP-SAT 120 s per solve, 4 workers, on a loaded
machine (so "best found" can still improve; the bound cannot be beaten).

| minutes from arrival to ready, all cars | real day | best found | proven bound |
|---|---:|---:|---:|
| any job order (relaxation) | 24,332 | 16,687 | 15,079 |
| the engine's own job order (a fault repaired first, else charge before bays) | 24,332 | 17,154 | 15,307 |
| the engine's order, and **no owner worse than the real day** | 24,332 | 17,057 | 15,354 |

| owner, minutes to ready | real day | the fair perfect day (no owner worse) | that owner's own best (others free) |
|---|---:|---:|---:|
| Tesla Robotaxi TN | 6,710 | 4,463 (-33%) | 4,053 |
| Waymo Nashville | 11,890 | 8,941 (-25%) | 7,946 |
| Zoox Southeast | 5,732 | 3,653 (-36%) | 3,063 |

- **The gap is not a trade between owners.** Holding every owner to no worse than the real day costs the perfect day
  almost nothing (17,057 against 17,154 found unconstrained): every owner can be a quarter to a third better at once. The
  agent's per-tick reorders, judged in hindsight, mostly traded owners (G511, G512, G515); a whole-day schedule made with
  foresight does not have to.
- **Contract waits:** minutes past the 30-minute queue wait, 3,365 on the real day, 1,116 on the fair perfect day, 839 at
  best on that measure alone (engine order; bound 231).
- **Due times:** at most 48 of the 93 cars with a due time can be ready by it (38 were). The other 45 were due sooner than
  their own work takes, which no schedule fixes: that is the work side's demand, read against the depot's real durations.
- **Where the gap sits** (any order): holding the bays where the kernel put them and rescheduling only the charging posts
  reaches 18,614; holding the posts and rescheduling only the bays reaches 20,796. The charge line carries the larger share.
- A car that finished its work waited a total of 1,318 minutes for the work side to send it (24,332 to ready against
  25,650 to dispatch): small, and not the depot's to schedule.

The battery on the same day (`bound_energy.jsonl`; each policy pays for its own highest half hour at the daily share of
the monthly demand charge):

| 12-hour normal day, 116 cars | half-hour peak | bill |
|---|---:|---:|
| no battery | 1,679 kW | $1,699 |
| the battery's day plan (`energy_reserve_shave` 1, what the twin depot runs; G370) | 1,160 kW | $1,382 |
| the same day with `energy_reserve_shave` 0 (the older fixed-target rule) | 2,336 kW | $2,225 |
| perfect foresight of the day's load | 735 kW | $1,085 |
| rolling plans seeing the next 1 / 2 / 4 hours exactly, the load held flat beyond | | $1,515 / $1,550 / $1,535 |

The older rule charges the battery into the peak and does worse than no battery; the day plan saves $843 against it on
this day. The car side of the two days is identical (every visit, every seat): the setting changes only the energy. A
first cut of this tool read the month's billed peak from the day's first snapshot, which already holds the first tick's
draw; under the older rule that hid most of its own peak (it charges hard at 6 AM). Every bill above is computed with
nothing billed before the day.

The rate is the twin depot's tariff for a September day, NES GSA-3 summer: $21.40 per kW of the month's highest half hour,
so a day pays 1/30 of $21.40 per kW of its own highest half hour (`ottoq_depot_tariffs`; $20.34 is the winter and
transition rate, and P2's first published metrics named it by mistake: the dollars were computed at $21.40). The tool
applies the first-block rate to the whole peak; NES bills the kW above 1,000 at $21.78, about $8.60 a day more at a
1,679 kW peak, for every policy whose peak is over 1,000 kW.

### Across the lab's days so far (the engine's own job order)

| day | visits | minutes to ready, real | best found | proven bound | no owner worse, best found | due cars ready by due, real / best | minutes past the contract wait, real / best on its own |
|---|---:|---:|---:|---:|---:|---:|---:|
| 116 cars, seed 171717 (4 workers) | 292 | 24,332 | 17,154 (-30%) | 15,307 (-37%) | 17,057 | 38 / 48 of 93 | 3,365 / 839 |
| 116 cars, seed 424242 (2 workers) | 269 | 25,015 | 17,765 (-29%) | 15,390 (-38%) | 17,802 | 17 / 39 of 84 | 3,565 / 378 |
| 150 cars, seed 171717 (2 workers) | 324 | 29,100 | 20,993 (-28%) | 17,505 (-40%) | 20,950 | 18 / 39 of 89 | 4,290 / 1,459 |

Each owner's own best on the second 116-car day (others free): Tesla 7,700 to 4,553 (-41%), Waymo 11,630 to 7,964 (-32%),
Zoox 5,685 to 3,098 (-46%) (`bound_ops.jsonl`, written 2026-11-06 00:19:18 UTC). Three days, two seeds: the gap is about
the same each time, 28-30% found and 37-40% to the bound, and holding every owner to no worse never costs more than 0.3%.

### At 150 cars (one day, seed 171717; solved 2026-11-05 23:45-23:56 UTC = 5:45-5:56 PM CT)

normal_day at 150 cars (`ottoq_cap_normal_day_150_171717`, 324 visits, 20 charger faults), the engine's own job order,
CP-SAT 120 s per solve on 2 workers beside four running lab days (so "best found" is weaker than at 116 cars, where it
had 4 workers on a quieter machine; the bound is still a bound).

| minutes from arrival to ready | real day | best found | proven bound |
|---|---:|---:|---:|
| all cars, the engine's own job order | 29,100 | 20,993 (-28%) | 17,505 (-40%) |
| the same, and no owner worse than the real day | 29,100 | 20,950 | 17,505 |

| owner, minutes to ready | real day | that owner's own best (others free) |
|---|---:|---:|
| Tesla Robotaxi TN (160 visits) | 12,430 | 7,630 (-39%) |
| Waymo Nashville (97 visits) | 11,090 | 7,129 (-36%) |
| Zoox Southeast (67 visits) | 5,580 | 2,918 (-48%) |

- The gap holds its size as the depot fills: 28% found at 150 cars against 30% at 116 (engine order), and the bound is
  40% under the real day against 37%. Holding every owner to no worse still costs almost nothing (20,950 against 20,993).
- Due times: at most 39 of the 89 cars with a due time can be ready by it (18 were). Minutes past the 30-minute contract
  wait: 4,290 on the real day, 1,459 found on that measure alone.
- The fleet was grown by cloning the twin's own cars round-robin, so the owner mix at 150 cars is not the 116-car mix
  (Tesla's cars carry 160 of the 324 visits): per-owner figures compare within a day, not across fleet sizes.

### A typical day's shape is most of the battery's prize (two lab days; the last solve written 2026-11-05 5:22 PM CT)

A second lab day, normal_day at 116 cars with seed 424242 (`ottoq_cap_normal_day_116_424242`, run `663d217a`), gives each
day a forecast that is not the day itself: the other day's load, five minutes by five minutes, as the shape of the rest of
the day. The plan re-solves every five minutes on what has actually happened, sees the coming load only through that shape,
and pays the bill the true load makes (`bound_energy.py --forecast-db`). The two days' loads differ by 217 kW on average
per five minutes, so the shape is a rough forecast, not a copy.

| 12-hour normal day, 116 cars (half-hour peak) | seed 171717 | seed 424242 |
|---|---:|---:|
| no battery | $1,699 (1,679 kW) | $1,499 (1,475 kW) |
| the battery's day plan, as the twin runs it | $1,382 (1,160 kW) | $1,543 (1,475 kW) |
| re-planned every 5 minutes, the load now held flat | $1,583 | $1,351 |
| the next hour exactly, flat beyond | $1,515 | $1,378 |
| the next 4 hours exactly, flat beyond | $1,535 | $1,313 |
| **a typical day's shape (the other day)** | **$1,152 (813 kW)** | **$1,243 (1,059 kW)** |
| the next hour exactly, then the typical shape | $1,135 (798 kW) | $1,207 (1,010 kW) |
| perfect foresight | $1,085 (735 kW) | $1,098 (850 kW) |

- **The shape of the day is the money, and a rough one is enough.** Planned on another day's shape, the battery's bill
  closes 77% of the gap between the day plan and perfect foresight on the first day ($230 of $298) and 67% on the second
  ($300 of $445). Seeing the next hours exactly and nothing beyond does far worse, on both days. The day plan as it runs
  also holds the two reserves of G517 below and these plans hold neither, so part of each gap is the reserves, not the
  forecast: the lab's what-if days split the two.
- **On the second day the day plan did not lower the peak at all** (1,475 kW with and without the battery). The battery
  started the day 25% full, and the day's highest draw came in its first ten minutes (2,226 kW at 6:10 AM CT, as the boot
  cars plugged in). The battery never discharged that day: its $44 over no battery is the energy it bought to fill itself
  from 25% to 50% (some of it the panels' midday surplus), not money lost. Why it did not discharge is G517 below: it
  was holding a reserve for a demand-response call that never came.
- Every plan above ends the day at least as full as the real battery did (2,702 kWh on the first day, 1,508 on the
  second); the no-battery bill does not pay for the energy the real battery stored, so it is slightly flattered.
- Two days, one forecast each way: a reading, not a range. These rolling plans are linear programs that plan the
  battery's refill along with its discharge; the twin's day plan does not (it decides each recharge on its own). So the
  forecast's worth here is the forecast's worth to such a planner, and the next section measures what the same shape is
  worth to the day plan as it runs: nothing, on these days.

### G517: two reserves keep a battery under about half full out of the morning surge

Two reserves stand between the battery and a discharge, and the plan records both every tick (`ottoq_energy_commands`,
`bess_setpoint_kw`: the plan's mode, the energy it may use, the reserve it holds):

1. **The demand-response reserve, held from the first minute of the day.** In summer the day plan holds 600 kWh
   (`bess_plan_dr_reserve_kwh`) for a possible demand-response call between 2 and 8 PM, at every step before the window,
   and while the battery holds less than that above its floor the plan is `reserve_protected` and does not discharge at
   all. The reserve has a vehicle purpose: during a call the cars may charge on what the battery can sustain
   (`ottoq_ev_charge_allowance_kw`), so a full reserve keeps a call from slowing them.
2. **A floor that rises at every surge.** The plan's floor is the battery's own (10%) plus 20 points times
   `ottoq_forecast_uncertainty`, the spread of the last 40 minutes of EV charging, which reads 1.0 from the first tick after
   a surge begins (read back on both lab days at 6:15, 6:25 and 6:35 AM CT), plus 3 points: 33% through every surge's
   first half hour.

So before 2 PM a battery needs about 33% to discharge at all, and about 53% during a surge. On the second day it started
24.5% full. At 6:10 AM CT, when the day's highest draw began (2,226 kW at the meter), the plan read 340 kWh it could use
against the 600 kWh reserve and held; from 6:15 the rising floor made it 0. It held for 30 ticks and never discharged that
day. On the first day it started 71% full and shaved, but at 6:15, holding about 1,660 kWh above its floor, the two
reserves left it 388. No demand-response call came on either day (`ottoq_dr_calls`).

Needed only from 2 PM, the same reserve costs nothing in hindsight on either day: with `--dr-reserve-kwh 600`, perfect
foresight is $1,085 and $1,098 exactly as without it, and the typical-day plans pay $0 and $3 more ($1,152 and $1,246).
The battery refills well before the window anyway (on the second day from 25% to 52% between 8 AM and 1 PM, without trying).

What the reserves cost on the second day, measured with the plan as it runs: the same day (seed 424242, 116 cars)
re-run in the lab with one reserve or both switched off (`lab/research/p2_capacity/`, tags `dr0`, `res0`, `dr0res0`;
`whatif_table.py`, read 2026-11-06 00:03 UTC = 6:03 PM CT on 11-05). Every car-facing scorecard line is identical across
the four days: the battery's plan never limits a car. The days end with different energy stored, so each bill is also
given at the base day's end state (the difference valued at the plan's own replacement cost, $0.070 per kWh).

| the second day (seed 424242) | half-hour peak | bill | stored at day end | bill at the base day's end state |
|---|---:|---:|---:|---:|
| the day plan as it runs (both reserves) | 1,475 kW | $1,543 | 1,508 kWh | $1,543 |
| the demand-response reserve off (`dr0`) | 1,354 kW | $1,538 | 2,691 kWh | $1,455 |
| the rising floor off (`res0`) | 1,475 kW | $1,601 | 2,362 kWh | $1,542 |
| both off (`dr0res0`) | 1,132 kW | $1,370 | 2,491 kWh | $1,301 |
| no battery | 1,475 kW | $1,499 | | |
| perfect foresight, the reserve needed from 2 PM | 850 kW | $1,098 | 1,508 kWh | $1,098 |

- **The first day too** (seed 171717, the battery 71% full at 6 AM; `dr0res0`, read 2026-11-06 00:56 UTC): both reserves
  off take the half-hour peak from 1,160 to 1,032 kW and the bill from $1,382 to $1,295 at the same end state, $88 of the
  $298 gap to perfect foresight, every car-facing line identical. So the reserves cost money on both days, most when the
  battery starts low ($242 on the second day).
- **Either reserve alone hides the other.** The rising floor off changes nothing while the demand-response reserve still
  holds the battery ($1 at the same end state); the reserve off saves $88; both off save $242 and take the peak from 1,475
  to 1,132 kW, 54% of the gap to perfect foresight ($242 of $445). No demand-response call came, so on this day both
  off is what "the reserve needed only from 2 PM" would have done, with nothing to refill against.
- The rest of the gap ($203) is the plan's forecast and its algorithm, and the forecast what-if says which: see below.

### The day plan given a typical day's shape moves nothing (2026-11-06 00:30 UTC = 6:30 PM CT on 11-05)

The same two days re-run with the day plan's EV forecast floored at the other day's EV charging, half hour by half hour
(`make_shape_whatif.py`, tags `shape` and `shape_dr0res0`; every car-facing line identical again):

| | half-hour peak | bill at the base day's end state |
|---|---:|---:|
| first day, the day plan as it runs | 1,160 kW | $1,382 |
| first day, the day plan with a typical day's shape | 1,159 kW | $1,382 |
| second day, both reserves off | 1,132 kW | $1,301 |
| second day, both reserves off, with a typical day's shape | 1,132 kW | $1,301 |

The shape took effect (the plan's forecast peak at 10 AM rose from 339 to 1,052 kW on the first day) and changed no
action. On both days the billed half hour is the 6 AM start-up surge, and it is set before the rest of the day's forecast
can matter: after it, the forecast peak sits under the peak already billed, so the plan's level and every charge and
discharge stay as they were. What decides the bill is how deep the battery may go into that first surge, which is the two
reserves, and whether the plan dares spend into it knowing it can refill later, which a linear program over the day does
and the day plan does not.

So the order of the battery's build is: the reserves first (G517, measured with the plan as it runs; built as 0797 and
on at the twin depot since 8:57 PM CT on 2026-11-05, `lab/research/p2_capacity/g517_lab_2026-11-06.md`), then a planner
that plans its own refill (the rolling linear program in `bound_energy.py`, held to the 600 kWh reserve from 2 PM), and
a forecast of the day's shape inside that planner, where it is worth something (on the first day the same planner went
from $1,583 with the load held flat to $1,152 with the shape). The first day's reserves are being measured the same way
(`dr0res0` on seed 171717).

### The battery planned as a linear program inside the engine's loop (2026-11-06, `battery_lp.py`)

Every tick, before the engine runs it, GLOP plans the rest of the day on the other day's load shape (the plan is made
before the tick, as an outside service's would be, so it cannot see the step's own load), holds the 600 kWh reserve from
2 PM, and the engine follows its first step through the MPC bridge it already has (`energy_mpc_follow` = 1); the rising
floor is fixed (`res0`). Every car-facing line identical on both days.

| at the base day's end state | first day (71% full at 6 AM) | second day (25% full) |
|---|---:|---:|
| the day plan as it runs | $1,382 (1,160 kW) | $1,543 (1,475 kW) |
| the day plan, both reserves off (`dr0res0`) | $1,295 (1,032 kW) | $1,301 (1,132 kW) |
| the LP in the loop, first cut (`lp`) | **$1,611 (1,457 kW)** | $1,319 (1,148 kW) |
| perfect foresight | $1,085 (735 kW) | $1,098 (850 kW) |

**The first cut ratcheted its own peak on the first day.** It handled the 6 AM surge, then planned to the edge of the peak
already billed (1,128 kW): charging is free of demand charge under it, so it charged at up to 1,500 kW wherever its
forecast saw room. At midday that forecast was 250-400 kW under the real load (the other day's shape), each half hour came
in over the billed peak, and each new peak became the next tick's headroom: 1,128, 1,164, 1,276, 1,321, 1,342, 1,359 and,
by 12:30, 1,457 kW. The day plan does not do this because it recharges only under its level less a margin (0435) and never
lifts a half hour above the billed peak (0600). So `battery_lp.py` now keeps the same two guards: the next 30 minutes are
never forecast under what the depot drew last, and a half hour wholly in the future is planned to stay
max(100 kW, 10% of the billed peak) under the plan's peak. The guarded runs are tag `lp2`.

| at the base day's end state | first day (71% full at 6 AM) | second day (25% full) |
|---|---:|---:|
| the day plan as it runs | $1,382 (1,160 kW) | $1,543 (1,475 kW) |
| the day plan, both reserves off (`dr0res0`) | $1,295 (1,032 kW) | $1,301 (1,132 kW) |
| **the LP in the loop, guarded (`lp2`), the reserve held from 2 PM** | **$1,237 (914 kW)** | **$1,286 (1,103 kW)** |
| perfect foresight | $1,085 (735 kW) | $1,098 (850 kW) |

**Guarded, the planner beats both on both days** (read 2026-11-06 01:49 and 02:01 UTC): $145 and $257 under the day
plan as it runs, $58 and $16 under the day plan with both reserves off, while it holds the 600 kWh call reserve from 2 PM
that the reserves-off plan gives up; 49% and 58% of the gap to perfect foresight closed. Every car-facing line is
identical to the base day but one: on the second day's `lp2` the scorecard reads `left_with_needed_work_open` 0 against 1,
because that replica was cloned after 0796 (G514's scorecard fix) reached the lab template; no car's day moved. Two days,
one forecast each way (each day planned on the other's shape): a reading, not a range.

The proposed fix keeps the reserve and needs it by the window: the plan may spend it before 2 PM when it can refill it by
then, and the floor hedges the plan's own forecast error, not the surge it is planning for. It is built behind a dial and
tested in the lab on a day with a demand-response call before anyone switches it on, so a call never slows a car.
