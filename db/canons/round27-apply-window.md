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

## 0225 WAS going to refuse — found 15:30 UTC (db/checks/0140), P3 rewritten 15:32

**Do not run the window as written.** 0225's P3 was dry-run against the floor
0226 installs — the combination the window actually creates, and one nothing had
evaluated, because 0226 is not applied yet. **Two of seven columns trip it, so
0225 raises and stops.**

This is the apply-order reasoning working. The note below says 0226 goes first
"deliberately: a lower floor makes 0225's P3 a much harder test." It is harder,
and it fails.

| column | trips on | verdict |
|---|---|---|
| `grid_smoke/424242/6t` | `d_rule=2 d_rcl=2 d_endst=2`, `d_sdr=0` | P3 should never have looked. A 6-tick fixture (0153), not a certification column. `d_sdr=0` means every pair predates h_sdr. |
| `busy_day/314159/12t` | `d_sdr=2` | Real, on a flagship column, and **fully explained**: the 08:25:00 pair's two arms hashed h_sdr differently and it PASSED — eighteen minutes before **0218** (applied 08:43:04 UTC) fixed h_sdr hashing a signature over a run-scoped id, and while 0219 still had h_sdr *measured, not enforced*. The measured phase catching a defect before enforcement is the doctrine succeeding, not a hole. |

**Three defects in P3, and 0225 must be revised before the window runs:**

1. **P3 does not key as the matrix keys.** It selects `r.depot_id` and then
   drops it at `GROUP BY 1,2,3`; the matrix keys `(depot, seed, ticks,
   scenario)`. Inert today only because 0138 proved the Benchmark depot has
   zero runs — a second lane activates it.
2. **P3 judges scenarios the matrix does not certify** (grid_smoke).
3. **P3's bar is stricter than its own stated purpose.** Its message claims
   applying "would break their streaks". Traced through the matrix's
   `bool_and ... ORDER BY rn` from the newest pair backwards,
   `busy_day/314159/12t` would go from 6 consecutive passes to **3** — and
   `green` needs ≥2, so **the column stays green**. It refuses a change that
   costs three streak rows for a disagreement that cannot recur.

**What must NOT be done to make it pass:** raise the floor past 08:25, or touch
the 08:25 pair. That disagreement is correct history and it is the evidence that
motivated 0218. A migration that becomes applicable by hiding evidence is worse
than one that refuses.

**0225 has since been revised (15:32–15:40 UTC).** P3 now asks the question that
matters — *does any column green under nine atoms stop being green under
fourteen?* — keyed exactly as the matrix keys, computed once into a temp table
and read twice, with an **A5** that reports every column whose
`consecutive_passes` moves *without* losing green (expected:
`busy_day/314159/12t` 6 → 3, which is the correct consequence of comparing more
atoms, not a regression). The stale lineage note was corrected too.

**BLOCKER CLEARED 15:47 UTC — the replacement P3 dry-runs clean** (`db/checks/0140`
Q5), executed against the floor 0226 installs rather than the one live at the
time. No column goes green → not-green, so **0225 will apply**. Exactly one
column moves — `busy_day/314159/12t`, **6 → 3** — which is the number 0140 Q4
traced by hand before the query existed, and A5 reports it alone. `grid_smoke`
excludes itself.

The same run also settles what 0226 buys: **six flagship columns show a streak
of 3 or more at the lower floor, against `green`'s bar of 2, where today they
read zero.** That is G28 confirmed from the other side and 0226's A4 passing
with room to spare.

*(The first attempt used the live floor and came back clean for the wrong reason
— one pair above the floor means a streak of 1 everywhere and nothing that can
lose green. It looked like a pass. Step 3b(ii) was written forty minutes before
that happened.)*

Order, unchanged: **0226 → 0225 → 0227 → 0228**.

## Pre-flight, 2026-09-08 15:25 UTC — every pin still matches live

Re-read from the live catalog between columns e and f, no pair in flight. All
four `md5(pg_get_functiondef(...))` pins the drafts assert are byte-identical to
what is deployed, so no P0 will refuse on drift:

| migration | function | live md5 | drafted |
|---|---|---|---|
| 0225 | `public.ottoq_cert_matrix` | `34628fff…5ed2d1b` | matches |
| 0226 | `public.ottoq_cert_recert_floor` | `060b11c8…c9ed1a0d` | matches |
| 0228 | `public.ottoq_vehicles_state_change` | `9ccac364…cc3f39ba7` | matches |
| 0228 | `public.ottoq_stalls_state_change` | `84d622c6…4f099c96cc` | matches |

0227 carries no function pin — it is index-only. Its P1 asserts the index does
not already exist, and `ocpp_sessions` currently holds eleven indexes, none of
them `ocpp_sessions_runscope_load_idx`. P1 will pass.

This is a point-in-time record, not a guarantee: the pins are re-checked by the
migrations themselves at apply time, which is the check that actually counts.
Its value is that a drift would have been found now rather than inside the
window.

## Step 0 — unschedule the round, or nothing will apply

Every one of the four files refuses while **any** `r<N>_*` job is `active`, and
round 27's seven stay active after firing: their schedules are date-pinned
(`55 13 08 09 *`), so they are genuine one-shots that cannot fire again this
year, but `cron.job.active` does not know that and neither does the guard. The
guard is right to be crude — a job that *looks* scheduled is a job that might
fire mid-migration.

Pre-flight, run 2026-09-08 15:18 UTC: **only round 27's seven jobs exist**. No
`r25_*` or `r26_*` residue, so the unschedule is exactly these:

```sql
-- after r27_g has FINISHED (pg_stat_activity, not the cron log — a running
-- two-statement job reports 'succeeded' at ~1 s, db/canons/round25.md)
SELECT cron.unschedule(jobname)
  FROM cron.job
 WHERE jobname ~ '^r27_';

-- then confirm the guard will pass
SELECT count(*) AS still_active FROM cron.job WHERE jobname ~ '^r[0-9]+_' AND active;
-- expected: 0
SELECT count(*) AS pairs_running FROM pg_stat_activity
 WHERE query ILIKE '%ottoq_determinism_pair%' AND state='active' AND pid <> pg_backend_pid();
-- expected: 0
```

**Do not unschedule `r27_g` before it runs.** It is the only instrumented column
and it is the measurement for G27 *and* G23(b); losing it costs a round.

## The order, and why it is this one

| # | file | what it does | why here |
|---|---|---|---|
| 1 | **0226** | the recert floor can read its own classifications | Must be first. It lowers the floor from 2026-09-08 13:41:09 to 2026-09-07 21:36:53.363037, which brings rounds 26 and 27 back into scope. |
| 2 | **0225** | the canon comparison sees all fourteen atoms | Must be second, *because* of 0226. Its `P3` asks whether any column green under the nine-atom comparison would stop being green under the fourteen-atom one. Under the old floor that question covered **one pair per column** and could not fail; under the new one it covers rounds 26 and 27, three to six pairs a column. Same check, far more evidence. |
| 3 | **0227** | the load meter stops reading 45,379 rows to sum 303 | Independent. Index only. Placed after the two that change what `green` means so that if round 28 moves, the cause is not ambiguous. |
| 4 | **0228** | provenance asks the depot, not the run id | Last. It is the only one that touches triggers firing on **every** write to `vehicles` and `stalls`. If something goes wrong here, the other three are already in and the diagnosis is not tangled with them. |

**0225 may legitimately refuse, and that would not be a failure of this plan.**
If P3 finds a column that loses green under the wider comparison, the right
response is to go and find out why — a canon moving unnoticed is the exact thing
0225 exists to make impossible — not to weaken P3. Apply 0227 and 0228 anyway
and leave 0225 for the investigation.

**As measured at 15:47 it will not refuse** (`db/checks/0140` Q5, dry-run at
0226's floor): no column loses green, one column's streak shortens
(`busy_day/314159/12t`, 6 → 3) and A5 reports it. That is a reading taken
*before* 0226 is applied, from a hand-pinned floor value. If 0226 installs a
floor other than `2026-09-07 21:36:53.363037+00` — its own A2 asserts it does not — the
dry-run does not transfer and P3 must be re-run before 0225. **The first version
of this same dry-run was run at the wrong floor and came back clean for the
wrong reason**, so the floor 0226 actually installs should be read off its
`RAISE NOTICE` and compared, not assumed.

## The assertion that proves 0226 worked, and it is not inside 0226

0226's own A2 asserts the floor drops when it is applied. The better test comes
straight after: **0227 and 0228 are two `forces_recert FALSE` migrations landing
in the same window, and the floor must not move for either of them.**

```sql
-- run BEFORE 0227, and again AFTER 0228
SELECT public.ottoq_cert_recert_floor()      AS floor,
       (SELECT count(*) FROM public.ottoq_cert_lineage_orphans()) AS orphans;
-- expected both times: 2026-09-07 21:36:53.363037+00 | 22
```

**Both expected values were wrong in the first draft of this runbook, and one of
them would have aborted the window.** Measured 15:57–15:59 UTC:

* The floor is **`21:36:53.363037`**, not the flat `21:36:53`. The floor is
  `GREATEST(branch1, branch2)`, and branch 2 — `max(classified_at)` read
  straight off `ottoq_cert_lineage` — wins by 363 ms. The flat value is a
  rounding of branch 1.
* Orphans is **22, not 0**, and 0226's original A1 asserted 0 — so 0226 would
  have aborted on its own assertion, as the first file in the window. The 22 are
  `0192`–`0215`, applied through the SQL endpoint, which writes no
  `schema_migrations` row for anything. Nothing to key against, so no
  normalisation can match them; 0199 anticipated exactly this and that is what
  branch 2 is for. A1 has been rewritten to assert the property that actually
  matters — no `schema_migrations` row since the naming boundary falls through
  to the conservative default, measured 0. See `db/checks/0135`'s addendum.

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
   **This is now a falsifiable prediction, not a hope.** The 15:47 dry-run
   (`db/checks/0140` Q5) computed the fourteen-atom streak every column will
   have at 0226's floor, and `r27_g` adds one more pair to `171717/24t`:

   | column | expected `consecutive_passes` | expected `green` |
   |---|---|---|
   | `busy_day/171717/24t` | **4** (3 + g) | **true** |
   | `busy_day/424242/24t` | **3** | **true** |
   | `busy_day/171717/12t` | **3** | **true** |
   | `busy_day/314159/12t` | **3** | **true** |
   | `busy_day/424242/12t` | **3** | **true** |
   | `normal_day/171717/12t` | **3** | **true** |
   | `busy_day/171717/48t` | 0 | false — stale, no pair since the floor |
   | `grid_smoke/424242/6t` | 1 | false — one pair, bar is 2 |

   **Six flagship columns green, where today there are zero.** If fewer go
   green, G28's diagnosis was incomplete and that is the next thing to chase.
   If *more* than these go green, the comparison is looser than intended and
   that is worse than fewer.

   A correction to what this step used to say: it claimed `busy_day/424242/24t`
   "carries twenty-six consecutive passing pairs (`db/checks/0135` Q5)". That
   26 is a count of passing pairs in a ten-day window, not a streak against the
   canon at 0226's floor — only **three** of that column's pairs sit above
   2026-09-07 21:36:53. Expecting 26 would have made a correct outcome look
   like a failure.

   **And 0225's A5 must name exactly one column**, `busy_day/314159/12t`,
   moving `6 -> 3`. That is the 08:25 pre-0218 `h_sdr` pair falling off the
   streak under the wider comparison — correct, expected, and traced by hand in
   `0140` Q4 before any query confirmed it. If A5 names a second column,
   something moved that this window did not predict.
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
