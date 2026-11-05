# The referee, owner by owner (frontier Phase 0, item 2; G511; `db/checks/0478`)

The referee is the check on the agent's charge orders. G508 priced its verdicts on the depot's totals; this
re-reads every past verdict one owner at a time (CLAUDE.md rule 14), in the research lab.

| file | what |
|---|---|
| `replay.sql` | re-grades the 370 decisions of 0475/0476's set with the grader's own pure functions, as recorded and with each car's owner added; checks both against production's stored grades |
| `analysis.sql` | each owner judged on its own cars with the engine's yardstick; the tables `0478` quotes |
| `results_2026-11-05.txt` | the output, run 2026-11-05 01:18 UTC (7:18 PM CT 2026-11-04) |

To run it again:

```bash
python3 -I lab/engine/lib/export_decisions.py --out /var/tmp/ottoq_decisions/$(date -u +%F)   # needs the token
psql -h /var/tmp -p 55433 -U postgres ottoq_lab -f lab/engine/sql/40_research_schema.sql
/var/tmp/ottoq_lab_venv/bin/python -I lab/engine/lib/load_reference_data.py --data /var/tmp/ottoq_decisions/$(date -u +%F) \
  --dsn "host=/var/tmp port=55433 dbname=ottoq_lab user=postgres" --out /tmp/decisions_load
psql -h /var/tmp -p 55433 -U postgres ottoq_lab -f lab/research/p0_referee_per_owner/replay.sql    # about 9 minutes
psql -h /var/tmp -p 55433 -U postgres ottoq_lab -f lab/research/p0_referee_per_owner/analysis.sql
```

The evidence itself (370 snapshots, grades and orders, 40 MB as exported) is not committed: it is production's,
re-exportable in seconds with the token, and the lab keeps it in its own `research` schema, apart from the engine.
