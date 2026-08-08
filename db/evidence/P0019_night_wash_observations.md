# P0019 — first observed execution of the 0018 wash paths

Instance probe before any run: 10x `count(*) from generate_series(1,1000000)` in one
transaction -> min 190.0 ms / median 190.5 ms / max 192.6 ms (spread 2.6 ms). Healthy;
no multi-second outliers, so timings below are not contaminated.

## How night was crossed (this is the part that never worked before)

`ottoq_start_demo_run` forces `ottoq_set_playback(run,'live',speed)`, and live playback
advances the sim clock by REAL elapsed x speed_x with speed_x hard-clamped to 3.0. One
real hour therefore buys three sim hours, so a demo run physically could not reach a
night window. That — not the wash gate — is why every prior run stayed inside 09:00-19:00.

Fix used: after starting, switch the run back to `fixed` playback
(`ottoq_set_playback(run,'fixed',5)`). In fixed mode
`ottoq_sim_advance_tick_world` advances `tick_interval_seconds * time_scale / 60`
= 30 * 60 / 60 = **30 sim-minutes per tick**, and the metronome paces ticks at
`6.0/speed_x` seconds. A full 24-sim-hour day = 48 ticks.

Start time is seed-derived: `ottoq_start_demo_run` sets the start minute-of-day to
`abs(hashtext(seed::text)) % 1440`. Seeds were chosen so the run *starts* in the evening:

  seed 6666   -> offset 1054 -> start 17:34
  seed 131313 -> offset 1138 -> start 18:58

Night in the gate is **America/Chicago local** hour >= 20 or < 6 (see below), i.e.
01:00-11:00 UTC on the sim clock.

## Time-base defect in the night gate (real, currently dormant)

`twin.ottoq_sim_generate_service_manifest`:

    v_hour    := EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))::int;
    v_sim_day := (v_clock::date - DATE '2020-01-01');

The night test is Chicago-local, the rotation day is the **UTC** date. For
America/Chicago the whole night window (01:00-11:00 UTC) falls inside one UTC date, so
the rotation day is well defined by luck, not by construction. At a depot whose local
offset is near zero the night would straddle midnight UTC and a single night would be
split across two rotation groups. Not a blocker for this depot; it is a latent seam.

## Rider-flag due time is anchored to the PRE-REBASE start

`ottoq_run_boot_draw` computes `rider_flag_due_at = sim_clock_start + rand*window_h`,
but it runs inside `ottoq_sim_run_scenario`, i.e. BEFORE `ottoq_start_demo_run` rebases
`sim_clock_start` to the seed-derived time of day. Run A started at 17:34 yet produced a
flag due at 13:05 — already in the past at tick 0. The 14-hour daytime flag window is
therefore not aligned with the run's actual window.

## THE RUNS

| | run id | seed | seed source | sim window (UTC) | crossed night? | ticks | real min |
|---|---|---|---|---|---|---|---|
| A | 92760504-92f5-4b04-9a68-d4f73237e7a4 | 6666 | explicit | 08-08 17:34 -> 08-09 17:34 (full 24 h) | YES, whole window | 48 | 3.8 |
| B | 499b2baa-eb0f-48b3-a752-2e80eae5f216 | 131313 | explicit | 08-08 18:58 -> 08-09 11:28 (16.5 h) | YES, whole window | 33 | ~22 |
| C | 85135f9d-447d-4f4b-82ad-1f88369cebbe | 3185052694047452824 | **none passed** | 08-08 20:41 -> 08-09 20:41 (full 24 h) | YES, whole window | 48 | ~13 |

Night in the gate = 01:00-11:00 UTC (20:00-06:00 America/Chicago). All three runs
traverse it end to end. Verified against the clock, not assumed.

Run B was stopped at 11:28 UTC once it had cleared the night window; A and C reached
their own 24-hour `sim_clock_end` and completed on their own.

## (a) A rider flag produces a real mid-deployment recall — YES

| run | flags drawn (of 116) | produced a recall | got a wash bay | never fired |
|---|---|---|---|---|
| A | 3 | 2 | 2 | 1 |
| B | 7 | 7 | 7 | 0 |
| C | 8 | 7 | - | 1 |

Worked example, run A, vehicle 37aee690: dispatched 19:34, scheduled return 20:34,
`returning_started_at` 20:04 — it turned for the depot **30 sim-min (one tick) into a
60-min deployment**, `return_trigger='rider_flag_cleaning'`, and was served in a wash
bay for 29 min. Flag row reached `status='served'`.

**Precise negative:** in runs A and C one flag each never fired. Run A's vehicle
b696f1b8 arrived at 02:04, its flag came due at 02:24, and it then sat
`staged_for_departure` in the depot until the run ended 15 sim-hours later. The flag is
only actioned on the deployment path (`ottoq_evaluate_return_need`) or at manifest
generation if already due on arrival. **A flag that comes due while the vehicle is
already inside the depot is never picked up.** That is a real gap, not a timing artefact.

Also noted: the flag does not prevent a flagged vehicle being dispatched — it recalls it
a tick later. Both run-A recalls follow that pattern.

## (b) The boot draw persists wash_group — YES, but only for the run's own depot

BEFORE (old fixed-salt values, all 220 vehicles): group 0=73, 1=72, 2=71, null=4.
AFTER run A's boot draw: 116 vehicles carry `condition_drawn_run` = run A and a fresh
group (40/39/37). **The other 100 vehicles were not touched** — `ottoq_run_boot_draw`
filters `home_depot_id = v_run.depot_id`, so depot 2's fleet keeps stale values
indefinitely. Harmless for a single-depot run; stated because "216 redrawn" would be wrong.

Of the 116 that were redrawn, 73 changed group and 43 did not — 37%, i.e. chance.

## (c) The night gate consumes the new wash_group — YES, exactly

Visits classified by (Chicago-local night?) x (wash_group = UTC sim_day % 3):

| | run A | run B | run C |
|---|---|---|---|
| night + on-rotation | **15 visits / 15 washed** | 6 / 6 | 11 / 11 |
| night + off-rotation | 28 / 0 | 27 / 0 | 24 / 0 |
| day + on-rotation | 39 / 0 | 19 / 1 | 44 / 0 |
| day + off-rotation | 78 / 0 | 53 / 0 | 80 / 0 |

Every on-rotation night visit washed; nothing else did, except two day washes across runs
B and C, which are the gate's own `soil >= 0.75` / `cycles >= 9` override clauses firing.
The gate is a total, exact function of those two inputs.

## (d) Two seeds produce visibly different wash cohorts — YES

Over the same 116 vehicles, comparing the group each run assigned:

    A vs B   39/116 agree (33.6%)
    A vs C   38/116 agree (32.8%)
    B vs C   41/116 agree (35.3%)
    all three agree  15/116

Chance agreement for three independent thirds is 38.7 and 12.9. The draws are
independent. Group-0 cohort: A=40, B=36, overlap only 13 vehicles.

## (e) Behaviour under contention — OBSERVED for the first time

3 wash bays at the depot. Bay-minutes booked against the 3x1440 = 4320 available per day:

| run | wash-bay bookings | bay-min | % of the 3-bay day | of which rider-flag | rider-flag % |
|---|---|---|---|---|---|
| A (24 h) | 46 | 654.9 | 15.2% | 49.0 | **1.13%** |
| B (16.5 h) | 33 | 474.5 | 11.0% | 190.9 | **4.42%** |

0018's A5 guard projected rider flags at **1.35%** of wash-bay minutes. Run A lands on it;
**run B is 3.3x higher**. A5 assumed one booking of 20 or 9 minutes per flag; the observed
pattern is more flags than expected (7 vs 3.5) and sometimes several bookings per flagged
vehicle (one had 3). The projection is the right order of magnitude but it is **not a
bound**, and should not be quoted as one. It stays far below A5's own 25% abort threshold,
so the guard's conclusion is unaffected.

## (f) The flag is non-deferrable under contention — HOLDS

Run B is the contention case: 7 flags competing with the nightly rotation for the same
3 bays. All 7 obtained a wash-bay booking — 5 `done`, 2 `held` at the moment of capture.
None was refused, dropped, or deferred. `held` is a queue position, not a refusal.

## Bay binding, discriminated on new_source (never on source='return_signal_prearrival')

    bay_reservation_activated         3 activations, 3 seated_on_reserved   (bound inside the real forecast window)
    bay_reservation_activated_early  15 activations, 15 seated_on_reserved  (vehicle-first override)

Reported separately, as required — `inside_window` is true by construction on the early path.

## PROTECT — re-measured, all held

* **0 double-booked pairs** on my own pairwise `during && during` scan (not the exclusion
  constraint), over the `held/active/done/interrupted` state set, measured both live
  (63 live bookings) and after teardown.
* **0 orphaned FKs across 225 foreign keys**, the key list generated from `pg_constraint`
  and executed per constraint. 0 unevaluable.
* **0010 geometry:** 0 overlapping pairs, **0 not_assessed**, 0 stalls buried in a
  structure, 0 outside the fence, parcel correct, and both depots at exactly
  115 staging / 30 l2 / 10 dcfc / 3 wash_bay / 2 service_bay = 160.
* **0008 laundering: 0** on the directional test. Note the trap: plain value-equality
  returns **15** pairs, every one of them a 0.000 = 0.000 match on an already-clean
  vehicle. `still_copied` with `soil_index > 0` is **0**.
* **0009:** `planned_return_at` is `attgenerated='s'`, an UPDATE raises **428C9** (probed
  against a zero-row predicate, so nothing was written), and 0 of 421 dispatch rows have a
  NULL plan. No fault_repair over-credit: 1 credit against 21 real fault_repair atoms.
* **cron 10/11/12 ON, 13 OFF.** Never touched.
* **drift CLEAN** — 0 applied-without-a-file, 0 name mismatches, routine counts match the
  baseline exactly (public 339, ottoq 54, twin 71). 0017 still shows in Section B2 as
  written-not-applied, which is its expected state.
* DB **497 MB -> 506 MB**, +9.3 MB net across three full runs.
* Instance probe: pre-run 190.0 / 190.5 / 192.6 ms; mid-run 193.4 / 201.6 / 298.6 ms.
  No multi-second outliers — timings are not contaminated.

## One thing I could NOT certify: seat consistency

My own scan of `vehicles.current_stall_id` against `stalls.current_vehicle_id` finds a
small standing disagreement in every run, measured live with a real denominator:

    run A  85 seated:  3 stall-disagrees, 7 seated-without-booking
    run B  81 seated:  2 stall-disagrees, 6 seated-without-booking
    run C  82 seated:  3 stall-disagrees, 5 seated-without-booking

The `stall_disagrees` rows are staging stalls whose `current_vehicle_id` points at a
different vehicle than the one claiming the stall. They persisted across 9 ticks, so they
are not mid-tick transients. **This is NOT established as a regression** — I could find no
canonical "ALWAYS HOLD" check in `db/checks/` or the catalogue to re-measure against, and
the rate is the same in all three runs. It is reported as an open question, not as a pass
and not as a failure.

## A non-finding, recorded so nobody chases it

`ottoq_sim_stop_and_reset` appears to return a truncated seed
(3185052694047452700 vs 3185052694047452824). That is JSON number precision in the
**client**, not the database — `random_seed::text` and the boot manifest both read back
the exact 19-digit value.
