-- migration-version: 20260914134225
-- migration-name:    0307_the_dial_audit_reads_functions_and_never_looked_at_a_view
--
-- 0307  THE DIAL AUDIT READS FUNCTIONS, AND NEVER LOOKED AT A VIEW
--
-- Third instance of the same defect in the same instrument, and the one that
-- matters most because the instrument is now load-bearing.
--
--   0291  reported gap 35. The truth was 37 -- a non-overlapping global regex
--         swallowed two NESTED calls.
--   0296  fixed that, and added a census so an unparsed call site is COUNTED
--         rather than silently dropped.
--   0307  the scan reads pg_proc AND NOTHING ELSE. A dial read by a VIEW is
--         invisible to it, and is reported as DEAD.
--
-- ---------------------------------------------------------------------------
-- WHAT IT IS WRONG ABOUT, MEASURED
--
-- public.ottoq_approach_band is a VIEW, and it reads three dials:
--
--   approach_freeze_minutes        zone A/B boundary
--   approach_horizon_minutes       outer edge of the re-optimisation window
--   approach_stale_heartbeat_sec   zone C hardware-fault detection
--
-- ottoq_policy_catalog_gap calls all three `catalogued_unread` -- its word for
-- a dial nothing reads. They are read on every evaluation of that view.
--
-- Exactly ONE view in the database reads a dial, and it is the one the
-- instrument is wrong about. A scan that misses a category of reader does not
-- miss it proportionally; it misses ALL of it.
--
-- ---------------------------------------------------------------------------
-- WHY THIS IS NOT COSMETIC ANY MORE
--
-- `catalogued_unread` is a DELETE LIST. It is the column a reader consults to
-- decide a dial is dead and its catalog row can go. Acting on today's eight
-- would have removed three rows that a live view depends on for its band
-- boundaries -- and with them the bounds that keep those values sane.
--
-- Two things would have caught it, and it is worth naming both because they
-- are the layers built earlier today:
--   * 0305's FOREIGN KEY: each of the three has one live row in
--     ottoq_policy_params, so DELETE on the catalog row raises 23503. The
--     constraint would have refused the delete even though the instrument
--     recommended it.
--   * and nothing else would have. There is no test over this view.
--
-- So the FK earned itself here, on the first day, against a delete that the
-- engine's own audit view would have justified.
--
-- ---------------------------------------------------------------------------
-- THE FIX
--
-- `src` becomes functions UNION views. Both instruments share the change:
-- ottoq_policy_catalog_gap (which keys the verdict) and
-- ottoq_policy_read_site_census (which counts what the regex could not parse).
-- A view contributes its pg_get_viewdef text, labelled `schema.name (view)` so
-- a reader can tell at a glance which kind of object holds the call site.
-- Matviews are included on the same terms; there are none today that match,
-- and the label says (matview) if one ever does.
--
-- NOT NAME-EXCLUDED, deliberately. The obvious worry is that the two
-- instrument views contain the literal REGEX TEXT `ottoq_policy_get\s*\(...`
-- and would match themselves. They do not: after `ottoq_policy_get` the
-- pattern requires `\s*\(`, i.e. optional whitespace then a LITERAL open
-- paren, and what follows in the stored view text is a backslash. Tested
-- empirically before writing this file, and asserted in P3 and A5 rather than
-- left as reasoning -- because "I thought about it and it should be fine" is
-- how 0231's table comment came to claim a protection that never existed.
--
-- ---------------------------------------------------------------------------
-- EXPECTED EFFECT, PREDICTED BEFORE APPLYING (each measured by running the new
-- definition as a plain query first)
--   gap status 'ok'                     152 -> 155
--   gap status 'catalogued_unread'        8 ->   5
--   gap status 'read_uncatalogued'        0 ->   0   (unchanged)
--   catalog rows                        160 -> 160   (this file inserts none)
--   census gains                        public.ottoq_approach_band (view),
--                                       3 call sites, 3 parsed, 0 unparsed
--   functions with unparsed call sites    3 ->   3   (unchanged)
--
-- AND THE FIVE THAT ARE GENUINELY UNREAD AFTERWARDS, which is the real output
-- of this file -- a delete list that can now be trusted:
--   cuopt_contention_min   111 live rows, no reader. Dies with the cuOpt cut.
--   reopt_cooldown_min     ) all three document a "reservation re-optimizer"
--   reopt_max_per_tick     ) that does not exist in this database; 0 live rows.
--   reopt_min_eta_min      )
--   wash_cadence_cycles    0 live rows; the engine reads the cadence from
--                          vehicles.config, not from a dial.
-- None is deleted here. This file fixes the INSTRUMENT; acting on its output
-- is a separate decision with its own evidence.
--
-- forces_recert = FALSE. Two reporting views, read by no function and no other
-- view (P1 measures it, as 0296's P1 did), and ottoq_policy_get never consults
-- the catalog, so no value any tick observes can move.
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0307 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0307 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0307 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0307 P-: nothing in flight';
END $inflight$;

-- P0. MD5 GUARD ON BOTH VIEWS.
DO $p0$
DECLARE v_gap text; v_cen text;
BEGIN
  SELECT md5(pg_get_viewdef('public.ottoq_policy_catalog_gap'::regclass, true)),
         md5(pg_get_viewdef('public.ottoq_policy_read_site_census'::regclass, true))
    INTO v_gap, v_cen;
  IF v_gap <> 'b3e12e3b342a98a8b1b5a1d8c61a4f23' THEN
    RAISE EXCEPTION '0307 P0: ottoq_policy_catalog_gap is not the definition this file '
                    'was written against (live md5 %)', v_gap;
  END IF;
  IF v_cen <> '4106a32e6d1383411e3dc94c73113c68' THEN
    RAISE EXCEPTION '0307 P0: ottoq_policy_read_site_census is not the definition this '
                    'file was written against (live md5 %)', v_cen;
  END IF;
  RAISE NOTICE '0307 P0: both view definitions match';
END $p0$;

-- P1. NEITHER INSTRUMENT HAS A CONSUMER. The forces_recert=false argument,
-- executed rather than inherited from 0296.
DO $p1$
DECLARE v_fns text; v_views text; v_getter int;
BEGIN
  SELECT string_agg(n.nspname||'.'||p.proname, ', ') INTO v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.prosrc ~ 'ottoq_policy_catalog_gap|ottoq_policy_read_site_census';
  IF v_fns IS NOT NULL THEN
    RAISE EXCEPTION '0307 P1: functions read the instruments (%); they are no longer '
                    'pure reporting objects and forces_recert must be re-argued', v_fns;
  END IF;

  SELECT string_agg(DISTINCT dn.nspname||'.'||dv.relname, ', ') INTO v_views
    FROM pg_depend d
    JOIN pg_rewrite r  ON r.oid = d.objid
    JOIN pg_class   dv ON dv.oid = r.ev_class
    JOIN pg_namespace dn ON dn.oid = dv.relnamespace
    JOIN pg_class   sv ON sv.oid = d.refobjid
   WHERE sv.relname IN ('ottoq_policy_catalog_gap','ottoq_policy_read_site_census')
     AND dv.relname NOT IN ('ottoq_policy_catalog_gap','ottoq_policy_read_site_census');
  IF v_views IS NOT NULL THEN
    RAISE EXCEPTION '0307 P1: views depend on the instruments (%)', v_views;
  END IF;

  SELECT count(*) INTO v_getter
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get'
     AND p.prosrc ~ 'ottoq_policy_param_catalog';
  IF v_getter > 0 THEN
    RAISE EXCEPTION '0307 P1: ottoq_policy_get now reads the catalog; the '
                    'forces_recert=false argument for every catalog file is void';
  END IF;
  RAISE NOTICE '0307 P1: no consumer; ottoq_policy_get still ignores the catalog';
END $p1$;

-- P2. THE DEFECT IS REAL AND REPRODUCES. The view reads the three dials, and
-- the instrument calls all three dead. Without this the file fixes nothing.
DO $p2$
DECLARE v_def text; v_dead int; k text;
BEGIN
  SELECT pg_get_viewdef('public.ottoq_approach_band'::regclass, true) INTO v_def;
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0307 P2: public.ottoq_approach_band is not a view any more';
  END IF;
  FOREACH k IN ARRAY ARRAY['approach_freeze_minutes','approach_horizon_minutes',
                           'approach_stale_heartbeat_sec'] LOOP
    IF position('ottoq_policy_get' in v_def) = 0 OR position(''''||k||'''' in v_def) = 0 THEN
      RAISE EXCEPTION '0307 P2: the view no longer reads %; the premise is stale', k;
    END IF;
  END LOOP;
  SELECT count(*) INTO v_dead FROM public.ottoq_policy_catalog_gap
   WHERE status = 'catalogued_unread'
     AND param_key IN ('approach_freeze_minutes','approach_horizon_minutes',
                       'approach_stale_heartbeat_sec');
  IF v_dead <> 3 THEN
    RAISE EXCEPTION '0307 P2: the instrument calls % of the 3 view-read dials dead, '
                    'expected 3 -- the defect does not reproduce', v_dead;
  END IF;
  RAISE NOTICE '0307 P2: the view reads all three, and the instrument calls all three dead';
END $p2$;

-- P3. THE INSTRUMENT VIEWS DO NOT MATCH THEIR OWN REGEX LITERAL. If they did,
-- scanning views would invent param keys out of the instrument's own source.
-- Asserted, not reasoned about.
DO $p3$
DECLARE v_self int;
BEGIN
  SELECT count(*) INTO v_self
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
         LATERAL regexp_matches(pg_get_viewdef(c.oid, true),
           'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''', 'g') AS m
   WHERE c.relkind IN ('v','m') AND n.nspname = 'public'
     AND c.relname IN ('ottoq_policy_catalog_gap','ottoq_policy_read_site_census');
  IF v_self > 0 THEN
    RAISE EXCEPTION '0307 P3: the instrument views self-match % time(s); scanning views '
                    'would fabricate param keys from the instrument''s own text', v_self;
  END IF;
  RAISE NOTICE '0307 P3: no self-match -- the regex literal is not a call site';
END $p3$;

-- ===========================================================================
-- THE TWO INSTRUMENTS, src extended to functions UNION views
-- ===========================================================================

CREATE OR REPLACE VIEW public.ottoq_policy_catalog_gap AS
WITH src AS (
  SELECT (n.nspname::text || '.'::text) || p.proname::text AS fn, p.prosrc AS body
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = ANY (ARRAY['public'::name, 'twin'::name, 'ottoq'::name])
  UNION ALL
  -- 0307: A DIAL READ BY A VIEW IS STILL A READ DIAL. Labelled so a reader can
  -- see which kind of object holds the call site.
  SELECT (n.nspname::text || '.'::text) || c.relname::text ||
         CASE WHEN c.relkind = 'm' THEN ' (matview)' ELSE ' (view)' END,
         pg_get_viewdef(c.oid, true)
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE c.relkind IN ('v','m')
     AND n.nspname = ANY (ARRAY['public'::name, 'twin'::name, 'ottoq'::name])
), literal_reads AS (
  SELECT s.fn, m[1] AS param_key
    FROM src s,
         LATERAL regexp_matches(s.body,
           'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''', 'g') AS m
), dynamic_reads AS (
  SELECT 'public.ottoq_intelligence_sources(gate_param_key)'::text AS fn,
         i.gate_param_key AS param_key
    FROM public.ottoq_intelligence_sources i
   WHERE i.gate_param_key IS NOT NULL
), all_reads AS (
  SELECT fn, param_key FROM literal_reads
  UNION
  SELECT fn, param_key FROM dynamic_reads
), caller_defaults AS (
  SELECT m[1] AS param_key,
         array_agg(DISTINCT btrim(m[2]) ORDER BY btrim(m[2])) AS defaults
    FROM src s,
         LATERAL regexp_matches(s.body,
           'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''\s*,\s*([^)]*)\)', 'g') AS m
   GROUP BY m[1]
), read_keys AS (
  SELECT a.param_key, count(DISTINCT a.fn) AS readers,
         array_agg(DISTINCT a.fn ORDER BY a.fn) AS reader_functions
    FROM all_reads a GROUP BY a.param_key
), rows_per_key AS (
  SELECT pp.param_key, count(*) AS live_rows
    FROM public.ottoq_policy_params pp GROUP BY pp.param_key
)
SELECT COALESCE(r.param_key, c.param_key) AS param_key,
       CASE WHEN r.param_key IS NULL THEN 'catalogued_unread'::text
            WHEN c.param_key IS NULL THEN 'read_uncatalogued'::text
            ELSE 'ok'::text END AS status,
       COALESCE(r.readers, 0::bigint) AS readers,
       COALESCE(x.live_rows, 0::bigint) AS live_rows,
       c.param_key IS NOT NULL AS catalogued,
       c.min_value, c.max_value, c.default_value,
       d.defaults AS caller_defaults,
       r.reader_functions
  FROM read_keys r
  FULL JOIN public.ottoq_policy_param_catalog c ON c.param_key = r.param_key
  LEFT JOIN rows_per_key x ON x.param_key = COALESCE(r.param_key, c.param_key)
  LEFT JOIN caller_defaults d ON d.param_key = COALESCE(r.param_key, c.param_key);

COMMENT ON VIEW public.ottoq_policy_catalog_gap IS
  '0307: scans FUNCTIONS AND VIEWS for ottoq_policy_get call sites. Before 0307 it '
  'read pg_proc only and reported the three dials of public.ottoq_approach_band -- a '
  'view -- as catalogued_unread, i.e. dead. status=catalogued_unread is a DELETE LIST, '
  'so a blind spot here is a recommendation to remove a live dial. Third fix to this '
  'instrument: 0291 undercounted by 2 on nested calls, 0296 added the unparsed census, '
  '0307 added views. Read it WITH ottoq_policy_read_site_census, which counts the call '
  'sites the regex still cannot parse.';

CREATE OR REPLACE VIEW public.ottoq_policy_read_site_census AS
WITH src AS (
  SELECT (n.nspname::text || '.'::text) || p.proname::text AS fn, p.prosrc AS body
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = ANY (ARRAY['public'::name, 'twin'::name, 'ottoq'::name])
     AND p.prosrc ~ 'ottoq_policy_get\s*\('
  UNION ALL
  SELECT (n.nspname::text || '.'::text) || c.relname::text ||
         CASE WHEN c.relkind = 'm' THEN ' (matview)' ELSE ' (view)' END,
         pg_get_viewdef(c.oid, true)
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE c.relkind IN ('v','m')
     AND n.nspname = ANY (ARRAY['public'::name, 'twin'::name, 'ottoq'::name])
     AND pg_get_viewdef(c.oid, true) ~ 'ottoq_policy_get\s*\('
), call_sites AS (
  SELECT s.fn, count(*) AS n_call_sites
    FROM src s, LATERAL regexp_matches(s.body, 'ottoq_policy_get\s*\(', 'g') AS m
   GROUP BY s.fn
), parsed AS (
  SELECT s.fn, count(*) AS n_parsed
    FROM src s, LATERAL regexp_matches(s.body,
           'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''', 'g') AS m
   GROUP BY s.fn
)
SELECT c.fn, c.n_call_sites,
       COALESCE(p.n_parsed, 0::bigint) AS n_parsed,
       c.n_call_sites - COALESCE(p.n_parsed, 0::bigint) AS n_unparsed
  FROM call_sites c LEFT JOIN parsed p ON p.fn = c.fn;

COMMENT ON VIEW public.ottoq_policy_read_site_census IS
  '0296 + 0307: per-object count of ottoq_policy_get call sites, how many the key regex '
  'could PARSE, and how many it could not. n_unparsed > 0 means a dial key that is a '
  'variable rather than a literal -- ottoq_policy_catalog_gap cannot see those, and this '
  'view is how the gap''s zero stays honest. Scans functions AND views since 0307.';

-- ===========================================================================
-- A1. THE VERDICT MOVED EXACTLY AS PREDICTED.
DO $a1$
DECLARE v_ok int; v_unread int; v_uncat int; v_cat int;
BEGIN
  SELECT count(*) FILTER (WHERE status='ok'),
         count(*) FILTER (WHERE status='catalogued_unread'),
         count(*) FILTER (WHERE status='read_uncatalogued')
    INTO v_ok, v_unread, v_uncat
    FROM public.ottoq_policy_catalog_gap;
  IF v_ok <> 155 THEN RAISE EXCEPTION 'A1 FAILED: ok is %, predicted 155', v_ok; END IF;
  IF v_unread <> 5 THEN RAISE EXCEPTION 'A1 FAILED: catalogued_unread is %, predicted 5', v_unread; END IF;
  IF v_uncat <> 0 THEN RAISE EXCEPTION 'A1 FAILED: read_uncatalogued is %, predicted 0', v_uncat; END IF;
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog;
  IF v_cat <> 160 THEN RAISE EXCEPTION 'A1 FAILED: catalog is % rows; this file inserts none', v_cat; END IF;
  RAISE NOTICE 'A1 OK: ok 152->155, catalogued_unread 8->5, read_uncatalogued 0, catalog 160';
END $a1$;

-- A2. THE THREE ARE ALIVE, AND THE VIEW IS NAMED AS THEIR READER.
DO $a2$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN
    SELECT param_key, status, reader_functions FROM public.ottoq_policy_catalog_gap
     WHERE param_key IN ('approach_freeze_minutes','approach_horizon_minutes',
                         'approach_stale_heartbeat_sec')
  LOOP
    IF r.status <> 'ok' THEN
      RAISE EXCEPTION 'A2 FAILED: % is still %', r.param_key, r.status;
    END IF;
    IF NOT ('public.ottoq_approach_band (view)' = ANY(r.reader_functions)) THEN
      RAISE EXCEPTION 'A2 FAILED: %''s readers are %, and do not name the view',
                      r.param_key, r.reader_functions;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 3 THEN RAISE EXCEPTION 'A2 FAILED: found % of the 3 keys', v_n; END IF;
  RAISE NOTICE 'A2 OK: all three now ok, each naming public.ottoq_approach_band (view)';
END $a2$;

-- A3. THE CENSUS SEES THE VIEW, fully parsed.
DO $a3$
DECLARE v_sites int; v_parsed int; v_unparsed int; v_bad int;
BEGIN
  SELECT n_call_sites, n_parsed, n_unparsed INTO v_sites, v_parsed, v_unparsed
    FROM public.ottoq_policy_read_site_census
   WHERE fn = 'public.ottoq_approach_band (view)';
  IF v_sites IS NULL THEN
    RAISE EXCEPTION 'A3 FAILED: the census still does not list the view';
  END IF;
  IF v_sites <> 3 OR v_parsed <> 3 OR v_unparsed <> 0 THEN
    RAISE EXCEPTION 'A3 FAILED: view census is %/%/%,  predicted 3/3/0',
                    v_sites, v_parsed, v_unparsed;
  END IF;
  SELECT count(*) INTO v_bad FROM public.ottoq_policy_read_site_census WHERE n_unparsed > 0;
  IF v_bad <> 3 THEN
    RAISE EXCEPTION 'A3 FAILED: % objects have unparsed call sites, predicted 3 '
                    '(unchanged by this file)', v_bad;
  END IF;
  RAISE NOTICE 'A3 OK: the view is counted 3/3/0; the unparsed residual is still 3 objects';
END $a3$;

-- A4. THE DELETE LIST IS NOW EXACTLY THE FIVE THAT ARE GENUINELY DEAD. Naming
-- them means a later file cannot quietly widen the list.
DO $a4$
DECLARE v_list text;
BEGIN
  SELECT string_agg(param_key, ', ' ORDER BY param_key) INTO v_list
    FROM public.ottoq_policy_catalog_gap WHERE status = 'catalogued_unread';
  IF v_list IS DISTINCT FROM 'cuopt_contention_min, reopt_cooldown_min, reopt_max_per_tick, '
                             'reopt_min_eta_min, wash_cadence_cycles' THEN
    RAISE EXCEPTION 'A4 FAILED: the unread set is [%], not the five this file named', v_list;
  END IF;
  RAISE NOTICE 'A4 OK: five genuinely unread dials, named';
END $a4$;

-- A5. NO KEY WAS FABRICATED FROM THE INSTRUMENTS' OWN TEXT. P3 asserted the
-- regex does not self-match; this asserts the CONSEQUENCE, on the live view.
DO $a5$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(param_key, ', ') INTO v_bad
    FROM public.ottoq_policy_catalog_gap
   WHERE reader_functions && ARRAY['public.ottoq_policy_catalog_gap (view)',
                                   'public.ottoq_policy_read_site_census (view)'];
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'A5 FAILED: keys attributed to an instrument view (%)', v_bad;
  END IF;
  RAISE NOTICE 'A5 OK: the instruments did not read themselves';
END $a5$;

-- ===========================================================================
-- LINEAGE, written here in the migration.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0307_the_dial_audit_reads_functions_and_never_looked_at_a_view', false,
        'Replaces two reporting views (ottoq_policy_catalog_gap, '
        'ottoq_policy_read_site_census) so their source scan covers VIEWS as well as '
        'functions. No function and no other view reads either instrument (P1 measures '
        'it), and ottoq_policy_get never consults the catalog, so no value any tick '
        'observes can move. The defect fixed: three dials read by the view '
        'public.ottoq_approach_band were reported catalogued_unread -- the column a '
        'reader uses as a delete list.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- A6. THE FLOOR DID NOT MOVE.
DO $a6$
DECLARE v_floor timestamptz;
BEGIN
  SELECT public.ottoq_cert_recert_floor() INTO v_floor;
  IF v_floor <> '2026-09-12 16:50:23.319089+00'::timestamptz THEN
    RAISE EXCEPTION 'A6 FAILED: recert floor moved to %', v_floor;
  END IF;
  RAISE NOTICE 'A6 OK: recert floor unmoved at %', v_floor;
END $a6$;
