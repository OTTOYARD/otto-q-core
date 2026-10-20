# Proposal: the owner app says OTTO-Q's ready-by promise, not the plan's last leg

**For:** Chase, and the session that holds the owner functions (`ottoq_owner_car`, `ottoq_owner_read`, OTTO-Command).
**From:** the research wing, 2026-10-18. **Status:** a proposal. Nothing is patched. If it is taken, it ships as a
certified change, and only a person turns it on in production (CLAUDE.md rules 10 and 11).
**Evidence:** [db/checks/0451](../db/checks/0451_forty_robotic_fast_chargers_and_what_the_twin_can_say_about_them.sql)
§12, read on live between 6:53 and 7:02 AM CT on 2026-10-18, queries (13), (18), (20) and (46)-(48). FINDINGS G383,
G454, G455.

## What an owner is told today

`public.ottoq_owner_car` (prosrc md5 `683bf45b`) returns `ready_by_sim` as `max(planned_end_sim)` over the car's
planned or active itinerary legs. `public.ottoq_owner_read` (md5 `e217e009`) turns that into "Planned to be ready
around ..." for one car, and "Next planned ready: ..." for the three soonest. The itinerary is amended in place, and its
charge leg is the 45% rule's (an L2 at an assumed 11 kW above 45%), whatever chargers the depot has (G459).

## What the twin measured

There were two promise arms: arm 96 is the normal day at ten posts, in tick; arm 97 is the busy day at ten posts, with
the command lag. Each arm is one seed. Both the app's time and OTTO-Q's promise (`public.ottoq_ready_promise`, md5
`2bf2e3ed`: 16 simulated futures of the charge line, then the after-charge allowance, 128 draws) were recorded at the
same moment and graded against the car's readiness check.

| | normal day: app | normal day: promise | busy day: app | busy day: promise |
|---|---|---|---|---|
| at arrival, cars ready by the time given | 0.389 | 0.471 by the median, 0.903 by the p90 | 0.151 | 0.203 / 0.397 |
| at arrival, mean absolute error | 76.7 min | 49.8 min (median) | 148.3 min | 139.8 min |
| second look (every 30 sim-min), ready by | 0.373 | 0.540 / 0.895 | 0.236 | 0.317 / 0.603 |
| second look, mean absolute error | 74.0 min | 26.2 min | 104.1 min | 69.5 min |
| second look, a time already gone | 9.1% of reads | never | 3.9% | never |

The app's extra error on the normal day is mostly phantom legs. On cars whose plan held none, the app and the promise
are equally good (48.6 and 48.7 minutes). The 40 cars whose plan carried an L2 leg that was later skipped carry 52% of
the app's absolute error. The app told those owners their car would be ready about 2 h 18 min after it was. Phantom
bay legs alone (G464) carry 10%. 0745 and 0750 remove both kinds of phantom (applied 2026-10-18 behind dials; their arms
are queued).

On the busy day both are late, because the bay line grows all day. The promise often knows it: on 154 of its 212
promises the allowance's p90 was a lower bound (`detail.after_lb >= 3`). On those promises the cars ran an hour or more
past it.

## The proposed change

1. **`ottoq_owner_car` reads the promise.** For the car's newest open visit in the run, take its newest re-estimate
   (`ottoq_ready_promise_updates`), else its arrival promise (`ottoq_ready_promises`). Where neither exists (production
   records neither today), compute `ottoq_ready_promise` on demand. Return these fields:
   - `ready_by_sim` / `ready_by_local`: the promise's **90th percentile**;
   - `ready_likely_sim` / `ready_likely_local`: its **median**;
   - `ready_basis`: `promise`, `promise_bound` (when `after_lb >= 3`, the p90 is a floor), or `plan` (no promise could be
     made, so the itinerary's time is used, as today);
   - `ready_next_look_local`: the time of the next re-estimate.
2. **`ottoq_owner_read` says it plainly.**
   - `promise`: "Ready by about *p90* (likely around *median*)."
   - `promise_bound`: "Not before *p90*. The depot is busy; OTTO-Q will update you at *next look*."
   - `plan`: today's "Planned to be ready around ...".
   - It never names a time already gone. If the promise's time has passed and the car is not ready, it says "running
     late" and gives the next estimate.
3. **Nothing else changes.** It is a read. It changes no car, order, setting or dial. Every promise charges to the
   owner's target (100% by default, rule 9) and finishes every needed service before it calls a car ready.

## What it needs before production

- **Latency.** On the promise arms, recording a promise per visit plus a re-estimate every 30 sim-minutes nearly
  doubled an arm's wall time (3,338 s against 1,700 s). An on-demand promise for one car per owner read is far
  smaller, but its latency at production's 120-second tick has not been measured. Measure it, or serve the newest
  recorded estimate.
- **More than one seed.** Every figure above is one seed per day. Before certifying, run two more normal-day promise
  arms on value_2026_09_30's seeds 2 and 3, in tick. After 0745's and 0750's arms, re-grade the app's own time to see
  how much of its gap they close.
- **The busy day's realism (G453).** Chase's demand assumption decides whether `busy_day` is a day to tune for.
  `busy_day` without its compression is lighter than `normal_day`.
- **The prior.** Until the run has 8 cars of a kind, the after-charge part comes from a prior that is short on the
  normal day (bias +16.3 min, by p90 0.741). A depot's own history should replace it in production.

## Risks

- A promise that is honest about a busy day is long. Owners will see "Not before 4:10 PM" where today they see "around
  1:30 PM". That is the point, but it is a product decision.
- `ottoq_owner_car` is shared by the owner app and OTTO-Command (rule 11). Both would change their answer together,
  which is intended.
