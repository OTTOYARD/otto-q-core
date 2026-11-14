-- migration-version: 20261114055208
-- migration-name:    0833_the_twin_depots_fleet_carries_24_ojais_and_6_lucid_gravities
--
-- 0833  **The twin depot's fleet carries 24 Waymo Ojais and 6 Lucid Gravities, under their own owner.**
--
-- WHY. Chase, 2026-11-14 (2026-11-13 evening CT), on seeing 2 Ojais on the lot: "let's do the split for Waymo as
--   mentioned" (22 I-PACE and 24 Ojai) and "add a handful of the Lucids".
--
-- §1 WHAT WAS SO (read 2026-11-14, twin depot 11111111-…, 116 autonomous cars): Waymo Nashville 44 I-PACE and 2 Ojai;
--   Tesla Robotaxi TN 32 Model Y and 4 Cybercab; Zoox Southeast 34. No Lucid Gravity, though the port profiles (0824)
--   and the twin's robots carry it.
--
-- §2 WHAT THIS DOES. The fleet stays 116 cars; rows are changed, none is added.
--   (a) Waymo-AV-019 .. Waymo-AV-040 (22 cars) become Ojais, and the 2 Ojais already there take the same make and
--       model text ('Waymo', 'Ojai'). Waymo Nashville: 22 I-PACE, 24 Ojai.
--   (b) Tesla-AV-065 .. Tesla-AV-070 (6 Model Ys) become Lucid Gravities, Lucid-AV-001 .. 006, platform `nuro`, under a
--       new owner, 'Uber Robotaxi Nashville' (66666666-…). Tesla Robotaxi TN: 26 Model Y, 4 Cybercab. The owner is new
--       because a car's owner is its owner (rule 14): a Lucid is not Tesla's.
--   (c) Two vehicle classes, and the new owner's contract.
--   (d) One row in ottoq_evidence_regimes: these 28 cars' charges before now are another vehicle's.
--
-- §3 FACTS AND WHAT IS ASSUMED (rule 3; found by direct search 2026-11-14).
--   Lucid Gravity Grand Touring: 123 kWh gross, peak DC about 400 kW, NACS.
--     https://evkx.net/models/lucid/gravity/gravity_gt-s/ ; https://gcn.com/?p=22469 (2026-10)
--     The Lucid, Uber and Nuro robotaxi is built on the Gravity (CES 2026):
--     https://rallies.ai/news/lucid-uber-and-nuro-launch-six-passenger-robotaxi-begin-san-francisco-testing
--     ASSUMPTION — pending R-23: the robotaxi carries the Grand Touring's pack and charge rate; none is published.
--   Waymo Ojai (built by Zeekr): 93 kWh gross in most sources (one earlier report: 76 kWh), 800 V.
--     https://carnewschina.com/?p=265625 ; https://www.arenaev.com/waymo_launches_first_purposebuilt_robotaxi-news-5924.php
--     ASSUMPTION — pending R-23: peak DC 200 kW. No figure is published; the sources say only "faster than the I-PACE".
--     Its inlet's position and connector are 0824's assumptions, unchanged.
--   The new owner's contract is a copy of Tesla Robotaxi TN's terms (100% charge ceiling, 30-minute queue wait, 80%
--   deploy floor). It is a placeholder for the twin, not a term anyone agreed.
--   Both classes take the existing classes' three-step energy curve. The twin's own DC physics (0573) gives any car
--   but the Model Y and the I-PACE the median acceptance curve.
--   No arrival message is emulated for platform `nuro`: there is no ottoq_oem_webhook_patterns row, and
--   twin.ottoq_sim_emit_arrival_webhook drops such a car's message by design ("real OEM not yet onboarded").
--
-- §4 PRECONDITIONS AND CHECKS. P0 no certification in flight and no run running. P1 the cars are as read (40
--   'Waymo I-Pace', 2 'Zeekr RT AV', the six Teslas are Model Ys). P2 once. V: 116 autonomous cars; by port profile
--   waymo_ipace 22, waymo_ojai 24, tesla_model_y 26, tesla_cybercab 4, zoox_robotaxi 34, lucid_gravity_nuro 6; every
--   car resolves a profile and an active contract; no car of another depot changed.
--
-- §5 CLASSIFICATION. forces_recert TRUE (the fleet's batteries, charge rates and owners change), forces_dial_restart
--   FALSE.
--
-- ROLLBACK: the pre-image of every changed vehicles row is in public.ottoq_schema_snapshots, label '0833_pre' (one
--   row, object_kind 'data', definition = the rows as JSON). Restore make, model, year, platform, fleet_operator_id,
--   vehicle_class_code, battery_capacity_kwh, inlet_max_kw, inlet_type, connector_type, display_name and config from
--   it; DELETE the two classes, the contract, the owner, the regime row and the lineage row named 0833.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
DECLARE c_depot constant uuid := '11111111-1111-1111-1111-111111111111'; n int;
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0833 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN RAISE EXCEPTION '0833 P0: a run is live'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0833_%') THEN RAISE EXCEPTION '0833 P2: already applied'; END IF;
  SELECT count(*) INTO n FROM public.vehicles WHERE home_depot_id = c_depot AND make = 'Waymo' AND model = 'I-Pace'
     AND display_name BETWEEN 'Waymo-AV-001' AND 'Waymo-AV-040';
  IF n <> 40 THEN RAISE EXCEPTION '0833 P1: % Waymo I-Pace cars named Waymo-AV-001..040, not 40', n; END IF;
  SELECT count(*) INTO n FROM public.vehicles WHERE home_depot_id = c_depot AND make = 'Zeekr' AND model = 'RT AV';
  IF n <> 2 THEN RAISE EXCEPTION '0833 P1: % Zeekr RT AV cars, not 2', n; END IF;
  SELECT count(*) INTO n FROM public.vehicles WHERE home_depot_id = c_depot AND make = 'Tesla' AND model = 'Model Y'
     AND display_name BETWEEN 'Tesla-AV-065' AND 'Tesla-AV-070';
  IF n <> 6 THEN RAISE EXCEPTION '0833 P1: % Tesla Model Ys named Tesla-AV-065..070, not 6', n; END IF;
END $pre$;

-- the rows as they were
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0833_pre', 'data', 'public', 'vehicles (28 rows of the twin depot)', j::text, md5(j::text)
  FROM (SELECT jsonb_agg(to_jsonb(v) ORDER BY v.display_name) AS j FROM public.vehicles v
         WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
           AND ((v.make = 'Waymo' AND v.display_name BETWEEN 'Waymo-AV-019' AND 'Waymo-AV-040')
                OR (v.make = 'Zeekr' AND v.model = 'RT AV')
                OR (v.make = 'Tesla' AND v.display_name BETWEEN 'Tesla-AV-065' AND 'Tesla-AV-070'))) q;

-- ── the Lucids' owner and its contract (a copy of Tesla Robotaxi TN's terms; a placeholder for the twin) ──
INSERT INTO public.fleet_operators
SELECT (jsonb_populate_record(f, jsonb_build_object(
          'id', '66666666-6666-6666-6666-666666666666', 'name', 'Uber Robotaxi Nashville',
          'company', 'Uber Technologies Inc', 'slug', 'uber-robotaxi-nashville',
          'contact_name', 'Twin placeholder', 'contact_email', 'ops@uber-robotaxi-nashville.test',
          'contact_phone', NULL, 'created_at', now(), 'updated_at', now()))).*
  FROM public.fleet_operators f WHERE f.id = '33333333-3333-3333-3333-333333333333';

INSERT INTO public.ottoq_fleet_operator_slas
SELECT (jsonb_populate_record(s, jsonb_build_object(
          'sla_id', gen_random_uuid(), 'fleet_operator_id', '66666666-6666-6666-6666-666666666666',
          'contract_reference', 'OTTOYARD-DEPOT-MSA-2026-UBERRO', 'effective_from', now(), 'version', 1,
          'notes', '0833: a copy of Tesla Robotaxi TN''s terms for the twin''s six Lucid Gravities. A placeholder, not an agreed contract.',
          'created_at', now(), 'updated_at', now()))).*
  FROM public.ottoq_fleet_operator_slas s
 WHERE s.fleet_operator_id = '33333333-3333-3333-3333-333333333333' AND s.status = 'active';

-- ── the two classes ──
INSERT INTO public.ottoq_vehicle_classes
SELECT (jsonb_populate_record(c, jsonb_build_object(
          'vehicle_class_code', 'lucid_gravity_nuro_2026', 'oem_name', 'Lucid',
          'oem_fleet_operator_id', '66666666-6666-6666-6666-666666666666', 'manufacturer', 'Lucid',
          'model', 'Gravity (robotaxi)', 'model_year', 2026, 'battery_capacity_kwh', 123, 'battery_chemistry', NULL,
          'max_charge_rate_kw', 400, 'inlet_type', 'NACS', 'curb_weight_kg', NULL, 'introduced_in', '0833',
          'notes', 'Lucid Gravity as the Lucid, Uber and Nuro robotaxi. 123 kWh gross and about 400 kW peak DC are the Grand Touring''s (evkx.net, gcn.com, read 2026-11-14); ASSUMPTION pending R-23 that the robotaxi carries them. Energy curve copied from the existing classes.',
          'created_at', now()))).*
  FROM public.ottoq_vehicle_classes c WHERE c.vehicle_class_code = 'tesla_model_y_robotaxi_2024';

INSERT INTO public.ottoq_vehicle_classes
SELECT (jsonb_populate_record(c, jsonb_build_object(
          'vehicle_class_code', 'waymo_zeekr_ojai_2026', 'manufacturer', 'Zeekr', 'model', 'Ojai', 'model_year', 2026,
          'battery_capacity_kwh', 93, 'battery_chemistry', NULL, 'max_charge_rate_kw', 200, 'curb_weight_kg', NULL,
          'introduced_in', '0833',
          'notes', 'Waymo Ojai, built by Zeekr. 93 kWh gross, 800 V (carnewschina.com, arenaev.com, read 2026-11-14; one earlier report said 76 kWh). ASSUMPTION pending R-23: 200 kW peak DC and CCS1; neither is published. Energy curve copied from the I-PACE class.',
          'created_at', now()))).*
  FROM public.ottoq_vehicle_classes c WHERE c.vehicle_class_code = 'waymo_jaguar_ipace_2024';

-- ── (a) 24 Ojais ──
UPDATE public.vehicles v
   SET make = 'Waymo', model = 'Ojai', year = 2026, vehicle_class_code = 'waymo_zeekr_ojai_2026',
       battery_capacity_kwh = 93, inlet_max_kw = 200, inlet_type = 'CCS1',
       config = CASE WHEN v.config ? 'vehicle_class_code'
                     THEN v.config || jsonb_build_object('vehicle_class_code', 'waymo_zeekr_ojai_2026') ELSE v.config END
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
   AND ((v.make = 'Waymo' AND v.model = 'I-Pace' AND v.display_name BETWEEN 'Waymo-AV-019' AND 'Waymo-AV-040')
        OR (v.make = 'Zeekr' AND v.model = 'RT AV'));

-- ── (b) 6 Lucid Gravities, under their own owner ──
UPDATE public.vehicles v
   SET make = 'Lucid', model = 'Gravity', year = 2026, platform = 'nuro',
       fleet_operator_id = '66666666-6666-6666-6666-666666666666', vehicle_class_code = 'lucid_gravity_nuro_2026',
       battery_capacity_kwh = 123, inlet_max_kw = 400, inlet_type = 'NACS', connector_type = 'NACS',
       display_name = 'Lucid-AV-' || lpad((right(v.display_name, 3)::int - 64)::text, 3, '0'),
       config = COALESCE(v.config, '{}'::jsonb) || jsonb_build_object('oem', 'Lucid')
                || CASE WHEN v.config ? 'vehicle_class_code'
                        THEN jsonb_build_object('vehicle_class_code', 'lucid_gravity_nuro_2026') ELSE '{}'::jsonb END
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
   AND v.make = 'Tesla' AND v.model = 'Model Y' AND v.display_name BETWEEN 'Tesla-AV-065' AND 'Tesla-AV-070';

-- ── (d) the learned charge clock: these cars' earlier charges are another vehicle's ──
INSERT INTO public.ottoq_evidence_regimes (model, scope, depot_id, starts_at, reason, source, recorded_by, recorded_at)
VALUES ('charge_time_v2', 'dcfc', '11111111-1111-1111-1111-111111111111', now(),
        '0833 changed 28 cars'' facts at the twin depot: 22 Waymo I-PACEs (84.7 kWh, 104 kW) and 2 earlier Ojai rows became Ojais (93 kWh, 200 kW assumed), and 6 Tesla Model Ys (75 kWh, 250 kW) became Lucid Gravities (123 kWh, 400 kW). Fast charges of those cars before this ran on the earlier battery and charge rate. No trial was run first: there is no charge yet on the new side to try the cut against.',
        'migration 0833; recorded by 0833', current_user, now());

CREATE TEMP TABLE _0833_selftest (result jsonb) ON COMMIT DROP;
DO $v$
DECLARE c_depot constant uuid := '11111111-1111-1111-1111-111111111111'; v jsonb; n_all int; n_nosla int; n_noprof int;
BEGIN
  SELECT jsonb_object_agg(k, n) INTO v FROM (
    SELECT COALESCE((public.ottoq_vehicle_port_profile(x.id)).profile_key, 'none') k, count(*) n
      FROM public.vehicles x WHERE x.home_depot_id = c_depot AND x.category = 'autonomous' GROUP BY 1) q;
  SELECT count(*) INTO n_all FROM public.vehicles WHERE home_depot_id = c_depot AND category = 'autonomous';
  SELECT count(*) INTO n_nosla FROM public.vehicles x WHERE x.home_depot_id = c_depot AND x.category = 'autonomous'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_fleet_operator_slas s
                      WHERE s.fleet_operator_id = x.fleet_operator_id AND s.status = 'active');
  IF n_all <> 116 THEN RAISE EXCEPTION '0833 V: % autonomous cars, not 116', n_all; END IF;
  IF n_nosla > 0 THEN RAISE EXCEPTION '0833 V: % cars with no active contract', n_nosla; END IF;
  IF v IS DISTINCT FROM jsonb_build_object('waymo_ipace', 22, 'waymo_ojai', 24, 'tesla_model_y', 26, 'tesla_cybercab', 4,
                                           'zoox_robotaxi', 34, 'lucid_gravity_nuro', 6) THEN
    RAISE EXCEPTION '0833 V: the fleet by port profile is %', v;
  END IF;
  IF (SELECT count(DISTINCT display_name) FROM public.vehicles WHERE home_depot_id = c_depot) <>
     (SELECT count(*) FROM public.vehicles WHERE home_depot_id = c_depot) THEN
    RAISE EXCEPTION '0833 V: a display name is used twice';
  END IF;
  INSERT INTO _0833_selftest VALUES (v);
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0833_the_twin_depots_fleet_carries_24_ojais_and_6_lucid_gravities', true, false,
        'The twin depot''s fleet by port profile at apply: ' || COALESCE((SELECT result::text FROM _0833_selftest LIMIT 1), 'no result'), now());
COMMIT;

-- APPLIED 2026-11-14 at 05:52:08 UTC (2026-11-13, 11:52 PM CT), ledger 20261114055208, through apply_migration, on
--   the first send. No run was live. At apply, by port profile: waymo_ipace 22, waymo_ojai 24, tesla_model_y 26,
--   tesla_cybercab 4, zoox_robotaxi 34, lucid_gravity_nuro 6.
--   The run started to check it: 7435e685.
--   RUN 7435e685 AT ITS END (724 ticks, ended 2026-11-14 07:00:00 UTC, read 07:05 UTC). Every car of every kind
--   charged at least once. By port profile, cars / sessions / faulted / mean minutes of a completed session:
--     lucid_gravity_nuro  6 / 10 / 1 / 22      tesla_cybercab  4 / 12 / 3 / 31      tesla_model_y 26 / 56 / 2 / 36
--     waymo_ipace        22 / 41 / 3 / 77      waymo_ojai     24 / 48 / 3 / 33      zoox_robotaxi 34 / 82 / 7 / 30
--   The Ojai's 33 minutes against the I-PACE's 77 rests on the assumed 200 kW (R-23). All 6 Lucids left for work.
--   Visits with a charge done and cleaned by the post's arm: Lucid 8 of 8, Cybercab 8 of 8, Model Y 48 of 48, Ojai
--   45 of 45, I-PACE 31 of 32, Zoox 71 of 73. The 3 without: two Zoox visits tidied by a technician (one before its
--   charge stopped, one after the stop asked the arm and the tidy was not one the arm takes), and one I-PACE visit
--   still open at the run's end after two faulted sessions.
--   sim_tick_failed (a deadlock in the decide half): 53, against 23 to 38 on the five runs before. Not explained.
