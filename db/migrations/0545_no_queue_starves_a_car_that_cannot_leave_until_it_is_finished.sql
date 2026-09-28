-- migration-version: 20260928034458
-- migration-name:    no_queue_starves_a_car_that_cannot_leave_until_it_is_finished
--
-- 0545  **No queue starves a car that cannot leave until it is finished. The readiness gate times a car only while it
--        waits, a bay seat goes to the most overdue car first, and a charger goes to the car with the highest response
--        ratio, so a top-off is not stuck behind every lower car.**
--
-- ══ §1 WHY (validation run 9eab647f, check 0402; CLAUDE.md rule 9; G269, G270, G271) ══════════════════════════════
--
--   Rule 9 makes every service a car needs required, so a car is held until it is finished (0543), and the first day
--   under it held: 112 departures, none unfinished, none below 99%. Holding changes what the queues are for. Each one
--   below was built for a depot that could release a car short, and each one starved some car once it could not.
--
--   G269, the gate's clock runs while the car is being served. The readiness gate stamps `held_since` the first time it
--   holds a car and keeps the stamp while the car goes to its remedy, so the time a car spends on a charger or in a bay
--   counts as time held. Tesla-AV-061 came in at 18%, was held at 5:39 AM CT (sim), charged on an L2 for 4 h 46 min,
--   and came back to the gate at 100% at 10:25 AM with its charge step closing that same tick. The gate read 285.8
--   minutes held, past the 240-minute hard cap, and escalated it to a person (`twin.deploy_gate_escalated`, critical)
--   for a car that had been served the whole time. It left at 100% with everything done two minutes later. The
--   45-minute patience flag (`deploy_gate_stuck`) reads the same clock.
--
--   G270, a bay seat goes to the car whose work "fits its window" before the car that is late. The decide tick's bay
--   admission (4b) seats cars by urgency, resumption, then `fits_window DESC`, then deploy time (`minutes_to_deploy`),
--   then shortest job. The needs card's `fits_window` is false for every car past its deploy time, because no work fits
--   a window that has closed. That rule was right when unfinished work could be left for later; under rule 9 it sorts
--   the latest cars last. Of the day's 32 needs-card seats, 15 went to cars due out 47 to 758 minutes later and 10 to
--   cars with no deploy time, against 7 to cars already late. Three cars were escalated after 240 minutes at 100%
--   waiting for a deep clean, 37 to 386 minutes past their deploy time, and none was seated before the teardown.
--
--   G271, the charge cursor serves the lowest charge first. `ottoq_decide_tick`'s stall-assignment cursor orders by
--   immediate dispatch, then (OTTO-Q's seat) `current_soc ASC`. That was right while a car could leave at the 80%
--   floor: the low car could not go and the 90% car could. Under 0539 every car charges to 100% and under 0543 none
--   leaves short, so the 90% car cannot go either, and it is the cheapest car to finish. With cars arriving at 43-49%
--   all day and every fast charger busy, nine cars sat on `need_charge` at 91-98% from the boot to the teardown, their
--   charge never moving: about 80 car-hours idle against 126.4 deployed.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The gate times a hold from the later of its stamp and the car's `last_state_change`. The gate never touches
--       `last_state_change` (it holds a car in `staged_awaiting_service` and changes only its step), and in a twin run
--       the column is on the sim clock (0057, 0061, 0256). So a car held the whole time keeps its first stamp and a
--       car that went to a charger or a bay and came back is timed from its return. A car that waits past the hard cap
--       for a charger or a bay that never frees is still escalated: that is the capacity finding the cap exists for.
--   (b) The bay admission seats the most overdue car first. `fits_window` leaves both of (4b)'s orderings (the seat
--       rank and the cursor), so seats go by urgency, resumption, then earliest deploy time, then shortest job. Earliest
--       deadline first is the order that keeps the latest car least late when every car must be finished.
--   (c) The charge cursor, on OTTO-Q's seat, takes the car with the highest response ratio first: (minutes it has
--       waited in its state + points it needs to its target) / points it needs. A top-off goes near the front, since
--       its ratio climbs fastest, and every waiting car's ratio rises the longer it waits, so no car starves. Waiting
--       is measured from `last_state_change`, as in (a), and the target is `ottoq_effective_target_soc_at` (0539's one
--       answer). Immediate dispatch still goes first, and the baseline seats (FIFO, greedy) keep their own keys: the
--       ratio is NULL for them and sorts nothing.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   Every arm runs the gate, the bay admission and the charge cursor: seat order, charger order, holds, flags and
--   escalations can move.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - Capacity. Wash and detail share one lane, LEAST(cleaning staff, wash supervisors) = 2 seats on 3 wash bays, and
--     every fast charger was busy through the day. Ordering decides who waits; it does not shorten the wait. That is a
--     capacity finding for the depot, reported with the run.
--   - The charge-wait KPI (`ottoq_kpi_charge_wait`) counts visits, so a car waiting for a charger with no visit on record
--     is invisible to it: eight of G271's nine. Check 0403 measures the cursor's waits from the state stream instead.
--   - The inspection seam (`ottoq.ottoq_enact_inspection_seam`) still takes only a car whose work fits its window into
--     the arrival-inspection lane. The in-place starter performs an overdue car's inspection where it is parked.
--   - A car's `flagged_issue` outlives its hold (the gate's release drops `deploy_gate` and keeps the flag); G208/G218.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0545 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: each function is the one measured (md5 of its source, 2026-09-28 03:08 UTC) ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)', '426dffc4d80e552cc69db737c724ff97'),
      ('public.ottoq_decide_tick(uuid)',                                                  'bdc29f3cfb77b7828bea907c8c2c1f24')
    ) AS t(sig, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) <> r.want THEN
      RAISE EXCEPTION '0545 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0545_pre', 'function', f.sch, f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('twin',   'ottoq_sim_advance_service_flow', 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'),
               ('public', 'ottoq_decide_tick',              'public.ottoq_decide_tick(uuid)')
       ) AS f(sch, obj, sig);

-- ── (a) the gate times a hold from the car's return ──
DO $gate$
DECLARE v_def text; n int;
  c_old CONSTANT text := $o$                             THEN COALESCE((v_rec.config #>> '{deploy_gate,held_since}')::timestamptz, p_sim_clock_now)$o$;
  c_new CONSTANT text := $n$                             -- 0545 (G269): from the later of the stamp and the car's last state change. A car that
                             -- went to its charger or bay and came back is timed from its return, not from its first
                             -- hold: time being served is not time held. The gate never moves last_state_change.
                             THEN GREATEST(COALESCE((v_rec.config #>> '{deploy_gate,held_since}')::timestamptz, p_sim_clock_now),
                                           COALESCE(v_rec.last_state_change, '-infinity'::timestamptz))$n$;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0545 gate: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $gate$;

-- ── (b) the bay admission seats the most overdue car first ──
DO $seats$
DECLARE v_def text; n int;
  c_pat CONSTANT text := $p$,(\s*)rk\.fits_window DESC NULLS LAST,$p$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  n := (SELECT count(*) FROM regexp_matches(v_def, c_pat, 'g'));
  IF n <> 2 THEN RAISE EXCEPTION '0545 seats: fits_window is in % orderings, not 2', n; END IF;
  -- both orderings keep every other key in place: urgency, resumption, deploy time, shortest job, vehicle id
  v_def := regexp_replace(v_def, c_pat, ',', 'g');
  n := (length(v_def) - length(replace(v_def, '--                      2. fits_window DESC  — do not burn a scarce bay on work that', '')))
       / length('--                      2. fits_window DESC  — do not burn a scarce bay on work that');
  IF n <> 1 THEN RAISE EXCEPTION '0545 seats: the ordering comment matches % times, not 1', n; END IF;
  v_def := replace(v_def, '--                      2. fits_window DESC  — do not burn a scarce bay on work that',
                   '--                      2. (0545, G270: fits_window left this ordering. Under rule 9 no car leaves'
                   || E'\n  --                         unfinished, and a car past its deploy time never "fits", so it sorted'
                   || E'\n  --                         the latest cars last. Earliest deadline first below.) Was: do not burn a scarce bay on work that');
  EXECUTE v_def;
END $seats$;

-- ── (c) the charge cursor serves the highest response ratio first on OTTO-Q's seat ──
DO $charge$
DECLARE v_def text; n int;
  c_old CONSTANT text := E'              CASE WHEN v_seat = 2 THEN v.current_soc END ASC,\n              v.current_soc ASC, v.id';
  c_new CONSTANT text := E'              CASE WHEN v_seat = 2 THEN v.current_soc END ASC,\n'
    || E'              /* 0545 (G271, CLAUDE.md rule 9): OTTO-Q''s seat takes the highest response ratio first, (minutes\n'
    || E'                 waited in this state + points to charge) / points to charge. Lowest charge first starved a car that\n'
    || E'                 needed only a top-off to 100%, which rule 9 keeps until it is full: nine cars sat the whole day at\n'
    || E'                 91-98% on 9eab647f. The ratio rises for every car the longer it waits, so none starves. NULL for\n'
    || E'                 the baseline seats, which keep their own keys above. */\n'
    || E'              CASE WHEN v_seat = 0 THEN\n'
    || E'                (GREATEST(EXTRACT(EPOCH FROM (v_clock - v.last_state_change)) / 60.0, 0)\n'
    || E'                 + GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1))\n'
    || E'                / GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1)\n'
    || E'              END DESC NULLS LAST,\n'
    || E'              v.current_soc ASC, v.id';
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0545 charge: the cursor''s order matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $charge$;

-- ── V1 (comment-stripped): the gate's clock, the seat order and the charger order are what §2 says ──
DO $verify$
DECLARE v_src text;
BEGIN
  v_src := regexp_replace(regexp_replace(
             pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF v_src !~ 'GREATEST\(COALESCE\(\(v_rec\.config #>> ''\{deploy_gate,held_since\}''\)::timestamptz, p_sim_clock_now\),\s+COALESCE\(v_rec\.last_state_change, ''-infinity''::timestamptz\)\)' THEN
    RAISE EXCEPTION '0545 V1: the gate does not time a hold from the car''s return';
  END IF;
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF v_src ~ 'rk\.fits_window\s+DESC' THEN
    RAISE EXCEPTION '0545 V1: the bay admission still orders by fits_window';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src, 'rk\.is_resume DESC,\s*rk\.minutes_to_deploy ASC NULLS LAST,\s*rk\.open_must_do_min ASC NULLS LAST,\s*rk\.vehicle_id', 'g')) <> 2 THEN
    RAISE EXCEPTION '0545 V1: the two orderings are not urgency, resumption, deploy time, shortest job, vehicle id';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'CASE WHEN v_seat = 2 THEN v\.current_soc END ASC,\s*CASE WHEN v_seat = 0 THEN\s*\(GREATEST\(EXTRACT\(EPOCH FROM \(v_clock - v\.last_state_change\)\) / 60\.0, 0\)\s*\+ GREATEST\(public\.ottoq_effective_target_soc_at\(v\.id, v_clock\) - v\.current_soc, 1\)\)\s*/ GREATEST\(public\.ottoq_effective_target_soc_at\(v\.id, v_clock\) - v\.current_soc, 1\)\s*END DESC NULLS LAST,\s*v\.current_soc ASC, v\.id', 'g')) <> 1 THEN
    RAISE EXCEPTION '0545 V1: the charge cursor does not take the highest response ratio first on OTTO-Q''s seat';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0545_no_queue_starves_a_car_that_cannot_leave_until_it_is_finished', true, true,
  'G269: the readiness gate times a hold from the later of its stamp and the car''s last state change, so time on a '
  'charger or in a bay no longer counts toward the patience flag and the hard-cap escalation. G270: the bay admission '
  '(4b) drops fits_window from its orderings, so seats go by urgency, resumption, earliest deploy time, shortest job. '
  'G271: the charge cursor, on OTTO-Q''s seat, takes the highest response ratio first ((minutes waited + points to '
  'charge) / points to charge) instead of the lowest charge. Every arm runs all three.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the ended validation run 9eab647f (its cars and visits are still on record): two cars at 100% held
--   at the gate for an open deep clean, both stamped 300 minutes ago. One has been here the whole time; the other came
--   back from a bay 10 minutes ago. One pass of the service flow escalates the first (held 300) and times the second
--   from its return (held 10), with no escalation.
DO $v3$
DECLARE
  v_msg text; v_run uuid := '9eab647f-01ae-4c32-92eb-a9803f1397af'; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_clock timestamptz; v_cars uuid[]; c1 uuid; c2 uuid; h1 numeric; h2 numeric; e1 int; e2 int;
BEGIN
  BEGIN
    SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    IF v_clock IS NULL THEN RAISE EXCEPTION '0545 V3: run % is gone; point V3 at a run that exists', v_run; END IF;
    SELECT array_agg(id ORDER BY id) INTO v_cars FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_twin AND v.category = 'autonomous'
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d
                          WHERE d.vehicle_id = v.id AND d.sim_run_id = v_run AND d.status IN ('active', 'returning'))
         AND NOT public.ottoq_vehicle_is_tethered(v.id, v_clock)
       ORDER BY v.id LIMIT 2) q;
    IF coalesce(array_length(v_cars, 1), 0) < 2 THEN RAISE EXCEPTION '0545 V3: fewer than two free twin cars'; END IF;
    c1 := v_cars[1]; c2 := v_cars[2];
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (v_cars) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status)
    SELECT c, v_run, v_twin, v_clock - interval '360 minutes', '0545_v3_' || c::text,
           '[{"svc":"interior_deep_clean","must_do":true,"status":"pending","concurrency":"bay","requires_bay":"wash_bay"}]'::jsonb,
           'open'
      FROM unnest(v_cars) c;
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state, current_soc = 100,
           last_state_change = CASE WHEN id = c1 THEN v_clock - interval '300 minutes' ELSE v_clock - interval '10 minutes' END,
           config = (COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type')
                    || jsonb_build_object('svc_step', 'need_deploy',
                         'deploy_gate', jsonb_build_object('run', v_run, 'held_since', v_clock - interval '300 minutes'))
     WHERE id = ANY (v_cars);

    SELECT count(*) FILTER (WHERE entity_id = c1), count(*) FILTER (WHERE entity_id = c2) INTO e1, e2
      FROM public.ottoq_events WHERE sim_run_id = v_run AND event_type = 'twin.deploy_gate_escalated'
       AND entity_id = ANY (v_cars);

    -- the service flow carries no search_path of its own and runs under its caller's (the world tick sets
    -- twin, ottoq, public, extensions); set the same here, local to this rolled-back block
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);
    PERFORM twin.ottoq_sim_advance_service_flow(v_run, v_clock, 30, v_twin);

    SELECT (config #>> '{deploy_gate,held_min}')::numeric INTO h1 FROM public.vehicles WHERE id = c1;
    SELECT (config #>> '{deploy_gate,held_min}')::numeric INTO h2 FROM public.vehicles WHERE id = c2;
    -- escalations this pass raised: after minus before
    SELECT count(*) FILTER (WHERE entity_id = c1) - e1, count(*) FILTER (WHERE entity_id = c2) - e2 INTO e1, e2
      FROM public.ottoq_events WHERE sim_run_id = v_run AND event_type = 'twin.deploy_gate_escalated'
       AND entity_id = ANY (v_cars);
    IF h1 IS DISTINCT FROM 300.0 OR e1 <> 1 OR h2 IS DISTINCT FROM 10.0 OR e2 <> 0 THEN
      RAISE EXCEPTION '0545 V3 FAILED: held the whole time % min (% escalation), back from a bay % min (% escalation)',
        h1, e1, h2, e2;
    END IF;

    RAISE EXCEPTION '0545 V3 PASSED: a car held the whole time read % min and was escalated (%); a car back from a bay 10 minutes ago read % min and was not (%)',
      h1, e1, h2, e2;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0545 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0545 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the two `definition`s in ottoq_schema_snapshots WHERE label = '0545_pre' as they are.
COMMIT;
