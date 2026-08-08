# 0020 — two night-crossing runs, exterior share raised

Certifies `db/migrations/0020_rider_flag_consume_and_place_is_atomic.sql`
(applied, version `20260808165323`) and `0021_one_vehicle_one_stall.sql`
(applied, version `20260808170813`).

**The headline: 22 rider flags across two night-crossing runs on two seeds, 0 silent
drops.** The baseline this replaces lost 2 of 16 silently.

---

## 1. The two runs

| | run A | run B |
|---|---|---|
| `sim_run_id` | `0a3c6910-e7c5-4e0a-924d-745386f7e819` | `cf855696-e4c9-458d-bd4b-0962e59ee929` |
| seed | **20260822** | **20260901** |
| started with | `ottoq_sim_run_scenario('normal_day', seed, 'operator_demo')` | same |
| ticks | 48 | 48 |
| sim window | 08:00 → 08:00 CST | 08:00 → 08:00 CST |
| `sim_clock_start` | `2026-08-08 13:00:00+00` | `2026-08-08 13:00:00+00` |
| exterior share drawn | **7 / 11 = 64%** | **7 / 11 = 64%** |

Run A was drawn with `rider_flag_interior_share` 0.70 → 0.35; run B with 0.70 → **0.30**,
`rider_flag_daily_pct` 3.0 → 12.0 in both. Both knobs restored to 3.0 / 0.70 in the
statement immediately after run creation (the draw happens once, at boot). **Verified
restored at the end of this session**, `updated_by = migration_0018` on both rows.

**Night verified by observation, not assumed.** Night = 20:00–06:00 = ticks 24–44.
Run B was read at tick 26 (21:00), tick 31 (23:30), tick 33 (00:30) and tick 42 (05:00),
then completed at tick 48 / 08:00. It crossed the whole of it.

**Both runs completed naturally.** `ottoq_sim_stop_and_reset` was never called, so there
are **no teardown rows** — the trap where stop writes the real wall clock into sim-domain
`actual_return_at` cannot apply. Confirmed: max `actual_return_at` for run B is
`2026-08-09 13:00:00+00` (sim domain, = sim_clock_end), not the 17:30 wall clock.

### Clock domain of every timestamp used below

| column | domain | evidence |
|---|---|---|
| `raised_at_sim_clock`, `recalled_at_sim_clock`, `served_at_sim_clock` | **SIM** | inside the run's 13:00→13:00 sim window |
| `dispatched_at`, `returning_started_at`, `actual_return_at` | **SIM** | same window; run B's real wall window is 17:22–17:30 and no value falls in it |
| `ottoq_sim_runs.started_at` / `ended_at` | **REAL** | 17:22:21 → 17:30:28 |

---

## 2. THE ASSERTION — zero silent drops

A flag is *silently dropped* if it is non-`pending` (the ledger claims it was handled) but
its vehicle has **no rider-flagged atom on a real visit**. Resolved by `recalled_visit_id`,
and the visit must exist, be the **same vehicle**, the **same run**, and carry the atom.

| run | kind | status | n | bound to real `visit_id` | atom on right veh + right run | atom `status:'done'` | `served_at_sim_clock` |
|---|---|---|---|---|---|---|---|
| A | exterior | `served` | 6 | 6 | 6 | 6 | 6 |
| A | exterior | `recalled` | 1 | 1 | 1 | — | — |
| A | interior | `served` | 3 | 3 | 3 | 3 | 3 |
| A | interior | `recalled` | 1 | 1 | 1 | — | — |
| B | exterior | `served` | **7** | 7 | 7 | **7** | 7 |
| B | interior | `served` | **4** | 4 | 4 | **4** | 4 |
| **total** | | | **22** | **22** | **22** | **20** | **20** |

* **22 of 22 consumed, 0 left `pending`.**
* **SILENT DROPS: 0 of 22.** Broken out: 0 unbound, 0 pointing at a missing visit,
  0 wrong vehicle, 0 wrong run, 0 missing the atom.
* Baseline was **2 of 16 dropped**. 0018 before it left 2 of 18 stuck visibly `pending`.

### Is that real, or vacuous? — the sample can discriminate

The reported defect was **exterior-only** at n=6. This certification ran **14 exterior
flags across the two runs (64% of 22)**, more than double the sample that produced the
defect, and **13 of 14 exterior flags reached `done`**. The one that did not is *placed on
a real visit*, not lost. **Exterior is no longer the failing kind, and there were enough of
them for that to mean something.**

---

## 3. Placed vs cleaned — reported separately, on purpose

* **20 of 22 genuinely cleaned** — a rider-flagged atom at `status:'done'` on the visit.
* **2 of 22 placed but not cleaned** — both in run A, one exterior one interior. The atom
  is committed on a real visit and had not reached a bay when the 24 sim-hours ran out.
  They are reported as `recalled`, carry no `served_at_sim_clock`, and are **not** counted
  as cleaned anywhere above.
* Run B cleaned **11 of 11**.

**`served_at_sim_clock` now matches reality exactly: 20 stamped, 20 atoms actually done.**
The baseline undercounted 6 stamped against 11 actually done, because only the arrival
RETIRE branch stamped it and that branch requires the car to arrive *again* — a car cleaned
on its last visit of the run was never stamped. The new `AFTER UPDATE` trigger on
`ottoq_visit_needs` closes it.

---

## 4. The root cause, re-verified independently — and one correction

The fix is run-scoped uniqueness: `UNIQUE (vehicle_id, visit_key)` replaced by
`ottoq_visit_needs_vehicle_visit_run_uk` on
`(vehicle_id, visit_key, COALESCE(sim_run_id, '000…0'))`. **Confirmed present.**

**Run B is a live reproduction of the collision condition.** It shares
`sim_clock_start = 2026-08-08 13:00:00+00` with run A, the same depot and the same
30-sim-min grid — so the same vehicle arriving at the same sim minute produces a
**byte-identical `visit_key`**.

> **15 `(vehicle_id, visit_key)` pairs are shared between run A and run B.**

Under the old run-blind constraint those 15 would have fallen through to `DO UPDATE` and
overwritten run A's rows. Measured after run B finished:

| check | result |
|---|---|
| run A's 11 rider-flagged visit rows still present | **11 of 11** |
| `md5(atoms)` byte-identical to the pre-run-B snapshot | **11 of 11** |
| `sim_run_id`, `visit_key`, `meta.rider_flagged` unchanged | **11 of 11** |
| run A silent drops re-measured *after* run B | **0** |

Snapshot preserved in `public.cert0020_runA_snapshot` (captured at run B tick 0).
**This is the decisive evidence**: the collision was reproduced, and nothing was lost.

### Correction to a claim I made mid-session

I first read four historical runs as showing the clobber (more rider-flagged visit rows
than flags drawn). **Three of those four were wrong.** `ottoq_visit_needs.sim_run_id` has
**no foreign key** to `ottoq_sim_runs` — 13 purged runs leave visit rows behind whose flag
rows were deleted with the run. That produces "flagged rows > 0, flags = 0" with no
clobbering involved. Only **`a30661fd`** is genuine evidence: its run row and its flag rows
both still exist, it drew **2** flags, and it carries **4** rider-flagged visit rows.
The original diagnosis stands on that one case; my broader reading did not.

*(Filed, not fixed here: `ottoq_visit_needs.sim_run_id` has no FK and no purge, so visit
rows outlive their runs. Unrelated to rider flags.)*

---

## 5. The runtime guard — proven non-vacuous by negative test

`trg_ottoq_rider_flag_placement_guard`, `BEFORE INSERT OR UPDATE`, raising `OQ020`.
Tested directly on a throwaway flag row (inserted, tested, deleted — **0 residue**):

| probe | result |
|---|---|
| insert `status='pending'`, no visit bound | **allowed** (correct) |
| move to `recalled` with **no visit bound** | **OQ020 raised** — *"…moved to status 'recalled' with no visit bound to it"* |
| move to `recalled` bound to **another vehicle's** visit | **OQ020 raised** — *"…points at visit …, which belongs to vehicle …"* |
| move to `recalled` bound to another vehicle's **genuinely rider-flagged** visit | **OQ020 raised** (correct — wrong vehicle) |
| back to `pending`, no visit | **allowed** (correct) |

**Did it ever fire wrongly? No.** All 22 legitimate placements across both runs were
allowed — had the guard been over-tight, those flags would have aborted their tick and
stuck at `pending`, and **0 of 22 are pending**. No `OQ020` appears in the Postgres log for
either run.

**Stated risk, not hidden:** the guard raises, and `twin.ottoq_sim_generate_arrival_manifests`
has no handler, so a genuine violation aborts the tick. That is deliberate — this bug class
is silent, and a stopped run that says why beats a finished run that quietly lost a
customer complaint.

---

## 6. No regression from 0019

| line | run A | run B | verdict |
|---|---|---|---|
| dispatch churn — **honest unconsumed test** (`dispatched_at >= raised AND (consumed IS NULL OR dispatched_at < consumed)`) | **0** of 20 | **0** of 21 | PASS |
| dispatch churn — naive test, for contrast only | 6 of 20 | 10 of 21 | *the naive test lies; not used* |
| in-depot sweep path exercised | 7 of 11 | 4 of 11 | PASS — both paths live |
| recall path exercised | 4 of 11 | 7 of 11 | PASS |
| one raise, one firing | 11 flags → 11 placements, no double-recall | same | PASS |
| recall **latency** (flag due → `returning_started_at`), sim domain | n=3, median **19.0** min, max **27.0** | n=4, median **14.5** min, max **19.0** | **0 over one tick (30 min)** in both |

**Honest note on latency.** The baseline is *median 6 min, max 28 min, 0 of 10 over one
tick*. Max and the one-tick bound both hold. The **median is higher** (19.0 / 14.5 vs 6),
but n is 3 and 4 here against 10 at baseline — because most flags are now handled
**in-depot** rather than by recall, which is 0019's hold behaviour working as designed.
I am not claiming an improvement, and I am not claiming the medians are comparable at
this sample size.

---

## 7. PROTECT — re-measured, whole list

| line | result | verdict |
|---|---|---|
| double bookings | **0 pairs** over **1,901** booking rows — own pairwise `during && during` on (run, stall) across `held`/`active`/`done`/`interrupted`, **not** the exclusion constraint. Run B alone: 0 over 406 | PASS |
| orphaned FKs | **226 FKs in `public`**, key lists generated from `pg_constraint`, **0 orphans, 0 uncheckable** | PASS |
| 0010 geometry | **0 overlapping pairs, 0 `not_assessed`**, heading-aware oriented footprint, `relative_x/y` read as **FEET** (no 1.5699 conversion). **160 per depot = 115 staging / 30 l2 / 10 dcfc / 3 wash_bay / 2 service_bay, both depots** | PASS |
| 0008 laundering | **0 directional.** 113 pairs (one per vehicle, run B); 15 naive value-equality hits, **all 15 are 0.000 = 0.000** on freshly-washed cars | PASS |
| 0009 `planned_return_at` | still raises **`428C9`** — *"column can only be updated to DEFAULT"* | PASS |
| cron | **10 ON, 11 ON, 12 ON, 13 OFF** — unchanged. **Cron 12 was never touched** | PASS |
| drift | **A (applied, no file) = 0; B (file, not applied) = 0; C (name mismatch) = 0.** `ottoq` routine count 55, matching the recorded baseline | CLEAN |

### ALWAYS HOLD — pre-existing, did not get worse

Measured on the filed definition (seated with **zero `ottoq_stall_bookings` rows anywhere**):

* seated vehicles: **73**
* seated with zero bookings anywhere: **4**
* they are **exactly the four filed ids** — `4cd2b777`, `9926e267`, `c433a36d`, `c98ef465`
* **none is rider-flagged**

**4 of 73**, against the filed **5/65 – 7/82**. Same four ids, same signature, at or below
the filed range. **It did not get worse.** Not re-litigated.

---

## 8. Adversarial — starvation from the blocking dispatch?

**Refuted.** The concern is that holding a flagged car presents as a deadlock under
oversubscription rather than as a parameter problem.

* run B: **0 of 11 never served**. Every held car was cleaned and released.
* wash bay utilisation in run B: **9.7%** — 420 booked bay-minutes against 4,320 available
  across 3 bays over 24 sim-hours, all 3 bays used. **The bays are nowhere near saturated,
  so the wait is not bay contention.**
* recall → served: run A median 98 min, run B median 132 min (max 340). That is the
  **atomic full-service visit** — charge to ~100% *then* all services before redeploy —
  not starvation. Consistent with the Full-Service Visit Doctrine.

**Unrecognised atom names stay total.** There are **0 `detail_bay` stalls** in the
database. The interior atom carries `requires_bay:'detail'`, and all **13**
`interior_deep_clean` bookings in run B landed on **`wash_bay`**. Nothing demanded a
stall type that does not exist.

---

## 9. What this does not prove

* Two runs, 22 flags. Not a distribution.
* The 2 unfinished placements in run A are unfinished because the clock ran out. A longer
  run would probably clean them; that was not tested.
* `log_vehicle_state_change` still clobbers sim-domain `last_state_change` to the real wall
  clock — **live but separate**, logged in the 0020 file. Once uniqueness is run-scoped it
  can no longer *lose* work; it only makes some `visit_key`s ugly rather than wrong.
* `ottoq_visit_needs.sim_run_id` has no FK and no purge (section 4). Filed, not fixed.
