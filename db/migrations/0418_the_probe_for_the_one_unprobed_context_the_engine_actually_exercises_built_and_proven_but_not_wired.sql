-- migration-version: PENDING
-- migration-name:    the_probe_for_the_one_unprobed_context_the_engine_actually_exercises_built_and_proven_but_not_wired
--
-- 0418  **`task_completion` is declared by five rules and probed by nothing, and it is the ONLY one of
--       `0326`'s 22 unprobed contexts that the engine actually exercises. This builds its probe, proves
--       its verdicts on live atoms, and deliberately does NOT wire it into the tick.**
--
--       `0326` §6(c) established the test that separates a harmless declaration gap from a real one: not
--       the count, but whether the engine performs the action. The engine completes atoms constantly.
--       G121 — three fast chargers held by vehicles that are in bays — is the bill for this probe's
--       absence, and `HW.006` is the rule that names that defect and prescribes its repair.
--
--       `forces_recert` **FALSE**, and §4 is emphatic about why that is only true because it is not wired.
--
-- ══ §1 WHAT THE PROBE HAS TO DO THAT `ottoq_shield_probe` CANNOT DO ALONE ══════
--
-- `ottoq_shield_probe('task_completion', …)` already selects the right five codes — `HW.003`
-- sensor_liveness, `HW.006` physical_presence_verification, `SLA.003` max_visit_duration, `SM.002`
-- task_transition_validity, `TW.002` overnight_staging. **What it cannot do is find the stall.** HW.006
-- reads `p_context->>'stall_id'`, and the completing atom is a jsonb element inside
-- `ottoq_visit_needs.atoms` that carries no stall at all.
--
-- The linkage exists and is exact: **`ottoq_stall_bookings.need_atom` records which atom a booking
-- serves.** `0383` established that parking holds carry `need_atom IS NULL` while service bookings name
-- their atom, so resolving `need_atom = svc` for the vehicle gives the stall the work was booked on, and
-- gives nothing when the work was not booked on a stall at all.
--
-- ══ §2 THE DESIGN DECISION THAT MATTERS, AND I CHANGED MY MIND ON IT ══════════
--
-- `0326` §7(b) measured the naive wiring: of the ten atoms in progress, **2 would FAIL HW.006 and 8 would
-- pass on "insufficient context for presence verification"** — because `cabin` and `exterior` atoms are
-- performed at the vehicle with no stall (`0383`: `lane_stalls=NULL`). I concluded there that the probe
-- *"must be scoped to atoms that genuinely occupy a stall."*
--
-- **Building it, that is the wrong fix, and the reason is worth recording.** Suppressing the probe when
-- there is no stall would also suppress `HW.003`, `SLA.003`, `SM.002` and `TW.002`, **none of which need a
-- stall** — and `HW.003` sensor liveness after completion is one of the gaps `0326` §6(b) identified as
-- real (*"the engine checks sensor liveness before work begins and never after it ends"*). Scoping the
-- probe to fix HW.006's vacuity would throw away four working checks to spare one rule an honest
-- abstention.
--
-- **And the vacuous pass is HW.006's OWN declared behaviour, not an accident of wiring.** Its evaluator
-- returns, in its own source, `TRUE` with reason `'insufficient context for presence verification'` and
-- `severity='warning'`. Changing that is changing the rule, which is a separate decision with its own
-- 2.9a round.
--
-- **So the discipline goes in the ACCOUNTING, not in the probe.** Probe always; count the abstentions
-- separately and never as protection. That is what `ottoq_assert_task_completion_coverage()` is for, and
-- it is the same lesson as `0326` §6(c) one level down: the fix for a misleading number is a second
-- number, not a suppressed measurement.
--
-- ══ §3 WHAT IT SAYS ON LIVE ATOMS — PROVEN, NOT PREDICTED ═════════════════════
--
-- V4 below runs the probe against every atom currently in progress on the live run and prints the verdict
-- table. Measured while writing this migration (2026-09-22 ~07:4x UTC, 02:4x CT), rolled back:
--
--     the probe resolves a stall for the atoms that have one, returns no stall for `cabin`/`exterior`,
--     and HW.006 splits cleanly into real verdicts and honest abstentions rather than one vacuous pass.
--
-- The numbers themselves are deliberately NOT written into this header as a claim to quote: they are one
-- instant of one run, and V4 re-derives them on every apply. **Read V4's NOTICE, not this paragraph** —
-- the `0417` lesson about a header number that moved between measurement and apply.
--
-- ══ §4 NOT WIRED, AND `forces_recert` IS FALSE ONLY BECAUSE OF THAT ═══════════
--
-- Wiring this probe into `twin.ottoq_sim_advance_visit_atoms` is a **one-line `PERFORM` inside the branch
-- that already sets an atom to `done`**, and that very function already establishes the pattern — it
-- wraps `ottoq_wear_mark_serviced` in its own `BEGIN/EXCEPTION` with the comment *"a ledger failure must
-- never unwind the atom close."* The probe cannot wedge the engine either way: **`ottoq_shield_probe`
-- does not block.** It returns a `would_block` column and leaves enforcement entirely to its caller
-- (`0326` §6).
--
-- **I am not wiring it tonight, and the reason is `forces_recert`, not risk.** `rules` is one of the
-- fourteen byte-identical determinism atoms (CLAUDE.md 2.9a). A probe at atom completion writes new rows
-- to `ottoq_rule_evaluations` on every run, so the `rules` atom's content changes and **every existing
-- canon is invalidated — `forces_recert` would be TRUE and the canon matrix's streaks would reset.**
-- That is a supported, ordinary classification, but resetting the reproducibility apparatus is Chase's
-- call to make awake, not a thing to do to him at 02:4x CT on a night's momentum. Determinism itself is
-- unaffected — both arms of a pair run the same code and write the same evaluations.
--
-- So this migration lands the part where the judgment lives (the stall resolution, the accounting split,
-- the proof on live data) and leaves a single reviewable line. **Nothing in the engine calls either
-- function created here**, which V5 asserts, and that is exactly why FALSE is earned.
--
-- ══ §5 WHAT THIS DOES NOT DO ══════════════════════════════════════════════════
--
-- It does not fix G121. A probe reports; it does not reconcile. `0326` §7(a) records why widening the
-- sweeper is the wrong repair (the exclusion is deliberate, written twice, and hard-freeing a `dcfc`
-- pointer from a sweep could race the charge-session path that owns that column). The narrow fix — clear
-- the charger pointer where the vehicle enters a bay — belongs with whoever owns that transition.
--
-- It also does not touch the other 21 unprobed contexts. Per `0326` §6(c) they are mostly actions this
-- engine never performs, and an unprobed context for an action nobody takes costs nothing.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n int;
BEGIN
  -- P1. The five codes are still declared against task_completion. If the declaration changed, this
  --     probe is aimed at nothing.
  SELECT count(DISTINCT rule_code) INTO v_n FROM public.ottoq_rules
   WHERE status='active' AND 'task_completion' = ANY(applies_to_actions);
  IF v_n < 5 THEN
    RAISE EXCEPTION '0418 P1: only % active codes declare task_completion, expected at least 5 -- '
                    're-derive 0326 §6(b) before building its probe', v_n;
  END IF;

  -- P2. STILL UNPROBED. If something else wired it while this was being written, this migration would be
  --     adding a second probe rather than the first, and the accounting below would double-count.
  SELECT count(*) INTO v_n FROM public.ottoq_rule_evaluations WHERE action_context='task_completion';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0418 P2: task_completion already has % evaluations -- something probes it now; '
                    'reconcile before adding another', v_n;
  END IF;

  -- P3. The linkage this probe depends on. `need_atom` must exist and be populated for service bookings,
  --     or the stall resolution in §1 silently returns nothing for everything and HW.006 abstains always.
  SELECT count(*) INTO v_n FROM public.ottoq_stall_bookings WHERE need_atom IS NOT NULL;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0418 P3: no booking anywhere carries a need_atom, so the atom-to-stall linkage of '
                    '§1 does not exist -- the probe could only ever abstain';
  END IF;

  -- P4. HW.006's evaluator still abstains rather than failing on missing context. §2's whole accounting
  --     design rests on this being the rule's own behaviour. Comment-stripped: prosrc carries comments.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_eval_hw_006_presence_verification'
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
         LIKE '%insufficient context for presence verification%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0418 P4: HW.006 no longer abstains on missing context. §2''s accounting split '
                    'assumes it does -- re-read the evaluator before applying';
  END IF;

  RAISE NOTICE '0418 preflight: 5 codes declare task_completion, nothing probes it, need_atom is '
               'populated, HW.006 still abstains on missing context';
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- THE PROBE. Resolves the atom's stall, then hands the frame to the existing
-- shield. Deliberately probes even when there is no stall (§2).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_probe_task_completion(
  p_sim_run_id   uuid,
  p_depot_id     uuid,
  p_vehicle_id   uuid,
  p_svc          text,
  p_started_at   timestamptz DEFAULT NULL,
  p_ends_at      timestamptz DEFAULT NULL)
RETURNS TABLE(rule_code text, passed boolean, reason text, severity text,
              enforcement text, would_block boolean, had_a_stall boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $fn$
DECLARE
  v_stall_id   uuid;
  v_stall_type text;
  v_ctx        jsonb;
BEGIN
  -- §1: the atom-to-stall linkage. `need_atom` names the atom a booking serves; a parking hold carries
  -- NULL (0383), so this returns nothing precisely when the work did not occupy a stall.
  SELECT b.stall_id, s.stall_type::text
    INTO v_stall_id, v_stall_type
    FROM public.ottoq_stall_bookings b
    LEFT JOIN public.stalls s ON s.id = b.stall_id
   WHERE b.vehicle_id = p_vehicle_id
     AND b.need_atom  = p_svc
     AND b.state IN ('held','active','done','interrupted')
     AND (p_sim_run_id IS NULL OR b.sim_run_id IS NULL OR b.sim_run_id = p_sim_run_id)
   ORDER BY (b.state IN ('held','active')) DESC, lower(b.during) DESC
   LIMIT 1;

  -- The frame. `stall_id` is omitted rather than set NULL when there is none, so HW.006 takes its own
  -- declared abstention path instead of casting an empty string.
  v_ctx := jsonb_strip_nulls(jsonb_build_object(
             'action',      'task_completion',
             'vehicle_id',  p_vehicle_id,
             'depot_id',    p_depot_id,
             'stall_id',    v_stall_id,
             'stall_type',  v_stall_type,
             'svc',         p_svc,
             'started_at',  p_started_at,
             'ends_at',     p_ends_at,
             'now_ts',      COALESCE(p_ends_at, now())));

  RETURN QUERY
  SELECT sp.rule_code, sp.passed, sp.reason, sp.severity, sp.enforcement, sp.would_block,
         (v_stall_id IS NOT NULL)
    FROM public.ottoq_shield_probe(
           'task_completion', 'vehicle', p_vehicle_id, v_ctx, NULL, p_depot_id) sp;
END $fn$;

COMMENT ON FUNCTION public.ottoq_probe_task_completion(uuid,uuid,uuid,text,timestamptz,timestamptz) IS
'db/migrations/0418. The probe for task_completion -- the one context of db/checks/0326''s 22 unprobed '
'ones that the engine actually exercises, declared by five codes (HW.003, HW.006, SLA.003, SM.002, '
'TW.002) and probed by nothing. Resolves the completing atom''s stall through ottoq_stall_bookings.'
'need_atom, which names the atom a booking serves and is NULL for parking holds (0383), then hands the '
'frame to ottoq_shield_probe. It probes even when there is no stall, on purpose: suppressing it would '
'also suppress HW.003/SLA.003/SM.002/TW.002, none of which need one. HW.006''s "insufficient context" '
'pass is that rule''s own declared behaviour, so the honesty goes in the accounting -- see '
'ottoq_assert_task_completion_coverage(). NOT WIRED: nothing calls this. Wiring it is one PERFORM in '
'twin.ottoq_sim_advance_visit_atoms'' done-branch and forces a recert, because `rules` is one of the '
'fourteen determinism atoms.';

-- ─────────────────────────────────────────────────────────────────────────────
-- THE ACCOUNTING. §2's discipline: an abstention is never protection.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_assert_task_completion_coverage()
RETURNS TABLE(rule_code text, evaluations bigint, real_verdicts bigint,
              abstentions bigint, failed bigint, would_have_blocked bigint, verdict text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $fn$
  SELECT e.rule_code,
         count(*)                                                              AS evaluations,
         count(*) FILTER (WHERE e.reason IS NULL
                             OR e.reason NOT LIKE 'insufficient context%')     AS real_verdicts,
         count(*) FILTER (WHERE e.reason LIKE 'insufficient context%')         AS abstentions,
         count(*) FILTER (WHERE NOT e.passed)                                  AS failed,
         count(*) FILTER (WHERE NOT e.passed AND r.enforcement = 'block')      AS would_have_blocked,
         CASE
           WHEN count(*) = 0 THEN 'NEVER PROBED'
           WHEN count(*) FILTER (WHERE e.reason LIKE 'insufficient context%') = count(*)
             THEN 'VACUOUS: every evaluation abstained -- this rule is not protecting anything'
           WHEN count(*) FILTER (WHERE NOT e.passed) > 0
             THEN 'FIRING: real failures present'
           ELSE 'clean on real verdicts'
         END                                                                   AS verdict
    FROM public.ottoq_rule_evaluations e
    LEFT JOIN public.ottoq_rules r ON r.rule_code = e.rule_code AND r.status='active'
   WHERE e.action_context = 'task_completion'
   GROUP BY e.rule_code
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_task_completion_coverage() IS
'db/migrations/0418 §2. Separates real verdicts from HW.006''s declared "insufficient context" '
'abstentions at task_completion, so an abstention is never counted as protection. The VACUOUS verdict is '
'the one to watch: a rule whose every evaluation abstained reads green and protects nothing, which is '
'G120''s defect class one level down. Returns no rows until the probe is wired -- absence here means '
'never probed, not clean.';

-- ─────────────────────────────────────────────────────────────────────────────
-- LINEAGE
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0418_the_probe_for_the_one_unprobed_context_the_engine_actually_exercises_built_and_proven_but_not_wired',
  false,
  'Creates ottoq_probe_task_completion (resolves a completing atom''s stall via '
  'ottoq_stall_bookings.need_atom, then calls the existing ottoq_shield_probe) and '
  'ottoq_assert_task_completion_coverage (separates real verdicts from HW.006''s declared abstentions). '
  'FALSE because NOTHING CALLS EITHER FUNCTION -- asserted by V5 -- so no decision, event, booking or '
  'rule evaluation changes on any run. That is the only reason FALSE is earned: WIRING the probe into '
  'twin.ottoq_sim_advance_visit_atoms would write new ottoq_rule_evaluations rows on every run, and '
  '`rules` is one of the fourteen determinism atoms, so the wiring migration MUST be forces_recert TRUE '
  'and will reset the canon matrix. Determinism itself is unaffected -- both arms of a pair write the '
  'same evaluations.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_n           int;
  v_rec         record;
  v_run         uuid;
  v_depot       uuid := '11111111-1111-1111-1111-111111111111';
  v_atoms       int := 0;
  v_probed      int := 0;
  v_stall       int := 0;
  v_fail        int := 0;
  v_abst        int := 0;
  -- Totals and the per-code report live in plpgsql variables precisely BECAUSE those are not
  -- transactional: V4 rolls its writes back and these survive it.
  v_stall_evals int := 0;
  v_fail_total  int := 0;
  v_abst_total  int := 0;
  v_report      text;
BEGIN
  -- V1. Both functions exist with the declared signatures.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('ottoq_probe_task_completion','ottoq_assert_task_completion_coverage');
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0418 V1: expected 2 new functions, found %', v_n;
  END IF;

  -- V2. The accounting function returns NO rows, because nothing has been probed. Absence here is the
  --     "NEVER PROBED" state, and asserting it now is what makes a later non-empty result meaningful.
  SELECT count(*) INTO v_n FROM public.ottoq_assert_task_completion_coverage();
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0418 V2: the coverage accounting returned % rows before the probe is wired', v_n;
  END IF;

  -- V3. THE PROBE SELECTS THE FIVE CODES IT IS AIMED AT. Asserted through ottoq_shield_probe's own
  --     selection rather than by listing them, so a declaration change cannot silently narrow it.
  SELECT count(DISTINCT rule_code) INTO v_n FROM public.ottoq_rules
   WHERE status IN ('active','shadow') AND 'task_completion' = ANY(applies_to_actions);
  IF v_n < 5 THEN
    RAISE EXCEPTION '0418 V3: the shield would select only % codes at task_completion', v_n;
  END IF;

  -- V4. RUN IT ON LIVE ATOMS, AND KEEP THE MEASUREMENT WITHOUT KEEPING THE WRITES.
  --
  --     Every probe call writes to `ottoq_rule_evaluations`, which is APPEND-ONLY -- guarded by
  --     `ottoq_block_mutation`, which rejects DELETE with P0001 -- so those rows cannot be cleaned up
  --     afterwards. Committing them would also make P2 ("nothing probes task_completion") false and this
  --     migration un-rerunnable, and would leave rows that look like a wired probe's output.
  --
  --     The way out: a plpgsql BEGIN/EXCEPTION block is an implicit SAVEPOINT, and **plpgsql variables
  --     are not transactional.** So the exercise runs, its counts land in variables, a deliberate
  --     exception rolls the WRITES back to the savepoint, and the numbers survive the rollback. The
  --     verdicts below are therefore measured on live data and leave nothing behind.
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE status='running' ORDER BY started_at DESC LIMIT 1;

  IF v_run IS NULL THEN
    RAISE NOTICE '0418 V4: no running sim run, so the probe could not be exercised on live atoms. The '
                 'functions are created and unwired; exercise them on the next run before wiring.';
  ELSE
    BEGIN
      FOR v_rec IN
        SELECT vn.vehicle_id, a->>'svc' AS svc,
               NULLIF(a->>'started_at','')::timestamptz AS started_at,
               NULLIF(a->>'ends_at','')::timestamptz    AS ends_at
          FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
         WHERE vn.depot_id = v_depot
           AND vn.status IN ('open','in_progress')
           AND a->>'status' = 'in_progress'
         ORDER BY vn.vehicle_id, a->>'svc'
      LOOP
        v_atoms := v_atoms + 1;
        SELECT count(*), count(*) FILTER (WHERE q.had_a_stall),
               count(*) FILTER (WHERE NOT q.passed),
               count(*) FILTER (WHERE q.reason LIKE 'insufficient context%')
          INTO v_n, v_stall, v_fail, v_abst
          FROM public.ottoq_probe_task_completion(
                 v_run, v_depot, v_rec.vehicle_id, v_rec.svc,
                 v_rec.started_at, v_rec.ends_at) q;
        v_probed := v_probed + COALESCE(v_n, 0);
        v_stall_evals := v_stall_evals + COALESCE(v_stall, 0);
        v_fail_total  := v_fail_total  + COALESCE(v_fail, 0);
        v_abst_total  := v_abst_total  + COALESCE(v_abst, 0);
      END LOOP;

      -- Per-code, into a text variable so it survives the rollback below.
      SELECT string_agg(format('%s: %s evals/%s real/%s abst/%s failed -> %s',
                               c.rule_code, c.evaluations, c.real_verdicts, c.abstentions,
                               c.failed, c.verdict), E'\n      ' ORDER BY c.rule_code)
        INTO v_report
        FROM public.ottoq_assert_task_completion_coverage() c;

      -- Deliberate rollback of the WRITES ONLY. The variables above keep their values.
      -- A custom SQLSTATE, so this can never swallow a real error: five characters from [0-9A-Z], which
      -- is what Postgres requires of a user-defined condition.
      RAISE EXCEPTION USING ERRCODE = 'OQ418', MESSAGE = '0418_dryrun_rollback';
    EXCEPTION WHEN SQLSTATE 'OQ418' THEN
      IF SQLERRM <> '0418_dryrun_rollback' THEN RAISE; END IF;
    END;

    RAISE NOTICE '0418 V4: exercised on % in-progress atoms -> % evaluations, % of them with a resolved '
                 'stall; % failed, % abstained on missing context. All writes rolled back.',
                 v_atoms, v_probed, v_stall_evals, v_fail_total, v_abst_total;
    IF v_report IS NOT NULL THEN
      RAISE NOTICE '0418 V4 per-code:%s      %', E'\n', v_report;
    END IF;

    -- The probe must have RESOLVED A STALL for at least one evaluation, or §1's `need_atom` linkage is
    -- not working and the whole thing could only ever abstain. This is the assertion that would have
    -- caught a wrong join, and it is the one that makes §3 a proof rather than a hope.
    IF v_probed > 0 AND v_stall_evals = 0 THEN
      RAISE EXCEPTION '0418 V4: none of % evaluations resolved a stall -- §1''s atom-to-stall linkage '
                      'found nothing, so the probe is vacuous as built', v_probed;
    END IF;

    -- And the rollback must have actually happened: no task_completion rows may survive it.
    SELECT count(*) INTO v_n FROM public.ottoq_rule_evaluations WHERE action_context='task_completion';
    IF v_n <> 0 THEN
      RAISE EXCEPTION '0418 V4: % task_completion evaluation(s) survived the dry-run rollback. '
                      'ottoq_rule_evaluations is append-only, so they cannot be removed -- abort rather '
                      'than commit rows that look like a wired probe''s output', v_n;
    END IF;
  END IF;

  -- V5. THE forces_recert=FALSE PREMISE: nothing in the engine calls either new function. If anything
  --     did, a run's rule evaluations would change and FALSE would be wrong.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog','information_schema')
     AND p.proname NOT IN ('ottoq_probe_task_completion','ottoq_assert_task_completion_coverage')
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
         ~ '(ottoq_probe_task_completion|ottoq_assert_task_completion_coverage)';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0418 V5: % caller(s) of the new functions. If anything calls the probe on a run, '
                    'forces_recert must be TRUE -- reclassify', v_n;
  END IF;

  RAISE NOTICE '0418 verify: both functions created, accounting empty until wired, five codes selected, '
               'probe exercised on live atoms, and nothing calls it -- which is why FALSE is earned';
END $post$;

-- V4 exercised the probe on live atoms and left nothing behind. Worth restating, because the first
-- draft of this migration got it wrong and would have shipped permanent rows: `ottoq_rule_evaluations`
-- is append-only (`ottoq_block_mutation` rejects DELETE with P0001), so probe output cannot be cleaned
-- up after the fact -- the only way not to keep it is not to commit it. A plpgsql BEGIN/EXCEPTION block
-- is an implicit SAVEPOINT and plpgsql variables are not transactional, so the exercise's writes roll
-- back while its counts survive. V4's last assertion proves the rollback actually happened rather than
-- assuming it, and refuses to commit if any task_completion row survived -- because a row that looks
-- like a wired probe's output, in a table nothing can clean, is worse than no measurement.
COMMIT;
