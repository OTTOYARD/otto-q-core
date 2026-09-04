-- =====================================================================
-- 0102  The shadow run that needed no engine change
-- =====================================================================
-- 0101 proposed shadow-routing the transitions through the rules layer as
-- step 1, and called it engine-path work needing a go/no-go.
--
-- IT DOES NOT NEED THE ENGINE AT ALL. ottoq_eval_sm_transition_validity
-- is a pure function of (entity_kind, from_state, to_state): it looks the
-- pair up in ottoq_state_transitions and fails when absent. The engine
-- already records every transition. So the shadow run is a set operation
-- over recorded history, read-only, available right now.
--
-- SECTION 1 — THE ANSWER
-- ---------------------------------------------------------------------
--   distinct (from,to) pairs the engine performs        66
--   pairs declared legal in ottoq_state_transitions     28
--   pairs that would BLOCK                              38
--
--   vehicle transitions recorded                   425,139
--   transitions that would BLOCK                   164,087
--                                                    38.60%
--
-- Switching SM.001 on today would refuse MORE THAN A THIRD of everything
-- the engine does.
--
-- SECTION 2 — WHICH SIDE IS WRONG
-- ---------------------------------------------------------------------
-- Two readings. Either the engine is making 164,087 invalid transitions,
-- or the declaration is incomplete. The top of the would-block list
-- decides it without ambiguity:
--
--   offline                 -> deployed                47,546
--   staged_for_departure    -> offline                 21,598
--   charge_complete_holding -> staged_for_departure    21,036
--   arrived_at_gate         -> offline                 20,750
--   offline                 -> en_route_to_depot       19,686
--   staged_awaiting_service -> offline                 15,608
--   charging_l2             -> offline                  4,532
--   staged_awaiting_service -> in_wash_bay              1,991
--   emergency_staged        -> offline                  1,537
--   tow_requested           -> emergency_staged         1,520
--   staged_awaiting_service -> tow_requested            1,504
--   in_service_bay          -> offline                  1,157
--   charging_dcfc           -> offline                    990
--
-- offline -> deployed is the single most fundamental thing a depot does:
-- a vehicle leaving to go to work. It is the MOST COMMON undeclared
-- transition, 47,546 times. No reading survives in which the engine has
-- been performing 47,546 illegal deployments.
--
--   THE DECLARATION IS INCOMPLETE. THE ENGINE IS NOT WRONG.
--
-- ottoq_state_transitions declares 28 pairs; the engine performs 66. It
-- rotted precisely BECAUSE nothing consulted it - a rule nobody runs is a
-- rule nobody maintains. The gap in 0101 and the rot here are not two
-- findings. They are the same fact seen from either end.
--
-- SECTION 3 — THIS INVERTS THE FIX ORDER
-- ---------------------------------------------------------------------
-- 0101 proposed: route in shadow, measure, then enforce. The measurement
-- came earlier and cheaper than expected, and it changes the sequence:
--
--   WIRING THE RULES UP FIRST WOULD HALT THE DEPOT. SM.001 is
--   enforcement=block. Its first act would be to refuse offline ->
--   deployed.
--
-- The corrected order:
--   1. RECONCILE ottoq_state_transitions against the 66 observed pairs.
--      Each undeclared pair is a decision: legal and undeclared (declare
--      it), or genuinely illegal (fix the engine). 38 decisions, and this
--      file lists them.
--   2. THEN wire the transitions to the rules layer, still in shadow.
--   3. THEN re-measure. The would-block rate must approach zero, and
--      whatever remains is a real defect worth blocking on.
--   4. THEN enforce, expecting forces_recert = TRUE.
--
-- SECTION 4 — A QUESTION INSIDE THE ANSWER, not decided here
-- ---------------------------------------------------------------------
-- A large share of the would-block volume is "-> offline": arrived_at_gate
-- (20,750), staged_awaiting_service (15,608), charging_l2 (4,532),
-- in_service_bay (1,157), charging_dcfc (990), emergency_staged (1,537).
--
-- Those are not operations. They are ottoq_sim_release_depot standing the
-- fleet down at teardown - the same finalizer 0181 caught recording
-- returns that never happened. The state machine does not model teardown,
-- so the finalizer performs transitions no operational path would.
--
-- That is a design question worth asking rather than answering here:
-- should teardown be exempt from transition validity (it is the world
-- being reset, not the world running), or should the state machine
-- declare a terminal path? Declaring every -> offline pair legal to make
-- a rule pass would be the wrong answer arrived at by the easiest route -
-- it would also legalise charging_l2 -> offline for an OPERATIONAL path,
-- where yanking a car out of an active charge session should probably
-- never be allowed.
--
-- SECTION 5 — WHAT THIS COST
-- ---------------------------------------------------------------------
-- Four read-only queries. No migration, no engine change, no risk. 0101
-- estimated this as a shadow-routing project gated on a go/no-go; it was
-- a join against a table that was already there.
--
-- Worth keeping: before building an instrument to measure something,
-- check whether the thing already recorded enough to be measured. The
-- engine had been writing the answer to the signed event stream 1.19
-- million times.
-- =====================================================================

-- §1 — the headline
WITH obs AS (
  SELECT (payload#>>'{diff,current_state,from}') AS from_state,
         (payload#>>'{diff,current_state,to}')   AS to_state, count(*) AS n
    FROM public.ottoq_events
   WHERE event_type='vehicle.state_changed' AND payload#>>'{diff,current_state,to}' IS NOT NULL
   GROUP BY 1,2
), judged AS (
  SELECT o.*, (t.transition_id IS NOT NULL) AS declared_legal
    FROM obs o LEFT JOIN public.ottoq_state_transitions t
           ON t.entity_kind='vehicle' AND t.status='active'
          AND t.from_state=o.from_state AND t.to_state=o.to_state
)
SELECT count(*) AS distinct_pairs,
       count(*) FILTER (WHERE declared_legal) AS pairs_declared_legal,
       count(*) FILTER (WHERE NOT declared_legal AND from_state<>to_state) AS pairs_would_block,
       sum(n) AS transitions_total,
       sum(n) FILTER (WHERE NOT declared_legal AND from_state<>to_state) AS transitions_would_block,
       round(100.0*sum(n) FILTER (WHERE NOT declared_legal AND from_state<>to_state)/sum(n),2) AS pct_would_block
  FROM judged;

-- §2/§3 — the 38 decisions. Each row is: declare it legal, or fix the
-- engine. Do not batch-declare them to make the rule pass.
WITH obs AS (
  SELECT (payload#>>'{diff,current_state,from}') AS from_state,
         (payload#>>'{diff,current_state,to}')   AS to_state, count(*) AS n
    FROM public.ottoq_events
   WHERE event_type='vehicle.state_changed' AND payload#>>'{diff,current_state,to}' IS NOT NULL
   GROUP BY 1,2
)
SELECT o.from_state, o.to_state, o.n AS transitions,
       (o.to_state = 'offline') AS likely_teardown_not_operation
  FROM obs o LEFT JOIN public.ottoq_state_transitions t
         ON t.entity_kind='vehicle' AND t.status='active'
        AND t.from_state=o.from_state AND t.to_state=o.to_state
 WHERE t.transition_id IS NULL AND o.from_state <> o.to_state
 ORDER BY o.n DESC;

-- §1 — what the table currently declares, for comparison
SELECT entity_kind, count(*) AS declared_active
  FROM public.ottoq_state_transitions WHERE status='active'
 GROUP BY entity_kind ORDER BY 1;
