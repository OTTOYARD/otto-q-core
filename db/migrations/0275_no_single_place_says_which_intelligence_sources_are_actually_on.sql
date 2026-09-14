-- migration-version: PENDING
-- migration-name:    0275_no_single_place_says_which_intelligence_sources_are_actually_on
--
-- 0275  NO SINGLE PLACE SAYS WHICH INTELLIGENCE SOURCES ARE ACTUALLY ON
--
-- ---------------------------------------------------------------------------
-- WHY THIS EXISTS
--
-- db/checks/0208 answered "are we using Nemotron, cuOpt, CP-SAT and the
-- Anthropic key" and it took an hour of archaeology across four tables, a
-- policy catalog, a proposer ledger and the repo's workflow files.
--
-- Then it got one of them wrong. 0208's engine table came from a query ending
-- in LIMIT 12; there are sixteen distinct l2_engine labels, and the limit
-- silently dropped cuOpt -- the source the file was about. The correction is
-- appended to 0208, and the corrected fact is sharper than the error: cuOpt
-- has decided 27 times and ALL 27 WERE ENACTED, so the engine does not ignore
-- it; a dial says it may not speak.
--
-- Both halves are the same defect. "Which sources are on, when did each last
-- decide, was it followed" has no answer you can SELECT, so answering it means
-- writing a query by hand, and a query written by hand can end in LIMIT 12.
--
-- ---------------------------------------------------------------------------
-- THE FIRST DRAFT OF THIS FILE TOOK ELEVEN SECONDS PER CALL. MEASURED.
--
-- It computed everything live from ottoq_decisions. EXPLAIN ANALYZE on that
-- one aggregate:
--
--   Parallel Seq Scan on ottoq_decisions  (2,177,338 rows)
--   Buffers: shared hit=32,425 read=200,664          -- 1.5 GB off disk
--   Execution Time: 11,187 ms
--
-- and the post-apply assertions called it twelve times, so the dry run hit the
-- sixty-second timeout and never reached its own verdict. That is how the
-- defect was found: the file's own proof refused to run.
--
-- An eleven-second status function is not a status function. It is db/checks/
-- 0098's twenty-two-second KPI view again -- the same class, written by the
-- same hand, two weeks later. So the shape changed:
--
--   ottoq_intelligence_refresh()   ONE pass over ottoq_decisions, using
--                                  GROUP BY ROLLUP so the per-label facts and
--                                  the window come from the same scan, and
--                                  writes ottoq_intelligence_snapshot.
--   ottoq_intelligence_status()    reads the SNAPSHOT, never the ledger.
--                                  Eighteen rows in, eighteen rows out.
--
-- A7 asserts that structurally: ottoq_intelligence_status must not mention
-- ottoq_decisions at all. An assertion about speed that measured milliseconds
-- would pass on a warm cache and prove nothing; an assertion that the
-- expensive table is not in the read path cannot.
--
-- The cost of that shape is staleness, so staleness is a COLUMN. Every row
-- carries computed_at and snapshot_age_hours. A number that might be a day old
-- says so.
--
-- ---------------------------------------------------------------------------
-- THE CENSUS CANNOT OMIT A LABEL, BY CONSTRUCTION
--
-- The registry names eighteen sources. The refresh does NOT look those up --
-- it writes a row for every label it FINDS, and marks each registered or not.
-- So a new decision engine appearing in the ledger lands in the snapshot as
-- registered=false and surfaces in the status as state UNREGISTERED, rather
-- than being quietly absent. A6 asserts there are none today.
--
-- That is the structural version of the lesson 0208 paid for: a census that
-- lists what it was told to look for is not a census.
--
-- ---------------------------------------------------------------------------
-- THE FOUR STATES
--
--   FOLLOWED      at least one decision it proposed was ENACTED
--   INVOKED       it decided, and nothing it decided was enacted
--   WIRED         plumbing exists here -- a gate parameter or its own ledger
--                 -- and it has decided nothing in the window
--   DECLARED      registered, and neither of the above
--   UNREGISTERED  it decides and nobody put it in the census
--
-- TWO SOURCES HAVE NO DATABASE PRESENCE, measured rather than assumed: no
-- function, no policy key, no decision row for either CP-SAT or Anthropic.
-- Their code is real and lives in the repo. Leaving them out would make the
-- status read healthier than the system is, so they are in it at DECLARED
-- with the note saying where the code actually is.
--
-- AND ONE THING MEASURED WHILE BUILDING IT. ottoq_policy_get DOES NOT READ
-- ottoq_policy_param_catalog -- its body never mentions the table, and
-- ottoq_policy_get(NULL, k, 7) returns 7 for a key whose catalog default is 1.
-- So default_value is DOCUMENTATION, not behaviour: a dial's effective default
-- is whatever each call site hardcodes, and if the two disagree nothing
-- notices. This function refuses to collapse them -- gate_override is the
-- stored value, gate_catalog_default is the catalog's, and gate_enabled is
-- NULL, not false, when nothing is stored. A3b asserts that on a real key.
--
-- AND A SECOND MEASURED DEFECT, IN THE SECOND DRAFT, FOUND THE SAME WAY.
-- With the snapshot shape in place the file still would not run: its
-- PRE-FLIGHT read ottoq_decisions three times (a filtered count for cuOpt, a
-- count(DISTINCT l2_engine), an EXISTS) and A4 read it a fourth, each one the
-- same 11-second seq scan, on top of the refresh's own. Five scans is ~55 s
-- against a 60 s tool ceiling -- a migration that passes or fails depending on
-- how warm the cache is.
--
-- So the order changed too. THE SCAN HAPPENS EXACTLY ONCE, in the refresh, and
-- every assertion afterwards reads the snapshot. P1 still runs first and still
-- refuses a double-apply from the catalogs alone, which costs nothing; the
-- facts that used to be pre-flight (cuOpt 27/27, service_priority 452/0,
-- sixteen labels) are asserted after the refresh instead, against the rows the
-- refresh wrote. They fail the same way and roll the same transaction back --
-- the whole file is one transaction -- they just do not each pay for their own
-- scan.
--
-- The lesson is the same one twice in one file: an instrument that is too
-- expensive to run is not an instrument, and the only reason I know either
-- time is that the proof refused to execute.
--
-- forces_recert = FALSE: two tables, one read-only status function, one
-- refresh that writes only its own snapshot, no engine caller, no dial
-- touched. A5 asserts ottoq_decide_tick and ottoq_determinism_pair are
-- byte-identical afterwards.
-- ---------------------------------------------------------------------------

SET LOCAL statement_timeout = '10min';

DO $pre$
DECLARE v_gate text;
BEGIN
  IF to_regclass('public.ottoq_intelligence_sources') IS NOT NULL
     OR to_regclass('public.ottoq_intelligence_snapshot') IS NOT NULL THEN
    RAISE EXCEPTION '0275 P1: a 0275 object already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public'
                AND p.proname IN ('ottoq_intelligence_status','ottoq_intelligence_refresh')) THEN
    RAISE EXCEPTION '0275 P1: a 0275 function already exists';
  END IF;

  -- P2: the one precondition that costs nothing to check -- it reads a
  -- five-row policy table, not the decision ledger. Everything else 0208
  -- measured is asserted AFTER the refresh, against the snapshot, so the
  -- 11-second scan is paid for once in this file rather than four times.
  SELECT param_value INTO v_gate FROM public.ottoq_policy_params
   WHERE scope_type='global' AND param_key='cuopt_propose_enabled';
  IF COALESCE(v_gate,'(unset)') <> '0' THEN
    RAISE EXCEPTION '0275 P2: cuopt_propose_enabled is now % -- expected 0', COALESCE(v_gate,'(unset)');
  END IF;
  RAISE NOTICE '0275 pre: cuOpt gate reads 0; the ledger facts are asserted after the refresh';
END $pre$;

CREATE TABLE public.ottoq_intelligence_sources (
  source           text PRIMARY KEY,
  kind             text NOT NULL CHECK (kind IN ('deterministic','solver_external','solver_local',
                                                 'llm','heuristic','baseline','fallback','probe')),
  gate_param_key   text,
  l2_engine_label  text UNIQUE,
  own_ledger       text,
  code_lives_in    text NOT NULL,
  note             text,
  registered_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_intelligence_sources IS
  '0275: the census of everything that can decide in this engine, including '
  'the sources whose code lives outside the database. Completeness is not '
  'trusted to this table -- ottoq_intelligence_refresh writes what it FINDS in '
  'the ledger and flags anything unregistered, because a registry that lists '
  'only what it was told to look for is how db/checks/0208 lost cuOpt.';

INSERT INTO public.ottoq_intelligence_sources
  (source, kind, gate_param_key, l2_engine_label, own_ledger, code_lives_in, note) VALUES
  ('deterministic_v1', 'deterministic', NULL, 'deterministic_v1', NULL,
   'public.ottoq_decide_tick',
   'The disposer. Not a proposer and not optional -- it is the shield every '
   'other source proposes through. In the census so the contrast is visible.'),
  ('cuopt', 'solver_external', 'cuopt_propose_enabled', 'cuopt', 'cuopt_invocation_log',
   'edge function ottoq-cuopt-propose -> optimize.api.nvidia.com',
   'Gate default 0 AND global override 0. 27 decisions, ALL 27 ENACTED, none '
   'in a cert run, none since 2026-08-30. The engine does not ignore cuOpt; a '
   'dial says it may not speak. Its ledger has three different counts -- '
   '20,424 rows, 551 real attempts, 16 answered by NVIDIA -- and half of it is '
   'the single abstain reason policy_disabled. See db/checks/0208.'),
  ('nemotron', 'llm', 'orchestrator_agent_enabled', 'nemotron', NULL,
   'edge function / ottoq_apply_ops_action, ottoq_run_blackbox',
   'Writes run policy dials via ottoq_policy_set(p_by:''ottoq_prime''), a path '
   'the L1 shield does not gate because a dial write is not a stall '
   'assignment. No stored override; the single call site '
   '(ottoq_sim_decide_and_dispatch) passes fallback 1, so it is effectively '
   'ON. 262 decisions, all enacted, on two days only, silent since 2026-08-30 '
   'for a reason not yet established -- the caller is outside this database.'),
  ('cpsat', 'solver_local', NULL, 'cpsat', NULL,
   'solvers/cpsat/model.py + bridge/proposer_bridge.py, submitted through '
   'public.ottoq_submit_external_proposal',
   'No function, no policy key and no decision row in this database -- '
   'measured. The bridge is real and uses the same door cuOpt uses; '
   '.github/workflows/proposer-loop.yml is workflow_dispatch only, so nothing '
   'fires it on a schedule.'),
  ('anthropic', 'llm', NULL, NULL, NULL,
   'bridge/llm_proposer.py, edge-functions/ottoq-ottocommand/index.ts, '
   '.github/workflows/proposer-loop.yml (advisory fire only)',
   'No database presence of any kind. The key is live; the CP-SAT loop does '
   'not use it and no engine function references it.'),
  ('ottoq_service_priority', 'heuristic', NULL, 'ottoq_service_priority', NULL,
   'public.ottoq_service_priority_propose',
   'Not switched off -- running and ignored. 452 proposals, ZERO enacted, '
   'still proposing. A quieter failure than a closed dial.'),
  ('inspect_seam',           'heuristic', NULL, 'inspect_seam',           NULL,
   'ottoq_decide_tick inspection seam', 'Local heuristic on the decide path.'),
  ('greedy_constrained',     'heuristic', NULL, 'greedy_constrained',     NULL,
   'ottoq_decide_tick stall assignment', 'The local greedy pick, shield-constrained.'),
  ('reservation_honoured',   'heuristic', NULL, 'reservation_honoured',   NULL,
   'ottoq_honour_reservation_proposal', 'Enacts a standing reservation.'),
  ('reservation_reassigned', 'heuristic', NULL, 'reservation_reassigned', NULL,
   'ottoq_honour_reservation_proposal', 'Moves a reservation that no longer fits.'),
  ('reservation_broken',     'heuristic', NULL, 'reservation_broken',     NULL,
   'ottoq_honour_reservation_proposal', 'Breaks a reservation physical reality overruled.'),
  ('needs_card',             'heuristic', NULL, 'needs_card',             NULL,
   'ottoq_decide_tick needs-card space routing',
   'Routes the site''s scarcest spaces. 20,360 decisions, 3,627 enacted.'),
  ('charge_disposition',     'heuristic', NULL, 'charge_disposition',     NULL,
   'ottoq_decide_tick charge disposition', 'Every one of its decisions is enacted.'),
  ('service_sequencing',     'heuristic', NULL, 'service_sequencing',     NULL,
   'ottoq_decide_tick service sequencing', 'The third proposer seat.'),
  ('fifo',                   'baseline',  NULL, 'fifo',                   NULL,
   'ottoq_fifo_tick / the A/B pair''s p_policy seat 1',
   'A comparison arm, not an intelligence source. Evaluates no L1 rules -- see '
   'CLAUDE.md C5''s second correction.'),
  ('greedy',                 'baseline',  NULL, 'greedy',                 NULL,
   'ottoq_greedy_tick / the A/B pair''s p_policy seat 2',
   'A comparison arm, not an intelligence source. Evaluates no L1 rules.'),
  ('deterministic_fallback', 'fallback',  NULL, 'deterministic_fallback', NULL,
   'ottoq_decide_tick fallback branch',
   '79 decisions, 7 enacted, none since 2026-08-29. What the engine does when '
   'the normal path cannot answer.'),
  ('agent_probe',            'probe',     NULL, 'agent_probe',            NULL,
   'the agent-layer posture probe (task #98)',
   '20 decisions, all enacted, 2026-09-09. An instrument, not a source; in the '
   'census because leaving instruments out is how a census stops being one.');

CREATE TABLE public.ottoq_intelligence_snapshot (
  source            text PRIMARY KEY,
  registered        boolean     NOT NULL,
  decisions         bigint      NOT NULL DEFAULT 0,
  enacted           bigint      NOT NULL DEFAULT 0,
  last_decision_at  timestamptz,
  window_from       timestamptz,
  window_to         timestamptz,
  computed_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_intelligence_snapshot IS
  '0275: one row per source AND per l2_engine label found in the ledger, '
  'whichever is larger. registered=false means something decided that the '
  'census does not know about. Refreshed by ottoq_intelligence_refresh; '
  'ottoq_intelligence_status reads this and never ottoq_decisions, because the '
  'live aggregate is an 11-second, 1.5 GB scan.';

CREATE OR REPLACE FUNCTION public.ottoq_intelligence_refresh()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'extensions'
AS $fn$
DECLARE v_now timestamptz := now(); v_rows int; v_unreg int;
BEGIN
  -- ONE pass. GROUP BY ROLLUP gives the per-label rows and the overall window
  -- from the same scan; GROUPING() tells the total row apart from a genuine
  -- NULL label, which a plain ROLLUP could not.
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
  win AS (SELECT lo, hi FROM agg WHERE is_total = 1),
  live AS (SELECT lbl, n, e, hi AS last_at FROM agg WHERE is_total = 0 AND lbl IS NOT NULL),
  -- FULL OUTER so a registered source with no decisions keeps its row AND an
  -- unregistered label that decided gets one. Neither side can hide the other.
  merged AS (
    SELECT COALESCE(s.source, l.lbl)        AS source,
           (s.source IS NOT NULL)           AS registered,
           COALESCE(l.n, 0)                 AS decisions,
           COALESCE(l.e, 0)                 AS enacted,
           l.last_at
      FROM public.ottoq_intelligence_sources s
      FULL OUTER JOIN live l ON l.lbl = s.l2_engine_label
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
  -- a row this refresh did not touch describes a source that no longer exists
  DELETE FROM public.ottoq_intelligence_snapshot WHERE computed_at < v_now;
  SELECT count(*) INTO v_unreg FROM public.ottoq_intelligence_snapshot WHERE NOT registered;

  RETURN jsonb_build_object('ok', true, 'sources', v_rows, 'unregistered', v_unreg,
                            'computed_at', v_now);
END $fn$;

COMMENT ON FUNCTION public.ottoq_intelligence_refresh() IS
  '0275: one scan of ottoq_decisions (~11 s, ~1.5 GB) into '
  'ottoq_intelligence_snapshot. Writes a row for every label it FINDS, not '
  'every source it was told about, so a new decision engine cannot go '
  'uncounted. Safe to call any time; it writes nothing the engine reads.';

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
  -- Reads the SNAPSHOT. Never ottoq_decisions -- A7 asserts that, because the
  -- live aggregate is an 11-second scan and this function is meant to be
  -- called casually.
  WITH cuopt AS (
    SELECT count(*) AS rows_all,
           count(*) FILTER (WHERE http_status IS NOT NULL) AS answered
      FROM public.cuopt_invocation_log
  )
  SELECT n.source,
         COALESCE(s.kind, 'unknown')                    AS kind,
         CASE
           WHEN NOT n.registered            THEN 'UNREGISTERED'
           WHEN n.enacted   > 0             THEN 'FOLLOWED'
           WHEN n.decisions > 0             THEN 'INVOKED'
           WHEN s.gate_param_key IS NOT NULL OR s.own_ledger IS NOT NULL THEN 'WIRED'
           ELSE 'DECLARED'
         END AS state,
         s.gate_param_key,
         -- the STORED value only. ottoq_policy_get never consults the catalog,
         -- so NULL here means "nobody set it", not "it is off".
         CASE WHEN s.gate_param_key IS NULL THEN NULL
              ELSE public.ottoq_policy_get(NULL, s.gate_param_key, NULL) END AS gate_override,
         CASE WHEN s.gate_param_key IS NULL THEN NULL
              ELSE (SELECT c.default_value::numeric FROM public.ottoq_policy_param_catalog c
                     WHERE c.param_key = s.gate_param_key) END AS gate_catalog_default,
         CASE WHEN s.gate_param_key IS NULL THEN NULL
              WHEN public.ottoq_policy_get(NULL, s.gate_param_key, NULL) IS NULL THEN NULL
              ELSE public.ottoq_policy_get(NULL, s.gate_param_key, NULL) <> 0 END AS gate_enabled,
         n.decisions,
         n.enacted,
         n.last_decision_at,
         CASE WHEN n.last_decision_at IS NULL THEN NULL
              ELSE round((EXTRACT(EPOCH FROM (n.window_to - n.last_decision_at))/3600)::numeric, 1) END,
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
               WHEN s.gate_param_key IS NOT NULL OR s.own_ledger IS NOT NULL THEN 3
               ELSE 4 END), n.enacted DESC, n.source;
$fn$;

COMMENT ON FUNCTION public.ottoq_intelligence_status() IS
  '0275: which sources are on, when each last decided, and whether anything it '
  'decided was followed. Reads ottoq_intelligence_snapshot, so every row '
  'carries computed_at and snapshot_age_hours -- a number that might be a day '
  'old says so. window_from / window_to are the decision ledger''s own bounds, '
  'roughly fifteen days, not the engine''s whole life. gate_override is the '
  'STORED value and gate_enabled is NULL, not false, when nothing is stored: '
  'ottoq_policy_get does not consult ottoq_policy_param_catalog, so the '
  'effective value of an unset dial is whatever the call site hardcodes.';

REVOKE ALL ON FUNCTION public.ottoq_intelligence_status() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ottoq_intelligence_refresh() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_intelligence_status() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_intelligence_refresh() TO service_role;
GRANT SELECT ON public.ottoq_intelligence_sources  TO authenticated, service_role;
GRANT SELECT ON public.ottoq_intelligence_snapshot TO authenticated, service_role;

SELECT public.ottoq_intelligence_refresh();

DO $post$
DECLARE v_n int; v_states int; v_unreg int; v_src text; v_r record;
BEGIN
  -- A1: eighteen registered sources, and the snapshot covers every one of them
  -- plus anything else that decided.
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_sources;
  IF v_n <> 18 THEN RAISE EXCEPTION '0275 A1: registry holds % rows, expected 18', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_snapshot;
  IF v_n <> 18 THEN RAISE EXCEPTION '0275 A1: snapshot holds % rows, expected 18', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_status();
  IF v_n <> 18 THEN RAISE EXCEPTION '0275 A1: status returned % rows', v_n; END IF;

  -- A2: THE LADDER MUST DISCRIMINATE. Everything on one rung measures nothing.
  SELECT count(DISTINCT state) INTO v_states FROM public.ottoq_intelligence_status();
  IF v_states < 3 THEN
    RAISE EXCEPTION '0275 A2: the ladder returned only % distinct states', v_states;
  END IF;

  -- A3: it lands where the corrected 0208 measured, source by source, so a
  -- derivation that produces the right SHAPE for the wrong reasons still fails.
  SELECT * INTO v_r FROM public.ottoq_intelligence_status() WHERE source='cuopt';
  IF v_r.state <> 'FOLLOWED' OR v_r.decisions <> 27 OR v_r.enacted <> 27 THEN
    RAISE EXCEPTION '0275 A3: cuopt reads state=% %/% -- expected FOLLOWED 27/27',
                    v_r.state, v_r.decisions, v_r.enacted;
  END IF;
  IF v_r.gate_enabled IS NOT FALSE THEN
    RAISE EXCEPTION '0275 A3: cuopt gate_enabled reads %, expected false', v_r.gate_enabled;
  END IF;
  IF COALESCE(v_r.own_ledger_rows,0) < 20000 OR COALESCE(v_r.own_ledger_answered,0) <> 16 THEN
    RAISE EXCEPTION '0275 A3: cuopt ledger reads %/% rows/answered -- the join is not wired',
                    v_r.own_ledger_rows, v_r.own_ledger_answered;
  END IF;

  SELECT * INTO v_r FROM public.ottoq_intelligence_status() WHERE source='ottoq_service_priority';
  IF v_r.state <> 'INVOKED' THEN
    RAISE EXCEPTION '0275 A3: ottoq_service_priority reads %, expected INVOKED', v_r.state;
  END IF;

  SELECT * INTO v_r FROM public.ottoq_intelligence_status() WHERE source='deterministic_v1';
  IF v_r.state <> 'FOLLOWED' OR v_r.enacted < 1000000 THEN
    RAISE EXCEPTION '0275 A3: the local path reads state=% enacted=%', v_r.state, v_r.enacted;
  END IF;

  SELECT * INTO v_r FROM public.ottoq_intelligence_status() WHERE source='anthropic';
  IF v_r.state <> 'DECLARED' OR v_r.gate_param_key IS NOT NULL THEN
    RAISE EXCEPTION '0275 A3: anthropic reads state=% gate=%, expected DECLARED with no dial',
                    v_r.state, v_r.gate_param_key;
  END IF;

  -- A3b: unset must not read as off.
  SELECT * INTO v_r FROM public.ottoq_intelligence_status() WHERE source='nemotron';
  IF v_r.gate_override IS NOT NULL OR v_r.gate_enabled IS NOT NULL THEN
    RAISE EXCEPTION '0275 A3b: nemotron has no stored override, so gate_override and '
                    'gate_enabled must both be NULL; got % / %', v_r.gate_override, v_r.gate_enabled;
  END IF;
  IF v_r.gate_catalog_default IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION '0275 A3b: nemotron catalog default reads %, expected 1', v_r.gate_catalog_default;
  END IF;

  -- A4: every row carries its window and its age, and the window is the
  -- ledger's own.
  IF EXISTS (SELECT 1 FROM public.ottoq_intelligence_status()
              WHERE window_from IS NULL OR window_to IS NULL OR window_to <= window_from
                 OR computed_at IS NULL OR snapshot_age_hours IS NULL) THEN
    RAISE EXCEPTION '0275 A4: a row came back without a usable window or age';
  END IF;
  -- one window, shared by every row. It comes from the same ROLLUP pass as the
  -- counts, so consistency is structural -- and re-reading min(created_at) off
  -- ottoq_decisions to "check" it would buy another 11-second scan to confirm
  -- something the query plan already guarantees.
  IF (SELECT count(DISTINCT window_from) FROM public.ottoq_intelligence_status()) <> 1
     OR (SELECT count(DISTINCT window_to) FROM public.ottoq_intelligence_status()) <> 1 THEN
    RAISE EXCEPTION '0275 A4: the rows do not share one window';
  END IF;

  -- A6a: the three facts 0208 turns on, asserted against the rows the refresh
  -- wrote rather than against four more scans. cuOpt is stated as 27/27
  -- because this is the assertion that caught 0208's LIMIT 12.
  SELECT * INTO v_r FROM public.ottoq_intelligence_snapshot WHERE source='cuopt';
  IF v_r.decisions <> 27 OR v_r.enacted <> 27 THEN
    RAISE EXCEPTION '0275 A6a: cuOpt reads %/%; 0208 (corrected) measured 27/27',
                    v_r.decisions, v_r.enacted;
  END IF;
  SELECT * INTO v_r FROM public.ottoq_intelligence_snapshot WHERE source='ottoq_service_priority';
  IF v_r.decisions < 400 OR v_r.enacted <> 0 THEN
    RAISE EXCEPTION '0275 A6a: ottoq_service_priority reads %/%, expected hundreds and ZERO enacted',
                    v_r.decisions, v_r.enacted;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_snapshot WHERE decisions > 0;
  IF v_n <> 16 THEN
    RAISE EXCEPTION '0275 A6a: % sources have decided, the seed was written against 16 -- '
                    'read the new one', v_n;
  END IF;

  -- A6: COMPLETENESS, data-driven rather than intended. The refresh wrote a
  -- row for every label it found; none of them may be unregistered.
  SELECT count(*) INTO v_unreg FROM public.ottoq_intelligence_snapshot WHERE NOT registered;
  IF v_unreg <> 0 THEN
    SELECT string_agg(source, ', ') INTO v_src
      FROM public.ottoq_intelligence_snapshot WHERE NOT registered;
    RAISE EXCEPTION '0275 A6: % labels decide in this engine and are not in the census: %',
                    v_unreg, v_src;
  END IF;

  -- A7: and the status path must not touch the expensive table. An assertion
  -- about elapsed milliseconds would pass on a warm cache and prove nothing;
  -- this one cannot.
  IF (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_intelligence_status')
     ILIKE '%ottoq_decisions%' THEN
    RAISE EXCEPTION '0275 A7: ottoq_intelligence_status reads ottoq_decisions -- '
                    'that is the 11-second, 1.5 GB scan this shape exists to avoid';
  END IF;
  IF (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_intelligence_refresh')
     NOT ILIKE '%ottoq_decisions%' THEN
    RAISE EXCEPTION '0275 A7: the refresh does not read ottoq_decisions -- '
                    'then the snapshot is coming from somewhere it should not';
  END IF;

  -- A5: nothing on the certified path moved.
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_decide_tick')
     IS DISTINCT FROM 'fd0bf428abeda40801467fd428a090f1' THEN
    RAISE EXCEPTION '0275 A5: ottoq_decide_tick changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair')
     IS DISTINCT FROM '8a35b8c874fed154cc216140faec0274' THEN
    RAISE EXCEPTION '0275 A5: ottoq_determinism_pair changed -- forces_recert is not FALSE';
  END IF;

  RAISE NOTICE '0275: A1-A7 passed. % distinct states across 18 sources, 0 unregistered.', v_states;
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0275_no_single_place_says_which_intelligence_sources_are_actually_on', false,
  'Adds ottoq_intelligence_sources (registry, 18 rows), ottoq_intelligence_snapshot, '
  'ottoq_intelligence_refresh() (one ROLLUP pass over ottoq_decisions, writing a row for every '
  'label it FINDS so nothing can go uncounted) and ottoq_intelligence_status() (STABLE, reads '
  'the snapshot only -- A7 asserts it never touches ottoq_decisions, because the live aggregate '
  'measured 11,187 ms and 1.5 GB). Writes nothing an engine reads, has no engine caller, '
  'touches no dial. A5 asserts ottoq_decide_tick (fd0bf428abeda40801467fd428a090f1) and '
  'ottoq_determinism_pair (8a35b8c874fed154cc216140faec0274) are byte-identical afterwards.',
  now());

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- (not yet applied)
-- ---------------------------------------------------------------------------
