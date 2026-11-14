-- migration-version: 20261114153539
-- migration-name:    0837_a_busy_day_no_longer_shortens_every_cars_maintenance_interval
--
-- 0837  **A busy day no longer shortens every car's maintenance and calibration interval.** (G550; applied under the number G548)
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-11-14, morning CT: "a service bay should be extremely rare or even quarterly from an annual perspective
--   unless there's a major issue with the vehicle like flat tire or malfunction of some sort. So for more than two or
--   three vehicles a day to visit the service bay would be way too much. ... the type of logic that you should catch as
--   a fleet expert."
--   The busy_day scenario's fleet_overrides multiply each car's preventive-maintenance interval by 0.01 and its
--   calibration interval by 0.02 (public.ottoq_scenario_apply_fleet_overrides, applied at each run's start after the
--   boot draw). Read 2026-11-14 15:33-15:40 UTC, the twin depot:
--     the cars' own draws (ottoq_variability_cards)     PM 6,523-9,469 km (mean 8,017); calibration 181-320 h (mean 247)
--     what the cars carried after the scale             PM 65-95 km; calibration 3.6-6.4 h
--     run 7c967d67 (busy_day, 9.1 sim-hours): each car drove a mean 73.4 km and 1.38 h
--     service-bay work on that run's visits             mechanical_pm 106 on 102 of 116 cars; sensor_calibration 37;
--                                                       fault_repair 5; cosmetic_repair 1
--   On the cars' own intervals the same driving makes about 116 x 73.4 / 8,017 = 1.1 maintenance visits and
--   116 x 1.38 / 247 = 0.6 calibrations in that day. The scale made 143. It is also what built the two service bays'
--   36-hour line (db/checks/0493 (4)) and, under rule 9, held those cars at the depot for work no fleet would ask for.
--   I read that line on 2026-11-14 and filed it as the known wall of G500-G503. It was the scenario.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   One row of data: busy_day's vehicle_overrides.pm_interval_km_scale and calib_interval_h_scale become 1. At 1 the
--   loader leaves each car the interval its boot draw gave it (ottoq_run_boot_draw rewrites both every run, so no
--   scaled value survives from an earlier run). The wear phase stays on: each car starts the day at its own point in
--   its own cycle, so maintenance falls due at the fleet's real rate and not all at once. No function is changed. No
--   other scenario carried a scale. Fault repairs and cosmetic repairs are drawn elsewhere and are not touched.
--
-- ══ §3 CHECKS ════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight and no run running. P1 the row is as read (0.01 and 0.02) and the loader is the function
--   read (md5). P2 once. V1 both scales are 1, the rest of busy_day's overrides and every other scenario's row are
--   byte for byte what they were, and no scenario carries a scale other than 1.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE: every busy_day run draws a different day from here on (its
--   recalls for service, its visits' atoms, its bays). Nothing acts on either while testing is off (rule 12).
--   Learned estimates: the charge clock's evidence is charges, which this does not change, so no row is added to
--   ottoq_evidence_regimes. The return and departure fits did learn from days with these recalls and bay holds; they
--   have no regime of their own, and db/checks/0495 records that as open.
--
-- APPLIED 2026-11-14 15:35:39 UTC (9:35 AM CT), ledger 20261114153539, between runs, P0-P2 and V1 passing inside the
--   file; the ledger holds this file from BEGIN to COMMIT under a two-line header. The first run after it is
--   ff41e769 (db/checks/0495).
--
-- ROLLBACK: UPDATE public.ottoq_sim_scenarios SET fleet_overrides = jsonb_set(jsonb_set(fleet_overrides,
--   '{vehicle_overrides,pm_interval_km_scale}', '0.01'), '{vehicle_overrides,calib_interval_h_scale}', '0.02')
--   WHERE scenario_code = 'busy_day'; DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0837_a_busy_day_no_longer_shortens_every_cars_maintenance_interval'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight, no run running ──
DO $p0$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0837 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0837 P0: a run is running; apply between runs';
  END IF;
END $p0$;

-- ── P1: the row and the loader are as read; P2: once ──
DO $p1$
DECLARE v_fo jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0837_a_busy_day_no_longer_shortens_every_cars_maintenance_interval') THEN
    RAISE EXCEPTION '0837 P2: already applied';
  END IF;
  SELECT fleet_overrides INTO v_fo FROM public.ottoq_sim_scenarios WHERE scenario_code = 'busy_day';
  IF v_fo IS NULL OR (v_fo #>> '{vehicle_overrides,pm_interval_km_scale}')::numeric IS DISTINCT FROM 0.01
     OR (v_fo #>> '{vehicle_overrides,calib_interval_h_scale}')::numeric IS DISTINCT FROM 0.02 THEN
    RAISE EXCEPTION '0837 P1: busy_day''s vehicle_overrides are not the ones read: %', v_fo -> 'vehicle_overrides';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_scenario_apply_fleet_overrides(uuid)'))
       IS DISTINCT FROM '2b8e59042b5b068e7ada0e1121b7e70a' THEN
    RAISE EXCEPTION '0837 P1: the scenario loader is not the function read; read it again before applying';
  END IF;
END $p1$;

CREATE TEMP TABLE _0837_before ON COMMIT DROP AS
SELECT scenario_code,
       md5(CASE WHEN scenario_code = 'busy_day'
                THEN (fleet_overrides #- '{vehicle_overrides,pm_interval_km_scale}'
                                      #- '{vehicle_overrides,calib_interval_h_scale}')::text
                ELSE COALESCE(fleet_overrides::text, 'null') END) AS rest_md5
  FROM public.ottoq_sim_scenarios;

UPDATE public.ottoq_sim_scenarios
   SET fleet_overrides = jsonb_set(jsonb_set(fleet_overrides,
                           '{vehicle_overrides,pm_interval_km_scale}', '1'::jsonb),
                           '{vehicle_overrides,calib_interval_h_scale}', '1'::jsonb)
 WHERE scenario_code = 'busy_day';

-- ── V1 ──
DO $v1$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_sim_scenarios s
   WHERE COALESCE((s.fleet_overrides #>> '{vehicle_overrides,pm_interval_km_scale}')::numeric, 1) <> 1
      OR COALESCE((s.fleet_overrides #>> '{vehicle_overrides,calib_interval_h_scale}')::numeric, 1) <> 1;
  IF v_n > 0 THEN RAISE EXCEPTION '0837 V1 FAILED: % scenario(s) still scale a maintenance interval', v_n; END IF;
  IF (SELECT (fleet_overrides #>> '{vehicle_overrides,pm_interval_km_scale}') || '/'
             || (fleet_overrides #>> '{vehicle_overrides,calib_interval_h_scale}') || '/'
             || (fleet_overrides #>> '{wear_phase,enabled}')
        FROM public.ottoq_sim_scenarios WHERE scenario_code = 'busy_day') IS DISTINCT FROM '1/1/true' THEN
    RAISE EXCEPTION '0837 V1 FAILED: busy_day does not read 1, 1 and the wear phase on';
  END IF;
  SELECT count(*) INTO v_n
    FROM public.ottoq_sim_scenarios s FULL JOIN _0837_before b USING (scenario_code)
   WHERE b.scenario_code IS NULL OR s.scenario_code IS NULL
      OR b.rest_md5 IS DISTINCT FROM
         md5(CASE WHEN s.scenario_code = 'busy_day'
                  THEN (s.fleet_overrides #- '{vehicle_overrides,pm_interval_km_scale}'
                                          #- '{vehicle_overrides,calib_interval_h_scale}')::text
                  ELSE COALESCE(s.fleet_overrides::text, 'null') END);
  IF v_n > 0 THEN RAISE EXCEPTION '0837 V1 FAILED: % scenario row(s) changed beyond the two scales', v_n; END IF;
END $v1$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0837_a_busy_day_no_longer_shortens_every_cars_maintenance_interval', true, true,
        'G548. Data only: busy_day''s vehicle_overrides.pm_interval_km_scale 0.01 -> 1 and calib_interval_h_scale '
        '0.02 -> 1, so a busy day keeps each car''s own maintenance and calibration interval. Every busy_day run '
        'draws a different day from here on (its service recalls, its visits'' atoms, its bays). No function changed.',
        now());

COMMIT;
