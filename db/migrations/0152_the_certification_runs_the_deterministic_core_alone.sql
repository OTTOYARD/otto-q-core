-- =====================================================================
-- 0152  The certification runs the deterministic core alone
-- =====================================================================
-- Chase, 7:45 PM CT Sep 1: "disable whatever you need. Keep moving
-- forward with our deterministic layer alone."
--
-- WHAT WAS FOUND. The determinism pair harness never quiesced the cuOpt
-- proposer. Measured on round 6's first twelve arms (7:05-7:50 PM CT):
--   - ottoq_policy_get(arm, 'cuopt_propose_enabled', 1) resolved 1 on
--     every arm; zero run-scoped policy rows existed for any arm.
--   - per arm: 1 sql_gate post to the ottoq-cuopt-propose edge function,
--     11 'debounce' refusals, 5-7 'first_refusal_arm' arms, 1 edge
--     'no_candidates_in_instance' (0 proposals out, latency up to 10.4 s).
--   - 692 deferral rows across the 12 arms (57-58 per arm) - each one a
--     vehicle held out of the greedy stall cursor for exactly one tick by
--     ottoq_cuopt_defer_hold, which is TRUE whenever the proposer is
--     enabled and a row is 'spent' at that tick.
-- So the thing being certified was "deterministic core + a proposer's
-- hold machinery", not the deterministic core.
--
-- WHY IT PASSED ANYWAY. ottoq_cuopt_refresh's debounce compares
-- fire_log.fired_at to now() - 3 s. now() is frozen for the life of a
-- transaction, and the pair runs both arms in one transaction, so every
-- call after the first is debounced identically on both arms. The
-- pg_net post cannot transmit until commit, so the edge function sees
-- no run and abstains. Determinism held by an accident of transaction
-- shape, not by design - a per-tick production transaction has neither
-- property. That is exactly the 0056 finding (33 invocations each,
-- 50 vs 47 holds, assignment order shifted), which quiesced the OLD
-- harness (ottoq_cert_arm_start, run_by='benchmark') and never reached
-- this one (ottoq_determinism_pair, run_by='cert_harness').
--
-- Production already quiesces per run: ottoq_production_start writes
-- cuopt_propose_enabled=0 for its run (row dated 2026-08-30 05:06 UTC).
-- Demo runs and cert arms did not. This migration makes "deterministic
-- core alone" the default everywhere, and pins it inside every cert arm.
--
-- TWO CHANGES
--  (A) Global policy tier: cuopt_propose_enabled = 0 and
--      cuopt_first_refusal_max_defers = 0. ottoq_policy_get resolves
--      run -> depot -> global -> literal default, so every run without
--      an explicit run/depot override now runs the deterministic core
--      alone. Readers: ottoq_cuopt_refresh (logs 'policy_disabled' -
--      the refusal stays countable, per the standing cuOpt rule),
--      ottoq_cuopt_defer_hold (fails open: never holds), ottoq_cron_tick
--      (no orchestrate-tick edge post), ottoq_cuopt_first_refusal_arm
--      (cap 0: returns before writing a row). The agentic layer returns
--      by writing a run-scoped 1 - one row, no code.
--  (B) ottoq_determinism_pair pins BOTH keys to 0 on each arm it starts,
--      run-scoped, so a later global re-enable cannot reach inside a
--      certification. Mirrors what 0056 did in ottoq_cert_arm_start.
--
-- Forces re-certification: the canon WILL move - roughly 57 held
-- vehicle-ticks per 12-tick arm now enter the cursor a tick earlier.
-- Round 7 establishes the deterministic-only canon. Round 6's green is
-- re-earned there, on the engine the claim is actually about.
--
-- ottoq_l2_optimize_assignments' 'greedy_constrained' proposals and the
-- 'ottoq_service_priority' proposals are the engine's own deterministic
-- proposers and are untouched.
-- =====================================================================

-- 1. Pin: refuse to edit a harness other than the one audited.
DO $pin$
DECLARE v_pin text; v_n int;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)), count(*) OVER () INTO v_pin, v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_n <> 1 THEN RAISE EXCEPTION '0152 expected 1 arity of ottoq_determinism_pair, found %', v_n; END IF;
  IF v_pin IS DISTINCT FROM '3345bee36fa701d05adfd6112026091c' THEN
    RAISE EXCEPTION '0152 pin mismatch ottoq_determinism_pair: %', v_pin;
  END IF;
END $pin$;

-- 2. The anchor appears exactly once, raw and comment-stripped.
DO $anchor$
DECLARE
  v_raw text; v_src text; v_nr int; v_ns int;
  v_anchor text := $a$v_run := twin.ottoq_sim_start_run(p_scenario, p_sim_start, 60, p_seed, 'cert_harness');$a$;
BEGIN
  SELECT pg_get_functiondef(p.oid),
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g')
    INTO v_raw, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  v_nr := (length(v_raw) - length(replace(v_raw, v_anchor, ''))) / length(v_anchor);
  v_ns := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_nr <> 1 OR v_ns <> 1 THEN
    RAISE EXCEPTION '0152 arm-start anchor: raw=% stripped=% (need 1/1)', v_nr, v_ns;
  END IF;
  IF position('0152_cert_quiesce' in v_raw) > 0 THEN
    RAISE EXCEPTION '0152 already applied to ottoq_determinism_pair';
  END IF;
END $anchor$;

-- 3. Proof of the pre-state, against the most recent certification arm.
--    This CAN fail: if the proposer were already quiesced for cert arms,
--    or the global tier already carried these keys, the premise of this
--    migration would be false and it must not run.
DO $proof$
DECLARE
  v_run uuid; v_enabled numeric; v_cap numeric; v_posts int; v_arms int; v_defer int; v_rows int;
BEGIN
  SELECT r.sim_run_id INTO v_run
    FROM public.ottoq_sim_runs r
   WHERE r.run_by='cert_harness' AND r.status='completed'
   ORDER BY r.started_at DESC, r.sim_run_id DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION '0152 proof: no completed cert_harness arm to measure'; END IF;

  v_enabled := public.ottoq_policy_get(v_run, 'cuopt_propose_enabled', 1);
  v_cap     := public.ottoq_policy_get(v_run, 'cuopt_first_refusal_max_defers', 1);
  SELECT count(*) INTO v_rows FROM public.ottoq_policy_params
   WHERE scope_type='run' AND scope_id=v_run AND param_key IN ('cuopt_propose_enabled','cuopt_first_refusal_max_defers');
  SELECT count(*) FILTER (WHERE stage='sql_gate' AND abstained_reason IS NULL),
         count(*) FILTER (WHERE abstained_reason='first_refusal_arm')
    INTO v_posts, v_arms
    FROM public.cuopt_invocation_log WHERE sim_run_id=v_run;
  SELECT count(*) INTO v_defer FROM public.ottoq_cuopt_deferrals WHERE sim_run_id=v_run;

  IF v_enabled <> 1 OR v_cap <> 1 OR v_rows <> 0 THEN
    RAISE EXCEPTION '0152 proof: latest cert arm % already quiesced (enabled=%, cap=%, run rows=%)', v_run, v_enabled, v_cap, v_rows;
  END IF;
  IF v_posts < 1 OR v_arms < 1 OR v_defer < 1 THEN
    RAISE EXCEPTION '0152 proof: latest cert arm % shows no proposer activity (posts=%, arms=%, deferral rows=%) - premise false', v_run, v_posts, v_arms, v_defer;
  END IF;

  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params
              WHERE scope_type='global' AND param_key IN ('cuopt_propose_enabled','cuopt_first_refusal_max_defers')) THEN
    RAISE EXCEPTION '0152 proof: a global row for one of the two keys already exists';
  END IF;
  IF (SELECT default_value FROM public.ottoq_policy_param_catalog WHERE param_key='cuopt_propose_enabled') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION '0152 proof: catalog default for cuopt_propose_enabled is not 1';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key='cuopt_first_refusal_max_defers') THEN
    RAISE EXCEPTION '0152 proof: cuopt_first_refusal_max_defers is already catalogued';
  END IF;

  RAISE NOTICE '0152 pre-state on arm %: enabled=% cap=% posts=% first_refusal_arms=% deferral_rows=%',
               v_run, v_enabled, v_cap, v_posts, v_arms, v_defer;
END $proof$;

-- 4. (A) Global tier: the deterministic core alone is the default.
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('global', '00000000-0000-0000-0000-000000000000'::uuid, 'cuopt_propose_enabled',          0, '0152_deterministic_only', now()),
       ('global', '00000000-0000-0000-0000-000000000000'::uuid, 'cuopt_first_refusal_max_defers', 0, '0152_deterministic_only', now())
ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
   SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by, updated_at = EXCLUDED.updated_at;

UPDATE public.ottoq_policy_param_catalog
   SET default_value = 0,
       description = description || ' 0152: global tier is 0 - the deterministic core runs alone. Re-enable per run with a run-scoped 1.'
 WHERE param_key = 'cuopt_propose_enabled';

INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects)
VALUES ('cuopt_first_refusal_max_defers',
        'Max one-tick right-of-first-refusal holds per vehicle per run while a cuOpt solve is in flight. 0 disables the hold ledger entirely (no rows written). 0152: global tier is 0.',
        0, 0, 10, 'ottoq_cuopt_first_refusal_arm; ottoq_cuopt_defer_hold via ottoq_decide_tick')
ON CONFLICT (param_key) DO NOTHING;

-- 5. (B) The harness pins both keys on every arm it starts.
DO $edit$
DECLARE
  v_def text;
  v_anchor text := $a$v_run := twin.ottoq_sim_start_run(p_scenario, p_sim_start, 60, p_seed, 'cert_harness');$a$;
  v_repl text := $a$v_run := twin.ottoq_sim_start_run(p_scenario, p_sim_start, 60, p_seed, 'cert_harness');
    /* 0152: a certification arm runs the deterministic core alone. Run-scoped, so a
       later global re-enable of the proposer cannot reach inside a cert (0056). */
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_run, 'cuopt_propose_enabled', 0, '0152_cert_quiesce'),
           ('run', v_run, 'cuopt_first_refusal_max_defers', 0, '0152_cert_quiesce')
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = 0, updated_by = '0152_cert_quiesce';$a$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF position(v_anchor in v_def) = 0 THEN
    RAISE EXCEPTION '0152 anchor absent from pg_get_functiondef output';
  END IF;
  EXECUTE replace(v_def, v_anchor, v_repl);
END $edit$;

-- 6. Post-checks.
DO $post$
DECLARE
  v_pin text; v_n int; v_src text; v_run uuid; v_k1 int; v_k2 int;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)), count(*) OVER (), p.prosrc INTO v_pin, v_n, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_n <> 1 THEN RAISE EXCEPTION '0152 arity changed to %', v_n; END IF;
  IF v_pin = '3345bee36fa701d05adfd6112026091c' THEN RAISE EXCEPTION '0152 body did not change'; END IF;

  -- each pinned key exactly once in the arm-start block; the marker itself 3 times (two VALUES rows + DO UPDATE)
  v_k1 := (length(v_src) - length(replace(v_src, $a$('run', v_run, 'cuopt_propose_enabled', 0, '0152_cert_quiesce')$a$, '')))
          / length($a$('run', v_run, 'cuopt_propose_enabled', 0, '0152_cert_quiesce')$a$);
  v_k2 := (length(v_src) - length(replace(v_src, $a$('run', v_run, 'cuopt_first_refusal_max_defers', 0, '0152_cert_quiesce')$a$, '')))
          / length($a$('run', v_run, 'cuopt_first_refusal_max_defers', 0, '0152_cert_quiesce')$a$);
  IF v_k1 <> 1 OR v_k2 <> 1 THEN RAISE EXCEPTION '0152 pinned keys present %/% times (need 1/1)', v_k1, v_k2; END IF;
  IF (length(v_src) - length(replace(v_src, '0152_cert_quiesce', ''))) / length('0152_cert_quiesce') <> 3 THEN
    RAISE EXCEPTION '0152 marker count is not 3';
  END IF;

  -- the global tier now answers 0 for a run with no override, and for the NULL run ottoq_cron_tick reads
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.run_by='cert_harness' AND r.status='completed' ORDER BY r.started_at DESC, r.sim_run_id DESC LIMIT 1;
  IF public.ottoq_policy_get(v_run, 'cuopt_propose_enabled', 1) <> 0
     OR public.ottoq_policy_get(v_run, 'cuopt_first_refusal_max_defers', 1) <> 0 THEN
    RAISE EXCEPTION '0152 global tier did not take effect for run %', v_run;
  END IF;
  IF public.ottoq_policy_get(NULL, 'cuopt_propose_enabled', 1) <> 0 THEN
    RAISE EXCEPTION '0152 global tier did not take effect for the NULL run (ottoq_cron_tick path)';
  END IF;
  IF (SELECT default_value FROM public.ottoq_policy_param_catalog WHERE param_key='cuopt_propose_enabled') <> 0 THEN
    RAISE EXCEPTION '0152 catalog default not updated';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key='cuopt_first_refusal_max_defers') THEN
    RAISE EXCEPTION '0152 catalog row for cuopt_first_refusal_max_defers missing';
  END IF;

  RAISE NOTICE '0152 applied; ottoq_determinism_pair new pin %', v_pin;
END $post$;

-- 7. Lineage. Engine behaviour changes for every run: forces re-certification.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_certification_runs_the_deterministic_core_alone', true,
        'Global tier: cuopt_propose_enabled=0, cuopt_first_refusal_max_defers=0; ottoq_determinism_pair pins both per arm. Removes the proposer''s one-tick holds (57-58 per 12-tick arm in round 6) from the decide path. Canon moves; round 7 establishes the deterministic-only canon.',
        now())
ON CONFLICT (name) DO UPDATE
   SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note, classified_at = EXCLUDED.classified_at;
