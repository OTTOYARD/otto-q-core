-- migration-version: 20260928053318
-- migration-name:    a_car_waiting_for_a_charger_keeps_its_place_in_line
--
-- 0546  **A car waiting for a charger keeps its place in line, a car with no visit is not sent to the back of it, and a
--        car the readiness gate releases leaves the gate's flag behind.** (a) The service flow's deadlock breaker
--        re-stamped `last_state_change` on every waiting car below 80% on every tick, so each of them read as having
--        just arrived. (b) The gate's release kept the flag the gate itself had raised, so a finished car went back to
--        work flagged for a technician. (c) The charge cursor's first key, "is this an immediate dispatch", read NULL
--        for a car with no visit, and NULLS LAST sorted every such car behind every car with a visit. (d) A car held on
--        its remedy (waiting for a charger or the service bay) was never escalated to a person, however long it
--        waited: the gate's hard cap judged only cars held for bay work.
--
-- ══ §1 WHY (validation run 4acf0b1d, check 0403; CLAUDE.md rule 9; G271, G272, G273) ═════════════════════════════════
--
--   0545 (c) orders OTTO-Q's charge cursor by response ratio, (minutes waited + points to charge) / points to charge,
--   and measures the wait from `vehicles.last_state_change`, which the log trigger and the twin keep on the sim clock.
--   The first probe of 4acf0b1d (tick 41, 5:08 AM CT sim) read 24 cars on `need_charge` at 12-46% with a wait of 0
--   minutes, beside boot cars at 78-96% with 18-21 minutes. Every one of the 24 had a visit; none of the boot cars did.
--
--   The writer is STEP 0 of `twin.ottoq_sim_advance_service_flow`, "re-charge stranded under-floor vehicles (deadlock
--   breaker)". Each tick it takes every car in `charge_complete_holding`, `staged_awaiting_service` or
--   `staged_for_departure` below `deploy_floor_soc` (80) with an open charge atom and no active dispatch, and writes
--   `current_state = 'staged_awaiting_service'`, `last_state_change = <this tick>`, `svc_step = 'need_charge'`, even
--   when the car is already exactly there. The log trigger stamps `last_state_change` only on a state change, and it
--   leaves an explicit stamp alone (0057), so the explicit stamp lands. And `ottoq_vehicles_state_change` drops a diff
--   of clock keys alone (0015), so the signed stream never shows it. Census at tick 95: of the cars whose
--   `last_state_change` was this tick with no state change in the stream, 17 were staged on `need_charge`, and all 17
--   were below 80% with an open charge atom. That is exactly STEP 0's set. The other 14 were deployed cars, stamped by the
--   deployed telemetry (§4).
--
--   What read the column, and so what the re-stamp broke for every waiting car below 80% with a visit:
--   - OTTO-Q's charge cursor (0545 (c)). The ratio's wait term was 0, so these cars kept a ratio of exactly 1 and
--     fell behind every car that had waited a minute, then among themselves to `current_soc ASC`: lowest charge first,
--     the order 0545 retired. A car at 50-79% could still starve behind a stream of lower arrivals, as Waymo-AV-006 (83%,
--     373 minutes) and Waymo-AV-037 (51%, 230 minutes) did on 9eab647f (0403 §0).
--   - The FIFO baseline seat (seat 1) orders the same cursor by `last_state_change ASC`. For these cars "first in"
--     was "whoever was re-stamped last", and the tie fell to lowest charge: the FIFO arm was not FIFO.
--   - `public.ottoq_depot_queue`, the queue positions the cockpits show, ranks by the same column. These cars always
--     sat at the back.
--   - `twin.ottoq_sim_advance_visit_atoms` hands technicians to in-place work (walkaround, sensor clean, cabin work)
--     by `last_state_change ASC` after the charging cars, so these cars' in-place work waited behind every other car.
--   - The service flow's own staging-overflow count reports cars waiting past `queue_patience`. None of these cars was
--     ever past it.
--
--   G273, the gate's flag outlives the hold. The readiness gate flags a car it has held past its patience
--   (`deploy_gate_stuck`, 45 minutes) or its hard cap (`deploy_gate_hard_cap`, 240) with `flagged_issue`, so that a
--   technician looks. When the car is finished the gate releases it to `staged_for_departure` and drops its own
--   `deploy_gate` stamp, but it keeps the flag. Only a service-bay seat clears it (0475). On 9eab647f (0403 §8,
--   measured before the purge), 8 releases kept the flag, on 7 cars, and one was Tesla-AV-061, G269's false alarm.
--   A flag that outlives its reason tells every cockpit that a finished car needs a person. It also routes the car to
--   the service bay the next time it leaves a wash or detail bay (the bay exit reads `flagged_issue` as service
--   work), which takes the scarcest seat in the depot for nothing.
--
--   G271 again, on 4acf0b1d: the ratio 0545 (c) added never reached the cars G271 was about. The cursor's first key
--   is `(SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn ...) DESC NULLS LAST`. For a car with no
--   open visit the subquery is NULL, and NULLS LAST puts it after every car with a visit, whatever it has waited. The
--   boot cars G271 found waiting at 91-98% (14 of 16 on 9eab647f) have no visit. At sim 6:30 AM on 4acf0b1d, 14
--   no-visit cars at 78-96% were still on `need_charge`, one of them for 102 minutes. The 35 charge sessions that had
--   started since 5:00 AM had all gone to cars with a visit: 18 immediate dispatches and 17 standard visits at 26-69%.
--   The 20 no-visit cars that did charge all started before 5:00 AM, when the boot left chargers free.
--
--   G274, a car waiting for its remedy is never escalated. 0542 made the readiness gate's hard cap (240 minutes) escalate
--   a held car to a person instead of releasing it. The gate judges only `need_deploy` cars, those held for wash or
--   detail work or its check. A car held on `need_charge` or `need_service` is just as unable to leave, and nothing
--   judges its wait. At sim 9:08 AM on 4acf0b1d, 14 cars had waited about 260 minutes for a charger, with no
--   escalation.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) STEP 0 stamps `last_state_change` only when it moves a car into `staged_awaiting_service`: from
--       `charge_complete_holding` or `staged_for_departure`. A car already staged keeps its stamp, so the stamp says
--       when it began to wait. Everything else STEP 0 does is unchanged: the replan, the step it writes and the temp
--       stall it claims. It stays a deadlock breaker. It no longer resets the clock of the car it is breaking the
--       deadlock for.
--   (b) The gate's release drops the flag when the gate raised it (`deploy_gate_stuck`, `deploy_gate_hard_cap`), in the
--       same statement that drops its `deploy_gate` stamp. A flag anything else raised (a fault, a cosmetic or wash
--       flag) is kept, as before. The escalation event stays in the signed stream: the record of what happened is
--       unchanged; only the car's current state stops saying it is still stuck.
--   (c) The charge cursor's first key reads a car with no open visit as not an immediate dispatch (false), not as
--       unknown (NULL). An immediate dispatch still goes first. Every other car, with a visit or without, is then
--       ordered by the seat's own keys: OTTO-Q's response ratio, FIFO's arrival, greedy's depletion.
--   (d) After the gate, the service flow escalates every car held on `need_charge` or `need_service` whose wait (since
--       `last_state_change`, which (a) makes the start of the wait) has reached the same hard cap. The car gets the
--       gate's own event, `twin.deploy_gate_escalated` (critical), with reason `waiting_for_a_charger` or
--       `waiting_for_the_service_bay`, what it still needs and how long it has waited. That is one event per wait: a
--       `remedy_wait` stamp holds this run and the start of the wait. The car is not moved or released: it is a
--       capacity finding for a person. The three cockpits already word the event.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   Every arm runs the service flow and the decide tick. `last_state_change` orders the charge cursor (both seats),
--   the in-place starter and the release cursor, and the cursor's first key now places a car with no visit, so which
--   car is served next can move. A flag dropped at release changes where a car goes when it next leaves a wash or
--   detail bay.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - The deployed telemetry (`twin.ottoq_sim_advance_deployed_telemetry`) stamps `last_state_change` on every
--     deployed car each tick with its SoC drain. Its readers are `ottoq_sweep_stranded_deployments`, for which a fresh
--     stamp means "reporting", and nothing that orders deployed cars. It is measured here, not changed.
--   - The charge-wait KPI still counts visits, so a boot car with no visit is not in it (G271). Check 0403 §7 reads the
--     waits from the state stream.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0546 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: each function is the one measured (md5 of its source after 0545, 2026-09-28 04:33-04:40 UTC) ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)', '06a8cc842fe864c804835d26c9e2b2db'),
      ('public.ottoq_decide_tick(uuid)',                                                  '8da886f7f14cf12c3705e6aa6ec6ed35')
    ) AS t(sig, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) <> r.want THEN
      RAISE EXCEPTION '0546 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0546_pre', 'function', f.sch, f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('twin',   'ottoq_sim_advance_service_flow', 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'),
               ('public', 'ottoq_decide_tick',              'public.ottoq_decide_tick(uuid)')
       ) AS f(sch, obj, sig);

-- ── STEP 0 stamps the clock only when it moves a car into staging ──
DO $step0$
DECLARE v_def text; n int;
  c_old CONSTANT text := E'      UPDATE vehicles\n'
    || E'         SET current_state = ''staged_awaiting_service''::vehicle_state,\n'
    || E'             last_state_change = p_sim_clock_now,\n'
    || E'             config = jsonb_set(config, ''{svc_step}'',\n'
    || E'                                to_jsonb(COALESCE(v_dec->>''svc_step'', ''need_charge'')))\n'
    || E'       WHERE id = v_rec.id;';
  c_new CONSTANT text := E'      UPDATE vehicles\n'
    || E'         SET current_state = ''staged_awaiting_service''::vehicle_state,\n'
    || E'             -- 0546 (G272): stamp the clock only for a car this moves INTO staging. A car already staged keeps\n'
    || E'             -- its stamp, so the stamp says when it began to wait. Re-stamping it every tick made every waiting\n'
    || E'             -- car below the floor read as just arrived to each queue that orders by it (the charge cursor,\n'
    || E'             -- FIFO, the depot queue, the in-place starter).\n'
    || E'             last_state_change = CASE WHEN current_state = ''staged_awaiting_service''::vehicle_state\n'
    || E'                                      THEN last_state_change ELSE p_sim_clock_now END,\n'
    || E'             config = jsonb_set(config, ''{svc_step}'',\n'
    || E'                                to_jsonb(COALESCE(v_dec->>''svc_step'', ''need_charge'')))\n'
    || E'       WHERE id = v_rec.id;';
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0546 step 0: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $step0$;

-- ── (b) the gate's release drops the flag the gate raised ──
DO $release$
DECLARE v_def text; n int;
  c_old CONSTANT text := E'          UPDATE vehicles SET current_state = ''staged_for_departure''::vehicle_state, last_state_change = p_sim_clock_now,\n'
    || E'                 config = jsonb_set(config, ''{svc_step}'', to_jsonb(''ready''::text)) - ''deploy_gate''\n'
    || E'           WHERE id = v_rec.id;';
  c_new CONSTANT text := E'          UPDATE vehicles SET current_state = ''staged_for_departure''::vehicle_state, last_state_change = p_sim_clock_now,\n'
    || E'                 -- 0546 (G273): the release drops the flag this gate raised with its own stamp. A finished car\n'
    || E'                 -- flagged "stuck" told every cockpit it needed a person, and the next bay exit sent it to the\n'
    || E'                 -- service bay. A flag anything else raised is kept.\n'
    || E'                 config = jsonb_set(config, ''{svc_step}'', to_jsonb(''ready''::text)) - ''deploy_gate''\n'
    || E'                          - (CASE WHEN config->>''flagged_issue_type'' IN (''deploy_gate_stuck'', ''deploy_gate_hard_cap'')\n'
    || E'                                  THEN ARRAY[''flagged_issue'', ''flagged_issue_type''] ELSE ARRAY[]::text[] END)\n'
    || E'           WHERE id = v_rec.id;';
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0546 release: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $release$;

-- ── (c) the charge cursor reads a car with no visit as not an immediate dispatch ──
DO $nullkey$
DECLARE v_def text; n int;
  c_head_old CONSTANT text := E'     ORDER BY (SELECT vn.urgency = ''immediate_dispatch'' FROM ottoq_visit_needs vn\n';
  c_head_new CONSTANT text := E'     ORDER BY COALESCE((SELECT vn.urgency = ''immediate_dispatch'' FROM ottoq_visit_needs vn\n';
  c_tail_old CONSTANT text := E'                 ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) DESC NULLS LAST,\n'
    || E'              /* 0261: under a baseline seat';
  c_tail_new CONSTANT text := E'                 ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false) DESC,\n'
    || E'              /* 0546 (G271): a car with no open visit is not an immediate dispatch. As NULL it sorted, NULLS LAST,\n'
    || E'                 after every car with a visit whatever it had waited: the boot cars G271 found at 91-98%. */\n'
    || E'              /* 0261: under a baseline seat';
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_head_old, ''))) / length(c_head_old);
  IF n <> 1 THEN RAISE EXCEPTION '0546 cursor: the head matches % times, not 1', n; END IF;
  n := (length(v_def) - length(replace(v_def, c_tail_old, ''))) / length(c_tail_old);
  IF n <> 1 THEN RAISE EXCEPTION '0546 cursor: the tail matches % times, not 1', n; END IF;
  EXECUTE replace(replace(v_def, c_head_old, c_head_new), c_tail_old, c_tail_new);
END $nullkey$;

-- ── (d) a car held on its remedy past the hard cap is escalated to a person ──
DO $remedywait$
DECLARE v_def text; n int;
  c_anchor CONSTANT text := E'  -- overflow now counts need_charge too: a vehicle held by the readiness gate is still\n';
  c_block CONSTANT text := $blk$  -- 0546 (G274, CLAUDE.md rule 9): a car held on its remedy (a charger or the service bay) past the hard cap is
  -- escalated to a person as a car held at the gate is: one critical twin.deploy_gate_escalated per wait, stamped
  -- remedy_wait {run, since}. The gate judges only need_deploy cars, so a car could wait all day for a charger with no
  -- one told. The car is not moved or released: its wait is a capacity finding.
  DECLARE v_w RECORD; v_wait_min NUMERIC; v_w_missing TEXT[];
  BEGIN
    FOR v_w IN
      SELECT v.id, v.current_soc, v.last_state_change, v.config->>'svc_step' AS step
        FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
         AND v.current_state = 'staged_awaiting_service'
         AND v.config->>'svc_step' IN ('need_charge', 'need_service')
         AND v.last_state_change <= p_sim_clock_now - make_interval(mins => v_hardcap::int)
         AND NOT (COALESCE(v.config #>> '{remedy_wait,run}', '') = p_sim_run_id::text
                  AND (v.config #>> '{remedy_wait,since}')::timestamptz IS NOT DISTINCT FROM v.last_state_change)
       ORDER BY v.last_state_change, v.id
    LOOP
      v_wait_min := EXTRACT(EPOCH FROM (p_sim_clock_now - v_w.last_state_change)) / 60.0;
      SELECT COALESCE(array_agg(DISTINCT a->>'svc' ORDER BY a->>'svc'), ARRAY[]::text[]) INTO v_w_missing
        FROM ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
       WHERE vn.vehicle_id = v_w.id AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open','in_progress')
         AND a->>'svc' <> 'readiness_check' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');
      IF v_w.step = 'need_charge' AND NOT ('charge' = ANY (v_w_missing)) THEN
        v_w_missing := ARRAY['charge'] || v_w_missing;
      END IF;
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'deploy_ready_gate',
        p_event_type := 'twin.deploy_gate_escalated', p_entity_type := 'vehicle', p_entity_id := v_w.id,
        p_payload := jsonb_build_object('held_min', round(v_wait_min, 1), 'hard_cap_min', v_hardcap,
          'reason', CASE WHEN v_w.step = 'need_charge' THEN 'waiting_for_a_charger' ELSE 'waiting_for_the_service_bay' END,
          'remedy', v_w.step, 'soc', v_w.current_soc, 'missing', to_jsonb(v_w_missing),
          'note', 'waited past the hard cap for its remedy: a person must look. The car is not released (CLAUDE.md rule 9)'),
        p_severity := 'critical', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
      UPDATE vehicles
         SET config = COALESCE(config, '{}'::jsonb) || jsonb_build_object('remedy_wait', jsonb_build_object(
               'run', p_sim_run_id, 'since', v_w.last_state_change, 'escalated_at', p_sim_clock_now))
       WHERE id = v_w.id;   -- last_state_change deliberately UNTOUCHED
    END LOOP;
  END;

$blk$;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_anchor, ''))) / length(c_anchor);
  IF n <> 1 THEN RAISE EXCEPTION '0546 remedy wait: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_anchor, c_block || c_anchor);
END $remedywait$;

-- ── V1 (comment-stripped): STEP 0 keeps a staged car's stamp ──
DO $verify$
DECLARE v_src text;
BEGIN
  v_src := regexp_replace(regexp_replace(
             pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'last_state_change\s*=\s*CASE WHEN current_state\s*=\s*''staged_awaiting_service''::vehicle_state\s+THEN last_state_change ELSE p_sim_clock_now END,\s*config\s*=\s*jsonb_set\(config,\s*''\{svc_step\}'',\s*to_jsonb\(COALESCE\(v_dec->>''svc_step'',\s*''need_charge''\)\)\)', 'g')) <> 1 THEN
    RAISE EXCEPTION '0546 V1: STEP 0 does not keep a staged car''s stamp';
  END IF;
  IF v_src ~ 'last_state_change\s*=\s*p_sim_clock_now,\s*config\s*=\s*jsonb_set\(config,\s*''\{svc_step\}'',\s*to_jsonb\(COALESCE\(v_dec->>' THEN
    RAISE EXCEPTION '0546 V1: STEP 0 still stamps every car it touches';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'to_jsonb\(''ready''::text\)\) - ''deploy_gate''\s*- \(CASE WHEN config->>''flagged_issue_type'' IN \(''deploy_gate_stuck'', ''deploy_gate_hard_cap''\)\s*THEN ARRAY\[''flagged_issue'', ''flagged_issue_type''\] ELSE ARRAY\[\]::text\[\] END\)', 'g')) <> 1 THEN
    RAISE EXCEPTION '0546 V1: the gate''s release does not drop the flag it raised';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'config->>''svc_step'' IN \(''need_charge'', ''need_service''\)\s*AND v\.last_state_change <= p_sim_clock_now - make_interval\(mins => v_hardcap::int\)', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_src, '''waiting_for_a_charger''', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_src, '''remedy_wait''', 'g')) <> 1 THEN
    RAISE EXCEPTION '0546 V1: a car held on its remedy past the hard cap is not escalated once per wait';
  END IF;
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'ORDER BY COALESCE\(\(SELECT vn\.urgency = ''immediate_dispatch'' FROM ottoq_visit_needs vn\s.*?LIMIT 1\), false\) DESC,\s*CASE WHEN v_seat = 1 THEN v\.last_state_change END ASC NULLS FIRST', 'gs')) <> 1 THEN
    RAISE EXCEPTION '0546 V1: the charge cursor''s first key does not read a car with no visit as false';
  END IF;
  IF v_src ~ 'LIMIT 1\) DESC NULLS LAST,\s*CASE WHEN v_seat = 1' THEN
    RAISE EXCEPTION '0546 V1: the charge cursor still sorts a car with no visit last';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0546_a_car_waiting_for_a_charger_keeps_its_place_in_line', true, true,
  'G272: STEP 0 of the service flow (the stranded under-floor deadlock breaker) stamps last_state_change only when it '
  'moves a car into staged_awaiting_service; a car already staged keeps its stamp. Before, every waiting car below the '
  'deploy floor with an open charge atom was re-stamped each tick, so the charge cursor (OTTO-Q''s response ratio and '
  'the FIFO seat), the depot queue, the in-place starter and the overflow patience count read it as just arrived. '
  'G273: the readiness gate''s release drops flagged_issue when the gate raised it (deploy_gate_stuck, '
  'deploy_gate_hard_cap); other flags are kept. G271: the charge cursor''s first key reads a car with no open visit '
  'as not an immediate dispatch (false) instead of NULL, which sorted it after every car with a visit. G274: a car '
  'held on need_charge or need_service past the gate''s hard cap is escalated to a person once per wait '
  '(twin.deploy_gate_escalated, reason waiting_for_a_charger / waiting_for_the_service_bay; remedy_wait stamp).', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the ended validation run 4acf0b1d (its cars and visits are still on record). Four cars, one pass of
--   the service flow:
--   (a) two cars at 50% with an open charge atom, stamped 60 minutes ago: one already staged on need_charge keeps its
--       stamp (a wait of 60 minutes); one in charge_complete_holding moves into staging stamped this tick (a real
--       state change);
--   (b) two finished cars at 100% held by the gate on need_deploy: one flagged by the gate (`deploy_gate_stuck`) is
--       released without the flag; one flagged by something else (`minor_cosmetic`) is released with it;
--   (d) a fifth car at 50% has waited 300 minutes on need_charge: it is escalated once, with reason
--       `waiting_for_a_charger`, and a second pass a minute later does not escalate it again. The car waiting 60
--       minutes is not escalated.
DO $v3$
DECLARE
  v_msg text; v_run uuid := '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c'; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_clock timestamptz; v_cars uuid[]; c1 uuid; c2 uuid; c3 uuid; c4 uuid; c7 uuid;
  s1 text; s2 text; s3 text; s4 text; t1 text; l1 timestamptz; l2 timestamptz; f3 text; f4 text;
  e1 int; e7 int; e7b int; r7 text; b1 int; b7 int;
BEGIN
  BEGIN
    SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    IF v_clock IS NULL THEN RAISE EXCEPTION '0546 V3: run % is gone; point V3 at a run that exists', v_run; END IF;
    SELECT array_agg(id ORDER BY id) INTO v_cars FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_twin AND v.category = 'autonomous'
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d
                          WHERE d.vehicle_id = v.id AND d.sim_run_id = v_run AND d.status IN ('active', 'returning'))
         AND NOT public.ottoq_vehicle_is_tethered(v.id, v_clock)
       ORDER BY v.id LIMIT 5) q;
    IF coalesce(array_length(v_cars, 1), 0) < 5 THEN RAISE EXCEPTION '0546 V3: fewer than five free twin cars'; END IF;
    c1 := v_cars[1]; c2 := v_cars[2]; c3 := v_cars[3]; c4 := v_cars[4]; c7 := v_cars[5];
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (v_cars) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    -- (a)'s two cars and (d)'s car owe a charge; (b)'s two have no open work
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status)
    SELECT c, v_run, v_twin, v_clock - interval '330 minutes', '0546_v3_' || c::text,
           '[{"svc":"charge","must_do":true,"status":"pending","concurrency":"anchor"}]'::jsonb, 'open'
      FROM unnest(ARRAY[c1, c2, c7]) c;
    UPDATE public.vehicles
       SET current_state = CASE WHEN id = c2 THEN 'charge_complete_holding' ELSE 'staged_awaiting_service' END::vehicle_state,
           current_soc = CASE WHEN id IN (c1, c2, c7) THEN 50 ELSE 100 END, current_stall_id = NULL,
           last_state_change = CASE WHEN id = c7 THEN v_clock - interval '300 minutes' ELSE v_clock - interval '60 minutes' END,
           config = (COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type' - 'deploy_gate' - 'remedy_wait')
                    || CASE WHEN id IN (c1, c7) THEN jsonb_build_object('svc_step', 'need_charge')
                            WHEN id = c2 THEN jsonb_build_object('svc_step', 'charged')
                            ELSE jsonb_build_object('svc_step', 'need_deploy',
                                   'deploy_gate', jsonb_build_object('run', v_run, 'held_since', v_clock - interval '50 minutes'),
                                   'flagged_issue', true,
                                   'flagged_issue_type', CASE WHEN id = c3 THEN 'deploy_gate_stuck' ELSE 'minor_cosmetic' END) END
     WHERE id = ANY (v_cars);

    -- escalations already on record for these cars from the run itself; this pass's are after minus before
    SELECT count(*) FILTER (WHERE entity_id = c1), count(*) FILTER (WHERE entity_id = c7) INTO b1, b7
      FROM public.ottoq_events WHERE sim_run_id = v_run AND event_type = 'twin.deploy_gate_escalated'
       AND entity_id IN (c1, c7);

    -- the service flow carries no search_path of its own and runs under its caller's (the world tick sets
    -- twin, ottoq, public, extensions); set the same here, local to this rolled-back block
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);
    PERFORM twin.ottoq_sim_advance_service_flow(v_run, v_clock, 30, v_twin);

    SELECT count(*) FILTER (WHERE entity_id = c1) - b1, count(*) FILTER (WHERE entity_id = c7) - b7
      INTO e1, e7
      FROM public.ottoq_events WHERE sim_run_id = v_run AND event_type = 'twin.deploy_gate_escalated'
       AND entity_id IN (c1, c7);
    SELECT payload->>'reason' INTO r7 FROM public.ottoq_events
     WHERE sim_run_id = v_run AND event_type = 'twin.deploy_gate_escalated' AND entity_id = c7
     ORDER BY event_seq DESC LIMIT 1;
    SELECT current_state::text, config->>'svc_step', last_state_change INTO s1, t1, l1 FROM public.vehicles WHERE id = c1;
    SELECT current_state::text, last_state_change INTO s2, l2 FROM public.vehicles WHERE id = c2;
    SELECT current_state::text, config->>'flagged_issue_type' INTO s3, f3 FROM public.vehicles WHERE id = c3;
    SELECT current_state::text, config->>'flagged_issue_type' INTO s4, f4 FROM public.vehicles WHERE id = c4;
    IF s1 <> 'staged_awaiting_service' OR t1 <> 'need_charge' OR l1 IS DISTINCT FROM v_clock - interval '60 minutes'
       OR s2 <> 'staged_awaiting_service' OR l2 IS DISTINCT FROM v_clock THEN
      RAISE EXCEPTION '0546 V3 FAILED (a): staged car % / % stamped % (want %); holding car % stamped % (want %)',
        s1, t1, l1, v_clock - interval '60 minutes', s2, l2, v_clock;
    END IF;
    IF s3 <> 'staged_for_departure' OR f3 IS NOT NULL OR s4 <> 'staged_for_departure' OR f4 IS DISTINCT FROM 'minor_cosmetic' THEN
      RAISE EXCEPTION '0546 V3 FAILED (b): gate-flagged car % flag %; otherwise-flagged car % flag %', s3, f3, s4, f4;
    END IF;
    -- (d): a second pass a minute later must not escalate the same wait again
    PERFORM twin.ottoq_sim_advance_service_flow(v_run, v_clock + interval '1 minute', 30, v_twin);
    SELECT count(*) - b7 INTO e7b FROM public.ottoq_events
     WHERE sim_run_id = v_run AND event_type = 'twin.deploy_gate_escalated' AND entity_id = c7;
    IF e1 <> 0 OR e7 <> 1 OR r7 IS DISTINCT FROM 'waiting_for_a_charger' OR e7b <> 1 THEN
      RAISE EXCEPTION '0546 V3 FAILED (d): 60-minute car escalated %; 300-minute car escalated % (reason %), % after a second pass',
        e1, e7, r7, e7b;
    END IF;

    RAISE EXCEPTION '0546 V3 PASSED: (a) the car already waiting kept its stamp (% minutes waited) and the car moved into staging was stamped this tick; (b) the gate released both finished cars, dropped the flag it raised and kept the cosmetic one; (d) the car waiting 300 minutes for a charger was escalated once (%) and not again',
      round(extract(epoch FROM (v_clock - l1)) / 60.0), r7;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0546 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0546 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- V3c, rolled back, on the same ended run: one working charger in the depot (every other twin charger faulted) and two
--   cars on need_charge. c5 has a standard visit owing a charge, is at 50% and has waited 30 minutes (ratio 1.6). c6 is
--   a boot car with no visit, at 90%, and has waited 100 minutes (ratio 11). One decide tick gives the charger to c6.
--   Before (c) it went to c5: a car with no visit sorted after every car with a visit.
DO $v3c$
DECLARE
  v_msg text; v_run uuid := '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c'; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_clock timestamptz; v_cars uuid[]; c5 uuid; c6 uuid; v_free uuid; v_charger uuid; v_by uuid; k5 int; k6 int;
BEGIN
  BEGIN
    SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    IF v_clock IS NULL THEN RAISE EXCEPTION '0546 V3c: run % is gone; point V3c at a run that exists', v_run; END IF;
    SELECT array_agg(id ORDER BY id) INTO v_cars FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_twin AND v.category = 'autonomous'
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d
                          WHERE d.vehicle_id = v.id AND d.sim_run_id = v_run AND d.status IN ('active', 'returning'))
         AND NOT public.ottoq_vehicle_is_tethered(v.id, v_clock)
       ORDER BY v.id LIMIT 2) q;
    IF coalesce(array_length(v_cars, 1), 0) < 2 THEN RAISE EXCEPTION '0546 V3c: fewer than two free twin cars'; END IF;
    c5 := v_cars[1]; c6 := v_cars[2];

    -- one L2 stall with a charger and a clear calendar stays; every other twin charger is faulted
    SELECT s.id, s.ocpp_charger_id INTO v_free, v_charger
      FROM public.stalls s
     WHERE s.depot_id = v_twin AND s.stall_type::text = 'l2' AND s.ocpp_charger_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                        WHERE b.stall_id = s.id AND b.state IN ('held', 'active')
                          AND b.during && tstzrange(v_clock, v_clock + interval '12 hours'))
     ORDER BY s.id LIMIT 1;
    IF v_free IS NULL THEN RAISE EXCEPTION '0546 V3c: no L2 stall with a clear calendar'; END IF;
    UPDATE public.ottoq_ocpp_chargers c SET station_state = 'Faulted'
      FROM public.stalls s
     WHERE s.ocpp_charger_id = c.charger_id AND s.depot_id = v_twin AND s.stall_type::text IN ('dcfc', 'l2') AND s.id <> v_free;
    UPDATE public.ottoq_ocpp_chargers SET station_state = 'Available' WHERE charger_id = v_charger;
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL,
                             status = 'available'
     WHERE id = v_free;

    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (v_cars) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status, urgency)
    VALUES (c5, v_run, v_twin, v_clock - interval '30 minutes', '0546_v3c_' || c5::text,
            '[{"svc":"charge","must_do":true,"status":"pending","concurrency":"anchor"}]'::jsonb, 'open', 'standard');
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state, current_stall_id = NULL,
           current_soc = CASE WHEN id = c5 THEN 50 ELSE 90 END,
           last_state_change = CASE WHEN id = c5 THEN v_clock - interval '30 minutes' ELSE v_clock - interval '100 minutes' END,
           config = (COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type' - 'deploy_gate')
                    || jsonb_build_object('svc_step', 'need_charge')
     WHERE id = ANY (v_cars);

    -- a tick of its own, so the decision snapshot and the ledger rows it writes do not collide with the run's last tick
    UPDATE public.ottoq_sim_runs SET tick_count = tick_count + 1 WHERE sim_run_id = v_run;
    PERFORM public.ottoq_decide_tick(v_run);

    SELECT reserved_by INTO v_by FROM public.stalls WHERE id = v_free;
    SELECT count(*) FILTER (WHERE vehicle_id = c5), count(*) FILTER (WHERE vehicle_id = c6) INTO k5, k6
      FROM public.ottoq_vehicle_commands
     WHERE sim_run_id = v_run AND issued_at = v_clock AND command_type = 'begin_charge' AND vehicle_id = ANY (v_cars);
    IF v_by IS DISTINCT FROM c6 OR k6 <> 1 OR k5 <> 0 THEN
      RAISE EXCEPTION '0546 V3c FAILED: the one charger is reserved by % (want the boot car %); begin_charge to the boot car %, to the visit car %',
        v_by, c6, k6, k5;
    END IF;

    RAISE EXCEPTION '0546 V3c PASSED: the one free charger went to the boot car with no visit (90%%, 100 minutes waiting), not the visit car at 50%% (30 minutes)';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0546 V3c PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0546 V3c: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3c$;

-- Rollback: EXECUTE the two `definition`s in ottoq_schema_snapshots WHERE label = '0546_pre' as they are.
COMMIT;
