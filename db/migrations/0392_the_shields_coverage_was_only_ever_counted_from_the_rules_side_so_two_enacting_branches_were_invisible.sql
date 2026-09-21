-- migration-version: 20260921002608
-- migration-name:    the_shields_coverage_was_only_ever_counted_from_the_rules_side_so_two_enacting_branches_were_invisible
--
-- 0392  EVERY COVERAGE NUMBER THIS REPO HAS EVER PUBLISHED ABOUT THE L1 SHIELD WAS COUNTED FROM
--       THE RULES' SIDE. COUNTED FROM THE ACTIONS' SIDE, **119 OF 859 ENACTED DECISIONS ON THE
--       LIVE RUN CARRY NO RULE EVALUATION AT ALL** — AND NO RULE-SIDE COUNT CAN SEE THAT.
--
-- `forces_recert` **FALSE**. This adds a declaration table and two read-only routines. It
-- changes no enacting path, no frame, no tick. Safe while a run is live, and one is
-- (`e8b8eb3e`). The remedy — routing the two branches that need it through the probe — is a
-- separate, `forces_recert TRUE` migration that waits for the run to finish, exactly as `0391`
-- was split from the SM.005 trigger for the same reason.
--
-- ══ 1. THE BLIND SPOT, AND WHY IT SURVIVED SIX RE-DERIVATIONS ══════════════
--
-- `0192`, then `0273`, then CLAUDE.md 2.5 all answer the same question: *of the declared rule
-- codes, how many are evaluated?* The answer moved from "20 of 29 at four probe points" to
-- "21 of 30 at six", and `0263` §1 sharpened it further to an optimistic bound. Every one of
-- those is a count **over `ottoq_rules`**, joined to `ottoq_rule_evaluations`.
--
-- **A rule-side count is structurally incapable of finding an enactment that consulted no rule.**
-- If a branch never calls `ottoq_shield_probe`, it contributes zero evaluations, so it changes
-- no numerator and no denominator on that side — it is not a low score, it is absent from the
-- exam. G44 has been open for eight days describing the nine rules with no caller; nothing has
-- described the actions with no rules.
--
-- **Measured on run `e8b8eb3e` (busy_day, seed 100020, twin depot, ~tick 160):**
--
--   enacted decisions                                  **859**
--   carrying >= 1 rule evaluation                       740   **86.1%**
--   carrying NONE                                      **119**
--     of those, written by the twin's own advancers       51
--     of those, written on the engine side              **68**
--
-- **And the instrument re-derives, so these are a MOMENT and not a total** — CLAUDE.md Part 3's
-- standing instruction, applied to my own figures. P4 ran six minutes later on the same
-- still-running run and read **1,011 enacted / 841 shielded / 170 unshielded / gap 82** (the
-- agent branch alone had gone 48 -> 70). Quote `ottoq_assert_shield_coverage(run)`, never this
-- header.
--
-- ══ 2. THE FIVE BRANCHES, EACH TRACED TO ITS WRITER ════════════════════════
--
-- `resolved_action_context` separates them cleanly, and every writer is named by one query
-- (`prosrc` matching both the context string and an INSERT into `ottoq_decisions`):
--
--   orchestrator_agent      nemotron          48   **no database writer at all**
--   itinerary_amended       deterministic_v1  30   twin.ottoq_sim_advance_flow_contract
--   triage_verdict          deterministic_v1  16   twin.ottoq_sim_advance_visit_atoms
--   gate_intake_no_charge   deterministic_v1  12   public.ottoq_decide_tick
--   bay_reconcile           deterministic_v1   5   ottoq.ottoq_bind_unbooked_bay_occupants
--
-- **`orchestrator_agent` matching no `prosrc` is the finding, not a failed query.** The agent
-- layer writes `ottoq_decisions` from outside the database — an edge function against the REST
-- API — which is why it is the one branch no in-database search can attribute. This is G62's
-- `agent_calls_with_no_l1_rules = 1,120 of 1,120` reproduced on a fresh run under a different
-- seed, and now localised to a single `resolved_action_context`.
--
-- **And `l2_engine` cannot be used to find these**, which is worth stating because it is the
-- obvious next instinct. `trg_ottoq_stamp_l2_engine` sets
-- `COALESCE(NULLIF(enacted_action->>'source',''), l2_engine, 'deterministic_v1')`, and on all
-- 42 of the unshielded `task_start` rows measured, `enacted_action->>'source'` is NULL. So their
-- `deterministic_v1` label is the trigger's **fallback**, not an engine declaring itself:
-- "deterministic_v1 did it" and "nobody stamped it" are indistinguishable in that column. Same
-- defect shape as `0289` — a field read outside the domain it is defined on.
--
-- **AND AN INDEPENDENT CONFIRMATION OF `0391`, FOUND WHILE TRACING THIS.** `ottoq_shield_probe`'s
-- full signature ends `..., p_triggered_by_event_id uuid, p_override_id uuid` — the shield has a
-- parameter for a human override, and it is how a real one would reach a decision row.
-- `ottoq_shield_and_log` calls the probe with **six** arguments and never passes an override id,
-- while setting `overridden := true` and `outcome_status := 'overridden_to_default'` whenever
-- `would_block` fires. So `overridden` true with `override_id` NULL is not an accident of the
-- data, it is what the writer's source does on every blocked action — which is exactly the
-- premise `0391` argued from 12,082 rows an hour ago, now readable off the function body.
--
-- ══ 3. ONLY TWO OF THE FIVE ARE A GAP, AND SAYING SO IS THE POINT ══════════
--
-- "86.1% shielded" is a worse headline than the truth, because three of the five branches
-- **should not** be shielded and a number that lumps them in invites the fix to be applied
-- where it does harm:
--
--   - `itinerary_amended` and `triage_verdict` are the **twin's** advancers. They record the
--     world progressing, not OTTO-Q choosing. A shield placed there would be asking the rules
--     for permission for something the simulated world already did.
--   - `bay_reconcile` binds a vehicle **already physically in a bay** to a booking that was
--     missing. That is the `space_conflict_ledger` posture CLAUDE.md rule 6 requires — physical
--     reality overruling the calendar — and gating it would mean refusing to write down a fact.
--
--   - **`gate_intake_no_charge` IS a gap.** Read end to end in `ottoq_decide_tick`'s
--     `(3b) GATE INTAKE — NO-CHARGE ARRIVALS` loop: it calls `ottoq.ottoq_book_stall` for a
--     staging stall, stamps `to_stall_id` on the itinerary leg, writes `'enacted'`, and calls
--     `ottoq_emit_vehicle_command(..., 'proceed_to_stall', ...)`. **A vehicle is claimed a stall
--     and commanded to drive to it, and the loop contains no `ottoq_shield_probe` anywhere
--     between its `FOR` and its `END LOOP`.** `0263` §1 got within one step of this — it found
--     that four of the five codes at `stall_assignment` are charge-specific and cannot judge a
--     parking hold — without noticing a parking branch that skips the probe entirely.
--   - **`orchestrator_agent` IS a gap**, and the worse one: it is the only path on which an AI
--     changes engine state, and it is the only path with no L1 evaluation.
--
-- **So the honest sentence is "60 of 859 enacted decisions, on two branches, both of which take
-- a physical action, carry no rule evaluation"** — not 119, and not 86%.
--
-- ══ 4. WHY A DECLARATION TABLE RATHER THAN A HARDCODED LIST ════════════════
--
-- The classification above is a judgement per branch, and a judgement hardcoded inside a
-- function is a judgement nobody can audit or extend. Three precedents in this database do it
-- as declared data instead, and the newest one was praised for it eight hours ago:
-- `ottoq_kpi_touch_actor_types` declares which actors are human (and `0391` leaned on its
-- `unknown` row's own warning); `ottoq_proposer_precedence` declares rank and `holds_tick`;
-- `ottoq_rules` declares the rules themselves. `ottoq_enactment_branches` is the same shape for
-- the decide/audit seam.
--
-- It also repairs a real deficiency: **`ottoq_decisions` does not record which function wrote
-- it.** Twelve insert sites live in `ottoq_decide_tick` alone, across eight database functions
-- plus one edge function, and `resolved_action_context` — free text each site sets by hand — is
-- the only proxy. Declaring the vocabulary is the cheapest thing that makes a new unshielded
-- branch announce itself instead of blending in, which is exactly what
-- `ottoq_assert_service_vocabulary()` does for services (`0383`).
--
-- **The predicate that matters is the INTERSECTION**: unshielded AND expected to be shielded.
-- A branch that is shielded needs no declaration to be safe, so an undeclared shielded branch
-- is not a finding; an undeclared UNSHIELDED one is, and the assert names it.
--
-- No run-scope registration is required or wanted: the table carries no run key, and its four
-- siblings (`ottoq_kpi_touch_actor_types`, `ottoq_proposer_precedence`, `ottoq_rules`,
-- `ottoq_cert_columns`) are likewise absent from `ottoq_run_scope_registry`. Check (a) of
-- `ottoq_check_run_scope_registry` warns on an unregistered **run-scoped** column; there is none
-- here.

BEGIN;

-- ══ P0. PREFLIGHT ══════════════════════════════════════════════════════════
DO $p0$
DECLARE v_sites int; v_probe_exists boolean;
BEGIN
  --: the whole file rests on rule_results being the record of an L1 evaluation, and on
  --: ottoq_shield_probe being what fills it. Assert both exist before reasoning from them.
  SELECT to_regprocedure('public.ottoq_shield_probe(text,text,uuid,jsonb,uuid,uuid,uuid,uuid)')
           IS NOT NULL
    INTO v_probe_exists;
  IF NOT v_probe_exists THEN
    RAISE EXCEPTION '0392 P0: ottoq_shield_probe(text,text,uuid,jsonb,uuid,uuid,uuid,uuid) is '
                    'absent; re-derive which routine fills rule_results before applying'
      USING ERRCODE='42883';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='ottoq_decisions'
                    AND column_name='rule_results') THEN
    RAISE EXCEPTION '0392 P0: ottoq_decisions.rule_results is absent' USING ERRCODE='42703';
  END IF;

  --: and the premise of s2: resolved_action_context must actually be populated, or the
  --: instrument groups everything into one bucket and reports nothing.
  SELECT count(DISTINCT resolved_action_context) INTO v_sites
    FROM public.ottoq_decisions WHERE outcome_status = 'enacted';
  RAISE NOTICE '0392 P0: % distinct resolved_action_context values across enacted decisions', v_sites;
  IF v_sites < 2 THEN
    RAISE EXCEPTION '0392 P0: resolved_action_context is not discriminating (% distinct values); '
                    'the coverage instrument would report one undifferentiated bucket', v_sites
      USING ERRCODE='22023';
  END IF;
END $p0$;

-- ══ P1. THE DECLARED SEAM VOCABULARY ═══════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.ottoq_enactment_branches (
  resolved_action_context text PRIMARY KEY,
  writer                  text    NOT NULL,
  writer_side             text    NOT NULL
                            CHECK (writer_side IN ('engine', 'twin', 'external')),
  shield_expected         boolean NOT NULL,
  note                    text,
  declared_at             timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_enactment_branches IS
  '0392. The declared vocabulary of the decide/audit seam: one row per '
  'ottoq_decisions.resolved_action_context that enacts, naming the routine that writes it, '
  'which side of the sim boundary that routine is on, and whether an L1 evaluation is EXPECTED '
  'on it. Declared rather than hardcoded for the same reason ottoq_kpi_touch_actor_types '
  'declares which actors are human: the judgement per branch is the part a reader must be able '
  'to audit and extend. ottoq_decisions does not record its writer -- twelve insert sites live '
  'in ottoq_decide_tick alone -- so resolved_action_context is the only available proxy and '
  'this table is what stops it being free text.';

COMMENT ON COLUMN public.ottoq_enactment_branches.shield_expected IS
  'TRUE when this branch chooses an action and should therefore pass ottoq_shield_probe. FALSE '
  'when it RECORDS something that already happened -- the twin advancing its own world, or a '
  'reconciliation binding a vehicle already physically present. Gating the latter would mean '
  'asking the rules for permission for a fact.';

INSERT INTO public.ottoq_enactment_branches
  (resolved_action_context, writer, writer_side, shield_expected, note)
VALUES
  ('orchestrator_agent', '(edge function, no database writer)', 'external', true,
   'The agent layer. Writes ottoq_decisions over the REST API, which is why no prosrc search '
   'attributes it. The one path on which an AI changes engine state and the one path the L1 '
   'shield does not gate -- G62''s agent_calls_with_no_l1_rules = 1,120 of 1,120, reproduced '
   'on run e8b8eb3e as 48 of 48 under a different seed. Remedy: route it through '
   'ottoq_shield_and_log, which already takes an arbitrary action array, already fills '
   'rule_results/overridden/safe_default_taken, and whose enacted_action passthrough preserves '
   'the source stamp so the row still reads l2_engine=nemotron.'),
  ('gate_intake_no_charge', 'public.ottoq_decide_tick', 'engine', true,
   'ottoq_decide_tick''s (3b) GATE INTAKE -- NO-CHARGE ARRIVALS loop. Calls ottoq_book_stall for '
   'a staging stall, stamps to_stall_id on the itinerary leg, writes enacted, and emits '
   'proceed_to_stall -- a stall claimed and a vehicle commanded to drive to it, with no '
   'ottoq_shield_probe anywhere between the loop''s FOR and its END LOOP. 0263 s1 came within '
   'one step of this by finding that four of the five codes at stall_assignment are '
   'charge-specific and cannot judge a parking hold.'),
  ('bay_reconcile', 'ottoq.ottoq_bind_unbooked_bay_occupants', 'engine', false,
   'Binds a vehicle ALREADY physically in a bay to a booking that was missing. This is the '
   'space_conflict_ledger posture CLAUDE.md rule 6 requires -- physical reality overruling the '
   'calendar -- so shielding it would mean refusing to write down a fact.'),
  ('itinerary_amended', 'twin.ottoq_sim_advance_flow_contract', 'twin', false,
   'The twin advancing its own world. Records progression, does not choose an action.'),
  ('triage_verdict', 'twin.ottoq_sim_advance_visit_atoms', 'twin', false,
   'The twin advancing its own world. Records progression, does not choose an action.')
ON CONFLICT (resolved_action_context) DO UPDATE
  SET writer          = EXCLUDED.writer,
      writer_side     = EXCLUDED.writer_side,
      shield_expected = EXCLUDED.shield_expected,
      note            = EXCLUDED.note;

-- ══ P2. THE ACTION-SIDE COVERAGE INSTRUMENT ════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_shield_coverage(p_sim_run_id uuid)
RETURNS TABLE (
  resolved_action_context text,
  l2_engine               text,
  writer                  text,
  writer_side             text,
  declared                boolean,
  shield_expected         boolean,
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
           count(*)                                AS n,
           count(*) FILTER (WHERE shielded)        AS n_sh,
           count(*) FILTER (WHERE NOT shielded)    AS n_un
      FROM e GROUP BY rc, eng
  )
  SELECT a.rc,
         a.eng,
         COALESCE(b.writer, '(undeclared)'),
         COALESCE(b.writer_side, '(undeclared)'),
         (b.resolved_action_context IS NOT NULL),
         b.shield_expected,
         a.n, a.n_sh, a.n_un,
         round(100.0 * a.n_sh / NULLIF(a.n, 0), 1),
         --: the verdict is the intersection, not the raw percentage. A shielded branch is
         --: safe whether or not anyone declared it; an UNSHIELDED undeclared one is the find.
         CASE
           WHEN a.n_un = 0                                   THEN 'shielded'
           WHEN b.resolved_action_context IS NULL            THEN 'GAP: unshielded and undeclared'
           WHEN b.shield_expected                            THEN 'GAP: unshielded, shield expected'
           ELSE 'unshielded by declaration'
         END
    FROM agg a
    LEFT JOIN public.ottoq_enactment_branches b ON b.resolved_action_context = a.rc
   ORDER BY a.n_un DESC, a.n DESC, a.rc;
$fn$;

COMMENT ON FUNCTION public.ottoq_shield_coverage(uuid) IS
  '0392. L1 shield coverage counted from the ACTIONS'' side: per enacting branch of one run, how '
  'many enacted decisions carry at least one rule evaluation. Every coverage figure before this '
  '(0192, 0273, CLAUDE.md 2.5) counted from the RULES'' side, joining ottoq_rules to '
  'ottoq_rule_evaluations -- which is structurally incapable of finding an enactment that '
  'consulted no rule, because such a branch contributes to neither numerator nor denominator. '
  'Read the verdict column, not pct_shielded: three of the five branches measured on '
  'run e8b8eb3e should NOT be shielded (the twin advancing its own world; a reconciliation '
  'binding a vehicle already physically present), and a headline that lumps them in invites the '
  'fix to be applied where it does harm.';

-- ══ P3. THE ASSERT — FAILS OPEN, RETURNS THE INTERSECTION ══════════════════
CREATE OR REPLACE FUNCTION public.ottoq_assert_shield_coverage(p_sim_run_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $fn$
  --: RETURNS rather than RAISES, and every aggregate is COALESCEd. 0384's lesson: a detector
  --: that raises on the data it exists to find is a detector nobody can run in a postflight.
  SELECT jsonb_build_object(
    'sim_run_id',            p_sim_run_id,
    'enacted',               COALESCE(sum(c.enacted), 0),
    'shielded',              COALESCE(sum(c.shielded), 0),
    'unshielded',            COALESCE(sum(c.unshielded), 0),
    'pct_shielded',          round(100.0 * COALESCE(sum(c.shielded), 0)
                                   / NULLIF(COALESCE(sum(c.enacted), 0), 0), 1),
    --: THE NUMBER THAT MATTERS. Unshielded AND (expected to be shielded OR undeclared).
    'unshielded_gap',        COALESCE(sum(c.unshielded) FILTER (
                               WHERE NOT c.declared OR c.shield_expected), 0),
    'unshielded_by_design',  COALESCE(sum(c.unshielded) FILTER (
                               WHERE c.declared AND NOT c.shield_expected), 0),
    'gap_branches',          COALESCE(jsonb_agg(jsonb_build_object(
                               'branch', c.resolved_action_context,
                               'engine', c.l2_engine,
                               'writer', c.writer,
                               'unshielded', c.unshielded)
                               ORDER BY c.unshielded DESC)
                               FILTER (WHERE c.unshielded > 0
                                         AND (NOT c.declared OR c.shield_expected)),
                             '[]'::jsonb),
    'undeclared_branches',   COALESCE(jsonb_agg(DISTINCT c.resolved_action_context)
                               FILTER (WHERE NOT c.declared), '[]'::jsonb)
  )
  FROM public.ottoq_shield_coverage(p_sim_run_id) c;
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_shield_coverage(uuid) IS
  '0392. Run-level rollup of ottoq_shield_coverage. Returns jsonb and never raises (0384). '
  'unshielded_gap is the number to act on: enacted decisions with no rule evaluation on a '
  'branch that is either declared shield_expected or not declared at all. '
  'unshielded_by_design is the remainder -- branches declared as recording a fact rather than '
  'choosing an action -- and it is not a defect. On run e8b8eb3e at ~tick 160 the gap was 60 '
  '(48 orchestrator_agent + 12 gate_intake_no_charge) of 859 enacted, against 51 by design.';

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0392_the_shields_coverage_was_only_ever_counted_from_the_rules_side_so_two_enacting_branches_were_invisible',
  false,
  'Adds public.ottoq_enactment_branches (a declared vocabulary for ottoq_decisions.'
  'resolved_action_context, naming each enacting branch''s writer, side of the sim boundary, '
  'and whether an L1 evaluation is expected on it), plus read-only '
  'ottoq_shield_coverage(uuid) and ottoq_assert_shield_coverage(uuid). FALSE: no enacting path, '
  'frame, tick or booking changes -- these are new objects nothing yet calls, so no canon '
  'column''s inputs move. The finding they exist to make visible: every shield-coverage figure '
  'this repo has published (0192, 0273, CLAUDE.md 2.5) was counted from the RULES'' side, which '
  'cannot detect an enactment that consulted no rule. Counted from the ACTIONS'' side on run '
  'e8b8eb3e, 119 of 859 enacted decisions carry no rule evaluation, of which 60 on two branches '
  '-- orchestrator_agent (the agent layer, writing over REST from an edge function) and '
  'gate_intake_no_charge (which books a staging stall and emits proceed_to_stall with no probe '
  'in the loop) -- are a real gap, and 59 are the twin advancing its own world or a '
  'reconciliation binding a vehicle already physically present, which should not be shielded. '
  'The remedy is a separate forces_recert TRUE migration that waits for the live run to finish.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ══ P4. POSTFLIGHT — INVOKE BOTH, DO NOT STRING-MATCH ══════════════════════
DO $p4$
DECLARE v_run uuid; v_roll jsonb; v_rows int;
BEGIN
  SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
   WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY sr.started_at DESC LIMIT 1;

  --: 0381 shipped a body that raised 42703 while three source assertions passed, because
  --: plpgsql resolves columns at execution time. Invoke.
  SELECT count(*) INTO v_rows FROM public.ottoq_shield_coverage(v_run);
  v_roll := public.ottoq_assert_shield_coverage(v_run);

  IF v_roll IS NULL OR NOT (v_roll ? 'unshielded_gap') THEN
    RAISE EXCEPTION '0392 P4: the rollup did not build' USING ERRCODE='23514';
  END IF;

  --: the identity that must hold, or the two FILTERed sums are double-counting or dropping:
  --: gap + by_design = unshielded, exactly. This is the sum-to-total check 0341 had to add
  --: to ottoq_intelligence_ledger after its first version bucketed 1,161 rows nowhere.
  IF (v_roll->>'unshielded_gap')::bigint + (v_roll->>'unshielded_by_design')::bigint
     <> (v_roll->>'unshielded')::bigint THEN
    RAISE EXCEPTION '0392 P4: gap (%) + by_design (%) <> unshielded (%)',
      v_roll->>'unshielded_gap', v_roll->>'unshielded_by_design', v_roll->>'unshielded'
      USING ERRCODE='23514';
  END IF;
  IF (v_roll->>'shielded')::bigint + (v_roll->>'unshielded')::bigint
     <> (v_roll->>'enacted')::bigint THEN
    RAISE EXCEPTION '0392 P4: shielded (%) + unshielded (%) <> enacted (%)',
      v_roll->>'shielded', v_roll->>'unshielded', v_roll->>'enacted'
      USING ERRCODE='23514';
  END IF;

  RAISE NOTICE '0392 P4: run % — % branches; enacted %, shielded % (%%%), gap %, by design %',
    v_run, v_rows, v_roll->>'enacted', v_roll->>'shielded', v_roll->>'pct_shielded',
    v_roll->>'unshielded_gap', v_roll->>'unshielded_by_design';
  RAISE NOTICE '0392 P4: gap branches %', v_roll->'gap_branches';
END $p4$;

COMMIT;
