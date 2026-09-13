# proposer/ — the forward orchestrator as a production proposer

The seat this occupies is **exactly cuOpt's seat, and deliberately no more**: a proposer under
the propose/dispose pattern. `propose()` takes a production decision frame and returns advisory
rows in the `ottoq_external_proposals` shape; the deferral pattern gives an in-flight proposal
its one-tick right-of-first-refusal; **the disposer remains the production decide path.**

**Occupying that seat requires sizing the frame, and the numbers are these.** Every solve is
bounded by default now (`DEFAULT_DET_BUDGET_S = 2.0`, deterministic work rather than wall
clock, so the cost is a property of the instance and not of the box). A deterministic budget
bounds the *search*, not the *model*, and on this codebase the model is what costs:

| frame | `max_assets` | wall time |
|---|---|---|
| 44 vehicles / 16 stalls | unset | **97.9 s** |
| 44 vehicles / 16 stalls | 12 | 14.0 s |
| 44 vehicles / 16 stalls | 8 | **7.6 s** |

The engine ticks every 30 seconds. So the whole-frame solve does **not** fit the one-tick seat
at production scale, at any budget — an earlier version of this README asserted the seat
without that qualification and it was not true. A caller that must occupy the tick passes
`max_assets`: the most urgent N are solved (earliest `ready_by`, then lowest SoC, then id) and
every deferred vehicle still gets an abstention row naming the batch, so *deferred to the next
tick* stays distinguishable from *nobody asked*. Left unset there is no batching, which is
right for offline planning.

```
decision frame ──▶ frame_to_scenario ──▶ lexicographic solve ──▶ plan_to_proposals ──▶ rows
 (ottoq_build_      (adapter: DB           (policies/forward:      (production
  decision_frame     vocabulary → kernel    min tardy, then         proposal jsonb,
  shape, verbatim)   declared data)         min peak)               verbatim)
```

**This module never writes.** It has no channel to: the separation guard proves it cannot
import a database client. Whoever calls it — an edge function, a founder-gated integration —
performs the insert and logs the fire record (`cuopt_invocation_log` discipline: every
invocation quantifiable, "never invoked" distinguishable from "invoked and abstained").

## What the frame does not carry — declared, not guessed

- **Battery capacity and energy curves.** A frame has `soc` (%) but not kWh, so energy is
  uncomputable from the frame alone. The caller supplies a `class_table` (in production: the
  `ottoq_vehicle_classes` join). **There is no default** — a made-up battery size is a silently
  wrong plan for every vehicle.
- **Required-ready-times.** The caller passes them or a default delta; every proposal's
  `rationale.ready_by_source` records which was used, so a schedule built on a default deadline
  is labeled as one.

### The production join, which for a while was a sentence and not an integration

The line above said the class table is "the `ottoq_vehicle_classes` join". It was not joinable
(finding L-41): the table is keyed by `vehicle_class_code` and the frame did not emit that
column at all; its columns are named `battery_capacity_kwh` / `max_charge_rate_kw`, so passing
a row verbatim raised `KeyError`; and it had no `charge_kinds` column, which the bridge now
requires and refuses to default. Three pieces close it:

- **Migration 0209** adds `vehicles[].vehicle_class_code` and `stalls[].supported_inlet_types`
  to `ottoq_build_decision_frame`, and a backfilled `charge_kinds` column to
  `ottoq_vehicle_classes` (derivation recorded in that column's `COMMENT`).
- **`proposer/class_table.py`** is the column projection — the renames written down once, with
  the `SELECT` committed beside them so the two cannot drift.
- **`class_key`** on `frame_to_scenario` / `propose` names the frame field the table is keyed
  on. It defaults to `vehicle_class_code`, the production key; a caller with a pack file keyed
  some other way names its own field.

### The plug is checked here, using the engine's own rule

`charge_kinds` decides which stall **types** a vehicle may reach; it says nothing about whether
the connector fits. The bridge folds the plug into the kernel's capability label — a point is
`dcfc@CCS1`, or `dcfc@CCS1+NACS` for a multi-standard one — so the kernel never learns what a
connector is, and a vehicle may only use labels whose inlet set contains its own inlet.

The rule is not invented here. The L1 shield already owns it: a `Multi` stall passes iff the
vehicle's inlet is in that stall's `supported_inlet_types`; otherwise `connector_type` must
equal `inlet_type`. On the flagship depot all 84 charging stalls are `Multi` with
`{CCS1, NACS}`, so a bridge comparing the two fields literally would abstain on every vehicle,
and one ignoring both would propose every vehicle onto every plug. Neither is what the engine
does.

### A stall somebody holds is not a point this tick (finding L-58)

The frame has carried `stalls[].status` and `stalls[].vehicle_id` (`stalls.status`,
`stalls.current_vehicle_id`) since 0209, and `frame_to_scenario` read neither: every
charge-capable stall was a service point the plan could start on at t=0. It showed on the
first live D3 cycle (run `af2def1b`, tick 10 — 40 charging stalls, 23 of them occupied): all
four immediate starts the solver planned were onto stalls another vehicle was plugged into,
with 17 free stalls idle. The shield would have refused each with a rule code, correctly, and
the proposer would have contributed nothing all run. Now a stall is offered to the solver only
if its `status` is exactly `available` **and** it holds no vehicle; the skipped count travels
as `stalls_busy` on the result and `n_stalls_busy` on the fire record, so "planned on 17 of
40" is a ledger fact. A row with no `status` key (fixtures, older producers) is treated as
free, so the field's absence is visible in the plan rather than silently emptying it. **Not
modelled yet, and said so:** when the occupant will finish — that is what `sessions[]` is for;
until it is read, a held stall is not planned on this tick rather than planned on at a guessed
time.

And the accounting beside it (finding L-59): `planned` counts rows that **name a stall**. A vehicle the
solver admits but gives no charge operation comes back as an abstain row and is counted as one; the
first tick-16 fire on run `af2def1b` had read "8 planned" over six stall rows before this was fixed.

### 'Pending' is not 'heard' (finding L-60)

Measured on the first live D3 run (`af2def1b`, 2026-09-13): 54 `forward_lex` rows submitted across
two fires, **zero** reached the shield. Two reasons, neither a refusal. A vehicle waiting in staging
usually already holds a booking the frame does not show, and the decide path re-decides a vehicle
only while it holds none — so a proposal for it sits `pending` until its TTL and is never looked at.
And an arrival is decided in the tick it arrives, by the local heuristic, unless the one-tick hold
(0259) is on for the run — which it could not be, because its gate key was never registered with
`ottoq_policy_set` (0262). The population an out-of-process proposer can be heard on is the one the
hold is holding: unreserved arrivals. `propose(..., serviceable_states=...)` and the bridge's
`--states` narrow the fire to it; the set can only narrow, never widen, and the fire record carries
it as `serviceable_states`. The frame-side fix — carry the booking so the proposer can see it — is a
kernel change and is not made here.

### The frame hides what decides (finding L-61) and an infeasible frame is a fire, not a crash (L-62)

Run `ccf48af1` (2026-09-13, the one-tick hold ON): 36 rows, 13 naming a stall, zero heard. The
selector (`ottoq_l2_external_proposal`) pre-filters a proposed stall on three facts — no current
vehicle, no live reservation for another vehicle, charger `station_state = 'Available'` — and the
frame carries only the first (`vehicle_id`). Every stall the proposer named was reserved for
someone else, freshly occupied, or behind a **Faulted** charger, and the frame said `available`
for all of them. Until the frame carries `reserved_by`, `reservation_expires_at` and the charger
state per stall (kernel migration, not made here), a proposer at a depot that reserves every
stall cannot be heard; `demo/D3_RUNBOOK.md` §5 has the per-stall table. And when the frame is
oversubscribed (13 vehicles, 1 stall) the kernel raises `INFEASIBLE`; the bridge now records
that as an `empty` fire with the solver's words in `error` and `--allow-rejection` lets it plan
what fits (L-62).

## Abstention is first-class

No class-table entry, no readable `soc`, a target at or below the current charge, or no point
on site whose plug fits → an **abstain row with its reason**, never a guess and never a silent
drop, and never an exception that takes the rest of the batch with it. The disposer should know
the proposer saw the vehicle and declined — cuOpt's abstention pattern, preserved.

## What integration requires (founder-gated; nothing here does it)

**2026-09-12 — the integration now exists, outside this package:** `bridge/proposer_bridge.py` (a non-kernel package; `bridge/README.md`) reads the frame, calls `propose()`, and submits the rows through `ottoq_submit_external_proposal`. The generalization L-40 asks for below is migration `0259`; the fire ledger is `0260`; `db/checks/0184` is the measurement.

An edge function that: reads the frame → calls `propose()` with the class-table join and
visit-need ready-bys → inserts the rows with `sim_run_id`/`depot_id`/`expires_at` → logs the
fire. The rows match the shape the gate router already receives from `greedy_constrained` and
cuOpt.

### The deferral pattern is cuOpt-only today (finding L-40)

This file and `forward_proposer.py`'s module docstring both said whoever inserts these rows gets
"the one-tick right-of-first-refusal" and that "the deferral table and gate router need nothing
new." **The second half is false, and it was worth being told plainly rather than discovered at
integration.** The live mechanism is source-specific in three places:

1. `ottoq_cuopt_first_refusal_arm` arms a vehicle only when no pending proposal exists with
   `p.source IN ('cuopt','cuopt_fallback')`, and writes to `ottoq_cuopt_deferrals`.
2. The arming cap is the policy key `cuopt_first_refusal_max_defers`.
3. `ottoq_l2_external_proposal` picks the winner with
   `ORDER BY (p.source = 'cuopt') DESC, (p.source = 'cuopt_fallback') DESC, p.created_at DESC`.

So a `forward_lex` row would get **no deferral window and last place in the tie-break**: it
would race the local decide path with no protection, and lose to any pending cuOpt row.

Nothing is affected today — measured 2026-09-08, `ottoq_external_proposals` holds
`greedy_constrained` 12,367, `ottoq_service_priority` 1,713, `cuopt` 136, and **`forward_lex` 0**,
because this module writes nothing and the integration is founder-gated. The claim was the
defect, and the claim is now corrected.

**The extension, when the integration lands** (deliberately NOT done here, because it rewrites
the live decide path's proposal selection and that is a scheduling decision, not a docs fix):
generalize the precedence into declared data rather than three literals. `ottoq_policy_params`
cannot hold it — `param_value` is `numeric` — so it needs a small precedence table keyed by
source, seeded with `('cuopt', 'cuopt_fallback')` so the default reproduces today's ordering
exactly and no canon moves. `ottoq_cuopt_deferrals` and its arming function want the same
treatment, parameterized by source rather than named for one.

## L-63 — what the solver actually does on a real flagship frame (measured 2026-09-13 05:35 UTC)

Ran the offline route over the captured flagship tick-1 frame (`frame_c1`: 39 vehicles,
40 charge stalls, **24 of them already busy**), `--states arrived_at_gate`,
`--default-ready-delta 30`, `--allow-rejection`, OR-Tools 9.15.6755:

| | value |
|---|---|
| vehicles in `arrived_at_gate` | 11 |
| rows that named a stall (`n_planned`) | **5** |
| rows that abstained | 6 — all six `not_due` |
| pass 1 / pass 2 status | `FEASIBLE` / `FEASIBLE` |
| `complete` | **false** |
| `optima_reached` | `min_tardy` 255, `min_peak` 370 |
| total tardiness / total flow / site peak | 255 min / 554 min / 370 kW |
| `deterministic_time` | **4.012026** against a `det_budget_s` of 2.0 |
| `reproducible` | **true** |

Four things to read correctly, because three of them look like defects and are not:

1. **`deterministic_time` 4.01 against a 2.0 budget is not a budget violation.** The field
   is the SUM across the lexicographic passes (`forward_proposer.py`: pass1 + pass2), and
   the budget is per pass. Two passes at the cap is exactly 4.0.
2. **`complete: false` with both passes `FEASIBLE` means neither pass PROVED its optimum
   inside the budget.** The plan is the best found, not a proven optimum. So the honest
   sentence is *"a deterministic-time-bounded solve that returns the best plan it found"* —
   never "optimal", on this frame size, at this budget.
3. **`reproducible: true` is independent of `complete`.** Same inputs, same plan, whether or
   not optimality was proved — which is the property the certification story needs, and the
   one `R-12` established the leading GPU solver cannot offer at all.
4. **Five of eleven planned, six abstained as `not_due`, is the objective working.** With 24
   of 40 stalls busy, the min-peak term defers anything it is not obliged to start; that is
   what `--default-ready-delta` exists to override when the point of the run is to see the
   proposer act (`demo/D3_RUNBOOK.md` §2).

And one limitation confirmed rather than found: **`--regime` is live-only**, exactly as its
help text says. The offline route cannot resolve a regime because it has no run to read a sim
hour from, so the declared-objective path (`intent/intent_v1.json` → `intent/solve.py` →
`policies/regime.py`) is exercised only against a live run. That is a real coverage gap for
G45's wiring claim, not a bug in the flag.
