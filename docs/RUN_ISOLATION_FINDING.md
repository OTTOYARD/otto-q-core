# Why the same seed scored 14 and 61 — runs are not isolated from each other

**The question:** two certification runs, identical seed, identical policy, both after 0070
pinned the world, scored **14** and **61** charge sessions three hours apart. Which is right?

**Answer: neither is wrong, and that is the problem.** `charge_sessions` is not a property of
the seed. It depends on how much *other runs' leftover data* is sitting in the shared tables at
the moment a run arms. Runs are scored against a depot that still contains the previous runs.

Nothing here is fixed yet. Two of the four findings below are proven; the headline mechanism is
a strong hypothesis whose controlled test was blocked by finding 4.

---

## 1. What `charge_sessions` actually measures — PROVEN

From `ottoq_score_run`, position 18 of the INSERT maps to:

```sql
charge_sessions  <-  (SELECT COUNT(*) FROM ocpp_sessions WHERE sim_run_id = p_sim_run_id)
```

It counts session **rows**, at the instant of scoring. It is not a measure of energy moved or
work completed. Every throughput comparison in the 62 / 41 / 23 / 10 / 14 / 61 series is a row
count against a shared table.

## 2. Prior runs' data is still in the tables when a new run starts — PROVEN

Measured at the arm of the most recent run, before its first tick:

| shared table | rows belonging to OTHER runs |
|---|---|
| `ottoq_stall_bookings` | **833** |
| `ottoq_visit_needs` | 39 |
| `ottoq_decisions` | 289 |

`ottoq_benchmark_reset` frees stalls, supersedes visit needs and resets vehicles — but it does
**not** remove prior runs' bookings. The depot the new run wakes up in is not empty.

**0070 made this sharply worse, and that is on me.** Before it, each run's sim clock started on
the arming day, so successive runs occupied *different* calendar windows and their bookings did
not sit on top of each other. 0070 pins every run to the same window — 2026-08-22 22:00 →
2026-08-23 08:00 — so **every cert run now stacks its ~700 bookings into the identical slots.**
The world is reproducible; the calendar is now cumulative.

## 3. The leading explanation for 14 vs 61 — STRONG HYPOTHESIS, not yet proven

The ordering fits exactly:

| run | foreign bookings at arm | charge_sessions |
|---|---|---|
| `56d90071` (19:02) | **125** — armed right after a purge had cleared the table | **61** |
| `65f5a6c3` / `90cbedb0` (16:16, 16:20) | prior runs' residue present | **14** each |
| `c8a4fbe4` (19:19) | **833** | run never started — see §4 |

The two runs that scored 14 agree with each other and were frame-identical through tick 17, so
they are internally consistent. The run that scored 61 is the one that started clean.

**Why this is a hypothesis and not a conclusion:** I have not yet run the controlled test —
same seed, deliberately varied residue — because the attempt was blocked by finding 4. A
plausible mechanism and a matching ordering is not proof, and this document does not claim it
as one.

## 4. A separate defect found while testing: the harness can silently do nothing — PROVEN

```sql
-- ottoq_cert_arm_step
FOR i IN 1..p_ticks LOOP
  EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) <> 'running';
  ...
RETURN v_done;
```

The most recent arm was flipped from `running` to `completed` at `tick_count = 0` by something
outside the harness, between the arm and the first step. `ottoq_cert_arm_step` returned **0**
and raised nothing. A certification run that never happened is indistinguishable from one that
did, unless the caller checks the return value against what it asked for.

**This is how a bad number could ship quietly**, and it should raise rather than return 0.

## 5. Run evidence is destroyed by an out-of-database caller — PROVEN

`ottoq_purge_prior_runs(p_keep_run uuid)` deletes every `class='engine'` run-scoped table for
every run except one, then deletes the run rows themselves. It is careful — it arms the
append-only guard, refuses to run on a blocking run-scope defect, deletes children before
parents, and exempts `production_live` and anything still `running`.

**But it does not exempt `cert_harness`, and no database function calls it** — so it is invoked
from outside (an edge function or the app). The observable consequence: runs `65f5a6c3` and
`90cbedb0` no longer exist. Their scores survive in `ottoq_ab_runs`; the evidence behind those
scores is gone.

Against the standing rule that **no number ships without a run ID**, the run ID currently
resolves to a score but not to the evidence that produced it.

---

## What this means for the A/B comparison

The throughput series that made greedy look better than OTTO-Q is not measuring policy quality.
It is measuring row counts in a table that other runs write to, in a calendar window that 0070
made every run share, scored at an instant that a purge can precede.

**This is a stronger indictment of the benchmark than `BENCHMARK_CREDIBILITY.md` reached.** That
document showed the power cap could never bind. This one shows the throughput metric is not
run-isolated either. Both need to hold before any policy comparison means anything.

## Recommended fixes, in order — none applied

1. **Isolate runs at arm time.** `ottoq_benchmark_reset` should clear prior runs' bookings,
   visit needs and open decisions for the benchmark depot, not just free the stalls. This is the
   one that unblocks everything else.
2. **Make the harness fail loudly.** `ottoq_cert_arm_step` should raise when it advances fewer
   ticks than requested, rather than returning a number the caller may not compare.
3. **Exempt `cert_harness` from `ottoq_purge_prior_runs`**, or snapshot the evidence into
   `ottoq_run_archives` before the purge can reach it, so a run ID keeps resolving to its
   evidence.
4. **Score on work, not rows.** `charge_sessions` should be energy delivered or vehicles
   turned around — quantities that mean something if a row is missing.

Then, and only then, re-run the four-policy comparison.
