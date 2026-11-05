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

Each day: the twin depot as built today (30 robotic DCFC posts, 3 wash bays, 2 service bays, 113 staging spaces, one
3,000 kWh battery), 12 hours from 6 AM CT at 5 sim-minutes a tick (the sweeps' own window), the deterministic core alone
(cuOpt and the agent quiesced), OTTO-Q's seat, the twin depot's dials as production has them.

## What it found

(results follow)
