-- migration-version: 20260820060000
-- migration-name:    cuopt_propose_enabled_cert_quiesce
-- 0056 — C7 FOLLOW-UP #10, found by re-certification #10 (post-0055 arms
-- 36adbeae vs 515526fe: 2/20 identical, first divergence sim-min 90). The
-- 0055 manifest fix holds: at the divergence tick every STATE and every SoC
-- is paired for the first time — the residue is purely WHICH stall each gate
-- vehicle was reserved, shifted by one down an ordered stall list. The
-- decisions audit trail shows the two runs' very first tick-3 decisions
-- differ, and the mechanism is ARCHITECTURAL, not a salt: the cuOpt proposer
-- fired 33 times in EACH arm (cuopt_invocation_log) and armed 50 vs 47
-- right-of-first-refusal deferrals (ottoq_cuopt_deferrals) — the deferral
-- holds a vehicle out of the local greedy path "while a solve is in flight",
-- and in-flight-ness is real pg_net HTTP timing, real debounce windows and
-- real TTL clocks. Two same-seed runs therefore hold DIFFERENT vehicles, and
-- every downstream stall pairing shifts.
--
-- THE FIX is a per-run policy, cuopt_propose_enabled (default 1 — production
-- and demo behavior byte-identical): ottoq_cuopt_refresh refuses (and LOGS
-- the refusal, per the ledger rule) when 0; ottoq_cuopt_defer_hold never
-- holds when 0; ottoq_cert_arm_start sets 0 for its own run. Nothing is
-- removed: propose/dispose, the deferral pattern, and the NVIDIA pipeline
-- are untouched for every non-cert run.
--
-- Same self-verifying in-place mechanism as 0054/0055. Pre-image pins:
--   public.ottoq_cuopt_refresh    220ae5cf31f85929fd8dbf14e3be4537
--   public.ottoq_cuopt_defer_hold b89aefc99a9d10530270f7c69a9a16b8
--   public.ottoq_cert_arm_start   121d6a5bb8ead5c9a33563f0ed0f6d5a

DO $do$
DECLARE
  p RECORD; v_oid oid; v_src text; v_cnt int; v_done jsonb := '{}'::jsonb;
BEGIN
  FOR p IN
    SELECT * FROM (VALUES
    ('public','ottoq_cuopt_refresh','220ae5cf31f85929fd8dbf14e3be4537',1,$anchor$  IF v_run IS NULL THEN
    PERFORM public.cuopt_log_gate(NULL, 'no_running_run', NULL, NULL, v_t0);
    RETURN NULL;
  END IF;$anchor$,$anchor$  IF v_run IS NULL THEN
    PERFORM public.cuopt_log_gate(NULL, 'no_running_run', NULL, NULL, v_t0);
    RETURN NULL;
  END IF;

  /* ══════════ 0056: CERT QUIESCE — THE PROPOSER IS REAL-ASYNC ══════════
     cuOpt proposes over pg_net HTTP with real-domain debounce, heartbeats and
     TTLs, so its fire/answer timing is wall-clock physics, not a function of
     the seed. Measured (re-cert #10, same-seed arms 36adbeae/515526fe): 33
     invocations EACH and 50 vs 47 right-of-first-refusal deferral holds — the
     holds, not the seed, chose which vehicles waited a tick, and the whole
     assignment order shifted behind them. A determinism-certified run must
     not exercise it. Per-run policy, default ON: production and demo runs are
     byte-identical in behavior; ottoq_cert_arm_start sets 0 for cert arms.
     Ledger-honest per the standing cuOpt rule: the refusal is logged like
     every other gate, so "policy_disabled N times" is a countable fact. */
  IF ottoq_policy_get(v_run, 'cuopt_propose_enabled', 1) < 1 THEN
    PERFORM public.cuopt_log_gate(v_run, 'policy_disabled', NULL, NULL, v_t0);
    RETURN NULL;
  END IF;$anchor$),
    ('public','ottoq_cuopt_defer_hold','b89aefc99a9d10530270f7c69a9a16b8',1,$anchor$  SELECT EXISTS (SELECT 1 FROM public.ottoq_cuopt_deferrals d$anchor$,$anchor$  SELECT public.ottoq_policy_get(p_sim_run_id, 'cuopt_propose_enabled', 1) >= 1
     /* 0056: cert quiesce — a run with the proposer disabled never holds a
        vehicle for it, even if stale deferral rows exist. Fails open. */
     AND EXISTS (SELECT 1 FROM public.ottoq_cuopt_deferrals d$anchor$),
    ('public','ottoq_cert_arm_start','121d6a5bb8ead5c9a33563f0ed0f6d5a',1,$anchor$  RETURNING sim_run_id INTO v_run;$anchor$,$anchor$  RETURNING sim_run_id INTO v_run;

  /* 0056: determinism cert arms quiesce the REAL-async cuOpt proposer (see
     the 0056 note in ottoq_cuopt_refresh). Run-scoped: nothing outside this
     arm's own run is affected. */
  INSERT INTO ottoq_policy_params (scope_type, scope_id, param_key, param_value)
  VALUES ('run', v_run, 'cuopt_propose_enabled', 0)
  ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = 0;$anchor$)
    ) AS t(sch, fn, pre_md5, n_expected, old, new)
  LOOP
    SELECT pr.oid INTO STRICT v_oid
      FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = p.sch AND pr.proname = p.fn;
    v_src := pg_get_functiondef(v_oid);
    IF NOT (v_done ? (p.sch || '.' || p.fn)) AND md5(v_src) <> p.pre_md5 THEN
      RAISE EXCEPTION '0056: %.% pre-image md5 % != pinned %', p.sch, p.fn, md5(v_src), p.pre_md5;
    END IF;
    v_cnt := (length(v_src) - length(replace(v_src, p.old, ''))) / length(p.old);
    IF v_cnt <> p.n_expected THEN
      RAISE EXCEPTION '0056: %.% anchor occurs % times (need %): %', p.sch, p.fn, v_cnt, p.n_expected, left(p.old, 80);
    END IF;
    EXECUTE replace(v_src, p.old, p.new);
    v_done := v_done || jsonb_build_object(p.sch || '.' || p.fn, true);
    RAISE NOTICE '0056 patched %.% -> md5 %', p.sch, p.fn,
      (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
        JOIN pg_namespace n ON n.oid = pr.pronamespace
       WHERE n.nspname = p.sch AND pr.proname = p.fn);
  END LOOP;
END
$do$;
