-- migration-version: 20260926045441
-- migration-name:    the_run_list_counted_no_charge_sessions_for_any_run_and_printed_its_row_cap_as_a_count
--
-- 0466  **The run list counted no charge sessions for any run, and printed its own row cap as a count.**
--       `db/checks/0357` §7. FINDINGS G198.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_twin_run_list(25)` on 2026-09-26 at 04:50 UTC, behind the twin cockpit's Runs tab and its Compare
--   view (via otto-twin-control `/sim_runs`):
--     - `charge_sessions` = 0 for every run, including 317d4331, which had 104 sessions in `ocpp_sessions`.
--     - `events_total` = 1500 for every run: the scan's own LIMIT. 317d4331 had 22,460. `telemetry_packets` = 1500
--       where it had 13,686. `faults` counted fault-like event types among only the newest 1,500 events.
--     - `faults` matched `%anomaly%`, so it counted `twin.weather_anomaly`, a per-tick weather summary: on 317d4331
--       454 of the 470 fault-like events were weather, and the run's actual faults were 16 (15
--       `charge.session_faulted`, 1 `twin.grid_frequency_excursion`).
--     - The 11th and older runs carry `counters: null`, and the Runs tab read a field of it on every render
--       (fixed in the cockpit, ottoyarddepot-sim#110). Stop lands the operator on that tab.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `charge_sessions` was `ocpp_sessions WHERE depot_id = run's depot AND started_at >= sim_runs.started_at`:
--   the session's `started_at` is SIM time and the run's is REAL time, so a run started at 04:14 UTC on 09-26 looked
--   for sessions after a moment its own sim day (09-25) never reaches. 0326 §1's defect: a gate compared against the
--   wrong clock answers the same thing every time. The other counters were each `count(*) FROM (... LIMIT 1500)`,
--   a cost guard written when these tables were far larger, and it reported the cap as the count.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Same signature, keys, and newest-ten rule. Every counter is run-scoped (`sim_run_id`, one clock domain) and
--   exact up to 200,000 rows; a counter that reaches that guard is listed in a new key `counters_capped`, so a cap can
--   never again read as a count. Measured on 317d4331: events 23 ms, telemetry 4 ms, sessions and dispatches ~1 ms.
--   `faults` counts the same fault-like event types over the run's own events rather than the newest 1,500, and
--   no longer counts weather.
--
-- ══ §4 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   A reporting function. No tick path calls it and no atom reads it (callers: the otto-twin-control edge function).

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0466 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file replaces, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_twin_run_list(integer)'::regprocedure)) <> 'fb8378f451e5d93b083f6b3b6c5bc933' THEN
    RAISE EXCEPTION '0466 P2: public.ottoq_twin_run_list is not the body this file replaces';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0466_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_twin_run_list(integer)'::regprocedure;

CREATE OR REPLACE FUNCTION public.ottoq_twin_run_list(p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET statement_timeout TO '8s'
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_out JSONB;
  -- 0466 (G198): a cost guard, not a count. A counter that reaches it is listed in counters_capped.
  c_guard CONSTANT int := 200000;
BEGIN
  SELECT COALESCE(jsonb_agg(r ORDER BY rn), '[]'::jsonb) INTO v_out
  FROM (
    SELECT sr.rn, jsonb_build_object(
      'sim_run_id',        sr.sim_run_id,
      'scenario',          sr.scenario_code,
      'status',            sr.status,
      'started_at',        sr.started_at,
      'ended_at',          sr.ended_at,
      'sim_clock_start',   sr.sim_clock_start,
      'sim_clock_current', sr.sim_clock_current,
      'tick_count',        sr.tick_count,
      'time_scale',        sr.time_scale,
      'seed',              sr.random_seed,
      'sim_minutes', GREATEST(0, ROUND(
        EXTRACT(EPOCH FROM (sr.sim_clock_current - sr.sim_clock_start)) / 60.0
      ))::int,
      -- counters only for the 10 NEWEST runs; every one run-scoped and exact up to c_guard (0466)
      'counters', CASE WHEN sr.rn <= 10 THEN jsonb_build_object(
        'dispatches_total',  k.dispatches_total,
        'dispatches_active', k.dispatches_active,
        'telemetry_packets', k.telemetry_packets,
        'events_total',      k.events_total,
        'incidents_open',    k.incidents_open,
        'incidents_total',   k.incidents_total,
        'faults',            k.faults,
        'charge_sessions',   k.charge_sessions
      ) ELSE NULL END,
      'counters_capped', CASE WHEN sr.rn <= 10 THEN to_jsonb(ARRAY(
        SELECT x.key FROM (VALUES ('dispatches_total', k.dispatches_total), ('telemetry_packets', k.telemetry_packets),
                                  ('events_total', k.events_total), ('incidents_total', k.incidents_total),
                                  ('faults', k.faults), ('charge_sessions', k.charge_sessions)) x(key, n)
         WHERE x.n >= c_guard ORDER BY x.key)) ELSE NULL END,
      'variability', (
        SELECT jsonb_build_object(
          'spread_mult', COALESCE((vp.knobs #>> '{_global,spread_mult}')::numeric, 1),
          'rate_mult',   COALESCE((vp.knobs #>> '{_global,rate_mult}')::numeric, 1),
          'tuned_knobs', (
            SELECT COUNT(*) FROM jsonb_object_keys(vp.knobs) AS keys(key)
             WHERE keys.key NOT LIKE '\_%'
          ),
          'notes', vp.notes
        )
        FROM ottoq_variability_profiles vp WHERE vp.sim_run_id = sr.sim_run_id
      )
    ) AS r
    FROM (
      SELECT sr0.*, row_number() OVER (ORDER BY sr0.started_at DESC NULLS LAST, sr0.sim_run_id) AS rn
      FROM ottoq_sim_runs sr0
      ORDER BY sr0.started_at DESC NULLS LAST, sr0.sim_run_id
      LIMIT GREATEST(1, LEAST(50, p_limit))
    ) sr
    LEFT JOIN LATERAL (
      SELECT
        (SELECT count(*) FROM (SELECT 1 FROM ottoq_vehicle_dispatches d WHERE d.sim_run_id = sr.sim_run_id LIMIT c_guard) q)::int AS dispatches_total,
        (SELECT count(*) FROM ottoq_vehicle_dispatches d WHERE d.sim_run_id = sr.sim_run_id AND d.status IN ('active','returning'))::int AS dispatches_active,
        (SELECT count(*) FROM (SELECT 1 FROM ottoq_telemetry_packets t WHERE t.sim_run_id = sr.sim_run_id LIMIT c_guard) q)::int AS telemetry_packets,
        (SELECT count(*) FROM (SELECT 1 FROM ottoq_events e WHERE e.sim_run_id = sr.sim_run_id LIMIT c_guard) q)::int AS events_total,
        (SELECT count(*) FROM ottoq_vehicle_incidents i WHERE i.sim_run_id = sr.sim_run_id AND i.resolution_status = 'open')::int AS incidents_open,
        (SELECT count(*) FROM (SELECT 1 FROM ottoq_vehicle_incidents i WHERE i.sim_run_id = sr.sim_run_id LIMIT c_guard) q)::int AS incidents_total,
        (SELECT count(*) FROM (SELECT 1 FROM ottoq_events e WHERE e.sim_run_id = sr.sim_run_id
                                AND (e.event_type LIKE '%fault%' OR e.event_type LIKE '%brownout%'
                                  OR e.event_type LIKE '%anomaly%' OR e.event_type LIKE '%incident%'
                                  OR e.event_type LIKE '%voltage%' OR e.event_type LIKE '%frequency%')
                                -- 0466 (G198): weather is not a fault. twin.weather_anomaly is a per-tick
                                -- weather summary and was 454 of 470 "faults" on 317d4331.
                                AND e.event_type NOT LIKE '%weather%'
                              LIMIT c_guard) q)::int AS faults,
        -- 0466 (G198): run-scoped. This compared a session's SIM start with the run's REAL start and read 0.
        (SELECT count(*) FROM (SELECT 1 FROM ocpp_sessions cs WHERE cs.sim_run_id = sr.sim_run_id LIMIT c_guard) q)::int AS charge_sessions
       WHERE sr.rn <= 10
    ) k ON true
  ) sub;

  RETURN v_out;
END;
$function$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_def text := pg_get_functiondef('public.ottoq_twin_run_list(integer)'::regprocedure);
        v_list jsonb; v_row jsonb; v_run uuid; v_sessions int; v_events int;
BEGIN
  -- V1: no 1,500-row cap, no real-time comparison for sessions.
  IF position('LIMIT 1500' IN v_def) > 0 OR position('cs.started_at >= sr.started_at' IN v_def) > 0
     OR position('0466 (G198)' IN v_def) = 0 THEN
    RAISE EXCEPTION '0466 V1: the run list is not the body this file writes';
  END IF;
  -- V2: on the newest run that has sessions, the counters equal direct counts.
  SELECT os.sim_run_id INTO v_run FROM ocpp_sessions os
    JOIN ottoq_sim_runs r ON r.sim_run_id = os.sim_run_id
   ORDER BY r.started_at DESC NULLS LAST LIMIT 1;
  v_list := public.ottoq_twin_run_list(50);
  SELECT e INTO v_row FROM jsonb_array_elements(v_list) e WHERE e->>'sim_run_id' = v_run::text;
  IF v_row IS NOT NULL AND v_row->'counters' IS NOT NULL AND v_row->'counters' <> 'null'::jsonb THEN
    SELECT count(*) INTO v_sessions FROM ocpp_sessions WHERE sim_run_id = v_run;
    SELECT count(*) INTO v_events FROM ottoq_events WHERE sim_run_id = v_run;
    IF (v_row->'counters'->>'charge_sessions')::int <> v_sessions
       OR ((v_row->'counters'->>'events_total')::int <> LEAST(v_events, 200000)) THEN
      RAISE EXCEPTION '0466 V2: run % counters % against sessions % events %', v_run, v_row->'counters', v_sessions, v_events;
    END IF;
  END IF;
  -- V2b: weather is not counted as a fault.
  IF position($x$AND e.event_type NOT LIKE '%weather%'$x$ IN v_def) = 0 THEN
    RAISE EXCEPTION '0466 V2b: the fault counter still counts weather';
  END IF;
  -- V3: same grants as before (the browser key never had it; the edge function calls it).
  IF has_function_privilege('anon', 'public.ottoq_twin_run_list(integer)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_twin_run_list(integer)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_twin_run_list(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '0466 V3: the grants moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0466_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0466_the_run_list_counted_no_charge_sessions_for_any_run_and_printed_its_row_cap_as_a_count', false,
  'Reporting: public.ottoq_twin_run_list counts run-scoped and exact up to a 200,000-row guard, flags a capped '
  'counter, and counts charge sessions by run instead of against the wrong clock. No tick path calls it.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
