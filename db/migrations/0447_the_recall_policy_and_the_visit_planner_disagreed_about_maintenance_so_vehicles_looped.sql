-- migration-version: PENDING
-- migration-name:    the_recall_policy_and_the_visit_planner_disagreed_about_maintenance_so_vehicles_looped
--
-- 0447  **The recall policy and the visit planner disagreed about whether interval maintenance is required, so
--       vehicles looped between deployment and recall and the depot met a tenth of its demand.**
--       `ottoq_recall_naive_threshold_v1` (the Recall Decision, C9) recalls a deployed vehicle as
--       `service_interval_due` the moment its PM kilometres or calibration hours are due. `ottoq.ottoq_derive_visit_needs`
--       then derives `mechanical_pm` and `sensor_calibration` as `must_do: false, deferrable: true` on every visit,
--       the recall's own included. So the vehicle is released with the work undone and its counters unreset, and the
--       recall fires again at its first telemetry tick. The brief says which rule is wrong: CLAUDE.md 2.7's
--       RecallDecision returns a `service_bundle`, and a recall whose bundle is not serviced is not a decision.
--       FINDINGS G181.
--
-- ══ §1 MEASURED 2026-09-23, RUN 324eb0f1 (busy_day, twin depot), BY SIM 12:55 CT ═══════════════════════════════
--
--   - 81 of 112 missions ended `service_interval_due`; the recent ones came back 1.6-3.0 minutes after leaving.
--   - 58 distinct vehicles were recalled for it, and 58 of 58 were still due afterwards. 0 of the run's 30 PM and
--     calibration atoms were done, and 0 were ever must_do. 61 of 116 vehicles were due at the measurement.
--   - Deployed against desired, from the dispatcher's own `twin.auto_dispatch_emit`: 9.9/14 at 05:00, then
--     11.8/25, 5.1/37, 7.4/45, 5.5/49, 6.9/50, 4.3/49 and 2.8/48 at 12:00. Energy was not the limit: chargers
--     delivered about 850 kWh an hour against about 430 for 48 vehicles deployed.
--   - busy_day compresses the intervals on purpose (`ottoq_scenario_apply_fleet_overrides`): PM every 65-95 km,
--     calibration every 3.6-6.4 h, against the need profile's 6,500-9,500 km and ~250 h. That is the scenario's
--     choice and this file does not touch it. What it exposed is a kernel defect that any scenario hits when
--     maintenance falls due: the loop.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) A second real Recall Decision, `public.ottoq_recall_interval_scheduled_v1`, registered as implementation 3
--       (`interval_scheduled_v1`, status `parked`, so a production run still refuses it). It is v1's source verbatim
--       with its name changed and ONE rung replaced. Interval maintenance becomes scheduled work: below a hard
--       limit it does not recall. The night-wave rung already counts a PM-due vehicle as an overnight need, so it
--       is served there or at a natural return. At or over
--       `recall_interval_hard_overdue_mult` x its interval (default 3), and only after `recall_min_productive_min`
--       deployed (default 120), it recalls as `service_interval_overdue`, non-deferrable.
--   (2) The visit keeps the recall's promise. If the vehicle's latest dispatch in the run came back as
--       `service_interval_overdue`, its `mechanical_pm` and `sensor_calibration` atoms become must_do, not
--       deferrable, not carried over, tagged with the trigger. This is exactly 0018/0019's rider-flag pattern.
--       naive_threshold_v1 never emits that trigger (P2), so nothing changes under the incumbent.
--   (3) `recall_implementation_id`'s envelope widens to 3, and the two new dials are catalogued (not
--       agent-writable).
--   (4) One dial experiment: `recall_implementation_id` 1 against 3 on busy_day, 48 ticks, primary
--       `asset_hours_available_per_day` (higher is better), with the harness's standing guardrails. The learning
--       loop of 0439 decides; nothing here promotes v3.
--
-- ══ §3 LIMITS, SAID PLAINLY ══════════════════════════════════════════════════════════════════════════════════
--
--   - Under busy_day's compression, PM demand is roughly ten times what two service bays can do, so no recall policy
--     can keep both PM compliance and availability. v3 chooses availability below the hard limit and PM compliance
--     above it; the experiment measures what that costs.
--   - The contention gate around the rung is unchanged, so a hard-overdue recall still waits for charger contention
--     below the SLA's queue limit, as every routine rung does.
--
-- ══ §4 forces_recert FALSE ═══════════════════════════════════════════════════════════════════════════════════
--
--   The incumbent is untouched: `recall_implementation_id` is 1 everywhere it is set (P2), v1's source is not edited,
--   and the visit promotion keys on a trigger only v3 emits.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0447 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%' OR query ILIKE '%ottoq_dial_experiment_runner%'
          OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0447 P0: a pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0447 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: the sources as read on 2026-09-23, every anchor unique, and nothing this creates exists yet ──
DO $$
DECLARE v_src text; v_n int; v_a text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamp with time zone,numeric,numeric)'::regprocedure;
  IF md5(v_src) <> '098ade627348b08e58941eb510f49dae' THEN
    RAISE EXCEPTION '0447 P1: ottoq_recall_naive_threshold_v1 md5 is %', md5(v_src);
  END IF;
  v_a := E'    IF COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km\n'
      || E'       OR COALESCE(v_w.drive_hours_total,0) - COALESCE(v_w.hours_at_last_calibration,0) >= v_calib_h THEN\n'
      || E'      RETURN QUERY SELECT true,''service_interval_due'',''routine'',4::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;\n'
      || E'    END IF;\n';
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0447 P1: the v1 interval rung matched % times', v_n; END IF;

  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'ottoq.ottoq_derive_visit_needs'::regproc;
  IF md5(v_src) <> '47c44f2559c1ccc2fea15c49d1c916f0' THEN
    RAISE EXCEPTION '0447 P1: ottoq.ottoq_derive_visit_needs md5 is %', md5(v_src);
  END IF;
  v_a := E'      ''est_min'',v_pm_min,''concurrency'',''bay'',''requires_bay'',''service_bay'',''carryover_eligible'',true);\n  END IF;\n';
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0447 P1: the mechanical_pm append matched % times', v_n; END IF;
  -- the promotion must land after BOTH appends it promotes
  IF position(v_a IN v_src) < position('''svc'',''sensor_calibration''' IN v_src) THEN
    RAISE EXCEPTION '0447 P1: mechanical_pm is no longer appended after sensor_calibration';
  END IF;

  IF to_regprocedure('public.ottoq_recall_interval_scheduled_v1(uuid,uuid,timestamp with time zone,numeric,numeric)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_recall_implementations WHERE impl_id = 3 OR implementation = 'interval_scheduled_v1') THEN
    RAISE EXCEPTION '0447 P1: implementation 3 already exists';
  END IF;
  IF (SELECT max_value FROM public.ottoq_policy_param_catalog WHERE param_key = 'recall_implementation_id') <> 2 THEN
    RAISE EXCEPTION '0447 P1: recall_implementation_id''s envelope is not 1..2';
  END IF;
END $$;

-- ── P2: the premises forces_recert FALSE rests on ──
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'recall_implementation_id' AND param_value <> 1) THEN
    RAISE EXCEPTION '0447 P2: recall_implementation_id is set to something other than 1 somewhere';
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamp with time zone,numeric,numeric)'::regprocedure)
       ~ 'service_interval_overdue'
     OR (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_recall_fixed_window_dummy(uuid,uuid,timestamp with time zone,numeric,numeric)'::regprocedure)
       ~ 'service_interval_overdue' THEN
    RAISE EXCEPTION '0447 P2: an existing recall implementation already emits service_interval_overdue';
  END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0447_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_derive_visit_needs'::regproc;

-- ── (1) interval_scheduled_v1: v1 verbatim, renamed, with the interval rung replaced ──
DO $v3$
DECLARE v_def text; v_new text;
  c_rung CONSTANT text :=
         E'    IF COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km\n'
      || E'       OR COALESCE(v_w.drive_hours_total,0) - COALESCE(v_w.hours_at_last_calibration,0) >= v_calib_h THEN\n'
      || E'      RETURN QUERY SELECT true,''service_interval_due'',''routine'',4::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;\n'
      || E'    END IF;\n';
BEGIN
  v_def := pg_get_functiondef('public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamp with time zone,numeric,numeric)'::regprocedure);
  v_new := replace(v_def, 'FUNCTION public.ottoq_recall_naive_threshold_v1(', 'FUNCTION public.ottoq_recall_interval_scheduled_v1(');
  v_new := replace(v_new, c_rung,
         E'    /* 0447 (G181) interval_scheduled_v1: interval maintenance is SCHEDULED work. Below the hard limit it is not a\n'
      || E'       recall -- the night-wave rung below already counts a PM-due vehicle as an overnight need. At or over the\n'
      || E'       limit, after a minimum productive run, the vehicle comes back and the visit makes the due atom must_do. */\n'
      || E'    IF GREATEST((COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0)) / NULLIF(v_pm_km, 0),\n'
      || E'                (COALESCE(v_w.drive_hours_total,0) - COALESCE(v_w.hours_at_last_calibration,0)) / NULLIF(v_calib_h, 0))\n'
      || E'         >= ottoq_policy_get(p_sim_run_id, ''recall_interval_hard_overdue_mult'', 3)\n'
      || E'       AND EXTRACT(EPOCH FROM (p_sim_clock_now - v_v.dispatched_at)) / 60.0\n'
      || E'         >= ottoq_policy_get(p_sim_run_id, ''recall_min_productive_min'', 120) THEN\n'
      || E'      RETURN QUERY SELECT true,''service_interval_overdue'',''routine'',4::smallint,false,1::smallint,v_eta_min,\n'
      || E'        v_ev || jsonb_build_object(\n'
      || E'          ''pm_ratio'', round((COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0)) / NULLIF(v_pm_km, 0), 2),\n'
      || E'          ''calib_ratio'', round((COALESCE(v_w.drive_hours_total,0) - COALESCE(v_w.hours_at_last_calibration,0)) / NULLIF(v_calib_h, 0), 2),\n'
      || E'          ''out_min'', round(EXTRACT(EPOCH FROM (p_sim_clock_now - v_v.dispatched_at)) / 60.0),\n'
      || E'          ''hard_mult'', ottoq_policy_get(p_sim_run_id, ''recall_interval_hard_overdue_mult'', 3),\n'
      || E'          ''min_productive_min'', ottoq_policy_get(p_sim_run_id, ''recall_min_productive_min'', 120)); RETURN;\n'
      || E'    END IF;\n');
  IF v_new = v_def OR position('ottoq_recall_interval_scheduled_v1(' IN v_new) = 0
     OR position('service_interval_overdue' IN v_new) = 0 OR position('''service_interval_due''' IN v_new) > 0 THEN
    RAISE EXCEPTION '0447: interval_scheduled_v1 was not derived cleanly from v1';
  END IF;
  EXECUTE v_new;
END $v3$;

COMMENT ON FUNCTION public.ottoq_recall_interval_scheduled_v1(uuid,uuid,timestamp with time zone,numeric,numeric) IS
  '0447: implementation 3, interval_scheduled_v1. naive_threshold_v1 verbatim except the interval rung: PM and '
  'calibration recall only at recall_interval_hard_overdue_mult x their interval (default 3) after '
  'recall_min_productive_min deployed (default 120), as service_interval_overdue, which ottoq_derive_visit_needs makes '
  'must_do. Below that, interval maintenance is served by the night waves. Do not call directly; the wrapper records '
  'the decision.';
REVOKE ALL ON FUNCTION public.ottoq_recall_interval_scheduled_v1(uuid,uuid,timestamp with time zone,numeric,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_recall_interval_scheduled_v1(uuid,uuid,timestamp with time zone,numeric,numeric) TO authenticated, service_role;

INSERT INTO public.ottoq_recall_implementations (impl_id, implementation, evaluator_function, status, note) VALUES
  (3, 'interval_scheduled_v1', 'ottoq_recall_interval_scheduled_v1', 'parked',
   '0447 (G181). naive_threshold_v1 with interval maintenance treated as scheduled work: no recall below '
   'recall_interval_hard_overdue_mult x the interval; above it, after recall_min_productive_min, a non-deferrable '
   'service_interval_overdue whose visit makes the atom must_do. Parked: twin runs and dial experiments only, until a '
   'human marks it active.');

-- ── (2) the visit keeps the recall's promise ──
DO $splice$
DECLARE v_def text; v_new text;
  c_anchor CONSTANT text := E'      ''est_min'',v_pm_min,''concurrency'',''bay'',''requires_bay'',''service_bay'',''carryover_eligible'',true);\n  END IF;\n';
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_derive_visit_needs'::regproc);
  v_new := replace(v_def, c_anchor,
         c_anchor
      || E'  /* 0447 (G181): a vehicle recalled because its interval maintenance was hard-overdue gets that maintenance on\n'
      || E'     this visit -- the recall''s service bundle (CLAUDE.md 2.7), exactly as 0018/0019 made a rider-flag\n'
      || E'     recall''s cleaning must_do. Only interval_scheduled_v1 emits this trigger; naive_threshold_v1 never does. */\n'
      || E'  IF (SELECT d.return_trigger FROM public.ottoq_vehicle_dispatches d\n'
      || E'       WHERE d.vehicle_id = p_vehicle_id AND d.sim_run_id = v_run\n'
      || E'       ORDER BY d.dispatched_at DESC, d.dispatch_id LIMIT 1) = ''service_interval_overdue''\n'
      || E'     AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>''svc'' IN (''mechanical_pm'',''sensor_calibration'')) THEN\n'
      || E'    SELECT jsonb_agg(CASE WHEN a->>''svc'' IN (''mechanical_pm'',''sensor_calibration'')\n'
      || E'                          THEN a || jsonb_build_object(''must_do'', true, ''deferrable'', false,\n'
      || E'                                 ''carryover_eligible'', false, ''return_trigger'', ''service_interval_overdue'')\n'
      || E'                          ELSE a END ORDER BY o)\n'
      || E'      INTO v_m FROM jsonb_array_elements(v_m) WITH ORDINALITY AS t(a, o);\n'
      || E'  END IF;\n');
  IF v_new = v_def OR position('''service_interval_overdue''' IN v_new) = 0 THEN
    RAISE EXCEPTION '0447: the visit promotion did not apply';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── (3) the envelope and the two dials ──
UPDATE public.ottoq_policy_param_catalog
   SET max_value = 3,
       description = 'Which registered Recall Decision procedure decides (ottoq_recall_implementations.impl_id): '
                  || '1 = naive_threshold_v1, the live ladder; 2 = fixed_window_dummy, the swap proof; '
                  || '3 = interval_scheduled_v1 (0447), interval maintenance as scheduled work.'
 WHERE param_key = 'recall_implementation_id';

INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('recall_interval_hard_overdue_mult',
        'interval_scheduled_v1 (0447): a deployed vehicle is recalled for PM or calibration only at or over this multiple '
        'of its interval; below it the night waves schedule the work.',
        3, 1, 10, 'ottoq_recall_interval_scheduled_v1 -> service_interval_overdue', false),
       ('recall_min_productive_min',
        'interval_scheduled_v1 (0447): minimum sim-minutes deployed before an overdue-maintenance recall may fire.',
        120, 0, 480, 'ottoq_recall_interval_scheduled_v1 -> service_interval_overdue', false);

-- ── (4) the experiment the learning loop runs ──
INSERT INTO public.ottoq_dial_experiments
       (created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks, sim_start,
        primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct,
        min_effect_pct, guardrail_alpha, hypothesis, status)
VALUES ('0447', '11111111-1111-1111-1111-111111111111', 'recall_implementation_id', 1, 3, '{}'::jsonb, 'busy_day', 48,
        '2026-09-01 09:00:00+00', 'asset_hours_available_per_day', 'higher', 6, 12, 0.05, 2, 0.5, 0.2,
        'G181: treating interval maintenance as scheduled work (interval_scheduled_v1) instead of an immediate recall '
        '(naive_threshold_v1) raises asset hours available per day on busy_day without a readiness or safety '
        'regression. On 324eb0f1 v1 recalled 58 vehicles for maintenance it never serviced and met 6-16% of demand '
        'from 07:00 CT.',
        'active');

-- ── V1: implementation 3 is v1 with exactly one rung changed ──
DO $$
DECLARE v1 text; v3 text; v_back text;
  c_rung CONSTANT text :=
         E'    IF COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km\n'
      || E'       OR COALESCE(v_w.drive_hours_total,0) - COALESCE(v_w.hours_at_last_calibration,0) >= v_calib_h THEN\n'
      || E'      RETURN QUERY SELECT true,''service_interval_due'',''routine'',4::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;\n'
      || E'    END IF;\n';
BEGIN
  SELECT prosrc INTO v1 FROM pg_proc WHERE oid = 'public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamp with time zone,numeric,numeric)'::regprocedure;
  SELECT prosrc INTO v3 FROM pg_proc WHERE oid = 'public.ottoq_recall_interval_scheduled_v1(uuid,uuid,timestamp with time zone,numeric,numeric)'::regprocedure;
  -- put v1's rung back into v3 in place of everything from the 0447 comment to its END IF, and demand v1 exactly
  v_back := regexp_replace(v3, '    /\* 0447 \(G181\) interval_scheduled_v1:.*?min_productive_min'', 120\)\); RETURN;\n    END IF;\n', c_rung);
  IF md5(v_back) <> md5(v1) THEN
    RAISE EXCEPTION '0447 V1: implementation 3 differs from v1 somewhere other than the interval rung';
  END IF;
  IF (SELECT provolatile FROM pg_proc WHERE oid = 'public.ottoq_recall_interval_scheduled_v1(uuid,uuid,timestamp with time zone,numeric,numeric)'::regprocedure)
     <> (SELECT provolatile FROM pg_proc WHERE oid = 'public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamp with time zone,numeric,numeric)'::regprocedure) THEN
    RAISE EXCEPTION '0447 V1: implementation 3 does not keep v1''s volatility';
  END IF;
END $$;

-- ── V2: the registry, the envelope, the dials and the experiment are what the header says ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_recall_implementations
                  WHERE impl_id = 3 AND implementation = 'interval_scheduled_v1' AND status = 'parked'
                    AND evaluator_function = 'ottoq_recall_interval_scheduled_v1') THEN
    RAISE EXCEPTION '0447 V2: implementation 3 is not registered as parked';
  END IF;
  IF (SELECT max_value FROM public.ottoq_policy_param_catalog WHERE param_key = 'recall_implementation_id') <> 3
     OR (SELECT count(*) FROM public.ottoq_policy_param_catalog
          WHERE param_key IN ('recall_interval_hard_overdue_mult','recall_min_productive_min') AND NOT agent_writable) <> 2 THEN
    RAISE EXCEPTION '0447 V2: the envelope or the new dials are wrong';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_dial_experiments
       WHERE param_key = 'recall_implementation_id' AND control_value = 1 AND treatment_value = 3 AND status = 'active') <> 1 THEN
    RAISE EXCEPTION '0447 V2: the recall experiment is not registered exactly once';
  END IF;
  -- the incumbent is untouched: every stored recall_implementation_id is still 1
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'recall_implementation_id' AND param_value <> 1) THEN
    RAISE EXCEPTION '0447 V2: the incumbent moved';
  END IF;
END $$;

-- ── V3: the visit promotion sits after both appends and keys only on the new trigger ──
DO $$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc WHERE oid = 'ottoq.ottoq_derive_visit_needs'::regproc;
  IF position('''service_interval_overdue''' IN v_src) = 0
     OR position('''service_interval_overdue''' IN v_src) < position('''svc'',''mechanical_pm''' IN v_src)
     OR position('''service_interval_overdue''' IN v_src) < position('''svc'',''sensor_calibration''' IN v_src)
     OR position('''service_interval_due''' IN v_src) > 0 THEN
    RAISE EXCEPTION '0447 V3: the visit promotion is not where the header says, or it keys on the incumbent''s trigger';
  END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0447_the_recall_policy_and_the_visit_planner_disagreed_about_maintenance_so_vehicles_looped',
   false,
   'G181: recall implementation 3, interval_scheduled_v1 (v1 verbatim but the interval rung: recall only at '
   'recall_interval_hard_overdue_mult x the interval after recall_min_productive_min, as service_interval_overdue), '
   'registered parked; ottoq_derive_visit_needs makes PM/calibration must_do on a service_interval_overdue visit; '
   'recall_implementation_id envelope 1..3 and two catalogued dials; a v1-vs-v3 dial experiment on '
   'asset_hours_available_per_day. FALSE: the incumbent (1) is unchanged and nothing it emits reaches the promotion.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert FALSE. After applying: the dial runner pairs v1 against v3 (0439), and a demo run can select v3 at run
-- scope (`recall_implementation_id` = 3) to show it end to end. Rollback: restore ottoq_derive_visit_needs from
-- ottoq_schema_snapshots label '0447_pre', set the experiment abandoned, delete implementation 3 and its function.
