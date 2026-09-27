-- migration-version: 20260921203917
-- migration-name:    the_evidence_ledgers_look_98_percent_unattributable_and_95_percent_of_that_is_recoverable_from_the_archive
--
-- 0409  **`ottoq_evidence_join_loss_now` reads 83–98% join loss across the evidence ledgers, and
--       that number is CORRECT. It is also badly incomplete: nearly every "lost" row is still
--       attributable, through `ottoq_run_archives` instead of `ottoq_sim_runs`. Two columns are
--       added so the reading carries its own remedy.**
--
--       `forces_recert` FALSE. This touches one read-only check function and its view. No engine
--       state, no emitted event, no atom.
--
-- ══ FIRST, WHAT IS NOT WRONG, BECAUSE I ALMOST "FIXED" IT ═══════════════════
--
-- `0408` revived this check (it had raised 42883 since `0403`), and its first successful reading
-- was alarming:
--
--     ottoq_model_call_ledger              8,498 rows   8,345 orphaned   98.20%
--     ottoq_proposal_disposition_ledger   20,223 rows  16,856 orphaned   83.35%
--     ottoq_proposer_fire_log              1,845 rows   1,768 orphaned   95.83%
--     ottoq_site_power_excursion_ledger    1,300 rows   1,259 orphaned   96.85%
--     ottoq_ab_runs                           91 rows      91 orphaned  100.00%
--
-- My first reading was that the check was pointed at the wrong parent — `ottoq_sim_runs` holds 49
-- rows against `ottoq_run_archives`'s 1,567 — and should be repointed. **`0380`'s own COMMENT
-- settles it the other way, and it should be read before anyone else has that thought:**
--
--     "rows_orphaned > 0 means a naive JOIN to ottoq_sim_runs drops that many purge survivors --
--      read it before quoting any per-seed or per-scenario aggregate over an evidence table."
--
-- The question this check asks is *"how much does a naive join to `ottoq_sim_runs` destroy?"*, and
-- for that question 98.2% is the right answer and repointing it would delete the warning. The
-- defect class it guards is `0145`/`0146`/`0250`/`0275`: an analyst writes
-- `JOIN ottoq_sim_runs USING (sim_run_id)` out of habit and silently loses 98% of the evidence the
-- ledger exists to preserve.
--
-- ══ WHAT IS MISSING, AND WHY IT MATTERS MORE THAN THE 98% ══════════════════
--
-- The reading stops one question short of useful. Measured 2026-09-21 20:40 UTC:
--
--                                        orphaned   recoverable via run_archives   truly lost
--     ottoq_proposal_disposition_ledger    16,856                       16,856              0
--     ottoq_model_call_ledger               8,345                        7,928            417
--
-- **The proposal disposition ledger's "83% join loss" is 0% lost provenance.** Every one of those
-- rows still names a run that `ottoq_run_archives` holds — scenario, seed, policy, depot, the
-- whole reproducibility key. The model call ledger's real unattributable figure is **417 of 8,498,
-- 4.9%**, not 98.2%. Twenty times smaller.
--
-- That gap is the difference between two very different sentences about the same table:
--
--   - "98% of the cuOpt evidence cannot be tied to a run"  — false, and it would retract
--     `SOLVER_STATE.md` §13 for no reason.
--   - "98% of it is invisible to a naive join, and 95% of THAT is recoverable by joining
--     `ottoq_run_archives` instead; 417 rows name a run nothing remembers"  — true, and the
--     second clause tells the reader what to do.
--
-- `db/checks/0275` reads this view, and this repo's standing rule is "cite the run, never the
-- table." A check that reports a run link as lost when the durable run key still holds it teaches
-- the opposite of that rule.
--
-- ══ WHY BOTH PARENTS, RATHER THAN SWAPPING ═════════════════════════════════
--
-- `ottoq_sim_runs` and `ottoq_run_archives` are BOTH `class='run_ledger'` in the registry, and
-- they are not interchangeable: the purge deletes prior runs from `ottoq_sim_runs` (49 rows
-- survive) while `ottoq_run_archives` accumulates one row per run ever archived (1,567). So
-- `ottoq_sim_runs` answers "is this run still live?" and `ottoq_run_archives` answers "is this run
-- still IDENTIFIABLE?" An evidence row needs the second, and the naive-join hazard is about the
-- first. Reporting both keeps each question answerable and neither answer able to masquerade as
-- the other.
--
-- Two new OUT columns, so the return signature changes and the function must be dropped rather
-- than replaced (42P13 forbids changing OUT columns in place). The view depends on it, so both go
-- and both come back in this transaction. `p_pattern`'s default is preserved verbatim.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n     int;
  v_cols  int;
  v_def   text;
  v_orph  bigint;
  v_rec   bigint;
BEGIN
  -- P1. The function is the 6-column, 1-default shape 0380/0408 left behind.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_evidence_join_loss';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0409 P1: expected exactly 1 ottoq_evidence_join_loss overload, found %', v_n;
  END IF;
  SELECT p.pronargdefaults,
         cardinality(string_to_array(pg_get_function_result(p.oid), ','))
    INTO v_n, v_cols
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_evidence_join_loss';
  IF v_n <> 1 OR v_cols <> 6 THEN
    RAISE EXCEPTION '0409 P1: expected 1 defaulted arg and 6 OUT columns, found % and % -- '
                    'signature moved since 0408', v_n, v_cols;
  END IF;

  -- P2. It RUNS. 0408 fixed the 42883; if it raises again this migration is building on sand.
  PERFORM count(*) FROM public.ottoq_evidence_join_loss();

  -- P3. The view is the trivial passthrough 0380 created, so recreating it loses no logic.
  SELECT pg_get_viewdef('public.ottoq_evidence_join_loss_now'::regclass, true) INTO v_def;
  IF v_def IS NULL OR v_def !~ 'ottoq_evidence_join_loss\(\)' THEN
    RAISE EXCEPTION '0409 P3: ottoq_evidence_join_loss_now is not the expected passthrough: %', v_def;
  END IF;

  -- P4. THE PREMISE. The archive must actually hold more runs than the live run table, or the
  --     second parent adds nothing and this migration is pointless.
  IF (SELECT count(*) FROM public.ottoq_run_archives)
     <= (SELECT count(*) FROM public.ottoq_sim_runs) THEN
    RAISE EXCEPTION '0409 P4: ottoq_run_archives (%) does not exceed ottoq_sim_runs (%) -- the '
                    'recoverability column would be noise',
                    (SELECT count(*) FROM public.ottoq_run_archives),
                    (SELECT count(*) FROM public.ottoq_sim_runs);
  END IF;
  IF (SELECT data_type FROM information_schema.columns
       WHERE table_schema='public' AND table_name='ottoq_run_archives'
         AND column_name='sim_run_id') <> 'uuid' THEN
    RAISE EXCEPTION '0409 P4: ottoq_run_archives.sim_run_id is not uuid -- cannot join evidence to it';
  END IF;

  -- P5. And the effect is real and large on at least one ledger, measured before it is claimed.
  SELECT count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                                             WHERE r.sim_run_id = p.sim_run_id)),
         count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                                             WHERE r.sim_run_id = p.sim_run_id)
                            AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a
                                         WHERE a.sim_run_id = p.sim_run_id))
    INTO v_orph, v_rec
    FROM public.ottoq_proposal_disposition_ledger p
   WHERE p.sim_run_id IS NOT NULL;
  IF v_orph = 0 OR v_rec * 100 / GREATEST(v_orph,1) < 50 THEN
    RAISE EXCEPTION '0409 P5: proposal disposition ledger: % orphans, % recoverable -- the header '
                    'claims near-total recoverability; re-derive it', v_orph, v_rec;
  END IF;

  -- P6. CAPTURE THE PRIVILEGES BEFORE DROPPING, because DROP/CREATE is not CREATE OR REPLACE:
  --     REPLACE preserves an object's ACL, CREATE takes Supabase's project-level
  --     ALTER DEFAULT PRIVILEGES instead. That is exactly the mechanism `0406` documented -- a
  --     new function in `public` becomes anon-reachable the moment it is created. Both objects
  --     ALREADY grant anon/authenticated/service_role (they are read-only: STABLE, no writes),
  --     so the expectation is that the ACL comes back identical. Asserted rather than assumed,
  --     and deliberately NOT changed here: tightening this surface is a security decision of its
  --     own, not a side effect of adding two columns.
  --
  --     Asserted as the four role/privilege PAIRS rather than as the ACL string, because default
  --     privileges rebuild the ACL array in their own order and a text compare would fail on
  --     ordering alone.
  IF NOT (has_function_privilege('anon',         'public.ottoq_evidence_join_loss(text)', 'EXECUTE')
      AND has_function_privilege('authenticated','public.ottoq_evidence_join_loss(text)', 'EXECUTE')
      AND has_function_privilege('service_role', 'public.ottoq_evidence_join_loss(text)', 'EXECUTE')
      AND has_table_privilege   ('anon',         'public.ottoq_evidence_join_loss_now',   'SELECT')
      AND has_table_privilege   ('service_role', 'public.ottoq_evidence_join_loss_now',   'SELECT')) THEN
    RAISE EXCEPTION '0409 P6: the pre-drop privilege set is not what V5 will assert afterwards -- '
                    're-measure the ACLs before dropping';
  END IF;

  RAISE NOTICE '0409 preflight: passed; % orphans of which % recoverable on the disposition ledger',
               v_orph, v_rec;
END $pre$;

DROP VIEW IF EXISTS public.ottoq_evidence_join_loss_now;
DROP FUNCTION IF EXISTS public.ottoq_evidence_join_loss(text);

CREATE FUNCTION public.ottoq_evidence_join_loss(p_pattern text DEFAULT 'ottoq\_%'::text)
RETURNS TABLE (table_name text, rows_total bigint, rows_with_run bigint,
               rows_orphaned bigint, join_loss_pct numeric,
               rows_recoverable_via_archive bigint, rows_unattributable bigint,
               has_fk_to_sim_runs boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
DECLARE
  r      record;
  v_tot  bigint;
  v_run  bigint;
  v_orph bigint;
  v_rec  bigint;
BEGIN
  FOR r IN
    SELECT DISTINCT reg.table_schema AS sch, reg.table_name AS tbl, reg.column_name AS col
      FROM public.ottoq_run_scope_registry reg
     WHERE reg.class = 'evidence'
       AND reg.table_name LIKE p_pattern
       --: Registered but dropped tables are not a finding; skip rather than raise.
       AND to_regclass(format('%I.%I', reg.table_schema, reg.table_name)) IS NOT NULL
       --: The join hazard needs the joining column to exist, AND to be joinable.
       --:
       --: `c.data_type = 'uuid'` ADDED 0408. The EXECUTE below compares this column to
       --: ottoq_sim_runs.sim_run_id, which is uuid. 0403 registered a bigint SURROGATE KEY
       --: (ottoq_dial_promotion_ledger.promotion_id) as evidence, the comparison raised 42883,
       --: and that killed the whole loop -- this check returned nothing at all from the moment
       --: 0403 landed until 0408.
       --:
       --: TYPE and not NAME, deliberately. 0344 fixed the same per-column/per-table confusion
       --: in ottoq_check_run_scope_registry check (b2) by narrowing to the four run-key column
       --: names; here that would drop ottoq_determinism_verdict_ledger.arm_a_run and .arm_b_run
       --: -- two uuid columns that ARE run references and whose join loss matters most -- in
       --: order to exclude one bigint. A non-uuid column cannot reference a uuid key; a uuid
       --: column called arm_a_run can.
       AND EXISTS (SELECT 1 FROM information_schema.columns c
                    WHERE c.table_schema = reg.table_schema
                      AND c.table_name  = reg.table_name
                      AND c.column_name = reg.column_name
                      AND c.data_type   = 'uuid')
     ORDER BY reg.table_name
  LOOP
    --: TWO PARENTS, ADDED 0409, and they answer different questions.
    --:
    --:   ottoq_sim_runs     -- "is this run still LIVE?" The purge deletes prior runs from it
    --:                         (49 rows at 0409), so a naive join to it drops purge survivors.
    --:                         rows_orphaned measures exactly that damage and is the original
    --:                         0380 warning. It is not a provenance measure.
    --:   ottoq_run_archives -- "is this run still IDENTIFIABLE?" One row per run ever archived
    --:                         (1,567 at 0409), carrying scenario + seed + policy + depot. This
    --:                         is what an evidence row actually needs.
    --:
    --: Measured at 0409: ottoq_proposal_disposition_ledger reported 83.35% join loss and
    --: 16,856 of 16,856 of those orphans were recoverable from the archive -- 0% lost
    --: provenance. ottoq_model_call_ledger reported 98.20% and its truly-unattributable count
    --: was 417 of 8,498, i.e. 4.9%. Reporting only the first number invites the sentence
    --: "98% of the cuOpt evidence cannot be tied to a run", which is false and would retract
    --: SOLVER_STATE.md section 13 for nothing. rows_unattributable is the number that would
    --: justify alarm; it is the one to quote.
    EXECUTE format(
      'SELECT count(*), count(%1$I), '
      '       count(*) FILTER (WHERE %1$I IS NOT NULL AND NOT EXISTS ('
      '         SELECT 1 FROM public.ottoq_sim_runs sr WHERE sr.sim_run_id = t.%1$I)), '
      '       count(*) FILTER (WHERE %1$I IS NOT NULL AND NOT EXISTS ('
      '         SELECT 1 FROM public.ottoq_sim_runs sr WHERE sr.sim_run_id = t.%1$I) '
      '                          AND EXISTS ('
      '         SELECT 1 FROM public.ottoq_run_archives ra WHERE ra.sim_run_id = t.%1$I)) '
      '  FROM %2$I.%3$I t', r.col, r.sch, r.tbl)
      INTO v_tot, v_run, v_orph, v_rec;

    table_name                   := r.tbl;
    rows_total                   := v_tot;
    rows_with_run                := v_run;
    rows_orphaned                := v_orph;
    join_loss_pct                := CASE WHEN v_tot > 0
                                         THEN round(100.0 * v_orph / v_tot, 2) ELSE NULL END;
    rows_recoverable_via_archive := v_rec;
    rows_unattributable          := v_orph - v_rec;
    --: An FK here would be a registry violation (check (b) wants one from engine/stamp
    --: only). Surfaced beside the loss because the two are the same mistake at different
    --: layers: one blocks the purge, the other silently omits its survivors.
    has_fk_to_sim_runs := EXISTS (
      SELECT 1 FROM pg_constraint c
       WHERE c.conrelid = to_regclass(format('%I.%I', r.sch, r.tbl))
         AND c.contype = 'f'
         AND c.confrelid = 'public.ottoq_sim_runs'::regclass);
    RETURN NEXT;
  END LOOP;
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_evidence_join_loss(text) IS
'0380, extended 0409. Per evidence-class table: how many rows a naive JOIN to ottoq_sim_runs '
'would drop (rows_orphaned / join_loss_pct -- the 0380 warning, read it before quoting any '
'per-seed or per-scenario aggregate over an evidence table), and how many of those are still '
'attributable through ottoq_run_archives (rows_recoverable_via_archive) versus name a run nothing '
'remembers (rows_unattributable). rows_orphaned is the size of the naive-join hazard; '
'rows_unattributable is the size of the actual evidence loss, and it is the only one of the two '
'that justifies alarm. has_fk_to_sim_runs must be false everywhere: true is a registry violation, '
'not a style question. Restored to working order by 0408 after 0403 registered a bigint surrogate '
'key as evidence and the uuid comparison raised 42883, silently disabling the whole check.';

CREATE VIEW public.ottoq_evidence_join_loss_now AS
SELECT * FROM public.ottoq_evidence_join_loss();

COMMENT ON VIEW public.ottoq_evidence_join_loss_now IS
'0380, extended 0409. The standing reading of ottoq_evidence_join_loss() over the live evidence '
'ledgers. rows_orphaned > 0 means a naive JOIN to ottoq_sim_runs drops that many purge survivors. '
'rows_unattributable > 0 is the stronger finding: those rows name a sim_run_id that is in neither '
'ottoq_sim_runs nor ottoq_run_archives, so no run ID can be cited for them at all. Quote '
'rows_unattributable, not join_loss_pct -- at 0409 the proposal disposition ledger read 83.35% '
'join loss with ZERO unattributable rows. has_fk_to_sim_runs must be false everywhere.';

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_rows int;
  v_n    int;
  v_pdl  record;
  v_mcl  record;
BEGIN
  -- V1. The view exists and returns the same table set as before, now eight columns wide.
  SELECT count(*) INTO v_rows FROM public.ottoq_evidence_join_loss_now;
  IF v_rows = 0 THEN
    RAISE EXCEPTION '0409 V1: ottoq_evidence_join_loss_now returned no rows';
  END IF;
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_evidence_join_loss_now';
  IF v_n <> 8 THEN
    RAISE EXCEPTION '0409 V1: view has % column(s), expected 8', v_n;
  END IF;

  -- V2. The determinism verdict ledger's two uuid arm columns are still covered -- 0408's type
  --     filter must survive the drop-and-recreate, or this migration silently undoes it.
  SELECT count(*) INTO v_n
    FROM public.ottoq_evidence_join_loss('ottoq\_determinism\_verdict\_ledger');
  IF v_n < 2 THEN
    RAISE EXCEPTION '0409 V2: determinism verdict ledger contributes % row(s), expected 2 '
                    '(arm_a_run, arm_b_run)', v_n;
  END IF;

  -- V3. The arithmetic holds and the header's two headline numbers are what the function says.
  SELECT * INTO v_pdl FROM public.ottoq_evidence_join_loss_now
   WHERE table_name = 'ottoq_proposal_disposition_ledger' LIMIT 1;
  IF v_pdl IS NULL THEN
    RAISE EXCEPTION '0409 V3: proposal disposition ledger absent from the reading';
  END IF;
  IF v_pdl.rows_recoverable_via_archive + v_pdl.rows_unattributable <> v_pdl.rows_orphaned THEN
    RAISE EXCEPTION '0409 V3: recoverable (%) + unattributable (%) <> orphaned (%)',
                    v_pdl.rows_recoverable_via_archive, v_pdl.rows_unattributable, v_pdl.rows_orphaned;
  END IF;
  IF v_pdl.rows_unattributable <> 0 THEN
    RAISE WARNING '0409 V3: proposal disposition ledger now has % unattributable row(s); the '
                  'header records 0 at 20:40 UTC. Not a failure -- but re-derive before quoting.',
                  v_pdl.rows_unattributable;
  END IF;

  SELECT * INTO v_mcl FROM public.ottoq_evidence_join_loss_now
   WHERE table_name = 'ottoq_model_call_ledger' LIMIT 1;
  IF v_mcl IS NOT NULL AND v_mcl.rows_orphaned > 0
     AND v_mcl.rows_unattributable >= v_mcl.rows_orphaned THEN
    RAISE EXCEPTION '0409 V3: model call ledger shows no recoverability (% of % orphans '
                    'unattributable) -- the archive join is not working',
                    v_mcl.rows_unattributable, v_mcl.rows_orphaned;
  END IF;

  -- V4. No FK crept in, and the anon surface is still clean after a DROP/CREATE (which, unlike
  --     CREATE OR REPLACE, DOES re-apply Supabase's project default privileges -- the 0406 hole).
  SELECT count(*) INTO v_n FROM public.ottoq_evidence_join_loss_now WHERE has_fk_to_sim_runs;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0409 V4: % evidence table(s) carry an FK to ottoq_sim_runs -- registry violation', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_assert_anon_rpc_surface();
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0409 V4: anon RPC surface reports % problem(s) after DROP/CREATE -- expected empty', v_n;
  END IF;

  -- V5. The privileges came back as they were. A DROP/CREATE that silently widens or narrows
  --     access is the 0406 hazard, and it would be invisible in the diff of this file. Same five
  --     pairs P6 asserted beforehand, so the two halves are one statement about one thing.
  IF NOT (has_function_privilege('anon',         'public.ottoq_evidence_join_loss(text)', 'EXECUTE')
      AND has_function_privilege('authenticated','public.ottoq_evidence_join_loss(text)', 'EXECUTE')
      AND has_function_privilege('service_role', 'public.ottoq_evidence_join_loss(text)', 'EXECUTE')
      AND has_table_privilege   ('anon',         'public.ottoq_evidence_join_loss_now',   'SELECT')
      AND has_table_privilege   ('service_role', 'public.ottoq_evidence_join_loss_now',   'SELECT')) THEN
    RAISE EXCEPTION '0409 V5: DROP/CREATE narrowed access -- the cockpit and any reader of '
                    'ottoq_evidence_join_loss_now would start getting permission denied';
  END IF;

  RAISE NOTICE '0409 verify: % evidence table(s) read; disposition ledger % orphaned / % '
               'recoverable / % unattributable',
               v_rows, v_pdl.rows_orphaned, v_pdl.rows_recoverable_via_archive,
               v_pdl.rows_unattributable;
END $post$;

COMMIT;
