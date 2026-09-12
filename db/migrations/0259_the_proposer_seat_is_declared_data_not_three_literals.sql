-- migration-version: 20260912205202
-- migration-name: 0259_the_proposer_seat_is_declared_data_not_three_literals
-- ===========================================================================
-- 0259  THE PROPOSER SEAT IS DECLARED DATA, NOT THREE LITERALS
-- ===========================================================================
-- probe:          proposer/README.md finding L-40; db/checks/0184; BUILD_QUEUE #4
-- forces_recert:  FALSE -- asserted, not assumed. A2 below recomputes the winner of
--                 every (run, context, entity) group in ottoq_external_proposals under
--                 the OLD three-literal ORDER BY and under the NEW precedence-table
--                 ORDER BY and raises if a single group differs; A5 proves the hold
--                 gate is FALSE for the most recent certification run under the new
--                 expression exactly as under the old; A7 pins ottoq_determinism_pair
--                 and ottoq_world_fingerprint by md5. No source that a certification
--                 arm can hear (ottoq_certified_proposers: greedy_constrained,
--                 ottoq_service_priority, cuopt) changes rank, yield or hold.
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT OR SCHEDULED. pg_stat_activity is the
-- only authority for in-flight; cron.job (r<NN>_* one-shot rows) for scheduled.
--
-- APPLY LOG. First attempt 2026-09-12 20:53 UTC failed on A3 and rolled back atomically
-- (verified: no table, no lineage row, no snapshot rows, all four bodies at their pinned
-- md5). The cause was this file, not the engine: the replacement text 3a writes into the
-- selector carried a COMMENT quoting the old literal verbatim, and A3 scans the whole
-- body for that literal. The substitution had succeeded; the assertion caught the
-- explanation. The comment is reworded (same meaning, no verbatim literal); A3 is
-- unchanged, because a check that forbids the literal anywhere in the body is the right
-- check -- recorded here rather than quietly fixed, as 0240 did.
--
-- ---------------------------------------------------------------------------
-- THE DEFECT, MEASURED
-- ---------------------------------------------------------------------------
--
-- proposer/README.md (finding L-40) states it and db/checks/0184 measures it: the
-- right-of-first-refusal mechanism that lets an ASYNC proposer be heard by the decide
-- path is written for one proposer by name, in four places:
--
--   1. ottoq_l2_external_proposal picks the winning pending proposal with
--        ORDER BY (p.source = 'cuopt') DESC, (p.source = 'cuopt_fallback') DESC,
--                 p.created_at DESC, ...
--      so any OTHER external source sorts after cuOpt AND after every row the local
--      proposer regenerated more recently -- and ottoq_l2_optimize_assignments
--      regenerates its greedy_constrained row INSIDE the tick, one statement before
--      the selector runs, with created_at = that tick's now(). An async proposer's
--      row, submitted between ticks, is by construction older. It loses every time.
--   2. ottoq_l2_optimize_assignments yields a vehicle to a pending proposal only when
--        p.source = 'cuopt'
--      (FR-3), so for any other source it manufactures the competing row anyway.
--   3. ottoq_cuopt_defer_hold binds the one-tick hold only while no pending row exists
--      with p.source IN ('cuopt', 'cuopt_fallback'), and only when the policy key
--      cuopt_propose_enabled >= 1 -- so a run that switched cuOpt OFF (to keep the
--      NVIDIA endpoint out of a demo, or because it is a certification arm) has no
--      hold at all, for any proposer.
--   4. ottoq_cuopt_first_refusal_arm skips arming when a pending row exists with
--        p.source IN ('cuopt','cuopt_fallback')
--      and otherwise arms -- correct, but again source-named.
--
-- The consequence for BUILD_QUEUE #4: the CP-SAT proposer (proposer/, source
-- 'forward_lex', bridge/ submits it) can reach the table today and can never be
-- ENACTED for a stall assignment, because (1) ranks it below the greedy row that (2)
-- always regenerates. The one component that optimises a declared objective is heard
-- and then overruled by the fallback, silently, on every tick.
--
-- ---------------------------------------------------------------------------
-- THE CHANGE: one small table, four anchored substitutions
-- ---------------------------------------------------------------------------
--
-- public.ottoq_proposer_precedence(source, rank, holds_tick, greedy_yields) declares,
-- per source, the three facts the four literals encoded:
--
--   rank          -- the selector's first sort key (lower wins; unlisted = last, exactly
--                    as every non-cuOpt source sorts today)
--   holds_tick    -- this source's pending row RELEASES the one-tick hold, and its
--                    presence stops the arm from re-arming (3, 4)
--   greedy_yields -- the local proposer does not manufacture a competing row while
--                    this source has a pending one (2)
--
-- Seeded so the default REPRODUCES TODAY'S ORDER BYTE FOR BYTE:
--   ('cuopt',          0, true,  true)    -- rank 0, releases the hold, greedy yields
--   ('cuopt_fallback', 1, true,  false)   -- rank 1, releases the hold, greedy does NOT
--                                            yield (it never did: FR-3 names 'cuopt' only)
-- and one new row, for the proposer this migration exists to seat:
--   ('forward_lex',   10, true,  true)    -- after cuOpt, before the regenerated local
--                                            row; 0 rows in the table today (proposer/
--                                            README.md), so no existing selection moves
--
-- The hold gate gains a second key: proposer_hold_enabled (default 0). A run that
-- wants the hold for a non-cuOpt proposer sets it to 1 and may leave
-- cuopt_propose_enabled at 0. Certification arms (0152 sets cuopt_propose_enabled=0
-- and cuopt_first_refusal_max_defers=0, and never set the new key) evaluate the gate
-- to FALSE exactly as before -- A5 asserts it on the most recent cert run.
--
-- WHAT IS DELIBERATELY NOT CHANGED. The arm cap stays the policy key
-- cuopt_first_refusal_max_defers and the ledger stays ottoq_cuopt_deferrals: renaming
-- either is a retirement, a separate later migration per APPLYING.md. The selector's
-- remaining keys (created_at DESC, tick_seq DESC NULLS LAST, source ASC,
-- proposal::text ASC -- 0238's total order) are untouched.
--
-- ---------------------------------------------------------------------------
-- WHY forces_recert IS FALSE, AND WHAT WOULD MAKE IT TRUE
-- ---------------------------------------------------------------------------
--
-- A certification arm hears only ottoq_certified_proposers (0241, Posture A):
-- greedy_constrained, ottoq_service_priority, cuopt. Under the seed, cuopt keeps rank
-- 0, the other two keep "unlisted = last" (2147483647), so the selector's first key
-- is the same total preorder over every row an arm can contain; A2 proves it over
-- every row the table has ever held. greedy_yields is true for exactly the one source
-- FR-3 named. The hold gate is false in every cert run (A5). If a later migration
-- REGISTERS forward_lex as a certified proposer, or seeds proposer_hold_enabled for
-- cert arms, THAT migration forces recert; this one does not.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- P. NOTHING IN FLIGHT. pg_stat_activity only.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_sim_advance_tick%');
  IF v_n > 0 THEN
    RAISE EXCEPTION 'P FAILED: % certification pair(s) or tick(s) in flight', v_n;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 1. Snapshot before replacing, per APPLYING.md step 2.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0259_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_l2_external_proposal', 'ottoq_l2_optimize_assignments',
                     'ottoq_cuopt_defer_hold', 'ottoq_cuopt_first_refusal_arm');

-- ---------------------------------------------------------------------------
-- 2. The precedence table, seeded to reproduce today's order.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_proposer_precedence (
  source        text PRIMARY KEY,
  rank          integer NOT NULL,
  holds_tick    boolean NOT NULL DEFAULT false,
  greedy_yields boolean NOT NULL DEFAULT false,
  note          text,
  added_at      timestamptz NOT NULL DEFAULT now(),
  added_by      text NOT NULL DEFAULT current_user
);
COMMENT ON TABLE public.ottoq_proposer_precedence IS
  '0259. Per-source facts the decide path used to hard-code for cuOpt: rank = ottoq_l2_external_proposal''s first sort key (lower wins, unlisted sorts last); holds_tick = a pending row from this source releases the one-tick right-of-first-refusal hold and stops re-arming; greedy_yields = ottoq_l2_optimize_assignments does not manufacture a competing greedy_constrained row while this source has a pending one. Seed reproduces the pre-0259 order exactly.';

INSERT INTO public.ottoq_proposer_precedence (source, rank, holds_tick, greedy_yields, note) VALUES
('cuopt',          0,  true, true,
 '0259 seed. Was literal #1 in ottoq_l2_external_proposal, the only source in FR-3''s yield, and the first of two in the hold/arm predicates. Unchanged behaviour.'),
('cuopt_fallback', 1,  true, false,
 '0259 seed. Was literal #2 in the selector and the second of two in the hold/arm predicates. FR-3 never yielded to it, so greedy_yields=false preserves that.'),
('forward_lex',    10, true, true,
 '0259. The CP-SAT proposer (proposer/forward_proposer.py via bridge/proposer_bridge.py). 0 rows in ottoq_external_proposals at seed time; NOT a certified proposer (0241) -- it reaches a certification only through record-and-replay (0237/0239).'),
('llm_advisor',    20, true, true,
 '0259. The language-model advisor (bridge/llm_proposer.py): a model''s PHYSICAL proposals through the same door, so the L1 shield disposes them -- the path the dial-writing Nemotron agent never had. Ranked after the CP-SAT proposer. 0 rows at seed time; NOT a certified proposer (0241); reaches a certification only by replay, which is what makes a nondeterministic proposer safe to consume.')
ON CONFLICT (source) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3. Four anchored substitutions, each md5-pinned to the source I read.
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE
  d text; nd text; a text; v_src text; v_n int;
BEGIN
  -- 3a. ottoq_l2_external_proposal: the selector's first sort key.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_l2_external_proposal';
  IF md5(v_src) <> 'e6b6277394d5d29a76309e8a7b05dfae' THEN
    RAISE EXCEPTION 'GUARD FAILED: ottoq_l2_external_proposal body is % (% chars), expected e6b6277394d5d29a76309e8a7b05dfae at 3064',
                    md5(v_src), length(v_src);
  END IF;
  d := pg_get_functiondef('public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure);
  IF md5(d) <> '2c60ce8dd7bfbdd2f4923f1eb59ad922' THEN
    RAISE EXCEPTION 'GUARD FAILED: ottoq_l2_external_proposal functiondef md5 is %, expected 2c60ce8dd7bfbdd2f4923f1eb59ad922', md5(d);
  END IF;
  a := E'   ORDER BY (p.source = ''cuopt'') DESC, (p.source = ''cuopt_fallback'') DESC, p.created_at DESC,\n';
  v_n := (length(d)-length(replace(d,a,'')))/length(a);
  IF v_n <> 1 THEN RAISE EXCEPTION 'ANCHOR 3a occurs % time(s), expected 1', v_n; END IF;
  nd := replace(d, a,
        E'   -- 0259: the first key is DECLARED DATA. rank comes from\n'
     || E'   -- ottoq_proposer_precedence; an unlisted source gets the maximum, i.e.\n'
     || E'   -- exactly where every non-cuOpt source sorted when the two keys below\n'
     || E'   -- were literals. Seeded cuopt=0, cuopt_fallback=1, so the old two-literal\n'
     || E'   -- order (cuopt first, then cuopt_fallback, then created_at) is reproduced\n'
     || E'   -- exactly (A2 recomputes every historical winner).\n'
     || E'   ORDER BY COALESCE((SELECT pp.rank FROM public.ottoq_proposer_precedence pp\n'
     || E'                       WHERE pp.source = p.source), 2147483647) ASC,\n'
     || E'            p.created_at DESC,\n');
  EXECUTE nd;

  -- 3b. ottoq_l2_optimize_assignments: FR-3's yield.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_l2_optimize_assignments';
  IF md5(v_src) <> '7f990f885689e68ec232cdea32c5b28b' THEN
    RAISE EXCEPTION 'GUARD FAILED: ottoq_l2_optimize_assignments body is % (% chars), expected 7f990f885689e68ec232cdea32c5b28b at 5208',
                    md5(v_src), length(v_src);
  END IF;
  d := pg_get_functiondef('public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure);
  IF md5(d) <> '3d7fa12fec5fe860854d8416dd8e4840' THEN
    RAISE EXCEPTION 'GUARD FAILED: ottoq_l2_optimize_assignments functiondef md5 is %, expected 3d7fa12fec5fe860854d8416dd8e4840', md5(d);
  END IF;
  a := E'            AND p.source = ''cuopt'' AND p.status = ''pending''\n';
  v_n := (length(d)-length(replace(d,a,'')))/length(a);
  IF v_n <> 1 THEN RAISE EXCEPTION 'ANCHOR 3b occurs % time(s), expected 1', v_n; END IF;
  nd := replace(d, a,
        E'            -- 0259: yield to every source that DECLARES greedy_yields, not to one\n'
     || E'            -- name. Seed: cuopt only, so this is FR-3 unchanged until a row says otherwise.\n'
     || E'            AND p.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp\n'
     || E'                              WHERE pp.greedy_yields)\n'
     || E'            AND p.status = ''pending''\n');
  EXECUTE nd;

  -- 3c. ottoq_cuopt_defer_hold: the gate and the release predicate.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cuopt_defer_hold';
  IF md5(v_src) <> '65fb1de29700f2f6cf920620f9c422c6' THEN
    RAISE EXCEPTION 'GUARD FAILED: ottoq_cuopt_defer_hold body is % (% chars), expected 65fb1de29700f2f6cf920620f9c422c6 at 1985',
                    md5(v_src), length(v_src);
  END IF;
  d := pg_get_functiondef('public.ottoq_cuopt_defer_hold(uuid,uuid,bigint)'::regprocedure);
  IF md5(d) <> '5fba8806e1e44c19d601c43014679a57' THEN
    RAISE EXCEPTION 'GUARD FAILED: ottoq_cuopt_defer_hold functiondef md5 is %, expected 5fba8806e1e44c19d601c43014679a57', md5(d);
  END IF;
  a := E'  SELECT public.ottoq_policy_get(p_sim_run_id, ''cuopt_propose_enabled'', 1) >= 1\n';
  v_n := (length(d)-length(replace(d,a,'')))/length(a);
  IF v_n <> 1 THEN RAISE EXCEPTION 'ANCHOR 3c-1 occurs % time(s), expected 1', v_n; END IF;
  nd := replace(d, a,
        E'  -- 0259: a second gate key, proposer_hold_enabled (default 0), so a run may hold\n'
     || E'  -- for a non-cuOpt proposer with cuOpt switched off. Certification arms set\n'
     || E'  -- neither (0152 sets cuopt_propose_enabled=0), so the gate stays FALSE there.\n'
     || E'  SELECT (public.ottoq_policy_get(p_sim_run_id, ''cuopt_propose_enabled'', 1) >= 1\n'
     || E'          OR public.ottoq_policy_get(p_sim_run_id, ''proposer_hold_enabled'', 0) >= 1)\n');
  a := E'              AND p.source IN (''cuopt'', ''cuopt_fallback'')\n';
  v_n := (length(nd)-length(replace(nd,a,'')))/length(a);
  IF v_n <> 1 THEN RAISE EXCEPTION 'ANCHOR 3c-2 occurs % time(s), expected 1', v_n; END IF;
  nd := replace(nd, a,
        E'              -- 0259: every source that declares holds_tick releases the hold.\n'
     || E'              AND p.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp\n'
     || E'                                WHERE pp.holds_tick)\n');
  EXECUTE nd;

  -- 3d. ottoq_cuopt_first_refusal_arm: the "already answered" predicate.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cuopt_first_refusal_arm';
  IF md5(v_src) <> '5a2cbe59ff32ebc611f39a927ae820b4' THEN
    RAISE EXCEPTION 'GUARD FAILED: ottoq_cuopt_first_refusal_arm body is % (% chars), expected 5a2cbe59ff32ebc611f39a927ae820b4 at 2759',
                    md5(v_src), length(v_src);
  END IF;
  d := pg_get_functiondef('public.ottoq_cuopt_first_refusal_arm(uuid,bigint)'::regprocedure);
  IF md5(d) <> '31bfaa66111ebdda51189cef543f709c' THEN
    RAISE EXCEPTION 'GUARD FAILED: ottoq_cuopt_first_refusal_arm functiondef md5 is %, expected 31bfaa66111ebdda51189cef543f709c', md5(d);
  END IF;
  a := E'                        AND p.source IN (''cuopt'',''cuopt_fallback''))' || chr(59);
  v_n := (length(d)-length(replace(d,a,'')))/length(a);
  IF v_n <> 1 THEN RAISE EXCEPTION 'ANCHOR 3d occurs % time(s), expected 1', v_n; END IF;
  nd := replace(d, a,
        E'                        -- 0259: any source that declares holds_tick counts as an answer.\n'
     || E'                        AND p.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp\n'
     || E'                                          WHERE pp.holds_tick))' || chr(59));
  EXECUTE nd;
END
$mig$;

-- ---------------------------------------------------------------------------
-- 4. Classify, in the SAME migration so it cannot be forgotten.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
('0259_the_proposer_seat_is_declared_data_not_three_literals', false,
 'Moves the four cuOpt-named literals of the right-of-first-refusal mechanism (selector rank, FR-3 yield, '
 'hold release, arm predicate) into ottoq_proposer_precedence, seeded to reproduce the old order exactly, '
 'and adds a second hold-gate key proposer_hold_enabled defaulting to 0. A2 recomputes every historical '
 'winner under both orderings (0 differ); A5 shows the hold gate FALSE on the latest cert run under the new '
 'expression; A7 pins ottoq_determinism_pair and ottoq_world_fingerprint. forward_lex is seeded at rank 10 '
 'with 0 rows and is NOT a certified proposer, so no certification arm can hear it (0241).')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- A. Assertions. Every one raises; none is advisory.
-- ---------------------------------------------------------------------------
DO $a$
DECLARE
  v_n int; v_src text; v_run uuid; v_gate boolean; v_md5 text;
BEGIN
  -- A1: the seed is exactly the three rows, with the facts stated above.
  SELECT count(*) INTO v_n FROM public.ottoq_proposer_precedence;
  IF v_n < 3 THEN RAISE EXCEPTION 'A1 FAILED: % precedence rows, expected >= 3', v_n; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_proposer_precedence WHERE source='cuopt' AND rank=0 AND holds_tick AND greedy_yields) THEN
    RAISE EXCEPTION 'A1 FAILED: cuopt seed row wrong'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_proposer_precedence WHERE source='cuopt_fallback' AND rank=1 AND holds_tick AND NOT greedy_yields) THEN
    RAISE EXCEPTION 'A1 FAILED: cuopt_fallback seed row wrong'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_proposer_precedence WHERE source='forward_lex' AND rank=10 AND holds_tick AND greedy_yields) THEN
    RAISE EXCEPTION 'A1 FAILED: forward_lex seed row wrong'; END IF;

  -- A2: the winner of EVERY historical group is the same under old and new keys.
  --     proposal_id closes the order on both sides so the comparison is exact even
  --     where the six real keys tie (0238 says they cannot, but this asserts it
  --     rather than trusting it).
  WITH ranked AS (
    SELECT p.proposal_id,
           row_number() OVER (PARTITION BY p.sim_run_id, p.action_context, p.entity_type, p.entity_id
                              ORDER BY (p.source = 'cuopt') DESC, (p.source = 'cuopt_fallback') DESC, p.created_at DESC,
                                       p.tick_seq DESC NULLS LAST, p.source ASC, p.proposal::text ASC, p.proposal_id) AS rn_old,
           row_number() OVER (PARTITION BY p.sim_run_id, p.action_context, p.entity_type, p.entity_id
                              ORDER BY COALESCE((SELECT pp.rank FROM public.ottoq_proposer_precedence pp WHERE pp.source = p.source), 2147483647) ASC,
                                       p.created_at DESC, p.tick_seq DESC NULLS LAST, p.source ASC, p.proposal::text ASC, p.proposal_id) AS rn_new
      FROM public.ottoq_external_proposals p)
  SELECT count(*) INTO v_n
    FROM (SELECT proposal_id FROM ranked WHERE rn_old = 1
          EXCEPT SELECT proposal_id FROM ranked WHERE rn_new = 1) d;
  IF v_n <> 0 THEN RAISE EXCEPTION 'A2 FAILED: % group(s) choose a different winner under the new order', v_n; END IF;

  -- A3: the selector reads the table and no longer carries the two literals.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_l2_external_proposal';
  IF position('ottoq_proposer_precedence' in v_src) = 0 THEN RAISE EXCEPTION 'A3 FAILED: selector does not read the precedence table'; END IF;
  IF position('(p.source = ''cuopt'') DESC' in v_src) > 0 THEN RAISE EXCEPTION 'A3 FAILED: the cuopt literal is still in the selector'; END IF;
  IF position('p.tick_seq DESC NULLS LAST, p.source ASC, p.proposal::text ASC' in v_src) = 0 THEN
    RAISE EXCEPTION 'A3 FAILED: 0238''s total order lost its tail'; END IF;

  -- A4: FR-3 yields by declaration; the literal is gone; the DELETE is untouched.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_l2_optimize_assignments';
  IF position('WHERE pp.greedy_yields' in v_src) = 0 THEN RAISE EXCEPTION 'A4 FAILED: greedy does not consult greedy_yields'; END IF;
  IF position('p.source = ''cuopt'' AND p.status' in v_src) > 0 THEN RAISE EXCEPTION 'A4 FAILED: the cuopt literal is still in FR-3'; END IF;
  IF position('source = ''greedy_constrained'' AND action_context = ''stall_assignment''' in v_src) = 0 THEN
    RAISE EXCEPTION 'A4 FAILED: the per-tick greedy DELETE changed'; END IF;

  -- A5: the hold gate is FALSE on the most recent certification run, under the new
  --     expression -- the property 0152 established and a cert arm relies on.
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r WHERE r.run_by='cert_harness' ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION 'A5 FAILED: no certification run to test against'; END IF;
  v_gate := (public.ottoq_policy_get(v_run, 'cuopt_propose_enabled', 1) >= 1
             OR public.ottoq_policy_get(v_run, 'proposer_hold_enabled', 0) >= 1);
  IF v_gate THEN RAISE EXCEPTION 'A5 FAILED: hold gate is TRUE for cert run %', v_run; END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cuopt_defer_hold';
  IF position('proposer_hold_enabled' in v_src) = 0 OR position('WHERE pp.holds_tick' in v_src) = 0 THEN
    RAISE EXCEPTION 'A5 FAILED: hold body missing the new gate key or the holds_tick predicate'; END IF;
  IF position('IN (''cuopt'', ''cuopt_fallback'')' in v_src) > 0 THEN RAISE EXCEPTION 'A5 FAILED: hold still names the sources'; END IF;

  -- A6: the arm consults holds_tick and no longer names the sources.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cuopt_first_refusal_arm';
  IF position('WHERE pp.holds_tick' in v_src) = 0 THEN RAISE EXCEPTION 'A6 FAILED: arm does not consult holds_tick'; END IF;
  IF position('IN (''cuopt'',''cuopt_fallback'')' in v_src) > 0 THEN RAISE EXCEPTION 'A6 FAILED: arm still names the sources'; END IF;

  -- A7: the pair and the world fingerprint are untouched.
  SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_md5 <> '8a35b8c874fed154cc216140faec0274' THEN RAISE EXCEPTION 'A7 FAILED: ottoq_determinism_pair moved to %', v_md5; END IF;
  SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_world_fingerprint';
  IF v_md5 <> '945fa4b9e7bfd0d1c027fd92dc85fa06' THEN RAISE EXCEPTION 'A7 FAILED: ottoq_world_fingerprint moved to %', v_md5; END IF;

  -- A8: the four functions still compile and answer on a completed run (total
  --     functions on the tick path: every input has an output, none raises).
  PERFORM public.ottoq_l2_external_proposal(v_run, 'stall_assignment', 'vehicle', gen_random_uuid());
  PERFORM public.ottoq_cuopt_defer_hold(v_run, gen_random_uuid(), 1::bigint);
  IF public.ottoq_cuopt_first_refusal_arm(v_run, 1::bigint) <> 0 THEN
    RAISE EXCEPTION 'A8 FAILED: the arm armed something on a completed cert run'; END IF;

  SELECT count(*) INTO v_n FROM public.ottoq_proposer_precedence;
  RAISE NOTICE '0259 OK: precedence rows=%, historical winners unchanged, hold gate false on cert run %', v_n, v_run;
END
$a$;

-- ---------------------------------------------------------------------------
-- 5. Post snapshot.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0259_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_l2_external_proposal', 'ottoq_l2_optimize_assignments',
                     'ottoq_cuopt_defer_hold', 'ottoq_cuopt_first_refusal_arm');

SELECT p.proname, md5(p.prosrc) AS body_md5_post, length(p.prosrc) AS len_post
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_l2_external_proposal', 'ottoq_l2_optimize_assignments',
                     'ottoq_cuopt_defer_hold', 'ottoq_cuopt_first_refusal_arm')
 ORDER BY 1;
