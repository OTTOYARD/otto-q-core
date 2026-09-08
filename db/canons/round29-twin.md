# Round 29 — the twin, to close Part A's last clause at fourteen atoms

**Written 2026-09-08 18:50 UTC, after scheduling and before either pair fires.**
Jobs `r29_t1_busy_314159_12` (18:58) and `r29_t2_busy_314159_12` (19:12), jobids
495 and 496. Command form copied verbatim from `r28_a`.

## Why this exists

Task #56 Part A reads: *"all six certification columns green AND inter-pair
reproducible, with h_nrg in the verdict, every canon stable across at least two
rounds."* After round 28, five of those six clauses hold at the fourteen-atom bar
0225 installed. One does not, and the reason is precise rather than rhetorical.

`db/checks/0113` treats two of the clauses as **separate tests**, and its own
section 3 shows why:

> **"AND inter-pair reproducible"** — 171717/12t twins: rounds 15 and 16.
> 314159/12t twins: round 17. Two columns, three rounds.
>
> **"every canon stable across at least two rounds"** — 171717/12t, normal_day,
> 171717/24t: rounds 14–17. …

A **twin** is two pairs of the same column run in the **same round**, minutes
apart, compared on **every verdict key** — 0113's bar (b) reads *"the two
314159/12t pairs agree on every field — MET (Q2: every verdict key equal but
'run')"*. A **streak** is successive pairs across rounds agreeing with the canon.

Round 28 delivered streaks of 4 and 5 at fourteen atoms. Those are stronger than a
twin in one respect — they span rounds, four applied migrations and ~26 hours — and
**weaker in another**: `on_canon` compares the fourteen atoms, where the twin test
compares every field of the verdict, a superset. That residual is the whole reason
this round exists. It would have been easy to argue the streaks subsume the twin
and declare Part A complete; the argument is not airtight, and one twin costs
twelve minutes.

## PREDICTION — stated before either pair fires

**The two pairs agree on every verdict key but `run`.** Both must also be `PASS`
and land on `busy_day/314159/12t`'s existing canon, which round 28 column a set
and which reads `fp 803698f3`.

| outcome | reading |
|---|---|
| every key equal but `run`, both PASS | Part A's last clause is re-shown at fourteen atoms and Part A is **met in full**. |
| the fourteen atoms equal, some **other** verdict key differs | **The most interesting outcome.** It would mean the fourteen-atom comparison is narrower than the verdict, exactly as `0225` proved nine was narrower than fourteen — and it names the next atom to promote. A finding, not a nuisance. |
| any of the fourteen atoms differs | Round 28's six green columns are called into question and this becomes the priority over everything else, `G29` included. |

The middle row is the one worth running for. **`0225` exists because a comparison
was narrower than the enforcement and nobody had checked.** The same question has
never been asked of the verdict-versus-matrix boundary, and a twin is the only
instrument that asks it.

## What this round is NOT

It is not a recertification of `G29` or of anything else. **No migration will be
applied between these two pairs**, or the twin measures a code change rather than
reproducibility. `pg_stat_activity` remains the only authority on whether a pair is
in flight — `cron.job_run_details` reported round 28's column e as `succeeded, 1
second` while it was 725 s into a 783-second run.

Results go below a `## Results` heading. Nothing above it is to be edited.
