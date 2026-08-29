-- migration-version: 20260829204500
-- migration-name:    the_kernel_defends_the_verb
-- 0091 -- R5, the REAL second writer -- and the discovery that 0090 patched a corpse.
--
-- WHAT THE FRESH RUN SHOWED (d5a8b7e8, seed 777012): 6 verbless enacted decisions, all
-- stall_assignment, all with proposed_action = the raw cuOpt proposal. Fingerprinting the rows
-- (full rule_results, propose/shield/enact latencies, l2_engine='cuopt') proved they are written
-- by the DECIDE PATH's shielded enactment inside ottoq_decide_tick -- the deferral-pattern
-- disposer -- not by ottoq_enact_cuopt_batch, which 0090 patched.
--
-- TWO FACTS ABOUT ottoq_enact_cuopt_batch, established while tracing this:
--   * ZERO callers anywhere in pg_proc (public/twin/ottoq). Dead code.
--   * Its ottoq_decisions INSERT names columns that DO NOT EXIST (proposal_latency_ms,
--     enactment_latency_ms) -- it would raise 42703 on any execution. It can never have
--     written a decision row in its current form. 0090's premise was wrong; its patch is
--     harmless (the dead function is now merely more correct). Disposal of the dead function
--     is a separate decision -- nothing is deleted here.
--
-- THE ACTUAL ASYMMETRY: the local greedy proposer (ottoq_l2_optimize_assignments) writes
-- 'verb','assign_stall' into every proposal it makes; the cuOpt edge proposer does not. The
-- disposer records whichever proposal wins, verbatim -- so cuOpt-won enactments are verbless.
--
-- ONE PATCH: public.ottoq_l2_external_proposal -- the single funnel through which EVERY
-- external proposal reaches the decide path -- normalizes a verbless, non-abstaining
-- stall_assignment proposal with 'verb':'assign_stall', tagged 'verb_by':'kernel_default' so
-- the trail says the KERNEL supplied the word, not the proposer. This is the same
-- normalization the function already performs for a missing 'source' key, and it covers every
-- current and future proposer at once instead of chasing each one.
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   public.ottoq_l2_external_proposal   f2cbd18b9b592e2abecd4c7e186cf9b9

DO $do$
DECLARE
  v_oid oid; v_src text; v_new text; v_cnt int;

  v_a1_old text := E'  SELECT CASE\n'
                || E'           WHEN p.proposal ? ''source'' THEN p.proposal\n'
                || E'           ELSE p.proposal || jsonb_build_object(''source'', p.source)\n'
                || E'         END\n';
  v_a1_new text := E'  SELECT (CASE\n'
                || E'           WHEN p.proposal ? ''source'' THEN p.proposal\n'
                || E'           ELSE p.proposal || jsonb_build_object(''source'', p.source)\n'
                || E'         END)\n'
                || E'         -- 0091: same normalization as ''source'' above, for the verb. The local\n'
                || E'         -- greedy proposer writes verb ''assign_stall'' itself; cuOpt''s edge proposer\n'
                || E'         -- does not, so every cuOpt-won enactment recorded an action with no name.\n'
                || E'         -- verb_by says the kernel supplied the word, not the proposer.\n'
                || E'         || CASE\n'
                || E'              WHEN p_action_context = ''stall_assignment''\n'
                || E'                   AND NOT (p.proposal ? ''verb'')\n'
                || E'                   AND NOT COALESCE((p.proposal->>''abstain'')::boolean, false)\n'
                || E'                THEN jsonb_build_object(''verb'',''assign_stall'',''verb_by'',''kernel_default'')\n'
                || E'              ELSE ''{}''::jsonb\n'
                || E'            END\n';
BEGIN
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_l2_external_proposal';
  v_src := pg_get_functiondef(v_oid);

  IF md5(v_src) <> 'f2cbd18b9b592e2abecd4c7e186cf9b9' THEN
    RAISE EXCEPTION '0091 abort: l2_external_proposal drifted from the pinned pre-image (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a1_old, ''))) / length(v_a1_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0091 abort: source-CASE anchor found % times, expected 1', v_cnt;
  END IF;

  v_new := replace(v_src, v_a1_old, v_a1_new);
  EXECUTE v_new;

  v_src := pg_get_functiondef(v_oid);
  IF position('verb_by' in v_src) = 0 THEN
    RAISE EXCEPTION '0091 abort: patched funnel does not carry the verb normalization';
  END IF;

  RAISE NOTICE '0091 applied: the kernel defends the verb at the proposal funnel.';
END
$do$;
