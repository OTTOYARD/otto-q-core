-- migration-version: PENDING
-- migration-name:    the_bay_calendar_seats_each_car_on_its_own
--
-- 0743  **The bay calendar seats each car on its own, and waits for a car the robotic arm still holds.** (G457)
--       Each tick the decide seats the cars whose bay reservation is due: ottoq.ottoq_activate_due_bay_reservations.
--       It seats them all or none. One error ends the call, every seat it made that tick goes with it, and the only trace
--       is a WARNING in the server log. A car that has just finished charging is ready for its bay at once, but the arm
--       still holds it for its demate (one tick in the twin), and moving it trips the arm interlock, which raises. So in a
--       tick where such a car holds a bay reservation, the calendar seats no one, its own ready cars included. Section (4)
--       already passes over a car the arm holds (0011-TETHER); the calendar never did. Research wing, rule 10: under a
--       dial, measured in the twin, then a certified change.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-17 4:55-5:20 PM CT) ══════════════════════════════════════════════════════════
--
--   Reproduced on live inside one transaction, rolled back, at 5:07 PM CT (db/checks/0451 query (24)). Two cars, each
--   with a held wash reservation in its window and its bay empty: A just off its charger in charge_complete_holding with
--   the arm still holding it, B staged and ready. The call seated 0 and B stayed staged_awaiting_service: it seated B
--   first, then moving A raised "arm interlock: vehicle ... is held by the arm at stall ...", and the handler threw both
--   seats away. With A's arm released, the same call seated both.
--
--   On last night's normal-day arms (seed 1, 12 hours), a car whose charge ended at a tick held a live bay booking in 36
--   of 144 ticks on arm 83 (10 posts), 38 on arm 86 (20), 50 on arm 84 (40) and 45 on arm 85 (40, managed). On arms 84
--   and 85 the calendar seated no car in any of those ticks (0 of its 3 seats, 0 of 4). On arms 83 and 86 some did (5 of
--   10, 2 of 4): a held car's early seat is declined before its move when another booking owns the time.
--
--   What it costs is smaller than that sounds, and not all of it is this. The calendar seats few cars at all (3 to 10 a
--   run; the staged path seats most), and it let reservations lapse whose car stood ready in the depot: 3, 1, 3, 2 and 2
--   wash reservations on arms 82, 83, 84, 85 and 86. On arm 84 car b73b5763 was ready in staging from 7:15 AM CT, its
--   detail reservation on NASH-WSH-01 ran 7:55-8:13 on an empty, unreserved bay, it was released as a no-show at 8:15,
--   and the car was washed at 10:25. In most of those reservations' ticks no car was held by the arm, so something else
--   also ended the call, and the server log is all it left. Under the dial each refused seat is recorded with its SQLSTATE
--   and message, so the arm will say what. The wash line's larger costs at 40 posts are G458's (reservations held for cars
--   still charging past their plan), and this file does not touch them.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dial bay_activation_per_seat (0..1, default 0; not agent-writable).
--   (b) ottoq.ottoq_activate_due_bay_reservations, five anchored insertions, acting only at 1:
--         - the dial is read once per call;
--         - the cursor passes over a car the arm still holds (public.ottoq_vehicle_is_tethered at the call's clock), as
--           section (4) does; it is seated on a later tick, once its demate is done;
--         - each seat runs in its own subtransaction. A seat that raises is undone, its stall reservation with it, and the
--           others stand. At 0 its handler re-raises, so the call ends whole exactly as before;
--         - the seats refused in a call are recorded once, with each booking's SQLSTATE and message
--           (ottoq.bay_reservation_seat_refused, catalogued).
--   (c) Sweep bayseat_normal_2026_10_17: arm 84's cell (dcfc40.otto_q) with the dial, normal_day from 6 AM CT for 12
--       hours at 5 sim-minutes a tick, value_2026_09_30's first seed, priority 16, so it runs after 0732's seeds and
--       0737's arm. Its arm budget is 3,000 s (arm 84 took 2,288 s), so the runner, which will not start an arm it
--       estimates past the window's close, can start it in a window's last hour.
--   Not changed: the reconcile, the yield, sections (4), (4b) and (5), how long a car charges, or what it needs (rule 9).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the activation is the body this file patches (prosrc md5 4fb04e0a);
--   public.ottoq_vehicle_is_tethered(uuid, timestamptz) exists; the dial, the event type and the sweep are absent; arm 84's
--   cell is as read. P2 not already applied. Pre-image to ottoq_schema_snapshots as '0743_pre'. Each anchor matches once,
--   and the five go in as one definition (the third and fourth open and close one block). V1 the body less its insertions
--   is its pre-image. V2 nothing for a run that does not exist. V3 the dial is catalogued
--   0..1 default 0 and not agent-writable, the event type is catalogued, and the sweep's cell is arm 84's plus the dial.
--   Executed in full by tests/test_bay_activation_per_seat_sql.py on the live bodies (md5 asserted).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At the dial's default the call computes what it computed before
--   (V1, and the new handler re-raises), and no certification arm, canon cell or dial experiment sets the dial.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0743_pre'; if no arm has run, DELETE the
--   sweep bayseat_normal_2026_10_17 and its cell, the dial's catalog row and the event type;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0743_the_bay_calendar_seats_each_car_on_its_own'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0743 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the body read, the helper it calls, arm 84's cell, nothing of this file ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'))
     IS DISTINCT FROM '4fb04e0a5f2d5d16b24fda2f9990f2d1' THEN
    RAISE EXCEPTION '0743 P1: ottoq.ottoq_activate_due_bay_reservations is not the body this file patches (md5 4fb04e0a)';
  END IF;
  IF to_regprocedure('public.ottoq_vehicle_is_tethered(uuid,timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION '0743 P1: public.ottoq_vehicle_is_tethered(uuid, timestamptz) is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_activation_per_seat')
     OR EXISTS (SELECT 1 FROM public.ottoq_event_types_catalog WHERE event_type = 'ottoq.bay_reservation_seat_refused')
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'bayseat_normal_2026_10_17') THEN
    RAISE EXCEPTION '0743 P1: the dial, the event type or the sweep already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'dcfc40_power_normal_2026_10_17' AND c.cell_code = 'dcfc40.otto_q'
                    AND c.buildout_code = 'dcfc40' AND s.scenario = 'normal_day'
                    AND s.sim_start = '2026-09-01 11:00:00+00' AND s.ticks = 144 AND s.sim_min_per_tick = 5
                    AND (c.fixed_params ->> 'deploy_peak_fraction')::numeric = 0.9
                    AND c.fixed_params - 'deploy_peak_fraction' = '{}'::jsonb) THEN
    RAISE EXCEPTION '0743 P1: arm 84''s cell (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q) is not as read';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0743_the_bay_calendar_seats_each_car_on_its_own') THEN
    RAISE EXCEPTION '0743 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0743_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bay_activation_per_seat',
        '0743 (G457): 1 = the bay calendar''s activation passes over a car the robotic arm still holds, and seats each car '
        'in its own subtransaction, so a refused seat costs that seat and not every seat in the call (each refusal is '
        'recorded as ottoq.bay_reservation_seat_refused). 0 = one error ends the call and every seat that tick goes with '
        'it, as before 0743. Research days only until certified.',
        0, 0, 1, 'ottoq.ottoq_activate_due_bay_reservations', false);

-- ── (b) the event a refused seat leaves ──
INSERT INTO public.ottoq_event_types_catalog (event_type, category, description, emitter, default_severity, introduced_in)
VALUES ('ottoq.bay_reservation_seat_refused', 'system_event',
        '0743 (G457): under bay_activation_per_seat, the bay calendar''s activation refused one or more seats in a call '
        'and kept the others. The payload lists each refused booking with its vehicle, stall, SQLSTATE and message.',
        'ottoq.ottoq_activate_due_bay_reservations', 'warning', '0743');

-- ── (b) the activation ──
CREATE TEMP TABLE _0743_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0743_patch VALUES
  -- 1: the dial, read once per call
  (1, 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o1$        v_end_ts timestamptz;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;
$o1$,
   $n1$        v_end_ts timestamptz;
        v_each boolean; v_refused jsonb := '[]'::jsonb;   -- 0743 (G457)
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;
  -- 0743 (G457): with bay_activation_per_seat on, a car the robotic arm still holds waits for a later tick, and each seat
  -- is its own: a refused seat costs that seat, not every seat this call. Off, the call is all or nothing, as before.
  v_each := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_activation_per_seat', 0), 0) >= 1;
$n1$),
  -- 2: the cursor passes over a car the arm still holds
  (2, 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o2$       AND NOT ottoq.ottoq_uplink_transfer_holds(b.vehicle_id, p_sim_run_id)
$o2$,
   $n2$       AND NOT ottoq.ottoq_uplink_transfer_holds(b.vehicle_id, p_sim_run_id)
       -- 0743 (G457): and, with bay_activation_per_seat on, not a car the robotic arm still holds: moving it trips the
       -- arm interlock, which raises. Section (4) passes over such a car the same way (0011-TETHER).
       AND (NOT v_each OR NOT public.ottoq_vehicle_is_tethered(v.id, p_clock))
$n2$),
  -- 3: each seat opens its own subtransaction
  (3, 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o3$  LOOP
    -- CAS the stall. If someone else took it first, leave the reservation alone and
$o3$,
   $n3$  LOOP
    BEGIN   -- 0743 (G457): each seat its own subtransaction (its handler closes the loop body)
    -- CAS the stall. If someone else took it first, leave the reservation alone and
$n3$),
  -- 4: and closes it: off, the error ends the call as before; on, it costs this seat only
  (4, 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o4$    IF NOT v_res.in_window THEN v_early := v_early + 1; END IF;
    v_n := v_n + 1;
  END LOOP;
$o4$,
   $n4$    IF NOT v_res.in_window THEN v_early := v_early + 1; END IF;
    v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      -- 0743 (G457): off, exactly as before: the error ends the call, and every seat it made goes with it. On, this
      -- seat alone is undone (its stall reservation with it), the others stand, and the refusal is recorded below.
      IF NOT v_each THEN RAISE; END IF;
      v_refused := v_refused || jsonb_build_object('booking_id', v_res.booking_id, 'vehicle_id', v_res.vehicle_id,
                     'stall_id', v_res.stall_id, 'sqlstate', SQLSTATE, 'message', left(SQLERRM, 240));
      RAISE WARNING '0743: a bay seat refused, the others kept: booking % vehicle % (% %)',
        v_res.booking_id, v_res.vehicle_id, SQLSTATE, SQLERRM;
    END;
  END LOOP;
$n4$),
  -- 5: the seats refused this call are recorded once
  (5, 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o5$  -- ONE summary event per tick (event-write amplification is the known tick-cost driver).
$o5$,
   $n5$  -- 0743 (G457): the seats refused this call, in one event. Off, a refusal ends the call before it gets here.
  IF jsonb_array_length(v_refused) > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'bay_reservation_activation',
        p_event_type := 'ottoq.bay_reservation_seat_refused', p_entity_type := 'depot',
        p_entity_id := p_depot_id,
        p_payload := jsonb_build_object('refused', v_refused, 'seated_total', v_n,
          'note', '0743: each seat is its own, so these refusals cost these seats and no other'),
        p_severity := 'warning',
        p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  -- ONE summary event per tick (event-write amplification is the known tick-cost driver).
$n5$);

-- All five go in at once: the third and fourth open and close one block, and neither compiles alone.
DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure);
  FOR p IN SELECT * FROM _0743_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0743: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0743: the activation is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its insertions is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0743_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '4fb04e0a5f2d5d16b24fda2f9990f2d1' THEN
    RAISE EXCEPTION '0743 V1: the activation less its insertions is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: nothing for a run that does not exist ──
DO $v2$
BEGIN
  IF ottoq.ottoq_activate_due_bay_reservations('00000000-0000-0000-0000-00000000743a'::uuid,
                                               '11111111-1111-1111-1111-111111111111'::uuid, now()) <> 0 THEN
    RAISE EXCEPTION '0743 V2: the activation seated something for a run that does not exist';
  END IF;
END $v2$;

-- ── (c) the pair: arm 84's cell with the dial ──
INSERT INTO public.ottoq_throughput_sweeps (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, notes)
VALUES ('bayseat_normal_2026_10_17',
        'The bay calendar seats each car on its own: arm 84''s 40 robotic fast chargers with bay_activation_per_seat',
        '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 16, 3000, 'active',
        '0743 (G457). Pairs with arm 84 (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q) on value_2026_09_30''s first '
        'seed; it differs only by the dial.');
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc40.otto_q.bay_per_seat', 1, 'otto_q', 'dcfc40',
       '{"deploy_peak_fraction": 0.90, "bay_activation_per_seat": 1}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'bayseat_normal_2026_10_17';

-- ── V3: the dial, the event type, the cell ──
DO $v3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'bay_activation_per_seat' AND default_value = 0 AND min_value = 0 AND max_value = 1
                    AND NOT COALESCE(agent_writable, false)) THEN
    RAISE EXCEPTION '0743 V3: the dial is not catalogued 0..1, default 0, not agent-writable';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_event_types_catalog WHERE event_type = 'ottoq.bay_reservation_seat_refused') THEN
    RAISE EXCEPTION '0743 V3: the event type is not catalogued';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'bayseat_normal_2026_10_17') <> 1
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                     JOIN public.ottoq_throughput_sweep_cells c84 ON c84.cell_code = 'dcfc40.otto_q'
                     JOIN public.ottoq_throughput_sweeps s84 ON s84.sweep_id = c84.sweep_id
                                                            AND s84.sweep_code = 'dcfc40_power_normal_2026_10_17'
                     WHERE s.sweep_code = 'bayseat_normal_2026_10_17'
                       AND c.buildout_code = c84.buildout_code AND c.seat = c84.seat
                       AND (s.scenario, s.sim_start, s.ticks, s.sim_min_per_tick, s.seeds[1])
                         = (s84.scenario, s84.sim_start, s84.ticks, s84.sim_min_per_tick, s84.seeds[1])
                       AND c.fixed_params - 'bay_activation_per_seat' = c84.fixed_params
                       AND c.fixed_params ->> 'bay_activation_per_seat' = '1') THEN
    RAISE EXCEPTION '0743 V3: the sweep''s cell is not arm 84''s plus the dial';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0743_the_bay_calendar_seats_each_car_on_its_own', false, false,
        'Dial bay_activation_per_seat (default 0) and the event type ottoq.bay_reservation_seat_refused; five anchored '
        'insertions in ottoq.ottoq_activate_due_bay_reservations that act only at 1: the cursor passes over a car the arm '
        'still holds, and each seat is its own subtransaction whose handler re-raises at 0 (V1: body less insertions is its '
        'pre-image). Sweep bayseat_normal_2026_10_17 (arm 84''s cell plus the dial, one seed, priority 16). No '
        'certification arm, canon cell or dial experiment sets the dial.',
        now());

COMMIT;
