# Candidate referee rules, owner by owner (frontier Phase 1, E2/E7, first replay report)

E2's first deliverable in `docs/FRONTIER_PLAN_2026-11-03.md` is "a replay report: for the graded decisions, the verdict
each candidate rule would have given and how it fares in hindsight". After G511 (`db/checks/0478`) showed that most of
the referee's wins move one owner's minutes onto another's, the candidates here are judged owner by owner (rule 14):
a good take is one that leaves no owner's cars worse off in hindsight and some owner's better.

| file | what |
|---|---|
| `futures.sql` | for each of the 370 decisions and each of its 12 futures (the referee's own, same seed), the depot's verdict and each owner's (run with `-v worker=N -v workers=4`, one per core) |
| `rules.sql` | the candidate rules decided from those futures, each judged by hindsight owner by owner |
| `results_<date>.txt` | the output |

Run after `lab/research/p0_referee_per_owner/` (it needs that folder's tables):

```bash
psql -h /var/tmp -p 55433 -U postgres ottoq_lab -c "CREATE TABLE IF NOT EXISTS research.referee_owner_futures (
  order_id bigint NOT NULL, s int NOT NULL, depot_cmp int NOT NULL, owner text NOT NULL, owner_cmp int NOT NULL,
  PRIMARY KEY (order_id, s, owner))"
for w in 0 1 2 3; do psql -h /var/tmp -p 55433 -U postgres ottoq_lab -v worker=$w -v workers=4 \
  -f lab/research/p1_referee_owner_futures/futures.sql & done; wait
psql -h /var/tmp -p 55433 -U postgres ottoq_lab -f lab/research/p1_referee_owner_futures/rules.sql
```

## What it found (2026-11-05 01:38 UTC = 7:38 PM CT 2026-11-04; `db/checks/0479`, G512)

| rule | takes | good for every owner | trades one owner for another | bad for every owner |
|---|---:|---:|---:|---:|
| the referee before 0784 | 32 | 5 | 22 | 5 |
| with 0784's owner guard (on since 10-25) | 5 | 1 | 3 | 1 |
| no owner worse (depot better) in 10 of 12 futures | 0 | 0 | 0 | 0 |
| no owner worse, some better, in 10 of 12 | 0 | 0 | 0 | 0 |

Only 35 of the 370 orders were good for every owner in hindsight, and no decision had more than 8 of its 12 futures
good for every owner. With three owners sharing one charge line, an order that moves one car up moves another
owner's car down.
