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

The battery on the same day: no battery $1,463, the day plan $1,147, perfect foresight $849 (`bound_energy.jsonl`); plans
that see 1-4 hours ahead perfectly and hold the load flat beyond do worse than the day plan ($1,300-$1,387).
