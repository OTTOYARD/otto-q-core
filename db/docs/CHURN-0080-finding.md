# OTTO-Q V1 — Stall-Assignment Churn (root-caused via the new audit feed)

Author: Hermes Agent · Date: 2026-08-28 · Run: 6889a959 (normal_day, seed 777002, post-0075/0079)

## The finding (what the audit feed exposed)

The `ottoq_activity_feed` I built in 0079 immediately surfaced a second churn defect — a sibling of
the deploy churn fixed in 0075, but deeper.

Vehicle `b9ef130e` (Waymo-AV-008) oscillated between a wash bay and an L2 charger:
- **104 stall-assignment decisions** for ONE vehicle in ~27 sim-minutes (52 to wash bay, 52 to charger)
- **41 of 42 `begin_charge` commands refused** as `superseded_by_newer_stall_command`
- **51 bookings interrupted** with `release_reason='bay_exit_before_planned_end'`

## Root cause (verified, not assumed)

`public.ottoq_decide_tick` has TWO independent space-assignment loops that both select the same
`staged_awaiting_service` vehicle in the same tick, assign it to DIFFERENT stalls, and do not
exclude each other:

1. **Section (3) — charge assignment.** Cursor: `current_state='staged_awaiting_service'` AND a free
   charger exists AND `current_soc < target_soc`. It does **not** consult the needs card. So a vehicle
   at SoC 93 (below the ~100% target) is routed to a charger — even when charge is merely
   *deferrable*.
2. **Section (4b) — needs-card space routing.** Cursor: `current_state='staged_awaiting_service'` with
   a must-do need whose lane requires a space. This vehicle's card: `must_do_now=['interior_deep_clean']`,
   `deferrable_now=['charge','sensor_calibration']`, `requires_charging='false'`. It correctly routes to
   the wash/detail bay.

So (3) charges "because SoC < target" while (4b) washes "because deep-clean is must-do". Two commands
for the same vehicle in the same tick → the confirm walk supersedes one → the loser's need remains
unmet → both re-fire next tick → infinite oscillation.

The (4b) firewall *was* written to prevent exactly this, but only one-directionally: it skips
vehicles whose card still lists `charge` in **must_do_now**. This vehicle has charge in
**deferrable_now**, so the firewall does not catch it, and section (3) has no corresponding check at all.

## Why it matters

- The decision ledger, forward calendar, and command bus all report motion that isn't earned — the
  same "motion reported but not earned" failure family as the deploy churn and every other defect in
  this project's history.
- It prevents a multi-need vehicle (the exact case Chase described: "comes back for a cleaning, might
  also need battery") from ever completing its atomic full-service visit. That is the product's core
  scenario, currently failing.
- It is **pre-existing**, not introduced by 0075/0079 — but 0075's deploy fix let vehicles progress
  further into their visits, which is what exposed it. One churn fixed revealed the next.

## The fix (design decision — the trade-off)

The doctrine (D6) is "full-service visit, charge is the anchor leg, energy first then bays." The bug
is not in that doctrine — it is that the two loops are not mutually exclusive for a vehicle that has
*deferrable* charge plus *must-do* bay work.

The correct sequencing is: **a vehicle with must-do bay work and merely-deferrable charge should go
to the bay first, and be topped off on charge afterwards** (before deploy). Section (3) should not
claim a vehicle that (a) has must-do bay work pending and (b) whose charge is not itself must-do.

The concrete fix: add a guard to section (3)'s cursor — skip a vehicle whose needs-card lists a
must-do bay service while its charge is only deferrable. The design cost is that section (3) must
read a light-weight "has must-do bay work" signal (not the full 250 ms card view) — a small derived
predicate or a cached column.

This is the "one space per vehicle per tick, sequenced by doctrine" principle the system has been
missing. I will implement it as a migration, then re-run and prove the oscillation is gone.

## Status

- 0075 (deploy churn): fixed, applied, verified.
- 0079 (activity feed): built, applied, verified — and it is what found this.
- 0080 (stall-assignment mutual exclusion): next, in progress.
