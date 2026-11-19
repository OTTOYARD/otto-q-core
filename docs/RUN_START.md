# How a run should start: a yard already at work

**Status:** recommendation, 2026-11-18 (evening CT). Not built. **Asked by Chase, 2026-11-18:** *"Should new run start
with vehicles in place and then 'go' after several ticks? Or take longer to plan upon start, but then renders with
vehicles randomly throughout the yard at various stages, etc?"*

## The answer

**The second, with one change of words: not random, but each car where its state says it is.** A run should open on a
yard that was already working before OTTO-Q looked at it: cars on chargers part-way through their charge, cars in the
bays part-way through their service, cars parked in staging stalls they actually hold, cars at the gate and cars out
at work. OTTO-Q's first tick then plans from that yard, as it will on the first morning at a real depot. A frozen yard
that "goes" after a few ticks is a picture of a depot switching on, which no real depot does; and it changes nothing
underneath, because the twin's record is the problem, not the timing (below).

**Why this one.** The swap test (`ottoyarddepot-sim/AGENTS.md`): the day OTTO-Q is connected to a real depot, that
depot is mid-shift. Its chargers are occupied, its bays are working, and no car is anywhere without a reason. A run
that starts any other way tests a start OTTO-Q will never meet in production.

## What happens today (read 2026-11-18 on run 368e1472, the last run, started 12:40 PM CT)

Read from `vehicle_state_log` at the twin depot, read-only:

| | Cars | With a stall in the twin's record |
|---|---|---|
| **At the boot instant** (18:40:49 UTC) | 116 | **0** |
| staged for departure | 72 | 0 |
| out at work (deployed) | 15 | 0 |
| at the gate | 12 | 0 |
| staged, awaiting service | 7 | 0 |
| charge complete, holding | 6 | 0 |
| driving home | 4 | 0 |
| **In the next 24 seconds** (the first tick, 18:41:13 UTC) | | |
| staged for departure, then awaiting service | 43 | 0 |
| awaiting service, then charging on a fast charger | **30** | 30 |
| charge complete, holding, then awaiting service | 7 | 0 |
| awaiting service, then in a wash bay | 3 | 3 |
| at the gate, then charge complete, holding | 1 | 0 |
| driving home, then at the gate | 1 | 0 |
| (85 state changes in all) | | |

So:

1. **97 cars are on the site with no stall in the twin's own record.** The renderer has to put them somewhere, so it
   claims a staging stall for each itself (`TwinMotionDriver`, `ledger.claimFirstFree`). That is the renderer deciding
   world state, which the law (`AGENTS.md`: *"the renderer only draws"*) calls a defect.
2. **All 30 fast chargers fill in one tick**, 24 seconds in, so the first thing anyone sees is 30 cars leaving staging
   at once. Nothing in a real depot does that; it is the yard's empty chargers meeting a full queue at the same moment.
3. **43 of the 72 "ready" cars need service a tick later.** The boot wrote a state before the needs were known.

What the boot already does well, and keeps: the cars at work start staggered through their trips and 30% of them are
already driving home (`twin.ottoq_sim_prime_deployment`, the 2026-08-02 stagger), so arrivals do not start with a dead
front. The yard has no equivalent of that stagger. That is the whole gap.

## What to build (an engine change; the renderer changes nothing)

One boot step after the needs draw and before the first tick, behind a policy dial that starts off, in
`twin.*` (world state, never OTTO-Q's decision path):

1. **Every car on the site gets a place it holds:** a staging stall booking through the calendar (the EXCLUDE
   constraint keeps it honest), or a charger, or a bay. No car on the site without one.
2. **Chargers and bays start part-way through their work**, stratified the way the deployment prime stratifies trips:
   a charge session already running with its state of charge drawn between where it started and its target (rule 9:
   the target stays 100%, nothing is shortened), a bay seat already under way with its end time inside the service's
   own duration. The cars chosen are cars whose drawn needs call for that work, so no service is invented.
3. **The first tick plans from there.** No synchronized wave: chargers free up one by one as their charges end.
4. **The renderer stops choosing.** With every car's stall in the twin's record, the driver's own staging claim is
   never reached at boot; the first snapshot draws everyone in place (it already does, for a car whose stall it knows).

**How it is checked (rule 12: one demo run, not a test program):** at the first frame every car on the site has a
stall in `vehicles.current_stall_id` and a live booking; the first 30 seconds change a handful of states instead of
the 85 above; no charge is shorter than its target; and the twin app's first minute shows chargers and bays working, not a
convoy.

**What it costs:** the boot fingerprint changes, so every determinism canon recertifies when the dial is turned on
(testing is paused under rule 12, so nothing reruns until it resumes), and a run's first hour is no longer a fill-up,
which changes every first-hour figure. Quote none from before and after together.

## Decision needed

Chase's yes on the second option (each car where its state says, chargers and bays part-way through) before the boot
change is built. It changes how every run starts, at the only test site, so it is his call, not a default.
