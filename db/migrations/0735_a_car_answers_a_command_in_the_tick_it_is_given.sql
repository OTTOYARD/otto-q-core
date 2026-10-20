-- migration-version: 20261017161641
-- migration-name:    a_car_answers_a_command_in_the_tick_it_is_given
--
-- 0735  **A car answers a command in the tick it is given (G449, G450).** The twin carries out every command a tick
--       after the decide gives it: on arm 83 all 507 executed commands were confirmed exactly 5.00 sim-minutes after
--       they were issued. That one lag has two costs, in opposite directions. A freed fast charger waits a tick for the
--       car the decide gave it (G449: 58 of 67 handovers with a car waiting took exactly 10 minutes). And a bay seat
--       starts a tick after its booking and still ends with it, so every wash and every service in the twin is a tick
--       shorter than planned (G450). Under a dial, default off, the twin's confirm walk and its charge reconcile run once
--       more after the decide, at the tick's clock, so a car moves into the stall or bay it was given, and plugs in,
--       in the tick it was given it, as a real car does within a minute or two. A TWIN FIDELITY FIX, NOT A PRODUCTION
--       CHANGE: in production the car itself answers a command when it receives it, and a bay reports its own finish.
--
-- ══ §1 WHY (G449, G450, db/checks/0451 §12) ══════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_sim_advance_tick runs the world (public.ottoq_sim_advance_tick_world), then the decide
--   (ottoq_sim_decide_and_dispatch). The decide gives its commands at the tick's clock. The world carries them out in its
--   confirm walk (twin.ottoq_sim_confirm_commands), which runs early in the NEXT tick's world, before that tick's charge
--   reconcile. On arm 83 (e7d5824c, dcfc10, normal day, seed 1) every executed command waited exactly one tick:
--   begin_charge 223, stage 163, proceed_to_stall 68, enter_wash 39, enter_service 14, all at 5.00 minutes.
--
--   Chargers (G449). A charge ends in tick t's charge step. Tick t+1 walks the arm's demate and frees the stall, and its
--   decide gives the stall to the next car. That car is seated, and its charge reconciled, only in tick t+2. So a
--   handover takes two ticks, 10 minutes at 5 minutes a tick, for a demate of 11.5 s and a mate of 18.5 s.
--
--   Bays (G450, new). ottoq_decide_tick books a bay from its own clock for the leg's planned duration
--   (v_bay_until := v_clock + v_bay_dur, ottoq.ottoq_enact_space_assignment(..., v_clock, v_bay_until, ...)). The
--   confirm walk seats the car a tick later and pins its service_ends_at to the booking's end (0458). So every bay seat
--   is a tick shorter than its booking. On arms 82-88, 470 of 472 bay seats began exactly one tick after their
--   booking. Washes sat a mean 11.9-13.1 minutes of 16.9-18.1 booked (28-30% short), services 35.0-44.6 of 40.4-49.6
--   (10-13% short). The twin's bays have been turning faster than their own plan: the opposite direction to G449, and
--   on busy_day, whose two service bays are its wall (db/checks/0450), the more consequential one.
--
--   One cause, one fix. A command given at tick t is carried out at tick t: the handover takes one tick, and a bay seat
--   lasts its booking.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) dial `twin_answer_in_tick`, 0..1, default 0, not agent-writable.
--   (b) twin.ottoq_sim_answer_in_tick(run, clock). It acts only for a run whose depot the twin feeds and whose operator
--       door is shut (twin_operator_door 0); the world tick's own confirm walk has the same two gates. It runs the confirm
--       walk at the tick's clock, stamps the tick's heartbeat on the depot's chargers that are not faulted and whose
--       heartbeat is behind the clock (the world tick's order before its own reconcile, 0424: a charger
--       ottoq_sim_recover_chargers brought back after the world's last stamp would otherwise read stale to HW.002), and
--       runs the charge reconcile. It returns what it did. A failure is a WARNING and the tick goes on, so a broken pass
--       leaves the tick as it was.
--   (c) public.ottoq_sim_advance_tick, one anchored insertion after the decide. With the dial on, and the run not
--       completing this tick, it calls (b) at the world's clock. With the dial off the inserted IF reads one dial and
--       does nothing, so the tick is the tick it was (V1).
--   (d) two sweeps at priority 15, after 0734's:
--       `answer_morning_2026_10_17`: arm 83's cell plus the dial over 0734's six-hour morning at 72 x 5, paired with
--       tick5_morning (the same cell and morning without the dial) and tick25_morning (the same at 2.5 minutes a tick);
--       `answer_normal_2026_10_17`: arms 83, 86 and 84's cells (dcfc10, dcfc20, dcfc40, normal day, seed 1) plus the
--       dial, the post-count curve of db/checks/0451 §10 point 2 with the command lag removed.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the tick, the confirm walk and the reconcile are the bodies read on 2026-10-17 (md5
--   dc2490aa, f0b580e4, 3517b7a5), 0734 applied, the dial and the helper absent, arm 83's run present. P2: not already
--   applied. V1: the tick's body less its insertion is its pre-image. V2: the helper does nothing without a run or a
--   clock. V3: on a rolled-back sub-block, a proceed_to_stall issued at arm 83's last clock is carried out by the helper
--   at that clock, zero lag, the stall holding the car and the car pointing at the stall, and nothing is left behind.
--   V4: the dial, the grants, the sweeps and their cells.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no certification arm, canon cell or dial experiment sets
--   twin_answer_in_tick, and with it 0 the tick's added IF reads the dial and does nothing.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0735_pre'; DROP FUNCTION
--   twin.ottoq_sim_answer_in_tick(uuid, timestamptz); before the sweeps have run, DELETE their cell and sweep rows (once
--   one has run its arms are evidence and stay); DELETE the dial's catalog row once no params row names it;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0735_a_car_answers_a_command_in_the_tick_it_is_given'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0735 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, 0734 applied, the dial and the helper absent, arm 83's run present ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_sim_advance_tick(uuid)'))
     IS DISTINCT FROM 'dc2490aad69e25cbb7033a97edabe2c8' THEN
    RAISE EXCEPTION '0735 P1: public.ottoq_sim_advance_tick is not the body read on 2026-10-17 (md5 dc2490aa)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'))
     IS DISTINCT FROM 'f0b580e47658a7f51a62663095e07157' THEN
    RAISE EXCEPTION '0735 P1: twin.ottoq_sim_confirm_commands is not the body read on 2026-10-17 (md5 f0b580e4)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_reconcile_charge_sessions(uuid,timestamp with time zone)'))
     IS DISTINCT FROM '3517b7a59410eba77b5a2d95c2b6306f' THEN
    RAISE EXCEPTION '0735 P1: twin.ottoq_sim_reconcile_charge_sessions is not the body read on 2026-10-17 (md5 3517b7a5)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0734_the_same_morning_at_half_the_tick_to_measure_what_the_tick_costs') THEN
    RAISE EXCEPTION '0735 P1: 0734 is not applied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'twin_answer_in_tick')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_answer_in_tick')
     OR to_regprocedure('twin.ottoq_sim_answer_in_tick(uuid,timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION '0735 P1: twin_answer_in_tick or its helper already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'
                    AND depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'completed') THEN
    RAISE EXCEPTION '0735 P1: arm 83''s run (e7d5824c), which V3 tests against, is gone';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps
              WHERE sweep_code IN ('answer_morning_2026_10_17', 'answer_normal_2026_10_17')) THEN
    RAISE EXCEPTION '0735 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0735_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_sim_advance_tick(uuid)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('twin_answer_in_tick',
        '0735 (G449, G450): 1 = after the decide, the twin carries out in the same tick the commands that decide gave, '
        'so a car moves into the stall or bay it was given, and plugs in, in the tick it was given it, as a real car '
        'does within a minute or two. 0 = a command is carried out in the next tick''s world step, a tick later: a freed '
        'fast charger waits a tick for its next car, and a bay seat starts a tick after its booking and still ends with '
        'it. Changes when the twin carries out a command, never what the engine decides. Research days only.',
        0, 0, 1, 'public.ottoq_sim_advance_tick, twin.ottoq_sim_answer_in_tick', false);

-- ── (b) the twin answers this tick's commands in this tick ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_answer_in_tick(p_sim_run_id uuid, p_sim_clock_now timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = twin, ottoq, public, extensions
AS $fn$
-- 0735 (G449, G450): the twin carries out, at this tick's clock, the commands this tick's decide gave, and plugs in a
-- car seated on a charger. The same two steps, in the same order, as the world tick's own (its confirm walk, then the
-- tick's heartbeats, then its charge reconcile), behind the same two gates (a depot the twin feeds, the operator door
-- shut). Called by public.ottoq_sim_advance_tick after the decide, only under the dial twin_answer_in_tick.
DECLARE v_depot uuid; v_feed_sim boolean; v_walked int := 0; v_started int := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_sim_clock_now IS NULL THEN
    RETURN jsonb_build_object('ran', false, 'why', 'no run or no clock');
  END IF;
  SELECT r.depot_id INTO v_depot FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN
    RETURN jsonb_build_object('ran', false, 'why', 'no run or no clock');
  END IF;
  SELECT COALESCE(d.feed_mode, 'sim') = 'sim' INTO v_feed_sim FROM public.depots d WHERE d.id = v_depot;
  IF NOT COALESCE(v_feed_sim, true) THEN
    RETURN jsonb_build_object('ran', false, 'why', 'the depot is not fed by the twin');
  END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'twin_operator_door', 0), 0) >= 1 THEN
    RETURN jsonb_build_object('ran', false, 'why', 'twin_operator_door: the operators answer through the v2 door');
  END IF;
  BEGIN
    v_walked := twin.ottoq_sim_confirm_commands(p_sim_run_id, p_sim_clock_now);
    UPDATE public.ottoq_ocpp_chargers SET last_heartbeat_at = p_sim_clock_now
     WHERE depot_id = v_depot AND station_state <> 'Faulted'
       AND (last_heartbeat_at IS NULL OR last_heartbeat_at < p_sim_clock_now);
    v_started := twin.ottoq_sim_reconcile_charge_sessions(p_sim_run_id, p_sim_clock_now);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0735 answer in tick: % %', SQLSTATE, SQLERRM;
    RETURN jsonb_build_object('ran', false, 'why', 'raised', 'sqlstate', SQLSTATE, 'error', SQLERRM);
  END;
  RETURN jsonb_build_object('ran', true, 'walked', v_walked, 'charges_started', v_started);
END
$fn$;

REVOKE ALL ON FUNCTION twin.ottoq_sim_answer_in_tick(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_answer_in_tick(uuid, timestamptz) TO service_role;

-- ══ (c): one anchored insertion in the tick, after the decide, the anchor once ═══════════════════════════════════════
CREATE TEMP TABLE _0735_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0735_patch VALUES
(1, 'public.ottoq_sim_advance_tick(uuid)'::regprocedure,
$old$  SELECT * INTO d FROM ottoq_sim_decide_and_dispatch(p_sim_run_id);
$old$,
$new$  SELECT * INTO d FROM ottoq_sim_decide_and_dispatch(p_sim_run_id);
  -- 0735 (G449, G450): with twin_answer_in_tick on, the twin carries out in this tick the commands this tick's decide
  -- gave, and plugs in a car seated on a charger; off, they wait for the next tick's world step, as they always did.
  IF NOT COALESCE(w.out_completed, false) AND w.out_sim_clock_after IS NOT NULL
     AND COALESCE(ottoq_policy_get(p_sim_run_id, 'twin_answer_in_tick', 0), 0) >= 1 THEN
    PERFORM twin.ottoq_sim_answer_in_tick(p_sim_run_id, w.out_sim_clock_after);
  END IF;
$new$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0735_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(p.fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0735: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(p.fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0735: % is not stored as patched', p.fn;
    END IF;
  END LOOP;
END $patch$;

-- ── (d) the sweeps that measure it: the morning first, so its created_at (a clock read per statement) runs it first ──
INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes, created_at)
SELECT 'answer_morning_2026_10_17',
       'A car answers a command in the tick it is given: the depot as built over the normal morning',
       v.depot_id, 'normal_day', v.sim_start, 72, 5, v.seeds[1:1], 0, 15, 5400, now(),
       '0735 (G449, G450): arm 83''s cell (dcfc10.otto_q) plus twin_answer_in_tick over 0734''s six-hour morning at '
       '72 x 5, on value_2026_09_30''s first seed. Paired with tick5_morning_2026_10_17 (the same without the dial) and '
       'tick25_morning_2026_10_17 (the same at 2.5 sim-minutes a tick).',
       clock_timestamp()
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes, created_at)
SELECT 'answer_normal_2026_10_17',
       'A car answers a command in the tick it is given: 10, 20 and 40 fast chargers over the normal day',
       v.depot_id, 'normal_day', v.sim_start, 144, 5, v.seeds[1:1], 0, 15, 5400, now(),
       '0735 (G449, G450): arms 83, 86 and 84''s cells (dcfc10, dcfc20 and dcfc40, normal_day, seed 1) plus '
       'twin_answer_in_tick, so db/checks/0451 §10''s post-count curve is read again with the twin''s one-tick command '
       'lag removed.',
       clock_timestamp()
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, c.cell_code, c.ord, 'otto_q', c.buildout_code,
       '{"deploy_peak_fraction": 0.90, "twin_answer_in_tick": 1}'::jsonb
  FROM public.ottoq_throughput_sweeps s
  JOIN (VALUES ('answer_morning_2026_10_17', 'dcfc10.otto_q.answer_in_tick', 1, 'dcfc10'),
               ('answer_normal_2026_10_17',  'dcfc10.otto_q.answer_in_tick', 1, 'dcfc10'),
               ('answer_normal_2026_10_17',  'dcfc20.otto_q.answer_in_tick', 2, 'dcfc20'),
               ('answer_normal_2026_10_17',  'dcfc40.otto_q.answer_in_tick', 3, 'dcfc40'))
         AS c(sweep_code, cell_code, ord, buildout_code) ON c.sweep_code = s.sweep_code;

-- ── V1: the tick's body less its 0735 insertion is its pre-image ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  FOR p IN SELECT * FROM _0735_patch ORDER BY seq LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = p.fn;
    v_body := replace(v_body, p.c_new, p.c_old);
    IF md5(v_body) IS DISTINCT FROM 'dc2490aad69e25cbb7033a97edabe2c8' THEN
      RAISE EXCEPTION '0735 V1: % less its insertion is not its pre-image (md5 %)', p.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: the helper does nothing without a run or a clock ──
DO $v2$
BEGIN
  IF (twin.ottoq_sim_answer_in_tick(gen_random_uuid(), now()) ->> 'ran')::boolean
     OR (twin.ottoq_sim_answer_in_tick('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd', NULL) ->> 'ran')::boolean
     OR (twin.ottoq_sim_answer_in_tick(NULL, now()) ->> 'ran')::boolean THEN
    RAISE EXCEPTION '0735 V2: the helper acted without a run or a clock';
  END IF;
END $v2$;

-- ── V3: a command given at a tick's clock is carried out by the helper at that clock, and nothing is left behind ──
DO $v3$
DECLARE
  v_run   uuid := 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd';
  v_depot uuid := '11111111-1111-1111-1111-111111111111';
  v_clock timestamptz; v_car uuid; v_stall uuid; v_cmd uuid; v_res jsonb;
  v_status text; v_confirmed timestamptz; v_stall_holds uuid; v_car_at uuid; v_left int;
BEGIN
  SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
  SELECT s.id INTO v_stall FROM public.stalls s
   WHERE s.depot_id = v_depot AND s.stall_type::text = 'staging'
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
   ORDER BY s.id LIMIT 1;
  SELECT v.id INTO v_car FROM public.vehicles v
   WHERE v.home_depot_id = v_depot AND v.current_stall_id IS NULL
     AND v.current_state::text NOT IN ('deployed', 'en_route_to_depot', 'completed', 'dead')
   ORDER BY v.id LIMIT 1;
  IF v_clock IS NULL OR v_stall IS NULL OR v_car IS NULL THEN
    RAISE EXCEPTION '0735 V3: no clock, free staging stall or idle car to test with (clock %, stall %, car %)',
      v_clock, v_stall, v_car;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands c WHERE c.sim_run_id = v_run AND c.status = 'issued') THEN
    RAISE EXCEPTION '0735 V3: arm 83''s run still holds issued commands, so the walk would not be this test alone';
  END IF;
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'twin_answer_in_tick', 1, '0735_v3', now())
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value;
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_depot, v_car, 'proceed_to_stall', jsonb_build_object('stall_id', v_stall), v_clock, '0735_v3')
    RETURNING command_id INTO v_cmd;
    v_res := twin.ottoq_sim_answer_in_tick(v_run, v_clock);
    SELECT c.status, c.confirmed_at INTO v_status, v_confirmed FROM public.ottoq_vehicle_commands c WHERE c.command_id = v_cmd;
    SELECT s.current_vehicle_id INTO v_stall_holds FROM public.stalls s WHERE s.id = v_stall;
    SELECT v.current_stall_id INTO v_car_at FROM public.vehicles v WHERE v.id = v_car;
    RAISE EXCEPTION 'undo_0735_v3';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'undo_0735_v3' THEN RAISE; END IF;
  END;
  IF NOT COALESCE((v_res ->> 'ran')::boolean, false) OR COALESCE((v_res ->> 'walked')::int, 0) < 1 THEN
    RAISE EXCEPTION '0735 V3: the helper did not walk the command (%)', v_res;
  END IF;
  IF v_status IS DISTINCT FROM 'executed' OR v_confirmed IS DISTINCT FROM v_clock THEN
    RAISE EXCEPTION '0735 V3: the command was % at %, not executed at the tick''s clock %', v_status, v_confirmed, v_clock;
  END IF;
  IF v_stall_holds IS DISTINCT FROM v_car OR v_car_at IS DISTINCT FROM v_stall THEN
    RAISE EXCEPTION '0735 V3: the stall holds % and the car points at %, not each other', v_stall_holds, v_car_at;
  END IF;
  SELECT count(*) INTO v_left FROM public.ottoq_vehicle_commands c WHERE c.issued_by = '0735_v3';
  IF v_left > 0 OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_answer_in_tick')
     OR (SELECT s.current_vehicle_id FROM public.stalls s WHERE s.id = v_stall) IS NOT NULL THEN
    RAISE EXCEPTION '0735 V3: the rolled-back sub-block left a command, a dial row or a seated car behind';
  END IF;
END $v3$;

-- ── V4: the dial, the grants, the sweeps and their cells ──
DO $v4$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'twin_answer_in_tick'
                  AND default_value = 0 AND min_value = 0 AND max_value = 1 AND NOT agent_writable)
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_answer_in_tick') THEN
    RAISE EXCEPTION '0735 V4: twin_answer_in_tick is not catalogued 0..1 default 0 with no row setting it';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_answer_in_tick(uuid,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_sim_answer_in_tick(uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'twin.ottoq_sim_answer_in_tick(uuid,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION '0735 V4: the helper''s grants are not postgres and service_role only';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_sim_advance_tick(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_sim_advance_tick(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0735 V4: the tick gained a browser grant';
  END IF;
  IF (SELECT string_agg(s.sweep_code || ':' || s.scenario || ':' || s.ticks || 'x' || s.sim_min_per_tick || ':' || s.priority
                        || ':' || cardinality(s.seeds) || ':' || s.arm_budget_s, ',' ORDER BY s.created_at)
        FROM public.ottoq_throughput_sweeps s
       WHERE s.sweep_code IN ('answer_morning_2026_10_17', 'answer_normal_2026_10_17'))
     IS DISTINCT FROM 'answer_morning_2026_10_17:normal_day:72x5:15:1:5400,answer_normal_2026_10_17:normal_day:144x5:15:1:5400' THEN
    RAISE EXCEPTION '0735 V4: the sweeps are not the morning (72 x 5) then the day (144 x 5), normal_day, priority 15, one seed';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps s, public.ottoq_throughput_sweeps v
              WHERE s.sweep_code IN ('answer_morning_2026_10_17', 'answer_normal_2026_10_17') AND v.sweep_code = 'value_2026_09_30'
                AND (s.seeds[1] IS DISTINCT FROM v.seeds[1] OR s.sim_start IS DISTINCT FROM v.sim_start
                     OR s.depot_id IS DISTINCT FROM v.depot_id)) THEN
    RAISE EXCEPTION '0735 V4: a sweep is not on value_2026_09_30''s first seed, sim start and depot';
  END IF;
  IF (SELECT row(s.ticks, s.sim_min_per_tick, s.seeds, s.sim_start, s.depot_id)
        FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'answer_morning_2026_10_17')
     IS DISTINCT FROM (SELECT row(s.ticks, s.sim_min_per_tick, s.seeds, s.sim_start, s.depot_id)
                         FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'tick5_morning_2026_10_17') THEN
    RAISE EXCEPTION '0735 V4: the morning is not tick5_morning''s ticks, seed, sim start and depot';
  END IF;
  -- each cell is its partner arm's cell plus the dial
  IF EXISTS (
       SELECT 1
         FROM (VALUES ('answer_morning_2026_10_17', 'dcfc10.otto_q.answer_in_tick', 'tick5_morning_2026_10_17',        'dcfc10.otto_q'),
                      ('answer_normal_2026_10_17',  'dcfc10.otto_q.answer_in_tick', 'dcfc40_normal_2026_10_17',        'dcfc10.otto_q'),
                      ('answer_normal_2026_10_17',  'dcfc20.otto_q.answer_in_tick', 'dcfc20_normal_2026_10_17',        'dcfc20.otto_q'),
                      ('answer_normal_2026_10_17',  'dcfc40.otto_q.answer_in_tick', 'dcfc40_power_normal_2026_10_17',  'dcfc40.otto_q'))
                AS x(sweep_code, cell_code, partner_sweep, partner_cell)
         LEFT JOIN LATERAL (SELECT c.fixed_params, c.buildout_code, c.seat FROM public.ottoq_throughput_sweep_cells c
                              JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                             WHERE s.sweep_code = x.sweep_code AND c.cell_code = x.cell_code) n ON true
         LEFT JOIN LATERAL (SELECT c.fixed_params, c.buildout_code, c.seat FROM public.ottoq_throughput_sweep_cells c
                              JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                             WHERE s.sweep_code = x.partner_sweep AND c.cell_code = x.partner_cell) p ON true
        WHERE n.fixed_params IS NULL OR p.fixed_params IS NULL
           OR (n.fixed_params - 'twin_answer_in_tick') IS DISTINCT FROM p.fixed_params
           OR n.buildout_code IS DISTINCT FROM p.buildout_code OR n.seat IS DISTINCT FROM p.seat) THEN
    RAISE EXCEPTION '0735 V4: a cell is not its partner arm''s cell plus twin_answer_in_tick';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code IN ('answer_morning_2026_10_17', 'answer_normal_2026_10_17')) <> 4 THEN
    RAISE EXCEPTION '0735 V4: the sweeps do not hold exactly four cells';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
                    jsonb_each_text(c.fixed_params) f
              WHERE s.sweep_code IN ('answer_morning_2026_10_17', 'answer_normal_2026_10_17')
                AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                                   AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                                   AND (k.max_value IS NULL OR f.value::numeric <= k.max_value))) THEN
    RAISE EXCEPTION '0735 V4: a cell sets a dial the arm would refuse';
  END IF;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0735_a_car_answers_a_command_in_the_tick_it_is_given', false, false,
  'Dial twin_answer_in_tick (default 0) and twin.ottoq_sim_answer_in_tick; one anchored insertion in '
  'public.ottoq_sim_advance_tick after the decide that, with the dial off, reads the dial and does nothing (V1: body less '
  'insertion is its pre-image). Sweeps answer_morning_2026_10_17 (one cell) and answer_normal_2026_10_17 (three cells), '
  'priority 15. No certification arm, canon cell or dial experiment sets the dial.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ══ APPLIED 2026-10-17 16:16:41 UTC (11:16 AM CT), ledger version 20261017161641 ═════════════════════════════════════
--
--   Through apply_migration with the sweep window closed, P0 passing. Executable part 21,128 characters, md5
--   8379f10749d35c7e579d99f558bf463b, equal to the ledger's statements[1] read back. public.ottoq_sim_advance_tick is now
--   md5 34173eb6eea02369ad32360c47c38fa2 (prosrc); twin.ottoq_sim_answer_in_tick c799b2fec0c201b99af6ae04d254cb5d. The
--   two sweeps were written at 16:16:41.899509 and 16:16:41.900663 UTC, so the runner takes the morning first: in its own
--   order they are the 4th to 7th arms of the next window, after 0733's arm and 0734's two mornings and before 0731's
--   bill-window cells.
--
--   Dry-run first, on live, rolled back by a closing exception: P0-P2, the patch (anchor once), V1-V4, then an end to
--   end check of the part V3 does not reach. A begin_charge was given at arm 83's last clock (2026-09-01 23:00 UTC) to
--   car 02ff42a9 (62%) for fast charger 0c916ac0, with the run's clock published as the world tick publishes it. The
--   helper walked 1 command and started 1 charge: the command executed at 23:00:00, the car went to charging_dcfc, and a
--   TWIN session was active from 23:00:00 on that stall with a first reading of 80.69 kW. The five charge-start rules
--   (EN.001, EN.002, EN.004, EN.005, HW.002) all passed and allowed it.
