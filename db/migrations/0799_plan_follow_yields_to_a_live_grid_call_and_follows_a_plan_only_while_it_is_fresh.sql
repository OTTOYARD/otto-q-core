-- migration-version: PENDING
-- migration-name:    plan_follow_yields_to_a_live_grid_call_and_follows_a_plan_only_while_it_is_fresh
--
-- 0799  **The battery's plan-follow mode yields to a live demand-response call, and follows an outside plan only while it
--        is fresh.** (G519)
--
-- ══ §0 WHY NOW ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-11-05: "let's not sleep on the agent/AI with BESS usage angle (Forward planning/analyzing, etc.)", and
--   2026-11-06 01:24 UTC: "continue building as needed. You're the expert". The research lab's battery planner (a linear
--   program over the rest of the day, lab/research/p2_capacity/battery_lp.py) reaches the engine through the
--   orchestrator's plan-follow branch (FR-1, energy_mpc_follow = 1), and that branch is not yet safe to drive (G519).
--
-- ══ §1 WHAT IS WRONG (FINDINGS G519; public.ottoq_energy_orchestrate as production holds it, md5(prosrc) 8f425cda) ══
--
--   With energy_mpc_follow at 1 the orchestrator takes the newest 'ready' row of ottoq_energy_plan for the run and follows
--   its setpoint for the current step, clamped only to the battery's power, its floor and its ceiling. v_dr_active is read
--   only in the day-plan and heuristic branches (discharge_dr), so a call that comes after the plan was made gets no answer
--   from the battery in this mode; and nothing bounds the plan's age, so a plan written hours earlier is followed as long
--   as its horizon covers the clock. Latent: the mode is off in production (the catalog's default is 0; one run-scope row
--   at 1 for an old run, f1000002, by ottocommand; no energy command production holds records 'mpc_follow'), and the one
--   routine that sets it, ottoq_fr1_cert_arm (the benchmark depot), has no caller.
--
-- ══ §2 WHAT THIS CHANGES (only where energy_mpc_follow is 1; elsewhere nothing decides differently) ════════════════════
--
--   Two anchored edits in public.ottoq_energy_orchestrate, and one new dial:
--   (1) plan-follow is skipped while a demand-response call is live (v_dr_active, computed before the branch), so the
--       day-plan path (0435) answers the call with the battery (discharge_dr); the planner's next plan starts from the
--       battery the call left.
--   (2) a plan is followed only while fresh: from its start to fewer than energy_mpc_max_plan_age_steps steps after it
--       (new dial, default 3, catalogued 1..48, not agent-writable); a staler plan, or none, falls back to the day plan,
--       as no plan did before. A planner that writes a plan every tick is always at step 0.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the orchestrator is the body 0797 left and production carries (prosrc md5 8f425cda, read
--   2026-11-06 02:56:08 UTC), 0797 is applied, and the new dial is not catalogued. P2 once. The pre-image to
--   ottoq_schema_snapshots as '0799_pre'. Each anchor matches once, read with bare newlines. V1 the body less its changes
--   is its pre-image. V2 the dial is catalogued as declared and set nowhere by this file. V3 the patched body is byte for
--   byte the one the research lab ran (md5). The lab ran this file on a copy of its template (ottoq_lab_0799) and the
--   planner on the forced-call day from it (lab/research/p2_capacity/jobs_2026-11-06_lp2_call_0799.txt).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ══════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: with energy_mpc_follow at 0 the orchestrator decides exactly as before (V1; both edits are inside
--   the branch the dial at 1 opens), and no certification arm, canon cell or dial experiment sets it to 1 (the one
--   routine that can, ottoq_fr1_cert_arm, has no caller). forces_dial_restart FALSE: no experiment varies either dial.
--
-- ══ §5 AT THE TWIN DEPOT (CLAUDE.md rule 12) ════════════════════════════════════════════════════════════════════════
--
--   Plan-follow stays off at the twin depot (energy_mpc_follow 0): no planner writes plans in production yet, and the day
--   plan is the plan of record (G168). This file makes the mode safe for the day one is switched on; nothing to set now.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0799_pre'; DELETE FROM
--   public.ottoq_policy_param_catalog WHERE param_key = 'energy_mpc_max_plan_age_steps'; DELETE FROM
--   public.ottoq_cert_lineage WHERE name = '0799_plan_follow_yields_to_a_live_grid_call_and_follows_a_plan_only_while_it_is_fresh'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0799 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the body this file was written against, 0797, and the dial not yet catalogued ──
DO $p1$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'))
       IS DISTINCT FROM '8f425cda7b4b8486b8b44594b9bfe11f' THEN
    RAISE EXCEPTION '0799 P1: public.ottoq_energy_orchestrate is not the body this file was written against';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0797_the_battery_holds_its_call_reserve_only_as_the_window_nears_and_its_floor_can_stop_rising_at_a_surge') THEN
    RAISE EXCEPTION '0799 P1: 0797 is not applied; apply in order';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'energy_mpc_max_plan_age_steps') THEN
    RAISE EXCEPTION '0799 P1: energy_mpc_max_plan_age_steps is already catalogued';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0799_plan_follow_yields_to_a_live_grid_call_and_follows_a_plan_only_while_it_is_fresh') THEN
    RAISE EXCEPTION '0799 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0799_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure;

-- ── the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                                agent_writable)
VALUES ('energy_mpc_max_plan_age_steps',
        '0799 (G519): with energy_mpc_follow at 1, the orchestrator follows an outside battery plan only from its start to '
        'fewer than this many steps after it; a staler plan, or none, falls back to the day plan. A planner that writes a '
        'plan every tick is always at step 0. Default 3.',
        3, 1, 48, 'public.ottoq_energy_orchestrate', false);

-- ── the patches ──
CREATE TEMP TABLE _0799_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0799_patch VALUES
  -- (1) a live call is the day plan's
  (1,
   $p1o$  IF ottoq_policy_get(p_sim_run_id, 'energy_mpc_follow', 0) >= 0.5 THEN$p1o$,
   $p1n$  IF ottoq_policy_get(p_sim_run_id, 'energy_mpc_follow', 0) >= 0.5
     -- 0799 (G519): a live demand-response call is the day plan's to answer (discharge_dr); an outside plan made before
     -- the call does not know it, so plan-follow waits for the call to end
     AND NOT v_dr_active THEN$p1n$),
  -- (2) a plan is followed only while fresh
  (2,
   $p2o$      IF v_step >= 0 AND v_step < v_plan.horizon_steps AND v_step+1 <= array_length(v_plan.bess_setpoint_kw,1) THEN$p2o$,
   $p2n$      IF v_step >= 0 AND v_step < v_plan.horizon_steps AND v_step+1 <= array_length(v_plan.bess_setpoint_kw,1)
         -- 0799 (G519): a plan is followed only while fresh; a staler one, or none, falls back to the day plan
         AND v_step < GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id, 'energy_mpc_max_plan_age_steps', 3), 3)) THEN$p2n$);

UPDATE _0799_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  FOR p IN SELECT * FROM _0799_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0799: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0799: public.ottoq_energy_orchestrate is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the body less its changes is its pre-image ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure;
  FOR p IN SELECT * FROM _0799_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '8f425cda7b4b8486b8b44594b9bfe11f' THEN
    RAISE EXCEPTION '0799 V1: the body less its changes is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: the dial, as declared, and set nowhere by this file ──
DO $v2$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key = 'energy_mpc_max_plan_age_steps' AND default_value = 3 AND min_value = 1 AND max_value = 48
         AND NOT COALESCE(agent_writable, false)) <> 1
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'energy_mpc_max_plan_age_steps') THEN
    RAISE EXCEPTION '0799 V2: the dial is not catalogued as declared, or is set somewhere';
  END IF;
END $v2$;

-- ── V3: the patched body is byte for byte the one the research lab ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure)
       IS DISTINCT FROM 'db31a8c652ef44f147926651d0e48557' THEN
    RAISE EXCEPTION '0799 V3: the patched body is not the one the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0799_plan_follow_yields_to_a_live_grid_call_and_follows_a_plan_only_while_it_is_fresh', false, false,
        'G519. With energy_mpc_follow at 1, public.ottoq_energy_orchestrate skips plan-follow while a demand-response call '
        'is live (the day plan answers it) and follows a plan only fewer than energy_mpc_max_plan_age_steps (new, default '
        '3) steps after its start. At 0 nothing runs differently (V1). No certification arm, canon cell or dial experiment '
        'sets energy_mpc_follow to 1 (ottoq_fr1_cert_arm, the one routine that can, has no caller).',
        now());

COMMIT;
