-- migration-version: 20260914040837
-- migration-name:    0279_the_dial_that_can_kill_a_certification_arm_is_not_in_the_catalog
--
-- 0279  THE ONE DIAL THAT CAN KILL A CERTIFICATION ARM IS THE ONE DIAL THE
--       SETTER WILL NOT WRITE
--
-- ---------------------------------------------------------------------------
-- 0262'S BUG, ON A THIRD KEY, AND THIS TIME IT IS LOAD-BEARING
--
-- Found while pinning 0278's key set (db/checks/0214 sec.4).
--
-- `proposer_seat` is 0261's A/B baseline selector. Measured today:
--
--   rows in ottoq_policy_params          12   (8 x seat 0, 3 x seat 1, 1 x seat 2)
--   rows in ottoq_policy_param_catalog    0
--   live functions that READ it           4   ottoq_ab_pair, ottoq_decide_tick,
--                                             ottoq_l2_propose_stall_assignment,
--                                             ottoq_sim_decide_and_dispatch
--
-- Because it is not catalogued, the setter refuses it and writes nothing:
--
--   SELECT ottoq_policy_set('run', <run>, 'proposer_seat', 1, 'x');
--   -> {"ok": false, "error": "unknown_param", "param": "proposer_seat"}
--
-- and it returns ok:false rather than RAISING, so a caller that does not read
-- the receipt is told nothing at all. All twelve existing rows were therefore
-- written around the setter, straight into the table, with no validation of
-- any kind. That is exactly 0262's finding -- and 0262 fixed the key it was
-- about, not the class.
--
-- ---------------------------------------------------------------------------
-- WHY THIS ONE IS WORSE THAN 0262's
--
-- proposer_hold_enabled is a boolean gate: a wrong value turns a feature off.
-- proposer_seat is dispatched on, and the dispatch has no default:
--
--   ottoq_l2_propose_stall_seat:
--     v_source := CASE p_seat WHEN 1 THEN 'fifo' WHEN 2 THEN 'greedy' END;
--     IF v_source IS NULL THEN
--       RAISE EXCEPTION 'ottoq_l2_propose_stall_seat: seat % is not a
--                        baseline (1 = fifo, 2 = greedy)', p_seat;
--     END IF;
--
-- So the legal set is exactly {0, 1, 2} -- 0 is otto_q and never reaches this
-- function, 1 is fifo, 2 is greedy -- and ANY other number raises.
--
-- Traced to where that raise lands, and it is not a warning:
--
--   ottoq_l2_propose_stall_assignment  delegates on seat <> 0, NO handler
--     <- ottoq_ab_arm_atoms            NO exception handler anywhere
--     <- ottoq_cert_arm_start          NO exception handler anywhere
--     <- ottoq_honour_reservation_proposal  (has one; this path is safe)
--
-- An operator who writes proposer_seat = 3 into the table -- the only way the
-- key CAN be written today -- kills an A/B arm or a certification arm outright.
-- The rule the whole engine is built on is that a failure must never abort a
-- tick, and this is a dial that can, reachable only by the unvalidated path.
--
-- ---------------------------------------------------------------------------
-- THE FIX IS ONE CATALOG ROW, AND IT DOES TWO THINGS
--
--   1. ottoq_policy_set starts ACCEPTING the key, so the supported way to set
--      it stops being "write to the table yourself."
--   2. ottoq_policy_set CLAMPS to [0, 2], so seat 3 lands on greedy instead of
--      raising inside an arm that cannot catch it.
--
-- On (2) and silent wrong values: the clamp is not silent. ottoq_policy_set
-- returns 'clamped': true and the requested-vs-applied pair in its receipt,
-- which is the same contract 0278's ottoq_agentic_arm refuses on. A caller
-- that reads its receipt is told; a caller that ignores it gets greedy instead
-- of a dead certification arm. Both are better than today.
--
-- NOT DONE HERE, on purpose: no attempt to make the direct-INSERT path
-- impossible. A CHECK constraint on ottoq_policy_params would have to know
-- every key's range and would duplicate the catalog; the right shape is a
-- trigger validating against the catalog, which is a bigger change with its
-- own blast radius and belongs in its own file. This migration closes the hole
-- for the one key that can abort an arm, and names the general one.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0279 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0279 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0279 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0279 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P1. THE KEY IS STILL UNCATALOGUED (two-sided: the file's premise) ------------
DO $p1$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key = 'proposer_seat';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0279 P1: proposer_seat is already catalogued (% row(s)); '
                    'this file''s premise no longer holds', v_n;
  END IF;
  RAISE NOTICE '0279 P1: proposer_seat is uncatalogued, as measured';
END $p1$;

-- P2. THE LEGAL SET IS STILL {0,1,2} -----------------------------------------
-- The range below is NOT a judgement call, it is read off the dispatch. If
-- somebody adds seat 3 to ottoq_l2_propose_stall_seat, this precondition fails
-- and the catalog row is re-derived rather than silently capping a real seat.
DO $p2$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_l2_propose_stall_seat';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0279 P2: ottoq_l2_propose_stall_seat does not exist';
  END IF;
  IF position('WHEN 1 THEN ''fifo'' WHEN 2 THEN ''greedy''' in v_src) = 0 THEN
    RAISE EXCEPTION '0279 P2: the seat dispatch is no longer exactly '
                    '(1 = fifo, 2 = greedy); re-derive max_value before applying';
  END IF;
  IF position('is not a baseline' in v_src) = 0 THEN
    RAISE EXCEPTION '0279 P2: the out-of-range seat no longer raises; '
                    're-read the function before trusting this file''s argument';
  END IF;
  RAISE NOTICE '0279 P2: seat dispatch is {1=fifo, 2=greedy} and out-of-range still raises';
END $p2$;

-- P3. EVERY EXISTING ROW IS ALREADY INSIDE THE RANGE THIS FILE DECLARES -------
-- If one were not, cataloguing would leave a live row the setter itself would
-- refuse to write -- a state worse than the one being fixed. Checked, not hoped.
DO $p3$
DECLARE v_bad int;
BEGIN
  SELECT count(*) INTO v_bad FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_seat' AND (param_value < 0 OR param_value > 2);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0279 P3: % existing proposer_seat row(s) are outside [0,2]; '
                    'they must be corrected before the key is catalogued', v_bad;
  END IF;
  RAISE NOTICE '0279 P3: all existing proposer_seat rows are within [0,2]';
END $p3$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES ('proposer_seat',
 '0261/0279: which assignment policy owns the in-tick fallback for a run. 0 = otto_q (the local decide path; ottoq_l2_propose_stall_assignment answers it directly), 1 = fifo, 2 = greedy -- non-zero delegates to ottoq_l2_propose_stall_seat, whose dispatch has NO default and RAISES on any other number. That raise reaches ottoq_ab_arm_atoms and ottoq_cert_arm_start, neither of which has an exception handler, so an out-of-range seat kills an A/B or certification arm outright. 0279 catalogues the key for two reasons: so ottoq_policy_set will write it at all (until then it answered unknown_param and all 12 live rows were written around the setter, unvalidated), and so the setter CLAMPS to [0,2] -- a mistyped seat becomes greedy, with clamped:true in the receipt, instead of a dead arm. THE RANGE IS READ OFF THE DISPATCH, not chosen: widen ottoq_l2_propose_stall_seat first, then max_value.',
 0, 0, 2, 'ottoq_l2_propose_stall_assignment, ottoq_l2_propose_stall_seat, ottoq_ab_pair, ottoq_decide_tick, ottoq_sim_decide_and_dispatch');

-- ---------------------------------------------------------------------------
-- A1. THE SETTER NOW ACCEPTS THE KEY IT HAS ALWAYS REFUSED.
-- Scratch scope id, not any real run: ottoq_policy_set does not check that a
-- run exists, which is why a scratch write is safe and why it is deleted below.
DO $a1$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000027900aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'proposer_seat', 1, '0279_proof');
  IF NOT COALESCE((v_r->>'ok')::boolean,false) THEN
    RAISE EXCEPTION 'A1 FAILED: ottoq_policy_set still refuses proposer_seat: %', v_r;
  END IF;
  IF public.ottoq_policy_get(v_scratch, 'proposer_seat', -1) <> 1 THEN
    RAISE EXCEPTION 'A1 FAILED: the value did not read back as 1';
  END IF;
  RAISE NOTICE 'A1 OK: the setter writes proposer_seat and it reads back';
END $a1$;

-- A2. AN OUT-OF-RANGE SEAT IS CLAMPED, AND THE RECEIPT SAYS SO.
-- This is the assertion that matters: seat 3 written directly into the table is
-- what kills an arm, and through the setter it can no longer land.
DO $a2$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000027900aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'proposer_seat', 3, '0279_proof');
  IF COALESCE((v_r->>'applied')::numeric, -1) <> 2 THEN
    RAISE EXCEPTION 'A2 FAILED: seat 3 applied as %, expected the clamp to 2: %',
                    v_r->>'applied', v_r;
  END IF;
  IF NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: the receipt does not report the clamp -- a silent '
                    'wrong value is not an improvement on a loud one: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'proposer_seat', -5, '0279_proof');
  IF COALESCE((v_r->>'applied')::numeric, -1) <> 0 THEN
    RAISE EXCEPTION 'A2 FAILED: seat -5 applied as %, expected the clamp to 0', v_r->>'applied';
  END IF;
  RAISE NOTICE 'A2 OK: 3 clamps to 2 and -5 clamps to 0, both reported as clamped';
END $a2$;

-- A3. THE TWELVE LIVE ROWS ARE UNTOUCHED AND STILL LEGAL.
DO $a3$
DECLARE v_n int; v_bad int;
BEGIN
  SELECT count(*) FILTER (WHERE updated_by <> '0279_proof'),
         count(*) FILTER (WHERE updated_by <> '0279_proof' AND (param_value < 0 OR param_value > 2))
    INTO v_n, v_bad
    FROM public.ottoq_policy_params WHERE param_key = 'proposer_seat';
  IF v_n <> 12 THEN
    RAISE EXCEPTION 'A3 FAILED: expected the 12 pre-existing proposer_seat rows, found %', v_n;
  END IF;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'A3 FAILED: % pre-existing row(s) outside [0,2]', v_bad;
  END IF;
  RAISE NOTICE 'A3 OK: 12 pre-existing rows, all within [0,2], none rewritten';
END $a3$;

-- A4. THE SCRATCH ROW IS GONE. A proof must not leave a dial behind.
DO $a4$
DECLARE v_n int;
BEGIN
  DELETE FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_seat' AND updated_by = '0279_proof';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A4 FAILED: expected to remove exactly 1 scratch row, removed %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params WHERE param_key='proposer_seat';
  IF v_n <> 12 THEN
    RAISE EXCEPTION 'A4 FAILED: % proposer_seat rows remain, expected the original 12', v_n;
  END IF;
  RAISE NOTICE 'A4 OK: scratch removed, 12 rows remain -- exactly what was here before';
END $a4$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0279_the_dial_that_can_kill_a_certification_arm_is_not_in_the_catalog', false,
 'One row in ottoq_policy_param_catalog for proposer_seat (0261''s A/B baseline selector), range [0,2] read off the dispatch in ottoq_l2_propose_stall_seat (0 = otto_q, 1 = fifo, 2 = greedy; anything else RAISES into ottoq_ab_arm_atoms and ottoq_cert_arm_start, neither of which has a handler). Effect: ottoq_policy_set stops answering unknown_param and starts clamping, so a mistyped seat becomes greedy with clamped:true in the receipt instead of a dead certification arm. No function is replaced, no engine behaviour changes for any in-range value, and the 12 pre-existing rows are untouched and asserted still in range (A3/A4). forces_recert=false: a catalog row is read only by ottoq_policy_set, which no certification arm calls.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- ===========================================================================
-- APPLIED 2026-09-14 04:08:37 UTC (11:08 PM CT, 2026-09-13) as
-- supabase_migrations.schema_migrations version 20260914040837.
--
-- Dry run: the file byte for byte inside BEGIN ... ROLLBACK, clean on the first
-- attempt. P-, P1, P2, P3 and A1-A4 all passed.
--
-- VERIFIED AFTER APPLY, against the live database:
--
--   ottoq_policy_param_catalog rows for proposer_seat   1   (was 0)
--   ottoq_policy_params rows for proposer_seat         12   (unchanged)
--   rows left behind by the proof                       0
--
--   ottoq_policy_set('run', <scratch>, 'proposer_seat', 7, ...)
--     -> {"ok": true, "applied": 2, "clamped": true,
--         "requested": 7, "safe_range": [0, 2]}
--
-- Seat 7 was, an hour ago, a value that could only be written by hand straight
-- into the table and would have raised inside ottoq_cert_arm_start with no
-- handler. It now lands on greedy and says so.
--
-- AND THE VERIFICATION ITSELF LEFT A DIAL BEHIND, which is worth writing down
-- rather than quietly cleaning up. The clamp probe above is a WRITE: it created
-- a live proposer_seat row at a scratch scope, tagged 0279_verify -- exactly
-- the litter A4 exists to forbid, produced by the step that checked A4's work.
-- Removed immediately and re-counted: 12 rows, zero rows tagged 0279%.
--
-- The lesson generalises past this file: an assertion that a migration leaves
-- nothing behind does not cover the operator confirming it afterwards. A probe
-- that mutates is part of the change, and belongs inside the transaction that
-- can roll it back.
-- ===========================================================================
