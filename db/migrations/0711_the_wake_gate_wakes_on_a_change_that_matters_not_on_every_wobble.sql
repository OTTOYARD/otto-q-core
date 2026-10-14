-- migration-version: 20261013180804
-- migration-name:    the_wake_gate_wakes_on_a_change_that_matters_not_on_every_wobble
--
-- 0711  **The wake gate wakes on a change that matters, not on every wobble.** 0705's gate woke the agent whenever a
--        count it watches moved by one. On a busy day those counts move by one on almost every beat, so the gate that was
--        built to make the agent sparse would have consulted it on 66 passes in 79 (this file: 25). It now wakes on an onset or a
--        material jump, and a critical scout finding always wakes it. Still shadow by default (agent_wake_enabled = 0).
--        (Measured 2026-10-13 on run 176b2912, replayed from the evidence 0703 keeps; db/checks/0440 §5.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 176b2912 (busy_day, seed 305838298283560562, twin depot, agent v29 on edge v41, gate in shadow; 755 ticks,
--   ended 16:22 UTC) kept 79 agent passes as evidence, and 79 decision rows and 79 Nemotron ledger rows agree with them.
--   The depot sat in contention the whole day: a mean of 53 cars in the charge line, about 0 chargers open, and 46 cars
--   past their 30-minute contract wait. Under that load the counts the gate watches wobble:
--
--     cars past the contract wait   50, 52, 51, 52, 54, 55, 54 ...   (0705 wakes on every +1)
--     faulted chargers              2, 3, 2, 3, 4, 3 ...             (0705 wakes on every flip either way)
--     scout findings (cumulative)   4 → 93, one stranded car at a time (0705 wakes on every new one)
--
--   Replayed in order over the 79 recorded fingerprints (the reference moves only on a woken pass that the model
--   answered, as the live gate's does), 0705's rules wake 66. The shadow record says 75 because overlapping passes read
--   an older reference (DC-6; 0710 fixed the race, not the overlap). This file's rules wake 25 (9 heartbeat, 9 charger,
--   7 stranded-car scout, 5 contract wait, 1 emergency, 1 first consult; a pass can have several; the critical count
--   was 4 legacy-task findings from the first tick to the last, so it never woke the agent).
--
--   WHAT THAT COSTS, measured, not assumed. The agent's order differed from the kernel's on 12 passes: 1 was taken, 11
--   were refused. The hindsight grader (0621) scored them: the taken one right_take, 5 of the refused missed_win, 6
--   right_refusal -- so the agent's differing orders won 6 times in 12, and the check's p_win does not separate them
--   (mean 0.37 on the missed wins, 0.43 on the right refusals; G389's finding again). This gate keeps 6 of the 12 and
--   skips the one that was taken. On one run, whether a consult helps is a coin flip that nothing on the board
--   predicts; a consult costs about 25,800 prompt and 1,400 completion tokens and 65 s. 25 wakes instead of 79 passes
--   is about 1.4 million tokens a run. That is the trade, and it is why the gate stays a person's switch.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_agent_wake, by SUBSTITUTION on the live definition (md5 9244b8c2 after 0710; each anchor asserted to
--   occur exactly once):
--
--     a. the fingerprint gains scout_critical (departed_below_target + legacy_task_residue) and scout_stranded
--        (stranded_open_must_do); scout_actionable stays, as their sum, so older fingerprints still compare.
--     b. charger_fault / charger_restored: when the faulted count moved by >= agent_wake_charger_delta (2) since the
--        last answered consult, not by one.
--     c. contract_wait and scout_finding (stranded): on ONSET (0 to more) or a JUMP of at least
--        max(agent_wake_jump_min, ceil(agent_wake_jump_pct% of the last count)) -- 5 and 20 by default.
--     d. scout_critical: ANY new critical finding wakes. A car that left below its target is rule 9's case and is never
--        averaged away. A fingerprint from before this file has no scout_critical and reads as 0, so the first pass
--        after it wakes once if any exist: the gate fails toward waking.
--     e. the result carries the thresholds it used (`hysteresis`).
--
--   Unchanged: first_consult, the heartbeat, contention onset/relief, emergency, dr_change, the shadow default, totality.
--   Three catalog rows (agent_wake_jump_min, agent_wake_jump_pct, agent_wake_charger_delta), none agent-writable.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   Called only by the agent's edge function, which is quiesced in certification arms. No atom hashes its output.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the ottoq_agent_wake definition snapshotted under label '0711_pre'. The three catalog rows are inert
--   without this file's function and may stay.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0711 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE v_md5 text := md5(pg_get_functiondef('public.ottoq_agent_wake(uuid)'::regprocedure));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0710_the_wake_gate_reads_the_record_the_claim_reads') THEN
    RAISE EXCEPTION '0711 P1: 0710 is not classified; apply in order';
  END IF;
  IF v_md5 IS DISTINCT FROM '9244b8c23967bf8dd9e0af4aa9b18602' THEN
    RAISE EXCEPTION '0711 P1: ottoq_agent_wake is not the definition this file was written against (md5 %)', v_md5;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
              WHERE param_key IN ('agent_wake_jump_min', 'agent_wake_jump_pct', 'agent_wake_charger_delta')) THEN
    RAISE EXCEPTION '0711 P1: a wake hysteresis dial already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0711_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_wake';

INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('agent_wake_jump_min',
        '0711: the wake gate wakes the agent when the cars past their contract wait, or the stranded cars the scouts '
        'found, rise by at least this many (or by agent_wake_jump_pct, whichever is more) since its last answered '
        'consult, or rise from none. Set by a person, never by an agent (rule 10).',
        5, 1, 50, 'ottoq_agent_wake (0711)', false),
       ('agent_wake_jump_pct',
        '0711: the relative half of the wake gate''s jump test, in percent of the count at the last answered consult.',
        20, 0, 100, 'ottoq_agent_wake (0711)', false),
       ('agent_wake_charger_delta',
        '0711: the wake gate wakes the agent when the faulted-charger count has moved by at least this many since its '
        'last answered consult (a single charger flapping on a busy day does not).',
        2, 1, 10, 'ottoq_agent_wake (0711)', false);

DO $wake$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_wake(uuid)'::regprocedure);
  --: a. the declarations
  v_old_decl constant text := E'  v_min_ago  numeric;\n';
  v_new_decl constant text := E'  v_min_ago  numeric;\n'
    || E'  v_crit     bigint; v_strand bigint;                  --: 0711\n'
    || E'  v_jmin     numeric; v_jpct numeric; v_cdelta numeric; v_prev_strand numeric; --: 0711\n';
  --: a. the scout count, split
  v_old_scout constant text :=
       E'  SELECT count(*) INTO v_found FROM public.ottoq_vehicle_scout_findings f\n'
    || E'   WHERE f.sim_run_id = p_sim_run_id\n'
    || E'     AND f.scout IN (''stranded_open_must_do'', ''departed_below_target'', ''legacy_task_residue'');\n';
  v_new_scout constant text :=
       E'  --: 0711: a critical finding (a car left below its target; legacy work that holds one) is counted apart from\n'
    || E'  --: stranded cars, so one critical finding always wakes while stranded cars wake on onset or a jump.\n'
    || E'  SELECT count(*), count(*) FILTER (WHERE f.scout IN (''departed_below_target'', ''legacy_task_residue'')),\n'
    || E'         count(*) FILTER (WHERE f.scout = ''stranded_open_must_do'')\n'
    || E'    INTO v_found, v_crit, v_strand FROM public.ottoq_vehicle_scout_findings f\n'
    || E'   WHERE f.sim_run_id = p_sim_run_id\n'
    || E'     AND f.scout IN (''stranded_open_must_do'', ''departed_below_target'', ''legacy_task_residue'');\n'
    || E'  v_jmin   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, ''agent_wake_jump_min'', 5), 5), 1);\n'
    || E'  v_jpct   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, ''agent_wake_jump_pct'', 20), 20), 0);\n'
    || E'  v_cdelta := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, ''agent_wake_charger_delta'', 2), 2), 1);\n';
  v_old_fp constant text := E'''dr_active'', v_dr, ''scout_actionable'', v_found);';
  v_new_fp constant text := E'''dr_active'', v_dr, ''scout_actionable'', v_found,\n'
    || E'                             ''scout_critical'', v_crit, ''scout_stranded'', v_strand);';
  --: b-d. the reasons
  v_old_rs constant text :=
       E'    IF v_faulted > COALESCE((v_prev ->> ''faulted_chargers'')::int, 0) THEN v_reasons := array_append(v_reasons, ''charger_fault''::text);\n'
    || E'    ELSIF v_faulted < COALESCE((v_prev ->> ''faulted_chargers'')::int, 0) THEN v_reasons := array_append(v_reasons, ''charger_restored''::text);\n'
    || E'    END IF;\n'
    || E'    IF v_emerg > COALESCE((v_prev ->> ''emergencies'')::int, 0) THEN v_reasons := array_append(v_reasons, ''emergency''::text); END IF;\n'
    || E'    IF v_over > COALESCE((v_prev ->> ''over_contract_wait'')::int, 0) THEN v_reasons := array_append(v_reasons, ''contract_wait''::text); END IF;\n'
    || E'    IF (v_prev ->> ''dr_active'') IS DISTINCT FROM (v_fp ->> ''dr_active'') THEN v_reasons := array_append(v_reasons, ''dr_change''::text); END IF;\n'
    || E'    IF v_found > COALESCE((v_prev ->> ''scout_actionable'')::bigint, 0) THEN v_reasons := array_append(v_reasons, ''scout_finding''::text); END IF;\n';
  v_new_rs constant text :=
       E'    --: 0711: hysteresis. On a busy day these counts move by one on almost every beat (run 176b2912: 0705''s rules\n'
    || E'    --: woke 66 of 79 replayed passes); wake on an onset or a material jump since the last answered consult.\n'
    || E'    IF abs(v_faulted - COALESCE((v_prev ->> ''faulted_chargers'')::int, 0)) >= v_cdelta THEN\n'
    || E'      v_reasons := array_append(v_reasons, CASE WHEN v_faulted > COALESCE((v_prev ->> ''faulted_chargers'')::int, 0)\n'
    || E'                                                THEN ''charger_fault'' ELSE ''charger_restored'' END::text);\n'
    || E'    END IF;\n'
    || E'    IF v_emerg > COALESCE((v_prev ->> ''emergencies'')::int, 0) THEN v_reasons := array_append(v_reasons, ''emergency''::text); END IF;\n'
    || E'    IF (COALESCE((v_prev ->> ''over_contract_wait'')::numeric, 0) = 0 AND v_over > 0)\n'
    || E'       OR v_over >= COALESCE((v_prev ->> ''over_contract_wait'')::numeric, 0)\n'
    || E'                    + GREATEST(v_jmin, ceil(COALESCE((v_prev ->> ''over_contract_wait'')::numeric, 0) * v_jpct / 100.0)) THEN\n'
    || E'      v_reasons := array_append(v_reasons, ''contract_wait''::text);\n'
    || E'    END IF;\n'
    || E'    IF (v_prev ->> ''dr_active'') IS DISTINCT FROM (v_fp ->> ''dr_active'') THEN v_reasons := array_append(v_reasons, ''dr_change''::text); END IF;\n'
    || E'    IF v_crit > COALESCE((v_prev ->> ''scout_critical'')::bigint, 0) THEN\n'
    || E'      v_reasons := array_append(v_reasons, ''scout_critical''::text);\n'
    || E'    END IF;\n'
    || E'    --: a fingerprint from before 0711 has only the sum; it stands in for the stranded count (an over-count, so\n'
    || E'    --: the first comparison after 0711 errs toward not re-waking for findings the agent was already shown)\n'
    || E'    v_prev_strand := COALESCE((v_prev ->> ''scout_stranded'')::numeric, (v_prev ->> ''scout_actionable'')::numeric, 0);\n'
    || E'    IF (v_prev_strand = 0 AND v_strand > 0)\n'
    || E'       OR v_strand >= v_prev_strand + GREATEST(v_jmin, ceil(v_prev_strand * v_jpct / 100.0)) THEN\n'
    || E'      v_reasons := array_append(v_reasons, ''scout_finding''::text);\n'
    || E'    END IF;\n';
  v_old_hb constant text := E'''heartbeat_sim_min'', v_hb_min,\n';
  v_new_hb constant text := E'''heartbeat_sim_min'', v_hb_min,\n'
    || E'    ''hysteresis'', jsonb_build_object(''jump_min'', v_jmin, ''jump_pct'', v_jpct, ''charger_delta'', v_cdelta),\n';
  v_pairs text[][] := ARRAY[[v_old_decl, v_new_decl], [v_old_scout, v_new_scout], [v_old_fp, v_new_fp],
                            [v_old_rs, v_new_rs], [v_old_hb, v_new_hb]];
  v_n int;
BEGIN
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0711: anchor % occurs % times in ottoq_agent_wake, expected exactly 1', i, v_n;
    END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $wake$;

DO $v$
DECLARE v_def text := pg_get_functiondef('public.ottoq_agent_wake(uuid)'::regprocedure);
        v_r jsonb;
BEGIN
  --: V1 the new rules are in the function and the old +1 rules are gone
  IF strpos(v_def, '>= v_cdelta') = 0 OR strpos(v_def, '''scout_critical''::text') = 0
     OR strpos(v_def, 'IF v_over > COALESCE((v_prev ->> ''over_contract_wait'')::int, 0) THEN') > 0 THEN
    RAISE EXCEPTION '0711 V1 FAILED: the wake rules are not as written';
  END IF;
  --: V2 an unknown run still wakes cleanly, and the gate stays shadow by default
  v_r := public.ottoq_agent_wake('00000000-0000-0000-0000-0000000000ff');
  IF NOT COALESCE((v_r ->> 'wake')::boolean, false) OR v_r ? 'error' THEN
    RAISE EXCEPTION '0711 V2 FAILED: an unknown run did not wake cleanly: %', v_r;
  END IF;
  IF (SELECT default_value FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_wake_enabled') <> 0
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                 WHERE param_key IN ('agent_wake_jump_min', 'agent_wake_jump_pct', 'agent_wake_charger_delta')
                   AND agent_writable) THEN
    RAISE EXCEPTION '0711 V2 FAILED: the wake dials are not as written';
  END IF;
  --: V3 grants unchanged by the replace
  IF has_function_privilege('anon', 'public.ottoq_agent_wake(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_agent_wake(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_agent_wake(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0711 V3 FAILED: grants changed';
  END IF;
  RAISE NOTICE '0711 V1-V3 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0711_the_wake_gate_wakes_on_a_change_that_matters_not_on_every_wobble', false, false,
  'Measured 2026-10-13 on run 176b2912 (db/checks/0440): 0705''s wake rules would consult the agent on 66 of 79 '
  'replayed passes; 0711 wakes on onset or a jump (25 of 79) and always on a critical scout finding. Still shadow by '
  'default. Called only by the agent edge function, quiesced in certification arms: FALSE/FALSE.',
  now());

COMMIT;
