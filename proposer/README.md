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

## Abstention is first-class

Unknown platform, or no capable point on site → an **abstain row with its reason**, never a
guess and never a silent drop. The disposer should know the proposer saw the vehicle and
declined — cuOpt's abstention pattern, preserved.

## What integration requires (founder-gated; nothing here does it)

An edge function that: reads the frame → calls `propose()` with the class-table join and
visit-need ready-bys → inserts the rows with `sim_run_id`/`depot_id`/`expires_at` → logs the
fire. The deferral table and gate router need nothing new — the rows match the shape they
already receive from `greedy_constrained` and cuOpt.
