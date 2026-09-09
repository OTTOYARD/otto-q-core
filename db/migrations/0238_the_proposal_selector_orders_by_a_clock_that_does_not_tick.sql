-- migration-version: 20260909031408
-- migration-name:    the_proposal_selector_orders_by_a_clock_that_does_not_tick
--
-- G41 / db/checks/0156.
--
-- ottoq_external_proposals.created_at DEFAULTS TO now(), and in PostgreSQL
-- now() is the TRANSACTION timestamp -- frozen for the life of the transaction.
-- A certification pair runs BOTH ARMS AND EVERY TICK IN ONE TRANSACTION; that
-- is the design of ottoq_determinism_pair, not an accident of it.
--
-- So `ORDER BY ... p.created_at DESC LIMIT 1` sorts nothing inside a
-- certification, and both readers of the proposal table fall through to
-- index-scan order. Measured over the whole table on 2026-09-09:
--
--   runs carrying proposals                                   827
--   runs where ALL proposals share one created_at             822   (99.4%)
--   proposals living in such a run             14,282 of 14,502   (98.5%)
--   groups where the ORDER BY has no deciding key                69
--   ...of which the two rows hold DIFFERENT proposals             68
--
-- and proven behaviourally, then rolled back (db/checks/0156):
--
--   the same two proposals submitted A,B  ->  the selector chose A
--   the same two proposals submitted B,A  ->  the selector chose B
--
-- The enacted action is a function of the order rows were written, which is
-- not an input to the decision.
--
-- ---------------------------------------------------------------------------
-- THIS DEFECT HAS BEEN CONVICTED HERE BEFORE
-- ---------------------------------------------------------------------------
-- Migration 0067 closed the identical shape in the stall selector next door
-- and left this one standing. Its comment is still in
-- ottoq_l2_optimize_assignments:
--
--     "the score above is byte-identical for two stalls of the same type at
--      the same distance, so LIMIT 1 returned heap order. Measured in re-cert
--      #19 at tick 10 ... handed to the same two vehicles in OPPOSITE order
--      across two same-seed arms, and by tick 18 fifty vehicles had diverged."
--
-- Same fix shape: append content keys until the order is total on the answer.
--
-- ---------------------------------------------------------------------------
-- TWO SITES, BOTH ON THE DECIDE PATH
-- ---------------------------------------------------------------------------
--   1. public.ottoq_l2_external_proposal(uuid,text,text,uuid)
--      the only read path from ottoq_external_proposals into ottoq_decide_tick
--      (called at its lines 128 'redeployment' and 958 'service_sequencing').
--
--   2. ottoq.ottoq_reoptimize_reservation_book(uuid,timestamptz) line 39
--      called from public.ottoq_sim_decide_and_dispatch. Chooses the STALL a
--      vehicle is swapped to out of pending cuOpt proposals. Its ORDER BY is
--      created_at DESC and nothing else -- source is already pinned to 'cuopt'
--      by the WHERE, so the bucket keys would not have helped it either.
--
-- ---------------------------------------------------------------------------
-- WHY NOW: IT BLOCKS POSTURE B
-- ---------------------------------------------------------------------------
-- 0237 records an agent proposal stream and replays it. Its capture is
-- CONTENT-ordered on purpose (0237 A2 asserts that, so a replay is
-- reproducible). The original run consumed those proposals in SUBMISSION
-- order. While insertion order decides, a faithful replay of a faithfully
-- recorded stream can enact a DIFFERENT proposal than the run it came from --
-- silently, with every atom matching, because h_prop hashes the SET of
-- proposals and not the choice among them.
--
-- A replay cannot certify a disposer whose output depends on something the
-- replay does not reproduce. This migration is therefore step 2.5 of the
-- SOLVER_STATE.md 8.3 sequence, and it comes before the replay-driven arm.
--
-- ---------------------------------------------------------------------------
-- THE ORDER, AND WHY IT STOPS WHERE IT DOES
-- ---------------------------------------------------------------------------
--   p.tick_seq DESC NULLS LAST   0236 gave the proposal its tick. This is what
--                                created_at DESC was trying to express and
--                                could not. NULLS LAST: pre-0236 rows have no
--                                tick and lose to rows that do.
--   p.source ASC                 stable bucket inside the same freshness.
--   p.proposal::text ASC         jsonb renders canonically (sorted keys,
--                                normalised whitespace), so this is a stable
--                                content key.
--
-- and NOT p.proposal_id. It is gen_random_uuid(): stable within an arm,
-- DIFFERENT between arms. Ordering by it would reintroduce the exact defect
-- being fixed, disguised as its remedy. Two rows equal on
-- (source, created_at, tick_seq, proposal) are interchangeable in the value
-- returned, so stopping here makes the order total ON THE ANSWER, which is the
-- only place totality is required.
--
-- Site 2 additionally orders by (p.proposal->>'stall_id'), because that -- not
-- the row -- is what it returns.
--
-- ---------------------------------------------------------------------------
-- forces_recert: TRUE
-- ---------------------------------------------------------------------------
-- Nothing DEFINED changes: every outcome this alters was undefined before it.
-- But the decide path's observable behaviour can move, and a canon that was
-- standing on index-scan order should be made to say so out loud. A recert
-- round follows this migration.
--
-- ottoq_decide_tick's own body is NOT edited (A5 pins its md5); only the two
-- functions it calls are.

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction.)

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
-- pg_stat_activity is the only authority: ottoq_sim_runs cannot see an
-- in-flight pair (both arms are one uncommitted transaction) and
-- cron.job_run_details reports one as 'succeeded' in about a second.
DO $inflight$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active'
     AND (query LIKE '%ottoq_determinism_pair%' OR query LIKE '%ottoq_cert_arm%');
  IF n > 0 THEN RAISE EXCEPTION 'P- REFUSED: % certification pair(s)/arm(s) in flight', n; END IF;
END $inflight$;

-- SNAPSHOT BEFORE REPLACE ----------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0238_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname='public' AND p.proname='ottoq_l2_external_proposal')
    OR (n.nspname='ottoq'  AND p.proname='ottoq_reoptimize_reservation_book');

-- P1. THE BODIES ARE THE ONES THIS WAS WRITTEN AGAINST ------------------------
DO $p1$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure));
  IF h <> 'b35e189067e678803d863b1af57565eb' THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_l2_external_proposal md5 is %, pinned b35e189067e678803d863b1af57565eb', h;
  END IF;
  h := md5(pg_get_functiondef('ottoq.ottoq_reoptimize_reservation_book(uuid,timestamptz)'::regprocedure));
  IF h <> 'db254f6974f17e8db0cda918cf83497a' THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_reoptimize_reservation_book md5 is %, pinned db254f6974f17e8db0cda918cf83497a', h;
  END IF;
END $p1$;

-- P2. tick_seq EXISTS. 0236 added it; without it the new key is a syntax error
--     at CREATE time, but a clear refusal beats a parse error in a log.
DO $p2$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='ottoq_external_proposals'
                    AND column_name='tick_seq') THEN
    RAISE EXCEPTION 'P2 REFUSED: ottoq_external_proposals.tick_seq is absent; 0236 has not been applied';
  END IF;
END $p2$;

-- ---------------------------------------------------------------------------
-- CHG1. SITE 1 -- the decide path's proposal reader. Catalog-derived, anchored,
--       uniqueness asserted before the rewrite is built.
-- ---------------------------------------------------------------------------
DO $chg1$
DECLARE d text; a1 text; n int;
BEGIN
  d  := pg_get_functiondef('public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure);
  a1 := '   ORDER BY (p.source = ''cuopt'') DESC, (p.source = ''cuopt_fallback'') DESC, p.created_at DESC';

  n := (length(d) - length(replace(d, a1, ''))) / length(a1);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG1 REFUSED: ORDER BY anchor occurs % times, expected 1', n; END IF;

  d := replace(d, a1, a1 || ','
    || E'\n            -- 0238 / db/checks/0156: the three keys above TIE. created_at defaults'
    || E'\n            -- to now(), which is the TRANSACTION timestamp, and a certification pair'
    || E'\n            -- runs both arms and every tick in one transaction -- so 98.5% of all'
    || E'\n            -- recorded proposals share one created_at and LIMIT 1 returned'
    || E'\n            -- index-scan order. Proven: the same two proposals submitted A,B chose A'
    || E'\n            -- and submitted B,A chose B. Same defect 0067 closed in the stall'
    || E'\n            -- selector next door. These three keys are total ON THE ANSWER.'
    || E'\n            -- proposal_id is deliberately NOT among them: gen_random_uuid() differs'
    || E'\n            -- between arms, which would reintroduce the defect as its own remedy.'
    || E'\n            p.tick_seq DESC NULLS LAST, p.source ASC, p.proposal::text ASC');

  EXECUTE d;
END $chg1$;

-- ---------------------------------------------------------------------------
-- CHG2. SITE 2 -- the swap-stall picker inside the reservation reoptimiser.
-- ---------------------------------------------------------------------------
DO $chg2$
DECLARE d text; a2 text; n int;
BEGIN
  d  := pg_get_functiondef('ottoq.ottoq_reoptimize_reservation_book(uuid,timestamptz)'::regprocedure);
  a2 := '     ORDER BY p.created_at DESC LIMIT 1;';

  n := (length(d) - length(replace(d, a2, ''))) / length(a2);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG2 REFUSED: ORDER BY anchor occurs % times, expected 1', n; END IF;

  d := replace(d, a2,
       '     ORDER BY p.created_at DESC,'
    || E'\n              /* 0238 / db/checks/0156: created_at is now() -- the TRANSACTION'
    || E'\n                 timestamp -- and a cert pair is one transaction, so it ties across'
    || E'\n                 the whole run. source is already pinned to ''cuopt'' by the WHERE, so'
    || E'\n                 nothing was deciding and LIMIT 1 returned scan order: an ARBITRARY'
    || E'\n                 stall for the swap. Ordered on content, and on stall_id because that'
    || E'\n                 -- not the row -- is what this SELECT returns. proposal_id excluded:'
    || E'\n                 gen_random_uuid() differs between arms. */'
    || E'\n              p.tick_seq DESC NULLS LAST, (p.proposal->>''stall_id'') ASC, p.proposal::text ASC'
    || E'\n      LIMIT 1;');

  EXECUTE d;
END $chg2$;

-- ===========================================================================
-- THE ASSERTIONS.
--
-- Behavioural, and deliberately built so they can FAIL. A textual check that
-- the words "tick_seq" and "proposal::text" appear in the ORDER BY would pass
-- on an implementation that put them in the wrong order, in the wrong
-- direction, or ahead of the source preference. Every claim below is made by
-- submitting real proposals through the real selector and reading back which
-- one it chose. A1 is the fix; A2, A3 and A4 are the negative controls that
-- show the instrument discriminates.
--
-- The probes clean up after themselves (A7 verifies), the way 0236 A1 did.
-- ===========================================================================
DO $TESTS$
DECLARE
  v_run uuid; v_veh uuid; v_a text; v_b text; v_tail text; v_d text;
  v_s1 text; v_s2 text;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 1;
  SELECT id         INTO v_veh FROM public.vehicles WHERE category='autonomous' ORDER BY id LIMIT 1;
  IF v_run IS NULL OR v_veh IS NULL THEN
    RAISE EXCEPTION 'TEST SETUP FAILED: need one sim run and one vehicle to probe with';
  END IF;

  ---------------------------------------------------------------------------
  -- A1  THE FLIP IS CLOSED. The same two proposals, submitted in both orders,
  --     must produce the same choice. This is the exact experiment db/checks/
  --     0156 ran before the fix, where it returned A then B.
  ---------------------------------------------------------------------------
  INSERT INTO public.ottoq_external_proposals
    (sim_run_id, action_context, entity_type, entity_id, proposal, source, status)
  VALUES (v_run,'0238_fwd','vehicle',v_veh,'{"tag":"aaa"}','probe_0238','pending'),
         (v_run,'0238_fwd','vehicle',v_veh,'{"tag":"bbb"}','probe_0238','pending'),
         (v_run,'0238_rev','vehicle',v_veh,'{"tag":"bbb"}','probe_0238','pending'),
         (v_run,'0238_rev','vehicle',v_veh,'{"tag":"aaa"}','probe_0238','pending');

  -- the premise the whole migration rests on, asserted rather than assumed
  IF (SELECT count(DISTINCT created_at) FROM public.ottoq_external_proposals
       WHERE action_context IN ('0238_fwd','0238_rev')) <> 1 THEN
    RAISE EXCEPTION 'A1 INVALID: created_at differs inside one transaction; now() is not frozen';
  END IF;

  v_a := public.ottoq_l2_external_proposal(v_run,'0238_fwd','vehicle',v_veh) ->> 'tag';
  v_b := public.ottoq_l2_external_proposal(v_run,'0238_rev','vehicle',v_veh) ->> 'tag';
  IF v_a IS DISTINCT FROM v_b THEN
    RAISE EXCEPTION 'A1 FAILED: insertion order still decides -- A,B chose %, B,A chose %', v_a, v_b;
  END IF;

  ---------------------------------------------------------------------------
  -- A2  NEGATIVE CONTROL: DIRECTION. The content key is ASC, so the
  --     lexicographically first proposal wins. An implementation that wrote
  --     proposal::text DESC would pass A1 and fail here.
  ---------------------------------------------------------------------------
  IF v_a <> 'aaa' THEN
    RAISE EXCEPTION 'A2 FAILED: content key is not ASC -- expected aaa, chose %', v_a;
  END IF;

  ---------------------------------------------------------------------------
  -- A3  NEGATIVE CONTROL: THE SOURCE PREFERENCE SURVIVED. The new keys were
  --     APPENDED, not prepended. cuOpt must still outrank a local proposer even
  --     when the local proposer wins every content key -- 'aaa' < 'zzz' and
  --     'cuopt' < 'ottoq_service_priority'. An implementation that put the
  --     content keys first would pass A1 and A2 and fail here.
  ---------------------------------------------------------------------------
  INSERT INTO public.ottoq_external_proposals
    (sim_run_id, action_context, entity_type, entity_id, proposal, source, status)
  VALUES (v_run,'0238_pref','vehicle',v_veh,'{"tag":"aaa"}','ottoq_service_priority','pending'),
         (v_run,'0238_pref','vehicle',v_veh,'{"tag":"zzz"}','cuopt','pending');

  v_a := public.ottoq_l2_external_proposal(v_run,'0238_pref','vehicle',v_veh) ->> 'tag';
  IF v_a <> 'zzz' THEN
    RAISE EXCEPTION 'A3 FAILED: the cuOpt preference no longer dominates -- chose % (expected zzz)', v_a;
  END IF;

  ---------------------------------------------------------------------------
  -- A4  NEGATIVE CONTROL: tick_seq IS ACTUALLY CONSULTED, AND OUTRANKS CONTENT.
  --     The later tick carries the lexicographically LAST proposal, so a
  --     selector that ignored tick_seq would return 'a1'. Both insertion orders
  --     must return 'z9'.
  ---------------------------------------------------------------------------
  INSERT INTO public.ottoq_external_proposals
    (sim_run_id, action_context, entity_type, entity_id, proposal, source, status, tick_seq)
  VALUES (v_run,'0238_tick_f','vehicle',v_veh,'{"tag":"a1"}','probe_0238','pending',1),
         (v_run,'0238_tick_f','vehicle',v_veh,'{"tag":"z9"}','probe_0238','pending',9),
         (v_run,'0238_tick_r','vehicle',v_veh,'{"tag":"z9"}','probe_0238','pending',9),
         (v_run,'0238_tick_r','vehicle',v_veh,'{"tag":"a1"}','probe_0238','pending',1);

  v_a := public.ottoq_l2_external_proposal(v_run,'0238_tick_f','vehicle',v_veh) ->> 'tag';
  v_b := public.ottoq_l2_external_proposal(v_run,'0238_tick_r','vehicle',v_veh) ->> 'tag';
  IF v_a <> 'z9' OR v_b <> 'z9' THEN
    RAISE EXCEPTION 'A4 FAILED: tick_seq does not decide -- chose % and % (expected z9 twice)', v_a, v_b;
  END IF;

  ---------------------------------------------------------------------------
  -- A5  SITE 2, EXECUTED RATHER THAN READ. The reservation reoptimiser needs a
  --     depot full of reserved vehicles to reach line 39, which no assertion
  --     can conjure inside a migration. So instead of retyping its ORDER BY and
  --     testing the copy -- which proves nothing about the shipped function --
  --     this LIFTS the ordering expression out of the live catalog definition
  --     and runs THAT over probe rows. If CHG2 wrote something different from
  --     what is asserted here, this executes the difference.
  ---------------------------------------------------------------------------
  INSERT INTO public.ottoq_external_proposals
    (sim_run_id, action_context, entity_type, entity_id, proposal, source, status)
  VALUES (v_run,'0238_s2f','vehicle',v_veh,'{"stall_id":"11111111-1111-1111-1111-111111111111"}','cuopt','pending'),
         (v_run,'0238_s2f','vehicle',v_veh,'{"stall_id":"99999999-9999-9999-9999-999999999999"}','cuopt','pending'),
         (v_run,'0238_s2r','vehicle',v_veh,'{"stall_id":"99999999-9999-9999-9999-999999999999"}','cuopt','pending'),
         (v_run,'0238_s2r','vehicle',v_veh,'{"stall_id":"11111111-1111-1111-1111-111111111111"}','cuopt','pending');

  v_d := pg_get_functiondef('ottoq.ottoq_reoptimize_reservation_book(uuid,timestamptz)'::regprocedure);
  v_tail := split_part(split_part(v_d, '     ORDER BY p.created_at DESC,', 2), 'LIMIT 1;', 1);
  IF v_tail = '' OR v_tail IS NULL THEN
    RAISE EXCEPTION 'A5 FAILED: could not lift site 2''s ORDER BY tail out of the live definition';
  END IF;

  EXECUTE 'SELECT (p.proposal->>''stall_id'') FROM public.ottoq_external_proposals p '
       || 'WHERE p.action_context = ''0238_s2f'' ORDER BY p.created_at DESC,' || v_tail || ' LIMIT 1'
    INTO v_s1;
  EXECUTE 'SELECT (p.proposal->>''stall_id'') FROM public.ottoq_external_proposals p '
       || 'WHERE p.action_context = ''0238_s2r'' ORDER BY p.created_at DESC,' || v_tail || ' LIMIT 1'
    INTO v_s2;

  IF v_s1 IS DISTINCT FROM v_s2 THEN
    RAISE EXCEPTION 'A5 FAILED: site 2 still returns insertion order -- % vs %', v_s1, v_s2;
  END IF;
  IF v_s1 <> '11111111-1111-1111-1111-111111111111' THEN
    RAISE EXCEPTION 'A5 FAILED: site 2''s stall key is not ASC -- chose %', v_s1;
  END IF;

  ---------------------------------------------------------------------------
  -- CLEAN UP. A7 verifies this actually happened.
  ---------------------------------------------------------------------------
  DELETE FROM public.ottoq_external_proposals WHERE action_context LIKE '0238\_%';
END $TESTS$;

-- A6  THE REMEDY IS NOT THE DEFECT. Neither ORDER BY may reach for
--     proposal_id: gen_random_uuid() is stable within an arm and different
--     between arms, so ordering by it would look like a fix and behave like
--     the bug. Asserted against both live definitions, not against intent.
DO $a6$
DECLARE d text;
BEGIN
  FOREACH d IN ARRAY ARRAY[
      pg_get_functiondef('public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure),
      pg_get_functiondef('ottoq.ottoq_reoptimize_reservation_book(uuid,timestamptz)'::regprocedure)]
  LOOP
    -- every ORDER BY ... LIMIT region in the body, non-greedy so the regions do
    -- not run into each other. split_part(d,'ORDER BY',2) was the first draft and
    -- was wrong: ottoq_reoptimize_reservation_book has four ORDER BYs, so part 2
    -- is the text between the FIRST and SECOND of them and never reaches line 39.
    IF EXISTS (SELECT 1 FROM regexp_matches(d, 'ORDER BY(.*?)LIMIT', 'gs') m
                WHERE m[1] ~ 'proposal_id') THEN
      RAISE EXCEPTION 'A6 FAILED: an ORDER BY reaches for proposal_id (gen_random_uuid), which differs between arms';
    END IF;
  END LOOP;
END $a6$;

-- A7  NO RESIDUE, AND THE DECIDE PATH ITSELF IS UNTOUCHED.
DO $a7$
DECLARE n int; h text;
BEGIN
  SELECT count(*) INTO n FROM public.ottoq_external_proposals
   WHERE action_context LIKE '0238\_%' OR source = 'probe_0238';
  IF n <> 0 THEN RAISE EXCEPTION 'A7 FAILED: % probe row(s) left behind', n; END IF;

  h := md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure));
  IF h <> 'ae98f71b879a0a11bdf366d21ff5b4eb' THEN
    RAISE EXCEPTION 'A7 FAILED: ottoq_decide_tick md5 moved to %', h;
  END IF;
END $a7$;

INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'the_proposal_selector_orders_by_a_clock_that_does_not_tick',
  now(),
  true,
  'G41 / db/checks/0156. ottoq_external_proposals.created_at defaults to now(), '
  'which is the TRANSACTION timestamp, and a certification pair runs both arms and '
  'every tick in ONE transaction -- so ORDER BY created_at DESC sorted nothing and '
  'LIMIT 1 returned index-scan order. Measured: 821 of 827 runs carrying proposals '
  'have every proposal sharing one created_at (14,282 of 14,502 rows); 69 groups had '
  'no deciding key, 68 of them holding different proposals. Proven and rolled back: '
  'the same two proposals submitted A,B chose A and submitted B,A chose B. Two live '
  'decide-path sites fixed -- ottoq_l2_external_proposal (both decide_tick call '
  'sites) and ottoq_reoptimize_reservation_book line 39 (the swap stall). Ordered on '
  'content: tick_seq DESC NULLS LAST, then source, then proposal::text -- never '
  'proposal_id, which is gen_random_uuid and differs between arms (A6 asserts that). '
  'forces_recert TRUE: nothing DEFINED changes, since every outcome this alters was '
  'undefined, but the decide path can move and a canon standing on scan order should '
  'say so. Blocks nothing downstream except Posture B, which it unblocks: 0237 '
  'captures content-ordered while runs consumed in submission order, so a faithful '
  'replay could enact a different proposal with every atom matching.'
);

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 22:15 CT (2026-09-09 03:15 UTC), version 20260909031408,
-- first attempt, all seven assertions green.
--
--   ottoq_l2_external_proposal          b35e1890... -> 2c60ce8dd7bfbdd2f4923f1eb59ad922
--   ottoq_reoptimize_reservation_book   db254f69... -> 66d1bcdcd6a50d054b17535ff8e44ef5
--   ottoq_decide_tick                   ae98f71b879a0a11bdf366d21ff5b4eb   UNCHANGED
--   pre-images snapshotted              2  (label 0238_pre)
--   probe residue                       0
--   lineage row, forces_recert TRUE     present
--   RECERT FLOOR MOVED                  2026-09-07 21:36:53.363037
--                                    -> 2026-09-09 03:15:07.410339
--
-- THEN, INDEPENDENTLY OF THE MIGRATION'S OWN ASSERTIONS, db/checks/0156's
-- experiment was re-run verbatim and rolled back:
--
--   before 0238:  submitted A,B -> chose A   |   submitted B,A -> chose B
--   after  0238:  submitted A,B -> chose A   |   submitted B,A -> chose A
--
-- The flip is closed. This matters more than A1 passing: A1 is a test the
-- migration brought with it, and this is the finding's own instrument, run
-- again afterwards without being told what to expect.
--
-- ---------------------------------------------------------------------------
-- WHAT IS NOW OWED
-- ---------------------------------------------------------------------------
-- forces_recert TRUE reset every canon streak. A recert round follows; until
-- it completes, no column is green and no number from before 03:15 UTC today
-- should be quoted as certified.
--
-- NEXT: 0239, the replay-driven certification arm. It was the task in hand when
-- this defect surfaced, and it could not have been honest before this migration:
-- 0237 captures a proposal stream in CONTENT order (its A2 asserts that) while
-- the run being recorded consumed in SUBMISSION order, and h_prop hashes the SET
-- of proposals rather than the CHOICE among them. A replay could therefore have
-- enacted a different proposal from the run it was recorded from, with all
-- fourteen atoms matching. Now that the selector is total on content, the
-- recorded order and the replayed order agree by construction.
