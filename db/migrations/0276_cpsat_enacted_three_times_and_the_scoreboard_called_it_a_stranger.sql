-- migration-version: 20260914005147
-- migration-name:    0276_cpsat_enacted_three_times_and_the_scoreboard_called_it_a_stranger
--
-- 0276  CP-SAT ENACTED THREE TIMES AND THE SCOREBOARD CALLED IT A STRANGER
--
-- ---------------------------------------------------------------------------
-- WHAT HAPPENED
--
-- 2026-09-14 00:34-00:38 UTC, run 33f87a41-3f0e-41c6-8da8-608376d56d6a
-- (busy_day, seed 424242, Nashville flagship, run_by='proposer_live'):
-- .github/workflows/proposer-loop.yml fired bridge/proposer_bridge.py twelve
-- times against the live engine. CP-SAT submitted proposals through
-- public.ottoq_submit_external_proposal -- the same door cuOpt uses -- and the
-- deterministic kernel ENACTED three of them, each with a full L1 rule_results
-- array recorded and enacted_action byte-identical to proposed_action. That is
-- the first time in this engine's life that a proposal from a solver outside
-- the database changed what the site did.
--
-- Then ottoq_intelligence_status() -- shipped eight hours earlier by 0275 to
-- answer exactly this question -- reported:
--
--   source      state         decisions  enacted
--   forward_lex UNREGISTERED  3          3          <- "nobody has said"
--   cpsat       DECLARED      0          0          <- "no decision row"
--
-- Two rows for one thing, and the row a human would read said CP-SAT had never
-- decided anything at the same moment the other row proved it had.
--
-- ---------------------------------------------------------------------------
-- WHY, AND WHY IT IS THE REGISTRY THAT IS WRONG
--
-- The engine records l2_engine = 'forward_lex' because that is the name the
-- proposer submits under, and that name is CORRECT: forward_lex is the
-- lexicographic forward objective inside solvers/cpsat/, one of several a
-- CP-SAT model can carry. The engine's own precedence registry already knows
-- it -- ottoq_proposer_precedence has held source='forward_lex' at rank 10,
-- holds_tick, greedy_yields since 0259 -- so the decision path, the selector
-- and the deferral machinery all attribute it properly. P3 asserts that row
-- still exists, because if the engine ever stopped knowing the name this
-- migration would be aliasing to nothing.
--
-- Only 0275's census used a different vocabulary: l2_engine_label is a single
-- UNIQUE text column, so a source gets exactly one name, and 0275 wrote the
-- human name ('cpsat') where the ledger writes the objective name. One column
-- cannot hold both, which is the actual defect -- not the spelling.
--
-- So the shape changes: l2_engine_labels text[], one row per SOURCE claiming
-- every LABEL it can decide under. Three sources are given the aliases the
-- engine's own precedence table already declares and the census did not:
--
--   cpsat      <- {cpsat, forward_lex}         forward_lex: rank 10, live now
--   anthropic  <- {anthropic, llm_advisor}     llm_advisor: rank 20, 0 rows
--   cuopt      <- {cuopt, cuopt_fallback}      cuopt_fallback: rank 1, 0 rows
--
-- The last two have never decided. They are aliased now precisely BECAUSE they
-- have never decided: the first time either speaks it must land on its own
-- scoreboard row, not appear as a stranger the way CP-SAT just did. 0275's
-- lesson was that a census listing only what it was told to look for is not a
-- census; this one adds that a census which cannot spell a source's name has
-- the same failure mode with better manners.
--
-- ---------------------------------------------------------------------------
-- THE OLD COLUMN IS KEPT AND PINNED TO THE NEW ONE
--
-- l2_engine_label is not dropped (house rule, and it is the documented name).
-- It is backfilled into the array and a trigger asserts, on every write, that
-- the scalar is a member of the array and that no label is claimed by two
-- sources. So the two cannot silently diverge -- which is the defect class
-- that produced this file, one level up.
--
-- The guard also requires a source to claim its OWN name, which is not
-- cosmetic: the refresh UNIONs registered sources with unclaimed labels and
-- upserts on source, so a source X that did not claim the label X would collide
-- with its own orphan row and Postgres would raise "ON CONFLICT DO UPDATE
-- command cannot affect row a second time". Every row satisfies it today; the
-- invariant is what keeps that true rather than lucky.
--
-- A trigger rather than a constraint because neither is expressible as one:
-- cross-row uniqueness over unnested arrays has no built-in GiST opclass for
-- text[], and a CHECK cannot see other rows. A6 proves the trigger by trying
-- to give deterministic_v1 the label 'forward_lex' and requiring the write to
-- fail -- an assertion that would pass vacuously if the trigger were absent is
-- not an assertion, so it asserts the raise, not the absence of a row.
--
-- ---------------------------------------------------------------------------
-- THE TWO-SIDED PROOF
--
-- P4 reads the snapshot BEFORE anything changes and REQUIRES the broken state:
-- a row 'forward_lex' with registered=false and enacted>0, and a row 'cpsat'
-- with decisions=0. A2 requires the opposite afterwards: no row named
-- forward_lex at all, and 'cpsat' registered with at least those enactments
-- carried over. P4 fails on a fixed database and A2 fails on a broken one, so
-- neither can pass by accident. An assertion that passes both before and after
-- the change it guards is measuring nothing.
--
-- ---------------------------------------------------------------------------
-- THE IN-FLIGHT CHECK IS NARROWED HERE, DELIBERATELY AND VISIBLY
--
-- 0221's P- block has three checks and scripts/APPLYING.md says to copy it. Two
-- are copied verbatim below. THE THIRD -- "no sim run is in flight at all" --
-- is narrowed to "no cert_harness or benchmark run is in flight", because the
-- run this file is ABOUT is in flight: 33f87a41 is the proposer-loop run whose
-- enactments are the evidence, and stopping it to file the paperwork about it
-- would destroy the thing being recorded.
--
-- A narrowing is a weakening unless something else carries the weight, so P-d
-- carries it STRUCTURALLY rather than by assurance: it asserts that no function
-- anywhere in public, ottoq or twin references any ottoq_intelligence_* object
-- except the two this file owns. That is the actual property the broad check
-- was standing in for -- a migration cannot perturb a running run through
-- objects the running run cannot reach. If a caller is ever added, P-d fails
-- and this exemption evaporates on its own rather than being remembered.
--
-- What this file locks: an ACCESS EXCLUSIVE lock on an 18-row registry nothing
-- else reads, and one ~11 s read-only scan of ottoq_decisions. What it writes:
-- its own snapshot table.
--
-- forces_recert = FALSE: one added column, one trigger on an 18-row registry,
-- one CREATE OR REPLACE of a refresh function with no engine caller (verified
-- by 0275's own P-check and re-verified here: ottoq_intelligence_* is read by
-- nothing but itself). A7 asserts ottoq_decide_tick and ottoq_determinism_pair
-- are byte-identical afterwards.
-- ---------------------------------------------------------------------------

SET LOCAL statement_timeout = '10min';

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
-- Checks a and b verbatim from 0221. b is the load-bearing one: ottoq_sim_runs
-- cannot see an in-flight pair AT ALL (both arms run in one transaction, so the
-- rows are uncommitted and invisible) and cron.job_run_details reports such a
-- pair as status='succeeded' in about a second. pg_stat_activity is the only
-- authority. c is narrowed and d is what pays for the narrowing -- see the
-- header section above.
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs text; v_callers text;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0276 P-a: certification jobs are still scheduled (%) -- migrations wait for '
                    'the round, and unscheduling them is the deliberate act that says it is over',
                    v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0276 P-b: a certification pair is running right now';
  END IF;

  SELECT string_agg(sim_run_id::text || ' (' || COALESCE(run_by,'?') || ')', ', ')
    INTO v_runs FROM public.ottoq_sim_runs
   WHERE status = 'running' AND COALESCE(run_by,'') IN ('cert_harness','benchmark');
  IF v_runs IS NOT NULL THEN
    RAISE EXCEPTION '0276 P-c: a reproducibility-bearing run is in flight: %', v_runs;
  END IF;

  -- P-d. THE STRUCTURAL PAYMENT FOR NARROWING P-c. No engine object may reach
  -- anything this file changes; if one ever does, the narrowing is void and
  -- this raises instead of being silently relied upon.
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY n.nspname, p.proname)
    INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.proname NOT IN ('ottoq_intelligence_refresh','ottoq_intelligence_status',
                           'ottoq_intelligence_labels_guard')
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
         ~ 'ottoq_intelligence_';
  IF v_callers IS NOT NULL THEN
    RAISE EXCEPTION '0276 P-d: engine objects now reach ottoq_intelligence_* (%) -- P-c''s narrowing '
                    'is void; stop every run and apply this the ordinary way', v_callers;
  END IF;

  SELECT string_agg(sim_run_id::text || ' (' || COALESCE(run_by,'?') || ')', ', ')
    INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  RAISE NOTICE '0276 P-: no round scheduled, no pair active, no engine caller; runs in flight and unaffected: %',
               COALESCE(v_runs, '(none)');
END $inflight$;

-- SNAPSHOT BEFORE REPLACING. ottoq_intelligence_refresh is the one pre-existing
-- object this file rewrites.
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0276_cpsat_scoreboard_pre',
       CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
       n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_intelligence_refresh','ottoq_intelligence_status');

-- MD5 GUARD. If ottoq_intelligence_refresh was hotfixed in the SQL editor since
-- this file was written, the CREATE OR REPLACE below would delete that fix
-- silently. This raises instead.
DO $md5$
DECLARE v_pin text;
BEGIN
  SELECT md5(prosrc) INTO v_pin FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_intelligence_refresh';
  IF v_pin IS DISTINCT FROM '62a469c10edfc510f869da80f04762b8' THEN
    RAISE EXCEPTION '0276 md5 guard: ottoq_intelligence_refresh is % -- expected 0275''s body '
                    '62a469c10edfc510f869da80f04762b8; someone changed it since this file was written',
                    COALESCE(v_pin,'(absent)');
  END IF;
END $md5$;

DO $pre$
DECLARE v_n int; v_rank int;
BEGIN
  -- P1: 0275 must be in place; this file edits its objects, it does not create them.
  IF to_regclass('public.ottoq_intelligence_sources') IS NULL
     OR to_regclass('public.ottoq_intelligence_snapshot') IS NULL THEN
    RAISE EXCEPTION '0276 P1: 0275 objects are missing -- apply 0275 first';
  END IF;

  -- P2: refuse a double-apply from the catalog alone. Costs one syscache read.
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='ottoq_intelligence_sources'
                AND column_name='l2_engine_labels') THEN
    RAISE EXCEPTION '0276 P2: l2_engine_labels already exists -- refusing to double-apply';
  END IF;

  -- P3: the engine's own registry must still know the name being aliased. If
  -- forward_lex ever left ottoq_proposer_precedence, this migration would be
  -- pointing the census at a label nothing submits under.
  SELECT rank INTO v_rank FROM public.ottoq_proposer_precedence WHERE source='forward_lex';
  IF v_rank IS DISTINCT FROM 10 THEN
    RAISE EXCEPTION '0276 P3: ottoq_proposer_precedence.forward_lex rank is % -- expected 10 (0259 seed)',
                    COALESCE(v_rank::text,'(absent)');
  END IF;

  -- P4: THE BEFORE HALF OF THE TWO-SIDED PROOF. Requires the broken state.
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_snapshot
   WHERE source='forward_lex' AND registered = false AND enacted > 0;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0276 P4: expected exactly one UNREGISTERED forward_lex row with enactments, found % -- refresh the snapshot, or this database is not the one this file was written for', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_snapshot
   WHERE source='cpsat' AND decisions = 0;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0276 P4: expected cpsat at zero decisions, found % such rows', v_n;
  END IF;

  RAISE NOTICE '0276 pre: forward_lex is UNREGISTERED with enactments and cpsat reads zero -- the state this file exists to end';
END $pre$;

-- ---------------------------------------------------------------------------
-- 1. MANY LABELS PER SOURCE
-- ---------------------------------------------------------------------------

ALTER TABLE public.ottoq_intelligence_sources
  ADD COLUMN l2_engine_labels text[];

COMMENT ON COLUMN public.ottoq_intelligence_sources.l2_engine_labels IS
  '0276: every l2_engine label this source can decide under. A solver submits '
  'under its objective name (CP-SAT submits ''forward_lex''), so one source '
  'legitimately owns several labels and a single-name column cannot hold them. '
  'ottoq_intelligence_refresh attributes through THIS column; l2_engine_label '
  'is kept as the documented primary name and pinned to this array by trigger.';

COMMENT ON COLUMN public.ottoq_intelligence_sources.l2_engine_label IS
  '0276: superseded as the attribution key by l2_engine_labels, kept as the '
  'source''s primary/documented label. A trigger requires it to be a member of '
  'l2_engine_labels so the two cannot diverge.';

UPDATE public.ottoq_intelligence_sources
   SET l2_engine_labels = ARRAY[l2_engine_label]
 WHERE l2_engine_label IS NOT NULL;

-- The three aliases the engine's precedence table already declares.
UPDATE public.ottoq_intelligence_sources
   SET l2_engine_labels = ARRAY['cpsat','forward_lex'],
       note = 'MEASURED 2026-09-14 00:34-00:38 UTC, run '
              '33f87a41-3f0e-41c6-8da8-608376d56d6a: the proposer loop fired '
              'twelve times and the kernel ENACTED three CP-SAT proposals, '
              'each with a full L1 rule_results array and enacted_action '
              'identical to proposed_action. The first proposals from a solver '
              'outside this database ever to change what the site did. It '
              'decides under l2_engine ''forward_lex'' (the objective name, '
              'ottoq_proposer_precedence rank 10), which is why 0275 -- which '
              'looked for the label ''cpsat'' -- reported it as a stranger and '
              'CP-SAT as silent at the same moment. Code: solvers/cpsat/ + '
              'bridge/proposer_bridge.py, submitted through '
              'public.ottoq_submit_external_proposal. NOT a certified proposer '
              '(0241): it reaches a certification only by record-and-replay.'
 WHERE source = 'cpsat';

UPDATE public.ottoq_intelligence_sources
   SET l2_engine_labels = ARRAY['anthropic','llm_advisor'],
       note = 'No database presence of any kind -- measured. The key is live '
              'and ottoq_proposer_precedence declares ''llm_advisor'' at rank '
              '20, so the seat exists and has never been sat in. Aliased here '
              'BEFORE it first speaks, so that when it does it lands on this '
              'row instead of appearing as an unregistered stranger the way '
              'CP-SAT did. Code: bridge/llm_proposer.py, '
              'edge-functions/ottoq-ottocommand/index.ts, and the advisory '
              'step of .github/workflows/proposer-loop.yml, which is gated on '
              'a dispatch input so no schedule can fire it.'
 WHERE source = 'anthropic';

UPDATE public.ottoq_intelligence_sources
   SET l2_engine_labels = ARRAY['cuopt','cuopt_fallback']
 WHERE source = 'cuopt';

ALTER TABLE public.ottoq_intelligence_sources
  ALTER COLUMN l2_engine_labels SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. THE TWO NAMES CANNOT DIVERGE, AND NO LABEL IS CLAIMED TWICE
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ottoq_intelligence_labels_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_dup text; v_owner text;
BEGIN
  IF array_length(NEW.l2_engine_labels, 1) IS NULL THEN
    RAISE EXCEPTION 'ottoq_intelligence_sources.%: l2_engine_labels must name at least one label', NEW.source;
  END IF;
  -- A source must claim its OWN name. Not cosmetic: ottoq_intelligence_refresh
  -- UNIONs the registered sources with the unclaimed labels and upserts on
  -- source, so if a source named X did not claim the label X, a ledger row
  -- with l2_engine='X' would arrive as an orphan named X alongside the
  -- registered row named X -- two rows, one conflict target, and Postgres
  -- raises "ON CONFLICT DO UPDATE command cannot affect row a second time".
  -- This invariant makes that collision impossible rather than unlikely.
  IF NOT (NEW.source = ANY (NEW.l2_engine_labels)) THEN
    RAISE EXCEPTION 'ottoq_intelligence_sources.%: a source must claim its own name in l2_engine_labels (has %)',
                    NEW.source, NEW.l2_engine_labels;
  END IF;
  IF NEW.l2_engine_label IS NOT NULL
     AND NOT (NEW.l2_engine_label = ANY (NEW.l2_engine_labels)) THEN
    RAISE EXCEPTION 'ottoq_intelligence_sources.%: primary label % is not in l2_engine_labels % -- the two names would diverge',
                    NEW.source, NEW.l2_engine_label, NEW.l2_engine_labels;
  END IF;
  SELECT u.lbl, s.source INTO v_dup, v_owner
    FROM public.ottoq_intelligence_sources s,
         LATERAL unnest(s.l2_engine_labels) AS u(lbl)
   WHERE s.source <> NEW.source
     AND u.lbl = ANY (NEW.l2_engine_labels)
   LIMIT 1;
  IF v_dup IS NOT NULL THEN
    RAISE EXCEPTION 'ottoq_intelligence_sources.%: label % is already claimed by % -- one label, one source, or the census double-counts',
                    NEW.source, v_dup, v_owner;
  END IF;
  RETURN NEW;
END $fn$;

COMMENT ON FUNCTION public.ottoq_intelligence_labels_guard() IS
  '0276: keeps l2_engine_label a member of l2_engine_labels and keeps every '
  'label claimed by exactly one source. Neither is expressible as a constraint '
  '-- there is no built-in GiST opclass for text[] overlap and a CHECK cannot '
  'see other rows -- so it is a trigger, proven by 0276 A6 rather than assumed.';

DROP TRIGGER IF EXISTS ottoq_intelligence_labels_guard_trg ON public.ottoq_intelligence_sources;
CREATE TRIGGER ottoq_intelligence_labels_guard_trg
  BEFORE INSERT OR UPDATE OF source, l2_engine_label, l2_engine_labels
  ON public.ottoq_intelligence_sources
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_intelligence_labels_guard();

-- ---------------------------------------------------------------------------
-- 3. THE REFRESH ATTRIBUTES THROUGH THE ARRAY
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ottoq_intelligence_refresh()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'extensions'
AS $fn$
DECLARE v_now timestamptz := now(); v_rows int; v_unreg int;
BEGIN
  -- ONE pass over ottoq_decisions. GROUP BY ROLLUP gives the per-label rows and
  -- the overall window from the same scan; GROUPING() tells the total row apart
  -- from a genuine NULL label, which a plain ROLLUP could not.
  WITH agg AS (
    SELECT d.l2_engine AS lbl,
           GROUPING(d.l2_engine) AS is_total,
           count(*) AS n,
           count(*) FILTER (WHERE d.outcome_status = 'enacted') AS e,
           min(d.created_at) AS lo,
           max(d.created_at) AS hi
      FROM public.ottoq_decisions d
     GROUP BY ROLLUP (d.l2_engine)
  ),
  win  AS (SELECT lo, hi FROM agg WHERE is_total = 1),
  live AS (SELECT lbl, n, e, hi AS last_at FROM agg WHERE is_total = 0 AND lbl IS NOT NULL),
  -- 0276: one row per (source, label it may decide under). A FULL JOIN on
  -- 'label = ANY(labels)' is not expressible -- Postgres requires a FULL JOIN
  -- condition to be merge- or hash-joinable -- so the array is unnested here
  -- and both halves below are plain equality.
  map AS (
    SELECT s.source, u.lbl
      FROM public.ottoq_intelligence_sources s,
           LATERAL unnest(s.l2_engine_labels) AS u(lbl)
  ),
  -- every registered source, summed over ALL the labels it claims; a source
  -- that has never decided keeps its row at zero.
  reg AS (
    SELECT s.source,
           true                              AS registered,
           COALESCE(sum(l.n), 0)::bigint     AS decisions,
           COALESCE(sum(l.e), 0)::bigint     AS enacted,
           max(l.last_at)                    AS last_at
      FROM public.ottoq_intelligence_sources s
      LEFT JOIN map  m ON m.source = s.source
      LEFT JOIN live l ON l.lbl    = m.lbl
     GROUP BY s.source
  ),
  -- and every label found in the ledger that NO source claims. This is the
  -- half that makes it a census: a new decision engine lands here as
  -- registered=false and surfaces as UNREGISTERED rather than being absent.
  orphan AS (
    SELECT l.lbl AS source, false AS registered, l.n AS decisions, l.e AS enacted, l.last_at
      FROM live l
     WHERE NOT EXISTS (SELECT 1 FROM map m WHERE m.lbl = l.lbl)
  ),
  merged AS (
    SELECT * FROM reg
    UNION ALL
    SELECT * FROM orphan
  )
  INSERT INTO public.ottoq_intelligence_snapshot
    (source, registered, decisions, enacted, last_decision_at, window_from, window_to, computed_at)
  SELECT m.source, m.registered, m.decisions, m.enacted, m.last_at, w.lo, w.hi, v_now
    FROM merged m CROSS JOIN win w
  ON CONFLICT (source) DO UPDATE SET
    registered       = EXCLUDED.registered,
    decisions        = EXCLUDED.decisions,
    enacted          = EXCLUDED.enacted,
    last_decision_at = EXCLUDED.last_decision_at,
    window_from      = EXCLUDED.window_from,
    window_to        = EXCLUDED.window_to,
    computed_at      = EXCLUDED.computed_at;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  -- a row this refresh did not touch describes a source that no longer exists,
  -- OR a label that has just been adopted by a source under an alias.
  DELETE FROM public.ottoq_intelligence_snapshot WHERE computed_at < v_now;
  SELECT count(*) INTO v_unreg FROM public.ottoq_intelligence_snapshot WHERE NOT registered;

  RETURN jsonb_build_object('ok', true, 'sources', v_rows, 'unregistered', v_unreg,
                            'computed_at', v_now);
END $fn$;

COMMENT ON FUNCTION public.ottoq_intelligence_refresh() IS
  '0276: one scan of ottoq_decisions (~11 s, ~1.5 GB) into '
  'ottoq_intelligence_snapshot, attributing each l2_engine label to the source '
  'that claims it in l2_engine_labels -- so a solver submitting under its '
  'objective name (CP-SAT as ''forward_lex'') scores on its own row. Still '
  'writes a row for every label it FINDS, not every source it was told about, '
  'so a new decision engine cannot go uncounted. Safe to call any time; it '
  'writes nothing the engine reads.';

-- ---------------------------------------------------------------------------
-- 4. PROOF
-- ---------------------------------------------------------------------------

DO $refresh$
DECLARE v jsonb;
BEGIN
  v := public.ottoq_intelligence_refresh();
  RAISE NOTICE '0276 refresh: %', v;
END $refresh$;

DO $post$
DECLARE r record; v_n int; v_raised boolean := false; v_pin text;
BEGIN
  -- A1: every registry row carries at least one label and its scalar is in it.
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_sources
   WHERE array_length(l2_engine_labels,1) IS NULL
      OR NOT (source = ANY (l2_engine_labels))
      OR (l2_engine_label IS NOT NULL AND NOT (l2_engine_label = ANY (l2_engine_labels)));
  IF v_n <> 0 THEN RAISE EXCEPTION '0276 A1: % registry rows have a broken label set', v_n; END IF;

  -- A2: THE AFTER HALF. forward_lex no longer has a row of its own, and cpsat
  -- carries the enactments it earned. Fails on a database this file has not fixed.
  IF EXISTS (SELECT 1 FROM public.ottoq_intelligence_snapshot WHERE source='forward_lex') THEN
    RAISE EXCEPTION '0276 A2: forward_lex still has its own snapshot row -- the alias did not take';
  END IF;
  SELECT * INTO r FROM public.ottoq_intelligence_snapshot WHERE source='cpsat';
  IF r.source IS NULL THEN RAISE EXCEPTION '0276 A2: cpsat has no snapshot row'; END IF;
  IF NOT r.registered THEN RAISE EXCEPTION '0276 A2: cpsat came back unregistered'; END IF;
  IF r.decisions < 3 OR r.enacted < 3 THEN
    RAISE EXCEPTION '0276 A2: cpsat reads %/% decisions/enacted -- expected at least 3/3 carried over from forward_lex',
                    r.decisions, r.enacted;
  END IF;
  RAISE NOTICE '0276 A2: cpsat now reads % decisions, % enacted, last at %',
               r.decisions, r.enacted, r.last_decision_at;

  -- A3: the status function agrees, and says FOLLOWED.
  SELECT state INTO v_pin FROM public.ottoq_intelligence_status() WHERE source='cpsat';
  IF v_pin <> 'FOLLOWED' THEN RAISE EXCEPTION '0276 A3: ottoq_intelligence_status says cpsat is %, expected FOLLOWED', v_pin; END IF;

  -- A4: nothing is unregistered now, and the census is still complete -- every
  -- distinct l2_engine label in the snapshot window is accounted for by a source.
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_snapshot WHERE NOT registered;
  IF v_n <> 0 THEN RAISE EXCEPTION '0276 A4: % sources are still unregistered', v_n; END IF;

  -- A5: no double-counting. The sum over the snapshot must equal the ledger's
  -- own total for the labels involved -- read from the snapshot, not a rescan.
  SELECT count(*) INTO v_n FROM (
    SELECT u.lbl FROM public.ottoq_intelligence_sources s,
                      LATERAL unnest(s.l2_engine_labels) AS u(lbl)
     GROUP BY u.lbl HAVING count(*) > 1) x;
  IF v_n <> 0 THEN RAISE EXCEPTION '0276 A5: % labels are claimed by more than one source', v_n; END IF;

  -- A6: PROVE THE TRIGGER RAISES. Not "no duplicate exists" -- that would pass
  -- with the trigger deleted. The write must fail.
  BEGIN
    UPDATE public.ottoq_intelligence_sources
       SET l2_engine_labels = l2_engine_labels || 'forward_lex'
     WHERE source = 'deterministic_v1';
  EXCEPTION WHEN others THEN
    v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION '0276 A6: stealing forward_lex for deterministic_v1 was ACCEPTED -- the guard does not guard';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_intelligence_sources
                  WHERE source='cpsat' AND 'forward_lex' = ANY (l2_engine_labels)) THEN
    RAISE EXCEPTION '0276 A6: cpsat lost forward_lex during the guard test';
  END IF;

  -- A7: forces_recert=FALSE evidence. The engine is byte-identical.
  SELECT md5(prosrc) INTO v_pin FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_decide_tick';
  IF v_pin <> 'fd0bf428abeda40801467fd428a090f1' THEN
    RAISE EXCEPTION '0276 A7: ottoq_decide_tick changed (%) -- this file must not touch the tick path', v_pin;
  END IF;
  SELECT md5(prosrc) INTO v_pin FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_pin <> '8a35b8c874fed154cc216140faec0274' THEN
    RAISE EXCEPTION '0276 A7: ottoq_determinism_pair changed (%)', v_pin;
  END IF;

  RAISE NOTICE '0276 applied: cpsat FOLLOWED, zero unregistered, guard proven, engine untouched';
END $post$;

-- POST-SNAPSHOT. Pairs with 0276_cpsat_scoreboard_pre so the rewrite is
-- reversible from the ledger without reading this file.
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0276_cpsat_scoreboard_post',
       CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
       n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_intelligence_refresh','ottoq_intelligence_status',
                     'ottoq_intelligence_labels_guard');

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0276_cpsat_enacted_three_times_and_the_scoreboard_called_it_a_stranger', false,
        'ottoq_intelligence_sources gains l2_engine_labels text[] so one source can claim several ledger labels; cpsat claims forward_lex (the objective name it submits under, ottoq_proposer_precedence rank 10), anthropic claims llm_advisor, cuopt claims cuopt_fallback. Refresh attributes through the array. A trigger keeps the scalar label a member of the array and every label claimed once. No engine caller, no dial, no tick-path change; ottoq_decide_tick and ottoq_determinism_pair pinned byte-identical by A7.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- ===========================================================================
-- APPLIED 2026-09-14 00:51:47 UTC (7:51 PM CT, 2026-09-13) as
-- supabase_migrations.schema_migrations version 20260914005147.
--
-- Dry-run: the file above, byte for byte, inside BEGIN ... ROLLBACK. It ran
-- clean and the rollback was verified afterwards (column absent, forward_lex
-- row still present, no lineage row, no schema snapshot). The one deviation
-- from the committed file in the dry-run submission was the added BEGIN/
-- ROLLBACK wrapper; nothing was trimmed. This is the rule 0275 broke on its
-- first apply eight hours earlier -- it trimmed comments out of the dry-run
-- paste and aborted on an assertion that read one of them.
--
-- APPLY OUTPUT, verified afterwards by ottoq_intelligence_status():
--
--   source                 state       decisions  enacted  hours_silent
--   deterministic_v1       FOLLOWED    1,833,982  1,544,376        0.0
--   nemotron               FOLLOWED          280      280          0.0
--   cuopt                  FOLLOWED           27       27        356.0
--   cpsat                  FOLLOWED            3        3          0.0
--   ottoq_service_priority  INVOKED          458        0          0.0
--   anthropic              DECLARED            0        0            -
--
-- CP-SAT reads FOLLOWED for the first time, and the four states now say four
-- different true things about four different failure modes: cuOpt is followed
-- and switched off (356 hours silent behind a dial); service_priority is
-- running and ignored (458 proposals, none enacted); anthropic has a seat and
-- has never sat in it; CP-SAT decides and is obeyed.
--
-- A6's guard test ran and raised as required, so the label guard is proven
-- rather than assumed. A7 confirmed ottoq_decide_tick
-- (fd0bf428abeda40801467fd428a090f1) and ottoq_determinism_pair
-- (8a35b8c874fed154cc216140faec0274) are byte-identical.
-- ===========================================================================
