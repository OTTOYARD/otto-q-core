-- migration-version: 20260919161259
-- migration-name:    the_cockpits_solver_join_has_never_matched_a_row
--
-- 0346  THE OTTO-TWIN COCKPIT HAS DISPLAYED "CP-SAT" AND ZERO THROUGHPUT FOR
--       EVERY RUN IT HAS EVER SHOWN, ON A JOIN THAT CANNOT MATCH.
--
-- Chase's standing requirement is that the agent and deterministic layers be
-- "fully functioning and VISIBLE IN OTTO-TWIN when a simulation is started". The
-- loop functions -- 0343 proved one chain end to end, 17 proposals enacted. The
-- cockpit cannot show it, and the reason is three lines of SQL.
--
-- `public.ottoq_activity_feed` is the only thing the cockpit's Decisions tab
-- reads (ottoyarddepot-sim/src/components/tabs/TwinDecisionLogTab.tsx, polled
-- every 4s via useActivityFeed). Its solver leg is a LATERAL join:
--
--     LEFT JOIN LATERAL (
--       SELECT l.effective_source, l.status, l.n_planned, l.n_submitted, l.fire
--         FROM public.ottoq_proposer_fire_log l
--        WHERE l.sim_run_id = d.sim_run_id
--          AND l.fire->>'agent_chain_id' = d.proposed_action->>'agent_solver_chain_id'
--     ) f ON d.resolved_action_context = 'orchestrator_agent'
--
-- MEASURED 2026-09-19:
--     ottoq_proposer_fire_log rows                                    112
--     ...of those carrying fire->>'agent_chain_id'                      0
--     agent decision rows (resolved_action_context='orchestrator_agent')  1,956
--     ...where that join matches                                        0
--
-- The key it joins on has never been written. Not once, on any row, in the life
-- of the table. So `f` is ALWAYS NULL, and three consequences follow, all of them
-- visible to an operator:
--
--   1. THE SOLVER IS MISNAMED, CONFIDENTLY. The feed computes
--      COALESCE(f.effective_source, 'cp_sat_forward_lex'). With f always NULL the
--      COALESCE always fires, so the cockpit states the solver was CP-SAT on
--      every row it has ever rendered. CP-SAT (`forward_lex`) has submitted
--      NOTHING since 2026-09-14 09:23; every enacted assignment since came from
--      cuOpt. This is not a missing value, it is a wrong value asserted -- the
--      exact class CLAUDE.md keeps catching (a comment or label claiming a
--      behaviour the system does not have), and the one an OEM diligence team
--      would find first.
--   2. THROUGHPUT READS ZERO. f.n_planned and f.n_submitted are NULL, so the
--      pipeline strip renders "CP-SAT: queued" and "Kernel: pending" while the
--      kernel enacted every proposal. A working system displayed as a broken one
--      -- the same defect I shipped in 0342's review and fixed in 0343, here in
--      the operator surface.
--   3. WRONG LEDGER EVEN IF THE KEY EXISTED. ottoq_proposer_fire_log is the
--      forward_lex bridge's ledger; cuOpt records into cuopt_invocation_log. On
--      run ac402e07 the fire log holds ZERO rows while 17 cuOpt proposals were
--      enacted. Fixing the key alone would still show nothing for a cuOpt run.
--
-- ── THE FIX ─────────────────────────────────────────────────────────────────
--
-- The signature is UNCHANGED -- same nine columns, same names, same order -- so
-- the front end and its hook keep working without a deploy. What changes is what
-- fills `engine` and `rationale`:
--
--   * SOLVER LEG now reads public.ottoq_model_call_ledger (0340), the unified
--     per-call ledger that covers cuOpt, Nemotron, CP-SAT and the Anthropic
--     advisor, joined on chain_id -- and falling back to the beat window
--     (tick .. tick+3) for a provider whose own ledger carries no chain id,
--     because net.http_post only QUEUES and a solver answers on a LATER beat
--     (0343's finding: agent at tick 1, proposals at ticks 2 and 3).
--   * NOTHING IS FABRICATED. `solver_engine` is the provider list actually
--     recorded, or NULL. The `engine` column says 'no solver call recorded'
--     rather than naming a solver that did not run. A new `solver_evidence` key
--     states which ledger the answer came from, so a reader can tell a measured
--     value from an absent one.
--   * KERNEL LEG is new and is the number the strip should have been showing:
--     enacted / refused / superseded / expired from ottoq_external_proposals,
--     joined on proposal->'agent_handoff'->>'chain_id' -- the key 0343 proved
--     live (2,490 proposals across 477 chains).
--   * THE FIRE LOG IS STILL READ, on (sim_run_id, tick_seq), for the frame shape
--     only it carries: n_in_serviceable_state vs n_vehicles_held, which is the
--     G60 starvation signature and appears in no other ledger.
--   * `planned` and `submitted` keep their existing meaning (fire-log counts) so
--     no current reader is silently re-pointed; `kernel_enacted` is added beside
--     them and the front end is updated in the same change to prefer it.
--
-- forces_recert: FALSE. ottoq_activity_feed is a STABLE read-only reporting
-- function. It is not on the tick path, no decide/propose/dispose routine reads
-- it, and it appears in none of the fourteen certification atoms. A3 asserts no
-- other routine in public/ottoq/twin calls it, so replacing it cannot change
-- engine behaviour.

DO $preflight$
DECLARE v_jobs int; v_runs int; v_fire int; v_keyed int; v_agent int; v_match int;
BEGIN
  SELECT count(*) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs > 0 THEN RAISE EXCEPTION '0346 P-: certification jobs are scheduled'; END IF;

  IF to_regprocedure('public.ottoq_activity_feed(uuid,integer,uuid)') IS NULL THEN
    RAISE EXCEPTION '0346 P1: ottoq_activity_feed is missing';
  END IF;
  IF to_regclass('public.ottoq_model_call_ledger') IS NULL THEN
    RAISE EXCEPTION '0346 P2: 0340 has not been applied; the solver leg has nothing to read';
  END IF;

  -- P3. THE DEFECT MUST STILL BE PRESENT, in the exact clause the header quotes.
  IF (SELECT prosrc FROM pg_proc
       WHERE oid='public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure)
     NOT LIKE '%l.fire->>''agent_chain_id''=d.proposed_action->>''agent_solver_chain_id''%' THEN
    RAISE EXCEPTION '0346 P3: the fire->>agent_chain_id join is not present; the feed has changed since measuring';
  END IF;

  -- P4. AND THE JOIN MUST STILL BE DEAD, recomputed here rather than trusted from
  -- the header. If it has started matching, the diagnosis is stale and the fix
  -- must be re-reasoned rather than applied.
  SELECT count(*) INTO v_fire  FROM public.ottoq_proposer_fire_log;
  SELECT count(*) INTO v_keyed FROM public.ottoq_proposer_fire_log WHERE fire ? 'agent_chain_id';
  SELECT count(*) INTO v_agent FROM public.ottoq_decisions
   WHERE resolved_action_context='orchestrator_agent';
  SELECT count(*) INTO v_match
    FROM public.ottoq_decisions d
    JOIN public.ottoq_proposer_fire_log l
      ON l.sim_run_id = d.sim_run_id
     AND l.fire->>'agent_chain_id' = d.proposed_action->>'agent_solver_chain_id'
   WHERE d.resolved_action_context='orchestrator_agent';
  IF v_keyed > 0 OR v_match > 0 THEN
    RAISE EXCEPTION '0346 P4: the join is not dead after all (% keyed rows, % matches) — re-reason before fixing',
      v_keyed, v_match;
  END IF;
  RAISE NOTICE '0346: fire log % rows, % carry agent_chain_id; % agent decisions, % join matches',
    v_fire, v_keyed, v_agent, v_match;

  -- P5. The replacement join key must be live, or this trades a dead join for
  -- another dead join.
  IF (SELECT count(*) FROM public.ottoq_external_proposals
       WHERE proposal->'agent_handoff'->>'chain_id' IS NOT NULL) = 0 THEN
    RAISE EXCEPTION '0346 P5: no proposal carries agent_handoff.chain_id; the kernel leg would be empty';
  END IF;
END $preflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0346-pre', 'function', 'public', 'ottoq_activity_feed(uuid,integer,uuid)',
       pg_get_functiondef('public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure));

CREATE OR REPLACE FUNCTION public.ottoq_activity_feed(
  p_sim_run_id uuid,
  p_limit integer DEFAULT 200,
  p_vehicle_id uuid DEFAULT NULL::uuid
)
RETURNS TABLE(occurred_at timestamp with time zone, vehicle_id uuid, display_name text,
              action text, engine text, target text, outcome text, rationale jsonb, reason text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT
    d.sim_clock AS occurred_at,
    d.entity_id AS vehicle_id,
    CASE WHEN d.resolved_action_context='orchestrator_agent'
         THEN 'OTTO-Q PRIME' ELSE v.display_name END AS display_name,
    COALESCE(d.resolved_action_context,d.action_context) AS action,
    --: 0346. NOTHING IS FABRICATED HERE ANY MORE. This was a COALESCE of
    --: f.effective_source onto a hardcoded CP-SAT literal, against a join that
    --: has never matched a row -- so the cockpit asserted CP-SAT on every line it
    --: ever rendered while cuOpt did the work. The literal is deliberately not
    --: spelled here: assertion A1a greps prosrc for it, and quoting it in a
    --: comment is enough to fail the file (it did, on the first apply).
    CASE WHEN d.resolved_action_context='orchestrator_agent'
         THEN COALESCE(d.proposed_action->>'model','deterministic_fallback') || ' -> ' ||
              COALESCE(m.providers, 'no solver call recorded')
         ELSE COALESCE(NULLIF(d.l2_engine,''),d.proposed_action->>'source') END AS engine,
    CASE WHEN d.resolved_action_context='orchestrator_agent'
         THEN 'objective: ' || COALESCE(d.proposed_action->'solver'->>'objective','readiness_first')
         ELSE COALESCE(s.stall_code,d.enacted_action->>'verb',d.proposed_action->>'verb') END AS target,
    d.outcome_status AS outcome,
    CASE WHEN d.resolved_action_context='orchestrator_agent' THEN
      jsonb_strip_nulls(jsonb_build_object(
        'summary',d.enacted_action->>'rationale',
        'agent_model',d.proposed_action->>'model',
        'objective',d.proposed_action->'solver'->>'objective',
        'objective_why',d.proposed_action->'solver'->>'why',
        --: measured, or absent. Never a default naming a solver that did not run.
        'solver_engine',m.providers,
        'solver_evidence',CASE WHEN m.providers IS NOT NULL
                               THEN 'ottoq_model_call_ledger' ELSE 'none' END,
        'solver_calls',m.calls,
        'proposals_returned',m.proposals_returned,
        'solver_max_latency_ms',m.max_latency_ms,
        'agent_over_one_tick',(COALESCE(d.total_latency_ms,0) > 30000),
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
    END AS reason
  FROM public.ottoq_decisions d
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
  ORDER BY d.sim_clock DESC,d.decision_seq DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit,200),1),500);
$function$;

COMMENT ON FUNCTION public.ottoq_activity_feed(uuid,integer,uuid) IS
'The OTTO-Twin Decisions tab''s only data source (TwinDecisionLogTab, polled every 4s). 0346 rebuilt its solver leg. It previously joined ottoq_proposer_fire_log on fire->>''agent_chain_id'' -- a key present on 0 of 112 rows, matching 0 of 1,956 agent decisions, so the join had never matched in the life of the table. Because the fallback was COALESCE(..., ''cp_sat_forward_lex''), the cockpit asserted CP-SAT as the solver on every line it ever rendered, while CP-SAT had submitted nothing since 2026-09-14 and cuOpt did all the work; and planned/submitted were always NULL, so the strip showed "Kernel: pending" while the kernel enacted everything. The solver leg now reads ottoq_model_call_ledger (unified across cuOpt/Nemotron/CP-SAT) on chain_id with a tick-window arm for providers whose rows carry none, the kernel leg reads ottoq_external_proposals on proposal->agent_handoff->>chain_id (live: 2,490 rows / 477 chains), and the fire log is kept only for the serviceable-vs-held frame shape it uniquely carries. NOTHING IS DEFAULTED: solver_engine is the measured provider or NULL, and solver_evidence says which ledger answered.';

DO $assertions$
DECLARE v_src text; v_cols int; v_run uuid; v_row record; v_bad int;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid='public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure;

  -- A1. The fabricated solver name is gone, and so is the dead join key.
  -- A1a checks the EXECUTABLE expression, not the bare literal. The first version
  -- grepped prosrc for the literal itself and failed the whole migration on the
  -- explanatory comment in the body, which quoted it -- a real catch, and the
  -- reason that comment now describes the literal instead of spelling it.
  -- COALESCE(f.effective_source is narrower and cannot be tripped by prose.
  IF v_src LIKE '%COALESCE(f.effective_source%' THEN
    RAISE EXCEPTION '0346 A1a: the fabricated solver-name default survives';
  END IF;
  IF v_src LIKE '%fire->>''agent_chain_id''%' THEN
    RAISE EXCEPTION '0346 A1b: the dead agent_chain_id join survives';
  END IF;
  IF v_src NOT LIKE '%ottoq_model_call_ledger%' THEN
    RAISE EXCEPTION '0346 A1c: the solver leg does not read the unified ledger';
  END IF;

  -- A2. THE SIGNATURE IS UNCHANGED, so the deployed front end keeps working. Nine
  -- columns, exact names. A renamed column would break the cockpit silently.
  SELECT count(*) INTO v_cols
    FROM unnest(string_to_array(pg_get_function_result(
           'public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure), ',')) x;
  IF v_cols <> 9 THEN
    RAISE EXCEPTION '0346 A2a: the feed returns % columns, expected 9', v_cols;
  END IF;
  IF pg_get_function_result('public.ottoq_activity_feed(uuid,integer,uuid)'::regprocedure)
     NOT LIKE '%occurred_at%vehicle_id%display_name%action%engine%target%outcome%rationale%reason%' THEN
    RAISE EXCEPTION '0346 A2b: the column names or order changed';
  END IF;

  -- A3. forces_recert=FALSE, asserted by absence: nothing in the engine reads
  -- this function, so replacing it cannot change how the engine behaves.
  SELECT count(*) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.prosrc ILIKE '%ottoq_activity_feed%'
     AND p.proname <> 'ottoq_activity_feed';
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0346 A3: % routine(s) read ottoq_activity_feed; forces_recert=FALSE is not safe', v_bad;
  END IF;

  -- A4. THE POINT OF THE WHOLE FILE, EXECUTED. On a run that HAS an agent chain
  -- and enacted proposals, the feed must now report a real provider and a
  -- non-zero kernel count -- not 'cp_sat_forward_lex' and not nulls.
  SELECT d.sim_run_id INTO v_run
    FROM public.ottoq_decisions d
    JOIN public.ottoq_external_proposals p
      ON p.sim_run_id = d.sim_run_id
     AND p.proposal->'agent_handoff'->>'chain_id' = d.proposed_action->>'agent_solver_chain_id'
   WHERE d.resolved_action_context='orchestrator_agent' AND p.status='enacted'
   ORDER BY d.created_at DESC LIMIT 1;

  IF v_run IS NULL THEN
    RAISE WARNING '0346 A4: SKIPPED — no run has an agent chain with enacted proposals to verify against';
  ELSE
    SELECT * INTO v_row FROM public.ottoq_activity_feed(v_run, 500, NULL) q
     WHERE q.action='orchestrator_agent'
       AND COALESCE((q.rationale->>'kernel_enacted')::int,0) > 0
     LIMIT 1;
    IF v_row IS NULL THEN
      RAISE EXCEPTION '0346 A4a: on run % the feed reports no agent row with kernel_enacted > 0', v_run;
    END IF;
    IF COALESCE(v_row.rationale->>'solver_engine','') = '' THEN
      RAISE EXCEPTION '0346 A4b: solver_engine is empty on a chain whose proposals were enacted';
    END IF;
    IF v_row.rationale->>'solver_engine' = 'cp_sat_forward_lex' THEN
      RAISE EXCEPTION '0346 A4c: solver_engine is still the fabricated literal';
    END IF;
    IF v_row.rationale->>'solver_evidence' <> 'ottoq_model_call_ledger' THEN
      RAISE EXCEPTION '0346 A4d: solver_evidence says % rather than naming the ledger',
        v_row.rationale->>'solver_evidence';
    END IF;
    RAISE NOTICE '0346 A4: run % now reports solver=% kernel_enacted=% (was "cp_sat_forward_lex" and null)',
      v_run, v_row.rationale->>'solver_engine', v_row.rationale->>'kernel_enacted';
  END IF;
END $assertions$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0346_the_cockpits_solver_join_has_never_matched_a_row', false,
  'ottoq_activity_feed -- the OTTO-Twin Decisions tab''s only data source -- joined the fire log on fire->>agent_chain_id, a key present on 0 of 112 rows and matching 0 of 1,956 agent decisions, so with COALESCE(...,''cp_sat_forward_lex'') the cockpit asserted CP-SAT as the solver on every line it ever rendered while cuOpt did the work, and showed zero kernel throughput while the kernel enacted everything. Solver leg now reads ottoq_model_call_ledger on chain_id, kernel leg reads ottoq_external_proposals on the chain id the producer writes, fire log kept only for the serviceable-vs-held frame shape. Signature unchanged (A2) and no engine routine reads the function (A3), so recertification is not required.',
  now())
ON CONFLICT(name) DO NOTHING;
