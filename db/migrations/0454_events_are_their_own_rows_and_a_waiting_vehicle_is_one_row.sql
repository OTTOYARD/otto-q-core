-- migration-version: 20260923061135
-- migration-name:    events_are_their_own_rows_and_a_waiting_vehicle_is_one_row
--
-- 0454  **0453 over-corrected, and the live stream showed it within a minute.** `db/checks/0356` §3. FINDINGS G189.
--
--   0453 made a repeat require the SAME verdict on the action's VERY NEXT decide tick, to stop 0452 folding a
--   vehicle's second deployment into its first. Measured on run 736406cf over its whole life, identical consecutive
--   verdicts recur at these gaps (in that action's own decide ticks):
--
--       action              median  p95     what the gap is
--       task_start             1      1     a vehicle judged every tick while it waits
--       stall_assignment       2     13     the charge loop judges each waiting vehicle about every second tick
--       redeployment          37     60     separate deployments of one vehicle
--       itinerary_amended     19     20     separate re-plans
--
--   So the next-tick rule split one vehicle's wait for a charger into ~2.5 rows (stall_assignment 448 -> 3,389
--   rows over the run), and no gap threshold separates the two cases for every action. They are different kinds of
--   thing: an EVENT happened (an agent pass, a deployment, a re-plan, a triage verdict, a gate intake) and is its
--   own row every time; a STATE VERDICT is restated while the world holds still and is one row until it changes.
--   A state verdict separated by more than 40 of its action's decide ticks (20 sim-minutes at the 30-second beat)
--   starts a new row, because that silence means the vehicle left the loop and came back -- task_start has 32 such
--   returns on this run. Events never read `standing`; standing (0453) stays per action.
--
--   Same signature, same columns, same ACL. `forces_recert` FALSE: a read-only reporting function that no tick
--   path calls and no atom reads.

BEGIN;

-- ── P0: no pair in flight (a live demo run is fine: nothing here is on a tick path) ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0454 P0: a pair is running right now'; END IF;
END $inflight$;

-- ── P2: the 0453 body this corrects ──
DO $premises$
BEGIN
  PERFORM 1 FROM pg_proc p WHERE p.oid = 'public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)'::regprocedure
     AND p.prosrc LIKE '%max(g.act_tick_n) = max(g.act_top_n)%' AND p.prosrc NOT LIKE '%is_event%';
  IF NOT FOUND THEN RAISE EXCEPTION '0454 P2: ottoq_activity_feed is not the 0453 body this file corrects'; END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0454_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)'::regprocedure;

-- ═══ the corrected stream ═══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_activity_feed(
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
  --: 0453: STANDING is measured against that action's own newest decide tick: the agent writes a later tick_seq
  --: than the decide path, so against the run's newest tick nothing the decide path said could ever read as
  --: still in force.
  --: 0454: EVENTS AND STATES ARE DIFFERENT THINGS. An event -- an agent pass, a deployment, a plan amendment, a
  --: triage verdict, a gate intake -- is its own row every time, however alike two of them look. A state verdict
  --: (task_start, stall_assignment, bay_reconcile, bess_dispatch, and any action not named here) is a repeat when
  --: it matches the entity's previous verdict for that action within 40 of that action's decide ticks (20 sim-min
  --: at the 30-second beat); a longer silence means the entity left the loop and came back. 0453 demanded the very
  --: next decide tick, and stall_assignment judges each waiting vehicle about every second tick (median gap 2,
  --: p95 13), so one wait split into ~2.5 rows.
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
           END AS sig,
           --: the ordinal of this decision's tick among the ticks on which this ACTION was decided at all
           dense_rank() OVER (PARTITION BY COALESCE(d1.resolved_action_context, d1.action_context)
                              ORDER BY d1.tick_seq) AS act_tick_n,
           COALESCE(d1.resolved_action_context, d1.action_context)
             IN ('orchestrator_agent','redeployment','itinerary_amended','triage_verdict','gate_intake_no_charge')
             AS is_event
      FROM public.ottoq_decisions d1, bounds b
     WHERE d1.sim_run_id = p_sim_run_id
       AND d1.tick_seq > b.w_start - 5
       AND (p_vehicle_id IS NULL OR d1.entity_id = p_vehicle_id)
  ),
  flagged AS (
    SELECT w.*,
           CASE WHEN w.is_event
                  OR (lag(w.sig) OVER k) IS DISTINCT FROM w.sig
                  OR w.act_tick_n - (lag(w.act_tick_n) OVER k) > 40 THEN 1 ELSE 0 END AS chg,
           max(w.act_tick_n) OVER (PARTITION BY w.act) AS act_top_n
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
           NOT bool_or(g.is_event) AND max(g.act_tick_n) = max(g.act_top_n) AS standing
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

-- ═══ verification ═════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_run uuid; v_page int; v_ev_rows int; v_ev_dec int; v_ev_standing int; v_top bigint; v_decided int; v_standing int; v_bad int;
BEGIN
  -- V1: the ACL survived the replace
  IF NOT (has_function_privilege('anon', 'public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)', 'EXECUTE')
      AND has_function_privilege('authenticated', 'public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)', 'EXECUTE')
      AND has_function_privilege('service_role', 'public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)', 'EXECUTE')) THEN
    RAISE EXCEPTION '0454 V1: the feed lost a grant';
  END IF;
  PERFORM 1 FROM pg_proc p, aclexplode(p.proacl) a
   WHERE p.oid = 'public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)'::regprocedure AND a.grantee = 0;
  IF FOUND THEN RAISE EXCEPTION '0454 V1: the feed is executable by PUBLIC'; END IF;

  SELECT d.sim_run_id INTO v_run FROM public.ottoq_decisions d
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY d.decision_seq DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    -- V2: every deployment in a short window is its own row, and no event reads standing
    SELECT count(*) INTO v_ev_dec FROM public.ottoq_decisions d
     WHERE d.sim_run_id = v_run AND COALESCE(d.resolved_action_context, d.action_context) = 'redeployment'
       AND d.tick_seq > (SELECT max(tick_seq) FROM public.ottoq_decisions WHERE sim_run_id = v_run) - 60;
    SELECT count(*), count(*) FILTER (WHERE f.action = 'redeployment'),
           count(*) FILTER (WHERE f.standing AND f.action IN ('orchestrator_agent','redeployment','itinerary_amended',
                                                             'triage_verdict','gate_intake_no_charge'))
      INTO v_page, v_ev_rows, v_ev_standing
      FROM public.ottoq_activity_feed(v_run, 500, NULL, true, 60) f;
    -- equality is only owed when the page was not truncated at its 500-row cap
    IF v_ev_rows <> v_ev_dec AND v_page < 500 THEN
      RAISE EXCEPTION '0454 V2: % deployments in the window but % deployment rows', v_ev_dec, v_ev_rows;
    END IF;
    IF v_ev_standing > 0 THEN RAISE EXCEPTION '0454 V2: % event rows read standing', v_ev_standing; END IF;

    -- V3: 0453's standing guarantee still holds for the decide path
    SELECT max(tick_seq) INTO v_top FROM public.ottoq_decisions
     WHERE sim_run_id = v_run AND COALESCE(resolved_action_context, action_context) = 'task_start';
    SELECT count(DISTINCT entity_id) INTO v_decided FROM public.ottoq_decisions
     WHERE sim_run_id = v_run AND COALESCE(resolved_action_context, action_context) = 'task_start' AND tick_seq = v_top;
    SELECT count(*) INTO v_standing FROM public.ottoq_activity_feed(v_run, 500, NULL, true, 240) f
     WHERE f.action = 'task_start' AND f.standing;
    IF v_standing > v_decided OR (v_decided > 0 AND v_standing = 0) THEN
      RAISE EXCEPTION '0454 V3: % standing task_start rows against % vehicles judged on the newest tick', v_standing, v_decided;
    END IF;
    SELECT count(*) INTO v_bad FROM public.ottoq_activity_feed(v_run, 500, NULL, true, 240) f
     WHERE f.held_ticks IS NULL OR f.held_ticks < 1 OR f.standing IS NULL OR f.last_at < f.occurred_at;
    IF v_bad > 0 THEN RAISE EXCEPTION '0454 V3: % rows with an impossible held span', v_bad; END IF;
    RAISE NOTICE '0454 run %: % deployment rows for % deployments; % standing task_start of % judged', v_run, v_ev_rows, v_ev_dec, v_standing, v_decided;
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0454_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0454_events_are_their_own_rows_and_a_waiting_vehicle_is_one_row', false,
  'Reporting: corrects 0453''s changes-only stream (events always their own row; a state verdict repeats within 40 of its action''s decide ticks). No tick path reads it.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
