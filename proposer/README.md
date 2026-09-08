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

## Abstention is first-class

No class-table entry, no readable `soc`, a target at or below the current charge, or no point
on site whose plug fits → an **abstain row with its reason**, never a guess and never a silent
drop, and never an exception that takes the rest of the batch with it. The disposer should know
the proposer saw the vehicle and declined — cuOpt's abstention pattern, preserved.

## What integration requires (founder-gated; nothing here does it)

An edge function that: reads the frame → calls `propose()` with the class-table join and
visit-need ready-bys → inserts the rows with `sim_run_id`/`depot_id`/`expires_at` → logs the
fire. The deferral table and gate router need nothing new — the rows match the shape they
already receive from `greedy_constrained` and cuOpt.
