-- migration-version: 20260928093601
-- migration-name:    a_paired_test_can_keep_a_fast_charger_for_a_car_that_wants_one
--
-- 0548  **A paired test can keep a free fast charger for a car that wants one.** (G277; research wing, rule 10.)
--        The charge order gives the next free charger to the car at the head of the line, whatever the charger's
--        kind. So a car that wanted an L2 took a fast charger while cars that wanted a fast charger waited, and those
--        cars then spent four hours on an L2. This adds one dial, `charge_kind_match`, read by the OTTO-Q seat's
--        stall pick, and one paired experiment on it. At 0, the default everywhere, nothing changes. At 1, a car that
--        wants an L2 does not take a free fast charger while the cars waiting that want one are at least as many as
--        the free fast chargers. It waits for an L2, and the fast charger goes to a car that wants it. No charge is
--        shortened. The engine never sets the dial; a win is a recommendation a person ships (0540).
--
-- ══ §1 WHY (validation run dbdffd5c, check 0404 §11d; FINDINGS G277; CLAUDE.md rules 9 and 10) ═════════════════════════
--
--   Rule 9: when cars wait for chargers, one of the answers is better ordering of who is served next. Never shorter
--   charges.
--
--   The OTTO-Q seat already decides which kind of charger each car wants (`ottoq_l2_propose_stall_assignment`): a fast
--   charger for a car below 45% or an immediate dispatch, an L2 otherwise. It prefers that kind among the free
--   chargers, but the car at the head of the line takes whichever charger is free. Measured on dbdffd5c at 08:08 UTC,
--   before the next run purged it:
--     - 14 fast-charger sessions went to cars that wanted an L2 (mean 74.8% at the start, 40.7 minutes each);
--     - 12 of those started while cars that wanted a fast charger were waiting, a mean 9.4 of them;
--     - 46 cars that wanted a fast charger (mean 38.6%) spent a mean 264.0 minutes on an L2;
--     - after each of those, the next fast-charger session started a median 6.2 minutes later.
--   A fast charger's advantage is at the bottom of the charge: below 50%, 83.7 minutes on a fast charger against
--   263.7 on an L2 (0404 §11d). At 70% and above, a top-off took 15.3 minutes on a fast charger against 33.7 on an L2.
--   So the same fast-charger minute saves far more time for a low car than for a top-off.
--
--   Rule 10: whether keeping the fast charger raises the depot's output is a question for the research wing, in the
--   twin, as a paired test. This file builds the lever and the test. It changes nothing outside the test's arms.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `charge_kind_match` in `ottoq_policy_param_catalog`: 0 or 1, default 0, not agent-writable.
--   (b) `public.ottoq_l2_propose_stall_assignment` reads the dial for the running run (seat 0 only; the baseline
--       seats return before it). At 1, after the stall is chosen, when all of these hold:
--         - the car wants an L2;
--         - the chosen stall is a fast charger, and it is not the car's own reservation;
--         - the other cars waiting for a charger at the depot that want a fast charger are at least as many as the
--           free fast chargers.
--       Then the pick abstains, with the reason `fast_charger_kept_for_a_car_that_wants_one` and the two counts.
--       "Waiting" is the charge cursor's own set: a car at the gate or staged, below its visit target minus 1.
--       "Wants one" is the seat's own rule: below 45%, or an immediate dispatch.
--     An abstention is what the cursor already does when no charger is free: the car waits (a car at the gate goes to
--     a staging hold), and the fast charger goes to a car that wants it later in the same tick.
--     When there are more free fast chargers than cars that want one, the car takes the spare, so no charger idles
--     for the rule.
--     At 0 the function returns exactly what it returned before. The one added call at 0 is a read of the dial, which
--     writes nothing.
--   (c) One dial experiment on it. It uses the same shape as `143a11c7`: busy_day at the twin, 90 ticks of 6
--       sim-minutes from 8:00 AM CT, looks at 6 and 12 pairs. The primary metric is deployed car-hours (higher is
--       better). The verdict's own guardrails (the five KPIs within 2%) and safety floor (no counted pair may leave
--       more returns unserved) apply unchanged.
--
--   Not changed: the charge target, the charge itself, the order of the cursor, the proposal of a car that wants a
--   fast charger, the baseline seats, external proposals, and every gate.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: no pair, recert or dial pair is in flight. P2: the pick is the function measured (md5 of its source), and the
--   dial is not yet catalogued. Exact-once patches. V1, comment-stripped: the rule is there once, gated on the dial,
--   and after the no-candidate return. V3, rolled back, on the latest ended twin run marked running, with every L2
--   and all but two fast chargers unavailable and two cars below 45% waiting:
--     (a) dial 1: a car at 80% abstains, and names 2 free fast chargers and 2 cars that want one;
--     (b) dial 1, one of the two waiting cars gone: the car at 80% takes a fast charger (the spare);
--     (c) dial 0, both waiting: the car at 80% takes a fast charger, as before;
--     (d) dial 1: a waiting car at 30% takes a fast charger, as before;
--     (e) dial 1, a fast charger reserved for the car at 80%: it takes its reservation.
--   The experiment is registered, active and due.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0448 was. The canon and every other experiment run the dial at
--   its default, where the pick is unchanged; the only added work at 0 is the dial read.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0548 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: the pick is the one measured (md5 of its source, 2026-09-28 08:12 UTC), and the dial is new ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure)
     <> '3dca1e5263e18ff21952141c9b911619' THEN
    RAISE EXCEPTION '0548 P2: public.ottoq_l2_propose_stall_assignment is not the function measured';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_kind_match') THEN
    RAISE EXCEPTION '0548 P2: charge_kind_match is already catalogued';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0548_pre', 'function', 'public', 'ottoq_l2_propose_stall_assignment',
       pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure));

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('charge_kind_match',
  '0548 (G277, research wing): whether the OTTO-Q seat keeps a free fast charger for a car that wants one. 0 (the '
  'default) = the car at the head of the line takes whichever charger is free. 1 = a car that wants an L2 (45% or '
  'more, not an immediate dispatch) does not take a free fast charger while the cars waiting that want one (below 45%, '
  'or an immediate dispatch) are at least as many as the free fast chargers; it waits for an L2. No charge is '
  'shortened. Set only in a paired test''s arms; a win is a recommendation a person ships (0540).',
  0, 0, 1, 'ottoq_l2_propose_stall_assignment', false);

-- ── (b) the pick reads it ──
DO $pick$
DECLARE v_def text; n int;
  c_decl_old CONSTANT text := $a$  v_veh_target numeric;   /* 0446 */
BEGIN$a$;
  c_decl_new CONSTANT text := $a$  v_veh_target numeric;   /* 0446 */
  v_kind_match int; v_n_dcfc int; v_n_want int;   /* 0548 (G277) */
BEGIN$a$;
  c_body_old CONSTANT text := $a$  IF v_stall.id IS NULL THEN RETURN jsonb_build_object('abstain', true, 'reason', 'no_compatible_available_stall'); END IF;
$a$;
  c_body_new CONSTANT text := $a$  IF v_stall.id IS NULL THEN RETURN jsonb_build_object('abstain', true, 'reason', 'no_compatible_available_stall'); END IF;

  /* 0548 (G277, research wing): at charge_kind_match = 1 a car that wants an L2 does not take a free fast charger
     while the cars waiting that want one are at least as many as the free fast chargers. It waits for an L2 (an
     abstention, as when no charger is free), and the fast charger goes to a car that wants it later in this tick.
     A spare fast charger is still taken, so no charger idles for the rule. At 0 (the default) nothing below changes. */
  v_kind_match := COALESCE(public.ottoq_policy_get(v_run, 'charge_kind_match', 0), 0)::int;
  IF v_kind_match = 1 AND v_want_type = 'l2' AND v_stall.stall_type::text = 'dcfc'
     AND (SELECT s0.reserved_by FROM stalls s0 WHERE s0.id = v_stall.id) IS DISTINCT FROM p_vehicle_id THEN
    SELECT count(*) INTO v_n_dcfc
      FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type::text = 'dcfc' AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= v_now)
       AND c.station_state = 'Available' AND c.last_heartbeat_at >= v_now - INTERVAL '90 seconds';
    SELECT count(*) INTO v_n_want
      FROM vehicles w
     WHERE w.home_depot_id = p_depot_id AND w.category = 'autonomous' AND w.id <> p_vehicle_id
       AND w.current_state IN ('arrived_at_gate', 'staged_awaiting_service')
       AND w.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
              WHERE vn.vehicle_id = w.id AND vn.status IN ('open','in_progress')
                AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                  = COALESCE(v_run,'00000000-0000-0000-0000-000000000000'::uuid)
              ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) - 1
       AND (w.current_soc < 45
            OR COALESCE((SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                  WHERE vn.vehicle_id = w.id AND vn.status IN ('open','in_progress')
                    AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                      = COALESCE(v_run,'00000000-0000-0000-0000-000000000000'::uuid)
                  ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false));
    IF v_n_want > 0 AND v_n_want >= v_n_dcfc THEN
      RETURN jsonb_build_object('abstain', true, 'reason', 'fast_charger_kept_for_a_car_that_wants_one',
        'rationale', jsonb_build_object('soc', v_soc, 'wanted_type', v_want_type, 'urgency', v_urgency,
                                        'kept_stall_id', v_stall.id, 'free_fast_chargers', v_n_dcfc,
                                        'cars_wanting_one', v_n_want, 'charge_kind_match', v_kind_match));
    END IF;
  END IF;
$a$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_decl_old, ''))) / length(c_decl_old);
  IF n <> 1 THEN RAISE EXCEPTION '0548 pick: the DECLARE anchor matches % times, not 1', n; END IF;
  n := (length(v_def) - length(replace(v_def, c_body_old, ''))) / length(c_body_old);
  IF n <> 1 THEN RAISE EXCEPTION '0548 pick: the no-candidate anchor matches % times, not 1', n; END IF;
  EXECUTE replace(replace(v_def, c_decl_old, c_decl_new), c_body_old, c_body_new);
END $pick$;

-- ── V1 (comment-stripped): the rule is there once, gated on the dial, after the no-candidate return ──
DO $verify$
DECLARE v_src text; p_none int; p_rule int;
BEGIN
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'v_kind_match\s*:=\s*COALESCE\(public\.ottoq_policy_get\(v_run,\s*''charge_kind_match'',\s*0\),\s*0\)::int;', 'g')) <> 1 THEN
    RAISE EXCEPTION '0548 V1: the pick does not read charge_kind_match for its run once';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'IF\s+v_kind_match\s*=\s*1\s+AND\s+v_want_type\s*=\s*''l2''\s+AND\s+v_stall\.stall_type::text\s*=\s*''dcfc''', 'g')) <> 1 THEN
    RAISE EXCEPTION '0548 V1: the rule is not gated on the dial, the wanted kind and the chosen kind';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src, '''fast_charger_kept_for_a_car_that_wants_one''', 'g')) <> 1 THEN
    RAISE EXCEPTION '0548 V1: the abstention reason is not there once';
  END IF;
  p_none := strpos(v_src, '''no_compatible_available_stall''');
  p_rule := strpos(v_src, 'v_kind_match := ');
  IF p_none = 0 OR p_rule = 0 OR p_rule < p_none THEN
    RAISE EXCEPTION '0548 V1: the rule does not come after the no-candidate return';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0548_a_paired_test_can_keep_a_fast_charger_for_a_car_that_wants_one', false, false,
  'G277, research wing (rule 10): the dial charge_kind_match (0/1, default 0) and one paired experiment on it. At 1, '
  'public.ottoq_l2_propose_stall_assignment (seat 0) abstains for a car that wants an L2 when its chosen stall is a '
  'free fast charger that is not its reservation and the cars waiting that want a fast charger (below 45% or an '
  'immediate dispatch) are at least as many as the free fast chargers. At 0 the pick returns what it returned before; '
  'the one added call is a read of the dial, which writes nothing. So the canon and every other experiment, which run '
  'the dial at 0, are unmoved (as 0448).', now())
ON CONFLICT (name) DO NOTHING;

-- ── (c) the paired test ──
INSERT INTO public.ottoq_dial_experiments
  (created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks, sim_start,
   primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct, min_effect_pct,
   guardrail_alpha, hypothesis, status, sim_min_per_tick, run_after)
VALUES ('claude_code_2026_09_28', '11111111-1111-1111-1111-111111111111', 'charge_kind_match', 0, 1, '{}'::jsonb,
  'busy_day', 90, '2026-09-01T13:00:00+00:00', 'deployed_car_hours', 'higher', 6, 12, 0.05, 2, 0.5, 0.2,
  'G277 (0548; db/checks/0404 §11d; FINDINGS G277): at charge_kind_match = 1, a car that wants an L2 (45% or more, '
  'not an immediate dispatch) does not take a free fast charger while the cars waiting that want one are at least as '
  'many as the free fast chargers, and the fast charger goes to a car that wants it. On dbdffd5c, 14 fast-charger '
  'sessions went to cars that wanted an L2 while a mean 9.4 low or immediate cars waited, and 46 cars that wanted a '
  'fast charger spent a mean 264 minutes on an L2. The treatment raises deployed car-hours without leaving any return '
  'unserved or moving the five KPIs more than 2% the wrong way. No charge is shortened (rule 9). Arms at 6 '
  'sim-minutes a tick from 8:00 AM CT for 90 ticks (to 5:00 PM, the operator governor''s 540 sim-minute day).',
  'active', 6, NULL);

-- V3, rolled back, on the latest ended twin run, marked running inside this block so the pick reads the run's dial.
DO $v3$
DECLARE
  v_msg text; v_twin uuid := '11111111-1111-1111-1111-111111111111'; v_run uuid; v_now timestamptz;
  v_cars uuid[]; t uuid; w1 uuid; w2 uuid; d1 uuid; d2 uuid; r jsonb; v_exp int;
BEGIN
  BEGIN
    IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = v_twin AND status IN ('running','paused')) THEN
      RAISE EXCEPTION '0548 V3: a run is live at the twin depot; V3 must run between runs';
    END IF;
    SELECT sim_run_id, sim_clock_current + interval '2 days' INTO v_run, v_now
      FROM public.ottoq_sim_runs WHERE depot_id = v_twin AND status = 'completed' AND sim_clock_current IS NOT NULL
     ORDER BY started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0548 V3: no ended twin run to stand on'; END IF;

    -- three cars with no open visit in that run, so no urgency decides the wanted kind
    SELECT array_agg(id ORDER BY id) INTO v_cars FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_twin AND v.category = 'autonomous'
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress'))
       ORDER BY v.id LIMIT 3) q;
    t := v_cars[1]; w1 := v_cars[2]; w2 := v_cars[3];
    SELECT (array_agg(s.id ORDER BY s.id))[1], (array_agg(s.id ORDER BY s.id))[2] INTO d1, d2
      FROM public.stalls s WHERE s.depot_id = v_twin AND s.stall_type::text = 'dcfc';
    IF w2 IS NULL OR d2 IS NULL THEN RAISE EXCEPTION '0548 V3: not enough twin cars without a visit, or fast chargers'; END IF;

    -- the scene, set with no run live: nobody else waiting, every L2 and all but two fast chargers unavailable
    UPDATE public.vehicles SET current_state = 'offline'::vehicle_state
     WHERE home_depot_id = v_twin AND category = 'autonomous' AND id <> ALL (v_cars)
       AND current_state IN ('arrived_at_gate','staged_awaiting_service');
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
     WHERE current_vehicle_id = ANY (v_cars) OR reserved_by = ANY (v_cars) OR id IN (d1, d2);
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state, current_stall_id = NULL, robotic_tether_stall_id = NULL,
           current_soc = CASE WHEN id = t THEN 80 WHEN id = w1 THEN 30 ELSE 35 END
     WHERE id = ANY (v_cars);
    UPDATE public.ottoq_ocpp_chargers c
       SET station_state = CASE WHEN s.id IN (d1, d2) THEN 'Available' ELSE 'Unavailable' END,
           last_heartbeat_at = v_now
      FROM public.stalls s
     WHERE s.ocpp_charger_id = c.charger_id AND s.depot_id = v_twin AND s.stall_type::text IN ('dcfc','l2');

    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;

    -- (a) dial 1: the car at 80% abstains; 2 free fast chargers, 2 cars that want one
    r := public.ottoq_policy_set('run', v_run, 'charge_kind_match', 1, '0548 V3');
    IF NOT COALESCE((r->>'ok')::boolean, false) THEN RAISE EXCEPTION '0548 V3: the setter refused charge_kind_match = 1: %', r; END IF;
    r := public.ottoq_l2_propose_stall_assignment(t, v_twin, jsonb_build_object('current_soc', 80, 'now_ts', v_now));
    IF NOT COALESCE((r->>'abstain')::boolean, false) OR r->>'reason' <> 'fast_charger_kept_for_a_car_that_wants_one'
       OR (r->'rationale'->>'free_fast_chargers')::int <> 2 OR (r->'rationale'->>'cars_wanting_one')::int <> 2 THEN
      RAISE EXCEPTION '0548 V3 FAILED (a): dial 1 with 2 cars wanting 2 free fast chargers returned %', r;
    END IF;

    -- (b) dial 1, one waiting car gone: the spare is taken
    UPDATE public.vehicles SET current_state = 'offline'::vehicle_state WHERE id = w2;
    r := public.ottoq_l2_propose_stall_assignment(t, v_twin, jsonb_build_object('current_soc', 80, 'now_ts', v_now));
    IF COALESCE((r->>'abstain')::boolean, true) OR r->>'stall_type' <> 'dcfc' THEN
      RAISE EXCEPTION '0548 V3 FAILED (b): dial 1 with 1 car wanting 2 free fast chargers returned %', r;
    END IF;
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service'::vehicle_state WHERE id = w2;

    -- (c) dial 0: the car at 80% takes a fast charger, as before
    r := public.ottoq_policy_set('run', v_run, 'charge_kind_match', 0, '0548 V3');
    IF NOT COALESCE((r->>'ok')::boolean, false) THEN RAISE EXCEPTION '0548 V3: the setter refused charge_kind_match = 0: %', r; END IF;
    r := public.ottoq_l2_propose_stall_assignment(t, v_twin, jsonb_build_object('current_soc', 80, 'now_ts', v_now));
    IF COALESCE((r->>'abstain')::boolean, true) OR r->>'stall_type' <> 'dcfc' THEN
      RAISE EXCEPTION '0548 V3 FAILED (c): dial 0 returned %', r;
    END IF;

    -- (d) dial 1: a waiting car at 30% takes a fast charger, as before
    r := public.ottoq_policy_set('run', v_run, 'charge_kind_match', 1, '0548 V3');
    IF NOT COALESCE((r->>'ok')::boolean, false) THEN RAISE EXCEPTION '0548 V3: the setter refused charge_kind_match = 1: %', r; END IF;
    r := public.ottoq_l2_propose_stall_assignment(w1, v_twin, jsonb_build_object('current_soc', 30, 'now_ts', v_now));
    IF COALESCE((r->>'abstain')::boolean, true) OR r->>'stall_type' <> 'dcfc' THEN
      RAISE EXCEPTION '0548 V3 FAILED (d): a car at 30%% under dial 1 returned %', r;
    END IF;

    -- (e) dial 1: a fast charger reserved for the car at 80% is its to take
    UPDATE public.stalls SET reserved_by = t, reserved_at = v_now, reservation_expires_at = v_now + interval '1 hour' WHERE id = d1;
    r := public.ottoq_l2_propose_stall_assignment(t, v_twin, jsonb_build_object('current_soc', 80, 'now_ts', v_now));
    IF COALESCE((r->>'abstain')::boolean, true) OR (r->>'stall_id')::uuid IS DISTINCT FROM d1 THEN
      RAISE EXCEPTION '0548 V3 FAILED (e): the car''s own reserved fast charger was not taken: %', r;
    END IF;

    SELECT count(*) INTO v_exp FROM public.ottoq_dial_experiments
     WHERE param_key = 'charge_kind_match' AND status = 'active' AND run_after IS NULL AND control_value = 0 AND treatment_value = 1;
    IF v_exp <> 1 THEN RAISE EXCEPTION '0548 V3 FAILED: % active charge_kind_match experiments, want 1', v_exp; END IF;

    RAISE EXCEPTION '0548 V3 PASSED: (a) dial 1 kept both free fast chargers for the 2 cars that want one; (b) with 1 such car the car at 80%% took the spare; (c) dial 0 took a fast charger as before; (d) a car at 30%% took a fast charger; (e) a reserved fast charger was taken by its car; the experiment is active and due';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0548 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0548 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0548_pre' as it is; DELETE the catalog row
-- and set the experiment's status to 'abandoned'.

COMMIT;
