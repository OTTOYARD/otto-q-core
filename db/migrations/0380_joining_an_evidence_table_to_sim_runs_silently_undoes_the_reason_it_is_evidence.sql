-- migration-version: 20260920135731
-- migration-name:    joining_an_evidence_table_to_sim_runs_silently_undoes_the_reason_it_is_evidence
--
-- 0380  EVERY EVIDENCE LEDGER WE BUILT EXISTS TO SURVIVE THE PURGE, AND THE OBVIOUS
--       WAY TO ANALYSE ONE THROWS THE SURVIVORS AWAY.
--
-- Read-only function plus a view. No tick path, no DDL on any existing table,
-- `forces_recert` **FALSE**.
--
-- ══ 1. HOW THIS WAS FOUND: I DID IT TO MYSELF, TWO QUERIES APART ════════════
--
-- Measuring `greedy_constrained`'s enactment rate, the same question answered two
-- ways, minutes apart:
--
--   ledger alone, GROUP BY sim_run_id                  **847 rows**
--   ledger JOIN ottoq_sim_runs, GROUP BY seed, ticks    **836 rows**
--
-- The missing **11** belong to run `3fb415d8`, which `ottoq_purge_prior_runs` deleted.
-- Those eleven rows are the most valuable in the table -- they are the only surviving
-- record of a deleted run, which is the entire reason `ottoq_proposal_disposition_ledger`
-- is `class='evidence'` with deliberately **no FK** to `ottoq_sim_runs`.
--
-- **An inner join to `ottoq_sim_runs` re-imposes exactly the foreign key the registry
-- forbids, at query time, silently.** `ottoq_check_run_scope_registry` check (b) requires
-- an FK for `engine`/`stamp` only, and 0340/0364/0374/0378 each record that an enforcing
-- FK on evidence "can only block the purge or, as CASCADE, erase what check (c) forbids
-- erasing". A join does neither of those -- it just omits, with no error and no warning,
-- and the omitted rows are precisely the purge survivors.
--
-- This is not hypothetical and it is not rare: **the natural analysis wants the run's
-- seed, scenario and tick count**, and those live only in `ottoq_sim_runs`. So every
-- future reader of every ledger built tonight has the same pull toward the same join.
--
-- ══ 2. AND IT ALREADY CORRUPTED A NUMBER I QUOTED ═══════════════════════════
--
-- `ottoq_proposer_scorecard` reports `greedy_constrained` at **35.30% enacted**, up from
-- `db/checks/0266`'s 22.52%, and I read the rise as improvement. It is not. Broken out:
--
--   experiment                                   runs   disp   enacted%
--   seed 777777, 1,260 ticks — the demo run         1    108    **24.1**
--   seed 171717, 12 ticks — certification arms      8    728    **37.4**
--   seed 777777, 1,245 ticks — PURGED, evidence only 1     11      9.1
--
-- **728 rows of twelve-tick certification arms outvote the demo run seven to one** and
-- pull the headline up eleven points. The run that represents actual operation says
-- 24.1%. Same defect class as `0266` §1(d) (denominators not comparable populations) and
-- `0250` (an unscoped aggregate answering a different question).
--
-- **One genuinely good thing fell out of the same breakdown:** those eight arms agree at
-- **exactly 91 dispositions / 34 enacted, every time.** Identical inputs, identical
-- proposal dispositions, across four separate pairs. That is determinism evidence at a
-- level which is **not** one of the fourteen enforced atoms, and it is worth knowing we
-- have it.
--
-- ══ 3. WHAT THIS INSTALLS, AND WHY IN THE DATABASE ══════════════════════════
--
-- `ottoq_evidence_join_loss(pattern)` reports, per evidence table, how many rows a naive
-- inner join to `ottoq_sim_runs` would drop. In the database rather than in `scripts/`
-- because the hazard is a SQL-shaped hazard: the person about to write the bad join is
-- already in a SQL session, and a guard they have to remember to run from a shell is a
-- guard that does not fire. `ottoq_evidence_join_loss_now` is the standing reading.
--
-- It defaults to `ottoq\_%`, which covers the four live ledgers. The registry holds
-- **179** evidence tables, 62 of them the `proof*/cert*/smoke*/build*` scratch set
-- CLAUDE.md's Known Hazards says still awaits classification -- auditing those by default
-- would bury the four that are read.
--
-- **The function does not forbid the join.** It cannot: sometimes restricting to live
-- runs is exactly what a caller wants. It makes the cost of the join a number, so the
-- choice is deliberate — the same posture as 0370 and 0374, measure before enforcing.

-- ══ PREFLIGHT ═══════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_ev int;
BEGIN
  SELECT count(DISTINCT table_name) INTO v_ev
    FROM public.ottoq_run_scope_registry WHERE class = 'evidence';
  IF v_ev = 0 THEN
    RAISE EXCEPTION '0380 P1: no evidence-class tables registered -- nothing to guard';
  END IF;
  RAISE NOTICE '0380 P1: % evidence tables registered', v_ev;
END $p1$;

DO $p2$
DECLARE v_total bigint; v_joined bigint;
BEGIN
  --: Assert the hazard is REAL in live data before shipping an instrument for it.
  SELECT count(*) INTO v_total FROM public.ottoq_proposal_disposition_ledger;
  SELECT count(*) INTO v_joined
    FROM public.ottoq_proposal_disposition_ledger l
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = l.sim_run_id;
  IF v_joined >= v_total THEN
    RAISE WARNING '0380 P2: no join loss on the disposition ledger right now (% = %) -- '
                  'the guard still installs; it will read 0 until a run is purged',
                  v_joined, v_total;
  ELSE
    RAISE NOTICE '0380 P2: confirmed -- a naive join drops % of % disposition rows',
                 v_total - v_joined, v_total;
  END IF;
END $p2$;

-- ══ 4. THE GUARD ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_evidence_join_loss(
  p_pattern text DEFAULT 'ottoq\_%')
RETURNS TABLE (
  table_name        text,
  rows_total        bigint,
  rows_with_run     bigint,
  rows_orphaned     bigint,
  join_loss_pct     numeric,
  has_fk_to_sim_runs boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  r      record;
  v_tot  bigint;
  v_run  bigint;
  v_orph bigint;
BEGIN
  FOR r IN
    SELECT DISTINCT reg.table_schema AS sch, reg.table_name AS tbl, reg.column_name AS col
      FROM public.ottoq_run_scope_registry reg
     WHERE reg.class = 'evidence'
       AND reg.table_name LIKE p_pattern
       --: Registered but dropped tables are not a finding; skip rather than raise.
       AND to_regclass(format('%I.%I', reg.table_schema, reg.table_name)) IS NOT NULL
       --: The join hazard needs the joining column to exist.
       AND EXISTS (SELECT 1 FROM information_schema.columns c
                    WHERE c.table_schema = reg.table_schema
                      AND c.table_name  = reg.table_name
                      AND c.column_name = reg.column_name)
     ORDER BY reg.table_name
  LOOP
    EXECUTE format(
      'SELECT count(*), count(%1$I), '
      '       count(*) FILTER (WHERE %1$I IS NOT NULL AND NOT EXISTS ('
      '         SELECT 1 FROM public.ottoq_sim_runs sr WHERE sr.sim_run_id = t.%1$I)) '
      '  FROM %2$I.%3$I t', r.col, r.sch, r.tbl)
      INTO v_tot, v_run, v_orph;

    table_name         := r.tbl;
    rows_total         := v_tot;
    rows_with_run      := v_run;
    rows_orphaned      := v_orph;
    join_loss_pct      := CASE WHEN v_tot > 0
                               THEN round(100.0 * v_orph / v_tot, 2) ELSE NULL END;
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
$function$;

COMMENT ON FUNCTION public.ottoq_evidence_join_loss(text) IS
'0380. Per evidence-class table, how many rows a naive INNER JOIN to ottoq_sim_runs would silently drop. Those rows are the purge survivors -- the only reason the table is class=evidence with deliberately no FK -- so joining to ottoq_sim_runs re-imposes at query time exactly the foreign key ottoq_check_run_scope_registry check (b) forbids, with no error and no warning. FOUND THE HARD WAY: the same question about greedy_constrained''s enactment rate returned 847 rows from the ledger alone and 836 through a join to ottoq_sim_runs, minutes apart; the missing 11 were the only surviving record of purged run 3fb415d8. The pull toward that join is structural, not careless -- seed, scenario and tick_count live ONLY in ottoq_sim_runs, and that is what any real analysis wants. It does NOT forbid the join, because restricting to live runs is sometimes correct; it makes the cost a number so the choice is deliberate. Defaults to ottoq\_% (the four live ledgers) because the registry holds 179 evidence tables, 62 of them the proof*/cert*/smoke*/build* scratch set CLAUDE.md still lists as awaiting classification, and auditing those by default would bury the ones that are read. has_fk_to_sim_runs surfaces the same mistake one layer down: an enforcing FK would block ottoq_purge_prior_runs or, as CASCADE, erase what check (c) forbids erasing.';

CREATE OR REPLACE VIEW public.ottoq_evidence_join_loss_now AS
SELECT * FROM public.ottoq_evidence_join_loss();

COMMENT ON VIEW public.ottoq_evidence_join_loss_now IS
'0380. The standing reading of ottoq_evidence_join_loss() over the four live evidence ledgers. rows_orphaned > 0 means a naive JOIN to ottoq_sim_runs drops that many purge survivors -- read it before quoting any per-seed or per-scenario aggregate over an evidence table. has_fk_to_sim_runs must be false everywhere: true is a registry violation, not a style question.';

-- ══ POSTFLIGHT ══════════════════════════════════════════════════════════════

DO $p3$
DECLARE v_rows int; v_anyfk int; v_loss int;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE has_fk_to_sim_runs),
         count(*) FILTER (WHERE rows_orphaned > 0)
    INTO v_rows, v_anyfk, v_loss
    FROM public.ottoq_evidence_join_loss_now;

  IF v_rows = 0 THEN
    RAISE EXCEPTION '0380 P3: the guard returned no rows -- the pattern matches nothing';
  END IF;
  IF v_anyfk > 0 THEN
    RAISE EXCEPTION '0380 P3: % evidence table(s) carry an FK to ottoq_sim_runs -- that is '
                    'a registry violation (check (b) wants one from engine/stamp only)', v_anyfk;
  END IF;
  RAISE NOTICE '0380 P3: % evidence tables audited, % with live join loss, 0 with an FK',
               v_rows, v_loss;
END $p3$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0380_joining_an_evidence_table_to_sim_runs_silently_undoes_the_reason_it_is_evidence', false,
  'Read-only function plus a view; no tick path and no DDL on any existing table, so no canon is '
  'invalidated. public.ottoq_evidence_join_loss(pattern) reports per evidence-class table how many '
  'rows a naive INNER JOIN to ottoq_sim_runs silently drops -- those rows being the purge '
  'survivors, i.e. the entire reason the table is class=evidence with deliberately no FK. Found by '
  'doing it: the same question about greedy_constrained returned 847 rows from the ledger alone and '
  '836 through a join, minutes apart, the missing 11 being the only surviving record of purged run '
  '3fb415d8. The pull is structural -- seed, scenario and tick_count live only in ottoq_sim_runs. '
  'It does not forbid the join; it prices it. Defaults to ottoq\\_% because 62 of the registry''s '
  '179 evidence tables are the scratch set CLAUDE.md still lists as unclassified. Also surfaced: '
  'ottoq_proposer_scorecard''s 35.30% for greedy_constrained is 728 rows of 12-tick certification '
  'arms outvoting the 108-row demo run seven to one -- the demo run reads 24.1% -- and the eight '
  'arms agree at exactly 91 dispositions / 34 enacted, which is determinism evidence at a level '
  'outside the fourteen atoms.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
