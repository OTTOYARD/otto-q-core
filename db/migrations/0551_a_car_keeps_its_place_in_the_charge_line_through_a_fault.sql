-- migration-version: PENDING
-- migration-name:    a_car_keeps_its_place_in_the_charge_line_through_a_fault
--
-- 0551  **A car keeps its place in the charge line through a charger fault and through every move it makes while it
--        waits, a car that has waited four hours for a charger at the gate is escalated to a person, and the cockpit's
--        queue shows the line the engine serves.** (G279, G282, G284; CLAUDE.md rule 9)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   G279. OTTO-Q's charge cursor (0545 (c)) serves the highest response ratio first, (minutes waited + points to charge)
--   / points to charge, and reads "minutes waited" as sim now minus `vehicles.last_state_change`. That column restarts at
--   every state change. So every move a car makes while it waits restarts its wait at zero, and the charge line treats it
--   as just arrived:
--     - a charger fault. `twin.ottoq_sim_stop_charge_session` re-queues a car below its target (rule 9) into
--       `staged_awaiting_service`, stamped this tick. On 0405bf42 (check 0407 §16) 17 faults erased about 28 hours of
--       accumulated wait; on ca448d95 (check 0408 §16b) 15 faults erased 993.8 minutes, the largest Zoox-AV-086's 377.2
--       (escalated at 8:37 AM, then 24.5 minutes on a fast charger that faulted, then back to zero). Rule 9 lets a charge
--       end short at a fault only if the car is re-queued to finish, and a car re-queued at the back of the line may not.
--     - a move from the gate to staging (18 on eff13379 by sim 5:15 AM), or from staging to a wash or service bay and back.
--   G282. 0546 (d) escalates a car to a person when it has waited past the hard cap (240 minutes) for its remedy, and reads
--   only staged cars on need_charge or need_service. The charge cursor also reads every car at the gate below its target,
--   and most of the fleet's wait for a charger is spent there (0408 §15: 35.1% of fleet time at the gate, 8.3% staged). On
--   ca448d95, 16 stays at the gate below target reached 240 minutes, the longest 356.4, 77.2 car-hours, and a person was
--   told about none of them (0408 §18).
--   G284. `public.ottoq_depot_queue` feeds the cockpit's queue positions (`ottoq_vehicle_queue_position`, read by the
--   field-ops cockpit), and says it mirrors the decide path's order. It mirrors the order from before 0545: lowest charge
--   first, a car with no visit last (the NULL 0546 (c) removed), `current_soc < target` (0493 made it target − 1), and
--   reservations judged against `now()`, the wall clock, which on a sim run reads every reservation as expired. Since
--   0545 the cockpit has shown a car a place in a line the engine does not serve. Measured on eff13379 at sim 8:25 AM CT
--   (a rolled-back compile of this file's mirror under another name, 17:10 UTC): both mirrors list the same 52 cars, and
--   they agree on the position of 1. The old mirror's head is Tesla-RT-001, Tesla-AV-055, Tesla-AV-068; the engine's
--   order, with no bank yet, is Tesla-AV-055, Tesla-AV-068, Tesla-RT-001.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   One clock for a car's wait for a charger: the minutes in its current waiting state plus the minutes it banked in
--   earlier waiting states of the same episode.
--   (a) `public.ottoq_charge_wait_min(config, last_state_change, clock, run)` and `public.ottoq_charge_wait_since(config,
--       last_state_change, run)`: the clock, and the start of the episode. Total functions: a stamp from another run, or a
--       malformed one, reads as no bank.
--   (b) `public.ottoq_vehicle_charge_wait_bank()`, a BEFORE UPDATE OF current_state trigger on `vehicles`
--       (`trg_vehicle_state_change_wait_bank`, which sorts after `trg_vehicle_state_change`, so it reads the sim-clock
--       stamp that trigger settles). An episode starts when a car below its charge threshold first waits (at the gate or
--       in staging). Each time the car leaves a waiting state below the threshold, the minutes it waited there are added to
--       `config.charge_wait = {run, since, banked_min}`. The episode ends, and the stamp goes, when the car reaches the
--       threshold at a state change or leaves the site. The threshold is the cursor's own filter (the latest open visit's
--       target for this run, else the fleet default, minus 1). The run is the one that stamps the state-change event
--       (`ottoq.ottoq_active_sim_run_id()`). The trigger never raises: a failure is a warning and the row is written as asked.
--   (c) The charge cursor's ratio (OTTO-Q's seat) reads the clock. A car re-queued by a fault comes back with the wait it
--       had, and fewer points to charge, so ahead of where it was. FIFO and greedy keep their own keys.
--   (d) The remedy-wait escalation reads every car the cursor reads: staged cars on need_charge or need_service, as
--       before, and cars at the gate below the cursor's threshold (G282). A charge wait is read on the cursor's clock and
--       escalated once per episode (`remedy_wait.since` is the episode's start). A service-bay wait is unchanged. The event
--       says where the car waits (`at`: the gate or staging). The car is not moved or released.
--   (e) `public.ottoq_depot_queue` mirrors the cursor: its filter (target − 1), its keys by seat (immediate, then the seat's
--       own; OTTO-Q's ratio on the clock), and the run's sim clock for reservations and the ratio. `waiting_since` is the
--       episode's start. The signature is unchanged.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   Every arm runs the decide tick and the service flow. The cursor's order moves whenever a car carries a bank (a fault,
--   a gate-to-staging move, a bay visit while below target), and the escalation writes events and a stamp. The stamp is
--   in `vehicles.config`, which the world fingerprint hashes through `ottoq_scrub_ids`, so the run id in it does not split
--   the arms; `since` and `banked_min` are sim-clock values. No arm starts with a stamp: the pair's fleet reset
--   (`ottoq_tick_invariance_reset_fleet`) rebuilds `config` from an allowlist of static keys, and `charge_wait` is not one.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - The re-queue threshold in `twin.ottoq_sim_stop_charge_session` stays `target_soc − 5`. A fault at 95-98% sends the
--     car to `charge_complete_holding`; the readiness gate then holds it below `ready_soc` and routes it to a charger, so
--     it is re-queued the long way round. Its bank survives that route (§2 (b) drops the stamp only at the threshold).
--   - The time a car spends being served (charging, in a bay) is not wait and is not banked.
--   - `ottoq_kpi_charge_wait` still counts visits from their charge atoms, not this clock.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0551 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run at the twin depot (V3 edits twin cars and runs the tick and the service flow on an ended run) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0551 P1: a run is live at the twin depot';
  END IF;
END $live$;

-- ── P2: each function is the one measured (md5 of its source, 2026-09-28 16:47 UTC) ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_decide_tick(uuid)',                                                  'ca2d7a9cbd319204e93090f0858753dd'),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)', '76ed2394228fe25e1c393be206203023'),
      ('public.ottoq_depot_queue(uuid,uuid)',                                             '10c780b10122d5ae85ab512000a09bdf'),
      ('public.log_vehicle_state_change()',                                               '17c668e165cf30fce0913970ac4356a5')
    ) AS t(sig, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) <> r.want THEN
      RAISE EXCEPTION '0551 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('ottoq_charge_wait_min', 'ottoq_charge_wait_since', 'ottoq_vehicle_charge_wait_bank')) THEN
    RAISE EXCEPTION '0551 P2: a function this file creates already exists';
  END IF;
END $premises$;

-- ── P3: the trigger order this file relies on. The BEFORE UPDATE triggers on vehicles are the three measured, the log
--   trigger (which settles last_state_change on the sim clock) is one of them, and the new name sorts after it and
--   before the timestamp trigger (row triggers fire in name order, compared bytewise). ──
DO $order$
DECLARE v_before text[];
BEGIN
  SELECT array_agg(t.tgname::text ORDER BY t.tgname::text COLLATE "C") INTO v_before
    FROM pg_trigger t
   WHERE t.tgrelid = 'public.vehicles'::regclass AND NOT t.tgisinternal
     AND (t.tgtype & 2) = 2 AND (t.tgtype & 16) = 16 AND (t.tgtype & 1) = 1;   -- BEFORE, UPDATE, ROW
  IF v_before IS DISTINCT FROM ARRAY['ottoq_arm_interlock', 'trg_vehicle_state_change', 'trg_vehicles_updated'] THEN
    RAISE EXCEPTION '0551 P3: the BEFORE UPDATE row triggers on vehicles are %, not the three measured', v_before;
  END IF;
  IF (SELECT p.proname FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
       WHERE t.tgrelid = 'public.vehicles'::regclass AND t.tgname = 'trg_vehicle_state_change') <> 'log_vehicle_state_change' THEN
    RAISE EXCEPTION '0551 P3: trg_vehicle_state_change does not run log_vehicle_state_change';
  END IF;
  IF NOT ('trg_vehicle_state_change' COLLATE "C" < 'trg_vehicle_state_change_wait_bank' COLLATE "C"
          AND 'trg_vehicle_state_change_wait_bank' COLLATE "C" < 'trg_vehicles_updated' COLLATE "C") THEN
    RAISE EXCEPTION '0551 P3: the new trigger name does not sort between the log trigger and the timestamp trigger';
  END IF;
END $order$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0551_pre', 'function', f.sch, f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('public', 'ottoq_decide_tick',              'public.ottoq_decide_tick(uuid)'),
               ('twin',   'ottoq_sim_advance_service_flow', 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'),
               ('public', 'ottoq_depot_queue',              'public.ottoq_depot_queue(uuid,uuid)')
       ) AS f(sch, obj, sig);

-- ── (a) the clock ──
CREATE OR REPLACE FUNCTION public.ottoq_charge_wait_min(p_config jsonb, p_last_state_change timestamptz,
                                                        p_clock timestamptz, p_sim_run_id uuid)
RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0551 (G279): a car's wait for a charger, in minutes: the minutes in its current waiting state plus the minutes it
  -- banked in earlier waiting states of this run's episode (config.charge_wait, written by
  -- public.ottoq_vehicle_charge_wait_bank). A stamp from another run, or one without a numeric bank, adds nothing.
  SELECT GREATEST(COALESCE(EXTRACT(EPOCH FROM (p_clock - p_last_state_change)) / 60.0, 0), 0)
       + CASE WHEN p_config #>> '{charge_wait,run}' = p_sim_run_id::text
               AND jsonb_typeof(p_config #> '{charge_wait,banked_min}') = 'number'
              THEN GREATEST((p_config #>> '{charge_wait,banked_min}')::numeric, 0)
              ELSE 0 END
$fn$;
COMMENT ON FUNCTION public.ottoq_charge_wait_min(jsonb, timestamptz, timestamptz, uuid) IS
  '0551 (G279): a car''s wait for a charger in minutes, the one clock the charge cursor, the remedy-wait escalation and '
  'the cockpit queue read: (clock - last_state_change) plus the minutes banked earlier in this run''s episode.';

CREATE OR REPLACE FUNCTION public.ottoq_charge_wait_since(p_config jsonb, p_last_state_change timestamptz, p_sim_run_id uuid)
RETURNS timestamptz
LANGUAGE plpgsql STABLE
AS $fn$
-- 0551 (G279): when a car's wait for a charger began: the start of this run's episode, or, with no stamp for this run,
-- the start of its current waiting state.
BEGIN
  IF p_config #>> '{charge_wait,run}' = p_sim_run_id::text THEN
    RETURN COALESCE((p_config #>> '{charge_wait,since}')::timestamptz, p_last_state_change);
  END IF;
  RETURN p_last_state_change;
EXCEPTION WHEN OTHERS THEN
  RETURN p_last_state_change;
END $fn$;
COMMENT ON FUNCTION public.ottoq_charge_wait_since(jsonb, timestamptz, uuid) IS
  '0551 (G279): the start of a car''s wait for a charger: its episode''s start in this run, else its last state change.';

-- ── (b) the bank ──
CREATE OR REPLACE FUNCTION public.ottoq_vehicle_charge_wait_bank()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0551 (G279, CLAUDE.md rule 9): a car keeps its place in the charge line through every move it makes while it waits.
-- Fires on a change of current_state, after trg_vehicle_state_change has settled NEW.last_state_change on the sim clock.
--   - off the site: the episode is over; the stamp goes.
--   - at or above the charge threshold (the cursor's filter): no longer waiting for a charger; the stamp goes.
--   - leaving a waiting state (the gate, staging) below the threshold: the minutes waited there are banked.
-- Never raises: a failure is a warning, and the row is written as the caller asked.
DECLARE
  v_run uuid; v_threshold numeric; v_prev jsonb; v_banked numeric := 0; v_since timestamptz; v_add numeric;
BEGIN
  BEGIN
    IF NEW.current_state IN ('offline', 'deployed', 'en_route_to_depot', 'en_route_to_deployment', 'tow_requested', 'out_of_service') THEN
      IF NEW.config ? 'charge_wait' THEN NEW.config := NEW.config - 'charge_wait'; END IF;
      RETURN NEW;
    END IF;
    v_run := ottoq.ottoq_active_sim_run_id();
    IF v_run IS NULL THEN RETURN NEW; END IF;
    v_threshold := COALESCE((SELECT vn.target_soc FROM public.ottoq_visit_needs vn
                              WHERE vn.vehicle_id = NEW.id AND vn.status IN ('open', 'in_progress') AND vn.sim_run_id = v_run
                              ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1),
                            public.ottoq_default_target_soc()) - 1;
    IF COALESCE(NEW.current_soc, 0) >= v_threshold THEN
      IF NEW.config ? 'charge_wait' THEN NEW.config := NEW.config - 'charge_wait'; END IF;
      RETURN NEW;
    END IF;
    IF OLD.current_state IN ('arrived_at_gate', 'staged_awaiting_service') AND COALESCE(OLD.current_soc, 0) < v_threshold THEN
      IF NEW.config #>> '{charge_wait,run}' = v_run::text THEN v_prev := NEW.config -> 'charge_wait'; END IF;
      IF jsonb_typeof(v_prev -> 'banked_min') = 'number' THEN v_banked := GREATEST((v_prev ->> 'banked_min')::numeric, 0); END IF;
      v_since := COALESCE((v_prev ->> 'since')::timestamptz, OLD.last_state_change);
      v_add   := GREATEST(COALESCE(EXTRACT(EPOCH FROM (NEW.last_state_change - OLD.last_state_change)) / 60.0, 0), 0);
      NEW.config := COALESCE(NEW.config, '{}'::jsonb) || jsonb_build_object('charge_wait', jsonb_build_object(
                      'run', v_run, 'since', v_since, 'banked_min', round(v_banked + v_add, 3)));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_vehicle_charge_wait_bank: % % (vehicle %)', SQLSTATE, SQLERRM, NEW.id;
  END;
  RETURN NEW;
END $fn$;
COMMENT ON FUNCTION public.ottoq_vehicle_charge_wait_bank() IS
  '0551 (G279): banks a car''s wait for a charger in config.charge_wait {run, since, banked_min} each time it leaves a '
  'waiting state (the gate, staging) below the charge threshold; drops it at the threshold or off the site.';

DO $trigger$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.vehicles'::regclass AND tgname = 'trg_vehicle_state_change_wait_bank') THEN
    CREATE TRIGGER trg_vehicle_state_change_wait_bank
      BEFORE UPDATE OF current_state ON public.vehicles
      FOR EACH ROW WHEN (OLD.current_state IS DISTINCT FROM NEW.current_state)
      EXECUTE FUNCTION public.ottoq_vehicle_charge_wait_bank();
  END IF;
END $trigger$;

-- ── (c) the charge cursor's ratio reads the clock ──
DO $cursor$
DECLARE v_def text; n int;
  c_old CONSTANT text := E'              CASE WHEN v_seat = 0 THEN\n'
    || E'                (GREATEST(EXTRACT(EPOCH FROM (v_clock - v.last_state_change)) / 60.0, 0)\n'
    || E'                 + GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1))\n';
  c_new CONSTANT text := E'              CASE WHEN v_seat = 0 THEN\n'
    || E'                /* 0551 (G279): the wait is the car''s whole wait in this run''s episode, public.ottoq_charge_wait_min:\n'
    || E'                   the minutes in its current waiting state plus those it banked earlier. A charger fault, or a move\n'
    || E'                   from the gate to staging or to a bay, used to restart it at zero. */\n'
    || E'                (public.ottoq_charge_wait_min(v.config, v.last_state_change, v_clock, p_sim_run_id)\n'
    || E'                 + GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1))\n';
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0551 cursor: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $cursor$;

-- ── (d) the remedy-wait escalation reads every car the cursor reads, on the cursor's clock ──
DO $remedywait$
DECLARE v_def text; n int;
  c_old CONSTANT text := $old$  -- 0546 (G274, CLAUDE.md rule 9): a car held on its remedy (a charger or the service bay) past the hard cap is
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

$old$;
  c_new CONSTANT text := $new$  -- 0546 (G274, CLAUDE.md rule 9): a car held on its remedy (a charger or the service bay) past the hard cap is
  -- escalated to a person as a car held at the gate is: one critical twin.deploy_gate_escalated per wait, stamped
  -- remedy_wait {run, since}. The gate judges only need_deploy cars, so a car could wait all day for a charger with no
  -- one told. The car is not moved or released: its wait is a capacity finding.
  -- 0551 (G282, G279): every car the charge cursor reads is waiting for a charger, at the gate as well as in staging, and a
  -- charge wait is read on the cursor's clock (public.ottoq_charge_wait_min), so a fault or a move does not restart it.
  -- One escalation per episode: remedy_wait.since is the episode's start (public.ottoq_charge_wait_since). A wait for the
  -- service bay is timed as before, from the car's last state change.
  DECLARE v_w RECORD; v_w_missing TEXT[];
  BEGIN
    FOR v_w IN
      SELECT q.* FROM (
        SELECT v.id, v.current_soc, v.config, v.current_state::text AS state,
               CASE WHEN v.current_state = 'arrived_at_gate' THEN 'need_charge' ELSE v.config->>'svc_step' END AS step,
               CASE WHEN v.current_state = 'arrived_at_gate' OR v.config->>'svc_step' = 'need_charge'
                    THEN public.ottoq_charge_wait_min(v.config, v.last_state_change, p_sim_clock_now, p_sim_run_id)
                    ELSE GREATEST(EXTRACT(EPOCH FROM (p_sim_clock_now - v.last_state_change)) / 60.0, 0) END AS wait_min,
               CASE WHEN v.current_state = 'arrived_at_gate' OR v.config->>'svc_step' = 'need_charge'
                    THEN public.ottoq_charge_wait_since(v.config, v.last_state_change, p_sim_run_id)
                    ELSE v.last_state_change END AS since
          FROM vehicles v
         WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
           AND ((v.current_state = 'staged_awaiting_service' AND v.config->>'svc_step' IN ('need_charge', 'need_service'))
                OR (v.current_state = 'arrived_at_gate'
                    AND v.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
                                                   WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                                                     AND vn.sim_run_id = p_sim_run_id
                                                   ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1),
                                                 public.ottoq_default_target_soc()) - 1))
      ) q
       WHERE q.wait_min >= v_hardcap
         AND NOT (COALESCE(q.config #>> '{remedy_wait,run}', '') = p_sim_run_id::text
                  AND (q.config #>> '{remedy_wait,since}')::timestamptz IS NOT DISTINCT FROM q.since)
       ORDER BY q.since, q.id
    LOOP
      SELECT COALESCE(array_agg(DISTINCT a->>'svc' ORDER BY a->>'svc'), ARRAY[]::text[]) INTO v_w_missing
        FROM ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
       WHERE vn.vehicle_id = v_w.id AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open','in_progress')
         AND a->>'svc' <> 'readiness_check' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');
      IF v_w.step = 'need_charge' AND NOT ('charge' = ANY (v_w_missing)) THEN
        v_w_missing := ARRAY['charge'] || v_w_missing;
      END IF;
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'deploy_ready_gate',
        p_event_type := 'twin.deploy_gate_escalated', p_entity_type := 'vehicle', p_entity_id := v_w.id,
        p_payload := jsonb_build_object('held_min', round(v_w.wait_min, 1), 'hard_cap_min', v_hardcap,
          'reason', CASE WHEN v_w.step = 'need_charge' THEN 'waiting_for_a_charger' ELSE 'waiting_for_the_service_bay' END,
          'remedy', v_w.step, 'soc', v_w.current_soc, 'missing', to_jsonb(v_w_missing),
          'at', CASE WHEN v_w.state = 'arrived_at_gate' THEN 'gate' ELSE 'staging' END, 'waiting_since', v_w.since,
          'note', 'waited past the hard cap for its remedy: a person must look. The car is not released (CLAUDE.md rule 9)'),
        p_severity := 'critical', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
      UPDATE vehicles
         SET config = COALESCE(config, '{}'::jsonb) || jsonb_build_object('remedy_wait', jsonb_build_object(
               'run', p_sim_run_id, 'since', v_w.since, 'escalated_at', p_sim_clock_now))
       WHERE id = v_w.id;   -- last_state_change deliberately UNTOUCHED
    END LOOP;
  END;

$new$;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0551 remedy wait: the block matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $remedywait$;

-- ── (e) the cockpit's queue mirrors the cursor ──
CREATE OR REPLACE FUNCTION public.ottoq_depot_queue(p_depot_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(queue_kind text, queue_position integer, queue_depth integer, vehicle_id uuid, vehicle_ref text, current_soc numeric, target_soc numeric, is_immediate boolean, waiting_since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'ottoq', 'extensions'
AS $function$
  WITH z AS (
    SELECT COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) AS run,
           -- 0551 (G284): the run's own clock, as the decide tick reads it. now() is the wall clock, hours from a sim
           -- run's, and read every reservation as expired.
           COALESCE((SELECT r.sim_clock_current FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id), now()) AS clock,
           COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0)::int AS seat),
  -- sect.3 STALL ASSIGNMENT -- mirrored: ottoq_decide_tick's charge cursor, its filter and its keys (0493, 0545 (c),
  -- 0546 (c), 0551). Not mirrored: the one-tick cuOpt deferral and the charging-staff LIMIT, which hold a car back from
  -- this tick without moving its place.
  charge AS (
    SELECT v.id, v.display_name, v.current_soc, v.last_state_change,
           public.ottoq_charge_wait_since(v.config, v.last_state_change, p_sim_run_id) AS waiting_since,
           COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                          = (SELECT run FROM z)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1),
                    public.ottoq_default_target_soc()) AS target_soc,
           -- 0546 (c): a car with no open visit is not an immediate dispatch.
           COALESCE((SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                          = (SELECT run FROM z)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false) AS is_immediate,
           -- 0545 (c) on 0551's clock: (minutes waited + points to charge) / points to charge.
           (public.ottoq_charge_wait_min(v.config, v.last_state_change, (SELECT clock FROM z), p_sim_run_id)
            + GREATEST(public.ottoq_effective_target_soc_at(v.id, (SELECT clock FROM z)) - v.current_soc, 1))
           / GREATEST(public.ottoq_effective_target_soc_at(v.id, (SELECT clock FROM z)) - v.current_soc, 1) AS ratio
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id
       AND v.category = 'autonomous'
       AND (v.current_state = 'arrived_at_gate'
            OR (v.current_state = 'staged_awaiting_service' AND EXISTS (
                 SELECT 1 FROM stalls s2
                   JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
                  WHERE s2.depot_id = p_depot_id
                    AND s2.stall_type::text IN ('dcfc','l2')
                    AND s2.current_vehicle_id IS NULL
                    AND c2.station_state = 'Available'
                    AND (s2.reserved_by IS NULL OR s2.reserved_by = v.id
                         OR s2.reservation_expires_at <= (SELECT clock FROM z)))))
  ),
  charge_q AS (
    SELECT 'charge'::text AS qk,
           (row_number() OVER (ORDER BY c.is_immediate DESC,
                                        CASE WHEN (SELECT seat FROM z) = 1 THEN c.last_state_change END ASC NULLS FIRST,
                                        CASE WHEN (SELECT seat FROM z) = 2 THEN c.current_soc END ASC,
                                        CASE WHEN (SELECT seat FROM z) = 0 THEN c.ratio END DESC NULLS LAST,
                                        c.current_soc ASC, c.id))::int AS pos,
           (count(*)    OVER ())::int AS depth,
           c.id, c.display_name, c.current_soc, c.target_soc, c.is_immediate, c.waiting_since
      FROM charge c
     WHERE c.current_soc < c.target_soc - 1   -- 0493: the engine's charge rule
  ),
  -- sect.3b GATE INTAKE -- mirrored.
  gate_q AS (
    SELECT 'gate_intake'::text AS qk,
           (row_number() OVER (ORDER BY v.last_state_change ASC NULLS FIRST, v.id))::int AS pos,
           (count(*)    OVER ())::int AS depth,
           v.id, v.display_name, v.current_soc,
           NULL::numeric AS target_soc, NULL::boolean AS is_immediate, v.last_state_change
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id
       AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate'
       AND v.current_stall_id IS NULL
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                    WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                      AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                        = (SELECT run FROM z)
                      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'svc' = 'charge'
                                         AND COALESCE(a->>'status','pending') <> 'done'))
  )
  -- every reference qualified with u.: the RETURNS TABLE columns are OUT
  -- parameters and an unqualified current_soc would be ambiguous against them.
  SELECT u.qk, u.pos, u.depth, u.id, u.display_name, u.current_soc,
         u.target_soc, u.is_immediate, u.waiting_since
    FROM (SELECT * FROM charge_q UNION ALL SELECT * FROM gate_q) u
   ORDER BY u.qk, u.pos;
$function$;

-- ── V1 (comment-stripped): each change is in place, and the old forms are gone ──
DO $verify$
DECLARE v_src text;
BEGIN
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'CASE WHEN v_seat = 0 THEN\s*\(public\.ottoq_charge_wait_min\(v\.config, v\.last_state_change, v_clock, p_sim_run_id\)\s*\+ GREATEST\(public\.ottoq_effective_target_soc_at\(v\.id, v_clock\) - v\.current_soc, 1\)\)', 'g')) <> 1 THEN
    RAISE EXCEPTION '0551 V1: the charge cursor''s ratio does not read the clock';
  END IF;
  IF v_src ~ 'GREATEST\(EXTRACT\(EPOCH FROM \(v_clock - v\.last_state_change\)\)\s*/\s*60\.0,\s*0\)' THEN
    RAISE EXCEPTION '0551 V1: the charge cursor still reads the wait from the last state change alone';
  END IF;
  v_src := regexp_replace(regexp_replace(
             pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src, 'public\.ottoq_charge_wait_min\(v\.config, v\.last_state_change, p_sim_clock_now, p_sim_run_id\)', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_src, 'public\.ottoq_charge_wait_since\(v\.config, v\.last_state_change, p_sim_run_id\)', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_src, 'OR \(v\.current_state = ''arrived_at_gate''\s*AND v\.current_soc < COALESCE\(', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_src, '''since'', v_w\.since', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_src, '''remedy_wait''', 'g')) <> 1 THEN
    RAISE EXCEPTION '0551 V1: the remedy-wait escalation does not read the gate, the clock and the episode';
  END IF;
  IF v_src ~ 'AND v\.last_state_change <= p_sim_clock_now - make_interval\(mins => v_hardcap::int\)' THEN
    RAISE EXCEPTION '0551 V1: the remedy-wait escalation still times a charge wait from the last state change';
  END IF;
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_depot_queue(uuid,uuid)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF v_src !~ 'public\.ottoq_charge_wait_min\(v\.config, v\.last_state_change, \(SELECT clock FROM z\), p_sim_run_id\)'
     OR v_src !~ 'c\.current_soc < c\.target_soc - 1'
     OR v_src ~ 'now\(\)\)\)\)\)'
     OR v_src ~ 'ORDER BY c\.is_immediate DESC NULLS LAST' THEN
    RAISE EXCEPTION '0551 V1: the cockpit''s queue does not mirror the cursor';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgrelid = 'public.vehicles'::regclass AND t.tgname = 'trg_vehicle_state_change_wait_bank'
                    AND t.tgenabled = 'O' AND t.tgfoid = 'public.ottoq_vehicle_charge_wait_bank()'::regprocedure
                    AND (t.tgtype & 2) = 2 AND (t.tgtype & 16) = 16 AND (t.tgtype & 1) = 1
                    AND pg_get_triggerdef(t.oid) ~ 'BEFORE UPDATE OF current_state ON public\.vehicles FOR EACH ROW WHEN \(\(old\.current_state IS DISTINCT FROM new\.current_state\)\)') THEN
    RAISE EXCEPTION '0551 V1: the bank trigger is not a BEFORE UPDATE OF current_state row trigger on a change of state';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0551_a_car_keeps_its_place_in_the_charge_line_through_a_fault', true, true,
  'G279: a car''s wait for a charger is one clock, public.ottoq_charge_wait_min: the minutes in its current waiting state '
  'plus the minutes banked in earlier waiting states of the run''s episode. A BEFORE UPDATE OF current_state trigger on '
  'vehicles (trg_vehicle_state_change_wait_bank) banks them in config.charge_wait {run, since, banked_min} each time a '
  'car leaves the gate or staging below the charge threshold, and drops the stamp at the threshold or off the site. The '
  'charge cursor''s OTTO-Q ratio reads the clock, so a charger fault or a move no longer sends a car to the back of the '
  'line. G282: the remedy-wait escalation (0546 (d)) also reads cars at the gate below the threshold, reads a charge wait '
  'on the same clock, and escalates once per episode. G284: ottoq_depot_queue (the cockpit''s queue positions) mirrors '
  'the cursor''s filter, keys and sim clock.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest ended operator run at the twin depot, pinned as the active run for this transaction so
--   the trigger stamps it. Seven cars:
--   (a) A waited 100 minutes at the gate at 40%, went to an L2 charger 80 minutes in, charged 20 minutes to 55%, and its
--       charger faulted. The real stop path re-queues it; the trigger has banked 80 minutes since the gate.
--   (c) B has waited 70 minutes in staging at 50%. With one charger free, OTTO-Q's seat serves A first: A's ratio is
--       (10 + 80 + 45) / 45 = 3.0 against B's (70 + 50) / 50 = 2.4. Before the bank, A read (10 + 45) / 45 = 1.2 and B went
--       first. The cockpit's queue puts A ahead of B too.
--   (d) G at the gate at 30% for 250 minutes and H at the gate for 100 minutes with 150 banked are escalated once each,
--       `at` the gate; I at the gate at 100% for 300 minutes and J at the gate at 30% for 100 minutes are not. G then moves
--       to staging; a second pass does not escalate it again.
--   (b) the episode ends: the stamp goes when a car reaches the threshold at a state change, and when it leaves the
--       site (here `offline`, the teardown's state; `deployed` is in the same list, and the departure floor would refuse
--       a car below its target).
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  t timestamptz; car uuid[]; l2 uuid[]; ch uuid[];
  a uuid; b uuid; g uuid; h uuid; i uuid; j uuid; k uuid;
  v_sess uuid; v_cfg jsonb; v_lsc timestamptz; v_state text; v_by uuid; ka int; kb int;
  e_before jsonb; e_after jsonb; e_again int; pa int; pb int;
BEGIN
  BEGIN
    SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.run_by = 'operator_demo' AND r.status NOT IN ('initializing', 'running', 'paused')
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0551 V3: no ended operator run at the twin depot'; END IF;
    SELECT sim_clock_current + interval '1 day' INTO t FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = t, tick_count = tick_count + 1 WHERE sim_run_id = v_run;
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);

    SELECT array_agg(id ORDER BY id) INTO car FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS NULL
         AND v.robotic_tether_until IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id OR s.reserved_by = v.id)
       ORDER BY v.id LIMIT 7) q;
    IF coalesce(array_length(car, 1), 0) < 7 THEN RAISE EXCEPTION '0551 V3: fewer than seven free twin cars'; END IF;
    a := car[1]; b := car[2]; g := car[3]; h := car[4]; i := car[5]; j := car[6]; k := car[7];
    SELECT array_agg(id ORDER BY stall_code), array_agg(charger_id ORDER BY stall_code) INTO l2, ch FROM (
      SELECT s.id, s.stall_code, s.ocpp_charger_id AS charger_id FROM public.stalls s
       WHERE s.depot_id = v_depot AND s.stall_type::text = 'l2' AND s.ocpp_charger_id IS NOT NULL
         AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.current_stall_id = s.id OR v.robotic_tether_stall_id = s.id)
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings bk
                          WHERE bk.stall_id = s.id AND bk.state IN ('held', 'active')
                            AND bk.during && tstzrange(t - interval '1 day', t + interval '1 day'))
       ORDER BY s.stall_code LIMIT 2) x;
    IF coalesce(array_length(l2, 1), 0) < 2 THEN RAISE EXCEPTION '0551 V3: fewer than two free L2 stalls'; END IF;

    -- every car starts off the site with no stamp and no visit in this run
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (car) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    UPDATE public.vehicles
       SET current_state = 'offline', current_depot_id = v_depot, current_soc = 50, target_soc = 100,
           last_state_change = t - interval '400 minutes',
           config = COALESCE(config, '{}'::jsonb) - 'charge_wait' - 'remedy_wait' - 'deploy_gate' - 'flagged_issue' - 'flagged_issue_type'
     WHERE id = ANY (car);

    -- (a) A: 100 minutes at the gate at 40%, then an L2 charger 80 minutes in, 20 minutes of charge, a fault.
    UPDATE public.vehicles SET current_state = 'arrived_at_gate', current_soc = 40, last_state_change = t - interval '100 minutes' WHERE id = a;
    UPDATE public.vehicles SET current_state = 'charging_l2', current_stall_id = l2[1], last_state_change = t - interval '20 minutes' WHERE id = a;
    UPDATE public.vehicles SET current_soc = 55 WHERE id = a;
    UPDATE public.ottoq_ocpp_chargers SET station_state = 'Occupied', station_state_changed_at = t - interval '20 minutes' WHERE charger_id = ch[1];
    INSERT INTO public.ocpp_sessions(depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id, connector_id,
                                     status, started_at, soc_start, energy_delivered_kwh, sim_run_id)
    VALUES (v_depot, l2[1], a, 'V3-0551-A', 'V3-0551-A', 1, 1, 'active', t - interval '20 minutes', 40, 12, v_run)
    RETURNING id INTO v_sess;
    SELECT config INTO v_cfg FROM public.vehicles WHERE id = a;
    IF (v_cfg #>> '{charge_wait,banked_min}')::numeric IS DISTINCT FROM 80
       OR (v_cfg #>> '{charge_wait,since}')::timestamptz IS DISTINCT FROM t - interval '100 minutes' THEN
      RAISE EXCEPTION '0551 V3 FAILED (a): leaving the gate for a charger banked %', v_cfg -> 'charge_wait';
    END IF;
    PERFORM twin.ottoq_sim_stop_charge_session(v_sess, 'fault.v3_0551', t, 'V3 0551', v_run);
    SELECT current_state::text, last_state_change, config INTO v_state, v_lsc, v_cfg FROM public.vehicles WHERE id = a;
    IF v_state <> 'staged_awaiting_service' OR v_lsc <> t
       OR (v_cfg #>> '{charge_wait,banked_min}')::numeric IS DISTINCT FROM 80
       OR public.ottoq_charge_wait_min(v_cfg, v_lsc, t + interval '10 minutes', v_run) <> 90 THEN
      RAISE EXCEPTION '0551 V3 FAILED (a): after the fault A is % stamped % with %, reading % minutes',
        v_state, v_lsc, v_cfg -> 'charge_wait', public.ottoq_charge_wait_min(v_cfg, v_lsc, t + interval '10 minutes', v_run);
    END IF;

    -- (c) B: 70 minutes in staging at 50%, by t + 10. One charger free (l2[2]); every other twin charger faulted.
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service', current_soc = 50, last_state_change = t - interval '60 minutes',
           config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', '"need_charge"') WHERE id = b;
    UPDATE public.ottoq_ocpp_chargers c SET station_state = 'Faulted'
      FROM public.stalls s
     WHERE s.ocpp_charger_id = c.charger_id AND s.depot_id = v_depot AND s.stall_type::text IN ('dcfc', 'l2') AND s.id <> l2[2];
    -- The world tick stamps every charger's heartbeat before the decide tick (0424), and the proposer offers only a
    -- charger heard from in the last 90 seconds. V3 calls the decide tick alone, a day past the run's end, so it stamps
    -- the one free charger itself.
    UPDATE public.ottoq_ocpp_chargers SET station_state = 'Available', last_heartbeat_at = t + interval '10 minutes'
     WHERE charger_id = ch[2];
    UPDATE public.ottoq_sim_runs SET sim_clock_current = t + interval '10 minutes', tick_count = tick_count + 1 WHERE sim_run_id = v_run;
    SELECT max(queue_position) FILTER (WHERE vehicle_id = a), max(queue_position) FILTER (WHERE vehicle_id = b) INTO pa, pb
      FROM public.ottoq_depot_queue(v_depot, v_run) WHERE queue_kind = 'charge';
    PERFORM public.ottoq_decide_tick(v_run);
    SELECT reserved_by INTO v_by FROM public.stalls WHERE id = l2[2];
    SELECT count(*) FILTER (WHERE vehicle_id = a), count(*) FILTER (WHERE vehicle_id = b) INTO ka, kb
      FROM public.ottoq_vehicle_commands
     WHERE sim_run_id = v_run AND issued_at = t + interval '10 minutes' AND command_type = 'begin_charge' AND vehicle_id IN (a, b);
    IF v_by IS DISTINCT FROM a OR ka <> 1 OR kb <> 0 THEN
      RAISE EXCEPTION '0551 V3 FAILED (c): the one charger is reserved by % (want A %); begin_charge to A %, to B %', v_by, a, ka, kb;
    END IF;
    IF pa IS NULL OR pb IS NULL OR pa >= pb THEN
      RAISE EXCEPTION '0551 V3 FAILED (c): the cockpit''s queue puts A at % and B at %', pa, pb;
    END IF;

    -- (d) G, H, I, J at the gate; H with 150 minutes banked (written apart from the state change, as the trigger would).
    UPDATE public.vehicles SET current_state = 'arrived_at_gate', current_soc = 30, last_state_change = t - interval '240 minutes' WHERE id = g;
    UPDATE public.vehicles SET current_state = 'arrived_at_gate', current_soc = 30, last_state_change = t - interval '90 minutes' WHERE id = h;
    UPDATE public.vehicles SET config = COALESCE(config, '{}'::jsonb) || jsonb_build_object('charge_wait',
             jsonb_build_object('run', v_run, 'since', t - interval '250 minutes', 'banked_min', 150)) WHERE id = h;
    UPDATE public.vehicles SET current_state = 'arrived_at_gate', current_soc = 100, last_state_change = t - interval '290 minutes' WHERE id = i;
    UPDATE public.vehicles SET current_state = 'arrived_at_gate', current_soc = 30, last_state_change = t - interval '90 minutes' WHERE id = j;
    SELECT COALESCE(jsonb_object_agg(entity_id::text, n), '{}'::jsonb) INTO e_before FROM (
      SELECT entity_id, count(*) AS n FROM public.ottoq_events
       WHERE sim_run_id = v_run AND event_type = 'twin.deploy_gate_escalated' AND entity_id IN (g, h, i, j) GROUP BY 1) q;
    PERFORM twin.ottoq_sim_advance_service_flow(v_run, t + interval '10 minutes', 30, v_depot);
    SELECT COALESCE(jsonb_object_agg(e.entity_id::text, jsonb_build_object('n', e.n, 'at', e.at_, 'held', e.held, 'reason', e.reason)), '{}'::jsonb)
      INTO e_after FROM (
      SELECT entity_id, count(*) - COALESCE((e_before ->> entity_id::text)::int, 0) AS n,
             max(payload->>'at') AS at_, max((payload->>'held_min')::numeric) AS held, max(payload->>'reason') AS reason
        FROM public.ottoq_events
       WHERE sim_run_id = v_run AND event_type = 'twin.deploy_gate_escalated' AND entity_id IN (g, h, i, j) GROUP BY 1) e
     WHERE e.n > 0;
    IF (e_after #>> ARRAY[g::text, 'n'])::int IS DISTINCT FROM 1 OR (e_after #>> ARRAY[g::text, 'at']) IS DISTINCT FROM 'gate'
       OR (e_after #>> ARRAY[g::text, 'reason']) IS DISTINCT FROM 'waiting_for_a_charger'
       OR (e_after #>> ARRAY[h::text, 'n'])::int IS DISTINCT FROM 1 OR (e_after #>> ARRAY[h::text, 'held'])::numeric IS DISTINCT FROM 250
       OR e_after ? i::text OR e_after ? j::text THEN
      RAISE EXCEPTION '0551 V3 FAILED (d): escalations % (G %, H %, I %, J %)', e_after, g, h, i, j;
    END IF;
    -- G moves to staging a minute later (the trigger banks 251 minutes, since unchanged); a second pass does not escalate it
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service', last_state_change = t + interval '11 minutes',
           config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', '"need_charge"') WHERE id = g;
    PERFORM twin.ottoq_sim_advance_service_flow(v_run, t + interval '12 minutes', 30, v_depot);
    SELECT count(*) - COALESCE((e_before ->> g::text)::int, 0) INTO e_again FROM public.ottoq_events
     WHERE sim_run_id = v_run AND event_type = 'twin.deploy_gate_escalated' AND entity_id = g;
    SELECT config INTO v_cfg FROM public.vehicles WHERE id = g;
    IF e_again <> 1 OR (v_cfg #>> '{charge_wait,banked_min}')::numeric IS DISTINCT FROM 251
       OR (v_cfg #>> '{charge_wait,since}')::timestamptz IS DISTINCT FROM t - interval '240 minutes' THEN
      RAISE EXCEPTION '0551 V3 FAILED (d): after the move G has % escalations and %', e_again, v_cfg -> 'charge_wait';
    END IF;

    -- (b) the episode ends at the threshold at a state change, and off the site
    UPDATE public.vehicles SET current_state = 'arrived_at_gate', current_soc = 60, last_state_change = t - interval '30 minutes' WHERE id = k;
    UPDATE public.vehicles SET current_state = 'charging_l2', last_state_change = t WHERE id = k;
    IF NOT ((SELECT config FROM public.vehicles WHERE id = k) ? 'charge_wait') THEN
      RAISE EXCEPTION '0551 V3 FAILED (b): K banked nothing leaving the gate';
    END IF;
    UPDATE public.vehicles SET current_soc = 99.5 WHERE id = k;
    UPDATE public.vehicles SET current_state = 'charge_complete_holding', last_state_change = t + interval '1 minute' WHERE id = k;
    UPDATE public.vehicles SET current_state = 'offline', last_state_change = t + interval '12 minutes' WHERE id = g;
    IF (SELECT config FROM public.vehicles WHERE id = k) ? 'charge_wait' OR (SELECT config FROM public.vehicles WHERE id = g) ? 'charge_wait' THEN
      RAISE EXCEPTION '0551 V3 FAILED (b): a stamp survived the threshold (%) or leaving the site (%)',
        (SELECT config -> 'charge_wait' FROM public.vehicles WHERE id = k), (SELECT config -> 'charge_wait' FROM public.vehicles WHERE id = g);
    END IF;

    RAISE EXCEPTION '0551 V3 PASSED on run %: (a) A banked its 80 minutes at the gate and kept them through the fault; (c) with one charger free the tick served A (ratio 3.0) before B (2.4), and the cockpit''s queue put A at % and B at %; (d) G and H were escalated once at the gate (H at 250 minutes with its bank), I and J were not, and G''s move to staging did not escalate it again; (b) the stamp went at the threshold and off the site',
      v_run, pa, pb;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0551 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0551 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0551_pre' as it is; then
--   ALTER TABLE public.vehicles DISABLE TRIGGER trg_vehicle_state_change_wait_bank (a stamp left in config is read by
--   nothing once the three functions are restored).

COMMIT;
