-- migration-version: PENDING
-- migration-name:    honest_completion_and_eta

-- ============================================================================
-- 0009_honest_completion_and_eta.sql
--
-- THE SHORT VERSION, IN PLAIN LANGUAGE
--
-- Two records in this system currently lie, and you cannot teach a forecast from a
-- record that lies. This file fixes both and does nothing else. No orchestration,
-- no decision logic, no LP, no cuOpt, no approval gate, no tick behaviour changes.
--
--   (1) THE DEPOT WRITES DOWN WORK IT DID NOT DO.
--       When a car leaves a bay, the twin ticks off a FIXED LIST of jobs -- always the
--       same list, no matter why the car went in. A car that went into the service bay
--       for a single sensor calibration comes out recorded as having had a calibration,
--       a preventive-maintenance service, a fault repair AND a cosmetic repair. Three of
--       those four never happened. The fault repair is the damaging one: it wipes the
--       car's fault list clean, so a genuinely broken car is filed as healthy.
--       That is the same disease 0008 just fixed one layer down, showing up again at the
--       caller, and it partly undoes 0008's work.
--       NOW: the depot ticks off only the jobs that car actually had outstanding on this
--       visit, plus the one job a technician's flag explicitly names. If a car genuinely
--       had all four due, it still gets all four -- the bug is unconditionality, not
--       breadth.
--
--   (2) THE DEPOT REWRITES ITS OWN SCHEDULE TO MATCH WHAT HAPPENED.
--       When a car decides to come home, the depot overwrites the arrival time it had
--       planned at dispatch with a fresh one -- and that fresh one is a flat 30 minutes
--       for every car, every time. Measured on live data: 116 of 116 rows, one single
--       ETA value in the entire table. So any "how accurate were we?" check grades the
--       schedule against an arrival the schedule itself caused. There is no learning
--       signal in that, only a circle.
--       NOW: the dispatch-time plan is preserved in its own column that nothing is able
--       to overwrite, and every refresh of the live estimate is stamped with WHEN it
--       happened and WHAT produced it. Plan, live estimate and actual arrival become
--       three separate observable facts for the first time.
--
--   WHAT THIS FILE DELIBERATELY DOES NOT DO: it does not make the 30-minute ETA
--   "smarter". The twin models no position, no route and no distance -- I checked, and
--   0 of 5,523 telemetry packets carry a coordinate. Worse, in the sim the arrival is
--   DEFINED as "return started + ETA", so the ETA does not predict the arrival, it
--   CAUSES it. Swapping one constant for a cleverer-looking constant would change a
--   number without adding an ounce of truth. Declined on purpose. See §6 DECLINED.
--
-- ============================================================================
-- ============================================================================
-- PREMISE VERIFICATION -- MEASURED LIVE ON gxdrcyphqjzjsuhxuqtg, 2026-08-05,
-- READ-ONLY, BEFORE A SINGLE LINE OF THIS FILE WAS WRITTEN. 0 runs `running`.
-- I state my OWN denominators throughout and never adopt one I cannot reproduce.
--
-- I was handed two premises. ONE HOLDS EXACTLY AS STATED AND IS WORSE THAN DESCRIBED.
-- THE OTHER IS HALF WRONG, and I correct it below rather than inherit it -- the
-- correction changes what the fix is allowed to rest on.
--
-- ---------------------------------------------------------------------------
-- PREMISE 1 -- "completion credit is a fixed array". CONFIRMED, VERBATIM.
--
-- Quoted from the live twin.ottoq_sim_advance_service_flow
-- (md5 8797fe90392487701947ede78b93a768, 464 lines, read live 2026-08-05):
--
--     -- wear truth follows completion (mark_serviced was dead: soil/PM/calibration never reset)
--     PERFORM ottoq_wear_mark_serviced(v_rec.id, p_sim_run_id, s, v_end_ts)
--       FROM unnest(CASE WHEN v_rec.current_state = 'in_wash_bay' THEN ARRAY['exterior_wash','sensor_clean']
--                        WHEN v_rec.current_state = 'in_detail_bay' THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
--                        ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END) AS s;
--
-- There is no predicate anywhere in that statement. The CASE branches on WHICH BAY the
-- vehicle is leaving and on nothing else. Every service-bay exit therefore credits four
-- services; every detail-bay exit credits three; every wash-bay exit credits two.
--
-- THIS IS ALREADY IN THE REPO AS AN OPEN DEFECT. 0005 registered it and left it:
--     "GAP 5 -- THE WHOLE-BAY-ARRAY OVER-MARKING IS STILL THERE (0004 GAP 4, now wider).
--      twin.ottoq_sim_advance_service_flow marks the entire bay array serviced on exit ...
--      the bay path still over-marks, and it now propagates into more profile columns
--      than before. Worth its own pass."
-- This file is that pass. Third migration in a row to name it; first to fix it.
--
-- HOW BIG IS THE LIE? MY OWN DENOMINATOR -- the entire visit ledger, all runs:
--     SELECT a->>'svc', count(*),
--            count(*) FILTER (WHERE COALESCE(a->>'status','pending')
--                             NOT IN ('done','cancelled','skipped')) AS outstanding
--       FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
--      GROUP BY 1 ORDER BY 2 DESC;
--     -> 234 atoms across 80 visits, 12 distinct service codes:
--        readiness_check 80 | interior_inspection 77 | interior_tidy 24 | mechanical_pm 11
--        item_retrieval 10 | charge 8 | remote_diagnostics 6 | triage_check 6
--        interior_deep_clean 4 | sensor_calibration 3 | sensor_clean 3 | fault_repair 2
--
--     TWO OF THE FOUR SERVICE-BAY CODES DO NOT EXIST IN THE LEDGER AT ALL:
--        exterior_wash   -> 0 atoms, ever. Credited on EVERY wash and detail exit.
--        cosmetic_repair -> 0 atoms, ever. Credited on EVERY service-bay exit.
--     AND fault_repair exists 2 times in the whole ledger, yet is credited on every
--     single service-bay exit.
--
-- WHAT EACH FALSE CREDIT ACTUALLY COSTS, read from the live public.ottoq_wear_mark_serviced
-- (the 0008 body, md5 6698cea9109e2b45d39ccf2f7c093136):
--     fault_repair        -> open_fault_codes := '{}', worst_fault_severity := 99
--                            AND wear open_dtc_count := 0, worst_open_dtc_rank := 99
--     mechanical_pm       -> last_pm_at, km_at_last_pm reset; wear km_at_last_pm reset
--     sensor_calibration  -> last_calibration_at, hours_at_last_calibration reset
--     exterior_wash       -> last_wash_at, exterior_soil_level reset
--     interior_deep_clean -> last_deep_clean_at, cabin_condition := 'clean', litter := 0
--     interior_tidy       -> cabin_condition light_litter -> clean
--     cosmetic_repair     -> UNMAPPED. Falls through every CASE. A no-op today; it is
--                            still a false entry in the record, and it would become a
--                            real reset the moment anyone maps it.
-- So the service-bay array's headline cost is exact and severe: A CAR THAT WENT IN FOR A
-- CALIBRATION COMES OUT WITH ITS FAULT LIST WIPED. 0008 spent a whole section refusing to
-- let a PM clear faults; the caller has been handing out fault_repair unconditionally the
-- entire time.
--
-- ⚠️ ONE CORRECTION TO THE BRIEF'S FRAMING, BECAUSE IT CHANGES WHAT I AM ALLOWED TO TOUCH.
-- The same fixed arrays are ALSO passed to ottoq_mark_visit_atoms_done two lines above.
-- That call is NOT part of this defect and I leave it byte-for-byte. Read its live body:
--     IF v_a->>'svc' = ANY(p_svcs) AND COALESCE(v_a->>'status','pending') <> 'done' THEN
-- It only ever touches atoms that ALREADY EXIST on the visit, so it is intersected by
-- construction. Passing it a wide array marks nothing that was not genuinely open.
-- ottoq_wear_mark_serviced has no such protection: it writes unconditionally to
-- ottoq_vehicle_wear and public.vehicle_need_profile whether or not the work was ever
-- requested. THAT asymmetry is the whole defect, and it is the only line I change.
--
-- THE CORRECT PATTERN I AM COPYING -- 0005 §3, quoted verbatim from the committed file
-- db/migrations/0005_inspection_and_condition_resets.sql (twin.ottoq_sim_advance_visit_atoms):
--
--         -- ══════════ 0005: CREDIT THE LEDGER THE DEPOT ACTUALLY READS ══════════
--         BEGIN
--           PERFORM public.ottoq_wear_mark_serviced(
--                     v_rec.vehicle_id, p_sim_run_id, v_a->>'svc',
--                     COALESCE((v_a->>'ends_at')::timestamptz, p_clock));
--         EXCEPTION WHEN OTHERS THEN
--           RAISE WARNING 'ottoq_sim_advance_visit_atoms: need-ledger credit FAILED SAFELY vehicle=% svc=% %: %',
--             v_rec.vehicle_id, v_a->>'svc', SQLSTATE, SQLERRM;
--         END;
--
-- ONE REAL ATOM CODE PER CALL -- `v_a->>'svc'`, the atom's own service, taken from the
-- atom the loop just closed. 0005's own gap register says so in as many words: "§3 does
-- NOT share this defect -- it credits the atom's own svc, one at a time, which is exactly
-- what was performed." That path stays exactly as it is; nothing here disables it.
-- The real-telemetry seam public.ottoq_ingest_service_complete is the same shape and is
-- additionally guarded -- it credits only when atoms actually moved:
--     IF v_before - v_after > 0 THEN
--       FOREACH v_s IN ARRAY p_services LOOP
--         BEGIN PERFORM ottoq_wear_mark_serviced(p_vehicle_id, v_run.sim_run_id, v_s, v_clock);
-- Live callers of ottoq_wear_mark_serviced today: 3 (ottoq_ingest_service_complete,
-- twin.ottoq_sim_advance_visit_atoms, twin.ottoq_sim_advance_service_flow). Two are
-- correct. The bay path is the outlier.
--
-- ---------------------------------------------------------------------------
-- PREMISE 2 -- "ottoq_return_eta_minutes is a constant that destructively overwrites
-- scheduled_return_at". THE CONSTANT IS CONFIRMED AND IS WORSE THAN STATED.
-- ⚠️ "DESTRUCTIVELY" IS HALF WRONG AND I AM CORRECTING IT, BECAUSE A WRONG PREMISE
--    POISONS A FIX EVEN WHEN IT POINTS AT THE RIGHT LINE OF CODE.
--
-- THE CONSTANT, quoted verbatim from the live public.ottoq_return_eta_minutes
-- (md5 c59fb82f326a01158a3276c3906d0ec4) -- the entire body:
--
--     CREATE OR REPLACE FUNCTION public.ottoq_return_eta_minutes(p_vehicle_id uuid, p_depot_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid)
--      RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER
--      SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
--     AS $function$
--       SELECT GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id, 'return_eta_minutes', 30), 30));
--     $function$
--
-- No vehicle, no depot, no distance, no traffic. Both of its first two parameters are
-- accepted and then never read. Its only live caller passes NULL for the depot.
--
-- THE OVERWRITE, quoted verbatim from the live twin.ottoq_sim_advance_deployed_telemetry
-- (md5 595d96841d68f63714e153faa7dfddf0):
--
--     v_eta_min := ottoq_return_eta_minutes(v_dispatch.vehicle_id, NULL, p_sim_run_id);
--     ...
--         UPDATE ottoq_vehicle_dispatches
--            SET status = 'returning',
--                returning_started_at = p_sim_clock_now,
--                return_eta_minutes   = v_eta_min,
--                scheduled_return_at  = p_sim_clock_now + (v_eta_min || ' minutes')::interval,
--
-- MEASURED, MY OWN DENOMINATOR (all 435 dispatch rows in the table, 7 runs):
--     SELECT count(*) FILTER (WHERE returning_started_at IS NOT NULL)                       AS reached_handshake,
--            count(*) FILTER (WHERE returning_started_at IS NOT NULL
--              AND scheduled_return_at = returning_started_at + interval '30 minutes')      AS exactly_plus_30,
--            count(DISTINCT return_eta_minutes)                                             AS distinct_eta
--       FROM public.ottoq_vehicle_dispatches;
--     -> reached_handshake 116 | exactly_plus_30 116 | distinct_eta 1 (min 30, max 30)
--   116 OF 116. Not 109 of 112 -- a different denominator, a stronger finding: it is not
--   "nearly always" 30, it is ALWAYS 30, and there has never been a second value.
--
-- ⚠️ THE CORRECTION: "the plan is destroyed" IS NOT TRUE, and pretending it is would have
--    led me to build a column the table already has.
--    `planned_duration_min` is written once at dispatch and NEVER UPDATED. I checked every
--    function whose body mentions it:
--      SELECT n.nspname||'.'||p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--       WHERE pg_get_functiondef(p.oid) ~ 'planned_duration_min';
--      -> ottoq_cert_arm_start, ottoq_comms_vehicle_status, ottoq_twin_offsite_window (all READ),
--         twin.ottoq_sim_dispatch_vehicle, twin.ottoq_sim_prime_deployment (both INSERT only).
--    Nothing updates it. And at insert time the two agree exactly, quoted verbatim from
--    twin.ottoq_sim_dispatch_vehicle:
--        dispatched_at, scheduled_return_at, planned_duration_min ...
--        p_sim_clock_now,
--        p_sim_clock_now + (v_planned_min || ' minutes')::INTERVAL,
--        v_planned_min, ...
--    So the dispatch-time plan SURVIVES as `dispatched_at + planned_duration_min`.
--        SELECT count(*), count(*) FILTER (
--                 WHERE scheduled_return_at = dispatched_at + (planned_duration_min||' minutes')::interval)
--          FROM public.ottoq_vehicle_dispatches;   -> 435 rows | 75 still equal
--    360 of 435 rows have had scheduled_return_at moved away from their own plan.
--
--    WHAT IS ACTUALLY WRONG IS NARROWER AND MORE PRECISE THAN "THE PLAN IS DESTROYED":
--    `scheduled_return_at` is ONE MUTABLE COLUMN CARRYING THREE DIFFERENT QUANTITIES over
--    the life of a row -- the dispatch plan, then the delay-card-adjusted plan, then the
--    return-handshake estimate -- with nothing on the row to say which one you are looking
--    at or when it changed. It is the column every forecast reader and every accuracy check
--    reaches for, and it is the one column that cannot be trusted to mean one thing.
--
-- THE ACCURACY NUMBERS, RECOMPUTED ON MY OWN DENOMINATOR (the 116 rows that actually went
-- through the return handshake, 2 runs):
--     plan (dispatched_at + planned_duration_min) vs actual_return_at:
--         median |err| 734.7 min | p90 766.7 | mean bias +633.3 | within 5 min: 0 of 116
--     scheduled_return_at (post-overwrite) vs actual_return_at:
--         median |err| 28.0 min | within 5 min: 0 of 116
--   The brief quoted 68.4 / 215.5 / +92.4 on 112 rows; I measure far larger errors on 116.
--   Different population, same verdict and then some: THE DISPATCH-TIME PLAN IS NOT A
--   PREDICTOR OF ANYTHING TODAY. That is exactly why it must be preserved as a first-class,
--   un-overwritable fact -- you cannot begin to improve a prediction you keep erasing.
--
-- ---------------------------------------------------------------------------
-- CAN ETA PART (b) BE DONE? NO. I AM DECLINING IT, WITH THE EVIDENCE.
--
-- (i) THE TWIN MODELS NO POSITION. The columns exist and are never written:
--       SELECT count(*), count(current_lat), count(current_lng), count(speed_kmh)
--         FROM public.ottoq_telemetry_packets;
--       -> 5,523 packets | current_lat 0 | current_lng 0 | speed_kmh 5,369
--     The twin's own emitter twin.ottoq_sim_emit_telemetry has no lat/lng parameter at all
--     and its two INSERT column lists omit both columns. There is no coordinate to measure
--     a distance from, and no depot-relative geometry anywhere on the deployed path.
--
-- (ii) SPEED IS NOT A TRAJECTORY. `v_avg_speed := 20 + seeded_random(...) * 70` is re-drawn
--     independently EVERY TICK, 20-90 km/h. It produces a distance TRAVELLED
--     (v_miles, accumulated into miles_driven) but never a distance REMAINING, because
--     there is no destination in the model to remain from.
--
-- (iii) AND THE DECISIVE ONE: IN THE SIM THE ETA DOES NOT PREDICT THE ARRIVAL, IT CAUSES
--     IT. The arrival branch, quoted verbatim from the live function:
--         ELSIF v_dispatch.status = 'returning'
--               AND p_sim_clock_now >= COALESCE(
--                     v_dispatch.returning_started_at
--                       + (COALESCE(v_dispatch.return_eta_minutes, 30) || ' minutes')::interval,
--                     v_dispatch.scheduled_return_at + INTERVAL '5 minutes') THEN
--     The vehicle arrives BECAUSE the ETA elapsed. Change the ETA and you change the
--     arrival by exactly the same amount. Any "improved" estimate would be graded against
--     an outcome it authored. A different constant with a better name is not an
--     improvement and I will not dress one up as one.
--
--     WHAT WOULD BE NEEDED LATER, stated plainly so this is a to-do and not a shrug:
--       - the twin must carry a destination and a remaining distance (or a route with legs)
--         and emit position on the telemetry packet, so ETA = f(distance, speed, traffic);
--       - the arrival must be driven by that physics rather than by the ETA field, so the
--         two become independent and the error is real;
--       - in PRODUCTION the honest source already exists and is not a model at all: the
--         vehicle reports its own ETA through public.ottoq_ingest_vehicle_signal(p_eta_min).
--         When that seam carries real traffic, ottoq_return_eta_minutes should prefer a
--         fresh vehicle-reported ETA and keep the policy value only as a fallback. That is
--         a behaviour change to a live decision path and is deliberately NOT in this file.
--
-- ---------------------------------------------------------------------------
-- CLOCK DOMAIN OF EVERY TIMESTAMP THIS FILE TOUCHES (sim-vs-real confusion is a known
-- recurring bug class here -- 8+ instances, one of them inside a measurement):
--   public.ottoq_vehicle_dispatches
--     dispatched_at .......... SIM   (written as p_sim_clock_now)
--     scheduled_return_at .... SIM   (dispatched_at + planned_duration_min, then mutated)
--     returning_started_at ... SIM   (p_sim_clock_now)
--     actual_return_at ....... SIM   (p_sim_clock_now)
--     planned_return_at ...... SIM   NEW: generated from dispatched_at + planned_duration_min
--     eta_refreshed_at ....... SIM   NEW: written as p_sim_clock_now
--     created_at ............. REAL  (now(); untouched by this file)
--   twin.ottoq_sim_advance_service_flow
--     p_sim_clock_now ........ SIM
--     v_end_ts ............... SIM   (config.service_ends_at, else p_sim_clock_now)
--   public.ottoq_vehicle_wear.updated_at and vehicle_need_profile.updated_at are REAL
--   (now()) and are set inside ottoq_wear_mark_serviced, which this file does not modify.
--   NO WALL-CLOCK VALUE IS COMPARED TO A SIM VALUE ANYWHERE IN THIS FILE.
-- ============================================================================


-- Fail fast rather than queue behind a live tick. §2 rewrites
-- public.ottoq_vehicle_dispatches (435 rows -- milliseconds) under ACCESS EXCLUSIVE;
-- lock_timeout means it gives up instead of stalling the engine.
SET lock_timeout = '5s';
SET statement_timeout = '600s';


-- ============================================================================
-- §1  SNAPSHOT, THEN GUARD  (house rule 1: snapshot before replace)
--
-- Recover any pre-image later with:
--   SELECT definition FROM public.ottoq_schema_snapshots
--    WHERE label = '0009_honest_completion_and_eta_pre' AND object_name = '<fn>';
--
-- NOTHING IS DROPPED BY THIS FILE. No table, no column, no function. Both function
-- changes are CREATE OR REPLACE of an existing signature; both column additions are
-- ADD COLUMN IF NOT EXISTS. There is no VACUUM FULL anywhere in this file.
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0009_honest_completion_and_eta_pre',
       CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
       n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname = 'twin'   AND p.proname IN ('ottoq_sim_advance_service_flow',
                                               'ottoq_sim_advance_deployed_telemetry'))
    OR (n.nspname = 'public' AND p.proname IN ('ottoq_return_eta_minutes',
                                               'ottoq_wear_mark_serviced',
                                               'ottoq_mark_visit_atoms_done'));
-- The last three are snapshotted as CONTEXT, not because they are edited. This file
-- does not touch any of them; capturing them makes the audit trail self-contained if
-- someone later asks what they looked like on the day the caller was fixed.

DO $guard$
DECLARE
  v_src text;
  v_n   int;
BEGIN
  -- ---- 0. no live run -------------------------------------------------------
  -- §2 rewrites a table the tick writes to every minute (cron 12). 435 rows is a
  -- millisecond rewrite, but it must not land mid-tick. If this ever blocks a needed
  -- fix, STOP the run first -- never disable cron 12, it IS the start engine.
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_n > 0 THEN
    RAISE EXCEPTION 'GUARD: % sim run(s) are running. §2 rewrites ottoq_vehicle_dispatches under ACCESS EXCLUSIVE. Stop the run, then re-apply. Nothing has been changed.', v_n;
  END IF;

  -- ---- 1. twin.ottoq_sim_advance_service_flow -------------------------------
  -- Exactly one signature, and it must still be the body this file quotes line by
  -- line -- md5 8797fe90392487701947ede78b93a768, read live 2026-08-05.
  SELECT count(*), min(md5(pg_get_functiondef(p.oid)))
    INTO v_n, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_service_flow';
  IF v_n = 0 THEN
    RAISE EXCEPTION 'GUARD: twin.ottoq_sim_advance_service_flow does not exist. This migration expected to REPLACE it, not create it. Nothing has been changed.';
  ELSIF v_n > 1 THEN
    RAISE EXCEPTION 'GUARD: twin.ottoq_sim_advance_service_flow has % overloads; this file assumes exactly one (uuid, timestamptz, numeric, uuid). Nothing has been changed.', v_n;
  ELSIF v_src <> '8797fe90392487701947ede78b93a768' THEN
    RAISE EXCEPTION 'GUARD: twin.ottoq_sim_advance_service_flow is md5 % , not the body (8797fe90392487701947ede78b93a768) this migration reproduces in full. Someone changed it outside this repo. Re-read the live body, re-base, re-run. Nothing has been changed.', v_src;
  END IF;

  -- The exact statement §3 removes must be present, or §3 is replacing something else.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_service_flow';
  IF position('FROM unnest(CASE WHEN v_rec.current_state = ''in_wash_bay''' IN v_src) = 0 THEN
    RAISE EXCEPTION 'GUARD: the fixed-array wear credit this migration removes is not present in the live body. Nothing has been changed.';
  END IF;
  IF position('PERFORM ottoq_mark_visit_atoms_done(v_rec.id,' IN v_src) = 0 THEN
    RAISE EXCEPTION 'GUARD: the ottoq_mark_visit_atoms_done call this migration preserves byte-for-byte is not present in the live body. Nothing has been changed.';
  END IF;

  -- ---- 2. twin.ottoq_sim_advance_deployed_telemetry -------------------------
  SELECT count(*), min(md5(pg_get_functiondef(p.oid)))
    INTO v_n, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_deployed_telemetry';
  IF v_n = 0 THEN
    RAISE EXCEPTION 'GUARD: twin.ottoq_sim_advance_deployed_telemetry does not exist. This migration expected to REPLACE it, not create it. Nothing has been changed.';
  ELSIF v_n > 1 THEN
    RAISE EXCEPTION 'GUARD: twin.ottoq_sim_advance_deployed_telemetry has % overloads; this file assumes exactly one (uuid, timestamptz, numeric). Nothing has been changed.', v_n;
  ELSIF v_src <> '595d96841d68f63714e153faa7dfddf0' THEN
    RAISE EXCEPTION 'GUARD: twin.ottoq_sim_advance_deployed_telemetry is md5 % , not the body (595d96841d68f63714e153faa7dfddf0) this migration reproduces in full. Someone changed it outside this repo. Re-read the live body, re-base, re-run. Nothing has been changed.', v_src;
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_deployed_telemetry';
  IF position('scheduled_return_at  = p_sim_clock_now + (v_eta_min || '' minutes'')::interval' IN v_src) = 0 THEN
    RAISE EXCEPTION 'GUARD: the return-handshake scheduled_return_at write this migration stamps is not present in the live body. Nothing has been changed.';
  END IF;

  -- ---- 3. the columns §4 writes must be addable, and the plan must be derivable ----
  -- planned_return_at is GENERATED from these two. Both are NOT NULL today, which is
  -- what makes the generated column a TOTAL function: it can never be NULL, so no
  -- reader has to handle a missing plan.
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='ottoq_vehicle_dispatches'
                AND column_name IN ('dispatched_at','planned_duration_min')
                AND is_nullable = 'YES') THEN
    RAISE EXCEPTION 'GUARD: dispatched_at / planned_duration_min are no longer NOT NULL; planned_return_at would be nullable and would stop being a total function. Nothing has been changed.';
  END IF;
END;
$guard$;


-- ============================================================================
-- §2  DEFECT 2(a) — GIVE THE PLAN A HOME NOTHING CAN OVERWRITE
--
-- THE RECOMMENDATION, AND THE TRADE-OFF, STATED PLAINLY.
--
-- The brief asked me to STOP OVERWRITING scheduled_return_at and move the live ETA to
-- its own column. I am delivering the GOAL of that instruction -- plan, live estimate
-- and actual as three separate observable facts -- but NOT by repointing
-- scheduled_return_at, and I want the reason on the record rather than buried.
--
-- WHY NOT REPOINT IT: fourteen live functions reference scheduled_return_at (counted
-- with `pg_get_functiondef(p.oid) ~ 'scheduled_return_at'` over public/twin/ottoq).
-- Two of them only WRITE it at insert (twin.ottoq_sim_dispatch_vehicle,
-- twin.ottoq_sim_prime_deployment); one is the function §4 edits. The remaining ELEVEN
-- READ it, and they read it as "current best estimate of when this vehicle arrives":
-- ottoq_predict_arrivals, ottoq_inbound_forecast, ottoq_forecast_net_load,
-- ottoq.ottoq_sim_prearrival_contracts, ottoq_agent_board, ottoq_comms_vehicle_status,
-- ottoq_evaluate_return_need, ottoq_ingest_vehicle_signal, ottoq_cert_arm_start,
-- twin.ottoq_sim_advance_wear_counters, twin.ottoq_sim_auto_dispatch_tick.
-- Making that column mean "the plan we made hours ago" instead would silently change
-- what every arrival forecast in the system sees. That is a decision-behaviour change,
-- and this brief forbids one.
--
-- WHAT I DO INSTEAD IS STRICTLY STRONGER FOR THE STATED PURPOSE. planned_return_at is a
-- GENERATED ALWAYS ... STORED column computed from two values nothing ever updates. It
-- is not "preserved by convention" -- Postgres makes it PHYSICALLY IMPOSSIBLE to write
-- to. No future migration, no twin function, no hand-run UPDATE can erase the plan,
-- including by accident. "Stop overwriting" is a promise; a generated column is a
-- guarantee. It also needs no backfill, no trigger, and no edit to the four functions
-- that create dispatch rows -- every past row and every future row gets it for free.
--
-- If the founder later decides the forecast readers SHOULD see the frozen plan, that is
-- now a one-line change in each reader, and the plan is already sitting there waiting.
--
-- eta_refreshed_at / eta_source close the other half: today, from a dispatch row alone,
-- you cannot tell WHEN scheduled_return_at stopped being the plan or WHAT moved it.
-- Both writers now say so. I deliberately did NOT add an `eta_minutes_live` column:
-- return_eta_minutes already holds exactly that value, and adding a duplicate column
-- with no distinct writer would be building for a forecast this file is not allowed to
-- build.
--
-- CLOCK DOMAIN: planned_return_at and eta_refreshed_at are both SIM-clock. Every
-- timestamp in this ALTER derives from dispatched_at or p_sim_clock_now, never now().
-- ============================================================================
ALTER TABLE public.ottoq_vehicle_dispatches
  ADD COLUMN IF NOT EXISTS planned_return_at timestamptz
    GENERATED ALWAYS AS (dispatched_at + (planned_duration_min * INTERVAL '1 minute')) STORED;

COMMENT ON COLUMN public.ottoq_vehicle_dispatches.planned_return_at IS
  '0009. THE DISPATCH-TIME PLAN, in SIM time. Generated from dispatched_at + planned_duration_min, both of which are written once at dispatch and never updated, so this can never be overwritten by anything. This is the column to grade a forecast against. scheduled_return_at is NOT the plan: it is the current best estimate and is rewritten in flight.';

ALTER TABLE public.ottoq_vehicle_dispatches
  ADD COLUMN IF NOT EXISTS eta_refreshed_at timestamptz;

COMMENT ON COLUMN public.ottoq_vehicle_dispatches.eta_refreshed_at IS
  '0009. SIM clock at which scheduled_return_at was last moved away from the plan. NULL means it still equals planned_return_at. Read with eta_source.';

ALTER TABLE public.ottoq_vehicle_dispatches
  ADD COLUMN IF NOT EXISTS eta_source text;

COMMENT ON COLUMN public.ottoq_vehicle_dispatches.eta_source IS
  '0009. What produced the current scheduled_return_at: ''twin_eta_delay_card:<cause>'' for a modelled delay, ''policy_constant:return_eta_minutes'' for the flat return-handshake ETA. Names the provenance so an accuracy check never has to guess.';

COMMENT ON COLUMN public.ottoq_vehicle_dispatches.scheduled_return_at IS
  '0009 WARNING: this is the CURRENT BEST ESTIMATE of arrival, not the plan. It starts equal to planned_return_at and is then rewritten in flight -- first by the twin eta_delay card, then wholesale by the return handshake. Grade forecasts against planned_return_at; check eta_refreshed_at / eta_source to see whether and why this value moved.';


-- ============================================================================
-- §3  DEFECT 1 — twin.ottoq_sim_advance_service_flow
--     CREDIT ONLY THE WORK THE VEHICLE ACTUALLY HAD.
--
-- Reproduced IN FULL from the live body (md5 8797fe90392487701947ede78b93a768). The
-- only functional changes are marked `0009` inline; every other line, including the
-- three bay capability arrays, the ottoq_mark_visit_atoms_done call, the readiness
-- gate, the booking-aware admission cursors and all five OUT counters, is byte-for-byte
-- the pre-image. A non-comment diff of the two bodies shows exactly six hunks, all in
-- STEP 1, all listed in §5.
--
-- THE RULE, IN ONE SENTENCE:
--   "actually had" = the services named on this vehicle's own live visit record and
--   still outstanding when it left the bay, read BEFORE those atoms are marked done,
--   plus the one service a technician's flag explicitly names, intersected with what
--   that bay is physically able to do.
--
-- WHY VISIT ATOMS AND NOT EXECUTED ITINERARY LEGS. The atoms ARE OTTO-Q's work order
-- for the visit: they are what the assignment engine reserved the bay for, they carry
-- must_do, and they are the same array ottoq_mark_visit_atoms_done is already crediting
-- correctly two lines above. Reading them makes the wear ledger and the visit ledger
-- agree BY CONSTRUCTION -- one array, two consumers -- instead of telling two stories.
-- Itinerary legs record where the car went, not what work was open: a service-bay visit
-- opens ONE leg of leg_type 'service' whether the bay did one job or four, so a leg
-- physically cannot distinguish them. It is the weaker witness, so it is not used.
--
-- WHY THE TECHNICIAN FLAG IS ALSO EVIDENCE. STEP 2 of this same function admits a
-- vehicle to the wash/detail lane on config.flagged_issue_type ALONE:
--        OR v.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')
-- with no atom required -- and `exterior_wash` appears 0 times in the entire visit
-- ledger, so in practice the flag is how cars reach that lane. An atoms-only rule would
-- credit those cars nothing; post-0008 only an exterior_wash may reset
-- vehicle_need_profile.exterior_soil_level, so the depot would wash the car, still grade
-- it dirty, and wash it again -- a NEW lie, pointing the other way. One mapping is
-- therefore honoured, and only where the flag names the work: 'wash_due' -> exterior_wash.
-- 'minor_cosmetic' is NOT mapped: a detail does not repair cosmetic damage, and inventing
-- that equivalence would be this very defect wearing a different hat. See GAP 1.
--
-- TOTALITY. If a vehicle has no visit row and no naming flag, the credit set is empty,
-- unnest yields zero rows, and the PERFORM makes no call at all -- a no-op, never an
-- error. Nothing in this block can raise, so it can never abort decide_tick. The empty
-- case is COUNTED and reported once per call as a WARNING, because "we could not tell
-- what this car was in for" is a gap a human should see, not something to paper over
-- with a false credit.
--
-- EVENT BUDGET. Zero new events on the happy path: the runtime proof rides on the
-- twin.service_completed event that was already being written per bay exit. One extra
-- WARNING event per CALL, and only when a bay exit credited nothing.
-- ============================================================================
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_service_flow(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric, p_depot_id uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid)
 RETURNS TABLE(out_washing integer, out_servicing integer, out_staged integer, out_ready integer, out_overflow integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_wash_cap    INT;  v_svc_cap     INT;  v_deploy_cap  INT;
  v_wash_dur    NUMERIC; v_detail_dur NUMERIC; v_svc_dur NUMERIC;
  v_in_wash     INT;  v_in_svc      INT;  v_admitted    INT;
  v_order       TEXT;  v_rec         RECORD;  v_needs_svc   BOOLEAN;  v_overflow    INT := 0;
  v_hour        INT;  v_fleet       INT;  v_deployed    INT;  v_target      INT;
  v_pressure    BOOLEAN := FALSE;  v_fasttracked INT := 0;  v_recharged   INT := 0;
  v_floor       NUMERIC;  v_end_ts      TIMESTAMPTZ;  v_feed_sim BOOLEAN := TRUE;
  -- DEPARTURE READINESS GATE (2026-08-02)
  v_ncand       INT := 0;  v_gate_on BOOLEAN := TRUE;
  v_patience_dep NUMERIC;  v_hardcap NUMERIC;  v_relcap INT;
  v_held        INT := 0;  v_esc_gate INT := 0;  v_override INT := 0;
  -- 0009 (DEFECT 1) HONEST COMPLETION CREDIT. Four working sets and three counters.
  -- v_bay_caps    = what this bay is PHYSICALLY ABLE to do (unchanged from the pre-image).
  -- v_outstanding = what THIS VEHICLE actually still had open on THIS visit, read before
  --                 the atoms are marked done.
  -- v_flag_svcs   = the technician flag that admitted it, where the flag names the work.
  -- v_credit      = v_bay_caps INTERSECT (v_outstanding UNION v_flag_svcs)  <-- the fix.
  v_bay_caps    TEXT[];  v_outstanding TEXT[];  v_flag_svcs TEXT[];  v_credit TEXT[];
  v_credited    INT := 0;  v_suppressed  INT := 0;  v_credit_none INT := 0;
BEGIN
  v_wash_cap   := ottoq_sim_lane_capacity(p_sim_run_id, 'cleaning_staff', 3);
  v_svc_cap    := ottoq_sim_lane_capacity(p_sim_run_id, 'service_staff', 2);
  v_deploy_cap := ottoq_sim_lane_capacity(p_sim_run_id, 'deploy_staff', 20);
  v_wash_dur   := ottoq_sim_service_minutes(p_sim_run_id, 'wash_time', 9);
  v_detail_dur := ottoq_sim_service_minutes(p_sim_run_id, 'detail_time', 25);
  v_svc_dur    := ottoq_sim_service_minutes(p_sim_run_id, 'maintenance_time', 40);
  v_floor      := ottoq_policy_get(p_sim_run_id, 'deploy_floor_soc', 80);
  SELECT COALESCE(d.feed_mode,'sim')='sim' INTO v_feed_sim FROM depots d WHERE d.id = p_depot_id;
  v_feed_sim := COALESCE(v_feed_sim, TRUE);

  SELECT COALESCE((knobs #>> ARRAY['_policy','scheduling_algorithm']), 'calibrated')
    INTO v_order FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id;
  v_order := COALESCE(v_order, 'calibrated');

  -- ───── STEP 0: re-charge stranded under-floor vehicles (deadlock breaker) ─────
  FOR v_rec IN
    SELECT v.id FROM vehicles v
     WHERE v.home_depot_id = p_depot_id AND v.category='autonomous'
       AND v.current_state IN ('charge_complete_holding','staged_awaiting_service','staged_for_departure')
       AND v.current_soc < v_floor
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
              WHERE n.vehicle_id = v.id AND n.sim_run_id = p_sim_run_id
                AND a->>'svc' = 'charge' AND COALESCE(a->>'status','open') <> 'done')
       AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
              WHERE d.vehicle_id = v.id AND d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning'))
  LOOP
    -- DOCTRINE (Chase 2026-07-28): never bounce a vehicle to the gate.
    -- SPLIT 2026-07-29: the CHOICE (re-queue for charge + pick/hold/reserve the temp
    -- stall) moved to ottoq_replan_stranded_undercharge. The twin only executes the
    -- returned plan: the flag write and the physical occupancy write.
    DECLARE v_dec jsonb; v_s uuid;
    BEGIN
      v_dec := ottoq_replan_stranded_undercharge(v_rec.id, p_sim_run_id, p_depot_id, p_sim_clock_now);

      UPDATE vehicles
         SET current_state = 'staged_awaiting_service'::vehicle_state,
             last_state_change = p_sim_clock_now,
             config = jsonb_set(config, '{svc_step}',
                                to_jsonb(COALESCE(v_dec->>'svc_step', 'need_charge')))
       WHERE id = v_rec.id;

      v_s := NULLIF(v_dec->>'stall_id', '')::uuid;
      IF v_s IS NOT NULL THEN
        UPDATE vehicles SET current_stall_id = v_s WHERE id = v_rec.id;
        UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
         WHERE id = v_s;
      END IF;
    END;
    v_recharged := v_recharged + 1;
  END LOOP;
  IF v_recharged > 0 THEN
    PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow', p_event_type := 'twin.recharge_stranded',
      p_entity_type := 'depot', p_entity_id := p_depot_id,
      p_payload := jsonb_build_object('recharged', v_recharged, 'floor', v_floor),
      p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END IF;

  -- ───── STEP 1: complete in-progress services (elapsed timer OR null-timer stuck) ─────
  FOR v_rec IN
    SELECT id, current_state, config FROM vehicles
     WHERE home_depot_id = p_depot_id
       AND current_state IN ('in_wash_bay','in_detail_bay','in_service_bay')
       AND ( COALESCE((config->>'service_done')::boolean, FALSE)
          OR ( v_feed_sim AND (
                 (config->>'service_ends_at') IS NULL
              OR (config->>'service_ends_at')::timestamptz <= p_sim_clock_now ) ) )
  LOOP
    v_end_ts := COALESCE((v_rec.config->>'service_ends_at')::timestamptz, p_sim_clock_now);
    -- T3 RENDER CONTRACT: the drive OUT of the bay to staging. Origin left NULL so the
    -- emitter resolves it from leg history to the bay the entry leg targeted, closing
    -- the route. Destination is a render target only; staged_awaiting_service holds no
    -- stall. Never allowed to abort the transition.
    BEGIN
      PERFORM ottoq_itin_travel_leg(p_sim_run_id, p_depot_id, v_rec.id, NULL,
        (SELECT s.id FROM stalls s
          WHERE s.depot_id = p_depot_id AND s.stall_type = 'staging'::stall_type
          ORDER BY (s.current_vehicle_id IS NOT NULL), s.stall_code
          OFFSET (abs(hashtext(v_rec.id::text)) % 20) LIMIT 1),
        p_sim_clock_now,
        CASE WHEN v_rec.current_state IN ('in_wash_bay','in_detail_bay')
             THEN 'exit_wash_to_staging' ELSE 'exit_service_to_staging' END,
        'twin_service_flow');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (bay exit): %', SQLERRM;
    END;
    IF v_rec.current_state IN ('in_wash_bay','in_detail_bay') THEN
      v_needs_svc := COALESCE((v_rec.config->>'flagged_issue')::boolean, FALSE);
      UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock_now,
             config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb(CASE WHEN v_needs_svc THEN 'need_service' ELSE 'need_deploy' END)), '{service_ends_at}', 'null'::jsonb) - 'service_done' - 'awaiting_external_completion'
       WHERE id = v_rec.id;
    ELSE
      UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock_now,
             config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('need_deploy'::text)), '{service_ends_at}', 'null'::jsonb) - 'service_done' - 'awaiting_external_completion'
       WHERE id = v_rec.id;
    END IF;
    PERFORM ottoq_itin_leg_close(p_sim_run_id, v_rec.id, ARRAY['wash','detail','service'], v_end_ts);

    -- ═══════ 0009 FIX (DEFECT 1) — CREDIT ONLY THE WORK THIS VEHICLE ACTUALLY HAD ═══════
    -- WAS: every bay exit credited a FIXED array regardless of why the car was in the bay,
    -- so a vehicle in for ONE job was recorded as having had up to FOUR. The exact pre-image
    -- line is quoted in this file's header, not here, so §POST can grep the live body for it.
    -- Registered as GAP 5 by 0005 and left open; this is that pass.
    --
    -- STEP A — the bay's CAPABILITY set. Byte-for-byte the three arrays from the pre-image.
    -- 0009 does not retune what a bay can do; it only stops claiming the bay did all of it.
    v_bay_caps := CASE WHEN v_rec.current_state = 'in_wash_bay' THEN ARRAY['exterior_wash','sensor_clean']
                       WHEN v_rec.current_state = 'in_detail_bay' THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
                       ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END;

    -- STEP B — what the vehicle ACTUALLY had outstanding, from its own visit record.
    -- ORDER IS LOAD-BEARING: this must be read BEFORE ottoq_mark_visit_atoms_done below,
    -- which flips these same atoms to 'done'. Read it after and the answer is always empty.
    -- The visit selector is IDENTICAL to ottoq_mark_visit_atoms_done's own (vehicle +
    -- status open/in_progress + newest created_at), so the wear ledger and the visit ledger
    -- can never disagree about WHICH visit they are discussing. "Outstanding" uses the
    -- depot's own existing definition, already live in STEP 2 of this same function:
    --     COALESCE(status,'pending') NOT IN ('done','cancelled','skipped')
    -- No new vocabulary is invented anywhere in this block.
    SELECT COALESCE(array_agg(DISTINCT a->>'svc'), ARRAY[]::text[])
      INTO v_outstanding
      FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.visit_id = (SELECT n2.visit_id FROM ottoq_visit_needs n2
                          WHERE n2.vehicle_id = v_rec.id
                            AND n2.status IN ('open','in_progress')
                          ORDER BY n2.created_at DESC LIMIT 1)
       AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped');
    v_outstanding := COALESCE(v_outstanding, ARRAY[]::text[]);

    -- STEP C — THE TECHNICIAN FLAG IS REAL WORK TOO, AND IGNORING IT WOULD BE A NEW LIE.
    -- STEP 2 of this function admits a vehicle to the wash/detail lane on
    -- `flagged_issue_type` ALONE, with no atom required. Atoms-only credit would leave that
    -- car's body soil never reset -- and post-0008 ONLY an exterior_wash may reset it -- so
    -- the depot would wash it, still grade it dirty, and wash it again, forever. ONE mapping,
    -- and only where the flag NAMES the work: 'wash_due' -> exterior_wash.
    -- 'minor_cosmetic' is deliberately NOT mapped (GAP 1): a detail does not repair cosmetic
    -- damage, and inventing that equivalence would be the same disease this file removes.
    v_flag_svcs := CASE WHEN v_rec.config->>'flagged_issue_type' = 'wash_due'
                        THEN ARRAY['exterior_wash'] ELSE ARRAY[]::text[] END;

    -- STEP D — THE CREDIT SET: what this bay CAN do  ∩  what this vehicle ACTUALLY had.
    -- If a vehicle genuinely had all four due it still gets all four: the bug being fixed is
    -- unconditionality, not breadth.
    v_credit := ARRAY(SELECT t.svc FROM unnest(v_bay_caps) AS t(svc)
                       WHERE t.svc = ANY(v_outstanding || v_flag_svcs));

    PERFORM ottoq_mark_visit_atoms_done(v_rec.id,
      CASE WHEN v_rec.current_state = 'in_wash_bay' THEN ARRAY['exterior_wash','sensor_clean']
           WHEN v_rec.current_state = 'in_detail_bay' THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
           ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END, v_end_ts);
    -- wear truth follows completion (mark_serviced was dead: soil/PM/calibration never reset)
    -- 0009: the fixed array is gone. One call per service the vehicle REALLY had -- the same
    -- one-real-atom-per-call shape 0005 §3 uses on the non-bay path, and the same shape the
    -- real-telemetry seam public.ottoq_ingest_service_complete uses (FOREACH over the codes
    -- the OEM actually reported). An empty credit set yields zero rows from unnest, so the
    -- PERFORM makes NO call at all: total, never an error, never able to abort decide_tick.
    -- ottoq_mark_visit_atoms_done above is left BYTE-FOR-BYTE UNCHANGED on purpose. It is
    -- already correctly intersected -- it only touches atoms that exist on the visit -- so it
    -- was never part of this defect, and narrowing it would be scope creep.
    PERFORM ottoq_wear_mark_serviced(v_rec.id, p_sim_run_id, s, v_end_ts)
      FROM unnest(v_credit) AS s;
    v_credited    := v_credited + COALESCE(array_length(v_credit, 1), 0);
    v_suppressed  := v_suppressed + COALESCE(array_length(v_bay_caps, 1), 0)
                                  - COALESCE(array_length(v_credit, 1), 0);
    IF COALESCE(array_length(v_credit, 1), 0) = 0 THEN v_credit_none := v_credit_none + 1; END IF;
    PERFORM ottoq_record_event(p_actor_type := 'av_vehicle', p_actor_id := v_rec.id::text, p_event_type := 'twin.service_completed',
      p_entity_type := 'vehicle', p_entity_id := v_rec.id, p_payload := jsonb_build_object('from', v_rec.current_state, 'self_healed', (v_rec.config->>'service_ends_at') IS NULL,
        -- 0009 RUNTIME PROOF, carried on an event that was already being written, so the
        -- write-rate budget (~852-960 B/event) is not disturbed by a new event type.
        'bay_capable', to_jsonb(v_bay_caps), 'credited', to_jsonb(v_credit),
        'suppressed_n', COALESCE(array_length(v_bay_caps,1),0) - COALESCE(array_length(v_credit,1),0)),
      p_severity := 'debug', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END LOOP;

  -- 0009: ONE summary event per CALL, and only when a bay exit credited NOTHING -- i.e. a
  -- vehicle sat in a bay yet no outstanding work and no naming flag could be found for it.
  -- That is a gap a human should see, not something to paper over with a false credit.
  -- Silent in the normal case, so the event budget is unchanged on the happy path.
  IF v_credit_none > 0 THEN
    PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow',
      p_event_type := 'twin.bay_credit_none', p_entity_type := 'depot', p_entity_id := p_depot_id,
      p_payload := jsonb_build_object('exits_crediting_nothing', v_credit_none,
        'services_credited', v_credited, 'services_suppressed', v_suppressed,
        'note', 'a bay exit found no outstanding work and no naming flag; nothing was credited, which is the honest answer -- investigate why the car was admitted'),
      p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END IF;

  -- ───── STEP 1.5: deploy-pressure fast-track past OPTIONAL wash ─────
  v_hour     := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_fleet    := (SELECT COUNT(*) FROM vehicles WHERE category='autonomous' AND home_depot_id=p_depot_id);
  v_deployed := (SELECT COUNT(*) FROM ottoq_vehicle_dispatches WHERE sim_run_id=p_sim_run_id AND status IN ('active','returning'));
  v_target   := FLOOR(v_fleet * ottoq_deploy_target_fraction(v_hour, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',0.55)));
  v_pressure := v_deployed < v_target;
  IF v_pressure THEN
    FOR v_rec IN
      SELECT v.id FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.category='autonomous'
         AND v.current_state = 'charge_complete_holding' AND v.current_soc >= v_floor
         AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
             WHERE n.vehicle_id = v.id AND n.sim_run_id = p_sim_run_id
               AND (a->>'must_do')::boolean = TRUE AND a->>'svc' NOT IN ('charge','readiness_check')
               AND COALESCE(a->>'status','open') <> 'done')
    LOOP
      UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock_now,
             config = jsonb_set(config, '{svc_step}', to_jsonb('need_deploy'::text)) WHERE id = v_rec.id;
      v_fasttracked := v_fasttracked + 1;
    END LOOP;
    IF v_fasttracked > 0 THEN
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow', p_event_type := 'twin.deploy_pressure_fasttrack',
        p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_payload := jsonb_build_object('fasttracked', v_fasttracked, 'deployed', v_deployed, 'target', v_target, 'hour_cst', v_hour),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END IF;
  END IF;

  -- ───── STEP 2: admit waiting vehicles into lanes (capacity-gated, ordered) ─────
  SELECT COUNT(*) INTO v_in_wash FROM vehicles WHERE home_depot_id = p_depot_id AND current_state IN ('in_wash_bay','in_detail_bay');
  v_admitted := 0;
  FOR v_rec IN
    -- M1_need_gated_wash: admit ONLY vehicles that actually have wash/detail
    -- work outstanding. Previously any holding vehicle was admitted to fill capacity.
    -- BOOKING-AWARE (2026-08-02), same reasoning as the service cursor below: the wash
    -- lane also ignored the forward calendar and picked a bay by OFFSET n % 3. The need
    -- gate and the ordering expression are preserved EXACTLY; a booking-holder key is
    -- prepended, and the vehicle's own reserved bay is surfaced for the travel leg.
    SELECT q.id, q.config, q.booked_stall FROM (
      SELECT v.id, v.config,
             (SELECT b2.stall_id
                FROM ottoq_stall_bookings b2 JOIN stalls sb ON sb.id = b2.stall_id
               WHERE b2.sim_run_id = p_sim_run_id AND b2.vehicle_id = v.id
                 AND b2.state = 'held' AND b2.purpose IN ('wash','detail')
                 AND sb.depot_id = p_depot_id AND sb.stall_type = 'wash_bay'::stall_type
                 AND sb.status NOT IN ('maintenance','closed')
                 AND lower(b2.during) <= p_sim_clock_now AND upper(b2.during) > p_sim_clock_now
               ORDER BY lower(b2.during) LIMIT 1) AS booked_stall,
             CASE v_order WHEN 'soc_optimized' THEN v.current_soc WHEN 'priority_weighted' THEN -COALESCE((v.config->>'seed_idx')::numeric, 0) ELSE EXTRACT(EPOCH FROM v.last_state_change) END AS ord
        FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.current_state = 'charge_complete_holding'
         AND (EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                       WHERE n.vehicle_id = v.id AND n.status IN ('open','in_progress')
                         AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
              OR v.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))
    ) q
     ORDER BY (q.booked_stall IS NULL), q.ord
     -- wash_supervisor_pool: the 8-10 min exterior wash needs a supervisor as well
     -- as a free lane (founder spec: "a couple of wash bay supervisors").
     LIMIT GREATEST(0, LEAST(v_wash_cap, ottoq_depot_staffing_count(p_depot_id,'wash_supervisor')) - v_in_wash)
  LOOP
    -- T3 RENDER CONTRACT: the drive to the wash building. Render-only; picks a
    -- door for the leg, claims nothing. Origin left NULL on purpose (it is NULL on
    -- every path into charge_complete_holding) so the emitter resolves it from leg history.
    BEGIN
      PERFORM ottoq_itin_travel_leg(p_sim_run_id, p_depot_id, v_rec.id, NULL,
        COALESCE(v_rec.booked_stall,
        (SELECT s.id FROM stalls s WHERE s.depot_id = p_depot_id
          AND s.stall_type = 'wash_bay'::stall_type
          ORDER BY (s.status IN ('maintenance','closed')), (s.current_vehicle_id IS NOT NULL), (EXISTS (SELECT 1 FROM ottoq_stall_bookings b3 WHERE b3.stall_id = s.id AND b3.sim_run_id = p_sim_run_id AND b3.state IN ('held','active','done') AND b3.during && tstzrange(p_sim_clock_now, p_sim_clock_now + make_interval(mins => GREATEST(v_wash_dur, v_detail_dur)::int), '[)'))), s.stall_code LIMIT 1)),
        p_sim_clock_now, 'taxi_to_wash', 'twin_service_flow');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (wash): %', SQLERRM;
    END;
    UPDATE vehicles
       SET current_state = (CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')) THEN 'in_detail_bay' ELSE 'in_wash_bay' END)::vehicle_state,
           last_state_change = p_sim_clock_now,
           config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('washing'::text)), '{service_ends_at}', to_jsonb((p_sim_clock_now +
               ((CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))
                      THEN v_detail_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'detail_time', v_rec.id::text || ':' || p_sim_clock_now::text, p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0)
                      ELSE v_wash_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'wash_time', v_rec.id::text || ':' || p_sim_clock_now::text, p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0) END) || ' minutes')::interval)::text))
     WHERE id = v_rec.id;
    IF v_rec.booked_stall IS NOT NULL THEN
      UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
       WHERE id = v_rec.booked_stall
         AND (current_vehicle_id IS NULL OR current_vehicle_id = v_rec.id);
      IF FOUND THEN
        UPDATE vehicles SET current_stall_id = v_rec.booked_stall WHERE id = v_rec.id;
      END IF;
    END IF;
    PERFORM ottoq_itin_leg_open(p_sim_run_id, p_depot_id, v_rec.id, p_sim_clock_now,
      CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')) THEN 'detail' ELSE 'wash' END,
      NULL, (SELECT (config->>'service_ends_at')::timestamptz FROM vehicles WHERE id = v_rec.id),
      jsonb_build_object('kind', 'distribution', 'corpus', 'service_ops', 'base_min', CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')) THEN v_detail_dur ELSE v_wash_dur END),
      'service_flow');
    v_admitted := v_admitted + 1;
  END LOOP;

  SELECT COUNT(*) INTO v_in_svc FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'in_service_bay';
  -- BOOKING-AWARE ADMISSION (2026-08-02). This cursor was blind to the forward calendar:
  -- it ordered purely by last_state_change and sent the car to an ARBITRARY bay
  -- (OFFSET n % 2), so a vehicle holding a live reservation got no priority and was often
  -- not even routed to the bay it had been promised. Reservations then rotted to
  -- no_show_grace_elapsed (37.3% of bay bookings). It now surfaces the vehicle's own open
  -- booking and admits booking-holders FIRST. Capacity is still staff-gated byte-for-byte:
  -- this changes WHO gets the slot and WHICH bay, never HOW MANY.
  FOR v_rec IN
    SELECT * FROM (
      SELECT v.id,
             (SELECT b2.stall_id
                FROM ottoq_stall_bookings b2 JOIN stalls sb ON sb.id = b2.stall_id
               WHERE b2.sim_run_id = p_sim_run_id AND b2.vehicle_id = v.id
                 AND b2.state = 'held' AND b2.purpose = 'service'
                 AND sb.depot_id = p_depot_id AND sb.stall_type = 'service_bay'::stall_type
                 AND sb.status NOT IN ('maintenance','closed')
                 AND lower(b2.during) <= p_sim_clock_now AND upper(b2.during) > p_sim_clock_now
               ORDER BY lower(b2.during) LIMIT 1) AS booked_stall,
             v.last_state_change AS lsc
        FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.current_state = 'staged_awaiting_service'
         AND v.config->>'svc_step' = 'need_service'
    ) q
     ORDER BY (q.booked_stall IS NULL), q.lsc LIMIT GREATEST(0, v_svc_cap - v_in_svc)
  LOOP
    -- T3 RENDER CONTRACT: the drive to the service bays (OFFICE-01 complex, far west).
    -- Render-only; claims no bay. Capacity remains staff-gated exactly as before.
    BEGIN
      PERFORM ottoq_itin_travel_leg(p_sim_run_id, p_depot_id, v_rec.id, NULL,
        COALESCE(v_rec.booked_stall,
        (SELECT s.id FROM stalls s WHERE s.depot_id = p_depot_id
          AND s.stall_type = 'service_bay'::stall_type
          ORDER BY (s.status IN ('maintenance','closed')), (s.current_vehicle_id IS NOT NULL), (EXISTS (SELECT 1 FROM ottoq_stall_bookings b3 WHERE b3.stall_id = s.id AND b3.sim_run_id = p_sim_run_id AND b3.state IN ('held','active','done') AND b3.during && tstzrange(p_sim_clock_now, p_sim_clock_now + make_interval(mins => v_svc_dur::int), '[)'))), s.stall_code LIMIT 1)),
        p_sim_clock_now, 'taxi_to_service', 'twin_service_flow');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (service): %', SQLERRM;
    END;
    UPDATE vehicles SET current_state = 'in_service_bay'::vehicle_state, last_state_change = p_sim_clock_now,
           config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('servicing'::text)), '{service_ends_at}', to_jsonb((p_sim_clock_now + ((v_svc_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'maintenance_time', v_rec.id::text || ':' || p_sim_clock_now::text, p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0)) || ' minutes')::interval)::text))
     WHERE id = v_rec.id;
    -- HONOUR THE RESERVATION PHYSICALLY. Claiming the booked bay is what lets
    -- ottoq.ottoq_activate_present_bookings flip the row held -> active next tick -- the
    -- RUNTIME proof the reservation was kept rather than silently expired. Guarded so it
    -- can never steal a bay another vehicle is standing in, so it cannot double-book.
    IF v_rec.booked_stall IS NOT NULL THEN
      UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
       WHERE id = v_rec.booked_stall
         AND (current_vehicle_id IS NULL OR current_vehicle_id = v_rec.id);
      IF FOUND THEN
        UPDATE vehicles SET current_stall_id = v_rec.booked_stall WHERE id = v_rec.id;
      END IF;
    END IF;
    PERFORM ottoq_itin_leg_open(p_sim_run_id, p_depot_id, v_rec.id, p_sim_clock_now, 'service', NULL,
      (SELECT (config->>'service_ends_at')::timestamptz FROM vehicles WHERE id = v_rec.id),
      jsonb_build_object('kind', 'distribution', 'corpus', 'service_ops', 'base_min', v_svc_dur), 'service_flow');
  END LOOP;

  -- ═════ STEP 3: RELEASE TO DEPARTURE — READINESS GATE (2026-08-02) ═════
  -- DOCTRINE (full-service visit): a visit is ATOMIC. 'staged_for_departure' must mean
  -- "this vehicle would be dispatched if asked" — nothing weaker. Before this gate the
  -- transition was UNCONDITIONAL, so vehicles at 28-29% SoC were staged as READY.
  -- That is not merely cosmetic: 'staged_for_departure' is NOT in ottoq_decide_tick's
  -- charging cursor (which reads 'arrived_at_gate' and 'staged_awaiting_service'), so
  -- staging an undercharged car REMOVED IT FROM THE CHARGE QUEUE, while
  -- ottoq_plan_dispatch_tick(deploy_plan) would refuse it anyway (soc >= 80 + no open
  -- must-do work). Dead inventory that could never leave and could never be fixed.
  --
  -- THE GATE IS THE DISPATCHER'S OWN ADMISSION PREDICATE, MOVED ONE STEP EARLIER.
  -- It is therefore never stricter than what the dispatcher accepts, so it cannot
  -- create a new deadlock class:
  --     soc >= ready_soc   AND   no open must-do work left in this run's visit
  -- ready_soc comes from the NEEDS CARD (ottoq_vehicle_needs_card.min_ready_soc_pct),
  -- not a bare SoC literal, so it follows the per-vehicle need profile; it falls back
  -- to the deploy_floor_soc policy when the card has no row for the vehicle — a TOTAL
  -- function: a missing card must never block a vehicle. The card also supplies
  -- must_do_now / fits_window / minutes_to_deploy as EVIDENCE on the hold receipt.
  -- The card is read ONCE per call for the whole candidate set: the view materialises
  -- the entire fleet regardless of its WHERE clause (measured 192 ms for a
  -- single-vehicle probe), so a per-vehicle read would cost seconds per tick.
  --
  -- NOT AN ENERGY GATE. Vehicle-first doctrine is untouched — nothing is held back for
  -- price or grid reasons. This is READINESS only: the vehicle is not finished.
  --
  -- ESCAPE HATCHES — nothing can sit forever:
  --   0. policy deploy_ready_gate_enabled = 0  → gate off, pre-2026-08-02 behaviour.
  --   1. a held vehicle is ROUTED TO THE REMEDY, never parked: svc_step := 'need_charge'
  --      (ottoq_decide_tick's charge cursor consumes staged_awaiting_service on SoC
  --      alone — no atom required) or 'need_service' (STEP 2 above consumes it).
  --      Both consumers verified in live source. The loop closes: charge →
  --      charge_complete_holding → STEP 1.5/STEP 2 → need_deploy → re-gated.
  --   2. deploy_gate_patience_min (default 45 sim-min) → config.flagged_issue +
  --      flagged_issue_type='deploy_gate_stuck' so a technician sees it, counted in a
  --      WARNING summary event.
  --   3. deploy_gate_hard_cap_min (default 240 sim-min — longer than any bounded demo)
  --      → released anyway, stamped config.deploy_gate_override with a CRITICAL audit
  --      event. Loud and countable, never silent.
  -- Event budget: ONE summary event per call (plus one per rare override), not one per
  -- vehicle — event-write amplification is the known tick-cost driver.
  v_gate_on      := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_ready_gate_enabled',1),1) > 0;
  v_patience_dep := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_gate_patience_min',45),45);
  v_hardcap      := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_gate_hard_cap_min',240),240);
  v_relcap       := GREATEST(1, CEIL(v_deploy_cap * COALESCE(p_tick_minutes, 30) / 30.0))::int;
  v_admitted := 0;

  SELECT COUNT(*) INTO v_ncand FROM vehicles v
   WHERE v.home_depot_id = p_depot_id AND v.current_state = 'staged_awaiting_service'
     AND v.config->>'svc_step' = 'need_deploy';

  IF v_ncand > 0 THEN
    FOR v_rec IN
      WITH cand AS (
        SELECT v.id, v.current_soc, v.config, v.last_state_change
          FROM vehicles v
         WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
           AND v.current_state = 'staged_awaiting_service'
           AND v.config->>'svc_step' = 'need_deploy'
      ), card AS (
        SELECT c.vehicle_id, c.min_ready_soc_pct, c.must_do_now, c.fits_window, c.minutes_to_deploy
          FROM ottoq_vehicle_needs_card c
         WHERE v_gate_on
      ), ev AS (
        SELECT cd.id, cd.current_soc, cd.config, cd.last_state_change,
               GREATEST(v_floor, COALESCE(k.min_ready_soc_pct, v_floor)) AS ready_soc,
               COALESCE(k.must_do_now, '{}'::text[])                     AS card_must,
               k.fits_window, k.minutes_to_deploy,
               -- IDENTICAL predicate to ottoq_plan_dispatch_tick(deploy_plan)
               EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                        WHERE vn.vehicle_id = cd.id AND vn.sim_run_id = p_sim_run_id
                          AND vn.status IN ('open','in_progress')
                          AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE COALESCE((a->>'must_do')::boolean,false) = true
                                         AND a->>'svc' <> 'readiness_check'
                                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')))
                                                                          AS work_open
          FROM cand cd LEFT JOIN card k ON k.vehicle_id = cd.id
      )
      SELECT ev.*,
             ((NOT v_gate_on) OR (ev.current_soc >= ev.ready_soc AND NOT ev.work_open)) AS ready
        FROM ev
       ORDER BY (CASE WHEN (NOT v_gate_on) OR (ev.current_soc >= ev.ready_soc AND NOT ev.work_open) THEN 0 ELSE 1 END),
                ev.last_state_change, ev.id
    LOOP
      IF v_rec.ready THEN
        -- deploy_cap_per_minute: v_deploy_cap is calibrated as releases per 30-MINUTE
        -- tick; rescale to the real tick length so throughput cannot change with tick size.
        IF v_admitted < v_relcap THEN
          UPDATE vehicles SET current_state = 'staged_for_departure'::vehicle_state, last_state_change = p_sim_clock_now,
                 config = jsonb_set(config, '{svc_step}', to_jsonb('ready'::text)) - 'deploy_gate'
           WHERE id = v_rec.id;
          v_admitted := v_admitted + 1;
        END IF;   -- over cap: stays need_deploy, retried next tick (unchanged behaviour)
      ELSE
        DECLARE
          v_since TIMESTAMPTZ; v_reason TEXT; v_missing TEXT[]; v_held_min NUMERIC; v_remedy TEXT;
        BEGIN
          v_since    := COALESCE((v_rec.config #>> '{deploy_gate,held_since}')::timestamptz, p_sim_clock_now);
          v_held_min := GREATEST(0, EXTRACT(EPOCH FROM (p_sim_clock_now - v_since))/60.0);
          v_reason   := CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN 'soc_below_ready' ELSE 'must_do_work_open' END;
          v_remedy   := CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN 'need_charge'     ELSE 'need_service' END;
          v_missing  := (CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN ARRAY['charge'] ELSE ARRAY[]::text[] END)
                        || COALESCE(v_rec.card_must, ARRAY[]::text[]);

          IF v_held_min >= v_hardcap THEN
            UPDATE vehicles SET current_state = 'staged_for_departure'::vehicle_state, last_state_change = p_sim_clock_now,
                   config = (jsonb_set(config, '{svc_step}', to_jsonb('ready'::text)) - 'deploy_gate')
                          || jsonb_build_object('deploy_gate_override', jsonb_build_object(
                               'at', p_sim_clock_now, 'held_min', round(v_held_min,1), 'reason', v_reason,
                               'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                               'missing', to_jsonb(v_missing), 'hard_cap_min', v_hardcap))
             WHERE id = v_rec.id;
            v_override := v_override + 1;
            PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'deploy_ready_gate',
              p_event_type := 'twin.deploy_gate_override', p_entity_type := 'vehicle', p_entity_id := v_rec.id,
              p_payload := jsonb_build_object('held_min', round(v_held_min,1), 'hard_cap_min', v_hardcap,
                'reason', v_reason, 'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                'missing', to_jsonb(v_missing),
                'note', 'escape hatch 3: released past the readiness gate so the twin cannot wedge; this is a DEFECT to investigate, not a normal path'),
              p_severity := 'critical', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
          ELSE
            UPDATE vehicles
               SET config = jsonb_set(config, '{svc_step}', to_jsonb(v_remedy))
                          || jsonb_build_object('deploy_gate', jsonb_build_object(
                               'held_since', v_since, 'held_min', round(v_held_min,1),
                               'reason', v_reason, 'remedy', v_remedy,
                               'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                               'missing', to_jsonb(v_missing),
                               'card_must_do_now', to_jsonb(COALESCE(v_rec.card_must, ARRAY[]::text[])),
                               'fits_window', v_rec.fits_window,
                               'minutes_to_deploy', v_rec.minutes_to_deploy))
                          || CASE WHEN v_held_min >= v_patience_dep
                                  THEN jsonb_build_object('flagged_issue', true,
                                                          'flagged_issue_type', 'deploy_gate_stuck')
                                  ELSE '{}'::jsonb END
             WHERE id = v_rec.id;   -- last_state_change deliberately UNTOUCHED (queue order + patience metric)
            v_held := v_held + 1;
            IF v_held_min >= v_patience_dep THEN v_esc_gate := v_esc_gate + 1; END IF;
          END IF;
        END;
      END IF;
    END LOOP;

    IF v_held > 0 OR v_override > 0 THEN
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'deploy_ready_gate',
        p_event_type := 'twin.deploy_gate_summary', p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_payload := jsonb_build_object('candidates', v_ncand, 'released', v_admitted,
          'held', v_held, 'escalated', v_esc_gate, 'overridden', v_override,
          'floor', v_floor, 'patience_min', v_patience_dep, 'hard_cap_min', v_hardcap,
          'gate_enabled', v_gate_on),
        p_severity := CASE WHEN v_override > 0 THEN 'critical'
                           WHEN v_esc_gate > 0 THEN 'warning' ELSE 'info' END,
        p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END IF;
  END IF;

  -- overflow now counts need_charge too: a vehicle held by the readiness gate is still
  -- waiting in staging and must not vanish from the queue telemetry.
  SELECT COUNT(*) INTO v_overflow FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'staged_awaiting_service' AND config->>'svc_step' IN ('need_service','need_deploy','need_charge');
  IF v_overflow > 0 THEN
    DECLARE v_patience NUMERIC := GREATEST(1, 10 + ottoq_apply_profile(p_sim_run_id, 'queue_patience', 0, 0)); v_escalated INT;
    BEGIN
      SELECT COUNT(*) INTO v_escalated FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'staged_awaiting_service'
         AND config->>'svc_step' IN ('need_service','need_deploy','need_charge') AND EXTRACT(EPOCH FROM (p_sim_clock_now - last_state_change))/60.0 > v_patience;
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow', p_event_type := 'twin.staging_overflow',
        p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_payload := jsonb_build_object('overflow', v_overflow, 'escalated', v_escalated, 'patience_min', ROUND(v_patience,1), 'wash_cap', v_wash_cap, 'svc_cap', v_svc_cap, 'deploy_cap', v_deploy_cap, 'gate_held', v_held),
        p_severity := CASE WHEN v_escalated > 0 THEN 'warning' ELSE 'info' END, p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END;
  END IF;

  out_washing   := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state IN ('in_wash_bay','in_detail_bay'));
  out_servicing := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state='in_service_bay');
  out_staged    := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state='staged_awaiting_service');
  out_ready     := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state='staged_for_departure');
  out_overflow  := v_overflow;
  RETURN NEXT;
END;
$function$;


-- ============================================================================
-- §4  DEFECT 2(a) — twin.ottoq_sim_advance_deployed_telemetry
--     MAKE THE REWRITE OF scheduled_return_at VISIBLE AND ATTRIBUTED.
--
-- Reproduced IN FULL from the live body (md5 595d96841d68f63714e153faa7dfddf0). Two
-- hunks change, both marked `0009` inline; nothing else moves. In particular the SoC
-- arithmetic, the incident path, the return-need evaluation, ottoq_book_appointment,
-- the deferral gate, the arrival branch and the miles_driven roll-up are all byte-for-byte.
--
-- THE ARITHMETIC OF scheduled_return_at IS UNCHANGED. Both writers still move it by
-- exactly the same amount they moved it before, so no arrival time and no forecast
-- reader sees a different number. What is added is the RECORD: eta_refreshed_at (SIM
-- clock), eta_source (what produced it), and -- on the return handshake -- the plan, the
-- live estimate and their difference written into return_evidence at the exact moment
-- of the refresh, so no later reader has to reconstruct what the plan had been.
--
-- ⚠️ DEFECT 2(b) IS DECLINED, NOT DEFERRED-WITH-A-WINK. ottoq_return_eta_minutes is left
-- BYTE-FOR-BYTE UNTOUCHED and is not even re-created by this file. The twin models no
-- position (0 of 5,523 telemetry packets carry a coordinate), no route and no remaining
-- distance, and the arrival is DEFINED as returning_started_at + return_eta_minutes --
-- so the ETA causes the arrival rather than predicting it, and any "better" ETA would be
-- graded against an outcome it authored. There is nothing real to compute from. The full
-- evidence and the list of what would have to exist first are in the PREMISE section
-- above under "CAN ETA PART (b) BE DONE?".
-- ============================================================================
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_deployed_telemetry(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric)
 RETURNS TABLE(out_vehicle_id uuid, out_action text, out_new_soc numeric, out_new_state text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_ret_should boolean; v_ret_trigger text; v_ret_urgency text; v_ret_ev jsonb;
  v_ret_deferrable boolean; v_book jsonb; v_eta_min numeric;
  v_dispatch        RECORD;
  v_active_frac     NUMERIC;
  v_avg_speed       NUMERIC;
  v_discharge_kw    NUMERIC;
  v_kwh_consumed    NUMERIC;
  v_miles           NUMERIC;
  v_new_soc         NUMERIC;
  v_seed            BIGINT;
  v_salt            TEXT;
  v_dtc             TEXT;
  v_incident        RECORD;
  v_ambient         NUMERIC;
  v_battery_temp    NUMERIC;
  v_should_return   BOOLEAN;
  v_min_soc_thresh  NUMERIC;
  v_incident_id     UUID;
  v_webhook_id      UUID;
  v_eta_card       JSONB;
  v_progress       NUMERIC;
BEGIN
  v_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42') || p_sim_clock_now::text, 42));

  FOR v_dispatch IN
    SELECT d.*, v.battery_capacity_kwh, v.current_soc AS v_soc,
           v.min_soc_threshold, v.current_state AS v_state,
           v.display_name, v.fleet_operator_id AS v_fleet_op,
           (v.config->>'consumption_scalar')::numeric AS v_cons_scalar
      FROM ottoq_vehicle_dispatches d
      JOIN vehicles v ON v.id = d.vehicle_id
     WHERE d.status IN ('active','returning')
       AND (p_sim_run_id IS NULL OR d.sim_run_id = p_sim_run_id)
  LOOP
    v_salt := v_dispatch.vehicle_id::text || ':' || p_sim_clock_now::text;
    v_min_soc_thresh := COALESCE(v_dispatch.min_soc_threshold, 20);

    v_active_frac := LEAST(1.0, (0.40 + ottoq_sim_seeded_random(v_seed, 'active:' || v_salt) * 0.45)
                     * ottoq_profile_rate_mult(p_sim_run_id, 'idle_fraction'));
    v_avg_speed   := 20 + ottoq_sim_seeded_random(v_seed, 'speed:' || v_salt) * 70;

    v_ambient := COALESCE(
      ottoq_sample_calibrated('ambient_temp_c','global', v_seed, 'amb:'||v_salt),
      22);

    v_discharge_kw := ottoq_sim_compute_discharge_rate(
      v_avg_speed, v_ambient, v_dispatch.battery_capacity_kwh,
      v_active_frac, NULL, v_seed, 'disch:'||v_salt);
    v_discharge_kw := ottoq_apply_profile(p_sim_run_id, 'soh_spread', v_discharge_kw, v_discharge_kw * 0.85);
    -- per-vehicle consumption scalar (condition card drawn at run boot)
    v_discharge_kw := v_discharge_kw * COALESCE(v_dispatch.v_cons_scalar, 1.0);
    v_kwh_consumed := v_discharge_kw * (p_tick_minutes / 60.0);
    v_miles := (v_avg_speed * v_active_frac * p_tick_minutes / 60.0) * 0.621371;

    v_new_soc := GREATEST(0,
      v_dispatch.v_soc - (v_kwh_consumed / v_dispatch.battery_capacity_kwh) * 100.0);

    v_battery_temp := v_ambient + 4 + v_active_frac * 6
      + ottoq_sim_seeded_random(v_seed, 'btemp:'||v_salt) * 4;

    v_dtc := ottoq_sim_maybe_spawn_dtc(v_seed, v_salt, p_tick_minutes, v_active_frac,
                                       ottoq_profile_rate_mult(p_sim_run_id, 'dtc'));

    v_incident := NULL;
    IF v_miles > 0 THEN
      SELECT * INTO v_incident FROM ottoq_sim_maybe_incident(v_seed, v_salt, v_miles,
                                       ottoq_profile_rate_mult(p_sim_run_id, 'incident') * ottoq_twin_incident_weather_mult(p_sim_run_id, p_sim_clock_now),
                                       ottoq_apply_profile(p_sim_run_id, 'incident_severity', 0, 0),
                                       ottoq_profile_rate_mult(p_sim_run_id, 'breakdown_rate'));
    END IF;

    IF v_incident.out_kind IS NOT NULL THEN
      v_incident_id := gen_random_uuid();
      INSERT INTO ottoq_vehicle_incidents (
        incident_id, vehicle_id, sim_run_id, occurred_at,
        incident_type, severity,
        speed_kmh_at_event, soc_pct_at_event,
        description, requires_tow, resolution_status
      ) VALUES (
        v_incident_id, v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
        v_incident.out_kind, v_incident.out_sev,
        v_avg_speed, v_new_soc,
        'Auto-generated by deployment simulator (DMV-calibrated rate)',
        v_incident.out_requires_tow, 'open');

      PERFORM ottoq_record_event(
        p_actor_type    := 'av_vehicle',
        p_actor_id      := v_dispatch.vehicle_id::text,
        p_event_type    := CASE WHEN v_incident.out_sev IN ('major','safety_critical')
                                THEN 'anomaly.critical_detected'
                                ELSE 'anomaly.detected' END,
        p_entity_type   := 'vehicle',
        p_entity_id     := v_dispatch.vehicle_id,
        p_fleet_operator_id := v_dispatch.v_fleet_op,
        p_payload       := jsonb_build_object(
          'incident_type', v_incident.out_kind,
          'severity', v_incident.out_sev,
          'requires_tow', v_incident.out_requires_tow,
          'soc_at_event', v_new_soc,
          'speed_at_event', v_avg_speed),
        p_severity      := CASE
                             WHEN v_incident.out_sev = 'major' THEN 'critical'
                             WHEN v_incident.out_sev = 'moderate' THEN 'warning'
                             ELSE 'info' END,
        p_ingest_source := 'twin',
        p_data_source   := 'twin',
        p_sim_run_id    := p_sim_run_id);

      IF v_incident.out_requires_tow THEN
        UPDATE vehicles SET current_state = 'tow_requested'::vehicle_state,
                            last_state_change = p_sim_clock_now,
                            current_soc = ROUND(v_new_soc::numeric,1),
                            current_soc_updated_at = p_sim_clock_now
         WHERE id = v_dispatch.vehicle_id;
        UPDATE ottoq_vehicle_dispatches SET status = 'aborted',
                                            actual_return_at = p_sim_clock_now
         WHERE dispatch_id = v_dispatch.dispatch_id;
        out_vehicle_id := v_dispatch.vehicle_id;
        out_action := 'incident:' || v_incident.out_kind;
        out_new_soc := v_new_soc; out_new_state := 'tow_requested';
        RETURN NEXT;
        CONTINUE;
      END IF;
    END IF;

    IF v_dispatch.status = 'active' THEN
      v_eta_card := ottoq_twin_deal_eta_card(p_sim_run_id, v_dispatch.dispatch_id, (p_sim_clock_now::date - DATE '2020-01-01')::int);
      IF (v_eta_card->>'will_delay')::boolean AND NOT COALESCE((v_eta_card->>'applied')::boolean, false) THEN
        v_progress := CASE WHEN v_dispatch.scheduled_return_at > v_dispatch.dispatched_at
          THEN EXTRACT(EPOCH FROM (p_sim_clock_now - v_dispatch.dispatched_at))
               / NULLIF(EXTRACT(EPOCH FROM (v_dispatch.scheduled_return_at - v_dispatch.dispatched_at)),0)
          ELSE 1 END;
        IF v_progress >= (v_eta_card->>'trigger_progress')::numeric THEN
          -- 0009 (DEFECT 2a). This is the FIRST of the two writers that move
          -- scheduled_return_at away from the dispatch-time plan, and until now it moved it
          -- SILENTLY -- from the row alone you could not tell the column had stopped being
          -- the plan. The move itself is legitimate (a real modelled delay) and is left
          -- byte-for-byte; what is added is the RECORD of it. The plan itself is now safe in
          -- its own generated column, planned_return_at, which nothing may overwrite.
          -- CLOCK DOMAIN: p_sim_clock_now is the SIM clock. So is scheduled_return_at.
          UPDATE ottoq_vehicle_dispatches
             SET scheduled_return_at = scheduled_return_at + ((v_eta_card->>'delay_min') || ' minutes')::interval,
                 eta_refreshed_at    = p_sim_clock_now,
                 eta_source          = 'twin_eta_delay_card:' || COALESCE(v_eta_card->>'cause','unknown')
           WHERE dispatch_id = v_dispatch.dispatch_id;
          v_dispatch.scheduled_return_at := v_dispatch.scheduled_return_at + ((v_eta_card->>'delay_min') || ' minutes')::interval;
          UPDATE ottoq_variability_cards SET meta = meta || '{"applied":true}'::jsonb
           WHERE sim_run_id=p_sim_run_id AND var_key='eta_delay' AND scope_instance=v_dispatch.dispatch_id::text;
          BEGIN
            PERFORM ottoq_record_event(
              p_actor_type:='av_vehicle', p_actor_id:=v_dispatch.vehicle_id::text,
              p_event_type:='fleet.arrival_delayed', p_entity_type:='vehicle', p_entity_id:=v_dispatch.vehicle_id,
              p_fleet_operator_id:=v_dispatch.v_fleet_op,
              p_payload:=jsonb_build_object('cause', v_eta_card->>'cause', 'delay_min', (v_eta_card->>'delay_min')::numeric,
                'new_eta', v_dispatch.scheduled_return_at),
              p_severity:='warning', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
          EXCEPTION WHEN OTHERS THEN NULL; END;
        END IF;
      END IF;
    END IF;

    UPDATE vehicles
       SET current_soc = ROUND(v_new_soc::numeric, 1),
           current_soc_updated_at = p_sim_clock_now,
           current_soc_source = 'oem_telemetry',
           last_state_change = p_sim_clock_now
     WHERE id = v_dispatch.vehicle_id;

    PERFORM ottoq_sim_emit_telemetry(
      v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
      v_new_soc, v_battery_temp, v_avg_speed * v_active_frac,
      v_discharge_kw, v_dispatch.v_state::text,
      CASE WHEN v_dtc IS NOT NULL THEN ARRAY[v_dtc] ELSE NULL END);

    -- AP-3: need-driven return decision (evaluator scoped to the real run)
    SELECT er.should_return, er.return_trigger, er.urgency, er.is_deferrable, er.evidence
      INTO v_ret_should, v_ret_trigger, v_ret_urgency, v_ret_deferrable, v_ret_ev
      FROM ottoq_evaluate_return_need(
             v_dispatch.vehicle_id, v_dispatch.sim_run_id, p_sim_clock_now,
             p_tick_minutes, v_new_soc) er;
    v_should_return := COALESCE(v_ret_should, false);

    IF v_should_return AND v_dispatch.status = 'active' THEN
      -- AP-4: THE RETURN HANDSHAKE. Telemetry was just emitted (the vehicle's "return to
      -- depot" notification). OTTO-Q now books the appointment BEFORE the state flip:
      -- builds the workflow, reserves the stall, communicates the selection back.
      v_eta_min := ottoq_return_eta_minutes(v_dispatch.vehicle_id, NULL, p_sim_run_id);
      BEGIN
        v_book := ottoq_book_appointment(
                  v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
                  v_ret_trigger, v_ret_urgency, COALESCE(v_ret_deferrable, false),
                  v_eta_min, v_new_soc, NULL);
      EXCEPTION WHEN OTHERS THEN
        -- one bad vehicle must never abort the whole telemetry step (tick hot path)
        v_book := jsonb_build_object('secured', false, 'reason', 'booking_error');
      END;

      -- Gate departure on securing a resource. Non-deferrable needs (reserve breach, fault)
      -- depart immediately regardless; a deferrable need with no free stall keeps the car
      -- deployed and earning, retrying next tick. That deferral is bounded by the SoC ladder:
      -- as charge drains, the trigger escalates to a non-deferrable low_soc_reserve return
      -- before any safety margin is at risk.
      IF COALESCE((v_book->>'secured')::boolean, false) OR NOT COALESCE(v_ret_deferrable, false) THEN
        UPDATE ottoq_vehicle_dispatches
           SET status = 'returning',
               return_trigger = COALESCE(v_ret_trigger, 'need_unspecified'),
               returning_started_at = p_sim_clock_now,
               return_eta_minutes   = v_eta_min,
               scheduled_return_at  = p_sim_clock_now + (v_eta_min || ' minutes')::interval,
               -- 0009 (DEFECT 2a). The SECOND writer, and the destructive one: it does not
               -- adjust the plan, it REPLACES it. Measured 2026-08-05 on live data: 116 of 116
               -- dispatch rows that reached this branch ended with
               -- scheduled_return_at = returning_started_at + EXACTLY 30 min, one distinct
               -- ETA value across the whole table. Grading that against the arrival it itself
               -- caused is circular; there was no training signal. The write is left standing
               -- (twelve other live functions READ this column as "current best arrival
               -- estimate"), but the plan is now preserved independently in planned_return_at,
               -- and the refresh is stamped, so plan / live-ETA / actual are three separate
               -- observable facts. CLOCK DOMAIN: every timestamp written here is the SIM
               -- clock. created_at is the ONLY wall-clock column on this table.
               eta_refreshed_at     = p_sim_clock_now,
               eta_source           = 'policy_constant:return_eta_minutes',
               return_evidence = COALESCE(v_ret_ev, '{}'::jsonb) || jsonb_build_object(
                 'decided_at', p_sim_clock_now,
                 'soc_at_decision', v_new_soc,
                 'reserve', v_min_soc_thresh,
                 'eta_minutes_is_a_parameter', true,
                 -- 0009: the divergence, computed at the exact moment of the refresh, so a
                 -- later reader never has to reconstruct what the plan had been.
                 'eta_source', 'policy_constant:return_eta_minutes',
                 'planned_return_at', planned_return_at,
                 'live_return_at', p_sim_clock_now + (v_eta_min || ' minutes')::interval,
                 'plan_minus_live_min', ROUND((EXTRACT(EPOCH FROM (planned_return_at
                     - (p_sim_clock_now + (v_eta_min || ' minutes')::interval))) / 60.0)::numeric, 1),
                 'appointment', v_book)
         WHERE dispatch_id = v_dispatch.dispatch_id;
        UPDATE vehicles SET current_state = 'en_route_to_depot'::vehicle_state,
                            last_state_change = p_sim_clock_now
         WHERE id = v_dispatch.vehicle_id;
        out_action := CASE WHEN COALESCE((v_book->>'secured')::boolean, false)
                           THEN 'returning:booked=' || COALESCE(v_book->>'stall_type','?')
                           ELSE 'returning:unbooked_nondeferrable' END;
      ELSE
        out_action := 'deferred:no_capacity';
      END IF;
    ELSIF v_dispatch.status = 'returning'
          AND p_sim_clock_now >= COALESCE(
                v_dispatch.returning_started_at
                  + (COALESCE(v_dispatch.return_eta_minutes, 30) || ' minutes')::interval,
                v_dispatch.scheduled_return_at + INTERVAL '5 minutes') THEN
      v_webhook_id := ottoq_sim_emit_arrival_webhook(
        v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
        v_dispatch.dispatch_id, v_new_soc);

      UPDATE ottoq_vehicle_dispatches
         SET status = 'completed',
             actual_return_at = p_sim_clock_now,
             actual_duration_min = EXTRACT(EPOCH FROM (p_sim_clock_now - dispatched_at)) / 60.0,
             arrival_jitter_min = EXTRACT(EPOCH FROM (p_sim_clock_now - COALESCE(
                 returning_started_at + (COALESCE(return_eta_minutes,30) || ' minutes')::interval,
                 scheduled_return_at))) / 60.0,
             soc_at_return_pct = v_new_soc,
             miles_driven = (SELECT COALESCE(SUM(speed_kmh) / 60.0 * 0.621371, 0)
                              FROM ottoq_telemetry_packets
                             WHERE sim_run_id = p_sim_run_id
                               AND vehicle_id = v_dispatch.vehicle_id
                               AND sim_clock_at >= v_dispatch.dispatched_at)
       WHERE dispatch_id = v_dispatch.dispatch_id;
      UPDATE vehicles SET current_state = 'arrived_at_gate'::vehicle_state,
                          current_soc = GREATEST(2, LEAST(100,
                            ottoq_apply_profile(p_sim_run_id, 'soc_on_arrival', v_new_soc, v_new_soc) - ottoq_twin_arrival_soc_drain(p_sim_run_id, p_sim_clock_now))),
                          last_state_change = p_sim_clock_now
       WHERE id = v_dispatch.vehicle_id;
      out_action := 'arrived:webhook=' || COALESCE(LEFT(v_webhook_id::text, 8), 'null');
    ELSE
      out_action := 'advancing';
    END IF;

    out_vehicle_id := v_dispatch.vehicle_id;
    out_new_soc := v_new_soc;
    out_new_state := (SELECT current_state::text FROM vehicles WHERE id = v_dispatch.vehicle_id);
    RETURN NEXT;
  END LOOP;
END;
$function$;


-- ============================================================================
-- §5  POST — SNAPSHOT THE NEW BODIES, THEN PROVE THE FILE TOOK
--
-- These checks grep the LIVE bodies rather than trusting that the statements above
-- ran. A migration that reports success while changing nothing is the exact disease
-- this repo keeps finding; refusing to take my own word for it is the cheapest
-- possible defence.
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0009_honest_completion_and_eta_post',
       CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
       n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'twin'
   AND p.proname IN ('ottoq_sim_advance_service_flow',
                     'ottoq_sim_advance_deployed_telemetry');

DO $post$
DECLARE
  v_src text;
  v_n   int;
BEGIN
  -- ---- §3 took ---------------------------------------------------------------
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_service_flow';

  IF position('FROM unnest(CASE WHEN v_rec.current_state = ''in_wash_bay''' IN v_src) > 0 THEN
    RAISE EXCEPTION 'POST: the fixed-array wear credit is still live. §3 did not take.';
  END IF;
  IF position('FROM unnest(v_credit) AS s;' IN v_src) = 0 THEN
    RAISE EXCEPTION 'POST: the intersected credit call is not present. §3 did not take.';
  END IF;
  -- the correct neighbour must have SURVIVED untouched
  IF position('PERFORM ottoq_mark_visit_atoms_done(v_rec.id,' IN v_src) = 0 THEN
    RAISE EXCEPTION 'POST: ottoq_mark_visit_atoms_done was supposed to survive byte-for-byte and is gone. §3 overreached.';
  END IF;
  -- the three capability arrays must still be exactly the pre-image's
  IF position('ELSE ARRAY[''mechanical_pm'',''sensor_calibration'',''fault_repair'',''cosmetic_repair''] END;' IN v_src) = 0 THEN
    RAISE EXCEPTION 'POST: the service-bay capability set is not intact. §3 changed what a bay can do, which it must not.';
  END IF;
  -- the atoms must be read BEFORE they are marked done -- order is the whole fix
  IF position('INTO v_outstanding' IN v_src) > position('PERFORM ottoq_mark_visit_atoms_done' IN v_src) THEN
    RAISE EXCEPTION 'POST: v_outstanding is read AFTER the atoms are marked done, so it can only ever be empty. §3 is inverted.';
  END IF;

  -- ---- §4 took ---------------------------------------------------------------
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_deployed_telemetry';

  IF position('eta_source          = ''twin_eta_delay_card:''' IN v_src) = 0 THEN
    RAISE EXCEPTION 'POST: the eta_delay-card stamp is not present. §4 did not take.';
  END IF;
  IF position('eta_source           = ''policy_constant:return_eta_minutes''' IN v_src) = 0 THEN
    RAISE EXCEPTION 'POST: the return-handshake stamp is not present. §4 did not take.';
  END IF;
  IF position('''plan_minus_live_min''' IN v_src) = 0 THEN
    RAISE EXCEPTION 'POST: the plan-vs-live divergence is not being recorded. §4 did not take.';
  END IF;
  -- the arithmetic must NOT have moved
  IF position('scheduled_return_at  = p_sim_clock_now + (v_eta_min || '' minutes'')::interval' IN v_src) = 0 THEN
    RAISE EXCEPTION 'POST: the scheduled_return_at write changed shape. §4 was supposed to stamp it, not retune it.';
  END IF;

  -- ---- §2 took, and nothing was dropped --------------------------------------
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_vehicle_dispatches'
     AND column_name IN ('planned_return_at','eta_refreshed_at','eta_source');
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'POST: expected 3 new dispatch columns, found %. §2 did not take.', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_vehicle_dispatches'
     AND column_name='planned_return_at' AND is_generated='ALWAYS';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'POST: planned_return_at is not GENERATED ALWAYS, so it is overwritable and the guarantee this file rests on does not hold.';
  END IF;

  -- the plan must be non-NULL on every existing row -- a total function, not a hope
  SELECT count(*) INTO v_n FROM public.ottoq_vehicle_dispatches WHERE planned_return_at IS NULL;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'POST: % dispatch rows have a NULL planned_return_at. The plan column is not total.', v_n;
  END IF;

  -- ottoq_return_eta_minutes must be EXACTLY as it was. Part (b) was declined, and a
  -- declined change that quietly happened anyway is worse than either outcome.
  SELECT count(*), min(md5(pg_get_functiondef(p.oid)))
    INTO v_n, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_return_eta_minutes';
  IF v_n <> 1 OR v_src <> 'c59fb82f326a01158a3276c3906d0ec4' THEN
    RAISE EXCEPTION 'POST: public.ottoq_return_eta_minutes changed (n=%, md5=%). This file declined to touch it and must not have.', v_n, v_src;
  END IF;

  -- and the two functions this file DOES NOT edit but depends on must still be single-signature
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('ottoq_wear_mark_serviced','ottoq_mark_visit_atoms_done');
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'POST: expected exactly one signature each for ottoq_wear_mark_serviced and ottoq_mark_visit_atoms_done; found % total.', v_n;
  END IF;

  RAISE NOTICE '0009 POST: all checks passed.';
END;
$post$;


-- ============================================================================
-- §6  WHAT THIS FILE DOES NOT FIX — THE GAPS REGISTER
--
-- Written so the founder finds these here rather than in a demo.
--
-- GAP 1 — 'minor_cosmetic' IS ADMITTED TO THE DETAIL BAY AND CREDITED NOTHING.
--   STEP 2 admits on flagged_issue_type IN ('minor_cosmetic','wash_due'). I map only
--   'wash_due', because a detail genuinely performs an exterior wash whereas nothing in
--   the detail bay's capability set repairs cosmetic damage. A 'minor_cosmetic' car
--   therefore leaves the bay with no wear credit. That is HONEST but INCOMPLETE, and it
--   surfaces as twin.bay_credit_none. THE REAL FIX IS UPSTREAM: either the flag should
--   raise a cosmetic_repair atom on the visit (so the service bay, which can do it, is
--   what gets booked), or 'minor_cosmetic' should stop routing to the detail bay. Both
--   are orchestration changes and are out of scope here.
--
-- GAP 2 — NOTHING CLEARS config.flagged_issue / flagged_issue_type AFTER A BAY VISIT.
--   Pre-existing, not introduced here: the wash/detail exit branch removes
--   'service_done' and 'awaiting_external_completion' from config but leaves the flag,
--   so a flagged car is re-admitted to the detail lane on every subsequent pass through
--   charge_complete_holding. The old false credit did not stop this either (admission
--   reads the flag, not the wear ledger), so this file neither causes nor worsens it --
--   but it is now the most likely explanation for a repeat twin.bay_credit_none.
--
-- GAP 3 — 'cosmetic_repair' IS AN UNMAPPED SERVICE CODE.
--   It is in the service bay's capability set, appears 0 times in the visit ledger, and
--   falls through every CASE in ottoq_wear_mark_serviced, so it moves nothing. Harmless
--   today, a live false-reset the moment someone maps it. Left alone deliberately:
--   mapping it is a modelling decision, not a bug fix.
--
-- GAP 4 — ottoq_mark_visit_atoms_done PICKS A VISIT WITHOUT RUN SCOPING.
--   Its selector is (vehicle_id, status IN open/in_progress, newest created_at) with no
--   sim_run_id. This file INHERITS that selector deliberately and byte-for-byte, so the
--   wear ledger and the visit ledger cannot disagree about which visit they mean.
--   "Fixing" it on one side only would create a divergence where none exists today. It
--   is a known defect class in this system (visit_key lacking run scoping) and wants its
--   own pass, on both sides at once.
--
-- GAP 5 — THE PM / FAULT DIVERGENCE 0008 CREATED IS NOW NARROWER BUT STILL THERE.
--   ottoq_wear_mark_serviced still zeroes the RUN-SCOPED wear ledger's open_dtc_count on
--   mechanical_pm while leaving the PROFILE's fault columns alone (0008's deliberate
--   choice). This file reduces how often that fires -- a PM is now only credited to a car
--   that actually had a PM outstanding -- but it does not resolve the divergence itself.
--
-- GAP 6 — THE ETA IS STILL A CONSTANT, AND THE SIM STILL HAS NO GEOGRAPHY.
--   Declined here with evidence (see PREMISE, part (b)). This is the single biggest
--   remaining obstacle to an arrival forecast that can be trained: until the twin models
--   a destination and a remaining distance, and until arrival is driven by that physics
--   instead of by the ETA field, plan-vs-actual accuracy remains partly self-referential.
--   What this file buys is that the three quantities are now separately observable, so
--   the work can be measured the day it starts.
--
-- GAP 7 — NO BACKFILL OF eta_refreshed_at / eta_source FOR THE 435 EXISTING ROWS.
--   They stay NULL on historical rows, which reads correctly as "we do not know when or
--   why this was moved" -- because we genuinely do not. Inventing a provenance for old
--   rows would be the same disease. planned_return_at, by contrast, IS populated for
--   every historical row, because it is derived rather than asserted.
--
--
-- ============================================================================
-- VERIFICATION BATTERY — RUN AFTER APPLYING. SIM DOMAIN ONLY.
--
-- ⚠️ RUN BUDGET: ~2.4-3.9 MB of event writes per REAL minute. A 4-6 real-minute run is
-- enough for every check below. This is a CORRECTNESS fix, not an orchestration
-- certification: do NOT run 139 sim-min for it.
-- ⚠️ STARTING A RUN PURGES THE PRIOR ONE. Preserve anything you want to compare into a
-- table whose name does NOT start with `ottoq` FIRST (ottoq_purge_prior_runs matches on
-- that prefix). proof0009_* is the convention used below.
-- ⚠️ NEVER disable cron job 12. It is the start engine. Pause a window if you must, then
-- restore it and VERIFY it is back on.
--
-- V1 -- THE HEADLINE FOR DEFECT 1. Capture AFTER the run is stopped. Every bay exit now
--       publishes what the bay could do and what it actually credited.
--   SELECT count(*)                                              AS bay_exits,
--          sum(jsonb_array_length(payload->'bay_capable'))       AS would_have_credited_before,
--          sum(jsonb_array_length(payload->'credited'))          AS credited_now,
--          sum((payload->>'suppressed_n')::int)                  AS false_credits_prevented,
--          count(*) FILTER (WHERE jsonb_array_length(payload->'credited') = 0) AS credited_nothing
--     FROM public.ottoq_events
--    WHERE event_type = 'twin.service_completed' AND sim_run_id = '<run>';
--   EXPECT: credited_now < would_have_credited_before, and false_credits_prevented > 0.
--   Before this file the two would have been equal BY CONSTRUCTION.
--
-- V2 -- THE ONE THAT MATTERS MOST: a car must no longer have its fault list wiped by a
--       job that was not a fault repair.
--   SELECT count(*) AS service_bay_exits,
--          count(*) FILTER (WHERE payload->'credited' ? 'fault_repair') AS credited_fault_repair
--     FROM public.ottoq_events
--    WHERE event_type = 'twin.service_completed' AND sim_run_id = '<run>'
--      AND payload->>'from' = 'in_service_bay';
--   EXPECT: credited_fault_repair is 0 unless a vehicle genuinely had a fault_repair atom
--   open. Cross-check the driver -- there are 2 fault_repair atoms in the entire ledger:
--     SELECT count(*) FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
--      WHERE a->>'svc' = 'fault_repair';
--
-- V3 -- NO UNDER-CREDIT. A car that genuinely had work due must still be credited for it.
--       Roll back; touches no committed state.
--   BEGIN;
--     SELECT vn.vehicle_id, a->>'svc', a->>'status'
--       FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
--      WHERE a->>'svc' IN ('mechanical_pm','sensor_calibration','interior_tidy')
--        AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped')
--      LIMIT 5;
--     -- pick one, then confirm after its next bay exit that last_pm_at / last_calibration_at
--     -- / cabin_condition moved for exactly that service and no other.
--   ROLLBACK;
--
-- V4 -- TOTALITY. A vehicle with no visit row and no flag must be a silent no-op, never an
--       error, and must never abort the tick. This is the leg_type regression class.
--   SELECT count(*) FROM public.ottoq_events
--    WHERE event_type = 'twin.bay_credit_none' AND sim_run_id = '<run>';
--   AND confirm decide_tick still completes:
--   SELECT count(*) FILTER (WHERE severity='critical') AS criticals, count(*) AS ticks
--     FROM public.ottoq_events WHERE sim_run_id='<run>' AND event_type LIKE 'twin.%';
--   EXPECT: bay_credit_none may be > 0 (that is the honest answer, see GAP 1/GAP 2); the
--   run must contain zero errors attributable to this block.
--
-- V5 -- THE HEADLINE FOR DEFECT 2. Plan, live estimate and actual are now three facts.
--       Before this file the first column did not exist as a timestamp and the accuracy
--       check was circular.
--   SELECT count(*)                                                             AS n,
--          count(*) FILTER (WHERE eta_refreshed_at IS NOT NULL)                 AS refreshed,
--          count(DISTINCT eta_source)                                           AS distinct_sources,
--          round(percentile_cont(0.5) WITHIN GROUP (ORDER BY
--            abs(EXTRACT(EPOCH FROM (actual_return_at - planned_return_at))/60.0))::numeric,1)
--                                                                               AS median_abs_plan_err_min,
--          round(percentile_cont(0.5) WITHIN GROUP (ORDER BY
--            abs(EXTRACT(EPOCH FROM (actual_return_at - scheduled_return_at))/60.0))::numeric,1)
--                                                                               AS median_abs_live_err_min
--     FROM public.ottoq_vehicle_dispatches
--    WHERE sim_run_id = '<run>' AND actual_return_at IS NOT NULL;
--   EXPECT: refreshed > 0, distinct_sources >= 1, and the two error columns DIFFER. If they
--   are identical the plan is still being overwritten and §2 has not held.
--
-- V6 -- THE PLAN IS PHYSICALLY UNWRITABLE. Prove the guarantee rather than assert it.
--   BEGIN;
--     UPDATE public.ottoq_vehicle_dispatches SET planned_return_at = now() WHERE true;
--   ROLLBACK;
--   EXPECT: ERROR 428C9 -- "column planned_return_at can only be updated to DEFAULT".
--   That error IS the proof. If it succeeds, §2 did not take.
--
-- V7 -- THE DIVERGENCE IS ON THE ROW, at the moment of the refresh, not reconstructed.
--   SELECT dispatch_id, eta_source,
--          return_evidence->>'planned_return_at'    AS plan,
--          return_evidence->>'live_return_at'       AS live,
--          return_evidence->>'plan_minus_live_min'  AS plan_minus_live_min
--     FROM public.ottoq_vehicle_dispatches
--    WHERE sim_run_id = '<run>' AND eta_refreshed_at IS NOT NULL LIMIT 10;
--
-- V8 -- PROTECT: nothing this file touched may regress the certified state. Re-measure,
--       do not assume. Compare against DB ~360 MB, tick ~0.9-3.7 s, ~852-960 B/event,
--       0 double-bookings, no starvation, phantoms 0, coverage 100%, emission invariant
--       1.000, laundering 0, drift CLEAN.
--   SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;
--   SELECT jobid, active FROM cron.job ORDER BY jobid;   -- 10/11/12 ON, 13 off
--   SELECT tgname, tgenabled FROM pg_trigger
--    WHERE tgname = 'trg_ottoq_auto_incident_report';    -- must remain DISABLED
--   AND run scripts/check-drift.sql -- must be CLEAN.
--
-- V9 -- LAUNDERING STAYS AT ZERO (0008's invariant). The new credit rule can only ever
--       REDUCE the number of profile writes, so this must not move in the wrong direction.
--   SELECT count(*) AS n,
--          count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)) AS looks_laundered
--     FROM public.vehicle_need_profile p
--     JOIN public.ottoq_vehicle_wear w ON w.vehicle_id = p.vehicle_id;
-- ============================================================================
