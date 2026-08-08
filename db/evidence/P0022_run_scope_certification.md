# 0022 certification — a run owns its rows, proved on live runs

**Migration** `0022_a_run_owns_its_rows`, ledger version **20260808182226**, applied.
**Battery** `db/checks/0022_run_scope_certification.sql` (read-only, re-runnable).
**Date** 2026-08-08.

0022 shipped with nine in-transaction assertions passing and its *outcome* unproven.
Nothing had yet reproduced, on two real runs, the cross-run collision that started this
line of work. This is that outcome.

---

## The one-line answer

Two night-crossing runs were given the same simulated clock so their visit keys collided
byte-for-byte. **11 keys collided. Run A's 182 ledger rows came through with every single
column identical except `status`** — 0 rows lost, 0 rows appeared, 0 rows changed owner.
Then the normal start button purged both runs for real: **168,842 rows across 34 tables and
7 run rows deleted, and the orphan population did not move.**

---

## 1. The assertion — reproduce the collision deliberately

### How the collision was produced (nothing was rigged)

`ottoq_sim_run_scenario` contains:

```sql
v_start := CASE WHEN p_run_by = 'operator_demo'
  THEN ((date_trunc('day', now() AT TIME ZONE 'America/Chicago') + interval '8 hours')
        AT TIME ZONE 'America/Chicago')
  ELSE NOW() END;
```

Every run started on the same real calendar day therefore gets a byte-identical
`sim_clock_start`, and the tick grid is a fixed 30 sim-min. `visit_key` is
`vehicle_id || ':' || to_char(clock,'YYYYMMDDHH24MISS')`, so two same-day runs mint
identical keys for the same vehicle in the same grid slot. **The collision is the default
behaviour of the shipped entry point, not a contrivance.**

| | run A | run B |
|---|---|---|
| id | `59e62365` | `4f89666a` |
| seed | 20260830 | 20260831 |
| `sim_clock_start` | 2026-08-08 13:00:00+00 | 2026-08-08 13:00:00+00 — **identical** |
| depot | `11111111` | `11111111` — identical |
| tick grid | 30 sim-min | 30 sim-min — identical |
| ticks reached | **48 of 48**, 08:00 → 08:00 CST | **28 of 48**, 08:00 → 22:00 CST |
| night crossed | yes, ticks 24–44 observed | yes, observed at 21:00 and 22:00 CST |

### Colliding keys — reported first, because a zero here would make the test vacuous

**11 byte-identical `(vehicle_id, visit_key)` pairs across runs A and B**, across 11
vehicles. Not vacuous.

### Run A's ledger, before run B existed vs after run B had written a night of rows

| measure | result |
|---|---|
| run A rows | 182 |
| payload byte-identical (md5 of every column except `status`) | **182 / 182** |
| payload changed | **0** |
| rows lost | **0** |
| rows appeared | **0** |
| run ownership moved | **0** |
| run-scoped query returns | **182**, out of 1,266 rows then present across 7 runs |

`atoms` and `meta` — the fields the original clobber replaced — are untouched on every row.

A whole-row md5 could hide a difference behind a hash, so the diff was also done
**column by column** rather than trusted to the hash:

| column that changed | rows |
|---|---|
| `status` | 99 |

That is the entire list. One column, and it is the one described next.

---

## 2. The cross-run write that survives 0022 — reported, not buried

`ottoq_sim_run_scenario` carries this, and 0022 does not touch that function:

```sql
UPDATE ottoq_visit_needs vn SET status = 'superseded'
  FROM vehicles v
 WHERE vn.vehicle_id = v.id AND v.home_depot_id = <depot>
   AND vn.status IN ('open','in_progress');
```

It is scoped by **depot, not by run**, so starting run B rewrote `status` on 99 rows
belonging to an already-finished run A (`open`/`in_progress` → `superseded`).

Honest reading: it cannot lose work — 0020 made uniqueness run-scoped, 0022 made the row's
run un-droppable — and `superseded` is a truthful terminal label for a need that never
completed. But it *is* a later run reaching into an earlier run's ledger, it is run-blind,
and **it is not fixed here.** Pre-existing; not introduced by 0022.

---

## 3. Orphans are not creatable

Six deliberate attempts. A pass only counts when the refusal is a **23503 raised by the
constraint itself** — a NOT NULL or unique index firing first would be a misread. Two early
probes did exactly that (`event_category` NOT NULL, then `keep_event_seq` unique) and were
rewritten until they actually reached the foreign key.

| target | probe | verdict | sqlstate |
|---|---|---|---|
| `ottoq_visit_needs` | UPDATE existing row → dead run | REFUSED | 23503 |
| `ottoq_visit_needs` | INSERT new row → dead run | REFUSED | 23503 |
| `site_energy_snapshots` | UPDATE existing row → dead run | REFUSED | 23503 |
| `ottoq_stall_bookings` | UPDATE existing row → dead run | REFUSED | 23503 |
| `ottoq_sim_runs` | DELETE parent still holding children | REFUSED | 23503 |
| `ottoq_events` (FK is **NOT VALID**) | INSERT new row → dead run | REFUSED | 23503 |

The `ottoq_events` result is the one worth stating plainly: a `NOT VALID` constraint still
enforces on every future write. Its historical 2 orphans are not rewritten, and no new one
can be created. `UPDATE` on that table is refused earlier still, by the append-only guard
(`P0001`), so an existing event row cannot be re-pointed at all.

---

## 4. The purge, on the real path — and this is what makes "0 orphans" non-vacuous

`ottoq_start_demo_run` (the normal start button) calls `ottoq_purge_prior_runs` at the end.
Run C exercised it for real against runs A and B.

```
rows_purged          168,842   across 34 tables
prior_runs_deleted         7
evidence_preserved       150
exception                 none
```

Because every engine FK is `NO ACTION`, a missed child table would have made the parent
`DELETE` raise 23503. It did not raise. Included in the sweep were the four tables the old
`LIKE 'ottoq%'` enumeration **could never see** — every row of which would have become an
orphan under the old code:

| table the old purge could not see | rows cleared |
|---|---|
| `ocpp_sessions` | 1,440 |
| `site_energy_snapshots` | 320 |
| `cuopt_invocation_log` | 291 |
| `space_conflict_ledger` | 17 |

`ottoq_events` cleared 56,467 rows, so the armed-retention path still works.

**The orphan population before and after that purge:**

| phase | FK keys with orphans | orphan rows |
|---|---|---|
| baseline (before any run) | 1 | 2 |
| after the purge | 1 | 2 |

Same key, same count: `fk_ottoq_events_sim_run`, the declared exception. **The operation
that used to manufacture orphans ran at full scale and manufactured none.**

Run A and run B after the purge: **0 run rows remaining, and 0 rows in any engine or stamp
table still pointing at them.** A clean children-first deletion with no residue — the
opposite of the old failure, where the rows survived and the run did not.

### Nothing was silently removed

| | |
|---|---|
| FKs to `ottoq_sim_runs` that are CASCADE | **0** |
| NO ACTION | 44 |
| SET NULL | 1 (`vehicles.owning_sim_run_id` only) |
| `vehicles` rows after a 168,842-row purge | **220** — unchanged |
| `stalls` rows after the purge | **320** — unchanged |
| stale vehicle run-stamps | 0 |

The single SET NULL cleared stamps and deleted no fleet row. **6 `production_live` runs
survived the purge untouched** — they are excluded from the doomed set by
`run_by <> 'production_live'`.

### The orphan census, generated from the registry — never a hand-written list

| class | before purge | after purge | reading |
|---|---|---|---|
| engine | 2 (1 table) | **2 (1 table)** | the declared `ottoq_events` pair, unchanged |
| stamp | 0 | **0** | |
| run_ledger | 59 | 59 | `ottoq_run_archives`, deliberately unconstrained |
| evidence | 86,720 | 91,749 | rose **by design** |

The evidence-class rise is fully accounted for: every table in the delta is a certification
snapshot (`cert0022_a_*`, `p0020_prestop_*`, `cert0020_*`) whose run was just purged. That
class exists **in order** to outlive its run. No engine table moved.

---

## 5. Both entry points

| entry point | result |
|---|---|
| `ottoq_sim_run_scenario(..., 'operator_demo')` | runs A and B — 48 and 28 ticks, both crossed night, fixed 30 sim-min playback |
| `ottoq_start_demo_run(...)` — the normal start button | run C started, purged 7 prior runs, and was ticking at **tick 19** within minutes |

### An unplanned live test of the guard's grading

Creating the `cert0022_*` capture tables put six new unregistered `sim_run_id` columns into
`public`. The drift guard flagged every one at severity **`warn`, not `block`**, so the
purge — and therefore the start button — was **not stopped by a scratch table**. That is
precisely what the second 0022 commit was written to guarantee, and it was exercised here
by accident rather than by design. Registering them as `evidence` returned the guard to
clean, closing the loop: new table → warn → register → clean.

---

## 6. Nothing regressed — PROTECT, whole list

| check | bound | measured | verdict |
|---|---|---|---|
| double-bookings, own pairwise `during && during`, **within a run** | 0 | **A 0, B 0** | PASS |
| orphaned FKs, key list generated from `pg_constraint` (294 keys, 271 in `public`) | 0 | **2, the declared `ottoq_events` pair** | PASS |
| 0010 geometry — oriented footprint, `relative_x/y` in FEET | 0 overlap, 0 not_assessed | **320 assessed, 0 not_assessed, 0 overlapping** | PASS |
| 0010 mix, both depots | 160 = 115/30/10/3/2 | **both depots exactly 115 staging / 30 l2 / 10 dcfc / 3 wash_bay / 2 service_bay** | PASS |
| 0008 laundering, **directional** | 0 | 775 pairs, 0 naive value-equality, **0 directional** | PASS |
| 0009 `planned_return_at` | raises 428C9 | **428C9** — `attgenerated='s'` | PASS |
| rider flags — 0 silent drops | 0 | **19 flags, 0 visit-missing, 0 wrong-vehicle, 0 wrong-run, 0 atom-missing** | PASS |
| dispatch churn (unconsumed test) | 0 | **A 0 of 3, B 0 of 26** | PASS |
| recall latency | 0 over one 30-min tick | **B: n=5, median 15 min, max 25 min, 0 over a tick** | PASS |
| cron 10/11/12 ON, 13 OFF | — | **10 ✓ 11 ✓ 12 ✓ ON, 13 OFF** — cron 12 never touched | PASS |
| drift | CLEAN | **CLEAN** — A/B/C clean, routine counts match public 346 / ottoq 55 / twin 71 | PASS |
| run-scope registry guard | 0 defects | **0** | PASS |

The naive dispatch-churn metric would have reported 1 and 5 "after raise" in the two runs.
Both are later, legitimate dispatches of cars whose cleaning had already finished — the trap
the metric is documented to spring. Keyed on the flag still being unconsumed: **0**.

### Placed is not cleaned — reported separately

| run | rider-flagged atoms | `done` | placed, not done |
|---|---|---|---|
| A (48 of 48 ticks) | 2 | 1 | 1 |
| B (**28 of 48 ticks**) | 17 | 7 | 10 |

Run B's 10 are work still in flight at the tick it was captured, not work dropped. Stated
because a reader would otherwise read 7-of-17 as a failure rate.

### ALWAYS HOLD — not worse, and the same signature

Measured **pre-stop** (STOP empties the depot). Neither run was ever stopped; both were
captured while the depot was still populated.

| run | seated | defects |
|---|---|---|
| A, tick 48 | 67 | **7** |
| B, tick 28 | 69 | **6** |

Filed band is 4/73–7/82. The defect **count** does not exceed the recorded worst (7), and
the composition is identical to the filed cause, checked vehicle by vehicle:

- `4cd2b777`, `9926e267`, `c433a36d`, `c98ef465` — **the same four ids**, zero bookings
  anywhere in the run, zero rider flags. This is `twin.ottoq_sim_seed_fleet` seating the
  fleet at run start and writing no booking row.
- 3 `emergency_staged` cars holding bookings elsewhere but none on the seat.

Said plainly: the *ratio* is higher than the best previously recorded because the seated
denominator was smaller (67 vs 82), not because more vehicles are unbooked. Pre-existing,
not a revert trigger, and not re-litigated here.

---

## 7. Adversarial pass — default REFUTED

**"0 orphans" is real, not vacuous.** Three independent lines, and the first alone would
not have been enough:

1. Six deliberate creation attempts, all refused with 23503 — including on the `NOT VALID`
   table.
2. The purge deleted 7 run rows and 168,842 child rows — *the exact operation that used to
   manufacture orphans* — and the orphan count did not move.
3. That purge cleared 2,068 rows from four tables the old enumeration could not see. Under
   the old code every one of those would now be an orphan.

**Did `ON DELETE` silently remove anything?** No. There are 0 CASCADE FKs to the run table.
Checked behaviourally, not by reading `confdeltype`: after a 168,842-row purge, `vehicles`
is still 220 and `stalls` is still 320. The one SET NULL cleared stamps only.

**Did the purge behave as claimed?** Yes, and it is registry-driven — verified by reading
the deployed function body, not the migration file: it computes the doomed set once as a
value, refuses to run on a `block`-severity defect, clears children from the registry with
no exception swallowed, then deletes the parent.

**Clock domains.** `sim_clock_*`, `raised_at_sim_clock`, `arrived_at` and `during` are SIM.
`started_at`, `ended_at`, `created_at`, `measured_at` are REAL wall clock. Tick counts are
run-domain. `ottoq_sim_stop_and_reset` writes the real clock into the sim-domain
`actual_return_at` — **no run here was ever stopped**, so there are no teardown rows to
exclude. That is a fact about the runs, not a filter applied after the fact.

**Instance health**, probed with a plpgsql loop rather than a CTE (a CTE evaluates once and
yields ten identical values): `{134.1, 1.6, 1.2, 1.2, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1}` ms.
The first sample is cold cache. No sign of the 17,748 ms host starvation.

---

## 8. What this certification found that was not asked for

**Tick cost collapses when runs accumulate unpurged.** Run A did 48 ticks in ~8 minutes.
Run B, started via the scenario entry point *without* purging first, degraded to roughly one
tick per 8 minutes — while the same tables held 7 runs' rows. After the purge cleared
168,842 rows, run C reached tick 19 within minutes on the same instance.

This is not a 0022 defect — it is the condition 0022's purge exists to prevent, and it only
appeared because the certification deliberately ran two scenario-entry runs back to back so
their ledgers would coexist. It is recorded because it is the practical argument for the
purge: **correctness and throughput are the same fix here.** It also means run B was
captured at tick 28 rather than 48; every run-B number above is labelled accordingly.

---

## 9. Still open — stated, not hidden

1. **The depot-scoped supersede write** (section 2). A later run rewrites `status` on a
   finished run's rows. Run-blind by depot. Pre-existing, unfixed.
2. **111,818 NULL-run rows**, 108,026 of them in `ottoq_events`. A foreign key permits NULL,
   so no FK can close this. Untouched deliberately — mass-deleting on a hunch was refused.
3. **`ottoq_events` keeps its 2 historical orphans.** Its FK is `NOT VALID` by choice: new
   orphans are impossible, history is not rewritten.
4. **`ottoq_run_archives` (59 orphans) has no FK on purpose** — it is the archive of a run
   that has been purged, so requiring the run to exist would defeat it.
5. **Run B reached 28 of 48 ticks.** It crossed night and produced 11 collisions, which is
   what the assertion needed, but it is not a completed 48-tick run.
