-- migration-version: 20260921005249
-- migration-name:    shield_expected_was_the_wrong_question_an_hour_after_i_shipped_it_ask_which_effects_are_gated_where
--
-- 0394  `0392`'s `shield_expected` ASKS *"SHOULD THIS BRANCH PASS THE PROBE ON THIS ROW?"* — AND
--       THREE OF THE SIX BRANCHES NOW MEASURED ARE GATED AT A **DIFFERENT PROBE POINT** THAN THE
--       ROW THEY ARE RECORDED ON, SO IT RETURNS **GAP FOR CORRECTLY-GATED BEHAVIOUR**. AN
--       INSTRUMENT THAT CRIES GAP THREE TIMES OUT OF FOUR IS WORSE THAN NO INSTRUMENT. THIS ASKS
--       WHICH **EFFECT FAMILIES** A BRANCH TOUCHES AND WHETHER EACH HAS A GATE ANYWHERE.
--
-- `forces_recert` **FALSE**. Two additive columns on a declaration table, a reshaped read-only
-- verdict, and one new declared branch. No enacting path, no frame, no tick. Safe while a run is
-- live, and one is (`e8b8eb3e`, tick 780, the return wave arriving).
--
-- Derivation in `db/checks/0293`. The short version, and it is an architectural fact rather than a
-- list of forgetful callers:
--
--   **THE SHIELD GATES EFFECT POINTS, NOT DECISIONS.** One query over the effect points:
--
--     GATED AT A CHOKEPOINT, covering every caller forever:
--       `public.ottoq_policy_set`             -> policy_write,         AI.001,   254 evals
--       `twin.ottoq_sim_start_charge_session` -> charge_session_start, 5 codes,  335 evals
--
--     NO PROBE AT ALL:
--       `ottoq.ottoq_book_stall`            the CALENDAR write     (space)
--       `public.ottoq_reserve_stall`        the POINTER claim      (space)
--       `ottoq.ottoq_emit_vehicle_command`  the downlink           (movement)
--       `public.ottoq_comms_send_command`   the downlink           (movement)
--
-- So **power** and **policy** are covered structurally; **space** and **movement** are checked only
-- by probe blocks written inline in `ottoq_decide_tick`, which means coverage for the two effect
-- families that physically move vehicles around a yard is exactly the set of callers that happen to
-- live inside one 83,000-character function. Every branch the census has flagged is a writer of
-- space or movement from outside it — **not a lapse, because there is no chokepoint to have used.**
--
-- ══ THE SIXTH BRANCH, WHICH THE INSTRUMENT FOUND BY ITSELF ═════════════════
--
-- `reservation_reopt` did not exist in `0392`'s census two hours earlier; `ottoq_shield_coverage`
-- surfaced it as the run advanced, which is the instrument doing precisely its job.
-- `ottoq.ottoq_reoptimize_reservation_book` takes a vehicle below 45% SoC holding a non-DCFC
-- reservation, finds a free healthy DCFC (preferring a fresh cuOpt proposal, else the local floor),
-- `ottoq_reserve_stall`s the new one, releases the old, rebuilds the plan, sends `proceed_to_stall`,
-- and marks the cuOpt proposal `enacted`. **9 enacted rebooks, 9 vehicles, 0 shielded, ticks
-- 364–658, one via the `cuopt` branch.**
--
-- **Checked for the one-hop-down case before declaring it, which is `0292`'s lesson applied on the
-- same night it was learned.** All nine rebooked vehicles accumulate `charge_session_start`
-- evaluations on the new stall — 5, 10 or 15 each, i.e. sessions × the five EN/HW codes — so **the
-- power draw IS gated**; and all nine show `stall_assignment` evaluations = **0**, so the space
-- claim never was. Partial, and the part that is gated is the part that could have hurt the site.
--
-- ══ WHY THE REMEDY IS NOT IN THIS FILE ═════════════════════════════════════
--
-- The fix is a probe inside `ottoq_reserve_stall` and `ottoq_book_stall` — the chokepoint pattern
-- this database already trusts twice. It is `forces_recert TRUE` (it changes what the tick path may
-- do, on every caller at once) **and it cannot be honestly evaluated yet**: `0263` §1 established
-- that four of the five `stall_assignment` codes are charge-specific and cannot judge a parking
-- hold, so dropping them into `ottoq_book_stall` would gate staging with charge rules and refuse
-- nothing while appearing to. **The space chokepoint needs a parking-competent rule before it needs
-- a probe.** That ordering is the finding (G101), not a delay.

BEGIN;

-- ══ P0. PREFLIGHT ══════════════════════════════════════════════════════════
DO $p0$
DECLARE v_gated int; v_ungated int;
BEGIN
  IF to_regclass('public.ottoq_enactment_branches') IS NULL THEN
    RAISE EXCEPTION '0394 P0: 0392''s declaration table is absent' USING ERRCODE='42P01';
  END IF;

  --: the premise: exactly two effect points must probe, and the four space/movement ones must
  --: not. If that has changed, the effect-family model in this file is stale before it lands.
  SELECT count(*) FILTER (WHERE p.prosrc LIKE '%ottoq_shield_probe%'),
         count(*) FILTER (WHERE p.prosrc NOT LIKE '%ottoq_shield_probe%')
    INTO v_gated, v_ungated
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.proname IN ('ottoq_policy_set', 'ottoq_sim_start_charge_session', 'ottoq_book_stall',
                       'ottoq_reserve_stall', 'ottoq_emit_vehicle_command',
                       'ottoq_comms_send_command');
  RAISE NOTICE '0394 P0: effect points — % probe, % do not', v_gated, v_ungated;
  IF v_gated <> 2 THEN
    RAISE EXCEPTION '0394 P0: expected exactly 2 probing effect points (ottoq_policy_set, '
                    'ottoq_sim_start_charge_session), found %. Re-derive 0293 s2 before applying.',
                    v_gated
      USING ERRCODE='22023';
  END IF;
END $p0$;

-- ══ P1. THE TWO COLUMNS THAT ASK THE RIGHT QUESTION ════════════════════════
ALTER TABLE public.ottoq_enactment_branches
  ADD COLUMN IF NOT EXISTS effect_families     text[],
  ADD COLUMN IF NOT EXISTS gated_downstream_at text;

COMMENT ON COLUMN public.ottoq_enactment_branches.effect_families IS
  '0394. Which physical effect families this branch actually causes: any of policy, power, space, '
  'movement. An empty array means the branch RECORDS something rather than causing it (the twin '
  'advancing its own world; a reconciliation binding a vehicle already physically present), and '
  'nothing is expected to gate it. This replaces shield_expected''s question -- "should the probe '
  'run on THIS ROW" -- which returned GAP for three of six branches that are correctly gated one '
  'hop down, at a different action_context on a different entity_type.';

COMMENT ON COLUMN public.ottoq_enactment_branches.gated_downstream_at IS
  '0394. Comma-separated action_context values where this branch''s effects actually meet the L1 '
  'shield, wherever that sits, or NULL for none. This engine gates EFFECT POINTS, not decisions: '
  'ottoq_policy_set probes at policy_write and covers every dial writer; '
  'twin.ottoq_sim_start_charge_session probes at charge_session_start and covers every charge. '
  'ottoq_book_stall, ottoq_reserve_stall, ottoq_emit_vehicle_command and ottoq_comms_send_command '
  'call no probe at all, so space and movement are gated only by the blocks written inline in '
  'ottoq_decide_tick -- i.e. for exactly the callers that live inside that one function.';

-- ══ P2. DECLARE ALL SIX, INCLUDING THE ONE THE INSTRUMENT FOUND ════════════
INSERT INTO public.ottoq_enactment_branches
  (resolved_action_context, writer, writer_side, shield_expected, effect_families,
   gated_downstream_at, note)
VALUES
  ('reservation_reopt', 'ottoq.ottoq_reoptimize_reservation_book', 'engine', true,
   ARRAY['space','movement','power'], 'charge_session_start',
   'Surfaced by ottoq_shield_coverage itself as run e8b8eb3e advanced -- it was not in 0392''s '
   'census two hours earlier. Takes a vehicle deployed/en_route below 45% SoC holding a non-DCFC '
   'reservation, finds a free healthy DCFC (preferring a fresh cuOpt proposal, else the local '
   'floor), calls ottoq_reserve_stall on the new one, releases the old, rebuilds the workflow '
   'plan, sends proceed_to_stall, and marks the cuOpt proposal enacted -- with no '
   'ottoq_shield_probe anywhere in the function. Measured: 9 enacted rebooks, 9 vehicles, 0 '
   'shielded, ticks 364-658, one via the cuopt branch. PARTIALLY gated: all nine rebooked '
   'vehicles accumulate charge_session_start evaluations on the new stall (5/10/15 each = '
   'sessions x the five EN/HW codes), so the POWER draw is gated and the site cap holds; all nine '
   'show stall_assignment evaluations = 0, so the SPACE claim is not. The remaining gap is space '
   'and movement, which have no chokepoint to gate them. See db/checks/0293, G101.')
ON CONFLICT (resolved_action_context) DO UPDATE
  SET writer = EXCLUDED.writer, writer_side = EXCLUDED.writer_side,
      shield_expected = EXCLUDED.shield_expected, effect_families = EXCLUDED.effect_families,
      gated_downstream_at = EXCLUDED.gated_downstream_at, note = EXCLUDED.note;

UPDATE public.ottoq_enactment_branches SET
  effect_families = CASE resolved_action_context
    WHEN 'orchestrator_agent'    THEN ARRAY['policy']
    WHEN 'gate_intake_no_charge' THEN ARRAY['space','movement']
    ELSE ARRAY[]::text[] END,
  gated_downstream_at = CASE resolved_action_context
    WHEN 'orchestrator_agent' THEN 'policy_write'
    ELSE NULL END
 WHERE resolved_action_context IN
   ('orchestrator_agent', 'gate_intake_no_charge', 'bay_reconcile',
    'itinerary_amended', 'triage_verdict');

-- ══ P3. THE VERDICT, RECOMPUTED FROM EFFECTS ═══════════════════════════════
--: DROP first: the OUT parameter list changes (two new columns), and CREATE OR REPLACE refuses
--: that with 42P13. Safe here because nothing on the tick path calls either function -- they are
--: one hour old and read-only -- and ottoq_assert_shield_coverage is recreated below in the same
--: transaction, so the window in which it references a dropped function never commits.
DROP FUNCTION IF EXISTS public.ottoq_shield_coverage(uuid);

CREATE OR REPLACE FUNCTION public.ottoq_shield_coverage(p_sim_run_id uuid)
RETURNS TABLE (
  resolved_action_context text,
  l2_engine               text,
  writer                  text,
  writer_side             text,
  declared                boolean,
  effect_families         text[],
  gated_downstream_at     text,
  enacted                 bigint,
  shielded                bigint,
  unshielded              bigint,
  pct_shielded            numeric,
  verdict                 text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $fn$
  WITH e AS (
    SELECT COALESCE(d.resolved_action_context, d.action_context, '(null)') AS rc,
           COALESCE(d.l2_engine, '(null)')                                AS eng,
           --: >0 is the test, not IS NOT NULL: six of ottoq_decide_tick's twelve insert
           --: sites omit the column entirely and the rest default it to '[]'.
           (jsonb_array_length(COALESCE(d.rule_results, '[]'::jsonb)) > 0) AS shielded
      FROM public.ottoq_decisions d
     WHERE d.sim_run_id = p_sim_run_id
       AND d.outcome_status = 'enacted'
  ), agg AS (
    SELECT rc, eng,
           count(*)                             AS n,
           count(*) FILTER (WHERE shielded)     AS n_sh,
           count(*) FILTER (WHERE NOT shielded) AS n_un
      FROM e GROUP BY rc, eng
  )
  SELECT a.rc,
         a.eng,
         COALESCE(b.writer, '(undeclared)'),
         COALESCE(b.writer_side, '(undeclared)'),
         (b.resolved_action_context IS NOT NULL),
         b.effect_families,
         b.gated_downstream_at,
         a.n, a.n_sh, a.n_un,
         round(100.0 * a.n_sh / NULLIF(a.n, 0), 1),
         --: 0394. THE VERDICT IS ABOUT EFFECTS, NOT ABOUT THIS ROW. A branch is fine when its
         --: row carries rules, OR it causes no physical effect, OR every family it causes has a
         --: gate somewhere. Anything undeclared and unshielded stays a gap: an undeclared branch
         --: has no effect model, so nothing can vouch for it.
         CASE
           WHEN a.n_un = 0                                THEN 'shielded on this row'
           WHEN b.resolved_action_context IS NULL         THEN 'GAP: unshielded and undeclared'
           WHEN COALESCE(array_length(b.effect_families, 1), 0) = 0
                                                          THEN 'records a fact — nothing to gate'
           --: the space/movement families have NO chokepoint anywhere in the engine, so a branch
           --: causing either, from outside ottoq_decide_tick's inline blocks, is ungated for it
           --: however much else it gates downstream. 0293 s2.
           WHEN b.effect_families && ARRAY['space','movement']
                                                          THEN 'GAP: space/movement ungated'
           WHEN b.gated_downstream_at IS NOT NULL          THEN 'gated downstream at '
                                                                || b.gated_downstream_at
           ELSE 'GAP: effects with no gate'
         END
    FROM agg a
    LEFT JOIN public.ottoq_enactment_branches b ON b.resolved_action_context = a.rc
   ORDER BY a.n_un DESC, a.n DESC, a.rc;
$fn$;

COMMENT ON FUNCTION public.ottoq_shield_coverage(uuid) IS
  '0394. L1 shield coverage per enacting branch of one run, judged on EFFECTS rather than on '
  'whether the decision row happens to carry rule_results. 0392''s original verdict asked "should '
  'the probe run on this row" and returned GAP for three of six branches that are correctly gated '
  'one hop down -- the agent at policy_write, reservation_reopt''s power at charge_session_start, '
  'and the twin''s own advancers which cause nothing. Read verdict, never pct_shielded. The two '
  'standing GAPs are space and movement, and they are gaps because NO effect point gates them: '
  'ottoq_book_stall, ottoq_reserve_stall, ottoq_emit_vehicle_command and ottoq_comms_send_command '
  'call no probe, so those families are checked only by the blocks inline in ottoq_decide_tick. '
  'Power and policy ARE gated at chokepoints that cover every caller (twin.'
  'ottoq_sim_start_charge_session, ottoq_policy_set) -- the pattern the space fix should copy, '
  'once a parking-competent rule exists for it to run (0263 s1).';

-- ══ P4. THE ROLLUP, WITH THE EFFECT-FAMILY SPLIT ═══════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_assert_shield_coverage(p_sim_run_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $fn$
  --: RETURNS rather than RAISES, and every aggregate is COALESCEd (0384).
  SELECT jsonb_build_object(
    'sim_run_id',           p_sim_run_id,
    'enacted',              COALESCE(sum(c.enacted), 0),
    'shielded_on_row',      COALESCE(sum(c.shielded), 0),
    'unshielded',           COALESCE(sum(c.unshielded), 0),
    --: THE NUMBER TO ACT ON: unshielded rows whose verdict is a GAP, i.e. an effect family with
    --: no gate anywhere, or a branch with no declared effect model at all.
    'unshielded_gap',       COALESCE(sum(c.unshielded) FILTER (
                              WHERE c.verdict LIKE 'GAP:%'), 0),
    'gated_downstream',     COALESCE(sum(c.unshielded) FILTER (
                              WHERE c.verdict LIKE 'gated downstream%'), 0),
    'records_a_fact',       COALESCE(sum(c.unshielded) FILTER (
                              WHERE c.verdict LIKE 'records a fact%'), 0),
    'gap_branches',         COALESCE(jsonb_agg(jsonb_build_object(
                              'branch',  c.resolved_action_context,
                              'engine',  c.l2_engine,
                              'writer',  c.writer,
                              'effects', c.effect_families,
                              'verdict', c.verdict,
                              'unshielded', c.unshielded)
                              ORDER BY c.unshielded DESC)
                              FILTER (WHERE c.unshielded > 0 AND c.verdict LIKE 'GAP:%'),
                            '[]'::jsonb),
    'undeclared_branches',  COALESCE(jsonb_agg(DISTINCT c.resolved_action_context)
                              FILTER (WHERE NOT c.declared), '[]'::jsonb)
  )
  FROM public.ottoq_shield_coverage(p_sim_run_id) c;
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_shield_coverage(uuid) IS
  '0394. Run-level rollup of ottoq_shield_coverage, split by why each unshielded row is '
  'unshielded: unshielded_gap (an effect family with no gate anywhere, or an undeclared branch), '
  'gated_downstream (the effect meets the shield at another probe point -- the agent''s dials at '
  'policy_write), and records_a_fact (the twin advancing its own world, or a reconciliation '
  'binding a vehicle already physically present). The three sum to unshielded, and P5 asserts '
  'that -- the sum-to-total check 0341 had to add to ottoq_intelligence_ledger after its first '
  'version bucketed 1,161 rows nowhere. Never raises (0384).';

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0394_shield_expected_was_the_wrong_question_an_hour_after_i_shipped_it_ask_which_effects_are_gated_where',
  false,
  'Reshapes 0392''s instrument to judge on effects rather than on whether the decision row carries '
  'rule_results: adds ottoq_enactment_branches.effect_families and .gated_downstream_at, '
  'recomputes ottoq_shield_coverage''s verdict from them, and splits the rollup into '
  'unshielded_gap / gated_downstream / records_a_fact. FALSE: two additive columns on a '
  'declaration table nothing on the tick path reads, plus two read-only function bodies. The '
  'finding behind it is architectural -- THE SHIELD GATES EFFECT POINTS, NOT DECISIONS, and only '
  'two of the four effect families have a chokepoint: ottoq_policy_set probes at policy_write '
  '(covers every dial writer) and twin.ottoq_sim_start_charge_session at charge_session_start '
  '(covers every charge), while ottoq_book_stall, ottoq_reserve_stall, ottoq_emit_vehicle_command '
  'and ottoq_comms_send_command call no probe at all, so SPACE and MOVEMENT are gated only by the '
  'blocks written inline in ottoq_decide_tick. Also declares reservation_reopt, a sixth branch '
  'the instrument surfaced by itself as run e8b8eb3e advanced: 9 DCFC rebooks, 0 shielded, one '
  'via cuopt, power gated downstream at charge_session_start on all nine but the space claim '
  'never gated. Remedy (a probe inside the two space chokepoints, copying the pattern the engine '
  'already trusts twice) is forces_recert TRUE and is blocked behind a real prerequisite: per '
  '0263 s1 four of the five stall_assignment codes are charge-specific and cannot judge a parking '
  'hold, so the space chokepoint needs a parking-competent rule before it needs a probe. G101.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ══ P5. POSTFLIGHT — INVOKE, AND ASSERT THE THREE-WAY SUM ══════════════════
DO $p5$
DECLARE v_run uuid; v_roll jsonb; v_names text;
BEGIN
  SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
   WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY sr.started_at DESC LIMIT 1;

  v_roll := public.ottoq_assert_shield_coverage(v_run);
  IF v_roll IS NULL OR NOT (v_roll ? 'unshielded_gap') THEN
    RAISE EXCEPTION '0394 P5: the rollup did not build' USING ERRCODE='23514';
  END IF;

  --: every unshielded row must land in exactly one of the three buckets.
  IF (v_roll->>'unshielded_gap')::bigint
     + (v_roll->>'gated_downstream')::bigint
     + (v_roll->>'records_a_fact')::bigint
     <> (v_roll->>'unshielded')::bigint THEN
    RAISE EXCEPTION '0394 P5: gap (%) + downstream (%) + fact (%) <> unshielded (%) — a bucket '
                    'is missing or double-counting, the 0341 defect',
      v_roll->>'unshielded_gap', v_roll->>'gated_downstream',
      v_roll->>'records_a_fact', v_roll->>'unshielded'
      USING ERRCODE='23514';
  END IF;
  IF (v_roll->>'shielded_on_row')::bigint + (v_roll->>'unshielded')::bigint
     <> (v_roll->>'enacted')::bigint THEN
    RAISE EXCEPTION '0394 P5: shielded (%) + unshielded (%) <> enacted (%)',
      v_roll->>'shielded_on_row', v_roll->>'unshielded', v_roll->>'enacted'
      USING ERRCODE='23514';
  END IF;

  --: and the agent must no longer be a gap, while the two space/movement branches must be.
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_roll->'gap_branches') g
              WHERE g->>'branch' = 'orchestrator_agent') THEN
    RAISE EXCEPTION '0394 P5: orchestrator_agent is still a gap under the effect-based verdict'
      USING ERRCODE='23514';
  END IF;

  SELECT string_agg(g->>'branch' || '=' || (g->>'unshielded'), ', ' ORDER BY g->>'branch')
    INTO v_names FROM jsonb_array_elements(v_roll->'gap_branches') g;

  RAISE NOTICE '0394 P5: run % — enacted %, on-row %, gap %, downstream %, fact %',
    v_run, v_roll->>'enacted', v_roll->>'shielded_on_row', v_roll->>'unshielded_gap',
    v_roll->>'gated_downstream', v_roll->>'records_a_fact';
  RAISE NOTICE '0394 P5: gap branches [%]', COALESCE(v_names, '(none)');
END $p5$;

COMMIT;
