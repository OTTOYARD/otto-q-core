# 0023 — A finished run's ledger is read-only, and a run-scoped read takes the run

**Migration** `db/migrations/0023_a_finished_run_is_read_only.sql`, ledger **20260808193142**, applied.
**Battery** `db/checks/0023_finished_run_readonly_certification.sql` (re-runnable).
**Instance** `gxdrcyphqjzjsuhxuqtg`.

This closes a trilogy. **0020** fixed WHICH row a run writes. **0022** fixed WHETHER a row still has
a run. **0023** fixes a run writing into ANOTHER run's rows.

---

## The one-paragraph version

A run now closes its own outstanding work when **it** ends, instead of leaving it for the next run to
sweep up. That removed the last write that reached across runs, and run A's ledger came through a
second run **byte-identical on all 15 columns, including `status`** — the column 0022 measured moving
on 99 of 182 rows. Separately, the energy reads now take the run they are *asked* about rather than
whichever run happens to be newest, so a finished run's grid numbers stay the finished run's. Where a
run genuinely measured no energy, the read returns nothing rather than borrowing a number from
somewhere else.

---

## The two premises in the brief that the code did not support

Both were checked against the live database before anything was built, and neither was built on.

**"`ottoq_build_decision_frame` has no run scoping at all."** It has had run scoping since 0022
(20260808182226). The named orphan runs `29b72b2b…` and `6256a99f…` no longer exist — 0022's purge
deleted them along with their 28,789 and 5,825 rows. The census the brief quotes is pre-0022.
**The real defect was one level down and is genuine:** `ottoq_current_sim_run_id()` is a *global*
lookup ("the running run, else the most recently started"). It is not the run the caller asked about.
`ottoq_capture_decision_snapshot`, `ottoq_api_twin_get_state` and `ottoq_score_run` each name their run
in their own signature and then threw it away at the energy read. That is what 0023 fixes.

**"Narrow the supersede so it cannot touch a terminal run's rows."** The start button
(`ottoq_start_demo_run`) sets the prior run to `aborted` *before* calling `ottoq_sim_run_scenario`, so
on the button path the previous run is already terminal when the supersede runs. A rule of the form
"do not touch a terminal run's rows" would have cleared **nothing** on the path actually used, while the
stale rows remain reachable — `idx_visit_needs_open_by_vehicle` is a partial index on
`(vehicle_id, created_at DESC) WHERE status IN ('open','in_progress')`, an index that exists precisely
to serve run-blind "open needs for this vehicle" lookups.

## Why the supersede had to reach across runs — the defect was at the other end

`ottoq_sim_stop_and_reset` finalised sessions, bookings, dispatches, stalls and vehicles and **did not
touch `ottoq_visit_needs` at all**. A properly stopped run left its needs open forever, and the only
code that ever closed them was the *next* run's start. That is why 0022 measured 99 of run A's rows
moving. 0023 moves the closing act to the run being closed, via an `AFTER UPDATE OF status` trigger on
`ottoq_sim_runs` — total by construction, because stop, abort, supersede and natural end-of-clock all
pass through one place. The start-time supersede then narrows to the one class no run transition can
reach: **ownerless** needs, `sim_run_id IS NULL`.

---

## The runs

| | RUN A | RUN B |
|---|---|---|
| sim_run_id | `ca5d5e38…` (seq 949) | `d797d848…` (seq 950) |
| seed | 20260840 | 20260841 |
| entry point | `ottoq_sim_run_scenario('normal_day', seed, 'operator_demo')` | same |
| `sim_clock_start` | `2026-08-08 13:00:00+00` = **08:00:00 CST** | **byte-identical** |
| playback | fixed, **30.0 sim-min/tick** (measured) | same |

The two runs share a `sim_clock_start` because `ottoq_sim_run_scenario` pins it to
`date_trunc('day', now() AT TIME ZONE 'America/Chicago') + 8h` for `run_by='operator_demo'`. **Nothing
was rigged** — the seeds are *different*, and the collision is the shipped default behaviour of the
entry point.

**Night crossing, measured not assumed** (from `ottoq_tick_clock_log`, run A): 48 ticks logged,
avg 30.0 sim-min each, 08:30 CST → 08:00 CST next day, **20 night ticks, first night tick 24, last 43** —
the 20:00–06:00 band exactly where the recipe says it should be.

### Clock domains, stated once
SIM: `sim_clock_*`, `arrived_at`, `dispatch_due_at`, `raised_at_sim_clock`, `recalled_at_sim_clock`,
booking `during`. REAL: `started_at`, `ended_at`, `created_at`, `captured_real`, `meta.closed_at`.
**Teardown rows:** `ottoq_sim_stop_and_reset` writes the REAL wall clock into the sim-domain
`actual_return_at`. **Runs A and B were never stopped** — both reached `status='completed'` on their own
at `sim_clock_end` — so there is no teardown row in either to exclude. That is a fact about these runs,
not a filter. (Run A's flag timestamps were separately confirmed to lie inside A's own sim window, so
the recall-latency and churn measures below are in the sim domain and are valid — unlike on a
live-clock run, where `recalled_at_sim_clock` carries the real clock.)

---

## 1. THE ASSERTION — colliding keys first

> A zero-collision result would make everything below vacuous, so the collision count is
> reported first and on its own.

| | |
|---|---|
| **colliding `visit_key`s, byte-identical across runs A and B** | **6** |
| distinct vehicles involved | 6 |
| forced? | **no** — different seeds (20260840 / 20260841); the keys collide because the two runs share `sim_clock_start` and the same 30-min tick grid |

For scale, 0022's pair produced 11. Six is fewer but non-zero, so **the test is not vacuous**.

### Run A's ledger, before run B existed vs after run B finished — column by column

Run A reached `status='completed'` on its own at tick 48. Its ledger was snapshotted at that
moment into `cert0023_a_visitneeds` (202 rows). Run B then started on the identical
`sim_clock_start` and ran its own 48 ticks. Run A's rows were then re-read and compared **one
column at a time** — a whole-row md5 can hide a difference behind a hash.

| measure | result |
|---|---|
| rows compared | **202** |
| columns compared | **all 15** |
| columns with any difference | **0** |
| **`status` — the column 0022 measured moving on 99 of 182 rows** | **0 differing rows** |
| rows lost | **0** |
| rows appeared | **0** |
| run A rows in table now | 202 = 202 |

Measured at two separate points: **immediately after run B's start** (which is where 0022's 99
rows moved) and **after run B completed**. Both: 0 differences on all 15 columns.

**This is not vacuous through inactivity.** While run A's 202 rows sat frozen, run B wrote **177
rows of its own** into the same table (379 rows total). The table was under active write the whole
time; only the finished run's rows were untouchable.

### Where the status move went — it did not disappear

Closing an open need when a run ends is correct and necessary. 0023 moves *when and by whom*.

Run A's rows, mid-run (tick 39) → at its own terminal transition:

| mid-run status | at terminal | rows |
|---|---|---|
| `in_progress` | `superseded` | 97 |
| `superseded` | `superseded` | 70 |
| `open` | `superseded` | 19 |

Of the 202 rows, **109 carry `closed_by='ottoq_close_run_needs'`, `close_reason='run_completed'`** —
closed by run A's *own* completion, stamped and attributable. The other 93 had already been
superseded by normal in-run mechanics and carry no stamp. Run B closed **103** of its own the same
way. Neither run touched the other's.

### The stop path, measured on a live run first

Before the A/B pair, the live run 947 (40 open needs) was stopped with
`ottoq_sim_stop_and_reset`. Before 0023 that function did not reference `ottoq_visit_needs` at all.

| | |
|---|---|
| rows at stop | 40 |
| open/in_progress at stop | **40** |
| superseded after stop | **40** |
| stamped `closed_by='ottoq_close_run_needs'` / `close_reason='run_completed'` | **40** |
| left open | **0** |

### The trigger's WHEN clause, proved behaviourally (scaffold, rolled back)

| step | open rows | stamped |
|---|---|---|
| 5 needs reopened while the run is `running` | 5 | — |
| `running` → **`paused`** — must NOT close (a paused run is still live) | **5, unchanged** | — |
| `paused` → **`aborted`** — must close | **0** | **5**, `close_reason='run_aborted'` |

The scaffold was rolled back and the rollback verified: run A is still `completed`, still 202 rows,
still 0 open, and the 15-column diff is still 0.

---

## 2. THE ENERGY READS

### Does the frame return only this run's snapshot?

Probed with run A **finished** and run B **live at the same depot** — the case that decides it.

| probe | result |
|---|---|
| `frame(depot1, runA_FINISHED)->energy` | `at 2026-08-09T13:00Z`, grid 0.00, building 84.50 — **run A's own final row** |
| `frame(depot1, runB_LIVE)->energy` | `at 2026-08-08T16:00Z`, building 168.30 — **run B's own row** |
| `frame(depot1)` 1-arg, kept for compatibility | identical to run B (delegates via `ottoq_current_sim_run_id()`) |

**They differ.** Same depot, same instant, two different answers keyed by the run id. Under the
global lookup both would have returned run B's numbers, and a frame stamped run A would have
carried run B's grid import.

### Total behaviour when a run has no snapshot — tested, not asserted

| probe | result |
|---|---|
| `frame(depot2, runB)` — depot 2 has **never** had a run-tagged row | **JSON null** |
| `frame(depot1, run_with_zero_snapshots)` | **JSON null** |
| `frame(depot1, nonexistent_run_uuid)` | **JSON null** |
| `ottoq_energy_cost_for_run(run_with_zero_snapshots)` | **all zeros, `snapshots = 0`** |
| `ottoq_energy_cost_for_run(runA)` | its own 48 snapshots, $296.33 |

It never falls back to another run, never to a depot-wide row, never to a default, and it does not
raise. Depot 2 returns null rather than one of the 452 untagged rows sitting there.

### The dead-run leak, both depots

The runs the brief named (`29b72b2b…`, `6256a99f…`) **no longer exist** — 0022's purge removed them
with their 28,789 and 5,825 rows, so that specific leak cannot recur. What remains is measured:

| depot | untagged rows | newest row (sim) |
|---|---|---|
| `1111…` | 2,455 | **2026-08-15 23:00** |
| `2222…` | 452 | 2026-06-23 08:00 |

**2,907 NULL-run rows, exactly as the brief states.** They are excluded **by construction**:
`se.sim_run_id = <uuid>` evaluates to NULL, not TRUE, for every one of them. No extra predicate.
This is not academic — the newest row at depot 1 by sim timestamp is an untagged row dated
**2026-08-15, a sim week past run A's clock**, and an unscoped `ORDER BY timestamp DESC LIMIT 1`
returns exactly that row. The run-scoped read does not. They are named, excluded, and **left in
place** — deleting 2,907 rows nobody has justified is the unearned action 0022 exists to prevent.

### Every caller passes its own run

| routine | call site |
|---|---|
| `ottoq_api_twin_get_state` | `ottoq_build_decision_frame(r.depot_id, r.sim_run_id)` |
| `ottoq_capture_decision_snapshot` | `ottoq_build_decision_frame(p_depot_id, p_sim_run_id)` |
| `ottoq_score_run` | `ottoq_build_decision_frame(v_run.depot_id, p_sim_run_id)` |

**Row-level attribution of what was actually recorded.** For every decision snapshot written during
these runs, the energy block was matched back to a `site_energy_snapshots` row **of the same run**,
on both timestamp and `grid_import_kw`:

| run | snapshots | matched own run's row | not matched |
|---|---|---|---|
| A | 24 | **24** | **0** |
| B | 4 | **4** | **0** |

**The scorer, quantified.** `ottoq_score_run` now records each run's own peak:

| run | `energy_peak_kw` recorded | that run's own max | depot-wide max |
|---|---|---|---|
| A | **510.20** | 510.20 | 1280.00 |
| B | **376.20** | 376.20 | 1280.00 |

The old unfiltered depot-wide `MAX(grid_import_kw)` would have written **1280.00 for both runs**.

### Which published figures this taints — NOT re-certified here

Do not re-quote until re-certified against a run made after 0023:
* the **−41% grid-peak** headline (already flagged);
* `ottoq_ab_runs.energy_peak_kw` and `.peak_demand_pct_of_cap` for every row written before 0022;
* any $/day or demand-charge figure from `ottoq_energy_cost_for_run` for a run that wrote no tagged
  snapshot — those came from the wall-clock depot-wide fallback removed by 0023;
* the `energy` block of any `ottoq_decision_snapshots` row recorded for a run that was not the
  globally-newest run at record time.

0023 makes these honest **going forward**. It does not restate them.

---

## 3. Does the supersede still do its job?

Yes — but the honest answer is that the **start-time clause is now vacuous, by design**.

| check | result |
|---|---|
| open needs belonging to a **terminal** run, anywhere in the database | **0** |
| **ownerless** open needs (`sim_run_id IS NULL`) before run B started | **0** |
| ownerless open needs now | **0** |

The narrowed clause (`sim_run_id IS NULL`) matched **zero rows** in this certification. **That is a
vacuous test and I am calling it vacuous.** It is vacuous because the trigger got there first: every
need now belongs to a run, and every run closes its own on the way out. The clause remains as the
backstop for the one class no run transition can reach. What is *not* vacuous is the invariant it
exists to protect — **0 open needs on a terminal run, globally** — and that is measured above and
holds. Run B started into a clean world without any later run reaching back to make it so.

---

## 4. PROTECT — re-measured

| item | bar | measured | verdict |
|---|---|---|---|
| double-bookings, own pairwise `during && during`, **within a run** | 0 | **A 0, B 0** | PASS |
| orphaned FKs, key list **generated from `pg_constraint`** | 0 beyond the declared pair | **271 keys, 2 orphans** — `fk_ottoq_events_sim_run`, `convalidated=false` | PASS |
| 0010 geometry, oriented footprint, `relative_x/y` in FEET | 0 overlap, 0 not_assessed | **320 assessed, 0 not_assessed, 0 overlapping** | PASS |
| 0010 mix, both depots | 160 = 115/30/10/3/2 | **both depots exactly 115/30/10/3/2** | PASS |
| 0008 laundering, **directional** | 0 | **1 value-equality pair (0.328), but the copy line is ABSENT from the live `ottoq_wear_mark_serviced`** — see below | PASS |
| 0009 `planned_return_at` | raises 428C9 | **428C9**, `attgenerated='s'` | PASS |
| rider flags — 0 silent drops | 0 | **A 3 flags, B 2 flags; 0 visit-missing, 0 wrong-vehicle, 0 wrong-run, 0 atom-missing** | PASS (small denominator) |
| dispatch churn, **unconsumed** test | 0 | **A 0 of 6, B 0 of 2** (naive metric would have said 3 and 0) | PASS |
| recall latency | 0 over one 30-min tick | **A n=1, 21 min, 0 over a tick; B n=0** | PASS but **near-vacuous** |
| in-depot sweeps fire | non-zero | **A: 2,510 task starts across all 48 ticks, 265 stall assignments, 255 redeployments, 22 bay reconciles** | PASS |
| cron 10/11/12 ON, 13 OFF | — | **10 ✓ 11 ✓ 12 ✓ ON, 13 OFF** — cron 12 never touched | PASS |
| drift | CLEAN | **CLEAN** — 0 applied-not-in-manifest, 0 manifest-not-applied, counts match **public 349 / ottoq 55 / twin 71** | PASS |
| 0022 run-scope registry guard | 0 defects | **0** | PASS |
| 0022 FKs + registry-driven purge intact | not weakened | **271 FKs, 115 `NO ACTION`; purge cleared 29,482 rows across 32 tables, 158 evidence rows preserved, no FK violation** | PASS |

**Laundering, precisely.** 316 profile/wear pairs; **1** has `exterior_soil_level = round(soil_index,3)`
at 0.328, below the 0.45 wash band. Rather than argue from statistics (~0.3 such matches are expected
by chance at 3 decimal places across 316 pairs), the structural test settles it: the laundering
assignment `exterior_soil_level = COALESCE(round(v_soil, 3), p.exterior_soil_level)` is **absent**
from the live `ottoq_wear_mark_serviced`. The 0008 gate holds; the single match is a coincidence, not
a copy.

**Placed vs cleaned, reported separately — "placed" is not "cleaned".**

| run | rider-flagged atoms | CLEANED (`done`) | PLACED, not done |
|---|---|---|---|
| A | 3 | **2** | 1 |
| B | 2 | **0** | **2** |

Run B placed both flagged washes and finished neither before its clock ran out. That is a true
negative result, reported as one.

### ALWAYS HOLD — pre-existing, reported honestly

Measured **before** any stop, on seated stalls (occupancy is a before-the-stop measure).

| run | seated | defects | ratio |
|---|---|---|---|
| A | 67 | **5** | **7.5%** |
| B | 69 | **4** | **5.8%** |

Filed band is 4/73–7/82, i.e. 5.5%–8.5%. Both runs sit **inside** the filed band on count and on
ratio. **It did not get worse.**

* **Run B is exactly the filed picture**: the same four ids — `4cd2b777`, `9926e267`, `c433a36d`,
  `c98ef465` — each with **zero bookings anywhere** and **zero rider flags**.
* **Run A carries those same four, plus one more**: `a1111111-0001-0001-0001-000000000005`, which has
  a **different signature** — it holds 3 bookings, where the filed four hold none. So it is not the
  `twin.ottoq_sim_seed_fleet` cause; it is a car still seated at the capture instant whose booking for
  that stall had already gone to `released`/`done`. Run B, captured the same way, does not show it.
  **Named, not swept up, and not re-litigated.** 0023 writes to neither `stalls` nor
  `ottoq_stall_bookings`, so it is not a plausible cause.

A measurement trap worth recording: an 8-character `vehicle_id` prefix is **not unique** in this
fleet — six vehicles share the `a1111111` prefix, and truncating to 8 chars made one vehicle look
like four. The table above uses full uuids. Separately confirmed: **0 vehicles are seated in more
than one stall**, so `one_vehicle_one_stall` holds.

---

## 5. ADVERSARIAL — default REFUTED

**"Byte-identical is real only because nothing collided."** Refuted. 6 byte-identical `visit_key`s
across 6 vehicles, from *different* seeds. And run B wrote 177 rows into the same table during the
window, so the table was not merely idle.

**"The runs did not really cross night."** Refuted, from `ottoq_tick_clock_log`, not from the recipe:
48 ticks, avg **30.0** sim-min, **20 night ticks, first night tick 24, last 43**.

**"Scoping the energy read made the cockpit or scorer return NULL where it used to return a number."**
Partly true, and acceptable. For a **live** run the cockpit returns real numbers (verified above), so
there is no regression on the demo path. The behaviour changes only for a run that wrote **no
snapshot of its own** — and exactly **1 of the 8 runs** in the database is in that state. It now
returns null / `snapshots=0` instead of a number borrowed from another run's rows. A null that says
"this run measured nothing" is true; an 812 kW borrowed from a dead run is not. **Empty is not clean,
but it beats confidently wrong.**

**"The narrowed supersede starves or deadlocks something."** No starvation: 0 open needs on any
terminal run, 0 ownerless open needs, both runs completed all 48 ticks, 0 runs in `failed`. No
deadlock observed; the trigger touches only rows belonging to the row being transitioned, in the same
transaction as the status update, so it adds no new lock ordering. **Honest limit:** `pg_stat_database`
reports 54 cumulative deadlocks with a NULL `stats_reset`, so that counter is lifetime and I could not
establish a before/after baseline — I am not claiming a delta from it. The operational signal instead:
**53 cron runs during the certification, 1 failure**, and that failure is fully explained — it is the
metronome **I** cancelled with `pg_cancel_backend` at 19:47:19 to take the run lock for the stop,
before run A existed.

**"The vacuous parts were quietly reported as passes."** Called out explicitly: the start-time
supersede clause matched **0 rows** (vacuous by design); recall latency is **n=1 in A and n=0 in B**
(near-vacuous, small denominator); rider-flag denominators are 3 and 2, not the 19–22 of earlier
certifications.

**Tick throughput.** Avg tick cost **A 1,858 ms / B 1,768 ms** — no collapse, unlike 0022 where two
coexisting ledgers drove it to ~1 tick per 8 minutes. The purge was taken **before** run A, and run
A's ledger was deliberately **not** purged afterwards so it would survive for the diff.

---

## 6. Verdict

| claim | verdict |
|---|---|
| A finished run's ledger is read-only across a later run | **PROVEN** — 202 rows, 15 of 15 columns, 0 differences, with 6 colliding keys and 177 concurrent writes |
| A run closes its own needs at its own terminal transition | **PROVEN** on stop (40/40), natural completion (A 109, B 103) and abort (scaffold, 5/5) |
| Pause does not close a live run's needs | **PROVEN** |
| A run-scoped energy read takes the run it is asked about | **PROVEN** — finished A and live B return different numbers at the same depot |
| Total behaviour with no snapshot | **PROVEN by test** — JSON null / `snapshots=0`, never a fallback, never a raise |
| PROTECT | **no regression** |

**0020 fixed which row a run writes. 0022 fixed whether a row still has a run. 0023 stops a run
writing into another run's rows — and the ledger came through byte-identical end to end.**
