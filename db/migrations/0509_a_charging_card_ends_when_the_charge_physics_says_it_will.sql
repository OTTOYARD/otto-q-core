-- migration-version: 20260927020531
-- migration-name:    a_charging_card_ends_when_the_charge_physics_says_it_will
--
-- 0509  **Under 0508 a charge step stays current until its session ends, and its card said "until" a time the
--       charge had already passed (G238, the display half).** `db/checks/0375` §6.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   0507 gave the current step `expected_end` = its actual start plus its planned duration. Before 0508 the charge
--   leg closed at the booking window, so a charge that outran its plan left the card anyway. 0508 keeps the leg open
--   until its session ends, which is the truth, and 21 of 31 completed L2 charges on 5344fc12 outran their window. So
--   the card would read "Now: Level 2 charge until 10:30 AM" at 10:50, with the progress bar pinned at 100%.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   For a current charge step whose car has an active session, `expected_end` is the run's clock plus the minutes the
--   planner's own charge model (`ottoq_estimate_charge_minutes`) gives from the car's SoC now to its target, calibrated
--   on this session as it runs: the model's minutes are scaled by the ratio of the minutes the session has actually
--   taken to the minutes the model says the SoC gained so far should have taken. The inputs are what a real depot
--   knows: the charger's `max_kw`, the car's inlet limit, pack and state of health, the session's start SoC, start
--   time and ambient, the car's SoC now, and the target capped by `ottoq_target_soc_cap` for the stall type. It reads
--   nothing only a simulation knows (no variability profile, no per-car curve card), so it behaves the same on real
--   OCPP meter values; the twin's own perturbations are what the calibration has to learn. Until the session has
--   gained 2 points of SoC the ratio is 1, and it is held between 0.5 and 5. The step then says
--   `eta_source: 'charge_physics'`, and its `progress_pct` is elapsed over elapsed plus remaining. Every other current
--   step keeps 0507's `expected_end` and says `eta_source: 'plan'`. Every current step also carries `over_plan_min`,
--   the whole minutes it has run past its planned duration (null until it has). Contract 1.2 -> 1.3: two fields
--   added, and `expected_end` of a running charge now comes from the calibrated physics.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   A read function for the cockpits: nothing certified reads it.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0509 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured (0507's) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure))
     <> '3e730ff03953c926b56916fa18f67552' THEN
    RAISE EXCEPTION '0509 P2: public.ottoq_depot_cards is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0509_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure);
  v_old1 text := $o1$        'actual_start', l.actual_start_sim,
        /* 0507 (G232): when the step will end from when it started, as the progress bar measures */
        'expected_end', CASE WHEN l.actual_start_sim IS NOT NULL AND l.planned_duration_s IS NOT NULL
                             THEN l.actual_start_sim + make_interval(secs => l.planned_duration_s)
                             ELSE l.planned_end_sim END,
        'progress_pct', LEAST(100, GREATEST(0, round(
           100.0 * EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.actual_start_sim))
                 / NULLIF(l.planned_duration_s,0)))))
       FROM ottoq_itinerary_legs l
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'active'$o1$;
  v_new1 text := $n1$        'actual_start', l.actual_start_sim,
        /* 0507 (G232), 0509 (G238): when the step will end. A running charge ends when the charge physics says it
           will from the car's SoC now; any other step when it started plus its planned duration. */
        'expected_end', CASE WHEN eta.min_left IS NOT NULL
                             THEN (SELECT sim_clock_current FROM run) + make_interval(secs => eta.min_left * 60)
                             WHEN l.actual_start_sim IS NOT NULL AND l.planned_duration_s IS NOT NULL
                             THEN l.actual_start_sim + make_interval(secs => l.planned_duration_s)
                             ELSE l.planned_end_sim END,
        'eta_source', CASE WHEN eta.min_left IS NOT NULL THEN 'charge_physics' ELSE 'plan' END,
        'over_plan_min', CASE WHEN l.actual_start_sim IS NOT NULL AND l.planned_duration_s IS NOT NULL
                               AND (SELECT sim_clock_current FROM run) > l.actual_start_sim + make_interval(secs => l.planned_duration_s)
                              THEN floor(EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run)
                                     - (l.actual_start_sim + make_interval(secs => l.planned_duration_s)))) / 60)::int END,
        'progress_pct', CASE WHEN eta.min_left IS NOT NULL THEN
             LEAST(100, GREATEST(0, round(
               100.0 * EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.actual_start_sim))
                     / NULLIF(EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.actual_start_sim))
                              + eta.min_left * 60, 0))))
           ELSE LEAST(100, GREATEST(0, round(
           100.0 * EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.actual_start_sim))
                 / NULLIF(l.planned_duration_s,0)))) END)
       FROM ottoq_itinerary_legs l
       /* 0509 (G238): the minutes left on the car's running charge. The planner's charge model from the SoC now to the
          target, scaled by how this session has actually run against the same model: the minutes it has taken over
          the minutes the model gives for the SoC it has gained (1 until it has gained 2 points; held in [0.5, 5]). */
       LEFT JOIN LATERAL (
         SELECT public.ottoq_estimate_charge_minutes(
                  x.soc_now, x.target, x.charger_kw, x.inlet_kw, x.pack_kwh, x.temp_c, x.soh, x.ratio) AS min_left
           FROM (
             SELECT y.*,
                    CASE WHEN y.soc_now - y.soc_start >= 2 AND y.model_min_done > 0
                         THEN LEAST(5, GREATEST(0.5, y.elapsed_min / y.model_min_done)) ELSE 1 END AS ratio
               FROM (
                 SELECT v.current_soc AS soc_now, os.soc_start,
                        LEAST(COALESCE(v.target_soc, public.ottoq_default_target_soc()),
                              public.ottoq_target_soc_cap(st.stall_type::text, os.started_at)) AS target,
                        ch.max_kw AS charger_kw, v.inlet_max_kw AS inlet_kw, v.battery_capacity_kwh AS pack_kwh,
                        COALESCE(os.ambient_temp_c, 22) + 5 AS temp_c,
                        COALESCE((v.config->>'battery_soh_pct')::numeric, 95) AS soh,
                        EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - os.started_at)) / 60 AS elapsed_min,
                        public.ottoq_estimate_charge_minutes(os.soc_start, v.current_soc, ch.max_kw, v.inlet_max_kw,
                          v.battery_capacity_kwh, COALESCE(os.ambient_temp_c, 22) + 5,
                          COALESCE((v.config->>'battery_soh_pct')::numeric, 95), 1.0) AS model_min_done
                   FROM ocpp_sessions os
                   JOIN stalls st ON st.id = os.stall_id
                   JOIN ottoq_ocpp_chargers ch ON ch.charger_id = st.ocpp_charger_id
                   JOIN vehicles v ON v.id = os.vehicle_id
                  WHERE l.leg_type IN ('charge_dcfc','charge_l2')
                    AND os.vehicle_id = l.vehicle_id AND os.sim_run_id = l.sim_run_id AND os.status = 'active'
                  ORDER BY os.started_at DESC LIMIT 1) y) x) eta ON true
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'active'$n1$;
  v_old2 text := $o2$'contract_version', '1.2',$o2$;
  v_new2 text := $n2$'contract_version', '1.3',$n2$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1);
  IF n <> 1 THEN RAISE EXCEPTION '0509: the current step matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2);
  IF n <> 1 THEN RAISE EXCEPTION '0509: the contract version matched % times, not once', n; END IF;
  EXECUTE replace(replace(v_def, v_old1, v_new1), v_old2, v_new2);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure;
  v_def text := pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure);
BEGIN
  -- V1: the current step carries the calibrated ETA (the model run twice: the span done and the span left), its
  -- source and the minutes past plan, once; nothing only a simulation knows is read; 0506's and 0507's fields are
  -- still there; the contract reads 1.3.
  IF (length(v_def) - length(replace(v_def, '''eta_source''', ''))) / length('''eta_source''') <> 1
     OR (length(v_def) - length(replace(v_def, '''over_plan_min''', ''))) / length('''over_plan_min''') <> 1
     OR (length(v_def) - length(replace(v_def, 'ottoq_estimate_charge_minutes(', ''))) / length('ottoq_estimate_charge_minutes(') <> 2
     OR position('ottoq_profile_rate_mult' IN v_def) > 0 OR position('charge_curve_scalar' IN v_def) > 0
     OR (length(v_def) - length(replace(v_def, '''expected_end''', ''))) / length('''expected_end''') <> 1
     OR (length(v_def) - length(replace(v_def, '''atom'', l.duration_basis->>''atom''', ''))) / length('''atom'', l.duration_basis->>''atom''') <> 3
     OR position('''overdue_min''' IN v_def) = 0
     OR position('''contract_version'', ''1.3''' IN v_def) = 0 THEN
    RAISE EXCEPTION '0509 V1: public.ottoq_depot_cards is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer, volatility and search path kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT provolatile FROM pg_proc WHERE oid = v_f) <> 's'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
          <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres'
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_f) <> 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0509 V2: public.ottoq_depot_cards''s privileges or settings changed';
  END IF;
END $verify$;

-- V3: on the live run, if there is one: every current charge step whose car has an active session reads
-- `eta_source = 'charge_physics'` with an `expected_end` at or after the payload's own clock, and every other current
-- step reads 'plan'. With no live run V3 is skipped, loudly.
DO $v3$
DECLARE
  v_cards jsonb; v_clock timestamptz; v_charge int; v_physics int; v_ahead int; v_other int; v_plan int;
BEGIN
  v_cards := public.ottoq_depot_cards('11111111-1111-1111-1111-111111111111', NULL);
  v_clock := (v_cards->>'sim_clock')::timestamptz;
  IF v_cards->>'sim_run_id' IS NULL OR v_clock IS NULL THEN
    RAISE NOTICE '0509 V3 SKIPPED: no live run at the twin depot to read cards from';
    RETURN;
  END IF;
  SELECT count(*) FILTER (WHERE st->>'leg_type' IN ('charge_dcfc','charge_l2')
                            AND EXISTS (SELECT 1 FROM public.ocpp_sessions os
                                         WHERE os.vehicle_id = (veh->>'vehicle_id')::uuid
                                           AND os.sim_run_id = (v_cards->>'sim_run_id')::uuid AND os.status = 'active')),
         count(*) FILTER (WHERE st->>'eta_source' = 'charge_physics'),
         count(*) FILTER (WHERE st->>'eta_source' = 'charge_physics' AND (st->>'expected_end')::timestamptz >= v_clock),
         count(*) FILTER (WHERE st->>'leg_type' NOT IN ('charge_dcfc','charge_l2')),
         count(*) FILTER (WHERE st->>'leg_type' NOT IN ('charge_dcfc','charge_l2') AND st->>'eta_source' = 'plan')
    INTO v_charge, v_physics, v_ahead, v_other, v_plan
    FROM jsonb_array_elements(v_cards->'vehicles') veh, jsonb_array_elements(COALESCE(veh->'card'->'steps', '[]'::jsonb)) st
   WHERE st->>'status' = 'current';
  IF v_charge = 0 OR v_physics <> v_charge OR v_ahead <> v_physics OR v_plan <> v_other THEN
    RAISE EXCEPTION '0509 V3 FAILED: % charging steps, % by physics (% ahead of the clock); % other steps, % by plan',
      v_charge, v_physics, v_ahead, v_other, v_plan;
  END IF;
  RAISE NOTICE '0509 V3 PASSED: % charging steps by physics, all ahead of the clock; % other steps by plan', v_physics, v_plan;
END $v3$;

-- Rollback: restore public.ottoq_depot_cards from ottoq_schema_snapshots label '0509_pre' (CREATE OR REPLACE, ACL
-- kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0509_a_charging_card_ends_when_the_charge_physics_says_it_will', false,
  'ottoq_depot_cards: a current charge step with an active session ends when the planner''s charge model, calibrated '
  'on the session so far, says it will from the car''s SoC now (eta_source charge_physics); every current step carries '
  'over_plan_min. A cockpit read function; nothing certified reads it.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
