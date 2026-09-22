-- 0325  **The `stall_assignment` probe has fired 975 times on the live run and every single one carries
--       a `requested_kw`. It is a CHARGE gate wearing an assignment gate's name. Meanwhile 212 of the
--       run's 276 stall bookings — 77% — are not charges.**
--
--       Third instance tonight of the same shape, and the most consequential: `0324` §3 found SM.001
--       green because the seeding path never reaches its probe; `0323` §3 found three probe points no
--       census had counted; this is a probe that fires for one class of the decision it is named after.
--
--       No migration. This is a coverage-shape finding and it does NOT support alarm — §3 is the part
--       that keeps it honest.
--
--       Measured on run `61cedc05-fa8a-44f0-8a31-5cd6404404ff` (busy_day, seed 700001, twin depot).
--
-- ══ §1 THE PROBE IS CHARGE-ONLY, MEASURED ═════════════════════════════════════
--
-- Every `stall_assignment` evaluation in the table carries `requested_kw`:
--
--     has requested_kw   evaluations   distinct codes
--     ----------------   -----------   --------------
--     true                       975                5
--     false                        0                -
--
-- 975 evaluations over 5 codes is **195 probe firings**, and the context is identical across all five:
-- `{action, now_ts, depot_id, stall_id, inlet_type, vehicle_id, current_soc, requested_kw,
-- vehicle_state, fleet_operator_id}`. **`requested_kw` is always present and `stall_type` and
-- `purpose` are never present** — so the probe is only reached when something is asking for power, and
-- the five codes it carries are the five that need power to have an opinion: `EN.001` grid capacity,
-- `EN.005` grid hardstop, `HW.001` connector compatibility, `HW.002` charger state, `HW.004` single
-- vehicle.
--
-- Against that, the same run's bookings:
--
--     purpose            bookings   stall type      charge?
--     ----------------   --------   -------------   -------
--     temp_hold               155   staging         no
--     charge_l2                46   l2              YES
--     service                  26   service_bay     no
--     wash                     21   wash_bay        no
--     charge_dcfc              18   dcfc            YES
--     perimeter_hold            5   staging         no
--     detail                    5   wash_bay        no
--     ----------------   --------
--     TOTAL                   276      of which charge: 64 (23%), non-charge: 212 (77%)
--
-- **So the gate named for judging stall assignments is asked about 23% of them.**
--
-- ══ §2 THIS SHARPENS `0263` §1 RATHER THAN REPEATING IT ═══════════════════════
--
-- `0263` §1 established that four of the five `stall_assignment` codes are charge-specific and
-- *"cannot judge a parking hold"*, and CLAUDE.md 2.5 quotes it as the reason 21-of-30 is an optimistic
-- bound. **The stronger fact is that they are never ASKED to.** "Cannot judge" implies the rule runs and
-- has nothing to say; measured, the probe does not fire at all for a non-charge assignment. A rule that
-- is not invoked and a rule that abstains are different failure modes with different fixes — the first
-- needs a probe, the second needs a rule — and only the first is what is happening here.
--
-- ══ §3 WHAT ACTUALLY PROTECTS THE OTHER 77%, BECAUSE IT IS NOT NOTHING ════════
--
-- **This is not an unguarded 212 bookings, and saying so would be the same overstatement in the
-- opposite direction.** Three mechanisms cover non-charge stall selection, none of them an L1 rule:
--
--   1. **The EXCLUDE constraint on `ottoq_stall_bookings`** makes double-booking physically impossible
--      — CLAUDE.md rule 6's "assignment plus verification", and a constraint is stronger than a rule
--      because it cannot be probed-around.
--   2. **The three-gate availability check** (pointer, calendar, and charger-not-`Faulted` for
--      `dcfc`/`l2`) inside the booking path, which Part 3 records as earned three times in one night.
--   3. **`task_start`, which DOES judge non-charge work** — measured on this run: `need_service` 3,237
--      evaluations, `need_deploy` 1,521, `wash` 104, each across all **13** codes. The vehicle's task
--      is gated even when its stall choice is not.
--
-- And `HW.004.stall_single_vehicle` says in its own description that a partial unique index enforces it
-- rather than the probe — **so the engine already documents this pattern of structural-rather-than-rule
-- protection.** That is a legitimate design: a constraint that cannot be bypassed beats a rule that can
-- be logged and ignored.
--
-- ══ §4 SO WHAT IS THE ACTUAL DEFECT, STATED NARROWLY ══════════════════════════
--
-- Not "77% of assignments are unprotected." It is this: **nothing rule-shaped judges whether the stall
-- TYPE fits the PURPOSE at the moment of assignment**, and no probe carries the two fields
-- (`stall_type`, `purpose`) such a rule would need. On this run every purpose landed on a plausible
-- type — `temp_hold`/`perimeter_hold` on `staging`, `service` on `service_bay`, `wash` and `detail` on
-- `wash_bay` — so **there is no observed violation to point at**, and that is precisely why it should be
-- built MEASURED before it is built ENFORCING, per CLAUDE.md 2.9a.
--
-- Measured over every surviving booking at the twin depot, the pair matrix is **completely
-- type-consistent** — `dcfc`/charge_dcfc 19, `l2`/charge_l2 76, `service_bay`/service 36,
-- `staging`/perimeter_hold 41, `staging`/temp_hold 165, `wash_bay`/wash 33, `wash_bay`/detail 10.
-- **Seven pairs, no crossings**: nothing parks on a charger and nothing charges in a bay. So the rule
-- would currently pass everything, which is the correct time to build it MEASURED.
--
-- Note `detail` lands on `wash_bay` (10 bookings depot-wide), which is either correct (a detail bay is a wash bay
-- in this depot's fixture — the twin depot has 3 wash bays and no separate detail bay) or the first
-- instance of the thing a type/purpose rule would catch. **I am not calling it either from here**: it
-- needs the fixture's intent, which is Chase's to state, and it is exactly the case that makes the rule
-- worth having rather than academic.
--
-- ══ §5 WHAT I AM NOT DOING, AND WHY ═══════════════════════════════════════════
--
-- **I am not adding a rule tonight.** A new L1 code needs (a) the two context fields plumbed into the
-- probe, which is a change to the booking path rather than to `ottoq_rules`, (b) a declared
-- type-to-purpose capability matrix, which does not exist as data — `stalls.stall_type` and
-- `ottoq_stall_bookings.purpose` have no join table asserting which pairs are legal — and (c) the 2.9a
-- MEASURED-then-ENFORCED round. Inventing (b) overnight would be exactly the invented-bound mistake
-- `0413` §5 and `0414` §3 both refused. **The capability matrix is also precisely what CLAUDE.md 2.3
-- already names as the ServicePoint generalization — "capabilities as (asset_class, operation) pairs" —
-- so this rule should be built ON that when C3 lands, not beside it.**
--
-- The honest one-line status: *the assignment gate is charge-only; non-charge stall selection is
-- protected structurally rather than by rule; the missing rule is stall-type-fits-purpose, it has no
-- observed violation yet, and its data dependency is C3's capability pairs.*

\echo '=== 0325 §1 — every stall_assignment evaluation carries requested_kw ==='
SELECT (context ? 'requested_kw') AS has_requested_kw,
       count(*) AS evaluations,
       count(DISTINCT rule_code) AS codes,
       round(count(*)/NULLIF(count(DISTINCT rule_code),0)) AS probe_firings
  FROM public.ottoq_rule_evaluations
 WHERE action_context='stall_assignment'
 GROUP BY 1;
-- One row, true. The gate never fires for an assignment that is not asking for power.

\echo '=== 0325 §1 — and 77% of bookings are not charges ==='
SELECT b.purpose, s.stall_type::text AS stall_type, count(*) AS bookings,
       CASE WHEN b.purpose LIKE 'charge%' THEN 'JUDGED at stall_assignment'
            ELSE 'not judged there' END AS shield_status
  FROM public.ottoq_stall_bookings b
  JOIN public.stalls s ON s.id = b.stall_id
 WHERE b.sim_run_id = '61cedc05-fa8a-44f0-8a31-5cd6404404ff'
 GROUP BY 1,2 ORDER BY bookings DESC;
-- RUN-scoped, to reproduce §1. Depot-scoped over every surviving booking it reads 380 total / 285
-- non-charge (75%) -- the same shape, and a reminder that a booking census needs its run as much as
-- its depot (CLAUDE.md rule 8 plus "cite the run, never the table").

\echo '=== 0325 §3 — what does cover the other 77%: task_start, across all 13 codes ==='
SELECT COALESCE(context->>'svc_step','(none)') AS svc_step,
       COALESCE(context->>'service','(none)') AS service,
       count(*) AS evaluations, count(DISTINCT rule_code) AS codes
  FROM public.ottoq_rule_evaluations
 WHERE action_context='task_start'
 GROUP BY 1,2 ORDER BY evaluations DESC LIMIT 8;
-- need_service, need_deploy and wash are all judged by 13 codes. The vehicle's TASK is gated even
-- where its STALL CHOICE is not, which is why §1 is a coverage-shape finding and not an alarm.

\echo '=== 0325 §4 — the pair a type-fits-purpose rule would judge, and no join table declares it ==='
SELECT s.stall_type::text AS stall_type, b.purpose, count(*) AS bookings
  FROM public.ottoq_stall_bookings b
  JOIN public.stalls s ON s.id = b.stall_id
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1,2 ORDER BY 1,2;
-- Every pair here is plausible, so there is nothing to enforce against yet -- except possibly
-- detail-on-wash_bay, which needs the fixture's intent. CLAUDE.md 2.3's (asset_class, operation)
-- capability pairs are where the legal set should be declared; C3 owns it.
