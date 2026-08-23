# Seed reproducibility — diagnosis

**Question put by the founder:** should a pinned seed also pin the world, so that holding
every input constant between two runs holds every variable constant, and moving one input
(drop five chargers) is a controlled experiment?

**Status: DIAGNOSIS ONLY. Nothing has been changed.** This document names the causes, the
evidence for each, and what a fix would cost. The fix is not authorized yet.

**Scope note up front:** everything here is about the **certification harness**, not about
production orchestration. No depot behaviour is affected by any of it.

---

## Summary

Two independent causes, both single lines, both inside `public.ottoq_cert_arm_start`.

| # | Cause | Effect | Evidence |
|---|---|---|---|
| 1 | The world seed mixes in the **A/B group UUID**, not just the run seed | Every re-certification gets a different starting fleet | **Measured exactly** |
| 2 | The sim start date is **today's real date**; day-lifespan variability is salted by day number | Weather, wind, solar, grid and vehicle ETAs change every calendar day | **Measured** |

Cause 1 explains the entire #20-vs-#22 discrepancy. Cause 2 was invisible in that comparison
because both runs happened on the same calendar day; it would have bitten the first time a
re-cert ran after midnight.

---

## A correction to an earlier claim of mine

I previously reported that the per-vehicle condition draw was clock-free and therefore ruled
out. That statement was about `ottoq_run_boot_draw` — **which the certification harness never
calls.** Both cert runs carry no `boot_draw` key in their payload at all:

```
payload keys, runs 677bca9c / 288d24fc / 914214a4 : inbound_forecast, tick_minutes_actual
```

The reassurance was accurate about that function and irrelevant to this path. The fleet's
starting state in a cert run is set directly by `ottoq_cert_arm_start`, which is where both
real causes live. Recorded rather than quietly dropped.

---

## Cause 1 — the A/B group UUID is mixed into the world seed

```sql
v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'wave', 17));
```

Every fact about the starting fleet is drawn from `v_wseed`: each vehicle's state of charge,
which 85 of 100 vehicles are deployed, and when each returns.

```sql
UPDATE vehicles SET current_soc = 90 + ottoq_sim_seeded_random(v_wseed,'soc:'||id::text)*8 ...
ORDER BY ottoq_sim_seeded_random(v_wseed, 'pick:'||v.id::text) LIMIT v_deploy_n
```

Because a fresh `ab_group` is allocated for each re-certification, **each re-cert draws a
different world from the same seed.** Both arms of one pair share the group, which is exactly
why determinism passes within a pair and fails across sessions.

### Evidence — prediction, not correlation

`twin.ottoq_sim_seeded_random` is declared **IMMUTABLE** (`provolatile = 'i'`), so the formula
can be evaluated independently and checked against what was recorded at arm time.

| Run | ab_group | `v_wseed` | Initial wave | SoC predicted == recorded | Deployed set predicted == actual |
|---|---|---|---|---|---|
| #20 arm A `677bca9c` | `…42425f` | 7681532243817775720 | 85 | **85 / 85, max error 0** | **85 / 85** |
| #22 arm A `288d24fc` | `…424261` | 6347474725636378542 | 85 | **85 / 85, max error 0** | **85 / 85** |
| #22 arm B `914214a4` | `…424261` | 6347474725636378542 | 85 | **85 / 85, max error 0** | — |

Two things this settles:

- **#22 arm A and arm B share an identical `v_wseed`.** The within-pair certification result is
  now mechanically explained, not merely observed.
- **#20's `v_wseed` differs.** Overlap between the two deployed sets is **70 of 85** — so 15
  vehicles deployed in #20 and not #22, and 15 the other way: **30 vehicles in a different
  state**, which is precisely the 30/100 originally measured from the tick-1 frames. The
  arithmetic closes.

---

## Cause 2 — the sim start date is today's date

```sql
v_sim0 := date_trunc('day', v_now) + interval '22 hours';
```

Migration 0065 introduced this to pin the *time of day* (the 22:00 return wave), because the
arming minute was swinging load by ~45%. It fixed the hour and left the **date** floating.

That matters because day- and block-lifespan variability is salted by a day number derived from
the sim clock's calendar date:

```sql
-- ottoq_twin_deal
v_bucket := ... WHEN 'day' THEN 'day:' || p_sim_day
                WHEN 'block' THEN 'block:' || p_sim_day || ':' || hour_block
v_salt   := p_var_key || '|' || p_scope_instance || '|' || v_bucket;
v_val    := ottoq_sample_calibrated(p_var_key, p_segment, v_seed, v_salt);
```

and the callers pass `(p_sim_clock_now::date - DATE '2020-01-01')` — in
`ottoq_sim_advance_weather_and_solar` (cloud cover, wind), `ottoq_sim_advance_grid` (grid plus
heat/cold climate stress) and `ottoq_sim_advance_deployed_telemetry` (per-dispatch ETA cards).

### Evidence — measured, same seed, day number the only difference

```
seed 424242, salt 'wind_speed_kmh|global|day:<n>'
  2026-08-22  day 2425  ->  5.544 km/h
  2026-08-23  day 2426  ->  9.252 km/h
  2026-08-24  day 2427  ->  7.416 km/h
```

So a re-cert run tomorrow gets different weather, different solar, a different grid and
different vehicle ETAs — from an identical seed.

---

## What is NOT broken

Worth stating, because it bounds the fix:

- **Only one function in the catalog mixes `ab_group` into a hash.** 28 functions use
  `hashtextextended`; `ottoq_cert_arm_start` is the only one that touches `ab_group`.
- **The twin's variability layer is correctly seeded.** `ottoq_twin_deal` reads
  `ottoq_sim_runs.random_seed` — the real run seed. The day-number leak is upstream of it, in
  the harness's choice of date.
- **The whole downstream engine is already reproducible.** #22's two arms ran two minutes apart
  and produced byte-identical 20-tick streams across weather, solar, grid, telemetry, wear and
  charge sessions. If any of those 28 functions carried a hidden clock dependency, that pair
  would have diverged. It did not.
- **The charger-fault lever is already clean.** `p_fault_chargers` selects by
  `ORDER BY stall_type, stall_code` — deterministic, and it does not perturb `v_wseed`. Dropping
  five chargers already leaves the fleet untouched, which is the controlled-experiment property
  the slider model needs.

---

## Proposed fix — not authorized, costed only

Both changes are one line, in one harness-only function, using the same self-verifying in-place
migration mechanism as 0054–0069 (pinned pre-image md5, anchor count, post-conditions).

1. **Drop the group from the world seed.**
   `v_wseed := abs(hashtextextended(p_seed::text || 'wave', 17));`
   Within a pair, nothing changes — both arms already shared the group. Across pairs, the same
   seed now yields the same world. A/B pairing and scoring still use `ab_group`; only world
   generation stops using it. This makes common-random-numbers pairing stronger, not weaker.

2. **Pin the date, keep it steerable.** Give the harness a start date with a fixed default
   rather than deriving it from `now()`, preserving 0065's pinned 22:00 hour. The default makes
   runs reproducible; passing a different date becomes a deliberate lever — the seam the future
   controls interface would attach to.

**Consequence the founder should weigh:** after this, every re-cert at seed 424242 is the *same*
test. That is what makes regression detection trustworthy, and it also means a single run stops
being evidence of robustness. Robustness comes from sweeping the seed deliberately — same
slider settings across N seeds, compared as a distribution. Pinning is what makes that sweep
meaningful; it does not perform it.

**What this does not cover.** This fixes the certification harness. The controls-interface
vision — sliders, presets, replay against a benchmark — would run through the product's own
run-start path, not `ottoq_cert_arm_start`. That path needs the same discipline applied
separately, and is a larger piece of work that should not be bundled here.
