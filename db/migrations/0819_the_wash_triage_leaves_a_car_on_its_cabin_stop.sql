-- migration-version: 20261112141807
-- migration-name:    0819_the_wash_triage_leaves_a_car_on_its_cabin_stop
--
-- 0819  **The twin's wash triage leaves a car on its cabin stop.**
--
-- WHY. A DEFECT IN 0817, FOUND ON ITS FIRST LIVE STOP. Run 56d8465f, car ef0b46c0, sim 15:47:20: the cabin-stop step
-- had seated the car on fast-charger post NASH-DCFC-STALL-10 (waited 91.0 minutes, the floor). The twin confirmed the
-- command and the car stood on the post, charge_complete_holding. IN THE SAME WORLD TICK twin.ottoq_sim_wash_triage
-- read it as a car that had just finished a charge and moved it on: staged_awaiting_service, svc_step need_service
-- (its visit also has a mechanical PM to do). The car still stood on the post, but the arm's starter takes a cabin
-- stop only from charge_complete_holding, so the arm never began. The stop's own 20-minute limit would have freed the
-- post with the clean not done.
--
-- 0817's self-test did not see it: V3 called the command confirm and the arm's starter directly, not the world tick,
-- so the triage never ran between them. A STAGED TEST THAT CALLS THE STEPS IT KNOWS ABOUT CANNOT FIND THE STEP IT DOES
-- NOT KNOW ABOUT. The check that would have found it is one world tick over the staged car.
--
-- 0817 gave the mover's hold (ottoq.ottoq_uplink_transfer_holds) to a car on its stop, and the decide tick's cursors
-- read that hold. The wash triage reads no hold at all: it takes every charge_complete_holding car at the depot.
--
-- WHAT THIS DOES.
--   (a) public.ottoq_on_cabin_stop(vehicle): true while the car stands on the post an open cabin stop names (the mark
--       on its deep-clean atom, pending or in progress). One test, no run argument, so any door can ask it.
--   (b) twin.ottoq_sim_wash_triage passes over such a car. Once the stop ends the mark is gone (0817's release), and
--       the triage reads the car as it reads every car that has left a charger.
--
-- RULE 9: this keeps a needed service from being cut off before it starts. Nothing is skipped or shortened.
--
-- P0 nothing in flight. P1 the body this file was written against (md5 of prosrc 28cd001a55d1de53dc51270ce6635140),
-- and 0817 applied. P2 once. V1 the patched body with its patch reversed is its pre-image. V2 the anchor matched once.
--
-- CLASSIFICATION. forces_recert FALSE, forces_dial_restart FALSE: no atom carries the mark unless
-- wash_bay_exterior_only is on (default 0), so the new test is false for every car in every certification arm.
-- Applied with a run live (the run that showed the defect), so the next stop on it is the check.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0819_pre'; DROP FUNCTION
--   public.ottoq_on_cabin_stop(uuid); DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0819_%'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0819 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'twin.ottoq_sim_wash_triage(uuid,timestamptz)'::regprocedure)
       IS DISTINCT FROM '28cd001a55d1de53dc51270ce6635140' THEN
    RAISE EXCEPTION '0819 P1: twin.ottoq_sim_wash_triage is not the body this file was written against';
  END IF;
  IF to_regprocedure('public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION '0819 P1: 0817 is not applied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0819_%') THEN
    RAISE EXCEPTION '0819 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0819_pre', 'function', 'twin', 'ottoq_sim_wash_triage',
       pg_get_functiondef('twin.ottoq_sim_wash_triage(uuid,timestamptz)'::regprocedure),
       md5(pg_get_functiondef('twin.ottoq_sim_wash_triage(uuid,timestamptz)'::regprocedure));

CREATE FUNCTION public.ottoq_on_cabin_stop(p_vehicle uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0819: the car stands on the fast-charger post an open cabin stop names (0817): its deep-clean atom, pending or in
  -- progress, carries that post, on a visit still open. False for every car when no stop is open.
  SELECT EXISTS (
    SELECT 1
      FROM public.vehicles v
      JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = v.id AND vn.status IN ('open', 'in_progress')
      CROSS JOIN LATERAL jsonb_array_elements(
        CASE WHEN jsonb_typeof(vn.atoms) = 'array' THEN vn.atoms ELSE '[]'::jsonb END) a
     WHERE v.id = p_vehicle AND v.current_stall_id IS NOT NULL
       AND a->>'svc' = 'interior_deep_clean'
       AND COALESCE(a->>'status', 'pending') IN ('pending', 'in_progress')
       AND a->>'cabin_stop_stall_id' = v.current_stall_id::text);
$function$;

COMMENT ON FUNCTION public.ottoq_on_cabin_stop(uuid) IS
  '0819: the car stands on the fast-charger post an open cabin stop names (0817). A door that moves '
  'charge_complete_holding cars passes over it.';

DO $patch$
DECLARE
  c_old constant text := $o$       AND current_state = 'charge_complete_holding'
     ORDER BY id   /* 0054:$o$;
  c_new constant text := $n$       AND current_state = 'charge_complete_holding'
       -- 0819: not a car on its cabin stop (0817). It stands on a fast-charger post for the arm's program, and has
       -- finished no charge.
       AND NOT public.ottoq_on_cabin_stop(id)
     ORDER BY id   /* 0054:$n$;
  v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_wash_triage(uuid,timestamptz)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0819 V2: the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);
  EXECUTE v_def;
  IF md5(replace(pg_get_functiondef('twin.ottoq_sim_wash_triage(uuid,timestamptz)'::regprocedure), c_new, c_old))
       IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s WHERE s.label = '0819_pre') THEN
    RAISE EXCEPTION '0819 V1: the patched body with its patch reversed is not its pre-image';
  END IF;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0819_the_wash_triage_leaves_a_car_on_its_cabin_stop', false, false,
        'A defect in 0817, found on its first live stop (run 56d8465f, car ef0b46c0): the twin''s wash triage moved the '
        'car on in the tick it was seated on its post, so the arm never began. The triage now passes over a car on its '
        'cabin stop (public.ottoq_on_cabin_stop). No atom carries the mark unless wash_bay_exterior_only is on, so the '
        'test is false in every certification arm.',
        now());

COMMIT;

-- APPLIED 2026-11-12 at 14:18:07 UTC (8:18 AM CT), ledger 20261112141807, through apply_migration, on the first send,
--   with demo run 56d8465f live at sim 16:00. The text sent was this file from BEGIN to COMMIT. Stored after the
--   apply, md5(prosrc): ottoq_sim_wash_triage c1d7d9b653996194dc2ecb792d037430, ottoq_on_cabin_stop
--   7995c2e788e5c109ce47686ea5b9c74e. db/checks/0484 has what the run showed after it.
