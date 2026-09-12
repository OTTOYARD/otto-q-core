-- migration-version: 20260912033843
-- migration-name: 0253_sm006_points_at_a_five_argument_evaluator_and_the_dispatcher_passes_four
-- ===========================================================================
-- 0253  SM.006 POINTS AT A FIVE-ARGUMENT EVALUATOR AND THE DISPATCHER PASSES
--       FOUR
-- ===========================================================================
-- probe:          db/checks/0167; BUILD_QUEUE P2 #11
-- forces_recert:  FALSE  (argued and asserted below, not assumed)
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT.
--
-- THE DEFECT, VERIFIED FROM THE CATALOG RATHER THAN TAKEN ON REPORT
--
-- A workflow claimed this; I checked it myself before writing the fix, because
-- the whole lesson of db/checks/0167 is that a claim from an instrument is not a
-- finding until the instrument is validated.
--
--   ottoq_rules WHERE rule_code = 'SM.006.bess_transition_validity'
--     evaluator_function = 'ottoq_eval_sm_transition_validity'
--
--   pg_proc for that function:  pronargs = 5, pronargdefaults = 0
--     (p_entity_kind text, p_entity_type text, p_entity_id uuid,
--      p_context jsonb, p_parameters jsonb)
--
--   Every OTHER active rule's evaluator: pronargs = 4, pronargdefaults = 0.
--
--   ottoq_evaluate_rule_core dispatches, verbatim:
--     v_dynamic_sql := format('SELECT * FROM %I($1,$2,$3,$4)', v_rule.evaluator_function);
--     EXECUTE v_dynamic_sql INTO v_result USING p_entity_type, p_entity_id, p_context, v_params;
--
-- Four placeholders, no defaults on the target, so the call cannot resolve. The
-- exception handler catches it and returns:
--
--     'evaluator_error_failclosed: ' || SQLERRM  -->  outcome 'blocked'
--
-- SM.006 is severity critical, enforcement block, scope depot. So the moment
-- `bess_state_change` is announced as an action context, EVERY BESS STATE CHANGE
-- IS REFUSED -- not validated against the state machine, refused outright, with a
-- message about the evaluator rather than about the battery.
--
-- WHY IT HAS NEVER BITTEN, AND WHY THAT IS THE DANGEROUS PART
--
-- `bess_state_change` is not one of the four action contexts the engine
-- announces (task_start, stall_assignment, redeployment, bess_dispatch), so
-- SM.006 has never been evaluated -- zero rows in ottoq_rule_evaluations for its
-- code, ever. The bug is invisible precisely because the rule is unreachable.
--
-- THAT MAKES IT A LANDMINE UNDER G44. G44's fix is to announce the missing
-- action contexts so the nine unreachable rules can fire. The instant that lands,
-- this one starts refusing every BESS transition. Fixing SM.006 FIRST, on its own,
-- is the whole point of shipping it separately: it defuses the mine before the
-- work that arms it, at zero behavioural cost today.
--
-- THE FIX IS THE PATTERN ITS OWN SIBLINGS ALREADY USE
--
-- SM.001, SM.002 and SM.003 each have a dedicated four-argument wrapper that
-- supplies the entity_kind and delegates. Read from the live catalog:
--
--   ottoq_eval_sm_001_vehicle_transition(p_entity_type, p_entity_id, p_context, p_parameters)
--     SELECT * FROM ottoq_eval_sm_transition_validity('vehicle', p_entity_type, ...)
--
-- SM.006 alone was wired straight to the generic. It needs the same wrapper with
-- 'bess', and ottoq_state_transitions already carries 17 active bess transitions,
-- so the data behind it is ready and only the call shape is wrong.
--
-- WHY forces_recert = FALSE, ARGUED
--
-- SM.006 has never been evaluated and `bess_state_change` is still not announced
-- after this migration -- 0253 changes the call shape, not the routing. So no
-- rule evaluation that happens today can change, and no verdict atom can move.
-- A5 asserts the routing is genuinely unchanged rather than trusting that
-- sentence.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The wrapper its siblings already have.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_eval_sm_006_bess_transition(
  p_entity_type text,
  p_entity_id   uuid,
  p_context     jsonb,
  p_parameters  jsonb)
RETURNS ottoq_rule_result
LANGUAGE sql STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT * FROM ottoq_eval_sm_transition_validity('bess', p_entity_type, p_entity_id, p_context, p_parameters);
$function$;

COMMENT ON FUNCTION public.ottoq_eval_sm_006_bess_transition(text,uuid,jsonb,jsonb) IS
  '0253: the four-argument wrapper SM.006 was missing. ottoq_evaluate_rule_core '
  'dispatches every evaluator as %I($1,$2,$3,$4); SM.006 pointed straight at the '
  'five-argument generic, so it could only ever return evaluator_error_failclosed '
  'and BLOCK. Identical in shape to ottoq_eval_sm_001_vehicle_transition.';

-- ---------------------------------------------------------------------------
-- 2. Point the rule at it.
-- ---------------------------------------------------------------------------
UPDATE public.ottoq_rules
   SET evaluator_function = 'ottoq_eval_sm_006_bess_transition',
       updated_at = now()
 WHERE rule_code = 'SM.006.bess_transition_validity'
   AND status = 'active';

-- ---------------------------------------------------------------------------
-- 3. Assertions, including a real behavioural one.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_n      int;
  v_bad    int;
  v_from   text; v_to text;
  v_res    ottoq_rule_result;
  v_ctx    jsonb;
BEGIN
  -- A1. Every active rule's evaluator now takes exactly four arguments with no
  --     defaults. This is the general form of the defect, not just SM.006's
  --     instance -- if another rule is ever wired to a wrong-arity function, this
  --     assertion is what catches it.
  SELECT count(*) INTO v_bad
    FROM public.ottoq_rules r
    JOIN pg_proc p ON p.proname = r.evaluator_function
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
   WHERE r.status = 'active' AND (p.pronargs - p.pronargdefaults) <> 4;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'A1 FAILED: % active rule(s) point at an evaluator the 4-arg dispatcher cannot call', v_bad;
  END IF;

  -- A2. Every active rule's evaluator actually exists. A dangling name fails the
  --     same way and would slip past A1's join.
  SELECT count(*) INTO v_bad
    FROM public.ottoq_rules r
   WHERE r.status = 'active'
     AND to_regprocedure('public.' || r.evaluator_function || '(text,uuid,jsonb,jsonb)') IS NULL;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'A2 FAILED: % active rule(s) name an evaluator with no 4-arg signature', v_bad;
  END IF;

  -- A3. BEHAVIOURAL: the wrapper accepts a REAL invalid bess transition and
  --     refuses it for the RIGHT reason -- because the state machine says so,
  --     not because the evaluator blew up. Before 0253 this call raised.
  SELECT t.from_state INTO v_from FROM ottoq_state_transitions t
   WHERE t.entity_kind='bess' AND t.status='active' LIMIT 1;
  v_ctx := jsonb_build_object('from_state', v_from,
                              'to_state', '__no_such_state__',
                              'actor_type', 'ottoq_engine');
  v_res := public.ottoq_eval_sm_006_bess_transition('bess', NULL::uuid, v_ctx, '{}'::jsonb);
  IF v_res.passed THEN
    RAISE EXCEPTION 'A3 FAILED: an invalid bess transition was allowed';
  END IF;
  IF v_res.reason NOT LIKE 'invalid transition for bess%' THEN
    RAISE EXCEPTION 'A3 FAILED: refused for the wrong reason: %', v_res.reason;
  END IF;

  -- A4. BEHAVIOURAL, the other direction: a real VALID transition passes. A rule
  --     that refuses everything also satisfies A3, and that is exactly the state
  --     0253 is fixing -- so the fix must be shown not to be a different flavour
  --     of always-block.
  SELECT t.from_state, t.to_state INTO v_from, v_to FROM ottoq_state_transitions t
   WHERE t.entity_kind='bess' AND t.status='active'
     AND cardinality(t.allowed_actor_types) = 0 LIMIT 1;
  IF v_from IS NULL THEN
    SELECT t.from_state, t.to_state INTO v_from, v_to FROM ottoq_state_transitions t
     WHERE t.entity_kind='bess' AND t.status='active'
       AND 'ottoq_engine' = ANY(t.allowed_actor_types) LIMIT 1;
  END IF;
  IF v_from IS NULL THEN
    RAISE NOTICE 'A4 SKIPPED: no bess transition this actor may make; A3 alone carries the proof';
  ELSE
    v_res := public.ottoq_eval_sm_006_bess_transition('bess', NULL::uuid,
               jsonb_build_object('from_state', v_from, 'to_state', v_to,
                                  'actor_type', 'ottoq_engine'), '{}'::jsonb);
    IF NOT v_res.passed THEN
      RAISE EXCEPTION 'A4 FAILED: a valid bess transition % -> % was refused: %', v_from, v_to, v_res.reason;
    END IF;
  END IF;

  -- A5. The ROUTING is unchanged: bess_state_change is still not announced, so
  --     SM.006 still cannot fire and this migration cannot move a verdict. This
  --     is what forces_recert=FALSE rests on, asserted rather than asserted-at.
  SELECT count(*) INTO v_n FROM public.ottoq_rules
   WHERE status='active' AND 'bess_state_change' = ANY(applies_to_actions);
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A5 FAILED: expected exactly SM.006 to listen for bess_state_change, found %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_rule_evaluations
   WHERE rule_code = 'SM.006.bess_transition_validity';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A5 FAILED: SM.006 has % evaluation(s); it was believed unreachable and the '
                    'forces_recert=FALSE argument depends on that', v_n;
  END IF;

  RAISE NOTICE 'A1-A5 PASSED: SM.006 now resolves, refuses invalid bess transitions for the right '
               'reason, allows valid ones, and is still unreachable so no verdict can move';
END $$;

-- ===========================================================================
-- WHAT REMAINS: G44 itself. Nine rules cannot fire because the engine announces
-- four action contexts and they listen outside that set. 0253 removes the one
-- booby trap in that set so the routing fix can be judged on its own behaviour
-- instead of on a cascade of BESS refusals. It does NOT close G44.
-- ===========================================================================
-- ===========================================================================
-- APPLIED 2026-09-12 03:38:43 UTC (2026-09-11 10:38 PM CT) -- version 20260912033843
--
-- A1-A5 all passed. The defect was re-confirmed from the live catalog
-- immediately before applying, not taken on the workflow's report:
--     active rules whose evaluator the 4-arg dispatcher cannot call:  1  -> 0
--     active rules naming a non-existent 4-arg signature:             1  -> 0
--     rules listening for bess_state_change:                          1 (SM.006)
--     SM.006 evaluations, all time:                                   0
--     active bess transitions available to the wrapper:              17
--
-- Submitted whole and unedited; scripts/exec-digest.py --check confirms this file
-- carries no comments inside a stored body, so there was nothing to condense.
--
-- WHAT THIS DID NOT DO: G44 is still open. SM.006 remains unreachable by design --
-- that is what A5 asserts and what forces_recert=FALSE rests on. The landmine is
-- defused; the routing fix that would have stepped on it is still to come.
-- ===========================================================================
