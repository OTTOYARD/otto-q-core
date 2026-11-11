# lab/research/p3_power: the electrical one-line, measured in the lab

Research-wing work (rule 10): it runs lab days on a copy of production's engine and changes nothing in production.

| path | what |
|---|---|
| `power_day.py` | one lab day with 0810's power capture: an arm started exactly as one arm of `ottoq_determinism_pair` (`lab/engine/lib/lab_run.py`), ticked, optionally with a transformer tripped mid-day (`--trip NODE@TICK:MINUTES`), optionally at a finer tick (`--step 2`), digested to the 14 atoms, committed, and read back through `ottoq_power_one_line` |
| `results/with_0810_48ticks.json`, `without_0810_48ticks.json` | the comparison: busy_day, seed 171717, 48 ticks; all fourteen atoms equal |
| `results/trip_tx_a1_48ticks.json` | TX-A1 tripped for 90 sim-minutes at tick 20 |
| `results/fine_2min_420ticks_trip_tx_b1.json` | 14 sim-hours at 2-minute ticks from 6 AM depot time, TX-B1 tripped for an hour at 2 PM; the cockpit's test fixture is this day's one-line |

What they found is `db/checks/0481`. To rerun:

```bash
bash lab/engine/install_server.sh        # once, as root
bash lab/engine/build_from_prod.sh lab/engine/export/2026-11-04 lab/engine/export/2026-11-04/data
D="host=/var/tmp port=55433 user=postgres"
psql "$D dbname=postgres" -c "create database ottoq_cur template ottoq_lab"
for f in db/migrations/0720_*.sql db/migrations/0791_*.sql db/migrations/079[4-9]_*.sql db/migrations/080[0-9]_*.sql; do
  psql "$D dbname=ottoq_cur" -v ON_ERROR_STOP=1 -q -f "$f"; done          # production's engine since the export (0701 needs the vault)
psql "$D dbname=postgres" -c "create database ottoq_pw template ottoq_cur"
psql "$D dbname=ottoq_pw" -v ON_ERROR_STOP=1 -q -f db/migrations/0810_*.sql
/var/tmp/ottoq_lab_venv/bin/python -I lab/research/p3_power/power_day.py --db ottoq_pw --out /tmp/day.json
```

A 48-tick day takes about 2 1/2 minutes; the 2-minute day about 14.
