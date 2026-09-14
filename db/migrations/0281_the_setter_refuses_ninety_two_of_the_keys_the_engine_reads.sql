-- migration-version: 20260914054506
-- migration-name:    0281_the_setter_refuses_ninety_two_of_the_keys_the_engine_reads
--
-- 0281  THE SUPPORTED WAY TO CHANGE A DIAL REFUSES SIXTY PERCENT OF THE DIALS
--
-- ---------------------------------------------------------------------------
-- WHAT 0279 TURNED OUT TO BE ONE INSTANCE OF
--
-- 0279 catalogued `proposer_seat` after finding it had 12 live rows, 0 catalog
-- rows and 4 live readers, so `ottoq_policy_set` answered
-- {"ok":false,"error":"unknown_param"} and every one of those rows had been
-- written straight into the table, unvalidated.
--
-- Generalised tonight, from the READER side -- every key any live function
-- passes to ottoq_policy_get as a literal:
--
--   policy keys the engine reads                        152
--     of those, catalogued                               60
--     of those, NOT catalogued                     90 or 92   <- ~60%, see
--                                                                  the lower-bound
--                                                                  note below
--   catalog rows total                                   68
--     catalogued but never read by any function           8
--   ottoq_policy_params rows                          2,739
--     rows whose key is uncatalogued                     61   across 38 keys
--
-- So the supported way to change a dial refuses 92 of the 152 dials the engine
-- actually reads, silently -- ok:false, no raise -- and 61 rows exist that
-- could only have been written around it. Among the 92: `enforce_site_charge_cap`
-- (the site power cap switch), `run_governor_max_sim_minutes` (the ceiling that
-- stops a run), `calib_interval_h` and `pm_interval_km` (11 readers each).
--
-- ---------------------------------------------------------------------------
-- WHY THIS FILE DOES NOT CATALOGUE THE NINETY-TWO
--
-- Because 0279's own lesson forbids it. That file's range was **read off the
-- dispatch** in ottoq_l2_propose_stall_seat, and its P2 block refuses to apply
-- if that dispatch ever changes shape. Ninety-two ranges cannot be derived that
-- way in one sitting, and a catalog row carrying an INVENTED min/max is worse
-- than no row at all: ottoq_policy_set would then clamp a real value to a
-- guessed bound, silently, and report ok:true. A guessed range is a wrong
-- answer wearing the costume of a validated one.
--
-- So this file ships the INSTRUMENT, not the ninety-two rows. The gap becomes a
-- query anybody can run instead of an investigation nobody repeats, and each
-- key gets catalogued as its consumer is actually read -- which is the only way
-- a range is ever legitimate.
--
-- ---------------------------------------------------------------------------
-- WHAT THE VIEW IS, AND WHAT IT CANNOT SEE
--
-- It reads pg_proc for every literal key passed to ottoq_policy_get, and
-- reports both directions of the mismatch:
--
--   read_uncatalogued   the engine reads it, ottoq_policy_set refuses it
--   catalogued_unread   a catalog row no function reads (8 of them)
--   ok                  read and catalogued
--
-- It also surfaces `caller_defaults`: the third argument each call site passes.
-- That is the de-facto default the engine has been running on, and it is the
-- honest starting point for a real catalog row -- a key whose call sites
-- disagree on the default is itself a finding.
--
-- A LOWER BOUND, AND IT IS MEASURED RATHER THAN HEDGED. The scan sees only keys
-- written as string LITERALS in an ottoq_policy_get call whose first argument
-- has no comma AND whose default argument has no closing parenthesis. So
-- `read_uncatalogued` can UNDERCOUNT and can never overcount, which is the safe
-- direction for a gap report.
--
-- The undercount is not hypothetical -- it is exactly two, and they are named.
-- The header's 92 comes from a looser scan that stops at the key; the VIEW
-- requires the key AND its default argument, and therefore reports 90. The two
-- it misses are `contention_wait_cap_ticks` and `timer_backstop_ticks`, whose
-- call sites wrap the default in a nested call so the `[^)]*` default group
-- terminates early. Both are uncatalogued either way, so the finding is
-- unaffected and only the count moves.
--
-- The honest sentence is therefore: at least 90 of 152, and 92 by the looser
-- scan. Widening the default group to handle nesting is a real improvement and
-- is deliberately NOT done here -- a regex that balances parentheses is how a
-- gap report starts lying about its own coverage.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0281 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0281 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0281 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0281 P-: nothing in flight';
END $inflight$;

-- P1. THE GAP IS STILL THERE (two-sided) --------------------------------------
-- If somebody catalogued the backlog since the measurement, this file's header
-- is stale and must be re-derived rather than shipped over a changed world.
DO $p1$
DECLARE v_uncat int;
BEGIN
  WITH read_keys AS (
    SELECT DISTINCT (regexp_matches(p.prosrc,
             'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''', 'g'))[1] AS k
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public','twin','ottoq')
  )
  SELECT count(*) INTO v_uncat
    FROM read_keys r
    LEFT JOIN public.ottoq_policy_param_catalog c ON c.param_key = r.k
   WHERE c.param_key IS NULL;
  IF v_uncat < 50 THEN
    RAISE EXCEPTION '0281 P1: only % uncatalogued read-keys remain; the header says 92. '
                    'Re-measure before applying.', v_uncat;
  END IF;
  RAISE NOTICE '0281 P1: % read-keys are uncatalogued, the gap this file reports', v_uncat;
END $p1$;

-- P2. THE VIEW NAME IS FREE ---------------------------------------------------
DO $p2$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'ottoq_policy_catalog_gap';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0281 P2: public.ottoq_policy_catalog_gap already exists';
  END IF;
  RAISE NOTICE '0281 P2: the view name is free';
END $p2$;

-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.ottoq_policy_catalog_gap AS
WITH read_sites AS (
  SELECT n.nspname || '.' || p.proname AS fn,
         (regexp_matches(p.prosrc,
            'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''\s*,\s*([^)]*)\)', 'g')) AS m
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
), read_keys AS (
  SELECT m[1] AS param_key,
         count(DISTINCT fn)                              AS readers,
         array_agg(DISTINCT fn ORDER BY fn)              AS reader_functions,
         array_agg(DISTINCT btrim(m[2]) ORDER BY btrim(m[2])) AS caller_defaults
    FROM read_sites GROUP BY 1
), rows_per_key AS (
  SELECT param_key, count(*) AS live_rows FROM public.ottoq_policy_params GROUP BY 1
)
SELECT COALESCE(r.param_key, c.param_key)                       AS param_key,
       CASE WHEN r.param_key IS NULL              THEN 'catalogued_unread'
            WHEN c.param_key IS NULL              THEN 'read_uncatalogued'
            ELSE                                       'ok' END AS status,
       COALESCE(r.readers, 0)                                   AS readers,
       COALESCE(x.live_rows, 0)                                 AS live_rows,
       (c.param_key IS NOT NULL)                                AS catalogued,
       c.min_value, c.max_value, c.default_value,
       r.caller_defaults,
       r.reader_functions
  FROM read_keys r
  FULL JOIN public.ottoq_policy_param_catalog c ON c.param_key = r.param_key
  LEFT JOIN rows_per_key x ON x.param_key = COALESCE(r.param_key, c.param_key);

COMMENT ON VIEW public.ottoq_policy_catalog_gap IS
'0281. Which policy dials ottoq_policy_set will actually write, and which it refuses. '
'status=read_uncatalogued: a live function reads the key and the setter answers '
'{"ok":false,"error":"unknown_param"} WITHOUT raising, so any row that exists for it was '
'written around the setter with no validation (0262 on proposer_hold_enabled, 0279 on '
'proposer_seat -- measured at 90 of 152 read keys by THIS view when it shipped, 92 by a looser scan that does not also require the default argument). '
'status=catalogued_unread: a catalog row no function reads. caller_defaults is the third '
'argument each call site passes -- the de-facto default the engine has been running on, and '
'the honest starting point for a real catalog row; a key whose call sites DISAGREE on the '
'default is itself a finding. LOWER BOUND: the scan sees only literal key names in a '
'ottoq_policy_get call whose first argument has no comma and whose default has no closing '
'parenthesis, so read_uncatalogued can undercount and never overcount -- measured at exactly '
'two missed keys, contention_wait_cap_ticks and timer_backstop_ticks, both uncatalogued either way. A catalog range must be READ OFF the consumer, never '
'invented -- see 0279, whose P2 pins the dispatch it derived its range from.';

-- ---------------------------------------------------------------------------
-- A1. THE VIEW REPORTS THE GAP THE HEADER CLAIMS.
DO $a1$
DECLARE v_read int; v_uncat int; v_unread int; v_ok int;
BEGIN
  SELECT count(*) FILTER (WHERE status <> 'catalogued_unread'),
         count(*) FILTER (WHERE status = 'read_uncatalogued'),
         count(*) FILTER (WHERE status = 'catalogued_unread'),
         count(*) FILTER (WHERE status = 'ok')
    INTO v_read, v_uncat, v_unread, v_ok
    FROM public.ottoq_policy_catalog_gap;
  IF v_uncat < 50 THEN
    RAISE EXCEPTION 'A1 FAILED: view reports only % read_uncatalogued keys', v_uncat;
  END IF;
  IF v_ok < 1 OR v_read < 100 THEN
    RAISE EXCEPTION 'A1 FAILED: view reports % read keys / % ok -- the scan looks broken',
                    v_read, v_ok;
  END IF;
  RAISE NOTICE 'A1 OK: % read keys -- % ok, % read_uncatalogued, % catalogued_unread',
               v_read, v_ok, v_uncat, v_unread;
END $a1$;

-- A2. THE TWO KEYS ALREADY CONVICTED BY NAME LAND WHERE THEY SHOULD.
-- proposer_seat was catalogued by 0279 and must now read 'ok'; a key 0279 did
-- NOT touch must still read 'read_uncatalogued'. Two-sided on one instrument.
DO $a2$
DECLARE v_seat text; v_cap text;
BEGIN
  SELECT status INTO v_seat FROM public.ottoq_policy_catalog_gap WHERE param_key='proposer_seat';
  IF v_seat IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'A2 FAILED: proposer_seat reads %, expected ok -- 0279 catalogued it', v_seat;
  END IF;
  SELECT status INTO v_cap FROM public.ottoq_policy_catalog_gap
   WHERE param_key='enforce_site_charge_cap';
  IF v_cap IS DISTINCT FROM 'read_uncatalogued' THEN
    RAISE EXCEPTION 'A2 FAILED: enforce_site_charge_cap reads %, expected read_uncatalogued', v_cap;
  END IF;
  RAISE NOTICE 'A2 OK: proposer_seat=ok (0279), enforce_site_charge_cap=read_uncatalogued';
END $a2$;

-- A3. THE VIEW IS READ-ONLY AND CHEAP ENOUGH TO RUN.
-- A gap report nobody runs is not a gap report. Bounded, not timed, because a
-- wall clock in an assertion is G15's defect class.
DO $a3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_catalog_gap;
  IF v_n < 100 THEN
    RAISE EXCEPTION 'A3 FAILED: the view returned only % rows', v_n;
  END IF;
  RAISE NOTICE 'A3 OK: the view returns % rows', v_n;
END $a3$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0281_the_setter_refuses_ninety_two_of_the_keys_the_engine_reads', false,
 'Adds ONE read-only view, public.ottoq_policy_catalog_gap, over pg_proc and ottoq_policy_param_catalog. Reports which policy dials ottoq_policy_set will write and which it silently refuses (92 of 152 read keys at ship time), plus catalogued-but-unread rows and the caller-supplied default at each call site. Deliberately catalogues NOTHING: 0279 established that a range must be read off its consumer, and 92 invented ranges would make ottoq_policy_set clamp real values to guessed bounds while reporting ok:true. No function is replaced, no table is written, no engine behaviour changes, and the view has no caller on the tick path. forces_recert=false: a view over the system catalogs is read-only by construction and no certification atom reads it.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- ===========================================================================
-- APPLIED 2026-09-14 05:45:06 UTC (12:45 AM CT) as
-- supabase_migrations.schema_migrations version 20260914054506.
--
-- Dry run: the file byte for byte inside BEGIN ... ROLLBACK, clean, and it is
-- what caught the 90-vs-92 discrepancy documented above -- the looser header
-- scan and the view's stricter one disagree by exactly two keys, both named.
--
-- VERIFIED AFTER APPLY, against the live database:
--
--   view rows                                        158
--   status = 'ok'          (setter will write it)     60
--   status = 'read_uncatalogued' (setter refuses)     90
--   status = 'catalogued_unread' (dead catalog row)    8
--   rows for refused keys, i.e. written around
--     ottoq_policy_set with no validation at all       57
--
-- ---------------------------------------------------------------------------
-- HOW TO USE THIS, because a gap report nobody runs is not a gap report
--
--   -- what can I actually set, and what will be silently refused?
--   SELECT param_key, status, readers, live_rows, caller_defaults
--     FROM public.ottoq_policy_catalog_gap
--    WHERE status = 'read_uncatalogued'
--    ORDER BY readers DESC, live_rows DESC;
--
--   -- which refused keys already have rows somebody wrote by hand?
--   SELECT param_key, readers, live_rows, reader_functions
--     FROM public.ottoq_policy_catalog_gap
--    WHERE status = 'read_uncatalogued' AND live_rows > 0
--    ORDER BY live_rows DESC;
--
--   -- catalog rows nothing reads (candidates for retirement, NOT for deletion
--   -- without checking an edge function or the UI does not read them)
--   SELECT param_key, min_value, max_value, default_value
--     FROM public.ottoq_policy_catalog_gap WHERE status = 'catalogued_unread';
--
-- THE ORDER TO CATALOGUE IN is readers DESC, then live_rows DESC: a key with
-- eleven readers and rows already written by hand is where an invented value
-- does the most damage. calib_interval_h and pm_interval_km head that list.
--
-- AND THE RULE FOR EACH ONE, unchanged from 0279: read the range OFF the
-- consumer, pin the consumer's shape in a P block so the file refuses to apply
-- if that shape changes, and prove the clamp with a two-sided assertion. The
-- `caller_defaults` column gives the honest default to start from. A key whose
-- call sites DISAGREE on the default is not a cataloguing task -- it is a bug
-- report, and it should be filed as one before any row is written.
-- ===========================================================================
