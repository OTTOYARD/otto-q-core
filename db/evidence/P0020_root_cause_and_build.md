# P0020 — the rider flag binds to a visit, and the visit is the right run's

**Migration:** `db/migrations/0020_rider_flag_consume_and_place_is_atomic.sql`
**Applied:** 2026-08-08, ledger version `20260808165323`
**Author:** Claude Opus 4.8, branch `p0020-flag-atomic-consume`, based on `origin/main` @ `8f8e464`

---

## 1. The brief, and the honest answer to it

> **2 of 16 rider flags were consumed and the cleaning VANISHED.** Both exterior
> (`f0077a3a`, `99ddf4ff`). Each carries a `recalled_visit_key` that matches NO row in
> `ottoq_visit_needs`. Neither vehicle has a rider-flagged atom on any visit.

**The cleaning did not vanish.** Read directly from the surviving rows:

| flag | `recalled_visit_key` | matching visit row | that row's atoms |
|---|---|---|---|
| `f0077a3a` exterior | `f0077a3a…:20260808200000` | **exists** | `exterior_wash`, `rider_flagged:true`, `must_do:true`, `deferrable:false`, `requires_bay:'wash_bay'`, **`status:'done'` at sim `2026-08-09T04:08:49`** |
| `99ddf4ff` exterior | `99ddf4ff…:20260809010000` | **exists** | `exterior_wash`, `rider_flagged:true`, `must_do:true`, `deferrable:false`, `requires_bay:'wash_bay'`, still pending on an `in_progress` visit |

Both rows also carry `meta.rider_flagged = true` and `meta.rider_flag_kind = 'exterior'`,
and both atoms carry the recall `why` string
*"Rider-reported exterior cleanliness issue; vehicle was recalled for this."*

So the correct statement is: **one of the two was actually washed. The other was correctly
placed and had not reached a bay when the run ended.** Neither was lost. That is a
materially different — and smaller — failure than the one reported, and saying so is the
point: *"placed" is not "cleaned", and a precise negative is a good result* cuts both ways.

**Where the "vanished" reading came from** is a real defect, and it is worse in a
direction nobody was looking.

---

## 2. The lead: confirmed as a phenomenon, refuted as the cause

> `twin.ottoq_sim_generate_service_manifest` builds `visit_key` from
> `vehicles.last_state_change`, which a BEFORE UPDATE trigger clobbers to the REAL wall
> clock, while the two failed `recalled_visit_key` values decode as SIM times matching the
> flag's own maturity. Two clock domains in one key space.

### CONFIRMED — the clock clobber is real

`public.log_vehicle_state_change` is `BEFORE UPDATE ON public.vehicles FOR EACH ROW` and
executes `NEW.last_state_change = NOW()` whenever `current_state` changes. It **overrides an
explicit sim-clock assignment made in the same UPDATE** — both `twin.ottoq_sim_wash_triage`
and `ottoq.ottoq_rider_flag_indepot_sweep` write `last_state_change = p_sim_clock` and are
silently overwritten.

It is visible in the data. **5 of 21 surviving flags** carry a `recalled_visit_key` whose
timestamp decodes to a real wall-clock instant equal to a run's `started_at`, not to any sim
time: `20260808154131` (×3, = run `56ef75fa` start) and `20260808160932` (×2, = run
`b857fd29` start). Two clock domains genuinely are sharing one key space.

### REFUTED — it is not what broke these two

Both failing keys decode to **clean SIM times that match their own recall exactly**:

* `f0077a3a…:20260808200000` — flag raised 19:56 sim, recalled 20:00 sim
* `99ddf4ff…:20260809010000` — flag raised 01:00 sim, recalled 01:00 sim

Neither is a real-clock value. The lead cannot explain either one, and the premise beneath
it (*"matches NO row"*) is false — both match a row, as shown in §1.

**The lead was not built on.** It is logged in §6 as a live but separate hazard.

---

## 3. What actually happened

```
visit_key = vehicle_id || ':' || to_char(clock, 'YYYYMMDDHH24MISS')   -- no run identifier
```

and the table's uniqueness was

```sql
UNIQUE (vehicle_id, visit_key)                            -- run-blind
```

upserted by

```sql
ON CONFLICT (vehicle_id, visit_key) DO UPDATE
  SET atoms = EXCLUDED.atoms, urgency = ..., archetype = ..., meta = ..., status = 'open'
      -- and NOT sim_run_id
```

Runs `a30661fd` (seed 20260820) and `b857fd29` (seed 20260821) **both** had
`sim_clock_start = 2026-08-08 13:00:00` and both walked the same 30-sim-min tick grid. A
vehicle arriving at the same sim minute in both runs therefore produced a **byte-identical**
`visit_key`. The later run's INSERT fell through to `DO UPDATE` and **overwrote the earlier
run's visit row**, replacing its atoms and meta with the new run's manifest while leaving
`sim_run_id` and `created_at` pointing at the **earlier** run.

### The proof, from rows rather than reasoning

Four visit rows are stamped `sim_run_id = a30661fd` **and** carry
`meta->>'rider_flagged' = 'true'`:

| vehicle | visit_key | flag actually belongs to |
|---|---|---|
| `5fe5fe42` | `…:20260808155916` | `a30661fd` ✔ own run |
| `aff36072` | `…:20260808153000` | `a30661fd` ✔ own run |
| **`f0077a3a`** | `…:20260808200000` | **`b857fd29`** ✘ |
| **`99ddf4ff`** | `…:20260809010000` | **`b857fd29`** ✘ |

Run `a30661fd` drew only **two** flags — `aff36072` and `5fe5fe42`. And
`meta.rider_flagged` can only be written `true` when the generator finds a flag for that
vehicle **in `v_run`**. Run `a30661fd` had no flag for either `f0077a3a` or `99ddf4ff`, so it
cannot have written that meta. Run `b857fd29` wrote it, through `DO UPDATE`, onto run
`a30661fd`'s row.

Those are exactly the two "vanished" flags.

### The failure is symmetric, and one half was invisible

1. **The current run's rider work becomes invisible** to every run-scoped query
   (`WHERE v.sim_run_id = f.sim_run_id` finds nothing) — reported as "the cleaning vanished".
2. **A completed run's ledger is silently rewritten after the fact** by a later run. Run
   `a30661fd` finished at 16:06:42 and its record changed at 16:01:53 and 16:03:25 under it.
   That is a black-box integrity problem well beyond rider flags, and nobody was looking
   for it.

`recalled_visit_key` being a reconstructed **string** with no referential integrity is what
let it stay silent: there was no way for the database to notice the flag and the visit had
drifted apart.

### Exterior-only was chance

The mechanism never reads `flag_kind`. It requires only a vehicle arriving at the same sim
minute in two runs sharing a `sim_clock_start`. At n = 2 the exterior clustering carries no
signal. (The certification run below was drawn with the exterior share raised to ~65% so the
sample can discriminate, as the brief asked.)

**Prior visit rows are NOT purged at run start** — 19 distinct historical `sim_run_id`s hold
visit rows on this instance right now, including 184 for `a30661fd` and 174 for `b857fd29`.
So this was not an exotic condition; it was waiting for any two runs to share a clock.

---

## 4. What 0020 changes

| # | Change | Why this shape |
|---|---|---|
| 1 | `UNIQUE (vehicle_id, visit_key)` → unique index on `(vehicle_id, visit_key, COALESCE(sim_run_id, nil-uuid))`; both upserts re-inferred onto it | Done at the **index**, not by putting a run tag in the key string. `visit_key` is also the salt for every `ottoq_sim_seeded_random(v_seed, v_visit \|\| …)` draw in the manifest — changing the string would move every draw in every run and unpin seed 424242. **This route changes no draw.** |
| 2 | `ottoq_rider_cleaning_flags.recalled_visit_id uuid` → FK to `ottoq_visit_needs(visit_id)`, `ON DELETE CASCADE` | Real referential integrity replaces a rebuilt string. CASCADE rather than SET NULL: SET NULL would fire an **UPDATE** on the flag during a purge, which the §3 guard would refuse — turning teardown into a hard failure. CASCADE deletes the row, fires no UPDATE, same end state. |
| 3 | Consume-and-place is **one step**: the manifest block only *reads* the flag and shapes the atom; the upsert gains `RETURNING visit_id`; the flag transition happens after, against that uuid. Same in the in-depot sweep. | 0019 wrote `status='recalled'` ~120 lines *before* any visit row existed. |
| 4 | Retire-or-place decided **by uuid, before the atom is shaped** | Deciding after the upsert would leave a `must_do`, non-deferrable cleaning stranded on the new visit that nothing clears — and ALWAYS HOLD would then keep a *clean* car in the depot indefinitely. |
| 5 | Runtime guard trigger, SQLSTATE `OQ020` | See §5. |
| 6 | `served_at_sim_clock` stamped by a trigger on `ottoq_visit_needs` when a rider-flagged atom reaches `status='done'` | One place, not two. The two writers today are `twin.ottoq_sim_advance_visit_atoms` and `public.ottoq_mark_visit_atoms_done`; a third added later is covered for free. |
| 7 | In-depot sweep's visit lookup scoped strictly to the run (`OR n.sim_run_id IS NULL` removed) | Same cross-run leak in another costume. |
| 8 | Sweep's catch-all handler re-raises `OQ020` | A handler that turns "this placement is a lie" into `RAISE WARNING` + `RETURN 0` would restore exactly the silence this file removes. |
| 9 | Flags re-anchor on any `sim_clock_start` rebase | See §7. |

---

## 5. The runtime guard, and its cost

`trg_ottoq_rider_flag_placement_guard` is `BEFORE INSERT OR UPDATE` on
`ottoq_rider_cleaning_flags`. On a real transition (INSERT, or a change of `status` /
`recalled_visit_id`) it refuses any non-`pending` status unless `recalled_visit_id` resolves
to a visit that **exists**, is the **same vehicle**, is the **same run**, and **carries a
`rider_flagged` atom**.

**RISK, STATED PLAINLY.** It raises, and `twin.ottoq_sim_generate_arrival_manifests` calls
the manifest generator with no handler — so a violation aborts the tick. That is deliberate.
This bug class is silent; a stopped run that says why beats a finished run that quietly lost
a customer complaint. The guard is scoped to transitions, so routine UPDATEs and teardown do
not touch it.

**Proven non-vacuous** by direct negative test on a throwaway flag row (inserted, tested,
deleted in one transaction):

| case | result |
|---|---|
| non-pending, no visit bound | **RAISED OQ020** — *"…moved to status 'recalled' with no visit bound to it"* |
| non-pending, bound to another vehicle's visit | **RAISED OQ020** — *"…points at visit …, which belongs to vehicle …"* |
| row left `pending` | no raise — correctly allowed |

---

## 6. Deliberately not changed, and why

**The `log_vehicle_state_change` clock clobber (§2) is left alone.** Once uniqueness is
run-scoped it can no longer cause a cross-run collision, which was its only path to losing
work; what remains is that some `visit_key`s are *ugly* (real-clock) rather than *wrong*.
Fixing it means either editing a BEFORE UPDATE trigger that fires on every vehicle write in
the system, or re-sourcing `v_clock` in the manifest — and `v_clock` seeds every
`ottoq_sim_seeded_random` salt, so re-sourcing it changes every draw in every run. Neither
is worth it for cosmetics. **Logged as a live residual.**

**The 3× live-playback clamp is not touched.** It is the other half of why a normally-started
run cannot reach night, but it is a playback-rate concern with no bearing on flag
correctness, and changing tick pacing underneath a metronome with its own timeout ceiling
(0012 / 0013) is not a change to ride along on a data-integrity migration.

---

## 7. The anchoring decision

**Confirmed in source first.** `public.ottoq_start_demo_run` calls
`ottoq_sim_run_scenario(...)` — which runs `ottoq_run_boot_draw`, and the draw anchors every
flag at `v_run.sim_clock_start + seeded offset` — and only **then** rebases
`sim_clock_start` to a random minute-of-day. A run started from the normal start button
anchors its flags against a clock that no longer exists, off by up to a full day.

**Decided: fix it.** 0019 routed around it by calling
`ottoq_sim_run_scenario(...,'operator_demo')` directly, which is not what the founder
presses. A feature that only works when you bypass the start button is not a working
feature.

**How:** not by rewriting `ottoq_start_demo_run` (a third function replaced for one clause),
but with `trg_ottoq_reanchor_rider_flags` on `ottoq_sim_runs`, which shifts every still-
pending flag by exactly the delta whenever `sim_clock_start` moves. Strictly more total —
it holds for `ottoq_start_demo_run`, for any future rebaser, and for a hand-run UPDATE. The
seeded offset inside the window is carried forward exactly; only the base moves, so the draw
stays deterministic.

---

## 8. Certification run

`0a3c6910`, seed **20260822**, `normal_day`, depot `1111…`, started with
`ottoq_sim_run_scenario('normal_day', 20260822, 'operator_demo')` — fixed playback,
30 sim-min per tick, 48 ticks, **08:00 → 08:00 America/Chicago**.

**Night verified, not assumed.** Night is 20:00–06:00 = ticks 24–44. The run was observed
at tick 28 / sim 22:00, tick 41 / sim 04:30, and tick 45 / sim 06:30 — it crossed the whole
of it.

**Denominator raised on purpose, and restored immediately.** `rider_flag_daily_pct` 3.0 →
12.0 and `rider_flag_interior_share` 0.70 → **0.35** at depot scope *before* run creation
(the draw happens once, at boot), both restored to 3.0 / 0.70 in the very next statement and
the pre-state preserved in `public.mig0020_policy_prestate`. The brief asked for a raised
exterior share so the sample could discriminate: the draw came out **7 exterior / 4 interior
(64% exterior)**, against 6 of 16 exterior in the run that reported the defect.

### The result

| flag kind | status | n | bound to a real `visit_id` | `served_at_sim_clock` stamped | atom genuinely `status:'done'` |
|---|---|---|---|---|---|
| exterior | `served` | **6** | 6 | 6 | **6** |
| exterior | `recalled` | 1 | 1 | — | — |
| interior | `served` | **3** | 3 | 3 | **3** |
| interior | `recalled` | 1 | 1 | — | — |
| **total** | | **11** | **11** | **9** | **9** |

* **11 of 11 flags consumed, 0 left `pending`.** 0018 left 2 of 18 stuck pending.
* **11 of 11 bound to a visit row that exists**, on the right vehicle, in the right run,
  carrying a rider-flagged atom. **0 unbound. 0 violating the guard's invariant.**
* **`served` and "atom actually done" agree exactly: 9 = 9.** That is the
  `served_at_sim_clock` undercount closed — it was 6 counted against 11 actually done.
* **The guard never fired.** No `OQ020` appears anywhere in the Postgres log for this run.
* The 2 flags still `recalled` are the honest remainder: the atom is placed on a real visit
  and had not reached a bay when the clock ran out. **Placed is not cleaned, and it is not
  reported as cleaned.**
* Exterior is no longer the failing kind — **6 of 7** exterior flags reached `done` at a 64%
  exterior share, which is the discriminating sample the brief asked for.

### What went wrong during certification, and what it found

The run **froze at tick 5** and sat there for 20 consecutive metronome calls, each rolling
the whole tick back on `idx_stalls_one_vehicle_per_stall`. `tick_count` stayed at 5 while
`next_tick_due_at` kept advancing, so from the outside it looked alive.

That is **not 0020**. It is a latent, seed-dependent deadlock in
`twin.ottoq_sim_advance_service_flow` — see `db/migrations/0021_one_vehicle_one_stall.sql`
for the full diagnosis, the `PG_EXCEPTION_CONTEXT` trace, and the three checks that rule
0020 out. 0021 fixes it at the table; the run advanced on the first metronome call after it
landed and completed the night.

---

## 9. PROTECT, re-measured after both migrations

| line | result |
|---|---|
| double bookings | **0** pairs over **4,155** booking rows — own pairwise `during && during` on (run, stall) across `held`/`active`/`done`/`interrupted`, **not** the exclusion constraint |
| orphaned FKs | **226** FKs in `public` (225 + 0020's new one), key lists generated from `pg_constraint`, **0 orphans** |
| 0010 geometry | **PASS — 0 overlapping pairs, 0 `not_assessed`** on the heading-aware oriented footprint (`relative_x/y` read as FEET, no 1.5699 conversion). **160 stalls per depot = 115 staging / 30 l2 / 10 dcfc / 3 wash_bay / 2 service_bay, both depots** |
| 0008 laundering | **0.** 114 pairs (one per vehicle, latest run — no fan-out); 16 naive value-equality flags, **all 16 are 0.000 = 0.000**; **0** under the directional `copied_after_wear` test |
| 0009 `planned_return_at` | still raises **`428C9`** on UPDATE |
| cron | **10 ON, 11 ON, 12 ON, 13 OFF** — unchanged. Cron 12 was never touched |
| drift | manifest regenerated; baseline moved `ottoq` 54 → 55 and `public` 339 → 344, **verified by name** |

### ALWAYS HOLD — stated with its definition, because the definitions differ

The filed pre-existing breach (5/65–7/82) was diagnosed as vehicles seated by
`twin.ottoq_sim_seed_fleet` **with no `ottoq_stall_bookings` row at all**. Measured on that
definition, in this run:

* seated vehicles: **69**
* seated with **zero bookings anywhere in the run**: **0**
* seated whose current seat was **never** booked in this run: **0**
* the four recurring ids (`4cd2b777`, `9926e267`, `c433a36d`, `c98ef465`): **none is seated**

**It did not get worse.** A looser reading — "no `held`/`active` booking covering the seat
right now" — gives 58 of 69, but that counts every car parked overnight whose booking has
legitimately closed to `done`, which is not the filed defect. **I do not have the exact query
behind the 5/65–7/82 figures, so I am not claiming this is the same measurement**; both
numbers are given with their definitions rather than one being presented as a comparison it
is not.
