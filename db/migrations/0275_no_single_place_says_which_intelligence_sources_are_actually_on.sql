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
-- appended to 0208 and the corrected fact is sharper than the error: cuOpt has
-- decided 27 times and all 27 were enacted, so the engine does not ignore it;
-- a dial says it may not speak.
--
-- Both halves of that are the same defect. "Which intelligence sources are on,
-- when did each last decide, and was it followed" has no answer you can
-- SELECT, so answering it means writing a query, and a query written by hand
-- can end in LIMIT 12.
--
-- This migration gives it an answer, and gives that answer a completeness
-- guard (A6) so the next omission fails an apply instead of reaching a
-- document. No dial is touched.
--
-- ---------------------------------------------------------------------------
-- THE FOUR STATES, MADE COMPUTABLE
--
-- DECLARED / WIRED / INVOKED / FOLLOWED, whose whole point is that "it exists"
-- is not "it runs". Derived in that order:
--
--   FOLLOWED  at least one decision it proposed was ENACTED
--   INVOKED   it decided, and nothing it decided was enacted
--   WIRED     plumbing exists in this database -- a gate parameter or its own
--             ledger -- and it has decided nothing in the window
--   DECLARED  registered, and neither of the above
--
-- EVERY NUMBER CARRIES ITS WINDOW. ottoq_decisions holds roughly fifteen days,
-- not the engine's life, and 0208 had to correct a note of mine that read 262
-- as a lifetime total. So window_from and window_to are COLUMNS of the result,
-- read from the ledger itself.
--
-- THE REGISTRY IS COMPLETE OR IT IS NOTHING. It holds every l2_engine label
-- that has ever appeared in ottoq_decisions -- all sixteen, including the
-- baselines, the fallback and my own agent probe -- plus the two sources with
-- no database presence at all. A6 asserts that completeness on every apply.
-- A census that lists only the interesting sources is how 0208 lost cuOpt.
--
-- TWO SOURCES HAVE NO DATABASE PRESENCE, measured rather than assumed: no
-- function, no policy key, no decision row for either CP-SAT or Anthropic.
-- Their code is real and lives in the repo. Leaving them out would make the
-- status function read healthier than the system is, so they are in it at
-- DECLARED with the note saying where the code actually is.
--
-- AND ONE THING MEASURED WHILE BUILDING IT, WHICH CHANGES HOW A GATE READS.
-- ottoq_policy_get DOES NOT READ ottoq_policy_param_catalog -- its body never
-- mentions the table, and ottoq_policy_get(NULL, k, 7) returns 7 for a key
-- whose catalog default is 1. So default_value is DOCUMENTATION, not
-- behaviour: a dial's effective default is whatever each call site hardcodes,
-- and if the two disagree nothing notices.
--
-- This function refuses to collapse them. gate_override is the stored value
-- (NULL when unset), gate_catalog_default is the catalog's, and gate_enabled
-- is NULL -- not false -- when nothing is stored, because from here the
-- effective value is genuinely unknown. A3b asserts that distinction on a real
-- key: cuOpt reads override 0 / enabled false, Nemotron reads override NULL /
-- enabled NULL with a catalog default of 1. Reporting both as "off" would be
-- the same class of lie this file exists to stop.
--
-- forces_recert = FALSE: one table, one STABLE read-only function, no engine
-- caller, nothing on the decide path. A5 asserts ottoq_decide_tick and
-- ottoq_determinism_pair are byte-identical afterwards.
-- ---------------------------------------------------------------------------

DO $pre$
DECLARE v_gate text; v_n bigint; v_e bigint; v_labels int;
BEGIN
  IF to_regclass('public.ottoq_intelligence_sources') IS NOT NULL THEN
    RAISE EXCEPTION '0275 P1: the registry already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public' AND p.proname='ottoq_intelligence_status') THEN
    RAISE EXCEPTION '0275 P1: ottoq_intelligence_status already exists';
  END IF;

  -- P2: the seed describes a measured world. If it has moved, refuse rather
  -- than ship a stale census. These three are the ones 0208 turns on, and the
  -- cuOpt pair is stated as 27/27 because this assertion is what caught the
  -- LIMIT 12 error in the first place.
  SELECT param_value INTO v_gate FROM public.ottoq_policy_params
   WHERE scope_type='global' AND param_key='cuopt_propose_enabled';
  IF COALESCE(v_gate,'(unset)') <> '0' THEN
    RAISE EXCEPTION '0275 P2: cuopt_propose_enabled is now % -- expected 0', COALESCE(v_gate,'(unset)');
  END IF;
  SELECT count(*), count(*) FILTER (WHERE outcome_status='enacted') INTO v_n, v_e
    FROM public.ottoq_decisions WHERE l2_engine='cuopt';
  IF v_n <> 27 OR v_e <> 27 THEN
    RAISE EXCEPTION '0275 P2: cuOpt reads %/% decisions/enacted; 0208 (corrected) measured 27/27', v_n, v_e;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_decisions
              WHERE l2_engine='ottoq_service_priority' AND outcome_status='enacted') THEN
    RAISE EXCEPTION '0275 P2: ottoq_service_priority now has an enacted decision -- 0208 measured none';
  END IF;

  -- P3: and the label set this registry claims to cover is the one that
  -- exists. Sixteen at the time of writing; a seventeenth means the seed is
  -- already short and A6 would fail after the table was created.
  SELECT count(DISTINCT l2_engine) INTO v_labels
    FROM public.ottoq_decisions WHERE l2_engine IS NOT NULL;
  IF v_labels <> 16 THEN
    RAISE EXCEPTION '0275 P3: % distinct l2_engine labels exist, the seed covers 16 -- '
                    'read the new one and add it before applying', v_labels;
  END IF;
  RAISE NOTICE '0275 pre: cuOpt gate 0, cuOpt 27/27, service_priority 0 enacted, % labels', v_labels;
END $pre$;

CREATE TABLE public.ottoq_intelligence_sources (
  source           text PRIMARY KEY,
  kind             text NOT NULL CHECK (kind IN ('deterministic','solver_external','solver_local',
                                                 'llm','heuristic','baseline','fallback','probe')),
  gate_param_key   text,          -- NULL when the source has no dial in this database
  l2_engine_label  text UNIQUE,   -- how it stamps ottoq_decisions.l2_engine; NULL if it never does
  own_ledger       text,          -- its own invocation ledger, NULL if it has none
  code_lives_in    text NOT NULL, -- where the implementation actually is
  note             text,
  registered_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_intelligence_sources IS
  '0275: the COMPLETE census of everything that has ever decided in this '
  'engine -- every l2_engine label without exception, plus the sources whose '
  'code lives outside the database. Completeness is asserted, not intended: a '
  'registry that lists only the interesting sources is how db/checks/0208 lost '
  'cuOpt behind a LIMIT 12.';

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

CREATE OR REPLACE FUNCTION public.ottoq_intelligence_status()
RETURNS TABLE(source text, kind text, state text,
              gate_param_key text, gate_override numeric, gate_catalog_default numeric,
              gate_enabled boolean,
              decisions bigint, enacted bigint,
              last_decision_at timestamptz, hours_silent numeric,
              own_ledger text, own_ledger_rows bigint, own_ledger_answered bigint,
              code_lives_in text, note text,
              window_from timestamptz, window_to timestamptz)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'extensions'
AS $fn$
  WITH win AS (
    SELECT min(d.created_at) AS lo, max(d.created_at) AS hi FROM public.ottoq_decisions d
  ),
  dec AS (
    SELECT d.l2_engine,
           count(*)                                           AS n,
           count(*) FILTER (WHERE d.outcome_status='enacted')  AS n_enacted,
           max(d.created_at)                                   AS last_at
      FROM public.ottoq_decisions d
     WHERE d.l2_engine IS NOT NULL
     GROUP BY d.l2_engine
  ),
  -- cuOpt is the only source with its own invocation ledger today. The join is
  -- written out by name rather than dispatched from the registry, because a
  -- status function that builds dynamic SQL from a table is a status function
  -- that can be made to run anything.
  cuopt AS (
    SELECT count(*) AS rows_all,
           count(*) FILTER (WHERE http_status IS NOT NULL) AS answered
      FROM public.cuopt_invocation_log
  )
  SELECT s.source,
         s.kind,
         CASE
           WHEN COALESCE(dc.n_enacted,0) > 0 THEN 'FOLLOWED'
           WHEN COALESCE(dc.n,0)         > 0 THEN 'INVOKED'
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
         COALESCE(dc.n, 0)         AS decisions,
         COALESCE(dc.n_enacted, 0) AS enacted,
         dc.last_at,
         CASE WHEN dc.last_at IS NULL THEN NULL
              ELSE round((EXTRACT(EPOCH FROM (w.hi - dc.last_at)) / 3600)::numeric, 1) END AS hours_silent,
         s.own_ledger,
         CASE WHEN s.own_ledger = 'cuopt_invocation_log' THEN c.rows_all END AS own_ledger_rows,
         CASE WHEN s.own_ledger = 'cuopt_invocation_log' THEN c.answered END AS own_ledger_answered,
         s.code_lives_in,
         s.note,
         w.lo, w.hi
    FROM public.ottoq_intelligence_sources s
    CROSS JOIN win w
    CROSS JOIN cuopt c
    LEFT JOIN dec dc ON dc.l2_engine = s.l2_engine_label
   ORDER BY (CASE
               WHEN COALESCE(dc.n_enacted,0) > 0 THEN 1
               WHEN COALESCE(dc.n,0)         > 0 THEN 2
               WHEN s.gate_param_key IS NOT NULL OR s.own_ledger IS NOT NULL THEN 3
               ELSE 4 END), COALESCE(dc.n_enacted,0) DESC, s.source;
$fn$;

COMMENT ON FUNCTION public.ottoq_intelligence_status() IS
  '0275: which sources are on, when each last decided, and whether anything it '
  'decided was followed. Every count carries its window (window_from / '
  'window_to) because ottoq_decisions is roughly fifteen days deep, not the '
  'engine''s whole life. hours_silent is measured against the window''s end, '
  'not wall-clock now, so the number does not drift while you read it. '
  'gate_override is the STORED value and gate_enabled is NULL, not false, when '
  'nothing is stored: ottoq_policy_get does not consult '
  'ottoq_policy_param_catalog, so from here the effective value of an unset '
  'dial is genuinely unknown -- it is whatever the call site hardcodes.';

REVOKE ALL ON FUNCTION public.ottoq_intelligence_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_intelligence_status() TO authenticated, service_role;
GRANT SELECT ON public.ottoq_intelligence_sources TO authenticated, service_role;

DO $post$
DECLARE v_n int; v_states int; v_missing int; v_labels int; v_r record;
BEGIN
  -- A1: eighteen sources, one status row each, nothing lost in the LEFT JOIN.
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_sources;
  IF v_n <> 18 THEN RAISE EXCEPTION '0275 A1: registry holds % rows, expected 18', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_intelligence_status();
  IF v_n <> 18 THEN RAISE EXCEPTION '0275 A1: status returned % rows for 18 sources', v_n; END IF;

  -- A2: THE LADDER MUST DISCRIMINATE. Everything on one rung measures nothing.
  SELECT count(DISTINCT state) INTO v_states FROM public.ottoq_intelligence_status();
  IF v_states < 3 THEN
    RAISE EXCEPTION '0275 A2: the ladder returned only % distinct states', v_states;
  END IF;

  -- A3: and it lands where the corrected 0208 measured, source by source, so
  -- a derivation that produces the right SHAPE for the wrong reasons fails.
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

  -- A3b: unset must not read as off. The assertion that distinguishes this
  -- design from a single collapsed gate column.
  SELECT * INTO v_r FROM public.ottoq_intelligence_status() WHERE source='nemotron';
  IF v_r.gate_override IS NOT NULL OR v_r.gate_enabled IS NOT NULL THEN
    RAISE EXCEPTION '0275 A3b: nemotron has no stored override, so gate_override and '
                    'gate_enabled must both be NULL; got % / %', v_r.gate_override, v_r.gate_enabled;
  END IF;
  IF v_r.gate_catalog_default IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION '0275 A3b: nemotron catalog default reads %, expected 1', v_r.gate_catalog_default;
  END IF;

  SELECT * INTO v_r FROM public.ottoq_intelligence_status() WHERE source='anthropic';
  IF v_r.state <> 'DECLARED' OR v_r.gate_param_key IS NOT NULL THEN
    RAISE EXCEPTION '0275 A3: anthropic reads state=% gate=%, expected DECLARED with no dial',
                    v_r.state, v_r.gate_param_key;
  END IF;

  -- A4: every row carries its window, and the window is the ledger's own.
  IF EXISTS (SELECT 1 FROM public.ottoq_intelligence_status()
              WHERE window_from IS NULL OR window_to IS NULL OR window_to <= window_from) THEN
    RAISE EXCEPTION '0275 A4: a row came back without a usable window';
  END IF;
  IF (SELECT DISTINCT window_from FROM public.ottoq_intelligence_status())
     IS DISTINCT FROM (SELECT min(created_at) FROM public.ottoq_decisions) THEN
    RAISE EXCEPTION '0275 A4: the reported window does not match the decision ledger';
  END IF;

  -- A6: COMPLETENESS. The guard that would have caught 0208's LIMIT 12. Every
  -- label that has ever decided must be registered. Non-vacuous by
  -- construction: the label set is counted first, so an empty ledger fails
  -- rather than passing silently.
  SELECT count(DISTINCT l2_engine) INTO v_labels
    FROM public.ottoq_decisions WHERE l2_engine IS NOT NULL;
  IF v_labels < 10 THEN
    RAISE EXCEPTION '0275 A6: only % distinct labels exist -- too few for this check to mean anything',
                    v_labels;
  END IF;
  SELECT count(*) INTO v_missing FROM (
    SELECT DISTINCT d.l2_engine FROM public.ottoq_decisions d WHERE d.l2_engine IS NOT NULL) x
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_intelligence_sources s
                      WHERE s.l2_engine_label = x.l2_engine);
  IF v_missing <> 0 THEN
    RAISE EXCEPTION '0275 A6: % l2_engine labels decide in this engine and are not in the census', v_missing;
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

  RAISE NOTICE '0275: A1-A6 passed. % distinct states across 18 sources, % labels all registered.',
               v_states, v_labels;
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0275_no_single_place_says_which_intelligence_sources_are_actually_on', false,
  'Adds ottoq_intelligence_sources (a COMPLETE registry: all 16 l2_engine labels plus cpsat and '
  'anthropic, which have no database presence) and ottoq_intelligence_status() (one STABLE '
  'read-only function deriving DECLARED/WIRED/INVOKED/FOLLOWED per source from ottoq_decisions '
  'and cuopt_invocation_log, carrying the ledger window as result columns, and reporting a '
  'dial''s stored override separately from its catalog default because ottoq_policy_get never '
  'reads the catalog). A6 asserts registry completeness against the live label set -- the guard '
  'for the LIMIT 12 error db/checks/0208 had to correct. Writes nothing an engine reads, has no '
  'engine caller, touches no dial. A5 asserts ottoq_decide_tick '
  '(fd0bf428abeda40801467fd428a090f1) and ottoq_determinism_pair '
  '(8a35b8c874fed154cc216140faec0274) are byte-identical afterwards.',
  now());

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- (not yet applied)
-- ---------------------------------------------------------------------------
