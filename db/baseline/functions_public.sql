-- GENERATED / SNAPSHOT FILE — DO NOT EDIT. Changes go in db/migrations/.
-- ---------------------------------------------------------------------------
-- Snapshot of the live otto-q-core brain (Supabase gxdrcyphqjzjsuhxuqtg).
-- Nothing reads this file at runtime. Editing it changes NOTHING about the
-- running system. To change the brain: add a numbered file in db/migrations/,
-- apply it per scripts/APPLYING.md, then re-export this baseline.
-- Baseline date: 2026-08-04 (export captured 2026-08-03; verified live 2026-08-04).
-- ---------------------------------------------------------------------------

-- ============================================================================
-- OTTO-Q-CORE  |  Supabase project gxdrcyphqjzjsuhxuqtg
-- USER-DEFINED FUNCTIONS / PROCEDURES  (schema: public)
-- ----------------------------------------------------------------------------
-- Exported verbatim via pg_get_functiondef(oid). Read-only snapshot.
-- Captured 2026-08-03 (previous capture: 2026-07-13).
-- Count: 336 user-defined routines (extension-owned functions such as PostGIS
--        are intentionally EXCLUDED; the raw public schema also contains 744
--        PostGIS/extension functions that are not part of OTTO-Q IP).
-- Order: proname, oid.  Each routine is preceded by "-- ===== <name> =====".
-- This is the source of the decide / tick / shield / metronome / energy /
-- dispatch / cuOpt / MPC logic -- the crown jewels.
--
-- NOTE: this file remains public-schema ONLY, exactly as in the 2026-07-13
--       snapshot, so its diff stays clean and comparable. The `ottoq` and
--       `twin` schemas are captured separately in db/functions_ottoq.sql and
--       db/functions_twin.sql (first-ever capture).
-- ============================================================================

-- ===== busy_day_probe_tick =====
CREATE OR REPLACE FUNCTION public.busy_day_probe_tick(p_run uuid, p_ticks integer DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE i int; v_next int; v_note text;
BEGIN
  FOR i IN 1..p_ticks LOOP
    v_note := '';
    BEGIN PERFORM ottoq_sim_advance_tick_world(p_run);
    EXCEPTION WHEN OTHERS THEN v_note := v_note || 'world_err:'||SQLERRM||' '; END;
    BEGIN PERFORM ottoq_sim_decide_and_dispatch(p_run);
    EXCEPTION WHEN OTHERS THEN v_note := v_note || 'decide_err:'||SQLERRM||' '; END;

    SELECT COALESCE(max(tick_no),0)+1 INTO v_next FROM busy_day_tick_probe_2026_08_01 WHERE run_id=p_run;
    INSERT INTO busy_day_tick_probe_2026_08_01
      (run_id, tick_no, sim_clock, at_gate, en_route, deployed, charging, in_bay, staged_svc, holding,
       occupied_stalls, dispatch_active, dispatch_returning, dispatch_completed, notes)
    SELECT p_run, v_next,
      (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id=p_run),
      count(*) FILTER (WHERE current_state='arrived_at_gate'),
      count(*) FILTER (WHERE current_state='en_route_to_depot'),
      count(*) FILTER (WHERE current_state='deployed'),
      count(*) FILTER (WHERE current_state::text LIKE 'charging%'),
      count(*) FILTER (WHERE current_state::text LIKE 'in_%bay'),
      count(*) FILTER (WHERE current_state='staged_awaiting_service'),
      count(*) FILTER (WHERE current_state='charge_complete_holding'),
      (SELECT count(*) FROM stalls WHERE depot_id='11111111-1111-1111-1111-111111111111' AND current_vehicle_id IS NOT NULL),
      (SELECT count(*) FROM ottoq_vehicle_dispatches WHERE sim_run_id=p_run AND status='active'),
      (SELECT count(*) FROM ottoq_vehicle_dispatches WHERE sim_run_id=p_run AND status='returning'),
      (SELECT count(*) FROM ottoq_vehicle_dispatches WHERE sim_run_id=p_run AND status='completed'),
      NULLIF(v_note,'')
    FROM vehicles WHERE home_depot_id='11111111-1111-1111-1111-111111111111' AND category='autonomous';
  END LOOP;
END $function$

-- ===== cuopt_invocation_log_append_only =====
CREATE OR REPLACE FUNCTION public.cuopt_invocation_log_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  RAISE EXCEPTION 'cuopt_invocation_log is append-only: UPDATE is not permitted';
END;
$function$

-- ===== cuopt_log_gate =====
CREATE OR REPLACE FUNCTION public.cuopt_log_gate(p_run uuid, p_reason text, p_cands integer DEFAULT NULL::integer, p_detail jsonb DEFAULT NULL::jsonb, p_t0 timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT 'sql_gate:v2'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_tick bigint; v_clock timestamptz;
BEGIN
  IF p_run IS NOT NULL THEN
    SELECT tick_count, sim_clock_current INTO v_tick, v_clock
      FROM public.ottoq_sim_runs WHERE sim_run_id = p_run;
  END IF;
  INSERT INTO public.cuopt_invocation_log
    (sim_run_id, stage, tick_seq, sim_clock, called_at, candidates_in,
     abstained_reason, latency_ms, source_note, detail)
  VALUES
    (p_run, 'sql_gate', v_tick, v_clock, COALESCE(p_t0, clock_timestamp()), p_cands,
     p_reason,
     CASE WHEN p_t0 IS NULL THEN NULL
          ELSE (EXTRACT(EPOCH FROM (clock_timestamp() - p_t0)) * 1000)::int END,
     p_note, p_detail);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cuopt_invocation_log write FAILED (reason=%): % / %', p_reason, SQLSTATE, SQLERRM;
END;
$function$

-- ===== does_task_trigger_oem_gate =====
CREATE OR REPLACE FUNCTION public.does_task_trigger_oem_gate(p_task_id uuid)
 RETURNS TABLE(triggers_gate boolean, mode text, timeout_seconds integer, on_timeout text, is_final_stage boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_mode TEXT;
  v_timeout INTEGER;
  v_on_timeout TEXT;
  v_task_seq INTEGER;
  v_max_seq INTEGER;
  v_is_final BOOLEAN;
  v_schedule_id UUID;
  v_oem_state TEXT;
BEGIN
  SELECT fo.progression_acceptance_mode,
         fo.oem_acceptance_timeout_seconds,
         fo.oem_acceptance_on_timeout,
         t.sequence_order,
         t.vehicle_schedule_id,
         t.oem_acceptance_state
  INTO v_mode, v_timeout, v_on_timeout, v_task_seq, v_schedule_id, v_oem_state
  FROM schedule_tasks t
  JOIN vehicles v ON v.id = t.vehicle_id
  LEFT JOIN fleet_operators fo ON fo.id = v.fleet_operator_id
  WHERE t.id = p_task_id;

  IF v_mode IS NULL THEN
    RETURN QUERY SELECT FALSE, 'auto'::TEXT, 180, 'auto_accept'::TEXT, FALSE;
    RETURN;
  END IF;

  -- Compute whether this is the final non-terminal task in the chain.
  SELECT MAX(sequence_order) INTO v_max_seq
  FROM schedule_tasks
  WHERE vehicle_schedule_id = v_schedule_id
    AND status NOT IN ('skipped','cancelled');

  v_is_final := (v_task_seq >= COALESCE(v_max_seq, v_task_seq));

  -- If the OEM gate has already reached a terminal state for this task, the
  -- gate must not fire again. Re-entry after /oem-accept or after a timeout
  -- auto-accept should flow straight through to the next progression stage
  -- (final redeploy / staged_for_departure).
  IF v_oem_state IN ('accepted','auto_accepted_on_timeout','rejected') THEN
    RETURN QUERY SELECT FALSE, v_mode, v_timeout, v_on_timeout, v_is_final;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    CASE
      WHEN v_mode = 'auto' THEN FALSE
      WHEN v_mode = 'tech_confirm_only' THEN FALSE
      WHEN v_mode = 'oem_webhook_required' THEN TRUE
      WHEN v_mode = 'oem_webhook_final_only' THEN v_is_final
      ELSE FALSE
    END,
    v_mode,
    v_timeout,
    v_on_timeout,
    v_is_final;
END;
$function$

-- ===== evaluate_slo_breach =====
CREATE OR REPLACE FUNCTION public.evaluate_slo_breach(p_slo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  slo RECORD;
  window_start TIMESTAMPTZ;
  observed_acc NUMERIC;
  sample_count INTEGER;
  passing_pct NUMERIC;
  severity TEXT := 'info';
  breached BOOLEAN := FALSE;
  breached_threshold NUMERIC;
BEGIN
  SELECT * INTO slo FROM accuracy_slos WHERE id = p_slo_id AND is_active;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'slo_not_found_or_inactive');
  END IF;

  window_start := NOW() - (slo.evaluation_window_hours || ' hours')::INTERVAL;

  -- % of predictions in window that passed the accuracy_threshold
  SELECT
    AVG(po.accuracy_score)::NUMERIC,
    COUNT(*)::INTEGER,
    (SUM(CASE WHEN po.accuracy_score >= slo.accuracy_threshold THEN 1 ELSE 0 END)::NUMERIC
     / NULLIF(COUNT(*), 0))::NUMERIC
  INTO observed_acc, sample_count, passing_pct
  FROM prediction_outcomes po
  WHERE (slo.depot_id IS NULL OR po.depot_id = slo.depot_id)
    AND po.prediction_type = slo.prediction_type
    AND (slo.time_horizon_hours IS NULL OR po.time_horizon_hours = slo.time_horizon_hours)
    AND po.scored_at >= window_start;

  -- Not enough samples — don't alert
  IF sample_count < slo.min_samples THEN
    RETURN jsonb_build_object(
      'slo_id', p_slo_id,
      'status', 'insufficient_samples',
      'sample_count', sample_count,
      'min_samples', slo.min_samples
    );
  END IF;

  -- Determine severity
  IF passing_pct < slo.critical_at THEN
    severity := 'critical';
    breached := TRUE;
    breached_threshold := slo.critical_at;
  ELSIF passing_pct < slo.warning_at THEN
    severity := 'warning';
    breached := TRUE;
    breached_threshold := slo.warning_at;
  ELSIF passing_pct < slo.slo_target THEN
    severity := 'info';
    breached := FALSE;
    breached_threshold := slo.slo_target;
  ELSE
    severity := 'info';
    breached := FALSE;
    breached_threshold := slo.slo_target;
  END IF;

  RETURN jsonb_build_object(
    'slo_id', p_slo_id,
    'status', CASE WHEN breached THEN 'breached' ELSE 'healthy' END,
    'severity', severity,
    'observed_accuracy', observed_acc,
    'passing_pct', passing_pct,
    'sample_count', sample_count,
    'window_start', window_start,
    'window_end', NOW(),
    'threshold_breached', breached_threshold,
    'slo_target', slo.slo_target,
    'warning_at', slo.warning_at,
    'critical_at', slo.critical_at
  );
END;
$function$

-- ===== get_active_model_version =====
CREATE OR REPLACE FUNCTION public.get_active_model_version(p_depot_id uuid, p_parameter_group text, p_ab_hash_input text DEFAULT NULL::text)
 RETURNS TABLE(version_id uuid, version_tag text, ab_test_id uuid, ab_variant text, parameters jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  active_test RECORD;
  hash_bucket INTEGER;
BEGIN
  -- Is there a running A/B test for this group?
  SELECT * INTO active_test
  FROM ab_tests
  WHERE depot_id = p_depot_id
    AND parameter_group = p_parameter_group
    AND status = 'running'
  LIMIT 1;

  IF FOUND AND p_ab_hash_input IS NOT NULL THEN
    -- Deterministic routing: hash the input, bucket into 100, compare to split
    hash_bucket := ABS(hashtext(p_ab_hash_input)) % 100;

    IF hash_bucket < active_test.traffic_split_pct THEN
      -- Route to variant B
      RETURN QUERY
        SELECT mv.id, mv.version_tag, active_test.id, 'B'::TEXT, mv.parameters
        FROM model_versions mv
        WHERE mv.id = active_test.variant_b_version_id;
      RETURN;
    ELSE
      -- Route to variant A
      RETURN QUERY
        SELECT mv.id, mv.version_tag, active_test.id, 'A'::TEXT, mv.parameters
        FROM model_versions mv
        WHERE mv.id = active_test.variant_a_version_id;
      RETURN;
    END IF;
  END IF;

  -- No running test — return the single active version
  RETURN QUERY
    SELECT mv.id, mv.version_tag, NULL::UUID, NULL::TEXT, mv.parameters
    FROM model_versions mv
    WHERE mv.depot_id = p_depot_id
      AND mv.parameter_group = p_parameter_group
      AND mv.status = 'active'
    ORDER BY mv.version_number DESC
    LIMIT 1;
END;
$function$

-- ===== get_fleet_operator_id =====
CREATE OR REPLACE FUNCTION public.get_fleet_operator_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT id FROM fleet_operators WHERE auth_user_id = auth.uid() LIMIT 1;
$function$

-- ===== get_retail_member_id =====
CREATE OR REPLACE FUNCTION public.get_retail_member_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT id FROM retail_members WHERE auth_user_id = auth.uid() LIMIT 1;
$function$

-- ===== get_staff_depot_id =====
CREATE OR REPLACE FUNCTION public.get_staff_depot_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT depot_id FROM staff_users WHERE auth_user_id = auth.uid() LIMIT 1;
$function$

-- ===== has_blocking_exception =====
CREATE OR REPLACE FUNCTION public.has_blocking_exception(p_vehicle_id uuid, p_stage text DEFAULT 'next_stall'::text)
 RETURNS TABLE(has_block boolean, exception_id uuid, exception_type text, severity text, required_resolver_role text, audit_note text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    TRUE AS has_block,
    e.id,
    e.exception_type::TEXT,
    e.severity::TEXT,
    e.required_resolver_role,
    e.audit_note
  FROM exceptions e
  WHERE e.vehicle_id = p_vehicle_id
    AND e.blocks_progression = TRUE
    AND e.status IN ('open','acknowledged','in_progress','escalated')
    AND (
      e.resolution_required_before IS NULL
      OR e.resolution_required_before = p_stage
      OR (e.resolution_required_before = 'redeployment' AND p_stage IN ('next_stall','next_service','redeployment'))
      OR (e.resolution_required_before = 'next_service' AND p_stage IN ('next_stall','next_service'))
    )
  ORDER BY
    CASE e.severity::TEXT
      WHEN 'critical' THEN 1
      WHEN 'high' THEN 2
      WHEN 'medium' THEN 3
      WHEN 'low' THEN 4
      ELSE 5
    END
  LIMIT 1;

  -- If nothing returned, still return one row indicating no block.
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT;
  END IF;
END;
$function$

-- ===== log_vehicle_state_change =====
CREATE OR REPLACE FUNCTION public.log_vehicle_state_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF OLD.current_state IS DISTINCT FROM NEW.current_state THEN
    INSERT INTO vehicle_state_log (
      vehicle_id, depot_id, previous_state, new_state,
      triggered_by, stall_id, metadata
    ) VALUES (
      NEW.id,
      NEW.current_depot_id,
      OLD.current_state,
      NEW.current_state,
      'otto_q_engine',  -- Default; overridden by application layer when appropriate
      NEW.current_stall_id,
      jsonb_build_object(
        'soc_at_transition', NEW.current_soc,
        'previous_stall_id', OLD.current_stall_id
      )
    );
    NEW.last_state_change = NOW();
  END IF;
  RETURN NEW;
END;
$function$

-- ===== ottoq_ab_paired_summary =====
CREATE OR REPLACE FUNCTION public.ottoq_ab_paired_summary(p_scenario text DEFAULT NULL::text)
 RETURNS TABLE(baseline text, metric text, n_pairs integer, mean_otto_q numeric, mean_baseline numeric, mean_diff numeric, diff_stddev numeric, pct_seeds_otto_q_wins numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  RETURN QUERY
  WITH wide AS (
    SELECT ab_group_id, seed,
      MAX(CASE WHEN policy='otto_q' THEN deploys_total END) oq_deploy,
      MAX(CASE WHEN policy='otto_q' THEN fleet_ready_pct END) oq_ready,
      MAX(CASE WHEN policy='otto_q' THEN safety_violations END) oq_viol,
      MAX(CASE WHEN policy='greedy' THEN deploys_total END) g_deploy,
      MAX(CASE WHEN policy='greedy' THEN fleet_ready_pct END) g_ready,
      MAX(CASE WHEN policy='greedy' THEN safety_violations END) g_viol,
      MAX(CASE WHEN policy='fifo' THEN deploys_total END) f_deploy,
      MAX(CASE WHEN policy='fifo' THEN fleet_ready_pct END) f_ready,
      MAX(CASE WHEN policy='fifo' THEN safety_violations END) f_viol
    FROM ottoq_ab_runs
    WHERE (p_scenario IS NULL OR scenario_code = p_scenario)
    GROUP BY ab_group_id, seed
  )
  -- greedy comparisons
  SELECT 'greedy','deploys_total', count(*)::int, round(avg(oq_deploy),2), round(avg(g_deploy),2), round(avg(oq_deploy-g_deploy),2),
         round(stddev(oq_deploy-g_deploy),2), round(100.0*avg((oq_deploy>=g_deploy)::int),1) FROM wide WHERE oq_deploy IS NOT NULL AND g_deploy IS NOT NULL
  UNION ALL
  SELECT 'greedy','fleet_ready_pct', count(*)::int, round(avg(oq_ready),2), round(avg(g_ready),2), round(avg(oq_ready-g_ready),2),
         round(stddev(oq_ready-g_ready),2), round(100.0*avg((oq_ready>=g_ready)::int),1) FROM wide WHERE oq_ready IS NOT NULL AND g_ready IS NOT NULL
  UNION ALL
  SELECT 'greedy','safety_violations', count(*)::int, round(avg(oq_viol),2), round(avg(g_viol),2), round(avg(oq_viol-g_viol),2),
         round(stddev(oq_viol-g_viol),2), round(100.0*avg((oq_viol<=g_viol)::int),1) FROM wide WHERE oq_viol IS NOT NULL AND g_viol IS NOT NULL
  -- fifo comparisons
  UNION ALL
  SELECT 'fifo','deploys_total', count(*)::int, round(avg(oq_deploy),2), round(avg(f_deploy),2), round(avg(oq_deploy-f_deploy),2),
         round(stddev(oq_deploy-f_deploy),2), round(100.0*avg((oq_deploy>=f_deploy)::int),1) FROM wide WHERE oq_deploy IS NOT NULL AND f_deploy IS NOT NULL
  UNION ALL
  SELECT 'fifo','fleet_ready_pct', count(*)::int, round(avg(oq_ready),2), round(avg(f_ready),2), round(avg(oq_ready-f_ready),2),
         round(stddev(oq_ready-f_ready),2), round(100.0*avg((oq_ready>=f_ready)::int),1) FROM wide WHERE oq_ready IS NOT NULL AND f_ready IS NOT NULL
  UNION ALL
  SELECT 'fifo','safety_violations', count(*)::int, round(avg(oq_viol),2), round(avg(f_viol),2), round(avg(oq_viol-f_viol),2),
         round(stddev(oq_viol-f_viol),2), round(100.0*avg((oq_viol<=f_viol)::int),1) FROM wide WHERE oq_viol IS NOT NULL AND f_viol IS NOT NULL;
END;
$function$

-- ===== ottoq_ab_stats =====
CREATE OR REPLACE FUNCTION public.ottoq_ab_stats(p_metric text, p_baseline text, p_direction text DEFAULT 'higher_better'::text, p_scenario text DEFAULT NULL::text)
 RETURNS TABLE(metric text, baseline text, n_pairs integer, mean_otto_q numeric, mean_baseline numeric, mean_diff numeric, sd_diff numeric, within_pair_corr numeric, crn_helps boolean, t_stat numeric, ci95_halfwidth numeric, significant_bonf boolean, ottoq_wins_pct numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_sign double precision := CASE WHEN p_direction='lower_better' THEN -1 ELSE 1 END;
BEGIN
  RETURN QUERY
  WITH pairs AS (
    SELECT ab_group_id,
      MAX(CASE WHEN policy='otto_q' THEN
        (CASE p_metric WHEN 'deploys_total' THEN deploys_total WHEN 'fleet_ready_pct' THEN fleet_ready_pct
              WHEN 'safety_violations' THEN safety_violations WHEN 'enacted_total' THEN enacted_total
              WHEN 'productive_deploys' THEN productive_deploys WHEN 'unsafe_deploys' THEN unsafe_deploys END) END)::double precision oq,
      MAX(CASE WHEN policy=p_baseline THEN
        (CASE p_metric WHEN 'deploys_total' THEN deploys_total WHEN 'fleet_ready_pct' THEN fleet_ready_pct
              WHEN 'safety_violations' THEN safety_violations WHEN 'enacted_total' THEN enacted_total
              WHEN 'productive_deploys' THEN productive_deploys WHEN 'unsafe_deploys' THEN unsafe_deploys END) END)::double precision bl
    FROM ottoq_ab_runs
    WHERE (p_scenario IS NULL OR scenario_code=p_scenario)
    GROUP BY ab_group_id
  ), valid AS (SELECT oq, bl, (oq-bl) d FROM pairs WHERE oq IS NOT NULL AND bl IS NOT NULL)
  SELECT
    p_metric, p_baseline,
    count(*)::int,
    round(avg(oq)::numeric,3), round(avg(bl)::numeric,3), round(avg(d)::numeric,3),
    round(COALESCE(stddev_samp(d),0)::numeric,3),
    round(COALESCE(corr(oq,bl),0)::numeric,3),
    COALESCE(corr(oq,bl),0) > 0,
    round((CASE WHEN COALESCE(stddev_samp(d),0)=0 THEN
             CASE WHEN avg(d)=0 THEN 0 ELSE 999 END
           ELSE avg(d)/(stddev_samp(d)/sqrt(count(*))) END)::numeric,3),
    round((ottoq_t_crit_bonf3((count(*)-1)::int) * COALESCE(stddev_samp(d),0)/sqrt(GREATEST(count(*),1)))::numeric,3),
    (v_sign*avg(d) - ottoq_t_crit_bonf3((count(*)-1)::int)*COALESCE(stddev_samp(d),0)/sqrt(GREATEST(count(*),1))) > 0,
    round((100.0*avg((CASE WHEN v_sign*d >= 0 THEN 1 ELSE 0 END)))::numeric,1)
  FROM valid;
END;
$function$

-- ===== ottoq_ack_vehicle_command =====
CREATE OR REPLACE FUNCTION public.ottoq_ack_vehicle_command(p_command_id uuid, p_disposition text DEFAULT 'executed'::text, p_actor text DEFAULT 'oem_fleet'::text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_cmd ottoq_vehicle_commands%ROWTYPE; v_now timestamptz := now(); v_disp text;
BEGIN
  v_disp := lower(COALESCE(p_disposition, 'executed'));
  IF v_disp NOT IN ('confirmed','executed','refused') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'disposition must be confirmed|executed|refused');
  END IF;
  SELECT * INTO v_cmd FROM ottoq_vehicle_commands WHERE command_id = p_command_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'command_not_found'); END IF;
  IF v_cmd.status IN ('executed','refused','expired') THEN
    RETURN jsonb_build_object('ok', true, 'already_terminal', v_cmd.status, 'command_id', p_command_id);
  END IF;

  UPDATE ottoq_vehicle_commands
     SET status = v_disp,
         confirmed_at = COALESCE(confirmed_at, v_now),
         confirmed_by = p_actor,
         executed_at  = CASE WHEN v_disp = 'executed' THEN v_now ELSE executed_at END,
         payload = CASE WHEN p_reason IS NULL THEN payload
                        ELSE COALESCE(payload,'{}'::jsonb) || jsonb_build_object('ack_reason', p_reason) END
   WHERE command_id = p_command_id;

  BEGIN
    PERFORM ottoq_record_event(
      p_actor_type := 'vehicle', p_actor_id := v_cmd.vehicle_id::text,
      p_event_type := 'vehicle.command_ack', p_entity_type := 'vehicle',
      p_entity_id := v_cmd.vehicle_id,
      p_payload := jsonb_build_object('command_id', p_command_id, 'command_type', v_cmd.command_type,
        'disposition', v_disp, 'actor', p_actor, 'reason', p_reason),
      p_severity := CASE WHEN v_disp = 'refused' THEN 'warning' ELSE 'info' END,
      p_ingest_source := 'production', p_data_source := 'production', p_sim_run_id := v_cmd.sim_run_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('ok', true, 'command_id', p_command_id, 'command_type', v_cmd.command_type,
                            'status', v_disp, 'vehicle_id', v_cmd.vehicle_id);
END;
$function$

-- ===== ottoq_active_charge_cap_kw =====
CREATE OR REPLACE FUNCTION public.ottoq_active_charge_cap_kw(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT setpoint_kw
    FROM ottoq_energy_commands
   WHERE sim_run_id = p_sim_run_id AND depot_id = p_depot_id
     AND command_type = 'charge_cap_kw' AND status = 'executed'
     AND issued_at + (COALESCE(horizon_min,15) || ' minutes')::interval >= p_sim_clock
   ORDER BY issued_at DESC
   LIMIT 1;
$function$

-- ===== ottoq_active_sim_run =====
CREATE OR REPLACE FUNCTION public.ottoq_active_sim_run()
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT sim_run_id FROM ottoq_sim_runs WHERE status='running' ORDER BY started_at DESC LIMIT 1;
$function$

-- ===== ottoq_agent_board =====
CREATE OR REPLACE FUNCTION public.ottoq_agent_board(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run RECORD; v_depot uuid; v_clock timestamptz; v_board jsonb;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count, scenario_code, random_seed
    INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_run.depot_id IS NULL THEN RETURN NULL; END IF;
  v_depot := v_run.depot_id; v_clock := v_run.sim_clock_current;

  SELECT jsonb_build_object(
    'sim_clock', v_clock, 'tick', v_run.tick_count, 'scenario', v_run.scenario_code,
    'fleet', (SELECT jsonb_object_agg(current_state, n) FROM (
        SELECT current_state, count(*) n FROM vehicles
        WHERE home_depot_id = v_depot AND category='autonomous' GROUP BY 1) f),
    'inbound_60m', (SELECT count(*) FROM vehicles v JOIN ottoq_vehicle_dispatches d ON d.vehicle_id = v.id
        WHERE v.home_depot_id = v_depot AND v.current_state='en_route_to_depot'
          AND d.actual_return_at IS NULL AND d.scheduled_return_at <= v_clock + interval '60 minutes'),
    'needs', jsonb_build_object(
      'open_visits_by_urgency', (SELECT jsonb_object_agg(urgency, n) FROM (
          SELECT urgency, count(*) n FROM ottoq_visit_needs
          WHERE depot_id = v_depot AND status IN ('open','in_progress') GROUP BY 1) u),
      'pending_atoms', (SELECT jsonb_object_agg(svc, n) FROM (
          SELECT a->>'svc' svc, count(*) n FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
          WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
            AND COALESCE(a->>'status','pending') = 'pending' GROUP BY 1 ORDER BY n DESC LIMIT 8) p),
      'carryovers', (SELECT count(*) FROM ottoq_visit_needs
          WHERE depot_id = v_depot AND status='carried_over' AND created_at > now() - interval '1 day')),
    'flow', jsonb_build_object(
      'legs', (SELECT jsonb_object_agg(status, n) FROM (
          SELECT status, count(*) n FROM ottoq_itinerary_legs
          WHERE sim_run_id = p_sim_run_id GROUP BY 1) l),
      'avg_abs_deviation_min', (SELECT round(avg(abs(deviation_s))/60.0,1) FROM ottoq_itinerary_legs
          WHERE sim_run_id = p_sim_run_id AND deviation_s IS NOT NULL),
      'amendments_recent', (SELECT count(*) FROM ottoq_decisions
          WHERE sim_run_id = p_sim_run_id AND resolved_action_context='itinerary_amended'
            AND sim_clock > v_clock - interval '2 hours')),
    'energy', jsonb_build_object(
      'site', (SELECT jsonb_build_object('grid_kw', round(COALESCE(building_load_kw,0)+COALESCE(total_ev_charging_kw,0)-COALESCE(solar_generation_kw,0)),
                       'ev_kw', round(COALESCE(total_ev_charging_kw,0)), 'solar_kw', round(COALESCE(solar_generation_kw,0)))
          FROM site_energy_snapshots WHERE depot_id = v_depot AND sim_run_id = p_sim_run_id
          ORDER BY timestamp DESC LIMIT 1),
      'bess', (SELECT jsonb_build_object('soc', current_soc_pct, 'power_kw', current_power_kw)
          FROM ottoq_bess_units WHERE depot_id = v_depot LIMIT 1),
      'bess_plan', (SELECT reason FROM ottoq_energy_commands
          WHERE depot_id = v_depot AND command_type='bess_setpoint_kw'
          ORDER BY issued_at DESC LIMIT 1),
      'forecast_charge_kw_60m', (SELECT round(COALESCE(predicted_charge_kw,0))
          FROM ottoq_predict_arrivals(v_depot, v_clock, p_sim_run_id, 60))),
    'approvals_pending', (SELECT jsonb_object_agg(approval_type, n) FROM (
        SELECT approval_type, count(*) n FROM ottoq_ops_approvals
        WHERE depot_id = v_depot AND status='pending' GROUP BY 1) a),
    'exceptions', (SELECT count(*) FROM vehicles
        WHERE home_depot_id = v_depot AND current_state IN ('tow_requested','emergency_staged')),
    'assignment_last_tick', (SELECT jsonb_object_agg(outcome_status, n) FROM (
        SELECT outcome_status, count(*) n FROM ottoq_decisions
        WHERE sim_run_id = p_sim_run_id AND tick_seq = v_run.tick_count
          AND action_context='stall_assignment' GROUP BY 1) o),
    'policy', jsonb_build_object(
      'deploy_peak_fraction', ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',0.90),
      'energy_demand_factor_peak', ottoq_policy_get(p_sim_run_id,'energy_demand_factor_peak',0.50),
      'energy_demand_factor_expensive', ottoq_policy_get(p_sim_run_id,'energy_demand_factor_expensive',0.35))
  ) INTO v_board;
  RETURN v_board;
END; $function$

-- ===== ottoq_amend_apply =====
CREATE OR REPLACE FUNCTION public.ottoq_amend_apply(p_schedule_id uuid, p_amendment jsonb, p_requested_by text DEFAULT 'yard_supervisor'::text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_type     text := lower(coalesce(p_amendment->>'type',''));
  v_vehicle  uuid;
  v_depot    uuid;
  v_modtype  modification_type;
  v_reqby    trigger_source;
  v_prev     jsonb;
  v_new      jsonb;
  v_modid    uuid;
  v_base     int;
  v_code     text;
  v_sd       record;
  v_warn     text := NULL;
  v_affected int := 0;
BEGIN
  SELECT vehicle_id, depot_id INTO v_vehicle, v_depot FROM vehicle_schedules WHERE id = p_schedule_id;
  IF v_vehicle IS NULL THEN RAISE EXCEPTION 'OTTOQ_AMEND: schedule % not found', p_schedule_id; END IF;

  BEGIN v_reqby := lower(coalesce(p_requested_by,'yard_supervisor'))::trigger_source;
  EXCEPTION WHEN others THEN v_reqby := 'otto_q_engine'; v_warn := 'requested_by invalid -> otto_q_engine'; END;

  SELECT jsonb_agg(jsonb_build_object('task_id',id,'seq',sequence_order,'service',service_code,'status',status,'stall',assigned_stall_id) ORDER BY sequence_order)
    INTO v_prev FROM schedule_tasks WHERE vehicle_schedule_id = p_schedule_id;

  -- locked prefix: highest sequence_order among non-pending, non-cancelled tasks
  SELECT coalesce(max(sequence_order),0) INTO v_base
    FROM schedule_tasks WHERE vehicle_schedule_id = p_schedule_id AND status NOT IN ('pending','cancelled');

  IF v_type = 'service_add' THEN
    v_code := lower(nullif(p_amendment->>'service_code',''));
    IF v_code IS NULL THEN RAISE EXCEPTION 'OTTOQ_AMEND: service_add requires service_code'; END IF;
    SELECT id, estimated_duration_minutes, default_sequence_order
      INTO v_sd FROM service_definitions WHERE depot_id=v_depot AND lower(code)=v_code AND is_active LIMIT 1;
    IF v_sd.id IS NULL THEN RAISE EXCEPTION 'OTTOQ_AMEND: unknown/inactive service "%" at depot', v_code; END IF;
    IF EXISTS (SELECT 1 FROM schedule_tasks WHERE vehicle_schedule_id=p_schedule_id AND lower(service_code)=v_code
               AND status IN ('pending','in_progress','vehicle_en_route')) THEN
      v_warn := concat_ws('; ', v_warn, 'service already present (added anyway)');
    END IF;
    INSERT INTO schedule_tasks (vehicle_schedule_id, vehicle_id, depot_id, service_definition_id, service_code,
        sequence_order, status, scheduled_start, scheduled_end)
    VALUES (p_schedule_id, v_vehicle, v_depot, v_sd.id, v_code,
        v_base + 1000 + coalesce(v_sd.default_sequence_order,500), 'pending',
        now(), now() + make_interval(mins => coalesce(v_sd.estimated_duration_minutes,15)));
    v_modtype := 'service_add';

  ELSIF v_type = 'service_remove' THEN
    v_code := lower(nullif(p_amendment->>'service_code',''));
    UPDATE schedule_tasks SET status='cancelled', updated_at=now()
      WHERE vehicle_schedule_id=p_schedule_id AND status='pending'
        AND (id = nullif(p_amendment->>'task_id','')::uuid OR lower(service_code)=v_code);
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected=0 THEN RAISE EXCEPTION 'OTTOQ_AMEND: no PENDING task matched for removal (locked tasks cannot be removed)'; END IF;
    v_modtype := 'service_remove';

  ELSIF v_type = 'reorder' THEN
    IF p_amendment->'order' IS NULL OR jsonb_typeof(p_amendment->'order') <> 'array' THEN
      RAISE EXCEPTION 'OTTOQ_AMEND: reorder requires an "order" array of service codes'; END IF;
    v_modtype := 'full_reschedule';

  ELSIF v_type = 'stall_reassignment' THEN
    UPDATE schedule_tasks SET assigned_stall_id = nullif(p_amendment->>'stall_id','')::uuid, reordered_at=now(), updated_at=now()
      WHERE vehicle_schedule_id=p_schedule_id AND status='pending'
        AND (id = nullif(p_amendment->>'task_id','')::uuid OR lower(service_code)=lower(nullif(p_amendment->>'service_code','')));
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected=0 THEN RAISE EXCEPTION 'OTTOQ_AMEND: no PENDING task matched for stall reassignment'; END IF;
    v_modtype := 'stall_reassignment';

  ELSIF v_type = 'priority_change' THEN
    BEGIN UPDATE vehicle_schedules SET priority = (p_amendment->>'priority')::priority_tier WHERE id=p_schedule_id;
    EXCEPTION WHEN others THEN RAISE EXCEPTION 'OTTOQ_AMEND: invalid priority "%" (priority_tier)', p_amendment->>'priority'; END;
    v_modtype := 'priority_change';

  ELSIF v_type = 'departure_change' THEN
    UPDATE vehicle_schedules SET departure_time = (p_amendment->>'departure_time')::timestamptz WHERE id=p_schedule_id;
    v_modtype := 'departure_change';

  ELSE
    RAISE EXCEPTION 'OTTOQ_AMEND: unknown amendment type "%"', v_type;
  END IF;

  -- renumber pending tail (stability: locked prefix untouched) only for set/order-changing ops
  IF v_type IN ('service_add','service_remove','reorder') THEN
    WITH ord AS (
      SELECT st.id,
             row_number() OVER (
               ORDER BY
                 CASE WHEN v_type='reorder'
                      THEN coalesce(array_position(ARRAY(SELECT lower(x) FROM jsonb_array_elements_text(p_amendment->'order') x), lower(st.service_code)), 999)
                      ELSE coalesce(sd.default_sequence_order, 500) END,
                 st.sequence_order
             ) AS rn
      FROM schedule_tasks st
      LEFT JOIN service_definitions sd ON sd.id = st.service_definition_id
      WHERE st.vehicle_schedule_id = p_schedule_id AND st.status = 'pending'
    )
    UPDATE schedule_tasks t SET sequence_order = v_base + ord.rn, updated_at=now()
      FROM ord WHERE t.id = ord.id;
  END IF;

  -- keep planned_services coherent (non-cancelled service codes in execution order)
  UPDATE vehicle_schedules vs SET planned_services = coalesce((
      SELECT jsonb_agg(service_code ORDER BY sequence_order)
      FROM schedule_tasks WHERE vehicle_schedule_id=p_schedule_id AND status <> 'cancelled' AND service_code IS NOT NULL
    ), '[]'::jsonb)
   WHERE vs.id = p_schedule_id;

  SELECT jsonb_agg(jsonb_build_object('task_id',id,'seq',sequence_order,'service',service_code,'status',status,'stall',assigned_stall_id) ORDER BY sequence_order)
    INTO v_new FROM schedule_tasks WHERE vehicle_schedule_id = p_schedule_id AND status <> 'cancelled';

  INSERT INTO schedule_modifications (vehicle_id, vehicle_schedule_id, depot_id, modification_type, requested_by,
      previous_values, new_values, reason, status, vehicles_affected)
  VALUES (v_vehicle, p_schedule_id, v_depot, v_modtype, v_reqby,
      coalesce(v_prev,'[]'::jsonb), coalesce(v_new,'[]'::jsonb), p_reason, 'applied', 1)
  RETURNING id INTO v_modid;

  RETURN jsonb_build_object('applied', true, 'amendment_type', v_type, 'modification_type', v_modtype,
    'modification_id', v_modid, 'requested_by', v_reqby, 'affected', v_affected,
    'new_chain', coalesce(v_new,'[]'::jsonb), 'warning', v_warn);
END;
$function$

-- ===== ottoq_api_otto_q_decide =====
CREATE OR REPLACE FUNCTION public.ottoq_api_otto_q_decide(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE d RECORD;
BEGIN
  SELECT * INTO d FROM ottoq_sim_decide_and_dispatch(p_sim_run_id);
  RETURN jsonb_build_object(
    'contract_version', '1.0', 'endpoint', 'otto_q.decide', 'sim_run_id', p_sim_run_id,
    'decisions_built', d.out_charge_assigned, 'enacted', d.out_dispatched,
    'vehicle_commands_pending', (SELECT count(*) FROM ottoq_vehicle_commands WHERE sim_run_id=p_sim_run_id AND status='issued'),
    'energy_commands_pending',  (SELECT count(*) FROM ottoq_energy_commands  WHERE sim_run_id=p_sim_run_id AND status='pending')
  );
END $function$

-- ===== ottoq_api_twin_apply_commands =====
CREATE OR REPLACE FUNCTION public.ottoq_api_twin_apply_commands(p_sim_run_id uuid, p_clock timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_clock timestamptz; v_confirmed int;
BEGIN
  SELECT COALESCE(p_clock, sim_clock_current) INTO v_clock FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  v_confirmed := ottoq_sim_confirm_commands(p_sim_run_id, v_clock);
  RETURN jsonb_build_object(
    'contract_version', '1.0', 'endpoint', 'twin.apply_commands', 'sim_run_id', p_sim_run_id,
    'vehicle_commands_confirmed', v_confirmed
  );
END $function$

-- ===== ottoq_api_twin_get_state =====
CREATE OR REPLACE FUNCTION public.ottoq_api_twin_get_state(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'contract_version', '1.1', 'endpoint', 'twin.get_state',
    'sim_run_id', r.sim_run_id, 'depot_id', r.depot_id,
    'sim_clock', r.sim_clock_current, 'tick', r.tick_count, 'status', r.status,
    'demo_speed_x', COALESCE(r.demo_speed_x, 1.0),
    'real_seconds_per_tick', round(6.0 / GREATEST(COALESCE(r.demo_speed_x,1.0), 0.25), 2),
    'sim_minutes_per_tick', round((r.tick_interval_seconds::numeric * COALESCE(r.time_scale,1)) / 60.0, 1),
    'next_tick_due_at', r.next_tick_due_at,
    'state', ottoq_build_decision_frame(r.depot_id)
  )
  FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
$function$

-- ===== ottoq_apply_bess_setpoint =====
CREATE OR REPLACE FUNCTION public.ottoq_apply_bess_setpoint(p_bess_id uuid, p_target_kw numeric, p_max_ramp_kw numeric DEFAULT 250, p_now timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(applied_kw numeric, direction text, clamped boolean, reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_bess  ottoq_bess_units%ROWTYPE;
  v_cur   numeric;
  v_want  numeric := p_target_kw;
  v_cap   numeric;
  v_clamped boolean := false;
  v_reason text := 'ok';
  v_dir   text;
BEGIN
  SELECT * INTO v_bess FROM ottoq_bess_units WHERE bess_id = p_bess_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 0::numeric, 'idle'::text, true, 'bess_not_found'; RETURN;
  END IF;
  v_cur := COALESCE(v_bess.current_power_kw, 0);

  -- 1. power clamp to the unit rating (charge +max_charge_kw, discharge -max_discharge_kw)
  IF v_want > 0 THEN
    v_cap := COALESCE(v_bess.max_charge_kw, 0);
    IF v_want > v_cap THEN v_want := v_cap; v_clamped := true; v_reason := 'clamped_to_max_charge'; END IF;
  ELSIF v_want < 0 THEN
    v_cap := COALESCE(v_bess.max_discharge_kw, 0);
    IF abs(v_want) > v_cap THEN v_want := -v_cap; v_clamped := true; v_reason := 'clamped_to_max_discharge'; END IF;
  END IF;

  -- 2. dwell guard: a sign flip (charge<->discharge) must pass through ~0 first.
  --    If current and target have opposite sign and current is non-trivial, force to 0
  --    (standby) this step — the next step can ramp into the new direction.
  IF sign(v_want) <> 0 AND sign(v_cur) <> 0 AND sign(v_want) <> sign(v_cur) AND abs(v_cur) > 5 THEN
    v_want := 0; v_clamped := true; v_reason := 'dwell_through_standby';
  END IF;

  -- 3. ramp limit vs current power
  IF abs(v_want - v_cur) > p_max_ramp_kw THEN
    v_want := v_cur + sign(v_want - v_cur) * p_max_ramp_kw;
    v_clamped := true;
    v_reason := CASE WHEN v_reason='ok' THEN 'ramp_limited' ELSE v_reason||'+ramp_limited' END;
  END IF;

  v_dir := CASE WHEN v_want > 0.5 THEN 'charge' WHEN v_want < -0.5 THEN 'discharge' ELSE 'standby' END;
  RETURN QUERY SELECT round(v_want,2), v_dir, v_clamped, v_reason;
END;
$function$

-- ===== ottoq_apply_need_escalation =====
CREATE OR REPLACE FUNCTION public.ottoq_apply_need_escalation(p_sim_run_id uuid DEFAULT NULL::uuid, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  v_t0        timestamptz := clock_timestamp();
  v_visits    int := 0;
  v_promoted  int := 0;
  v_by_svc    jsonb := '{}'::jsonb;
BEGIN
  CREATE TEMP TABLE _esc_new (visit_id uuid PRIMARY KEY, atoms jsonb, promoted int)
    ON COMMIT DROP;

  WITH tgt AS (
    SELECT n.visit_id, n.vehicle_id, n.atoms
      FROM ottoq_visit_needs n
     WHERE n.status IN ('open','in_progress')
       AND (p_sim_run_id IS NULL OR n.sim_run_id = p_sim_run_id)
       AND jsonb_typeof(n.atoms) = 'array'
  ), ex AS (
    SELECT t.visit_id, t.vehicle_id, a.value AS atom, a.ordinality AS ord,
           a.value->>'svc' AS svc,
           COALESCE((a.value->>'must_do')::boolean, false) AS cur_must
      FROM tgt t, LATERAL jsonb_array_elements(t.atoms) WITH ORDINALITY a(value, ordinality)
  ), scored AS (
    SELECT e.*,
           -- the urgency that governs this svc, drawn from the vehicle's need profile
           CASE e.svc
             WHEN 'exterior_wash'       THEN c.wash_urgency
             WHEN 'interior_deep_clean' THEN c.cabin_urgency
             WHEN 'sensor_calibration'  THEN c.calib_urgency
             WHEN 'mechanical_pm'       THEN ottoq_urgency_max(c.pm_urgency,
                                              ottoq_urgency_max(c.tire_urgency, c.brake_urgency))
             WHEN 'software_update'     THEN c.software_urgency
             WHEN 'fault_repair'        THEN c.fault_urgency
             WHEN 'item_retrieval'      THEN c.item_urgency
             ELSE NULL
           END AS urg,
           (pol.svc IS NOT NULL) AS governed
      FROM ex e
      LEFT JOIN ottoq_vehicle_needs_card c ON c.vehicle_id = e.vehicle_id
      LEFT JOIN service_cadence_policy pol ON pol.svc = e.svc AND pol.is_active
  ), decided AS (
    SELECT s.*,
           -- MONOTONE: only ever promotes.
           (s.cur_must OR (s.governed AND s.urg IS NOT NULL
                           AND COALESCE(s.atom->>'status','pending') NOT IN ('done','cancelled','skipped')
                           AND ottoq_service_must_do(s.svc, s.urg))) AS new_must
      FROM scored s
  ), rebuilt AS (
    SELECT visit_id,
           jsonb_agg(
             CASE WHEN new_must AND NOT cur_must
                  THEN atom || jsonb_build_object('must_do', true, 'deferrable', false,
                                                  'escalated_by', 'cadence',
                                                  'escalation_urgency', urg)
                  ELSE atom END
             ORDER BY ord) AS atoms,
           count(*) FILTER (WHERE new_must AND NOT cur_must)::int AS promoted
      FROM decided GROUP BY visit_id
  )
  INSERT INTO _esc_new SELECT visit_id, atoms, promoted FROM rebuilt WHERE promoted > 0;

  SELECT count(*), COALESCE(sum(promoted),0) INTO v_visits, v_promoted FROM _esc_new;

  SELECT COALESCE(jsonb_object_agg(svc, n), '{}'::jsonb) INTO v_by_svc
    FROM (SELECT a.value->>'svc' AS svc, count(*) AS n
            FROM _esc_new e, LATERAL jsonb_array_elements(e.atoms) a
           WHERE a.value->>'escalated_by' = 'cadence'
           GROUP BY 1) q;

  IF NOT p_dry_run THEN
    UPDATE ottoq_visit_needs n
       SET atoms = e.atoms
      FROM _esc_new e
     WHERE n.visit_id = e.visit_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'dry_run', p_dry_run, 'sim_run_id', p_sim_run_id,
    'visits_touched', v_visits, 'atoms_promoted', v_promoted, 'by_svc', v_by_svc,
    'ms', round(EXTRACT(epoch FROM (clock_timestamp() - v_t0)) * 1000));
END;
$function$

-- ===== ottoq_apply_ops_action =====
CREATE OR REPLACE FUNCTION public.ottoq_apply_ops_action(p_sim_run_id uuid, p_depot_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb, p_by text DEFAULT 'ottoq_prime'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_val numeric; v_cur numeric;
BEGIN
  IF p_action = 'raise_deploy_surge' THEN
    -- clear a deploy backlog faster (AM commute / post-wave). Clamp 0.10–1.00, ≤+40%/move.
    v_cur := ottoq_policy_get(p_sim_run_id, 'deploy_surge_catchup', 0.35);
    v_val := LEAST(1.00, GREATEST(0.10, LEAST(v_cur * 1.40, COALESCE((p_args->>'value')::numeric, v_cur * 1.30))));
    PERFORM ottoq_policy_set('run', p_sim_run_id, 'deploy_surge_catchup', v_val, p_by);
    RETURN jsonb_build_object('status','applied','action',p_action,'param','deploy_surge_catchup','from',v_cur,'to',v_val);

  ELSIF p_action = 'extend_forecast_horizon' THEN
    -- look further ahead to pre-position BESS/staging for an inbound wave. Clamp 10–90 min.
    v_cur := ottoq_policy_get(p_sim_run_id, 'forecast_horizon_min', 30);
    v_val := LEAST(90, GREATEST(10, COALESCE((p_args->>'value')::numeric, v_cur + 15)));
    PERFORM ottoq_policy_set('run', p_sim_run_id, 'forecast_horizon_min', v_val, p_by);
    RETURN jsonb_build_object('status','applied','action',p_action,'param','forecast_horizon_min','from',v_cur,'to',v_val);

  ELSIF p_action = 'enable_energy_reserve' THEN
    -- switch energy shaving to the causal water-fill reserve target (BESS + timing only).
    PERFORM ottoq_policy_set('run', p_sim_run_id, 'energy_reserve_shave', 1, p_by);
    RETURN jsonb_build_object('status','applied','action',p_action,'param','energy_reserve_shave','to',1);

  ELSE
    -- OUT OF WHITELIST → human approval queue (Pulse), not a silent drop.
    INSERT INTO ottoq_ops_approvals (approval_type, sim_run_id, depot_id, status, priority, payload, requested_at, expires_at)
    VALUES ('nemotron_ops_action', p_sim_run_id, p_depot_id, 'pending',
            COALESCE(NULLIF(p_args->>'priority',''), 'normal'),
            jsonb_build_object('action', p_action, 'args', p_args, 'by', p_by, 'reason','not in auto-exec whitelist'),
            now(), now() + interval '30 minutes');
    RETURN jsonb_build_object('status','queued_for_approval','action',p_action);
  END IF;
END;
$function$

-- ===== ottoq_apply_profile =====
CREATE OR REPLACE FUNCTION public.ottoq_apply_profile(p_sim_run_id uuid, p_var text, p_raw numeric, p_mean numeric DEFAULT NULL::numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_knobs    JSONB;
  v_knob     JSONB;
  v_gspread  NUMERIC;
  v_spread   NUMERIC;
  v_shift    NUMERIC;
  v_floor    NUMERIC;
  v_ceiling  NUMERIC;
  v_mean     NUMERIC;
  v_out      NUMERIC;
BEGIN
  IF p_sim_run_id IS NULL OR p_raw IS NULL THEN
    RETURN p_raw;
  END IF;

  SELECT knobs INTO v_knobs
    FROM ottoq_variability_profiles
   WHERE sim_run_id = p_sim_run_id;

  -- No profile → identity (behaves exactly like today)
  IF v_knobs IS NULL THEN
    RETURN p_raw;
  END IF;

  v_knob    := COALESCE(v_knobs -> p_var, '{}'::jsonb);
  v_gspread := COALESCE((v_knobs #>> '{_global,spread_mult}')::numeric, 1);
  v_spread  := COALESCE((v_knob ->> 'spread')::numeric, 1) * v_gspread;
  v_shift   := COALESCE((v_knob ->> 'shift')::numeric, 0);
  v_floor   := (v_knob ->> 'floor')::numeric;     -- may be NULL
  v_ceiling := (v_knob ->> 'ceiling')::numeric;   -- may be NULL

  -- Fast path: fully neutral knob
  IF v_spread = 1 AND v_shift = 0 AND v_floor IS NULL AND v_ceiling IS NULL THEN
    RETURN p_raw;
  END IF;

  -- Center for variance widening
  v_mean := p_mean;
  IF v_mean IS NULL THEN
    SELECT mean_value INTO v_mean
      FROM ottoq_calibration_distributions
     WHERE variable_name = p_var AND segment = 'global'
     LIMIT 1;
  END IF;
  v_mean := COALESCE(v_mean, p_raw);

  v_out := v_mean + (p_raw - v_mean) * v_spread + v_shift;

  IF v_floor   IS NOT NULL THEN v_out := GREATEST(v_out, v_floor);   END IF;
  IF v_ceiling IS NOT NULL THEN v_out := LEAST(v_out, v_ceiling);    END IF;

  RETURN v_out;
END;
$function$

-- ===== ottoq_approach_zone =====
CREATE OR REPLACE FUNCTION public.ottoq_approach_zone(p_vehicle_id uuid, p_sim_run_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'extensions'
AS $function$
  SELECT COALESCE(
    (SELECT b.zone FROM public.ottoq_approach_band b
      WHERE b.vehicle_id = p_vehicle_id AND b.sim_run_id = p_sim_run_id
      LIMIT 1),
    'B');   -- FAIL-CLOSED: no row => FROZEN, never open.
$function$

-- ===== ottoq_archive_run =====
CREATE OR REPLACE FUNCTION public.ottoq_archive_run(p_sim_run_id uuid, p_reason text DEFAULT 'operator_stop'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run ottoq_sim_runs%ROWTYPE; v_metrics jsonb;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'run not found');
  END IF;

  -- Cheap, index-friendly tallies only. Nothing here may scan ottoq_events broadly.
  v_metrics := jsonb_build_object(
    'events_generated',   COALESCE(v_run.events_generated, 0),
    'charge_sessions',    COALESCE(v_run.charge_sessions, 0),
    'tasks_completed',    COALESCE(v_run.tasks_completed, 0),
    'vehicles_simulated', COALESCE(v_run.vehicles_simulated, 0),
    'commands_issued',    (SELECT count(*) FROM ottoq_vehicle_commands WHERE sim_run_id = p_sim_run_id),
    'commands_refused',   (SELECT count(*) FROM ottoq_vehicle_commands WHERE sim_run_id = p_sim_run_id AND status = 'refused'),
    'dispatches',         (SELECT count(*) FROM ottoq_vehicle_dispatches WHERE sim_run_id = p_sim_run_id)
  );

  INSERT INTO public.ottoq_run_archives AS a (
    sim_run_id, reason, scenario, policy, random_seed, depot_id, run_by,
    started_at, ended_at, tick_count, sim_clock_start, sim_clock_end,
    playback_mode, speed_x, metrics, run_payload)
  VALUES (
    p_sim_run_id, p_reason, v_run.scenario_code, v_run.policy, v_run.random_seed,
    v_run.depot_id, v_run.run_by, v_run.started_at, COALESCE(v_run.ended_at, now()),
    v_run.tick_count, v_run.sim_clock_start, v_run.sim_clock_current,
    v_run.payload->>'playback_mode', (v_run.payload->>'speed_x')::numeric,
    v_metrics, v_run.payload)
  ON CONFLICT (sim_run_id) DO UPDATE
    SET archived_at = now(), reason = EXCLUDED.reason, ended_at = EXCLUDED.ended_at,
        tick_count = EXCLUDED.tick_count, sim_clock_end = EXCLUDED.sim_clock_end,
        metrics = EXCLUDED.metrics, run_payload = EXCLUDED.run_payload;

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id,
    'reproducible_from', jsonb_build_object('scenario', v_run.scenario_code,
      'random_seed', v_run.random_seed, 'policy', v_run.policy, 'depot_id', v_run.depot_id),
    'metrics', v_metrics);
END;
$function$

-- ===== ottoq_assert_clock_invariant =====
CREATE OR REPLACE FUNCTION public.ottoq_assert_clock_invariant(p_sim_run_id uuid, p_tolerance numeric DEFAULT 0.05)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE f RECORD;
BEGIN
  SELECT * INTO f FROM ottoq_clock_fidelity(p_sim_run_id, 20);
  IF NOT FOUND OR f.ticks_measured < 2 THEN RETURN NULL; END IF;
  IF f.playback_mode <> 'live' THEN RETURN NULL; END IF;
  IF f.ratio IS NULL OR f.target_ratio IS NULL THEN RETURN NULL; END IF;
  IF abs(f.ratio - f.target_ratio) / f.target_ratio > p_tolerance THEN
    RETURN format('CLOCK INVARIANT FAILED: measured %s x vs target %s x over %s ticks (p95 tick %s ms). %s',
                  f.ratio, f.target_ratio, f.ticks_measured, f.p95_tick_ms, f.verdict);
  END IF;
  RETURN NULL;
END;
$function$

-- ===== ottoq_assert_context_sufficient =====
CREATE OR REPLACE FUNCTION public.ottoq_assert_context_sufficient(p_action_context text, p_context jsonb)
 RETURNS TABLE(sufficient boolean, missing_inputs text[])
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_required text[];
  v_missing  text[] := '{}';
  v_key      text;
BEGIN
  -- Per-action required-input sets (the safety-critical inputs each gate needs).
  -- Conservative: if an action_context is unknown here, require depot_id at minimum.
  v_required := CASE p_action_context
    WHEN 'stall_assignment'      THEN ARRAY['depot_id','vehicle_id','stall_id']
    WHEN 'charge_session_start'  THEN ARRAY['depot_id','vehicle_id','stall_id','requested_kw']
    WHEN 'power_increase'        THEN ARRAY['depot_id','charger_id','requested_kw']
    WHEN 'charge_session_throttle' THEN ARRAY['depot_id','charger_id']
    WHEN 'task_start'            THEN ARRAY['depot_id','vehicle_id']
    WHEN 'redeployment'          THEN ARRAY['vehicle_id','fleet_operator_id']
    WHEN 'release'               THEN ARRAY['vehicle_id']
    WHEN 'oem_acceptance'        THEN ARRAY['vehicle_id','fleet_operator_id']
    WHEN 'vehicle_state_change'  THEN ARRAY['from_state','to_state']
    WHEN 'bess_dispatch'         THEN ARRAY['depot_id','bess_id']
    ELSE ARRAY['depot_id']
  END;

  FOREACH v_key IN ARRAY v_required LOOP
    IF NULLIF(p_context ->> v_key, '') IS NULL THEN
      v_missing := array_append(v_missing, v_key);
    END IF;
  END LOOP;

  RETURN QUERY SELECT (cardinality(v_missing) = 0), v_missing;
END;
$function$

-- ===== ottoq_assert_playback_isolation =====
CREATE OR REPLACE FUNCTION public.ottoq_assert_playback_isolation()
 RETURNS TABLE(function_name text, violation text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT p.proname::text,
         CASE WHEN p.prosrc ~ 'speed_x' AND p.prosrc ~ 'playback_mode'
                THEN 'reads BOTH speed_x and playback_mode'
              WHEN p.prosrc ~ 'speed_x' THEN 'reads speed_x'
              ELSE 'reads playback_mode' END
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND (p.prosrc ~ 'speed_x' OR p.prosrc ~ 'playback_mode')
     -- every surface where a decision is proposed, shielded, scored or enacted
     AND p.proname ~ '^ottoq_(decide|l1_|l2_|shield|eval_|book_appointment|honour_|plan_|service_priority|reoptimize|cuopt_|energy_orchestrate|greedy_tick|fifo_tick|manual_tick|score_run|sim_auto_dispatch|sim_auto_charge)'
     -- the clock instrument itself legitimately reads them
     AND p.proname NOT IN ('ottoq_clock_fidelity','ottoq_clock_fidelity_ticks',
                           'ottoq_assert_clock_invariant','ottoq_assert_playback_isolation')
   ORDER BY 1;
$function$

-- ===== ottoq_assert_snapshot_integrity =====
CREATE OR REPLACE FUNCTION public.ottoq_assert_snapshot_integrity(p_snapshot_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_row ottoq_decision_snapshots%ROWTYPE;
  v_recomputed text;
BEGIN
  SELECT * INTO v_row FROM ottoq_decision_snapshots WHERE snapshot_id = p_snapshot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'OTTOQ_SNAPSHOT_MISSING: %', p_snapshot_id USING ERRCODE = 'P0001';
  END IF;
  v_recomputed := encode(digest(jsonb_pretty(v_row.frame), 'sha256'), 'hex');
  IF v_recomputed <> v_row.content_hash THEN
    RAISE EXCEPTION 'OTTOQ_SNAPSHOT_TAMPERED: % expected % got %', p_snapshot_id, v_row.content_hash, v_recomputed
      USING ERRCODE = 'P0001';
  END IF;
  RETURN TRUE;
END;
$function$

-- ===== ottoq_auto_generate_incident_report =====
CREATE OR REPLACE FUNCTION public.ottoq_auto_generate_incident_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_incident_id UUID;
  v_existing_count INT;
BEGIN
  -- Skip auto-incident-report generation for BENCHMARK depots (perf: this trigger scans the huge
  -- ottoq_events/rule_evaluations history; synthetic A/B runs don't need prod audit reports).
  -- depots is tiny so this PK-keyed EXISTS is microseconds; robust to any 'benchmark%' slug depot.
  IF NEW.depot_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM depots d WHERE d.id = NEW.depot_id AND d.slug LIKE 'benchmark%') THEN
    RETURN NEW;
  END IF;

  IF NEW.severity <> 'safety_critical' THEN RETURN NEW; END IF;

  IF NEW.event_type IN (
    'incident.report_generated','incident.report_reviewed','incident.report_reopened',
    'audit.report_requested','audit.report_completed','emergency.cleared',
    'emergency.cascade_complete','emergency.action_executed','emergency.notify_actors'
  ) THEN
    RETURN NEW;
  END IF;

  IF NEW.correlation_id IS NOT NULL THEN
    SELECT count(*) INTO v_existing_count
      FROM ottoq_incident_reports
     WHERE source_correlation_id = NEW.correlation_id;
    IF v_existing_count > 0 THEN RETURN NEW; END IF;
  END IF;

  BEGIN
    v_incident_id := ottoq_generate_incident_report(
      p_triggering_event_id := NEW.event_id,
      p_window_minutes_before := 15,
      p_window_minutes_after  := 60,
      p_generated_by_actor_type := 'ottoq_engine'
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN NEW;
END;
$function$

-- ===== ottoq_benchmark_reset =====
CREATE OR REPLACE FUNCTION public.ottoq_benchmark_reset(p_depot uuid, p_arrival_soc numeric DEFAULT 30, p_target_soc numeric DEFAULT 80)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF p_depot NOT IN (SELECT id FROM depots WHERE slug LIKE 'benchmark%') THEN
    RAISE EXCEPTION 'ottoq_benchmark_reset refuses non-benchmark depot %', p_depot;  -- safety: never reset production
  END IF;
  -- self-heal zombie runs (worker death between scoring and abort)
  UPDATE ottoq_sim_runs SET status='aborted', ended_at=now(),
         notes = COALESCE(notes,'') || ' | auto-aborted by benchmark_reset (zombie heal)'
   WHERE depot_id=p_depot AND status='running';
  UPDATE stalls SET status='available', current_vehicle_id=NULL, reserved_by=NULL, reserved_at=NULL, reservation_expires_at=NULL WHERE depot_id=p_depot;
  UPDATE ottoq_ocpp_chargers SET station_state='Available', last_heartbeat_at=now(), last_fault_code=NULL WHERE depot_id=p_depot;
  UPDATE ocpp_sessions SET status='completed', ended_at=now() WHERE depot_id=p_depot AND status='active';
  UPDATE vehicles SET current_state='arrived_at_gate', current_soc=p_arrival_soc, target_soc=p_target_soc,
         current_stall_id=NULL, last_state_change=now(),
         config=((COALESCE(config,'{}'::jsonb)-'svc_step')-'service_manifest')-'service_manifest_meta' - 'battery_soh_pct' - 'consumption_scalar' - 'charge_curve_scalar' - 'soil_rate' - 'pm_interval_km' - 'calib_interval_h' - 'service_speed_scalar' - 'wash_cadence_cycles' - 'cycles_since_wash' - 'condition_drawn_run'
   WHERE home_depot_id=p_depot AND category='autonomous';
  UPDATE ottoq_visit_needs SET status='superseded'
   WHERE depot_id=p_depot AND status IN ('open','in_progress');
  UPDATE ottoq_ops_approvals SET status='expired'
   WHERE depot_id=p_depot AND status='pending';
END $function$

-- ===== ottoq_bess_reserve_target =====
CREATE OR REPLACE FUNCTION public.ottoq_bess_reserve_target(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone, p_horizon_ticks integer DEFAULT 16, p_tick_min numeric DEFAULT 30)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_cap numeric; v_soc numeric; v_floor numeric; v_maxdis numeric; v_eff numeric; v_reserve_pct numeric;
  v_e_avail numeric; v_dt numeric := p_tick_min/60.0; v_base numeric;
  v_load numeric[]; lo numeric; hi numeric; mid numeric; needed numeric; k int;
BEGIN
  SELECT capacity_kwh, current_soc_pct, COALESCE(soc_min_floor_pct,10), COALESCE(max_discharge_kw,500),
         sqrt(GREATEST(0.5, COALESCE(roundtrip_efficiency_pct,90)/100.0))
    INTO v_cap, v_soc, v_floor, v_maxdis, v_eff FROM ottoq_bess_units WHERE depot_id=p_depot_id LIMIT 1;
  IF v_cap IS NULL OR v_soc IS NULL THEN RETURN NULL; END IF;

  v_reserve_pct := v_floor + COALESCE(ottoq_forecast_uncertainty(p_sim_run_id, p_depot_id, p_sim_clock),0) * 20;
  v_e_avail := GREATEST(0, (v_soc - v_reserve_pct)/100.0 * v_cap) * v_eff;

  v_load := ottoq_forecast_net_load(p_sim_run_id, p_depot_id, p_sim_clock, p_horizon_ticks, p_tick_min);
  IF v_load IS NULL OR array_length(v_load,1) IS NULL THEN RETURN NULL; END IF;
  SELECT COALESCE(min(u),0) INTO v_base FROM unnest(v_load) u;

  lo := v_base; SELECT max(u) INTO hi FROM unnest(v_load) u;
  IF hi <= lo THEN RETURN round(hi,1); END IF;
  FOR k IN 1..34 LOOP
    mid := (lo+hi)/2.0;
    SELECT COALESCE(SUM(LEAST(v_maxdis, GREATEST(0, u-mid)))*v_dt, 0) INTO needed FROM unnest(v_load) u;
    IF needed <= v_e_avail THEN hi := mid; ELSE lo := mid; END IF;
  END LOOP;
  RETURN round(hi,1);
END;
$function$

-- ===== ottoq_blackbox_latest_run =====
CREATE OR REPLACE FUNCTION public.ottoq_blackbox_latest_run()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT to_jsonb(t) FROM (
    SELECT sim_run_id,
           scenario_code,
           status,
           COALESCE(tick_count, 0)      AS tick_count,
           COALESCE(demo_speed_x, 1)    AS demo_speed_x
    FROM ottoq_sim_runs
    WHERE run_by = 'operator_demo'
    ORDER BY started_at DESC
    LIMIT 1
  ) t;
$function$

-- ===== ottoq_block_mutation =====
CREATE OR REPLACE FUNCTION public.ottoq_block_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' AND current_setting('ottoq.retention', true) = 'on' THEN
    RETURN OLD;  -- retention maintenance (transaction-local flag, see ottoq_retention_purge)
  END IF;
  RAISE EXCEPTION 'OTTOQ_APPEND_ONLY: % rejected on table %.', TG_OP, TG_TABLE_NAME
    USING ERRCODE = 'P0001';
END;
$function$

-- ===== ottoq_booking_provenance_audit =====
CREATE OR REPLACE FUNCTION public.ottoq_booking_provenance_audit(p_sim_run_id uuid)
 RETURNS TABLE(booking_id uuid, vehicle_id uuid, stall_id uuid, stall_type text, purpose text, booked_by text, source text, decision_link text, decision_id uuid, backed_by_key boolean, backed_by_match boolean, backing_context text, is_phantom boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'extensions'
AS $function$
  SELECT
    b.booking_id, b.vehicle_id, b.stall_id,
    s.stall_type::text, b.purpose, b.booked_by, b.source, b.decision_link, b.decision_id,
    k.ok AS backed_by_key,
    m.ok AS backed_by_match,
    COALESCE(k.ctx, m.ctx) AS backing_context,
    (b.booked_by = 'otto_q_enacted' AND NOT (k.ok OR m.ok)) AS is_phantom
  FROM public.ottoq_stall_bookings b
  LEFT JOIN public.stalls s ON s.id = b.stall_id
  -- (1) BY KEY: the booking names the enacted decision that caused it.
  CROSS JOIN LATERAL (
    SELECT EXISTS (SELECT 1 FROM public.ottoq_decisions d
                    WHERE d.decision_id = b.decision_id
                      AND d.sim_run_id  = b.sim_run_id
                      AND d.outcome_status = 'enacted') AS ok,
           (SELECT COALESCE(d.resolved_action_context, d.action_context)
              FROM public.ottoq_decisions d
             WHERE d.decision_id = b.decision_id
               AND d.sim_run_id  = b.sim_run_id
               AND d.outcome_status = 'enacted' LIMIT 1) AS ctx
  ) k
  -- (2) BY MATCH: an enacted decision placed THIS vehicle in THIS stall, and did so while
  --     this booking's window was open. Deliberately NOT filtered on action_context --
  --     that filter is what produced the bogus 11.7% phantom rate on run d78dd3b1.
  CROSS JOIN LATERAL (
    SELECT EXISTS (SELECT 1 FROM public.ottoq_decisions d
                    WHERE d.sim_run_id = b.sim_run_id
                      AND d.outcome_status = 'enacted'
                      AND d.entity_id = b.vehicle_id
                      AND NULLIF(d.enacted_action->>'stall_id','')::uuid = b.stall_id
                      AND d.sim_clock <@ b.during) AS ok,
           (SELECT COALESCE(d.resolved_action_context, d.action_context)
              FROM public.ottoq_decisions d
             WHERE d.sim_run_id = b.sim_run_id
               AND d.outcome_status = 'enacted'
               AND d.entity_id = b.vehicle_id
               AND NULLIF(d.enacted_action->>'stall_id','')::uuid = b.stall_id
               AND d.sim_clock <@ b.during LIMIT 1) AS ctx
  ) m
  WHERE b.sim_run_id = p_sim_run_id;
$function$

-- ===== ottoq_booking_provenance_summary =====
CREATE OR REPLACE FUNCTION public.ottoq_booking_provenance_summary(p_sim_run_id uuid)
 RETURNS TABLE(enacted_bookings bigint, backed_by_key bigint, backed_by_match bigint, backed_any bigint, phantoms bigint, phantom_pct numeric, reverse_coverage_pct numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'extensions'
AS $function$
  SELECT COUNT(*),
         COUNT(*) FILTER (WHERE a.backed_by_key),
         COUNT(*) FILTER (WHERE a.backed_by_match),
         COUNT(*) FILTER (WHERE a.backed_by_key OR a.backed_by_match),
         COUNT(*) FILTER (WHERE a.is_phantom),
         ROUND(100.0 * COUNT(*) FILTER (WHERE a.is_phantom) / NULLIF(COUNT(*),0), 1),
         ROUND(100.0 * COUNT(*) FILTER (WHERE a.backed_by_key OR a.backed_by_match)
               / NULLIF(COUNT(*),0), 1)
    FROM public.ottoq_booking_provenance_audit(p_sim_run_id) a
   WHERE a.booked_by = 'otto_q_enacted';
$function$

-- ===== ottoq_brain_deploy_rank =====
CREATE OR REPLACE FUNCTION public.ottoq_brain_deploy_rank(p_sim_run_id uuid, p_vehicle_id uuid)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT MIN(d.tick_seq)
    FROM ottoq_decisions d
   WHERE d.sim_run_id      = p_sim_run_id
     AND d.entity_id       = p_vehicle_id
     AND d.entity_type     = 'vehicle'
     AND d.action_context  = 'redeployment'
     AND d.outcome_status  = 'enacted'
     AND d.sim_clock > COALESCE(
           (SELECT MAX(vd.dispatched_at) FROM ottoq_vehicle_dispatches vd
             WHERE vd.sim_run_id = p_sim_run_id AND vd.vehicle_id = p_vehicle_id),
           '-infinity'::timestamptz);
$function$

-- ===== ottoq_build_decision_context =====
CREATE OR REPLACE FUNCTION public.ottoq_build_decision_context(p_action_context text, p_entity_type text, p_entity_id uuid, p_depot_id uuid, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_ctx jsonb := jsonb_build_object('depot_id', p_depot_id, 'now_ts', p_now, 'action', p_action_context);
  v_veh RECORD;
BEGIN
  IF p_entity_type = 'vehicle' AND p_entity_id IS NOT NULL THEN
    SELECT current_soc, current_state, fleet_operator_id, inlet_type INTO v_veh FROM vehicles WHERE id = p_entity_id;
    v_ctx := v_ctx || jsonb_build_object('vehicle_id', p_entity_id, 'current_soc', v_veh.current_soc,
              'vehicle_state', v_veh.current_state, 'fleet_operator_id', v_veh.fleet_operator_id, 'inlet_type', v_veh.inlet_type);
  END IF;
  RETURN v_ctx;
END;
$function$

-- ===== ottoq_build_decision_frame =====
CREATE OR REPLACE FUNCTION public.ottoq_build_decision_frame(p_depot_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'vehicles', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', v.id, 'state', v.current_state, 'soc', ROUND(v.current_soc::numeric,2),
        'stall_id', v.current_stall_id, 'inlet_type', v.inlet_type,
        'inlet_max_kw', v.inlet_max_kw, 'fleet_operator_id', v.fleet_operator_id,
        'make', v.make, 'platform', v.platform, 'svc_step', v.config->>'svc_step',
        'target_soc', v.target_soc, 'min_soc_threshold', v.min_soc_threshold
      ) ORDER BY v.id)
      FROM vehicles v WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
    ), '[]'::jsonb),
    'stalls', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', s.id, 'type', s.stall_type, 'status', s.status,
        'vehicle_id', s.current_vehicle_id, 'connector_type', s.connector_type,
        'connector_max_kw', s.connector_max_kw
      ) ORDER BY s.id)
      FROM stalls s WHERE s.depot_id = p_depot_id
    ), '[]'::jsonb),
    'sessions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cs.id, 'stall_id', cs.stall_id, 'vehicle_id', cs.vehicle_id,
        'status', cs.status, 'started_at', cs.started_at,
        'power_kw', ((cs.last_meter_value->>'power_kw'))::numeric
      ) ORDER BY cs.id)
      FROM ocpp_sessions cs WHERE cs.depot_id = p_depot_id AND cs.status = 'active'
    ), '[]'::jsonb),
    'energy', (
      SELECT jsonb_build_object(
        'grid_import_kw', se.grid_import_kw, 'total_ev_charging_kw', se.total_ev_charging_kw,
        'building_load_kw', se.building_load_kw, 'peak_demand_kw_15min', se.peak_demand_kw_15min,
        'tariff', se.current_tariff_label, 'at', se.timestamp
      )
      FROM site_energy_snapshots se WHERE se.depot_id = p_depot_id
      ORDER BY se.timestamp DESC LIMIT 1
    ),
    'bess', (
      SELECT jsonb_build_object(
        'soc_pct', b.current_soc_pct, 'power_kw', b.current_power_kw,
        'state', b.current_state, 'temp_c', b.current_temperature_c, 'soh_pct', b.current_soh_pct
      )
      FROM ottoq_bess_units b WHERE b.depot_id = p_depot_id LIMIT 1
    )
  );
$function$

-- ===== ottoq_build_workflow_plan =====
CREATE OR REPLACE FUNCTION public.ottoq_build_workflow_plan(p_vehicle_id uuid, p_sim_run_id uuid, p_arrival_at timestamp with time zone, p_atoms jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_a jsonb; v_legs jsonb := '[]'::jsonb; v_seq int := 0;
  v_charge_min int := 0; v_overlay_max int := 0; v_est int;
  v_t timestamptz; v_bay_t timestamptz; v_svc text; v_conc text;
  v_ready timestamptz;
BEGIN
  IF p_atoms IS NULL OR jsonb_array_length(p_atoms) = 0 THEN
    RETURN jsonb_build_object('legs', '[]'::jsonb, 'total_min', 0,
                              'arrival_at', p_arrival_at, 'projected_ready_at', p_arrival_at);
  END IF;
  v_t := p_arrival_at;

  -- 1) the charge ANCHOR (real physics minutes from manifest v4)
  FOR v_a IN SELECT * FROM jsonb_array_elements(p_atoms) LOOP
    IF v_a->>'svc' = 'charge' AND COALESCE(v_a->>'status','pending') NOT IN ('done','cancelled') THEN
      v_charge_min := GREATEST(v_charge_min, COALESCE(round((v_a->>'est_min')::numeric)::int, 25));
    END IF;
  END LOOP;
  IF v_charge_min > 0 THEN
    v_seq := v_seq + 1;
    v_legs := v_legs || jsonb_build_object('seq', v_seq, 'svc', 'charge',
      'est_min', v_charge_min, 'starts_at', v_t,
      'ends_at', v_t + (v_charge_min || ' minutes')::interval, 'parallel', false);
  END IF;

  -- 2) DURING-CHARGE overlays (cabin/exterior/digital run while plugged in)
  FOR v_a IN SELECT * FROM jsonb_array_elements(p_atoms) LOOP
    v_svc  := v_a->>'svc';
    v_conc := COALESCE(v_a->>'concurrency','');
    IF v_svc <> 'charge' AND v_conc IN ('cabin','exterior','digital')
       AND COALESCE(v_a->>'status','pending') NOT IN ('done','cancelled') THEN
      v_est := COALESCE(round((v_a->>'est_min')::numeric)::int, 5);
      v_overlay_max := GREATEST(v_overlay_max, v_est);
      v_seq := v_seq + 1;
      v_legs := v_legs || jsonb_build_object('seq', v_seq, 'svc', v_svc,
        'est_min', v_est, 'starts_at', v_t,
        'ends_at', v_t + (v_est || ' minutes')::interval, 'parallel', true);
    END IF;
  END LOOP;

  -- 3) the BAY CHAIN, sequential after the anchor/overlays clear
  v_bay_t := v_t + (GREATEST(v_charge_min, v_overlay_max) || ' minutes')::interval;
  FOR v_a IN
    SELECT a.* FROM jsonb_array_elements(p_atoms) a
    ORDER BY CASE a.value->>'svc'
      WHEN 'exterior_wash' THEN 1 WHEN 'sensor_calibration' THEN 2
      WHEN 'interior_deep_clean' THEN 3 WHEN 'mechanical_pm' THEN 4
      WHEN 'cosmetic_repair' THEN 5 WHEN 'fault_repair' THEN 6 ELSE 9 END
  LOOP
    v_svc := v_a->>'svc';
    IF COALESCE(v_a->>'concurrency','') = 'bay'
       AND COALESCE(v_a->>'status','pending') NOT IN ('done','cancelled') THEN
      v_est := COALESCE(round((v_a->>'est_min')::numeric)::int, 20);
      v_seq := v_seq + 1;
      v_legs := v_legs || jsonb_build_object('seq', v_seq, 'svc', v_svc,
        'est_min', v_est, 'starts_at', v_bay_t,
        'ends_at', v_bay_t + (v_est || ' minutes')::interval, 'parallel', false,
        'requires_bay', v_a->>'requires_bay');
      v_bay_t := v_bay_t + (v_est || ' minutes')::interval;
    END IF;
  END LOOP;

  -- 4) the READINESS GATE closes the visit
  FOR v_a IN SELECT * FROM jsonb_array_elements(p_atoms) LOOP
    IF COALESCE(v_a->>'concurrency','') = 'gate'
       AND COALESCE(v_a->>'status','pending') NOT IN ('done','cancelled') THEN
      v_est := COALESCE(round((v_a->>'est_min')::numeric)::int, 3);
      v_seq := v_seq + 1;
      v_legs := v_legs || jsonb_build_object('seq', v_seq, 'svc', v_a->>'svc',
        'est_min', v_est, 'starts_at', v_bay_t,
        'ends_at', v_bay_t + (v_est || ' minutes')::interval, 'parallel', false);
      v_bay_t := v_bay_t + (v_est || ' minutes')::interval;
    END IF;
  END LOOP;

  v_ready := v_bay_t;
  RETURN jsonb_build_object(
    'legs', v_legs,
    'total_min', GREATEST(0, round(EXTRACT(epoch FROM (v_ready - p_arrival_at)) / 60)::int),
    'arrival_at', p_arrival_at,
    'projected_ready_at', v_ready,
    'planned_pre_arrival', true);
END;
$function$

-- ===== ottoq_calibration_coverage =====
CREATE OR REPLACE FUNCTION public.ottoq_calibration_coverage()
 RETURNS TABLE(out_domain text, out_dataset_code text, out_status text, out_variables bigint, out_distributions bigint, out_total_samples bigint, out_ingested_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT
    d.domain, d.dataset_code, d.status,
    count(DISTINCT dist.variable_name),
    count(dist.distribution_id),
    COALESCE(sum(dist.sample_count), 0),
    d.ingested_at
  FROM ottoq_calibration_datasets d
  LEFT JOIN ottoq_calibration_distributions dist ON dist.dataset_code = d.dataset_code
  GROUP BY d.domain, d.dataset_code, d.status, d.ingested_at
  ORDER BY d.domain, d.dataset_code;
$function$

-- ===== ottoq_canonicalize_payload =====
CREATE OR REPLACE FUNCTION public.ottoq_canonicalize_payload(p jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF p IS NULL THEN RETURN '{}'; END IF;
  RETURN jsonb_strip_nulls(p)::text;
END;
$function$

-- ===== ottoq_capture_decision_snapshot =====
CREATE OR REPLACE FUNCTION public.ottoq_capture_decision_snapshot(p_sim_run_id uuid, p_tick_seq bigint, p_depot_id uuid, p_sim_clock timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_existing uuid;
  v_frame    jsonb;
  v_hash     text;
  v_counts   jsonb;
  v_id       uuid;
BEGIN
  SELECT snapshot_id INTO v_existing
    FROM ottoq_decision_snapshots WHERE sim_run_id = p_sim_run_id AND tick_seq = p_tick_seq;
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;

  v_frame := ottoq_build_decision_frame(p_depot_id);
  -- deterministic content hash over the canonical (key-sorted) frame text
  v_hash := encode(digest(jsonb_pretty(v_frame), 'sha256'), 'hex');
  v_counts := jsonb_build_object(
    'vehicles', jsonb_array_length(COALESCE(v_frame->'vehicles','[]'::jsonb)),
    'stalls',   jsonb_array_length(COALESCE(v_frame->'stalls','[]'::jsonb)),
    'sessions', jsonb_array_length(COALESCE(v_frame->'sessions','[]'::jsonb))
  );

  INSERT INTO ottoq_decision_snapshots (sim_run_id, tick_seq, depot_id, sim_clock, content_hash, frame, frame_counts)
  VALUES (p_sim_run_id, p_tick_seq, p_depot_id, p_sim_clock, v_hash, v_frame, v_counts)
  ON CONFLICT (sim_run_id, tick_seq) DO NOTHING
  RETURNING snapshot_id INTO v_id;

  IF v_id IS NULL THEN
    SELECT snapshot_id INTO v_id FROM ottoq_decision_snapshots
     WHERE sim_run_id = p_sim_run_id AND tick_seq = p_tick_seq;
  END IF;
  RETURN v_id;
END;
$function$

-- ===== ottoq_causation_chain =====
CREATE OR REPLACE FUNCTION public.ottoq_causation_chain(p_event_id uuid)
 RETURNS SETOF ottoq_events
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH RECURSIVE chain AS (
    SELECT * FROM ottoq_events WHERE event_id = p_event_id
    UNION ALL
    SELECT e.* FROM ottoq_events e
    JOIN chain c ON e.event_id = c.parent_event_id
  )
  SELECT * FROM chain ORDER BY occurred_at ASC;
$function$

-- ===== ottoq_cert_arm =====
CREATE OR REPLACE PROCEDURE public.ottoq_cert_arm(IN p_seed bigint, IN p_policy text, IN p_ab_group uuid, IN p_ticks integer, IN p_start timestamp with time zone DEFAULT NULL::timestamp with time zone, IN p_fault_chargers integer DEFAULT 0)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $procedure$
DECLARE v_run uuid; i int; v_now timestamptz := now(); v_wseed bigint; v_deploy_n int; v_total int;
        d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 80);
  UPDATE ottoq_bess_units SET current_soc_pct = 90.0, current_temperature_c = 25.0 WHERE depot_id = d;
  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'wave', 17));
  SELECT count(*) INTO v_total FROM vehicles WHERE home_depot_id=d AND category='autonomous';
  v_deploy_n := FLOOR(v_total * 0.85);
  -- start-of-shift: whole fleet charged + staged
  UPDATE vehicles SET current_soc = 90 + ottoq_sim_seeded_random(v_wseed,'soc:'||id::text)*8,
                      target_soc = 90, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=v_now
   WHERE home_depot_id=d AND category='autonomous';
  IF p_fault_chargers > 0 THEN
    UPDATE ottoq_ocpp_chargers SET station_state='Faulted', last_fault_code='STRESS_OUTAGE_CERT'
     WHERE charger_id IN (SELECT s.ocpp_charger_id FROM stalls s WHERE s.depot_id=d
        AND s.stall_type::text IN ('dcfc','l2') AND s.ocpp_charger_id IS NOT NULL
        ORDER BY s.stall_type::text, s.stall_code LIMIT p_fault_chargers);
  END IF;
  INSERT INTO ottoq_sim_runs (scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES ('ef24648f-eaf6-4686-bd07-1e018a8224ab','normal_day', v_now, v_now, v_now + interval '24 hours',
    d, 60, 30, 'running', p_policy, 'benchmark', 0, p_seed, p_ab_group, v_now, v_now, v_now)
  RETURNING sim_run_id INTO v_run;
  -- WAVE: deploy 85% fresh; they drain over the shift and return as a clustered low-SoC wave
  WITH picked AS (
    SELECT v.id, v.fleet_operator_id, v.current_soc FROM vehicles v
    WHERE v.home_depot_id=d AND v.category='autonomous'
    ORDER BY ottoq_sim_seeded_random(v_wseed, 'pick:'||v.id::text) LIMIT v_deploy_n)
  INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
  SELECT gen_random_uuid(), p.id, v_run, p.fleet_operator_id, v_now,
         v_now + ((360 + ottoq_sim_seeded_random(v_wseed,'ret:'||p.id::text)*240) || ' minutes')::interval,
         420, p.current_soc, 'active' FROM picked p;
  UPDATE vehicles SET current_state='deployed', last_state_change=v_now
   WHERE id IN (SELECT vehicle_id FROM ottoq_vehicle_dispatches WHERE sim_run_id=v_run AND status='active');
  FOR i IN 1..p_ticks LOOP
    PERFORM ottoq_sim_advance_and_snapshot(v_run);
    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=v_run) <> 'running';
  END LOOP;
  PERFORM ottoq_score_run(v_run);
  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=v_run;
  UPDATE ottoq_ocpp_chargers SET station_state='Available', last_fault_code=NULL
   WHERE depot_id=d AND last_fault_code='STRESS_OUTAGE_CERT';
END $procedure$

-- ===== ottoq_cert_arm_finish =====
CREATE OR REPLACE FUNCTION public.ottoq_cert_arm_finish(p_run uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_score_run(p_run);
  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=p_run;
  UPDATE ottoq_ocpp_chargers SET station_state='Available', last_fault_code=NULL
   WHERE depot_id=d AND last_fault_code='STRESS_OUTAGE_CERT';
END;
$function$

-- ===== ottoq_cert_arm_start =====
CREATE OR REPLACE FUNCTION public.ottoq_cert_arm_start(p_seed bigint, p_policy text, p_ab_group uuid, p_fault_chargers integer DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run uuid; v_now timestamptz := now(); v_wseed bigint; v_deploy_n int; v_total int;
        d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 80);
  UPDATE ottoq_bess_units SET current_soc_pct = 90.0, current_temperature_c = 25.0 WHERE depot_id = d;
  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'wave', 17));
  SELECT count(*) INTO v_total FROM vehicles WHERE home_depot_id=d AND category='autonomous';
  v_deploy_n := FLOOR(v_total * 0.85);

  UPDATE vehicles SET current_soc = 90 + ottoq_sim_seeded_random(v_wseed,'soc:'||id::text)*8,
                      target_soc = 90, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=v_now
   WHERE home_depot_id=d AND category='autonomous';

  IF p_fault_chargers > 0 THEN
    UPDATE ottoq_ocpp_chargers SET station_state='Faulted', last_fault_code='STRESS_OUTAGE_CERT'
     WHERE charger_id IN (SELECT s.ocpp_charger_id FROM stalls s WHERE s.depot_id=d
        AND s.stall_type IN ('dcfc'::stall_type,'l2'::stall_type) AND s.ocpp_charger_id IS NOT NULL
        ORDER BY s.stall_type, s.stall_code LIMIT p_fault_chargers);
  END IF;

  INSERT INTO ottoq_sim_runs (scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES ('ef24648f-eaf6-4686-bd07-1e018a8224ab','normal_day', v_now, v_now, v_now + interval '24 hours',
    d, 60, 30, 'running', p_policy, 'benchmark', 0, p_seed, p_ab_group, v_now, v_now, v_now)
  RETURNING sim_run_id INTO v_run;

  WITH picked AS (
    SELECT v.id, v.fleet_operator_id, v.current_soc FROM vehicles v
    WHERE v.home_depot_id=d AND v.category='autonomous'
    ORDER BY ottoq_sim_seeded_random(v_wseed, 'pick:'||v.id::text) LIMIT v_deploy_n)
  INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
  SELECT gen_random_uuid(), p.id, v_run, p.fleet_operator_id, v_now,
         v_now + ((360 + ottoq_sim_seeded_random(v_wseed,'ret:'||p.id::text)*240) || ' minutes')::interval,
         420, p.current_soc, 'active' FROM picked p;

  UPDATE vehicles SET current_state='deployed', last_state_change=v_now
   WHERE id IN (SELECT vehicle_id FROM ottoq_vehicle_dispatches WHERE sim_run_id=v_run AND status='active');

  RETURN v_run;
END;
$function$

-- ===== ottoq_cert_arm_step =====
CREATE OR REPLACE FUNCTION public.ottoq_cert_arm_step(p_run uuid, p_ticks integer)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE i int; v_done int := 0;
BEGIN
  FOR i IN 1..p_ticks LOOP
    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) <> 'running';
    PERFORM ottoq_sim_advance_and_snapshot(p_run);
    v_done := v_done + 1;
  END LOOP;
  RETURN v_done;
END;
$function$

-- ===== ottoq_cert_arm_wave =====
CREATE OR REPLACE PROCEDURE public.ottoq_cert_arm_wave(IN p_seed bigint, IN p_policy text, IN p_ab_group uuid, IN p_ticks integer, IN p_fault_chargers integer DEFAULT 0)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $procedure$
DECLARE v_run uuid; i int; v_now timestamptz := now(); v_wseed bigint; v_total int;
        d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 80);
  UPDATE ottoq_bess_units SET current_soc_pct = 90.0, current_temperature_c = 25.0 WHERE depot_id = d;
  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'wave', 17));
  SELECT count(*) INTO v_total FROM vehicles WHERE home_depot_id=d AND category='autonomous';
  -- start-of-evening: whole fleet out on shift, charged this morning
  -- end-of-shift v2: the fleet is DEEP into its shift — low SoC, real charge demand
  UPDATE vehicles SET current_soc = 24 + ottoq_sim_seeded_random(v_wseed,'soc:'||id::text)*16,
                      target_soc = 90, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=v_now
   WHERE home_depot_id=d AND category='autonomous';
  IF p_fault_chargers > 0 THEN
    UPDATE ottoq_ocpp_chargers SET station_state='Faulted', last_fault_code='SCARCITY_SWEEP_CERT'
     WHERE charger_id IN (SELECT s.ocpp_charger_id FROM stalls s WHERE s.depot_id=d
        AND s.stall_type::text IN ('dcfc','l2') AND s.ocpp_charger_id IS NOT NULL
        ORDER BY CASE WHEN s.stall_type::text='l2' THEN 0 ELSE 1 END, s.stall_code LIMIT p_fault_chargers);
  END IF;
  INSERT INTO ottoq_sim_runs (scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES ('ef24648f-eaf6-4686-bd07-1e018a8224ab','overnight_wave', v_now, v_now, v_now + interval '24 hours',
    d, 60, 30, 'running', p_policy, 'benchmark', 0, p_seed, p_ab_group, v_now, v_now, v_now)
  RETURNING sim_run_id INTO v_run;
  -- THE WAVE: 100% of the fleet out, ALL returning within 60-180 min (compressed arrivals)
  WITH picked AS (
    SELECT v.id, v.fleet_operator_id, v.current_soc FROM vehicles v
    WHERE v.home_depot_id=d AND v.category='autonomous')
  INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
  SELECT gen_random_uuid(), p.id, v_run, p.fleet_operator_id, v_now - interval '9 hours',
         v_now + ((60 + ottoq_sim_seeded_random(v_wseed,'ret:'||p.id::text)*120) || ' minutes')::interval,
         630, p.current_soc, 'active' FROM picked p;
  UPDATE vehicles SET current_state='deployed', last_state_change=v_now
   WHERE id IN (SELECT vehicle_id FROM ottoq_vehicle_dispatches WHERE sim_run_id=v_run AND status='active');
  FOR i IN 1..p_ticks LOOP
    PERFORM ottoq_sim_advance_and_snapshot(v_run);
    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=v_run) <> 'running';
  END LOOP;
  PERFORM ottoq_score_run(v_run);
  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=v_run;
  UPDATE ottoq_ocpp_chargers SET station_state='Available', last_fault_code=NULL
   WHERE depot_id=d AND last_fault_code='SCARCITY_SWEEP_CERT';
END $procedure$

-- ===== ottoq_cert_battery_step =====
CREATE OR REPLACE FUNCTION public.ottoq_cert_battery_step()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_job ottoq_cert_queue%ROWTYPE;
  v_t0  timestamptz := clock_timestamp();
BEGIN
  -- transaction-scoped lock: two concurrent invocations can never both run an arm
  IF NOT pg_try_advisory_xact_lock(hashtext('ottoq_cert_battery')::bigint) THEN
    RETURN jsonb_build_object('skipped', 'lock_held');
  END IF;
  -- never start while any benchmark run is live (stale 'running' = manual cleanup first)
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs
              WHERE depot_id = '22222222-2222-2222-2222-222222222222' AND status = 'running') THEN
    RETURN jsonb_build_object('skipped', 'bench_busy');
  END IF;

  SELECT * INTO v_job FROM ottoq_cert_queue
   WHERE status = 'pending' ORDER BY id LIMIT 1
   FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN jsonb_build_object('idle', true); END IF;

  UPDATE ottoq_cert_queue SET status = 'running', started_at = now() WHERE id = v_job.id;

  BEGIN
    IF v_job.scenario = 'shift' THEN
      CALL ottoq_cert_arm(v_job.seed, v_job.policy, v_job.ab_group, v_job.ticks, NULL, v_job.fault_chargers);
    ELSIF v_job.scenario = 'wave' THEN
      CALL ottoq_cert_arm_wave(v_job.seed, v_job.policy, v_job.ab_group, v_job.ticks, v_job.fault_chargers);
    END IF;
    UPDATE ottoq_cert_queue SET status = 'done', finished_at = now() WHERE id = v_job.id;
    RETURN jsonb_build_object('ran', v_job.id, 'scenario', v_job.scenario, 'seed', v_job.seed,
      'policy', v_job.policy, 'secs', round(extract(epoch FROM clock_timestamp() - v_t0)::numeric, 1));
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_cert_queue SET status = 'error', error = SQLERRM, finished_at = now() WHERE id = v_job.id;
    -- leave the failed benchmark run aborted so the next step isn't blocked
    UPDATE ottoq_sim_runs SET status = 'aborted', ended_at = now()
     WHERE depot_id = '22222222-2222-2222-2222-222222222222' AND status = 'running';
    RETURN jsonb_build_object('error', SQLERRM, 'job', v_job.id);
  END;
END;
$function$

-- ===== ottoq_certify_run =====
CREATE OR REPLACE FUNCTION public.ottoq_certify_run(p_sim_run_id uuid)
 RETURNS TABLE(ticks_examined integer, unsafe_deploy_ticks integer, over_stall_ticks integer, charge_offline_ticks integer, over_power_ticks integer, over_power_measurable integer, worst_dcfc_draw_kw numeric, dcfc_cap_kw numeric, certified boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_cap numeric;
BEGIN
  SELECT d.dcfc_max_concurrent_kw INTO v_cap
    FROM ottoq_sim_runs r JOIN depots d ON d.id = r.depot_id
   WHERE r.sim_run_id = p_sim_run_id;

  WITH per_tick AS (
    SELECT
      s.tick_seq,
      -- B1: a stall id held by more than one vehicle in this frame
      (SELECT count(*) FROM (
         SELECT v->>'stall_id' AS sid
           FROM jsonb_array_elements(COALESCE(s.frame->'vehicles','[]'::jsonb)) v
          WHERE COALESCE(v->>'stall_id','') <> ''
          GROUP BY 1 HAVING count(*) > 1) x) AS b1,
      -- B2: deployed (or heading out) below the vehicle's own floor
      (SELECT count(*) FROM jsonb_array_elements(COALESCE(s.frame->'vehicles','[]'::jsonb)) v
        WHERE v->>'state' IN ('deployed','en_route_to_deployment')
          AND (v->>'soc')::numeric < COALESCE((v->>'min_soc_threshold')::numeric, 15)) AS b2,
      -- B3: charging at a stall the frame reports as not usable
      (SELECT count(*) FROM jsonb_array_elements(COALESCE(s.frame->'vehicles','[]'::jsonb)) v
         JOIN jsonb_array_elements(COALESCE(s.frame->'stalls','[]'::jsonb)) st
           ON st->>'id' = v->>'stall_id'
        WHERE v->>'state' IN ('charging_dcfc','charging_l2')
          AND lower(COALESCE(st->>'status','')) IN ('faulted','unavailable','offline')) AS b3,
      -- B4: real metered draw on DCFC stalls this tick (NULL when unrecorded)
      (SELECT CASE WHEN count(*) FILTER (WHERE se ? 'power_kw' AND se->>'power_kw' IS NOT NULL) = 0
                   THEN NULL
                   ELSE COALESCE(SUM((se->>'power_kw')::numeric), 0) END
         FROM jsonb_array_elements(COALESCE(s.frame->'sessions','[]'::jsonb)) se
         JOIN jsonb_array_elements(COALESCE(s.frame->'stalls','[]'::jsonb)) st
           ON st->>'id' = se->>'stall_id'
        WHERE st->>'type' = 'dcfc' AND se->>'status' = 'active') AS dcfc_kw
    FROM ottoq_decision_snapshots s
   WHERE s.sim_run_id = p_sim_run_id
  )
  SELECT
    count(*)::int,
    count(*) FILTER (WHERE b2 > 0)::int,
    count(*) FILTER (WHERE b1 > 0)::int,
    count(*) FILTER (WHERE b3 > 0)::int,
    count(*) FILTER (WHERE dcfc_kw IS NOT NULL AND v_cap IS NOT NULL AND dcfc_kw > v_cap)::int,
    count(*) FILTER (WHERE dcfc_kw IS NOT NULL)::int,
    max(dcfc_kw),
    v_cap,
    (count(*) FILTER (WHERE b1 > 0 OR b2 > 0 OR b3 > 0) = 0
     AND count(*) FILTER (WHERE dcfc_kw IS NOT NULL AND v_cap IS NOT NULL AND dcfc_kw > v_cap) = 0
     AND count(*) FILTER (WHERE dcfc_kw IS NOT NULL) > 0
     AND count(*) > 0)
  INTO ticks_examined, unsafe_deploy_ticks, over_stall_ticks, charge_offline_ticks,
       over_power_ticks, over_power_measurable, worst_dcfc_draw_kw, dcfc_cap_kw, certified
  FROM per_tick;

  RETURN NEXT;
END;
$function$

-- ===== ottoq_charge_minutes_between =====
CREATE OR REPLACE FUNCTION public.ottoq_charge_minutes_between(p_soc_from numeric, p_soc_to numeric, p_charger_kw numeric, p_vehicle_max_kw numeric DEFAULT 150, p_batt_kwh numeric DEFAULT 75, p_soh numeric DEFAULT 95, p_temp_c numeric DEFAULT 22, p_step_pct numeric DEFAULT 0.5)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE s numeric := p_soc_from; kw numeric; mins numeric := 0; dkwh numeric;
BEGIN
  dkwh := p_step_pct/100.0 * p_batt_kwh;
  WHILE s < p_soc_to LOOP
    kw := ottoq_sim_compute_charge_rate(
            p_soc_pct := s, p_battery_temp_c := p_temp_c, p_ambient_temp_c := p_temp_c,
            p_charger_max_kw := p_charger_kw, p_vehicle_max_kw := p_vehicle_max_kw,
            p_battery_capacity_kwh := p_batt_kwh, p_battery_soh_pct := p_soh,
            p_noise_seed := 42, p_noise_salt := 'mix');
    EXIT WHEN kw <= 0.1;
    mins := mins + (dkwh / kw) * 60.0;
    s := s + p_step_pct;
  END LOOP;
  RETURN ROUND(mins, 1);
END; $function$

-- ===== ottoq_charge_plan_for_visit =====
CREATE OR REPLACE FUNCTION public.ottoq_charge_plan_for_visit(p_vehicle_id uuid, p_clock timestamp with time zone DEFAULT now(), p_hours_until_deploy numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v vehicles%ROWTYPE; v_hour int; v_overnight boolean; v_chem text;
  v_target numeric; v_class text; v_slack numeric; v_l2_min numeric; v_reason text;
  v_days_since numeric; v_bal int; v_baseline timestamptz;
BEGIN
  SELECT * INTO v FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason','vehicle_not_found'); END IF;
  v_chem := COALESCE(v.config->>'battery_chemistry', 'lfp');
  v_bal  := COALESCE((v.config->>'balance_interval_days')::int, 0);
  v_hour := EXTRACT(HOUR FROM (p_clock AT TIME ZONE 'America/Chicago'))::int;
  v_overnight := (v_hour >= 21 OR v_hour < 5);
  v_slack := COALESCE(p_hours_until_deploy,
               CASE WHEN v_overnight
                    THEN GREATEST(0.5, 5.0 + CASE WHEN v_hour >= 21 THEN (24 - v_hour) ELSE -v_hour END)
                    ELSE 1.0 END);
  v_target := COALESCE((v.config->>'nightly_soc_target')::numeric,
                       CASE WHEN v_chem='lfp' THEN 100 ELSE 90 END);

  IF v_chem <> 'lfp' AND v_bal > 0 THEN
    -- baseline = last recorded balance charge, else the onboarding date (NOT "due now")
    v_baseline := COALESCE((v.config->>'last_balance_charge_at')::timestamptz,
                           (v.config->>'battery_onboarded_at')::timestamptz, p_clock);
    v_days_since := EXTRACT(EPOCH FROM (p_clock - v_baseline))/86400.0;
    IF v_days_since >= v_bal THEN v_target := 100; v_reason := 'nmc_periodic_balance_charge'; END IF;
  END IF;

  v_l2_min := ottoq_charge_minutes_between(COALESCE(v.current_soc,20), v_target, 19.2, 150,
                COALESCE(v.battery_capacity_kwh,75), COALESCE((v.config->>'battery_soh_pct')::numeric,95));

  IF v_overnight AND (v_l2_min/60.0) <= v_slack THEN
    v_class := 'l2'; v_reason := COALESCE(v_reason, 'overnight_l2_full_charge');
  ELSIF v_overnight THEN
    v_class := 'dcfc'; v_target := LEAST(v_target, 90); v_reason := 'late_overnight_dcfc_capped_90';
  ELSE
    v_class := 'dcfc'; v_target := 80; v_reason := 'daytime_fast_turnaround_80';
  END IF;

  RETURN jsonb_build_object('ok', true, 'vehicle_id', p_vehicle_id,
    'charger_class', v_class, 'target_soc', v_target, 'chemistry', v_chem,
    'overnight', v_overnight, 'hours_until_deploy', ROUND(v_slack,2),
    'est_l2_minutes_to_target', v_l2_min, 'reason', v_reason, 'no_mid_session_switch', true);
END; $function$

-- ===== ottoq_charger_mix_analysis =====
CREATE OR REPLACE FUNCTION public.ottoq_charger_mix_analysis(p_fleet integer DEFAULT 100, p_window_h numeric DEFAULT 7.0, p_arrive_soc numeric DEFAULT 25, p_handoff_soc numeric DEFAULT 80, p_batt_kwh numeric DEFAULT 75, p_dcfc_kw numeric DEFAULT 150, p_l2_kw numeric DEFAULT 19.2, p_dcfc_capex numeric DEFAULT 100000, p_l2_capex numeric DEFAULT 6000)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  t_dc_full numeric; t_dc_hand numeric; t_l2_full numeric; t_l2_top numeric;
  n_dc_only int; n_dc_hand int; n_l2_hand int; cap_only numeric; cap_hand numeric;
BEGIN
  t_dc_full := ottoq_charge_minutes_between(p_arrive_soc, 100, p_dcfc_kw, 150, p_batt_kwh);
  t_dc_hand := ottoq_charge_minutes_between(p_arrive_soc, p_handoff_soc, p_dcfc_kw, 150, p_batt_kwh);
  t_l2_full := ottoq_charge_minutes_between(p_arrive_soc, 100, p_l2_kw, 150, p_batt_kwh);
  t_l2_top  := ottoq_charge_minutes_between(p_handoff_soc, 100, p_l2_kw, 150, p_batt_kwh);

  -- chargers needed (throughput bound, 15% headroom for arrival timing)
  n_dc_only := CEIL(p_fleet * (t_dc_full/60.0) / p_window_h * 1.15);
  n_dc_hand := CEIL(p_fleet * (t_dc_hand/60.0) / p_window_h * 1.15);
  n_l2_hand := CEIL(p_fleet * (t_l2_top /60.0) / p_window_h * 1.15);
  cap_only  := n_dc_only * p_dcfc_capex;
  cap_hand  := n_dc_hand * p_dcfc_capex + n_l2_hand * p_l2_capex;

  RETURN jsonb_build_object(
    'assumptions', jsonb_build_object('fleet',p_fleet,'window_h',p_window_h,'arrive_soc',p_arrive_soc,
      'handoff_soc',p_handoff_soc,'batt_kwh',p_batt_kwh,'dcfc_kw',p_dcfc_kw,'l2_kw',p_l2_kw),
    'charge_minutes', jsonb_build_object(
      'dcfc_'||p_arrive_soc||'_to_100', t_dc_full,
      'dcfc_'||p_arrive_soc||'_to_'||p_handoff_soc, t_dc_hand,
      'dcfc_'||p_handoff_soc||'_to_100_TAPER', ROUND(t_dc_full - t_dc_hand,1),
      'l2_'||p_arrive_soc||'_to_100', t_l2_full,
      'l2_'||p_handoff_soc||'_to_100', t_l2_top),
    'dcfc_sessions_per_stall_per_hour', jsonb_build_object(
      'charging_to_100_on_dcfc', ROUND(60.0/NULLIF(t_dc_full,0),2),
      'handoff_at_'||p_handoff_soc, ROUND(60.0/NULLIF(t_dc_hand,0),2)),
    'strategy_A_dcfc_only', jsonb_build_object('dcfc_needed',n_dc_only,'l2_needed',0,
      'peak_kw', n_dc_only*p_dcfc_kw, 'charger_capex_usd', cap_only),
    'strategy_B_handoff', jsonb_build_object('dcfc_needed',n_dc_hand,'l2_needed',n_l2_hand,
      'peak_kw', n_dc_hand*p_dcfc_kw + n_l2_hand*p_l2_kw, 'charger_capex_usd', cap_hand),
    'handoff_advantage', jsonb_build_object(
      'dcfc_throughput_multiple', ROUND(t_dc_full/NULLIF(t_dc_hand,0),2),
      'charger_capex_saved_usd', cap_only - cap_hand,
      'peak_kw_reduction', n_dc_only*p_dcfc_kw - (n_dc_hand*p_dcfc_kw + n_l2_hand*p_l2_kw)));
END; $function$

-- ===== ottoq_cil_propose =====
CREATE OR REPLACE FUNCTION public.ottoq_cil_propose(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_efactor numeric; v_deploy numeric;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  v_efactor := ottoq_policy_get(p_sim_run_id,'energy_demand_factor_peak',0.50);
  v_deploy  := ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',0.90);
  RETURN jsonb_build_array(
    jsonb_build_object('label','current','params', jsonb_build_object()),
    jsonb_build_object('label','energy_shave_more','params', jsonb_build_object('energy_demand_factor_peak', GREATEST(0.15, v_efactor-0.10))),
    jsonb_build_object('label','energy_relax','params',      jsonb_build_object('energy_demand_factor_peak', LEAST(0.90, v_efactor+0.10))),
    jsonb_build_object('label','deploy_more','params',       jsonb_build_object('deploy_peak_fraction', LEAST(1.00, v_deploy+0.05)))
  );
END;
$function$

-- ===== ottoq_cil_tick =====
CREATE OR REPLACE FUNCTION public.ottoq_cil_tick(p_sim_run_id uuid, p_horizon integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_plans jsonb; v_depot uuid; v_eval jsonb;
  v_cur_score numeric; v_best_label text; v_best_score numeric; v_best_params jsonb;
  k text; val text; v_adopted boolean := false; v_result jsonb; v_rationale text;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  v_plans := ottoq_cil_propose(p_sim_run_id);

  -- evaluate every plan forward in the twin (fork+rollback, 0-unsafe hard gate inside the MPC)
  SELECT jsonb_agg(jsonb_build_object('label',plan_label,'score',score,'feasible',feasible,
                                      'peak',predicted_peak_kw,'throughput',throughput,'readiness',am_readiness))
    INTO v_eval
    FROM ottoq_mpc_lookahead(p_sim_run_id, v_plans, p_horizon, 'balanced')
   WHERE NOT is_best AND plan_label IS NOT NULL;

  SELECT (e->>'score')::numeric INTO v_cur_score
    FROM jsonb_array_elements(v_eval) e WHERE e->>'label' = 'current';
  SELECT e->>'label', (e->>'score')::numeric INTO v_best_label, v_best_score
    FROM jsonb_array_elements(v_eval) e
   WHERE (e->>'feasible')::boolean AND (e->>'score') IS NOT NULL
   ORDER BY (e->>'score')::numeric DESC LIMIT 1;

  IF v_best_label IS NOT NULL AND v_best_label <> 'current'
     AND v_best_score > COALESCE(v_cur_score, -1) + 0.01 THEN
    SELECT e->'params' INTO v_best_params FROM jsonb_array_elements(v_plans) e WHERE e->>'label' = v_best_label;
    FOR k, val IN SELECT * FROM jsonb_each_text(v_best_params) LOOP
      INSERT INTO ottoq_policy_params(scope_type, scope_id, param_key, param_value, updated_by)
        VALUES ('depot', v_depot, k, val::numeric, 'cil')
        ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value, updated_at = now();
    END LOOP;
    v_adopted := true;
    v_rationale := format('Twin A/B: %s scored %s vs current %s (0-unsafe) → adopted to depot policy.',
                          v_best_label, round(v_best_score,3), round(coalesce(v_cur_score,0),3));
  ELSE
    v_rationale := format('Current policy is best (%s); no tweak beat it on a 0-unsafe basis.', round(coalesce(v_cur_score,0),3));
  END IF;

  INSERT INTO ottoq_cil_adoptions(sim_run_id, depot_id, adopted, plan_label, params, score_current, score_adopted, source, rationale, eval)
  VALUES (p_sim_run_id, v_depot, v_adopted, CASE WHEN v_adopted THEN v_best_label ELSE 'current' END,
          COALESCE(v_best_params,'{}'::jsonb), v_cur_score, CASE WHEN v_adopted THEN v_best_score ELSE v_cur_score END,
          'cil_heuristic', v_rationale, v_eval);

  PERFORM ottoq_record_event(
    p_actor_type:='ottoq_engine', p_actor_id:='cil', p_event_type:='ottoq.cil_decision',
    p_entity_type:='depot', p_entity_id:=v_depot, p_depot_id:=v_depot,
    p_payload:=jsonb_build_object('adopted',v_adopted,'plan',v_best_label,'rationale',v_rationale,'eval',v_eval),
    p_severity:='info', p_ingest_source:='otto_q', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);

  v_result := jsonb_build_object('adopted',v_adopted,'chosen',COALESCE(v_best_label,'current'),
     'score_current',v_cur_score,'score_chosen',COALESCE(v_best_score,v_cur_score),'rationale',v_rationale,'eval',v_eval);
  RETURN v_result;
END;
$function$

-- ===== ottoq_claim_tick_kw =====
CREATE OR REPLACE FUNCTION public.ottoq_claim_tick_kw(p_sim_run_id uuid, p_tick_seq bigint, p_depot_id uuid, p_amount_kw numeric, p_entity_id uuid DEFAULT NULL::uuid, p_resource text DEFAULT 'grid_kw'::text)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  INSERT INTO ottoq_tick_reservations (sim_run_id, tick_seq, depot_id, resource, entity_id, amount_kw)
  VALUES (p_sim_run_id, p_tick_seq, p_depot_id, p_resource, p_entity_id, p_amount_kw)
  RETURNING reservation_id;
$function$

-- ===== ottoq_cleaning_due =====
CREATE OR REPLACE FUNCTION public.ottoq_cleaning_due(p_vehicle_id uuid, p_interior_hours integer DEFAULT 24, p_exterior_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_now           timestamptz := now();
  v_last_interior timestamptz;
  v_last_exterior timestamptz;
  v_interior_due  boolean;
  v_exterior_due  boolean;
  v_rec           text[] := ARRAY[]::text[];
BEGIN
  SELECT max(coalesce(actual_end, confirmation_timestamp, scheduled_end)) INTO v_last_interior
    FROM schedule_tasks
   WHERE vehicle_id = p_vehicle_id AND status = 'completed' AND lower(service_code) IN ('interior_detail','full_detail');
  SELECT max(coalesce(actual_end, confirmation_timestamp, scheduled_end)) INTO v_last_exterior
    FROM schedule_tasks
   WHERE vehicle_id = p_vehicle_id AND status = 'completed' AND lower(service_code) IN ('exterior_wash','full_detail','wash');

  v_interior_due := v_last_interior IS NULL OR v_last_interior < v_now - make_interval(hours => p_interior_hours);
  v_exterior_due := v_last_exterior IS NULL OR v_last_exterior < v_now - make_interval(days  => p_exterior_days);
  IF v_interior_due THEN v_rec := array_append(v_rec, 'interior_detail'); END IF;
  IF v_exterior_due THEN v_rec := array_append(v_rec, 'exterior_wash');   END IF;

  RETURN jsonb_build_object(
    'vehicle_id', p_vehicle_id, 'now', v_now,
    'interior_due', v_interior_due, 'exterior_due', v_exterior_due,
    'last_interior_at', v_last_interior, 'last_exterior_at', v_last_exterior,
    'interior_threshold_hours', p_interior_hours, 'exterior_threshold_days', p_exterior_days,
    'recommended_cleaning_services', to_jsonb(v_rec)
  );
END;
$function$

-- ===== ottoq_clock_fidelity =====
CREATE OR REPLACE FUNCTION public.ottoq_clock_fidelity(p_sim_run_id uuid, p_last_n integer DEFAULT 20)
 RETURNS TABLE(ticks_measured integer, sim_seconds numeric, real_seconds numeric, ratio numeric, target_ratio numeric, playback_mode text, p50_tick_ms numeric, p95_tick_ms numeric, max_sustainable_speed numeric, within_tolerance boolean, verdict text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_mode text; v_spd numeric;
BEGIN
  SELECT COALESCE(l.playback_mode,'fixed'), COALESCE(l.speed_x,1.0)
    INTO v_mode, v_spd
    FROM ottoq_tick_clock_log l
   WHERE l.sim_run_id = p_sim_run_id
   ORDER BY l.real_started_at DESC LIMIT 1;
  IF v_mode IS NULL THEN RETURN; END IF;

  RETURN QUERY
  WITH t AS (
    SELECT * FROM ottoq_tick_clock_log
     WHERE sim_run_id = p_sim_run_id
     ORDER BY real_started_at DESC LIMIT GREATEST(2, p_last_n)
  ), agg AS (
    SELECT count(*)::int                                                            AS n,
           sum(sim_advance_s)::numeric                                              AS sim_s,
           EXTRACT(EPOCH FROM (max(real_ended_at) - min(real_started_at)))::numeric  AS real_s,
           (percentile_cont(0.50) WITHIN GROUP (ORDER BY tick_compute_ms))::numeric  AS p50,
           (percentile_cont(0.95) WITHIN GROUP (ORDER BY tick_compute_ms))::numeric  AS p95,
           avg(sim_advance_s)::numeric                                               AS avg_adv
      FROM t
  )
  SELECT a.n,
         round(a.sim_s,1),
         round(a.real_s,1),
         round(a.sim_s / NULLIF(a.real_s,0), 3),
         CASE WHEN v_mode='live' THEN v_spd ELSE NULL END,
         v_mode,
         round(a.p50,1),
         round(a.p95,1),
         -- HARD PHYSICAL CEILING: sim-seconds a tick represents / seconds to compute it.
         round(a.avg_adv / NULLIF(a.p95/1000.0, 0), 2),
         CASE WHEN v_mode<>'live' OR a.real_s=0 THEN NULL
              ELSE abs((a.sim_s/a.real_s) - v_spd)/v_spd < 0.05 END,
         CASE
           WHEN a.n < 2 THEN 'insufficient ticks'
           WHEN v_mode <> 'live' THEN
             'FIXED playback - compression ' || round(a.sim_s/NULLIF(a.real_s,0),1)::text ||
             'x. p95 tick ' || round(a.p95,0)::text || 'ms'
           WHEN abs((a.sim_s/a.real_s)-v_spd)/v_spd < 0.05 THEN
             'ON TARGET ' || v_spd::text || 'x (p95 tick ' || round(a.p95,0)::text || 'ms)'
           WHEN (a.sim_s/a.real_s) < v_spd THEN
             'RUNNING SLOW - tick cost exceeds budget. p95 ' || round(a.p95,0)::text || 'ms'
           ELSE 'RUNNING FAST ' || round(a.sim_s/a.real_s,2)::text || 'x vs target ' || v_spd::text ||
                'x (p95 tick ' || round(a.p95,0)::text || 'ms)'
         END
    FROM agg a;
END;
$function$

-- ===== ottoq_clock_fidelity_ticks =====
CREATE OR REPLACE FUNCTION public.ottoq_clock_fidelity_ticks(p_sim_run_id uuid, p_last_n integer DEFAULT 30)
 RETURNS TABLE(real_at timestamp with time zone, sim_at timestamp with time zone, real_delta_s numeric, sim_delta_s numeric, instant_ratio numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH s AS (
    SELECT created_at AS real_ts, timestamp AS sim_ts,
           lag(created_at) OVER (ORDER BY created_at) AS prev_real,
           lag(timestamp)  OVER (ORDER BY created_at) AS prev_sim
      FROM site_energy_snapshots
     WHERE sim_run_id = p_sim_run_id
     ORDER BY created_at DESC
     LIMIT GREATEST(2, p_last_n)
  )
  SELECT real_ts, sim_ts,
         round(EXTRACT(EPOCH FROM (real_ts - prev_real))::numeric, 2),
         round(EXTRACT(EPOCH FROM (sim_ts  - prev_sim))::numeric, 1),
         round((EXTRACT(EPOCH FROM (sim_ts - prev_sim))
              / NULLIF(EXTRACT(EPOCH FROM (real_ts - prev_real)),0))::numeric, 2)
    FROM s WHERE prev_real IS NOT NULL
   ORDER BY real_ts DESC;
$function$

-- ===== ottoq_close_atom_leg =====
CREATE OR REPLACE FUNCTION public.ottoq_close_atom_leg(p_sim_run_id uuid, p_vehicle uuid, p_svc text, p_started timestamp with time zone, p_ended timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_leg uuid; v_planned_end timestamptz;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN; END IF;
  SELECT leg_id, planned_end_sim INTO v_leg, v_planned_end FROM ottoq_itinerary_legs
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle
     AND leg_type = p_svc AND status IN ('planned','active')
   ORDER BY seq LIMIT 1;
  IF v_leg IS NULL THEN RETURN; END IF;
  UPDATE ottoq_itinerary_legs
     SET status = 'done',
         actual_start_sim = COALESCE(actual_start_sim, p_started),
         actual_end_sim = p_ended,
         deviation_s = CASE WHEN v_planned_end IS NULL THEN NULL
                            ELSE EXTRACT(EPOCH FROM (p_ended - v_planned_end))::int END
   WHERE leg_id = v_leg;
END; $function$

-- ===== ottoq_comms_advance =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_advance(p_run uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE d RECORD; v_seed bigint; v_n int := 0; v_eta jsonb;
BEGIN
  FOR d IN
    SELECT dp.dispatch_id, dp.vehicle_id, dp.status, dp.dispatched_at
      FROM ottoq_vehicle_dispatches dp
     WHERE dp.sim_run_id = p_run AND dp.status IN ('active','returning')
  LOOP
    v_seed := abs(hashtextextended(d.vehicle_id::text || p_clock::text, 9));
    -- uplink: SAE J2735 BSM telemetry (speed/heading plausible; position null until real GPS feed)
    PERFORM ottoq_comms_emit_telemetry(p_run, d.vehicle_id, p_clock, NULL, NULL,
      ROUND(((20 + (v_seed % 70)) / 3.6)::numeric, 2), (v_seed % 360));
    v_n := v_n + 1;

    -- downlink: recall command once, when the trip flips to returning
    IF d.status = 'returning' AND NOT EXISTS (
        SELECT 1 FROM ottoq_comms_messages m
         WHERE m.sim_run_id = p_run AND m.vehicle_id = d.vehicle_id
           AND m.msg_type = 'command' AND m.payload->>'command' = 'recall'
           AND m.sim_clock_at >= d.dispatched_at) THEN
      PERFORM ottoq_comms_send_command(p_run, d.vehicle_id, 'recall',
        jsonb_build_object('to','depot','dispatch_id', d.dispatch_id), p_clock, false);
    END IF;

    -- edge case: an applied ETA-delay → OTTO-Q asks to stage/re-queue → teleop gate (once)
    SELECT meta INTO v_eta FROM ottoq_variability_cards
      WHERE sim_run_id = p_run AND var_key = 'eta_delay' AND scope_instance = d.dispatch_id::text
        AND (meta->>'applied')::boolean LIMIT 1;
    IF v_eta IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM ottoq_comms_messages m
         WHERE m.sim_run_id = p_run AND m.vehicle_id = d.vehicle_id
           AND m.msg_type = 'command' AND m.payload->>'command' = 'stage_hold') THEN
      PERFORM ottoq_comms_send_command(p_run, d.vehicle_id, 'stage_hold',
        jsonb_build_object('reason','eta_delay','cause', v_eta->>'cause', 'delay_min', v_eta->>'delay_min'),
        p_clock, true);
    END IF;
  END LOOP;
  RETURN v_n;
END $function$

-- ===== ottoq_comms_emit_telemetry =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_emit_telemetry(p_run uuid, p_vehicle uuid, p_clock timestamp with time zone, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_speed_mps numeric DEFAULT NULL::numeric, p_heading numeric DEFAULT NULL::numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v RECORD; v_dropout numeric; v_dropped boolean; v_payload jsonb; v_msg_id uuid; v_seed bigint;
BEGIN
  SELECT current_soc, current_state, battery_capacity_kwh INTO v FROM vehicles WHERE id=p_vehicle;
  v_seed := abs(hashtextextended(p_run::text||p_vehicle::text||p_clock::text,7));
  v_dropout := 0.01 * COALESCE(ottoq_profile_rate_mult(p_run,'telemetry_dropout'),1);  -- comms-loss variable
  v_dropped := ottoq_sim_seeded_random(v_seed,'drop') < v_dropout;
  v_payload := jsonb_build_object(
    'bsm_core', jsonb_build_object(
      'msgCnt', (EXTRACT(EPOCH FROM p_clock)::bigint % 128),
      'secMark', (EXTRACT(SECOND FROM p_clock)*1000)::int,
      'position', jsonb_build_object('lat',p_lat,'long',p_lng,'elev_m',180),
      'speed_mps', ROUND(COALESCE(p_speed_mps,0)::numeric,2),
      'heading_deg', ROUND(COALESCE(p_heading,0)::numeric,1),
      'accelSet', jsonb_build_object('long_mps2',0,'lat_mps2',0,'vert_g',1.0,'yaw_degps',0),
      'brakes', 'unavailable', 'size', jsonb_build_object('width_cm',200,'length_cm',490)),
    'ev_ext', jsonb_build_object('soc_pct', v.current_soc,
      'usable_kwh', ROUND((COALESCE(v.battery_capacity_kwh,75)*COALESCE(v.current_soc,0)/100.0)::numeric,1)),
    'av_ext', jsonb_build_object('autonomy_level',4,'ads_engaged',true,'mission_state',v.current_state::text));
  INSERT INTO ottoq_comms_messages(sim_run_id,vehicle_id,direction,topic,msg_type,qos,header,payload,status,latency_ms,sim_clock_at)
  VALUES (p_run,p_vehicle,'uplink','fleet/'||p_vehicle::text||'/telemetry/bsm','telemetry',1,
    ottoq_comms_envelope(p_vehicle,'telemetry',NULL,p_clock), v_payload,
    CASE WHEN v_dropped THEN 'dropped' ELSE 'delivered' END,
    CASE WHEN v_dropped THEN NULL ELSE (40 + (v_seed % 80))::int END, p_clock)
  RETURNING msg_id INTO v_msg_id;
  RETURN v_msg_id;
END $function$

-- ===== ottoq_comms_envelope =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_envelope(p_vehicle uuid, p_msg_type text, p_correlation uuid, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'vehicle_uuid', p_vehicle, 'message_type', p_msg_type, 'message_uuid', gen_random_uuid(),
    'correlation_id', p_correlation, 'message_version', '1.0',
    'timestamp_utc', to_char(p_clock AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'schema', 'OTTOYARD-Fleet/1.0 (SAE J2735 BSM + ISO 20078 ExVe envelope, MQTT transport)');
$function$

-- ===== ottoq_comms_escalate =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_escalate(p_run uuid, p_vehicle uuid, p_command text, p_params jsonb, p_clock timestamp with time zone, p_source text DEFAULT 'ai_uncertain'::text, p_summary text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_corr uuid := gen_random_uuid();
BEGIN
  INSERT INTO ottoq_comms_messages(sim_run_id,vehicle_id,correlation_id,direction,topic,msg_type,qos,header,payload,status,sim_clock_at)
  VALUES (p_run,p_vehicle,v_corr,'uplink','fleet/'||p_vehicle::text||'/assist/req','assist_request',1,
    ottoq_comms_envelope(p_vehicle,'assist_request',v_corr,p_clock),
    jsonb_build_object('situation','outside_normal_orchestration_parameters','proposed_action',p_command,
      'params',COALESCE(p_params,'{}'::jsonb),'source',p_source,
      'summary',COALESCE(p_summary, p_command||' on vehicle '||left(p_vehicle::text,8)),
      'control_mode','indirect','escalated_to_human',true),
    'pending_human', p_clock);
  RETURN jsonb_build_object('correlation_id',v_corr,'status','pending_human','proposed_action',p_command);
END $function$

-- ===== ottoq_comms_locate_vehicle =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_locate_vehicle(p_query text, p_run uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_id uuid; v_clean text;
BEGIN
  v_clean := lower(trim(COALESCE(p_query,'')));
  BEGIN v_id := v_clean::uuid; EXCEPTION WHEN others THEN v_id := NULL; END;
  IF v_id IS NULL OR NOT EXISTS (SELECT 1 FROM vehicles WHERE id=v_id) THEN
    SELECT id INTO v_id FROM vehicles
     WHERE id::text LIKE replace(replace(v_clean,'%',''),'_','')||'%' AND length(v_clean) >= 4
     ORDER BY id LIMIT 1;
  END IF;
  IF v_id IS NULL THEN RETURN jsonb_build_object('found',false,'query',p_query,'note','no vehicle matches that id/prefix'); END IF;
  RETURN ottoq_comms_vehicle_status(v_id, p_run) || jsonb_build_object('found',true);
END $function$

-- ===== ottoq_comms_manager_escalate =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_manager_escalate(p_vehicle_query text, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_id uuid; v_clean text; v_run uuid; v_clock timestamptz;
BEGIN
  v_clean := lower(trim(COALESCE(p_vehicle_query,'')));
  BEGIN v_id := v_clean::uuid; EXCEPTION WHEN others THEN v_id := NULL; END;
  IF v_id IS NULL OR NOT EXISTS (SELECT 1 FROM vehicles WHERE id=v_id) THEN
    SELECT id INTO v_id FROM vehicles
     WHERE id::text LIKE replace(replace(v_clean,'%',''),'_','')||'%' AND length(v_clean) >= 4
     ORDER BY id LIMIT 1;
  END IF;
  IF v_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','vehicle not found','query',p_vehicle_query); END IF;
  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock
    FROM ottoq_sim_runs WHERE status='running' ORDER BY sim_clock_current DESC NULLS LAST LIMIT 1;
  IF v_run IS NULL THEN SELECT owning_sim_run_id INTO v_run FROM vehicles WHERE id=v_id; v_clock := now(); END IF;
  RETURN ottoq_comms_escalate(v_run, v_id, p_action, '{}'::jsonb, COALESCE(v_clock, now()), 'orchestra_manager',
           COALESCE(p_reason, p_action||' — requested by fleet manager')) || jsonb_build_object('ok',true,'vehicle_id',v_id);
END $function$

-- ===== ottoq_comms_pending_teleop =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_pending_teleop(p_run uuid)
 RETURNS TABLE(correlation_id uuid, vehicle_id uuid, proposed_action text, params jsonb, source text, summary text, requested_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT correlation_id, vehicle_id, payload->>'proposed_action', payload->'params', payload->>'source', payload->>'summary', sim_clock_at
  FROM ottoq_comms_messages
  WHERE sim_run_id=p_run AND msg_type='assist_request' AND status='pending_human'
  ORDER BY sim_clock_at;
$function$

-- ===== ottoq_comms_send_command =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_send_command(p_run uuid, p_vehicle uuid, p_command text, p_params jsonb, p_clock timestamp with time zone, p_edge_case boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_corr uuid := gen_random_uuid(); v_cmd_id uuid; v_status text; v_decision jsonb;
BEGIN
  INSERT INTO ottoq_comms_messages(sim_run_id,vehicle_id,correlation_id,direction,topic,msg_type,qos,header,payload,status,latency_ms,sim_clock_at)
  VALUES (p_run,p_vehicle,v_corr,'downlink','fleet/'||p_vehicle::text||'/cmd','command',2,
    ottoq_comms_envelope(p_vehicle,'command',v_corr,p_clock),
    jsonb_build_object('command',p_command,'params',p_params,'ttl_s',120,'issued_by','otto_q','edge_case',p_edge_case),
    CASE WHEN p_edge_case THEN 'pending_assist' ELSE 'sent' END, 50, p_clock)
  RETURNING msg_id INTO v_cmd_id;
  IF p_edge_case THEN
    v_decision := ottoq_comms_teleop_review(p_run,p_vehicle,v_corr,p_command,p_params,p_clock);
    IF (v_decision->>'decision')='escalated' THEN
      RETURN jsonb_build_object('command',p_command,'correlation_id',v_corr,'final_status','pending_human','teleop',v_decision);
    END IF;
    v_status := CASE WHEN (v_decision->>'decision')='approve' THEN 'completed' ELSE 'denied' END;
  ELSE
    v_status := 'completed';
  END IF;
  INSERT INTO ottoq_comms_messages(sim_run_id,vehicle_id,correlation_id,direction,topic,msg_type,qos,header,payload,status,latency_ms,sim_clock_at)
  VALUES (p_run,p_vehicle,v_corr,'uplink','fleet/'||p_vehicle::text||'/cmd/ack','ack',1,
    ottoq_comms_envelope(p_vehicle,'ack',v_corr,p_clock),
    jsonb_build_object('ack_for',v_cmd_id,'command',p_command,'status',CASE WHEN v_status='denied' THEN 'rejected' ELSE 'completed' END),
    v_status, 60, p_clock);
  UPDATE ottoq_comms_messages SET status=v_status WHERE msg_id=v_cmd_id;
  RETURN jsonb_build_object('command',p_command,'correlation_id',v_corr,'final_status',v_status,'teleop',COALESCE(v_decision,'null'::jsonb));
END $function$

-- ===== ottoq_comms_teleop_respond =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_teleop_respond(p_correlation_id uuid, p_decision text, p_operator text DEFAULT 'depot_operator'::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_req RECORD; v_cmd RECORD; v_cmd_status text;
BEGIN
  IF p_decision NOT IN ('approve','deny') THEN RAISE EXCEPTION 'decision must be approve or deny'; END IF;
  SELECT * INTO v_req FROM ottoq_comms_messages
    WHERE correlation_id=p_correlation_id AND msg_type='assist_request' AND status='pending_human' LIMIT 1;
  IF v_req.msg_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','no pending teleop request for that correlation'); END IF;
  INSERT INTO ottoq_comms_messages(sim_run_id,vehicle_id,correlation_id,direction,topic,msg_type,qos,header,payload,status,latency_ms,sim_clock_at)
  VALUES (v_req.sim_run_id,v_req.vehicle_id,p_correlation_id,'downlink','fleet/'||v_req.vehicle_id::text||'/assist/resp','assist_response',1,
    ottoq_comms_envelope(v_req.vehicle_id,'assist_response',p_correlation_id,v_req.sim_clock_at),
    jsonb_build_object('decision',p_decision,'operator',p_operator,'human',true,'escalated_to_human',true,'note',p_note,'control_mode','indirect'),
    p_decision, 0, v_req.sim_clock_at);
  UPDATE ottoq_comms_messages SET status=p_decision WHERE correlation_id=p_correlation_id AND msg_type='assist_request';
  SELECT * INTO v_cmd FROM ottoq_comms_messages WHERE correlation_id=p_correlation_id AND msg_type='command' LIMIT 1;
  v_cmd_status := CASE WHEN p_decision='approve' THEN 'completed' ELSE 'denied' END;
  IF v_cmd.msg_id IS NOT NULL THEN
    INSERT INTO ottoq_comms_messages(sim_run_id,vehicle_id,correlation_id,direction,topic,msg_type,qos,header,payload,status,latency_ms,sim_clock_at)
    VALUES (v_req.sim_run_id,v_req.vehicle_id,p_correlation_id,'uplink','fleet/'||v_req.vehicle_id::text||'/cmd/ack','ack',1,
      ottoq_comms_envelope(v_req.vehicle_id,'ack',p_correlation_id,v_req.sim_clock_at),
      jsonb_build_object('ack_for',v_cmd.msg_id,'command',v_cmd.payload->>'command','status',CASE WHEN p_decision='deny' THEN 'rejected' ELSE 'completed' END),
      v_cmd_status, 60, v_req.sim_clock_at);
    UPDATE ottoq_comms_messages SET status=v_cmd_status WHERE msg_id=v_cmd.msg_id;
  END IF;
  RETURN jsonb_build_object('ok',true,'correlation_id',p_correlation_id,'decision',p_decision,'operator',p_operator,
    'vehicle_id',v_req.vehicle_id,'command',COALESCE(v_cmd.payload->>'command', v_req.payload->>'proposed_action'));
END $function$

-- ===== ottoq_comms_teleop_review =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_teleop_review(p_run uuid, p_vehicle uuid, p_corr uuid, p_command text, p_params jsonb, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_decision text; v_rationale text; v_known boolean;
BEGIN
  INSERT INTO ottoq_comms_messages(sim_run_id,vehicle_id,correlation_id,direction,topic,msg_type,qos,header,payload,status,sim_clock_at)
  VALUES (p_run,p_vehicle,p_corr,'uplink','fleet/'||p_vehicle::text||'/assist/req','assist_request',1,
    ottoq_comms_envelope(p_vehicle,'assist_request',p_corr,p_clock),
    jsonb_build_object('situation','outside_normal_orchestration_parameters','proposed_action',p_command,'params',p_params,'control_mode','indirect'),
    'pending_assist', p_clock);
  v_known := p_command IN ('stage_hold','temporary_stage','reroute_for_delay','incident_triage_ack','recall_unsafe');
  IF NOT v_known THEN
    -- novel / non-predetermined action → escalate to human (depot/teleoperator), no auto-response
    UPDATE ottoq_comms_messages
      SET status='pending_human',
          payload = payload || jsonb_build_object('escalated_to_human',true,'source','ai_uncertain',
            'summary','novel action "'||p_command||'" outside predetermined set — confirm vehicle movement')
      WHERE correlation_id=p_corr AND msg_type='assist_request';
    RETURN jsonb_build_object('decision','escalated','operator','ai_remote_assistant','status','pending_human',
      'rationale','novel action outside predetermined set — escalated to depot/teleoperator for confirmation');
  END IF;
  v_decision := CASE WHEN p_command='recall_unsafe' THEN 'deny' ELSE 'approve' END;
  v_rationale := CASE v_decision WHEN 'approve' THEN 'within remote-assistance authority; vehicle movement confirmed'
                                 ELSE 'unsafe recall — denied by remote assistance' END;
  INSERT INTO ottoq_comms_messages(sim_run_id,vehicle_id,correlation_id,direction,topic,msg_type,qos,header,payload,status,latency_ms,sim_clock_at)
  VALUES (p_run,p_vehicle,p_corr,'downlink','fleet/'||p_vehicle::text||'/assist/resp','assist_response',1,
    ottoq_comms_envelope(p_vehicle,'assist_response',p_corr,p_clock),
    jsonb_build_object('decision',v_decision,'operator','ai_remote_assistant','escalated_to_human',false,'rationale',v_rationale,'control_mode','indirect'),
    v_decision, 200, p_clock);
  UPDATE ottoq_comms_messages SET status='resolved' WHERE correlation_id=p_corr AND msg_type='assist_request';
  RETURN jsonb_build_object('decision',v_decision,'operator','ai_remote_assistant','rationale',v_rationale);
END $function$

-- ===== ottoq_comms_vehicle_status =====
CREATE OR REPLACE FUNCTION public.ottoq_comms_vehicle_status(p_vehicle uuid, p_run uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run uuid; v_veh jsonb; v_disp jsonb; v_comms jsonb; v_pending jsonb;
BEGIN
  v_run := COALESCE(p_run, (SELECT sim_run_id FROM ottoq_comms_messages WHERE vehicle_id=p_vehicle ORDER BY sim_clock_at DESC LIMIT 1));
  SELECT jsonb_build_object('current_state',current_state,'current_soc',current_soc,'current_depot_id',current_depot_id)
    INTO v_veh FROM vehicles WHERE id=p_vehicle;
  SELECT to_jsonb(d) INTO v_disp FROM (
    SELECT status, dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, return_trigger
    FROM ottoq_vehicle_dispatches WHERE vehicle_id=p_vehicle AND (v_run IS NULL OR sim_run_id=v_run)
    ORDER BY dispatched_at DESC LIMIT 1) d;
  SELECT jsonb_agg(line ORDER BY ord DESC) INTO v_comms FROM (
    SELECT sim_clock_at AS ord, jsonb_build_object('clock',sim_clock_at,'dir',direction,'type',msg_type,
            'action',COALESCE(payload->>'command',payload->>'proposed_action',payload->>'decision'),
            'topic',topic,'qos',qos,'latency_ms',latency_ms,'status',status) AS line
    FROM ottoq_comms_messages WHERE vehicle_id=p_vehicle AND (v_run IS NULL OR sim_run_id=v_run)
    ORDER BY sim_clock_at DESC LIMIT 15) m;
  SELECT jsonb_agg(jsonb_build_object('correlation_id',correlation_id,'proposed_action',payload->>'proposed_action','summary',payload->>'summary','since',sim_clock_at))
    INTO v_pending FROM ottoq_comms_messages
    WHERE vehicle_id=p_vehicle AND msg_type='assist_request' AND status='pending_human' AND (v_run IS NULL OR sim_run_id=v_run);
  RETURN jsonb_build_object('vehicle_id',p_vehicle,'sim_run_id',v_run,'vehicle',COALESCE(v_veh,'null'::jsonb),
    'dispatch',COALESCE(v_disp,'null'::jsonb),'recent_comms',COALESCE(v_comms,'[]'::jsonb),'pending_teleop',COALESCE(v_pending,'[]'::jsonb));
END $function$

-- ===== ottoq_complete_audit_report =====
CREATE OR REPLACE FUNCTION public.ottoq_complete_audit_report(p_report_id uuid, p_payload jsonb, p_event_count bigint DEFAULT NULL::bigint, p_rule_eval_count bigint DEFAULT NULL::bigint, p_prediction_count bigint DEFAULT NULL::bigint, p_anomaly_count bigint DEFAULT NULL::bigint, p_override_count bigint DEFAULT NULL::bigint, p_emergency_count bigint DEFAULT NULL::bigint, p_visit_count bigint DEFAULT NULL::bigint, p_audit_trail_complete boolean DEFAULT true, p_data_quality_score numeric DEFAULT 1.0, p_signing_key_id text DEFAULT 'system:v1'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_report     ottoq_audit_reports%ROWTYPE;
  v_hash       TEXT;
  v_signature  TEXT;
BEGIN
  v_hash := encode(digest(jsonb_strip_nulls(p_payload)::text, 'sha256'), 'hex');

  SELECT * INTO v_report FROM ottoq_audit_reports r WHERE r.report_id = p_report_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'audit report % not found', p_report_id;
  END IF;

  v_signature := ottoq_sign_event(
    v_report.report_id, v_report.requested_at,
    'ottoq_engine', 'audit.report_completed',
    'audit_report', v_report.report_id,
    v_hash, p_signing_key_id
  );

  UPDATE ottoq_audit_reports
     SET generation_completed_at = NOW(),
         generation_duration_ms = EXTRACT(MILLISECOND FROM (NOW() - generation_started_at))::INTEGER,
         generation_status = 'completed',
         payload = p_payload,
         payload_hash = v_hash,
         signature = v_signature,
         signature_key_id = p_signing_key_id,
         event_count = p_event_count,
         rule_eval_count = p_rule_eval_count,
         prediction_count = p_prediction_count,
         anomaly_count = p_anomaly_count,
         override_count = p_override_count,
         emergency_count = p_emergency_count,
         visit_count = p_visit_count,
         audit_trail_complete = p_audit_trail_complete,
         data_quality_score = p_data_quality_score
   WHERE report_id = p_report_id;

  PERFORM ottoq_record_event(
    p_actor_type    := 'ottoq_engine',
    p_event_type    := 'audit.report_completed',
    p_entity_type   := 'audit_report',
    p_entity_id     := p_report_id,
    p_fleet_operator_id := v_report.fleet_operator_id,
    p_depot_id      := v_report.depot_id,
    p_payload       := jsonb_build_object(
      'report_type', v_report.report_type,
      'event_count', p_event_count,
      'audit_trail_complete', p_audit_trail_complete,
      'data_quality_score', p_data_quality_score,
      'signature_present', (v_signature IS NOT NULL)
    ),
    p_severity      := 'info',
    p_parent_event_id := v_report.source_event_id
  );
END;
$function$

-- ===== ottoq_complete_training_run =====
CREATE OR REPLACE FUNCTION public.ottoq_complete_training_run(p_training_run_id uuid, p_status text, p_resulting_model_version_id uuid DEFAULT NULL::uuid, p_training_metrics jsonb DEFAULT '{}'::jsonb, p_test_metrics jsonb DEFAULT '{}'::jsonb, p_artifact_storage_path text DEFAULT NULL::text, p_artifact_sha256 text DEFAULT NULL::text, p_artifact_size_bytes bigint DEFAULT NULL::bigint, p_dataset_n_samples bigint DEFAULT NULL::bigint, p_dataset_hash text DEFAULT NULL::text, p_failure_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_training_runs%ROWTYPE;
BEGIN
  UPDATE ottoq_training_runs tr
     SET completed_at = NOW(),
         duration_seconds = EXTRACT(EPOCH FROM (NOW() - started_at))::INTEGER,
         status = p_status,
         resulting_model_version_id = p_resulting_model_version_id,
         training_metrics = p_training_metrics,
         test_metrics = p_test_metrics,
         artifact_storage_path = p_artifact_storage_path,
         artifact_sha256 = p_artifact_sha256,
         artifact_size_bytes = p_artifact_size_bytes,
         dataset_n_samples = p_dataset_n_samples,
         dataset_hash = p_dataset_hash,
         failure_reason = p_failure_reason
   WHERE tr.training_run_id = p_training_run_id
   RETURNING * INTO v_run;

  PERFORM ottoq_record_event(
    p_actor_type    := 'system_scheduler',
    p_event_type    := CASE WHEN p_status='succeeded' THEN 'training.succeeded' ELSE 'training.failed' END,
    p_entity_type   := 'training_run',
    p_entity_id     := p_training_run_id,
    p_payload       := jsonb_build_object(
                        'prediction_type', v_run.prediction_type,
                        'duration_seconds', v_run.duration_seconds,
                        'metrics', p_training_metrics,
                        'resulting_model_version_id', p_resulting_model_version_id
                      ),
    p_severity      := CASE WHEN p_status='failed' THEN 'error' ELSE 'info' END
  );
END;
$function$

-- ===== ottoq_compute_accuracy_for_window =====
CREATE OR REPLACE FUNCTION public.ottoq_compute_accuracy_for_window(p_prediction_type text, p_depot_id uuid, p_fleet_operator_id uuid, p_vehicle_class text, p_horizon_minutes integer, p_report_date date, p_hour_of_day integer DEFAULT NULL::integer, p_day_of_week integer DEFAULT NULL::integer, p_model_version_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_id        UUID;
  v_window_s  TIMESTAMPTZ := p_report_date::timestamptz;
  v_window_e  TIMESTAMPTZ := (p_report_date + 1)::timestamptz;
  v_n_pred    INTEGER;
  v_n_scored  INTEGER;
  v_mae       NUMERIC;
  v_rmse      NUMERIC;
  v_mape      NUMERIC;
  v_bias      NUMERIC;
  v_dir_acc   NUMERIC;
  v_cov_80    NUMERIC;
  v_cov_50    NUMERIC;
  v_avg_width NUMERIC;
BEGIN
  WITH paired AS (
    SELECT
      p.id AS prediction_id,
      p.p10, p.p50, p.p90, p.predicted_value,
      po.actual_value, po.accuracy_score,
      CASE
        WHEN p.predicted_value ? 'value' THEN (p.predicted_value->>'value')::NUMERIC
        WHEN p.p50 IS NOT NULL THEN p.p50
        ELSE NULL
      END AS pred_num,
      CASE
        WHEN po.actual_value ? 'value' THEN (po.actual_value->>'value')::NUMERIC
        ELSE NULL
      END AS act_num
    FROM ottoq_predictions p
    JOIN prediction_outcomes po ON po.prediction_id = p.id
    WHERE p.prediction_type = p_prediction_type
      AND p.created_at >= v_window_s
      AND p.created_at <  v_window_e
      AND (p_depot_id          IS NULL OR p.depot_id = p_depot_id)
      AND (p_fleet_operator_id IS NULL OR p.fleet_operator_id = p_fleet_operator_id)
      AND (p_horizon_minutes   IS NULL OR p.horizon_minutes = p_horizon_minutes)
      AND (p_model_version_id  IS NULL OR p.model_version_id = p_model_version_id)
      AND (p_hour_of_day       IS NULL OR EXTRACT(HOUR FROM p.created_at) = p_hour_of_day)
      AND (p_day_of_week       IS NULL OR EXTRACT(ISODOW FROM p.created_at) = p_day_of_week)
  )
  SELECT
    count(*),
    count(*) FILTER (WHERE pred_num IS NOT NULL AND act_num IS NOT NULL),
    avg(abs(pred_num - act_num)),
    sqrt(avg(power(pred_num - act_num, 2))),
    100.0 * avg(abs(pred_num - act_num) / NULLIF(abs(act_num), 0)),
    avg(pred_num - act_num),
    avg(CASE WHEN sign(pred_num) = sign(act_num) THEN 1 ELSE 0 END)::NUMERIC,
    count(*) FILTER (WHERE p10 IS NOT NULL AND p90 IS NOT NULL AND act_num BETWEEN p10 AND p90)::NUMERIC
      / NULLIF(count(*) FILTER (WHERE p10 IS NOT NULL AND p90 IS NOT NULL), 0),
    NULL::NUMERIC,
    avg(p90 - p10)
  INTO v_n_pred, v_n_scored, v_mae, v_rmse, v_mape, v_bias, v_dir_acc,
       v_cov_80, v_cov_50, v_avg_width
  FROM paired;

  INSERT INTO ottoq_prediction_accuracy_heatmap (
    prediction_type, depot_id, fleet_operator_id, vehicle_class,
    horizon_minutes, hour_of_day, day_of_week, report_date,
    n_predictions, n_scored,
    mae, rmse, mape, bias, directional_accuracy,
    coverage_80, coverage_50, avg_interval_width,
    model_version_id, computed_at
  ) VALUES (
    p_prediction_type, p_depot_id, p_fleet_operator_id, p_vehicle_class,
    p_horizon_minutes, p_hour_of_day, p_day_of_week, p_report_date,
    COALESCE(v_n_pred, 0), COALESCE(v_n_scored, 0),
    v_mae, v_rmse, v_mape, v_bias, v_dir_acc,
    v_cov_80, v_cov_50, v_avg_width,
    p_model_version_id, NOW()
  )
  ON CONFLICT (prediction_type, depot_id, fleet_operator_id, vehicle_class,
               horizon_minutes, hour_of_day, day_of_week, report_date, model_version_id)
  DO UPDATE SET
    n_predictions = EXCLUDED.n_predictions,
    n_scored      = EXCLUDED.n_scored,
    mae           = EXCLUDED.mae,
    rmse          = EXCLUDED.rmse,
    mape          = EXCLUDED.mape,
    bias          = EXCLUDED.bias,
    directional_accuracy = EXCLUDED.directional_accuracy,
    coverage_80   = EXCLUDED.coverage_80,
    avg_interval_width = EXCLUDED.avg_interval_width,
    computed_at   = NOW()
  RETURNING heatmap_id INTO v_id;

  RETURN v_id;
END;
$function$

-- ===== ottoq_compute_audit_trail_completeness =====
CREATE OR REPLACE FUNCTION public.ottoq_compute_audit_trail_completeness(p_report_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_report          ottoq_audit_reports%ROWTYPE;
  v_signed_count    BIGINT;
  v_total_count     BIGINT;
  v_invalid_count   BIGINT;
  v_complete        BOOLEAN;
  v_event_id        UUID;
  v_verification    RECORD;
  v_retention_floor TIMESTAMPTZ;
  v_status          TEXT;
  c_sample_size     CONSTANT INT := 50;
BEGIN
  SELECT * INTO v_report FROM ottoq_audit_reports r WHERE r.report_id = p_report_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'audit report % not found', p_report_id;
  END IF;

  -- Retention floor = oldest event still held. Leftmost leaf of the event_seq
  -- UNIQUE btree (~4 page reads). NEVER min(occurred_at): occurred_at has only a
  -- BRIN, so that degrades to a full 8.3 GB heap scan (measured timing out 25 s).
  SELECT e.occurred_at INTO v_retention_floor
    FROM ottoq_events e ORDER BY e.event_seq ASC LIMIT 1;

  SELECT count(*),
         count(*) FILTER (WHERE signature IS NOT NULL)
    INTO v_total_count, v_signed_count
    FROM ottoq_events e
   WHERE e.occurred_at >= v_report.window_start
     AND e.occurred_at <= v_report.window_end
     AND (v_report.fleet_operator_id IS NULL OR e.fleet_operator_id = v_report.fleet_operator_id)
     AND (v_report.depot_id          IS NULL OR e.depot_id = v_report.depot_id);

  v_invalid_count := 0;
  FOR v_event_id IN
    SELECT e.event_id FROM ottoq_events e
     WHERE e.occurred_at >= v_report.window_start
       AND e.occurred_at <= v_report.window_end
       AND e.signature IS NOT NULL
       AND (v_report.fleet_operator_id IS NULL OR e.fleet_operator_id = v_report.fleet_operator_id)
       AND (v_report.depot_id          IS NULL OR e.depot_id = v_report.depot_id)
     ORDER BY e.event_seq
     LIMIT c_sample_size
  LOOP
    SELECT * INTO v_verification FROM ottoq_verify_event_signature(v_event_id);
    -- correct column names: has_signature / valid
    IF v_verification.has_signature AND NOT v_verification.valid THEN
      v_invalid_count := v_invalid_count + 1;
    END IF;
  END LOOP;

  IF v_retention_floor IS NULL THEN
    v_status := 'no_events_at_all';             v_complete := FALSE;
  ELSIF v_total_count = 0 THEN
    v_status := CASE WHEN v_report.window_start < v_retention_floor
                       THEN 'window_predates_retention'
                     ELSE 'no_events_in_window' END;
    v_complete := FALSE;
  ELSIF v_report.window_start < v_retention_floor THEN
    v_status := 'window_partially_purged';      v_complete := FALSE;
  ELSIF v_total_count <> v_signed_count THEN
    v_status := 'unsigned_events_present';      v_complete := FALSE;
  ELSIF v_invalid_count > 0 THEN
    v_status := 'invalid_signatures_in_sample'; v_complete := FALSE;
  ELSE
    v_status := 'complete';                     v_complete := TRUE;
  END IF;

  UPDATE ottoq_audit_reports
     SET audit_trail_complete = v_complete,
         exclusions =
           COALESCE(
             (SELECT jsonb_agg(elem)
                FROM jsonb_array_elements(COALESCE(exclusions, '[]'::jsonb)) AS elem
               WHERE NOT (elem ? 'audit_trail_check')),
             '[]'::jsonb)
           || jsonb_build_object(
                'audit_trail_check', jsonb_build_object(
                  'checked_at', NOW(),
                  'status', v_status,
                  'total_events', v_total_count,
                  'signed_events', v_signed_count,
                  'invalid_signatures_sampled', v_invalid_count,
                  'signature_sample_size', c_sample_size,
                  'retention_floor', v_retention_floor,
                  'window_start', v_report.window_start,
                  'window_end', v_report.window_end
                )
              )
   WHERE report_id = p_report_id;

  RETURN v_complete;
END;
$function$

-- ===== ottoq_compute_depot_benchmark =====
CREATE OR REPLACE FUNCTION public.ottoq_compute_depot_benchmark(p_depot_id uuid, p_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_id             UUID;
  v_window_s       TIMESTAMPTZ := p_date::timestamptz;
  v_window_e       TIMESTAMPTZ := (p_date + 1)::timestamptz;

  v_visits         INTEGER;
  v_vehicles       INTEGER;
  v_oems           INTEGER;
  v_service_hours  NUMERIC;

  v_kwh            NUMERIC;
  v_revenue        NUMERIC;
  v_cost           NUMERIC;

  v_rule_failures  INTEGER;
  v_anomalies      INTEGER;
  v_emergencies    INTEGER;
  v_overrides      INTEGER;

  v_carbon_offset  NUMERIC;
  v_avg_sla        NUMERIC;
  v_worst_sla      NUMERIC;
  v_sla_violations INTEGER;
BEGIN
  -- Throughput from visit_cost_attribution (will be zero until pipeline produces visits)
  SELECT count(*), count(DISTINCT vehicle_id), count(DISTINCT fleet_operator_id),
         COALESCE(SUM(visit_duration_min) / 60.0, 0),
         COALESCE(SUM(kwh_delivered), 0),
         COALESCE(SUM(billable_amount_usd), 0),
         COALESCE(SUM(total_cost_usd), 0),
         COALESCE(SUM(carbon_offset_kg_co2), 0)
    INTO v_visits, v_vehicles, v_oems, v_service_hours,
         v_kwh, v_revenue, v_cost, v_carbon_offset
    FROM ottoq_visit_cost_attribution
   WHERE depot_id = p_depot_id
     AND visit_completed_at >= v_window_s
     AND visit_completed_at <  v_window_e;

  -- Quality counters from Layer 1
  SELECT count(*) INTO v_rule_failures
    FROM ottoq_rule_evaluations
   WHERE depot_id = p_depot_id AND evaluated_at >= v_window_s AND evaluated_at < v_window_e AND passed = FALSE;

  SELECT count(*) INTO v_anomalies
    FROM ottoq_anomaly_observations
   WHERE depot_id = p_depot_id AND observed_at >= v_window_s AND observed_at < v_window_e AND is_anomaly = TRUE;

  SELECT count(*) INTO v_emergencies
    FROM ottoq_emergency_invocations
   WHERE depot_id = p_depot_id AND triggered_at >= v_window_s AND triggered_at < v_window_e;

  SELECT count(*) INTO v_overrides
    FROM ottoq_rule_evaluations
   WHERE depot_id = p_depot_id AND evaluated_at >= v_window_s AND evaluated_at < v_window_e AND enforcement_taken = 'overridden';

  -- SLA composite (across all OEMs at this depot)
  SELECT AVG(overall_compliance_pct), MIN(overall_compliance_pct), SUM(non_compliant_visits)
    INTO v_avg_sla, v_worst_sla, v_sla_violations
    FROM ottoq_sla_conformance_daily
   WHERE depot_id = p_depot_id AND report_date = p_date;

  INSERT INTO ottoq_depot_benchmarks_daily (
    depot_id, report_date,
    visits_completed, vehicles_served, oems_served, total_service_hours,
    avg_sla_compliance_pct, worst_sla_compliance_pct, sla_violations_count,
    total_kwh_delivered, total_revenue_usd, total_cost_usd,
    margin_pct, cost_per_visit_usd,
    rule_failures_count, anomalies_count, emergencies_count, overrides_count,
    total_carbon_offset_kg, computed_at
  ) VALUES (
    p_depot_id, p_date,
    v_visits, v_vehicles, v_oems, v_service_hours,
    v_avg_sla, v_worst_sla, COALESCE(v_sla_violations, 0),
    v_kwh, v_revenue, v_cost,
    CASE WHEN v_revenue > 0 THEN (v_revenue - v_cost) / v_revenue * 100 ELSE NULL END,
    CASE WHEN v_visits > 0 THEN v_cost / v_visits ELSE NULL END,
    v_rule_failures, v_anomalies, v_emergencies, v_overrides,
    v_carbon_offset, NOW()
  )
  ON CONFLICT (depot_id, report_date) DO UPDATE SET
    visits_completed = EXCLUDED.visits_completed,
    vehicles_served  = EXCLUDED.vehicles_served,
    oems_served      = EXCLUDED.oems_served,
    total_service_hours = EXCLUDED.total_service_hours,
    avg_sla_compliance_pct = EXCLUDED.avg_sla_compliance_pct,
    worst_sla_compliance_pct = EXCLUDED.worst_sla_compliance_pct,
    sla_violations_count = EXCLUDED.sla_violations_count,
    total_kwh_delivered = EXCLUDED.total_kwh_delivered,
    total_revenue_usd = EXCLUDED.total_revenue_usd,
    total_cost_usd = EXCLUDED.total_cost_usd,
    margin_pct = EXCLUDED.margin_pct,
    cost_per_visit_usd = EXCLUDED.cost_per_visit_usd,
    rule_failures_count = EXCLUDED.rule_failures_count,
    anomalies_count = EXCLUDED.anomalies_count,
    emergencies_count = EXCLUDED.emergencies_count,
    overrides_count = EXCLUDED.overrides_count,
    total_carbon_offset_kg = EXCLUDED.total_carbon_offset_kg,
    computed_at = NOW()
  RETURNING benchmark_id INTO v_id;
  RETURN v_id;
END;
$function$

-- ===== ottoq_compute_event_hash =====
CREATE OR REPLACE FUNCTION public.ottoq_compute_event_hash(p jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  RETURN encode(digest(ottoq_canonicalize_payload(p), 'sha256'), 'hex');
END;
$function$

-- ===== ottoq_compute_sla_conformance_for_day =====
CREATE OR REPLACE FUNCTION public.ottoq_compute_sla_conformance_for_day(p_fleet_operator_id uuid, p_depot_id uuid, p_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_window_start    TIMESTAMPTZ := p_date::timestamptz;
  v_window_end      TIMESTAMPTZ := (p_date + 1)::timestamptz;
  v_conformance_id  UUID;

  v_total           INTEGER := 0;
  v_compliant       INTEGER := 0;
  v_partial         INTEGER := 0;
  v_noncompliant    INTEGER := 0;

  v_pct_soc         NUMERIC;
  v_pct_visit_time  NUMERIC;
  v_pct_services    NUMERIC;
  v_pct_oem_gate    NUMERIC;
  v_pct_queue       NUMERIC;
  v_pct_maint       NUMERIC;
  v_pct_no_excep    NUMERIC;

  v_overall         NUMERIC;
  v_grade           TEXT;

  v_contract_ref    TEXT;
  v_sample_evals    UUID[];
BEGIN
  -- Active SLA contract reference
  SELECT contract_reference INTO v_contract_ref
    FROM ottoq_get_active_sla(p_fleet_operator_id);

  -- Per-clause conformance using rule_evaluations as the substrate
  WITH evals AS (
    SELECT rule_code, passed, evaluation_id
      FROM ottoq_rule_evaluations
     WHERE fleet_operator_id = p_fleet_operator_id
       AND (p_depot_id IS NULL OR depot_id = p_depot_id)
       AND evaluated_at >= v_window_start
       AND evaluated_at < v_window_end
       AND rule_code LIKE 'SLA.%'
  ),
  per_rule AS (
    SELECT rule_code,
           count(*) AS total,
           count(*) FILTER (WHERE passed) AS passed_count
      FROM evals GROUP BY rule_code
  )
  SELECT
    MAX(CASE WHEN rule_code = 'SLA.001.min_soc_at_deployment'  THEN (passed_count::NUMERIC / NULLIF(total,0)) END) * 100,
    MAX(CASE WHEN rule_code = 'SLA.003.max_visit_duration'      THEN (passed_count::NUMERIC / NULLIF(total,0)) END) * 100,
    MAX(CASE WHEN rule_code = 'SLA.004.required_services_complete' THEN (passed_count::NUMERIC / NULLIF(total,0)) END) * 100,
    MAX(CASE WHEN rule_code = 'SLA.005.oem_acceptance_timing'  THEN (passed_count::NUMERIC / NULLIF(total,0)) END) * 100,
    MAX(CASE WHEN rule_code = 'SLA.002.max_queue_depth'        THEN (passed_count::NUMERIC / NULLIF(total,0)) END) * 100,
    MAX(CASE WHEN rule_code = 'SLA.006.maintenance_window'     THEN (passed_count::NUMERIC / NULLIF(total,0)) END) * 100,
    MAX(CASE WHEN rule_code = 'SLA.007.redeployment_readiness' THEN (passed_count::NUMERIC / NULLIF(total,0)) END) * 100
  INTO v_pct_soc, v_pct_visit_time, v_pct_services,
       v_pct_oem_gate, v_pct_queue, v_pct_maint, v_pct_no_excep
  FROM per_rule;

  -- Visit-level totals from depot_visit_reports (if table exists)
  BEGIN
    EXECUTE format('
      SELECT
        count(*),
        count(*) FILTER (WHERE deviation_count = 0 AND audit_trail_complete),
        count(*) FILTER (WHERE deviation_count > 0 AND audit_trail_complete),
        count(*) FILTER (WHERE NOT audit_trail_complete OR deviation_count > 5)
      FROM depot_visit_reports
      WHERE fleet_operator_id = $1
        AND ($2 IS NULL OR depot_id = $2)
        AND visit_completed_at >= $3
        AND visit_completed_at < $4
    ') INTO v_total, v_compliant, v_partial, v_noncompliant
      USING p_fleet_operator_id, p_depot_id, v_window_start, v_window_end;
  EXCEPTION WHEN OTHERS THEN
    -- visit_reports not yet populated; fall back to rule-eval counts
    v_total := COALESCE((SELECT count(DISTINCT entity_id) FROM ottoq_rule_evaluations
                          WHERE fleet_operator_id = p_fleet_operator_id
                            AND evaluated_at >= v_window_start AND evaluated_at < v_window_end), 0);
    v_compliant := 0;
    v_partial := 0;
    v_noncompliant := 0;
  END;

  -- Composite weighted score
  v_overall := COALESCE(
    (COALESCE(v_pct_soc, 100) * 0.25)        -- 25% weight: SOC floor (highest value)
    + (COALESCE(v_pct_visit_time, 100) * 0.15) -- 15%: visit duration
    + (COALESCE(v_pct_services, 100) * 0.20) -- 20%: required services
    + (COALESCE(v_pct_oem_gate, 100) * 0.10) -- 10%: OEM gate
    + (COALESCE(v_pct_queue, 100) * 0.10)    -- 10%: queue depth
    + (COALESCE(v_pct_maint, 100) * 0.05)    -- 5%: maintenance window
    + (COALESCE(v_pct_no_excep, 100) * 0.15) -- 15%: redeployment readiness
  , 100);

  v_grade := CASE
    WHEN v_overall >= 95 THEN 'A'
    WHEN v_overall >= 90 THEN 'B'
    WHEN v_overall >= 80 THEN 'C'
    WHEN v_overall >= 70 THEN 'D'
    ELSE 'F'
  END;

  -- Sample evaluation IDs for forensic drill-down
  SELECT array_agg(evaluation_id ORDER BY evaluated_at DESC) FILTER (WHERE NOT passed)
    INTO v_sample_evals
    FROM (
      SELECT evaluation_id, evaluated_at, passed FROM ottoq_rule_evaluations
       WHERE fleet_operator_id = p_fleet_operator_id
         AND (p_depot_id IS NULL OR depot_id = p_depot_id)
         AND evaluated_at >= v_window_start
         AND evaluated_at < v_window_end
         AND rule_code LIKE 'SLA.%'
         AND NOT passed
       LIMIT 25
    ) failed_evals;

  -- Upsert
  INSERT INTO ottoq_sla_conformance_daily (
    fleet_operator_id, depot_id, report_date, sla_contract_reference,
    total_visits, compliant_visits, partial_visits, non_compliant_visits,
    pct_meeting_min_soc, pct_meeting_max_visit_time, pct_meeting_required_services,
    pct_meeting_oem_gate, pct_within_queue_depth, pct_in_maintenance_window,
    pct_no_blocking_exceptions, overall_compliance_pct, composite_grade,
    rule_eval_sample_ids
  ) VALUES (
    p_fleet_operator_id, p_depot_id, p_date, v_contract_ref,
    v_total, v_compliant, v_partial, v_noncompliant,
    v_pct_soc, v_pct_visit_time, v_pct_services,
    v_pct_oem_gate, v_pct_queue, v_pct_maint,
    v_pct_no_excep, v_overall, v_grade,
    COALESCE(v_sample_evals, '{}'::uuid[])
  )
  ON CONFLICT (fleet_operator_id, depot_id, report_date) DO UPDATE
    SET total_visits             = EXCLUDED.total_visits,
        compliant_visits         = EXCLUDED.compliant_visits,
        partial_visits           = EXCLUDED.partial_visits,
        non_compliant_visits     = EXCLUDED.non_compliant_visits,
        pct_meeting_min_soc      = EXCLUDED.pct_meeting_min_soc,
        pct_meeting_max_visit_time = EXCLUDED.pct_meeting_max_visit_time,
        pct_meeting_required_services = EXCLUDED.pct_meeting_required_services,
        pct_meeting_oem_gate     = EXCLUDED.pct_meeting_oem_gate,
        pct_within_queue_depth   = EXCLUDED.pct_within_queue_depth,
        pct_in_maintenance_window = EXCLUDED.pct_in_maintenance_window,
        pct_no_blocking_exceptions = EXCLUDED.pct_no_blocking_exceptions,
        overall_compliance_pct   = EXCLUDED.overall_compliance_pct,
        composite_grade          = EXCLUDED.composite_grade,
        rule_eval_sample_ids     = EXCLUDED.rule_eval_sample_ids,
        computed_at              = NOW()
  RETURNING conformance_id INTO v_conformance_id;

  RETURN v_conformance_id;
END;
$function$

-- ===== ottoq_compute_visit_cost =====
CREATE OR REPLACE FUNCTION public.ottoq_compute_visit_cost(p_schedule_id uuid, p_visit_report_id uuid DEFAULT NULL::uuid, p_kwh_delivered numeric DEFAULT NULL::numeric, p_kwh_from_grid numeric DEFAULT NULL::numeric, p_kwh_from_solar numeric DEFAULT NULL::numeric, p_kwh_from_bess numeric DEFAULT NULL::numeric, p_avg_rate_per_kwh numeric DEFAULT NULL::numeric, p_demand_charge_usd numeric DEFAULT 0, p_labor_cost_usd numeric DEFAULT 0, p_opportunity_cost_usd numeric DEFAULT 0, p_consumables_cost_usd numeric DEFAULT 0, p_billable_amount_usd numeric DEFAULT NULL::numeric, p_carbon_intensity_kg_per_kwh numeric DEFAULT 0.4, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_vehicle_id uuid DEFAULT NULL::uuid, p_visit_started_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_visit_completed_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_id              UUID;
  v_energy_cost     NUMERIC := COALESCE(p_kwh_delivered, 0) * COALESCE(p_avg_rate_per_kwh, 0);
  v_total_cost      NUMERIC;
  v_margin          NUMERIC;
  v_margin_pct      NUMERIC;
  v_carbon_offset   NUMERIC;
  v_duration_min    NUMERIC;
BEGIN
  v_total_cost := v_energy_cost
                + COALESCE(p_demand_charge_usd, 0)
                + COALESCE(p_labor_cost_usd, 0)
                + COALESCE(p_opportunity_cost_usd, 0)
                + COALESCE(p_consumables_cost_usd, 0);

  IF p_billable_amount_usd IS NOT NULL THEN
    v_margin := p_billable_amount_usd - v_total_cost;
    v_margin_pct := CASE WHEN p_billable_amount_usd > 0 THEN v_margin / p_billable_amount_usd * 100 ELSE NULL END;
  END IF;

  -- Avoided carbon: kWh × (ICE equivalent factor - grid factor)
  -- ICE car emits ~ 0.35 kg CO2/mile, 4 mi/kWh → 0.087 kg CO2/kWh for similar travel
  -- This is highly simplified; calibrate per pilot.
  v_carbon_offset := COALESCE(p_kwh_delivered, 0) * GREATEST(0.45 - COALESCE(p_carbon_intensity_kg_per_kwh, 0.4), 0);

  IF p_visit_started_at IS NOT NULL AND p_visit_completed_at IS NOT NULL THEN
    v_duration_min := EXTRACT(EPOCH FROM (p_visit_completed_at - p_visit_started_at)) / 60.0;
  END IF;

  INSERT INTO ottoq_visit_cost_attribution (
    attribution_id, schedule_id, visit_report_id,
    vehicle_id, fleet_operator_id, depot_id,
    visit_started_at, visit_completed_at, visit_duration_min,
    kwh_delivered, kwh_from_grid, kwh_from_solar, kwh_from_bess,
    energy_cost_usd, demand_charge_usd, labor_cost_usd,
    opportunity_cost_usd, consumables_cost_usd, total_cost_usd,
    billable_amount_usd, margin_usd, margin_pct,
    carbon_offset_kg_co2, grid_carbon_intensity_kg_per_kwh,
    compute_method
  ) VALUES (
    gen_random_uuid(), p_schedule_id, p_visit_report_id,
    p_vehicle_id, p_fleet_operator_id, p_depot_id,
    p_visit_started_at, p_visit_completed_at, v_duration_min,
    p_kwh_delivered, p_kwh_from_grid, p_kwh_from_solar, p_kwh_from_bess,
    v_energy_cost, p_demand_charge_usd, p_labor_cost_usd,
    p_opportunity_cost_usd, p_consumables_cost_usd, v_total_cost,
    p_billable_amount_usd, v_margin, v_margin_pct,
    v_carbon_offset, p_carbon_intensity_kg_per_kwh,
    'rule_based'
  )
  ON CONFLICT (schedule_id) DO UPDATE SET
    kwh_delivered    = EXCLUDED.kwh_delivered,
    kwh_from_grid    = EXCLUDED.kwh_from_grid,
    kwh_from_solar   = EXCLUDED.kwh_from_solar,
    kwh_from_bess    = EXCLUDED.kwh_from_bess,
    energy_cost_usd  = EXCLUDED.energy_cost_usd,
    demand_charge_usd = EXCLUDED.demand_charge_usd,
    labor_cost_usd   = EXCLUDED.labor_cost_usd,
    total_cost_usd   = EXCLUDED.total_cost_usd,
    billable_amount_usd = EXCLUDED.billable_amount_usd,
    margin_usd       = EXCLUDED.margin_usd,
    margin_pct       = EXCLUDED.margin_pct,
    carbon_offset_kg_co2 = EXCLUDED.carbon_offset_kg_co2,
    computed_at      = NOW()
  RETURNING attribution_id INTO v_id;
  RETURN v_id;
END;
$function$

-- ===== ottoq_count_breaches_in_frame =====
CREATE OR REPLACE FUNCTION public.ottoq_count_breaches_in_frame(p_frame jsonb, p_depot_id uuid)
 RETURNS TABLE(total integer, b_over_stall integer, b_deploy_low_soc integer, b_charge_offline integer)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_veh jsonb := COALESCE(p_frame->'vehicles','[]'::jsonb);
BEGIN
  -- B1: a stall id held by >1 vehicle in the frame
  b_over_stall := COALESCE((
    SELECT count(*) FROM (
      SELECT e->>'stall_id' sid FROM jsonb_array_elements(v_veh) e
       WHERE e->>'stall_id' IS NOT NULL
       GROUP BY e->>'stall_id' HAVING count(*) > 1
    ) x), 0);
  -- B2: a deployed/en-route vehicle below its min SoC floor (default 15)
  b_deploy_low_soc := COALESCE((
    SELECT count(*) FROM jsonb_array_elements(v_veh) e
     WHERE e->>'state' IN ('deployed','en_route_to_deployment')
       AND COALESCE((e->>'soc')::numeric, 100) < COALESCE((e->>'min_soc_threshold')::numeric, 15)), 0);
  -- B3: a charging vehicle whose stall connector is null/unknown in the frame (proxy: charging w/o a stall)
  b_charge_offline := COALESCE((
    SELECT count(*) FROM jsonb_array_elements(v_veh) e
     WHERE e->>'state' IN ('charging_dcfc','charging_l2') AND (e->>'stall_id') IS NULL), 0);
  total := b_over_stall + b_deploy_low_soc + b_charge_offline;
  RETURN NEXT;
END;
$function$

-- ===== ottoq_count_enacted_breaches =====
CREATE OR REPLACE FUNCTION public.ottoq_count_enacted_breaches(p_sim_run_id uuid)
 RETURNS TABLE(total integer, b_over_stall integer, b_deploy_low_soc integer, b_charge_offline integer, b_over_power integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_cap numeric; v_dcfc_draw numeric; v_clock timestamptz;
BEGIN
  SELECT depot_id, sim_clock_current INTO v_depot, v_clock
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;

  -- B1: a stall holding more than one vehicle (two vehicles claim the same stall)
  b_over_stall := COALESCE((
    SELECT count(*) FROM (
      SELECT current_stall_id FROM vehicles
       WHERE home_depot_id=v_depot AND category='autonomous' AND current_stall_id IS NOT NULL
       GROUP BY current_stall_id HAVING count(*) > 1
    ) x), 0);

  -- B2: a vehicle in a deployment state below its min SoC floor (unsafe dispatch)
  b_deploy_low_soc := COALESCE((
    SELECT count(*) FROM vehicles
     WHERE home_depot_id=v_depot AND category='autonomous'
       AND current_state IN ('deployed','en_route_to_deployment')
       AND current_soc < COALESCE(min_soc_threshold, 15)), 0);

  -- B3: a vehicle charging at a Faulted/offline charger
  b_charge_offline := COALESCE((
    SELECT count(*) FROM vehicles v
     JOIN stalls s ON s.id = v.current_stall_id
     LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state IN ('charging_dcfc','charging_l2')
       AND (c.station_state = 'Faulted' OR c.station_state = 'Unavailable' OR c.charger_id IS NULL)), 0);

  -- B4: REAL metered DCFC draw beyond the depot engineering cap.
  -- WAS: SUM(connector_max_kw) over occupied DCFC stalls — nameplate, not draw.
  SELECT dcfc_max_concurrent_kw INTO v_cap FROM depots WHERE id=v_depot;
  SELECT COALESCE(SUM(((cs.last_meter_value->>'power_kw'))::numeric), 0)
    INTO v_dcfc_draw
    FROM ocpp_sessions cs
    JOIN stalls s ON s.id = cs.stall_id
   WHERE cs.depot_id = v_depot
     AND s.stall_type::text = 'dcfc'
     AND cs.status = 'active'::ocpp_session_status
     AND cs.sim_run_id = p_sim_run_id
     AND (v_clock IS NULL OR (cs.started_at <= v_clock AND (cs.ended_at IS NULL OR cs.ended_at >= v_clock)));
  b_over_power := CASE WHEN v_cap IS NOT NULL AND v_dcfc_draw > v_cap THEN 1 ELSE 0 END;

  total := COALESCE(b_over_stall,0)+COALESCE(b_deploy_low_soc,0)+COALESCE(b_charge_offline,0)+COALESCE(b_over_power,0);
  RETURN NEXT;
END;
$function$

-- ===== ottoq_crn_draw =====
CREATE OR REPLACE FUNCTION public.ottoq_crn_draw(p_run_seed bigint, p_stream text, p_slot_key text, p_sim_day integer DEFAULT 0, p_tick bigint DEFAULT 0)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- hashtextextended gives a stable 64-bit hash; map to [0,1). The seed is the salt
  -- so different A/B seeds → different worlds, same seed → identical exogenous draws.
  SELECT (abs(hashtextextended(
            p_stream || '|' || p_slot_key || '|' || p_sim_day::text || '|' || p_tick::text,
            p_run_seed)) % 1000000000)::double precision / 1000000000.0;
$function$

-- ===== ottoq_crn_init_run =====
CREATE OR REPLACE FUNCTION public.ottoq_crn_init_run(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_seed bigint; v_manifest jsonb;
BEGIN
  SELECT random_seed INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  v_manifest := jsonb_build_object(
    'run_seed', v_seed,
    'streams', jsonb_build_array('weather','grid','arrival','charger_fault','soc_noise','incident'),
    'keying', 'environment_slot',  -- exogenous shocks keyed to slot, not vehicle (causal correctness)
    'rng', 'counter_based_hashtextextended_v1');
  UPDATE ottoq_sim_runs SET crn_streams = v_manifest WHERE sim_run_id = p_sim_run_id;
  RETURN v_manifest;
END;
$function$

-- ===== ottoq_crn_normal =====
CREATE OR REPLACE FUNCTION public.ottoq_crn_normal(p_run_seed bigint, p_stream text, p_slot_key text, p_sim_day integer DEFAULT 0, p_tick bigint DEFAULT 0)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- two independent CRN draws (salted differently) → one N(0,1) via Box-Muller
  SELECT sqrt(-2.0 * ln(GREATEST(1e-12, ottoq_crn_draw(p_run_seed, p_stream||':u1', p_slot_key, p_sim_day, p_tick))))
       * cos(2.0 * pi() * ottoq_crn_draw(p_run_seed, p_stream||':u2', p_slot_key, p_sim_day, p_tick));
$function$

-- ===== ottoq_cron_tick =====
CREATE OR REPLACE FUNCTION public.ottoq_cron_tick()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE k text; base text := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1';
BEGIN
  -- GATE: no started run, no work. Nothing below costs a cent while idle.
  IF NOT EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = 'running') THEN
    RETURN;
  END IF;

  -- (0) advance the WORLD (twin physics) FIRST so the brain reads FRESH state.
  BEGIN PERFORM ottoq_world_advance(); EXCEPTION WHEN OTHERS THEN RAISE WARNING 'cron world_advance: %', SQLERRM; END;

  -- (0b) hygiene: pending external proposals whose run is no longer running
  BEGIN
    UPDATE ottoq_external_proposals p SET status='expired'
     WHERE p.status='pending'
       AND NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id=p.sim_run_id AND r.status='running');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'cron proposal sweep: %', SQLERRM; END;

  SELECT decrypted_secret INTO k FROM vault.decrypted_secrets WHERE name = 'ottoq_anon_key' LIMIT 1;
  IF k IS NULL THEN RAISE WARNING 'ottoq_cron_tick: anon key missing from vault'; RETURN; END IF;

  -- (1) depot-wide re-optimize (~7s w/ cuOpt -> needs >5s pg_net default timeout)
  PERFORM net.http_post(
    url := base || '/ottoq-orchestrate-tick',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||k,'apikey',k),
    body := jsonb_build_object('depot_id','11111111-1111-1111-1111-111111111111','submit',true,'shadow',false),
    timeout_milliseconds := 25000);

  -- N4: OTTO-Q Prime (central orchestrator agent) — board review every ~10 min
  IF EXTRACT(MINUTE FROM now())::int % 10 < 2 THEN
    PERFORM net.http_post(
      url := base || '/ottoq-orchestrator-agent',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||k,'apikey',k),
      body := jsonb_build_object('depot_id','11111111-1111-1111-1111-111111111111'),
      timeout_milliseconds := 25000);
  END IF;

  -- (2) ingress / wave-admission policy (auto day/night)
  PERFORM net.http_post(
    url := base || '/ottoq-wave-admit',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||k,'apikey',k),
    body := jsonb_build_object('depot_id','11111111-1111-1111-1111-111111111111','commit',true),
    timeout_milliseconds := 12000);
END $function$

-- ===== ottoq_cuopt_defer_arm =====
CREATE OR REPLACE FUNCTION public.ottoq_cuopt_defer_arm(p_sim_run_id uuid, p_tick bigint, p_vehicle_ids uuid[], p_net_request_id bigint DEFAULT NULL::bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int := 0; v_sim timestamptz;
BEGIN
  IF p_sim_run_id IS NULL OR p_vehicle_ids IS NULL OR array_length(p_vehicle_ids,1) IS NULL THEN
    RETURN 0;
  END IF;
  SELECT COALESCE(sim_clock_current, now()) INTO v_sim
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;

  INSERT INTO public.ottoq_cuopt_deferrals AS d
    (sim_run_id, vehicle_id, state, armed_at_tick, armed_at_sim, armed_at_real,
     net_request_id, defer_count)
  SELECT p_sim_run_id, v.id, 'armed', p_tick, v_sim, now(), p_net_request_id, 1
    FROM vehicles v
   WHERE v.id = ANY (p_vehicle_ids)
     -- ZONE GUARD (A/B/C doctrine). Deferral is only ever applied to vehicles that
     -- are OUTSIDE the depot walls and hold no space: at the gate, en route, or
     -- deployed. A vehicle standing on a stall or in a bay is inside the walls and
     -- is governed by the in-depot reassignment gate, never by this ledger, so a
     -- Zone B frozen itinerary can never be touched by a cuOpt deferral.
     AND v.current_state IN ('arrived_at_gate','en_route_to_depot','deployed')
     AND v.current_stall_id IS NULL
  ON CONFLICT (sim_run_id, vehicle_id) DO UPDATE
     SET state          = 'armed',
         armed_at_tick  = EXCLUDED.armed_at_tick,
         armed_at_sim   = EXCLUDED.armed_at_sim,
         armed_at_real  = EXCLUDED.armed_at_real,
         net_request_id = EXCLUDED.net_request_id,
         defer_count    = d.defer_count + 1
   WHERE d.state = 'clear';   -- <== STARVATION BOUND. never re-arm 'armed' or 'spent'.

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_cuopt_defer_arm: % (run=%, tick=%)', SQLERRM, p_sim_run_id, p_tick;
  RETURN 0;
END;
$function$

-- ===== ottoq_cuopt_defer_hold =====
CREATE OR REPLACE FUNCTION public.ottoq_cuopt_defer_hold(p_sim_run_id uuid, p_vehicle_id uuid, p_tick bigint)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.ottoq_cuopt_deferrals d
                  WHERE d.sim_run_id = p_sim_run_id
                    AND d.vehicle_id = p_vehicle_id
                    AND d.state = 'spent'
                    AND d.spent_at_tick = p_tick)
     -- RIGHT OF FIRST REFUSAL, NOT VETO: release the moment cuOpt has ANSWERED for this
     -- vehicle. The predicate is deliberately narrowed to cuOpt-SOURCED proposals. The
     -- old test (ottoq_l2_external_proposal(...) IS NULL) accepted greedy_constrained
     -- rows too, and ottoq_l2_optimize_assignments manufactures exactly such a row for
     -- every at-gate vehicle one statement AFTER the deferral is armed — so the hold
     -- released before it could ever bind. Measured: 52 of 80 armed vehicles enacted on
     -- their own arm tick.
     --
     -- Stall LIVENESS is deliberately NOT re-checked here. If cuOpt answered but the
     -- stall it named has since been taken, we WANT the hold to release so the local
     -- greedy path can serve the vehicle this tick. Every branch fails OPEN toward
     -- assigning the vehicle.
     AND NOT EXISTS (
           SELECT 1 FROM public.ottoq_external_proposals p
            WHERE p.sim_run_id     = p_sim_run_id
              AND p.action_context = 'stall_assignment'
              AND p.entity_type    = 'vehicle'
              AND p.entity_id      = p_vehicle_id
              AND p.status         = 'pending'
              AND p.source IN ('cuopt', 'cuopt_fallback')
              -- proposal TTL stays in the REAL domain, matching ottoq_l2_external_proposal
              AND GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                           p.created_at + interval '35 minutes') >= now());
$function$

-- ===== ottoq_cuopt_defer_roll =====
CREATE OR REPLACE FUNCTION public.ottoq_cuopt_defer_roll(p_sim_run_id uuid, p_tick bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  -- STEP 1 — RELEASE. Any row spent by an EARLIER decide tick becomes 'clear'
  -- before this tick's cursor reads it, so the vehicle it names is assignable
  -- this tick with no condition attached. This is the starvation bound.
  UPDATE public.ottoq_cuopt_deferrals
     SET state = 'clear', cleared_at_tick = p_tick
   WHERE sim_run_id = p_sim_run_id
     AND state = 'spent'
     AND spent_at_tick < p_tick;

  -- STEP 2 — CONSUME. Arm -> spent. This tick, and only this tick, holds them.
  UPDATE public.ottoq_cuopt_deferrals
     SET state = 'spent', spent_at_tick = p_tick
   WHERE sim_run_id = p_sim_run_id
     AND state = 'armed'
     AND armed_at_tick <= p_tick;
EXCEPTION WHEN OTHERS THEN
  -- A ledger hiccup must NEVER abort decide_tick. Failing open = greedy behaves
  -- exactly as it did before this change.
  RAISE WARNING 'ottoq_cuopt_defer_roll: % (run=%, tick=%)', SQLERRM, p_sim_run_id, p_tick;
END;
$function$

-- ===== ottoq_cuopt_first_refusal_arm =====
CREATE OR REPLACE FUNCTION public.ottoq_cuopt_first_refusal_arm(p_sim_run_id uuid, p_tick bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_sim timestamptz; v_cap int; v_ids uuid[]; v_n int := 0;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;

  -- STARVATION BOUND + OFF SWITCH, both policy-tunable per run.
  v_cap := GREATEST(0, ottoq_policy_get(p_sim_run_id, 'cuopt_first_refusal_max_defers', 1)::int);
  IF v_cap = 0 THEN RETURN 0; END IF;

  SELECT depot_id, COALESCE(sim_clock_current, now()) INTO v_depot, v_sim
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  SELECT COALESCE(array_agg(v.id), ARRAY[]::uuid[]) INTO v_ids
    FROM vehicles v
   WHERE v.home_depot_id = v_depot
     AND v.category = 'autonomous'
     -- Zone A/outside-the-walls only. Mirrors ottoq_cuopt_defer_arm's own guard.
     AND v.current_state = 'arrived_at_gate'
     AND v.current_stall_id IS NULL
     AND v.current_soc < 85
     -- greedy has already reserved a charge stall for it => nothing left to optimise
     AND NOT EXISTS (SELECT 1 FROM stalls s
                      WHERE s.reserved_by = v.id
                        AND s.stall_type::text IN ('dcfc','l2')
                        AND COALESCE(s.reservation_expires_at, v_sim) >= v_sim)
     -- THE BOUND: never hold a vehicle that is already armed/spent, and never
     -- more than v_cap times in the whole run.
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_cuopt_deferrals d
                      WHERE d.sim_run_id = p_sim_run_id AND d.vehicle_id = v.id
                        AND (d.state <> 'clear' OR d.defer_count >= v_cap))
     -- cuOpt has already answered for this vehicle => let the cursor enact it now
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_external_proposals p
                      WHERE p.sim_run_id     = p_sim_run_id
                        AND p.action_context = 'stall_assignment'
                        AND p.entity_type    = 'vehicle'
                        AND p.entity_id      = v.id
                        AND p.status         = 'pending'
                        AND p.source IN ('cuopt','cuopt_fallback'));

  IF v_ids IS NULL OR array_length(v_ids,1) IS NULL THEN RETURN 0; END IF;

  v_n := public.ottoq_cuopt_defer_arm(p_sim_run_id, p_tick, v_ids, NULL);

  BEGIN
    PERFORM public.cuopt_log_gate(
      p_sim_run_id, 'first_refusal_arm', array_length(v_ids,1),
      jsonb_build_object('armed', v_n, 'offered', array_length(v_ids,1),
                         'tick', p_tick, 'max_defers', v_cap),
      clock_timestamp(), 'p7_first_refusal');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  -- Fail OPEN: a ledger hiccup must never change how the engine assigns.
  RAISE WARNING 'ottoq_cuopt_first_refusal_arm: % (run=%, tick=%)', SQLERRM, p_sim_run_id, p_tick;
  RETURN 0;
END;
$function$

-- ===== ottoq_cuopt_refresh =====
CREATE OR REPLACE FUNCTION public.ottoq_cuopt_refresh(p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run uuid; v_depot uuid; v_key text; v_req bigint; v_candidates int; v_last timestamptz; v_debounce int;
        v_t0 timestamptz := clock_timestamp();
        v_tick bigint; v_sim timestamptz; v_cand uuid[]; v_armed int := 0;
BEGIN
  IF current_setting('ottoq.dryrun', true) = 'on' THEN
    PERFORM public.cuopt_log_gate(p_sim_run_id, 'dryrun_mpc_fork', NULL, NULL, v_t0);
    RETURN NULL;
  END IF;
  v_run := p_sim_run_id;
  IF v_run IS NULL THEN
    SELECT sim_run_id INTO v_run FROM ottoq_sim_runs
     WHERE status='running' AND COALESCE(run_by,'') <> 'production_live'
     ORDER BY started_at DESC LIMIT 1;
  END IF;
  IF v_run IS NULL THEN
    PERFORM public.cuopt_log_gate(NULL, 'no_running_run', NULL, NULL, v_t0);
    RETURN NULL;
  END IF;

  -- DEBOUNCE (tunable). REAL domain on purpose: it throttles NVIDIA API spend,
  -- billed in real seconds, not sim seconds.
  v_debounce := GREATEST(1, ottoq_policy_get(v_run, 'cuopt_debounce_s', 2)::int);
  SELECT fired_at INTO v_last FROM ottoq_cuopt_fire_log WHERE sim_run_id = v_run;
  IF v_last IS NOT NULL AND v_last > now() - make_interval(secs => v_debounce) THEN
    PERFORM public.cuopt_log_gate(v_run, 'debounce', NULL,
      jsonb_build_object('debounce_s', v_debounce, 'last_fired_at', v_last), v_t0);
    RETURN NULL;
  END IF;

  SELECT depot_id, COALESCE(tick_count,0), COALESCE(sim_clock_current, now())
    INTO v_depot, v_tick, v_sim
    FROM ottoq_sim_runs WHERE sim_run_id = v_run;
  IF v_depot IS NULL THEN
    PERFORM public.cuopt_log_gate(v_run, 'no_depot', NULL, NULL, v_t0);
    RETURN NULL;
  END IF;

  -- ==========================================================================
  -- CANDIDATE PREDICATE. This is the AUTHORITATIVE gate.
  -- Exclusions (a) reserved-by-greedy and (b) already-enacted-this-tick apply to
  -- the AT-GATE cohort only; the en-route cohort is DEFINED by holding a live
  -- non-DCFC reservation, so applying (a) to it would delete it entirely.
  -- CLOCK DOMAIN: reservation_expires_at is SIM-domain and MUST be compared to
  -- v_sim; tick_seq carries no clock at all.
  --
  -- P7 2026-08-03 — COHORT (2) TEMP STAGING, NEW. ottoq_decide_tick's own
  -- stall-assignment cursor assigns charge stalls to 'staged_awaiting_service'
  -- vehicles, and the edge function re-validates that exact state, but the gate
  -- never offered them, so cuOpt could not compete for a single one. Temp
  -- staging is the pressure valve for a decision that lands late -- precisely
  -- the population an optimiser should be re-planning. The predicate below is
  -- decide_tick's, unchanged: a free + healthy charge stall must exist, and the
  -- SoC envelope is the vehicle's own open visit target (else 85). This is
  -- PARITY, not a widening of eligibility: a vehicle outside decide_tick's
  -- envelope could never have had a cuOpt proposal enacted anyway.
  -- ==========================================================================
  SELECT COALESCE(array_agg(v.id), ARRAY[]::uuid[]), count(*)
    INTO v_cand, v_candidates
    FROM vehicles v
   WHERE v.home_depot_id = v_depot AND v.category='autonomous'
     AND ( (    v.current_state='arrived_at_gate' AND v.current_soc < 85
            AND NOT EXISTS (SELECT 1 FROM stalls s
                             WHERE s.reserved_by = v.id
                               AND s.stall_type::text IN ('dcfc','l2')
                               AND COALESCE(s.reservation_expires_at, v_sim) >= v_sim)
            AND NOT EXISTS (SELECT 1 FROM ottoq_decisions dd
                             WHERE dd.sim_run_id      = v_run
                               AND dd.entity_type     = 'vehicle'
                               AND dd.entity_id       = v.id
                               AND dd.action_context  = 'stall_assignment'
                               AND dd.outcome_status  = 'enacted'
                               AND dd.tick_seq       >= v_tick) )
        OR (    v.current_state='staged_awaiting_service'
            AND v.current_stall_id IS NULL
            AND v.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
                                           WHERE vn.vehicle_id = v.id
                                             AND vn.status IN ('open','in_progress')
                                           ORDER BY vn.created_at DESC LIMIT 1), 85)
            AND EXISTS (SELECT 1 FROM stalls s2
                          JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
                         WHERE s2.depot_id = v_depot
                           AND s2.stall_type::text IN ('dcfc','l2')
                           AND s2.current_vehicle_id IS NULL
                           AND c2.station_state = 'Available'
                           AND (s2.reserved_by IS NULL OR s2.reserved_by = v.id
                                OR s2.reservation_expires_at <= v_sim))
            AND NOT EXISTS (SELECT 1 FROM ottoq_decisions dd
                             WHERE dd.sim_run_id      = v_run
                               AND dd.entity_type     = 'vehicle'
                               AND dd.entity_id       = v.id
                               AND dd.action_context  = 'stall_assignment'
                               AND dd.outcome_status  = 'enacted'
                               AND dd.tick_seq       >= v_tick) )
        OR ( v.current_state IN ('deployed','en_route_to_depot') AND v.current_soc < 45
             AND EXISTS (SELECT 1 FROM stalls s WHERE s.reserved_by = v.id
                           AND s.stall_type::text <> 'dcfc'
                           AND COALESCE(s.reservation_expires_at, v_sim) >= v_sim)
             AND EXISTS (SELECT 1 FROM stalls s2
                           JOIN ottoq_ocpp_chargers ch ON ch.charger_id = s2.ocpp_charger_id
                          WHERE s2.depot_id = v_depot AND s2.stall_type::text='dcfc'
                            AND s2.status='available' AND s2.reserved_by IS NULL
                            AND ch.station_state='Available') ) );

  IF v_candidates = 0 THEN
    PERFORM public.cuopt_log_gate(v_run, 'sql_gate_no_candidates', 0, NULL, v_t0);
    RETURN NULL;
  END IF;

  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='ottoq_anon_key' LIMIT 1;
  IF v_key IS NULL THEN
    PERFORM public.cuopt_log_gate(v_run, 'no_anon_key_in_vault', v_candidates, NULL, v_t0);
    RETURN NULL;
  END IF;

  INSERT INTO ottoq_cuopt_fire_log (sim_run_id, fired_at) VALUES (v_run, now())
    ON CONFLICT (sim_run_id) DO UPDATE SET fired_at = now();

  -- SHIP THE INSTANCE. v_cand is the set just gated on and just armed a deferral
  -- for. The edge fn re-validates every id against the live world before posing
  -- it, so this pins IDENTITY, never eligibility.
  SELECT net.http_post(
    url := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-cuopt-propose',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key,'apikey',v_key),
    body := jsonb_build_object('sim_run_id', v_run,
                               'vehicle_ids', to_jsonb(v_cand),
                               'gate_tick', v_tick,
                               'gate_sim_clock', v_sim),
    timeout_milliseconds := 20000) INTO v_req;

  -- RIGHT OF FIRST REFUSAL. Armed only AFTER a solve was actually posted, so the
  -- greedy path is never held back for a call that never happened.
  BEGIN
    v_armed := public.ottoq_cuopt_defer_arm(v_run, v_tick, v_cand, v_req);
  EXCEPTION WHEN OTHERS THEN
    v_armed := -1;
    RAISE WARNING 'cuopt defer arm failed (non-fatal): %', SQLERRM;
  END;

  PERFORM public.cuopt_log_gate(v_run, NULL, v_candidates,
    jsonb_build_object('posted', true, 'net_request_id', v_req,
                       'gate_tick', v_tick, 'gate_sim_clock', v_sim,
                       'pinned_vehicle_ids', v_candidates,
                       'deferred_to_cuopt', v_armed), v_t0);
  RETURN v_req;
END;
$function$

-- ===== ottoq_decide_tick =====
CREATE OR REPLACE FUNCTION public.ottoq_decide_tick(p_sim_run_id uuid)
 RETURNS ottoq_decide_tick_result
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_clock timestamptz; v_tick bigint; v_snapshot_id uuid;
  v_req RECORD; v_ctx jsonb; v_proposal jsonb; v_action jsonb;
  v_blocks int; v_block_codes text[]; v_rule_rows jsonb; v_disarm jsonb;
  v_outcome text; v_over boolean; v_safe boolean;
  v_t0 timestamptz; v_prop_ms int; v_shield_ms int; v_enact_ms int;
  v_built int := 0; v_enacted int := 0; v_overc int := 0; v_deferred int := 0; v_errored int := 0; v_disn int := 0;
  v_bess RECORD; v_energy RECORD;
  v_total_fleet int; v_curr_deployed int; v_target_pct numeric; v_demand_target int; v_deploy_budget int;
  v_charge_cap_kw numeric; v_ev_committed_kw numeric := 0; v_stage_stall uuid;
  v_charge_leg RECORD; v_bkg uuid;
  v_stage_leg_id uuid; v_stage_until timestamptz;
  v_bay_leg_id uuid; v_bay_leg_type text; v_bay_dur interval; v_bay_until timestamptz;
  v_bay_bkg uuid; v_bay_purpose text;
  -- P1 (needs-card space routing)
  v_need RECORD; v_space jsonb;
  v_wash_phys int; v_svc_phys int; v_wash_open int; v_svc_open int;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count INTO v_depot, v_clock, v_tick
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN ROW(0,NULL,0,0,0,0,0,0,0)::ottoq_decide_tick_result; END IF;
  v_snapshot_id := ottoq_capture_decision_snapshot(p_sim_run_id, v_tick, v_depot, v_clock);

  -- P1 BAY RELEASE. twin.ottoq_sim_advance_service_flow STEP 1 moves a vehicle OUT of a bay
  -- back to staged_awaiting_service and never clears stalls.current_vehicle_id or
  -- vehicles.current_stall_id; nothing else clears a bay either. Physical bay occupancy is
  -- switched ON below, so without this sweep the 3 wash / 2 service bays would fill and
  -- NEVER free - a permanent depot deadlock after five vehicles. Release-only: this call can
  -- free a space but can never claim one, and it never touches dcfc/l2 stalls.
  -- BOOKING LIFECYCLE. Promote held -> active for every booking whose vehicle is now
  -- physically standing on its stall, BEFORE the release sweep below. This is what gives
  -- 'active' a meaning, and what lets the sweep close a REAL occupancy as 'done' (with its
  -- window truncated to the true end) instead of lumping it in with forward reservations
  -- that nobody ever used. Release-only and non-fatal, like the sweep itself.
  PERFORM ottoq.ottoq_activate_present_bookings(p_sim_run_id, v_clock);

  -- HONOUR OR RE-PLAN, NEVER LET IT ROT (2026-08-02). Runs BEFORE the release sweep on
  -- purpose: a bay reservation whose vehicle is still bolted to a charger is slid forward
  -- to when the car can actually be there, so the sweep below never sees it as a no-show.
  -- Bounded defers + explicit give-up: it can free a window or move one, never claim one.
  PERFORM ottoq.ottoq_reconcile_bay_reservations(p_sim_run_id, v_depot, v_clock);

  PERFORM ottoq.ottoq_release_vacated_spaces(p_sim_run_id, v_depot, v_clock);

  -- NO BAY ENTRY WITHOUT A BOOKING. twin.ottoq_sim_advance_service_flow STEP 2 admits
  -- vehicles into wash/detail/service bays on STAFF capacity and claims no stall at all,
  -- so those occupancies were invisible to the forward calendar -- which is how 22
  -- vehicles came to be "in" 2 physical service bays. OTTO-Q reconciles here: book what
  -- is physically there, in place, against a real stall. Release-only for chargers,
  -- non-fatal, and it never moves a vehicle that is already standing in a real bay.
  PERFORM ottoq.ottoq_bind_unbooked_bay_occupants(p_sim_run_id, v_depot, v_clock);

  SELECT lmp_usd_per_mwh INTO v_energy FROM ottoq_grid_snapshots WHERE sim_run_id=p_sim_run_id ORDER BY sim_clock_at DESC LIMIT 1;

  -- (1) ENERGY / BESS
  FOR v_bess IN SELECT bess_id, current_soc_pct FROM ottoq_bess_units WHERE depot_id = v_depot LOOP
    v_built := v_built + 1; v_t0 := clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := jsonb_build_object('depot_id',v_depot,'now_ts',v_clock,'bess_id',v_bess.bess_id,
              'bess_soc_pct',v_bess.current_soc_pct,'lmp_usd_mwh',COALESCE(v_energy.lmp_usd_per_mwh,40));
    v_proposal := ottoq_l2_propose_bess(v_bess.bess_id, v_depot, v_ctx);
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN
      v_deferred := v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'bess_dispatch','bess',v_bess.bess_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE;
    END IF;
    v_ctx := v_ctx || jsonb_build_object('requested_kw', v_proposal->>'requested_kw', 'action', v_proposal->>'action');
    v_t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('bess_dispatch','bess',v_bess.bess_id,v_ctx,NULL,v_depot);
    v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_bess(v_bess.bess_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1; END IF;
    v_t0 := clock_timestamp();
    IF v_outcome='enacted' THEN PERFORM ottoq_apply_bess_setpoint(v_bess.bess_id, (v_action->>'requested_kw')::numeric, 250, v_clock); END IF;
    v_enact_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'bess_dispatch','bess_dispatch','bess',v_bess.bess_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- (2) DEPLOY-READINESS
  SELECT COUNT(*) INTO v_total_fleet FROM vehicles WHERE category='autonomous' AND home_depot_id=v_depot;
  SELECT COUNT(*) INTO v_curr_deployed FROM vehicles
    WHERE category='autonomous' AND home_depot_id=v_depot AND current_state IN ('deployed','en_route_to_deployment');
  SELECT COALESCE((s.fleet_overrides->>'target_deployed_fraction')::numeric, 0.55) INTO v_target_pct
    FROM ottoq_sim_runs r LEFT JOIN ottoq_sim_scenarios s ON s.scenario_code = COALESCE(r.scenario_code,'normal_day')
   WHERE r.sim_run_id = p_sim_run_id;
  v_demand_target := FLOOR(v_total_fleet * ottoq_deploy_target_fraction(EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))::int, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',COALESCE(v_target_pct, 0.90))));
  v_deploy_budget := GREATEST(v_demand_target - v_curr_deployed, 0);

  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='staged_for_departure'
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
             WHERE vn.vehicle_id = v.id AND (vn.sim_run_id = p_sim_run_id OR vn.sim_run_id IS NULL) AND vn.status IN ('open','in_progress')
               AND ((a->>'svc' = 'software_update' AND COALESCE(a->>'status','pending') = 'in_progress')
                 OR (COALESCE((a->>'must_do')::boolean,false) AND a->>'svc' <> 'readiness_check'
                     AND COALESCE(a->>'status','pending') IN ('pending','in_progress'))))
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn2 WHERE vn2.vehicle_id = v.id
             AND vn2.status IN ('open','in_progress') AND vn2.urgency = 'overnight_hold'
             AND vn2.dispatch_due_at IS NOT NULL AND vn2.dispatch_due_at > v_clock)
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn3, jsonb_array_elements(vn3.atoms) a3
             WHERE vn3.vehicle_id = v.id AND vn3.status IN ('open','in_progress')
               AND COALESCE((a3->>'requires_tech_greenlight')::boolean,false)
               AND NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals ap
                     WHERE ap.vehicle_id = v.id AND ap.approval_type = 'tech_greenlight'
                       AND ap.status = 'approved' AND ap.created_at >= vn3.created_at))
     ORDER BY v.current_soc DESC, v.id LIMIT GREATEST(v_deploy_budget,0)
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('redeployment','vehicle',v_req.vehicle_id,v_depot,v_clock);
    -- A1: cuOpt/Nemotron may propose the redeploy; heuristic is the safe fallback.
    v_proposal := COALESCE(
      ottoq_l2_external_proposal(p_sim_run_id, 'redeployment', 'vehicle', v_req.vehicle_id),
      ottoq_l2_propose_deploy(v_req.vehicle_id, v_depot, v_ctx));
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'redeployment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE; END IF;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('redeployment','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_deploy(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      -- BRAIN/TWIN SEPARATION: OTTO-Q does NOT mutate vehicle state. It emits the
      -- command below; ottoq_sim_dispatch_vehicle (twin) performs the transition
      -- atomically with the dispatch record. Writing 'en_route_to_deployment'
      -- here created a limbo the rate-limited twin could not drain (task #169).
      PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'dispatch', jsonb_build_object('soc', v_req.current_soc), v_clock);
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,deploy_readiness,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'redeployment','redeployment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,CASE WHEN v_outcome='enacted' THEN 'ready' ELSE 'held' END,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- P0 (2026-08-03): A REOPENED NEED IS A FIRST-CLASS DEMAND.
  -- ottoq.ottoq_readmit_resumed_visits was unreachable: its emergency_staged /
  -- retrieved_staged pair is produced ONLY by tow retrieval, whose dwell gate compares a
  -- REAL-clock last_state_change (clobbered by the BEFORE UPDATE trigger) against the SIM
  -- clock and is therefore never true. This stage is keyed on the NEED instead, so a
  -- cut-short charge competes for a plug in the SAME tick, through the SAME intake
  -- cursors below, as a fresh arrival. Self-silencing; can never abort the tick.
  PERFORM ottoq.ottoq_readmit_reopened_needs(p_sim_run_id, v_depot, v_clock);

  -- (3) STALL ASSIGNMENT
  -- P2 RIGHT OF FIRST REFUSAL (2026-08-02). Advance the cuOpt deferral
  -- ledger EXACTLY ONCE per decide tick, before the candidate cursor is opened.
  -- roll() step 1 releases every vehicle that a PREVIOUS tick held, so a hold can
  -- never span two consecutive decide ticks; step 2 then consumes this tick's
  -- freshly armed rows. roll() swallows its own errors: if the ledger is broken
  -- the engine simply behaves exactly as it did before this change.
  PERFORM public.ottoq_cuopt_defer_roll(p_sim_run_id, v_tick);
  v_charge_cap_kw := ottoq_active_charge_cap_kw(p_sim_run_id, v_depot, v_clock);
  IF v_charge_cap_kw IS NOT NULL THEN
    SELECT COALESCE(SUM(LEAST(COALESCE(st.connector_max_kw,50), COALESCE(vv.inlet_max_kw,250)) * CASE WHEN COALESCE(st.connector_max_kw,50)<=50 THEN 1.0 WHEN COALESCE(vv.current_soc,50)<55 THEN 0.85 WHEN COALESCE(vv.current_soc,50)<75 THEN 0.55 ELSE 0.30 END),0) INTO v_ev_committed_kw
      FROM vehicles vv JOIN stalls st ON st.id = vv.current_stall_id
     WHERE vv.home_depot_id = v_depot AND vv.current_state IN ('charging_dcfc','charging_l2');
  END IF;

  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       -- P2 RIGHT OF FIRST REFUSAL (2026-08-02). Hold this vehicle out of the local
       -- greedy path for EXACTLY ONE decide tick while a cuOpt solve is in flight,
       -- so the optimizer's answer is not pre-empted by the stall it was solving for.
       -- ottoq_cuopt_defer_hold is READ-ONLY and goes FALSE the moment a usable
       -- proposal exists for this vehicle (right of FIRST REFUSAL, not veto) -- the
       -- vehicle then enters the cursor normally and the proposal is ENACTED here.
       -- It also goes FALSE unconditionally on the next decide tick. No vehicle can
       -- starve: see public.ottoq_cuopt_defer_roll / _arm.
       AND NOT public.ottoq_cuopt_defer_hold(p_sim_run_id, v.id, v_tick)
       AND (v.current_state = 'arrived_at_gate'
            OR (v.current_state = 'staged_awaiting_service' AND EXISTS (
                 SELECT 1 FROM stalls s2
                   JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
                  WHERE s2.depot_id = v_depot
                    AND s2.stall_type::text IN ('dcfc','l2')
                    AND s2.current_vehicle_id IS NULL
                    AND c2.station_state = 'Available'
                    AND (s2.reserved_by IS NULL OR s2.reserved_by = v.id
                         OR s2.reservation_expires_at <= v_clock))))
       AND v.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
              WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
              ORDER BY vn.created_at DESC LIMIT 1), 85)
     ORDER BY (SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                 WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                 ORDER BY vn.created_at DESC LIMIT 1) DESC NULLS LAST,
              v.current_soc ASC, v.id
     -- charging_staff gate: general techs plug in / unplug and do the interior
     -- clean at the stall, so STAFF (not stalls) cap how many cars can be on
     -- charge at once. Neutral staffing (cap >= the 45 physical charge stalls)
     -- leaves the cursor unbounded, so this is a no-op until the knob moves.
     LIMIT (CASE
              WHEN ottoq_sim_lane_capacity(p_sim_run_id, 'charging_staff', 45) >= 45
                THEN 2147483647
              ELSE GREATEST(0,
                     ottoq_sim_lane_capacity(p_sim_run_id, 'charging_staff', 45)
                     - (SELECT count(*) FROM vehicles vc
                         WHERE vc.home_depot_id = v_depot
                           AND vc.current_state IN ('charging_dcfc','charging_l2')))
            END)
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('stall_assignment','vehicle',v_req.vehicle_id,v_depot,v_clock);
    v_proposal := ottoq_honour_reservation_proposal(p_sim_run_id, v_req.vehicle_id, v_depot, v_ctx);
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      IF (SELECT current_stall_id FROM vehicles WHERE id = v_req.vehicle_id) IS NULL THEN
        -- DOCTRINE (Chase 2026-07-28): never a gate queue; temp vs perimeter is chosen by
          -- PURPOSE and duration, not by whichever staging stall sorts first.
          DECLARE v_disp jsonb; v_hold jsonb;
          BEGIN
            v_disp := ottoq_arrival_disposition(p_sim_run_id, v_depot, v_req.vehicle_id, v_clock);
            IF (v_disp->>'action') IN ('perimeter_hold','temp_stage_await_resource','temp_stage_tech_hold','quarantine') THEN
              v_hold := ottoq_book_hold_stall(
                          p_sim_run_id, v_depot, v_req.vehicle_id,
                          COALESCE((v_disp->>'stage_from')::timestamptz, v_clock),
                          COALESCE((v_disp->>'stage_until')::timestamptz, v_clock + interval '30 minutes'));
              IF COALESCE((v_hold->>'booked')::boolean, false) THEN
                SELECT b.stall_id INTO v_stage_stall
                  FROM ottoq_stall_bookings b WHERE b.booking_id = (v_hold->>'booking_id')::uuid;
                IF v_stage_stall IS NOT NULL
                   AND ottoq_reserve_stall(v_stage_stall, v_req.vehicle_id, v_clock, 900) THEN
                  UPDATE vehicles SET current_stall_id = v_stage_stall,
                         current_state = 'staged_awaiting_service'::vehicle_state,
                         last_state_change = v_clock
                   WHERE id = v_req.vehicle_id;
                  UPDATE stalls SET current_vehicle_id = v_req.vehicle_id, status = 'occupied'
                   WHERE id = v_stage_stall;
                END IF;
              END IF;
            END IF;
          END;
      END IF;
      CONTINUE; END IF;
    v_ctx := v_ctx || jsonb_build_object('stall_id', v_proposal->>'stall_id', 'requested_kw', v_proposal->>'requested_kw');
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_stall(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal;
      IF ottoq_reserve_stall((v_action->>'stall_id')::uuid, v_req.vehicle_id, v_clock, 600) THEN
        UPDATE stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL, status = 'available'
         WHERE current_vehicle_id = v_req.vehicle_id AND id <> (v_action->>'stall_id')::uuid;
        UPDATE vehicles SET current_state=(CASE WHEN v_action->>'stall_type'='dcfc' THEN 'charging_dcfc' ELSE 'charging_l2' END)::vehicle_state, current_stall_id=(v_action->>'stall_id')::uuid, last_state_change=v_clock WHERE id=v_req.vehicle_id;
        UPDATE stalls SET current_vehicle_id=v_req.vehicle_id, status='occupied' WHERE id=(v_action->>'stall_id')::uuid;
        PERFORM ottoq_claim_tick_kw(p_sim_run_id, v_tick, v_depot, (v_action->>'requested_kw')::numeric, v_req.vehicle_id);
        PERFORM ottoq_start_concurrent_atoms(v_req.vehicle_id, v_clock);
        PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_req.vehicle_id, v_clock);

        -- FORWARD AVAILABILITY / P0: ENACTMENT AND CALENDAR ARE ONE ACT.
        -- Every stall assignment that reaches this line - cuopt, deterministic, greedy and
        -- reservation_honoured all return through v_action above - is now recorded on the
        -- forward calendar in THIS transaction, against the EXACT stall enacted.
        --
        -- Previously the booking sat inside "IF v_charge_leg.leg_id IS NOT NULL", and the planner
        -- emits a charge leg only when the visit-need manifest carries an svc='charge' atom. When
        -- it does not, that branch never ran: 51 enacted charge assignments, 0 charge bookings,
        -- 0% end-to-end coverage. The booking no longer depends on a planned leg existing.
        --
        -- The leg is still PREFERRED when present, for two reasons: it carries the real timed
        -- window, and stamping to_stall_id is the existing sentinel that removes the leg from both
        -- booking cursors (ottoq_book_workflow / ottoq_find_and_book_stall), suppressing the second
        -- independent stall search. The calendar still RECORDS the decision, it never re-derives it.
        SELECT l.leg_id, l.leg_type, l.planned_start_sim, l.planned_end_sim
          INTO v_charge_leg
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id  = p_sim_run_id
           AND l.vehicle_id  = v_req.vehicle_id
           AND l.status      = 'planned'
           AND l.to_stall_id IS NULL
           AND l.leg_type IN ('charge_dcfc','charge_l2')
           AND l.planned_start_sim IS NOT NULL
           AND l.planned_end_sim   IS NOT NULL
           AND l.planned_end_sim   > v_clock
         ORDER BY l.seq
         LIMIT 1;

        -- p_purpose is left NULL so the purpose is derived from the stall ACTUALLY taken, not from
        -- what the planner intended. The helper supersedes phantom overlaps, is idempotent on
        -- (run, stall, vehicle, purpose, window), and can never abort this tick.
        v_bkg := ottoq.ottoq_record_enacted_booking(
                   p_sim_run_id, (v_action->>'stall_id')::uuid, v_req.vehicle_id, v_clock,
                   v_charge_leg.leg_id, v_charge_leg.planned_start_sim, v_charge_leg.planned_end_sim,
                   NULL, COALESCE(v_action->>'source','deterministic'));

        IF v_bkg IS NOT NULL AND v_charge_leg.leg_id IS NOT NULL THEN
          UPDATE public.ottoq_itinerary_legs
             SET to_stall_id = (v_action->>'stall_id')::uuid
           WHERE leg_id = v_charge_leg.leg_id;
        END IF;

        v_outcome:='enacted'; v_enacted:=v_enacted+1;
        v_ev_committed_kw := v_ev_committed_kw + COALESCE((v_action->>'requested_kw')::numeric,0);
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'begin_charge', jsonb_build_object('stall_id', v_action->>'stall_id', 'stall_type', v_action->>'stall_type', 'requested_kw', v_action->>'requested_kw'), v_clock);
      ELSE v_action:=ottoq_l1_safe_default_stall(v_req.vehicle_id,v_ctx); v_outcome:='deferred_stale_entity'; v_deferred:=v_deferred+1; END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- (3b) GATE INTAKE — NO-CHARGE ARRIVALS
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate'
       AND v.current_stall_id IS NULL
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                    WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') <> 'done'))
  LOOP
    SELECT s.id INTO v_stage_stall FROM stalls s
     WHERE s.depot_id = v_depot AND s.stall_type = 'staging'
       AND s.zone IS DISTINCT FROM 'arrival_inspection'
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= v_clock)
     ORDER BY (s.staging_role = 'temp') DESC, s.distance_from_entrance NULLS LAST, s.id LIMIT 1;
    IF v_stage_stall IS NOT NULL AND ottoq_reserve_stall(v_stage_stall, v_req.vehicle_id, v_clock, 900) THEN
      UPDATE vehicles SET current_stall_id = v_stage_stall,
             current_state = 'staged_awaiting_service'::vehicle_state,
             last_state_change = v_clock,
             config = jsonb_set(COALESCE(config,'{}'::jsonb), '{svc_step}',
               to_jsonb(CASE WHEN EXISTS (SELECT 1 FROM ottoq_visit_needs vn2, jsonb_array_elements(vn2.atoms) a2
                                           WHERE vn2.vehicle_id = v_req.vehicle_id AND vn2.status IN ('open','in_progress')
                                             AND a2->>'svc' IN ('mechanical_pm','fault_repair','sensor_calibration')
                                             AND COALESCE((a2->>'must_do')::boolean,false)
                                             AND COALESCE(a2->>'status','pending') = 'pending')
                            THEN 'need_service' ELSE 'need_deploy' END))
       WHERE id = v_req.vehicle_id;
      UPDATE stalls SET current_vehicle_id = v_req.vehicle_id, status = 'occupied' WHERE id = v_stage_stall;
      PERFORM ottoq_start_concurrent_atoms(v_req.vehicle_id, v_clock);
      v_built := v_built + 1; v_enacted := v_enacted + 1;
      PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_req.vehicle_id, v_clock);
      -- CALENDAR (staging). The single biggest gap: the whole service-only intake path
      -- enacted a stall and wrote NOTHING to the forward-occupancy calendar.
      -- We RECORD the stall the intake ALREADY picked above. We must NOT call
      -- ottoq_book_hold_stall here: it runs its OWN independent search, which is exactly
      -- the decision/calendar divergence fixed on 2026-08-01.
      SELECT l.leg_id INTO v_stage_leg_id
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.leg_type = 'stage' AND l.to_stall_id IS NULL
         AND l.planned_end_sim > v_clock
       ORDER BY l.seq LIMIT 1;
      -- The car holds this staging stall until its itinerary is done: nothing in (4) or (5)
      -- clears stalls.current_vehicle_id, only (3)'s charge branch and redeploy do.
      -- Hard-capped so a runaway itinerary can never reserve a space indefinitely.
      SELECT max(l.planned_end_sim) INTO v_stage_until
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.planned_end_sim > v_clock;
      v_stage_until := GREATEST(
        LEAST(
          COALESCE(v_stage_until,
                   v_clock + make_interval(mins => ottoq_policy_get(p_sim_run_id,'staging_hold_default_min',30)::int)),
          v_clock + make_interval(mins => ottoq_policy_get(p_sim_run_id,'staging_hold_max_min',480)::int)),
        v_clock + interval '1 minute');
      v_bkg := ottoq.ottoq_book_stall(p_sim_run_id, v_stage_stall, v_req.vehicle_id,
                 'staging', v_clock, v_stage_until, NULL, v_stage_leg_id,
                 ottoq.ottoq_booking_authorship('gate_intake_staging'));
      IF v_bkg IS NOT NULL THEN
        UPDATE public.ottoq_stall_bookings SET source = COALESCE(source, 'gate_intake_staging')
         WHERE booking_id = v_bkg;
      END IF;
      IF v_bkg IS NOT NULL AND v_stage_leg_id IS NOT NULL THEN
        -- same sentinel the charge path uses: a stamped to_stall_id removes the leg from
        -- ottoq_book_workflow's cursor, so no second independent search can re-derive it.
        UPDATE public.ottoq_itinerary_legs SET to_stall_id = v_stage_stall
         WHERE leg_id = v_stage_leg_id;
      END IF;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','gate_intake_no_charge','vehicle',v_req.vehicle_id,
              jsonb_build_object('stall_id',v_stage_stall,'staging_pick','temp_first'),
              jsonb_build_object('verb','gate_intake','stall_id',v_stage_stall),
              jsonb_build_object('verb','gate_intake','stall_id',v_stage_stall,'booking_id',v_bkg),
              'enacted',0,0);
      PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'proceed_to_stall', jsonb_build_object('stall_id', v_stage_stall, 'reason', 'gate_intake'), v_clock);
    END IF;
  END LOOP;

  -- (4) CHARGE DISPOSITION
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='charge_complete_holding'
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('task_start','vehicle',v_req.vehicle_id,v_depot,v_clock) || jsonb_build_object('requires_charging','false','service','wash');
    v_proposal := ottoq_l2_propose_charge_disposition(v_req.vehicle_id, v_depot, v_ctx || jsonb_build_object('sim_run_id', p_sim_run_id));
    v_prop_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE; END IF;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('task_start','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_charge_disposition(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      IF COALESCE(v_action->>'verb','admit_wash') = 'skip_wash' THEN
        -- SERVICE-NEED ROUTING (2026-08-01): no wash/detail work outstanding, so do
        -- NOT burn one of the depot's 3 wash bays on a clean car. Advance the vehicle
        -- inside the SAME atomic visit to what it does still need. Nothing is booked
        -- and no stall is claimed, so the calendar cannot over-report.
        UPDATE vehicles SET current_state='staged_awaiting_service', last_state_change=v_clock,
               config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',
                                to_jsonb(COALESCE(v_action->>'next_step','need_deploy'))) WHERE id=v_req.vehicle_id;
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'stage',
                jsonb_build_object('reason','no_wash_need','next_step',COALESCE(v_action->>'next_step','need_deploy')), v_clock);
        v_action := COALESCE(v_action,'{}'::jsonb) || jsonb_build_object('bay_booked', false, 'bay_stall_type', 'none');
      ELSE
      -- BAY ENTRY MOVED BELOW THE HELPER (Phase 3). It used to happen HERE, before any
      -- bay had been claimed or booked: if ottoq_enact_space_assignment then found no free
      -- bay, the vehicle was already 'in_wash_bay' with no stall and no calendar row --
      -- a bay physically occupied while the calendar showed it free. The state flip and
      -- the enter_wash command are now gated on the booking, exactly as (4b) already was.
      -- CALENDAR (wash/detail bay). CHOOSE + CLAIM + RECORD, one act.
      -- ottoq_enact_space_assignment picks the bay, reserves it, writes
      -- vehicles.current_stall_id and books the window in THIS transaction. The bay entry
      -- below is GATED on that result: no free bay means no entry, and the miss is recorded
      -- on the decision row as verb 'hold_no_bay'. The calendar can under-report a REFUSAL
      -- but it can no longer report a bay as free while a vehicle is standing in it.
      SELECT l.leg_id, l.leg_type, (l.planned_end_sim - l.planned_start_sim)
        INTO v_bay_leg_id, v_bay_leg_type, v_bay_dur
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.to_stall_id IS NULL
         AND l.leg_type IN ('wash','detail')
       ORDER BY l.seq LIMIT 1;
      IF v_bay_leg_id IS NULL THEN
        -- FALLBACK -- THIS IS WHY leg_id WAS NULL ON EVERY ENACTED BOOKING (11 of 11 on
        -- run 4332b898, against 94 of 94 on the planner path). The forward planner
        -- ottoq_book_workflow books the leg AHEAD of time and stamps to_stall_id, so the
        -- cursor above (to_stall_id IS NULL) found nothing and enactment booked a SECOND
        -- row on a possibly different stall with no leg. Adopt the planned leg instead:
        -- ottoq_enact_space_assignment honours its reservation and
        -- ottoq_record_enacted_booking adopts that row rather than duplicating it.
        SELECT l.leg_id, l.leg_type, (l.planned_end_sim - l.planned_start_sim)
          INTO v_bay_leg_id, v_bay_leg_type, v_bay_dur
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
           AND l.status IN ('planned','active')
           AND l.leg_type IN ('wash','detail')
         ORDER BY (l.status = 'active') DESC, l.seq LIMIT 1;
      END IF;
      -- TOTAL allow-list leg_type -> purpose. Only the two wash-lane leg types can reach
      -- here; nothing is ever passed through to the CLOSED 9-label purpose CHECK.
      -- (no detail_bay stalls are seeded - detail shares the wash lane, as in ottoq_book_workflow)
      v_bay_purpose := CASE WHEN COALESCE(v_action->>'bay_kind', v_bay_leg_type) = 'detail' THEN 'detail' ELSE 'wash' END;
      v_bay_until := v_clock + GREATEST(
        COALESCE(v_bay_dur,
                 make_interval(mins => ottoq_policy_get(p_sim_run_id,'wash_bay_default_min',25)::int)),
        interval '1 minute');
      v_space := ottoq.ottoq_enact_space_assignment(p_sim_run_id, v_depot, v_req.vehicle_id,
                     'wash_bay', v_bay_purpose, v_clock, v_bay_until,
                     v_bay_leg_id, 'charge_disposition');
      v_bay_bkg := NULLIF(v_space->>'booking_id','')::uuid;
      IF v_bay_bkg IS NOT NULL AND v_bay_leg_id IS NOT NULL THEN
        UPDATE public.ottoq_itinerary_legs
           SET to_stall_id = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                               WHERE b.booking_id = v_bay_bkg)
         WHERE leg_id = v_bay_leg_id;
      END IF;
      IF COALESCE((v_space->>'assigned')::boolean, false) THEN
        -- ENTRY AND CALENDAR ARE ONE ACT. A real wash bay has been claimed AND booked in
        -- this transaction, so the command names the stall, the booking and the leg.
        UPDATE vehicles SET current_state='in_wash_bay', last_state_change=v_clock,
               config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('washing'::text)) WHERE id=v_req.vehicle_id;
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'enter_wash',
                jsonb_build_object('stall_id',   v_space->>'stall_id',
                                   'booking_id', v_space->>'booking_id',
                                   'leg_id',     v_bay_leg_id,
                                   'purpose',    v_bay_purpose), v_clock);
        v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                    || jsonb_build_object('bay_booked', v_bay_bkg IS NOT NULL,
                                          'bay_purpose', v_bay_purpose,
                                          'bay_stall_type', 'wash_bay',
                                          'stall_id', v_space->>'stall_id',
                                          'booking_id', v_space->>'booking_id',
                                          'leg_id', v_bay_leg_id);
      ELSE
        -- NO BAY -> DO NOT ENTER ONE. The vehicle is left exactly where this proposer's own
        -- 'wash_lane_full_hold' abstain leaves it (charge_complete_holding) and is retried
        -- next tick. No state write, no command, no booking. Throughput cannot regress:
        -- this branch is only reachable when there is genuinely no bookable wash bay, and
        -- release step (b) hard-frees stale bay stalls earlier in this same tick.
        v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                    || jsonb_build_object('verb','hold_no_bay', 'bay_booked', false,
                                          'bay_purpose', v_bay_purpose,
                                          'bay_stall_type', 'wash_bay');
        v_outcome := 'noop_no_candidate'; v_enacted := v_enacted - 1; v_deferred := v_deferred + 1;
      END IF;
      END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- ══════════════════════════════════════════════════════════════════════════════════
  -- (4b) NEEDS-CARD SPACE ROUTING  —  P1, 2026-08-01
  --
  -- WHAT THIS CLOSES. Before this block the engine literally could not decide "send this
  -- vehicle to the wash bay". The ONLY door into in_wash_bay/in_detail_bay was section (4),
  -- whose cursor is current_state='charge_complete_holding'. Measured on run c177c1ca over
  -- 573 ticks: ZERO admit_wash decisions, 5 skip_wash — while 371 vehicles were promoted
  -- straight from staged_awaiting_service to staged_for_departure by (5), a state from which
  -- no wash/detail door existed at all. That is the whole reason 51 of 51 (and 209 of 209
  -- before) enacted assignments were charging while 3 wash bays sat 100 pct idle.
  --
  -- WHAT IT DOES. For each vehicle HOLDING in staging, read public.ottoq_vehicle_needs_card,
  -- take the highest-priority must-do need that requires a SPACE, and place the vehicle into
  -- the space that need's lane requires — through ottoq_enact_space_assignment, so choosing
  -- the stall and writing the forward-calendar booking are ONE act against the SAME stall
  -- (the P0 rule, now extended past chargers).
  --
  -- SPACE MAP is read from service_cadence_policy.lane, never hardcoded, and is TOTAL:
  --   lane 'wash_bay'    (exterior_wash)                        -> wash_bay,    purpose 'wash'
  --   lane 'detail'      (interior_deep_clean)                  -> wash_bay,    purpose 'detail'
  --        ^ zero detail_bay stalls are seeded; detail shares the wash lane, exactly as
  --          ottoq_book_workflow and twin STEP 2 already do.
  --   lane 'service_bay' (fault_repair, sensor_calibration,
  --                       mechanical_pm, cosmetic_repair)       -> service_bay, purpose 'service'
  --   lane 'anchor'      (charge)      -> NOT HANDLED HERE, see CHARGE FIREWALL.
  --   lane 'cabin'/'exterior'/'digital'/'gate' -> NO SPACE AT ALL. That work overlaps
  --        charging and is already started at the stall by ottoq_start_concurrent_atoms;
  --        spending one of 3 wash or 2 service bays on it would be a straight loss.
  --   any lane the catalogue gains later -> no space, silently skipped. TOTAL FUNCTION
  --        (the 2026-08-01 leg_type lesson): an unknown lane can never reach a CHECK.
  --
  -- ══ ORDERING / PRIORITY RULE ══
  --   WITHIN a vehicle : lowest service_cadence_policy.sequence_order wins, so the visit is
  --     worked in the catalogue's own order (fault_repair 30 -> wash 40 -> detail 45 ->
  --     calibration 55 -> pm 60 -> cosmetic 70). One space at a time; the vehicle comes back
  --     through this block on a later tick for the next item, inside ONE atomic visit.
  --   ACROSS vehicles  : 1. urgency rank DESC (critical > overdue > due > due_soon > ok)
  --                      2. fits_window DESC  — do not burn a scarce bay on work that
  --                         provably cannot finish before the vehicle is due out
  --                      3. minutes_to_deploy ASC — earliest deadline first (EDF)
  --                      4. open_must_do_min ASC — shortest job first, so a scarce bay
  --                         clears more vehicles per hour
  --                      5. vehicle_id — deterministic, seed-stable tiebreak
  --
  -- ══ CHARGE FIREWALL — five independent reasons this cannot regress charging ══
  --  1. Sections (1),(2),(3),(3b) are byte-for-byte unchanged by this migration, including
  --     Gate B in ottoq_honour_reservation_proposal and the cuOpt 'source' passthrough.
  --  2. This block only ever asks for 'wash_bay' or 'service_bay', and
  --     ottoq_enact_space_assignment REFUSES 'dcfc'/'l2' outright. No path built here can
  --     reserve, occupy or book a charger.
  --  3. Any vehicle whose card still lists 'charge' in must_do_now is SKIPPED and left to
  --     section (3). Charge is the anchor leg (sequence_order 10): energy first, then bays.
  --  4. It runs AFTER (3), so every charge decision this tick is already made and its stalls
  --     already reserved before one bay is considered.
  --  5. Separate staff pools: charging is capped by 'charging_staff', wash by
  --     LEAST(cleaning_staff, wash_supervisor), service by 'service_staff'. Bay work cannot
  --     consume a charging tech.
  --  NET EFFECT ON CHARGING IS POSITIVE: today a vehicle in a bay still holds the l2/dcfc
  --  stall it charged on, because nothing clears it. Occupying the bay moves
  --  vehicles.current_stall_id, which fires trg_sync_stall_occupancy and hands that charger
  --  straight back to section (3). Chargers are freed sooner, never later.
  --
  -- ══ ANTI-STARVATION ══ wash and service headroom are computed with the TWIN'S OWN
  -- capacity formulas, verbatim, so this block can never admit past the lane the twin itself
  -- would allow, and the two lanes are counted separately so neither can starve the other.
  --
  -- ══ IN-DEPOT REASSIGNMENT / ZONES ══ the cursor is restricted to current_state
  -- 'staged_awaiting_service', a HOLDING state. It structurally cannot pick up a vehicle that
  -- is charging, washing or being serviced, so it can never re-route work in progress and
  -- therefore never needs ottoq_indepot_reassignment_guard — this is forward progression to
  -- the next due leg of the same visit, which is exactly what (4) and (5) already do. Zone C
  -- (malfunction / congestion / flag) vehicles are skipped and left to the exception path
  -- that owns them. Zone is NOT required to be 'A' here: ottoq_approach_zone fails closed to
  -- 'B' for any vehicle with no approach-band row, which is every in-depot vehicle, so an
  -- A-only test would silently disable the whole block.
  --
  -- ══ COST ══ ottoq_vehicle_needs_card is a 116-row / ~250 ms view. It is evaluated ONCE per
  -- tick and only after two cheap pre-checks find both a waiting vehicle and lane headroom.
  -- ══════════════════════════════════════════════════════════════════════════════════
  SELECT count(*) FILTER (WHERE s.stall_type = 'wash_bay'::stall_type),
         count(*) FILTER (WHERE s.stall_type = 'service_bay'::stall_type)
    INTO v_wash_phys, v_svc_phys
    FROM stalls s
   WHERE s.depot_id = v_depot AND s.status NOT IN ('maintenance','closed');

  IF COALESCE(v_wash_phys,0) + COALESCE(v_svc_phys,0) > 0
     AND EXISTS (SELECT 1 FROM vehicles v
                  WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
                    AND v.current_state = 'staged_awaiting_service') THEN

    v_wash_open := GREATEST(0,
      LEAST(ottoq_sim_lane_capacity(p_sim_run_id,'cleaning_staff', GREATEST(COALESCE(v_wash_phys,0),1)),
            ottoq_depot_staffing_count(v_depot,'wash_supervisor'))
      - (SELECT count(*) FROM vehicles
          WHERE home_depot_id = v_depot AND current_state IN ('in_wash_bay','in_detail_bay')));
    v_svc_open := GREATEST(0,
      ottoq_sim_lane_capacity(p_sim_run_id,'service_staff', GREATEST(COALESCE(v_svc_phys,0),1))
      - (SELECT count(*) FROM vehicles
          WHERE home_depot_id = v_depot AND current_state = 'in_service_bay'));

    IF COALESCE(v_wash_open,0) + COALESCE(v_svc_open,0) > 0 THEN
      FOR v_need IN
        WITH card AS (
          SELECT c.vehicle_id, c.overall_urgency, c.must_do_now, c.minutes_to_deploy,
                 c.fits_window, c.open_must_do_min
            FROM public.ottoq_vehicle_needs_card c
           WHERE c.depot_id = v_depot
             -- CHARGE FIRST (full-service visit doctrine, anchor leg): if energy is still a
             -- must-do, this vehicle belongs to section (3), not to a bay.
             AND NOT ('charge' = ANY (COALESCE(c.must_do_now, '{}'::text[])))
        ), spaced AS (
          SELECT k.vehicle_id, k.overall_urgency, k.minutes_to_deploy, k.fits_window,
                 k.open_must_do_min, x.svc, p.lane, p.sequence_order,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash_bay'
                             WHEN 'detail'      THEN 'wash_bay'
                             WHEN 'service_bay' THEN 'service_bay' END AS stall_type,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash'
                             WHEN 'detail'      THEN 'detail'
                             WHEN 'service_bay' THEN 'service' END AS purpose,
                 CASE p.lane WHEN 'wash_bay'    THEN 'in_wash_bay'
                             WHEN 'detail'      THEN 'in_detail_bay'
                             WHEN 'service_bay' THEN 'in_service_bay' END AS new_state,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash_time'
                             WHEN 'detail'      THEN 'detail_time'
                             WHEN 'service_bay' THEN 'maintenance_time' END AS time_key,
                 CASE p.lane WHEN 'wash_bay'    THEN 9
                             WHEN 'detail'      THEN 25
                             ELSE 40 END AS base_min
            FROM card k
            CROSS JOIN LATERAL unnest(k.must_do_now) AS x(svc)
            JOIN public.service_cadence_policy p ON p.svc = x.svc AND p.is_active
           WHERE p.lane IN ('wash_bay','detail','service_bay')
        ), pick AS (
          -- SEQUENCE inside the visit: the catalogue's own order.
          SELECT DISTINCT ON (s.vehicle_id) s.*
            FROM spaced s
           ORDER BY s.vehicle_id, s.sequence_order, s.svc
        )
        SELECT pk.vehicle_id, pk.svc, pk.lane, pk.stall_type, pk.purpose, pk.new_state,
               pk.time_key, pk.base_min, pk.overall_urgency, pk.minutes_to_deploy,
               pk.fits_window, pk.open_must_do_min, pk.sequence_order, v.fleet_operator_id
          FROM pick pk
          JOIN vehicles v ON v.id = pk.vehicle_id
         WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
           AND v.current_state = 'staged_awaiting_service'
           AND COALESCE(public.ottoq_approach_zone(pk.vehicle_id, p_sim_run_id),'B') <> 'C'
         ORDER BY public.ottoq_urgency_rank(pk.overall_urgency) DESC,
                  pk.fits_window DESC NULLS LAST,
                  pk.minutes_to_deploy ASC NULLS LAST,
                  pk.open_must_do_min ASC NULLS LAST,
                  pk.vehicle_id
         LIMIT 20
      LOOP
        IF v_need.stall_type = 'wash_bay'    AND COALESCE(v_wash_open,0) <= 0 THEN CONTINUE; END IF;
        IF v_need.stall_type = 'service_bay' AND COALESCE(v_svc_open,0)  <= 0 THEN CONTINUE; END IF;

        v_built := v_built + 1; v_t0 := clock_timestamp();
        v_over := false; v_safe := false; v_block_codes := '{}'; v_rule_rows := NULL;
        v_ctx := ottoq_build_decision_context('task_start','vehicle',v_need.vehicle_id,v_depot,v_clock)
                 || jsonb_build_object('need', v_need.svc, 'lane', v_need.lane,
                      'stall_type', v_need.stall_type, 'purpose', v_need.purpose,
                      'overall_urgency', v_need.overall_urgency,
                      'minutes_to_deploy', v_need.minutes_to_deploy,
                      'fits_window', v_need.fits_window,
                      'open_must_do_min', v_need.open_must_do_min,
                      'sequence_order', v_need.sequence_order,
                      'requires_charging','false','service', v_need.purpose);
        v_proposal := jsonb_build_object('abstain', false, 'verb','assign_stall',
                        'resolved_action_context','stall_assignment', 'source','needs_card',
                        'vehicle_id', v_need.vehicle_id, 'stall_type', v_need.stall_type,
                        'purpose', v_need.purpose, 'need', v_need.svc, 'requested_kw', 0);
        v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

        v_t0 := clock_timestamp();
        SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
               jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
          INTO v_blocks, v_block_codes, v_rule_rows
          FROM ottoq_shield_probe('task_start','vehicle',v_need.vehicle_id,v_ctx,v_need.fleet_operator_id,v_depot);
        v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

        v_t0 := clock_timestamp();
        IF COALESCE(v_blocks,0) > 0 THEN
          -- SHIELD BLOCKS => take NO space. The vehicle stays in staging and section (5)
          -- handles it exactly as today. Bays are ADDITIVE, so a refusal here can only ever
          -- return the engine to its pre-P1 behaviour - never worse.
          v_action := jsonb_build_object('verb','hold_no_space','reason','shield_block');
          v_safe := true; v_over := true; v_outcome := 'overridden_to_default'; v_overc := v_overc + 1;
        ELSE
          -- TIMING BELONGS TO THE TWIN. ottoq_sim_service_minutes is the exact function
          -- twin STEP 2 uses for its own admissions, so routing a car here cannot invent a
          -- new dwell regime. The planner's timed leg is preferred whenever one exists.
          SELECT l.leg_id, l.planned_end_sim INTO v_bay_leg_id, v_bay_until
            FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_need.vehicle_id
             AND l.status = 'planned' AND l.to_stall_id IS NULL
             AND l.leg_type = public.ottoq_svc_to_leg_type(v_need.svc)
             AND l.planned_end_sim IS NOT NULL AND l.planned_end_sim > v_clock
           ORDER BY l.seq LIMIT 1;
          v_bay_until := GREATEST(
            COALESCE(v_bay_until,
                     v_clock + make_interval(mins => GREATEST(
                       ottoq_sim_service_minutes(p_sim_run_id, v_need.time_key, v_need.base_min)::int, 1))),
            v_clock + interval '1 minute');

          v_space := ottoq.ottoq_enact_space_assignment(
                       p_sim_run_id, v_depot, v_need.vehicle_id, v_need.stall_type,
                       v_need.purpose, v_clock, v_bay_until, v_bay_leg_id, 'needs_card');

          IF COALESCE((v_space->>'assigned')::boolean, false) THEN
            UPDATE vehicles
               SET current_state = v_need.new_state::vehicle_state,
                   last_state_change = v_clock,
                   config = jsonb_set(
                              jsonb_set(COALESCE(config,'{}'::jsonb), '{svc_step}',
                                to_jsonb(CASE WHEN v_need.stall_type = 'service_bay'
                                              THEN 'servicing' ELSE 'washing' END)),
                              '{service_ends_at}', to_jsonb(v_bay_until::text))
             WHERE id = v_need.vehicle_id;
            IF v_need.stall_type = 'wash_bay' THEN v_wash_open := v_wash_open - 1;
                                              ELSE v_svc_open  := v_svc_open  - 1; END IF;
            v_action := v_proposal || v_space
                        || jsonb_build_object('verb','assign_stall',
                             'stall_id', v_space->>'stall_id',
                             'bay_booked', (v_space->>'booking_id') IS NOT NULL);
            v_outcome := 'enacted'; v_enacted := v_enacted + 1;
            PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_need.vehicle_id,
              'proceed_to_stall',
              jsonb_build_object('stall_id', v_space->>'stall_id',
                                 'reason', 'needs_card_' || v_need.purpose,
                                 'need', v_need.svc), v_clock);
          ELSE
            v_action := v_proposal || COALESCE(v_space,'{}'::jsonb)
                        || jsonb_build_object('verb','hold_no_space');
            v_outcome := 'noop_no_candidate'; v_deferred := v_deferred + 1;
          END IF;
        END IF;
        v_enact_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
        -- action_context 'task_start' matches the probe context used by (4) and (5) for bay
        -- admissions; resolved_action_context 'stall_assignment' is the HONEST classification
        -- because a space really was claimed AND booked - which is also what makes bays
        -- finally countable in the enacted_stall_by_space_type metric that read 51/51 charging.
        INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
        VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','stall_assignment','vehicle',v_need.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
      END LOOP;
    END IF;
  END IF;

  -- (5) SERVICE SEQUENCING
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.fleet_operator_id, v.config->>'svc_step' AS svc_step
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='staged_awaiting_service'
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('task_start','vehicle',v_req.vehicle_id,v_depot,v_clock) || jsonb_build_object('svc_step', v_req.svc_step, 'requires_charging','false','service','service');
    -- A1: cuOpt/Nemotron may propose the service order; heuristic is the fallback.
    v_proposal := COALESCE(
      ottoq_l2_external_proposal(p_sim_run_id, 'service_sequencing', 'vehicle', v_req.vehicle_id),
      ottoq_l2_propose_service(v_req.vehicle_id, v_depot, v_ctx));
    v_prop_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('task_start','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_service(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      IF v_action->>'verb'='admit_service' THEN
        -- BAY ENTRY MOVED BELOW THE HELPER (Phase 3) -- same defect and same fix as (4).
        -- CALENDAR (service bay). CHOOSE + RECORD ONLY, never gating - same contract as (4).
        SELECT l.leg_id, (l.planned_end_sim - l.planned_start_sim)
          INTO v_bay_leg_id, v_bay_dur
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
           AND l.status = 'planned' AND l.to_stall_id IS NULL
           AND l.leg_type IN ('service','mechanical_pm','fault_repair','sensor_calibration','cosmetic_repair')
         ORDER BY l.seq LIMIT 1;
        IF v_bay_leg_id IS NULL THEN
          -- FALLBACK: adopt the leg the forward planner already booked (see section (4)).
          SELECT l.leg_id, (l.planned_end_sim - l.planned_start_sim)
            INTO v_bay_leg_id, v_bay_dur
            FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
             AND l.status IN ('planned','active')
             AND l.leg_type IN ('service','mechanical_pm','fault_repair','sensor_calibration','cosmetic_repair')
           ORDER BY (l.status = 'active') DESC, l.seq LIMIT 1;
        END IF;
        -- TOTAL allow-list: all five of those leg types collapse to the single legal
        -- purpose 'service'. The leg_type itself is NEVER passed through.
        v_bay_until := v_clock + GREATEST(
          COALESCE(v_bay_dur,
                   make_interval(mins => ottoq_policy_get(p_sim_run_id,'service_bay_default_min',45)::int)),
          interval '1 minute');
        v_space := ottoq.ottoq_enact_space_assignment(p_sim_run_id, v_depot, v_req.vehicle_id,
                       'service_bay', 'service', v_clock, v_bay_until,
                       v_bay_leg_id, 'service_sequencing');
        v_bay_bkg := NULLIF(v_space->>'booking_id','')::uuid;
        IF v_bay_bkg IS NOT NULL AND v_bay_leg_id IS NOT NULL THEN
          UPDATE public.ottoq_itinerary_legs
             SET to_stall_id = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                                 WHERE b.booking_id = v_bay_bkg)
           WHERE leg_id = v_bay_leg_id;
        END IF;
        IF COALESCE((v_space->>'assigned')::boolean, false) THEN
          UPDATE vehicles SET current_state='in_service_bay', last_state_change=v_clock,
                 config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('servicing'::text)) WHERE id=v_req.vehicle_id;
          PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'enter_service',
                  jsonb_build_object('stall_id',   v_space->>'stall_id',
                                     'booking_id', v_space->>'booking_id',
                                     'leg_id',     v_bay_leg_id,
                                     'purpose',    'service'), v_clock);
          v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                      || jsonb_build_object('bay_booked', v_bay_bkg IS NOT NULL,
                                            'bay_purpose', 'service',
                                            'bay_stall_type', 'service_bay',
                                            'stall_id', v_space->>'stall_id',
                                            'booking_id', v_space->>'booking_id',
                                            'leg_id', v_bay_leg_id);
        ELSE
          -- NO BAY -> DO NOT ENTER ONE. Identical in effect to this proposer's own
          -- 'hold_in_queue': the vehicle stays in staged_awaiting_service and is retried.
          v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                      || jsonb_build_object('verb','hold_no_bay', 'bay_booked', false,
                                            'bay_purpose', 'service',
                                            'bay_stall_type', 'service_bay');
          v_outcome := 'noop_no_candidate'; v_enacted := v_enacted - 1; v_deferred := v_deferred + 1;
        END IF;
      ELSIF v_action->>'verb' = 'hold_in_queue' THEN
        -- SERVICE-NEED HOLD: must-do bay work outstanding and no free bay (or the
        -- shield blocked). Leave the vehicle in staged_awaiting_service - no state
        -- write at all - so the service queue keeps it instead of redeploying a
        -- vehicle with mandatory work open. The proposer bounds this with a
        -- patience threshold, so a hold can never strand a vehicle.
        NULL;
      ELSE
        UPDATE vehicles SET current_state='staged_for_departure', last_state_change=v_clock,
               config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('ready'::text)) WHERE id=v_req.vehicle_id;
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'stage', jsonb_build_object('ready', true), v_clock);
      END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- A3: close the external-proposal lifecycle for this tick — consumed
  -- (entity got an enacted decision) → 'enacted'; past-freshness → 'expired'.
  UPDATE ottoq_external_proposals p SET status='enacted'
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND EXISTS (SELECT 1 FROM ottoq_decisions d
                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
                    AND d.entity_id=p.entity_id AND d.outcome_status='enacted'
                    AND d.enacted_action->>'source' = p.source);
  -- honest pre-emption: the entity was decided this tick, but NOT by this proposal
  UPDATE ottoq_external_proposals p SET status='superseded'
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND EXISTS (SELECT 1 FROM ottoq_decisions d
                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
                    AND d.entity_id=p.entity_id AND d.outcome_status='enacted');
  UPDATE ottoq_external_proposals p SET status='expired'
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND GREATEST(COALESCE(p.expires_at, p.created_at+interval '35 minutes'), p.created_at+interval '35 minutes') < v_clock;

  -- ══════════════════ BUILD 3: THE INSPECT SEAM (ADDITIVE) ══════════════════
  -- 177 inspect legs ended the prior run still 'planned' across 110 arriving vehicles
  -- while 14 inspection stalls per depot sat idle, because (1) the needs card never
  -- emits 'interior_inspection', (2) this tick's bay loop filters to lanes
  -- wash_bay/detail/service_bay and inspection is lane 'cabin', and (3) inspection
  -- stalls are stall_type='staging' so no caller could address them.
  -- Placed HERE, last, on purpose: charging (3), the bay loop and service sequencing
  -- (5) have all already run, so the seam can only take vehicles nothing else claimed.
  -- It never raises (see the handler inside) -- the 2026-08-01 leg_type lesson.
  v_enacted := v_enacted + COALESCE(
    ottoq.ottoq_enact_inspection_seam(p_sim_run_id, v_depot, v_tick, v_snapshot_id, v_clock), 0);

  PERFORM ottoq.ottoq_link_bookings_to_decisions(p_sim_run_id, v_tick);

  RETURN ROW(v_tick, v_clock, v_built, v_enacted, v_overc, v_deferred, v_errored, v_disn,
             (SELECT COALESCE(SUM(total_latency_ms),0) FROM ottoq_decisions WHERE sim_run_id=p_sim_run_id AND tick_seq=v_tick))::ottoq_decide_tick_result;
END;
$function$

-- ===== ottoq_demand_charge_per_kw =====
CREATE OR REPLACE FUNCTION public.ottoq_demand_charge_per_kw(p_depot_id uuid, p_at timestamp with time zone DEFAULT now())
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE(
    (SELECT demand_excess_usd_kw FROM public.ottoq_depot_tariffs
      WHERE depot_id = p_depot_id AND active
        AND EXTRACT(MONTH FROM p_at AT TIME ZONE 'America/Chicago')::int = ANY(season_months)
      ORDER BY effective_from DESC LIMIT 1),
    10);
$function$

-- ===== ottoq_demo_metronome =====
CREATE OR REPLACE PROCEDURE public.ottoq_demo_metronome(IN p_budget_s integer DEFAULT 50)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_start timestamptz := clock_timestamp();
  v_run RECORD; v_advanced timestamptz; v_interval numeric; v_base numeric := 6.0;
  v_any boolean; v_window_ms numeric; v_req bigint;
  v_max_ticks int; v_floor numeric; v_max_real_min numeric; v_stop_reason text;
  v_fire_beat_at timestamptz;
BEGIN
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM ottoq_sim_runs
      WHERE status = 'running'
        AND COALESCE(run_by,'') NOT IN ('production_live','cert_harness')
    ) INTO v_any;
    EXIT WHEN NOT v_any;

    FOR v_run IN
      SELECT sim_run_id,
             COALESCE((payload->>'speed_x')::numeric, demo_speed_x, 1.0) AS spd,
             COALESCE(payload->>'playback_mode','fixed') AS pmode,
             next_tick_due_at, started_at,
             depot_id, COALESCE(policy,'otto_q') AS policy, COALESCE(tick_count,0) AS ticks
      FROM ottoq_sim_runs
      WHERE status = 'running'
        AND COALESCE(run_by,'') NOT IN ('production_live','cert_harness')
    LOOP
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;
      v_fire_beat_at := NULL;

      -- ═══════════ RUNAWAY BACKSTOP (playback-mode aware) ═══════════
      -- A TICK IS NOT A COMPARABLE UNIT ACROSS PLAYBACK MODES.
      --   fixed: 30 sim-min/tick  => 240 ticks = 5 sim-days (never binds).
      --   live : cadence is 6/speed_x REAL seconds and the clock advances
      --          real_elapsed * speed_x, so a tick is a CONSTANT 0.1 sim-min at
      --          any speed 1x-3x => 240 ticks = 24 SIM-MINUTES.
      -- So in live mode the backstop is REAL wall-clock time. Both are per-run
      -- policy-tunable.
      v_stop_reason := NULL;
      IF v_run.pmode = 'live' THEN
        v_max_ticks    := GREATEST(10, ottoq_policy_get(v_run.sim_run_id, 'demo_max_ticks_live', 5000)::int);
        v_max_real_min := GREATEST(1, ottoq_policy_get(v_run.sim_run_id, 'demo_max_real_minutes', 60));
      ELSE
        v_max_ticks    := GREATEST(10, ottoq_policy_get(v_run.sim_run_id, 'demo_max_ticks', 240)::int);
        v_max_real_min := NULL;
      END IF;

      IF v_run.ticks >= v_max_ticks THEN
        v_stop_reason := 'tick ceiling ' || v_max_ticks || ' reached';
      ELSIF v_max_real_min IS NOT NULL
        AND EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_run.started_at, clock_timestamp())))/60.0
            >= v_max_real_min THEN
        v_stop_reason := 'live-mode real-time ceiling ' || round(v_max_real_min,1) || ' real-min reached';
      END IF;

      IF v_stop_reason IS NOT NULL THEN
        BEGIN
          PERFORM set_config('lock_timeout', '8000', true);
          PERFORM ottoq_sim_stop_and_reset(
            v_run.sim_run_id,
            'auto-stopped by metronome: ' || v_stop_reason || ' (perpetuity backstop)');
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'metronome ceiling-stop % failed: % — forcing status', v_run.sim_run_id, SQLERRM;
          UPDATE ottoq_sim_runs
             SET status = 'completed',
                 ended_at = COALESCE(ended_at, now()),
                 failure_reason = COALESCE(failure_reason, v_stop_reason || '; forced stop')
           WHERE sim_run_id = v_run.sim_run_id;
        END;
        COMMIT;
        CONTINUE;
      END IF;

      v_floor := GREATEST(0.2, ottoq_policy_get(v_run.sim_run_id, 'tick_cadence_floor_s', 2.0));
      IF v_run.pmode = 'live' THEN
        v_interval := GREATEST(v_floor, v_base / GREATEST(v_run.spd, 0.25));
      ELSE
        v_interval := GREATEST(0.2, v_base / GREATEST(v_run.spd, 0.25));
      END IF;
      CONTINUE WHEN v_run.next_tick_due_at IS NOT NULL AND clock_timestamp() < v_run.next_tick_due_at;

      v_advanced := NULL;
      BEGIN
        PERFORM set_config('lock_timeout', '8000', true);
        SELECT out_sim_clock_after INTO v_advanced FROM public.ottoq_sim_advance_tick_world(v_run.sim_run_id) LIMIT 1;
      EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome world % failed: %', v_run.sim_run_id, SQLERRM; END;

      IF v_advanced IS NOT NULL THEN
        -- ═══════════════ SPLIT TICK: alternate FIRE and DECIDE ═══════════════
        -- v_run.ticks is the PRE-increment tick_count.
        IF (v_run.ticks % 2) = 1 THEN
          ------------------------------------------------------------------
          -- DECIDE BEAT. ottoq_decide_tick -> ottoq_honour_reservation_proposal
          -- -> ottoq_l2_external_proposal finds the PENDING source='cuopt'
          -- proposal the previous FIRE beat left waiting, and that function's
          -- ORDER BY ranks 'cuopt' above 'greedy_constrained'. Its effective TTL
          -- floors at 35 REAL minutes, so the edge function's 90 s ttl is not a
          -- risk. ottoq_l2_optimize_assignments' FR-3 clause sees the fresh
          -- cuopt row and yields that vehicle, so local greedy does not
          -- overwrite it.
          -- P6: decide_and_dispatch's own cuOpt fire stands itself down while
          -- the heartbeat stamped below is fresh, so this beat no longer posts a
          -- structurally-late request.
          ------------------------------------------------------------------
          BEGIN
            PERFORM set_config('lock_timeout', '8000', true);
            PERFORM public.ottoq_sim_decide_and_dispatch(v_run.sim_run_id);
          EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome decide % failed: %', v_run.sim_run_id, SQLERRM; END;
        ELSE
          ------------------------------------------------------------------
          -- FIRE BEAT. No decide ran this beat, so at-gate low-SoC vehicles are
          -- still at the gate and their stalls are still unreserved when the
          -- COMMIT below releases the pg_net request. That is the ONLY ordering
          -- that lets the edge function see candidates > 0 AND freeStalls > 0
          -- simultaneously, clear its {"source":"none"} early return, and reach
          -- the NVIDIA key.
          --
          -- P6 FIX 2: the `cuopt_contention_min` pre-count is GONE. It was an
          -- at-gate-only duplicate of a predicate ottoq_cuopt_refresh already
          -- owns properly, so it could only ever VETO a fire the real gate would
          -- have allowed — and at its default of 2 it did exactly that, holding
          -- the healthy beat to 10 fires out of 73. Calling refresh directly
          -- also restores the en-route reservation-upgrade cohort on this beat
          -- (the old count could not see it) and costs one query fewer.
          -- refresh() self-gates: it returns early and logs
          -- 'sql_gate_no_candidates' at zero candidates, so NVIDIA is only paid
          -- when there is >= 1 REAL candidate, and its own debounce (2 real s,
          -- below the 4.0 s fire cadence at 3x) throttles spend.
          -- The old `DELETE FROM ottoq_cuopt_fire_log` hack is REMOVED — it only
          -- existed to punch through the stamp the decide-beat fire left, and
          -- that fire no longer happens here.
          ------------------------------------------------------------------
          IF v_run.policy = 'otto_q' THEN
            v_window_ms := ottoq_policy_get(v_run.sim_run_id, 'cuopt_solve_window_ms', 4000); -- ENABLE flag (>0)
            IF v_window_ms > 0 THEN
              v_req := NULL;
              BEGIN
                PERFORM set_config('lock_timeout', '8000', true);
                v_req := ottoq_cuopt_refresh(v_run.sim_run_id);
              EXCEPTION WHEN OTHERS THEN NULL; END;
              -- Heartbeat: proves to decide_and_dispatch that a healthy fire beat
              -- is live, so it stands its own late fire down. Stamped whether or
              -- not refresh posted — the beat RAN, which is what is being claimed.
              v_fire_beat_at := clock_timestamp();
            END IF;
          END IF;
        END IF;
      END IF;

      UPDATE ottoq_sim_runs
         SET next_tick_due_at = clock_timestamp() + make_interval(secs => v_interval),
             payload = CASE WHEN v_fire_beat_at IS NOT NULL
                            THEN COALESCE(payload,'{}'::jsonb)
                                 || jsonb_build_object('cuopt_fire_beat_at', v_fire_beat_at)
                            ELSE payload END
       WHERE sim_run_id = v_run.sim_run_id;
      COMMIT;
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;
    END LOOP;
    EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;
    PERFORM pg_sleep(0.4);
  END LOOP;
END;
$procedure$

-- ===== ottoq_deploy_target_fraction =====
CREATE OR REPLACE FUNCTION public.ottoq_deploy_target_fraction(p_hour integer, p_peak numeric DEFAULT 0.90)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT GREATEST(0.005, LEAST(COALESCE(p_peak,0.90),
    COALESCE(p_peak,0.90) * (CASE (((p_hour % 24)+24)%24)
      WHEN 0 THEN 0.03 WHEN 1 THEN 0.015 WHEN 2 THEN 0.008 WHEN 3 THEN 0.005 WHEN 4 THEN 0.06
      WHEN 5 THEN 0.28 WHEN 6 THEN 0.48 WHEN 7 THEN 0.72 WHEN 8 THEN 0.88 WHEN 9 THEN 0.95
      WHEN 10 THEN 0.96 WHEN 11 THEN 0.95 WHEN 12 THEN 0.93 WHEN 13 THEN 0.93 WHEN 14 THEN 0.94
      WHEN 15 THEN 0.96 WHEN 16 THEN 1.00 WHEN 17 THEN 1.00 WHEN 18 THEN 1.00 WHEN 19 THEN 0.94
      WHEN 20 THEN 0.82 WHEN 21 THEN 0.66 WHEN 22 THEN 0.30 WHEN 23 THEN 0.12 ELSE 0.6 END)));
$function$

-- ===== ottoq_depot_capacity =====
CREATE OR REPLACE FUNCTION public.ottoq_depot_capacity(p_seed bigint, p_fleet integer, p_window_h numeric DEFAULT 7.0, p_arrival_spread_h numeric DEFAULT 2.5, p_dcfc integer DEFAULT 10, p_l2 integer DEFAULT 20, p_wash integer DEFAULT 3, p_service integer DEFAULT 2, p_batt_kwh numeric DEFAULT 75, p_dcfc_kw numeric DEFAULT 150, p_l2_kw numeric DEFAULT 19.2, p_soc_lo integer DEFAULT 18, p_soc_hi integer DEFAULT 38, p_clean_min numeric DEFAULT 18, p_ext_prob numeric DEFAULT 0.5, p_ext_min numeric DEFAULT 9, p_inspect_min numeric DEFAULT 8, p_svc_prob numeric DEFAULT 0.12, p_svc_min numeric DEFAULT 45, p_slot_min integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_slots int := FLOOR(p_window_h*60/p_slot_min)::int;
  v_spread int := FLOOR(p_arrival_spread_h*60/p_slot_min)::int;
  v_dc int[]; v_l2 int[]; v_wa int[]; v_sv int[];
  v_kwh_dc numeric := p_dcfc_kw*p_slot_min/60.0; v_kwh_l2 numeric := p_l2_kw*p_slot_min/60.0;
  a_arr int[]; a_soc numeric[]; ord int[];
  v_arr int; v_soc numeric; v_need numeric; v_t int; v_ok boolean; v_len int;
  v_done int := 0; f_ch int := 0; f_cl int := 0; f_in int := 0;
  v_dcu int := 0; v_l2u int := 0; v_wau int := 0; v_svu int := 0;
  i int; idx int;
BEGIN
  v_dc := array_fill(p_dcfc, ARRAY[v_slots]); v_l2 := array_fill(p_l2, ARRAY[v_slots]);
  v_wa := array_fill(p_wash, ARRAY[v_slots]); v_sv := array_fill(p_service, ARRAY[v_slots]);
  a_arr := '{}'; a_soc := '{}';
  FOR i IN 1..p_fleet LOOP
    a_arr[i] := FLOOR(ottoq_sim_seeded_random(p_seed,'arr:'||i)*(v_spread+1))::int;
    a_soc[i] := p_soc_lo + ottoq_sim_seeded_random(p_seed,'soc:'||i)*(p_soc_hi-p_soc_lo);
  END LOOP;
  SELECT array_agg(t.i ORDER BY t.a, t.i) INTO ord FROM unnest(a_arr) WITH ORDINALITY AS t(a,i);

  FOREACH idx IN ARRAY ord LOOP
    v_arr := a_arr[idx]; v_soc := a_soc[idx]; v_t := v_arr + 1; v_ok := true;
    v_need := (100 - v_soc)/100.0 * p_batt_kwh;
    DECLARE n1 int := CEIL(v_need/v_kwh_l2)::int; n2 int := CEIL(v_need/v_kwh_dc)::int;
            got boolean := false; s int; k int; run int; want int;
    BEGIN
      FOR pass IN 1..2 LOOP
        CONTINUE WHEN got;
        want := CASE WHEN pass=1 THEN n1 ELSE n2 END;
        CONTINUE WHEN v_t + want - 1 > v_slots;
        s := v_t;
        WHILE s <= v_slots - want + 1 LOOP
          run := 0;
          WHILE run < want AND (CASE WHEN pass=1 THEN v_l2[s+run] ELSE v_dc[s+run] END) > 0 LOOP run := run+1; END LOOP;
          IF run >= want THEN
            FOR k IN s..(s+want-1) LOOP
              IF pass=1 THEN v_l2[k] := v_l2[k]-1; ELSE v_dc[k] := v_dc[k]-1; END IF; END LOOP;
            IF pass=1 THEN v_l2u := v_l2u+want; ELSE v_dcu := v_dcu+want; END IF;
            v_t := s+want; got := true; EXIT;
          END IF;
          s := s + GREATEST(1, run+1);
        END LOOP;
      END LOOP;
      IF NOT got THEN v_ok := false; f_ch := f_ch+1; END IF;
    END;
    IF v_ok THEN
      v_len := CEIL((p_clean_min + CASE WHEN ottoq_sim_seeded_random(p_seed,'ext:'||idx) < p_ext_prob THEN p_ext_min ELSE 0 END)/p_slot_min)::int;
      DECLARE got boolean := false; s int; k int; run int;
      BEGIN
        IF v_t + v_len - 1 <= v_slots THEN
          s := v_t;
          WHILE s <= v_slots - v_len + 1 LOOP
            run := 0; WHILE run < v_len AND v_wa[s+run] > 0 LOOP run := run+1; END LOOP;
            IF run >= v_len THEN
              FOR k IN s..(s+v_len-1) LOOP v_wa[k] := v_wa[k]-1; END LOOP;
              v_wau := v_wau+v_len; v_t := s+v_len; got := true; EXIT;
            END IF;
            s := s + GREATEST(1, run+1);
          END LOOP;
        END IF;
        IF NOT got THEN v_ok := false; f_cl := f_cl+1; END IF;
      END;
    END IF;
    IF v_ok THEN
      v_len := CEIL((p_inspect_min + CASE WHEN ottoq_sim_seeded_random(p_seed,'svc:'||idx) < p_svc_prob THEN p_svc_min ELSE 0 END)/p_slot_min)::int;
      DECLARE got boolean := false; s int; k int; run int;
      BEGIN
        IF v_t + v_len - 1 <= v_slots THEN
          s := v_t;
          WHILE s <= v_slots - v_len + 1 LOOP
            run := 0; WHILE run < v_len AND v_sv[s+run] > 0 LOOP run := run+1; END LOOP;
            IF run >= v_len THEN
              FOR k IN s..(s+v_len-1) LOOP v_sv[k] := v_sv[k]-1; END LOOP;
              v_svu := v_svu+v_len; v_t := s+v_len; got := true; EXIT;
            END IF;
            s := s + GREATEST(1, run+1);
          END LOOP;
        END IF;
        IF NOT got THEN v_ok := false; f_in := f_in+1; END IF;
      END;
    END IF;
    IF v_ok THEN v_done := v_done+1; END IF;
  END LOOP;

  RETURN jsonb_build_object('fleet',p_fleet,'completed',v_done,'all_ready',(v_done=p_fleet),
    'fail',jsonb_build_object('charge',f_ch,'clean',f_cl,'inspect',f_in),
    'util_pct',jsonb_build_object(
      'dcfc',ROUND(100.0*v_dcu/GREATEST(1,p_dcfc*v_slots),0),'l2',ROUND(100.0*v_l2u/GREATEST(1,p_l2*v_slots),0),
      'wash',ROUND(100.0*v_wau/GREATEST(1,p_wash*v_slots),0),'service',ROUND(100.0*v_svu/GREATEST(1,p_service*v_slots),0)));
END; $function$

-- ===== ottoq_depot_capacity_v2 =====
CREATE OR REPLACE FUNCTION public.ottoq_depot_capacity_v2(p_seed bigint, p_fleet integer, p_window_h numeric DEFAULT 7.0, p_arrival_spread_h numeric DEFAULT 2.5, p_dcfc integer DEFAULT 10, p_l2 integer DEFAULT 20, p_wash_lanes integer DEFAULT 2, p_techs integer DEFAULT 4, p_service_bays integer DEFAULT 2, p_batt_kwh numeric DEFAULT 75, p_dcfc_kw numeric DEFAULT 150, p_l2_kw numeric DEFAULT 19.2, p_soc_lo integer DEFAULT 18, p_soc_hi integer DEFAULT 38, p_interior_min numeric DEFAULT 4, p_inspect_min numeric DEFAULT 5, p_tech_overhead_min numeric DEFAULT 3, p_ext_min numeric DEFAULT 3, p_svc_prob numeric DEFAULT 0.12, p_svc_min numeric DEFAULT 45, p_slot_min integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_slots int := FLOOR(p_window_h*60/p_slot_min)::int;
  v_spread int := FLOOR(p_arrival_spread_h*60/p_slot_min)::int;
  v_dc int[]; v_l2 int[]; v_wa int[]; v_tk int[]; v_sv int[];
  v_kwh_dc numeric := p_dcfc_kw*p_slot_min/60.0; v_kwh_l2 numeric := p_l2_kw*p_slot_min/60.0;
  a_arr int[]; a_soc numeric[]; ord int[];
  n_tech int := GREATEST(1, CEIL((p_interior_min+p_inspect_min+p_tech_overhead_min)/p_slot_min)::int);
  n_ext  int := GREATEST(1, CEIL(p_ext_min/p_slot_min)::int);
  v_arr int; v_soc numeric; v_need numeric; v_ok boolean;
  v_cs int; v_ce int; v_cls text;      -- charge start/end/class
  v_done int := 0; f_ch int := 0; f_tk int := 0; f_ex int := 0; f_sv int := 0;
  u_dc int := 0; u_l2 int := 0; u_wa int := 0; u_tk int := 0; u_sv int := 0;
  i int; idx int; dcfc_forced int := 0;
BEGIN
  v_dc := array_fill(p_dcfc, ARRAY[v_slots]); v_l2 := array_fill(p_l2, ARRAY[v_slots]);
  v_wa := array_fill(p_wash_lanes, ARRAY[v_slots]); v_tk := array_fill(p_techs, ARRAY[v_slots]);
  v_sv := array_fill(p_service_bays, ARRAY[v_slots]);
  a_arr := '{}'; a_soc := '{}';
  FOR i IN 1..p_fleet LOOP
    a_arr[i] := FLOOR(ottoq_sim_seeded_random(p_seed,'arr:'||i)*(v_spread+1))::int;
    a_soc[i] := p_soc_lo + ottoq_sim_seeded_random(p_seed,'soc:'||i)*(p_soc_hi-p_soc_lo);
  END LOOP;
  SELECT array_agg(t.i ORDER BY t.a, t.i) INTO ord FROM unnest(a_arr) WITH ORDINALITY AS t(a,i);

  FOREACH idx IN ARRAY ord LOOP
    v_arr := a_arr[idx]; v_soc := a_soc[idx]; v_ok := true;
    v_need := (100 - v_soc)/100.0 * p_batt_kwh;
    v_cs := NULL; v_ce := NULL; v_cls := NULL;

    -- STAGE 1 + CHAIN-AWARE CLASS SELECTION -------------------------------------------
    DECLARE n1 int := CEIL(v_need/v_kwh_l2)::int; n2 int := CEIL(v_need/v_kwh_dc)::int;
            need_svc boolean := ottoq_sim_seeded_random(p_seed,'svc:'||idx) < p_svc_prob;
            tail int; s int; k int; run int; want int; got boolean := false;
    BEGIN
      tail := n_ext + CASE WHEN need_svc THEN CEIL(p_svc_min/p_slot_min)::int ELSE 0 END;
      FOR pass IN 1..2 LOOP        -- pass 1 = L2 (cheap), pass 2 = DCFC (fast, time-buying)
        CONTINUE WHEN got;
        want := CASE WHEN pass=1 THEN n1 ELSE n2 END;
        -- chain-aware: only take this class if charge + downstream tail still fits the night
        CONTINUE WHEN (v_arr + 1) + want - 1 + tail > v_slots;
        s := v_arr + 1;
        WHILE s <= v_slots - want + 1 - tail LOOP
          run := 0;
          WHILE run < want AND (CASE WHEN pass=1 THEN v_l2[s+run] ELSE v_dc[s+run] END) > 0 LOOP run := run+1; END LOOP;
          IF run >= want THEN
            -- require a tech window INSIDE this charge block (clean+inspect run in parallel)
            DECLARE ts int := s; tfound boolean := false; r2 int; k2 int;
            BEGIN
              WHILE ts <= s + want - n_tech LOOP
                r2 := 0;
                WHILE r2 < n_tech AND v_tk[ts+r2] > 0 LOOP r2 := r2+1; END LOOP;
                IF r2 >= n_tech THEN
                  FOR k2 IN ts..(ts+n_tech-1) LOOP v_tk[k2] := v_tk[k2]-1; END LOOP;
                  u_tk := u_tk + n_tech; tfound := true; EXIT;
                END IF;
                ts := ts + GREATEST(1, r2+1);
              END LOOP;
              IF tfound THEN
                FOR k IN s..(s+want-1) LOOP
                  IF pass=1 THEN v_l2[k] := v_l2[k]-1; ELSE v_dc[k] := v_dc[k]-1; END IF; END LOOP;
                IF pass=1 THEN u_l2 := u_l2+want; ELSE u_dc := u_dc+want; dcfc_forced := dcfc_forced+1; END IF;
                v_cs := s; v_ce := s+want; v_cls := CASE WHEN pass=1 THEN 'l2' ELSE 'dcfc' END;
                got := true;
              END IF;
            END;
          END IF;
          EXIT WHEN got;
          s := s + GREATEST(1, run+1);
        END LOOP;
      END LOOP;
      IF NOT got THEN v_ok := false; f_ch := f_ch+1; END IF;
    END;

    -- STAGE 2: pull-through exterior rinse (quick lane) --------------------------------
    IF v_ok THEN
      DECLARE s int := v_ce; got boolean := false; k int; run int;
      BEGIN
        WHILE s <= v_slots - n_ext + 1 LOOP
          run := 0; WHILE run < n_ext AND v_wa[s+run] > 0 LOOP run := run+1; END LOOP;
          IF run >= n_ext THEN
            FOR k IN s..(s+n_ext-1) LOOP v_wa[k] := v_wa[k]-1; END LOOP;
            u_wa := u_wa+n_ext; v_ce := s+n_ext; got := true; EXIT;
          END IF;
          s := s + GREATEST(1, run+1);
        END LOOP;
        IF NOT got THEN v_ok := false; f_ex := f_ex+1; END IF;
      END;
    END IF;

    -- STAGE 3: Monte-Carlo deeper service (service bay) ---------------------------------
    IF v_ok AND ottoq_sim_seeded_random(p_seed,'svc:'||idx) < p_svc_prob THEN
      DECLARE n3 int := CEIL(p_svc_min/p_slot_min)::int; s int := v_ce; got boolean := false; k int; run int;
      BEGIN
        WHILE s <= v_slots - n3 + 1 LOOP
          run := 0; WHILE run < n3 AND v_sv[s+run] > 0 LOOP run := run+1; END LOOP;
          IF run >= n3 THEN
            FOR k IN s..(s+n3-1) LOOP v_sv[k] := v_sv[k]-1; END LOOP;
            u_sv := u_sv+n3; got := true; EXIT;
          END IF;
          s := s + GREATEST(1, run+1);
        END LOOP;
        IF NOT got THEN v_ok := false; f_sv := f_sv+1; END IF;
      END;
    END IF;

    IF v_ok THEN v_done := v_done+1; END IF;
  END LOOP;

  RETURN jsonb_build_object('fleet',p_fleet,'completed',v_done,'all_ready',(v_done=p_fleet),
    'dcfc_forced_by_time', dcfc_forced,
    'fail',jsonb_build_object('charge_or_tech',f_ch,'exterior',f_ex,'service_bay',f_sv),
    'util_pct',jsonb_build_object(
      'dcfc',ROUND(100.0*u_dc/GREATEST(1,p_dcfc*v_slots),0),'l2',ROUND(100.0*u_l2/GREATEST(1,p_l2*v_slots),0),
      'wash_lane',ROUND(100.0*u_wa/GREATEST(1,p_wash_lanes*v_slots),0),
      'techs',ROUND(100.0*u_tk/GREATEST(1,p_techs*v_slots),0),
      'service_bay',ROUND(100.0*u_sv/GREATEST(1,p_service_bays*v_slots),0)));
END; $function$

-- ===== ottoq_depot_capacity_v3 =====
CREATE OR REPLACE FUNCTION public.ottoq_depot_capacity_v3(p_seed bigint, p_fleet integer, p_window_h numeric DEFAULT 7.0, p_arrival_spread_h numeric DEFAULT 2.5, p_dcfc integer DEFAULT 10, p_l2 integer DEFAULT 20, p_wash_lanes integer DEFAULT 2, p_techs integer DEFAULT 6, p_service_bays integer DEFAULT 2, p_batt_kwh numeric DEFAULT 75, p_dcfc_kw numeric DEFAULT 150, p_l2_kw numeric DEFAULT 19.2, p_soc_lo integer DEFAULT 18, p_soc_hi integer DEFAULT 38, p_tech_touch_min numeric DEFAULT 9, p_ext_prob numeric DEFAULT 0.33, p_ext_min numeric DEFAULT 3, p_svc_prob numeric DEFAULT 0.12, p_svc_min numeric DEFAULT 45, p_slot_min integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_slots int := FLOOR(p_window_h*60/p_slot_min)::int;
  v_spread int := FLOOR(p_arrival_spread_h*60/p_slot_min)::int;
  v_dc int[]; v_l2 int[]; v_wa int[]; v_tk int[]; v_sv int[];
  v_kwh_dc numeric := p_dcfc_kw*p_slot_min/60.0; v_kwh_l2 numeric := p_l2_kw*p_slot_min/60.0;
  a_arr int[]; a_soc numeric[]; ord int[];
  n_tech int := GREATEST(1, CEIL(p_tech_touch_min/p_slot_min)::int);
  n_ext  int := GREATEST(1, CEIL(p_ext_min/p_slot_min)::int);
  n_svc  int := GREATEST(1, CEIL(p_svc_min/p_slot_min)::int);
  v_arr int; v_soc numeric; v_need numeric; v_ok boolean; v_ce int;
  v_done int := 0; f_ch int := 0; f_ex int := 0; f_sv int := 0;
  u_dc int := 0; u_l2 int := 0; u_wa int := 0; u_tk int := 0; u_sv int := 0;
  dcfc_forced int := 0; i int; idx int;
  dc_cycle numeric; l2_cycle numeric;
BEGIN
  v_dc := array_fill(p_dcfc, ARRAY[v_slots]); v_l2 := array_fill(p_l2, ARRAY[v_slots]);
  v_wa := array_fill(p_wash_lanes, ARRAY[v_slots]); v_tk := array_fill(p_techs, ARRAY[v_slots]);
  v_sv := array_fill(p_service_bays, ARRAY[v_slots]);
  a_arr := '{}'; a_soc := '{}';
  FOR i IN 1..p_fleet LOOP
    a_arr[i] := FLOOR(ottoq_sim_seeded_random(p_seed,'arr:'||i)*(v_spread+1))::int;
    a_soc[i] := p_soc_lo + ottoq_sim_seeded_random(p_seed,'soc:'||i)*(p_soc_hi-p_soc_lo);
  END LOOP;
  SELECT array_agg(t.i ORDER BY t.a, t.i) INTO ord FROM unnest(a_arr) WITH ORDINALITY AS t(a,i);

  FOREACH idx IN ARRAY ord LOOP
    v_arr := a_arr[idx]; v_soc := a_soc[idx]; v_ok := true; v_ce := NULL;
    v_need := (100 - v_soc)/100.0 * p_batt_kwh;
    DECLARE n1 int := CEIL(v_need/v_kwh_l2)::int; n2 int := CEIL(v_need/v_kwh_dc)::int;
            wants_ext boolean := ottoq_sim_seeded_random(p_seed,'ext:'||idx) < p_ext_prob;
            wants_svc boolean := ottoq_sim_seeded_random(p_seed,'svc:'||idx) < p_svc_prob;
            tail int; s int; k int; run int; want int; got boolean := false;
    BEGIN
      tail := (CASE WHEN wants_ext THEN n_ext ELSE 0 END) + (CASE WHEN wants_svc THEN n_svc ELSE 0 END);
      FOR pass IN 1..2 LOOP
        CONTINUE WHEN got;
        want := CASE WHEN pass=1 THEN n1 ELSE n2 END;
        CONTINUE WHEN (v_arr+1) + want - 1 + tail > v_slots;
        s := v_arr + 1;
        WHILE s <= v_slots - want + 1 - tail LOOP
          run := 0;
          WHILE run < want AND (CASE WHEN pass=1 THEN v_l2[s+run] ELSE v_dc[s+run] END) > 0 LOOP run := run+1; END LOOP;
          IF run >= want THEN
            DECLARE ts int := s; tf boolean := false; r2 int; k2 int; hi int;
            BEGIN
              hi := GREATEST(s, s + want - n_tech);
              WHILE ts <= hi LOOP
                r2 := 0;
                WHILE r2 < n_tech AND (ts+r2) <= v_slots AND v_tk[ts+r2] > 0 LOOP r2 := r2+1; END LOOP;
                IF r2 >= n_tech THEN
                  FOR k2 IN ts..(ts+n_tech-1) LOOP v_tk[k2] := v_tk[k2]-1; END LOOP;
                  u_tk := u_tk + n_tech; tf := true; EXIT;
                END IF;
                ts := ts + GREATEST(1, r2+1);
              END LOOP;
              IF tf THEN
                FOR k IN s..(s+want-1) LOOP
                  IF pass=1 THEN v_l2[k] := v_l2[k]-1; ELSE v_dc[k] := v_dc[k]-1; END IF; END LOOP;
                IF pass=1 THEN u_l2 := u_l2+want; ELSE u_dc := u_dc+want; dcfc_forced := dcfc_forced+1; END IF;
                v_ce := s+want; got := true;
              END IF;
            END;
          END IF;
          EXIT WHEN got;
          s := s + GREATEST(1, run+1);
        END LOOP;
      END LOOP;
      IF NOT got THEN v_ok := false; f_ch := f_ch+1; END IF;

      IF v_ok AND wants_ext THEN
        DECLARE s2 int := v_ce; g2 boolean := false; k int; run2 int;
        BEGIN
          WHILE s2 <= v_slots - n_ext + 1 LOOP
            run2 := 0; WHILE run2 < n_ext AND v_wa[s2+run2] > 0 LOOP run2 := run2+1; END LOOP;
            IF run2 >= n_ext THEN
              FOR k IN s2..(s2+n_ext-1) LOOP v_wa[k] := v_wa[k]-1; END LOOP;
              u_wa := u_wa+n_ext; v_ce := s2+n_ext; g2 := true; EXIT;
            END IF;
            s2 := s2 + GREATEST(1, run2+1);
          END LOOP;
          IF NOT g2 THEN v_ok := false; f_ex := f_ex+1; END IF;
        END;
      END IF;

      IF v_ok AND wants_svc THEN
        DECLARE s3 int := v_ce; g3 boolean := false; k int; run3 int;
        BEGIN
          WHILE s3 <= v_slots - n_svc + 1 LOOP
            run3 := 0; WHILE run3 < n_svc AND v_sv[s3+run3] > 0 LOOP run3 := run3+1; END LOOP;
            IF run3 >= n_svc THEN
              FOR k IN s3..(s3+n_svc-1) LOOP v_sv[k] := v_sv[k]-1; END LOOP;
              u_sv := u_sv+n_svc; g3 := true; EXIT;
            END IF;
            s3 := s3 + GREATEST(1, run3+1);
          END LOOP;
          IF NOT g3 THEN v_ok := false; f_sv := f_sv+1; END IF;
        END;
      END IF;
    END;
    IF v_ok THEN v_done := v_done+1; END IF;
  END LOOP;

  -- zone staffing guidance (analytic): stalls one tech can cover = zone cycle time / tech touch
  dc_cycle := (( (100 - (p_soc_lo+p_soc_hi)/2.0)/100.0*p_batt_kwh) / p_dcfc_kw)*60.0;
  l2_cycle := (( (100 - (p_soc_lo+p_soc_hi)/2.0)/100.0*p_batt_kwh) / p_l2_kw)*60.0;
  RETURN jsonb_build_object('fleet',p_fleet,'completed',v_done,'all_ready',(v_done=p_fleet),
    'dcfc_forced_by_time',dcfc_forced,
    'fail',jsonb_build_object('charge_or_tech',f_ch,'exterior',f_ex,'service_bay',f_sv),
    'util_pct',jsonb_build_object('dcfc',ROUND(100.0*u_dc/GREATEST(1,p_dcfc*v_slots),0),
      'l2',ROUND(100.0*u_l2/GREATEST(1,p_l2*v_slots),0),
      'wash_lane',ROUND(100.0*u_wa/GREATEST(1,p_wash_lanes*v_slots),0),
      'techs',ROUND(100.0*u_tk/GREATEST(1,p_techs*v_slots),0),
      'service_bay',ROUND(100.0*u_sv/GREATEST(1,p_service_bays*v_slots),0)),
    'zone_staffing',jsonb_build_object(
      'dcfc_cycle_min',ROUND(dc_cycle,0),'l2_cycle_min',ROUND(l2_cycle,0),
      'stalls_per_tech_dcfc',ROUND(dc_cycle/p_tech_touch_min,1),
      'stalls_per_tech_l2',ROUND(l2_cycle/p_tech_touch_min,1),
      'techs_needed', CEIL(p_dcfc/GREATEST(0.5,dc_cycle/p_tech_touch_min)) + CEIL(p_l2/GREATEST(0.5,l2_cycle/p_tech_touch_min))));
END; $function$

-- ===== ottoq_depot_cards =====
CREATE OR REPLACE FUNCTION public.ottoq_depot_cards(p_depot_id uuid, p_fleet_operator_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
WITH run AS (
  SELECT sim_run_id, sim_clock_current, status AS run_status
  FROM ottoq_sim_runs
  WHERE depot_id = p_depot_id
    AND status IN ('running','paused')
  ORDER BY started_at DESC
  LIMIT 1
),
veh AS (
  SELECT v.id, v.display_name, v.make, v.model,
         v.fleet_operator_id, f.name AS operator_name,
         v.current_state::text AS state, v.current_soc, v.target_soc
  FROM vehicles v
  LEFT JOIN fleet_operators f ON f.id = v.fleet_operator_id
  WHERE v.current_depot_id = p_depot_id
    AND (p_fleet_operator_id IS NULL OR v.fleet_operator_id = p_fleet_operator_id)
),
card AS (
  SELECT vh.id AS vehicle_id,
         (SELECT to_jsonb(n) - 'meta'
            FROM ottoq_visit_needs n
           WHERE n.vehicle_id = vh.id AND n.sim_run_id = r.sim_run_id
           ORDER BY n.created_at DESC LIMIT 1)               AS need,
         (SELECT i.itinerary_id
            FROM ottoq_vehicle_itineraries i
           WHERE i.vehicle_id = vh.id AND i.sim_run_id = r.sim_run_id
             AND i.status = 'active'
           ORDER BY i.sim_created_at DESC LIMIT 1)           AS itinerary_id
  FROM veh vh CROSS JOIN run r
),
seq AS (
  SELECT c.vehicle_id,
         jsonb_agg(s.step ORDER BY s.ord) AS steps
  FROM card c
  CROSS JOIN LATERAL (
    (SELECT l.seq AS ord, jsonb_build_object(
        'seq', l.seq, 'leg_type', l.leg_type, 'status', 'done',
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim,
        'actual_start', l.actual_start_sim,  'actual_end', l.actual_end_sim) AS step
       FROM ottoq_itinerary_legs l
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'done'
      ORDER BY l.seq DESC LIMIT 3)
    UNION ALL
    (SELECT l.seq, jsonb_build_object(
        'seq', l.seq, 'leg_type', l.leg_type, 'status', 'current',
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim,
        'actual_start', l.actual_start_sim,
        'progress_pct', LEAST(100, GREATEST(0, round(
           100.0 * EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.actual_start_sim))
                 / NULLIF(l.planned_duration_s,0)))))
       FROM ottoq_itinerary_legs l
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'active'
      ORDER BY l.seq LIMIT 1)
    UNION ALL
    (SELECT l.seq, jsonb_build_object(
        'seq', l.seq, 'leg_type', l.leg_type, 'status', 'upcoming',
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim)
       FROM ottoq_itinerary_legs l
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'planned'
      ORDER BY l.seq LIMIT 5)
  ) s(ord, step)
  WHERE c.itinerary_id IS NOT NULL
  GROUP BY c.vehicle_id
)
SELECT jsonb_build_object(
  'endpoint', 'ottoq.depot_cards',
  'contract_version', '1.0',
  'depot_id', p_depot_id,
  'fleet_operator_id', p_fleet_operator_id,
  'sim_run_id', (SELECT sim_run_id FROM run),
  'run_status', (SELECT run_status FROM run),
  'sim_clock',  (SELECT sim_clock_current FROM run),
  'vehicles', COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
       'vehicle_id', vh.id,
       'display_name', vh.display_name,
       'oem', vh.make, 'model', vh.model,
       'operator', jsonb_build_object('id', vh.fleet_operator_id, 'name', vh.operator_name),
       'state', vh.state, 'soc', vh.current_soc, 'target_soc', vh.target_soc,
       'card', CASE WHEN (SELECT sim_run_id FROM run) IS NULL THEN NULL ELSE jsonb_build_object(
          'urgency',         c.need->>'urgency',
          'dispatch_due_at', c.need->>'dispatch_due_at',
          'needs',           COALESCE((
                               SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                                 'svc', a->>'svc', 'status', a->>'status',
                                 'done_at', a->>'done_at', 'must_do', (a->>'must_do')::boolean)))
                               FROM jsonb_array_elements(c.need->'atoms') a), '[]'::jsonb),
          'steps',           COALESCE(s.steps,'[]'::jsonb),
          'current_step',    (SELECT st FROM jsonb_array_elements(COALESCE(s.steps,'[]'::jsonb)) st
                               WHERE st->>'status'='current' LIMIT 1),
          'next_step',       (SELECT st FROM jsonb_array_elements(COALESCE(s.steps,'[]'::jsonb)) st
                               WHERE st->>'status'='upcoming' LIMIT 1)
       ) END
     ) ORDER BY vh.display_name)
     FROM veh vh
     LEFT JOIN card c ON c.vehicle_id = vh.id
     LEFT JOIN seq  s ON s.vehicle_id = vh.id
  ), '[]'::jsonb)
);
$function$

-- ===== ottoq_depot_current_demand_kw =====
CREATE OR REPLACE FUNCTION public.ottoq_depot_current_demand_kw(p_depot_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT ottoq_sim_compute_charger_load_kw(p_depot_id, now());
$function$

-- ===== ottoq_depot_current_demand_kw =====
CREATE OR REPLACE FUNCTION public.ottoq_depot_current_demand_kw(p_depot_id uuid, p_now timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT ottoq_sim_compute_charger_load_kw(p_depot_id, COALESCE(p_now, now()));
$function$

-- ===== ottoq_depot_local_time =====
CREATE OR REPLACE FUNCTION public.ottoq_depot_local_time(p_depot_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_tz TEXT;
BEGIN
  SELECT operating_timezone INTO v_tz FROM depots WHERE id = p_depot_id;
  v_tz := COALESCE(v_tz, 'UTC');
  RETURN (NOW() AT TIME ZONE v_tz);
END;
$function$

-- ===== ottoq_depot_running_run =====
CREATE OR REPLACE FUNCTION public.ottoq_depot_running_run(p_depot_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT sim_run_id FROM ottoq_sim_runs
   WHERE depot_id = p_depot_id AND status = 'running'
   ORDER BY started_at DESC LIMIT 1;
$function$

-- ===== ottoq_depot_staffing_count =====
CREATE OR REPLACE FUNCTION public.ottoq_depot_staffing_count(p_depot_id uuid, p_role text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE((SELECT headcount FROM ottoq_depot_staffing
                    WHERE depot_id = p_depot_id AND role = p_role),
                  CASE p_role WHEN 'general_tech' THEN 10
                              WHEN 'wash_supervisor' THEN 2
                              WHEN 'service_tech' THEN 3 ELSE 1 END);
$function$

-- ===== ottoq_dispatch_bump_wash_cycle =====
CREATE OR REPLACE FUNCTION public.ottoq_dispatch_bump_wash_cycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  -- boot-prime inserts are not deploy cycles (prime sets this GUC for its txn)
  IF current_setting('ottoq.skip_wash_bump', true) = '1' THEN RETURN NEW; END IF;
  UPDATE vehicles
     SET config = jsonb_set(COALESCE(config,'{}'::jsonb), '{cycles_since_wash}',
                            to_jsonb(COALESCE((config->>'cycles_since_wash')::int, 0) + 1))
   WHERE id = NEW.vehicle_id
     AND config ? 'wash_cadence_cycles';
  RETURN NEW;
END;
$function$

-- ===== ottoq_dtc_severity_rank =====
CREATE OR REPLACE FUNCTION public.ottoq_dtc_severity_rank(p_sev text)
 RETURNS smallint
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT CASE lower(coalesce(p_sev,''))
           WHEN 'safety_critical' THEN 0
           WHEN 'major'           THEN 1
           WHEN 'moderate'        THEN 2
           WHEN 'minor'           THEN 3
           WHEN 'info'            THEN 4
           ELSE 99 END::smallint;
$function$

-- ===== ottoq_effective_deploy_floor =====
CREATE OR REPLACE FUNCTION public.ottoq_effective_deploy_floor(p_vehicle_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT ottoq_effective_deploy_floor_at(p_vehicle_id, now());
$function$

-- ===== ottoq_effective_deploy_floor_at =====
CREATE OR REPLACE FUNCTION public.ottoq_effective_deploy_floor_at(p_vehicle_id uuid, p_as_of timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE(
    (SELECT s.min_soc_at_deployment_pct FROM ottoq_fleet_operator_slas s
      WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status='active'
        AND s.effective_from <= p_as_of
        AND (s.effective_until IS NULL OR s.effective_until > p_as_of)
      ORDER BY s.version DESC LIMIT 1), 80)
  FROM vehicles v WHERE v.id = p_vehicle_id;
$function$

-- ===== ottoq_effective_reserve_soc =====
CREATE OR REPLACE FUNCTION public.ottoq_effective_reserve_soc(p_vehicle_id uuid, p_as_of timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT GREATEST(
    COALESCE(
      (SELECT s.return_reserve_soc_pct FROM ottoq_fleet_operator_slas s
        WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status='active'
          AND s.effective_from <= p_as_of
          AND (s.effective_until IS NULL OR s.effective_until > p_as_of)
        ORDER BY s.version DESC LIMIT 1),
      v.min_soc_threshold, 20),
    COALESCE(v.min_soc_threshold, 20)
  )
  FROM vehicles v WHERE v.id = p_vehicle_id;
$function$

-- ===== ottoq_effective_target_soc =====
CREATE OR REPLACE FUNCTION public.ottoq_effective_target_soc(p_vehicle_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT ottoq_effective_target_soc_at(p_vehicle_id, now());
$function$

-- ===== ottoq_effective_target_soc_at =====
CREATE OR REPLACE FUNCTION public.ottoq_effective_target_soc_at(p_vehicle_id uuid, p_as_of timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE(
    v.target_soc,
    (SELECT s.preferred_soc_at_deployment_pct FROM ottoq_fleet_operator_slas s
      WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status='active'
        AND s.effective_from <= p_as_of
        AND (s.effective_until IS NULL OR s.effective_until > p_as_of)
      ORDER BY s.version DESC LIMIT 1), 90)
  FROM vehicles v WHERE v.id = p_vehicle_id;
$function$

-- ===== ottoq_emergency_clear =====
CREATE OR REPLACE FUNCTION public.ottoq_emergency_clear(p_invocation_id uuid, p_cleared_by_actor_type text, p_cleared_by_actor_id text, p_resolution_note text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_inv ottoq_emergency_invocations%ROWTYPE;
  v_protocol ottoq_emergency_protocols%ROWTYPE;
BEGIN
  IF p_resolution_note IS NULL OR length(trim(p_resolution_note)) < 5 THEN
    RAISE EXCEPTION 'resolution_note must be ≥ 5 chars' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_inv FROM ottoq_emergency_invocations WHERE invocation_id = p_invocation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invocation % not found', p_invocation_id;
  END IF;
  IF v_inv.cleared_at IS NOT NULL THEN
    RAISE EXCEPTION 'invocation % already cleared at %', p_invocation_id, v_inv.cleared_at;
  END IF;

  SELECT * INTO v_protocol FROM ottoq_emergency_protocols WHERE protocol_code = v_inv.protocol_code;

  UPDATE ottoq_emergency_invocations
     SET cleared_at           = NOW(),
         cleared_by_actor_type = p_cleared_by_actor_type,
         cleared_by_actor_id   = p_cleared_by_actor_id,
         resolution_note       = p_resolution_note,
         outcome               = 'cleared'
   WHERE invocation_id = p_invocation_id;

  -- Clear any arrival_pause records tied to this invocation
  UPDATE ottoq_grid_events
     SET cleared_at = NOW()
   WHERE depot_id = v_inv.depot_id
     AND payload @> jsonb_build_object('invocation_id', p_invocation_id::text)
     AND cleared_at IS NULL;

  PERFORM ottoq_record_event(
    p_actor_type    := p_cleared_by_actor_type,
    p_actor_id      := p_cleared_by_actor_id,
    p_event_type    := 'emergency.cleared',
    p_entity_type   := 'emergency_invocation',
    p_entity_id     := p_invocation_id,
    p_depot_id      := v_inv.depot_id,
    p_payload       := jsonb_build_object(
                         'protocol_code', v_inv.protocol_code,
                         'resolution_note', p_resolution_note,
                         'duration_seconds', EXTRACT(EPOCH FROM (NOW() - v_inv.triggered_at))
                       ),
    p_severity      := 'warning'
  );

  RETURN TRUE;
END;
$function$

-- ===== ottoq_emit_recommendation =====
CREATE OR REPLACE FUNCTION public.ottoq_emit_recommendation(p_proposed_action text, p_prediction_id uuid DEFAULT NULL::uuid, p_prediction_type text DEFAULT NULL::text, p_action_parameters jsonb DEFAULT '{}'::jsonb, p_entity_type text DEFAULT 'system'::text, p_entity_id uuid DEFAULT NULL::uuid, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_shadow_only boolean DEFAULT false, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid, p_expires_in_seconds integer DEFAULT 300)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec_id           UUID := gen_random_uuid();
  v_correlation      UUID;
  v_event_id         UUID;
  v_eval_rows        JSONB := '[]'::jsonb;
  v_blocked_rules    TEXT[] := '{}'::text[];
  v_eval_record      RECORD;
  v_admitted         BOOLEAN := TRUE;
  v_decision_reason  TEXT;
BEGIN
  v_correlation := COALESCE(p_correlation_id,
    NULLIF(current_setting('ottoq.correlation_id', TRUE), '')::UUID,
    gen_random_uuid()
  );

  -- 1. Record initial 'pending' row
  INSERT INTO ottoq_recommendations (
    recommendation_id, emitted_at,
    prediction_id, prediction_type,
    proposed_action, action_parameters,
    entity_type, entity_id, fleet_operator_id, depot_id,
    status, shadow_only,
    expires_at, correlation_id, parent_event_id
  ) VALUES (
    v_rec_id, NOW(),
    p_prediction_id, p_prediction_type,
    p_proposed_action, p_action_parameters,
    p_entity_type, p_entity_id, p_fleet_operator_id, p_depot_id,
    CASE WHEN p_shadow_only THEN 'shadow' ELSE 'validating' END,
    p_shadow_only,
    NOW() + (p_expires_in_seconds || ' seconds')::INTERVAL,
    v_correlation, p_parent_event_id
  );

  -- 2. Run Layer 1 rules for this proposed action
  --    Use SAVEPOINT so a blocking rule's RAISE doesn't kill our transaction
  BEGIN
    FOR v_eval_record IN
      SELECT * FROM ottoq_evaluate_rules_for_action(
        p_action_context        := p_proposed_action,
        p_entity_type           := p_entity_type,
        p_entity_id             := p_entity_id,
        p_context               := p_action_parameters,
        p_fleet_operator_id     := p_fleet_operator_id,
        p_depot_id              := p_depot_id,
        p_triggered_by_event_id := p_parent_event_id
      )
    LOOP
      v_eval_rows := v_eval_rows || jsonb_build_object(
        'rule_code', v_eval_record.rule_code,
        'passed', v_eval_record.passed,
        'reason', v_eval_record.reason,
        'enforcement_taken', v_eval_record.enforcement_taken,
        'evaluation_id', v_eval_record.evaluation_id
      );
      IF NOT v_eval_record.passed AND v_eval_record.enforcement_taken = 'blocked' THEN
        v_blocked_rules := array_append(v_blocked_rules, v_eval_record.rule_code);
        v_admitted := FALSE;
      END IF;
    END LOOP;
  EXCEPTION WHEN sqlstate 'P0001' THEN
    -- Layer 1 blocking rule raised. Capture and continue.
    IF SQLERRM LIKE 'OTTOQ_RULE_BLOCKED:%' THEN
      v_admitted := FALSE;
      v_decision_reason := SQLERRM;
      -- The blocked rule_code is in the message; we capture generically
      v_blocked_rules := array_append(v_blocked_rules, 'see_decision_reason');
    ELSE
      RAISE;
    END IF;
  END;

  -- 3. Finalize status
  IF p_shadow_only THEN
    v_decision_reason := 'shadow mode: not actuated';
    UPDATE ottoq_recommendations
       SET decided_at = NOW(),
           rules_evaluated = v_eval_rows,
           rules_blocked_by = v_blocked_rules,
           status = 'shadow',
           decision_reason = v_decision_reason
     WHERE recommendation_id = v_rec_id;
  ELSIF v_admitted THEN
    UPDATE ottoq_recommendations
       SET decided_at = NOW(),
           rules_evaluated = v_eval_rows,
           rules_blocked_by = v_blocked_rules,
           status = 'admitted',
           decision_reason = 'all_rules_passed'
     WHERE recommendation_id = v_rec_id;
  ELSE
    UPDATE ottoq_recommendations
       SET decided_at = NOW(),
           rules_evaluated = v_eval_rows,
           rules_blocked_by = v_blocked_rules,
           status = 'rejected',
           decision_reason = COALESCE(v_decision_reason, 'blocked_by_rules: ' || array_to_string(v_blocked_rules, ','))
     WHERE recommendation_id = v_rec_id;
  END IF;

  -- 4. Emit Layer-1 event
  v_event_id := ottoq_record_event(
    p_actor_type        := 'ottoq_engine',
    p_event_type        := CASE
                            WHEN p_shadow_only THEN 'recommendation.shadow'
                            WHEN v_admitted THEN 'recommendation.admitted'
                            ELSE 'recommendation.rejected'
                          END,
    p_entity_type       := 'recommendation',
    p_entity_id         := v_rec_id,
    p_fleet_operator_id := p_fleet_operator_id,
    p_depot_id          := p_depot_id,
    p_payload           := jsonb_build_object(
                            'prediction_id', p_prediction_id,
                            'prediction_type', p_prediction_type,
                            'proposed_action', p_proposed_action,
                            'action_parameters', p_action_parameters,
                            'rules_evaluated', v_eval_rows,
                            'rules_blocked_by', v_blocked_rules,
                            'shadow_only', p_shadow_only
                          ),
    p_severity          := CASE WHEN v_admitted OR p_shadow_only THEN 'info' ELSE 'warning' END,
    p_correlation_id    := v_correlation,
    p_parent_event_id   := p_parent_event_id
  );

  RETURN v_rec_id;
END;
$function$

-- ===== ottoq_energy_cost_for_run =====
CREATE OR REPLACE FUNCTION public.ottoq_energy_cost_for_run(p_sim_run_id uuid, p_demand_charge_per_kw numeric DEFAULT NULL::numeric)
 RETURNS TABLE(peak_kw numeric, demand_charge_usd_month numeric, energy_kwh numeric, energy_cost_usd numeric, avg_rate_per_kwh numeric, snapshots integer)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_start timestamptz; v_end timestamptz; v_tick_hours numeric;
  v_has_tagged boolean; v_rate numeric; v_sim_clock timestamptz;
BEGIN
  SELECT depot_id, started_at, COALESCE(ended_at, now()),
         (tick_interval_seconds::numeric * COALESCE(time_scale,1))/3600.0,
         COALESCE(sim_clock_current, started_at)
    INTO v_depot, v_start, v_end, v_tick_hours, v_sim_clock
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN; END IF;

  v_rate := COALESCE(p_demand_charge_per_kw, ottoq_demand_charge_per_kw(v_depot, v_sim_clock));

  SELECT EXISTS(SELECT 1 FROM site_energy_snapshots WHERE sim_run_id = p_sim_run_id)
    INTO v_has_tagged;

  RETURN QUERY
  WITH snaps AS (
    SELECT peak_demand_kw_15min AS peak, GREATEST(grid_import_kw,0) AS imp,
           COALESCE(current_rate_per_kwh,0.12) AS rate
      FROM site_energy_snapshots
     WHERE CASE WHEN v_has_tagged
                THEN sim_run_id = p_sim_run_id
                ELSE depot_id = v_depot AND created_at >= v_start AND created_at <= v_end
           END
  )
  SELECT
    ROUND(COALESCE(MAX(peak),0),0),
    ROUND(COALESCE(MAX(peak),0) * v_rate, 0),
    ROUND(COALESCE(SUM(imp * v_tick_hours),0),1),
    ROUND(COALESCE(SUM(imp * v_tick_hours * rate),0),2),
    ROUND(COALESCE(AVG(rate),0),3),
    COUNT(*)::int
  FROM snaps;
END;
$function$

-- ===== ottoq_energy_mpc_ingest =====
CREATE OR REPLACE FUNCTION public.ottoq_energy_mpc_ingest(p_plan_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_plan RECORD; v_status int; v_content text; v_err text;
  v_setpoints numeric[]; v_grid numeric[]; v_peak numeric; v_solver text; v_optstatus text; v_resp jsonb;
BEGIN
  SELECT * INTO v_plan FROM ottoq_energy_plan WHERE id = p_plan_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','no_such_plan'); END IF;
  IF v_plan.plan_state <> 'pending' THEN
    RETURN jsonb_build_object('ok', v_plan.plan_state='ready', 'plan_state', v_plan.plan_state,
      'plan_id', p_plan_id, 'predicted_peak_kw', round(v_plan.predicted_peak_kw,1));
  END IF;

  SELECT r.status_code, r.content, r.error_msg INTO v_status, v_content, v_err
    FROM net._http_response r WHERE r.id = v_plan.request_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',true,'plan_state','pending','plan_id',p_plan_id); END IF;

  IF v_status IS DISTINCT FROM 200 OR v_content IS NULL OR v_content !~ '^[{\[]' THEN
    UPDATE ottoq_energy_plan SET plan_state='failed', status=coalesce('http_'||v_status, 'error') WHERE id=p_plan_id;
    RETURN jsonb_build_object('ok',false,'plan_state','failed','status',v_status,'err',left(coalesce(v_err,v_content),160));
  END IF;

  v_resp := v_content::jsonb;
  SELECT array_agg((x)::numeric) INTO v_setpoints FROM jsonb_array_elements_text(v_resp->'bess_setpoint_kw') x;
  SELECT array_agg((x)::numeric) INTO v_grid      FROM jsonb_array_elements_text(v_resp->'grid_import_kw') x;
  v_peak := (v_resp->>'predicted_peak_kw')::numeric; v_solver := v_resp->>'solver'; v_optstatus := v_resp->>'status';

  UPDATE ottoq_energy_plan
     SET bess_setpoint_kw=v_setpoints, grid_import_kw=v_grid, predicted_peak_kw=v_peak,
         solver=v_solver, status=v_optstatus, plan_state='ready',
         latency_ms = (extract(epoch from (now()-created_at))*1000)::int
   WHERE id=p_plan_id;

  RETURN jsonb_build_object('ok',true,'plan_state','ready','plan_id',p_plan_id,'solver',v_solver,
    'opt_status',v_optstatus,'predicted_peak_kw',round(v_peak,1),
    'forecast_peak_kw', round((SELECT max(u) FROM unnest(v_plan.forecast_load_kw) u),1));
END;
$function$

-- ===== ottoq_energy_mpc_ingest_run =====
CREATE OR REPLACE FUNCTION public.ottoq_energy_mpc_ingest_run(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE r RECORD; v_n int := 0; v_ready int := 0; v_last jsonb;
BEGIN
  FOR r IN SELECT id FROM ottoq_energy_plan WHERE sim_run_id=p_sim_run_id AND plan_state='pending' LOOP
    v_last := ottoq_energy_mpc_ingest(r.id); v_n := v_n+1;
    IF (v_last->>'plan_state')='ready' THEN v_ready := v_ready+1; END IF;
  END LOOP;
  RETURN jsonb_build_object('ingested', v_n, 'ready', v_ready, 'last', v_last);
END;
$function$

-- ===== ottoq_energy_mpc_replan =====
CREATE OR REPLACE FUNCTION public.ottoq_energy_mpc_replan(p_sim_run_id uuid, p_depot_id uuid, p_horizon_steps integer DEFAULT 40, p_tick_minutes numeric DEFAULT 30, p_forecast_load_kw numeric[] DEFAULT NULL::numeric[], p_wait_ms integer DEFAULT 7000, p_bridge_url text DEFAULT 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-energy-mpc'::text, p_bridge_token text DEFAULT 'ottoq-frontier-a7f3c9d1e5b8'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_start timestamptz; v_base numeric:=0; v_solar numeric:=0; v_ev numeric:=0; v_arr numeric;
  v_load numeric[]; v_bess RECORD; v_eff numeric; v_dt_h numeric := p_tick_minutes/60.0;
  v_body jsonb; v_req bigint; v_plan_id uuid; v_source text; h int; v_deadline timestamptz; v_found boolean;
BEGIN
  SELECT max(timestamp) INTO v_start FROM site_energy_snapshots WHERE depot_id=p_depot_id AND sim_run_id=p_sim_run_id;
  v_start := COALESCE(v_start, now());

  SELECT capacity_kwh, current_soc_pct, current_soc_kwh, max_charge_kw, max_discharge_kw,
         soc_min_floor_pct, soc_max_ceiling_pct, roundtrip_efficiency_pct
    INTO v_bess FROM ottoq_bess_units WHERE depot_id=p_depot_id LIMIT 1;
  IF v_bess.capacity_kwh IS NULL THEN RETURN jsonb_build_object('ok',false,'error','no_bess_for_depot'); END IF;
  v_eff := sqrt(GREATEST(0.5, COALESCE(v_bess.roundtrip_efficiency_pct,90)/100.0));

  IF p_forecast_load_kw IS NOT NULL THEN
    v_load := p_forecast_load_kw; v_source := 'mpc_perfect_forecast'; p_horizon_steps := array_length(v_load,1);
  ELSE
    v_source := 'mpc';
    SELECT COALESCE(building_load_kw,0)+COALESCE(lighting_load_kw,0), COALESCE(solar_generation_kw,0),
           COALESCE(total_ev_charging_kw,0) INTO v_base, v_solar, v_ev
      FROM site_energy_snapshots WHERE depot_id=p_depot_id AND sim_run_id=p_sim_run_id ORDER BY timestamp DESC LIMIT 1;
    v_load := array_fill(0::numeric, ARRAY[p_horizon_steps]);
    FOR h IN 1..p_horizon_steps LOOP
      SELECT predicted_charge_kw INTO v_arr FROM ottoq_predict_arrivals(
        p_depot_id, v_start + ((h-1)*p_tick_minutes)*interval '1 min', p_sim_run_id, p_tick_minutes::int);
      v_load[h] := GREATEST(v_base, v_base + COALESCE(v_ev,0)*power(0.90,h-1) + COALESCE(v_arr,0) - v_solar);
    END LOOP;
  END IF;

  v_body := jsonb_build_object(
    'load_kw', to_jsonb(v_load),
    'solar_kw', to_jsonb(array_fill(0::numeric, ARRAY[p_horizon_steps])),
    'energy_price_usd_per_kwh', to_jsonb(array_fill(0.06::numeric, ARRAY[p_horizon_steps])),
    'tick_hours', v_dt_h, 'demand_charge_usd_per_kw', 21.78,
    'bess', jsonb_build_object(
       'soc_kwh', COALESCE(v_bess.current_soc_kwh, v_bess.capacity_kwh*COALESCE(v_bess.current_soc_pct,50)/100.0),
       'capacity_kwh', v_bess.capacity_kwh, 'max_charge_kw', v_bess.max_charge_kw, 'max_discharge_kw', v_bess.max_discharge_kw,
       'soc_floor_frac', COALESCE(v_bess.soc_min_floor_pct,10)/100.0, 'soc_ceiling_frac', COALESCE(v_bess.soc_max_ceiling_pct,90)/100.0,
       'eff_charge', v_eff, 'eff_discharge', v_eff));

  v_req := net.http_post(url := p_bridge_url,
    headers := jsonb_build_object('Content-Type','application/json','x-bridge-token',p_bridge_token),
    body := v_body, timeout_milliseconds := 30000);

  INSERT INTO ottoq_energy_plan (sim_run_id, depot_id, plan_start_clock, tick_minutes, horizon_steps,
      bess_setpoint_kw, forecast_load_kw, source, request_id, plan_state)
  VALUES (p_sim_run_id, p_depot_id, v_start, p_tick_minutes, p_horizon_steps,
      ARRAY[]::numeric[], v_load, v_source, v_req, 'pending')
  RETURNING id INTO v_plan_id;

  -- opportunistic short poll (warm path returns fast); else caller ingests later
  v_deadline := clock_timestamp() + make_interval(secs => GREATEST(0,p_wait_ms)/1000.0);
  LOOP
    PERFORM pg_sleep(1);
    SELECT true INTO v_found FROM net._http_response WHERE id=v_req;
    EXIT WHEN v_found OR clock_timestamp() > v_deadline;
  END LOOP;

  RETURN ottoq_energy_mpc_ingest(v_plan_id) || jsonb_build_object('request_id', v_req, 'plan_id', v_plan_id);
END;
$function$

-- ===== ottoq_energy_mpc_replan =====
CREATE OR REPLACE FUNCTION public.ottoq_energy_mpc_replan(p_sim_run_id uuid, p_depot_id uuid, p_horizon_steps integer DEFAULT 40, p_tick_minutes numeric DEFAULT 30, p_forecast_load_kw numeric[] DEFAULT NULL::numeric[], p_wait_ms integer DEFAULT 7000, p_bridge_url text DEFAULT 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-energy-mpc'::text, p_bridge_token text DEFAULT 'ottoq-frontier-a7f3c9d1e5b8'::text, p_plan_start timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_start timestamptz; v_base numeric:=0; v_solar numeric:=0; v_ev numeric:=0; v_arr numeric;
  v_load numeric[]; v_bess RECORD; v_eff numeric; v_dt_h numeric := p_tick_minutes/60.0;
  v_body jsonb; v_req bigint; v_plan_id uuid; v_source text; h int; v_deadline timestamptz; v_found boolean;
BEGIN
  IF p_plan_start IS NOT NULL THEN
    v_start := p_plan_start;
  ELSE
    SELECT max(timestamp) INTO v_start FROM site_energy_snapshots WHERE depot_id=p_depot_id AND sim_run_id=p_sim_run_id;
    v_start := COALESCE(v_start, now());
  END IF;

  SELECT capacity_kwh, current_soc_pct, current_soc_kwh, max_charge_kw, max_discharge_kw,
         soc_min_floor_pct, soc_max_ceiling_pct, roundtrip_efficiency_pct
    INTO v_bess FROM ottoq_bess_units WHERE depot_id=p_depot_id LIMIT 1;
  IF v_bess.capacity_kwh IS NULL THEN RETURN jsonb_build_object('ok',false,'error','no_bess_for_depot'); END IF;
  v_eff := sqrt(GREATEST(0.5, COALESCE(v_bess.roundtrip_efficiency_pct,90)/100.0));

  IF p_forecast_load_kw IS NOT NULL THEN
    v_load := p_forecast_load_kw; v_source := 'mpc_perfect_forecast'; p_horizon_steps := array_length(v_load,1);
  ELSE
    v_source := 'mpc';
    SELECT COALESCE(building_load_kw,0)+COALESCE(lighting_load_kw,0), COALESCE(solar_generation_kw,0),
           COALESCE(total_ev_charging_kw,0) INTO v_base, v_solar, v_ev
      FROM site_energy_snapshots WHERE depot_id=p_depot_id AND sim_run_id=p_sim_run_id ORDER BY timestamp DESC LIMIT 1;
    v_load := array_fill(0::numeric, ARRAY[p_horizon_steps]);
    FOR h IN 1..p_horizon_steps LOOP
      SELECT predicted_charge_kw INTO v_arr FROM ottoq_predict_arrivals(
        p_depot_id, v_start + ((h-1)*p_tick_minutes)*interval '1 min', p_sim_run_id, p_tick_minutes::int);
      v_load[h] := GREATEST(v_base, v_base + COALESCE(v_ev,0)*power(0.90,h-1) + COALESCE(v_arr,0) - v_solar);
    END LOOP;
  END IF;

  v_body := jsonb_build_object(
    'load_kw', to_jsonb(v_load),
    'solar_kw', to_jsonb(array_fill(0::numeric, ARRAY[p_horizon_steps])),
    'energy_price_usd_per_kwh', to_jsonb(array_fill(0.06::numeric, ARRAY[p_horizon_steps])),
    'tick_hours', v_dt_h, 'demand_charge_usd_per_kw', 21.78,
    'bess', jsonb_build_object(
       'soc_kwh', COALESCE(v_bess.current_soc_kwh, v_bess.capacity_kwh*COALESCE(v_bess.current_soc_pct,50)/100.0),
       'capacity_kwh', v_bess.capacity_kwh, 'max_charge_kw', v_bess.max_charge_kw, 'max_discharge_kw', v_bess.max_discharge_kw,
       'soc_floor_frac', COALESCE(v_bess.soc_min_floor_pct,10)/100.0, 'soc_ceiling_frac', COALESCE(v_bess.soc_max_ceiling_pct,90)/100.0,
       'eff_charge', v_eff, 'eff_discharge', v_eff));

  v_req := net.http_post(url := p_bridge_url,
    headers := jsonb_build_object('Content-Type','application/json','x-bridge-token',p_bridge_token),
    body := v_body, timeout_milliseconds := 30000);

  INSERT INTO ottoq_energy_plan (sim_run_id, depot_id, plan_start_clock, tick_minutes, horizon_steps,
      bess_setpoint_kw, forecast_load_kw, source, request_id, plan_state)
  VALUES (p_sim_run_id, p_depot_id, v_start, p_tick_minutes, p_horizon_steps,
      ARRAY[]::numeric[], v_load, v_source, v_req, 'pending')
  RETURNING id INTO v_plan_id;

  v_deadline := clock_timestamp() + make_interval(secs => GREATEST(0,p_wait_ms)/1000.0);
  LOOP
    PERFORM pg_sleep(1);
    SELECT true INTO v_found FROM net._http_response WHERE id=v_req;
    EXIT WHEN v_found OR clock_timestamp() > v_deadline;
  END LOOP;

  RETURN ottoq_energy_mpc_ingest(v_plan_id) || jsonb_build_object('request_id', v_req, 'plan_id', v_plan_id);
END;
$function$

-- ===== ottoq_energy_mpc_replan =====
CREATE OR REPLACE FUNCTION public.ottoq_energy_mpc_replan(p_sim_run_id uuid, p_depot_id uuid, p_horizon_steps integer DEFAULT 40, p_tick_minutes numeric DEFAULT 30, p_forecast_load_kw numeric[] DEFAULT NULL::numeric[], p_wait_ms integer DEFAULT 7000, p_bridge_url text DEFAULT 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-energy-mpc'::text, p_bridge_token text DEFAULT 'ottoq-frontier-a7f3c9d1e5b8'::text, p_plan_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_forecast_from_run uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_start timestamptz; v_base numeric:=0; v_solar numeric:=0; v_ev numeric:=0; v_arr numeric;
  v_load numeric[]; v_bess RECORD; v_eff numeric; v_dt_h numeric := p_tick_minutes/60.0;
  v_body jsonb; v_req bigint; v_plan_id uuid; v_source text; h int; v_deadline timestamptz; v_found boolean;
BEGIN
  IF p_plan_start IS NOT NULL THEN v_start := p_plan_start;
  ELSE
    SELECT max(timestamp) INTO v_start FROM site_energy_snapshots WHERE depot_id=p_depot_id AND sim_run_id=p_sim_run_id;
    v_start := COALESCE(v_start, now());
  END IF;

  SELECT capacity_kwh, current_soc_pct, current_soc_kwh, max_charge_kw, max_discharge_kw,
         soc_min_floor_pct, soc_max_ceiling_pct, roundtrip_efficiency_pct
    INTO v_bess FROM ottoq_bess_units WHERE depot_id=p_depot_id LIMIT 1;
  IF v_bess.capacity_kwh IS NULL THEN RETURN jsonb_build_object('ok',false,'error','no_bess_for_depot'); END IF;
  v_eff := sqrt(GREATEST(0.5, COALESCE(v_bess.roundtrip_efficiency_pct,90)/100.0));

  IF p_forecast_from_run IS NOT NULL THEN
    SELECT array_agg(nl ORDER BY timestamp) INTO v_load FROM (
      SELECT timestamp, GREATEST(0, building_load_kw+lighting_load_kw+total_ev_charging_kw-solar_generation_kw) AS nl
      FROM site_energy_snapshots WHERE sim_run_id=p_forecast_from_run) q;
    v_source := 'mpc_perfect_forecast'; p_horizon_steps := array_length(v_load,1);
  ELSIF p_forecast_load_kw IS NOT NULL THEN
    v_load := p_forecast_load_kw; v_source := 'mpc_perfect_forecast'; p_horizon_steps := array_length(v_load,1);
  ELSE
    v_source := 'mpc';
    SELECT COALESCE(building_load_kw,0)+COALESCE(lighting_load_kw,0), COALESCE(solar_generation_kw,0),
           COALESCE(total_ev_charging_kw,0) INTO v_base, v_solar, v_ev
      FROM site_energy_snapshots WHERE depot_id=p_depot_id AND sim_run_id=p_sim_run_id ORDER BY timestamp DESC LIMIT 1;
    v_load := array_fill(0::numeric, ARRAY[p_horizon_steps]);
    FOR h IN 1..p_horizon_steps LOOP
      SELECT predicted_charge_kw INTO v_arr FROM ottoq_predict_arrivals(
        p_depot_id, v_start + ((h-1)*p_tick_minutes)*interval '1 min', p_sim_run_id, p_tick_minutes::int);
      v_load[h] := GREATEST(v_base, v_base + COALESCE(v_ev,0)*power(0.90,h-1) + COALESCE(v_arr,0) - v_solar);
    END LOOP;
  END IF;

  v_body := jsonb_build_object(
    'load_kw', to_jsonb(v_load),
    'solar_kw', to_jsonb(array_fill(0::numeric, ARRAY[p_horizon_steps])),
    'energy_price_usd_per_kwh', to_jsonb(array_fill(0.06::numeric, ARRAY[p_horizon_steps])),
    'tick_hours', v_dt_h, 'demand_charge_usd_per_kw', 21.78,
    'bess', jsonb_build_object(
       'soc_kwh', COALESCE(v_bess.current_soc_kwh, v_bess.capacity_kwh*COALESCE(v_bess.current_soc_pct,50)/100.0),
       'capacity_kwh', v_bess.capacity_kwh, 'max_charge_kw', v_bess.max_charge_kw, 'max_discharge_kw', v_bess.max_discharge_kw,
       'soc_floor_frac', COALESCE(v_bess.soc_min_floor_pct,10)/100.0, 'soc_ceiling_frac', COALESCE(v_bess.soc_max_ceiling_pct,90)/100.0,
       'eff_charge', v_eff, 'eff_discharge', v_eff));

  v_req := net.http_post(url := p_bridge_url,
    headers := jsonb_build_object('Content-Type','application/json','x-bridge-token',p_bridge_token),
    body := v_body, timeout_milliseconds := 30000);

  INSERT INTO ottoq_energy_plan (sim_run_id, depot_id, plan_start_clock, tick_minutes, horizon_steps,
      bess_setpoint_kw, forecast_load_kw, source, request_id, plan_state)
  VALUES (p_sim_run_id, p_depot_id, v_start, p_tick_minutes, p_horizon_steps,
      ARRAY[]::numeric[], v_load, v_source, v_req, 'pending')
  RETURNING id INTO v_plan_id;

  v_deadline := clock_timestamp() + make_interval(secs => GREATEST(0,p_wait_ms)/1000.0);
  LOOP
    PERFORM pg_sleep(1);
    SELECT true INTO v_found FROM net._http_response WHERE id=v_req;
    EXIT WHEN v_found OR clock_timestamp() > v_deadline;
  END LOOP;

  RETURN ottoq_energy_mpc_ingest(v_plan_id) || jsonb_build_object('request_id', v_req, 'plan_id', v_plan_id);
END;
$function$

-- ===== ottoq_energy_orchestrate =====
CREATE OR REPLACE FUNCTION public.ottoq_energy_orchestrate(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone, p_tick_seq bigint)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_service_max numeric; v_se RECORD; v_lmp numeric; v_bess RECORD;
  v_base_load numeric; v_solar numeric; v_ev numeric; v_net_load numeric;
  v_demand_target numeric; v_bess_dispatch numeric := 0; v_charge_cap numeric;
  v_expensive boolean; v_forecast_kw numeric; v_wave_incoming boolean;
  v_dr_cap numeric; v_dr_active boolean; v_solar_surplus numeric; v_tempok boolean;
  v_mode text := 'idle';
  v_soc numeric; v_floor numeric; v_ceil numeric; v_maxdis numeric; v_maxchg numeric;
  v_uncertainty numeric := 0; v_reserve_floor numeric;
  v_seed bigint; v_desired_ev numeric; v_recharge_ceiling numeric;
  v_mpc_follow boolean := false; v_plan RECORD; v_step int; v_mpc_setpoint numeric := NULL;
  v_reserve_shave boolean := false;
BEGIN
  SELECT service_max_kw INTO v_service_max FROM depots WHERE id = p_depot_id;
  IF v_service_max IS NULL THEN RETURN NULL; END IF;
  v_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42'), 42));

  SELECT building_load_kw, lighting_load_kw, solar_generation_kw, total_ev_charging_kw
    INTO v_se FROM site_energy_snapshots
   WHERE depot_id = p_depot_id AND sim_run_id = p_sim_run_id ORDER BY timestamp DESC LIMIT 1;
  v_base_load := COALESCE(v_se.building_load_kw,0) + COALESCE(v_se.lighting_load_kw,0);
  v_solar     := COALESCE(v_se.solar_generation_kw,0);

  SELECT COALESCE(SUM(
    ottoq_sim_compute_charge_rate(
      p_soc_pct := v.current_soc,
      p_battery_temp_c := COALESCE(s.ambient_temp_c,22) + 5 + ottoq_sim_seeded_random(v_seed,'btemp:'||s.id::text)*8 + LEAST(15, EXTRACT(EPOCH FROM (p_sim_clock - s.started_at))/600.0*5),
      p_ambient_temp_c := COALESCE(s.ambient_temp_c,22), p_charger_max_kw := ch.max_kw,
      p_vehicle_max_kw := v.inlet_max_kw, p_battery_capacity_kwh := v.battery_capacity_kwh,
      p_battery_soh_pct := COALESCE((v.config->>'battery_soh_pct')::numeric,95),
      p_noise_seed := v_seed, p_noise_salt := s.id::text||':'||p_sim_clock::text)
    / GREATEST(0.2, ottoq_profile_rate_mult(p_sim_run_id,'charge_time'))
  ),0) INTO v_desired_ev
  FROM ocpp_sessions s JOIN stalls st ON st.id = s.stall_id
  JOIN ottoq_ocpp_chargers ch ON ch.charger_id = st.ocpp_charger_id
  JOIN vehicles v ON v.id = s.vehicle_id
  WHERE s.status='active' AND s.id_token LIKE 'TWIN-%';

  v_ev        := GREATEST(COALESCE(v_se.total_ev_charging_kw,0), COALESCE(v_desired_ev,0));
  v_net_load  := v_base_load + v_ev - v_solar;
  v_solar_surplus := GREATEST(0, v_solar - (v_base_load + v_ev));

  SELECT lmp_usd_per_mwh INTO v_lmp FROM ottoq_grid_snapshots
   WHERE sim_run_id = p_sim_run_id ORDER BY sim_clock_at DESC LIMIT 1;
  v_lmp := COALESCE(v_lmp, 40);  v_expensive := v_lmp > 60;

  SELECT current_soc_pct, soc_min_floor_pct, soc_max_ceiling_pct, max_discharge_kw, max_charge_kw,
         current_temperature_c, temperature_max_c
    INTO v_bess FROM ottoq_bess_units WHERE depot_id = p_depot_id LIMIT 1;
  v_tempok := COALESCE(v_bess.current_temperature_c, 25) < COALESCE(v_bess.temperature_max_c, 50) - 2;
  v_soc := v_bess.current_soc_pct; v_floor := COALESCE(v_bess.soc_min_floor_pct,10);
  v_ceil := COALESCE(v_bess.soc_max_ceiling_pct,90);
  v_maxdis := COALESCE(v_bess.max_discharge_kw,500); v_maxchg := COALESCE(v_bess.max_charge_kw,500);
  v_uncertainty := COALESCE(ottoq_forecast_uncertainty(p_sim_run_id, p_depot_id, p_sim_clock), 0);
  v_reserve_floor := v_floor + v_uncertainty * 20;

  v_demand_target := v_service_max * (CASE WHEN v_expensive THEN ottoq_policy_get(p_sim_run_id,'energy_demand_factor_expensive',0.35) ELSE ottoq_policy_get(p_sim_run_id,'energy_demand_factor_peak',0.50) END);

  -- FR-1b: causal reserve-aware water-fill target (robust, in-twin, self-correcting each tick)
  IF ottoq_policy_get(p_sim_run_id, 'energy_reserve_shave', 0) >= 0.5 THEN
    v_demand_target := COALESCE(ottoq_bess_reserve_target(p_sim_run_id, p_depot_id, p_sim_clock, 16, 30), v_demand_target);
    v_reserve_shave := true;
  END IF;

  v_recharge_ceiling := 0.40 * v_demand_target;   -- recharge only in deep valleys, never near a billable peak

  SELECT required_load_cap_kw INTO v_dr_cap FROM ottoq_dr_calls
   WHERE depot_id = p_depot_id AND call_status IN ('active','issued') AND expires_at > p_sim_clock
   ORDER BY required_load_cap_kw ASC LIMIT 1;
  v_dr_active := v_dr_cap IS NOT NULL;
  IF v_dr_active THEN v_demand_target := LEAST(v_demand_target, v_dr_cap); END IF;

  SELECT predicted_charge_kw INTO v_forecast_kw FROM ottoq_predict_arrivals(p_depot_id, p_sim_clock, p_sim_run_id, 60);
  v_forecast_kw := COALESCE(v_forecast_kw, 0);
  v_wave_incoming := v_forecast_kw > v_demand_target * 0.4;

  -- FR-1: frontier MPC plan-follow (gated; falls through to heuristic if no fresh plan/step)
  IF ottoq_policy_get(p_sim_run_id, 'energy_mpc_follow', 0) >= 0.5 THEN
    SELECT bess_setpoint_kw, plan_start_clock, tick_minutes, horizon_steps
      INTO v_plan FROM ottoq_energy_plan
     WHERE sim_run_id = p_sim_run_id AND depot_id = p_depot_id AND plan_state = 'ready'
       AND array_length(bess_setpoint_kw,1) > 0
     ORDER BY created_at DESC LIMIT 1;
    IF FOUND THEN
      v_step := floor(EXTRACT(EPOCH FROM (p_sim_clock - v_plan.plan_start_clock)) / (v_plan.tick_minutes*60.0))::int;
      IF v_step >= 0 AND v_step < v_plan.horizon_steps AND v_step+1 <= array_length(v_plan.bess_setpoint_kw,1) THEN
        v_mpc_setpoint := v_plan.bess_setpoint_kw[v_step+1];
        v_mpc_follow := true;
      END IF;
    END IF;
  END IF;

  IF NOT v_tempok OR v_soc IS NULL THEN
    v_bess_dispatch := 0; v_mode := 'thermal_hold';
  ELSIF v_mpc_follow THEN
    v_bess_dispatch := GREATEST(-v_maxchg, LEAST(v_maxdis, v_mpc_setpoint));
    IF v_bess_dispatch > 0 AND v_soc <= v_reserve_floor + 3 THEN v_bess_dispatch := 0; END IF;
    IF v_bess_dispatch < 0 AND v_soc >= v_ceil - 1 THEN v_bess_dispatch := 0; END IF;
    v_mode := 'mpc_follow';
  ELSIF v_net_load > v_demand_target AND v_soc > v_reserve_floor + 3 THEN
    v_bess_dispatch := LEAST(v_maxdis, v_net_load - v_demand_target);
    v_mode := CASE WHEN v_dr_active THEN 'discharge_dr' WHEN v_reserve_shave THEN 'discharge_reserve_shave' ELSE 'discharge_shave' END;
  ELSIF v_soc < v_ceil - 3 THEN
    IF v_solar_surplus > 5 THEN
      v_bess_dispatch := -LEAST(v_maxchg, v_solar_surplus);
      v_mode := 'charge_solar_capture';
    ELSIF NOT v_expensive AND NOT v_wave_incoming AND v_net_load < v_recharge_ceiling THEN
      v_bess_dispatch := -LEAST(v_maxchg, GREATEST(0, v_recharge_ceiling - v_net_load));
      v_mode := 'charge_offpeak_reserve';
    ELSE
      v_bess_dispatch := 0; v_mode := 'hold_reserve';
    END IF;
  ELSE
    v_bess_dispatch := 0; v_mode := 'idle';
  END IF;

  v_charge_cap := GREATEST(50, v_demand_target - v_base_load + v_solar + v_bess_dispatch);

  INSERT INTO ottoq_energy_commands (sim_run_id, depot_id, tick_seq, issued_at, source, command_type, setpoint_kw, horizon_min, reason)
  VALUES
   (p_sim_run_id, p_depot_id, p_tick_seq, p_sim_clock, 'otto_q', 'charge_cap_kw', round(v_charge_cap,1), 15,
     jsonb_build_object('advisory', true, 'demand_target', round(v_demand_target,0), 'base_load', round(v_base_load,0),
                        'solar', round(v_solar,0), 'desired_ev_kw', round(v_desired_ev,0), 'lmp_usd_mwh', v_lmp, 'expensive', v_expensive,
                        'dr_active', v_dr_active, 'dr_cap_kw', v_dr_cap, 'forecast_charge_kw', round(v_forecast_kw,0))),
   (p_sim_run_id, p_depot_id, p_tick_seq, p_sim_clock, CASE WHEN v_mpc_follow THEN 'otto_q_mpc' ELSE 'otto_q' END, 'bess_setpoint_kw', round(v_bess_dispatch,1), 35,
     jsonb_build_object('mode', v_mode, 'soc_pct', v_soc, 'temp_c', v_bess.current_temperature_c,
                        'lmp_usd_mwh', v_lmp, 'solar_surplus_kw', round(v_solar_surplus,0),
                        'net_load_kw', round(v_net_load,0), 'demand_target_kw', round(v_demand_target,0), 'recharge_ceiling_kw', round(v_recharge_ceiling,0),
                        'desired_ev_kw', round(v_desired_ev,0), 'forecast_charge_kw', round(v_forecast_kw,0),
                        'reserve_shave', v_reserve_shave,
                        'mpc_setpoint_kw', CASE WHEN v_mpc_follow THEN round(v_mpc_setpoint,1) END, 'mpc_step', v_step));
  RETURN round(v_charge_cap,1);
END;
$function$

-- ===== ottoq_entity_history =====
CREATE OR REPLACE FUNCTION public.ottoq_entity_history(p_entity_type text, p_entity_id uuid, p_limit integer DEFAULT 500)
 RETURNS SETOF ottoq_events
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT * FROM ottoq_events
  WHERE entity_type = p_entity_type AND entity_id = p_entity_id
  ORDER BY event_seq DESC
  LIMIT p_limit;
$function$

-- ===== ottoq_estimate_charge_minutes =====
CREATE OR REPLACE FUNCTION public.ottoq_estimate_charge_minutes(p_start_soc numeric, p_target_soc numeric, p_charger_max_kw numeric, p_vehicle_max_kw numeric, p_battery_capacity_kwh numeric, p_battery_temp_c numeric DEFAULT 25, p_battery_soh_pct numeric DEFAULT 95, p_rate_mult numeric DEFAULT 1.0)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc  numeric := p_start_soc;
  v_step numeric := 1.0;
  v_kw   numeric;
  v_min  numeric := 0;
BEGIN
  IF p_target_soc <= p_start_soc OR p_battery_capacity_kwh <= 0 THEN RETURN 0; END IF;
  WHILE v_soc < p_target_soc LOOP
    v_kw := public.ottoq_sim_compute_charge_rate(
      p_soc_pct := v_soc,
      p_battery_temp_c := p_battery_temp_c,
      p_ambient_temp_c := p_battery_temp_c,
      p_charger_max_kw := p_charger_max_kw,
      p_vehicle_max_kw := p_vehicle_max_kw,
      p_battery_capacity_kwh := p_battery_capacity_kwh,
      p_battery_soh_pct := p_battery_soh_pct,
      p_noise_seed := 0, p_noise_salt := 'plan');
    v_kw := v_kw / GREATEST(0.2, p_rate_mult);
    EXIT WHEN v_kw <= 0.5;
    v_min := v_min + (v_step / 100.0 * p_battery_capacity_kwh) / v_kw * 60.0;
    v_soc := v_soc + v_step;
  END LOOP;
  RETURN ROUND(v_min, 1);
END;
$function$

-- ===== ottoq_eval_en_001_grid_capacity =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_en_001_grid_capacity(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot_id     UUID;
  v_request_kw   NUMERIC;
  v_depot        depots%ROWTYPE;
  v_now          TIMESTAMPTZ := COALESCE(NULLIF(p_context ->> 'now_ts','')::timestamptz, NOW());  -- WIRE-3
  v_current_kw   NUMERIC;
  v_engineering_cap NUMERIC;
  v_after_kw     NUMERIC;
  v_safety_pct   NUMERIC;
  v_min_headroom NUMERIC;
BEGIN
  v_depot_id := NULLIF(p_context ->> 'depot_id', '')::UUID;
  v_request_kw := COALESCE((p_context ->> 'requested_kw')::NUMERIC, 0);
  IF v_depot_id IS NULL OR v_request_kw <= 0 THEN
    RETURN ROW(TRUE, 'no depot/request context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;
  SELECT * INTO v_depot FROM depots WHERE id = v_depot_id;
  IF v_depot.dcfc_max_concurrent_kw IS NULL THEN
    RETURN ROW(TRUE, 'depot has no dcfc_max_concurrent_kw configured (allow)', 'warning',
      jsonb_build_object('depot_id', v_depot_id), 'configure_depot_capacity')::ottoq_rule_result;
  END IF;
  v_safety_pct := COALESCE(v_depot.dcfc_safety_margin_pct, 10.0);
  v_engineering_cap := v_depot.dcfc_max_concurrent_kw * (1 - v_safety_pct/100.0);
  v_current_kw := ottoq_depot_current_demand_kw(v_depot_id, v_now);   -- WIRE-3: sim clock
  v_after_kw := v_current_kw + v_request_kw;
  v_min_headroom := v_engineering_cap - v_after_kw;
  IF v_after_kw > v_engineering_cap THEN
    RETURN ROW(FALSE,
      format('would exceed engineering cap: %s + %s = %s kW (cap with margin: %s kW)',
        round(v_current_kw,1), round(v_request_kw,1), round(v_after_kw,1), round(v_engineering_cap,1)),
      'safety_critical',   -- OD-6: near-breaker-trip is safety_critical, not the downgraded 'critical'
      jsonb_build_object('depot_id', v_depot_id, 'current_kw', v_current_kw, 'requested_kw', v_request_kw,
        'after_kw', v_after_kw, 'engineering_cap_kw', v_engineering_cap, 'safety_margin_pct', v_safety_pct,
        'depot_dcfc_max_kw', v_depot.dcfc_max_concurrent_kw, 'now_ts', v_now),
      'defer_or_throttle_other_sessions')::ottoq_rule_result;
  END IF;
  IF v_depot.service_max_kw IS NOT NULL AND v_after_kw > v_depot.service_max_kw THEN
    RETURN ROW(FALSE,
      format('would exceed utility service contract: %s > %s kW', round(v_after_kw,1), round(v_depot.service_max_kw,1)),
      'safety_critical',
      jsonb_build_object('after_kw', v_after_kw, 'service_max_kw', v_depot.service_max_kw),
      'engage_bess_or_defer')::ottoq_rule_result;
  END IF;
  RETURN ROW(TRUE,
    format('grid capacity OK: %s + %s = %s kW (headroom %s kW)',
      round(v_current_kw,1), round(v_request_kw,1), round(v_after_kw,1), round(v_min_headroom,1)),
    NULL,
    jsonb_build_object('current_kw', v_current_kw, 'after_kw', v_after_kw,
      'engineering_cap_kw', v_engineering_cap, 'headroom_kw', v_min_headroom), NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_en_002_stall_power_ceiling =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_en_002_stall_power_ceiling(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_stall_id      UUID;
  v_request_kw    NUMERIC;
  v_stall_max_kw  NUMERIC;
BEGIN
  v_stall_id := NULLIF(p_context ->> 'stall_id', '')::UUID;
  v_request_kw := COALESCE((p_context ->> 'requested_kw')::NUMERIC, 0);

  IF v_stall_id IS NULL OR v_request_kw <= 0 THEN
    RETURN ROW(TRUE, 'no stall/request context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  SELECT connector_max_kw INTO v_stall_max_kw FROM stalls WHERE id = v_stall_id;

  IF v_stall_max_kw IS NULL THEN
    RETURN ROW(TRUE, 'stall has no max_kw configured', 'warning',
      jsonb_build_object('stall_id', v_stall_id),
      NULL
    )::ottoq_rule_result;
  END IF;

  IF v_request_kw > v_stall_max_kw THEN
    RETURN ROW(FALSE,
      format('requested %s kW exceeds stall ceiling %s kW', v_request_kw, v_stall_max_kw),
      'critical',
      jsonb_build_object(
        'stall_id', v_stall_id,
        'requested_kw', v_request_kw,
        'stall_max_kw', v_stall_max_kw
      ),
      'reduce_target_power'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,
    format('within stall ceiling (%s / %s kW)', v_request_kw, v_stall_max_kw),
    NULL,
    jsonb_build_object('utilization_pct', ROUND((v_request_kw / v_stall_max_kw) * 100, 1)),
    NULL
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_en_003_bess_limits =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_en_003_bess_limits(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_bess_id  UUID;
  v_action   TEXT;
  v_req_kw   NUMERIC;
  v_bess     ottoq_bess_units%ROWTYPE;
  v_cap      NUMERIC;
BEGIN
  v_bess_id := COALESCE(NULLIF(p_context ->> 'bess_id','')::UUID, CASE WHEN p_entity_type='bess' THEN p_entity_id END);
  v_action  := COALESCE(p_context ->> 'action', 'unknown');
  v_req_kw  := COALESCE((p_context ->> 'requested_kw')::NUMERIC, NULL);

  IF v_bess_id IS NULL THEN
    -- pick the depot's unit if a depot is given (bess_dispatch path)
    SELECT bess_id INTO v_bess_id FROM ottoq_bess_units WHERE depot_id = NULLIF(p_context->>'depot_id','')::uuid LIMIT 1;
  END IF;
  IF v_bess_id IS NULL THEN
    RETURN ROW(TRUE, 'no bess context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  SELECT * INTO v_bess FROM ottoq_bess_units WHERE bess_id = v_bess_id;
  IF NOT FOUND THEN
    RETURN ROW(FALSE, format('BESS %s not registered', v_bess_id), 'safety_critical',
      jsonb_build_object('bess_id', v_bess_id), 'register_bess')::ottoq_rule_result;
  END IF;

  -- M15: normalize a 'bess_dispatch' verb to charge/discharge from the requested_kw sign
  IF v_action IN ('unknown','bess_dispatch') AND v_req_kw IS NOT NULL THEN
    v_action := CASE WHEN v_req_kw > 0 THEN 'charge' WHEN v_req_kw < 0 THEN 'discharge' ELSE 'standby' END;
  END IF;

  -- SoC floor (discharge) / ceiling (charge) — preserved
  IF v_action = 'discharge' AND v_bess.current_soc_pct IS NOT NULL AND v_bess.current_soc_pct <= v_bess.soc_min_floor_pct THEN
    RETURN ROW(FALSE, format('BESS at SoC floor: %s%% <= %s%%', v_bess.current_soc_pct, v_bess.soc_min_floor_pct),
      'safety_critical', jsonb_build_object('current_soc_pct', v_bess.current_soc_pct, 'floor_pct', v_bess.soc_min_floor_pct), 'defer_discharge')::ottoq_rule_result;
  END IF;
  IF v_action = 'charge' AND v_bess.current_soc_pct IS NOT NULL AND v_bess.current_soc_pct >= v_bess.soc_max_ceiling_pct THEN
    RETURN ROW(FALSE, format('BESS at SoC ceiling: %s%% >= %s%%', v_bess.current_soc_pct, v_bess.soc_max_ceiling_pct),
      'safety_critical', jsonb_build_object('current_soc_pct', v_bess.current_soc_pct, 'ceiling_pct', v_bess.soc_max_ceiling_pct), 'defer_charge')::ottoq_rule_result;
  END IF;

  -- M15: power/C-rate ceiling — reject a draw beyond the unit's rated power
  IF v_req_kw IS NOT NULL THEN
    v_cap := CASE WHEN v_req_kw > 0 THEN COALESCE(v_bess.max_charge_kw,0) ELSE COALESCE(v_bess.max_discharge_kw,0) END;
    IF abs(v_req_kw) > v_cap THEN
      RETURN ROW(FALSE, format('BESS setpoint %s kW exceeds rated %s kW (%s)', round(abs(v_req_kw),1), round(v_cap,1), v_action),
        'safety_critical', jsonb_build_object('requested_kw', v_req_kw, 'rated_kw', v_cap, 'action', v_action), 'clamp_to_rated_power')::ottoq_rule_result;
    END IF;
  END IF;

  RETURN ROW(TRUE, format('BESS within limits (%s, soc %s%%)', v_action, COALESCE(v_bess.current_soc_pct::text,'?')),
    NULL, jsonb_build_object('soc_pct', v_bess.current_soc_pct, 'state', v_bess.current_state, 'action', v_action), NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_en_004_demand_response =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_en_004_demand_response(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot_id   UUID;
  v_request_kw NUMERIC;
  v_dr_event   ottoq_grid_events%ROWTYPE;
  v_now        TIMESTAMPTZ := COALESCE(NULLIF(p_context ->> 'now_ts','')::timestamptz, NOW());  -- WIRE-3
  v_target_kw  NUMERIC;
  v_current_kw NUMERIC;
  v_allow_bess BOOLEAN := COALESCE((p_parameters ->> 'allow_bess_offset')::BOOLEAN, TRUE);
BEGIN
  v_depot_id := NULLIF(p_context ->> 'depot_id', '')::UUID;
  v_request_kw := COALESCE((p_context ->> 'requested_kw')::NUMERIC, 0);
  IF v_depot_id IS NULL THEN
    RETURN ROW(TRUE, 'no depot context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;
  SELECT * INTO v_dr_event FROM ottoq_grid_events
   WHERE depot_id = v_depot_id AND event_type = 'demand_response_called'
     AND cleared_at IS NULL AND effective_at <= v_now
     AND (expires_at IS NULL OR expires_at > v_now)   -- WIRE-3
   ORDER BY effective_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN ROW(TRUE, 'no active demand-response window', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;
  v_target_kw := (v_dr_event.payload ->> 'target_kw')::NUMERIC;
  v_current_kw := ottoq_depot_current_demand_kw(v_depot_id, v_now);   -- WIRE-3: pass sim clock
  IF v_target_kw IS NULL THEN
    RETURN ROW(FALSE, 'demand-response active without explicit target_kw — blocking new sessions conservatively',
      'warning', jsonb_build_object('grid_event_id', v_dr_event.grid_event_id), 'defer_until_dr_clears')::ottoq_rule_result;
  END IF;
  IF v_current_kw + v_request_kw > v_target_kw THEN
    -- NOTE: Postgres format() has NO %.1f (that's printf). The DEPLOYED EN.004 used
    -- %.1f and would THROW 22023 on the exact block path — another reason it was
    -- silently dead. Fixed: round() + %s.
    RETURN ROW(FALSE, format('demand-response: %s + %s > target %s kW', round(v_current_kw,1), round(v_request_kw,1), round(v_target_kw,1)),
      'critical', jsonb_build_object('grid_event_id', v_dr_event.grid_event_id, 'target_kw', v_target_kw, 'current_kw', v_current_kw,
        'requested_kw', v_request_kw, 'expires_at', v_dr_event.expires_at, 'allow_bess_offset', v_allow_bess),
      CASE WHEN v_allow_bess THEN 'engage_bess_or_defer' ELSE 'defer_until_dr_clears' END)::ottoq_rule_result;
  END IF;
  RETURN ROW(TRUE, format('within DR target (%s + %s <= %s kW)', round(v_current_kw,1), round(v_request_kw,1), round(v_target_kw,1)),
    NULL, jsonb_build_object('headroom_kw', v_target_kw - (v_current_kw + v_request_kw)), NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_en_005_grid_event_hardstop =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_en_005_grid_event_hardstop(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot_id UUID;
  v_event    ottoq_grid_events%ROWTYPE;
  v_now      TIMESTAMPTZ := COALESCE(NULLIF(p_context ->> 'now_ts','')::timestamptz, NOW());  -- WIRE-3
  -- WIRE-4: include the twin-mirrored vocabulary alongside the legacy set so the
  -- certified rule fires on real TWIN grid faults without changing its contract.
  v_hard_stop_types TEXT[] := ARRAY['grid_trip','brownout','undervoltage','overvoltage','grid_voltage_sag','grid_frequency_excursion','grid_brownout'];
BEGIN
  v_depot_id := NULLIF(p_context ->> 'depot_id', '')::UUID;
  IF v_depot_id IS NULL THEN
    RETURN ROW(TRUE, 'no depot context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;
  SELECT * INTO v_event FROM ottoq_grid_events
   WHERE depot_id = v_depot_id AND event_type = ANY(v_hard_stop_types)
     AND cleared_at IS NULL AND effective_at <= v_now
     AND (expires_at IS NULL OR expires_at > v_now)   -- WIRE-3 + honor expiry so events clear
   ORDER BY effective_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN ROW(TRUE, 'grid healthy', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;
  RETURN ROW(FALSE, format('grid event active: %s (since %s)', v_event.event_type, v_event.effective_at),
    'safety_critical', jsonb_build_object('grid_event_id', v_event.grid_event_id, 'event_type', v_event.event_type,
      'effective_at', v_event.effective_at, 'expires_at', v_event.expires_at, 'payload', v_event.payload),
    'emergency_cascade')::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_hw_001_connector_compatibility =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_hw_001_connector_compatibility(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_stall_id        UUID;
  v_vehicle_id      UUID;
  v_stall_conn      TEXT;
  v_supported       TEXT[];
  v_vehicle_inlet   TEXT;
  v_strict          BOOLEAN := COALESCE((p_parameters ->> 'strict')::BOOLEAN, FALSE);
  v_svc             TEXT := lower(coalesce(p_context ->> 'service_code', p_context ->> 'service', ''));
  v_req_charge      TEXT := p_context ->> 'requires_charging';
  v_result          ottoq_rule_result;
BEGIN
  -- SCOPE GUARD (charge-only rule): connector compatibility is a CHARGING precondition.
  -- For an action the caller explicitly flags as non-charging (inspection / wash / staging
  -- transition) it is N/A. Default is UNCHANGED: with no service hint, full strict enforcement
  -- still applies, and any charging service code still gets the full check below. The rule still
  -- runs and records this N/A verdict (auditable; not silenced).
  IF v_req_charge = 'false'
     OR (v_svc <> '' AND v_svc NOT IN ('charge','dcfc_charge','l2_charge','charging','fast_charge','dc_fast_charge')) THEN
    RETURN ROW(TRUE,
      format('non-charging action (%s): connector compatibility N/A', COALESCE(NULLIF(v_svc,''),'flagged')),
      NULL, jsonb_build_object('service', v_svc, 'requires_charging', v_req_charge), NULL)::ottoq_rule_result;
  END IF;

  v_stall_id := COALESCE(
    NULLIF(p_context ->> 'stall_id', '')::UUID,
    CASE WHEN p_entity_type = 'stall' THEN p_entity_id END
  );
  v_vehicle_id := COALESCE(
    NULLIF(p_context ->> 'vehicle_id', '')::UUID,
    CASE WHEN p_entity_type = 'vehicle' THEN p_entity_id END
  );

  IF v_stall_id IS NULL OR v_vehicle_id IS NULL THEN
    v_result := ROW(
      NOT v_strict,
      CASE WHEN v_strict THEN 'missing stall_id or vehicle_id in context'
           ELSE 'unknown stall/vehicle pair (non-strict mode: allowed)' END,
      NULL,
      jsonb_build_object('stall_id', v_stall_id, 'vehicle_id', v_vehicle_id),
      NULL
    )::ottoq_rule_result;
    RETURN v_result;
  END IF;

  SELECT connector_type, supported_inlet_types
    INTO v_stall_conn, v_supported
    FROM stalls WHERE id = v_stall_id;

  SELECT inlet_type INTO v_vehicle_inlet
    FROM vehicles WHERE id = v_vehicle_id;

  -- Non-charging stalls always pass
  IF v_stall_conn = 'NonCharging' THEN
    RETURN ROW(TRUE, 'non-charging stall: compatibility check N/A',
      NULL, jsonb_build_object('stall_connector', v_stall_conn), NULL)::ottoq_rule_result;
  END IF;

  -- NULL handling
  IF v_stall_conn IS NULL OR v_vehicle_inlet IS NULL THEN
    RETURN ROW(
      NOT v_strict,
      format('null connector data (stall=%s, vehicle=%s); strict=%s',
        COALESCE(v_stall_conn, 'null'),
        COALESCE(v_vehicle_inlet, 'null'),
        v_strict),
      CASE WHEN v_strict THEN 'error' ELSE 'warning' END,
      jsonb_build_object(
        'stall_connector', v_stall_conn,
        'vehicle_inlet', v_vehicle_inlet,
        'strict', v_strict
      ),
      'populate_inlet_metadata'
    )::ottoq_rule_result;
  END IF;

  -- Multi-standard stalls pass if vehicle inlet is in supported list
  IF v_stall_conn = 'Multi' THEN
    IF v_vehicle_inlet = ANY(v_supported) THEN
      RETURN ROW(TRUE,
        format('multi-standard stall supports %s', v_vehicle_inlet),
        NULL,
        jsonb_build_object('vehicle_inlet', v_vehicle_inlet, 'supported', v_supported),
        NULL
      )::ottoq_rule_result;
    ELSE
      RETURN ROW(FALSE,
        format('multi-standard stall does not support %s (supports: %s)',
          v_vehicle_inlet, array_to_string(v_supported, ',')),
        NULL,
        jsonb_build_object('vehicle_inlet', v_vehicle_inlet, 'supported', v_supported),
        'reroute_to_compatible_stall'
      )::ottoq_rule_result;
    END IF;
  END IF;

  -- Direct match
  IF v_stall_conn = v_vehicle_inlet THEN
    RETURN ROW(TRUE,
      format('connector match: %s', v_stall_conn),
      NULL,
      jsonb_build_object('connector', v_stall_conn),
      NULL
    )::ottoq_rule_result;
  END IF;

  -- Cross-compatible pairs (extensible — encoded here as known-safe pairs)
  IF (v_stall_conn = 'CCS1' AND v_vehicle_inlet = 'CCS1')
     OR (v_stall_conn = 'NACS' AND v_vehicle_inlet = 'NACS')
     OR (v_stall_conn = 'NACS' AND v_vehicle_inlet = 'Tesla_Proprietary')
     OR (v_stall_conn = 'Tesla_Proprietary' AND v_vehicle_inlet = 'NACS') THEN
    RETURN ROW(TRUE,
      format('known-compatible pair: stall=%s vehicle=%s', v_stall_conn, v_vehicle_inlet),
      NULL,
      jsonb_build_object('stall_connector', v_stall_conn, 'vehicle_inlet', v_vehicle_inlet),
      NULL
    )::ottoq_rule_result;
  END IF;

  -- Mismatch
  RETURN ROW(FALSE,
    format('connector mismatch: stall=%s, vehicle inlet=%s', v_stall_conn, v_vehicle_inlet),
    'safety_critical',
    jsonb_build_object(
      'stall_connector', v_stall_conn,
      'vehicle_inlet', v_vehicle_inlet
    ),
    'reroute_to_compatible_stall'
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_hw_002_charger_state =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_hw_002_charger_state(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_charger_id     UUID;
  v_stall_id       UUID;
  v_charger        ottoq_ocpp_chargers%ROWTYPE;
  v_now            TIMESTAMPTZ := COALESCE(NULLIF(p_context ->> 'now_ts','')::timestamptz, NOW());  -- WIRE-3
  v_max_offline_s  INTEGER := COALESCE((p_parameters ->> 'max_offline_seconds')::INT, 90);
  v_allowed_states TEXT[] := COALESCE(ARRAY(SELECT jsonb_array_elements_text(p_parameters -> 'allowed_states')), ARRAY['Available']);
BEGIN
  v_charger_id := NULLIF(p_context ->> 'charger_id', '')::UUID;
  v_stall_id   := NULLIF(p_context ->> 'stall_id', '')::UUID;
  IF v_charger_id IS NULL AND v_stall_id IS NOT NULL THEN
    SELECT ocpp_charger_id INTO v_charger_id FROM stalls WHERE id = v_stall_id;
  END IF;
  IF v_charger_id IS NULL THEN
    RETURN ROW(TRUE, 'no charger bound to stall (non-charging context)', NULL,
      jsonb_build_object('stall_id', v_stall_id, 'charger_id', NULL), NULL)::ottoq_rule_result;
  END IF;
  SELECT * INTO v_charger FROM ottoq_ocpp_chargers WHERE charger_id = v_charger_id;
  IF NOT FOUND THEN
    RETURN ROW(FALSE, format('charger %s not registered in ottoq_ocpp_chargers', v_charger_id),
      'safety_critical', jsonb_build_object('charger_id', v_charger_id), 'register_charger')::ottoq_rule_result;
  END IF;
  IF v_charger.last_heartbeat_at IS NULL
     OR v_charger.last_heartbeat_at < v_now - (v_max_offline_s || ' seconds')::INTERVAL THEN   -- WIRE-3: v_now
    RETURN ROW(FALSE, format('charger %s offline (last heartbeat: %s)', v_charger.ocpp_identifier, COALESCE(v_charger.last_heartbeat_at::text, 'never')),
      'critical', jsonb_build_object('charger_id', v_charger_id, 'ocpp_identifier', v_charger.ocpp_identifier,
        'last_heartbeat_at', v_charger.last_heartbeat_at, 'max_offline_seconds', v_max_offline_s, 'now_ts', v_now),
      'wait_for_charger_reconnect_or_reroute')::ottoq_rule_result;
  END IF;
  IF NOT (v_charger.station_state = ANY(v_allowed_states)) THEN
    RETURN ROW(FALSE, format('charger state=%s not in allowed states %s', v_charger.station_state, array_to_string(v_allowed_states, ',')),
      CASE WHEN v_charger.station_state = 'Faulted' THEN 'safety_critical' ELSE 'error' END,
      jsonb_build_object('charger_id', v_charger_id, 'state', v_charger.station_state, 'state_changed_at', v_charger.station_state_changed_at,
        'allowed_states', v_allowed_states, 'last_fault_code', v_charger.last_fault_code),
      CASE WHEN v_charger.station_state IN ('Faulted', 'Maintenance') THEN 'reroute_to_alternate_charger' ELSE 'wait_for_availability' END)::ottoq_rule_result;
  END IF;
  RETURN ROW(TRUE, format('charger %s available and online', v_charger.ocpp_identifier), NULL,
    jsonb_build_object('charger_id', v_charger_id, 'state', v_charger.station_state), NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_hw_003_sensor_liveness =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_hw_003_sensor_liveness(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_vehicle_id        UUID;
  v_soc_updated_at    TIMESTAMPTZ;
  v_now               TIMESTAMPTZ := COALESCE(NULLIF(p_context ->> 'now_ts','')::timestamptz, NOW());  -- WIRE-3
  v_max_stale_seconds INTEGER := COALESCE((p_parameters ->> 'max_stale_seconds')::INT, 300);
  v_age_seconds       NUMERIC;
  v_svc               TEXT := lower(coalesce(p_context ->> 'service_code', p_context ->> 'service', ''));
  v_req_charge        TEXT := p_context ->> 'requires_charging';
BEGIN
  -- SCOPE GUARD (charge-only rule): SOC liveness gates CHARGE-RELATED decisions only.
  -- A non-charging task transition (inspection / wash / staging) does not depend on SOC
  -- freshness. Charging task_starts and redeployment carry no such flag and remain FULLY
  -- gated (stale SOC still blocks them). The rule still runs and records this N/A verdict.
  IF v_req_charge = 'false'
     OR (v_svc <> '' AND v_svc NOT IN ('charge','dcfc_charge','l2_charge','charging','fast_charge','dc_fast_charge')) THEN
    RETURN ROW(TRUE,
      format('non-charging action (%s): SOC liveness N/A', COALESCE(NULLIF(v_svc,''),'flagged')),
      NULL, jsonb_build_object('service', v_svc, 'requires_charging', v_req_charge), NULL)::ottoq_rule_result;
  END IF;

  v_vehicle_id := COALESCE(NULLIF(p_context ->> 'vehicle_id', '')::UUID, CASE WHEN p_entity_type = 'vehicle' THEN p_entity_id END);
  IF v_vehicle_id IS NULL THEN
    RETURN ROW(TRUE, 'no vehicle context; skipping liveness check', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;
  SELECT current_soc_updated_at INTO v_soc_updated_at FROM vehicles WHERE id = v_vehicle_id;
  IF v_soc_updated_at IS NULL THEN
    RETURN ROW(FALSE, 'vehicle has no current_soc_updated_at; SOC liveness unknown', 'error',
      jsonb_build_object('vehicle_id', v_vehicle_id), 'populate_soc_telemetry')::ottoq_rule_result;
  END IF;
  v_age_seconds := EXTRACT(EPOCH FROM (v_now - v_soc_updated_at));   -- WIRE-3: v_now
  IF v_age_seconds > v_max_stale_seconds THEN
    RETURN ROW(FALSE, format('SOC sensor stale: %s seconds old (threshold %s)', round(v_age_seconds)::TEXT, v_max_stale_seconds),
      'safety_critical', jsonb_build_object('vehicle_id', v_vehicle_id, 'soc_updated_at', v_soc_updated_at,
        'age_seconds', v_age_seconds, 'max_stale_seconds', v_max_stale_seconds, 'now_ts', v_now), 'wait_for_fresh_telemetry')::ottoq_rule_result;
  END IF;
  RETURN ROW(TRUE, format('SOC fresh: %s seconds old', round(v_age_seconds)::TEXT), NULL,
    jsonb_build_object('age_seconds', v_age_seconds), NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_hw_004_stall_concurrency =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_hw_004_stall_concurrency(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_stall_id         UUID;
  v_proposed_vehicle UUID;
  v_current_vehicle  UUID;
  v_reserved_by      UUID;
  v_res_expires      TIMESTAMPTZ;
  v_now              TIMESTAMPTZ := COALESCE(NULLIF(p_context->>'now_ts','')::timestamptz, NOW());
BEGIN
  v_stall_id := COALESCE(NULLIF(p_context ->> 'stall_id','')::UUID, CASE WHEN p_entity_type='stall' THEN p_entity_id END);
  v_proposed_vehicle := NULLIF(p_context ->> 'vehicle_id','')::UUID;
  IF v_stall_id IS NULL THEN
    RETURN ROW(TRUE, 'no stall context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  SELECT current_vehicle_id, reserved_by, reservation_expires_at
    INTO v_current_vehicle, v_reserved_by, v_res_expires
    FROM stalls WHERE id = v_stall_id;

  -- occupied by a DIFFERENT vehicle → block
  IF v_current_vehicle IS NOT NULL AND v_current_vehicle <> COALESCE(v_proposed_vehicle, v_current_vehicle) THEN
    RETURN ROW(FALSE, format('stall %s already occupied by %s', v_stall_id, v_current_vehicle),
      'critical', jsonb_build_object('stall_id', v_stall_id, 'current_vehicle_id', v_current_vehicle), 'choose_another_stall')::ottoq_rule_result;
  END IF;

  -- SUB-2: live reservation held by a DIFFERENT vehicle → block (the OFFERED→DOCKED window)
  IF v_reserved_by IS NOT NULL AND v_reserved_by <> COALESCE(v_proposed_vehicle, v_reserved_by)
     AND (v_res_expires IS NULL OR v_res_expires > v_now) THEN
    RETURN ROW(FALSE, format('stall %s reserved by %s until %s', v_stall_id, v_reserved_by, v_res_expires),
      'critical', jsonb_build_object('stall_id', v_stall_id, 'reserved_by', v_reserved_by, 'reservation_expires_at', v_res_expires), 'choose_another_stall')::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE, 'stall available', NULL, jsonb_build_object('stall_id', v_stall_id), NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_hw_005_vehicle_one_task =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_hw_005_vehicle_one_task(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_vehicle_id   UUID;
  v_active_count INTEGER;
  v_active_ids   UUID[];
BEGIN
  v_vehicle_id := COALESCE(NULLIF(p_context ->> 'vehicle_id','')::UUID, CASE WHEN p_entity_type='vehicle' THEN p_entity_id END);
  IF v_vehicle_id IS NULL THEN
    RETURN ROW(TRUE, 'no vehicle context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  SELECT count(*), array_agg(id) INTO v_active_count, v_active_ids
    FROM schedule_tasks
   WHERE vehicle_id = v_vehicle_id
     AND status IN ('in_progress','vehicle_en_route');   -- H4: real enum values

  IF COALESCE(v_active_count,0) > 1 THEN
    RETURN ROW(FALSE, format('vehicle has %s simultaneously active tasks', v_active_count),
      'critical', jsonb_build_object('vehicle_id', v_vehicle_id, 'active_count', v_active_count, 'active_task_ids', to_jsonb(v_active_ids)),
      'serialize_tasks')::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE, format('vehicle has %s active task(s)', COALESCE(v_active_count,0)),
    NULL, jsonb_build_object('active_count', COALESCE(v_active_count,0)), NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_hw_006_presence_verification =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_hw_006_presence_verification(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_stall_id      UUID;
  v_vehicle_id    UUID;
  v_require_chg   BOOLEAN := COALESCE((p_parameters ->> 'require_charging_signal')::BOOLEAN, FALSE);
  v_stall_current UUID;
BEGIN
  v_stall_id   := NULLIF(p_context ->> 'stall_id', '')::UUID;
  v_vehicle_id := NULLIF(p_context ->> 'vehicle_id', '')::UUID;

  IF v_stall_id IS NULL OR v_vehicle_id IS NULL THEN
    -- Without both, we can't verify; pass through with warning
    RETURN ROW(TRUE, 'insufficient context for presence verification',
      'warning',
      jsonb_build_object('stall_id', v_stall_id, 'vehicle_id', v_vehicle_id),
      NULL
    )::ottoq_rule_result;
  END IF;

  BEGIN
    EXECUTE 'SELECT current_vehicle_id FROM stalls WHERE id = $1'
      INTO v_stall_current USING v_stall_id;
  EXCEPTION WHEN undefined_column THEN
    RETURN ROW(TRUE, 'stalls.current_vehicle_id not present',
      NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END;

  IF v_stall_current IS DISTINCT FROM v_vehicle_id THEN
    RETURN ROW(FALSE,
      'system state mismatch: stall does not record this vehicle as present',
      'critical',
      jsonb_build_object(
        'stall_id', v_stall_id,
        'expected_vehicle_id', v_vehicle_id,
        'stall_current_vehicle_id', v_stall_current
      ),
      'reconcile_state_or_dispatch_tech_check'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE, 'vehicle presence confirmed at stall',
    NULL,
    jsonb_build_object('stall_id', v_stall_id, 'vehicle_id', v_vehicle_id),
    NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_sla_001_min_soc_at_deployment =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sla_001_min_soc_at_deployment(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_vehicle_id    UUID;
  v_fleet_op_id   UUID;
  v_current_soc   NUMERIC;
  v_sla           ottoq_fleet_operator_slas;
  v_min_floor     NUMERIC;
BEGIN
  v_vehicle_id  := COALESCE(NULLIF(p_context ->> 'vehicle_id','')::UUID,
                            CASE WHEN p_entity_type = 'vehicle' THEN p_entity_id END);
  v_fleet_op_id := NULLIF(p_context ->> 'fleet_operator_id','')::UUID;
  v_current_soc := NULLIF(p_context ->> 'current_soc_pct','')::NUMERIC;

  IF v_vehicle_id IS NULL OR v_fleet_op_id IS NULL THEN
    RETURN ROW(TRUE, 'missing vehicle or fleet_operator context', NULL,
      '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  -- Pull live SOC if not in context
  IF v_current_soc IS NULL THEN
    BEGIN
      EXECUTE 'SELECT current_soc FROM vehicles WHERE id = $1'
        INTO v_current_soc USING v_vehicle_id;
    EXCEPTION WHEN undefined_column THEN NULL;
    END;
  END IF;

  v_sla := ottoq_get_active_sla(v_fleet_op_id);

  -- Floor precedence: parameter override → SLA → default
  v_min_floor := COALESCE(
    (p_parameters ->> 'min_soc_pct')::NUMERIC,
    v_sla.min_soc_at_deployment_pct,
    80.0
  );

  IF v_current_soc IS NULL THEN
    RETURN ROW(FALSE,
      'cannot evaluate: vehicle SOC unknown',
      'error',
      jsonb_build_object('vehicle_id', v_vehicle_id),
      'populate_soc_telemetry'
    )::ottoq_rule_result;
  END IF;

  IF v_current_soc < v_min_floor THEN
    RETURN ROW(FALSE,
      format('SOC %s%% below SLA floor %s%%', v_current_soc, v_min_floor),
      'critical',
      jsonb_build_object(
        'vehicle_id', v_vehicle_id,
        'fleet_operator_id', v_fleet_op_id,
        'current_soc_pct', v_current_soc,
        'min_floor_pct', v_min_floor,
        'sla_contract_reference', v_sla.contract_reference
      ),
      'continue_charging_to_floor'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,
    format('SOC %s%% meets floor %s%%', v_current_soc, v_min_floor),
    NULL,
    jsonb_build_object('current_soc', v_current_soc, 'floor', v_min_floor),
    NULL
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_sla_002_max_queue_depth =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sla_002_max_queue_depth(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_fleet_op_id  UUID;
  v_depot_id     UUID;
  v_sla          ottoq_fleet_operator_slas;
  v_max_depth    INTEGER;
  v_current      INTEGER;
BEGIN
  v_fleet_op_id := NULLIF(p_context ->> 'fleet_operator_id','')::UUID;
  v_depot_id    := NULLIF(p_context ->> 'depot_id','')::UUID;

  IF v_fleet_op_id IS NULL OR v_depot_id IS NULL THEN
    RETURN ROW(TRUE, 'missing fleet_operator/depot context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  v_sla := ottoq_get_active_sla(v_fleet_op_id);
  v_max_depth := COALESCE(
    (p_parameters ->> 'max_depth')::INTEGER,
    v_sla.max_queue_depth,
    50
  );

  BEGIN
    EXECUTE 'SELECT count(*) FROM vehicles
              WHERE fleet_operator_id = $1
                AND current_state IN (''queued'', ''waiting_assignment'')'
      INTO v_current USING v_fleet_op_id;
  EXCEPTION WHEN undefined_column THEN
    v_current := 0;
  END;

  IF v_current >= v_max_depth THEN
    RETURN ROW(FALSE,
      format('queue depth %s ≥ SLA max %s', v_current, v_max_depth),
      'warning',
      jsonb_build_object('current', v_current, 'max', v_max_depth,
                         'fleet_operator_id', v_fleet_op_id,
                         'depot_id', v_depot_id),
      'defer_new_arrivals_or_scale_capacity'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,
    format('queue depth %s of %s allowed', v_current, v_max_depth),
    NULL,
    jsonb_build_object('current', v_current, 'max', v_max_depth),
    NULL
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_sla_003_max_visit_duration =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sla_003_max_visit_duration(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_schedule_id   UUID;
  v_fleet_op_id   UUID;
  v_arrival_at    TIMESTAMPTZ;
  v_sla           ottoq_fleet_operator_slas;
  v_max_minutes   INTEGER;
  v_elapsed_min   NUMERIC;
BEGIN
  v_schedule_id := COALESCE(NULLIF(p_context ->> 'schedule_id','')::UUID,
                            CASE WHEN p_entity_type = 'schedule' THEN p_entity_id END);
  v_fleet_op_id := NULLIF(p_context ->> 'fleet_operator_id','')::UUID;
  v_arrival_at  := NULLIF(p_context ->> 'arrival_at','')::TIMESTAMPTZ;

  IF v_schedule_id IS NULL OR v_fleet_op_id IS NULL THEN
    RETURN ROW(TRUE, 'missing context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  v_sla := ottoq_get_active_sla(v_fleet_op_id);
  v_max_minutes := COALESCE(
    (p_parameters ->> 'max_minutes')::INTEGER,
    v_sla.max_visit_duration_minutes,
    180
  );

  IF v_arrival_at IS NULL THEN
    BEGIN
      EXECUTE 'SELECT created_at FROM vehicle_schedules WHERE id = $1'
        INTO v_arrival_at USING v_schedule_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  IF v_arrival_at IS NULL THEN
    RETURN ROW(TRUE, 'no arrival_at; cannot evaluate', 'warning', '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  v_elapsed_min := EXTRACT(EPOCH FROM (NOW() - v_arrival_at)) / 60.0;

  IF v_elapsed_min > v_max_minutes THEN
    RETURN ROW(FALSE,
      format('visit elapsed %s min > SLA max %s min', v_elapsed_min, v_max_minutes),
      'warning',
      jsonb_build_object(
        'schedule_id', v_schedule_id,
        'arrival_at', v_arrival_at,
        'elapsed_minutes', v_elapsed_min,
        'max_minutes', v_max_minutes,
        'sla_contract_reference', v_sla.contract_reference
      ),
      'escalate_or_expedite'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,
    format('within SLA: %s / %s min', v_elapsed_min, v_max_minutes),
    NULL,
    jsonb_build_object('elapsed_minutes', v_elapsed_min, 'max_minutes', v_max_minutes),
    NULL
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_sla_004_required_services =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sla_004_required_services(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_vehicle_id UUID; v_schedule_id UUID; v_fleet_op_id UUID;
  v_sla ottoq_fleet_operator_slas; v_atoms JSONB; v_needs_id UUID;
  v_required TEXT[]; v_completed TEXT[]; v_missing TEXT[];
  v_soc NUMERIC; v_chg_target NUMERIC; v_tol NUMERIC;
  v_pending TEXT[]; v_charge_short BOOLEAN := false;
BEGIN
  v_vehicle_id  := COALESCE(NULLIF(p_context ->> 'vehicle_id','')::UUID,
                            CASE WHEN p_entity_type = 'vehicle' THEN p_entity_id END);
  v_schedule_id := COALESCE(NULLIF(p_context ->> 'schedule_id','')::UUID,
                            CASE WHEN p_entity_type = 'schedule' THEN p_entity_id END);
  v_fleet_op_id := NULLIF(p_context ->> 'fleet_operator_id','')::UUID;
  v_tol := COALESCE((p_parameters ->> 'charge_tolerance_pct')::NUMERIC, 1.0);

  ---------------------------------------------------------------------------
  -- PRIMARY PATH: the vehicle's OPEN visit manifest (appointment doctrine)
  ---------------------------------------------------------------------------
  IF v_vehicle_id IS NOT NULL THEN
    SELECT vn.visit_id, vn.atoms INTO v_needs_id, v_atoms
      FROM ottoq_visit_needs vn
     WHERE vn.vehicle_id = v_vehicle_id AND vn.status IN ('open','in_progress')
     ORDER BY vn.created_at DESC NULLS LAST LIMIT 1;

    IF v_atoms IS NOT NULL AND jsonb_typeof(v_atoms) = 'array' THEN
      SELECT current_soc INTO v_soc FROM vehicles WHERE id = v_vehicle_id;

      -- every must_do atom that is not yet done blocks redeployment
      SELECT array_agg(a->>'svc' ORDER BY a->>'svc')
        INTO v_pending
        FROM jsonb_array_elements(v_atoms) a
       WHERE COALESCE((a->>'must_do')::boolean, true)
         AND NOT COALESCE((a->>'deferrable')::boolean, false)
         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped');

      -- FULL-CHARGE DOCTRINE: a charge atom marked done still fails the gate if the
      -- measured SoC never reached its planned target (guards a mis-stamped atom).
      SELECT (a->>'target_soc')::NUMERIC INTO v_chg_target
        FROM jsonb_array_elements(v_atoms) a
       WHERE a->>'svc' = 'charge'
         AND COALESCE(a->>'status','pending') <> 'cancelled'
       LIMIT 1;

      IF v_chg_target IS NOT NULL AND v_soc IS NOT NULL AND v_soc < v_chg_target - v_tol THEN
        v_charge_short := true;
      END IF;

      IF COALESCE(cardinality(v_pending),0) > 0 OR v_charge_short THEN
        RETURN ROW(FALSE,
          format('visit incomplete: %s%s',
                 COALESCE(array_to_string(v_pending,','),'-'),
                 CASE WHEN v_charge_short
                      THEN format(' | charge %s%% < target %s%%', ROUND(v_soc,1), v_chg_target)
                      ELSE '' END),
          'critical',
          jsonb_build_object('vehicle_id', v_vehicle_id, 'visit_needs_id', v_needs_id,
            'pending_must_do', COALESCE(v_pending, ARRAY[]::text[]),
            'charge_target_soc', v_chg_target, 'current_soc', v_soc,
            'charge_short', v_charge_short, 'source', 'visit_manifest'),
          'complete_visit_manifest'
        )::ottoq_rule_result;
      END IF;

      RETURN ROW(TRUE, 'visit manifest complete (all must-do atoms done)', NULL,
        jsonb_build_object('vehicle_id', v_vehicle_id, 'visit_needs_id', v_needs_id,
          'charge_target_soc', v_chg_target, 'current_soc', v_soc, 'source','visit_manifest'),
        NULL)::ottoq_rule_result;
    END IF;
  END IF;

  ---------------------------------------------------------------------------
  -- FALLBACK: legacy schedule_tasks path (no open visit manifest for this vehicle)
  ---------------------------------------------------------------------------
  IF v_schedule_id IS NULL OR v_fleet_op_id IS NULL THEN
    RETURN ROW(TRUE, 'no visit manifest and no schedule/fleet context', NULL,
      jsonb_build_object('vehicle_id', v_vehicle_id, 'source','none'), NULL)::ottoq_rule_result;
  END IF;

  v_sla := ottoq_get_active_sla(v_fleet_op_id);
  -- NULLIF(...,'{}') is the defect fix: an empty array must fall through to the SLA.
  v_required := COALESCE(
    NULLIF(ARRAY(SELECT jsonb_array_elements_text(p_parameters -> 'required_services')), '{}'),
    NULLIF(v_sla.required_services_before_deploy, '{}'),
    ARRAY['charge']);

  BEGIN
    EXECUTE 'SELECT array_agg(DISTINCT service_code) FROM schedule_tasks
              WHERE schedule_id = $1 AND status = ''completed'''
      INTO v_completed USING v_schedule_id;
  EXCEPTION WHEN undefined_column THEN
    BEGIN
      EXECUTE 'SELECT array_agg(DISTINCT service_type) FROM schedule_tasks
                WHERE schedule_id = $1 AND status = ''completed'''
        INTO v_completed USING v_schedule_id;
    EXCEPTION WHEN OTHERS THEN v_completed := '{}';
    END;
  END;
  v_completed := COALESCE(v_completed, '{}'::text[]);
  SELECT array_agg(req) INTO v_missing FROM unnest(v_required) AS req WHERE req <> ALL(v_completed);

  IF v_missing IS NOT NULL AND cardinality(v_missing) > 0 THEN
    RETURN ROW(FALSE, format('required services not complete: %s', array_to_string(v_missing, ',')),
      'critical',
      jsonb_build_object('required', v_required, 'completed', v_completed,
        'missing', v_missing, 'source','schedule_tasks',
        'sla_contract_reference', v_sla.contract_reference),
      'complete_missing_services')::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE, format('all %s required services complete', cardinality(v_required)), NULL,
    jsonb_build_object('required', v_required, 'completed', v_completed, 'source','schedule_tasks'),
    NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_sla_005_oem_acceptance_timing =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sla_005_oem_acceptance_timing(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_task_id        UUID;
  v_fleet_op_id    UUID;
  v_sla            ottoq_fleet_operator_slas;
  v_required       BOOLEAN;
  v_timeout_s      INTEGER;
  v_on_timeout     TEXT;
  v_mode           TEXT;
BEGIN
  v_task_id     := COALESCE(NULLIF(p_context ->> 'task_id','')::UUID,
                            CASE WHEN p_entity_type = 'task' THEN p_entity_id END);
  v_fleet_op_id := NULLIF(p_context ->> 'fleet_operator_id','')::UUID;

  IF v_fleet_op_id IS NULL THEN
    RETURN ROW(TRUE, 'no fleet_operator context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  v_sla := ottoq_get_active_sla(v_fleet_op_id);
  v_required  := COALESCE((p_parameters ->> 'required')::BOOLEAN, v_sla.oem_acceptance_required, TRUE);
  v_timeout_s := COALESCE((p_parameters ->> 'timeout_seconds')::INT, v_sla.oem_acceptance_timeout_seconds, 180);
  v_on_timeout := COALESCE(p_parameters ->> 'on_timeout', v_sla.oem_acceptance_on_timeout, 'auto_accept');
  v_mode      := COALESCE(p_parameters ->> 'mode', v_sla.oem_acceptance_mode, 'oem_webhook_final_only');

  -- Informational: this rule mostly *configures* the gate behavior. It passes
  -- as long as configuration is present and consistent. Actual gate timing
  -- enforcement happens in the progression control engine, which reads
  -- ottoq_get_active_sla() to drive its behavior.

  RETURN ROW(TRUE,
    format('OEM gate configured: mode=%s timeout=%ss on_timeout=%s', v_mode, v_timeout_s, v_on_timeout),
    NULL,
    jsonb_build_object(
      'required', v_required,
      'mode', v_mode,
      'timeout_seconds', v_timeout_s,
      'on_timeout', v_on_timeout,
      'contract_reference', v_sla.contract_reference
    ),
    NULL
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_sla_006_maintenance_window =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sla_006_maintenance_window(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_fleet_op_id  UUID;
  v_service_code TEXT;
  v_sla          ottoq_fleet_operator_slas;
  v_now_time     TIME;
  v_in_window    BOOLEAN;
  v_maint_kinds  TEXT[] := COALESCE(
    ARRAY(SELECT jsonb_array_elements_text(p_parameters -> 'maintenance_services')),
    ARRAY['deep_clean','battery_diagnostic','tire_rotation','brake_inspection','calibration_deep','firmware_update','suspension_check']
  );
BEGIN
  v_fleet_op_id  := NULLIF(p_context ->> 'fleet_operator_id','')::UUID;
  v_service_code := p_context ->> 'service_code';

  IF v_fleet_op_id IS NULL OR v_service_code IS NULL THEN
    RETURN ROW(TRUE, 'no context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  -- Only applies to maintenance-class services
  IF NOT (v_service_code = ANY(v_maint_kinds)) THEN
    RETURN ROW(TRUE,
      format('service %s is not maintenance-class', v_service_code),
      NULL,
      jsonb_build_object('service_code', v_service_code),
      NULL
    )::ottoq_rule_result;
  END IF;

  v_sla := ottoq_get_active_sla(v_fleet_op_id);
  IF v_sla.allow_maintenance_during_peak THEN
    RETURN ROW(TRUE, 'SLA permits maintenance during peak', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  IF v_sla.maintenance_window_start IS NULL OR v_sla.maintenance_window_end IS NULL THEN
    RETURN ROW(TRUE, 'no maintenance window configured', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  v_now_time := (NOW() AT TIME ZONE 'UTC')::TIME;

  -- Window may cross midnight
  IF v_sla.maintenance_window_start <= v_sla.maintenance_window_end THEN
    v_in_window := v_now_time BETWEEN v_sla.maintenance_window_start AND v_sla.maintenance_window_end;
  ELSE
    v_in_window := v_now_time >= v_sla.maintenance_window_start
                OR v_now_time <= v_sla.maintenance_window_end;
  END IF;

  IF NOT v_in_window THEN
    RETURN ROW(FALSE,
      format('service %s outside maintenance window [%s, %s] (now: %s UTC)',
        v_service_code, v_sla.maintenance_window_start, v_sla.maintenance_window_end, v_now_time),
      'warning',
      jsonb_build_object(
        'service_code', v_service_code,
        'window_start', v_sla.maintenance_window_start,
        'window_end', v_sla.maintenance_window_end,
        'now_utc', v_now_time,
        'contract_reference', v_sla.contract_reference
      ),
      'defer_to_maintenance_window'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE, 'within maintenance window', NULL,
    jsonb_build_object('now_utc', v_now_time, 'window_start', v_sla.maintenance_window_start),
    NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_sla_007_redeployment_readiness =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sla_007_redeployment_readiness(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_vehicle_id      UUID;
  v_schedule_id     UUID;
  v_fleet_op_id     UUID;
  v_blockers        JSONB := '[]'::jsonb;
  v_open_exceptions INTEGER := 0;
  v_blocker_count   INTEGER := 0;
BEGIN
  v_vehicle_id  := NULLIF(p_context ->> 'vehicle_id','')::UUID;
  v_schedule_id := NULLIF(p_context ->> 'schedule_id','')::UUID;
  v_fleet_op_id := NULLIF(p_context ->> 'fleet_operator_id','')::UUID;

  IF v_vehicle_id IS NULL THEN
    RETURN ROW(TRUE, 'no vehicle context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  -- Open exceptions blocking progression
  BEGIN
    EXECUTE '
      SELECT count(*) FROM exceptions e
       JOIN schedule_tasks t ON e.task_id = t.id
      WHERE t.vehicle_id = $1
        AND e.status IN (''open'', ''flagged'')
        AND e.blocks_progression = TRUE
    ' INTO v_open_exceptions USING v_vehicle_id;
  EXCEPTION WHEN OTHERS THEN
    v_open_exceptions := 0;
  END;

  IF v_open_exceptions > 0 THEN
    v_blockers := v_blockers || jsonb_build_object(
      'reason', 'open_blocking_exceptions',
      'count', v_open_exceptions
    );
    v_blocker_count := v_blocker_count + 1;
  END IF;

  -- Note: SOC, services, sensor liveness are independent rules and run
  -- alongside this one in ottoq_evaluate_rules_for_action('redeployment').
  -- This rule focuses on exceptions + composite summary.

  IF v_blocker_count > 0 THEN
    RETURN ROW(FALSE,
      format('%s blocker(s) preventing redeployment', v_blocker_count),
      'critical',
      jsonb_build_object(
        'vehicle_id', v_vehicle_id,
        'schedule_id', v_schedule_id,
        'blockers', v_blockers
      ),
      'resolve_blockers'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,
    'no open blocking exceptions',
    NULL,
    jsonb_build_object('vehicle_id', v_vehicle_id),
    NULL
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_sm_001_vehicle_transition =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sm_001_vehicle_transition(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT * FROM ottoq_eval_sm_transition_validity('vehicle', p_entity_type, p_entity_id, p_context, p_parameters);
$function$

-- ===== ottoq_eval_sm_002_task_transition =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sm_002_task_transition(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT * FROM ottoq_eval_sm_transition_validity('task', p_entity_type, p_entity_id, p_context, p_parameters);
$function$

-- ===== ottoq_eval_sm_003_stall_transition =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sm_003_stall_transition(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT * FROM ottoq_eval_sm_transition_validity('stall', p_entity_type, p_entity_id, p_context, p_parameters);
$function$

-- ===== ottoq_eval_sm_004_role_gating =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sm_004_role_gating(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_actor_type      TEXT;
  v_action          TEXT;
  v_allowed_actors  TEXT[];
BEGIN
  v_actor_type := COALESCE(
    p_context ->> 'actor_type',
    NULLIF(current_setting('ottoq.actor_type', TRUE), ''),
    'unknown'
  );
  v_action := p_context ->> 'action';

  -- Action-to-roles map (parameterized; safe defaults baked in)
  v_allowed_actors := COALESCE(
    ARRAY(SELECT jsonb_array_elements_text(p_parameters -> 'allowed_actors')),
    CASE v_action
      WHEN 'tech_override'    THEN ARRAY['depot_tech','depot_supervisor']
      WHEN 'flag_abnormality' THEN ARRAY['depot_tech','depot_supervisor','oem_admin_console','oem_dispatch_webhook']
      WHEN 'resolve_abnormality_tech' THEN ARRAY['depot_tech','depot_supervisor']
      WHEN 'resolve_abnormality_oem'  THEN ARRAY['depot_tech','depot_supervisor','oem_admin_console']
      WHEN 'oem_accept'       THEN ARRAY['oem_dispatch_webhook','oem_admin_console']
      WHEN 'oem_flag_midflow' THEN ARRAY['oem_admin_console','oem_dispatch_webhook']
      WHEN 'emergency_stop'   THEN ARRAY['depot_supervisor','command_center_operator','external_sensor']
      WHEN 'brain_pause'      THEN ARRAY['command_center_operator','depot_supervisor']
      ELSE ARRAY[]::TEXT[]
    END
  );

  IF cardinality(v_allowed_actors) = 0 THEN
    RETURN ROW(TRUE, 'no role restriction for action', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  IF NOT (v_actor_type = ANY(v_allowed_actors)) THEN
    RETURN ROW(FALSE,
      format('actor %s not authorized for action %s', v_actor_type, v_action),
      'critical',
      jsonb_build_object(
        'actor_type', v_actor_type,
        'action', v_action,
        'allowed_actors', v_allowed_actors
      ),
      'use_authorized_actor'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE, format('actor %s authorized for %s', v_actor_type, v_action), NULL,
    jsonb_build_object('actor_type', v_actor_type, 'action', v_action), NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_sm_005_audit_note_required =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sm_005_audit_note_required(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_decision     TEXT;
  v_audit_note   TEXT;
  v_min_chars    INTEGER := COALESCE((p_parameters ->> 'min_chars')::INT, 3);
  v_override_decisions TEXT[] := ARRAY[
    'tech_override_skip','tech_override_reroute','tech_override_hold',
    'tech_override_flag_exception','tech_override_defer','tech_override_escalate',
    'oem_rejected','oem_flagged_mid_flow','abnormality_blocked','abnormality_resolved'
  ];
BEGIN
  v_decision   := p_context ->> 'decision';
  v_audit_note := p_context ->> 'audit_note';

  IF v_decision IS NULL THEN
    RETURN ROW(TRUE, 'no decision context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  IF NOT (v_decision = ANY(v_override_decisions)) THEN
    RETURN ROW(TRUE, 'decision not in override class', NULL,
      jsonb_build_object('decision', v_decision), NULL)::ottoq_rule_result;
  END IF;

  IF v_audit_note IS NULL OR length(trim(v_audit_note)) < v_min_chars THEN
    RETURN ROW(FALSE,
      format('audit_note required (min %s chars) for decision=%s', v_min_chars, v_decision),
      'critical',
      jsonb_build_object(
        'decision', v_decision,
        'audit_note_length', COALESCE(length(trim(v_audit_note)),0),
        'min_chars', v_min_chars
      ),
      'provide_substantive_audit_note'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,
    format('audit_note present (%s chars)', length(trim(v_audit_note))),
    NULL,
    jsonb_build_object('audit_note_length', length(trim(v_audit_note))),
    NULL
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_sm_transition_validity =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_sm_transition_validity(p_entity_kind text, p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_from_state  TEXT;
  v_to_state    TEXT;
  v_actor_type  TEXT;
  v_trans       ottoq_state_transitions%ROWTYPE;
  v_role_ok     BOOLEAN;
BEGIN
  v_from_state := p_context ->> 'from_state';
  v_to_state   := p_context ->> 'to_state';
  v_actor_type := COALESCE(
    p_context ->> 'actor_type',
    NULLIF(current_setting('ottoq.actor_type', TRUE), ''),
    'unknown'
  );

  IF v_from_state IS NULL OR v_to_state IS NULL THEN
    RETURN ROW(TRUE, 'no transition context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  -- Allow no-op transitions (state set to itself)
  IF v_from_state = v_to_state THEN
    RETURN ROW(TRUE, 'no-op transition', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  SELECT * INTO v_trans
    FROM ottoq_state_transitions
   WHERE entity_kind = p_entity_kind
     AND from_state = v_from_state
     AND to_state   = v_to_state
     AND status = 'active';

  IF NOT FOUND THEN
    RETURN ROW(FALSE,
      format('invalid transition for %s: %s → %s', p_entity_kind, v_from_state, v_to_state),
      'critical',
      jsonb_build_object(
        'entity_kind', p_entity_kind,
        'from_state', v_from_state,
        'to_state', v_to_state,
        'actor_type', v_actor_type
      ),
      'review_state_machine_or_use_valid_transition'
    )::ottoq_rule_result;
  END IF;

  -- Role gate
  IF cardinality(v_trans.allowed_actor_types) > 0
     AND NOT (v_actor_type = ANY(v_trans.allowed_actor_types)) THEN
    RETURN ROW(FALSE,
      format('actor %s not authorized for %s transition %s → %s',
        v_actor_type, p_entity_kind, v_from_state, v_to_state),
      'critical',
      jsonb_build_object(
        'actor_type', v_actor_type,
        'allowed_actor_types', v_trans.allowed_actor_types,
        'transition', v_from_state || '→' || v_to_state
      ),
      'escalate_or_use_authorized_actor'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,
    format('transition allowed: %s → %s by %s', v_from_state, v_to_state, v_actor_type),
    NULL,
    jsonb_build_object(
      'transition_id', v_trans.transition_id,
      'actor_type', v_actor_type
    ),
    NULL
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_tw_001_operational_hours =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_tw_001_operational_hours(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot_id   UUID;
  v_depot      depots%ROWTYPE;
  v_local_time TIME;
  v_in_hours   BOOLEAN;
BEGIN
  v_depot_id := COALESCE(NULLIF(p_context ->> 'depot_id','')::UUID,
                         CASE WHEN p_entity_type='depot' THEN p_entity_id END);
  IF v_depot_id IS NULL THEN
    RETURN ROW(TRUE,'no depot context',NULL,'{}'::jsonb,NULL)::ottoq_rule_result;
  END IF;

  SELECT * INTO v_depot FROM depots WHERE id = v_depot_id;
  IF v_depot.operational_hours_start IS NULL OR v_depot.operational_hours_end IS NULL THEN
    RETURN ROW(TRUE,'depot operates 24/7',NULL,'{}'::jsonb,NULL)::ottoq_rule_result;
  END IF;

  v_local_time := (ottoq_depot_local_time(v_depot_id))::TIME;

  IF v_depot.operational_hours_start <= v_depot.operational_hours_end THEN
    v_in_hours := v_local_time BETWEEN v_depot.operational_hours_start AND v_depot.operational_hours_end;
  ELSE
    v_in_hours := v_local_time >= v_depot.operational_hours_start
               OR v_local_time <= v_depot.operational_hours_end;
  END IF;

  IF NOT v_in_hours THEN
    RETURN ROW(FALSE,
      format('outside operational hours [%s, %s] (local %s)',
        v_depot.operational_hours_start, v_depot.operational_hours_end, v_local_time),
      'warning',
      jsonb_build_object(
        'depot_id', v_depot_id,
        'local_time', v_local_time,
        'hours_start', v_depot.operational_hours_start,
        'hours_end', v_depot.operational_hours_end,
        'timezone', v_depot.operating_timezone
      ),
      'queue_for_next_operational_window'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,'within operational hours',NULL,
    jsonb_build_object('local_time', v_local_time),NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_tw_002_overnight_staging =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_tw_002_overnight_staging(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot_id     UUID;
  v_minutes      NUMERIC;
  v_threshold    INTEGER;
  v_depot        depots%ROWTYPE;
BEGIN
  v_depot_id := NULLIF(p_context ->> 'depot_id','')::UUID;
  v_minutes  := NULLIF(p_context ->> 'minutes_to_departure','')::NUMERIC;

  IF v_depot_id IS NULL OR v_minutes IS NULL THEN
    RETURN ROW(TRUE,'insufficient context',NULL,'{}'::jsonb,NULL)::ottoq_rule_result;
  END IF;

  SELECT * INTO v_depot FROM depots WHERE id = v_depot_id;
  v_threshold := COALESCE(
    (p_parameters ->> 'threshold_minutes')::INT,
    v_depot.overnight_staging_threshold_minutes,
    120
  );

  IF v_minutes > v_threshold THEN
    -- This rule SUGGESTS staging — it's not a hard block on the alternative
    RETURN ROW(TRUE,
      format('staging recommended: %s min > threshold %s', v_minutes, v_threshold),
      'info',
      jsonb_build_object(
        'minutes_to_departure', v_minutes,
        'threshold_minutes', v_threshold,
        'recommendation', 'overnight_stage'
      ),
      'overnight_stage'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,
    format('immediate flow recommended: %s ≤ %s', v_minutes, v_threshold),
    NULL,
    jsonb_build_object('minutes_to_departure', v_minutes, 'threshold', v_threshold),
    'continue_immediate'
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_tw_003_quiet_hours =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_tw_003_quiet_hours(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot_id     UUID;
  v_service_code TEXT;
  v_loud_kinds   TEXT[];
  v_depot        depots%ROWTYPE;
  v_local_time   TIME;
  v_in_quiet     BOOLEAN;
BEGIN
  v_depot_id    := NULLIF(p_context ->> 'depot_id','')::UUID;
  v_service_code := p_context ->> 'service_code';
  v_loud_kinds  := COALESCE(
    ARRAY(SELECT jsonb_array_elements_text(p_parameters -> 'loud_services')),
    ARRAY['exterior_wash','pressure_wash','tire_rotation','brake_service']
  );

  IF v_depot_id IS NULL OR v_service_code IS NULL THEN
    RETURN ROW(TRUE,'no context',NULL,'{}'::jsonb,NULL)::ottoq_rule_result;
  END IF;
  IF NOT (v_service_code = ANY(v_loud_kinds)) THEN
    RETURN ROW(TRUE,
      format('service %s is not noise-class', v_service_code),
      NULL, jsonb_build_object('service_code', v_service_code), NULL
    )::ottoq_rule_result;
  END IF;

  SELECT * INTO v_depot FROM depots WHERE id = v_depot_id;
  IF v_depot.quiet_hours_start IS NULL OR v_depot.quiet_hours_end IS NULL THEN
    RETURN ROW(TRUE,'depot has no quiet hours configured',NULL,'{}'::jsonb,NULL)::ottoq_rule_result;
  END IF;

  v_local_time := (ottoq_depot_local_time(v_depot_id))::TIME;
  IF v_depot.quiet_hours_start <= v_depot.quiet_hours_end THEN
    v_in_quiet := v_local_time BETWEEN v_depot.quiet_hours_start AND v_depot.quiet_hours_end;
  ELSE
    v_in_quiet := v_local_time >= v_depot.quiet_hours_start
               OR v_local_time <= v_depot.quiet_hours_end;
  END IF;

  IF v_in_quiet THEN
    RETURN ROW(FALSE,
      format('service %s during quiet hours [%s, %s] (local %s)',
        v_service_code, v_depot.quiet_hours_start, v_depot.quiet_hours_end, v_local_time),
      'warning',
      jsonb_build_object(
        'service_code', v_service_code,
        'local_time', v_local_time,
        'quiet_start', v_depot.quiet_hours_start,
        'quiet_end', v_depot.quiet_hours_end
      ),
      'defer_to_after_quiet_hours'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,'outside quiet hours',NULL,
    jsonb_build_object('local_time', v_local_time),NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_tw_004_tariff_window =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_tw_004_tariff_window(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot_id     UUID;
  v_local_time   TIME;
  v_peak_start   TIME := COALESCE((p_parameters ->> 'peak_start')::TIME, '14:00'::TIME);
  v_peak_end     TIME := COALESCE((p_parameters ->> 'peak_end')::TIME, '20:00'::TIME);
  v_is_peak      BOOLEAN;
BEGIN
  v_depot_id := NULLIF(p_context ->> 'depot_id','')::UUID;
  IF v_depot_id IS NULL THEN
    RETURN ROW(TRUE,'no depot context',NULL,'{}'::jsonb,NULL)::ottoq_rule_result;
  END IF;

  v_local_time := (ottoq_depot_local_time(v_depot_id))::TIME;
  v_is_peak := v_local_time BETWEEN v_peak_start AND v_peak_end;

  RETURN ROW(TRUE,
    format('tariff window: %s', CASE WHEN v_is_peak THEN 'PEAK (avoid heavy charging)' ELSE 'OFF-PEAK (prefer heavy charging)' END),
    NULL,
    jsonb_build_object(
      'depot_id', v_depot_id,
      'local_time', v_local_time,
      'is_peak', v_is_peak,
      'peak_start', v_peak_start,
      'peak_end', v_peak_end,
      'cost_preference_score', CASE WHEN v_is_peak THEN 0.3 ELSE 0.9 END
    ),
    CASE WHEN v_is_peak THEN 'prefer_defer_or_bess' ELSE 'prefer_immediate_charge' END
  )::ottoq_rule_result;
END;
$function$

-- ===== ottoq_eval_tw_005_shift_buffer =====
CREATE OR REPLACE FUNCTION public.ottoq_eval_tw_005_shift_buffer(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot_id    UUID;
  v_buffer_min  INTEGER;
  v_local_time  TIME;
  v_local_dow   INTEGER;
  v_shift       RECORD;
  v_minutes_to_boundary NUMERIC;
BEGIN
  v_depot_id := NULLIF(p_context ->> 'depot_id','')::UUID;
  IF v_depot_id IS NULL THEN
    RETURN ROW(TRUE,'no depot context',NULL,'{}'::jsonb,NULL)::ottoq_rule_result;
  END IF;

  SELECT shift_change_buffer_minutes INTO v_buffer_min FROM depots WHERE id = v_depot_id;
  v_buffer_min := COALESCE((p_parameters ->> 'buffer_minutes')::INT, v_buffer_min, 15);
  IF v_buffer_min <= 0 THEN
    RETURN ROW(TRUE,'buffer disabled',NULL,'{}'::jsonb,NULL)::ottoq_rule_result;
  END IF;

  v_local_time := (ottoq_depot_local_time(v_depot_id))::TIME;
  v_local_dow  := EXTRACT(ISODOW FROM ottoq_depot_local_time(v_depot_id))::INT;

  -- Find nearest upcoming shift boundary within v_buffer_min minutes
  FOR v_shift IN
    SELECT shift_name, start_time
      FROM ottoq_depot_shifts
     WHERE depot_id = v_depot_id
       AND status = 'active'
       AND v_local_dow = ANY(days_of_week)
  LOOP
    v_minutes_to_boundary :=
      EXTRACT(EPOCH FROM (v_shift.start_time - v_local_time)) / 60.0;

    IF v_minutes_to_boundary > 0 AND v_minutes_to_boundary <= v_buffer_min THEN
      RETURN ROW(FALSE,
        format('within %s min of shift change to %s (%s min)',
          v_buffer_min, v_shift.shift_name, v_minutes_to_boundary),
        'warning',
        jsonb_build_object(
          'shift', v_shift.shift_name,
          'shift_start', v_shift.start_time,
          'minutes_to_boundary', v_minutes_to_boundary,
          'buffer_minutes', v_buffer_min
        ),
        'wait_for_shift_handoff'
      )::ottoq_rule_result;
    END IF;
  END LOOP;

  RETURN ROW(TRUE,'outside shift change buffer',NULL,'{}'::jsonb,NULL)::ottoq_rule_result;
END;
$function$

-- ===== ottoq_evaluate_return_need =====
CREATE OR REPLACE FUNCTION public.ottoq_evaluate_return_need(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_horizon_min numeric DEFAULT 30, p_soc_pct numeric DEFAULT NULL::numeric)
 RETURNS TABLE(should_return boolean, return_trigger text, urgency text, rung smallint, is_deferrable boolean, lead_ticks smallint, projected_eta_min numeric, evidence jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_v RECORD; v_pkt RECORD; v_w RECORD;
  v_soc numeric; v_reserve numeric; v_floor numeric; v_eta_min numeric;
  v_hour int; v_depot uuid;
  v_burn_per_min numeric; v_burn_guard numeric; v_reserve_margin numeric;
  v_dtc_debt int; v_comms_stale int; v_wait_cap int; v_backstop_ticks int;
  v_wash_soil numeric; v_sensor_soil numeric; v_pm_km numeric; v_calib_h numeric;
  v_free_chargers int; v_inbound int; v_wait_ticks int; v_max_wait_min numeric;
  v_in_window boolean; v_slot int; v_slot_open boolean; v_holdout boolean;
  v_pkt_age_min numeric; v_has_service_need boolean; v_overnight_need boolean;
  v_ev jsonb;
BEGIN
  IF p_sim_run_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_evaluate_return_need requires a run scope';
  END IF;

  SELECT d.dispatch_id, d.scheduled_return_at, d.dispatched_at, v.home_depot_id, v.config,
         v.current_soc, v.min_soc_threshold
    INTO v_v
    FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id = d.vehicle_id
   WHERE d.vehicle_id = p_vehicle_id AND d.sim_run_id = p_sim_run_id AND d.status = 'active'
   ORDER BY d.dispatched_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::text, 'none', 10::smallint, NULL::boolean,
                        NULL::smallint, NULL::numeric,
                        jsonb_build_object('reason','no active dispatch in run');
    RETURN;
  END IF;
  v_depot := v_v.home_depot_id;

  SELECT tp.soc_pct, tp.sim_clock_at
    INTO v_pkt
    FROM ottoq_telemetry_packets tp
   WHERE tp.vehicle_id = p_vehicle_id AND tp.sim_run_id = p_sim_run_id
     AND tp.sim_clock_at <= p_sim_clock_now AND tp.soc_pct IS NOT NULL
   ORDER BY tp.sim_clock_at DESC, tp.packet_seq DESC LIMIT 1;

  SELECT w.worst_open_dtc_rank, w.open_dtc_count, w.soil_index,
         w.drive_km_total, w.km_at_last_pm, w.drive_hours_total,
         w.hours_at_last_calibration, w.calibrated_at
    INTO v_w
    FROM ottoq_vehicle_wear w
   WHERE w.vehicle_id = p_vehicle_id AND w.sim_run_id = p_sim_run_id;

  v_soc     := COALESCE(p_soc_pct, v_pkt.soc_pct, v_v.current_soc);
  v_reserve := ottoq_effective_reserve_soc(p_vehicle_id, p_sim_clock_now);
  v_floor   := ottoq_effective_deploy_floor_at(p_vehicle_id, p_sim_clock_now);
  v_eta_min := ottoq_return_eta_minutes(p_vehicle_id, v_depot, p_sim_run_id);
  v_hour    := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  v_burn_per_min   := ottoq_policy_get(p_sim_run_id,'p99_burn_pct_per_min',0.25);
  v_reserve_margin := ottoq_policy_get(p_sim_run_id,'reserve_margin_pct',15);
  v_dtc_debt       := ottoq_policy_get(p_sim_run_id,'dtc_debt_threshold',3)::int;
  v_comms_stale    := ottoq_policy_get(p_sim_run_id,'comms_stale_ticks',3)::int;
  v_wait_cap       := ottoq_policy_get(p_sim_run_id,'contention_wait_cap_min',
                        ottoq_policy_get(p_sim_run_id,'contention_wait_cap_ticks',4) * 30)::int;
  -- tick_invariant_thresholds: minutes, not ticks. 1440 = the 24 h backstop that a
  -- 48-tick value only happened to mean at a 30-minute tick.
  v_backstop_ticks := ottoq_policy_get(p_sim_run_id,'timer_backstop_min',
                        ottoq_policy_get(p_sim_run_id,'timer_backstop_ticks',48) * 30)::int;
  v_wash_soil      := ottoq_policy_get(p_sim_run_id,'wash_soil_threshold',0.50);
  v_sensor_soil    := ottoq_policy_get(p_sim_run_id,'sensor_soil_threshold',0.35);
  v_pm_km          := COALESCE((v_v.config->>'pm_interval_km')::numeric, ottoq_policy_get(p_sim_run_id,'pm_interval_km',8000));
  v_calib_h        := COALESCE((v_v.config->>'calib_interval_h')::numeric, ottoq_policy_get(p_sim_run_id,'calib_interval_h',250));

  v_burn_guard := v_burn_per_min * (v_eta_min + p_horizon_min);

  SELECT count(*) INTO v_free_chargers FROM stalls s
   WHERE s.depot_id = v_depot AND s.stall_kind = 'charging'
     AND s.status = 'available' AND s.current_vehicle_id IS NULL;
  SELECT count(*) INTO v_inbound FROM vehicles vv
   WHERE vv.home_depot_id = v_depot AND vv.category='autonomous'
     AND vv.current_state IN ('en_route_to_depot','arrived_at_gate');

  -- wait_estimate_in_minutes: QUEUE ROUNDS (unitless). Do NOT clamp with
  -- v_wait_cap here — that value is now MINUTES and is applied at the comparison.
  v_wait_ticks := CASE WHEN v_free_chargers >= v_inbound + 1 THEN 0
         ELSE CEIL((v_inbound + 1 - v_free_chargers)/GREATEST(v_free_chargers,1)::numeric) END;
  v_max_wait_min := COALESCE((SELECT s.max_queue_wait_minutes FROM ottoq_fleet_operator_slas s
     JOIN vehicles vv ON vv.id=p_vehicle_id AND vv.fleet_operator_id=s.fleet_operator_id
     WHERE s.status='active' ORDER BY s.version DESC LIMIT 1), 30);

  v_pkt_age_min := CASE WHEN v_pkt.sim_clock_at IS NULL THEN NULL
                        ELSE EXTRACT(EPOCH FROM (p_sim_clock_now - v_pkt.sim_clock_at))/60.0 END;

  v_has_service_need := COALESCE(v_w.soil_index,0) >= v_sensor_soil
     OR COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km
     OR (COALESCE((v_v.config->>'wash_group')::int,
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3))
                = ((p_sim_clock_now::date - DATE '2020-01-01') % 3));
  v_overnight_need := v_has_service_need OR v_soc < v_floor;

  v_ev := jsonb_build_object(
    'soc', v_soc, 'reserve', v_reserve, 'deploy_floor', v_floor, 'target_absent_from_loop', true,
    'burn_guard', round(v_burn_guard,2), 'reserve_margin', v_reserve_margin,
    'eta_min', v_eta_min, 'free_chargers', v_free_chargers, 'inbound', v_inbound,
    'wait_ticks', v_wait_ticks, 'reserved_by_bias', 'supply overcounted (reserved_by not consulted)',
    'worst_dtc_rank', v_w.worst_open_dtc_rank, 'soil', v_w.soil_index, 'hour_local', v_hour);

  IF v_soc <= v_reserve + v_burn_guard THEN
    RETURN QUERY SELECT true,'critical_reserve','critical',0::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF COALESCE(v_w.worst_open_dtc_rank,99) = 0 THEN
    RETURN QUERY SELECT true,'fault_safety_critical','critical',1::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF COALESCE(v_w.worst_open_dtc_rank,99) = 1 OR COALESCE(v_w.open_dtc_count,0) >= v_dtc_debt THEN
    RETURN QUERY SELECT true,'fault_major','urgent',2::smallint,false,1::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF v_soc <= v_reserve + v_reserve_margin THEN
    RETURN QUERY SELECT true,'low_soc_reserve','urgent',3::smallint,false,1::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF (v_pkt_age_min IS NULL
        AND EXTRACT(EPOCH FROM (p_sim_clock_now - v_v.dispatched_at))/60.0 >= v_comms_stale * p_horizon_min)
     OR (v_pkt_age_min IS NOT NULL AND v_pkt_age_min >= v_comms_stale * p_horizon_min) THEN
    RETURN QUERY SELECT true,'comms_stale','urgent',8::smallint,false,0::smallint,v_eta_min,
                        v_ev || jsonb_build_object('pkt_age_min', v_pkt_age_min); RETURN;
  END IF;
  IF v_v.scheduled_return_at IS NOT NULL
     AND p_sim_clock_now >= v_v.scheduled_return_at + (v_backstop_ticks || ' minutes')::interval THEN
    RETURN QUERY SELECT true,'timer_backstop','anomaly',9::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;

  -- a queue round is a SERVICE SESSION (~30 min), not a tick. Using p_horizon_min
  -- here is what made the wait estimate shrink/grow with tick size.
  IF LEAST(v_wait_ticks * 30.0, v_wait_cap) <= v_max_wait_min THEN
    IF COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km
       OR COALESCE(v_w.drive_hours_total,0) - COALESCE(v_w.hours_at_last_calibration,0) >= v_calib_h THEN
      RETURN QUERY SELECT true,'service_interval_due','routine',4::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;
    END IF;
    IF COALESCE(v_w.soil_index,0) >= v_sensor_soil THEN
      RETURN QUERY SELECT true,'sensor_soil','routine',5::smallint,true,1::smallint,v_eta_min,v_ev; RETURN;
    END IF;
    v_in_window := (v_hour >= 22 OR v_hour < 4);
    v_slot      := LEAST(3, width_bucket(v_soc, 0, 100, 3));
    v_slot_open := (v_hour >= 22 AND v_hour - 22 >= v_slot - 1) OR v_hour < 4;
    v_holdout := ottoq_is_overnight_holdout(p_vehicle_id, p_sim_run_id, p_sim_clock_now, ottoq_policy_get(p_sim_run_id, 'overnight_holdout_pct', 1)::int);
    IF v_in_window AND v_slot_open AND v_overnight_need AND (NOT v_holdout OR (v_hour >= 3 AND v_hour < 22)) THEN
      RETURN QUERY SELECT true,'overnight_prestage','scheduled',6::smallint,true,1::smallint,v_eta_min,
                          v_ev || jsonb_build_object('slot', v_slot); RETURN;
    END IF;
    IF (COALESCE(v_w.soil_index,0) >= v_wash_soil
        OR COALESCE((v_v.config->>'wash_group')::int,
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3))
                = ((p_sim_clock_now::date - DATE '2020-01-01') % 3))
       AND (v_hour < 7 OR v_hour >= 21) THEN
      RETURN QUERY SELECT true,'wash_cadence','routine',7::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;
    END IF;
  END IF;

  RETURN QUERY SELECT false, NULL::text, 'none', 10::smallint, NULL::boolean, NULL::smallint, NULL::numeric,
                      v_ev || jsonb_build_object('decision','no need; stay deployed');
END;
$function$

-- ===== ottoq_evaluate_rule =====
CREATE OR REPLACE FUNCTION public.ottoq_evaluate_rule(p_rule_code text, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_context jsonb DEFAULT '{}'::jsonb, p_action_context text DEFAULT NULL::text, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_triggered_by_event_id uuid DEFAULT NULL::uuid, p_override_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(passed boolean, reason text, enforcement_taken text, evaluation_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rule_version integer;
BEGIN
  -- call the non-raising core (assign each OUT column explicitly)
  SELECT c.passed, c.reason, c.enforcement_taken, c.evaluation_id, c.rule_version
    INTO passed, reason, enforcement_taken, evaluation_id, v_rule_version
  FROM ottoq_evaluate_rule_core(
    p_rule_code, p_entity_type, p_entity_id, p_context, p_action_context,
    p_fleet_operator_id, p_depot_id, p_triggered_by_event_id, p_override_id) c;

  IF enforcement_taken = 'blocked' THEN
    RAISE EXCEPTION 'OTTOQ_RULE_BLOCKED: % — %', p_rule_code, COALESCE(reason,'no reason provided')
      USING ERRCODE = 'P0001',
            HINT = format('rule_version=%s evaluation_id=%s', v_rule_version, evaluation_id);
  END IF;

  RETURN QUERY SELECT passed, reason, enforcement_taken, evaluation_id;
END;
$function$

-- ===== ottoq_evaluate_rule_core =====
CREATE OR REPLACE FUNCTION public.ottoq_evaluate_rule_core(p_rule_code text, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_context jsonb DEFAULT '{}'::jsonb, p_action_context text DEFAULT NULL::text, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_triggered_by_event_id uuid DEFAULT NULL::uuid, p_override_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(passed boolean, reason text, enforcement_taken text, evaluation_id uuid, severity text, enforcement text, suggested_action text, rule_version integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rule        ottoq_rules%ROWTYPE;
  v_params      JSONB;
  v_result      ottoq_rule_result;
  v_started_at  TIMESTAMPTZ := clock_timestamp();
  v_eval_id     UUID := gen_random_uuid();
  v_event_id    UUID;
  v_enforcement TEXT;
  v_severity    TEXT;
  v_taken       TEXT;
  v_correlation UUID;
  v_dynamic_sql TEXT;
BEGIN
  SELECT * INTO v_rule FROM ottoq_rules
   WHERE rule_code = p_rule_code AND status IN ('active','shadow')
   ORDER BY version DESC LIMIT 1;

  IF NOT FOUND THEN
    v_event_id := ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_event_type := 'system.catalog_miss',
      p_entity_type := COALESCE(p_entity_type, 'system'), p_entity_id := p_entity_id,
      p_payload := jsonb_build_object('missing_rule_code', p_rule_code), p_severity := 'warning');
    RETURN QUERY SELECT TRUE, 'rule_not_found'::text, 'allowed'::text, v_eval_id,
                        'info'::text, 'log_only'::text, NULL::text, 0;
    RETURN;
  END IF;

  v_params := ottoq_resolve_rule_parameters(p_rule_code, p_fleet_operator_id, p_depot_id, NULL);

  BEGIN
    v_dynamic_sql := format('SELECT * FROM %I($1,$2,$3,$4)', v_rule.evaluator_function);
    EXECUTE v_dynamic_sql INTO v_result USING p_entity_type, p_entity_id, p_context, v_params;
  EXCEPTION WHEN OTHERS THEN
    v_event_id := ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_event_type := 'system.catalog_miss',
      p_entity_type := COALESCE(p_entity_type, 'system'), p_entity_id := p_entity_id,
      p_payload := jsonb_build_object('rule_code', p_rule_code, 'evaluator_error', SQLERRM,
                     'sqlstate', SQLSTATE, 'enforcement', v_rule.enforcement, 'severity', v_rule.severity,
                     'fail_closed', (v_rule.enforcement = 'block')),
      p_severity := 'critical');

    -- WIRE-2: a BLOCK-tier rule that THROWS fails CLOSED (the safety posture);
    -- non-block advisory rules keep log-and-pass (don't halt the depot on an advisory bug).
    IF v_rule.enforcement = 'block' THEN
      RETURN QUERY SELECT FALSE, ('evaluator_error_failclosed: ' || SQLERRM)::text, 'blocked'::text, v_eval_id,
                          COALESCE(v_rule.severity,'critical'), v_rule.enforcement, 'fix_evaluator_or_supply_context'::text, v_rule.version;
    ELSE
      RETURN QUERY SELECT TRUE, ('evaluator_error: ' || SQLERRM)::text, 'logged'::text, v_eval_id,
                          COALESCE(v_rule.severity,'warning'), v_rule.enforcement, NULL::text, v_rule.version;
    END IF;
    RETURN;
  END;

  v_enforcement := v_rule.enforcement;
  v_severity    := COALESCE(v_result.severity_override, v_rule.severity);

  IF v_result.passed THEN
    v_taken := CASE WHEN v_enforcement = 'shadow' THEN 'shadow_pass' ELSE 'allowed' END;
  ELSE
    v_taken := CASE
      WHEN p_override_id IS NOT NULL THEN 'overridden'
      WHEN v_enforcement = 'block'    THEN 'blocked'
      WHEN v_enforcement = 'warn'     THEN 'warned'
      WHEN v_enforcement = 'log_only' THEN 'logged'
      WHEN v_enforcement = 'shadow'   THEN 'shadow_fail'
      ELSE 'logged'
    END;
  END IF;

  v_correlation := NULLIF(current_setting('ottoq.correlation_id', TRUE), '')::UUID;

  IF current_setting('ottoq.dryrun', true) = 'on' THEN
    RETURN QUERY SELECT v_result.passed, v_result.reason, v_taken, v_eval_id, v_severity, v_enforcement, v_result.suggested_action, v_rule.version;
    RETURN;
  END IF;  -- MPC fork: evaluate but do not persist
  INSERT INTO ottoq_rule_evaluations (
    evaluation_id, evaluated_at, duration_ms, rule_code, rule_version,
    triggered_by_event_id, action_context, entity_type, entity_id,
    fleet_operator_id, depot_id, passed, reason, severity, enforcement, enforcement_taken,
    parameters_used, context, result_payload, override_id, correlation_id
  ) VALUES (
    v_eval_id, NOW(), EXTRACT(MILLISECOND FROM (clock_timestamp() - v_started_at))::INTEGER,
    p_rule_code, v_rule.version, p_triggered_by_event_id, p_action_context,
    p_entity_type, p_entity_id, p_fleet_operator_id, p_depot_id,
    v_result.passed, v_result.reason, v_severity, v_enforcement, v_taken,
    v_params, p_context, COALESCE(v_result.payload, '{}'::jsonb), p_override_id, v_correlation
  );

  v_event_id := ottoq_record_event(
    p_actor_type := 'ottoq_engine',
    p_event_type := CASE WHEN v_result.passed THEN 'rule.evaluated_pass' ELSE 'rule.evaluated_fail' END,
    p_entity_type := COALESCE(p_entity_type, 'system'), p_entity_id := p_entity_id,
    p_fleet_operator_id := p_fleet_operator_id, p_depot_id := p_depot_id,
    p_payload := jsonb_build_object(
      'rule_code', p_rule_code, 'rule_version', v_rule.version,
      'passed', v_result.passed, 'reason', v_result.reason,
      'enforcement_taken', v_taken, 'severity', v_severity,
      'action_context', p_action_context, 'override_id', p_override_id,
      'result_payload', v_result.payload),
    p_severity := v_severity, p_parent_event_id := p_triggered_by_event_id, p_correlation_id := v_correlation);

  UPDATE ottoq_rule_evaluations re SET linked_event_id = v_event_id WHERE re.evaluation_id = v_eval_id;

  RETURN QUERY SELECT v_result.passed, v_result.reason, v_taken, v_eval_id,
                      v_severity, v_enforcement, v_result.suggested_action, v_rule.version;
END;
$function$

-- ===== ottoq_evaluate_rules_for_action =====
CREATE OR REPLACE FUNCTION public.ottoq_evaluate_rules_for_action(p_action_context text, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_context jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_triggered_by_event_id uuid DEFAULT NULL::uuid, p_override_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(rule_code text, passed boolean, reason text, enforcement_taken text, evaluation_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rc     TEXT;
  v_result RECORD;
BEGIN
  FOR v_rc IN
    SELECT r.rule_code FROM ottoq_rules r
     WHERE r.status IN ('active','shadow')
       AND p_action_context = ANY(r.applies_to_actions)
     ORDER BY CASE r.severity
                WHEN 'safety_critical' THEN 1 WHEN 'critical' THEN 2
                WHEN 'error' THEN 3 WHEN 'warning' THEN 4 WHEN 'info' THEN 5 ELSE 6 END,
              r.rule_code
  LOOP
    SELECT * INTO v_result FROM ottoq_evaluate_rule(
      p_rule_code             := v_rc,
      p_entity_type           := p_entity_type,
      p_entity_id             := p_entity_id,
      p_context               := p_context,
      p_action_context        := p_action_context,
      p_fleet_operator_id     := p_fleet_operator_id,
      p_depot_id              := p_depot_id,
      p_triggered_by_event_id := p_triggered_by_event_id,
      p_override_id           := p_override_id        -- WIRE-5: forward
    );
    rule_code         := v_rc;
    passed            := v_result.passed;
    reason            := v_result.reason;
    enforcement_taken := v_result.enforcement_taken;
    evaluation_id     := v_result.evaluation_id;
    RETURN NEXT;
  END LOOP;
END;
$function$

-- ===== ottoq_events_block_mutation =====
CREATE OR REPLACE FUNCTION public.ottoq_events_block_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' AND current_setting('ottoq.retention', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'ottoq_events is append-only. Operation % rejected on event_id=%',
    TG_OP, COALESCE(OLD.event_id, NEW.event_id);
END;
$function$

-- ===== ottoq_feature_is_fresh =====
CREATE OR REPLACE FUNCTION public.ottoq_feature_is_fresh(p_feature_name text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_row     ottoq_feature_values%ROWTYPE;
  v_sla     INTEGER;
BEGIN
  SELECT freshness_sla_seconds INTO v_sla FROM ottoq_features WHERE feature_name = p_feature_name;
  IF v_sla IS NULL THEN
    RETURN TRUE; -- no SLA configured; assume fresh
  END IF;
  v_row := ottoq_get_feature(p_feature_name, p_entity_type, p_entity_id);
  IF v_row.value_id IS NULL THEN
    RETURN FALSE;
  END IF;
  RETURN EXTRACT(EPOCH FROM (NOW() - v_row.observation_time)) <= v_sla;
END;
$function$

-- ===== ottoq_feed_plan =====
CREATE OR REPLACE FUNCTION public.ottoq_feed_plan(p_var_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT plan FROM public.ottoq_feed_plans
   WHERE var_key = p_var_key AND status = 'active'
   ORDER BY version DESC LIMIT 1;
$function$

-- ===== ottoq_fifo_tick =====
CREATE OR REPLACE FUNCTION public.ottoq_fifo_tick(p_sim_run_id uuid)
 RETURNS ottoq_decide_tick_result
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_clock timestamptz; v_tick bigint;
  v_req RECORD; v_stall RECORD; v_built int := 0; v_enacted int := 0;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count INTO v_depot, v_clock, v_tick
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN ROW(0,NULL,0,0,0,0,0,0,0)::ottoq_decide_tick_result; END IF;

  -- (a) STALL: arrived vehicles, FIFO by id, take next free charger in id order (no urgency)
  FOR v_req IN
    SELECT id AS vehicle_id FROM vehicles
     WHERE home_depot_id=v_depot AND category='autonomous' AND current_state='arrived_at_gate' AND current_soc<85
     ORDER BY id   -- FIFO (no SoC ranking)
  LOOP
    v_built := v_built + 1;
    SELECT s.id, s.stall_type INTO v_stall FROM stalls s
     WHERE s.depot_id=v_depot AND s.stall_type IN ('dcfc','l2') AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= v_clock)
     ORDER BY s.id LIMIT 1;    -- first free stall, no optimization
    IF v_stall.id IS NOT NULL AND ottoq_reserve_stall(v_stall.id, v_req.vehicle_id, v_clock, 600) THEN
      UPDATE vehicles SET current_state=(CASE WHEN v_stall.stall_type::text='dcfc' THEN 'charging_dcfc' ELSE 'charging_l2' END)::vehicle_state,
             current_stall_id=v_stall.id, last_state_change=v_clock WHERE id=v_req.vehicle_id;
      UPDATE stalls SET current_vehicle_id=v_req.vehicle_id, status='occupied' WHERE id=v_stall.id;
      v_enacted := v_enacted + 1;
    END IF;
  END LOOP;

  -- (b) DEPLOY: staged_for_departure, FIFO by last_state_change, deploy if SoC>=70 (same safety floor, no ranking)
  FOR v_req IN
    SELECT id AS vehicle_id FROM vehicles
     WHERE home_depot_id=v_depot AND category='autonomous' AND current_state='staged_for_departure' AND current_soc>=70
     ORDER BY last_state_change ASC NULLS FIRST, id LIMIT 40
  LOOP
    v_built := v_built + 1;
    UPDATE vehicles SET current_state='en_route_to_deployment', current_stall_id=NULL, last_state_change=v_clock WHERE id=v_req.vehicle_id;
    v_enacted := v_enacted + 1;
  END LOOP;

  -- (c) SERVICE/HOLDING: charge_complete_holding → wash in FIFO order (capacity-gated like greedy)
  FOR v_req IN
    SELECT id AS vehicle_id FROM vehicles
     WHERE home_depot_id=v_depot AND category='autonomous' AND current_state='charge_complete_holding'
     ORDER BY last_state_change ASC NULLS FIRST, id LIMIT 40
  LOOP
    v_built := v_built + 1;
    IF (SELECT count(*) FROM vehicles WHERE home_depot_id=v_depot AND current_state IN ('in_wash_bay','in_detail_bay')) < ottoq_sim_lane_capacity(NULL,'cleaning_staff',3) THEN
      UPDATE vehicles SET current_state='in_wash_bay', last_state_change=v_clock,
             config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('washing'::text)) WHERE id=v_req.vehicle_id;
      v_enacted := v_enacted + 1;
    END IF;
  END LOOP;

  -- (d) staged_awaiting_service → promote ready (FIFO)
  FOR v_req IN
    SELECT id AS vehicle_id FROM vehicles
     WHERE home_depot_id=v_depot AND category='autonomous' AND current_state='staged_awaiting_service'
     ORDER BY last_state_change ASC NULLS FIRST, id LIMIT 40
  LOOP
    v_built := v_built + 1;
    UPDATE vehicles SET current_state='staged_for_departure', last_state_change=v_clock,
           config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('ready'::text)) WHERE id=v_req.vehicle_id;
    v_enacted := v_enacted + 1;
  END LOOP;

  RETURN ROW(v_tick, v_clock, v_built, v_enacted, 0, 0, 0, 0, 0)::ottoq_decide_tick_result;
END;
$function$

-- ===== ottoq_fleet_pending_commands =====
CREATE OR REPLACE FUNCTION public.ottoq_fleet_pending_commands(p_depot_id uuid DEFAULT NULL::uuid, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 200)
 RETURNS TABLE(command_id uuid, vehicle_id uuid, vehicle_ref text, command_type text, payload jsonb, issued_at timestamp with time zone, issued_by text, status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT c.command_id, c.vehicle_id, v.display_name AS vehicle_ref, c.command_type,
         c.payload, c.issued_at, c.issued_by, c.status
    FROM ottoq_vehicle_commands c
    JOIN vehicles v ON v.id = c.vehicle_id
   WHERE c.status = 'issued'
     AND (p_depot_id IS NULL OR c.depot_id = p_depot_id)
     AND (p_fleet_operator_id IS NULL OR v.fleet_operator_id = p_fleet_operator_id)
   ORDER BY c.issued_at DESC
   LIMIT GREATEST(1, LEAST(p_limit, 1000));
$function$

-- ===== ottoq_forecast_net_load =====
CREATE OR REPLACE FUNCTION public.ottoq_forecast_net_load(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone, p_horizon_ticks integer DEFAULT 16, p_tick_min numeric DEFAULT 30, p_arrival_soc numeric DEFAULT 30)
 RETURNS numeric[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_base numeric; v_solar numeric; v_load numeric[]; h int; r RECORD;
  v_rate numeric; v_kwh numeric; v_dur_min numeric; v_step_min numeric;
BEGIN
  SELECT COALESCE(building_load_kw,0)+COALESCE(lighting_load_kw,0), COALESCE(solar_generation_kw,0)
    INTO v_base, v_solar FROM site_energy_snapshots
   WHERE depot_id=p_depot_id AND sim_run_id=p_sim_run_id ORDER BY timestamp DESC LIMIT 1;
  v_base := COALESCE(v_base, 50); v_solar := COALESCE(v_solar, 0);
  v_load := array_fill(0::numeric, ARRAY[p_horizon_ticks]);

  -- (1) currently-active charging sessions: hold their rate until they finish
  FOR r IN
    SELECT ottoq_sim_compute_charge_rate(
             p_soc_pct := v.current_soc, p_battery_temp_c := COALESCE(s.ambient_temp_c,22)+5,
             p_ambient_temp_c := COALESCE(s.ambient_temp_c,22), p_charger_max_kw := ch.max_kw,
             p_vehicle_max_kw := v.inlet_max_kw, p_battery_capacity_kwh := v.battery_capacity_kwh,
             p_battery_soh_pct := 95, p_noise_seed := 1, p_noise_salt := s.id::text) AS rate,
           GREATEST(0,(COALESCE(v.target_soc,90)-v.current_soc)/100.0*COALESCE(v.battery_capacity_kwh,75)) AS kwh
    FROM ocpp_sessions s JOIN stalls st ON st.id=s.stall_id
    JOIN ottoq_ocpp_chargers ch ON ch.charger_id=st.ocpp_charger_id
    JOIN vehicles v ON v.id=s.vehicle_id
    WHERE s.status='active' AND s.sim_run_id=p_sim_run_id
  LOOP
    v_rate := GREATEST(r.rate, 1); v_dur_min := r.kwh / v_rate * 60.0;
    FOR h IN 1..p_horizon_ticks LOOP
      IF (h-1)*p_tick_min < v_dur_min THEN v_load[h] := v_load[h] + v_rate; END IF;
    END LOOP;
  END LOOP;

  -- (2) scheduled future arrivals: charge from their ETA through their charge window
  FOR r IN
    SELECT d.scheduled_return_at AS eta, v.target_soc, v.battery_capacity_kwh, v.inlet_max_kw
    FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id=d.vehicle_id
    WHERE d.sim_run_id=p_sim_run_id AND d.status IN ('active','returning')
      AND d.scheduled_return_at IS NOT NULL
      AND d.scheduled_return_at <= p_sim_clock + (p_horizon_ticks*p_tick_min)*interval '1 min'
      AND d.scheduled_return_at >  p_sim_clock - interval '30 min'
  LOOP
    v_rate := LEAST(COALESCE(r.inlet_max_kw,150), 250) * 0.60;  -- avg DCFC session power
    v_kwh  := GREATEST(0,(COALESCE(r.target_soc,90)-p_arrival_soc)/100.0*COALESCE(r.battery_capacity_kwh,75));
    v_dur_min := v_kwh / GREATEST(v_rate,1) * 60.0;
    FOR h IN 1..p_horizon_ticks LOOP
      v_step_min := EXTRACT(EPOCH FROM (p_sim_clock + ((h-1)*p_tick_min)*interval '1 min' - r.eta))/60.0;
      IF v_step_min >= -p_tick_min AND v_step_min < v_dur_min THEN v_load[h] := v_load[h] + v_rate; END IF;
    END LOOP;
  END LOOP;

  -- net load = base + concurrent charging - solar (floored at base)
  FOR h IN 1..p_horizon_ticks LOOP
    v_load[h] := GREATEST(v_base, v_base + v_load[h] - v_solar);
  END LOOP;
  RETURN v_load;
END;
$function$

-- ===== ottoq_forecast_uncertainty =====
CREATE OR REPLACE FUNCTION public.ottoq_forecast_uncertainty(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH recent AS (
    SELECT total_ev_charging_kw AS x FROM site_energy_snapshots
     WHERE sim_run_id = p_sim_run_id AND depot_id = p_depot_id AND timestamp <= p_sim_clock
     ORDER BY timestamp DESC LIMIT 8
  )
  SELECT LEAST(1.0, GREATEST(0.0,
    COALESCE(stddev_pop(x) / NULLIF(avg(x),0), 0) / 0.40))   -- CV of 0.40 ⇒ max uncertainty
  FROM recent WHERE x IS NOT NULL;
$function$

-- ===== ottoq_fr1_cert_arm =====
CREATE OR REPLACE PROCEDURE public.ottoq_fr1_cert_arm(IN p_run uuid, IN p_seed bigint, IN p_ab_group uuid, IN p_ticks integer, IN p_start timestamp with time zone, IN p_mpc boolean DEFAULT false)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $procedure$
DECLARE i int; v_wseed bigint; v_deploy_n int; v_total int;
        d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 80);
  UPDATE ottoq_bess_units SET current_soc_pct=90.0, current_soc_kwh=capacity_kwh*0.90, current_temperature_c=25.0,
         current_power_kw=0 WHERE depot_id=d;
  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'wave', 17));
  SELECT count(*) INTO v_total FROM vehicles WHERE home_depot_id=d AND category='autonomous';
  v_deploy_n := FLOOR(v_total * 0.85);
  UPDATE vehicles SET current_soc = 90 + ottoq_sim_seeded_random(v_wseed,'soc:'||id::text)*8,
                      target_soc = 90, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=p_start
   WHERE home_depot_id=d AND category='autonomous';
  INSERT INTO ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES (p_run, 'ef24648f-eaf6-4686-bd07-1e018a8224ab','normal_day', p_start, p_start, p_start + interval '24 hours',
    d, 60, 30, 'running', 'otto_q', 'benchmark', 0, p_seed, p_ab_group, p_start, p_start, p_start);
  IF p_mpc THEN PERFORM ottoq_policy_set('run', p_run, 'energy_mpc_follow', 1); END IF;
  WITH picked AS (
    SELECT v.id, v.fleet_operator_id, v.current_soc FROM vehicles v
    WHERE v.home_depot_id=d AND v.category='autonomous'
    ORDER BY ottoq_sim_seeded_random(v_wseed, 'pick:'||v.id::text) LIMIT v_deploy_n)
  INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
  SELECT gen_random_uuid(), p.id, p_run, p.fleet_operator_id, p_start,
         p_start + ((360 + ottoq_sim_seeded_random(v_wseed,'ret:'||p.id::text)*240) || ' minutes')::interval,
         420, p.current_soc, 'active' FROM picked p;
  UPDATE vehicles SET current_state='deployed', last_state_change=p_start
   WHERE id IN (SELECT vehicle_id FROM ottoq_vehicle_dispatches WHERE sim_run_id=p_run AND status='active');
  FOR i IN 1..p_ticks LOOP
    PERFORM ottoq_sim_advance_and_snapshot(p_run);
    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) <> 'running';
  END LOOP;
  PERFORM ottoq_score_run(p_run);
  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=p_run;
END $procedure$

-- ===== ottoq_fr1_reactive_min_peak =====
CREATE OR REPLACE FUNCTION public.ottoq_fr1_reactive_min_peak(p_run uuid, p_precharge boolean DEFAULT false)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_L numeric[]; v_cap numeric; v_floor_k numeric; v_ceil_k numeric; v_maxdis numeric; v_maxchg numeric;
  v_eff numeric; v_dt numeric := 0.5; n int; lo numeric; hi numeric; mid numeric; soc numeric;
  achieved numeric; dis numeric; chg numeric; grid numeric; t int; iter int;
BEGIN
  SELECT array_agg(nl ORDER BY ts) INTO v_L FROM (
    SELECT timestamp ts, GREATEST(0, building_load_kw+lighting_load_kw+total_ev_charging_kw-solar_generation_kw) nl
    FROM site_energy_snapshots WHERE sim_run_id=p_run) q;
  n := array_length(v_L,1);
  SELECT capacity_kwh, soc_min_floor_pct/100.0*capacity_kwh, soc_max_ceiling_pct/100.0*capacity_kwh,
         max_discharge_kw, max_charge_kw, sqrt(GREATEST(0.5,COALESCE(roundtrip_efficiency_pct,90)/100.0))
    INTO v_cap, v_floor_k, v_ceil_k, v_maxdis, v_maxchg, v_eff
    FROM ottoq_bess_units WHERE depot_id='22222222-2222-2222-2222-222222222222' LIMIT 1;

  lo := 0; SELECT max(u) INTO hi FROM unnest(v_L) u;
  FOR iter IN 1..40 LOOP
    mid := (lo+hi)/2.0; soc := 0.90*v_cap; achieved := 0;
    FOR t IN 1..n LOOP
      chg := 0; dis := 0;
      IF v_L[t] > mid AND soc > v_floor_k THEN
        dis := LEAST(v_maxdis, v_L[t]-mid, (soc - v_floor_k)*v_eff/v_dt);
        soc := soc - dis/v_eff*v_dt; grid := v_L[t]-dis;
      ELSIF p_precharge AND v_L[t] < mid AND soc < v_ceil_k THEN
        chg := LEAST(v_maxchg, mid - v_L[t], (v_ceil_k - soc)/(v_dt*v_eff));
        soc := soc + chg*v_eff*v_dt; grid := v_L[t]+chg;
      ELSE grid := v_L[t]; END IF;
      achieved := GREATEST(achieved, grid);
    END LOOP;
    IF achieved <= mid + 0.5 THEN hi := mid; ELSE lo := mid; END IF;
  END LOOP;
  RETURN round(hi,1);
END;
$function$

-- ===== ottoq_generate_audit_bundle =====
CREATE OR REPLACE FUNCTION public.ottoq_generate_audit_bundle(p_fleet_operator_id uuid, p_report_ids uuid[], p_bundle_code text, p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_format text DEFAULT 'jsonl'::text, p_storage_path text DEFAULT NULL::text, p_size_bytes bigint DEFAULT NULL::bigint, p_sha256 text DEFAULT NULL::text, p_signing_key_id text DEFAULT 'system:v1'::text, p_generated_by_actor_type text DEFAULT 'system'::text, p_generated_by_actor_id text DEFAULT NULL::text, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_bundle_id   UUID := gen_random_uuid();
  v_sha256      TEXT;
  v_signature   TEXT;
  v_manifest    JSONB;
  v_event_low   BIGINT;
  v_event_high  BIGINT;
BEGIN
  -- Compute event_seq range from the period
  SELECT MIN(event_seq), MAX(event_seq) INTO v_event_low, v_event_high
    FROM ottoq_events
   WHERE occurred_at BETWEEN p_window_start AND p_window_end
     AND (p_fleet_operator_id IS NULL OR fleet_operator_id = p_fleet_operator_id);

  -- Build manifest summarizing what's inside
  v_manifest := jsonb_build_object(
    'report_count', cardinality(p_report_ids),
    'event_count',  COALESCE(v_event_high - v_event_low + 1, 0),
    'window_start', p_window_start,
    'window_end',   p_window_end,
    'rule_eval_count', (
      SELECT count(*) FROM ottoq_rule_evaluations
       WHERE evaluated_at BETWEEN p_window_start AND p_window_end
         AND (p_fleet_operator_id IS NULL OR fleet_operator_id = p_fleet_operator_id)
    ),
    'prediction_count', (
      SELECT count(*) FROM ottoq_predictions
       WHERE created_at BETWEEN p_window_start AND p_window_end
         AND (p_fleet_operator_id IS NULL OR fleet_operator_id = p_fleet_operator_id)
    ),
    'anomaly_count', (
      SELECT count(*) FROM ottoq_anomaly_observations
       WHERE observed_at BETWEEN p_window_start AND p_window_end
         AND (p_fleet_operator_id IS NULL OR fleet_operator_id = p_fleet_operator_id)
         AND is_anomaly = TRUE
    ),
    'emergency_count', (
      SELECT count(*) FROM ottoq_emergency_invocations
       WHERE triggered_at BETWEEN p_window_start AND p_window_end
    ),
    'audit_trail_complete', TRUE
  );

  -- sha256 placeholder until file upload provides the real hash
  v_sha256 := COALESCE(p_sha256, encode(digest(v_manifest::text, 'sha256'), 'hex'));

  -- Sign
  v_signature := ottoq_sign_bundle(v_bundle_id, p_window_start, p_window_end, v_sha256, p_signing_key_id);
  IF v_signature IS NULL THEN
    -- Fail-open: record bundle but flag missing signature
    v_signature := 'UNSIGNED:no_signing_secret_available';
  END IF;

  INSERT INTO ottoq_audit_bundles (
    bundle_id, bundle_code, fleet_operator_id,
    report_ids, event_id_range_low, event_id_range_high,
    window_start, window_end,
    format, storage_path, size_bytes, sha256,
    signature, signature_key_id, signature_algorithm,
    manifest, generated_by_actor_type, generated_by_actor_id, expires_at
  ) VALUES (
    v_bundle_id, p_bundle_code, p_fleet_operator_id,
    p_report_ids, v_event_low, v_event_high,
    p_window_start, p_window_end,
    p_format, p_storage_path, p_size_bytes, v_sha256,
    v_signature, p_signing_key_id, 'HMAC-SHA-256',
    v_manifest, p_generated_by_actor_type, p_generated_by_actor_id, p_expires_at
  );

  PERFORM ottoq_record_event(
    p_actor_type        := p_generated_by_actor_type,
    p_actor_id          := p_generated_by_actor_id,
    p_event_type        := 'audit.bundle_generated',
    p_entity_type       := 'audit_bundle',
    p_entity_id         := v_bundle_id,
    p_fleet_operator_id := p_fleet_operator_id,
    p_payload           := jsonb_build_object(
      'bundle_code', p_bundle_code,
      'report_ids', to_jsonb(p_report_ids),
      'manifest', v_manifest,
      'signature_present', (v_signature NOT LIKE 'UNSIGNED:%')
    ),
    p_severity          := 'info'
  );

  RETURN v_bundle_id;
END;
$function$

-- ===== ottoq_generate_incident_report =====
CREATE OR REPLACE FUNCTION public.ottoq_generate_incident_report(p_triggering_event_id uuid, p_incident_type text DEFAULT NULL::text, p_window_minutes_before integer DEFAULT 15, p_window_minutes_after integer DEFAULT 60, p_root_cause_summary text DEFAULT NULL::text, p_generated_by_actor_type text DEFAULT 'ottoq_engine'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_id                 UUID := gen_random_uuid();
  v_event              ottoq_events%ROWTYPE;
  v_window_start       TIMESTAMPTZ;
  v_window_end         TIMESTAMPTZ;
  v_timeline           JSONB := '[]'::jsonb;
  v_event_ids          UUID[];
  v_events_count       INTEGER;
  v_rule_failures_count INTEGER;
  v_anomaly_count      INTEGER;
  v_override_count     INTEGER;
  v_vehicles_affected  INTEGER;
  v_stalls_affected    INTEGER;
  v_incident_code      TEXT;
BEGIN
  -- Pull triggering event
  SELECT * INTO v_event FROM ottoq_events e WHERE e.event_id = p_triggering_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Triggering event % not found', p_triggering_event_id;
  END IF;

  v_window_start := v_event.occurred_at - (p_window_minutes_before || ' minutes')::INTERVAL;
  v_window_end   := v_event.occurred_at + (p_window_minutes_after  || ' minutes')::INTERVAL;

  -- Build timeline
  SELECT
    jsonb_agg(jsonb_build_object(
      'at', out_occurred_at, 'kind', out_kind, 'subject', out_subject,
      'summary', out_summary, 'severity', out_severity,
      'actor_type', out_actor_type, 'actor_id', out_actor_id,
      'event_id', out_event_id, 'payload', out_payload
    ) ORDER BY out_occurred_at),
    array_agg(out_event_id) FILTER (WHERE out_event_id IS NOT NULL)
    INTO v_timeline, v_event_ids
  FROM ottoq_replay_window(v_window_start, v_window_end,
                           v_event.fleet_operator_id, v_event.depot_id,
                           NULL, v_event.correlation_id);

  -- Stats
  v_events_count       := jsonb_array_length(COALESCE(v_timeline, '[]'::jsonb));
  v_rule_failures_count := (
    SELECT count(*) FROM ottoq_rule_evaluations
     WHERE evaluated_at BETWEEN v_window_start AND v_window_end
       AND passed = FALSE
       AND ((v_event.depot_id IS NULL) OR depot_id = v_event.depot_id)
  );
  v_anomaly_count := (
    SELECT count(*) FROM ottoq_anomaly_observations
     WHERE observed_at BETWEEN v_window_start AND v_window_end
       AND is_anomaly = TRUE
       AND ((v_event.depot_id IS NULL) OR depot_id = v_event.depot_id)
  );
  v_override_count := (
    SELECT count(*) FROM ottoq_rule_evaluations
     WHERE evaluated_at BETWEEN v_window_start AND v_window_end
       AND enforcement_taken = 'overridden'
       AND ((v_event.depot_id IS NULL) OR depot_id = v_event.depot_id)
  );
  v_vehicles_affected := (
    SELECT count(DISTINCT entity_id) FROM ottoq_events
     WHERE occurred_at BETWEEN v_window_start AND v_window_end
       AND entity_type = 'vehicle'
       AND ((v_event.depot_id IS NULL) OR depot_id = v_event.depot_id)
  );
  v_stalls_affected := (
    SELECT count(DISTINCT entity_id) FROM ottoq_events
     WHERE occurred_at BETWEEN v_window_start AND v_window_end
       AND entity_type = 'stall'
       AND ((v_event.depot_id IS NULL) OR depot_id = v_event.depot_id)
  );

  v_incident_code := 'INC-' || to_char(v_event.occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD-HH24MI')
                     || '-' || upper(substr(v_id::text, 1, 6));

  -- Insert report
  INSERT INTO ottoq_incident_reports (
    incident_report_id, incident_code,
    incident_type, triggered_at, triggering_event_id, source_correlation_id,
    fleet_operator_id, depot_id,
    window_start, window_end,
    timeline, event_ids_in_timeline,
    duration_seconds, events_in_window, rule_failures_count,
    anomaly_count, override_count, vehicles_affected, stalls_affected,
    root_cause_summary, generated_by_actor_type,
    payload
  ) VALUES (
    v_id, v_incident_code,
    COALESCE(p_incident_type,
             CASE
               WHEN v_event.event_type LIKE 'emergency.%' THEN 'emergency_cascade'
               WHEN v_event.severity = 'safety_critical'  THEN 'safety_event'
               WHEN v_event.event_type LIKE 'anomaly.critical%' THEN 'anomaly_critical'
               WHEN v_event.event_type = 'sla.violation_recorded' THEN 'sla_critical_breach'
               ELSE 'other'
             END),
    v_event.occurred_at, p_triggering_event_id, v_event.correlation_id,
    v_event.fleet_operator_id, v_event.depot_id,
    v_window_start, v_window_end,
    COALESCE(v_timeline, '[]'::jsonb), COALESCE(v_event_ids, '{}'::uuid[]),
    EXTRACT(EPOCH FROM (v_window_end - v_window_start))::INTEGER,
    v_events_count, v_rule_failures_count,
    v_anomaly_count, v_override_count, v_vehicles_affected, v_stalls_affected,
    p_root_cause_summary, p_generated_by_actor_type,
    jsonb_build_object('triggering_event_type', v_event.event_type,
                       'triggering_severity', v_event.severity)
  );

  -- Emit Layer-1 event
  PERFORM ottoq_record_event(
    p_actor_type    := p_generated_by_actor_type,
    p_event_type    := 'incident.report_generated',
    p_entity_type   := 'incident_report',
    p_entity_id     := v_id,
    p_fleet_operator_id := v_event.fleet_operator_id,
    p_depot_id      := v_event.depot_id,
    p_payload       := jsonb_build_object(
      'incident_code', v_incident_code,
      'triggering_event_id', p_triggering_event_id,
      'window_minutes_before', p_window_minutes_before,
      'window_minutes_after', p_window_minutes_after,
      'events_in_window', v_events_count
    ),
    p_severity      := 'info',
    p_parent_event_id := p_triggering_event_id,
    p_correlation_id := v_event.correlation_id
  );

  RETURN v_id;
END;
$function$

-- ===== ottoq_get_active_sla =====
CREATE OR REPLACE FUNCTION public.ottoq_get_active_sla(p_fleet_operator_id uuid)
 RETURNS ottoq_fleet_operator_slas
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT * FROM ottoq_fleet_operator_slas
   WHERE fleet_operator_id = p_fleet_operator_id
     AND status = 'active'
     AND effective_from <= NOW()
     AND (effective_until IS NULL OR effective_until > NOW())
   ORDER BY version DESC
   LIMIT 1;
$function$


-- ===== ottoq_get_feature =====
CREATE OR REPLACE FUNCTION public.ottoq_get_feature(p_feature_name text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_as_of timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS ottoq_feature_values
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_as_of TIMESTAMPTZ := COALESCE(p_as_of, NOW());
  v_row   ottoq_feature_values%ROWTYPE;
BEGIN
  SELECT * INTO v_row
    FROM ottoq_feature_values fv
   WHERE fv.feature_name = p_feature_name
     AND ((fv.entity_id IS NULL AND p_entity_id IS NULL)
          OR fv.entity_id = p_entity_id)
     AND fv.entity_type = p_entity_type
     AND fv.valid_from <= v_as_of
     AND (fv.valid_until IS NULL OR fv.valid_until > v_as_of)
   ORDER BY fv.valid_from DESC
   LIMIT 1;
  RETURN v_row;
END;
$function$


-- ===== ottoq_get_feature_value_jsonb =====
CREATE OR REPLACE FUNCTION public.ottoq_get_feature_value_jsonb(p_feature_name text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_as_of timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_row    ottoq_feature_values%ROWTYPE;
  v_result JSONB;
BEGIN
  v_row := ottoq_get_feature(p_feature_name, p_entity_type, p_entity_id, p_as_of);
  IF v_row.value_id IS NULL THEN
    RETURN jsonb_build_object('feature_name', p_feature_name, 'available', FALSE);
  END IF;
  v_result := jsonb_build_object(
    'feature_name', v_row.feature_name,
    'available', TRUE,
    'value', COALESCE(
      to_jsonb(v_row.value_numeric),
      to_jsonb(v_row.value_integer),
      to_jsonb(v_row.value_boolean),
      to_jsonb(v_row.value_text),
      to_jsonb(v_row.value_timestamp),
      v_row.value_json
    ),
    'observation_time', v_row.observation_time,
    'valid_from', v_row.valid_from,
    'age_seconds', EXTRACT(EPOCH FROM (NOW() - v_row.observation_time)),
    'feature_version', v_row.feature_version,
    'quality_score', v_row.quality_score,
    'is_imputed', v_row.is_imputed
  );
  RETURN v_result;
END;
$function$


-- ===== ottoq_greedy_tick =====
CREATE OR REPLACE FUNCTION public.ottoq_greedy_tick(p_sim_run_id uuid)
 RETURNS ottoq_decide_tick_result
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_clock timestamptz; v_tick bigint; v_disp int; v_charge int;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count INTO v_depot, v_clock, v_tick
    FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF v_depot IS NULL THEN RETURN ROW(0,NULL,0,0,0,0,0,0,0)::ottoq_decide_tick_result; END IF;
  v_charge := ottoq_sim_auto_charge_assign_tick(p_sim_run_id, v_clock);
  v_disp := ottoq_sim_auto_dispatch_tick(p_sim_run_id, v_clock, 30);
  RETURN ROW(v_tick, v_clock, COALESCE(v_disp,0)+COALESCE(v_charge,0), COALESCE(v_disp,0)+COALESCE(v_charge,0), 0,0,0,0,0)::ottoq_decide_tick_result;
END;
$function$


-- ===== ottoq_honour_reservation_proposal =====
CREATE OR REPLACE FUNCTION public.ottoq_honour_reservation_proposal(p_sim_run_id uuid, p_vehicle_id uuid, p_depot_id uuid, p_ctx jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_now timestamptz := COALESCE(NULLIF(p_ctx->>'now_ts','')::timestamptz, now());
  v_resv_stall uuid; v_had_resv boolean; v_prop jsonb; v_plan jsonb; v_atoms jsonb;
BEGIN
  -- does this vehicle hold ANY live reservation on a charge stall (honourable or not)?
  v_had_resv := EXISTS (SELECT 1 FROM stalls s
                         WHERE s.reserved_by = p_vehicle_id
                           AND s.reservation_expires_at > v_now
                           AND s.stall_type IN ('dcfc','l2'));

  -- is that reservation currently HONOURABLE (stall free + charger available)?
  SELECT s.id INTO v_resv_stall
    FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.reserved_by = p_vehicle_id
     AND s.reservation_expires_at > v_now
     AND s.stall_type IN ('dcfc','l2')
     AND s.current_vehicle_id IS NULL
     AND c.station_state = 'Available'
     AND c.last_heartbeat_at >= v_now - interval '90 seconds'
   ORDER BY s.id LIMIT 1;

  IF v_resv_stall IS NOT NULL THEN
    -- HONOUR: deterministic heuristic prefers the reserved stall (ORDER BY reserved_by=self first)
    v_prop := ottoq_l2_propose_stall_assignment(p_vehicle_id, p_depot_id, p_ctx);
    IF NOT COALESCE((v_prop->>'abstain')::boolean, true)
       AND (v_prop->>'stall_id')::uuid = v_resv_stall THEN
      RETURN v_prop || jsonb_build_object('source','reservation_honoured','honoured_stall',v_resv_stall);
    ELSIF v_had_resv THEN
      -- ORCH-1b: the booking changed — rebuild the timed plan against the new
      -- stall and TELL THE VEHICLE (update downlink), never a silent re-route.
      BEGIN
        SELECT vn.atoms INTO v_atoms FROM ottoq_visit_needs vn
         WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
         ORDER BY vn.created_at DESC LIMIT 1;
        v_plan := ottoq_build_workflow_plan(p_vehicle_id, p_sim_run_id, v_now, v_atoms);
        PERFORM ottoq_comms_send_command(p_sim_run_id, p_vehicle_id, 'proceed_to_stall',
          jsonb_build_object('plan_update','reassigned','stall_id', v_prop->>'stall_id',
                             'plan', v_plan), v_now, false);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      RETURN COALESCE(v_prop,'{}'::jsonb) || jsonb_build_object('source','reservation_reassigned','plan_update', true);
    END IF;
    RETURN v_prop;
  END IF;

  -- no honourable reservation: optimizer-first, heuristic fallback (unchanged behaviour)
  v_prop := COALESCE(
    ottoq_l2_external_proposal(p_sim_run_id, 'stall_assignment', 'vehicle', p_vehicle_id),
    ottoq_l2_propose_stall_assignment(p_vehicle_id, p_depot_id, p_ctx));
  IF v_had_resv THEN
    -- booking broken (stall/charger gone): re-plan against the re-pick + notify the vehicle
    BEGIN
      SELECT vn.atoms INTO v_atoms FROM ottoq_visit_needs vn
       WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
       ORDER BY vn.created_at DESC LIMIT 1;
      v_plan := ottoq_build_workflow_plan(p_vehicle_id, p_sim_run_id, v_now, v_atoms);
      PERFORM ottoq_comms_send_command(p_sim_run_id, p_vehicle_id, 'proceed_to_stall',
        jsonb_build_object('plan_update','rebooked','stall_id', v_prop->>'stall_id',
                           'plan', v_plan), v_now, false);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN COALESCE(v_prop,'{}'::jsonb) || jsonb_build_object('source','reservation_broken','plan_update', true);
  END IF;
  RETURN v_prop;
END;
$function$


-- ===== ottoq_inbound_forecast =====
CREATE OR REPLACE FUNCTION public.ottoq_inbound_forecast(p_depot_id uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid, p_horizon_min numeric DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run    ottoq_sim_runs%ROWTYPE;
  v_clock  timestamptz;
  v_end    timestamptz;
  v_buckets jsonb;
  v_needs   jsonb;
  v_cap     jsonb;
  v_inbound int;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs
   WHERE depot_id = p_depot_id AND status = 'running'
   ORDER BY started_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_live_run');
  END IF;
  v_clock := COALESCE(v_run.sim_clock_current, now());
  v_end   := v_clock + (p_horizon_min || ' minutes')::interval;

  -- inbound set: returning now, or active with a scheduled return inside the horizon
  WITH inbound AS (
    SELECT d.vehicle_id, d.status,
           GREATEST(0, EXTRACT(EPOCH FROM (COALESCE(d.scheduled_return_at, v_clock) - v_clock))/60.0) AS eta_min,
           COALESCE((d.return_evidence->>'soc_at_decision')::numeric, v.current_soc) AS soc_est,
           d.return_trigger
      FROM ottoq_vehicle_dispatches d
      JOIN vehicles v ON v.id = d.vehicle_id
     WHERE d.sim_run_id = v_run.sim_run_id
       AND ( d.status = 'returning'
          OR (d.status = 'active' AND d.scheduled_return_at <= v_end) )
  )
  SELECT COUNT(*),
         jsonb_build_object(
           'q0_15',  COUNT(*) FILTER (WHERE eta_min < 15),
           'q15_30', COUNT(*) FILTER (WHERE eta_min >= 15 AND eta_min < 30),
           'q30_45', COUNT(*) FILTER (WHERE eta_min >= 30 AND eta_min < 45),
           'q45_60', COUNT(*) FILTER (WHERE eta_min >= 45),
           'soc_min', round(min(soc_est), 1), 'soc_avg', round(avg(soc_est), 1), 'soc_max', round(max(soc_est), 1),
           'critical', COUNT(*) FILTER (WHERE return_trigger IN ('critical_reserve','low_soc_reserve')))
    INTO v_inbound, v_buckets
    FROM inbound;

  -- what the inbound fleet will need (from already-booked appointments + open needs)
  SELECT jsonb_build_object(
      'charge_dcfc', COUNT(*) FILTER (WHERE vn.meta->'workflow_plan'->0->>'svc' = 'charge'
                                        AND COALESCE(vn.meta->>'charger_class','dcfc') = 'dcfc'),
      'charge_l2',   COUNT(*) FILTER (WHERE vn.meta->'workflow_plan'->0->>'svc' = 'charge'
                                        AND vn.meta->>'charger_class' = 'l2'),
      'bay_work',    COUNT(*) FILTER (WHERE EXISTS (
                        SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                         WHERE a->>'concurrency' = 'bay' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))),
      'booked_total', COUNT(*))
    INTO v_needs
    FROM ottoq_visit_needs vn
   WHERE vn.sim_run_id = v_run.sim_run_id AND vn.status IN ('open','in_progress')
     AND vn.vehicle_id IN (
       SELECT d.vehicle_id FROM ottoq_vehicle_dispatches d
        WHERE d.sim_run_id = v_run.sim_run_id
          AND (d.status = 'returning' OR (d.status = 'active' AND d.scheduled_return_at <= v_end)));

  -- absorption capacity: free now + charging sessions likely to free up inside the horizon
  SELECT jsonb_build_object(
      'dcfc_free',   COUNT(*) FILTER (WHERE s.stall_type::text = 'dcfc' AND s.status = 'available'),
      'l2_free',     COUNT(*) FILTER (WHERE s.stall_type::text = 'l2'   AND s.status = 'available'),
      'staging_free',COUNT(*) FILTER (WHERE s.stall_type::text = 'staging' AND s.status = 'available'),
      'freeing_soon', (SELECT COUNT(*) FROM ocpp_sessions cs
                        JOIN vehicles cv ON cv.id = cs.vehicle_id
                       WHERE cs.depot_id = p_depot_id AND cs.status = 'active'
                         AND cv.current_soc >= COALESCE(cv.target_soc, 90) - 8))
    INTO v_cap
    FROM stalls s WHERE s.depot_id = p_depot_id;

  RETURN jsonb_build_object(
    'ok', true, 'sim_run_id', v_run.sim_run_id, 'as_of', v_clock, 'horizon_min', p_horizon_min,
    'inbound_total', v_inbound, 'arrivals', v_buckets, 'needs', v_needs, 'capacity', v_cap,
    'pressure', jsonb_build_object(
      'charge_demand', COALESCE((v_needs->>'charge_dcfc')::int, 0) + COALESCE((v_needs->>'charge_l2')::int, 0),
      'charge_supply', COALESCE((v_cap->>'dcfc_free')::int, 0) + COALESCE((v_cap->>'l2_free')::int, 0)
                     + COALESCE((v_cap->>'freeing_soon')::int, 0),
      'saturated', (COALESCE((v_needs->>'charge_dcfc')::int, 0) + COALESCE((v_needs->>'charge_l2')::int, 0))
                 > (COALESCE((v_cap->>'dcfc_free')::int, 0) + COALESCE((v_cap->>'l2_free')::int, 0)
                  + COALESCE((v_cap->>'freeing_soon')::int, 0))));
END;
$function$


-- ===== ottoq_indepot_reassignment_guard =====
CREATE OR REPLACE FUNCTION public.ottoq_indepot_reassignment_guard(p_vehicle_id uuid, p_sim_run_id uuid, p_reason text DEFAULT 'optimization'::text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh vehicles%ROWTYPE;
  v_approval uuid;
  v_sev text;
  v_mid boolean;
  v_enforce numeric;
  v_pay jsonb;
  v_immob boolean;
  v_req numeric;
  v_defer_class text;
  v_bay boolean;
  v_si boolean;          -- service-incompatible: the SERVICE cannot safely continue in place
  v_si_basis text;
  v_fault_class text;
BEGIN
  SELECT * INTO v_veh FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('allowed', false, 'reason', 'vehicle_not_found'); END IF;

  IF v_veh.current_state IN ('deployed','en_route_to_depot','en_route_to_deployment','offline') THEN
    RETURN jsonb_build_object('allowed', true, 'mode', 'outside_walls');
  END IF;

  v_sev     := lower(COALESCE(p_payload->>'severity',''));
  v_mid     := v_veh.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','charging_dcfc','charging_l2');
  v_bay     := v_veh.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay');
  v_enforce := COALESCE(ottoq_policy_get(p_sim_run_id, 'indepot_guard_enforce', 1), 1);
  v_pay     := COALESCE(p_payload, '{}'::jsonb)
               || jsonb_build_object('reason', p_reason, 'state', v_veh.current_state::text, 'mid_service', v_mid);

  -- ESCAPE HATCH A: policy kill-switch restores the pre-fix auto-allow for all fault traffic.
  IF v_enforce < 1 AND p_reason IN ('resource_fault','vehicle_fault') THEN
    RETURN jsonb_build_object('allowed', true, 'mode', 'legacy_auto_allow', 'recorded', false);
  END IF;

  -- RESOURCE FAULT: the SPACE broke. The vehicle physically cannot stay, so it still moves --
  -- but it is now RECORDED as a gated decision instead of being silently waved through.
  IF p_reason = 'resource_fault' THEN
    INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
           requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
    VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
            v_pay || jsonb_build_object('gate_mode','resource_fault_auto_reroute',
                                        'auto_reason','space_unusable_vehicle_must_move'),
            now(), now(), now() + interval '30 minutes', 'high', 'approved', now(),
            'auto_gate:resource_fault')
    RETURNING approval_id INTO v_approval;
    RETURN jsonb_build_object('allowed', true, 'mode', 'resource_fault_auto_reroute',
                              'recorded', true, 'approval_id', v_approval, 'preserve_work', true,
                              'rebook_required', true);
  END IF;

  -- VEHICLE FAULT: the vehicle broke; the bay itself is fine.
  IF p_reason = 'vehicle_fault' THEN

    -- No atomic work to protect. Allow, audited. (Unchanged.)
    IF NOT v_mid THEN
      INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
             requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
      VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
              v_pay || jsonb_build_object('gate_mode','vehicle_fault_not_in_service'),
              now(), now(), now() + interval '30 minutes', 'normal', 'approved', now(),
              'auto_gate:vehicle_fault_not_in_service')
      RETURNING approval_id INTO v_approval;
      RETURN jsonb_build_object('allowed', true, 'mode', 'vehicle_fault_not_in_service',
                                'recorded', true, 'approval_id', v_approval);
    END IF;

    -- ══════════════ PHASE 10 FIX A (kept) ══════════════
    -- SEVERITY IS A CONSEQUENCE RATING, NOT A DISPOSITION.
    v_immob      := COALESCE((p_payload->>'immobilizing')::boolean, false);
    v_fault_class:= NULLIF(p_payload->>'fault_class','');
    v_req        := COALESCE(ottoq_policy_get(p_sim_run_id,'indepot_critical_requires_immobilizing',1),1);

    -- ══════════════ PHASE 12 FIX (P2) — IMMOBILIZING IS NOT A LICENCE TO CUT THE WORK ══════════════
    -- MEASURED (phase 11, seed 424242): all 12 work-cutting evictions came through this branch,
    -- 10 of them off charging_l2, destroying 595.56 of the 641.30 minutes -- avg 66.17 min each,
    -- max 139.96. The predicate that let them through was `immobilizing`, and immobilizing is
    -- the WRONG question for a vehicle sitting on a plug.
    --   "Immobilizing" answers: can the vehicle LEAVE UNDER ITS OWN POWER?  -> tow vs drive-away.
    --   It does NOT answer: can the SERVICE SAFELY CONTINUE WHERE IT IS?
    -- A charger does not care that the drive system, steering or brakes are broken. A vehicle
    -- that cannot move cannot be "evicted" at all -- it must be TOWED, and it keeps occupying
    -- that stall until the tow arrives, so terminating the charge buys the depot nothing and
    -- throws away the energy work. The faults that genuinely forbid continuing in place are the
    -- ENERGY/THERMAL ones (HV isolation, battery thermal, charge-system) plus anything in a BAY,
    -- where the cycle physically requires the vehicle to move.
    -- `service_incompatible` is the new explicit signal (production: the OEM fault code's
    -- class). TOTAL FUNCTION: a caller that does not send it falls back to the old
    -- `immobilizing` behaviour, so no other caller changes.
    v_si := COALESCE((p_payload->>'service_incompatible')::boolean, v_immob);
    v_si_basis := CASE WHEN p_payload ? 'service_incompatible' THEN 'fault_class' ELSE 'legacy_immobilizing_fallback' END;
    IF v_immob AND v_bay THEN
      -- A vehicle that cannot move cannot complete a wash/detail/service cycle.
      v_si := true; v_si_basis := 'immobilizing_in_bay';
    END IF;

    IF v_sev = 'critical' AND (v_si OR v_req < 1) THEN
      -- ZONE C, genuine: the service cannot continue in place. Evict -- safety first, and the
      -- tow/tech path must never deadlock -- but it is a GATED, AUDITED decision and the caller
      -- is told it MUST preserve the outstanding work and RE-BOOK it.
      -- gate_mode string is deliberately UNCHANGED so phase-10/11/12 harness sections stay
      -- like-for-like; the narrowed basis is stamped alongside it.
      INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
             requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
      VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
              v_pay || jsonb_build_object('gate_mode','vehicle_fault_critical_immobilizing',
                        'immobilizing', v_immob,
                        'service_incompatible', v_si,
                        'evict_basis', v_si_basis,
                        'fault_class', v_fault_class,
                        'auto_reason', CASE WHEN v_req < 1 THEN 'policy_immobilizing_check_disabled'
                                            ELSE 'service_cannot_continue_in_place' END,
                        'work_disposition','outstanding_work_must_survive_as_due_and_be_rebooked'),
              now(), now(), now() + interval '30 minutes', 'high', 'approved', now(),
              'auto_gate:vehicle_fault_critical_immobilizing')
      RETURNING approval_id INTO v_approval;
      RETURN jsonb_build_object('allowed', true, 'mode', 'vehicle_fault_critical_immobilizing',
                                'recorded', true, 'approval_id', v_approval, 'preserve_work', true,
                                'rebook_required', true,
                                'service_incompatible', v_si, 'evict_basis', v_si_basis,
                                'immobilizing', v_immob, 'fault_class', v_fault_class);
    END IF;

    -- MID-SERVICE, SERVICE CAN CONTINUE: DEFER. The atomic visit finishes first; the exception
    -- handler resumes the eviction afterwards. THREE defer classes, three budgets:
    --   immobilizing_awaiting_tow  -- broken but charge-safe: it is going nowhere without a tow
    --                                 anyway, so let the plug finish. BOUNDED budget, never open.
    --   critical_not_immobilizing  -- short budget, acted on quickly.
    --   major                      -- original budget.
    -- NO DEADLOCK: every class still exits on service-window-complete, left-service-state,
    -- technician approval (this row is inserted HIGH priority and is visible immediately), or a
    -- bounded budget expiry. The tow/tech path is never closed, only sequenced.
    v_defer_class := CASE WHEN v_immob            THEN 'immobilizing_awaiting_tow'
                          WHEN v_sev='critical'   THEN 'critical_not_immobilizing'
                          ELSE 'major' END;
    INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
           requested_at, decide_after, expires_at, priority)
    SELECT 'indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
           v_pay || jsonb_build_object('gate_mode','deferred_awaiting_tech',
                                       'defer_class', v_defer_class,
                                       'immobilizing', v_immob,
                                       'service_incompatible', v_si,
                                       'fault_class', v_fault_class),
           now(), now(), now() + interval '30 minutes',
           CASE WHEN v_sev='critical' OR v_immob THEN 'high' ELSE 'normal' END
    WHERE NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals a
                       WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
                         AND a.status = 'pending')
    RETURNING approval_id INTO v_approval;
    IF v_approval IS NULL THEN
      -- AUDIT-STAMP RESCUE: the INSERT was suppressed because a pending indepot_reassign
      -- already exists for this vehicle. The decision IS still audited -- by THAT row -- so
      -- return its id instead of NULL. MEASURED (live run 4921c87d): 24 of 45 deferrals lost
      -- their audit stamp this way; phase 10/11 never hit it because no other writer left
      -- pending approvals behind.
      SELECT a.approval_id INTO v_approval FROM ottoq_ops_approvals a
       WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
         AND a.status = 'pending' ORDER BY a.requested_at DESC LIMIT 1;
    END IF;
    RETURN jsonb_build_object('allowed', false, 'mode', 'deferred_awaiting_tech',
                              'defer_class', v_defer_class,
                              'immobilizing', v_immob, 'service_incompatible', v_si,
                              'fault_class', v_fault_class,
                              'approval_id', v_approval, 'state', v_veh.current_state::text);
  END IF;

  -- Everything else (optimization / congestion / operator request) defers, as before.
  INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id,
         payload, requested_at, decide_after, expires_at, priority)
  SELECT 'indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
         v_pay, now(), now(), now() + interval '30 minutes', 'normal'
  WHERE NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals a
                     WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
                       AND a.status = 'pending')
  RETURNING approval_id INTO v_approval;
    IF v_approval IS NULL THEN
    -- AUDIT-STAMP RESCUE: the INSERT was suppressed because a pending indepot_reassign
    -- already exists for this vehicle. The decision IS still audited -- by THAT row -- so
    -- return its id instead of NULL. MEASURED (live run 4921c87d): 24 of 45 deferrals lost
    -- their audit stamp this way; phase 10/11 never hit it because no other writer left
    -- pending approvals behind.
    SELECT a.approval_id INTO v_approval FROM ottoq_ops_approvals a
     WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
       AND a.status = 'pending' ORDER BY a.requested_at DESC LIMIT 1;
  END IF;
  RETURN jsonb_build_object('allowed', false, 'mode', 'awaiting_tech_approval',
                            'approval_id', v_approval, 'state', v_veh.current_state::text);
END;
$function$


-- ===== ottoq_ingest_service_complete =====
CREATE OR REPLACE FUNCTION public.ottoq_ingest_service_complete(p_vehicle_id uuid, p_source text DEFAULT 'production'::text, p_actor text DEFAULT 'depot_tech'::text, p_services text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh    vehicles%ROWTYPE;
  v_run    ottoq_sim_runs%ROWTYPE;
  v_clock  timestamptz;
  v_s      text;
  v_before int; v_after int;
BEGIN
  SELECT * INTO v_veh FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'vehicle_not_found'); END IF;

  SELECT * INTO v_run FROM ottoq_sim_runs
   WHERE depot_id = v_veh.home_depot_id AND status = 'running'
   ORDER BY started_at DESC LIMIT 1;
  v_clock := COALESCE(v_run.sim_clock_current, now());

  IF p_services IS NOT NULL AND array_length(p_services, 1) > 0 THEN
    IF v_veh.current_state IN ('deployed','en_route_to_deployment','offline') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'vehicle_not_in_depot', 'state', v_veh.current_state::text);
    END IF;
    SELECT COUNT(*) INTO v_before FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
       AND a->>'svc' = ANY(p_services) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');
    PERFORM ottoq_mark_visit_atoms_done(p_vehicle_id, p_services, v_clock);
    SELECT COUNT(*) INTO v_after FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
       AND a->>'svc' = ANY(p_services) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');
    IF v_run.sim_run_id IS NOT NULL AND v_before - v_after > 0 THEN
      FOREACH v_s IN ARRAY p_services LOOP
        BEGIN PERFORM ottoq_wear_mark_serviced(p_vehicle_id, v_run.sim_run_id, v_s, v_clock);
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END LOOP;
    END IF;
    BEGIN
      PERFORM ottoq_record_event(
        p_actor_type := 'depot_tech', p_actor_id := p_actor,
        p_event_type := 'ops.services_completed_reported', p_entity_type := 'vehicle', p_entity_id := p_vehicle_id,
        p_payload := jsonb_build_object('services', to_jsonb(p_services), 'atoms_matched', v_before - v_after,
                                        'state', v_veh.current_state::text, 'source', p_source),
        p_severity := CASE WHEN v_before - v_after = 0 THEN 'warning' ELSE 'info' END,
        p_ingest_source := 'production', p_data_source := 'production',
        p_sim_run_id := v_run.sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN jsonb_build_object('ok', v_before - v_after > 0, 'vehicle_id', p_vehicle_id,
      'services_reported', to_jsonb(p_services), 'atoms_matched', v_before - v_after,
      'note', CASE WHEN v_before - v_after = 0 THEN 'no open workflow atoms matched the reported services' ELSE NULL END);
  END IF;

  IF v_veh.current_state NOT IN ('in_wash_bay','in_detail_bay','in_service_bay') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_in_bay', 'state', v_veh.current_state::text);
  END IF;
  UPDATE vehicles SET config = jsonb_set(COALESCE(config,'{}'::jsonb), '{service_done}', 'true'::jsonb)
   WHERE id = p_vehicle_id;
  BEGIN
    PERFORM ottoq_record_event(
      p_actor_type := 'depot_tech', p_actor_id := p_actor,
      p_event_type := 'ops.service_completed_reported', p_entity_type := 'vehicle', p_entity_id := p_vehicle_id,
      p_payload := jsonb_build_object('bay', v_veh.current_state::text, 'source', p_source),
      p_severity := 'info', p_ingest_source := 'production', p_data_source := 'production',
      p_sim_run_id := v_run.sim_run_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN jsonb_build_object('ok', true, 'vehicle_id', p_vehicle_id, 'bay', v_veh.current_state::text,
                            'note', 'service_flow will finalize on the next tick');
END;
$function$


-- ===== ottoq_ingest_vehicle_signal =====
CREATE OR REPLACE FUNCTION public.ottoq_ingest_vehicle_signal(p_vehicle_id uuid, p_soc_pct numeric DEFAULT NULL::numeric, p_eta_min numeric DEFAULT NULL::numeric, p_source text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh       vehicles%ROWTYPE;
  v_run       ottoq_sim_runs%ROWTYPE;
  v_dispatch  ottoq_vehicle_dispatches%ROWTYPE;
  v_clock     timestamptz;
  v_dec       jsonb;
  v_marked    boolean := false;
BEGIN
  SELECT * INTO v_veh FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('evaluated', false, 'reason', 'vehicle_not_found');
  END IF;

  -- the live orchestration context for this vehicle's depot (demo run or production_live)
  SELECT * INTO v_run FROM ottoq_sim_runs
   WHERE depot_id = v_veh.home_depot_id AND status = 'running'
   ORDER BY started_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('evaluated', false, 'reason', 'no_live_run');
  END IF;
  v_clock := COALESCE(v_run.sim_clock_current, now());

  -- only vehicles that are OUT get the return handshake; in-depot progression is decide_tick's job
  IF v_veh.current_state NOT IN ('deployed','en_route_to_deployment','offline') THEN
    RETURN jsonb_build_object('evaluated', false, 'reason', 'not_out',
                              'state', v_veh.current_state::text);
  END IF;

  SELECT * INTO v_dispatch FROM ottoq_vehicle_dispatches
   WHERE vehicle_id = p_vehicle_id AND sim_run_id = v_run.sim_run_id AND status = 'active'
   ORDER BY dispatched_at DESC LIMIT 1;

  -- OTTO-Q owns the choice: the return ladder, trigger/urgency/deferrability,
  -- the ETA projection, the appointment (resource reservation + downlink), and
  -- the departure verdict. The twin only executes what comes back.
  v_dec := ottoq_decide_return_on_signal(
             p_vehicle_id, v_run.sim_run_id, v_clock,
             p_soc_pct, v_veh.current_soc, p_eta_min);

  IF NOT COALESCE((v_dec->>'should_return')::boolean, false) THEN
    RETURN jsonb_build_object('evaluated', true, 'should_return', false,
                              'sim_run_id', v_run.sim_run_id);
  END IF;

  -- twin executes the decision: physical bookkeeping only
  IF COALESCE((v_dec->>'depart')::boolean, false) THEN
    IF v_dispatch.dispatch_id IS NOT NULL THEN
      UPDATE ottoq_vehicle_dispatches
         SET status = 'returning',
             return_trigger = v_dec->>'trigger',
             returning_started_at = v_clock,
             return_eta_minutes   = (v_dec->>'eta_min')::numeric,
             scheduled_return_at  = v_clock + (((v_dec->>'eta_min')::numeric) || ' minutes')::interval,
             return_evidence = COALESCE(return_evidence, '{}'::jsonb) || jsonb_build_object(
               'decided_at', v_clock, 'soc_at_decision', p_soc_pct,
               'signal_source', p_source, 'appointment', v_dec->'appointment')
       WHERE dispatch_id = v_dispatch.dispatch_id;
    END IF;
    UPDATE vehicles SET current_state = 'en_route_to_depot'::vehicle_state,
                        last_state_change = v_clock
     WHERE id = p_vehicle_id;
    v_marked := true;
  END IF;

  RETURN jsonb_build_object(
    'evaluated', true, 'should_return', true,
    'trigger', v_dec->>'trigger', 'urgency', v_dec->>'urgency',
    'deferrable', (v_dec->>'deferrable')::boolean,
    'eta_min', (v_dec->>'eta_min')::numeric,
    'vehicle_initiated', (v_dec->>'vehicle_initiated')::boolean,
    'marked_returning', v_marked, 'sim_run_id', v_run.sim_run_id,
    'appointment', v_dec->'appointment');
END;
$function$


-- ===== ottoq_is_overnight_holdout =====
CREATE OR REPLACE FUNCTION public.ottoq_is_overnight_holdout(p_vehicle uuid, p_run uuid, p_clock timestamp with time zone, p_pct integer DEFAULT 1)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT (abs(hashtextextended(
     p_vehicle::text || ':' || p_run::text || ':' ||
     (((p_clock AT TIME ZONE 'America/Chicago') - interval '5 hours')::date)::text, 7)) % 100)
   < GREATEST(1, COALESCE(p_pct,1));
$function$


-- ===== ottoq_itin_close_travel_legs =====
CREATE OR REPLACE FUNCTION public.ottoq_itin_close_travel_legs(p_sim_run_id uuid, p_clock timestamp with time zone, p_max_age_min integer DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_done int := 0; v_amended int := 0; v_stale int := 0;
BEGIN
  -- 1) PLAN COMPLETE: the scheduled duration has elapsed. This — not the twin's
  --    instantaneous state flip — is when a rendered movement is over.
  WITH finished AS (
    UPDATE ottoq_itinerary_legs l
       SET status = 'done', actual_end_sim = p_clock
     WHERE l.sim_run_id = p_sim_run_id
       AND l.duration_basis->>'kind' = 'travel'
       AND l.status NOT IN ('done','amended','skipped')
       AND p_clock >= l.planned_end_sim
    RETURNING 1)
  SELECT count(*) INTO v_done FROM finished;

  -- 2) SUPERSEDED: a newer travel leg replaced this one mid-flight.
  WITH superseded AS (
    UPDATE ottoq_itinerary_legs l
       SET status = 'amended', actual_end_sim = p_clock
     WHERE l.sim_run_id = p_sim_run_id
       AND l.duration_basis->>'kind' = 'travel'
       AND l.status NOT IN ('done','amended','skipped')
       AND EXISTS (SELECT 1 FROM ottoq_itinerary_legs n
                    WHERE n.sim_run_id = l.sim_run_id
                      AND n.vehicle_id = l.vehicle_id
                      AND n.duration_basis->>'kind' = 'travel'
                      AND n.planned_start_sim > l.planned_start_sim)
    RETURNING 1)
  SELECT count(*) INTO v_amended FROM superseded;

  -- 3) STALE valve: a leg whose plan-end somehow never arrives (clock rewind, a
  --    jump backwards) must not pace a car forever.
  WITH stale AS (
    UPDATE ottoq_itinerary_legs l
       SET status = 'skipped', actual_end_sim = p_clock
     WHERE l.sim_run_id = p_sim_run_id
       AND l.duration_basis->>'kind' = 'travel'
       AND l.status NOT IN ('done','amended','skipped')
       AND l.planned_start_sim < p_clock - make_interval(mins => p_max_age_min)
    RETURNING 1)
  SELECT count(*) INTO v_stale FROM stale;

  RETURN v_done + v_amended + v_stale;
END;
$function$


-- ===== ottoq_itin_leg_close =====
CREATE OR REPLACE FUNCTION public.ottoq_itin_leg_close(p_sim_run_id uuid, p_vehicle_id uuid, p_leg_types text[], p_now timestamp with time zone, p_status text DEFAULT 'done'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;
  UPDATE ottoq_itinerary_legs
     SET actual_end_sim = p_now, status = p_status,
         deviation_s = CASE WHEN planned_end_sim IS NULL THEN NULL
                            ELSE EXTRACT(EPOCH FROM (p_now - planned_end_sim))::int END
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle_id
     AND status = 'active' AND leg_type = ANY(p_leg_types);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$


-- ===== ottoq_itin_leg_open =====
CREATE OR REPLACE FUNCTION public.ottoq_itin_leg_open(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_now timestamp with time zone, p_leg_type text, p_to_stall uuid, p_planned_end timestamp with time zone, p_basis jsonb, p_created_by text DEFAULT 'decide_tick'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_itin uuid; v_seq int; v_leg uuid;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN NULL; END IF;
  SELECT itinerary_id INTO v_itin FROM ottoq_vehicle_itineraries
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle_id AND status = 'active'
   ORDER BY created_at DESC LIMIT 1;
  IF v_itin IS NULL THEN
    INSERT INTO ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, created_by, sim_created_at)
    VALUES (p_sim_run_id, p_depot_id, p_vehicle_id, p_created_by, p_now)
    RETURNING itinerary_id INTO v_itin;
  END IF;
  -- N2/M4: reality CLAIMS the matching planned leg (plan-vs-actual per leg);
  -- unplanned events still insert fresh legs below.
  SELECT leg_id INTO v_leg FROM ottoq_itinerary_legs
   WHERE itinerary_id = v_itin AND leg_type = p_leg_type AND status = 'planned'
   ORDER BY seq LIMIT 1;
  IF v_leg IS NOT NULL THEN
    UPDATE ottoq_itinerary_legs
       SET actual_start_sim = p_now, status = 'active', to_stall_id = COALESCE(p_to_stall, to_stall_id),
           duration_basis = duration_basis || COALESCE(p_basis, '{}'::jsonb)
     WHERE leg_id = v_leg;
  ELSE
    SELECT COALESCE(MAX(seq), 0) + 1 INTO v_seq FROM ottoq_itinerary_legs WHERE itinerary_id = v_itin;
    INSERT INTO ottoq_itinerary_legs (
      itinerary_id, sim_run_id, vehicle_id, seq, leg_type, to_stall_id,
      planned_start_sim, planned_end_sim, planned_duration_s, duration_basis,
      actual_start_sim, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle_id, v_seq, p_leg_type, p_to_stall,
      p_now, p_planned_end,
      CASE WHEN p_planned_end IS NULL THEN NULL
           ELSE GREATEST(0, EXTRACT(EPOCH FROM (p_planned_end - p_now)))::int END,
      COALESCE(p_basis, '{}'::jsonb), p_now, 'active')
    RETURNING leg_id INTO v_leg;
  END IF;

  -- LATE BIND (2026-08-02). The calendar row already standing in this stall learns its leg
  -- the moment the leg becomes real. We bind at most ONE live row -- the one whose window
  -- sits closest to now -- and only if no other live row already carries this leg.
  -- 'none' is the resolver's "I looked and found nothing", i.e. UNSET for provenance
  -- purposes -- it must be overwritten here, not preserved.
  -- Fully sub-blocked: this function runs with the CALLER's privileges, so a permission or
  -- constraint problem here must never abort the twin's transaction.
  BEGIN
    IF v_leg IS NOT NULL AND p_to_stall IS NOT NULL THEN
      UPDATE public.ottoq_stall_bookings b
         SET leg_id     = v_leg,
             leg_source = CASE WHEN COALESCE(b.leg_source,'none') = 'none'
                               THEN 'late_bind_leg_open' ELSE b.leg_source END,
             why        = COALESCE(b.why, '') ||
                          format(' | leg %s (%s) opened here at %s',
                                 left(v_leg::text,8), p_leg_type, to_char(p_now,'HH24:MI'))
       WHERE b.booking_id = (
               SELECT bb.booking_id FROM public.ottoq_stall_bookings bb
                WHERE bb.sim_run_id = p_sim_run_id
                  AND bb.stall_id   = p_to_stall
                  AND bb.vehicle_id = p_vehicle_id
                  AND bb.leg_id IS NULL
                  AND bb.state IN ('held','active')
                  AND bb.during && tstzrange(p_now - interval '90 minutes',
                                             p_now + interval '90 minutes', '[)')
                ORDER BY abs(EXTRACT(EPOCH FROM (lower(bb.during) - p_now)))
                LIMIT 1)
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings bz
                          WHERE bz.leg_id = v_leg AND bz.state IN ('held','active'));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_leg;
END; $function$


-- ===== ottoq_itin_travel_leg =====
CREATE OR REPLACE FUNCTION public.ottoq_itin_travel_leg(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_from_stall uuid, p_to_stall uuid, p_start_sim timestamp with time zone, p_leg_type text DEFAULT 'taxi'::text, p_created_by text DEFAULT 'twin'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_leg uuid := gen_random_uuid();
  v_itin uuid; v_seq int; v_from uuid; v_prior_legs int;
  fx numeric; fy numeric; tx numeric; ty numeric;
  v_units numeric; v_metres numeric; v_speed numeric; v_overhead numeric; v_secs numeric;
  v_type text; v_intent text; v_geom text;
  v_scale CONSTANT numeric := 0.3048;  -- metres per FOOT. stalls.relative_x/y are feet
                                        -- (ottoq_site_structures.origin_x_ft etc). 0.4785 was the
                                        -- sitePlan logical unit and made every leg 1.57x too long.
BEGIN
  IF p_sim_run_id IS NULL OR p_to_stall IS NULL OR p_vehicle_id IS NULL OR p_start_sim IS NULL THEN
    RETURN NULL;
  END IF;

  -- (1) caller origin, only if it is a real move
  v_from := CASE WHEN p_from_stall IS NOT DISTINCT FROM p_to_stall THEN NULL ELSE p_from_stall END;

  -- (2) otherwise the last stall this vehicle actually occupied, per its own itinerary
  IF v_from IS NULL THEN
    SELECT l.to_stall_id INTO v_from
      FROM ottoq_itinerary_legs l
     WHERE l.sim_run_id = p_sim_run_id
       AND l.vehicle_id = p_vehicle_id
       AND l.to_stall_id IS NOT NULL
       AND l.to_stall_id <> p_to_stall
       AND l.planned_start_sim <= p_start_sim
     ORDER BY l.planned_start_sim DESC, l.seq DESC
     LIMIT 1;
  END IF;

  SELECT count(*) INTO v_prior_legs FROM ottoq_itinerary_legs
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle_id;

  v_intent := p_leg_type;
  v_type := CASE
    WHEN p_leg_type IN ('arrive','taxi','depart','settle','stage') THEN p_leg_type
    WHEN p_leg_type ILIKE '%gate%' OR p_leg_type ILIKE '%depart%'  THEN 'depart'
    ELSE 'taxi' END;

  SELECT itinerary_id INTO v_itin FROM ottoq_vehicle_itineraries
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle_id AND status = 'active'
   ORDER BY created_at DESC LIMIT 1;
  IF v_itin IS NULL THEN
    INSERT INTO ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, created_by, sim_created_at)
    VALUES (p_sim_run_id, p_depot_id, p_vehicle_id, p_created_by, p_start_sim)
    RETURNING itinerary_id INTO v_itin;
  END IF;
  SELECT COALESCE(MAX(seq), 0) + 1 INTO v_seq FROM ottoq_itinerary_legs WHERE itinerary_id = v_itin;

  SELECT relative_x, relative_y INTO tx, ty FROM stalls WHERE id = p_to_stall;
  IF v_from IS NOT NULL THEN
    SELECT relative_x, relative_y INTO fx, fy FROM stalls WHERE id = v_from;
  END IF;

  v_speed    := GREATEST(0.5, ottoq_policy_get(p_sim_run_id, 'yard_taxi_speed_mps', 3.5));
  v_overhead := GREATEST(0,   ottoq_policy_get(p_sim_run_id, 'yard_manoeuvre_s',    20));

  IF fx IS NOT NULL AND fy IS NOT NULL AND tx IS NOT NULL AND ty IS NOT NULL
     AND NOT (fx = 0 AND fy = 0) AND NOT (tx = 0 AND ty = 0) THEN
    v_units := sqrt( (tx - fx)^2 + (ty - fy)^2 );
    v_geom  := 'measured';
  ELSE
    v_units := ottoq_policy_get(p_sim_run_id, 'yard_default_units', 120);
    v_geom  := CASE
                 WHEN v_from IS NULL AND v_prior_legs = 0 THEN 'arrival_from_offmap'
                 WHEN v_from IS NULL                      THEN 'origin_unresolved'
                 ELSE 'bay_geometry_missing'   -- wash_bay / service_bay are still (0,0)
               END;
  END IF;

  v_metres := v_units * v_scale;
  v_secs   := GREATEST(5.0, (v_metres / v_speed) + v_overhead);

  INSERT INTO ottoq_itinerary_legs (
    leg_id, itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
    from_stall_id, to_stall_id,
    planned_start_sim, planned_end_sim, planned_duration_s,
    actual_start_sim, status, duration_basis)
  VALUES (
    v_leg, v_itin, p_sim_run_id, p_vehicle_id, v_seq, v_type,
    v_from, p_to_stall,
    p_start_sim, p_start_sim + make_interval(secs => v_secs), round(v_secs)::int,
    p_start_sim, 'active',
    jsonb_build_object('kind','travel','intent',v_intent,
                       'units',round(v_units,1),'metres',round(v_metres,1),
                       'speed_mps',v_speed,'manoeuvre_s',v_overhead,
                       'geometry',v_geom,'origin_source',
                         CASE WHEN p_from_stall IS NOT NULL AND p_from_stall <> p_to_stall THEN 'caller'
                              WHEN v_from IS NOT NULL THEN 'leg_history'
                              ELSE 'none' END,
                       'created_by',p_created_by));
  RETURN v_leg;
END;
$function$


-- ===== ottoq_jsonb_diff =====
CREATE OR REPLACE FUNCTION public.ottoq_jsonb_diff(old_doc jsonb, new_doc jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_result JSONB := '{}'::jsonb;
  v_key TEXT;
  v_old_val JSONB;
  v_new_val JSONB;
BEGIN
  -- Keys that changed
  FOR v_key IN
    SELECT DISTINCT key FROM (
      SELECT jsonb_object_keys(COALESCE(old_doc, '{}'::jsonb)) AS key
      UNION
      SELECT jsonb_object_keys(COALESCE(new_doc, '{}'::jsonb)) AS key
    ) k
  LOOP
    v_old_val := COALESCE(old_doc, '{}'::jsonb) -> v_key;
    v_new_val := COALESCE(new_doc, '{}'::jsonb) -> v_key;
    IF v_old_val IS DISTINCT FROM v_new_val THEN
      v_result := v_result || jsonb_build_object(v_key,
        jsonb_build_object('from', v_old_val, 'to', v_new_val));
    END IF;
  END LOOP;
  RETURN v_result;
END;
$function$


-- ===== ottoq_l1_override_authorized =====
CREATE OR REPLACE FUNCTION public.ottoq_l1_override_authorized(p_rule_code text, p_actor_type text, p_actor_id text, p_justification text, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_fleet_operator_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rule ottoq_rules%ROWTYPE;
  v_id   uuid;
BEGIN
  SELECT * INTO v_rule FROM ottoq_rules
   WHERE rule_code = p_rule_code AND status IN ('active','shadow')
   ORDER BY version DESC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'OTTOQ_OVERRIDE_UNKNOWN_RULE: %', p_rule_code USING ERRCODE = 'P0001';
  END IF;

  -- 1. the rule must be overridable at all
  IF NOT COALESCE(v_rule.override_allowed, FALSE) THEN
    RAISE EXCEPTION 'OTTOQ_OVERRIDE_FORBIDDEN: rule % is not overridable', p_rule_code USING ERRCODE = 'P0001';
  END IF;

  -- 2. the actor's role must meet/exceed the rule's required min role
  IF ottoq_role_rank(p_actor_type) < ottoq_role_rank(COALESCE(v_rule.override_min_role,'command_center_operator')) THEN
    RAISE EXCEPTION 'OTTOQ_OVERRIDE_ROLE_INSUFFICIENT: % requires %, got %',
      p_rule_code, COALESCE(v_rule.override_min_role,'command_center_operator'), p_actor_type USING ERRCODE = 'P0001';
  END IF;

  -- 3. justification floor (kept; SM.005 audit-note policy, OD-33)
  IF p_justification IS NULL OR length(trim(p_justification)) < 10 THEN
    RAISE EXCEPTION 'OTTOQ_OVERRIDE_JUSTIFICATION_REQUIRED: >=10 chars' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO ottoq_rule_overrides
    (rule_code, rule_version, entity_type, entity_id, override_actor_type, override_actor_id,
     approved_by, justification, effective_from, depot_id, fleet_operator_id, payload)
  VALUES
    (p_rule_code, v_rule.version, p_entity_type, p_entity_id, p_actor_type, p_actor_id,
     p_actor_id, p_justification, NOW(), p_depot_id, p_fleet_operator_id,
     jsonb_build_object('authorized_by','ottoq_l1_override_authorized','min_role',v_rule.override_min_role))
  RETURNING override_id INTO v_id;
  RETURN v_id;
END;
$function$


-- ===== ottoq_l1_safe_default_bess =====
CREATE OR REPLACE FUNCTION public.ottoq_l1_safe_default_bess(p_bess_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object('verb','bess_idle','bess_id',p_bess_id,'requested_kw',0,'reason','bess_shield_blocked');
$function$


-- ===== ottoq_l1_safe_default_charge_disposition =====
CREATE OR REPLACE FUNCTION public.ottoq_l1_safe_default_charge_disposition(p_vehicle_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object('verb','hold','vehicle_id',p_vehicle_id,'reason','disposition_shield_blocked');
$function$


-- ===== ottoq_l1_safe_default_deploy =====
CREATE OR REPLACE FUNCTION public.ottoq_l1_safe_default_deploy(p_vehicle_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object('verb','hold_in_staging','vehicle_id',p_vehicle_id,'reason','deploy_shield_blocked');
$function$


-- ===== ottoq_l1_safe_default_service =====
CREATE OR REPLACE FUNCTION public.ottoq_l1_safe_default_service(p_vehicle_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object('verb','hold_in_queue','vehicle_id',p_vehicle_id,'reason','service_shield_blocked');
$function$


-- ===== ottoq_l1_safe_default_stall =====
CREATE OR REPLACE FUNCTION public.ottoq_l1_safe_default_stall(p_vehicle_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object('verb','hold_at_gate','vehicle_id',p_vehicle_id,'reason','shield_blocked_proposal','requested_kw',0);
$function$


-- ===== ottoq_l2_external_proposal =====
CREATE OR REPLACE FUNCTION public.ottoq_l2_external_proposal(p_sim_run_id uuid, p_action_context text, p_entity_type text, p_entity_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT CASE
           WHEN p.proposal ? 'source' THEN p.proposal
           ELSE p.proposal || jsonb_build_object('source', p.source)
         END
    FROM public.ottoq_external_proposals p
   WHERE p.sim_run_id = p_sim_run_id AND p.action_context = p_action_context
     AND p.entity_type = p_entity_type AND p.entity_id = p_entity_id
     AND p.status = 'pending'
     -- proposal TTL stays in the REAL domain (see migration note)
     AND GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                  p.created_at + interval '35 minutes') >= now()
     AND (p.action_context <> 'stall_assignment' OR EXISTS (
        SELECT 1 FROM stalls s
          JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
         WHERE s.id = (p.proposal->>'stall_id')::uuid
           AND s.current_vehicle_id IS NULL
           -- SIM-domain: compare reservation expiry against the run's sim clock
           AND (s.reserved_by IS NULL OR s.reserved_by = p_entity_id
                OR s.reservation_expires_at <= COALESCE(
                     (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), now()))
           AND c.station_state = 'Available'
           -- SIM-domain: charger heartbeat freshness against the run's sim clock
           AND c.last_heartbeat_at >= COALESCE(
                 (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), now())
                 - interval '90 seconds'))
   ORDER BY (p.source = 'cuopt') DESC, (p.source = 'cuopt_fallback') DESC, p.created_at DESC
   LIMIT 1
$function$


-- ===== ottoq_l2_optimize_assignments =====
CREATE OR REPLACE FUNCTION public.ottoq_l2_optimize_assignments(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_n int := 0; v_veh RECORD; v_stall_id uuid; v_stall_type text; v_conn_max numeric;
  v_used uuid[] := ARRAY[]::uuid[];
BEGIN
  -- fresh start each tick: clear this run's prior local proposals (avoid stale accumulation)
  DELETE FROM ottoq_external_proposals
   WHERE sim_run_id = p_sim_run_id AND source = 'greedy_constrained' AND action_context = 'stall_assignment';

  FOR v_veh IN
    SELECT v.id, v.current_soc, v.target_soc, v.inlet_type, v.inlet_max_kw, v.fleet_operator_id
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate' AND v.current_soc < COALESCE(v.target_soc,90) - 0.5
       -- FR-3: yield to a fresh cuOpt proposal for this vehicle (cuOpt owns it this tick)
       AND NOT EXISTS (
         SELECT 1 FROM ottoq_external_proposals p
          WHERE p.sim_run_id = p_sim_run_id AND p.action_context = 'stall_assignment'
            AND p.entity_type = 'vehicle' AND p.entity_id = v.id
            AND p.source = 'cuopt' AND p.status = 'pending'
            AND COALESCE(p.expires_at, p.created_at + interval '35 minutes') >= now())
     ORDER BY v.current_soc ASC, v.id              -- urgency: most depleted vehicle picks first
  LOOP
    SELECT s.id, s.stall_type, s.connector_max_kw
      INTO v_stall_id, v_stall_type, v_conn_max
      FROM stalls s
      JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type IN ('dcfc','l2')
       AND s.current_vehicle_id IS NULL
       AND NOT (s.id = ANY(v_used))
       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= now())
       AND c.station_state = 'Available'
       AND c.last_heartbeat_at >= p_sim_clock - INTERVAL '90 seconds'
       AND ( v_veh.inlet_type IS NULL
          OR s.connector_type = v_veh.inlet_type
          OR (s.connector_type = 'Multi' AND v_veh.inlet_type = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
          OR (s.connector_type = 'NACS'  AND v_veh.inlet_type IN ('NACS','Tesla_Proprietary')) )
     ORDER BY
       ( CASE WHEN v_veh.current_soc < 35 AND s.stall_type = 'l2'   THEN 50
              WHEN v_veh.current_soc >= 60 AND s.stall_type = 'dcfc' THEN 40
              ELSE 0 END )
       + COALESCE(s.distance_from_entrance, 50) * 0.1
     ASC
     LIMIT 1;

    IF v_stall_id IS NULL THEN CONTINUE; END IF;
    v_used := array_append(v_used, v_stall_id);

    INSERT INTO ottoq_external_proposals
      (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal, source, status, created_at, expires_at)
    VALUES (p_sim_run_id, p_depot_id, 'stall_assignment', 'vehicle', v_veh.id,
      jsonb_build_object('abstain', false, 'resolved_action_context', 'stall_assignment', 'verb', 'assign_stall',
        'vehicle_id', v_veh.id, 'stall_id', v_stall_id, 'stall_type', v_stall_type,
        'requested_kw', ROUND((LEAST(COALESCE(v_conn_max,50), COALESCE(v_veh.inlet_max_kw,250))
            * CASE WHEN COALESCE(v_conn_max,50) <= 50 THEN 1.0
                   WHEN v_veh.current_soc < 55 THEN 0.85 WHEN v_veh.current_soc < 75 THEN 0.55 ELSE 0.30 END)::numeric, 1),
        'l2_engine', 'greedy_constrained',
        'rationale', jsonb_build_object('soc', v_veh.current_soc, 'optimizer', 'greedy_constrained', 'inlet', v_veh.inlet_type)),
      'greedy_constrained', 'pending', now(), now() + INTERVAL '120 seconds');
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$


-- ===== ottoq_l2_propose_bess =====
CREATE OR REPLACE FUNCTION public.ottoq_l2_propose_bess(p_bess_id uuid, p_depot_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_now timestamptz := COALESCE(NULLIF(p_context->>'now_ts','')::timestamptz, now());
  v_cmd RECORD;
BEGIN
  -- VEHICLE-FIRST DOCTRINE (N1): the shielded BESS decision IS OTTO-Q's demand-aware
  -- energy plan. ottoq_energy_orchestrate posts bess_setpoint_kw every tick
  -- (+ = discharge to shave actual/forecast peaks, - = recharge from solar/off-peak,
  -- reserve- and thermal-aware). One brain, one plan — price alone never moves the
  -- battery; it reacts to (forecast) site demand. Legacy LMP-arbitrage removed.
  SELECT setpoint_kw, reason INTO v_cmd
    FROM ottoq_energy_commands
   WHERE depot_id = p_depot_id
     AND command_type = 'bess_setpoint_kw'
     AND issued_at <= v_now
     AND issued_at + (COALESCE(horizon_min,15) || ' minutes')::interval >= v_now
   ORDER BY issued_at DESC
   LIMIT 1;
  IF v_cmd.setpoint_kw IS NULL OR abs(v_cmd.setpoint_kw) < 1 THEN
    RETURN jsonb_build_object('abstain', true, 'reason', 'no_active_energy_plan_or_standby');
  END IF;
  RETURN jsonb_build_object(
    'abstain', false,
    'resolved_action_context', 'bess_dispatch',
    'verb', 'set_bess',
    'bess_id', p_bess_id,
    'requested_kw', v_cmd.setpoint_kw,
    'action', CASE WHEN v_cmd.setpoint_kw > 0 THEN 'discharge' ELSE 'charge' END,
    'rationale', COALESCE(v_cmd.reason, '{}'::jsonb)
                 || jsonb_build_object('source', 'ottoq_energy_orchestrate'));
END;
$function$


-- ===== ottoq_l2_propose_charge_disposition =====
CREATE OR REPLACE FUNCTION public.ottoq_l2_propose_charge_disposition(p_vehicle_id uuid, p_depot_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_in_wash int; v_wash_cap int; v_phys int; v_run uuid;
  v_needs_wash boolean; v_wants_detail boolean; v_flagged boolean; v_needs_service boolean;
BEGIN
  -- SERVICE-NEED GATE (2026-08-01). This proposer used to be NEED-BLIND: it admitted
  -- ANY vehicle leaving charge into the wash lane whenever the lane was not full.
  -- Measured on run 274389e1-0b5e-4c14-936e-12b1e6000c60: 18 of 18 engine wash
  -- admissions had NO exterior_wash and NO interior_deep_clean atom anywhere in their
  -- visit. The twin's own admitter (twin.ottoq_sim_advance_service_flow STEP 2, tag
  -- M1_need_gated_wash) IS need-gated, so two writers disagreed and OTTO-Q was the
  -- dumber one. The predicate and the capacity rule below are the twin's, verbatim.

  -- Resolve the run so the staffing knobs actually apply. The old code passed NULL and
  -- ottoq_sim_lane_capacity returns p_physical unchanged on NULL => the staffing slider
  -- was silently dead on this lane.
  v_run := NULLIF(p_context->>'sim_run_id','')::uuid;
  IF v_run IS NULL THEN
    SELECT r.sim_run_id INTO v_run FROM ottoq_sim_runs r
     WHERE r.depot_id = p_depot_id AND r.ended_at IS NULL
     ORDER BY r.started_at DESC LIMIT 1;
  END IF;

  -- physical wash bays are REAL here (3 seeded); the old comment claiming none was wrong.
  SELECT count(*) INTO v_phys FROM stalls s
   WHERE s.depot_id = p_depot_id AND s.stall_type = 'wash_bay'::stall_type;
  v_phys := COALESCE(NULLIF(v_phys,0), 3);
  -- wash_supervisor_pool: same LEAST(lane, supervisors) rule the twin's STEP 2 uses.
  v_wash_cap := LEAST(ottoq_sim_lane_capacity(v_run, 'cleaning_staff', v_phys),
                      ottoq_depot_staffing_count(p_depot_id, 'wash_supervisor'));

  SELECT COALESCE(v.config->>'flagged_issue_type','') IN ('minor_cosmetic','wash_due')
    INTO v_flagged FROM vehicles v WHERE v.id = p_vehicle_id;
  v_flagged := COALESCE(v_flagged, false);

  v_needs_wash := v_flagged OR EXISTS (
      SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
       WHERE n.vehicle_id = p_vehicle_id AND n.status IN ('open','in_progress')
         AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'));

  SELECT count(*) INTO v_in_wash FROM vehicles
   WHERE home_depot_id = p_depot_id AND current_state IN ('in_wash_bay','in_detail_bay');

  IF v_needs_wash THEN
    IF v_in_wash < v_wash_cap THEN
      v_wants_detail := v_flagged OR ottoq_visit_wants_detail(p_vehicle_id);
      RETURN jsonb_build_object('abstain', false, 'resolved_action_context','task_start',
        'verb','admit_wash', 'vehicle_id', p_vehicle_id, 'requested_kw', 0,
        'bay_kind', CASE WHEN v_wants_detail THEN 'detail' ELSE 'wash' END,
        'rationale', jsonb_build_object('in_wash', v_in_wash, 'wash_cap', v_wash_cap,
                                        'need', 'wash_atom_outstanding', 'flagged', v_flagged));
    END IF;
    -- unchanged from today: genuine need + full lane => hold in charge_complete_holding
    RETURN jsonb_build_object('abstain', true, 'reason', 'wash_lane_full_hold',
      'rationale', jsonb_build_object('in_wash', v_in_wash, 'wash_cap', v_wash_cap));
  END IF;

  -- NO wash/detail work outstanding. Do NOT spend one of 3 scarce bays on a clean car.
  -- Advance it inside the SAME atomic visit to whatever it does still need.
  v_needs_service := EXISTS (
      SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
       WHERE n.vehicle_id = p_vehicle_id AND n.status IN ('open','in_progress')
         AND a->>'svc' IN ('mechanical_pm','sensor_calibration','cosmetic_repair','fault_repair')
         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
    OR COALESCE((SELECT v.config->>'flagged_issue' FROM vehicles v WHERE v.id = p_vehicle_id),'false')
       IN ('true','t','1');

  RETURN jsonb_build_object('abstain', false, 'resolved_action_context','task_start',
    'verb','skip_wash', 'vehicle_id', p_vehicle_id, 'requested_kw', 0,
    'next_step', CASE WHEN v_needs_service THEN 'need_service' ELSE 'need_deploy' END,
    'rationale', jsonb_build_object('need','no_wash_outstanding', 'wash_cap', v_wash_cap,
                                    'routes_to_service', v_needs_service));
END;
$function$


-- ===== ottoq_l2_propose_deploy =====
CREATE OR REPLACE FUNCTION public.ottoq_l2_propose_deploy(p_vehicle_id uuid, p_depot_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc      numeric := COALESCE((p_context->>'current_soc')::numeric, 0);
  v_fleet_op uuid    := NULLIF(p_context->>'fleet_operator_id','')::uuid;
  v_floor    numeric;
BEGIN
  -- Read the SAME deploy floor the shield (SLA.001) enforces, so L2 proposes only
  -- shield-passable deploys. Guarded: a NULL/absent fleet op falls back to 80.
  BEGIN
    SELECT min_soc_at_deployment_pct INTO v_floor FROM ottoq_get_active_sla(v_fleet_op);
  EXCEPTION WHEN OTHERS THEN
    v_floor := NULL;
  END;
  v_floor := COALESCE(v_floor, 80);

  IF v_soc < v_floor THEN
    RETURN jsonb_build_object('abstain', true, 'reason', 'soc_below_deploy_floor',
      'soc', v_soc, 'floor', v_floor);
  END IF;
  RETURN jsonb_build_object('abstain', false, 'resolved_action_context','redeployment',
    'verb','deploy', 'vehicle_id', p_vehicle_id, 'fleet_operator_id', p_context->>'fleet_operator_id',
    'rationale', jsonb_build_object('soc', v_soc, 'floor', v_floor));
END;
$function$


-- ===== ottoq_l2_propose_service =====
CREATE OR REPLACE FUNCTION public.ottoq_l2_propose_service(p_vehicle_id uuid, p_depot_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_in_svc int; v_svc_cap int; v_phys int; v_run uuid;
  v_step text := p_context->>'svc_step';
  v_open jsonb; v_must boolean; v_any boolean;
  v_wait_min numeric; v_patience numeric;
BEGIN
  -- MANIFEST-FIRST SERVICE (2026-08-01). This proposer used to admit a vehicle to a
  -- service bay ONLY when config.svc_step already said 'need_service' - a flag the twin
  -- sets from config.flagged_issue alone. A vehicle carrying an outstanding
  -- mechanical_pm / sensor_calibration / cosmetic_repair / fault_repair atom but no flag
  -- was promoted straight to staged_for_departure with the work still open, which
  -- breaches the full-service visit doctrine. The manifest is now a first-class input.
  v_run := NULLIF(p_context->>'sim_run_id','')::uuid;
  IF v_run IS NULL THEN
    SELECT r.sim_run_id INTO v_run FROM ottoq_sim_runs r
     WHERE r.depot_id = p_depot_id AND r.ended_at IS NULL
     ORDER BY r.started_at DESC LIMIT 1;
  END IF;

  SELECT count(*) INTO v_phys FROM stalls s
   WHERE s.depot_id = p_depot_id AND s.stall_type = 'service_bay'::stall_type;
  v_phys := COALESCE(NULLIF(v_phys,0), 2);
  v_svc_cap := ottoq_sim_lane_capacity(v_run, 'service_staff', v_phys);

  SELECT count(*) INTO v_in_svc FROM vehicles
   WHERE home_depot_id = p_depot_id AND current_state = 'in_service_bay';

  -- what the vehicle's MANIFEST still asks a service bay for
  SELECT COALESCE(jsonb_agg(DISTINCT a->>'svc'), '[]'::jsonb),
         COALESCE(bool_or(COALESCE(a->>'must_do','false') = 'true'), false)
    INTO v_open, v_must
    FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
   WHERE n.vehicle_id = p_vehicle_id AND n.status IN ('open','in_progress')
     AND a->>'svc' IN ('mechanical_pm','sensor_calibration','cosmetic_repair','fault_repair')
     AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped');
  v_open := COALESCE(v_open, '[]'::jsonb);
  v_must := COALESCE(v_must, false);
  v_any  := jsonb_array_length(v_open) > 0;

  IF (v_step = 'need_service' OR v_any) AND v_in_svc < v_svc_cap THEN
    RETURN jsonb_build_object('abstain', false, 'resolved_action_context','task_start',
      'verb','admit_service', 'vehicle_id', p_vehicle_id, 'requested_kw', 0,
      'rationale', jsonb_build_object('in_svc', v_in_svc, 'svc_cap', v_svc_cap, 'step', v_step,
        'open_service_atoms', v_open, 'must_do', v_must,
        'need_source', CASE WHEN v_any THEN 'manifest' ELSE 'flag' END));
  END IF;

  -- Bay busy AND must-do work outstanding => hold in the service queue rather than
  -- redeploying a vehicle with MANDATORY work open (full-service visit doctrine).
  -- Bounded twice so this can never strand a vehicle or gridlock the depot:
  --   (a) only must_do atoms hold - measured, only fault_repair is ever must_do
  --       (377 of ~37k service atoms), everything else is deferrable and still deploys;
  --   (b) the hold expires at service_hold_patience_min sim-minutes.
  IF v_must AND v_in_svc >= v_svc_cap THEN
    v_patience := ottoq_policy_get(v_run, 'service_hold_patience_min', 120);
    SELECT EXTRACT(EPOCH FROM (COALESCE((p_context->>'now_ts')::timestamptz, now()) - v.last_state_change))/60.0
      INTO v_wait_min FROM vehicles v WHERE v.id = p_vehicle_id;
    IF COALESCE(v_wait_min, 0) <= v_patience THEN
      RETURN jsonb_build_object('abstain', false, 'resolved_action_context','task_start',
        'verb','hold_in_queue', 'vehicle_id', p_vehicle_id, 'requested_kw', 0,
        'reason','must_do_service_outstanding_bay_busy',
        'rationale', jsonb_build_object('in_svc', v_in_svc, 'svc_cap', v_svc_cap,
          'open_service_atoms', v_open, 'waited_min', ROUND(COALESCE(v_wait_min,0),1),
          'patience_min', v_patience));
    END IF;
  END IF;

  -- else promote to deploy-ready (today's default), now carrying an HONEST record of any
  -- deferrable service work being carried forward to the next visit.
  RETURN jsonb_build_object('abstain', false, 'resolved_action_context','task_start',
    'verb','promote_ready', 'vehicle_id', p_vehicle_id, 'requested_kw', 0,
    'deferred_service', v_open,
    'rationale', jsonb_build_object('step', v_step, 'in_svc', v_in_svc, 'svc_cap', v_svc_cap,
      'deferred', v_open, 'must_do_outstanding', v_must));
END;
$function$


-- ===== ottoq_l2_propose_stall_assignment =====
CREATE OR REPLACE FUNCTION public.ottoq_l2_propose_stall_assignment(p_vehicle_id uuid, p_depot_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc   numeric := COALESCE((p_context->>'current_soc')::numeric, 50);
  v_now   timestamptz := COALESCE(NULLIF(p_context->>'now_ts','')::timestamptz, now());
  v_inlet text;
  v_inlet_kw numeric;
  v_want_type text;
  v_urgency text;
  v_stall RECORD;
  v_eff_kw numeric;
BEGIN
  SELECT vn.urgency INTO v_urgency FROM ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
   ORDER BY vn.created_at DESC LIMIT 1;
  v_want_type := CASE WHEN v_soc < 45 OR v_urgency = 'immediate_dispatch' THEN 'dcfc' ELSE 'l2' END;

  SELECT inlet_type, inlet_max_kw INTO v_inlet, v_inlet_kw FROM vehicles WHERE id = p_vehicle_id;

  SELECT s.id, s.stall_type, s.connector_max_kw INTO v_stall
    FROM stalls s
    JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = p_depot_id
     AND s.stall_type IN ('dcfc','l2')
     AND s.current_vehicle_id IS NULL
     AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= v_now)
     AND c.station_state = 'Available'
     AND c.last_heartbeat_at >= v_now - INTERVAL '90 seconds'
     AND (
          v_inlet IS NULL
       OR s.connector_type = v_inlet
       OR (s.connector_type = 'Multi' AND v_inlet = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
       OR (s.connector_type = 'NACS'  AND v_inlet IN ('NACS','Tesla_Proprietary'))
     )
   ORDER BY COALESCE(s.reserved_by = p_vehicle_id, false) DESC,          -- N3: your pre-reserved stall first
            (s.stall_type::text = v_want_type) DESC,
            s.relative_y ASC NULLS LAST,
            s.id
   LIMIT 1;

  IF v_stall.id IS NULL THEN
    RETURN jsonb_build_object('abstain', true, 'reason', 'no_compatible_available_stall');
  END IF;

  v_eff_kw := LEAST(COALESCE(v_stall.connector_max_kw, 50), COALESCE(v_inlet_kw, 250));
  v_eff_kw := v_eff_kw * CASE
       WHEN COALESCE(v_stall.connector_max_kw, 50) <= 50 THEN 1.0
       WHEN v_soc < 55 THEN 0.85
       WHEN v_soc < 75 THEN 0.55
       ELSE 0.30
     END;

  RETURN jsonb_build_object(
    'abstain', false,
    'resolved_action_context', 'stall_assignment',
    'verb', 'assign_stall',
    'vehicle_id', p_vehicle_id,
    'stall_id', v_stall.id,
    'stall_type', v_stall.stall_type,
    'requested_kw', ROUND(v_eff_kw::numeric, 1),
    'rationale', jsonb_build_object('soc', v_soc, 'wanted_type', v_want_type, 'inlet', v_inlet,
      'urgency', v_urgency, 'eff_draw_kw', ROUND(v_eff_kw::numeric, 1)));
END;
$function$


-- ===== ottoq_local_to_latlng =====
CREATE OR REPLACE FUNCTION public.ottoq_local_to_latlng(p_origin_lat double precision, p_origin_lng double precision, p_x_ft double precision, p_y_ft double precision)
 RETURNS TABLE(out_lat numeric, out_lng numeric)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_ft_per_deg_lat DOUBLE PRECISION := 364000;
  v_ft_per_deg_lng DOUBLE PRECISION;
BEGIN
  v_ft_per_deg_lng := 364000.0 * cos(radians(p_origin_lat));
  RETURN QUERY SELECT
    (p_origin_lat + (p_y_ft / v_ft_per_deg_lat))::NUMERIC,
    (p_origin_lng + (p_x_ft / v_ft_per_deg_lng))::NUMERIC;
END;
$function$


-- ===== ottoq_log_deploy_event =====
CREATE OR REPLACE FUNCTION public.ottoq_log_deploy_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run uuid; v_policy text; v_clock timestamptz; v_floor numeric;
BEGIN
  -- Attribute the deploy to the depot's single running sim run (owning_sim_run_id
  -- is not populated in pilots; the one-running-run-per-depot index makes this unique).
  SELECT sim_run_id, policy, sim_clock_current
    INTO v_run, v_policy, v_clock
    FROM ottoq_sim_runs
   WHERE depot_id = NEW.home_depot_id AND status = 'running'
   ORDER BY started_at DESC NULLS LAST LIMIT 1;
  IF v_run IS NULL THEN
    RETURN NEW;  -- not inside a sim run (e.g. manual/ops action) — don't log
  END IF;

  -- The deploy SLA floor for THIS vehicle's fleet operator (same source as SLA.001).
  BEGIN
    SELECT min_soc_at_deployment_pct INTO v_floor FROM ottoq_get_active_sla(NEW.fleet_operator_id);
  EXCEPTION WHEN OTHERS THEN
    v_floor := NULL;
  END;
  v_floor := COALESCE(v_floor, 80);

  INSERT INTO ottoq_deploy_log (
    sim_run_id, vehicle_id, policy, sim_clock, soc_at_deploy, floor_at_deploy,
    is_productive, from_state, to_state)
  VALUES (
    v_run, NEW.id, v_policy, v_clock, NEW.current_soc, v_floor,
    (NEW.current_soc >= v_floor), OLD.current_state::text, NEW.current_state::text);
  RETURN NEW;
END;
$function$


-- ===== ottoq_log_inference_complete =====
CREATE OR REPLACE FUNCTION public.ottoq_log_inference_complete(p_inference_id uuid, p_predicted_value jsonb DEFAULT NULL::jsonb, p_p10 numeric DEFAULT NULL::numeric, p_p50 numeric DEFAULT NULL::numeric, p_p90 numeric DEFAULT NULL::numeric, p_confidence numeric DEFAULT NULL::numeric, p_uncertainty_method text DEFAULT NULL::text, p_prediction_id uuid DEFAULT NULL::uuid, p_inference_ms integer DEFAULT NULL::integer, p_feature_fetch_ms integer DEFAULT NULL::integer, p_status text DEFAULT 'completed'::text, p_error_message text DEFAULT NULL::text, p_error_code text DEFAULT NULL::text, p_shadow_compared_to uuid DEFAULT NULL::uuid, p_shadow_disagreement numeric DEFAULT NULL::numeric, p_cost_estimate_cents numeric DEFAULT NULL::numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  UPDATE ottoq_inference_log
     SET completed_at = NOW(),
         latency_ms = EXTRACT(MILLISECOND FROM (NOW() - requested_at))::INTEGER,
         feature_fetch_ms = p_feature_fetch_ms,
         inference_ms = p_inference_ms,
         predicted_value = p_predicted_value,
         p10 = p_p10, p50 = p_p50, p90 = p_p90,
         confidence = p_confidence,
         uncertainty_method = p_uncertainty_method,
         prediction_id = p_prediction_id,
         status = p_status,
         error_message = p_error_message,
         error_code = p_error_code,
         shadow_compared_to = p_shadow_compared_to,
         shadow_disagreement = p_shadow_disagreement,
         cost_estimate_cents = p_cost_estimate_cents
   WHERE inference_id = p_inference_id;
END;
$function$


-- ===== ottoq_log_inference_start =====
CREATE OR REPLACE FUNCTION public.ottoq_log_inference_start(p_prediction_type text, p_model_version_id uuid DEFAULT NULL::uuid, p_route_id uuid DEFAULT NULL::uuid, p_serving_runtime text DEFAULT NULL::text, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_vehicle_id uuid DEFAULT NULL::uuid, p_vehicle_class text DEFAULT NULL::text, p_features_used jsonb DEFAULT NULL::jsonb, p_feature_snapshot_ids uuid[] DEFAULT NULL::uuid[], p_inputs_hash text DEFAULT NULL::text, p_ab_test_id uuid DEFAULT NULL::uuid, p_ab_test_variant text DEFAULT NULL::text, p_is_shadow boolean DEFAULT false, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_inference_id UUID := gen_random_uuid();
  v_correlation  UUID;
BEGIN
  v_correlation := COALESCE(p_correlation_id,
    NULLIF(current_setting('ottoq.correlation_id', TRUE), '')::UUID,
    gen_random_uuid()
  );

  INSERT INTO ottoq_inference_log (
    inference_id, requested_at,
    prediction_type, model_version_id, route_id, serving_runtime,
    fleet_operator_id, depot_id, vehicle_id, vehicle_class,
    features_used, feature_snapshot_ids, inputs_hash,
    ab_test_id, ab_test_variant, is_shadow,
    status, correlation_id, parent_event_id
  ) VALUES (
    v_inference_id, NOW(),
    p_prediction_type, p_model_version_id, p_route_id, p_serving_runtime,
    p_fleet_operator_id, p_depot_id, p_vehicle_id, p_vehicle_class,
    p_features_used, p_feature_snapshot_ids, p_inputs_hash,
    p_ab_test_id, p_ab_test_variant, p_is_shadow,
    'pending', v_correlation, p_parent_event_id
  );
  RETURN v_inference_id;
END;
$function$


-- ===== ottoq_manual_tick =====
CREATE OR REPLACE FUNCTION public.ottoq_manual_tick(p_sim_run_id uuid)
 RETURNS ottoq_decide_tick_result
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_clock timestamptz; v_tick bigint;
  v_req RECORD; v_stall RECORD; v_built int := 0; v_enacted int := 0;
  v_cap int := 25; v_active int;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count INTO v_depot, v_clock, v_tick FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF v_depot IS NULL THEN RETURN ROW(0,NULL,0,0,0,0,0,0,0)::ottoq_decide_tick_result; END IF;

  SELECT count(*) INTO v_active FROM vehicles
   WHERE home_depot_id=v_depot AND category='autonomous'
     AND current_state IN ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay','in_service_bay','staged_awaiting_service','charge_complete_holding','service_complete_holding');

  -- (a) ADMIT arrivals to a charger ONLY while under the monitoring cap (else they pile at the gate)
  FOR v_req IN SELECT id AS vehicle_id FROM vehicles
     WHERE home_depot_id=v_depot AND category='autonomous' AND current_state='arrived_at_gate' AND current_soc<85
     ORDER BY id LOOP
    EXIT WHEN v_active >= v_cap;
    v_built := v_built + 1;
    SELECT s.id, s.stall_type INTO v_stall FROM stalls s
     WHERE s.depot_id=v_depot AND s.stall_type IN ('dcfc','l2') AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= v_clock) ORDER BY s.id LIMIT 1;
    IF v_stall.id IS NOT NULL AND ottoq_reserve_stall(v_stall.id, v_req.vehicle_id, v_clock, 600) THEN
      UPDATE vehicles SET current_state=(CASE WHEN v_stall.stall_type::text='dcfc' THEN 'charging_dcfc' ELSE 'charging_l2' END)::vehicle_state,
             current_stall_id=v_stall.id, last_state_change=v_clock WHERE id=v_req.vehicle_id;
      UPDATE stalls SET current_vehicle_id=v_req.vehicle_id, status='occupied' WHERE id=v_stall.id;
      v_enacted := v_enacted + 1; v_active := v_active + 1;
    END IF;
  END LOOP;

  -- (b) charge_complete_holding -> wash
  FOR v_req IN SELECT id AS vehicle_id FROM vehicles
     WHERE home_depot_id=v_depot AND category='autonomous' AND current_state='charge_complete_holding'
     ORDER BY last_state_change ASC NULLS FIRST, id LOOP
    v_built := v_built + 1;
    UPDATE vehicles SET current_state='in_wash_bay', last_state_change=v_clock,
           config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('washing'::text)) WHERE id=v_req.vehicle_id;
    v_enacted := v_enacted + 1;
  END LOOP;

  -- (c) staged_awaiting_service -> ready
  FOR v_req IN SELECT id AS vehicle_id FROM vehicles
     WHERE home_depot_id=v_depot AND category='autonomous' AND current_state='staged_awaiting_service'
     ORDER BY last_state_change ASC NULLS FIRST, id LOOP
    v_built := v_built + 1;
    UPDATE vehicles SET current_state='staged_for_departure', last_state_change=v_clock,
           config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('ready'::text)) WHERE id=v_req.vehicle_id;
    v_enacted := v_enacted + 1;
  END LOOP;

  -- (d) deploy ready SoC>=70 (frees monitoring capacity)
  FOR v_req IN SELECT id AS vehicle_id FROM vehicles
     WHERE home_depot_id=v_depot AND category='autonomous' AND current_state='staged_for_departure' AND current_soc>=70
     ORDER BY last_state_change ASC NULLS FIRST, id LOOP
    v_built := v_built + 1;
    UPDATE vehicles SET current_state='en_route_to_deployment', current_stall_id=NULL, last_state_change=v_clock WHERE id=v_req.vehicle_id;
    v_enacted := v_enacted + 1;
  END LOOP;

  RETURN ROW(v_tick, v_clock, v_built, v_enacted, 0, 0, 0, 0, 0)::ottoq_decide_tick_result;
END;
$function$


-- ===== ottoq_mark_recommendation_executed =====
CREATE OR REPLACE FUNCTION public.ottoq_mark_recommendation_executed(p_recommendation_id uuid, p_executed_by text, p_outcome text, p_execution_event_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  UPDATE ottoq_recommendations
     SET executed_at        = NOW(),
         executed_by        = p_executed_by,
         execution_outcome  = p_outcome,
         execution_event_id = p_execution_event_id,
         status             = CASE
                                WHEN p_outcome = 'rolled_back' THEN 'rolled_back'
                                ELSE 'executed'
                              END
   WHERE recommendation_id = p_recommendation_id;
END;
$function$


-- ===== ottoq_mark_visit_atoms_done =====
CREATE OR REPLACE FUNCTION public.ottoq_mark_visit_atoms_done(p_vehicle uuid, p_svcs text[], p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_visit uuid; v_atoms jsonb; v_new jsonb := '[]'::jsonb; v_a jsonb; v_n int := 0;
BEGIN
  SELECT visit_id, atoms INTO v_visit, v_atoms FROM ottoq_visit_needs
   WHERE vehicle_id = p_vehicle AND status IN ('open','in_progress')
   ORDER BY created_at DESC LIMIT 1;
  IF v_visit IS NULL THEN RETURN 0; END IF;
  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
    IF v_a->>'svc' = ANY(p_svcs) AND COALESCE(v_a->>'status','pending') <> 'done' THEN
      v_a := v_a || jsonb_build_object('status','done','done_at', to_jsonb(p_clock));
      v_n := v_n + 1;
    END IF;
    v_new := v_new || jsonb_build_array(v_a);
  END LOOP;
  IF v_n > 0 THEN UPDATE ottoq_visit_needs SET atoms = v_new, status = 'in_progress' WHERE visit_id = v_visit; END IF;
  RETURN v_n;
END; $function$


-- ===== ottoq_mirror_dr_call =====
CREATE OR REPLACE FUNCTION public.ottoq_mirror_dr_call(p_dr_call_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE d ottoq_dr_calls%ROWTYPE; v_id uuid;
BEGIN
  SELECT * INTO d FROM ottoq_dr_calls WHERE dr_call_id = p_dr_call_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF d.cleared_at IS NOT NULL OR d.call_status NOT IN ('active','issued') THEN
    -- clear the mirror
    RETURN ottoq_mirror_grid_event_to_ottoq(d.depot_id, 'demand_response_called', COALESCE(d.cleared_at, d.expires_at, NOW()), NULL,
             jsonb_build_object('dr_call_id', d.dr_call_id), TRUE);
  END IF;
  v_id := ottoq_mirror_grid_event_to_ottoq(d.depot_id, 'demand_response_called', d.issued_at, d.expires_at,
            jsonb_build_object('dr_call_id', d.dr_call_id, 'target_kw', d.required_load_cap_kw,
                               'program', d.program, 'reason', d.reason), FALSE);
  RETURN v_id;
END;
$function$


-- ===== ottoq_mirror_grid_event_to_ottoq =====
CREATE OR REPLACE FUNCTION public.ottoq_mirror_grid_event_to_ottoq(p_depot_id uuid, p_kind text, p_effective_at timestamp with time zone, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_payload jsonb DEFAULT '{}'::jsonb, p_clear boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_event_type TEXT;
  v_severity   TEXT;
  v_id         UUID;
BEGIN
  -- Map twin vocabulary -> certified-evaluator vocabulary.
  v_event_type := CASE p_kind
    WHEN 'grid_brownout'            THEN 'brownout'
    WHEN 'grid_voltage_sag'         THEN 'undervoltage'
    WHEN 'grid_frequency_excursion' THEN 'grid_trip'
    WHEN 'demand_response_called'   THEN 'demand_response_called'
    ELSE p_kind  -- already-canonical types pass through (brownout/undervoltage/overvoltage/grid_trip)
  END;
  v_severity := CASE WHEN v_event_type = 'demand_response_called' THEN 'critical' ELSE 'safety_critical' END;

  IF p_clear THEN
    -- Clear the most-recent open event of this type for the depot.
    UPDATE ottoq_grid_events
       SET cleared_at = p_effective_at
     WHERE depot_id = p_depot_id AND event_type = v_event_type AND cleared_at IS NULL
       AND grid_event_id = (
         SELECT grid_event_id FROM ottoq_grid_events
          WHERE depot_id = p_depot_id AND event_type = v_event_type AND cleared_at IS NULL
          ORDER BY effective_at DESC LIMIT 1)
     RETURNING grid_event_id INTO v_id;
    RETURN v_id;
  END IF;

  INSERT INTO ottoq_grid_events (depot_id, event_type, severity, effective_at, expires_at, source, payload)
  VALUES (p_depot_id, v_event_type, v_severity, p_effective_at, p_expires_at, 'twin_mirror',
          p_payload || jsonb_build_object('twin_kind', p_kind))
  RETURNING grid_event_id INTO v_id;
  RETURN v_id;
END;
$function$


-- ===== ottoq_mpc_energy_lookahead =====
CREATE OR REPLACE FUNCTION public.ottoq_mpc_energy_lookahead(p_sim_run_id uuid, p_horizon_ticks integer DEFAULT 3, p_factors numeric[] DEFAULT ARRAY[0.35, 0.45, 0.55, 0.65])
 RETURNS TABLE(factor numeric, predicted_peak_kw numeric, predicted_demand_charge_usd numeric, ready_vehicles integer, unsafe integer, feasible boolean, is_best boolean)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_f numeric; v_peak numeric; v_ready int; v_unsafe int; v_err text;
  v_clock timestamptz; v_depot uuid; v_base_unsafe int;
  v_best_f numeric; v_best_charge numeric := NULL;
  v_rows jsonb := '[]'::jsonb;
BEGIN
  PERFORM set_config('ottoq.dryrun','on',true);   -- forks fire NO real NVIDIA calls
  SELECT sim_clock_current, depot_id INTO v_clock, v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  SELECT count(*) INTO v_base_unsafe FROM ottoq_deploy_log WHERE sim_run_id=p_sim_run_id AND NOT is_productive;

  FOREACH v_f IN ARRAY p_factors LOOP
    v_peak := NULL; v_ready := NULL; v_unsafe := NULL; v_err := NULL;
    BEGIN
      INSERT INTO ottoq_policy_params(scope_type,scope_id,param_key,param_value,updated_by) VALUES
        ('run',p_sim_run_id,'energy_demand_factor_peak',v_f,'mpc'),
        ('run',p_sim_run_id,'energy_demand_factor_expensive',GREATEST(0.20,v_f-0.15),'mpc')
        ON CONFLICT (scope_type,scope_id,param_key) DO UPDATE SET param_value=EXCLUDED.param_value;

      PERFORM ottoq_sim_advance_tick(p_sim_run_id) FROM generate_series(1,p_horizon_ticks);

      SELECT ROUND(MAX(peak_demand_kw_15min),0) INTO v_peak FROM site_energy_snapshots
        WHERE sim_run_id=p_sim_run_id AND timestamp > v_clock;
      SELECT count(*) INTO v_ready FROM vehicles WHERE home_depot_id=v_depot AND category='autonomous'
        AND current_state IN ('staged_for_departure','charge_complete_holding') AND current_soc>=80;
      SELECT count(*)-v_base_unsafe INTO v_unsafe FROM ottoq_deploy_log
        WHERE sim_run_id=p_sim_run_id AND NOT is_productive;

      RAISE EXCEPTION 'MPC_ROLLBACK';     -- undo the entire simulated branch
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM <> 'MPC_ROLLBACK' THEN v_err := SQLERRM; END IF;
    END;

    factor := v_f;
    predicted_peak_kw := v_peak;
    predicted_demand_charge_usd := ROUND(COALESCE(v_peak,0)*10,0);
    ready_vehicles := COALESCE(v_ready,0);
    unsafe := COALESCE(v_unsafe,0);
    feasible := (v_err IS NULL AND COALESCE(v_unsafe,0) = 0);
    is_best := false;
    -- best = lowest predicted demand charge among feasible (0-unsafe) candidates
    IF feasible AND (v_best_charge IS NULL OR predicted_demand_charge_usd < v_best_charge) THEN
      v_best_charge := predicted_demand_charge_usd; v_best_f := v_f;
    END IF;
    v_rows := v_rows || jsonb_build_object('factor',v_f,'charge',predicted_demand_charge_usd,'ready',ready_vehicles,'unsafe',unsafe,'feasible',feasible);
    RETURN NEXT;
  END LOOP;

  PERFORM set_config('ottoq.dryrun','off',true);
  DELETE FROM ottoq_policy_params WHERE scope_type='run' AND scope_id=p_sim_run_id AND updated_by='mpc';

  -- emit the plan (which factor OTTO-Q would pick + why) for the audit/cockpit
  PERFORM ottoq_record_event(
    p_actor_type:='ottoq_engine', p_actor_id:='mpc_planner',
    p_event_type:='ottoq.mpc_plan', p_entity_type:='depot', p_entity_id:=v_depot, p_depot_id:=v_depot,
    p_payload:=jsonb_build_object('horizon_ticks',p_horizon_ticks,'candidates',v_rows,
       'chosen_factor',v_best_f,'chosen_demand_charge_usd',v_best_charge),
    p_severity:='info', p_ingest_source:='otto_q', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);

  -- mark the winner in the returned set
  RETURN QUERY SELECT v_best_f, NULL::numeric, v_best_charge, NULL::int, 0, true, true WHERE v_best_f IS NOT NULL;
END;
$function$


-- ===== ottoq_mpc_lookahead =====
CREATE OR REPLACE FUNCTION public.ottoq_mpc_lookahead(p_sim_run_id uuid, p_plans jsonb, p_horizon_ticks integer DEFAULT 3, p_objective text DEFAULT 'balanced'::text)
 RETURNS TABLE(plan_label text, predicted_peak_kw numeric, predicted_demand_charge_usd numeric, throughput integer, am_readiness integer, unsafe integer, feasible boolean, score numeric, is_best boolean)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_plan jsonb; v_label text; v_params jsonb; k text; val text;
  v_clock timestamptz; v_depot uuid; v_smax numeric; v_fleet int;
  v_base_prod int; v_base_unsafe int;
  v_peak numeric; v_prod int; v_unsafe int; v_ready int; v_err text;
  v_score numeric; v_best_label text; v_best_score numeric := NULL; v_rows jsonb := '[]'::jsonb;
BEGIN
  PERFORM set_config('ottoq.dryrun','on',true);
  SELECT sim_clock_current, depot_id INTO v_clock, v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  SELECT service_max_kw INTO v_smax FROM depots WHERE id=v_depot;
  SELECT count(*) INTO v_fleet FROM vehicles WHERE home_depot_id=v_depot AND category='autonomous';
  SELECT count(*) FILTER (WHERE is_productive), count(*) FILTER (WHERE NOT is_productive)
    INTO v_base_prod, v_base_unsafe FROM ottoq_deploy_log WHERE sim_run_id=p_sim_run_id;

  FOR v_plan IN SELECT * FROM jsonb_array_elements(p_plans) LOOP
    v_label := COALESCE(v_plan->>'label','plan'); v_params := COALESCE(v_plan->'params','{}'::jsonb);
    v_peak:=NULL; v_prod:=NULL; v_unsafe:=NULL; v_ready:=NULL; v_err:=NULL;
    BEGIN
      FOR k, val IN SELECT * FROM jsonb_each_text(v_params) LOOP
        INSERT INTO ottoq_policy_params(scope_type,scope_id,param_key,param_value,updated_by)
          VALUES ('run',p_sim_run_id,k,val::numeric,'mpc')
          ON CONFLICT (scope_type,scope_id,param_key) DO UPDATE SET param_value=EXCLUDED.param_value;
      END LOOP;

      PERFORM ottoq_sim_advance_tick(p_sim_run_id) FROM generate_series(1,p_horizon_ticks);

      SELECT ROUND(MAX(peak_demand_kw_15min),0) INTO v_peak FROM site_energy_snapshots
        WHERE sim_run_id=p_sim_run_id AND timestamp > v_clock;
      SELECT count(*) FILTER (WHERE is_productive)-v_base_prod, count(*) FILTER (WHERE NOT is_productive)-v_base_unsafe
        INTO v_prod, v_unsafe FROM ottoq_deploy_log WHERE sim_run_id=p_sim_run_id;
      SELECT count(*) INTO v_ready FROM vehicles WHERE home_depot_id=v_depot AND category='autonomous'
        AND current_state IN ('staged_for_departure','charge_complete_holding') AND current_soc>=80;

      RAISE EXCEPTION 'MPC_RB';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM <> 'MPC_RB' THEN v_err := SQLERRM; END IF;
    END;
    -- clean this plan's overrides for the next branch (also rolled back, belt-and-suspenders)
    DELETE FROM ottoq_policy_params WHERE scope_type='run' AND scope_id=p_sim_run_id AND updated_by='mpc';

    plan_label := v_label;
    predicted_peak_kw := v_peak;
    predicted_demand_charge_usd := ROUND(COALESCE(v_peak,0)*10,0);
    throughput := COALESCE(v_prod,0);
    am_readiness := COALESCE(v_ready,0);
    unsafe := COALESCE(v_unsafe,0);
    feasible := (v_err IS NULL AND COALESCE(v_unsafe,0)=0);
    -- normalized balanced score (energy 0.4 / throughput 0.3 / readiness 0.3), 0-unsafe hard gate
    v_score := CASE WHEN NOT feasible THEN -1 ELSE
        0.40 * (1 - LEAST(1, predicted_demand_charge_usd / GREATEST(1, v_smax*10)))
      + 0.30 * LEAST(1, throughput::numeric / GREATEST(1, v_fleet*0.15))
      + 0.30 * LEAST(1, am_readiness::numeric / GREATEST(1, v_fleet)) END;
    score := ROUND(v_score,4);
    is_best := false;

    IF feasible THEN
      v_score := CASE p_objective
        WHEN 'min_demand_charge' THEN -predicted_demand_charge_usd
        WHEN 'max_readiness'     THEN am_readiness
        WHEN 'max_throughput'    THEN throughput
        ELSE v_score END;
      IF v_best_score IS NULL OR v_score > v_best_score THEN v_best_score := v_score; v_best_label := v_label; END IF;
    END IF;
    v_rows := v_rows || jsonb_build_object('label',v_label,'peak',predicted_peak_kw,'charge',predicted_demand_charge_usd,
        'throughput',throughput,'readiness',am_readiness,'unsafe',unsafe,'feasible',feasible,'score',score);
    RETURN NEXT;
  END LOOP;

  PERFORM set_config('ottoq.dryrun','off',true);
  PERFORM ottoq_record_event(
    p_actor_type:='ottoq_engine', p_actor_id:='mpc_planner',
    p_event_type:='ottoq.mpc_plan', p_entity_type:='depot', p_entity_id:=v_depot, p_depot_id:=v_depot,
    p_payload:=jsonb_build_object('objective',p_objective,'horizon_ticks',p_horizon_ticks,
       'plans',v_rows,'chosen',v_best_label),
    p_severity:='info', p_ingest_source:='otto_q', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);

  -- second pass to flag the winner
  RETURN QUERY SELECT v_best_label, NULL::numeric, NULL::numeric, NULL::int, NULL::int, 0, true, v_best_score, true
               WHERE v_best_label IS NOT NULL;
END;
$function$


-- ===== ottoq_need_to_leg_type =====
CREATE OR REPLACE FUNCTION public.ottoq_need_to_leg_type(p_need text, p_dcfc_safe boolean DEFAULT true)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_need = 'charge' THEN CASE WHEN COALESCE(p_dcfc_safe, true) THEN 'charge_dcfc' ELSE 'charge_l2' END
    ELSE public.ottoq_svc_to_leg_type(p_need)
  END;
$function$

-- ===== ottoq_nl_status_brief =====
CREATE OR REPLACE FUNCTION public.ottoq_nl_status_brief(p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run uuid; v_depot uuid; v_clock timestamptz; r jsonb;
BEGIN
  v_run := COALESCE(p_sim_run_id, ottoq_active_sim_run());
  IF v_run IS NULL THEN RETURN jsonb_build_object('active_run', false, 'note','No simulation/operation is currently running.'); END IF;
  SELECT depot_id, sim_clock_current INTO v_depot, v_clock FROM ottoq_sim_runs WHERE sim_run_id = v_run;
  SELECT jsonb_build_object(
    'active_run', true,
    'sim_clock', v_clock,
    'energy_aggressiveness_factor', round(ottoq_policy_get(v_run,'energy_demand_factor_peak',0.50),2),
    'forecast_uncertainty_0to1', round(ottoq_forecast_uncertainty(v_run, v_depot, v_clock),2),
    'battery_soc_pct', (SELECT round(current_soc_pct,0) FROM ottoq_bess_units WHERE depot_id = v_depot LIMIT 1),
    'recent_grid_peak_kw', (SELECT round(max(grid_import_kw),0) FROM site_energy_snapshots WHERE sim_run_id = v_run AND timestamp > v_clock - interval '2 hours'),
    'ready_to_deploy', (SELECT count(*) FROM vehicles WHERE home_depot_id = v_depot AND category='autonomous' AND current_state IN ('staged_for_departure','charge_complete_holding') AND current_soc >= 80),
    'charging_now', (SELECT count(*) FROM ocpp_sessions WHERE status='active'),
    'unsafe_so_far', (SELECT count(*) FROM ottoq_deploy_log WHERE sim_run_id = v_run AND NOT is_productive)
  ) INTO r;
  RETURN r;
END;
$function$


-- ===== ottoq_oem_deliver_live =====
CREATE OR REPLACE FUNCTION public.ottoq_oem_deliver_live(p_webhook_id uuid, p_sim_run_id uuid, p_vehicle_id uuid, p_fleet_op uuid, p_oem text, p_endpoint text, p_payload jsonb, p_secret_ref text, p_sim_clock_now timestamp with time zone)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_secret text;
  v_body   text := p_payload::text;
  v_sig    text;
  v_req    bigint;
  v_ts     text := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
BEGIN
  -- resolve the signing secret from vault (same mechanism cuOpt uses for its key)
  IF p_secret_ref IS NOT NULL THEN
    SELECT decrypted_secret INTO v_secret
      FROM vault.decrypted_secrets WHERE name = p_secret_ref LIMIT 1;
  END IF;
  v_secret := COALESCE(v_secret, 'unsigned');
  v_sig := ottoq_oem_sign_payload(v_body, v_secret);

  -- REAL POST. Signature + delivery metadata in headers a real receiver verifies.
  SELECT net.http_post(
    url := p_endpoint,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-OTTOQ-Event', 'vehicle.arrival',
      'X-OTTOQ-Signature', 'sha256=' || v_sig,
      'X-OTTOQ-Webhook-Id', p_webhook_id::text,
      'X-OTTOQ-Timestamp', v_ts),
    body := p_payload,
    timeout_milliseconds := 15000
  ) INTO v_req;

  -- log the LIVE attempt with a TRUE status of 'sent' (the real HTTP status is
  -- reconciled later by the collector — never invented here)
  INSERT INTO ottoq_oem_webhook_log (
    webhook_id, sim_run_id, vehicle_id, fleet_operator_id,
    oem_name, webhook_type, http_method, endpoint_url,
    payload, payload_complete, attempt_num, is_retry, is_duplicate,
    delivery_mode, http_request_id, signature,
    http_status, delivery_status, validation_result,
    sim_clock_emitted_at, real_at, data_source)
  VALUES (
    p_webhook_id, p_sim_run_id, p_vehicle_id, p_fleet_op,
    p_oem, 'arrival', 'POST', p_endpoint,
    p_payload, TRUE, 1, FALSE, FALSE,
    'live', v_req, v_sig,
    NULL, 'sent', 'pending_delivery',
    p_sim_clock_now, now(), 'live');

  RETURN v_req;
END;
$function$


-- ===== ottoq_oem_fleet_overview =====
CREATE OR REPLACE FUNCTION public.ottoq_oem_fleet_overview(p_fleet_operator_id uuid, p_lookback_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_window TIMESTAMPTZ := NOW() - (p_lookback_days || ' days')::INTERVAL;
  v_result JSONB;
BEGIN
  v_result := jsonb_build_object(
    'fleet_operator_id',         p_fleet_operator_id,
    'window_start',              v_window,
    'window_end',                NOW(),
    'lookback_days',             p_lookback_days,

    'live', jsonb_build_object(
      'active_emergencies',      (SELECT count(*) FROM ottoq_emergency_invocations ei
                                   JOIN depots d ON d.id = ei.depot_id
                                   WHERE ei.cleared_at IS NULL),
      'active_recommendations',  (SELECT count(*) FROM ottoq_recommendations
                                   WHERE fleet_operator_id = p_fleet_operator_id
                                     AND status IN ('pending','validating','admitted')
                                     AND (expires_at IS NULL OR expires_at > NOW())),
      'pending_oem_gates',       0
    ),

    'totals', jsonb_build_object(
      'events',                  (SELECT count(*) FROM ottoq_events
                                   WHERE fleet_operator_id = p_fleet_operator_id
                                     AND occurred_at > v_window),
      'predictions',             (SELECT count(*) FROM ottoq_predictions
                                   WHERE fleet_operator_id = p_fleet_operator_id
                                     AND created_at > v_window),
      'rule_evaluations',        (SELECT count(*) FROM ottoq_rule_evaluations
                                   WHERE fleet_operator_id = p_fleet_operator_id
                                     AND evaluated_at > v_window),
      'rule_failures',           (SELECT count(*) FROM ottoq_rule_evaluations
                                   WHERE fleet_operator_id = p_fleet_operator_id
                                     AND evaluated_at > v_window
                                     AND passed = FALSE),
      'sla_violations',          (SELECT count(*) FROM ottoq_sla_violations
                                   WHERE fleet_operator_id = p_fleet_operator_id
                                     AND detected_at > v_window),
      'anomalies_flagged',       (SELECT count(*) FROM ottoq_anomaly_observations
                                   WHERE fleet_operator_id = p_fleet_operator_id
                                     AND observed_at > v_window
                                     AND is_anomaly = TRUE),
      'recommendations_admitted',(SELECT count(*) FROM ottoq_recommendations
                                   WHERE fleet_operator_id = p_fleet_operator_id
                                     AND emitted_at > v_window
                                     AND status IN ('admitted','executed')),
      'recommendations_rejected',(SELECT count(*) FROM ottoq_recommendations
                                   WHERE fleet_operator_id = p_fleet_operator_id
                                     AND emitted_at > v_window
                                     AND status = 'rejected')
    ),

    'sla_compliance', jsonb_build_object(
      'most_recent', (SELECT row_to_json(sc) FROM (
        SELECT report_date, overall_compliance_pct, composite_grade,
               total_visits, compliant_visits, non_compliant_visits
        FROM ottoq_sla_conformance_daily
        WHERE fleet_operator_id = p_fleet_operator_id
        ORDER BY report_date DESC LIMIT 1
      ) sc),
      'rolling_avg_pct', (SELECT ROUND(AVG(overall_compliance_pct)::NUMERIC, 2)
        FROM ottoq_sla_conformance_daily
        WHERE fleet_operator_id = p_fleet_operator_id
          AND report_date >= v_window::DATE)
    ),

    'top_rule_failures', (
      SELECT jsonb_agg(jsonb_build_object(
        'rule_code', rule_code, 'title', title,
        'severity', rule_severity, 'failure_count', failure_count
      ) ORDER BY failure_count DESC)
      FROM ottoq_oem_rule_failure_top
      WHERE fleet_operator_id = p_fleet_operator_id
      LIMIT 10
    ),

    'top_anomaly_detectors', (
      SELECT jsonb_agg(jsonb_build_object(
        'detector_code', detector_code, 'category', detector_category,
        'title', detector_title, 'anomalies_7d', anomalies_7d
      ) ORDER BY anomalies_7d DESC)
      FROM ottoq_oem_anomaly_summary
      WHERE fleet_operator_id = p_fleet_operator_id
      LIMIT 5
    ),

    'computed_at',               NOW()
  );

  RETURN v_result;
END;
$function$


-- ===== ottoq_oem_sign_payload =====
CREATE OR REPLACE FUNCTION public.ottoq_oem_sign_payload(p_body text, p_secret text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT encode(extensions.hmac(p_body, p_secret, 'sha256'), 'hex');
$function$


-- ===== ottoq_oem_webhook_collect_responses =====
CREATE OR REPLACE FUNCTION public.ottoq_oem_webhook_collect_responses()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n integer;
BEGIN
  WITH resolved AS (
    SELECT l.webhook_id, l.http_request_id,
           r.status_code, r.content, r.error_msg
      FROM ottoq_oem_webhook_log l
      JOIN net._http_response r ON r.id = l.http_request_id
     WHERE l.delivery_mode = 'live' AND l.delivery_status = 'sent'
       AND l.http_request_id IS NOT NULL
  ), upd AS (
    UPDATE ottoq_oem_webhook_log l SET
      http_status      = res.status_code,
      response_payload = CASE WHEN res.content IS NOT NULL
                              THEN jsonb_build_object('body', left(res.content, 2000))
                              ELSE jsonb_build_object('error', res.error_msg) END,
      delivery_status  = CASE
                           WHEN res.status_code BETWEEN 200 AND 299 THEN 'delivered'
                           WHEN res.status_code IN (401,403)        THEN 'auth_failed'
                           WHEN res.status_code = 429               THEN 'rate_limited'
                           WHEN res.status_code >= 500              THEN 'server_error'
                           WHEN res.status_code IS NULL             THEN 'timed_out'
                           ELSE 'rejected_other' END,
      validation_result = CASE
                           WHEN res.status_code BETWEEN 200 AND 299 THEN 'accepted'
                           WHEN res.status_code IN (401,403)        THEN 'rejected_auth'
                           ELSE 'rejected_other' END,
      real_at = now()
    FROM resolved res WHERE l.webhook_id = res.webhook_id
    RETURNING 1)
  SELECT count(*) INTO v_n FROM upd;
  RETURN COALESCE(v_n, 0);
END;
$function$


-- ===== ottoq_onboard_vehicle_battery =====
CREATE OR REPLACE FUNCTION public.ottoq_onboard_vehicle_battery(p_vehicle_id uuid, p_chemistry text, p_pack_kwh numeric DEFAULT NULL::numeric, p_balance_interval_days integer DEFAULT 7, p_actor text DEFAULT 'onboarding'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_chem text := lower(COALESCE(p_chemistry,''));
BEGIN
  IF v_chem NOT IN ('lfp','nmc','nca') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'chemistry must be lfp|nmc|nca');
  END IF;
  UPDATE vehicles SET
    config = COALESCE(config,'{}'::jsonb) || jsonb_build_object(
      'battery_chemistry', v_chem,
      'nightly_soc_target', CASE WHEN v_chem = 'lfp' THEN 100 ELSE 90 END,
      'balance_interval_days', CASE WHEN v_chem = 'lfp' THEN 0 ELSE p_balance_interval_days END,
      'battery_onboarded_at', to_jsonb(now())),
    battery_capacity_kwh = COALESCE(p_pack_kwh, battery_capacity_kwh)
  WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'vehicle_not_found'); END IF;
  RETURN jsonb_build_object('ok', true, 'vehicle_id', p_vehicle_id, 'chemistry', v_chem,
    'nightly_soc_target', CASE WHEN v_chem='lfp' THEN 100 ELSE 90 END);
END; $function$


-- ===== ottoq_ops_set_feed_mode =====
CREATE OR REPLACE FUNCTION public.ottoq_ops_set_feed_mode(p_depot_id uuid, p_mode text, p_actor text DEFAULT 'ops'::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_old text;
BEGIN
  IF p_mode NOT IN ('sim','external') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mode must be sim|external');
  END IF;
  SELECT feed_mode INTO v_old FROM depots WHERE id = p_depot_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'depot not found'); END IF;
  UPDATE depots SET feed_mode = p_mode WHERE id = p_depot_id;
  BEGIN
    PERFORM ottoq_record_event(
      p_actor_type := 'depot_tech', p_actor_id := p_actor,
      p_event_type := 'ops.feed_mode_set', p_entity_type := 'system',
      p_payload := jsonb_build_object('depot_id', p_depot_id, 'from', v_old, 'to', p_mode, 'note', p_note),
      p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN jsonb_build_object('ok', true, 'depot_id', p_depot_id, 'from', v_old, 'to', p_mode);
END;
$function$


-- ===== ottoq_ops_set_rush_valve =====
CREATE OR REPLACE FUNCTION public.ottoq_ops_set_rush_valve(p_sim_run_id uuid, p_on boolean, p_actor text DEFAULT 'technician'::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_cap numeric;
BEGIN
  PERFORM ottoq_policy_set('run', p_sim_run_id, 'rush_valve_forced',
                           CASE WHEN p_on THEN 1 ELSE 0 END, p_actor);
  v_cap := ottoq_policy_get(p_sim_run_id, 'deploy_release_per_tick_cap', 6);
  PERFORM ottoq_record_event(
    p_actor_type := 'depot_tech', p_actor_id := COALESCE(p_actor,'technician'),
    p_event_type := CASE WHEN p_on THEN 'ops.rush_valve_engaged' ELSE 'ops.rush_valve_released' END,
    p_entity_type := 'system',
    p_payload := jsonb_build_object('sim_run_id', p_sim_run_id, 'on', p_on,
                                    'base_cap', v_cap, 'note', p_note),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
    p_sim_run_id := p_sim_run_id);
  RETURN jsonb_build_object('ok', true, 'rush_valve_forced', p_on,
                            'effective_cap', CASE WHEN p_on THEN GREATEST(1, v_cap::int/2) ELSE v_cap::int END);
END;
$function$


-- ===== ottoq_orchestrator_trigger =====
CREATE OR REPLACE FUNCTION public.ottoq_orchestrator_trigger(p_depot_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT
    (SELECT count(*) FROM vehicles
       WHERE current_depot_id = p_depot_id AND category='autonomous'
         AND current_state = 'arrived_at_gate') >= 5
    OR
    (SELECT count(*) FROM vehicles
       WHERE current_depot_id = p_depot_id AND category='autonomous'
         AND current_state = 'charge_complete_holding') >= 25;
$function$


-- ===== ottoq_pause_run =====
CREATE OR REPLACE FUNCTION public.ottoq_pause_run(p_sim_run_id uuid, p_reason text DEFAULT 'operator_pause'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run ottoq_sim_runs%ROWTYPE;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
  IF v_run.status <> 'running' THEN
    RETURN jsonb_build_object('ok', true, 'noop', true, 'status', v_run.status,
                              'note', 'run was not running');
  END IF;

  UPDATE ottoq_sim_runs
     SET status = 'paused',
         next_tick_due_at = NULL,
         payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('paused_at', clock_timestamp(), 'pause_reason', p_reason)
   WHERE sim_run_id = p_sim_run_id;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'otto_twin',
    p_event_type := 'twin.sim_run_paused', p_entity_type := 'sim_run',
    p_entity_id := p_sim_run_id, p_depot_id := v_run.depot_id,
    p_payload := jsonb_build_object('reason', p_reason, 'tick_count', v_run.tick_count),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
    p_sim_run_id := p_sim_run_id);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'status', 'paused',
    'frozen_at_sim_clock', v_run.sim_clock_current, 'tick_count', v_run.tick_count);
END;
$function$


-- ===== ottoq_plan_overnight_wave =====
CREATE OR REPLACE FUNCTION public.ottoq_plan_overnight_wave(p_sim_run_id uuid, p_morning_deploy_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_slot_min integer DEFAULT 15, p_dcfc_kw numeric DEFAULT 150, p_l2_kw numeric DEFAULT 19)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_now timestamptz; v_deadline timestamptz; v_slots int;
  v_dcfc_cap int; v_l2_cap int;
  v_dcfc_free int[]; v_l2_free int[];
  v_rec RECORD; v_v RECORD;
  v_need_kwh numeric; v_min_l2 numeric; v_min_dcfc numeric;
  v_k int; v_s int; v_ok boolean; v_class text; v_start int; v_kslots int;
  v_planned int := 0; v_stranded int := 0; v_dcfc_used int := 0; v_l2_used int := 0;
  i int; j int;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'run_not_found'); END IF;
  v_now := COALESCE(v_run.sim_clock_current, now());
  v_deadline := COALESCE(p_morning_deploy_at,
    ((date_trunc('day', (v_now AT TIME ZONE 'America/Chicago'))
      + CASE WHEN EXTRACT(HOUR FROM (v_now AT TIME ZONE 'America/Chicago')) < 5
             THEN interval '5 hours' ELSE interval '29 hours' END) AT TIME ZONE 'America/Chicago'));
  v_slots := GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_deadline - v_now)) / (p_slot_min*60.0))::int);
  IF v_slots > 200 THEN v_slots := 200; END IF;   -- guard

  SELECT COUNT(*) FILTER (WHERE stall_type::text='dcfc'),
         COUNT(*) FILTER (WHERE stall_type::text='l2')
    INTO v_dcfc_cap, v_l2_cap
    FROM stalls WHERE depot_id = v_run.depot_id;

  v_dcfc_free := array_fill(v_dcfc_cap, ARRAY[v_slots]);
  v_l2_free   := array_fill(v_l2_cap,   ARRAY[v_slots]);

  DELETE FROM ottoq_wave_plan WHERE sim_run_id = p_sim_run_id;

  -- worklist: returning / en-route / at-depot-awaiting vehicles that need charge.
  -- FOUNDER WALL: vehicles already IN a charger/bay are NOT rescheduled here.
  -- EDF order: earliest due first; deepest-drained first as the tiebreak.
  FOR v_rec IN
    SELECT v.id, v.current_soc, COALESCE(v.target_soc,90) AS target_soc,
           COALESCE(v.battery_capacity_kwh, 75) AS cap_kwh,
           -- staggered per-vehicle deadline: default common morning slot (Phase-1 assumption;
           -- real per-vehicle deploy distribution is a founder-ratify item)
           v_deadline AS due_at
      FROM vehicles v
     WHERE v.home_depot_id = v_run.depot_id AND v.category='autonomous'
       AND v.current_state IN ('deployed','en_route_to_depot','arrived_at_gate',
                               'staged_awaiting_service','charge_complete_holding')
       AND v.current_soc < COALESCE(v.target_soc,90) - 2
     ORDER BY due_at ASC, v.current_soc ASC
  LOOP
    v_need_kwh := GREATEST(0, (v_rec.target_soc - v_rec.current_soc)/100.0 * v_rec.cap_kwh);
    v_min_l2   := v_need_kwh / p_l2_kw * 60.0;
    v_min_dcfc := v_need_kwh / p_dcfc_kw * 60.0;

    v_class := NULL; v_start := NULL;
    -- PREFER L2 (save scarce DCFC for who truly needs it) IF it finishes by deadline;
    -- else DCFC; else stranded. Earliest feasible start (fill the valley from wave onset).
    v_kslots := GREATEST(1, CEIL(v_min_l2 / p_slot_min)::int);
    IF v_kslots <= v_slots THEN
      FOR v_s IN 1 .. (v_slots - v_kslots + 1) LOOP
        v_ok := true;
        FOR j IN v_s .. (v_s + v_kslots - 1) LOOP
          IF v_l2_free[j] <= 0 THEN v_ok := false; EXIT; END IF;
        END LOOP;
        IF v_ok THEN v_class := 'l2'; v_start := v_s; EXIT; END IF;
      END LOOP;
    END IF;
    IF v_class IS NULL THEN
      v_kslots := GREATEST(1, CEIL(v_min_dcfc / p_slot_min)::int);
      IF v_kslots <= v_slots THEN
        FOR v_s IN 1 .. (v_slots - v_kslots + 1) LOOP
          v_ok := true;
          FOR j IN v_s .. (v_s + v_kslots - 1) LOOP
            IF v_dcfc_free[j] <= 0 THEN v_ok := false; EXIT; END IF;
          END LOOP;
          IF v_ok THEN v_class := 'dcfc'; v_start := v_s; EXIT; END IF;
        END LOOP;
      END IF;
    END IF;

    IF v_class IS NULL THEN
      INSERT INTO ottoq_wave_plan (sim_run_id, vehicle_id, want_class, target_soc, due_at, feasible, reason)
      VALUES (p_sim_run_id, v_rec.id, 'none', v_rec.target_soc, v_rec.due_at, false, 'no_charger_block_meets_deadline');
      v_stranded := v_stranded + 1;
      CONTINUE;
    END IF;

    -- reserve the block
    FOR j IN v_start .. (v_start + v_kslots - 1) LOOP
      IF v_class='l2' THEN v_l2_free[j] := v_l2_free[j] - 1; ELSE v_dcfc_free[j] := v_dcfc_free[j] - 1; END IF;
    END LOOP;
    IF v_class='l2' THEN v_l2_used := v_l2_used + 1; ELSE v_dcfc_used := v_dcfc_used + 1; END IF;

    INSERT INTO ottoq_wave_plan (sim_run_id, vehicle_id, want_class, charge_start_at, charge_end_at,
      charge_minutes, target_soc, due_at, feasible, reason)
    VALUES (p_sim_run_id, v_rec.id, v_class,
      v_now + ((v_start-1)*p_slot_min || ' minutes')::interval,
      v_now + ((v_start-1+v_kslots)*p_slot_min || ' minutes')::interval,
      ROUND(CASE WHEN v_class='l2' THEN v_min_l2 ELSE v_min_dcfc END,1),
      v_rec.target_soc, v_rec.due_at, true, 'scheduled');
    v_planned := v_planned + 1;
  END LOOP;

  -- peak concurrent chargers (energy proxy for the infeasibility/CapEx signal)
  RETURN jsonb_build_object(
    'ok', true, 'sim_run_id', p_sim_run_id, 'generator', 'edf_v1',
    'horizon_slots', v_slots, 'slot_min', p_slot_min, 'deadline', v_deadline,
    'resources', jsonb_build_object('dcfc', v_dcfc_cap, 'l2', v_l2_cap),
    'planned', v_planned, 'stranded', v_stranded,
    'dcfc_used', v_dcfc_used, 'l2_used', v_l2_used,
    'peak_dcfc_concurrent', v_dcfc_cap - (SELECT COALESCE(MIN(x),v_dcfc_cap) FROM unnest(v_dcfc_free) x),
    'peak_l2_concurrent',   v_l2_cap   - (SELECT COALESCE(MIN(x),v_l2_cap)   FROM unnest(v_l2_free) x),
    'feasible_all', (v_stranded = 0));
END;
$function$


-- ===== ottoq_plan_visit_itinerary =====
CREATE OR REPLACE FUNCTION public.ottoq_plan_visit_itinerary(p_sim_run_id uuid, p_vehicle uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_visit RECORD; v_veh RECORD; v_itin uuid; v_depot uuid;
  v_a jsonb; v_cursor timestamptz; v_charge_start timestamptz; v_charge_end timestamptz;
  v_min numeric; v_seq int := 0; v_n int := 0;
  v_wash_wait numeric; v_svc_wait numeric;
  v_charger_kw numeric; v_charge_leg_type text;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;
  SELECT vn.visit_id, vn.atoms, vn.urgency, vn.dispatch_due_at, vn.target_soc INTO v_visit
    FROM ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle AND vn.status IN ('open','in_progress')
   ORDER BY vn.created_at DESC LIMIT 1;
  IF v_visit.visit_id IS NULL THEN RETURN 0; END IF;
  SELECT home_depot_id, current_soc, COALESCE(inlet_max_kw,150) AS inlet_kw,
         COALESCE(battery_capacity_kwh,75) AS pack_kwh
    INTO v_veh FROM vehicles WHERE id = p_vehicle;
  v_depot := v_veh.home_depot_id;

  SELECT itinerary_id INTO v_itin FROM ottoq_vehicle_itineraries
   WHERE sim_run_id = p_sim_run_id AND vehicle_id = p_vehicle AND status = 'active'
   ORDER BY created_at DESC LIMIT 1;
  IF v_itin IS NOT NULL AND EXISTS (SELECT 1 FROM ottoq_itinerary_legs
        WHERE itinerary_id = v_itin AND status = 'planned') THEN
    RETURN 0;
  END IF;
  IF v_itin IS NULL THEN
    INSERT INTO ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, created_by, sim_created_at)
    VALUES (p_sim_run_id, v_depot, p_vehicle, 'flow_contract_m4', p_clock)
    RETURNING itinerary_id INTO v_itin;
  END IF;
  SELECT COALESCE(MAX(seq),0) INTO v_seq FROM ottoq_itinerary_legs WHERE itinerary_id = v_itin;

  SELECT count(*) * 10.0 / GREATEST(1, ottoq_sim_lane_capacity(NULL,'cleaning_staff',3)) INTO v_wash_wait
    FROM vehicles WHERE home_depot_id = v_depot AND current_state IN ('in_wash_bay','in_detail_bay');
  SELECT count(*) * 40.0 / GREATEST(1, ottoq_sim_lane_capacity(NULL,'service_staff',2)) INTO v_svc_wait
    FROM vehicles WHERE home_depot_id = v_depot AND current_state = 'in_service_bay';

  v_cursor := p_clock;

  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_visit.atoms) a
              WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')) THEN
    SELECT a INTO v_a FROM jsonb_array_elements(v_visit.atoms) a
     WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled') LIMIT 1;
    v_charger_kw := (CASE WHEN v_veh.current_soc < 45 THEN 100 ELSE 11 END);
    v_charge_leg_type := (CASE WHEN v_veh.current_soc < 45 THEN 'charge_dcfc' ELSE 'charge_l2' END);
    BEGIN
      SELECT ottoq_estimate_charge_minutes(v_veh.current_soc,
             COALESCE((v_a->>'target_soc')::numeric, v_visit.target_soc, 80),
             v_charger_kw, v_veh.inlet_kw, v_veh.pack_kwh, 20, 100, 1.0) INTO v_min;
    EXCEPTION WHEN OTHERS THEN
      v_min := GREATEST(10, (COALESCE((v_a->>'target_soc')::numeric, 80) - v_veh.current_soc) * 1.2);
    END;
    v_min := COALESCE(v_min, 25);
    v_charge_start := v_cursor; v_charge_end := v_cursor + (v_min::text || ' minutes')::interval;
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, v_charge_leg_type, v_charge_start, v_charge_end,
           (v_min*60)::int, jsonb_build_object('kind','flow_contract','charger_kw_assumed',v_charger_kw), 'planned');
    FOR v_a IN SELECT a FROM jsonb_array_elements(v_visit.atoms) a LOOP
      IF v_a->>'concurrency' IN ('cabin','exterior','digital')
         AND v_a->>'svc' NOT IN ('readiness_check')
         AND COALESCE(v_a->>'status','pending') NOT IN ('done','cancelled') THEN
        v_seq := v_seq + 1; v_n := v_n + 1;
        INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
               planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
        VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, public.ottoq_svc_to_leg_type(v_a->>'svc'), v_charge_start,
               v_charge_start + ((COALESCE((v_a->>'est_min')::numeric,5))::text || ' minutes')::interval,
               (COALESCE((v_a->>'est_min')::numeric,5)*60)::int,
               jsonb_build_object('kind','flow_contract','concurrent_with','charge','atom',v_a->>'svc'), 'planned');
      END IF;
    END LOOP;
    v_cursor := v_charge_end;
  ELSE
    FOR v_a IN SELECT a FROM jsonb_array_elements(v_visit.atoms) a LOOP
      IF v_a->>'concurrency' IN ('cabin','exterior','digital')
         AND v_a->>'svc' NOT IN ('readiness_check')
         AND COALESCE(v_a->>'status','pending') NOT IN ('done','cancelled') THEN
        v_seq := v_seq + 1; v_n := v_n + 1;
        INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
               planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
        VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, public.ottoq_svc_to_leg_type(v_a->>'svc'), v_cursor,
               v_cursor + ((COALESCE((v_a->>'est_min')::numeric,5))::text || ' minutes')::interval,
               (COALESCE((v_a->>'est_min')::numeric,5)*60)::int,
               jsonb_build_object('kind','flow_contract','atom',v_a->>'svc'), 'planned');
      END IF;
    END LOOP;
    v_cursor := v_cursor + interval '10 minutes';
  END IF;

  FOR v_a IN
    SELECT a FROM jsonb_array_elements(v_visit.atoms) a
    WHERE a->>'concurrency' = 'bay' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')
    ORDER BY (CASE a->>'svc' WHEN 'exterior_wash' THEN 1 WHEN 'interior_deep_clean' THEN 2
                             WHEN 'sensor_calibration' THEN 3 WHEN 'mechanical_pm' THEN 4
                             WHEN 'fault_repair' THEN 5 ELSE 6 END)
  LOOP
    -- Duration is the SERVICE time only; the forward calendar expresses contention
      -- by moving the leg, not by inflating it. (queue_wait_min is still recorded in
      -- duration_basis below for diagnostics.)
      v_min := COALESCE((v_a->>'est_min')::numeric, 20);
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq,
           (CASE v_a->>'svc' WHEN 'exterior_wash' THEN 'wash' WHEN 'interior_deep_clean' THEN 'detail'
                             ELSE 'service' END),
           v_cursor, v_cursor + (v_min::text || ' minutes')::interval, (v_min*60)::int,
           jsonb_build_object('kind','flow_contract','atom',v_a->>'svc','queue_wait_min',
             round((CASE WHEN v_a->>'requires_bay' IN ('wash_bay','detail') THEN COALESCE(v_wash_wait,0) ELSE COALESCE(v_svc_wait,0) END),1)), 'planned');
    v_cursor := v_cursor + (v_min::text || ' minutes')::interval;
  END LOOP;

  IF v_visit.urgency = 'overnight_hold' AND v_visit.dispatch_due_at IS NOT NULL AND v_visit.dispatch_due_at > v_cursor THEN
    v_seq := v_seq + 1; v_n := v_n + 1;
    INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
           planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
    VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, 'stage', v_cursor, v_visit.dispatch_due_at,
           GREATEST(0, EXTRACT(EPOCH FROM (v_visit.dispatch_due_at - v_cursor)))::int,
           jsonb_build_object('kind','flow_contract','reason','overnight_hold'), 'planned');
    v_cursor := v_visit.dispatch_due_at;
  END IF;
  v_seq := v_seq + 1; v_n := v_n + 1;
  INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
         planned_start_sim, planned_end_sim, planned_duration_s, duration_basis, status)
  VALUES (v_itin, p_sim_run_id, p_vehicle, v_seq, 'inspect', v_cursor, v_cursor + interval '3 minutes',
         180, jsonb_build_object('kind','flow_contract','atom','readiness_check'), 'planned');
  RETURN v_n;
END; $function$


-- ===== ottoq_policy_get =====
CREATE OR REPLACE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v numeric; v_depot uuid;
BEGIN
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='run' AND scope_id=p_sim_run_id AND param_key=p_param_key;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF v_depot IS NOT NULL THEN
    SELECT param_value INTO v FROM ottoq_policy_params
     WHERE scope_type='depot' AND scope_id=v_depot AND param_key=p_param_key;
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='global' AND scope_id IS NULL AND param_key=p_param_key;
  RETURN COALESCE(v, p_default);
END;
$function$


-- ===== ottoq_policy_set =====
CREATE OR REPLACE FUNCTION public.ottoq_policy_set(p_scope_type text, p_scope_id uuid, p_param_key text, p_param_value numeric, p_by text DEFAULT 'ottocommand'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_min numeric; v_max numeric; v_final numeric;
BEGIN
  IF p_scope_type = 'sim_run' THEN p_scope_type := 'run'; END IF;
  IF p_scope_type NOT IN ('global','depot','run') THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_scope_type','scope_type',p_scope_type,
                              'allowed',jsonb_build_array('global','depot','run'));
  END IF;

  SELECT min_value, max_value INTO v_min, v_max FROM ottoq_policy_param_catalog WHERE param_key = p_param_key;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','unknown_param','param',p_param_key); END IF;
  v_final := GREATEST(v_min, LEAST(v_max, p_param_value));
  INSERT INTO ottoq_policy_params(scope_type, scope_id, param_key, param_value, updated_by)
    VALUES (p_scope_type, p_scope_id, p_param_key, v_final, p_by)
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value, updated_at = now();
  RETURN jsonb_build_object('ok',true,'param',p_param_key,'requested',p_param_value,'applied',v_final,
                            'clamped', v_final <> p_param_value,'safe_range',jsonb_build_array(v_min,v_max),
                            'scope_type',p_scope_type);
END;
$function$


-- ===== ottoq_precip_daily_mm =====
CREATE OR REPLACE FUNCTION public.ottoq_precip_daily_mm(p_run_id uuid, p_clock timestamp with time zone)
 RETURNS numeric
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_day int := (p_clock::date - DATE '2020-01-01');
  v_mo text := to_char(p_clock AT TIME ZONE 'America/Chicago', 'MM');
  v_card numeric; v_plan jsonb; v_seed bigint;
  v_yest numeric; v_p numeric; v_u numeric; v_wet boolean; v_mm numeric := 0;
BEGIN
  SELECT value INTO v_card FROM ottoq_variability_cards
   WHERE sim_run_id = p_run_id AND var_key = 'precip_mm'
     AND scope_instance = 'global' AND bucket_key = 'day:' || v_day;
  IF FOUND THEN RETURN v_card; END IF;

  v_plan := ottoq_feed_plan('precip_unified');
  SELECT COALESCE(random_seed, 42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_run_id;

  IF v_plan IS NULL THEN
    -- legacy: generic card engine deal from the global fitted grid
    RETURN COALESCE(ottoq_twin_deal(p_run_id, 'precip_mm', 'global', p_clock, v_day, 0), 0);
  END IF;

  -- Markov occurrence: p11 if yesterday was wet, else p01 (monthly, GHCN-computed)
  SELECT value INTO v_yest FROM ottoq_variability_cards
   WHERE sim_run_id = p_run_id AND var_key = 'precip_mm'
     AND scope_instance = 'global' AND bucket_key = 'day:' || (v_day - 1);
  v_p := CASE
    WHEN v_yest IS NULL THEN (v_plan->'markov_monthly'->v_mo->>'p_wet')::numeric
    WHEN v_yest >= (v_plan->>'wet_day_threshold_mm')::numeric THEN (v_plan->'markov_monthly'->v_mo->>'p11')::numeric
    ELSE (v_plan->'markov_monthly'->v_mo->>'p01')::numeric END;
  v_p := LEAST(0.98, v_p * COALESCE(ottoq_profile_rate_mult(p_run_id, 'precip'), 1));  -- A.10 scenario knob

  v_u := ottoq_sim_seeded_random(v_seed, 'precip_day:' || v_day);
  v_wet := v_u < v_p;
  IF v_wet THEN
    v_mm := COALESCE(ottoq_sample_calibrated('precip_wet_mm', 'month:' || v_mo, v_seed, 'precip_amt:' || v_day), 2.0);
  END IF;

  INSERT INTO ottoq_variability_cards(sim_run_id, var_key, scope_instance, lifespan, bucket_key, value, meta, drawn_at_clock, drawn_at_tick)
  VALUES (p_run_id, 'precip_mm', 'global', 'day', 'day:' || v_day, round(v_mm, 2),
          jsonb_build_object('plan', 'precip_unified.v1', 'wet', v_wet, 'month', v_mo,
                             'markov_p', round(v_p, 3), 'yesterday_wet', COALESCE(v_yest >= 0.2, false)),
          p_clock, 0)
  ON CONFLICT (sim_run_id, var_key, scope_instance, bucket_key) DO NOTHING;
  SELECT value INTO v_card FROM ottoq_variability_cards
   WHERE sim_run_id = p_run_id AND var_key = 'precip_mm'
     AND scope_instance = 'global' AND bucket_key = 'day:' || v_day;
  RETURN COALESCE(v_card, v_mm);
END;
$function$


-- ===== ottoq_predict_arrivals =====
CREATE OR REPLACE FUNCTION public.ottoq_predict_arrivals(p_depot_id uuid, p_sim_clock timestamp with time zone, p_sim_run_id uuid DEFAULT NULL::uuid, p_horizon_min integer DEFAULT 30)
 RETURNS TABLE(incoming_count integer, charge_needed_count integer, predicted_charge_kw numeric, predicted_charge_kwh numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_in_count int; v_chg_count int; v_kw numeric; v_kwh numeric;
BEGIN
  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE v.current_soc < COALESCE(v.target_soc,90) - 1),
    COALESCE(SUM(CASE WHEN v.current_soc < COALESCE(v.target_soc,90) - 1
              THEN LEAST(COALESCE(v.inlet_max_kw,150), 250)
                   * CASE WHEN v.current_soc < 35 THEN 0.90 WHEN v.current_soc < 55 THEN 0.80
                          WHEN v.current_soc < 75 THEN 0.50 ELSE 0.25 END
              ELSE 0 END), 0),
    COALESCE(SUM(GREATEST(0, (COALESCE(v.target_soc,90) - v.current_soc)/100.0 * COALESCE(v.battery_capacity_kwh,75))), 0)
  INTO v_in_count, v_chg_count, v_kw, v_kwh
  FROM ottoq_vehicle_dispatches d
  JOIN vehicles v ON v.id = d.vehicle_id
  WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning')
    AND d.scheduled_return_at IS NOT NULL
    AND d.scheduled_return_at <= p_sim_clock + (p_horizon_min || ' minutes')::interval
    AND d.scheduled_return_at >  p_sim_clock - INTERVAL '5 minutes';

  IF v_in_count > 0 THEN
    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='arrival_forecaster',
      p_event_type:='ottoq.arrival_forecast', p_entity_type:='depot', p_entity_id:=p_depot_id,
      p_depot_id:=p_depot_id,
      p_payload:=jsonb_build_object('horizon_min', p_horizon_min, 'incoming_count', v_in_count,
        'charge_needed_count', v_chg_count, 'predicted_charge_kw', ROUND(v_kw,0),
        'predicted_charge_kwh', ROUND(v_kwh,0)),
      p_severity:='info', p_ingest_source:='otto_q', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
  END IF;

  incoming_count := v_in_count; charge_needed_count := v_chg_count;
  predicted_charge_kw := ROUND(v_kw,0); predicted_charge_kwh := ROUND(v_kwh,0);
  RETURN NEXT;
END;
$function$


-- ===== ottoq_profile_rate_mult =====
CREATE OR REPLACE FUNCTION public.ottoq_profile_rate_mult(p_sim_run_id uuid, p_event text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_knobs  JSONB;
  v_global NUMERIC;
  v_rate   NUMERIC;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 1; END IF;

  SELECT knobs INTO v_knobs
    FROM ottoq_variability_profiles
   WHERE sim_run_id = p_sim_run_id;
  IF v_knobs IS NULL THEN RETURN 1; END IF;

  v_global := COALESCE((v_knobs #>> '{_global,rate_mult}')::numeric, 1);
  v_rate   := COALESCE((v_knobs #>> ARRAY['_rates', p_event])::numeric, 1);
  RETURN v_rate * v_global;
END;
$function$


-- ===== ottoq_progress_commit =====
CREATE OR REPLACE FUNCTION public.ottoq_progress_commit(p_mode text, p_vehicle_id uuid, p_schedule_id uuid, p_depot_id uuid, p_role text DEFAULT 'yard_supervisor'::text, p_current_task_id uuid DEFAULT NULL::uuid, p_next_task_id uuid DEFAULT NULL::uuid, p_from_seq integer DEFAULT NULL::integer, p_to_seq integer DEFAULT NULL::integer, p_to_stall_id uuid DEFAULT NULL::uuid, p_audit_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_role        staff_role;
  v_role_in     text := lower(coalesce(p_role,'yard_supervisor'));
  v_decision_id uuid;
  v_completed   boolean := false;
  v_started     int := 0;
BEGIN
  BEGIN v_role := v_role_in::staff_role; EXCEPTION WHEN others THEN v_role := 'yard_supervisor'; END;

  IF p_mode = 'advance' THEN
    IF p_next_task_id IS NULL THEN RAISE EXCEPTION 'OTTOQ_PROGRESS: advance requires p_next_task_id'; END IF;

    UPDATE schedule_tasks
       SET status='completed', confirmed_by_role=v_role, confirmation_timestamp=now()
     WHERE id=p_current_task_id AND status='in_progress';
    v_completed := FOUND;

    UPDATE schedule_tasks SET status='in_progress'
     WHERE id=p_next_task_id AND status='pending';
    GET DIAGNOSTICS v_started = ROW_COUNT;
    IF v_started = 0 THEN
      RAISE EXCEPTION 'OTTOQ_PROGRESS_RACE: next task % no longer pending (already advanced or cancelled)', p_next_task_id
        USING ERRCODE='P0001';
    END IF;

    INSERT INTO progression_decisions
      (vehicle_id, task_id, schedule_id, depot_id, decision, triggered_by,
       from_task_sequence, to_task_sequence, to_stall_id, audit_note, payload)
    VALUES
      (p_vehicle_id, p_next_task_id, p_schedule_id, p_depot_id, 'auto_advanced', 'tech_confirm',
       p_from_seq, p_to_seq, p_to_stall_id, coalesce(p_audit_note,'shield-authorized advance'),
       jsonb_build_object('role', v_role))
    RETURNING id INTO v_decision_id;

    RETURN jsonb_build_object('committed', true, 'mode','advance',
      'current_completed', v_completed, 'next_started', true, 'role', v_role, 'decision_id', v_decision_id);

  ELSIF p_mode = 'deploy' THEN
    INSERT INTO progression_decisions
      (vehicle_id, schedule_id, depot_id, decision, triggered_by, audit_note, payload)
    VALUES
      (p_vehicle_id, p_schedule_id, p_depot_id, 'all_services_complete', 'tech_confirm',
       coalesce(p_audit_note,'shield-authorized deploy (all services complete, readiness passed)'),
       jsonb_build_object('role', v_role, 'deploy_authorized', true))
    RETURNING id INTO v_decision_id;

    BEGIN UPDATE vehicle_schedules SET status='completed' WHERE id=p_schedule_id AND status='in_progress';
    EXCEPTION WHEN others THEN NULL; END;

    RETURN jsonb_build_object('committed', true, 'mode','deploy', 'role', v_role, 'decision_id', v_decision_id);
  ELSE
    RAISE EXCEPTION 'OTTOQ_PROGRESS: unknown mode %', p_mode;
  END IF;
END;
$function$


-- ===== ottoq_progression_decisions_enforce_audit_note =====
CREATE OR REPLACE FUNCTION public.ottoq_progression_decisions_enforce_audit_note()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_override_decisions TEXT[] := ARRAY[
    'tech_override_skip','tech_override_reroute','tech_override_hold',
    'tech_override_flag_exception','tech_override_defer','tech_override_escalate',
    'oem_rejected','oem_flagged_mid_flow','abnormality_blocked'
  ];
BEGIN
  IF NEW.decision = ANY(v_override_decisions) THEN
    IF NEW.audit_note IS NULL OR length(trim(NEW.audit_note)) < 3 THEN
      RAISE EXCEPTION 'OTTOQ_AUDIT_NOTE_REQUIRED: decision=% requires audit_note (min 3 chars)',
        NEW.decision
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$


-- ===== ottoq_purge_prior_runs =====
CREATE OR REPLACE FUNCTION public.ottoq_purge_prior_runs(p_keep_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_tbl text; v_n int; v_total bigint := 0; v_runs int;
  -- Tables that must SURVIVE a purge. Their whole job is to outlive the run.
  c_keep_tables CONSTANT text[] := ARRAY['ottoq_sim_runs', 'ottoq_run_archives'];
BEGIN
  FOR v_tbl IN
    SELECT table_name FROM information_schema.columns
     WHERE table_schema='public' AND column_name='sim_run_id' AND table_name LIKE 'ottoq%'
       AND NOT (table_name = ANY (c_keep_tables))
  LOOP
    BEGIN
      EXECUTE format(
        'DELETE FROM public.%I WHERE sim_run_id IN (SELECT sim_run_id FROM ottoq_sim_runs WHERE sim_run_id <> $1 AND COALESCE(run_by,'''') <> ''production_live'')',
        v_tbl) USING p_keep_run;
      GET DIAGNOSTICS v_n = ROW_COUNT; v_total := v_total + v_n;
    EXCEPTION WHEN OTHERS THEN
      -- still non-fatal, but no longer invisible
      RAISE WARNING 'purge_prior_runs: table % failed: %', v_tbl, SQLERRM;
    END;
  END LOOP;
  DELETE FROM ottoq_sim_runs WHERE sim_run_id <> p_keep_run AND COALESCE(run_by,'') <> 'production_live'
     AND status <> 'running';
  GET DIAGNOSTICS v_runs = ROW_COUNT;
  RETURN jsonb_build_object('ok',true,'kept',p_keep_run,'rows_purged',v_total,'prior_runs_deleted',v_runs,
    'preserved_tables', to_jsonb(c_keep_tables));
END;
$function$

-- ===== ottoq_reconcile_charger_states =====
CREATE OR REPLACE FUNCTION public.ottoq_reconcile_charger_states(p_depot_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_healed integer; v_orphans integer := 0; v_unstuck integer := 0;
BEGIN
  -- (0) ORPHAN-SESSION SWEEP. A charge session may not outlive the vehicle's presence
  -- at that stall. The VEHICLE is authoritative: if vehicles.current_stall_id no longer
  -- points at the session's stall, the car has physically gone and the session is dead
  -- weight holding a charger hostage.
  WITH orphan AS (
    SELECT cs.id, cs.stall_id, cs.vehicle_id
      FROM ocpp_sessions cs
      JOIN stalls s ON s.id = cs.stall_id
     WHERE s.depot_id  = p_depot_id
       AND s.stall_type IN ('dcfc','l2')
       AND cs.status   = 'active'::ocpp_session_status
       AND cs.id_token LIKE 'TWIN-%'                 -- twin sessions only, never real hardware
       AND COALESCE(cs.meter_values_count, 0) >= 1   -- advanced at least once => not a mid-assignment race
       AND NOT EXISTS (SELECT 1 FROM vehicles v
                        WHERE v.id = cs.vehicle_id
                          AND v.current_stall_id = cs.stall_id)
  ), closed AS (
    UPDATE ocpp_sessions cs
       SET status         = 'cancelled'::ocpp_session_status,
           ended_at       = COALESCE(cs.ended_at, now()),
           stopped_reason = 'vehicle_departed_orphan_sweep',
           updated_at     = now()
      FROM orphan o
     WHERE cs.id = o.id
    RETURNING cs.id
  )
  SELECT count(*) INTO v_orphans FROM closed;

  -- (1) STALE STALL OCCUPANCY. Same guard twin.ottoq_sim_stop_charge_session already uses:
  -- clear a charge stall that still names a vehicle which no longer points back at it.
  -- Cannot evict a car that is genuinely parked there.
  WITH unstuck AS (
    UPDATE stalls s
       SET current_vehicle_id = NULL
     WHERE s.depot_id = p_depot_id
       AND s.stall_type IN ('dcfc','l2')
       AND s.current_vehicle_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM vehicles v
                        WHERE v.id = s.current_vehicle_id
                          AND v.current_stall_id = s.id)
       AND NOT EXISTS (SELECT 1 FROM ocpp_sessions cs2
                        WHERE cs2.stall_id = s.id
                          AND cs2.status = 'active'::ocpp_session_status)
    RETURNING s.id
  )
  SELECT count(*) INTO v_unstuck FROM unstuck;

  -- (2) HEAL THE CHARGER (original behaviour, unchanged). Now reachable, because the
  -- orphan session that used to disarm this predicate has just been closed above.
  WITH stranded AS (
    SELECT c.charger_id
      FROM ottoq_ocpp_chargers c
      JOIN stalls s ON s.ocpp_charger_id = c.charger_id
     WHERE s.depot_id = p_depot_id
       AND c.station_state = 'Occupied'          -- never Faulted/Unavailable
       AND s.current_vehicle_id IS NULL          -- stall is physically empty
       AND NOT EXISTS (                          -- and no session is live on it
             SELECT 1 FROM ocpp_sessions cs
              WHERE cs.stall_id = s.id AND cs.status = 'active'::ocpp_session_status)
  ), upd AS (
    UPDATE ottoq_ocpp_chargers c
       SET station_state = 'Available'
      FROM stranded st
     WHERE c.charger_id = st.charger_id
    RETURNING c.charger_id
  )
  SELECT count(*) INTO v_healed FROM upd;

  RETURN COALESCE(v_healed, 0);
END;
$function$


-- ===== ottoq_record_balance_charge =====
CREATE OR REPLACE FUNCTION public.ottoq_record_balance_charge(p_vehicle_id uuid, p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  UPDATE vehicles SET config = COALESCE(config,'{}'::jsonb)
                    || jsonb_build_object('last_balance_charge_at', to_jsonb(p_at))
   WHERE id = p_vehicle_id;
  RETURN jsonb_build_object('ok', FOUND, 'vehicle_id', p_vehicle_id, 'at', p_at);
END; $function$


-- ===== ottoq_record_counterfactual =====
CREATE OR REPLACE FUNCTION public.ottoq_record_counterfactual(p_source_kind text, p_source_id uuid, p_scenario_label text, p_scenario_description text DEFAULT NULL::text, p_alternate_inputs jsonb DEFAULT '{}'::jsonb, p_alternate_model_version_id uuid DEFAULT NULL::uuid, p_alternate_parameters jsonb DEFAULT '{}'::jsonb, p_actual_outcome jsonb DEFAULT NULL::jsonb, p_counterfactual_outcome jsonb DEFAULT NULL::jsonb, p_outcome_kind text DEFAULT NULL::text, p_actual_value numeric DEFAULT NULL::numeric, p_counterfactual_value numeric DEFAULT NULL::numeric, p_delta_unit text DEFAULT NULL::text, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_vehicle_id uuid DEFAULT NULL::uuid, p_ran_by_actor_type text DEFAULT 'system'::text, p_ran_by_actor_id text DEFAULT NULL::text, p_source_correlation_id uuid DEFAULT NULL::uuid, p_source_decision_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_id UUID := gen_random_uuid();
  v_delta NUMERIC;
  v_dir TEXT;
BEGIN
  IF p_actual_value IS NOT NULL AND p_counterfactual_value IS NOT NULL THEN
    v_delta := p_counterfactual_value - p_actual_value;
    -- Direction is domain-specific; we default to "neutral" and let caller override.
    v_dir := 'neutral';
  END IF;

  INSERT INTO ottoq_counterfactuals (
    counterfactual_id, ran_at,
    source_kind, source_id, source_correlation_id, source_decision_at,
    scenario_label, scenario_description,
    alternate_inputs, alternate_model_version_id, alternate_parameters,
    actual_outcome, counterfactual_outcome,
    outcome_kind, actual_value, counterfactual_value,
    delta, delta_unit, delta_direction,
    fleet_operator_id, depot_id, vehicle_id,
    status, ran_by_actor_type, ran_by_actor_id
  ) VALUES (
    v_id, NOW(),
    p_source_kind, p_source_id, p_source_correlation_id, p_source_decision_at,
    p_scenario_label, p_scenario_description,
    p_alternate_inputs, p_alternate_model_version_id, p_alternate_parameters,
    p_actual_outcome, p_counterfactual_outcome,
    p_outcome_kind, p_actual_value, p_counterfactual_value,
    v_delta, p_delta_unit, v_dir,
    p_fleet_operator_id, p_depot_id, p_vehicle_id,
    'completed', p_ran_by_actor_type, p_ran_by_actor_id
  );

  PERFORM ottoq_record_event(
    p_actor_type    := p_ran_by_actor_type,
    p_actor_id      := p_ran_by_actor_id,
    p_event_type    := 'counterfactual.computed',
    p_entity_type   := 'counterfactual',
    p_entity_id     := v_id,
    p_fleet_operator_id := p_fleet_operator_id,
    p_depot_id      := p_depot_id,
    p_payload       := jsonb_build_object(
      'source_kind', p_source_kind, 'scenario', p_scenario_label,
      'actual_value', p_actual_value, 'counterfactual_value', p_counterfactual_value,
      'delta', v_delta
    ),
    p_severity      := 'info'
  );
  RETURN v_id;
END;
$function$


-- ===== ottoq_record_event =====
CREATE OR REPLACE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL::text, p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_previous_state jsonb DEFAULT NULL::jsonb, p_new_state jsonb DEFAULT NULL::jsonb, p_severity text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid, p_related_task_id uuid DEFAULT NULL::uuid, p_related_schedule_id uuid DEFAULT NULL::uuid, p_related_decision_id uuid DEFAULT NULL::uuid, p_outcome text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer, p_ingest_source text DEFAULT 'app'::text, p_signing_key_id text DEFAULT 'system:v1'::text, p_data_source text DEFAULT 'production'::text, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_event_id        UUID := gen_random_uuid();
  v_category        TEXT;
  v_severity        TEXT;
  v_payload_hash    TEXT;
  v_signature       TEXT;
  v_correlation_id  UUID;
  v_causation       UUID[] := '{}'::uuid[];
  v_parent          ottoq_events%ROWTYPE;
  v_occurred_at     TIMESTAMPTZ := NOW();
BEGIN
  SELECT category, default_severity INTO v_category, v_severity
    FROM ottoq_event_types_catalog WHERE event_type = p_event_type;
  IF v_category IS NULL THEN
    v_category := 'system_event';
    v_severity := 'warning';
  END IF;
  v_severity := COALESCE(p_severity, v_severity);

  v_correlation_id := COALESCE(
    p_correlation_id,
    NULLIF(current_setting('ottoq.correlation_id', TRUE), '')::UUID,
    gen_random_uuid()
  );

  IF p_parent_event_id IS NOT NULL THEN
    SELECT * INTO v_parent FROM ottoq_events WHERE event_id = p_parent_event_id;
    IF FOUND THEN
      v_causation := v_parent.causation_chain || p_parent_event_id;
    ELSE
      v_causation := ARRAY[p_parent_event_id];
    END IF;
  END IF;

  v_payload_hash := ottoq_compute_event_hash(p_payload);
  v_signature := ottoq_sign_event(
    v_event_id, v_occurred_at, p_actor_type, p_event_type,
    p_entity_type, p_entity_id, v_payload_hash, p_signing_key_id
  );

  INSERT INTO ottoq_events (
    event_id, occurred_at, recorded_at,
    actor_type, actor_id, actor_metadata,
    event_type, event_category, severity,
    entity_type, entity_id,
    fleet_operator_id, depot_id,
    payload, previous_state, new_state,
    correlation_id, parent_event_id, causation_chain,
    related_task_id, related_schedule_id, related_decision_id,
    payload_hash, signature, signature_key_id,
    outcome, latency_ms, ingest_source,
    data_source, sim_run_id
  ) VALUES (
    v_event_id, v_occurred_at, NOW(),
    p_actor_type, p_actor_id, p_actor_metadata,
    p_event_type, v_category, v_severity,
    p_entity_type, p_entity_id,
    p_fleet_operator_id, p_depot_id,
    p_payload, p_previous_state, p_new_state,
    v_correlation_id, p_parent_event_id, v_causation,
    p_related_task_id, p_related_schedule_id, p_related_decision_id,
    v_payload_hash, v_signature, p_signing_key_id,
    p_outcome, p_latency_ms, p_ingest_source,
    COALESCE(p_data_source, 'production'), p_sim_run_id
  );

  RETURN v_event_id;
END;
$function$


-- ===== ottoq_record_feature_value =====
CREATE OR REPLACE FUNCTION public.ottoq_record_feature_value(p_feature_name text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_value_numeric numeric DEFAULT NULL::numeric, p_value_integer bigint DEFAULT NULL::bigint, p_value_boolean boolean DEFAULT NULL::boolean, p_value_text text DEFAULT NULL::text, p_value_timestamp timestamp with time zone DEFAULT NULL::timestamp with time zone, p_value_json jsonb DEFAULT NULL::jsonb, p_valid_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_observation_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_source text DEFAULT 'app'::text, p_source_event_id uuid DEFAULT NULL::uuid, p_computed_by text DEFAULT NULL::text, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_quality_score numeric DEFAULT NULL::numeric, p_is_imputed boolean DEFAULT false, p_emit_event boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_value_id    UUID := gen_random_uuid();
  v_valid_from  TIMESTAMPTZ := COALESCE(p_valid_from, NOW());
  v_feature_ver INTEGER;
BEGIN
  UPDATE ottoq_feature_values fv
     SET valid_until = v_valid_from
   WHERE fv.feature_name = p_feature_name
     AND ((fv.entity_id IS NULL AND p_entity_id IS NULL) OR fv.entity_id = p_entity_id)
     AND fv.entity_type = p_entity_type
     AND fv.valid_until IS NULL;

  SELECT version INTO v_feature_ver FROM ottoq_features WHERE feature_name = p_feature_name;
  v_feature_ver := COALESCE(v_feature_ver, 1);

  INSERT INTO ottoq_feature_values (
    value_id, feature_name, entity_type, entity_id,
    value_numeric, value_integer, value_boolean,
    value_text, value_timestamp, value_json,
    valid_from, observation_time,
    source, source_event_id, computed_by, feature_version,
    quality_score, is_imputed,
    fleet_operator_id, depot_id
  ) VALUES (
    v_value_id, p_feature_name, p_entity_type, p_entity_id,
    p_value_numeric, p_value_integer, p_value_boolean,
    p_value_text, p_value_timestamp, p_value_json,
    v_valid_from, COALESCE(p_observation_time, NOW()),
    p_source, p_source_event_id, p_computed_by, v_feature_ver,
    p_quality_score, p_is_imputed,
    p_fleet_operator_id, p_depot_id
  );

  -- Optional event emission (off by default — feature writes are high-volume)
  IF p_emit_event THEN
    PERFORM ottoq_record_event(
      p_actor_type        := 'ottoq_engine',
      p_event_type        := 'feature.recorded',
      p_entity_type       := p_entity_type,
      p_entity_id         := p_entity_id,
      p_fleet_operator_id := p_fleet_operator_id,
      p_depot_id          := p_depot_id,
      p_payload           := jsonb_build_object(
        'feature_name', p_feature_name,
        'value_id', v_value_id,
        'source', p_source,
        'quality_score', p_quality_score
      ),
      p_severity          := 'debug'
    );
  END IF;

  RETURN v_value_id;
END;
$function$


-- ===== ottoq_record_prediction =====
CREATE OR REPLACE FUNCTION public.ottoq_record_prediction(p_prediction_type text, p_depot_id uuid DEFAULT NULL::uuid, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_vehicle_id uuid DEFAULT NULL::uuid, p_predicted_value jsonb DEFAULT NULL::jsonb, p_p10 numeric DEFAULT NULL::numeric, p_p50 numeric DEFAULT NULL::numeric, p_p90 numeric DEFAULT NULL::numeric, p_confidence numeric DEFAULT NULL::numeric, p_prediction_interval_method text DEFAULT NULL::text, p_prediction_baseline text DEFAULT 'heuristic'::text, p_target_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_horizon_minutes integer DEFAULT NULL::integer, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_recommendation jsonb DEFAULT NULL::jsonb, p_action_type text DEFAULT NULL::text, p_action_parameters jsonb DEFAULT NULL::jsonb, p_model_version_id uuid DEFAULT NULL::uuid, p_ab_test_id uuid DEFAULT NULL::uuid, p_ab_test_variant text DEFAULT NULL::text, p_inputs jsonb DEFAULT NULL::jsonb, p_feature_snapshot_ids uuid[] DEFAULT NULL::uuid[], p_latency_ms integer DEFAULT NULL::integer, p_shadow_only boolean DEFAULT false, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_prediction_id  UUID := gen_random_uuid();
  v_event_id       UUID;
  v_inputs_hash    TEXT;
  v_correlation    UUID;
  v_type           ottoq_prediction_types_catalog%ROWTYPE;
  v_title          TEXT;
BEGIN
  SELECT * INTO v_type FROM ottoq_prediction_types_catalog
   WHERE prediction_type = p_prediction_type AND status IN ('active','shadow');
  IF NOT FOUND THEN
    PERFORM ottoq_record_event(
      p_actor_type := 'ottoq_engine',
      p_event_type := 'system.catalog_miss',
      p_entity_type := 'prediction',
      p_payload := jsonb_build_object('unknown_prediction_type', p_prediction_type),
      p_severity := 'warning'
    );
  END IF;

  -- Default title to prediction_type description or the type code itself
  v_title := COALESCE(p_title, v_type.title, p_prediction_type);

  IF p_inputs IS NOT NULL THEN
    v_inputs_hash := encode(digest(jsonb_strip_nulls(p_inputs)::text, 'sha256'), 'hex');
  END IF;

  v_correlation := COALESCE(p_correlation_id,
    NULLIF(current_setting('ottoq.correlation_id', TRUE), '')::UUID,
    gen_random_uuid()
  );

  v_event_id := ottoq_record_event(
    p_actor_type        := 'ottoq_engine',
    p_event_type        := 'prediction.emitted',
    p_entity_type       := COALESCE(v_type.target_entity_type, 'prediction'),
    p_entity_id         := v_prediction_id,
    p_fleet_operator_id := p_fleet_operator_id,
    p_depot_id          := p_depot_id,
    p_payload           := jsonb_build_object(
                            'prediction_type', p_prediction_type,
                            'predicted_value', p_predicted_value,
                            'p10', p_p10, 'p50', p_p50, 'p90', p_p90,
                            'confidence', p_confidence,
                            'horizon_minutes', p_horizon_minutes,
                            'baseline', p_prediction_baseline,
                            'shadow_only', p_shadow_only,
                            'model_version_id', p_model_version_id
                          ),
    p_severity          := CASE WHEN p_shadow_only THEN 'debug' ELSE 'info' END,
    p_correlation_id    := v_correlation,
    p_parent_event_id   := p_parent_event_id,
    p_latency_ms        := p_latency_ms
  );

  INSERT INTO ottoq_predictions (
    id, depot_id, fleet_operator_id, vehicle_id,
    prediction_type, title, description,
    predicted_value, p10, p50, p90,
    confidence, prediction_interval_method, prediction_baseline,
    recommendation, action_type, action_parameters,
    target_at, horizon_minutes, expires_at,
    model_version_id, ab_test_id, ab_test_variant,
    supporting_data, inputs_hash, feature_snapshot_ids,
    shadow_only, event_id, correlation_id, latency_ms,
    status, created_at
  ) VALUES (
    v_prediction_id, p_depot_id, p_fleet_operator_id, p_vehicle_id,
    p_prediction_type, v_title, p_description,
    p_predicted_value, p_p10, p_p50, p_p90,
    p_confidence, p_prediction_interval_method, p_prediction_baseline,
    p_recommendation, p_action_type, p_action_parameters,
    p_target_at, p_horizon_minutes,
    COALESCE(p_expires_at,
             p_target_at + INTERVAL '1 hour',
             NOW() + (COALESCE(p_horizon_minutes, 60) || ' minutes')::INTERVAL),
    p_model_version_id, p_ab_test_id, p_ab_test_variant,
    p_inputs, v_inputs_hash, p_feature_snapshot_ids,
    p_shadow_only, v_event_id, v_correlation, p_latency_ms,
    'proposed', NOW()
  );

  RETURN v_prediction_id;
END;
$function$


-- ===== ottoq_record_sla_violation =====
CREATE OR REPLACE FUNCTION public.ottoq_record_sla_violation(p_fleet_operator_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_schedule_id uuid, p_rule_code text, p_rule_evaluation_id uuid, p_severity text, p_clause_text text, p_expected_value jsonb, p_observed_value jsonb, p_variance_amount numeric, p_variance_unit text, p_correlation_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_id UUID := gen_random_uuid();
  v_event_id UUID;
BEGIN
  v_event_id := ottoq_record_event(
    p_actor_type        := 'ottoq_engine',
    p_event_type        := 'sla.violation_recorded',
    p_entity_type       := 'sla_violation',
    p_entity_id         := v_id,
    p_fleet_operator_id := p_fleet_operator_id,
    p_depot_id          := p_depot_id,
    p_payload           := jsonb_build_object(
      'rule_code', p_rule_code,
      'severity', p_severity,
      'variance_amount', p_variance_amount,
      'variance_unit', p_variance_unit,
      'vehicle_id', p_vehicle_id,
      'schedule_id', p_schedule_id
    ),
    p_severity          := CASE p_severity WHEN 'critical_breach' THEN 'critical' WHEN 'breach' THEN 'error' ELSE 'warning' END,
    p_correlation_id    := p_correlation_id
  );

  INSERT INTO ottoq_sla_violations (
    violation_id, fleet_operator_id, depot_id, vehicle_id, schedule_id,
    rule_code, rule_evaluation_id, clause_text,
    expected_value, observed_value, variance_amount, variance_unit, severity,
    linked_event_id, correlation_id
  ) VALUES (
    v_id, p_fleet_operator_id, p_depot_id, p_vehicle_id, p_schedule_id,
    p_rule_code, p_rule_evaluation_id, p_clause_text,
    p_expected_value, p_observed_value, p_variance_amount, p_variance_unit, p_severity,
    v_event_id, p_correlation_id
  );
  RETURN v_id;
END;
$function$


-- ===== ottoq_register_audit_report =====
CREATE OR REPLACE FUNCTION public.ottoq_register_audit_report(p_report_type text, p_report_subtype text DEFAULT NULL::text, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_window_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_window_end timestamp with time zone DEFAULT NULL::timestamp with time zone, p_requested_by_actor_type text DEFAULT 'system'::text, p_requested_by_actor_id text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_format text DEFAULT 'json'::text, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_parent_report_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_report_id UUID := gen_random_uuid();
  v_event_id  UUID;
BEGIN
  INSERT INTO ottoq_audit_reports (
    report_id, report_type, report_subtype,
    fleet_operator_id, depot_id,
    window_start, window_end,
    requested_by_actor_type, requested_by_actor_id, requested_at,
    generation_status, generation_started_at,
    title, description, format, expires_at, parent_report_id
  ) VALUES (
    v_report_id, p_report_type, p_report_subtype,
    p_fleet_operator_id, p_depot_id,
    COALESCE(p_window_start, NOW() - INTERVAL '24 hours'),
    COALESCE(p_window_end, NOW()),
    p_requested_by_actor_type, p_requested_by_actor_id, NOW(),
    'generating', NOW(),
    p_title, p_description, p_format, p_expires_at, p_parent_report_id
  );

  v_event_id := ottoq_record_event(
    p_actor_type        := p_requested_by_actor_type,
    p_actor_id          := p_requested_by_actor_id,
    p_event_type        := 'audit.report_requested',
    p_entity_type       := 'audit_report',
    p_entity_id         := v_report_id,
    p_fleet_operator_id := p_fleet_operator_id,
    p_depot_id          := p_depot_id,
    p_payload           := jsonb_build_object(
      'report_type', p_report_type, 'report_subtype', p_report_subtype,
      'window_start', p_window_start, 'window_end', p_window_end
    ),
    p_severity          := 'info'
  );

  UPDATE ottoq_audit_reports SET source_event_id = v_event_id WHERE report_id = v_report_id;
  RETURN v_report_id;
END;
$function$


-- ===== ottoq_register_rule =====
CREATE OR REPLACE FUNCTION public.ottoq_register_rule(p_rule_code text, p_category text, p_title text, p_description text, p_rationale text, p_severity text, p_enforcement text, p_scope text, p_evaluator_function text, p_default_parameters jsonb DEFAULT '{}'::jsonb, p_applies_to_actions text[] DEFAULT '{}'::text[], p_applies_to_entities text[] DEFAULT '{}'::text[], p_introduced_in text DEFAULT 'unknown'::text, p_external_references jsonb DEFAULT '{}'::jsonb, p_override_allowed boolean DEFAULT false, p_override_min_role text DEFAULT NULL::text, p_status text DEFAULT 'active'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_existing_id   UUID;
  v_new_version   INTEGER;
  v_new_id        UUID;
BEGIN
  SELECT rule_id, version + 1
    INTO v_existing_id, v_new_version
    FROM ottoq_rules
   WHERE rule_code = p_rule_code
   ORDER BY version DESC
   LIMIT 1;

  v_new_version := COALESCE(v_new_version, 1);

  -- Archive prior active version
  UPDATE ottoq_rules
     SET status = 'archived', updated_at = NOW()
   WHERE rule_code = p_rule_code AND status = 'active';

  INSERT INTO ottoq_rules (
    rule_code, version, category, title, description, rationale,
    severity, enforcement, scope, evaluator_function,
    default_parameters, applies_to_actions, applies_to_entities,
    introduced_in, external_references, override_allowed, override_min_role,
    status
  ) VALUES (
    p_rule_code, v_new_version, p_category, p_title, p_description, p_rationale,
    p_severity, p_enforcement, p_scope, p_evaluator_function,
    p_default_parameters, p_applies_to_actions, p_applies_to_entities,
    p_introduced_in, p_external_references, p_override_allowed, p_override_min_role,
    p_status
  ) RETURNING rule_id INTO v_new_id;

  RETURN v_new_id;
END;
$function$


-- ===== ottoq_reopen_visit_atoms =====
CREATE OR REPLACE FUNCTION public.ottoq_reopen_visit_atoms(p_vehicle uuid, p_svcs text[], p_since timestamp with time zone, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_visit uuid; v_atoms jsonb; v_new jsonb := '[]'::jsonb; v_a jsonb;
        v_n int := 0;            -- atoms genuinely RE-OPENED (credit voided / work cut mid-flight)
        v_from_done int := 0;    -- strict phase-9 definition: atom had been marked done
        v_from_active int := 0;  -- atom was visibly mid-work
        v_already_due int := 0;  -- atom matched the service set but was never credited
        v_outstanding int := 0; v_status text; v_st text;
        v_meta jsonb := '{}'::jsonb; v_run uuid;
        v_fallback boolean := false; v_attempts int := 0; v_max int := 3;
        v_stamp jsonb; v_row_reopened boolean := false;
BEGIN
  IF p_vehicle IS NULL THEN RETURN 0; END IF;
  -- TOTAL: an unknown/empty purpose maps to no atoms; nothing to re-open.
  IF p_svcs IS NULL OR array_length(p_svcs,1) IS NULL THEN RETURN 0; END IF;

  -- (1) The LIVE visit.
  SELECT vn.visit_id, vn.atoms, vn.status, COALESCE(vn.meta,'{}'::jsonb), vn.sim_run_id
    INTO v_visit, v_atoms, v_status, v_meta, v_run
    FROM ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle AND vn.status IN ('open','in_progress')
   ORDER BY vn.created_at DESC LIMIT 1;

  -- (2) FALLBACK, WIDENED (PHASE 10 FIX B-3).
  -- The old fallback pre-filtered with EXISTS(atom.svc = ANY(p_svcs)). MEASURED (phase 9,
  -- vehicle 2d2c46af): a booking with purpose='wash' -> p_svcs {exterior_wash,sensor_clean}
  -- was matched against a manifest whose only bay atom was 'interior_deep_clean'
  -- (workflow_plan leg 2, requires_bay='detail'). The intersection was EMPTY, the row was
  -- invisible to the fallback, and the outstanding work was forgotten outright.
  -- A needs row that still OWES work now qualifies on its own, intersection or not; the
  -- intersection only decides RANKING.
  IF v_visit IS NULL THEN
    SELECT c.visit_id, c.atoms, c.status, COALESCE(c.meta,'{}'::jsonb), c.sim_run_id
      INTO v_visit, v_atoms, v_status, v_meta, v_run
      FROM (
        SELECT vn.*,
               (SELECT count(*) FROM jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) a
                 WHERE a->>'svc' = ANY(p_svcs)
                   AND COALESCE(a->>'status','pending') = 'done'
                   AND (p_since IS NULL OR (a->>'done_at') IS NULL
                        OR (a->>'done_at')::timestamptz >= p_since)) AS n_reopenable,
               (SELECT count(*) FROM jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) a
                 WHERE COALESCE(a->>'status','pending') NOT IN ('done','cancelled')) AS n_outstanding
          FROM ottoq_visit_needs vn
         WHERE vn.vehicle_id = p_vehicle
           AND vn.created_at >= now() - interval '24 hours'
      ) c
     WHERE c.n_reopenable > 0 OR c.n_outstanding > 0
     ORDER BY c.n_reopenable DESC, c.n_outstanding DESC, c.created_at DESC
     LIMIT 1;
    v_fallback := (v_visit IS NOT NULL);
  END IF;

  IF v_visit IS NULL THEN RETURN 0; END IF;

  -- ══════════════ LOOP BOUND — a thrashing vehicle must terminate ══════════════
  v_max := GREATEST(COALESCE(public.ottoq_policy_get(v_run,'visit_reopen_max_attempts',3)::int, 3), 0);
  v_attempts := COALESCE((v_meta->'reopen'->>'attempts')::int, 0);
  IF v_attempts >= v_max THEN
    BEGIN
      UPDATE ottoq_visit_needs
         SET meta = COALESCE(meta,'{}'::jsonb)
                    || jsonb_build_object('reopen_escalated', true,
                                          'reopen_escalated_at', now(),
                                          'reopen_escalated_reason', p_reason)
       WHERE visit_id = v_visit;
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'reopen_visit_atoms',
        p_event_type := 'ottoq.replan_escalated',
        p_entity_type := 'vehicle', p_entity_id := p_vehicle,
        p_payload := jsonb_build_object('visit_id', v_visit, 'attempts', v_attempts,
                                        'max_attempts', v_max, 'reason', p_reason,
                                        'doctrine','bounded_replan_then_flag'),
        p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id := v_run);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'replan_escalated stamp dropped: sqlstate=% msg=%', SQLSTATE, SQLERRM;
    END;
    RETURN 0;
  END IF;

  -- ══════════════ PHASE 10 FIX B-2 — RE-OPEN THE ATOM, NOT JUST THE ROW ══════════════
  -- The old loop only ever touched atoms at status='done'. MEASURED (phase 9): across the
  -- whole run mechanical_pm sat at 62 pending / 2 open, sensor_calibration 24 pending / 0,
  -- fault_repair 6 pending / 0 -- a bay marks its atom done only on CLEAN EXIT, so an
  -- interrupted session almost never leaves a 'done' atom behind. That is why strict
  -- atoms_reopened>0 was 2 of 8: there was literally nothing in 'done' state to re-open.
  FOR v_a IN SELECT * FROM jsonb_array_elements(COALESCE(v_atoms,'[]'::jsonb)) LOOP
    v_st := lower(COALESCE(v_a->>'status','pending'));

    IF v_a->>'svc' = ANY(p_svcs) AND v_st <> 'cancelled' THEN
      IF v_st = 'done'
         AND (p_since IS NULL OR (v_a->>'done_at') IS NULL OR (v_a->>'done_at')::timestamptz >= p_since)
      THEN
        -- Credited, then the session was cut short: the credit is void. Redo it.
        v_a := (v_a - 'done_at')
               || jsonb_build_object('status','open', 'reopened_at', to_jsonb(now()),
                                     'reopen_reason', p_reason, 'reopened_from', 'done');
        v_from_done := v_from_done + 1; v_n := v_n + 1;
      ELSIF v_st IN ('in_progress','active','started') THEN
        -- Visibly mid-work when the space was taken away. Genuinely cut short.
        v_a := (v_a - 'done_at')
               || jsonb_build_object('status','open', 'reopened_at', to_jsonb(now()),
                                     'reopen_reason', p_reason, 'reopened_from', v_st);
        v_from_active := v_from_active + 1; v_n := v_n + 1;
      ELSIF v_st <> 'done' THEN
        -- ALREADY DUE. The atom was never credited, so there is nothing to re-open. Stamp it
        -- so the interruption is auditable, but do NOT count it as a re-open -- counting it
        -- would inflate the metric with work the depot never actually lost.
        v_a := v_a || jsonb_build_object('cut_short_at', to_jsonb(now()),
                                         'cut_short_reason', p_reason);
        v_already_due := v_already_due + 1;
      END IF;
    END IF;

    IF lower(COALESCE(v_a->>'status','pending')) NOT IN ('done','cancelled') THEN
      v_outstanding := v_outstanding + 1;
    END IF;
    v_new := v_new || jsonb_build_array(v_a);
  END LOOP;

  -- Row-level stamp. `ottoq_visit_needs` has NO reopen_reason COLUMN, so the row-level
  -- telemetry the doctrine asks for lives in meta->>'reopen_reason'.
  v_stamp := jsonb_build_object(
    'reopen_reason', p_reason,
    'reopen', jsonb_build_object('attempts', v_attempts + 1,
                                 'max_attempts', v_max,
                                 'last_reason', p_reason,
                                 'last_at', now(),
                                 'atoms_reopened', v_n,
                                 'atoms_reopened_from_done', v_from_done,
                                 'atoms_reopened_from_active', v_from_active,
                                 'atoms_already_due', v_already_due,
                                 'outstanding_restored', CASE WHEN v_n = 0 THEN v_outstanding ELSE 0 END,
                                 'via_fallback', v_fallback,
                                 'prior_status', v_status));

  -- ══════════════ PHASE 10 FIX B-1 — WRITE ALWAYS ══════════════
  -- WAS: `ELSIF v_outstanding > 0 AND v_status <> 'open' THEN`.
  -- When the needs row happened to be ALREADY open, that guard made the function write
  -- NOTHING -- no atom change, no meta stamp, no visit_reopened event -- and the caller's
  -- outcome check (`meta->>'reopen_reason' = 'bay_session_interrupted'`) therefore scored the
  -- interruption as FORGOTTEN. All 3 of the 3 phase-9 total misses were this branch
  -- (2d2c46af, ca2624fc, c3333333: none had a reopen key in meta).
  IF v_n > 0 OR v_outstanding > 0 THEN
    UPDATE ottoq_visit_needs
       SET atoms  = v_new,
           status = 'open',
           meta   = COALESCE(meta,'{}'::jsonb) || v_stamp
     WHERE visit_id = v_visit;
    v_row_reopened := true;
  END IF;

  IF v_row_reopened THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'reopen_visit_atoms',
        p_event_type := 'ottoq.visit_reopened',
        p_entity_type := 'vehicle', p_entity_id := p_vehicle,
        p_payload := jsonb_build_object('visit_id', v_visit,
                                        'atoms_reopened', v_n,
                                        'atoms_reopened_from_done', v_from_done,
                                        'atoms_reopened_from_active', v_from_active,
                                        'atoms_already_due', v_already_due,
                                        'outstanding_restored', CASE WHEN v_n = 0 THEN v_outstanding ELSE 0 END,
                                        'outstanding_after', v_outstanding,
                                        'prior_status', v_status,
                                        'via_fallback', v_fallback,
                                        'attempts', v_attempts + 1,
                                        'max_attempts', v_max,
                                        'reopen_reason', p_reason),
        p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id := v_run);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'visit_reopened audit event dropped: sqlstate=% msg=%', SQLSTATE, SQLERRM;
    END;
  END IF;

  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_reopen_visit_atoms: FAILED sqlstate=% msg=% vehicle=%', SQLSTATE, SQLERRM, p_vehicle;
  RETURN 0;
END
$function$


-- ===== ottoq_replay_window =====
CREATE OR REPLACE FUNCTION public.ottoq_replay_window(p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_vehicle_id uuid DEFAULT NULL::uuid, p_correlation_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(out_seq bigint, out_occurred_at timestamp with time zone, out_kind text, out_subject text, out_summary text, out_severity text, out_actor_type text, out_actor_id text, out_payload jsonb, out_event_id uuid, out_correlation_id uuid)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  RETURN QUERY
  SELECT * FROM (
    SELECT
      e.event_seq, e.occurred_at, 'event'::text, e.entity_type, e.event_type,
      e.severity, e.actor_type, e.actor_id, e.payload, e.event_id, e.correlation_id
    FROM ottoq_events e
    WHERE e.occurred_at BETWEEN p_window_start AND p_window_end
      AND (p_fleet_operator_id IS NULL OR e.fleet_operator_id = p_fleet_operator_id)
      AND (p_depot_id          IS NULL OR e.depot_id = p_depot_id)
      AND (p_vehicle_id        IS NULL OR e.entity_id = p_vehicle_id)
      AND (p_correlation_id    IS NULL OR e.correlation_id = p_correlation_id)

    UNION ALL
    SELECT
      NULL::bigint, re.evaluated_at, 'rule_failure'::text, re.entity_type,
      re.rule_code || ' — ' || COALESCE(re.reason,''),
      re.severity, 'ottoq_engine'::text, NULL::text,
      jsonb_build_object('rule_code', re.rule_code, 'reason', re.reason,
                         'enforcement_taken', re.enforcement_taken),
      re.linked_event_id, re.correlation_id
    FROM ottoq_rule_evaluations re
    WHERE re.evaluated_at BETWEEN p_window_start AND p_window_end AND re.passed = FALSE
      AND (p_fleet_operator_id IS NULL OR re.fleet_operator_id = p_fleet_operator_id)
      AND (p_depot_id          IS NULL OR re.depot_id = p_depot_id)
      AND (p_vehicle_id        IS NULL OR re.entity_id = p_vehicle_id)
      AND (p_correlation_id    IS NULL OR re.correlation_id = p_correlation_id)

    UNION ALL
    SELECT
      NULL::bigint, ao.observed_at, 'anomaly'::text, ao.entity_type,
      ao.detector_code || ' score=' || ROUND(ao.anomaly_score::NUMERIC, 3)::text,
      ao.severity, 'ottoq_engine'::text, NULL::text,
      jsonb_build_object('detector', ao.detector_code, 'score', ao.anomaly_score,
                         'context', ao.context),
      ao.linked_event_id, ao.correlation_id
    FROM ottoq_anomaly_observations ao
    WHERE ao.observed_at BETWEEN p_window_start AND p_window_end AND ao.is_anomaly = TRUE
      AND (p_fleet_operator_id IS NULL OR ao.fleet_operator_id = p_fleet_operator_id)
      AND (p_depot_id          IS NULL OR ao.depot_id = p_depot_id)
      AND (p_vehicle_id        IS NULL OR ao.entity_id = p_vehicle_id)
      AND (p_correlation_id    IS NULL OR ao.correlation_id = p_correlation_id)

    UNION ALL
    SELECT
      NULL::bigint, p.created_at, 'prediction'::text, p.prediction_type::text,
      format('predict %s → %s', p.prediction_type, COALESCE(p.predicted_value::text, 'n/a')),
      'info'::text, 'ottoq_engine'::text, NULL::text,
      jsonb_build_object('type', p.prediction_type, 'value', p.predicted_value,
                         'p10', p.p10, 'p50', p.p50, 'p90', p.p90,
                         'baseline', p.prediction_baseline),
      p.event_id, p.correlation_id
    FROM ottoq_predictions p
    WHERE p.created_at BETWEEN p_window_start AND p_window_end
      AND (p_fleet_operator_id IS NULL OR p.fleet_operator_id = p_fleet_operator_id)
      AND (p_depot_id          IS NULL OR p.depot_id = p_depot_id)
      AND (p_vehicle_id        IS NULL OR p.vehicle_id = p_vehicle_id)
      AND (p_correlation_id    IS NULL OR p.correlation_id = p_correlation_id)

    UNION ALL
    SELECT
      NULL::bigint, r.emitted_at, 'recommendation'::text, r.proposed_action,
      format('%s → %s (%s)', r.proposed_action, r.status, COALESCE(r.decision_reason,'')),
      CASE WHEN r.status='rejected' THEN 'warning' ELSE 'info' END, 'ottoq_engine'::text, NULL::text,
      jsonb_build_object('action', r.proposed_action, 'status', r.status,
                         'rules_blocked_by', r.rules_blocked_by, 'shadow', r.shadow_only),
      NULL::uuid, r.correlation_id
    FROM ottoq_recommendations r
    WHERE r.emitted_at BETWEEN p_window_start AND p_window_end
      AND (p_fleet_operator_id IS NULL OR r.fleet_operator_id = p_fleet_operator_id)
      AND (p_depot_id          IS NULL OR r.depot_id = p_depot_id)
      AND (p_correlation_id    IS NULL OR r.correlation_id = p_correlation_id)

    UNION ALL
    SELECT
      NULL::bigint, ei.triggered_at, 'emergency'::text, ei.protocol_code,
      'cascade triggered: ' || ei.protocol_code,
      'safety_critical'::text, ei.triggered_by_actor_type, ei.triggered_by_actor_id,
      jsonb_build_object('protocol', ei.protocol_code, 'outcome', ei.outcome,
                         'actions_count', jsonb_array_length(ei.cascade_executed)),
      ei.linked_event_id, ei.correlation_id
    FROM ottoq_emergency_invocations ei
    WHERE ei.triggered_at BETWEEN p_window_start AND p_window_end
      AND (p_depot_id IS NULL OR ei.depot_id = p_depot_id)
      AND (p_correlation_id IS NULL OR ei.correlation_id = p_correlation_id)
  ) AS combined
  ORDER BY combined.occurred_at ASC, combined.event_seq ASC NULLS LAST;
END;
$function$


-- ===== ottoq_reserve_stall =====
CREATE OR REPLACE FUNCTION public.ottoq_reserve_stall(p_stall_id uuid, p_vehicle_id uuid, p_now timestamp with time zone, p_ttl_seconds integer DEFAULT 600)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_ok boolean;
BEGIN
  -- atomic: reserve only if free (no current vehicle, and no live reservation by another vehicle)
  UPDATE stalls
     SET reserved_by = p_vehicle_id, reserved_at = p_now,
         reservation_expires_at = p_now + (p_ttl_seconds || ' seconds')::interval
   WHERE id = p_stall_id
     AND current_vehicle_id IS NULL
     AND (reserved_by IS NULL OR reserved_by = p_vehicle_id
          OR reservation_expires_at IS NULL OR reservation_expires_at <= p_now)
  RETURNING true INTO v_ok;
  RETURN COALESCE(v_ok, false);
END;
$function$


-- ===== ottoq_resolve_model_for_prediction =====
CREATE OR REPLACE FUNCTION public.ottoq_resolve_model_for_prediction(p_prediction_type text, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_vehicle_class text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(out_model_version_id uuid, out_fallback_model_version_id uuid, out_shadow_mode boolean, out_route_id uuid, out_specificity_score integer, out_match_reason text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_now TIMESTAMPTZ := NOW();
  v_hash NUMERIC;
BEGIN
  v_hash := COALESCE(
    (abs(hashtext(COALESCE(p_entity_id::text, p_prediction_type) || COALESCE(p_depot_id::text,''))) % 10000)::NUMERIC / 100.0,
    50.0
  );

  RETURN QUERY
  WITH scored_routes AS (
    SELECT
      r.route_id AS r_route_id,
      r.model_version_id AS r_model_version_id,
      r.fallback_model_version_id AS r_fallback_model_version_id,
      r.shadow_mode AS r_shadow_mode,
      r.traffic_share_pct AS r_traffic_share_pct,
      r.priority AS r_priority,
      ( CASE WHEN r.fleet_operator_id IS NOT NULL AND r.fleet_operator_id = p_fleet_operator_id THEN 10 ELSE 0 END
      + CASE WHEN r.depot_id IS NOT NULL AND r.depot_id = p_depot_id THEN 10 ELSE 0 END
      + CASE WHEN r.vehicle_class IS NOT NULL AND r.vehicle_class = p_vehicle_class THEN 10 ELSE 0 END
      ) AS r_scope_score,
      ( CASE WHEN r.fleet_operator_id IS NULL OR r.fleet_operator_id = p_fleet_operator_id THEN 0 ELSE -1000 END
      + CASE WHEN r.depot_id IS NULL OR r.depot_id = p_depot_id THEN 0 ELSE -1000 END
      + CASE WHEN r.vehicle_class IS NULL OR r.vehicle_class = p_vehicle_class THEN 0 ELSE -1000 END
      ) AS r_exclusion_score
    FROM ottoq_model_routes r
    WHERE r.prediction_type = p_prediction_type
      AND r.effective_from <= v_now
      AND (r.effective_until IS NULL OR r.effective_until > v_now)
  ),
  eligible AS (
    SELECT * FROM scored_routes WHERE r_exclusion_score = 0
  ),
  top_priority AS (
    SELECT * FROM eligible
     ORDER BY (r_scope_score + r_priority) DESC, r_route_id
  ),
  selected AS (
    SELECT *,
      SUM(r_traffic_share_pct) OVER (ORDER BY (r_scope_score + r_priority) DESC, r_route_id) AS r_cumulative_pct
    FROM top_priority
  )
  SELECT
    s.r_model_version_id,
    s.r_fallback_model_version_id,
    s.r_shadow_mode,
    s.r_route_id,
    s.r_scope_score::INTEGER,
    format('matched route_id=%s priority=%s scope_score=%s', s.r_route_id, s.r_priority, s.r_scope_score)
  FROM selected s
  WHERE v_hash <= s.r_cumulative_pct
  ORDER BY (s.r_scope_score + s.r_priority) DESC, s.r_route_id
  LIMIT 1;
END;
$function$


-- ===== ottoq_resolve_rule_parameters =====
CREATE OR REPLACE FUNCTION public.ottoq_resolve_rule_parameters(p_rule_code text, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_vehicle_class text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_params        JSONB;
  v_fleet_params  JSONB;
  v_depot_params  JSONB;
BEGIN
  -- Start with rule defaults
  SELECT default_parameters INTO v_params
    FROM ottoq_rules
   WHERE rule_code = p_rule_code AND status = 'active'
   ORDER BY version DESC
   LIMIT 1;

  IF v_params IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  -- Layer in fleet-operator overrides
  IF p_fleet_operator_id IS NOT NULL THEN
    SELECT parameters INTO v_fleet_params
      FROM ottoq_rule_parameters
     WHERE rule_code = p_rule_code
       AND scope = 'fleet_operator'
       AND scope_id = p_fleet_operator_id
       AND effective_from <= NOW()
       AND (effective_until IS NULL OR effective_until > NOW())
     ORDER BY effective_from DESC
     LIMIT 1;
    IF v_fleet_params IS NOT NULL THEN
      v_params := v_params || v_fleet_params;
    END IF;
  END IF;

  -- Layer in depot overrides (most specific)
  IF p_depot_id IS NOT NULL THEN
    SELECT parameters INTO v_depot_params
      FROM ottoq_rule_parameters
     WHERE rule_code = p_rule_code
       AND scope = 'depot'
       AND scope_id = p_depot_id
       AND effective_from <= NOW()
       AND (effective_until IS NULL OR effective_until > NOW())
     ORDER BY effective_from DESC
     LIMIT 1;
    IF v_depot_params IS NOT NULL THEN
      v_params := v_params || v_depot_params;
    END IF;
  END IF;

  RETURN v_params;
END;
$function$


-- ===== ottoq_resolve_signing_secret =====
CREATE OR REPLACE FUNCTION public.ottoq_resolve_signing_secret(p_key_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_secret   TEXT;
  v_ref      TEXT;
  v_guc_name TEXT := 'ottoq.signing_secret_' || replace(p_key_id, ':', '_');
BEGIN
  -- 1. GUC override (set by edge function on connection). Also the cache slot.
  v_secret := current_setting(v_guc_name, TRUE);
  IF v_secret IS NOT NULL AND length(v_secret) > 0 THEN
    RETURN v_secret;
  END IF;

  -- 2. Default GUC for the system key (allows bootstrap)
  IF p_key_id = 'system:v1' THEN
    v_secret := current_setting('ottoq.signing_secret_default', TRUE);
    IF v_secret IS NOT NULL AND length(v_secret) > 0 THEN
      RETURN v_secret;
    END IF;
  END IF;

  -- 3. Resolve through the key registry. Only 'vault:<name>' is resolvable from
  --    inside the database; 'env:<NAME>' is by definition not visible here.
  SELECT k.secret_ref INTO v_ref
    FROM ottoq_signing_keys k
   WHERE k.key_id = p_key_id
     AND k.is_active
   LIMIT 1;

  IF v_ref IS NOT NULL AND v_ref LIKE 'vault:%' THEN
    BEGIN
      SELECT s.decrypted_secret INTO v_secret
        FROM vault.decrypted_secrets s
       WHERE s.name = substring(v_ref FROM 7)
       LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      -- Vault unreadable for this role: fall through to NULL rather than break
      -- event recording. Recording must never fail because signing failed.
      v_secret := NULL;
    END;

    IF v_secret IS NOT NULL AND length(v_secret) > 0 THEN
      -- Cache for the rest of this session so the hot writer does not decrypt
      -- once per event. Session-scoped, so it survives per-tick COMMITs.
      PERFORM set_config(v_guc_name, v_secret, false);
      RETURN v_secret;
    END IF;
  END IF;

  -- 4. No secret available: signing is skipped, the event is still recorded.
  RETURN NULL;
END;
$function$


-- ===== ottoq_resume_run =====
CREATE OR REPLACE FUNCTION public.ottoq_resume_run(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run ottoq_sim_runs%ROWTYPE; v_paused_at timestamptz; v_paused_s numeric;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
  IF v_run.status <> 'paused' THEN
    RETURN jsonb_build_object('ok', true, 'noop', true, 'status', v_run.status,
                              'note', 'run was not paused');
  END IF;

  v_paused_at := (v_run.payload->>'paused_at')::timestamptz;
  v_paused_s  := GREATEST(0, EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_paused_at, clock_timestamp()))));

  -- ⭐ RE-ANCHOR THE LIVE CLOCK. Without this the first tick after resume advances the
  -- sim clock by the entire paused interval (see migration comment).
  UPDATE ottoq_sim_runs
     SET status = 'running',
         last_tick_at = clock_timestamp(),
         next_tick_due_at = now(),
         payload = (COALESCE(payload,'{}'::jsonb) - 'paused_at' - 'pause_reason')
                   || jsonb_build_object('last_pause_seconds', round(v_paused_s, 2))
   WHERE sim_run_id = p_sim_run_id;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'otto_twin',
    p_event_type := 'twin.sim_run_resumed', p_entity_type := 'sim_run',
    p_entity_id := p_sim_run_id, p_depot_id := v_run.depot_id,
    p_payload := jsonb_build_object('paused_seconds', round(v_paused_s, 2),
                                    'sim_clock_resumed_at', v_run.sim_clock_current),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
    p_sim_run_id := p_sim_run_id);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'status', 'running',
    'resumed_at_sim_clock', v_run.sim_clock_current,
    'paused_real_seconds', round(v_paused_s, 2),
    'clock_reanchored', true);
END;
$function$


-- ===== ottoq_retention_purge_worker =====
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_worker(IN p_time_budget_s integer DEFAULT 75, IN p_micro_batch integer DEFAULT 2000, IN p_keep interval DEFAULT '48:00:00'::interval)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_cut   timestamptz := now() - p_keep;
  v_t0    timestamptz := clock_timestamp();
  v_n     bigint;
  v_round bigint;
  v_total bigint := 0;
BEGIN
  -- forward-compatible resolution without a SET clause (see migration notes):
  -- a routine with SET cannot COMMIT, and these procedures commit per iteration.
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);
  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running — skipped';
    RETURN;
  END IF;

  LOOP
    EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
    v_round := 0;
    PERFORM set_config('ottoq.retention', 'on', true);  -- re-arm each txn (COMMIT resets it)

    DELETE FROM public.ottoq_events WHERE event_id IN (
      SELECT event_id FROM public.ottoq_events WHERE occurred_at < v_cut LIMIT p_micro_batch);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_round := v_round + v_n;

    DELETE FROM public.ottoq_rule_evaluations WHERE evaluation_id IN (
      SELECT evaluation_id FROM public.ottoq_rule_evaluations WHERE evaluated_at < v_cut LIMIT p_micro_batch);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_round := v_round + v_n;

    DELETE FROM public.ottoq_incident_reports WHERE incident_report_id IN (
      SELECT incident_report_id FROM public.ottoq_incident_reports WHERE triggered_at < v_cut LIMIT p_micro_batch);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_round := v_round + v_n;

    COMMIT;
    v_total := v_total + v_round;

    IF v_round = 0 THEN
      PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'ottoq-retention-backlog';
      COMMIT;
      EXIT;
    END IF;
  END LOOP;

  RAISE NOTICE 'retention purge: % rows deleted this call', v_total;
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$


-- ===== ottoq_retention_purge_worker =====
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_worker(IN p_time_budget_s integer DEFAULT 60, IN p_micro_batch integer DEFAULT 2000, IN p_keep interval DEFAULT '48:00:00'::interval, IN p_tables text[] DEFAULT ARRAY['ottoq_events'::text])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_cut     timestamptz := now() - p_keep;
  v_t0      timestamptz := clock_timestamp();
  v_n       bigint;
  v_total   bigint := 0;
  v_blk     bigint;
  v_max_blk bigint;
  v_window  bigint := 15000;   -- ~120MB of heap per statement, bounded IO
  v_wrapped boolean;
BEGIN
  -- forward-compatible resolution without a SET clause (see migration notes):
  -- a routine with SET cannot COMMIT, and these procedures commit per iteration.
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);
  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running — skipped';
    RETURN;
  END IF;

  -- EVENTS: forward-only block-cursor walk.
  IF 'ottoq_events' = ANY(p_tables) THEN
    v_max_blk := pg_relation_size('public.ottoq_events') / 8192;
    SELECT cursor_block INTO v_blk FROM public.ottoq_retention_state WHERE table_name = 'ottoq_events';

    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);

      DELETE FROM public.ottoq_events WHERE ctid IN (
        SELECT ctid FROM public.ottoq_events
         WHERE ctid >= format('(%s,0)', v_blk)::tid
           AND ctid <  format('(%s,0)', LEAST(v_blk + v_window, v_max_blk + 1))::tid
           AND occurred_at < v_cut
         LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      v_wrapped := false;

      IF v_n < p_micro_batch THEN
        -- window exhausted → advance; wrap to 0 at the end of the heap
        v_blk := v_blk + v_window;
        IF v_blk > v_max_blk THEN
          v_blk := 0;
          v_wrapped := true;
        END IF;
      END IF;

      UPDATE public.ottoq_retention_state
         SET cursor_block = v_blk,
             pass_deleted = CASE WHEN v_wrapped THEN 0 ELSE pass_deleted + v_n END,
             updated_at = now()
       WHERE table_name = 'ottoq_events';

      -- a full wrap with nothing deleted the whole pass → backlog drained
      IF v_wrapped AND v_total = 0
         AND (SELECT pass_deleted FROM public.ottoq_retention_state WHERE table_name='ottoq_events') = 0 THEN
        PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'ottoq-retention-backlog';
        COMMIT;
        EXIT;
      END IF;

      COMMIT;  -- each window's work is permanent regardless of later failures
    END LOOP;
  END IF;

  -- Bloated small tables (rule_evaluations / incident_reports) stay parked
  -- until their VACUUM FULL compaction is authorized; simple scans there
  -- exceed the cron statement cap.
  IF 'ottoq_rule_evaluations' = ANY(p_tables) THEN
    PERFORM set_config('ottoq.retention', 'on', true);
    DELETE FROM public.ottoq_rule_evaluations WHERE evaluation_id IN (
      SELECT evaluation_id FROM public.ottoq_rule_evaluations WHERE evaluated_at < v_cut LIMIT p_micro_batch);
    COMMIT;
  END IF;
  IF 'ottoq_incident_reports' = ANY(p_tables) THEN
    PERFORM set_config('ottoq.retention', 'on', true);
    DELETE FROM public.ottoq_incident_reports WHERE incident_report_id IN (
      SELECT incident_report_id FROM public.ottoq_incident_reports WHERE triggered_at < v_cut LIMIT p_micro_batch);
    COMMIT;
  END IF;

  RAISE NOTICE 'retention purge: % rows deleted this call', v_total;
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$


-- ===== ottoq_return_eta_minutes =====
CREATE OR REPLACE FUNCTION public.ottoq_return_eta_minutes(p_vehicle_id uuid, p_depot_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id, 'return_eta_minutes', 30), 30));
$function$


-- ===== ottoq_role_rank =====
CREATE OR REPLACE FUNCTION public.ottoq_role_rank(p_role text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT CASE p_role
    WHEN 'command_center_operator' THEN 3
    WHEN 'depot_supervisor'        THEN 2
    WHEN 'depot_tech'              THEN 1
    ELSE 0 END;
$function$

-- ===== ottoq_run_blackbox =====
CREATE OR REPLACE FUNCTION public.ottoq_run_blackbox(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_meta jsonb; v_code jsonb; v_data jsonb := '{}'::jsonb; v_tbl text; v_rows jsonb; v_depot uuid;
BEGIN
  PERFORM set_config('statement_timeout', '150000', true);  -- export can take a moment to assemble; give it room
  SELECT to_jsonb(r), r.depot_id INTO v_meta, v_depot FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_meta IS NULL THEN RETURN jsonb_build_object('error','run not found','sim_run_id',p_sim_run_id); END IF;

  SELECT jsonb_object_agg(proname, pg_get_functiondef(oid)) INTO v_code
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname ~ '^ottoq_(sim_|decide_tick|greedy_tick|fifo_tick|manual_tick|l2_|cuopt_|energy_orchestrate|orchestrator_trigger|apply_ops_action|demo_metronome|deploy_target|policy_get|policy_set|shield|plan_visit|itin_leg|mark_visit|record_event|active_charge_cap|deploy_target_fraction|run_blackbox|sim_stop_and_reset)';

  FOR v_tbl IN
    SELECT table_name FROM information_schema.columns
     WHERE table_schema='public' AND column_name='sim_run_id' AND table_name LIKE 'ottoq%'
     ORDER BY table_name
  LOOP
    BEGIN
      EXECUTE format('SELECT jsonb_agg(to_jsonb(t)) FROM (SELECT * FROM public.%I WHERE sim_run_id=$1 LIMIT 200000) t', v_tbl)
        INTO v_rows USING p_sim_run_id;
      v_data := v_data || jsonb_build_object(v_tbl, COALESCE(v_rows, '[]'::jsonb));
    EXCEPTION WHEN OTHERS THEN
      v_data := v_data || jsonb_build_object(v_tbl, jsonb_build_object('_export_error', SQLERRM));
    END;
  END LOOP;

  v_data := v_data || jsonb_build_object('vehicles',
    COALESCE((SELECT jsonb_agg(to_jsonb(v)) FROM vehicles v WHERE v.owning_sim_run_id = p_sim_run_id OR v.current_depot_id = v_depot), '[]'::jsonb));
  v_data := v_data || jsonb_build_object('stalls',
    COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM stalls s WHERE s.depot_id = v_depot), '[]'::jsonb));
  v_data := v_data || jsonb_build_object('ocpp_sessions',
    COALESCE((SELECT jsonb_agg(to_jsonb(o)) FROM ocpp_sessions o WHERE o.depot_id = v_depot AND o.started_at >= (v_meta->>'started_at')::timestamptz), '[]'::jsonb));

  RETURN jsonb_build_object(
    'black_box_version', '1.0', 'generated_at', now(), 'sim_run_id', p_sim_run_id, 'run', v_meta,
    'edge_fn_ai_sources', jsonb_build_object('_note','AI seam code lives in the edge-function store, not pg_proc',
       'cuopt','ottoq-cuopt-propose','nemotron_conductor','ottoq-orchestrator-agent'),
    'executed_code', v_code, 'data', v_data);
END;
$function$


-- ===== ottoq_run_blackbox_meta =====
CREATE OR REPLACE FUNCTION public.ottoq_run_blackbox_meta(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'black_box_version','1.0','generated_at',now(),'sim_run_id',p_sim_run_id,
    'run', (SELECT to_jsonb(r) FROM ottoq_sim_runs r WHERE r.sim_run_id=p_sim_run_id),
    'depot_id', (SELECT depot_id FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id),
    'executed_code', (SELECT jsonb_object_agg(proname, pg_get_functiondef(oid)) FROM pg_proc
       WHERE pronamespace='public'::regnamespace
         AND proname ~ '^ottoq_(sim_|decide_tick|greedy_tick|fifo_tick|manual_tick|l2_|cuopt_|energy_orchestrate|orchestrator_trigger|apply_ops_action|demo_metronome|deploy_target|policy_get|policy_set|shield|plan_visit|itin_leg|mark_visit|record_event|active_charge_cap|deploy_target_fraction|run_blackbox|sim_stop_and_reset)'),
    'data_tables', (SELECT jsonb_agg(table_name ORDER BY table_name) FROM information_schema.columns
       WHERE table_schema='public' AND column_name='sim_run_id' AND table_name LIKE 'ottoq%'),
    'edge_fn_ai_sources', jsonb_build_object('cuopt','ottoq-cuopt-propose','nemotron_conductor','ottoq-orchestrator-agent')
  );
$function$


-- ===== ottoq_run_boot_draw =====
CREATE OR REPLACE FUNCTION public.ottoq_run_boot_draw(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run   ottoq_sim_runs%ROWTYPE;
  v_seed  bigint;
  v_n     int := 0;
  v_world jsonb := '{}'::jsonb;
  v_key   text;
  v_manifest jsonb;
  v_t0    timestamptz := clock_timestamp();
  v_profiles jsonb := jsonb_build_object('ok', false, 'skipped', true);
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
  v_seed := COALESCE(v_run.random_seed, 42);

  -- ---- 1. PER-VEHICLE CONDITION DRAW (config = hot-loop truth; cards = provenance)
  WITH fleet AS (
    SELECT v.id
      FROM vehicles v
     WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous' AND v.is_active
  ), draws AS (
    SELECT id,
      round((88 + 12 * (1 - power(ottoq_sim_seeded_random(v_seed, 'veh_soh:'    || id::text), 2)))::numeric, 1) AS soh,
      round((0.88 + 0.30 * ottoq_sim_seeded_random(v_seed, 'veh_cons:'          || id::text))::numeric, 3)      AS cons,
      round((0.85 + 0.25 * ottoq_sim_seeded_random(v_seed, 'veh_curve:'         || id::text))::numeric, 3)      AS curve,
      round((0.5 + 1.5 * power(ottoq_sim_seeded_random(v_seed, 'veh_soil:'      || id::text), 2))::numeric, 3)  AS soil,
      round((6500 + 3000 * ottoq_sim_seeded_random(v_seed, 'veh_pm:'            || id::text))::numeric, 0)      AS pm_km,
      round((180 + 140 * ottoq_sim_seeded_random(v_seed, 'veh_calib:'           || id::text))::numeric, 0)      AS calib_h,
      round((0.80 + 0.45 * ottoq_sim_seeded_random(v_seed, 'veh_svcspd:'        || id::text))::numeric, 3)      AS svcspd,
      (2 + floor(3 * ottoq_sim_seeded_random(v_seed, 'veh_washcad:'             || id::text)))::int             AS washcad,
      ottoq_sim_seeded_random(v_seed, 'veh_washphase:' || id::text)                                             AS washphase
    FROM fleet
  ), cfg AS (
    UPDATE vehicles v SET config = COALESCE(v.config, '{}'::jsonb) || jsonb_build_object(
        'battery_soh_pct',      d.soh,
        'consumption_scalar',   d.cons,
        'charge_curve_scalar',  d.curve,
        'soil_rate',            d.soil,
        'pm_interval_km',       d.pm_km,
        'calib_interval_h',     d.calib_h,
        'service_speed_scalar', d.svcspd,
        'wash_cadence_cycles',  d.washcad,
        'cycles_since_wash',    floor(d.washcad * d.washphase)::int,
        'condition_drawn_run',  p_sim_run_id::text)
      FROM draws d WHERE v.id = d.id
      RETURNING v.id, d.soh, d.cons, d.curve, d.soil, d.pm_km, d.calib_h, d.svcspd, d.washcad
  ), cards AS (
    INSERT INTO ottoq_variability_cards
      (sim_run_id, var_key, scope_instance, lifespan, bucket_key, value, drawn_at_clock, drawn_at_tick)
    SELECT p_sim_run_id, x.k, c.id::text, 'run', 'run', x.val, v_run.sim_clock_start, 0
      FROM cfg c CROSS JOIN LATERAL (VALUES
        ('veh_battery_soh_pct',      c.soh),
        ('veh_consumption_scalar',   c.cons),
        ('veh_charge_curve_scalar',  c.curve),
        ('veh_soil_rate',            c.soil),
        ('veh_pm_interval_km',       c.pm_km),
        ('veh_calib_interval_h',     c.calib_h),
        ('veh_service_speed_scalar', c.svcspd),
        ('veh_wash_cadence_cycles',  c.washcad::numeric)) AS x(k, val)
    ON CONFLICT (sim_run_id, var_key, scope_instance, bucket_key) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM cfg;

  -- ---- 1b. RICH PER-VEHICLE NEED PROFILE (energy / cleanliness / sensor+software /
  --          mechanical / operational commitment / items). Runs AFTER the condition draw
  --          so it inherits soh / soil_rate / pm_interval_km / calib_interval_h.
  --          Wrapped: a profile failure must NEVER abort a run boot.
  BEGIN
    v_profiles := ottoq_seed_vehicle_need_profiles(p_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    v_profiles := jsonb_build_object('ok', false, 'error', SQLERRM);
    RAISE WARNING 'boot_draw: need-profile seeding failed: %', SQLERRM;
  END;

  -- ---- 2. WORLD DAY-0 DRAW (every run/day/block world card dealt before tick 1)
  FOR v_key IN
    SELECT var_key FROM ottoq_variability_catalog
     WHERE lifespan IN ('run','day','block') AND COALESCE(scope,'') <> 'vehicle'
  LOOP
    BEGIN
      v_world := v_world || jsonb_build_object(v_key,
        ottoq_twin_deal(p_sim_run_id, v_key, 'global', v_run.sim_clock_start,
                        (v_run.sim_clock_start::date - DATE '2020-01-01'), 0, 'global'));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- ---- 3. THE BOOT MANIFEST (loading-screen + Black Box content)
  SELECT jsonb_build_object(
    'ok', true, 'drawn_at', now(), 'seed', v_seed, 'vehicles_drawn', v_n,
    'draw_ms', round(EXTRACT(epoch FROM (clock_timestamp() - v_t0)) * 1000),
    'need_profiles', v_profiles,
    'world_day0', v_world,
    'fleet_condition', (
      SELECT jsonb_object_agg(k, jsonb_build_object('min', mn, 'avg', av, 'max', mx))
      FROM (
        SELECT var_key AS k, round(min(value),2) AS mn, round(avg(value),2) AS av, round(max(value),2) AS mx
          FROM ottoq_variability_cards
         WHERE sim_run_id = p_sim_run_id AND var_key LIKE 'veh\_%' ESCAPE '\'
         GROUP BY var_key) s))
  INTO v_manifest;

  UPDATE ottoq_sim_runs
     SET payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('boot_draw', v_manifest)
   WHERE sim_run_id = p_sim_run_id;

  RETURN v_manifest;
END;
$function$


-- ===== ottoq_run_policy_to_end =====
CREATE OR REPLACE FUNCTION public.ottoq_run_policy_to_end(p_sim_run_id uuid, p_max_ticks integer DEFAULT 48)
 RETURNS TABLE(ticks_run integer, completed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_done boolean := false; v_i int := 0; v_tick bigint;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN QUERY SELECT 0, true; RETURN; END IF;
  WHILE v_i < p_max_ticks AND NOT v_done LOOP
    SELECT out_completed INTO v_done FROM ottoq_sim_advance_tick(p_sim_run_id);  -- tick now self-heartbeats
    v_i := v_i + 1;
  END LOOP;
  SELECT tick_count INTO v_tick FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  PERFORM ottoq_capture_decision_snapshot(p_sim_run_id, 1000000000::bigint + v_tick, v_depot,
            (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id));
  RETURN QUERY SELECT v_i, v_done;
END;
$function$


-- ===== ottoq_safety_cert_arm =====
CREATE OR REPLACE PROCEDURE public.ottoq_safety_cert_arm(IN p_run uuid, IN p_seed bigint, IN p_ab_group uuid, IN p_ticks integer, IN p_start timestamp with time zone, IN p_drain_frac numeric DEFAULT 0.65)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $procedure$
DECLARE i int; v_wseed bigint; d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 90);
  UPDATE ottoq_bess_units SET current_soc_pct=90, current_soc_kwh=capacity_kwh*0.9, current_power_kw=0, current_temperature_c=25 WHERE depot_id=d;
  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'safety', 23));
  -- drained fleet: p_drain_frac below the 80% floor (55-79%), the rest safe (85-95%), all staged & ready
  UPDATE vehicles SET
    current_soc = CASE WHEN ottoq_sim_seeded_random(v_wseed,'drain:'||id::text) < p_drain_frac
                       THEN 55 + ottoq_sim_seeded_random(v_wseed,'lo:'||id::text)*24
                       ELSE 85 + ottoq_sim_seeded_random(v_wseed,'hi:'||id::text)*10 END,
    target_soc = 90, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=p_start
   WHERE home_depot_id=d AND category='autonomous';
  INSERT INTO ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES (p_run, 'ef24648f-eaf6-4686-bd07-1e018a8224ab','normal_day', p_start, p_start, p_start + interval '24 hours',
    d, 60, 30, 'running', 'otto_q', 'benchmark', 0, p_seed, p_ab_group, p_start, p_start, p_start);
  FOR i IN 1..p_ticks LOOP
    PERFORM ottoq_sim_advance_and_snapshot(p_run);
    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) <> 'running';
  END LOOP;
  PERFORM ottoq_score_run(p_run);
  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=p_run;
END $procedure$


-- ===== ottoq_sample_calibrated =====
CREATE OR REPLACE FUNCTION public.ottoq_sample_calibrated(p_variable_name text, p_segment text DEFAULT 'global'::text, p_seed bigint DEFAULT 42, p_salt text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_dist        ottoq_calibration_distributions%ROWTYPE;
  v_u           NUMERIC;
  v_pos         NUMERIC;
  v_idx_low     INTEGER;
  v_idx_high    INTEGER;
  v_frac        NUMERIC;
  v_val_low     NUMERIC;
  v_val_high    NUMERIC;
  v_result      NUMERIC;
  v_salt        TEXT;
BEGIN
  v_salt := COALESCE(p_salt, p_variable_name || ':' || p_segment);

  -- 1. Resolve distribution (exact segment, then 'global' fallback)
  SELECT * INTO v_dist
    FROM ottoq_calibration_distributions
   WHERE variable_name = p_variable_name
     AND segment = p_segment
   LIMIT 1;

  IF NOT FOUND THEN
    SELECT * INTO v_dist
      FROM ottoq_calibration_distributions
     WHERE variable_name = p_variable_name
       AND segment = 'global'
     LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    -- No calibration data for this variable — return NULL so the caller
    -- knows to fall back (and ideally logs a calibration gap).
    RETURN NULL;
  END IF;

  -- 2. Deterministic uniform draw
  v_u := ottoq_sim_seeded_random(p_seed, v_salt);

  -- 3. Map onto the 101-point quantile grid (indices 1..101 in PG arrays)
  v_pos      := v_u * 100.0;            -- 0..100
  v_idx_low  := floor(v_pos)::INTEGER;  -- 0..100
  v_idx_high := LEAST(v_idx_low + 1, 100);
  v_frac     := v_pos - v_idx_low;

  v_val_low  := v_dist.quantile_grid[v_idx_low + 1];   -- PG arrays 1-indexed
  v_val_high := v_dist.quantile_grid[v_idx_high + 1];
  v_result   := v_val_low + (v_val_high - v_val_low) * v_frac;

  -- 4. Clamp to physical bounds
  IF v_dist.hard_min IS NOT NULL THEN v_result := GREATEST(v_result, v_dist.hard_min); END IF;
  IF v_dist.hard_max IS NOT NULL THEN v_result := LEAST(v_result, v_dist.hard_max); END IF;

  RETURN v_result;
END;
$function$


-- ===== ottoq_sample_shaped =====
CREATE OR REPLACE FUNCTION public.ottoq_sample_shaped(p_sim_run_id uuid, p_var text, p_segment text, p_seed bigint, p_salt text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_raw NUMERIC;
BEGIN
  v_raw := ottoq_sample_calibrated(p_var, p_segment, p_seed, p_salt);
  IF v_raw IS NULL THEN RETURN NULL; END IF;
  RETURN ottoq_apply_profile(p_sim_run_id, p_var, v_raw);
END;
$function$


-- ===== ottoq_scenario_apply_fleet_overrides =====
CREATE OR REPLACE FUNCTION public.ottoq_scenario_apply_fleet_overrides(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run     ottoq_sim_runs%ROWTYPE;
  v_fo      jsonb; v_pol jsonb; v_veh jsonb; v_phase jsonb;
  v_k       text;  v_applied jsonb := '{}'::jsonb;
  v_pm      numeric; v_cal numeric;
  v_scaled  int := 0; v_wear int := 0;
  v_seed    bigint; v_soil_thresh numeric; v_soil_max numeric;
  v_receipt jsonb;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'run not found'); END IF;
  v_seed := COALESCE(v_run.random_seed, 42);

  SELECT s.fleet_overrides INTO v_fo
    FROM ottoq_sim_scenarios s WHERE s.scenario_code = v_run.scenario_code;
  v_fo    := COALESCE(v_fo, '{}'::jsonb);
  v_pol   := COALESCE(v_fo->'policy_overrides',  '{}'::jsonb);
  v_veh   := COALESCE(v_fo->'vehicle_overrides', '{}'::jsonb);
  v_phase := COALESCE(v_fo->'wear_phase',        '{}'::jsonb);

  -- (1) RUN-SCOPED policy. Run scope is checked first by ottoq_policy_get, so this
  --     overrides depot defaults for THIS run only; other scenarios are untouched.
  FOR v_k IN SELECT jsonb_object_keys(v_pol) LOOP
    BEGIN
      PERFORM ottoq_policy_set('run', p_sim_run_id, v_k, (v_pol->>v_k)::numeric, 'scenario_loader');
      v_applied := v_applied || jsonb_build_object(v_k, (v_pol->>v_k)::numeric);
    EXCEPTION WHEN OTHERS THEN
      v_applied := v_applied || jsonb_build_object(v_k, 'ERROR: '||SQLERRM);
    END;
  END LOOP;

  -- (2) Per-vehicle service intervals. IDEMPOTENT BY CONSTRUCTION: the scale is
  --     applied to the UNSCALED draw held in ottoq_variability_cards, never to the
  --     current config value, so calling this twice cannot compound (the old
  --     wrapper multiplied config in place, which is why a stale marker survived a
  --     run that never scaled anything).
  v_pm  := COALESCE((v_veh->>'pm_interval_km_scale')::numeric, 1);
  v_cal := COALESCE((v_veh->>'calib_interval_h_scale')::numeric, 1);
  IF v_pm <> 1 OR v_cal <> 1 THEN
    WITH base AS (
      SELECT c.scope_instance::uuid AS vid,
             max(c.value) FILTER (WHERE c.var_key = 'veh_pm_interval_km')   AS pm_raw,
             max(c.value) FILTER (WHERE c.var_key = 'veh_calib_interval_h') AS cal_raw
        FROM ottoq_variability_cards c
       WHERE c.sim_run_id = p_sim_run_id
         AND c.var_key IN ('veh_pm_interval_km','veh_calib_interval_h')
       GROUP BY 1
    ), tgt AS (
      SELECT v.id,
             COALESCE(b.pm_raw,  (v.config->>'pm_interval_km')::numeric,   8000) AS pm_raw,
             COALESCE(b.cal_raw, (v.config->>'calib_interval_h')::numeric,  250) AS cal_raw,
             (b.pm_raw IS NOT NULL) AS from_card
        FROM vehicles v
        LEFT JOIN base b ON b.vid = v.id
       WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous'
    )
    UPDATE vehicles v
       SET config = (COALESCE(v.config,'{}'::jsonb) - 'busy_day_interval_scale')
                 || jsonb_build_object(
                      'pm_interval_km',   GREATEST(1, round(t.pm_raw  * v_pm)),
                      'calib_interval_h', GREATEST(1, round(t.cal_raw * v_cal, 1)),
                      'scenario_interval_scale', jsonb_build_object(
                        'scenario',      v_run.scenario_code,
                        'run',           p_sim_run_id::text,
                        'pm_km_scale',   v_pm,
                        'calib_h_scale', v_cal,
                        'basis', CASE WHEN t.from_card THEN 'unscaled_variability_card'
                                      ELSE 'config_fallback' END))
      FROM tgt t
     WHERE v.id = t.id;
    GET DIAGNOSTICS v_scaled = ROW_COUNT;
  ELSE
    -- no scaling asked for: strip any stale marker so config can never lie again
    UPDATE vehicles v
       SET config = COALESCE(v.config,'{}'::jsonb) - 'busy_day_interval_scale' - 'scenario_interval_scale'
     WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous'
       AND (v.config ? 'busy_day_interval_scale' OR v.config ? 'scenario_interval_scale');
  END IF;

  -- (3) WEAR PHASE OFFSETS -- this is what turns a THUNDERING HERD into a SUSTAINED
  --     stream. Without it every vehicle starts its PM / calibration / soil clock at
  --     zero, so with a short interval the whole fleet comes due in the same handful
  --     of ticks (the phase-3 front-loaded burst) and the depot is empty afterwards.
  --     Seeding each vehicle at a uniformly-random point in its own cycle spreads
  --     due-times evenly across the first cycle, and the cycle re-spreads naturally
  --     after that. Opt-in per scenario, so normal_day is bit-for-bit unaffected.
  IF COALESCE((v_phase->>'enabled')::boolean, false) THEN
    v_soil_thresh := COALESCE(ottoq_policy_get(p_sim_run_id, 'sensor_soil_threshold', 0.35), 0.35);
    v_soil_max    := COALESCE((v_phase->>'soil_seed_fraction')::numeric, 0.85) * v_soil_thresh;

    INSERT INTO ottoq_vehicle_wear (
      vehicle_id, sim_run_id, drive_km_total, drive_hours_total,
      km_at_last_pm, hours_at_last_calibration, soil_index,
      worst_open_dtc_rank, last_advanced_tick, last_advanced_sim_clock)
    SELECT v.id, p_sim_run_id, 0, 0,
           -- negative "km at last PM" == "already this far into the PM cycle at t0"
           -1 * round(ottoq_sim_seeded_random(v_seed, 'pmphase:'   || v.id::text)
                      * COALESCE((v.config->>'pm_interval_km')::numeric, 8000), 3),
           -1 * round(ottoq_sim_seeded_random(v_seed, 'calphase:'  || v.id::text)
                      * COALESCE((v.config->>'calib_interval_h')::numeric, 250), 4),
           round(ottoq_sim_seeded_random(v_seed, 'soilphase:' || v.id::text) * v_soil_max, 4),
           99, -1, v_run.sim_clock_start
      FROM vehicles v
     WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous'
    ON CONFLICT (vehicle_id, sim_run_id) DO NOTHING;
    GET DIAGNOSTICS v_wear = ROW_COUNT;
  END IF;

  v_receipt := jsonb_build_object(
    'ok', true, 'scenario', v_run.scenario_code, 'seed', v_seed,
    'policy_applied', v_applied,
    'vehicles_scaled', v_scaled,
    'pm_km_scale', v_pm, 'calib_h_scale', v_cal,
    'wear_rows_phased', v_wear,
    'wear_phase_enabled', COALESCE((v_phase->>'enabled')::boolean, false),
    'applied_at', now());

  UPDATE ottoq_sim_runs
     SET payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object('scenario_overrides', v_receipt)
   WHERE sim_run_id = p_sim_run_id;

  BEGIN
    PERFORM ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_actor_id := 'scenario_loader',
      p_event_type := 'twin.scenario_overrides_applied', p_entity_type := 'system',
      p_payload := v_receipt, p_severity := 'info',
      p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_receipt;
END;
$function$


-- ===== ottoq_schedule_tasks_state_change =====
CREATE OR REPLACE FUNCTION public.ottoq_schedule_tasks_state_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_payload      JSONB;
  v_diff         JSONB;
  v_actor_type   TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
  v_actor_id     TEXT := NULLIF(current_setting('ottoq.actor_id', TRUE), '');
  v_event_type   TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_event_type := 'task.created';
    PERFORM ottoq_record_event(
      p_actor_type        := v_actor_type,
      p_actor_id          := v_actor_id,
      p_event_type        := v_event_type,
      p_entity_type       := 'task',
      p_entity_id         := NEW.id,
      p_related_task_id   := NEW.id,
      p_payload           := jsonb_build_object('new', to_jsonb(NEW)),
      p_new_state         := to_jsonb(NEW),
      p_ingest_source     := 'trigger'
    );
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF to_jsonb(OLD) = to_jsonb(NEW) THEN RETURN NEW; END IF;
    v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
    -- Skip pure-timestamp churn. Conservative: ONLY updated_at. Every domain
    -- timestamp (oem_accepted_at, tech_override_at, ...) still emits an event.
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_object_keys(v_diff) AS k
       WHERE k <> ALL (ARRAY['updated_at'])
    ) THEN
      RETURN NEW;
    END IF;
    v_event_type := 'task.state_changed';
    v_payload := jsonb_build_object('diff', v_diff);
    PERFORM ottoq_record_event(
      p_actor_type        := v_actor_type,
      p_actor_id          := v_actor_id,
      p_event_type        := v_event_type,
      p_entity_type       := 'task',
      p_entity_id         := NEW.id,
      p_related_task_id   := NEW.id,
      p_payload           := v_payload,
      p_new_state         := to_jsonb(NEW),
      p_ingest_source     := 'trigger'
    );
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$function$


-- ===== ottoq_score_observation =====
CREATE OR REPLACE FUNCTION public.ottoq_score_observation(p_detector_code text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_observed_value jsonb DEFAULT NULL::jsonb, p_observed_numeric numeric DEFAULT NULL::numeric, p_observed_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_detector       ottoq_anomaly_detectors%ROWTYPE;
  v_observation_id UUID := gen_random_uuid();
  v_score          NUMERIC := 0;
  v_is_anomaly     BOOLEAN := FALSE;
  v_severity       TEXT := 'info';
  v_event_id       UUID;
  v_context        JSONB;
  v_correlation    UUID;
  v_observed_at    TIMESTAMPTZ := COALESCE(p_observed_at, NOW());
  -- threshold params
  v_low            NUMERIC;
  v_high           NUMERIC;
  -- z_score params
  v_window_size    INTEGER;
  v_z_threshold    NUMERIC;
  v_mean           NUMERIC;
  v_stddev         NUMERIC;
  v_z              NUMERIC;
  -- iqr params
  v_iqr_mult       NUMERIC;
  v_q1             NUMERIC;
  v_q3             NUMERIC;
BEGIN
  SELECT * INTO v_detector
    FROM ottoq_anomaly_detectors
   WHERE detector_code = p_detector_code AND status IN ('active','shadow');
  IF NOT FOUND THEN
    -- Unknown detector — log catalog miss, return NULL
    PERFORM ottoq_record_event(
      p_actor_type := 'ottoq_engine',
      p_event_type := 'system.catalog_miss',
      p_entity_type := 'anomaly_detector',
      p_payload := jsonb_build_object('unknown_detector_code', p_detector_code),
      p_severity := 'warning'
    );
    RETURN NULL;
  END IF;

  v_context := p_context;
  v_correlation := NULLIF(current_setting('ottoq.correlation_id', TRUE), '')::UUID;

  -- Method dispatch
  CASE v_detector.method

    WHEN 'threshold' THEN
      v_low  := (v_detector.parameters ->> 'low')::NUMERIC;
      v_high := (v_detector.parameters ->> 'high')::NUMERIC;
      IF p_observed_numeric IS NOT NULL THEN
        IF (v_low IS NOT NULL AND p_observed_numeric < v_low)
           OR (v_high IS NOT NULL AND p_observed_numeric > v_high) THEN
          v_score := 1.0;
          v_is_anomaly := TRUE;
        END IF;
        v_context := v_context || jsonb_build_object('low', v_low, 'high', v_high, 'observed', p_observed_numeric);
      END IF;

    WHEN 'z_score' THEN
      v_window_size := COALESCE((v_detector.parameters ->> 'window_size')::INTEGER, 100);
      v_z_threshold := COALESCE((v_detector.parameters ->> 'score_threshold')::NUMERIC, 3.0);
      -- Compute mean + stddev over recent observations
      SELECT avg(observed_value::text::numeric)::NUMERIC,
             COALESCE(stddev_samp(observed_value::text::numeric), 0)
        INTO v_mean, v_stddev
        FROM (
          SELECT observed_value FROM ottoq_anomaly_observations
           WHERE detector_id = v_detector.detector_id
             AND entity_type = p_entity_type
             AND (p_entity_id IS NULL OR entity_id = p_entity_id)
             AND observed_value IS NOT NULL
           ORDER BY observed_at DESC LIMIT v_window_size
        ) recent;
      IF v_stddev IS NULL OR v_stddev = 0 THEN
        v_z := 0;
      ELSE
        v_z := abs((p_observed_numeric - COALESCE(v_mean, p_observed_numeric)) / v_stddev);
      END IF;
      -- Normalize to 0..1 (capped at 1.0)
      v_score := LEAST(v_z / (v_z_threshold * 2.0), 1.0);
      v_is_anomaly := v_z >= v_z_threshold;
      v_context := v_context || jsonb_build_object('mean', v_mean, 'stddev', v_stddev, 'z', v_z, 'threshold', v_z_threshold);

    WHEN 'iqr' THEN
      v_window_size := COALESCE((v_detector.parameters ->> 'window_size')::INTEGER, 50);
      v_iqr_mult    := COALESCE((v_detector.parameters ->> 'iqr_multiplier')::NUMERIC, 1.5);
      SELECT percentile_cont(0.25) WITHIN GROUP (ORDER BY (observed_value::text::numeric)),
             percentile_cont(0.75) WITHIN GROUP (ORDER BY (observed_value::text::numeric))
        INTO v_q1, v_q3
        FROM (
          SELECT observed_value FROM ottoq_anomaly_observations
           WHERE detector_id = v_detector.detector_id
             AND entity_type = p_entity_type
             AND (p_entity_id IS NULL OR entity_id = p_entity_id)
             AND observed_value IS NOT NULL
           ORDER BY observed_at DESC LIMIT v_window_size
        ) recent;
      IF v_q1 IS NULL OR v_q3 IS NULL THEN
        v_score := 0;
      ELSE
        v_low := v_q1 - (v_q3 - v_q1) * v_iqr_mult;
        v_high := v_q3 + (v_q3 - v_q1) * v_iqr_mult;
        IF p_observed_numeric < v_low OR p_observed_numeric > v_high THEN
          v_score := 1.0; v_is_anomaly := TRUE;
        END IF;
      END IF;
      v_context := v_context || jsonb_build_object('q1', v_q1, 'q3', v_q3, 'mult', v_iqr_mult);

    ELSE
      -- ml_isoforest / ml_lstm / custom — populated when models deploy
      v_score := 0;
      v_context := v_context || jsonb_build_object('method', v_detector.method, 'note', 'method not yet implemented in pg layer; awaiting model deployment');
  END CASE;

  -- Severity mapping
  v_severity := CASE
    WHEN NOT v_is_anomaly THEN 'info'
    WHEN v_score >= v_detector.severity_critical_threshold THEN 'safety_critical'
    WHEN v_score >= v_detector.severity_high_threshold THEN 'critical'
    WHEN v_score >= v_detector.severity_low_threshold THEN 'warning'
    ELSE 'info'
  END;

  -- Insert observation
  INSERT INTO ottoq_anomaly_observations (
    observation_id, detector_id, detector_code, observed_at,
    entity_type, entity_id, feature_name, observed_value,
    anomaly_score, is_anomaly, severity, context,
    fleet_operator_id, depot_id, correlation_id
  ) VALUES (
    v_observation_id, v_detector.detector_id, v_detector.detector_code, v_observed_at,
    p_entity_type, p_entity_id, v_detector.target_feature, p_observed_value,
    v_score, v_is_anomaly, v_severity, v_context,
    p_fleet_operator_id, p_depot_id, v_correlation
  );

  -- Update detector stats
  UPDATE ottoq_anomaly_detectors
     SET observations_total = observations_total + 1,
         observations_anomalous = observations_anomalous + (CASE WHEN v_is_anomaly THEN 1 ELSE 0 END),
         last_observation_at = v_observed_at,
         last_anomaly_at = CASE WHEN v_is_anomaly THEN v_observed_at ELSE last_anomaly_at END
   WHERE detector_id = v_detector.detector_id;

  -- Emit safety event if anomalous + detector says so
  IF v_is_anomaly AND v_detector.emit_event THEN
    v_event_id := ottoq_record_event(
      p_actor_type        := 'ottoq_engine',
      p_event_type        := CASE
                               WHEN v_severity IN ('safety_critical','critical') THEN 'anomaly.critical_detected'
                               ELSE 'anomaly.detected'
                             END,
      p_entity_type       := p_entity_type,
      p_entity_id         := p_entity_id,
      p_fleet_operator_id := p_fleet_operator_id,
      p_depot_id          := p_depot_id,
      p_payload           := jsonb_build_object(
                              'detector_code', v_detector.detector_code,
                              'category', v_detector.category,
                              'anomaly_score', v_score,
                              'severity', v_severity,
                              'method', v_detector.method,
                              'context', v_context,
                              'observation_id', v_observation_id
                            ),
      p_severity          := v_severity,
      p_correlation_id    := v_correlation
    );
    UPDATE ottoq_anomaly_observations
       SET event_emitted = TRUE, linked_event_id = v_event_id
     WHERE observation_id = v_observation_id;
  END IF;

  RETURN v_observation_id;
END;
$function$


-- ===== ottoq_score_run =====
CREATE OR REPLACE FUNCTION public.ottoq_score_run(p_sim_run_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE; v_id uuid; v_total int; v_ready numeric;
  v_frame jsonb; v_breach RECORD; v_ov int; v_deployed int; v_veh jsonb;
  v_prod int; v_unsafe int;
  v_turned int; v_backlog int; v_run_hours numeric; v_cap numeric; v_peak numeric;
  v_trips int; v_cycled int; v_med numeric; v_ready_dep numeric;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL THEN RETURN NULL; END IF;

  SELECT frame INTO v_frame FROM ottoq_decision_snapshots
   WHERE sim_run_id = p_sim_run_id ORDER BY tick_seq DESC LIMIT 1;
  IF v_frame IS NULL THEN v_frame := ottoq_build_decision_frame(v_run.depot_id); END IF;
  v_veh := COALESCE(v_frame->'vehicles','[]'::jsonb);

  SELECT count(*) INTO v_total FROM jsonb_array_elements(v_veh);
  v_total := GREATEST(v_total,1);
  v_ready := 100.0 * (SELECT count(*) FROM jsonb_array_elements(v_veh) e WHERE e->>'state'='staged_for_departure')::numeric / v_total;
  v_deployed := (SELECT count(*) FROM jsonb_array_elements(v_veh) e WHERE e->>'state' IN ('deployed','en_route_to_deployment'));
  SELECT * INTO v_breach FROM ottoq_count_breaches_in_frame(v_frame, v_run.depot_id);
  SELECT COUNT(*) INTO v_ov FROM ottoq_decisions WHERE sim_run_id=p_sim_run_id AND overridden;
  SELECT COUNT(*) FILTER (WHERE dl.is_productive AND EXISTS (
             SELECT 1 FROM ottoq_vehicle_dispatches vd
              WHERE vd.sim_run_id = dl.sim_run_id AND vd.vehicle_id = dl.vehicle_id
                AND vd.dispatched_at >= dl.sim_clock - interval '2 minutes')),
         COUNT(*) FILTER (WHERE NOT dl.is_productive)
    INTO v_prod, v_unsafe FROM ottoq_deploy_log dl WHERE dl.sim_run_id = p_sim_run_id;

  v_turned  := (SELECT count(*) FROM jsonb_array_elements(v_veh) e WHERE e->>'state' IN ('staged_for_departure','en_route_to_deployment','service_complete_holding'));
  -- CUMULATIVE truth from durable dispatch records (never final-frame)
  SELECT COUNT(*), COUNT(DISTINCT d.vehicle_id) INTO v_trips, v_cycled
    FROM ottoq_vehicle_dispatches d
   WHERE d.sim_run_id = p_sim_run_id AND d.status='completed'
     AND d.actual_return_at >= v_run.sim_clock_start;
  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (nxt.dispatched_at - d.actual_return_at))/60.0)
    INTO v_med
    FROM ottoq_vehicle_dispatches d
    JOIN LATERAL (SELECT d2.dispatched_at FROM ottoq_vehicle_dispatches d2
                   WHERE d2.sim_run_id = d.sim_run_id AND d2.vehicle_id = d.vehicle_id
                     AND d2.dispatched_at > d.actual_return_at
                   ORDER BY d2.dispatched_at LIMIT 1) nxt ON true
   WHERE d.sim_run_id = p_sim_run_id AND d.status='completed' AND d.actual_return_at IS NOT NULL;
  v_ready_dep := 100.0 * ((SELECT count(*) FROM jsonb_array_elements(v_veh) e
                            WHERE e->>'state' IN ('staged_for_departure','en_route_to_deployment','service_complete_holding','deployed'))::numeric) / v_total;
  v_backlog := (SELECT count(*) FROM jsonb_array_elements(v_veh) e WHERE e->>'state'='arrived_at_gate');
  v_run_hours := GREATEST(0.05, v_run.tick_count * (v_run.tick_interval_seconds::numeric * COALESCE(v_run.time_scale,1)) / 3600.0);
  SELECT service_max_kw * (1 - COALESCE(dcfc_safety_margin_pct,10)/100.0) INTO v_cap FROM depots WHERE id = v_run.depot_id;
  -- run-scoped billed peak (was: unfiltered depot MAX -> cross-run contamination)
  v_peak := (SELECT COALESCE(MAX(grid_import_kw),0) FROM site_energy_snapshots WHERE sim_run_id = p_sim_run_id);

  INSERT INTO ottoq_ab_runs (
    ab_group_id, sim_run_id, seed, policy, scenario_code, ticks,
    decisions_total, enacted_total, deploys_total, productive_deploys, unsafe_deploys,
    fleet_ready_pct, safety_violations, safety_critical_violations, overrides_total,
    avg_decision_latency_ms, energy_peak_kw, charge_sessions, incidents_open,
    vehicles_turned_around, gate_backlog, throughput_per_hr, peak_demand_pct_of_cap,
    trips_completed, vehicles_cycled, median_turnaround_min, ready_or_deployed_pct)
  VALUES (
    COALESCE(v_run.ab_group_id, p_sim_run_id), p_sim_run_id, v_run.random_seed, v_run.policy, v_run.scenario_code, v_run.tick_count,
    (SELECT COUNT(*) FROM ottoq_decisions WHERE sim_run_id=p_sim_run_id),
    (SELECT COUNT(*) FROM ottoq_decisions WHERE sim_run_id=p_sim_run_id AND outcome_status='enacted'),
    v_deployed, COALESCE(v_prod,0), COALESCE(v_unsafe,0),
    round(v_ready,2), v_breach.total, v_breach.b_deploy_low_soc, COALESCE(v_ov,0),
    (SELECT AVG(total_latency_ms) FROM ottoq_decisions WHERE sim_run_id=p_sim_run_id),
    v_peak,   -- run-scoped billed peak
    (SELECT COUNT(*) FROM ocpp_sessions WHERE sim_run_id=p_sim_run_id),
    (SELECT COUNT(*) FROM ottoq_vehicle_incidents WHERE sim_run_id=p_sim_run_id AND resolution_status='open'),
    v_turned, v_backlog, round(COALESCE(v_trips,0) / v_run_hours, 1), round(100.0 * COALESCE(v_peak,0) / NULLIF(v_cap,0), 0),
    v_trips, v_cycled, round(COALESCE(v_med,0), 0), round(COALESCE(v_ready_dep,0), 0))
  RETURNING ab_run_id INTO v_id;
  RETURN v_id;
END;
$function$


-- ===== ottoq_seed_oem_route_slots =====
CREATE OR REPLACE FUNCTION public.ottoq_seed_oem_route_slots(p_prediction_type text, p_priority_base integer DEFAULT 100)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_inserted INTEGER := 0;
  v_oem      RECORD;
BEGIN
  -- Generic route (priority_base; matches when no more-specific route applies)
  INSERT INTO ottoq_model_routes (
    prediction_type, priority, traffic_share_pct, shadow_mode,
    rationale, created_by
  )
  SELECT p_prediction_type, p_priority_base, 100, FALSE,
         'Generic fallback route (auto-seeded by ottoq_seed_oem_route_slots)',
         'ottoq_seed_oem_route_slots'
  WHERE NOT EXISTS (
    SELECT 1 FROM ottoq_model_routes r
     WHERE r.prediction_type = p_prediction_type
       AND r.fleet_operator_id IS NULL
       AND r.depot_id IS NULL
       AND r.vehicle_class IS NULL
  );
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  -- Per-OEM route slot for each fleet_operator (NULL model_version until trained)
  FOR v_oem IN
    SELECT id, name FROM fleet_operators WHERE is_active = TRUE
  LOOP
    INSERT INTO ottoq_model_routes (
      prediction_type, fleet_operator_id, priority,
      traffic_share_pct, shadow_mode,
      rationale, created_by
    )
    SELECT p_prediction_type, v_oem.id, p_priority_base + 100, 100, FALSE,
           format('Per-OEM route slot for %s (auto-seeded; awaiting trained model)', v_oem.name),
           'ottoq_seed_oem_route_slots'
    WHERE NOT EXISTS (
      SELECT 1 FROM ottoq_model_routes r
       WHERE r.prediction_type = p_prediction_type
         AND r.fleet_operator_id = v_oem.id
         AND r.depot_id IS NULL
         AND r.vehicle_class IS NULL
    );
    v_inserted := v_inserted + 1;
  END LOOP;

  -- Per-vehicle-class route slot for each known vehicle class
  FOR v_oem IN
    SELECT vehicle_class_code, oem_fleet_operator_id FROM ottoq_vehicle_classes WHERE status = 'active'
  LOOP
    INSERT INTO ottoq_model_routes (
      prediction_type, vehicle_class, fleet_operator_id, priority,
      traffic_share_pct, shadow_mode,
      rationale, created_by
    )
    SELECT p_prediction_type, v_oem.vehicle_class_code, v_oem.oem_fleet_operator_id,
           p_priority_base + 200, 100, FALSE,
           format('Per-vehicle-class route slot for %s (auto-seeded; awaiting trained model)', v_oem.vehicle_class_code),
           'ottoq_seed_oem_route_slots'
    WHERE NOT EXISTS (
      SELECT 1 FROM ottoq_model_routes r
       WHERE r.prediction_type = p_prediction_type
         AND r.vehicle_class = v_oem.vehicle_class_code
    );
    v_inserted := v_inserted + 1;
  END LOOP;

  RETURN v_inserted;
END;
$function$


-- ===== ottoq_seed_vehicle_need_profiles =====
CREATE OR REPLACE FUNCTION public.ottoq_seed_vehicle_need_profiles(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run       ottoq_sim_runs%ROWTYPE;
  v_seed      bigint;
  v_clock     timestamptz;
  v_sla_floor numeric;
  v_n         int := 0;
  v_t0        timestamptz := clock_timestamp();
  v_target_sw text;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
  v_seed  := COALESCE(v_run.random_seed, 42);
  v_clock := COALESCE(v_run.sim_clock_current, v_run.sim_clock_start, now());

  BEGIN
    SELECT min_soc_at_deployment_pct INTO v_sla_floor
      FROM ottoq_get_active_sla((SELECT fleet_operator_id FROM vehicles
                                  WHERE home_depot_id = v_run.depot_id AND fleet_operator_id IS NOT NULL
                                  LIMIT 1));
  EXCEPTION WHEN OTHERS THEN v_sla_floor := NULL; END;
  v_sla_floor := COALESCE(v_sla_floor, 80);

  v_target_sw := '2026.' || (30 + floor(3 * ottoq_sim_seeded_random(v_seed, 'vnp:swtarget'))::int)::text || '.4';

  WITH fleet AS (
    SELECT v.id, v.config, v.inlet_max_kw, v.battery_capacity_kwh, v.min_soc_threshold,
           v.target_soc, v.current_soc
      FROM vehicles v
     WHERE v.home_depot_id = v_run.depot_id
       AND v.category = 'autonomous'
       AND v.is_active
  ), w AS (
    SELECT DISTINCT ON (vehicle_id) vehicle_id, soil_index, drive_km_total, backfilled_km,
           drive_hours_total, km_at_last_pm, hours_at_last_calibration, calibrated_at,
           open_dtc_count, worst_open_dtc_rank, cabin_litter_events
      FROM ottoq_vehicle_wear
     WHERE sim_run_id = p_sim_run_id
     ORDER BY vehicle_id, updated_at DESC
  ), d AS (
    SELECT f.id, f.config, f.inlet_max_kw,
      ottoq_sim_seeded_random(v_seed, 'vnp:temp:'     || f.id::text) AS r_temp,
      ottoq_sim_seeded_random(v_seed, 'vnp:dcfc:'     || f.id::text) AS r_dcfc,
      ottoq_sim_seeded_random(v_seed, 'vnp:balance:'  || f.id::text) AS r_bal,
      ottoq_sim_seeded_random(v_seed, 'vnp:soil:'     || f.id::text) AS r_soil,
      ottoq_sim_seeded_random(v_seed, 'vnp:cabin:'    || f.id::text) AS r_cabin,
      ottoq_sim_seeded_random(v_seed, 'vnp:wash:'     || f.id::text) AS r_wash,
      ottoq_sim_seeded_random(v_seed, 'vnp:washint:'  || f.id::text) AS r_washint,
      ottoq_sim_seeded_random(v_seed, 'vnp:deep:'     || f.id::text) AS r_deep,
      ottoq_sim_seeded_random(v_seed, 'vnp:calib:'    || f.id::text) AS r_calib,
      ottoq_sim_seeded_random(v_seed, 'vnp:sensor:'   || f.id::text) AS r_sensor,
      ottoq_sim_seeded_random(v_seed, 'vnp:sw:'       || f.id::text) AS r_sw,
      ottoq_sim_seeded_random(v_seed, 'vnp:odo:'      || f.id::text) AS r_odo,
      ottoq_sim_seeded_random(v_seed, 'vnp:pm:'       || f.id::text) AS r_pm,
      ottoq_sim_seeded_random(v_seed, 'vnp:fault:'    || f.id::text) AS r_fault,
      ottoq_sim_seeded_random(v_seed, 'vnp:faultsev:' || f.id::text) AS r_faultsev,
      ottoq_sim_seeded_random(v_seed, 'vnp:tire:'     || f.id::text) AS r_tire,
      ottoq_sim_seeded_random(v_seed, 'vnp:brake:'    || f.id::text) AS r_brake,
      ottoq_sim_seeded_random(v_seed, 'vnp:deploy:'   || f.id::text) AS r_deploy,
      ottoq_sim_seeded_random(v_seed, 'vnp:deployhr:' || f.id::text) AS r_deployhr,
      ottoq_sim_seeded_random(v_seed, 'vnp:prio:'     || f.id::text) AS r_prio,
      ottoq_sim_seeded_random(v_seed, 'vnp:shift:'    || f.id::text) AS r_shift,
      ottoq_sim_seeded_random(v_seed, 'vnp:item:'     || f.id::text) AS r_item,
      ottoq_sim_seeded_random(v_seed, 'vnp:itemkind:' || f.id::text) AS r_itemkind,
      COALESCE((f.config->>'battery_soh_pct')::numeric,
               round((88 + 12 * ottoq_sim_seeded_random(v_seed, 'vnp:soh:' || f.id::text))::numeric, 1)) AS soh,
      COALESCE((f.config->>'charge_curve_scalar')::numeric, 1.0) AS curve,
      COALESCE((f.config->>'soil_rate')::numeric, 1.0)           AS soil_rate,
      (f.config->>'lifetime_miles')::numeric                     AS lifetime_mi,
      COALESCE((f.config->>'pm_interval_km')::numeric,
               round((6500 + 3000 * ottoq_sim_seeded_random(v_seed, 'vnp:pmint:' || f.id::text))::numeric, 0)) AS pm_int,
      COALESCE((f.config->>'calib_interval_h')::numeric,
               round((180 + 140 * ottoq_sim_seeded_random(v_seed, 'vnp:calint:' || f.id::text))::numeric, 0)) AS cal_int,
      wr.soil_index, wr.drive_km_total, wr.backfilled_km, wr.km_at_last_pm AS w_km_pm,
      wr.hours_at_last_calibration, wr.calibrated_at, wr.open_dtc_count,
      wr.worst_open_dtc_rank, wr.cabin_litter_events
    FROM fleet f LEFT JOIN w wr ON wr.vehicle_id = f.id
  ), calc AS (
    SELECT d.*,
      round((12 + 30 * d.r_temp)::numeric, 1)                                   AS pack_temp_c,
      round((COALESCE(d.inlet_max_kw, 150) * d.curve
             * (0.70 + 0.30 * LEAST(1, GREATEST(0, (d.soh - 85) / 15.0))))::numeric, 1) AS accept_kw,
      round(COALESCE(d.soil_index, LEAST(1.0, 0.05 + 0.85 * d.r_soil * d.soil_rate))::numeric, 3) AS soil_lvl,
      round((48 + 48 * d.r_washint)::numeric, 0)                                AS wash_int_h,
      round((1.45 * d.r_wash * (48 + 48 * d.r_washint))::numeric, 0)            AS wash_ago_h,
      round((1.18 * d.r_deep * 336)::numeric, 0)                                AS deep_ago_h,
      round((1.50 * d.r_calib * d.cal_int)::numeric, 0)                         AS calib_ago_h,
      round((88 + 12 * d.r_sensor)::numeric, 1)                                 AS sensor_health,
      -- LIFETIME odometer: config.lifetime_miles -> km, plus km accrued inside this run
      round((COALESCE(d.lifetime_mi * 1.60934, 20000 + 160000 * d.r_odo)
             + COALESCE(d.drive_km_total, 0))::numeric, 0)                      AS odo_km,
      -- km since PM: seeded phase on the LIFETIME scale + whatever this run has added
      round((1.45 * d.r_pm * d.pm_int
             + GREATEST(0, COALESCE(d.drive_km_total, 0) - COALESCE(d.w_km_pm, 0)))::numeric, 0) AS km_since_pm,
      GREATEST(0, COALESCE(d.open_dtc_count, 0))                                AS dtc_n_wear
      FROM d
  )
  INSERT INTO public.vehicle_need_profile AS p (
    vehicle_id, profile_version, drawn_for_run, drawn_seed, drawn_at, drawn_at_sim_clock,
    battery_soh_pct, battery_chemistry, charge_accept_kw, pack_temp_c, dcfc_safe,
    dcfc_block_reason, cell_balance_due_at, min_ready_soc_pct,
    exterior_soil_level, cabin_condition, last_wash_at, last_deep_clean_at,
    wash_interval_h, deep_clean_interval_h,
    calib_interval_h, calib_interval_km, last_calibration_at, sensor_health_pct,
    software_version, sw_target_version, sw_update_size_mb,
    odometer_km, pm_interval_km, km_at_last_pm, last_pm_at,
    open_fault_codes, worst_fault_severity, tire_tread_mm, tire_rotation_due_km, brake_wear_pct,
    next_deploy_at, priority_class, assigned_shift,
    item_retrieval_pending, item_reported_at, item_description, updated_at)
  SELECT
    c.id, 'v1', p_sim_run_id, v_seed, now(), v_clock,
    c.soh,
    CASE WHEN c.r_dcfc < 0.22 THEN 'LFP' ELSE 'NMC' END,
    c.accept_kw,
    c.pack_temp_c,
    NOT (c.pack_temp_c >= 40 OR c.soh < 90 AND c.r_dcfc < 0.35 OR c.r_bal < 0.06),
    CASE WHEN c.pack_temp_c >= 40            THEN 'pack_temp_high'
         WHEN c.soh < 90 AND c.r_dcfc < 0.35 THEN 'soh_derate'
         WHEN c.r_bal < 0.06                 THEN 'cell_balance_overdue'
         ELSE NULL END,
    v_clock + make_interval(hours => round((-72 + 336 * c.r_bal)::numeric)::int),
    v_sla_floor,
    c.soil_lvl,
    CASE WHEN c.r_cabin < 0.02 THEN 'biohazard'
         WHEN c.r_cabin < 0.14 THEN 'soiled'
         WHEN c.r_cabin < 0.45 THEN 'light_litter'
         ELSE 'clean' END,
    v_clock - make_interval(hours => c.wash_ago_h::int),
    v_clock - make_interval(hours => c.deep_ago_h::int),
    c.wash_int_h, 336,
    c.cal_int,
    round(c.pm_int * 1.5, 0),
    COALESCE(c.calibrated_at, v_clock - make_interval(hours => c.calib_ago_h::int)),
    c.sensor_health,
    CASE WHEN c.r_sw < 0.58 THEN v_target_sw
         WHEN c.r_sw < 0.86 THEN '2026.28.9'
         ELSE '2026.26.2' END,
    v_target_sw,
    CASE WHEN c.r_sw < 0.58 THEN 0 ELSE (400 + floor(1800 * c.r_sw))::int END,
    c.odo_km, c.pm_int,
    GREATEST(0, c.odo_km - c.km_since_pm),
    v_clock - make_interval(days => (5 + floor(115 * c.r_pm))::int),
    CASE WHEN c.dtc_n_wear >= 2 OR c.r_fault < 0.05
           THEN ARRAY['P0AA6','U0100']
         WHEN c.dtc_n_wear = 1 OR c.r_fault < 0.13
           THEN ARRAY[(ARRAY['C1A55','B10A2','U0422','P1B01'])[1 + floor(4 * c.r_faultsev)::int]]
         ELSE '{}'::text[] END,
    CASE WHEN c.dtc_n_wear >= 2 OR c.r_fault < 0.05 THEN 1
         WHEN c.dtc_n_wear = 1 OR c.r_fault < 0.13 THEN (2 + floor(3 * c.r_faultsev))::smallint
         ELSE 99 END::smallint,
    round((2.4 + 6.0 * c.r_tire)::numeric, 1),
    round((c.odo_km + (-1500 + 12000 * c.r_tire))::numeric, 0),
    round((5 + 80 * c.r_brake)::numeric, 1),
    CASE WHEN c.r_deploy < 0.10 THEN NULL
         WHEN c.r_deploy < 0.32 THEN v_clock + make_interval(mins => (35 + floor(85 * c.r_deployhr))::int)
         WHEN c.r_deploy < 0.70 THEN v_clock + make_interval(mins => (120 + floor(240 * c.r_deployhr))::int)
         ELSE                        v_clock + make_interval(mins => (360 + floor(540 * c.r_deployhr))::int)
    END,
    CASE WHEN c.r_prio < 0.07 THEN 'critical'
         WHEN c.r_prio < 0.27 THEN 'high'
         WHEN c.r_prio < 0.88 THEN 'standard'
         ELSE 'low' END,
    CASE WHEN c.r_shift < 0.40 THEN 'day'
         WHEN c.r_shift < 0.78 THEN 'night'
         ELSE 'flex' END,
    (c.r_item < 0.07 OR COALESCE(c.cabin_litter_events,0) >= 3),
    CASE WHEN c.r_item < 0.07 OR COALESCE(c.cabin_litter_events,0) >= 3
         THEN v_clock - make_interval(mins => (10 + floor(180 * c.r_itemkind))::int) END,
    CASE WHEN c.r_item < 0.07 OR COALESCE(c.cabin_litter_events,0) >= 3
         THEN (ARRAY['phone','wallet','backpack','keys','laptop'])[1 + floor(5 * c.r_itemkind)::int] END,
    now()
  FROM calc c
  ON CONFLICT (vehicle_id) DO UPDATE SET
    profile_version = EXCLUDED.profile_version, drawn_for_run = EXCLUDED.drawn_for_run,
    drawn_seed = EXCLUDED.drawn_seed, drawn_at = EXCLUDED.drawn_at,
    drawn_at_sim_clock = EXCLUDED.drawn_at_sim_clock,
    battery_soh_pct = EXCLUDED.battery_soh_pct, battery_chemistry = EXCLUDED.battery_chemistry,
    charge_accept_kw = EXCLUDED.charge_accept_kw, pack_temp_c = EXCLUDED.pack_temp_c,
    dcfc_safe = EXCLUDED.dcfc_safe, dcfc_block_reason = EXCLUDED.dcfc_block_reason,
    cell_balance_due_at = EXCLUDED.cell_balance_due_at, min_ready_soc_pct = EXCLUDED.min_ready_soc_pct,
    exterior_soil_level = EXCLUDED.exterior_soil_level, cabin_condition = EXCLUDED.cabin_condition,
    last_wash_at = EXCLUDED.last_wash_at, last_deep_clean_at = EXCLUDED.last_deep_clean_at,
    wash_interval_h = EXCLUDED.wash_interval_h, deep_clean_interval_h = EXCLUDED.deep_clean_interval_h,
    calib_interval_h = EXCLUDED.calib_interval_h, calib_interval_km = EXCLUDED.calib_interval_km,
    last_calibration_at = EXCLUDED.last_calibration_at, sensor_health_pct = EXCLUDED.sensor_health_pct,
    software_version = EXCLUDED.software_version, sw_target_version = EXCLUDED.sw_target_version,
    sw_update_size_mb = EXCLUDED.sw_update_size_mb,
    odometer_km = EXCLUDED.odometer_km, pm_interval_km = EXCLUDED.pm_interval_km,
    km_at_last_pm = EXCLUDED.km_at_last_pm, last_pm_at = EXCLUDED.last_pm_at,
    open_fault_codes = EXCLUDED.open_fault_codes, worst_fault_severity = EXCLUDED.worst_fault_severity,
    tire_tread_mm = EXCLUDED.tire_tread_mm, tire_rotation_due_km = EXCLUDED.tire_rotation_due_km,
    brake_wear_pct = EXCLUDED.brake_wear_pct,
    next_deploy_at = EXCLUDED.next_deploy_at, priority_class = EXCLUDED.priority_class,
    assigned_shift = EXCLUDED.assigned_shift,
    item_retrieval_pending = EXCLUDED.item_retrieval_pending,
    item_reported_at = EXCLUDED.item_reported_at, item_description = EXCLUDED.item_description,
    updated_at = now();

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'profiles_seeded', v_n, 'seed', v_seed,
    'sim_clock', v_clock, 'sw_target', v_target_sw, 'sla_floor', v_sla_floor,
    'ms', round(EXTRACT(epoch FROM (clock_timestamp() - v_t0)) * 1000));
END;
$function$


-- ===== ottoq_service_must_do =====
CREATE OR REPLACE FUNCTION public.ottoq_service_must_do(p_svc text, p_urgency text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
  SELECT CASE COALESCE(c.must_do_at, 'never')
           WHEN 'always'   THEN true
           WHEN 'due'      THEN p_urgency IN ('due','overdue','critical')
           WHEN 'overdue'  THEN p_urgency IN ('overdue','critical')
           WHEN 'critical' THEN p_urgency =  'critical'
           ELSE false
         END
    FROM (SELECT 1) z
    LEFT JOIN public.service_cadence_policy c
           ON c.svc = p_svc AND c.is_active;
$function$


-- ===== ottoq_service_priority_propose =====
CREATE OR REPLACE FUNCTION public.ottoq_service_priority_propose(p_sim_run_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_clock timestamptz;
  v_cap int; v_in_svc int; v_slots int;
  v_row RECORD; v_n int := 0;
BEGIN
  SELECT depot_id, sim_clock_current INTO v_depot, v_clock
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  -- staff-gated service lane capacity (same source the heuristic reads)
  BEGIN v_cap := ottoq_sim_lane_capacity(NULL, 'service_staff', 2);
  EXCEPTION WHEN OTHERS THEN v_cap := 2; END;
  SELECT count(*) INTO v_in_svc FROM vehicles
   WHERE home_depot_id = v_depot AND current_state = 'in_service_bay';
  v_slots := GREATEST(0, COALESCE(v_cap,2) - COALESCE(v_in_svc,0));
  IF v_slots = 0 THEN RETURN 0; END IF;

  FOR v_row IN
    WITH waiting AS (
      SELECT v.id AS vehicle_id,
             v.current_soc,
             GREATEST(0, EXTRACT(EPOCH FROM (v_clock - COALESCE(v.last_state_change, v_clock)))/60.0) AS dwell_min,
             -- a genuinely pending must-do service atom (readiness_check excluded)
             EXISTS (SELECT 1 FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE((a->>'must_do')::boolean,false)
                        AND a->>'svc' <> 'readiness_check'
                        AND COALESCE(a->>'status','pending') IN ('pending','in_progress')) AS has_must_do,
             COALESCE((SELECT vn2.urgency FROM ottoq_visit_needs vn2
                        WHERE vn2.vehicle_id = v.id AND vn2.status IN ('open','in_progress')
                        ORDER BY vn2.created_at DESC LIMIT 1), 'standard') AS urgency
        FROM vehicles v
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
         AND v.current_state = 'staged_awaiting_service'
         AND COALESCE(v.config->>'svc_step','') = 'need_service'
    )
    SELECT vehicle_id, current_soc, dwell_min, has_must_do, urgency,
           ( dwell_min * 1.0
           + CASE WHEN has_must_do THEN 60 ELSE 0 END
           + CASE urgency WHEN 'tech_hold' THEN 80 WHEN 'immediate_dispatch' THEN 40 ELSE 0 END
           + COALESCE(current_soc,0) * 0.2 ) AS priority
      FROM waiting
     ORDER BY priority DESC, vehicle_id
     LIMIT v_slots
  LOOP
    PERFORM ottoq_submit_external_proposal(
      p_sim_run_id := p_sim_run_id,
      p_depot_id   := v_depot,
      p_action_context := 'service_sequencing',
      p_entity_type := 'vehicle',
      p_entity_id   := v_row.vehicle_id,
      p_proposal := jsonb_build_object(
        'abstain', false,
        'resolved_action_context', 'task_start',
        'verb', 'admit_service',
        'vehicle_id', v_row.vehicle_id,
        'requested_kw', 0,
        'l2_engine', 'ottoq_service_priority',
        'rationale', jsonb_build_object(
          'priority', round(v_row.priority::numeric,1),
          'dwell_min', round(v_row.dwell_min::numeric,1),
          'must_do', v_row.has_must_do,
          'urgency', v_row.urgency,
          'soc', v_row.current_soc,
          'slots_free', v_slots,
          'model', 'must_do x dwell x urgency x deploy_value')),
      p_source := 'ottoq_service_priority',
      p_ttl_seconds := 120);
    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END;
$function$


-- ===== ottoq_service_urgency =====
CREATE OR REPLACE FUNCTION public.ottoq_service_urgency(p_svc text, p_ratio numeric)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
  SELECT CASE
           WHEN p_ratio IS NULL THEN 'unknown'
           WHEN p_ratio >= COALESCE(c.critical_ratio, 1.60) THEN 'critical'
           WHEN p_ratio >= COALESCE(c.overdue_ratio,  1.25) THEN 'overdue'
           WHEN p_ratio >= COALESCE(c.due_ratio,      1.00) THEN 'due'
           WHEN p_ratio >= COALESCE(c.due_soon_ratio, 0.75) THEN 'due_soon'
           ELSE 'ok'
         END
    FROM (SELECT 1) z
    LEFT JOIN public.service_cadence_policy c
           ON c.svc = p_svc AND c.is_active;
$function$


-- ===== ottoq_set_demo_speed =====
CREATE OR REPLACE FUNCTION public.ottoq_set_demo_speed(p_sim_run_id uuid, p_speed numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_x numeric;
BEGIN
  v_x := GREATEST(0.25, LEAST(5.0, COALESCE(p_speed,1.0)));
  UPDATE ottoq_sim_runs SET demo_speed_x = v_x, next_tick_due_at = now()
   WHERE sim_run_id = p_sim_run_id AND status='running';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','no_running_run'); END IF;
  RETURN jsonb_build_object('ok',true,'sim_run_id',p_sim_run_id,'demo_speed_x',v_x,
    'real_seconds_per_tick', round(6.0/v_x,2));
END;
$function$


-- ===== ottoq_set_playback =====
CREATE OR REPLACE FUNCTION public.ottoq_set_playback(p_sim_run_id uuid, p_mode text DEFAULT NULL::text, p_speed_x numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_mode text; v_speed numeric; v_run ottoq_sim_runs%ROWTYPE;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason','run_not_found'); END IF;

  v_mode  := COALESCE(NULLIF(p_mode,''), v_run.payload->>'playback_mode', 'fixed');
  IF v_mode NOT IN ('live','fixed') THEN
    RETURN jsonb_build_object('ok', false, 'reason','bad_mode', 'got', v_mode);
  END IF;
  -- hard clamp: 3x is the founder-approved ceiling for CONTINUOUS play. Anything
  -- faster must be a jump, so decisions are never silently outrun by the clock.
  v_speed := LEAST(3.0, GREATEST(1.0,
               COALESCE(p_speed_x, (v_run.payload->>'speed_x')::numeric, 1.0)));

  UPDATE ottoq_sim_runs
     SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('playback_mode', v_mode, 'speed_x', v_speed)
   WHERE sim_run_id = p_sim_run_id;

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id,
    'playback_mode', v_mode, 'speed_x', v_speed,
    'meaning', CASE WHEN v_mode='live'
                    THEN format('1 real second = %s sim second(s)', v_speed)
                    ELSE format('%s sim-minutes per tick (fixed)',
                         round((v_run.tick_interval_seconds::numeric*v_run.time_scale)/60.0,2)) END);
END; $function$


-- ===== ottoq_shield_and_log =====
CREATE OR REPLACE FUNCTION public.ottoq_shield_and_log(p_sim_run_id uuid, p_tick_seq bigint, p_depot_id uuid, p_actions jsonb, p_shadow boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  a jsonb; v_ctx jsonb; v_blocks int; v_block_codes text[]; v_rule_rows jsonb;
  v_over boolean; v_safe boolean; v_outcome text; v_ac text; v_eid uuid; v_fleet uuid;
  n_enacted int := 0; n_over int := 0; n_noop int := 0; results jsonb := '[]'::jsonb;
BEGIN
  IF p_actions IS NULL OR jsonb_typeof(p_actions) <> 'array' THEN
    RETURN jsonb_build_object('error','p_actions must be a jsonb array');
  END IF;
  FOR a IN SELECT * FROM jsonb_array_elements(p_actions) LOOP
    v_ac  := COALESCE(a->>'action_context','stall_assignment');
    v_eid := NULLIF(a->>'vehicle_id','')::uuid;
    v_over := false; v_safe := false; v_block_codes := '{}'; v_rule_rows := '[]'::jsonb;
    IF v_eid IS NULL THEN CONTINUE; END IF;
    SELECT fleet_operator_id INTO v_fleet FROM vehicles WHERE id = v_eid;
    v_ctx := COALESCE(ottoq_build_decision_context(v_ac,'vehicle',v_eid,p_depot_id,now()), '{}'::jsonb)
             || jsonb_build_object('stall_id', a->>'stall_id', 'requested_kw', a->>'requested_kw',
                                   'service', a->>'service', 'stall_kind', a->>'kind');

    IF (a->>'stall_id') IS NULL THEN
      v_outcome := 'noop_no_candidate'; n_noop := n_noop + 1;
    ELSE
      SELECT count(*) FILTER (WHERE would_block),
             array_agg(rule_code) FILTER (WHERE would_block),
             jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
        INTO v_blocks, v_block_codes, v_rule_rows
        FROM ottoq_shield_probe(v_ac,'vehicle',v_eid,v_ctx,v_fleet,p_depot_id);
      IF COALESCE(v_blocks,0) > 0 THEN
        v_over := true; v_safe := true; v_outcome := 'overridden_to_default'; n_over := n_over + 1;
      ELSE
        v_outcome := 'enacted'; n_enacted := n_enacted + 1;
      END IF;
    END IF;

    INSERT INTO ottoq_decisions (sim_run_id, tick_seq, depot_id, action_context, resolved_action_context,
      entity_type, entity_id, context_frame, proposed_action, enacted_action, overridden, override_rule_codes,
      rule_results, safe_default_taken, outcome_status)
    VALUES (p_sim_run_id, p_tick_seq, p_depot_id, v_ac, v_ac, 'vehicle', v_eid, v_ctx, a,
      CASE WHEN v_outcome='enacted' THEN a ELSE '{}'::jsonb END, v_over, COALESCE(v_block_codes,'{}'),
      COALESCE(v_rule_rows,'[]'::jsonb), v_safe, v_outcome);

    IF v_outcome = 'enacted' THEN
      PERFORM ottoq_emit_recommendation(
        p_proposed_action := v_ac, p_prediction_type := 'stall_assignment',
        p_action_parameters := jsonb_build_object('vehicle_id',v_eid,'stall_id',a->>'stall_id','service',a->>'service','requested_kw',a->>'requested_kw'),
        p_entity_type := 'vehicle', p_entity_id := v_eid, p_fleet_operator_id := v_fleet,
        p_depot_id := p_depot_id, p_shadow_only := p_shadow);
    END IF;

    results := results || jsonb_build_object('vehicle_id',v_eid,'service',a->>'service','stall_id',a->>'stall_id','outcome',v_outcome,'blocked_by',to_jsonb(v_block_codes));
  END LOOP;
  RETURN jsonb_build_object('sim_run_id',p_sim_run_id,'tick_seq',p_tick_seq,'enacted',n_enacted,'overridden',n_over,'noop',n_noop,'decisions',results);
END;
$function$


-- ===== ottoq_shield_probe =====
CREATE OR REPLACE FUNCTION public.ottoq_shield_probe(p_action_context text, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_context jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_triggered_by_event_id uuid DEFAULT NULL::uuid, p_override_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(rule_code text, passed boolean, reason text, enforcement_taken text, evaluation_id uuid, severity text, enforcement text, suggested_action text, would_block boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rc TEXT;
BEGIN
  FOR v_rc IN
    SELECT r.rule_code FROM ottoq_rules r
     WHERE r.status IN ('active','shadow')
       AND p_action_context = ANY(r.applies_to_actions)
     ORDER BY CASE r.severity
                WHEN 'safety_critical' THEN 1 WHEN 'critical' THEN 2
                WHEN 'error' THEN 3 WHEN 'warning' THEN 4 WHEN 'info' THEN 5 ELSE 6 END,
              r.rule_code
  LOOP
    RETURN QUERY
    SELECT v_rc, c.passed, c.reason, c.enforcement_taken, c.evaluation_id,
           c.severity, c.enforcement, c.suggested_action,
           -- would_block = this rule, if enforced, blocks the action (override-agnostic):
           (NOT c.passed AND c.enforcement = 'block')
    FROM ottoq_evaluate_rule_core(
      v_rc, p_entity_type, p_entity_id, p_context, p_action_context,
      p_fleet_operator_id, p_depot_id, p_triggered_by_event_id, p_override_id) c;
  END LOOP;
END;
$function$

-- ===== ottoq_sign_bundle =====
CREATE OR REPLACE FUNCTION public.ottoq_sign_bundle(p_bundle_id uuid, p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_sha256 text, p_signing_key_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_secret      TEXT;
  v_canonical   TEXT;
BEGIN
  v_secret := ottoq_resolve_signing_secret(p_signing_key_id);
  IF v_secret IS NULL THEN
    RETURN NULL;
  END IF;
  v_canonical := concat_ws('|',
    p_bundle_id::text,
    to_char(p_window_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    to_char(p_window_end   AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    p_sha256
  );
  RETURN encode(hmac(v_canonical, v_secret, 'sha256'), 'hex');
END;
$function$


-- ===== ottoq_sign_event =====
CREATE OR REPLACE FUNCTION public.ottoq_sign_event(p_event_id uuid, p_occurred_at timestamp with time zone, p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid, p_payload_hash text, p_key_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_secret TEXT;
  v_canonical TEXT;
BEGIN
  v_secret := ottoq_resolve_signing_secret(p_key_id);
  IF v_secret IS NULL THEN
    RETURN NULL;
  END IF;

  v_canonical := concat_ws('|',
    p_event_id::text,
    to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    p_actor_type,
    p_event_type,
    p_entity_type,
    COALESCE(p_entity_id::text, ''),
    p_payload_hash
  );

  RETURN encode(hmac(v_canonical, v_secret, 'sha256'), 'hex');
END;
$function$


-- ===== ottoq_sim_advance_and_snapshot =====
CREATE OR REPLACE FUNCTION public.ottoq_sim_advance_and_snapshot(p_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_frame jsonb;
BEGIN
  PERFORM ottoq_sim_advance_tick(p_run);
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_run;
  SELECT jsonb_build_object(
    'gate',      count(*) FILTER (WHERE current_state='arrived_at_gate'),
    'charging',  count(*) FILTER (WHERE current_state IN ('charging_dcfc','charging_l2')),
    'servicing', count(*) FILTER (WHERE current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','staged_awaiting_service','charge_complete_holding','service_complete_holding')),
    'ready',     count(*) FILTER (WHERE current_state='staged_for_departure'),
    'deployed',  count(*) FILTER (WHERE current_state='en_route_to_deployment'),
    'turned_around', count(*) FILTER (WHERE current_state IN ('staged_for_departure','en_route_to_deployment','service_complete_holding'))
  ) INTO v_frame FROM vehicles WHERE home_depot_id=v_depot AND category='autonomous';
  RETURN v_frame;
END $function$


-- ===== ottoq_sim_advance_due_runs =====
CREATE OR REPLACE FUNCTION public.ottoq_sim_advance_due_runs(p_max_runs integer DEFAULT 10)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run     RECORD;
  v_total   INTEGER := 0;
BEGIN
  FOR v_run IN
    SELECT sim_run_id FROM ottoq_sim_runs
     WHERE status = 'running'
       AND next_tick_due_at <= NOW()
     ORDER BY next_tick_due_at ASC
     LIMIT p_max_runs
  LOOP
    PERFORM ottoq_sim_advance_tick(v_run.sim_run_id);
    v_total := v_total + 1;
  END LOOP;
  RETURN v_total;
END;
$function$


-- ===== ottoq_sim_advance_tick =====
CREATE OR REPLACE FUNCTION public.ottoq_sim_advance_tick(p_sim_run_id uuid)
 RETURNS TABLE(out_sim_clock_after timestamp with time zone, out_tick_minutes numeric, out_dispatched integer, out_telemetry_emitted integer, out_charge_assigned integer, out_charge_advanced integer, out_completed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE w RECORD; d RECORD;
BEGIN
  SELECT * INTO w FROM ottoq_sim_advance_tick_world(p_sim_run_id);
  IF w.out_completed AND w.out_sim_clock_after IS NULL THEN
    out_completed:=TRUE; RETURN NEXT; RETURN;
  END IF;
  SELECT * INTO d FROM ottoq_sim_decide_and_dispatch(p_sim_run_id);
  out_sim_clock_after:=w.out_sim_clock_after; out_tick_minutes:=w.out_tick_minutes;
  out_dispatched:=d.out_dispatched; out_telemetry_emitted:=w.out_telemetry_emitted;
  out_charge_assigned:=d.out_charge_assigned; out_charge_advanced:=w.out_charge_advanced;
  out_completed:=w.out_completed;
  RETURN NEXT;
END;
$function$


-- ===== ottoq_sim_advance_tick_world =====
CREATE OR REPLACE FUNCTION public.ottoq_sim_advance_tick_world(p_sim_run_id uuid)
 RETURNS TABLE(out_sim_clock_after timestamp with time zone, out_tick_minutes numeric, out_telemetry_emitted integer, out_charge_advanced integer, out_completed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_wear_ids uuid[];
  v_wear_written int;
  v_run ottoq_sim_runs%ROWTYPE;
  v_tick_minutes numeric; v_new_sim_clock timestamptz; v_completed boolean := FALSE;
  v_telemetry_count int; v_tick_t0 timestamptz; v_charge_adv int; v_feed_sim boolean := true;
BEGIN
  v_tick_t0 := clock_timestamp();   -- T0 instrument: whole-tick wall clock
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id FOR UPDATE;
  IF NOT FOUND OR v_run.status NOT IN ('running') THEN out_completed:=TRUE; RETURN NEXT; RETURN; END IF;

  SELECT COALESCE(d.feed_mode, 'sim') = 'sim' INTO v_feed_sim FROM depots d WHERE d.id = v_run.depot_id;
  v_feed_sim := COALESCE(v_feed_sim, true);
  -- PLAYBACK CLOCK. 'live' = TRUE 1:1 (sim advances by REAL elapsed x speed_x, so
  -- one real second is one sim second at 1x). 'fixed' (default) keeps the historical
  -- tick_interval_seconds * time_scale behaviour so certs/benchmarks stay deterministic.
  -- The 0.05..10 clamp keeps a stalled metronome or a long GC pause from teleporting
  -- the world; it never applies in fixed mode.
  IF COALESCE(v_run.payload->>'playback_mode','fixed') = 'live' THEN
    -- TRUE 1:1. clock_timestamp() (NOT now(), which is transaction time and does
    -- not advance inside a transaction). Floor 0 -- a zero advance is correct when
    -- no real time has elapsed. The 10-minute ceiling stays as the anti-teleport guard.
    v_tick_minutes := LEAST(10.0, GREATEST(0.0,
      (EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_run.last_tick_at, clock_timestamp())))
       * COALESCE((v_run.payload->>'speed_x')::numeric, 1.0)) / 60.0));
  ELSE
    v_tick_minutes := (v_run.tick_interval_seconds::numeric * v_run.time_scale) / 60.0;
  END IF;
  v_new_sim_clock := v_run.sim_clock_current + (v_tick_minutes || ' minutes')::interval;
  IF v_new_sim_clock >= v_run.sim_clock_end THEN v_new_sim_clock := v_run.sim_clock_end; v_completed := TRUE; END IF;

  PERFORM ottoq_sim_advance_visit_atoms(p_sim_run_id, v_new_sim_clock);
  PERFORM ottoq_opportunistic_scan(p_sim_run_id, v_new_sim_clock);
  PERFORM ottoq_sim_advance_flow_contract(p_sim_run_id, v_new_sim_clock);
  IF v_feed_sim THEN
    PERFORM ottoq_sim_prearrival_contracts(p_sim_run_id, v_new_sim_clock);
    PERFORM ottoq_sim_confirm_commands(p_sim_run_id, v_new_sim_clock);
  END IF;
  IF (v_run.policy IS NULL OR v_run.policy = 'otto_q') AND ottoq_policy_get(p_sim_run_id,'energy_orchestration_enabled',1) > 0 THEN
    PERFORM ottoq_energy_orchestrate(p_sim_run_id, v_run.depot_id, v_new_sim_clock, v_run.tick_count + 1);
  END IF;
  IF v_feed_sim THEN
    PERFORM ottoq_sim_energy_controller(p_sim_run_id, v_run.depot_id, v_new_sim_clock);
  END IF;

  IF v_feed_sim THEN
    PERFORM ottoq_sim_reconcile_charge_sessions(p_sim_run_id, v_new_sim_clock);
    SELECT COUNT(*) INTO v_charge_adv FROM ottoq_sim_advance_charge_sessions(p_sim_run_id, v_new_sim_clock);
    PERFORM ottoq_sim_advance_all_energy(v_run.depot_id, p_sim_run_id, v_new_sim_clock, v_tick_minutes);
  ELSE
    v_charge_adv := 0;
  END IF;
  IF v_feed_sim THEN
  -- AP-2 R1: snapshot the in-flight dispatch set BEFORE telemetry mutates it
  SELECT array_agg(d.dispatch_id) INTO v_wear_ids
    FROM ottoq_vehicle_dispatches d
   WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning');
  SELECT COUNT(*) INTO v_telemetry_count FROM ottoq_sim_advance_deployed_telemetry(p_sim_run_id, v_new_sim_clock, v_tick_minutes);
  v_wear_written := -1;
  BEGIN
    v_wear_written := ottoq_sim_advance_wear_counters(
      p_sim_run_id, v_new_sim_clock, v_tick_minutes, v_run.tick_count + 1, COALESCE(v_wear_ids, ARRAY[]::uuid[]));
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'wear_counters: %', SQLERRM; END;
  BEGIN
    INSERT INTO ottoq_wear_tick_status (sim_run_id, tick_seq, sim_clock, attempted, written, note)
    VALUES (p_sim_run_id, v_run.tick_count + 1, v_new_sim_clock,
            COALESCE(array_length(v_wear_ids,1),0), GREATEST(v_wear_written,0),
            CASE WHEN v_wear_written < 0 THEN 'advancer raised' ELSE NULL END)
    ON CONFLICT (sim_run_id, tick_seq) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  ELSE
    v_telemetry_count := 0;
  END IF;
  BEGIN PERFORM ottoq_comms_advance(p_sim_run_id, v_new_sim_clock); EXCEPTION WHEN OTHERS THEN RAISE WARNING 'comms_advance: %', SQLERRM; END;
  PERFORM ottoq_sim_advance_service_flow(p_sim_run_id, v_new_sim_clock, v_tick_minutes, v_run.depot_id);
  IF v_feed_sim THEN PERFORM ottoq_sim_overnight_service_drain(v_run.depot_id, v_new_sim_clock, p_sim_run_id); END IF;

  UPDATE ottoq_sim_runs SET sim_clock_current=v_new_sim_clock, last_tick_at=v_tick_t0,
         -- LIVE-CLOCK COUPLING FIX 2026-08-01: publish the ACTUAL elapsed sim-minutes
         -- so every per-tick RATE cap downstream scales with the real tick size.
         -- Fixed mode writes exactly 30 = the historical fallback (no behaviour change).
         payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object('tick_minutes_actual', v_tick_minutes),  -- anchor at tick START so the tick's own compute is inside the next elapsed
         next_tick_due_at=clock_timestamp()+(v_run.tick_interval_seconds||' seconds')::interval,
         tick_count=tick_count+1, status=CASE WHEN v_completed THEN 'completed' ELSE status END,
         ended_at=CASE WHEN v_completed THEN NOW() ELSE ended_at END
   WHERE sim_run_id=p_sim_run_id;

  IF v_feed_sim THEN
    PERFORM ottoq_sim_emit_depot_heartbeats(v_run.depot_id, v_new_sim_clock);
    UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_new_sim_clock WHERE depot_id = v_run.depot_id AND station_state <> 'Faulted';
    PERFORM ottoq_sim_recover_chargers(v_run.depot_id, v_new_sim_clock, 50);
  END IF;
  BEGIN PERFORM ottoq_reconcile_charger_states(v_run.depot_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'charger reconcile: %', SQLERRM; END;
  BEGIN PERFORM ottoq_oem_webhook_collect_responses();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'webhook reconcile: %', SQLERRM; END;
  BEGIN PERFORM ottoq_admit_stranded_vehicles(v_run.depot_id, p_sim_run_id, v_new_sim_clock, 80, 12);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'admit stranded: %', SQLERRM; END;

  UPDATE vehicles SET current_state='charge_complete_holding'::vehicle_state, last_state_change=v_new_sim_clock
   WHERE home_depot_id=v_run.depot_id AND category='autonomous'
     AND current_state='arrived_at_gate' AND current_soc>=85;

  IF v_feed_sim THEN
    PERFORM ottoq_sim_generate_arrival_manifests(v_run.depot_id, p_sim_run_id);
  END IF;
  PERFORM ottoq_sim_wash_triage(v_run.depot_id, v_new_sim_clock);
  IF v_feed_sim THEN
    PERFORM ottoq_sim_vehicle_exception_handler(v_run.depot_id, v_new_sim_clock, p_sim_run_id);
    PERFORM ottoq_sim_bay_fault_handler(v_run.depot_id, v_new_sim_clock, p_sim_run_id);
  END IF;

  -- T0 instrument: authoritative wall-clock + compute cost, one row per tick.
  -- clock_timestamp() (not now()) so batch-stepped ticks are individually timed.
  BEGIN
    INSERT INTO ottoq_tick_clock_log (
      sim_run_id, tick_seq, real_started_at, real_ended_at,
      sim_clock_before, sim_clock_after, tick_compute_ms, sim_advance_s,
      playback_mode, speed_x)
    VALUES (
      p_sim_run_id, COALESCE(v_run.tick_count,0) + 1, v_tick_t0, clock_timestamp(),
      v_run.sim_clock_current, v_new_sim_clock,
      round(EXTRACT(EPOCH FROM (clock_timestamp() - v_tick_t0))::numeric * 1000, 1),
      round(EXTRACT(EPOCH FROM (v_new_sim_clock - v_run.sim_clock_current))::numeric, 1),
      COALESCE(v_run.payload->>'playback_mode','fixed'),
      COALESCE((v_run.payload->>'speed_x')::numeric, 1.0))
    ON CONFLICT (sim_run_id, tick_seq) DO UPDATE
      SET real_ended_at   = EXCLUDED.real_ended_at,
          tick_compute_ms = EXCLUDED.tick_compute_ms;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'tick clock log: %', SQLERRM;
  END;

  out_sim_clock_after:=v_new_sim_clock; out_tick_minutes:=v_tick_minutes;
  out_telemetry_emitted:=v_telemetry_count; out_charge_advanced:=v_charge_adv; out_completed:=v_completed;
  RETURN NEXT;
END;
$function$


-- ===== ottoq_sim_compute_charge_rate =====
CREATE OR REPLACE FUNCTION public.ottoq_sim_compute_charge_rate(p_soc_pct numeric, p_battery_temp_c numeric, p_ambient_temp_c numeric, p_charger_max_kw numeric, p_vehicle_max_kw numeric, p_battery_capacity_kwh numeric, p_battery_soh_pct numeric DEFAULT 100, p_noise_seed bigint DEFAULT 0, p_noise_salt text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_base_rate      NUMERIC;
  v_is_dcfc        BOOLEAN;
  v_curve_factor   NUMERIC := 1.0;
  v_thermal_factor NUMERIC := 1.0;
  v_soh_factor     NUMERIC;
  v_noise_factor   NUMERIC;
BEGIN
  v_base_rate := LEAST(p_charger_max_kw, p_vehicle_max_kw);
  IF v_base_rate <= 0 THEN RETURN 0; END IF;
  v_is_dcfc := p_charger_max_kw > 22;

  IF v_is_dcfc THEN
    -- DCFC: ramp to peak by 20%, NEAR-LINEAR decline 20->80% (1.0 -> 0.22),
    -- steeper CV tail 80->100% (0.22 -> 0.08). 20->80 on a 75kWh pack lands
    -- ~25-30 min at typical effective power — the measured reality.
    IF p_soc_pct < 20 THEN
      v_curve_factor := 0.85 + (p_soc_pct / 20.0) * 0.15;
    ELSIF p_soc_pct <= 80 THEN
      v_curve_factor := 1.0 - ((p_soc_pct - 20.0) / 60.0) * 0.78;
    ELSE
      v_curve_factor := GREATEST(0.08, 0.22 - ((p_soc_pct - 80.0) / 20.0) * 0.14);
    END IF;
  ELSE
    -- L2/AC: onboard-charger limited, flat with ~88% AC->DC efficiency;
    -- taper only near full.
    v_curve_factor := CASE WHEN p_soc_pct > 95 THEN 0.88 * 0.5 ELSE 0.88 END;
  END IF;

  -- thermal derate: INL-calibrated cold behavior; heat derate unchanged
  IF p_battery_temp_c > 35 THEN
    v_thermal_factor := GREATEST(0.30, 1.0 - (p_battery_temp_c - 35) * 0.020);
  ELSIF p_battery_temp_c < 0 THEN
    v_thermal_factor := GREATEST(0.20, 0.35 + p_battery_temp_c * 0.010);  -- <=0C: 0.35 and falling
  ELSIF p_battery_temp_c < 10 THEN
    v_thermal_factor := 0.65;                                             -- 0-10C: x0.65 (INL)
  ELSIF p_battery_temp_c < 15 THEN
    v_thermal_factor := 0.65 + (p_battery_temp_c - 10) * 0.07;            -- blend 10->15C
  END IF;

  v_soh_factor := 0.70 + (p_battery_soh_pct / 100.0) * 0.30;
  v_noise_factor := 0.97 + ottoq_sim_seeded_random(
    p_noise_seed, COALESCE(p_noise_salt, '') || ':' || p_soc_pct::text) * 0.06;

  RETURN ROUND((v_base_rate * v_curve_factor * v_thermal_factor * v_soh_factor * v_noise_factor)::NUMERIC, 3);
END;
$function$


-- ===== ottoq_sim_decide_and_dispatch =====
CREATE OR REPLACE FUNCTION public.ottoq_sim_decide_and_dispatch(p_sim_run_id uuid)
 RETURNS TABLE(out_dispatched integer, out_charge_assigned integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_decide ottoq_decide_tick_result;
  v_is_benchmark boolean; v_redeployed int := 0;
  v_tick_minutes numeric; v_k text;
  v_fire_hb timestamptz; v_hb_window int;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF NOT FOUND THEN out_dispatched:=0; out_charge_assigned:=0; RETURN NEXT; RETURN; END IF;
  v_tick_minutes := COALESCE((v_run.payload->>'tick_minutes_actual')::numeric,
                             (v_run.tick_interval_seconds::numeric * v_run.time_scale) / 60.0);

  SELECT EXISTS (SELECT 1 FROM depots d WHERE d.id = v_run.depot_id AND d.slug LIKE 'benchmark%') INTO v_is_benchmark;

  IF v_run.policy IS NULL OR v_run.policy = 'otto_q' THEN
    BEGIN
      UPDATE ottoq_sim_runs
         SET payload = COALESCE(payload,'{}'::jsonb)
                     || jsonb_build_object('inbound_forecast', ottoq_inbound_forecast(v_run.depot_id, 60))
       WHERE sim_run_id = p_sim_run_id;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'inbound_forecast attach: %', SQLERRM;
    END;
    BEGIN
      PERFORM ottoq_reoptimize_reservation_book(p_sim_run_id, v_run.sim_clock_current);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'reservation reopt: %', SQLERRM;
    END;

    -- ════════════════════════════════════════════════════════════════════════
    -- P6 FIX 2 — DECIDE-BEAT cuOpt FIRE, CONDITIONAL. net.http_post only QUEUES
    -- a row; the pg_net worker cannot transmit until THIS transaction COMMITS,
    -- and ottoq_decide_tick runs a few lines below, inside it. So a fire from
    -- here lands one full tick late by construction. It is NOT deleted, because
    -- this function is also the only route to cuOpt for callers with no fire
    -- beat (twin.ottoq_world_advance, ottoq_api_otto_q_decide, probe ticks).
    -- Stand down ONLY while a healthy FIRE beat is demonstrably running.
    -- ════════════════════════════════════════════════════════════════════════
    v_hb_window := GREATEST(5, ottoq_policy_get(p_sim_run_id, 'cuopt_fire_beat_heartbeat_s', 60)::int);
    BEGIN
      v_fire_hb := (v_run.payload->>'cuopt_fire_beat_at')::timestamptz;
    EXCEPTION WHEN OTHERS THEN v_fire_hb := NULL;
    END;
    IF v_fire_hb IS NULL OR v_fire_hb < now() - make_interval(secs => v_hb_window) THEN
      BEGIN PERFORM ottoq_cuopt_refresh(p_sim_run_id); EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;

    -- ════════════════════════════════════════════════════════════════════════
    -- P7 2026-08-03 — RIGHT OF FIRST REFUSAL ON DECIDE-BEAT ARRIVALS.
    --
    -- The metronome alternates FIRE and DECIDE beats. A vehicle that reaches the
    -- gate during a DECIDE beat is placed by the local greedy path inside THIS
    -- transaction, so no FIRE beat ever sees it and cuOpt cannot compete for it.
    -- Measured on the phase-9 cert: 113 arrivals, 57 gate candidates -- the
    -- coin-flip you would predict from the beat split, not a solver problem.
    --
    -- This holds such a vehicle out of the greedy cursor for EXACTLY ONE decide
    -- tick so the next FIRE beat can offer it. The hold releases the instant a
    -- cuopt proposal exists (first refusal, never veto) and UNCONDITIONALLY at
    -- the next decide tick via ottoq_cuopt_defer_roll -- so if cuOpt abstains,
    -- greedy assigns next tick with no condition attached. Capped at
    -- cuopt_first_refusal_max_defers (default 1) per vehicle per run; set it to
    -- 0 to disable. Never aborts the tick.
    -- ════════════════════════════════════════════════════════════════════════
    BEGIN
      PERFORM ottoq_cuopt_first_refusal_arm(p_sim_run_id, COALESCE(v_run.tick_count,0));
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'cuopt first-refusal arm: %', SQLERRM;
    END;

    PERFORM ottoq_l2_optimize_assignments(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
    BEGIN PERFORM ottoq_service_priority_propose(p_sim_run_id); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  v_decide := CASE v_run.policy
    WHEN 'greedy' THEN ottoq_greedy_tick(p_sim_run_id)
    WHEN 'fifo'   THEN ottoq_fifo_tick(p_sim_run_id)
    WHEN 'manual' THEN ottoq_manual_tick(p_sim_run_id)
    ELSE               ottoq_decide_tick(p_sim_run_id)
  END;

  IF v_run.policy IS DISTINCT FROM 'greedy' THEN
    v_redeployed := ottoq_sim_auto_dispatch_tick(p_sim_run_id, v_run.sim_clock_current, v_tick_minutes);
  END IF;

  BEGIN
    PERFORM ottoq_itin_close_travel_legs(p_sim_run_id, v_run.sim_clock_current, 20);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'close travel legs: %', SQLERRM;
  END;

  BEGIN
    PERFORM ottoq_sweep_stranded_deployments(p_sim_run_id, v_run.sim_clock_current, 45);

  BEGIN
    PERFORM ottoq_release_expired_bookings(p_sim_run_id, v_run.sim_clock_current);
    PERFORM ottoq_place_unplaced_vehicles(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
    PERFORM ottoq.ottoq_react_to_refusals(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'placement reconcile: %', SQLERRM;
  END;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'stranded deploy sweep: %', SQLERRM;
  END;

  IF COALESCE(v_run.run_by,'') <> 'benchmark'
     AND NOT v_is_benchmark
     AND v_run.policy IS NOT DISTINCT FROM 'otto_q'
     AND ( (COALESCE(v_run.tick_count,0) % 3) = 0
           OR ottoq_orchestrator_trigger(v_run.depot_id) ) THEN
    BEGIN
      SELECT decrypted_secret INTO v_k FROM vault.decrypted_secrets WHERE name='ottoq_anon_key' LIMIT 1;
      IF v_k IS NOT NULL THEN
        PERFORM net.http_post(
          url := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-orchestrator-agent',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_k,'apikey',v_k),
          body := jsonb_build_object('depot_id', v_run.depot_id, 'sim_run_id', p_sim_run_id),
          timeout_milliseconds := 20000);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  PERFORM ottoq_record_event(
    p_actor_type:='ottoq_engine', p_actor_id:='ottoq_orchestrator', p_event_type:='twin.sim_tick_advanced',
    p_entity_type:='system', p_payload:=jsonb_build_object('sim_run_id',p_sim_run_id,'sim_clock',v_run.sim_clock_current,
      'policy',v_run.policy,'decisions_built',v_decide.requests_built,'enacted',v_decide.enacted,
      'redeployed',v_redeployed,'completed',(v_run.status='completed')),
    p_severity:='debug', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);

  out_dispatched:=v_decide.enacted; out_charge_assigned:=v_decide.requests_built;
  RETURN NEXT;
END;
$function$


-- ===== ottoq_sim_jump_forward =====
CREATE OR REPLACE FUNCTION public.ottoq_sim_jump_forward(p_sim_run_id uuid, p_sim_minutes numeric, p_max_seconds numeric DEFAULT 6.0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_target timestamptz; v_started timestamptz;
  v_prev_mode text; v_ticks int := 0; v_done boolean := false;
  v_t0 timestamptz; v_dec_before bigint; v_dec_after bigint;
  v_book_before bigint; v_book_after bigint; v_elapsed numeric;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason','run_not_found'); END IF;
  IF v_run.status <> 'running' THEN
    RETURN jsonb_build_object('ok', false, 'reason','run_not_running', 'status', v_run.status);
  END IF;

  -- Resume an in-flight jump, or start a new one. The TARGET is persisted so repeated
  -- calls converge on the same destination even if each gets only part way.
  v_target := COALESCE((v_run.payload->'jump'->>'target_sim_clock')::timestamptz,
                       v_run.sim_clock_current + (p_sim_minutes || ' minutes')::interval);
  IF v_run.sim_clock_end IS NOT NULL AND v_target > v_run.sim_clock_end THEN
    v_target := v_run.sim_clock_end;
  END IF;
  v_prev_mode := COALESCE(v_run.payload->'jump'->>'prev_mode',
                          v_run.payload->>'playback_mode', 'fixed');
  v_t0 := v_run.sim_clock_current;

  SELECT count(*) INTO v_dec_before  FROM ottoq_decisions   WHERE sim_run_id = p_sim_run_id;
  SELECT count(*) INTO v_book_before FROM ottoq_visit_needs WHERE sim_run_id = p_sim_run_id;

  UPDATE ottoq_sim_runs
     SET payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object(
           'playback_mode','fixed',
           'jump', jsonb_build_object(
             'status','planning', 'target_sim_clock', v_target,
             'from_sim_clock', COALESCE(v_run.payload->'jump'->>'from_sim_clock', v_t0::text),
             'prev_mode', v_prev_mode))
   WHERE sim_run_id = p_sim_run_id;

  v_started := clock_timestamp();
  LOOP
    SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
    EXIT WHEN v_run.sim_clock_current >= v_target;
    EXIT WHEN v_run.status <> 'running';
    -- clock_timestamp() advances inside the transaction; now() would not.
    EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_started)) >= p_max_seconds;

    BEGIN PERFORM ottoq_sim_advance_tick(p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'jump tick failed: %', SQLERRM;
      EXIT;
    END;
    v_ticks := v_ticks + 1;
  END LOOP;

  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  v_done := (v_run.sim_clock_current >= v_target) OR (v_run.status <> 'running');

  SELECT count(*) INTO v_dec_after  FROM ottoq_decisions   WHERE sim_run_id = p_sim_run_id;
  SELECT count(*) INTO v_book_after FROM ottoq_visit_needs WHERE sim_run_id = p_sim_run_id;

  IF v_done THEN
    UPDATE ottoq_sim_runs
       SET payload = (COALESCE(payload,'{}'::jsonb) - 'jump')
                     || jsonb_build_object('playback_mode', v_prev_mode)
     WHERE sim_run_id = p_sim_run_id;
  END IF;

  v_elapsed := EXTRACT(EPOCH FROM (clock_timestamp() - v_started));
  RETURN jsonb_build_object(
    'ok', true, 'done', v_done,
    'sim_clock', v_run.sim_clock_current,
    'target_sim_clock', v_target,
    'remaining_sim_minutes', GREATEST(0, round(EXTRACT(EPOCH FROM (v_target - v_run.sim_clock_current))/60.0, 1)),
    'ticks_this_call', v_ticks,
    'seconds_this_call', round(v_elapsed, 2),
    'playback_mode', CASE WHEN v_done THEN v_prev_mode ELSE 'fixed' END,
    'ottoq_worked', jsonb_build_object(
      'decisions_made', v_dec_after - v_dec_before,
      'visits_booked',  v_book_after - v_book_before));
END; $function$


-- ===== ottoq_sim_run_scenario =====
CREATE OR REPLACE FUNCTION public.ottoq_sim_run_scenario(p_scenario_code text, p_seed bigint DEFAULT NULL::bigint, p_run_by text DEFAULT 'system_scheduler'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_scenario   ottoq_sim_scenarios%ROWTYPE;
  v_sim_run_id UUID := gen_random_uuid();
  v_seed       BIGINT;
  v_start      TIMESTAMPTZ;
  v_end        TIMESTAMPTZ;
  v_start_hour INT;
  v_prime_frac NUMERIC;
BEGIN
  SELECT * INTO v_scenario FROM ottoq_sim_scenarios
   WHERE scenario_code = p_scenario_code AND status = 'available';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'scenario % not found or not available', p_scenario_code;
  END IF;

  v_start := CASE WHEN p_run_by = 'operator_demo'
    THEN ((date_trunc('day', now() AT TIME ZONE 'America/Chicago') + interval '8 hours') AT TIME ZONE 'America/Chicago')
    ELSE NOW() END;
  v_start_hour := EXTRACT(HOUR FROM (v_start AT TIME ZONE 'America/Chicago'))::int;

  v_seed := COALESCE(p_seed, abs(hashtextextended(gen_random_uuid()::text, 42)));
  v_end  := v_start + (v_scenario.default_duration_hours || ' hours')::interval;

  INSERT INTO ottoq_scenarios (
    scenario_id, scenario_code, category, title, description,
    depot_id, sim_duration_minutes, default_time_scale, tick_interval_seconds,
    initial_conditions, arrival_profile, timeline, random_seed, status,
    introduced_in, created_at, updated_at
  ) VALUES (
    v_scenario.scenario_id, v_scenario.scenario_code,
    CASE
      WHEN p_scenario_code = 'normal_day' THEN 'normal_operations'
      WHEN p_scenario_code IN ('heat_wave','winter_storm','solar_underperformance_partly_cloudy',
                               'aggressive_fleet_turnover') THEN 'stress_test'
      WHEN p_scenario_code IN ('dr_event_cascade','charger_outage_morning_rush',
                               'grid_brownout_at_peak') THEN 'edge_case'
      ELSE 'demo' END,
    v_scenario.title, COALESCE(v_scenario.description, v_scenario.title),
    v_scenario.default_depot_id,
    (v_scenario.default_duration_hours * 60)::int,
    v_scenario.default_time_scale,
    v_scenario.default_tick_seconds,
    jsonb_build_object('weather_overrides', v_scenario.weather_overrides,
                       'fleet_overrides',   v_scenario.fleet_overrides),
    jsonb_build_object('shape', 'nyc_tlc_hourly_arrival_rate'),
    jsonb_build_object('grid_overrides',    v_scenario.grid_overrides,
                       'charger_overrides', v_scenario.charger_overrides,
                       'fault_injection',   v_scenario.fault_injection),
    v_seed, 'active', '20260619_twin_a6', NOW(), NOW()
  )
  ON CONFLICT (scenario_id) DO NOTHING;

  UPDATE ottoq_sim_runs SET status='completed', ended_at=NOW(),
         notes = COALESCE(notes,'') || ' | superseded by ' || p_scenario_code
   WHERE depot_id = v_scenario.default_depot_id AND status='running';

  -- a superseded run's open needs must not leak into the new world
  UPDATE ottoq_visit_needs vn SET status = 'superseded'
    FROM vehicles v
   WHERE vn.vehicle_id = v.id AND v.home_depot_id = v_scenario.default_depot_id
     AND vn.status IN ('open','in_progress');

  INSERT INTO ottoq_sim_runs (
    sim_run_id, scenario_id, scenario_code, status,
    sim_clock_start, sim_clock_current, sim_clock_end,
    started_at, last_tick_at, next_tick_due_at,
    depot_id, random_seed, time_scale, tick_interval_seconds,
    run_by, notes
  ) VALUES (
    v_sim_run_id, v_scenario.scenario_id, v_scenario.scenario_code, 'running',
    v_start, v_start, v_end, NOW(), NOW(), NOW(),
    v_scenario.default_depot_id, v_seed,
    v_scenario.default_time_scale, v_scenario.default_tick_seconds,
    p_run_by, 'Started via ottoq_sim_run_scenario(' || p_scenario_code || ')'
  );

  BEGIN
    PERFORM ottoq_sim_seed_fleet(v_scenario.default_depot_id, v_seed, v_start_hour);
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('seed_fleet', jsonb_build_object('ok', true))
     WHERE sim_run_id = v_sim_run_id;
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('seed_fleet', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
  END;

  -- CARD-2: the DRAW PHASE — every world + per-vehicle variable dealt before tick 1
  BEGIN
    PERFORM ottoq_run_boot_draw(v_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('boot_draw', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
    BEGIN
      PERFORM ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'run_boot_draw',
        p_event_type := 'twin.boot_draw_failed', p_entity_type := 'system',
        p_payload := jsonb_build_object('sim_run_id', v_sim_run_id, 'error', SQLERRM),
        p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id := v_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END;

  BEGIN
    PERFORM ottoq_variability_instantiate(v_sim_run_id, p_scenario_code);
  EXCEPTION WHEN undefined_function THEN NULL;
  END;

  -- (A) SCENARIO FLEET OVERRIDES -- on the LOAD path, not in a wrapper. Runs AFTER
  --     ottoq_run_boot_draw (which unconditionally rewrites pm_interval_km /
  --     calib_interval_h) and BEFORE prime, so the wear phase offsets see the final
  --     intervals. Receipt, never silence: a failure here is recorded on the run.
  BEGIN
    PERFORM ottoq_scenario_apply_fleet_overrides(v_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('scenario_overrides', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
    RAISE WARNING 'scenario fleet overrides: %', SQLERRM;
  END;

  BEGIN
    IF NOT EXISTS (SELECT 1 FROM depots d
                    WHERE d.id = v_scenario.default_depot_id AND d.slug LIKE 'benchmark%') THEN
      DECLARE v_primed INTEGER; v_pool INTEGER; v_states JSONB;
      BEGIN
        SELECT COUNT(*) INTO v_pool FROM vehicles v
         WHERE v.home_depot_id = v_scenario.default_depot_id AND v.category = 'autonomous'
           AND v.current_soc >= 80
           AND v.current_state IN ('staged_for_departure','en_route_to_deployment','offline');
        SELECT jsonb_object_agg(s, n) INTO v_states
          FROM (SELECT current_state::text AS s, COUNT(*) AS n FROM vehicles
                 WHERE home_depot_id = v_scenario.default_depot_id AND category = 'autonomous'
                 GROUP BY 1) t;
        -- (B) prime at the SCENARIO's hour-shaped deployed target
        v_prime_frac := ottoq_deploy_target_fraction(
                          v_start_hour,
                          COALESCE((v_scenario.fleet_overrides->>'target_deployed_fraction')::numeric, 0.92));
        v_primed := ottoq_sim_prime_deployment(v_sim_run_id, v_start, v_prime_frac);
        UPDATE ottoq_sim_runs
           SET payload = COALESCE(payload,'{}'::jsonb)
                       || jsonb_build_object('boot_prime', jsonb_build_object(
                            'ok', true, 'primed', v_primed, 'candidate_pool', v_pool,
                            'prime_fraction', v_prime_frac, 'start_hour_cst', v_start_hour,
                            'state_histogram', v_states))
         WHERE sim_run_id = v_sim_run_id;
      END;
    ELSE
      UPDATE ottoq_sim_runs
         SET payload = COALESCE(payload,'{}'::jsonb)
                     || jsonb_build_object('boot_prime', jsonb_build_object('ok', true, 'skipped', 'benchmark_depot'))
       WHERE sim_run_id = v_sim_run_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('boot_prime', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
  END;

  IF v_scenario.grid_overrides ? 'force_bess_starting_soc_pct' THEN
    UPDATE ottoq_bess_units
       SET current_soc_pct = (v_scenario.grid_overrides->>'force_bess_starting_soc_pct')::numeric,
           current_soc_kwh = capacity_kwh
                          * ((v_scenario.grid_overrides->>'force_bess_starting_soc_pct')::numeric) / 100.0
     WHERE depot_id = v_scenario.default_depot_id;
  END IF;

  PERFORM ottoq_record_event(
    p_actor_type := 'system_scheduler', p_actor_id := 'twin_scenario_runner',
    p_event_type := 'twin.scenario_started', p_entity_type := 'system',
    p_payload := jsonb_build_object('sim_run_id', v_sim_run_id, 'scenario_code', p_scenario_code,
      'seed', v_seed, 'start_hour_cst', v_start_hour, 'duration_h', v_scenario.default_duration_hours),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := v_sim_run_id);

  RETURN v_sim_run_id;
END;
$function$


-- ===== ottoq_sim_stop_and_reset =====
CREATE OR REPLACE FUNCTION public.ottoq_sim_stop_and_reset(p_sim_run_id uuid, p_reason text DEFAULT 'operator_stop'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_veh int := 0; v_sess int := 0; v_archive jsonb;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN jsonb_build_object('ok',false,'error','run not found'); END IF;
  UPDATE ottoq_sim_runs SET
      status='completed', ended_at=now(), next_tick_due_at=NULL, failure_reason=p_reason,
      -- truthful run-metadata tallies for the flight recorder
      charge_sessions    = (SELECT count(*) FROM ocpp_sessions        WHERE sim_run_id = p_sim_run_id),
      events_generated   = (SELECT count(*) FROM ottoq_events         WHERE sim_run_id = p_sim_run_id),
      tasks_completed    = (SELECT count(*) FROM ottoq_events         WHERE sim_run_id = p_sim_run_id AND event_type = 'twin.service_completed'),
      vehicles_simulated = (SELECT count(DISTINCT vehicle_id) FROM ottoq_telemetry_packets WHERE sim_run_id = p_sim_run_id)
   WHERE sim_run_id = p_sim_run_id;

  -- SAVE THE RUN LOG BEFORE WIPING THE TWIN. Runs are reproducible from their
  -- seed, so the archive stores the reproducibility key + outcome metrics; the raw
  -- rows are purged by the NEXT ottoq_start_demo_run and would otherwise be lost.
  -- No EXCEPTION handler here on purpose -- see migration comment.
  v_archive := ottoq_archive_run(p_sim_run_id, p_reason);

  UPDATE ocpp_sessions SET status='cancelled', ended_at=now(), stopped_reason='sim_reset', updated_at=now()
   WHERE depot_id = v_depot AND status='active';
  GET DIAGNOSTICS v_sess = ROW_COUNT;
  UPDATE stalls SET current_vehicle_id=NULL, reserved_by=NULL, reservation_expires_at=NULL WHERE depot_id = v_depot;
  -- release the forward calendar too: a stopped depot holds no reservations.
  BEGIN
    UPDATE ottoq_stall_bookings
       SET state = 'released', released_at = now(), release_reason = 'run_stopped'
     WHERE sim_run_id = p_sim_run_id AND state IN ('held','active');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'stop_and_reset booking release: %', SQLERRM; END;
  UPDATE ottoq_vehicle_dispatches SET status='completed', actual_return_at=COALESCE(actual_return_at, now()), return_trigger=COALESCE(return_trigger, 'run_stopped')
   WHERE sim_run_id = p_sim_run_id AND status IN ('active','returning');
  UPDATE vehicles SET current_state='offline'::vehicle_state, current_stall_id=NULL, last_state_change=now(),
         config = (COALESCE(config,'{}'::jsonb) - 'svc_step' - 'service_ends_at')
   WHERE current_depot_id = v_depot AND category='autonomous';
  GET DIAGNOSTICS v_veh = ROW_COUNT;
  -- release chargers stranded by the bulk session cancel above (see migration notes)
  BEGIN PERFORM ottoq_reconcile_charger_states(v_depot);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'stop_and_reset charger reconcile: %', SQLERRM; END;
  PERFORM ottoq_record_event(p_actor_type:='ottoq_engine', p_actor_id:='otto_twin',
    p_event_type:='twin.sim_stopped_and_reset', p_entity_type:='sim_run', p_entity_id:=p_sim_run_id,
    p_depot_id:=v_depot, p_payload:=jsonb_build_object('reason',p_reason,'vehicles_reset',v_veh,'sessions_ended',v_sess),
    p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
  RETURN jsonb_build_object('ok',true,'stopped',p_sim_run_id,'depot_reset_to_empty',true,
    'vehicles_unplaced',v_veh,'sessions_ended',v_sess,'blackbox_ready',true,
    'archived', COALESCE(v_archive->>'ok','false')::boolean,
    'reproducible_from', v_archive->'reproducible_from');
END;
$function$


-- ===== ottoq_stalls_state_change =====
CREATE OR REPLACE FUNCTION public.ottoq_stalls_state_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_payload      JSONB;
  v_diff         JSONB;
  v_actor_type   TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
  v_actor_id     TEXT := NULLIF(current_setting('ottoq.actor_id', TRUE), '');
  v_event_type   TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_event_type := 'stall.created';
    PERFORM ottoq_record_event(
      p_actor_type    := v_actor_type,
      p_actor_id      := v_actor_id,
      p_event_type    := v_event_type,
      p_entity_type   := 'stall',
      p_entity_id     := NEW.id,
      p_depot_id      := NEW.depot_id,
      p_payload       := jsonb_build_object('new', to_jsonb(NEW)),
      p_new_state     := to_jsonb(NEW),
      p_ingest_source := 'trigger'
    );
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF to_jsonb(OLD) = to_jsonb(NEW) THEN RETURN NEW; END IF;
    v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
    -- Skip pure-timestamp churn: only clock columns moved, no state change.
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_object_keys(v_diff) AS k
       WHERE k <> ALL (ARRAY['updated_at','reservation_expires_at'])
    ) THEN
      RETURN NEW;
    END IF;
    v_event_type := 'stall.state_changed';
    v_payload := jsonb_build_object('diff', v_diff);
    PERFORM ottoq_record_event(
      p_actor_type     := v_actor_type,
      p_actor_id       := v_actor_id,
      p_event_type     := v_event_type,
      p_entity_type    := 'stall',
      p_entity_id      := NEW.id,
      p_depot_id       := NEW.depot_id,
      p_payload        := v_payload,
      p_new_state      := to_jsonb(NEW),
      p_ingest_source  := 'trigger'
    );
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$function$


-- ===== ottoq_stamp_booked_at_sim =====
CREATE OR REPLACE FUNCTION public.ottoq_stamp_booked_at_sim()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.booked_at_sim IS NULL AND NEW.sim_run_id IS NOT NULL THEN
    BEGIN
      SELECT r.sim_clock_current INTO NEW.booked_at_sim
        FROM public.ottoq_sim_runs r
       WHERE r.sim_run_id = NEW.sim_run_id;
    EXCEPTION WHEN OTHERS THEN
      NEW.booked_at_sim := NULL;   -- never cost a booking over an audit stamp
    END;
  END IF;
  -- Last resort: a booking always has a sim-domain anchor, even if the run row is gone.
  IF NEW.booked_at_sim IS NULL THEN
    NEW.booked_at_sim := lower(NEW.during);
  END IF;
  RETURN NEW;
END
$function$


-- ===== ottoq_stamp_l2_engine =====
CREATE OR REPLACE FUNCTION public.ottoq_stamp_l2_engine()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  NEW.l2_engine := COALESCE(NULLIF(NEW.enacted_action->>'source',''), NEW.l2_engine, 'deterministic_v1');
  RETURN NEW;
END;
$function$


-- ===== ottoq_start_busy_run =====
CREATE OR REPLACE FUNCTION public.ottoq_start_busy_run(p_speed numeric DEFAULT 1.0, p_days integer DEFAULT 1, p_seed bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_res jsonb; v_run uuid; v_ov jsonb;
BEGIN
  -- Overrides are now applied by ottoq_sim_run_scenario (inside ottoq_start_demo_run),
  -- so this wrapper is a thin, VERIFYING alias. It exists so old callers keep working
  -- and so an operator gets a loud receipt if the loader ever fails to apply them.
  v_res := ottoq_start_demo_run('busy_day', p_speed, p_days, p_seed);
  v_run := (v_res->>'sim_run_id')::uuid;
  IF v_run IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no sim_run_id', 'start', v_res);
  END IF;

  SELECT payload->'scenario_overrides' INTO v_ov FROM ottoq_sim_runs WHERE sim_run_id = v_run;

  RETURN v_res || jsonb_build_object('busy_day', jsonb_build_object(
    'ok', COALESCE((v_ov->>'ok')::boolean, false),
    'applied_by', 'ottoq_sim_run_scenario/ottoq_scenario_apply_fleet_overrides',
    'scenario_overrides', v_ov));
END;
$function$


-- ===== ottoq_start_concurrent_atoms =====
CREATE OR REPLACE FUNCTION public.ottoq_start_concurrent_atoms(p_vehicle uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_visit uuid; v_atoms jsonb; v_depot uuid;
  v_new jsonb := '[]'::jsonb; v_a jsonb; v_free int; v_started int := 0;
  v_needs_triage boolean; v_has_triage boolean;
BEGIN
  SELECT home_depot_id INTO v_depot FROM vehicles WHERE id = p_vehicle;
  SELECT visit_id, atoms INTO v_visit, v_atoms FROM ottoq_visit_needs
   WHERE vehicle_id = p_vehicle AND status IN ('open','in_progress')
   ORDER BY created_at DESC LIMIT 1;
  IF v_visit IS NULL THEN RETURN 0; END IF;

  SELECT
    EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a
             WHERE COALESCE((a->>'confirm_required')::boolean,false)
               AND COALESCE(a->>'status','pending') = 'pending'),
    EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a WHERE a->>'svc' = 'triage_check')
  INTO v_needs_triage, v_has_triage;
  IF v_needs_triage AND NOT v_has_triage THEN
    v_atoms := v_atoms || jsonb_build_array(jsonb_build_object(
      'svc','triage_check','must_do',true,'deferrable',false,'est_min',3,'concurrency','cabin'));
  END IF;

  -- general_tech_pool (founder spec: ~10 techs in the charging zones). Each tech
  -- handles ONE vehicle at a time: plug in -> 3-5 min interior clean -> inspect.
  -- Cars in a wash bay are deliberately NOT subtracted here — the automatic wash is
  -- supervised by the wash_supervisor pool, it does not consume a charging-zone tech.
  SELECT GREATEST(0, ottoq_depot_staffing_count(v_depot, 'general_tech')
      - (SELECT count(*) FROM ottoq_visit_needs vn2, jsonb_array_elements(vn2.atoms) a2
           WHERE vn2.depot_id = v_depot AND vn2.status = 'in_progress'
             AND a2->>'status' = 'in_progress' AND a2->>'concurrency' IN ('cabin','exterior')))
    INTO v_free;
  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
    IF COALESCE(v_a->>'status','pending') = 'pending'
       AND v_a->>'concurrency' IN ('cabin','exterior','digital')
       AND v_a->>'svc' <> 'readiness_check'
       AND (NOT COALESCE((v_a->>'confirm_required')::boolean,false)) THEN
      IF v_a->>'concurrency' = 'digital' OR v_free > 0 THEN
        IF v_a->>'concurrency' <> 'digital' THEN v_free := v_free - 1; END IF;
        v_a := v_a || jsonb_build_object('status','in_progress',
                'started_at', to_jsonb(p_clock),
                'ends_at', to_jsonb(p_clock + ((COALESCE((v_a->>'est_min')::numeric,5))::text || ' minutes')::interval));
        v_started := v_started + 1;
      END IF;
    END IF;
    v_new := v_new || jsonb_build_array(v_a);
  END LOOP;
  IF v_started > 0 OR (v_needs_triage AND NOT v_has_triage) THEN
    UPDATE ottoq_visit_needs SET atoms = v_new, status = 'in_progress' WHERE visit_id = v_visit;
  END IF;
  RETURN v_started;
END; $function$


-- ===== ottoq_start_demo_run =====
CREATE OR REPLACE FUNCTION public.ottoq_start_demo_run(p_scenario text DEFAULT 'normal_day'::text, p_speed numeric DEFAULT 1.0, p_days integer DEFAULT 1, p_seed bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  r uuid;
  v_x numeric := GREATEST(0.25, LEAST(5.0, COALESCE(p_speed,1.0)));
  v_purge jsonb;
  v_aborted int;
  v_offset_min int;
  v_new_start timestamptz;
BEGIN
  UPDATE ottoq_sim_runs
     SET status = 'aborted'
   WHERE COALESCE(run_by,'') <> 'production_live'
     AND status IN ('running','paused');
  GET DIAGNOSTICS v_aborted = ROW_COUNT;

  r := ottoq_sim_run_scenario(p_scenario, p_seed, 'operator_demo');

  -- Random minute-of-day; seed-derived when seeded so reproducibility holds.
  v_offset_min := CASE
    WHEN p_seed IS NOT NULL THEN (abs(hashtext(p_seed::text)) % 1440)
    ELSE floor(random() * 1440)::int
  END;

  UPDATE ottoq_sim_runs
     SET sim_clock_start   = date_trunc('day', sim_clock_start) + make_interval(mins => v_offset_min),
         sim_clock_current = date_trunc('day', sim_clock_start) + make_interval(mins => v_offset_min),
         sim_clock_end     = date_trunc('day', sim_clock_start) + make_interval(mins => v_offset_min)
                             + make_interval(days => GREATEST(1, p_days)),
         demo_speed_x      = v_x,
         next_tick_due_at  = now()
   WHERE sim_run_id = r
  RETURNING sim_clock_start INTO v_new_start;

  -- ═══════ LIVE CLOCK IS NOW THE DEMO DEFAULT (2026-08-01) ═══════
  -- Fixed mode quantises ETA to the 30-minute tick grid, so the approach band's
  -- 10-minute freeze threshold had nothing to bite on (the boundary was crossed
  -- only 3 times in 1,850 observations) and the cuOpt window collapsed to a single
  -- point at exactly 30.00 min. In live mode the sim clock advances by REAL elapsed
  -- time x speed_x, so ETA is CONTINUOUS at any speed -- a multiplier is fine and is
  -- how the founder actually watches. ottoq_set_playback applies the founder-approved
  -- 1x-3x clamp for continuous play. This is the DEMO/VIEWING path only: the cert
  -- harness (run_by='cert_harness') and production_live never call this function and
  -- keep fixed-mode determinism.
  PERFORM ottoq_set_playback(r, 'live', v_x);

  v_purge := ottoq_purge_prior_runs(r);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', r, 'scenario', p_scenario,
    'demo_speed_x', v_x, 'real_seconds_per_tick', round(6.0/v_x,2),
    'playback_mode', 'live', 'playback_speed_x', LEAST(3.0, GREATEST(1.0, v_x)),
    'runs_for_sim_days', GREATEST(1,p_days),
    'sim_clock_start', v_new_start,
    'start_time_of_day', to_char(v_new_start, 'HH24:MI'),
    'start_offset_min', v_offset_min,
    'start_deterministic', p_seed IS NOT NULL,
    'aborted_prior_running', v_aborted, 'purged_prior', v_purge);
END;
$function$


-- ===== ottoq_start_training_run =====
CREATE OR REPLACE FUNCTION public.ottoq_start_training_run(p_prediction_type text, p_model_family text, p_parent_model_version_id uuid DEFAULT NULL::uuid, p_dataset_window_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_dataset_window_end timestamp with time zone DEFAULT NULL::timestamp with time zone, p_hyperparameters jsonb DEFAULT '{}'::jsonb, p_trainer text DEFAULT 'colab'::text, p_trainer_user text DEFAULT NULL::text, p_notebook_url text DEFAULT NULL::text, p_git_commit_sha text DEFAULT NULL::text, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_vehicle_class text DEFAULT NULL::text, p_triggered_by text DEFAULT 'manual'::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO ottoq_training_runs (
    training_run_id, prediction_type, model_family,
    parent_model_version_id, started_at,
    dataset_window_start, dataset_window_end,
    hyperparameters, trainer, trainer_user, notebook_url, git_commit_sha,
    fleet_operator_id, depot_id, vehicle_class,
    triggered_by, notes, status
  ) VALUES (
    v_id, p_prediction_type, p_model_family,
    p_parent_model_version_id, NOW(),
    p_dataset_window_start, p_dataset_window_end,
    p_hyperparameters, p_trainer, p_trainer_user, p_notebook_url, p_git_commit_sha,
    p_fleet_operator_id, p_depot_id, p_vehicle_class,
    p_triggered_by, p_notes, 'running'
  );

  PERFORM ottoq_record_event(
    p_actor_type    := 'system_scheduler',
    p_actor_id      := p_trainer_user,
    p_event_type    := 'training.started',
    p_entity_type   := 'training_run',
    p_entity_id     := v_id,
    p_payload       := jsonb_build_object(
                        'prediction_type', p_prediction_type,
                        'model_family', p_model_family,
                        'trainer', p_trainer,
                        'triggered_by', p_triggered_by
                      ),
    p_severity      := 'info'
  );

  RETURN v_id;
END;
$function$


-- ===== ottoq_submit_external_proposal =====
CREATE OR REPLACE FUNCTION public.ottoq_submit_external_proposal(p_sim_run_id uuid, p_depot_id uuid, p_action_context text, p_entity_type text, p_entity_id uuid, p_proposal jsonb, p_source text DEFAULT 'external'::text, p_ttl_seconds integer DEFAULT 120)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_id uuid;
BEGIN
  UPDATE public.ottoq_external_proposals SET status='superseded'
   WHERE sim_run_id=p_sim_run_id AND action_context=p_action_context
     AND entity_type=p_entity_type AND entity_id=p_entity_id AND status='pending';
  INSERT INTO public.ottoq_external_proposals
    (sim_run_id,depot_id,action_context,entity_type,entity_id,proposal,source,status,expires_at)
  VALUES (p_sim_run_id,p_depot_id,p_action_context,p_entity_type,p_entity_id,p_proposal,p_source,'pending',
          now() + (p_ttl_seconds || ' seconds')::interval)
  RETURNING proposal_id INTO v_id;
  RETURN v_id;
END; $function$


-- ===== ottoq_svc_to_leg_type =====
CREATE OR REPLACE FUNCTION public.ottoq_svc_to_leg_type(p_svc text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT CASE
    -- twin codes that are already valid itinerary leg types: pass through unchanged
    WHEN p_svc = ANY (ARRAY['interior_tidy','sensor_clean','item_retrieval','software_update',
                            'remote_diagnostics','triage_check','sensor_calibration',
                            'mechanical_pm','fault_repair','cosmetic_repair'])
      THEN p_svc
    -- twin codes with a distinct itinerary spelling (matches the bay loop's existing CASE)
    WHEN p_svc = 'exterior_wash'       THEN 'wash'
    WHEN p_svc = 'interior_deep_clean' THEN 'detail'
    WHEN p_svc = 'interior_inspection' THEN 'inspect'
    -- Anything the twin invents that OTTO-Q has no leg for lands on the generic service leg.
    -- DO NOT remove this ELSE: totality is the whole point. The true code is preserved in
    -- ottoq_itinerary_legs.payload->>'atom', so the remap is lossless.
    ELSE 'service'
  END;
$function$

-- ===== ottoq_sweep_orphaned_visit_artifacts =====
CREATE OR REPLACE FUNCTION public.ottoq_sweep_orphaned_visit_artifacts(p_depot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_legs int := 0; v_itin int := 0; v_needs int := 0; v_res int := 0;
BEGIN
  UPDATE ottoq_itinerary_legs l
     SET status = 'skipped'
    FROM ottoq_vehicle_itineraries i
    JOIN ottoq_sim_runs r ON r.sim_run_id = i.sim_run_id
   WHERE l.itinerary_id = i.itinerary_id
     AND i.status = 'active' AND r.status <> 'running'
     AND l.status IN ('planned','active');
  GET DIAGNOSTICS v_legs = ROW_COUNT;

  UPDATE ottoq_vehicle_itineraries i
     SET status = 'cancelled'
    FROM ottoq_sim_runs r
   WHERE i.sim_run_id = r.sim_run_id
     AND i.status = 'active'
     AND r.status <> 'running';
  GET DIAGNOSTICS v_itin = ROW_COUNT;

  UPDATE ottoq_visit_needs vn
     SET status = 'superseded'
    FROM vehicles v
   WHERE vn.vehicle_id = v.id
     AND v.home_depot_id = p_depot_id
     AND vn.status IN ('open','in_progress','carried_over')
     AND v.current_state IN ('deployed','en_route_to_deployment','offline');
  GET DIAGNOSTICS v_needs = ROW_COUNT;

  UPDATE stalls s
     SET reserved_by = NULL, reservation_expires_at = NULL
    FROM vehicles v
   WHERE s.depot_id = p_depot_id
     AND s.reserved_by = v.id
     AND v.current_state IN ('deployed','en_route_to_deployment','offline');
  GET DIAGNOSTICS v_res = ROW_COUNT;

  RETURN jsonb_build_object('legs_skipped',v_legs,'itineraries_cancelled',v_itin,
    'needs_superseded',v_needs,'reservations_released',v_res);
END;
$function$


-- ===== ottoq_sweep_stranded_deployments =====
CREATE OR REPLACE FUNCTION public.ottoq_sweep_stranded_deployments(p_sim_run_id uuid, p_clock timestamp with time zone, p_max_minutes integer DEFAULT 45)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int := 0; v_depot uuid;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  -- A vehicle that has sat in en_route_to_deployment past the grace window with NO
  -- active dispatch is, by definition, lost: it is outside the depot service flow
  -- (so its atoms can never advance) and outside the dispatch flow (so it will never
  -- leave). Put it back in the departure queue where the normal gates apply.
  WITH stranded AS (
    SELECT v.id
      FROM vehicles v
     WHERE v.home_depot_id = v_depot
       AND v.category = 'autonomous'
       AND v.current_state = 'en_route_to_deployment'
       AND v.last_state_change < p_clock - make_interval(mins => p_max_minutes)
       AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
                        WHERE d.vehicle_id = v.id AND d.sim_run_id = p_sim_run_id
                          AND d.status IN ('active','returning'))
  ), fixed AS (
    UPDATE vehicles SET current_state = 'staged_for_departure', last_state_change = p_clock
     WHERE id IN (SELECT id FROM stranded)
    RETURNING id
  )
  SELECT count(*) INTO v_n FROM fixed;

  IF v_n > 0 THEN
    PERFORM ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_actor_id := 'deploy_strand_sweep',
      p_event_type := 'ops.stranded_deploy_recovered', p_entity_type := 'depot',
      p_entity_id := v_depot, p_depot_id := v_depot,
      p_payload := jsonb_build_object('recovered', v_n, 'grace_minutes', p_max_minutes),
      p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin',
      p_sim_run_id := p_sim_run_id);
  END IF;
  RETURN v_n;
END;
$function$


-- ===== ottoq_t4_coverage =====
CREATE OR REPLACE FUNCTION public.ottoq_t4_coverage(p_sim_run_id uuid)
 RETURNS TABLE(moving integer, covered integer, ratio numeric, open_legs integer, orphan_legs integer, states jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
WITH s AS (SELECT ottoq_twin_snapshot(p_sim_run_id) j),
veh AS (SELECT v->>'id' vid, v->>'state' st
          FROM s, jsonb_array_elements(j->'fleet'->'vehicles') v),
lg AS (SELECT DISTINCT l->>'vehicle_id' vid
         FROM s, jsonb_array_elements(j->'legs') l
        WHERE l->>'kind' = 'travel'),
mv AS (SELECT vid FROM veh WHERE st IN ('en_route_to_depot','en_route_to_deployment'))
SELECT (SELECT count(*) FROM mv)::int,
       (SELECT count(*) FROM mv WHERE vid IN (SELECT vid FROM lg))::int,
       CASE WHEN (SELECT count(*) FROM mv) = 0 THEN NULL
            ELSE round((SELECT count(*) FROM mv WHERE vid IN (SELECT vid FROM lg))::numeric
                       / (SELECT count(*) FROM mv), 3) END,
       (SELECT count(*) FROM lg)::int,
       (SELECT count(*) FROM lg WHERE vid NOT IN (SELECT vid FROM veh))::int,
       (SELECT jsonb_object_agg(st, n) FROM (SELECT st, count(*) n FROM veh GROUP BY st) x);
$function$


-- ===== ottoq_t4_step_and_sample =====
CREATE OR REPLACE FUNCTION public.ottoq_t4_step_and_sample(p_sim_run_id uuid, p_ticks integer DEFAULT 1)
 RETURNS TABLE(moving integer, covered integer, ratio numeric, open_legs integer, orphan_legs integer)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE i int; r record;
BEGIN
  FOR i IN 1..p_ticks LOOP
    PERFORM ottoq_cert_arm_step(p_sim_run_id, 1);
    SELECT * INTO r FROM ottoq_t4_coverage(p_sim_run_id);
    INSERT INTO ottoq_t4_coverage_samples(sim_run_id,moving,covered,ratio,open_legs,orphan_legs,states)
      VALUES (p_sim_run_id, r.moving, r.covered, r.ratio, r.open_legs, r.orphan_legs, r.states);
  END LOOP;
  RETURN QUERY SELECT s.moving, s.covered, s.ratio, s.open_legs, s.orphan_legs
    FROM ottoq_t4_coverage_samples s
   WHERE s.sim_run_id = p_sim_run_id ORDER BY s.id DESC LIMIT p_ticks;
END;
$function$


-- ===== ottoq_t_crit_bonf3 =====
CREATE OR REPLACE FUNCTION public.ottoq_t_crit_bonf3(p_df integer)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT CASE
    WHEN p_df <= 1 THEN 38.19 WHEN p_df = 2 THEN 7.65 WHEN p_df = 3 THEN 5.08
    WHEN p_df = 4 THEN 4.22  WHEN p_df = 5 THEN 3.81 WHEN p_df = 6 THEN 3.57
    WHEN p_df = 7 THEN 3.41  WHEN p_df = 8 THEN 3.31 WHEN p_df = 9 THEN 3.23
    WHEN p_df <= 14 THEN 3.05 WHEN p_df <= 19 THEN 2.95 WHEN p_df <= 29 THEN 2.86
    ELSE 2.74 END;  -- approaches z(0.9917)=2.39 asymptotically; kept conservative
$function$


-- ===== ottoq_tick_claimed_kw =====
CREATE OR REPLACE FUNCTION public.ottoq_tick_claimed_kw(p_sim_run_id uuid, p_tick_seq bigint, p_resource text DEFAULT 'grid_kw'::text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE(SUM(amount_kw), 0) FROM ottoq_tick_reservations
   WHERE sim_run_id = p_sim_run_id AND tick_seq = p_tick_seq AND resource = p_resource;
$function$


-- ===== ottoq_tick_invariance_arm =====
CREATE OR REPLACE FUNCTION public.ottoq_tick_invariance_arm(p_cert_seed bigint, p_tick_minutes numeric, p_sim_minutes numeric DEFAULT 120, p_max_seconds numeric DEFAULT 6.0, p_scenario text DEFAULT 'normal_day'::text, p_start_clock timestamp with time zone DEFAULT '2026-08-01 02:00:00+00'::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_arm ottoq_tick_invariance_arms%ROWTYPE;
  v_run ottoq_sim_runs%ROWTYPE; v_run_id uuid;
  v_target timestamptz; v_started timestamptz; v_ticks int := 0; v_done boolean;
BEGIN
  IF p_tick_minutes <= 0 THEN RETURN jsonb_build_object('ok',false,'reason','bad_tick_minutes'); END IF;

  SELECT * INTO v_arm FROM ottoq_tick_invariance_arms
   WHERE cert_seed = p_cert_seed AND tick_minutes = p_tick_minutes;

  IF NOT FOUND THEN
    -- identical seed + identical start clock; ONLY the tick length differs.
    -- fixed-mode tick length = tick_interval_seconds(30) * time_scale / 60 => time_scale = 2*minutes
    -- identical_fleet_reset: common random numbers. Every arm starts from the SAME
    -- seed-derived fleet state, so tick length is the only variable.
    PERFORM ottoq_tick_invariance_reset_fleet(
      (SELECT id FROM depots ORDER BY id LIMIT 1), p_cert_seed);
    v_run_id := ottoq_sim_start_run(p_scenario, p_start_clock, (p_tick_minutes * 2)::numeric,
                                    p_cert_seed, 'cert_harness');
    -- prime_identical_start_state: put the same fraction of the fleet on the road
    -- before tick 1. Seed + clock + fraction are identical across arms, so the ONLY
    -- difference between arms remains the tick length.
    BEGIN PERFORM ottoq_sim_prime_deployment(v_run_id, p_start_clock, 0.70);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm prime failed: %', SQLERRM; END;
    INSERT INTO ottoq_tick_invariance_arms (cert_seed, tick_minutes, sim_run_id, scenario_code, sim_minutes)
    VALUES (p_cert_seed, p_tick_minutes, v_run_id, p_scenario, p_sim_minutes);
    SELECT * INTO v_arm FROM ottoq_tick_invariance_arms
     WHERE cert_seed = p_cert_seed AND tick_minutes = p_tick_minutes;
  ELSIF v_arm.status = 'done' THEN
    RETURN jsonb_build_object('ok',true,'done',true,'already_complete',true,
                              'tick_minutes',p_tick_minutes,'metrics',v_arm.metrics);
  END IF;

  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = v_arm.sim_run_id;
  v_target := v_run.sim_clock_start + (p_sim_minutes || ' minutes')::interval;

  v_started := clock_timestamp();
  LOOP
    SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = v_arm.sim_run_id;
    EXIT WHEN v_run.sim_clock_current >= v_target OR v_run.status <> 'running';
    EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_started)) >= p_max_seconds;
    BEGIN PERFORM ottoq_sim_advance_tick(v_arm.sim_run_id);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm tick failed: %', SQLERRM; EXIT; END;
    v_ticks := v_ticks + 1;
  END LOOP;

  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = v_arm.sim_run_id;
  v_done := (v_run.sim_clock_current >= v_target) OR (v_run.status <> 'running');

  IF v_done THEN
    -- snapshot metrics BEFORE stopping (stop resets the depot and clears live state)
    UPDATE ottoq_tick_invariance_arms
       SET status='done', finished_at=now(), metrics = ottoq_tick_invariance_metrics(v_arm.sim_run_id)
     WHERE cert_seed=p_cert_seed AND tick_minutes=p_tick_minutes;
    -- release_depot_for_next_arm: one running run per depot, so hand the depot back
    BEGIN PERFORM ottoq_sim_stop_and_reset(v_arm.sim_run_id, 'tick_invariance_arm_complete');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm stop failed: %', SQLERRM; END;
  END IF;

  RETURN jsonb_build_object('ok',true,'done',v_done,'tick_minutes',p_tick_minutes,
    'sim_run_id', v_arm.sim_run_id, 'ticks_this_call', v_ticks,
    'sim_clock', v_run.sim_clock_current, 'target', v_target,
    'remaining_sim_minutes', GREATEST(0, ROUND(EXTRACT(EPOCH FROM (v_target - v_run.sim_clock_current))/60.0,1)));
END; $function$


-- ===== ottoq_tick_invariance_metrics =====
CREATE OR REPLACE FUNCTION public.ottoq_tick_invariance_metrics(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH r AS (SELECT * FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id),
  b AS (
    SELECT
      (SELECT count(*) FROM ottoq_vehicle_dispatches d WHERE d.sim_run_id = p_sim_run_id
                                                         AND d.status='completed')     AS completed_dispatches,
      (SELECT count(*) FROM ottoq_visit_needs n WHERE n.sim_run_id = p_sim_run_id)      AS visits,
      (SELECT count(*) FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
        WHERE n.sim_run_id = p_sim_run_id AND a->>'svc' = 'exterior_wash')              AS washes,
      (SELECT COALESCE(SUM(drive_km_total),0) FROM ottoq_vehicle_wear w
        WHERE w.sim_run_id = p_sim_run_id)                                              AS km,
      (SELECT COALESCE(SUM(energy_delivered_kwh),0) FROM ocpp_sessions s
        WHERE s.sim_run_id = p_sim_run_id)                                              AS kwh
  )
  SELECT jsonb_build_object(
    -- ---- invariants that must hold exactly ----
    'sim_minutes_elapsed', ROUND(EXTRACT(EPOCH FROM (r.sim_clock_current - r.sim_clock_start))/60.0, 2),
    'tick_count',          r.tick_count,
    'unsafe_blocks',       (SELECT count(*) FROM ottoq_rule_evaluations e
                             WHERE e.rule_code='SLA.001.min_soc_at_deployment' AND e.passed=false
                               AND e.evaluated_at >= r.started_at),
    -- ---- physics ----
    'drive_km_total',      ROUND(b.km::numeric,1),
    'soil_index_mean',     (SELECT ROUND(AVG(soil_index)::numeric,4) FROM ottoq_vehicle_wear w
                             WHERE w.sim_run_id = p_sim_run_id),
    -- ---- raw counts (retained: window-edge sensitive, do NOT read as rate bias) ----
    'completed_dispatches', b.completed_dispatches,
    'visits_created',       b.visits,
    'wash_atoms',           b.washes,
    'decisions',            (SELECT count(*) FROM ottoq_decisions d WHERE d.sim_run_id = p_sim_run_id),
    -- ---- NORMALISED: the honest scheduling instrument (edge divided out) ----
    'visits_per_dispatch', CASE WHEN b.completed_dispatches > 0
                                THEN ROUND((b.visits::numeric / b.completed_dispatches), 4) END,
    'washes_per_visit',    CASE WHEN b.visits > 0
                                THEN ROUND((b.washes::numeric / b.visits), 4) END,
    'kwh_per_100km',       CASE WHEN b.km > 0
                                THEN ROUND((b.kwh::numeric * 100.0 / b.km), 3) END
  )
  FROM r, b;
$function$


-- ===== ottoq_tick_invariance_report =====
CREATE OR REPLACE FUNCTION public.ottoq_tick_invariance_report(p_cert_seed bigint, p_tolerance_pct numeric DEFAULT 5.0)
 RETURNS TABLE(metric text, per_tick_size jsonb, spread_pct numeric, verdict text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH arms AS (
    SELECT a.tick_minutes, a.metrics FROM ottoq_tick_invariance_arms a
     WHERE a.cert_seed = p_cert_seed AND a.status='done'
  ), kv AS (
    SELECT e.key AS m, a.tick_minutes AS tm, NULLIF(e.value #>> '{}','')::numeric AS val
      FROM arms a, jsonb_each(a.metrics) e
     WHERE jsonb_typeof(e.value) = 'number'
  ), agg AS (
    SELECT kv.m,
           jsonb_object_agg(kv.tm::text || 'min', kv.val) AS vals,
           min(kv.val) AS lo, max(kv.val) AS hi, avg(kv.val) AS mean, count(*) AS n
      FROM kv GROUP BY kv.m
  )
  SELECT agg.m,
         agg.vals,
         CASE WHEN COALESCE(NULLIF(abs(agg.mean),0),0) = 0 THEN 0::numeric
              ELSE ROUND((100.0*(agg.hi-agg.lo)/abs(agg.mean))::numeric, 1) END,
         CASE WHEN agg.n < 2 THEN 'NEED >=2 ARMS'
              WHEN agg.m = 'tick_count' THEN 'EXPECTED TO DIFFER'
              WHEN COALESCE(NULLIF(abs(agg.mean),0),0) = 0 THEN 'INVARIANT (all zero)'
              WHEN (100.0*(agg.hi-agg.lo)/abs(agg.mean)) <= p_tolerance_pct THEN 'INVARIANT'
              ELSE 'TICK-COUPLED - investigate' END
    FROM agg ORDER BY 3 DESC NULLS LAST;
$function$


-- ===== ottoq_tick_invariance_reset_fleet =====
CREATE OR REPLACE FUNCTION public.ottoq_tick_invariance_reset_fleet(p_depot_id uuid, p_seed bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int;
BEGIN
  -- deterministic, seed-derived SoC in a deployable band; identical for every arm
  UPDATE vehicles v
     SET current_soc   = ROUND((85 + ottoq_sim_seeded_random(p_seed, 'inv:soc:' || v.id::text) * 14)::numeric, 1),
         current_state = 'offline'::vehicle_state,
         current_stall_id = NULL,
         last_state_change = now(),
         config = COALESCE(v.config,'{}'::jsonb) || jsonb_build_object('cycles_since_wash', 1)
   WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous';
  GET DIAGNOSTICS v_n = ROW_COUNT;

  UPDATE stalls SET current_vehicle_id = NULL, reserved_by = NULL,
                    reservation_expires_at = NULL, status = 'available'
   WHERE depot_id = p_depot_id AND status <> 'maintenance';
  RETURN v_n;
END; $function$


-- ===== ottoq_trigger_emergency_cascade =====
CREATE OR REPLACE FUNCTION public.ottoq_trigger_emergency_cascade(p_protocol_code text, p_depot_id uuid, p_triggered_by_actor_type text, p_triggered_by_actor_id text DEFAULT NULL::text, p_source_payload jsonb DEFAULT '{}'::jsonb, p_triggered_by_event_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_protocol         ottoq_emergency_protocols%ROWTYPE;
  v_invocation_id    UUID := gen_random_uuid();
  v_correlation      UUID := COALESCE(
                        NULLIF(current_setting('ottoq.correlation_id', TRUE), '')::UUID,
                        gen_random_uuid()
                      );
  v_event_id         UUID;
  v_action           JSONB;
  v_action_results   JSONB := '[]'::jsonb;
  v_action_status    TEXT;
  v_action_details   JSONB;
  v_outcome          TEXT := 'completed';
  v_affected_stalls  INTEGER := 0;
  v_affected_vehicles INTEGER := 0;
  v_affected_chargers INTEGER := 0;
BEGIN
  -- 1. Lookup protocol
  SELECT * INTO v_protocol
    FROM ottoq_emergency_protocols
   WHERE protocol_code = p_protocol_code AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OTTOQ_PROTOCOL_NOT_FOUND: %', p_protocol_code USING ERRCODE = 'P0001';
  END IF;

  -- 2. Emit "emergency.triggered" event FIRST (before any side effects)
  v_event_id := ottoq_record_event(
    p_actor_type        := p_triggered_by_actor_type,
    p_actor_id          := p_triggered_by_actor_id,
    p_event_type        := 'emergency.triggered',
    p_entity_type       := 'emergency_invocation',
    p_entity_id         := v_invocation_id,
    p_depot_id          := p_depot_id,
    p_payload           := jsonb_build_object(
                             'protocol_code', p_protocol_code,
                             'category', v_protocol.category,
                             'severity', v_protocol.severity,
                             'source', p_source_payload
                           ),
    p_severity          := v_protocol.severity,
    p_parent_event_id   := p_triggered_by_event_id,
    p_correlation_id    := v_correlation
  );

  -- 3. Insert invocation row
  INSERT INTO ottoq_emergency_invocations (
    invocation_id, protocol_code, triggered_at,
    triggered_by_actor_type, triggered_by_actor_id, triggered_by_event_id,
    source_payload, depot_id, affects_scope,
    outcome, linked_event_id, correlation_id
  ) VALUES (
    v_invocation_id, p_protocol_code, NOW(),
    p_triggered_by_actor_type, p_triggered_by_actor_id, p_triggered_by_event_id,
    p_source_payload, p_depot_id, v_protocol.affects_scope,
    'in_progress', v_event_id, v_correlation
  );

  -- 4. Execute cascade actions in order
  FOR v_action IN SELECT jsonb_array_elements(v_protocol.cascade_actions)
  LOOP
    BEGIN
      v_action_status := 'ok';
      v_action_details := '{}'::jsonb;

      CASE v_action ->> 'action'
        WHEN 'de_energize_all_chargers' THEN
          UPDATE ottoq_ocpp_chargers
             SET station_state = 'Unavailable',
                 station_state_changed_at = NOW()
           WHERE depot_id = p_depot_id;
          GET DIAGNOSTICS v_affected_chargers = ROW_COUNT;
          v_action_details := jsonb_build_object('chargers_de_energized', v_affected_chargers);

        WHEN 'sequester_all_vehicles' THEN
          -- Move all in-flow vehicles at this depot to emergency_staged
          BEGIN
            EXECUTE format('
              UPDATE vehicles SET current_state = ''emergency_staged''
               WHERE current_state IN (''queued'',''assigned'',''in_service'',''charging'',''washing'',''calibrating'',''staged_for_departure'')
                 AND id IN (SELECT current_vehicle_id FROM stalls WHERE depot_id = $1 AND current_vehicle_id IS NOT NULL)
            ') USING p_depot_id;
            GET DIAGNOSTICS v_affected_vehicles = ROW_COUNT;
          EXCEPTION WHEN OTHERS THEN
            v_affected_vehicles := 0;
          END;
          v_action_details := jsonb_build_object('vehicles_sequestered', v_affected_vehicles);

        WHEN 'lock_all_stalls' THEN
          BEGIN
            EXECUTE 'UPDATE stalls SET status = ''offline'' WHERE depot_id = $1 AND status <> ''offline'''
              USING p_depot_id;
            GET DIAGNOSTICS v_affected_stalls = ROW_COUNT;
          EXCEPTION WHEN OTHERS THEN
            v_affected_stalls := 0;
          END;
          v_action_details := jsonb_build_object('stalls_locked', v_affected_stalls);

        WHEN 'pause_arrivals' THEN
          -- Insert a grid_event-style marker; arrival logic checks for active
          -- 'arrival_pause' rows during admission.
          INSERT INTO ottoq_grid_events (
            depot_id, event_type, severity, effective_at, source, payload
          ) VALUES (
            p_depot_id, 'curtailment_request', 'safety_critical', NOW(),
            'emergency_cascade',
            jsonb_build_object('reason','arrival_pause_emergency',
                               'protocol_code', p_protocol_code,
                               'invocation_id', v_invocation_id)
          );
          v_action_details := jsonb_build_object('arrival_pause_set', TRUE);

        WHEN 'notify_actors' THEN
          -- Notification is downstream; we just emit an event other systems
          -- subscribe to. ottoq_event 'emergency.notify_actors' carries the list.
          PERFORM ottoq_record_event(
            p_actor_type     := 'ottoq_engine',
            p_event_type     := 'emergency.notify_actors',
            p_entity_type    := 'emergency_invocation',
            p_entity_id      := v_invocation_id,
            p_depot_id       := p_depot_id,
            p_payload        := jsonb_build_object(
                                  'protocol_code', p_protocol_code,
                                  'actors_to_notify', v_protocol.notify_actors,
                                  'webhooks', v_protocol.external_notify_webhooks
                                ),
            p_severity       := v_protocol.severity,
            p_parent_event_id := v_event_id,
            p_correlation_id := v_correlation
          );
          v_action_details := jsonb_build_object('notify_actors', v_protocol.notify_actors);

        WHEN 'engage_bess' THEN
          UPDATE ottoq_bess_units
             SET current_state = 'discharging'
           WHERE depot_id = p_depot_id
             AND current_state = 'idle'
             AND current_soc_pct > soc_min_floor_pct;
          GET DIAGNOSTICS v_action_details = ROW_COUNT;
          v_action_details := jsonb_build_object('bess_engaged_count', v_action_details);

        WHEN 'isolate_bess' THEN
          UPDATE ottoq_bess_units
             SET current_state = 'offline'
           WHERE depot_id = p_depot_id;
          v_action_details := jsonb_build_object('bess_isolated', TRUE);

        WHEN 'log_only' THEN
          -- Pure observation, no side effects
          v_action_details := jsonb_build_object('logged', TRUE);

        ELSE
          v_action_status := 'unknown_action';
          v_action_details := jsonb_build_object('unknown_action', v_action ->> 'action');
      END CASE;

    EXCEPTION WHEN OTHERS THEN
      v_action_status := 'failed';
      v_action_details := jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE);
      v_outcome := 'partial';
    END;

    v_action_results := v_action_results || jsonb_build_object(
      'action', v_action ->> 'action',
      'status', v_action_status,
      'details', v_action_details,
      'executed_at', NOW()
    );

    -- Per-action event for granular audit
    PERFORM ottoq_record_event(
      p_actor_type      := 'ottoq_engine',
      p_event_type      := 'emergency.action_executed',
      p_entity_type     := 'emergency_invocation',
      p_entity_id       := v_invocation_id,
      p_depot_id        := p_depot_id,
      p_payload         := jsonb_build_object(
                             'protocol_code', p_protocol_code,
                             'action', v_action ->> 'action',
                             'status', v_action_status,
                             'details', v_action_details
                           ),
      p_severity        := CASE WHEN v_action_status='ok' THEN 'info' ELSE 'critical' END,
      p_parent_event_id := v_event_id,
      p_correlation_id  := v_correlation
    );
  END LOOP;

  -- 5. Finalize invocation row
  UPDATE ottoq_emergency_invocations
     SET cascade_executed = v_action_results,
         outcome          = v_outcome
   WHERE invocation_id = v_invocation_id;

  -- 6. Emit completion event
  PERFORM ottoq_record_event(
    p_actor_type      := 'ottoq_engine',
    p_event_type      := 'emergency.cascade_complete',
    p_entity_type     := 'emergency_invocation',
    p_entity_id       := v_invocation_id,
    p_depot_id        := p_depot_id,
    p_payload         := jsonb_build_object(
                          'protocol_code', p_protocol_code,
                          'outcome', v_outcome,
                          'actions_executed', jsonb_array_length(v_action_results)
                        ),
    p_severity        := v_protocol.severity,
    p_parent_event_id := v_event_id,
    p_correlation_id  := v_correlation
  );

  RETURN v_invocation_id;
END;
$function$


-- ===== ottoq_twin_appointments =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_appointments(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_clock timestamptz; v_hour int; v_total int;
  v_reservations jsonb; v_inbound jsonb; v_phases jsonb; v_overnight jsonb; v_headline jsonb;
  v_charge_stalls int; v_recalled int; v_holdout int; v_returning int; v_booked int;
BEGIN
  SELECT depot_id, sim_clock_current INTO v_depot, v_clock
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN jsonb_build_object('error','no such run'); END IF;
  v_hour := EXTRACT(HOUR FROM v_clock AT TIME ZONE 'America/Chicago')::int;

  SELECT count(*) INTO v_total FROM vehicles WHERE home_depot_id=v_depot AND category='autonomous';
  SELECT count(*) INTO v_charge_stalls FROM stalls WHERE depot_id=v_depot AND stall_type IN ('dcfc','l2');

  SELECT jsonb_agg(jsonb_build_object(
           'stall_id', s.id, 'stall_code', s.stall_code, 'stall_type', s.stall_type,
           'av_id', v.display_name, 'veh_state', v.current_state::text, 'soc', round(v.current_soc,0),
           'expires_at', s.reservation_expires_at,
           'inbound', (v.current_state::text = 'en_route_to_depot'),
           'occupied', (s.current_vehicle_id IS NOT NULL))
         ORDER BY s.stall_type, s.stall_code)
    INTO v_reservations
    FROM stalls s JOIN vehicles v ON v.id = s.reserved_by
   WHERE s.depot_id = v_depot AND s.reserved_by IS NOT NULL
     AND (s.reservation_expires_at IS NULL OR s.reservation_expires_at > v_clock);

  SELECT jsonb_agg(jsonb_build_object(
           'av_id', v.display_name, 'soc', round(v.current_soc,0),
           'return_trigger', d.return_trigger,
           'booked_stall_type', d.return_evidence->'appointment'->>'stall_type',
           'secured', COALESCE((d.return_evidence->'appointment'->>'secured')::boolean, false),
           'eta_min', round(d.return_eta_minutes,0),
           'workflow', (SELECT COALESCE(jsonb_agg(a->>'svc'), '[]'::jsonb)
                          FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                         WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                           AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')))
         ORDER BY v.current_soc)
    INTO v_inbound
    FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id = d.vehicle_id
   WHERE d.sim_run_id = p_sim_run_id AND d.status = 'returning';

  SELECT jsonb_object_agg(phase, n) INTO v_phases FROM (
    SELECT CASE
             WHEN cs IN ('deployed','en_route_to_deployment') THEN 'deployed'
             WHEN cs = 'en_route_to_depot' THEN 'inbound'
             WHEN cs = 'arrived_at_gate' THEN 'at_gate'
             WHEN cs IN ('charging_dcfc','charging_l2') THEN 'charging'
             WHEN cs = 'in_wash_bay' THEN 'washing'
             WHEN cs = 'in_service_bay' THEN 'servicing'
             WHEN cs IN ('staged_awaiting_service','staged_for_departure','charge_complete_holding') THEN 'staged_ready'
             ELSE 'other' END AS phase, count(*) n
      FROM (SELECT current_state::text AS cs FROM vehicles
             WHERE home_depot_id=v_depot AND category='autonomous') q
     GROUP BY 1) z;

  SELECT COALESCE(sum((payload->>'recalled')::int),0) INTO v_recalled
    FROM ottoq_events
   WHERE sim_run_id=p_sim_run_id AND event_type='twin.overnight_surplus_recall'
     AND occurred_at >= v_clock - interval '8 hours';
  SELECT count(*) INTO v_holdout FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id=d.vehicle_id
   WHERE d.sim_run_id=p_sim_run_id AND d.status='active'
     AND ottoq_is_overnight_holdout(v.id, p_sim_run_id, v_clock, 1);
  v_overnight := jsonb_build_object(
    'window_active', (v_hour >= 22 OR v_hour < 6), 'hour_cst', v_hour,
    'recalled_tonight', v_recalled, 'holdout_still_out', v_holdout);

  SELECT count(*) FILTER (WHERE status='returning'),
         count(*) FILTER (WHERE status='returning' AND return_evidence ? 'appointment')
    INTO v_returning, v_booked
    FROM ottoq_vehicle_dispatches WHERE sim_run_id=p_sim_run_id AND status='returning';
  v_headline := jsonb_build_object(
    'fleet_total', v_total, 'charge_stalls', v_charge_stalls,
    'veh_per_charger', round(v_total::numeric / NULLIF(v_charge_stalls,0), 1),
    'inbound_count', COALESCE(v_returning,0), 'booked_before_arrival', COALESCE(v_booked,0),
    'reservations_held', COALESCE(jsonb_array_length(v_reservations),0),
    'unsafe_deploys_run', COALESCE((SELECT count(*) FROM ottoq_deploy_log
                                     WHERE sim_run_id=p_sim_run_id AND NOT is_productive),0));

  RETURN jsonb_build_object(
    'sim_run_id', p_sim_run_id, 'sim_clock', v_clock, 'hour_cst', v_hour,
    'headline', v_headline, 'phases', COALESCE(v_phases, '{}'::jsonb),
    'reservations', COALESCE(v_reservations, '[]'::jsonb),
    'inbound', COALESCE(v_inbound, '[]'::jsonb), 'overnight', v_overnight);
END;
$function$


-- ===== ottoq_twin_arrival_soc_drain =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_arrival_soc_drain(p_run uuid, p_clock timestamp with time zone)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v jsonb;
BEGIN
  v := ottoq_twin_climate_stress(p_run, (p_clock::date - DATE '2020-01-01')::int);
  RETURN COALESCE((v->>'heat_stress')::numeric,0) * 8 + COALESCE((v->>'cold_stress')::numeric,0) * 12;
END $function$


-- ===== ottoq_twin_boot_manifest =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_boot_manifest(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'sim_run_id', r.sim_run_id,
    'scenario', r.scenario_code,
    'status', r.status,
    'tick_count', r.tick_count,
    'random_seed', r.random_seed,
    'boot_draw', r.payload->'boot_draw')
  FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
$function$


-- ===== ottoq_twin_climate_stress =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_climate_stress(p_run_id uuid, p_sim_day integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_temp numeric; v_clock timestamptz; v_precip numeric;
BEGIN
  SELECT value INTO v_temp FROM ottoq_variability_cards
   WHERE sim_run_id=p_run_id AND var_key='ambient_temp_c' AND scope_instance='global' AND bucket_key='day:'||p_sim_day LIMIT 1;
  -- p_sim_day is on the DATE '2020-01-01' epoch (all callers pass date-diff),
  -- so the reconstructed clock lands on the correct calendar date/month.
  v_clock := (DATE '2020-01-01' + p_sim_day)::timestamptz;
  -- ONE precipitation truth: the same Markov daily-budget card the hourly
  -- weather disaggregates (feed-agent precip_unified).
  v_precip := ottoq_precip_daily_mm(p_run_id, v_clock);
  RETURN jsonb_build_object(
    'ambient_c',     v_temp,
    'heat_stress',   GREATEST(0, LEAST(1, (v_temp - 28) / 10.0)),
    'cold_stress',   GREATEST(0, LEAST(1, (5 - v_temp)  / 15.0)),
    'precip_mm',     COALESCE(v_precip,0),
    'precip_stress', GREATEST(0, LEAST(1, COALESCE(v_precip,0) / 15.0)));
END
$function$


-- ===== ottoq_twin_deal =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_deal(p_run_id uuid, p_var_key text, p_scope_instance text, p_sim_clock timestamp with time zone, p_sim_day integer DEFAULT 0, p_tick bigint DEFAULT 0, p_segment text DEFAULT 'global'::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_lifespan text; v_min numeric; v_max numeric;
  v_seed bigint; v_bucket text; v_val numeric; v_salt text;
  v_block_hrs constant int := 4;
BEGIN
  SELECT lifespan, min_value, max_value INTO v_lifespan, v_min, v_max
    FROM ottoq_variability_catalog WHERE var_key = p_var_key;
  IF v_lifespan IS NULL THEN RETURN NULL; END IF;           -- unknown variable

  SELECT COALESCE(random_seed, 42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_run_id;
  v_seed := COALESCE(v_seed, 42);

  -- the lifespan epoch (when a fresh card is dealt)
  v_bucket := CASE v_lifespan
    WHEN 'run'   THEN 'run'
    WHEN 'day'   THEN 'day:' || p_sim_day
    WHEN 'block' THEN 'block:' || p_sim_day || ':' || (EXTRACT(HOUR FROM p_sim_clock)::int / v_block_hrs)
    ELSE v_lifespan || ':' || p_scope_instance              -- session/arrival/visit/trip/event: instance = epoch
  END;

  SELECT value INTO v_val FROM ottoq_variability_cards
   WHERE sim_run_id = p_run_id AND var_key = p_var_key
     AND scope_instance = p_scope_instance AND bucket_key = v_bucket;
  IF FOUND THEN RETURN v_val; END IF;                       -- card still valid → hold it

  -- deal a fresh card: calibrated draw where a fitted distribution exists, else uniform over bounds
  v_salt := p_var_key || '|' || p_scope_instance || '|' || v_bucket;
  v_val := ottoq_sample_calibrated(p_var_key, p_segment, v_seed, v_salt);
  IF v_val IS NULL THEN
    v_val := COALESCE(v_min,0)
           + ottoq_crn_draw(v_seed, p_var_key, v_bucket, p_sim_day, 0)
             * (COALESCE(v_max,1) - COALESCE(v_min,0));
  END IF;

  UPDATE ottoq_variability_cards SET active = false
    WHERE sim_run_id = p_run_id AND var_key = p_var_key AND scope_instance = p_scope_instance AND active;
  INSERT INTO ottoq_variability_cards(sim_run_id, var_key, scope_instance, lifespan, bucket_key, value, drawn_at_clock, drawn_at_tick)
    VALUES (p_run_id, p_var_key, p_scope_instance, v_lifespan, v_bucket, v_val, p_sim_clock, p_tick)
    ON CONFLICT (sim_run_id, var_key, scope_instance, bucket_key) DO UPDATE SET active = true
    RETURNING value INTO v_val;
  RETURN v_val;
END $function$


-- ===== ottoq_twin_deal_eta_card =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_deal_eta_card(p_run_id uuid, p_dispatch_id uuid, p_sim_day integer DEFAULT 0, p_tick bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed bigint; v_bucket text := 'trip:' || p_dispatch_id::text;
  v_existing jsonb; v_mult numeric; v_u numeric; v_us numeric; v_ut numeric;
  v_will boolean; v_delay numeric; v_cause text; v_trig numeric; v_meta jsonb;
  v_clim jsonb; v_weather numeric;
  v_base_delay constant numeric := 0.18;
BEGIN
  SELECT meta INTO v_existing FROM ottoq_variability_cards
    WHERE sim_run_id=p_run_id AND var_key='eta_delay' AND scope_instance=p_dispatch_id::text AND bucket_key=v_bucket;
  IF FOUND THEN RETURN v_existing; END IF;

  SELECT COALESCE(random_seed,42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id=p_run_id;
  v_seed := COALESCE(v_seed,42);
  v_mult := COALESCE(ottoq_profile_rate_mult(p_run_id,'eta_delay'),1);   -- own knob (congestion deck)

  -- correlation web: cold + wet day → more & worse traffic delays (real NOAA-fed climate regime)
  v_clim := ottoq_twin_climate_stress(p_run_id, p_sim_day);
  v_weather := 1 + COALESCE((v_clim->>'cold_stress')::numeric,0)*0.6
                 + COALESCE((v_clim->>'precip_stress')::numeric,0)*1.0;

  v_u  := ottoq_crn_draw(v_seed,'eta_delay_will',    p_dispatch_id::text, p_sim_day, p_tick);
  v_us := ottoq_crn_draw(v_seed,'eta_delay_sev',     p_dispatch_id::text, p_sim_day, p_tick);
  v_ut := ottoq_crn_draw(v_seed,'eta_delay_trigger', p_dispatch_id::text, p_sim_day, p_tick);

  v_will := v_u < LEAST(0.95, v_base_delay * v_mult * v_weather);
  v_us   := LEAST(1, v_us + (v_weather - 1) * 0.12);   -- bad weather nudges toward heavy/accident
  IF    v_us < 0.65 THEN v_delay := 5  + v_us/0.65*15;           v_cause := 'congestion';
  ELSIF v_us < 0.90 THEN v_delay := 20 + (v_us-0.65)/0.25*25;    v_cause := 'heavy_traffic';
  ELSE                   v_delay := 45 + (v_us-0.90)/0.10*45;    v_cause := 'accident';
  END IF;
  v_trig := 0.30 + v_ut*0.60;

  v_meta := jsonb_build_object('will_delay', v_will, 'delay_min', round(v_delay), 'cause', v_cause,
    'trigger_progress', round(v_trig,2), 'applied', false,
    'weather_mult', round(v_weather,2), 'precip_mm', round(COALESCE((v_clim->>'precip_mm')::numeric,0),1));
  INSERT INTO ottoq_variability_cards(sim_run_id,var_key,scope_instance,lifespan,bucket_key,value,meta,drawn_at_tick)
    VALUES (p_run_id,'eta_delay',p_dispatch_id::text,'trip',v_bucket, CASE WHEN v_will THEN round(v_delay) ELSE 0 END, v_meta, p_tick)
    ON CONFLICT (sim_run_id,var_key,scope_instance,bucket_key) DO UPDATE SET meta=EXCLUDED.meta
    RETURNING meta INTO v_meta;
  RETURN v_meta;
END $function$


-- ===== ottoq_twin_deal_fault_card =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_deal_fault_card(p_run_id uuid, p_session_id uuid, p_soc_start numeric, p_target_soc numeric, p_sim_clock timestamp with time zone, p_sim_day integer DEFAULT 0, p_tick bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed bigint; v_bucket text := 'session:' || p_session_id::text;
  v_existing jsonb; v_mult numeric; v_will boolean; v_trigger numeric; v_mode text;
  v_u_fault numeric; v_u_trig numeric; v_u_mode numeric; v_meta jsonb; v_heat numeric;
  v_start numeric := COALESCE(p_soc_start, 20); v_target numeric := COALESCE(p_target_soc, 90);
  v_plan jsonb; v_base_fault numeric := 0.05;
  v_charger_id uuid; v_mtbf numeric; v_hazard numeric := 1.0; v_p numeric;
  v_repair_min numeric; v_mode_mult numeric; v_staffed numeric;
BEGIN
  SELECT meta INTO v_existing FROM ottoq_variability_cards
    WHERE sim_run_id = p_run_id AND var_key = 'charger_fault'
      AND scope_instance = p_session_id::text AND bucket_key = v_bucket;
  IF FOUND THEN RETURN v_existing; END IF;

  SELECT COALESCE(random_seed, 42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_run_id;
  v_seed := COALESCE(v_seed, 42);
  v_mult := COALESCE(ottoq_profile_rate_mult(p_run_id, 'charger_fault'), 1);
  v_heat := COALESCE((ottoq_twin_climate_stress(p_run_id,
              (p_sim_clock::date - DATE '2020-01-01'))->>'heat_stress')::numeric, 0);

  -- feed-agent plan (falls back to legacy constants when absent)
  v_plan := ottoq_feed_plan('charger_fault_repair');
  IF v_plan IS NOT NULL THEN
    v_base_fault := LEAST(GREATEST((v_plan->>'base_session_fault_p')::numeric,
                    (v_plan->'base_clamp'->>0)::numeric), (v_plan->'base_clamp'->>1)::numeric);
  END IF;

  -- per-CHARGER MTBF hazard: one run-lifespan card per charger from the fitted
  -- days_between_faults grid — lemon chargers fault often, golden ones rarely.
  SELECT st.ocpp_charger_id INTO v_charger_id
    FROM ocpp_sessions s JOIN stalls st ON st.id = s.stall_id WHERE s.id = p_session_id;
  IF v_plan IS NOT NULL AND v_charger_id IS NOT NULL THEN
    SELECT value INTO v_mtbf FROM ottoq_variability_cards
     WHERE sim_run_id = p_run_id AND var_key = 'charger_mtbf_days'
       AND scope_instance = v_charger_id::text AND bucket_key = 'run';
    IF v_mtbf IS NULL THEN
      v_mtbf := ottoq_sample_calibrated('days_between_faults', 'global', v_seed, 'mtbf:' || v_charger_id::text);
      IF v_mtbf IS NOT NULL THEN
        INSERT INTO ottoq_variability_cards(sim_run_id, var_key, scope_instance, lifespan, bucket_key, value, meta, drawn_at_clock, drawn_at_tick)
        VALUES (p_run_id, 'charger_mtbf_days', v_charger_id::text, 'run', 'run', round(v_mtbf, 2),
                jsonb_build_object('source', 'charger_reliability.days_between_faults', 'plan', 'charger_fault_repair.v1'),
                p_sim_clock, p_tick)
        ON CONFLICT (sim_run_id, var_key, scope_instance, bucket_key) DO NOTHING;
      END IF;
    END IF;
    IF v_mtbf IS NOT NULL AND v_mtbf > 0 THEN
      v_hazard := LEAST(GREATEST((v_plan->'mtbf'->>'median_days')::numeric / v_mtbf,
                  (v_plan->'mtbf'->'hazard_scale_clamp'->>0)::numeric),
                  (v_plan->'mtbf'->'hazard_scale_clamp'->>1)::numeric);
    END IF;
  END IF;

  v_u_fault := ottoq_crn_draw(v_seed, 'charger_fault_card',    p_session_id::text, p_sim_day, p_tick);
  v_u_trig  := ottoq_crn_draw(v_seed, 'charger_fault_trigger', p_session_id::text, p_sim_day, p_tick);
  v_u_mode  := ottoq_crn_draw(v_seed, 'charger_fault_mode',    p_session_id::text, p_sim_day, p_tick);

  v_p := v_base_fault * v_mult * (1 + v_heat * 1.5) * v_hazard;
  IF v_plan IS NOT NULL THEN
    v_p := LEAST(GREATEST(v_p, (v_plan->'mtbf'->'per_session_p_clamp'->>0)::numeric),
                 (v_plan->'mtbf'->'per_session_p_clamp'->>1)::numeric);
  ELSE
    v_p := LEAST(0.95, v_p);
  END IF;

  v_will    := v_u_fault < v_p;
  v_trigger := v_start + v_u_trig * GREATEST(1, v_target - v_start);
  v_mode    := CASE
    WHEN v_u_mode < 0.25 THEN 'fault.connector_cable'
    WHEN v_u_mode < 0.45 THEN 'fault.communication_dropout'
    WHEN v_u_mode < 0.55 THEN 'fault.station_hardware'
    WHEN v_u_mode < 0.60 THEN 'fault.ground_fault_safety'
    WHEN v_u_mode < 0.70 THEN 'fault.thermal_emergency'
    ELSE 'fault.session_aborted_other' END;

  -- repair duration: fitted repair_days grid × staffed-depot factor × mode mult
  IF v_will AND v_plan IS NOT NULL THEN
    v_staffed := (v_plan->'repair'->>'depot_staffed_factor')::numeric;
    v_mode_mult := COALESCE((v_plan->'repair'->'mode_multipliers'->>v_mode)::numeric, 1.0);
    v_repair_min := ottoq_sample_calibrated('repair_days', 'global', v_seed, 'repair:' || p_session_id::text);
    IF v_repair_min IS NOT NULL THEN
      v_repair_min := round(v_repair_min * 1440.0 * v_staffed * v_mode_mult);
      v_repair_min := LEAST(GREATEST(v_repair_min, (v_plan->'repair'->'minutes_clamp'->>0)::numeric),
                            (v_plan->'repair'->'minutes_clamp'->>1)::numeric);
    END IF;
  END IF;

  v_meta := jsonb_build_object('will_fault', v_will, 'trigger_soc', round(v_trigger,1),
    'fault_mode', v_mode, 'soc_start', round(v_start,1), 'rate_mult', round(v_mult,2),
    'heat_stress', round(v_heat,2),
    'hazard_scale', round(v_hazard,2), 'charger_mtbf_days', round(COALESCE(v_mtbf,0),1),
    'session_fault_p', round(v_p,4), 'repair_minutes', v_repair_min,
    'plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'charger_fault_repair.v1' END);
  INSERT INTO ottoq_variability_cards(sim_run_id, var_key, scope_instance, lifespan, bucket_key, value, meta, drawn_at_clock, drawn_at_tick)
    VALUES (p_run_id, 'charger_fault', p_session_id::text, 'session', v_bucket, CASE WHEN v_will THEN 1 ELSE 0 END, v_meta, p_sim_clock, p_tick)
    ON CONFLICT (sim_run_id, var_key, scope_instance, bucket_key) DO UPDATE SET meta = EXCLUDED.meta
    RETURNING meta INTO v_meta;
  RETURN v_meta;
END
$function$


-- ===== ottoq_twin_depot_layout =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_depot_layout(p_depot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_out JSONB;
BEGIN
  SELECT jsonb_build_object(
    'depot', (
      SELECT jsonb_build_object(
        'id', d.id, 'name', d.name,
        'origin_lat', d.origin_lat, 'origin_lng', d.origin_lng
      ) FROM depots d WHERE d.id = p_depot_id
    ),
    'structures', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'code', s.structure_code, 'kind', s.structure_kind, 'title', s.title,
        'x_ft', s.origin_x_ft, 'y_ft', s.origin_y_ft,
        'width_ft', s.width_ft, 'length_ft', s.length_ft,
        'height_ft', s.height_ft, 'rotation_deg', s.rotation_deg
      ) ORDER BY s.structure_code)
      FROM ottoq_site_structures s WHERE s.depot_id = p_depot_id
    ), '[]'::jsonb),
    'stalls', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', st.id, 'code', st.stall_code, 'type', st.stall_type,
        'zone', st.zone, 'canopy', st.canopy_code, 'covered', st.covered,
        'x', st.relative_x, 'y', st.relative_y, 'heading', st.heading_degrees,
        'connector_kw', st.connector_max_kw
      ) ORDER BY st.stall_code)
      FROM stalls st WHERE st.depot_id = p_depot_id
    ), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END;
$function$


-- ===== ottoq_twin_events_window =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_events_window(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run   ottoq_sim_runs%ROWTYPE;
  v_min   numeric;
  v_out   jsonb;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'sim_run not found'); END IF;
  v_min := NULLIF(EXTRACT(EPOCH FROM (v_run.sim_clock_current - v_run.sim_clock_start)) / 60.0, 0);

  WITH sig AS (
    SELECT event_type, severity, occurred_at, payload FROM ottoq_events
     WHERE sim_run_id = p_sim_run_id
       AND event_type NOT IN (
         'twin.bess_dispatch','twin.weather_tick','twin.solar_tick','twin.grid_tick',
         'twin.sim_tick_advanced','twin.telemetry_emitted','twin.bess_soh_degradation')),
  started AS (SELECT payload p FROM sig WHERE event_type = 'charge.session_started'),
  ended   AS (SELECT payload p FROM sig WHERE event_type = 'charge.session_completed'),
  faulted AS (SELECT payload p FROM sig WHERE event_type = 'charge.session_faulted'),
  delayed AS (SELECT payload p FROM sig WHERE event_type = 'fleet.arrival_delayed'),
  excepted AS (SELECT payload p FROM sig WHERE event_type LIKE 'vehicle.exception%'),
  valve   AS (SELECT payload p, occurred_at FROM sig WHERE event_type = 'twin.rush_valve_hold'),
  fcast   AS (SELECT payload p, occurred_at FROM sig WHERE event_type = 'ottoq.arrival_forecast'
               ORDER BY occurred_at DESC LIMIT 1)
  SELECT jsonb_build_object(
    'window', jsonb_build_object(
      'basis','run_to_date',
      'signal_events',(SELECT count(*) FROM sig),
      'first_at',(SELECT min(occurred_at) FROM sig),
      'last_at',(SELECT max(occurred_at) FROM sig),
      'sim_minutes_elapsed', v_min),
    'by_type', COALESCE((SELECT jsonb_object_agg(event_type,n) FROM (SELECT event_type,count(*) n FROM sig GROUP BY 1) t),'{}'::jsonb),
    'by_severity', COALESCE((SELECT jsonb_object_agg(severity,n) FROM (SELECT severity,count(*) n FROM sig GROUP BY 1) s),'{}'::jsonb),
    'reliability', jsonb_build_object(
      'charge_sessions',(SELECT count(*) FROM started),
      'charge_faults',(SELECT count(*) FROM faulted),
      'charge_fault_rate',(SELECT CASE WHEN count(*)=0 THEN NULL ELSE round((SELECT count(*) FROM faulted)::numeric/count(*),4) END FROM started),
      'fault_reasons', COALESCE((SELECT jsonb_object_agg(reason,n) FROM (SELECT COALESCE(p->>'reason','unspecified') reason,count(*) n FROM faulted GROUP BY 1) fr),'{}'::jsonb),
      'repair_minutes_total',(SELECT CASE WHEN count(*) FILTER (WHERE p->>'repair_minutes' IS NOT NULL)=0 THEN NULL ELSE sum((p->>'repair_minutes')::numeric) END FROM faulted),
      'arrival_delays',(SELECT count(*) FROM delayed),
      'delay_min_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'delay_min')::numeric)::numeric,1) FROM delayed WHERE p->>'delay_min' IS NOT NULL),
      'delay_causes', COALESCE((SELECT jsonb_object_agg(cause,n) FROM (SELECT COALESCE(p->>'cause','unspecified') cause,count(*) n FROM delayed GROUP BY 1) dc),'{}'::jsonb),
      'stranded_recharges',(SELECT count(*) FROM sig WHERE event_type='twin.recharge_stranded'),
      'tow_events',(SELECT count(*) FROM sig WHERE event_type LIKE 'vehicle.tow%'),
      'exceptions_by_severity', COALESCE((SELECT jsonb_object_agg(sev,n) FROM (SELECT COALESCE(p->>'severity','unspecified') sev,count(*) n FROM excepted GROUP BY 1) es),'{}'::jsonb),
      'faults_per_sim_hour',(SELECT CASE WHEN v_min IS NULL THEN NULL ELSE round(count(*)*60.0/v_min,3) END FROM faulted),
      'delays_per_sim_hour',(SELECT CASE WHEN v_min IS NULL THEN NULL ELSE round(count(*)*60.0/v_min,3) END FROM delayed)),
    'charging', jsonb_build_object(
      'target_soc_p50',(SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'soc_target')::numeric) FROM started WHERE p->>'soc_target' IS NOT NULL),
      'soc_start_p50',(SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'soc_start')::numeric) FROM started WHERE p->>'soc_start' IS NOT NULL),
      'charge_curve_ratio_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'initial_rate_kw')::numeric/NULLIF((p->>'max_rate_kw')::numeric,0))::numeric,3) FROM started WHERE p->>'initial_rate_kw' IS NOT NULL AND p->>'max_rate_kw' IS NOT NULL),
      'battery_temp_c_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'battery_temp_c')::numeric)::numeric,1) FROM started WHERE p->>'battery_temp_c' IS NOT NULL),
      'battery_soh_pct_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'battery_soh_pct')::numeric)::numeric,2) FROM started WHERE p->>'battery_soh_pct' IS NOT NULL),
      'sessions_completed',(SELECT count(*) FROM ended),
      'energy_kwh_total',(SELECT CASE WHEN count(*) FILTER (WHERE p->>'energy_kwh' IS NOT NULL)=0 THEN NULL ELSE round(sum((p->>'energy_kwh')::numeric),2) END FROM ended),
      'avg_power_kw_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'avg_power_kw')::numeric)::numeric,2) FROM ended WHERE p->>'avg_power_kw' IS NOT NULL),
      'session_duration_s_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'duration_s')::numeric)::numeric,1) FROM ended WHERE p->>'duration_s' IS NOT NULL),
      'auto_rerouted',(SELECT count(*) FILTER (WHERE (p->>'auto_rerouted')::boolean) FROM ended)),
    'demand_forecast',(SELECT jsonb_build_object(
        'at',f.occurred_at,'horizon_min',(f.p->>'horizon_min')::numeric,
        'incoming_count',(f.p->>'incoming_count')::numeric,
        'charge_needed_count',(f.p->>'charge_needed_count')::numeric,
        'predicted_charge_kw',(f.p->>'predicted_charge_kw')::numeric,
        'predicted_charge_kwh',(f.p->>'predicted_charge_kwh')::numeric) FROM fcast f),
    'throughput', jsonb_build_object(
      'valve_holds',(SELECT count(*) FROM valve),
      'held_total',(SELECT CASE WHEN count(*) FILTER (WHERE p->>'held' IS NOT NULL)=0 THEN NULL ELSE sum((p->>'held')::numeric) END FROM valve),
      'released_total',(SELECT CASE WHEN count(*) FILTER (WHERE p->>'released' IS NOT NULL)=0 THEN NULL ELSE sum((p->>'released')::numeric) END FROM valve),
      'cap_last',(SELECT (p->>'cap')::numeric FROM valve ORDER BY occurred_at DESC LIMIT 1))
  ) INTO v_out;
  RETURN v_out;
END;
$function$

-- ===== ottoq_twin_fleet_condition =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_fleet_condition(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run   ottoq_sim_runs%ROWTYPE;
  v_out   jsonb;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'sim_run not found');
  END IF;

  WITH fleet AS (
    SELECT v.id,
           v.av_api_vehicle_id AS av_id,
           COALESCE(v.config, '{}'::jsonb) AS cfg
      FROM vehicles v
     WHERE v.category = 'autonomous'
       AND v.home_depot_id = v_run.depot_id
  ), rows AS (
    SELECT id, av_id,
           (NULLIF(cfg->>'battery_soh_pct',      ''))::numeric AS battery_soh_pct,
           (NULLIF(cfg->>'consumption_scalar',   ''))::numeric AS consumption_scalar,
           (NULLIF(cfg->>'charge_curve_scalar',  ''))::numeric AS charge_curve_scalar,
           (NULLIF(cfg->>'soil_rate',            ''))::numeric AS soil_rate,
           (NULLIF(cfg->>'pm_interval_km',       ''))::numeric AS pm_interval_km,
           (NULLIF(cfg->>'calib_interval_h',     ''))::numeric AS calib_interval_h,
           (NULLIF(cfg->>'service_speed_scalar', ''))::numeric AS service_speed_scalar,
           (NULLIF(cfg->>'wash_cadence_cycles',  ''))::numeric AS wash_cadence_cycles,
           (NULLIF(cfg->>'cycles_since_wash',    ''))::numeric AS cycles_since_wash,
           cfg->>'condition_drawn_run' AS drawn_run
      FROM fleet
  )
  SELECT jsonb_build_object(
    'fleet_size', (SELECT count(*) FROM rows),
    'with_condition', (SELECT count(*) FROM rows WHERE battery_soh_pct IS NOT NULL),
    'drawn_for_this_run', (
      SELECT CASE
        WHEN count(*) FILTER (WHERE drawn_run IS NOT NULL) = 0 THEN NULL
        ELSE bool_and(drawn_run = p_sim_run_id::text) FILTER (WHERE drawn_run IS NOT NULL)
      END FROM rows),
    'drawn_run_ids', (
      SELECT jsonb_agg(DISTINCT drawn_run) FROM rows WHERE drawn_run IS NOT NULL),
    'vehicles', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'vehicle_id',           id,
        'av_id',                av_id,
        'battery_soh_pct',      battery_soh_pct,
        'consumption_scalar',   consumption_scalar,
        'charge_curve_scalar',  charge_curve_scalar,
        'soil_rate',            soil_rate,
        'pm_interval_km',       pm_interval_km,
        'calib_interval_h',     calib_interval_h,
        'service_speed_scalar', service_speed_scalar,
        'wash_cadence_cycles',  wash_cadence_cycles,
        'cycles_since_wash',    cycles_since_wash,
        'wash_due_ratio', CASE
          WHEN wash_cadence_cycles IS NULL OR wash_cadence_cycles = 0 THEN NULL
          ELSE round(cycles_since_wash / wash_cadence_cycles, 3) END)
        ORDER BY av_id)
      FROM rows), '[]'::jsonb),
    'spread', (
      SELECT jsonb_object_agg(k, stat) FROM (
        SELECT 'battery_soh_pct' AS k, ottoq_twin_spread_stat(array_agg(battery_soh_pct)) AS stat FROM rows
        UNION ALL SELECT 'consumption_scalar',   ottoq_twin_spread_stat(array_agg(consumption_scalar))   FROM rows
        UNION ALL SELECT 'charge_curve_scalar',  ottoq_twin_spread_stat(array_agg(charge_curve_scalar))  FROM rows
        UNION ALL SELECT 'soil_rate',            ottoq_twin_spread_stat(array_agg(soil_rate))            FROM rows
        UNION ALL SELECT 'pm_interval_km',       ottoq_twin_spread_stat(array_agg(pm_interval_km))       FROM rows
        UNION ALL SELECT 'calib_interval_h',     ottoq_twin_spread_stat(array_agg(calib_interval_h))     FROM rows
        UNION ALL SELECT 'service_speed_scalar', ottoq_twin_spread_stat(array_agg(service_speed_scalar)) FROM rows
        UNION ALL SELECT 'wash_cadence_cycles',  ottoq_twin_spread_stat(array_agg(wash_cadence_cycles))  FROM rows
      ) s)
  ) INTO v_out;

  RETURN v_out;
END;
$function$


-- ===== ottoq_twin_incident_weather_mult =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_incident_weather_mult(p_run uuid, p_clock timestamp with time zone)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v jsonb;
BEGIN
  v := ottoq_twin_climate_stress(p_run, (p_clock::date - DATE '2020-01-01')::int);
  RETURN 1 + COALESCE((v->>'cold_stress')::numeric,0) * 0.4 + COALESCE((v->>'precip_stress')::numeric,0) * 0.8;
END $function$


-- ===== ottoq_twin_ingest_refresh =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_ingest_refresh()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_anon text; v_eia text; v_noaa text;
  base text := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-twin-ingest';
BEGIN
  SELECT decrypted_secret INTO v_anon FROM vault.decrypted_secrets WHERE name='ottoq_anon_key' LIMIT 1;
  SELECT decrypted_secret INTO v_eia  FROM vault.decrypted_secrets WHERE name='eia_api_key'    LIMIT 1;
  SELECT decrypted_secret INTO v_noaa FROM vault.decrypted_secrets WHERE name='noaa_cdo_token' LIMIT 1;
  IF v_anon IS NULL THEN RAISE WARNING 'twin_ingest_refresh: anon key missing from vault'; RETURN; END IF;

  IF v_eia IS NOT NULL THEN
    PERFORM net.http_post(url := base,
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_anon,'apikey',v_anon),
      body := jsonb_build_object('source','eia','eia_key',v_eia), timeout_milliseconds := 120000);
  END IF;
  IF v_noaa IS NOT NULL THEN
    PERFORM net.http_post(url := base,
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_anon,'apikey',v_anon),
      body := jsonb_build_object('source','noaa','noaa_token',v_noaa), timeout_milliseconds := 120000);
  END IF;
END $function$


-- ===== ottoq_twin_labor_window =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_labor_window(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run   ottoq_sim_runs%ROWTYPE;
  v_knobs jsonb;
  v_min   numeric;
  v_phys  int;
  v_out   jsonb;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'sim_run not found'); END IF;

  SELECT knobs INTO v_knobs FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id;
  v_min := NULLIF(EXTRACT(EPOCH FROM (v_run.sim_clock_current - v_run.sim_clock_start)) / 60.0, 0);

  -- the charge-stall count for THIS depot, not a constant, so a depot with a
  -- different build does not get Nashville's 45 silently applied to it
  SELECT count(*) INTO v_phys FROM stalls
   WHERE depot_id = v_run.depot_id AND stall_type::text IN ('dcfc','l2');

  WITH ovf AS (
    SELECT payload p, occurred_at FROM ottoq_events
     WHERE sim_run_id = p_sim_run_id AND event_type = 'twin.staging_overflow'
  ), latest AS (SELECT p FROM ovf ORDER BY occurred_at DESC LIMIT 1),
     started AS (SELECT payload p FROM ottoq_events
                  WHERE sim_run_id = p_sim_run_id AND event_type = 'twin.deferred_service_started'),
     done AS (SELECT payload p FROM ottoq_events
               WHERE sim_run_id = p_sim_run_id AND event_type = 'twin.deferred_service_completed')
  SELECT jsonb_build_object(
    'window', jsonb_build_object('basis','run_to_date','sim_minutes_elapsed', v_min),
    'staffing', COALESCE((SELECT jsonb_object_agg(role, headcount)
        FROM ottoq_depot_staffing WHERE depot_id = v_run.depot_id), '{}'::jsonb),
    'knobs', jsonb_build_object(
      'staffing_level',  (v_knobs #>> '{_rates,staffing_level}')::numeric,
      'charging_staff',  (v_knobs #>> '{_rates,charging_staff}')::numeric,
      'cleaning_staff',  (v_knobs #>> '{_rates,cleaning_staff}')::numeric,
      'service_staff',   (v_knobs #>> '{_rates,service_staff}')::numeric,
      'deploy_staff',    (v_knobs #>> '{_rates,deploy_staff}')::numeric,
      'any_set', (v_knobs #> '{_rates}') IS NOT NULL AND EXISTS (
        SELECT 1 FROM jsonb_object_keys(COALESCE(v_knobs -> '_rates', '{}'::jsonb)) k
         WHERE k IN ('staffing_level','charging_staff','cleaning_staff','service_staff','deploy_staff'))),
    'lanes', jsonb_build_object(
      'wash_cap',   (SELECT (p->>'wash_cap')::int   FROM latest),
      'service_cap',(SELECT (p->>'svc_cap')::int    FROM latest),
      'deploy_cap', (SELECT (p->>'deploy_cap')::int FROM latest),
      -- COMPUTED, not stamped — see the header note.
      'charge_cap', ottoq_sim_lane_capacity(p_sim_run_id, 'charging_staff', v_phys),
      'charge_stalls_physical', v_phys,
      'charge_cap_basis', 'computed_from_knob',
      'patience_min', (SELECT (p->>'patience_min')::numeric FROM latest),
      'observed_at', (SELECT occurred_at FROM ovf ORDER BY occurred_at DESC LIMIT 1)),
    'overflow', jsonb_build_object(
      'events',        (SELECT count(*) FROM ovf),
      'vehicles_total',(SELECT COALESCE(sum((p->>'overflow')::int),0) FROM ovf),
      'vehicles_max',  (SELECT max((p->>'overflow')::int) FROM ovf),
      'escalated',     (SELECT COALESCE(sum((p->>'escalated')::int),0) FROM ovf),
      'per_sim_hour',  CASE WHEN v_min IS NULL OR v_min = 0 THEN NULL
                       ELSE round((SELECT count(*) FROM ovf)::numeric * 60.0 / v_min, 3) END),
    'backlog', jsonb_build_object(
      'started',   (SELECT count(*) FROM started),
      'completed', (SELECT count(*) FROM done),
      'open',      GREATEST(0, (SELECT count(*) FROM started) - (SELECT count(*) FROM done)),
      'by_service', COALESCE((
        SELECT jsonb_object_agg(svc, jsonb_build_object('started', n, 'est_min_p50', p50, 'requires_bay', bay))
          FROM (SELECT p->'item'->>'svc' svc, count(*) n,
                       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'dur_min')::numeric)::numeric,1) p50,
                       max(p->'item'->>'requires_bay') bay
                  FROM started WHERE p->'item'->>'svc' IS NOT NULL GROUP BY 1) s), '{}'::jsonb),
      'bay_bound',  (SELECT count(*) FROM started WHERE p->'item'->>'concurrency' = 'bay'),
      'digital',    (SELECT count(*) FROM started WHERE p->'item'->>'concurrency' = 'digital'),
      'blocks_dispatch', (SELECT count(*) FROM started
                           WHERE (p->'item'->>'blocks_dispatch_while_running')::boolean))
  ) INTO v_out;
  RETURN v_out;
END;
$function$


-- ===== ottoq_twin_offsite_window =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_offsite_window(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_out jsonb;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','sim_run not found'); END IF;

  WITH d AS (SELECT * FROM ottoq_vehicle_dispatches WHERE sim_run_id = p_sim_run_id),
       done AS (SELECT * FROM d WHERE actual_duration_min IS NOT NULL),
       live AS (SELECT * FROM d WHERE status = 'active')
  SELECT jsonb_build_object(
    'dispatches', jsonb_build_object(
      'total', (SELECT count(*) FROM d), 'completed', (SELECT count(*) FROM done),
      'active', (SELECT count(*) FROM live)),
    'off_site_now', jsonb_build_object(
      'count', (SELECT count(*) FROM live),
      'elapsed_min_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (
          ORDER BY EXTRACT(EPOCH FROM (v_run.sim_clock_current - dispatched_at))/60.0)::numeric,1) FROM live),
      'return_eta_min_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (
          ORDER BY return_eta_minutes)::numeric,1) FROM live WHERE return_eta_minutes IS NOT NULL),
      'soc_at_dispatch_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY soc_at_dispatch_pct)::numeric,1) FROM live)),
    'duration', jsonb_build_object(
      'planned_min_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY planned_duration_min)::numeric,1) FROM done),
      'actual_min_p50',  (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_duration_min)::numeric,1) FROM done),
      'actual_min_p90',  (SELECT round(percentile_cont(0.9) WITHIN GROUP (ORDER BY actual_duration_min)::numeric,1) FROM done),
      'drift_min_p50',   (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_duration_min - planned_duration_min)::numeric,1) FROM done),
      'overran_plan', (SELECT count(*) FROM done WHERE actual_duration_min > planned_duration_min),
      'ratio_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_duration_min / NULLIF(planned_duration_min,0))::numeric,3) FROM done)),
    'activity', jsonb_build_object(
      'miles_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY miles_driven)::numeric,2) FROM done),
      'miles_per_trip_min_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (
          ORDER BY miles_driven / NULLIF(actual_duration_min,0))::numeric,4) FROM done),
      'soc_drop_pct_per_hour_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (
          ORDER BY (soc_at_dispatch_pct - soc_at_return_pct) / NULLIF(actual_duration_min,0) * 60)::numeric,2) FROM done),
      'energy_basis', 'soc_delta_proxy'),
    'soc', jsonb_build_object(
      'at_dispatch_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY soc_at_dispatch_pct)::numeric,1) FROM done),
      'at_return_p50',   (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY soc_at_return_pct)::numeric,1) FROM done),
      'at_return_p10',   (SELECT round(percentile_cont(0.1) WITHIN GROUP (ORDER BY soc_at_return_pct)::numeric,1) FROM done),
      'returned_below_20', (SELECT count(*) FROM done WHERE soc_at_return_pct < 20)),
    'arrival_jitter_min_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY arrival_jitter_min)::numeric,1) FROM done),
    -- the sparsity, stated: a p50 of 0 hides that 2.5% of trips arrive very late
    'arrival_jitter_delayed_n', (SELECT count(*) FROM done WHERE arrival_jitter_min > 0),
    'arrival_jitter_min_max', (SELECT round(max(arrival_jitter_min)::numeric,1) FROM done),
    'by_return_trigger', COALESCE((
      SELECT jsonb_object_agg(trg, jsonb_build_object('n', n, 'planned_min_p50', pp,
        'actual_min_p50', ap, 'drift_min_p50', dp, 'soc_at_return_p50', sr))
      FROM (SELECT COALESCE(return_trigger,'(unrecorded)') trg, count(*) n,
          round(percentile_cont(0.5) WITHIN GROUP (ORDER BY planned_duration_min)::numeric,1) pp,
          round(percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_duration_min)::numeric,1) ap,
          round(percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_duration_min - planned_duration_min)::numeric,1) dp,
          round(percentile_cont(0.5) WITHIN GROUP (ORDER BY soc_at_return_pct)::numeric,1) sr
        FROM done GROUP BY 1) s), '{}'::jsonb)
  ) INTO v_out;
  RETURN v_out;
END;
$function$


-- ===== ottoq_twin_refit_distribution =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_refit_distribution(p_dataset text, p_variable text, p_segment text, p_values numeric[], p_units text DEFAULT NULL::text, p_clip_min numeric DEFAULT NULL::numeric, p_clip_max numeric DEFAULT NULL::numeric, p_src_start date DEFAULT NULL::date, p_src_end date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_grid numeric[]; v_n bigint; v_mean numeric; v_sd numeric; v_min numeric; v_max numeric; v_med numeric;
BEGIN
  v_n := (SELECT count(*) FROM unnest(p_values) v
            WHERE v IS NOT NULL AND (p_clip_min IS NULL OR v>=p_clip_min) AND (p_clip_max IS NULL OR v<=p_clip_max));
  IF v_n < 20 THEN RAISE EXCEPTION 'refit %/%: only % usable values after clipping', p_variable, p_segment, v_n; END IF;

  SELECT array_agg(q ORDER BY g) INTO v_grid
    FROM generate_series(0,100) g
    CROSS JOIN LATERAL (
      SELECT percentile_cont(g/100.0) WITHIN GROUP (ORDER BY v) AS q
        FROM unnest(p_values) v
       WHERE v IS NOT NULL AND (p_clip_min IS NULL OR v>=p_clip_min) AND (p_clip_max IS NULL OR v<=p_clip_max)
    ) x;

  SELECT avg(v), stddev_pop(v), min(v), max(v), percentile_cont(0.5) WITHIN GROUP (ORDER BY v)
    INTO v_mean, v_sd, v_min, v_max, v_med
    FROM unnest(p_values) v
   WHERE v IS NOT NULL AND (p_clip_min IS NULL OR v>=p_clip_min) AND (p_clip_max IS NULL OR v<=p_clip_max);

  DELETE FROM ottoq_calibration_distributions WHERE variable_name=p_variable AND segment=p_segment;
  INSERT INTO ottoq_calibration_distributions
    (dataset_code, variable_name, segment, quantile_grid, sample_count, mean_value, stddev_value,
     min_value, max_value, median_value, units, hard_min, hard_max, best_fit_family, fitted_at)
  VALUES (p_dataset, p_variable, p_segment, v_grid, v_n, v_mean, v_sd, v_min, v_max, v_med,
     p_units, p_clip_min, p_clip_max, 'empirical_quantile', now());

  UPDATE ottoq_calibration_datasets
     SET record_count=v_n, ingested_at=now(), ingestion_method='api_live', status='ingested',
         date_range_start=COALESCE(p_src_start,date_range_start), date_range_end=COALESCE(p_src_end,date_range_end),
         ingestion_notes='Live refit via ottoq-twin-ingest: '||v_n||' values for '||p_variable
   WHERE dataset_code=p_dataset;

  RETURN jsonb_build_object('variable',p_variable,'segment',p_segment,'n',v_n,
    'min',round(v_min,2),'median',round(v_med,2),'max',round(v_max,2),'mean',round(v_mean,2));
END $function$


-- ===== ottoq_twin_run_context =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_run_context(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE(
    (SELECT jsonb_build_object(
       'sim_run_id',  r.sim_run_id,
       'depot_id',    r.depot_id,
       'depot_name',  d.name,
       'scenario',    r.scenario_code,
       'status',      r.status,
       'seed',        r.random_seed,
       'stall_count', (SELECT count(*) FROM stalls s WHERE s.depot_id = r.depot_id),
       'fleet_count', (SELECT count(*) FROM vehicles v
                        WHERE v.category = 'autonomous' AND v.home_depot_id = r.depot_id),
       -- what the run was configured to use
       'policy_configured', r.policy,
       -- what actually made the decisions. NULL when no decision was logged —
       -- an unrun policy is not a policy in force.
       'policy_observed', (
         SELECT dl.policy FROM ottoq_deploy_log dl
          WHERE dl.sim_run_id = r.sim_run_id AND dl.policy IS NOT NULL
          GROUP BY dl.policy ORDER BY count(*) DESC LIMIT 1),
       'policy_decisions', (
         SELECT count(*) FROM ottoq_deploy_log dl WHERE dl.sim_run_id = r.sim_run_id),
       -- distinct policies seen; more than one means the run switched mid-flight
       'policy_variants', (
         SELECT jsonb_object_agg(policy, n) FROM (
           SELECT policy, count(*) n FROM ottoq_deploy_log
            WHERE sim_run_id = r.sim_run_id AND policy IS NOT NULL
            GROUP BY policy) s),
       'policy_matches_config', (
         SELECT CASE
           WHEN r.policy IS NULL THEN NULL
           WHEN count(*) FILTER (WHERE dl.policy IS NOT NULL) = 0 THEN NULL
           ELSE bool_and(dl.policy = r.policy) FILTER (WHERE dl.policy IS NOT NULL)
         END
         FROM ottoq_deploy_log dl WHERE dl.sim_run_id = r.sim_run_id))
       FROM ottoq_sim_runs r
       LEFT JOIN depots d ON d.id = r.depot_id
      WHERE r.sim_run_id = p_sim_run_id),
    jsonb_build_object('error', 'sim_run not found'));
$function$


-- ===== ottoq_twin_run_list =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_run_list(p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET statement_timeout TO '8s'
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_out JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(r), '[]'::jsonb) INTO v_out
  FROM (
    SELECT jsonb_build_object(
      'sim_run_id',        sr.sim_run_id,
      'scenario',          sr.scenario_code,
      'status',            sr.status,
      'started_at',        sr.started_at,
      'ended_at',          sr.ended_at,
      'sim_clock_start',   sr.sim_clock_start,
      'sim_clock_current', sr.sim_clock_current,
      'tick_count',        sr.tick_count,
      'time_scale',        sr.time_scale,
      'seed',              sr.random_seed,
      'sim_minutes', GREATEST(0, ROUND(
        EXTRACT(EPOCH FROM (sr.sim_clock_current - sr.sim_clock_start)) / 60.0
      ))::int,
      -- counters only for the 10 NEWEST runs; each scan hard-capped at 1500 rows
      'counters', CASE WHEN sr.rn <= 10 THEN jsonb_build_object(
        'dispatches_total',  (SELECT COUNT(*) FROM (SELECT 1 FROM ottoq_vehicle_dispatches d WHERE d.sim_run_id = sr.sim_run_id LIMIT 1500) c1),
        'dispatches_active', (SELECT COUNT(*) FROM (SELECT d.status FROM ottoq_vehicle_dispatches d WHERE d.sim_run_id = sr.sim_run_id ORDER BY d.created_at DESC LIMIT 1500) c2 WHERE c2.status IN ('active','returning')),
        'telemetry_packets', (SELECT COUNT(*) FROM (SELECT 1 FROM ottoq_telemetry_packets t WHERE t.sim_run_id = sr.sim_run_id LIMIT 1500) c3),
        'events_total',      (SELECT COUNT(*) FROM (SELECT 1 FROM ottoq_events e WHERE e.sim_run_id = sr.sim_run_id LIMIT 1500) c4),
        'incidents_open',    (SELECT COUNT(*) FROM (SELECT i.resolution_status FROM ottoq_vehicle_incidents i WHERE i.sim_run_id = sr.sim_run_id LIMIT 1500) c5 WHERE c5.resolution_status = 'open'),
        'incidents_total',   (SELECT COUNT(*) FROM (SELECT 1 FROM ottoq_vehicle_incidents i WHERE i.sim_run_id = sr.sim_run_id LIMIT 1500) c6),
        'faults',            (SELECT COUNT(*) FROM (SELECT e.event_type FROM ottoq_events e WHERE e.sim_run_id = sr.sim_run_id ORDER BY e.occurred_at DESC LIMIT 1500) c7
                               WHERE (c7.event_type LIKE '%fault%' OR c7.event_type LIKE '%brownout%'
                                  OR c7.event_type LIKE '%anomaly%' OR c7.event_type LIKE '%incident%'
                                  OR c7.event_type LIKE '%voltage%' OR c7.event_type LIKE '%frequency%')),
        'charge_sessions',   (SELECT COUNT(*) FROM (SELECT 1 FROM ocpp_sessions cs WHERE cs.depot_id = sr.depot_id AND cs.started_at >= sr.started_at LIMIT 1500) c8)
      ) ELSE NULL END,
      'variability', (
        SELECT jsonb_build_object(
          'spread_mult', COALESCE((vp.knobs #>> '{_global,spread_mult}')::numeric, 1),
          'rate_mult',   COALESCE((vp.knobs #>> '{_global,rate_mult}')::numeric, 1),
          'tuned_knobs', (
            SELECT COUNT(*) FROM jsonb_object_keys(vp.knobs) AS keys(key)
             WHERE keys.key NOT LIKE '\_%'
          ),
          'notes', vp.notes
        )
        FROM ottoq_variability_profiles vp WHERE vp.sim_run_id = sr.sim_run_id
      )
    ) AS r
    FROM (
      SELECT sr0.*, row_number() OVER (ORDER BY sr0.started_at DESC NULLS LAST) AS rn
      FROM ottoq_sim_runs sr0
      ORDER BY sr0.started_at DESC NULLS LAST
      LIMIT GREATEST(1, LEAST(50, p_limit))
    ) sr
  ) sub;

  RETURN v_out;
END;
$function$


-- ===== ottoq_twin_snapshot =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_snapshot(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run     ottoq_sim_runs%ROWTYPE;
  v_depot   UUID;
  v_clock   TIMESTAMPTZ;
  v_out     JSONB;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'sim_run not found', 'sim_run_id', p_sim_run_id);
  END IF;
  v_depot := v_run.depot_id;
  v_clock := v_run.sim_clock_current;

  SELECT jsonb_build_object(

    'run', jsonb_build_object(
      'sim_run_id',  v_run.sim_run_id,
      'scenario',    v_run.scenario_code,
      'status',      v_run.status,
      'sim_clock',   v_clock,
      'tick_count',  v_run.tick_count,
      'time_scale',  v_run.time_scale,
      'seed',        v_run.random_seed,
      -- PLAYBACK CONTRACT for the renderer.
      -- 'live'  => 1 real second advances the sim clock by speed_x sim seconds (true 1:1 at 1x)
      -- 'fixed' => historical tick_interval_seconds * time_scale behaviour (certs/benchmarks)
      'playback_mode', COALESCE(v_run.payload->>'playback_mode','fixed'),
      'speed_x',       COALESCE((v_run.payload->>'speed_x')::numeric, 1.0),
      -- T5: MEASURED, not configured. NULL until >=2 ticks are logged.
      'clock_measured', (
         SELECT jsonb_build_object(
                  'ratio',            f.ratio,
                  'target',           f.target_ratio,
                  'ticks',            f.ticks_measured,
                  'p50_tick_ms',      f.p50_tick_ms,
                  'p95_tick_ms',      f.p95_tick_ms,
                  'max_speed',        f.max_sustainable_speed,
                  'within_tolerance', f.within_tolerance,
                  'verdict',          f.verdict)
           FROM ottoq_clock_fidelity(v_run.sim_run_id, 20) f),
      -- present ONLY while a fast-forward is in flight; drives the planning pause + progress
      'jump',             v_run.payload->'jump',
      -- pacing inputs: elapsed-since-last-tick and clock skew
      'last_tick_at',     v_run.last_tick_at,
      'next_tick_due_at', v_run.next_tick_due_at,
      'server_now',       now()
    ),

    -- T3 RENDER CONTRACT: timed legs. The renderer INTERPOLATES these; it must
    -- never invent motion the contract did not specify.
    'legs', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'leg_id',      l.leg_id,
        'vehicle_id',  l.vehicle_id,
        'seq',         l.seq,
        'leg_type',    l.leg_type,
        'intent',      l.duration_basis->>'intent',
        'kind',        COALESCE(l.duration_basis->>'kind','dwell'),
        'from_stall',  l.from_stall_id,
        'to_stall',    l.to_stall_id,
        'from_x',      fs.relative_x, 'from_y', fs.relative_y,
        'to_x',        ts.relative_x, 'to_y',   ts.relative_y,
        'start_sim',   l.planned_start_sim,
        'end_sim',     l.planned_end_sim,
        'duration_s',  l.planned_duration_s,
        'status',      l.status,
        'geometry',    COALESCE(l.duration_basis->>'geometry','n/a'))
        ORDER BY l.vehicle_id, l.seq)
        FROM ottoq_itinerary_legs l
        LEFT JOIN stalls fs ON fs.id = l.from_stall_id
        LEFT JOIN stalls ts ON ts.id = l.to_stall_id
       WHERE l.sim_run_id = v_run.sim_run_id
         AND (
           CASE WHEN COALESCE(l.duration_basis->>'kind','dwell') = 'travel'
                -- TRAVEL: covered until CLOSED. ottoq_itin_close_travel_legs bounds
                -- it (arrived / superseded / stale), so a drive that overruns its
                -- estimate stays covered instead of falling off a time cliff.
                THEN l.status NOT IN ('done','amended','skipped')
                -- DWELL: durations are authoritative, keep the time window.
                ELSE l.status <> 'done'
                     AND l.planned_end_sim   >= v_clock - interval '10 minutes'
                     AND l.planned_start_sim <= v_clock + interval '10 minutes'
           END)
    ), '[]'::jsonb),

    -- #173 (D): server half of the CONTRACT COVERAGE ratio. The renderer knows
    -- how many cars are physically taxiing; only it can close the ratio. Publish
    -- the denominator so coverage is measurable instead of assumed.
    'legs_meta', jsonb_build_object(
      'open_travel_legs', (
        SELECT count(*) FROM ottoq_itinerary_legs l2
         WHERE l2.sim_run_id = v_run.sim_run_id
           AND l2.duration_basis->>'kind' = 'travel'
           AND l2.status NOT IN ('done','amended','skipped')),
      'vehicles_with_open_leg', (
        SELECT count(DISTINCT l3.vehicle_id) FROM ottoq_itinerary_legs l3
         WHERE l3.sim_run_id = v_run.sim_run_id
           AND l3.duration_basis->>'kind' = 'travel'
           AND l3.status NOT IN ('done','amended','skipped')),
      'closed_this_run', (
        SELECT count(*) FROM ottoq_itinerary_legs l4
         WHERE l4.sim_run_id = v_run.sim_run_id
           AND l4.duration_basis->>'kind' = 'travel'
           AND l4.status = 'done'),
      'median_deviation_s', (
        SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY l5.deviation_s)::numeric, 1)
          FROM ottoq_itinerary_legs l5
         WHERE l5.sim_run_id = v_run.sim_run_id
           AND l5.duration_basis->>'kind' = 'travel'
           AND l5.deviation_s IS NOT NULL)),

    'fleet', jsonb_build_object(
      'counts', (
        SELECT jsonb_object_agg(state, n) FROM (
          SELECT current_state::text AS state, COUNT(*) AS n
            FROM vehicles WHERE category = 'autonomous' AND home_depot_id = v_depot
           GROUP BY current_state
        ) c
      ),
      'total', (SELECT COUNT(*) FROM vehicles WHERE category = 'autonomous' AND home_depot_id = v_depot),
      'vehicles', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', v.id, 'av_id', v.av_api_vehicle_id, 'make', v.make,
          'platform', v.platform, 'state', v.current_state,
          'soc', ROUND(v.current_soc::numeric, 1), 'stall_id', v.current_stall_id
        ) ORDER BY v.av_api_vehicle_id)
        FROM vehicles v WHERE v.category = 'autonomous' AND v.home_depot_id = v_depot
      ), '[]'::jsonb)
    ),

    -- Live stall status only (geometry comes from layout, cached once)
    'stalls_status', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', st.id, 'status', st.status, 'vehicle_id', st.current_vehicle_id
      ))
      FROM stalls st WHERE st.depot_id = v_depot
        AND st.status::text <> 'available'        -- only occupied/charging/faulted (light payload)
    ), '[]'::jsonb),

    'energy', (
      SELECT jsonb_build_object(
        'grid_import_kw', se.grid_import_kw, 'grid_export_kw', se.grid_export_kw,
        'solar_kw', se.solar_generation_kw, 'bess_output_kw', se.bess_output_kw,
        'ev_charging_kw', se.total_ev_charging_kw, 'building_kw', se.building_load_kw,
        'peak_15min_kw', se.peak_demand_kw_15min,
        'tariff', se.current_tariff_label, 'rate_per_kwh', se.current_rate_per_kwh,
        'at', se.timestamp
      )
      FROM site_energy_snapshots se WHERE se.depot_id = v_depot
        AND se.timestamp <= v_clock
        AND se.timestamp >= v_run.sim_clock_start   -- scope to THIS run's sim-time window
      ORDER BY se.timestamp DESC LIMIT 1
    ),

    'bess', (
      SELECT jsonb_build_object(
        'soc_pct', b.current_soc_pct, 'power_kw', b.current_power_kw,
        'state', b.current_state, 'temp_c', b.current_temperature_c,
        'soh_pct', b.current_soh_pct
      )
      FROM ottoq_bess_units b WHERE b.depot_id = v_depot LIMIT 1
    ),

    'weather', (
      SELECT jsonb_build_object(
        'temp_c', w.ambient_temp_c, 'cloud_pct', w.cloud_cover_pct,
        'conditions', w.conditions_label, 'precip', w.precip_state,
        'ghi_wm2', w.ghi_wm2, 'wind_kmh', w.wind_speed_kmh,
        'solar_elev_deg', w.solar_elevation_deg, 'at', w.sim_clock_at,
        'humidity_pct', w.relative_humidity_pct
      )
      FROM ottoq_weather_snapshots w WHERE w.sim_run_id = p_sim_run_id
      ORDER BY w.sim_clock_at DESC LIMIT 1
    ),

    'grid', (
      SELECT jsonb_build_object(
        'lmp_usd_mwh', g.lmp_usd_per_mwh, 'tariff', g.current_tariff_label,
        'carbon_gco2_kwh', g.carbon_intensity_gco2_per_kwh,
        'voltage_status', g.voltage_status, 'frequency_hz', g.frequency_hz,
        'reserve_margin_pct', g.reserve_margin_pct,
        'dr_active', (g.active_dr_call_id IS NOT NULL),
        'dr_cap_kw', g.dr_required_load_cap_kw, 'at', g.sim_clock_at
      )
      FROM ottoq_grid_snapshots g WHERE g.sim_run_id = p_sim_run_id
      ORDER BY g.sim_clock_at DESC LIMIT 1
    ),

    'counters', jsonb_build_object(
      'dispatches_active', (SELECT COUNT(*) FROM ottoq_vehicle_dispatches
                             WHERE sim_run_id = p_sim_run_id AND status IN ('active','returning')),
      'dispatches_total',  (SELECT COUNT(*) FROM ottoq_vehicle_dispatches WHERE sim_run_id = p_sim_run_id),
      'telemetry_packets', (SELECT COUNT(*) FROM ottoq_telemetry_packets WHERE sim_run_id = p_sim_run_id),
      'charge_sessions',   (SELECT COUNT(*) FROM ocpp_sessions cs WHERE cs.sim_run_id = p_sim_run_id),
      'events_total',      (SELECT COUNT(*) FROM ottoq_events WHERE sim_run_id = p_sim_run_id),
      'open_incidents',    (SELECT COUNT(*) FROM ottoq_vehicle_incidents
                             WHERE sim_run_id = p_sim_run_id AND resolution_status = 'open')
    ),

    'recent_events', COALESCE((
      SELECT jsonb_agg(e) FROM (
        SELECT jsonb_build_object(
          'type', event_type, 'severity', severity,
          'at', occurred_at, 'entity', entity_type,
          'payload', payload
        ) AS e
        FROM ottoq_events
        WHERE sim_run_id = p_sim_run_id
          AND event_type NOT IN (
            'twin.bess_dispatch','twin.weather_tick','twin.solar_tick','twin.grid_tick',
            'twin.sim_tick_advanced','twin.telemetry_emitted','twin.bess_soh_degradation'
          )
        ORDER BY occurred_at DESC LIMIT 15
      ) sub
    ), '[]'::jsonb),

    'variability', COALESCE((
      SELECT knobs FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id
    ), '{}'::jsonb)

  ) INTO v_out;

  RETURN v_out;
END;
$function$


-- ===== ottoq_twin_spread_stat =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_spread_stat(p_vals numeric[])
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT CASE WHEN count(v) = 0 THEN
      jsonb_build_object('n', 0, 'min', NULL, 'p50', NULL, 'max', NULL, 'spread', NULL)
    ELSE jsonb_build_object(
      'n',      count(v),
      'min',    round(min(v), 3),
      'p50',    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY v)::numeric, 3),
      'max',    round(max(v), 3),
      'spread', round(max(v) - min(v), 3))
    END
  FROM unnest(p_vals) v WHERE v IS NOT NULL;
$function$


-- ===== ottoq_twin_wear_window =====
CREATE OR REPLACE FUNCTION public.ottoq_twin_wear_window(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_out jsonb;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','sim_run not found'); END IF;

  WITH w AS (
    SELECT wr.*,
           v.av_api_vehicle_id AS av_id,
           -- the DRAWN intervals this vehicle is measured against
           (NULLIF(v.config->>'pm_interval_km',   ''))::numeric AS pm_interval_km,
           (NULLIF(v.config->>'calib_interval_h', ''))::numeric AS calib_interval_h,
           -- 99 means "no open DTC", NOT severity 99
           NULLIF(wr.worst_open_dtc_rank, 99) AS dtc_rank
      FROM ottoq_vehicle_wear wr
      JOIN vehicles v ON v.id = wr.vehicle_id
     WHERE wr.sim_run_id = p_sim_run_id
  ), due AS (
    SELECT *,
      -- progress against this vehicle's own interval; >= 1 means overdue.
      CASE WHEN pm_interval_km IS NULL OR pm_interval_km = 0 THEN NULL
           ELSE round((drive_km_total - COALESCE(km_at_last_pm,0)) / pm_interval_km, 3) END AS pm_due_ratio,
      CASE WHEN calib_interval_h IS NULL OR calib_interval_h = 0 THEN NULL
           ELSE round((drive_hours_total - COALESCE(hours_at_last_calibration,0)) / calib_interval_h, 3) END AS calib_due_ratio
      FROM w
  )
  SELECT jsonb_build_object(
    'fleet_size', (SELECT count(*) FROM due),

    'wear', jsonb_build_object(
      'drive_km_p50',    (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY drive_km_total)::numeric,1) FROM due),
      'drive_hours_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY drive_hours_total)::numeric,2) FROM due),
      'soil_index_p50',  (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY soil_index)::numeric,3) FROM due),
      'soil_index_max',  (SELECT round(max(soil_index)::numeric,3) FROM due),
      'cabin_litter_total', (SELECT COALESCE(sum(cabin_litter_events),0) FROM due)),

    -- ── SERVICE DUE: the interval joined to the progress against it ────────
    'due', jsonb_build_object(
      'pm_due_ratio_p50',    (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY pm_due_ratio)::numeric,3) FROM due WHERE pm_due_ratio IS NOT NULL),
      'pm_overdue',          (SELECT count(*) FROM due WHERE pm_due_ratio >= 1),
      'pm_due_soon',         (SELECT count(*) FROM due WHERE pm_due_ratio >= 0.9 AND pm_due_ratio < 1),
      'calib_due_ratio_p50', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY calib_due_ratio)::numeric,3) FROM due WHERE calib_due_ratio IS NOT NULL),
      'calib_overdue',       (SELECT count(*) FROM due WHERE calib_due_ratio >= 1),
      'measurable',          (SELECT count(*) FROM due WHERE pm_due_ratio IS NOT NULL)),

    -- ── DTC ───────────────────────────────────────────────────────────────
    'dtc', jsonb_build_object(
      'open_total',    (SELECT COALESCE(sum(open_dtc_count),0) FROM due),
      'vehicles_with_open', (SELECT count(*) FROM due WHERE open_dtc_count > 0),
      -- NULL when the fleet is clean: there is no "worst rank" without a DTC,
      -- and 99 would read as a catastrophic severity.
      'worst_rank',    (SELECT min(dtc_rank) FROM due),
      -- say which way the scale runs; the raw column is inverted and unlabelled
      'rank_scale',    'lower_is_worse',
      'rank_sentinel_note', '99 in ottoq_vehicle_wear means NO open DTC; mapped to null here',
      'by_rank', COALESCE((
        SELECT jsonb_object_agg(dtc_rank::text, n)
          FROM (SELECT dtc_rank, count(*) n FROM due WHERE dtc_rank IS NOT NULL GROUP BY 1) s), '{}'::jsonb)),

    -- ── the worst-off vehicles, so the signal is actionable not just summary
    'attention', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'av_id', av_id, 'vehicle_id', vehicle_id,
        'pm_due_ratio', pm_due_ratio, 'calib_due_ratio', calib_due_ratio,
        'soil_index', round(soil_index,3),
        'open_dtc_count', open_dtc_count, 'worst_dtc_rank', dtc_rank)
        ORDER BY dtc_rank NULLS LAST, pm_due_ratio DESC NULLS LAST)
      FROM (SELECT * FROM due
             WHERE open_dtc_count > 0 OR pm_due_ratio >= 0.9 OR calib_due_ratio >= 0.9
             ORDER BY dtc_rank NULLS LAST, pm_due_ratio DESC NULLS LAST
             LIMIT 20) t), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END;
$function$


-- ===== ottoq_urgency_max =====
CREATE OR REPLACE FUNCTION public.ottoq_urgency_max(p_a text, p_b text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
  SELECT CASE WHEN public.ottoq_urgency_rank(p_a) >= public.ottoq_urgency_rank(p_b)
              THEN p_a ELSE p_b END;
$function$


-- ===== ottoq_urgency_rank =====
CREATE OR REPLACE FUNCTION public.ottoq_urgency_rank(p_urgency text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT CASE p_urgency
           WHEN 'critical' THEN 5 WHEN 'overdue' THEN 4 WHEN 'due' THEN 3
           WHEN 'due_soon' THEN 2 WHEN 'ok' THEN 1 ELSE 0 END;
$function$


-- ===== ottoq_variability_instantiate =====
CREATE OR REPLACE FUNCTION public.ottoq_variability_instantiate(p_sim_run_id uuid, p_template_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_knobs JSONB;
  v_id    UUID;
BEGIN
  SELECT knobs INTO v_knobs FROM ottoq_variability_profiles
   WHERE name = p_template_name;
  IF v_knobs IS NULL THEN
    SELECT knobs INTO v_knobs FROM ottoq_variability_profiles WHERE name = '__default__';
  END IF;
  v_knobs := COALESCE(v_knobs, '{}'::jsonb);

  INSERT INTO ottoq_variability_profiles (sim_run_id, name, knobs, notes)
  VALUES (p_sim_run_id, NULL, v_knobs, 'instantiated from ' || p_template_name)
  ON CONFLICT (sim_run_id) DO UPDATE SET knobs = EXCLUDED.knobs, updated_at = NOW()
  RETURNING profile_id INTO v_id;

  RETURN v_id;
END;
$function$


-- ===== ottoq_vehicle_card =====
CREATE OR REPLACE FUNCTION public.ottoq_vehicle_card(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'endpoint','ottoq.vehicle_card','contract_version','1.0',
    'vehicle', (SELECT st FROM jsonb_array_elements(
        public.ottoq_depot_cards((SELECT current_depot_id FROM vehicles WHERE id = p_vehicle_id))->'vehicles') st
      WHERE (st->>'vehicle_id')::uuid = p_vehicle_id LIMIT 1)
  );
$function$


-- ===== ottoq_vehicles_state_change =====
CREATE OR REPLACE FUNCTION public.ottoq_vehicles_state_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_payload      JSONB;
  v_diff         JSONB;
  v_actor_type   TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
  v_actor_id     TEXT := NULLIF(current_setting('ottoq.actor_id', TRUE), '');
  v_event_type   TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_event_type := 'vehicle.created';
    v_payload := jsonb_build_object('new', to_jsonb(NEW));
    PERFORM ottoq_record_event(
      p_actor_type        := v_actor_type,
      p_actor_id          := v_actor_id,
      p_event_type        := v_event_type,
      p_entity_type       := 'vehicle',
      p_entity_id         := NEW.id,
      p_fleet_operator_id := NEW.fleet_operator_id,
      p_payload           := v_payload,
      p_new_state         := to_jsonb(NEW),
      p_ingest_source     := 'trigger'
    );
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Skip if nothing material changed
    IF to_jsonb(OLD) = to_jsonb(NEW) THEN
      RETURN NEW;
    END IF;
    v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
    -- Skip pure-timestamp churn: only clock columns moved, no state change.
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_object_keys(v_diff) AS k
       WHERE k <> ALL (ARRAY['updated_at','current_soc_updated_at'])
    ) THEN
      RETURN NEW;
    END IF;
    v_event_type := 'vehicle.state_changed';
    v_payload := jsonb_build_object('diff', v_diff);
    PERFORM ottoq_record_event(
      p_actor_type        := v_actor_type,
      p_actor_id          := v_actor_id,
      p_event_type        := v_event_type,
      p_entity_type       := 'vehicle',
      p_entity_id         := NEW.id,
      p_fleet_operator_id := NEW.fleet_operator_id,
      p_payload           := v_payload,
      p_new_state         := to_jsonb(NEW),
      p_ingest_source     := 'trigger'
    );
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$function$


-- ===== ottoq_verify_audit_bundle =====
CREATE OR REPLACE FUNCTION public.ottoq_verify_audit_bundle(p_bundle_id uuid)
 RETURNS TABLE(out_bundle_id uuid, out_has_signature boolean, out_valid boolean, out_algorithm text, out_signing_key_id text, out_computed text, out_stored text, out_manifest_match boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_bundle ottoq_audit_bundles%ROWTYPE;
  v_recomputed TEXT;
BEGIN
  SELECT * INTO v_bundle FROM ottoq_audit_bundles b WHERE b.bundle_id = p_bundle_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bundle % not found', p_bundle_id;
  END IF;

  v_recomputed := ottoq_sign_bundle(
    v_bundle.bundle_id, v_bundle.window_start, v_bundle.window_end,
    v_bundle.sha256, v_bundle.signature_key_id
  );

  RETURN QUERY SELECT
    v_bundle.bundle_id,
    (v_bundle.signature IS NOT NULL),
    (v_recomputed IS NOT NULL AND v_recomputed = v_bundle.signature),
    v_bundle.signature_algorithm,
    v_bundle.signature_key_id,
    v_recomputed,
    v_bundle.signature,
    TRUE;
END;
$function$


-- ===== ottoq_verify_event_signature =====
CREATE OR REPLACE FUNCTION public.ottoq_verify_event_signature(p_event_id uuid)
 RETURNS TABLE(event_id uuid, has_signature boolean, valid boolean, algorithm text, key_id text, computed text, stored text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_event       ottoq_events%ROWTYPE;
  v_recomputed  TEXT;
BEGIN
  SELECT * INTO v_event FROM ottoq_events e WHERE e.event_id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event % not found', p_event_id;
  END IF;
  IF v_event.signature IS NULL THEN
    RETURN QUERY SELECT v_event.event_id, FALSE, FALSE, v_event.signature_algorithm,
      v_event.signature_key_id, NULL::TEXT, NULL::TEXT;
    RETURN;
  END IF;
  v_recomputed := ottoq_sign_event(
    v_event.event_id, v_event.occurred_at,
    v_event.actor_type, v_event.event_type,
    v_event.entity_type, v_event.entity_id,
    v_event.payload_hash, v_event.signature_key_id
  );
  RETURN QUERY SELECT
    v_event.event_id, TRUE, (v_recomputed = v_event.signature),
    v_event.signature_algorithm, v_event.signature_key_id,
    v_recomputed, v_event.signature;
END;
$function$


-- ===== ottoq_visit_wants_detail =====
CREATE OR REPLACE FUNCTION public.ottoq_visit_wants_detail(p_vehicle uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
    WHERE vn.vehicle_id = p_vehicle AND vn.status IN ('open','in_progress')
      AND a->>'svc' = 'interior_deep_clean' AND COALESCE(a->>'status','pending') <> 'done');
$function$


-- ===== ottoq_wave_capex_cert =====
CREATE OR REPLACE FUNCTION public.ottoq_wave_capex_cert(p_seed bigint, p_fleet_n integer DEFAULT 116, p_deadline_h numeric DEFAULT 7, p_arrival_spread_h numeric DEFAULT 2.5, p_soc_lo integer DEFAULT 18, p_soc_hi integer DEFAULT 38, p_batt_kwh numeric DEFAULT 75, p_dcfc_kw numeric DEFAULT 150, p_l2_kw numeric DEFAULT 11, p_slot_min integer DEFAULT 15)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_slots int := GREATEST(1, FLOOR(p_deadline_h*60/p_slot_min)::int);
  v_spread int := GREATEST(0, FLOOR(p_arrival_spread_h*60/p_slot_min)::int);
  v_arr int[]; v_soc numeric[]; v_ndc int[]; v_nl2 int[]; v_need_kwh numeric;
  v_configs jsonb := '[{"label":"45","dcfc":10,"l2":35},{"label":"35","dcfc":10,"l2":25},{"label":"30","dcfc":10,"l2":20},{"label":"25","dcfc":8,"l2":17},{"label":"22","dcfc":8,"l2":14},{"label":"20","dcfc":6,"l2":14}]';
  v_cfg jsonb; v_policy text; v_order int[]; v_idx int;
  v_dcfc_free int[]; v_l2_free int[]; v_dcfc_cap int; v_l2_cap int;
  v_k int; v_s int; v_j int; v_ok boolean; v_placed boolean;
  v_stranded int; v_results jsonb := '[]'; v_row jsonb;
  v_edf_first_n int := NULL; v_greedy_first_n int := NULL; i int;
BEGIN
  v_arr := '{}'; v_soc := '{}'; v_ndc := '{}'; v_nl2 := '{}';
  FOR i IN 1..p_fleet_n LOOP
    v_arr[i] := FLOOR(ottoq_sim_seeded_random(p_seed, 'arr:'||i) * (v_spread+1))::int;
    v_soc[i] := p_soc_lo + ottoq_sim_seeded_random(p_seed, 'soc:'||i) * (p_soc_hi-p_soc_lo);
    v_need_kwh := GREATEST(0, (90 - v_soc[i])/100.0 * p_batt_kwh);
    v_ndc[i] := GREATEST(1, CEIL(v_need_kwh / p_dcfc_kw * 60.0 / p_slot_min)::int);
    v_nl2[i] := GREATEST(1, CEIL(v_need_kwh / p_l2_kw  * 60.0 / p_slot_min)::int);
  END LOOP;
  FOR v_cfg IN SELECT jsonb_array_elements(v_configs) LOOP
    v_dcfc_cap := (v_cfg->>'dcfc')::int; v_l2_cap := (v_cfg->>'l2')::int;
    FOREACH v_policy IN ARRAY ARRAY['edf','greedy'] LOOP
      v_dcfc_free := array_fill(v_dcfc_cap, ARRAY[v_slots]);
      v_l2_free   := array_fill(v_l2_cap,   ARRAY[v_slots]);
      IF v_policy='edf' THEN
        SELECT array_agg(idx ORDER BY soc ASC, arr ASC) INTO v_order FROM unnest(v_soc, v_arr) WITH ORDINALITY AS t(soc, arr, idx);
      ELSE
        SELECT array_agg(idx ORDER BY arr ASC, idx ASC) INTO v_order FROM unnest(v_soc, v_arr) WITH ORDINALITY AS t(soc, arr, idx);
      END IF;
      v_stranded := 0;
      FOREACH v_idx IN ARRAY v_order LOOP
        v_placed := false;
        FOR v_j IN 1..2 LOOP   -- BOTH policies: DCFC-first (use the fast chargers), then L2
          DECLARE v_class text; v_need int; v_rel int := v_arr[v_idx] + 1;
          BEGIN
            IF v_j=1 THEN v_class := 'dcfc'; v_need := v_ndc[v_idx];
            ELSE v_class := 'l2'; v_need := v_nl2[v_idx]; END IF;
            IF v_rel + v_need - 1 > v_slots THEN CONTINUE; END IF;
            FOR v_s IN v_rel .. (v_slots - v_need + 1) LOOP
              v_ok := true;
              FOR v_k IN v_s .. (v_s + v_need - 1) LOOP
                IF (v_class='l2' AND v_l2_free[v_k] <= 0) OR (v_class='dcfc' AND v_dcfc_free[v_k] <= 0) THEN v_ok := false; EXIT; END IF;
              END LOOP;
              IF v_ok THEN
                FOR v_k IN v_s .. (v_s + v_need - 1) LOOP
                  IF v_class='l2' THEN v_l2_free[v_k] := v_l2_free[v_k]-1; ELSE v_dcfc_free[v_k] := v_dcfc_free[v_k]-1; END IF;
                END LOOP;
                v_placed := true; EXIT;
              END IF;
            END LOOP;
            IF v_placed THEN EXIT; END IF;
          END;
        END LOOP;
        IF NOT v_placed THEN v_stranded := v_stranded + 1; END IF;
      END LOOP;
      v_results := v_results || jsonb_build_array(jsonb_build_object('chargers', v_cfg->>'label', 'dcfc', v_dcfc_cap, 'l2', v_l2_cap, 'policy', v_policy, 'stranded', v_stranded));
      IF v_stranded > 0 THEN
        IF v_policy='edf'    AND v_edf_first_n    IS NULL THEN v_edf_first_n := v_dcfc_cap+v_l2_cap; END IF;
        IF v_policy='greedy' AND v_greedy_first_n IS NULL THEN v_greedy_first_n := v_dcfc_cap+v_l2_cap; END IF;
      END IF;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object('seed', p_seed, 'results', v_results,
    'frontier', jsonb_build_object('greedy_first_strands_at', v_greedy_first_n, 'edf_first_strands_at', v_edf_first_n,
      'capex_charger_gap', COALESCE(v_greedy_first_n,20) - COALESCE(v_edf_first_n,20)));
END; $function$

-- ===== ottoq_wave_capex_cert_v2 =====
CREATE OR REPLACE FUNCTION public.ottoq_wave_capex_cert_v2(p_seed bigint, p_fleet_n integer DEFAULT 116, p_deadline_h numeric DEFAULT 7, p_arrival_spread_h numeric DEFAULT 2.5, p_soc_lo integer DEFAULT 18, p_soc_hi integer DEFAULT 38, p_batt_kwh numeric DEFAULT 75, p_dcfc_kw numeric DEFAULT 150, p_l2_kw numeric DEFAULT 11, p_slot_min integer DEFAULT 5, p_deploy_floor numeric DEFAULT 80, p_full_target numeric DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_slots  int := FLOOR(p_deadline_h*60/p_slot_min)::int;
  v_spread int := FLOOR(p_arrival_spread_h*60/p_slot_min)::int;
  v_arr int[]; v_soc numeric[];
  v_kwh_dc numeric := p_dcfc_kw * p_slot_min/60.0;
  v_kwh_l2 numeric := p_l2_kw  * p_slot_min/60.0;
  v_configs jsonb := '[{"label":"30","dcfc":10,"l2":20},{"label":"25","dcfc":8,"l2":17},
                       {"label":"22","dcfc":8,"l2":14},{"label":"20","dcfc":6,"l2":14},
                       {"label":"18","dcfc":6,"l2":12},{"label":"16","dcfc":6,"l2":10}]';
  v_cfg jsonb; v_policy text; v_order int[]; v_idx int;
  v_dc int[]; v_l2 int[]; v_dc_cap int; v_l2_cap int;
  v_target numeric; v_rem numeric; v_got numeric; v_ach numeric;
  v_want int; v_bs int; v_bl int; v_s int; v_run int; v_after int;
  v_stranded int; v_ready int; v_dcu int; v_l2u int;
  v_results jsonb := '[]'; v_first jsonb := '{}';
  i int; leg int;
BEGIN
  v_arr := '{}'; v_soc := '{}';
  FOR i IN 1..p_fleet_n LOOP
    v_arr[i] := FLOOR(ottoq_sim_seeded_random(p_seed, 'arr:'||i) * (v_spread+1))::int;
    v_soc[i] := p_soc_lo + ottoq_sim_seeded_random(p_seed, 'soc:'||i) * (p_soc_hi-p_soc_lo);
  END LOOP;

  FOR v_cfg IN SELECT jsonb_array_elements(v_configs) LOOP
    v_dc_cap := (v_cfg->>'dcfc')::int; v_l2_cap := (v_cfg->>'l2')::int;
    FOREACH v_policy IN ARRAY ARRAY['greedy','edf_v1','edf_v2'] LOOP
      v_dc := array_fill(v_dc_cap, ARRAY[v_slots]);
      v_l2 := array_fill(v_l2_cap, ARRAY[v_slots]);
      v_target := CASE WHEN v_policy='edf_v2' THEN p_deploy_floor ELSE p_full_target END;
      IF v_policy='greedy' THEN
        SELECT array_agg(idx ORDER BY arr ASC, idx ASC) INTO v_order
          FROM unnest(v_soc, v_arr) WITH ORDINALITY AS t(soc, arr, idx);
      ELSE
        SELECT array_agg(idx ORDER BY soc ASC, arr ASC) INTO v_order
          FROM unnest(v_soc, v_arr) WITH ORDINALITY AS t(soc, arr, idx);
      END IF;
      v_stranded := 0; v_ready := 0; v_dcu := 0; v_l2u := 0;

      FOREACH v_idx IN ARRAY v_order LOOP
        v_rem := GREATEST(0, (v_target - v_soc[v_idx])/100.0 * p_batt_kwh);
        v_got := 0; v_after := v_arr[v_idx] + 1;
        FOR leg IN 1..2 LOOP
          DECLARE v_kwh numeric; v_isdc boolean;
          BEGIN
            EXIT WHEN v_rem <= 0.01;
            v_isdc := (leg = 1);
            v_kwh  := CASE WHEN v_isdc THEN v_kwh_dc ELSE v_kwh_l2 END;
            v_want := CEIL(v_rem / v_kwh)::int;
            v_bs := NULL; v_bl := 0; v_s := v_after;
            WHILE v_s <= v_slots LOOP
              v_run := 0;
              WHILE (v_s + v_run) <= v_slots AND v_run < v_want
                    AND (CASE WHEN v_isdc THEN v_dc[v_s+v_run] ELSE v_l2[v_s+v_run] END) > 0 LOOP
                v_run := v_run + 1;
              END LOOP;
              IF v_run > v_bl THEN v_bl := v_run; v_bs := v_s; END IF;
              EXIT WHEN v_bl >= v_want;
              v_s := v_s + GREATEST(1, v_run + 1);
            END LOOP;
            IF v_bl > 0 THEN
              FOR i IN v_bs .. (v_bs + v_bl - 1) LOOP
                IF v_isdc THEN v_dc[i] := v_dc[i]-1; ELSE v_l2[i] := v_l2[i]-1; END IF;
              END LOOP;
              IF v_isdc THEN v_dcu := v_dcu + v_bl; ELSE v_l2u := v_l2u + v_bl; END IF;
              v_got := v_got + v_bl * v_kwh;
              v_rem := GREATEST(0, v_rem - v_bl * v_kwh);
              v_after := v_bs + v_bl;
            END IF;
          END;
        END LOOP;
        v_ach := v_soc[v_idx] + v_got / p_batt_kwh * 100.0;
        IF v_ach >= p_deploy_floor - 0.01 THEN v_ready := v_ready + 1; ELSE v_stranded := v_stranded + 1; END IF;
      END LOOP;

      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'chargers', v_cfg->>'label', 'policy', v_policy,
        'ready', v_ready, 'stranded', v_stranded,
        'dcfc_util_pct', ROUND(100.0*v_dcu/GREATEST(1,v_dc_cap*v_slots),0),
        'l2_util_pct',   ROUND(100.0*v_l2u/GREATEST(1,v_l2_cap*v_slots),0)));
      IF v_stranded > 0 AND NOT (v_first ? v_policy) THEN
        v_first := v_first || jsonb_build_object(v_policy, (v_dc_cap+v_l2_cap));
      END IF;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('seed', p_seed, 'fleet', p_fleet_n, 'slot_min', p_slot_min,
    'deploy_floor', p_deploy_floor, 'results', v_results, 'first_strands_at_chargers', v_first);
END;
$function$


-- ===== ottoq_wear_mark_serviced =====
CREATE OR REPLACE FUNCTION public.ottoq_wear_mark_serviced(p_vehicle_id uuid, p_sim_run_id uuid, p_service text, p_clock timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  UPDATE ottoq_vehicle_wear w SET
    soil_index = CASE WHEN p_service IN ('exterior_wash','sensor_clean','interior_deep_clean')
                      THEN 0 ELSE w.soil_index END,
    cabin_litter_events = CASE WHEN p_service IN ('interior_tidy','interior_deep_clean')
                      THEN 0 ELSE w.cabin_litter_events END,
    km_at_last_pm = CASE WHEN p_service = 'mechanical_pm'
                      THEN w.drive_km_total ELSE w.km_at_last_pm END,
    hours_at_last_calibration = CASE WHEN p_service = 'sensor_calibration'
                      THEN w.drive_hours_total ELSE w.hours_at_last_calibration END,
    calibrated_at = CASE WHEN p_service = 'sensor_calibration'
                      THEN p_clock ELSE w.calibrated_at END,
    open_dtc_count = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
                      THEN 0 ELSE w.open_dtc_count END,
    worst_open_dtc_rank = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
                      THEN 99 ELSE w.worst_open_dtc_rank END,
    updated_at = now()
  WHERE w.vehicle_id = p_vehicle_id AND w.sim_run_id = p_sim_run_id;

  -- v4: a completed wash restarts this vehicle's deploy-cycle wash cadence
  IF p_service = 'exterior_wash' THEN
    UPDATE vehicles
       SET config = jsonb_set(COALESCE(config,'{}'::jsonb), '{cycles_since_wash}', '0'::jsonb)
     WHERE id = p_vehicle_id;
  END IF;
  RETURN FOUND;
END;
$function$


-- ===== sync_stall_occupancy =====
CREATE OR REPLACE FUNCTION public.sync_stall_occupancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  -- Clear old stall
  IF OLD.current_stall_id IS NOT NULL AND OLD.current_stall_id IS DISTINCT FROM NEW.current_stall_id THEN
    UPDATE stalls SET
      status = 'available',
      current_vehicle_id = NULL
    WHERE id = OLD.current_stall_id;
  END IF;

  -- Occupy new stall
  IF NEW.current_stall_id IS NOT NULL AND OLD.current_stall_id IS DISTINCT FROM NEW.current_stall_id THEN
    UPDATE stalls SET
      status = 'occupied',
      current_vehicle_id = NEW.id
    WHERE id = NEW.current_stall_id;
  END IF;

  RETURN NEW;
END;
$function$


-- ===== update_timestamp =====
CREATE OR REPLACE FUNCTION public.update_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$


-- ===== update_updated_at_column =====
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $function$


-- ===== update_wave_count =====
CREATE OR REPLACE FUNCTION public.update_wave_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    IF NEW.wave_id IS NOT NULL THEN
      UPDATE waves SET vehicle_count = (
        SELECT COUNT(*) FROM vehicle_schedules WHERE wave_id = NEW.wave_id AND status != 'cancelled'
      ) WHERE id = NEW.wave_id;
    END IF;
  END IF;

  IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
    IF OLD.wave_id IS NOT NULL AND (TG_OP = 'DELETE' OR OLD.wave_id IS DISTINCT FROM NEW.wave_id) THEN
      UPDATE waves SET vehicle_count = (
        SELECT COUNT(*) FROM vehicle_schedules WHERE wave_id = OLD.wave_id AND status != 'cancelled'
      ) WHERE id = OLD.wave_id;
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$


-- ===== validate_depot_snapshot =====
CREATE OR REPLACE FUNCTION public.validate_depot_snapshot(snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  errors JSONB := '[]'::JSONB;
  stall_util JSONB;
  snap_at TIMESTAMPTZ;
  demand NUMERIC;
BEGIN
  -- Required fields
  IF snapshot->>'depot_id' IS NULL THEN
    errors := errors || jsonb_build_array(jsonb_build_object(
      'field', 'depot_id', 'error_type', 'null_required_field',
      'message', 'depot_id is required'));
  END IF;

  -- snapshot_at must exist and not be in the future (> 5 min skew allowed)
  snap_at := (snapshot->>'snapshot_at')::TIMESTAMPTZ;
  IF snap_at IS NULL THEN
    errors := errors || jsonb_build_array(jsonb_build_object(
      'field', 'snapshot_at', 'error_type', 'null_required_field',
      'message', 'snapshot_at is required'));
  ELSIF snap_at > NOW() + INTERVAL '5 minutes' THEN
    errors := errors || jsonb_build_array(jsonb_build_object(
      'field', 'snapshot_at', 'error_type', 'out_of_range',
      'message', 'snapshot_at is in the future',
      'actual', snap_at::TEXT));
  END IF;

  -- Vehicle count sanity: on_site >= charging + in_service + staged
  IF (snapshot->>'vehicles_on_site')::INTEGER <
     COALESCE((snapshot->>'vehicles_charging')::INTEGER, 0)
     + COALESCE((snapshot->>'vehicles_in_service')::INTEGER, 0)
     + COALESCE((snapshot->>'vehicles_staged')::INTEGER, 0)
  THEN
    errors := errors || jsonb_build_array(jsonb_build_object(
      'field', 'vehicles_on_site', 'error_type', 'monotonic_violation',
      'message', 'vehicles_on_site must be >= charging + in_service + staged'));
  END IF;

  -- Demand physical plausibility
  demand := (snapshot->>'current_demand_kw')::NUMERIC;
  IF demand IS NOT NULL AND (demand < 0 OR demand > 5000) THEN
    errors := errors || jsonb_build_array(jsonb_build_object(
      'field', 'current_demand_kw', 'error_type', 'physical_implausibility',
      'message', 'current_demand_kw outside plausible range [0, 5000]',
      'actual', demand::TEXT));
  END IF;

  -- stall_utilization JSONB shape (if present)
  stall_util := snapshot->'stall_utilization';
  IF stall_util IS NOT NULL AND jsonb_typeof(stall_util) != 'object' THEN
    errors := errors || jsonb_build_array(jsonb_build_object(
      'field', 'stall_utilization', 'error_type', 'schema_mismatch',
      'message', 'stall_utilization must be a JSON object'));
  END IF;

  -- Health score range
  IF (snapshot->>'depot_health_score') IS NOT NULL
     AND ((snapshot->>'depot_health_score')::NUMERIC < 0
          OR (snapshot->>'depot_health_score')::NUMERIC > 1)
  THEN
    errors := errors || jsonb_build_array(jsonb_build_object(
      'field', 'depot_health_score', 'error_type', 'out_of_range',
      'message', 'depot_health_score must be in [0, 1]'));
  END IF;

  RETURN jsonb_build_object(
    'valid', jsonb_array_length(errors) = 0,
    'errors', errors,
    'checked_at', NOW()
  );
END;
$function$


-- ===== workload_harness_metrics =====
CREATE OR REPLACE FUNCTION public.workload_harness_metrics(p_sim_run_id uuid)
 RETURNS TABLE(section text, metric text, value numeric, denom numeric, per_arrival numeric, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_s timestamptz; v_e timestamptz;
  v_sim_min numeric; v_arrivals numeric; v_win tstzrange; v_bucket_cap numeric;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN; END IF;
  v_s := v_run.sim_clock_start;
  v_e := GREATEST(v_run.sim_clock_current, v_run.sim_clock_start);
  v_win := tstzrange(v_s, v_e, '[)');
  v_sim_min := ROUND(EXTRACT(epoch FROM (v_e - v_s))/60.0, 3);

  SELECT COUNT(*)::numeric INTO v_arrivals
    FROM ottoq_vehicle_dispatches d
   WHERE d.sim_run_id = p_sim_run_id AND d.actual_return_at IS NOT NULL
     AND COALESCE(d.return_trigger,'') NOT IN ('run_stopped','run_reseed_abort')
     AND d.actual_return_at <@ v_win;

  RETURN QUERY SELECT '0_window'::text,'sim_minutes'::text, v_sim_min, NULL::numeric, NULL::numeric,
    format('%s -> %s', v_s, v_e)::text;
  RETURN QUERY SELECT '0_window','ticks', v_run.tick_count::numeric, v_sim_min, NULL::numeric,
    format('%s sim-min per tick, %s ticks/sim-min. playback=%s. LIVE playback derives sim time from REAL elapsed time, so this ratio is NOT seed-stable; FIXED playback is.',
      ROUND(v_sim_min / NULLIF(v_run.tick_count,0), 3),
      ROUND(v_run.tick_count::numeric / NULLIF(v_sim_min,0), 3),
      COALESCE(v_run.payload->>'playback_mode','fixed'))::text;
  RETURN QUERY SELECT '0_window','real_minutes',
    ROUND(EXTRACT(epoch FROM (COALESCE(v_run.ended_at, v_run.last_tick_at) - v_run.started_at))/60.0, 2),
    NULL::numeric, NULL::numeric, COALESCE(v_run.payload->>'playback_mode','fixed')::text;
  RETURN QUERY SELECT '0_window','seed', v_run.random_seed::numeric, NULL::numeric, NULL::numeric,
    format('scenario=%s run_by=%s status=%s', v_run.scenario_code, v_run.run_by, v_run.status)::text;
  RETURN QUERY SELECT '0_window','overrides_applied',
    (CASE WHEN COALESCE((v_run.payload#>>'{scenario_overrides,ok}')::boolean,false) THEN 1 ELSE 0 END)::numeric,
    NULL::numeric, NULL::numeric,
    COALESCE(v_run.payload#>>'{scenario_overrides,policy_applied}',
             'NONE - scenario fleet_overrides were NOT applied to this run')::text;
  RETURN QUERY SELECT '0_window','vehicles_scaled',
    COALESCE((v_run.payload#>>'{scenario_overrides,vehicles_scaled}')::numeric,0),
    NULL::numeric, NULL::numeric,
    format('wear_rows_phased=%s pm_scale=%s',
      COALESCE(v_run.payload#>>'{scenario_overrides,wear_rows_phased}','0'),
      COALESCE(v_run.payload#>>'{scenario_overrides,pm_km_scale}','1'))::text;

  RETURN QUERY SELECT '1_workload','arrivals', v_arrivals, v_sim_min, NULL::numeric,
    format('%s arrivals/sim-min', ROUND(v_arrivals/NULLIF(v_sim_min,0), 4))::text;
  RETURN QUERY SELECT '1_workload','arriving_vehicles_distinct',
    (SELECT COUNT(DISTINCT d.vehicle_id)::numeric FROM ottoq_vehicle_dispatches d
      WHERE d.sim_run_id=p_sim_run_id AND d.actual_return_at IS NOT NULL
        AND COALESCE(d.return_trigger,'') NOT IN ('run_stopped','run_reseed_abort')
        AND d.actual_return_at <@ v_win),
    v_arrivals, NULL::numeric, 'repeat visits = arrivals - distinct'::text;
  RETURN QUERY SELECT '1_workload','boot_primed_deployed',
    COALESCE((v_run.payload#>>'{boot_prime,primed}')::numeric,0), NULL::numeric, NULL::numeric,
    format('prime_fraction=%s pool=%s start_hour_cst=%s',
      COALESCE(v_run.payload#>>'{boot_prime,prime_fraction}','?'),
      COALESCE(v_run.payload#>>'{boot_prime,candidate_pool}','?'),
      COALESCE(v_run.payload#>>'{boot_prime,start_hour_cst}','?'))::text;
  RETURN QUERY SELECT '1_workload','dispatches_total',
    (SELECT COUNT(*)::numeric FROM ottoq_vehicle_dispatches d WHERE d.sim_run_id=p_sim_run_id),
    NULL::numeric, NULL::numeric, 'includes the boot prime'::text;
  RETURN QUERY SELECT '1_workload','redeployed_after_visit',
    (SELECT COUNT(*)::numeric FROM ottoq_vehicle_dispatches d
      WHERE d.sim_run_id=p_sim_run_id AND d.dispatched_at > v_s),
    v_arrivals,
    ROUND((SELECT COUNT(*)::numeric FROM ottoq_vehicle_dispatches d
            WHERE d.sim_run_id=p_sim_run_id AND d.dispatched_at > v_s) / NULLIF(v_arrivals,0), 3),
    'FLOW CHECK: redeployments per arrival. ~1.0 = vehicles flow through; near 0 = they pile up.'::text;

  RETURN QUERY
  WITH ev AS (
    SELECT d.actual_return_at AS t, 1 AS delta FROM ottoq_vehicle_dispatches d
     WHERE d.sim_run_id=p_sim_run_id AND d.actual_return_at IS NOT NULL
       AND COALESCE(d.return_trigger,'') NOT IN ('run_stopped','run_reseed_abort')
       AND d.actual_return_at <@ v_win
    UNION ALL
    SELECT d.dispatched_at, -1 FROM ottoq_vehicle_dispatches d
     WHERE d.sim_run_id=p_sim_run_id AND d.dispatched_at > v_s AND d.dispatched_at <@ v_win
  ), run AS (SELECT SUM(delta) OVER (ORDER BY t, delta) AS c FROM ev)
  SELECT '1_workload','peak_queue_growth', COALESCE(MAX(c),0)::numeric, v_arrivals,
         ROUND(COALESCE(MAX(c),0)::numeric / NULLIF(v_arrivals,0), 3),
         'PILE-UP CHECK: peak (arrivals - redeployments). Bounded and re-drained = flow; monotonically rising = a queue.'::text
    FROM run;

  v_bucket_cap := LEAST(GREATEST(1, CEIL(v_sim_min/15.0)), GREATEST(1, v_run.tick_count))::numeric;
  RETURN QUERY
  WITH buckets AS (
    SELECT width_bucket(EXTRACT(epoch FROM (d.actual_return_at - v_s))/60.0,
                        0, GREATEST(v_sim_min,1), GREATEST(1, CEIL(v_sim_min/15.0)::int)) AS b
      FROM ottoq_vehicle_dispatches d
     WHERE d.sim_run_id=p_sim_run_id AND d.actual_return_at IS NOT NULL
       AND COALESCE(d.return_trigger,'') NOT IN ('run_stopped','run_reseed_abort')
       AND d.actual_return_at <@ v_win)
  SELECT '1_workload','arrival_buckets_covered', COUNT(DISTINCT b)::numeric, v_bucket_cap,
         ROUND(100.0*COUNT(DISTINCT b)::numeric / NULLIF(v_bucket_cap,0),1),
         'SUSTAIN CHECK: 15-sim-min buckets with >=1 arrival, over the attainable ceiling (min of buckets, ticks). per_arrival column = percent covered.'::text
    FROM buckets;

  RETURN QUERY SELECT '1_workload','return_trigger_mix', NULL::numeric, NULL::numeric, NULL::numeric,
    COALESCE((SELECT string_agg(t||'='||n, ', ' ORDER BY n DESC) FROM (
       SELECT COALESCE(d.return_trigger,'(null)') t, COUNT(*) n
         FROM ottoq_vehicle_dispatches d WHERE d.sim_run_id=p_sim_run_id
          AND d.returning_started_at IS NOT NULL GROUP BY 1) x), 'none')::text;

  RETURN QUERY SELECT '2_assignments','stall_assignments_enacted',
    (SELECT COUNT(*)::numeric FROM ottoq_decisions dc
      WHERE dc.sim_run_id=p_sim_run_id
        AND COALESCE(dc.resolved_action_context, dc.action_context)='stall_assignment'
        AND dc.outcome_status='enacted'),
    v_arrivals,
    ROUND((SELECT COUNT(*)::numeric FROM ottoq_decisions dc
            WHERE dc.sim_run_id=p_sim_run_id
              AND COALESCE(dc.resolved_action_context, dc.action_context)='stall_assignment'
              AND dc.outcome_status='enacted') / NULLIF(v_arrivals,0), 3),
    'PRIMARY METRIC: assignments per ARRIVING VEHICLE. ~1.0 = each car placed once; >>1.0 = re-booking churn, not throughput.'::text;

  RETURN QUERY SELECT '3_churn','bookings_total',
    (SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b WHERE b.sim_run_id=p_sim_run_id),
    v_arrivals,
    ROUND((SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b WHERE b.sim_run_id=p_sim_run_id)
          / NULLIF(v_arrivals,0), 3), 'all states'::text;
  RETURN QUERY SELECT '3_churn','bookings_superseded',
    (SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b WHERE b.sim_run_id=p_sim_run_id AND b.state='superseded'),
    v_arrivals,
    ROUND((SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b
            WHERE b.sim_run_id=p_sim_run_id AND b.state='superseded') / NULLIF(v_arrivals,0), 3),
    'CHURN. Every superseded booking is a plan that was thrown away.'::text;
  RETURN QUERY SELECT '3_churn','bookings_released',
    (SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b WHERE b.sim_run_id=p_sim_run_id AND b.state='released'),
    v_arrivals, NULL::numeric, 'window elapsed / handed back (a stop releases all open bookings, so this is inflated at teardown)'::text;

  -- ===================== 4_work  (BUILD 2 corrected) =====================
  RETURN QUERY SELECT '4_work','work_sessions_done',
    (SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b
      WHERE b.sim_run_id=p_sim_run_id AND b.state='done' AND ottoq.ottoq_is_work_purpose(b.purpose)),
    v_arrivals,
    ROUND((SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b
            WHERE b.sim_run_id=p_sim_run_id AND b.state='done' AND ottoq.ottoq_is_work_purpose(b.purpose))
          / NULLIF(v_arrivals,0), 3),
    'PRIMARY METRIC: work FINISHED per arriving vehicle. BUILD 2: `done` now excludes the terminal state `interrupted` (occupied the bay but did not finish), and parking (temp_hold/staging/perimeter_hold) is excluded - parking is not work.'::text;

  RETURN QUERY SELECT '4_work','work_sessions_interrupted',
    (SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b
      WHERE b.sim_run_id=p_sim_run_id AND b.state='interrupted'),
    v_arrivals,
    ROUND((SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b
            WHERE b.sim_run_id=p_sim_run_id AND b.state='interrupted') / NULLIF(v_arrivals,0), 3),
    'HONESTY LINE: bay sessions that occupied a space but did NOT finish the planned work (actual < 80% of planned, shortfall >= 120s). These used to be counted as completions.'::text;

  RETURN QUERY SELECT '4_work','work_sessions_done_legacy_definition',
    (SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b
      WHERE b.sim_run_id=p_sim_run_id AND b.state IN ('done','interrupted') AND b.purpose <> 'temp_hold'),
    v_arrivals,
    ROUND((SELECT COUNT(*)::numeric FROM ottoq_stall_bookings b
            WHERE b.sim_run_id=p_sim_run_id AND b.state IN ('done','interrupted') AND b.purpose <> 'temp_hold')
          / NULLIF(v_arrivals,0), 3),
    'PRE-BUILD-2 DEFINITION, kept visible on purpose so the correction can never be hidden: counted interrupted sessions AND parking as completed work.'::text;

  RETURN QUERY SELECT '4_work','vehicles_served_distinct',
    (SELECT COUNT(DISTINCT b.vehicle_id)::numeric FROM ottoq_stall_bookings b
      WHERE b.sim_run_id=p_sim_run_id AND b.state='done' AND ottoq.ottoq_is_work_purpose(b.purpose)),
    v_arrivals, NULL::numeric, 'coverage of the arriving population (finished work only)'::text;
  RETURN QUERY SELECT '4_work','work_purpose_mix', NULL::numeric, NULL::numeric, NULL::numeric,
    COALESCE((SELECT string_agg(p||'='||n, ', ' ORDER BY n DESC) FROM (
      SELECT b.purpose p, COUNT(*) n FROM ottoq_stall_bookings b
       WHERE b.sim_run_id=p_sim_run_id AND b.state='done' AND ottoq.ottoq_is_work_purpose(b.purpose)
       GROUP BY 1) x), 'none')::text;
  RETURN QUERY SELECT '4_work','interrupted_purpose_mix', NULL::numeric, NULL::numeric, NULL::numeric,
    COALESCE((SELECT string_agg(p||'='||n, ', ' ORDER BY n DESC) FROM (
      SELECT b.purpose p, COUNT(*) n FROM ottoq_stall_bookings b
       WHERE b.sim_run_id=p_sim_run_id AND b.state='interrupted'
       GROUP BY 1) x), 'none')::text;

  -- ===================== 5_utilisation =====================
  -- BUILD 2: `interrupted` IS occupancy-bearing here. The vehicle really was in the stall
  -- for the clipped interval, so dropping it would understate how busy the depot was.
  RETURN QUERY
  WITH occupied AS (
    SELECT s.stall_kind::text AS stall_kind, b.stall_id, b.during * v_win AS d
      FROM ottoq_stall_bookings b JOIN stalls s ON s.id = b.stall_id
     WHERE b.sim_run_id = p_sim_run_id
       AND s.depot_id = v_run.depot_id
       AND b.state IN ('held','active','done','interrupted') AND b.during && v_win
  ), merged AS (
    SELECT o.stall_kind, o.stall_id, range_agg(o.d) AS m FROM occupied o WHERE NOT isempty(o.d) GROUP BY 1,2
  ), busy AS (
    SELECT m.stall_kind, SUM(EXTRACT(epoch FROM (upper(r) - lower(r)))/60.0) AS busy_min
      FROM merged m CROSS JOIN LATERAL unnest(m.m) AS r GROUP BY 1
  ), cap AS (
    SELECT s.stall_kind::text AS stall_kind, COUNT(*)::numeric * v_sim_min AS cap_min, COUNT(*)::numeric AS n
      FROM stalls s WHERE s.depot_id = v_run.depot_id GROUP BY 1
  )
  SELECT '5_utilisation'::text, ('stall_kind:'||c.stall_kind)::text,
         ROUND(COALESCE(b.busy_min,0),1), ROUND(c.cap_min,1),
         ROUND(100.0 * COALESCE(b.busy_min,0) / NULLIF(c.cap_min,0), 1),
         format('%s stalls; per_arrival column here is PERCENT OCCUPIED (union-of-intervals clipped to window; includes interrupted sessions - the space really was occupied)', c.n)::text
    FROM cap c LEFT JOIN busy b ON b.stall_kind = c.stall_kind;

  -- ZONE-SCOPED INSPECTION LINE (2026-08-03). stall_kind and zone agree at this depot
  -- (all 14 arrival_inspection stalls carry stall_kind='inspection'), so this line and the
  -- stall_kind:inspection line above MUST match. They are both reported so any future divergence
  -- is visible instead of arguable. NOTE the denominator is DEPOT-SCOPED: a depot-blind
  -- "SELECT count(*) FROM stalls WHERE zone='arrival_inspection'" returns 28 because the
  -- database holds TWO seeded depots -- that is a two-depot count, not this run's capacity.
  RETURN QUERY
  WITH occ AS (
    SELECT b.stall_id, b.purpose, b.during * v_win AS d
      FROM ottoq_stall_bookings b JOIN stalls s ON s.id = b.stall_id
     WHERE b.sim_run_id = p_sim_run_id
       AND s.depot_id = v_run.depot_id
       AND s.zone = 'arrival_inspection'
       AND b.state IN ('held','active','done','interrupted') AND b.during && v_win
  ), merged AS (
    SELECT o.stall_id, range_agg(o.d) AS m FROM occ o WHERE NOT isempty(o.d) GROUP BY 1
  ), busy AS (
    SELECT SUM(EXTRACT(epoch FROM (upper(r) - lower(r)))/60.0) AS busy_min
      FROM merged m CROSS JOIN LATERAL unnest(m.m) AS r
  ), park AS (
    SELECT COALESCE(SUM(EXTRACT(epoch FROM (upper(o.d) - lower(o.d)))/60.0),0) AS park_min,
           COUNT(*) AS park_bookings
      FROM occ o WHERE o.purpose IN ('temp_hold','perimeter_hold','staging') AND NOT isempty(o.d)
  ), n AS (
    SELECT COUNT(*)::numeric AS stalls FROM stalls s
     WHERE s.depot_id = v_run.depot_id AND s.zone = 'arrival_inspection'
  )
  SELECT '5_utilisation'::text, 'zone:arrival_inspection'::text,
         ROUND(COALESCE(busy.busy_min,0),1), ROUND(n.stalls * v_sim_min, 1),
         ROUND(100.0 * COALESCE(busy.busy_min,0) / NULLIF(n.stalls * v_sim_min,0), 1),
         format('MY OWN DENOMINATOR: %s stalls WHERE zone=arrival_inspection AND depot_id=%s (this run''s depot), times %s sim-min. per_arrival column = PERCENT OCCUPIED (union of intervals clipped to window). A depot-BLIND count of that zone returns 28 across the two seeded depots and would halve this figure.',
                n.stalls, v_run.depot_id, v_sim_min)::text
    FROM busy, n;

  RETURN QUERY
  WITH occ AS (
    SELECT b.purpose, b.during * v_win AS d
      FROM ottoq_stall_bookings b JOIN stalls s ON s.id = b.stall_id
     WHERE b.sim_run_id = p_sim_run_id
       AND s.depot_id = v_run.depot_id
       AND s.zone = 'arrival_inspection'
       AND b.state IN ('held','active','done','interrupted') AND b.during && v_win
       AND NOT isempty(b.during * v_win)
  )
  SELECT '5_utilisation'::text, 'zone:arrival_inspection_parking_squat'::text,
         ROUND(COALESCE(SUM(EXTRACT(epoch FROM (upper(d)-lower(d)))/60.0)
                        FILTER (WHERE purpose IN ('temp_hold','perimeter_hold','staging')),0),1),
         ROUND(COALESCE(SUM(EXTRACT(epoch FROM (upper(d)-lower(d)))/60.0),0),1),
         ROUND(100.0 * COALESCE(SUM(EXTRACT(epoch FROM (upper(d)-lower(d)))/60.0)
                        FILTER (WHERE purpose IN ('temp_hold','perimeter_hold','staging')),0)
               / NULLIF(COALESCE(SUM(EXTRACT(epoch FROM (upper(d)-lower(d)))/60.0),0),0), 1),
         format('TARGET 0. Parking stall-minutes as a share of ALL occupied stall-minutes in the inspection zone (NOT union-merged - this is a per-booking sum so the purpose split adds up). Mix: %s',
                COALESCE((SELECT string_agg(x.p||'='||x.n, ', ' ORDER BY x.n DESC) FROM (
                   SELECT purpose p, COUNT(*) n FROM occ GROUP BY 1) x), 'none'))::text
    FROM occ;

  RETURN QUERY SELECT '6_fingerprint','arrival_sequence_md5', NULL::numeric, NULL::numeric, NULL::numeric,
    COALESCE((SELECT md5(string_agg(d.vehicle_id::text||'@'||d.actual_return_at::text||'/'||COALESCE(d.return_trigger,''), '|'
                          ORDER BY d.actual_return_at, d.vehicle_id))
       FROM ottoq_vehicle_dispatches d
      WHERE d.sim_run_id=p_sim_run_id AND d.actual_return_at IS NOT NULL
        AND COALESCE(d.return_trigger,'') NOT IN ('run_stopped','run_reseed_abort')), 'none')::text;
  RETURN QUERY SELECT '6_fingerprint','wear_state_md5_end_of_run', NULL::numeric, NULL::numeric, NULL::numeric,
    COALESCE((SELECT md5(string_agg(w.vehicle_id::text||':'||w.km_at_last_pm::text||':'||w.hours_at_last_calibration::text, '|'
                          ORDER BY w.vehicle_id))
       FROM ottoq_vehicle_wear w WHERE w.sim_run_id=p_sim_run_id), 'none')::text;
  -- ============ 7_invariants: EMISSION COMPLETENESS ============
  -- Phase 10 shipped a metric that could only ever observe 3.8% of reality: 50 of 52
  -- bookings reached state='interrupted' WITHOUT emitting ottoq.booking_interrupted.
  -- This invariant makes that class of blindness self-reporting. Any gap is a BLIND SPOT:
  -- do not trust ANY interruption-derived number in the same run until it reads 1.000.
  RETURN QUERY
  WITH b AS (SELECT COUNT(DISTINCT sb.booking_id)::numeric n
               FROM ottoq_stall_bookings sb
              WHERE sb.sim_run_id = p_sim_run_id AND sb.state = 'interrupted'),
       e AS (SELECT COUNT(DISTINCT (ev.payload->>'booking_id'))::numeric n
               FROM ottoq_events ev
              WHERE ev.sim_run_id = p_sim_run_id
                AND ev.event_type = 'ottoq.booking_interrupted'
                AND NULLIF(ev.payload->>'booking_id','') IS NOT NULL)
  SELECT '7_invariants'::text, 'interruption_emission_ratio'::text,
         ROUND(e.n / NULLIF(b.n,0), 3), b.n, NULL::numeric,
         format('TARGET 1.000 (1:1). %s bookings state=interrupted vs %s distinct booking_ids in ottoq.booking_interrupted events. %s',
                b.n, e.n,
                CASE WHEN b.n = 0 AND e.n = 0 THEN 'PASS (no interruptions this run)'
                     WHEN b.n = e.n THEN 'PASS - every interruption emitted'
                     WHEN e.n < b.n THEN '*** FAIL: BLIND SPOT - ' || (b.n - e.n)::text ||
                          ' interruption(s) emitted NOTHING. Interruption metrics are UNDER-COUNTING; do not quote them.'
                     ELSE '*** FAIL: MORE events than interrupted bookings (' || (e.n - b.n)::text ||
                          ' extra) - double emission or stale booking_ids.' END)::text
    FROM b, e;

  -- Companion: which paths emitted, so a future gap is attributable to a specific writer.
  RETURN QUERY
  SELECT '7_invariants'::text, 'interruption_emission_by_reason'::text, NULL::numeric, NULL::numeric, NULL::numeric,
         COALESCE((SELECT string_agg(x.reason||'='||x.bk||'bk/'||x.evn||'ev', ', ' ORDER BY x.bk DESC)
                     FROM (SELECT COALESCE(sb.release_reason,'(null)') reason,
                                  COUNT(DISTINCT sb.booking_id) bk,
                                  COUNT(DISTINCT ev.payload->>'booking_id') evn
                             FROM ottoq_stall_bookings sb
                             LEFT JOIN ottoq_events ev
                               ON ev.sim_run_id = sb.sim_run_id
                              AND ev.event_type = 'ottoq.booking_interrupted'
                              AND (ev.payload->>'booking_id')::uuid = sb.booking_id
                            WHERE sb.sim_run_id = p_sim_run_id AND sb.state = 'interrupted'
                            GROUP BY 1) x), 'none')::text;

  -- ============ 7_invariants: SUPPLY-COUNT HONESTY (P1 2026-08-03) ============
  -- Any cuOpt edge call reporting free_stalls_in = 0 while stalls were provably
  -- free is a DEFECT: the optimiser was starved by a counting error rather than
  -- by real congestion. TARGET 0. Anything above 0 means the availability read
  -- has regressed again -- do NOT trust cuOpt share/enactment numbers from the
  -- same run until this reads 0.
  RETURN QUERY
  WITH calls AS (
    SELECT l.id_key, l.sim_clock, l.free_stalls_in,
           NULLIF(l.detail->>'physically_free_stalls','')::numeric AS self_free
      FROM (SELECT ROW_NUMBER() OVER (ORDER BY cl.called_at) AS id_key, cl.*
              FROM cuopt_invocation_log cl
             WHERE cl.stage='edge' AND cl.sim_run_id = p_sim_run_id
               AND cl.free_stalls_in IS NOT NULL) l
  ),
  tot AS (
    SELECT COUNT(*)::numeric n FROM stalls s
     WHERE s.depot_id = v_run.depot_id AND s.stall_type::text IN ('dcfc','l2')
  ),
  busy AS (
    SELECT c.id_key, COUNT(DISTINCT b.stall_id)::numeric n
      FROM calls c
      JOIN ottoq_stall_bookings b
        ON b.sim_run_id = p_sim_run_id
       AND b.state IN ('held','active','done','interrupted')
       AND c.sim_clock IS NOT NULL AND b.during @> c.sim_clock
      JOIN stalls s ON s.id = b.stall_id
       AND s.depot_id = v_run.depot_id AND s.stall_type::text IN ('dcfc','l2')
     GROUP BY 1
  ),
  scored AS (
    SELECT c.free_stalls_in,
           COALESCE(c.self_free, t.n - COALESCE(bu.n,0)) AS provably_free
      FROM calls c CROSS JOIN tot t LEFT JOIN busy bu ON bu.id_key = c.id_key
  )
  SELECT '7_invariants'::text, 'cuopt_free_stall_undercount'::text,
         COUNT(*) FILTER (WHERE free_stalls_in = 0 AND provably_free > 0)::numeric,
         COUNT(*)::numeric,
         ROUND(100.0 * COUNT(*) FILTER (WHERE free_stalls_in = 0 AND provably_free > 0)
               / NULLIF(COUNT(*),0), 1),
         format('TARGET 0. %s of %s edge calls reported free_stalls_in=0 while %s stalls were provably free (avg on those calls). Witness: edge physically_free_stalls when present, else the booking ledger (held/active/done/interrupted covering that sim_clock), charge stalls scoped to this depot. Above 0 => the availability read has regressed; cuOpt share numbers from this run are NOT trustworthy.',
                COUNT(*) FILTER (WHERE free_stalls_in = 0 AND provably_free > 0),
                COUNT(*),
                COALESCE(ROUND(AVG(provably_free) FILTER (WHERE free_stalls_in = 0 AND provably_free > 0),2),0))::text
    FROM scored;


  RETURN;
END;
$function$
