-- migration-version: PENDING
-- migration-name:    the_ledger_says_blocked_and_cannot_say_whether_anything_was_blocked_so_it_learns_to_say_both
--
-- 0430  **`ottoq_rule_evaluations.enforcement_taken='blocked'` is the shield's RECOMMENDATION, and at six of
--       ten probe points the caller discards it — so 5,721 of 7,626 `blocked` rows record a refusal that
--       never happened (G149, `db/checks/0337` §3, quantified in `0345`).** This does not change enforcement
--       anywhere. It makes the column readable, by deriving each probe point's posture from the callers'
--       own source and exposing it beside every evaluation.
--
--       **The rule this file follows is the one `0345` arrived at: fix the ledger, not the enforcement.**
--       `0428` promoted exactly one checkpoint, on its own evidence; the other five stay advisory and are
--       supposed to. What was wrong was that a reader could not tell which was which without reading
--       PL/pgSQL.
--
--       `forces_recert` **FALSE**: three new read-only objects, no engine path touched, no atom reads them.
--
-- ══ §1 WHY THIS IS DERIVED AND NOT A HAND-MAINTAINED TABLE ═══════════════════
--
-- A static list of "which probe points enforce" would be correct the day it was written and wrong the first
-- time somebody promoted one — which has now happened twice in a day (`0422` added a probe point, `0428`
-- promoted one). So `ottoq_shield_probe_posture()` re-derives from `pg_proc` on every call:
--
--   * **comment-stripped**, because `twin.ottoq_sim_advance_visit_atoms` matches `ottoq_shield_probe` on a
--     raw grep and **zero** times once comments are removed — it calls the wrapper. A census that does not
--     strip comments overcounts (`0345` §1);
--   * **whitespace-tolerant**, because the literal `COALESCE(v_blocks,0)>0` finds five of `ottoq_decide_tick`'s
--     six honouring branches and misses the sixth, which spells it with spaces around the `>`. That near-miss
--     has now happened **four times on this one column**. An assertion a formatting difference can flip is
--     not an assertion;
--   * **variable-name-tolerant**, because `0428` introduced `v_shield_blocks` beside the existing `v_blocks`.
--
-- Verified against the live catalog before this file was written: the derivation reproduces `0345` §1's
-- census exactly, **and already shows `charge_session_start` as honouring**, which it was not before `0428`.
-- The derivation tracks reality rather than restating a snapshot.
--
-- ══ §2 THE LIMIT, STATED IN THE INSTRUMENT ITSELF RATHER THAN DISCOVERED LATER ══
--
-- **A caller can pass the action context as a VARIABLE, and then no static derivation can map it.**
-- `public.ottoq_shield_and_log` does exactly that — `FROM ottoq_shield_probe(v_ac,'vehicle',v_eid,…)` — and
-- it *does* branch on `COALESCE(v_blocks,0) > 0`. `0345` §1 listed it under `stall_assignment` and
-- `redeployment` only because I had read the function; nothing in the source ties the call site to those
-- names.
--
-- **So the function returns those callers as their own rows with `action_context IS NULL` and
-- `posture='unresolvable_variable_context'`, rather than silently omitting them.** Today that changes no
-- answer — both contexts it serves are already honoured by `ottoq_decide_tick` — but a variable-context
-- caller could one day be the *only* caller of some context, and then a derivation that hid it would report
-- that context as unprobed. **This is `0326` §6(a)'s standing finding in a new place: a static caller search
-- can never find a rule's wiring, so the instrument must say where it is blind.**
--
-- ══ §3 WHAT THE VIEW SAYS, AND THE ONE WORD THAT MATTERS ═════════════════════
--
-- `public.ottoq_rule_evaluation_effect` adds two columns to every evaluation:
--
--     recommendation   -- = enforcement_taken. What the SHIELD said.
--     effect           -- what the ENGINE did with it:
--                      --   'refused'        blocked at a probe point whose caller branches
--                      --   'recorded_only'  blocked at a probe point whose caller discards it
--                      --   'unknown_posture' blocked at a probe point with no resolvable caller
--                      --   otherwise the recommendation itself (allowed / logged / …)
--
-- **`recorded_only` is the word this migration exists to make sayable.** Before it, the only honest
-- phrasing was a paragraph; now the count is a `WHERE` clause. Note it is deliberately NOT called
-- "ignored": the row is written, signed and kept, and at four of those six points the rule was broken
-- rather than the discard being wrong (`0345` §2). "Recorded and not acted on" is the same language
-- `space_conflict_ledger` already uses for its own contradicted claims, and that consistency is intentional.
--
-- ══ §4 WHAT THIS DELIBERATELY DOES NOT DO ════════════════════════════════════
--
--   1. **It promotes nothing.** Not one caller changes. `0345` §3's order stands: fix the input, measure the
--      rate to zero, promote one checkpoint at a time.
--   2. **It does not backfill or alter a single historical row.** The posture is computed at read time from
--      today's code, so a row evaluated before `0428` will read `refused` under today's posture even though
--      it was `recorded_only` when written. **That is a real limitation and §6 says how to read around it**
--      — it is the price of not editing a signed ledger, and the right price.
--   3. **It does not touch `enforcement_taken`.** Rewriting what the shield said, to make it agree with what
--      the engine did, would destroy the distinction this file exists to expose.
--
-- ══ §5 PRE-FLIGHT, CHANGE, VERIFICATION ═══════════════════════════════════════

\set ON_ERROR_STOP on
BEGIN;

-- ── P1: the defect is live -- blocked rows exist at discarding probe points ──
DO $$
DECLARE v_blocked int;
BEGIN
  SELECT count(*) INTO v_blocked FROM public.ottoq_rule_evaluations WHERE enforcement_taken='blocked';
  IF v_blocked = 0 THEN
    RAISE EXCEPTION '0430 P1: no blocked rows in the ledger -- re-derive db/checks/0337 and 0345 before '
                    'building an instrument for a population that does not exist.';
  END IF;
  RAISE NOTICE '0430 P1: % blocked rows to disambiguate', v_blocked;
END $$;

-- ── P2: the derivation must reproduce the census 0345 measured by hand.
-- If these three named facts do not come back, the regexes have drifted and the instrument would ship a
-- confident wrong answer -- which is worse than no instrument.
DO $$
DECLARE v_decide_sites int; v_decide_branches int; v_advance_stripped int;
BEGIN
  SELECT (SELECT count(*) FROM regexp_matches(s.src,'ottoq_shield_probe','g')),
         (SELECT count(*) FROM regexp_matches(s.src,'COALESCE\s*\(\s*v_\w*blocks\w*\s*,\s*0\s*\)\s*>\s*0','g'))
    INTO v_decide_sites, v_decide_branches
    FROM (SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
            FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='public' AND p.proname='ottoq_decide_tick') s;
  IF v_decide_sites <> v_decide_branches THEN
    RAISE EXCEPTION '0430 P2: ottoq_decide_tick has % probe sites but % honouring branches -- 0345 measured '
                    'six and six. If this is five, the whitespace-tolerant regex has regressed to the '
                    'literal form that missed the sixth site.', v_decide_sites, v_decide_branches;
  END IF;

  SELECT (SELECT count(*) FROM regexp_matches(
            regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g'),
            'ottoq_shield_probe','g'))
    INTO v_advance_stripped
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms';
  IF COALESCE(v_advance_stripped,0) <> 0 THEN
    RAISE EXCEPTION '0430 P2: twin.ottoq_sim_advance_visit_atoms shows % probe references after comment '
                    'stripping, expected 0 -- it calls the WRAPPER. If this is non-zero the comment '
                    'stripping is not working and the census overcounts.', v_advance_stripped;
  END IF;
  RAISE NOTICE '0430 P2: decide_tick % sites / % branches; advance_visit_atoms 0 after stripping',
               v_decide_sites, v_decide_branches;
END $$;

-- ── P3: nothing in flight (G141 -- a pair is invisible to ottoq_sim_runs) ──
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_n <> 0 THEN RAISE EXCEPTION '0430 P3: % run(s) running/paused -- apply between runs', v_n; END IF;
END $$;

-- ── (A) THE POSTURE, DERIVED FROM THE CALLERS' OWN SOURCE ON EVERY CALL ──
CREATE OR REPLACE FUNCTION public.ottoq_shield_probe_posture()
RETURNS TABLE (action_context text, posture text, callers text[],
               -- bigint, not int: these are count() results, and declaring int would lean on an
               -- assignment cast for no reason.
               honouring bigint, discarding bigint, captures_no_branch bigint)
LANGUAGE sql STABLE AS $body$
  WITH callers AS (
    SELECT n.nspname||'.'||p.proname AS fn,
           regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE p.prosrc ~ 'ottoq_shield_probe' AND p.proname <> 'ottoq_shield_probe'),
  classified AS (
    SELECT c.fn, c.src,
           (c.src ~ 'PERFORM\s+1?\s*\*?\s*(FROM\s+)?public\.ottoq_shield_probe') AS discards,
           -- whitespace-tolerant AND variable-name-tolerant: v_blocks, v_shield_blocks, ...
           (c.src ~ 'COALESCE\s*\(\s*v_\w*blocks\w*\s*,\s*0\s*\)\s*>\s*0')       AS branches,
           -- A caller has an unresolvable site when its probe-call count exceeds the count of sites whose
           -- context is a LITERAL. Counting is used rather than a pattern for "not a literal" because
           -- Postgres POSIX regex has no negative lookahead, and the naive form `\(\s*[a-z_]+[^'']` also
           -- matches every named-argument caller (`p_action_context := '…'`) -- flagging callers that are
           -- in fact perfectly resolvable.
           (SELECT count(*) FROM regexp_matches(c.src,'ottoq_shield_probe','g'))
             > (SELECT count(*) FROM regexp_matches(c.src,
                  'ottoq_shield_probe\s*\(\s*(?:p_action_context\s*:=\s*)?''[a-z_]+''','g')) AS variable_context
      FROM callers c),
  sites AS (
    SELECT cl.fn, cl.discards, cl.branches,
           (regexp_matches(cl.src,
              'ottoq_shield_probe\s*\(\s*(?:p_action_context\s*:=\s*)?''([a-z_]+)''','g'))[1] AS ac
      FROM classified cl),
  resolved AS (
    SELECT s.ac AS action_context,
           CASE WHEN bool_or(s.branches) AND bool_or(s.discards) THEN 'mixed'
                WHEN bool_or(s.branches)                          THEN 'enforced'
                ELSE 'advisory' END AS posture,
           array_agg(DISTINCT s.fn ORDER BY s.fn) AS callers,
           count(DISTINCT s.fn) FILTER (WHERE s.branches)                        AS honouring,
           count(DISTINCT s.fn) FILTER (WHERE s.discards)                        AS discarding,
           count(DISTINCT s.fn) FILTER (WHERE NOT s.branches AND NOT s.discards) AS captures_no_branch
      FROM sites s GROUP BY s.ac),
  unresolved AS (
    -- Section 2: a caller passing the context as a VARIABLE is reported, never omitted.
    SELECT NULL::text AS action_context,
           'unresolvable_variable_context'::text AS posture,
           array_agg(DISTINCT cl.fn ORDER BY cl.fn) AS callers,
           count(DISTINCT cl.fn) FILTER (WHERE cl.branches) AS honouring,
           count(DISTINCT cl.fn) FILTER (WHERE cl.discards) AS discarding,
           0::bigint AS captures_no_branch
      FROM classified cl
     WHERE cl.variable_context
    HAVING count(*) > 0)
    -- No "and has no literal site" guard: a caller with BOTH literal and variable sites still has a blind
    -- spot, and excluding it would hide exactly the case this row exists to surface.
  SELECT * FROM resolved
  UNION ALL
  SELECT * FROM unresolved
  ORDER BY 2, 1 NULLS LAST;
$body$;

COMMENT ON FUNCTION public.ottoq_shield_probe_posture() IS
  'G149/0430. Per action_context, whether the CALLER acts on the shield''s verdict. Derived from pg_proc on '
  'every call rather than stored, because a stored list was correct until 0422 added a probe point and 0428 '
  'promoted one, both in a single day. Comment-stripped (twin.ottoq_sim_advance_visit_atoms matches the '
  'probe on a raw grep and zero times stripped -- it calls the wrapper), whitespace-tolerant (the literal '
  'COALESCE(v_blocks,0)>0 misses ottoq_decide_tick''s sixth site, which spells it with spaces) and '
  'variable-name-tolerant (0428 introduced v_shield_blocks). A caller passing the context as a VARIABLE '
  'cannot be mapped statically and is returned with action_context IS NULL and '
  'posture=unresolvable_variable_context rather than omitted -- see 0430 section 2.';

-- ── (B) THE VIEW: what the shield said, beside what the engine did ──
CREATE OR REPLACE VIEW public.ottoq_rule_evaluation_effect AS
  SELECT re.evaluation_id, re.evaluated_at, re.rule_code, re.action_context,
         re.entity_type, re.entity_id, re.depot_id, re.sim_run_id,
         re.passed, re.severity, re.enforcement, re.reason,
         re.enforcement_taken AS recommendation,
         CASE
           WHEN re.enforcement_taken <> 'blocked' THEN re.enforcement_taken
           WHEN pp.posture IN ('enforced','mixed')  THEN 'refused'
           WHEN pp.posture = 'advisory'             THEN 'recorded_only'
           ELSE 'unknown_posture'
         END AS effect,
         pp.posture AS probe_posture
    FROM public.ottoq_rule_evaluations re
    LEFT JOIN public.ottoq_shield_probe_posture() pp ON pp.action_context = re.action_context;

COMMENT ON VIEW public.ottoq_rule_evaluation_effect IS
  'G149/0430. ottoq_rule_evaluations.enforcement_taken is what the SHIELD recommended; `effect` is what the '
  'ENGINE did with it. blocked + an enforcing caller = refused; blocked + a discarding caller = '
  'recorded_only. NEVER quote "N decisions blocked by the L1 shield" from the base table without naming the '
  'probe point -- at six of ten it means the opposite of what it reads (0337 section 3). CAVEAT: the posture '
  'is computed at READ time from today''s code, so rows evaluated before a promotion read under today''s '
  'posture. Window on the promoting migration to read a historical rate honestly -- 0428 (20260922170157) '
  'promoted charge_session_start.';

-- ── (C) THE ASSERTION: no probe point may be silently unknown ──
CREATE OR REPLACE FUNCTION public.ottoq_assert_shield_posture_known()
RETURNS TABLE (action_context text, blocked_rows bigint, verdict text)
LANGUAGE sql STABLE AS $body$
  SELECT re.action_context,
         count(*) FILTER (WHERE re.enforcement_taken='blocked') AS blocked_rows,
         CASE WHEN pp.action_context IS NULL
              THEN 'UNKNOWN -- this context appears in the ledger but no caller passing it as a LITERAL was '
                || 'found. Either a new probe point was added, or it is served by a variable-context caller '
                || '(0430 section 2). Read ottoq_shield_probe_posture() and resolve it before quoting any '
                || 'rate over this context.'
              ELSE 'known: '||pp.posture END AS verdict
    FROM public.ottoq_rule_evaluations re
    LEFT JOIN public.ottoq_shield_probe_posture() pp ON pp.action_context = re.action_context
   GROUP BY re.action_context, pp.action_context, pp.posture
   ORDER BY 2 DESC;
$body$;

-- ── V1: the derivation reproduces the hand census, including the promotion 0428 made ──
DO $$
DECLARE v_enforced int; v_advisory int; v_charge text; v_unres int;
BEGIN
  SELECT count(*) FILTER (WHERE posture='enforced'),
         count(*) FILTER (WHERE posture='advisory'),
         count(*) FILTER (WHERE posture='unresolvable_variable_context')
    INTO v_enforced, v_advisory, v_unres
    FROM public.ottoq_shield_probe_posture();

  SELECT posture INTO v_charge FROM public.ottoq_shield_probe_posture()
   WHERE action_context='charge_session_start';
  IF v_charge IS DISTINCT FROM 'enforced' THEN
    RAISE EXCEPTION '0430 V1: charge_session_start reads "%" but 0428 promoted it -- the derivation does not '
                    'track reality and must not ship', v_charge;
  END IF;
  IF v_enforced < 4 THEN
    RAISE EXCEPTION '0430 V1: only % enforced contexts; 0345 measured four before 0428 promoted a fifth',
                    v_enforced;
  END IF;
  IF v_advisory < 1 THEN
    RAISE EXCEPTION '0430 V1: no advisory contexts -- G149 says there are five. The discard detection is '
                    'broken and this instrument would report full enforcement.';
  END IF;
  RAISE NOTICE '0430 V1: % enforced, % advisory, % unresolvable', v_enforced, v_advisory, v_unres;
END $$;

-- ── V2: the view actually separates the two populations, which is the whole point ──
DO $$
DECLARE v_refused bigint; v_recorded bigint; v_unknown bigint;
BEGIN
  SELECT count(*) FILTER (WHERE effect='refused'),
         count(*) FILTER (WHERE effect='recorded_only'),
         count(*) FILTER (WHERE effect='unknown_posture')
    INTO v_refused, v_recorded, v_unknown
    FROM public.ottoq_rule_evaluation_effect
   WHERE recommendation='blocked';
  IF v_refused + v_recorded + v_unknown = 0 THEN
    RAISE EXCEPTION '0430 V2: the view classified zero blocked rows -- the join is wrong';
  END IF;
  IF v_unknown > 0 THEN
    RAISE WARNING '0430 V2: % blocked rows sit at a context with no resolvable caller -- run '
                  'ottoq_assert_shield_posture_known() and resolve before quoting a rate', v_unknown;
  END IF;
  RAISE NOTICE '0430 V2: blocked rows split refused=% recorded_only=% unknown=%',
               v_refused, v_recorded, v_unknown;
END $$;

-- ── V3: the instrument must NOT claim the base column changed ──
DO $$
DECLARE v_base bigint; v_view bigint;
BEGIN
  SELECT count(*) INTO v_base FROM public.ottoq_rule_evaluations WHERE enforcement_taken='blocked';
  SELECT count(*) INTO v_view FROM public.ottoq_rule_evaluation_effect WHERE recommendation='blocked';
  IF v_base <> v_view THEN
    RAISE EXCEPTION '0430 V3: base table has % blocked rows and the view %, so the view is filtering or '
                    'duplicating. It must reclassify, never change the population.', v_base, v_view;
  END IF;
  RAISE NOTICE '0430 V3: % blocked rows in, % out -- the view reclassifies and does not filter',
               v_base, v_view;
END $$;

-- ── LINEAGE. In the file and inside the transaction. ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0430_the_ledger_says_blocked_and_cannot_say_whether_anything_was_blocked_so_it_learns_to_say_both',
  false,
  'G149. ottoq_rule_evaluations.enforcement_taken=blocked is the SHIELD''s recommendation, and at six of ten '
  'probe points the caller discards it, so 5,721 of 7,626 blocked rows record a refusal that never happened. '
  'This changes NO enforcement: it adds ottoq_shield_probe_posture() (per action_context, whether the caller '
  'acts on the verdict), the view ottoq_rule_evaluation_effect (recommendation beside effect: refused / '
  'recorded_only / unknown_posture) and ottoq_assert_shield_posture_known(). DERIVED, NOT STORED: a stored '
  'list was correct until 0422 added a probe point and 0428 promoted one, both the same day. The derivation '
  'is comment-stripped (advance_visit_atoms matches the probe on a raw grep and zero times stripped), '
  'whitespace-tolerant (the literal COALESCE(v_blocks,0)>0 finds five of decide_tick''s six honouring '
  'branches and misses the one spelled with spaces -- the fourth near-miss on this one column) and '
  'variable-name-tolerant (0428 added v_shield_blocks). STATES ITS OWN BLIND SPOT: ottoq_shield_and_log '
  'passes the context as a VARIABLE and does branch, so no static derivation can map it; it is returned with '
  'action_context IS NULL and posture=unresolvable_variable_context rather than omitted, because a '
  'variable-context caller could one day be the only caller of some context. CAVEAT recorded in the view''s '
  'comment: posture is computed at READ time, so rows evaluated before a promotion read under today''s '
  'posture -- window on the promoting migration. Deliberately does not backfill, does not alter '
  'enforcement_taken (rewriting what the shield said to agree with what the engine did would destroy the '
  'distinction), and promotes nothing. FALSE: three read-only objects, no engine path touched, no atom '
  'reads them.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §6 AFTER APPLYING ═════════════════════════════════════════════════════════
--
--   SELECT * FROM public.ottoq_shield_probe_posture();
--   SELECT * FROM public.ottoq_assert_shield_posture_known();
--   SELECT effect, count(*) FROM public.ottoq_rule_evaluation_effect
--    WHERE recommendation='blocked' GROUP BY 1 ORDER BY 2 DESC;
--
-- **Read the third one with §4(2) in hand.** The posture is today's, so a blocked row written at
-- `charge_session_start` before `0428` (`20260922170157`) will read `refused` although nothing refused it at
-- the time. To count honestly across a promotion, window on the promoting migration:
--
--   … WHERE recommendation='blocked' AND evaluated_at >= '2026-09-22 17:01:57+00'
--
-- **And the sentence this migration finally makes sayable, which is the point:** instead of *"5,721 of 7,626
-- blocked rows record a refusal that never happened, and to know which you must read PL/pgSQL"*, the honest
-- count is now `WHERE effect = 'recorded_only'`.
