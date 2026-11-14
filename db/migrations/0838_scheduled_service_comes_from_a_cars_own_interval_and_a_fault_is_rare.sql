-- migration-version: 20261114154052
-- migration-name:    0838_scheduled_service_comes_from_a_cars_own_interval_and_a_fault_is_rare
--
-- 0838  **Scheduled service comes from a car's own interval, and a fault or a cosmetic repair is rare.** (G549)
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-11-14, morning CT (CLAUDE.md rule 15): a service bay visit is "extremely rare or even quarterly ...
--   unless there's a major issue with the vehicle like flat tire or malfunction", and "more than two or three vehicles a
--   day ... would be way too much".
--   0837 took the busy day's interval scale off. Its first run (ff41e769, read at sim 1.5 h, 15:36 UTC) already held 6
--   mechanical_pm, 2 sensor_calibration and 2 fault_repair, on cars 2% to 97% of the way through their maintenance
--   interval. A second generator made them. twin.ottoq_sim_observe_asset draws, on EVERY arrival, from the active
--   'service_manifest' feed plan (v1, 2026-07-10, "explicitly tunable assumptions"):
--     mechanical_pm        0.05 x 0.5 x (0.5 below 80% of the interval, 4 from 80%, 12 once due)   1.25% of arrivals at least
--     sensor_calibration   0.04 x 0.5 x the same steps                                             1% at least
--     cosmetic_repair      0.02 x 0.5                                                              1%
--     fault_repair         0.02 (the function's default; the plan carries no fault_repair_p)       2%
--   At about 250 arrivals a day that is 5 fault repairs (run 7c967d67 drew 5), 2 to 3 cosmetic repairs, and
--   maintenance and calibration on cars nowhere near due. The plan's own provenance says what replaces the draw:
--   "mileage-based sensor_calibration/mechanical_pm ... once vehicle odometer state exists". It exists
--   (ottoq_vehicle_wear), and since 0715 ottoq.ottoq_derive_visit_needs writes both services, required, on the visit
--   where a car's own interval is due.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   A new version (2) of the 'service_manifest' feed plan, promoted through public.ottoq_feed_plan_promote under a
--   person's name (0716). It is version 1 with four numbers changed:
--     probabilities.mechanical_pm        0.05 -> 0       scheduled maintenance comes only from the car's interval (0715)
--     probabilities.sensor_calibration   0.04 -> 0       the same
--     probabilities.cosmetic_repair      0.02 -> 0.001   0.05% of arrivals after the long-tail scale
--     fault_repair_p                     (0.02 default) -> 0.002
--   ASSUMPTION: the last two rates have no fleet-service source. They are set so that a 116-car day stays inside
--   Chase's bound: about 0.5 fault repairs and 0.1 cosmetic repairs a day at 250 arrivals, beside about 1.1
--   maintenance visits and 0.6 calibrations from the cars' own intervals (0837 §1). Chase can set them from a UI or
--   a later version. No function is changed; every draw is still taken with its own salt, so no other draw moves.
--
-- ══ §3 CHECKS ════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight and no run running. P1 the active plan is version 1 with the four numbers as read, the
--   observer is the function read (md5), and 0715 and 0837 are classified. P2 once. V1 the active plan is version 2,
--   equal to version 1 but for the four numbers; version 1 is superseded; the promotion is on record under a person.
--   V2 the observer, called 400 times on a car at the twin depot with no run, draws no maintenance and no calibration.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE: every scenario's arrivals draw different service from here on.
--   Nothing acts on either while testing is off (rule 12). No row is added to ottoq_evidence_regimes: the charge
--   clock's evidence is charges (see 0837 §4 for the fits this does touch).
--
-- APPLIED 2026-11-14 15:40:52 UTC (9:40 AM CT), ledger 20261114154052, between runs. A first attempt a minute earlier
--   failed inside V1 and rolled back with nothing changed: the check subtracted a key before the path operators
--   bound ("operator is not unique: unknown - unknown"). I had not run the file on the scratch PostgreSQL. It was
--   fixed, run there end to end, and applied. The ledger holds this file from BEGIN to COMMIT under a two-line header.
--
-- ROLLBACK: SELECT public.ottoq_feed_plan_promote((SELECT plan_id FROM public.ottoq_feed_plans WHERE var_key =
--   'service_manifest' AND version = 1), '<a person>', 'rollback of 0838'); DELETE FROM public.ottoq_cert_lineage
--   WHERE name = '0838_scheduled_service_comes_from_a_cars_own_interval_and_a_fault_is_rare'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $p0$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0838 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0838 P0: a run is running; apply between runs';
  END IF;
END $p0$;

DO $p1$
DECLARE v_p jsonb; v_ver integer;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0838_scheduled_service_comes_from_a_cars_own_interval_and_a_fault_is_rare')
     OR EXISTS (SELECT 1 FROM public.ottoq_feed_plans WHERE var_key = 'service_manifest' AND version = 2) THEN
    RAISE EXCEPTION '0838 P2: already applied';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_cert_lineage
       WHERE name IN ('0837_a_busy_day_no_longer_shortens_every_cars_maintenance_interval')
          OR name LIKE '0715\_%') < 2 THEN
    RAISE EXCEPTION '0838 P1: 0715 or 0837 is not classified; apply in order';
  END IF;
  SELECT plan, version INTO v_p, v_ver FROM public.ottoq_feed_plans
   WHERE var_key = 'service_manifest' AND status = 'active' ORDER BY version DESC LIMIT 1;
  IF v_ver IS DISTINCT FROM 1 OR (v_p #>> '{probabilities,mechanical_pm}')::numeric IS DISTINCT FROM 0.05
     OR (v_p #>> '{probabilities,sensor_calibration}')::numeric IS DISTINCT FROM 0.04
     OR (v_p #>> '{probabilities,cosmetic_repair}')::numeric IS DISTINCT FROM 0.02 OR v_p ? 'fault_repair_p' THEN
    RAISE EXCEPTION '0838 P1: the active service_manifest plan is not version 1 as read: v% %', v_ver, v_p;
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_observe_asset(uuid,uuid,uuid,bigint,timestamp with time zone,uuid)'))
       IS DISTINCT FROM '7cc869e6423fa79edc15000e0c2ca406' THEN
    RAISE EXCEPTION '0838 P1: the observer is not the function read; read it again before applying';
  END IF;
END $p1$;

INSERT INTO public.ottoq_feed_plans (plan_id, var_key, version, status, method, plan, provenance, authored_by, rationale)
SELECT gen_random_uuid(), 'service_manifest', 2, 'draft', p.method,
       jsonb_set(jsonb_set(jsonb_set(p.plan,
         '{probabilities,mechanical_pm}', '0'::jsonb),
         '{probabilities,sensor_calibration}', '0'::jsonb),
         '{probabilities,cosmetic_repair}', '0.001'::jsonb) || jsonb_build_object('fault_repair_p', 0.002),
       jsonb_build_object(
         'source_type', 'declared_assumptions',
         'basis', 'Chase, 2026-11-14 (CLAUDE.md rule 15): a service bay visit is rare, about quarterly for scheduled '
                  'work, and more than two or three cars a day is too many. Scheduled maintenance and calibration come '
                  'from each car''s own interval (0715). ASSUMPTION: fault_repair_p 0.002 and cosmetic_repair 0.001 '
                  'have no fleet-service source; they are set to keep a 116-car day inside that bound.',
         'replaces_version', 1, 'migration', '0838'),
       'Claude Code (0838)',
       'Version 1 drew maintenance, calibration, a cosmetic repair and a fault repair on every arrival, whatever the '
       'car''s mileage: about 20 service-bay jobs a day at the twin depot on the cars'' own intervals. Version 2 '
       'leaves scheduled work to the interval and makes a fault and a cosmetic repair rare.'
  FROM public.ottoq_feed_plans p
 WHERE p.var_key = 'service_manifest' AND p.version = 1;

DO $promote$
DECLARE v_r jsonb;
BEGIN
  v_r := public.ottoq_feed_plan_promote(
           (SELECT plan_id FROM public.ottoq_feed_plans WHERE var_key = 'service_manifest' AND version = 2),
           'Chase (delegated to Claude Code: 0838)',
           'Rule 15, Chase 2026-11-14: more than two or three cars a day in the service bays is too many. Scheduled '
           'service comes from a car''s own interval; a fault or a cosmetic repair is rare.');
  IF NOT COALESCE((v_r ->> 'ok')::boolean, false) OR (v_r ->> 'version') <> '2' OR v_r ? 'already_active' THEN
    RAISE EXCEPTION '0838: the promotion answered %', v_r;
  END IF;
END $promote$;

DO $v1$
DECLARE v_new jsonb; v_old jsonb;
BEGIN
  SELECT plan INTO v_old FROM public.ottoq_feed_plans WHERE var_key = 'service_manifest' AND version = 1 AND status = 'superseded';
  SELECT plan INTO v_new FROM public.ottoq_feed_plans WHERE var_key = 'service_manifest' AND version = 2 AND status = 'active';
  IF v_old IS NULL OR v_new IS NULL OR public.ottoq_feed_plan('service_manifest') IS DISTINCT FROM v_new THEN
    RAISE EXCEPTION '0838 V1 FAILED: version 2 is not the active plan, or version 1 is not superseded';
  END IF;
  IF ((v_new - 'fault_repair_p')
        #- '{probabilities,mechanical_pm}' #- '{probabilities,sensor_calibration}' #- '{probabilities,cosmetic_repair}')
     IS DISTINCT FROM
     (v_old #- '{probabilities,mechanical_pm}' #- '{probabilities,sensor_calibration}' #- '{probabilities,cosmetic_repair}') THEN
    RAISE EXCEPTION '0838 V1 FAILED: version 2 differs from version 1 beyond the four numbers';
  END IF;
  IF (v_new #>> '{probabilities,mechanical_pm}')::numeric <> 0 OR (v_new #>> '{probabilities,sensor_calibration}')::numeric <> 0
     OR (v_new #>> '{probabilities,cosmetic_repair}')::numeric <> 0.001 OR (v_new ->> 'fault_repair_p')::numeric <> 0.002 THEN
    RAISE EXCEPTION '0838 V1 FAILED: the four numbers are not 0, 0, 0.001 and 0.002';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_feed_plan_promotions
                  WHERE var_key = 'service_manifest' AND version = 2 AND replaced_ver = 1
                    AND promoted_by = 'Chase (delegated to Claude Code: 0838)') THEN
    RAISE EXCEPTION '0838 V1 FAILED: the promotion is not on record';
  END IF;
END $v1$;

-- ── V2: 400 draws on one car, no run: no maintenance, no calibration ──
DO $v2$
DECLARE v_car uuid; v_n integer; v_pm integer; v_cal integer; v_fault integer; v_cos integer;
BEGIN
  SELECT id INTO v_car FROM public.vehicles
   WHERE home_depot_id = '11111111-1111-1111-1111-111111111111' AND category = 'autonomous' ORDER BY id LIMIT 1;
  IF v_car IS NULL THEN RAISE NOTICE '0838 V2 SKIPPED: no car at the twin depot here'; RETURN; END IF;
  SELECT count(*), count(*) FILTER (WHERE (o ->> 'mechanical_pm')::boolean),
         count(*) FILTER (WHERE (o ->> 'sensor_calibration')::boolean),
         count(*) FILTER (WHERE (o ->> 'fault')::boolean), count(*) FILTER (WHERE (o ->> 'cosmetic_repair')::boolean)
    INTO v_n, v_pm, v_cal, v_fault, v_cos
    FROM generate_series(1, 400) g,
         LATERAL twin.ottoq_sim_observe_asset(v_car, NULL, NULL, 838 + g, '2026-11-14 15:00:00+00'::timestamptz
                                              + (g || ' minutes')::interval, NULL) AS o;
  IF v_pm > 0 OR v_cal > 0 THEN
    RAISE EXCEPTION '0838 V2 FAILED: % maintenance and % calibration drawn in % arrivals', v_pm, v_cal, v_n;
  END IF;
  RAISE NOTICE '0838 V2 PASSED: % arrivals drew 0 maintenance, 0 calibration, % fault(s), % cosmetic repair(s)',
    v_n, v_fault, v_cos;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0838_scheduled_service_comes_from_a_cars_own_interval_and_a_fault_is_rare', true, true,
        'G549. Data only: version 2 of the service_manifest feed plan, promoted under a person''s name. The per-arrival '
        'draws of mechanical_pm and sensor_calibration go to 0 (0715 writes both when a car''s own interval is due), '
        'cosmetic_repair 0.02 -> 0.001 and fault_repair_p 0.02 -> 0.002 (the last two are labelled assumptions). Every '
        'scenario''s arrivals draw different service from here on. No function changed.',
        now());

COMMIT;
