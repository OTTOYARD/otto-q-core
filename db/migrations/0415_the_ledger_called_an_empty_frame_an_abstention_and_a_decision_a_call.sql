-- migration-version: 20260922053000
-- migration-name:    the_ledger_called_an_empty_frame_an_abstention_and_a_decision_a_call
--
-- 0415  **`ottoq_intelligence_ledger` is the view CLAUDE.md instructs every reader to use for the
--       rule-6 answer, and it conflates three pairs of states that are not alike. Tonight it made me
--       publish two wrong conclusions about the solver layer before I caught them, which is the
--       strongest possible argument for fixing the instrument rather than the sentences.**
--
--       `forces_recert` **FALSE** — this changes a reporting view and an outcome classifier that
--       nothing in the decide path reads. §5 asserts that.
--
-- ══ §1 THE THREE CONFLATIONS, AND WHAT EACH ONE COST ══════════════════════════
--
-- **(a) `calls` counted rows, not calls.** `count(*)` over the whole ledger, including rows written by
-- `ottoq_capture_decision_model_call` for local decisions that never left the database. Measured:
-- `cpsat_service` 3,638 rows against **487** endpoint-carrying calls (86.6% not calls),
-- `nvidia_nemotron` 4,248 rows against **0**. Only `nvidia_cuopt` was clean. `0301` fixed the WRITE
-- side by stamping `endpoint`; the read side was never fixed, so the defect survived its own fix.
--
-- **(b) Latency averaged two different physical quantities.** `cpsat_service` reported **251 ms**
-- across all rows and **1,847 ms** across its real calls — a 7.4x understatement, because 3,151
-- sub-25 ms in-database decision rows were averaged in with network round trips. The two are not
-- comparable and must not share a column.
--
-- **(c) `solved_but_zero_proposals` meant both "I declined everything you offered" and "you offered me
-- nothing."** This is the one that matters most. Of CP-SAT's 444 calls since the 2026-09-21 07:41
-- infrastructure fix, **328 (74%) carry `rows: 0`** — an EMPTY CANDIDATE SET. CP-SAT was asked to
-- assign nothing and correctly returned nothing, in 21 ms. Those are not abstentions. Counting them as
-- such is what produced the sentence "the CP-SAT service answers 20 of 487 calls — 4.1%", which is
-- arithmetically true and describes a solver that does not exist: **on frames that actually contain
-- candidates its usable-answer rate is ~20%, comparable to cuOpt's 19.8% per entity.**
--
-- Same defect family as `0322` §9 (`superseded` meaning self-refresh, not defeat) and `0277`
-- ("required of none" meaning undeclared, not unrequired): **a status word that spans two states makes
-- every ratio built on it wrong, and the error is invisible because the arithmetic is right.**
--
-- ══ §2 AND THE CLASSIFIER SILENTLY GAVE UP ON 3,538 ROWS ══════════════════════
--
-- `ottoq_model_call_outcome_class` knows eleven outcome strings and returns `'unclassified'` for
-- anything else. Three live outcomes were never added: **`solved_but_zero_proposals` (420),
-- `deferred_site_power_cap` (3,074) and `errored` (44)** — together exactly the 3,538 rows the view
-- reported as `unclassified` for `cpsat_service`. The five-class invariant `0341` added was satisfied
-- the whole time, because `unclassified` absorbed the shortfall and still summed. **An invariant that a
-- catch-all bucket can satisfy is not an invariant.** The counts are now asserted to sum with
-- `unclassified = 0`, so a new outcome string fails the migration's own check instead of vanishing.
--
-- ══ §3 THE REGIME SPLIT, WHICH IS WHY AGGREGATES LIED ═════════════════════════
--
-- Not fixed here, but it is the reason (a)-(c) were able to mislead, and it belongs on the record.
-- CP-SAT's lifetime aggregate spans **four resolved outages**, each visible in the fallback reasons
-- with a first and last timestamp:
--
--     "CP-SAT service is not configured"                1,502   09-19 17:12 -> 09-20 05:16
--     "THE RUNNING IMAGE PREDATES CP-SAT" (stale image)   835   09-20 19:46 -> 09-21 02:31
--     "Signal timed out."                                 206   09-20 19:32 -> 09-21 07:41
--     "invalid proposer envelope"                         191   09-20 15:46 -> 09-20 19:45
--     "500 Internal Server Error"                           1   09-21 22:23
--
-- **86% of the 2,735 fallbacks were configuration or deployment failures, not solver failures**, and
-- every one stopped when it was fixed — the last coinciding with `0398` giving the box an Elastic IP
-- at 07:38 and verifying `/health` lists `cp_sat_forward_lex`. So any statistic averaged over CP-SAT's
-- lifetime describes a service that was unreachable for most of it. The view now carries
-- `first_call`/`last_call` per provider as it did, and the standing queries below are written to take
-- a cutover, because **an aggregate over a period containing a fixed outage is a claim about nothing.**
--
-- ══ §4 WHAT THIS CHANGES FOR READERS, INCLUDING ONE DELIBERATE BREAK ══════════
--
-- Every existing column keeps its name. Two change MEANING, on purpose, because their names were
-- already promises the values did not keep:
--
--   * `calls` now counts `endpoint IS NOT NULL` — an external call. Was: every ledger row.
--   * `avg_latency_ms` / `max_latency_ms` / `calls_over_one_tick` now cover external calls only.
--
-- **`nvidia_nemotron` therefore reports `calls = 0` and NULL call latency**, because not one of its
-- rows records an endpoint. That is the honest answer and it is a visible change for anything reading
-- the agent's latency from this view — so the agent's number moves to columns that say what it is:
-- `captured_decisions`, `avg_decision_latency_ms`, `decisions_over_one_tick`. **G62 is unaffected and
-- better stated:** 22,593 ms mean decision latency over 4,246 decisions with 1,023 over one tick is
-- now labelled DECISION latency, which is what it always measured and the right measure for an
-- advisory agent on a 30-second beat.
--
-- New columns: `ledger_rows`, `captured_decisions`, `no_candidate_calls`, `declined_all_calls`,
-- `avg_decision_latency_ms`, `max_decision_latency_ms`, `decisions_over_one_tick`.
--
-- ══ §5 WHAT IS NOT DONE, AND WHY I DID NOT DO IT TONIGHT ══════════════════════
--
-- **The empty-frame call should not be made at all.** 328 of 444 CP-SAT round trips asked a solver to
-- assign an empty set. The right fix is a candidate-count check before the fetch in
-- `ottoq-cpsat-propose`, plus emitting `no_candidates` as its own outcome string rather than
-- overloading `solved_but_zero_proposals`. **No database function invokes that edge function** — the
-- chain is edge-to-edge from `ottoq-orchestrator-agent` — so it cannot be fixed from SQL, and I am not
-- redeploying the one currently-working external solver path on an untested change overnight. The view
-- below derives the split from `detail->>'rows'` instead, so the measurement is correct NOW and the
-- edge change becomes a pure efficiency win (328 fewer round trips) rather than a correctness fix.
--
-- `forces_recert` FALSE: `ottoq_intelligence_ledger` is a reporting view, and
-- `ottoq_model_call_outcome_class` is read only by it and by `0340`'s capture triggers' reporting.
-- V5 asserts no decide-path function reads either, so no atom any canon digested can move.
--
-- ══ §6 APPLIED, AND WHAT THE VIEW READS NOW ═══════════════════════════════════
--
-- Applied statement-wise via `execute_sql` (`apply_migration` contends with the recert harness, which
-- runs `statement_timeout = 0` and holds locks for minutes — see `0414` §5). Every preflight and
-- verify above executed and passed. Measured immediately after:
--
--   provider          calls  rows   captured  answered abstain err  no_cand  decl_all  call_ms  dec_ms
--   ---------------   -----  -----  --------  -------- ------- ---  -------  --------  -------  ------
--   nvidia_nemotron       0  4,248     4,248     4,246       2    0        0         0     NULL  22,596
--   cpsat_service       487  3,638     3,151        97   3,494   44      328        92    1,847       4
--   nvidia_cuopt      1,159  1,159         0     1,141      18    0        0         0    2,719    NULL
--
-- **`unclassified` is 0 on all three, where `cpsat_service` alone had 3,538.** Classes sum to
-- `ledger_rows` and `calls + captured_decisions = ledger_rows` on every row, both asserted.
--
-- **And CP-SAT's 487 calls now decompose exactly:** 328 empty frames + 92 declined-all + 20 answered
-- + 44 errored + 3 refused. So on the **112 calls that actually carried candidates, 20 produced a
-- usable proposal — 17.9%**, against the 4.1% the old view implied. That is the number to quote, and
-- it is in the same band as cuOpt's 19.8% per entity rather than five times worse.
--
-- **The agent's row is the clearest it has ever been:** zero calls, 4,248 captured decisions, 22,596 ms
-- mean DECISION latency, **1,024 decisions over one tick**, and `agent_calls_with_no_l1_rules` 4,248
-- of 4,248. G62 and the L1 gap are now both stated in columns that mean what they say.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n int;
BEGIN
  -- P1. The three unclassified outcomes are exactly the shortfall this migration claims.
  SELECT count(*) INTO v_n FROM public.ottoq_model_call_ledger
   WHERE public.ottoq_model_call_outcome_class(outcome) = 'unclassified';
  IF v_n = 0 THEN
    RAISE EXCEPTION '0415 P1: nothing is unclassified, so the classifier was already extended -- '
                    're-derive before widening it again';
  END IF;
  RAISE NOTICE '0415 preflight: % ledger rows currently classify as unclassified', v_n;

  -- P2. The empty-frame population exists and is a `rows` = 0 population, not an abstain population.
  SELECT count(*) INTO v_n FROM public.ottoq_model_call_ledger
   WHERE outcome = 'solved_but_zero_proposals'
     AND COALESCE((detail->>'rows')::int, -1) = 0;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0415 P2: no solved_but_zero_proposals row carries rows=0, so the '
                    'no_candidate/declined_all split has nothing to separate';
  END IF;
  RAISE NOTICE '0415 preflight: % empty-frame calls to separate from real abstentions', v_n;
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (1) THE CLASSIFIER LEARNS THE THREE OUTCOMES IT WAS SILENTLY DROPPING.
--     It takes only the outcome STRING, so it cannot see `rows` -- the
--     no-candidate split therefore lives in the view, not here. Keeping that
--     boundary explicit matters: a classifier that needed the detail payload
--     would be a different function with a different contract.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_model_call_outcome_class(p_outcome text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE lower(COALESCE(p_outcome,''))
    --: the cuOpt-side vocabulary, set by 0340's own classifier
    WHEN 'answered'          THEN 'answered'
    WHEN 'abstained'         THEN 'abstained'
    WHEN 'fallback'          THEN 'fallback'
    WHEN 'refused'           THEN 'refused'
    WHEN 'error'             THEN 'error'
    --: the ottoq_decisions vocabulary, passed through verbatim on purpose
    WHEN 'enacted'           THEN 'answered'
    WHEN 'superseded'        THEN 'refused'
    WHEN 'expired'           THEN 'refused'
    WHEN 'noop_no_candidate' THEN 'abstained'
    WHEN 'shielded'          THEN 'refused'
    WHEN 'overridden'        THEN 'refused'
    --: 0415 -- three live outcomes the classifier never knew, which together were
    --: exactly the 3,538 rows the view reported as `unclassified` for cpsat_service.
    --: `solved_but_zero_proposals` is 'abstained' HERE because the string alone cannot
    --: distinguish "declined everything" from "offered nothing"; the view splits it on
    --: detail->>'rows'. See db/migrations/0415 §1(c).
    WHEN 'solved_but_zero_proposals' THEN 'abstained'
    WHEN 'deferred_site_power_cap'   THEN 'abstained'
    WHEN 'errored'                   THEN 'error'
    ELSE 'unclassified'
  END;
$fn$;

COMMENT ON FUNCTION public.ottoq_model_call_outcome_class(text) IS
  '0415: maps a model-call outcome string to one of five classes. Extended with '
  'solved_but_zero_proposals, deferred_site_power_cap and errored, which were silently falling into '
  '''unclassified'' -- 3,538 rows, and the five-class sum invariant still passed because the '
  'catch-all absorbed them. An invariant a catch-all can satisfy is not an invariant, so '
  'ottoq_intelligence_ledger now asserts unclassified = 0. NOTE the deliberate limit: this function '
  'sees only the outcome STRING, so solved_but_zero_proposals maps to ''abstained'' here and the '
  'empty-frame split (74% of CP-SAT calls) is derived in the view from detail->>''rows''.';

-- ─────────────────────────────────────────────────────────────────────────────
-- (2) THE VIEW. Every old column keeps its name; `calls` and the latency
--     columns keep their PROMISE instead of their old value (§4).
-- ─────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE VIEW can only APPEND columns, never reorder or rename them, so the original
-- twenty-one columns stay in their original order and the seven new ones go at the end. `calls` and
-- the latency columns keep their position and change only their VALUE (§4).
CREATE OR REPLACE VIEW public.ottoq_intelligence_ledger AS
  SELECT
    provider,
    role,

    -- A CALL IS A ROW THAT LEFT THE DATABASE. `endpoint IS NOT NULL` is the predicate 0301
    -- established for exactly this, and the read side never used it until 0415.
    count(*) FILTER (WHERE endpoint IS NOT NULL)                       AS calls,

    count(*) FILTER (WHERE http_status >= 200 AND http_status <= 299)   AS provider_status_2xx,
    count(*) FILTER (WHERE http_status IS NOT NULL
                       AND (http_status < 200 OR http_status > 299))    AS provider_status_other,
    count(*) FILTER (WHERE http_status IS NULL)                         AS provider_status_unknown,

    count(*) FILTER (WHERE public.ottoq_model_call_outcome_class(outcome) = 'answered')     AS answered,
    count(*) FILTER (WHERE public.ottoq_model_call_outcome_class(outcome) = 'abstained')    AS abstained,
    count(*) FILTER (WHERE public.ottoq_model_call_outcome_class(outcome) = 'fallback')     AS fell_back,
    count(*) FILTER (WHERE public.ottoq_model_call_outcome_class(outcome) = 'refused')      AS refused,
    count(*) FILTER (WHERE public.ottoq_model_call_outcome_class(outcome) = 'error')        AS errored,
    count(*) FILTER (WHERE public.ottoq_model_call_outcome_class(outcome) = 'unclassified') AS unclassified,

    jsonb_object_agg(outcome, n ORDER BY outcome)                       AS outcomes,
    COALESCE(sum(proposals_out), 0::bigint)                             AS proposals,
    count(*) FILTER (WHERE COALESCE((detail->>'l1_rules_evaluated')::int, 0) = 0
                       AND role = 'agent')                              AS agent_calls_with_no_l1_rules,

    -- NETWORK latency, over calls that actually crossed the network.
    round(avg(latency_ms) FILTER (WHERE endpoint IS NOT NULL))          AS avg_latency_ms,
    max(latency_ms)       FILTER (WHERE endpoint IS NOT NULL)           AS max_latency_ms,
    count(*) FILTER (WHERE endpoint IS NOT NULL AND latency_ms > 30000) AS calls_over_one_tick,

    min(called_at)                                                      AS first_call,
    max(called_at)                                                      AS last_call,
    count(*) FILTER (WHERE source_kind = 'backfill')                    AS reconstructed,

    -- ══ 0415 ADDITIONS, appended because a view cannot reorder ══
    count(*)                                                            AS ledger_rows,
    count(*) FILTER (WHERE endpoint IS NULL)                            AS captured_decisions,

    -- THE SPLIT THAT STOPS "NOTHING TO DO" READING AS "DECLINED EVERYTHING".
    count(*) FILTER (WHERE outcome = 'solved_but_zero_proposals'
                       AND COALESCE((detail->>'rows')::int, -1) = 0)    AS no_candidate_calls,
    count(*) FILTER (WHERE outcome = 'solved_but_zero_proposals'
                       AND COALESCE((detail->>'rows')::int, -1) > 0)    AS declined_all_calls,

    -- DECISION latency, over rows captured from ottoq_decisions. This is G62's measure, now labelled
    -- as what it is rather than borrowing the call-latency column.
    round(avg(latency_ms) FILTER (WHERE endpoint IS NULL))              AS avg_decision_latency_ms,
    max(latency_ms)       FILTER (WHERE endpoint IS NULL)               AS max_decision_latency_ms,
    count(*) FILTER (WHERE endpoint IS NULL AND latency_ms > 30000)     AS decisions_over_one_tick
  FROM (
    SELECT l.*, count(*) OVER (PARTITION BY l.provider, l.role, l.outcome) AS n
      FROM public.ottoq_model_call_ledger l
  ) z
  GROUP BY provider, role;

COMMENT ON VIEW public.ottoq_intelligence_ledger IS
  '0415: the rule-6 answer per provider. `calls` counts rows that LEFT THE DATABASE '
  '(endpoint IS NOT NULL); `ledger_rows` is every row and `captured_decisions` the in-database '
  'remainder -- before 0415 `calls` was count(*), so cpsat_service read 3,638 when it had made 487 '
  'calls and nvidia_nemotron read 4,248 when it had made none. avg/max_latency_ms and '
  'calls_over_one_tick cover external calls only (mixing them understated CP-SAT 7.4x); the agent''s '
  'number is avg_decision_latency_ms / decisions_over_one_tick. no_candidate_calls separates "you '
  'offered me nothing" (74% of CP-SAT calls) from declined_all_calls, because '
  'solved_but_zero_proposals meant both and that made every abstention ratio wrong. '
  'ALWAYS TAKE A TIME WINDOW: CP-SAT''s lifetime spans four resolved outages (0415 §3), so a '
  'lifetime aggregate describes a service that was unreachable for most of it.';

-- ─────────────────────────────────────────────────────────────────────────────
-- LINEAGE
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0415_the_ledger_called_an_empty_frame_an_abstention_and_a_decision_a_call', false,
  'Reporting-only. Fixes ottoq_intelligence_ledger (calls counted ledger rows including in-database '
  'decisions; latency averaged network round trips with sub-25ms local decisions; '
  'solved_but_zero_proposals conflated an empty candidate set with declining everything) and extends '
  'ottoq_model_call_outcome_class with three outcomes that were falling into unclassified. No decide-'
  'path function reads either object -- asserted in V5 -- so no decision, event, booking or dial '
  'value changes and no canon column digested anything different.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  r        record;
  v_n      int;
  v_calls  bigint;
  v_rows   bigint;
  v_readers text;
BEGIN
  -- V1. NOTHING IS UNCLASSIFIED ANY MORE, and the five classes sum to LEDGER ROWS -- not to `calls`,
  --     which is now a strict subset. 0341's invariant was asserted against the wrong total, which is
  --     how a catch-all bucket kept satisfying it.
  FOR r IN SELECT * FROM public.ottoq_intelligence_ledger LOOP
    IF r.unclassified <> 0 THEN
      RAISE EXCEPTION '0415 V1: provider % still has % unclassified rows; add the outcome string to '
                      'ottoq_model_call_outcome_class rather than letting it vanish',
                      r.provider, r.unclassified;
    END IF;
    IF r.answered + r.abstained + r.fell_back + r.refused + r.errored <> r.ledger_rows THEN
      RAISE EXCEPTION '0415 V1: provider % classes sum to % but holds % ledger rows',
                      r.provider,
                      r.answered + r.abstained + r.fell_back + r.refused + r.errored,
                      r.ledger_rows;
    END IF;
    -- V2. calls is a SUBSET of ledger_rows and complements captured_decisions exactly.
    IF r.calls + r.captured_decisions <> r.ledger_rows THEN
      RAISE EXCEPTION '0415 V2: provider %: calls % + captured_decisions % <> ledger_rows %',
                      r.provider, r.calls, r.captured_decisions, r.ledger_rows;
    END IF;
  END LOOP;

  -- V3. THE HEADLINE NUMBERS ARE NOW THE HONEST ONES. cpsat_service must read 487 calls out of 3,638
  --     rows, and nvidia_nemotron must read 0 calls -- the two figures the old view got wrong.
  SELECT calls, ledger_rows INTO v_calls, v_rows
    FROM public.ottoq_intelligence_ledger WHERE provider='cpsat_service';
  IF v_calls >= v_rows THEN
    RAISE EXCEPTION '0415 V3: cpsat_service reports % calls of % rows -- the endpoint predicate is '
                    'not separating captured decisions from calls', v_calls, v_rows;
  END IF;
  SELECT calls INTO v_calls FROM public.ottoq_intelligence_ledger WHERE provider='nvidia_nemotron';
  IF v_calls <> 0 THEN
    RAISE EXCEPTION '0415 V3: nvidia_nemotron reports % calls; no nemotron row carries an endpoint, '
                    'so this must be 0 and its latency must live in the decision columns', v_calls;
  END IF;

  -- V4. THE EMPTY-FRAME SPLIT IS REAL AND DOMINANT. If no_candidate_calls were zero the split would
  --     be decorative; it is 74% of CP-SAT's calls and that is the point of the migration.
  SELECT no_candidate_calls INTO v_n
    FROM public.ottoq_intelligence_ledger WHERE provider='cpsat_service';
  IF COALESCE(v_n,0) = 0 THEN
    RAISE EXCEPTION '0415 V4: cpsat_service reports 0 no_candidate_calls; the rows=0 population was '
                    'measured at 328 and must be separated from genuine abstentions';
  END IF;

  -- V5. THE forces_recert=FALSE PREMISE: no function outside reporting reads either object. A
  --     decide-path reader would mean this migration changes engine behaviour.
  --     ottoq_intelligence_stack is the ONE known reader and it is a status/reporting surface: it
  --     exposes {calls, proposals, last_call} per provider for the cockpit. It is named explicitly
  --     rather than pattern-excluded, so a NEW reader appearing trips this check and gets inspected.
  SELECT count(*), string_agg(n.nspname||'.'||p.proname, ', ') INTO v_n, v_readers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog','information_schema')
     AND p.proname NOT IN ('ottoq_model_call_outcome_class', 'ottoq_intelligence_stack')
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),
                        '--[^' || chr(10) || ']*','','g')
         LIKE '%ottoq_intelligence_ledger%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0415 V5: % unexpected reader(s) of ottoq_intelligence_ledger: %. If any is on '
                    'the decide path, forces_recert must be TRUE -- inspect before applying',
                    v_n, v_readers;
  END IF;

  RAISE NOTICE '0415 verify: no unclassified rows, classes sum to ledger_rows, calls is a strict '
               'subset, nemotron reports 0 calls, the empty-frame split is populated, and nothing '
               'outside reporting reads the view';
END $post$;

COMMIT;
