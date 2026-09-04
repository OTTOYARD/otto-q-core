-- =====================================================================
-- 0103  The answer is different for every rule
-- =====================================================================
-- Completing 0102 across the other entity kinds. The result is not one
-- verdict, it is three, and they point in different directions - which is
-- exactly why "wire up the rules layer" was never a single decision.
--
-- SECTION 1 — THE FULL PICTURE
-- ---------------------------------------------------------------------
--   entity   declared  observed  undeclared   volume      declared
--            (active)   pairs      pairs     would block  never seen
--   vehicle     41        66         38        38.60%        13
--   stall       10         2          0         0.00%         8
--   bess        17    NO EVENTS AT ALL          n/a          17
--   task        14    (HW.006, not measured here)
--
-- SM.003 (stall) COULD BE SWITCHED ON TODAY. Two distinct transitions
-- across 344,340 events, both declared legal, nothing would block.
--
-- SM.001 (vehicle) CANNOT. 38.60%, and the most common undeclared pair is
-- offline -> deployed, 47,546 times (0102).
--
-- SM.006 (bess) HAS NO SOURCE. See §2 - this is the correction.
--
-- SECTION 2 — A CORRECTION TO 0101
-- ---------------------------------------------------------------------
-- 0101 concluded, in capitals: "IT IS A ROUTING PROBLEM, NOT A DETECTION
-- PROBLEM. The transitions, the rules, and the evaluators all exist;
-- nothing connects them."
--
-- THAT IS TRUE FOR VEHICLE AND STALL AND FALSE FOR BESS. There is no
-- bess.state_changed event type. No event type matching bess, battery or
-- storage exists in ottoq_events at all. The BESS state machine declares
-- 17 active transitions and the engine has never once recorded taking
-- one.
--
-- So SM.006 is not a rule waiting to be connected. It is a rule with
-- nothing to connect to, and wiring it would be building the event
-- source first. Different work, different size, and 0101 obscured that by
-- generalising from the two entity kinds that happened to be
-- well-instrumented.
--
-- I drew the general claim from vehicle and stall, which have 1.19M and
-- 767k events respectively, and did not check the third. The same shape
-- as 0098's phantom: a conclusion correct about what was measured and
-- wrong about what was not.
--
-- SECTION 3 — THE PAYLOAD SHAPES DIFFER, AND ONE MORE TRAP
-- ---------------------------------------------------------------------
-- Vehicles carry the transition at   diff.current_state.{from,to}
-- Stalls  carry it at                diff.status.{from,to}
--
-- Anything routing these events must handle per-entity payload shapes;
-- there is no single accessor. And the gating problem from 0101 §3 is
-- WORSE for stalls than for vehicles:
--
--   vehicle.state_changed   ~29% carry no transition
--   stall.state_changed      55% carry no transition
--                            (344,340 of 767,357 do)
--
-- More than half of the events named "stall.state_changed" are not state
-- changes. Routing on event_type alone would hand SM.003 over 423,000
-- non-transitions.
--
-- SECTION 4 — DEAD DECLARATIONS, THE OTHER DIRECTION
-- ---------------------------------------------------------------------
-- The table is not only incomplete. It also declares transitions the
-- engine never performs:
--
--   vehicle   13 of 41 declared, never seen
--   stall      8 of 10 declared, never seen
--   bess      17 of 17 declared, never seen
--
-- The stall machine is the striking one: the engine exercises 2 of its 10
-- declared transitions. Either the design anticipated states the engine
-- never grew, or those paths exist and no scenario has reached them. Both
-- are worth knowing before anyone treats this table as a specification of
-- what the depot does.
--
-- A declaration nothing reads drifts in BOTH directions at once, and it
-- did.
--
-- SECTION 5 — WHAT THIS CHANGES ABOUT THE PLAN
-- ---------------------------------------------------------------------
-- 0102 gave a single corrected order: reconcile, wire, re-measure,
-- enforce. That still holds per rule, but the rules are not at the same
-- stage and should not move together:
--
--   SM.003 stall     reconcile NOT needed. Wire it (with the §3 gate on
--                    the from/to pair, and the stall payload shape), then
--                    enforce. Lowest risk of the three, and it would put
--                    a real critical/block rule into service.
--   SM.001 vehicle   reconcile the 38 pairs FIRST (0102 lists them).
--                    Wiring before that halts the depot.
--   SM.006 bess      build the event source, or retire the rule. It has
--                    been declared-and-dark since it was written.
--
-- SECTION 6 — STILL NOT DECIDED HERE, ON PURPOSE
-- ---------------------------------------------------------------------
-- Every one of the above is a recommendation with the measurement
-- attached, not a change. Nothing in 0101, 0102 or 0103 has altered the
-- engine, the rules, or the transition table. The three checks are an
-- argument for a decision, and the decision is Chase's:
--   - the 38 vehicle transitions: declare, or fix the engine, one by one
--   - teardown (-> offline): exempt, or give it a declared terminal path
--   - SM.006: build the BESS event source, or retire the rule
-- =====================================================================

-- §1 — the full picture, per entity kind
WITH veh AS (
  SELECT (payload#>>'{diff,current_state,from}') f, (payload#>>'{diff,current_state,to}') t, count(*) n
    FROM public.ottoq_events WHERE event_type='vehicle.state_changed'
     AND payload#>>'{diff,current_state,to}' IS NOT NULL GROUP BY 1,2
), sta AS (
  SELECT (payload#>>'{diff,status,from}') f, (payload#>>'{diff,status,to}') t, count(*) n
    FROM public.ottoq_events WHERE event_type='stall.state_changed'
     AND payload#>>'{diff,status,to}' IS NOT NULL GROUP BY 1,2
)
SELECT 'vehicle' AS entity,
       (SELECT count(*) FROM public.ottoq_state_transitions WHERE entity_kind='vehicle' AND status='active') AS declared,
       (SELECT count(*) FROM veh) AS observed_pairs,
       (SELECT count(*) FROM veh v LEFT JOIN public.ottoq_state_transitions t
          ON t.entity_kind='vehicle' AND t.status='active' AND t.from_state=v.f AND t.to_state=v.t
        WHERE t.transition_id IS NULL AND v.f IS DISTINCT FROM v.t) AS undeclared_pairs
UNION ALL
SELECT 'stall',
       (SELECT count(*) FROM public.ottoq_state_transitions WHERE entity_kind='stall' AND status='active'),
       (SELECT count(*) FROM sta),
       (SELECT count(*) FROM sta s LEFT JOIN public.ottoq_state_transitions t
          ON t.entity_kind='stall' AND t.status='active' AND t.from_state=s.f AND t.to_state=s.t
        WHERE t.transition_id IS NULL AND s.f IS DISTINCT FROM s.t)
UNION ALL
SELECT 'bess',
       (SELECT count(*) FROM public.ottoq_state_transitions WHERE entity_kind='bess' AND status='active'),
       0, 0;

-- §2 — the correction. This must return zero rows: BESS records nothing.
SELECT event_type, count(*) FROM public.ottoq_events
 WHERE event_type ILIKE '%bess%' OR event_type ILIKE '%battery%' OR event_type ILIKE '%storage%'
 GROUP BY 1;

-- §3 — the gating trap, worse for stalls than vehicles
SELECT event_type, count(*) AS events,
       count(*) FILTER (WHERE payload#>>'{diff,current_state,to}' IS NOT NULL) AS carries_current_state,
       count(*) FILTER (WHERE payload#>>'{diff,status,to}' IS NOT NULL)        AS carries_status,
       round(100.0*(count(*) - count(*) FILTER (WHERE payload#>>'{diff,current_state,to}' IS NOT NULL
                                                   OR payload#>>'{diff,status,to}' IS NOT NULL))/count(*),1)
         AS pct_without_any_transition
  FROM public.ottoq_events
 WHERE event_type IN ('vehicle.state_changed','stall.state_changed')
 GROUP BY event_type ORDER BY events DESC;

-- §4 — declarations the engine never exercises
SELECT t.entity_kind, count(*) AS declared_never_seen
  FROM public.ottoq_state_transitions t
 WHERE t.status='active'
   AND NOT EXISTS (
     SELECT 1 FROM public.ottoq_events e
      WHERE (t.entity_kind='vehicle' AND e.event_type='vehicle.state_changed'
             AND e.payload#>>'{diff,current_state,from}' = t.from_state
             AND e.payload#>>'{diff,current_state,to}'   = t.to_state)
         OR (t.entity_kind='stall' AND e.event_type='stall.state_changed'
             AND e.payload#>>'{diff,status,from}' = t.from_state
             AND e.payload#>>'{diff,status,to}'   = t.to_state))
 GROUP BY t.entity_kind ORDER BY 1;
