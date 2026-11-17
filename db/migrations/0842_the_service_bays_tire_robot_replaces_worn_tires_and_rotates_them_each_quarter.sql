-- migration-version: PENDING
-- migration-name:    0842_the_service_bays_tire_robot_replaces_worn_tires_and_rotates_them_each_quarter
--
-- 0842  **OTTO-Q gives the service bays' tire robot (OTTO-TIRE) its two jobs: a worn set of tires is replaced, and the
--        tires are rotated once a quarter. Each is a required service of its own, seated for the robot's length, and
--        a worn tire no longer seats a car for preventive maintenance it does not need.**
--
-- WHY. Chase, 2026-11-17, after a run in which the robot never moved: "Let's not do a flat, because that would require
--   rolling the vehicle in on its rim (not safe/advised). Flats will be brought in via tow truck (OTTOW workflow) and
--   then jacked up in place at a parking spot for it to receive a new tire. The tire robot stall needs to be for worn
--   out tires and rotations (scheduled quarterly, and only occurs a few times per simulation run)."
--   The machine itself is ottoyarddepot-sim's cad/otto_cad/robots/tire_bay.py and docs/OTTO-TIRE.md (merged in that
--   repo's #179): a lift, a portal on floor rails and 2 wheel robots that swap whole wheels between the car and the
--   NEW and OLD racks.
--
-- §1 WHAT WAS SO (read 2026-11-17, production).
--   (a) service_cadence_policy, the live catalog, had no tire service. Nothing in OTTO-Q could send work to the robot.
--   (b) public.ottoq_vehicle_needs_card folds tire wear into preventive maintenance: mech_urgency =
--       max(pm_urgency, tire_urgency, brake_urgency), and that is the urgency of its 'mechanical_pm' row.
--       mechanical_pm is must-do at 'critical', and tire_urgency is critical under 2.7 mm. The seeder draws tread
--       uniform on 2.4 to 8.4 mm, so 1 car in 20 starts a run under 2.7 mm and is seated for mechanical_pm. The bay
--       exit credits mechanical_pm, which resets the PM clock and not the tread, so the card asks again: run 89ac9e74
--       (Chase's, 2026-11-17) held Waymo-AV-033 (tread 2.5 mm) and AV-038 (2.4 mm), both with PM not due, in the two
--       service bays for it. V3a below reproduces it.
--   (c) vehicle_need_profile.tire_rotation_due_km is drawn by the seeder and read by nothing. It is left as it is.
--   (d) Nothing in OTTO-Q models a flat tire (a fault is generic: open_fault_codes, fault_repair), so there is no flat
--       to send elsewhere yet. The tow-truck path Chase describes is its own build.
--
-- §2 WHAT THIS DOES.
--   CATALOG. Two rows in service_cadence_policy, lane 'service_bay', must-do at 'due':
--     tire_replacement  graded by the needs card on tread depth, as before: due under 3.0 mm, critical under 2.7 mm.
--     tire_rotation     interval 2,190 h (a quarter), graded on the time since the last rotation like every interval
--                       service (due at 1.0, overdue 1.10, critical 1.25).
--     Each is 12 minutes: the twin's program for all 4 wheels is 534 s on a Tesla Model Y (docs/OTTO-TIRE.md), plus the
--     drive on and off and the lift. ASSUMPTION, labelled in the rows' notes. sequence_order 62 and 64, after PM.
--   PROFILE. vehicle_need_profile.last_tire_rotation_at (new). The seeder draws it 12 h to a quarter ago, salt
--     'vnp:tirerot:', and now draws tread uniform on 2.9 to 8.0 mm, which rounds under 3.0 mm for about 1 car in 100.
--     Expected per run at the twin depot's 116 cars: about 1.1 replacements; rotations about 0.6 due at the start and
--     1.3 more falling due in a 24-hour day (116 / 91.25 days), plus those that ride along (below). "A few times per
--     simulation run." V7 reads the counts on the newest run's own seed.
--   NEEDS CARD. tire_replacement and tire_rotation are rows of their own. mechanical_pm's row is max(pm, brake).
--     New columns, appended: last_tire_rotation_at, tire_rotation_due_at, tire_rotation_ratio, tire_rotation_urgency.
--     A car whose tires are due for replacement is not graded for rotation (a new set restarts the quarter). The card's
--     overall urgency still counts tires.
--   VISIT. ottoq.ottoq_derive_visit_needs reads the car's own profile and puts each due tire job on the visit,
--     required (must_do, not deferrable), at the service bay, whatever the observer drew: 0715's rule for PM and
--     calibration. A rotation due within 14 days rides along when the car is going to the service bay for other
--     required work (its 'ridealong' key says so): the robot does it inside the seat it already has, and the car does
--     not come back for it in two weeks.
--   SEAT. public.ottoq_service_bay_seat_base_min: a service-bay seat whose only work is the robot's is the robot's 12
--     minutes, before the run's variability; a seat for any other service-bay work, or for a technician's flag, keeps
--     the bay's own default (40, or the L2 door's 45) and the robot works inside it. Read at all three doors to the
--     bay: the needs card's booking and the L2 service proposer's admission (service_sequencing) in
--     public.ottoq_decide_tick, each when no itinerary leg gives the length, and the twin's booked admission in
--     twin.ottoq_sim_advance_service_flow STEP 2. Measured in a rolled-back exercise of the tick before this file was
--     applied: without the L2 door's line a worn car's bay was booked for 45 minutes.
--   EXIT. The service bay's credit arrays (STEP 1 of the service flow, ottoq_bay_purpose_atoms,
--     ottoq_state_service_atoms) carry the two services, so the bay exit marks them done and
--     public.ottoq_wear_mark_serviced resets the car: a replacement fits 8.0 mm (the shallow end of a new car tire's
--     10/32 to 11/32 in) and restarts the quarter; a rotation restarts the quarter. ottoq_atom_retirable_set follows
--     ottoq_bay_purpose_atoms, so ottoq_atoms_guard keeps them required.
--   ROUTING LISTS that name the service bay's work by name gain the two: the gate intake's need_service step
--     (ottoq_decide_tick), the two L2 proposers, the leg closers at the bay exit and at a reported completion, the
--     cadence escalation, and the booking's reason text.
--   Rules. 9: each tire job is required and is finished before the car leaves (public.ottoq_departure_clear reads the
--   visit). 10: no setting and no experiment; a service added to the catalog. 12: one demo run to see it working; no
--   pair, no sweep. 13: no ceiling. 14: a tire job takes its place in the service bay's line as any other service
--   does; no owner's car is moved. 15: these are service-bay visits. Chase set their rate ("only occurs a few times
--   per simulation run"); at quarterly rotations a 116-car fleet averages 1.27 a day.
--
-- SOURCES (read 2026-11-17).
--   New car tires start at 10/32 to 11/32 in of tread (7.9 to 8.7 mm): Tire Rack,
--   https://www.tirerack.com/tires/tiretech/techpage.jsp?techid=197 ; 8 to 9 mm: Continental,
--   https://www.continental-tires.com/be/nl/tire-knowledge/tread-depth/ . The engine's 3.0 mm due line (the card's
--   own, kept) lies between the 4/32 in (3.2 mm) many sources give as the replacement point and the 2/32 in (1.6 mm)
--   legal minimum in most US states (same sources).
--
-- §3 PRECONDITIONS AND CHECKS. P0 no certification in flight and no live run at the twin depot. P1 the body of every
--   function and the view this file patches (md5). P2 once.
--   V1 every patched function is stored as its snapshot with exactly this file's substitutions, each matched once;
--      the view keeps its columns and gains the four, in order.
--   V2 the catalog declares the two (ottoq_assert_service_vocabulary: nothing undeclared), both are retirable, both
--      are in the service bay's credit arrays, and a signed-in reader may call the three functions the card uses.
--   V3 probes on the twin depot's newest finished run, rolled back. V3a, before the patch: a car with fresh PM and
--      2.6 mm tread is must-do for mechanical_pm (the defect, reproduced). V3b, after it: that car is must-do for
--      tire_replacement and not mechanical_pm; its visit carries tire_replacement, required, at the service bay, and
--      no rotation; its seat is 12 minutes alone and 40 with PM; the bay exit's wear reset fits 8.0 mm and clears it.
--      At 6.0 mm and a rotation 100 days ago it is must-do for tire_rotation and its visit carries it; the reset clears
--      it and keeps the tread. At 80 days, a visit with nothing else for the service bay carries no rotation, and a
--      visit with preventive maintenance carries one that rides along, in a 40-minute seat. The cadence escalation runs.
--   V7 the seeder, on the newest run's seed: how many of the twin depot's cars start worn and how many rotations fall
--      due in a day (reported, and bounded at 8 each).
--   V4 the decide tick and the service flow themselves, rolled back: on the newest finished run, one car staged full
--      with worn tires and nothing else, both service bays clear. The tick errs nowhere and books the car a service
--      bay for 12 minutes; the service flow seats it for 12 minutes times the run's own draw (at most 24).
--
-- §4 CLASSIFICATION. forces_recert TRUE: visits gain services, the service bays seat different cars for different
--   lengths, and the decisions that read them follow. forces_dial_restart FALSE.
--
-- ROLLBACK: for each function, EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0842_pre' AND
--   object_kind = 'function'. The view gained four columns, which CREATE OR REPLACE cannot remove: DROP VIEW
--   public.ottoq_vehicle_needs_card (nothing depends on it, read 2026-11-17) and CREATE it from its snapshot's
--   definition, then restore its comment and its grants (postgres, authenticated, service_role: all privileges).
--   DELETE FROM service_cadence_policy WHERE svc IN ('tire_replacement','tire_rotation'); drop the five 0842 helper
--   functions and the column vehicle_need_profile.last_tire_rotation_at; DELETE FROM public.ottoq_cert_lineage WHERE
--   name LIKE '0842_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
DECLARE r record;
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0842 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running') THEN
    RAISE EXCEPTION '0842 P0: a run is live at the twin depot; apply between runs';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)',              'bd34d1346bd3d17b8aa04a361cdc4913'),
      ('public.ottoq_decide_tick(uuid)',                                                     'd09961121632e5374405eb51d7ab6ee7'),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)',                 '02b12d958aba397731d50155c871b542'),
      ('public.ottoq_seed_vehicle_need_profiles(uuid)',                                      '833b89869e0c9bde223cae04e750cb69'),
      ('public.ottoq_wear_mark_serviced(uuid,uuid,text,timestamptz)',                        '30f6c25597f640ba9d7de40c92d198b1'),
      ('ottoq.ottoq_bay_purpose_atoms(text)',                                                '84bc5c3630789622deecabd563636051'),
      ('ottoq.ottoq_state_service_atoms(text)',                                              'ecc49c365a31d6e3c2a02e1a89c10b34'),
      ('public.ottoq_apply_need_escalation(uuid,boolean)',                                   '8cd87d9d4cc7122ec85d6db55bd334af'),
      ('public.ottoq_close_bay_seat_legs(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,text[])', '61e9e4d54ff8a096fe3a7f7c770cbed1'),
      ('public.ottoq_close_reported_work_legs(uuid,uuid,text[],timestamptz)',                'afb1590603d57ecabe72707f87b00315'),
      ('public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)',                        'ecb10ed6afcea74b16bb4b66b8a1608e'),
      ('public.ottoq_l2_propose_service(uuid,uuid,jsonb)',                                   'beb56749598523e65abb094c5d970ea5'),
      ('ottoq.ottoq_booking_why(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,uuid)',     'b57d868e67b617ec9174ee7fe2849cf2')
    ) AS t(f, m)
  LOOP
    IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.f)) IS DISTINCT FROM r.m THEN
      RAISE EXCEPTION '0842 P1: % is not the body this file was written against', r.f;
    END IF;
  END LOOP;
  IF md5(pg_get_viewdef('public.ottoq_vehicle_needs_card'::regclass)) IS DISTINCT FROM '2afb8f674652bc11dd190570c34054e3' THEN
    RAISE EXCEPTION '0842 P1: public.ottoq_vehicle_needs_card is not the view this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0842_%')
     OR EXISTS (SELECT 1 FROM public.service_cadence_policy WHERE svc IN ('tire_replacement', 'tire_rotation'))
     OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vehicle_need_profile'
                                                         AND column_name = 'last_tire_rotation_at') THEN
    RAISE EXCEPTION '0842 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0842_pre', 'function', split_part(f, '.', 1), f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY[
    'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)',
    'public.ottoq_decide_tick(uuid)',
    'twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)',
    'public.ottoq_seed_vehicle_need_profiles(uuid)',
    'public.ottoq_wear_mark_serviced(uuid,uuid,text,timestamptz)',
    'ottoq.ottoq_bay_purpose_atoms(text)',
    'ottoq.ottoq_state_service_atoms(text)',
    'public.ottoq_apply_need_escalation(uuid,boolean)',
    'public.ottoq_close_bay_seat_legs(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,text[])',
    'public.ottoq_close_reported_work_legs(uuid,uuid,text[],timestamptz)',
    'public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)',
    'public.ottoq_l2_propose_service(uuid,uuid,jsonb)',
    'ottoq.ottoq_booking_why(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,uuid)']) AS f
UNION ALL
SELECT '0842_pre', 'view', 'public', 'public.ottoq_vehicle_needs_card',
       pg_get_viewdef('public.ottoq_vehicle_needs_card'::regclass), md5(pg_get_viewdef('public.ottoq_vehicle_needs_card'::regclass));

-- ───── the profile: when the car's tires were last rotated ─────
ALTER TABLE public.vehicle_need_profile ADD COLUMN last_tire_rotation_at timestamptz;
COMMENT ON COLUMN public.vehicle_need_profile.last_tire_rotation_at IS
  '0842: when the car''s tires were last rotated (or replaced, which restarts the quarter). The needs card grades '
  'tire_rotation on the time since, against service_cadence_policy.interval_h (2,190 h). NULL: not known, never graded.';

-- ───── the catalog ─────
INSERT INTO public.service_cadence_policy (svc, display_name, category, lane, est_min_default, interval_h, interval_km,
                                           cadence_kind, due_soon_ratio, due_ratio, overdue_ratio, critical_ratio,
                                           must_do_at, lane_stalls, observed_clear_pct, sequence_order, notes, is_active)
VALUES
  ('tire_replacement', 'Tire replacement', 'mechanical', 'service_bay', 12, NULL, NULL,
   'condition', 0.75, 1.00, 1.25, 1.60, 'due', 2, NULL, 62,
   'OTTO-TIRE (0842): the service bay''s tire robot fits a new set of wheels (8.0 mm tread). Graded by the needs card on '
   || 'tread depth, not on these ratios: due under 3.0 mm, critical under 2.7 mm. A flat is not this robot''s work: '
   || 'Chase, 2026-11-17, a flat comes in on a tow truck and is jacked up where it is parked. 12 min: the twin''s program '
   || 'for all 4 wheels (534 s on a Tesla Model Y) plus the drive on and off, ASSUMPTION.', true),
  ('tire_rotation', 'Tire rotation', 'mechanical', 'service_bay', 12, 2190, NULL,
   'time', 0.90, 1.00, 1.10, 1.25, 'due', 2, NULL, 64,
   'OTTO-TIRE (0842): Chase, 2026-11-17, rotations are scheduled quarterly and only occur a few times per simulation '
   || 'run. Every 2,190 h. One due within 14 days rides along when the car is in the service bay for other required '
   || 'work. Not graded while the tires are due for replacement. 12 min, ASSUMPTION.', true);

-- ───── the helpers ─────
CREATE FUNCTION public.ottoq_tire_replacement_due(p_tread_mm numeric) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, public AS $f$
  -- 0842: a worn set: tread under 3.0 mm, the line at which the needs card grades the tires 'due'. Unknown tread is
  -- never due.
  SELECT COALESCE(p_tread_mm < 3.0, false)
$f$;

CREATE FUNCTION public.ottoq_tire_rotation_interval_h() RETURNS numeric
LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $f$
  -- 0842: the rotation's interval, read from the catalog (a quarter, 2,190 h, if the row is missing or zero)
  SELECT COALESCE((SELECT NULLIF(c.interval_h, 0) FROM public.service_cadence_policy c
                    WHERE c.svc = 'tire_rotation' AND c.is_active), 2190)
$f$;

CREATE FUNCTION public.ottoq_tire_rotation_ratio(p_last timestamptz, p_clock timestamptz) RETURNS numeric
LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $f$
  -- 0842: the time since the last rotation over the interval, as every interval service is graded. NULL when either
  -- clock is unknown.
  SELECT CASE WHEN p_last IS NULL OR p_clock IS NULL THEN NULL
              ELSE round((EXTRACT(EPOCH FROM (p_clock - p_last)) / 3600.0 / public.ottoq_tire_rotation_interval_h())::numeric, 3)
         END
$f$;

CREATE FUNCTION public.ottoq_tire_job_minutes(p_svc text) RETURNS numeric
LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $f$
  -- 0842: a tire job's length, from the catalog (12 if the row is missing)
  SELECT COALESCE((SELECT c.est_min_default FROM public.service_cadence_policy c WHERE c.svc = p_svc AND c.is_active), 12)
$f$;

CREATE FUNCTION public.ottoq_service_bay_seat_base_min(p_sim_run_id uuid, p_vehicle_id uuid, p_svc text, p_default numeric)
RETURNS numeric
LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $f$
  -- 0842: how long a service-bay seat is, before the run's variability. A seat whose only work is the tire robot's (a
  -- replacement or a rotation) is the robot's length. A seat for any other service-bay work, or for a technician's
  -- flag, keeps the bay's own default, and the robot's work is done inside it. p_svc is the need the seat is for (NULL:
  -- read the car's visit alone). Total: a missing input gives p_default, and nothing here raises.
  WITH v AS (
    SELECT n.atoms
      FROM public.ottoq_visit_needs n
     WHERE n.vehicle_id = p_vehicle_id AND n.status IN ('open', 'in_progress')
       AND COALESCE(n.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
     ORDER BY n.created_at DESC, n.visit_key DESC
     LIMIT 1
  ), open_bay AS (
    SELECT a ->> 'svc' AS svc,
           CASE WHEN (a ->> 'est_min') ~ '^[0-9]+(\.[0-9]+)?$' THEN (a ->> 'est_min')::numeric END AS est
      FROM v
      CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(v.atoms) = 'array' THEN v.atoms ELSE '[]'::jsonb END) a
      JOIN public.service_cadence_policy c ON c.svc = a ->> 'svc' AND c.is_active AND c.lane = 'service_bay'
     WHERE COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled', 'skipped')
  )
  SELECT CASE
           WHEN p_vehicle_id IS NULL THEN p_default
           WHEN p_svc IS NOT NULL AND p_svc NOT IN ('tire_replacement', 'tire_rotation') THEN p_default
           WHEN EXISTS (SELECT 1 FROM public.vehicles x
                         WHERE x.id = p_vehicle_id
                           AND lower(COALESCE(x.config ->> 'flagged_issue', 'false')) IN ('true', 't', '1')
                           AND COALESCE(x.config ->> 'flagged_issue_type', '') NOT IN ('deploy_gate_stuck', 'deploy_gate_hard_cap'))
             THEN p_default
           WHEN EXISTS (SELECT 1 FROM open_bay o WHERE o.svc NOT IN ('tire_replacement', 'tire_rotation')) THEN p_default
           WHEN p_svc IS NULL AND NOT EXISTS (SELECT 1 FROM open_bay) THEN p_default
           ELSE COALESCE(GREATEST((SELECT max(o.est) FROM open_bay o),
                                  CASE WHEN p_svc IN ('tire_replacement', 'tire_rotation')
                                       THEN public.ottoq_tire_job_minutes(p_svc) END),
                         p_default)
         END
$f$;

-- the needs card calls three of them, and EXECUTE is checked against the person reading the view (APPLYING.md §2)
GRANT EXECUTE ON FUNCTION public.ottoq_tire_replacement_due(numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_tire_rotation_interval_h() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_tire_rotation_ratio(timestamptz, timestamptz) TO authenticated;

-- V3a: the defect on the card as it was. The probe raises to roll its writes back; the answer is the exception's detail.
CREATE FUNCTION pg_temp._0842_pre_probe() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  c_depot CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_car uuid; v_r jsonb; v_detail text;
BEGIN
  SELECT p.vehicle_id INTO v_car FROM public.vehicle_need_profile p JOIN public.vehicles v ON v.id = p.vehicle_id
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous' AND v.is_active ORDER BY v.id LIMIT 1;
  IF v_car IS NULL THEN RAISE EXCEPTION '0842 V3a: no car to probe with'; END IF;
  BEGIN
    UPDATE public.vehicle_need_profile
       SET tire_tread_mm = 2.6, km_at_last_pm = odometer_km, brake_wear_pct = 10
     WHERE vehicle_id = v_car;
    SELECT jsonb_build_object('must_do_now', to_jsonb(c.must_do_now), 'tire_urgency', c.tire_urgency,
                              'pm_urgency', c.pm_urgency, 'pm_ratio', c.pm_ratio)
      INTO v_r FROM public.ottoq_vehicle_needs_card c WHERE c.vehicle_id = v_car;
    RAISE EXCEPTION USING ERRCODE = 'OQ842', MESSAGE = '0842 V3a probe', DETAIL = COALESCE(v_r, '{}'::jsonb)::text;
  EXCEPTION WHEN SQLSTATE 'OQ842' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN v_detail::jsonb;
  END;
END $f$;

DO $v3a$
DECLARE v_r jsonb := pg_temp._0842_pre_probe();
BEGIN
  IF NOT COALESCE((v_r->'must_do_now') ? 'mechanical_pm', false) OR (v_r->>'tire_urgency') IS DISTINCT FROM 'critical'
     OR (v_r->>'pm_urgency') IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION '0842 V3a: the defect did not reproduce on the card as it was: %', v_r;
  END IF;
  RAISE NOTICE '0842 V3a (before): %', v_r;
END $v3a$;

-- ───── the substitutions ─────
CREATE TEMP TABLE _0842_patch (obj text, seq int, c_old text, c_new text, PRIMARY KEY (obj, seq)) ON COMMIT DROP;

-- the seeder
INSERT INTO _0842_patch VALUES
('public.ottoq_seed_vehicle_need_profiles(uuid)', 1,
$o$      ottoq_sim_seeded_random(v_seed, 'vnp:tire:'     || f.id::text) AS r_tire,
$o$,
$n$      ottoq_sim_seeded_random(v_seed, 'vnp:tire:'     || f.id::text) AS r_tire,
      ottoq_sim_seeded_random(v_seed, 'vnp:tirerot:'  || f.id::text) AS r_tirerot,   -- 0842
$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 2,
$o$    round((2.4 + 6.0 * c.r_tire)::numeric, 1),
$o$,
$n$    round((2.9 + 5.1 * c.r_tire)::numeric, 1),   -- 0842: rounds under 3.0 mm (a worn set) for about 1 car in 100
$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 3,
$o$    open_fault_codes, worst_fault_severity, tire_tread_mm, tire_rotation_due_km, brake_wear_pct,
$o$,
$n$    open_fault_codes, worst_fault_severity, tire_tread_mm, tire_rotation_due_km, brake_wear_pct, last_tire_rotation_at,
$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 4,
$o$    round((5 + 80 * c.r_brake)::numeric, 1),
$o$,
$n$    round((5 + 80 * c.r_brake)::numeric, 1),
    -- 0842: the last tire rotation, 12 h to a quarter ago
    v_clock - make_interval(hours => (12 + floor(public.ottoq_tire_rotation_interval_h() * c.r_tirerot))::int),
$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 5,
$o$    brake_wear_pct = EXCLUDED.brake_wear_pct,
$o$,
$n$    brake_wear_pct = EXCLUDED.brake_wear_pct,
    last_tire_rotation_at = EXCLUDED.last_tire_rotation_at,   -- 0842
$n$);

-- the deriver
INSERT INTO _0842_patch VALUES
('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)', 1,
$o$  v_pm_due boolean := false; v_calib_due boolean := false;   --: 0715
$o$,
$n$  v_pm_due boolean := false; v_calib_due boolean := false;   --: 0715
  v_tread numeric; v_rot_last timestamptz; v_rot_ratio numeric;              -- 0842
  v_tire_replace boolean := false; v_tire_rotate boolean := false;          -- 0842
$n$),
('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)', 2,
$o$  IF COALESCE((p_obs->>'cosmetic_repair')::boolean, false) THEN
$o$,
$n$  /* 0842 (Chase, 2026-11-17): the service bays' tire robot does two jobs, a worn set of tires and the quarterly
     rotation. Both are read from the car's own profile, so each is required on this visit whatever the observer drew
     (0715's rule). A worn set (tread under 3.0 mm, the needs card's own 'due') is replaced, and a car whose tires are
     replaced is not also rotated. A rotation is due a quarter after the last one; one due within 14 days rides along
     when the car is going to the service bay for other required work. A flat is not this robot's work: it comes in on
     a tow truck and is changed where it is parked. */
  SELECT p.tire_tread_mm, p.last_tire_rotation_at INTO v_tread, v_rot_last
    FROM public.vehicle_need_profile p WHERE p.vehicle_id = p_vehicle_id;
  v_rot_ratio    := public.ottoq_tire_rotation_ratio(v_rot_last, v_clock);
  v_tire_replace := public.ottoq_tire_replacement_due(v_tread);
  v_tire_rotate  := NOT v_tire_replace
                    AND (COALESCE(v_rot_ratio, 0) >= 1
                         OR (COALESCE(v_rot_ratio, 0) >= 1 - 14 * 24 / public.ottoq_tire_rotation_interval_h()
                             AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e
                                          WHERE e->>'requires_bay' = 'service_bay'
                                            AND COALESCE((e->>'must_do')::boolean, false))));
  IF v_tire_replace AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'tire_replacement') THEN
    v_m := v_m || jsonb_build_object('svc','tire_replacement','must_do',true,'deferrable',false,
      'est_min',public.ottoq_tire_job_minutes('tire_replacement'),'concurrency','bay','requires_bay','service_bay',
      'carryover_eligible',false,'tread_mm',v_tread);
  END IF;
  IF v_tire_rotate AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'tire_rotation') THEN
    v_m := v_m || jsonb_build_object('svc','tire_rotation','must_do',true,'deferrable',false,
      'est_min',public.ottoq_tire_job_minutes('tire_rotation'),'concurrency','bay','requires_bay','service_bay',
      'carryover_eligible',false,'rotation_ratio',v_rot_ratio,'ridealong',COALESCE(v_rot_ratio, 0) < 1);
  END IF;
  IF COALESCE((p_obs->>'cosmetic_repair')::boolean, false) THEN
$n$);

-- the bay exit's wear reset
INSERT INTO _0842_patch VALUES
('public.ottoq_wear_mark_serviced(uuid,uuid,text,timestamptz)', 1,
$o$      last_pm_at = CASE WHEN p_service = 'mechanical_pm'
                          THEN p_clock ELSE p.last_pm_at END,
$o$,
$n$      last_pm_at = CASE WHEN p_service = 'mechanical_pm'
                          THEN p_clock ELSE p.last_pm_at END,
      -- 0842: the tire robot's two jobs. A replacement fits a new set (8.0 mm, the shallow end of a new car tire's
      -- 10/32 to 11/32 in) and restarts the rotation quarter; a rotation restarts the quarter and keeps the tread.
      tire_tread_mm = CASE WHEN p_service = 'tire_replacement'
                          THEN 8.0 ELSE p.tire_tread_mm END,
      last_tire_rotation_at = CASE WHEN p_service IN ('tire_rotation', 'tire_replacement')
                          THEN p_clock ELSE p.last_tire_rotation_at END,
$n$);

-- the service bay's credit arrays
INSERT INTO _0842_patch VALUES
('ottoq.ottoq_bay_purpose_atoms(text)', 1,
$o$WHEN 'service' THEN ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair']$o$,
$n$WHEN 'service' THEN ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair',
                                'tire_replacement','tire_rotation']   -- 0842$n$),
('ottoq.ottoq_state_service_atoms(text)', 1,
$o$WHEN 'in_service_bay' THEN ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair']$o$,
$n$WHEN 'in_service_bay' THEN ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair',
                                       'tire_replacement','tire_rotation']   -- 0842$n$),
('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)', 1,
$o$ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END;$o$,
$n$ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair',
                                  'tire_replacement','tire_rotation'] END;   -- 0842$n$),
('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)', 2,
$o$ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END, v_end_ts);$o$,
$n$ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair',
                       'tire_replacement','tire_rotation'] END, v_end_ts);   -- 0842$n$),
-- the twin's booked admission to a service bay: a seat for the robot alone is the robot's length (0842)
('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)', 3,
$o$((v_svc_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'maintenance_time',$o$,
$n$((ottoq_sim_service_minutes(p_sim_run_id, 'maintenance_time', public.ottoq_service_bay_seat_base_min(p_sim_run_id, v_rec.id, NULL, 40)) * COALESCE(ottoq_twin_deal(p_sim_run_id, 'maintenance_time',$n$);

-- the decide tick: the gate intake's step, and the needs card's booking length
INSERT INTO _0842_patch VALUES
('public.ottoq_decide_tick(uuid)', 1,
$o$AND a2->>'svc' IN ('mechanical_pm','fault_repair','sensor_calibration')$o$,
$n$AND a2->>'svc' IN ('mechanical_pm','fault_repair','sensor_calibration','tire_replacement','tire_rotation') /* 0842 */$n$),
('public.ottoq_decide_tick(uuid)', 2,
$o$ELSE 40 END AS base_min$o$,
$n$ELSE public.ottoq_service_bay_seat_base_min(p_sim_run_id, k.vehicle_id, x.svc, 40) END AS base_min   -- 0842$n$),
-- the L2 service proposer's admission (service_sequencing): with no planned leg, its default is the robot's length
-- for a car whose only service-bay work is the robot's
('public.ottoq_decide_tick(uuid)', 3,
$o$make_interval(mins => ottoq_policy_get(p_sim_run_id,'service_bay_default_min',45)::int)),$o$,
$n$make_interval(mins => public.ottoq_service_bay_seat_base_min(p_sim_run_id, v_req.vehicle_id, NULL,
                                              ottoq_policy_get(p_sim_run_id,'service_bay_default_min',45))::int)),   -- 0842$n$);

-- the cadence escalation
INSERT INTO _0842_patch VALUES
('public.ottoq_apply_need_escalation(uuid,boolean)', 1,
$o$             WHEN 'mechanical_pm'       THEN ottoq_urgency_max(c.pm_urgency,
                                              ottoq_urgency_max(c.tire_urgency, c.brake_urgency))
$o$,
$n$             WHEN 'mechanical_pm'       THEN ottoq_urgency_max(c.pm_urgency, c.brake_urgency)   -- 0842: tires are their own
             WHEN 'tire_replacement'    THEN c.tire_urgency
             WHEN 'tire_rotation'       THEN c.tire_rotation_urgency
$n$);

-- the leg closers, the L2 proposers and the booking's reason
INSERT INTO _0842_patch VALUES
('public.ottoq_close_bay_seat_legs(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,text[])', 1,
$o$'sensor_calibration', 'fault_repair', 'cosmetic_repair');$o$,
$n$'sensor_calibration', 'fault_repair', 'cosmetic_repair',
                                                 'tire_replacement', 'tire_rotation');   -- 0842$n$),
('public.ottoq_close_bay_seat_legs(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,text[])', 2,
$o$WHEN 'cosmetic_repair' THEN 'service' END = v_type$o$,
$n$WHEN 'cosmetic_repair' THEN 'service'
                                                          WHEN 'tire_replacement' THEN 'service'
                                                          WHEN 'tire_rotation' THEN 'service' END = v_type$n$),
('public.ottoq_close_reported_work_legs(uuid,uuid,text[],timestamptz)', 1,
$o$'cosmetic_repair') THEN$o$,
$n$'cosmetic_repair', 'tire_replacement', 'tire_rotation') THEN   -- 0842$n$),
('public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)', 1,
$o$AND a->>'svc' IN ('mechanical_pm','sensor_calibration','cosmetic_repair','fault_repair')$o$,
$n$AND a->>'svc' IN ('mechanical_pm','sensor_calibration','cosmetic_repair','fault_repair','tire_replacement','tire_rotation') /* 0842 */$n$),
('public.ottoq_l2_propose_service(uuid,uuid,jsonb)', 1,
$o$AND a->>'svc' IN ('mechanical_pm','sensor_calibration','cosmetic_repair','fault_repair')$o$,
$n$AND a->>'svc' IN ('mechanical_pm','sensor_calibration','cosmetic_repair','fault_repair','tire_replacement','tire_rotation') /* 0842 */$n$),
('ottoq.ottoq_booking_why(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,uuid)', 1,
$o$'mechanical_pm','fault_repair','cosmetic_repair',$o$,
$n$'mechanical_pm','fault_repair','cosmetic_repair','tire_replacement','tire_rotation',$n$);

-- the needs card
INSERT INTO _0842_patch VALUES
('view:public.ottoq_vehicle_needs_card', 1,
$o$            p.tire_rotation_due_km,
$o$,
$n$            p.tire_rotation_due_km,
            p.last_tire_rotation_at,
$n$),
('view:public.ottoq_vehicle_needs_card', 2,
$o$            b.tire_rotation_due_km,
$o$,
$n$            b.tire_rotation_due_km,
            b.last_tire_rotation_at,
$n$),
('view:public.ottoq_vehicle_needs_card', 3,
$o$            (b.last_calibration_at + make_interval(hours => (COALESCE(b.calib_interval_h, (250)::numeric))::integer)) AS calib_due_at,
$o$,
$n$            (b.last_calibration_at + make_interval(hours => (COALESCE(b.calib_interval_h, (250)::numeric))::integer)) AS calib_due_at,
            ottoq_tire_rotation_ratio(b.last_tire_rotation_at, b.sim_clock) AS tire_rotation_ratio,
            (b.last_tire_rotation_at + make_interval(hours => (ottoq_tire_rotation_interval_h())::integer)) AS tire_rotation_due_at,
$n$),
('view:public.ottoq_vehicle_needs_card', 4,
$o$            c.tire_rotation_due_km,
$o$,
$n$            c.tire_rotation_due_km,
            c.last_tire_rotation_at,
$n$),
('view:public.ottoq_vehicle_needs_card', 5,
$o$            c.calib_due_at,
$o$,
$n$            c.calib_due_at,
            c.tire_rotation_ratio,
            c.tire_rotation_due_at,
$n$),
('view:public.ottoq_vehicle_needs_card', 6,
$o$                END AS tire_urgency,
$o$,
$n$                END AS tire_urgency,
                CASE
                    WHEN ottoq_tire_replacement_due(c.tire_tread_mm) THEN 'ok'::text
                    ELSE ottoq_service_urgency('tire_rotation'::text, c.tire_rotation_ratio)
                END AS tire_rotation_urgency,
$n$),
('view:public.ottoq_vehicle_needs_card', 7,
$o$            g.tire_rotation_due_km,
$o$,
$n$            g.tire_rotation_due_km,
            g.last_tire_rotation_at,
$n$),
('view:public.ottoq_vehicle_needs_card', 8,
$o$            g.calib_due_at,
$o$,
$n$            g.calib_due_at,
            g.tire_rotation_ratio,
            g.tire_rotation_due_at,
$n$),
('view:public.ottoq_vehicle_needs_card', 9,
$o$            g.tire_urgency,
$o$,
$n$            g.tire_urgency,
            g.tire_rotation_urgency,
$n$),
('view:public.ottoq_vehicle_needs_card', 10,
$o$            ottoq_urgency_max(g.pm_urgency, ottoq_urgency_max(g.tire_urgency, g.brake_urgency)) AS mech_urgency
$o$,
$n$            ottoq_urgency_max(ottoq_urgency_max(g.pm_urgency, g.tire_rotation_urgency), ottoq_urgency_max(g.tire_urgency, g.brake_urgency)) AS mech_urgency
$n$),
('view:public.ottoq_vehicle_needs_card', 11,
$o$('mechanical_pm'::text,m.mech_urgency,true)$o$,
$n$('mechanical_pm'::text,ottoq_urgency_max(m.pm_urgency, m.brake_urgency),true), ('tire_replacement'::text,m.tire_urgency,true), ('tire_rotation'::text,m.tire_rotation_urgency,true)$n$),
('view:public.ottoq_vehicle_needs_card', 12,
$o$            m.tire_rotation_due_km,
$o$,
$n$            m.tire_rotation_due_km,
            m.last_tire_rotation_at,
$n$),
('view:public.ottoq_vehicle_needs_card', 13,
$o$            m.calib_due_at,
$o$,
$n$            m.calib_due_at,
            m.tire_rotation_ratio,
            m.tire_rotation_due_at,
$n$),
('view:public.ottoq_vehicle_needs_card', 14,
$o$            m.tire_urgency,
$o$,
$n$            m.tire_urgency,
            m.tire_rotation_urgency,
$n$),
('view:public.ottoq_vehicle_needs_card', 15,
$o$'tire_tread_mm', tire_tread_mm, 'tire_urgency', tire_urgency,$o$,
$n$'tire_tread_mm', tire_tread_mm, 'tire_urgency', tire_urgency, 'last_tire_rotation_at', last_tire_rotation_at, 'tire_rotation_due_at', tire_rotation_due_at, 'tire_rotation_urgency', tire_rotation_urgency,$n$),
('view:public.ottoq_vehicle_needs_card', 16,
$o$    (COALESCE(array_length(owed_bay_svcs_raw, 1), 0) > 0) AS rebook_owed
   FROM roll r;$o$,
$n$    (COALESCE(array_length(owed_bay_svcs_raw, 1), 0) > 0) AS rebook_owed,
    last_tire_rotation_at,
    tire_rotation_due_at,
    tire_rotation_ratio,
    tire_rotation_urgency
   FROM roll r;$n$);

DO $patch$
DECLARE
  o record; p record; v_def text; v_snap text; n int;
  v_cols_before text[]; v_cols_after text[];
BEGIN
  FOR o IN SELECT DISTINCT obj FROM _0842_patch ORDER BY obj LOOP
    IF o.obj LIKE 'view:%' THEN
      v_def := pg_get_viewdef('public.ottoq_vehicle_needs_card'::regclass);
    ELSE
      v_def := pg_get_functiondef(to_regprocedure(o.obj));
    END IF;
    v_snap := v_def;
    FOR p IN SELECT * FROM _0842_patch WHERE obj = o.obj ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN RAISE EXCEPTION '0842 V1: % substitution % matches % times, not 1', o.obj, p.seq, n; END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    IF o.obj LIKE 'view:%' THEN
      SELECT array_agg(a.attname::text ORDER BY a.attnum) INTO v_cols_before
        FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_vehicle_needs_card'::regclass AND a.attnum > 0 AND NOT a.attisdropped;
      EXECUTE 'CREATE OR REPLACE VIEW public.ottoq_vehicle_needs_card AS ' || v_def;
      SELECT array_agg(a.attname::text ORDER BY a.attnum) INTO v_cols_after
        FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_vehicle_needs_card'::regclass AND a.attnum > 0 AND NOT a.attisdropped;
      IF v_cols_after IS DISTINCT FROM v_cols_before
                                     || ARRAY['last_tire_rotation_at', 'tire_rotation_due_at', 'tire_rotation_ratio', 'tire_rotation_urgency'] THEN
        RAISE EXCEPTION '0842 V1: the needs card''s columns are not its old ones and the four, in order: %', v_cols_after;
      END IF;
    ELSE
      EXECUTE v_def;
      IF pg_get_functiondef(to_regprocedure(o.obj)) IS DISTINCT FROM v_def THEN
        RAISE EXCEPTION '0842 V1: % is not stored as patched', o.obj;
      END IF;
      IF md5(v_snap) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                        WHERE s.label = '0842_pre' AND s.object_name = o.obj
                                        ORDER BY s.snapshot_id DESC LIMIT 1) THEN
        RAISE EXCEPTION '0842 V1: % was patched from a body that is not its snapshot', o.obj;
      END IF;
    END IF;
  END LOOP;
END $patch$;

-- V2: declared, retirable, credited at the service bay's exit, readable by a signed-in reader
DO $v2$
DECLARE v record;
BEGIN
  SELECT * INTO v FROM public.ottoq_assert_service_vocabulary();
  IF cardinality(v.undeclared) <> 0 THEN RAISE EXCEPTION '0842 V2: undeclared services: %', v.undeclared; END IF;
  IF NOT (ottoq.ottoq_atom_retirable('tire_replacement') AND ottoq.ottoq_atom_retirable('tire_rotation')) THEN
    RAISE EXCEPTION '0842 V2: the tire services are not retirable, so ottoq_atoms_guard would demote them';
  END IF;
  IF NOT (ottoq.ottoq_bay_purpose_atoms('service') @> ARRAY['tire_replacement', 'tire_rotation']
          AND ottoq.ottoq_state_service_atoms('in_service_bay') @> ARRAY['tire_replacement', 'tire_rotation']) THEN
    RAISE EXCEPTION '0842 V2: the service bay''s credit arrays do not carry the tire services';
  END IF;
  IF NOT (has_function_privilege('authenticated', 'public.ottoq_tire_replacement_due(numeric)', 'EXECUTE')
          AND has_function_privilege('authenticated', 'public.ottoq_tire_rotation_interval_h()', 'EXECUTE')
          AND has_function_privilege('authenticated', 'public.ottoq_tire_rotation_ratio(timestamptz,timestamptz)', 'EXECUTE')) THEN
    RAISE EXCEPTION '0842 V2: a signed-in reader of the needs card cannot call the tire functions it uses';
  END IF;
END $v2$;

-- V3b and V7: the probes after the patch, rolled back the same way
CREATE FUNCTION pg_temp._0842_post_probe() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  c_depot CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_start timestamptz; v_car uuid; v_r jsonb := '{}'::jsonb; v_detail text;
  v_card record; v_atoms jsonb;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start), r.sim_clock_start INTO v_run, v_clock, v_start
    FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot AND r.status = 'completed' ORDER BY r.started_at DESC LIMIT 1;
  SELECT p.vehicle_id INTO v_car FROM public.vehicle_need_profile p JOIN public.vehicles v ON v.id = p.vehicle_id
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous' AND v.is_active ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_car IS NULL THEN RAISE EXCEPTION '0842 V3b: no run or car to probe with'; END IF;
  BEGIN
    -- nothing else for the service bay on the card: PM fresh, brakes good, calibration fresh, no fault
    UPDATE public.vehicle_need_profile
       SET tire_tread_mm = 2.6, last_tire_rotation_at = v_clock - interval '100 days',
           km_at_last_pm = odometer_km, brake_wear_pct = 10, last_calibration_at = v_clock, sensor_health_pct = 99,
           worst_fault_severity = 99, open_fault_codes = '{}'::text[]
     WHERE vehicle_id = v_car;
    -- and nothing interval-due on the run's wear ledger (the deriver's 0715 read)
    UPDATE public.ottoq_vehicle_wear SET km_at_last_pm = drive_km_total, hours_at_last_calibration = drive_hours_total
     WHERE vehicle_id = v_car AND sim_run_id = v_run;
    -- each step below closes the visit before it, as a bay exit would, so the deriver's 0698 carry has nothing owed
    UPDATE public.ottoq_visit_needs SET status = 'complete' WHERE vehicle_id = v_car AND status IN ('open', 'in_progress');

    -- (1) worn: replacement on the card, not PM, and no rotation while the tires are due for replacement
    SELECT * INTO v_card FROM public.ottoq_vehicle_needs_card c WHERE c.vehicle_id = v_car;
    v_r := v_r || jsonb_build_object('worn_card', jsonb_build_object('must_do_now', to_jsonb(v_card.must_do_now),
             'tire_urgency', v_card.tire_urgency, 'tire_rotation_urgency', v_card.tire_rotation_urgency));
    -- (2) worn: the visit
    PERFORM ottoq.ottoq_derive_visit_needs(v_car, v_run, v_run, v_clock + interval '1 minutes', c_depot, '{}'::jsonb);
    SELECT n.atoms INTO v_atoms FROM public.ottoq_visit_needs n
     WHERE n.vehicle_id = v_car AND n.sim_run_id = v_run AND n.status = 'open' ORDER BY n.created_at DESC LIMIT 1;
    v_r := v_r || jsonb_build_object('worn_visit', (SELECT COALESCE(jsonb_agg(jsonb_build_object('svc', a->>'svc',
             'must_do', a->'must_do', 'requires_bay', a->'requires_bay', 'est_min', a->'est_min')), '[]'::jsonb)
             FROM jsonb_array_elements(v_atoms) a WHERE a->>'svc' LIKE 'tire%'));
    -- (3) the seat: the robot's length alone, the bay's own with other work
    v_r := v_r || jsonb_build_object('seat_alone', public.ottoq_service_bay_seat_base_min(v_run, v_car, NULL, 40),
             'seat_for_tires', public.ottoq_service_bay_seat_base_min(v_run, v_car, 'tire_replacement', 40),
             'seat_for_pm', public.ottoq_service_bay_seat_base_min(v_run, v_car, 'mechanical_pm', 40));
    -- (4) the bay exit's reset
    PERFORM public.ottoq_wear_mark_serviced(v_car, v_run, 'tire_replacement', v_clock);
    SELECT * INTO v_card FROM public.ottoq_vehicle_needs_card c WHERE c.vehicle_id = v_car;
    v_r := v_r || jsonb_build_object('replaced', jsonb_build_object('tread_mm', v_card.tire_tread_mm,
             'rotation_ratio', v_card.tire_rotation_ratio, 'must_do_now', to_jsonb(v_card.must_do_now)));

    -- (5) a rotation 100 days ago
    UPDATE public.vehicle_need_profile SET tire_tread_mm = 6.0, last_tire_rotation_at = v_clock - interval '100 days'
     WHERE vehicle_id = v_car;
    SELECT * INTO v_card FROM public.ottoq_vehicle_needs_card c WHERE c.vehicle_id = v_car;
    UPDATE public.ottoq_visit_needs SET status = 'complete' WHERE vehicle_id = v_car AND status IN ('open', 'in_progress');
    PERFORM ottoq.ottoq_derive_visit_needs(v_car, v_run, v_run, v_clock + interval '2 minutes', c_depot, '{}'::jsonb);
    SELECT n.atoms INTO v_atoms FROM public.ottoq_visit_needs n
     WHERE n.vehicle_id = v_car AND n.sim_run_id = v_run AND n.status = 'open' ORDER BY n.created_at DESC LIMIT 1;
    v_r := v_r || jsonb_build_object('rotation_card', jsonb_build_object('must_do_now', to_jsonb(v_card.must_do_now),
             'ratio', v_card.tire_rotation_ratio, 'urgency', v_card.tire_rotation_urgency, 'due_at', v_card.tire_rotation_due_at),
             'rotation_visit', (SELECT COALESCE(jsonb_agg(jsonb_build_object('svc', a->>'svc', 'must_do', a->'must_do',
               'ridealong', a->'ridealong')), '[]'::jsonb) FROM jsonb_array_elements(v_atoms) a WHERE a->>'svc' LIKE 'tire%'));
    -- (6) rotated
    PERFORM public.ottoq_wear_mark_serviced(v_car, v_run, 'tire_rotation', v_clock);
    SELECT * INTO v_card FROM public.ottoq_vehicle_needs_card c WHERE c.vehicle_id = v_car;
    v_r := v_r || jsonb_build_object('rotated', jsonb_build_object('tread_mm', v_card.tire_tread_mm,
             'rotation_ratio', v_card.tire_rotation_ratio, 'must_do_now', to_jsonb(v_card.must_do_now)));

    -- (7) 80 days: no rotation alone; one rides along with preventive maintenance, in the bay's own seat
    UPDATE public.vehicle_need_profile SET last_tire_rotation_at = v_clock - interval '80 days' WHERE vehicle_id = v_car;
    UPDATE public.ottoq_visit_needs SET status = 'complete' WHERE vehicle_id = v_car AND status IN ('open', 'in_progress');
    PERFORM ottoq.ottoq_derive_visit_needs(v_car, v_run, v_run, v_clock + interval '3 minutes', c_depot, '{}'::jsonb);
    SELECT n.atoms INTO v_atoms FROM public.ottoq_visit_needs n
     WHERE n.vehicle_id = v_car AND n.sim_run_id = v_run AND n.status = 'open' ORDER BY n.created_at DESC LIMIT 1;
    v_r := v_r || jsonb_build_object('early_alone', (SELECT COALESCE(jsonb_agg(a->>'svc'), '[]'::jsonb)
             FROM jsonb_array_elements(v_atoms) a WHERE a->>'svc' LIKE 'tire%'));
    UPDATE public.ottoq_visit_needs SET status = 'complete' WHERE vehicle_id = v_car AND status IN ('open', 'in_progress');
    PERFORM ottoq.ottoq_derive_visit_needs(v_car, v_run, v_run, v_clock + interval '4 minutes', c_depot, '{"mechanical_pm": true}'::jsonb);
    SELECT n.atoms INTO v_atoms FROM public.ottoq_visit_needs n
     WHERE n.vehicle_id = v_car AND n.sim_run_id = v_run AND n.status = 'open' ORDER BY n.created_at DESC LIMIT 1;
    v_r := v_r || jsonb_build_object('early_with_pm', (SELECT COALESCE(jsonb_agg(jsonb_build_object('svc', a->>'svc',
             'must_do', a->'must_do', 'ridealong', a->'ridealong')), '[]'::jsonb)
             FROM jsonb_array_elements(v_atoms) a WHERE a->>'svc' IN ('tire_rotation', 'mechanical_pm')),
             'seat_with_pm', public.ottoq_service_bay_seat_base_min(v_run, v_car, NULL, 40));

    -- (8) the cadence escalation runs over the new card columns
    v_r := v_r || jsonb_build_object('escalation', public.ottoq_apply_need_escalation(v_run, true) -> 'ok');

    -- (9) V7: the seeder on this run's own seed
    PERFORM public.ottoq_seed_vehicle_need_profiles(v_run);
    v_r := v_r || jsonb_build_object('seeded', (
      SELECT jsonb_build_object(
               'cars', count(*),
               'worn', count(*) FILTER (WHERE public.ottoq_tire_replacement_due(p.tire_tread_mm)),
               'rotation_due_at_draw', count(*) FILTER (WHERE NOT public.ottoq_tire_replacement_due(p.tire_tread_mm)
                                         AND public.ottoq_tire_rotation_ratio(p.last_tire_rotation_at, p.drawn_at_sim_clock) >= 1),
               'rotation_due_within_24h', count(*) FILTER (WHERE NOT public.ottoq_tire_replacement_due(p.tire_tread_mm)
                                         AND public.ottoq_tire_rotation_ratio(p.last_tire_rotation_at, p.drawn_at_sim_clock) < 1
                                         AND public.ottoq_tire_rotation_ratio(p.last_tire_rotation_at, p.drawn_at_sim_clock + interval '24 hours') >= 1),
               'tread_min', min(p.tire_tread_mm), 'tread_max', max(p.tire_tread_mm))
        FROM public.vehicle_need_profile p JOIN public.vehicles v ON v.id = p.vehicle_id
       WHERE v.home_depot_id = c_depot AND p.drawn_for_run = v_run));

    RAISE EXCEPTION USING ERRCODE = 'OQ842', MESSAGE = '0842 V3b probe', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ842' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN v_detail::jsonb;
  END;
END $f$;

DO $v3b$
DECLARE v_r jsonb := pg_temp._0842_post_probe();
BEGIN
  IF NOT COALESCE((v_r #> '{worn_card,must_do_now}') ? 'tire_replacement', false)
     OR COALESCE((v_r #> '{worn_card,must_do_now}') ? 'mechanical_pm', true)
     OR (v_r #>> '{worn_card,tire_rotation_urgency}') IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION '0842 V3b (1): a worn car is not must-do for tire_replacement alone: %', v_r;
  END IF;
  IF NOT COALESCE((v_r->'worn_visit') @> '[{"svc": "tire_replacement", "must_do": true, "requires_bay": "service_bay"}]'::jsonb, false)
     OR COALESCE((v_r->'worn_visit') @> '[{"svc": "tire_rotation"}]'::jsonb, true) THEN
    RAISE EXCEPTION '0842 V3b (2): a worn car''s visit does not carry tire_replacement alone, required, at the service bay: %', v_r;
  END IF;
  IF (v_r->>'seat_alone')::numeric <> 12 OR (v_r->>'seat_for_tires')::numeric <> 12 OR (v_r->>'seat_for_pm')::numeric <> 40 THEN
    RAISE EXCEPTION '0842 V3b (3): the seat lengths are not 12 alone and 40 for other work: %', v_r;
  END IF;
  IF (v_r #>> '{replaced,tread_mm}')::numeric <> 8.0 OR (v_r #>> '{replaced,rotation_ratio}')::numeric <> 0
     OR COALESCE((v_r #> '{replaced,must_do_now}') ? 'tire_replacement', true) THEN
    RAISE EXCEPTION '0842 V3b (4): the replacement''s reset did not fit 8.0 mm, restart the quarter and clear the need: %', v_r;
  END IF;
  IF NOT COALESCE((v_r #> '{rotation_card,must_do_now}') ? 'tire_rotation', false)
     OR NOT COALESCE((v_r->'rotation_visit') @> '[{"svc": "tire_rotation", "must_do": true, "ridealong": false}]'::jsonb, false) THEN
    RAISE EXCEPTION '0842 V3b (5): a rotation 100 days ago is not on the card and the visit: %', v_r;
  END IF;
  IF (v_r #>> '{rotated,tread_mm}')::numeric <> 6.0 OR (v_r #>> '{rotated,rotation_ratio}')::numeric <> 0
     OR COALESCE((v_r #> '{rotated,must_do_now}') ? 'tire_rotation', true) THEN
    RAISE EXCEPTION '0842 V3b (6): the rotation''s reset did not restart the quarter, keep the tread and clear the need: %', v_r;
  END IF;
  IF jsonb_array_length(COALESCE(v_r->'early_alone', '[null]'::jsonb)) <> 0
     OR NOT COALESCE((v_r->'early_with_pm') @> '[{"svc": "tire_rotation", "must_do": true, "ridealong": true}, {"svc": "mechanical_pm"}]'::jsonb, false)
     OR (v_r->>'seat_with_pm')::numeric <> 40 THEN
    RAISE EXCEPTION '0842 V3b (7): an early rotation did not wait alone, or did not ride along with PM in a 40-minute seat: %', v_r;
  END IF;
  IF (v_r->>'escalation') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '0842 V3b (8): the cadence escalation did not run: %', v_r;
  END IF;
  IF COALESCE((v_r #>> '{seeded,cars}')::int, 0) < 50 OR (v_r #>> '{seeded,worn}')::int > 8
     OR (v_r #>> '{seeded,rotation_due_at_draw}')::int + (v_r #>> '{seeded,rotation_due_within_24h}')::int > 8
     OR (v_r #>> '{seeded,tread_min}')::numeric < 2.9 OR (v_r #>> '{seeded,tread_max}')::numeric > 8.0 THEN
    RAISE EXCEPTION '0842 V7: the seeder''s tire draws are not a few a run: %', v_r->'seeded';
  END IF;
  RAISE NOTICE '0842 V3b/V7 (after): %', v_r;
END $v3b$;

-- V4: the decide tick and the service flow themselves, rolled back the same way
CREATE FUNCTION pg_temp._0842_tick_probe() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  c_depot CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_car uuid; v_r jsonb := '{}'::jsonb; v_detail text;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start) INTO v_run, v_clock
    FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot AND r.status = 'completed' ORDER BY r.started_at DESC LIMIT 1;
  SELECT v.id INTO v_car FROM public.vehicles v
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous' AND v.is_active ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_car IS NULL THEN RAISE EXCEPTION '0842 V4: no run or car to probe with'; END IF;
  BEGIN
    -- both service bays clear, on the floor and on the calendar
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, status = 'available'
     WHERE depot_id = c_depot AND stall_type::text = 'service_bay';
    UPDATE public.ottoq_stall_bookings b SET state = 'released'
      FROM public.stalls s WHERE s.id = b.stall_id AND s.depot_id = c_depot AND s.stall_type::text = 'service_bay'
       AND b.state IN ('held', 'active') AND b.during && tstzrange(v_clock - interval '2 hours', v_clock + interval '4 hours');
    -- one car, full, worn tires and nothing else, staged for the service bay
    UPDATE public.vehicle_need_profile
       SET tire_tread_mm = 2.6, last_tire_rotation_at = v_clock - interval '10 days', km_at_last_pm = odometer_km,
           brake_wear_pct = 10, last_calibration_at = v_clock, sensor_health_pct = 99, worst_fault_severity = 99,
           open_fault_codes = '{}'::text[], exterior_soil_level = 0, cabin_condition = 'clean', last_wash_at = v_clock,
           last_deep_clean_at = v_clock, software_version = sw_target_version, item_retrieval_pending = false
     WHERE vehicle_id = v_car;
    UPDATE public.ottoq_vehicle_wear SET km_at_last_pm = drive_km_total, hours_at_last_calibration = drive_hours_total
     WHERE vehicle_id = v_car AND sim_run_id = v_run;
    UPDATE public.vehicles SET current_soc = 100, current_state = 'staged_awaiting_service',
           last_state_change = v_clock - interval '5 minutes',
           config = COALESCE(config, '{}'::jsonb) || '{"svc_step": "need_service"}'::jsonb
     WHERE id = v_car;
    UPDATE public.ottoq_visit_needs SET status = 'complete' WHERE vehicle_id = v_car AND status IN ('open', 'in_progress');
    PERFORM ottoq.ottoq_derive_visit_needs(v_car, v_run, v_run, v_clock, c_depot, '{}'::jsonb);
    v_r := v_r || jsonb_build_object('tick', (SELECT to_jsonb(t) FROM public.ottoq_decide_tick(v_run) t));
    v_r := v_r || jsonb_build_object('bookings', (
      SELECT COALESCE(jsonb_agg(round((EXTRACT(EPOCH FROM (upper(b.during) - lower(b.during))) / 60)::numeric, 2)), '[]'::jsonb)
        FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
       WHERE b.vehicle_id = v_car AND b.sim_run_id = v_run AND s.stall_type::text = 'service_bay'
         AND b.state IN ('held', 'active')));
    -- the service flow runs under its caller's search path; the twin's tick sets this one
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);
    PERFORM twin.ottoq_sim_advance_service_flow(v_run, v_clock, 1, c_depot);
    v_r := v_r || (SELECT jsonb_build_object('state', v.current_state,
                          'seat_min', round((EXTRACT(EPOCH FROM ((v.config->>'service_ends_at')::timestamptz - v_clock)) / 60)::numeric, 2))
                     FROM public.vehicles v WHERE v.id = v_car);
    RAISE EXCEPTION USING ERRCODE = 'OQ842', MESSAGE = '0842 V4 probe', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ842' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN v_detail::jsonb;
  END;
END $f$;

DO $v4$
DECLARE v_r jsonb := pg_temp._0842_tick_probe();
BEGIN
  IF COALESCE((v_r #>> '{tick,errored}')::int, -1) <> 0
     OR jsonb_array_length(COALESCE(v_r->'bookings', '[]'::jsonb)) = 0
     OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_r->'bookings') m WHERE m::numeric <> 12)
     OR (v_r->>'state') IS DISTINCT FROM 'in_service_bay'
     OR COALESCE((v_r->>'seat_min')::numeric, 0) NOT BETWEEN 1 AND 24 THEN
    RAISE EXCEPTION '0842 V4: the tick and the service flow did not seat a worn car for the robot''s length: %', v_r;
  END IF;
  RAISE NOTICE '0842 V4: %', v_r;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0842_the_service_bays_tire_robot_replaces_worn_tires_and_rotates_them_each_quarter', true, false,
        'OTTO-TIRE (Chase, 2026-11-17): tire_replacement (tread under 3.0 mm) and tire_rotation (every 2,190 h) are '
        || 'service-bay services of their own, required on the visit, seated for 12 minutes alone, credited at the bay '
        || 'exit with the tread and rotation reset. The needs card no longer seats a worn car for mechanical_pm. '
        || 'Pre-images are 0842_pre.', now());
COMMIT;
