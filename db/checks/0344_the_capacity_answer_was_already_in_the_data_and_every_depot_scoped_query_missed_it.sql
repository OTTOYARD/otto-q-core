-- 0344  **The question rule 8 exists to answer — "how many vehicles can this depot comfortably stage,
--       sort and orchestrate" — has been being answered continuously, and every depot-scoped query has
--       missed it, because the depot is in `entity_id` and not in `depot_id`.**
--
--       **The headline: at 120 vehicles the twin depot is NOT comfortable. On 3,128 overflow events it
--       carries a mean of 30.3 vehicles in overflow and 10.5 waiting past the patience threshold, peaking
--       at 46.** And 53.8% of its 9,193 refusals are `no_capacity`.
--
--       Measured 2026-09-22 ~16:2x UTC (11:2x CT).
--
-- ══ §1 WHY NOBODY HAD SEEN IT ════════════════════════════════════════════════
--
-- `twin.staging_overflow` is the depot's own "I am out of room" signal. **3,144 of 3,144 carry
-- `depot_id IS NULL`** — so every query written to rule 8's standard (`WHERE depot_id = '11111111-…'`)
-- returns ZERO and reads as "this never happens."
--
-- The depot is not missing, it is in the wrong column. `twin.ottoq_sim_advance_service_flow` emits:
--
--     p_entity_type := 'depot',
--     p_entity_id   := p_depot_id,     <-- the depot IS here
--     ...                              <-- and p_depot_id is never passed
--
-- Read through `entity_id`, **3,128 of the 3,144 are the twin depot** (the other 16 are a fixture, mean
-- overflow 1.0). So the evidence was complete and correctly attributed all along, just not by the column
-- every capacity question filters on.
--
-- **This is the fourth instance today of one shape** — after `0338` (five provenance columns, I measured
-- the sparse one), `0341` (`new_state` emptied by a space optimisation) and `0343` (a probe whose
-- population cannot contain what the rule tests). **I measured the standard column and concluded the
-- system was silent.** The cost here is the largest yet: it is not a wrong number, it is *a commercial
-- question that looked unanswered for weeks while its answer accumulated 3,128 times.*
--
-- ══ §2 WHAT THE DEPOT IS ACTUALLY DOING AT 120 VEHICLES ══════════════════════
--
--     twin.staging_overflow, entity_id = the twin depot        3,128 events, last 16:09:33
--       mean vehicles in overflow                              **30.3**
--       mean waiting past patience ("escalated")                **10.5**
--       max waiting past patience                                **46**
--       patience threshold                                      10.0 min
--
--     ottoq.refusal_escalated, depot_id = the twin depot       9,193 events, last 16:09:33
--       no_capacity                       4,949   **53.8%**
--       superseded                        2,125     23.1%
--       vehicle_state_incompatible        2,049     22.3%
--       command_malformed                    70      0.8%
--
-- **So the dominant failure mode of this depot, by a factor of two over anything else, is running out of
-- space** — and on a typical overflow tick roughly a quarter of the 120-vehicle fleet is queued with ten
-- of them already past the patience window.
--
-- `arm.move_refused` is 48 events, all correctly depot-attributed — small, and not the constraint.
--
-- ══ §3 WHAT THIS DOES **NOT** ESTABLISH, AND ONE TRAP INSIDE THE PAYLOAD ═════
--
-- **The payload's `*_cap` fields cannot tell you which capacity binds, and they look as though they can.**
-- Measured over all 3,222 twin events: `wash_cap` is **3.00 on every single event**, `svc_cap` **2.00**,
-- `deploy_cap` **20.00**, and **none is ever 0** — `wash_cap_exhausted`, `svc_cap_exhausted` and
-- `deploy_cap_exhausted` are all **zero**. These are the depot's *configured* capacities being restated on
-- every event, not the remaining headroom. **A reader would reasonably conclude no capacity was ever
-- exhausted, which is the opposite of what the same payload's `overflow: 30.3` says.**
--
-- So this check establishes **that** the depot is over-subscribed at 120 vehicles and **how badly**. It does
-- NOT establish **which** resource binds first.
--
-- **The best existing evidence on that is `db/checks/0250`**, which measured the live run and found every
-- refused proposal asking for one of the two charging stall types at **87% and 80% occupancy** — against a
-- site that has only **10 DCFC + 30 L2 = 40 charging positions for 120 vehicles**, of which `0372`/`0264`
-- put ~**13.8% of charger-time** out of service to faults, i.e. ~34 effective. That is a strong prior and it
-- is not re-derived here: the depot is idle at this moment (4 vehicles on site), so a live occupancy census
-- now would measure nothing, which is `0334`'s rule in its other direction.
--
-- ══ §4 THE CONSEQUENCE FOR WHAT TO BUILD NEXT ════════════════════════════════
--
-- I told Chase the next step was to "run the capacity experiment, because that number does not exist."
-- **Half of that was wrong: the experiment has been running continuously and the number exists.** What was
-- missing was reading it.
--
-- So the revised sequence is cheaper than proposed:
--
--   1. **Fix the attribution** (one argument: pass `p_depot_id` at the emit site). Until then every
--      capacity query written to rule 8's own standard silently returns zero — and rule 8 *mandates* that
--      predicate, so the house style and this event are in direct conflict.
--   2. **Make `*_cap` mean remaining, or rename it.** A field that always equals its configured value is a
--      trap that reads as reassurance.
--   3. **Then vary load** and watch `escalated` — which is already the right dependent variable, already
--      recorded, and already has a 10-minute patience threshold to define "comfortable" against.
--
-- **And the definition of "comfortable" is now a measurable thing rather than a philosophical one:** the
-- engine already computes `escalated` = vehicles waiting longer than `patience_min`. Chase's threshold
-- question ("zero refusals, or some acceptable wait?") maps onto exactly this field, so the business
-- judgement he owns is a single number — the tolerable value of `escalated` — and everything else follows.

\echo '=== 0344 §1 — the depot is in entity_id, not depot_id, so every rule-8 query reads zero ==='
SELECT event_type,
       count(*) AS total,
       count(*) FILTER (WHERE depot_id='11111111-1111-1111-1111-111111111111') AS by_depot_id,
       count(*) FILTER (WHERE depot_id IS NULL)                                AS depot_id_null,
       count(*) FILTER (WHERE entity_id='11111111-1111-1111-1111-111111111111') AS by_entity_id
  FROM public.ottoq_events
 WHERE event_type IN ('ottoq.refusal_escalated','twin.staging_overflow','arm.move_refused')
 GROUP BY 1 ORDER BY total DESC;
-- staging_overflow: 3,144 total, 0 by depot_id, 3,144 depot_id NULL, 3,128 by entity_id. The signal is
-- complete and correctly attributed -- just not by the column rule 8 mandates.

\echo '=== 0344 §2 — what the depot is doing at 120 vehicles ==='
SELECT count(*) AS events,
       round(avg((payload->>'overflow')::numeric),1)   AS mean_in_overflow,
       round(avg((payload->>'escalated')::numeric),1)  AS mean_past_patience,
       max((payload->>'escalated')::numeric)           AS max_past_patience,
       round(avg((payload->>'patience_min')::numeric),1) AS patience_min,
       max(occurred_at) AS last_seen
  FROM public.ottoq_events
 WHERE event_type='twin.staging_overflow'
   AND entity_id='11111111-1111-1111-1111-111111111111';
-- 30.3 in overflow, 10.5 past patience, max 46, on a 120-vehicle fleet. Not comfortable.

SELECT payload->>'reason_code' AS reason_code, count(*) AS n,
       round(100.0*count(*)/sum(count(*)) OVER (),1) AS pct
  FROM public.ottoq_events
 WHERE event_type='ottoq.refusal_escalated'
   AND depot_id='11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY n DESC;
-- no_capacity 53.8%, twice anything else. Space is the dominant failure mode.

\echo '=== 0344 §3 — the trap: the cap fields are constants, and read as reassurance ==='
SELECT count(*) AS events,
       count(DISTINCT payload->>'wash_cap')   AS distinct_wash_cap,
       count(DISTINCT payload->>'svc_cap')    AS distinct_svc_cap,
       count(DISTINCT payload->>'deploy_cap') AS distinct_deploy_cap,
       count(*) FILTER (WHERE (payload->>'wash_cap')::numeric = 0)   AS wash_exhausted,
       count(*) FILTER (WHERE (payload->>'svc_cap')::numeric = 0)    AS svc_exhausted,
       count(*) FILTER (WHERE (payload->>'deploy_cap')::numeric = 0) AS deploy_exhausted
  FROM public.ottoq_events
 WHERE event_type='twin.staging_overflow'
   AND entity_id='11111111-1111-1111-1111-111111111111';
-- One distinct value each, never zero. These are CONFIGURED capacities restated per event, not headroom.
-- A reader would conclude nothing was ever exhausted while the same payload reports 30 vehicles in
-- overflow. Which resource binds is NOT answerable from here -- 0250 is the evidence for that (refused
-- proposals wanting dcfc/l2 at 87%/80% occupancy, 40 charging positions for 120 vehicles, ~34 effective
-- after the 13.8% fault loss of 0372/0264).
