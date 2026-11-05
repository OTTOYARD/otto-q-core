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
