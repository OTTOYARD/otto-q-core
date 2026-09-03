# Round 12 canons — 2026-09-03

Flagship depot, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced.
Engine as of **0180**.

**Twelve pairs, six columns, two each. Not one hash moved from round 11.**

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg | rec |
|---|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `04177a2a` | `5328154a` | `0bf42b3c` | `8dcf8918` | 0 |
| busy_day | 314159 | 12 | `773fd6dc` | `ad492891` | `4274369c` | `2b271f2f` | 0 |
| normal_day | 171717 | 12 | `78ece09b` | `c36a99c1` | `2838c66c` | `5512b237` | 0 |
| busy_day | 171717 | 24 | `ec5c38aa` | `8221f656` | `096b099e` | `da9c269c` | 0 |
| busy_day | 424242 | 12 | `16aabc27` | `f1224a98` | `5a227276` | `0cac7e0b` | 3 |
| busy_day | 424242 | 24 | `ac1dc757` | `3adcc2dc` | `37ed2670` | `c5ef0ab3` | 14 |

Every column `pairs = 2`, all four hashes single-valued within the column, every
run `passed`. 0180's prediction — published in its header before the round —
held on all 24 hash comparisons, with no column permitted to move.

**Three round boundaries now** (8 → 10 → 11 → 12) for the four columns unchanged
since round 8; two for the 424242 pair that 0179 established.

## THE TWO-LANE CADENCE IS UNBLOCKED — verified, not inferred

This is what 0180 was for. `db/checks/0089` §4 fixed the pass condition in
advance and deliberately excluded wall time. The result:

| | before 0180 | after 0180 |
|---|---|---|
| fixture lane, concurrent with a flagship pair | blocked **75 s+**, killed at 60 s | **12.5 s, completed** |
| what it was waiting on | tuple lock on `vehicle_need_profile`, `transactionid` ShareLock on the flagship's xid | nothing |
| assertions | never reached | all green, `pair_verdict_passed` equal=true |

**Proof it was concurrent, not sequential.** Wall time alone would not settle
this, so the control is a state read taken *after* the fixture lane finished:

```
now 21:55:17   flagship_still_running 1   flagship_elapsed_s 438
               flagship_pairs_committed 0
               fixture_pairs_committed  1
```

The fixture lane **started and committed while the flagship's transaction was
still open and uncommitted**. Before 0180 that was impossible by construction —
it had to wait for the flagship to commit. The pass condition is met by
entailment, not by a stopwatch.

## A SEPARATE FINDING, larger than the probe: a cert pair halts pg_cron

Two attempts to run the second lane *as a cron job* (`lane2b`, `lane2c`) never
fired at all — no `cron.job_run_details` row, the silent shape recorded in
round 11. The cause is not lead time, which was my first theory and was wrong
(`lane2c` had 129 s of lead).

`cron.job_run_details` shows pg_cron launched **nothing at all** from 21:48:00
onward, while `ottoq-demo-metronome` is scheduled `* * * * *` and had fired at
:44, :45, :46, :47, :48. Five-plus consecutive missed minutes, with:

- every job still `active = true`, including the metronome
- the `pg_cron launcher` backend alive, `blocked_by = 0`, no wait event
- **1** background worker of `max_worker_processes = 6` in use
- `cron.max_running_jobs = 32`

So it is not disabled jobs, not worker exhaustion, and not the launcher being
lock-blocked. **21:48:00 is exactly when the flagship certification pair
started.** `ottoq-depot-tick` and `ottoq-run-governor` stopped with it.

This is **not** 0180's doing and is **not** fixed by it — 0180 removed a row-lock
collision; this is the scheduler itself going quiet. It is the same shape as the
`ottoq_start_demo_run` blockage found in `db/checks/0089` but broader and by a
different mechanism: **while a certification pair runs, the production tick
schedule stops.** **Causation is now confirmed, not inferred.** The confirming observation was
taken as soon as the pair committed:

```
21:55:17   pair_running 1   last_cron_launch 21:48:00   launches_since 0
21:56:50   pair_running 0   last_cron_launch 21:56:06   launches_since 5
           flagship_pairs_committed 1
```

pg_cron was silent for the whole 21:49–21:55 window and resumed in the same
minute the pair committed. The scheduler stops for exactly the duration of a
certification pair, then catches up.

Filed as its own investigation rather than folded into a fix. Nothing here is
guessed: each excluded cause was measured.

## Method correction, kept because it produced the finding

Probe 1 worked because the fixture smoke ran **inline from a client session**.
Moving it to a cron job this round was my error — and it is precisely what
exposed the pg_cron stall. The correct probe method is: flagship via cron,
second lane inline from a session. Recorded so the next probe does not
rediscover it.

---

## REFUTATION — 22:07 UTC. The general claim above is WRONG.

Appended, not edited, per this directory's README.

The section above says a cert pair halts pg_cron and frames it as a general
hazard of the scheduler. **The generalisation is refuted.** A controlled
experiment was run with its interpretation fixed in advance:

`probe_sleeper` — a cron job whose entire body is `SELECT pg_sleep(90)`, touching
nothing — ran **22:01:00 → 22:02:30**, a full 90 seconds. During that window:

| job | scheduled | fired |
|---|---|---|
| `ottoq-demo-metronome` | `* * * * *` | **22:02:00, on time** |
| `ottoq-depot-tick` | `*/2 * * * *` | **22:02:00, on time** |
| `ottoq-run-governor` | `*/2 * * * *` | **22:02:00, on time** |

**A long-running pg_cron job does not stall the launcher.** Duration is not the
cause, so "don't run long work in pg_cron" is not the lesson and the mitigation
proposed above ("certification pairs must not run as cron jobs") is not
established.

### What survives, and what does not

**Survives — the effect.** No cron job of any kind launched between 21:49 and
21:55, and the metronome resumed at 21:55:54, the minute the pair committed.
That was measured with a **join-free** count over `cron.job_run_details`, so it
is not an artifact of the query bug below.

**Refuted — the generalisation.** Whatever stops the scheduler is specific to
what a certification pair *does*, not to how long it runs. The pair holds a long
transaction **and** writes shared tables; a sleeper does neither.

**Unnamed — the mechanism.** Note the shape of the evidence: during the stall
there were **no run rows at all**, not rows sitting blocked. Jobs that merely
waited on the pair's row locks would still have been dispatched and recorded.
So the launcher was not dispatching — and the sleeper shows a busy job alone
does not cause that. The cause is not yet identified and is not guessed here.

### A query bug worth keeping

The first attempt to read this experiment used
`FROM cron.job_run_details d JOIN cron.job j USING (jobid)` and showed **no**
`probe_sleeper` row — which read as "the sleeper never fired". It had fired. A
self-unscheduling job deletes its own `cron.job` row, so an inner join silently
drops every run it ever made.

Same family as the traps this codebase keeps collecting: a query that cannot see
the thing it is looking for returns an answer that looks like evidence of
absence. Read `cron.job_run_details` **join-free** and resolve the name
separately.
