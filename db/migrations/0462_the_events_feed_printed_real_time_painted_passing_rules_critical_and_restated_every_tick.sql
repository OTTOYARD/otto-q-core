-- migration-version: 20260926040843
-- migration-name:    the_events_feed_printed_real_time_painted_passing_rules_critical_and_restated_every_tick
--
-- 0462  **The cockpit's Events feed printed real insert time beside a sim-time cockpit, painted passing rule checks
--       as critical alerts, and was mostly the row-diff audit trail restated every tick.** FINDINGS G193.
--
-- ══ §1 MEASURED on run 736406cf (busy_day, twin depot), 2026-09-23 06:40 UTC ══════════════════════════════════════
--
--   The Events tab showed `ottoq_twin_snapshot.recent_events`: the newest 15 events by `occurred_at`, minus seven
--   telemetry types. Of the run's non-telemetry events:
--     - `vehicle.state_changed` 26,675 and `stall.state_changed` 6,217 (68%): whole-row audit diffs with no summary;
--       the tab printed "Vehicle.state changed · vehicle" fifteen times at one timestamp.
--     - `rule.evaluated_pass` 5,088 carrying the RULE's severity, `critical` or `safety_critical`: a passing check
--       rendered as a red alert. A rule's consequence already has its own row (`ottoq.charge_start_refused`, or the
--       decision's "Held by the shield").
--     - `twin.staging_overflow` and `twin.recharge_stranded` 1,461 each, one per tick (gap p50 0.42, p90 0.53 sim-min).
--   And `at` was `occurred_at`, the REAL insert time ("01:33:24" on every row) while every other surface shows sim
--   time (14:40 CT): 0326 §1's two-clock class in the one tab that had not been converted.
--
-- ══ §2 WHAT THIS DOES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   A new read-only function, `public.ottoq_run_event_feed(run, limit, window_min)`, for the Events tab:
--     - SIM TIME: `sim_at` is `sim_clock_at`; `occurred_at` is returned beside it and never shown as the time.
--     - NOT THE AUDIT TRAIL: row diffs (`%.state_changed`), rule evaluations (`rule.evaluated_%`), debug severity and
--       the per-tick telemetry types are left to their own ledgers.
--     - REPEATS COLLAPSE: consecutive occurrences of one (event_type, entity, severity) less than five sim-minutes
--       apart are one row carrying `repeats`, `first_sim_at`, `sim_at` (the latest) and the latest payload. A per-tick
--       summary becomes one standing row; two genuinely separate events stay two rows.
--     - `standing`: the group's latest occurrence is within five sim-minutes of the run's newest event.
--     - `clipped`: the group began before the window, so its `first_sim_at` is the window's edge, not its start.
--     - `row_key`: stable across polls, so a growing group updates in place instead of re-arriving.
--     - `entity_name`: the vehicle's display name or the stall's code where the entity is one.
--   Bounded: the scan walks the newest 20,000 events of the run on the occurred_at index, then keeps the last
--   `window_min` sim-minutes (default 120). Measured on 689095e2 in a rolled-back dry run: 102 ms for 60 rows
--   (9 of them collapsed repeats) from 12,364 raw events in the window -- 408 `twin.staging_overflow` became one
--   standing row. The cockpit polls it every 10 s.
--
--   `ottoq_twin_snapshot.recent_events` is left as it is: the Events tab is its only consumer and stops reading it.
--
-- ══ §3 forces_recert FALSE ════════════════════════════════════════════════════════════════════════════════════════
--   A new read-only reporting function; no tick path calls it and no atom reads it.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: pg_stat_activity keeps 1 kB of query text and the recert runner (cron 746) names
          -- ottoq_determinism_pair only at character 1,303, so the clause above never sees it. Its
          -- advisory-lock key is in its first 100 characters.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0462 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_run_event_feed') THEN
    RAISE EXCEPTION '0462 P1: ottoq_run_event_feed already exists';
  END IF;
END $premises$;

CREATE FUNCTION public.ottoq_run_event_feed(
    p_sim_run_id uuid,
    p_limit      integer DEFAULT 60,
    p_window_min integer DEFAULT 120)
 RETURNS TABLE(row_key text, sim_at timestamp with time zone, first_sim_at timestamp with time zone,
               occurred_at timestamp with time zone, event_type text, severity text, entity_type text,
               entity_id uuid, entity_name text, payload jsonb, repeats integer, standing boolean, clipped boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  --: 0462. The Events tab's feed: sim time, not the audit trail, repeats collapsed. See the migration header.
  WITH raw AS (
    SELECT e.event_seq, e.event_type, e.severity, e.entity_type, e.entity_id, e.payload, e.occurred_at, e.sim_clock_at
      FROM public.ottoq_events e
     WHERE e.sim_run_id = p_sim_run_id
     ORDER BY e.occurred_at DESC
     LIMIT 20000
  ),
  bound AS (
    SELECT max(r.sim_clock_at) AS t_max,
           GREATEST(min(r.sim_clock_at),
                    max(r.sim_clock_at) - make_interval(mins => GREATEST(COALESCE(p_window_min, 120), 5))) AS t_min
      FROM raw r
  ),
  kept AS (
    SELECT r.*
      FROM raw r, bound b
     WHERE r.sim_clock_at >= b.t_min
       AND COALESCE(r.severity, 'info') <> 'debug'
       AND r.event_type NOT LIKE '%.state_changed'
       AND r.event_type NOT LIKE 'rule.evaluated%'
       AND r.event_type NOT IN ('twin.bess_dispatch','twin.weather_tick','twin.solar_tick','twin.grid_tick',
                                'twin.sim_tick_advanced','twin.telemetry_emitted','twin.bess_soh_degradation')
  ),
  seq AS (
    SELECT k.*,
           lag(k.sim_clock_at) OVER (PARTITION BY k.event_type, k.entity_id, k.severity
                                     ORDER BY k.sim_clock_at, k.event_seq) AS prev_sim
      FROM kept k
  ),
  grp AS (
    SELECT s.*,
           sum(CASE WHEN s.prev_sim IS NULL OR s.sim_clock_at - s.prev_sim > interval '5 minutes' THEN 1 ELSE 0 END)
             OVER (PARTITION BY s.event_type, s.entity_id, s.severity ORDER BY s.sim_clock_at, s.event_seq) AS g
      FROM seq s
  ),
  agg AS (
    SELECT gr.event_type, gr.entity_id, gr.severity, gr.g,
           count(*)::int                                                          AS repeats,
           min(gr.sim_clock_at)                                                   AS first_sim,
           max(gr.sim_clock_at)                                                   AS last_sim,
           max(gr.occurred_at)                                                    AS last_real,
           min(gr.event_seq)                                                      AS first_seq,
           max(gr.event_seq)                                                      AS last_seq,
           (array_agg(gr.payload     ORDER BY gr.sim_clock_at DESC, gr.event_seq DESC))[1] AS payload,
           (array_agg(gr.entity_type ORDER BY gr.sim_clock_at DESC, gr.event_seq DESC))[1] AS entity_type
      FROM grp gr
     GROUP BY gr.event_type, gr.entity_id, gr.severity, gr.g
  )
  SELECT CASE WHEN a.first_sim <= b.t_min + interval '1 minute'
              THEN 's:' || a.event_type || ':' || COALESCE(a.entity_id::text, '-') || ':' || COALESCE(a.severity, '-')
              ELSE 'g:' || a.first_seq::text END                                  AS row_key,
         a.last_sim                                                               AS sim_at,
         a.first_sim                                                              AS first_sim_at,
         a.last_real                                                              AS occurred_at,
         a.event_type,
         a.severity,
         a.entity_type,
         a.entity_id,
         COALESCE(v.display_name, st.stall_code,
                  a.payload->>'vehicle_display_name', a.payload->>'vehicle', a.payload->>'canopy_code',
                  pv.display_name)                                                AS entity_name,
         a.payload,
         a.repeats,
         (a.repeats > 1 AND a.last_sim >= b.t_max - interval '5 minutes')         AS standing,
         (a.first_sim <= b.t_min + interval '1 minute')                           AS clipped
    FROM agg a
    CROSS JOIN bound b
    LEFT JOIN public.vehicles v  ON a.entity_type = 'vehicle' AND v.id = a.entity_id
    LEFT JOIN public.stalls   st ON a.entity_type = 'stall'   AND st.id = a.entity_id
    LEFT JOIN public.vehicles pv ON a.entity_type NOT IN ('vehicle','stall')
                                AND pv.id = CASE WHEN a.payload->>'vehicle_id' ~* '^[0-9a-f-]{36}$'
                                                 THEN (a.payload->>'vehicle_id')::uuid END
   ORDER BY a.last_sim DESC, a.last_seq DESC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 60), 1), 300);
$function$;

REVOKE ALL ON FUNCTION public.ottoq_run_event_feed(uuid, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_run_event_feed(uuid, integer, integer) TO anon, authenticated, service_role;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_run uuid; v_rows int; v_audit int; v_real int; v_repeated int;
BEGIN
  IF NOT has_function_privilege('anon', 'public.ottoq_run_event_feed(uuid,integer,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '0462 V1: anon cannot read the feed';
  END IF;
  -- the newest twin-depot run that still has events
  SELECT e.sim_run_id INTO v_run FROM public.ottoq_events e
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY e.occurred_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;
  SELECT count(*),
         count(*) FILTER (WHERE f.event_type LIKE '%.state_changed' OR f.event_type LIKE 'rule.evaluated%'),
         count(*) FILTER (WHERE f.sim_at IS NULL),
         count(*) FILTER (WHERE f.repeats > 1)
    INTO v_rows, v_audit, v_real, v_repeated
    FROM public.ottoq_run_event_feed(v_run, 300, 120) f;
  -- V2: nothing from the audit trail, and every row carries a sim time
  IF v_audit > 0 THEN RAISE EXCEPTION '0462 V2: % audit rows in the feed', v_audit; END IF;
  IF v_real > 0 THEN RAISE EXCEPTION '0462 V2: % rows without a sim time', v_real; END IF;
  -- V3: row keys are unique within a page
  IF (SELECT count(*) - count(DISTINCT f.row_key) FROM public.ottoq_run_event_feed(v_run, 300, 120) f) <> 0 THEN
    RAISE EXCEPTION '0462 V3: duplicate row keys';
  END IF;
  RAISE NOTICE '0462 run %: % rows, % of them collapsed repeats', v_run, v_rows, v_repeated;
END $verify$;

-- Rollback: DROP FUNCTION public.ottoq_run_event_feed(uuid, integer, integer);

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0462_the_events_feed_printed_real_time_painted_passing_rules_critical_and_restated_every_tick', false,
  'Reporting: new read-only ottoq_run_event_feed for the cockpit Events tab. No tick path calls it and no atom reads it.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
