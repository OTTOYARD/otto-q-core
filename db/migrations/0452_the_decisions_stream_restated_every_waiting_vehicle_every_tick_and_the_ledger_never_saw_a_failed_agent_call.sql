-- migration-version: 20260923060345
-- migration-name:    the_decisions_stream_restated_every_waiting_vehicle_every_tick_and_the_ledger_never_saw_a_failed_agent_call
--
-- 0452  **Two reporting defects behind the cockpit's Decisions stream, both measured on run 736406cf (busy_day, twin
--       depot) at 2026-09-23 ~05:55 UTC. `db/checks/0356` holds the queries. FINDINGS G189 (stream) and G190 (ledger).**
--
-- ══ §1 THE STREAM WAS 97% RESTATEMENT, AND THE AGENT FELL OFF THE PAGE ═══════════════════════════════════════
--
--   `ottoq_activity_feed` returns one row per `ottoq_decisions` row. The decide path writes a row for EVERY waiting
--   vehicle on EVERY tick, whether or not anything about that vehicle changed. Over the run's first 311 decided ticks:
--
--       task_start          12,197 rows,   131 changes   (98.9% the same verdict restated)   39.2 rows / tick
--       stall_assignment     4,557 rows,   363 changes   (92.0%)                             14.7 rows / tick
--       bay_reconcile          441 rows,    16 changes   (96.4%)
--       bess_dispatch          311 rows,    13 changes   (95.8%)
--       orchestrator_agent      28 rows                  (every one its own decision)
--
--   The cockpit polls the newest 200 rows every 4 s. At ~58 rows per tick a page is ~3.4 ticks deep, and the agent
--   fires at most every third tick -- so **the newest 500 rows contained zero agent decisions** when measured, and the
--   stream Chase asked for ("a live stream of comments and decisions that are coming through and being proposed or
--   enacted") showed "Promote -> promote_ready" forty times a tick. That verdict is not a promotion: in
--   `ottoq_decide_tick` (5) only `admit_service` acts; `promote_ready` is `ottoq_l2_propose_service` saying no
--   service-bay work blocks the vehicle, recorded as `enacted` and changing nothing.
--
--   FIX: `p_changes_only` returns only the decision at which a (entity, action) pair's verdict CHANGED, inside the
--   last `p_window_ticks` ticks, with `held_ticks` (how many ticks it then stood), `last_at` and `standing` (still in
--   force on the newest tick). Two decisions are the same verdict when outcome, verb, reason, stall, battery action,
--   service step, battery mode, plan shift and override codes all agree -- NOT the rationale's live counters
--   (`in_svc`, `soc_pct`...), which move with other vehicles and would make every row a "change". Every agent pass is
--   its own decision. The default (`p_changes_only = false`) returns exactly what it returned before, plus four
--   columns, so a caller that does not opt in sees no change. `decision_seq` is returned so a client has a real row
--   identity instead of composing one.
--
--   The signature changes (two parameters, four columns), which CREATE OR REPLACE cannot do, so the function is
--   dropped and recreated in this transaction with its ACL restored exactly: anon, authenticated, service_role,
--   postgres; no PUBLIC. It has no dependent objects and no SQL caller (checked below); its one caller is the cockpit.
--   Also in the body: an agent pass whose model call failed now reads `deterministic_fallback -> ...` in `engine`
--   and has no `agent_model`, instead of the literal model name "none".
--
-- ══ §2 THE EVIDENCE LEDGER RECORDED EVERY AGENT CALL THAT WORKED AND NONE THAT FAILED ═════════════════════════
--
--   `ottoq_model_call_ledger` is the instrument CLAUDE.md rule 6 says to quote. Its agent rows come from
--   `ottoq_capture_decision_model_call_trg`, which fires `WHEN l2_engine IN ('nemotron','forward_lex','llm_advisor')`.
--   `trg_ottoq_stamp_l2_engine` sets `l2_engine` from `enacted_action->>'source'`, and an agent pass whose model call
--   failed carries `source = 'deterministic_fallback'`. So **a failed call is never captured.** Measured: the ledger's
--   last `nvidia_nemotron` row is 2026-09-23 04:12:10 UTC; from 05:30 the agent made 33 passes, each one an attempted
--   call to the NVIDIA endpoint that timed out at 75 s (G188), and the ledger holds none of them. Read through
--   `ottoq_intelligence_ledger`, an endpoint that failed every call for half an hour looks like an agent that simply
--   stopped being called -- rule 6's "unquantified in both directions" arriving through the capture path.
--
--   FIX: the trigger also fires for an agent pass (`resolved_action_context = 'orchestrator_agent'`) that fell back
--   AFTER attempting a call (`propose_latency_ms > 0`; the agent sets it only when a key existed and it called out),
--   and the function records it as provider `nvidia_nemotron`, role `agent`, outcome `fallback` -- a class
--   `ottoq_model_call_outcome_class` and the view's `fell_back` column already know -- with the endpoint's own error
--   text in `detail.model_error`. A pass that made no call ("no key") is still not a call and is still not recorded.
--   Surviving fallback passes are backfilled as `source_kind = 'backfill'`, so they are countable and never mistaken
--   for live capture. Fallbacks from runs already purged are gone with their decisions and are not reconstructed.
--
-- ══ §3 forces_recert FALSE ═══════════════════════════════════════════════════════════════════════════════════
--
--   (1) is a read-only reporting function no tick path calls. (2) changes an error-swallowing AFTER INSERT capture
--   on `ottoq_decisions` that writes only to the evidence ledger; no certification atom reads that ledger, and the
--   new branch fires only for agent fallback rows, which a determinism pair does not produce. The P0 guard refuses
--   only while a pair is in flight.

BEGIN;

-- ── P0: no pair in flight (a live demo run is fine: nothing here is on a tick path) ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0452 P0: a pair is running right now'; END IF;
END $inflight$;

-- ── P2: the premises this file builds on ──
DO $premises$
BEGIN
  PERFORM 1 FROM pg_proc p WHERE p.oid = 'public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure
     AND p.prosrc LIKE '%''advice_ticks_late''%';
  IF NOT FOUND THEN RAISE EXCEPTION '0452 P2: ottoq_activity_feed is not the 0451 body this file extends'; END IF;
  -- nothing may depend on the function being dropped, and no function may call it
  PERFORM 1 FROM pg_depend d WHERE d.refobjid = 'public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure
     AND d.deptype = 'n';
  IF FOUND THEN RAISE EXCEPTION '0452 P2: an object depends on ottoq_activity_feed'; END IF;
  PERFORM 1 FROM pg_proc p WHERE p.prosrc LIKE '%ottoq_activity_feed%' AND p.proname <> 'ottoq_activity_feed';
  IF FOUND THEN RAISE EXCEPTION '0452 P2: a function calls ottoq_activity_feed; this file assumes the cockpit is its only caller'; END IF;
  PERFORM 1 FROM pg_trigger t WHERE t.tgname = 'ottoq_capture_decision_model_call_trg'
     AND t.tgrelid = 'public.ottoq_decisions'::regclass;
  IF NOT FOUND THEN RAISE EXCEPTION '0452 P2: ottoq_capture_decision_model_call_trg (0340) is missing'; END IF;
  PERFORM 1 FROM pg_trigger t WHERE t.tgname = 'trg_ottoq_stamp_l2_engine'
     AND t.tgrelid = 'public.ottoq_decisions'::regclass;
  IF NOT FOUND THEN RAISE EXCEPTION '0452 P2: trg_ottoq_stamp_l2_engine is missing; §2''s diagnosis rests on it'; END IF;
  IF public.ottoq_model_call_outcome_class('fallback') <> 'fallback' THEN
    RAISE EXCEPTION '0452 P2: the outcome classifier does not know ''fallback''';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0452_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure,
                 'public.ottoq_capture_decision_model_call()'::regprocedure);

-- ═══ (1) the Decisions stream ═════════════════════════════════════════════════════════════════════════════
DROP FUNCTION public.ottoq_activity_feed(uuid, integer, uuid);

CREATE FUNCTION public.ottoq_activity_feed(
    p_sim_run_id   uuid,
    p_limit        integer DEFAULT 200,
    p_vehicle_id   uuid    DEFAULT NULL::uuid,
    p_changes_only boolean DEFAULT false,
    p_window_ticks integer DEFAULT 240)
 RETURNS TABLE(occurred_at timestamp with time zone, vehicle_id uuid, display_name text, action text, engine text,
               target text, outcome text, rationale jsonb, reason text,
               decision_seq bigint, tick_seq bigint, held_ticks integer, last_at timestamp with time zone,
               standing boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  --: 0452 CHANGES-ONLY. `bounds` is empty unless p_changes_only, so the default call reads exactly the rows it
  --: read before. The window carries five extra ticks of context so a verdict standing since before the window is
  --: recognised as a repeat at its edge instead of being reported as a fresh change.
  WITH bounds AS (
    SELECT max(d0.tick_seq) AS t,
           max(d0.tick_seq) - GREATEST(COALESCE(p_window_ticks,240),1) AS w_start
      FROM public.ottoq_decisions d0
     WHERE p_changes_only AND d0.sim_run_id = p_sim_run_id
  ),
  win AS (
    SELECT d1.decision_seq, d1.tick_seq, d1.sim_clock, d1.entity_type, d1.entity_id,
           COALESCE(d1.resolved_action_context, d1.action_context) AS act,
           --: THE SAME VERDICT: what the decision decided, never the live counters in its rationale.
           CASE WHEN COALESCE(d1.resolved_action_context, d1.action_context) = 'orchestrator_agent'
                THEN d1.decision_seq::text
                ELSE concat_ws('|', d1.outcome_status,
                       COALESCE(d1.enacted_action->>'verb',     d1.proposed_action->>'verb'),
                       COALESCE(d1.enacted_action->>'reason',   d1.proposed_action->>'reason'),
                       COALESCE(d1.enacted_action->>'stall_id', d1.proposed_action->>'stall_id'),
                       COALESCE(d1.enacted_action->>'action',   d1.proposed_action->>'action'),
                       COALESCE(d1.enacted_action->'rationale'->>'step', d1.proposed_action->'rationale'->>'step'),
                       COALESCE(d1.enacted_action->'rationale'->>'mode', d1.proposed_action->'rationale'->>'mode'),
                       d1.enacted_action->>'shift_s',
                       array_to_string(d1.override_rule_codes, ','))
           END AS sig
      FROM public.ottoq_decisions d1, bounds b
     WHERE d1.sim_run_id = p_sim_run_id
       AND d1.tick_seq > b.w_start - 5
       AND (p_vehicle_id IS NULL OR d1.entity_id = p_vehicle_id)
  ),
  flagged AS (
    SELECT w.*, CASE WHEN (lag(w.sig) OVER k) IS DISTINCT FROM w.sig THEN 1 ELSE 0 END AS chg
      FROM win w
    WINDOW k AS (PARTITION BY w.entity_type, w.entity_id, w.act ORDER BY w.tick_seq, w.decision_seq)
  ),
  grouped AS (
    SELECT f.*, sum(f.chg) OVER (PARTITION BY f.entity_type, f.entity_id, f.act
                                 ORDER BY f.tick_seq, f.decision_seq) AS grp
      FROM flagged f
  ),
  picked AS (
    --: one row per run of identical verdicts: the decision that changed it, and how long it then stood
    SELECT min(g.decision_seq)             AS decision_seq,
           count(DISTINCT g.tick_seq)::int AS held_ticks,
           max(g.sim_clock)                AS last_at,
           max(g.tick_seq) = max(b.t)      AS standing
      FROM grouped g, bounds b
     GROUP BY g.entity_type, g.entity_id, g.act, g.grp
    HAVING min(g.tick_seq) > max(b.w_start)
  )
  SELECT
    d.sim_clock AS occurred_at,
    d.entity_id AS vehicle_id,
    CASE WHEN d.resolved_action_context='orchestrator_agent'
         THEN 'OTTO-Q PRIME' ELSE v.display_name END AS display_name,
    COALESCE(d.resolved_action_context,d.action_context) AS action,
    --: 0346. NOTHING IS FABRICATED HERE ANY MORE. This was a COALESCE of
    --: f.effective_source onto a hardcoded solver literal, against a join that
    --: has never matched a row. The literal is deliberately not spelled here:
    --: assertion A1a greps prosrc, and quoting it in a comment was enough to fail
    --: the file (it did, on the first apply).
    --: 0452: a failed model call records model 'none'; say what actually decided.
    CASE WHEN d.resolved_action_context='orchestrator_agent'
         THEN COALESCE(NULLIF(d.proposed_action->>'model','none'),'deterministic_fallback') || ' -> ' ||
              COALESCE(m.providers, 'no solver call recorded')
         ELSE COALESCE(NULLIF(d.l2_engine,''),d.proposed_action->>'source') END AS engine,
    CASE WHEN d.resolved_action_context='orchestrator_agent'
         THEN 'objective: ' || COALESCE(d.proposed_action->'solver'->>'objective','readiness_first')
         ELSE COALESCE(s.stall_code,d.enacted_action->>'verb',d.proposed_action->>'verb') END AS target,
    d.outcome_status AS outcome,
    CASE WHEN d.resolved_action_context='orchestrator_agent' THEN
      jsonb_strip_nulls(jsonb_build_object(
        'summary',d.enacted_action->>'rationale',
        'agent_model',NULLIF(d.proposed_action->>'model','none'),
        'objective',d.proposed_action->'solver'->>'objective',
        'objective_why',d.proposed_action->'solver'->>'why',
        --: measured, or absent. Never a default naming a solver that did not run.
        'solver_engine',m.providers,
        'solver_evidence',CASE WHEN m.providers IS NOT NULL
                               THEN 'ottoq_model_call_ledger' ELSE 'none' END,
        'solver_calls',m.calls,
        'proposals_returned',m.proposals_returned,
        'solver_max_latency_ms',m.max_latency_ms,
        --: 0451: how late the advice was APPLIED (receipt tick - computed tick, as the provenance view
        --: computes it). The retracted over-one-tick flag is gone: the tick never waits on the agent (0332).
        'advice_ticks_late',((d.enacted_action->'solver_handoff'->'receipt'->>'tick_seq')::bigint - d.tick_seq),
        'model_error',CASE WHEN d.enacted_action->>'source' = 'deterministic_fallback'
                           THEN substring(d.enacted_action->>'rationale' FROM '\(([^)]*)\)') END,
        'handoff_status',d.enacted_action->'solver_handoff'->>'status',
        --: THE KERNEL LEG, which the strip never had. Joined on the chain id the
        --: producer actually writes (0343), not on tick equality: net.http_post
        --: queues, so proposals land on a LATER beat.
        'kernel_enacted',k.enacted,
        'kernel_refused',k.refused,
        'kernel_superseded',k.superseded,
        'kernel_expired',k.expired,
        'kernel_landed_ticks',k.landed_ticks,
        --: fire-log values keep their previous meaning so no reader is silently
        --: re-pointed; they are the forward_lex bridge's numbers and are NULL for
        --: a cuOpt-served run, which is now honest rather than hidden.
        'solver_status',f.status,
        'planned',f.n_planned,
        'submitted',f.n_submitted,
        --: the G60 starvation signature, which only the fire log carries.
        'frame_serviceable',f.n_in_serviceable_state,
        'frame_held',(f.fire->>'n_vehicles_held')::int,
        'retry_attempts',f.fire->'retry_attempts',
        'applied',d.enacted_action->'applied',
        'queued',d.enacted_action->'queued',
        'rejected',d.enacted_action->'rejected',
        'l1_rules_evaluated',jsonb_array_length(COALESCE(d.rule_results,'[]'::jsonb)),
        'chain_id',d.proposed_action->>'agent_solver_chain_id'
      ))
      ELSE d.proposed_action->'rationale' END AS rationale,
    CASE
      WHEN d.resolved_action_context='orchestrator_agent'
        THEN COALESCE(d.enacted_action->>'rationale',d.proposed_action->'solver'->>'why')
      WHEN d.override_rule_codes IS NOT NULL AND cardinality(d.override_rule_codes)>0
        THEN 'blocked: ' || array_to_string(d.override_rule_codes,', ')
      WHEN d.proposed_action ? 'rationale'
       AND jsonb_typeof(d.proposed_action->'rationale') <> 'null'
        THEN (d.proposed_action->'rationale')::text
      WHEN jsonb_typeof(d.rule_results)='array' AND jsonb_array_length(d.rule_results)>0
        THEN COALESCE(d.rule_results->0->>'reason',d.rule_results->0->>'rule_code')
      ELSE COALESCE(NULLIF(d.l2_engine,''),d.proposed_action->>'source')
    END AS reason,
    d.decision_seq,
    d.tick_seq,
    pk.held_ticks,
    pk.last_at,
    pk.standing
  FROM public.ottoq_decisions d
  LEFT JOIN picked pk ON pk.decision_seq = d.decision_seq
  LEFT JOIN public.vehicles v ON v.id=d.entity_id AND d.entity_type='vehicle'
  LEFT JOIN public.stalls s ON s.id=CASE
    WHEN COALESCE(d.enacted_action->>'stall_id',d.proposed_action->>'stall_id','') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
    THEN COALESCE(d.enacted_action->>'stall_id',d.proposed_action->>'stall_id')::uuid
    ELSE NULL END
  --: 0346 SOLVER LEG: the unified per-call ledger, not the forward_lex-only fire
  --: log, and on a key that is actually written. The tick-window arm exists
  --: because cuOpt's own rows carry no chain id and answer on a later beat.
  LEFT JOIN LATERAL (
    SELECT string_agg(DISTINCT z.provider, '+' ORDER BY z.provider) AS providers,
           count(*)                                    AS calls,
           COALESCE(sum(z.proposals_out),0)            AS proposals_returned,
           max(z.latency_ms)                           AS max_latency_ms
      FROM public.ottoq_model_call_ledger z
     WHERE z.sim_run_id = d.sim_run_id
       AND z.role = 'proposer'
       AND ( z.chain_id = d.proposed_action->>'agent_solver_chain_id'
          OR ( z.chain_id IS NULL
               AND z.tick_seq BETWEEN d.tick_seq AND d.tick_seq + 3 ) )
  ) m ON d.resolved_action_context='orchestrator_agent'
  --: 0346 KERNEL LEG: joined on the chain id the producer writes.
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE p.status='enacted')    AS enacted,
           count(*) FILTER (WHERE p.status='refused')     AS refused,
           count(*) FILTER (WHERE p.status='superseded')  AS superseded,
           count(*) FILTER (WHERE p.status='expired')     AS expired,
           jsonb_agg(DISTINCT p.tick_seq)                 AS landed_ticks
      FROM public.ottoq_external_proposals p
     WHERE p.sim_run_id = d.sim_run_id
       AND p.proposal->'agent_handoff'->>'chain_id' = d.proposed_action->>'agent_solver_chain_id'
  ) k ON d.resolved_action_context='orchestrator_agent'
  --: 0346 FRAME SHAPE: the fire log, now joined on (run, tick) rather than a key
  --: it has never carried. Still the only source of serviceable-vs-held.
  LEFT JOIN LATERAL (
    SELECT l.effective_source,l.status,l.n_planned,l.n_submitted,
           l.n_in_serviceable_state,l.fire
      FROM public.ottoq_proposer_fire_log l
     WHERE l.sim_run_id=d.sim_run_id
       AND l.tick_seq BETWEEN d.tick_seq AND d.tick_seq + 3
     ORDER BY l.fired_at DESC,l.fire_id DESC LIMIT 1
  ) f ON d.resolved_action_context='orchestrator_agent'
  WHERE d.sim_run_id=p_sim_run_id
    AND (p_vehicle_id IS NULL OR d.entity_id=p_vehicle_id)
    --: in changes-only mode the scan is bounded to the window, so a long run costs its window, not its life;
    --: the default mode is not bounded at all, so it returns exactly the rows it returned before 0452
    AND (NOT p_changes_only OR d.tick_seq > (SELECT b.w_start FROM bounds b))
    AND (NOT p_changes_only OR pk.decision_seq IS NOT NULL)
  ORDER BY d.sim_clock DESC,d.decision_seq DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit,200),1),500);
$function$;

REVOKE ALL ON FUNCTION public.ottoq_activity_feed(uuid, integer, uuid, boolean, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_activity_feed(uuid, integer, uuid, boolean, integer)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_activity_feed(uuid, integer, uuid, boolean, integer) IS
'The OTTO-Twin Decisions stream (TwinDecisionLogTab). 0346 rebuilt its solver leg onto ottoq_model_call_ledger and its kernel leg onto ottoq_external_proposals; NOTHING IS DEFAULTED (solver_engine is the measured provider or NULL). 0451 replaced the retracted over-one-tick flag with advice_ticks_late and model_error. 0452: p_changes_only returns only the decision at which an (entity, action) verdict CHANGED within the last p_window_ticks ticks, with held_ticks / last_at / standing -- on run 736406cf, 98.9% of task_start rows and 92% of stall_assignment rows restated the previous tick, and the newest 500 rows held no agent decision at all. Default behaviour is unchanged. decision_seq is a real row identity.';

-- ═══ (2) every attempted agent call reaches the evidence ledger ═════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_capture_decision_model_call()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  --: 0452: an agent pass whose model call FAILED. trg_ottoq_stamp_l2_engine stamps its l2_engine from
  --: enacted_action->>'source' = 'deterministic_fallback', which the 0340 capture never matched -- so a
  --: failed call was never a ledger row. The WHEN clause below admits it only when a call was attempted.
  v_agent_fallback boolean := NEW.resolved_action_context = 'orchestrator_agent'
                              AND NEW.l2_engine = 'deterministic_fallback';
BEGIN
  BEGIN
    PERFORM public.ottoq_log_model_call(
      p_provider   => CASE WHEN v_agent_fallback THEN 'nvidia_nemotron'
                           ELSE CASE NEW.l2_engine
                                  WHEN 'nemotron'    THEN 'nvidia_nemotron'
                                  WHEN 'forward_lex' THEN 'cpsat_service'
                                  WHEN 'llm_advisor' THEN 'anthropic_advisor'
                                  ELSE NEW.l2_engine END END,
      p_role       => CASE WHEN NEW.l2_engine = 'nemotron' OR v_agent_fallback THEN 'agent' ELSE 'proposer' END,
      p_outcome    => CASE
                        WHEN v_agent_fallback THEN 'fallback'
                        WHEN NEW.outcome_status IS NOT NULL THEN NEW.outcome_status
                        WHEN NEW.overridden THEN 'refused'
                        ELSE 'answered' END,
      p_sim_run_id => NEW.sim_run_id,
      p_depot_id   => NEW.depot_id,
      p_tick_seq   => NEW.tick_seq,
      p_sim_clock  => NEW.sim_clock,
      p_chain_id   => COALESCE(NEW.proposed_action->>'agent_solver_chain_id',
                               NEW.context_frame->>'agent_solver_chain_id'),
      p_model      => NULLIF(NEW.proposed_action->>'model', 'none'),
      p_latency_ms => NEW.total_latency_ms,
      --: rationale_present, NOT the rationale. The 0335 boundary.
      p_rationale_present => (NEW.enacted_action ? 'rationale'),
      p_detail     => jsonb_strip_nulls(jsonb_build_object(
                        'l2_engine', NEW.l2_engine,
                        'action_context', NEW.action_context,
                        'decision_id', NEW.decision_id,
                        'overridden', NEW.overridden,
                        'override_rule_codes', NEW.override_rule_codes,
                        'solver', NEW.proposed_action->>'solver',
                        'solver_handoff', NEW.enacted_action->'solver_handoff',
                        --: THE SHIELD GAP, MADE COUNTABLE. Measured 2026-09-19:
                        --: 729 of 729 nemotron rows carried an empty
                        --: rule_results. A reader can now quantify that without
                        --: ottoq_decisions, which the purge deletes.
                        'l1_rules_evaluated',
                          jsonb_array_length(COALESCE(NEW.rule_results,'[]'::jsonb)),
                        --: 0452: what the endpoint said, and how long the call itself took
                        'model_error', CASE WHEN v_agent_fallback
                                            THEN substring(NEW.enacted_action->>'rationale' FROM '\(([^)]*)\)') END,
                        'propose_latency_ms', CASE WHEN v_agent_fallback THEN NEW.propose_latency_ms END)),
      p_source_kind => 'live');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_capture_decision_model_call: % (decision=%)', SQLERRM, NEW.decision_id;
  END;
  RETURN NEW;
END $fn$;

DROP TRIGGER ottoq_capture_decision_model_call_trg ON public.ottoq_decisions;
CREATE TRIGGER ottoq_capture_decision_model_call_trg
  AFTER INSERT ON public.ottoq_decisions
  --: 'cuopt' IS DELIBERATELY ABSENT (0340): the cuOpt CALL is captured at cuopt_invocation_log; an
  --: ottoq_decisions row with l2_engine='cuopt' is the ENACTMENT of a proposal that call produced.
  --: 0452: an agent pass that fell back after ATTEMPTING a call is a call. propose_latency_ms is 0 when
  --: the agent had no key and never called out ("no key"), and that pass is still not a call.
  FOR EACH ROW WHEN (NEW.l2_engine IN ('nemotron','forward_lex','llm_advisor')
                     OR (NEW.resolved_action_context = 'orchestrator_agent'
                         AND NEW.l2_engine = 'deterministic_fallback'
                         AND COALESCE(NEW.propose_latency_ms, 0) > 0))
  EXECUTE FUNCTION public.ottoq_capture_decision_model_call();

-- Backfill the surviving failed calls, marked as reconstructed. Idempotent on decision_id.
DO $backfill$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN
    SELECT d.* FROM public.ottoq_decisions d
     WHERE d.resolved_action_context = 'orchestrator_agent'
       AND d.l2_engine = 'deterministic_fallback'
       AND COALESCE(d.propose_latency_ms, 0) > 0
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_model_call_ledger z
                        WHERE z.detail->>'decision_id' = d.decision_id::text)
     ORDER BY d.decision_seq
  LOOP
    PERFORM public.ottoq_log_model_call(
      p_provider => 'nvidia_nemotron', p_role => 'agent', p_outcome => 'fallback',
      p_sim_run_id => r.sim_run_id, p_depot_id => r.depot_id, p_tick_seq => r.tick_seq, p_sim_clock => r.sim_clock,
      p_chain_id => COALESCE(r.proposed_action->>'agent_solver_chain_id', r.context_frame->>'agent_solver_chain_id'),
      p_model => NULL, p_latency_ms => r.total_latency_ms,
      p_rationale_present => (r.enacted_action ? 'rationale'),
      p_detail => jsonb_strip_nulls(jsonb_build_object(
        'l2_engine', r.l2_engine, 'action_context', r.action_context, 'decision_id', r.decision_id,
        'overridden', r.overridden, 'solver_handoff', r.enacted_action->'solver_handoff',
        'l1_rules_evaluated', jsonb_array_length(COALESCE(r.rule_results,'[]'::jsonb)),
        'model_error', substring(r.enacted_action->>'rationale' FROM '\(([^)]*)\)'),
        'propose_latency_ms', r.propose_latency_ms,
        'backfilled_by', '0452')),
      p_source_kind => 'backfill');
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE '0452 backfill: % failed agent calls recorded', v_n;
END $backfill$;

-- ═══ verification ═════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_run uuid; v_all int; v_chg int; v_all_ts int; v_chg_ts int; v_agents_win int; v_agents_chg int;
  v_dupe int; v_missing int;
BEGIN
  -- V1: one signature, the new one; the three-argument form is gone so PostgREST cannot find two candidates
  IF to_regprocedure('public.ottoq_activity_feed(uuid,integer,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0452 V1: the three-argument feed still exists';
  END IF;
  IF to_regprocedure('public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)') IS NULL THEN
    RAISE EXCEPTION '0452 V1: the new feed does not exist';
  END IF;

  -- V2: the ACL is the one it had: anon, authenticated, service_role -- and not PUBLIC
  IF NOT (has_function_privilege('anon', 'public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)', 'EXECUTE')
      AND has_function_privilege('authenticated', 'public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)', 'EXECUTE')
      AND has_function_privilege('service_role', 'public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)', 'EXECUTE')) THEN
    RAISE EXCEPTION '0452 V2: the feed lost a grant';
  END IF;
  PERFORM 1 FROM pg_proc p, aclexplode(p.proacl) a
   WHERE p.oid = 'public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)'::regprocedure AND a.grantee = 0;
  IF FOUND THEN RAISE EXCEPTION '0452 V2: the feed is executable by PUBLIC'; END IF;

  -- V3: on the most recent twin-depot run with decisions, changes-only is a strict subset that keeps every agent pass
  SELECT d.sim_run_id INTO v_run FROM public.ottoq_decisions d
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY d.decision_seq DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    SELECT count(*), count(*) FILTER (WHERE action = 'task_start') INTO v_all, v_all_ts
      FROM public.ottoq_activity_feed(v_run, 500);
    SELECT count(*), count(*) FILTER (WHERE action = 'task_start'),
           count(*) FILTER (WHERE action = 'orchestrator_agent')
      INTO v_chg, v_chg_ts, v_agents_chg
      FROM public.ottoq_activity_feed(v_run, 500, NULL, true, 240);
    SELECT count(*) INTO v_agents_win FROM public.ottoq_decisions d
     WHERE d.sim_run_id = v_run AND d.resolved_action_context = 'orchestrator_agent'
       AND d.tick_seq > (SELECT max(tick_seq) FROM public.ottoq_decisions WHERE sim_run_id = v_run) - 240;
    IF v_chg = 0 THEN RAISE EXCEPTION '0452 V3: changes-only returned nothing on run %', v_run; END IF;
    IF v_agents_chg < LEAST(v_agents_win, 500) AND v_chg < 500 THEN
      RAISE EXCEPTION '0452 V3: % agent passes in the window, % in the changes-only stream', v_agents_win, v_agents_chg;
    END IF;
    -- every changes-only row says how long its verdict stood and whether it still does
    SELECT count(*) INTO v_dupe FROM public.ottoq_activity_feed(v_run, 500, NULL, true, 240) f
     WHERE f.held_ticks IS NULL OR f.held_ticks < 1 OR f.standing IS NULL;
    IF v_dupe > 0 THEN RAISE EXCEPTION '0452 V3: % changes-only rows lack held_ticks/standing', v_dupe; END IF;
    RAISE NOTICE '0452 V3 run %: default % rows (task_start %) / changes-only % rows (task_start %, agent % of % in window)',
      v_run, v_all, v_all_ts, v_chg, v_chg_ts, v_agents_chg, v_agents_win;
  END IF;

  -- V4: the capture admits attempted-but-failed agent calls, and every surviving one is now in the ledger
  PERFORM 1 FROM pg_trigger t WHERE t.tgname = 'ottoq_capture_decision_model_call_trg'
     AND pg_get_triggerdef(t.oid) LIKE '%deterministic_fallback%' AND pg_get_triggerdef(t.oid) LIKE '%propose_latency_ms%';
  IF NOT FOUND THEN RAISE EXCEPTION '0452 V4: the capture trigger does not admit failed agent calls'; END IF;
  SELECT count(*) INTO v_missing FROM public.ottoq_decisions d
   WHERE d.resolved_action_context = 'orchestrator_agent' AND d.l2_engine = 'deterministic_fallback'
     AND COALESCE(d.propose_latency_ms, 0) > 0
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_model_call_ledger z WHERE z.detail->>'decision_id' = d.decision_id::text);
  IF v_missing > 0 THEN RAISE EXCEPTION '0452 V4: % failed agent calls are still not in the ledger', v_missing; END IF;
  -- and the view counts them where they belong
  PERFORM 1 FROM public.ottoq_intelligence_ledger WHERE provider = 'nvidia_nemotron' AND role = 'agent' AND unclassified > 0;
  IF FOUND THEN RAISE EXCEPTION '0452 V4: the ledger view could not classify an agent row'; END IF;
END $verify$;

-- Rollback: DROP FUNCTION public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer); recreate the
-- three-argument form and restore the capture function from ottoq_schema_snapshots label '0452_pre'
-- (re-GRANT the feed to anon, authenticated, service_role); recreate the trigger with the 0340 WHEN clause.
-- The backfilled ledger rows (source_kind='backfill', detail.backfilled_by='0452') are append-only and stay.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0452_the_decisions_stream_restated_every_waiting_vehicle_every_tick_and_the_ledger_never_saw_a_failed_agent_call', false,
  'Reporting: ottoq_activity_feed gains a changes-only mode (default unchanged) and the evidence-ledger capture records agent calls that failed. No tick path reads either; no atom reads the ledger.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
