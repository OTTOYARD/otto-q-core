-- tests/fixtures/tick_lock_stub.sql -- what 0790 meets. Eleven definitions are the live ones of 2026-10-14
-- (pg_get_functiondef, byte for byte; tests/test_tick_lock_sql.py asserts each md5):
--   public.ottoq_sim_advance_tick_world(uuid)                              3e0ddbb1b097587bc2c0e9135d7895aa
--   public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)         0cd92ef247e8959fda68b2e6087bd944
--   twin.ottoq_report_charger_fault(uuid,text,text,text)                   a4339948b3520016e9979dc13faac605
--   public.ottoq_sim_stop_and_reset(uuid,text)                             bc8ee182436dfcd6bd53f62547ad5d5e  (0790 patches)
--   public.ottoq_sim_mark_stopped(uuid,text)                               d3325a7e94bc2791c5ebad11ae61a85d
--   public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean) 5ed4b74688e95d22736f3e4c6123e6a6
--   public.ottoq_demo_metronome(integer)  (a procedure)                    d02b6af9e3fa622267247f7277ef7057
--   public.ottoq_caller_identity()                                         9fc609c3613e62a79e40c2399b3f893d
--   public.ottoq_submit_external_proposal(uuid,uuid,text,text,uuid,jsonb,text,integer)
--                                                                          d19f166c1e280cb9bdc186f936f28d7c
--   public.ottoq_proposer_submit_batch(uuid,uuid,text,jsonb,jsonb,integer) 8c78997969489b3c8e097eba41fadc13
--   public.ottoq_capture_proposal_disposition()  (with its trigger, as live) 2d16c05a77ab1ad9b81780105fbfd78b
-- Every function they call is a stub that writes its name to t_calls. The tables carry the columns those bodies read and
-- write, and every run-scoped one carries its live foreign key to ottoq_sim_runs, which carries its live keys: the primary
-- key sim_run_id, the unique sim_run_seq, and the partial unique index on a running run per depot (partial, so not a key
-- a row lock can see). ottoq_proposer_fire_log and ottoq_proposal_disposition_ledger carry no foreign key, as live.
--
-- public.ottoq_sim_decide_and_dispatch is NOT the live body. It stands in for the metronome's decide step: the kernel
-- takes each car's newest pending proposal (read unlocked, as the live chooser ottoq_l2_external_proposal reads it) and
-- writes an enacted decision of this tick, then runs ottoq_decide_tick lines 1226-1244 (A3) VERBATIM, line 1228 being the
-- UPDATE the database's log caught at 16:42:42 UTC on 2026-10-14. Before A3: when t_decide.door names an application, it
-- waits (at most 20 s) until a backend of that name is waiting on a lock, so a test can put the door's wait inside the
-- beat; when t_decide.agent names one, it waits once per session until that agent has committed a newer proposal or is
-- waiting on a lock, so a test can put a proposal batch inside the beat. ottoq_purge_prior_runs is NOT the live body
-- either: it keeps the live order and statements on the run's row (see it below). Used by tests/test_tick_lock_sql.py.
SET check_function_bodies = off;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS twin; CREATE SCHEMA IF NOT EXISTS ottoq; CREATE SCHEMA IF NOT EXISTS extensions;
CREATE TABLE public.t_inflight (n int NOT NULL DEFAULT 0); INSERT INTO public.t_inflight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql
  AS 'SELECT n FROM public.t_inflight';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial, label text, object_kind text, schema_name text,
  object_name text, definition text, def_md5 text, captured_at timestamptz DEFAULT now());
CREATE TYPE public.vehicle_state AS ENUM ('arrived_at_gate', 'charge_complete_holding', 'charging', 'staged_awaiting_service');

CREATE TABLE public.depots (id uuid PRIMARY KEY, feed_mode text);
CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  sim_run_seq bigserial NOT NULL UNIQUE,
  scenario_code text, started_at timestamptz NOT NULL DEFAULT now(), ended_at timestamptz,
  last_tick_at timestamptz, next_tick_due_at timestamptz,
  sim_clock_start timestamptz, sim_clock_current timestamptz NOT NULL, sim_clock_end timestamptz NOT NULL,
  time_scale numeric NOT NULL DEFAULT 60.0, tick_interval_seconds integer NOT NULL DEFAULT 30,
  tick_count integer NOT NULL DEFAULT 0, depot_id uuid, random_seed bigint NOT NULL DEFAULT 42,
  status text NOT NULL DEFAULT 'initializing', failure_reason text, run_by text, notes text,
  payload jsonb DEFAULT '{}'::jsonb, policy text NOT NULL DEFAULT 'otto_q', demo_speed_x numeric NOT NULL DEFAULT 1.0);
CREATE UNIQUE INDEX ottoq_one_running_run_per_depot ON public.ottoq_sim_runs (depot_id) WHERE status = 'running';

CREATE TABLE public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid,
  station_state text, last_heartbeat_at timestamptz, last_fault_code text, station_state_changed_at timestamptz,
  last_fault_payload jsonb);
CREATE TABLE public.stalls (id uuid PRIMARY KEY, depot_id uuid, stall_code text, stall_type text, status text,
  ocpp_charger_id uuid REFERENCES public.ottoq_ocpp_chargers (charger_id) ON DELETE SET NULL,
  current_vehicle_id uuid, reserved_by uuid, reserved_at timestamptz, reservation_expires_at timestamptz);
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, home_depot_id uuid, category text, current_state public.vehicle_state,
  current_stall_id uuid, current_soc numeric, last_state_change timestamptz, robotic_tether_until timestamptz,
  robotic_tether_stall_id uuid, robotic_tether_direction text);
CREATE TABLE public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stall_id uuid, vehicle_id uuid,
  status text, sim_run_id uuid REFERENCES public.ottoq_sim_runs (sim_run_id));
CREATE TABLE public.ottoq_vehicle_dispatches (dispatch_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sim_run_id uuid REFERENCES public.ottoq_sim_runs (sim_run_id), status text);
CREATE TABLE public.ottoq_wear_tick_status (sim_run_id uuid REFERENCES public.ottoq_sim_runs (sim_run_id), tick_seq integer,
  sim_clock timestamptz, attempted integer, written integer, note text, PRIMARY KEY (sim_run_id, tick_seq));
CREATE TABLE public.ottoq_tick_clock_log (sim_run_id uuid REFERENCES public.ottoq_sim_runs (sim_run_id), tick_seq integer,
  real_started_at timestamptz, real_ended_at timestamptz, sim_clock_before timestamptz, sim_clock_after timestamptz,
  tick_compute_ms numeric, sim_advance_s numeric, playback_mode text, speed_x numeric, PRIMARY KEY (sim_run_id, tick_seq));
-- the agent's decision row, written through PostgREST: the insert c5f4ff34's 36 waits were measured on
CREATE TABLE public.ottoq_decisions (decision_id bigserial PRIMARY KEY,
  sim_run_id uuid CONSTRAINT fk_ottoq_decisions_sim_run REFERENCES public.ottoq_sim_runs (sim_run_id),
  resolved_action_context text, created_at timestamptz NOT NULL DEFAULT now(), tick_seq integer, entity_id uuid,
  outcome_status text, enacted_action jsonb, action_context text);
CREATE TABLE public.ottoq_external_proposals (proposal_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sim_run_id uuid CONSTRAINT fk_ottoq_external_proposals_sim_run REFERENCES public.ottoq_sim_runs (sim_run_id),
  action_context text DEFAULT 'stall_assignment', entity_type text DEFAULT 'vehicle', entity_id uuid, source text,
  proposal jsonb DEFAULT '{}'::jsonb, status text DEFAULT 'pending', expires_at timestamptz,
  created_at timestamptz DEFAULT now(), disposition_reason text, disposed_at timestamptz, disposed_tick bigint,
  depot_id uuid, declared_source text, submitted_by_role text, submitted_by uuid, tick_seq integer);
-- the proposal path's other tables, with no foreign key to the run, as live
CREATE TABLE public.ottoq_certified_proposers (source text PRIMARY KEY);
CREATE TABLE public.ottoq_proposer_precedence (source text PRIMARY KEY, rank integer);
CREATE TABLE public.ottoq_proposer_fire_log (fire_id bigserial PRIMARY KEY, sim_run_id uuid, depot_id uuid,
  declared_source text, effective_source text, tick_seq integer, fired_at timestamptz DEFAULT now(), status text,
  frame_hash text, n_vehicles integer, n_in_serviceable_state integer, n_rows integer, n_planned integer,
  n_abstained integer, n_deferred integer, n_submitted integer, proposal_ids uuid[], solver jsonb, fire jsonb, error text);
CREATE TABLE public.ottoq_proposal_disposition_ledger (disposition_id bigserial PRIMARY KEY, sim_run_id uuid,
  proposal_id uuid, depot_id uuid, action_context text, entity_type text, entity_id uuid, source text,
  proposer_rank integer, status text, disposition_reason text, abstained boolean, promotion_count integer,
  promoted_from uuid, stall_id uuid, requested_kw numeric, proposal_created_at timestamptz, disposed_at timestamptz,
  disposed_tick bigint, captured_at timestamptz DEFAULT now(), source_kind text);
-- what ottoq_caller_identity reads: no JWT, so a psql session as postgres is 'system', as pg_cron's is live
CREATE SCHEMA IF NOT EXISTS auth;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE
  AS 'SELECT NULLIF(current_setting(''request.jwt.claim.role'', true), '''')';
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS 'SELECT NULL::uuid';

CREATE TABLE public.t_calls (seq bigserial PRIMARY KEY, fn text NOT NULL, note text);
CREATE TABLE public.t_tick_failures (seq bigserial PRIMARY KEY, sim_run_id uuid, phase text, message text, sqlstate text);
CREATE TABLE public.t_decide (door text, agent text);
INSERT INTO public.t_decide VALUES (NULL, NULL);

CREATE FUNCTION public.ottoq_policy_get(uuid, text, numeric) RETURNS numeric LANGUAGE sql AS 'SELECT $3';
CREATE FUNCTION public.ottoq_sim_advance_visit_atoms(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_visit_atoms'); END$s$;
CREATE FUNCTION public.ottoq_opportunistic_scan(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_opportunistic_scan'); END$s$;
CREATE FUNCTION public.ottoq_sim_advance_flow_contract(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_flow_contract'); END$s$;
CREATE FUNCTION public.ottoq_sim_prearrival_contracts(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_prearrival_contracts'); END$s$;
CREATE FUNCTION public.ottoq_sim_confirm_commands(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_confirm_commands'); END$s$;
CREATE FUNCTION public.ottoq_sim_reconcile_charge_sessions(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_reconcile_charge_sessions'); END$s$;
CREATE FUNCTION public.ottoq_energy_orchestrate(uuid, uuid, timestamptz, integer) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_energy_orchestrate'); END$s$;
CREATE FUNCTION public.ottoq_sim_energy_controller(uuid, uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_energy_controller'); END$s$;
CREATE FUNCTION public.ottoq_sim_advance_charge_sessions(uuid, timestamptz) RETURNS SETOF integer LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_charge_sessions'); RETURN; END$s$;
CREATE FUNCTION public.ottoq_sim_advance_all_energy(uuid, uuid, timestamptz, numeric) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_all_energy'); END$s$;
CREATE FUNCTION public.ottoq_sim_advance_deployed_telemetry(uuid, timestamptz, numeric) RETURNS SETOF integer LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_deployed_telemetry'); RETURN; END$s$;
CREATE FUNCTION public.ottoq_sim_advance_wear_counters(uuid, timestamptz, numeric, integer, uuid[]) RETURNS integer LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_wear_counters'); RETURN 0; END$s$;
CREATE FUNCTION public.ottoq_comms_advance(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_comms_advance'); END$s$;
CREATE FUNCTION public.ottoq_sim_advance_service_flow(uuid, timestamptz, numeric, uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_advance_service_flow'); END$s$;
CREATE FUNCTION public.ottoq_sim_overnight_service_drain(uuid, timestamptz, uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_overnight_service_drain'); END$s$;
CREATE FUNCTION public.ottoq_sim_emit_depot_heartbeats(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_emit_depot_heartbeats'); END$s$;
CREATE FUNCTION public.ottoq_sim_recover_chargers(uuid, timestamptz, integer) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_recover_chargers'); END$s$;
CREATE FUNCTION public.ottoq_reconcile_charger_states(uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_reconcile_charger_states'); END$s$;
CREATE FUNCTION public.ottoq_oem_webhook_collect_responses() RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_oem_webhook_collect_responses'); END$s$;
CREATE FUNCTION public.ottoq_admit_stranded_vehicles(uuid, uuid, timestamptz, integer, integer) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_admit_stranded_vehicles'); END$s$;
CREATE FUNCTION public.ottoq_sim_generate_arrival_manifests(uuid, uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_generate_arrival_manifests'); END$s$;
CREATE FUNCTION public.ottoq_sim_wash_triage(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_wash_triage'); END$s$;
CREATE FUNCTION public.ottoq_sim_vehicle_exception_handler(uuid, timestamptz, uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_vehicle_exception_handler'); END$s$;
CREATE FUNCTION public.ottoq_sim_bay_fault_handler(uuid, timestamptz, uuid) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_bay_fault_handler'); END$s$;
CREATE FUNCTION ottoq.ottoq_owner_orders_tick(uuid, timestamptz) RETURNS integer LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_owner_orders_tick'); RETURN 0; END$s$;
CREATE FUNCTION twin.ottoq_arm_advance_cycles(uuid, timestamptz) RETURNS void LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_arm_advance_cycles'); END$s$;
CREATE FUNCTION public.ottoq_release_expired_tethers(timestamptz) RETURNS integer LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_release_expired_tethers'); RETURN 0; END$s$;

-- the doors' callees
CREATE FUNCTION twin.ottoq_sim_stop_charge_session(p_session_id uuid, p_reason text, p_clock timestamptz, p_message text,
  p_sim_run_id uuid) RETURNS void LANGUAGE plpgsql AS $s$
BEGIN
  INSERT INTO public.t_calls (fn, note) VALUES ('ottoq_sim_stop_charge_session', p_reason);
  UPDATE public.ocpp_sessions SET status = 'faulted' WHERE id = p_session_id;
END$s$;
CREATE FUNCTION public.ottoq_replan_after_charger_fault(uuid, uuid, uuid, text, uuid, text, timestamptz) RETURNS jsonb
  LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_replan_after_charger_fault');
  RETURN jsonb_build_object('disposition', 'requeued_same_class'); END$s$;
CREATE FUNCTION public.ottoq_record_event(p_actor_type text, p_actor_id text, p_event_type text, p_entity_type text,
  p_payload jsonb, p_severity text, p_ingest_source text, p_data_source text, p_sim_run_id uuid) RETURNS void
  LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_calls (fn, note) VALUES ('ottoq_record_event', p_event_type); END$s$;
-- the stop door's callees: the proposals' rescue step, and the depot's release (records the lock_timeout it ran under)
CREATE FUNCTION public.ottoq_promote_proposal_candidates(uuid, bigint, timestamptz) RETURNS integer LANGUAGE plpgsql AS $s$
BEGIN INSERT INTO public.t_calls (fn, note) VALUES ('ottoq_promote_proposal_candidates', current_setting('lock_timeout'));
  RETURN 0; END$s$;
CREATE FUNCTION public.ottoq_sim_release_depot(uuid, text) RETURNS jsonb LANGUAGE plpgsql AS $s$
BEGIN INSERT INTO public.t_calls (fn, note) VALUES ('ottoq_sim_release_depot', current_setting('lock_timeout'));
  RETURN jsonb_build_object('released', true); END$s$;
-- the metronome's callees
CREATE FUNCTION twin.ottoq_twin_operator_step(uuid) RETURNS jsonb LANGUAGE plpgsql AS $s$
BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_twin_operator_step'); RETURN '{}'::jsonb; END$s$;
CREATE FUNCTION public.ottoq_record_tick_failure(p_run uuid, p_phase text, p_message text, p_sqlstate text) RETURNS void
  LANGUAGE plpgsql AS $s$BEGIN INSERT INTO public.t_tick_failures (sim_run_id, phase, message, sqlstate)
  VALUES (p_run, p_phase, p_message, p_sqlstate); END$s$;
CREATE FUNCTION public.ottoq_cuopt_refresh(uuid) RETURNS bigint LANGUAGE plpgsql AS $s$
BEGIN INSERT INTO public.t_calls (fn) VALUES ('ottoq_cuopt_refresh'); RETURN NULL; END$s$;
-- NOT the live body: the kernel's choice, the two waits, and then ottoq_decide_tick lines 1226-1244 VERBATIM (A3)
CREATE FUNCTION public.ottoq_sim_decide_and_dispatch(p_sim_run_id uuid) RETURNS void LANGUAGE plpgsql AS $s$
DECLARE v_door text := (SELECT door FROM public.t_decide); v_agent text := (SELECT agent FROM public.t_decide);
        v_t0 timestamptz := clock_timestamp(); v_tick integer; v_clock timestamptz; r record;
BEGIN
  INSERT INTO public.t_calls (fn) VALUES ('ottoq_sim_decide_and_dispatch');
  SELECT tick_count, sim_clock_current INTO v_tick, v_clock FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  FOR r IN SELECT DISTINCT ON (p.entity_id) p.entity_id, p.source, p.proposal
             FROM ottoq_external_proposals p
            WHERE p.sim_run_id = p_sim_run_id AND p.status = 'pending'
            ORDER BY p.entity_id, p.created_at DESC LOOP
    INSERT INTO ottoq_decisions (sim_run_id, tick_seq, entity_id, outcome_status, enacted_action, action_context,
                                 resolved_action_context)
    VALUES (p_sim_run_id, v_tick, r.entity_id, 'enacted', r.proposal || jsonb_build_object('source', r.source),
            'stall_assignment', 'stall_assignment');
  END LOOP;
  PERFORM set_config('application_name', 'ottoq_0790_metronome_in_decide', false);
  IF v_door IS NOT NULL THEN
    WHILE NOT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = v_door AND wait_event_type = 'Lock') LOOP
      IF clock_timestamp() > v_t0 + interval '20 seconds' THEN
        RAISE EXCEPTION 'decide stub: no backend named % ever waited on a lock', v_door;
      END IF;
      PERFORM pg_sleep(0.05);
      PERFORM pg_stat_clear_snapshot();   -- pg_stat_activity is read once per transaction otherwise
    END LOOP;
  END IF;
  IF v_agent IS NOT NULL AND current_setting('ottoq_test.agent_waited', true) IS DISTINCT FROM 'yes' THEN
    PERFORM set_config('ottoq_test.agent_waited', 'yes', false);
    LOOP
      EXIT WHEN EXISTS (SELECT 1 FROM ottoq_external_proposals p
                         WHERE p.sim_run_id = p_sim_run_id AND p.created_at > v_t0);
      EXIT WHEN EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = v_agent AND wait_event_type = 'Lock');
      IF clock_timestamp() > v_t0 + interval '20 seconds' THEN
        RAISE EXCEPTION 'decide stub: the agent % never arrived', v_agent;
      END IF;
      PERFORM pg_sleep(0.05);
      PERFORM pg_stat_clear_snapshot();
    END LOOP;
  END IF;

  -- A3: close the external-proposal lifecycle for this tick — consumed
  -- (entity got an enacted decision) → 'enacted'; past-freshness → 'expired'.
  UPDATE ottoq_external_proposals p
     SET status='enacted', disposition_reason='enacted_by_kernel',
         disposed_at=clock_timestamp(), disposed_tick=v_tick
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND EXISTS (SELECT 1 FROM ottoq_decisions d
                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
                    AND d.entity_id=p.entity_id AND d.outcome_status='enacted'
                    AND d.enacted_action->>'source' = p.source);
  -- honest pre-emption: the entity was decided this tick, but NOT by this proposal
  UPDATE ottoq_external_proposals p
     SET status='superseded', disposition_reason='entity_decided_by_other_proposal',
         disposed_at=clock_timestamp(), disposed_tick=v_tick
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND EXISTS (SELECT 1 FROM ottoq_decisions d
                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
                    AND d.entity_id=p.entity_id AND d.outcome_status='enacted');
  PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, v_tick, v_clock, false);
END$s$;

-- NOT live bodies: the shapes 0790's P2 reads in them. ottoq_decide_tick enacts the run's proposals by the UPDATE its
-- line 1228 carries. ottoq_purge_prior_runs is the one function that deletes ottoq_sim_runs rows, and it is kept in the
-- live body's order with its two statements on ottoq_sim_runs verbatim (live md5 46f1f29f, read 2026-10-15 00:16:48
-- UTC): it chooses its runs once, deletes their rows in the run-scoped tables by dynamic SQL, children first (the
-- proposals among them; live reads the tables from the run-scope registry, here they are this stub's), and deletes the
-- runs' rows last. Between the two, t_hold_for_door() lets a test put a stop door inside it.
CREATE FUNCTION public.ottoq_decide_tick(p_sim_run_id uuid) RETURNS void LANGUAGE plpgsql AS $s$
BEGIN
  UPDATE ottoq_external_proposals p
     SET status='enacted', disposition_reason='enacted_by_kernel', disposed_at=clock_timestamp()
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending';
END$s$;
-- test hook: when t_decide.door names an application, wait (at most 20 s) until a backend of that name waits on a lock,
-- so the statement after the hook runs while that backend is blocked. Renames this backend '<name>_holding' first, so a
-- test can see it has reached the hook before it starts the door. Holds once per session: a demo start holds after its
-- first statement, and the purge it then calls goes straight on (the door may have lost a deadlock by then).
CREATE FUNCTION public.t_hold_for_door() RETURNS void LANGUAGE plpgsql AS $s$
DECLARE v_door text := (SELECT door FROM public.t_decide); v_t0 timestamptz := clock_timestamp();
BEGIN
  IF v_door IS NULL OR current_setting('ottoq_test.held_for_door', true) IS NOT DISTINCT FROM 'yes' THEN RETURN; END IF;
  PERFORM set_config('ottoq_test.held_for_door', 'yes', false);
  PERFORM set_config('application_name', current_setting('application_name') || '_holding', false);
  WHILE NOT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = v_door AND wait_event_type = 'Lock') LOOP
    IF clock_timestamp() > v_t0 + interval '20 seconds' THEN
      RAISE EXCEPTION 'test hook: no backend named % ever waited on a lock', v_door;
    END IF;
    PERFORM pg_sleep(0.05);
    PERFORM pg_stat_clear_snapshot();   -- pg_stat_activity is read once per transaction otherwise
  END LOOP;
END$s$;
CREATE FUNCTION public.ottoq_purge_prior_runs(p_keep_run uuid) RETURNS jsonb LANGUAGE plpgsql AS $s$
DECLARE r record; v_doomed uuid[]; v_runs int;
BEGIN
  SELECT array_agg(sim_run_id) INTO v_doomed
    FROM public.ottoq_sim_runs
   WHERE sim_run_id <> p_keep_run
     AND COALESCE(run_by,'') <> 'production_live'
     AND status <> 'running';
  IF v_doomed IS NULL OR cardinality(v_doomed) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'kept', p_keep_run, 'prior_runs_deleted', 0);
  END IF;
  FOR r IN SELECT x.s, x.t, x.c
             FROM (VALUES (1, 'public', 'ottoq_external_proposals', 'sim_run_id'), (2, 'public', 'ottoq_decisions', 'sim_run_id'),
                          (3, 'public', 'ocpp_sessions', 'sim_run_id'), (4, 'public', 'ottoq_vehicle_dispatches', 'sim_run_id'),
                          (5, 'public', 'ottoq_wear_tick_status', 'sim_run_id'), (6, 'public', 'ottoq_tick_clock_log', 'sim_run_id'))
                  AS x(n, s, t, c)
            ORDER BY x.n LOOP
    EXECUTE format('DELETE FROM %1$I.%2$I WHERE %3$I = ANY($1)', r.s, r.t, r.c)
      USING v_doomed;
  END LOOP;
  PERFORM public.t_hold_for_door();
  DELETE FROM public.ottoq_sim_runs WHERE sim_run_id = ANY(v_doomed);
  GET DIAGNOSTICS v_runs = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'kept', p_keep_run, 'prior_runs_deleted', v_runs);
END$s$;

-- ══ the live definitions, byte for byte ══

CREATE OR REPLACE FUNCTION public.ottoq_sim_advance_tick_world(p_sim_run_id uuid)
 RETURNS TABLE(out_sim_clock_after timestamp with time zone, out_tick_minutes numeric, out_telemetry_emitted integer, out_charge_advanced integer, out_completed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_wear_ids uuid[];
  v_wear_written int;
  v_run ottoq_sim_runs%ROWTYPE;
  v_tick_minutes numeric; v_new_sim_clock timestamptz; v_completed boolean := FALSE;
  v_telemetry_count int; v_tick_t0 timestamptz; v_charge_adv int; v_feed_sim boolean := true;
BEGIN
  v_tick_t0 := clock_timestamp();   -- T0 instrument: whole-tick wall clock
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id FOR UPDATE;
  IF NOT FOUND OR v_run.status NOT IN ('running') THEN out_completed:=TRUE; RETURN NEXT; RETURN; END IF;

  SELECT COALESCE(d.feed_mode, 'sim') = 'sim' INTO v_feed_sim FROM depots d WHERE d.id = v_run.depot_id;
  v_feed_sim := COALESCE(v_feed_sim, true);
  -- PLAYBACK CLOCK. 'live' = TRUE 1:1 (sim advances by REAL elapsed x speed_x, so
  -- one real second is one sim second at 1x). 'fixed' (default) keeps the historical
  -- tick_interval_seconds * time_scale behaviour so certs/benchmarks stay deterministic.
  -- The 0.05..10 clamp keeps a stalled metronome or a long GC pause from teleporting
  -- the world; it never applies in fixed mode.
  /* 0258: THE COMMENT ABOVE STATES THE INVARIANT AND NOTHING HELD IT. In 'live' mode
     v_tick_minutes is REAL ELAPSED TIME, so the sim clock itself -- not merely a stamp --
     would differ between two arms of one pair, and every duration, deadline, booking and
     charge interval downstream with it. A cert run got 'fixed' only because
     twin.ottoq_sim_start_run never writes the key: held shut by a NULL. The key is read
     EVERY tick, so it can also be set on a run already in flight, which is why the guard
     is here at the point of use rather than in the pair's pre-flight (and why a
     pre-flight read of the SCENARIO would have asserted nothing -- ottoq_scenarios has
     no such column). It REFUSES rather than coercing: a certification whose clock is not
     the clock its payload claims must not produce a verdict. Scope is exactly the two run
     classes the comment names; production and demo keep 'live' untouched.
     db/checks/0182 section 5. Measured: 0 of 980 cert/benchmark runs have ever carried it. */
  IF COALESCE(v_run.payload->>'playback_mode','fixed') = 'live'
     AND COALESCE(v_run.run_by,'') IN ('cert_harness','benchmark') THEN
    RAISE EXCEPTION 'ottoq_sim_advance_tick_world: run % is run_by=% with '
                    'playback_mode=live. A cert or benchmark run may not advance on the '
                    'wall clock -- the tick SIZE would be real elapsed time and the two '
                    'arms of a pair could never agree. Refused rather than coerced to '
                    'fixed, so the run cannot disagree with its own payload. 0258.',
                    p_sim_run_id, v_run.run_by USING ERRCODE = 'P0001';
  END IF;
  IF COALESCE(v_run.payload->>'playback_mode','fixed') = 'live' THEN
    -- TRUE 1:1. clock_timestamp() (NOT now(), which is transaction time and does
    -- not advance inside a transaction). Floor 0 -- a zero advance is correct when
    -- no real time has elapsed. The 10-minute ceiling stays as the anti-teleport guard.
    v_tick_minutes := LEAST(10.0, GREATEST(0.0,
      (EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_run.last_tick_at, clock_timestamp())))
       * COALESCE((v_run.payload->>'speed_x')::numeric, 1.0)) / 60.0));
  ELSE
    v_tick_minutes := (v_run.tick_interval_seconds::numeric * v_run.time_scale) / 60.0;
  END IF;
  v_new_sim_clock := v_run.sim_clock_current + (v_tick_minutes || ' minutes')::interval;
  IF v_new_sim_clock >= v_run.sim_clock_end THEN v_new_sim_clock := v_run.sim_clock_end; v_completed := TRUE; END IF;
  PERFORM set_config('ottoq.sim_clock', p_sim_run_id::text || '|' || v_new_sim_clock::text, true);  /* 0204: publish the tick's clock for ottoq.ottoq_run_now() */


  -- 0605: WHAT AN OWNER'S AGENT SET FOR ITS OWN CARS, applied at the tick (charge targets, service orders, holds),
  -- before the visit atoms advance and the charges advance. Inert on a run no owner touched: one index probe.
  PERFORM ottoq.ottoq_owner_orders_tick(p_sim_run_id, v_new_sim_clock);
  PERFORM ottoq_sim_advance_visit_atoms(p_sim_run_id, v_new_sim_clock);
  PERFORM ottoq_opportunistic_scan(p_sim_run_id, v_new_sim_clock);
  PERFORM ottoq_sim_advance_flow_contract(p_sim_run_id, v_new_sim_clock);
  IF v_feed_sim THEN
    PERFORM ottoq_sim_prearrival_contracts(p_sim_run_id, v_new_sim_clock);
    -- 0654: with twin_operator_door on, the twin's operators carry out OTTO-Q's directives in their own step before
    -- this tick (twin.ottoq_twin_operator_step) and answer through the v2 door, so the walk does not run here.
    IF ottoq_policy_get(p_sim_run_id, 'twin_operator_door', 0) < 1 THEN
      PERFORM ottoq_sim_confirm_commands(p_sim_run_id, v_new_sim_clock);
    END IF;
  END IF;
  -- 0445 (G178): the battery is dispatched below, after reconciliation starts this tick's sessions

  IF v_feed_sim THEN
    -- THE ARM MOVES — AND IT MOVES FIRST. This ran after the charge block until
    -- the live run of 2026-08-12 showed why that cannot work: a mate opened in the
    -- previous tick is only walkable in this one, and the charge block below can
    -- stop the session and open a demate over the top of it before the advancer
    -- ever sees it. The mate was clobbered every time, 'align' was never reached,
    -- and no registration was ever recorded. Walking the arm first settles any
    -- pending mate — writing its registration — before anything can end the charge
    -- underneath it. Physics, so it belongs in the world half; wrapped because the
    -- tick must survive anything the robot does.
    BEGIN PERFORM twin.ottoq_arm_advance_cycles(p_sim_run_id, v_new_sim_clock);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm advance: %', SQLERRM; END;
    UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_new_sim_clock
     WHERE depot_id = v_run.depot_id AND station_state <> 'Faulted';
    PERFORM ottoq_sim_reconcile_charge_sessions(p_sim_run_id, v_new_sim_clock);
  END IF;
  /* 0445 (G178): THE BATTERY ANSWERS THE LOAD IT WILL SEE. The orchestrator sums the ACTIVE sessions' rates,
     so it must run after reconciliation has started this tick's sessions and before energy is delivered;
     above the charge block it answered one tick late (a whole billing interval at 30 sim-min per tick). */
  IF (v_run.policy IS NULL OR v_run.policy = 'otto_q') AND ottoq_policy_get(p_sim_run_id,'energy_orchestration_enabled',1) > 0 THEN
    PERFORM ottoq_energy_orchestrate(p_sim_run_id, v_run.depot_id, v_new_sim_clock, v_run.tick_count + 1);
  END IF;
  IF v_feed_sim THEN
    PERFORM ottoq_sim_energy_controller(p_sim_run_id, v_run.depot_id, v_new_sim_clock);
  END IF;
  IF v_feed_sim THEN
    SELECT COUNT(*) INTO v_charge_adv FROM ottoq_sim_advance_charge_sessions(p_sim_run_id, v_new_sim_clock);
    PERFORM ottoq_sim_advance_all_energy(v_run.depot_id, p_sim_run_id, v_new_sim_clock, v_tick_minutes);
  ELSE
    v_charge_adv := 0;
  END IF;
  IF v_feed_sim THEN
  -- AP-2 R1: snapshot the in-flight dispatch set BEFORE telemetry mutates it
  SELECT array_agg(d.dispatch_id) INTO v_wear_ids
    FROM ottoq_vehicle_dispatches d
   WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning');
  SELECT COUNT(*) INTO v_telemetry_count FROM ottoq_sim_advance_deployed_telemetry(p_sim_run_id, v_new_sim_clock, v_tick_minutes);
  v_wear_written := -1;
  BEGIN
    v_wear_written := ottoq_sim_advance_wear_counters(
      p_sim_run_id, v_new_sim_clock, v_tick_minutes, v_run.tick_count + 1, COALESCE(v_wear_ids, ARRAY[]::uuid[]));
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'wear_counters: %', SQLERRM; END;
  BEGIN
    INSERT INTO ottoq_wear_tick_status (sim_run_id, tick_seq, sim_clock, attempted, written, note)
    VALUES (p_sim_run_id, v_run.tick_count + 1, v_new_sim_clock,
            COALESCE(array_length(v_wear_ids,1),0), GREATEST(v_wear_written,0),
            CASE WHEN v_wear_written < 0 THEN 'advancer raised' ELSE NULL END)
    ON CONFLICT (sim_run_id, tick_seq) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  ELSE
    v_telemetry_count := 0;
  END IF;
  BEGIN PERFORM ottoq_comms_advance(p_sim_run_id, v_new_sim_clock); EXCEPTION WHEN OTHERS THEN RAISE WARNING 'comms_advance: %', SQLERRM; END;
  PERFORM ottoq_sim_advance_service_flow(p_sim_run_id, v_new_sim_clock, v_tick_minutes, v_run.depot_id);
  IF v_feed_sim THEN PERFORM ottoq_sim_overnight_service_drain(v_run.depot_id, v_new_sim_clock, p_sim_run_id); END IF;

  UPDATE ottoq_sim_runs SET sim_clock_current=v_new_sim_clock, last_tick_at=v_tick_t0,
         -- LIVE-CLOCK COUPLING FIX 2026-08-01: publish the ACTUAL elapsed sim-minutes
         -- so every per-tick RATE cap downstream scales with the real tick size.
         -- Fixed mode writes exactly 30 = the historical fallback (no behaviour change).
         payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object('tick_minutes_actual', v_tick_minutes),  -- anchor at tick START so the tick's own compute is inside the next elapsed
         next_tick_due_at=clock_timestamp()+(v_run.tick_interval_seconds||' seconds')::interval,
         tick_count=tick_count+1, status=CASE WHEN v_completed THEN 'completed' ELSE status END,
         ended_at=CASE WHEN v_completed THEN NOW() ELSE ended_at END
   WHERE sim_run_id=p_sim_run_id;

  IF v_feed_sim THEN
    PERFORM ottoq_sim_emit_depot_heartbeats(v_run.depot_id, v_new_sim_clock);
    UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_new_sim_clock WHERE depot_id = v_run.depot_id AND station_state <> 'Faulted';
    PERFORM ottoq_sim_recover_chargers(v_run.depot_id, v_new_sim_clock, 50);
  END IF;
  -- ═══════════ 0011-TETHER: THE ROBOT HAS FINISHED DEMATING ═══════════
  -- Single releaser for the robotic tether: clears the deadline AND frees the stall the
  -- arm was holding. Deliberately placed BEFORE the charger reconcile so a plug freed
  -- here is healed to Available in the SAME tick instead of lagging one behind. Called
  -- from the world tick, not the decide tick, because it is physics, not a decision --
  -- and because the world tick runs every metronome beat while decide runs on alternate
  -- beats. Self-contained: the sweep never raises, and this wrapper is belt-and-braces.
  BEGIN PERFORM public.ottoq_release_expired_tethers(v_new_sim_clock);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'tether release: %', SQLERRM; END;
  BEGIN PERFORM ottoq_reconcile_charger_states(v_run.depot_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'charger reconcile: %', SQLERRM; END;
  BEGIN PERFORM ottoq_oem_webhook_collect_responses();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'webhook reconcile: %', SQLERRM; END;
  BEGIN PERFORM ottoq_admit_stranded_vehicles(v_run.depot_id, p_sim_run_id, v_new_sim_clock, 80, 12);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'admit stranded: %', SQLERRM; END;

  UPDATE vehicles SET current_state='charge_complete_holding'::vehicle_state, last_state_change=v_new_sim_clock
   WHERE home_depot_id=v_run.depot_id AND category='autonomous'
     AND current_state='arrived_at_gate' AND current_soc>=85;

  IF v_feed_sim THEN
    PERFORM ottoq_sim_generate_arrival_manifests(v_run.depot_id, p_sim_run_id);
  END IF;
  PERFORM ottoq_sim_wash_triage(v_run.depot_id, v_new_sim_clock);
  IF v_feed_sim THEN
    PERFORM ottoq_sim_vehicle_exception_handler(v_run.depot_id, v_new_sim_clock, p_sim_run_id);
    PERFORM ottoq_sim_bay_fault_handler(v_run.depot_id, v_new_sim_clock, p_sim_run_id);
  END IF;

  -- T0 instrument: authoritative wall-clock + compute cost, one row per tick.
  -- clock_timestamp() (not now()) so batch-stepped ticks are individually timed.
  BEGIN
    INSERT INTO ottoq_tick_clock_log (
      sim_run_id, tick_seq, real_started_at, real_ended_at,
      sim_clock_before, sim_clock_after, tick_compute_ms, sim_advance_s,
      playback_mode, speed_x)
    VALUES (
      p_sim_run_id, COALESCE(v_run.tick_count,0) + 1, v_tick_t0, clock_timestamp(),
      v_run.sim_clock_current, v_new_sim_clock,
      round(EXTRACT(EPOCH FROM (clock_timestamp() - v_tick_t0))::numeric * 1000, 1),
      round(EXTRACT(EPOCH FROM (v_new_sim_clock - v_run.sim_clock_current))::numeric, 1),
      COALESCE(v_run.payload->>'playback_mode','fixed'),
      COALESCE((v_run.payload->>'speed_x')::numeric, 1.0))
    ON CONFLICT (sim_run_id, tick_seq) DO UPDATE
      SET real_ended_at   = EXCLUDED.real_ended_at,
          tick_compute_ms = EXCLUDED.tick_compute_ms;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'tick clock log: %', SQLERRM;
  END;

  out_sim_clock_after:=v_new_sim_clock; out_tick_minutes:=v_tick_minutes;
  out_telemetry_emitted:=v_telemetry_count; out_charge_advanced:=v_charge_adv; out_completed:=v_completed;
  RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_twin_inject_charger_fault(p_sim_run_id uuid, p_charger_id uuid DEFAULT NULL::uuid, p_repair_minutes numeric DEFAULT 60, p_actor text DEFAULT 'cockpit_operator'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run RECORD; v_charger uuid; v_stall_code text; v_had_vehicle boolean; v_res jsonb;
  v_sess RECORD; v_stopped int := 0;   -- 0550
  v_repair numeric := LEAST(GREATEST(COALESCE(p_repair_minutes, 60), 5), 480);
BEGIN
  -- 0552 (G285): the run's row first, FOR UPDATE, as the tick takes it. A door called during a tick waits for the
  -- tick to commit instead of deadlocking with it over the sessions and stalls both write.
  SELECT sim_run_id, depot_id, status, sim_clock_current INTO v_run
    FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id
     FOR UPDATE;
  IF v_run.sim_run_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'run_not_found'); END IF;
  IF v_run.status <> 'running' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'run_not_running', 'status', v_run.status);
  END IF;

  -- The target is always a charger at the RUN'S depot (rule 8). Given one, it must be; given none, take the
  -- DC fast charger whose loss is visible -- one with a vehicle on it first -- in a fixed order.
  SELECT c.charger_id, s.stall_code, (s.current_vehicle_id IS NOT NULL)
    INTO v_charger, v_stall_code, v_had_vehicle
    FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = v_run.depot_id AND c.depot_id = v_run.depot_id
     AND c.station_state <> 'Faulted'
     AND (p_charger_id IS NULL OR c.charger_id = p_charger_id)
     AND (p_charger_id IS NOT NULL OR s.stall_type::text = 'dcfc')
   ORDER BY (s.current_vehicle_id IS NOT NULL) DESC, s.stall_code
   LIMIT 1;
  IF v_charger IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'reason', CASE WHEN p_charger_id IS NULL THEN 'no_healthy_dcfc_charger_at_this_depot'
                     ELSE 'charger_not_at_this_depot_or_already_faulted' END);
  END IF;

  -- 0550 (G281): THE HARDWARE FAILS FIRST. A charger that faults ends the session it is running. The twin's own
  -- faults do that through twin.ottoq_sim_stop_charge_session with a 'fault.*' reason, which closes the session, marks
  -- the charger Faulted and re-queues the car to finish (or holds it) by the one rule. The door takes the same path, so
  -- the fault it injects is one the world sees. Before 0550 it only reported the fault, and the car charged on through
  -- it (0408 §17). The report below then takes the stall out of the pool and replans any car still reserved to it.
  FOR v_sess IN
    SELECT o.id FROM public.ocpp_sessions o JOIN public.stalls s ON s.id = o.stall_id
     WHERE s.ocpp_charger_id = v_charger AND o.sim_run_id = p_sim_run_id AND o.status = 'active'
     ORDER BY o.id
  LOOP
    PERFORM twin.ottoq_sim_stop_charge_session(v_sess.id, 'fault.operator_injected', v_run.sim_clock_current,
              'Injected from the cockpit; repairs in ' || v_repair || ' sim-min', p_sim_run_id);
    v_stopped := v_stopped + 1;
  END LOOP;

  v_res := twin.ottoq_report_charger_fault(
             p_charger_id => v_charger, p_actor => p_actor, p_fault_code => 'operator_injected',
             p_note => 'injected from the cockpit; repairs in ' || v_repair || ' sim-min');

  -- report_charger_fault stamps now() (REAL time). twin.ottoq_sim_recover_chargers compares the stamp with the
  -- SIM clock plus last_fault_payload.repair_minutes, so the fault is re-stamped on the sim clock here.
  UPDATE public.ottoq_ocpp_chargers
     SET station_state_changed_at = v_run.sim_clock_current,
         last_fault_payload = COALESCE(last_fault_payload, '{}'::jsonb)
                              || jsonb_build_object('repair_minutes', v_repair, 'injected_via', 'cockpit',
                                                    'sim_run_id', p_sim_run_id)
   WHERE charger_id = v_charger AND station_state = 'Faulted';

  RETURN jsonb_build_object('ok', COALESCE((v_res->>'ok')::boolean, false),
    'charger_id', v_charger, 'stall_code', v_stall_code, 'had_vehicle', v_had_vehicle,
    'repair_minutes', v_repair, 'sessions_stopped', v_stopped, 'faulted_at_sim', v_run.sim_clock_current,
    'recovers_at_sim', v_run.sim_clock_current + make_interval(secs => (v_repair * 60)::double precision),
    'report', v_res);
END $function$;

CREATE OR REPLACE FUNCTION twin.ottoq_report_charger_fault(p_charger_id uuid, p_actor text DEFAULT 'depot_tech'::text, p_fault_code text DEFAULT 'TECH_CONFIRMED_FAULT'::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_run uuid; v_clock timestamptz;
  v_stall RECORD; v_veh RECORD; v_plan jsonb;
  v_moved int := 0; v_parked int := 0; v_out jsonb := '[]'::jsonb;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_ocpp_chargers WHERE charger_id = p_charger_id;
  IF v_depot IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason','charger_not_found'); END IF;
  -- 0552 (G285): the run's row first, FOR UPDATE, as the tick takes it, before the charger and the stall.
  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM ottoq_sim_runs
   WHERE depot_id = v_depot AND status='running' ORDER BY started_at DESC LIMIT 1
     FOR UPDATE;
  v_clock := COALESCE(v_clock, now());

  -- WORLD FACT: the hardware failed.
  UPDATE ottoq_ocpp_chargers
     SET station_state='Faulted', last_fault_code=p_fault_code, station_state_changed_at=now()
   WHERE charger_id = p_charger_id;

  FOR v_stall IN
    SELECT s.id, s.current_vehicle_id, s.reserved_by, s.stall_type::text AS stype
      FROM stalls s WHERE s.ocpp_charger_id = p_charger_id
     ORDER BY s.id   /* 0054: run-stable cursor order */
  LOOP
    FOR v_veh IN
      SELECT v.* FROM vehicles v
       WHERE v.id IN (v_stall.current_vehicle_id, v_stall.reserved_by) AND v.id IS NOT NULL
         -- 0550 (G281): a car the robot is unplugging from this stall has finished here. Its session is closed and it
         -- leaves when the demate ends (ottoq_release_expired_tethers). It is not displaced, so it is not replanned: a
         -- replan would reserve it a stall and send it a command for a move the world is already making. A car still
         -- being plugged in (direction 'mate') is displaced and is replanned.
         AND NOT (v.robotic_tether_until IS NOT NULL AND v.robotic_tether_stall_id = v_stall.id
                  AND COALESCE(v.robotic_tether_direction, 'demate') = 'demate')
       ORDER BY v.id   /* 0054: run-stable cursor order */
    LOOP
      -- WORLD FACT: this stall leaves the pool. Vacate before re-placing.
      UPDATE stalls SET reserved_by=NULL, reserved_at=NULL, reservation_expires_at=NULL,
             current_vehicle_id=NULL, status='maintenance'
       WHERE id = v_stall.id;

      -- DECISION (OTTO-Q): where does the displaced vehicle go?
      v_plan := ottoq_replan_after_charger_fault(
                  v_veh.id, v_run, v_depot, v_stall.stype, p_charger_id, p_fault_code, v_clock);

      IF (v_plan->>'disposition') = 'requeued_same_class' THEN
        v_moved := v_moved + 1;
      ELSIF (v_plan->>'disposition') = 'temp_parked_awaiting_charger' THEN
        v_parked := v_parked + 1;
      END IF;
      v_out := v_out || jsonb_build_array(v_plan);
    END LOOP;
    -- stall with no vehicle on it: still take it out of the pool
    UPDATE stalls SET status='maintenance' WHERE id=v_stall.id AND status <> 'maintenance';
  END LOOP;

  BEGIN
    PERFORM ottoq_record_event(p_actor_type:='depot_tech', p_actor_id:=p_actor,
      p_event_type:='ops.charger_fault_confirmed', p_entity_type:='system',
      p_payload:=jsonb_build_object('charger_id',p_charger_id,'fault',p_fault_code,'note',p_note,
        'requeued',v_moved,'temp_parked',v_parked,'dispositions',v_out),
      p_severity:='warning', p_ingest_source:='production', p_data_source:='production',
      p_sim_run_id:=v_run);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok',true,'charger_id',p_charger_id,'fault',p_fault_code,
    'requeued_same_class',v_moved,'temp_parked',v_parked,'vehicles',v_out);
END
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_sim_stop_and_reset(p_sim_run_id uuid, p_reason text DEFAULT 'operator_stop'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_marked boolean;
BEGIN
  -- 0092: the teardown's own trigger events must carry the run they tear down;
  -- once mark_stopped flips the status, the lookup path can no longer find it.
  PERFORM set_config('ottoq.sim_run_id', p_sim_run_id::text, true);
  PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, NULL, NULL, true);
  v_marked := ottoq_sim_mark_stopped(p_sim_run_id, p_reason);
  RETURN ottoq_sim_release_depot(p_sim_run_id, p_reason)
         || jsonb_build_object('marked_stopped', v_marked);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_sim_mark_stopped(p_sim_run_id uuid, p_reason text DEFAULT 'operator_stop'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_hit int;
BEGIN
  -- Deliberately short: if we cannot have the row in 8 s, the caller should cancel
  -- whatever is holding it and try again rather than queue behind a doomed tick.
  PERFORM set_config('lock_timeout','8000', true);

  UPDATE ottoq_sim_runs
     SET status           = 'completed',
         ended_at         = COALESCE(ended_at, now()),
         next_tick_due_at = NULL,
         failure_reason   = COALESCE(failure_reason, p_reason)
   WHERE sim_run_id = p_sim_run_id
     AND status IN ('running','paused');
  GET DIAGNOSTICS v_hit = ROW_COUNT;

  RETURN v_hit > 0;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_dispose_external_proposals(p_sim_run_id uuid, p_tick_seq bigint DEFAULT NULL::bigint, p_sim_clock timestamp with time zone DEFAULT NULL::timestamp with time zone, p_finalize boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_clock timestamptz;
  v_wall  timestamptz := clock_timestamp();
  v_n     integer := 0;
BEGIN
  SELECT COALESCE(p_sim_clock, r.sim_clock_current, v_wall)
    INTO v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = p_sim_run_id;
  v_clock := COALESCE(v_clock, p_sim_clock, v_wall);

  -- ═══════════ 0358: RESCUE BEFORE REFUSAL ═══════════
  -- G71: 74% of refusals named a stall that was ALREADY HELD when the proposal
  -- was made -- proposer staleness, not contention. If the proposal carries a
  -- ranked candidate set, take the first still-feasible one and leave the row
  -- pending for the next tick's enactment instead of refusing it outright.
  -- Runs BEFORE the UPDATE below so that UPDATE re-reads the promoted target and
  -- no longer has grounds to refuse it.
  -- Never allowed to abort disposal: if promotion fails, pending rows must still
  -- be disposed or they accumulate forever.
  BEGIN
    PERFORM public.ottoq_promote_proposal_candidates(
              p_sim_run_id, p_tick_seq, v_clock);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0358 promote_proposal_candidates: %', SQLERRM;
  END;

  UPDATE public.ottoq_external_proposals p
     SET status = CASE
                    WHEN p_finalize THEN 'expired'
                    WHEN GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                                  p.created_at + interval '35 minutes') < v_wall THEN 'expired'
                    ELSE 'refused'
                  END,
         disposition_reason = CASE
           WHEN p_finalize THEN 'run_finalized'
           WHEN GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                         p.created_at + interval '35 minutes') < v_wall THEN 'ttl_elapsed'
           WHEN COALESCE(p.proposal->>'abstain', '') IN ('true', 't', '1')
             THEN 'proposer_abstained'
           WHEN COALESCE(p.proposal->>'stall_id', '') !~
                '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
             THEN 'invalid_stall_id'
           WHEN NOT EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid)
             THEN 'stall_missing'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid
                AND s.current_vehicle_id IS NOT NULL)
             THEN 'stall_occupied'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid
                AND s.reserved_by IS NOT NULL
                AND s.reserved_by <> p.entity_id
                AND (s.reservation_expires_at IS NULL OR s.reservation_expires_at > v_clock))
             THEN 'stall_reserved'
           WHEN NOT EXISTS (
             SELECT 1 FROM public.stalls s
              JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
                WHERE s.id = (p.proposal->>'stall_id')::uuid
                  AND c.station_state = 'Available')
             THEN 'charger_unavailable'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
                WHERE s.id = (p.proposal->>'stall_id')::uuid
                  AND c.last_heartbeat_at < v_clock - interval '90 seconds')
             THEN 'charger_heartbeat_stale'
           ELSE 'target_no_longer_eligible'
         END,
         disposed_at = v_wall,
         disposed_tick = p_tick_seq
   WHERE p.sim_run_id = p_sim_run_id
     AND p.status = 'pending'
     AND (
       p_finalize
       OR GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                   p.created_at + interval '35 minutes') < v_wall
       OR (
         p.action_context = 'stall_assignment'
         AND (
           COALESCE(p.proposal->>'stall_id', '') !~
             '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
           OR NOT EXISTS (
             SELECT 1
               FROM public.stalls s
               JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
              WHERE s.id = CASE
                WHEN COALESCE(p.proposal->>'stall_id', '') ~
                     '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
                THEN (p.proposal->>'stall_id')::uuid
                ELSE NULL
              END
                AND s.current_vehicle_id IS NULL
                AND (s.reserved_by IS NULL OR s.reserved_by = p.entity_id
                     OR s.reservation_expires_at <= v_clock)
                AND c.station_state = 'Available'
                AND c.last_heartbeat_at >= v_clock - interval '90 seconds'
           )
         )
       )
     );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE PROCEDURE public.ottoq_demo_metronome(IN p_budget_s integer DEFAULT 50)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_start timestamptz := clock_timestamp();
  v_run RECORD; v_advanced timestamptz; v_interval numeric; v_base numeric := 6.0;
  v_any boolean; v_window_ms numeric; v_req bigint;
  v_max_ticks int; v_floor numeric; v_max_real_min numeric; v_stop_reason text;
  v_fire_beat_at timestamptz;
  v_tick_t0 timestamptz;
  v_worst_tick_s numeric := 0;
  v_ceiling_s numeric;
  v_reserve_s numeric;
  v_guard_on boolean := true;
  v_elapsed_s numeric;
BEGIN
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  BEGIN
    SELECT s.setting::numeric / 1000.0 INTO v_ceiling_s
      FROM pg_settings s WHERE s.name = 'statement_timeout';
  EXCEPTION WHEN OTHERS THEN
    v_ceiling_s := 0;   -- unreadable ceiling => guard stands down rather than guessing
  END;
  v_ceiling_s := COALESCE(v_ceiling_s, 0);

  LOOP
    SELECT EXISTS (
      SELECT 1 FROM ottoq_sim_runs
      WHERE status = 'running'
        AND COALESCE(run_by,'') NOT IN ('production_live','cert_harness')
    ) INTO v_any;
    EXIT WHEN NOT v_any;

    FOR v_run IN
      SELECT sim_run_id,
             COALESCE((payload->>'speed_x')::numeric, demo_speed_x, 1.0) AS spd,
             COALESCE(payload->>'playback_mode','fixed') AS pmode,
             next_tick_due_at, started_at,
             depot_id, COALESCE(policy,'otto_q') AS policy, COALESCE(tick_count,0) AS ticks
      FROM ottoq_sim_runs
      WHERE status = 'running'
        AND COALESCE(run_by,'') NOT IN ('production_live','cert_harness')
    LOOP
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;
      v_fire_beat_at := NULL;

      v_guard_on := ottoq_policy_get(v_run.sim_run_id, 'metronome_ceiling_guard', 1) >= 1;
      IF v_guard_on AND v_ceiling_s > 0 THEN
        v_elapsed_s := EXTRACT(EPOCH FROM (clock_timestamp() - v_start));
        v_reserve_s := GREATEST(v_worst_tick_s * 1.5, 15.0);
        EXIT WHEN v_elapsed_s + v_reserve_s > v_ceiling_s * 0.9;
      END IF;

      v_stop_reason := NULL;
      IF v_run.pmode = 'live' THEN
        v_max_ticks    := GREATEST(10, ottoq_policy_get(v_run.sim_run_id, 'demo_max_ticks_live', 5000)::int);
        v_max_real_min := GREATEST(1, ottoq_policy_get(v_run.sim_run_id, 'demo_max_real_minutes', 60));
      ELSE
        v_max_ticks    := GREATEST(10, ottoq_policy_get(v_run.sim_run_id, 'demo_max_ticks', 240)::int);
        v_max_real_min := NULL;
      END IF;

      IF v_run.ticks >= v_max_ticks THEN
        v_stop_reason := 'tick ceiling ' || v_max_ticks || ' reached';
      ELSIF v_max_real_min IS NOT NULL
        AND EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_run.started_at, clock_timestamp())))/60.0
            >= v_max_real_min THEN
        v_stop_reason := 'live-mode real-time ceiling ' || round(v_max_real_min,1) || ' real-min reached';
      END IF;

      IF v_stop_reason IS NOT NULL THEN
        BEGIN
          PERFORM set_config('lock_timeout', '8000', true);
          PERFORM ottoq_sim_stop_and_reset(
            v_run.sim_run_id,
            'auto-stopped by metronome: ' || v_stop_reason || ' (perpetuity backstop)');
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'metronome ceiling-stop % failed: % — forcing status', v_run.sim_run_id, SQLERRM;
          UPDATE ottoq_sim_runs
             SET status = 'completed',
                 ended_at = COALESCE(ended_at, now()),
                 failure_reason = COALESCE(failure_reason, v_stop_reason || '; forced stop')
           WHERE sim_run_id = v_run.sim_run_id;
        END;
        COMMIT;
        CONTINUE;
      END IF;

      v_floor := GREATEST(0.2, ottoq_policy_get(v_run.sim_run_id, 'tick_cadence_floor_s', 2.0));
      IF v_run.pmode = 'live' THEN
        v_interval := GREATEST(v_floor, v_base / GREATEST(v_run.spd, 0.25));
      ELSE
        v_interval := GREATEST(0.2, v_base / GREATEST(v_run.spd, 0.25));
      END IF;
      CONTINUE WHEN v_run.next_tick_due_at IS NOT NULL AND clock_timestamp() < v_run.next_tick_due_at;

      v_tick_t0 := clock_timestamp();
      -- 0654: with twin_operator_door on, the twin's operators answer OTTO-Q's directives in their own transaction,
      -- before the world moves: acks no longer happen inside OTTO-Q's.
      IF ottoq_policy_get(v_run.sim_run_id, 'twin_operator_door', 0) >= 1 THEN
        BEGIN
          PERFORM set_config('lock_timeout', '8000', true);
          PERFORM twin.ottoq_twin_operator_step(v_run.sim_run_id);
        EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome operators % failed: %', v_run.sim_run_id, SQLERRM;
          PERFORM public.ottoq_record_tick_failure(v_run.sim_run_id, 'operators', SQLERRM, SQLSTATE); END;
        COMMIT;
      END IF;
      v_advanced := NULL;
      BEGIN
        PERFORM set_config('lock_timeout', '8000', true);
        SELECT out_sim_clock_after INTO v_advanced FROM public.ottoq_sim_advance_tick_world(v_run.sim_run_id) LIMIT 1;
      EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome world % failed: %', v_run.sim_run_id, SQLERRM;
        PERFORM public.ottoq_record_tick_failure(v_run.sim_run_id, 'world', SQLERRM, SQLSTATE); END;

      IF v_advanced IS NOT NULL THEN
        IF (v_run.ticks % 2) = 1 THEN
          BEGIN
            PERFORM set_config('lock_timeout', '8000', true);
            PERFORM public.ottoq_sim_decide_and_dispatch(v_run.sim_run_id);
          EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome decide % failed: %', v_run.sim_run_id, SQLERRM;
            PERFORM public.ottoq_record_tick_failure(v_run.sim_run_id, 'decide', SQLERRM, SQLSTATE); END;
        ELSE
          IF v_run.policy = 'otto_q' THEN
            v_window_ms := ottoq_policy_get(v_run.sim_run_id, 'cuopt_solve_window_ms', 4000);
            IF v_window_ms > 0 THEN
              v_req := NULL;
              BEGIN
                PERFORM set_config('lock_timeout', '8000', true);
                v_req := ottoq_cuopt_refresh(v_run.sim_run_id);
              EXCEPTION WHEN OTHERS THEN NULL; END;
              v_fire_beat_at := clock_timestamp();
            END IF;
          END IF;
        END IF;
      END IF;

      v_worst_tick_s := GREATEST(v_worst_tick_s,
                                 EXTRACT(EPOCH FROM (clock_timestamp() - v_tick_t0)));

      UPDATE ottoq_sim_runs
         SET next_tick_due_at = clock_timestamp() + make_interval(secs => v_interval),
             payload = CASE WHEN v_fire_beat_at IS NOT NULL
                            THEN COALESCE(payload,'{}'::jsonb)
                                 || jsonb_build_object('cuopt_fire_beat_at', v_fire_beat_at)
                            ELSE payload END
       WHERE sim_run_id = v_run.sim_run_id;
      COMMIT;
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;
    END LOOP;
    EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;

    IF v_guard_on AND v_ceiling_s > 0
       AND EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) + GREATEST(v_worst_tick_s * 1.5, 15.0)
           > v_ceiling_s * 0.9 THEN
      EXIT;
    END IF;

    PERFORM pg_sleep(0.4);
  END LOOP;
END;
$procedure$;

-- the proposal path, live: who is calling, a proposal and a batch of them, and the evidence ledger's capture

CREATE OR REPLACE FUNCTION public.ottoq_caller_identity()
 RETURNS TABLE(trust text, jwt_role text, auth_uid uuid, db_session_user text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0198. Who is calling, decided by the SERVER from what PostgREST or the
  -- session actually established -- never from an argument.
  --   system    : no JWT at all (pg_cron, a migration, psql as postgres) or
  --               the service_role key (edge functions). Trusted to name
  --               itself, and recorded as having done so.
  --   operator  : the authenticated role with a real auth.uid().
  --   anonymous : the anon key, or an authenticated JWT with no subject.
  SELECT CASE
           WHEN auth.role() IS NULL                                   THEN 'system'
           WHEN auth.role() = 'service_role'                          THEN 'system'
           WHEN auth.role() = 'authenticated' AND auth.uid() IS NOT NULL THEN 'operator'
           ELSE 'anonymous'
         END,
         auth.role(),
         auth.uid(),
         session_user::text;
$function$
;
CREATE OR REPLACE FUNCTION public.ottoq_submit_external_proposal(p_sim_run_id uuid, p_depot_id uuid, p_action_context text, p_entity_type text, p_entity_id uuid, p_proposal jsonb, p_source text DEFAULT 'external'::text, p_ttl_seconds integer DEFAULT 120)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_id uuid;
  v_who RECORD;
  v_source text;
  v_role text;
BEGIN
  SELECT * INTO v_who FROM public.ottoq_caller_identity();

  -- 0198. Identity is the server's to assign.
  IF v_who.trust = 'anonymous' THEN
    RAISE EXCEPTION 'OTTOQ_PROPOSAL_UNAUTHENTICATED: an anonymous caller cannot propose'
      USING ERRCODE = '42501';
  ELSIF v_who.trust = 'system' THEN
    -- cron (postgres), a migration, or an edge function (service_role): the
    -- declared source names the proposer (cuopt, ottoq_service_priority, ...).
    v_source := COALESCE(NULLIF(p_source, ''), 'external');
    v_role   := 'system:' || COALESCE(v_who.jwt_role, 'db:' || v_who.db_session_user);
  ELSE
    -- an operator: the source IS the operator, whatever the client typed.
    v_source := 'operator:' || v_who.auth_uid::text;
    v_role   := 'operator:authenticated';
  END IF;

  -- 0241 / POSTURE A (SOLVER_STATE.md 8.2; step 2 of the 8.3 sequence).
  -- A certification arm hears only the proposers it was certified with.
  -- 0105 and 0152 quiesce the proposers this repository owns; nothing
  -- stopped an agent proposing into a cert run through this door, and if
  -- one did the pair would report "failed" over fourteen hashes with no
  -- hint that a stranger was in the room.
  --
  -- Checked on v_source, the SERVER-derived source, not on p_source: an
  -- operator is 'operator:<uuid>' and can never be registered.
  --
  -- Refused BEFORE the supersede below, so a refused proposal cannot even
  -- displace a pending one on its way out.
  --
  -- A REPLAY is unaffected and deliberately not on the registry:
  -- ottoq_proposal_replay_inject (0237) writes the table directly and never
  -- comes through here. Being a replay is its own admission, which keeps
  -- Posture A and Posture B independent of each other.
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
              WHERE r.sim_run_id = p_sim_run_id AND r.run_by = 'cert_harness')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_certified_proposers cp
                      WHERE cp.source = v_source) THEN
    RAISE EXCEPTION 'OTTOQ_PROPOSAL_REFUSED_CERT: proposer % is not a certified proposer and run % is a certification arm (Posture A). Register it in ottoq_certified_proposers, or record the stream and replay it -- ottoq_proposal_replay_capture then ottoq_determinism_pair_replay.', v_source, p_sim_run_id
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.ottoq_external_proposals
     SET status='superseded',
         disposition_reason='newer_proposal_same_entity',
         disposed_at=clock_timestamp(),
         disposed_tick=(SELECT r.tick_count FROM public.ottoq_sim_runs r
                         WHERE r.sim_run_id=p_sim_run_id)
   WHERE sim_run_id=p_sim_run_id AND action_context=p_action_context
     AND entity_type=p_entity_type AND entity_id=p_entity_id AND status='pending'
     AND NOT (
           public.ottoq_policy_get(p_sim_run_id, 'proposer_rank_protects_supersede', 0) >= 1
       AND COALESCE((SELECT pp.rank FROM public.ottoq_proposer_precedence pp
                      WHERE pp.source = public.ottoq_external_proposals.source), 2147483647)
         < COALESCE((SELECT pp.rank FROM public.ottoq_proposer_precedence pp
                      WHERE pp.source = v_source), 2147483647));
  INSERT INTO public.ottoq_external_proposals
    (sim_run_id,depot_id,action_context,entity_type,entity_id,proposal,source,status,expires_at,
     declared_source, submitted_by_role, submitted_by, tick_seq)
  VALUES (p_sim_run_id,p_depot_id,p_action_context,p_entity_type,p_entity_id,p_proposal,v_source,'pending',
          now() + (p_ttl_seconds || ' seconds')::interval,
          p_source, v_role, v_who.auth_uid,
          -- 0236: the tick is the run's to state, not the caller's.
          (SELECT r.tick_count FROM public.ottoq_sim_runs r
            WHERE r.sim_run_id = p_sim_run_id))
  RETURNING proposal_id INTO v_id;
  RETURN v_id;
END; $function$
;
CREATE OR REPLACE FUNCTION public.ottoq_proposer_submit_batch(p_sim_run_id uuid, p_depot_id uuid, p_source text, p_rows jsonb, p_fire jsonb, p_ttl_seconds integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_row     jsonb;
  v_id      uuid;
  v_ids     uuid[] := ARRAY[]::uuid[];
  v_n       integer := 0;
  v_status  text;
  v_err     text;
  v_tick    integer;
  v_fire_id bigint;
  v_eff     text;
  v_fire    jsonb := COALESCE(p_fire, '{}'::jsonb);
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR NULLIF(p_source, '') IS NULL THEN
    RAISE EXCEPTION 'ottoq_proposer_submit_batch: sim_run_id, depot_id and source are all required'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(COALESCE(p_rows, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'ottoq_proposer_submit_batch: p_rows must be a jsonb array, got %',
                    jsonb_typeof(p_rows) USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_ttl_seconds, 0) < 1 THEN
    RAISE EXCEPTION 'ottoq_proposer_submit_batch: p_ttl_seconds must be >= 1' USING ERRCODE = '22023';
  END IF;

  SELECT r.tick_count INTO v_tick FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ottoq_proposer_submit_batch: run % does not exist', p_sim_run_id
      USING ERRCODE = '22023';
  END IF;

  -- THE BATCH IS ONE SUB-TRANSACTION. A refusal on row k rolls back rows 1..k-1
  -- too: a half-submitted plan is not a plan, and the ledger row says exactly
  -- what happened instead of raising past the caller.
  BEGIN
    FOR v_row IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
      v_id := public.ottoq_submit_external_proposal(
                p_sim_run_id, p_depot_id,
                v_row->>'action_context', v_row->>'entity_type',
                (v_row->>'entity_id')::uuid, v_row->'proposal',
                p_source, p_ttl_seconds);
      v_ids := v_ids || v_id;
      v_n := v_n + 1;
    END LOOP;
    v_status := CASE WHEN v_n = 0 THEN 'empty' ELSE 'submitted' END;
  EXCEPTION WHEN OTHERS THEN
    v_ids := ARRAY[]::uuid[];
    v_n := 0;
    v_err := SQLSTATE || ': ' || SQLERRM;
    v_status := CASE WHEN SQLERRM LIKE 'OTTOQ_PROPOSAL_REFUSED_CERT%'
                       OR SQLERRM LIKE 'OTTOQ_PROPOSAL_UNAUTHENTICATED%'
                     THEN 'refused' ELSE 'error' END;
  END;

  -- The SERVER-derived source (0198), read back from the first receipt.
  IF v_n > 0 THEN
    SELECT p.source INTO v_eff FROM public.ottoq_external_proposals p WHERE p.proposal_id = v_ids[1];
  END IF;

  INSERT INTO public.ottoq_proposer_fire_log
    (sim_run_id, depot_id, declared_source, effective_source, tick_seq, status,
     frame_hash, n_vehicles, n_in_serviceable_state, n_rows, n_planned, n_abstained,
     n_deferred, n_submitted, proposal_ids, solver, fire, error)
  VALUES
    (p_sim_run_id, p_depot_id, p_source, v_eff, v_tick, v_status,
     v_fire->>'frame_hash',
     (v_fire->>'n_vehicles')::int, (v_fire->>'n_in_serviceable_state')::int,
     jsonb_array_length(COALESCE(p_rows, '[]'::jsonb)),
     (v_fire->>'n_planned')::int, (v_fire->>'n_abstained')::int, (v_fire->>'n_deferred')::int,
     v_n, v_ids, v_fire->'solver', v_fire, v_err)
  RETURNING fire_id INTO v_fire_id;

  RETURN jsonb_build_object(
    'fire_id', v_fire_id, 'status', v_status, 'submitted', v_n,
    'proposal_ids', to_jsonb(v_ids), 'tick_seq', v_tick,
    'effective_source', v_eff, 'error', v_err);
END
$function$
;

CREATE OR REPLACE FUNCTION public.ottoq_capture_proposal_disposition()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  --: Only a transition INTO a terminal status is an outcome. A pending row that
  --: is rewritten by promotion (0358) is not a disposition and must not be
  --: counted as one.
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status = 'pending' THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.ottoq_proposal_disposition_ledger
    (sim_run_id, proposal_id, depot_id, action_context, entity_type, entity_id,
     source, proposer_rank, status, disposition_reason, abstained,
     promotion_count, promoted_from, stall_id, requested_kw,
     proposal_created_at, disposed_at, disposed_tick, source_kind)
  VALUES
    (NEW.sim_run_id, NEW.proposal_id, NEW.depot_id, NEW.action_context,
     NEW.entity_type, NEW.entity_id, NEW.source,
     --: frozen at capture, on purpose -- see the table comment
     (SELECT pp.rank FROM public.ottoq_proposer_precedence pp WHERE pp.source = NEW.source),
     NEW.status, NEW.disposition_reason,
     COALESCE(NEW.proposal->>'abstain', '') IN ('true','t','1'),
     NULLIF(NEW.proposal->>'promotion_count','')::integer,
     NULLIF(NEW.proposal->>'promoted_from','')::uuid,
     NULLIF(NEW.proposal->>'stall_id','')::uuid,
     CASE WHEN (NEW.proposal->>'requested_kw') ~ '^[0-9]+(\.[0-9]+)?$'
          THEN (NEW.proposal->>'requested_kw')::numeric END,
     NEW.created_at, NEW.disposed_at, NEW.disposed_tick, 'live');

  RETURN NEW;

--: SWALLOWED ON PURPOSE. This fires on the disposition path, which runs inside
--: decide_tick. APPLYING.md: a failure there must never abort the tick, because a
--: rolled-back tick reads as "succeeded" in cron and produces zero stall
--: assignments. A missing evidence row is a gap; a rolled-back tick is an outage.
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '0364 capture_proposal_disposition: % %', SQLSTATE, SQLERRM;
  RETURN NEW;
END $function$
;
CREATE TRIGGER ottoq_capture_proposal_disposition_trg AFTER UPDATE OF status ON public.ottoq_external_proposals FOR EACH ROW EXECUTE FUNCTION ottoq_capture_proposal_disposition();
