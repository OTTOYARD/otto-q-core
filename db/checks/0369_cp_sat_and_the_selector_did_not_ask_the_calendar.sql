-- 0369  **G229: CP-SAT and the proposal selector did not ask the calendar the gate refuses on.**
--
--       Found on validation run `394e1e83` (0368 §10): 3 of the 24 `begin_charge` the gate refused were CP-SAT
--       (`forward_lex`) proposals. This check records why (§1), the rolled-back probes behind 0498 and 0499 (§2, §3),
--       and the canon under 0499 (§4). §1 takes the run as a psql variable:
--
--           \set run '394e1e83-f835-44a1-9c9f-7921c44af8c5'
--
--       The gate (`ottoq.ottoq_validate_assignment`) asks four things of a charger for `begin_charge`: the pointer, the
--       reservation, the charger's state, and last whether ANOTHER vehicle's held, active, done or interrupted booking
--       covers the clock. The decision frame's `offerable` (what CP-SAT plans onto) and the proposal selector
--       (`public.ottoq_l2_external_proposal`, what the charge step asks first) each asked the first three and not the
--       calendar.

-- ══ §1 THE THREE REFUSALS AND WHAT HELD THE CHARGER ════════════════════════════════════════════════════════════════

\echo '=== 0369 §1 — forward_lex begin_charge refused at the gate, with the booking that refused it ==='
WITH r AS (
  SELECT c.vehicle_id, c.issued_at, c.payload->>'stall_id' AS stall_id, c.reason_code, c.reason_detail
    FROM public.ottoq_vehicle_commands c
   WHERE c.sim_run_id = :'run' AND c.command_type = 'begin_charge' AND c.status = 'refused'
     AND c.confirmed_by = 'otto_q_preflight' AND NOT (c.payload ? 'reroute_reason'))
SELECT left(r.vehicle_id::text, 8) AS car, r.issued_at, left(r.stall_id, 8) AS stall, r.reason_detail,
       (SELECT string_agg(left(b.vehicle_id::text, 8) || ' ' || b.purpose || ' [' || to_char(lower(b.during), 'HH24:MI:SS')
                          || ', ' || to_char(upper(b.during), 'HH24:MI:SS') || ') booked at sim '
                          || to_char(b.booked_at_sim, 'HH24:MI:SS'), ' | ')
          FROM public.ottoq_stall_bookings b
         WHERE b.sim_run_id = :'run' AND b.stall_id::text = r.stall_id AND b.vehicle_id <> r.vehicle_id
           AND b.during @> r.issued_at) AS covering_booking,
       (SELECT to_char(min(o.started_at), 'HH24:MI:SS') FROM public.ocpp_sessions o
         WHERE o.sim_run_id = :'run' AND o.stall_id::text = r.stall_id AND o.started_at >= r.issued_at) AS next_plug_in
  FROM r
  JOIN LATERAL (SELECT 1 FROM public.ottoq_decisions d
                 WHERE d.sim_run_id = :'run' AND d.entity_id = r.vehicle_id AND d.sim_clock = r.issued_at
                   AND d.resolved_action_context = 'stall_assignment' AND d.proposed_action->>'stall_id' = r.stall_id
                   AND COALESCE(d.proposed_action->>'l2_engine', d.proposed_action->'rationale'->>'optimizer') = 'forward_lex'
                 LIMIT 1) fl ON true
 ORDER BY r.issued_at, r.vehicle_id;
-- READ (21:00 UTC, after the stop; times are sim, UTC; the run's sim day is CDT, so 13:35 UTC is 8:35 AM):
--   2d2c46af  13:35:51  L2 d01cc4ff  calendar booking held by 28417bea  28417bea charge_l2 [13:04:41, 15:18:35) booked 13:03:22  next plug-in 13:37:12
--   2d2c46af  13:36:42  L2 d01cc4ff  calendar booking held by 28417bea  (the same booking)                                            13:37:12
--   bbf2928f  13:36:42  L2 d01cc4ff  calendar booking held by 28417bea  (the same booking)                                            13:37:12
--   All three are one charger promised to one car: 28417bea's charge booking covered 8:04-10:18 AM from the tick
--   before its window, the car plugged in at 8:37 (its session, 50bc1f67, ran to 10:44 and faulted), and in the half
--   hour between, the stall's pointer was empty, its charger Available and answering and its reservation free. So the
--   frame said `offerable`, CP-SAT planned two other cars onto it, the selector handed both proposals on, and the gate
--   refused each on the calendar. The reactor found no other L2 free ("no_capacity, candidates_seen 0"), so nothing
--   was lost but the two refused commands; the booking was right and the proposals were wrong.
--   The booking's own row reads `done / window_elapsed_occupied` at the stop: it was closed at its window's end with
--   the car still on the stall (G81's overstay). Which state it was in at 8:35 is not recorded; the gate counts held,
--   active, done and interrupted alike.

-- ══ §2 0498: THE FRAME ASKS THE CALENDAR (rolled-back probe, old body then new) ════════════════════════════════════
--
--   On the newest run whose frame carries the facts (`394e1e83`, `proposer_frame_facts` = 1), at its clock: one charger
--   made clean (free, Available, answering, no booking covering the clock), promised to car B by a charge booking
--   covering the clock, and asked about for car A. The old body, then 0498's patch as filed, then the new body, in one
--   transaction that ends in an exception. Run at 21:04 UTC (4:04 PM CT), before the apply:
--     run 394e1e83 at 16:52:11 UTC, dcfc 0c916ac0, car B=00cc3d0a promised it, car A=02ff42a9 asks
--     OLD frame before the promise: offerable=true | after: offerable=true, calendar_held_by present=f, facts_version=3
--     gate for A after the promise: {"ok": false, "code": "target_occupied",
--                                    "detail": "calendar booking held by 00cc3d0a-...", "blocker_vehicle_id": "00cc3d0a-..."}
--     NEW frame after the promise: offerable=false, calendar_held_by=00cc3d0a, facts_version=4
--     gate for A: the same refusal
--     facts-off frame (a certification arm's) stalls carrying either key: 0
--   So the old frame offered a charger the gate refuses, and the new one names the car that holds it. The same probe
--   runs inside 0498 as V3 and must pass for the migration to apply.
--   0498 = 20260926210609 (4:06 PM CT), stored statement md5 6092a318..., equal to the file's body; forces_recert FALSE
--   (the facts block is off for every certification arm, and no atom reads `ottoq_decision_snapshots`).
--
--   The probe as run (the patch block between the two is 0498's `$patch$` verbatim and is not repeated here):
--   DO $probe_old$
--   DECLARE
--     v_run uuid; v_depot uuid; v_clk timestamptz;
--     v_stall uuid; v_type text; v_b uuid; v_a uuid; v_st0 jsonb; v_st1 jsonb; v_gate jsonb;
--   BEGIN
--     SELECT r.sim_run_id, r.depot_id, r.sim_clock_current INTO v_run, v_depot, v_clk
--       FROM public.ottoq_sim_runs r
--      WHERE r.sim_clock_current IS NOT NULL AND r.depot_id IS NOT NULL
--        AND COALESCE(public.ottoq_policy_get(r.sim_run_id, 'proposer_frame_facts', 0), 0) >= 1
--      ORDER BY r.started_at DESC LIMIT 1;
--     SELECT s.id, s.stall_type::text INTO v_stall, v_type
--       FROM public.stalls s
--      WHERE s.depot_id = v_depot AND s.stall_type::text IN ('dcfc','l2') AND s.ocpp_charger_id IS NOT NULL
--      ORDER BY s.id LIMIT 1;
--     SELECT v.id INTO v_b FROM public.vehicles v
--      WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS DISTINCT FROM v_stall
--      ORDER BY v.id LIMIT 1;
--     SELECT v.id INTO v_a FROM public.vehicles v
--      WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.id <> v_b
--        AND v.current_stall_id IS DISTINCT FROM v_stall
--        AND v.current_state::text NOT IN ('tow_requested','out_of_service')
--      ORDER BY v.id LIMIT 1;
--     -- one clean charger at the run's clock: free, Available, answering, no booking covering the clock
--     UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL, status = 'available'
--      WHERE id = v_stall;
--     UPDATE public.ottoq_ocpp_chargers c SET station_state = 'Available', last_heartbeat_at = v_clk
--       FROM public.stalls s WHERE s.id = v_stall AND c.charger_id = s.ocpp_charger_id;
--     DELETE FROM public.ottoq_stall_bookings b
--      WHERE b.sim_run_id = v_run AND b.stall_id = v_stall AND b.during @> v_clk AND b.state IN ('held','active','done','interrupted');
--     SELECT s INTO v_st0 FROM jsonb_array_elements(public.ottoq_build_decision_frame(v_depot, v_run)->'stalls') s WHERE (s->>'id')::uuid = v_stall;
--     -- the promise: car B's charge booking on that charger, covering the clock
--     PERFORM ottoq.ottoq_book_stall(v_run, v_stall, v_b, 'charge_' || v_type, v_clk - interval '5 minutes',
--                                    v_clk + interval '30 minutes', NULL, NULL, 'otto_q');
--     SELECT s INTO v_st1 FROM jsonb_array_elements(public.ottoq_build_decision_frame(v_depot, v_run)->'stalls') s WHERE (s->>'id')::uuid = v_stall;
--     v_gate := ottoq.ottoq_validate_assignment(v_a, v_stall, 'begin_charge', v_clk, v_run);
--     PERFORM set_config('probe0498.ctx', jsonb_build_object('run', v_run, 'depot', v_depot, 'clk', v_clk, 'stall', v_stall,
--                        'type', v_type, 'a', v_a, 'b', v_b)::text, true);
--     PERFORM set_config('probe0498.old', format(E'run %s at %s, %s %s, car B=%s promised it, car A=%s asks\n OLD frame before the promise: offerable=%s | after: offerable=%s, calendar_held_by present=%s, facts_version=%s\n gate for A after the promise: %s',
--         left(v_run::text, 8), v_clk, v_type, left(v_stall::text, 8), left(v_b::text, 8), left(v_a::text, 8),
--         v_st0->>'offerable', v_st1->>'offerable', (v_st1 ? 'calendar_held_by'),
--         public.ottoq_build_decision_frame(v_depot, v_run)->'selector'->>'facts_version', v_gate), true);
--   END $probe_old$;
--
--   -- 0498's $patch$ block, verbatim from the migration
--
--   DO $probe_new$
--   DECLARE
--     c jsonb := current_setting('probe0498.ctx')::jsonb;
--     v_st jsonb; v_gate jsonb; v_frame jsonb; v_other int;
--   BEGIN
--     v_frame := public.ottoq_build_decision_frame((c->>'depot')::uuid, (c->>'run')::uuid);
--     SELECT s INTO v_st FROM jsonb_array_elements(v_frame->'stalls') s WHERE s->>'id' = c->>'stall';
--     v_gate := ottoq.ottoq_validate_assignment((c->>'a')::uuid, (c->>'stall')::uuid, 'begin_charge', (c->>'clk')::timestamptz, (c->>'run')::uuid);
--     -- and the facts-off frame a certification arm builds carries neither key
--     SELECT count(*) INTO v_other FROM jsonb_array_elements(public.ottoq_build_decision_frame((c->>'depot')::uuid, NULL)->'stalls') s
--      WHERE s ? 'calendar_held_by' OR s ? 'offerable';
--     RAISE EXCEPTION E'PROBE0498\n %\n NEW frame after the promise: offerable=%, calendar_held_by=%, facts_version=%\n gate for A: %\n facts-off frame stalls carrying either key: %',
--       current_setting('probe0498.old'), v_st->>'offerable', left(v_st->>'calendar_held_by', 8), v_frame->'selector'->>'facts_version',
--       v_gate, v_other;
--   END $probe_new$;
--
--   A first version of this probe picked a charger the frame already offered at the run's clock and found none: the
--   canon arms that ran after `394e1e83` stopped re-stamped the shared chargers' heartbeats on their own sim clocks, so
--   against the stopped run's clock every charger read stale. 0498's V3 had the same premise and would have skipped
--   silently (its NOTICE is not shown by the SQL runner), so both now make the charger clean first and V3 raises
--   instead of skipping.

-- ══ §3 0499: THE SELECTOR ASKS THE CALENDAR (rolled-back probe, old body then new) ══════════════════════════════════
--
--   The same clean charger on the newest operator run, a pending `forward_lex` proposal for car A on it, then the
--   charger promised to car B. Run at 21:08 UTC (4:08 PM CT), before the apply:
--     run 394e1e83 at 16:52:11 UTC, dcfc 0c916ac0, forward_lex proposal for A=02ff42a9, then promised to B=00cc3d0a
--     OLD selector for A: before the promise 0c916ac0 | after 0c916ac0
--     gate for A after the promise: calendar booking held by 00cc3d0a-2518-446b-b9b7-e025e293e37b
--     NEW selector for A after the promise: nothing (passed over)
--   0499's V3 also checks that B's own proposal for the charger B holds is still handed on (the gate excludes the
--   car's own booking, and so does the selector).
--   0499 = 20260926210943 (4:09 PM CT), stored statement md5 3343cf0c..., equal to the file's body; forces_recert TRUE.
--
--   The probe as run:
--   DO $probe_old$
--   DECLARE
--     v_run uuid; v_depot uuid; v_clk timestamptz; v_stall uuid; v_type text; v_a uuid; v_b uuid;
--     v_before jsonb; v_after jsonb;
--   BEGIN
--     SELECT r.sim_run_id, r.depot_id, r.sim_clock_current INTO v_run, v_depot, v_clk
--       FROM public.ottoq_sim_runs r
--      WHERE r.sim_clock_current IS NOT NULL AND r.depot_id IS NOT NULL AND r.validation_status IS NULL
--      ORDER BY r.started_at DESC LIMIT 1;
--     SELECT s.id, s.stall_type::text INTO v_stall, v_type FROM public.stalls s
--      WHERE s.depot_id = v_depot AND s.stall_type::text IN ('dcfc','l2') AND s.ocpp_charger_id IS NOT NULL ORDER BY s.id LIMIT 1;
--     SELECT v.id INTO v_b FROM public.vehicles v
--      WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS DISTINCT FROM v_stall ORDER BY v.id LIMIT 1;
--     SELECT v.id INTO v_a FROM public.vehicles v
--      WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.id <> v_b AND v.current_stall_id IS DISTINCT FROM v_stall
--        AND v.current_state::text NOT IN ('tow_requested','out_of_service') ORDER BY v.id LIMIT 1;
--     UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL, status = 'available' WHERE id = v_stall;
--     UPDATE public.ottoq_ocpp_chargers c SET station_state = 'Available', last_heartbeat_at = v_clk
--       FROM public.stalls s WHERE s.id = v_stall AND c.charger_id = s.ocpp_charger_id;
--     DELETE FROM public.ottoq_stall_bookings b
--      WHERE b.sim_run_id = v_run AND b.stall_id = v_stall AND b.during @> v_clk AND b.state IN ('held','active','done','interrupted');
--     DELETE FROM public.ottoq_external_proposals p
--      WHERE p.sim_run_id = v_run AND p.action_context = 'stall_assignment' AND p.entity_id IN (v_a, v_b);
--     INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal, source)
--     VALUES (v_run, v_depot, 'stall_assignment', 'vehicle', v_a,
--             jsonb_build_object('verb','assign_stall','stall_id', v_stall, 'stall_type', v_type, 'abstain', false), 'forward_lex');
--     v_before := public.ottoq_l2_external_proposal(v_run, 'stall_assignment', 'vehicle', v_a);
--     PERFORM ottoq.ottoq_book_stall(v_run, v_stall, v_b, 'charge_' || v_type, v_clk - interval '5 minutes',
--                                    v_clk + interval '30 minutes', NULL, NULL, 'otto_q');
--     v_after := public.ottoq_l2_external_proposal(v_run, 'stall_assignment', 'vehicle', v_a);
--     PERFORM set_config('probe0499.ctx', jsonb_build_object('run', v_run, 'stall', v_stall, 'a', v_a, 'b', v_b, 'clk', v_clk)::text, true);
--     PERFORM set_config('probe0499.old', format(E'run %s at %s, %s %s, forward_lex proposal for A=%s, then promised to B=%s\n OLD selector for A: before the promise %s | after %s\n gate for A after the promise: %s',
--         left(v_run::text, 8), v_clk, v_type, left(v_stall::text, 8), left(v_a::text, 8), left(v_b::text, 8),
--         COALESCE(left(v_before->>'stall_id', 8), 'nothing'), COALESCE(left(v_after->>'stall_id', 8), 'nothing'),
--         ottoq.ottoq_validate_assignment(v_a, v_stall, 'begin_charge', v_clk, v_run)->>'detail'), true);
--   END $probe_old$;
--
--   -- 0499's $patch$ block, verbatim from the migration
--
--   DO $probe_new$
--   DECLARE
--     c jsonb := current_setting('probe0499.ctx')::jsonb;
--     v_after jsonb;
--   BEGIN
--     v_after := public.ottoq_l2_external_proposal((c->>'run')::uuid, 'stall_assignment', 'vehicle', (c->>'a')::uuid);
--     RAISE EXCEPTION E'PROBE0499\n %\n NEW selector for A after the promise: %',
--       current_setting('probe0499.old'), COALESCE(left(v_after->>'stall_id', 8), 'nothing (passed over)');
--   END $probe_new$;

-- ══ §4 THE CANON UNDER 0499 ═════════════════════════════════════════════════════════════════════════════════════════
--
--   PREDICTED: 9 of 9 pass, and no digest moves from the column's verdict under 0495 (402-410), because under 0495 no
--   arm had a `begin_charge` of the charge step's refused at the gate, so no proposal the selector handed on was one
--   the gate refused.

\echo '=== 0369 §4 — the canon under 0499: each column''s verdict, and which of its arm A digests moved from 0495''s ==='
WITH v AS (
  SELECT l.verdict_id, l.scenario || '/' || l.seed || '/' || l.ticks AS col, l.outcome, l.disagreeing_atoms,
         l.verdict->'arm_a' AS a, l.certified_at
    FROM public.ottoq_determinism_verdict_ledger l
   WHERE l.verdict_id BETWEEN 402 AND 410 OR l.certified_at > '2026-09-26 21:09:43+00'),
k(key) AS (VALUES ('fp'),('boot'),('endst'),('ticks'),('h_bkg'),('h_cal'),('h_cmd'),('h_dec'),('h_defr'),('h_evt'),
                  ('h_nrg'),('h_prop'),('h_rcl'),('h_rule'),('h_sdr'))
SELECT n.col, o.verdict_id AS under_0495, n.verdict_id AS under_0499, n.outcome, n.disagreeing_atoms,
       COALESCE(array_agg(k.key ORDER BY k.key) FILTER (WHERE o.a->k.key IS DISTINCT FROM n.a->k.key), '{}') AS moved
  FROM v n
  JOIN v o ON o.col = n.col AND o.verdict_id BETWEEN 402 AND 410
  CROSS JOIN k
 WHERE n.verdict_id > 410
 GROUP BY n.col, o.verdict_id, n.verdict_id, n.outcome, n.disagreeing_atoms
 ORDER BY n.verdict_id;
-- READ (21:38 UTC, 4:38 PM CT): the canon re-certified 9 of 9 under 0499, each column on its first attempt:
--     grid_smoke/239001/6    402 -> 411  passed  moved {}
--     grid_smoke/424242/6    403 -> 412  passed  moved {}
--     busy_day/171717/12     404 -> 413  passed  moved {}
--     busy_day/314159/12     405 -> 414  passed  moved {}
--     busy_day/424242/12     406 -> 415  passed  moved {}
--     normal_day/171717/12   407 -> 416  passed  moved {}
--     busy_day/171717/24     408 -> 417  passed  moved {}
--     busy_day/424242/24     409 -> 418  passed  moved {}
--     busy_day/171717/48     410 -> 419  passed  moved {}
--   Verdicts 411-419, pairs started 21:10-21:29 UTC (4:10-4:29 PM CT; `certified_at` is the pair's transaction start),
--   the first 17 seconds after 0499 went in, the last ending at 21:38. HELD as predicted: no digest moved, so no
--   proposal the selector handed on in the canon was one the gate refuses, and 0499 changes no certified behaviour.
--   0498 needs no canon reading (the facts block is off for every arm).
