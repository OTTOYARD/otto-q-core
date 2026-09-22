-- migration-version: 20260922134041
-- migration-name:    wiring_the_task_completion_probe_so_the_rule_that_names_g121_can_finally_fire
--
-- 0422  **`0418` built the `task_completion` probe, proved its verdicts on live atoms, and deliberately
--       left it unwired. This is the one line it left. `task_completion` becomes the TENTH probe point
--       and `HW.006` fires for the first time in this engine's life.**
--
--       `forces_recert` **TRUE**, and that is the entire reason `0418` stopped where it did. See §3.
--
-- ══ §1 WHY THIS IS NOT A COSMETIC COUNT ═══════════════════════════════════════
--
-- `0326` §6 established the test that separates a harmless declaration gap from a real one: **not the
-- count, but whether the engine performs the action.** Of the 22 contexts nothing probes, 21 are actions
-- this engine never takes — SM.004's seven are human/UI actions with no DB path, and `oem_acceptance`,
-- `release` and `power_increase` rename transitions the engine reaches through `redeployment` and
-- `charge_session_start`, where the same codes already fire. `task_completion` is the exception. The
-- engine completes atoms constantly.
--
-- And the bill is already on the books. **G121**: three of the twin depot's ten fast chargers carry
-- `status='available'` together with a live `current_vehicle_id` and `reserved_by`, all three pointing at
-- a vehicle physically in a bay, persistent across ticks. **`HW.006.physical_presence_verification` is
-- the rule that names exactly that defect and prescribes its repair, and it has never been evaluated
-- once** (G122), because nothing probed the context it declares.
--
-- The sharpest instance stays worth repeating: `task_completion` is declared by **five** codes —
-- `HW.003.sensor_liveness`, `HW.006`, `SLA.003.max_visit_duration`, `SM.002.task_transition_validity`,
-- `TW.002` — and **three of the five already scored as "evaluated" because they fire at `task_start`**.
-- So the engine has been checking sensor liveness before work begins, never after it ends, and counting
-- that as covered.
--
-- ══ §2 WHERE IT GOES, AND WHY IT CANNOT WEDGE THE TICK ════════════════════════
--
-- Inside `twin.ottoq_sim_advance_visit_atoms`, in the branch that sets an atom to `done` — immediately
-- after the wear-ledger credit, whose own `BEGIN/EXCEPTION` block carries the comment this one copies:
-- *"a ledger failure must never unwind the atom close, the leg close, or the tick."*
--
-- Three independent reasons it cannot break a run:
--
--   1. **`ottoq_shield_probe` does not block.** It returns a `would_block` column and leaves enforcement
--      entirely to its caller (`0326` §6). This caller enforces nothing. It probes.
--   2. **Its own exception handler**, matching the established pattern one statement above it.
--   3. **`PERFORM`, not a gate.** No branch of the atom close reads its result.
--
-- **Scope, stated because it is a real limit and not a footnote.** This call site is in the `twin` schema,
-- so it probes the TWIN's completions. Production completions still have no `task_completion` probe.
-- Under operating rule 8 the twin depot is the only test target, so this is the right and only scope
-- today — but "HW.006 now fires" must never be said without "on twin atom completions."
--
-- ══ §3 THE CLASSIFICATION, WHICH IS THE WHOLE COST ════════════════════════════
--
-- `rules` is one of the fourteen byte-identical determinism atoms (CLAUDE.md 2.9a). A probe at atom
-- completion writes new rows to `ottoq_rule_evaluations` on every run, so the `rules` atom's content
-- changes and every stored canon verdict is superseded. `forces_recert` **TRUE**, the canon matrix's
-- per-column streaks reset, and the sweep re-runs (~36 min).
--
-- **Determinism itself is untouched, and that distinction is the point of the classification.** Both arms
-- of a pair run the same code and write the same evaluations; what changes is that yesterday's verdict
-- was taken on an engine that no longer exists. That is what a recert floor is for.
--
-- Volume: roughly 400 atom completions on a 48-tick busy_day run x 5 codes ~= 2,000 evaluations, against
-- a live `task_start` count of 137,787. It is not a write-volume decision.
--
-- ══ §4 WHY IT IS BEING APPLIED NOW RATHER THAN HELD AGAIN ═════════════════════
--
-- `0418` §4 held it for one stated reason — *"resetting the reproducibility apparatus is Chase's call to
-- make awake"* — and Chase has since settled that class of decision in his own words: *"If you can answer
-- it yourself or use your expertise ... then go ahead and do that. Only let me know if it's major and you
-- can't decide."* A recert is not a cost to be timed around; it is the verification. Holding a fix so the
-- apparatus that would check it stays green is backwards.
--
-- It is applied **after** `0421`'s sweep completes and not during it, so that sweep isolates `0421`
-- (`db/checks/0330` is its verification and needs a clean before/after). Two other `forces_recert`
-- changes ride with this one so the next sweep validates all three together.
--
-- ══ §5 WHAT THIS DOES NOT DO ══════════════════════════════════════════════════
--
-- **It does not fix G121.** A probe reports; it does not reconcile. `0326` §7(a) records why widening
-- `ottoq_release_vacated_spaces` is the wrong repair (the bay-only exclusion is deliberate, written
-- twice, and hard-freeing a `dcfc` pointer from a sweep could race the charge-session path that owns that
-- column). What this buys is that the defect becomes COUNTABLE from the shield's own ledger instead of
-- from an ad-hoc census.
--
-- **It does not make HW.006 protective.** `0418` §2: HW.006's evaluator returns TRUE with reason
-- *"insufficient context for presence verification"* and `severity='warning'` when no stall resolves, and
-- `cabin`/`exterior` atoms are performed at the vehicle with no stall at all (`0383`). Those are honest
-- abstentions and `ottoq_assert_task_completion_coverage()` exists precisely to count them separately.
-- **Read that function, never the raw evaluation count.**

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n   int;
  v_def text;
BEGIN
  -- P1. 0418's probe and its accounting function both exist. Wiring a call to something absent would
  --     fail at runtime inside an exception handler -- i.e. silently, forever.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('ottoq_probe_task_completion',
                                              'ottoq_assert_task_completion_coverage');
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0422 P1: expected 0418''s two functions, found % -- apply 0418 first', v_n;
  END IF;

  -- P2. STILL UNPROBED. 0418 P2 asserted this when it built the probe; re-assert it here because the
  --     accounting in §5 double-counts if something else started probing in between.
  SELECT count(*) INTO v_n FROM public.ottoq_rule_evaluations WHERE action_context='task_completion';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0422 P2: task_completion already has % evaluations -- reconcile before wiring', v_n;
  END IF;

  -- P3. The five codes still declare the context. A probe aimed at a declaration that moved is a probe
  --     aimed at nothing.
  SELECT count(DISTINCT rule_code) INTO v_n FROM public.ottoq_rules
   WHERE status='active' AND 'task_completion' = ANY(applies_to_actions);
  IF v_n < 5 THEN
    RAISE EXCEPTION '0422 P3: only % active codes declare task_completion, expected >= 5', v_n;
  END IF;

  -- P4. The splice anchor occurs EXACTLY ONCE, the wear-ledger call precedes its own handler, and
  --     v_depot is in scope at the splice point. All three are preconditions of the edit below.
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms';
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0422 P4: twin.ottoq_sim_advance_visit_atoms does not exist';
  END IF;
  v_n := (length(v_def) - length(replace(v_def,'need-ledger credit FAILED SAFELY','')))
         / length('need-ledger credit FAILED SAFELY');
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0422 P4: the splice anchor occurs % times, expected exactly 1', v_n;
  END IF;
  IF position('ottoq_wear_mark_serviced' in v_def) >= position('need-ledger credit FAILED SAFELY' in v_def) THEN
    RAISE EXCEPTION '0422 P4: the wear-ledger call no longer precedes its own handler -- the block this '
                    'migration splices after is not the block it was written against';
  END IF;
  IF position('v_depot uuid' in v_def) = 0 THEN
    RAISE EXCEPTION '0422 P4: v_depot is not declared -- the probe call would not compile';
  END IF;

  -- P5. No demo or cert run is live. This rewrites a function the tick calls; doing so mid-run would
  --     change the engine under a run that is already being fingerprinted.
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0422 P5: % run(s) are running/paused -- wait for the sweep and any demo to finish', v_n;
  END IF;
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- THE EDIT -- surgical splice, asserted by byte delta
-- ─────────────────────────────────────────────────────────────────────────────
DO $fix$
DECLARE
  v_def    text;
  v_new    text;
  v_insert text;
  v_pos    int;
  v_endpos int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms';

  v_insert :=
E'\n\n        -- 0422: PROBE task_completion -- the one unprobed context the engine actually performs.\n'
'        -- 0418 built and proved this probe and left it unwired because `rules` is one of the fourteen\n'
'        -- determinism atoms. This is that line. Own handler, exactly like the ledger credit above: a\n'
'        -- shield READ must never unwind the atom close. ottoq_shield_probe does not block -- it returns\n'
'        -- would_block and leaves enforcement to its caller, and this caller enforces nothing.\n'
'        BEGIN\n'
'          PERFORM public.ottoq_probe_task_completion(\n'
'                    p_sim_run_id, v_depot, v_rec.vehicle_id, v_a->>''svc'',\n'
'                    (v_a->>''started_at'')::timestamptz,\n'
'                    COALESCE((v_a->>''ends_at'')::timestamptz, p_clock));\n'
'        EXCEPTION WHEN OTHERS THEN\n'
'          RAISE WARNING ''ottoq_sim_advance_visit_atoms: task_completion probe FAILED SAFELY vehicle=% svc=% %: %'',\n'
'            v_rec.vehicle_id, v_a->>''svc'', SQLSTATE, SQLERRM;\n'
'        END;';

  -- Locate the END; that closes the wear-ledger handler, by walking forward from the anchor rather than
  -- by typing a multi-line literal that whitespace drift could silently miss.
  v_pos    := position('need-ledger credit FAILED SAFELY' in v_def);
  v_endpos := v_pos + position('END;' in substring(v_def from v_pos)) - 1 + 3;

  IF substring(v_def from v_endpos - 3 for 4) <> 'END;' THEN
    RAISE EXCEPTION '0422 fix: the computed splice point is "%" not "END;" -- refusing to splice',
                    substring(v_def from v_endpos - 3 for 4);
  END IF;

  v_new := substring(v_def for v_endpos) || v_insert || substring(v_def from v_endpos + 1);

  -- THE BYTE-DELTA ASSERTION: the rewritten definition must be longer by EXACTLY the inserted text and
  -- by nothing else. Any other change anywhere in the definition aborts here.
  IF length(v_new) - length(v_def) <> length(v_insert) THEN
    RAISE EXCEPTION '0422 fix: byte delta is % but the insert is % -- something else changed',
                    length(v_new) - length(v_def), length(v_insert);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0422 fix: installed, +% bytes, exactly the inserted block', length(v_insert);
END $fix$;

-- ─────────────────────────────────────────────────────────────────────────────
-- LINEAGE
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0422_wiring_the_task_completion_probe_so_the_rule_that_names_g121_can_finally_fire',
  true,
  'Wires 0418''s ottoq_probe_task_completion into twin.ottoq_sim_advance_visit_atoms'' done branch, '
  'making task_completion the tenth probe point and firing HW.006.physical_presence_verification for the '
  'first time -- the rule that names G121 (three dcfc stalls held by vehicles that are in bays) and had '
  'never been evaluated once because nothing probed the context it declares. TRUE because `rules` is one '
  'of the fourteen atoms: every run now writes ~2,000 extra ottoq_rule_evaluations rows, so every stored '
  'canon verdict is superseded. Determinism is unaffected -- both arms run the same code and write the '
  'same evaluations. Scope is TWIN completions only (the call site is in the twin schema); production '
  'completions remain unprobed. Does not fix G121 and does not make HW.006 protective: it abstains with '
  'severity=warning when no stall resolves, which is its own declared behaviour, and '
  'ottoq_assert_task_completion_coverage() counts those abstentions separately -- read that, never the '
  'raw evaluation count.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_src   text;
  v_n     int;
  v_rec   RECORD;
  v_before int;
  v_after  int;
BEGIN
  -- V1. The call is installed, exactly once, and AFTER the wear-ledger credit (i.e. inside the done
  --     branch, not somewhere earlier in the function). Comment-stripped: prosrc carries comments, and
  --     this migration's own comment block names the function it is asserting -- 0329 hit that trap in
  --     the assertion meant to prove its own finding.
  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
    INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms';
  v_n := (length(v_src) - length(replace(v_src,'ottoq_probe_task_completion','')))
         / length('ottoq_probe_task_completion');
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0422 V1: the probe call appears % times in the installed function, expected 1', v_n;
  END IF;
  IF position('ottoq_probe_task_completion' in v_src) < position('ottoq_wear_mark_serviced' in v_src) THEN
    RAISE EXCEPTION '0422 V1: the probe precedes the wear credit -- it was spliced into the wrong block';
  END IF;

  -- V2. THE GUARDS THAT MUST SURVIVE. Each of these is a named prior finding living inside this
  --     function; a splice that dropped one would pass V1 and lose a fix.
  FOREACH v_src IN ARRAY ARRAY['ottoq_wear_mark_serviced',      -- 0005: the ledger the depot reads
                               'ottoq_close_atom_leg',          -- N2/M4c: the flow-contract leg
                               'run-stable cursor order',       -- 0054: deterministic cursor
                               'requires_tech_greenlight',      -- the ops-approval path
                               'readiness_check']               -- the atom the sweep depends on
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms'
       AND position(v_src in pg_get_functiondef(p.oid)) > 0;
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0422 V2: guard "%" is missing from the installed function', v_src;
    END IF;
  END LOOP;

  -- V3. THE PROBE ACTUALLY PRODUCES VERDICTS. Not "the call is present" -- run it against a real atom
  --     and count the evaluations it writes. The savepoint trick: a plpgsql BEGIN/EXCEPTION block is an
  --     implicit SAVEPOINT, and plpgsql variables are NOT transactional, so the writes roll back while
  --     the counts survive to be reported.
  SELECT count(*) INTO v_before FROM public.ottoq_rule_evaluations WHERE action_context='task_completion';
  BEGIN
    SELECT vn.vehicle_id, r.sim_run_id, r.depot_id, a->>'svc' AS svc,
           (a->>'started_at')::timestamptz AS st, (a->>'ends_at')::timestamptz AS en
      INTO v_rec
      FROM public.ottoq_visit_needs vn
      JOIN public.ottoq_sim_runs r ON r.sim_run_id = vn.sim_run_id
      CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
     WHERE a->>'status' IN ('in_progress','done') AND a ? 'started_at'
     ORDER BY (a->>'started_at')::timestamptz DESC
     LIMIT 1;

    IF v_rec.vehicle_id IS NULL THEN
      RAISE WARNING '0422 V3: no atom with a started_at anywhere -- the probe could not be exercised. '
                    'This is a COLD DATABASE, not a passing test. Re-run V3 after the next run.';
    ELSE
      PERFORM public.ottoq_probe_task_completion(v_rec.sim_run_id, v_rec.depot_id, v_rec.vehicle_id,
                                                 v_rec.svc, v_rec.st, COALESCE(v_rec.en, now()));
      SELECT count(*) INTO v_after FROM public.ottoq_rule_evaluations WHERE action_context='task_completion';
      IF v_after - v_before < 1 THEN
        RAISE EXCEPTION '0422 V3: the probe wrote % evaluations for a real atom -- it is inert',
                        v_after - v_before;
      END IF;
      RAISE NOTICE '0422 V3: the probe wrote % task_completion evaluations for svc=% (rolled back)',
                   v_after - v_before, v_rec.svc;
    END IF;
    RAISE EXCEPTION 'OQ422 rollback' USING ERRCODE = 'OQ422';
  EXCEPTION WHEN SQLSTATE 'OQ422' THEN
    NULL;  -- deliberate: V3's writes are discarded, its counts are not
  END;

  -- V4. The classification is on the record. A forces_recert change that did not register would leave
  --     the canon matrix reporting green on an engine that moved.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage
   WHERE name LIKE '0422%' AND forces_recert;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0422 V4: lineage row missing or not forces_recert';
  END IF;

  RAISE NOTICE '0422: verified. task_completion is the tenth probe point; the next sweep recertifies '
               'every canon against an engine that now evaluates HW.006.';
END $post$;

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- AFTER THE NEXT SWEEP, RUN THIS. It is the number to quote, and the raw
-- evaluation count is not.
-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT * FROM public.ottoq_assert_task_completion_coverage();
--   -- real_verdicts vs abstentions per code. HW.006 abstaining on cabin/exterior atoms is CORRECT
--   -- (0383: those are performed at the vehicle, lane_stalls NULL); HW.006 FAILING on a bay or charge
--   -- atom is G121 becoming countable from the shield's own ledger.
