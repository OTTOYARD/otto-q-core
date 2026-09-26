-- migration-version: 20260925200000
-- migration-name:    the_cockpits_could_not_read_the_card_they_were_built_on_and_it_never_said_where_a_vehicle_was_booked
--
-- 0460  **The two cockpits could not read the card they were built on, and the card never said where a vehicle
--       was booked or what OTTO-Q last decided for it.**
--
--       `ottoq_depot_cards(depot_id, fleet_operator_id)` is the one read contract both cockpits are meant to project
--       (ottoyard-field-ops/AGENTS.md, ottoyard-OTTO-Q/AGENTS.md: "one read contract, three projections").
--
-- ══ §1 MEASURED 2026-09-25 ════════════════════════════════════════════════════════════════════════════════════
--
--   - `has_function_privilege('anon', 'public.ottoq_depot_cards(uuid,uuid)', 'execute')` = false.
--     OTTO-PULSE calls it with the anon key (src/hooks/use-ottoq-cards.ts) and PostgREST answers
--     `401 42501 permission denied for function ottoq_depot_cards`. The vehicle work-order cards have shown
--     nothing since. Every other twin read the cockpits use (ottoq_activity_feed, ottoq_twin_appointments,
--     ottoq_twin_fleet_condition, ottoq_twin_events_window, ottoq_nl_status_brief) is already anon-executable,
--     and all of them, like this one, are read-only SECURITY DEFINER functions over the same run tables.
--   - The card carried state, SoC, needs and itinerary steps, but not:
--       * the stall the vehicle is in (vehicles.current_stall_id is populated; the card dropped it),
--       * its reservations (`ottoq_stall_bookings` held/active rows: purpose, stall, window, why),
--       * the last thing OTTO-Q decided for it (`ottoq_decisions`, entity_type = 'vehicle').
--     So a cockpit that wanted "vehicle -> reservation -> decision" had to invent a second read path, which is
--     exactly what the contract exists to prevent.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) Same signature, same return type, body only (no new overload: see the 0076 lesson). contract_version 1.1.
--       Every 1.0 key is kept byte-for-byte in meaning; the new keys are additive.
--   (2) Per vehicle, new keys:
--         `stall`         {id, code, kind}  from vehicles.current_stall_id -> stalls. NULL when not in a stall.
--         `reservations`  held + active bookings of THIS run for the vehicle, ordered by window start:
--                         {booking_id, purpose, state, stall_code, stall_kind, starts_at, ends_at, why, need_atom,
--                          booked_by}.
--         `last_decision` newest ottoq_decisions row of THIS run with entity_id = vehicle:
--                         {at, action, verb, outcome, engine, rationale}. verb and rationale read enacted first,
--                         then proposed, the same precedence ottoq_activity_feed uses.
--       All three are NULL / [] when no run is live, exactly like `card`.
--   (3) Top level, new key (the depot-wide reservation board is the union of the per-vehicle lists; it is not
--       published twice, which would double a ~150 KB payload the cockpits poll every 5 s):
--         `reservation_ledger` count of this run's bookings by state (done / released / superseded /
--                              interrupted / held / active), operator-filtered. Reported side by side on purpose:
--                              AGENTS.md "report done / interrupted / legacy side by side".
--   (4) GRANT EXECUTE to anon, authenticated. Read-only, STABLE, returns no credential or PII beyond what the
--       already-granted snapshot and activity feed return. The operator filter stays a client-side choice; the
--       tenancy gap is unchanged and recorded in ottoyard-OTTO-Q/AGENTS.md ("spoofable ... known security gate").
--
--   Unchanged: run selection (running/paused run on the depot, newest first), the vehicle scope
--   (current_depot_id), the needs/steps/current_step/next_step card and its honesty rules.
--
-- ══ §3 forces_recert FALSE ═══════════════════════════════════════════════════════════════════════════════════
--   Read path only. No decide, tick, enact or world function reads ottoq_depot_cards.

BEGIN;
SET LOCAL lock_timeout = '8s';

CREATE OR REPLACE FUNCTION public.ottoq_depot_cards(p_depot_id uuid, p_fleet_operator_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
WITH run AS (
  SELECT sim_run_id, sim_clock_current, status AS run_status
  FROM ottoq_sim_runs
  WHERE depot_id = p_depot_id
    AND status IN ('running','paused')
  ORDER BY started_at DESC
  LIMIT 1
),
veh AS (
  SELECT v.id, v.display_name, v.make, v.model,
         v.fleet_operator_id, f.name AS operator_name,
         v.current_state::text AS state, v.current_soc, v.target_soc,
         v.current_stall_id
  FROM vehicles v
  LEFT JOIN fleet_operators f ON f.id = v.fleet_operator_id
  WHERE v.current_depot_id = p_depot_id
    AND (p_fleet_operator_id IS NULL OR v.fleet_operator_id = p_fleet_operator_id)
),
card AS (
  SELECT vh.id AS vehicle_id,
         (SELECT to_jsonb(n) - 'meta'
            FROM ottoq_visit_needs n
           WHERE n.vehicle_id = vh.id AND n.sim_run_id = r.sim_run_id
           ORDER BY n.created_at DESC LIMIT 1)               AS need,
         (SELECT i.itinerary_id
            FROM ottoq_vehicle_itineraries i
           WHERE i.vehicle_id = vh.id AND i.sim_run_id = r.sim_run_id
             AND i.status = 'active'
           ORDER BY i.sim_created_at DESC LIMIT 1)           AS itinerary_id
  FROM veh vh CROSS JOIN run r
),
seq AS (
  SELECT c.vehicle_id,
         jsonb_agg(s.step ORDER BY s.ord) AS steps
  FROM card c
  CROSS JOIN LATERAL (
    (SELECT l.seq AS ord, jsonb_build_object(
        'seq', l.seq, 'leg_type', l.leg_type, 'status', 'done',
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim,
        'actual_start', l.actual_start_sim,  'actual_end', l.actual_end_sim) AS step
       FROM ottoq_itinerary_legs l
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'done'
      ORDER BY l.seq DESC LIMIT 3)
    UNION ALL
    (SELECT l.seq, jsonb_build_object(
        'seq', l.seq, 'leg_type', l.leg_type, 'status', 'current',
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim,
        'actual_start', l.actual_start_sim,
        'progress_pct', LEAST(100, GREATEST(0, round(
           100.0 * EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.actual_start_sim))
                 / NULLIF(l.planned_duration_s,0)))))
       FROM ottoq_itinerary_legs l
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'active'
      ORDER BY l.seq LIMIT 1)
    UNION ALL
    (SELECT l.seq, jsonb_build_object(
        'seq', l.seq, 'leg_type', l.leg_type, 'status', 'upcoming',
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim)
       FROM ottoq_itinerary_legs l
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'planned'
      ORDER BY l.seq LIMIT 5)
  ) s(ord, step)
  WHERE c.itinerary_id IS NOT NULL
  GROUP BY c.vehicle_id
),
--: 0460 — reservations of THIS run, for the vehicles in scope.
bk AS (
  SELECT b.booking_id, b.vehicle_id, b.purpose, b.state,
         lower(b.during) AS starts_at, upper(b.during) AS ends_at,
         b.why, b.need_atom, b.booked_by,
         st.stall_code, st.stall_kind::text AS stall_kind
    FROM ottoq_stall_bookings b
    JOIN run r ON r.sim_run_id = b.sim_run_id
    JOIN veh vh ON vh.id = b.vehicle_id
    LEFT JOIN stalls st ON st.id = b.stall_id
   WHERE b.state IN ('held','active')
),
bk_json AS (
  SELECT bk.vehicle_id,
         jsonb_agg(jsonb_build_object(
           'booking_id', bk.booking_id, 'purpose', bk.purpose, 'state', bk.state,
           'stall_code', bk.stall_code, 'stall_kind', bk.stall_kind,
           'starts_at', bk.starts_at, 'ends_at', bk.ends_at,
           'why', bk.why, 'need_atom', bk.need_atom, 'booked_by', bk.booked_by)
           ORDER BY bk.starts_at NULLS LAST) AS items
    FROM bk GROUP BY bk.vehicle_id
),
--: 0460 — the newest decision of THIS run per vehicle in scope.
dec AS (
  SELECT DISTINCT ON (d.entity_id)
         d.entity_id AS vehicle_id,
         jsonb_build_object(
           'at',        d.sim_clock,
           'action',    COALESCE(d.resolved_action_context, d.action_context),
           'verb',      COALESCE(d.enacted_action->>'verb', d.proposed_action->>'verb'),
           'outcome',   d.outcome_status,
           'engine',    d.l2_engine,
           'rationale', COALESCE(d.enacted_action->'rationale', d.proposed_action->'rationale')) AS last_decision
    FROM ottoq_decisions d
    JOIN run r ON r.sim_run_id = d.sim_run_id
   WHERE d.entity_type = 'vehicle'
     AND d.entity_id IN (SELECT id FROM veh)
   ORDER BY d.entity_id, d.decision_seq DESC
)
SELECT jsonb_build_object(
  'endpoint', 'ottoq.depot_cards',
  'contract_version', '1.1',
  'depot_id', p_depot_id,
  'fleet_operator_id', p_fleet_operator_id,
  'sim_run_id', (SELECT sim_run_id FROM run),
  'run_status', (SELECT run_status FROM run),
  'sim_clock',  (SELECT sim_clock_current FROM run),
  'vehicles', COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
       'vehicle_id', vh.id,
       'display_name', vh.display_name,
       'oem', vh.make, 'model', vh.model,
       'operator', jsonb_build_object('id', vh.fleet_operator_id, 'name', vh.operator_name),
       'state', vh.state, 'soc', vh.current_soc, 'target_soc', vh.target_soc,
       'stall', CASE WHEN vh.current_stall_id IS NULL THEN NULL ELSE (
          SELECT jsonb_build_object('id', st.id, 'code', st.stall_code, 'kind', st.stall_kind::text)
            FROM stalls st WHERE st.id = vh.current_stall_id) END,
       'reservations', CASE WHEN (SELECT sim_run_id FROM run) IS NULL THEN '[]'::jsonb
                            ELSE COALESCE(bj.items, '[]'::jsonb) END,
       'last_decision', dc.last_decision,
       'card', CASE WHEN (SELECT sim_run_id FROM run) IS NULL THEN NULL ELSE jsonb_build_object(
          'urgency',         c.need->>'urgency',
          'dispatch_due_at', c.need->>'dispatch_due_at',
          'needs',           COALESCE((
                               SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                                 'svc', a->>'svc', 'status', a->>'status',
                                 'done_at', a->>'done_at', 'must_do', (a->>'must_do')::boolean)))
                               FROM jsonb_array_elements(c.need->'atoms') a), '[]'::jsonb),
          'steps',           COALESCE(s.steps,'[]'::jsonb),
          'current_step',    (SELECT st FROM jsonb_array_elements(COALESCE(s.steps,'[]'::jsonb)) st
                               WHERE st->>'status'='current' LIMIT 1),
          'next_step',       (SELECT st FROM jsonb_array_elements(COALESCE(s.steps,'[]'::jsonb)) st
                               WHERE st->>'status'='upcoming' LIMIT 1)
       ) END
     ) ORDER BY vh.display_name)
     FROM veh vh
     LEFT JOIN card c     ON c.vehicle_id  = vh.id
     LEFT JOIN seq  s     ON s.vehicle_id  = vh.id
     LEFT JOIN bk_json bj ON bj.vehicle_id = vh.id
     LEFT JOIN dec  dc    ON dc.vehicle_id = vh.id
  ), '[]'::jsonb),
  'reservation_ledger', COALESCE((
     SELECT jsonb_object_agg(x.state, x.n) FROM (
       SELECT b.state, count(*) AS n
         FROM ottoq_stall_bookings b
         JOIN run r ON r.sim_run_id = b.sim_run_id
         JOIN veh vh ON vh.id = b.vehicle_id
        GROUP BY b.state) x
  ), '{}'::jsonb)
);
$function$;

GRANT EXECUTE ON FUNCTION public.ottoq_depot_cards(uuid, uuid) TO anon, authenticated;

COMMIT;

-- ══ VERIFY (read-only, run after apply) ══════════════════════════════════════════════════════════════════════
--   select count(*) = 1 from pg_proc where proname = 'ottoq_depot_cards';                          -- one overload
--   select prosrc ilike '%0460%' from pg_proc where proname = 'ottoq_depot_cards';                 -- this body
--   select has_function_privilege('anon','public.ottoq_depot_cards(uuid,uuid)','execute');        -- true
--   select ottoq_depot_cards('11111111-1111-1111-1111-111111111111')->>'contract_version';        -- '1.1'
--   During a live run: the sum over vehicles of jsonb_array_length(->'reservations') equals
--   (select count(*) from ottoq_stall_bookings where sim_run_id = <run> and state in ('held','active')
--      and vehicle_id in (select id from vehicles where current_depot_id = <depot>)).
