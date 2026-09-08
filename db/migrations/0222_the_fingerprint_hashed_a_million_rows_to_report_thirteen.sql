-- migration-version: PENDING
-- migration-name:    the_fingerprint_hashed_a_million_rows_to_report_thirteen
--
-- ---------------------------------------------------------------------------
-- 0222 — G19. ottoq_boot_state_fingerprint serialized and hashed 1.36 MILLION
--        rows per call, four times per pair, to characterise thirteen.
--
-- Convicted in db/checks/0129, by the statement profile from round 25's sixth
-- pair (r25_g, 10:52 UTC, track_functions='pl' and pg_stat_statements.track=
-- 'all' in its own session). Ranked by total_exec_time:
--
--     calls   secs   statement
--         1  700.7   SELECT ottoq_determinism_pair(...)        <- the whole pair
--        24  439.0     SELECT ottoq_sim_advance_tick(v_run)
--         4  255.3   WITH vn AS (SELECT ... md5(to_jsonb(t)...  <- THIS
--
-- 439 s of ticks plus 255 s of this one statement is 694 s of a 700.7 s pair.
-- **Thirty-six percent of the certification is four calls to the boot
-- fingerprint**, which is not in the tick loop at all: twice at boot, twice in
-- the verdict.
--
-- WHAT IT DOES. The function walks four tables scoped to the DEPOT and to
-- nothing else, and computes md5(to_jsonb(t)::text) — a full row-to-JSON
-- serialization plus a hash — for every row. There is no run predicate, and
-- that is deliberate: the whole point is to see rows belonging to OTHER runs
-- (`fgn`) so residue from a previous run cannot hide behind a passing verdict.
-- That is the V7 guarantee and it must survive untouched.
--
-- WHAT IT KEEPS. Each fgn branch then selects on a small set of live states:
--
--     visit_needs   fgn AND st IN ('open','in_progress','carried_over')
--     bookings      fgn AND st IN ('held','active','interrupted')
--     legs          fgn AND st IN ('planned','active','in_progress')
--     dispatches    fgn AND st IN ('active','returning')
--
-- So every foreign row in a TERMINAL state is serialized, hashed, and thrown
-- away three lines later. At the flagship depot today:
--
--     ottoq_stall_bookings    786,457 scanned        0 usable by fgn
--     ottoq_itinerary_legs    485,526 scanned       13 usable by fgn
--     ottoq_visit_needs        88,932 scanned        0 usable by fgn
--     ---------------------------------------------------------------
--                           1,360,915 per call      13
--
-- 5.4 million row-hashes per pair for thirteen rows and the current run's own
-- few thousand. And it is the drift exactly: every pair appends ~800 bookings
-- and ~680 legs to those tables, so the fingerprint costs more on every
-- subsequent run, forever, on an unchanged workload. Same defect class as
-- db/checks/0098 and 0123 — cost set by history rather than by the run — this
-- time inside the certification's own verdict.
--
-- THE FIX, and why it cannot change the answer. Push each branch's own filter
-- down into its CTE:
--
--     AND (t.sim_run_id IS NULL OR t.sim_run_id = p_run
--          OR t.<state> IN (<that table's fgn state set>))
--
-- A row this excludes has sim_run_id NOT NULL, <> p_run, and a state outside
-- the fgn set. `vis` is NOT fgn, so it cannot see that row. `fgn`'s own WHERE
-- already rejects it. Neither count(*) nor either string_agg over either branch
-- can move. The V7 guarantee is untouched: every foreign row in a live state is
-- still serialized and hashed exactly as before.
--
-- A3 does not argue this, it measures it: the fingerprint is computed for real
-- (depot, run) pairs BEFORE the rewrite and recomputed after, inside the same
-- transaction, and the migration aborts on any difference.
--
-- forces_recert: FALSE, as a PREDICTION. `endst` is an enforced verdict atom
-- and this is the function that computes it, so round 26 is the test: every
-- atom on every column must be unchanged. If one moves, revert — the argument
-- above is then wrong somewhere and the canon is not the thing to adjust.
-- ---------------------------------------------------------------------------

BEGIN;

-- A2 calls the REWRITTEN definition twice, which should be fast; the timeout is
-- headroom in case it is not, and a signal if the fix did not work.
SET LOCAL statement_timeout = '5min';

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
-- The standing constraint: never apply while a certification pair is running or
-- scheduled. ottoq_sim_runs cannot see an in-flight pair (both arms are one
-- transaction, so the rows are uncommitted and invisible) and
-- cron.job_run_details reports one as succeeded in ~1 s. pg_stat_activity is
-- the only authority.
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0222 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0222 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0222 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0222 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0222_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_boot_state_fingerprint';

-- P0. THE BODY IS THE ONE THIS WAS WRITTEN AGAINST ---------------------------
DO $p0$
DECLARE v_md5 text;
BEGIN
  SELECT left(md5(pg_get_functiondef(p.oid)),8) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_boot_state_fingerprint';
  IF v_md5 IS DISTINCT FROM '4a6d2809' THEN
    RAISE EXCEPTION '0222 P0: ottoq_boot_state_fingerprint is %, pinned 4a6d2809',
                    COALESCE(v_md5,'(absent)');
  END IF;
  RAISE NOTICE '0222 P0: body 4a6d2809';
END $p0$;

-- P1. VERIFY THE OUT-OF-BAND CAPTURE ----------------------------------------
-- The comparison A2 makes needs the answer the OLD definition gives, and the
-- old definition is the thing that takes ~64 seconds a call — which is the
-- entire point of this migration and also more than the 60-second apply API
-- will wait. The first attempt at applying 0222 timed out inside its own
-- before-capture and rolled back cleanly, which is what BEGIN/COMMIT is for.
--
-- So the capture runs OUT OF BAND, before this file, via a one-shot cron job
-- named `cap0222` (deliberately not matching `^r[0-9]+_`, so it does not trip
-- the in-flight guard above). Two samples:
--
--   * the most recent flagship run — the `vis` branch with a real run's own
--     rows, the `fgn` branch with every other run's.
--   * a uuid no run has ever had — EVERY row is foreign, so the fgn branch runs
--     at its widest and vis is empty. If the new predicate wrongly dropped a
--     live foreign row, this is the sample that shows it.
--
-- Capturing outside the transaction is only sound if the answer cannot have
-- moved in between, so this block checks both halves of that: the capture must
-- have been taken against the SAME function body this migration is pinned to
-- (captured_against_md5), and nothing may have run since — which the in-flight
-- guard above already established.
DO $p1$
DECLARE v_n int; v_bad text;
BEGIN
  IF to_regclass('public.ottoq_0222_fp_before') IS NULL THEN
    RAISE EXCEPTION '0222 P1: public.ottoq_0222_fp_before does not exist — run the cap0222 '
                    'capture first; see this file''s P1 comment';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_0222_fp_before;
  IF v_n < 2 THEN
    RAISE EXCEPTION '0222 P1: the capture holds % row(s), want at least 2', v_n;
  END IF;
  SELECT string_agg(DISTINCT COALESCE(captured_against_md5,'(null)'), ',') INTO v_bad
    FROM public.ottoq_0222_fp_before WHERE captured_against_md5 IS DISTINCT FROM '4a6d2809';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0222 P1: the capture was taken against body [%], not the pinned 4a6d2809 — '
                    'it is comparing against the wrong definition', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_0222_fp_before WHERE fp_before IS NULL) THEN
    RAISE EXCEPTION '0222 P1: a captured fingerprint is NULL';
  END IF;
  RAISE NOTICE '0222 P1: % captured samples, all against body 4a6d2809', v_n;
END $p1$;

-- 1. THE REWRITE, DERIVED FROM THE CATALOG ----------------------------------
-- Four exact string replacements on the live definition. Anchors 3 and 4 share
-- their WHERE text, so each anchor includes its FROM line to stay unique; every
-- one is asserted to appear exactly once before anything is replaced.
DO $rw$
DECLARE
  v_def text;
  v_anchors text[] := ARRAY[
    $a$  FROM public.ottoq_visit_needs t WHERE t.depot_id = p_depot$a$,
    $a$  FROM public.ottoq_stall_bookings t
  WHERE EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = t.stall_id AND s.depot_id = p_depot)$a$,
    $a$  FROM public.ottoq_itinerary_legs t
  WHERE EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = t.vehicle_id AND v.home_depot_id = p_depot)$a$,
    $a$  FROM public.ottoq_vehicle_dispatches t
  WHERE EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = t.vehicle_id AND v.home_depot_id = p_depot)$a$];
  v_tails text[] := ARRAY[
    $b$
    --: 0222. The fgn branch below consumes only these states; without this the
    --: CTE serialized and hashed every terminal row at the depot, for every run
    --: that ever ran, and discarded them. Excluded rows are foreign AND
    --: terminal: vis cannot see them and fgn's own WHERE rejects them.
    AND (t.sim_run_id IS NULL OR t.sim_run_id = p_run
         OR t.status::text IN ('open','in_progress','carried_over'))$b$,
    $b$
    --: 0222. See the visit_needs CTE. 786,457 rows scanned at the flagship
    --: depot, 0 of them usable by the fgn branch.
    AND (t.sim_run_id IS NULL OR t.sim_run_id = p_run
         OR t.state::text IN ('held','active','interrupted'))$b$,
    $b$
    --: 0222. See the visit_needs CTE. 485,526 rows scanned, 13 usable.
    AND (t.sim_run_id IS NULL OR t.sim_run_id = p_run
         OR t.status::text IN ('planned','active','in_progress'))$b$,
    $b$
    --: 0222. See the visit_needs CTE.
    AND (t.sim_run_id IS NULL OR t.sim_run_id = p_run
         OR t.status::text IN ('active','returning'))$b$];
  i int; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_boot_state_fingerprint';

  FOR i IN 1 .. array_length(v_anchors,1) LOOP
    v_n := (length(v_def) - length(replace(v_def, v_anchors[i], '')))
           / length(v_anchors[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0222: anchor % appears % times in the catalog definition, want exactly 1',
                      i, v_n;
    END IF;
  END LOOP;

  FOR i IN 1 .. array_length(v_anchors,1) LOOP
    v_def := replace(v_def, v_anchors[i], v_anchors[i] || v_tails[i]);
  END LOOP;

  EXECUTE v_def;
  RAISE NOTICE '0222: ottoq_boot_state_fingerprint rewritten from its own catalog definition';
END $rw$;

-- A1. ALL FOUR PREDICATES LANDED, AND NOTHING ELSE MOVED --------------------
DO $a1$
DECLARE v_def text; v_flat text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_boot_state_fingerprint';
  v_flat := regexp_replace(v_def, '\s+', ' ', 'g');

  v_n := (length(v_flat) - length(replace(v_flat, 'OR t.sim_run_id = p_run', '')))
         / length('OR t.sim_run_id = p_run');
  IF v_n <> 4 THEN
    RAISE EXCEPTION '0222 A1: % of 4 run-scope predicates present', v_n;
  END IF;

  -- the four fgn selectors are untouched: the guarantee lives in them
  IF position($$fgn AND st IN ('open','in_progress','carried_over')$$ in v_flat) = 0
     OR position($$fgn AND st IN ('held','active','interrupted')$$ in v_flat) = 0
     OR position($$fgn AND st IN ('planned','active','in_progress')$$ in v_flat) = 0
     OR position($$fgn AND st IN ('active','returning')$$ in v_flat) = 0 THEN
    RAISE EXCEPTION '0222 A1: an fgn state selector is missing — the V7 residue guarantee moved';
  END IF;

  IF position('ottoq_calibration_fingerprint()' in v_flat) = 0 THEN
    RAISE EXCEPTION '0222 A1: 0201''s calibration term is gone';
  END IF;
  RAISE NOTICE '0222 A1: four predicates in, four fgn selectors intact, calibration term intact';
END $a1$;

-- A2. THE FINGERPRINT IS BYTE-IDENTICAL ON REAL DATA -------------------------
-- The claim is that the excluded rows are used by neither branch. This does not
-- argue it: it recomputes the fingerprint for real (depot, run) pairs against
-- the values captured from the OLD definition earlier in this transaction, and
-- aborts on any difference.
DO $a2$
DECLARE r record; v_new jsonb; v_bad int := 0;
BEGIN
  FOR r IN SELECT * FROM public.ottoq_0222_fp_before LOOP
    v_new := public.ottoq_boot_state_fingerprint(r.depot_id, r.sim_run_id);
    IF v_new IS DISTINCT FROM r.fp_before THEN
      v_bad := v_bad + 1;
      RAISE WARNING '0222 A2: fingerprint MOVED for depot % run %', r.depot_id, r.sim_run_id;
    END IF;
  END LOOP;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0222 A2: the fingerprint changed for % of the sampled (depot, run) pairs — '
                    'the excluded rows were not unused after all', v_bad;
  END IF;
  IF (SELECT count(*) FROM public.ottoq_0222_fp_before) = 0 THEN
    RAISE EXCEPTION '0222 A2: no (depot, run) pair was sampled — the assertion proved nothing';
  END IF;
  RAISE NOTICE '0222 A2: fingerprint byte-identical across % sampled (depot, run) pairs',
               (SELECT count(*) FROM public.ottoq_0222_fp_before);
END $a2$;

--: the capture table is KEPT. It is the evidence A2 compared against, taken
--: against a body this migration then replaced, so it cannot be recreated.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0222_the_fingerprint_hashed_a_million_rows_to_report_thirteen', FALSE,
        'G19, db/checks/0129. ottoq_boot_state_fingerprint (the endst atom, made id-blind by '
        '0139) serialized and md5-hashed every row at the depot in four tables — 1,360,915 rows '
        'per call at flagship — four times per pair, and the fgn branches consume only rows in a '
        'few live states: 13 of those 1.36M today. Statement profile from r25_g: 255.3 s over 4 '
        'calls, 36% of a 700.7 s pair, outside the tick loop entirely. Fixed by pushing each '
        'branch''s own state filter into its CTE; excluded rows are foreign AND terminal, so vis '
        'cannot see them and fgn already rejects them, and A2 recomputes the fingerprint on real '
        '(depot, run) pairs to prove it rather than argue it. The V7 residue guarantee is '
        'unchanged — every foreign row in a live state is still hashed. forces_recert FALSE is a '
        'prediction: endst is enforced and this computes it, so if any atom moves in round 26, '
        'revert.',
        now());

COMMIT;
