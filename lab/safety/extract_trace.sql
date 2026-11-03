-- lab/safety/extract_trace.sql -- the post-cell event traces the E3 v0 monitor reads (lab/safety/monitor.py).
--
-- READ-ONLY. Two SELECT statements, nothing else: no INSERT/UPDATE/DELETE/DDL, no function that writes.
-- Run against otto-q-core (gxdrcyphqjzjsuhxuqtg). The run's rows are engine-class (ottoq_run_scope_registry): the next
-- demo run's start purges them, so this file reproduces the fixtures only while run 8c0b2e04 is the latest run.
--
-- Run 8c0b2e04-8ea9-49a8-bfed-bed10ddfbc8b: busy_day at the twin depot 11111111-1111-1111-1111-111111111111 (rule 8),
-- started 2026-11-03 03:37:10 UTC, 129 ticks, sim 14:02:30 to 14:29:59 (sim times are stored as UTC timestamps on the
-- sim clock; they are never compared with now()). The posts are every stall with a session that ended 'faulted' on the
-- run: NASH-DCFC-STALL-02, -11, -13, -18, -22, -29 (db/checks/0474 §1).
--
-- Statement 1: one row per (post, event). Statement 2: the run's tick clock. The fixtures under
-- fixtures/8c0b2e04/ are these two results as CSV, one file per post plus ticks.csv, with the md5 of each file's text
-- computed here and checked against the file on disk (see README.md, "Reproduce the fixtures").
--
-- Events (the monitor's vocabulary; every id is a full UUID, because twin vehicle ids share 8-character prefixes):
--   car_arrived        vehicles.current_stall_id set to the post          vehicle.state_changed diff
--   car_left           vehicles.current_stall_id moved off the post       vehicle.state_changed diff (to=... in detail)
--   mate_started       the charge arm starts a mate on the post           arm.mate_started (window_s, session)
--   mate_latched       the connector latched                              arm.mate_latched
--   session_started    a charge session opens on the post's charger       charge.session_started (soc_start, soc_target)
--   session_completed  the session reached its end normally               charge.session_completed (soc_end)
--   charger_faulted    the post's charger faulted the session             charge.session_faulted (reason, repair_minutes)
--   demate_started     the demate tether starts (phase unlatch)           arm.demate_started (window_s)
--   emergency_release  the stop path's re-queue branch lets the car go    arm.emergency_release
--   demate_cleared     the charge arm reports clear (phase clear)         arm.demate_cleared
--   clean_started      the post's cleaning arm starts its cycle           ottoq_visit_needs.atoms, performed_by
--   clean_done         ...and its cycle is credited done                  'stall_cabin_robot', robot_stall_id = post
--   clean_cancelled    ...or cancelled (atom interrupted[] on this post)  (0758, 0764, 0767)
--   session_ended_*    a session that ended with no charge.session_* event (here: cancelled when the run stopped)
--   run_stopped        the end of the observation                         twin.sim_stopped_and_reset
-- Within one sim instant rows are ordered by the step that writes them (the charge ends, the arm demates, the arm
-- clears, the cleaning arm's step, the sweep releases, a car arrives, a mate starts), then by ottoq_events.event_seq.

-- ── Statement 1: the events of every faulted post ─────────────────────────────────────────────────────────────────────
WITH r AS (SELECT '8c0b2e04-8ea9-49a8-bfed-bed10ddfbc8b'::uuid AS run),
posts AS (
  SELECT DISTINCT s.id AS stall_id, s.stall_code
    FROM public.ocpp_sessions os JOIN public.stalls s ON s.id = os.stall_id, r
   WHERE os.sim_run_id = r.run AND os.status = 'faulted'
),
ev AS (SELECT e.* FROM public.ottoq_events e, r WHERE e.sim_run_id = r.run),
atoms AS (
  SELECT vn.visit_id, vn.vehicle_id, a
    FROM public.ottoq_visit_needs vn, r,
         LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(vn.atoms) = 'array' THEN vn.atoms ELSE '[]'::jsonb END) a
   WHERE vn.sim_run_id = r.run AND a->>'performed_by' = 'stall_cabin_robot'
),
rows AS (
  SELECT p.stall_code, e.sim_clock_at AS t, 60 AS rk, e.event_seq AS q, 'car_arrived' AS event, e.entity_id AS vehicle_id,
         '' AS detail, 'ottoq_events#' || e.event_seq AS source
    FROM ev e JOIN posts p ON (e.payload->'diff'->'current_stall_id'->>'to') = p.stall_id::text
   WHERE e.event_type = 'vehicle.state_changed' AND e.entity_type = 'vehicle'
  UNION ALL
  SELECT p.stall_code, e.sim_clock_at, 50, e.event_seq, 'car_left', e.entity_id,
         'to=' || COALESCE(e.payload->'diff'->'current_stall_id'->>'to', 'none'), 'ottoq_events#' || e.event_seq
    FROM ev e JOIN posts p ON (e.payload->'diff'->'current_stall_id'->>'from') = p.stall_id::text
   WHERE e.event_type = 'vehicle.state_changed' AND e.entity_type = 'vehicle'
     AND (e.payload->'diff'->'current_stall_id'->>'to') IS DISTINCT FROM p.stall_id::text
  UNION ALL
  SELECT p.stall_code, e.sim_clock_at,
         CASE e.event_type WHEN 'arm.demate_started' THEN 20 WHEN 'arm.emergency_release' THEN 20
                           WHEN 'arm.demate_cleared' THEN 30 WHEN 'arm.mate_started' THEN 70 ELSE 80 END,
         e.event_seq,
         CASE e.event_type WHEN 'arm.mate_started' THEN 'mate_started' WHEN 'arm.mate_latched' THEN 'mate_latched'
                           WHEN 'arm.demate_started' THEN 'demate_started' WHEN 'arm.demate_cleared' THEN 'demate_cleared'
                           ELSE 'emergency_release' END,
         e.entity_id,
         concat_ws(';',
           CASE WHEN e.payload ? 'window_s' THEN 'window_s=' || (e.payload->>'window_s') END,
           CASE WHEN e.payload ? 'outcome' THEN 'outcome=' || (e.payload->>'outcome') END,
           CASE WHEN e.payload ? 'tether_phase' THEN 'tether_phase=' || (e.payload->>'tether_phase') END,
           CASE WHEN e.payload ? 'session_id' THEN 'session=' || (e.payload->>'session_id') END),
         'ottoq_events#' || e.event_seq
    FROM ev e JOIN posts p ON (e.payload->>'stall_id') = p.stall_id::text
   WHERE e.event_type IN ('arm.mate_started', 'arm.mate_latched', 'arm.demate_started', 'arm.demate_cleared',
                          'arm.emergency_release')
  UNION ALL
  SELECT p.stall_code, e.sim_clock_at,
         CASE e.event_type WHEN 'charge.session_started' THEN 71 ELSE 10 END,
         e.event_seq,
         CASE e.event_type WHEN 'charge.session_started' THEN 'session_started'
                           WHEN 'charge.session_completed' THEN 'session_completed' ELSE 'charger_faulted' END,
         os.vehicle_id,
         concat_ws(';',
           CASE WHEN e.payload ? 'reason' THEN 'reason=' || (e.payload->>'reason') END,
           CASE WHEN e.payload ? 'repair_minutes' THEN 'repair_minutes=' || (e.payload->>'repair_minutes') END,
           CASE WHEN e.payload ? 'soc_start' THEN 'soc_start=' || (e.payload->>'soc_start') END,
           CASE WHEN e.payload ? 'soc_target' THEN 'soc_target=' || (e.payload->>'soc_target') END,
           CASE WHEN e.payload ? 'soc_end' THEN 'soc_end=' || (e.payload->>'soc_end') END,
           'session=' || os.id),
         'ottoq_events#' || e.event_seq
    FROM ev e JOIN public.ocpp_sessions os ON os.id = e.entity_id JOIN posts p ON p.stall_id = os.stall_id
   WHERE e.event_type IN ('charge.session_started', 'charge.session_completed', 'charge.session_faulted')
  UNION ALL
  SELECT p.stall_code, os.ended_at, 90, NULL::bigint, 'session_ended_' || os.status::text, os.vehicle_id,
         concat_ws(';', 'reason=' || COALESCE(os.stopped_reason, ''), 'session=' || os.id), 'ocpp_sessions#' || os.id
    FROM public.ocpp_sessions os JOIN posts p ON p.stall_id = os.stall_id, r
   WHERE os.sim_run_id = r.run AND os.status::text NOT IN ('completed', 'faulted') AND os.ended_at IS NOT NULL
  UNION
  -- a clean's start: the atom's own start on its post, and every start an interruption recorded on another post
  SELECT p.stall_code, (x.a->>'started_at')::timestamptz, 85, NULL::bigint, 'clean_started', x.vehicle_id,
         concat_ws(';', 'svc=' || (x.a->>'svc'), 'arm_routine=' || COALESCE(x.a->>'arm_routine', 'false')),
         'ottoq_visit_needs#' || x.visit_id
    FROM atoms x JOIN posts p ON (x.a->>'robot_stall_id') = p.stall_id::text
   WHERE x.a ? 'started_at'
  UNION
  SELECT p.stall_code, (i->>'started_at')::timestamptz, 85, NULL::bigint, 'clean_started', x.vehicle_id,
         concat_ws(';', 'svc=' || (x.a->>'svc'), 'arm_routine=' || COALESCE(x.a->>'arm_routine', 'false')),
         'ottoq_visit_needs#' || x.visit_id
    FROM atoms x, LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(x.a->'interrupted') = 'array'
                                                    THEN x.a->'interrupted' ELSE '[]'::jsonb END) i
    JOIN posts p ON (i->>'stall_id') = p.stall_id::text
   WHERE i ? 'started_at'
  UNION ALL
  SELECT p.stall_code, (x.a->>'done_at')::timestamptz, 40, NULL::bigint, 'clean_done', x.vehicle_id,
         'svc=' || (x.a->>'svc'), 'ottoq_visit_needs#' || x.visit_id
    FROM atoms x JOIN posts p ON (x.a->>'robot_stall_id') = p.stall_id::text
   WHERE x.a->>'status' = 'done' AND x.a ? 'done_at'
  UNION ALL
  SELECT p.stall_code, (i->>'at')::timestamptz, 40, NULL::bigint, 'clean_cancelled', x.vehicle_id,
         concat_ws(';', 'svc=' || (x.a->>'svc'), 'reason=' || COALESCE(i->>'reason', '')),
         'ottoq_visit_needs#' || x.visit_id
    FROM atoms x, LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(x.a->'interrupted') = 'array'
                                                    THEN x.a->'interrupted' ELSE '[]'::jsonb END) i
    JOIN posts p ON (i->>'stall_id') = p.stall_id::text
  UNION ALL
  SELECT p.stall_code, e.sim_clock_at, 99, e.event_seq, 'run_stopped', NULL::uuid, '', 'ottoq_events#' || e.event_seq
    FROM ev e CROSS JOIN posts p
   WHERE e.event_type = 'twin.sim_stopped_and_reset'
)
SELECT stall_code AS post,
       row_number() OVER (PARTITION BY stall_code ORDER BY t, rk, q NULLS LAST, event, vehicle_id) AS seq,
       to_char(t AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS sim_time,
       event, COALESCE(vehicle_id::text, '') AS vehicle_id, detail, source
  FROM rows
 ORDER BY post, seq;

-- ── Statement 2: the run's tick clock (one twin.weather_tick per tick; 129 on this run, the same instants as
--    twin.bess_dispatch). public.ottoq_release_expired_tethers runs once per tick. ─────────────────────────────────────
SELECT row_number() OVER (ORDER BY e.sim_clock_at) AS tick,
       to_char(e.sim_clock_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS sim_time,
       'ottoq_events#' || e.event_seq AS source
  FROM public.ottoq_events e
 WHERE e.sim_run_id = '8c0b2e04-8ea9-49a8-bfed-bed10ddfbc8b' AND e.event_type = 'twin.weather_tick'
 ORDER BY e.sim_clock_at;
