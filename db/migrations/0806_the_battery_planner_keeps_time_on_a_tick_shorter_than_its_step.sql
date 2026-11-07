-- migration-version: 20261106183952
-- migration-name:    the_battery_planner_keeps_time_on_a_tick_shorter_than_its_step
--
-- 0806  **The battery planner keeps time on a tick shorter than its step.** (G528; B1, the production battery planner)
--
-- ══ §0 WHY NOW ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0804 (applied 2026-11-06 17:50:51 UTC) is the planner's seam: the request, the fire to the edge function and the
--   landing. It was measured in the research lab on days that tick every 5 minutes, the planner's own step. Read against
--   production's tick lengths after the apply, it would never steer the battery there (G528). Its dials are off and the
--   edge function is not deployed, so nothing has run; this file is the fix before anything is switched on.
--
-- ══ §1 WHAT IS WRONG (FINDINGS G528; production's tick lengths read 2026-11-06 18:03:36 UTC) ═════════════════════════
--
--   ottoq_bess_planner_fire starts a plan one step after the fire's clock (plan_start_clock = clock + 5 minutes), so
--   that the next tick reads its step 0, and the orchestrator follows the newest ready plan at step
--   floor((clock - plan_start) / step). At a 5-minute tick the next tick lands on step 0. At a shorter tick it lands
--   before the plan starts (step -1): the plan is passed over and the day plan decides; and since every tick fires a
--   newer plan, the newest ready plan always starts in the future, so none is ever followed. Production's tick is 2
--   minutes (its one session read 103 sim-seconds a tick), and 55 of the 57 operator demo runs started at the twin depot
--   in the last 60 days ticked under 5 sim-minutes (median 14.7 sim-seconds a tick). Fired every tick, such a run would
--   also ask the service for some 20 plans per 5-minute step.
--
-- ══ §2 WHAT THIS CHANGES (three anchored edits, nothing else; every one inert while bess_planner_enabled is 0) ═══════
--
--   (1) ottoq_bess_planner_fire: the plan starts at the fire's own clock plus a microsecond, so a tick follows the step
--       its clock falls in, (start + j steps, start + j + 1 steps], whatever the tick's length. At a 5-minute tick the
--       step read is the one read before: the tick at start + k steps reads step k - 1, as it did.
--   (2) ottoq_bess_planner_fire: asked at most once per step of sim time (no plan fired for the run within the last
--       bess_planner_step_min minutes of sim time). At a 5-minute tick that is every tick, as before; at a 15-second tick
--       one plan per 20 ticks, not 20.
--   (3) ottoq_bess_planner_request: the last step before the plan (the windows that straddle now) averages the tick under
--       way with the snapshots already in that step; at a 5-minute tick there are none, as before.
--   The cars are never touched; the plan moves only the battery, and only where energy_mpc_follow is on (0799).
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 not applied; 0804 applied, its fire and request the bodies production carries (prosrc md5
--   157cf1a4 and adb6cee3, read 2026-11-06 18:08:44 UTC), and the orchestrator 0804's (5ae3ea63), whose step reckoning V2
--   mirrors. Pre-images to ottoq_schema_snapshots as '0806_pre'. Each anchor matches once, read with bare newlines.
--   V1 each body less its changes is its pre-image. V2 on the twin's latest run, rolled back with its rows: a plan fired
--   at T starts at T plus a microsecond; the planner is not asked again at T + 15 s or T + 4:59 and is at T + 5:00; on the
--   landed plan the orchestrator's reckoning reads steps 0, 0, 0, 1, 1 at T + 15 s, 2:00, 5:00, 5:15 and 10:00; and the
--   request's last past step is the mean of the snapshots in it and the tick under way. Skipped with a notice when the
--   twin depot has no run. V3 the patched bodies are byte for byte the ones the research lab ran.
--   In the research lab (2026-11-06 18:13-18:35 UTC; lab/research/p2_capacity/g528_lab_2026-11-06.md), seed 424242's
--   36-hour day billed from 6 PM day 1: at the lab's 5-minute tick this file changes nothing (864 of 864 energy commands,
--   426 plans and 740 sessions as the recorded p36prod day); at production's 2-minute tick the chain as 0804 left it
--   followed a plan on 0.6% of ticks (7, after the last plan was asked) and billed the day plan's $1,485.76 to the cent,
--   and with this file it followed on 99.0% of ticks and billed $1,233.87 (the billed half hour 592 kW against 1,000),
--   $251.89 saved, 65% of the gap to perfect foresight, every car-facing line of the scorecard the day plan's. V2 passed on
--   a copy of the p36prod day. One seed: a single reading.
--
-- ══ §4 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: bess_planner_enabled is 0 by default and in every certified arm,
--   and with it off neither function is called.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0806_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0806_the_battery_planner_keeps_time_on_a_tick_shorter_than_its_step'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0806 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0806_the_battery_planner_keeps_time_on_a_tick_shorter_than_its_step') THEN
    RAISE EXCEPTION '0806 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0804_the_battery_plans_its_day_on_the_learned_forecast_and_the_planner_answers_from_outside') THEN
    RAISE EXCEPTION '0806 P1: 0804 (the planner''s request, fire and landing) comes first';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_bess_planner_fire(uuid,uuid,timestamp with time zone,bigint,jsonb,numeric,numeric,numeric)'))
       IS DISTINCT FROM '157cf1a400ed66c0c1d0797668bf7cf7'
     OR (SELECT md5(prosrc) FROM pg_proc
          WHERE oid = to_regprocedure('public.ottoq_bess_planner_request(uuid,uuid,timestamp with time zone,jsonb,bigint,numeric,numeric,numeric)'))
       IS DISTINCT FROM 'adb6cee3be19d9713d95ffaa820dfd0e' THEN
    RAISE EXCEPTION '0806 P1: the planner''s fire or request is not the body 0804 left (157cf1a4, adb6cee3)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'))
     IS DISTINCT FROM '5ae3ea6336d7c15d343ae6b82c394285' THEN
    RAISE EXCEPTION '0806 P1: public.ottoq_energy_orchestrate is not the body 0804 left (5ae3ea63), whose step V2 mirrors';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0806_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_bess_planner_fire(uuid,uuid,timestamp with time zone,bigint,jsonb,numeric,numeric,numeric)'::regprocedure,
                 'public.ottoq_bess_planner_request(uuid,uuid,timestamp with time zone,jsonb,bigint,numeric,numeric,numeric)'::regprocedure);

CREATE TEMP TABLE _0806_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0806_patch VALUES
-- (2) at most once per step of sim time
('public.ottoq_bess_planner_fire(uuid,uuid,timestamp with time zone,bigint,jsonb,numeric,numeric,numeric)', 1,
$o$DECLARE v_q jsonb; v_req jsonb; v_id uuid; v_step numeric; v_m int; v_k text; v_rid bigint;
BEGIN
  v_q := public.ottoq_bess_planner_request(p_sim_run_id, p_depot_id, p_sim_clock, p_day_plan, NULL, p_net_now_kw,$o$,
$n$DECLARE v_q jsonb; v_req jsonb; v_id uuid; v_step numeric; v_m int; v_k text; v_rid bigint;
BEGIN
  -- 0806 (G528): asked at most once per step of sim time. A plan's steps are bess_planner_step_min long whatever the
  -- tick; at a tick of one step that is every tick, as before, and at a 15-second tick one plan per 20 ticks, not 20.
  v_step := ottoq_policy_get(p_sim_run_id, 'bess_planner_step_min', 5);
  IF v_step NOT IN (1, 2, 3, 5, 6, 10, 15, 30) THEN v_step := 5; END IF;
  IF EXISTS (SELECT 1 FROM ottoq_energy_plan q
              WHERE q.sim_run_id = p_sim_run_id AND q.source = 'bess_planner'
                AND (q.detail->>'fired_clock')::timestamptz > p_sim_clock - make_interval(secs => v_step * 60)) THEN
    RETURN NULL;
  END IF;
  v_q := public.ottoq_bess_planner_request(p_sim_run_id, p_depot_id, p_sim_clock, p_day_plan, NULL, p_net_now_kw,$n$),
-- (1) the plan starts at the fire's own clock
('public.ottoq_bess_planner_fire(uuid,uuid,timestamp with time zone,bigint,jsonb,numeric,numeric,numeric)', 2,
$o$  VALUES (p_sim_run_id, p_depot_id, p_sim_clock + make_interval(secs => v_step * 60), v_step, v_m, ARRAY[]::numeric[],$o$,
$n$  VALUES (p_sim_run_id, p_depot_id,
          -- 0806 (G528): the plan starts at this tick, so a later tick follows the step its clock falls in, (start + j
          -- steps, start + j + 1 steps], whatever the tick's length; one step after the fire's clock was right only at a
          -- tick of exactly one step (the orchestrator reads floor((clock - start) / step))
          p_sim_clock + interval '1 microsecond', v_step, v_m, ARRAY[]::numeric[],$n$),
-- (3) the last step before the plan: the tick under way with the snapshots already in it
('public.ottoq_bess_planner_request(uuid,uuid,timestamp with time zone,jsonb,bigint,numeric,numeric,numeric)', 3,
$o$    FROM (SELECT k, CASE WHEN k = 1 AND p_grid_now_kw IS NOT NULL THEN round(GREATEST(p_grid_now_kw, 0), 1)$o$,
$n$    FROM (SELECT k, CASE WHEN k = 1 AND p_grid_now_kw IS NOT NULL
                         -- 0806 (G528): the tick under way with the snapshots already in its step (at a tick of one step
                         -- there are none, as before)
                         THEN (SELECT round(GREATEST(avg(z.x), 0), 1)
                                 FROM (SELECT COALESCE(e.grid_import_kw, 0) AS x FROM site_energy_snapshots e
                                        WHERE e.depot_id = p_depot_id AND e.sim_run_id = p_sim_run_id
                                          AND e.timestamp > p_sim_clock - make_interval(secs => v_step * 60)
                                          AND e.timestamp < p_sim_clock
                                       UNION ALL SELECT p_grid_now_kw) z)$n$);

UPDATE _0806_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE f text; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0806_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(f::regprocedure);
    FOR p IN SELECT * FROM _0806_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0806: anchor % matches % times, not 1', p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f::regprocedure) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0806: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each body less its changes is its pre-image ──
DO $v1$
DECLARE f text; p record; v_body text; v_want text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0806_patch ORDER BY fn LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = f::regprocedure;
    FOR p IN SELECT * FROM _0806_patch WHERE fn = f ORDER BY seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    v_want := CASE WHEN f LIKE 'public.ottoq_bess_planner_fire%' THEN '157cf1a400ed66c0c1d0797668bf7cf7'
                   ELSE 'adb6cee3be19d9713d95ffaa820dfd0e' END;
    IF md5(v_body) IS DISTINCT FROM v_want THEN
      RAISE EXCEPTION '0806 V1: % less its changes is not its pre-image (md5 %)', f, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: on the twin's latest run, rolled back with its rows ──
DO $v2$
DECLARE
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_mid bigint; v_plan jsonb; v_p1 uuid; v_p2 uuid; v_ps timestamptz; v_l jsonb;
  v_q jsonb; v_last numeric; v_want numeric; v_steps text; v_n int;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start) INTO v_run, v_clock
    FROM ottoq_sim_runs r WHERE r.depot_id = c_twin AND r.sim_clock_start IS NOT NULL
   ORDER BY r.started_at DESC NULLS LAST LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0806 V2: skipped, the twin depot has no run to probe';
    RETURN;
  END IF;
  BEGIN
    -- a synthetic learned forecast, so the request is built whatever the log holds (0804 V2's), and 6 hours to plan
    INSERT INTO public.ottoq_bess_forecast_models (depot_id, note, usable, quantile, lam, fold_by, runs, n_folds, n_examples,
                                                   features, per_half_hour, profile)
    SELECT c_twin, '0806 V2 (rolled back)', true, 0.8, 10, 'run_day', ARRAY[v_run], 3, 0, ARRAY['1'],
           (SELECT jsonb_agg(jsonb_build_object('h', h, 'n', 0, 'mu', to_jsonb(array_fill(0::float8, ARRAY[9])),
                                                'sd', to_jsonb(array_fill(1::float8, ARRAY[9])),
                                                'w', to_jsonb(ARRAY[300::float8, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
                                                'offset_kw', 50) ORDER BY h) FROM generate_series(0, 7) h),
           (SELECT jsonb_agg(jsonb_build_object('b', b, 'n_days', 3, 'pre_mean_kw', 400, 'pre_upper_kw', 450,
                                                'ev_mean_kw', 350, 'ev_upper_kw', 400) ORDER BY b) FROM generate_series(0, 47) b)
    RETURNING model_id INTO v_mid;
    UPDATE ottoq_sim_runs SET sim_clock_end = v_clock + interval '6 hours' WHERE sim_run_id = v_run;
    v_plan := public.ottoq_bess_day_plan(v_run, c_twin, v_clock, NULL);
    IF NOT COALESCE((v_plan->>'ok')::boolean, false) THEN
      RAISE NOTICE '0806 V2: skipped, the twin''s day plan does not solve at run %', v_run;
      RAISE EXCEPTION USING ERRCODE = 'P0806', MESSAGE = 'roll back';
    END IF;
    -- (1) the plan starts at the fire's own clock
    v_p1 := public.ottoq_bess_planner_fire(v_run, c_twin, v_clock, 1, v_plan, 500, 400, 100);
    SELECT plan_start_clock, horizon_steps INTO v_ps, v_n FROM ottoq_energy_plan WHERE id = v_p1;
    IF v_p1 IS NULL OR v_ps IS DISTINCT FROM v_clock + interval '1 microsecond' THEN
      RAISE EXCEPTION '0806 V2: the plan does not start at the fire''s clock: % against %', v_ps, v_clock;
    END IF;
    -- (2) at most once per step of sim time
    IF public.ottoq_bess_planner_fire(v_run, c_twin, v_clock + interval '15 seconds', 2, v_plan, 500, 400, 100) IS NOT NULL
       OR public.ottoq_bess_planner_fire(v_run, c_twin, v_clock + interval '4 minutes 59 seconds', 3, v_plan, 500, 400, 100)
          IS NOT NULL THEN
      RAISE EXCEPTION '0806 V2: the planner was asked twice inside one step';
    END IF;
    v_p2 := public.ottoq_bess_planner_fire(v_run, c_twin, v_clock + interval '5 minutes', 4, v_plan, 500, 400, 100);
    IF v_p2 IS NULL THEN
      RAISE EXCEPTION '0806 V2: the planner was not asked a step later';
    END IF;
    -- the step a tick follows on the landed plan, by the orchestrator's own reckoning
    v_l := public.ottoq_bess_planner_land(v_p1, jsonb_build_object(
             'status', 'optimal', 'solver', 'glop', 'objective_usd', 1.0, 'solve_ms', 5, 'peak_kw', jsonb_build_array(500),
             'grid_kw', to_jsonb(array_fill(400::numeric, ARRAY[v_n])),
             'setpoint_kw', to_jsonb(array_fill(0::numeric, ARRAY[v_n]))), 200, 900);
    IF v_l->>'state' <> 'ready' THEN
      RAISE EXCEPTION '0806 V2: the plan did not land: %', v_l;
    END IF;
    SELECT string_agg(floor(EXTRACT(EPOCH FROM (c.at - p.plan_start_clock)) / (p.tick_minutes * 60.0))::int::text, ','
                      ORDER BY c.at)
      INTO v_steps
      FROM ottoq_energy_plan p,
           unnest(ARRAY[v_clock + interval '15 seconds', v_clock + interval '2 minutes', v_clock + interval '5 minutes',
                        v_clock + interval '5 minutes 15 seconds', v_clock + interval '10 minutes']) AS c(at)
     WHERE p.id = v_p1;
    IF v_steps IS DISTINCT FROM '0,0,0,1,1' THEN
      RAISE EXCEPTION '0806 V2: ticks read steps % of the plan (0,0,0,1,1 expected)', v_steps;
    END IF;
    -- (3) the last past step: the tick under way (0 kW here) with the snapshots already in its step
    v_q := public.ottoq_bess_planner_request(v_run, c_twin, v_clock, v_plan, v_mid, 500, 0, 0);
    v_last := (v_q->'request'->'past_grid_kw'->>(jsonb_array_length(v_q->'request'->'past_grid_kw') - 1))::numeric;
    SELECT round(GREATEST(avg(z.x), 0), 1) INTO v_want
      FROM (SELECT COALESCE(e.grid_import_kw, 0) AS x FROM site_energy_snapshots e
             WHERE e.depot_id = c_twin AND e.sim_run_id = v_run
               AND e.timestamp > v_clock - interval '5 minutes' AND e.timestamp < v_clock
            UNION ALL SELECT 0) z;
    IF v_last IS DISTINCT FROM v_want THEN
      RAISE EXCEPTION '0806 V2: the last past step is % kW, not the mean of its snapshots and the tick under way (% kW)',
        v_last, v_want;
    END IF;
    RAISE NOTICE '0806 V2: run %, plan starts %, steps read %, last past step % kW', v_run, v_ps, v_steps, v_last;
    RAISE EXCEPTION USING ERRCODE = 'P0806', MESSAGE = 'roll back the probe';
  EXCEPTION WHEN SQLSTATE 'P0806' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_models WHERE note = '0806 V2 (rolled back)')
     OR EXISTS (SELECT 1 FROM ottoq_energy_plan WHERE sim_run_id = v_run AND source = 'bess_planner'
                   AND (detail->>'tick_seq') IN ('1', '2', '3', '4') AND (detail->>'fired_clock')::timestamptz >= v_clock) THEN
    RAISE EXCEPTION '0806 V2: the probe''s rows were not rolled back';
  END IF;
END $v2$;

-- ── V3: the patched bodies are byte for byte the ones the research lab ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_bess_planner_fire(uuid,uuid,timestamp with time zone,bigint,jsonb,numeric,numeric,numeric)'::regprocedure)
       IS DISTINCT FROM '7131ebaffdf2e64388e1f35768fd4cf8'
     OR (SELECT md5(prosrc) FROM pg_proc
          WHERE oid = 'public.ottoq_bess_planner_request(uuid,uuid,timestamp with time zone,jsonb,bigint,numeric,numeric,numeric)'::regprocedure)
       IS DISTINCT FROM '8b1a0f5c737776cf085490bcc4504bc8' THEN
    RAISE EXCEPTION '0806 V3: the patched bodies are not the ones the lab ran (fire %, request %)',
      (SELECT md5(prosrc) FROM pg_proc
        WHERE oid = 'public.ottoq_bess_planner_fire(uuid,uuid,timestamp with time zone,bigint,jsonb,numeric,numeric,numeric)'::regprocedure),
      (SELECT md5(prosrc) FROM pg_proc
        WHERE oid = 'public.ottoq_bess_planner_request(uuid,uuid,timestamp with time zone,jsonb,bigint,numeric,numeric,numeric)'::regprocedure);
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0806_the_battery_planner_keeps_time_on_a_tick_shorter_than_its_step', false, false,
        'G528. The battery planner''s plan starts at the fire''s own clock, so a tick follows the step its clock falls in '
        'whatever its length; the planner is asked at most once per step of sim time; the request''s last past step '
        'averages the tick under way with the snapshots in it. At a 5-minute tick nothing changes. Inert while '
        'bess_planner_enabled is 0 (the default and every certified arm).',
        now());

COMMIT;

-- APPLIED 2026-11-06 at 18:39:52 UTC (12:39 PM CT), ledger 20261106183952, through apply_migration, on Chase's word
--   ("Yes, just keep building", read 2026-11-06 by 13:20 UTC, the go-ahead for the battery planner), confirmed by Chase
--   at the connector's prompt. Nothing live (no run running, in flight 0), the fire and the request at the md5s P1
--   names (157cf1a4, adb6cee3) and the orchestrator 0804's (5ae3ea63), read 18:37:23 UTC. The text sent was this file
--   before its version line and this footer were set: 20,086 characters, md5 23aed2c0, equal to the ledger's
--   statements[1] read back. P0, P1, the anchors, V1, V2 (on edf611ad, the twin's latest run) and V3 passed inside the
--   apply. Read back at 18:39:59 UTC: md5(prosrc) of the fire 7131ebaf and of the request 8b1a0f5c, the bodies
--   ottoq_lab_0806m ran; two '0806_pre' snapshots; no bess_planner plan, no forecast model and an empty pg_net queue
--   (the probe rolled back); the lineage row FALSE/FALSE at 18:39:52. The planner's dials stay off at the twin depot
--   until #21 is deployed with the edge function and a model is usable. The lab template ottoq_lab took the same text
--   and ledger row at 18:42 UTC.
