-- migration-version: 20261013180020
-- migration-name:    the_wake_gate_reads_the_record_the_claim_reads
--
-- 0710  **The wake gate reads the record the claim reads.** ottoq_agent_wake (0705) found the agent's last answered
--        consult in ottoq_agent_pass_evidence, but ottoq_agent_chain_claim decides a pass is DONE from its decision
--        row, and edge v29 writes the decision first and the evidence a moment later. A pass claimed inside that gap
--        saw no previous answer and woke as first_consult. (Found 2026-10-13 on run 176b2912; db/checks/0440 §4.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 176b2912 (busy_day, twin depot, agent v29 on edge v41, wake gate in shadow), measured 15:21 UTC read-only:
--   pass 5's decision row was written at 15:18:23.95 and its evidence row at 15:18:29.53 (5.6 s later; the first pass
--   also wrote the prompt row). Pass 6 was claimed at tick 3 inside that gap -- the claim saw pass 5's decision and let
--   it in -- and its wake test found no answered consult in the evidence table, so it reported reasons [first_consult].
--   In shadow that only mislabels a reason; with the gate on it would be a model call the gate exists to save. Passes
--   7 and 8 read pass 5 and pass 6 correctly, because their wake ran after both rows existed.
--
--   The fix is to read the same record the claim reads. Since v29 every agent decision row carries the wake verdict
--   (context_frame.wake, fingerprint included) and its source (enacted_action.source: 'nemotron' when the model
--   answered, 'deterministic_fallback' when it did not, 'kernel_regime' on a solver-only pass).
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   In public.ottoq_agent_wake, the "last answered consult" is read first from ottoq_decisions (the run's newest
--   orchestrator_agent row with source 'nemotron' and a wake block, walking the (sim_run_id, tick_seq) index back from
--   the newest tick), and only when there is none from ottoq_agent_pass_evidence as before (a run whose engine rows
--   were purged). last_consult gains `from` ('decision' or 'evidence'). By SUBSTITUTION on the live definition; the
--   anchor is asserted to occur exactly once. Nothing else changes.
--
--   NOT changed, and named so nobody reads it as fixed: passes OVERLAP. ottoq_agent_chain_claim lets a new pass in
--   when the previous claim is older than agent_chain_inflight_timeout_s (45 s by default, catalog max 120), and a
--   consulted pass takes 55-70 s (passes 6-8 above), so on this run pass 7 was claimed while pass 6 was still running.
--   That is the study's DC-6 (an order chosen by arrival, not by when it was computed), older than this file.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   Called only by the agent's edge function, quiesced in certification arms; reads one more table.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the ottoq_agent_wake definition snapshotted under label '0710_pre' in ottoq_schema_snapshots.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0710 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE v_md5 text := md5(pg_get_functiondef('public.ottoq_agent_wake(uuid)'::regprocedure));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0705_the_agent_is_consulted_when_something_changes_not_on_every_beat') THEN
    RAISE EXCEPTION '0710 P1: 0705 is not classified; apply in order';
  END IF;
  IF v_md5 IS DISTINCT FROM 'd6c8ab8698e633fd1fa653491afc4e07' THEN
    RAISE EXCEPTION '0710 P1: ottoq_agent_wake is not the definition this file was written against (md5 %)', v_md5;
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0710_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_wake';

DO $wake$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_wake(uuid)'::regprocedure);
  v_old_select constant text :=
       E'  --: the last pass that consulted the model AND got an answer; a fallback or failed pass does not reset the clock\n'
    || E'  SELECT e.pass_id, e.recorded_tick, e.sim_clock, e.wake -> ''fingerprint'' AS fp,\n'
    || E'         e.answer -> ''solver'' ->> ''objective'' AS objective\n'
    || E'    INTO v_last\n'
    || E'    FROM public.ottoq_agent_pass_evidence e\n'
    || E'   WHERE e.sim_run_id = p_sim_run_id AND e.consulted AND e.outcome_class NOT IN (''fallback'', ''failed'')\n'
    || E'   ORDER BY e.pass_id DESC LIMIT 1;\n';
  v_new_select constant text :=
       E'  --: the last pass that consulted the model AND got an answer; a fallback or failed pass does not reset the clock.\n'
    || E'  --: 0710: read first from the DECISION row, the record ottoq_agent_chain_claim reads to decide a pass is done; edge\n'
    || E'  --: v29 writes the evidence row a moment later, and a pass claimed in that gap used to wake as first_consult.\n'
    || E'  SELECT d.decision_seq AS pass_id, d.tick_seq AS recorded_tick, d.sim_clock,\n'
    || E'         d.context_frame -> ''wake'' -> ''fingerprint'' AS fp,\n'
    || E'         d.proposed_action -> ''solver'' ->> ''objective'' AS objective, ''decision''::text AS src\n'
    || E'    INTO v_last\n'
    || E'    FROM public.ottoq_decisions d\n'
    || E'   WHERE d.sim_run_id = p_sim_run_id AND d.resolved_action_context = ''orchestrator_agent''\n'
    || E'     AND d.enacted_action ->> ''source'' = ''nemotron'' AND d.context_frame ? ''wake''\n'
    || E'   ORDER BY d.tick_seq DESC, d.decision_seq DESC LIMIT 1;\n'
    || E'  IF v_last.pass_id IS NULL THEN\n'
    || E'    SELECT e.pass_id, e.recorded_tick, e.sim_clock, e.wake -> ''fingerprint'' AS fp,\n'
    || E'           e.answer -> ''solver'' ->> ''objective'' AS objective, ''evidence''::text AS src\n'
    || E'      INTO v_last\n'
    || E'      FROM public.ottoq_agent_pass_evidence e\n'
    || E'     WHERE e.sim_run_id = p_sim_run_id AND e.consulted AND e.outcome_class NOT IN (''fallback'', ''failed'')\n'
    || E'     ORDER BY e.pass_id DESC LIMIT 1;\n'
    || E'  END IF;\n';
  v_old_lc constant text := E'jsonb_build_object(''pass_id'', v_last.pass_id, ''tick'', v_last.recorded_tick,';
  v_new_lc constant text := E'jsonb_build_object(''from'', v_last.src, ''pass_id'', v_last.pass_id, ''tick'', v_last.recorded_tick,';
  v_n int; v_m int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, v_old_select, ''))) / length(v_old_select);
  v_m := (length(v_def) - length(replace(v_def, v_old_lc, ''))) / length(v_old_lc);
  IF v_n <> 1 OR v_m <> 1 THEN
    RAISE EXCEPTION '0710: anchors found % and % times in ottoq_agent_wake, expected exactly 1 each', v_n, v_m;
  END IF;
  EXECUTE replace(replace(v_def, v_old_select, v_new_select), v_old_lc, v_new_lc);
END $wake$;

DO $v$
DECLARE v_def text := pg_get_functiondef('public.ottoq_agent_wake(uuid)'::regprocedure);
        v_r jsonb;
BEGIN
  IF strpos(v_def, 'FROM public.ottoq_decisions d') = 0 OR strpos(v_def, '''from'', v_last.src') = 0 THEN
    RAISE EXCEPTION '0710 V1 FAILED: the wake gate does not read the decision row';
  END IF;
  v_r := public.ottoq_agent_wake('00000000-0000-0000-0000-0000000000ff');
  IF NOT COALESCE((v_r ->> 'wake')::boolean, false) OR v_r ? 'error' THEN
    RAISE EXCEPTION '0710 V2 FAILED: an unknown run did not wake cleanly: %', v_r;
  END IF;
  RAISE NOTICE '0710 V1-V2 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0710_the_wake_gate_reads_the_record_the_claim_reads', false, false,
  'Found 2026-10-13 on run 176b2912 (db/checks/0440): ottoq_agent_wake reads the last answered consult from the decision '
  'row the claim reads, before the evidence row written after it. Called only by the agent edge function, quiesced in '
  'certification arms: FALSE/FALSE.',
  now());

COMMIT;
