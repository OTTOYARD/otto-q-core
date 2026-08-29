-- migration-version: 20260829200000
-- migration-name:    cuopt_enactments_carry_their_verb
-- 0090 -- written against R5's second writer; SUPERSEDED IN PURPOSE BY 0091, kept because it
-- was applied (and registered) before the truth surfaced. Read 0091 for the real story.
--
-- WHAT THIS WAS MEANT TO FIX: the first post-v17 run (d5a8b7e8, seed 777012) surfaced verbless
-- enacted decisions, action_context='stall_assignment', source='cuopt'. This migration patched
-- public.ottoq_enact_cuopt_batch -- whose decision INSERT writes the raw proposal jsonb with no
-- verb -- to stamp 'verb':'begin_charge' into enacted_action.
--
-- WHAT TURNED OUT TO BE TRUE (established minutes after applying, while the verbless count kept
-- growing): ottoq_enact_cuopt_batch has ZERO callers in pg_proc, and its INSERT names columns
-- that do not exist in ottoq_decisions (proposal_latency_ms, enactment_latency_ms) -- it would
-- raise 42703 if anything ever called it. It is dead AND broken; it never wrote those rows. The
-- real writer is the decide path's deferral enactment, fixed properly in 0091 at the proposal
-- funnel. This patch is harmless -- the dead function is now merely more correct -- and the
-- broken column list plus the disposal question (quarantine vs drop) are left for a deliberate
-- decision, not a drive-by.
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   public.ottoq_enact_cuopt_batch   6c5969d0c3935015f4a5643e13806ff6

DO $do$
DECLARE
  v_oid oid; v_src text; v_new text; v_cnt int;

  v_a1_old text := E'      v_proposal.proposal, v_proposal.proposal, v_proposal.proposal,';
  v_a1_new text := E'      v_proposal.proposal,\n'
                || E'      -- 0090: the enacted row names its action. The command emitted below is\n'
                || E'      -- ''begin_charge''; the proposal jsonb stays the proposer''s untouched words.\n'
                || E'      v_proposal.proposal || jsonb_build_object(''verb'',''begin_charge''),\n'
                || E'      v_proposal.proposal,';
BEGIN
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_enact_cuopt_batch';
  v_src := pg_get_functiondef(v_oid);

  IF md5(v_src) <> '6c5969d0c3935015f4a5643e13806ff6' THEN
    RAISE EXCEPTION '0090 abort: enact_cuopt_batch drifted from the pinned pre-image (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a1_old, ''))) / length(v_a1_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0090 abort: decision-insert anchor found % times, expected 1', v_cnt;
  END IF;

  v_new := replace(v_src, v_a1_old, v_a1_new);
  EXECUTE v_new;

  v_src := pg_get_functiondef(v_oid);
  IF position('''verb'',''begin_charge''' in v_src) = 0 THEN
    RAISE EXCEPTION '0090 abort: patched enactor does not carry the verb';
  END IF;

  RAISE NOTICE '0090 applied: cuOpt enactments carry their verb.';
END
$do$;
