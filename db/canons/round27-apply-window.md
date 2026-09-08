# The apply window after round 27 — order, reasoning, and what proves it worked

Written 2026-09-08 14:35 UTC / 9:35 AM CT, while round 27 is still running, so
the order is decided on the reasoning rather than on whatever is convenient when
the last column lands.

**Nothing here may be applied until round 27's last column (`r27_g`, 15:52 UTC)
has finished AND its jobs are unscheduled.** Every one of the four files enforces
that itself in a `P-` block — a pair active in `pg_stat_activity`, or any
`r<N>_*` job still `active` in `cron.job`, and the migration refuses. That is
belt and braces on purpose: `ottoq_sim_runs` cannot see an in-flight pair (both
arms are one transaction) and `cron.job_run_details` reports a running
two-statement job as `succeeded` at ~1 s (`db/canons/round25.md`).

## The order, and why it is this one

| # | file | what it does | why here |
|---|---|---|---|
| 1 | **0226** | the recert floor can read its own classifications | Must be first. It lowers the floor from 2026-09-08 13:41:09 to 2026-09-07 21:36:53, which brings rounds 26 and 27 back into scope. |
| 2 | **0225** | the canon comparison sees all fourteen atoms | Must be second, *because* of 0226. Its `P3` asks whether any column already disagrees with itself on a newly compared atom at or above the floor. Under the old floor that question covered **one pair**; under the new one it covers rounds 26 and 27. Same check, far more evidence. |
| 3 | **0227** | the load meter stops reading 45,379 rows to sum 303 | Independent. Index only. Placed after the two that change what `green` means so that if round 28 moves, the cause is not ambiguous. |
| 4 | **0228** | provenance asks the depot, not the run id | Last. It is the only one that touches triggers firing on **every** write to `vehicles` and `stalls`. If something goes wrong here, the other three are already in and the diagnosis is not tangled with them. |

**0225 may legitimately refuse, and that is not a failure of this plan.** If P3
finds a column whose `h_rule`, `h_rcl`, `h_sdr` or `endst` moved between rounds
26 and 27, the right response is to go and find out why — that is a canon moving
unnoticed, which is the exact thing 0225 exists to make impossible — not to
weaken P3. Apply 0227 and 0228 anyway and leave 0225 for the investigation.

## The assertion that proves 0226 worked, and it is not inside 0226

0226's own A2 asserts the floor drops when it is applied. The better test comes
straight after: **0227 and 0228 are two `forces_recert FALSE` migrations landing
in the same window, and the floor must not move for either of them.**

```sql
-- run BEFORE 0227, and again AFTER 0228
SELECT public.ottoq_cert_recert_floor()      AS floor,
       (SELECT count(*) FROM public.ottoq_cert_lineage_orphans()) AS orphans;
-- expected both times: 2026-09-07 21:36:53+00 | 0
```

If the floor moves, a lineage row did not join, and the fix is incomplete.
Before G28 this could not have been checked at all, because there was nothing
that could tell a reachable classification from an unreachable one.

**0225's lineage row was missing from its first draft**, and this is exactly the
failure that would have caught it: four `forces_recert FALSE` migrations, and
the floor jumping anyway because one of them had no row to read. It is recorded
in 0225's own footer rather than quietly fixed.

## After the window

1. `scripts/check-drift.sql` — every applied file has a ledger row and a
   matching deployed body.
2. The matrix, now judging fourteen atoms over a floor that admits rounds 26
   and 27:
   ```sql
   SELECT scenario, seed, ticks, pairs_seen, consecutive_passes, green, stale,
          canon_rule, canon_rcl, canon_sdr, canon_endst
     FROM public.ottoq_cert_matrix(now() - interval '10 days')
    WHERE depot = '11111111-1111-1111-1111-111111111111'
    ORDER BY ticks DESC, scenario, seed;
   ```
   **Some columns should go green.** `busy_day/424242/24t` carries twenty-six
   consecutive passing pairs (`db/checks/0135` Q5) and has been reading
   `consecutive_passes = 0`. If nothing goes green after the floor drops, G28's
   diagnosis was incomplete and that is the next thing to chase.
3. 0224's outstanding verification, which round 27 now supplies:
   ```sql
   SELECT data_source, count(*) FROM public.ottoq_events
    WHERE event_type = 'ottoq.refusal_escalated'
      AND recorded_at > '2026-09-08 13:41:09+00'
    GROUP BY 1;
   -- expected: no 'production' rows
   ```
4. Schedule round 28 with `scripts/schedule-round.sql` (`v_round := 28`), which
   now takes the max of the last 6 runs of each tick count and so will size its
   slots from round 27's durations rather than round 26's.
5. **Round 28's prediction, to be committed before it runs, as always.** 0227
   claims about 4.5% of a pair. On round 27's 12-tick mean that is roughly 16 s.
   Say it as a number in `db/canons/round28.md` before the first column fires,
   and say plainly that 0228 and 0225 predict *no* duration change at all — one
   is a label, the other is a read nothing in the pair calls.

## What is still not mine

- **S-01 / S-02.** The committed secret stays compromised until it is rotated on
  EC2 and in Supabase. Code half fixed and pinned; rotation is an operator action.
- **The 67 unfiled migrations** (G18) — whether to recover them.
- **G23's first question**: are a finished twin run's bookings evidence worth
  keeping? `ottoq_stall_bookings` is 14% purged over its life against
  `ottoq_events`' 97%, and it is 53% of every disk block this database has ever
  read. The answer decides whether that is a retention change or a fact of life.
- **The 27,460 mislabelled signed events** that 0228 stops but cannot repair.
  They are signed and the signature covers the mislabel: relabelling invalidates
  the signature, deleting is a deletion from an audit ledger.
