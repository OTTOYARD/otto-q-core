-- migration-version: 20261113044222
-- migration-name:    0824_a_car_is_charged_only_at_a_post_whose_arm_stands_on_its_charge_port_side
--
-- 0824  **A car is charged only at a post whose arm stands on its charge-port side. The twin tells the robots which
--        vehicle it is and where its inlet is.**
--
-- WHY. Chase, 2026-11-12 (evening CT): "Make the robots and robotic arms know which vehicle is arriving or staged and
--   have it work around their charging port location ... If the port is on the left side, have OTTO-Q send vehicles to
--   only charging stall sides where the arm is in the left. And vice versa for a right side plug port."
--
-- §1 WHAT WAS SO. The engine knew a car's connector (vehicles.inlet_type against stalls.supported_inlet_types) and
--   nothing about where on the body the inlet is. The renderer drew every inlet on whichever flank its charger stood on
--   (ottoyarddepot-sim chargePort.ts: "we model the vehicle as ARRIVING CORRECTLY ORIENTED"). The posts are not alike:
--   read 2026-11-13, the twin depot's 30 fast-charger posts are 15 with heading 60 (canopy_side W, the arm on the
--   car's RIGHT) and 15 with heading 300 (canopy_side E, the arm on the car's LEFT). Its fleet, by where the maker puts
--   the inlet: 44 Jaguar I-PACE (left front wing), 32 Tesla Model Y (left rear), 2 Zeekr (left rear, assumed),
--   34 Zoox (not published; the vehicle drives either way, so it can present either flank), 4 Tesla Cybercab (rear
--   bumper, on the centreline). Sources and dates: ottoyarddepot-sim docs/FLEET-MODELS.md.
--
-- §2 WHAT THIS DOES.
--   (a) public.ottoq_charge_port_profiles: one row per vehicle kind (face, fore/aft, height, connector, whether it can
--       present either flank, whether the position is an assumption). public.ottoq_vehicle_port_profile(vehicle)
--       resolves a car by its make and model. A car with no profile is not restricted.
--   (b) public.ottoq_stall_arm_side(stall): 'right' or 'left', the side of the CAR the post's arm stands on, from the
--       post's heading (0561: 60 on the west column, 300 on the east). No stall row is written.
--   (c) public.ottoq_port_side_fits_stall(run, vehicle, stall): true unless charge_port_side_routing is on, the stall is
--       a fast-charger post, and the car's inlet is on the flank away from the arm. A rear inlet and a vehicle that
--       presents either flank fit both sides.
--   (d) The kernel's seat proposer offers only posts that fit, and among free posts a car that fits both sides takes
--       the side fewer of the depot's cars can use. The charge step declines any proposer's post that does not fit, as
--       an abstention that says what it declined; the car keeps its place in the charge line.
--   (e) The twin snapshot's vehicle row carries the car's model and its port profile, so the renderer's arm reads where
--       the inlet is and which connector it takes from the twin, not from a table of its own.
--   Behind charge_port_side_routing (default 0). Set to 1 at the twin depot by this file, on Chase's instruction.
--
-- §3 THE COST, WHICH IS A CAPACITY FINDING AND IS STATED BEFORE THE SWITCH (rules 9 and 13). With the dial on, 78 of
--   the twin depot's 116 autonomous cars (every Waymo and every Tesla Model Y) can be charged at 15 of its 30 posts. The other
--   15 posts can charge 38 cars (34 Zoox, 4 Cybercab). That is what the hardware is: a pedestal arm cannot reach
--   across a car. It is not a lever on a car: no charge is shortened, no target lowered, no service skipped; a car
--   that does not fit a free post waits for one that fits (queueing, rule 9). The answers to the wait are named in
--   ottoyarddepot-sim docs/CHARGE-ARM-REACH.md: a left-port car backing into a right-arm post presents its left flank,
--   and posts can be built with the arm on the side the fleet needs. Neither is in this file.
--   RULE 14, CHECKED. The test reads where a car's inlet is, never who owns it. Its effect is not even across owners:
--   Zoox's cars fit every post and Waymo's and Tesla's Model Ys fit half. (d)'s side preference exists so that a car
--   that fits both sides does not take a left-arm post while a right-arm post is free. It changes which free post that
--   car takes, never its place in the line.
--
-- §4 WHAT THIS DOES NOT DO. It does not change vehicles or classes: the 4 Cybercabs still carry inlet_type CCS1 and the
--   Model Y's class, and the 2 Zeekrs the I-PACE's class (the profile's connector is NACS for the Cybercab; the stall
--   test still reads vehicles.inlet_type, and every post carries both connectors, so no car is refused by it). It does
--   not gate the twin's own auto-assign (twin.ottoq_sim_auto_charge_assign_tick), the stranded-recharge door of the
--   service flow, or public.ottoq_promote_proposal_candidates: a post they pick is still checked by the charge step
--   only where it passes through it. It does not move a cabin stop (0817): a car that is not plugged in needs no side.
--
-- §5 PRECONDITIONS AND CHECKS. P0 no certification in flight (a run may be live, as for 0819). P1 the three bodies this file was written against
--   (md5 of prosrc, read 2026-11-13 03:5x UTC, after 0823). P2 once. V1 each patched body with its patches reversed is
--   its pre-image. V2 every anchor matched once. V3 the facts: 15 right and 15 left posts at the twin depot, every
--   autonomous car there resolves a profile, and the pure fit rule on its six cases. It reads and writes nothing else:
--   the proposer's answer on a staged run is NOT tested here and is the first thing to read on the first run.
--
-- §6 CLASSIFICATION. forces_recert TRUE, forces_dial_restart FALSE: the dial is set to 1 at the twin depot, where the
--   canon columns run, so which post a car is offered changes there. Nothing acts on it until testing resumes (rule 12).
--
-- ROLLBACK: DELETE FROM public.ottoq_policy_params WHERE param_key = 'charge_port_side_routing'; EXECUTE each
--   `definition` in ottoq_schema_snapshots WHERE label = '0824_pre'; DROP the five functions and the table below;
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_port_side_routing';
--   DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0824_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ── P0, P1, P2 ──
DO $pre$
DECLARE r record;
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0824 P0: a certification is in flight'; END IF;
  /* A run may be live (as 0819 was applied): the new functions are read only from the patched doors, and a seat already
     taken is not moved. The footer says which run was live. */
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)', '5a6e4b5469103d79c8ea80f489a1a195'),
      ('public.ottoq_decide_tick(uuid)',                            '6b139ccf90d5e24b900f0eb87ab802ac'),
      ('public.ottoq_twin_snapshot(uuid)',                          '0636303b7ced86b967b277e9b2cccc55')) AS t(fn, m)
  LOOP
    IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.m THEN
      RAISE EXCEPTION '0824 P1: % is not the body this file was written against', r.fn;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0824_%')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_port_side_routing') THEN
    RAISE EXCEPTION '0824 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0824_pre', 'function', 'public', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)', 'public.ottoq_decide_tick(uuid)',
                    'public.ottoq_twin_snapshot(uuid)']) AS f;

-- ── (a) where each kind of vehicle carries its inlet ──
CREATE TABLE public.ottoq_charge_port_profiles (
  profile_key            text PRIMARY KEY,
  match_priority         int  NOT NULL UNIQUE,
  match_make_model       text NOT NULL,
  port_face              text NOT NULL CHECK (port_face IN ('left', 'right', 'rear')),
  port_along_m           numeric NOT NULL,
  port_height_m          numeric NOT NULL CHECK (port_height_m > 0),
  port_lateral_m         numeric NOT NULL DEFAULT 0,
  connector              text NOT NULL CHECK (connector IN ('CCS1', 'NACS')),
  presents_either_side   boolean NOT NULL DEFAULT false,
  position_assumed       boolean NOT NULL,
  body_length_m          numeric NOT NULL,
  body_width_m           numeric NOT NULL,
  note                   text NOT NULL
);
COMMENT ON TABLE public.ottoq_charge_port_profiles IS
  '0824: where each kind of vehicle carries its charge inlet. port_along_m is metres from the middle of the body, positive toward the nose; port_face rear is the tail, facing backward. match_make_model is a case-insensitive regex on make and model, tried in match_priority order. Sources: ottoyarddepot-sim docs/FLEET-MODELS.md. Structural, not run-scoped.';
ALTER TABLE public.ottoq_charge_port_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_charge_port_profiles_read ON public.ottoq_charge_port_profiles FOR SELECT USING (true);

INSERT INTO public.ottoq_charge_port_profiles
  (profile_key, match_priority, match_make_model, port_face, port_along_m, port_height_m, connector,
   presents_either_side, position_assumed, body_length_m, body_width_m, note)
VALUES
  ('tesla_cybercab',     10, 'cybercab',            'rear', -2.2225, 0.62, 'NACS', false, true,  4.445, 1.753,
   'Rear bumper behind a drop-down door, DC only (reported). Height and lateral position assumed: centre, 0.62 m.'),
  ('tesla_model_y',      20, 'tesla',               'left', -2.165,  1.00, 'NACS', false, false, 4.790, 1.920,
   'Left rear, in the tail-lamp cluster.'),
  ('waymo_ojai',         30, 'zeekr|ojai',          'left', -1.856,  0.95, 'CCS1', false, true,  4.688, 1.995,
   'ASSUMPTION: left rear quarter, CCS1. Waymo has published neither.'),
  ('waymo_ipace',        40, 'jaguar|i-?pace',      'left',  1.201,  0.90, 'CCS1', false, false, 4.682, 1.895,
   'Left front wing, above and behind the wheel arch.'),
  ('zoox_robotaxi',      50, 'zoox',                'left', -1.185,  0.78, 'CCS1', true,  true,  3.630, 1.830,
   'ASSUMPTION: one CCS1 inlet low on a side near a corner. The vehicle drives either way, so it presents either flank.'),
  ('lucid_gravity_nuro', 60, 'lucid|gravity',       'left', -2.035,  1.02, 'NACS', false, false, 5.030, 2.000,
   'Left rear quarter.');

CREATE FUNCTION public.ottoq_vehicle_port_profile(p_vehicle uuid)
 RETURNS public.ottoq_charge_port_profiles LANGUAGE sql STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT pp.* FROM public.vehicles v
    JOIN public.ottoq_charge_port_profiles pp
      ON (COALESCE(v.make, '') || ' ' || COALESCE(v.model, '')) ~* pp.match_make_model
   WHERE v.id = p_vehicle
   ORDER BY pp.match_priority LIMIT 1;
$function$;

-- ── (b) which side of the car a post's arm stands on ──
CREATE FUNCTION public.ottoq_stall_arm_side(p_stall uuid)
 RETURNS text LANGUAGE sql STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  /* 0561: a west-column post has heading 60 and its car noses north-east, so the post stands on the car's right; an
     east-column post has heading 300 and stands on the car's left (ottoyarddepot-sim depotPlacement.portFlank). */
  SELECT CASE WHEN s.stall_type::text <> 'dcfc' OR s.heading_degrees IS NULL THEN NULL
              WHEN s.heading_degrees < 180 THEN 'right' ELSE 'left' END
    FROM public.stalls s WHERE s.id = p_stall;
$function$;

-- ── (c) the rule, pure, and the rule on a run ──
CREATE FUNCTION public.ottoq_port_side_fits(p_face text, p_either boolean, p_arm_side text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  SELECT p_face IS NULL OR p_arm_side IS NULL OR p_face = 'rear' OR COALESCE(p_either, false) OR p_face = p_arm_side;
$function$;

CREATE FUNCTION public.ottoq_port_side_fits_stall(p_sim_run_id uuid, p_vehicle uuid, p_stall uuid)
 RETURNS boolean LANGUAGE sql STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_port_side_routing', 0), 0) < 1
      OR public.ottoq_port_side_fits((public.ottoq_vehicle_port_profile(p_vehicle)).port_face,
                                     (public.ottoq_vehicle_port_profile(p_vehicle)).presents_either_side,
                                     public.ottoq_stall_arm_side(p_stall));
$function$;

CREATE FUNCTION public.ottoq_port_side_rank(p_sim_run_id uuid, p_vehicle uuid, p_stall uuid)
 RETURNS int LANGUAGE sql STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  /* 1 for the post a both-sides car should leave free: the arm side MORE of the depot's one-side cars need. 0 for
     every other case, and for every car with the dial off. */
  SELECT CASE
    WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_port_side_routing', 0), 0) < 1 THEN 0
    WHEN NOT ((public.ottoq_vehicle_port_profile(p_vehicle)).port_face = 'rear'
              OR COALESCE((public.ottoq_vehicle_port_profile(p_vehicle)).presents_either_side, false)) THEN 0
    WHEN public.ottoq_stall_arm_side(p_stall) = (
           SELECT pf.port_face FROM public.stalls s
             JOIN public.vehicles v ON v.home_depot_id = s.depot_id AND v.category = 'autonomous'
             CROSS JOIN LATERAL public.ottoq_vehicle_port_profile(v.id) pf
            WHERE s.id = p_stall AND pf.port_face IN ('left', 'right') AND NOT pf.presents_either_side
            GROUP BY pf.port_face ORDER BY count(*) DESC, pf.port_face LIMIT 1) THEN 1
    ELSE 0 END;
$function$;

CREATE FUNCTION public.ottoq_vehicle_port_json(p_vehicle uuid)
 RETURNS jsonb LANGUAGE sql STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object('profile', pp.profile_key, 'face', pp.port_face, 'along_m', pp.port_along_m,
                            'height_m', pp.port_height_m, 'lateral_m', pp.port_lateral_m, 'connector', pp.connector,
                            'either_side', pp.presents_either_side, 'assumed', pp.position_assumed,
                            'length_m', pp.body_length_m, 'width_m', pp.body_width_m)
    FROM public.ottoq_vehicle_port_profile(p_vehicle) pp WHERE pp.profile_key IS NOT NULL;
$function$;

INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES
  ('charge_port_side_routing',
   '0824: 1 = a car is offered and seated only on a fast-charger post whose arm stands on the side of the car its charge inlet is on (a rear inlet and a vehicle that presents either flank fit both). 0 = as before 0824.',
   0, 0, 1,
   'public.ottoq_port_side_fits_stall; public.ottoq_port_side_rank; public.ottoq_l2_propose_stall_assignment; public.ottoq_decide_tick', false);

-- ── (d), (e) the three patches ──
CREATE TEMP TABLE _0824_patch (seq int, fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0824_patch VALUES
(1, 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)',
$o1$AND (s.stall_type::text = 'dcfc' OR NOT public.ottoq_charge_needs_cleaning_post(v_run, p_vehicle_id))$o1$,
$n1$AND (s.stall_type::text = 'dcfc' OR NOT public.ottoq_charge_needs_cleaning_post(v_run, p_vehicle_id))
       /* 0824: only a post whose arm stands on the car's charge-port side. True for every car with
          charge_port_side_routing off. */
       AND public.ottoq_port_side_fits_stall(v_run, p_vehicle_id, s.id)$n1$),
(2, 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)',
$o2$(stall_type::text = v_want_type) DESC, relative_y ASC NULLS LAST, id$o2$,
$n2$(stall_type::text = v_want_type) DESC,
            /* 0824: a car that fits both sides leaves free the side more one-side cars need */
            public.ottoq_port_side_rank(v_run, p_vehicle_id, id) ASC, relative_y ASC NULLS LAST, id$n2$),
(3, 'public.ottoq_decide_tick(uuid)',
$o3$'declined_source', v_proposal->>'source');
    END IF;
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;$o3$,
$n3$'declined_source', v_proposal->>'source');
    END IF;
    /* 0824: a car is plugged in only at a post whose arm stands on its charge-port side (Chase, 2026-11-12). Any
       proposer's other answer is declined, as an abstention that says what it declined; the car keeps its place. */
    IF NOT COALESCE((v_proposal->>'abstain')::boolean, false)
       AND NULLIF(v_proposal->>'stall_id', '') IS NOT NULL
       AND NOT public.ottoq_port_side_fits_stall(p_sim_run_id, v_req.vehicle_id, NULLIF(v_proposal->>'stall_id', '')::uuid) THEN
      v_proposal := jsonb_build_object('abstain', true, 'reason', 'waits_for_a_post_on_its_charge_port_side',
                                       'declined_stall_id', v_proposal->>'stall_id',
                                       'declined_source', v_proposal->>'source');
    END IF;
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;$n3$),
(4, 'public.ottoq_twin_snapshot(uuid)',
$o4$'platform', v.platform, 'state', v.current_state,$o4$,
$n4$'platform', v.platform, 'state', v.current_state,
          -- 0824: which vehicle it is and where its charge inlet is, for the arms. NULL port: no profile.
          'model', v.model, 'port', public.ottoq_vehicle_port_json(v.id),$n4$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0824_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0824 V2: anchor % in % matches % times, not 1', p.seq, p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0824: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0824_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0824_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0824_pre' AND s.object_name = f.fn LIMIT 1) THEN
      RAISE EXCEPTION '0824 V1: % with its patches reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

-- ── on at the twin depot (rule 12; Chase's instruction, §3 names its cost) ──
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('depot', '11111111-1111-1111-1111-111111111111', 'charge_port_side_routing', 1,
        'Chase (delegated to Claude Code: 0824)', now());

-- ── V3 the facts ──
CREATE TEMP TABLE _0824_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_right int; v_left int; v_noprofile int; v_left_only int; v_both int;
BEGIN
  SELECT count(*) FILTER (WHERE public.ottoq_stall_arm_side(id) = 'right'),
         count(*) FILTER (WHERE public.ottoq_stall_arm_side(id) = 'left')
    INTO v_right, v_left FROM public.stalls WHERE depot_id = c_depot AND stall_type::text = 'dcfc';
  IF v_right = 0 OR v_left = 0 OR v_right + v_left <> (SELECT count(*) FROM public.stalls WHERE depot_id = c_depot AND stall_type::text = 'dcfc') THEN
    RAISE EXCEPTION '0824 V3: the twin depot''s posts do not all have an arm side (right %, left %)', v_right, v_left;
  END IF;
  SELECT count(*) FILTER (WHERE (public.ottoq_vehicle_port_profile(id)).profile_key IS NULL),
         count(*) FILTER (WHERE (public.ottoq_vehicle_port_profile(id)).port_face = 'left'
                            AND NOT (public.ottoq_vehicle_port_profile(id)).presents_either_side),
         count(*) FILTER (WHERE (public.ottoq_vehicle_port_profile(id)).port_face = 'rear'
                             OR (public.ottoq_vehicle_port_profile(id)).presents_either_side)
    INTO v_noprofile, v_left_only, v_both
    FROM public.vehicles WHERE home_depot_id = c_depot AND category = 'autonomous';
  IF v_noprofile > 0 THEN RAISE EXCEPTION '0824 V3: % autonomous cars at the twin depot resolve no port profile', v_noprofile; END IF;
  IF NOT (public.ottoq_port_side_fits('left', false, 'left') AND NOT public.ottoq_port_side_fits('left', false, 'right')
          AND public.ottoq_port_side_fits('left', true, 'right') AND public.ottoq_port_side_fits('rear', false, 'right')
          AND public.ottoq_port_side_fits(NULL, NULL, 'right') AND public.ottoq_port_side_fits('right', false, NULL)) THEN
    RAISE EXCEPTION '0824 V3: the fit rule fails one of its six cases';
  END IF;
  INSERT INTO _0824_selftest VALUES (jsonb_build_object('posts_right', v_right, 'posts_left', v_left,
    'cars_left_only', v_left_only, 'cars_both_sides', v_both, 'cars_no_profile', v_noprofile));
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0824_a_car_is_charged_only_at_a_post_whose_arm_stands_on_its_charge_port_side', true, false,
        'charge_port_side_routing set to 1 at the twin depot: which post a car is offered changes there. V3 at apply: '
        || COALESCE((SELECT result::text FROM _0824_selftest LIMIT 1), 'no result'), now());
COMMIT;

-- APPLIED 2026-11-13 at 04:42:22 UTC (2026-11-12, 10:42 PM CT), ledger 20261113044222, through apply_migration, on the
--   first send. Before it, the same statements ran once against the live engine inside a transaction that was rolled
--   back (04:1x UTC): every anchor matched once, V1 held, the snapshot's vehicle row carried `model` and `port`, and the
--   fit rule read true and false where it should for all five vehicle kinds at both arm sides.
--   A run was live at the apply (a95e51a3, operator_demo, busy_day, started 04:22:43 UTC). At that moment 11 left-port
--   cars stood on right-arm posts, seated before the rule existed (9 I-PACE, 2 Model Y); the rule moves no seated car.
--   V3 at apply: posts_right 15, posts_left 15, cars_left_only 78, cars_both_sides 38, cars_no_profile 0.
--   Stored after the apply, md5(prosrc): ottoq_l2_propose_stall_assignment 98aff784671e488bd07ef5a546295023,
--   ottoq_decide_tick 8454612c7529bbe9bba3c85ddc3bbf34, ottoq_twin_snapshot 7f961b8576f4c8dddea6f7d825f54a12.
--   The first seats made under the rule are read in db/checks/0489.
