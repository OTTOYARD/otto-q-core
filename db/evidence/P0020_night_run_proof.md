# 0020 — proving 0019 on a night run

0019 was applied but **never run**. Its own migration log says so: *"no simulation run has
been executed against 0019, so nothing here shows a flagged car being declined a dispatch,
a parked flag acquiring its atom, or a flag-linked dispatch returning early."* This document
is that run.

**No migration was written or applied by this session.** 0019 is live at ledger version
`20260808153457`; everything below is measurement.

**Headline, stated before the detail so it cannot be buried:**

* **The dispatch churn is gone.** 0 of 33 flag-linked dispatches went out while the flag was
  still pending, against **9 of 10** before.
* **The in-depot path works.** 6 sweeps across the two runs; a flag maturing on a parked car
  now acquires its atom within ≤2 ticks instead of stranding for 15 sim-hours.
* **No flag fired twice.** 0 double-recalls, 0 atoms on multiple visits.
* **The literal success criterion is NOT met — 2 of 10 recalls turned back early against
  `planned_return_at`.** But the criterion is confounded, and the reason is arithmetic, not
  behavioural: see §4. On the fair subset it is 2 of 2, and recall *latency* is ≤1 tick
  every time.
* **A NEW defect this run surfaced: 2 of 16 flags were consumed and the work vanished.**
  Both exterior. This is a silent failure and it is worse than the one 0018 had. See §6.

---

## 1. Is 0019 actually applied?

**Yes.** Ledger row `20260808153457` / `rider_flag_holds_the_vehicle`.

The ledger's `md5(statements[1])` is `7c2ce44a…`; the committed file today reads
`29934425…`. **The two differ, and that is not drift.** `7c2ce44a` is byte-exact the file at
commit `c02de39` — the bytes that were streamed. Commit `4c7d458` then changed exactly one
line, `-- migration-version: PENDING` → `-- migration-version: 20260808153457`. A diff of
the two commits restricted to non-comment lines is **empty**. The safety argument holds.

All four replaced routines carry 0019's post-image md5, read back live from `pg_proc`:
`ottoq.ottoq_plan_dispatch_tick` `59907a11`, `twin.ottoq_sim_dispatch_vehicle` `1fdcb54c`,
`twin.ottoq_sim_auto_dispatch_tick` `7a8f8993`, `public.ottoq_evaluate_return_need`
`5693e310`. Both new routines exist.

`public.ottoq_rider_flag_due` is genuinely **total**: its body ANDs the lookup with
`p_vehicle_id IS NOT NULL AND p_sim_run_id IS NOT NULL AND p_clock IS NOT NULL`, so a NULL
argument yields `false`, never NULL, and it cannot raise.

---

## 2. THE RUN RECIPE — and the anchoring defect it had to route around

The 0019 evidence run reached night but produced a **zero denominator**: 0 flag-linked recall
dispatches, because every flag matured while its car was already parked. Its own diagnosis
named the cause, and this session confirmed it in source:

* `ottoq_run_boot_draw` anchors `raised_at_sim_clock` to `sim_clock_start` **as it stands at
  boot**.
* `ottoq_start_demo_run` **rebases** `sim_clock_start` to a random minute-of-day *after* the
  draw, and forces `live` playback, which `ottoq_set_playback` clamps to 3× — which is why a
  demo run physically cannot reach night.
* `ottoq_demo_metronome` skips only `run_by IN ('production_live','cert_harness')`.

So calling **`ottoq_sim_run_scenario('normal_day', <seed>, 'operator_demo')` directly** gives
a correctly-anchored, fixed-playback run that the metronome still drives. **No code was
changed to achieve this** — it is a different entry point into existing code, and it is the
reason this session could produce mid-deployment recalls at all.

Both runs: `normal_day`, depot `1111…`, 116 autonomous vehicles, 160 stalls
(115 staging / 30 l2 / 10 dcfc / **3 wash_bay** / 2 service_bay), fixed playback,
`tick_interval_seconds 30 × time_scale 60 = 30 sim-min per tick`, 48 ticks = 24 sim-hours,
**08:00 → 08:00 America/Chicago**.

**Night verified, not assumed.** 20:00–06:00 is ticks 24–44. Both runs ran all 48 ticks and
reached `status='completed'` on their own at `sim_clock_end`. **Neither run was ever
stopped**, so **no `actual_return_at` in either run carries a teardown wall-clock stamp** —
a stronger exclusion than filtering them out, and the reason no teardown filter appears below.

Instance probed (`generate_series(1,1000000)` ×10 **inside a plpgsql loop**, not a CTE):
before 204/195/192/192/193/193/193/192/192/191 ms, after 264/194/192/192/192/193/192/192/192/193 ms.
Healthy at both ends.

| run | seed | flag rate | flags | dispatches |
|---|---|---|---|---|
| **R1** `a30661fd` | 20260820 | **3.0 %/day — shipped default, untouched** | 2 | 199 |
| **R2** `b857fd29` | 20260821 | 12.0 %/day — **raised for denominator, then restored** | 16 | 201 |

**Declared plainly:** R2's `rider_flag_daily_pct` was raised at depot scope 3.0 → 12.0
*before* run creation (the draw happens once, at boot) and **restored to 3.0 immediately
after**, verified back at 3.0 in the same statement. R2 is a statistical-power instrument,
not a claim about how often riders complain. R1 used shipped settings.

**Clock domains.** Every timestamp quoted below (`dispatched_at`, `planned_return_at`,
`returning_started_at`, `raised_at_sim_clock`, booking `during`) is in the **sim domain**,
rendered `America/Chicago`. The only real-clock values touched are `started_at`/`ended_at`
on the run row and the probe timings, and neither enters any arithmetic here.

---

## 3. Dispatch churn — the thing 0019 was built to kill

Baseline (0018-era): **9 of 10** flag-linked dispatches went out with the flag **already due**.

**The naive metric lies, and it lied to me first.** `dispatched_at >= raised_at_sim_clock`
flags 3 of 5 in R1 and 9 of 28 in R2 — but a flag row keeps its `raised_at` forever, so that
test also catches every *later, legitimate* dispatch of a car whose cleaning was already
finished. Checked individually, all of them had the cleaning `done` before the dispatch.

The correct test is: was the flag still **pending** (unconsumed) *and* due at that instant?

| run | flag-linked dispatches | naive "after raise" | **dispatched while flag still PENDING** |
|---|---|---|---|
| R1 | 5 | 3 | **0** |
| R2 | 28 | 9 | **0** |
| **total** | **33** | 12 | **0** |

**0 of 33, against 9 of 10 before.** `twin.dispatch_refused_rider_flag` fired **0 times** in
both runs — the designed outcome, because the planner cursor declines the candidate before
the door is ever reached; the door is a backstop and should stay silent.

Corroborating: **6 in-depot sweeps** across the two runs are cars that were parked with a due
flag at a moment the dispatcher was running — i.e. exactly the cars the gate held back.

---

## 4. 🔴 THE ASSERTION — and why it cannot be answered as posed

**Literally: 2 of 10 R2 recalls turned back EARLY against `planned_return_at`. Median −138
min (late). That FAILS the criterion as written.** Said plainly, not dressed up.

But the criterion is confounded, and the confound is arithmetic:

> **8 of the 10 recalls had their flag mature AFTER the vehicle's `planned_return_at` had
> already passed** — by +1 to +409 minutes. For those eight, turning back "early against
> plan" is **impossible**: the deadline was gone before the flag existed.

The cause is structural and applies to every trigger, not just flags. In R1: median
`planned_duration_min` = **65 min**, median actual minutes deployed before turning back =
**275 min**. `planned_return_at = dispatched_at + planned_duration_min` is a *drawn nominal
plan*, not a commitment the system schedules against; the fleet routinely runs ~4× past it.
That is why the 0018-era battery shows **every** trigger late except `prime_inbound`.

**The fair subset — flags that matured while the plan was still live — is 2 of 2 early:**

| vehicle | plan | flag due | planned return | turned back | early vs plan | latency |
|---|---|---|---|---|---|---|
| `229f655b` | 90 min | 21:02 | 22:29 | 21:30 | **+60 min early** | 28 min |
| `a1111111` | 56 min | 08:15 | 08:45 | 08:30 | **+16 min early** | 15 min |

⚠️ **Adversarial, and it costs one of the two:** at 30 sim-min per tick,
`returning_started_at` is quantised to tick boundaries. `+16 min` is **inside one tick** and
cannot be distinguished from quantisation — it must not be leaned on. `+60 min` is **two
ticks** and survives. So: **1 of 2 fair-test earlies is robust to tick granularity, 1 is
not.** n=2 is a thin denominator and is reported as thin.

**The measure that is not confounded is recall latency — flag due → `returning_started_at`:**

| | R2, n=10 |
|---|---|
| median | **6 min** |
| max | **28 min** |
| over one tick (>30 min) | **0** |

**Every recall fired within a single tick of the flag maturing.** That is the honest
statement of responsiveness, and it is the number I would put in front of anyone.

**Recommendation:** retire "early vs `planned_return_at`" as the acceptance test for recalls.
It measures the gap between a nominal plan and a fleet that ignores it. Replace it with
recall latency, which is what the claim "OTTO-Q takes the car off the road" actually means.

---

## 5. The in-depot path, and the double-fire

**In-depot sweeps: 1 in R1, 5 in R2.**

R1's is the cleanest single demonstration in either run. Vehicle `5fe5fe42` was
`staged_for_departure` — parked, and next in line to be sent out — at 21:00, with its flag
due 21:04. In the 0018 era this exact situation stranded a car for 15 sim-hours.

* tick 27 (21:30) — flag due, still `pending`, sweep has not run
* tick 28 (22:00) — **sweep fires**: flag `pending`→`recalled`, vehicle
  `staged_for_departure`→`staged_awaiting_service`, `interior_deep_clean` appended to its
  open visit as `must_do: true, deferrable: false, raised_in_depot: true`
* the atom reached `done` at 01:20, and the car was not dispatched until 04:00 — **after**
  the clean

⚠️ **Worst-case in-depot latency is 2 ticks, not 1**, and that is structural: the sweep sits
inside `twin.ottoq_sim_auto_dispatch_tick`, which the metronome calls only on **odd** ticks
(`v_run.ticks % 2 = 1`). Not a defect, but it should be stated rather than rounded to "next
tick".

**Double-fire: closed.** R1 and R2 both show **0** vehicles with more than one
`rider_flag_cleaning` dispatch and **0** with the flag atom on more than one visit. The 0018
residual (one car carrying the atom on two visits) did not recur.

---

## 6. 🔴 NEW DEFECT — 2 of 16 flags were consumed and the work vanished

This did not exist in the 0018 measurement and is **not** a regression of an old defect — it
is a new one, surfaced only because R2 drew enough exterior flags to hit it.

| flag kind | flags | atom `done` | atom placed, unfinished | **no atom at all** |
|---|---|---|---|---|
| interior | 10 | 8 | 2 | **0** |
| exterior | 6 | 3 | 1 | **2** |
| **total** | **16** | **11** | **3** | **2** |

The two are `f0077a3a` and `99ddf4ff`, both **exterior**. Both:

* were recalled (a real `rider_flag_cleaning` dispatch fired),
* had their flag advanced to `status='recalled'` and stamped with a `recalled_visit_key`,
* **carry no rider-flagged atom on any visit in the run**,
* and **their `recalled_visit_key` matches no row in `ottoq_visit_needs`** — 2 of 16 flags
  point at a visit that does not exist; the other 14 point at a real one,
* ended the run `staged_for_departure` — free to redeploy, dirty.

**Why this matters more than the defect it replaced.** 0018's failure mode was 2 of 18 flags
stuck `pending` — visibly unfired. 0019's is 2 of 16 marked `recalled` — the ledger says
handled and nothing was done. **It is silent.** It also directly contradicts the premise the
0019 judgement call rests on: *"at the instant the flag is consumed it has become a must_do
atom on an open visit."* In these two cases it did not, so ownership **did** lapse.

**Not diagnosed to root cause here, deliberately.** The observable is solid; the mechanism is
not yet proven. The strong lead is the visit-key time base the previous session already
named: `twin.ottoq_sim_generate_service_manifest` builds `visit_key` from
`vehicles.last_state_change`, which a `BEFORE UPDATE` trigger clobbers to the **real** clock,
while these two `recalled_visit_key` values (`…20260808200000`, `…20260809010000`) decode as
**sim** times matching the flag's own maturity. Two clock domains in one key space would
explain a key that points at nothing. That needs its own migration and its own proof.

---

## 7. PROTECT — re-measured, denominators stated

| line | R1 | R2 | verdict |
|---|---|---|---|
| double-booked stall-pairs (own pairwise `during && during`, **not** the constraint) | **0** / 1,199 bookings | **0** / 1,143 | PASS |
| orphaned FKs (key list generated from `pg_constraint`) | **225 checked, 0 orphans, 0 errored** | PASS |
| 0010 geometry (heading-aware oriented footprint; `relative_x/y` read as **FEET**, no 1.5699 conversion) | **320 assessed, 0 not_assessed, 0 overlapping pairs** | PASS |
| 0010 inventory | **115/30/10/3/2 = 160 at BOTH depots** | PASS |
| 0008 laundering (directional `copied_after_wear`) | 421 pairs, 2 naive value-equality, **0 directional** — both naive hits are 0.000 = 0.000 | PASS |
| 0009 `planned_return_at` immutable | UPDATE raises **`428C9`** | PASS |
| cron | **10 ON, 11 ON, 12 ON, 13 OFF** — untouched, cron 12 never disabled | PASS |
| drift | 0 unexplained ledger rows, 0 in-repo-not-applied, 0 name mismatches, ledger 638 | PASS |
| **ALWAYS HOLD** | **5 of 65 seated** | **6 of 67 seated** | **STILL BREACHED — unchanged by 0019** |

**Drift footnote, honest:** the only count delta is `ottoq` 54→55 and `public` 339→340, and
those are **exactly** 0019's two new routines, verified *by name*
(`ottoq.ottoq_rider_flag_indepot_sweep`, `public.ottoq_rider_flag_due`). The drift script's
embedded `baseline_counts` still says 54/339 and should be bumped to 55/340 — housekeeping,
fixed in this branch.

**Mapping totality.** Every atom that requires a bay resolves to a stall type that **exists**:
`exterior_wash`→`wash_bay`, `interior_deep_clean`→`wash_bay` (the detail lane folds onto the
wash lane because there are **0 `detail_bay` stalls**), `fault_repair`/`mechanical_pm`/
`sensor_calibration`/`cosmetic_repair`→`service_bay`. Unrecognised names — including `''`
and a deliberately invented one — return NULL, meaning *no bay required*, never a demand for
a stall type that does not exist. All 16 R2 flags resolved to `wash_bay`. Not regressed.

### ALWAYS HOLD: resolved as pre-existing, on stronger evidence than before

The previous session could not call it pre-existing honestly, because no pre-0018 baseline
existed for this exact query. **Two fresh runs on two new seeds, through a different entry
point, settle it:**

The **same four vehicles** — `4cd2b777`, `9926e267`, `c433a36d`, `c98ef465` — appear with
**zero bookings anywhere in the run** in run A, in the prior 0019 run, in R1 **and** in R2.
Four runs, four different seeds, and 0 of them rider-flagged in any run. The remainder are
`emergency_staged` cars holding bookings elsewhere but none on the seat.

That is the signature of `twin.ottoq_sim_seed_fleet`, which seats the fleet onto stalls at
run start and writes no `ottoq_stall_bookings` row. **0019 did not cause it and did not
change it** (5/65 and 6/67 here, 5/91 and 7/82 before — same identities, no worse).
**Verdict: pre-existing, filed, not inherited. Not grounds for revert.**

---

## 8. Adversarial — default REFUTED

* **Is any "early" a tick artifact?** *Partly yes, and it costs one of the two.* `+16 min` is
  inside one 30-min tick and is discarded as indistinguishable from quantisation. `+60 min`
  is two ticks and survives. Stated in §4 rather than hidden.
* **Are teardown rows contaminating the returns?** *No, and not by filtering.* Neither run
  was ever stopped — both completed at `sim_clock_end` — so `ottoq_sim_stop_and_reset` never
  ran and no real-clock `actual_return_at` exists in either run.
* **Did blocking dispatch starve the fleet or deadlock the run?** *No.* R1 (2 flags) 199
  dispatches; R2 (**16** flags, 8× the load) **201** dispatches. Both ran all 48 ticks and
  completed on schedule. Wash bays — the contended resource — used **421 of 4,320 bay-minutes
  (9.8 %)** with peak concurrency touching 3 of 3 exactly once. ALWAYS HOLD ×
  oversubscription would present as a deadlock; there is none, and the bays were not close to
  saturated.
* **Is "0 dispatched while pending" vacuous — did the gate ever have anything to hold?**
  *No, it is not vacuous.* 6 in-depot sweeps are cars that were parked with a due flag while
  the dispatcher ran; under 0018 those are exactly the cars that got sent out and recalled.
* **Does the cert battery prove anything about 0019?** *No, and it must not be read that way.*
  See §9.

---

## 9. PR #13's certification battery, re-run

**First, a correction to the brief: PR #13 is not open. It was merged, as was PR #14 — so
`origin/main` already carries 0019, the battery, and the 0019 evidence doc.**

Re-run in full. **Every recorded answer reproduces exactly**, which is the point: the battery
reads *frozen* `p0019_*` snapshot tables from three **0018-era** runs, so re-running it
verifies the preserved evidence has not drifted. **It does not measure 0019** — nothing in it
touches a run made after 0019 landed.

* the measurement trap: **1** distinct value against the rebased column for **all 10** trigger
  types — confirming `scheduled_return_at − returning_started_at` is 30 by construction
* `rider_flag_cleaning` n=10, median **−16** (16 min late); `prime_inbound` **+14** (early)
* flags across A/B/C: 18 total, **2 stuck `pending`**
* witness: 3+3 `bay_reservation_activated`, 15+14 `…_early` — 18 activations, 17 done
* 0 double-booked pairs; geometry 320/0/0; FK 225/0/0

⚠️ One nuance worth recording: the 0019 evidence doc reports that `prime_inbound`'s "median
14 min early" **did not reproduce** in its own new run. Both statements are true of different
datasets — it reproduces in the frozen A+B snapshot and did not in that session's run, where
`prime_inbound` rows were created before `ottoq_start_demo_run` rebased the clock. In **this**
session's runs that rebase never happened, which removes the artifact at source.

---

## 10. What this run does not show

* Only **2** recalls had a live plan to be early against. n=2, and one of the two is inside
  tick granularity. **The "early" claim is not established** on this evidence and is not
  claimed.
* The exterior drop (§6) is **observed, not root-caused**.
* 3 of 16 flags ended with the atom placed but unfinished. Placed is not cleaned, and is not
  reported as cleaned.
* R2's flag rate is 4× shipped. It proves the *mechanism* under load; it is not a statement
  about real complaint volume.
* The in-depot path never advances the flag to `served` — `served_at_sim_clock` stays NULL
  even when the atom reaches `done` (R1 `5fe5fe42` is the worked example). Ledger cosmetics,
  but it makes "served" an undercount: 6 of 16 in R2 by flag status, 11 of 16 by atom status.
