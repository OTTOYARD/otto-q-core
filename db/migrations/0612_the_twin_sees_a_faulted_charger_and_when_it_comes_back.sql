-- migration-version: PENDING
-- migration-name:    the_twin_sees_a_faulted_charger_and_when_it_comes_back
--
-- 0612  **The twin sees a faulted charger, and when it comes back.** Chase, 2026-10-07: *"make sure it indicates
--       somewhere visually that that charging station is down due to a fault and cars are not routed to it. If it
--       falls mid run, make sure OTTO-Q is aware of that and route cars away from that specific charger."*
--
--   THE ENGINE ALREADY ROUTES AROUND A FAULT, MEASURED BEFORE THIS FILE on run fd6ed035 (busy_day, 14 Monte Carlo
--   charger faults, 10 to 138 repair minutes each): inside every repair window the faulted stall took **0
--   reservations, 0 cars and 0 charge sessions**, and 13 of the 14 cars the fault interrupted charged again on another
--   charger (the 14th was at 99% and left at 99%). The candidate source refuses a Faulted charger since 0372,
--   HW.002 refuses a charge start on one since 0424/0428, and twin.ottoq_sim_recover_chargers puts it back after its
--   drawn repair time (0550).
--
--   WHAT WAS MISSING IS THE PICTURE. A Monte Carlo fault sets ottoq_ocpp_chargers.station_state = 'Faulted' and
--   leaves stalls.status = 'available', and ottoq_twin_snapshot sent only stalls whose status was not 'available'.
--   So the twin never heard of the fault: it drew the stall as free, and its own assignment pool (which already
--   drops a stall the twin reports 'faulted' or 'offline') could not drop it. At the moment of writing three
--   chargers at the twin depot are Faulted (DCFC W-02 communication dropout, DCFC E-09 station hardware, L2 W-20
--   connector cable) and all three stalls read 'available' in the snapshot.
--
--   THE FIX, in the snapshot's stall list only: join each stall's OCPP charger; report 'faulted' as the stall's status
--   while its charger is Faulted; add charger_state, fault_code and fault_until (the fault time plus the drawn repair
--   minutes, the same quantity twin.ottoq_sim_recover_chargers waits for); and include a stall whose charger is
--   Faulted even when the stall itself reads 'available'. Nothing else in the function changes. It is patched by
--   replace on three anchors, each asserted to occur exactly once, against an md5-guarded live body (the pattern of
--   0605 section 6). forces_recert FALSE, forces_dial_restart FALSE: a read for the renderer, not on the tick path.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0612 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the live snapshot is the body this file was written against; what 6b-style joins read exists ──
DO $premises$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'public.ottoq_twin_snapshot(uuid)'::regprocedure)
     IS DISTINCT FROM '63e86feba8d6ff449d38da431698a121' THEN
    RAISE EXCEPTION '0612 P1: public.ottoq_twin_snapshot is not the body this file patches (md5 63e86feb); read it again first';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_ocpp_chargers'
        AND column_name IN ('charger_id', 'station_state', 'station_state_changed_at', 'last_fault_code', 'last_fault_payload')) <> 5
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'stalls'
                      AND column_name = 'ocpp_charger_id') THEN
    RAISE EXCEPTION '0612 P1: a column the patch joins is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0612_the_twin_sees_a_faulted_charger_and_when_it_comes_back') THEN
    RAISE EXCEPTION '0612 P1: already applied';
  END IF;
END $premises$;

-- ── snapshot before the patch ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0612_pre', 'function', 'public', 'ottoq_twin_snapshot',
       pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure));

-- ── the patch: three anchors, each exactly once ──
DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure);
  -- 1. the stall object: a Faulted charger reads 'faulted', with its fault and when it comes back
  a1 constant text := $a$        'id', st.id, 'status', st.status, 'vehicle_id', st.current_vehicle_id,
$a$;
  b1 constant text := $b$        'id', st.id,
        -- 0612: a stall whose charger is Faulted reads 'faulted' until the drawn repair ends, so the twin draws it down
        -- and its assignment pool drops it. The engine's own candidate source refuses it already (0372).
        'status', CASE WHEN oc.station_state = 'Faulted' THEN 'faulted' ELSE st.status::text END,
        'vehicle_id', st.current_vehicle_id,
        'charger_state', oc.station_state,
        'fault_code', CASE WHEN oc.station_state = 'Faulted' THEN oc.last_fault_code END,
        'fault_until', CASE WHEN oc.station_state = 'Faulted' THEN oc.station_state_changed_at
                              + ((oc.last_fault_payload ->> 'repair_minutes')::numeric || ' minutes')::interval END,
$b$;
  -- 2. the join to the stall's charger
  a2 constant text := $a$      FROM stalls st
      LEFT JOIN vehicles tv
$a$;
  b2 constant text := $b$      FROM stalls st
      LEFT JOIN public.ottoq_ocpp_chargers oc ON oc.charger_id = st.ocpp_charger_id   -- 0612
      LEFT JOIN vehicles tv
$b$;
  -- 3. the filter: a stall whose charger is down is sent even while the stall itself reads 'available'
  a3 constant text := $a$        AND (st.status::text <> 'available'       -- only occupied/charging/faulted (light payload)
$a$;
  b3 constant text := $b$        AND (st.status::text <> 'available'       -- only occupied/charging/faulted (light payload)
             OR oc.station_state = 'Faulted'      -- 0612: ...plus any stall whose charger is down
$b$;
BEGIN
  IF (length(v_def) - length(replace(v_def, a1, ''))) / length(a1) <> 1
     OR (length(v_def) - length(replace(v_def, a2, ''))) / length(a2) <> 1
     OR (length(v_def) - length(replace(v_def, a3, ''))) / length(a3) <> 1 THEN
    RAISE EXCEPTION '0612 patch: an anchor does not occur exactly once in the live snapshot';
  END IF;
  EXECUTE replace(replace(replace(v_def, a1, b1), a2, b2), a3, b3);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_src  text;
  v_run  uuid;
  v_snap jsonb;
  v_miss integer;
  v_bad  integer;
BEGIN
  -- V1: the grants survived (the twin reads it as authenticated through its edge function)
  IF NOT has_function_privilege('authenticated', 'public.ottoq_twin_snapshot(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_twin_snapshot(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0612 V1: the snapshot lost a grant';
  END IF;
  -- V2: the three new fragments are in the body, once each
  SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.oid = 'public.ottoq_twin_snapshot(uuid)'::regprocedure;
  IF v_src !~ $r$'status', CASE WHEN oc\.station_state = 'Faulted' THEN 'faulted'$r$
     OR v_src !~ 'LEFT JOIN public\.ottoq_ocpp_chargers oc ON oc\.charger_id = st\.ocpp_charger_id'
     OR v_src !~ $r$OR oc\.station_state = 'Faulted'      -- 0612$r$ THEN
    RAISE EXCEPTION '0612 V2: a patched fragment is missing from the snapshot';
  END IF;
  -- V3: on the newest twin-depot run, every stall whose charger is Faulted now is in the stall list as 'faulted',
  -- with its fault code and the time it comes back, and no stall on a healthy charger reads 'faulted'.
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;
  v_snap := public.ottoq_twin_snapshot(v_run);
  SELECT count(*) INTO v_miss
    FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND c.station_state = 'Faulted'
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_snap -> 'stalls_status', '[]'::jsonb)) x
                      WHERE x ->> 'id' = s.id::text AND x ->> 'status' = 'faulted' AND x ? 'fault_until' AND x ? 'fault_code');
  SELECT count(*) INTO v_bad
    FROM jsonb_array_elements(COALESCE(v_snap -> 'stalls_status', '[]'::jsonb)) x
    JOIN public.stalls s ON s.id::text = x ->> 'id'
    LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE x ->> 'status' = 'faulted' AND c.station_state IS DISTINCT FROM 'Faulted';
  IF v_miss > 0 OR v_bad > 0 THEN
    RAISE EXCEPTION '0612 V3: % faulted charger(s) missing from the snapshot, % stall(s) wrongly marked faulted', v_miss, v_bad;
  END IF;
  RAISE NOTICE '0612 V3 on run %: % faulted stall(s) in the snapshot', v_run,
    (SELECT count(*) FROM jsonb_array_elements(COALESCE(v_snap -> 'stalls_status', '[]'::jsonb)) x WHERE x ->> 'status' = 'faulted');
END $verify$;

-- Rollback: EXECUTE the '0612_pre' definition from public.ottoq_schema_snapshots; DELETE FROM public.ottoq_cert_lineage
-- WHERE name = '0612_the_twin_sees_a_faulted_charger_and_when_it_comes_back'.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0612_the_twin_sees_a_faulted_charger_and_when_it_comes_back', false, false,
  'ottoq_twin_snapshot reports a stall whose OCPP charger is Faulted as ''faulted'', with fault_code and fault_until, and sends it even when the stall reads ''available''. A read for the renderer; the engine already refuses a faulted charger (0372, HW.002).',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
