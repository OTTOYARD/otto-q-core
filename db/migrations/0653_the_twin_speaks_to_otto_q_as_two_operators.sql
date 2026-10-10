-- migration-version: 20261010013631
-- migration-name:    the_twin_speaks_to_otto_q_as_two_operators
--
-- 0653  **The twin gets two synthetic operators, sim-a and sim-b, each with its own key to the v2 door, and a step in
--        which they read their own directives, carry them out and answer each one through the door.** (Step 4 of the
--        twin data contract review, 2026-10-08: "Make the twin a client. The twin publishes and receives only through
--        the v2 door, as two synthetic operators. Acks stop happening inside OTTO-Q's transaction. An automated test
--        proves sim-a never sees sim-b." Chase, 2026-10-09 CT: "Start building.")
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The twin carries out OTTO-Q's commands by reading the engine's own table (twin.ottoq_sim_confirm_commands, "the
--   walk") inside the world tick, in the same transaction as OTTO-Q's next decisions, and it writes the outcome
--   straight onto the engine's rows under OTTO-Q's own name: 81,407 of the twin depot's 81,446 executed commands say
--   confirmed_by 'otto_q_preflight' (read 2026-10-10). There is no interface for a real operator to be swapped in
--   for. 0650-0652 built one (the v2 door, the outbox, the payload door); this gives the twin the two operators that
--   use it, and the step in which they do. 0654 wires the step into the ticks behind a flag.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) twin.ottoq_twin_operators and two twin source keys, issued and scoped through 0649/0650's own functions:
--         sim-a  Waymo Nashville                      (46 cars at the twin depot)
--         sim-b  Tesla Robotaxi TN and Zoox Southeast (36 + 34)
--       Data source twin, streams telemetry, arrival and incident. The raw keys are never kept or shown: the twin
--       calls the door's database half inside the database with each key's hash, which is exactly what the HTTP door
--       hands those functions. The four retail cars with no fleet have never had a command and get no operator.
--   (b) twin.ottoq_twin_operator_log (one row per directive an operator handled: what the world did, the ack sent,
--       the door's answer), ..._state (each operator's outbox cursor per run, and directives held over) and
--       ..._sequences (the per-car sequence the twin numbers its events with). Class 'engine', with foreign keys.
--   (c) The door's run for a twin key: public.ottoq_v2_take_events and public.ottoq_v2_read_directives honour the
--       transaction-local setting ottoq.v2_twin_run, which only twin.ottoq_twin_operator_step sets, so the twin's
--       operators are judged on the run they speak for. Without it nothing changes: the depot's newest running run,
--       production_live excluded, as before. No HTTP caller can set it.
--   (d) public.ottoq_api_twin_apply_directives (0652) reads what the walk did from the twin's log when the walk
--       reports there (0654), else from the engine's row (the walk as it is today). A directive already answered
--       gets no second ack.
--   (e) twin.ottoq_twin_operator_step(run): every operator reads the directives it has not read; the world carries
--       them out in ONE pass of the walk, in the walk's own order (the world is shared, the operators are channels,
--       so neither is served first); then each operator answers its own through the door with its own key, as a
--       CloudEvent with its own source, subject and per-car sequence, at the run's clock. Nothing calls it yet.
--   (f) public.ottoq_assert_operator_isolation(run): per operator, every directive delivered to it, every event the
--       door took from it, every directive it answered and every ack recorded under its name concerned its own
--       fleets' cars. Expected: zero violations, and each operator seen at least once.
--   (g) The flag the ticks will read, twin_operator_door (0 = the walk inside the world tick, as today; 1 = the
--       operators' step), declared in the policy catalog. Nothing reads it until 0654.
--   (h) public.ottoq_command_handshake counts an ack written by a door operator ('operator:<name>') as external,
--       not as OTTO-Q's own (it read any actor the registry did not list as 'self').
--
-- ══ §3 WHAT IT DOES NOT CHANGE; forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════
--
--   No tick path calls anything here and none reads the new tables or the flag. The two door functions behave as
--   before unless the pin is set, and only the new step sets it. The payload door answers the same as 0652's when
--   the walk writes the engine's rows, which is what the walk does until 0654. V1 runs the step on a copy of the
--   newest twin run inside a sub-block that rolls back.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Revoke the two keys (public.ottoq_revoke_source_key) and re-run 0650's take_events, 0651's read_directives and
--   0652's apply_directives definitions. Dropping the new tables and functions needs a person at the connector's
--   prompt.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0653 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0652_the_twin_applies_the_directives_it_is_handed_and_answers_each_with_an_ack') THEN
    RAISE EXCEPTION '0653 P1: 0652 is not classified; apply in order';
  END IF;
  IF to_regclass('twin.ottoq_twin_operators') IS NOT NULL OR to_regclass('twin.ottoq_twin_operator_log') IS NOT NULL
     OR to_regclass('twin.ottoq_twin_operator_state') IS NOT NULL OR to_regclass('twin.ottoq_twin_operator_sequences') IS NOT NULL
     OR to_regprocedure('twin.ottoq_twin_operator_step(uuid)') IS NOT NULL
     OR to_regprocedure('public.ottoq_assert_operator_isolation(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0653 P1: an object this file creates exists already';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'twin_operator_door') THEN
    RAISE EXCEPTION '0653 P1: the policy key twin_operator_door exists already';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottow_api_keys WHERE source_name IN ('sim-a', 'sim-b')) THEN
    RAISE EXCEPTION '0653 P1: a key named sim-a or sim-b exists already';
  END IF;
  IF (SELECT count(*) FROM public.fleet_operators
       WHERE (id, name) IN (('22222222-2222-2222-2222-222222222222'::uuid, 'Waymo Nashville'),
                            ('33333333-3333-3333-3333-333333333333'::uuid, 'Tesla Robotaxi TN'),
                            ('44444444-4444-4444-4444-444444444444'::uuid, 'Zoox Southeast'))) <> 3 THEN
    RAISE EXCEPTION '0653 P1: the three fleets at the twin depot are not the ones this file splits between sim-a and sim-b';
  END IF;
  IF to_regprocedure('public.ottoq_issue_source_key(uuid,text,text,text,text[],text[])') IS NULL
     OR to_regprocedure('public.ottoq_scope_source_key(uuid,uuid[])') IS NULL
     OR to_regprocedure('public.ottoq_v2_take_events(text,jsonb,boolean)') IS NULL
     OR to_regprocedure('public.ottoq_v2_read_directives(text,bigint,integer,boolean)') IS NULL
     OR to_regprocedure('ottoq.ottoq_v2_rfc3339(timestamptz)') IS NULL
     OR to_regprocedure('ottoq.ottoq_v2_tstz(text)') IS NULL
     OR to_regprocedure('ottoq.ottoq_v2_directive_event(uuid)') IS NULL THEN
    RAISE EXCEPTION '0653 P1: a function of 0649-0651 this file calls is missing';
  END IF;
END $premises$;

-- ── (a) the twin's operators and their keys ──
CREATE TABLE twin.ottoq_twin_operators (
  source_name text PRIMARY KEY CHECK (source_name ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  depot_id    uuid NOT NULL REFERENCES public.depots (id),
  key_id      uuid NOT NULL UNIQUE REFERENCES public.ottow_api_keys (id),
  note        text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE twin.ottoq_twin_operators IS
  '0653: the synthetic operators the twin speaks to OTTO-Q as, each through its own v2 door key (ottow_api_keys, data '
  'source twin, scoped to its fleets). The key''s fleets are the truth; this names which keys are the twin''s.';

DO $keys$
DECLARE v_twin uuid := '11111111-1111-1111-1111-111111111111'; k jsonb; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('sim-a', ARRAY['22222222-2222-2222-2222-222222222222']::uuid[], 'Waymo Nashville'),
      ('sim-b', ARRAY['33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444']::uuid[],
                'Tesla Robotaxi TN and Zoox Southeast')) AS t(name, fleets, note)
  LOOP
    -- the raw key comes back once, here, and is dropped: the twin uses the key's hash inside the database
    k := public.ottoq_issue_source_key(v_twin, 'fleet_api', r.name, 'twin', ARRAY['telemetry', 'arrival', 'incident'], NULL);
    PERFORM public.ottoq_scope_source_key((k ->> 'id')::uuid, r.fleets);
    INSERT INTO twin.ottoq_twin_operators (source_name, depot_id, key_id, note)
    VALUES (r.name, v_twin, (k ->> 'id')::uuid, 'the twin''s synthetic operator for ' || r.note || ' (0653)');
  END LOOP;
END $keys$;

-- ── (b) what the operators did ──
CREATE TABLE twin.ottoq_twin_operator_log (
  log_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sim_run_id      uuid NOT NULL REFERENCES public.ottoq_sim_runs (sim_run_id),
  command_id      uuid NOT NULL,
  source_name     text,
  vehicle_ref     text,
  outcome         text CHECK (outcome IN ('executed', 'refused')),
  reason_code     text,
  refusal_reason  text,
  walked_at       timestamptz,
  walks           integer NOT NULL DEFAULT 0,
  read_at         timestamptz,
  ack             jsonb,
  door            jsonb,
  CONSTRAINT ottoq_twin_operator_log_once UNIQUE (sim_run_id, command_id)
);
COMMENT ON TABLE twin.ottoq_twin_operator_log IS
  '0653: one row per directive the twin''s operators handled in a run: what the world did with it (outcome, the '
  'engine''s own reason code, written by the walk when it reports, 0654), which operator read it, the ack it sent '
  'and the door''s answer. The engine learns the outcome only from the ack.';

CREATE TABLE twin.ottoq_twin_operator_state (
  sim_run_id        uuid NOT NULL REFERENCES public.ottoq_sim_runs (sim_run_id),
  source_name       text NOT NULL REFERENCES twin.ottoq_twin_operators (source_name),
  directive_cursor  bigint NOT NULL DEFAULT 0,
  pending           jsonb NOT NULL DEFAULT '[]'::jsonb,
  steps             integer NOT NULL DEFAULT 0,
  last_step_clock   timestamptz,
  PRIMARY KEY (sim_run_id, source_name)
);
COMMENT ON TABLE twin.ottoq_twin_operator_state IS
  '0653: per run and operator, the outbox cursor it has read to and the directives it holds over to its next step.';

CREATE TABLE twin.ottoq_twin_operator_sequences (
  sim_run_id   uuid NOT NULL REFERENCES public.ottoq_sim_runs (sim_run_id),
  source_name  text NOT NULL,
  vehicle_ref  text NOT NULL,
  last_seq     bigint NOT NULL,
  PRIMARY KEY (sim_run_id, source_name, vehicle_ref)
);
COMMENT ON TABLE twin.ottoq_twin_operator_sequences IS
  '0653: the last CloudEvents sequence an operator gave a car''s events in a run (contract rule 6: each car''s events '
  'are numbered by its operator).';

ALTER TABLE twin.ottoq_twin_operators          ENABLE ROW LEVEL SECURITY;
ALTER TABLE twin.ottoq_twin_operator_log       ENABLE ROW LEVEL SECURITY;
ALTER TABLE twin.ottoq_twin_operator_state     ENABLE ROW LEVEL SECURITY;
ALTER TABLE twin.ottoq_twin_operator_sequences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON twin.ottoq_twin_operators, twin.ottoq_twin_operator_log, twin.ottoq_twin_operator_state,
              twin.ottoq_twin_operator_sequences FROM PUBLIC, anon, authenticated;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('twin', 'ottoq_twin_operator_log', 'sim_run_id', 'engine',
        '0653: what the twin''s operators did with a run''s directives. Goes with its run.'),
       ('twin', 'ottoq_twin_operator_state', 'sim_run_id', 'engine',
        '0653: an operator''s outbox cursor and held-over directives for a run. Goes with its run.'),
       ('twin', 'ottoq_twin_operator_sequences', 'sim_run_id', 'engine',
        '0653: the per-car event sequence an operator numbered in a run. Goes with its run.');

-- ── (c) the door judges the twin's operators on the run they speak for ──
CREATE OR REPLACE FUNCTION public.ottoq_v2_take_events(p_key_hash text, p_events jsonb, p_dry_run boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  k public.ottow_api_keys%ROWTYPE;
  v_run uuid; v_engine_run uuid; v_clock timestamptz; v_pin uuid;
  v_ev jsonb; v_res jsonb; v_out jsonb := '[]'::jsonb; v_n int;
BEGIN
  /* 0650: the v2 door (contract/README.md). The HTTP door hashes the X-OTTO-Q-API-Key it was handed (SHA-256,
     lowercase hex) and passes the hash and the events it has already checked against contract/schemas. */
  SELECT * INTO k FROM public.ottow_api_keys WHERE key_hash = p_key_hash AND is_active LIMIT 1;
  IF k.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_or_revoked_key');
  END IF;
  IF jsonb_typeof(p_events) IS DISTINCT FROM 'array' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'events_must_be_an_array');
  END IF;
  v_n := jsonb_array_length(p_events);
  IF v_n NOT BETWEEN 1 AND 500 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'batch_size', 'detail', '1 to 500 events per request', 'received', v_n);
  END IF;

  -- the data source's clock (README rule 2)
  IF k.data_source IN ('twin', 'replay') THEN
    -- 0653: the twin's own operators name the run they speak for (twin.ottoq_twin_operator_step pins it for its own
    -- transaction, and only a function in the database can set it); any other twin or replay key is judged on its
    -- depot's newest running run, as before.
    v_pin := CASE WHEN COALESCE(current_setting('ottoq.v2_twin_run', true), '')
                       ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                  THEN current_setting('ottoq.v2_twin_run', true)::uuid END;
    SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
      FROM public.ottoq_sim_runs r
     WHERE r.depot_id = k.depot_id AND r.status = 'running'
       AND CASE WHEN v_pin IS NULL THEN COALESCE(r.run_by, '') <> 'production_live' ELSE r.sim_run_id = v_pin END
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL OR v_clock IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'no_running_run',
        'detail', 'a twin or replay key is judged on its run''s clock, and no run is running at its depot');
    END IF;
    v_engine_run := v_run;
  ELSE
    v_clock := now();
    SELECT r.sim_run_id INTO v_engine_run FROM public.ottoq_sim_runs r
     WHERE r.depot_id = k.depot_id AND r.status = 'running' AND r.run_by = 'production_live'
     ORDER BY r.started_at DESC LIMIT 1;
  END IF;

  UPDATE public.ottow_api_keys SET last_used_at = now() WHERE id = k.id;

  BEGIN
    FOR v_ev IN SELECT value FROM jsonb_array_elements(p_events) LOOP
      v_res := ottoq.ottoq_v2_take_one(k.id, v_run, v_engine_run, v_clock, v_ev);
      v_out := v_out || jsonb_build_array(v_res);
    END LOOP;
    IF p_dry_run THEN
      RAISE EXCEPTION 'ottoq_v2_dry_run';
    END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'ottoq_v2_dry_run' THEN
      RAISE;
    END IF;
  END;

  RETURN jsonb_build_object(
    'ok', true, 'dry_run', p_dry_run, 'key_prefix', k.key_prefix, 'operator', k.source_name, 'depot_id', k.depot_id,
    'data_source', k.data_source, 'sim_run_id', v_run, 'clock', v_clock, 'received', v_n,
    'applied',   (SELECT count(*) FROM jsonb_array_elements(v_out) r WHERE r ->> 'disposition' = 'applied'),
    'late',      (SELECT count(*) FROM jsonb_array_elements(v_out) r WHERE r ->> 'disposition' = 'late'),
    'duplicate', (SELECT count(*) FROM jsonb_array_elements(v_out) r WHERE r ->> 'disposition' = 'duplicate'),
    'refused',   (SELECT count(*) FROM jsonb_array_elements(v_out) r WHERE r ->> 'disposition' = 'refused'),
    'results', v_out);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_v2_read_directives(
  p_key_hash text, p_after bigint DEFAULT 0, p_limit integer DEFAULT 100, p_mark_delivered boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  k public.ottow_api_keys%ROWTYPE;
  v_run uuid; v_lim integer; v_last bigint := COALESCE(p_after, 0); v_pin uuid;
  v_events jsonb := '[]'::jsonb; v_ids uuid[] := ARRAY[]::uuid[]; v_ev jsonb; r record;
BEGIN
  /* 0651: contract/README.md rules 3 and 4. A key reads the directives for its own fleets' cars at its own depot,
     of its own data source, after its cursor. The HTTP door signs each one before it leaves. */
  SELECT * INTO k FROM public.ottow_api_keys WHERE key_hash = p_key_hash AND is_active LIMIT 1;
  IF k.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_or_revoked_key');
  END IF;
  IF COALESCE(cardinality(k.fleet_operator_ids), 0) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'key_speaks_for_no_fleet');
  END IF;
  IF k.data_source NOT IN ('production', 'twin') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_directives_for_' || k.data_source);
  END IF;
  v_lim := least(greatest(COALESCE(p_limit, 100), 1), 500);
  IF k.data_source = 'twin' THEN
    -- 0653: the run the twin's own operators name, as in ottoq_v2_take_events; else the depot's newest running run.
    v_pin := CASE WHEN COALESCE(current_setting('ottoq.v2_twin_run', true), '')
                       ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                  THEN current_setting('ottoq.v2_twin_run', true)::uuid END;
    SELECT r2.sim_run_id INTO v_run FROM public.ottoq_sim_runs r2
     WHERE r2.depot_id = k.depot_id AND r2.status = 'running'
       AND CASE WHEN v_pin IS NULL THEN COALESCE(r2.run_by, '') <> 'production_live' ELSE r2.sim_run_id = v_pin END
     ORDER BY r2.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN
      RETURN jsonb_build_object('ok', true, 'operator', k.source_name, 'data_source', k.data_source, 'events', '[]'::jsonb,
                                'count', 0, 'next_after', v_last, 'note', 'no_running_run');
    END IF;
  END IF;

  FOR r IN
    SELECT c.command_id, c.command_seq
      FROM public.ottoq_vehicle_commands c
      JOIN public.vehicles v ON v.id = c.vehicle_id
     WHERE c.depot_id = k.depot_id
       AND c.data_source = k.data_source
       AND v.fleet_operator_id = ANY (k.fleet_operator_ids)
       AND c.command_seq > COALESCE(p_after, 0)
       AND c.command_type <> 'dispatch'
       AND NOT (c.status = 'refused' AND c.confirmed_by = 'otto_q_preflight')
       AND (k.data_source = 'production' OR c.sim_run_id = v_run)
     ORDER BY c.command_seq
     LIMIT v_lim
  LOOP
    v_last := r.command_seq;
    v_ev := ottoq.ottoq_v2_directive_event(r.command_id);
    IF v_ev IS NOT NULL THEN
      v_events := v_events || jsonb_build_array(v_ev);
      v_ids := v_ids || r.command_id;
    END IF;
  END LOOP;

  IF p_mark_delivered AND cardinality(v_ids) > 0 THEN
    UPDATE public.ottoq_vehicle_commands
       SET delivered_at = COALESCE(delivered_at, now()), delivered_to = COALESCE(delivered_to, 'v2:' || k.source_name)
     WHERE command_id = ANY (v_ids);
  END IF;
  UPDATE public.ottow_api_keys SET last_used_at = now() WHERE id = k.id;
  RETURN jsonb_build_object('ok', true, 'operator', k.source_name, 'depot_id', k.depot_id, 'data_source', k.data_source,
                            'sim_run_id', v_run, 'events', v_events, 'count', jsonb_array_length(v_events),
                            'next_after', v_last);
END $fn$;

-- ── (d) the payload door reads what the walk did ──
CREATE OR REPLACE FUNCTION public.ottoq_api_twin_apply_directives(p_sim_run_id uuid, p_clock timestamptz, p_directives jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_clock timestamptz; v_run_found boolean;
  e jsonb; d jsonb; v_id uuid; c public.ottoq_vehicle_commands%ROWTYPE;
  v_run uuid[] := ARRAY[]::uuid[]; v_out jsonb := '[]'::jsonb; v_ack jsonb; v_obs text; r record;
  v_status text; v_code text; v_refusal text;
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
BEGIN
  /* 0652, read again by 0653: the world receives directive documents and answers each one (contract/README.md rules
     3 and 9). The caller wraps each ack in its own CloudEvent and sends it through the v2 door. A signature is
     checked by whoever received the directive over the wire; this door trusts the database it is in. 0653: what the
     walk did comes from the twin's own log when the walk reports there (0654), else from the engine's row. */
  SELECT true, COALESCE(p_clock, r0.sim_clock_current) INTO v_run_found, v_clock
    FROM public.ottoq_sim_runs r0 WHERE r0.sim_run_id = p_sim_run_id;
  IF NOT COALESCE(v_run_found, false) OR v_clock IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_run_or_no_clock');
  END IF;
  IF jsonb_typeof(p_directives) IS DISTINCT FROM 'array' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'directives_must_be_an_array');
  END IF;
  v_obs := ottoq.ottoq_v2_rfc3339(v_clock);

  -- 1. which of these the walk may run: this run's, version 1, in force now, still issued. The rest are answered
  --    here, and a directive already answered gets no second ack.
  FOR e IN SELECT value FROM jsonb_array_elements(p_directives) LOOP
    d := e -> 'data';
    v_id := CASE WHEN d ->> 'directive_id' ~ c_uuid THEN (d ->> 'directive_id')::uuid END;
    c := NULL;
    SELECT * INTO c FROM public.ottoq_vehicle_commands WHERE command_id = v_id AND sim_run_id = p_sim_run_id;
    v_ack := NULL;
    IF c.command_id IS NULL THEN
      v_ack := jsonb_build_object('disposition', 'rejected', 'reason', 'other', 'detail', 'not a directive of this run');
    ELSIF (d ->> 'version') IS DISTINCT FROM '1' THEN
      v_ack := jsonb_build_object('disposition', 'rejected', 'reason', 'other', 'detail', 'a version this depot never issued');
    ELSIF c.status <> 'issued' THEN
      v_out := v_out || jsonb_build_array(jsonb_build_object('directive_id', c.command_id, 'deferred', 'already_answered',
                                                             'status', c.status));
      CONTINUE;
    ELSIF ottoq.ottoq_v2_tstz(d ->> 'expires_at') IS NULL OR ottoq.ottoq_v2_tstz(d ->> 'expires_at') <= v_clock THEN
      v_ack := jsonb_build_object('disposition', 'unable', 'reason', 'expired');
    ELSIF ottoq.ottoq_v2_tstz(d ->> 'valid_from') > v_clock THEN
      v_out := v_out || jsonb_build_array(jsonb_build_object('directive_id', c.command_id, 'deferred', 'not_yet_valid'));
      CONTINUE;
    ELSE
      IF NOT (c.command_id = ANY (v_run)) THEN
        v_run := v_run || c.command_id;
      END IF;
      CONTINUE;
    END IF;
    v_out := v_out || jsonb_build_array(jsonb_build_object('directive_id', d ->> 'directive_id', 'ack',
      jsonb_build_object('directive_id', d ->> 'directive_id', 'directive_version', 1, 'observed_at', v_obs) || v_ack));
  END LOOP;

  -- 2. the walk, over exactly those (an empty set runs nothing). A report left by an earlier walk of one of them is
  --    cleared first: it was never answered, or the command would not still be issued.
  IF cardinality(v_run) > 0 THEN
    UPDATE twin.ottoq_twin_operator_log
       SET outcome = NULL, reason_code = NULL, refusal_reason = NULL, walked_at = NULL
     WHERE sim_run_id = p_sim_run_id AND command_id = ANY (v_run) AND outcome IS NOT NULL;
    PERFORM set_config('ottoq.apply_only', v_run::text, true);
    PERFORM twin.ottoq_sim_confirm_commands(p_sim_run_id, v_clock);
    PERFORM set_config('ottoq.apply_only', '', true);
  END IF;

  -- 3. what happened to each, as the contract's ack
  FOR r IN SELECT cmd.command_id, cmd.status AS cmd_status, cmd.reason_code AS cmd_code,
                  cmd.payload ->> 'refusal_reason' AS cmd_refusal, o.outcome, o.reason_code AS o_code,
                  o.refusal_reason AS o_refusal, v.current_state::text AS state
             FROM public.ottoq_vehicle_commands cmd
             JOIN public.vehicles v ON v.id = cmd.vehicle_id
             LEFT JOIN twin.ottoq_twin_operator_log o
               ON o.sim_run_id = p_sim_run_id AND o.command_id = cmd.command_id AND o.outcome IS NOT NULL
            WHERE cmd.command_id = ANY (v_run)
            ORDER BY cmd.command_seq
  LOOP
    v_status  := COALESCE(r.outcome, CASE WHEN r.cmd_status <> 'issued' THEN r.cmd_status END);
    v_code    := CASE WHEN r.outcome IS NOT NULL THEN r.o_code ELSE r.cmd_code END;
    v_refusal := CASE WHEN r.outcome IS NOT NULL THEN r.o_refusal ELSE r.cmd_refusal END;
    v_ack := CASE
      WHEN v_status IS NULL THEN NULL
      WHEN v_status IN ('executed', 'confirmed') THEN jsonb_build_object('disposition', 'accepted')
      WHEN v_status = 'expired' THEN jsonb_build_object('disposition', 'unable', 'reason', 'expired')
      WHEN v_code = 'target_occupied'      THEN jsonb_build_object('disposition', 'unable', 'reason', 'occupied')
      WHEN v_code = 'resource_faulted'     THEN jsonb_build_object('disposition', 'unable', 'reason', 'charger_fault')
      WHEN v_code = 'vehicle_unresponsive' THEN jsonb_build_object('disposition', 'unable', 'reason', 'vehicle_unresponsive')
      WHEN v_code = 'superseded'           THEN jsonb_build_object('disposition', 'rejected', 'reason', 'superseded')
      WHEN v_code = 'vehicle_state_incompatible'
           AND r.state IN ('deployed', 'en_route_to_depot', 'en_route_to_deployment', 'offline')
                                           THEN jsonb_build_object('disposition', 'unable', 'reason', 'vehicle_not_at_depot')
      ELSE jsonb_build_object('disposition', 'unable', 'reason', 'other',
                              'detail', left(COALESCE(v_code, 'refused') || COALESCE(': ' || v_refusal, ''), 500))
    END;
    IF v_ack IS NULL THEN
      v_out := v_out || jsonb_build_array(jsonb_build_object('directive_id', r.command_id, 'deferred', 'not_run'));
    ELSE
      v_out := v_out || jsonb_build_array(jsonb_build_object('directive_id', r.command_id, 'ack',
        jsonb_build_object('directive_id', r.command_id, 'directive_version', 1, 'observed_at', v_obs) || v_ack));
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'contract_version', '0.1', 'endpoint', 'twin.apply_directives',
                            'sim_run_id', p_sim_run_id, 'clock', v_clock, 'results', v_out);
END $fn$;

-- ── (e) the operators' step ──
CREATE OR REPLACE FUNCTION twin.ottoq_twin_operator_step(p_run uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  r public.ottoq_sim_runs%ROWTYPE;
  op record; e jsonb; res jsonb; v_read jsonb; v_apply jsonb; v_take jsonb; v_ack jsonb; v_chunk jsonb;
  v_after bigint; v_next bigint; v_pending jsonb; v_clock timestamptz; v_obs text; v_seq bigint; v_ref text;
  v_events jsonb := '[]'::jsonb;   -- every directive read this step, in reading order
  v_owner jsonb := '{}'::jsonb;    -- directive_id -> the operator that read it
  v_subject jsonb := '{}'::jsonb;  -- directive_id -> the car it concerns
  v_event_of jsonb := '{}'::jsonb; -- directive_id -> the directive event itself (to hold one over)
  v_acks jsonb; v_held jsonb; v_out jsonb := '{}'::jsonb;
  v_read_n int; v_ack_n int; v_applied int; v_refused int; v_skipped int; i int;
  c_schema constant text := 'https://ottoyard.com/schemas/ottoq/contract/0.1/directive.ack.json';
BEGIN
  /* 0653. The twin as two operators (contract/README.md; the review's step 4). Every operator reads the directives
     it has not read through the outbox, the world carries them all out in ONE pass of the walk in the walk's own
     order (the world is one place; the operators are channels, so neither is served first), and each operator
     answers its own through the v2 door with its own key. The clock is the run's own: the twin answers at the tick
     it heard the directive in. A failure raises: an operator that cannot speak must not look like one that agreed. */
  SELECT * INTO r FROM public.ottoq_sim_runs WHERE sim_run_id = p_run;
  IF r.sim_run_id IS NULL OR r.status <> 'running' OR r.sim_clock_current IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'run_not_running', 'sim_run_id', p_run);
  END IF;
  v_clock := r.sim_clock_current;
  v_obs := ottoq.ottoq_v2_rfc3339(v_clock);
  PERFORM set_config('ottoq.v2_twin_run', p_run::text, true);

  -- 1. each operator reads what it has not read, after what it held over
  FOR op IN SELECT o.source_name, k.key_hash
              FROM twin.ottoq_twin_operators o JOIN public.ottow_api_keys k ON k.id = o.key_id
             WHERE o.depot_id = r.depot_id AND k.is_active AND k.data_source = 'twin'
             ORDER BY o.source_name
  LOOP
    INSERT INTO twin.ottoq_twin_operator_state (sim_run_id, source_name) VALUES (p_run, op.source_name)
    ON CONFLICT (sim_run_id, source_name) DO NOTHING;
    SELECT directive_cursor, pending INTO v_after, v_pending
      FROM twin.ottoq_twin_operator_state WHERE sim_run_id = p_run AND source_name = op.source_name FOR UPDATE;
    v_read_n := 0;
    FOR e IN SELECT value FROM jsonb_array_elements(v_pending) LOOP
      v_events := v_events || jsonb_build_array(e);
      v_owner := v_owner || jsonb_build_object(e -> 'data' ->> 'directive_id', op.source_name);
      v_subject := v_subject || jsonb_build_object(e -> 'data' ->> 'directive_id', e ->> 'subject');
      v_event_of := v_event_of || jsonb_build_object(e -> 'data' ->> 'directive_id', e);
    END LOOP;
    LOOP
      v_read := public.ottoq_v2_read_directives(op.key_hash, v_after, 500, true);
      IF NOT COALESCE((v_read ->> 'ok')::boolean, false) THEN
        RAISE EXCEPTION 'twin operator %: the outbox refused it: %', op.source_name, v_read;
      END IF;
      FOR e IN SELECT value FROM jsonb_array_elements(v_read -> 'events') LOOP
        v_events := v_events || jsonb_build_array(e);
        v_owner := v_owner || jsonb_build_object(e -> 'data' ->> 'directive_id', op.source_name);
        v_subject := v_subject || jsonb_build_object(e -> 'data' ->> 'directive_id', e ->> 'subject');
        v_event_of := v_event_of || jsonb_build_object(e -> 'data' ->> 'directive_id', e);
        v_read_n := v_read_n + 1;
      END LOOP;
      v_next := COALESCE((v_read ->> 'next_after')::bigint, v_after);
      EXIT WHEN v_next <= v_after;
      v_after := v_next;
    END LOOP;
    UPDATE twin.ottoq_twin_operator_state
       SET directive_cursor = v_after, pending = '[]'::jsonb, steps = steps + 1, last_step_clock = v_clock
     WHERE sim_run_id = p_run AND source_name = op.source_name;
    v_out := v_out || jsonb_build_object(op.source_name, jsonb_build_object('read', v_read_n));
  END LOOP;

  -- 2. the world carries them out, once, in one pass
  IF jsonb_array_length(v_events) > 0 THEN
    v_apply := public.ottoq_api_twin_apply_directives(p_run, v_clock, v_events);
    IF NOT COALESCE((v_apply ->> 'ok')::boolean, false) THEN
      RAISE EXCEPTION 'twin operators: the payload door refused the step: %', v_apply;
    END IF;
  ELSE
    v_apply := jsonb_build_object('results', '[]'::jsonb);
  END IF;

  -- 3. each operator answers its own, with its own key
  FOR op IN SELECT o.source_name, k.key_hash
              FROM twin.ottoq_twin_operators o JOIN public.ottow_api_keys k ON k.id = o.key_id
             WHERE o.depot_id = r.depot_id AND k.is_active AND k.data_source = 'twin'
             ORDER BY o.source_name
  LOOP
    v_acks := '[]'::jsonb; v_held := '[]'::jsonb; v_skipped := 0;
    FOR res IN SELECT x.value FROM jsonb_array_elements(v_apply -> 'results') AS x(value)
                WHERE v_owner ->> (x.value ->> 'directive_id') = op.source_name
    LOOP
      v_ref := v_subject ->> (res ->> 'directive_id');
      IF res ? 'ack' THEN
        INSERT INTO twin.ottoq_twin_operator_sequences (sim_run_id, source_name, vehicle_ref, last_seq)
        VALUES (p_run, op.source_name, v_ref, 1)
        ON CONFLICT (sim_run_id, source_name, vehicle_ref) DO UPDATE SET last_seq = twin.ottoq_twin_operator_sequences.last_seq + 1
        RETURNING last_seq INTO v_seq;
        v_ack := jsonb_build_object(
          'specversion', '1.0', 'id', 'ack-' || (res ->> 'directive_id'),
          'source', 'urn:ottoq:src:' || op.source_name || ':' || v_ref, 'subject', v_ref,
          'type', 'com.ottoyard.directive.ack', 'time', v_obs, 'datacontenttype', 'application/json',
          'dataschema', c_schema, 'sequence', lpad(v_seq::text, 20, '0'), 'data', res -> 'ack');
        v_acks := v_acks || jsonb_build_array(v_ack);
        INSERT INTO twin.ottoq_twin_operator_log (sim_run_id, command_id, source_name, vehicle_ref, read_at, ack)
        VALUES (p_run, (res ->> 'directive_id')::uuid, op.source_name, v_ref, v_clock, res -> 'ack')
        ON CONFLICT (sim_run_id, command_id) DO UPDATE
          SET source_name = EXCLUDED.source_name, vehicle_ref = EXCLUDED.vehicle_ref, read_at = EXCLUDED.read_at,
              ack = EXCLUDED.ack;
      ELSIF res ->> 'deferred' IN ('not_yet_valid', 'not_run') THEN
        v_held := v_held || jsonb_build_array(v_event_of -> (res ->> 'directive_id'));
      ELSE
        v_skipped := v_skipped + 1;
        INSERT INTO twin.ottoq_twin_operator_log (sim_run_id, command_id, source_name, vehicle_ref, read_at, door)
        VALUES (p_run, (res ->> 'directive_id')::uuid, op.source_name, v_ref, v_clock,
                jsonb_build_object('skipped', res ->> 'deferred', 'status', res ->> 'status'))
        ON CONFLICT (sim_run_id, command_id) DO UPDATE
          SET source_name = EXCLUDED.source_name, vehicle_ref = EXCLUDED.vehicle_ref, read_at = EXCLUDED.read_at,
              door = EXCLUDED.door;
      END IF;
    END LOOP;

    v_ack_n := jsonb_array_length(v_acks); v_applied := 0; v_refused := 0; i := 0;
    WHILE i < v_ack_n LOOP
      SELECT jsonb_agg(x.value ORDER BY x.n) INTO v_chunk
        FROM jsonb_array_elements(v_acks) WITH ORDINALITY x(value, n) WHERE x.n > i AND x.n <= i + 500;
      v_take := public.ottoq_v2_take_events(op.key_hash, v_chunk, false);
      IF NOT COALESCE((v_take ->> 'ok')::boolean, false) THEN
        RAISE EXCEPTION 'twin operator %: the door refused its acks: %', op.source_name, v_take;
      END IF;
      FOR res IN SELECT value FROM jsonb_array_elements(v_take -> 'results') LOOP
        IF res ->> 'disposition' = 'applied' THEN v_applied := v_applied + 1; ELSE v_refused := v_refused + 1; END IF;
        UPDATE twin.ottoq_twin_operator_log
           SET door = res
         WHERE sim_run_id = p_run AND command_id::text = substr(res ->> 'id', 5) AND source_name = op.source_name;
      END LOOP;
      i := i + 500;
    END LOOP;
    IF v_refused > 0 THEN
      RAISE WARNING 'twin operator %: the door did not apply % of % acks on run %', op.source_name, v_refused, v_ack_n, p_run;
    END IF;
    IF jsonb_array_length(v_held) > 0 THEN
      UPDATE twin.ottoq_twin_operator_state SET pending = v_held WHERE sim_run_id = p_run AND source_name = op.source_name;
    END IF;
    v_out := jsonb_set(v_out, ARRAY[op.source_name], (v_out -> op.source_name) || jsonb_build_object(
      'acks', v_ack_n, 'applied', v_applied, 'not_applied', v_refused, 'held', jsonb_array_length(v_held),
      'already_answered', v_skipped));
  END LOOP;

  PERFORM set_config('ottoq.v2_twin_run', '', true);
  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_run, 'clock', v_clock, 'directives', jsonb_array_length(v_events),
                            'operators', v_out);
END $fn$;

-- ── (f) sim-a never sees sim-b ──
CREATE OR REPLACE FUNCTION public.ottoq_assert_operator_isolation(p_run uuid)
RETURNS TABLE (check_name text, source_name text, rows_seen bigint, violations bigint, sample jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  /* 0653: for each of the twin's operators at the run's depot, every directive delivered to it, every event the door
     took from it, every directive it answered and every ack recorded in its name concerned a car of its own fleets.
     violations must be 0; rows_seen > 0 shows the check had something to judge. */
  WITH ops AS (
    SELECT o.source_name, k.id AS key_id, k.fleet_operator_ids
      FROM twin.ottoq_twin_operators o JOIN public.ottow_api_keys k ON k.id = o.key_id
     WHERE o.depot_id = (SELECT depot_id FROM public.ottoq_sim_runs WHERE sim_run_id = p_run)),
  seen AS (
    SELECT 'directive_delivered'::text AS check_name, ops.source_name, c.command_id::text AS item,
           v.fleet_operator_id = ANY (ops.fleet_operator_ids) AS own
      FROM ops JOIN public.ottoq_vehicle_commands c ON c.sim_run_id = p_run AND c.delivered_to = 'v2:' || ops.source_name
      JOIN public.vehicles v ON v.id = c.vehicle_id
    UNION ALL
    SELECT 'event_taken', ops.source_name, i.inbox_id::text, v.fleet_operator_id = ANY (ops.fleet_operator_ids)
      FROM ops JOIN public.ottoq_v2_inbox i ON i.sim_run_id = p_run AND i.key_id = ops.key_id
      JOIN public.vehicles v ON v.id = i.vehicle_id
    UNION ALL
    SELECT 'directive_answered', ops.source_name, l.command_id::text, v.fleet_operator_id = ANY (ops.fleet_operator_ids)
      FROM ops JOIN twin.ottoq_twin_operator_log l ON l.sim_run_id = p_run AND l.source_name = ops.source_name
      JOIN public.ottoq_vehicle_commands c ON c.command_id = l.command_id
      JOIN public.vehicles v ON v.id = c.vehicle_id
    UNION ALL
    SELECT 'command_confirmed_by_operator', ops.source_name, c.command_id::text, v.fleet_operator_id = ANY (ops.fleet_operator_ids)
      FROM ops JOIN public.ottoq_vehicle_commands c ON c.sim_run_id = p_run AND c.confirmed_by = 'operator:' || ops.source_name
      JOIN public.vehicles v ON v.id = c.vehicle_id
    UNION ALL
    SELECT 'ack_event_recorded', ops.source_name, ev.event_id::text, v.fleet_operator_id = ANY (ops.fleet_operator_ids)
      FROM ops JOIN public.ottoq_events ev
        ON ev.sim_run_id = p_run AND ev.event_type = 'directive.ack' AND ev.actor_id = ops.source_name
      JOIN public.vehicles v ON v.id = ev.entity_id)
  SELECT k.check_name, o.source_name, count(s.item), count(s.item) FILTER (WHERE NOT s.own),
         COALESCE(jsonb_agg(s.item) FILTER (WHERE NOT s.own), '[]'::jsonb)
    FROM ops o
   CROSS JOIN (VALUES ('directive_delivered'), ('event_taken'), ('directive_answered'), ('command_confirmed_by_operator'),
                      ('ack_event_recorded')) AS k(check_name)
    LEFT JOIN seen s ON s.source_name = o.source_name AND s.check_name = k.check_name
   GROUP BY k.check_name, o.source_name
   ORDER BY k.check_name, o.source_name
$fn$;

REVOKE ALL ON FUNCTION twin.ottoq_twin_operator_step(uuid)                   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_assert_operator_isolation(uuid)          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_v2_take_events(text,jsonb,boolean)       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_v2_read_directives(text,bigint,integer,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_api_twin_apply_directives(uuid,timestamptz,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_twin_operator_step(uuid)                TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_assert_operator_isolation(uuid)       TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_v2_take_events(text,jsonb,boolean)    TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_v2_read_directives(text,bigint,integer,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_api_twin_apply_directives(uuid,timestamptz,jsonb) TO service_role;

-- ── (g) the flag the ticks will read (0654) ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('twin_operator_door',
        '0653: how the twin carries out OTTO-Q''s directives. 0 (the default) = the walk inside the world tick reads the '
        'engine''s commands and writes the outcome on them, as before. 1 = the twin''s operators (sim-a, sim-b) read their '
        'directives through the v2 outbox, the world carries them out, and each operator answers through the v2 door in '
        'its own transaction (twin.ottoq_twin_operator_step). A person''s dial, never the agent''s.',
        0, 0, 1,
        'ottoq_sim_advance_tick_world, twin.ottoq_world_advance, ottoq_sim_advance_tick, ottoq_demo_metronome (0654)', false);

-- ── (h) an ack an operator sent through the door is not OTTO-Q's own ──
CREATE OR REPLACE VIEW public.ottoq_command_handshake AS
 SELECT c.data_source,
    count(*) AS issued_total,
    count(*) FILTER (WHERE c.delivered_at IS NOT NULL) AS delivered,
    count(*) FILTER (WHERE c.confirmed_by IS NOT NULL) AS acked,
    count(*) FILTER (WHERE c.confirmed_by IS NOT NULL AND COALESCE(r.kind,
      CASE WHEN c.confirmed_by LIKE 'operator:%' THEN 'external'::text ELSE 'self'::text END) = 'self'::text) AS acked_by_us,
    count(*) FILTER (WHERE COALESCE(r.kind,
      CASE WHEN c.confirmed_by LIKE 'operator:%' THEN 'external'::text ELSE 'self'::text END) = 'operator'::text) AS acked_by_operator,
    count(*) FILTER (WHERE COALESCE(r.kind,
      CASE WHEN c.confirmed_by LIKE 'operator:%' THEN 'external'::text ELSE 'self'::text END) = 'external'::text) AS acked_by_asset,
    min(c.issued_at) AS first_issued,
    max(c.issued_at) AS last_issued
   FROM ottoq_vehicle_commands c
     LEFT JOIN ottoq_command_actor_registry r ON r.actor = c.confirmed_by
  GROUP BY c.data_source;

-- ── V1: the step on a copy of the twin depot's newest run, in a sub-block that rolls back ──
DO $v1$
DECLARE
  v_msg text; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_a_car uuid; v_b_car uuid; v_s1 uuid; v_s2 uuid; c1 uuid; c2 uuid;
  v_step jsonb; v_step2 jsonb; v_iso jsonb; v_viol bigint; v_log_a int; v_log_b int; v_cross int;
  v_del_a text; v_del_b text; v_keys int; v_pin text;
BEGIN
  SELECT count(*) INTO v_keys FROM twin.ottoq_twin_operators o JOIN public.ottow_api_keys k ON k.id = o.key_id
   WHERE k.data_source = 'twin' AND k.is_active AND k.depot_id = v_twin
     AND ((o.source_name = 'sim-a' AND k.fleet_operator_ids = ARRAY['22222222-2222-2222-2222-222222222222']::uuid[])
       OR (o.source_name = 'sim-b' AND k.fleet_operator_ids = ARRAY['33333333-3333-3333-3333-333333333333',
                                                                     '44444444-4444-4444-4444-444444444444']::uuid[]));
  IF v_keys <> 2 THEN RAISE EXCEPTION '0653 V1 FAILED: sim-a and sim-b are not two active twin keys scoped as stated'; END IF;

  SELECT sim_run_id, COALESCE(sim_clock_current, started_at) INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = v_twin AND COALESCE(run_by, '') <> 'production_live' ORDER BY started_at DESC LIMIT 1;
  SELECT id INTO v_a_car FROM public.vehicles
   WHERE home_depot_id = v_twin AND fleet_operator_id = '22222222-2222-2222-2222-222222222222' AND current_stall_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = vehicles.id) ORDER BY display_name LIMIT 1;
  SELECT id INTO v_b_car FROM public.vehicles
   WHERE home_depot_id = v_twin AND fleet_operator_id = '33333333-3333-3333-3333-333333333333' AND current_stall_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = vehicles.id) ORDER BY display_name LIMIT 1;
  SELECT (array_agg(id ORDER BY stall_code))[1], (array_agg(id ORDER BY stall_code))[2] INTO v_s1, v_s2
    FROM (SELECT id, stall_code FROM public.stalls
           WHERE depot_id = v_twin AND stall_type = 'staging' AND current_vehicle_id IS NULL
             AND (reserved_by IS NULL OR reservation_expires_at <= COALESCE(v_clock, now()))
           ORDER BY stall_code DESC LIMIT 2) s;
  IF v_run IS NULL OR v_a_car IS NULL OR v_b_car IS NULL OR v_s2 IS NULL THEN
    RAISE EXCEPTION '0653 V1: no run, no free Waymo or Tesla car, or no two free staging stalls at the twin depot to probe with';
  END IF;

  BEGIN
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = v_clock WHERE sim_run_id = v_run;
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_a_car, 'hold', jsonb_build_object('stall_id', v_s1), v_clock, '0653_v1_probe') RETURNING command_id INTO c1;
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_b_car, 'hold', jsonb_build_object('stall_id', v_s2), v_clock, '0653_v1_probe') RETURNING command_id INTO c2;
    v_step := twin.ottoq_twin_operator_step(v_run);
    v_step2 := twin.ottoq_twin_operator_step(v_run);   -- a second step reads nothing new and answers nothing twice
    SELECT delivered_to INTO v_del_a FROM public.ottoq_vehicle_commands WHERE command_id = c1;
    SELECT delivered_to INTO v_del_b FROM public.ottoq_vehicle_commands WHERE command_id = c2;
    SELECT count(*) INTO v_log_a FROM twin.ottoq_twin_operator_log WHERE sim_run_id = v_run AND command_id = c1 AND source_name = 'sim-a';
    SELECT count(*) INTO v_log_b FROM twin.ottoq_twin_operator_log WHERE sim_run_id = v_run AND command_id = c2 AND source_name = 'sim-b';
    SELECT count(*) INTO v_cross FROM twin.ottoq_twin_operator_log
     WHERE sim_run_id = v_run AND ((command_id = c1 AND source_name <> 'sim-a') OR (command_id = c2 AND source_name <> 'sim-b'));
    SELECT jsonb_agg(to_jsonb(i)), sum(i.violations) INTO v_iso, v_viol FROM public.ottoq_assert_operator_isolation(v_run) i;
    v_pin := current_setting('ottoq.v2_twin_run', true);
    RAISE EXCEPTION '0653 V1 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0653 V1 PROBED' THEN RAISE EXCEPTION '0653 V1: the probe itself failed: %', v_msg; END IF;

  IF NOT COALESCE((v_step ->> 'ok')::boolean, false) OR (v_step ->> 'directives')::int < 2 THEN
    RAISE EXCEPTION '0653 V1 FAILED: the step: %', v_step;
  END IF;
  IF v_del_a IS DISTINCT FROM 'v2:sim-a' OR v_del_b IS DISTINCT FROM 'v2:sim-b' THEN
    RAISE EXCEPTION '0653 V1 FAILED: the Waymo directive went to %, the Tesla one to %', v_del_a, v_del_b;
  END IF;
  IF v_log_a <> 1 OR v_log_b <> 1 OR v_cross <> 0 THEN
    RAISE EXCEPTION '0653 V1 FAILED: the log: sim-a % / sim-b % / crossed %', v_log_a, v_log_b, v_cross;
  END IF;
  IF (v_step -> 'operators' -> 'sim-a' ->> 'acks')::int < 1 OR (v_step -> 'operators' -> 'sim-b' ->> 'acks')::int < 1
     OR (v_step -> 'operators' -> 'sim-a' ->> 'not_applied')::int <> 0 OR (v_step -> 'operators' -> 'sim-b' ->> 'not_applied')::int <> 0 THEN
    RAISE EXCEPTION '0653 V1 FAILED: the acks: %', v_step -> 'operators';
  END IF;
  IF NOT COALESCE((v_step2 ->> 'ok')::boolean, false) OR (v_step2 ->> 'directives')::int <> 0 THEN
    RAISE EXCEPTION '0653 V1 FAILED: a second step read again: %', v_step2;
  END IF;
  IF COALESCE(v_viol, -1) <> 0 THEN RAISE EXCEPTION '0653 V1 FAILED: isolation: %', v_iso; END IF;
  IF COALESCE(v_pin, '') <> '' THEN RAISE EXCEPTION '0653 V1 FAILED: the run pin is still set: %', v_pin; END IF;
  RAISE NOTICE '0653 V1 PASSED on run %: the Waymo directive went to sim-a and the Tesla one to sim-b, each answered by its own operator through the door (%); a second step read nothing; isolation 0 violations over %; the pin cleared; all rolled back',
    v_run, v_step -> 'operators', v_iso;
END $v1$;

-- ── V2: who may call what, and the registry ──
DO $v2$
DECLARE r record; v_block int;
BEGIN
  FOR r IN SELECT unnest(ARRAY['twin.ottoq_twin_operator_step(uuid)', 'public.ottoq_assert_operator_isolation(uuid)',
                               'public.ottoq_v2_take_events(text,jsonb,boolean)',
                               'public.ottoq_v2_read_directives(text,bigint,integer,boolean)',
                               'public.ottoq_api_twin_apply_directives(uuid,timestamptz,jsonb)'])::regprocedure AS f
  LOOP
    IF has_function_privilege('anon', r.f, 'EXECUTE') OR has_function_privilege('authenticated', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0653 V2 FAILED: % is executable by anon or authenticated', r.f;
    END IF;
    IF NOT has_function_privilege('service_role', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0653 V2 FAILED: service_role cannot execute %', r.f;
    END IF;
  END LOOP;
  FOR r IN SELECT unnest(ARRAY['twin.ottoq_twin_operators', 'twin.ottoq_twin_operator_log', 'twin.ottoq_twin_operator_state',
                               'twin.ottoq_twin_operator_sequences']) AS t
  LOOP
    IF has_table_privilege('anon', r.t, 'SELECT') OR has_table_privilege('authenticated', r.t, 'SELECT') THEN
      RAISE EXCEPTION '0653 V2 FAILED: anon or authenticated can read %', r.t;
    END IF;
  END LOOP;
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN RAISE EXCEPTION '0653 V2 FAILED: % blocking run-scope defect(s) after registering the new tables', v_block; END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0653_the_twin_speaks_to_otto_q_as_two_operators', false, false,
  'Step 4 of the twin data contract review: the twin''s two operators sim-a (Waymo Nashville) and sim-b (Tesla '
  'Robotaxi TN, Zoox Southeast) with twin keys; twin.ottoq_twin_operator_step (read through the outbox, one walk, '
  'acks through the door); the door''s run pin for them; the payload door reads the twin''s report; '
  'ottoq_assert_operator_isolation; the twin_operator_door flag declared (0). No tick path calls or reads any of it. '
  'FALSE/FALSE.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-10 01:36:31 UTC (8:36 PM CT on 2026-10-09), version 20261010013631 ═══════════════════════════════
--   Claude, MCP apply_migration, the file as committed in 2a06582; the ledger's stored statement is that file byte for
--   byte (md5 bf33a42ce245f485232a67f9702feefc, 50,502 characters, 51,274 bytes). P0, P1, V1 (the step on a copy of the
--   twin depot's newest run, against the live walk), V2 passed in the apply's transaction. Read after: sim-a (Waymo
--   Nashville) and sim-b (Tesla Robotaxi TN, Zoox Southeast), both twin keys, active, streams telemetry/arrival/
--   incident; 0 operator log rows and 0 inbox rows (V1 rolled back); 0 run-scope blocks; twin_operator_door declared
--   with default 0 and no policy row anywhere, so nothing reads a 1.
