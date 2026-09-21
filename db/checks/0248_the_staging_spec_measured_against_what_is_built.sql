-- ============================================================================
-- 0248 — CHASE'S STAGING / ORCHESTRATION SPEC, MEASURED LINE BY LINE AGAINST
--        WHAT IS ACTUALLY BUILT.
-- ============================================================================
-- Measured 2026-09-14 ~23:10 UTC, read-only, against twin run
-- 34ffb2d9-bcc6-4232-bbfc-d2c4d51e4ec5 and the live schema. Round 45 in flight
-- on other depots; nothing here writes.
--
-- THE SPEC, as given: short-term staging AND long-term/perimeter holding; know
-- which stalls are booked and do not send vehicles there; when every service,
-- wash and charge stall is booked, stage temporarily; anything flagged
-- mid-workflow goes to perimeter / long-term holding; when a stall frees,
-- TELL the vehicle to proceed; never lose track of a vehicle that is waiting.
-- It matters most where supply is scarce -- 10 DCFC and no L2 means staging and
-- the COMMUNICATION of staging dominate the run.
--
-- ── CORRECTION FIRST, BECAUSE I SAID THE WRONG THING OUT LOUD ──────────────
-- I sampled FOUR twin.staging_overflow rows, saw 'escalated': 0 on each, and
-- reported that escalation never fires. The aggregate over all twenty says:
--
--   overflow events ........................... 20
--   max vehicles in overflow at once .......... 13
--   summed overflow observations .............. 166
--   ESCALATED ................................. 43      <-- not zero
--   gate_held ................................. 14
--   patience_min .............................. 10
--   svc_cap / wash_cap ........................ 2 / 3
--
-- Four rows are not the population. Same defect class as everything else caught
-- today, committed while actively hunting for it.
--
-- ── WHAT IS LIVE AND FIRING ────────────────────────────────────────────────
--
--   short-term staging ....... 232 stalls across 6 zones (arrival_inspection,
--                              staging_buffer, staging_east/north/south/west).
--                              In the run: 522 bookings, 116 vehicles, 170 done,
--                              2 superseded, ZERO space conflicts, zero residue.
--
--   saturation -> stage ...... twin.staging_overflow, 20 events, carrying the
--                              caps it was measured against (svc 2, wash 3).
--                              This is "everything is booked, hold them" and it
--                              works.
--
--   patience + escalation .... a 10-minute patience clock, 43 escalations, 14
--                              gate holds, in twin.ottoq_sim_advance_service_flow
--                              which deliberately leaves last_state_change
--                              untouched so queue order and the patience metric
--                              survive the hold.
--
--   the waiting vocabulary ... vehicle_state already carries exactly the spec's
--                              shape: arrived_at_gate, staged_awaiting_service,
--                              charge_complete_holding, service_complete_holding,
--                              staged_for_departure, emergency_staged,
--                              tow_requested, out_of_service.
--                              Live right now: staged_awaiting_service 18,
--                              staged_for_departure 10, emergency_staged 3,
--                              tow_requested 4.
--
--   machinery that already exists by name: ottoq_place_unplaced_vehicles,
--   ottoq_depot_queue, ottoq_vehicle_queue_position, ottoq_release_vacated_spaces,
--   ottoq_stage_advance_approval, ottoq_admit_stranded_vehicles,
--   ottoq_eval_sla_002_max_queue_depth, ottoq_book_hold_stall.
--
-- ── THE THREE REAL GAPS ────────────────────────────────────────────────────
--
-- GAP 1 — THERE IS NOWHERE TO ESCALATE TO. The spec's long-term / perimeter
-- holding area is DECLARED IN THE TYPE SYSTEM AND HAS ZERO INSTANCES:
--
--   stall_type enum ...... dcfc, l2, wash_bay, detail_bay, service_bay,
--                          staging, parking, safety
--   stalls of type parking .......... 0      (in the whole database)
--   stalls of type safety ........... 0
--   stalls of type detail_bay ....... 0
--   stalls of type staging ........ 232
--   functions mentioning 'parking' .. 1
--   functions mentioning 'safety' ... 4
--
-- So escalation decides, 43 times, and has one undifferentiated staging pool to
-- put the vehicle in. A flagged vehicle and a vehicle waiting five minutes for a
-- charger occupy the same class of space. That is the gap, and it is a DATA gap
-- plus a routing gap, not a missing concept -- the vocabulary is already there.
--
-- GAP 2 — THE ENGINE DOES NOT KNOW WHICH STALLS ARE BOOKED. Measured on the run
-- (db/checks/0247): of 347 stall-bearing commands, 116 were dispatched at an
-- ALREADY OCCUPIED target and refused by preflight -- 33%. 107 of the 119 space
-- conflicts are l2, 9 are dcfc, ZERO are staging. Nothing double-occupied; the
-- net held every time. But the spec says do not send them there, and the engine
-- sends them there a third of the time. Already tracked as G56 (task #120) and
-- G57 (task #121); this run is live evidence for both.
--
-- GAP 3 — THE `stage` COMMAND CARRIES NO STALL, SO IT CANNOT BE CHECKED. 115 of
-- 118 stage commands in the run carry no stall_id, and the executor's occupancy
-- gate keys on the payload carrying one. The command that implements the spec's
-- most-used path is the one command that is never validated (0247).
--
-- ── WHAT IS NOT YET MEASURED, AND MUST BE BEFORE ANY CLAIM ─────────────────
--   * the release -> notify -> proceed loop: ottoq_release_vacated_spaces and
--     ottoq_stage_advance_approval both exist; whether a freed stall actually
--     produces a command to a specific waiting vehicle, and how fast, is NOT
--     established here.
--   * queue integrity: whether every vehicle that entered
--     staged_awaiting_service later received an assignment, and the wait
--     distribution. ottoq_vehicle_queue_position exists; its coverage is
--     unmeasured.
--   * the scarcity case the spec cares most about -- a depot with DCFC and no
--     L2 -- has not been run. Flagship has 30 l2 and 10 dcfc, so it never
--     exercises the regime where staging dominates.
-- ============================================================================

-- 1. The spec's holding classes: declared vs instantiated.
SELECT unnest(enum_range(NULL::stall_type))::text AS declared_stall_type,
       (SELECT count(*) FROM public.stalls s
         WHERE s.stall_type::text = unnest(enum_range(NULL::stall_type))::text) AS stalls_that_exist;

-- 2. Saturation, patience and escalation as actually recorded.
SELECT count(*) AS overflow_events,
       max((payload->>'overflow')::int)  AS max_vehicles_held,
       sum((payload->>'escalated')::int) AS escalated,
       sum((payload->>'gate_held')::int) AS gate_held,
       min((payload->>'patience_min')::numeric) AS patience_min,
       min((payload->>'svc_cap')::int)   AS svc_cap,
       min((payload->>'wash_cap')::int)  AS wash_cap
  FROM public.ottoq_events
 WHERE sim_run_id='34ffb2d9-bcc6-4232-bbfc-d2c4d51e4ec5'
   AND event_type='twin.staging_overflow';

-- 3. The waiting vocabulary, and whether the engine ever reaches each state.
SELECT unnest(enum_range(NULL::vehicle_state))::text AS state,
       (SELECT count(*) FROM public.vehicles v
         WHERE v.current_state::text = unnest(enum_range(NULL::vehicle_state))::text) AS vehicles_now;

-- 4. GAP 2 restated as one number: how often the engine aimed at a taken stall.
SELECT count(*) FILTER (WHERE payload ? 'stall_id')                       AS stall_bearing_commands,
       count(*) FILTER (WHERE reason_code = 'target_occupied')            AS aimed_at_an_occupied_stall,
       round(100.0 * count(*) FILTER (WHERE reason_code='target_occupied')
             / NULLIF(count(*) FILTER (WHERE payload ? 'stall_id'),0), 1) AS pct
  FROM public.ottoq_vehicle_commands
 WHERE sim_run_id='34ffb2d9-bcc6-4232-bbfc-d2c4d51e4ec5';
