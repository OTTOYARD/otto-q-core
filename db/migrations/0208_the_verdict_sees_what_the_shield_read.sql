-- ---------------------------------------------------------------------------
-- 0208 — h_rule must see WHAT THE RULES READ, not only what they decided.
--
-- WHY (found by round 22's read; recorded in db/checks/0118):
--
-- 0205 promoted h_rule into the pair verdict on six agreeing pairs. Round 22
-- shows the instrument is narrower than the claim it carries.
--
-- 0204 (G15) stopped the L1 shield reading the wall clock inside the twin. On
-- the 171717/24t column the effect is unmistakable:
--
--     TW.001.operational_hours evaluations   1,036 -> 1,036   (unchanged)
--     distinct result_payload->>'local_time'     1 -> 24      (00:00 - 23:30)
--     h_rule                          62ed1a1e… -> 62ed1a1e…  (UNMOVED)
--
-- The evaluator went from judging every task against one frozen local time to
-- judging each against the run's own clock. The verdict did not notice.
--
-- ottoq_hash_rule_evaluations hashes rule_code, rule_version, action_context,
-- entity_type, entity_id, passed, severity, enforcement, enforcement_taken and
-- parameters_used. `parameters_used` looks like the evaluator's inputs and is
-- not: it is the rule's CONFIGURED THRESHOLDS, and it is CONSTANT per rule.
-- Measured on a full round-22 arm, all twenty active rules have exactly ONE
-- distinct parameters_used value each. Five carry a value at all —
--
--     HW.001  {"strict": true}
--     HW.002  {"allowed_states": ["Available"], "max_offline_seconds": 90}
--     HW.003  {"max_stale_seconds": 300}
--     EN.004  {"allow_bess_offset": true}
--     TW.005  {"buffer_minutes": 15}
--
-- — and the other fifteen carry {}. So that field can detect a THRESHOLD
-- change, which is worth having, and can never vary with what an evaluator
-- read on a given tick.
--
-- Every bit of per-evaluation variation lives in `result_payload`, and
-- result_payload is not hashed at all:
--
--     SLA.004  91 distinct payloads / 106 evaluations
--     SLA.007  74 / 106      EN.001  44 / 760      HW.002  41 / 760
--     HW.004   40 / 179      TW.001  24 / 581
--
-- So the shipped h_rule answers "did the same rules fire on the same entities,
-- under the same thresholds, and reach the same verdicts". It does not answer
-- "did they read the same world". An engine change that fed every evaluator a
-- wrong grid headroom, a wrong SoC, or a wrong clock passes the pair and moves
-- no canon.
--
-- (The first draft of this header claimed parameters_used was {} everywhere.
-- A2's precondition refused the apply and named five rules that carry it. The
-- claim above is the re-measurement; the correction is left visible because
-- the refusal is the reason the migration is correct.)
--
-- This did not weaken any past verdict: both arms of a pair are equally blind
-- and they agreed. It is a ROUND-TO-ROUND detection gap, the same class 0139
-- closed for endst and 0199 closed for the proposal stream.
--
-- WHAT THIS DOES: folds result_payload into the hash, minus the keys proven
-- volatile between arms.
--
-- WHY A NAMED DENYLIST AND NOT A PATTERN. Measured on all nine round-22 pairs,
-- key by key, exactly ONE (rule_code, key) ever disagrees between arms:
--
--     SLA.004.required_services_complete / visit_needs_id   4 of 9 pairs
--
-- visit_needs_id is the id of a row the run itself creates, so it differs
-- between arms by construction — the same reason 0139 made endst id-blind.
-- Every other key on every other rule is arm-stable, including the entity
-- uuids (stall_id, charger_id, vehicle_id), which name pre-existing rows.
--
-- The excluded key is therefore NAMED, not matched by a `%_id` pattern. A new
-- volatile key appearing later must fail a pair loudly and be classified here
-- on purpose. A pattern would swallow it silently, and a check that cannot
-- fail is not a check.
--
-- ROLLED-BACK LIVE PROBE (A4 below) recomputes the candidate hash over all
-- nine round-22 pairs and asserts BOTH halves: every pair equal (the hash is
-- not spuriously volatile) AND the value moved off the old one (the change is
-- not a no-op).
--
-- PREDICTION, written before round 23 runs:
--   * canon_rule MOVES on all six flagship columns and on the grid fixture.
--     It must move: the hash now covers content it did not cover.
--   * NOTHING ELSE MOVES. h_cmd, h_dec, h_evt, h_bkg, h_nrg, h_prop, h_defr,
--     h_cal, fp and endst are untouched — this migration changes one hash
--     function and no engine behaviour whatsoever.
--   * All nine pairs pass. The probe already proved arm-equality on the
--     round-22 rows; round 23 re-proves it on fresh ones.
--   If h_cmd moves anywhere, this migration did something it should not have
--   and the reading is wrong, not the engine.
--
-- forces_recert: TRUE. canon_rule moves everywhere, so the streak restarts.
-- ---------------------------------------------------------------------------

BEGIN;

SET LOCAL statement_timeout = '10min';

-- --- A0. Pin what we are rewriting -----------------------------------------
CREATE TEMP TABLE _pin_0208(name text PRIMARY KEY, md5_before text) ON COMMIT DROP;
INSERT INTO _pin_0208 VALUES
  ('ottoq_hash_rule_evaluations', '453cf9b9c3302a79072bac9b35d93480');

DO $$
DECLARE v_live text; v_pin text;
BEGIN
  SELECT md5_before INTO v_pin FROM _pin_0208 WHERE name='ottoq_hash_rule_evaluations';
  SELECT md5(p.prosrc) INTO v_live
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_hash_rule_evaluations';
  IF v_live IS NULL THEN
    RAISE EXCEPTION 'PRECONDITION: public.ottoq_hash_rule_evaluations does not exist'
      USING ERRCODE='P0208';
  END IF;
  IF v_live IS DISTINCT FROM v_pin THEN
    RAISE EXCEPTION 'PRECONDITION: ottoq_hash_rule_evaluations body drifted: % (pinned %)',
      v_live, v_pin USING ERRCODE='P0208';
  END IF;
END $$;

-- --- A1. Precondition: the blind spot is really there ----------------------
-- If a previous migration already folded result_payload in, this one is moot
-- and must refuse rather than silently rewrite over it.
DO $$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_hash_rule_evaluations';
  IF v_def LIKE '%result_payload%' THEN
    RAISE EXCEPTION 'PRECONDITION: h_rule already hashes result_payload; 0208 is moot'
      USING ERRCODE='P0208';
  END IF;
  IF v_def NOT LIKE '%parameters_used%' THEN
    RAISE EXCEPTION 'PRECONDITION: h_rule does not hash parameters_used either; '
                    'the body is not the one 0208 was written against'
      USING ERRCODE='P0208';
  END IF;
END $$;

-- --- A2. Precondition: the hashed field CANNOT carry per-evaluation reads,
--         and the unhashed one demonstrably does.
--
-- This is the assertion the whole migration rests on, and it is the one that
-- caught the first draft's wrong claim. Both halves must hold on a real
-- round-22 arm:
--   (a) no rule code has more than one distinct parameters_used value — the
--       hashed field is a per-rule constant, so it cannot be standing in for
--       what the evaluator read;
--   (b) at least one rule has many distinct result_payload values — the
--       unhashed field is where the reads actually are.
-- If (a) fails, parameters_used already carries reads and the blind spot is
-- narrower than described. If (b) fails, there is nothing to fold in.
DO $$
DECLARE v_multi int; v_max_payloads int; v_run uuid; v_worst text;
BEGIN
  SELECT r.sim_run_id INTO v_run
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id='11111111-1111-1111-1111-111111111111'
     AND r.status='completed'
     AND EXISTS (SELECT 1 FROM public.ottoq_rule_evaluations e
                  WHERE e.sim_run_id = r.sim_run_id)
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE EXCEPTION 'PRECONDITION: no completed flagship run carries rule evaluations'
      USING ERRCODE='P0208';
  END IF;

  SELECT count(*) INTO v_multi FROM (
    SELECT e.rule_code FROM public.ottoq_rule_evaluations e
     WHERE e.sim_run_id = v_run
     GROUP BY 1 HAVING count(DISTINCT e.parameters_used::text) > 1) q;
  IF v_multi > 0 THEN
    RAISE EXCEPTION 'PRECONDITION (a): % rule codes vary their parameters_used '
                    'on run % — the hashed field DOES carry per-evaluation '
                    'reads and the blind spot is narrower than 0208 describes; '
                    're-measure before rewriting', v_multi, v_run
      USING ERRCODE='P0208';
  END IF;

  SELECT max(n), (array_agg(rule_code ORDER BY n DESC))[1]
    INTO v_max_payloads, v_worst
    FROM (SELECT e.rule_code, count(DISTINCT e.result_payload::text) AS n
            FROM public.ottoq_rule_evaluations e
           WHERE e.sim_run_id = v_run GROUP BY 1) q;
  IF COALESCE(v_max_payloads, 0) < 2 THEN
    RAISE EXCEPTION 'PRECONDITION (b): no rule on run % has more than one '
                    'distinct result_payload — there is nothing for 0208 to '
                    'fold in', v_run USING ERRCODE='P0208';
  END IF;

  RAISE NOTICE '0208 A2: run %, parameters_used constant per rule; '
               'result_payload varies up to % values (%)',
               v_run, v_max_payloads, v_worst;
END $$;

-- --- A3. The rewrite -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_hash_rule_evaluations(p_run uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
  --: WHAT THE RULE DECIDED, AND WHAT IT READ.
  --:
  --: The decision half (rule_code .. enforcement_taken) is 0203's original.
  --: result_payload is 0208's addition: it is where every evaluator records
  --: the world it looked at -- the local time, the grid headroom, the SoC, the
  --: stall it found occupied. Without it the verdict could not distinguish a
  --: shield reading the run's clock from one reading the wall clock, which is
  --: exactly what 0204 changed and h_rule did not see (db/checks/0118).
  --:
  --: EXCLUDED KEYS, each named on purpose rather than matched by a pattern.
  --: Measured key-by-key across all nine round-22 pairs, this is the complete
  --: set that differs between two arms of the same run:
  --:
  --:   visit_needs_id  -- the id of a row the RUN creates (SLA.004). Differs
  --:                      between arms by construction, like every run-scoped
  --:                      id 0139 stripped from endst. Entity uuids that name
  --:                      PRE-EXISTING rows (stall_id, charger_id, vehicle_id)
  --:                      are arm-stable and stay in the hash.
  --:
  --: A new volatile key must FAIL a pair and be classified here deliberately.
  --: A `%_id` pattern would swallow it silently, and a check that cannot fail
  --: is not a check.
  SELECT md5(COALESCE(string_agg(
           e.rule_code || '|' || COALESCE(e.rule_version::text,'-') || '|' || COALESCE(e.action_context,'-')
           || '|' || COALESCE(e.entity_type,'-') || '|' || COALESCE(e.entity_id::text,'-')
           || '|' || COALESCE(e.passed::text,'-') || '|' || COALESCE(e.severity,'-')
           || '|' || COALESCE(e.enforcement,'-') || '|' || COALESCE(e.enforcement_taken,'-')
           || '|' || COALESCE(e.parameters_used::text,'-')
           || '|' || COALESCE((e.result_payload - 'visit_needs_id')::text,'-'),
           E'\n' ORDER BY e.rule_code, COALESCE(e.rule_version::text,'-'), COALESCE(e.action_context,'-'),
                          COALESCE(e.entity_type,'-'), COALESCE(e.entity_id::text,'-'),
                          COALESCE(e.passed::text,'-'), COALESCE(e.severity,'-'),
                          COALESCE(e.enforcement,'-'), COALESCE(e.enforcement_taken,'-'),
                          COALESCE(e.parameters_used::text,'-'),
                          COALESCE((e.result_payload - 'visit_needs_id')::text,'-')), ''))
    FROM public.ottoq_rule_evaluations e
   WHERE e.sim_run_id = p_run;
$function$;

-- --- A4. Exact-once rewrite proof ------------------------------------------
DO $$
DECLARE v_def text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_hash_rule_evaluations';

  -- The EXACT hashed fragment must appear exactly twice: once building the
  -- string, once in the ORDER BY that makes the aggregate deterministic.
  -- Counting the bare token 'result_payload' would also count the comment
  -- block above it and could not tell a hashed column from a mention of one.
  v_n := (length(v_def) - length(replace(v_def, '(e.result_payload - ''visit_needs_id'')::text', '')))
         / length('(e.result_payload - ''visit_needs_id'')::text');
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'REWRITE: the hashed result_payload fragment appears % '
                    'times, expected exactly 2 (the payload and the ORDER BY). '
                    'One occurrence means the aggregate is unordered and the '
                    'hash is not reproducible.', v_n USING ERRCODE='P0208';
  END IF;

  -- the decision half survived intact
  IF v_def NOT LIKE '%enforcement_taken%' OR v_def NOT LIKE '%parameters_used%' THEN
    RAISE EXCEPTION 'REWRITE: the 0203 decision fields were lost'
      USING ERRCODE='P0208';
  END IF;
END $$;

-- --- A5. Rolled-back live probe: BOTH halves -------------------------------
-- (a) every round-22 pair agrees under the new hash  -> not spuriously volatile
-- (b) the value MOVED off the old hash on every pair -> not a no-op
DO $$
DECLARE
  v_pairs int; v_disagree int; v_unmoved int;
BEGIN
  WITH pairs AS (
    SELECT r.sim_run_id, r.started_at,
           row_number() OVER (PARTITION BY r.started_at ORDER BY r.sim_run_id) AS arm
      FROM public.ottoq_sim_runs r
     WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
       AND r.started_at >= '2026-09-07 18:27:44+00'
       AND r.status = 'completed'),
  h AS (
    SELECT p.started_at, p.arm,
           public.ottoq_hash_rule_evaluations(p.sim_run_id) AS h_new,
           (SELECT r.validation_notes::jsonb->'arm_a'->>'h_rule'
              FROM public.ottoq_sim_runs r
             WHERE r.sim_run_id = p.sim_run_id) AS h_old
      FROM pairs p),
  per_pair AS (
    SELECT started_at,
           max(h_new) FILTER (WHERE arm=1) AS a,
           max(h_new) FILTER (WHERE arm=2) AS b,
           max(h_old) FILTER (WHERE arm=1) AS old_a
      FROM h GROUP BY 1)
  SELECT count(*),
         count(*) FILTER (WHERE a IS DISTINCT FROM b),
         count(*) FILTER (WHERE old_a IS NOT NULL AND a = old_a)
    INTO v_pairs, v_disagree, v_unmoved
    FROM per_pair;

  IF v_pairs < 9 THEN
    RAISE EXCEPTION 'PROBE: only % round-22 pairs found, expected 9 — the '
                    'probe has no evidence to stand on', v_pairs USING ERRCODE='P0208';
  END IF;
  IF v_disagree > 0 THEN
    RAISE EXCEPTION 'PROBE (a): % of % pairs DISAGREE under the new hash — '
                    'result_payload carries volatile content beyond '
                    'visit_needs_id; widen the denylist and re-measure before '
                    'applying', v_disagree, v_pairs USING ERRCODE='P0208';
  END IF;
  IF v_unmoved > 0 THEN
    RAISE EXCEPTION 'PROBE (b): % of % pairs hash IDENTICALLY to the old '
                    'h_rule — the rewrite changed nothing and this migration '
                    'is a no-op', v_unmoved, v_pairs USING ERRCODE='P0208';
  END IF;

  RAISE NOTICE '0208 probe: % pairs, all arm-equal, all moved off the old hash', v_pairs;
END $$;

-- --- A6. Lineage -----------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0208_the_verdict_sees_what_the_shield_read', TRUE,
        'h_rule now hashes result_payload (minus the run-generated '
        'visit_needs_id), so the verdict sees what each evaluator READ and not '
        'only what it decided. Found by round 22: 0204 changed TW.001''s '
        'local_time from 1 distinct value to 24 and h_rule did not move. '
        'canon_rule moves on every column by design; no engine behaviour '
        'changes and no other hash may move.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-07 21:36:53 UTC (4:36 PM CT), second attempt.
--
-- THE FIRST ATTEMPT WAS REFUSED BY ITS OWN A2, and that refusal is the reason
-- this migration is correct rather than merely applied. The header claimed
-- parameters_used was {} on all twenty active rules; A2 read a real round-22
-- arm and answered:
--
--     PRECONDITION: 5 rule codes DO carry parameters_used on run
--     82a126b1-67e0-4d73-8de1-77055f0d1662; the blind spot is narrower than
--     0208 describes - re-measure before rewriting
--
-- Re-measuring produced the sharper and true statement now in the header:
-- parameters_used is the rule's CONFIGURED THRESHOLDS, exactly one distinct
-- value per rule across all twenty (five carry a value, fifteen carry {}), so
-- it can catch a threshold change and can never vary with what an evaluator
-- read. A2 was rewritten to assert THAT property — no rule varies its
-- parameters_used, and at least one rule varies its result_payload — which is
-- the property the migration actually rests on.
--
-- CATALOG-VERIFIED AFTER APPLY (not the client's success message):
--     ottoq_hash_rule_evaluations  md5 453cf9b9… -> e87e34ba…
--     pg_get_functiondef LIKE '%result_payload%'   true
--     ottoq_cert_lineage forces_recert             true
--     ottoq_cert_recert_floor()   2026-09-07 21:36:53.363037+00
--
-- Both probe halves passed on all nine round-22 pairs: every pair arm-equal
-- under the new hash, every pair moved off its old h_rule.
--
-- ottoq_determinism_pair is unchanged — it calls this function by name and
-- picks up the new body without a rewrite.
--
-- ROUND 23 SCHEDULED at the new floor: jobs 443-451, r23_c1..c9,
-- 21:45-23:48 UTC (4:45-6:48 PM CT), last pair landing ~00:13 UTC.
-- Same nine columns as rounds 21 and 22.
-- ---------------------------------------------------------------------------
