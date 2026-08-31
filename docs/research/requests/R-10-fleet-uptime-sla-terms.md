# R-10 — What autonomous-fleet operators actually contract for: uptime and depot SLA terms

**Filed:** 2026-08-31 by the build track (Claude Code)
**Blocks:** nothing today — the engine runs. It blocks the *targets*, which is worse:
`ottoq_kpi_five()` currently emits five measurements with **no thresholds**, so the system
cannot answer "are we meeting the requirement." `ottoq_fleet_operator_slas` already holds the
right shape (min_soc_at_deployment_pct 80, preferred 90, max_queue_wait_minutes 30,
expected_visit_duration_minutes 45) but roughly half its fields are NULL. This request fills
the NULLs with sourced values instead of invented ones.

Please answer per **operator type** where they differ — robotaxi (Waymo, Zoox, Cruise-style),
yard logistics / drayage, and AMR / intralogistics — and name the source and its date for each
figure. Where something is genuinely not public, say "not public" rather than estimating; a
labelled gap is more useful to us than a plausible number.

## Q1 — Availability, stated as the operator states it
What availability or uptime figure do these operators commit to or publish, and **what is the
denominator**? Specifically: is it vehicle-hours available / vehicle-hours owned, percentage of
fleet ready at a named clock time, or something else? Give the metric name and formula as the
source words it, plus the numeric target if published (e.g. "95% of fleet available at 06:00
local").

## Q2 — Readiness deadline and state
Is there a contractual **time by which N vehicles must be ready**, and what does "ready" mean in
those terms — minimum state of charge, cleanliness, inspection currency, calibration validity?
We need the units: percent SoC, hours since last clean, days since calibration.

## Q3 — The NULL fields, directly
For each, a typical contracted value or "not public":
- `max_visit_duration_minutes` — cap on total time a vehicle may be held at a depot
- `max_queue_depth` — how many vehicles may be waiting before it is a breach
- `max_overnight_stage_count` — cap on vehicles parked overnight at one site
- `max_concurrent_vehicles_at_depot` — site occupancy cap
- `return_reserve_soc_pct` — SoC an operator insists is retained for the return trip
- `maintenance_window_start` / `_end` — hours in which service is permitted or forbidden
- `required_services_before_deploy` — services that must complete before a vehicle redeploys

## Q4 — Penalties
How are misses actually priced: per-vehicle-hour credits, flat monthly service credits, tiered
by breach severity? We have an empty `penalty_schedule` and no idea of its shape.

## Q5 — Which number the operator manages to
Of everything above, **which single figure do fleet operations teams actually watch daily**?
We have five KPIs and no ranking; if one of them is what the customer lives by, that changes
what we optimise first.

Why it matters: our core currently optimises none of these explicitly (see
`db/checks/0052_capability_depth_audit.sql` — there is no objective function, and the site power
cap is recorded but not enforced). Before we wire an objective, we want its terms to come from
what customers actually buy rather than from our own assumptions.
