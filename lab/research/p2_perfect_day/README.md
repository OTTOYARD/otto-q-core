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

(results follow)
