-- migration-version: 20260913011239
-- migration-name: 0262_the_hold_key_the_setter_refused
-- ===========================================================================
-- 0262  THE HOLD KEY THE SETTER REFUSED  (D3: the one-tick hold could not be switched on)
-- ===========================================================================
-- probe:          run af2def1b-8413-4eba-a434-637444b06bb9 (the first D3 demo run,
--                 2026-09-13 00:26-01:00 UTC); demo/D3_RUNBOOK.md §1; 0259 §3c;
--                 db/checks/0186 §1 (the ledger reading of what that run heard).
-- forces_recert:  FALSE -- one catalog row, no function changes. The gate 0259 added to
--                 ottoq_cuopt_defer_hold reads this key through ottoq_policy_get with
--                 default 0, and no certification arm sets it (0259 A5, re-asserted in A4
--                 below); the default is unchanged, so a certification arm computes
--                 exactly what it computed before this file. ottoq_determinism_pair is
--                 pinned in A5.
--
-- WHAT WAS FOUND. 0259 taught ottoq_cuopt_defer_hold a second gate key,
-- proposer_hold_enabled, so a run with cuOpt quiesced could still hold an arriving
-- vehicle out of the local cursor for one decide tick while a non-cuOpt proposer answers.
-- It read the key through ottoq_policy_get, which reads ottoq_policy_params directly. It
-- never registered the key in ottoq_policy_param_catalog -- and ottoq_policy_set, the
-- only sanctioned writer of ottoq_policy_params, refuses any key the catalog lacks:
--
--   SELECT ottoq_policy_set('run', <run>, 'proposer_hold_enabled', 1, 'd3_demo');
--   -> {"ok": false, "error": "unknown_param", "param": "proposer_hold_enabled"}
--
-- Measured on the first D3 demo run: the runbook's §1 issued exactly that call, it
-- returned ok=false, nothing read the return, and the run proceeded with the hold OFF.
-- Every forward_lex row the CP-SAT bridge then submitted (fires 3 and 4 of
-- ottoq_proposer_fire_log, 54 rows) was either superseded by the local heuristic deciding
-- the same vehicle in the same tick, or left pending for a vehicle that already carried a
-- booking and would never be decided again. Zero rows reached the shield. The proposer
-- was not refused; it was never heard -- and 'pending' in ottoq_external_proposals does
-- not distinguish "awaiting the next decide" from "for a vehicle nothing will decide".
--
-- A SECOND, RELATED FACT, RECORDED HERE AND FIXED IN THE RUNBOOK, NOT THE ENGINE.
-- ottoq_cuopt_first_refusal_arm returns before arming anything when
-- cuopt_first_refusal_max_defers resolves to 0, and 0152 set the GLOBAL tier to 0 so the
-- deterministic core certifies alone. A run that wants the hold must set BOTH keys at run
-- scope: proposer_hold_enabled=1 (the gate) and cuopt_first_refusal_max_defers=1 (the
-- arm). demo/D3_RUNBOOK.md §1 now says so and reads the return of every policy_set.
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
  SELECT count(*) INTO v_n FROM cron.job WHERE active AND jobname ~ '^r[0-9]+_';
  IF v_n > 0 THEN
    RAISE EXCEPTION 'P FAILED: % certification job(s) scheduled', v_n;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 1. Register the key. The catalog is what ottoq_policy_set consults; the range is the
--    same 0..1 as cuopt_propose_enabled and orchestrator_agent_enabled.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects)
SELECT 'proposer_hold_enabled',
       '0259/0262: second key of the one-tick hold gate in ottoq_cuopt_defer_hold. 1 = a run with cuOpt quiesced '
       'still holds an arriving vehicle out of the local cursor for one decide tick so any holds_tick proposer '
       '(ottoq_proposer_precedence) can answer; the hold releases the moment such a proposer answers and '
       'unconditionally at the next decide tick. Needs cuopt_first_refusal_max_defers >= 1 at the same scope or '
       'nothing is ever armed (0152: global tier is 0). Default 0. Certification arms set neither key.',
       0, 0, 1,
       'ottoq_cuopt_defer_hold gate (0259 3c), read via ottoq_policy_get; arm cap is cuopt_first_refusal_max_defers'
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'proposer_hold_enabled');

-- ---------------------------------------------------------------------------
-- 2. Classify.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
('0262_the_hold_key_the_setter_refused', false,
 'One row in ottoq_policy_param_catalog so ottoq_policy_set accepts proposer_hold_enabled (0259 read it, never '
 'registered it). No function changes; default stays 0; no certification arm sets it (A4). ottoq_determinism_pair '
 'pinned (A5).')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- A. Assertions. A1-A2 use a scratch run scope that no run owns and delete it after;
--    A3 asserts the scratch left nothing behind.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-000000000262';
  v_r jsonb; v_n int; v_h text;
BEGIN
  -- A1  THE SETTER ACCEPTS THE KEY AND THE GETTER SEES IT.
  v_r := public.ottoq_policy_set('run', v_scratch, 'proposer_hold_enabled', 1, '0262_proof');
  IF COALESCE((v_r->>'ok')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'A1 FAILED: ottoq_policy_set still refuses proposer_hold_enabled: %', v_r;
  END IF;
  IF public.ottoq_policy_get(v_scratch, 'proposer_hold_enabled', 0) <> 1 THEN
    RAISE EXCEPTION 'A1 FAILED: ottoq_policy_get did not read back 1';
  END IF;

  -- A2  THE RANGE CLAMPS: a 5 is applied as 1, exactly like the sibling 0..1 keys.
  v_r := public.ottoq_policy_set('run', v_scratch, 'proposer_hold_enabled', 5, '0262_proof');
  IF (v_r->>'applied')::numeric <> 1 THEN
    RAISE EXCEPTION 'A2 FAILED: expected applied=1 for a request of 5, got %', v_r;
  END IF;

  -- A3  NO RESIDUE.
  DELETE FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_scratch;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params WHERE scope_id = v_scratch;
  IF v_n <> 0 THEN RAISE EXCEPTION 'A3 FAILED: % scratch row(s) remain', v_n; END IF;

  -- A4  NO CERTIFICATION ARM SETS THE KEY, AND THE GLOBAL TIER HAS NO ROW: the gate a
  --     certification computes is the default, 0, before and after this file.
  SELECT count(*) INTO v_n
    FROM public.ottoq_policy_params pp
    LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = pp.scope_id
   WHERE pp.param_key = 'proposer_hold_enabled'
     AND (pp.scope_type = 'global' OR r.run_by = 'cert_harness');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: proposer_hold_enabled is set on % global/certification scope(s)', v_n;
  END IF;

  -- A5  THE PAIR IS UNTOUCHED -- md5 of the BODY (pg_proc.prosrc), which is what 0257,
  --     0259, 0260 and 0261 pin. The first apply attempt of this file hashed
  --     pg_get_functiondef instead, got 0014feacf34a9d6342d10a8d022860d2 and refused
  --     itself; the body was 8a35... throughout (pg_proc.xmin 12853725 predates the
  --     round-40 arms). Recorded so the two hashes are never confused again.
  SELECT md5(p.prosrc) INTO v_h FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_determinism_pair';
  IF v_h <> '8a35b8c874fed154cc216140faec0274' THEN
    RAISE EXCEPTION 'A5 FAILED: ottoq_determinism_pair body md5 is %, expected 8a35b8c874fed154cc216140faec0274', v_h;
  END IF;

  RAISE NOTICE '0262: A1-A5 held';
END $$;

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- ---------------------------------------------------------------------------
-- 2026-09-13 01:11 UTC  attempt 1 REFUSED by its own A5: the pin hashed
--                       pg_get_functiondef (0014feacf34a9d6342d10a8d022860d2), the sibling
--                       migrations pin md5(prosrc) (8a35b8c874fed154cc216140faec0274).
--                       Nothing applied (apply_migration is atomic). Body verified
--                       unchanged: prosrc md5 8a35..., pg_proc.xmin 12853725 < the
--                       round-40 arms' xids. A5 rewritten to hash the body.
-- 2026-09-13 01:12 UTC  attempt 2 APPLIED as version 20260913011239. A1-A5 held; scratch
--                       scope 00000000-0000-0000-0000-000000000262 left 0 rows. Then, on
--                       run af2def1b (the demo run, paused at tick 18):
--                       ottoq_policy_set(proposer_hold_enabled=1) -> ok, applied 1;
--                       ottoq_policy_set(cuopt_first_refusal_max_defers=1) -> ok, applied 1.
