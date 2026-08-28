-- migration-version: 20260828040000
-- migration-name:    activity_feed
-- 0079 -- The V1 audit/activity log: a read-side feed of orchestration decisions with their WHY.
--
-- CONTEXT. Chase's V1 bar is "a 2D representation with an audit/activity log showing in real time
-- WHY assets were orchestrated in specific manners." The orchestration already happens and is
-- recorded in ottoq_decisions -- but nothing surfaces it as a human-readable, chronological feed.
-- The existing audit stack (ottoq_generate_audit_bundle / _verify / _sign / ottoq_entity_history /
-- ottoq_booking_provenance_audit) is FORENSIC: signed bundles, raw event history, provenance. It is
-- not a live "why did this vehicle move here" feed.
--
-- The "why" already exists in three structured places on each ottoq_decisions row:
--   * proposed_action.rationale   -- the proposer's own reasoning (e.g. {"soc":98,"floor":80},
--                                    {"need":"no_wash_outstanding","wash_cap":2,...})
--   * rule_results[].reason       -- plain-English shield confirmations ("grid capacity OK ...",
--                                    "charger NASH-L2-04 available and online", "stall available")
--   * override_rule_codes         -- which shield rule blocked a proposal (e.g. EN.001.grid_capacity_ceiling)
--   * l2_engine / proposed_action.source -- who proposed (cuopt, nemotron, needs_card, deterministic_v1)
--
-- This function is a PURE READ (STABLE, no writes) over public tables, exposed to PostgREST so the
-- twin cockpit and both operator cockpits render the same feed. It is the "renderer only draws"
-- half of the contract: it does not decide, it does not mutate, it only projects ottoq_decisions.

CREATE OR REPLACE FUNCTION public.ottoq_activity_feed(
  p_sim_run_id uuid,
  p_limit integer DEFAULT 200,
  p_vehicle_id uuid DEFAULT NULL
)
 RETURNS TABLE (
   occurred_at      timestamptz,
   vehicle_id       uuid,
   display_name     text,
   action           text,
   engine           text,
   target           text,
   outcome          text,
   rationale        jsonb,
   reason           text
 )
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  SELECT
    d.sim_clock AS occurred_at,
    d.entity_id AS vehicle_id,
    v.display_name,
    COALESCE(d.resolved_action_context, d.action_context) AS action,
    COALESCE(NULLIF(d.l2_engine,''), d.proposed_action->>'source') AS engine,
    COALESCE(
      s.stall_code,
      CASE
        WHEN d.enacted_action->>'verb' IS NOT NULL THEN d.enacted_action->>'verb'
        WHEN d.proposed_action->>'verb' IS NOT NULL THEN d.proposed_action->>'verb'
      END
    ) AS target,
    d.outcome_status AS outcome,
    d.proposed_action->'rationale' AS rationale,
    CASE
      -- 1. A shielded proposal: say which rule blocked it.
      WHEN d.override_rule_codes IS NOT NULL
       AND cardinality(d.override_rule_codes) > 0
        THEN 'blocked: ' || array_to_string(d.override_rule_codes, ', ')
      -- 2. The proposer's own rationale (richest).
      WHEN d.proposed_action ? 'rationale'
       AND jsonb_typeof(d.proposed_action->'rationale') <> 'null'
        THEN (d.proposed_action->'rationale')::text
      -- 3. The shield's plain-English confirmation.
      WHEN jsonb_typeof(d.rule_results) = 'array'
       AND jsonb_array_length(d.rule_results) > 0
        THEN COALESCE(d.rule_results->0->>'reason', d.rule_results->0->>'rule_code')
      -- 4. Fall back to who proposed it.
      ELSE COALESCE(NULLIF(d.l2_engine,''), d.proposed_action->>'source')
    END AS reason
  FROM ottoq_decisions d
  LEFT JOIN vehicles v ON v.id = d.entity_id AND d.entity_type = 'vehicle'
  LEFT JOIN stalls  s ON s.id = COALESCE(
        (d.enacted_action->>'stall_id')::uuid,
        (d.proposed_action->>'stall_id')::uuid)
  WHERE d.sim_run_id = p_sim_run_id
    AND (p_vehicle_id IS NULL OR d.entity_id = p_vehicle_id)
  ORDER BY d.sim_clock DESC, d.decision_seq DESC
  LIMIT p_limit;
$fn$;

COMMENT ON FUNCTION public.ottoq_activity_feed(uuid, integer, uuid) IS
  'Read-side audit/activity feed: orchestration decisions with their why, for the twin and operator cockpits.';
