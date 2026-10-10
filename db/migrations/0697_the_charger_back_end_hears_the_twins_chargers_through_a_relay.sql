-- migration-version: PENDING
-- migration-name:    the_charger_back_end_hears_the_twins_chargers_through_a_relay
--
-- 0697  **OTTO-Q's charger back end gets its own credential, made on the machine it runs on, and through it reads the
--        twin's charger frames and reports what a real OCPP 2.0.1 back end did with each.**
--        Step 5 of the twin data contract review, the live bridge (csms/README.md, "Still to build").
--
-- ══ §0 THIS FILE HOLDS A DROP: APPLY IT WITH A PERSON PRESENT ═════════════════════════════════════════════════
--
--   ottow_api_keys.source admits oem_webhook, fleet_api and vehicle_telemetry (its CHECK). A charger back end is
--   none of them, and naming it one would mislabel every row it sends. The CHECK is replaced by the same list plus
--   charger_backend, which takes ALTER TABLE ... DROP CONSTRAINT: the database connector asks a person to approve a
--   DROP, and that approval is never worked around.
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   csms/bridge.py has each twin charger say its rows of ottoq_ocpp_messages to the back end (csms/csms_server.py) as
--   an OCPP 2.0.1 station over a real WebSocket. Run beside the back end on AWS, it needs the rows out of this
--   database and its findings back in, with no inbound port on the box and no database key on it. The relay
--   (edge-functions/ottoq-csms-relay) is that door; this file is its database half.
--
--   The credential is a platform source key, 0649's, with one difference that matters: it is made on the box. 0649's
--   issuer makes the key here and returns it once, so it passes through whoever calls it; here the box makes its key,
--   keeps it in its own store and hands over only the SHA-256 and the 14-character prefix, which are not secrets.
--   A person registers the hash (public.ottoq_register_source_key_hash, service role only). Revoking is 0649's.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════
--
--   (a) ottow_api_keys.source admits charger_backend.
--   (b) public.ottoq_register_source_key_hash: 0649's issuer for a key made elsewhere. Same table, same guard door,
--       same checks, and the hash must be 64 lowercase hex characters and new.
--   (c) public.ottoq_csms_pull(key_hash, after, limit, with_chargers): a charger_backend key with the ocpp stream and
--       the twin's data source reads its depot's charger frames sent by a station (cs_to_csms), in message_seq order,
--       after a cursor, 1 to 1000 at a time; a negative cursor starts at the head. with_chargers adds what each charger
--       says in its BootNotification (identifier, vendor, model, serial, firmware). A production key is refused: a
--       real back end hears its chargers directly, and nothing of production's is read through this door.
--   (d) public.ottoq_csms_reports, and public.ottoq_csms_report(key_hash, report): what the bridge found for each batch
--       (frames by outcome and by action, the transactions the back end closed and their seqNo order, the first ten
--       refusals). Evidence, not engine: no run column, so the purge never takes it, and it is how "the twin's
--       chargers are accepted by a real 2.0.1 back end" is quoted with its numbers.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════
--
--   Nothing the engine or the twin runs reads or writes any of it: a new credential kind, two functions only the
--   service role may call, and a table only they write.
--
-- ══ §4 ROLLBACK ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Revoke the back end's key (ottoq_revoke_source_key). The functions and the table stay (dropping needs a person at
--   the connector) and nothing calls them once the relay is not deployed.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0697 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0649_source_keys_are_issued_by_the_platform_and_bind_a_depot_and_a_data_source') THEN
    RAISE EXCEPTION '0697 P1: 0649 is not classified; the source keys this file extends are not there';
  END IF;
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
       WHERE conrelid = 'public.ottow_api_keys'::regclass AND conname = 'ottow_api_keys_source_check')
     IS DISTINCT FROM 'CHECK ((source = ANY (ARRAY[''oem_webhook''::text, ''fleet_api''::text, ''vehicle_telemetry''::text])))' THEN
    RAISE EXCEPTION '0697 P1: ottow_api_keys.source is not checked as this file was written against';
  END IF;
  IF to_regprocedure('public.ottoq_source_key_check(text,text)') IS NULL THEN
    RAISE EXCEPTION '0697 P1: public.ottoq_source_key_check(text,text) is missing';
  END IF;
  IF to_regprocedure('public.ottoq_register_source_key_hash(uuid,text,text,text,text,text,text[])') IS NOT NULL
     OR to_regprocedure('public.ottoq_csms_pull(text,bigint,integer,boolean)') IS NOT NULL
     OR to_regprocedure('public.ottoq_csms_report(text,jsonb)') IS NOT NULL
     OR to_regclass('public.ottoq_csms_reports') IS NOT NULL THEN
    RAISE EXCEPTION '0697 P1: an object this file creates exists already';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers WHERE depot_id = '11111111-1111-1111-1111-111111111111') THEN
    RAISE EXCEPTION '0697 P1: the twin depot has no chargers';
  END IF;
END $premises$;

-- ── (a) a charger back end is a kind of source ──
ALTER TABLE public.ottow_api_keys DROP CONSTRAINT ottow_api_keys_source_check;
ALTER TABLE public.ottow_api_keys ADD CONSTRAINT ottow_api_keys_source_check
  CHECK (source = ANY (ARRAY['oem_webhook'::text, 'fleet_api'::text, 'vehicle_telemetry'::text, 'charger_backend'::text]));

-- ── (b) a key made elsewhere, registered by its hash ──
CREATE FUNCTION public.ottoq_register_source_key_hash(
  p_depot_id uuid, p_source text, p_source_name text, p_key_hash text, p_key_prefix text,
  p_data_source text DEFAULT 'production', p_streams text[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_id uuid; v_name text := btrim(p_source_name); v_ds text := COALESCE(p_data_source, 'production');
BEGIN
  /* 0697: 0649's issuer for a key its holder made. The key never reaches this database; its SHA-256 (lowercase hex,
     of the whole key) and its first 14 characters do. */
  IF p_depot_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.depots WHERE id = p_depot_id) THEN
    RAISE EXCEPTION 'ottoq_register_source_key_hash: unknown depot %', p_depot_id;
  END IF;
  IF COALESCE(v_name, '') = '' THEN
    RAISE EXCEPTION 'ottoq_register_source_key_hash: source_name is required';
  END IF;
  IF p_key_hash IS NULL OR p_key_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'ottoq_register_source_key_hash: the hash is the SHA-256 of the key, 64 lowercase hex characters';
  END IF;
  IF p_key_prefix IS NULL OR p_key_prefix !~ '^ottow_[0-9a-f]{8}$' THEN
    RAISE EXCEPTION 'ottoq_register_source_key_hash: the prefix is the key''s first 14 characters, ottow_ and 8 hex';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottow_api_keys WHERE key_hash = p_key_hash) THEN
    RAISE EXCEPTION 'ottoq_register_source_key_hash: that key is registered already';
  END IF;
  PERFORM set_config('ottoq.source_key_door', 'on', true);
  INSERT INTO public.ottow_api_keys (depot_id, key_hash, key_prefix, source, source_name, data_source, streams)
  VALUES (p_depot_id, p_key_hash, p_key_prefix, p_source, v_name, v_ds, p_streams)
  RETURNING id INTO v_id;
  PERFORM set_config('ottoq.source_key_door', 'off', true);
  RETURN jsonb_build_object('id', v_id, 'key_prefix', p_key_prefix, 'depot_id', p_depot_id, 'source', p_source,
                            'source_name', v_name, 'data_source', v_ds, 'streams', to_jsonb(p_streams));
END $fn$;

-- ── (c) the twin's charger frames, for the back end ──
CREATE FUNCTION public.ottoq_csms_pull(p_key_hash text, p_after bigint, p_limit integer DEFAULT 200,
                                       p_with_chargers boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_chk jsonb; v_depot uuid; v_ds text; v_limit int := LEAST(GREATEST(COALESCE(p_limit, 200), 1), 1000);
  v_rows jsonb; v_next bigint; v_n int; v_chargers jsonb;
BEGIN
  /* 0697: what the twin's chargers sent, in the order they sent it, to OTTO-Q's charger back end. */
  v_chk := public.ottoq_source_key_check(p_key_hash, 'ocpp');
  IF NOT COALESCE((v_chk ->> 'ok')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_chk ->> 'reason');
  END IF;
  IF v_chk ->> 'source' IS DISTINCT FROM 'charger_backend' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_a_charger_backend_key');
  END IF;
  v_depot := (v_chk ->> 'depot_id')::uuid;
  v_ds := v_chk ->> 'data_source';
  IF v_ds IS DISTINCT FROM 'twin' THEN   -- a real back end hears its own chargers; nothing of production's comes out
    RETURN jsonb_build_object('ok', false, 'reason', 'pull_is_for_the_twin');
  END IF;
  IF p_with_chargers THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('ocpp_identifier', c.ocpp_identifier, 'vendor', c.vendor, 'model', c.model,
                                                 'serial_number', c.serial_number, 'firmware_version', c.firmware_version,
                                                 'max_kw', c.max_kw, 'num_connectors', c.num_connectors)
                              ORDER BY c.ocpp_identifier), '[]'::jsonb)
      INTO v_chargers
      FROM public.ottoq_ocpp_chargers c
     WHERE c.depot_id = v_depot AND c.decommissioned_at IS NULL;
  END IF;
  IF p_after IS NULL OR p_after < 0 THEN   -- start at the head: what is sent from now on
    SELECT COALESCE(max(m.message_seq), 0) INTO v_next FROM public.ottoq_ocpp_messages m;
    RETURN jsonb_build_object('ok', true, 'depot_id', v_depot, 'data_source', v_ds, 'rows', '[]'::jsonb,
                              'next_after', v_next, 'more', false)
           || CASE WHEN p_with_chargers THEN jsonb_build_object('chargers', v_chargers) ELSE '{}'::jsonb END;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('message_seq', x.message_seq, 'ocpp_identifier', x.ocpp_identifier,
                                               'direction', x.direction, 'message_type', x.message_type,
                                               'payload', x.payload, 'sim_run_id', x.sim_run_id,
                                               'sim_clock_at', x.sim_clock_at) ORDER BY x.message_seq), '[]'::jsonb),
         max(x.message_seq), count(*)
    INTO v_rows, v_next, v_n
    FROM (SELECT m.message_seq, c.ocpp_identifier, m.direction, m.message_type, m.payload, m.sim_run_id, m.sim_clock_at
            FROM public.ottoq_ocpp_messages m
            JOIN public.ottoq_ocpp_chargers c ON c.charger_id = m.charger_id
           WHERE m.message_seq > p_after AND c.depot_id = v_depot AND m.data_source = v_ds
             AND m.direction = 'cs_to_csms'
           ORDER BY m.message_seq
           LIMIT v_limit) x;
  RETURN jsonb_build_object('ok', true, 'depot_id', v_depot, 'data_source', v_ds, 'rows', v_rows,
                            'next_after', COALESCE(v_next, p_after), 'more', v_n = v_limit)
         || CASE WHEN p_with_chargers THEN jsonb_build_object('chargers', v_chargers) ELSE '{}'::jsonb END;
END $fn$;

-- ── (d) what the back end did with them ──
CREATE TABLE public.ottoq_csms_reports (
  report_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  key_id         uuid NOT NULL,
  key_prefix     text NOT NULL,
  depot_id       uuid NOT NULL,
  data_source    text NOT NULL,
  received_at    timestamptz NOT NULL DEFAULT now(),
  from_seq       bigint NOT NULL,
  to_seq         bigint NOT NULL,
  frames         integer NOT NULL CHECK (frames >= 0),
  accepted       integer NOT NULL CHECK (accepted >= 0),
  not_2_0_1      integer NOT NULL CHECK (not_2_0_1 >= 0),
  csms_error     integer NOT NULL CHECK (csms_error >= 0),
  not_a_station_frame integer NOT NULL CHECK (not_a_station_frame >= 0),
  by_action      jsonb NOT NULL DEFAULT '{}'::jsonb,
  transactions   jsonb NOT NULL DEFAULT '{}'::jsonb,
  first_refusals jsonb NOT NULL DEFAULT '[]'::jsonb,
  bridge         jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (to_seq >= from_seq),
  CHECK (frames = accepted + not_2_0_1 + csms_error + not_a_station_frame)
);
COMMENT ON TABLE public.ottoq_csms_reports IS
  '0697: what OTTO-Q''s charger back end (csms/) did with each batch of the twin''s charger frames, as its bridge '
  'reported it through ottoq-csms-relay: frames by outcome (accepted, not_2_0_1, csms_error, not_a_station_frame) and '
  'by action, the transactions it closed and their seqNo order. Evidence: no run column, kept past every purge.';
ALTER TABLE public.ottoq_csms_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ottoq_csms_reports FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.ottoq_csms_report(p_key_hash text, p_report jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_chk jsonb; v_o jsonb; v_id bigint;
BEGIN
  /* 0697: the bridge's report of one batch. The key decides the depot and the data source; the report only counts. */
  v_chk := public.ottoq_source_key_check(p_key_hash, 'ocpp');
  IF NOT COALESCE((v_chk ->> 'ok')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_chk ->> 'reason');
  END IF;
  IF v_chk ->> 'source' IS DISTINCT FROM 'charger_backend' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_a_charger_backend_key');
  END IF;
  IF jsonb_typeof(p_report) IS DISTINCT FROM 'object' OR jsonb_typeof(p_report -> 'outcomes') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_report -> 'frames') IS DISTINCT FROM 'number'
     OR jsonb_typeof(p_report -> 'from_seq') IS DISTINCT FROM 'number' OR jsonb_typeof(p_report -> 'to_seq') IS DISTINCT FROM 'number'
     OR length(p_report::text) > 262144 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'report_shape');
  END IF;
  v_o := p_report -> 'outcomes';
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(v_o) k WHERE k NOT IN ('accepted', 'not_2_0_1', 'csms_error', 'not_a_station_frame'))
     OR EXISTS (SELECT 1 FROM jsonb_each(v_o) e WHERE jsonb_typeof(e.value) <> 'number' OR (e.value #>> '{}')::numeric < 0
                                                   OR (e.value #>> '{}')::numeric <> trunc((e.value #>> '{}')::numeric)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'report_outcomes');
  END IF;
  BEGIN
    INSERT INTO public.ottoq_csms_reports (key_id, key_prefix, depot_id, data_source, from_seq, to_seq, frames, accepted,
                                           not_2_0_1, csms_error, not_a_station_frame, by_action, transactions,
                                           first_refusals, bridge)
    VALUES ((v_chk ->> 'key_id')::uuid, v_chk ->> 'key_prefix', (v_chk ->> 'depot_id')::uuid, v_chk ->> 'data_source',
            (p_report ->> 'from_seq')::bigint, (p_report ->> 'to_seq')::bigint, (p_report ->> 'frames')::int,
            COALESCE((v_o ->> 'accepted')::int, 0), COALESCE((v_o ->> 'not_2_0_1')::int, 0),
            COALESCE((v_o ->> 'csms_error')::int, 0), COALESCE((v_o ->> 'not_a_station_frame')::int, 0),
            CASE WHEN jsonb_typeof(p_report -> 'by_action') = 'object' THEN p_report -> 'by_action' ELSE '{}'::jsonb END,
            CASE WHEN jsonb_typeof(p_report -> 'transactions') = 'object' THEN p_report -> 'transactions' ELSE '{}'::jsonb END,
            CASE WHEN jsonb_typeof(p_report -> 'first_refusals') = 'array'
                 THEN (SELECT COALESCE(jsonb_agg(r), '[]'::jsonb) FROM (SELECT r FROM jsonb_array_elements(p_report -> 'first_refusals') r LIMIT 10) s)
                 ELSE '[]'::jsonb END,
            CASE WHEN jsonb_typeof(p_report -> 'bridge') = 'object' THEN p_report -> 'bridge' ELSE '{}'::jsonb END)
    RETURNING report_id INTO v_id;
  EXCEPTION WHEN check_violation THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'report_does_not_add_up');
  END;
  RETURN jsonb_build_object('ok', true, 'report_id', v_id);
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_register_source_key_hash(uuid,text,text,text,text,text,text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_csms_pull(text,bigint,integer,boolean)                          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_csms_report(text,jsonb)                                         FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_register_source_key_hash(uuid,text,text,text,text,text,text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_csms_pull(text,bigint,integer,boolean)                          TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_csms_report(text,jsonb)                                         TO service_role;

-- ── V1: register, read, report, and every refusal; the probe keys and report roll back with the sub-block ──
DO $v1$
DECLARE
  v_twin uuid := '11111111-1111-1111-1111-111111111111';
  h_ok text := encode(sha256(convert_to('ottow_' || repeat('a1', 32), 'UTF8')), 'hex');
  h_prod text := encode(sha256(convert_to('ottow_' || repeat('b2', 32), 'UTF8')), 'hex');
  h_nostream text := encode(sha256(convert_to('ottow_' || repeat('c3', 32), 'UTF8')), 'hex');
  h_fleet text := encode(sha256(convert_to('ottow_' || repeat('d4', 32), 'UTF8')), 'hex');
  v_head jsonb; v_page jsonb; v_from bigint; r jsonb := '{}'::jsonb; v_msg text; v_dup boolean := false; v_bad boolean := false;
  v_rep_ok jsonb; v_rep_sum jsonb; v_rep_key jsonb; v_rep_fleet jsonb;
BEGIN
  BEGIN
    PERFORM public.ottoq_register_source_key_hash(v_twin, 'charger_backend', '0697 probe', h_ok, 'ottow_a1a1a1a1', 'twin', ARRAY['ocpp']);
    PERFORM public.ottoq_register_source_key_hash(v_twin, 'charger_backend', '0697 probe prod', h_prod, 'ottow_b2b2b2b2', 'production', ARRAY['ocpp']);
    PERFORM public.ottoq_register_source_key_hash(v_twin, 'charger_backend', '0697 probe telemetry', h_nostream, 'ottow_c3c3c3c3', 'twin', ARRAY['telemetry']);
    PERFORM public.ottoq_register_source_key_hash(v_twin, 'fleet_api', '0697 probe fleet', h_fleet, 'ottow_d4d4d4d4', 'twin', ARRAY['ocpp']);
    BEGIN
      PERFORM public.ottoq_register_source_key_hash(v_twin, 'charger_backend', '0697 probe again', h_ok, 'ottow_a1a1a1a1', 'twin', ARRAY['ocpp']);
    EXCEPTION WHEN OTHERS THEN v_dup := SQLERRM LIKE '%registered already%';
    END;
    BEGIN
      PERFORM public.ottoq_register_source_key_hash(v_twin, 'charger_backend', '0697 probe bad', 'ABC', 'ottow_a1a1a1a1', 'twin', ARRAY['ocpp']);
    EXCEPTION WHEN OTHERS THEN v_bad := SQLERRM LIKE '%64 lowercase hex%';
    END;
    v_head := public.ottoq_csms_pull(h_ok, -1, 200, true);
    SELECT GREATEST(0, max(m.message_seq) - 2000) INTO v_from
      FROM public.ottoq_ocpp_messages m JOIN public.ottoq_ocpp_chargers c ON c.charger_id = m.charger_id
     WHERE c.depot_id = v_twin AND m.data_source = 'twin';
    v_page := public.ottoq_csms_pull(h_ok, v_from, 50, false);
    -- each report its own statement, so the read of what was kept below sees it
    v_rep_ok := public.ottoq_csms_report(h_ok, jsonb_build_object('from_seq', v_from, 'to_seq', v_from + 3, 'frames', 3,
                  'outcomes', jsonb_build_object('accepted', 2, 'not_2_0_1', 1),
                  'by_action', jsonb_build_object('TransactionEvent:accepted', 2, 'Authorize:not_2_0_1', 1)));
    v_rep_sum := public.ottoq_csms_report(h_ok, jsonb_build_object('from_seq', 1, 'to_seq', 2, 'frames', 5,
                   'outcomes', jsonb_build_object('accepted', 2)));
    v_rep_key := public.ottoq_csms_report(h_ok, jsonb_build_object('from_seq', 1, 'to_seq', 2, 'frames', 1,
                   'outcomes', jsonb_build_object('fine', 1)));
    v_rep_fleet := public.ottoq_csms_report(h_fleet, jsonb_build_object('from_seq', 1, 'to_seq', 2, 'frames', 0,
                     'outcomes', '{}'::jsonb));
    r := jsonb_build_object(
      'dup', v_dup, 'bad', v_bad, 'head', v_head - 'chargers', 'chargers', jsonb_array_length(v_head -> 'chargers'),
      'page_n', jsonb_array_length(v_page -> 'rows'), 'page_more', v_page -> 'more', 'page_next', v_page -> 'next_after',
      'page_from', v_from,
      'page_ordered', (SELECT bool_and((a.v ->> 'message_seq')::bigint < (b.v ->> 'message_seq')::bigint)
                         FROM jsonb_array_elements(v_page -> 'rows') WITH ORDINALITY a(v, i)
                         JOIN jsonb_array_elements(v_page -> 'rows') WITH ORDINALITY b(v, i) ON b.i = a.i + 1),
      'page_dirs', (SELECT jsonb_agg(DISTINCT e ->> 'direction') FROM jsonb_array_elements(v_page -> 'rows') e),
      'page_twin', (SELECT bool_and(EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers c
                                             WHERE c.ocpp_identifier = e ->> 'ocpp_identifier' AND c.depot_id = v_twin))
                      FROM jsonb_array_elements(v_page -> 'rows') e),
      'prod', public.ottoq_csms_pull(h_prod, 0, 10, false), 'nostream', public.ottoq_csms_pull(h_nostream, 0, 10, false),
      'fleet', public.ottoq_csms_pull(h_fleet, 0, 10, false),
      'unknown', public.ottoq_csms_pull(repeat('0', 64), 0, 10, false),
      'report_ok', v_rep_ok, 'report_bad_sum', v_rep_sum, 'report_bad_key', v_rep_key, 'report_fleet', v_rep_fleet,
      'stored', (SELECT to_jsonb(x) FROM public.ottoq_csms_reports x WHERE x.key_prefix = 'ottow_a1a1a1a1'));
    RAISE EXCEPTION '0697 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0697 PROBED' THEN RAISE EXCEPTION '0697 V1 probe failed: %', v_msg; END IF;
  IF NOT (r ->> 'dup')::boolean OR NOT (r ->> 'bad')::boolean THEN
    RAISE EXCEPTION '0697 V1 FAILED: a duplicate or malformed hash was registered: %', r;
  END IF;
  IF r #>> '{head,ok}' <> 'true' OR jsonb_array_length(r #> '{head,rows}') <> 0 OR (r #>> '{head,next_after}')::bigint < (r ->> 'page_from')::bigint
     OR (r ->> 'chargers')::int < 1 THEN
    RAISE EXCEPTION '0697 V1 FAILED: a negative cursor did not start at the head with the chargers: %', r;
  END IF;
  IF (r ->> 'page_n')::int < 1 OR (r ->> 'page_n')::int > 50 OR NOT COALESCE((r ->> 'page_ordered')::boolean, true)
     OR r -> 'page_dirs' <> '["cs_to_csms"]'::jsonb OR NOT (r ->> 'page_twin')::boolean
     OR (r ->> 'page_next')::bigint <= (r ->> 'page_from')::bigint THEN
    RAISE EXCEPTION '0697 V1 FAILED: a page of frames is not the twin depot''s station frames in order after the cursor: %', r;
  END IF;
  IF r #>> '{prod,reason}' IS DISTINCT FROM 'pull_is_for_the_twin' OR r #>> '{nostream,reason}' IS DISTINCT FROM 'stream_not_allowed'
     OR r #>> '{fleet,reason}' IS DISTINCT FROM 'not_a_charger_backend_key' OR r #>> '{unknown,reason}' IS DISTINCT FROM 'unknown_or_revoked_key' THEN
    RAISE EXCEPTION '0697 V1 FAILED: a key that may not read frames was not refused for its reason: %', r;
  END IF;
  IF r #>> '{report_ok,ok}' <> 'true' OR r #>> '{report_bad_sum,reason}' IS DISTINCT FROM 'report_does_not_add_up'
     OR r #>> '{report_bad_key,reason}' IS DISTINCT FROM 'report_outcomes' OR r #>> '{report_fleet,reason}' IS DISTINCT FROM 'not_a_charger_backend_key'
     OR (r #>> '{stored,accepted}')::int <> 2 OR (r #>> '{stored,not_2_0_1}')::int <> 1 OR r #>> '{stored,data_source}' <> 'twin' THEN
    RAISE EXCEPTION '0697 V1 FAILED: a report was not kept as sent, or a bad one was kept: %', r;
  END IF;
  RAISE NOTICE '0697 V1 PASSED: a key made elsewhere registered by its hash (a duplicate and a malformed hash refused); the head and % chargers; % frames in order after a cursor, all station frames at the twin depot; production, wrong stream, wrong kind of key and unknown key refused; a report kept and two that do not add up refused (all rolled back)',
    r ->> 'chargers', r ->> 'page_n';
END $v1$;

-- ── V2: the source list, the grants, the table's locks ──
DO $v2$
BEGIN
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
       WHERE conrelid = 'public.ottow_api_keys'::regclass AND conname = 'ottow_api_keys_source_check')
     NOT LIKE '%charger_backend%' THEN
    RAISE EXCEPTION '0697 V2 FAILED: charger_backend is not a source';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_csms_pull(text,bigint,integer,boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_csms_report(text,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_register_source_key_hash(uuid,text,text,text,text,text,text[])', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_register_source_key_hash(uuid,text,text,text,text,text,text[])', 'EXECUTE')
     OR has_table_privilege('anon', 'public.ottoq_csms_reports', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ottoq_csms_reports', 'SELECT')
     OR NOT has_function_privilege('service_role', 'public.ottoq_csms_pull(text,bigint,integer,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION '0697 V2 FAILED: the relay''s functions or table are reachable by the public key, or not by the service role';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.ottoq_csms_reports'::regclass) THEN
    RAISE EXCEPTION '0697 V2 FAILED: the reports table has no row security';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottow_api_keys WHERE source = 'charger_backend') THEN
    RAISE EXCEPTION '0697 V2 FAILED: a probe key survived';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block') THEN
    RAISE EXCEPTION '0697 V2 FAILED: the run-scope registry reports a blocking defect';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0697_the_charger_back_end_hears_the_twins_chargers_through_a_relay', false, false,
  'Step 5, the live bridge''s database half. ottow_api_keys.source admits charger_backend (its CHECK replaced, a DROP '
  'approved at the connector); ottoq_register_source_key_hash registers a key made elsewhere by its SHA-256; '
  'ottoq_csms_pull gives a charger_backend twin key its depot''s station frames after a cursor; ottoq_csms_report keeps '
  'what the back end did with them in ottoq_csms_reports (evidence). Service role only. Nothing the engine or the twin '
  'runs reads or writes them: FALSE/FALSE.',
  now());

COMMIT;
