-- migration-version: PENDING
-- migration-name:    a_charges_closing_frames_name_the_charger_that_sent_them
--
-- 0723  **A charge's closing frames name the charger that sent them, so the charger back end can hear a charge end.**
--        The 0697 follow-up: its relay could deliver every frame of a twin charge except the two that close it.
--
-- ══ §1 WHY (measured 2026-10-14, read-only) ═══════════════════════════════════════════════════════════════════
--
--   twin.ottoq_sim_stop_charge_session (live md5 2281c70b3b5d7cc39f3026bf2b09b4cd) ends a charge with two OCPP 2.0.1
--   frames, TransactionEvent Ended and a StatusNotification saying the connector is Available, and sends both through
--   twin.ottoq_sim_emit_ocpp(p_session_id, NULL, ...): its second argument is the charger, and the stop step passes NULL.
--   The start step sends its three (StatusNotification Occupied, Authorize, TransactionEvent Started) from
--   v_charger.charger_id, the charger its stall maps to (SELECT * INTO v_charger FROM ottoq_ocpp_chargers WHERE
--   charger_id = v_stall.ocpp_charger_id), and the advance step sends every Updated from st.ocpp_charger_id, the same
--   mapping read through JOIN stalls st ON st.id = s.stall_id. So a transaction opens and runs on a charger and closes
--   on none.
--
--     run 458156c8 (ab_harness, twin depot, 2026-10-14): Started 487 with a charger, Updated 8,257 with a charger,
--       Authorize 487 and StatusNotification 487 with a charger; Ended 455 of 455 NULL, closing StatusNotification
--       455 of 455 NULL.
--     the whole frame log: Ended 12,731 of 12,731 NULL. At the twin depot 14,363 Started frames over 71 runs since
--       0694 (2026-10-10), every one from exactly the charger its session's stall maps to today.
--
--   0697's relay (public.ottoq_csms_pull, pending) reads the twin depot's frames as
--     FROM ottoq_ocpp_messages m JOIN ottoq_ocpp_chargers c ON c.charger_id = m.charger_id WHERE ... c.depot_id = <key's depot>
--   an inner join, which is right (a frame belongs to the station that sent it, and the depot comes from the charger),
--   and which drops every closing frame. The charger back end would open every twin transaction and close none, and a
--   station would never be heard to go Available again.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════
--
--   One anchored patch of twin.ottoq_sim_stop_charge_session, md5-guarded, each anchor asserted to match exactly once:
--     1. a variable, v_charger_id uuid;
--     2. before the Ended frame, v_charger_id := the charger the session's stall maps to, read as
--          SELECT c.charger_id FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
--           WHERE s.id = v_session.stall_id
--        the mapping the start step sent Started from, the advance step sends Updated from, and this step's own charger
--        write (a few lines below, unchanged) finds the charger it marks Available or Faulted by. Read through the
--        charger table so it can only name a charger that exists: stalls.ocpp_charger_id is a foreign key to the
--        charger (ON DELETE SET NULL) today, so the join only matters if that ever changes, and then the frame carries
--        NULL, as every closing frame did before this file, rather than an id the frame log's own foreign key
--        (ottoq_ocpp_messages.charger_id -> ottoq_ocpp_chargers) would refuse and abort the close on;
--     3. the Ended frame and the closing StatusNotification pass v_charger_id where they passed NULL.
--   Nothing else in the function moves (V2 reverses the patch and compares the whole definition, header included, to
--   the snapshot). The SELECT is by primary key and not STRICT, so it cannot raise and the step stays total. The
--   session's own record of its station, ocpp_sessions.charge_point_id (the start step's v_charger.ocpp_identifier),
--   names the same charger on all 487 sessions of 458156c8; the stall's mapping is used because it is what every other
--   step uses.
--
--   Not done here, on purpose: the 12,731 closing frames already written keep NULL (ottoq_ocpp_messages is run-scoped
--   engine data the next demo run purges, and the relay starts at the head); and the closing StatusNotification still
--   says Available after a fault, while the same step marks the charger Faulted (33 of the 455 on 458156c8 ended on a
--   fault). That is the payload, not the charger, and is its own file.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════
--
--   The fourteen atoms of public.ottoq_determinism_pair (read 2026-10-14, md5 5a54e2e8, comment-stripped): fp
--   (ottoq.ottoq_world_fingerprint: ottoq_bess_units, ottoq_ocpp_chargers, stalls, vehicle_need_profile, vehicles),
--   h_cmd (ottoq_vehicle_commands), h_dec (ottoq_decisions), h_evt (ottoq_events), h_bkg (ottoq_stall_bookings), h_nrg
--   (ottoq_energy_commands), h_prop (ottoq_hash_proposals: ottoq_external_proposals), h_defr (ottoq_hash_deferrals:
--   ottoq_cuopt_deferrals), h_cal (ottoq_calibration_fingerprint: the four calibration tables), h_rule
--   (ottoq_hash_rule_evaluations: ottoq_rule_evaluations), h_rcl (ottoq_hash_recall_decisions: ottoq_recall_decisions),
--   h_sdr (ottoq_hash_sdrs: ottoq_service_detail_records, ottoq_stall_bookings, stalls, vehicles, depots), tick_count
--   (ottoq_sim_runs), end_state (ottoq_boot_state_fingerprint: ottoq_itinerary_legs, ottoq_ocpp_chargers,
--   ottoq_stall_bookings, ottoq_vehicle_dispatches, ottoq_visit_needs, stalls, vehicles). NONE reads
--   ottoq_ocpp_messages, none uses dynamic SQL, and none digests a frame's charger_id.
--
--   The whole catalog, comment-stripped: three functions name ottoq_ocpp_messages. twin.ottoq_sim_emit_ocpp writes it;
--   twin.ottoq_ocpp201_next_seq counts a session's TransactionEvents (ocpp_session_id, message_type); and
--   public.ottoq_charge_time_v2_params_cut, the charge clock's fit, reads sim_clock_at, message_type and payload by
--   ocpp_session_id. None reads charger_id. No view reads the table and no trigger fires on it. The two atoms that read
--   ottoq_ocpp_chargers (fp, end_state) read its state, which this file does not change (the charger write is
--   untouched, V2). So every frame row, every count and every fit is what it was; only a column nothing in the engine
--   reads moves from NULL to the charger. Dial pairs score KPIs from the same tables: FALSE. 0694 changed this step's
--   frames under the same census and was FALSE/FALSE.
--
-- ══ §4 ROLLBACK ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0723_pre';
--   DELETE FROM ottoq_cert_lineage WHERE name = '0723_a_charges_closing_frames_name_the_charger_that_sent_them'.
--   Frames written in between keep their charger, which is the truth.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0723 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the definition this file patches, and the premises its consistency claim rests on ──
DO $premises$
DECLARE v_md5 text; v_src text; v_all int; v_ok int;
BEGIN
  SELECT md5(pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure)) INTO v_md5;
  IF v_md5 IS DISTINCT FROM '2281c70b3b5d7cc39f3026bf2b09b4cd' THEN
    RAISE EXCEPTION '0723 P1: twin.ottoq_sim_stop_charge_session is not the definition this file was written against (md5 %)', v_md5;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0694_the_twins_chargers_speak_ocpp_2_0_1') THEN
    RAISE EXCEPTION '0723 P1: 0694 is not classified; the Ended frame this file addresses is not there';
  END IF;
  -- the emitter's second argument is the charger
  IF (SELECT p.proargnames[2] FROM pg_proc p
       WHERE p.oid = 'twin.ottoq_sim_emit_ocpp(uuid,uuid,uuid,uuid,timestamptz,text,text,jsonb)'::regprocedure)
     IS DISTINCT FROM 'p_charger_id' THEN
    RAISE EXCEPTION '0723 P1: twin.ottoq_sim_emit_ocpp''s second argument is not the charger';
  END IF;
  -- the start step sends every frame from the charger its stall maps to
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p WHERE p.oid = 'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure;
  SELECT count(*) INTO v_all FROM regexp_matches(v_src, 'ottoq_sim_emit_ocpp\s*\(', 'g');
  SELECT count(*) INTO v_ok FROM regexp_matches(v_src, 'ottoq_sim_emit_ocpp\s*\(\s*v_session_id\s*,\s*v_charger\.charger_id\s*,', 'g');
  IF v_all < 1 OR v_ok <> v_all
     OR v_src !~* 'SELECT\s+\*\s+INTO\s+v_charger\s+FROM\s+ottoq_ocpp_chargers\s+WHERE\s+charger_id\s*=\s*v_stall\.ocpp_charger_id' THEN
    RAISE EXCEPTION '0723 P1: the start step no longer sends its frames from its stall''s charger (% of % emits)', v_ok, v_all;
  END IF;
  -- the advance step sends every Updated from the same mapping
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p WHERE p.oid = 'twin.ottoq_sim_advance_charge_sessions(uuid,timestamptz)'::regprocedure;
  SELECT count(*) INTO v_all FROM regexp_matches(v_src, 'ottoq_sim_emit_ocpp\s*\(', 'g');
  SELECT count(*) INTO v_ok FROM regexp_matches(v_src, 'ottoq_sim_emit_ocpp\s*\(\s*v_session\.id\s*,\s*v_session\.ocpp_charger_id\s*,', 'g');
  IF v_all < 1 OR v_ok <> v_all
     OR v_src !~* 'SELECT\s+s\.\*\s*,\s*st\.ocpp_charger_id.*?JOIN\s+stalls\s+st\s+ON\s+st\.id\s*=\s*s\.stall_id' THEN
    RAISE EXCEPTION '0723 P1: the advance step no longer sends its frames from its stall''s charger (% of % emits)', v_ok, v_all;
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0723_pre', 'function', 'twin', 'ottoq_sim_stop_charge_session', pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p WHERE p.oid = 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure;

-- ── the patch: three anchors, each asserted to match exactly once ──
DO $sub$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure);
  v_a1 constant text := $a$  v_repair_min numeric;
$a$;
  v_n1 constant text := $n$  v_repair_min numeric;
  v_charger_id uuid;   -- 0723: the charger the closing frames are sent from
$n$;
  v_a2 constant text := $a$  -- rides in customData
  PERFORM ottoq_sim_emit_ocpp(p_session_id, NULL, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'TransactionEvent', twin.ottoq_ocpp201_tx_event(
$a$;
  v_n2 constant text := $n$  -- rides in customData
  -- 0723: both closing frames are sent from the session's charger, the one its stall maps to: the start step sent
  -- Started from it, the advance step sends Updated from it, and the charger write below finds it the same way. Read
  -- through the charger table, so a charger that is gone leaves NULL (what every closing frame carried before 0723),
  -- never an id the frame log's foreign key would refuse. By primary key and not STRICT: it cannot raise.
  SELECT c.charger_id INTO v_charger_id
    FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.id = v_session.stall_id;
  PERFORM ottoq_sim_emit_ocpp(p_session_id, v_charger_id, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'TransactionEvent', twin.ottoq_ocpp201_tx_event(
$n$;
  v_a3 constant text := $a$  PERFORM ottoq_sim_emit_ocpp(p_session_id, NULL, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StatusNotification', jsonb_build_object(
$a$;
  v_n3 constant text := $n$  PERFORM ottoq_sim_emit_ocpp(p_session_id, v_charger_id, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StatusNotification', jsonb_build_object(
$n$;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_a1, ''))) / length(v_a1) <> 1 THEN
    RAISE EXCEPTION '0723: anchor 1 (the declarations) does not match exactly once';
  END IF;
  IF (length(v_def) - length(replace(v_def, v_a2, ''))) / length(v_a2) <> 1 THEN
    RAISE EXCEPTION '0723: anchor 2 (the Ended frame) does not match exactly once';
  END IF;
  IF (length(v_def) - length(replace(v_def, v_a3, ''))) / length(v_a3) <> 1 THEN
    RAISE EXCEPTION '0723: anchor 3 (the closing StatusNotification) does not match exactly once';
  END IF;
  v_def := replace(replace(replace(v_def, v_a1, v_n1), v_a2, v_n2), v_a3, v_n3);
  EXECUTE v_def;
END $sub$;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ── V1: a charge opened and closed on the live steps, in a block that rolls back: every frame it sent names one
--        charger, its stall's, and every one passes 0697's relay join ──
CREATE FUNCTION pg_temp.p0723_session() RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
  v_twin constant uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_veh uuid; v_stall uuid; v_charger uuid; v_sid uuid; v_r jsonb; v_msg text;
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = v_twin AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  -- a free L2 stall whose charger is not faulted (0694's probe's choice)
  SELECT s.id, s.ocpp_charger_id INTO v_stall, v_charger
    FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = v_twin AND s.stall_type = 'l2'
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.vehicles x WHERE x.current_stall_id = s.id)
     AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions o WHERE o.stall_id = s.id AND o.status = 'active')
     AND c.station_state IS DISTINCT FROM 'Faulted'
   ORDER BY s.stall_code, s.id LIMIT 1;
  -- a car with a battery, no charge under way, and no stall holding it
  SELECT v.id INTO v_veh
    FROM public.vehicles v
   WHERE v.home_depot_id = v_twin AND COALESCE(v.battery_capacity_kwh, 0) > 0 AND v.fleet_operator_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions o WHERE o.vehicle_id = v.id AND o.status = 'active')
     AND NOT EXISTS (SELECT 1 FROM public.stalls st WHERE st.current_vehicle_id = v.id OR st.reserved_by = v.id)
   ORDER BY v.display_name, v.id LIMIT 1;
  IF v_run IS NULL OR v_stall IS NULL OR v_veh IS NULL THEN
    RAISE EXCEPTION '0723 V1: no stopped twin run, no free L2 stall or no car to probe';
  END IF;
  BEGIN
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    -- the charger heard from at the run's clock, as the tick stamps it before its charge steps (0424)
    UPDATE public.ottoq_ocpp_chargers SET station_state = 'Available', last_heartbeat_at = v_clock WHERE charger_id = v_charger;
    UPDATE public.vehicles
       SET current_soc = 50, current_state = 'staged_awaiting_service', current_stall_id = NULL,
           robotic_tether_until = NULL, last_state_change = v_clock
     WHERE id = v_veh;
    v_sid := twin.ottoq_sim_start_charge_session(v_veh, v_stall, v_run, NULL, v_clock);
    IF v_sid IS NULL THEN
      RAISE EXCEPTION '0723 V1: the shield refused the probe''s charge start';
    END IF;
    PERFORM twin.ottoq_sim_stop_charge_session(v_sid, 'completed', v_clock + interval '20 minutes', NULL, v_run);
    SELECT jsonb_build_object(
             'charger', v_charger,
             'frames', jsonb_agg(jsonb_build_object(
                         't', m.message_type, 'e', m.payload ->> 'eventType', 'st', m.payload ->> 'connectorStatus',
                         'c', m.charger_id,
                         'relay', EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers c
                                           WHERE c.charger_id = m.charger_id AND c.depot_id = v_twin))
                       ORDER BY m.message_seq))
      INTO v_r
      FROM public.ottoq_ocpp_messages m
     WHERE m.ocpp_session_id = v_sid AND m.direction = 'cs_to_csms';
    RAISE EXCEPTION '0723 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0723 PROBED' THEN RAISE EXCEPTION '0723 charge probe failed: %', v_msg; END IF;
  RETURN v_r;
END $fn$;

DO $vprobe$
DECLARE v jsonb := pg_temp.p0723_session();
BEGIN
  IF (SELECT count(*) FROM jsonb_array_elements(v -> 'frames') f
       WHERE f ->> 't' = 'TransactionEvent' AND f ->> 'e' = 'Ended') <> 1
     OR (SELECT count(*) FROM jsonb_array_elements(v -> 'frames') f
          WHERE f ->> 't' = 'TransactionEvent' AND f ->> 'e' = 'Started') <> 1
     OR (SELECT count(*) FROM jsonb_array_elements(v -> 'frames') f
          WHERE f ->> 't' = 'StatusNotification' AND f ->> 'st' = 'Available') <> 1 THEN
    RAISE EXCEPTION '0723 V1 FAILED: the probe charge did not open with one Started and close with one Ended and one Available: %', v;
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'frames') f WHERE f ->> 'c' IS DISTINCT FROM v ->> 'charger')
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'frames') f WHERE NOT (f ->> 'relay')::boolean) THEN
    RAISE EXCEPTION '0723 V1 FAILED: a frame of the probe charge does not name its stall''s charger, or 0697''s join drops it: %', v;
  END IF;
  RAISE NOTICE '0723 V1 PASSED: one charge opened and closed on the live steps sent % station frames, Started to Ended, every one from charger % and every one kept by 0697''s join (all rolled back)',
    jsonb_array_length(v -> 'frames'), v ->> 'charger';
END $vprobe$;

DO $v$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure);
  v_src text;
BEGIN
  --: V2 nothing else moved: undoing the three changes gives back the snapshot byte for byte (header included, so
  --:    SECURITY DEFINER and the search_path are proven unchanged; CREATE OR REPLACE keeps the grants)
  IF replace(replace(replace(v_def,
       $n$  v_repair_min numeric;
  v_charger_id uuid;   -- 0723: the charger the closing frames are sent from
$n$, $a$  v_repair_min numeric;
$a$),
       $n$  -- rides in customData
  -- 0723: both closing frames are sent from the session's charger, the one its stall maps to: the start step sent
  -- Started from it, the advance step sends Updated from it, and the charger write below finds it the same way. Read
  -- through the charger table, so a charger that is gone leaves NULL (what every closing frame carried before 0723),
  -- never an id the frame log's foreign key would refuse. By primary key and not STRICT: it cannot raise.
  SELECT c.charger_id INTO v_charger_id
    FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.id = v_session.stall_id;
  PERFORM ottoq_sim_emit_ocpp(p_session_id, v_charger_id, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'TransactionEvent', twin.ottoq_ocpp201_tx_event(
$n$, $a$  -- rides in customData
  PERFORM ottoq_sim_emit_ocpp(p_session_id, NULL, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'TransactionEvent', twin.ottoq_ocpp201_tx_event(
$a$),
       $n$  PERFORM ottoq_sim_emit_ocpp(p_session_id, v_charger_id, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StatusNotification', jsonb_build_object(
$n$, $a$  PERFORM ottoq_sim_emit_ocpp(p_session_id, NULL, v_session.vehicle_id, p_sim_run_id, v_clock,
    'cs_to_csms', 'StatusNotification', jsonb_build_object(
$a$)
     IS DISTINCT FROM (SELECT s.definition FROM public.ottoq_schema_snapshots s
                        WHERE s.label = '0723_pre' AND s.object_name = 'ottoq_sim_stop_charge_session'
                        ORDER BY s.snapshot_id DESC LIMIT 1) THEN
    RAISE EXCEPTION '0723 V2 FAILED: the body changed by more than the charger of the two closing frames';
  END IF;

  --: V3 comment-stripped: no frame is sent from NULL, both closing frames from v_charger_id, and the charger is read
  --:    before the first of them
  v_src := regexp_replace(regexp_replace(v_def, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src, 'ottoq_sim_emit_ocpp\s*\(\s*p_session_id\s*,\s*NULL\s*,', 'gi')) <> 0
     OR (SELECT count(*) FROM regexp_matches(v_src, 'ottoq_sim_emit_ocpp\s*\(', 'g')) <> 2
     OR (SELECT count(*) FROM regexp_matches(v_src, 'ottoq_sim_emit_ocpp\s*\(\s*p_session_id\s*,\s*v_charger_id\s*,', 'g')) <> 2
     OR NOT (strpos(v_src, 'INTO v_charger_id') BETWEEN 1 AND strpos(v_src, 'ottoq_sim_emit_ocpp(') - 1) THEN
    RAISE EXCEPTION '0723 V3 FAILED: a closing frame is still sent from NULL, or before its charger is read';
  END IF;
  RAISE NOTICE '0723 V2-V3 PASSED: the stop step''s two closing frames are sent from the session''s charger and nothing else moved';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0723_a_charges_closing_frames_name_the_charger_that_sent_them', false, false,
  'The 0697 follow-up: twin.ottoq_sim_stop_charge_session sent TransactionEvent Ended and the closing '
  'StatusNotification with charger_id NULL (run 458156c8: 455 of 455 each; the whole log: 12,731 Ended, all NULL), '
  'while the start and advance steps send from the charger the session''s stall maps to, so 0697''s relay (an inner '
  'join on the charger) could never deliver a charge''s end. Both now pass that charger, read through the charger '
  'table (NULL only if it is gone); anchored and md5-guarded (2281c70b), nothing else moved (V2). No determinism atom '
  'reads ottoq_ocpp_messages and nothing in the catalog reads its charger_id (emit writes it; next_seq and the charge '
  'clock''s fit read by session): FALSE/FALSE.',
  now());

COMMIT;
