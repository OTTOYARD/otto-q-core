-- migration-version: 20260914101744
-- migration-name:    0296_the_gap_view_cannot_see_five_of_its_own_call_sites
--
-- 0296  THE GAP VIEW CANNOT SEE FIVE OF ITS OWN CALL SITES
--
-- The instrument that measures how many dials ottoq_policy_set refuses is
-- itself blind, and it is blind in the direction that flatters us: it reports
-- a SMALLER gap than exists. I quoted its number -- "35 left of 92" -- in a
-- task title and in 0291's footer. The measured number is 37.
--
-- ---------------------------------------------------------------------------
-- WHAT THE VIEW DOES AND WHY IT MISSES
--
-- ottoq_policy_catalog_gap finds the keys the engine reads by grepping every
-- function body for calls to ottoq_policy_get. Its regex is
--
--     ottoq_policy_get\s*\(\s*[^,]+,\s*'([a-z0-9_]+)'\s*,\s*([^)]*)\)
--                                                       ^^^^^^^^^^^^
--                                     it insists on capturing the 3rd argument
--
-- and the capture of the third argument is what breaks it, in two ways.
--
-- 1. THE SWALLOW. regexp_matches(..., 'g') does not find overlapping matches.
--    ottoq_recall_naive_threshold_v1 nests one read inside another's default:
--
--      v_wait_cap := ottoq_policy_get(p_sim_run_id,'contention_wait_cap_min',
--                      ottoq_policy_get(p_sim_run_id,'contention_wait_cap_ticks',4) * 30)::int;
--
--    The OUTER match runs from the outer 'ottoq_policy_get(' through the inner
--    call's first ')'. The inner call's own start offset is inside that span,
--    the global scan resumes after it, and the inner key is never emitted.
--    Two keys are lost this way -- contention_wait_cap_ticks and
--    timer_backstop_ticks -- and they are the whole of the 35-vs-37 gap.
--
--    This is the THIRD instance of this defect class in a fortnight. The
--    0286 read-back parser lost night_wave_bands to a character class that
--    excluded digits, and its non-greedy scan then swallowed the next tuple.
--    Same shape: the parser, not the data, was wrong, and the parser failed
--    quietly rather than loudly.
--
-- 2. THE FIRST ARGUMENT IS NOT ALWAYS COMMA-FREE. [^,]+ assumes the run-id
--    expression contains no comma. ottoq_cron_tick passes a multi-line
--    subquery containing COALESCE(r.run_by,'') -- so the site does not match
--    at all. Its key, orchestrator_agent_enabled, survives in the census only
--    because ottoq_sim_decide_and_dispatch happens to read it too. That is
--    luck, not coverage.
--
-- And a third category the regex can never fix:
--
-- 3. FOUR SITES READ A KEY THAT IS NOT IN THE SOURCE AT ALL. The key is a
--    column value:
--      public.ottoq_agentic_arming      -> v_k.param_key   (an inline VALUES list)
--      public.ottoq_intelligence_status -> s.gate_param_key
--                                          (public.ottoq_intelligence_sources)
--    No scanner over prosrc can see these. ottoq_intelligence_sources is the
--    live one: it names the gate dial for each intelligence source, and if a
--    row named an uncatalogued key that source's gate would be UNWRITABLE
--    through ottoq_policy_set while the status function went on reporting a
--    state for it. Measured today: 2 gate keys, both catalogued, so this is a
--    hole rather than a wound. It is closed here by reading the table as a
--    first-class key source.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS FILE CHANGES
--
-- a) The key regex drops the third-argument capture, so it ends at the key
--    literal and cannot swallow a nested call. Caller defaults move to their
--    own CTE using the OLD three-argument pattern -- best-effort by design:
--    the two nested keys will show caller_defaults NULL, which is the honest
--    answer, because their default is another function call.
--
-- b) ottoq_intelligence_sources.gate_param_key becomes a reader, listed as
--    'public.ottoq_intelligence_sources(gate_param_key)' so it is obvious in
--    reader_functions that it is a table, not a function.
--
-- c) A NEW VIEW, ottoq_policy_read_site_census, counts textual call sites per
--    function against parsed ones and reports the RESIDUAL. This is the part
--    that matters more than the two keys: an instrument that cannot parse
--    everything must say so and count what it dropped. Today it reports 186
--    call sites across 66 functions, 181 parsed, 5 unparsed in 3 functions --
--    and those 5 are exactly the sites enumerated above.
--
-- The caveat, stated rather than hidden: the census counts TEXTUAL occurrences
-- of 'ottoq_policy_get(' , so an occurrence inside a comment counts as a call
-- site and would show as an unparsed residual. There are none today (all five
-- residual sites were read by hand and are live code), but a future comment
-- quoting a call will raise the residual. That is the 0294-A1 lesson -- prosrc
-- includes comments -- kept as a known property instead of a surprise.
--
-- forces_recert = FALSE, and this one is provable rather than argued:
-- ottoq_policy_get NEVER reads the catalog or either view, and NOTHING reads
-- ottoq_policy_catalog_gap -- no function body mentions it and no view depends
-- on it. P1 asserts both. These are reporting objects with no consumer on any
-- decide or tick path.
--
-- ---------------------------------------------------------------------------
-- EXPECTED EFFECT, PREDICTED BEFORE APPLYING (dry-run 2026-09-14 10:05 UTC)
--
--   ottoq_policy_catalog_gap, status='read_uncatalogued'     35 -> 37
--   ottoq_policy_catalog_gap, distinct keys read            152 -> 152
--   ottoq_policy_catalog_gap, status='catalogued_unread'       8 ->   8
--   contention_wait_cap_ticks, timer_backstop_ticks       absent -> read_uncatalogued
--   ottoq_policy_read_site_census                        (new) 186 sites / 5 unparsed
--
-- The key count does NOT move: both newly-visible keys were already read by
-- name elsewhere in the same function, so they were counted once and are now
-- counted correctly. The gap moves because neither was ever catalogued.
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0296 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0296 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0296 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0296 P-: nothing in flight';
END $inflight$;

-- P0. MD5 GUARD. Replace the definition I actually read, not whatever is there.
DO $p0$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_viewdef('public.ottoq_policy_catalog_gap'::regclass, true)) INTO v_md5;
  IF v_md5 <> '0a7d646d9cd3361f1a252210f6e5ab1d' THEN
    RAISE EXCEPTION '0296 P0: ottoq_policy_catalog_gap is not the definition this '
                    'file was written against (live md5 %). Someone changed it; '
                    're-read it before replacing it.', v_md5;
  END IF;
  RAISE NOTICE '0296 P0: view md5 matches';
END $p0$;

-- P1. NOTHING CONSUMES THE GAP VIEW. This is the forces_recert=false argument,
-- measured rather than asserted: no function body mentions it, no view depends
-- on it, and ottoq_policy_get itself never reads the catalog.
DO $p1$
DECLARE v_fns text; v_views text; v_getter_reads_catalog int;
BEGIN
  SELECT string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY n.nspname||'.'||p.proname)
    INTO v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.prosrc ~ 'ottoq_policy_catalog_gap';
  IF v_fns IS NOT NULL THEN
    RAISE EXCEPTION '0296 P1: functions read the gap view (%); it is no longer a '
                    'pure reporting object and forces_recert must be re-argued', v_fns;
  END IF;

  SELECT string_agg(DISTINCT dn.nspname||'.'||dv.relname, ', ')
    INTO v_views
    FROM pg_depend d
    JOIN pg_rewrite r  ON r.oid = d.objid
    JOIN pg_class   dv ON dv.oid = r.ev_class
    JOIN pg_namespace dn ON dn.oid = dv.relnamespace
    JOIN pg_class   sv ON sv.oid = d.refobjid
   WHERE sv.relname = 'ottoq_policy_catalog_gap'
     AND dv.relname <> 'ottoq_policy_catalog_gap';
  IF v_views IS NOT NULL THEN
    RAISE EXCEPTION '0296 P1: views depend on the gap view (%)', v_views;
  END IF;

  SELECT count(*) INTO v_getter_reads_catalog
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get'
     AND p.prosrc ~ 'ottoq_policy_param_catalog';
  IF v_getter_reads_catalog > 0 THEN
    RAISE EXCEPTION '0296 P1: ottoq_policy_get now reads the catalog; the '
                    'forces_recert=false argument for every catalog file is void';
  END IF;

  RAISE NOTICE '0296 P1: gap view has no consumer; ottoq_policy_get still ignores the catalog';
END $p1$;

-- P2. THE TWO NESTED READS ARE REALLY THERE. Without this, A1 is a statement
-- about a regex rather than about the engine, and could pass vacuously.
DO $p2$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_recall_naive_threshold_v1';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0296 P2: ottoq_recall_naive_threshold_v1 does not exist';
  END IF;
  IF position('ottoq_policy_get(p_sim_run_id,''contention_wait_cap_ticks'',4) * 30' in v_src) = 0 THEN
    RAISE EXCEPTION '0296 P2: the nested contention_wait_cap_ticks read is not in the live source';
  END IF;
  IF position('ottoq_policy_get(p_sim_run_id,''timer_backstop_ticks'',48) * 30' in v_src) = 0 THEN
    RAISE EXCEPTION '0296 P2: the nested timer_backstop_ticks read is not in the live source';
  END IF;
  RAISE NOTICE '0296 P2: both nested reads present in live prosrc';
END $p2$;

-- P3. THE OLD REGEX IS BLIND TO THEM, AND THE NEW ONE IS NOT. The claim this
-- file is built on, executed against the live catalog rather than asserted.
DO $p3$
DECLARE v_old int; v_new int;
BEGIN
  SELECT count(*) INTO v_old
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         LATERAL regexp_matches(p.prosrc,
           'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''\s*,\s*([^)]*)\)', 'g') AS m
   WHERE n.nspname IN ('public','twin','ottoq')
     AND m[1] IN ('contention_wait_cap_ticks','timer_backstop_ticks');
  SELECT count(*) INTO v_new
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         LATERAL regexp_matches(p.prosrc,
           'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''', 'g') AS m
   WHERE n.nspname IN ('public','twin','ottoq')
     AND m[1] IN ('contention_wait_cap_ticks','timer_backstop_ticks');
  IF v_old <> 0 THEN
    RAISE EXCEPTION '0296 P3: the old regex finds % of the two nested keys; the '
                    'premise of this file is wrong', v_old;
  END IF;
  IF v_new <> 2 THEN
    RAISE EXCEPTION '0296 P3: the new regex finds % of the two nested keys, expected 2', v_new;
  END IF;
  RAISE NOTICE '0296 P3: old regex 0/2, new regex 2/2 -- the swallow is real and the fix reaches it';
END $p3$;

-- P4. THE DYNAMIC KEY SOURCE IS SAFE TO ADD. If any gate_param_key were
-- uncatalogued the gap would move by more than the two keys this file claims,
-- and A2's 37 would be wrong for a reason unrelated to the regex.
DO $p4$
DECLARE v_bad text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_sources
   WHERE gate_param_key IS NOT NULL;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0296 P4: no gate_param_key rows at all; the dynamic source '
                    'would be dead weight and A4 could not fail';
  END IF;
  SELECT string_agg(i.source||'->'||i.gate_param_key, ', ' ORDER BY i.source) INTO v_bad
    FROM public.ottoq_intelligence_sources i
   WHERE i.gate_param_key IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog c
                      WHERE c.param_key = i.gate_param_key);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0296 P4: a gate key is uncatalogued (%). That is a real '
                    'finding -- an intelligence source whose gate cannot be set -- '
                    'but it changes this file''s predicted counts. Catalogue it first.', v_bad;
  END IF;
  RAISE NOTICE '0296 P4: % gate keys, all catalogued', v_n;
END $p4$;

-- S. SNAPSHOT ---------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
  (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0296_pre', 'view', 'public', 'ottoq_policy_catalog_gap',
       pg_get_viewdef('public.ottoq_policy_catalog_gap'::regclass, true),
       md5(pg_get_viewdef('public.ottoq_policy_catalog_gap'::regclass, true));

-- ===========================================================================
-- THE CHANGE
-- ===========================================================================

CREATE OR REPLACE VIEW public.ottoq_policy_catalog_gap AS
WITH src AS (
  SELECT (n.nspname::text || '.'::text) || p.proname::text AS fn,
         p.prosrc
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = ANY (ARRAY['public'::name, 'twin'::name, 'ottoq'::name])
), literal_reads AS (
  -- NO third-argument capture. The match ends at the closing quote of the key,
  -- so a call nested inside another call's default argument is not swallowed.
  SELECT s.fn, m[1] AS param_key
    FROM src s,
         LATERAL regexp_matches(s.prosrc,
           'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''', 'g') AS m
), dynamic_reads AS (
  -- Keys named by DATA, not by source. No prosrc scanner can see these;
  -- ottoq_intelligence_status reads whatever this column holds.
  SELECT 'public.ottoq_intelligence_sources(gate_param_key)'::text AS fn,
         i.gate_param_key AS param_key
    FROM public.ottoq_intelligence_sources i
   WHERE i.gate_param_key IS NOT NULL
), all_reads AS (
  SELECT fn, param_key FROM literal_reads
  UNION
  SELECT fn, param_key FROM dynamic_reads
), caller_defaults AS (
  -- Best effort, and only here. This still uses the three-argument pattern, so
  -- it inherits the swallow -- which is now harmless, because it no longer
  -- decides which keys exist. A key with no parseable default reports NULL.
  SELECT m[1] AS param_key,
         array_agg(DISTINCT btrim(m[2]) ORDER BY (btrim(m[2]))) AS defaults
    FROM src s,
         LATERAL regexp_matches(s.prosrc,
           'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''\s*,\s*([^)]*)\)', 'g') AS m
   GROUP BY m[1]
), read_keys AS (
  SELECT a.param_key,
         count(DISTINCT a.fn) AS readers,
         array_agg(DISTINCT a.fn ORDER BY a.fn) AS reader_functions
    FROM all_reads a
   GROUP BY a.param_key
), rows_per_key AS (
  SELECT pp.param_key, count(*) AS live_rows
    FROM public.ottoq_policy_params pp
   GROUP BY pp.param_key
)
SELECT COALESCE(r.param_key, c.param_key) AS param_key,
       CASE
         WHEN r.param_key IS NULL THEN 'catalogued_unread'::text
         WHEN c.param_key IS NULL THEN 'read_uncatalogued'::text
         ELSE 'ok'::text
       END AS status,
       COALESCE(r.readers, 0::bigint) AS readers,
       COALESCE(x.live_rows, 0::bigint) AS live_rows,
       c.param_key IS NOT NULL AS catalogued,
       c.min_value,
       c.max_value,
       c.default_value,
       d.defaults AS caller_defaults,
       r.reader_functions
  FROM read_keys r
  FULL JOIN public.ottoq_policy_param_catalog c ON c.param_key = r.param_key
  LEFT JOIN rows_per_key    x ON x.param_key = COALESCE(r.param_key, c.param_key)
  LEFT JOIN caller_defaults d ON d.param_key = COALESCE(r.param_key, c.param_key);

COMMENT ON VIEW public.ottoq_policy_catalog_gap IS
'Every policy dial the engine READS, against every dial the catalog admits. '
'status=read_uncatalogued means ottoq_policy_set REFUSES to write the key '
'(unknown_param), so no agent can turn it through the sanctioned path. '
'Keys come from two sources: a regex over prosrc that deliberately does NOT '
'capture the third argument -- capturing it made the global scan swallow calls '
'nested inside another call''s default, which hid contention_wait_cap_ticks '
'and timer_backstop_ticks entirely (0296) -- and ottoq_intelligence_sources.'
'gate_param_key, which names gate dials in DATA where no scanner can see them. '
'caller_defaults is best-effort and may be NULL. This view has no consumer: '
'nothing on any decide or tick path reads it, and ottoq_policy_get never reads '
'the catalog, which is why catalog migrations are forces_recert=false. '
'Call sites the key regex cannot parse are COUNTED, not dropped -- see '
'ottoq_policy_read_site_census.';

CREATE OR REPLACE VIEW public.ottoq_policy_read_site_census AS
WITH src AS (
  SELECT (n.nspname::text || '.'::text) || p.proname::text AS fn,
         p.prosrc
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = ANY (ARRAY['public'::name, 'twin'::name, 'ottoq'::name])
     AND p.prosrc ~ 'ottoq_policy_get\s*\('
), call_sites AS (
  SELECT s.fn, count(*) AS n_call_sites
    FROM src s, LATERAL regexp_matches(s.prosrc, 'ottoq_policy_get\s*\(', 'g')
   GROUP BY s.fn
), parsed AS (
  SELECT s.fn, count(*) AS n_parsed
    FROM src s,
         LATERAL regexp_matches(s.prosrc,
           'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''', 'g')
   GROUP BY s.fn
)
SELECT c.fn,
       c.n_call_sites,
       COALESCE(p.n_parsed, 0::bigint) AS n_parsed,
       c.n_call_sites - COALESCE(p.n_parsed, 0::bigint) AS n_unparsed
  FROM call_sites c
  LEFT JOIN parsed p ON p.fn = c.fn;

COMMENT ON VIEW public.ottoq_policy_read_site_census IS
'The residual of ottoq_policy_catalog_gap''s key scanner, made visible. One row '
'per function that mentions ottoq_policy_get(, with the number of textual call '
'sites, the number the key regex could parse, and the difference. An instrument '
'that cannot parse everything must say how much it dropped; before 0296 this one '
'silently reported a gap two keys smaller than the truth. '
'n_unparsed>0 is not automatically a defect -- four of today''s five residual '
'sites read a key held in a COLUMN (ottoq_agentic_arming''s VALUES list, '
'ottoq_intelligence_status''s gate_param_key) and no source scanner can ever '
'parse those; the fifth (ottoq_cron_tick) passes a subquery containing a comma '
'as the run id. But an unexplained rise in n_unparsed means a new call shape the '
'gap view is not counting. '
'CAVEAT: this counts TEXTUAL occurrences, so a call quoted inside a comment '
'counts as a site and shows as residual. There are none today.';

-- ===========================================================================
-- ASSERTIONS
-- ===========================================================================

-- A1. The two swallowed keys are now visible, and visible as UNCATALOGUED --
-- which is the finding: they are dials no agent can turn.
DO $a1$
DECLARE v_row record; v_n int := 0;
BEGIN
  FOR v_row IN
    SELECT param_key, status, readers, live_rows
      FROM public.ottoq_policy_catalog_gap
     WHERE param_key IN ('contention_wait_cap_ticks','timer_backstop_ticks')
     ORDER BY param_key
  LOOP
    v_n := v_n + 1;
    IF v_row.status <> 'read_uncatalogued' THEN
      RAISE EXCEPTION 'A1 FAILED: % reports status %, expected read_uncatalogued',
                      v_row.param_key, v_row.status;
    END IF;
    RAISE NOTICE 'A1: % -> % (% readers, % live rows)',
                 v_row.param_key, v_row.status, v_row.readers, v_row.live_rows;
  END LOOP;
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'A1 FAILED: the view shows % of the two nested keys, expected 2', v_n;
  END IF;
  RAISE NOTICE 'A1 OK: both formerly-swallowed keys are visible and uncatalogued';
END $a1$;

-- A2. The predicted counts, all three, checked against the numbers written in
-- this file's header BEFORE it was applied.
DO $a2$
DECLARE v_gap int; v_read int; v_unread int;
BEGIN
  SELECT count(*) FILTER (WHERE status = 'read_uncatalogued'),
         count(*) FILTER (WHERE status <> 'catalogued_unread'),
         count(*) FILTER (WHERE status = 'catalogued_unread')
    INTO v_gap, v_read, v_unread
    FROM public.ottoq_policy_catalog_gap;
  IF v_gap <> 37 THEN
    RAISE EXCEPTION 'A2 FAILED: gap is %, predicted 37', v_gap;
  END IF;
  IF v_read <> 152 THEN
    RAISE EXCEPTION 'A2 FAILED: % keys read, predicted 152', v_read;
  END IF;
  IF v_unread <> 8 THEN
    RAISE EXCEPTION 'A2 FAILED: % catalogued-unread, predicted 8', v_unread;
  END IF;
  RAISE NOTICE 'A2 OK: 152 keys read, % uncatalogued (was 35), % catalogued-unread',
               v_gap, v_unread;
END $a2$;

-- A3. The residual is counted, named, and equal to the five sites read by hand.
DO $a3$
DECLARE v_sites bigint; v_parsed bigint; v_unparsed bigint; v_fns text;
BEGIN
  SELECT sum(n_call_sites), sum(n_parsed), sum(n_unparsed)
    INTO v_sites, v_parsed, v_unparsed
    FROM public.ottoq_policy_read_site_census;
  SELECT string_agg(fn || '=' || n_unparsed, ', ' ORDER BY fn) INTO v_fns
    FROM public.ottoq_policy_read_site_census WHERE n_unparsed > 0;
  IF v_sites <> 186 THEN
    RAISE EXCEPTION 'A3 FAILED: % call sites, predicted 186', v_sites;
  END IF;
  IF v_unparsed <> 5 THEN
    RAISE EXCEPTION 'A3 FAILED: % unparsed sites, predicted 5 (%)', v_unparsed, v_fns;
  END IF;
  IF v_fns IS DISTINCT FROM
     'public.ottoq_agentic_arming=1, public.ottoq_cron_tick=1, public.ottoq_intelligence_status=3' THEN
    RAISE EXCEPTION 'A3 FAILED: the residual sits in a different place than expected: %', v_fns;
  END IF;
  RAISE NOTICE 'A3 OK: % sites, % parsed, % unparsed -- %', v_sites, v_parsed, v_unparsed, v_fns;
END $a3$;

-- A4. The dynamic reader is a reader. Not "the table exists" -- the view must
-- actually attribute a key to it, or the dynamic_reads CTE is decoration.
DO $a4$
DECLARE v_fns text[]; v_hit int;
BEGIN
  SELECT reader_functions INTO v_fns
    FROM public.ottoq_policy_catalog_gap WHERE param_key = 'orchestrator_agent_enabled';
  IF v_fns IS NULL THEN
    RAISE EXCEPTION 'A4 FAILED: orchestrator_agent_enabled has no readers at all';
  END IF;
  SELECT count(*) INTO v_hit FROM unnest(v_fns) AS f
   WHERE f = 'public.ottoq_intelligence_sources(gate_param_key)';
  IF v_hit <> 1 THEN
    RAISE EXCEPTION 'A4 FAILED: the gate table is not credited as a reader of '
                    'orchestrator_agent_enabled; readers are %', v_fns;
  END IF;
  RAISE NOTICE 'A4 OK: orchestrator_agent_enabled credited to % readers including the gate table',
               array_length(v_fns, 1);
END $a4$;

-- A5. The shape contract CREATE OR REPLACE VIEW enforces implicitly, asserted
-- explicitly: ten columns, same names, same order. A caller reading this view
-- positionally must not break.
DO $a5$
DECLARE v_cols text;
BEGIN
  SELECT string_agg(a.attname, ',' ORDER BY a.attnum) INTO v_cols
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
   WHERE n.nspname = 'public' AND c.relname = 'ottoq_policy_catalog_gap';
  IF v_cols <> 'param_key,status,readers,live_rows,catalogued,min_value,max_value,'
              || 'default_value,caller_defaults,reader_functions' THEN
    RAISE EXCEPTION 'A5 FAILED: column shape changed: %', v_cols;
  END IF;
  RAISE NOTICE 'A5 OK: column shape unchanged';
END $a5$;

-- ===========================================================================
-- WHAT IS NOT FIXED HERE, ON PURPOSE
--
-- ottoq_intelligence_sources.gate_param_key has no foreign key to the catalog,
-- so a row CAN still name a key ottoq_policy_set would refuse. P4 catches it at
-- apply time and the gap view now shows it as read_uncatalogued, but nothing
-- prevents the INSERT. A constraint is a separate concern and a separate file.
-- ===========================================================================
