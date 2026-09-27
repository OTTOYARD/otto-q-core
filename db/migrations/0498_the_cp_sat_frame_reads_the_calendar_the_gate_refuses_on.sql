-- migration-version: 20260926210609
-- migration-name:    the_cp_sat_frame_reads_the_calendar_the_gate_refuses_on
--
-- 0498  **CP-SAT planned cars onto chargers promised to other cars (G229).** `db/checks/0369` §1–§2.
--
-- ══ §1 WHAT WAS WRONG ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   CP-SAT (`forward_lex`) plans over the frame `public.ottoq_build_decision_frame` builds, and plans only onto a stall
--   whose `offerable` is true (`proposer/forward_proposer.py` `stall_is_free`). `offerable` is documented as the door's
--   verdict (0265), and it asked the pointer, the charger's state and heartbeat and the reservation. The door
--   (`ottoq.ottoq_validate_assignment`) asks one thing more, last: whether ANOTHER vehicle's held, active, done or
--   interrupted booking covers the clock. So a charger promised to a car still on its way read offerable, and a
--   proposal for it was refused at the gate.
--
--   Measured on validation run `394e1e83`: all 3 `forward_lex` refusals were on L2 `d01cc4ff`, whose calendar held car
--   `28417bea`'s charge booking from sim 8:04 to 10:18 AM (booked at 8:03, the tick before its window). The car
--   plugged in at 8:37. CP-SAT offered the stall to `2d2c46af` at 8:35 and 8:36 and to `bbf2928f` at 8:36, and the gate
--   refused each with "calendar booking held by 28417bea". The reactor found no other L2 free.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   Each stall in the frame's facts block gains `calendar_held_by`: the vehicle whose booking covers the frame's
--   clock, by the gate's own lookup (the same four states, the same `during @> clock`, the same order, the run scope
--   as an explicit branch so each side uses `ottoq_stall_bookings_live_stall_idx`). `offerable` also requires it to be
--   empty. Like the rest of that object this is vehicle-blind: a vehicle whose own booking covers the clock already
--   holds a place (`has_live_booking`) and is not planned for. `selector.facts_version` goes 3 → 4.
--
--   Every other reader of `offerable` is served the same way: the LLM advisor's digest (`bridge/llm_proposer.py`)
--   shows it, and nothing in the database reads it. The proposer's refusal vocabulary names the new reason
--   (`calendar_held`, `proposer/forward_proposer.py`) so a fire record says which scarcity CP-SAT hit.
--
-- ══ §3 forces_recert FALSE ══════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_decide_tick` snapshots this frame every tick, but the facts block is emitted only when
--   `proposer_frame_facts` is on, and it is not set for any certification arm (every arm reads the default, 0), so a
--   canon arm's frame carries neither key. And no atom reads `ottoq_decision_snapshots`: the functions that do are the
--   snapshot writer and verifier, `ottoq_certify_run`, `ottoq_score_run` and `ottoq_twin_run_digest`, none called by
--   `ottoq_determinism_pair`.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0498 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure))
     <> '5573183a97e47087d5ff70e6a1104523' THEN
    RAISE EXCEPTION '0498 P2: public.ottoq_build_decision_frame(uuid,uuid) is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0498_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure;

DO $patch$
DECLARE
  r record;
  v_def text := pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure);
  n int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('offerable and the calendar lookup',
       $o$                           OR COALESCE(s.reservation_expires_at, '-infinity'::timestamptz) <= g.clk))
      ) ELSE '{}'::jsonb END
      ORDER BY s.id)
      FROM stalls s
      LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
      WHERE s.depot_id = p_depot_id
$o$,
       $n$                           OR COALESCE(s.reservation_expires_at, '-infinity'::timestamptz) <= g.clk)
                      AND cal.vehicle_id IS NULL),
        --: 0498 (G229). THE CALENDAR, the gate's last test and the one this verdict did not
        --: ask. ottoq.ottoq_validate_assignment refuses a stall on which ANOTHER vehicle's held,
        --: active, done or interrupted booking covers the clock. Without it a charger promised
        --: to a car still on its way read offerable, CP-SAT planned a car onto it and the gate
        --: refused the begin_charge: all 3 forward_lex refusals on run 394e1e83, on one L2 whose
        --: calendar held another car from 8:04 to 10:18 AM while that car arrived at 8:37.
        --: calendar_held_by names the holder. Vehicle-blind like the rest of this object: a
        --: vehicle whose own booking covers the clock holds a place and is not planned for.
        'calendar_held_by', cal.vehicle_id
      ) ELSE '{}'::jsonb END
      ORDER BY s.id)
      FROM stalls s
      LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
      --: 0498 (G229). The gate's own calendar lookup: the same states, the same order, and
      --: the run scope as an explicit branch as the gate writes it (0221), so each side is
      --: sargable on ottoq_stall_bookings_live_stall_idx. Gated on g.facts like every other
      --: fact, so a facts-off frame does no extra work.
      LEFT JOIN LATERAL (
        SELECT x.vehicle_id
          FROM (SELECT b.vehicle_id, lower(b.during) AS lo, b.booking_id
                  FROM ottoq_stall_bookings b
                 WHERE g.facts >= 1 AND p_sim_run_id IS NOT NULL
                   AND b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                   AND b.state IN ('held','active','done','interrupted')
                   AND b.during @> g.clk
                UNION ALL
                SELECT b.vehicle_id, lower(b.during), b.booking_id
                  FROM ottoq_stall_bookings b
                 WHERE g.facts >= 1 AND p_sim_run_id IS NULL
                   AND b.sim_run_id IS NULL AND b.stall_id = s.id
                   AND b.state IN ('held','active','done','interrupted')
                   AND b.during @> g.clk) x
         ORDER BY x.lo, x.vehicle_id, x.booking_id
         LIMIT 1
      ) cal ON true
      WHERE s.depot_id = p_depot_id
$n$),
      ('the contract version',
       $o$    'selector', jsonb_build_object('facts_version', 3, 'clock', g.clk,
$o$,
       $n$    --: 0498 (G229). facts_version 4: offerable also asks the calendar, and every stall
    --: carries calendar_held_by, the vehicle whose booking covers the clock.
    'selector', jsonb_build_object('facts_version', 4, 'clock', g.clk,
$n$)
    ) t(what, v_old, v_new)
  LOOP
    n := (length(v_def) - length(replace(v_def, r.v_old, ''))) / length(r.v_old);
    IF n <> 1 THEN RAISE EXCEPTION '0498: % matched % times, not once', r.what, n; END IF;
    v_def := replace(v_def, r.v_old, r.v_new);
  END LOOP;
  EXECUTE v_def;
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f    regprocedure := 'public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure;
  v_def  text := pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure);
  v_run uuid; v_depot uuid; v_clk timestamptz;
  v_frame jsonb; v_stall uuid; v_type text; v_b uuid; v_a uuid; v_st jsonb; v_gate jsonb;
BEGIN
  -- V1: the verdict asks the calendar once, the fact is published once, and the contract says 4.
  IF (length(v_def) - length(replace(v_def, 'AND cal.vehicle_id IS NULL),', ''))) / length('AND cal.vehicle_id IS NULL),') <> 1
     OR (length(v_def) - length(replace(v_def, '''calendar_held_by'', cal.vehicle_id', ''))) / length('''calendar_held_by'', cal.vehicle_id') <> 1
     OR (length(v_def) - length(replace(v_def, ') cal ON true', ''))) / length(') cal ON true') <> 1
     OR position('''facts_version'', 4' IN v_def) = 0 OR position('''facts_version'', 3' IN v_def) > 0 THEN
    RAISE EXCEPTION '0498 V1: the frame does not ask the calendar exactly once, or still says facts_version 3';
  END IF;
  -- V2: still stable and security definer, the same search path and privileges.
  IF (SELECT provolatile FROM pg_proc WHERE oid = v_f) <> 's' OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_f) <> 'search_path=twin, ottoq, public, extensions'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
        <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0498 V2: ottoq_build_decision_frame changed volatility, search path or privileges';
  END IF;
  -- V3: on the newest run whose frame carries the facts, make one charger clean at the run's clock (free, Available,
  -- answering, no booking covering the clock), see the frame offer it, promise it to one car, and ask the frame and the
  -- gate about it for another. The frame must stop offering it and name the holder, and the gate must refuse it for
  -- the same reason. Everything V3 writes is rolled back with its sub-block.
  SELECT r.sim_run_id, r.depot_id, r.sim_clock_current INTO v_run, v_depot, v_clk
    FROM public.ottoq_sim_runs r
   WHERE r.sim_clock_current IS NOT NULL AND r.depot_id IS NOT NULL
     AND COALESCE(public.ottoq_policy_get(r.sim_run_id, 'proposer_frame_facts', 0), 0) >= 1
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE EXCEPTION '0498 V3: no run carries the frame facts, so nothing here can show the frame asking the calendar';
  END IF;
  v_frame := public.ottoq_build_decision_frame(v_depot, v_run);
  IF (v_frame->'selector'->>'facts_version') IS DISTINCT FROM '4'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_frame->'stalls') s WHERE NOT (s ? 'calendar_held_by')) THEN
    RAISE EXCEPTION '0498 V3: a facts-on frame does not carry calendar_held_by on every stall';
  END IF;
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
  IF v_stall IS NULL OR v_a IS NULL OR v_b IS NULL THEN
    RAISE EXCEPTION '0498 V3: the depot of run % has no charger or not two cars to probe with', v_run;
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
    SELECT s INTO v_st FROM jsonb_array_elements(public.ottoq_build_decision_frame(v_depot, v_run)->'stalls') s
     WHERE (s->>'id')::uuid = v_stall;
    IF NOT COALESCE((v_st->>'offerable')::boolean, false) OR v_st->>'calendar_held_by' IS NOT NULL THEN
      RAISE EXCEPTION '0498 V3: the clean charger % is not offered before the promise: %', v_stall, v_st;
    END IF;
    PERFORM ottoq.ottoq_book_stall(v_run, v_stall, v_b, 'charge_' || v_type, v_clk - interval '5 minutes',
                                   v_clk + interval '30 minutes', NULL, NULL, 'otto_q');
    SELECT s INTO v_st FROM jsonb_array_elements(public.ottoq_build_decision_frame(v_depot, v_run)->'stalls') s
     WHERE (s->>'id')::uuid = v_stall;
    v_gate := ottoq.ottoq_validate_assignment(v_a, v_stall, 'begin_charge', v_clk, v_run);
    IF COALESCE((v_st->>'offerable')::boolean, true) OR (v_st->>'calendar_held_by')::uuid IS DISTINCT FROM v_b THEN
      RAISE EXCEPTION '0498 V3: the frame still offers % or names % as its holder, not %', v_stall, v_st->>'calendar_held_by', v_b;
    END IF;
    IF COALESCE((v_gate->>'ok')::boolean, true) OR v_gate->>'detail' IS DISTINCT FROM 'calendar booking held by ' || v_b THEN
      RAISE EXCEPTION '0498 V3: the gate answered % for the promised charger', v_gate;
    END IF;
    RAISE EXCEPTION '0498_v3_rolled_back';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '0498_v3_rolled_back' THEN RAISE; END IF;
  END;
END $verify$;

-- Rollback: restore public.ottoq_build_decision_frame(uuid,uuid) from ottoq_schema_snapshots label '0498_pre'
-- (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0498_the_cp_sat_frame_reads_the_calendar_the_gate_refuses_on', false,
  'ottoq_build_decision_frame: each stall in the facts block carries calendar_held_by (the gate''s own calendar '
  'lookup) and offerable requires it empty, facts_version 4. The facts block is off for every certification arm '
  'and no atom reads ottoq_decision_snapshots.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
