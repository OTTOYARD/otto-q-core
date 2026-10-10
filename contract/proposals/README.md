# Proposals for contract 0.2

Nothing here is part of contract 0.1. Each proposal is a draft schema, an example and a test that validates the draft
against 0.1's own shared definitions, so it cannot drift from the rules it reuses.

## `directive.recall` (proposed 2026-10-10, for Chase's decision)

**Why:** contract 0.1 has no way for OTTO-Q to ask an operator to bring a car home. Only the operator can say a car
is coming (`depot.arrival.intent`). The twin works today because OTTO-Q's own recall evaluator runs inside the twin's
tick, which no real operator would allow, so the last stage of the twin's sending side (docs/TWIN_SENDING_SIDE.md)
cannot be routed through the door without it. The Recall Decision (CLAUDE.md 2.7) is the single interface to the work
side, and this is its wire form.

**What:** `com.ottoyard.directive.recall`, OTTO-Q to operator, ack required, with every directive's header (id,
version, `supersedes`, issue, validity, expiry, ack deadline, the car). Its own fields: `recall_by` (the latest turn
home), `reason` (closed: `energy_reserve`, `service_due`, `fault`, `depot_window`, `owner_request`), `services` (from
the depot's catalog) and `target_ready_time` (p50 and p90). No charge target: the owner's own target stands (rule 8).

**The answer:** an ack as for every directive. `accepted`, then a `depot.arrival.intent` when the car turns home. Or
`rejected` or `unable` with a reason from the closed list, which gains one value, **`mission_in_progress`**: the car is
mid-trip and will come when it ends. CLAUDE.md 2.7 calls that refusal *"a first-class event triggering re-solve, never
an error"*; OTTO-Q re-plans the visit around the later arrival.

**What it changes when adopted:** the twin's operators honour recalls as a real operator would, and OTTO-Q's recall
evaluator runs on the telemetry the door took, not inside the twin's tick.
