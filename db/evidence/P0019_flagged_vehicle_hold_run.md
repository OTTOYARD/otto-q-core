# 0019 — one night-crossing run against the applied migration

Run `56ef75fa-b543-4188-965c-a2959fc838de`, scenario `normal_day`, **seed 6666** —
deliberately the same seed as run A of the 0018 measurement session, so the draw is
identical and the two runs are directly comparable.

Sim window **2026-08-08 17:34 → 2026-08-09 17:34 UTC**, a full 24 sim-hours, 48 ticks,
~5 real minutes. Fixed playback, 30 sim-min per tick. The clock **verified** to pass the
whole 20:00–06:00 night window rather than assumed: tick 7 = 21:04, tick 13 = 00:04,
tick 19 = 03:04, tick 23 = 05:04.

Instance probed before (`generate_series(1,1000000)` ×10 inside a plpgsql loop, not a
CTE): 203, 197, 241, 198, 199, 195, 200, 198, 192, 192 ms. After: 202, 225, 191, 192,
204, 191, 192, 191, 192, 191 ms. Healthy at both ends, so nothing below is contaminated
by the host starvation this instance has shown before.

Seed 6666 draws **3 rider flags**, all `interior`, on the same three vehicles as run A:

| vehicle | flag due (sim) | state at tick 0 |
|---|---|---|
| `37aee690` | 2026-08-08 13:05 — **already past** the run's 17:34 start | `charge_complete_holding` |
| `87098f16` | 2026-08-08 18:11 — 37 min into the run | `en_route_to_depot` |
| `b696f1b8` | 2026-08-09 02:24 — 8.8 h into the run | `en_route_to_depot` |

`37aee690` is the car that in run A was **recalled twice** over 16 sim-hours.
`b696f1b8` is the car that in run A **arrived 02:04, matured 02:24, and then sat in
`staged_for_departure` for 15 more sim-hours**.

---

## What actually happened

### (i) No vehicle was dispatched owing a due flag — 0, against 9 of 10 before

Every dispatch of a flagged vehicle in this run, with its own denominator:

| vehicle | dispatched (sim) | trigger | flag due | flag age at dispatch | dispatched while owing? |
|---|---|---|---|---|---|
| `87098f16` | 08-08 12:22 | `prime_inbound` | 18:11 | **−349 min** | **no** |
| `b696f1b8` | 08-08 11:19 | `prime_inbound` | 02:24 (+1d) | **−904 min** | **no** |
| `37aee690` | *(never dispatched)* | — | 13:05 | — | **no** |

**0 of 2 dispatches went out owing a due flag.** In run A it was **9 of 10**, at flag
ages of +43 to +1,349 minutes. Both surviving dispatches left hours *before* their flag
came due, which is the only kind of flag-linked departure the design permits.

`37aee690` — the double-recall car — was **never dispatched at all**. Its flag was
already due when the run's clock was rebased to 17:34, so the hold applied from tick 0
and it stayed in the depot until the work was on its visit. **It was not recalled twice,
because it was not sent out once.**

`twin.dispatch_refused_rider_flag` fired **0 times**. That is the designed outcome, not
a missing feature: the planner cursor declines to select a flagged vehicle, so the
refusal at the door is the backstop it was written to be and should stay silent.

### (ii) The in-depot path fired twice, and put a car in a bay the same tick

`ottoq.rider_flag_serviced_in_depot` was emitted **2 times**, each `flags_actioned: 1`,
`visits_appended: 1`, `visits_opened: 0` — both flags landed on a visit the car was
already having, so no visit had to be invented.

* **`87098f16`** — flag due 18:11. Sweep appended the atom at **18:34, the next tick**.
  Booking on **`NASH-WSH-01`**, `purpose='detail'`, `need_atom='interior_deep_clean'`,
  window **18:34 → 19:03**, state **`done`**. The atom reads
  `interior_deep_clean[done, rider_flagged, raised_in_depot]`.
  **Flag matures on a parked car → atom on the visit → bay booked in the same tick →
  serviced to `done`.** That whole chain did not exist before 0019.
* **`b696f1b8`** — flag due 02:24. Sweep appended the atom at **02:34, the next tick**,
  onto an `E_tech_hold_fault` visit whose `fault_repair` reached `done`.
  **⚠️ Its `interior_deep_clean` was still `pending` when the run ended.** The atom was
  placed and held the car; it was **not cleaned**. Ten sim-minutes to acquire the work,
  against 15 sim-hours of nothing in run A — but a placed atom is not a finished one and
  is not reported as one.

### (iii) One raise, one firing — but a residual that is 0018's, not 0019's

No flag produced a second **recall**: 0 dispatches of any flagged vehicle occurred after
its flag came due, so the re-trigger the judgement call was written to close did not
happen.

`37aee690` did have its cleaning atom **emitted onto two visits** — one reached `done`
at 20:04, and a second still-open visit carries it as `pending`. That is a re-emission
of work inside the depot, **not** a re-recall, and its cause is upstream of 0019:
`twin.ottoq_sim_generate_service_manifest` builds `visit_key` from
`vehicles.last_state_change`, which the `BEFORE UPDATE` trigger clobbers to the **real**
clock. Every visit key in this run for these three cars ends `:20260808154131` — the
real wall-clock second the run started. Visit keys are therefore not monotonic in sim
time, so 0018's "the visit this flag was consumed by has closed" test cannot be trusted.
**Named, not fixed here.** Fixing it means changing the manifest's time base, which is a
migration of its own.

### The success criterion could not be evaluated — and that is the honest result

The criterion was: *flagged dispatches turn back EARLY against `planned_return_at`.*

**There were 0 `rider_flag_cleaning` recall dispatches in this run.** Both mid-deployment
flags matured while their car was **already back in the depot** (both came home at 18:04
on `prime_inbound`), so the recall rung never had to fire and the in-depot path took
both. The denominator is zero. **The criterion is not evaluated, and a zero-denominator
result is not a pass.**

For contrast, and with the denominator stated, returns against `planned_return_at` in
this run, teardown-stamped rows excluded (`actual_return_at < 2026-08-10`, which removes
rows carrying the real wall clock written by `ottoq_sim_stop_and_reset`):

| trigger | n | median min vs plan | returned early |
|---|---|---|---|
| `low_soc_reserve` | 103 | +479.8 | 0 |
| `prime_inbound` | 27 | +296.3 | 0 |
| `sensor_soil` | 21 | +58.9 | 4 |
| `wash_cadence` | 16 | +41.9 | 6 |
| `overnight_prestage` | 7 | +90.9 | 0 |
| `comms_stale` | 2 | +255.7 | 0 |
| `critical_reserve` | 1 | +479.8 | 0 |

⚠️ **The briefing's contrast figure does not reproduce here.** It reported
`prime_inbound` returning a median 14 min *early*; in this run it is 296 min *late*, 0
early. The likely reason is structural rather than behavioural: `prime_inbound`
dispatches are created during run priming with `dispatched_at` **before**
`ottoq_start_demo_run` rebases `sim_clock_start` (11:19 and 12:22 against a 17:34 start),
so their generated `planned_return_at` is anchored in a clock the run then jumped past.
Their lateness is an artifact of the rebase. `wash_cadence` and `sensor_soil` still
discriminate — 6 of 16 and 4 of 21 return early — so the column itself is working.

---

## PROTECT, re-measured against this run

* **0 double-booked stall-pairs** over 357 bookings in the run — my own pairwise
  `during && during` on run + stall across `held`/`active`/`done`/`interrupted`, **not**
  the exclusion constraint.
* **ALWAYS HOLD, live after the run: 5 of 91 seated vehicles have no booking covering
  the seat, 4 of them with no booking anywhere in the run.** Preserved in
  `public.p0019b_alwayshold`.
  **The four are the same four vehicle ids as run A** — `4cd2b777`, `9926e267`,
  `c433a36d`, `c98ef465` — across two runs with different seeds and with 0019 applied.
  **0 of the 5 are rider-flagged.** That reproduces the diagnosis independently:
  `twin.ottoq_sim_seed_fleet` seats these cars onto stalls at run start and writes no
  `ottoq_stall_bookings` row, so they never enter the booking loop at all. It is neither
  0018's nor 0019's, and the ratio did not worsen (5/91 here, 7/82 in run A).

## What this run does not show

* No flag-linked **recall** dispatch occurred, so nothing here demonstrates a flagged
  car turning for the depot mid-deployment and arriving early against its plan. Getting
  that case needs a draw whose flags mature **after** departure and **before** the car's
  natural return — which requires fixing the anchoring defect below, not another run.
* `rider_flag_due_at` is still computed by `ottoq_run_boot_draw` from the **pre-rebase**
  `sim_clock_start`, so one of the three flags in this seed was already due before tick
  0. That is a real defect, first recorded by the previous session, still unfixed, and
  out of 0019's scope.
* One of the two in-depot flags was not cleaned before the run ended.
