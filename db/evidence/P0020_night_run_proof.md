# 0020 — proving 0019 on a night run

0019 was applied but **never run**. Its own migration log says so plainly: *"no simulation
run has been executed against 0019, so nothing here shows a flagged car being declined a
dispatch, a parked flag acquiring its atom, or a flag-linked dispatch returning early."*
This document is that run.

**No migration was written or applied by this session.** 0019 is already live at ledger
version `20260808153457`; everything below is measurement.

---

## 0. First, is 0019 actually applied?

**Yes.** Ledger row `20260808153457` / `rider_flag_holds_the_vehicle`.

The ledger's `md5(statements[1])` is `7c2ce44a7272f56168fb4fd92dfe7e7f`. The committed file
today reads `29934425fdb031ca1e94c598f92d05c4` — **the two differ, and that is not drift.**
`7c2ce44a` is byte-exact the file at commit `c02de39`, i.e. the bytes that were streamed;
commit `4c7d458` then changed exactly one line, `-- migration-version: PENDING` →
`-- migration-version: 20260808153457`. A diff of the two commits restricted to
non-comment lines is **empty**. The safety argument (ledger md5 == bytes that ran) holds.

All four replaced routines carry 0019's post-image md5, read back live:

| routine | live md5 | 0019 claimed |
|---|---|---|
| `ottoq.ottoq_plan_dispatch_tick` | `59907a11…` | `59907a11` |
| `twin.ottoq_sim_dispatch_vehicle` | `1fdcb54c…` | `1fdcb54c` |
| `twin.ottoq_sim_auto_dispatch_tick` | `7a8f8993…` | `7a8f8993` |
| `public.ottoq_evaluate_return_need` | `5693e310…` | `5693e310` |

Both new routines exist: `public.ottoq_rider_flag_due`,
`ottoq.ottoq_rider_flag_indepot_sweep`.

---

## 1. THE RUN RECIPE — and the anchoring defect it had to route around

The 0019 evidence run reached night but produced a **zero denominator**: 0 flag-linked
recall dispatches, because all its flags matured while their cars were already parked. Its
own diagnosis named the cause — `ottoq_run_boot_draw` anchors `raised_at_sim_clock` to
`sim_clock_start` **as it stands at boot**, and `ottoq_start_demo_run` then *rebases*
`sim_clock_start` to a random minute-of-day **after** the draw. The flag due-times are
therefore anchored in a clock the run immediately jumps away from.

**This session routed around it rather than living with it.** Reading the source:

* `ottoq_sim_run_scenario()` creates the run, seeds the fleet, calls `ottoq_run_boot_draw`,
  and primes deployment. It does **not** rebase.
* `ottoq_start_demo_run()` is the only thing that rebases — and it also forces `live`
  playback, which `ottoq_set_playback` clamps to 3×, which is why a demo run cannot reach
  night.
* `ottoq_demo_metronome` skips only `run_by IN ('production_live','cert_harness')`.

So calling **`ottoq_sim_run_scenario('normal_day', <seed>, 'operator_demo')` directly**
gives a correctly-anchored, fixed-playback run that the metronome still drives. No code was
changed to achieve this; it is a different entry point into existing code.

Both runs below: `normal_day`, depot `1111…`, 116 autonomous vehicles, 160 stalls
(115 staging / 30 l2 / 10 dcfc / **3 wash_bay** / 2 service_bay), fixed playback,
`tick_interval_seconds 30 × time_scale 60 = 30 sim-min per tick`, 48 ticks = 24 sim-hours,
**08:00 → 08:00 America/Chicago**.

**Night was verified, not assumed.** 20:00–06:00 is ticks 24–44; both runs ran the full 48
and ended at 08:00 the following day, `status='completed'` on their own at `sim_clock_end`
— so **neither run was ever stopped**, and therefore **no `actual_return_at` in either run
carries a teardown wall-clock stamp**. That is a stronger exclusion than filtering them out.

Instance probed before the runs, `generate_series(1,1000000)` ×10 **inside a plpgsql loop**:
204, 195, 192, 192, 193, 193, 193, 192, 192, 191 ms — healthy, no host CPU starvation.

| run | seed | flag rate | flags drawn | note |
|---|---|---|---|---|
| **R1** `a30661fd` | 20260820 | **3.0 %/day (default, untouched)** | 2 | the realistic run |
| **R2** `b857fd29` | 20260821 | 12.0 %/day (**raised for denominator, then restored**) | 16 | the powered run |

**Declared plainly:** R2's `rider_flag_daily_pct` was raised at depot scope from 3.0 to 12.0
*before* the run (the draw happens once, at boot) and **restored to 3.0 immediately after
the run was created** — verified back at 3.0 in the same statement. R2 is a
statistical-power instrument, not a claim about how often riders complain. R1 is the run
that used shipped settings.

---

## 2. Evidence tables (do not drop)

`p0020_prestop_r1_{runrow,dispatches,flags,bookings,visitneeds,vehicles,stalls}`,
`p0020_alwayshold_r1`, `p0020_r2_flags_t0`, and the R2 equivalents.

Occupancy / placement / per-vehicle state were captured **at tick 48, pre-stop**. Ledger and
flag reads are from the same capture. Every number below states its own denominator.
