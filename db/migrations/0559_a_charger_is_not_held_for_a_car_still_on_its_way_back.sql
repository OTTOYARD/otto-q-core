-- migration-version: PENDING
-- migration-name:    a_charger_is_not_held_for_a_car_still_on_its_way_back
--
-- 0559  **A charger is not held for a car still on its way back when the run leaves the charge to the line.** (G293,
--       part 1; CLAUDE.md rule 9: "freeing a charger the moment its car is done, and better ordering of who is served
--       next")
--
-- ══ §1 WHY (measured live on check 0412's run 4b0999db, 2026-09-28, 7:40-7:55 PM CT, sim 4:26-7:21 AM) ══════════════
--
--   G293 (check 0411 §22) blamed the in-kernel L2 optimizer's order for cars seated ahead of cars that had waited longer.
--   Measured on this run, the optimizer is not the mechanism: the decide path's cursor walks the charge line in order
--   (immediate dispatch, then the banked response ratio) and asks per car for a reservation, then the optimizer's proposal
--   for that car, then the heuristic. The chargers the later cars took were already claimed for them before the cursor
--   got there, in two ways (0412 §29):
--     - the plan's own charge booking, made first come: Tesla-AV-067 arrived at 5:56 AM and at 6:02 its plan booked
--       NASH-L2-STALL-12 from 6:20; at 6:24 the 28 cars ahead of it in the line were refused that charger (the gate refuses
--       a charger another car's live booking covers). Not in this file (§4).
--     - a charger reserved for a car that was still out. At the recall, `ottoq.ottoq_book_appointment` reserves any free
--       charger for the returning car, for its ETA plus 40 minutes, and sends `proceed_to_stall`, which the gate refuses
--       while the car is still driving (`vehicle_state_incompatible: en_route_to_depot`), and the reservation stays; and
--       `ottoq.ottoq_reoptimize_reservation_book` moves a returning car below 45% from the stall it holds to a free fast
--       charger. By sim 7:21 AM, 8 chargers (5 fast, 3 L2) had been reserved for cars not yet at the depot and stood empty
--       66.3 charger-minutes (up to 21.9 minutes each: Zoox-AV-098 held NASH-DCFC-STALL-10 from 4:31:57 AM and arrived at
--       4:53). Cars were waiting for a charger throughout: 2,486 refusals fell inside those holds (car-ticks; every
--       refusal in the window, not only those a held charger could have served). Each returning car then took its charger
--       ahead of every car waiting (source `reservation_honoured`).
--
--   The run had asked for exactly the opposite. `prearrival_charge_yields_to_solver` (0339) is 1 on this run, as on
--   every armed run (`ottoq_agentic_arm`: "the charge stall is not reserved before the primary proposer can see it"),
--   and its catalog row reads: "When 1, ... does NOT pre-reserve a dcfc/l2 stall for an en_route_to_depot vehicle; it
--   reserves staging only and leaves the charge assignment to the gate". Backstop 2 of
--   `ottoq.ottoq_sim_prearrival_contracts` honours it; the appointment book and the re-optimizer never read it.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq.ottoq_book_appointment`, when the run's dial is 1, reserves no charger: the returning car gets a staging
--       stall (the branch it already takes when no charger is free) and its charge is assigned at the depot, in the line.
--       The charge plan (class and target) is still made and stamped on the car and its charge atom.
--   (b) `ottoq.ottoq_reoptimize_reservation_book`, when the run's dial is 1, upgrades nothing and says so
--       (`yields_to_the_line`): a returning car holds no charger to upgrade, and a free fast charger taken for it now
--       would stand empty until it arrives.
--   At 0 (the global default, and every certification arm, which `ottoq_agentic_arm` refuses to arm) nothing changes.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   Both functions run in every arm (the recall path and the decide-and-dispatch step). The canon runs at 0, where
--   neither changes, so its digests should not move; the sweep confirms it. A dial pair arm that sets the dial to 1 does
--   change.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - G293 part 2: a waiting car's plan books a charger window first come, and that booking bars the cars ahead of it
--     in the line when the window comes due (Tesla-AV-067 above). Whether a waiting car's charge booking may bar a car
--     ahead of it, and how to keep the calendar in the line's order, is a design question with a research-wing paired
--     test first (rule 10).
--   - The dial's global default (0). Production reads the global tier; changing it is a research-wing recommendation,
--     shipped as its own certified change.
--   - `ottoq_sim_prearrival_contracts`' M1 refresh, which keeps a returning car's reservation alive: under 1 it now only
--     ever refreshes a staging stall. Unchanged.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0559 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run at the twin depot (V3 edits twin cars, stalls, chargers, visits and dials on an ended run) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0559 P1: a run is live at the twin depot';
  END IF;
END $live$;

-- ── P2: the two functions are the ones measured on 2026-09-28 (md5 of their source) ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)',
                                                                                  'c63a84bfd533ca58ca4e8ac1356520e0'),
      ('ottoq.ottoq_reoptimize_reservation_book(uuid,timestamp with time zone)',  'd3bc978503d2ded0eece6650af75582b')) x(sig, md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0559 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0559_pre', 'function', p.pronamespace::regnamespace::text, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
 WHERE p.oid IN ('ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)'::regprocedure,
                 'ottoq.ottoq_reoptimize_reservation_book(uuid,timestamp with time zone)'::regprocedure);

-- ── (a) and (b): one splice in each ──
DO $splice$
DECLARE v_def text; n int; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    -- (a) the appointment book reserves no charger for a returning car when the run leaves the charge to the line
    ('ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)',
$o$  IF v_has_charge THEN
    -- reserve only an INLET-COMPATIBLE charge stall so the booking is honourable on arrival
$o$,
$n$  -- 0559 (G293, CLAUDE.md rule 9): no charger is held for a car still on its way back when the run leaves the charge
  -- to the line (prearrival_charge_yields_to_solver = 1, 0339; ottoq_agentic_arm sets it on every armed run). The
  -- appointment is made at the recall, so the car is never here yet: on 0412's run a free charger reserved here for a
  -- returning car stood empty up to 22 minutes while the cars waiting at the depot were refused it, and the car then took
  -- it ahead of all of them. The car gets a staging stall below, as backstop 2 of ottoq_sim_prearrival_contracts has
  -- given it since 0339, and its charge is assigned at the depot, in the line's order.
  IF v_has_charge
     AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'prearrival_charge_yields_to_solver', 0), 0) < 1 THEN
    -- reserve only an INLET-COMPATIBLE charge stall so the booking is honourable on arrival
$n$),
    -- (b) the reservation re-optimizer upgrades nothing when the run leaves the charge to the line
    ('ottoq.ottoq_reoptimize_reservation_book(uuid,timestamp with time zone)',
$o$  IF NOT FOUND OR COALESCE(v_run.policy,'otto_q') <> 'otto_q' THEN
    RETURN jsonb_build_object('swaps', 0);
  END IF;
$o$,
$n$  IF NOT FOUND OR COALESCE(v_run.policy,'otto_q') <> 'otto_q' THEN
    RETURN jsonb_build_object('swaps', 0);
  END IF;

  -- 0559 (G293, CLAUDE.md rule 9): when the run leaves the charge to the line (prearrival_charge_yields_to_solver = 1,
  -- 0339), a returning car holds no charger before it arrives, so there is nothing to upgrade, and a free fast charger
  -- taken for it now would stand empty until it arrives while the cars at the depot wait (0412: Waymo-AV-006 and
  -- Tesla-AV-049, moved from a staging or L2 hold to a free fast charger while driving back).
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'prearrival_charge_yields_to_solver', 0), 0) >= 1 THEN
    RETURN jsonb_build_object('swaps', 0, 'cuopt', 0, 'yields_to_the_line', true);
  END IF;
$n$)) x(sig, a_old, a_new)
  LOOP
    v_def := pg_get_functiondef(r.sig::regprocedure);
    n := (length(v_def) - length(replace(v_def, r.a_old, ''))) / length(r.a_old);
    IF n <> 1 THEN RAISE EXCEPTION '0559 splice: the anchor matches % times in %, not 1: %', n, r.sig, left(r.a_old, 80); END IF;
    EXECUTE replace(v_def, r.a_old, r.a_new);
  END LOOP;
END $splice$;

COMMENT ON FUNCTION ottoq.ottoq_reoptimize_reservation_book(uuid, timestamptz) IS
  'Moves a returning car below 45% from a non-fast stall it holds to a free fast charger (cuOpt''s pick first). 0559 '
  '(G293): does nothing when the run leaves the charge to the line (prearrival_charge_yields_to_solver = 1): the car holds '
  'no charger before it arrives, and a charger taken for it now would stand empty while the cars at the depot wait.';

-- ── V1 (comment-stripped): each change is in the live source ──
DO $verify$
DECLARE r record; v_src text; k int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)',
       'IF v_has_charge\s+AND COALESCE\(public\.ottoq_policy_get\(p_sim_run_id,\s*''prearrival_charge_yields_to_solver'',\s*0\),\s*0\)\s*<\s*1\s+THEN', 1),
      ('ottoq.ottoq_reoptimize_reservation_book(uuid,timestamp with time zone)',
       'IF COALESCE\(public\.ottoq_policy_get\(p_sim_run_id,\s*''prearrival_charge_yields_to_solver'',\s*0\),\s*0\)\s*>=\s*1\s+THEN', 1),
      ('ottoq.ottoq_reoptimize_reservation_book(uuid,timestamp with time zone)',
       '''yields_to_the_line'',\s*true', 1)
    ) x(sig, pat, want)
  LOOP
    v_src := regexp_replace(regexp_replace(pg_get_functiondef(r.sig::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
    k := (SELECT count(*) FROM regexp_matches(v_src, r.pat, 'g'));
    IF k <> r.want THEN RAISE EXCEPTION '0559 V1: % matches % times in %, not %', r.pat, k, r.sig, r.want; END IF;
  END LOOP;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0559_a_charger_is_not_held_for_a_car_still_on_its_way_back', true, true,
  'G293 part 1: the appointment book reserved a free charger for a car still driving back (at the recall, for its ETA '
  'plus 40 minutes) and the reservation re-optimizer moved a returning car below 45% to a free fast charger, both '
  'ignoring prearrival_charge_yields_to_solver (0339), which every armed run sets to 1. On 0412''s run by sim 7:21 AM, '
  '8 chargers stood empty 66.3 charger-minutes for cars not yet at the depot while waiting cars were refused, and each '
  'returning car then took its charger ahead of the line. Both now honour the dial: at 1 a returning car gets staging '
  'and its charge is assigned at the depot, in the line''s order. At 0 (the canon) nothing changes.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest ended operator run at the twin depot, pinned as the active run for this transaction.
--   Three free twin cars, every other twin car offline, every twin charger reporting Available with no car and no
--   reservation. A, B and R are driving back at 30% (en_route_to_depot) with an open visit that owes a charge; their
--   inlet type is cleared so every charger fits them.
--   (1) dial 1: the appointment book gives A no charger (not staging-or-nothing by accident: at least one fast charger
--       is free at that moment);
--   (2) dial 1: with R holding a staging stall, the re-optimizer upgrades nothing and says yields_to_the_line, and R
--       holds no charger;
--   (3) dial 0: the appointment book reserves B a charger, as before;
--   (4) dial 0: the re-optimizer moves R to a free fast charger, as before.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  t timestamptz; car uuid[]; a uuid; b uuid; rr uuid; stg uuid;
  res_a jsonb; res_b jsonb; ro1 jsonb; ro0 jsonb; free_fast int;
  a_chg int; b_chg int; r_chg1 int; r_fast0 int; v_pass text;
BEGIN
  BEGIN
    SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.run_by = 'operator_demo' AND r.status NOT IN ('initializing', 'running', 'paused')
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0559 V3: no ended operator run at the twin depot'; END IF;
    SELECT sim_clock_current + interval '1 day' INTO t FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = t, tick_count = tick_count + 1,
                                     policy = 'otto_q'
     WHERE sim_run_id = v_run;
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);

    SELECT array_agg(id ORDER BY id) INTO car FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS NULL
         AND v.robotic_tether_until IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id OR s.reserved_by = v.id)
       ORDER BY v.id LIMIT 3) q;
    IF coalesce(array_length(car, 1), 0) < 3 THEN RAISE EXCEPTION '0559 V3: fewer than three free twin cars'; END IF;
    a := car[1]; b := car[2]; rr := car[3];

    -- only these three in play; every twin charger free, Available and fresh
    UPDATE public.vehicles SET current_state = 'offline'
     WHERE home_depot_id = v_depot AND NOT (id = ANY (car)) AND robotic_tether_until IS NULL AND current_state <> 'offline';
    UPDATE public.stalls
       SET current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL, status = 'available'
     WHERE depot_id = v_depot AND stall_type::text IN ('dcfc', 'l2');
    UPDATE public.ottoq_ocpp_chargers c2 SET station_state = 'Available', last_heartbeat_at = t
      FROM public.stalls s
     WHERE s.ocpp_charger_id = c2.charger_id AND s.depot_id = v_depot AND s.stall_type::text IN ('dcfc', 'l2');
    UPDATE public.ottoq_stall_bookings
       SET state = 'released', released_at = GREATEST(t, COALESCE(booked_at_sim, t)), release_reason = 'v3_0559_setup'
     WHERE sim_run_id = v_run AND state IN ('held', 'active');
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (car) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    UPDATE public.vehicles
       SET current_state = 'en_route_to_depot', current_soc = 30, target_soc = 100, inlet_type = NULL,
           last_state_change = t - interval '10 minutes',
           config = (COALESCE(config, '{}'::jsonb) - 'charge_wait' - 'remedy_wait' - 'deploy_gate' - 'exception' - 'svc_step')
     WHERE id = ANY (car);
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, target_soc, atoms,
                                          status, source)
    SELECT x.vid, v_run, v_depot, t + interval '20 minutes', 'V3-0559-' || x.vid::text, 'standard', 100,
           jsonb_build_array(jsonb_build_object('svc', 'charge', 'concurrency', 'anchor', 'must_do', true, 'status', 'pending'),
                             jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'pending')),
           'open', 'v3_0559'
      FROM unnest(car) AS x(vid);

    -- (1) dial 1: A gets no charger, with fast chargers free
    PERFORM public.ottoq_policy_set('run', v_run, 'prearrival_charge_yields_to_solver', 1, 'v3_0559');
    SELECT count(*) INTO free_fast FROM public.stalls s
      JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = v_depot AND s.stall_type::text = 'dcfc' AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
       AND c.station_state = 'Available';
    res_a := ottoq.ottoq_book_appointment(a, v_run, t, 'low_soc_reserve', 'urgent', false, 20, 30, v_depot);
    SELECT count(*) INTO a_chg FROM public.stalls WHERE reserved_by = a AND stall_type::text IN ('dcfc', 'l2');
    IF free_fast < 1 OR a_chg <> 0 OR COALESCE(res_a->>'stall_type', 'none') IN ('dcfc', 'l2') THEN
      RAISE EXCEPTION '0559 V3 FAILED (1): with % fast charger(s) free and the dial at 1 the appointment book returned % and A holds % charger(s)',
        free_fast, res_a, a_chg;
    END IF;

    -- (2) dial 1: R holds a staging stall; the re-optimizer upgrades nothing
    SELECT s.id INTO stg FROM public.stalls s
     WHERE s.depot_id = v_depot AND s.stall_type::text = 'staging' AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
     ORDER BY s.stall_code LIMIT 1;
    IF stg IS NULL OR NOT public.ottoq_reserve_stall(stg, rr, t, 1800) THEN
      RAISE EXCEPTION '0559 V3 setup: no staging stall could be reserved for R (%)', stg;
    END IF;
    ro1 := ottoq.ottoq_reoptimize_reservation_book(v_run, t);
    SELECT count(*) INTO r_chg1 FROM public.stalls WHERE reserved_by = rr AND stall_type::text IN ('dcfc', 'l2');
    IF COALESCE((ro1->>'swaps')::int, -1) <> 0 OR NOT COALESCE((ro1->>'yields_to_the_line')::boolean, false) OR r_chg1 <> 0 THEN
      RAISE EXCEPTION '0559 V3 FAILED (2): with the dial at 1 the re-optimizer returned % and R holds % charger(s)', ro1, r_chg1;
    END IF;

    -- (3) dial 0: B gets a charger, as before
    PERFORM public.ottoq_policy_set('run', v_run, 'prearrival_charge_yields_to_solver', 0, 'v3_0559');
    res_b := ottoq.ottoq_book_appointment(b, v_run, t, 'low_soc_reserve', 'urgent', false, 20, 30, v_depot);
    SELECT count(*) INTO b_chg FROM public.stalls WHERE reserved_by = b AND stall_type::text IN ('dcfc', 'l2');
    IF COALESCE(res_b->>'stall_type', 'none') NOT IN ('dcfc', 'l2') OR b_chg <> 1 THEN
      RAISE EXCEPTION '0559 V3 FAILED (3): with the dial at 0 the appointment book returned % and B holds % charger(s)', res_b, b_chg;
    END IF;

    -- (4) dial 0: the re-optimizer moves R to a free fast charger, as before
    ro0 := ottoq.ottoq_reoptimize_reservation_book(v_run, t);
    SELECT count(*) INTO r_fast0 FROM public.stalls WHERE reserved_by = rr AND stall_type::text = 'dcfc';
    IF COALESCE((ro0->>'swaps')::int, 0) < 1 OR r_fast0 <> 1 OR (ro0 ? 'yields_to_the_line') THEN
      RAISE EXCEPTION '0559 V3 FAILED (4): with the dial at 0 the re-optimizer returned % and R holds % fast charger(s)', ro0, r_fast0;
    END IF;

    v_pass := format('0559 V3 PASSED on run %s: at dial 1 the appointment book gave A %s with %s fast charger(s) free, and '
                     || 'the re-optimizer upgraded nothing (%s); at dial 0 the appointment book reserved B a %s and the '
                     || 're-optimizer moved R to a fast charger (%s)',
                     v_run, COALESCE(res_a->>'stall_type', 'nothing'), free_fast, ro1, res_b->>'stall_type', ro0);
    RAISE EXCEPTION '%', v_pass;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0559 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0559 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0559_pre' as it is (the appointment book
-- and the reservation re-optimizer as they were).

COMMIT;
