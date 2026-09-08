-- migration-version: APPLIED-NO-LEDGER-ROW
-- migration-name:    a_production_run_does_not_recall_on_a_parked_implementation
-- (applied through execute_sql, which writes no supabase_migrations row; the
--  file's own APPLIED footer is the record. See task G18.)
-- ---------------------------------------------------------------------------
-- 0210 — the recall registry has a status column and the wrapper never read it.
--
-- WHY (db/checks/0121 Q5, recorded there as an open observation rather than
-- fixed in a documentation commit):
--
-- 0206 made the Recall Decision swappable in the database the way recall/ is in
-- Python: ottoq_evaluate_return_need reads recall_implementation_id from the
-- run's policy, looks the row up in ottoq_recall_implementations, and EXECUTEs
-- whatever evaluator_function that row names. That is genuinely dynamic — it is
-- not a name stamped onto a decision the wrapper made itself — and it is the
-- reason C9's "config-swappable with zero call-site changes" is a fact here and
-- not a claim.
--
-- The registry also carries `status`, and the wrapper selected the row by
-- impl_id alone:
--
--     naive_threshold_v1   active   ottoq_recall_naive_threshold_v1
--     fixed_window_dummy   parked   ottoq_recall_fixed_window_dummy
--
-- fixed_window_dummy exists to PROVE the swap. Its own evidence payload says
-- so ("the swap proof"). It recalls everything inside a fixed window and the
-- catalog entry for the parameter calls it the swap proof in as many words. A
-- production run that set recall_implementation_id = 2 would have recalled real
-- assets on it, and the wrapper computes data_source ('production' vs 'twin')
-- eleven lines further down, so the information to refuse was already in hand
-- and simply not consulted.
--
-- WHAT THIS DOES. One condition, before dispatch: a run whose ottoq_sim_runs
-- .run_by is 'production_live' may not recall on an implementation the registry
-- does not call active. It raises SQLSTATE OQ210 naming the implementation and
-- its status.
--
-- WHAT THIS DELIBERATELY DOES NOT DO.
--   * It does not refuse a non-active implementation on a TWIN run. That would
--     delete the swap proof to protect production, and the swap proof is the
--     evidence that the Recall Decision is an interface rather than a function.
--     Probe A4 asserts the dummy still runs on a twin run.
--   * It does not consult status when the implementation IS active, so the
--     certification path executes exactly the statements it executed before.
--     Absent condition, absent work: the EXISTS on ottoq_sim_runs is inside the
--     status test, so a run on impl 1 does not even pay for the lookup.
--   * It does not touch the cert harness. A cert run naming impl 2 would move
--     that column's canon, which is true of every policy parameter and is the
--     harness's business (0152 quiesces the proposer the same way). Recorded,
--     not fixed here.
--
-- HOW. Catalog-derived rewrite, not a transcription: the body is read with
-- pg_get_functiondef, pinned by md5, the dispatch line is asserted to appear
-- exactly once, and the guard is spliced in front of it. The resulting md5 is
-- itself pinned, so the rewrite either produces the body that was probed or it
-- fails.
--
-- MD5 PINS
--   ottoq_evaluate_return_need   53018872b12d8032f8728851dff719e7
--                             -> 36e7abd739ae947209c028e59c31b69c
--   ottoq_recall_naive_threshold_v1   cd3ffc2ad5c6f18f391c753e8bda42f1  (untouched)
--   ottoq_recall_fixed_window_dummy   3d6d024aa0b547416f64205930e2fa68  (untouched)
--
-- PREDICTION, written before the probe ran, and all four held:
--   A1  the dispatch anchor appears exactly once
--   A2  A/B over four replayed decisions is byte-identical under impl 1
--   A3  impl 2 on a production run raises OQ210
--   A4  impl 2 on a twin run still returns the dummy's decision
--
-- PROBE READINGS 2026-09-08 (one transaction, rolled back by SQLSTATE OQPRB):
--   dispatches_activated = 5   anchor = 1   new_md5 = 36e7abd7…
--   A2  ab_identical = t, distinct_outcomes = 4, reached_ladder = 4
--       (the first attempt reached the ladder ZERO times out of six: every
--        replayed run is finished, so ottoq_evaluate_return_need returned
--        'no active dispatch in run' before touching a rung, and an A/B over
--        six identical early returns proves nothing. The probe now flips those
--        dispatches to 'active' inside the rolled-back transaction so the
--        rungs actually run. This is why the reading is 4 replays and not 6.)
--   A3  OQ210 raised
--   A4  ok — (t, fixed_window, scheduled, …, "why": "the swap proof: …")
--
-- forces_recert: FALSE. No canon hashes a function definition (0121 Q1 style
-- sweep: no cert/determinism/fingerprint function calls pg_get_functiondef),
-- and under the active implementation the decide path is byte-identical, as A2
-- measured rather than argued.
-- ---------------------------------------------------------------------------

BEGIN;

-- PRECONDITIONS ------------------------------------------------------------
DO $pre$
DECLARE v_def text; v_n int; v_anchor text;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ '^r[0-9]+_') THEN
    RAISE EXCEPTION '0210: a certification round is scheduled; migrations wait for the round';
  END IF;
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0210: a sim run is in flight';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE query ILIKE '%ottoq_determinism_pair%' AND pid <> pg_backend_pid()) THEN
    RAISE EXCEPTION '0210: a determinism pair is executing';
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_evaluate_return_need';
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0210: ottoq_evaluate_return_need does not exist';
  END IF;
  IF md5(v_def) <> '53018872b12d8032f8728851dff719e7' THEN
    RAISE EXCEPTION '0210: ottoq_evaluate_return_need is not at the pinned 53018872 (found %). '
                    'Something changed it since 0206; re-read before rewriting.', md5(v_def);
  END IF;

  v_anchor := '  EXECUTE format(''SELECT * FROM public.%I($1, $2, $3, $4, $5)''';
  v_n := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0210: the dispatch line appears % times, not once; splicing is unsafe', v_n;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM ottoq_recall_implementations WHERE status = 'active') THEN
    RAISE EXCEPTION '0210: no implementation is registered active; this guard would refuse everything';
  END IF;
  RAISE NOTICE '0210 pre: evaluator pinned at 53018872, dispatch anchor unique, an active implementation exists, nothing in flight';
END $pre$;

-- A1. THE REWRITE ----------------------------------------------------------
DO $rw$
DECLARE v_def text; v_new text; v_anchor text; v_guard text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_evaluate_return_need';

  v_anchor := '  EXECUTE format(''SELECT * FROM public.%I($1, $2, $3, $4, $5)''';
  v_guard := '  IF v_impl.status IS DISTINCT FROM ''active''
     AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                  WHERE r.sim_run_id = p_sim_run_id AND r.run_by = ''production_live'') THEN
    RAISE EXCEPTION USING ERRCODE = ''OQ210'',
      MESSAGE = format(''ottoq_evaluate_return_need: recall implementation %L is registered %L, not active; a production run does not recall real assets on it'', v_impl.implementation, v_impl.status),
      HINT = ''Set recall_implementation_id to an active implementation, or mark this one active in ottoq_recall_implementations.'';
  END IF;

';
  v_new := replace(v_def, v_anchor, v_guard || v_anchor);
  IF md5(v_new) <> '36e7abd739ae947209c028e59c31b69c' THEN
    RAISE EXCEPTION '0210: the spliced body is %, not the probed 36e7abd7. Refusing to install a body '
                    'that is not the one the A/B was measured on.', md5(v_new);
  END IF;
  EXECUTE v_new;
END $rw$;

-- A2. THE GUARD FIRES, AND ONLY WHERE IT SHOULD ----------------------------
--     Both halves, on the real registry rows, without touching a vehicle.
DO $probe$
DECLARE v_ok boolean;
BEGIN
  SELECT pg_get_functiondef('public.ottoq_evaluate_return_need'::regproc) LIKE '%v_impl.status IS DISTINCT FROM%'
    INTO v_ok;
  IF NOT v_ok THEN RAISE EXCEPTION '0210 A2: the status test is not in the installed body'; END IF;

  SELECT pg_get_functiondef('public.ottoq_evaluate_return_need'::regproc) LIKE '%production_live%'
    INTO v_ok;
  IF NOT v_ok THEN RAISE EXCEPTION '0210 A2: the production test is not in the installed body'; END IF;
  RAISE NOTICE '0210 A2: guard installed, gated on status AND production_live';
END $probe$;

-- A3. THE REGISTRY IS UNCHANGED -------------------------------------------
DO $reg$
DECLARE v_rows int;
BEGIN
  SELECT count(*) INTO v_rows FROM ottoq_recall_implementations;
  IF v_rows <> 2 THEN RAISE EXCEPTION '0210 A3: registry has % rows, expected 2', v_rows; END IF;
  IF NOT EXISTS (SELECT 1 FROM ottoq_recall_implementations
                  WHERE implementation = 'naive_threshold_v1' AND status = 'active') THEN
    RAISE EXCEPTION '0210 A3: naive_threshold_v1 is not active';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM ottoq_recall_implementations
                  WHERE implementation = 'fixed_window_dummy' AND status = 'parked') THEN
    RAISE EXCEPTION '0210 A3: fixed_window_dummy is not parked';
  END IF;
  RAISE NOTICE '0210 A3: registry unchanged — naive_threshold_v1 active, fixed_window_dummy parked';
END $reg$;

-- LINEAGE ------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0210_a_production_run_does_not_recall_on_a_parked_implementation', FALSE,
        'ottoq_evaluate_return_need refuses a recall implementation the registry does not call '
        'active WHEN the run is production_live (SQLSTATE OQ210); 53018872 -> 36e7abd7. The twin '
        'swap proof is deliberately untouched — refusing the parked dummy everywhere would delete '
        'the evidence that the Recall Decision is an interface. Under the active implementation '
        'the decide path is byte-identical, measured not argued: an A/B over four replayed '
        'decisions that reach the rung ladder, run in a rolled-back transaction before this '
        'migration was written.',
        now());

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 to gxdrcyphqjzjsuhxuqtg. Catalog-verified after commit:
--
--   ottoq_evaluate_return_need        36e7abd739ae947209c028e59c31b69c
--                                     (exactly the body the A/B was run on)
--   ottoq_recall_naive_threshold_v1   cd3ffc2ad5c6f18f391c753e8bda42f1  unmoved
--   ottoq_recall_fixed_window_dummy   3d6d024aa0b547416f64205930e2fa68  unmoved
--   ottoq_cert_lineage 0210           forces_recert = false
--   ottoq_cert_recert_floor()         2026-09-07 21:36:53.363037+00  UNMOVED —
--       still 0208's floor, which is the point: no canon moves here
--   ottoq_recall_decisions            8390, unchanged (the probes ran under
--                                     ottoq.dryrun = on and wrote nothing)
--
-- THE PROBE LEFT NOTHING BEHIND, and that was checked rather than assumed:
--   ottoq_policy_params rows for recall_implementation_id   0
--   ottoq_vehicle_dispatches with status 'active'           0
-- Both are counts of things the rolled-back probe created — two policy rows and
-- five reactivated dispatches. A rollback that silently half-committed would
-- show up here as a non-zero, and a fabricated 'active' dispatch surviving into
-- the live world would be a genuinely dangerous piece of litter: the decide path
-- reads exactly that predicate.
--
-- WHAT A LATER READER SHOULD DO WITH THIS. The guard is one condition and it is
-- worth knowing what it does NOT cover. A cert_harness run may still name the
-- parked implementation, and would move that column's canon — true of every
-- policy parameter, and the harness's business rather than this function's.
-- An operator_demo run may too. The line drawn here is the one that matters:
-- real assets, recalled for real, on an evaluator the registry does not stand
-- behind.
-- ---------------------------------------------------------------------------
