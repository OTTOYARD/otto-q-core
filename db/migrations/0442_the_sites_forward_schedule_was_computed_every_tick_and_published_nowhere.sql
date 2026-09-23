-- migration-version: PENDING
-- migration-name:    the_sites_forward_schedule_was_computed_every_tick_and_published_nowhere
--
-- 0442  **The site's forward schedule was computed every tick and published nowhere.** Since 0435 the battery
--       follows `public.ottoq_bess_day_plan`, which returns a 30-minute schedule to local midnight: forecast net
--       load, planned discharge per step, the DR reserve and prices. `ottoq_energy_orchestrate` keeps the plan's
--       scalars and drops the arrays (`v_day_plan - 'forecast' - 'discharge_plan_kw'`). The object the brief names
--       for that schedule, ServiceProfile (CLAUDE.md 2.6; `public.service_profiles`, 0043), reads
--       `ottoq_energy_plan`, which has never held a row. FINDINGS G9 (no producer) and G168 (the MPC bridge is
--       dormant); `db/checks/0056` OPEN 6 said the same of the water-fill's forward vector.
--
-- ══ §1 WHAT IS WRONG, MEASURED 2026-09-23 ════════════════════════════════════════════════════════════════════
--
--   (a) `public.service_profiles` returns 0 rows while run 324eb0f1 (busy_day, plan mode on since tick 1) is live.
--       Both halves are empty:
--       - site_power reads `ottoq_energy_plan`. Its only writer is the MPC bridge, which nothing calls: 0 rows ever.
--       - service_point keeps bookings with `upper(during) > now() - interval '1 hour'`. `during` is SIM time and
--         `now()` is REAL (0326 §1). The run's sim clock read 2026-09-22 ~05:00 CT while now() read 2026-09-23
--         02:25 UTC, so every held or active booking of a sim run is filtered out.
--   (b) The schedule the view was built to show is computed every tick and discarded. The plan that replaced the
--       water-fill inherited 0056 OPEN 6's gap.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `ottoq_energy_plan` gains `ev_allowance_kw numeric[]` and `detail jsonb`, both nullable, and a partial index
--       on the applied rows of a run, which the publisher reads every tick.
--   (2) `public.ottoq_publish_day_plan(run, depot, clock, tick_seq, plan, bess_now_kw, charge_cap_now_kw)`. Step k
--       covers [clock + 30(k-1) min, clock + 30k min), exactly the plan's own steps.
--       - `bess_setpoint_kw[k]`: step 1 is the setpoint the orchestrator just issued; later steps are the plan's
--         discharge.
--       - `grid_import_kw[k]` = max(0, net[k] - bess[k]); `forecast_load_kw` is the plan's net forecast.
--       - `ev_allowance_kw[k]`: step 1 is the charge cap the orchestrator just issued. Later steps apply the
--         orchestrator's own plan-mode formula, max(50, level_k - base[k] + solar[k] + max(bess[k], 0)), with
--         level_k clamped to the active DR call's cap for steps that begin before the call expires.
--       - `predicted_peak_kw` = max(grid_import_kw).
--       The run's previous applied day-plan profile becomes `superseded` and the new one is `applied`, so the view
--       shows one site-power profile per run: the one in force.
--   (3) The orchestrator calls it after writing its commands, only when the day plan succeeded and MPC-follow is
--       off. The call sits in an exception block, so a failed publication is a warning and never a stopped tick.
--   (4) `public.service_profiles`:
--       - site_power periods add `rate_unit`, `start_period_s` (explicit offsets per step), `ev_allowance_kw`,
--         `source`, `profile_id` and the plan's detail;
--       - `published_at` is the publisher's own clock when it gives one (sim time on sim runs);
--       - service_point compares booking windows with the run's own sim clock (`now()` only for production rows)
--         and publishes `booked_at_sim`.
--       Columns, grants and `security_invoker` are unchanged.
--
-- ══ §3 forces_recert FALSE ═══════════════════════════════════════════════════════════════════════════════════
--
--   - The orchestrator's new statement runs only when the day plan ran, and certification runs never reach plan
--     mode. P2 re-proves 0435 P3: no depot or global row turns `energy_reserve_shave` on.
--   - No atom reads `ottoq_energy_plan`; `h_nrg` digests `ottoq_energy_commands`. P2 proves it from source.
--   - No function reads `service_profiles` (P2).
--   - A dial-experiment treatment arm publishes, which changes no atom and no metric of `ottoq_dial_arm_metrics`.
--
-- ══ §4 NOT DONE ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - No OCPP semantics are claimed. Profile purpose, stackLevel, EVSE targeting and W versus A belong to the
--     adapter boundary (C10), with sources. This file supplies what any of them needs first: a profile that
--     exists, explicit period offsets, a declared unit, and an identity that supersedes its predecessor.
--   - The MPC bridge is left as it is. Its follow branch reads only `plan_state = 'ready'`, which the publisher
--     never writes (V3).

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0442 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%' OR query ILIKE '%ottoq_dial_experiment_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0442 P0: a determinism or dial pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0442 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: the orchestrator, the view and the table as read on 2026-09-23; what this creates does not exist ──
DO $$
DECLARE v_src text; v_n int;
  c_anchor CONSTANT text := E'             ELSE ''{}''::jsonb END);   /* 0435 */\n  RETURN round(v_charge_cap,1);';
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure;
  IF md5(v_src) <> '7b5f7d9a0bb7432cfe733c473a36437f' THEN RAISE EXCEPTION '0442 P1: ottoq_energy_orchestrate md5 is %', md5(v_src); END IF;
  v_n := (length(v_src) - length(replace(v_src, c_anchor, ''))) / length(c_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0442 P1: the orchestrator anchor matched % times', v_n; END IF;
  IF md5(pg_get_viewdef('public.service_profiles'::regclass, true)) <> '32824b909ace4396c5b9eea926418c95' THEN
    RAISE EXCEPTION '0442 P1: service_profiles md5 is %', md5(pg_get_viewdef('public.service_profiles'::regclass, true));
  END IF;
  -- the plan carries the arrays the publisher reads
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure;
  IF position('''net_kw''' IN v_src) = 0 OR position('''base_kw''' IN v_src) = 0 OR position('''solar_kw''' IN v_src) = 0
     OR position('''discharge_plan_kw''' IN v_src) = 0 OR position('''horizon_steps''' IN v_src) = 0 THEN
    RAISE EXCEPTION '0442 P1: ottoq_bess_day_plan no longer returns the forecast and discharge arrays';
  END IF;
  -- the table's arrays are numeric[], which the publisher writes
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_energy_plan'
         AND column_name IN ('bess_setpoint_kw','grid_import_kw','forecast_load_kw') AND udt_name = '_numeric') <> 3 THEN
    RAISE EXCEPTION '0442 P1: ottoq_energy_plan''s schedule arrays are not numeric[]';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_energy_plan'
                AND column_name IN ('ev_allowance_kw','detail'))
     OR to_regprocedure('public.ottoq_publish_day_plan(uuid,uuid,timestamp with time zone,bigint,jsonb,numeric,numeric)') IS NOT NULL THEN
    RAISE EXCEPTION '0442 P1: the publication objects already exist';
  END IF;
END $$;

-- ── P2: the premises forces_recert FALSE rests on ──
DO $$
DECLARE v_readers text;
BEGIN
  -- certification runs never reach plan mode (0435 P3), and nothing follows an MPC plan at depot or global scope
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params
              WHERE param_key IN ('energy_reserve_shave', 'energy_mpc_follow') AND scope_type IN ('depot','global')
                AND param_value >= 0.5) THEN
    RAISE EXCEPTION '0442 P2: energy_reserve_shave or energy_mpc_follow is on at depot/global scope';
  END IF;
  -- no atom or fingerprint reads the plan table, and nothing reads the view
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_readers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND (p.proname ILIKE '%atom%' OR p.proname ILIKE '%fingerprint%' OR p.proname IN ('ottoq_determinism_pair','ottoq_ab_pair'))
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') ~ 'ottoq_energy_plan\M';
  IF v_readers IS NOT NULL THEN RAISE EXCEPTION '0442 P2: % read(s) ottoq_energy_plan -- a published plan would move an atom', v_readers; END IF;
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_readers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') ~ 'service_profiles';
  IF v_readers IS NOT NULL THEN RAISE EXCEPTION '0442 P2: % read(s) service_profiles', v_readers; END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0442_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure;
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0442_pre', 'view', 'public', 'service_profiles',
       pg_get_viewdef('public.service_profiles'::regclass, true),
       md5(pg_get_viewdef('public.service_profiles'::regclass, true));

-- ── (1) THE TABLE ──
ALTER TABLE public.ottoq_energy_plan
  ADD COLUMN ev_allowance_kw numeric[],
  ADD COLUMN detail jsonb;
COMMENT ON COLUMN public.ottoq_energy_plan.ev_allowance_kw IS
  '0442: per step, the EV charging the plan leaves room for (kW). Step 1 is the charge cap the orchestrator issued; '
  'later steps apply its plan-mode formula max(50, level - base + solar + max(bess, 0)), level clamped to an active '
  'DR call''s cap for steps that begin before the call expires.';
COMMENT ON COLUMN public.ottoq_energy_plan.detail IS
  '0442: the publisher''s context -- publication clock (sim time on sim runs), tick, level, DR clamp, prices, the '
  'DR reserve per step and the plan''s scalars.';
CREATE INDEX ottoq_energy_plan_applied ON public.ottoq_energy_plan (sim_run_id, depot_id) WHERE plan_state = 'applied';

-- ── (2) THE PUBLISHER ──
CREATE OR REPLACE FUNCTION public.ottoq_publish_day_plan(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz,
                                                         p_tick_seq bigint, p_plan jsonb, p_bess_now_kw numeric,
                                                         p_charge_cap_now_kw numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/* 0442 (G9, G168): persist the day plan the battery just acted on as the site's forward schedule, the site_power
   ServiceProfile, superseding the run's previous one. Step k covers [clock + 30(k-1) min, clock + 30k min), the plan's
   own steps. Arithmetic over the plan's arrays; the one read is the active DR call, by the orchestrator's own query. */
DECLARE
  v_n int; v_step numeric; v_level numeric; k int; v_start timestamptz; v_lvl numeric; v_id uuid;
  v_net numeric[]; v_dis numeric[]; v_base numeric[]; v_solar numeric[];
  v_bess numeric[] := '{}'; v_grid numeric[] := '{}'; v_allow numeric[] := '{}';
  v_dr_cap numeric; v_dr_end timestamptz;
BEGIN
  IF NOT COALESCE((p_plan->>'ok')::boolean, false) THEN RETURN NULL; END IF;
  v_n     := (p_plan->>'horizon_steps')::int;
  v_step  := COALESCE((p_plan->>'step_min')::numeric, 30);
  v_level := (p_plan->>'level_kw')::numeric;
  SELECT array_agg(x::numeric ORDER BY o) INTO v_net
    FROM jsonb_array_elements_text(p_plan->'forecast'->'net_kw') WITH ORDINALITY AS t(x, o);
  SELECT array_agg(x::numeric ORDER BY o) INTO v_dis
    FROM jsonb_array_elements_text(p_plan->'discharge_plan_kw') WITH ORDINALITY AS t(x, o);
  SELECT array_agg(x::numeric ORDER BY o) INTO v_base
    FROM jsonb_array_elements_text(p_plan->'forecast'->'base_kw') WITH ORDINALITY AS t(x, o);
  SELECT array_agg(x::numeric ORDER BY o) INTO v_solar
    FROM jsonb_array_elements_text(p_plan->'forecast'->'solar_kw') WITH ORDINALITY AS t(x, o);
  IF v_n IS NULL OR v_n < 1 OR v_level IS NULL
     OR COALESCE(array_length(v_net, 1), 0) < v_n OR COALESCE(array_length(v_dis, 1), 0) < v_n
     OR COALESCE(array_length(v_base, 1), 0) < v_n OR COALESCE(array_length(v_solar, 1), 0) < v_n THEN
    RAISE EXCEPTION '0442: the plan does not carry % steps of forecast and discharge', v_n;
  END IF;

  -- the DR call the orchestrator clamped its level to (its query, its order), and when that call ends
  SELECT required_load_cap_kw, expires_at INTO v_dr_cap, v_dr_end FROM ottoq_dr_calls
   WHERE COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
     AND depot_id = p_depot_id AND call_status IN ('active','issued') AND expires_at > p_sim_clock
   ORDER BY required_load_cap_kw ASC, dr_call_id LIMIT 1;

  FOR k IN 1..v_n LOOP
    v_start := p_sim_clock + make_interval(secs => ((k - 1) * v_step * 60)::double precision);
    v_bess  := v_bess || CASE WHEN k = 1 THEN COALESCE(p_bess_now_kw, v_dis[1]) ELSE v_dis[k] END;
    v_grid  := v_grid || GREATEST(0, v_net[k] - v_bess[k]);
    v_lvl   := CASE WHEN v_dr_cap IS NOT NULL AND v_start < v_dr_end THEN LEAST(v_level, v_dr_cap) ELSE v_level END;
    v_allow := v_allow || CASE WHEN k = 1 AND p_charge_cap_now_kw IS NOT NULL THEN p_charge_cap_now_kw
                               ELSE GREATEST(50, v_lvl - v_base[k] + v_solar[k] + GREATEST(v_bess[k], 0)) END;
  END LOOP;

  UPDATE ottoq_energy_plan SET plan_state = 'superseded'
   WHERE sim_run_id = p_sim_run_id AND depot_id = p_depot_id AND source = 'day_plan' AND plan_state = 'applied';

  INSERT INTO ottoq_energy_plan (sim_run_id, depot_id, plan_start_clock, tick_minutes, horizon_steps,
                                 bess_setpoint_kw, grid_import_kw, forecast_load_kw, predicted_peak_kw,
                                 solver, status, source, request_id, latency_ms, plan_state, ev_allowance_kw, detail)
  VALUES (p_sim_run_id, p_depot_id, p_sim_clock, v_step, v_n,
          v_bess, v_grid, v_net[1:v_n], (SELECT max(g) FROM unnest(v_grid) AS g),
          'ottoq_bess_day_plan', 'ok', 'day_plan', NULL, round(NULLIF(p_plan->>'solve_ms', '')::numeric)::int, 'applied',
          v_allow,
          jsonb_build_object('published_at', p_sim_clock, 'tick_seq', p_tick_seq, 'level_kw', v_level,
                             'mode', p_plan->'mode', 'dr_cap_kw', v_dr_cap, 'dr_expires_at', v_dr_end,
                             'price', p_plan->'forecast'->'price', 'reserve_kwh', p_plan->'forecast'->'reserve_kwh',
                             'plan', p_plan - 'forecast' - 'discharge_plan_kw'))
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;
REVOKE ALL ON FUNCTION public.ottoq_publish_day_plan(uuid, uuid, timestamp with time zone, bigint, jsonb, numeric, numeric)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_publish_day_plan(uuid, uuid, timestamp with time zone, bigint, jsonb, numeric, numeric)
  TO service_role;

-- ── (3) THE ORCHESTRATOR PUBLISHES WHAT IT JUST ACTED ON ──
DO $splice$
DECLARE v_def text; v_new text;
  c_anchor CONSTANT text := E'             ELSE ''{}''::jsonb END);   /* 0435 */\n  RETURN round(v_charge_cap,1);';
BEGIN
  v_def := pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  v_new := replace(v_def, c_anchor,
       E'             ELSE ''{}''::jsonb END);   /* 0435 */\n'
    || E'  /* 0442 (G9, G168): the plan the battery just acted on is the site''s forward schedule. Publish it as the\n'
    || E'     site_power ServiceProfile, superseding the last one. Plan mode only, so no certification arm publishes;\n'
    || E'     a failed publication is a warning, never a stopped tick. */\n'
    || E'  IF COALESCE((v_day_plan->>''ok'')::boolean, false) AND NOT v_mpc_follow THEN\n'
    || E'    BEGIN\n'
    || E'      PERFORM public.ottoq_publish_day_plan(p_sim_run_id, p_depot_id, p_sim_clock, p_tick_seq, v_day_plan,\n'
    || E'                                            round(v_bess_dispatch, 1), round(v_charge_cap, 1));\n'
    || E'    EXCEPTION WHEN OTHERS THEN\n'
    || E'      RAISE WARNING ''0442: day plan publication failed at tick %: %'', p_tick_seq, SQLERRM;\n'
    || E'    END;\n'
    || E'  END IF;\n'
    || E'  RETURN round(v_charge_cap,1);');
  IF v_new = v_def OR position('ottoq_publish_day_plan' IN v_new) = 0 THEN
    RAISE EXCEPTION '0442 (3): the orchestrator splice did not apply';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── (4) THE VIEW: a published profile, on the run's own clock ──
CREATE OR REPLACE VIEW public.service_profiles
  WITH (security_invoker = true) AS
SELECT 'site_power'        AS resource_kind,
       p.depot_id          AS site_id,
       NULL::uuid          AS service_point_id,
       p.sim_run_id,
       COALESCE((p.detail->>'published_at')::timestamptz, p.created_at) AS published_at,
       p.plan_start_clock  AS window_start,
       p.plan_start_clock
         + make_interval(mins => (p.tick_minutes * p.horizon_steps)::int)
                           AS window_end,
       jsonb_build_object(
         'tick_minutes',     p.tick_minutes,
         'rate_unit',        'kW',
         'start_period_s',   (SELECT jsonb_agg(((i - 1) * p.tick_minutes * 60)::int ORDER BY i)
                                FROM generate_series(1, p.horizon_steps) AS i),
         'bess_setpoint_kw', to_jsonb(p.bess_setpoint_kw),
         'grid_import_kw',   to_jsonb(p.grid_import_kw),
         'forecast_load_kw', to_jsonb(p.forecast_load_kw),
         'ev_allowance_kw',  to_jsonb(p.ev_allowance_kw),
         'predicted_peak_kw', p.predicted_peak_kw,
         'solver',           p.solver,
         'source',           p.source,
         'profile_id',       p.id,
         'detail',           p.detail) AS periods,
       p.plan_state         AS profile_state
  FROM public.ottoq_energy_plan p
 WHERE p.plan_state IN ('ready','applied','pending')
UNION ALL
SELECT 'service_point', s.depot_id, b.stall_id, b.sim_run_id,
       COALESCE(b.booked_at_sim, b.booked_at), lower(b.during), upper(b.during),
       jsonb_build_object('operation', COALESCE(oc.operation_code, b.purpose),
                          'asset_id', b.vehicle_id,
                          'booking_state', b.state),
       b.state
  FROM public.ottoq_stall_bookings b
  JOIN public.stalls s ON s.id = b.stall_id
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = b.sim_run_id
  LEFT JOIN public.ottoq_operation_catalog oc
         ON oc.booking_purpose = b.purpose AND oc.pack_id = 'robotaxi'
 WHERE b.state IN ('held','active')
   AND upper(b.during) > COALESCE(r.sim_clock_current, now()) - interval '1 hour';   -- 0442: the run's own clock
COMMENT ON VIEW public.service_profiles IS
  'ServiceProfile (CLAUDE.md 2.6): the published forward schedule. site_power: the profile in force per run '
  '(ottoq_energy_plan, plan_state ready/applied/pending; the day plan publishes applied and supersedes its '
  'predecessor, 0442), with explicit per-step offsets and a declared unit. service_point: held/active bookings whose '
  'window ends after the run''s own sim clock minus an hour (now() only for production rows).';

-- ── V1: the publisher, on a synthetic plan against a real run, rolled back ──
DO $v1$
DECLARE
  v_run uuid; v_clock timestamptz; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  v_plan jsonb; v_a uuid; v_b uuid; r record; v_msg text; v_sp record;
BEGIN
  -- the latest run that is not live, so the probe never touches a running run's world
  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = v_depot AND status NOT IN ('running','paused') ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION '0442 V1: no finished run on the twin depot to publish against'; END IF;
  v_clock := v_clock + interval '3 days';   -- after any DR call of the run, so the first check is unclamped
  v_plan := jsonb_build_object('ok', true, 'plan', '0435', 'mode', 'shave', 'level_kw', 500, 'horizon_steps', 4,
                               'step_min', 30, 'solve_ms', 12,
                               'forecast', jsonb_build_object('net_kw', '[600,700,400,300]'::jsonb,
                                                              'base_kw', '[100,100,100,100]'::jsonb,
                                                              'solar_kw', '[200,100,0,0]'::jsonb,
                                                              'ev_kw', '[700,700,300,200]'::jsonb,
                                                              'price', '[0.1,0.1,0.2,0.2]'::jsonb,
                                                              'reserve_kwh', '[600,600,600,600]'::jsonb),
                               'discharge_plan_kw', '[100,200,0,0]'::jsonb);
  BEGIN
    v_a := public.ottoq_publish_day_plan(v_run, v_depot, v_clock, 1, v_plan, 90, 480);
    SELECT * INTO r FROM public.ottoq_energy_plan WHERE id = v_a;
    IF r.bess_setpoint_kw <> ARRAY[90,200,0,0]::numeric[] OR r.grid_import_kw <> ARRAY[510,500,400,300]::numeric[]
       OR r.ev_allowance_kw <> ARRAY[480,700,400,400]::numeric[] OR r.predicted_peak_kw <> 510
       OR r.forecast_load_kw <> ARRAY[600,700,400,300]::numeric[] OR r.plan_state <> 'applied' OR r.source <> 'day_plan' THEN
      RAISE EXCEPTION '0442 V1: the published arrays are wrong: bess % grid % allow % peak %',
        r.bess_setpoint_kw, r.grid_import_kw, r.ev_allowance_kw, r.predicted_peak_kw;
    END IF;
    -- a DR call covering the first two steps clamps the second step's allowance and not the third's
    INSERT INTO public.ottoq_dr_calls (depot_id, sim_run_id, issued_at, expires_at, duration_minutes, required_load_cap_kw, reason)
    VALUES (v_depot, v_run, v_clock - interval '5 minutes', v_clock + interval '45 minutes', 50, 300, '0442_probe');
    v_b := public.ottoq_publish_day_plan(v_run, v_depot, v_clock, 2, v_plan, 90, 480);
    SELECT * INTO r FROM public.ottoq_energy_plan WHERE id = v_b;
    IF r.ev_allowance_kw <> ARRAY[480,500,400,400]::numeric[] OR (r.detail->>'dr_cap_kw')::numeric <> 300 THEN
      RAISE EXCEPTION '0442 V1: the DR clamp is wrong: allow % detail %', r.ev_allowance_kw, r.detail->'dr_cap_kw';
    END IF;
    -- the second publication superseded the first; the view shows one site-power profile for the run, the second
    IF (SELECT plan_state FROM public.ottoq_energy_plan WHERE id = v_a) <> 'superseded'
       OR (SELECT count(*) FROM public.ottoq_energy_plan WHERE sim_run_id = v_run AND source = 'day_plan' AND plan_state = 'applied') <> 1 THEN
      RAISE EXCEPTION '0442 V1: the first profile was not superseded';
    END IF;
    SELECT * INTO v_sp FROM public.service_profiles WHERE resource_kind = 'site_power' AND sim_run_id = v_run;
    IF NOT FOUND OR (v_sp.periods->>'profile_id')::uuid <> v_b OR v_sp.published_at <> v_clock
       OR v_sp.periods->'start_period_s' <> '[0,1800,3600,5400]'::jsonb OR v_sp.periods->>'rate_unit' <> 'kW'
       OR v_sp.window_end <> v_clock + interval '2 hours' OR v_sp.periods->'ev_allowance_kw' <> '[480,500,400,400]'::jsonb THEN
      RAISE EXCEPTION '0442 V1: the view does not show the profile in force: %', to_jsonb(v_sp);
    END IF;
    RAISE EXCEPTION USING MESSAGE = '0442_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> '0442_probe_rollback' THEN RAISE EXCEPTION '%', v_msg; END IF;
  END;
END $v1$;

-- ── V2: a booking is judged against its run's clock, not the wall clock, rolled back ──
DO $v2$
DECLARE v_run uuid; v_clock timestamptz; v_stall uuid; v_veh uuid; v_bk uuid; v_msg text;
BEGIN
  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status NOT IN ('running','paused')
   ORDER BY started_at DESC LIMIT 1;
  SELECT v.id INTO v_veh FROM public.vehicles v WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_veh IS NULL THEN RAISE EXCEPTION '0442 V2: no finished run or no vehicle on the twin depot'; END IF;
  -- the test only discriminates if the run's clock is more than an hour behind the wall clock
  IF v_clock > now() - interval '3 hours' THEN
    RAISE EXCEPTION '0442 V2: the latest run''s clock % is too close to now() to tell the two clocks apart', v_clock;
  END IF;
  SELECT s.id INTO v_stall FROM public.stalls s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'staging'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b WHERE b.stall_id = s.id AND b.sim_run_id = v_run
                        AND b.during && tstzrange(v_clock, v_clock + interval '40 minutes'))
   ORDER BY s.id LIMIT 1;
  BEGIN
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_by, source, booked_at_sim)
    VALUES (v_run, v_stall, v_veh, 'temp_hold', tstzrange(v_clock + interval '10 minutes', v_clock + interval '40 minutes'),
            'held', '0442_probe', '0442_probe', v_clock)
    RETURNING booking_id INTO v_bk;
    IF NOT EXISTS (SELECT 1 FROM public.service_profiles WHERE resource_kind = 'service_point' AND sim_run_id = v_run
                      AND service_point_id = v_stall AND published_at = v_clock) THEN
      RAISE EXCEPTION '0442 V2: a held booking ahead of its run''s clock is not in the view';
    END IF;
    RAISE EXCEPTION USING MESSAGE = '0442_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> '0442_probe_rollback' THEN RAISE EXCEPTION '%', v_msg; END IF;
  END;
END $v2$;

-- ── V3: what shipped is what the header says ──
DO $$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure;
  -- the publication is conditional on the plan and on MPC-follow being off, and sits after the command insert
  IF position('IF COALESCE((v_day_plan->>''ok'')::boolean, false) AND NOT v_mpc_follow THEN' IN v_src) = 0
     OR position('ottoq_publish_day_plan' IN v_src) < position('INSERT INTO ottoq_energy_commands' IN v_src) THEN
    RAISE EXCEPTION '0442 V3: the orchestrator does not publish where and when the header says';
  END IF;
  -- the MPC follow branch still reads only ready plans, and the publisher never writes one
  IF position('plan_state = ''ready''' IN v_src) = 0 THEN
    RAISE EXCEPTION '0442 V3: the MPC follow branch no longer filters on ready';
  END IF;
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_publish_day_plan(uuid,uuid,timestamp with time zone,bigint,jsonb,numeric,numeric)'::regprocedure;
  IF position('''ready''' IN v_src) > 0 THEN RAISE EXCEPTION '0442 V3: the publisher writes a ready plan'; END IF;
  -- the view kept its grants' target and its security mode
  IF (SELECT reloptions FROM pg_class WHERE oid = 'public.service_profiles'::regclass) IS DISTINCT FROM ARRAY['security_invoker=true'] THEN
    RAISE EXCEPTION '0442 V3: service_profiles lost security_invoker';
  END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0442_the_sites_forward_schedule_was_computed_every_tick_and_published_nowhere',
   false,
   'G9/G168: ottoq_publish_day_plan persists the day plan the battery acted on into ottoq_energy_plan (source '
   'day_plan, plan_state applied, predecessor superseded; bess, grid, net forecast, EV allowance with the DR clamp). '
   'ottoq_energy_orchestrate calls it in plan mode only, after its command insert, in an exception block. '
   'service_profiles: explicit step offsets, a declared unit, the profile in force, and bookings judged on the run''s '
   'own clock. FALSE: certification runs never reach plan mode (P2), no atom reads ottoq_energy_plan (P2), nothing '
   'reads the view.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert FALSE. After applying: the next armed run (or a dial-experiment treatment arm) writes one applied
-- profile per run into ottoq_energy_plan, and `SELECT * FROM service_profiles WHERE resource_kind = 'site_power'`
-- shows it. Rollback: restore ottoq_energy_orchestrate and service_profiles from ottoq_schema_snapshots label
-- '0442_pre'; the two columns, the index and the publisher can stay.
