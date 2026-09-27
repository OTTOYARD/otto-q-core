-- 0373  **G235: the recall appointment's staging pick, and the hour's hold the reactor gave its refusal (0502, 0503).**
--
--       Found on validation run `b0fdc92b` (0372 §6): the refusal reactor booked staging holds that nothing ever used.
--       This check follows it to the recall appointment that was refused, measures both halves across every run of
--       the 9 hours before 23:00 UTC on 2026-09-26, and records the rolled-back probe behind 0502 and 0503. Takes the
--       run as a psql variable where one is needed:
--
--           \set run '<sim_run_id>'

-- ══ §1 WHAT THE REACTOR'S REROUTES BECAME, BY WHAT WAS REFUSED ═══════════════════════════════════════════════════

\echo '=== 0373 §1 — refused commands the reactor rerouted, and how the booking it made ended (runs of the last 9 hours) ==='
SELECT c.command_type, (c.payload->>'appointment')::boolean AS appointment, c.reason_code, b.purpose, b.state, count(*) AS n
  FROM public.ottoq_vehicle_commands c
  JOIN public.ottoq_stall_bookings b ON b.booking_id = (c.payload->'reaction'->>'booking_id')::uuid
 WHERE c.status = 'refused' AND c.payload->'reaction'->>'action' = 'rerouted'
   AND c.sim_run_id IN (SELECT sim_run_id FROM public.ottoq_sim_runs WHERE started_at > now() - interval '9 hours')
 GROUP BY 1, 2, 3, 4, 5 ORDER BY 6 DESC;
-- READ (2026-09-26 23:00 UTC, 6:00 PM CT; operator, cert and A/B runs alike):
--     begin_charge                 target_occupied  charge_l2    done        219
--     stage        appointment     target_occupied  temp_hold    released    194
--     proceed_to_stall appointment target_occupied  charge_l2    done        127 / superseded 109 / released 26
--     proceed_to_stall appointment target_occupied  charge_dcfc  done         70 / released 22 / superseded 8
--     begin_charge                 target_occupied  charge_l2    released     14;  charge_dcfc done 12 / released 4
--   Every staging reroute came from a refused recall appointment, and all 194 of its holds were released unused. The
--   charge reroutes were mostly used (`done`: the car charged there). So the leak is the staging half only.
--   (`state` alone reads `released` for both "the window ran out" and "the run stopped"; 191 of the 194 were
--   `window_elapsed`, 3 `run_stopped`.)

-- ══ §2 WHY THE APPOINTMENT WAS REFUSED ════════════════════════════════════════════════════════════════════════════

\echo '=== 0373 §2 — refused staging appointments on the run, with the gate''s reason ==='
SELECT left(c.vehicle_id::text, 8) AS car, c.issued_at, c.reason_code, c.reason_detail,
       (SELECT stall_code FROM public.stalls s WHERE s.id::text = c.payload->>'stall_id') AS stall
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = :'run' AND c.command_type = 'stage' AND c.status = 'refused'
   AND (c.payload->>'appointment')::boolean
 ORDER BY c.issued_at;
-- READ on b0fdc92b: 7, every one `target_occupied` with "calendar booking held by <another car>", on NASH-STG-B010
--   (3), B008 (2), B006 and B007: the first stalls in the appointment pick's own order (temp role first, nearest the
--   entrance). `ottoq.ottoq_book_appointment` picks a staging stall on the pointer and the reservation only, while the
--   gate every command passes (`ottoq.ottoq_validate_assignment`) also refuses another car's live booking. B007's
--   blocker, c9746783, had left the stall three minutes earlier and its hold was still live (G195's staging half),
--   so one leak seeded the other.
--   The appointment is a pointer reservation and nothing more: it books no calendar hold, and on this run the car
--   reached the appointed stall in 30 of 81 appointments the gate accepted (0372 §6(b)).

-- ══ §3 THE PROBE, OLD BODIES AND NEW, ON THE STOPPED RUN ════════════════════════════════════════════════════════
--
--   One transaction ending in RAISE, on b0fdc92b after its stop (sim 16:44:49 UTC). Each case runs in its own
--   rolled-back block under the live bodies, then both bodies as filed are applied inside the transaction and the
--   same cases run again. The 0502 case faults every charger at the depot so the appointment falls to staging, and
--   books another car's live `temp_hold` on the stall the pick takes first. The 0503 case sends two cars `stage` to
--   staging stalls other cars' holds cover, one as a recall appointment and one plain (the control), and runs the
--   reactor.
--
--   Result (run before the applies, at about 6:20 PM CT):
--     pick OLD:    first-in-order NASH-STG-B012 (held by another car) | appointment on NASH-STG-B012 |
--                  stage refused, calendar booking held by 02ff42a9-...
--     reactor OLD: appointment (refused, calendar booking held by 03726c33-...) -> rerouted | reaction holds for its car
--                  1 (temp_hold 60 min) | its refused stall reserved by its car | control (refused) -> rerouted to S024
--     pick NEW:    first-in-order NASH-STG-B012 (held by another car) | appointment on NASH-STG-B011 | stage issued
--     reactor NEW: appointment (refused, ...) -> left_to_arrival | reaction holds for its car 0 | its refused stall
--                  reserved by nobody | control (refused) -> rerouted to S023
--   (The control lands on S023 under the new body because the appointment no longer takes the first free stall.)
--   The two cases are 0502's and 0503's V3, which each migration runs and must pass to apply.
--
--   The probe, verbatim:
--   DO $probe$
--   DECLARE
--     v_run uuid; v_clock timestamptz; v_depot uuid := '11111111-1111-1111-1111-111111111111';
--     v_car uuid; v_other uuid; v_first uuid; v_res jsonb; v_cmd record;
--     v_cars uuid[]; v_stalls uuid[]; v_cmd_app uuid; v_cmd_ctl uuid;
--     v_out text := '';
--   BEGIN
--     SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs r
--      WHERE r.depot_id = v_depot AND r.validation_status IS NULL AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
--      ORDER BY r.started_at DESC LIMIT 1;
--     v_out := 'run ' || left(v_run::text, 8) || ' at ' || v_clock;
--
--     -- the 0502 case: a recall appointment whose first staging stall another car's booking holds
--     BEGIN
--       UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted' WHERE depot_id = v_depot;
--       SELECT v.id INTO v_car FROM public.vehicles v
--        WHERE v.home_depot_id = v_depot AND v.current_stall_id IS NULL ORDER BY v.id LIMIT 1;
--       SELECT v.id INTO v_other FROM public.vehicles v
--        WHERE v.home_depot_id = v_depot AND v.id <> v_car ORDER BY v.id LIMIT 1;
--       SELECT s.id INTO v_first FROM public.stalls s
--        WHERE s.depot_id = v_depot AND s.stall_type = 'staging' AND s.current_vehicle_id IS NULL
--          AND (s.reserved_by IS NULL OR s.reserved_by = v_car OR s.reservation_expires_at <= v_clock)
--        ORDER BY (s.staging_role = 'temp') DESC, s.distance_from_entrance NULLS LAST, s.id LIMIT 1;
--       PERFORM ottoq.ottoq_book_stall(v_run, v_first, v_other, 'temp_hold', v_clock, v_clock + interval '30 minutes',
--                                      NULL, NULL, 'probe_0373');
--       v_res := ottoq.ottoq_book_appointment(v_car, v_run, v_clock, 'probe_0373', 'normal', true, 15, 60, v_depot);
--       SELECT c.status, c.reason_detail, c.payload->>'stall_id' AS stall INTO v_cmd
--         FROM public.ottoq_vehicle_commands c
--        WHERE c.sim_run_id = v_run AND c.vehicle_id = v_car AND c.command_type = 'stage' AND c.issued_at = v_clock
--          AND (c.payload->>'appointment')::boolean
--        ORDER BY c.command_seq DESC LIMIT 1;
--       RAISE EXCEPTION 'pick %: first-in-order % (held by another car) | appointment on % | stage % %',
--         'OLD', (SELECT stall_code FROM public.stalls WHERE id = v_first),
--         (SELECT stall_code FROM public.stalls WHERE id = (v_res->>'stall_id')::uuid), v_cmd.status, COALESCE(v_cmd.reason_detail, '');
--     EXCEPTION WHEN OTHERS THEN v_out := v_out || E'\n' || SQLERRM;
--     END;
--
--     -- the 0503 case: a refused appointment and a refused plain stage (the control), then the reactor
--     BEGIN
--       SELECT array_agg(id ORDER BY id) INTO v_cars
--         FROM (SELECT v.id FROM public.vehicles v WHERE v.home_depot_id = v_depot AND v.current_stall_id IS NULL
--                ORDER BY v.id LIMIT 4) x;
--       SELECT array_agg(id ORDER BY id) INTO v_stalls
--         FROM (SELECT s.id FROM public.stalls s
--                WHERE s.depot_id = v_depot AND s.stall_type = 'staging' AND s.zone <> 'arrival_inspection'
--                  AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
--                ORDER BY s.id LIMIT 2) y;
--       UPDATE public.ottoq_vehicle_commands SET reacted_at = v_clock
--        WHERE sim_run_id = v_run AND status = 'refused' AND reacted_at IS NULL;
--       PERFORM ottoq.ottoq_book_stall(v_run, v_stalls[1], v_cars[3], 'temp_hold', v_clock, v_clock + interval '30 minutes',
--                                      NULL, NULL, 'probe_0373');
--       PERFORM ottoq.ottoq_book_stall(v_run, v_stalls[2], v_cars[4], 'temp_hold', v_clock, v_clock + interval '30 minutes',
--                                      NULL, NULL, 'probe_0373');
--       PERFORM public.ottoq_reserve_stall(v_stalls[1], v_cars[1], v_clock, 3000);
--       PERFORM public.ottoq_reserve_stall(v_stalls[2], v_cars[2], v_clock, 3000);
--       v_cmd_app := ottoq.ottoq_emit_vehicle_command(v_run, v_depot, v_cars[1], 'stage',
--                      jsonb_build_object('stall_id', v_stalls[1], 'stall_type', 'staging', 'appointment', true), v_clock);
--       v_cmd_ctl := ottoq.ottoq_emit_vehicle_command(v_run, v_depot, v_cars[2], 'stage',
--                      jsonb_build_object('stall_id', v_stalls[2], 'stall_type', 'staging'), v_clock);
--       PERFORM ottoq.ottoq_react_to_refusals(v_run, v_depot, v_clock);
--       RAISE EXCEPTION 'reactor %: appointment (%, %) -> % | reaction holds for its car % | its refused stall reserved by % | control (%) -> %',
--         'OLD',
--         (SELECT status FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_app),
--         (SELECT reason_detail FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_app),
--         (SELECT payload->'reaction'->>'action' FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_app),
--         (SELECT count(*) || ' (' || COALESCE(string_agg(DISTINCT purpose || ' ' || round(EXTRACT(epoch FROM upper(during) - lower(during)) / 60) || ' min', ', '), '') || ')'
--            FROM public.ottoq_stall_bookings WHERE sim_run_id = v_run AND vehicle_id = v_cars[1] AND booked_by LIKE 'otto_q_reaction%'),
--         COALESCE((SELECT CASE WHEN reserved_by = v_cars[1] THEN 'its car' ELSE reserved_by::text END FROM public.stalls WHERE id = v_stalls[1]), 'nobody'),
--         (SELECT status FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_ctl),
--         (SELECT (payload->'reaction'->>'action') || ' to ' || COALESCE((SELECT stall_code FROM public.stalls WHERE id::text = payload->'reaction'->>'new_stall_id'), '?')
--            FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_ctl);
--     EXCEPTION WHEN OTHERS THEN v_out := v_out || E'\n' || SQLERRM;
--     END;
--
--     -- the two bodies as filed
--   DECLARE
--     v_def text := pg_get_functiondef('ottoq.ottoq_book_appointment(uuid,uuid,timestamptz,text,text,boolean,numeric,numeric,uuid)'::regprocedure);
--     v_old text := $o$       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= p_clock)
--        ORDER BY (s.staging_role = 'temp') DESC$o$;
--     v_new text := $n$       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= p_clock)
--          /* 0502 (G235): the calendar is a gate too. This pick read the pointer only, so it took a stall another
--             car's live booking held, the gate refused the appointment (7 of 7 staging refusals on b0fdc92b), and the
--             reactor booked the car an hour on a stall it never used. A candidate is now a stall the gate accepts for
--             this car at this moment, the call ottoq_emit_vehicle_command makes next (0467 and 0494 did the same). */
--          AND COALESCE((ottoq.ottoq_validate_assignment(p_vehicle_id, s.id, 'stage', p_clock, p_sim_run_id)->>'ok')::boolean, false)
--        ORDER BY (s.staging_role = 'temp') DESC$n$;
--     n int;
--   BEGIN
--     n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
--     IF n <> 1 THEN RAISE EXCEPTION '0502: the staging pick matched % times, not once', n; END IF;
--     EXECUTE replace(v_def, v_old, v_new);
--   END;
--   DECLARE
--     v_def text := pg_get_functiondef('ottoq.ottoq_react_to_refusals(uuid,uuid,timestamptz)'::regprocedure);
--     v_old text := $o$                                      'by_command_type',v_newer_type,'by_issued_at',v_newer_at);
--
--       ELSIF v_rec.reason_code IN ('target_occupied','resource_faulted')
--          AND v_rec.command_type IN ('proceed_to_stall','begin_charge','stage') THEN
--   $o$;
--     v_new text := $n$                                      'by_command_type',v_newer_type,'by_issued_at',v_newer_at);
--
--       /* 0503 (G235): A REFUSED STAGING APPOINTMENT IS LEFT TO THE CAR'S ARRIVAL. The reroute below booked such a car
--          an hour on another staging stall, and nothing used it: 0 of 194 across every run of the 9 hours to 23:00 UTC
--          on 2026-09-26, because the arrival flow (the inspection seam, the charge step's parking hold) places the car
--          itself and never looks at that hold. The appointment's own reservation on the refused stall goes too: the car
--          is not coming to it. */
--       ELSIF v_rec.command_type = 'stage' AND v_rec.payload->'appointment' = 'true'::jsonb
--          AND v_rec.reason_code IN ('target_occupied','resource_faulted') THEN
--         v_outcome := jsonb_build_object('action','left_to_arrival','reason',v_rec.reason_code);
--         UPDATE public.stalls s
--            SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
--          WHERE s.id = NULLIF(v_rec.payload->>'stall_id','')::uuid
--            AND s.reserved_by = v_rec.vehicle_id
--            AND s.current_vehicle_id IS DISTINCT FROM v_rec.vehicle_id;
--
--       ELSIF v_rec.reason_code IN ('target_occupied','resource_faulted')
--          AND v_rec.command_type IN ('proceed_to_stall','begin_charge','stage') THEN
--   $n$;
--     n int;
--   BEGIN
--     n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
--     IF n <> 1 THEN RAISE EXCEPTION '0503: the reroute branch matched % times, not once', n; END IF;
--     EXECUTE replace(v_def, v_old, v_new);
--   END;
--
--     -- the 0502 case: a recall appointment whose first staging stall another car's booking holds
--     BEGIN
--       UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted' WHERE depot_id = v_depot;
--       SELECT v.id INTO v_car FROM public.vehicles v
--        WHERE v.home_depot_id = v_depot AND v.current_stall_id IS NULL ORDER BY v.id LIMIT 1;
--       SELECT v.id INTO v_other FROM public.vehicles v
--        WHERE v.home_depot_id = v_depot AND v.id <> v_car ORDER BY v.id LIMIT 1;
--       SELECT s.id INTO v_first FROM public.stalls s
--        WHERE s.depot_id = v_depot AND s.stall_type = 'staging' AND s.current_vehicle_id IS NULL
--          AND (s.reserved_by IS NULL OR s.reserved_by = v_car OR s.reservation_expires_at <= v_clock)
--        ORDER BY (s.staging_role = 'temp') DESC, s.distance_from_entrance NULLS LAST, s.id LIMIT 1;
--       PERFORM ottoq.ottoq_book_stall(v_run, v_first, v_other, 'temp_hold', v_clock, v_clock + interval '30 minutes',
--                                      NULL, NULL, 'probe_0373');
--       v_res := ottoq.ottoq_book_appointment(v_car, v_run, v_clock, 'probe_0373', 'normal', true, 15, 60, v_depot);
--       SELECT c.status, c.reason_detail, c.payload->>'stall_id' AS stall INTO v_cmd
--         FROM public.ottoq_vehicle_commands c
--        WHERE c.sim_run_id = v_run AND c.vehicle_id = v_car AND c.command_type = 'stage' AND c.issued_at = v_clock
--          AND (c.payload->>'appointment')::boolean
--        ORDER BY c.command_seq DESC LIMIT 1;
--       RAISE EXCEPTION 'pick %: first-in-order % (held by another car) | appointment on % | stage % %',
--         'NEW', (SELECT stall_code FROM public.stalls WHERE id = v_first),
--         (SELECT stall_code FROM public.stalls WHERE id = (v_res->>'stall_id')::uuid), v_cmd.status, COALESCE(v_cmd.reason_detail, '');
--     EXCEPTION WHEN OTHERS THEN v_out := v_out || E'\n' || SQLERRM;
--     END;
--
--     -- the 0503 case: a refused appointment and a refused plain stage (the control), then the reactor
--     BEGIN
--       SELECT array_agg(id ORDER BY id) INTO v_cars
--         FROM (SELECT v.id FROM public.vehicles v WHERE v.home_depot_id = v_depot AND v.current_stall_id IS NULL
--                ORDER BY v.id LIMIT 4) x;
--       SELECT array_agg(id ORDER BY id) INTO v_stalls
--         FROM (SELECT s.id FROM public.stalls s
--                WHERE s.depot_id = v_depot AND s.stall_type = 'staging' AND s.zone <> 'arrival_inspection'
--                  AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
--                ORDER BY s.id LIMIT 2) y;
--       UPDATE public.ottoq_vehicle_commands SET reacted_at = v_clock
--        WHERE sim_run_id = v_run AND status = 'refused' AND reacted_at IS NULL;
--       PERFORM ottoq.ottoq_book_stall(v_run, v_stalls[1], v_cars[3], 'temp_hold', v_clock, v_clock + interval '30 minutes',
--                                      NULL, NULL, 'probe_0373');
--       PERFORM ottoq.ottoq_book_stall(v_run, v_stalls[2], v_cars[4], 'temp_hold', v_clock, v_clock + interval '30 minutes',
--                                      NULL, NULL, 'probe_0373');
--       PERFORM public.ottoq_reserve_stall(v_stalls[1], v_cars[1], v_clock, 3000);
--       PERFORM public.ottoq_reserve_stall(v_stalls[2], v_cars[2], v_clock, 3000);
--       v_cmd_app := ottoq.ottoq_emit_vehicle_command(v_run, v_depot, v_cars[1], 'stage',
--                      jsonb_build_object('stall_id', v_stalls[1], 'stall_type', 'staging', 'appointment', true), v_clock);
--       v_cmd_ctl := ottoq.ottoq_emit_vehicle_command(v_run, v_depot, v_cars[2], 'stage',
--                      jsonb_build_object('stall_id', v_stalls[2], 'stall_type', 'staging'), v_clock);
--       PERFORM ottoq.ottoq_react_to_refusals(v_run, v_depot, v_clock);
--       RAISE EXCEPTION 'reactor %: appointment (%, %) -> % | reaction holds for its car % | its refused stall reserved by % | control (%) -> %',
--         'NEW',
--         (SELECT status FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_app),
--         (SELECT reason_detail FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_app),
--         (SELECT payload->'reaction'->>'action' FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_app),
--         (SELECT count(*) || ' (' || COALESCE(string_agg(DISTINCT purpose || ' ' || round(EXTRACT(epoch FROM upper(during) - lower(during)) / 60) || ' min', ', '), '') || ')'
--            FROM public.ottoq_stall_bookings WHERE sim_run_id = v_run AND vehicle_id = v_cars[1] AND booked_by LIKE 'otto_q_reaction%'),
--         COALESCE((SELECT CASE WHEN reserved_by = v_cars[1] THEN 'its car' ELSE reserved_by::text END FROM public.stalls WHERE id = v_stalls[1]), 'nobody'),
--         (SELECT status FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_ctl),
--         (SELECT (payload->'reaction'->>'action') || ' to ' || COALESCE((SELECT stall_code FROM public.stalls WHERE id::text = payload->'reaction'->>'new_stall_id'), '?')
--            FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_ctl);
--     EXCEPTION WHEN OTHERS THEN v_out := v_out || E'\n' || SQLERRM;
--     END;
--
--     RAISE EXCEPTION 'PROBE 0373 %', v_out;
--   END $probe$;

-- ══ §4 THE APPLIES, AND THE CANON UNDER THEM ═════════════════════════════════════════════════════════════════════

\echo '=== 0373 §4 — 0502 and 0503 as applied ==='
SELECT m.version, m.name, md5(m.statements[1]) AS stored_md5
  FROM supabase_migrations.schema_migrations m
 WHERE m.name IN ('the_recall_appointment_picks_a_staging_stall_the_gate_accepts',
                  'the_refusal_reactor_leaves_a_refused_staging_appointment_to_the_cars_arrival')
 ORDER BY m.version;
-- READ: 0502 = 20260926232454 (6:24 PM CT), md5 21640289a9b4dd34f4a9bade88fed2d2; 0503 = 20260926232527 (6:25 PM
--   CT), md5 9c529c1bb9cab7a45ebbbaec04d466ae. Each equal to its file's body, each forces_recert TRUE, each dry-run
--   first with its V3 passing. The recert runner's grid_smoke/239001/6 pair (verdict 429) started at 23:25:00 UTC,
--   between the two applies, so it certified under 0502 alone and the column runs again under 0503.

\echo '=== 0373 §4(b) — the canon since 0503, and what moved against its verdict under 0500 ==='
WITH now_v AS (
  SELECT DISTINCT ON (scenario, seed, ticks) verdict_id, scenario, seed, ticks, certified_at, equal, disagreeing_atoms,
         verdict->'arm_a' AS a
    FROM public.ottoq_determinism_verdict_ledger
   WHERE certified_at > '2026-09-26 23:25:27+00'
   ORDER BY scenario, seed, ticks, verdict_id DESC),
before_v AS (
  SELECT DISTINCT ON (scenario, seed, ticks) verdict_id, scenario, seed, ticks, verdict->'arm_a' AS a
    FROM public.ottoq_determinism_verdict_ledger
   WHERE verdict_id BETWEEN 420 AND 428
   ORDER BY scenario, seed, ticks, verdict_id DESC)
SELECT n.scenario || '/' || n.seed || '/' || n.ticks AS col, b.verdict_id AS was, n.verdict_id AS now, n.equal,
       (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(n.a) k
         WHERE (k LIKE 'h\_%' OR k IN ('fp','endst'))
           AND n.a->>k IS DISTINCT FROM b.a->>k) AS moved
  FROM now_v n LEFT JOIN before_v b USING (scenario, seed, ticks)
 ORDER BY 1;
-- READ (2026-09-26 23:55 UTC, 6:55 PM CT): all nine columns passed under 0502 and 0503, verdicts 430-438, the last
--   (busy_day/171717/48) certified at 6:45 PM CT. Against verdicts 420-428 (the canon under 0500/0501):
--     grid_smoke/239001/6 and grid_smoke/424242/6       nothing moved (no recall appointments on a 6-tick smoke run)
--     busy_day/171717/12, /24, /48, normal_day/171717/12  endst, h_bkg, h_cmd, h_evt, h_rule
--     busy_day/314159/12                                 endst, h_cmd, h_evt, h_rule
--     busy_day/424242/12 and /24                         endst, h_bkg, h_cmd, h_dec, h_evt, h_nrg, h_prop, h_rcl,
--                                                        h_rule, h_sdr
--   The shape the two changes predict: bookings, commands and events move where a staging appointment was refused
--   and rerouted, and on seed 424242 the changed placements carry through to decisions, energy, proposals, recalls
--   and service records. 0504 was applied at 6:56 PM CT, after this reading, and re-certifies the canon under it
--   (0374 §4).

-- ══ §5 THE NEXT VALIDATION RUN, PREDICTED BEFORE IT STARTS ══════════════════════════════════════════════════════
--
--   PREDICTED on the next busy_day operator run: (a) no staging appointment refused for another car's live booking
--   (7 on b0fdc92b); (b) no `otto_q_reaction` parking hold (7 on b0fdc92b, 194 across 9 hours); (c) if a staging
--   appointment is still refused (the stall taken between the pick and the gate), its reaction reads `left_to_arrival`
--   and its stall is no longer reserved by the car; (d) the charge reroutes unchanged in kind.
--   (a) and (b) are §2 and 0372 §6(a) read on the new run; (c) is this:

\echo '=== 0373 §5(c) — refused staging appointments on the run and how the reactor answered ==='
SELECT c.reason_code, left(c.reason_detail, 40) AS detail, c.payload->'reaction'->>'action' AS reaction, count(*)
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = :'run' AND c.command_type = 'stage' AND c.status = 'refused'
   AND (c.payload->>'appointment')::boolean
 GROUP BY 1, 2, 3 ORDER BY 4 DESC;
-- READ: pending.
