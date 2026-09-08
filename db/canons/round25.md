# Round 25 — 2026-09-08 (in progress; first pair fired 3:25 AM CT / 08:25 UTC)

Flagship depot `11111111-…`, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced,
arm budget 900 s. Engine as of **0216** (the SDR booking pick + the `leg_id` index) and
**0217/0218** (h_sdr measured, h_rcl enforced).

## Pair 1 — busy_day / 314159 / 12 ticks — **PASSED**

Runs `5861ea1d` (arm a) and `98095daf` (arm b). Wall clock **812 s**.

**All eleven enforced atoms held, and every one reproduces round 24 exactly:**

| atom | round 25 | vs round 24 |
|---|---|---|
| `fp` | `803698f3` | same |
| `h_cmd` | `109e340b` | same |
| `h_dec` | `9abdb4af` | same |
| `h_evt` | `9c631343` | same |
| `h_bkg` | `174b8835` | same |
| `h_nrg` | `a9c6b693` | same |
| `h_prop` | `a79c1095` | same |
| `h_cal` | `11a24626` | same |
| `h_rule` | `fc69953b` | same |
| `h_rcl` | `0e67b89a` | same — **first round in which it could fail a pair** |
| `endst` | unchanged | same |

So 0216, 0217 and 0218 moved no canon, which is what all three predicted, and `h_rcl`'s
promotion from measured to enforced (0217) passed on its first outing.

## The new instrument found something on its first run

`h_sdr` — measured, not judged — differed: **`0df9a909` vs `65ec044e`**.

The carrier was the hash, not the engine. Matching the 284 SDRs across arms on
`(vin, operation_code, started_at)`, field by field:

| column | rows differing |
|---|---|
| `tariff_id` | 0 of 284 |
| `total_cost_usd` | 0 of 284 |
| `ended_at` | 0 of 284 |
| `duration_min` | 0 of 284 |
| `source_kind` | 0 of 284 |
| **`payload_hash`** | **284 of 284** |

`payload_hash` is `ottoq_compute_event_hash(v_payload)`, and `ottoq_emit_sdr` builds
`v_payload` with `'leg_id', p_leg_id` — a fresh uuid per run. 0217 called `h_sdr` id-blind and
then included a column that cannot be equal across two arms by construction. **0218 removes
it**, and the same expression without it reads `aad2d1be` on **both** arms.

Which is the result that matters: **0216 worked.** The booking attribution reproduces exactly
now. Before it, 23 of 284 SDRs per arm bound to a different calendar claim on a replay of the
same seed, inside a pair that passed.

0218's A3 also re-checks that the corrected hash still *separates* the pre-0216 arms
(`1cc8a3ef` vs `e1fe3504`) — the false positive is not being fixed by blinding the instrument.

## The speed claim, refuted

0216 added the missing `leg_id` index after measuring the trigger's own lookup at
**965.175 ms → 0.295 ms** (50,769 blocks → 25). That is real, and the scan it removes was
genuinely unbounded in history. **It did not make the pair faster.**

| | wall clock |
|---|---|
| pre-0216 (round 24, two pairs) | 797 s, 801 s |
| post-0216 (round 25, pair 1) | **812 s** |

812 s sits inside the previous days' range (688–822). The microbenchmark was cold-cache
(`read=50769`); in a real arm those pages are warm and each scan costs far less, so ~2,236 of
them do not add up to anything near the 800 s pair. The index is still correct — it removes a
cost that grows with total history rather than with the run — but it is **not** the drift.

**The drift is still open.** Refuted so far: the `ottoq_demo_metronome` cron job (flat at
20 ms/run all week), and missing `sim_run_id` indexes on the verdict-hash tables
(`ottoq_events`, `ottoq_decisions`, `ottoq_rule_evaluations`, `ottoq_energy_commands`,
`ottoq_recall_decisions`, `ottoq_external_proposals` all have one). At 24 ticks per pair and
812 s, the number to attack is ~33 s per tick, and `pg_stat_statements.track` is `top`, so the
tick's internals are invisible to it. Next instrument, not next guess.

## Pairs 2 to 5 — all **PASSED**, all with a clean `h_sdr`

Scheduled 08:46, 09:02, 09:18, 09:34 and 10:00 UTC (3:46 – 5:00 AM CT), 16-minute spacing for
12-tick and 26 for 24-tick, from the 812 s / ~1300 s measurements.

| column | fired | wall clock | verdict | `h_sdr` a / b |
|---|---|---|---|---|
| `busy_day` / 171717 / 12t | 08:46 | 686 s | passed | `a2a35e03` = `a2a35e03` |
| `normal_day` / 171717 / 12t | 09:02 | 735 s | passed | `e0dfbbe8` = `e0dfbbe8` |
| `busy_day` / 424242 / 12t | 09:18 | 754 s | passed | `6fd75365` = `6fd75365` |
| `busy_day` / 171717 / **24t** | 09:34 | ~1,300 s | passed | `957abcfb` = `957abcfb` |

Four columns, four agreements, on the first round in which `h_sdr` exists in its corrected
(0218) form. Every other atom on every column reproduces the column's own last canon, with
**one move, twice, and both times it is 0208's**:

| column | atom | from | to | previous pair |
|---|---|---|---|---|
| `busy_day` / 424242 / 12t | `h_rule` | `c3cca844` | `d56e09a3` | 09-07 20:07 |
| `busy_day` / 171717 / 24t | `h_rule` | `62ed1a1e` | `9564b998` | 09-07 18:35 |

0208 was applied 09-07 21:36 — **after** both of those pairs — so each column is taking the
move at its first post-0208 outing, exactly as `busy_day / 314159 / 12t` already did in round
24 (`333cf172` → `fc69953b`). On both columns every other atom is byte-identical to that
previous pair: `fp`, `h_cmd`, `h_dec`, `h_evt`, `h_bkg`, `h_nrg`, `h_prop`, `h_defr`, `h_cal`
and `h_rcl`. `h_cal` is `11a24626` on all four columns, as it has been all week.

### An observability trap worth knowing about

`cron.job_run_details` cannot be trusted to say whether one of these pairs is finished. At
09:53 it reported `r25_e_busy_171717_24` as **`status='succeeded'`, `return_message='SET'`,
duration 1 second** — while `pg_stat_activity` showed that job's own backend still executing
the pair, 1,169 seconds in. The job command is two statements (`SET statement_timeout …;
SELECT ottoq_determinism_pair(…)`) and the run-details row reflects the first one until the
job actually ends. The authority for "is a pair running" is `pg_stat_activity`, not the cron
log — which matters because the standing rule is never to apply a migration while a pair is in
flight, and the cron log will happily say the coast is clear.

## The instrument the drift needed was already in the server

`pg_stat_statements.track` is `top`, so nothing inside a plpgsql function is visible there —
that was recorded above as the reason the tick's internals could not be attributed. The way
round is **`track_functions`**, which is `none` globally but which the `postgres` role can set
**per session**:

```sql
SET track_functions TO 'pl';   -- verified settable as postgres, 2026-09-08 09:30 UTC
```

Because the setting is session-local and every other session on this database leaves it at
`none`, the `pg_stat_user_functions` delta across a session that sets it contains **only that
session's** calls. The metronome, the depot tick and the run governor — all firing every one or
two minutes throughout — contribute nothing to it. That is exact isolation with no migration,
no engine change and nothing added to a hashed table.

So the sixth pair of round 25 is also the G19 instrument. `busy_day / 314159 / 12t` has to be
re-run anyway — its 08:25 pair predates 0218 and its stored `h_sdr` is the contaminated kind —
so job `r25_g_busy_314159_12_profiled` at **10:40 UTC (5:40 AM CT)** snapshots
`pg_stat_user_functions` into `g19_fn_before` and then runs that re-run with `pl` tracking on.
The verdict is a normal verdict: timing instrumentation touches no atom.

## Schedule change during the round

`r25_f` was moved from 10:00 to **10:12 UTC** and `r25_g` from 10:40 to **10:52** (5:12 and
5:52 AM CT). Pair e was still running at 09:53 having started 09:34, and a 24-tick pair at the
current pace lands between 1,300 and 1,600 s — so the original 10:00 slot risked starting f
while e still held the flagship depot. Both new slots were asserted `fire_utc > now()` against
the database clock before being written.

### How to read the capture, written before it exists

Two traps, both easy to walk into once numbers are on the screen.

**Nesting double-counts.** With `pg_stat_statements.track='all'`, the top-level
`SELECT ottoq_determinism_pair(…)` carries the whole pair's `total_exec_time`,
AND every statement inside it is recorded separately, AND a plpgsql statement
that calls a function includes that function's time. So the nested rows sum to
far more than the pair. Rank by `total_exec_time` with the top-level row
excluded, and read a row as "this statement and everything under it", never as
a share of a total.

**Other sessions leak in, but only their top level.** The metronome, the depot
tick and the run governor fire every one or two minutes and their sessions leave
`track` at `'top'`, so the diff will contain a handful of rows for
`CALL public.ottoq_demo_metronome(50)`, `SELECT public.ottoq_cron_tick()` and
`SELECT public.ottoq_run_governor_auto_stop()` — and nothing from inside them.
Those three are identifiable by name and are the only contamination.

The number that settles G19 is simpler than either: `g19_seq_before` and
`g19_io_pref` differenced after the pair commits give **sequential scans and
disk blocks read per pair**, per table, measured rather than inferred. Note that
those counters do not move while the pair runs — both arms are one transaction
and pgstat flushes at commit — so a zero mid-pair means nothing.

## Round completion

The round is complete when all six columns have a post-0218 pair; `h_sdr` is enforced by 0219
only if all six show the arms agreeing, which is the same gate 0206 set for `h_rcl` and 0217
closed. 0219's P1 block reads that condition out of the ledger itself and aborts if it does not
hold, so the gate is not mine to wave through.
