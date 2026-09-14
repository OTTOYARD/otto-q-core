-- migration-version: PENDING
-- migration-name:    0278_arming_the_agentic_layer_is_a_five_key_hand_ritual_and_the_demo_got_four
--
-- 0278  ARMING THE AGENTIC LAYER IS A HAND RITUAL, AND A RUN ARMED FOUR WAYS
--       OUT OF FIVE LOOKS EXACTLY LIKE A RUN THAT IS ARMED
--
-- ---------------------------------------------------------------------------
-- THE MEASUREMENT THIS FILE EXISTS FOR  (db/checks/0214)
--
-- CP-SAT has fired four times in its life, across two runs. Every one of those
-- four fires read a frame built with `proposer_frame_facts` = 0, because that
-- key has never been set at ANY scope -- not global, not depot, not run, not
-- once, in the whole life of the database:
--
--   SELECT count(*) FROM ottoq_policy_params WHERE param_key='proposer_frame_facts';
--   -> 0
--
-- With the gate off, migration 0265's whole apparatus is dark. The frame does
-- not carry `offerable`, `reserved_by`, `reservation_live`, `charger_state`,
-- `charger_fresh`, `has_live_booking` or the `selector` block, so
-- proposer/forward_proposer.py's candidate filter (frame_to_scenario ->
-- stall_block_reason -> stall_is_free) falls back to its pre-0265 test --
-- status and occupancy -- which a stall that is RESERVED BUT EMPTY passes.
--
-- CP-SAT was therefore offered points the door would refuse, and named them.
-- That is the shape of G49: 23 of 23 `noop_no_candidate` proposals named a
-- stall booked in the same run for a different vehicle.
--
-- The producer, the consumer, the candidate filter, the graceful fallback and
-- the fire-record contract stamp were all built, tested and shipped. One table
-- row was missing.
--
-- ---------------------------------------------------------------------------
-- WHY THIS FILE IS NOT "INSERT THE ROW"
--
-- Inserting the row by hand is what produced this. Both CP-SAT runs were armed
-- by hand, by `d3_demo`, with four keys each:
--
--   cuopt_first_refusal_max_defers = 1     proposer_hold_enabled      = 1
--   cuopt_propose_enabled          = 0     orchestrator_agent_enabled = 0
--
-- and neither got the fifth. Nothing in the repository arms a proposer run --
-- `grep -rn policy_set --include=*.py --include=*.sh --include=*.yml` returns
-- nothing -- so the ritual lives in an operator's memory, and a run armed four
-- ways out of five is indistinguishable, to every instrument we have, from a
-- run that is armed.
--
-- That is db/migrations/0277's defect one rung out. 0277 fixed a census that
-- could not tell "has proposed" from "has never existed." This is a system
-- that cannot tell "armed" from "armed except for the key that matters."
--
-- So this file makes arming ONE CALL that cannot be done partially, and makes
-- PARTIAL ARMING A STATE THE SYSTEM REPORTS.
--
-- ---------------------------------------------------------------------------
-- THE KEY SET, AND WHY EACH IS IN IT
--
--   proposer_frame_facts           = 1   0265. The frame carries the facts the
--                                        door pre-filters on, so a proposer
--                                        never has to guess whether a point is
--                                        real. Without it the other two arm a
--                                        proposer to answer from a blind frame.
--   proposer_hold_enabled          = 1   0259/0262. The one-tick right of first
--                                        refusal for a non-cuOpt proposer. The
--                                        gate in ottoq_cuopt_defer_hold reads
--                                        (cuopt_propose_enabled >= 1 OR this).
--   cuopt_first_refusal_max_defers = 1   The arm's own bound, read by
--                                        ottoq_cuopt_first_refusal_arm. 0152
--                                        set the GLOBAL tier to 0 as an off
--                                        switch, so without a run-scope row
--                                        nothing is ever armed and the hold
--                                        above can never bind.
--
-- DELIBERATELY NOT IN THE SET, and each omission is a decision:
--
--   cuopt_propose_enabled      global is already 0 (0152) and the hold gate is
--                              satisfied by proposer_hold_enabled alone. An arm
--                              turns things ON; it does not carry somebody
--                              else's off switch.
--   orchestrator_agent_enabled same -- a quiescing key, not an arming key.
--   proposer_seat              0261's A/B BASELINE selector (seat 0 is otto_q;
--                              non-zero delegates the in-tick fallback to
--                              ottoq_l2_propose_stall_seat). It is the POLICY
--                              dimension. Bundling it into a PROPOSER arm is
--                              exactly the conflation db/checks/0146 warns
--                              about: swapping the policy must not swap the
--                              constraint set, and arming a proposer must not
--                              silently swap the policy. It also still carries
--                              0262's original bug -- 12 rows written, 0 catalog
--                              rows, 4 live readers, so ottoq_policy_set answers
--                              {"ok":false,"error":"unknown_param"} and writes
--                              nothing while callers that ignore the receipt
--                              believe they set it. Recorded in db/checks/0214
--                              sec.4; its own file, not this one.
--
-- ---------------------------------------------------------------------------
-- RUN SCOPE ONLY, AND WHY THAT IS LOAD-BEARING
--
-- 0265's own catalog entry: "RUN SCOPE ONLY: with the key absent (0) the frame
-- is byte-identical to its pre-0265 output, which is what every certification
-- arm sees." A global or depot row would change the frame under every
-- certification arm at that scope and invalidate the canon.
--
-- So ottoq_agentic_arm writes run scope and nothing else, refuses a
-- cert_harness run outright, and A4 asserts no global/depot row appeared.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
-- Three checks; the middle one is load-bearing. ottoq_sim_runs cannot see an
-- in-flight pair at all (both arms run in one transaction, rows uncommitted and
-- invisible), and cron.job_run_details reports an in-flight pair as
-- status='succeeded' in about a second. pg_stat_activity is the only authority.
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0278 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0278 P-: a determinism pair is running right now';
  END IF;

  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0278 P-: % sim run(s) are in flight', v_runs;
  END IF;

  RAISE NOTICE '0278 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P1. THE BROKEN WORLD THIS FILE DESCRIBES MUST STILL BE THE WORLD ------------
-- Two-sided, in 0276's style: the file's whole argument is that the key has
-- never been set. If someone set it by hand between the measurement and the
-- apply, this file's header is a lie and A3 below would pass for the wrong
-- reason. Refuse rather than ship a document that no longer matches.
DO $p1$
DECLARE v_n int; v_cat int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_frame_facts';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0278 P1: proposer_frame_facts now has % row(s); 0214 measured 0. '
                    'Re-measure and rewrite the header before applying.', v_n;
  END IF;
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog
   WHERE param_key IN ('proposer_frame_facts','proposer_hold_enabled','cuopt_first_refusal_max_defers');
  IF v_cat <> 3 THEN
    RAISE EXCEPTION '0278 P1: expected all 3 arming keys in ottoq_policy_param_catalog, found %. '
                    'ottoq_policy_set silently refuses an uncatalogued key (0262).', v_cat;
  END IF;
  RAISE NOTICE '0278 P1: key unset (0 rows), all 3 arming keys catalogued';
END $p1$;

-- P2. THE TWO RUNS THE ASSERTIONS READ MUST STILL BE THERE --------------------
DO $p2$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs
   WHERE sim_run_id IN ('ccf48af1-0507-4a80-ac26-ec7a303c8826'::uuid,
                        'af2def1b-8413-4eba-a434-637444b06bb9'::uuid)
     AND run_by <> 'cert_harness';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0278 P2: expected both CP-SAT demo runs present and non-cert, found %', v_n;
  END IF;
  RAISE NOTICE '0278 P2: both CP-SAT demo runs present and non-cert';
END $p2$;

-- ---------------------------------------------------------------------------
-- SNAPSHOT. Both functions are new, so there is nothing to overwrite. The
-- snapshot is taken anyway and will be empty: an empty snapshot row set is the
-- evidence that this file created rather than replaced, and a NON-empty one
-- would mean a name collision worth stopping for.
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0278_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_agentic_arm','ottoq_agentic_arming');

-- ---------------------------------------------------------------------------
-- 1. THE REPORT. What is this run armed for, and what is missing.
--
-- Read-only and total: every run id has a defined answer, including one that
-- does not exist. Verdicts:
--
--   unknown_run     no ottoq_sim_runs row
--   cert_excluded   run_by='cert_harness' -- arming is refused by design, and
--                   that is a STATE, not a fault
--   armed           every key in the set is at its required value
--   partial         at least one, but not all, are
--   unarmed         none are
CREATE OR REPLACE FUNCTION public.ottoq_agentic_arming(p_sim_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_run_by text; v_found boolean;
  v_keys   jsonb := '[]'::jsonb;
  v_k      record;
  v_have   numeric; v_ok int := 0; v_tot int := 0;
  v_missing text[] := ARRAY[]::text[];
BEGIN
  SELECT r.run_by, true INTO v_run_by, v_found
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT COALESCE(v_found, false) THEN
    RETURN jsonb_build_object('verdict','unknown_run','sim_run_id',p_sim_run_id);
  END IF;

  FOR v_k IN
    SELECT * FROM (VALUES
      ('proposer_frame_facts',           1::numeric,
       '0265: the frame carries the facts the door pre-filters on'),
      ('proposer_hold_enabled',          1::numeric,
       '0259/0262: one-tick right of first refusal for a non-cuOpt proposer'),
      ('cuopt_first_refusal_max_defers', 1::numeric,
       '0152 set the global tier to 0; without a run row nothing is ever armed')
    ) AS t(param_key, required, why)
    ORDER BY 1
  LOOP
    v_tot := v_tot + 1;
    --: The DEFAULT passed here is deliberately 0, not the caller default the
    --: engine's own readers use. This function asks "what is SET", and a key
    --: that resolves only through a caller's fallback is not set.
    v_have := COALESCE(public.ottoq_policy_get(p_sim_run_id, v_k.param_key, 0), 0);
    IF v_have >= v_k.required THEN
      v_ok := v_ok + 1;
    ELSE
      v_missing := v_missing || v_k.param_key;
    END IF;
    v_keys := v_keys || jsonb_build_array(jsonb_build_object(
      'param_key', v_k.param_key, 'required', v_k.required,
      'in_force', v_have, 'satisfied', v_have >= v_k.required, 'why', v_k.why));
  END LOOP;

  RETURN jsonb_build_object(
    'sim_run_id', p_sim_run_id,
    'run_by', v_run_by,
    'verdict', CASE WHEN v_run_by = 'cert_harness' THEN 'cert_excluded'
                    WHEN v_ok = v_tot THEN 'armed'
                    WHEN v_ok = 0     THEN 'unarmed'
                    ELSE 'partial' END,
    'satisfied', v_ok, 'required', v_tot,
    'missing', to_jsonb(v_missing), 'keys', v_keys);
END $$;

COMMENT ON FUNCTION public.ottoq_agentic_arming(uuid) IS
'0278. What is this run armed for, and what is missing. Read-only and total. '
'Verdicts: unknown_run, cert_excluded, armed, partial, unarmed. "partial" is '
'the state that had no name before this migration, and is the state both '
'CP-SAT demo runs were actually in.';

-- ---------------------------------------------------------------------------
-- 2. THE ARM. One call, run scope only, all-or-nothing, with a receipt.
--
-- NOT a total function and deliberately so: unlike anything on the decide-tick
-- path, this is an OPERATOR action, and an operator who half-armed a run must
-- be told loudly rather than warned quietly. The failure mode this file exists
-- to end is precisely a silent partial success.
CREATE OR REPLACE FUNCTION public.ottoq_agentic_arm(p_sim_run_id uuid, p_by text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  v_run_by text; v_found boolean; v_k record; v_r jsonb;
  v_receipts jsonb := '[]'::jsonb;
BEGIN
  IF p_sim_run_id IS NULL OR NULLIF(p_by,'') IS NULL THEN
    RAISE EXCEPTION 'ottoq_agentic_arm: sim_run_id and by are both required'
      USING ERRCODE = '22023';
  END IF;

  SELECT r.run_by, true INTO v_run_by, v_found
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT COALESCE(v_found, false) THEN
    RAISE EXCEPTION 'ottoq_agentic_arm: run % does not exist', p_sim_run_id
      USING ERRCODE = '22023';
  END IF;

  --: THE CANON GUARD. 0265: with the key absent the frame is byte-identical to
  --: its pre-0265 output, "which is what every certification arm sees." Arming
  --: a certification arm would change the frame under the canon. Refused here
  --: rather than left to the operator, which is the whole point of the file.
  IF v_run_by = 'cert_harness' THEN
    RAISE EXCEPTION 'ottoq_agentic_arm: run % is a certification arm (run_by=cert_harness). '
                    'Arming it would change the frame the canon was measured against. '
                    'A proposer reaches a certification by record-and-replay (0237/0239), '
                    'never by being armed into one.', p_sim_run_id
      USING ERRCODE = '42501';
  END IF;

  FOR v_k IN
    SELECT * FROM (VALUES
      ('proposer_frame_facts',           1::numeric),
      ('proposer_hold_enabled',          1::numeric),
      ('cuopt_first_refusal_max_defers', 1::numeric)
    ) AS t(param_key, value) ORDER BY 1
  LOOP
    --: ALWAYS run scope. ottoq_policy_set clamps to the catalog range and
    --: answers {"ok":false,"error":"unknown_param"} for a key it does not know
    --: WITHOUT raising (0262) -- so the receipt is read, not assumed. That
    --: unread receipt is the exact mechanism by which proposer_seat has 12 rows
    --: nobody could have written through the setter.
    v_r := public.ottoq_policy_set('run', p_sim_run_id, v_k.param_key, v_k.value, p_by);
    IF NOT COALESCE((v_r->>'ok')::boolean, false) THEN
      RAISE EXCEPTION 'ottoq_agentic_arm: ottoq_policy_set refused % -> %', v_k.param_key, v_r
        USING ERRCODE = '22023';
    END IF;
    IF COALESCE((v_r->>'clamped')::boolean, false) THEN
      RAISE EXCEPTION 'ottoq_agentic_arm: % was clamped from % to % by the catalog range %; '
                      'an arm that silently lands on a different value is the defect this '
                      'function exists to end',
                      v_k.param_key, v_r->>'requested', v_r->>'applied', v_r->>'safe_range'
        USING ERRCODE = '22023';
    END IF;
    v_receipts := v_receipts || jsonb_build_array(v_r);
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'armed_by', p_by,
                            'receipts', v_receipts,
                            'arming', public.ottoq_agentic_arming(p_sim_run_id));
END $$;

COMMENT ON FUNCTION public.ottoq_agentic_arm(uuid, text) IS
'0278. Arm one run for the agentic layer in a single call: run scope only, '
'all-or-nothing, receipt-checked, and refused outright on a cert_harness run. '
'Replaces a five-key hand ritual that was got wrong on both of the only two '
'runs it was ever performed on (db/checks/0214).';

REVOKE EXECUTE ON FUNCTION public.ottoq_agentic_arm(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ottoq_agentic_arm(uuid, text) FROM anon;

-- ---------------------------------------------------------------------------
-- A1. THE REPORT NAMES THE BROKEN WORLD AS BROKEN.
-- Ordered FIRST, and reading the run this file never touches, so it cannot be
-- confused by A2's write. This is the assertion that matters: an instrument
-- that cannot see the defect it was built for is not an instrument.
DO $a1$
DECLARE v jsonb;
BEGIN
  v := public.ottoq_agentic_arming('ccf48af1-0507-4a80-ac26-ec7a303c8826'::uuid);
  IF v->>'verdict' <> 'partial' THEN
    RAISE EXCEPTION 'A1 FAILED: CP-SAT demo run reads %, expected partial: %', v->>'verdict', v;
  END IF;
  IF NOT (v->'missing' @> '["proposer_frame_facts"]'::jsonb) THEN
    RAISE EXCEPTION 'A1 FAILED: missing does not name proposer_frame_facts: %', v;
  END IF;
  IF jsonb_array_length(v->'missing') <> 1 THEN
    RAISE EXCEPTION 'A1 FAILED: expected exactly one missing key, got %', v->'missing';
  END IF;
  RAISE NOTICE 'A1 OK: the run that fired CP-SAT four times reads partial, missing exactly '
               'proposer_frame_facts (satisfied %/%)', v->>'satisfied', v->>'required';
END $a1$;

-- A2. ARMING WORKS, AND THE HISTORICAL RECORD IS PUT BACK.
-- Precise about what "put back" means: of the three keys, two already existed on
-- this run at the required value, so ottoq_policy_set's ON CONFLICT re-writes
-- param_value to the same number and moves updated_at. It does NOT touch
-- updated_by, so those rows keep saying d3_demo -- which is true, d3_demo set
-- them. Only proposer_frame_facts is a new row, it is the only row carrying
-- updated_by='0278_proof', and it is the only row deleted. The run's ARMING
-- STATE is restored exactly; two updated_at stamps move and are not evidence of
-- anything.
-- Uses the OTHER demo run, then deletes the one row it added. Those policy rows
-- are evidence of how that run actually executed; leaving it armed would make
-- the ledger describe a run that never happened.
DO $a2$
DECLARE v_run uuid := 'af2def1b-8413-4eba-a434-637444b06bb9'::uuid;
        v_before jsonb; v_after jsonb; v_r jsonb; v_n int;
BEGIN
  v_before := public.ottoq_agentic_arming(v_run);
  IF v_before->>'verdict' <> 'partial' THEN
    RAISE EXCEPTION 'A2 SETUP FAILED: expected partial before arming, got %', v_before;
  END IF;

  v_r := public.ottoq_agentic_arm(v_run, '0278_proof');
  v_after := v_r->'arming';
  IF v_after->>'verdict' <> 'armed' THEN
    RAISE EXCEPTION 'A2 FAILED: after arming the run reads %, expected armed: %',
                    v_after->>'verdict', v_after;
  END IF;
  IF jsonb_array_length(v_after->'missing') <> 0 THEN
    RAISE EXCEPTION 'A2 FAILED: armed run still names missing keys: %', v_after->'missing';
  END IF;

  DELETE FROM public.ottoq_policy_params
   WHERE scope_type='run' AND scope_id=v_run
     AND param_key='proposer_frame_facts' AND updated_by='0278_proof';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A2 FAILED: expected to restore exactly 1 row, restored %', v_n;
  END IF;
  IF public.ottoq_agentic_arming(v_run)->>'verdict' <> 'partial' THEN
    RAISE EXCEPTION 'A2 FAILED: the historical run was not restored to partial';
  END IF;
  RAISE NOTICE 'A2 OK: arm -> armed (3/3), then restored to partial';
END $a2$;

-- A3. A CERTIFICATION ARM IS REFUSED. Proven by requiring the call to FAIL.
DO $a3$
DECLARE v_cert uuid; v_ok boolean := false;
BEGIN
  SELECT sim_run_id INTO v_cert FROM public.ottoq_sim_runs
   WHERE run_by = 'cert_harness' ORDER BY started_at DESC LIMIT 1;
  IF v_cert IS NULL THEN
    RAISE EXCEPTION 'A3 INCONCLUSIVE: no cert_harness run to test the guard against';
  END IF;
  BEGIN
    PERFORM public.ottoq_agentic_arm(v_cert, '0278_proof_must_fail');
  EXCEPTION WHEN insufficient_privilege THEN
    v_ok := true;
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'A3 FAILED: a cert_harness run was armed; the canon guard does not hold';
  END IF;
  IF public.ottoq_agentic_arming(v_cert)->>'verdict' <> 'cert_excluded' THEN
    RAISE EXCEPTION 'A3 FAILED: a cert run does not read cert_excluded';
  END IF;
  RAISE NOTICE 'A3 OK: arming a certification arm is refused, and it reads cert_excluded';
END $a3$;

-- A4. NOTHING LEAKED OUT OF RUN SCOPE. The 0265 warning, asserted.
DO $a4$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_frame_facts' AND scope_type IN ('global','depot');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: proposer_frame_facts appeared at % global/depot scope(s); '
                    'every certification arm at that scope would see a changed frame', v_n;
  END IF;
  RAISE NOTICE 'A4 OK: proposer_frame_facts exists at no global or depot scope';
END $a4$;

-- A5. AN UNKNOWN RUN HAS A DEFINED ANSWER, NOT AN ERROR.
DO $a5$
DECLARE v jsonb;
BEGIN
  v := public.ottoq_agentic_arming('00000000-0000-0000-0000-0000000000ff'::uuid);
  IF v->>'verdict' <> 'unknown_run' THEN
    RAISE EXCEPTION 'A5 FAILED: unknown run reads %, expected unknown_run', v->>'verdict';
  END IF;
  RAISE NOTICE 'A5 OK: the report is total';
END $a5$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0278_arming_the_agentic_layer_is_a_five_key_hand_ritual_and_the_demo_got_four', false,
 'Adds two NEW functions: ottoq_agentic_arming (read-only, total report -- unknown_run / cert_excluded / armed / partial / unarmed) and ottoq_agentic_arm (one call, run scope only, receipt-checked, refused outright on a cert_harness run). Replaces no existing object, has no engine caller, is on no tick path, and writes no policy row that outlives its own self-restoring A2 proof. forces_recert=false: the frame every certification arm sees is unchanged, asserted directly by A4 -- proposer_frame_facts exists at no global or depot scope and the arm cannot create one, because it writes run scope and refuses run_by=cert_harness.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
