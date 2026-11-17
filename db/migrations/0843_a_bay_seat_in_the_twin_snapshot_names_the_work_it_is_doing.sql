-- migration-version: PENDING
-- migration-name:    0843_a_bay_seat_in_the_twin_snapshot_names_the_work_it_is_doing
--
-- 0843  **A car's bay seat in the twin's snapshot names the work the seat is doing, as the bay exit will credit it, so
--        the yard plays the right machine's program: the tire robot's for a tire job, nothing for a fault repair.**
--
-- WHY. 0842 gave the service bays' tire robot (OTTO-TIRE) its two jobs. The snapshot's `bay_seat` (0762) says when a
--   car was seated in a bay and when its timer ends, and the renderer plays a wash or detail bay's machine inside that
--   window. A service bay seats cars for several kinds of work, and only two of them are the robot's, so the window
--   alone cannot say whether the robot runs, or which program (a replacement or a rotation). Read on the first check
--   run after 0842 (0dc17f83, 2026-11-17): Waymo-AV-038 was seated for tire_replacement from the needs card alone (a
--   boot car with no visit), so its visit, which the snapshot also carries, held no tire atom at all.
--
-- §1 WHAT THIS DOES. public.ottoq_bay_seat_work(vehicle, state, run, config): what the bay can do
--   (ottoq.ottoq_state_service_atoms) of what the car's open visit in the run still owes and the need the seat was made
--   for (config.bay_need, while it is bound to the seat's timer). It is twin.ottoq_sim_advance_service_flow STEP 1's own
--   credit set (0009, 0458), read before the exit instead of at it. public.ottoq_twin_snapshot adds it to `bay_seat` as
--   `work`, a sorted array; an older reader ignores the key. Read-only: no decision reads the snapshot.
--   Rules: nothing a car needs changes (9); no setting (10); no test (12).
--
-- §2 PRECONDITIONS AND CHECKS. P0 no certification in flight and no live run at the twin depot. P1 the snapshot's body
--   (md5 of prosrc). P2 once. V1 the anchor matched once and the snapshot is stored as patched, from its snapshot. V2 a
--   probe, rolled back, on the twin depot's newest finished run: one car seated in a service bay for tire_rotation
--   (bay_need bound to its timer, no visit) and one for tire_replacement owed on its visit read `work` =
--   ["tire_rotation"] and ["tire_replacement"]; a car in a wash bay reads only wash work.
--
-- §3 CLASSIFICATION. forces_recert FALSE (no decision reads it). forces_dial_restart FALSE.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0843_pre'; DROP FUNCTION
--   public.ottoq_bay_seat_work(uuid, text, uuid, jsonb); DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0843_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0843 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running') THEN
    RAISE EXCEPTION '0843 P0: a run is live at the twin depot; apply between runs';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_twin_snapshot(uuid)'))
     IS DISTINCT FROM '7f961b8576f4c8dddea6f7d825f54a12' THEN
    RAISE EXCEPTION '0843 P1: public.ottoq_twin_snapshot is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0843_%')
     OR to_regprocedure('public.ottoq_bay_seat_work(uuid,text,uuid,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION '0843 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0843_pre', 'function', 'public', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_twin_snapshot(uuid)']) AS f;

CREATE FUNCTION public.ottoq_bay_seat_work(p_vehicle_id uuid, p_state text, p_sim_run_id uuid, p_config jsonb)
RETURNS text[]
LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $f$
  -- 0843: the work a car's bay seat is doing, as the bay exit will credit it (twin.ottoq_sim_advance_service_flow STEP 1):
  -- what the bay can do, of what the car's open visit in the run still owes and the need the seat was made for (while
  -- that need is bound to the seat's timer). Empty for a car in no bay. Total: nothing here raises.
  SELECT COALESCE(array_agg(DISTINCT w ORDER BY w), '{}'::text[])
    FROM unnest(ottoq.ottoq_state_service_atoms(p_state)) AS w
   WHERE w = (CASE WHEN (p_config -> 'bay_need' ->> 'ends_at') IS NOT DISTINCT FROM (p_config ->> 'service_ends_at')
                   THEN NULLIF(p_config -> 'bay_need' ->> 'svc', '') END)
      OR EXISTS (SELECT 1
                   FROM public.ottoq_visit_needs n
                   CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(n.atoms) = 'array' THEN n.atoms
                                                                ELSE '[]'::jsonb END) a
                  WHERE n.vehicle_id = p_vehicle_id AND n.status IN ('open', 'in_progress')
                    AND COALESCE(n.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                      = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                    AND a ->> 'svc' = w
                    AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled', 'skipped'))
$f$;

CREATE TEMP TABLE _0843_patch (c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0843_patch VALUES (
$o$'ends_at', public.ottoq_try_timestamptz(v.config ->> 'service_ends_at'))$o$,
$n$'ends_at', public.ottoq_try_timestamptz(v.config ->> 'service_ends_at'),
                                  -- 0843: the work the seat is doing, as the bay exit will credit it, so the renderer
                                  -- plays the right machine's program (the tire robot's for a tire job)
                                  'work', to_jsonb(public.ottoq_bay_seat_work(v.id, v.current_state::text,
                                                                              v_run.sim_run_id, v.config)))$n$);

DO $patch$
DECLARE p record; v_def text; v_old text; n int;
BEGIN
  SELECT * INTO p FROM _0843_patch;
  v_old := pg_get_functiondef(to_regprocedure('public.ottoq_twin_snapshot(uuid)'));
  n := (length(v_old) - length(replace(v_old, p.c_old, ''))) / length(p.c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0843 V1: the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_old, p.c_old, p.c_new);
  EXECUTE v_def;
  IF pg_get_functiondef(to_regprocedure('public.ottoq_twin_snapshot(uuid)')) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0843 V1: the snapshot is not stored as patched';
  END IF;
  IF md5(replace(v_def, p.c_new, p.c_old)) IS DISTINCT FROM
     (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0843_pre' ORDER BY snapshot_id DESC LIMIT 1) THEN
    RAISE EXCEPTION '0843 V1: the patched definition with the patch reversed is not the snapshot';
  END IF;
END $patch$;

-- V2: the probe. It raises to roll its writes back; the answer comes back as the exception's detail.
CREATE FUNCTION pg_temp._0843_probe() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  c_depot CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_a uuid; v_b uuid; v_c uuid; v_snap jsonb; v_r jsonb; v_detail text;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start) INTO v_run, v_clock
    FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot AND r.status = 'completed' ORDER BY r.started_at DESC LIMIT 1;
  SELECT (array_agg(v.id ORDER BY v.id))[1], (array_agg(v.id ORDER BY v.id))[2], (array_agg(v.id ORDER BY v.id))[3]
    INTO v_a, v_b, v_c
    FROM public.vehicles v WHERE v.home_depot_id = c_depot AND v.category = 'autonomous' AND v.is_active;
  IF v_run IS NULL OR v_c IS NULL THEN RAISE EXCEPTION '0843 V2: no run or cars to probe with'; END IF;
  BEGIN
    UPDATE public.ottoq_visit_needs SET status = 'complete'
     WHERE vehicle_id IN (v_a, v_b, v_c) AND status IN ('open', 'in_progress');
    -- a: seated for a rotation from the needs card alone (the need bound to the seat's timer, no visit)
    UPDATE public.vehicles SET current_state = 'in_service_bay', last_state_change = v_clock,
           config = COALESCE(config, '{}'::jsonb)
                    || jsonb_build_object('service_ends_at', (v_clock + interval '12 minutes')::text,
                                          'bay_need', jsonb_build_object('svc', 'tire_rotation',
                                                                         'ends_at', (v_clock + interval '12 minutes')::text))
     WHERE id = v_a;
    -- b: seated for a replacement its visit owes
    UPDATE public.vehicles SET current_state = 'in_service_bay', last_state_change = v_clock,
           config = (COALESCE(config, '{}'::jsonb) - 'bay_need')
                    || jsonb_build_object('service_ends_at', (v_clock + interval '12 minutes')::text)
     WHERE id = v_b;
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype, urgency, atoms,
                                          status, source, meta)
    VALUES (v_b, v_run, c_depot, v_clock, v_b::text || ':0843probe', 'B_full_service', 'standard',
            jsonb_build_array(jsonb_build_object('svc', 'tire_replacement', 'must_do', true, 'status', 'pending',
                                                 'concurrency', 'bay', 'requires_bay', 'service_bay'),
                              jsonb_build_object('svc', 'exterior_wash', 'must_do', true, 'status', 'pending')),
            'open', 'probe', '{"generator":"0843 V2"}');
    -- c: in a wash bay, washing
    UPDATE public.vehicles SET current_state = 'in_wash_bay', last_state_change = v_clock,
           config = COALESCE(config, '{}'::jsonb)
                    || jsonb_build_object('service_ends_at', (v_clock + interval '9 minutes')::text,
                                          'bay_need', jsonb_build_object('svc', 'exterior_wash',
                                                                         'ends_at', (v_clock + interval '9 minutes')::text))
     WHERE id = v_c;
    v_snap := public.ottoq_twin_snapshot(v_run);
    v_r := jsonb_build_object(
      'a', (SELECT x -> 'bay_seat' -> 'work' FROM jsonb_array_elements(v_snap #> '{fleet,vehicles}') x WHERE (x ->> 'id')::uuid = v_a),
      'b', (SELECT x -> 'bay_seat' -> 'work' FROM jsonb_array_elements(v_snap #> '{fleet,vehicles}') x WHERE (x ->> 'id')::uuid = v_b),
      'c', (SELECT x -> 'bay_seat' -> 'work' FROM jsonb_array_elements(v_snap #> '{fleet,vehicles}') x WHERE (x ->> 'id')::uuid = v_c));
    RAISE EXCEPTION USING ERRCODE = 'OQ843', MESSAGE = '0843 V2 probe', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ843' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN v_detail::jsonb;
  END;
END $f$;

DO $v2$
DECLARE v_r jsonb := pg_temp._0843_probe();
BEGIN
  IF (v_r -> 'a') IS DISTINCT FROM '["tire_rotation"]'::jsonb
     OR (v_r -> 'b') IS DISTINCT FROM '["tire_replacement"]'::jsonb
     OR (v_r -> 'c') IS DISTINCT FROM '["exterior_wash"]'::jsonb THEN
    RAISE EXCEPTION '0843 V2: the bay seats do not name their work: %', v_r;
  END IF;
  RAISE NOTICE '0843 V2: %', v_r;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0843_a_bay_seat_in_the_twin_snapshot_names_the_work_it_is_doing', false, false,
        'The twin snapshot''s bay_seat carries `work`, the bay exit''s own credit set read before the exit, so the yard '
        || 'plays the tire robot for a tire job (0842). Read-only; no decision reads the snapshot. Pre-image 0843_pre.', now());
COMMIT;
