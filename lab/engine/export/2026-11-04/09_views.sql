-- 09_views.sql: 90 statements, exported from production's catalog
-- @@ view public.calendar_ledger_integrity
CREATE VIEW public.calendar_ledger_integrity AS
 SELECT b.sim_run_id,
    b.booking_id,
    b.vehicle_id,
    b.stall_id,
    (s.stall_type)::text AS stall_type,
    b.state,
    b.release_reason,
    b.booked_by,
    b.source,
    b.decision_id,
    (b.decision_id IS NOT NULL) AS backed_by_key,
    (b.source IS NOT NULL) AS has_provenance,
    (EXISTS ( SELECT 1
           FROM public.ottoq_decisions d
          WHERE ((d.sim_run_id = b.sim_run_id) AND (d.outcome_status = 'enacted'::text) AND (d.entity_id = b.vehicle_id) AND ((NULLIF((d.enacted_action ->> 'stall_id'::text), ''::text))::uuid = b.stall_id)))) AS backed_by_inference,
    ((b.booked_by = 'otto_q_enacted'::text) AND (b.decision_id IS NULL) AND (b.source IS NULL) AND (NOT (EXISTS ( SELECT 1
           FROM public.ottoq_decisions d
          WHERE ((d.sim_run_id = b.sim_run_id) AND (d.outcome_status = 'enacted'::text) AND (d.entity_id = b.vehicle_id) AND ((NULLIF((d.enacted_action ->> 'stall_id'::text), ''::text))::uuid = b.stall_id)))))) AS is_phantom
   FROM (public.ottoq_stall_bookings b
     JOIN public.stalls s ON ((s.id = b.stall_id)));
-- @@ view public.kernel_asset_classes
CREATE VIEW public.kernel_asset_classes WITH (security_invoker=true) AS
 SELECT vehicle_class_code AS asset_class_code,
    pack_id,
    oem_name AS operator_name,
    manufacturer,
    model,
    battery_capacity_kwh,
    max_charge_rate_kw,
    inlet_type,
    energy_curve,
    duty_cycle_profile,
    status
   FROM public.ottoq_vehicle_classes;
-- @@ view public.kernel_assets
CREATE VIEW public.kernel_assets WITH (security_invoker=true) AS
 SELECT id AS asset_id,
    vehicle_class_code AS asset_class_code,
    (category)::text AS asset_category,
    fleet_operator_id AS operator_id,
    home_depot_id AS home_site_id,
    current_depot_id AS current_site_id,
    current_stall_id AS current_point_id,
    (current_state)::text AS state,
    current_soc,
    target_soc,
    is_active,
    owning_sim_run_id
   FROM public.vehicles v;
-- @@ view public.kernel_service_points
CREATE VIEW public.kernel_service_points WITH (security_invoker=true) AS
 SELECT id AS service_point_id,
    depot_id AS site_id,
    stall_code AS point_code,
    (stall_type)::text AS point_kind,
    status,
    connector_max_kw,
    supported_inlet_types,
    zone,
    covered
   FROM public.stalls s;
-- @@ view public.ottoq_accuracy_trend_daily
CREATE VIEW public.ottoq_accuracy_trend_daily WITH (security_invoker=on) AS
 SELECT prediction_type,
    report_date,
    count(*) AS cells,
    sum(n_scored) AS total_scored,
    round(avg(mae), 3) AS avg_mae,
    round(avg(mape), 2) AS avg_mape,
    round(avg(coverage_80), 3) AS avg_coverage_80,
    round(avg(bias), 3) AS avg_bias
   FROM public.ottoq_prediction_accuracy_heatmap
  WHERE (report_date >= (CURRENT_DATE - 30))
  GROUP BY prediction_type, report_date
  ORDER BY prediction_type, report_date DESC;
-- @@ view public.ottoq_accuracy_weak_spots
CREATE VIEW public.ottoq_accuracy_weak_spots WITH (security_invoker=on) AS
 SELECT prediction_type,
    depot_id,
    fleet_operator_id,
    hour_of_day,
    day_of_week,
    n_scored,
    mae,
    mape,
    bias,
    coverage_80,
    report_date
   FROM public.ottoq_prediction_accuracy_heatmap
  WHERE ((report_date >= (CURRENT_DATE - 30)) AND (n_scored >= 20) AND ((mape > (20)::numeric) OR (coverage_80 < 0.6)))
  ORDER BY mape DESC NULLS LAST, coverage_80;
-- @@ view public.ottoq_active_emergencies
CREATE VIEW public.ottoq_active_emergencies WITH (security_invoker=on) AS
 SELECT i.invocation_id,
    i.protocol_code,
    p.title,
    p.category,
    p.severity,
    i.depot_id,
    i.triggered_at,
    (EXTRACT(epoch FROM (now() - i.triggered_at)))::integer AS active_seconds,
    i.outcome,
    i.cascade_executed,
    i.correlation_id
   FROM (public.ottoq_emergency_invocations i
     JOIN public.ottoq_emergency_protocols p ON ((p.protocol_code = i.protocol_code)))
  WHERE (i.cleared_at IS NULL)
  ORDER BY i.triggered_at DESC;
-- @@ view public.ottoq_active_layer2_recommendations
CREATE VIEW public.ottoq_active_layer2_recommendations WITH (security_invoker=on) AS
 SELECT recommendation_id,
    emitted_at,
    prediction_id,
    prediction_type,
    proposed_action,
    action_parameters,
    entity_type,
    entity_id,
    fleet_operator_id,
    depot_id,
    status,
    decision_reason,
    rules_blocked_by,
    expires_at,
    shadow_only,
    correlation_id,
    (EXTRACT(epoch FROM (now() - emitted_at)))::integer AS age_seconds
   FROM public.ottoq_recommendations r
  WHERE ((status = ANY (ARRAY['pending'::text, 'validating'::text, 'admitted'::text, 'shadow'::text])) AND ((expires_at IS NULL) OR (expires_at > now())))
  ORDER BY emitted_at DESC;
-- @@ view public.ottoq_active_predictions
CREATE VIEW public.ottoq_active_predictions WITH (security_invoker=on) AS
 SELECT id,
    depot_id,
    fleet_operator_id,
    vehicle_id,
    prediction_type,
    title,
    description,
    predicted_value,
    p10,
    p50,
    p90,
    prediction_interval_method,
    calibration_score,
    prediction_baseline,
    confidence,
    target_at,
    horizon_minutes,
    recommendation,
    action_type,
    action_parameters,
    status,
    execution_status,
    model_version_id,
    ab_test_id,
    ab_test_variant,
    shadow_only,
    correlation_id,
    event_id,
    latency_ms,
    created_at,
    expires_at
   FROM public.ottoq_predictions p
  WHERE ((status = ANY (ARRAY['proposed'::text, 'approved'::text, 'executing'::text])) AND ((expires_at IS NULL) OR (expires_at > now())));
-- @@ view public.ottoq_active_sim_runs
CREATE VIEW public.ottoq_active_sim_runs WITH (security_invoker=on) AS
 SELECT sr.sim_run_id,
    sr.scenario_code,
    s.title AS scenario_title,
    s.category,
    sr.status,
    sr.depot_id,
    sr.sim_clock_start,
    sr.sim_clock_current,
    sr.sim_clock_end,
    round(((100.0 * EXTRACT(epoch FROM (sr.sim_clock_current - sr.sim_clock_start))) / NULLIF(EXTRACT(epoch FROM (sr.sim_clock_end - sr.sim_clock_start)), (0)::numeric)), 1) AS pct_complete,
    sr.time_scale,
    sr.tick_count,
    sr.events_generated,
    sr.vehicles_simulated,
    sr.charge_sessions,
    sr.rule_evaluations,
    sr.rule_failures,
    sr.anomalies_injected,
    sr.emergencies_triggered,
    sr.started_at,
    sr.last_tick_at,
    sr.next_tick_due_at
   FROM (public.ottoq_sim_runs sr
     JOIN public.ottoq_scenarios s ON ((s.scenario_id = sr.scenario_id)))
  WHERE (sr.status = ANY (ARRAY['running'::text, 'paused'::text, 'initializing'::text]))
  ORDER BY sr.started_at DESC;
-- @@ view public.ottoq_agent_advice_provenance
CREATE VIEW public.ottoq_agent_advice_provenance AS
 WITH base AS (
         SELECT l.call_id,
            l.sim_run_id,
            l.depot_id,
            l.chain_id,
            l.source_kind,
            l.called_at,
            l.latency_ms,
            l.outcome,
            l.tick_seq AS computed_tick,
            l.sim_clock AS computed_sim_clock,
            ((((l.detail -> 'solver_handoff'::text) -> 'receipt'::text) ->> 'tick_seq'::text))::bigint AS applied_tick,
            (((l.detail -> 'solver_handoff'::text) -> 'directive'::text) ->> 'objective'::text) AS objective,
            ((l.detail -> 'solver_handoff'::text) ->> 'status'::text) AS handoff_status,
            ((l.detail -> 'solver_handoff'::text) ->> 'fallback_reason'::text) AS fallback_reason,
            (l.detail ? 'solver_handoff'::text) AS has_handoff
           FROM public.ottoq_model_call_ledger l
          WHERE ((l.provider = 'nvidia_nemotron'::text) AND (l.role = 'agent'::text))
        )
 SELECT b.call_id,
    b.sim_run_id,
    b.depot_id,
    b.chain_id,
    b.source_kind,
    b.called_at,
    b.latency_ms,
    b.outcome,
    b.computed_tick,
    b.computed_sim_clock,
    b.applied_tick,
    (b.applied_tick - b.computed_tick) AS staleness_ticks,
    b.objective,
    b.handoff_status,
    b.fallback_reason,
        CASE
            WHEN (NOT b.has_handoff) THEN 'no_handoff'::text
            WHEN (b.handoff_status = 'skipped'::text) THEN 'skipped'::text
            WHEN (b.handoff_status = 'fallback'::text) THEN 'fell_back'::text
            WHEN (b.applied_tick IS NOT NULL) THEN 'applied'::text
            ELSE 'completed_without_applied_tick'::text
        END AS staleness_class,
    nxt.objective AS next_fresh_objective,
    nxt.computed_tick AS next_fresh_tick,
        CASE
            WHEN ((b.applied_tick IS NULL) OR (nxt.objective IS NULL)) THEN NULL::boolean
            ELSE (b.objective IS DISTINCT FROM nxt.objective)
        END AS staleness_changed_the_answer
   FROM (base b
     LEFT JOIN LATERAL ( SELECT o.objective,
            o.computed_tick
           FROM base o
          WHERE ((o.sim_run_id = b.sim_run_id) AND (o.source_kind = b.source_kind) AND (o.call_id <> b.call_id) AND (b.applied_tick IS NOT NULL) AND (o.computed_tick >= b.applied_tick))
          ORDER BY o.computed_tick, o.call_id
         LIMIT 1) nxt ON (true));
-- @@ view public.ottoq_agent_advice_staleness
CREATE VIEW public.ottoq_agent_advice_staleness AS
 WITH modal AS (
         SELECT v.source_kind,
            mode() WITHIN GROUP (ORDER BY v.objective) AS modal_objective
           FROM public.ottoq_agent_advice_provenance v
          WHERE (v.objective IS NOT NULL)
          GROUP BY v.source_kind
        )
 SELECT p.source_kind,
    count(*) AS agent_calls,
    count(*) FILTER (WHERE (p.staleness_class = 'applied'::text)) AS applied,
    count(*) FILTER (WHERE (p.staleness_class = 'completed_without_applied_tick'::text)) AS completed_without_applied_tick,
    count(*) FILTER (WHERE (p.staleness_class = 'fell_back'::text)) AS fell_back,
    count(*) FILTER (WHERE (p.staleness_class = 'skipped'::text)) AS skipped,
    count(*) FILTER (WHERE (p.staleness_class = 'no_handoff'::text)) AS no_handoff,
    (count(*) = ((((count(*) FILTER (WHERE (p.staleness_class = 'applied'::text)) + count(*) FILTER (WHERE (p.staleness_class = 'completed_without_applied_tick'::text))) + count(*) FILTER (WHERE (p.staleness_class = 'fell_back'::text))) + count(*) FILTER (WHERE (p.staleness_class = 'skipped'::text))) + count(*) FILTER (WHERE (p.staleness_class = 'no_handoff'::text)))) AS classes_sum_to_calls,
    round(avg(p.staleness_ticks), 2) AS mean_staleness_ticks,
    percentile_disc((0.5)::double precision) WITHIN GROUP (ORDER BY p.staleness_ticks) AS p50_staleness_ticks,
    percentile_disc((0.95)::double precision) WITHIN GROUP (ORDER BY p.staleness_ticks) AS p95_staleness_ticks,
    max(p.staleness_ticks) AS max_staleness_ticks,
    count(*) FILTER (WHERE (p.staleness_ticks > 1)) AS stale_over_one_tick,
    count(*) FILTER (WHERE (p.staleness_ticks > 10)) AS stale_over_ten_ticks,
    count(*) FILTER (WHERE (p.staleness_ticks < 0)) AS applied_before_computed,
    count(*) FILTER (WHERE (p.staleness_changed_the_answer IS NOT NULL)) AS comparable,
    count(*) FILTER (WHERE p.staleness_changed_the_answer) AS staleness_changed_answer,
    round(((100.0 * (count(*) FILTER (WHERE p.staleness_changed_the_answer))::numeric) / (NULLIF(count(*) FILTER (WHERE (p.staleness_changed_the_answer IS NOT NULL)), 0))::numeric), 2) AS pct_staleness_changed_answer,
    m.modal_objective,
    round(((100.0 * (count(*) FILTER (WHERE ((p.staleness_changed_the_answer IS NOT NULL) AND (p.next_fresh_objective IS DISTINCT FROM m.modal_objective))))::numeric) / (NULLIF(count(*) FILTER (WHERE (p.staleness_changed_the_answer IS NOT NULL)), 0))::numeric), 2) AS pct_modal_constant_would_be_wrong,
    count(DISTINCT p.objective) AS distinct_objectives,
    round(avg(p.latency_ms)) AS mean_latency_ms,
    percentile_disc((0.5)::double precision) WITHIN GROUP (ORDER BY p.latency_ms) AS p50_latency_ms,
    percentile_disc((0.95)::double precision) WITHIN GROUP (ORDER BY p.latency_ms) AS p95_latency_ms,
    max(p.latency_ms) AS max_latency_ms,
    count(*) FILTER (WHERE (p.latency_ms > 30000)) AS calls_over_thirty_seconds,
    max(p.called_at) AS last_call_at
   FROM (public.ottoq_agent_advice_provenance p
     LEFT JOIN modal m ON ((m.source_kind = p.source_kind)))
  GROUP BY p.source_kind, m.modal_objective;
-- @@ view public.ottoq_agent_charge_order_succession
CREATE VIEW public.ottoq_agent_charge_order_succession WITH (security_invoker=true) AS
 SELECT o.order_id,
    o.sim_run_id,
    o.board_tick,
    o.recorded_tick,
    LEAST(o.board_tick, o.recorded_tick) AS board_key,
    (b.order_id IS NULL) AS stood,
    b.order_id AS outranked_by,
        CASE
            WHEN (b.order_id IS NULL) THEN s.order_id
            ELSE NULL::bigint
        END AS superseded_by
   FROM ((public.ottoq_agent_charge_orders o
     LEFT JOIN LATERAL ( SELECT p.order_id
           FROM public.ottoq_agent_charge_orders p
          WHERE ((p.sim_run_id = o.sim_run_id) AND (p.status = ANY (ARRAY['accepted'::text, 'partial'::text])) AND (p.order_id < o.order_id) AND (LEAST(p.board_tick, p.recorded_tick) > LEAST(o.board_tick, o.recorded_tick)))
          ORDER BY LEAST(p.board_tick, p.recorded_tick) DESC, p.order_id DESC
         LIMIT 1) b ON (true))
     LEFT JOIN LATERAL ( SELECT q.order_id
           FROM public.ottoq_agent_charge_orders q
          WHERE ((q.sim_run_id = o.sim_run_id) AND (q.status = ANY (ARRAY['accepted'::text, 'partial'::text])) AND (q.order_id > o.order_id) AND (LEAST(q.board_tick, q.recorded_tick) >= LEAST(o.board_tick, o.recorded_tick)))
          ORDER BY q.order_id
         LIMIT 1) s ON (true))
  WHERE (o.status = ANY (ARRAY['accepted'::text, 'partial'::text]));
-- @@ view public.ottoq_agent_pass_scorecard
CREATE VIEW public.ottoq_agent_pass_scorecard AS
 SELECT date_trunc('day'::text, recorded_at) AS day,
    seat,
        CASE
            WHEN (run_by = 'production_live'::text) THEN 'production'::text
            ELSE 'twin'::text
        END AS run_kind,
    COALESCE(model_answered, 'none'::text) AS model_answered,
    count(*) AS passes,
    count(*) FILTER (WHERE consulted) AS consulted,
    count(*) FILTER (WHERE (outcome_class = 'changed_state'::text)) AS changed_state,
    count(*) FILTER (WHERE (outcome_class = 'echo'::text)) AS echo,
    count(*) FILTER (WHERE (outcome_class = 'advisory'::text)) AS advisory,
    count(*) FILTER (WHERE (outcome_class = 'no_effect'::text)) AS no_effect,
    count(*) FILTER (WHERE (outcome_class = 'solver_only'::text)) AS solver_only,
    count(*) FILTER (WHERE (outcome_class = 'fallback'::text)) AS fallback,
    count(*) FILTER (WHERE (outcome_class = 'failed'::text)) AS failed,
    count(*) FILTER (WHERE (outcome_class = ANY (ARRAY['changed_state'::text, 'echo'::text, 'advisory'::text, 'no_effect'::text, 'solver_only'::text, 'fallback'::text, 'failed'::text]))) AS classified,
    sum((NULLIF((usage ->> 'prompt_tokens'::text), ''::text))::bigint) AS prompt_tokens,
    sum((NULLIF((usage ->> 'completion_tokens'::text), ''::text))::bigint) AS completion_tokens,
    round(avg(propose_ms) FILTER (WHERE consulted)) AS mean_propose_ms,
    percentile_disc((0.95)::double precision) WITHIN GROUP (ORDER BY total_ms) AS p95_total_ms,
    round(avg(board_bytes)) AS mean_board_bytes,
    count(DISTINCT sim_run_id) AS runs
   FROM public.ottoq_agent_pass_evidence e
  GROUP BY (date_trunc('day'::text, recorded_at)), seat,
        CASE
            WHEN (run_by = 'production_live'::text) THEN 'production'::text
            ELSE 'twin'::text
        END, COALESCE(model_answered, 'none'::text);
-- @@ view public.ottoq_approach_band
CREATE VIEW public.ottoq_approach_band AS
 WITH r AS NOT MATERIALIZED (
         SELECT rr.sim_run_id,
            rr.depot_id,
            rr.sim_clock_current,
            GREATEST(public.ottoq_policy_get(rr.sim_run_id, 'approach_freeze_minutes'::text, (10)::numeric), (0)::numeric) AS freeze_min,
            GREATEST(public.ottoq_policy_get(rr.sim_run_id, 'approach_horizon_minutes'::text, (30)::numeric), (1)::numeric) AS horizon_min,
            GREATEST(public.ottoq_policy_get(rr.sim_run_id, 'approach_stale_heartbeat_sec'::text, (90)::numeric), (1)::numeric) AS hb_sec
           FROM public.ottoq_sim_runs rr
          WHERE (rr.depot_id IS NOT NULL)
        ), d AS (
         SELECT DISTINCT ON (dd.sim_run_id, dd.vehicle_id) dd.sim_run_id,
            dd.vehicle_id,
            dd.scheduled_return_at,
            dd.status
           FROM public.ottoq_vehicle_dispatches dd
          WHERE ((dd.status = ANY (ARRAY['active'::text, 'returning'::text])) AND (dd.actual_return_at IS NULL))
          ORDER BY dd.sim_run_id, dd.vehicle_id, dd.dispatched_at DESC NULLS LAST
        ), b AS (
         SELECT r.sim_run_id,
            r.depot_id,
            r.sim_clock_current,
            r.freeze_min,
            r.horizon_min,
            v.id AS vehicle_id,
            (v.current_state)::text AS current_state,
            (v.category)::text AS category,
            v.current_soc,
            v.inlet_type,
            v.inlet_max_kw,
            v.current_stall_id,
            d.scheduled_return_at,
                CASE
                    WHEN ((d.scheduled_return_at IS NOT NULL) AND (r.sim_clock_current IS NOT NULL)) THEN round((EXTRACT(epoch FROM (d.scheduled_return_at - r.sim_clock_current)) / 60.0), 2)
                    ELSE NULL::numeric
                END AS minutes_out,
            (EXISTS ( SELECT 1
                   FROM (public.stalls s
                     LEFT JOIN public.ottoq_ocpp_chargers c ON ((c.charger_id = s.ocpp_charger_id)))
                  WHERE (((s.reserved_by = v.id) OR (s.current_vehicle_id = v.id) OR (s.id = v.current_stall_id)) AND ((s.status = ANY (ARRAY['maintenance'::text, 'closed'::text])) OR ((s.ocpp_charger_id IS NOT NULL) AND (c.station_state = ANY (ARRAY['Faulted'::text, 'Unavailable'::text, 'Maintenance'::text]))) OR ((s.ocpp_charger_id IS NOT NULL) AND (c.charger_id IS NULL)) OR ((s.ocpp_charger_id IS NOT NULL) AND (c.charger_id IS NOT NULL) AND (c.last_fault_code IS NOT NULL) AND (r.sim_clock_current IS NOT NULL) AND (c.last_heartbeat_at < (r.sim_clock_current - ((r.hb_sec || ' seconds'::text))::interval))))))) AS c_hardware,
            (((v.current_state)::text = ANY (ARRAY['tow_requested'::text, 'out_of_service'::text, 'emergency_staged'::text])) OR (EXISTS ( SELECT 1
                   FROM public.ottoq_ops_approvals a
                  WHERE ((a.vehicle_id = v.id) AND (a.sim_run_id = r.sim_run_id) AND (a.status = 'pending'::text) AND (a.approval_type = ANY (ARRAY['indepot_reassign'::text, 'tech_greenlight'::text])))))) AS c_flag
           FROM ((r
             JOIN public.vehicles v ON ((v.home_depot_id = r.depot_id)))
             LEFT JOIN d ON (((d.sim_run_id = r.sim_run_id) AND (d.vehicle_id = v.id))))
        )
 SELECT sim_run_id,
    depot_id,
    vehicle_id,
    current_state,
    category,
    current_soc,
    inlet_type,
    inlet_max_kw,
    scheduled_return_at,
    sim_clock_current,
    minutes_out,
    freeze_min,
    horizon_min,
        CASE
            WHEN ((current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) AND (minutes_out IS NOT NULL) AND (minutes_out > freeze_min)) THEN 'A'::text
            WHEN (c_hardware OR c_flag) THEN 'C'::text
            ELSE 'B'::text
        END AS zone,
        CASE
            WHEN ((current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) AND (minutes_out IS NOT NULL) AND (minutes_out > freeze_min)) THEN
            CASE
                WHEN (minutes_out <= horizon_min) THEN 'open:in_cuopt_window'::text
                ELSE 'open:beyond_cuopt_horizon'::text
            END
            WHEN c_hardware THEN 'reopened:hardware_malfunction'::text
            WHEN c_flag THEN 'reopened:flag'::text
            WHEN ((current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) AND (minutes_out IS NOT NULL)) THEN 'frozen:approached'::text
            WHEN (current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) THEN 'frozen:fail_closed_no_eta'::text
            WHEN (current_state = ANY (ARRAY['arrived_at_gate'::text, 'staged_awaiting_service'::text, 'charging_dcfc'::text, 'charging_l2'::text, 'charge_complete_holding'::text, 'in_wash_bay'::text, 'in_detail_bay'::text, 'in_service_bay'::text, 'service_complete_holding'::text, 'staged_for_departure'::text, 'emergency_staged'::text, 'tow_requested'::text])) THEN 'frozen:entered'::text
            ELSE 'frozen:not_inbound'::text
        END AS zone_reason,
    ((current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) AND ((minutes_out IS NULL) OR (minutes_out <= freeze_min))) AS approached,
    (current_state = ANY (ARRAY['arrived_at_gate'::text, 'staged_awaiting_service'::text, 'charging_dcfc'::text, 'charging_l2'::text, 'charge_complete_holding'::text, 'in_wash_bay'::text, 'in_detail_bay'::text, 'in_service_bay'::text, 'service_complete_holding'::text, 'staged_for_departure'::text, 'emergency_staged'::text, 'tow_requested'::text])) AS entered,
    ((current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) AND (minutes_out IS NOT NULL) AND (minutes_out > freeze_min) AND (minutes_out <= horizon_min)) AS in_cuopt_window,
    c_hardware AS zone_c_hardware,
    c_flag AS zone_c_flag
   FROM b;
-- @@ view public.ottoq_booking_why_v1
CREATE VIEW public.ottoq_booking_why_v1 AS
 SELECT b.booking_id,
    b.sim_run_id,
    b.vehicle_id,
    b.stall_id,
    s.stall_code,
    (s.stall_type)::text AS stall_type,
    b.purpose,
    lower(b.during) AS starts_at,
    upper(b.during) AS ends_at,
    b.state,
    b.booked_by,
    b.source,
    b.leg_id,
    b.leg_source,
    l.leg_type,
    l.status AS leg_status,
    l.seq AS leg_seq,
    (l.duration_basis ->> 'atom'::text) AS leg_atom,
    l.planned_start_sim,
    l.planned_end_sim,
    l.actual_start_sim,
    b.visit_id,
    vn.archetype,
    vn.urgency,
    vn.target_soc,
    b.need_code,
    b.need_atom,
    b.need_source,
    COALESCE(b.why, format('%s %s %s-%s (legacy row: no recorded why)'::text, COALESCE(s.stall_code, 'stall'::text), b.purpose, to_char(lower(b.during), 'HH24:MI'::text), to_char(upper(b.during), 'HH24:MI'::text))) AS why,
    (b.leg_id IS NOT NULL) AS has_leg,
    ((b.need_code IS NOT NULL) OR (b.leg_id IS NOT NULL)) AS answers_why
   FROM (((public.ottoq_stall_bookings b
     LEFT JOIN public.stalls s ON ((s.id = b.stall_id)))
     LEFT JOIN public.ottoq_itinerary_legs l ON ((l.leg_id = b.leg_id)))
     LEFT JOIN public.ottoq_visit_needs vn ON ((vn.visit_id = b.visit_id)));
-- @@ view public.ottoq_calibration_status
CREATE VIEW public.ottoq_calibration_status WITH (security_invoker=on) AS
 SELECT d.domain,
    d.dataset_code,
    d.source_name,
    d.status,
    d.record_count,
    d.date_range_start,
    d.date_range_end,
    d.ingested_at,
    count(dist.distribution_id) AS distributions,
    count(DISTINCT dist.variable_name) AS variables,
    count(DISTINCT p.profile_id) AS profiles
   FROM ((public.ottoq_calibration_datasets d
     LEFT JOIN public.ottoq_calibration_distributions dist ON ((dist.dataset_code = d.dataset_code)))
     LEFT JOIN public.ottoq_calibration_profiles p ON ((p.dataset_code = d.dataset_code)))
  GROUP BY d.domain, d.dataset_code, d.source_name, d.status, d.record_count, d.date_range_start, d.date_range_end, d.ingested_at
  ORDER BY d.domain, d.dataset_code;
-- @@ view public.ottoq_channel_health_now
CREATE VIEW public.ottoq_channel_health_now WITH (security_invoker=true) AS
 SELECT DISTINCT ON (channel) channel,
    status,
    reason,
    observed,
    sim_run_id,
    checked_at,
    ( SELECT min(h2.checked_at) AS min
           FROM public.ottoq_channel_health h2
          WHERE ((h2.channel = h.channel) AND (h2.health_id > COALESCE(( SELECT max(h3.health_id) AS max
                   FROM public.ottoq_channel_health h3
                  WHERE ((h3.channel = h.channel) AND (h3.status <> h.status))), (0)::bigint)))) AS status_since
   FROM public.ottoq_channel_health h
  ORDER BY channel, health_id DESC;
-- @@ view public.ottoq_charge_order_attributions
CREATE VIEW public.ottoq_charge_order_attributions WITH (security_invoker=true) AS
 SELECT a.order_id,
    a.sim_run_id,
    a.depot_id,
    a.parts,
    a.subset_values,
    a.shapley,
    a.verdict_changed,
    a.code_md5,
    a.computed_at
   FROM public.ottoq_charge_order_attribution a
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.ottoq_charge_order_reattributions r
          WHERE (r.order_id = a.order_id))))
UNION ALL
 SELECT r.order_id,
    r.sim_run_id,
    r.depot_id,
    r.parts,
    r.subset_values,
    r.shapley,
    r.verdict_changed,
    r.code_md5,
    r.computed_at
   FROM public.ottoq_charge_order_reattributions r
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.ottoq_charge_order_reattributions n
          WHERE ((n.order_id = r.order_id) AND (ROW(n.reattributed_at, n.code_md5) > ROW(r.reattributed_at, r.code_md5))))));
-- @@ view public.ottoq_charge_order_grades
CREATE VIEW public.ottoq_charge_order_grades WITH (security_invoker=true) AS
 SELECT h.order_id,
    h.sim_run_id,
    h.depot_id,
    h.sim_clock,
    h.window_min,
    h.observed_min,
    h.status,
    h.reason,
    h.taken,
    h.decision,
    h.futures,
    h.wins,
    h.need,
    h.p_win,
    h.expected,
    h.hindsight,
    h.outcome,
    h.moves,
    h.forecast,
    h.fidelity,
    h.realized,
    h.code_md5,
    h.graded_at
   FROM public.ottoq_charge_order_hindsight h
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.ottoq_charge_order_regrades r
          WHERE (r.order_id = h.order_id))))
UNION ALL
 SELECT r.order_id,
    r.sim_run_id,
    r.depot_id,
    r.sim_clock,
    r.window_min,
    r.observed_min,
    r.status,
    r.reason,
    r.taken,
    r.decision,
    r.futures,
    r.wins,
    r.need,
    r.p_win,
    r.expected,
    r.hindsight,
    r.outcome,
    r.moves,
    r.forecast,
    r.fidelity,
    r.realized,
    r.code_md5,
    r.graded_at
   FROM public.ottoq_charge_order_regrades r
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.ottoq_charge_order_regrades n
          WHERE ((n.order_id = r.order_id) AND (ROW(n.regraded_at, n.code_md5) > ROW(r.regraded_at, r.code_md5))))));
-- @@ view public.ottoq_command_handshake
CREATE VIEW public.ottoq_command_handshake AS
 SELECT c.data_source,
    count(*) AS issued_total,
    count(*) FILTER (WHERE (c.delivered_at IS NOT NULL)) AS delivered,
    count(*) FILTER (WHERE (c.confirmed_by IS NOT NULL)) AS acked,
    count(*) FILTER (WHERE ((c.confirmed_by IS NOT NULL) AND (COALESCE(r.kind,
        CASE
            WHEN (c.confirmed_by ~~ 'operator:%'::text) THEN 'external'::text
            ELSE 'self'::text
        END) = 'self'::text))) AS acked_by_us,
    count(*) FILTER (WHERE (COALESCE(r.kind,
        CASE
            WHEN (c.confirmed_by ~~ 'operator:%'::text) THEN 'external'::text
            ELSE 'self'::text
        END) = 'operator'::text)) AS acked_by_operator,
    count(*) FILTER (WHERE (COALESCE(r.kind,
        CASE
            WHEN (c.confirmed_by ~~ 'operator:%'::text) THEN 'external'::text
            ELSE 'self'::text
        END) = 'external'::text)) AS acked_by_asset,
    min(c.issued_at) AS first_issued,
    max(c.issued_at) AS last_issued
   FROM (public.ottoq_vehicle_commands c
     LEFT JOIN public.ottoq_command_actor_registry r ON ((r.actor = c.confirmed_by)))
  GROUP BY c.data_source;
-- @@ view public.ottoq_counterfactual_summary_30d
CREATE VIEW public.ottoq_counterfactual_summary_30d WITH (security_invoker=on) AS
 SELECT scenario_label,
    source_kind,
    count(*) AS runs,
    count(*) FILTER (WHERE (delta_direction = 'better'::text)) AS better_count,
    count(*) FILTER (WHERE (delta_direction = 'worse'::text)) AS worse_count,
    count(*) FILTER (WHERE (delta_direction = 'neutral'::text)) AS neutral_count,
    avg(delta) AS avg_delta,
    percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((delta)::double precision)) AS median_delta,
    min(delta) AS min_delta,
    max(delta) AS max_delta
   FROM public.ottoq_counterfactuals
  WHERE ((ran_at > (now() - '30 days'::interval)) AND (delta IS NOT NULL))
  GROUP BY scenario_label, source_kind;
-- @@ view public.ottoq_cross_depot_ranking_30d
CREATE VIEW public.ottoq_cross_depot_ranking_30d WITH (security_invoker=on) AS
 SELECT d.id AS depot_id,
    d.name AS depot_name,
    sum(b.visits_completed) AS visits,
    round(avg(b.avg_sla_compliance_pct), 2) AS avg_sla_pct,
    sum(b.rule_failures_count) AS rule_failures,
    sum(b.anomalies_count) AS anomalies,
    sum(b.emergencies_count) AS emergencies,
    sum(b.overrides_count) AS overrides,
    round(sum(b.total_kwh_delivered), 1) AS kwh,
    round(sum(b.total_revenue_usd), 2) AS revenue,
    round(sum(b.total_cost_usd), 2) AS cost,
    round(avg(b.margin_pct), 2) AS avg_margin_pct,
    round(sum(b.total_carbon_offset_kg), 1) AS carbon_offset_kg,
    dense_rank() OVER (ORDER BY (avg(b.avg_sla_compliance_pct)) DESC NULLS LAST) AS sla_rank,
    dense_rank() OVER (ORDER BY (avg(b.margin_pct)) DESC NULLS LAST) AS margin_rank,
    dense_rank() OVER (ORDER BY (sum(b.emergencies_count))) AS safety_rank
   FROM (public.depots d
     LEFT JOIN public.ottoq_depot_benchmarks_daily b ON (((b.depot_id = d.id) AND (b.report_date >= (CURRENT_DATE - 30)))))
  GROUP BY d.id, d.name;
-- @@ view public.ottoq_depot_economics_summary
CREATE VIEW public.ottoq_depot_economics_summary WITH (security_invoker=on) AS
 SELECT depot_id,
    date_trunc('month'::text, (report_date)::timestamp with time zone) AS month_start,
    sum(visits_completed) AS visits,
    sum(total_kwh_delivered) AS kwh_delivered,
    sum(total_operating_cost_usd) AS operating_cost,
    sum(total_revenue_usd) AS revenue,
    sum(total_margin_usd) AS margin,
    round(((sum(total_margin_usd) / NULLIF(sum(total_revenue_usd), (0)::numeric)) * (100)::numeric), 2) AS margin_pct,
    sum(total_carbon_offset_kg) AS carbon_offset_kg,
    avg(solar_self_consumption_pct) AS avg_solar_self_consumption_pct
   FROM public.ottoq_depot_cost_daily
  GROUP BY depot_id, (date_trunc('month'::text, (report_date)::timestamp with time zone));
-- @@ view public.ottoq_determinism_canon
CREATE VIEW public.ottoq_determinism_canon AS
 SELECT c.depot_id,
    c.scenario,
    c.seed,
    c.ticks,
    c.enabled,
    c.max_age,
    c.note AS column_note,
    l.verdict_id,
    l.certified_at,
    l.outcome,
    l.equal,
    l.complete,
    l.disagreeing_atoms,
    l.null_atoms,
    l.engine_hash,
    public.ottoq_cert_recert_floor() AS recert_floor,
    ((l.certified_at IS NOT NULL) AND (l.certified_at >= public.ottoq_cert_recert_floor()) AND (l.outcome = 'passed'::text)) AS satisfies_floor,
        CASE
            WHEN (l.certified_at IS NULL) THEN 'NEVER CERTIFIED DURABLY'::text
            WHEN (l.certified_at < public.ottoq_cert_recert_floor()) THEN 'stale: predates the recert floor'::text
            WHEN (l.outcome <> 'passed'::text) THEN ('fresh but '::text || l.outcome)
            ELSE 'current'::text
        END AS status
   FROM (public.ottoq_cert_columns c
     LEFT JOIN LATERAL ( SELECT v.verdict_id,
            v.certified_at,
            v.depot_id,
            v.scenario,
            v.seed,
            v.ticks,
            v.outcome,
            v.equal,
            v.complete,
            v.arm_a_run,
            v.arm_b_run,
            v.atoms_compared,
            v.disagreeing_atoms,
            v.null_atoms,
            v.engine_hash,
            v.verdict
           FROM public.ottoq_determinism_verdict_ledger v
          WHERE ((v.depot_id = c.depot_id) AND (v.scenario = c.scenario) AND (v.seed = c.seed) AND (v.ticks = c.ticks))
          ORDER BY v.certified_at DESC
         LIMIT 1) l ON (true))
  ORDER BY c.depot_id, c.ticks, c.scenario, c.seed;
-- @@ view public.ottoq_determinism_verdict_clock
CREATE VIEW public.ottoq_determinism_verdict_clock AS
 SELECT l.verdict_id,
    l.certified_at,
    l.scenario,
    l.seed,
    l.ticks AS tick_count,
    l.outcome,
    l.equal,
    l.engine_hash,
    round(((EXTRACT(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / (NULLIF(r.tick_count, 0))::numeric) / 60.0), 2) AS sim_min_per_tick,
    r.tick_interval_seconds AS wall_seconds_per_tick,
    (r.sim_run_id IS NOT NULL) AS clock_recoverable,
    r.run_by AS arm_a_run_by
   FROM (public.ottoq_determinism_verdict_ledger l
     LEFT JOIN public.ottoq_sim_runs r ON ((r.sim_run_id = l.arm_a_run)));
-- @@ view public.ottoq_dial_outcome_reanalysis
CREATE VIEW public.ottoq_dial_outcome_reanalysis AS
 SELECT d.engine_hash,
    d.scenario,
    d.sim_min_per_tick,
    k.dial,
    k.value,
    count(*) AS runs,
    count(DISTINCT d.random_seed) AS seeds,
    round(avg(((d.metrics ->> 'tasks_completed'::text))::numeric), 2) AS avg_tasks_completed,
    round(avg(((d.metrics ->> 'charge_sessions'::text))::numeric), 2) AS avg_charge_sessions,
    round(avg(((d.metrics ->> 'commands_refused'::text))::numeric), 2) AS avg_commands_refused,
    round(avg(d.rule_evaluations), 1) AS avg_rule_evaluations,
    round(avg(d.rules_blocked), 1) AS avg_rules_blocked,
    (count(DISTINCT d.random_seed) >= 2) AS has_replication,
    (min(COALESCE(d.rule_evaluations, (0)::bigint)) > 0) AS every_run_paid_the_shield
   FROM (public.ottoq_run_dial_ledger d
     CROSS JOIN LATERAL jsonb_each_text(d.dials) k(dial, value))
  WHERE (d.metrics IS NOT NULL)
  GROUP BY d.engine_hash, d.scenario, d.sim_min_per_tick, k.dial, k.value;
-- @@ view public.ottoq_event_stream
CREATE VIEW public.ottoq_event_stream AS
 SELECT event_id,
    event_seq,
    occurred_at,
    recorded_at,
    actor_type,
    actor_id,
    event_type,
    event_category,
    severity,
    entity_type,
    entity_id,
    fleet_operator_id,
    depot_id,
    payload,
    previous_state,
    new_state,
    correlation_id,
    parent_event_id,
    causation_chain,
    related_task_id,
    related_schedule_id,
    related_decision_id,
    outcome,
    latency_ms,
    ingest_source,
    signature_key_id,
    (signature IS NOT NULL) AS is_signed
   FROM public.ottoq_events
  ORDER BY event_seq DESC;
-- @@ view public.ottoq_evidence_join_loss_now
CREATE VIEW public.ottoq_evidence_join_loss_now AS
 SELECT table_name,
    rows_total,
    rows_with_run,
    rows_orphaned,
    join_loss_pct,
    rows_recoverable_via_archive,
    rows_unattributable,
    has_fk_to_sim_runs
   FROM public.ottoq_evidence_join_loss() ottoq_evidence_join_loss(table_name, rows_total, rows_with_run, rows_orphaned, join_loss_pct, rows_recoverable_via_archive, rows_unattributable, has_fk_to_sim_runs);
-- @@ view public.ottoq_features_live
CREATE VIEW public.ottoq_features_live WITH (security_invoker=on) AS
 SELECT fv.feature_name,
    fv.entity_type,
    fv.entity_id,
    COALESCE(to_jsonb(fv.value_numeric), to_jsonb(fv.value_integer), to_jsonb(fv.value_boolean), to_jsonb(fv.value_text), to_jsonb(fv.value_timestamp), fv.value_json) AS value,
    fv.valid_from,
    fv.observation_time,
    (EXTRACT(epoch FROM (now() - fv.observation_time)))::integer AS age_seconds,
    fv.quality_score,
    fv.is_imputed,
    fv.is_outlier,
    fv.fleet_operator_id,
    fv.depot_id,
    fv.feature_version,
    f.freshness_sla_seconds,
    (EXTRACT(epoch FROM (now() - fv.observation_time)) <= (f.freshness_sla_seconds)::numeric) AS is_fresh
   FROM (public.ottoq_feature_values fv
     LEFT JOIN public.ottoq_features f ON ((f.feature_name = fv.feature_name)))
  WHERE (fv.valid_until IS NULL);
-- @@ view public.ottoq_first_refusal_outcomes
CREATE VIEW public.ottoq_first_refusal_outcomes AS
 SELECT d.sim_run_id,
    r.run_by,
    r.started_at AS run_started_at,
    d.vehicle_id,
    d.state,
    d.armed_at_tick,
    d.spent_at_tick,
    d.cleared_at_tick,
    d.defer_count,
    a.source AS answer_source,
    a.status AS answer_status,
    a.tick_seq AS answer_tick,
    (a.source IS NOT NULL) AS answered,
        CASE
            WHEN (d.spent_at_tick IS NULL) THEN 'never_bound'::text
            WHEN (a.source IS NULL) THEN 'unanswered'::text
            WHEN (a.status = 'enacted'::text) THEN 'answered_enacted'::text
            ELSE 'answered_not_enacted'::text
        END AS outcome
   FROM ((public.ottoq_cuopt_deferrals d
     LEFT JOIN public.ottoq_sim_runs r ON ((r.sim_run_id = d.sim_run_id)))
     LEFT JOIN LATERAL ( SELECT p.source,
            p.status,
            p.tick_seq
           FROM (public.ottoq_external_proposals p
             JOIN public.ottoq_proposer_precedence pp ON (((pp.source = p.source) AND pp.holds_tick)))
          WHERE ((p.sim_run_id = d.sim_run_id) AND (p.entity_id = d.vehicle_id) AND (p.entity_type = 'vehicle'::text) AND (p.action_context = 'stall_assignment'::text) AND (d.spent_at_tick IS NOT NULL) AND (p.tick_seq <= d.spent_at_tick))
          ORDER BY pp.rank, p.tick_seq DESC
         LIMIT 1) a ON (true));
-- @@ view public.ottoq_first_refusal_summary
CREATE VIEW public.ottoq_first_refusal_summary AS
 SELECT sim_run_id,
    run_by,
    run_started_at,
    count(*) AS holds,
    count(*) FILTER (WHERE (outcome = 'answered_enacted'::text)) AS answered_enacted,
    count(*) FILTER (WHERE (outcome = 'answered_not_enacted'::text)) AS answered_not_enacted,
    count(*) FILTER (WHERE (outcome = 'unanswered'::text)) AS unanswered,
    count(*) FILTER (WHERE (outcome = 'never_bound'::text)) AS never_bound,
    min(armed_at_tick) AS first_armed_tick,
    max(armed_at_tick) AS last_armed_tick,
    round(((100.0 * (count(*) FILTER (WHERE answered))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS answered_pct
   FROM public.ottoq_first_refusal_outcomes
  GROUP BY sim_run_id, run_by, run_started_at;
-- @@ view public.ottoq_indepot_gate_latency
CREATE VIEW public.ottoq_indepot_gate_latency AS
 SELECT approval_id,
    sim_run_id,
    depot_id,
    vehicle_id,
    status,
    decided_by,
    (payload ->> 'gate_mode'::text) AS gate_mode,
    ((payload -> 'decision'::text) ->> 'verdict'::text) AS verdict,
    ((payload -> 'decision'::text) ->> 'reason'::text) AS verdict_reason,
    COALESCE((((payload -> 'decision'::text) ->> 'fast_path'::text))::boolean, false) AS fast_path,
    (payload ? 'decision'::text) AS has_audit_object,
        CASE
            WHEN (((payload ->> 'requested_at_sim'::text) IS NOT NULL) AND (((payload -> 'decision'::text) ->> 'decided_at_sim'::text) IS NOT NULL)) THEN 'sim'::text
            WHEN (((payload ->> 'requested_at_sim'::text) IS NULL) AND (decided_at IS NOT NULL) AND (requested_at IS NOT NULL)) THEN 'real'::text
            ELSE 'unmeasurable'::text
        END AS clock_domain,
        CASE
            WHEN (((payload ->> 'requested_at_sim'::text) IS NOT NULL) AND (((payload -> 'decision'::text) ->> 'decided_at_sim'::text) IS NOT NULL)) THEN round((EXTRACT(epoch FROM ((((payload -> 'decision'::text) ->> 'decided_at_sim'::text))::timestamp with time zone - ((payload ->> 'requested_at_sim'::text))::timestamp with time zone)) / 60.0), 2)
            WHEN (((payload ->> 'requested_at_sim'::text) IS NULL) AND (decided_at IS NOT NULL) AND (requested_at IS NOT NULL)) THEN round((EXTRACT(epoch FROM (decided_at - requested_at)) / 60.0), 2)
            ELSE NULL::numeric
        END AS latency_min,
    requested_at,
    decided_at,
    ((payload ->> 'requested_at_sim'::text))::timestamp with time zone AS requested_at_sim,
    (((payload -> 'decision'::text) ->> 'decided_at_sim'::text))::timestamp with time zone AS decided_at_sim
   FROM public.ottoq_ops_approvals ap
  WHERE (approval_type = 'indepot_reassign'::text);
-- @@ view public.ottoq_inference_failures
CREATE VIEW public.ottoq_inference_failures WITH (security_invoker=on) AS
 SELECT inference_id,
    requested_at,
    prediction_type,
    model_version_id,
    fleet_operator_id,
    depot_id,
    vehicle_id,
    status,
    error_code,
    error_message,
    correlation_id,
    latency_ms
   FROM public.ottoq_inference_log
  WHERE ((status = ANY (ARRAY['failed'::text, 'timed_out'::text])) AND (requested_at > (now() - '24:00:00'::interval)))
  ORDER BY requested_at DESC;
-- @@ view public.ottoq_inference_latency_summary
CREATE VIEW public.ottoq_inference_latency_summary WITH (security_invoker=on) AS
 SELECT prediction_type,
    model_version_id,
    count(*) AS calls_last_hour,
    count(*) FILTER (WHERE (status = 'completed'::text)) AS succeeded,
    count(*) FILTER (WHERE (status = ANY (ARRAY['failed'::text, 'timed_out'::text]))) AS failed,
    (round(avg(latency_ms)))::integer AS avg_latency_ms,
    (percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((latency_ms)::double precision)))::integer AS p50_ms,
    (percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((latency_ms)::double precision)))::integer AS p95_ms,
    (percentile_cont((0.99)::double precision) WITHIN GROUP (ORDER BY ((latency_ms)::double precision)))::integer AS p99_ms,
    max(latency_ms) AS max_ms,
    round(avg(cost_estimate_cents), 4) AS avg_cost_cents
   FROM public.ottoq_inference_log
  WHERE (requested_at > (now() - '01:00:00'::interval))
  GROUP BY prediction_type, model_version_id;
-- @@ view public.ottoq_intelligence_ledger
CREATE VIEW public.ottoq_intelligence_ledger AS
 SELECT provider,
    role,
    count(*) FILTER (WHERE (endpoint IS NOT NULL)) AS calls,
    count(*) FILTER (WHERE ((http_status >= 200) AND (http_status <= 299))) AS provider_status_2xx,
    count(*) FILTER (WHERE ((http_status IS NOT NULL) AND ((http_status < 200) OR (http_status > 299)))) AS provider_status_other,
    count(*) FILTER (WHERE (http_status IS NULL)) AS provider_status_unknown,
    count(*) FILTER (WHERE (public.ottoq_model_call_outcome_class(outcome) = 'answered'::text)) AS answered,
    count(*) FILTER (WHERE (public.ottoq_model_call_outcome_class(outcome) = 'abstained'::text)) AS abstained,
    count(*) FILTER (WHERE (public.ottoq_model_call_outcome_class(outcome) = 'fallback'::text)) AS fell_back,
    count(*) FILTER (WHERE (public.ottoq_model_call_outcome_class(outcome) = 'refused'::text)) AS refused,
    count(*) FILTER (WHERE (public.ottoq_model_call_outcome_class(outcome) = 'error'::text)) AS errored,
    count(*) FILTER (WHERE (public.ottoq_model_call_outcome_class(outcome) = 'unclassified'::text)) AS unclassified,
    jsonb_object_agg(outcome, n ORDER BY outcome) AS outcomes,
    COALESCE(sum(proposals_out), (0)::bigint) AS proposals,
    count(*) FILTER (WHERE ((COALESCE(((detail ->> 'l1_rules_evaluated'::text))::integer, 0) = 0) AND (role = 'agent'::text))) AS agent_calls_with_no_l1_rules,
    round(avg(latency_ms) FILTER (WHERE (endpoint IS NOT NULL))) AS avg_latency_ms,
    max(latency_ms) FILTER (WHERE (endpoint IS NOT NULL)) AS max_latency_ms,
    count(*) FILTER (WHERE ((endpoint IS NOT NULL) AND (latency_ms > 30000))) AS calls_over_one_tick,
    min(called_at) AS first_call,
    max(called_at) AS last_call,
    count(*) FILTER (WHERE (source_kind = 'backfill'::text)) AS reconstructed,
    count(*) AS ledger_rows,
    count(*) FILTER (WHERE (endpoint IS NULL)) AS captured_decisions,
    count(*) FILTER (WHERE ((outcome = 'solved_but_zero_proposals'::text) AND (COALESCE(((detail ->> 'rows'::text))::integer, '-1'::integer) = 0))) AS no_candidate_calls,
    count(*) FILTER (WHERE ((outcome = 'solved_but_zero_proposals'::text) AND (COALESCE(((detail ->> 'rows'::text))::integer, '-1'::integer) > 0))) AS declined_all_calls,
    round(avg(latency_ms) FILTER (WHERE (endpoint IS NULL))) AS avg_decision_latency_ms,
    max(latency_ms) FILTER (WHERE (endpoint IS NULL)) AS max_decision_latency_ms,
    count(*) FILTER (WHERE ((endpoint IS NULL) AND (latency_ms > 30000))) AS decisions_over_one_tick
   FROM ( SELECT l.call_id,
            l.sim_run_id,
            l.depot_id,
            l.tick_seq,
            l.sim_clock,
            l.chain_id,
            l.provider,
            l.role,
            l.model,
            l.endpoint,
            l.http_status,
            l.latency_ms,
            l.outcome,
            l.proposals_out,
            l.rationale_present,
            l.detail,
            l.called_at,
            l.source_kind,
            count(*) OVER (PARTITION BY l.provider, l.role, l.outcome) AS n
           FROM public.ottoq_model_call_ledger l) z
  GROUP BY provider, role;
-- @@ view public.ottoq_kpi_asset_hours_available_per_day
CREATE VIEW public.ottoq_kpi_asset_hours_available_per_day AS
 WITH d AS (
         SELECT v.sim_run_id,
            v.vehicle_id,
            v.dispatched_at,
            COALESCE(v.actual_return_at, v.scheduled_return_at) AS claimed_end,
            (v.actual_return_at IS NULL) AS open_at_horizon,
            r.sim_clock_start AS win_from,
            COALESCE(r.sim_clock_current, now()) AS win_to,
            (r.sim_clock_current IS NOT NULL) AS horizon_from_run
           FROM (public.ottoq_vehicle_dispatches v
             LEFT JOIN public.ottoq_sim_runs r ON ((r.sim_run_id = v.sim_run_id)))
        ), c AS (
         SELECT d.sim_run_id,
            d.vehicle_id,
            d.dispatched_at,
            d.claimed_end,
            d.open_at_horizon,
            d.win_from,
            d.win_to,
            d.horizon_from_run,
            GREATEST(d.dispatched_at, COALESCE(d.win_from, d.dispatched_at)) AS credit_from,
            LEAST(COALESCE(d.claimed_end, d.win_to), d.win_to) AS credit_to
           FROM d
        ), sliced AS (
         SELECT c.sim_run_id,
            c.vehicle_id,
            c.dispatched_at,
            c.claimed_end,
            c.win_to,
            c.horizon_from_run,
            c.open_at_horizon,
            c.credit_from,
            c.credit_to,
            (gs.gs)::date AS day,
            GREATEST(EXTRACT(epoch FROM (LEAST(c.credit_to, (gs.gs + '1 day'::interval)) - GREATEST(c.credit_from, gs.gs))), (0)::numeric) AS slice_secs,
            (gs.gs = date_trunc('day'::text, c.credit_from)) AS is_first_slice
           FROM c,
            LATERAL generate_series(date_trunc('day'::text, c.credit_from), date_trunc('day'::text, GREATEST(c.credit_to, c.credit_from)), '1 day'::interval) gs(gs)
        )
 SELECT sim_run_id,
    day,
    round((sum(slice_secs) / 3600.0), 2) AS asset_hours_available,
    count(DISTINCT vehicle_id) AS assets_counted,
    min(win_to) AS horizon,
        CASE
            WHEN bool_and(horizon_from_run) THEN 'run_horizon'::text
            ELSE 'wall_clock'::text
        END AS horizon_source,
    round((sum(
        CASE
            WHEN is_first_slice THEN (EXTRACT(epoch FROM (COALESCE(claimed_end, win_to) - dispatched_at)) - GREATEST(EXTRACT(epoch FROM (credit_to - credit_from)), (0)::numeric))
            ELSE (0)::numeric
        END) / 3600.0), 2) AS hours_clipped_to_window,
    count(*) FILTER (WHERE (open_at_horizon AND is_first_slice)) AS dispatches_open_at_horizon,
    count(*) FILTER (WHERE is_first_slice) AS dispatches_counted
   FROM sliced
  GROUP BY sim_run_id, day;
-- @@ view public.ottoq_kpi_p95_time_to_service
CREATE VIEW public.ottoq_kpi_p95_time_to_service AS
 WITH tot AS (
         SELECT d.sim_run_id,
            count(*) AS dispatches_total,
            count(*) FILTER (WHERE (d.actual_return_at IS NULL)) AS dispatches_never_returned,
            count(*) FILTER (WHERE (d.actual_return_at > r.sim_clock_current)) AS dispatches_returned_past_horizon,
            count(*) FILTER (WHERE ((d.actual_return_at IS NOT NULL) AND (d.actual_return_at <= r.sim_clock_current))) AS dispatches_admitted
           FROM (public.ottoq_vehicle_dispatches d
             JOIN public.ottoq_sim_runs r ON ((r.sim_run_id = d.sim_run_id)))
          GROUP BY d.sim_run_id
        ), pairs AS (
         SELECT d.dispatch_id,
            d.sim_run_id,
            d.actual_return_at,
            r.sim_clock_current AS run_reached,
            min(l.actual_start_sim) FILTER (WHERE (l.actual_start_sim >= d.actual_return_at)) AS first_op_active_at,
            min(l.planned_start_sim) FILTER (WHERE (l.planned_start_sim >= d.actual_return_at)) AS first_work_planned_at
           FROM ((public.ottoq_vehicle_dispatches d
             JOIN public.ottoq_sim_runs r ON ((r.sim_run_id = d.sim_run_id)))
             LEFT JOIN public.ottoq_itinerary_legs l ON (((l.sim_run_id = d.sim_run_id) AND (l.vehicle_id = d.vehicle_id) AND (l.leg_type <> ALL (ARRAY['taxi'::text, 'stage'::text])))))
          WHERE ((d.actual_return_at IS NOT NULL) AND (d.actual_return_at <= r.sim_clock_current))
          GROUP BY d.dispatch_id, d.sim_run_id, d.actual_return_at, r.sim_clock_current
        ), agg AS (
         SELECT pairs.sim_run_id,
            round((percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY (((EXTRACT(epoch FROM (pairs.first_op_active_at - pairs.actual_return_at)) / 60.0))::double precision)))::numeric, 1) AS p95,
            count(*) FILTER (WHERE (pairs.first_op_active_at IS NOT NULL)) AS measured,
            count(*) FILTER (WHERE ((pairs.first_op_active_at IS NULL) AND (pairs.first_work_planned_at IS NOT NULL) AND (pairs.first_work_planned_at < pairs.run_reached))) AS unserved,
            round((percentile_cont((0.50)::double precision) WITHIN GROUP (ORDER BY (((EXTRACT(epoch FROM (pairs.first_op_active_at - pairs.actual_return_at)) / 60.0))::double precision)))::numeric, 1) AS p50,
            round(max((EXTRACT(epoch FROM (pairs.first_op_active_at - pairs.actual_return_at)) / 60.0)), 1) AS max_min,
            count(*) FILTER (WHERE ((pairs.first_op_active_at IS NULL) AND ((pairs.first_work_planned_at IS NULL) OR (pairs.first_work_planned_at >= pairs.run_reached)))) AS deferred
           FROM pairs
          GROUP BY pairs.sim_run_id
        )
 SELECT t.sim_run_id,
    a.p95 AS p95_time_to_service_min,
    COALESCE(a.measured, (0)::bigint) AS returns_measured,
    COALESCE(a.unserved, (0)::bigint) AS returns_unserved,
    a.p50 AS p50_time_to_service_min,
    a.max_min AS max_time_to_service_min,
    COALESCE(a.deferred, (0)::bigint) AS returns_deferred_beyond_horizon,
    t.dispatches_total,
    t.dispatches_admitted,
    t.dispatches_never_returned,
    t.dispatches_returned_past_horizon
   FROM (tot t
     LEFT JOIN agg a USING (sim_run_id));
-- @@ view public.ottoq_kpi_peak_site_kw
CREATE VIEW public.ottoq_kpi_peak_site_kw WITH (security_invoker=true) AS
 WITH rolling AS (
         SELECT s.sim_run_id,
            s."timestamp",
            avg(s.grid_import_kw) OVER (PARTITION BY s.sim_run_id, s.depot_id ORDER BY s."timestamp" RANGE BETWEEN '00:15:00'::interval PRECEDING AND CURRENT ROW) AS kw_15min
           FROM public.site_energy_snapshots s
        )
 SELECT sim_run_id,
    round(max(kw_15min), 1) AS peak_site_kw_15min,
    count(*) AS snapshots
   FROM rolling
  GROUP BY sim_run_id;
-- @@ view public.ottoq_kpi_peak_site_kw_demand
CREATE VIEW public.ottoq_kpi_peak_site_kw_demand AS
 WITH rolling AS (
         SELECT s.sim_run_id,
            s."timestamp",
            avg((((COALESCE(s.total_ev_charging_kw, (0)::numeric) + COALESCE(s.building_load_kw, (0)::numeric)) + COALESCE(s.lighting_load_kw, (0)::numeric)) - COALESCE(s.solar_generation_kw, (0)::numeric))) OVER (PARTITION BY s.sim_run_id, s.depot_id ORDER BY s."timestamp" RANGE BETWEEN '00:15:00'::interval PRECEDING AND CURRENT ROW) AS kw_15min
           FROM public.site_energy_snapshots s
        )
 SELECT sim_run_id,
    round(max(kw_15min), 1) AS peak_site_kw_demand_15min,
    count(*) AS snapshots
   FROM rolling
  GROUP BY sim_run_id;
-- @@ view public.ottoq_kpi_service_point_turns
CREATE VIEW public.ottoq_kpi_service_point_turns AS
 SELECT sim_run_id,
    day,
    count(*) FILTER (WHERE ((src = 'left'::text) AND (NOT teardown))) AS turns_completed,
    count(DISTINCT stall_id) FILTER (WHERE (src = 'left'::text)) AS points_used,
    round(((count(*) FILTER (WHERE ((src = 'left'::text) AND (NOT teardown))))::numeric / (GREATEST((1)::bigint, count(DISTINCT stall_id) FILTER (WHERE (src = 'left'::text))))::numeric), 2) AS turns_per_point_per_day,
    count(*) FILTER (WHERE ((src = 'booked'::text) AND (state <> 'done'::text))) AS bookings_not_a_turn,
    count(*) FILTER (WHERE ((src = 'booked'::text) AND (release_reason = 'window_elapsed'::text))) AS released_never_occupied,
    count(*) FILTER (WHERE ((src = 'booked'::text) AND (release_reason = 'run_stopped'::text))) AS released_by_teardown,
    count(*) FILTER (WHERE ((src = 'booked'::text) AND (release_reason = 'no_show_grace_elapsed'::text))) AS released_no_show,
    count(DISTINCT stall_id) FILTER (WHERE ((src = 'left'::text) AND (NOT teardown))) AS points_with_a_turn,
    count(*) FILTER (WHERE (src = 'booked'::text)) AS bookings_seen,
    count(*) FILTER (WHERE ((src = 'booked'::text) AND (state = 'done'::text))) AS bookings_done,
    count(DISTINCT stall_id) FILTER (WHERE (src = 'booked'::text)) AS points_booked,
    round(((count(*) FILTER (WHERE ((src = 'booked'::text) AND (state = 'done'::text))))::numeric / (GREATEST((1)::bigint, count(DISTINCT stall_id) FILTER (WHERE (src = 'booked'::text))))::numeric), 2) AS booking_turns_per_point_per_day,
    count(*) FILTER (WHERE ((src = 'left'::text) AND teardown)) AS left_at_teardown
   FROM ( SELECT 'left'::text AS src,
            e.sim_run_id,
            (date_trunc('day'::text, e.sim_clock_at))::date AS day,
            ((((e.payload -> 'diff'::text) -> 'current_stall_id'::text) ->> 'from'::text))::uuid AS stall_id,
            COALESCE(((((e.payload -> 'diff'::text) -> 'current_state'::text) ->> 'to'::text) = 'offline'::text), false) AS teardown,
            NULL::text AS state,
            NULL::text AS release_reason
           FROM public.ottoq_events e
          WHERE (((e.event_type || ''::text) = 'vehicle.state_changed'::text) AND (e.sim_run_id IS NOT NULL) AND ((((e.payload -> 'diff'::text) -> 'current_stall_id'::text) ->> 'from'::text) IS NOT NULL))
        UNION ALL
         SELECT 'booked'::text,
            b.sim_run_id,
            (date_trunc('day'::text, lower(b.during)))::date AS date_trunc,
            b.stall_id,
            false,
            b.state,
            b.release_reason
           FROM public.ottoq_stall_bookings b
          WHERE (b.sim_run_id IS NOT NULL)) u
  GROUP BY sim_run_id, day;
-- @@ view public.ottoq_kpi_touch_events_per_turn
CREATE VIEW public.ottoq_kpi_touch_events_per_turn AS
 WITH per_run AS (
         SELECT u.sim_run_id,
            count(*) FILTER (WHERE (u.src = 'arrived'::text)) AS arrivals,
            count(*) FILTER (WHERE ((u.src = 'booked'::text) AND u.done)) AS bookings_done,
            count(*) FILTER (WHERE ((u.src = 'booked'::text) AND (NOT u.done))) AS bookings_not_done,
            count(*) FILTER (WHERE (u.src = 'worked'::text)) AS technician
           FROM ( SELECT 'arrived'::text AS src,
                    e.sim_run_id,
                    NULL::boolean AS done
                   FROM public.ottoq_events e
                  WHERE (((e.event_type || ''::text) = 'vehicle.state_changed'::text) AND (e.sim_run_id IS NOT NULL) AND ((((e.payload -> 'diff'::text) -> 'current_state'::text) ->> 'to'::text) = 'arrived_at_gate'::text))
                UNION ALL
                 SELECT 'booked'::text,
                    b.sim_run_id,
                    (b.state = 'done'::text)
                   FROM public.ottoq_stall_bookings b
                  WHERE (b.sim_run_id IS NOT NULL)
                UNION ALL
                 SELECT 'worked'::text,
                    vn.sim_run_id,
                    NULL::boolean
                   FROM (((public.ottoq_visit_needs vn
                     CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a(value))
                     JOIN public.service_cadence_policy c ON ((c.svc = (a.value ->> 'svc'::text))))
                     JOIN public.ottoq_kpi_touch_lanes l ON (((l.lane = c.lane) AND l.human_touch)))
                  WHERE ((vn.sim_run_id IS NOT NULL) AND (COALESCE((a.value ->> 'status'::text), 'pending'::text) <> 'cancelled'::text) AND (((a.value ->> 'started_at'::text) IS NOT NULL) OR ((a.value ->> 'done_at'::text) IS NOT NULL)) AND (NOT (EXISTS ( SELECT 1
                           FROM public.ottoq_kpi_touch_actor_types k
                          WHERE ((k.actor_type = (a.value ->> 'performed_by'::text)) AND (NOT k.human_actor))))))) u
          GROUP BY u.sim_run_id
        ), counted AS (
         SELECT p.sim_run_id,
            p.arrivals,
            p.bookings_done,
            p.bookings_not_done,
            p.technician,
            ( SELECT count(*) AS count
                   FROM public.ottoq_events e
                  WHERE ((e.sim_run_id = p.sim_run_id) AND (e.actor_type IN ( SELECT k.actor_type
                           FROM public.ottoq_kpi_touch_actor_types k
                          WHERE k.human_actor)))) AS n_op,
            ( SELECT count(*) AS count
                   FROM public.ottoq_decisions d
                  WHERE ((d.sim_run_id = p.sim_run_id) AND (d.override_id IS NOT NULL))) AS n_ov,
            ( SELECT count(*) AS count
                   FROM public.ottoq_decisions d
                  WHERE ((d.sim_run_id = p.sim_run_id) AND d.overridden AND (d.override_id IS NULL))) AS n_ov_flag_only
           FROM per_run p
        )
 SELECT sim_run_id,
    ((n_op + n_ov) + technician) AS touch_events,
    arrivals AS turns,
        CASE
            WHEN (arrivals > 0) THEN round(((((n_op + n_ov) + technician))::numeric / (arrivals)::numeric), 3)
            ELSE NULL::numeric
        END AS touch_events_per_turn,
    bookings_not_done AS bookings_not_a_turn,
    n_op AS touch_events_operator,
    n_ov AS touch_events_override,
    n_ov_flag_only AS touch_events_override_flag_only,
    technician AS touch_events_technician,
    bookings_done
   FROM counted;
-- @@ view public.ottoq_margin_ledger
CREATE VIEW public.ottoq_margin_ledger WITH (security_invoker=true) AS
 WITH pr AS (
         SELECT max(ottoq_margin_prices.low) FILTER (WHERE (ottoq_margin_prices.price_code = 'revenue_per_deployed_car_hour'::text)) AS rev_lo,
            max(ottoq_margin_prices.point) FILTER (WHERE (ottoq_margin_prices.price_code = 'revenue_per_deployed_car_hour'::text)) AS rev_pt,
            max(ottoq_margin_prices.high) FILTER (WHERE (ottoq_margin_prices.price_code = 'revenue_per_deployed_car_hour'::text)) AS rev_hi,
            max(ottoq_margin_prices.low) FILTER (WHERE (ottoq_margin_prices.price_code = 'vehicle_capex'::text)) AS cap_lo,
            max(ottoq_margin_prices.point) FILTER (WHERE (ottoq_margin_prices.price_code = 'vehicle_capex'::text)) AS cap_pt,
            max(ottoq_margin_prices.high) FILTER (WHERE (ottoq_margin_prices.price_code = 'vehicle_capex'::text)) AS cap_hi
           FROM public.ottoq_margin_prices
        ), cmp AS (
         SELECT 'seat'::text AS comparison,
            x.sweep_code,
            x.buildout_code,
            x.fixed_params,
            x.seed,
            x.baseline,
            x.world_identical,
            x.served_delta,
            x.on_time_pct_delta,
            x.deployed_car_hours_delta,
            x.site_cost_usd_delta,
            x.otto_q_run,
            x.baseline_run
           FROM public.ottoq_throughput_sweep_pairs x
        UNION ALL
         SELECT 'dial'::text,
            c.sweep_code,
            c.buildout_code,
            c.treatment_params,
            c.seed,
            c.control_cell,
            c.world_identical,
            c.served_delta,
            c.on_time_pct_delta,
            c.deployed_car_hours_delta,
            c.site_cost_usd_delta,
            c.treatment_run,
            c.control_run
           FROM public.ottoq_throughput_sweep_contrasts c
        ), p AS (
         SELECT x.comparison,
            x.sweep_code,
            x.buildout_code,
            x.fixed_params,
            x.seed,
            x.baseline,
            x.world_identical,
            x.served_delta,
            x.on_time_pct_delta,
            x.deployed_car_hours_delta,
            x.site_cost_usd_delta,
            x.otto_q_run,
            x.baseline_run,
            ((qa.scorecard #>> '{run,horizon_h}'::text[]))::numeric AS window_h,
            ((qa.arm_metrics ->> 'demand_car_hours'::text))::numeric AS demand_car_hours,
            COALESCE((((qa.arm_metrics ->> 'demand_car_hours'::text))::numeric = ((ba.arm_metrics ->> 'demand_car_hours'::text))::numeric), false) AS demand_identical,
            (((ba.arm_metrics ->> 'unmet_demand_car_hours'::text))::numeric - ((qa.arm_metrics ->> 'unmet_demand_car_hours'::text))::numeric) AS demand_met_car_hours_delta
           FROM ((cmp x
             JOIN public.ottoq_throughput_sweep_arms qa ON (((qa.sim_run_id = x.otto_q_run) AND (NOT qa.replicate))))
             JOIN public.ottoq_throughput_sweep_arms ba ON (((ba.sim_run_id = x.baseline_run) AND (NOT ba.replicate))))
        ), m AS (
         SELECT p.comparison,
            p.sweep_code,
            p.buildout_code,
            p.fixed_params,
            p.seed,
            p.baseline,
            p.world_identical,
            p.served_delta,
            p.on_time_pct_delta,
            p.deployed_car_hours_delta,
            p.site_cost_usd_delta,
            p.otto_q_run,
            p.baseline_run,
            p.window_h,
            p.demand_car_hours,
            p.demand_identical,
            p.demand_met_car_hours_delta,
            (p.demand_met_car_hours_delta / NULLIF(p.window_h, (0)::numeric)) AS cars,
            public.ottoq_margin_band(p.demand_met_car_hours_delta, pr.rev_lo, pr.rev_pt, pr.rev_hi) AS up,
            public.ottoq_margin_band((p.demand_met_car_hours_delta / NULLIF(p.window_h, (0)::numeric)), pr.cap_lo, pr.cap_pt, pr.cap_hi) AS cap
           FROM (p
             CROSS JOIN pr)
        )
 SELECT sweep_code,
    buildout_code,
    fixed_params,
    seed,
    baseline,
    world_identical,
    demand_identical,
    window_h,
    demand_car_hours,
    served_delta,
    on_time_pct_delta,
    deployed_car_hours_delta,
    demand_met_car_hours_delta,
    up[1] AS uptime_usd_low,
    up[2] AS uptime_usd_point,
    up[3] AS uptime_usd_high,
    round(site_cost_usd_delta, 2) AS site_cost_usd_delta,
    round(cars, 2) AS cars_at_work_delta,
    cap[1] AS fleet_capex_equiv_usd_low,
    cap[2] AS fleet_capex_equiv_usd_point,
    cap[3] AS fleet_capex_equiv_usd_high,
    otto_q_run,
    baseline_run,
    comparison
   FROM m;
-- @@ view public.ottoq_margin_summary
CREATE VIEW public.ottoq_margin_summary WITH (security_invoker=true) AS
 WITH l AS (
         SELECT ottoq_margin_ledger.sweep_code,
            ottoq_margin_ledger.buildout_code,
            ottoq_margin_ledger.fixed_params,
            ottoq_margin_ledger.seed,
            ottoq_margin_ledger.baseline,
            ottoq_margin_ledger.world_identical,
            ottoq_margin_ledger.demand_identical,
            ottoq_margin_ledger.window_h,
            ottoq_margin_ledger.demand_car_hours,
            ottoq_margin_ledger.served_delta,
            ottoq_margin_ledger.on_time_pct_delta,
            ottoq_margin_ledger.deployed_car_hours_delta,
            ottoq_margin_ledger.demand_met_car_hours_delta,
            ottoq_margin_ledger.uptime_usd_low,
            ottoq_margin_ledger.uptime_usd_point,
            ottoq_margin_ledger.uptime_usd_high,
            ottoq_margin_ledger.site_cost_usd_delta,
            ottoq_margin_ledger.cars_at_work_delta,
            ottoq_margin_ledger.fleet_capex_equiv_usd_low,
            ottoq_margin_ledger.fleet_capex_equiv_usd_point,
            ottoq_margin_ledger.fleet_capex_equiv_usd_high,
            ottoq_margin_ledger.otto_q_run,
            ottoq_margin_ledger.baseline_run,
            (ottoq_margin_ledger.world_identical AND ottoq_margin_ledger.demand_identical) AS clean
           FROM public.ottoq_margin_ledger
        )
 SELECT sweep_code,
    buildout_code,
    fixed_params,
    baseline,
    max(window_h) AS window_h,
    count(*) FILTER (WHERE clean) AS seeds,
    count(*) FILTER (WHERE (NOT clean)) AS seeds_set_aside,
    jsonb_build_object('mean', round(avg(served_delta) FILTER (WHERE clean), 1), 'min', min(served_delta) FILTER (WHERE clean), 'max', max(served_delta) FILTER (WHERE clean)) AS served_delta,
    jsonb_build_object('mean', round(avg(demand_met_car_hours_delta) FILTER (WHERE clean), 1), 'min', min(demand_met_car_hours_delta) FILTER (WHERE clean), 'max', max(demand_met_car_hours_delta) FILTER (WHERE clean)) AS demand_met_car_hours_delta,
    jsonb_build_object('mean_point', round(avg(uptime_usd_point) FILTER (WHERE clean), 0), 'min_low', min(uptime_usd_low) FILTER (WHERE clean), 'max_high', max(uptime_usd_high) FILTER (WHERE clean)) AS uptime_usd,
    jsonb_build_object('mean', round(avg(site_cost_usd_delta) FILTER (WHERE clean), 2), 'min', min(site_cost_usd_delta) FILTER (WHERE clean), 'max', max(site_cost_usd_delta) FILTER (WHERE clean)) AS site_cost_usd_delta,
    jsonb_build_object('mean', round(avg(cars_at_work_delta) FILTER (WHERE clean), 2), 'min', min(cars_at_work_delta) FILTER (WHERE clean), 'max', max(cars_at_work_delta) FILTER (WHERE clean)) AS cars_at_work_delta,
    jsonb_build_object('mean_point', round(avg(fleet_capex_equiv_usd_point) FILTER (WHERE clean), 0), 'min_low', min(fleet_capex_equiv_usd_low) FILTER (WHERE clean), 'max_high', max(fleet_capex_equiv_usd_high) FILTER (WHERE clean)) AS fleet_capex_equiv_usd
   FROM l
  GROUP BY sweep_code, buildout_code, fixed_params, baseline;
-- @@ view public.ottoq_network_summary_weekly
CREATE VIEW public.ottoq_network_summary_weekly WITH (security_invoker=on) AS
 SELECT date_trunc('week'::text, (report_date)::timestamp with time zone) AS week_start,
    count(DISTINCT depot_id) AS active_depots,
    sum(visits_completed) AS total_visits,
    sum(vehicles_served) AS total_unique_vehicles,
    round(avg(avg_sla_compliance_pct), 2) AS network_avg_sla_pct,
    sum(rule_failures_count) AS total_rule_failures,
    sum(anomalies_count) AS total_anomalies,
    sum(emergencies_count) AS total_emergencies,
    round(sum(total_kwh_delivered), 1) AS total_kwh,
    round(sum(total_revenue_usd), 2) AS total_revenue,
    round(sum(total_cost_usd), 2) AS total_cost,
    round(sum(total_carbon_offset_kg), 1) AS total_carbon_offset_kg
   FROM public.ottoq_depot_benchmarks_daily
  WHERE (report_date >= (CURRENT_DATE - 90))
  GROUP BY (date_trunc('week'::text, (report_date)::timestamp with time zone))
  ORDER BY (date_trunc('week'::text, (report_date)::timestamp with time zone)) DESC;
-- @@ view public.ottoq_oem_anomaly_summary
CREATE VIEW public.ottoq_oem_anomaly_summary WITH (security_invoker=on) AS
 SELECT ao.fleet_operator_id,
    ao.depot_id,
    ao.detector_code,
    ad.category AS detector_category,
    ad.title AS detector_title,
    count(*) AS observations_7d,
    count(*) FILTER (WHERE ao.is_anomaly) AS anomalies_7d,
    count(*) FILTER (WHERE (ao.severity = ANY (ARRAY['critical'::text, 'safety_critical'::text]))) AS critical_7d,
    max(ao.observed_at) FILTER (WHERE ao.is_anomaly) AS last_anomaly_at,
    round(((100.0 * (count(*) FILTER (WHERE ao.is_anomaly))::numeric) / (NULLIF(count(*), 0))::numeric), 2) AS anomaly_rate_pct
   FROM (public.ottoq_anomaly_observations ao
     JOIN public.ottoq_anomaly_detectors ad ON ((ad.detector_code = ao.detector_code)))
  WHERE (ao.observed_at > (now() - '7 days'::interval))
  GROUP BY ao.fleet_operator_id, ao.depot_id, ao.detector_code, ad.category, ad.title;
-- @@ view public.ottoq_oem_dashboard_summary
CREATE VIEW public.ottoq_oem_dashboard_summary AS
 SELECT fo.id AS fleet_operator_id,
    fo.name AS fleet_operator_name,
    d.id AS depot_id,
    d.name AS depot_name,
    ( SELECT count(*) AS count
           FROM public.ottoq_events e
          WHERE ((e.fleet_operator_id = fo.id) AND ((e.depot_id = d.id) OR (e.depot_id IS NULL)) AND (e.occurred_at > (now() - '24:00:00'::interval)))) AS events_24h,
    ( SELECT count(*) AS count
           FROM public.ottoq_predictions p
          WHERE ((p.fleet_operator_id = fo.id) AND ((p.depot_id = d.id) OR (p.depot_id IS NULL)) AND (p.created_at > (now() - '24:00:00'::interval)))) AS predictions_24h,
    ( SELECT count(*) AS count
           FROM public.ottoq_anomaly_observations a
          WHERE ((a.fleet_operator_id = fo.id) AND ((a.depot_id = d.id) OR (a.depot_id IS NULL)) AND (a.is_anomaly = true) AND (a.observed_at > (now() - '24:00:00'::interval)))) AS anomalies_24h,
    ( SELECT count(*) AS count
           FROM public.ottoq_rule_evaluations re
          WHERE ((re.fleet_operator_id = fo.id) AND ((re.depot_id = d.id) OR (re.depot_id IS NULL)) AND (re.passed = false) AND (re.evaluated_at > (now() - '24:00:00'::interval)))) AS rule_failures_24h,
    ( SELECT count(*) AS count
           FROM public.ottoq_sla_violations v
          WHERE ((v.fleet_operator_id = fo.id) AND ((v.depot_id = d.id) OR (v.depot_id IS NULL)) AND (v.detected_at > (now() - '24:00:00'::interval)))) AS sla_violations_24h,
    ( SELECT count(*) AS count
           FROM public.ottoq_emergency_invocations ei
          WHERE ((ei.depot_id = d.id) AND (ei.triggered_at > (now() - '24:00:00'::interval)))) AS emergencies_24h,
    ( SELECT count(*) AS count
           FROM public.ottoq_emergency_invocations ei
          WHERE ((ei.depot_id = d.id) AND (ei.cleared_at IS NULL))) AS active_emergencies,
    ( SELECT count(*) AS count
           FROM public.ottoq_recommendations r
          WHERE ((r.fleet_operator_id = fo.id) AND (r.status = ANY (ARRAY['pending'::text, 'validating'::text, 'admitted'::text])) AND ((r.expires_at IS NULL) OR (r.expires_at > now())))) AS active_recommendations,
    ( SELECT sc.overall_compliance_pct
           FROM public.ottoq_sla_conformance_daily sc
          WHERE ((sc.fleet_operator_id = fo.id) AND ((sc.depot_id = d.id) OR ((sc.depot_id IS NULL) AND (d.id IS NULL))))
          ORDER BY sc.report_date DESC
         LIMIT 1) AS last_compliance_pct,
    ( SELECT sc.composite_grade
           FROM public.ottoq_sla_conformance_daily sc
          WHERE ((sc.fleet_operator_id = fo.id) AND ((sc.depot_id = d.id) OR ((sc.depot_id IS NULL) AND (d.id IS NULL))))
          ORDER BY sc.report_date DESC
         LIMIT 1) AS last_grade
   FROM (public.fleet_operators fo
     CROSS JOIN public.depots d)
  WHERE (fo.is_active = true);
-- @@ view public.ottoq_oem_model_coverage
CREATE VIEW public.ottoq_oem_model_coverage WITH (security_invoker=on) AS
 SELECT r.prediction_type,
    fo.name AS oem_name,
    fo.id AS fleet_operator_id,
    r.vehicle_class,
    (r.model_version_id IS NOT NULL) AS has_trained_model,
    mv.version_tag,
    mv.deployment_stage,
    mv.artifact_format,
    r.shadow_mode,
    r.created_at AS route_created_at
   FROM ((public.ottoq_model_routes r
     LEFT JOIN public.fleet_operators fo ON ((fo.id = r.fleet_operator_id)))
     LEFT JOIN public.model_versions mv ON ((mv.id = r.model_version_id)))
  WHERE ((r.effective_from <= now()) AND ((r.effective_until IS NULL) OR (r.effective_until > now())))
  ORDER BY r.prediction_type, fo.name NULLS FIRST, r.vehicle_class NULLS FIRST;
-- @@ view public.ottoq_oem_override_summary
CREATE VIEW public.ottoq_oem_override_summary WITH (security_invoker=on) AS
 SELECT fleet_operator_id,
    depot_id,
    count(*) FILTER (WHERE (enforcement_taken = 'overridden'::text)) AS overrides_7d,
    count(DISTINCT entity_id) FILTER (WHERE (enforcement_taken = 'overridden'::text)) AS unique_entities,
    count(DISTINCT rule_code) FILTER (WHERE (enforcement_taken = 'overridden'::text)) AS unique_rules_overridden,
    count(*) FILTER (WHERE (enforcement_taken = ANY (ARRAY['blocked'::text, 'warned'::text]))) AS blocks_or_warnings_7d
   FROM public.ottoq_rule_evaluations re
  WHERE (evaluated_at > (now() - '7 days'::interval))
  GROUP BY fleet_operator_id, depot_id;
-- @@ view public.ottoq_oem_recent_predictions
CREATE VIEW public.ottoq_oem_recent_predictions WITH (security_invoker=on) AS
 SELECT p.id AS prediction_id,
    p.fleet_operator_id,
    p.depot_id,
    p.vehicle_id,
    p.prediction_type,
    p.title,
    p.predicted_value,
    p.p10,
    p.p50,
    p.p90,
    p.confidence,
    p.prediction_baseline,
    p.action_type,
    p.target_at,
    p.horizon_minutes,
    p.shadow_only,
    p.status,
    p.execution_status,
    p.created_at,
    p.expires_at,
    pt.title AS prediction_title_full,
    pt.output_unit
   FROM (public.ottoq_predictions p
     LEFT JOIN public.ottoq_prediction_types_catalog pt ON ((pt.prediction_type = p.prediction_type)))
  WHERE (p.created_at > (now() - '24:00:00'::interval))
  ORDER BY p.created_at DESC;
-- @@ view public.ottoq_oem_rule_failure_top
CREATE VIEW public.ottoq_oem_rule_failure_top WITH (security_invoker=on) AS
 SELECT re.fleet_operator_id,
    re.depot_id,
    re.rule_code,
    r.title,
    r.severity AS rule_severity,
    count(*) AS failure_count,
    count(DISTINCT re.entity_id) AS unique_entities_affected,
    max(re.evaluated_at) AS most_recent
   FROM (public.ottoq_rule_evaluations re
     JOIN public.ottoq_rules r ON (((r.rule_code = re.rule_code) AND (r.version = re.rule_version))))
  WHERE ((re.passed = false) AND (re.evaluated_at > (now() - '7 days'::interval)))
  GROUP BY re.fleet_operator_id, re.depot_id, re.rule_code, r.title, r.severity
  ORDER BY (count(*)) DESC;
-- @@ view public.ottoq_oem_unit_economics_30d
CREATE VIEW public.ottoq_oem_unit_economics_30d WITH (security_invoker=on) AS
 SELECT fleet_operator_id,
    count(*) AS visits,
    round(sum(kwh_delivered), 1) AS total_kwh,
    round(sum(total_cost_usd), 2) AS total_cost_usd,
    round(sum(billable_amount_usd), 2) AS total_revenue_usd,
    round(sum(margin_usd), 2) AS total_margin_usd,
    round(avg(margin_pct), 2) AS avg_margin_pct,
    round(avg(total_cost_usd), 2) AS avg_cost_per_visit_usd,
    round(avg(kwh_delivered), 1) AS avg_kwh_per_visit,
    round(sum(carbon_offset_kg_co2), 1) AS total_carbon_offset_kg
   FROM public.ottoq_visit_cost_attribution
  WHERE (visit_completed_at > (now() - '30 days'::interval))
  GROUP BY fleet_operator_id;
-- @@ view public.ottoq_oem_visit_history
CREATE VIEW public.ottoq_oem_visit_history WITH (security_invoker=on) AS
 SELECT id AS visit_report_id,
    fleet_operator_id,
    depot_id,
    vehicle_id,
    schedule_id,
    visit_started_at,
    visit_completed_at,
    planned_duration_min,
    actual_duration_min,
    variance_minutes,
    deviation_count,
    audit_trail_complete,
    redeployment_status,
    jsonb_array_length(overrides_applied) AS override_count,
    jsonb_array_length(abnormalities) AS abnormality_count,
    jsonb_array_length(oem_interactions) AS oem_interaction_count,
    jsonb_array_length(exceptions_raised) AS exception_count
   FROM public.depot_visit_reports vr
  ORDER BY visit_completed_at DESC NULLS LAST;
-- @@ view public.ottoq_policy_catalog_gap
CREATE VIEW public.ottoq_policy_catalog_gap AS
 WITH src AS (
         SELECT (((n.nspname)::text || '.'::text) || (p.proname)::text) AS fn,
            p.prosrc AS body
           FROM (pg_proc p
             JOIN pg_namespace n ON ((n.oid = p.pronamespace)))
          WHERE (n.nspname = ANY (ARRAY['public'::name, 'twin'::name, 'ottoq'::name]))
        UNION ALL
         SELECT ((((n.nspname)::text || '.'::text) || (c_1.relname)::text) ||
                CASE
                    WHEN (c_1.relkind = 'm'::"char") THEN ' (matview)'::text
                    ELSE ' (view)'::text
                END),
            pg_get_viewdef(c_1.oid, true) AS pg_get_viewdef
           FROM (pg_class c_1
             JOIN pg_namespace n ON ((n.oid = c_1.relnamespace)))
          WHERE ((c_1.relkind = ANY (ARRAY['v'::"char", 'm'::"char"])) AND (n.nspname = ANY (ARRAY['public'::name, 'twin'::name, 'ottoq'::name])))
        ), literal_reads AS (
         SELECT s.fn,
            m.m[1] AS param_key
           FROM src s,
            LATERAL regexp_matches(s.body, 'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)'''::text, 'g'::text) m(m)
        ), dynamic_reads AS (
         SELECT 'public.ottoq_intelligence_sources(gate_param_key)'::text AS fn,
            i.gate_param_key AS param_key
           FROM public.ottoq_intelligence_sources i
          WHERE (i.gate_param_key IS NOT NULL)
        ), all_reads AS (
         SELECT literal_reads.fn,
            literal_reads.param_key
           FROM literal_reads
        UNION
         SELECT dynamic_reads.fn,
            dynamic_reads.param_key
           FROM dynamic_reads
        ), caller_defaults AS (
         SELECT m.m[1] AS param_key,
            array_agg(DISTINCT btrim(m.m[2]) ORDER BY (btrim(m.m[2]))) AS defaults
           FROM src s,
            LATERAL regexp_matches(s.body, 'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)''\s*,\s*([^)]*)\)'::text, 'g'::text) m(m)
          GROUP BY m.m[1]
        ), read_keys AS (
         SELECT a.param_key,
            count(DISTINCT a.fn) AS readers,
            array_agg(DISTINCT a.fn ORDER BY a.fn) AS reader_functions
           FROM all_reads a
          GROUP BY a.param_key
        ), rows_per_key AS (
         SELECT pp.param_key,
            count(*) AS live_rows
           FROM public.ottoq_policy_params pp
          GROUP BY pp.param_key
        )
 SELECT COALESCE(r.param_key, c.param_key) AS param_key,
        CASE
            WHEN (r.param_key IS NULL) THEN 'catalogued_unread'::text
            WHEN (c.param_key IS NULL) THEN 'read_uncatalogued'::text
            ELSE 'ok'::text
        END AS status,
    COALESCE(r.readers, (0)::bigint) AS readers,
    COALESCE(x.live_rows, (0)::bigint) AS live_rows,
    (c.param_key IS NOT NULL) AS catalogued,
    c.min_value,
    c.max_value,
    c.default_value,
    d.defaults AS caller_defaults,
    r.reader_functions
   FROM (((read_keys r
     FULL JOIN public.ottoq_policy_param_catalog c ON ((c.param_key = r.param_key)))
     LEFT JOIN rows_per_key x ON ((x.param_key = COALESCE(r.param_key, c.param_key))))
     LEFT JOIN caller_defaults d ON ((d.param_key = COALESCE(r.param_key, c.param_key))));
-- @@ view public.ottoq_policy_read_site_census
CREATE VIEW public.ottoq_policy_read_site_census AS
 WITH src AS (
         SELECT (((n.nspname)::text || '.'::text) || (p_1.proname)::text) AS fn,
            p_1.prosrc AS body
           FROM (pg_proc p_1
             JOIN pg_namespace n ON ((n.oid = p_1.pronamespace)))
          WHERE ((n.nspname = ANY (ARRAY['public'::name, 'twin'::name, 'ottoq'::name])) AND (p_1.prosrc ~ 'ottoq_policy_get\s*\('::text))
        UNION ALL
         SELECT ((((n.nspname)::text || '.'::text) || (c_1.relname)::text) ||
                CASE
                    WHEN (c_1.relkind = 'm'::"char") THEN ' (matview)'::text
                    ELSE ' (view)'::text
                END),
            pg_get_viewdef(c_1.oid, true) AS pg_get_viewdef
           FROM (pg_class c_1
             JOIN pg_namespace n ON ((n.oid = c_1.relnamespace)))
          WHERE ((c_1.relkind = ANY (ARRAY['v'::"char", 'm'::"char"])) AND (n.nspname = ANY (ARRAY['public'::name, 'twin'::name, 'ottoq'::name])) AND (pg_get_viewdef(c_1.oid, true) ~ 'ottoq_policy_get\s*\('::text))
        ), call_sites AS (
         SELECT s.fn,
            count(*) AS n_call_sites
           FROM src s,
            LATERAL regexp_matches(s.body, 'ottoq_policy_get\s*\('::text, 'g'::text) m(m)
          GROUP BY s.fn
        ), parsed AS (
         SELECT s.fn,
            count(*) AS n_parsed
           FROM src s,
            LATERAL regexp_matches(s.body, 'ottoq_policy_get\s*\(\s*[^,]+,\s*''([a-z0-9_]+)'''::text, 'g'::text) m(m)
          GROUP BY s.fn
        )
 SELECT c.fn,
    c.n_call_sites,
    COALESCE(p.n_parsed, (0)::bigint) AS n_parsed,
    (c.n_call_sites - COALESCE(p.n_parsed, (0)::bigint)) AS n_unparsed
   FROM (call_sites c
     LEFT JOIN parsed p ON ((p.fn = c.fn)));
-- @@ view public.ottoq_proposer_scorecard
CREATE VIEW public.ottoq_proposer_scorecard AS
 SELECT source,
    proposer_rank,
    count(*) AS dispositions,
    count(*) FILTER (WHERE (status = 'enacted'::text)) AS enacted,
    count(*) FILTER (WHERE abstained) AS abstained,
    count(*) FILTER (WHERE ((status = 'refused'::text) AND (NOT abstained))) AS refused_real,
    count(*) FILTER (WHERE (status = 'superseded'::text)) AS superseded,
    count(*) FILTER (WHERE (status = 'expired'::text)) AS expired,
    count(*) FILTER (WHERE (COALESCE(promotion_count, 0) > 0)) AS rescued_by_promotion,
    round(((100.0 * (count(*) FILTER (WHERE (status = 'enacted'::text)))::numeric) / (NULLIF(count(*) FILTER (WHERE (NOT abstained)), 0))::numeric), 2) AS enacted_pct_of_committed,
    count(DISTINCT sim_run_id) AS runs,
    min(disposed_at) AS first_disposed,
    max(disposed_at) AS last_disposed
   FROM public.ottoq_proposal_disposition_ledger d
  GROUP BY source, proposer_rank;
-- @@ view public.ottoq_recent_audit_bundles
CREATE VIEW public.ottoq_recent_audit_bundles WITH (security_invoker=on) AS
 SELECT b.bundle_id,
    b.bundle_code,
    b.fleet_operator_id,
    fo.name AS fleet_operator_name,
    b.window_start,
    b.window_end,
    b.format,
    b.size_bytes,
    b.sha256,
    ((b.signature IS NOT NULL) AND (b.signature !~~ 'UNSIGNED:%'::text)) AS is_signed,
    b.signature_key_id,
    b.manifest,
    b.generated_at,
    b.generated_by_actor_type,
    b.download_count,
    b.last_downloaded_at,
    b.expires_at,
    b.revoked_at
   FROM (public.ottoq_audit_bundles b
     LEFT JOIN public.fleet_operators fo ON ((fo.id = b.fleet_operator_id)))
  WHERE (b.generated_at > (now() - '90 days'::interval))
  ORDER BY b.generated_at DESC;
-- @@ view public.ottoq_recent_audit_reports
CREATE VIEW public.ottoq_recent_audit_reports WITH (security_invoker=on) AS
 SELECT report_id,
    report_type,
    report_subtype,
    fleet_operator_id,
    depot_id,
    window_start,
    window_end,
    generation_status,
    generation_completed_at,
    event_count,
    rule_eval_count,
    prediction_count,
    anomaly_count,
    override_count,
    emergency_count,
    visit_count,
    audit_trail_complete,
    data_quality_score,
    (signature IS NOT NULL) AS is_signed,
    signature_key_id,
    format,
    expires_at
   FROM public.ottoq_audit_reports r
  WHERE (requested_at > (now() - '30 days'::interval))
  ORDER BY requested_at DESC;
-- @@ view public.ottoq_recent_rule_evaluations
CREATE VIEW public.ottoq_recent_rule_evaluations WITH (security_invoker=on) AS
 SELECT e.evaluation_id,
    e.evaluated_at,
    e.rule_code,
    e.rule_version,
    r.title AS rule_title,
    r.category AS rule_category,
    e.entity_type,
    e.entity_id,
    e.fleet_operator_id,
    e.depot_id,
    e.passed,
    e.reason,
    e.severity,
    e.enforcement_taken,
    e.action_context,
    e.duration_ms,
    e.linked_event_id,
    e.correlation_id
   FROM (public.ottoq_rule_evaluations e
     LEFT JOIN public.ottoq_rules r ON (((r.rule_code = e.rule_code) AND (r.version = e.rule_version))))
  WHERE (e.evaluated_at > (now() - '24:00:00'::interval))
  ORDER BY e.evaluation_seq DESC;
-- @@ view public.ottoq_recommendation_outcomes_24h
CREATE VIEW public.ottoq_recommendation_outcomes_24h WITH (security_invoker=on) AS
 SELECT prediction_type,
    proposed_action,
    count(*) FILTER (WHERE (status = 'admitted'::text)) AS admitted,
    count(*) FILTER (WHERE (status = 'rejected'::text)) AS rejected,
    count(*) FILTER (WHERE (status = 'executed'::text)) AS executed,
    count(*) FILTER (WHERE (execution_outcome = 'succeeded'::text)) AS execution_succeeded,
    count(*) FILTER (WHERE (status = 'shadow'::text)) AS shadow_only_count,
    count(*) AS total,
    round(((100.0 * (count(*) FILTER (WHERE (status = ANY (ARRAY['admitted'::text, 'executed'::text]))))::numeric) / (NULLIF(count(*) FILTER (WHERE (NOT shadow_only)), 0))::numeric), 2) AS admission_rate_pct
   FROM public.ottoq_recommendations
  WHERE (emitted_at > (now() - '24:00:00'::interval))
  GROUP BY prediction_type, proposed_action;
-- @@ view public.ottoq_reward_unscorable
CREATE VIEW public.ottoq_reward_unscorable AS
 SELECT public.ottoq_run_unscorable_reason(d.*) AS reason,
    count(*) AS runs
   FROM public.ottoq_run_dial_ledger d
  WHERE (public.ottoq_run_unscorable_reason(d.*) IS NOT NULL)
  GROUP BY (public.ottoq_run_unscorable_reason(d.*))
  ORDER BY (count(*)) DESC;
-- @@ view public.ottoq_rule_enforcement_reality
CREATE VIEW public.ottoq_rule_enforcement_reality AS
 WITH win AS (
         SELECT min(ottoq_rule_evaluations.evaluated_at) AS window_start,
            max(ottoq_rule_evaluations.evaluated_at) AS window_end,
            GREATEST(1, ((max(ottoq_rule_evaluations.evaluated_at))::date - (min(ottoq_rule_evaluations.evaluated_at))::date)) AS window_days
           FROM public.ottoq_rule_evaluations
        )
 SELECT r.rule_code,
    r.severity,
    r.enforcement,
    r.status,
    array_to_string(r.applies_to_actions, ','::text) AS applies_to_actions,
    ev.n AS evaluations_in_window,
    w.window_start,
    w.window_end,
    w.window_days,
        CASE
            WHEN (ev.n > 0) THEN 'enforcing'::text
            ELSE 'not_observed_in_window'::text
        END AS reality,
    ((r.status = 'active'::text) AND (r.enforcement = 'block'::text) AND (ev.n = 0)) AS block_without_evidence
   FROM ((public.ottoq_rules r
     CROSS JOIN win w)
     CROSS JOIN LATERAL ( SELECT count(*) AS n
           FROM public.ottoq_rule_evaluations e
          WHERE (e.rule_code = r.rule_code)) ev);
-- @@ view public.ottoq_rule_evaluation_effect
CREATE VIEW public.ottoq_rule_evaluation_effect AS
 SELECT re.evaluation_id,
    re.evaluated_at,
    re.rule_code,
    re.action_context,
    re.entity_type,
    re.entity_id,
    re.depot_id,
    re.sim_run_id,
    re.passed,
    re.severity,
    re.enforcement,
    re.reason,
    re.enforcement_taken AS recommendation,
        CASE
            WHEN (re.enforcement_taken <> 'blocked'::text) THEN re.enforcement_taken
            WHEN (pp.posture = ANY (ARRAY['enforced'::text, 'mixed'::text])) THEN 'refused'::text
            WHEN (pp.posture = 'advisory'::text) THEN 'recorded_only'::text
            ELSE 'unknown_posture'::text
        END AS effect,
    pp.posture AS probe_posture
   FROM (public.ottoq_rule_evaluations re
     LEFT JOIN public.ottoq_shield_probe_posture() pp(action_context, posture, callers, honouring, discarding, captures_no_branch) ON ((pp.action_context = re.action_context)));
-- @@ view public.ottoq_rule_failures
CREATE VIEW public.ottoq_rule_failures WITH (security_invoker=on) AS
 SELECT e.evaluation_id,
    e.evaluated_at,
    e.rule_code,
    r.title,
    r.severity AS rule_severity,
    e.severity AS evaluation_severity,
    e.reason,
    e.entity_type,
    e.entity_id,
    e.fleet_operator_id,
    e.depot_id,
    e.enforcement_taken,
    e.action_context,
    e.correlation_id
   FROM (public.ottoq_rule_evaluations e
     JOIN public.ottoq_rules r ON (((r.rule_code = e.rule_code) AND (r.version = e.rule_version))))
  WHERE ((e.passed = false) AND (e.evaluated_at > (now() - '7 days'::interval)))
  ORDER BY
        CASE e.severity
            WHEN 'safety_critical'::text THEN 1
            WHEN 'critical'::text THEN 2
            WHEN 'error'::text THEN 3
            WHEN 'warning'::text THEN 4
            ELSE 5
        END, e.evaluated_at DESC;
-- @@ view public.ottoq_rules_with_predictive_coverage
CREATE VIEW public.ottoq_rules_with_predictive_coverage WITH (security_invoker=on) AS
 SELECT r.rule_code,
    r.title AS rule_title,
    r.category AS rule_category,
    r.severity,
    count(prl.prediction_type) AS predictor_count,
    array_agg(prl.prediction_type) FILTER (WHERE prl.enabled) AS predicting_types
   FROM (public.ottoq_rules r
     LEFT JOIN public.ottoq_prediction_rule_links prl ON ((prl.rule_code = r.rule_code)))
  WHERE (r.status = 'active'::text)
  GROUP BY r.rule_code, r.title, r.category, r.severity
  ORDER BY (count(prl.prediction_type)) DESC, r.rule_code;
-- @@ view public.ottoq_run_reward_ledger
CREATE VIEW public.ottoq_run_reward_ledger AS
 WITH scorable AS (
         SELECT d.sim_run_id,
            d.captured_at,
            d.depot_id,
            d.scenario,
            d.policy,
            d.random_seed,
            d.engine_hash,
            d.config_hash,
            d.sim_min_per_tick,
            d.tick_count,
            d.dials,
            d.dials_set_count,
            d.metrics,
            d.rule_evaluations,
            d.rules_blocked,
            d.kpi,
            d.kpi_purged,
            d.returns_unserved,
            public.ottoq_run_unscorable_reason(d.*) AS unscorable_reason,
            public.ottoq_run_reward_terms(d.kpi) AS terms
           FROM public.ottoq_run_dial_ledger d
          WHERE (NOT (EXISTS ( SELECT 1
                   FROM public.ottoq_dial_pair_ledger pl
                  WHERE ((pl.run_a = d.sim_run_id) OR (pl.run_b = d.sim_run_id)))))
        ), cell AS (
         SELECT s.sim_run_id,
            s.captured_at,
            s.depot_id,
            s.scenario,
            s.policy,
            s.random_seed,
            s.engine_hash,
            s.config_hash,
            s.sim_min_per_tick,
            s.tick_count,
            s.dials,
            s.dials_set_count,
            s.metrics,
            s.rule_evaluations,
            s.rules_blocked,
            s.kpi,
            s.kpi_purged,
            s.returns_unserved,
            s.unscorable_reason,
            s.terms,
            t.k AS kpi_name,
            (t.v)::numeric AS kpi_value,
            min((t.v)::numeric) OVER cw AS cell_min,
            max((t.v)::numeric) OVER cw AS cell_max
           FROM (scorable s
             CROSS JOIN LATERAL jsonb_each_text(s.terms) t(k, v))
          WHERE ((s.unscorable_reason IS NULL) AND (t.v IS NOT NULL))
          WINDOW cw AS (PARTITION BY s.engine_hash, s.scenario, s.sim_min_per_tick, t.k)
        )
 SELECT c.sim_run_id,
    c.depot_id,
    c.engine_hash,
    c.scenario,
    c.sim_min_per_tick,
    c.random_seed,
    c.dials,
    c.rule_evaluations,
    c.rules_blocked,
    c.returns_unserved,
    w.weight_version,
    round(sum((((w.weights ->> c.kpi_name))::numeric *
        CASE
            WHEN (c.cell_max = c.cell_min) THEN 0.5
            ELSE ((c.kpi_value - c.cell_min) / (c.cell_max - c.cell_min))
        END)), 6) AS reward,
    count(*) AS kpis_weighed
   FROM (cell c
     JOIN public.ottoq_reward_weights w ON (w.is_active))
  WHERE (w.weights ? c.kpi_name)
  GROUP BY c.sim_run_id, c.depot_id, c.engine_hash, c.scenario, c.sim_min_per_tick, c.random_seed, c.dials, c.rule_evaluations, c.rules_blocked, c.returns_unserved, w.weight_version;
-- @@ view public.ottoq_safety_events
CREATE VIEW public.ottoq_safety_events AS
 SELECT event_id,
    event_seq,
    occurred_at,
    recorded_at,
    actor_type,
    actor_id,
    actor_metadata,
    event_type,
    event_category,
    severity,
    entity_type,
    entity_id,
    fleet_operator_id,
    depot_id,
    payload,
    previous_state,
    new_state,
    correlation_id,
    parent_event_id,
    causation_chain,
    related_task_id,
    related_schedule_id,
    related_decision_id,
    payload_hash,
    signature,
    signature_key_id,
    signature_algorithm,
    outcome,
    outcome_recorded_at,
    latency_ms,
    ingest_source,
    schema_version
   FROM public.ottoq_events
  WHERE (severity = ANY (ARRAY['critical'::text, 'safety_critical'::text]))
  ORDER BY event_seq DESC;
-- @@ view public.ottoq_shadow_disagreements
CREATE VIEW public.ottoq_shadow_disagreements WITH (security_invoker=on) AS
 SELECT prediction_type,
    model_version_id,
    count(*) AS shadow_calls,
    avg(shadow_disagreement) AS avg_disagreement,
    max(shadow_disagreement) AS max_disagreement
   FROM public.ottoq_inference_log
  WHERE ((is_shadow = true) AND (shadow_compared_to IS NOT NULL) AND (requested_at > (now() - '7 days'::interval)))
  GROUP BY prediction_type, model_version_id
  ORDER BY (avg(shadow_disagreement)) DESC NULLS LAST;
-- @@ view public.ottoq_site_power_ledger
CREATE VIEW public.ottoq_site_power_ledger AS
 SELECT depot_id,
    count(*) AS readings,
    count(*) FILTER (WHERE (severity_tier = 'excursion'::text)) AS excursions,
    count(*) FILTER (WHERE (severity_tier = 'high_water'::text)) AS high_water,
    count(*) FILTER (WHERE (severity_tier = 'armed'::text)) AS detector_armed_runs,
    count(*) FILTER (WHERE (severity_tier = 'ev_over_published_cap'::text)) AS ev_over_published_cap,
    round(max(ev_over_cap_kw), 1) AS worst_ev_over_cap_kw,
    round(avg(ev_over_cap_kw), 1) AS mean_ev_over_cap_kw,
    ((((count(*) FILTER (WHERE (severity_tier = 'excursion'::text)) + count(*) FILTER (WHERE (severity_tier = 'high_water'::text))) + count(*) FILTER (WHERE (severity_tier = 'armed'::text))) + count(*) FILTER (WHERE (severity_tier = 'ev_over_published_cap'::text))) = count(*)) AS tiers_sum_to_readings,
    count(DISTINCT sim_run_id) AS runs_seen,
    count(DISTINCT sim_run_id) FILTER (WHERE (severity_tier = 'excursion'::text)) AS runs_with_excursion,
    max(cap_kw) AS cap_kw,
    round(max(total_import_kw), 1) AS worst_total_kw,
    round(max(excess_kw) FILTER (WHERE (severity_tier = 'excursion'::text)), 1) AS worst_excess_kw,
    round(avg(total_import_kw) FILTER (WHERE (severity_tier = 'excursion'::text)), 1) AS mean_total_when_over,
    mode() WITHIN GROUP (ORDER BY dominant_component) FILTER (WHERE (severity_tier = 'excursion'::text)) AS largest_component,
    count(*) FILTER (WHERE ((severity_tier = 'excursion'::text) AND ((total_import_kw - COALESCE(bess_charging_kw, (0)::numeric)) <= cap_kw))) AS excursions_bess_deferral_clears,
    count(*) FILTER (WHERE ((severity_tier = 'excursion'::text) AND ((total_import_kw - COALESCE(bess_charging_kw, (0)::numeric)) > cap_kw))) AS excursions_needing_ev_action,
    round(max(bess_charging_kw) FILTER (WHERE (severity_tier = 'excursion'::text)), 1) AS worst_bess_charging_kw,
    round(max(ev_charging_kw) FILTER (WHERE (severity_tier = 'excursion'::text)), 1) AS worst_ev_charging_kw,
    count(*) FILTER (WHERE (source_kind = 'live'::text)) AS live_rows,
    count(*) FILTER (WHERE (source_kind = 'backfill'::text)) AS backfilled_rows,
    max(sim_clock) AS last_reading_sim_clock,
    max(detected_at) AS last_detected_at
   FROM public.ottoq_site_power_excursion_ledger l
  GROUP BY depot_id;
-- @@ view public.ottoq_site_power_plan_audit
CREATE VIEW public.ottoq_site_power_plan_audit AS
 SELECT depot_id,
    count(*) AS plans_over_contract,
    count(DISTINCT sim_run_id) AS runs_seen,
    max(service_max_kw) AS service_max_kw,
    round(max(demand_target_kw), 1) AS worst_demand_target_kw,
    round(max(target_excess_kw), 1) AS worst_excess_over_contract_kw,
    round(avg(target_excess_kw), 1) AS mean_excess_kw,
    round(max(contract_derived_target_kw), 1) AS contract_derived_target_kw,
    round(max(published_charge_cap_kw), 1) AS worst_published_cap_kw,
    count(*) FILTER (WHERE advisory) AS caps_marked_advisory,
    count(*) FILTER (WHERE reserve_shave_on) AS with_reserve_shave_on,
    (count(*) FILTER (WHERE advisory) = count(*)) AS all_advisory,
    (count(*) FILTER (WHERE reserve_shave_on) = count(*)) AS all_reserve_shave,
    count(*) FILTER (WHERE (source_kind = 'live'::text)) AS live_rows,
    count(*) FILTER (WHERE (source_kind = 'backfill'::text)) AS backfilled_rows,
    max(issued_at) AS last_issued_at
   FROM public.ottoq_site_power_plan_ledger l
  GROUP BY depot_id;
-- @@ view public.ottoq_sla_conformance_monthly
CREATE VIEW public.ottoq_sla_conformance_monthly WITH (security_invoker=on) AS
 SELECT fleet_operator_id,
    depot_id,
    (date_trunc('month'::text, (report_date)::timestamp with time zone))::date AS month_start,
    count(*) AS days_with_data,
    sum(total_visits) AS total_visits,
    sum(compliant_visits) AS compliant_visits,
    sum(non_compliant_visits) AS non_compliant_visits,
    round(avg(overall_compliance_pct), 2) AS avg_compliance_pct,
    round(avg(pct_meeting_min_soc), 2) AS avg_min_soc_pct,
    round(avg(pct_meeting_max_visit_time), 2) AS avg_visit_time_pct,
    round(avg(pct_meeting_required_services), 2) AS avg_services_pct,
    round(avg(pct_meeting_oem_gate), 2) AS avg_oem_gate_pct
   FROM public.ottoq_sla_conformance_daily
  GROUP BY fleet_operator_id, depot_id, (date_trunc('month'::text, (report_date)::timestamp with time zone));
-- @@ view public.ottoq_sla_conformance_weekly
CREATE VIEW public.ottoq_sla_conformance_weekly WITH (security_invoker=on) AS
 SELECT fleet_operator_id,
    depot_id,
    (date_trunc('week'::text, (report_date)::timestamp with time zone))::date AS week_start,
    count(*) AS days_with_data,
    sum(total_visits) AS total_visits,
    sum(compliant_visits) AS compliant_visits,
    sum(non_compliant_visits) AS non_compliant_visits,
    round(avg(overall_compliance_pct), 2) AS avg_compliance_pct,
    min(overall_compliance_pct) AS worst_day_pct,
    max(overall_compliance_pct) AS best_day_pct,
    min(composite_grade) AS worst_grade
   FROM public.ottoq_sla_conformance_daily
  GROUP BY fleet_operator_id, depot_id, (date_trunc('week'::text, (report_date)::timestamp with time zone));
-- @@ view public.ottoq_space_integrity_summary
CREATE VIEW public.ottoq_space_integrity_summary AS
 SELECT COALESCE(stall_type, '(unknown)'::text) AS stall_type,
    incident_kind,
    count(*) AS incidents,
    count(DISTINCT sim_run_id) AS runs,
    count(DISTINCT stall_id) AS stalls,
    count(DISTINCT expected_vehicle_id) AS vehicles,
    count(*) FILTER (WHERE had_open_charge_session) AS with_open_session_at_detection,
    count(*) FILTER (WHERE exposed_to_pointer_clear) AS untethered_at_detection,
    min(evaluated_at) AS first_seen,
    max(evaluated_at) AS last_seen
   FROM public.ottoq_space_integrity_ledger
  GROUP BY COALESCE(stall_type, '(unknown)'::text), incident_kind;
-- @@ view public.ottoq_swap_test_scoreboard
CREATE VIEW public.ottoq_swap_test_scoreboard AS
 SELECT scenario_code,
        CASE scenario_code
            WHEN 'normal_day'::text THEN 'calm'::text
            WHEN 'aggressive_fleet_turnover'::text THEN 'stress'::text
            ELSE scenario_code
        END AS condition,
    policy,
    count(*) AS n_seeds,
    round(avg(unsafe_deploys), 1) AS avg_unsafe_deploys,
    round(avg(safety_violations), 1) AS avg_breaches,
    round(avg(productive_deploys), 1) AS avg_productive_deploys,
    round(avg(fleet_ready_pct), 1) AS avg_readiness_pct
   FROM public.ottoq_ab_runs
  GROUP BY scenario_code, policy;
-- @@ view public.ottoq_throughput_cross_sweep_twins
CREATE VIEW public.ottoq_throughput_cross_sweep_twins WITH (security_invoker=true) AS
 WITH cur AS (
         SELECT a.arm_id,
            a.seed,
            a.ran_at,
            a.boot_md5,
            a.atoms,
            a.sweep_id,
            s.sweep_code,
            s.depot_id,
            s.scenario,
            s.sim_start,
            s.sim_min_per_tick,
            s.ticks,
            s.fleet_code,
            c.cell_code,
            c.seat,
            c.buildout_code,
            c.fixed_params
           FROM ((public.ottoq_throughput_sweep_arms a
             JOIN public.ottoq_throughput_sweep_cells c ON ((c.cell_id = a.cell_id)))
             JOIN public.ottoq_throughput_sweeps s ON ((s.sweep_id = a.sweep_id)))
          WHERE ((NOT a.replicate) AND a.complete AND (a.ran_at >= public.ottoq_dial_pair_floor()))
        )
 SELECT e.sweep_code AS earlier_sweep,
    e.cell_code AS earlier_cell,
    l.sweep_code AS later_sweep,
    l.cell_code AS later_cell,
    l.seed,
    e.arm_id AS earlier_arm,
    l.arm_id AS later_arm,
    e.ran_at AS earlier_ran_at,
    l.ran_at AS later_ran_at,
    ((l.boot_md5 = e.boot_md5) AND ((l.atoms - 'run'::text) = (e.atoms - 'run'::text))) AS identical,
    ( SELECT COALESCE(jsonb_agg(k.k ORDER BY k.k), '[]'::jsonb) AS "coalesce"
           FROM jsonb_object_keys((COALESCE((e.atoms - 'run'::text), '{}'::jsonb) || COALESCE((l.atoms - 'run'::text), '{}'::jsonb))) k(k)
          WHERE ((e.atoms -> k.k) IS DISTINCT FROM (l.atoms -> k.k))) AS moved
   FROM (cur e
     JOIN cur l ON (((l.sweep_id <> e.sweep_id) AND (l.ran_at > e.ran_at) AND (l.seed = e.seed) AND (l.depot_id = e.depot_id) AND (l.scenario = e.scenario) AND (l.sim_start = e.sim_start) AND (l.sim_min_per_tick = e.sim_min_per_tick) AND (l.ticks = e.ticks) AND (l.seat = e.seat) AND (l.buildout_code = e.buildout_code) AND (l.fixed_params = e.fixed_params) AND (NOT (l.fleet_code IS DISTINCT FROM e.fleet_code)))));
-- @@ view public.ottoq_throughput_frontier
CREATE VIEW public.ottoq_throughput_frontier WITH (security_invoker=true) AS
 WITH cur AS (
         SELECT a.arm_id,
            a.sweep_id,
            a.cell_id,
            a.seed,
            a.replicate,
            a.sim_run_id,
            a.engine_hash,
            a.dial_floor,
            a.ran_at,
            a.complete,
            a.ticks,
            a.wall_s,
            a.paid_shield,
            a.boot_md5,
            a.h_cal,
            a.atoms,
            a.buildout,
            a.restore,
            a.score_id,
            a.scorecard,
            a.arm_metrics,
            a.arm_error,
            c.cell_code,
            c.ord,
            c.seat,
            c.buildout_code,
            c.fixed_params,
            s.sweep_code,
            s.ticks AS sweep_ticks,
            s.sim_min_per_tick,
            s.seeds
           FROM ((public.ottoq_throughput_sweep_arms a
             JOIN public.ottoq_throughput_sweep_cells c ON ((c.cell_id = a.cell_id)))
             JOIN public.ottoq_throughput_sweeps s ON ((s.sweep_id = a.sweep_id)))
          WHERE ((NOT a.replicate) AND (a.ran_at >= public.ottoq_dial_pair_floor()))
        ), v AS (
         SELECT cur.arm_id,
            cur.sweep_id,
            cur.cell_id,
            cur.seed,
            cur.replicate,
            cur.sim_run_id,
            cur.engine_hash,
            cur.dial_floor,
            cur.ran_at,
            cur.complete,
            cur.ticks,
            cur.wall_s,
            cur.paid_shield,
            cur.boot_md5,
            cur.h_cal,
            cur.atoms,
            cur.buildout,
            cur.restore,
            cur.score_id,
            cur.scorecard,
            cur.arm_metrics,
            cur.arm_error,
            cur.cell_code,
            cur.ord,
            cur.seat,
            cur.buildout_code,
            cur.fixed_params,
            cur.sweep_code,
            cur.sweep_ticks,
            cur.sim_min_per_tick,
            cur.seeds,
            ((cur.scorecard #>> '{throughput,visits_served}'::text[]))::numeric AS served,
            ((cur.scorecard #>> '{throughput,vehicles_served}'::text[]))::numeric AS vehicles,
            ((cur.scorecard #>> '{throughput,peak_hour_served}'::text[]))::numeric AS peak_hour,
            ((cur.scorecard #>> '{timeliness,on_time_pct}'::text[]))::numeric AS on_time_pct,
            ((cur.scorecard #>> '{timeliness,door_p50_min}'::text[]))::numeric AS door_p50,
            (((cur.scorecard #>> '{rule9,left_below_target}'::text[]))::numeric + ((cur.scorecard #>> '{rule9,left_with_needed_work_open}'::text[]))::numeric) AS rule9_breaches,
            ((cur.scorecard #>> '{fast_chargers,turns_per_charger_per_day}'::text[]))::numeric AS turns,
            ((cur.scorecard #>> '{fast_chargers,busy_pct}'::text[]))::numeric AS busy_pct,
            ((cur.scorecard #>> '{fast_chargers,mean_kw}'::text[]))::numeric AS mean_kw,
            ((cur.scorecard ->> 'l2_sessions'::text))::numeric AS l2_sessions,
            ((cur.arm_metrics ->> 'deployed_car_hours'::text))::numeric AS deployed_h,
            ((cur.arm_metrics ->> 'unmet_demand_pct'::text))::numeric AS unmet_pct,
            ((cur.arm_metrics ->> 'site_cost_usd_per_day'::text))::numeric AS site_cost,
            ((cur.arm_metrics ->> 'peak_site_kw'::text))::numeric AS peak_kw
           FROM cur
        )
 SELECT sweep_code,
    cell_code,
    ord,
    buildout_code,
    seat,
    fixed_params,
    sim_min_per_tick,
    sweep_ticks,
    cardinality(min(seeds)) AS seeds_planned,
    count(*) AS arms,
    count(*) FILTER (WHERE (complete AND paid_shield)) AS valid_arms,
    count(*) FILTER (WHERE (arm_error IS NOT NULL)) AS failed_arms,
    jsonb_build_object('mean', round(avg(served) FILTER (WHERE (complete AND paid_shield)), 1), 'min', min(served) FILTER (WHERE (complete AND paid_shield)), 'max', max(served) FILTER (WHERE (complete AND paid_shield))) AS visits_served,
    jsonb_build_object('mean', round(avg(vehicles) FILTER (WHERE (complete AND paid_shield)), 1), 'min', min(vehicles) FILTER (WHERE (complete AND paid_shield)), 'max', max(vehicles) FILTER (WHERE (complete AND paid_shield))) AS vehicles_served,
    jsonb_build_object('mean', round(avg(peak_hour) FILTER (WHERE (complete AND paid_shield)), 1), 'max', max(peak_hour) FILTER (WHERE (complete AND paid_shield))) AS peak_hour_served,
    jsonb_build_object('mean', round(avg(on_time_pct) FILTER (WHERE (complete AND paid_shield)), 1), 'min', min(on_time_pct) FILTER (WHERE (complete AND paid_shield)), 'max', max(on_time_pct) FILTER (WHERE (complete AND paid_shield))) AS on_time_pct,
    jsonb_build_object('mean', round(avg(door_p50) FILTER (WHERE (complete AND paid_shield)), 0), 'min', min(door_p50) FILTER (WHERE (complete AND paid_shield)), 'max', max(door_p50) FILTER (WHERE (complete AND paid_shield))) AS door_p50_min,
    sum(rule9_breaches) FILTER (WHERE (complete AND paid_shield)) AS rule9_breaches,
    round(avg(turns) FILTER (WHERE (complete AND paid_shield)), 2) AS dcfc_turns_per_charger_per_day,
    round(avg(busy_pct) FILTER (WHERE (complete AND paid_shield)), 1) AS dcfc_busy_pct,
    round(avg(mean_kw) FILTER (WHERE (complete AND paid_shield)), 1) AS dcfc_mean_kw,
    round(avg(l2_sessions) FILTER (WHERE (complete AND paid_shield)), 1) AS l2_sessions,
    round(avg(deployed_h) FILTER (WHERE (complete AND paid_shield)), 1) AS deployed_car_hours,
    round(avg(unmet_pct) FILTER (WHERE (complete AND paid_shield)), 1) AS unmet_demand_pct,
    round(avg(site_cost) FILTER (WHERE (complete AND paid_shield)), 2) AS site_cost_usd_per_day,
    round(avg(peak_kw) FILTER (WHERE (complete AND paid_shield)), 1) AS peak_site_kw,
    round(avg(wall_s), 0) AS mean_wall_s
   FROM v
  GROUP BY sweep_code, cell_code, ord, buildout_code, seat, fixed_params, sim_min_per_tick, sweep_ticks;
-- @@ view public.ottoq_throughput_scores_latest
CREATE VIEW public.ottoq_throughput_scores_latest WITH (security_invoker=true) AS
 SELECT DISTINCT ON (sim_run_id) score_id,
    sim_run_id,
    scenario_code,
    random_seed,
    tick_count,
    policy,
    step_min,
    scorecard,
    scorecard_md5,
    origin,
    scored_at
   FROM public.ottoq_throughput_scores t
  ORDER BY sim_run_id, score_id DESC;
-- @@ view public.ottoq_throughput_sweep_contrasts
CREATE VIEW public.ottoq_throughput_sweep_contrasts WITH (security_invoker=true) AS
 WITH cur AS (
         SELECT a.arm_id,
            a.sweep_id,
            a.cell_id,
            a.seed,
            a.replicate,
            a.sim_run_id,
            a.engine_hash,
            a.dial_floor,
            a.ran_at,
            a.complete,
            a.ticks,
            a.wall_s,
            a.paid_shield,
            a.boot_md5,
            a.h_cal,
            a.atoms,
            a.buildout,
            a.restore,
            a.score_id,
            a.scorecard,
            a.arm_metrics,
            a.arm_error,
            c.cell_code,
            c.seat,
            c.buildout_code,
            c.fixed_params,
            c.control_cell_code,
            s.sweep_code
           FROM ((public.ottoq_throughput_sweep_arms a
             JOIN public.ottoq_throughput_sweep_cells c ON ((c.cell_id = a.cell_id)))
             JOIN public.ottoq_throughput_sweeps s ON ((s.sweep_id = a.sweep_id)))
          WHERE ((NOT a.replicate) AND (a.ran_at >= public.ottoq_dial_pair_floor()) AND a.complete AND a.paid_shield)
        )
 SELECT t.sweep_code,
    t.cell_code AS treatment_cell,
    k.cell_code AS control_cell,
    t.buildout_code,
    t.seat,
    t.fixed_params AS treatment_params,
    k.fixed_params AS control_params,
    t.seed,
    ((t.boot_md5 = k.boot_md5) AND (NOT (t.h_cal IS DISTINCT FROM k.h_cal))) AS world_identical,
    (((t.scorecard #>> '{throughput,visits_served}'::text[]))::numeric - ((k.scorecard #>> '{throughput,visits_served}'::text[]))::numeric) AS served_delta,
    (((t.scorecard #>> '{timeliness,on_time_pct}'::text[]))::numeric - ((k.scorecard #>> '{timeliness,on_time_pct}'::text[]))::numeric) AS on_time_pct_delta,
    (((t.scorecard #>> '{timeliness,door_p50_min}'::text[]))::numeric - ((k.scorecard #>> '{timeliness,door_p50_min}'::text[]))::numeric) AS door_p50_delta_min,
    (((t.arm_metrics ->> 'deployed_car_hours'::text))::numeric - ((k.arm_metrics ->> 'deployed_car_hours'::text))::numeric) AS deployed_car_hours_delta,
    (((t.arm_metrics ->> 'site_cost_usd_per_day'::text))::numeric - ((k.arm_metrics ->> 'site_cost_usd_per_day'::text))::numeric) AS site_cost_usd_delta,
    t.sim_run_id AS treatment_run,
    k.sim_run_id AS control_run
   FROM (cur t
     JOIN cur k ON (((k.sweep_id = t.sweep_id) AND (k.cell_code = t.control_cell_code) AND (k.seed = t.seed))))
  WHERE (t.control_cell_code IS NOT NULL);
-- @@ view public.ottoq_throughput_sweep_pairs
CREATE VIEW public.ottoq_throughput_sweep_pairs WITH (security_invoker=true) AS
 WITH cur AS (
         SELECT a.arm_id,
            a.sweep_id,
            a.cell_id,
            a.seed,
            a.replicate,
            a.sim_run_id,
            a.engine_hash,
            a.dial_floor,
            a.ran_at,
            a.complete,
            a.ticks,
            a.wall_s,
            a.paid_shield,
            a.boot_md5,
            a.h_cal,
            a.atoms,
            a.buildout,
            a.restore,
            a.score_id,
            a.scorecard,
            a.arm_metrics,
            a.arm_error,
            c.seat,
            c.buildout_code,
            c.fixed_params,
            s.sweep_code
           FROM ((public.ottoq_throughput_sweep_arms a
             JOIN public.ottoq_throughput_sweep_cells c ON ((c.cell_id = a.cell_id)))
             JOIN public.ottoq_throughput_sweeps s ON ((s.sweep_id = a.sweep_id)))
          WHERE ((NOT a.replicate) AND (a.ran_at >= public.ottoq_dial_pair_floor()) AND a.complete AND a.paid_shield)
        )
 SELECT q.sweep_code,
    q.buildout_code,
    q.fixed_params,
    q.seed,
    b.seat AS baseline,
    ((q.boot_md5 = b.boot_md5) AND (NOT (q.h_cal IS DISTINCT FROM b.h_cal))) AS world_identical,
    (((q.scorecard #>> '{throughput,visits_served}'::text[]))::numeric - ((b.scorecard #>> '{throughput,visits_served}'::text[]))::numeric) AS served_delta,
    (((q.scorecard #>> '{timeliness,on_time_pct}'::text[]))::numeric - ((b.scorecard #>> '{timeliness,on_time_pct}'::text[]))::numeric) AS on_time_pct_delta,
    (((q.scorecard #>> '{timeliness,door_p50_min}'::text[]))::numeric - ((b.scorecard #>> '{timeliness,door_p50_min}'::text[]))::numeric) AS door_p50_delta_min,
    (((q.arm_metrics ->> 'deployed_car_hours'::text))::numeric - ((b.arm_metrics ->> 'deployed_car_hours'::text))::numeric) AS deployed_car_hours_delta,
    (((q.arm_metrics ->> 'site_cost_usd_per_day'::text))::numeric - ((b.arm_metrics ->> 'site_cost_usd_per_day'::text))::numeric) AS site_cost_usd_delta,
    q.sim_run_id AS otto_q_run,
    b.sim_run_id AS baseline_run
   FROM (cur q
     JOIN cur b ON (((b.sweep_id = q.sweep_id) AND (b.seed = q.seed) AND (b.buildout_code = q.buildout_code) AND (b.fixed_params = q.fixed_params) AND (b.seat <> 'otto_q'::text))))
  WHERE (q.seat = 'otto_q'::text);
-- @@ view public.ottoq_throughput_sweep_replicates
CREATE VIEW public.ottoq_throughput_sweep_replicates WITH (security_invoker=true) AS
 SELECT s.sweep_code,
    c.cell_code,
    r.seed,
    p.arm_id AS primary_arm,
    r.arm_id AS replicate_arm,
    p.ran_at AS primary_ran_at,
    r.ran_at AS replicate_ran_at,
    ((r.boot_md5 = p.boot_md5) AND ((r.atoms - 'run'::text) = (p.atoms - 'run'::text))) AS identical,
    ( SELECT COALESCE(jsonb_agg(k.k ORDER BY k.k), '[]'::jsonb) AS "coalesce"
           FROM jsonb_object_keys((COALESCE((p.atoms - 'run'::text), '{}'::jsonb) || COALESCE((r.atoms - 'run'::text), '{}'::jsonb))) k(k)
          WHERE ((p.atoms -> k.k) IS DISTINCT FROM (r.atoms -> k.k))) AS moved
   FROM (((public.ottoq_throughput_sweep_arms r
     JOIN public.ottoq_throughput_sweep_arms p ON (((p.cell_id = r.cell_id) AND (p.seed = r.seed) AND (NOT p.replicate) AND p.complete AND (p.ran_at >= public.ottoq_dial_pair_floor()))))
     JOIN public.ottoq_throughput_sweep_cells c ON ((c.cell_id = r.cell_id)))
     JOIN public.ottoq_throughput_sweeps s ON ((s.sweep_id = r.sweep_id)))
  WHERE (r.replicate AND r.complete AND (r.ran_at >= public.ottoq_dial_pair_floor()));
-- @@ view public.ottoq_twin_playback_timeline
CREATE VIEW public.ottoq_twin_playback_timeline WITH (security_invoker=true) AS
 SELECT l.sim_run_id,
    'v1'::text AS playback_schema_version,
    l.vehicle_id AS entity_id,
    'vehicle'::text AS entity_kind,
        CASE
            WHEN oc.is_movement THEN 'move'::text
            ELSE COALESCE(oc.operation_code, l.leg_type)
        END AS event_type,
    COALESCE(l.actual_start_sim, l.planned_start_sim) AS t_start,
    COALESCE(l.actual_end_sim, l.planned_end_sim) AS t_end,
        CASE
            WHEN (sf.id IS NOT NULL) THEN jsonb_build_object('x', sf.relative_x, 'y', sf.relative_y, 'heading_deg', sf.heading_degrees, 'stall_code', sf.stall_code)
            ELSE NULL::jsonb
        END AS from_pose,
        CASE
            WHEN (st.id IS NOT NULL) THEN jsonb_build_object('x', st.relative_x, 'y', st.relative_y, 'heading_deg', st.heading_degrees, 'stall_code', st.stall_code)
            ELSE NULL::jsonb
        END AS to_pose,
    l.leg_id,
    l.status AS leg_status,
    l.seq
   FROM (((public.ottoq_itinerary_legs l
     LEFT JOIN public.ottoq_operation_catalog oc ON (((oc.leg_type = l.leg_type) AND (oc.pack_id = 'robotaxi'::text))))
     LEFT JOIN public.stalls sf ON ((sf.id = l.from_stall_id)))
     LEFT JOIN public.stalls st ON ((st.id = l.to_stall_id)));
-- @@ view public.ottoq_vehicle_needs_card
CREATE VIEW public.ottoq_vehicle_needs_card AS
 WITH run AS (
         SELECT DISTINCT ON (r_1.depot_id) r_1.depot_id,
            r_1.sim_run_id,
            COALESCE(r_1.sim_clock_current, r_1.sim_clock_start, now()) AS sim_clock
           FROM public.ottoq_sim_runs r_1
          ORDER BY r_1.depot_id, (r_1.status = 'running'::text) DESC, r_1.started_at DESC
        ), base AS (
         SELECT p.vehicle_id,
            p.profile_version,
            p.drawn_for_run,
            p.drawn_seed,
            p.drawn_at,
            p.drawn_at_sim_clock,
            p.battery_soh_pct,
            p.battery_chemistry,
            p.charge_accept_kw,
            p.pack_temp_c,
            p.dcfc_safe,
            p.dcfc_block_reason,
            p.cell_balance_due_at,
            p.min_ready_soc_pct,
            p.exterior_soil_level,
            p.cabin_condition,
            p.last_wash_at,
            p.last_deep_clean_at,
            p.wash_interval_h,
            p.deep_clean_interval_h,
            p.calib_interval_h,
            p.calib_interval_km,
            p.last_calibration_at,
            p.sensor_health_pct,
            p.software_version,
            p.sw_target_version,
            p.sw_update_size_mb,
            p.odometer_km,
            p.pm_interval_km,
            p.km_at_last_pm,
            p.last_pm_at,
            p.open_fault_codes,
            p.worst_fault_severity,
            p.tire_tread_mm,
            p.tire_rotation_due_km,
            p.brake_wear_pct,
            p.next_deploy_at,
            p.priority_class,
            p.assigned_shift,
            p.item_retrieval_pending,
            p.item_reported_at,
            p.item_description,
            p.updated_at,
            v.av_api_vehicle_id AS av_id,
            v.display_name,
            v.home_depot_id AS depot_id,
            v.current_state,
            v.current_soc,
            v.target_soc,
            v.battery_capacity_kwh,
            v.inlet_max_kw,
            r_1.sim_run_id AS run_id,
            COALESCE(r_1.sim_clock, now()) AS sim_clock
           FROM ((public.vehicle_need_profile p
             JOIN public.vehicles v ON ((v.id = p.vehicle_id)))
             LEFT JOIN run r_1 ON ((r_1.depot_id = v.home_depot_id)))
        ), owed AS (
         SELECT b.vehicle_id,
            COALESCE(array_agg(DISTINCT (a.value ->> 'svc'::text)), '{}'::text[]) AS owed_bay_svcs,
            COALESCE(sum(
                CASE
                    WHEN ((a.value ->> 'est_min'::text) ~ '^[0-9]+(\.[0-9]+)?$'::text) THEN ((a.value ->> 'est_min'::text))::numeric
                    ELSE (0)::numeric
                END), (0)::numeric) AS owed_bay_min
           FROM (((base b
             JOIN public.ottoq_visit_needs n ON (((n.vehicle_id = b.vehicle_id) AND (n.status = ANY (ARRAY['open'::text, 'in_progress'::text])) AND ((n.sim_run_id = b.run_id) OR (n.sim_run_id IS NULL) OR (b.run_id IS NULL)))))
             CROSS JOIN LATERAL jsonb_array_elements(COALESCE(n.atoms, '[]'::jsonb)) a(value))
             JOIN public.service_cadence_policy p ON (((p.svc = (a.value ->> 'svc'::text)) AND p.is_active AND (p.lane = ANY (ARRAY['wash_bay'::text, 'detail'::text, 'service_bay'::text])))))
          WHERE ((lower(COALESCE((a.value ->> 'status'::text), 'pending'::text)) <> ALL (ARRAY['done'::text, 'cancelled'::text, 'skipped'::text])) AND COALESCE(((a.value ->> 'must_do'::text))::boolean, false) AND ((a.value ? 'reopened_at'::text) OR (a.value ? 'cut_short_at'::text) OR (COALESCE(n.meta, '{}'::jsonb) ? 'reopen'::text)))
          GROUP BY b.vehicle_id
        ), calc AS (
         SELECT b.vehicle_id,
            b.profile_version,
            b.drawn_for_run,
            b.drawn_seed,
            b.drawn_at,
            b.drawn_at_sim_clock,
            b.battery_soh_pct,
            b.battery_chemistry,
            b.charge_accept_kw,
            b.pack_temp_c,
            b.dcfc_safe,
            b.dcfc_block_reason,
            b.cell_balance_due_at,
            b.min_ready_soc_pct,
            b.exterior_soil_level,
            b.cabin_condition,
            b.last_wash_at,
            b.last_deep_clean_at,
            b.wash_interval_h,
            b.deep_clean_interval_h,
            b.calib_interval_h,
            b.calib_interval_km,
            b.last_calibration_at,
            b.sensor_health_pct,
            b.software_version,
            b.sw_target_version,
            b.sw_update_size_mb,
            b.odometer_km,
            b.pm_interval_km,
            b.km_at_last_pm,
            b.last_pm_at,
            b.open_fault_codes,
            b.worst_fault_severity,
            b.tire_tread_mm,
            b.tire_rotation_due_km,
            b.brake_wear_pct,
            b.next_deploy_at,
            b.priority_class,
            b.assigned_shift,
            b.item_retrieval_pending,
            b.item_reported_at,
            b.item_description,
            b.updated_at,
            b.av_id,
            b.display_name,
            b.depot_id,
            b.current_state,
            b.current_soc,
            b.target_soc,
            b.battery_capacity_kwh,
            b.inlet_max_kw,
            b.run_id,
            b.sim_clock,
                CASE
                    WHEN (b.next_deploy_at IS NULL) THEN NULL::integer
                    ELSE (round((EXTRACT(epoch FROM (b.next_deploy_at - b.sim_clock)) / 60.0)))::integer
                END AS minutes_to_deploy,
            GREATEST((0)::numeric, (COALESCE(b.min_ready_soc_pct, (80)::numeric) - (COALESCE(b.current_soc, 0))::numeric)) AS soc_deficit_to_sla,
            GREATEST(0, (COALESCE(b.target_soc, 90) - COALESCE(b.current_soc, 0))) AS soc_deficit_to_target,
            (round(COALESCE(public.ottoq_estimate_charge_minutes((COALESCE(b.current_soc, 50))::numeric, (COALESCE(b.target_soc, 90))::numeric, (150)::numeric, COALESCE(b.inlet_max_kw, (150)::numeric), COALESCE(b.battery_capacity_kwh, (75)::numeric), COALESCE(b.pack_temp_c, (25)::numeric), COALESCE(b.battery_soh_pct, (95)::numeric), 1.0), (0)::numeric)))::integer AS est_charge_min,
            round(((EXTRACT(epoch FROM (b.sim_clock - b.last_wash_at)) / 3600.0) / NULLIF(b.wash_interval_h, (0)::numeric)), 3) AS wash_ratio,
            round(((EXTRACT(epoch FROM (b.sim_clock - b.last_deep_clean_at)) / 3600.0) / NULLIF(b.deep_clean_interval_h, (0)::numeric)), 3) AS deep_clean_ratio,
            round(((EXTRACT(epoch FROM (b.sim_clock - b.last_calibration_at)) / 3600.0) / NULLIF(b.calib_interval_h, (0)::numeric)), 3) AS calib_ratio,
            round((GREATEST((0)::numeric, (b.odometer_km - COALESCE(b.km_at_last_pm, (0)::numeric))) / NULLIF(b.pm_interval_km, (0)::numeric)), 3) AS pm_ratio,
            (b.last_wash_at + make_interval(hours => (COALESCE(b.wash_interval_h, (72)::numeric))::integer)) AS wash_due_at,
            (b.last_deep_clean_at + make_interval(hours => (COALESCE(b.deep_clean_interval_h, (336)::numeric))::integer)) AS deep_clean_due_at,
            (b.last_calibration_at + make_interval(hours => (COALESCE(b.calib_interval_h, (250)::numeric))::integer)) AS calib_due_at,
            GREATEST((0)::numeric, (b.odometer_km - COALESCE(b.km_at_last_pm, (0)::numeric))) AS km_since_pm,
            (b.software_version IS DISTINCT FROM b.sw_target_version) AS sw_behind,
            ( SELECT COALESCE(sum(((a.value ->> 'est_min'::text))::numeric), (0)::numeric) AS "coalesce"
                   FROM public.ottoq_visit_needs n,
                    LATERAL jsonb_array_elements(n.atoms) a(value)
                  WHERE ((n.vehicle_id = b.vehicle_id) AND (n.status = 'open'::text))) AS open_work_min,
            ( SELECT COALESCE(sum(((a.value ->> 'est_min'::text))::numeric), (0)::numeric) AS "coalesce"
                   FROM public.ottoq_visit_needs n,
                    LATERAL jsonb_array_elements(n.atoms) a(value)
                  WHERE ((n.vehicle_id = b.vehicle_id) AND (n.status = 'open'::text) AND COALESCE(((a.value ->> 'must_do'::text))::boolean, false))) AS open_must_do_min
           FROM base b
        ), grade AS (
         SELECT c.vehicle_id,
            c.profile_version,
            c.drawn_for_run,
            c.drawn_seed,
            c.drawn_at,
            c.drawn_at_sim_clock,
            c.battery_soh_pct,
            c.battery_chemistry,
            c.charge_accept_kw,
            c.pack_temp_c,
            c.dcfc_safe,
            c.dcfc_block_reason,
            c.cell_balance_due_at,
            c.min_ready_soc_pct,
            c.exterior_soil_level,
            c.cabin_condition,
            c.last_wash_at,
            c.last_deep_clean_at,
            c.wash_interval_h,
            c.deep_clean_interval_h,
            c.calib_interval_h,
            c.calib_interval_km,
            c.last_calibration_at,
            c.sensor_health_pct,
            c.software_version,
            c.sw_target_version,
            c.sw_update_size_mb,
            c.odometer_km,
            c.pm_interval_km,
            c.km_at_last_pm,
            c.last_pm_at,
            c.open_fault_codes,
            c.worst_fault_severity,
            c.tire_tread_mm,
            c.tire_rotation_due_km,
            c.brake_wear_pct,
            c.next_deploy_at,
            c.priority_class,
            c.assigned_shift,
            c.item_retrieval_pending,
            c.item_reported_at,
            c.item_description,
            c.updated_at,
            c.av_id,
            c.display_name,
            c.depot_id,
            c.current_state,
            c.current_soc,
            c.target_soc,
            c.battery_capacity_kwh,
            c.inlet_max_kw,
            c.run_id,
            c.sim_clock,
            c.minutes_to_deploy,
            c.soc_deficit_to_sla,
            c.soc_deficit_to_target,
            c.est_charge_min,
            c.wash_ratio,
            c.deep_clean_ratio,
            c.calib_ratio,
            c.pm_ratio,
            c.wash_due_at,
            c.deep_clean_due_at,
            c.calib_due_at,
            c.km_since_pm,
            c.sw_behind,
            c.open_work_min,
            c.open_must_do_min,
                CASE
                    WHEN ((c.soc_deficit_to_sla > (0)::numeric) AND (COALESCE(c.minutes_to_deploy, 999999) < c.est_charge_min)) THEN 'critical'::text
                    WHEN (c.soc_deficit_to_sla > (0)::numeric) THEN 'due'::text
                    WHEN (c.soc_deficit_to_target > 5) THEN 'due_soon'::text
                    ELSE 'ok'::text
                END AS energy_urgency,
            public.ottoq_urgency_max(public.ottoq_service_urgency('exterior_wash'::text, c.wash_ratio),
                CASE
                    WHEN (c.exterior_soil_level >= 0.85) THEN 'overdue'::text
                    WHEN (c.exterior_soil_level >= 0.65) THEN 'due'::text
                    WHEN (c.exterior_soil_level >= 0.45) THEN 'due_soon'::text
                    ELSE 'ok'::text
                END) AS wash_urgency,
            public.ottoq_urgency_max(public.ottoq_service_urgency('interior_deep_clean'::text, c.deep_clean_ratio),
                CASE
                    WHEN (c.cabin_condition = 'biohazard'::text) THEN 'critical'::text
                    WHEN (c.cabin_condition = 'soiled'::text) THEN 'overdue'::text
                    WHEN (c.cabin_condition = 'light_litter'::text) THEN 'due_soon'::text
                    ELSE 'ok'::text
                END) AS cabin_urgency,
            public.ottoq_urgency_max(public.ottoq_service_urgency('sensor_calibration'::text, c.calib_ratio),
                CASE
                    WHEN (c.sensor_health_pct < (89)::numeric) THEN 'due'::text
                    WHEN (c.sensor_health_pct < (91)::numeric) THEN 'due_soon'::text
                    ELSE 'ok'::text
                END) AS calib_urgency,
            public.ottoq_service_urgency('mechanical_pm'::text, c.pm_ratio) AS pm_urgency,
            public.ottoq_service_urgency('fault_repair'::text,
                CASE
                    WHEN (c.worst_fault_severity = 1) THEN 2.00
                    WHEN (c.worst_fault_severity <= 3) THEN 1.30
                    WHEN (c.worst_fault_severity <= 5) THEN 0.80
                    ELSE 0.00
                END) AS fault_urgency,
                CASE
                    WHEN (c.tire_tread_mm < 2.7) THEN 'critical'::text
                    WHEN (c.tire_tread_mm < 3.0) THEN 'due'::text
                    WHEN (c.tire_tread_mm < 4.0) THEN 'due_soon'::text
                    ELSE 'ok'::text
                END AS tire_urgency,
                CASE
                    WHEN (c.brake_wear_pct >= (82)::numeric) THEN 'critical'::text
                    WHEN (c.brake_wear_pct >= (80)::numeric) THEN 'due'::text
                    WHEN (c.brake_wear_pct >= (65)::numeric) THEN 'due_soon'::text
                    ELSE 'ok'::text
                END AS brake_urgency,
            public.ottoq_service_urgency('software_update'::text,
                CASE
                    WHEN (NOT (c.software_version IS DISTINCT FROM c.sw_target_version)) THEN 0.00
                    WHEN (c.software_version = '2026.26.2'::text) THEN 1.30
                    ELSE 0.80
                END) AS software_urgency,
                CASE
                    WHEN c.item_retrieval_pending THEN 'due'::text
                    ELSE 'ok'::text
                END AS item_urgency
           FROM calc c
        ), mech AS (
         SELECT g.vehicle_id,
            g.profile_version,
            g.drawn_for_run,
            g.drawn_seed,
            g.drawn_at,
            g.drawn_at_sim_clock,
            g.battery_soh_pct,
            g.battery_chemistry,
            g.charge_accept_kw,
            g.pack_temp_c,
            g.dcfc_safe,
            g.dcfc_block_reason,
            g.cell_balance_due_at,
            g.min_ready_soc_pct,
            g.exterior_soil_level,
            g.cabin_condition,
            g.last_wash_at,
            g.last_deep_clean_at,
            g.wash_interval_h,
            g.deep_clean_interval_h,
            g.calib_interval_h,
            g.calib_interval_km,
            g.last_calibration_at,
            g.sensor_health_pct,
            g.software_version,
            g.sw_target_version,
            g.sw_update_size_mb,
            g.odometer_km,
            g.pm_interval_km,
            g.km_at_last_pm,
            g.last_pm_at,
            g.open_fault_codes,
            g.worst_fault_severity,
            g.tire_tread_mm,
            g.tire_rotation_due_km,
            g.brake_wear_pct,
            g.next_deploy_at,
            g.priority_class,
            g.assigned_shift,
            g.item_retrieval_pending,
            g.item_reported_at,
            g.item_description,
            g.updated_at,
            g.av_id,
            g.display_name,
            g.depot_id,
            g.current_state,
            g.current_soc,
            g.target_soc,
            g.battery_capacity_kwh,
            g.inlet_max_kw,
            g.run_id,
            g.sim_clock,
            g.minutes_to_deploy,
            g.soc_deficit_to_sla,
            g.soc_deficit_to_target,
            g.est_charge_min,
            g.wash_ratio,
            g.deep_clean_ratio,
            g.calib_ratio,
            g.pm_ratio,
            g.wash_due_at,
            g.deep_clean_due_at,
            g.calib_due_at,
            g.km_since_pm,
            g.sw_behind,
            g.open_work_min,
            g.open_must_do_min,
            g.energy_urgency,
            g.wash_urgency,
            g.cabin_urgency,
            g.calib_urgency,
            g.pm_urgency,
            g.fault_urgency,
            g.tire_urgency,
            g.brake_urgency,
            g.software_urgency,
            g.item_urgency,
            public.ottoq_urgency_max(g.pm_urgency, public.ottoq_urgency_max(g.tire_urgency, g.brake_urgency)) AS mech_urgency
           FROM grade g
        ), cand AS (
         SELECT m.vehicle_id,
            x.svc,
            x.urg,
            public.ottoq_service_must_do(x.svc, x.urg) AS is_must_do
           FROM (mech m
             CROSS JOIN LATERAL ( VALUES ('charge'::text,m.energy_urgency,(m.energy_urgency <> 'ok'::text)), ('exterior_wash'::text,m.wash_urgency,true), ('interior_deep_clean'::text,m.cabin_urgency,true), ('sensor_calibration'::text,m.calib_urgency,true), ('mechanical_pm'::text,m.mech_urgency,true), ('fault_repair'::text,m.fault_urgency,(COALESCE((m.worst_fault_severity)::integer, 99) <= 3)), ('software_update'::text,m.software_urgency,m.sw_behind), ('item_retrieval'::text,m.item_urgency,m.item_retrieval_pending)) x(svc, urg, applies))
          WHERE x.applies
        ), agg AS (
         SELECT cand.vehicle_id,
            COALESCE(array_agg(DISTINCT cand.svc) FILTER (WHERE cand.is_must_do), '{}'::text[]) AS must_do_now,
            COALESCE(array_agg(DISTINCT cand.svc) FILTER (WHERE ((NOT cand.is_must_do) AND (public.ottoq_urgency_rank(cand.urg) >= 2))), '{}'::text[]) AS deferrable_now
           FROM cand
          GROUP BY cand.vehicle_id
        ), roll AS (
         SELECT m.vehicle_id,
            m.profile_version,
            m.drawn_for_run,
            m.drawn_seed,
            m.drawn_at,
            m.drawn_at_sim_clock,
            m.battery_soh_pct,
            m.battery_chemistry,
            m.charge_accept_kw,
            m.pack_temp_c,
            m.dcfc_safe,
            m.dcfc_block_reason,
            m.cell_balance_due_at,
            m.min_ready_soc_pct,
            m.exterior_soil_level,
            m.cabin_condition,
            m.last_wash_at,
            m.last_deep_clean_at,
            m.wash_interval_h,
            m.deep_clean_interval_h,
            m.calib_interval_h,
            m.calib_interval_km,
            m.last_calibration_at,
            m.sensor_health_pct,
            m.software_version,
            m.sw_target_version,
            m.sw_update_size_mb,
            m.odometer_km,
            m.pm_interval_km,
            m.km_at_last_pm,
            m.last_pm_at,
            m.open_fault_codes,
            m.worst_fault_severity,
            m.tire_tread_mm,
            m.tire_rotation_due_km,
            m.brake_wear_pct,
            m.next_deploy_at,
            m.priority_class,
            m.assigned_shift,
            m.item_retrieval_pending,
            m.item_reported_at,
            m.item_description,
            m.updated_at,
            m.av_id,
            m.display_name,
            m.depot_id,
            m.current_state,
            m.current_soc,
            m.target_soc,
            m.battery_capacity_kwh,
            m.inlet_max_kw,
            m.run_id,
            m.sim_clock,
            m.minutes_to_deploy,
            m.soc_deficit_to_sla,
            m.soc_deficit_to_target,
            m.est_charge_min,
            m.wash_ratio,
            m.deep_clean_ratio,
            m.calib_ratio,
            m.pm_ratio,
            m.wash_due_at,
            m.deep_clean_due_at,
            m.calib_due_at,
            m.km_since_pm,
            m.sw_behind,
            m.open_work_min,
            m.open_must_do_min,
            m.energy_urgency,
            m.wash_urgency,
            m.cabin_urgency,
            m.calib_urgency,
            m.pm_urgency,
            m.fault_urgency,
            m.tire_urgency,
            m.brake_urgency,
            m.software_urgency,
            m.item_urgency,
            m.mech_urgency,
            COALESCE(a.must_do_now, '{}'::text[]) AS must_do_now_raw,
            COALESCE(a.deferrable_now, '{}'::text[]) AS deferrable_now_raw,
            COALESCE(o.owed_bay_svcs, '{}'::text[]) AS owed_bay_svcs_raw,
            COALESCE(o.owed_bay_min, (0)::numeric) AS owed_bay_min_raw,
            ( SELECT COALESCE(array_agg(DISTINCT u.x), '{}'::text[]) AS "coalesce"
                   FROM unnest((COALESCE(a.must_do_now, '{}'::text[]) || COALESCE(o.owed_bay_svcs, '{}'::text[]))) u(x)) AS must_do_all_raw
           FROM ((mech m
             LEFT JOIN agg a ON ((a.vehicle_id = m.vehicle_id)))
             LEFT JOIN owed o ON ((o.vehicle_id = m.vehicle_id)))
        )
 SELECT vehicle_id,
    av_id,
    display_name,
    depot_id,
    run_id,
    sim_clock,
    current_state,
    drawn_seed,
    profile_version,
    current_soc AS soc_pct,
    target_soc AS target_soc_pct,
    min_ready_soc_pct,
    soc_deficit_to_sla,
    soc_deficit_to_target,
    est_charge_min,
    battery_soh_pct,
    battery_chemistry,
    charge_accept_kw,
    pack_temp_c,
    dcfc_safe,
    dcfc_block_reason,
    cell_balance_due_at,
    energy_urgency,
    exterior_soil_level,
    cabin_condition,
    last_wash_at,
    wash_due_at,
    wash_ratio,
    wash_urgency,
    last_deep_clean_at,
    deep_clean_due_at,
    deep_clean_ratio,
    cabin_urgency,
    last_calibration_at,
    calib_due_at,
    calib_ratio,
    calib_urgency,
    sensor_health_pct,
    software_version,
    sw_target_version,
    sw_behind,
    sw_update_size_mb,
    software_urgency,
    odometer_km,
    km_since_pm,
    pm_interval_km,
    pm_ratio,
    pm_urgency,
    open_fault_codes,
    worst_fault_severity,
    fault_urgency,
    tire_tread_mm,
    tire_urgency,
    brake_wear_pct,
    brake_urgency,
    next_deploy_at,
    minutes_to_deploy,
    priority_class,
    assigned_shift,
    item_retrieval_pending,
    item_description,
    item_reported_at,
    item_urgency,
    must_do_all_raw AS must_do_now,
    ( SELECT COALESCE(array_agg(DISTINCT d.x), '{}'::text[]) AS "coalesce"
           FROM unnest(r.deferrable_now_raw) d(x)
          WHERE (NOT (d.x = ANY (r.must_do_all_raw)))) AS deferrable_now,
    open_work_min,
    open_must_do_min,
        CASE
            WHEN (minutes_to_deploy IS NULL) THEN true
            ELSE ((minutes_to_deploy)::numeric >= GREATEST((est_charge_min)::numeric, open_must_do_min))
        END AS fits_window,
    ( SELECT public.ottoq_urgency_max(public.ottoq_urgency_max(public.ottoq_urgency_max(public.ottoq_urgency_max(r.energy_urgency, r.wash_urgency), public.ottoq_urgency_max(r.cabin_urgency, r.calib_urgency)), public.ottoq_urgency_max(r.mech_urgency, r.fault_urgency)), public.ottoq_urgency_max(
                CASE
                    WHEN (r.priority_class = 'critical'::text) THEN 'critical'::text
                    ELSE 'ok'::text
                END, public.ottoq_urgency_max(r.software_urgency, r.item_urgency))) AS ottoq_urgency_max) AS overall_urgency,
    ( SELECT array_agg(DISTINCT public.ottoq_need_to_leg_type(x.x, r.dcfc_safe)) AS array_agg
           FROM unnest(r.must_do_all_raw) x(x)) AS must_do_legs,
    jsonb_build_object('vehicle_id', vehicle_id, 'av_id', av_id, 'as_of', sim_clock, 'commitment', jsonb_build_object('next_deploy_at', next_deploy_at, 'minutes_to_deploy', minutes_to_deploy, 'priority_class', priority_class, 'assigned_shift', assigned_shift), 'energy', jsonb_build_object('soc_pct', current_soc, 'target_soc_pct', target_soc, 'min_ready_soc_pct', min_ready_soc_pct, 'est_charge_min', est_charge_min, 'battery_soh_pct', battery_soh_pct, 'charge_accept_kw', charge_accept_kw, 'pack_temp_c', pack_temp_c, 'dcfc_safe', dcfc_safe, 'dcfc_block_reason', dcfc_block_reason, 'urgency', energy_urgency), 'cleanliness', jsonb_build_object('exterior_soil_level', exterior_soil_level, 'cabin_condition', cabin_condition, 'wash_due_at', wash_due_at, 'wash_ratio', wash_ratio, 'wash_urgency', wash_urgency, 'deep_clean_due_at', deep_clean_due_at, 'cabin_urgency', cabin_urgency), 'sensor_software', jsonb_build_object('calib_due_at', calib_due_at, 'calib_ratio', calib_ratio, 'calib_urgency', calib_urgency, 'sensor_health_pct', sensor_health_pct, 'software_version', software_version, 'sw_target_version', sw_target_version, 'sw_behind', sw_behind, 'software_urgency', software_urgency), 'mechanical', jsonb_build_object('odometer_km', odometer_km, 'km_since_pm', km_since_pm, 'pm_ratio', pm_ratio, 'pm_urgency', pm_urgency, 'open_fault_codes', to_jsonb(open_fault_codes), 'worst_fault_severity', worst_fault_severity, 'fault_urgency', fault_urgency, 'tire_tread_mm', tire_tread_mm, 'tire_urgency', tire_urgency, 'brake_wear_pct', brake_wear_pct, 'brake_urgency', brake_urgency), 'items', jsonb_build_object('pending', item_retrieval_pending, 'description', item_description, 'reported_at', item_reported_at), 'must_do_now', to_jsonb(must_do_all_raw), 'deferrable_now', to_jsonb(( SELECT COALESCE(array_agg(DISTINCT d2.x), '{}'::text[]) AS "coalesce"
           FROM unnest(r.deferrable_now_raw) d2(x)
          WHERE (NOT (d2.x = ANY (r.must_do_all_raw))))), 'must_do_legs', to_jsonb(( SELECT array_agg(DISTINCT public.ottoq_need_to_leg_type(x.x, r.dcfc_safe)) AS array_agg
           FROM unnest(r.must_do_all_raw) x(x))), 'open_work_min', open_work_min, 'open_must_do_min', open_must_do_min, 'owed_bay_svcs', to_jsonb(owed_bay_svcs_raw), 'owed_bay_min', owed_bay_min_raw, 'rebook_owed', (COALESCE(array_length(owed_bay_svcs_raw, 1), 0) > 0)) AS need_statement,
    owed_bay_svcs_raw AS owed_bay_svcs,
    owed_bay_min_raw AS owed_bay_min,
    (COALESCE(array_length(owed_bay_svcs_raw, 1), 0) > 0) AS rebook_owed
   FROM roll r;
-- @@ view public.service_locations
CREATE VIEW public.service_locations WITH (security_invoker=true) AS
 SELECT s.id AS service_point_id,
    s.depot_id AS site_id,
    d.name AS site_name,
    s.stall_code AS point_code,
    (s.stall_type)::text AS point_kind,
    s.status AS point_status,
    s.covered,
    s.zone,
    COALESCE(jsonb_agg(DISTINCT jsonb_build_object('asset_class', c.asset_class_code, 'operation', c.operation_code)) FILTER (WHERE (c.stall_id IS NOT NULL)), '[]'::jsonb) AS capabilities
   FROM ((public.stalls s
     JOIN public.depots d ON ((d.id = s.depot_id)))
     LEFT JOIN public.ottoq_service_point_capabilities c ON (((c.stall_id = s.id) AND c.active)))
  GROUP BY s.id, s.depot_id, d.name, s.stall_code, s.stall_type, s.status, s.covered, s.zone;
-- @@ view public.service_profiles
CREATE VIEW public.service_profiles WITH (security_invoker=true) AS
 SELECT 'site_power'::text AS resource_kind,
    p.depot_id AS site_id,
    NULL::uuid AS service_point_id,
    p.sim_run_id,
    COALESCE(((p.detail ->> 'published_at'::text))::timestamp with time zone, p.created_at) AS published_at,
    p.plan_start_clock AS window_start,
    (p.plan_start_clock + make_interval(mins => ((p.tick_minutes * (p.horizon_steps)::numeric))::integer)) AS window_end,
    jsonb_build_object('tick_minutes', p.tick_minutes, 'rate_unit', 'kW', 'start_period_s', ( SELECT jsonb_agg((((((i.i - 1))::numeric * p.tick_minutes) * (60)::numeric))::integer ORDER BY i.i) AS jsonb_agg
           FROM generate_series(1, p.horizon_steps) i(i)), 'bess_setpoint_kw', to_jsonb(p.bess_setpoint_kw), 'grid_import_kw', to_jsonb(p.grid_import_kw), 'forecast_load_kw', to_jsonb(p.forecast_load_kw), 'ev_allowance_kw', to_jsonb(p.ev_allowance_kw), 'predicted_peak_kw', p.predicted_peak_kw, 'solver', p.solver, 'source', p.source, 'profile_id', p.id, 'detail', p.detail) AS periods,
    p.plan_state AS profile_state
   FROM public.ottoq_energy_plan p
  WHERE (p.plan_state = ANY (ARRAY['ready'::text, 'applied'::text, 'pending'::text]))
UNION ALL
 SELECT 'service_point'::text AS resource_kind,
    s.depot_id AS site_id,
    b.stall_id AS service_point_id,
    b.sim_run_id,
    COALESCE(b.booked_at_sim, b.booked_at) AS published_at,
    lower(b.during) AS window_start,
    upper(b.during) AS window_end,
    jsonb_build_object('operation', COALESCE(oc.operation_code, b.purpose), 'asset_id', b.vehicle_id, 'booking_state', b.state) AS periods,
    b.state AS profile_state
   FROM (((public.ottoq_stall_bookings b
     JOIN public.stalls s ON ((s.id = b.stall_id)))
     LEFT JOIN public.ottoq_sim_runs r ON ((r.sim_run_id = b.sim_run_id)))
     LEFT JOIN public.ottoq_operation_catalog oc ON (((oc.booking_purpose = b.purpose) AND (oc.pack_id = 'robotaxi'::text))))
  WHERE ((b.state = ANY (ARRAY['held'::text, 'active'::text])) AND (upper(b.during) > (COALESCE(r.sim_clock_current, now()) - '01:00:00'::interval)));
-- @@ view public.service_sessions
CREATE VIEW public.service_sessions WITH (security_invoker=true) AS
 SELECT b.booking_id AS session_id,
    'booking'::text AS session_source,
    b.sim_run_id,
    b.vehicle_id AS asset_id,
    b.stall_id AS service_point_id,
    COALESCE(oc.operation_code, b.purpose) AS operation_code,
    lower(b.during) AS started_at,
        CASE
            WHEN (b.state = ANY (ARRAY['done'::text, 'released'::text, 'superseded'::text, 'interrupted'::text])) THEN upper(b.during)
            ELSE NULL::timestamp with time zone
        END AS ended_at,
    b.state AS session_state,
    b.visit_id,
    b.leg_id,
    NULL::uuid AS schedule_task_id
   FROM (public.ottoq_stall_bookings b
     LEFT JOIN public.ottoq_operation_catalog oc ON (((oc.booking_purpose = b.purpose) AND (oc.pack_id = 'robotaxi'::text))))
UNION ALL
 SELECT t.id AS session_id,
    'schedule_task'::text AS session_source,
    NULL::uuid AS sim_run_id,
    t.vehicle_id AS asset_id,
    COALESCE(t.actual_stall_id, t.assigned_stall_id) AS service_point_id,
    COALESCE(oc.operation_code, t.service_code, sd.code) AS operation_code,
    COALESCE(t.actual_start, t.scheduled_start) AS started_at,
    t.actual_end AS ended_at,
    (t.status)::text AS session_state,
    NULL::uuid AS visit_id,
    NULL::uuid AS leg_id,
    t.id AS schedule_task_id
   FROM ((public.schedule_tasks t
     JOIN public.service_definitions sd ON ((sd.id = t.service_definition_id)))
     LEFT JOIN public.ottoq_operation_catalog oc ON (((oc.svc_code = COALESCE(t.service_code, sd.code)) AND (oc.pack_id = 'robotaxi'::text))))
  WHERE ((t.status)::text = ANY (ARRAY['in_progress'::text, 'completed'::text]));
-- @@ view public.v_charger_status
CREATE VIEW public.v_charger_status AS
 SELECT s.id AS stall_id,
    s.depot_id,
    s.stall_code,
    s.stall_type,
    s.status AS stall_status,
    s.current_vehicle_id,
    v.display_name AS vehicle_name,
    v.current_soc,
    os.transaction_id,
    os.status AS session_status,
    os.energy_delivered_kwh,
    os.peak_power_kw,
    os.soc_start,
    os.soc_end,
    os.started_at AS session_started,
    cc.cooldown_required,
    cc.available_at AS cooldown_available_at,
    (GREATEST((0)::numeric, (EXTRACT(epoch FROM (cc.available_at - now())) / (60)::numeric)))::integer AS cooldown_minutes_remaining,
    chs.health_score AS charger_health,
    chs.recommended_maintenance
   FROM ((((public.stalls s
     LEFT JOIN public.vehicles v ON ((v.id = s.current_vehicle_id)))
     LEFT JOIN public.ocpp_sessions os ON (((os.stall_id = s.id) AND (os.status = 'active'::public.ocpp_session_status))))
     LEFT JOIN public.charger_cooldowns cc ON (((cc.stall_id = s.id) AND (cc.resolved = false))))
     LEFT JOIN public.charger_health_scores chs ON ((chs.stall_id = s.id)))
  WHERE (s.stall_type = ANY (ARRAY['dcfc'::public.stall_type, 'l2'::public.stall_type]));
-- @@ view public.v_depot_status
CREATE VIEW public.v_depot_status AS
 SELECT d.id AS depot_id,
    d.name AS depot_name,
    d.slug,
    count(DISTINCT v.id) FILTER (WHERE ((v.current_depot_id = d.id) AND (v.current_state <> 'offline'::public.vehicle_state))) AS vehicles_on_site,
    count(DISTINCT s.id) FILTER (WHERE ((s.stall_type = 'dcfc'::public.stall_type) AND (s.status = 'occupied'::text))) AS dcfc_in_use,
    count(DISTINCT s.id) FILTER (WHERE ((s.stall_type = 'dcfc'::public.stall_type) AND (s.status = 'available'::text))) AS dcfc_available,
    count(DISTINCT s.id) FILTER (WHERE ((s.stall_type = 'l2'::public.stall_type) AND (s.status = 'occupied'::text))) AS l2_in_use,
    count(DISTINCT s.id) FILTER (WHERE ((s.stall_type = 'l2'::public.stall_type) AND (s.status = 'available'::text))) AS l2_available,
    count(DISTINCT s.id) FILTER (WHERE ((s.stall_type = 'wash_bay'::public.stall_type) AND (s.status = 'occupied'::text))) AS wash_bays_in_use,
    count(DISTINCT s.id) FILTER (WHERE ((s.stall_type = 'wash_bay'::public.stall_type) AND (s.status = 'available'::text))) AS wash_bays_available,
    count(DISTINCT s.id) FILTER (WHERE ((s.stall_type = 'service_bay'::public.stall_type) AND (s.status = 'occupied'::text))) AS service_bays_in_use,
    count(DISTINCT e.id) FILTER (WHERE (e.status = ANY (ARRAY['open'::public.exception_status, 'acknowledged'::public.exception_status, 'in_progress'::public.exception_status]))) AS active_exceptions
   FROM (((public.depots d
     LEFT JOIN public.stalls s ON ((s.depot_id = d.id)))
     LEFT JOIN public.vehicles v ON ((v.current_depot_id = d.id)))
     LEFT JOIN public.exceptions e ON ((e.depot_id = d.id)))
  WHERE (d.status = 'active'::text)
  GROUP BY d.id, d.name, d.slug;
-- @@ view public.v_energy_status
CREATE VIEW public.v_energy_status AS
 SELECT d.id AS depot_id,
    d.name AS depot_name,
    ses.grid_import_kw,
    ses.solar_generation_kw,
    ses.bess_output_kw,
    ses.total_ev_charging_kw,
    ses.building_load_kw,
    ses.peak_demand_kw_15min,
    ses.billing_period_peak_kw,
    ses.current_tariff_label,
    ses.current_rate_per_kwh,
    bs.soc_percent AS bess_soc,
    bs.status AS bess_status,
    bs.current_output_kw AS bess_current_output,
    ((d.config ->> 'peak_demand_kw_limit'::text))::numeric AS demand_limit_kw,
        CASE
            WHEN (((d.config ->> 'peak_demand_kw_limit'::text))::numeric > (0)::numeric) THEN round(((ses.peak_demand_kw_15min / ((d.config ->> 'peak_demand_kw_limit'::text))::numeric) * (100)::numeric), 1)
            ELSE (0)::numeric
        END AS demand_utilization_pct
   FROM ((public.depots d
     LEFT JOIN LATERAL ( SELECT site_energy_snapshots.id,
            site_energy_snapshots.depot_id,
            site_energy_snapshots."timestamp",
            site_energy_snapshots.grid_import_kw,
            site_energy_snapshots.grid_export_kw,
            site_energy_snapshots.solar_generation_kw,
            site_energy_snapshots.bess_output_kw,
            site_energy_snapshots.total_ev_charging_kw,
            site_energy_snapshots.building_load_kw,
            site_energy_snapshots.lighting_load_kw,
            site_energy_snapshots.peak_demand_kw_15min,
            site_energy_snapshots.billing_period_peak_kw,
            site_energy_snapshots.current_tariff_label,
            site_energy_snapshots.current_rate_per_kwh,
            site_energy_snapshots.created_at
           FROM public.site_energy_snapshots
          WHERE (site_energy_snapshots.depot_id = d.id)
          ORDER BY site_energy_snapshots."timestamp" DESC
         LIMIT 1) ses ON (true))
     LEFT JOIN LATERAL ( SELECT bess_snapshots.id,
            bess_snapshots.depot_id,
            bess_snapshots.system_id,
            bess_snapshots."timestamp",
            bess_snapshots.soc_percent,
            bess_snapshots.capacity_kwh,
            bess_snapshots.usable_capacity_kwh,
            bess_snapshots.current_output_kw,
            bess_snapshots.max_discharge_kw,
            bess_snapshots.max_charge_kw,
            bess_snapshots.grid_import_kw,
            bess_snapshots.grid_export_kw,
            bess_snapshots.temperature_c,
            bess_snapshots.health_percent,
            bess_snapshots.cycle_count,
            bess_snapshots.status,
            bess_snapshots.created_at
           FROM public.bess_snapshots
          WHERE (bess_snapshots.depot_id = d.id)
          ORDER BY bess_snapshots."timestamp" DESC
         LIMIT 1) bs ON (true))
  WHERE (d.status = 'active'::text);
-- @@ view public.v_vehicle_service_history
CREATE VIEW public.v_vehicle_service_history AS
 SELECT v.id AS vehicle_id,
    v.display_name,
    v.vin,
    fo.name AS fleet_operator,
    count(DISTINCT vs.id) AS total_visits,
    count(DISTINCT st.id) AS total_services,
    count(DISTINCT st.id) FILTER (WHERE (st.status = 'completed'::public.task_status)) AS completed_services,
    count(DISTINCT st.id) FILTER (WHERE (st.status = 'exception'::public.task_status)) AS exception_services,
    avg((EXTRACT(epoch FROM (st.actual_end - st.actual_start)) / (60)::numeric)) FILTER (WHERE (st.status = 'completed'::public.task_status)) AS avg_service_duration_minutes,
    max(vs.actual_arrival) AS last_visit,
    sum(st.energy_delivered_kwh) FILTER (WHERE (st.energy_delivered_kwh IS NOT NULL)) AS total_kwh_delivered
   FROM (((public.vehicles v
     LEFT JOIN public.fleet_operators fo ON ((fo.id = v.fleet_operator_id)))
     LEFT JOIN public.vehicle_schedules vs ON ((vs.vehicle_id = v.id)))
     LEFT JOIN public.schedule_tasks st ON ((st.vehicle_schedule_id = vs.id)))
  GROUP BY v.id, v.display_name, v.vin, fo.name;
-- @@ view public.workload_harness_report
CREATE VIEW public.workload_harness_report AS
 SELECT r.sim_run_id,
    r.scenario_code,
    r.random_seed,
    r.status,
    m.section,
    m.metric,
    m.value,
    m.denom,
    m.per_arrival,
    m.detail
   FROM (( SELECT ottoq_sim_runs.sim_run_id,
            ottoq_sim_runs.sim_run_seq,
            ottoq_sim_runs.scenario_id,
            ottoq_sim_runs.scenario_code,
            ottoq_sim_runs.started_at,
            ottoq_sim_runs.ended_at,
            ottoq_sim_runs.last_tick_at,
            ottoq_sim_runs.next_tick_due_at,
            ottoq_sim_runs.sim_clock_start,
            ottoq_sim_runs.sim_clock_current,
            ottoq_sim_runs.sim_clock_end,
            ottoq_sim_runs.time_scale,
            ottoq_sim_runs.tick_interval_seconds,
            ottoq_sim_runs.tick_count,
            ottoq_sim_runs.depot_id,
            ottoq_sim_runs.random_seed,
            ottoq_sim_runs.status,
            ottoq_sim_runs.failure_reason,
            ottoq_sim_runs.events_generated,
            ottoq_sim_runs.vehicles_simulated,
            ottoq_sim_runs.charge_sessions,
            ottoq_sim_runs.tasks_completed,
            ottoq_sim_runs.anomalies_injected,
            ottoq_sim_runs.emergencies_triggered,
            ottoq_sim_runs.rule_evaluations,
            ottoq_sim_runs.rule_failures,
            ottoq_sim_runs.predictions_emitted,
            ottoq_sim_runs.recommendations_made,
            ottoq_sim_runs.timeline_cursor,
            ottoq_sim_runs.validation_status,
            ottoq_sim_runs.validation_notes,
            ottoq_sim_runs.validation_assertions,
            ottoq_sim_runs.run_by,
            ottoq_sim_runs.notes,
            ottoq_sim_runs.payload,
            ottoq_sim_runs.policy,
            ottoq_sim_runs.ab_group_id,
            ottoq_sim_runs.crn_streams,
            ottoq_sim_runs.demo_speed_x
           FROM public.ottoq_sim_runs
          WHERE (COALESCE(ottoq_sim_runs.run_by, ''::text) <> 'production_live'::text)
          ORDER BY ottoq_sim_runs.started_at DESC
         LIMIT 1) r
     CROSS JOIN LATERAL public.workload_harness_metrics(r.sim_run_id) m(section, metric, value, denom, per_arrival, detail));
