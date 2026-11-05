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

The two seeds at 116 cars differ by as much as 116 and 150 cars do on one seed: one day per point is a reading, not a
curve. More seeds and whole days are running.
