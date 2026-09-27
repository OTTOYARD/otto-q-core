-- migration-version: 20260926210943
-- migration-name:    the_proposal_selector_asks_the_calendar_the_gate_refuses_on
--
-- 0499  **The selector still handed the charge step an external proposal the gate refuses (G229, the disposal side).**
--       `db/checks/0369` §1 and §3.
--
-- ══ §1 WHAT WAS WRONG ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_l2_external_proposal` is what the charge step asks first for a car with no honourable reservation
--   (`ottoq_honour_reservation_proposal`), and the decision frame names it as the authority for `offerable`. For a
--   `stall_assignment` proposal it re-checks the stall against the pointer, the reservation and the charger's state and
--   heartbeat, and not the calendar. So a pending proposal for a charger another car's booking covers passed it, the
--   charge step emitted `begin_charge`, and the gate (`ottoq.ottoq_validate_assignment`) refused it. That is how CP-SAT's
--   3 proposals reached the gate on validation run `394e1e83` (0498 stops CP-SAT making them), and it is what any
--   proposal made against an older calendar still does: CP-SAT's are read up to 35 minutes after they were made.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   The selector's stall check also asks the gate's calendar question: no booking of ANOTHER vehicle, held, active, done
--   or interrupted, covers the run's clock (the clock this function already uses for the reservation and the
--   heartbeat). The proposal's own vehicle's booking does not count, as at the gate. A proposal that fails is passed
--   over like one whose charger went Faulted: it is not disposed of here, and the charge step falls back to the per-car
--   proposer, which has asked the gate since 0494.
--
-- ══ §3 forces_recert TRUE ═══════════════════════════════════════════════════════════════════════════════════════
--
--   The selector runs in the certified tick for the greedy optimizer's `greedy_constrained` proposals. Predicted: no
--   digest moves, because under 0495 every canon arm had 0 refusals of the charge step's `begin_charge`, so no proposal
--   the selector handed on was one the gate refused. The sweep reads it.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0499 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure))
     <> '70594a47fd91ada4c2d1f4d57621fef4' THEN
    RAISE EXCEPTION '0499 P2: public.ottoq_l2_external_proposal is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0499_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure);
  v_old text := $o$           AND c.last_heartbeat_at >= COALESCE(
                 (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), now())
                 - interval '90 seconds'))
$o$;
  v_new text := $n$           AND c.last_heartbeat_at >= COALESCE(
                 (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), now())
                 - interval '90 seconds'
           -- 0499 (G229): the calendar, the gate's last test. A charger another car's live booking covers
           -- at the run's clock is refused by ottoq.ottoq_validate_assignment, so a proposal for it is
           -- passed over here instead of being emitted to be refused. The proposal's own vehicle's booking
           -- does not count, as at the gate. Same states and clock domain as the gate.
           AND NOT EXISTS (
             SELECT 1 FROM ottoq_stall_bookings b
              WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                AND b.state IN ('held','active','done','interrupted')
                AND b.vehicle_id <> p_entity_id
                AND b.during @> COALESCE(
                      (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), now()))))
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0499: the stall check matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f    regprocedure := 'public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure;
  v_def  text := pg_get_functiondef('public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure);
  v_run uuid; v_depot uuid; v_clk timestamptz; v_stall uuid; v_type text; v_a uuid; v_b uuid;
  v_before jsonb; v_after jsonb; v_own jsonb; v_gate jsonb;
BEGIN
  -- V1: the calendar clause sits inside the stall check once, excluding the proposal's own vehicle.
  IF (length(v_def) - length(replace(v_def, 'AND b.vehicle_id <> p_entity_id', ''))) / length('AND b.vehicle_id <> p_entity_id') <> 1
     OR position('AND b.vehicle_id <> p_entity_id' IN v_def) < position('c.last_heartbeat_at >= COALESCE(' IN v_def)
     OR position('AND b.vehicle_id <> p_entity_id' IN v_def) > position('-- 0259:' IN v_def) THEN
    RAISE EXCEPTION '0499 V1: the selector does not ask the calendar inside its stall check';
  END IF;
  -- V2: still volatile and invoker-rights, the same search path and privileges.
  IF (SELECT provolatile FROM pg_proc WHERE oid = v_f) <> 'v' OR (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_f) <> 'search_path=twin, ottoq, public, extensions'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
        <> '=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0499 V2: ottoq_l2_external_proposal changed volatility, search path or privileges';
  END IF;
  -- V3: on the newest run with a clock, one clean charger, a pending proposal for car A on it: the selector hands it on.
  -- Promise the charger to car B: the selector passes A's proposal over, still hands on B's own, and the gate refuses
  -- A for the same reason. Everything V3 writes is rolled back with its sub-block.
  SELECT r.sim_run_id, r.depot_id, r.sim_clock_current INTO v_run, v_depot, v_clk
    FROM public.ottoq_sim_runs r
   WHERE r.sim_clock_current IS NOT NULL AND r.depot_id IS NOT NULL AND r.validation_status IS NULL
   ORDER BY r.started_at DESC LIMIT 1;
  SELECT s.id, s.stall_type::text INTO v_stall, v_type
    FROM public.stalls s
   WHERE s.depot_id = v_depot AND s.stall_type::text IN ('dcfc','l2') AND s.ocpp_charger_id IS NOT NULL
   ORDER BY s.id LIMIT 1;
  SELECT v.id INTO v_b FROM public.vehicles v
   WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS DISTINCT FROM v_stall
   ORDER BY v.id LIMIT 1;
  SELECT v.id INTO v_a FROM public.vehicles v
   WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.id <> v_b
     AND v.current_stall_id IS DISTINCT FROM v_stall
     AND v.current_state::text NOT IN ('tow_requested','out_of_service')
   ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_stall IS NULL OR v_a IS NULL OR v_b IS NULL THEN
    RAISE EXCEPTION '0499 V3: no operator run with a charger and two cars to probe with';
  END IF;
  BEGIN
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL,
                             status = 'available'
     WHERE id = v_stall;
    UPDATE public.ottoq_ocpp_chargers c SET station_state = 'Available', last_heartbeat_at = v_clk
      FROM public.stalls s WHERE s.id = v_stall AND c.charger_id = s.ocpp_charger_id;
    DELETE FROM public.ottoq_stall_bookings b
     WHERE b.sim_run_id = v_run AND b.stall_id = v_stall AND b.during @> v_clk
       AND b.state IN ('held','active','done','interrupted');
    DELETE FROM public.ottoq_external_proposals p
     WHERE p.sim_run_id = v_run AND p.action_context = 'stall_assignment' AND p.entity_id IN (v_a, v_b);
    INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal, source)
    VALUES (v_run, v_depot, 'stall_assignment', 'vehicle', v_a,
            jsonb_build_object('verb','assign_stall','stall_id', v_stall, 'stall_type', v_type, 'abstain', false), 'forward_lex'),
           (v_run, v_depot, 'stall_assignment', 'vehicle', v_b,
            jsonb_build_object('verb','assign_stall','stall_id', v_stall, 'stall_type', v_type, 'abstain', false), 'forward_lex');
    v_before := public.ottoq_l2_external_proposal(v_run, 'stall_assignment', 'vehicle', v_a);
    IF (v_before->>'stall_id')::uuid IS DISTINCT FROM v_stall THEN
      RAISE EXCEPTION '0499 V3: before the promise the selector did not hand on A''s proposal: %', v_before;
    END IF;
    PERFORM ottoq.ottoq_book_stall(v_run, v_stall, v_b, 'charge_' || v_type, v_clk - interval '5 minutes',
                                   v_clk + interval '30 minutes', NULL, NULL, 'otto_q');
    v_after := public.ottoq_l2_external_proposal(v_run, 'stall_assignment', 'vehicle', v_a);
    v_own   := public.ottoq_l2_external_proposal(v_run, 'stall_assignment', 'vehicle', v_b);
    v_gate  := ottoq.ottoq_validate_assignment(v_a, v_stall, 'begin_charge', v_clk, v_run);
    IF v_after IS NOT NULL THEN
      RAISE EXCEPTION '0499 V3: the selector still hands on A''s proposal for a charger promised to B: %', v_after;
    END IF;
    IF (v_own->>'stall_id')::uuid IS DISTINCT FROM v_stall THEN
      RAISE EXCEPTION '0499 V3: the selector refused B''s proposal for the charger B itself holds: %', v_own;
    END IF;
    IF COALESCE((v_gate->>'ok')::boolean, true) OR v_gate->>'detail' IS DISTINCT FROM 'calendar booking held by ' || v_b THEN
      RAISE EXCEPTION '0499 V3: the gate answered % for A', v_gate;
    END IF;
    RAISE EXCEPTION '0499_v3_rolled_back';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '0499_v3_rolled_back' THEN RAISE; END IF;
  END;
END $verify$;

-- Rollback: restore public.ottoq_l2_external_proposal from ottoq_schema_snapshots label '0499_pre' (CREATE OR REPLACE,
-- ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0499_the_proposal_selector_asks_the_calendar_the_gate_refuses_on', true,
  'ottoq_l2_external_proposal passes over a stall_assignment proposal whose charger another vehicle''s held, active, '
  'done or interrupted booking covers at the run''s clock, the gate''s calendar test. Runs in the certified tick for '
  'greedy_constrained proposals.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
