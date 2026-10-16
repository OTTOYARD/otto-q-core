-- tests/fixtures/model_call_ledger_stub.sql
--
-- The evidence ledger of external model calls (db/migrations/0340, 0341, 0415) as the live catalog holds it, for the
-- scratch chains that apply db/migrations/0721 (which records OTTO-Command's model calls in it). Read from the live
-- catalog (gxdrcyphqjzjsuhxuqtg) on 2026-10-14 between 17:59 and 18:17 UTC (12:59-1:17 PM CT), read-only:
--   public.ottoq_log_model_call(...)                    md5(pg_get_functiondef) 482dcde3ae386e07da3e8ebcf5188373
--   public.ottoq_model_call_ledger_append_only()        md5(pg_get_functiondef) 43eeb790fe779fb15bd06158f5e1ea16
--   public.ottoq_model_call_outcome_class(text)         md5(pg_get_functiondef) 05ce85781fc4c45a6cc991b9cea9dc25
-- the table's columns, defaults, indexes and trigger as the catalog lists them, and the view
-- public.ottoq_intelligence_ledger as pg_get_viewdef returns it. tests/test_ottocommand_executor_sql.py asserts the three
-- md5s on the scratch cluster, so a drift between this file and the live catalog fails the suite, not an apply.
-- Loads after tests/fixtures/agent_gateway_stub_engine.sql (it registers the ledger's run key in its registry).

CREATE SEQUENCE IF NOT EXISTS public.ottoq_model_call_ledger_call_id_seq;
CREATE TABLE public.ottoq_model_call_ledger (
  call_id           bigint NOT NULL DEFAULT nextval('ottoq_model_call_ledger_call_id_seq'::regclass) PRIMARY KEY,
  sim_run_id        uuid,
  depot_id          uuid,
  tick_seq          bigint,
  sim_clock         timestamp with time zone,
  chain_id          text,
  provider          text NOT NULL,
  role              text NOT NULL,
  model             text,
  endpoint          text,
  http_status       integer,
  latency_ms        integer,
  outcome           text NOT NULL,
  proposals_out     integer,
  rationale_present boolean,
  detail            jsonb NOT NULL DEFAULT '{}'::jsonb,
  called_at         timestamp with time zone NOT NULL DEFAULT now(),
  source_kind       text NOT NULL DEFAULT 'live'::text
);
ALTER SEQUENCE public.ottoq_model_call_ledger_call_id_seq OWNED BY public.ottoq_model_call_ledger.call_id;
CREATE INDEX ottoq_model_call_ledger_provider_at_idx ON public.ottoq_model_call_ledger USING btree (provider, called_at DESC);
CREATE INDEX ottoq_model_call_ledger_run_idx ON public.ottoq_model_call_ledger USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
CREATE INDEX ottoq_model_call_ledger_chain_idx ON public.ottoq_model_call_ledger USING btree (chain_id) WHERE (chain_id IS NOT NULL);

CREATE OR REPLACE FUNCTION public.ottoq_model_call_ledger_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF COALESCE(current_setting('ottoq.model_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_model_call_ledger is append-only: % refused. Set ottoq.model_ledger_unlock=on in the session to override, and say why in a migration.',
    TG_OP
    USING ERRCODE = '42501';
END $function$;

CREATE TRIGGER ottoq_model_call_ledger_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_model_call_ledger FOR EACH ROW EXECUTE FUNCTION ottoq_model_call_ledger_append_only();

CREATE OR REPLACE FUNCTION public.ottoq_log_model_call(p_provider text, p_role text, p_outcome text, p_sim_run_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_tick_seq bigint DEFAULT NULL::bigint, p_sim_clock timestamp with time zone DEFAULT NULL::timestamp with time zone, p_chain_id text DEFAULT NULL::text, p_model text DEFAULT NULL::text, p_endpoint text DEFAULT NULL::text, p_http_status integer DEFAULT NULL::integer, p_latency_ms integer DEFAULT NULL::integer, p_proposals_out integer DEFAULT NULL::integer, p_rationale_present boolean DEFAULT NULL::boolean, p_detail jsonb DEFAULT '{}'::jsonb, p_source_kind text DEFAULT 'live'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_id bigint;
BEGIN
  INSERT INTO public.ottoq_model_call_ledger
    (sim_run_id, depot_id, tick_seq, sim_clock, chain_id, provider, role, model,
     endpoint, http_status, latency_ms, outcome, proposals_out, rationale_present,
     detail, source_kind)
  VALUES
    (p_sim_run_id, p_depot_id, p_tick_seq, p_sim_clock, p_chain_id,
     p_provider, p_role, p_model, p_endpoint, p_http_status, p_latency_ms,
     p_outcome, p_proposals_out, p_rationale_present,
     COALESCE(p_detail,'{}'::jsonb), COALESCE(p_source_kind,'live'))
  RETURNING call_id INTO v_id;
  RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.ottoq_model_call_outcome_class(p_outcome text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE lower(COALESCE(p_outcome,''))
    WHEN 'answered'          THEN 'answered'
    WHEN 'abstained'         THEN 'abstained'
    WHEN 'fallback'          THEN 'fallback'
    WHEN 'refused'           THEN 'refused'
    WHEN 'error'             THEN 'error'
    WHEN 'enacted'           THEN 'answered'
    WHEN 'superseded'        THEN 'refused'
    WHEN 'expired'           THEN 'refused'
    WHEN 'noop_no_candidate' THEN 'abstained'
    WHEN 'shielded'          THEN 'refused'
    WHEN 'overridden'        THEN 'refused'
    -- 0415: three live outcomes the classifier never knew, together exactly the 3,538 rows the
    -- view reported as unclassified for cpsat_service. solved_but_zero_proposals is 'abstained'
    -- HERE because the string alone cannot distinguish "declined everything" from "offered
    -- nothing"; the view splits it on detail->>'rows'. See db/migrations/0415 §1(c).
    WHEN 'solved_but_zero_proposals' THEN 'abstained'
    WHEN 'deferred_site_power_cap'   THEN 'abstained'
    WHEN 'errored'                   THEN 'error'
    ELSE 'unclassified'
  END;
$function$;

CREATE VIEW public.ottoq_intelligence_ledger AS
 SELECT provider,
    role,
    count(*) FILTER (WHERE (endpoint IS NOT NULL)) AS calls,
    count(*) FILTER (WHERE ((http_status >= 200) AND (http_status <= 299))) AS provider_status_2xx,
    count(*) FILTER (WHERE ((http_status IS NOT NULL) AND ((http_status < 200) OR (http_status > 299)))) AS provider_status_other,
    count(*) FILTER (WHERE (http_status IS NULL)) AS provider_status_unknown,
    count(*) FILTER (WHERE (ottoq_model_call_outcome_class(outcome) = 'answered'::text)) AS answered,
    count(*) FILTER (WHERE (ottoq_model_call_outcome_class(outcome) = 'abstained'::text)) AS abstained,
    count(*) FILTER (WHERE (ottoq_model_call_outcome_class(outcome) = 'fallback'::text)) AS fell_back,
    count(*) FILTER (WHERE (ottoq_model_call_outcome_class(outcome) = 'refused'::text)) AS refused,
    count(*) FILTER (WHERE (ottoq_model_call_outcome_class(outcome) = 'error'::text)) AS errored,
    count(*) FILTER (WHERE (ottoq_model_call_outcome_class(outcome) = 'unclassified'::text)) AS unclassified,
    jsonb_object_agg(outcome, n ORDER BY outcome) AS outcomes,
    COALESCE(sum(proposals_out), (0)::bigint) AS proposals,
    count(*) FILTER (WHERE ((COALESCE(((detail ->> 'l1_rules_evaluated'::text))::integer, 0) = 0) AND (role = 'agent'::text))) AS agent_calls_with_no_l1_rules,
    round(avg(latency_ms) FILTER (WHERE (endpoint IS NOT NULL))) AS avg_latency_ms,
    max(latency_ms) FILTER (WHERE (endpoint IS NOT NULL)) AS max_latency_ms,
    count(*) FILTER (WHERE ((endpoint IS NOT NULL) AND (latency_ms > 30000))) AS calls_over_one_tick,
    min(called_at) AS first_call,
    max(called_at) AS last_call,
    count(*) FILTER (WHERE (source_kind = 'backfill'::text)) AS reconstructed,
    count(*) AS ledger_rows,
    count(*) FILTER (WHERE (endpoint IS NULL)) AS captured_decisions,
    count(*) FILTER (WHERE ((outcome = 'solved_but_zero_proposals'::text) AND (COALESCE(((detail ->> 'rows'::text))::integer, '-1'::integer) = 0))) AS no_candidate_calls,
    count(*) FILTER (WHERE ((outcome = 'solved_but_zero_proposals'::text) AND (COALESCE(((detail ->> 'rows'::text))::integer, '-1'::integer) > 0))) AS declined_all_calls,
    round(avg(latency_ms) FILTER (WHERE (endpoint IS NULL))) AS avg_decision_latency_ms,
    max(latency_ms) FILTER (WHERE (endpoint IS NULL)) AS max_decision_latency_ms,
    count(*) FILTER (WHERE ((endpoint IS NULL) AND (latency_ms > 30000))) AS decisions_over_one_tick
   FROM ( SELECT l.call_id,
            l.sim_run_id,
            l.depot_id,
            l.tick_seq,
            l.sim_clock,
            l.chain_id,
            l.provider,
            l.role,
            l.model,
            l.endpoint,
            l.http_status,
            l.latency_ms,
            l.outcome,
            l.proposals_out,
            l.rationale_present,
            l.detail,
            l.called_at,
            l.source_kind,
            count(*) OVER (PARTITION BY l.provider, l.role, l.outcome) AS n
           FROM ottoq_model_call_ledger l) z
  GROUP BY provider, role;

--: live grants: the writer is executable by authenticated and service_role (a finding 0721 reports, not one it changes)
REVOKE ALL ON FUNCTION public.ottoq_log_model_call(text, text, text, uuid, uuid, bigint, timestamptz, text, text, text, integer, integer, integer, boolean, jsonb, text) FROM PUBLIC;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.ottoq_log_model_call(text, text, text, uuid, uuid, bigint, timestamptz, text, text, text, integer, integer, integer, boolean, jsonb, text) TO authenticated, service_role';
  END IF;
END $g$;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES
  ('public', 'ottoq_model_call_ledger', 'sim_run_id', 'evidence', '0340: one row per external model or solver call; outlives its run.');
