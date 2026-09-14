-- migration-version: 20260914012023
-- migration-name:    0277_a_source_that_has_proposed_and_one_that_has_never_existed_read_the_same
--
-- 0277  A SOURCE THAT HAS PROPOSED AND ONE THAT HAS NEVER EXISTED READ THE SAME
--
-- ---------------------------------------------------------------------------
-- FOUND BY USING THE INSTRUMENT, ONE HOUR AFTER SHIPPING IT
--
-- 2026-09-14 01:08:57 UTC the Anthropic advisory proposer fired for the first
-- time in its life and submitted 24 proposals through
-- public.ottoq_submit_external_proposal, with reasoning attached:
--
--   "Lowest SoC (7%) gets an open CCS1-capable fast stall."
--
-- ottoq_intelligence_status() then reported anthropic as DECLARED -- the state
-- whose own definition is "registered, and none of the above", i.e. no database
-- presence of any kind. The row was byte-identical to what it said an hour
-- earlier when the proposer had genuinely never run.
--
-- 0275's four states are all defined on ottoq_decisions:
--
--   FOLLOWED  a decision it made was enacted
--   INVOKED   it decided, nothing enacted
--   WIRED     a gate or a ledger exists, it has not decided
--   DECLARED  registered, none of the above
--
-- A proposer that has put rows through the door and is waiting for the decide
-- tick to select one has NOT decided -- so it falls all the way to DECLARED and
-- is indistinguishable from a source that has never done anything at all. That
-- is the same defect class 0275 and 0276 both existed to fix, one rung further
-- out: the census could not say a true thing it had the data for.
--
-- ---------------------------------------------------------------------------
-- THE FIFTH STATE
--
--   FOLLOWED  > INVOKED > PROPOSED > WIRED > DECLARED
--
--   PROPOSED  it has submitted proposals through the door and no decision row
--             has quoted it yet.
--
-- It sits BELOW INVOKED deliberately. ottoq_service_priority has 2,380
-- proposals and 462 decisions, none enacted; it must keep reading INVOKED,
-- because "it decided and was not followed" (db/checks/0212) is a sharper fact
-- than "it proposed". Proposing is what you can say about a source when
-- nothing has decided on it yet -- no more.
--
-- ---------------------------------------------------------------------------
-- WHY THE ALIAS WORK IN 0276 IS WHAT MAKES THIS ONE CHEAP
--
-- Proposals are keyed by SOURCE, decisions by l2_engine LABEL, and the two
-- vocabularies differ exactly where 0276 said they would. Measured now, every
-- proposal source resolves through l2_engine_labels with nothing left over:
--
--   proposal source          proposals  enacted  census row
--   greedy_constrained          12,600    4,169  greedy_constrained
--   ottoq_service_priority       2,380        0  ottoq_service_priority
--   forward_lex                    329        6  cpsat        <- 0276 alias
--   agent_probe                    240       40  agent_probe
--   cuopt                          136       27  cuopt
--   llm_advisor                     24        0  anthropic    <- 0276 alias
--
-- Both aliases are 0276's, and one of them (llm_advisor) was added BEFORE that
-- proposer had ever spoken, precisely so its first appearance would not arrive
-- as a stranger. It spoke ninety minutes later and landed on its own row. P3
-- asserts the mapping is total, because an unclaimed proposal source would
-- create an orphan snapshot row and could collide with a registered one.
--
-- ---------------------------------------------------------------------------
-- THE FUNCTION'S SIGNATURE DOES NOT CHANGE, AND THE DRY RUN IS WHY
--
-- The first draft added proposals/proposals_enacted/last_proposal_at to
-- ottoq_intelligence_status()'s RETURNS TABLE. The byte-for-byte dry run
-- refused it:
--
--   ERROR 42P13: cannot change return type of existing function
--   DETAIL: Row type defined by OUT parameters is different.
--   HINT: Use DROP FUNCTION ottoq_intelligence_status() first.
--
-- scripts/APPLYING.md says NEVER DROP -- CREATE OR REPLACE only, and retiring a
-- signature is a separate, later migration. So the signature stays exactly as
-- 0275 defined it.
--
-- That turns out to be the better shape anyway. The DEFECT was that a proposer
-- read DECLARED, and the state column already exists: fixing the ladder fixes
-- the defect with no signature change at all. The three counts live in
-- ottoq_intelligence_snapshot, which anyone can select from directly, and the
-- assertions below read them from there. Adding them to the function is a
-- convenience, and a convenience is not worth a DROP on a function two hours
-- old whose shape other things may already read.
--
-- ---------------------------------------------------------------------------
-- COST
--
-- One added scan of ottoq_external_proposals: 15,709 rows, 26 MB -- three
-- orders of magnitude below the ottoq_decisions scan the refresh already pays
-- (2.2M rows, 1.5 GB), so the refresh's shape and its ~11 s budget are
-- unchanged. ottoq_intelligence_status still reads only the snapshot; A5
-- re-asserts that structurally, comments stripped, exactly as 0275 A7 does --
-- that assertion aborted 0275's first apply by reading its own documentation,
-- and the stripped form is what fixed it.
--
-- forces_recert = FALSE: two added snapshot columns, one CREATE OR REPLACE of
-- each of the two 0275/0276 functions, no engine caller (P-d re-asserts that),
-- no dial, no tick-path change. A6 pins ottoq_decide_tick and
-- ottoq_determinism_pair byte-identical.
-- ---------------------------------------------------------------------------

SET LOCAL statement_timeout = '10min';

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
-- Checks a and b verbatim from 0221; c narrowed and d paying for the narrowing,
-- for the same reason and with the same structural guarantee as 0276.
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs text; v_callers text;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0277 P-a: certification jobs are still scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0277 P-b: a certification pair is running right now';
  END IF;

  SELECT string_agg(sim_run_id::text || ' (' || COALESCE(run_by,'?') || ')', ', ')
    INTO v_runs FROM public.ottoq_sim_runs
   WHERE status = 'running' AND COALESCE(run_by,'') IN ('cert_harness','benchmark');
  IF v_runs IS NOT NULL THEN
    RAISE EXCEPTION '0277 P-c: a reproducibility-bearing run is in flight: %', v_runs;
  END IF;

  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY n.nspname, p.proname)
    INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.proname NOT IN ('ottoq_intelligence_refresh','ottoq_intelligence_status',
                           'ottoq_intelligence_labels_guard')
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
         ~ 'ottoq_intelligence_';
  IF v_callers IS NOT NULL THEN
    RAISE EXCEPTION '0277 P-d: engine objects now reach ottoq_intelligence_* (%) -- P-c''s narrowing is void', v_callers;
  END IF;

  RAISE NOTICE '0277 P-: no round scheduled, no pair active, no engine caller';
END $inflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0277_proposed_state_pre',
       CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
       n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_intelligence_refresh','ottoq_intelligence_status');

DO $pre$
DECLARE v_n int; v_state text; v_unmapped text;
BEGIN
  -- P1: 0276 must be in place -- this file attributes proposals through its array.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='ottoq_intelligence_sources'
                    AND column_name='l2_engine_labels') THEN
    RAISE EXCEPTION '0277 P1: 0276''s l2_engine_labels is missing -- apply 0276 first';
  END IF;

  -- P2: refuse a double-apply from the catalog alone.
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='ottoq_intelligence_snapshot'
                AND column_name='proposals') THEN
    RAISE EXCEPTION '0277 P2: snapshot.proposals already exists -- refusing to double-apply';
  END IF;

  -- P3: every proposal SOURCE must resolve to exactly one census row. An
  -- unclaimed one would become an orphan snapshot row, and if its name equalled
  -- a registered source the upsert would hit the same conflict target twice.
  SELECT string_agg(DISTINCT p.source, ', ') INTO v_unmapped
    FROM public.ottoq_external_proposals p
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_intelligence_sources s
                      WHERE p.source = ANY (s.l2_engine_labels));
  IF v_unmapped IS NOT NULL THEN
    RAISE EXCEPTION '0277 P3: proposal sources no census row claims: % -- register or alias them first', v_unmapped;
  END IF;

  -- P4: THE BEFORE HALF. anthropic has proposed 24 times and the census calls
  -- it DECLARED. This assertion is false the moment this file has run.
  SELECT count(*) INTO v_n FROM public.ottoq_external_proposals WHERE source = 'llm_advisor';
  IF v_n < 24 THEN
    RAISE EXCEPTION '0277 P4: expected at least 24 llm_advisor proposals, found % -- this is not the database this file was written for', v_n;
  END IF;
  SELECT state INTO v_state FROM public.ottoq_intelligence_status() WHERE source = 'anthropic';
  IF v_state IS DISTINCT FROM 'DECLARED' THEN
    RAISE EXCEPTION '0277 P4: anthropic already reads % -- expected DECLARED, the defect this file ends', COALESCE(v_state,'(absent)');
  END IF;

  RAISE NOTICE '0277 pre: anthropic has % proposals and reads DECLARED', v_n;
END $pre$;

-- ---------------------------------------------------------------------------
-- 1. THE SNAPSHOT CARRIES THE PROPOSAL STREAM
-- ---------------------------------------------------------------------------

ALTER TABLE public.ottoq_intelligence_snapshot
  ADD COLUMN proposals          bigint NOT NULL DEFAULT 0,
  ADD COLUMN proposals_enacted  bigint NOT NULL DEFAULT 0,
  ADD COLUMN last_proposal_at   timestamptz;

COMMENT ON COLUMN public.ottoq_intelligence_snapshot.proposals IS
  '0277: rows this source put through public.ottoq_submit_external_proposal, '
  'attributed through l2_engine_labels because proposals are keyed by SOURCE '
  'and decisions by LABEL. Without this a proposer waiting on the decide tick '
  'was indistinguishable from one that had never run.';

-- ---------------------------------------------------------------------------
-- 2. THE REFRESH READS BOTH STREAMS
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ottoq_intelligence_refresh()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'extensions'
AS $fn$
DECLARE v_now timestamptz := now(); v_rows int; v_unreg int;
BEGIN
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
  -- 0277: the proposal stream, keyed by SOURCE. 15,709 rows / 26 MB against the
  -- decision ledger's 2.2M / 1.5 GB, so this scan is noise next to the one the
  -- refresh already pays.
  props AS (
    SELECT p.source AS lbl,
           count(*) AS pn,
           count(*) FILTER (WHERE p.status = 'enacted') AS pe,
           max(p.created_at) AS plast
      FROM public.ottoq_external_proposals p
     GROUP BY p.source
  ),
  map AS (
    SELECT s.source, u.lbl
      FROM public.ottoq_intelligence_sources s,
           LATERAL unnest(s.l2_engine_labels) AS u(lbl)
  ),
  reg AS (
    SELECT s.source,
           true                              AS registered,
           COALESCE(sum(l.n), 0)::bigint     AS decisions,
           COALESCE(sum(l.e), 0)::bigint     AS enacted,
           max(l.last_at)                    AS last_at,
           COALESCE(sum(r.pn), 0)::bigint    AS proposals,
           COALESCE(sum(r.pe), 0)::bigint    AS proposals_enacted,
           max(r.plast)                      AS last_proposal_at
      FROM public.ottoq_intelligence_sources s
      LEFT JOIN map   m ON m.source = s.source
      LEFT JOIN live  l ON l.lbl    = m.lbl
      LEFT JOIN props r ON r.lbl    = m.lbl
     GROUP BY s.source
  ),
  -- Every label found in EITHER stream that no source claims. Both halves, so a
  -- new engine cannot hide behind having only proposed.
  found AS (
    SELECT lbl FROM live
    UNION
    SELECT lbl FROM props
  ),
  orphan AS (
    SELECT f.lbl                                AS source,
           false                                AS registered,
           COALESCE(l.n, 0)::bigint             AS decisions,
           COALESCE(l.e, 0)::bigint             AS enacted,
           l.last_at                            AS last_at,
           COALESCE(r.pn, 0)::bigint            AS proposals,
           COALESCE(r.pe, 0)::bigint            AS proposals_enacted,
           r.plast                              AS last_proposal_at
      FROM found f
      LEFT JOIN live  l ON l.lbl = f.lbl
      LEFT JOIN props r ON r.lbl = f.lbl
     WHERE NOT EXISTS (SELECT 1 FROM map m WHERE m.lbl = f.lbl)
  ),
  merged AS (
    SELECT * FROM reg
    UNION ALL
    SELECT * FROM orphan
  )
  INSERT INTO public.ottoq_intelligence_snapshot
    (source, registered, decisions, enacted, last_decision_at,
     proposals, proposals_enacted, last_proposal_at,
     window_from, window_to, computed_at)
  SELECT m.source, m.registered, m.decisions, m.enacted, m.last_at,
         m.proposals, m.proposals_enacted, m.last_proposal_at,
         w.lo, w.hi, v_now
    FROM merged m CROSS JOIN win w
  ON CONFLICT (source) DO UPDATE SET
    registered        = EXCLUDED.registered,
    decisions         = EXCLUDED.decisions,
    enacted           = EXCLUDED.enacted,
    last_decision_at  = EXCLUDED.last_decision_at,
    proposals         = EXCLUDED.proposals,
    proposals_enacted = EXCLUDED.proposals_enacted,
    last_proposal_at  = EXCLUDED.last_proposal_at,
    window_from       = EXCLUDED.window_from,
    window_to         = EXCLUDED.window_to,
    computed_at       = EXCLUDED.computed_at;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  DELETE FROM public.ottoq_intelligence_snapshot WHERE computed_at < v_now;
  SELECT count(*) INTO v_unreg FROM public.ottoq_intelligence_snapshot WHERE NOT registered;

  RETURN jsonb_build_object('ok', true, 'sources', v_rows, 'unregistered', v_unreg,
                            'computed_at', v_now);
END $fn$;

COMMENT ON FUNCTION public.ottoq_intelligence_refresh() IS
  '0277: one scan of ottoq_decisions and one of ottoq_external_proposals into '
  'ottoq_intelligence_snapshot, both attributed through l2_engine_labels. '
  'Writes a row for every label it FINDS in EITHER stream, so a source that has '
  'only ever proposed still appears. Safe to call any time; writes nothing the '
  'engine reads.';

-- ---------------------------------------------------------------------------
-- 3. THE FIFTH STATE
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ottoq_intelligence_status()
RETURNS TABLE(source text, kind text, state text,
              gate_param_key text, gate_override numeric, gate_catalog_default numeric,
              gate_enabled boolean,
              decisions bigint, enacted bigint,
              last_decision_at timestamptz, hours_silent numeric,
              own_ledger text, own_ledger_rows bigint, own_ledger_answered bigint,
              code_lives_in text, note text,
              window_from timestamptz, window_to timestamptz,
              computed_at timestamptz, snapshot_age_hours numeric)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'extensions'
AS $fn$
  -- Reads the SNAPSHOT only. A5 asserts the expensive ledger is not in this
  -- read path; the live aggregate is an 11-second, 1.5 GB scan and this
  -- function is meant to be called casually.
  WITH cuopt AS (
    SELECT count(*) AS rows_all,
           count(*) FILTER (WHERE http_status IS NOT NULL) AS answered
      FROM public.cuopt_invocation_log
  )
  SELECT n.source,
         COALESCE(s.kind, 'unknown') AS kind,
         CASE
           WHEN NOT n.registered            THEN 'UNREGISTERED'
           WHEN n.enacted   > 0             THEN 'FOLLOWED'
           WHEN n.decisions > 0             THEN 'INVOKED'
           -- 0277: it put rows through the door and nothing has decided on them
           -- yet. Below INVOKED on purpose: "decided and not followed" is a
           -- sharper fact than "proposed", so a source with decisions keeps it.
           WHEN n.proposals > 0             THEN 'PROPOSED'
           WHEN s.gate_param_key IS NOT NULL OR s.own_ledger IS NOT NULL THEN 'WIRED'
           ELSE 'DECLARED'
         END AS state,
         s.gate_param_key,
         CASE WHEN s.gate_param_key IS NULL THEN NULL
              ELSE public.ottoq_policy_get(NULL, s.gate_param_key, NULL) END,
         CASE WHEN s.gate_param_key IS NULL THEN NULL
              ELSE (SELECT c.default_value::numeric FROM public.ottoq_policy_param_catalog c
                     WHERE c.param_key = s.gate_param_key) END,
         CASE WHEN s.gate_param_key IS NULL THEN NULL
              WHEN public.ottoq_policy_get(NULL, s.gate_param_key, NULL) IS NULL THEN NULL
              ELSE public.ottoq_policy_get(NULL, s.gate_param_key, NULL) <> 0 END,
         n.decisions,
         n.enacted,
         n.last_decision_at,
         -- silence is measured against the LATER of the two streams: a source
         -- that is proposing steadily and simply not being selected is not
         -- silent, and 0209 spent an evening on exactly that confusion.
         CASE WHEN GREATEST(COALESCE(n.last_decision_at, '-infinity'::timestamptz),
                            COALESCE(n.last_proposal_at, '-infinity'::timestamptz))
                   = '-infinity'::timestamptz THEN NULL
              -- clamped at zero: window_to is the last DECISION in the ledger, so
              -- a source proposing right now is newer than the window and would
              -- otherwise report negative hours of silence.
              ELSE GREATEST(0, round((EXTRACT(EPOCH FROM (n.window_to -
                     GREATEST(COALESCE(n.last_decision_at, '-infinity'::timestamptz),
                              COALESCE(n.last_proposal_at, '-infinity'::timestamptz))))/3600)::numeric, 1))
         END,
         s.own_ledger,
         CASE WHEN s.own_ledger = 'cuopt_invocation_log' THEN c.rows_all END,
         CASE WHEN s.own_ledger = 'cuopt_invocation_log' THEN c.answered END,
         COALESCE(s.code_lives_in, '(unregistered -- nobody has said)'),
         s.note,
         n.window_from,
         n.window_to,
         n.computed_at,
         round((EXTRACT(EPOCH FROM (now() - n.computed_at))/3600)::numeric, 2)
    FROM public.ottoq_intelligence_snapshot n
    CROSS JOIN cuopt c
    LEFT JOIN public.ottoq_intelligence_sources s ON s.source = n.source
   ORDER BY (CASE
               WHEN NOT n.registered THEN 0
               WHEN n.enacted   > 0  THEN 1
               WHEN n.decisions > 0  THEN 2
               WHEN n.proposals > 0  THEN 3
               WHEN s.gate_param_key IS NOT NULL OR s.own_ledger IS NOT NULL THEN 4
               ELSE 5 END), n.enacted DESC, n.proposals DESC, n.source;
$fn$;

COMMENT ON FUNCTION public.ottoq_intelligence_status() IS
  '0277: five states -- FOLLOWED > INVOKED > PROPOSED > WIRED > DECLARED, plus '
  'UNREGISTERED. PROPOSED exists because the Anthropic advisor submitted 24 '
  'proposals on 2026-09-14 and this function called it DECLARED, the state '
  'meaning "no database presence of any kind". Reads the snapshot, never '
  'ottoq_decisions.';

-- ---------------------------------------------------------------------------
-- 4. PROOF
-- ---------------------------------------------------------------------------

DO $refresh$
DECLARE v jsonb;
BEGIN
  v := public.ottoq_intelligence_refresh();
  RAISE NOTICE '0277 refresh: %', v;
END $refresh$;

DO $post$
DECLARE r record; v_n int; v_code text; v_pin text;
BEGIN
  -- A1: THE AFTER HALF. anthropic reads PROPOSED and carries its 24 rows.
  -- The counts come from the SNAPSHOT TABLE, not the status function -- see the
  -- signature note in the header for why the function's shape did not change.
  SELECT st.state, sn.proposals, sn.decisions, sn.last_proposal_at
    INTO r
    FROM public.ottoq_intelligence_snapshot sn
    JOIN public.ottoq_intelligence_status() st ON st.source = sn.source
   WHERE sn.source = 'anthropic';
  IF r.state IS NULL THEN RAISE EXCEPTION '0277 A1: anthropic has no row'; END IF;
  IF r.state <> 'PROPOSED' THEN
    RAISE EXCEPTION '0277 A1: anthropic reads %, expected PROPOSED', r.state;
  END IF;
  IF r.proposals < 24 OR r.decisions <> 0 THEN
    RAISE EXCEPTION '0277 A1: anthropic reads %/% proposals/decisions -- expected >=24 and 0',
                    r.proposals, r.decisions;
  END IF;
  RAISE NOTICE '0277 A1: anthropic PROPOSED, % proposals, last at %', r.proposals, r.last_proposal_at;

  -- A2: the ladder does not demote anyone. ottoq_service_priority has 2,380
  -- proposals AND 462 decisions; it must stay INVOKED, because 0212's finding
  -- is the sharper one and PROPOSED would bury it.
  SELECT st.state, sn.proposals INTO r
    FROM public.ottoq_intelligence_snapshot sn
    JOIN public.ottoq_intelligence_status() st ON st.source = sn.source
   WHERE sn.source = 'ottoq_service_priority';
  IF r.state <> 'INVOKED' THEN
    RAISE EXCEPTION '0277 A2: ottoq_service_priority reads %, expected INVOKED -- PROPOSED must not outrank a source that decided', r.state;
  END IF;
  IF r.proposals < 2380 THEN
    RAISE EXCEPTION '0277 A2: ottoq_service_priority shows % proposals, expected >= 2380', r.proposals;
  END IF;

  -- A3: cpsat keeps FOLLOWED and now shows the proposals behind it.
  SELECT st.state, sn.enacted, sn.proposals INTO r
    FROM public.ottoq_intelligence_snapshot sn
    JOIN public.ottoq_intelligence_status() st ON st.source = sn.source
   WHERE sn.source = 'cpsat';
  IF r.state <> 'FOLLOWED' OR r.enacted < 6 OR r.proposals < 329 THEN
    RAISE EXCEPTION '0277 A3: cpsat reads % with %/% enacted/proposals -- expected FOLLOWED, >=6, >=329',
                    r.state, r.enacted, r.proposals;
  END IF;

  -- A4: the census is still complete in BOTH streams.
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_snapshot WHERE NOT registered;
  IF v_n <> 0 THEN RAISE EXCEPTION '0277 A4: % unregistered sources', v_n; END IF;
  SELECT count(DISTINCT p.source) INTO v_n FROM public.ottoq_external_proposals p
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_intelligence_snapshot n WHERE n.source = p.source)
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_intelligence_sources s WHERE p.source = ANY (s.l2_engine_labels));
  IF v_n <> 0 THEN RAISE EXCEPTION '0277 A4: % proposal sources are in no snapshot row', v_n; END IF;

  -- A5: the status function still does not read the decision ledger. Comments
  -- stripped first -- 0275's first apply aborted on its own prose, and 0270's
  -- A1 did the same thing the same morning.
  SELECT regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') INTO v_code
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_intelligence_status';
  IF v_code ILIKE '%ottoq_decisions%' THEN
    RAISE EXCEPTION '0277 A5: ottoq_intelligence_status reads ottoq_decisions -- that is an 11 s scan';
  END IF;
  IF v_code ILIKE '%ottoq_external_proposals%' THEN
    RAISE EXCEPTION '0277 A5: ottoq_intelligence_status reads ottoq_external_proposals -- the snapshot carries it';
  END IF;

  -- A6: forces_recert=FALSE evidence.
  SELECT md5(prosrc) INTO v_pin FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_decide_tick';
  IF v_pin <> 'fd0bf428abeda40801467fd428a090f1' THEN
    RAISE EXCEPTION '0277 A6: ottoq_decide_tick changed (%)', v_pin;
  END IF;
  SELECT md5(prosrc) INTO v_pin FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_pin <> '8a35b8c874fed154cc216140faec0274' THEN
    RAISE EXCEPTION '0277 A6: ottoq_determinism_pair changed (%)', v_pin;
  END IF;

  RAISE NOTICE '0277 applied: five states, anthropic PROPOSED, engine untouched';
END $post$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0277_proposed_state_post',
       CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
       n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_intelligence_refresh','ottoq_intelligence_status');

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0277_a_source_that_has_proposed_and_one_that_has_never_existed_read_the_same', false,
        'ottoq_intelligence_snapshot gains proposals/proposals_enacted/last_proposal_at; the refresh scans ottoq_external_proposals (15,709 rows) alongside the decision ledger and attributes both through l2_engine_labels; ottoq_intelligence_status gains a fifth state PROPOSED, ranked below INVOKED. Read-only census objects, no engine caller, no dial, no tick-path change; ottoq_decide_tick and ottoq_determinism_pair pinned byte-identical by A6.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- ===========================================================================
-- APPLIED 2026-09-14 01:20:23 UTC (8:20 PM CT, 2026-09-13) as
-- supabase_migrations.schema_migrations version 20260914012023.
--
-- Dry-run: the file above, byte for byte, inside BEGIN ... ROLLBACK, twice --
-- and the FIRST dry run is the reason this file has the shape it has. It
-- refused with 42P13 (cannot change return type of existing function) because
-- the draft added three OUT parameters to ottoq_intelligence_status(). Postgres
-- wants a DROP for that and APPLYING.md says never DROP, so the signature was
-- reverted to 0275's exactly and the counts moved to the snapshot table, where
-- the assertions read them. That is the better shape anyway: the defect was a
-- proposer reading DECLARED, and the state column already existed.
--
-- The second dry run ran clean and the rollback was verified afterwards
-- (no column, no lineage row, no schema snapshot, anthropic still DECLARED).
--
-- VERIFIED AFTER APPLY:
--
--   state      source                  dec   enacted  props  props_enacted  silent
--   FOLLOWED   greedy_constrained   87,004    84,155 12,600          4,169     0.0
--   FOLLOWED   nemotron                301       301      0              0     0.0
--   FOLLOWED   cuopt                    27        27    136             27   356.6
--   FOLLOWED   cpsat                     6         6    329              6     0.0
--   INVOKED    ottoq_service_priority  462         0  2,380              0     0.2
--   PROPOSED   anthropic                 0         0     24              0     0.0
--
-- Six rows, six different true things. anthropic is PROPOSED rather than
-- DECLARED, which is the whole point. ottoq_service_priority keeps INVOKED with
-- 2,380 proposals and nothing enacted on either stream -- db/checks/0212's
-- finding, now legible at a glance. cuopt is followed and switched off. cpsat
-- is followed and live.
-- ===========================================================================
