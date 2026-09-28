-- migration-version: 20260928163347
-- migration-name:    a_charger_fault_from_the_cockpit_stops_the_charge
--
-- 0550  **A charger fault injected from the cockpit stops the charge, and only a repair clears a fault.** (G281.)
--        The cockpit's fault door took a charger down on paper. The car on it kept charging, the charge's normal
--        completion put the charger back in service, and the record said the car had been rerouted. The door now does to
--        the world what a real fault does: it ends the session through the same function the twin's own faults use, and
--        that re-queues the car to finish. A stop that is not a fault no longer un-faults a charger, and a repaired
--        charger returns its stall to service.
--
-- ══ §1 WHY (charger-outage stress run ca448d95, check 0408 §17; CLAUDE.md rules 9 and 10; G281) ════════════════════════
--
--   The research wing's stress test took three DC fast chargers down at sim 7:12:44 AM CT for 120 minutes, through
--   `ottoq_twin_inject_charger_fault` (0451), the door the cockpit's button uses. Not one charge stopped:
--     - Zoox-AV-077 completed at 100% on DCFC-02 18.3 minutes later. Waymo-AV-018 plugged in 50 seconds after that.
--     - Waymo-AV-016 completed at 100% on DCFC-03 73.4 minutes later. Zoox-AV-076 plugged in 1.5 minutes after that.
--     - Waymo-AV-004 was still charging on DCFC-01, at 98%, when the repair clock ran out.
--   Four writers, each correct on its own terms:
--     1. The door reports through `twin.ottoq_report_charger_fault`, the depot tech's confirm path. That path marks the
--        charger Faulted and the stall `maintenance`, and replans each car on or reserved to the stall. It never closes
--        the running `ocpp_sessions` row, so the twin's charge advance keeps adding energy. The twin's own faults stop
--        the session through `twin.ottoq_sim_stop_charge_session` with a `fault.*` reason, which re-queues the car
--        (0407 §16: 19 faults, none left short). The door never took that path.
--     2. The replan's 'stage' downlink is acked `completed` by `ottoq_comms_send_command`, which does nothing to the car.
--        The stall's guard declines, correctly, to clear the pointer of a car that is on the stall.
--     3. `twin.ottoq_sim_stop_charge_session` set a charger `Available` on any stop that is not a fault, whatever its
--        state, and restarted `station_state_changed_at`, which `twin.ottoq_sim_recover_chargers` reads as the start of
--        the repair.
--     4. `sync_stall_occupancy` sets the stall a car leaves to `available`, whatever its status. HW.002 then passed,
--        correctly, on a charger that read Available.
--   And one found by reading: recovery returned only the charger, never its stall. Once the door stops the charge, the
--   car leaves the stall before the report marks it `maintenance`, so without (d) below every injected fault would hold
--   its stall out of service until the next run's seed.
--
--   Rule 9 lets a charge end short for a charger fault only if the car is re-queued to finish. The door's fault ended
--   no charge, so the rule was never exercised by it, and a research-wing stress test through the door measured nothing.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `public.ottoq_twin_inject_charger_fault`. Before it reports the fault, it stops every session this run has
--       running on the charger through `twin.ottoq_sim_stop_charge_session(session, 'fault.operator_injected', sim clock,
--       message, run)`, the path the twin's own faults take. That closes the session as `faulted`, marks the charger
--       Faulted, and re-queues the car to finish (below target − 5) or holds it (at or above), by the one rule the stop
--       already applies. Then it reports, as before, and re-stamps the repair on the sim clock, as before. It returns
--       `sessions_stopped`.
--   (b) `twin.ottoq_report_charger_fault`. A car the robot is unplugging from the stall (`robotic_tether_*` pointing at
--       it, direction `demate`) has finished there: its session is closed and it leaves when the demate ends. It is not
--       displaced, so it is not replanned. Every other car on or reserved to the stall is replanned as before, including
--       a car still being plugged in (direction `mate`).
--   (c) `twin.ottoq_sim_stop_charge_session`. Only a repair clears a fault. A stop that is not a fault leaves a Faulted
--       charger Faulted, and leaves its `station_state_changed_at` alone.
--   (d) `twin.ottoq_sim_recover_chargers`. A repaired charger returns its stall from `maintenance`: `available`, or
--       `occupied` if a car is on it. Only a stall on a charger this call repaired, and only from `maintenance`.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════════
--
--   No certification or dial arm can reach a changed branch, and V2 asserts each premise before anything is written:
--     - (a) and (b): `twin.ottoq_report_charger_fault` has one caller in the database, the door, and the door has none.
--       The cockpit's edge function and one-shot research jobs call it; no arm does.
--     - (c) needs a stop that is not a fault on a Faulted charger. An arm's charger is Faulted only by a fault stop,
--       which closes that session, and every charger serves exactly one stall (twin depot: 40 chargers, 40 stalls). A
--       new session cannot start on a Faulted charger: HW.002 refuses it at `charge_session_start`, which
--       `twin.ottoq_sim_start_charge_session` enforces (`shield_enforce_charge_session_start`, default 1, since 0428).
--     - (d) needs a charger stall in `maintenance`. Only `twin.ottoq_report_charger_fault` writes that on a charger
--       stall, and no arm calls it.
--   The next migration that does force a recert (G279's) re-runs the canon over this one too.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - `sync_stall_occupancy` still sets the stall a car leaves to `available` whatever its status (writer 4). After (a)
--     it no longer matters for an injected fault: the car leaves before the report marks the stall. It still matters
--     for a car that is unplugged from a faulted charger after the report (b's case), where the charger, which stays
--     Faulted, is what keeps new cars off it. It is a trigger on every vehicles UPDATE and is left alone.
--   - The stop's StatusNotification says `Available` after a fault too. Nothing in the database reads it (the one
--     `connectorStatus` reader is the real-OCPP ingest function), so it is recorded and not changed.
--   - The door runs outside the tick, which takes no lock the door could share: job 777's first attempt deadlocked
--     against it (40P01). Pressing again is the remedy today. Recorded in 0408 §17.
--   - G279 (a fault sends the car to the back of the charge line) is not addressed here. This file makes the fault
--     real, so the repeat of the stress test can size G279 under a real outage.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0550 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run at the twin depot (V3 marks the ended stress run as running, and the report reads the latest) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0550 P1: a run is live at the twin depot';
  END IF;
END $live$;

-- ── P2: the four functions are the ones measured (2026-09-28 15:40 UTC, definitions) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)'::regprocedure))
     <> 'ae7517f6e032b8080d609a13e94eb5d5' THEN
    RAISE EXCEPTION '0550 P2: public.ottoq_twin_inject_charger_fault is not the function measured';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_report_charger_fault(uuid,text,text,text)'::regprocedure))
     <> 'a4ed3ea6d871a9a756ef4cc62e9a98a5' THEN
    RAISE EXCEPTION '0550 P2: twin.ottoq_report_charger_fault is not the function measured';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure))
     <> '12348f80ca9cd38668350c9456e7acad' THEN
    RAISE EXCEPTION '0550 P2: twin.ottoq_sim_stop_charge_session is not the function measured';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_recover_chargers(uuid,timestamp with time zone,numeric)'::regprocedure))
     <> 'b3ae395333a39caa9435ba60368b944b' THEN
    RAISE EXCEPTION '0550 P2: twin.ottoq_sim_recover_chargers is not the function measured';
  END IF;
END $premises$;

-- ── V2: the premises of forces_recert FALSE (§3), asserted before anything is written ──
DO $unreachable$
DECLARE v_callers text[]; v_shared int; v_maint int; v_door_callers text[];
BEGIN
  WITH src AS (
    SELECT n.nspname || '.' || p.proname AS fn,
           regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g') AS body
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prokind IN ('f', 'p'))
  SELECT array_agg(fn ORDER BY fn) FILTER (WHERE strpos(body, 'ottoq_report_charger_fault') > 0 AND fn <> 'twin.ottoq_report_charger_fault'),
         array_agg(fn ORDER BY fn) FILTER (WHERE strpos(body, 'ottoq_twin_inject_charger_fault') > 0 AND fn <> 'public.ottoq_twin_inject_charger_fault')
    INTO v_callers, v_door_callers FROM src;
  IF v_callers IS DISTINCT FROM ARRAY['public.ottoq_twin_inject_charger_fault'] THEN
    RAISE EXCEPTION '0550 V2: twin.ottoq_report_charger_fault has callers other than the door: %', v_callers;
  END IF;
  IF v_door_callers IS NOT NULL THEN
    RAISE EXCEPTION '0550 V2: the door has a caller in the database: %', v_door_callers;
  END IF;
  SELECT count(*) INTO v_shared FROM (SELECT ocpp_charger_id FROM public.stalls WHERE ocpp_charger_id IS NOT NULL
                                        GROUP BY 1 HAVING count(*) > 1) x;
  IF v_shared > 0 THEN
    RAISE EXCEPTION '0550 V2: % chargers serve more than one stall, so (c) can fire in an arm', v_shared;
  END IF;
  SELECT count(*) INTO v_maint FROM public.stalls WHERE ocpp_charger_id IS NOT NULL AND status = 'maintenance';
  IF v_maint > 0 THEN
    RAISE EXCEPTION '0550 V2: % charger stalls are in maintenance now, so (d) would change the next arm''s world', v_maint;
  END IF;
  IF strpos(regexp_replace((SELECT prosrc FROM pg_proc WHERE oid = 'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)'::regprocedure), '\s+', ' ', 'g'),
            '''shield_enforce_charge_session_start'', 1) >= 1 THEN') = 0 THEN
    RAISE EXCEPTION '0550 V2: the charge start does not refuse on the shield at the default setting';
  END IF;
  IF public.ottoq_policy_get(NULL::uuid, 'shield_enforce_charge_session_start', 1) < 1 THEN
    RAISE EXCEPTION '0550 V2: charge-start enforcement is off globally';
  END IF;
END $unreachable$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0550_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)'::regprocedure,
                 'twin.ottoq_report_charger_fault(uuid,text,text,text)'::regprocedure,
                 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure,
                 'twin.ottoq_sim_recover_chargers(uuid,timestamp with time zone,numeric)'::regprocedure);

-- ── (a) the door stops the charge before it reports the fault ──
DO $door$
DECLARE v_def text;
  d_old CONSTANT text := $a$  v_run RECORD; v_charger uuid; v_stall_code text; v_had_vehicle boolean; v_res jsonb;
$a$;
  d_new CONSTANT text := $a$  v_run RECORD; v_charger uuid; v_stall_code text; v_had_vehicle boolean; v_res jsonb;
  v_sess RECORD; v_stopped int := 0;   -- 0550
$a$;
  s_old CONSTANT text := $a$  v_res := twin.ottoq_report_charger_fault(
$a$;
  s_new CONSTANT text := $a$  -- 0550 (G281): THE HARDWARE FAILS FIRST. A charger that faults ends the session it is running. The twin's own
  -- faults do that through twin.ottoq_sim_stop_charge_session with a 'fault.*' reason, which closes the session, marks
  -- the charger Faulted and re-queues the car to finish (or holds it) by the one rule. The door takes the same path, so
  -- the fault it injects is one the world sees. Before 0550 it only reported the fault, and the car charged on through
  -- it (0408 §17). The report below then takes the stall out of the pool and replans any car still reserved to it.
  FOR v_sess IN
    SELECT o.id FROM public.ocpp_sessions o JOIN public.stalls s ON s.id = o.stall_id
     WHERE s.ocpp_charger_id = v_charger AND o.sim_run_id = p_sim_run_id AND o.status = 'active'
     ORDER BY o.id
  LOOP
    PERFORM twin.ottoq_sim_stop_charge_session(v_sess.id, 'fault.operator_injected', v_run.sim_clock_current,
              'Injected from the cockpit; repairs in ' || v_repair || ' sim-min', p_sim_run_id);
    v_stopped := v_stopped + 1;
  END LOOP;

  v_res := twin.ottoq_report_charger_fault(
$a$;
  r_old CONSTANT text := $a$    'repair_minutes', v_repair, 'faulted_at_sim', v_run.sim_clock_current,
$a$;
  r_new CONSTANT text := $a$    'repair_minutes', v_repair, 'sessions_stopped', v_stopped, 'faulted_at_sim', v_run.sim_clock_current,
$a$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)'::regprocedure);
  IF (length(v_def) - length(replace(v_def, d_old, ''))) / length(d_old) <> 1
     OR (length(v_def) - length(replace(v_def, s_old, ''))) / length(s_old) <> 1
     OR (length(v_def) - length(replace(v_def, r_old, ''))) / length(r_old) <> 1 THEN
    RAISE EXCEPTION '0550 (a): the door''s text is not the text measured';
  END IF;
  EXECUTE replace(replace(replace(v_def, d_old, d_new), s_old, s_new), r_old, r_new);
END $door$;

-- ── (b) the report does not replan a car the robot is unplugging from the stall ──
DO $report$
DECLARE v_def text;
  c_old CONSTANT text := $a$      SELECT v.* FROM vehicles v
       WHERE v.id IN (v_stall.current_vehicle_id, v_stall.reserved_by) AND v.id IS NOT NULL
       ORDER BY v.id$a$;
  c_new CONSTANT text := $a$      SELECT v.* FROM vehicles v
       WHERE v.id IN (v_stall.current_vehicle_id, v_stall.reserved_by) AND v.id IS NOT NULL
         -- 0550 (G281): a car the robot is unplugging from this stall has finished here. Its session is closed and it
         -- leaves when the demate ends (ottoq_release_expired_tethers). It is not displaced, so it is not replanned: a
         -- replan would reserve it a stall and send it a command for a move the world is already making. A car still
         -- being plugged in (direction 'mate') is displaced and is replanned.
         AND NOT (v.robotic_tether_until IS NOT NULL AND v.robotic_tether_stall_id = v_stall.id
                  AND COALESCE(v.robotic_tether_direction, 'demate') = 'demate')
       ORDER BY v.id$a$;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_report_charger_fault(uuid,text,text,text)'::regprocedure);
  IF (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old) <> 1 THEN
    RAISE EXCEPTION '0550 (b): the report''s vehicle cursor is not the text measured';
  END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $report$;

-- ── (c) only a repair clears a fault ──
DO $stop$
DECLARE v_def text;
  c_old CONSTANT text := $a$    station_state = CASE WHEN p_reason LIKE 'fault%' THEN 'Faulted' ELSE 'Available' END,
    station_state_changed_at = v_clock,
$a$;
  c_new CONSTANT text := $a$    -- 0550 (G281): only a repair clears a fault. A stop that is not a fault leaves a Faulted charger Faulted, and
    -- leaves its stamp alone, because twin.ottoq_sim_recover_chargers reads the stamp as the start of the repair.
    -- Before 0550 a car that charged on through an injected fault put its charger back in service when it finished.
    station_state = CASE WHEN p_reason LIKE 'fault%' THEN 'Faulted'
                         WHEN c.station_state = 'Faulted' THEN 'Faulted' ELSE 'Available' END,
    station_state_changed_at = CASE WHEN p_reason NOT LIKE 'fault%' AND c.station_state = 'Faulted'
                                    THEN c.station_state_changed_at ELSE v_clock END,
$a$;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure);
  IF (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old) <> 1 THEN
    RAISE EXCEPTION '0550 (c): the stop''s charger update is not the text measured';
  END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $stop$;

-- ── (d) a repaired charger returns its stall to service ──
DO $recover$
DECLARE v_def text;
  c_old CONSTANT text := $a$BEGIN
  UPDATE ottoq_ocpp_chargers
     SET station_state = 'Available',
         station_state_changed_at = p_sim_clock,
         last_heartbeat_at = p_sim_clock,
         last_fault_code = NULL
   WHERE depot_id = p_depot_id
     AND station_state = 'Faulted'
     AND station_state_changed_at <=
         p_sim_clock - (COALESCE((last_fault_payload->>'repair_minutes')::numeric,
                                 p_repair_minutes) || ' minutes')::interval;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;$a$;
  c_new CONSTANT text := $a$BEGIN
  -- 0550 (G281): a repaired charger returns its stall to service. twin.ottoq_report_charger_fault takes a faulted
  -- charger's stall out of the pool ('maintenance'), and before 0550 nothing put it back: a fault reported on a charger
  -- whose car had left, or that had none, held the stall out of service past the repair, until the next run's seed.
  -- Only a stall on a charger this call repaired is touched, and only from 'maintenance'.
  WITH rec AS (
    UPDATE ottoq_ocpp_chargers
       SET station_state = 'Available',
           station_state_changed_at = p_sim_clock,
           last_heartbeat_at = p_sim_clock,
           last_fault_code = NULL
     WHERE depot_id = p_depot_id
       AND station_state = 'Faulted'
       AND station_state_changed_at <=
           p_sim_clock - (COALESCE((last_fault_payload->>'repair_minutes')::numeric,
                                   p_repair_minutes) || ' minutes')::interval
    RETURNING charger_id
  ), back_in_service AS (
    UPDATE stalls s
       SET status = CASE WHEN s.current_vehicle_id IS NULL THEN 'available' ELSE 'occupied' END
      FROM rec
     WHERE s.ocpp_charger_id = rec.charger_id AND s.depot_id = p_depot_id AND s.status = 'maintenance'
    RETURNING s.id
  )
  SELECT count(*) INTO v_n FROM rec;
  RETURN v_n;$a$;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_recover_chargers(uuid,timestamp with time zone,numeric)'::regprocedure);
  IF (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old) <> 1 THEN
    RAISE EXCEPTION '0550 (d): the recovery''s body is not the text measured';
  END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $recover$;

-- ── V1: each change is in the catalog ──
DO $verify$
DECLARE v_door text; v_report text; v_stop text; v_recover text;
BEGIN
  v_door    := regexp_replace((SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)'::regprocedure), '\s+', ' ', 'g');
  v_report  := regexp_replace((SELECT prosrc FROM pg_proc WHERE oid = 'twin.ottoq_report_charger_fault(uuid,text,text,text)'::regprocedure), '\s+', ' ', 'g');
  v_stop    := regexp_replace((SELECT prosrc FROM pg_proc WHERE oid = 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure), '\s+', ' ', 'g');
  v_recover := regexp_replace((SELECT prosrc FROM pg_proc WHERE oid = 'twin.ottoq_sim_recover_chargers(uuid,timestamp with time zone,numeric)'::regprocedure), '\s+', ' ', 'g');
  IF strpos(v_door, 'PERFORM twin.ottoq_sim_stop_charge_session(v_sess.id, ''fault.operator_injected''') = 0
     OR strpos(v_door, 'PERFORM twin.ottoq_sim_stop_charge_session') > strpos(v_door, 'v_res := twin.ottoq_report_charger_fault(') THEN
    RAISE EXCEPTION '0550 V1: the door does not stop the session before it reports';
  END IF;
  IF strpos(v_report, 'AND NOT (v.robotic_tether_until IS NOT NULL AND v.robotic_tether_stall_id = v_stall.id') = 0 THEN
    RAISE EXCEPTION '0550 V1: the report still replans a car the robot is unplugging';
  END IF;
  IF strpos(v_stop, 'WHEN c.station_state = ''Faulted'' THEN ''Faulted'' ELSE ''Available'' END') = 0
     OR strpos(v_stop, 'THEN c.station_state_changed_at ELSE v_clock END') = 0 THEN
    RAISE EXCEPTION '0550 V1: a stop that is not a fault still clears a fault';
  END IF;
  IF strpos(v_recover, 'back_in_service AS ( UPDATE stalls s') = 0 THEN
    RAISE EXCEPTION '0550 V1: a repaired charger does not return its stall';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0550_a_charger_fault_from_the_cockpit_stops_the_charge', false, false,
  'G281: (a) public.ottoq_twin_inject_charger_fault stops every session its run has running on the charger through '
  'twin.ottoq_sim_stop_charge_session with reason fault.operator_injected (the twin''s own fault path, which re-queues '
  'the car) before it reports the fault; (b) twin.ottoq_report_charger_fault does not replan a car the robot is '
  'unplugging from the stall; (c) twin.ottoq_sim_stop_charge_session leaves a Faulted charger Faulted, with its repair '
  'stamp, on a stop that is not a fault; (d) twin.ottoq_sim_recover_chargers returns a repaired charger''s stall from '
  'maintenance. Before, the cockpit''s fault stopped no charge (ca448d95, check 0408 §17: two cars finished at 100% on '
  'a faulted charger, one charged on past the repair, and two chargers were back in service 19 and 75 minutes into a '
  '120-minute repair). FALSE because no arm reaches a changed branch: the door and the report have no caller in any arm, '
  'every charger serves one stall, a session cannot start on a Faulted charger (HW.002 enforced at charge_session_start), '
  'and only the report writes maintenance on a charger stall. V2 asserts each premise.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the ended stress run ca448d95, marked running a sim day after it ended so nothing of its own can
--   collide. Four healthy fast chargers with no car, in stall order, and four twin cars on no stall:
--     X on S1 at 50%: the door stops its session as a fault, the stop re-queues it, and the report replans nobody.
--     Y on S2, charging when its charger is marked Faulted (as the tech's confirm path would): a normal completion
--       leaves the charger Faulted with its stamp.
--     Recovery an hour and a minute later returns S1's charger and S1 itself to service.
--     Z on S3 at 99% with a latched arm: the stop holds it on the robot, and the report does not replan it.
--     Q reserved to S4 and en route: the report replans it, so the exemption is as narrow as it reads.
DO $v3$
DECLARE
  v_msg text; v_run uuid := 'ca448d95-6526-40b6-b36e-a5e02273fff3'; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  t timestamptz; st uuid[]; ch uuid[]; car uuid[];
  sx uuid; sy uuid; sz uuid; r1 jsonb; r3 jsonb; r4 jsonb;
  v_state text; v_stamp timestamptz; v_status text; v_reason text; v_rep numeric; v_n int;
BEGIN
  BEGIN
    SELECT sim_clock_current + interval '1 day' INTO t FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    IF t IS NULL THEN RAISE EXCEPTION '0550 V3: the stress run is gone'; END IF;
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = t WHERE sim_run_id = v_run;

    SELECT array_agg(id ORDER BY stall_code), array_agg(charger_id ORDER BY stall_code) INTO st, ch FROM (
      SELECT s.id, s.stall_code, s.ocpp_charger_id AS charger_id FROM public.stalls s
        JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
       WHERE s.depot_id = v_depot AND s.stall_type::text = 'dcfc' AND c.station_state <> 'Faulted'
         AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.current_stall_id = s.id OR v.robotic_tether_stall_id = s.id)
       ORDER BY s.stall_code LIMIT 4) x;
    SELECT array_agg(id ORDER BY id) INTO car FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS NULL
         AND v.robotic_tether_until IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id OR s.reserved_by = v.id)
       ORDER BY v.id LIMIT 4) y;
    IF coalesce(array_length(st, 1), 0) < 4 OR coalesce(array_length(car, 1), 0) < 4 THEN
      RAISE EXCEPTION '0550 V3: fewer than four free fast chargers (%) or four free cars (%)', array_length(st, 1), array_length(car, 1);
    END IF;

    -- X on S1, Y on S2, Z on S3: each charging, with a live session.
    UPDATE public.vehicles SET current_state = 'charging_dcfc', current_stall_id = st[1], current_depot_id = v_depot,
           current_soc = 50, target_soc = 100, last_state_change = t - interval '20 minutes' WHERE id = car[1];
    UPDATE public.vehicles SET current_state = 'charging_dcfc', current_stall_id = st[2], current_depot_id = v_depot,
           current_soc = 60, target_soc = 100, last_state_change = t - interval '20 minutes' WHERE id = car[2];
    UPDATE public.vehicles SET current_state = 'charging_dcfc', current_stall_id = st[3], current_depot_id = v_depot,
           current_soc = 99, target_soc = 100, last_state_change = t - interval '40 minutes' WHERE id = car[3];
    UPDATE public.ottoq_ocpp_chargers SET station_state = 'Occupied', station_state_changed_at = t - interval '20 minutes'
     WHERE charger_id IN (ch[1], ch[2], ch[3]);
    INSERT INTO public.ocpp_sessions(depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id, connector_id,
                                     status, started_at, soc_start, energy_delivered_kwh, sim_run_id)
    VALUES (v_depot, st[1], car[1], 'V3-0550-X', 'V3-0550-X', 1, 1, 'active', t - interval '20 minutes', 40, 10, v_run)
    RETURNING id INTO sx;
    INSERT INTO public.ocpp_sessions(depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id, connector_id,
                                     status, started_at, soc_start, energy_delivered_kwh, sim_run_id)
    VALUES (v_depot, st[2], car[2], 'V3-0550-Y', 'V3-0550-Y', 1, 1, 'active', t - interval '20 minutes', 50, 10, v_run)
    RETURNING id INTO sy;
    INSERT INTO public.ocpp_sessions(depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id, connector_id,
                                     status, started_at, soc_start, energy_delivered_kwh, sim_run_id)
    VALUES (v_depot, st[3], car[3], 'V3-0550-Z', 'V3-0550-Z', 1, 1, 'active', t - interval '40 minutes', 70, 30, v_run)
    RETURNING id INTO sz;
    INSERT INTO twin.arm_cycles(sim_run_id, depot_id, stall_id, vehicle_id, session_id, direction, phase,
                                phase_started_at, phase_deadline, started_at, ended_at, outcome)
    VALUES (v_run, v_depot, st[3], car[3], sz, 'mate', 'charging', t - interval '41 minutes', t - interval '40 minutes',
            t - interval '41 minutes', t - interval '40 minutes', 'latched');
    -- Q reserved to S4, en route.
    UPDATE public.stalls SET reserved_by = car[4], reserved_at = t - interval '5 minutes',
           reservation_expires_at = t + interval '25 minutes' WHERE id = st[4];

    -- (a) X: the door stops the charge, the stop re-queues the car, and the report replans nobody.
    r1 := public.ottoq_twin_inject_charger_fault(v_run, ch[1], 60, 'v3_0550');
    SELECT status::text, stopped_reason INTO v_status, v_reason FROM public.ocpp_sessions WHERE id = sx;
    SELECT station_state, station_state_changed_at, (last_fault_payload->>'repair_minutes')::numeric
      INTO v_state, v_stamp, v_rep FROM public.ottoq_ocpp_chargers WHERE charger_id = ch[1];
    IF NOT COALESCE((r1->>'ok')::boolean, false) OR (r1->>'sessions_stopped')::int IS DISTINCT FROM 1
       OR v_status <> 'faulted' OR v_reason <> 'fault.operator_injected'
       OR v_state <> 'Faulted' OR v_stamp <> t OR v_rep IS DISTINCT FROM 60
       OR (SELECT current_state::text FROM public.vehicles WHERE id = car[1]) = 'charging_dcfc'
       OR jsonb_array_length(COALESCE(r1->'report'->'vehicles', '[]'::jsonb)) <> 0
       OR (SELECT status FROM public.stalls WHERE id = st[1]) <> 'maintenance' THEN
      RAISE EXCEPTION '0550 V3 FAILED (a): result %, session % %, charger % at % repair %, car now %, stall now %',
        r1, v_status, v_reason, v_state, v_stamp, v_rep,
        (SELECT current_state::text FROM public.vehicles WHERE id = car[1]), (SELECT status FROM public.stalls WHERE id = st[1]);
    END IF;

    -- (c) Y: its charger is marked Faulted while it charges; its normal completion leaves the fault and its stamp.
    UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted', station_state_changed_at = t - interval '10 minutes'
     WHERE charger_id = ch[2];
    PERFORM twin.ottoq_sim_stop_charge_session(sy, 'completed', t, NULL, v_run);
    SELECT station_state, station_state_changed_at INTO v_state, v_stamp FROM public.ottoq_ocpp_chargers WHERE charger_id = ch[2];
    IF v_state <> 'Faulted' OR v_stamp <> t - interval '10 minutes' THEN
      RAISE EXCEPTION '0550 V3 FAILED (c): a completion left the charger % stamped %', v_state, v_stamp;
    END IF;

    -- (b) Z: the stop holds it on the robot, and the report does not replan it.
    r3 := public.ottoq_twin_inject_charger_fault(v_run, ch[3], 60, 'v3_0550');
    IF (SELECT status::text FROM public.ocpp_sessions WHERE id = sz) <> 'faulted'
       OR (SELECT robotic_tether_stall_id FROM public.vehicles WHERE id = car[3]) IS DISTINCT FROM st[3]
       OR jsonb_array_length(COALESCE(r3->'report'->'vehicles', '[]'::jsonb)) <> 0 THEN
      RAISE EXCEPTION '0550 V3 FAILED (b): result %, car tethered to %', r3,
        (SELECT robotic_tether_stall_id FROM public.vehicles WHERE id = car[3]);
    END IF;

    -- (b), the other side: Q, reserved and en route, is replanned.
    r4 := public.ottoq_twin_inject_charger_fault(v_run, ch[4], 60, 'v3_0550');
    IF (r4->>'sessions_stopped')::int IS DISTINCT FROM 0
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(r4->'report'->'vehicles', '[]'::jsonb)) e
                       WHERE (e->>'vehicle_id')::uuid = car[4]) THEN
      RAISE EXCEPTION '0550 V3 FAILED (b, en route): result %', r4;
    END IF;

    -- (d) an hour and a minute later: S1's charger is repaired, and S1 is back in service.
    v_n := twin.ottoq_sim_recover_chargers(v_depot, t + interval '61 minutes', 75);
    IF (SELECT station_state FROM public.ottoq_ocpp_chargers WHERE charger_id = ch[1]) <> 'Available'
       OR (SELECT status FROM public.stalls WHERE id = st[1]) <> 'available' THEN
      RAISE EXCEPTION '0550 V3 FAILED (d): charger %, stall %',
        (SELECT station_state FROM public.ottoq_ocpp_chargers WHERE charger_id = ch[1]), (SELECT status FROM public.stalls WHERE id = st[1]);
    END IF;

    RAISE EXCEPTION '0550 V3 PASSED: (a) the door stopped X''s session as a fault, re-queued it, and the report replanned nobody; (c) a completion on a Faulted charger left it Faulted with its stamp; (b) Z, on the robot at 99%%, was not replanned, and Q, en route, was; (d) the repair returned the charger and its stall';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0550 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0550 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0550_pre' as it is.

COMMIT;
