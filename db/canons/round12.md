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
schedule stops.** Causation is strongly indicated by the timing and by every
alternative above being excluded; the confirming observation is whether cron
resumes when the pair commits, which is recorded separately.

Filed as its own investigation rather than folded into a fix. Nothing here is
guessed: each excluded cause was measured.

## Method correction, kept because it produced the finding

Probe 1 worked because the fixture smoke ran **inline from a client session**.
Moving it to a cron job this round was my error — and it is precisely what
exposed the pg_cron stall. The correct probe method is: flagship via cron,
second lane inline from a session. Recorded so the next probe does not
rediscover it.
