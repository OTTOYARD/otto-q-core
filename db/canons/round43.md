# Round 43 — the recert round for the forward-prediction work (0313–0319)

**Status: IN FLIGHT.** This file is the "before" half, committed at 2026-09-14 17:29 UTC
(12:29 PM CT), before the first flagship pair fired. The judgement goes below the line once
the pairs land. It is written now because round 43 tests a prediction, and a prediction
recorded after the result is not a prediction.

## Why this round exists

Five migrations applied on 2026-09-14 between 16:35 and 17:18 UTC, and four of them are
classified `forces_recert = TRUE`:

| | applied | forces_recert |
|---|---|---|
| `0313` the predictive recall rung takes eight values and none of them is the vehicle | `20260914163515` | **TRUE** |
| `0314` vehicles get a position and the ETA stops being a constant | `20260914164237` | false |
| `0315` the speed cancelled out of my own ETA | `20260914164649` | false |
| `0316` the ETA function starts answering its own arguments | `20260914165752` | **TRUE** |
| `0317` the twin writes where each asset is, not only how charged | `20260914170416` | **TRUE** |
| `0318` the engine stopped guessing and the label kept saying guess | `20260914170807` | **TRUE** |
| `0319` I seeded a deterministic draw on a random uuid | `20260914171845` | **TRUE** |

The recert floor is therefore **`2026-09-14 17:18:45.095549+00`** — `0319`'s apply stamp —
and every certification column started this round at `consecutive_passes = 0`.

## What 0319 was, because it is the reason this round is not a formality

`ottoq_trip_geometry` chose a vehicle's bearing and trip radius from
`twin.ottoq_sim_seeded_random(seed, salt)` — a pure hash, correctly seeded — with a salt
built from `gen_random_uuid()`. A deterministic draw keyed on a random value is a random
draw wearing a seed's name.

**Four convictions of this class now:** `0137` (the world fingerprint hashed a write
timestamp), `0139` (the end-state fingerprint was not id-blind), `0216`
(`ocpp_sessions.id` defaults to `uuid_generate_v4()` and was both hashed and used as the
sort key), and this one. The rule that would have caught all four, stated as plainly as it
can be: **before measuring a value, read its assignment.**

It is also the case that **none of my own checks could see it.** Positions and ETAs looked
right by every measure I had built — 96–98% of packets positioned across two twin runs, 62
distinct ETAs where there had been one, assertions passing inside four migrations. The
determinism pair found it in a single run. That is the argument for the apparatus in
CLAUDE.md 2.9a, restated by a case rather than by assertion.

## Lane 1 — the grid columns, already landed

Run by hand before the flagship lane, cheapest-first, precisely to establish that the `0319`
fix holds across seeds before spending an hour of wall clock on the expensive columns.

| depot | seed | ticks | scenario | pairs | result |
|---|---|---|---|---|---|
| `aacd0bb0` | 239001 | 6 | grid_smoke | 2 | **green** (`consecutive_passes = 2`) |
| `aacd0bb0` | 424242 | 6 | grid_smoke | 2 | **green** |
| `aacd0bb0` | 171717 | 12 | grid_smoke | 1 (+1 pre-existing) | **green** |

Three columns, three seeds, two horizons, every atom equal. The fix holds outside the single
pair that exposed the defect.

## Lane 2 — the flagship columns, the prediction

Seven columns on depot `11111111`, `sim_start 2026-09-01 02:00:00+00`, two pairs each.

### P1 — every flagship column passes twice and goes green.

The falsifier: **any flagship column that fails means 0313–0319 carry nondeterminism the
grid lane is too small to express.** The grid fixture is 4 vehicles, 10 stalls, 4 chargers;
the flagship is the full depot. A defect that needs concurrency, or needs a vehicle to be
deployed rather than parked, would pass lane 1 and fail here. That is the whole reason lane 2
is run at full size and not skipped.

### P2 — the canons MOVE, and the atoms that move name what the change actually reached.

The engine changed, so the canons must change; a flagship canon that did **not** move would
mean the work never reached the certified path at all. Recorded here so the diff is against
a number written down in advance, not against a memory:

| column | fp | cmd | dec | evt | bkg | nrg | prop | rule | rcl | sdr | endst |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 48t/171717/busy | 9c28854e | 5727d446 | 7a8ac80f | 39b36da3 | a8910602 | dd96089d | f260e51f | c8ff19af | d66783aa | 262c354a | 5a3ec345 |
| 24t/171717/busy | 9c28854e | 050c4606 | 0360adc9 | b2230619 | 947a2316 | 4c5035fe | 0046879e | 9564b998 | fa8ab72c | 957abcfb | dc344d68 |
| 24t/424242/busy | 7a14aa52 | 8f232001 | 35148055 | 8dc37f82 | ea8a12e2 | c79957a5 | aabef458 | 726f6769 | 928262d2 | f2587dbc | 7fb3eca5 |
| 12t/171717/busy | 9c28854e | 1ae7ba68 | cf2f44e2 | e16ad964 | 7146a8e1 | 08f719af | 0046879e | 3e57f511 | 0a4ca4d3 | a2a35e03 | 8b5a0ad4 |
| 12t/314159/busy | b8606125 | 109e340b | 9abdb4af | 9c631343 | 174b8835 | a9c6b693 | a79c1095 | fc69953b | 0e67b89a | a1f79c20 | 660898c9 |
| 12t/424242/busy | 7a14aa52 | 76134009 | 47757095 | 6453c09b | 8bc2877b | 9917f7c3 | 029cad7d | d56e09a3 | f58ee562 | 6fd75365 | 4f1879cf |
| 12t/171717/normal | 9c28854e | 5921ef70 | 37624cdd | ac672423 | ed4a986c | 17c9b12b | 779e5a74 | 5b1d1dfa | e4e41e69 | e0dfbbe8 | d801f3ce |

(First eight hex characters; the full values are in the pre-round matrix.)

**Named in advance, so the diff can refute it:** `endst` should move on every column, because
`ottoq_vehicle_dispatches` is inside `endst.dispatches.vis` and `0314`/`0315`/`0316` changed
what `return_eta_minutes` holds — it was the literal `30` in all 123,665 rows and is now
computed per vehicle. `rcl` should move, because `0313` gave the recall rung a **measured**
burn rate in place of a policy constant. `dec` and `cmd` should follow wherever a changed
recall or a changed ETA changed what the decide path did. `cal` should **not** move: no
calibration prior was refitted.

### The lane-2 schedule, and what b1 already shows

Fourteen pg_cron slots, sized from a measured 12-tick pair rather than from the stale
constants in `scripts/schedule-round.sql` (whose 14-minute floor was set when a 12-tick pair
took 535 s; it takes **125 s** today, post-`0229`). Slots: 5 min at 12 ticks, 8 at 24, 14 at 48.

| | fires UTC | CT | ticks |
|---|---|---|---|
| `r43_b1` 171717 busy | 17:30 | 12:30 PM | 12 |
| `r43_a1` 314159 busy | 17:36 | 12:36 PM | 12 |
| `r43_c1` 171717 normal | 17:41 | 12:41 PM | 12 |
| `r43_d1` 424242 busy | 17:46 | 12:46 PM | 12 |
| `r43_e1` 171717 busy | 17:51 | 12:51 PM | 24 |
| `r43_f1` 424242 busy | 17:59 | 12:59 PM | 24 |
| `r43_g1` 171717 busy | 18:07 | 1:07 PM | 48 |
| `r43_a2` … `r43_g2` | 18:21 – 18:57 | 1:21 – 1:57 PM | second pass |

Pass 1 covers all seven columns before pass 2 begins, deliberately: if the work carries a
defect the grid lane was too small to express, it shows on seven columns in the first 50
minutes rather than on one column after two hours.

**`r43_b1` landed at 17:32:49 UTC, 125 s, `equal: true`, every atom matching.** Its canons
against the pre-round row above, which is P2's first datum:

| atom | before | after | |
|---|---|---|---|
| `endst` | `8b5a0ad4` | `65f26efe` | **moved** |
| `rcl` | `0a4ca4d3` | `e8062941` | **moved** |
| `dec` | `cf2f44e2` | `5e03ebd0` | **moved** |
| `cmd` | `1ae7ba68` | `e07b4d2f` | **moved** |
| `cal` | `11a24626` | `11a24626` | unchanged, as predicted |

The four that were predicted to move moved, and the one predicted to hold held. One column
is not seven, and the judgement below waits for the rest.

### P3 — the grid columns do not move again.

Nothing will be applied while lane 2 is in flight. Any migration during the round would push
the floor past every pair already banked and the round would prove nothing — which is the
0308/0309/0311 lesson from the other direction.

## The blind spot this round exposes, narrowed by measurement, and NOT fixed in it

The fourteen atoms hash `ottoq_decision_snapshots`, `ottoq_vehicle_commands`,
`ottoq_decisions`, `ottoq_events`, `ottoq_stall_bookings`, `ottoq_energy_commands`,
proposals, deferrals, calibration, rule evaluations, recall decisions, SDRs, the tick count
and the end state. **`ottoq_telemetry_packets` is not among them** — no atom function
references it — and the position columns `0317` taught the emitter to write live there.

**A first draft of this section claimed that made position determinism entirely
uncertified, and that was too strong.** Measured, the geometry has exactly one source:

```
ottoq_trip_geometry(vehicle, run, clock) -> (bearing_deg, radius_km, progress, distance_km)
  |- ottoq_vehicle_position  -> ST_Project(depot origin, distance, bearing) -> lat/lng
  |                             -> ottoq_telemetry_packets.current_lat/current_lng
  `- ottoq_computed_eta_minutes -> distance / speed x congestion
                                -> ottoq_vehicle_dispatches.return_eta_minutes  [in endst]
```

So `distance_km` **is** certified, transitively: it sets the ETA, the ETA is written to the
dispatch row, and `endst.dispatches.vis` hashes it. That is precisely why the pair caught
`0319` at all — the random salt moved the calibrated radius, the radius moved the ETA, and
the ETA moved the end state.

What is genuinely uncovered is **the other half of the same tuple: `bearing_deg`.** It feeds
`ottoq_vehicle_position` and nothing else. A bearing that varied between two arms of one
seed would put every asset somewhere different on the map, and all fourteen atoms would
still agree — because no atom reads a packet, and bearing reaches no other table. `0319`
broke both halves at once and was convicted by the half that happens to be wired; a future
defect in the bearing alone would not be.

The fix is an atom over the telemetry position stream, added **MEASURED** first and enforced
only after a flagship round shows the arms agree, per 2.9a. Drafted after this round lands,
applied after that — never during. Recorded here, before the round, so that the round cannot
be quoted as evidence for a property it does not test.

---

## THE JUDGEMENT

*(written when the pairs land)*
