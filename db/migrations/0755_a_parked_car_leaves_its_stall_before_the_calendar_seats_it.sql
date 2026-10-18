-- migration-version: PENDING
-- migration-name:    a_parked_car_leaves_its_stall_before_the_calendar_seats_it
--
-- 0755  **A parked car leaves its stall before the bay calendar seats it.** (G471)
--       Each tick the decide seats the cars whose bay reservation is due (ottoq.ottoq_activate_due_bay_reservations). It
--       moves the car and stamps it in the bay in one statement: current_stall_id to the bay and current_state to
--       in_wash_bay (or in_detail_bay, in_service_bay) together. The triggers that then free the car's old stall see a car
--       already in a bay leaving a stall, and trg_reassignment_guard reads that as work cut short: it asks the in-depot
--       gate, which defers an automated reassignment, and puts the old stall's pointer back. The bay's claim on the car
--       then trips the one-stall index (idx_stalls_one_vehicle_per_stall, 23505), and the call ends, every seat it made
--       that tick with it. So the calendar cannot seat a car parked on a staging stall, or one leaving a service bay for a
--       wash, at all, and its reservation lapses as a no-show while the car stands ready. Section (4b)'s door does not hit
--       this: ottoq_enact_space_assignment moves the stall alone and the state comes later, with the command. Research
--       wing, rule 10: under a dial, measured in the twin, then a certified change.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-18 2:40-3:09 AM CT) ══════════════════════════════════════════════════════════
--
--   The server log, 2026-10-17 3:15 AM CT to 2026-10-18 3:15 AM CT: ottoq_activate_due_bay_reservations ended whole 235
--   times, every one "sqlstate=23505 msg=duplicate key value violates unique constraint idx_stalls_one_vehicle_per_stall",
--   7 to 46 calls a run on the night's arms (46 on arm 94, 30 on arm 95, 14 on arm 93, 18 on arm 85, 15 on arm 86). That
--   is 0743 §1's "something else also ended the call": in most of the ticks it read, no car was held by the arm.
--   Reproduced on the live bodies (tests/test_bay_activation_frees_parking_sql.py, with the three live BEFORE UPDATE
--   triggers on stalls and the in-depot gate, which 0743's test world leaves out): a car staged on a staging stall with
--   its wash reservation due and its bay free is not seated, and the call logs exactly that 23505. With 0743's dial the
--   refusal costs that seat only and is recorded, and the car is still not seated.
--   On the arms (db/checks/0451 §18, query (39)): every wash or service no-show whose car was idle in the depot at its
--   slot had the car staged_awaiting_service on a staging stall (1 on arm 83, 3 on 84, 6 on 95, none on 93). The car's
--   own reservation also bars it from section (4b), which needs the bay free for the whole job (0451 §14), so a car in
--   that state waits for its reservation to lapse before any door will take it.
--   The committed record cannot show any of this: the refused call rolls back, the gate's pending approval with it, and
--   the log line names neither the car nor the booking. 0743's own reproduction on live (2026-10-17 5:07 PM CT) seated
--   its staged car only because it had cleared both cars' stall pointers and ran with no run live: the guard consults
--   the gate only while a run is 'running' at the depot. Production is no exception, since ottoq_production_start opens
--   its session as an ottoq_sim_runs row with status 'running'.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dial bay_activation_frees_parking (0..1, default 0; not agent-writable).
--   (b) ottoq.ottoq_activate_due_bay_reservations, as 0743 leaves it, three anchored insertions, acting only at 1:
--         - the dial is read once per call;
--         - before the car is stamped in its bay, its stall moves alone, while its state is still the holding state the
--           cursor found it in. The triggers then free the old stall (the guard lets a holding car's stall go) and give
--           the car the bay; the stamp that follows changes no stall, so they do nothing more.
--       The arm interlock fires on the first statement exactly as it fired on the one before (it watches the stall), so a
--       car the arm still holds is refused as before, and 0743's dial still passes over it.
--   (c) Sweep bayfree_normal_2026_10_18: arm 95's cell (answer_normal_2026_10_17 / dcfc40.otto_q.answer_in_tick, the
--       twin answering in the tick) with the dial, its seeds copied by SQL, priority 16, budget 3,000 s.
--   Not changed: which cars the calendar seats or when, the guard, the in-depot gate, the triggers, sections (4), (4b)
--   and (5), how long a car charges or what it needs (rule 9).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 0743 is applied and the activation is the body it leaves (prosrc md5 80d42bc1); the dial and
--   the sweep are absent; arm 95's cell is as read. P2 not already applied. Pre-image to ottoq_schema_snapshots as
--   '0755_pre'. Each anchor matches once. V1 the body less its insertions is its pre-image. V2 nothing for a run that does
--   not exist. V3 the dial is catalogued 0..1 default 0 and not agent-writable, and the sweep's cell is arm 95's plus the
--   dial. Executed in full by tests/test_bay_activation_frees_parking_sql.py on the live bodies (md5 asserted).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At the dial's default the call computes what it computed before
--   (V1, and the insertion is skipped at 0), and no certification arm, canon cell or dial experiment sets the dial.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0755_pre'; if no arm has run, DELETE the
--   sweep bayfree_normal_2026_10_18 and its cell and the dial's catalog row;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0755_a_parked_car_leaves_its_stall_before_the_calendar_seats_it'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0755 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: 0743 applied and its body, nothing of this file, arm 95's cell ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0743_the_bay_calendar_seats_each_car_on_its_own') THEN
    RAISE EXCEPTION '0755 P1: 0743 is not applied (this file patches the activation as 0743 leaves it)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'))
     IS DISTINCT FROM '80d42bc1a54521582a14948f6951a891' THEN
    RAISE EXCEPTION '0755 P1: ottoq.ottoq_activate_due_bay_reservations is not the body 0743 leaves (md5 80d42bc1)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_activation_frees_parking')
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'bayfree_normal_2026_10_18') THEN
    RAISE EXCEPTION '0755 P1: the dial or the sweep already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'answer_normal_2026_10_17' AND c.cell_code = 'dcfc40.otto_q.answer_in_tick'
                    AND c.buildout_code = 'dcfc40' AND c.seat = 'otto_q' AND s.scenario = 'normal_day'
                    AND s.sim_start = '2026-09-01 11:00:00+00' AND s.ticks = 144 AND s.sim_min_per_tick = 5
                    AND c.fixed_params = '{"deploy_peak_fraction": 0.9, "twin_answer_in_tick": 1}'::jsonb) THEN
    RAISE EXCEPTION '0755 P1: arm 95''s cell (answer_normal_2026_10_17 / dcfc40.otto_q.answer_in_tick) is not as read';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0755_a_parked_car_leaves_its_stall_before_the_calendar_seats_it') THEN
    RAISE EXCEPTION '0755 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0755_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bay_activation_frees_parking',
        '0755 (G471): 1 = the bay calendar''s activation moves a car''s stall to its bay while the car is still in its '
        'holding state, and only then stamps it in the bay, so the triggers free the stall it was parked on. 0 = the stall '
        'move and the bay state go in one statement, as before 0755: the reassignment guard then reads a parked car as '
        'one cut short mid-work, keeps its old stall, and the seat fails on the one-stall index. Research days only until '
        'certified.',
        0, 0, 1, 'ottoq.ottoq_activate_due_bay_reservations', false);

-- ── (b) the activation ──
CREATE TEMP TABLE _0755_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0755_patch VALUES
  -- 1: the dial's variable, beside 0743's
  (1, 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o1$        v_each boolean; v_refused jsonb := '[]'::jsonb;   -- 0743 (G457)
$o1$,
   $n1$        v_each boolean; v_refused jsonb := '[]'::jsonb;   -- 0743 (G457)
        v_free_first boolean;   -- 0755 (G471)
$n1$),
  -- 2: the dial, read once per call
  (2, 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o2$  v_each := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_activation_per_seat', 0), 0) >= 1;
$o2$,
   $n2$  v_each := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_activation_per_seat', 0), 0) >= 1;
  -- 0755 (G471): with bay_activation_frees_parking on, a car leaves the stall it is parked on before it is stamped in its
  -- bay. Off, the move and the stamp are one statement, as before.
  v_free_first := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_activation_frees_parking', 0), 0) >= 1;
$n2$),
  -- 3: the stall moves first, while the car is still holding
  (3, 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o3$    UPDATE public.vehicles
       SET current_stall_id = v_res.stall_id,
           current_state    = v_state::vehicle_state,
$o3$,
   $n3$    -- 0755 (G471): with bay_activation_frees_parking on, the car's stall moves alone first, while its state is still
    -- the holding state the cursor found it in. Moved and stamped in one statement, it is a car in a bay leaving a
    -- stall, which trg_reassignment_guard reads as work cut short: the gate defers, the old stall keeps the car, and
    -- the bay's claim on it trips idx_stalls_one_vehicle_per_stall. Moved first, it is a holding car leaving its
    -- parking, which needs no approval, and the triggers free the old stall and give it the bay, as (4b)'s door does.
    -- The statement below then changes no stall, so they do nothing more. The arm interlock watches the stall, so a
    -- car the arm holds is refused here exactly as it was there.
    IF v_free_first THEN
      UPDATE public.vehicles SET current_stall_id = v_res.stall_id
       WHERE id = v_res.vehicle_id AND current_stall_id IS DISTINCT FROM v_res.stall_id;
    END IF;
    UPDATE public.vehicles
       SET current_stall_id = v_res.stall_id,
           current_state    = v_state::vehicle_state,
$n3$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure);
  FOR p IN SELECT * FROM _0755_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0755: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0755: the activation is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its insertions is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0755_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '80d42bc1a54521582a14948f6951a891' THEN
    RAISE EXCEPTION '0755 V1: the activation less its insertions is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: nothing for a run that does not exist ──
DO $v2$
BEGIN
  IF ottoq.ottoq_activate_due_bay_reservations('00000000-0000-0000-0000-00000000755a'::uuid,
                                               '11111111-1111-1111-1111-111111111111'::uuid, now()) <> 0 THEN
    RAISE EXCEPTION '0755 V2: the activation seated something for a run that does not exist';
  END IF;
END $v2$;

-- ── (c) the pair: arm 95's cell with the dial, its seeds copied by SQL ──
INSERT INTO public.ottoq_throughput_sweeps (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, notes)
SELECT 'bayfree_normal_2026_10_18',
       'A parked car leaves its stall before the bay calendar seats it: arm 95''s 40 robotic fast chargers, the twin '
       'answering in the tick, with bay_activation_frees_parking',
       s.depot_id, s.scenario, s.sim_start, s.ticks, s.sim_min_per_tick, s.seeds, 0, 16, 3000, 'active',
       '0755 (G471). Pairs with arm 95 (answer_normal_2026_10_17 / dcfc40.otto_q.answer_in_tick) on its seed; it differs '
       'only by the dial.'
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'answer_normal_2026_10_17';
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc40.otto_q.answer_in_tick.bay_frees_parking', 1, 'otto_q', 'dcfc40',
       '{"deploy_peak_fraction": 0.90, "twin_answer_in_tick": 1, "bay_activation_frees_parking": 1}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'bayfree_normal_2026_10_18';

-- ── V3: the dial, the cell ──
DO $v3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'bay_activation_frees_parking' AND default_value = 0 AND min_value = 0 AND max_value = 1
                    AND NOT COALESCE(agent_writable, false)) THEN
    RAISE EXCEPTION '0755 V3: the dial is not catalogued 0..1, default 0, not agent-writable';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'bayfree_normal_2026_10_18') <> 1
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                     JOIN public.ottoq_throughput_sweep_cells c95 ON c95.cell_code = 'dcfc40.otto_q.answer_in_tick'
                     JOIN public.ottoq_throughput_sweeps s95 ON s95.sweep_id = c95.sweep_id
                                                            AND s95.sweep_code = 'answer_normal_2026_10_17'
                     WHERE s.sweep_code = 'bayfree_normal_2026_10_18'
                       AND c.buildout_code = c95.buildout_code AND c.seat = c95.seat
                       AND (s.depot_id, s.scenario, s.sim_start, s.ticks, s.sim_min_per_tick, s.seeds)
                         = (s95.depot_id, s95.scenario, s95.sim_start, s95.ticks, s95.sim_min_per_tick, s95.seeds)
                       AND c.fixed_params - 'bay_activation_frees_parking' = c95.fixed_params
                       AND c.fixed_params ->> 'bay_activation_frees_parking' = '1') THEN
    RAISE EXCEPTION '0755 V3: the sweep''s cell is not arm 95''s plus the dial';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0755_a_parked_car_leaves_its_stall_before_the_calendar_seats_it', false, false,
        'Dial bay_activation_frees_parking (default 0); three anchored insertions in '
        'ottoq.ottoq_activate_due_bay_reservations, on 0743''s body, that act only at 1: the car''s stall moves alone '
        'before it is stamped in its bay, so the triggers free the stall it was parked on (V1: body less insertions is its '
        'pre-image). Sweep bayfree_normal_2026_10_18 (arm 95''s cell plus the dial, its seed, priority 16). No '
        'certification arm, canon cell or dial experiment sets the dial.',
        now());

COMMIT;
