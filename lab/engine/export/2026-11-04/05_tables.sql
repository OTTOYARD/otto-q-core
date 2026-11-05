-- 05_tables.sql: 453 statements, exported from production's catalog
-- @@ table public._fk0020
CREATE TABLE public._fk0020 (
    con text,
    child text,
    parent text,
    orphans bigint
);
-- @@ table public._p9
CREATE TABLE public._p9 (
    k text,
    v text
);
-- @@ table public._test_api
CREATE TABLE public._test_api (
    id integer
);
-- @@ table public._w0020
CREATE TABLE public._w0020 (
    k text,
    v text
);
-- @@ table public.ab_tests
CREATE TABLE public.ab_tests (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    parameter_group text NOT NULL,
    test_name text NOT NULL,
    variant_a_version_id uuid NOT NULL,
    variant_b_version_id uuid NOT NULL,
    traffic_split_pct integer NOT NULL,
    hypothesis text,
    primary_metric text NOT NULL,
    minimum_sample_size integer NOT NULL,
    minimum_detectable_effect numeric(5,4),
    significance_level numeric(4,3) NOT NULL,
    power numeric(4,3) NOT NULL,
    status text NOT NULL,
    started_at timestamp with time zone,
    planned_end_at timestamp with time zone,
    ended_at timestamp with time zone,
    variant_a_samples integer,
    variant_b_samples integer,
    variant_a_metric numeric(10,6),
    variant_b_metric numeric(10,6),
    effect_size numeric(10,6),
    confidence_interval jsonb,
    p_value numeric(10,8),
    winner_version_id uuid,
    conclusion text,
    safety_stop_conditions jsonb,
    created_at timestamp with time zone NOT NULL,
    created_by text,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.accuracy_alerts
CREATE TABLE public.accuracy_alerts (
    id uuid NOT NULL,
    slo_id uuid NOT NULL,
    depot_id uuid,
    prediction_type text NOT NULL,
    time_horizon_hours integer,
    severity text NOT NULL,
    observed_at timestamp with time zone NOT NULL,
    observed_accuracy numeric(5,4) NOT NULL,
    threshold_breached numeric(4,3) NOT NULL,
    samples_in_window integer NOT NULL,
    window_start timestamp with time zone NOT NULL,
    window_end timestamp with time zone NOT NULL,
    auto_action_taken jsonb,
    acknowledged_at timestamp with time zone,
    acknowledged_by text,
    resolved_at timestamp with time zone,
    resolved_by text,
    resolution_notes text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.accuracy_slos
CREATE TABLE public.accuracy_slos (
    id uuid NOT NULL,
    depot_id uuid,
    prediction_type text NOT NULL,
    time_horizon_hours integer,
    slo_target numeric(4,3) NOT NULL,
    accuracy_threshold numeric(4,3) NOT NULL,
    evaluation_window_hours integer NOT NULL,
    min_samples integer NOT NULL,
    warning_at numeric(4,3),
    critical_at numeric(4,3),
    alert_cooldown_min integer NOT NULL,
    auto_rollback_on_breach boolean NOT NULL,
    auto_rollback_confidence numeric(4,3),
    is_active boolean NOT NULL,
    owner text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.action_guardrails
CREATE TABLE public.action_guardrails (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    action_type text NOT NULL,
    max_per_hour integer NOT NULL,
    max_per_shift integer NOT NULL,
    max_per_day integer NOT NULL,
    min_confidence numeric(4,3) NOT NULL,
    auto_execute_confidence numeric(4,3) NOT NULL,
    cooldown_minutes integer NOT NULL,
    blackout_start time without time zone,
    blackout_end time without time zone,
    requires_human_approval boolean NOT NULL,
    enabled boolean NOT NULL,
    allow_rollback boolean NOT NULL,
    max_vehicles_affected integer,
    max_demand_impact_kw numeric(10,2),
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ai_decision_log
CREATE TABLE public.ai_decision_log (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    vehicle_id uuid,
    request_id text NOT NULL,
    context text NOT NULL,
    urgency text NOT NULL,
    question text NOT NULL,
    depot_state jsonb NOT NULL,
    specific_data jsonb NOT NULL,
    constraints jsonb,
    model_used text,
    decisions jsonb,
    reasoning_chain text,
    requires_human_approval boolean,
    auto_apply_eligible boolean,
    status text NOT NULL,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    applied_at timestamp with time zone,
    token_usage_input integer,
    token_usage_output integer,
    latency_ms integer,
    error_message text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.api_integrations
CREATE TABLE public.api_integrations (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    fleet_operator_id uuid,
    platform public.av_platform NOT NULL,
    integration_name text NOT NULL,
    is_active boolean NOT NULL,
    api_base_url text NOT NULL,
    auth_type text NOT NULL,
    credentials jsonb NOT NULL,
    endpoint_config jsonb NOT NULL,
    callback_url text,
    callback_secret text,
    rate_limit_requests_per_min integer,
    rate_limit_requests_per_day integer,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.autonomous_action_log
CREATE TABLE public.autonomous_action_log (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    prediction_id uuid,
    action_type text NOT NULL,
    action_parameters jsonb NOT NULL,
    action_summary text,
    pre_state jsonb NOT NULL,
    post_state jsonb,
    confidence numeric(4,3) NOT NULL,
    approval_method text NOT NULL,
    approved_by text,
    risk_factors jsonb,
    estimated_impact text,
    status text NOT NULL,
    execution_started_at timestamp with time zone,
    execution_completed_at timestamp with time zone,
    execution_duration_ms integer,
    error_message text,
    rollback_data jsonb,
    rollback_performed boolean NOT NULL,
    rollback_at timestamp with time zone,
    rollback_reason text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    downstream_system text,
    executed_payload jsonb,
    downstream_response jsonb,
    downstream_status_code integer,
    idempotency_key text,
    retry_count integer,
    contract_id uuid,
    ab_test_id uuid,
    fusion_log_id uuid
);
-- @@ table public.availability_fix_proof_2026_08_03
CREATE TABLE public.availability_fix_proof_2026_08_03 (
    id bigint NOT NULL,
    at timestamp with time zone NOT NULL,
    phase text NOT NULL,
    metric text NOT NULL,
    value numeric,
    note text
);
-- @@ table public.bay_reservation_reconcile_2026_08_02
CREATE TABLE public.bay_reservation_reconcile_2026_08_02 (
    id bigint NOT NULL,
    logged_at timestamp with time zone NOT NULL,
    sim_run_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    vehicle_id uuid,
    stall_id uuid,
    purpose text,
    sim_clock timestamp with time zone,
    action text NOT NULL,
    reason text,
    blocked_by text,
    old_from timestamp with time zone,
    old_to timestamp with time zone,
    new_from timestamp with time zone,
    new_to timestamp with time zone,
    defer_seq integer,
    eta timestamp with time zone
);
-- @@ table public.bess_snapshots
CREATE TABLE public.bess_snapshots (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    system_id text NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    soc_percent numeric(5,2) NOT NULL,
    capacity_kwh numeric(10,2) NOT NULL,
    usable_capacity_kwh numeric(10,2) NOT NULL,
    current_output_kw numeric(10,2) NOT NULL,
    max_discharge_kw numeric(10,2) NOT NULL,
    max_charge_kw numeric(10,2) NOT NULL,
    grid_import_kw numeric(10,2),
    grid_export_kw numeric(10,2),
    temperature_c numeric(5,1),
    health_percent numeric(5,2),
    cycle_count integer,
    status public.bess_status NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.booking_ledger_proof_2026_08_01
CREATE TABLE public.booking_ledger_proof_2026_08_01 (
    phase text,
    decision_id uuid,
    sim_run_id uuid,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    created_at timestamp with time zone,
    vehicle_id uuid,
    src text,
    stall_decided uuid
);
-- @@ table public.booking_ledger_proof_bk_2026_08_01
CREATE TABLE public.booking_ledger_proof_bk_2026_08_01 (
    phase text,
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text
);
-- @@ table public.build1_smoke_result
CREATE TABLE public.build1_smoke_result (
    step text,
    metric text,
    value numeric,
    note text
);
-- @@ table public.build2_bookings_raw_2026_08_02
CREATE TABLE public.build2_bookings_raw_2026_08_02 (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    stall_kind text,
    stall_type text,
    window_min numeric,
    preserved_at timestamp with time zone
);
-- @@ table public.build2_cert_424242
CREATE TABLE public.build2_cert_424242 (
    sim_run_id uuid,
    captured_at timestamp with time zone,
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text
);
-- @@ table public.build2_interrupted_recount_2026_08_02
CREATE TABLE public.build2_interrupted_recount_2026_08_02 (
    booking_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    stall_id uuid,
    leg_id uuid,
    purpose text,
    release_reason_before text,
    actual_min numeric,
    planned_min_reconstructed numeric,
    completion_ratio numeric,
    shortfall_min numeric,
    reclassified_interrupted boolean,
    method text,
    classified_at timestamp with time zone
);
-- @@ table public.build2_needscard_before_2026_08_02
CREATE TABLE public.build2_needscard_before_2026_08_02 (
    vehicle_id uuid,
    open_work_min numeric,
    open_must_do_min numeric,
    need_statement jsonb,
    captured_at timestamp with time zone
);
-- @@ table public.build2_visit_needs_raw_2026_08_02
CREATE TABLE public.build2_visit_needs_raw_2026_08_02 (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone,
    visit_key text,
    archetype text,
    urgency text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb,
    status text,
    source text,
    meta jsonb,
    created_at timestamp with time zone,
    preserved_at timestamp with time zone
);
-- @@ table public.build3_pre_bookings_2026_08_02
CREATE TABLE public.build3_pre_bookings_2026_08_02 (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    stall_kind text,
    zone text
);
-- @@ table public.build3_pre_legs_2026_08_02
CREATE TABLE public.build3_pre_legs_2026_08_02 (
    leg_id uuid,
    itinerary_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    seq integer,
    leg_type text,
    from_stall_id uuid,
    to_stall_id uuid,
    planned_start_sim timestamp with time zone,
    planned_end_sim timestamp with time zone,
    planned_duration_s integer,
    duration_basis jsonb,
    actual_start_sim timestamp with time zone,
    actual_end_sim timestamp with time zone,
    status text,
    deviation_s integer,
    created_at timestamp with time zone
);
-- @@ table public.build3_smoke_bookings_2026_08_02
CREATE TABLE public.build3_smoke_bookings_2026_08_02 (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    stall_kind text,
    zone text
);
-- @@ table public.build3_smoke_legs_2026_08_02
CREATE TABLE public.build3_smoke_legs_2026_08_02 (
    leg_id uuid,
    itinerary_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    seq integer,
    leg_type text,
    from_stall_id uuid,
    to_stall_id uuid,
    planned_start_sim timestamp with time zone,
    planned_end_sim timestamp with time zone,
    planned_duration_s integer,
    duration_basis jsonb,
    actual_start_sim timestamp with time zone,
    actual_end_sim timestamp with time zone,
    status text,
    deviation_s integer,
    created_at timestamp with time zone
);
-- @@ table public.busy_day_tick_probe_2026_08_01
CREATE TABLE public.busy_day_tick_probe_2026_08_01 (
    probe_id bigint NOT NULL,
    run_id uuid,
    tick_no integer,
    at_wall timestamp with time zone,
    sim_clock timestamp with time zone,
    at_gate integer,
    en_route integer,
    deployed integer,
    charging integer,
    in_bay integer,
    staged_svc integer,
    holding integer,
    occupied_stalls integer,
    dispatch_active integer,
    dispatch_returning integer,
    dispatch_completed integer,
    notes text
);
-- @@ table public.cert0020_runa_snapshot
CREATE TABLE public.cert0020_runa_snapshot (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    visit_key text,
    status text,
    atoms jsonb,
    meta jsonb,
    atoms_md5 text,
    captured_at timestamp with time zone
);
-- @@ table public.cert0022_a_after_b
CREATE TABLE public.cert0022_a_after_b (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone,
    visit_key text,
    archetype text,
    urgency text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb,
    status text,
    source text,
    meta jsonb,
    created_at timestamp with time zone,
    whole_row_md5 text,
    payload_md5 text
);
-- @@ table public.cert0022_a_bookings
CREATE TABLE public.cert0022_a_bookings (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    booked_at_sim timestamp with time zone
);
-- @@ table public.cert0022_a_dispatches
CREATE TABLE public.cert0022_a_dispatches (
    dispatch_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    fleet_operator_id uuid,
    dispatched_at timestamp with time zone,
    scheduled_return_at timestamp with time zone,
    actual_return_at timestamp with time zone,
    planned_duration_min numeric,
    actual_duration_min numeric,
    arrival_jitter_min numeric,
    soc_at_dispatch_pct numeric,
    soc_at_return_pct numeric,
    energy_consumed_kwh numeric,
    miles_driven numeric,
    return_trigger text,
    return_state text,
    status text,
    data_source text,
    created_at timestamp with time zone,
    returning_started_at timestamp with time zone,
    return_eta_minutes numeric,
    return_evidence jsonb,
    heartbeat_count integer,
    planned_return_at timestamp with time zone,
    eta_refreshed_at timestamp with time zone,
    eta_source text
);
-- @@ table public.cert0022_a_flags
CREATE TABLE public.cert0022_a_flags (
    flag_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    depot_id uuid,
    flag_kind text,
    status text,
    why text,
    return_trigger text,
    service_atom text,
    stall_type_required text,
    raised_at_sim_clock timestamp with time zone,
    recalled_at_sim_clock timestamp with time zone,
    recalled_visit_key text,
    served_at_sim_clock timestamp with time zone,
    reserved_stall_id uuid,
    drawn_seed bigint,
    created_at timestamp with time zone,
    recalled_visit_id uuid
);
-- @@ table public.cert0022_a_runrow
CREATE TABLE public.cert0022_a_runrow (
    sim_run_id uuid,
    sim_run_seq bigint,
    scenario_id uuid,
    scenario_code text,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    last_tick_at timestamp with time zone,
    next_tick_due_at timestamp with time zone,
    sim_clock_start timestamp with time zone,
    sim_clock_current timestamp with time zone,
    sim_clock_end timestamp with time zone,
    time_scale numeric,
    tick_interval_seconds integer,
    tick_count integer,
    depot_id uuid,
    random_seed bigint,
    status text,
    failure_reason text,
    events_generated bigint,
    vehicles_simulated integer,
    charge_sessions integer,
    tasks_completed integer,
    anomalies_injected integer,
    emergencies_triggered integer,
    rule_evaluations bigint,
    rule_failures bigint,
    predictions_emitted bigint,
    recommendations_made bigint,
    timeline_cursor integer,
    validation_status text,
    validation_notes text,
    validation_assertions jsonb,
    run_by text,
    notes text,
    payload jsonb,
    policy text,
    ab_group_id uuid,
    crn_streams jsonb,
    demo_speed_x numeric
);
-- @@ table public.cert0022_a_stalls
CREATE TABLE public.cert0022_a_stalls (
    id uuid,
    depot_id uuid,
    stall_code text,
    stall_type public.stall_type,
    display_name text,
    relative_x double precision,
    relative_y double precision,
    heading_degrees smallint,
    absolute_lat double precision,
    absolute_lng double precision,
    absolute_point public.geography(Point,4326),
    distance_from_entrance integer,
    status text,
    current_vehicle_id uuid,
    equipment_config jsonb,
    fiducial_marker_id text,
    uwb_beacon_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    zone text,
    reserved_for_mission_id uuid,
    connector_type text,
    connector_max_kw numeric,
    supported_inlet_types text[],
    ocpp_charger_id uuid,
    stall_kind text,
    canopy_code text,
    covered boolean,
    stall_width_ft numeric,
    stall_depth_ft numeric,
    reserved_by uuid,
    reserved_at timestamp with time zone,
    reservation_expires_at timestamp with time zone,
    staging_role text
);
-- @@ table public.cert0022_a_visitneeds
CREATE TABLE public.cert0022_a_visitneeds (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone,
    visit_key text,
    archetype text,
    urgency text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb,
    status text,
    source text,
    meta jsonb,
    created_at timestamp with time zone,
    whole_row_md5 text,
    payload_md5 text
);
-- @@ table public.cert0022_b_bookings
CREATE TABLE public.cert0022_b_bookings (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    booked_at_sim timestamp with time zone
);
-- @@ table public.cert0022_b_dispatches
CREATE TABLE public.cert0022_b_dispatches (
    dispatch_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    fleet_operator_id uuid,
    dispatched_at timestamp with time zone,
    scheduled_return_at timestamp with time zone,
    actual_return_at timestamp with time zone,
    planned_duration_min numeric,
    actual_duration_min numeric,
    arrival_jitter_min numeric,
    soc_at_dispatch_pct numeric,
    soc_at_return_pct numeric,
    energy_consumed_kwh numeric,
    miles_driven numeric,
    return_trigger text,
    return_state text,
    status text,
    data_source text,
    created_at timestamp with time zone,
    returning_started_at timestamp with time zone,
    return_eta_minutes numeric,
    return_evidence jsonb,
    heartbeat_count integer,
    planned_return_at timestamp with time zone,
    eta_refreshed_at timestamp with time zone,
    eta_source text
);
-- @@ table public.cert0022_b_flags
CREATE TABLE public.cert0022_b_flags (
    flag_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    depot_id uuid,
    flag_kind text,
    status text,
    why text,
    return_trigger text,
    service_atom text,
    stall_type_required text,
    raised_at_sim_clock timestamp with time zone,
    recalled_at_sim_clock timestamp with time zone,
    recalled_visit_key text,
    served_at_sim_clock timestamp with time zone,
    reserved_stall_id uuid,
    drawn_seed bigint,
    created_at timestamp with time zone,
    recalled_visit_id uuid
);
-- @@ table public.cert0022_b_runrow
CREATE TABLE public.cert0022_b_runrow (
    sim_run_id uuid,
    sim_run_seq bigint,
    scenario_id uuid,
    scenario_code text,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    last_tick_at timestamp with time zone,
    next_tick_due_at timestamp with time zone,
    sim_clock_start timestamp with time zone,
    sim_clock_current timestamp with time zone,
    sim_clock_end timestamp with time zone,
    time_scale numeric,
    tick_interval_seconds integer,
    tick_count integer,
    depot_id uuid,
    random_seed bigint,
    status text,
    failure_reason text,
    events_generated bigint,
    vehicles_simulated integer,
    charge_sessions integer,
    tasks_completed integer,
    anomalies_injected integer,
    emergencies_triggered integer,
    rule_evaluations bigint,
    rule_failures bigint,
    predictions_emitted bigint,
    recommendations_made bigint,
    timeline_cursor integer,
    validation_status text,
    validation_notes text,
    validation_assertions jsonb,
    run_by text,
    notes text,
    payload jsonb,
    policy text,
    ab_group_id uuid,
    crn_streams jsonb,
    demo_speed_x numeric
);
-- @@ table public.cert0022_b_stalls
CREATE TABLE public.cert0022_b_stalls (
    id uuid,
    depot_id uuid,
    stall_code text,
    stall_type public.stall_type,
    display_name text,
    relative_x double precision,
    relative_y double precision,
    heading_degrees smallint,
    absolute_lat double precision,
    absolute_lng double precision,
    absolute_point public.geography(Point,4326),
    distance_from_entrance integer,
    status text,
    current_vehicle_id uuid,
    equipment_config jsonb,
    fiducial_marker_id text,
    uwb_beacon_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    zone text,
    reserved_for_mission_id uuid,
    connector_type text,
    connector_max_kw numeric,
    supported_inlet_types text[],
    ocpp_charger_id uuid,
    stall_kind text,
    canopy_code text,
    covered boolean,
    stall_width_ft numeric,
    stall_depth_ft numeric,
    reserved_by uuid,
    reserved_at timestamp with time zone,
    reservation_expires_at timestamp with time zone,
    staging_role text
);
-- @@ table public.cert0022_b_visitneeds
CREATE TABLE public.cert0022_b_visitneeds (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone,
    visit_key text,
    archetype text,
    urgency text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb,
    status text,
    source text,
    meta jsonb,
    created_at timestamp with time zone
);
-- @@ table public.cert0022_collision
CREATE TABLE public.cert0022_collision (
    vehicle_id uuid,
    visit_key text,
    run_a_visit_id uuid,
    run_b_visit_id uuid,
    run_a uuid,
    run_b uuid
);
-- @@ table public.cert0022_fk_orphan_sweep
CREATE TABLE public.cert0022_fk_orphan_sweep (
    phase text,
    conname text,
    child text,
    childcols text,
    parent text,
    parentcols text,
    orphans bigint,
    measured_at timestamp with time zone
);
-- @@ table public.cert0022_misc
CREATE TABLE public.cert0022_misc (
    k text NOT NULL,
    v text,
    at_ts timestamp with time zone
);
-- @@ table public.cert0022_orphan_refusal
CREATE TABLE public.cert0022_orphan_refusal (
    probe text,
    target text,
    verdict text,
    sqlstate text,
    detail text,
    at_ts timestamp with time zone
);
-- @@ table public.cert0022_orphans_by_class
CREATE TABLE public.cert0022_orphans_by_class (
    phase text,
    class text,
    table_name text,
    column_name text,
    orphan_rows bigint,
    dead_runs integer,
    at_ts timestamp with time zone
);
-- @@ table public.cert0022_purge_receipt
CREATE TABLE public.cert0022_purge_receipt (
    phase text,
    receipt jsonb,
    runs_before integer,
    runs_after integer,
    visitneeds_before bigint,
    visitneeds_after bigint,
    events_before bigint,
    events_after bigint,
    bookings_before bigint,
    bookings_after bigint,
    at_ts timestamp with time zone
);
-- @@ table public.cert0023_a_bookings
CREATE TABLE public.cert0023_a_bookings (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    booked_at_sim timestamp with time zone
);
-- @@ table public.cert0023_a_dispatches
CREATE TABLE public.cert0023_a_dispatches (
    dispatch_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    fleet_operator_id uuid,
    dispatched_at timestamp with time zone,
    scheduled_return_at timestamp with time zone,
    actual_return_at timestamp with time zone,
    planned_duration_min numeric,
    actual_duration_min numeric,
    arrival_jitter_min numeric,
    soc_at_dispatch_pct numeric,
    soc_at_return_pct numeric,
    energy_consumed_kwh numeric,
    miles_driven numeric,
    return_trigger text,
    return_state text,
    status text,
    data_source text,
    created_at timestamp with time zone,
    returning_started_at timestamp with time zone,
    return_eta_minutes numeric,
    return_evidence jsonb,
    heartbeat_count integer,
    planned_return_at timestamp with time zone,
    eta_refreshed_at timestamp with time zone,
    eta_source text
);
-- @@ table public.cert0023_a_energy
CREATE TABLE public.cert0023_a_energy (
    id uuid,
    depot_id uuid,
    "timestamp" timestamp with time zone,
    grid_import_kw numeric(10,2),
    grid_export_kw numeric(10,2),
    solar_generation_kw numeric(10,2),
    bess_output_kw numeric(10,2),
    total_ev_charging_kw numeric(10,2),
    building_load_kw numeric(10,2),
    lighting_load_kw numeric(10,2),
    peak_demand_kw_15min numeric(10,2),
    billing_period_peak_kw numeric(10,2),
    current_tariff_label public.tariff_label,
    current_rate_per_kwh numeric(8,4),
    created_at timestamp with time zone,
    sim_run_id uuid,
    data_source text,
    lmp_usd_mwh numeric,
    carbon_gco2_kwh numeric
);
-- @@ table public.cert0023_a_flags
CREATE TABLE public.cert0023_a_flags (
    flag_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    depot_id uuid,
    flag_kind text,
    status text,
    why text,
    return_trigger text,
    service_atom text,
    stall_type_required text,
    raised_at_sim_clock timestamp with time zone,
    recalled_at_sim_clock timestamp with time zone,
    recalled_visit_key text,
    served_at_sim_clock timestamp with time zone,
    reserved_stall_id uuid,
    drawn_seed bigint,
    created_at timestamp with time zone,
    recalled_visit_id uuid
);
-- @@ table public.cert0023_a_running
CREATE TABLE public.cert0023_a_running (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone,
    visit_key text,
    archetype text,
    urgency text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb,
    status text,
    source text,
    meta jsonb,
    created_at timestamp with time zone,
    at_tick integer
);
-- @@ table public.cert0023_a_runrow
CREATE TABLE public.cert0023_a_runrow (
    sim_run_id uuid,
    sim_run_seq bigint,
    scenario_id uuid,
    scenario_code text,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    last_tick_at timestamp with time zone,
    next_tick_due_at timestamp with time zone,
    sim_clock_start timestamp with time zone,
    sim_clock_current timestamp with time zone,
    sim_clock_end timestamp with time zone,
    time_scale numeric,
    tick_interval_seconds integer,
    tick_count integer,
    depot_id uuid,
    random_seed bigint,
    status text,
    failure_reason text,
    events_generated bigint,
    vehicles_simulated integer,
    charge_sessions integer,
    tasks_completed integer,
    anomalies_injected integer,
    emergencies_triggered integer,
    rule_evaluations bigint,
    rule_failures bigint,
    predictions_emitted bigint,
    recommendations_made bigint,
    timeline_cursor integer,
    validation_status text,
    validation_notes text,
    validation_assertions jsonb,
    run_by text,
    notes text,
    payload jsonb,
    policy text,
    ab_group_id uuid,
    crn_streams jsonb,
    demo_speed_x numeric
);
-- @@ table public.cert0023_a_stalls
CREATE TABLE public.cert0023_a_stalls (
    id uuid,
    depot_id uuid,
    stall_type public.stall_type,
    status text,
    current_vehicle_id uuid,
    captured_real timestamp with time zone
);
-- @@ table public.cert0023_a_visitneeds
CREATE TABLE public.cert0023_a_visitneeds (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone,
    visit_key text,
    archetype text,
    urgency text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb,
    status text,
    source text,
    meta jsonb,
    created_at timestamp with time zone
);
-- @@ table public.cert0023_b_bookings
CREATE TABLE public.cert0023_b_bookings (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    booked_at_sim timestamp with time zone
);
-- @@ table public.cert0023_b_dispatches
CREATE TABLE public.cert0023_b_dispatches (
    dispatch_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    fleet_operator_id uuid,
    dispatched_at timestamp with time zone,
    scheduled_return_at timestamp with time zone,
    actual_return_at timestamp with time zone,
    planned_duration_min numeric,
    actual_duration_min numeric,
    arrival_jitter_min numeric,
    soc_at_dispatch_pct numeric,
    soc_at_return_pct numeric,
    energy_consumed_kwh numeric,
    miles_driven numeric,
    return_trigger text,
    return_state text,
    status text,
    data_source text,
    created_at timestamp with time zone,
    returning_started_at timestamp with time zone,
    return_eta_minutes numeric,
    return_evidence jsonb,
    heartbeat_count integer,
    planned_return_at timestamp with time zone,
    eta_refreshed_at timestamp with time zone,
    eta_source text
);
-- @@ table public.cert0023_b_energy
CREATE TABLE public.cert0023_b_energy (
    id uuid,
    depot_id uuid,
    "timestamp" timestamp with time zone,
    grid_import_kw numeric(10,2),
    grid_export_kw numeric(10,2),
    solar_generation_kw numeric(10,2),
    bess_output_kw numeric(10,2),
    total_ev_charging_kw numeric(10,2),
    building_load_kw numeric(10,2),
    lighting_load_kw numeric(10,2),
    peak_demand_kw_15min numeric(10,2),
    billing_period_peak_kw numeric(10,2),
    current_tariff_label public.tariff_label,
    current_rate_per_kwh numeric(8,4),
    created_at timestamp with time zone,
    sim_run_id uuid,
    data_source text,
    lmp_usd_mwh numeric,
    carbon_gco2_kwh numeric
);
-- @@ table public.cert0023_b_flags
CREATE TABLE public.cert0023_b_flags (
    flag_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    depot_id uuid,
    flag_kind text,
    status text,
    why text,
    return_trigger text,
    service_atom text,
    stall_type_required text,
    raised_at_sim_clock timestamp with time zone,
    recalled_at_sim_clock timestamp with time zone,
    recalled_visit_key text,
    served_at_sim_clock timestamp with time zone,
    reserved_stall_id uuid,
    drawn_seed bigint,
    created_at timestamp with time zone,
    recalled_visit_id uuid
);
-- @@ table public.cert0023_b_runrow
CREATE TABLE public.cert0023_b_runrow (
    sim_run_id uuid,
    sim_run_seq bigint,
    scenario_id uuid,
    scenario_code text,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    last_tick_at timestamp with time zone,
    next_tick_due_at timestamp with time zone,
    sim_clock_start timestamp with time zone,
    sim_clock_current timestamp with time zone,
    sim_clock_end timestamp with time zone,
    time_scale numeric,
    tick_interval_seconds integer,
    tick_count integer,
    depot_id uuid,
    random_seed bigint,
    status text,
    failure_reason text,
    events_generated bigint,
    vehicles_simulated integer,
    charge_sessions integer,
    tasks_completed integer,
    anomalies_injected integer,
    emergencies_triggered integer,
    rule_evaluations bigint,
    rule_failures bigint,
    predictions_emitted bigint,
    recommendations_made bigint,
    timeline_cursor integer,
    validation_status text,
    validation_notes text,
    validation_assertions jsonb,
    run_by text,
    notes text,
    payload jsonb,
    policy text,
    ab_group_id uuid,
    crn_streams jsonb,
    demo_speed_x numeric
);
-- @@ table public.cert0023_b_stalls
CREATE TABLE public.cert0023_b_stalls (
    id uuid,
    depot_id uuid,
    stall_type public.stall_type,
    status text,
    current_vehicle_id uuid,
    captured_real timestamp with time zone
);
-- @@ table public.cert0023_b_visitneeds
CREATE TABLE public.cert0023_b_visitneeds (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone,
    visit_key text,
    archetype text,
    urgency text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb,
    status text,
    source text,
    meta jsonb,
    created_at timestamp with time zone
);
-- @@ table public.cert0023_c_needs_before
CREATE TABLE public.cert0023_c_needs_before (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone,
    visit_key text,
    archetype text,
    urgency text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb,
    status text,
    source text,
    meta jsonb,
    created_at timestamp with time zone
);
-- @@ table public.cert0023_c_needs_terminal
CREATE TABLE public.cert0023_c_needs_terminal (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone,
    visit_key text,
    archetype text,
    urgency text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb,
    status text,
    source text,
    meta jsonb,
    created_at timestamp with time zone
);
-- @@ table public.cert0023_coldiff
CREATE TABLE public.cert0023_coldiff (
    phase text,
    column_name text,
    rows_compared bigint,
    differing_rows bigint,
    at_ts timestamp with time zone
);
-- @@ table public.cert0023_energy_probe
CREATE TABLE public.cert0023_energy_probe (
    k text NOT NULL,
    v text,
    at_ts timestamp with time zone
);
-- @@ table public.cert0023_fk_orphan_sweep
CREATE TABLE public.cert0023_fk_orphan_sweep (
    conname text,
    child text,
    parent text,
    orphans bigint,
    phase text,
    at_ts timestamp with time zone
);
-- @@ table public.cert0023_misc
CREATE TABLE public.cert0023_misc (
    k text NOT NULL,
    v text,
    at_ts timestamp with time zone
);
-- @@ table public.cert0023_stop_pre
CREATE TABLE public.cert0023_stop_pre (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    status text,
    meta jsonb,
    captured_real timestamp with time zone
);
-- @@ table public.cert0023_trigger_paths
CREATE TABLE public.cert0023_trigger_paths (
    step text,
    open_rows bigint,
    stamped bigint,
    at_ts timestamp with time zone
);
-- @@ table public.charger_cooldowns
CREATE TABLE public.charger_cooldowns (
    id uuid NOT NULL,
    stall_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    charge_point_id text NOT NULL,
    last_session_id uuid,
    last_session_end timestamp with time zone NOT NULL,
    last_session_peak_kw numeric(8,2) NOT NULL,
    last_session_energy_kwh numeric(10,3) NOT NULL,
    connector_temp_c numeric(5,1) NOT NULL,
    ambient_temp_c numeric(5,1),
    cooldown_required boolean NOT NULL,
    cooldown_minutes_total integer NOT NULL,
    cooldown_started_at timestamp with time zone NOT NULL,
    available_at timestamp with time zone NOT NULL,
    reduced_rate_available boolean,
    reduced_rate_max_kw numeric(8,2),
    resolved boolean NOT NULL,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.charger_health_scores
CREATE TABLE public.charger_health_scores (
    id uuid NOT NULL,
    stall_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    charge_point_id text NOT NULL,
    health_score numeric(5,2) NOT NULL,
    uptime_percent_7d numeric(5,2),
    uptime_percent_30d numeric(5,2),
    fault_count_7d integer,
    fault_count_30d integer,
    avg_session_success_rate numeric(5,4),
    avg_power_delivery_efficiency numeric(5,4),
    last_fault_at timestamp with time zone,
    last_fault_type text,
    total_sessions integer,
    failed_sessions integer,
    recommended_maintenance boolean,
    last_maintenance_at timestamp with time zone,
    factors jsonb,
    calculated_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.cuopt_enactment_proof_2026_08_01
CREATE TABLE public.cuopt_enactment_proof_2026_08_01 (
    captured_at timestamp with time zone NOT NULL,
    kind text NOT NULL,
    row_data jsonb NOT NULL
);
-- @@ table public.cuopt_invocation_log
CREATE TABLE public.cuopt_invocation_log (
    invocation_id bigint NOT NULL,
    sim_run_id uuid,
    stage text NOT NULL,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    called_at timestamp with time zone NOT NULL,
    candidates_in integer,
    free_stalls_in integer,
    proposals_out integer,
    abstained_reason text,
    latency_ms integer,
    http_status integer,
    source_note text,
    detail jsonb
);
-- @@ table public.cuopt_supply_before_2026_08_02
CREATE TABLE public.cuopt_supply_before_2026_08_02 (
    invocation_id bigint,
    sim_run_id uuid,
    stage text,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    called_at timestamp with time zone,
    candidates_in integer,
    free_stalls_in integer,
    proposals_out integer,
    abstained_reason text,
    latency_ms integer,
    http_status integer,
    source_note text,
    detail jsonb
);
-- @@ table public.cuopt_supply_ledger_2026_08_03
CREATE TABLE public.cuopt_supply_ledger_2026_08_03 (
    capture_note text,
    captured_at timestamp with time zone,
    invocation_id bigint,
    sim_run_id uuid,
    stage text,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    called_at timestamp with time zone,
    candidates_in integer,
    free_stalls_in integer,
    proposals_out integer,
    abstained_reason text,
    latency_ms integer,
    http_status integer,
    source_note text,
    detail jsonb
);
-- @@ table public.cuopt_supply_proof_2026_08_02
CREATE TABLE public.cuopt_supply_proof_2026_08_02 (
    invocation_id bigint,
    sim_run_id uuid,
    stage text,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    called_at timestamp with time zone,
    candidates_in integer,
    free_stalls_in integer,
    proposals_out integer,
    abstained_reason text,
    latency_ms integer,
    http_status integer,
    source_note text,
    detail jsonb,
    capture_note text,
    captured_at timestamp with time zone
);
-- @@ table public.data_quality_errors
CREATE TABLE public.data_quality_errors (
    id uuid NOT NULL,
    depot_id uuid,
    source_table text NOT NULL,
    source_id uuid,
    source_name text,
    error_type text NOT NULL,
    severity text NOT NULL,
    field_name text,
    expected text,
    actual text,
    message text NOT NULL,
    payload_sample jsonb,
    predictions_affected integer,
    actions_blocked integer,
    detected_at timestamp with time zone NOT NULL,
    resolved_at timestamp with time zone,
    resolved_by text,
    resolution_notes text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.decision_fusion_log
CREATE TABLE public.decision_fusion_log (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    trigger_type text NOT NULL,
    trigger_details jsonb NOT NULL,
    signals jsonb NOT NULL,
    fusion_method text NOT NULL,
    fusion_parameters jsonb,
    fusion_output jsonb NOT NULL,
    confidence numeric(4,3) NOT NULL,
    categories_addressed text[],
    emitted_prediction_id uuid,
    emitted_action_id uuid,
    outcome_link jsonb,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.demand_management_log
CREATE TABLE public.demand_management_log (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    active_dcfc_count integer NOT NULL,
    active_l2_count integer NOT NULL,
    total_draw_kw numeric(10,2) NOT NULL,
    peak_limit_kw numeric(10,2),
    utilization_pct numeric(5,2),
    action text NOT NULL,
    vehicles_affected jsonb,
    details text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.demand_shaping_plans
CREATE TABLE public.demand_shaping_plans (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    generated_at timestamp with time zone NOT NULL,
    planning_start timestamp with time zone NOT NULL,
    planning_end timestamp with time zone NOT NULL,
    target_peak_kw numeric(10,2) NOT NULL,
    projected_peak_kw numeric(10,2) NOT NULL,
    original_peak_kw numeric(10,2) NOT NULL,
    peak_reduction_kw numeric(10,2) NOT NULL,
    peak_reduction_pct numeric(5,2) NOT NULL,
    projected_demand_cost numeric(10,2),
    original_demand_cost numeric(10,2),
    savings_dollars numeric(10,2),
    optimized_schedule jsonb NOT NULL,
    demand_curve jsonb NOT NULL,
    bess_dispatch jsonb,
    constraints_satisfied boolean NOT NULL,
    constraint_violations jsonb,
    status text NOT NULL,
    applied_at timestamp with time zone,
    applied_by public.trigger_source,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.depot_state_snapshots
CREATE TABLE public.depot_state_snapshots (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    snapshot_at timestamp with time zone NOT NULL,
    vehicles_on_site integer NOT NULL,
    vehicles_charging integer NOT NULL,
    vehicles_in_service integer NOT NULL,
    vehicles_staged integer NOT NULL,
    vehicles_en_route integer NOT NULL,
    stall_utilization jsonb NOT NULL,
    active_exceptions integer NOT NULL,
    active_ottow_missions integer NOT NULL,
    current_demand_kw numeric(10,2) NOT NULL,
    peak_demand_kw_15min numeric(10,2),
    queue_depth integer NOT NULL,
    tasks_pending integer NOT NULL,
    tasks_in_progress integer NOT NULL,
    tasks_completed_today integer NOT NULL,
    current_tariff_label text,
    current_rate_per_kwh numeric(8,4),
    solar_generation_kw numeric(10,2),
    bess_output_kw numeric(10,2),
    weather_data jsonb,
    active_wave_codes text[],
    next_wave_eta_minutes integer,
    vehicles_expected_next_2h integer,
    depot_health_score numeric(4,3),
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.depot_visit_reports
CREATE TABLE public.depot_visit_reports (
    id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    schedule_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    fleet_operator_id uuid,
    visit_started_at timestamp with time zone NOT NULL,
    visit_completed_at timestamp with time zone,
    planned_sequence jsonb NOT NULL,
    actual_sequence jsonb NOT NULL,
    deviation_count integer NOT NULL,
    overrides_applied jsonb NOT NULL,
    abnormalities jsonb NOT NULL,
    oem_interactions jsonb NOT NULL,
    exceptions_raised jsonb NOT NULL,
    planned_duration_min numeric(10,2),
    actual_duration_min numeric(10,2),
    variance_minutes numeric(10,2),
    redeployment_status text,
    audit_trail_complete boolean NOT NULL,
    generated_at timestamp with time zone NOT NULL,
    payload jsonb NOT NULL
);
-- @@ table public.depots
CREATE TABLE public.depots (
    id uuid NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    address text,
    city text,
    state text,
    zip text,
    country text,
    origin_lat double precision,
    origin_lng double precision,
    origin_point public.geography(Point,4326),
    geofence public.geography(Polygon,4326),
    timezone text NOT NULL,
    status text NOT NULL,
    config jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    service_voltage numeric,
    service_max_kw numeric,
    service_max_kva numeric,
    service_provider text,
    service_tariff_code text,
    dcfc_max_concurrent_kw numeric,
    dcfc_safety_margin_pct numeric,
    demand_charge_threshold_kw numeric,
    demand_response_program text,
    demand_response_active boolean,
    operating_timezone text,
    operational_hours_start time without time zone,
    operational_hours_end time without time zone,
    overnight_staging_threshold_minutes integer,
    quiet_hours_start time without time zone,
    quiet_hours_end time without time zone,
    shift_change_buffer_minutes integer,
    site_length_ft numeric,
    site_width_ft numeric,
    site_acres numeric,
    site_layout jsonb,
    daily_throughput_target integer,
    feed_mode text NOT NULL
);
-- @@ table public.dispatch_commands
CREATE TABLE public.dispatch_commands (
    id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    platform public.av_platform NOT NULL,
    av_api_vehicle_id text NOT NULL,
    command_type text NOT NULL,
    destination_lat double precision,
    destination_lng double precision,
    destination_stall_id uuid,
    destination_stall_code text,
    idempotency_key text NOT NULL,
    issued_at timestamp with time zone NOT NULL,
    issued_by public.trigger_source NOT NULL,
    issued_by_user_id uuid,
    timeout_seconds integer NOT NULL,
    success boolean,
    platform_command_id text,
    estimated_arrival_seconds integer,
    error_code text,
    error_message text,
    platform_response jsonb,
    attempt_number integer NOT NULL,
    retry_of_id uuid,
    retry_eligible boolean,
    completed_at timestamp with time zone,
    vehicle_arrived_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.downstream_action_contracts
CREATE TABLE public.downstream_action_contracts (
    id uuid NOT NULL,
    action_type text NOT NULL,
    downstream_system text NOT NULL,
    payload_schema jsonb NOT NULL,
    example_payload jsonb,
    transport_method text NOT NULL,
    endpoint_template text,
    auth_requirements jsonb,
    retry_policy jsonb NOT NULL,
    idempotency_key_source text,
    timeout_ms integer NOT NULL,
    supports_rollback boolean NOT NULL,
    rollback_strategy text,
    rollback_payload_template jsonb,
    is_implemented boolean NOT NULL,
    implementation_notes text,
    partner_contact text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.early_recall_log
CREATE TABLE public.early_recall_log (
    id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    vehicle_schedule_id uuid,
    assessed_at timestamp with time zone NOT NULL,
    current_soc integer NOT NULL,
    predicted_soc_at_arrival integer NOT NULL,
    confidence_low integer NOT NULL,
    confidence_high integer NOT NULL,
    min_soc_threshold integer NOT NULL,
    distance_to_depot_miles numeric(8,2),
    energy_to_depot_kwh numeric(8,2),
    can_reach_depot boolean NOT NULL,
    urgency public.recall_urgency NOT NULL,
    recommended_action public.recall_action NOT NULL,
    reason text NOT NULL,
    disruption_impact text NOT NULL,
    affected_wave_id uuid,
    vehicles_displaced integer,
    wave_can_absorb boolean,
    action_taken public.recall_action,
    action_taken_at timestamp with time zone,
    action_taken_by public.trigger_source,
    override_reason text,
    scheduled_arrival timestamp with time zone NOT NULL,
    recommended_arrival timestamp with time zone,
    actual_arrival timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.emergency_queue_insertions
CREATE TABLE public.emergency_queue_insertions (
    id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    reason public.emergency_reason NOT NULL,
    priority_override public.priority_tier NOT NULL,
    services_needed jsonb NOT NULL,
    estimated_arrival_minutes integer NOT NULL,
    current_soc integer,
    special_instructions text,
    requested_by public.trigger_source NOT NULL,
    requested_by_user_id uuid,
    oem_approval_required boolean NOT NULL,
    oem_reference_id text,
    status text NOT NULL,
    approved_by uuid,
    approved_at timestamp with time zone,
    assigned_wave_id uuid,
    assigned_stall_id uuid,
    assigned_arrival_time timestamp with time zone,
    vehicle_schedule_id uuid,
    disruption_score integer NOT NULL,
    vehicles_displaced jsonb,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.emission_fix_smoke_2026_08_03
CREATE TABLE public.emission_fix_smoke_2026_08_03 (
    id bigint NOT NULL,
    at timestamp with time zone,
    step text,
    note text,
    ok boolean
);
-- @@ table public.engine_config
CREATE TABLE public.engine_config (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    early_recall_soc_advisory integer NOT NULL,
    early_recall_soc_recommended integer NOT NULL,
    early_recall_soc_critical integer NOT NULL,
    early_recall_check_interval_min integer NOT NULL,
    cooldown_temp_threshold_c numeric(5,1) NOT NULL,
    cooldown_base_minutes integer NOT NULL,
    cooldown_per_degree_minutes numeric(4,2) NOT NULL,
    demand_shaping_enabled boolean NOT NULL,
    demand_target_pct_of_limit integer NOT NULL,
    bess_arbitrage_enabled boolean NOT NULL,
    ai_enabled boolean NOT NULL,
    ai_auto_apply_confidence numeric(4,3) NOT NULL,
    ai_model text NOT NULL,
    ai_max_response_time_ms integer NOT NULL,
    max_emergency_insertions_per_hr integer NOT NULL,
    disruption_approval_threshold integer NOT NULL,
    modification_deadline_hours integer NOT NULL,
    late_modification_fee_base numeric(10,2) NOT NULL,
    cb_failure_threshold integer NOT NULL,
    cb_reset_timeout_ms integer NOT NULL,
    cb_half_open_max_requests integer NOT NULL,
    min_move_buffer_seconds integer NOT NULL,
    max_simultaneous_moves integer NOT NULL,
    emergency_stop_propagation boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.exceptions
CREATE TABLE public.exceptions (
    id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    schedule_task_id uuid,
    vehicle_schedule_id uuid,
    stall_id uuid,
    exception_type public.exception_type NOT NULL,
    severity public.exception_severity NOT NULL,
    status public.exception_status NOT NULL,
    title text NOT NULL,
    description text,
    photos jsonb,
    reported_by_user_id uuid,
    reported_by_role public.staff_role,
    assigned_to_user_id uuid,
    assigned_to_role public.staff_role,
    resolution_action text,
    resolution_notes text,
    resolved_by_user_id uuid,
    resolved_by_role public.staff_role,
    stall_closed boolean,
    stall_reopened_at timestamp with time zone,
    schedule_impact text,
    credit_issued boolean,
    credit_amount numeric(10,2),
    tow_requested boolean,
    tow_dispatch_id text,
    tow_eta timestamp with time zone,
    tow_completed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    acknowledged_at timestamp with time zone,
    resolved_at timestamp with time zone,
    updated_at timestamp with time zone NOT NULL,
    metadata jsonb,
    blocks_progression boolean NOT NULL,
    resolution_required_before text,
    required_resolver_role text,
    audit_note text,
    data_source text,
    sim_run_id uuid
);
-- @@ table public.external_factor_sources
CREATE TABLE public.external_factor_sources (
    id uuid NOT NULL,
    depot_id uuid,
    factor_type text NOT NULL,
    source_name text NOT NULL,
    provider text,
    source_url text,
    config jsonb NOT NULL,
    poll_interval_sec integer NOT NULL,
    poll_mode text NOT NULL,
    schema_version integer NOT NULL,
    required_fields text[],
    staleness_tolerance_sec integer NOT NULL,
    last_polled_at timestamp with time zone,
    last_success_at timestamp with time zone,
    last_error_at timestamp with time zone,
    last_error text,
    consecutive_failures integer NOT NULL,
    health_status text NOT NULL,
    is_active boolean NOT NULL,
    fallback_strategy text,
    notes text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.external_factors_log
CREATE TABLE public.external_factors_log (
    id uuid NOT NULL,
    source_id uuid NOT NULL,
    depot_id uuid,
    factor_type text NOT NULL,
    observed_at timestamp with time zone NOT NULL,
    ingested_at timestamp with time zone NOT NULL,
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone,
    payload jsonb NOT NULL,
    data_hash text,
    quality_score numeric(4,3),
    is_interpolated boolean NOT NULL,
    supersedes_id uuid,
    consumed_by_predictions uuid[],
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.fleet_features_daily
CREATE TABLE public.fleet_features_daily (
    id uuid NOT NULL,
    feature_date date NOT NULL,
    feature_group text NOT NULL,
    scope text NOT NULL,
    scope_id text NOT NULL,
    features jsonb NOT NULL,
    sample_count integer NOT NULL,
    confidence numeric(4,3) NOT NULL,
    lookback_days integer NOT NULL,
    computed_at timestamp with time zone NOT NULL,
    compute_duration_ms integer,
    compute_method text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.fleet_operators
CREATE TABLE public.fleet_operators (
    id uuid NOT NULL,
    name text NOT NULL,
    company text NOT NULL,
    slug text NOT NULL,
    contact_name text,
    contact_email text,
    contact_phone text,
    contract_tier text NOT NULL,
    priority public.priority_tier NOT NULL,
    monthly_rate_per_vehicle numeric(10,2),
    default_target_soc integer NOT NULL,
    default_service_sequence jsonb NOT NULL,
    webhook_url text,
    api_key_hash text,
    fleet_api_config jsonb,
    notification_preferences jsonb NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    auth_user_id uuid,
    progression_acceptance_mode text NOT NULL,
    oem_acceptance_timeout_seconds integer NOT NULL,
    oem_acceptance_on_timeout text NOT NULL,
    oem_flag_inbound_secret text
);
-- @@ table public.fwd1_cert_424242
CREATE TABLE public.fwd1_cert_424242 (
    id bigint NOT NULL,
    captured_at timestamp with time zone NOT NULL,
    phase text NOT NULL,
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text
);
-- @@ table public.fwd2_atom_samples
CREATE TABLE public.fwd2_atom_samples (
    sampled_at timestamp with time zone NOT NULL,
    sim_min numeric,
    vehicle_id uuid,
    svc text,
    done_atoms integer,
    last_done_at timestamp with time zone
);
-- @@ table public.fwd2_boot_profiles
CREATE TABLE public.fwd2_boot_profiles (
    snap_at timestamp with time zone,
    vehicle_id uuid,
    profile_version text,
    drawn_for_run uuid,
    drawn_seed bigint,
    drawn_at timestamp with time zone,
    drawn_at_sim_clock timestamp with time zone,
    battery_soh_pct numeric,
    battery_chemistry text,
    charge_accept_kw numeric,
    pack_temp_c numeric,
    dcfc_safe boolean,
    dcfc_block_reason text,
    cell_balance_due_at timestamp with time zone,
    min_ready_soc_pct numeric,
    exterior_soil_level numeric,
    cabin_condition text,
    last_wash_at timestamp with time zone,
    last_deep_clean_at timestamp with time zone,
    wash_interval_h numeric,
    deep_clean_interval_h numeric,
    calib_interval_h numeric,
    calib_interval_km numeric,
    last_calibration_at timestamp with time zone,
    sensor_health_pct numeric,
    software_version text,
    sw_target_version text,
    sw_update_size_mb integer,
    odometer_km numeric,
    pm_interval_km numeric,
    km_at_last_pm numeric,
    last_pm_at timestamp with time zone,
    open_fault_codes text[],
    worst_fault_severity smallint,
    tire_tread_mm numeric,
    tire_rotation_due_km numeric,
    brake_wear_pct numeric,
    next_deploy_at timestamp with time zone,
    priority_class text,
    assigned_shift text,
    item_retrieval_pending boolean,
    item_reported_at timestamp with time zone,
    item_description text,
    updated_at timestamp with time zone,
    wear_km_applied numeric,
    wear_km_applied_run uuid
);
-- @@ table public.fwd2_card_samples
CREATE TABLE public.fwd2_card_samples (
    sampled_at timestamp with time zone NOT NULL,
    sim_min numeric,
    vehicle_id uuid,
    overall_urgency text,
    wash_urgency text,
    cabin_urgency text,
    exterior_soil_level numeric,
    cabin_condition text,
    wash_ratio numeric,
    deep_clean_ratio numeric
);
-- @@ table public.fwd2_pre909_card
CREATE TABLE public.fwd2_pre909_card (
    vehicle_id uuid,
    av_id text,
    display_name text,
    depot_id uuid,
    run_id uuid,
    sim_clock timestamp with time zone,
    current_state public.vehicle_state,
    drawn_seed bigint,
    profile_version text,
    soc_pct integer,
    target_soc_pct integer,
    min_ready_soc_pct numeric,
    soc_deficit_to_sla numeric,
    soc_deficit_to_target integer,
    est_charge_min integer,
    battery_soh_pct numeric,
    battery_chemistry text,
    charge_accept_kw numeric,
    pack_temp_c numeric,
    dcfc_safe boolean,
    dcfc_block_reason text,
    cell_balance_due_at timestamp with time zone,
    energy_urgency text,
    exterior_soil_level numeric,
    cabin_condition text,
    last_wash_at timestamp with time zone,
    wash_due_at timestamp with time zone,
    wash_ratio numeric,
    wash_urgency text,
    last_deep_clean_at timestamp with time zone,
    deep_clean_due_at timestamp with time zone,
    deep_clean_ratio numeric,
    cabin_urgency text,
    last_calibration_at timestamp with time zone,
    calib_due_at timestamp with time zone,
    calib_ratio numeric,
    calib_urgency text,
    sensor_health_pct numeric,
    software_version text,
    sw_target_version text,
    sw_behind boolean,
    sw_update_size_mb integer,
    software_urgency text,
    odometer_km numeric,
    km_since_pm numeric,
    pm_interval_km numeric,
    pm_ratio numeric,
    pm_urgency text,
    open_fault_codes text[],
    worst_fault_severity smallint,
    fault_urgency text,
    tire_tread_mm numeric,
    tire_urgency text,
    brake_wear_pct numeric,
    brake_urgency text,
    next_deploy_at timestamp with time zone,
    minutes_to_deploy integer,
    priority_class text,
    assigned_shift text,
    item_retrieval_pending boolean,
    item_description text,
    item_reported_at timestamp with time zone,
    item_urgency text,
    must_do_now text[],
    deferrable_now text[],
    open_work_min numeric,
    open_must_do_min numeric,
    fits_window boolean,
    overall_urgency text,
    must_do_legs text[],
    need_statement jsonb,
    owed_bay_svcs text[],
    owed_bay_min numeric,
    rebook_owed boolean
);
-- @@ table public.fwd2_pre909_profiles
CREATE TABLE public.fwd2_pre909_profiles (
    vehicle_id uuid,
    profile_version text,
    drawn_for_run uuid,
    drawn_seed bigint,
    drawn_at timestamp with time zone,
    drawn_at_sim_clock timestamp with time zone,
    battery_soh_pct numeric,
    battery_chemistry text,
    charge_accept_kw numeric,
    pack_temp_c numeric,
    dcfc_safe boolean,
    dcfc_block_reason text,
    cell_balance_due_at timestamp with time zone,
    min_ready_soc_pct numeric,
    exterior_soil_level numeric,
    cabin_condition text,
    last_wash_at timestamp with time zone,
    last_deep_clean_at timestamp with time zone,
    wash_interval_h numeric,
    deep_clean_interval_h numeric,
    calib_interval_h numeric,
    calib_interval_km numeric,
    last_calibration_at timestamp with time zone,
    sensor_health_pct numeric,
    software_version text,
    sw_target_version text,
    sw_update_size_mb integer,
    odometer_km numeric,
    pm_interval_km numeric,
    km_at_last_pm numeric,
    last_pm_at timestamp with time zone,
    open_fault_codes text[],
    worst_fault_severity smallint,
    tire_tread_mm numeric,
    tire_rotation_due_km numeric,
    brake_wear_pct numeric,
    next_deploy_at timestamp with time zone,
    priority_class text,
    assigned_shift text,
    item_retrieval_pending boolean,
    item_reported_at timestamp with time zone,
    item_description text,
    updated_at timestamp with time zone,
    wear_km_applied numeric,
    wear_km_applied_run uuid
);
-- @@ table public.fwd2_pre909_runrow
CREATE TABLE public.fwd2_pre909_runrow (
    sim_run_id uuid,
    sim_run_seq bigint,
    scenario_id uuid,
    scenario_code text,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    last_tick_at timestamp with time zone,
    next_tick_due_at timestamp with time zone,
    sim_clock_start timestamp with time zone,
    sim_clock_current timestamp with time zone,
    sim_clock_end timestamp with time zone,
    time_scale numeric,
    tick_interval_seconds integer,
    tick_count integer,
    depot_id uuid,
    random_seed bigint,
    status text,
    failure_reason text,
    events_generated bigint,
    vehicles_simulated integer,
    charge_sessions integer,
    tasks_completed integer,
    anomalies_injected integer,
    emergencies_triggered integer,
    rule_evaluations bigint,
    rule_failures bigint,
    predictions_emitted bigint,
    recommendations_made bigint,
    timeline_cursor integer,
    validation_status text,
    validation_notes text,
    validation_assertions jsonb,
    run_by text,
    notes text,
    payload jsonb,
    policy text,
    ab_group_id uuid,
    crn_streams jsonb,
    demo_speed_x numeric
);
-- @@ table public.fwd2_profile_samples
CREATE TABLE public.fwd2_profile_samples (
    sampled_at timestamp with time zone NOT NULL,
    sim_min numeric,
    vehicle_id uuid,
    exterior_soil_level numeric,
    cabin_condition text,
    last_wash_at timestamp with time zone,
    last_deep_clean_at timestamp with time zone,
    last_calibration_at timestamp with time zone,
    last_pm_at timestamp with time zone,
    odometer_km numeric,
    wear_km_applied numeric,
    wear_km_applied_run uuid,
    worst_fault_severity integer,
    item_retrieval_pending boolean,
    software_version text,
    updated_at timestamp with time zone
);
-- @@ table public.fwd2_soil_laundering_evidence
CREATE TABLE public.fwd2_soil_laundering_evidence (
    vehicle_id uuid,
    boot_soil numeric,
    now_soil numeric,
    wear_soil_index numeric,
    boot_cabin text,
    now_cabin text,
    crossed_out_of_wash_bands boolean,
    had_wash_or_detail_bay boolean,
    done_svcs text,
    done_bookings text,
    captured_at timestamp with time zone
);
-- @@ table public.fwd2_urgency_samples
CREATE TABLE public.fwd2_urgency_samples (
    sample_id bigint NOT NULL,
    sampled_at timestamp with time zone NOT NULL,
    sim_run_id uuid,
    sim_clock timestamp with time zone,
    sim_min numeric,
    tick_count integer,
    n_ok integer,
    n_due_soon integer,
    n_due integer,
    n_overdue integer,
    n_critical integer,
    n_total integer,
    n_overdue_or_critical integer,
    pct_overdue_or_critical numeric,
    note text
);
-- @@ table public.fwd3_bay_exits
CREATE TABLE public.fwd3_bay_exits (
    vehicle_id uuid,
    from_state text,
    occurred_at timestamp with time zone,
    event_seq bigint
);
-- @@ table public.fwd3_gate_probe
CREATE TABLE public.fwd3_gate_probe (
    step text,
    veh uuid,
    soil numeric,
    n_faults integer,
    sev integer,
    at timestamp with time zone
);
-- @@ table public.fwd3_pgss_t0
CREATE TABLE public.fwd3_pgss_t0 (
    snap_at timestamp with time zone,
    queryid bigint,
    calls bigint,
    total_exec_time double precision,
    rows bigint,
    q text
);
-- @@ table public.fwd3_postboot_profile
CREATE TABLE public.fwd3_postboot_profile (
    vehicle_id uuid,
    exterior_soil_level numeric,
    last_wash_at timestamp with time zone,
    last_deep_clean_at timestamp with time zone,
    worst_fault_severity smallint,
    open_fault_codes text[],
    n_faults integer,
    cabin_condition text,
    drawn_for_run uuid,
    drawn_at timestamp with time zone,
    updated_at timestamp with time zone,
    snap_at timestamp with time zone
);
-- @@ table public.fwd3_postboot_wear
CREATE TABLE public.fwd3_postboot_wear (
    vehicle_id uuid,
    sim_run_id uuid,
    soil_index numeric,
    open_dtc_count integer,
    worst_open_dtc_rank smallint,
    updated_at timestamp with time zone,
    snap_at timestamp with time zone
);
-- @@ table public.fwd3_postrun_atoms
CREATE TABLE public.fwd3_postrun_atoms (
    vehicle_id uuid,
    visit_id uuid,
    visit_status text,
    svc text,
    atom_status text,
    done_at text,
    atom jsonb
);
-- @@ table public.fwd3_postrun_bay_exits
CREATE TABLE public.fwd3_postrun_bay_exits (
    vehicle_id uuid,
    from_state text,
    occurred_at timestamp with time zone,
    event_seq bigint
);
-- @@ table public.fwd3_postrun_bookings
CREATE TABLE public.fwd3_postrun_bookings (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    booked_at_sim timestamp with time zone
);
-- @@ table public.fwd3_postrun_legs
CREATE TABLE public.fwd3_postrun_legs (
    leg_id uuid,
    itinerary_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    seq integer,
    leg_type text,
    from_stall_id uuid,
    to_stall_id uuid,
    planned_start_sim timestamp with time zone,
    planned_end_sim timestamp with time zone,
    planned_duration_s integer,
    duration_basis jsonb,
    actual_start_sim timestamp with time zone,
    actual_end_sim timestamp with time zone,
    status text,
    deviation_s integer,
    created_at timestamp with time zone
);
-- @@ table public.fwd3_postrun_profile
CREATE TABLE public.fwd3_postrun_profile (
    vehicle_id uuid,
    exterior_soil_level numeric,
    last_wash_at timestamp with time zone,
    last_deep_clean_at timestamp with time zone,
    worst_fault_severity smallint,
    open_fault_codes text[],
    n_faults integer,
    cabin_condition text,
    updated_at timestamp with time zone,
    snap_at timestamp with time zone
);
-- @@ table public.fwd3_postrun_stats
CREATE TABLE public.fwd3_postrun_stats (
    snap_at timestamp with time zone,
    db_bytes bigint,
    events_total bigint,
    events_run bigint,
    events_bytes bigint
);
-- @@ table public.fwd3_postrun_wear
CREATE TABLE public.fwd3_postrun_wear (
    vehicle_id uuid,
    sim_run_id uuid,
    soil_index numeric,
    open_dtc_count integer,
    worst_open_dtc_rank smallint,
    updated_at timestamp with time zone
);
-- @@ table public.fwd3_prerun_cron
CREATE TABLE public.fwd3_prerun_cron (
    jobid bigint,
    schedule text,
    active boolean,
    command text,
    snap_at timestamp with time zone
);
-- @@ table public.fwd3_prerun_profile
CREATE TABLE public.fwd3_prerun_profile (
    vehicle_id uuid,
    profile_version text,
    drawn_for_run uuid,
    drawn_seed bigint,
    drawn_at timestamp with time zone,
    drawn_at_sim_clock timestamp with time zone,
    battery_soh_pct numeric,
    battery_chemistry text,
    charge_accept_kw numeric,
    pack_temp_c numeric,
    dcfc_safe boolean,
    dcfc_block_reason text,
    cell_balance_due_at timestamp with time zone,
    min_ready_soc_pct numeric,
    exterior_soil_level numeric,
    cabin_condition text,
    last_wash_at timestamp with time zone,
    last_deep_clean_at timestamp with time zone,
    wash_interval_h numeric,
    deep_clean_interval_h numeric,
    calib_interval_h numeric,
    calib_interval_km numeric,
    last_calibration_at timestamp with time zone,
    sensor_health_pct numeric,
    software_version text,
    sw_target_version text,
    sw_update_size_mb integer,
    odometer_km numeric,
    pm_interval_km numeric,
    km_at_last_pm numeric,
    last_pm_at timestamp with time zone,
    open_fault_codes text[],
    worst_fault_severity smallint,
    tire_tread_mm numeric,
    tire_rotation_due_km numeric,
    brake_wear_pct numeric,
    next_deploy_at timestamp with time zone,
    priority_class text,
    assigned_shift text,
    item_retrieval_pending boolean,
    item_reported_at timestamp with time zone,
    item_description text,
    updated_at timestamp with time zone,
    wear_km_applied numeric,
    wear_km_applied_run uuid,
    snap_at timestamp with time zone
);
-- @@ table public.fwd3_prerun_retention_state
CREATE TABLE public.fwd3_prerun_retention_state (
    table_name text,
    cursor_block bigint,
    pass_deleted bigint,
    updated_at timestamp with time zone,
    snap_at timestamp with time zone
);
-- @@ table public.fwd3_prerun_stats
CREATE TABLE public.fwd3_prerun_stats (
    snap_at timestamp with time zone,
    db_bytes bigint,
    events bigint,
    events_bytes bigint,
    runs bigint
);
-- @@ table public.fwd3_prerun_wear
CREATE TABLE public.fwd3_prerun_wear (
    vehicle_id uuid,
    sim_run_id uuid,
    drive_km_total numeric,
    drive_hours_total numeric,
    backfilled_km numeric,
    backfilled_hours numeric,
    km_at_last_pm numeric,
    hours_at_last_calibration numeric,
    calibrated_at timestamp with time zone,
    soil_index numeric,
    cabin_litter_events integer,
    open_dtc_count integer,
    worst_open_dtc_rank smallint,
    last_advanced_tick bigint,
    last_advanced_sim_clock timestamp with time zone,
    km_per_tick_ema numeric,
    drive_ticks_observed integer,
    updated_at timestamp with time zone,
    snap_at timestamp with time zone
);
-- @@ table public.fwd3_tick_probe
CREATE TABLE public.fwd3_tick_probe (
    i integer,
    secs numeric,
    at timestamp with time zone
);
-- @@ table public.fwd4_pre_counts
CREATE TABLE public.fwd4_pre_counts (
    t text,
    n bigint
);
-- @@ table public.g19_fn_before
CREATE TABLE public.g19_fn_before (
    funcid oid,
    schemaname name,
    funcname name,
    calls bigint,
    total_time double precision,
    self_time double precision,
    snap_at timestamp with time zone
);
-- @@ table public.g19_fp_after
CREATE TABLE public.g19_fp_after (
    pass integer,
    ms numeric
);
-- @@ table public.g19_idle_before
CREATE TABLE public.g19_idle_before (
    relid oid,
    relname name,
    seq_scan bigint,
    seq_tup_read bigint,
    idx_scan bigint,
    heap_blks_read bigint,
    heap_blks_hit bigint,
    snap_at timestamp with time zone
);
-- @@ table public.g19_io_before
CREATE TABLE public.g19_io_before (
    relid oid,
    relname name,
    heap_blks_read bigint,
    heap_blks_hit bigint,
    idx_blks_read bigint,
    idx_blks_hit bigint,
    snap_at timestamp with time zone
);
-- @@ table public.g19_io_pref
CREATE TABLE public.g19_io_pref (
    relid oid,
    relname name,
    heap_blks_read bigint,
    heap_blks_hit bigint,
    idx_blks_read bigint,
    idx_blks_hit bigint,
    snap_at timestamp with time zone
);
-- @@ table public.g19_microbench
CREATE TABLE public.g19_microbench (
    pass integer,
    stalls integer,
    coalesce_ms numeric,
    sargable_ms numeric
);
-- @@ table public.g19_seq_before
CREATE TABLE public.g19_seq_before (
    relid oid,
    relname name,
    seq_scan bigint,
    seq_tup_read bigint,
    idx_scan bigint,
    idx_tup_fetch bigint,
    n_tup_ins bigint,
    n_tup_upd bigint,
    snap_at timestamp with time zone
);
-- @@ table public.g19_stmt_before
CREATE TABLE public.g19_stmt_before (
    queryid bigint,
    calls bigint,
    total_exec_time double precision,
    rows bigint,
    shared_blks_hit bigint,
    shared_blks_read bigint,
    query text,
    snap_at timestamp with time zone
);
-- @@ table public.integration_health
CREATE TABLE public.integration_health (
    id uuid NOT NULL,
    integration_name text NOT NULL,
    platform public.av_platform,
    endpoint text NOT NULL,
    circuit_state public.circuit_breaker_state NOT NULL,
    consecutive_failures integer NOT NULL,
    failure_threshold integer NOT NULL,
    last_success_at timestamp with time zone,
    last_failure_at timestamp with time zone,
    last_error_message text,
    last_error_code text,
    avg_response_ms integer NOT NULL,
    p95_response_ms integer NOT NULL,
    p99_response_ms integer NOT NULL,
    success_rate_1h numeric(5,2) NOT NULL,
    success_rate_24h numeric(5,2) NOT NULL,
    total_requests_24h integer NOT NULL,
    circuit_opened_at timestamp with time zone,
    circuit_half_open_at timestamp with time zone,
    next_retry_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.leg_why_smoke_2026_08_02
CREATE TABLE public.leg_why_smoke_2026_08_02 (
    case_no integer,
    case_name text,
    booking_id uuid,
    vehicle_id uuid,
    stall_code text,
    purpose text,
    leg_id uuid,
    leg_source text,
    leg_type text,
    leg_status text,
    visit_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    why text,
    captured_at timestamp with time zone
);
-- @@ table public.maintenance_log
CREATE TABLE public.maintenance_log (
    id uuid NOT NULL,
    maintenance_schedule_id uuid,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    category public.maintenance_category NOT NULL,
    performed_at timestamp with time zone NOT NULL,
    performed_by_user_id uuid,
    stall_id uuid,
    duration_minutes integer,
    findings text,
    actions_taken text,
    parts_used jsonb,
    photos jsonb,
    pass_fail text,
    follow_up_required boolean,
    follow_up_notes text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.maintenance_schedules
CREATE TABLE public.maintenance_schedules (
    id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    category public.maintenance_category NOT NULL,
    frequency public.maintenance_frequency NOT NULL,
    description text,
    preferred_day_of_week jsonb,
    preferred_time_start time without time zone,
    preferred_time_end time without time zone,
    estimated_duration_minutes integer NOT NULL,
    last_performed_at timestamp with time zone,
    last_performed_by uuid,
    next_scheduled_date date,
    next_scheduled_time timestamp with time zone,
    assigned_stall_id uuid,
    trigger_miles_interval integer,
    last_trigger_miles integer,
    current_miles integer,
    status text NOT NULL,
    is_auto_scheduled boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.mig0003_decoded
CREATE TABLE public.mig0003_decoded (
    id integer NOT NULL,
    sql_text text
);
-- @@ table public.mig0003_smoke
CREATE TABLE public.mig0003_smoke (
    k text NOT NULL,
    v text
);
-- @@ table public.mig0003_smoke_receipt_bookings
CREATE TABLE public.mig0003_smoke_receipt_bookings (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    booked_at_sim timestamp with time zone
);
-- @@ table public.mig0003_smoke_receipt_decisions
CREATE TABLE public.mig0003_smoke_receipt_decisions (
    decision_id uuid,
    decision_seq bigint,
    decision_request_id uuid,
    sim_run_id uuid,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    depot_id uuid,
    snapshot_id uuid,
    action_context text,
    resolved_action_context text,
    entity_type text,
    entity_id uuid,
    gate text,
    failed_gate text,
    context_frame jsonb,
    shield_delta jsonb,
    proposed_action jsonb,
    enacted_action jsonb,
    overridden boolean,
    override_rule_code text,
    override_rule_codes text[],
    override_reason text,
    override_id uuid,
    rule_results jsonb,
    shield_verdict jsonb,
    shield_disarm_flags jsonb,
    safe_default_taken boolean,
    safe_default_shielded boolean,
    deploy_readiness text,
    handshake_outcome text,
    committed_kw_before numeric,
    committed_kw_after numeric,
    propose_latency_ms integer,
    shield_latency_ms integer,
    enact_latency_ms integer,
    total_latency_ms integer,
    outcome_status text,
    l2_engine text,
    confidence numeric,
    created_at timestamp with time zone
);
-- @@ table public.mig0004_smoke_receipt
CREATE TABLE public.mig0004_smoke_receipt (
    phase text,
    captured_at timestamp with time zone,
    vehicle_id uuid,
    profile_version text,
    drawn_for_run uuid,
    drawn_seed bigint,
    drawn_at timestamp with time zone,
    drawn_at_sim_clock timestamp with time zone,
    battery_soh_pct numeric,
    battery_chemistry text,
    charge_accept_kw numeric,
    pack_temp_c numeric,
    dcfc_safe boolean,
    dcfc_block_reason text,
    cell_balance_due_at timestamp with time zone,
    min_ready_soc_pct numeric,
    exterior_soil_level numeric,
    cabin_condition text,
    last_wash_at timestamp with time zone,
    last_deep_clean_at timestamp with time zone,
    wash_interval_h numeric,
    deep_clean_interval_h numeric,
    calib_interval_h numeric,
    calib_interval_km numeric,
    last_calibration_at timestamp with time zone,
    sensor_health_pct numeric,
    software_version text,
    sw_target_version text,
    sw_update_size_mb integer,
    odometer_km numeric,
    pm_interval_km numeric,
    km_at_last_pm numeric,
    last_pm_at timestamp with time zone,
    open_fault_codes text[],
    worst_fault_severity smallint,
    tire_tread_mm numeric,
    tire_rotation_due_km numeric,
    brake_wear_pct numeric,
    next_deploy_at timestamp with time zone,
    priority_class text,
    assigned_shift text,
    item_retrieval_pending boolean,
    item_reported_at timestamp with time zone,
    item_description text,
    updated_at timestamp with time zone,
    wear_km_applied numeric,
    wear_km_applied_run uuid,
    vehicle_state_at_capture text
);
-- @@ table public.mig0006_cron_prestate
CREATE TABLE public.mig0006_cron_prestate (
    jobid bigint,
    jobname text,
    schedule text,
    active boolean,
    captured_at timestamp with time zone
);
-- @@ table public.mig0006_drift_out
CREATE TABLE public.mig0006_drift_out (
    ord integer,
    severity text,
    check_name text,
    detail text
);
-- @@ table public.mig0006_drift_src
CREATE TABLE public.mig0006_drift_src (
    part integer NOT NULL,
    body text NOT NULL
);
-- @@ table public.mig0006_runrows
CREATE TABLE public.mig0006_runrows (
    tbl text,
    sim_run_id uuid,
    n bigint
);
-- @@ table public.mig0006_smoke
CREATE TABLE public.mig0006_smoke (
    label text NOT NULL,
    event_id uuid,
    sim_run_id uuid,
    note text
);
-- @@ table public.mig0006_source
CREATE TABLE public.mig0006_source (
    part integer NOT NULL,
    body text NOT NULL
);
-- @@ table public.mig0009_immutability_test
CREATE TABLE public.mig0009_immutability_test (
    result text,
    sqlstate text,
    msg text
);
-- @@ table public.mig0009_pre_dispatches
CREATE TABLE public.mig0009_pre_dispatches (
    dispatch_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    fleet_operator_id uuid,
    dispatched_at timestamp with time zone,
    scheduled_return_at timestamp with time zone,
    actual_return_at timestamp with time zone,
    planned_duration_min numeric,
    actual_duration_min numeric,
    arrival_jitter_min numeric,
    soc_at_dispatch_pct numeric,
    soc_at_return_pct numeric,
    energy_consumed_kwh numeric,
    miles_driven numeric,
    return_trigger text,
    return_state text,
    status text,
    data_source text,
    created_at timestamp with time zone,
    returning_started_at timestamp with time zone,
    return_eta_minutes numeric,
    return_evidence jsonb,
    heartbeat_count integer,
    planned_return_at timestamp with time zone,
    eta_refreshed_at timestamp with time zone,
    eta_source text
);
-- @@ table public.mig0009_pre_visit_needs
CREATE TABLE public.mig0009_pre_visit_needs (
    visit_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone,
    visit_key text,
    archetype text,
    urgency text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb,
    status text,
    source text,
    meta jsonb,
    created_at timestamp with time zone
);
-- @@ table public.mig0009_prerun_protect
CREATE TABLE public.mig0009_prerun_protect (
    captured_real timestamp with time zone,
    db_bytes bigint,
    events_n bigint,
    events_bytes bigint,
    dispatches_n bigint,
    cron_active bigint
);
-- @@ table public.mig0009_run920_dispatches
CREATE TABLE public.mig0009_run920_dispatches (
    dispatch_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    fleet_operator_id uuid,
    dispatched_at timestamp with time zone,
    scheduled_return_at timestamp with time zone,
    actual_return_at timestamp with time zone,
    planned_duration_min numeric,
    actual_duration_min numeric,
    arrival_jitter_min numeric,
    soc_at_dispatch_pct numeric,
    soc_at_return_pct numeric,
    energy_consumed_kwh numeric,
    miles_driven numeric,
    return_trigger text,
    return_state text,
    status text,
    data_source text,
    created_at timestamp with time zone,
    returning_started_at timestamp with time zone,
    return_eta_minutes numeric,
    return_evidence jsonb,
    heartbeat_count integer,
    planned_return_at timestamp with time zone,
    eta_refreshed_at timestamp with time zone,
    eta_source text
);
-- @@ table public.mig0009_run920_exits
CREATE TABLE public.mig0009_run920_exits (
    vid uuid,
    occurred_at timestamp with time zone,
    bay text,
    credited jsonb,
    capable jsonb,
    suppressed integer
);
-- @@ table public.mig0020_policy_prestate
CREATE TABLE public.mig0020_policy_prestate (
    scope_type text,
    scope_id uuid,
    param_key text,
    param_value numeric,
    updated_by text,
    updated_at timestamp with time zone,
    captured_at timestamp with time zone
);
-- @@ table public.mig0020_prestate
CREATE TABLE public.mig0020_prestate (
    captured_at timestamp with time zone NOT NULL,
    object text NOT NULL,
    definition text NOT NULL
);
-- @@ table public.model_parameters
CREATE TABLE public.model_parameters (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    parameter_group text NOT NULL,
    parameters jsonb NOT NULL,
    is_active boolean NOT NULL,
    version integer NOT NULL,
    last_tuned_at timestamp with time zone,
    tuned_by text,
    performance_metrics jsonb,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.model_tuning_runs
CREATE TABLE public.model_tuning_runs (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    parameter_group text NOT NULL,
    trigger_type text NOT NULL,
    parameters_before jsonb NOT NULL,
    parameters_after jsonb NOT NULL,
    parameter_diffs jsonb NOT NULL,
    accuracy_before numeric(5,4) NOT NULL,
    accuracy_after numeric(5,4),
    samples_evaluated integer NOT NULL,
    evaluation_window_hours integer NOT NULL,
    tuning_method text NOT NULL,
    status text NOT NULL,
    improvement_pct numeric(6,3),
    confirmed_at timestamp with time zone,
    rolled_back_at timestamp with time zone,
    rollback_reason text,
    notes text,
    error_message text,
    duration_ms integer,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.model_versions
CREATE TABLE public.model_versions (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    parameter_group text NOT NULL,
    version_tag text NOT NULL,
    version_number integer NOT NULL,
    parameters jsonb NOT NULL,
    parameters_hash text NOT NULL,
    parent_version_id uuid,
    source text NOT NULL,
    tuning_run_id uuid,
    status text NOT NULL,
    approved_by text,
    approved_at timestamp with time zone,
    promoted_to_active_at timestamp with time zone,
    archived_at timestamp with time zone,
    accuracy_metrics jsonb,
    promotion_notes text,
    created_at timestamp with time zone NOT NULL,
    created_by text,
    prediction_type text,
    artifact_format text,
    artifact_storage_path text,
    artifact_size_bytes bigint,
    artifact_sha256 text,
    serving_runtime text,
    feature_schema jsonb,
    output_schema jsonb,
    deployment_stage text,
    oem_id uuid,
    vehicle_class text,
    training_metadata jsonb,
    training_run_id uuid,
    shadow_traffic_pct numeric,
    expected_latency_p95_ms integer
);
-- @@ table public.notifications
CREATE TABLE public.notifications (
    id uuid NOT NULL,
    depot_id uuid,
    fleet_operator_id uuid,
    retail_member_id uuid,
    staff_user_id uuid,
    channel public.notification_channel NOT NULL,
    status public.notification_status NOT NULL,
    event_type text NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    action_url text,
    vehicle_id uuid,
    schedule_task_id uuid,
    exception_id uuid,
    webhook_url text,
    webhook_payload jsonb,
    webhook_response_code integer,
    webhook_attempts integer,
    scheduled_for timestamp with time zone,
    sent_at timestamp with time zone,
    delivered_at timestamp with time zone,
    read_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ocpp_meter_values
CREATE TABLE public.ocpp_meter_values (
    id uuid NOT NULL,
    ocpp_session_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    charge_point_id text NOT NULL,
    evse_id integer NOT NULL,
    seq_no integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    soc_percent integer,
    power_import_kw numeric(8,2),
    energy_import_kwh numeric(10,3),
    voltage_v numeric(6,1),
    current_a numeric(6,1),
    temperature_c numeric(5,1),
    raw_sampled_values jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ocpp_sessions
CREATE TABLE public.ocpp_sessions (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    stall_id uuid NOT NULL,
    vehicle_id uuid,
    schedule_task_id uuid,
    charge_point_id text NOT NULL,
    transaction_id text NOT NULL,
    evse_id integer NOT NULL,
    connector_id integer NOT NULL,
    status public.ocpp_session_status NOT NULL,
    started_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    soc_start integer,
    soc_end integer,
    energy_delivered_kwh numeric(10,3) NOT NULL,
    peak_power_kw numeric(8,2) NOT NULL,
    avg_power_kw numeric(8,2) NOT NULL,
    connector_temp_c_max numeric(5,1),
    connector_temp_c_final numeric(5,1),
    ambient_temp_c numeric(5,1),
    stopped_reason text,
    id_token text,
    meter_values_count integer NOT NULL,
    last_meter_value jsonb,
    charging_profile_applied boolean,
    max_rate_limit_kw numeric(8,2),
    fault_count integer,
    last_fault_message text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    sim_run_id uuid
);
-- @@ table public.ottoq_0249_start_log
CREATE TABLE public.ottoq_0249_start_log (
    id bigint NOT NULL,
    at timestamp with time zone NOT NULL,
    phase text NOT NULL,
    payload jsonb NOT NULL
);
-- @@ table public.ottoq_ab_runs
CREATE TABLE public.ottoq_ab_runs (
    ab_run_id uuid NOT NULL,
    ab_group_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    seed bigint NOT NULL,
    policy text NOT NULL,
    scenario_code text,
    ticks bigint,
    decisions_total integer,
    enacted_total integer,
    deploys_total integer,
    fleet_ready_pct numeric,
    safety_violations integer,
    safety_critical_violations integer,
    overrides_total integer,
    avg_decision_latency_ms numeric,
    energy_peak_kw numeric,
    charge_sessions integer,
    incidents_open integer,
    scored_at timestamp with time zone NOT NULL,
    productive_deploys integer,
    unsafe_deploys integer,
    vehicles_turned_around integer,
    gate_backlog integer,
    throughput_per_hr numeric,
    peak_demand_pct_of_cap numeric,
    trips_completed integer,
    vehicles_cycled integer,
    median_turnaround_min numeric,
    ready_or_deployed_pct numeric
);
-- @@ table public.ottoq_agent_call_ledger
CREATE TABLE public.ottoq_agent_call_ledger (
    call_id bigint NOT NULL,
    principal_id uuid,
    principal_name text,
    transport text NOT NULL,
    tool text NOT NULL,
    http_method text,
    path text,
    ok boolean NOT NULL,
    http_status integer,
    error_code text,
    latency_ms integer,
    request_id uuid,
    depot_id uuid,
    fleet_operator_id uuid,
    detail jsonb NOT NULL,
    called_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_agent_charge_orders
CREATE TABLE public.ottoq_agent_charge_orders (
    order_id bigint NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid,
    board_tick bigint,
    recorded_tick bigint NOT NULL,
    sim_clock timestamp with time zone,
    chain_id text,
    model text,
    status text NOT NULL,
    n_offered integer NOT NULL,
    n_accepted integer NOT NULL,
    cars jsonb NOT NULL,
    dropped jsonb NOT NULL,
    why text,
    recorded_at timestamp with time zone NOT NULL,
    source_kind text NOT NULL,
    projection jsonb
);
-- @@ table public.ottoq_agent_demo_passcode
CREATE TABLE public.ottoq_agent_demo_passcode (
    depot_id uuid NOT NULL,
    fleet_operator_id uuid NOT NULL,
    passcode_hash text,
    enabled boolean NOT NULL,
    session_minutes integer NOT NULL,
    set_at timestamp with time zone NOT NULL,
    set_by text NOT NULL
);
-- @@ table public.ottoq_agent_pass_evidence
CREATE TABLE public.ottoq_agent_pass_evidence (
    pass_id bigint NOT NULL,
    chain_id text NOT NULL,
    seat text NOT NULL,
    agent_version text NOT NULL,
    sim_run_id uuid,
    depot_id uuid,
    run_by text,
    board_tick bigint,
    trigger_tick bigint,
    recorded_tick bigint,
    sim_clock timestamp with time zone,
    wake jsonb,
    consulted boolean NOT NULL,
    board_text text,
    board_bytes integer GENERATED ALWAYS AS (octet_length(board_text)) STORED,
    board_sha256 text GENERATED ALWAYS AS (public.ottoq_sha256_utf8(board_text)) STORED,
    board_sha256_client text,
    prompt_sha256 text,
    models_requested text[],
    model_answered text,
    response_model text,
    response_id text,
    sampling jsonb,
    usage jsonb,
    attempts jsonb,
    answer jsonb,
    levers jsonb NOT NULL,
    outcome_class text NOT NULL,
    decision_written boolean NOT NULL,
    propose_ms integer,
    total_ms integer,
    recorded_at timestamp with time zone NOT NULL,
    source_kind text NOT NULL
);
-- @@ table public.ottoq_agent_principals
CREATE TABLE public.ottoq_agent_principals (
    principal_id uuid NOT NULL,
    name text NOT NULL,
    kind text NOT NULL,
    depot_id uuid NOT NULL,
    fleet_operator_id uuid,
    capabilities text[] NOT NULL,
    token_hash text NOT NULL,
    token_prefix text NOT NULL,
    status text NOT NULL,
    rate_limit_per_min integer NOT NULL,
    max_pending integer NOT NULL,
    note text,
    created_at timestamp with time zone NOT NULL,
    created_by text NOT NULL,
    last_used_at timestamp with time zone,
    revoked_at timestamp with time zone,
    revoked_reason text,
    origin text NOT NULL,
    display_name text,
    expires_at timestamp with time zone
);
-- @@ table public.ottoq_agent_prompts
CREATE TABLE public.ottoq_agent_prompts (
    prompt_sha256 text NOT NULL,
    agent_version text NOT NULL,
    prompt_text text NOT NULL,
    text_sha256 text GENERATED ALWAYS AS (public.ottoq_sha256_utf8(prompt_text)) STORED,
    first_seen_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_agent_requests
CREATE TABLE public.ottoq_agent_requests (
    request_id uuid NOT NULL,
    principal_id uuid NOT NULL,
    principal_name text NOT NULL,
    principal_kind text NOT NULL,
    depot_id uuid NOT NULL,
    fleet_operator_id uuid,
    sim_run_id uuid,
    sim_clock timestamp with time zone,
    kind text NOT NULL,
    vehicle_id uuid,
    vehicle_label text,
    title text NOT NULL,
    body text,
    payload jsonb NOT NULL,
    priority text NOT NULL,
    idempotency_key text,
    status text NOT NULL,
    decision text,
    decided_by_kind text,
    decided_by_uid uuid,
    decided_by_label text,
    decision_note text,
    decided_at timestamp with time zone,
    engine_door text,
    engine_reply jsonb,
    applied_at timestamp with time zone,
    closed_reason text,
    created_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_anomaly_detectors
CREATE TABLE public.ottoq_anomaly_detectors (
    detector_id uuid NOT NULL,
    detector_code text NOT NULL,
    category text NOT NULL,
    method text NOT NULL,
    target_feature text,
    target_entity_type text NOT NULL,
    observation_source text,
    parameters jsonb NOT NULL,
    anomaly_score_threshold numeric NOT NULL,
    severity_low_threshold numeric,
    severity_high_threshold numeric,
    severity_critical_threshold numeric,
    emit_event boolean NOT NULL,
    create_exception boolean NOT NULL,
    required_resolver_role text,
    title text NOT NULL,
    description text NOT NULL,
    rationale text,
    status text NOT NULL,
    introduced_in text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    observations_total bigint NOT NULL,
    observations_anomalous bigint NOT NULL,
    last_anomaly_at timestamp with time zone,
    last_observation_at timestamp with time zone
);
-- @@ table public.ottoq_anomaly_observations
CREATE TABLE public.ottoq_anomaly_observations (
    observation_id uuid NOT NULL,
    observation_seq bigint NOT NULL,
    detector_id uuid NOT NULL,
    detector_code text NOT NULL,
    observed_at timestamp with time zone NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    feature_name text,
    observed_value jsonb,
    anomaly_score numeric NOT NULL,
    is_anomaly boolean NOT NULL,
    severity text NOT NULL,
    context jsonb NOT NULL,
    event_emitted boolean NOT NULL,
    exception_created boolean NOT NULL,
    linked_event_id uuid,
    exception_id uuid,
    fleet_operator_id uuid,
    depot_id uuid,
    correlation_id uuid
);
-- @@ table public.ottoq_arbiter_assessments
CREATE TABLE public.ottoq_arbiter_assessments (
    assessment_id bigint NOT NULL,
    depot_id uuid NOT NULL,
    assessed_at timestamp with time zone NOT NULL,
    since timestamp with time zone NOT NULL,
    n_graded integer NOT NULL,
    n_decisions integer NOT NULL,
    assessment jsonb NOT NULL,
    improvement_areas jsonb NOT NULL,
    code_md5 text NOT NULL
);
-- @@ table public.ottoq_audit_bundles
CREATE TABLE public.ottoq_audit_bundles (
    bundle_id uuid NOT NULL,
    bundle_seq bigint NOT NULL,
    bundle_code text NOT NULL,
    fleet_operator_id uuid NOT NULL,
    report_ids uuid[] NOT NULL,
    event_id_range_low bigint,
    event_id_range_high bigint,
    window_start timestamp with time zone NOT NULL,
    window_end timestamp with time zone NOT NULL,
    format text NOT NULL,
    storage_path text,
    size_bytes bigint,
    sha256 text NOT NULL,
    signature text NOT NULL,
    signature_key_id text NOT NULL,
    signature_algorithm text NOT NULL,
    manifest jsonb NOT NULL,
    public_verification_url text,
    generated_at timestamp with time zone NOT NULL,
    generated_by_actor_type text,
    generated_by_actor_id text,
    delivered_to text,
    delivered_at timestamp with time zone,
    download_count integer NOT NULL,
    last_downloaded_at timestamp with time zone,
    expires_at timestamp with time zone,
    revoked_at timestamp with time zone,
    revocation_reason text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_audit_reports
CREATE TABLE public.ottoq_audit_reports (
    report_id uuid NOT NULL,
    report_seq bigint NOT NULL,
    report_type text NOT NULL,
    report_subtype text,
    fleet_operator_id uuid,
    depot_id uuid,
    vehicle_id uuid,
    schedule_id uuid,
    window_start timestamp with time zone NOT NULL,
    window_end timestamp with time zone NOT NULL,
    requested_by_actor_type text,
    requested_by_actor_id text,
    requested_at timestamp with time zone NOT NULL,
    generation_started_at timestamp with time zone,
    generation_completed_at timestamp with time zone,
    generation_status text NOT NULL,
    generation_duration_ms integer,
    generation_error text,
    payload jsonb,
    payload_hash text,
    signature text,
    signature_key_id text,
    signature_algorithm text,
    event_count bigint,
    rule_eval_count bigint,
    prediction_count bigint,
    anomaly_count bigint,
    override_count bigint,
    emergency_count bigint,
    visit_count bigint,
    title text,
    description text,
    format text,
    expires_at timestamp with time zone,
    parent_report_id uuid,
    source_event_id uuid,
    audit_trail_complete boolean,
    data_quality_score numeric,
    exclusions jsonb,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_bay_binding_witness
CREATE TABLE public.ottoq_bay_binding_witness (
    witness_id bigint NOT NULL,
    observed_real timestamp with time zone NOT NULL,
    observed_sim timestamp with time zone,
    sim_run_id uuid,
    booking_id uuid,
    vehicle_id uuid,
    stall_id uuid,
    veh_current_stall uuid,
    old_state text,
    new_state text,
    old_source text,
    new_source text,
    purpose text,
    window_start timestamp with time zone,
    window_end timestamp with time zone,
    seated_on_reserved boolean,
    inside_window boolean
);
-- @@ table public.ottoq_benchmark_frames
CREATE TABLE public.ottoq_benchmark_frames (
    id bigint NOT NULL,
    comparison_id uuid NOT NULL,
    policy text NOT NULL,
    tick integer NOT NULL,
    frame jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_bess_units
CREATE TABLE public.ottoq_bess_units (
    bess_id uuid NOT NULL,
    depot_id uuid,
    bess_identifier text NOT NULL,
    vendor text,
    model text,
    capacity_kwh numeric NOT NULL,
    max_charge_kw numeric NOT NULL,
    max_discharge_kw numeric NOT NULL,
    installed_at timestamp with time zone,
    current_soc_pct numeric,
    current_soc_kwh numeric,
    current_temperature_c numeric,
    current_state text NOT NULL,
    current_power_kw numeric,
    current_state_updated_at timestamp with time zone NOT NULL,
    last_heartbeat_at timestamp with time zone,
    soc_min_floor_pct numeric NOT NULL,
    soc_max_ceiling_pct numeric NOT NULL,
    temperature_max_c numeric NOT NULL,
    temperature_min_c numeric NOT NULL,
    last_fault_code text,
    last_fault_at timestamp with time zone,
    last_fault_payload jsonb,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    current_soh_pct numeric,
    current_cycle_count numeric,
    lifetime_kwh_charged numeric,
    lifetime_kwh_discharged numeric,
    chemistry text,
    roundtrip_efficiency_pct numeric,
    auxiliary_load_kw numeric,
    hvac_setpoint_c numeric NOT NULL,
    hvac_rated_ambient_c numeric NOT NULL,
    hvac_rated_min_ambient_c numeric NOT NULL,
    hvac_rated_kw numeric
);
-- @@ table public.ottoq_calibration_correlations
CREATE TABLE public.ottoq_calibration_correlations (
    correlation_id uuid NOT NULL,
    dataset_code text NOT NULL,
    variable_a text NOT NULL,
    variable_b text NOT NULL,
    coefficient numeric NOT NULL,
    method text NOT NULL,
    sample_count bigint,
    fitted_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_calibration_datasets
CREATE TABLE public.ottoq_calibration_datasets (
    dataset_code text NOT NULL,
    source_name text NOT NULL,
    source_org text NOT NULL,
    source_url text,
    license text,
    domain text NOT NULL,
    description text NOT NULL,
    what_it_calibrates text NOT NULL,
    record_count bigint,
    date_range_start date,
    date_range_end date,
    ingested_at timestamp with time zone,
    ingestion_method text,
    ingestion_notes text,
    ingestion_script text,
    raw_sample jsonb,
    status text NOT NULL,
    data_quality_score numeric,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_calibration_distributions
CREATE TABLE public.ottoq_calibration_distributions (
    distribution_id uuid NOT NULL,
    dataset_code text NOT NULL,
    variable_name text NOT NULL,
    segment text NOT NULL,
    quantile_grid numeric[] NOT NULL,
    sample_count bigint NOT NULL,
    mean_value numeric,
    stddev_value numeric,
    min_value numeric,
    max_value numeric,
    median_value numeric,
    best_fit_family text,
    best_fit_parameters jsonb,
    goodness_of_fit jsonb,
    units text,
    hard_min numeric,
    hard_max numeric,
    fitted_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_calibration_metrics
CREATE TABLE public.ottoq_calibration_metrics (
    calibration_id uuid NOT NULL,
    prediction_type text NOT NULL,
    model_version_id uuid,
    computed_at timestamp with time zone NOT NULL,
    window_start timestamp with time zone NOT NULL,
    window_end timestamp with time zone NOT NULL,
    n_predictions bigint,
    n_scored bigint,
    coverage_80 numeric,
    coverage_50 numeric,
    coverage_95 numeric,
    avg_interval_width numeric,
    mae numeric,
    rmse numeric,
    mape numeric,
    r2 numeric,
    directional_accuracy numeric,
    accuracy numeric,
    precision_ numeric,
    recall numeric,
    f1 numeric,
    roc_auc numeric,
    is_well_calibrated boolean,
    calibration_alert text,
    fleet_operator_id uuid,
    depot_id uuid,
    vehicle_class text,
    payload jsonb
);
-- @@ table public.ottoq_calibration_profiles
CREATE TABLE public.ottoq_calibration_profiles (
    profile_id uuid NOT NULL,
    dataset_code text NOT NULL,
    profile_name text NOT NULL,
    profile_kind text NOT NULL,
    profile_data jsonb NOT NULL,
    units text,
    description text,
    normalization text,
    fitted_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_canopy_state
CREATE TABLE public.ottoq_canopy_state (
    canopy_code text NOT NULL,
    depot_id uuid NOT NULL,
    structure_id uuid,
    nameplate_dc_kw numeric NOT NULL,
    nameplate_ac_kw numeric NOT NULL,
    tilt_deg numeric NOT NULL,
    azimuth_deg numeric NOT NULL,
    current_soiling numeric NOT NULL,
    last_rain_clean_at timestamp with time zone,
    last_updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_cert_columns
CREATE TABLE public.ottoq_cert_columns (
    depot_id uuid NOT NULL,
    scenario text NOT NULL,
    seed bigint NOT NULL,
    ticks integer NOT NULL,
    max_age interval NOT NULL,
    enabled boolean NOT NULL,
    note text NOT NULL,
    added_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_cert_lineage
CREATE TABLE public.ottoq_cert_lineage (
    name text NOT NULL,
    forces_recert boolean NOT NULL,
    note text NOT NULL,
    classified_at timestamp with time zone NOT NULL,
    forces_dial_restart boolean
);
-- @@ table public.ottoq_cert_queue
CREATE TABLE public.ottoq_cert_queue (
    id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_cert_queue_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    scenario text NOT NULL,
    seed bigint NOT NULL,
    policy text NOT NULL,
    ab_group uuid NOT NULL,
    ticks integer NOT NULL,
    fault_chargers integer NOT NULL,
    status text NOT NULL,
    error text,
    enqueued_at timestamp with time zone NOT NULL,
    started_at timestamp with time zone,
    finished_at timestamp with time zone
);
-- @@ table public.ottoq_certified_proposers
CREATE TABLE public.ottoq_certified_proposers (
    source text NOT NULL,
    note text NOT NULL,
    added_at timestamp with time zone NOT NULL,
    added_by text NOT NULL
);
-- @@ table public.ottoq_challenger_findings
CREATE TABLE public.ottoq_challenger_findings (
    finding_id bigint NOT NULL,
    sim_run_id uuid,
    depot_id uuid NOT NULL,
    question text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    episode_key text NOT NULL,
    first_seen_sim timestamp with time zone NOT NULL,
    last_seen_sim timestamp with time zone NOT NULL,
    scans_seen integer NOT NULL,
    evidence jsonb NOT NULL,
    peak jsonb NOT NULL,
    counterfactual jsonb NOT NULL,
    status text NOT NULL,
    closed_sim timestamp with time zone,
    realized jsonb,
    grade text,
    graded_at timestamp with time zone,
    proposal_id uuid,
    detected_at timestamp with time zone NOT NULL,
    engine_hash text,
    scan_version text NOT NULL
);
-- @@ table public.ottoq_channel_health
CREATE TABLE public.ottoq_channel_health (
    health_id bigint NOT NULL,
    channel text NOT NULL,
    status text NOT NULL,
    prev_status text,
    reason text NOT NULL,
    observed jsonb NOT NULL,
    sim_run_id uuid,
    checked_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_charge_clock_fits
CREATE TABLE public.ottoq_charge_clock_fits (
    fit_id bigint NOT NULL,
    depot_id uuid NOT NULL,
    model text NOT NULL,
    fitted_at timestamp with time zone NOT NULL,
    evidence_from timestamp with time zone,
    evidence_through timestamp with time zone,
    n_evidence integer NOT NULL,
    n_runs integer NOT NULL,
    usable boolean NOT NULL,
    params jsonb NOT NULL,
    code_md5 text NOT NULL,
    fitted_by text NOT NULL,
    note text
);
-- @@ table public.ottoq_charge_duration_ledger
CREATE TABLE public.ottoq_charge_duration_ledger (
    session_id uuid NOT NULL,
    recorded_at timestamp with time zone NOT NULL,
    source_kind text NOT NULL,
    sim_run_id uuid,
    run_by text,
    tick_interval_seconds integer,
    depot_id uuid,
    stall_id uuid,
    charger_type text,
    charger_kw numeric,
    vehicle_id uuid,
    vehicle_kw numeric,
    battery_kwh numeric,
    soc_start integer,
    soc_end integer,
    ambient_temp_c numeric,
    depot_air_c numeric,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    duration_min numeric,
    energy_delivered_kwh numeric,
    stopped_reason text,
    nominal_min numeric,
    detail jsonb NOT NULL,
    capture_version smallint NOT NULL,
    charge_target_soc numeric,
    visit_target_soc numeric,
    visit_id uuid,
    soc_at_stop numeric,
    booking_id uuid,
    booked_from timestamp with time zone,
    booked_to timestamp with time zone,
    booking_state text,
    booking_source text,
    tick_minutes numeric
);
-- @@ table public.ottoq_charge_fault_fits
CREATE TABLE public.ottoq_charge_fault_fits (
    fit_id bigint NOT NULL,
    depot_id uuid NOT NULL,
    model text NOT NULL,
    fitted_at timestamp with time zone NOT NULL,
    evidence_from timestamp with time zone,
    evidence_through timestamp with time zone,
    n_evidence integer NOT NULL,
    n_runs integer NOT NULL,
    usable boolean NOT NULL,
    params jsonb NOT NULL,
    code_md5 text NOT NULL,
    fitted_by text NOT NULL,
    note text
);
-- @@ table public.ottoq_charge_order_attribution
CREATE TABLE public.ottoq_charge_order_attribution (
    order_id bigint NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid,
    parts text[] NOT NULL,
    subset_values jsonb NOT NULL,
    shapley jsonb NOT NULL,
    verdict_changed boolean NOT NULL,
    code_md5 text NOT NULL,
    computed_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_charge_order_hindsight
CREATE TABLE public.ottoq_charge_order_hindsight (
    order_id bigint NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid,
    sim_clock timestamp with time zone,
    window_min numeric NOT NULL,
    observed_min numeric NOT NULL,
    status text,
    reason text,
    taken boolean NOT NULL,
    decision boolean NOT NULL,
    futures integer,
    wins integer,
    need integer,
    p_win numeric,
    expected jsonb NOT NULL,
    hindsight jsonb NOT NULL,
    outcome text NOT NULL,
    moves text[] NOT NULL,
    forecast jsonb NOT NULL,
    fidelity jsonb NOT NULL,
    realized jsonb NOT NULL,
    code_md5 text NOT NULL,
    graded_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_charge_order_reattributions
CREATE TABLE public.ottoq_charge_order_reattributions (
    order_id bigint NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid,
    parts text[] NOT NULL,
    subset_values jsonb NOT NULL,
    shapley jsonb NOT NULL,
    verdict_changed boolean NOT NULL,
    code_md5 text NOT NULL,
    computed_at timestamp with time zone NOT NULL,
    reattributed_at timestamp with time zone NOT NULL,
    supersedes_code_md5 text NOT NULL,
    defect text NOT NULL,
    detail jsonb NOT NULL
);
-- @@ table public.ottoq_charge_order_regrades
CREATE TABLE public.ottoq_charge_order_regrades (
    order_id bigint NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid,
    sim_clock timestamp with time zone,
    window_min numeric NOT NULL,
    observed_min numeric NOT NULL,
    status text,
    reason text,
    taken boolean NOT NULL,
    decision boolean NOT NULL,
    futures integer,
    wins integer,
    need integer,
    p_win numeric,
    expected jsonb NOT NULL,
    hindsight jsonb NOT NULL,
    outcome text NOT NULL,
    moves text[] NOT NULL,
    forecast jsonb NOT NULL,
    fidelity jsonb NOT NULL,
    realized jsonb NOT NULL,
    code_md5 text NOT NULL,
    graded_at timestamp with time zone NOT NULL,
    regraded_at timestamp with time zone NOT NULL,
    supersedes_code_md5 text NOT NULL,
    defect text NOT NULL,
    detail jsonb NOT NULL
);
-- @@ table public.ottoq_charge_order_snapshots
CREATE TABLE public.ottoq_charge_order_snapshots (
    order_id bigint NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid,
    sim_clock timestamp with time zone,
    seed text NOT NULL,
    futures integer NOT NULL,
    win_frac numeric NOT NULL,
    state jsonb NOT NULL,
    agent_order jsonb NOT NULL,
    code_md5 text NOT NULL,
    recorded_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_charge_window_calibration
CREATE TABLE public.ottoq_charge_window_calibration (
    calibration_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_charge_window_calibration_calibration_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    fitted_at timestamp with time zone NOT NULL,
    depot_id uuid NOT NULL,
    method text NOT NULL,
    alpha numeric NOT NULL,
    c0 numeric NOT NULL,
    band_edges_c numeric[] NOT NULL,
    min_group_n integer NOT NULL,
    min_run_minutes integer NOT NULL,
    evidence_through timestamp with time zone NOT NULL,
    code_md5 jsonb NOT NULL,
    source_runs text[] NOT NULL,
    n_judged integer NOT NULL,
    cells jsonb NOT NULL,
    loro jsonb NOT NULL,
    note text
);
-- @@ table public.ottoq_cil_adoptions
CREATE TABLE public.ottoq_cil_adoptions (
    adoption_id uuid NOT NULL,
    sim_run_id uuid,
    depot_id uuid,
    decided_at timestamp with time zone,
    adopted boolean,
    plan_label text,
    params jsonb,
    score_current numeric,
    score_adopted numeric,
    source text,
    rationale text,
    eval jsonb
);
-- @@ table public.ottoq_command_actor_registry
CREATE TABLE public.ottoq_command_actor_registry (
    actor text NOT NULL,
    kind text NOT NULL,
    note text,
    registered_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_comms_messages
CREATE TABLE public.ottoq_comms_messages (
    msg_id uuid NOT NULL,
    sim_run_id uuid,
    vehicle_id uuid,
    correlation_id uuid,
    direction text NOT NULL,
    topic text NOT NULL,
    msg_type text NOT NULL,
    qos smallint NOT NULL,
    header jsonb NOT NULL,
    payload jsonb NOT NULL,
    status text NOT NULL,
    latency_ms integer,
    sim_clock_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_counterfactuals
CREATE TABLE public.ottoq_counterfactuals (
    counterfactual_id uuid NOT NULL,
    counterfactual_seq bigint NOT NULL,
    source_kind text NOT NULL,
    source_id uuid NOT NULL,
    source_event_id uuid,
    source_correlation_id uuid,
    ran_at timestamp with time zone NOT NULL,
    source_decision_at timestamp with time zone,
    scenario_label text NOT NULL,
    scenario_description text,
    alternate_inputs jsonb NOT NULL,
    alternate_model_version_id uuid,
    alternate_parameters jsonb,
    actual_outcome jsonb,
    counterfactual_outcome jsonb,
    outcome_kind text,
    actual_value numeric,
    counterfactual_value numeric,
    delta numeric,
    delta_unit text,
    delta_direction text,
    hypothesis_supported boolean,
    effect_size numeric,
    confidence_interval jsonb,
    notes text,
    fleet_operator_id uuid,
    depot_id uuid,
    vehicle_id uuid,
    status text NOT NULL,
    ran_by_actor_type text,
    ran_by_actor_id text,
    payload jsonb
);
-- @@ table public.ottoq_cuopt_deferrals
CREATE TABLE public.ottoq_cuopt_deferrals (
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    state text NOT NULL,
    armed_at_tick bigint,
    armed_at_sim timestamp with time zone,
    armed_at_real timestamp with time zone,
    spent_at_tick bigint,
    cleared_at_tick bigint,
    net_request_id bigint,
    defer_count integer NOT NULL
);
-- @@ table public.ottoq_cuopt_fire_log
CREATE TABLE public.ottoq_cuopt_fire_log (
    sim_run_id uuid NOT NULL,
    fired_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_data_drift_metrics
CREATE TABLE public.ottoq_data_drift_metrics (
    drift_id uuid NOT NULL,
    feature_name text NOT NULL,
    scope text NOT NULL,
    scope_id text,
    computed_at timestamp with time zone NOT NULL,
    reference_window_start timestamp with time zone NOT NULL,
    reference_window_end timestamp with time zone NOT NULL,
    current_window_start timestamp with time zone NOT NULL,
    current_window_end timestamp with time zone NOT NULL,
    psi numeric,
    kl_divergence numeric,
    js_divergence numeric,
    ks_statistic numeric,
    ks_pvalue numeric,
    wasserstein numeric,
    current_mean numeric,
    current_stddev numeric,
    current_p50 numeric,
    current_p95 numeric,
    current_null_pct numeric,
    current_n bigint,
    drift_detected boolean,
    drift_severity text,
    retraining_triggered boolean NOT NULL,
    alert_emitted boolean NOT NULL,
    payload jsonb
);
-- @@ table public.ottoq_decision_snapshots
CREATE TABLE public.ottoq_decision_snapshots (
    snapshot_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    tick_seq bigint NOT NULL,
    depot_id uuid NOT NULL,
    captured_at timestamp with time zone NOT NULL,
    sim_clock timestamp with time zone NOT NULL,
    content_hash text NOT NULL,
    frame jsonb NOT NULL,
    frame_counts jsonb NOT NULL,
    hash_algo smallint
);
-- @@ table public.ottoq_decisions
CREATE TABLE public.ottoq_decisions (
    decision_id uuid NOT NULL,
    decision_seq bigint NOT NULL,
    decision_request_id uuid,
    sim_run_id uuid NOT NULL,
    tick_seq bigint NOT NULL,
    sim_clock timestamp with time zone,
    depot_id uuid,
    snapshot_id uuid,
    action_context text NOT NULL,
    resolved_action_context text,
    entity_type text,
    entity_id uuid,
    gate text,
    failed_gate text,
    context_frame jsonb,
    shield_delta jsonb,
    proposed_action jsonb,
    enacted_action jsonb,
    overridden boolean NOT NULL,
    override_rule_code text,
    override_rule_codes text[],
    override_reason text,
    override_id uuid,
    rule_results jsonb NOT NULL,
    shield_verdict jsonb,
    shield_disarm_flags jsonb NOT NULL,
    safe_default_taken boolean NOT NULL,
    safe_default_shielded boolean,
    deploy_readiness text,
    handshake_outcome text,
    committed_kw_before numeric,
    committed_kw_after numeric,
    propose_latency_ms integer,
    shield_latency_ms integer,
    enact_latency_ms integer,
    total_latency_ms integer,
    outcome_status text NOT NULL,
    l2_engine text,
    confidence numeric,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_deploy_log
CREATE TABLE public.ottoq_deploy_log (
    deploy_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    policy text,
    sim_clock timestamp with time zone,
    soc_at_deploy numeric,
    floor_at_deploy numeric,
    is_productive boolean,
    from_state text,
    to_state text,
    logged_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_depot_benchmarks_daily
CREATE TABLE public.ottoq_depot_benchmarks_daily (
    benchmark_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    report_date date NOT NULL,
    visits_completed integer NOT NULL,
    vehicles_served integer NOT NULL,
    oems_served integer NOT NULL,
    total_service_hours numeric NOT NULL,
    stall_utilization_pct numeric,
    avg_sla_compliance_pct numeric,
    worst_sla_compliance_pct numeric,
    sla_violations_count integer NOT NULL,
    total_kwh_delivered numeric NOT NULL,
    peak_demand_kw numeric,
    solar_self_consumption_pct numeric,
    bess_cycles_today numeric,
    total_revenue_usd numeric NOT NULL,
    total_cost_usd numeric NOT NULL,
    margin_pct numeric,
    cost_per_visit_usd numeric,
    cost_per_kwh_blended_usd numeric,
    rule_failures_count integer NOT NULL,
    anomalies_count integer NOT NULL,
    emergencies_count integer NOT NULL,
    overrides_count integer NOT NULL,
    avg_prediction_mape numeric,
    avg_prediction_coverage_80 numeric,
    total_carbon_offset_kg numeric NOT NULL,
    computed_at timestamp with time zone NOT NULL,
    payload jsonb
);
-- @@ table public.ottoq_depot_cost_daily
CREATE TABLE public.ottoq_depot_cost_daily (
    depot_cost_daily_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    report_date date NOT NULL,
    visits_completed integer NOT NULL,
    unique_vehicles integer NOT NULL,
    unique_fleet_operators integer NOT NULL,
    total_kwh_delivered numeric NOT NULL,
    total_kwh_from_grid numeric NOT NULL,
    total_kwh_from_solar numeric NOT NULL,
    total_kwh_from_bess numeric NOT NULL,
    peak_demand_kw numeric,
    solar_self_consumption_pct numeric,
    total_energy_cost_usd numeric NOT NULL,
    total_demand_charge_usd numeric NOT NULL,
    total_labor_cost_usd numeric NOT NULL,
    total_opportunity_cost_usd numeric NOT NULL,
    fixed_overhead_usd numeric NOT NULL,
    total_operating_cost_usd numeric NOT NULL,
    total_revenue_usd numeric NOT NULL,
    total_margin_usd numeric NOT NULL,
    margin_pct numeric,
    total_carbon_offset_kg numeric NOT NULL,
    carbon_intensity_avg numeric,
    avg_kwh_per_visit numeric,
    avg_cost_per_visit_usd numeric,
    avg_margin_per_visit_usd numeric,
    cost_per_kwh_blended_usd numeric,
    computed_at timestamp with time zone NOT NULL,
    payload jsonb
);
-- @@ table public.ottoq_depot_shifts
CREATE TABLE public.ottoq_depot_shifts (
    shift_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    shift_name text NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    days_of_week integer[] NOT NULL,
    min_techs integer NOT NULL,
    notes text,
    status text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_depot_staffing
CREATE TABLE public.ottoq_depot_staffing (
    depot_id uuid NOT NULL,
    role text NOT NULL,
    headcount integer NOT NULL,
    notes text,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_depot_tariffs
CREATE TABLE public.ottoq_depot_tariffs (
    tariff_row_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    schedule_code text NOT NULL,
    utility text NOT NULL,
    season text NOT NULL,
    season_months integer[] NOT NULL,
    demand_first_block_usd_kw numeric NOT NULL,
    demand_excess_usd_kw numeric NOT NULL,
    block_kw numeric NOT NULL,
    fixed_monthly_usd numeric,
    energy_base_cents_kwh numeric,
    demand_basis text NOT NULL,
    effective_from date NOT NULL,
    provenance jsonb NOT NULL,
    active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_determinism_verdict_ledger
CREATE TABLE public.ottoq_determinism_verdict_ledger (
    verdict_id bigint NOT NULL,
    certified_at timestamp with time zone NOT NULL,
    depot_id uuid NOT NULL,
    scenario text NOT NULL,
    seed bigint NOT NULL,
    ticks integer NOT NULL,
    outcome text NOT NULL,
    equal boolean NOT NULL,
    complete boolean NOT NULL,
    arm_a_run uuid,
    arm_b_run uuid,
    atoms_compared integer NOT NULL,
    disagreeing_atoms text[] NOT NULL,
    null_atoms text[] NOT NULL,
    engine_hash text,
    verdict jsonb NOT NULL
);
-- @@ table public.ottoq_dial_experiments
CREATE TABLE public.ottoq_dial_experiments (
    experiment_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by text NOT NULL,
    depot_id uuid NOT NULL,
    param_key text NOT NULL,
    control_value numeric NOT NULL,
    treatment_value numeric NOT NULL,
    fixed_params jsonb NOT NULL,
    scenario text NOT NULL,
    ticks integer NOT NULL,
    sim_start timestamp with time zone NOT NULL,
    primary_metric text NOT NULL,
    primary_better text NOT NULL,
    first_look_pairs integer NOT NULL,
    final_look_pairs integer NOT NULL,
    alpha numeric NOT NULL,
    guardrail_margin_pct numeric NOT NULL,
    min_effect_pct numeric NOT NULL,
    guardrail_alpha numeric NOT NULL,
    hypothesis text NOT NULL,
    status text NOT NULL,
    concluded_at timestamp with time zone,
    verdict jsonb,
    sim_min_per_tick numeric NOT NULL,
    run_after timestamp with time zone
);
-- @@ table public.ottoq_dial_pair_ledger
CREATE TABLE public.ottoq_dial_pair_ledger (
    pair_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_dial_pair_ledger_pair_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    experiment_id uuid NOT NULL,
    seed bigint NOT NULL,
    engine_hash text NOT NULL,
    ran_at timestamp with time zone NOT NULL,
    run_a uuid NOT NULL,
    run_b uuid NOT NULL,
    ab_group_id uuid NOT NULL,
    complete boolean NOT NULL,
    world_identical boolean NOT NULL,
    both_paid_shield boolean NOT NULL,
    differs boolean NOT NULL,
    moved jsonb NOT NULL,
    metrics_a jsonb NOT NULL,
    metrics_b jsonb NOT NULL,
    delta jsonb NOT NULL,
    wall_s numeric,
    dial_read_a boolean,
    dial_read_b boolean
);
-- @@ table public.ottoq_dial_promotion_ledger
CREATE TABLE public.ottoq_dial_promotion_ledger (
    promotion_id bigint NOT NULL,
    decided_at timestamp with time zone NOT NULL,
    depot_id uuid NOT NULL,
    param_key text NOT NULL,
    from_value numeric,
    to_value numeric,
    outcome text NOT NULL,
    reason text NOT NULL,
    engine_hash text,
    scenario text,
    sim_min_per_tick numeric,
    cell_runs integer,
    cell_seeds integer,
    winner_reward numeric,
    incumbent_rules_blocked numeric,
    winner_rules_blocked numeric,
    weight_version integer,
    rolled_back_of bigint,
    setter_response jsonb,
    experiment_id uuid,
    evidence jsonb
);
-- @@ table public.ottoq_dr_calls
CREATE TABLE public.ottoq_dr_calls (
    dr_call_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    sim_run_id uuid,
    issued_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    duration_minutes numeric,
    required_load_cap_kw numeric NOT NULL,
    reason text,
    program text NOT NULL,
    call_status text NOT NULL,
    cleared_at timestamp with time zone,
    compliance_score numeric,
    data_source text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_dtc_catalog
CREATE TABLE public.ottoq_dtc_catalog (
    dtc_code text NOT NULL,
    category text NOT NULL,
    severity text NOT NULL,
    title text NOT NULL,
    description text,
    introduced_in text
);
-- @@ table public.ottoq_emergency_invocations
CREATE TABLE public.ottoq_emergency_invocations (
    invocation_id uuid NOT NULL,
    invocation_seq bigint NOT NULL,
    protocol_code text NOT NULL,
    triggered_at timestamp with time zone NOT NULL,
    cleared_at timestamp with time zone,
    triggered_by_actor_type text NOT NULL,
    triggered_by_actor_id text,
    triggered_by_event_id uuid,
    source_payload jsonb NOT NULL,
    depot_id uuid,
    affects_scope text,
    cascade_executed jsonb NOT NULL,
    outcome text NOT NULL,
    failure_payload jsonb,
    cleared_by_actor_type text,
    cleared_by_actor_id text,
    resolution_note text,
    linked_event_id uuid,
    correlation_id uuid
);
-- @@ table public.ottoq_emergency_protocols
CREATE TABLE public.ottoq_emergency_protocols (
    protocol_id uuid NOT NULL,
    protocol_code text NOT NULL,
    category text NOT NULL,
    severity text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    rationale text,
    external_references jsonb,
    trigger_event_types text[] NOT NULL,
    cascade_actions jsonb NOT NULL,
    affects_scope text NOT NULL,
    requires_manual_clear boolean NOT NULL,
    auto_clear_after_seconds integer,
    notify_actors text[] NOT NULL,
    external_notify_webhooks text[],
    status text NOT NULL,
    introduced_in text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_enactment_branches
CREATE TABLE public.ottoq_enactment_branches (
    resolved_action_context text NOT NULL,
    writer text NOT NULL,
    writer_side text NOT NULL,
    shield_expected boolean NOT NULL,
    note text,
    declared_at timestamp with time zone NOT NULL,
    effect_families text[],
    gated_downstream_at text
);
-- @@ table public.ottoq_energy_commands
CREATE TABLE public.ottoq_energy_commands (
    command_id uuid NOT NULL,
    sim_run_id uuid,
    depot_id uuid NOT NULL,
    tick_seq bigint,
    issued_at timestamp with time zone NOT NULL,
    source text NOT NULL,
    command_type text NOT NULL,
    setpoint_kw numeric,
    horizon_min numeric,
    reason jsonb,
    status text NOT NULL,
    executed_at timestamp with time zone,
    executed_note text,
    data_source text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    delivered_at timestamp with time zone,
    delivered_to text,
    confirmed_at timestamp with time zone,
    confirmed_by text
);
-- @@ table public.ottoq_energy_plan
CREATE TABLE public.ottoq_energy_plan (
    id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    plan_start_clock timestamp with time zone NOT NULL,
    tick_minutes numeric NOT NULL,
    horizon_steps integer NOT NULL,
    bess_setpoint_kw numeric[] NOT NULL,
    grid_import_kw numeric[],
    forecast_load_kw numeric[],
    predicted_peak_kw numeric,
    solver text,
    status text,
    source text NOT NULL,
    request_id bigint,
    latency_ms integer,
    plan_state text NOT NULL,
    ev_allowance_kw numeric[],
    detail jsonb
);
-- @@ table public.ottoq_energy_rates
CREATE TABLE public.ottoq_energy_rates (
    rate_code text NOT NULL,
    label text NOT NULL,
    energy_cents_kwh numeric,
    fuel_adj_cents_kwh numeric NOT NULL,
    demand_charged boolean NOT NULL,
    fixed_usd_month numeric NOT NULL,
    sources jsonb NOT NULL,
    notes text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_event_state_anchor
CREATE TABLE public.ottoq_event_state_anchor (
    run_key uuid NOT NULL,
    event_type text NOT NULL,
    entity_id uuid NOT NULL,
    anchor_day date NOT NULL,
    anchor_event_id uuid NOT NULL,
    anchor_seq bigint NOT NULL,
    entity_type text NOT NULL,
    sim_run_id uuid,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_event_types_catalog
CREATE TABLE public.ottoq_event_types_catalog (
    event_type text NOT NULL,
    category text NOT NULL,
    description text NOT NULL,
    payload_schema jsonb,
    emitter text,
    default_severity text NOT NULL,
    introduced_in text,
    deprecated boolean NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_events
CREATE TABLE public.ottoq_events (
    event_id uuid NOT NULL,
    event_seq bigint NOT NULL,
    occurred_at timestamp with time zone NOT NULL,
    recorded_at timestamp with time zone NOT NULL,
    actor_type text NOT NULL,
    actor_id text,
    actor_metadata jsonb NOT NULL,
    event_type text NOT NULL,
    event_category text NOT NULL,
    severity text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    fleet_operator_id uuid,
    depot_id uuid,
    payload jsonb NOT NULL,
    previous_state jsonb,
    new_state jsonb,
    correlation_id uuid NOT NULL,
    parent_event_id uuid,
    causation_chain uuid[] NOT NULL,
    related_task_id uuid,
    related_schedule_id uuid,
    related_decision_id uuid,
    payload_hash text NOT NULL,
    signature text,
    signature_key_id text,
    signature_algorithm text NOT NULL,
    outcome text,
    outcome_recorded_at timestamp with time zone,
    latency_ms integer,
    ingest_source text,
    schema_version text NOT NULL,
    data_source text NOT NULL,
    sim_run_id uuid,
    sim_clock_at timestamp with time zone
) WITH (autovacuum_vacuum_scale_factor=0.02, autovacuum_vacuum_threshold=500, autovacuum_analyze_scale_factor=0.02, autovacuum_analyze_threshold=500, autovacuum_vacuum_cost_delay=2, autovacuum_vacuum_cost_limit=2000, autovacuum_vacuum_insert_scale_factor=0.05, autovacuum_vacuum_insert_threshold=10000);
-- @@ table public.ottoq_evidence_regimes
CREATE TABLE public.ottoq_evidence_regimes (
    regime_id bigint NOT NULL,
    model text NOT NULL,
    scope text NOT NULL,
    depot_id uuid,
    starts_at timestamp with time zone NOT NULL,
    reason text NOT NULL,
    source text NOT NULL,
    recorded_by text NOT NULL,
    recorded_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_external_proposals
CREATE TABLE public.ottoq_external_proposals (
    proposal_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid,
    action_context text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    proposal jsonb NOT NULL,
    source text NOT NULL,
    status text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone,
    declared_source text,
    submitted_by_role text,
    submitted_by uuid,
    tick_seq integer,
    disposition_reason text,
    disposed_at timestamp with time zone,
    disposed_tick integer
);
-- @@ table public.ottoq_feature_values
CREATE TABLE public.ottoq_feature_values (
    value_id uuid NOT NULL,
    value_seq bigint NOT NULL,
    feature_name text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    scope_id text,
    value_numeric numeric,
    value_integer bigint,
    value_boolean boolean,
    value_text text,
    value_timestamp timestamp with time zone,
    value_json jsonb,
    valid_from timestamp with time zone NOT NULL,
    valid_until timestamp with time zone,
    observation_time timestamp with time zone NOT NULL,
    source text,
    source_event_id uuid,
    computed_by text,
    feature_version integer NOT NULL,
    quality_score numeric,
    is_imputed boolean NOT NULL,
    is_outlier boolean NOT NULL,
    fleet_operator_id uuid,
    depot_id uuid,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_features
CREATE TABLE public.ottoq_features (
    feature_name text NOT NULL,
    category text NOT NULL,
    data_type text NOT NULL,
    units text,
    valid_range_low numeric,
    valid_range_high numeric,
    enum_values text[],
    title text NOT NULL,
    description text NOT NULL,
    computation_formula text,
    source text,
    is_realtime boolean NOT NULL,
    refresh_frequency text,
    freshness_sla_seconds integer NOT NULL,
    depends_on_features text[] NOT NULL,
    depends_on_tables text[] NOT NULL,
    owner text,
    introduced_in text,
    observed_min numeric,
    observed_max numeric,
    observed_mean numeric,
    observed_p50 numeric,
    observed_p95 numeric,
    observed_p99 numeric,
    observed_null_pct numeric,
    stats_updated_at timestamp with time zone,
    version integer NOT NULL,
    status text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_feed_activations
CREATE TABLE public.ottoq_feed_activations (
    activation_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    var_key text NOT NULL,
    plan_id uuid NOT NULL,
    agent_model text NOT NULL,
    agent_notes text,
    activated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_feed_plan_promotions
CREATE TABLE public.ottoq_feed_plan_promotions (
    promotion_id bigint NOT NULL,
    plan_id uuid NOT NULL,
    var_key text NOT NULL,
    version integer NOT NULL,
    replaced_plan uuid,
    replaced_ver integer,
    promoted_by text NOT NULL,
    reason text NOT NULL,
    authored_by text,
    promoted_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_feed_plans
CREATE TABLE public.ottoq_feed_plans (
    plan_id uuid NOT NULL,
    var_key text NOT NULL,
    version integer NOT NULL,
    status text NOT NULL,
    method text NOT NULL,
    plan jsonb NOT NULL,
    provenance jsonb NOT NULL,
    authored_by text NOT NULL,
    rationale text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fleet_buildout_active
CREATE TABLE public.ottoq_fleet_buildout_active (
    depot_id uuid NOT NULL,
    fleet_code text NOT NULL,
    applied_at timestamp with time zone NOT NULL,
    backend_pid integer NOT NULL,
    vehicles_pre jsonb NOT NULL,
    stalls_pre jsonb NOT NULL
);
-- @@ table public.ottoq_fleet_buildouts
CREATE TABLE public.ottoq_fleet_buildouts (
    fleet_code text NOT NULL,
    depot_id uuid NOT NULL,
    lender_depot_id uuid NOT NULL,
    title text NOT NULL,
    borrow_by_class jsonb NOT NULL,
    fleet_size integer NOT NULL,
    basis jsonb NOT NULL
);
-- @@ table public.ottoq_fleet_operator_slas
CREATE TABLE public.ottoq_fleet_operator_slas (
    sla_id uuid NOT NULL,
    fleet_operator_id uuid NOT NULL,
    contract_reference text,
    effective_from timestamp with time zone NOT NULL,
    effective_until timestamp with time zone,
    status text NOT NULL,
    version integer NOT NULL,
    min_soc_at_deployment_pct numeric,
    preferred_soc_at_deployment_pct numeric,
    max_charge_target_pct numeric,
    min_charge_target_pct numeric,
    max_visit_duration_minutes integer,
    max_queue_wait_minutes integer,
    expected_visit_duration_minutes integer,
    max_concurrent_vehicles_at_depot integer,
    max_queue_depth integer,
    max_overnight_stage_count integer,
    required_services_before_deploy text[],
    blocked_services text[],
    oem_acceptance_required boolean NOT NULL,
    oem_acceptance_timeout_seconds integer,
    oem_acceptance_on_timeout text,
    oem_webhook_callback_url text,
    oem_acceptance_mode text,
    maintenance_window_start time without time zone,
    maintenance_window_end time without time zone,
    allow_maintenance_during_peak boolean NOT NULL,
    reporting_email text,
    reporting_webhook text,
    reporting_frequency text,
    reports_must_be_signed boolean NOT NULL,
    audit_retention_days integer,
    pii_redaction_required boolean NOT NULL,
    penalty_schedule jsonb,
    notes text,
    signed_by_oem text,
    signed_by_depot text,
    signed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    return_reserve_soc_pct numeric
);
-- @@ table public.ottoq_fn_backup_cold_start
CREATE TABLE public.ottoq_fn_backup_cold_start (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_dcfc_day_night
CREATE TABLE public.ottoq_fn_backup_dcfc_day_night (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_dcfc_first
CREATE TABLE public.ottoq_fn_backup_dcfc_first (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_demate_deadlock
CREATE TABLE public.ottoq_fn_backup_demate_deadlock (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_frozen_target
CREATE TABLE public.ottoq_fn_backup_frozen_target (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_geometry_contract
CREATE TABLE public.ottoq_fn_backup_geometry_contract (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_night_waves
CREATE TABLE public.ottoq_fn_backup_night_waves (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_plug_target_policy
CREATE TABLE public.ottoq_fn_backup_plug_target_policy (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_single_run
CREATE TABLE public.ottoq_fn_backup_single_run (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_soc_clamp
CREATE TABLE public.ottoq_fn_backup_soc_clamp (
    captured_at timestamp with time zone NOT NULL,
    fn_name text NOT NULL,
    definition text NOT NULL
);
-- @@ table public.ottoq_fn_backup_stall_watchdog
CREATE TABLE public.ottoq_fn_backup_stall_watchdog (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_supersede_churn
CREATE TABLE public.ottoq_fn_backup_supersede_churn (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_backup_tick_observability
CREATE TABLE public.ottoq_fn_backup_tick_observability (
    fn text NOT NULL,
    definition text NOT NULL,
    backed_up_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_fn_definition_backups
CREATE TABLE public.ottoq_fn_definition_backups (
    backup_id bigint NOT NULL,
    captured_at timestamp with time zone NOT NULL,
    reason text NOT NULL,
    fn_signature text NOT NULL,
    fn_definition text NOT NULL,
    def_md5 text NOT NULL
);
-- @@ table public.ottoq_grant_boundary_backup
CREATE TABLE public.ottoq_grant_boundary_backup (
    captured_at timestamp with time zone NOT NULL,
    relname text NOT NULL,
    relrowsecurity boolean NOT NULL,
    relacl text
);
-- @@ table public.ottoq_grant_snapshot_0198
CREATE TABLE public.ottoq_grant_snapshot_0198 (
    schema_name text NOT NULL,
    function_name text NOT NULL,
    identity_args text NOT NULL,
    owner_name text NOT NULL,
    acl_before text,
    actions text[] NOT NULL,
    taken_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_grid_events
CREATE TABLE public.ottoq_grid_events (
    grid_event_id uuid NOT NULL,
    depot_id uuid,
    event_type text NOT NULL,
    severity text NOT NULL,
    effective_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone,
    source text,
    payload jsonb NOT NULL,
    cleared_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_grid_snapshots
CREATE TABLE public.ottoq_grid_snapshots (
    snapshot_id uuid NOT NULL,
    snapshot_seq bigint NOT NULL,
    depot_id uuid NOT NULL,
    sim_run_id uuid,
    sim_clock_at timestamp with time zone NOT NULL,
    region_demand_mw numeric,
    region_supply_mw numeric,
    reserve_margin_pct numeric,
    generation_mix jsonb,
    carbon_intensity_gco2_per_kwh numeric,
    voltage_v numeric,
    frequency_hz numeric,
    voltage_status text NOT NULL,
    frequency_status text NOT NULL,
    lmp_usd_per_mwh numeric,
    current_tariff_label text,
    current_rate_usd_per_kwh numeric,
    active_dr_call_id uuid,
    dr_required_load_cap_kw numeric,
    data_source text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_incident_reports
CREATE TABLE public.ottoq_incident_reports (
    incident_report_id uuid NOT NULL,
    incident_report_seq bigint NOT NULL,
    incident_code text,
    incident_type text NOT NULL,
    triggered_at timestamp with time zone NOT NULL,
    triggering_event_id uuid,
    triggering_emergency_invocation_id uuid,
    source_correlation_id uuid,
    fleet_operator_id uuid,
    depot_id uuid,
    vehicle_id uuid,
    schedule_id uuid,
    window_start timestamp with time zone NOT NULL,
    window_end timestamp with time zone NOT NULL,
    timeline jsonb NOT NULL,
    event_ids_in_timeline uuid[] NOT NULL,
    rule_failures_in_window jsonb NOT NULL,
    predictions_in_window jsonb NOT NULL,
    recommendations_in_window jsonb NOT NULL,
    root_cause_summary text,
    contributing_factors jsonb,
    systems_involved text[],
    actor_decisions jsonb,
    recommendation_outcomes jsonb,
    duration_seconds integer,
    events_in_window integer NOT NULL,
    rule_failures_count integer NOT NULL,
    anomaly_count integer NOT NULL,
    override_count integer NOT NULL,
    vehicles_affected integer NOT NULL,
    stalls_affected integer NOT NULL,
    generated_at timestamp with time zone NOT NULL,
    generated_by_actor_type text,
    generated_by_actor_id text,
    status text NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    review_notes text,
    audit_report_id uuid,
    audit_bundle_id uuid,
    payload jsonb
);
-- @@ table public.ottoq_inference_log
CREATE TABLE public.ottoq_inference_log (
    inference_id uuid NOT NULL,
    inference_seq bigint NOT NULL,
    requested_at timestamp with time zone NOT NULL,
    completed_at timestamp with time zone,
    latency_ms integer,
    feature_fetch_ms integer,
    inference_ms integer,
    prediction_type text NOT NULL,
    model_version_id uuid,
    route_id uuid,
    serving_runtime text,
    fleet_operator_id uuid,
    depot_id uuid,
    vehicle_id uuid,
    vehicle_class text,
    features_used jsonb,
    feature_snapshot_ids uuid[],
    inputs_hash text,
    context jsonb,
    predicted_value jsonb,
    p10 numeric,
    p50 numeric,
    p90 numeric,
    confidence numeric,
    prediction_id uuid,
    uncertainty_method text,
    ab_test_id uuid,
    ab_test_variant text,
    is_shadow boolean NOT NULL,
    shadow_compared_to uuid,
    shadow_disagreement numeric,
    status text NOT NULL,
    error_message text,
    error_code text,
    correlation_id uuid,
    parent_event_id uuid,
    event_id uuid,
    cost_estimate_cents numeric,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_intelligence_snapshot
CREATE TABLE public.ottoq_intelligence_snapshot (
    source text NOT NULL,
    registered boolean NOT NULL,
    decisions bigint NOT NULL,
    enacted bigint NOT NULL,
    last_decision_at timestamp with time zone,
    window_from timestamp with time zone,
    window_to timestamp with time zone,
    computed_at timestamp with time zone NOT NULL,
    proposals bigint NOT NULL,
    proposals_enacted bigint NOT NULL,
    last_proposal_at timestamp with time zone
);
-- @@ table public.ottoq_intelligence_sources
CREATE TABLE public.ottoq_intelligence_sources (
    source text NOT NULL,
    kind text NOT NULL,
    gate_param_key text,
    l2_engine_label text,
    own_ledger text,
    code_lives_in text NOT NULL,
    note text,
    registered_at timestamp with time zone NOT NULL,
    l2_engine_labels text[] NOT NULL
);
-- @@ table public.ottoq_itinerary_legs
CREATE TABLE public.ottoq_itinerary_legs (
    leg_id uuid NOT NULL,
    itinerary_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    seq integer NOT NULL,
    leg_type text NOT NULL,
    from_stall_id uuid,
    to_stall_id uuid,
    planned_start_sim timestamp with time zone,
    planned_end_sim timestamp with time zone,
    planned_duration_s integer,
    duration_basis jsonb NOT NULL,
    actual_start_sim timestamp with time zone,
    actual_end_sim timestamp with time zone,
    status text NOT NULL,
    deviation_s integer,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_kpi_touch_actor_types
CREATE TABLE public.ottoq_kpi_touch_actor_types (
    actor_type text NOT NULL,
    human_actor boolean NOT NULL,
    note text NOT NULL,
    classified_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_kpi_touch_lanes
CREATE TABLE public.ottoq_kpi_touch_lanes (
    lane text NOT NULL,
    human_touch boolean NOT NULL,
    note text NOT NULL,
    classified_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_layout_backup_0010_depots
CREATE TABLE public.ottoq_layout_backup_0010_depots (
    id uuid,
    site_length_ft numeric,
    site_width_ft numeric,
    site_acres numeric,
    site_layout jsonb,
    backed_up_at timestamp with time zone
);
-- @@ table public.ottoq_layout_backup_0010_stalls
CREATE TABLE public.ottoq_layout_backup_0010_stalls (
    id uuid,
    depot_id uuid,
    stall_code text,
    stall_type public.stall_type,
    display_name text,
    relative_x double precision,
    relative_y double precision,
    heading_degrees smallint,
    absolute_lat double precision,
    absolute_lng double precision,
    absolute_point public.geography(Point,4326),
    distance_from_entrance integer,
    status text,
    current_vehicle_id uuid,
    equipment_config jsonb,
    fiducial_marker_id text,
    uwb_beacon_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    zone text,
    reserved_for_mission_id uuid,
    connector_type text,
    connector_max_kw numeric,
    supported_inlet_types text[],
    ocpp_charger_id uuid,
    stall_kind text,
    canopy_code text,
    covered boolean,
    stall_width_ft numeric,
    stall_depth_ft numeric,
    reserved_by uuid,
    reserved_at timestamp with time zone,
    reservation_expires_at timestamp with time zone,
    staging_role text,
    backed_up_at timestamp with time zone
);
-- @@ table public.ottoq_layout_backup_0010_structures
CREATE TABLE public.ottoq_layout_backup_0010_structures (
    structure_id uuid,
    depot_id uuid,
    structure_code text,
    structure_kind text,
    title text,
    origin_x_ft numeric,
    origin_y_ft numeric,
    width_ft numeric,
    length_ft numeric,
    height_ft numeric,
    rotation_deg numeric,
    absolute_lat numeric,
    absolute_lng numeric,
    properties jsonb,
    status text,
    introduced_in text,
    created_at timestamp with time zone,
    backed_up_at timestamp with time zone
);
-- @@ table public.ottoq_layout_backup_0011_stall_bookings
CREATE TABLE public.ottoq_layout_backup_0011_stall_bookings (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    booked_at_sim timestamp with time zone
);
-- @@ table public.ottoq_layout_backup_0011_stalls
CREATE TABLE public.ottoq_layout_backup_0011_stalls (
    id uuid,
    depot_id uuid,
    stall_code text,
    stall_type public.stall_type,
    display_name text,
    relative_x double precision,
    relative_y double precision,
    heading_degrees smallint,
    absolute_lat double precision,
    absolute_lng double precision,
    absolute_point public.geography(Point,4326),
    distance_from_entrance integer,
    status text,
    current_vehicle_id uuid,
    equipment_config jsonb,
    fiducial_marker_id text,
    uwb_beacon_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    zone text,
    reserved_for_mission_id uuid,
    connector_type text,
    connector_max_kw numeric,
    supported_inlet_types text[],
    ocpp_charger_id uuid,
    stall_kind text,
    canopy_code text,
    covered boolean,
    stall_width_ft numeric,
    stall_depth_ft numeric,
    reserved_by uuid,
    reserved_at timestamp with time zone,
    reservation_expires_at timestamp with time zone,
    staging_role text
);
-- @@ table public.ottoq_layout_backup_0011_vehicle_state_log
CREATE TABLE public.ottoq_layout_backup_0011_vehicle_state_log (
    id uuid,
    vehicle_id uuid,
    depot_id uuid,
    previous_state public.vehicle_state,
    new_state public.vehicle_state,
    triggered_by public.trigger_source,
    trigger_user_id uuid,
    stall_id uuid,
    schedule_task_id uuid,
    vehicle_schedule_id uuid,
    metadata jsonb,
    created_at timestamp with time zone
);
-- @@ table public.ottoq_learned_estimates
CREATE TABLE public.ottoq_learned_estimates (
    estimate_id bigint NOT NULL,
    depot_id uuid NOT NULL,
    model text NOT NULL,
    fitted_at timestamp with time zone NOT NULL,
    evidence_from timestamp with time zone,
    evidence_through timestamp with time zone,
    n_evidence integer NOT NULL,
    n_runs integer NOT NULL,
    usable boolean NOT NULL,
    params jsonb NOT NULL,
    code_md5 text NOT NULL,
    fitted_by text NOT NULL,
    note text
);
-- @@ table public.ottoq_margin_prices
CREATE TABLE public.ottoq_margin_prices (
    price_code text NOT NULL,
    unit text NOT NULL,
    low numeric NOT NULL,
    point numeric NOT NULL,
    high numeric NOT NULL,
    lever text NOT NULL,
    basis text NOT NULL,
    sources jsonb NOT NULL,
    confidence text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_model_artifacts
CREATE TABLE public.ottoq_model_artifacts (
    artifact_id uuid NOT NULL,
    storage_path text NOT NULL,
    format text NOT NULL,
    size_bytes bigint NOT NULL,
    sha256 text NOT NULL,
    uploaded_at timestamp with time zone NOT NULL,
    uploaded_by text,
    description text,
    source_run_id uuid,
    is_active boolean NOT NULL,
    retired_at timestamp with time zone
);
-- @@ table public.ottoq_model_call_ledger
CREATE TABLE public.ottoq_model_call_ledger (
    call_id bigint NOT NULL,
    sim_run_id uuid,
    depot_id uuid,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    chain_id text,
    provider text NOT NULL,
    role text NOT NULL,
    model text,
    endpoint text,
    http_status integer,
    latency_ms integer,
    outcome text NOT NULL,
    proposals_out integer,
    rationale_present boolean,
    detail jsonb NOT NULL,
    called_at timestamp with time zone NOT NULL,
    source_kind text NOT NULL
);
-- @@ table public.ottoq_model_routes
CREATE TABLE public.ottoq_model_routes (
    route_id uuid NOT NULL,
    prediction_type text NOT NULL,
    fleet_operator_id uuid,
    depot_id uuid,
    vehicle_class text,
    model_version_id uuid,
    fallback_model_version_id uuid,
    effective_from timestamp with time zone NOT NULL,
    effective_until timestamp with time zone,
    priority integer NOT NULL,
    traffic_share_pct numeric NOT NULL,
    shadow_mode boolean NOT NULL,
    ab_test_id uuid,
    rationale text,
    created_at timestamp with time zone NOT NULL,
    created_by text
);
-- @@ table public.ottoq_oauth_auth_requests
CREATE TABLE public.ottoq_oauth_auth_requests (
    request_id uuid NOT NULL,
    client_id text NOT NULL,
    redirect_uri text NOT NULL,
    code_challenge text NOT NULL,
    state text,
    scope text NOT NULL,
    resource text NOT NULL,
    issuer text NOT NULL,
    status text NOT NULL,
    account_id uuid,
    code_hash text,
    code_expires_at timestamp with time zone,
    principal_id uuid,
    requested_ip text,
    created_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    decided_at timestamp with time zone
);
-- @@ table public.ottoq_oauth_clients
CREATE TABLE public.ottoq_oauth_clients (
    client_id text NOT NULL,
    client_name text NOT NULL,
    redirect_uris text[] NOT NULL,
    grant_types text[] NOT NULL,
    metadata jsonb NOT NULL,
    registered_ip text,
    status text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_oauth_device_codes
CREATE TABLE public.ottoq_oauth_device_codes (
    device_code_hash text NOT NULL,
    user_code text NOT NULL,
    client_id text NOT NULL,
    scope text NOT NULL,
    resource text NOT NULL,
    status text NOT NULL,
    account_id uuid,
    principal_id uuid,
    interval_s integer NOT NULL,
    requested_ip text,
    created_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    decided_at timestamp with time zone,
    last_polled_at timestamp with time zone,
    polls integer NOT NULL
);
-- @@ table public.ottoq_oauth_grants
CREATE TABLE public.ottoq_oauth_grants (
    principal_id uuid NOT NULL,
    account_id uuid NOT NULL,
    email text NOT NULL,
    client_id text NOT NULL,
    scope text NOT NULL,
    resource text NOT NULL,
    created_via text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_oauth_tokens
CREATE TABLE public.ottoq_oauth_tokens (
    token_hash text NOT NULL,
    kind text NOT NULL,
    principal_id uuid NOT NULL,
    issued_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    replaced_by text,
    revoked_at timestamp with time zone,
    revoked_reason text
);
-- @@ table public.ottoq_ocpp_chargers
CREATE TABLE public.ottoq_ocpp_chargers (
    charger_id uuid NOT NULL,
    depot_id uuid,
    ocpp_identifier text NOT NULL,
    vendor text,
    model text,
    serial_number text,
    firmware_version text,
    ocpp_protocol_version text,
    station_state text NOT NULL,
    station_state_changed_at timestamp with time zone NOT NULL,
    last_heartbeat_at timestamp with time zone,
    max_kw numeric,
    num_connectors integer NOT NULL,
    connector_states jsonb NOT NULL,
    last_fault_code text,
    last_fault_at timestamp with time zone,
    last_fault_payload jsonb,
    installed_at timestamp with time zone,
    decommissioned_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_ocpp_messages
CREATE TABLE public.ottoq_ocpp_messages (
    message_id uuid NOT NULL,
    message_seq bigint NOT NULL,
    ocpp_session_id uuid,
    charger_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    message_at timestamp with time zone NOT NULL,
    sim_clock_at timestamp with time zone,
    direction text NOT NULL,
    message_type text NOT NULL,
    ocpp_version text NOT NULL,
    payload jsonb NOT NULL,
    data_source text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_oem_webhook_log
CREATE TABLE public.ottoq_oem_webhook_log (
    webhook_id uuid NOT NULL,
    webhook_seq bigint NOT NULL,
    sim_run_id uuid,
    vehicle_id uuid,
    fleet_operator_id uuid,
    oem_name text NOT NULL,
    webhook_type text NOT NULL,
    http_method text NOT NULL,
    endpoint_url text,
    payload jsonb,
    payload_complete boolean NOT NULL,
    payload_missing_fields text[],
    attempt_num integer NOT NULL,
    is_retry boolean NOT NULL,
    is_duplicate boolean NOT NULL,
    is_out_of_order boolean NOT NULL,
    parent_webhook_id uuid,
    latency_ms integer,
    http_status integer,
    response_payload jsonb,
    delivery_status text NOT NULL,
    validation_result text,
    sim_clock_emitted_at timestamp with time zone NOT NULL,
    sim_clock_delivered_at timestamp with time zone,
    real_at timestamp with time zone NOT NULL,
    data_source text NOT NULL,
    delivery_mode text NOT NULL,
    http_request_id bigint,
    signature text
) WITH (autovacuum_vacuum_scale_factor=0.02, autovacuum_vacuum_threshold=500, autovacuum_analyze_scale_factor=0.02, autovacuum_analyze_threshold=500, autovacuum_vacuum_cost_delay=2, autovacuum_vacuum_cost_limit=2000);
-- @@ table public.ottoq_oem_webhook_patterns
CREATE TABLE public.ottoq_oem_webhook_patterns (
    oem_name text NOT NULL,
    fleet_operator_id uuid,
    webhook_endpoint text NOT NULL,
    payload_schema_version text NOT NULL,
    latency_mean_ms integer NOT NULL,
    latency_p99_ms integer NOT NULL,
    latency_distribution text NOT NULL,
    retry_policy jsonb NOT NULL,
    payload_completeness_pct numeric NOT NULL,
    duplicate_send_pct numeric NOT NULL,
    out_of_order_pct numeric NOT NULL,
    auth_failure_pct numeric NOT NULL,
    rate_limit_pct numeric NOT NULL,
    network_timeout_pct numeric NOT NULL,
    server_error_5xx_pct numeric NOT NULL,
    required_fields jsonb NOT NULL,
    optional_fields jsonb NOT NULL,
    notes text,
    active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    live_delivery_enabled boolean NOT NULL,
    live_endpoint_url text,
    signing_secret_ref text
);
-- @@ table public.ottoq_operation_catalog
CREATE TABLE public.ottoq_operation_catalog (
    pack_id text NOT NULL,
    operation_code text NOT NULL,
    display_name text,
    category text NOT NULL,
    leg_type text,
    booking_purpose text,
    svc_code text,
    parallel_with_charge boolean NOT NULL,
    is_movement boolean NOT NULL,
    energy_bearing boolean NOT NULL,
    emits_sdr boolean NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_ops_approvals
CREATE TABLE public.ottoq_ops_approvals (
    approval_id uuid NOT NULL,
    approval_type text NOT NULL,
    vehicle_id uuid NOT NULL,
    visit_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    status text NOT NULL,
    priority text NOT NULL,
    payload jsonb,
    requested_at timestamp with time zone NOT NULL,
    decide_after timestamp with time zone,
    expires_at timestamp with time zone,
    decided_at timestamp with time zone,
    decided_by text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_owner_accounts
CREATE TABLE public.ottoq_owner_accounts (
    account_id uuid NOT NULL,
    email text NOT NULL,
    fleet_operator_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    status text NOT NULL,
    note text,
    created_at timestamp with time zone NOT NULL,
    created_by text NOT NULL,
    disabled_at timestamp with time zone
);
-- @@ table public.ottoq_owner_commands
CREATE TABLE public.ottoq_owner_commands (
    command_id uuid NOT NULL,
    principal_id uuid NOT NULL,
    principal_name text NOT NULL,
    fleet_operator_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    sim_run_id uuid,
    sim_clock timestamp with time zone,
    tool text NOT NULL,
    mode text NOT NULL,
    outcome text NOT NULL,
    args jsonb NOT NULL,
    vehicles jsonb NOT NULL,
    effects jsonb NOT NULL,
    refusal jsonb,
    summary text NOT NULL,
    plan_hash text,
    link text,
    idempotency_key text,
    undoes_command_id uuid,
    undone_by_command_id uuid,
    undone_at timestamp with time zone,
    lifted_at timestamp with time zone,
    lifted_reason text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_owner_settings
CREATE TABLE public.ottoq_owner_settings (
    setting_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    fleet_operator_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    kind text NOT NULL,
    charge_limit_pct numeric,
    hold_until_sim timestamp with time zone,
    service text,
    service_when text,
    include_current_visit boolean,
    command_id uuid NOT NULL,
    replaces_setting_id uuid,
    status text NOT NULL,
    set_at timestamp with time zone NOT NULL,
    set_at_sim timestamp with time zone NOT NULL,
    closed_at timestamp with time zone,
    closed_at_sim timestamp with time zone,
    closed_reason text,
    closed_by_command_id uuid,
    pending_reconcile boolean NOT NULL,
    applied jsonb NOT NULL
);
-- @@ table public.ottoq_policy_param_catalog
CREATE TABLE public.ottoq_policy_param_catalog (
    param_key text NOT NULL,
    description text,
    default_value numeric,
    min_value numeric,
    max_value numeric,
    affects text,
    min_exclusive numeric,
    max_exclusive numeric,
    agent_writable boolean NOT NULL,
    agent_min_value numeric,
    agent_max_value numeric,
    agent_max_drift_pct numeric
);
-- @@ table public.ottoq_policy_params
CREATE TABLE public.ottoq_policy_params (
    scope_type text NOT NULL,
    scope_id uuid NOT NULL,
    param_key text NOT NULL,
    param_value numeric NOT NULL,
    updated_by text,
    updated_at timestamp with time zone
);
-- @@ table public.ottoq_prediction_accuracy_heatmap
CREATE TABLE public.ottoq_prediction_accuracy_heatmap (
    heatmap_id uuid NOT NULL,
    prediction_type text NOT NULL,
    depot_id uuid,
    fleet_operator_id uuid,
    vehicle_class text,
    horizon_minutes integer,
    hour_of_day integer,
    day_of_week integer,
    report_date date NOT NULL,
    n_predictions integer NOT NULL,
    n_scored integer NOT NULL,
    n_in_p10_p90 integer,
    mae numeric,
    rmse numeric,
    mape numeric,
    median_abs_error numeric,
    bias numeric,
    directional_accuracy numeric,
    coverage_80 numeric,
    coverage_50 numeric,
    coverage_95 numeric,
    avg_interval_width numeric,
    pit_uniformity_score numeric,
    model_version_id uuid,
    baseline_method text,
    is_well_performing boolean,
    notes text,
    computed_at timestamp with time zone NOT NULL,
    payload jsonb
);
-- @@ table public.ottoq_prediction_rule_links
CREATE TABLE public.ottoq_prediction_rule_links (
    link_id uuid NOT NULL,
    prediction_type text NOT NULL,
    rule_code text NOT NULL,
    relationship text NOT NULL,
    comparison text,
    threshold_source text,
    threshold_param text,
    enabled boolean NOT NULL,
    rationale text,
    introduced_in text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_prediction_types_catalog
CREATE TABLE public.ottoq_prediction_types_catalog (
    prediction_type text NOT NULL,
    category text NOT NULL,
    target_entity_type text NOT NULL,
    output_kind text NOT NULL,
    output_unit text,
    output_range_low numeric,
    output_range_high numeric,
    title text NOT NULL,
    description text NOT NULL,
    business_value text,
    supported_horizons_minutes integer[] NOT NULL,
    default_horizon_minutes integer NOT NULL,
    required_features text[] NOT NULL,
    optional_features text[] NOT NULL,
    freshness_sla_seconds integer NOT NULL,
    latency_p95_ms integer NOT NULL,
    status text NOT NULL,
    introduced_in text,
    ml_ready boolean NOT NULL,
    baseline_method text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_predictions
CREATE TABLE public.ottoq_predictions (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    vehicle_id uuid,
    prediction_type text NOT NULL,
    title text,
    description text,
    recommendation jsonb,
    confidence numeric(4,3),
    supporting_data jsonb,
    analysis_window_start timestamp with time zone,
    analysis_window_end timestamp with time zone,
    status text NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    applied_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone,
    time_horizon_hours integer,
    model_version integer,
    action_type text,
    action_parameters jsonb,
    execution_status text,
    executed_at timestamp with time zone,
    executed_by text,
    rollback_data jsonb,
    model_version_id uuid,
    ab_test_id uuid,
    ab_test_variant text,
    feature_snapshot_ids uuid[],
    fleet_feature_date date,
    fusion_log_id uuid,
    explanation_id uuid,
    data_quality_score numeric(4,3),
    target_at timestamp with time zone,
    horizon_minutes integer,
    predicted_value jsonb,
    p10 numeric,
    p50 numeric,
    p90 numeric,
    prediction_interval_method text,
    calibration_score numeric,
    prediction_baseline text,
    inputs_hash text,
    fleet_operator_id uuid,
    event_id uuid,
    correlation_id uuid,
    latency_ms integer,
    shadow_only boolean NOT NULL
);
-- @@ table public.ottoq_proposal_disposition_ledger
CREATE TABLE public.ottoq_proposal_disposition_ledger (
    disposition_id bigint NOT NULL,
    sim_run_id uuid,
    proposal_id uuid,
    depot_id uuid,
    action_context text,
    entity_type text,
    entity_id uuid,
    source text NOT NULL,
    proposer_rank integer,
    status text NOT NULL,
    disposition_reason text,
    abstained boolean NOT NULL,
    promotion_count integer,
    promoted_from uuid,
    stall_id uuid,
    requested_kw numeric,
    proposal_created_at timestamp with time zone,
    disposed_at timestamp with time zone,
    disposed_tick bigint,
    captured_at timestamp with time zone NOT NULL,
    source_kind text NOT NULL
);
-- @@ table public.ottoq_proposal_replay
CREATE TABLE public.ottoq_proposal_replay (
    replay_id uuid NOT NULL,
    seq integer NOT NULL,
    tick_seq integer NOT NULL,
    action_context text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    proposal jsonb NOT NULL,
    source text NOT NULL,
    orig_status text,
    captured_from uuid NOT NULL,
    captured_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_proposer_fire_log
CREATE TABLE public.ottoq_proposer_fire_log (
    fire_id bigint NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    declared_source text NOT NULL,
    effective_source text,
    tick_seq integer,
    fired_at timestamp with time zone NOT NULL,
    status text NOT NULL,
    frame_hash text,
    n_vehicles integer,
    n_in_serviceable_state integer,
    n_rows integer NOT NULL,
    n_planned integer,
    n_abstained integer,
    n_deferred integer,
    n_submitted integer NOT NULL,
    proposal_ids uuid[] NOT NULL,
    solver jsonb,
    fire jsonb NOT NULL,
    error text
);
-- @@ table public.ottoq_proposer_precedence
CREATE TABLE public.ottoq_proposer_precedence (
    source text NOT NULL,
    rank integer NOT NULL,
    holds_tick boolean NOT NULL,
    greedy_yields boolean NOT NULL,
    note text,
    added_at timestamp with time zone NOT NULL,
    added_by text NOT NULL
);
-- @@ table public.ottoq_ready_promise_updates
CREATE TABLE public.ottoq_ready_promise_updates (
    update_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_ready_promise_updates_update_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    visit_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    estimated_at timestamp with time zone NOT NULL,
    arrived_at timestamp with time zone,
    situation text NOT NULL,
    bundle text NOT NULL,
    elapsed_min numeric,
    ready_p50_min numeric,
    ready_p90_min numeric,
    ready_p50_at timestamp with time zone,
    ready_p90_at timestamp with time zone,
    owner_read boolean NOT NULL,
    owner_ready_by_sim timestamp with time zone,
    detail jsonb NOT NULL,
    recorded_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_ready_promises
CREATE TABLE public.ottoq_ready_promises (
    promise_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_ready_promises_promise_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    visit_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    promised_at timestamp with time zone NOT NULL,
    arrived_at timestamp with time zone,
    due_at timestamp with time zone,
    situation text NOT NULL,
    bundle text NOT NULL,
    plan_charge_min numeric,
    charge_p50_min numeric,
    charge_p90_min numeric,
    ready_p50_min numeric NOT NULL,
    ready_p90_min numeric NOT NULL,
    ready_p50_at timestamp with time zone NOT NULL,
    ready_p90_at timestamp with time zone NOT NULL,
    futures integer NOT NULL,
    detail jsonb NOT NULL,
    recorded_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_recall_decisions
CREATE TABLE public.ottoq_recall_decisions (
    recall_id uuid NOT NULL,
    decision_seq bigint GENERATED BY DEFAULT AS IDENTITY (SEQUENCE NAME public.ottoq_recall_decisions_decision_seq_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid,
    decided_at_sim timestamp with time zone NOT NULL,
    decided_at timestamp with time zone NOT NULL,
    implementation text NOT NULL,
    should_return boolean NOT NULL,
    return_trigger text,
    urgency text,
    rung smallint,
    is_deferrable boolean,
    lead_ticks smallint,
    projected_eta_min numeric,
    horizon_min numeric,
    soc_override numeric,
    inputs jsonb NOT NULL,
    content_hash text NOT NULL,
    data_source text NOT NULL
);
-- @@ table public.ottoq_recall_implementations
CREATE TABLE public.ottoq_recall_implementations (
    impl_id smallint NOT NULL,
    implementation text NOT NULL,
    evaluator_function text NOT NULL,
    status text NOT NULL,
    note text
);
-- @@ table public.ottoq_recall_refusals
CREATE TABLE public.ottoq_recall_refusals (
    refusal_id uuid NOT NULL,
    refusal_seq bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_recall_refusals_refusal_seq_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    recall_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid,
    refused_at_sim timestamp with time zone NOT NULL,
    refused_at timestamp with time zone NOT NULL,
    refused_by text NOT NULL,
    reason_code text NOT NULL,
    retry_after_min numeric NOT NULL,
    recall_trigger text,
    recall_urgency text,
    was_deferrable boolean,
    evidence jsonb NOT NULL,
    content_hash text NOT NULL,
    data_source text NOT NULL
);
-- @@ table public.ottoq_recommendations
CREATE TABLE public.ottoq_recommendations (
    recommendation_id uuid NOT NULL,
    recommendation_seq bigint NOT NULL,
    emitted_at timestamp with time zone NOT NULL,
    prediction_id uuid,
    prediction_type text,
    proposed_action text NOT NULL,
    action_parameters jsonb NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    fleet_operator_id uuid,
    depot_id uuid,
    rules_evaluated jsonb,
    rules_blocked_by text[],
    status text NOT NULL,
    decided_at timestamp with time zone,
    decision_reason text,
    executed_at timestamp with time zone,
    executed_by text,
    execution_event_id uuid,
    execution_outcome text,
    expires_at timestamp with time zone,
    shadow_only boolean NOT NULL,
    correlation_id uuid,
    parent_event_id uuid,
    recommendation_payload jsonb
);
-- @@ table public.ottoq_research_findings
CREATE TABLE public.ottoq_research_findings (
    finding_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_research_findings_finding_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    slug text NOT NULL,
    depot_id uuid NOT NULL,
    phase text NOT NULL,
    item text NOT NULL,
    kind text NOT NULL,
    status text NOT NULL,
    title text NOT NULL,
    summary text NOT NULL,
    metrics jsonb NOT NULL,
    evidence text,
    run_ids text[] NOT NULL,
    measured_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_retention_engine_allowlist
CREATE TABLE public.ottoq_retention_engine_allowlist (
    table_name text NOT NULL,
    added_at timestamp with time zone NOT NULL,
    note text NOT NULL
);
-- @@ table public.ottoq_retention_policy
CREATE TABLE public.ottoq_retention_policy (
    policy_key text NOT NULL,
    enabled boolean NOT NULL,
    keep_interval interval NOT NULL,
    day_aligned boolean NOT NULL,
    notes text,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_retention_state
CREATE TABLE public.ottoq_retention_state (
    table_name text NOT NULL,
    cursor_block bigint NOT NULL,
    pass_deleted bigint NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_retraining_triggers
CREATE TABLE public.ottoq_retraining_triggers (
    trigger_id uuid NOT NULL,
    trigger_code text NOT NULL,
    prediction_type text NOT NULL,
    condition_kind text NOT NULL,
    condition jsonb NOT NULL,
    enabled boolean NOT NULL,
    description text,
    last_fired_at timestamp with time zone,
    fire_count bigint NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_reward_weights
CREATE TABLE public.ottoq_reward_weights (
    weight_version integer NOT NULL,
    is_active boolean NOT NULL,
    weights jsonb NOT NULL,
    note text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_rider_cleaning_flags
CREATE TABLE public.ottoq_rider_cleaning_flags (
    flag_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid,
    flag_kind text NOT NULL,
    status text NOT NULL,
    why text NOT NULL,
    return_trigger text NOT NULL,
    service_atom text NOT NULL,
    stall_type_required text,
    raised_at_sim_clock timestamp with time zone NOT NULL,
    recalled_at_sim_clock timestamp with time zone,
    recalled_visit_key text,
    served_at_sim_clock timestamp with time zone,
    reserved_stall_id uuid,
    drawn_seed bigint,
    created_at timestamp with time zone NOT NULL,
    recalled_visit_id uuid
);
-- @@ table public.ottoq_rule_evaluations
CREATE TABLE public.ottoq_rule_evaluations (
    evaluation_id uuid NOT NULL,
    evaluation_seq bigint NOT NULL,
    evaluated_at timestamp with time zone NOT NULL,
    duration_ms integer,
    rule_code text NOT NULL,
    rule_version integer NOT NULL,
    triggered_by_event_id uuid,
    action_context text,
    entity_type text,
    entity_id uuid,
    fleet_operator_id uuid,
    depot_id uuid,
    passed boolean NOT NULL,
    reason text,
    severity text NOT NULL,
    enforcement text NOT NULL,
    enforcement_taken text NOT NULL,
    parameters_used jsonb NOT NULL,
    context jsonb NOT NULL,
    result_payload jsonb NOT NULL,
    override_id uuid,
    linked_event_id uuid,
    correlation_id uuid,
    sim_run_id uuid
) WITH (autovacuum_vacuum_scale_factor=0.02, autovacuum_vacuum_threshold=500, autovacuum_analyze_scale_factor=0.02, autovacuum_analyze_threshold=500, autovacuum_vacuum_cost_delay=2, autovacuum_vacuum_cost_limit=2000);
-- @@ table public.ottoq_rule_overrides
CREATE TABLE public.ottoq_rule_overrides (
    override_id uuid NOT NULL,
    rule_code text NOT NULL,
    rule_version integer NOT NULL,
    entity_type text,
    entity_id uuid,
    override_actor_type text NOT NULL,
    override_actor_id text,
    approved_by text,
    justification text NOT NULL,
    effective_from timestamp with time zone NOT NULL,
    effective_until timestamp with time zone,
    triggered_evaluation_id uuid,
    linked_event_id uuid,
    created_at timestamp with time zone NOT NULL,
    fleet_operator_id uuid,
    depot_id uuid,
    payload jsonb,
    declared_actor_type text,
    actor_auth_uid uuid,
    identity_source text
);
-- @@ table public.ottoq_rule_parameters
CREATE TABLE public.ottoq_rule_parameters (
    parameter_id uuid NOT NULL,
    rule_code text NOT NULL,
    scope text NOT NULL,
    scope_id uuid NOT NULL,
    parameters jsonb NOT NULL,
    effective_from timestamp with time zone NOT NULL,
    effective_until timestamp with time zone,
    reason text,
    approved_by text,
    created_at timestamp with time zone NOT NULL,
    created_by text
);
-- @@ table public.ottoq_rules
CREATE TABLE public.ottoq_rules (
    rule_id uuid NOT NULL,
    rule_code text NOT NULL,
    version integer NOT NULL,
    category text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    rationale text NOT NULL,
    severity text NOT NULL,
    enforcement text NOT NULL,
    override_allowed boolean NOT NULL,
    override_min_role text,
    scope text NOT NULL,
    evaluator_function text NOT NULL,
    default_parameters jsonb NOT NULL,
    applies_to_actions text[] NOT NULL,
    applies_to_entities text[] NOT NULL,
    status text NOT NULL,
    introduced_in text NOT NULL,
    deprecated_at timestamp with time zone,
    deprecation_reason text,
    successor_rule_code text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    created_by text,
    external_references jsonb
);
-- @@ table public.ottoq_run_archives
CREATE TABLE public.ottoq_run_archives (
    sim_run_id uuid NOT NULL,
    archived_at timestamp with time zone NOT NULL,
    reason text,
    scenario text,
    policy text,
    random_seed bigint,
    depot_id uuid,
    run_by text,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    tick_count integer,
    sim_clock_start timestamp with time zone,
    sim_clock_end timestamp with time zone,
    playback_mode text,
    speed_x numeric,
    metrics jsonb NOT NULL,
    run_payload jsonb,
    pack_id text NOT NULL,
    config_hash text,
    engine_hash text,
    config_key jsonb
);
-- @@ table public.ottoq_run_dial_ledger
CREATE TABLE public.ottoq_run_dial_ledger (
    sim_run_id uuid NOT NULL,
    captured_at timestamp with time zone NOT NULL,
    depot_id uuid,
    scenario text,
    policy text,
    random_seed bigint,
    engine_hash text,
    config_hash text,
    sim_min_per_tick numeric,
    tick_count integer,
    dials jsonb NOT NULL,
    dials_set_count integer NOT NULL,
    metrics jsonb,
    rule_evaluations bigint,
    rules_blocked bigint,
    kpi jsonb,
    kpi_purged boolean,
    returns_unserved integer
);
-- @@ table public.ottoq_run_once_claim
CREATE TABLE public.ottoq_run_once_claim (
    tag text NOT NULL,
    claimed_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone,
    receipt jsonb,
    err text
);
-- @@ table public.ottoq_run_scope_registry
CREATE TABLE public.ottoq_run_scope_registry (
    table_schema text NOT NULL,
    table_name text NOT NULL,
    column_name text NOT NULL,
    class text NOT NULL,
    note text,
    registered_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_scenarios
CREATE TABLE public.ottoq_scenarios (
    scenario_id uuid NOT NULL,
    scenario_code text NOT NULL,
    category text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    validates text,
    expected_outcome text,
    depot_id uuid,
    fleet_operator_ids uuid[],
    sim_duration_minutes integer NOT NULL,
    default_time_scale numeric NOT NULL,
    tick_interval_seconds integer NOT NULL,
    initial_conditions jsonb NOT NULL,
    arrival_profile jsonb NOT NULL,
    timeline jsonb NOT NULL,
    random_seed bigint NOT NULL,
    stress_params jsonb,
    status text NOT NULL,
    tags text[],
    introduced_in text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    start_window_lo_hour_ct smallint,
    start_window_hi_hour_ct smallint
);
-- @@ table public.ottoq_schema_snapshots
CREATE TABLE public.ottoq_schema_snapshots (
    snapshot_id bigint NOT NULL,
    taken_at timestamp with time zone NOT NULL,
    label text NOT NULL,
    object_kind text NOT NULL,
    schema_name text NOT NULL,
    object_name text NOT NULL,
    definition text NOT NULL,
    def_md5 text NOT NULL
);
-- @@ table public.ottoq_service_detail_records
CREATE TABLE public.ottoq_service_detail_records (
    sdr_id uuid NOT NULL,
    sdr_seq bigint NOT NULL,
    sim_run_id uuid,
    data_source text NOT NULL,
    pack_id text NOT NULL,
    operation_code text NOT NULL,
    vehicle_id uuid,
    asset_class_code text,
    fleet_operator_id uuid,
    depot_id uuid,
    stall_id uuid,
    source_kind text NOT NULL,
    leg_id uuid,
    schedule_task_id uuid,
    visit_id uuid,
    booking_id uuid,
    ocpp_session_id uuid,
    started_at timestamp with time zone,
    ended_at timestamp with time zone NOT NULL,
    duration_min numeric,
    energy_kwh numeric,
    peak_kw numeric,
    tariff_id uuid,
    attribution_id uuid,
    cost_components jsonb NOT NULL,
    total_cost_usd numeric,
    billable_amount_usd numeric,
    currency text NOT NULL,
    sdr_event_id uuid,
    payload_hash text NOT NULL,
    signature text,
    signature_key_id text,
    signature_algorithm text NOT NULL,
    status text NOT NULL,
    schema_version text NOT NULL,
    issued_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_service_endpoints
CREATE TABLE public.ottoq_service_endpoints (
    service_key text NOT NULL,
    base_url text NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by text NOT NULL,
    note text
);
-- @@ table public.ottoq_service_point_capabilities
CREATE TABLE public.ottoq_service_point_capabilities (
    stall_id uuid NOT NULL,
    asset_class_code text NOT NULL,
    pack_id text NOT NULL,
    operation_code text NOT NULL,
    active boolean NOT NULL,
    source text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_service_tariffs
CREATE TABLE public.ottoq_service_tariffs (
    tariff_id uuid NOT NULL,
    pack_id text NOT NULL,
    operation_code text NOT NULL,
    asset_class_code text,
    fleet_operator_id uuid,
    window_label text NOT NULL,
    price_usd numeric,
    price_unit text NOT NULL,
    currency text NOT NULL,
    effective_from timestamp with time zone NOT NULL,
    effective_until timestamp with time zone,
    active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_service_tokens
CREATE TABLE public.ottoq_service_tokens (
    token_id uuid NOT NULL,
    fleet_operator_id uuid,
    vehicle_id uuid,
    asset_class_code text,
    entitlements jsonb NOT NULL,
    status text NOT NULL,
    valid_from timestamp with time zone NOT NULL,
    valid_until timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_signing_keys
CREATE TABLE public.ottoq_signing_keys (
    key_id text NOT NULL,
    scope text NOT NULL,
    scope_id uuid,
    algorithm text NOT NULL,
    secret_ref text NOT NULL,
    is_active boolean NOT NULL,
    activated_at timestamp with time zone NOT NULL,
    rotated_at timestamp with time zone,
    rotation_reason text,
    created_by text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_sim_runs
CREATE TABLE public.ottoq_sim_runs (
    sim_run_id uuid NOT NULL,
    sim_run_seq bigint NOT NULL,
    scenario_id uuid NOT NULL,
    scenario_code text NOT NULL,
    started_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    last_tick_at timestamp with time zone,
    next_tick_due_at timestamp with time zone,
    sim_clock_start timestamp with time zone NOT NULL,
    sim_clock_current timestamp with time zone NOT NULL,
    sim_clock_end timestamp with time zone NOT NULL,
    time_scale numeric NOT NULL,
    tick_interval_seconds integer NOT NULL,
    tick_count integer NOT NULL,
    depot_id uuid,
    random_seed bigint NOT NULL,
    status text NOT NULL,
    failure_reason text,
    events_generated bigint NOT NULL,
    vehicles_simulated integer NOT NULL,
    charge_sessions integer NOT NULL,
    tasks_completed integer NOT NULL,
    anomalies_injected integer NOT NULL,
    emergencies_triggered integer NOT NULL,
    rule_evaluations bigint NOT NULL,
    rule_failures bigint NOT NULL,
    predictions_emitted bigint NOT NULL,
    recommendations_made bigint NOT NULL,
    timeline_cursor integer NOT NULL,
    validation_status text,
    validation_notes text,
    validation_assertions jsonb,
    run_by text,
    notes text,
    payload jsonb,
    policy text NOT NULL,
    ab_group_id uuid,
    crn_streams jsonb,
    demo_speed_x numeric NOT NULL,
    purged_at timestamp with time zone
);
-- @@ table public.ottoq_sim_scenarios
CREATE TABLE public.ottoq_sim_scenarios (
    scenario_id uuid NOT NULL,
    scenario_code text NOT NULL,
    title text NOT NULL,
    description text,
    default_duration_hours numeric NOT NULL,
    default_time_scale numeric NOT NULL,
    default_tick_seconds integer NOT NULL,
    default_random_seed bigint NOT NULL,
    default_depot_id uuid NOT NULL,
    weather_overrides jsonb,
    fleet_overrides jsonb,
    charger_overrides jsonb,
    grid_overrides jsonb,
    fault_injection jsonb,
    status text NOT NULL,
    introduced_in text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_site_base_history
CREATE TABLE public.ottoq_site_base_history (
    change_code text NOT NULL,
    depot_id uuid NOT NULL,
    stall_id uuid NOT NULL,
    valid_until timestamp with time zone NOT NULL,
    stall_code text NOT NULL,
    stall_type text NOT NULL,
    before jsonb NOT NULL,
    after jsonb NOT NULL,
    recorded_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_site_buildout_active
CREATE TABLE public.ottoq_site_buildout_active (
    depot_id uuid NOT NULL,
    buildout_code text NOT NULL,
    applied_at timestamp with time zone NOT NULL,
    backend_pid integer NOT NULL,
    pre_image jsonb NOT NULL
);
-- @@ table public.ottoq_site_buildouts
CREATE TABLE public.ottoq_site_buildouts (
    buildout_code text NOT NULL,
    depot_id uuid NOT NULL,
    title text NOT NULL,
    dcfc_posts integer NOT NULL,
    convert_l2 text[] NOT NULL,
    dcfc_max_concurrent_kw numeric NOT NULL,
    service_max_kw numeric NOT NULL,
    basis jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL,
    stall_set jsonb NOT NULL,
    buildable boolean NOT NULL
);
-- @@ table public.ottoq_site_power_excursion_ledger
CREATE TABLE public.ottoq_site_power_excursion_ledger (
    excursion_id bigint NOT NULL,
    sim_run_id uuid,
    depot_id uuid NOT NULL,
    snapshot_id uuid NOT NULL,
    sim_clock timestamp with time zone,
    severity_tier text NOT NULL,
    total_import_kw numeric NOT NULL,
    cap_kw numeric NOT NULL,
    excess_kw numeric NOT NULL,
    warn_kw numeric NOT NULL,
    ev_charging_kw numeric,
    bess_output_kw numeric,
    bess_charging_kw numeric,
    base_load_kw numeric,
    solar_kw numeric,
    cap_source text,
    dominant_component text,
    detected_at timestamp with time zone NOT NULL,
    source_kind text NOT NULL,
    published_cap_kw numeric,
    ev_over_cap_kw numeric
);
-- @@ table public.ottoq_site_power_plan_ledger
CREATE TABLE public.ottoq_site_power_plan_ledger (
    plan_id bigint NOT NULL,
    sim_run_id uuid,
    depot_id uuid NOT NULL,
    command_id uuid NOT NULL,
    tick_seq bigint,
    issued_at timestamp with time zone,
    finding text NOT NULL,
    service_max_kw numeric NOT NULL,
    demand_factor numeric,
    contract_derived_target_kw numeric,
    demand_target_kw numeric NOT NULL,
    target_excess_kw numeric NOT NULL,
    published_charge_cap_kw numeric,
    base_load_kw numeric,
    solar_kw numeric,
    advisory boolean,
    reserve_shave_on boolean,
    captured_at timestamp with time zone NOT NULL,
    source_kind text NOT NULL
);
-- @@ table public.ottoq_site_structures
CREATE TABLE public.ottoq_site_structures (
    structure_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    structure_code text NOT NULL,
    structure_kind text NOT NULL,
    title text,
    origin_x_ft numeric NOT NULL,
    origin_y_ft numeric NOT NULL,
    width_ft numeric,
    length_ft numeric,
    height_ft numeric,
    rotation_deg numeric,
    absolute_lat numeric,
    absolute_lng numeric,
    properties jsonb NOT NULL,
    status text NOT NULL,
    introduced_in text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_sla_conformance_daily
CREATE TABLE public.ottoq_sla_conformance_daily (
    conformance_id uuid NOT NULL,
    fleet_operator_id uuid NOT NULL,
    depot_id uuid,
    report_date date NOT NULL,
    sla_contract_reference text,
    total_visits integer NOT NULL,
    compliant_visits integer NOT NULL,
    partial_visits integer NOT NULL,
    non_compliant_visits integer NOT NULL,
    pct_meeting_min_soc numeric,
    pct_meeting_max_visit_time numeric,
    pct_meeting_required_services numeric,
    pct_meeting_oem_gate numeric,
    pct_within_queue_depth numeric,
    pct_in_maintenance_window numeric,
    pct_no_blocking_exceptions numeric,
    overall_compliance_pct numeric,
    composite_grade text,
    total_variance_minutes numeric,
    estimated_penalty_usd numeric,
    total_kwh_delivered numeric,
    total_visit_minutes numeric,
    total_services_completed integer,
    computed_at timestamp with time zone NOT NULL,
    rule_eval_sample_ids uuid[],
    visit_report_sample_ids uuid[]
);
-- @@ table public.ottoq_sla_violations
CREATE TABLE public.ottoq_sla_violations (
    violation_id uuid NOT NULL,
    fleet_operator_id uuid NOT NULL,
    depot_id uuid,
    vehicle_id uuid,
    schedule_id uuid,
    rule_code text NOT NULL,
    rule_evaluation_id uuid,
    clause_text text,
    expected_value jsonb,
    observed_value jsonb,
    variance_amount numeric,
    variance_unit text,
    severity text NOT NULL,
    detected_at timestamp with time zone NOT NULL,
    acknowledged_at timestamp with time zone,
    acknowledged_by text,
    remediation_note text,
    linked_event_id uuid,
    correlation_id uuid
);
-- @@ table public.ottoq_solar_output
CREATE TABLE public.ottoq_solar_output (
    output_id uuid NOT NULL,
    output_seq bigint NOT NULL,
    depot_id uuid NOT NULL,
    sim_run_id uuid,
    weather_snapshot_id uuid,
    canopy_structure_id uuid,
    canopy_code text NOT NULL,
    sim_clock_at timestamp with time zone NOT NULL,
    irradiance_poa_wm2 numeric,
    ambient_temp_c numeric,
    cell_temp_c numeric,
    soiling_factor numeric,
    nameplate_dc_kw numeric NOT NULL,
    nameplate_ac_kw numeric NOT NULL,
    dc_power_kw numeric,
    ac_power_kw numeric,
    inverter_efficiency numeric,
    inverter_clipped boolean NOT NULL,
    inverter_blip boolean NOT NULL,
    data_source text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_space_integrity_ledger
CREATE TABLE public.ottoq_space_integrity_ledger (
    incident_id bigint NOT NULL,
    recorded_at timestamp with time zone NOT NULL,
    sim_run_id uuid,
    depot_id uuid,
    evaluated_at timestamp with time zone NOT NULL,
    sim_clock timestamp with time zone,
    rule_code text NOT NULL,
    action_context text,
    incident_kind text NOT NULL,
    stall_id uuid NOT NULL,
    stall_type text,
    stall_status text,
    expected_vehicle_id uuid NOT NULL,
    stall_current_vehicle_id uuid,
    had_open_charge_session boolean,
    open_session_started_at timestamp with time zone,
    tether_until timestamp with time zone,
    tether_stall_id uuid,
    exposed_to_pointer_clear boolean,
    source_evaluation_id uuid,
    detail jsonb NOT NULL
);
-- @@ table public.ottoq_specialization_strategies
CREATE TABLE public.ottoq_specialization_strategies (
    strategy_id uuid NOT NULL,
    prediction_type text NOT NULL,
    specialization_level text NOT NULL,
    enabled boolean NOT NULL,
    min_samples_required integer NOT NULL,
    min_days_of_history integer NOT NULL,
    min_improvement_pct numeric NOT NULL,
    description text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_stall_bookings
CREATE TABLE public.ottoq_stall_bookings (
    booking_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    stall_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    visit_id uuid,
    leg_id uuid,
    purpose text NOT NULL,
    during tstzrange NOT NULL,
    state text NOT NULL,
    booked_at timestamp with time zone NOT NULL,
    booked_by text NOT NULL,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    booked_at_sim timestamp with time zone
);
-- @@ table public.ottoq_stall_distance_backup_20260812
CREATE TABLE public.ottoq_stall_distance_backup_20260812 (
    id uuid,
    depot_id uuid,
    stall_code text,
    stall_type text,
    relative_x double precision,
    relative_y double precision,
    distance_before integer
);
-- @@ table public.ottoq_state_transitions
CREATE TABLE public.ottoq_state_transitions (
    transition_id uuid NOT NULL,
    entity_kind text NOT NULL,
    from_state text NOT NULL,
    to_state text NOT NULL,
    trigger_event text,
    allowed_actor_types text[] NOT NULL,
    required_conditions text[],
    description text,
    introduced_in text,
    status text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_t4_coverage_samples
CREATE TABLE public.ottoq_t4_coverage_samples (
    id bigint NOT NULL,
    sim_run_id uuid NOT NULL,
    taken_at timestamp with time zone NOT NULL,
    moving integer,
    covered integer,
    ratio numeric,
    open_legs integer,
    states jsonb,
    orphan_legs integer
);
-- @@ table public.ottoq_tariff_windows
CREATE TABLE public.ottoq_tariff_windows (
    tariff_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    label text NOT NULL,
    rate_usd_per_kwh numeric NOT NULL,
    hour_start integer NOT NULL,
    hour_end integer NOT NULL,
    day_of_week_mask integer NOT NULL,
    season text NOT NULL,
    active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_telemetry_packets
CREATE TABLE public.ottoq_telemetry_packets (
    packet_id uuid NOT NULL,
    packet_seq bigint NOT NULL,
    vehicle_id uuid NOT NULL,
    sim_run_id uuid,
    fleet_operator_id uuid,
    packet_at timestamp with time zone NOT NULL,
    sim_clock_at timestamp with time zone,
    soc_pct numeric,
    soc_source text,
    battery_temp_c numeric,
    motor_temp_c numeric,
    cabin_temp_c numeric,
    ambient_temp_c numeric,
    tire_pressures_psi numeric[],
    speed_kmh numeric,
    heading_deg numeric,
    current_lat numeric,
    current_lng numeric,
    instant_power_kw numeric,
    power_15min_avg_kw numeric,
    vehicle_state text,
    odometer_km numeric,
    range_remaining_km numeric,
    dtc_codes text[],
    active_warnings text[],
    signal_strength_pct numeric,
    packet_integrity text,
    dropped_reason text,
    data_source text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_throughput_scores
CREATE TABLE public.ottoq_throughput_scores (
    score_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_throughput_scores_score_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    sim_run_id uuid NOT NULL,
    scenario_code text,
    random_seed bigint,
    tick_count integer,
    policy text,
    step_min numeric,
    scorecard jsonb NOT NULL,
    scorecard_md5 text NOT NULL,
    origin text NOT NULL,
    scored_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_throughput_sweep_arms
CREATE TABLE public.ottoq_throughput_sweep_arms (
    arm_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_throughput_sweep_arms_arm_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    sweep_id uuid NOT NULL,
    cell_id uuid NOT NULL,
    seed bigint NOT NULL,
    replicate boolean NOT NULL,
    sim_run_id uuid,
    engine_hash text NOT NULL,
    dial_floor timestamp with time zone NOT NULL,
    ran_at timestamp with time zone NOT NULL,
    complete boolean NOT NULL,
    ticks integer,
    wall_s numeric,
    paid_shield boolean,
    boot_md5 text,
    h_cal text,
    atoms jsonb,
    buildout jsonb,
    restore jsonb,
    score_id bigint,
    scorecard jsonb,
    arm_metrics jsonb,
    arm_error jsonb,
    fleet_buildout jsonb,
    fleet_restore jsonb
);
-- @@ table public.ottoq_throughput_sweep_cells
CREATE TABLE public.ottoq_throughput_sweep_cells (
    cell_id uuid NOT NULL,
    sweep_id uuid NOT NULL,
    cell_code text NOT NULL,
    ord integer NOT NULL,
    seat text NOT NULL,
    buildout_code text NOT NULL,
    fixed_params jsonb NOT NULL,
    control_cell_code text
);
-- @@ table public.ottoq_throughput_sweeps
CREATE TABLE public.ottoq_throughput_sweeps (
    sweep_id uuid NOT NULL,
    sweep_code text NOT NULL,
    title text NOT NULL,
    depot_id uuid NOT NULL,
    scenario text NOT NULL,
    sim_start timestamp with time zone NOT NULL,
    ticks integer NOT NULL,
    sim_min_per_tick numeric NOT NULL,
    seeds bigint[] NOT NULL,
    replicates integer NOT NULL,
    priority integer NOT NULL,
    arm_budget_s integer,
    status text NOT NULL,
    run_after timestamp with time zone,
    notes text,
    created_by text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    concluded_at timestamp with time zone,
    fleet_code text
);
-- @@ table public.ottoq_tick_clock_log
CREATE TABLE public.ottoq_tick_clock_log (
    sim_run_id uuid NOT NULL,
    tick_seq integer NOT NULL,
    real_started_at timestamp with time zone NOT NULL,
    real_ended_at timestamp with time zone NOT NULL,
    sim_clock_before timestamp with time zone NOT NULL,
    sim_clock_after timestamp with time zone NOT NULL,
    tick_compute_ms numeric NOT NULL,
    sim_advance_s numeric NOT NULL,
    playback_mode text,
    speed_x numeric
);
-- @@ table public.ottoq_tick_invariance_arms
CREATE TABLE public.ottoq_tick_invariance_arms (
    cert_seed bigint NOT NULL,
    tick_minutes numeric NOT NULL,
    sim_run_id uuid,
    scenario_code text NOT NULL,
    sim_minutes numeric NOT NULL,
    status text NOT NULL,
    metrics jsonb,
    started_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone
);
-- @@ table public.ottoq_tick_reservations
CREATE TABLE public.ottoq_tick_reservations (
    reservation_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    tick_seq bigint NOT NULL,
    depot_id uuid NOT NULL,
    resource text NOT NULL,
    entity_id uuid,
    amount_kw numeric NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_training_runs
CREATE TABLE public.ottoq_training_runs (
    training_run_id uuid NOT NULL,
    prediction_type text NOT NULL,
    model_family text,
    parent_model_version_id uuid,
    resulting_model_version_id uuid,
    started_at timestamp with time zone NOT NULL,
    completed_at timestamp with time zone,
    duration_seconds integer,
    dataset_window_start timestamp with time zone,
    dataset_window_end timestamp with time zone,
    dataset_n_samples bigint,
    dataset_n_features integer,
    feature_names text[],
    train_n bigint,
    validation_n bigint,
    test_n bigint,
    dataset_hash text,
    hyperparameters jsonb NOT NULL,
    trainer text,
    trainer_user text,
    notebook_url text,
    git_commit_sha text,
    training_metrics jsonb NOT NULL,
    test_metrics jsonb,
    cross_validation jsonb,
    artifact_storage_path text,
    artifact_format text,
    artifact_size_bytes bigint,
    artifact_sha256 text,
    status text NOT NULL,
    failure_reason text,
    fleet_operator_id uuid,
    depot_id uuid,
    vehicle_class text,
    triggered_by text,
    triggered_by_alert_id uuid,
    notes text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_v2_cursors
CREATE TABLE public.ottoq_v2_cursors (
    cursor_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_v2_cursors_cursor_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    source_name text NOT NULL,
    ce_source text NOT NULL,
    sim_run_id uuid,
    last_sequence text,
    applied bigint NOT NULL,
    late bigint NOT NULL,
    gaps numeric NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_v2_inbox
CREATE TABLE public.ottoq_v2_inbox (
    inbox_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_v2_inbox_inbox_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    received_at timestamp with time zone NOT NULL,
    key_id uuid NOT NULL,
    source_name text NOT NULL,
    depot_id uuid NOT NULL,
    data_source text NOT NULL,
    sim_run_id uuid,
    clock_at timestamp with time zone NOT NULL,
    ce_id text NOT NULL,
    ce_source text NOT NULL,
    ce_type text NOT NULL,
    ce_time timestamp with time zone NOT NULL,
    ce_subject text,
    ce_sequence text NOT NULL,
    vehicle_id uuid,
    disposition text NOT NULL,
    detail jsonb NOT NULL,
    event jsonb NOT NULL
);
-- @@ table public.ottoq_v2_signal_ttl
CREATE TABLE public.ottoq_v2_signal_ttl (
    data_source text NOT NULL,
    vss_path text NOT NULL,
    ttl_s integer NOT NULL,
    note text
);
-- @@ table public.ottoq_v2_signing_keys
CREATE TABLE public.ottoq_v2_signing_keys (
    kid text NOT NULL,
    public_jwk jsonb NOT NULL,
    vault_secret_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    retired_at timestamp with time zone
);
-- @@ table public.ottoq_variability_cards
CREATE TABLE public.ottoq_variability_cards (
    id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.ottoq_variability_cards_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    sim_run_id uuid NOT NULL,
    var_key text NOT NULL,
    scope_instance text NOT NULL,
    lifespan text NOT NULL,
    bucket_key text NOT NULL,
    value numeric,
    meta jsonb NOT NULL,
    active boolean NOT NULL,
    drawn_at_clock timestamp with time zone,
    drawn_at_tick bigint,
    created_at timestamp with time zone NOT NULL
) WITH (autovacuum_vacuum_scale_factor=0.02, autovacuum_vacuum_threshold=500, autovacuum_analyze_scale_factor=0.02, autovacuum_analyze_threshold=500, autovacuum_vacuum_cost_delay=2, autovacuum_vacuum_cost_limit=2000);
-- @@ table public.ottoq_variability_catalog
CREATE TABLE public.ottoq_variability_catalog (
    var_key text NOT NULL,
    domain text NOT NULL,
    label text NOT NULL,
    definition text NOT NULL,
    unit text,
    kind text NOT NULL,
    knob_types text[] NOT NULL,
    neutral_value numeric,
    min_value numeric,
    max_value numeric,
    step numeric,
    select_options text[],
    is_primary boolean NOT NULL,
    wired boolean NOT NULL,
    generator text,
    display_order integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    lifespan text,
    scope text,
    redraw_event text
);
-- @@ table public.ottoq_variability_profiles
CREATE TABLE public.ottoq_variability_profiles (
    profile_id uuid NOT NULL,
    sim_run_id uuid,
    name text,
    knobs jsonb NOT NULL,
    notes text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_vehicle_classes
CREATE TABLE public.ottoq_vehicle_classes (
    vehicle_class_code text NOT NULL,
    oem_name text NOT NULL,
    oem_fleet_operator_id uuid,
    manufacturer text,
    model text,
    model_year integer,
    trim_or_variant text,
    battery_capacity_kwh numeric,
    battery_chemistry text,
    max_charge_rate_kw numeric,
    inlet_type text,
    curb_weight_kg numeric,
    typical_daily_kwh numeric,
    expected_lifetime_miles bigint,
    fast_charge_compatible boolean,
    status text NOT NULL,
    introduced_in text,
    notes text,
    created_at timestamp with time zone NOT NULL,
    pack_id text NOT NULL,
    energy_curve jsonb,
    duty_cycle_profile jsonb,
    charge_kinds text[] NOT NULL
);
-- @@ table public.ottoq_vehicle_commands
CREATE TABLE public.ottoq_vehicle_commands (
    command_id uuid NOT NULL,
    sim_run_id uuid,
    depot_id uuid,
    vehicle_id uuid NOT NULL,
    command_type text NOT NULL,
    payload jsonb,
    issued_at timestamp with time zone NOT NULL,
    issued_by text NOT NULL,
    status text NOT NULL,
    confirmed_at timestamp with time zone,
    confirmed_by text,
    executed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    reason_code text,
    reason_detail text,
    reacted_at timestamp with time zone,
    command_seq bigint GENERATED BY DEFAULT AS IDENTITY (SEQUENCE NAME public.ottoq_vehicle_commands_command_seq_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    data_source text NOT NULL,
    delivered_at timestamp with time zone,
    delivered_to text
) WITH (autovacuum_vacuum_scale_factor=0.02, autovacuum_vacuum_threshold=500, autovacuum_analyze_scale_factor=0.02, autovacuum_analyze_threshold=500, autovacuum_vacuum_cost_delay=2, autovacuum_vacuum_cost_limit=2000);
-- @@ table public.ottoq_vehicle_dispatches
CREATE TABLE public.ottoq_vehicle_dispatches (
    dispatch_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    sim_run_id uuid,
    fleet_operator_id uuid,
    dispatched_at timestamp with time zone NOT NULL,
    scheduled_return_at timestamp with time zone NOT NULL,
    actual_return_at timestamp with time zone,
    planned_duration_min numeric NOT NULL,
    actual_duration_min numeric,
    arrival_jitter_min numeric,
    soc_at_dispatch_pct numeric,
    soc_at_return_pct numeric,
    energy_consumed_kwh numeric,
    miles_driven numeric,
    return_trigger text,
    return_state text,
    status text NOT NULL,
    data_source text,
    created_at timestamp with time zone NOT NULL,
    returning_started_at timestamp with time zone,
    return_eta_minutes numeric,
    return_evidence jsonb,
    heartbeat_count integer NOT NULL,
    planned_return_at timestamp with time zone GENERATED ALWAYS AS ((((dispatched_at AT TIME ZONE 'UTC'::text) + ((planned_duration_min)::double precision * '00:01:00'::interval)) AT TIME ZONE 'UTC'::text)) STORED,
    eta_refreshed_at timestamp with time zone,
    eta_source text
) WITH (autovacuum_vacuum_scale_factor=0.02, autovacuum_vacuum_threshold=500, autovacuum_analyze_scale_factor=0.02, autovacuum_analyze_threshold=500, autovacuum_vacuum_cost_delay=2, autovacuum_vacuum_cost_limit=2000);
-- @@ table public.ottoq_vehicle_incidents
CREATE TABLE public.ottoq_vehicle_incidents (
    incident_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    sim_run_id uuid,
    occurred_at timestamp with time zone NOT NULL,
    recorded_at timestamp with time zone NOT NULL,
    incident_type text NOT NULL,
    severity text NOT NULL,
    at_lat numeric,
    at_lng numeric,
    speed_kmh_at_event numeric,
    soc_pct_at_event numeric,
    description text,
    requires_tow boolean NOT NULL,
    resolution_status text,
    data_source text NOT NULL,
    linked_event_id uuid
);
-- @@ table public.ottoq_vehicle_itineraries
CREATE TABLE public.ottoq_vehicle_itineraries (
    itinerary_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    created_by text NOT NULL,
    status text NOT NULL,
    sim_created_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    visit_id uuid
);
-- @@ table public.ottoq_vehicle_scout_findings
CREATE TABLE public.ottoq_vehicle_scout_findings (
    finding_id bigint NOT NULL,
    sim_run_id uuid,
    depot_id uuid,
    vehicle_id uuid NOT NULL,
    scout text NOT NULL,
    severity text NOT NULL,
    episode_key text NOT NULL,
    first_seen_sim_clock timestamp with time zone,
    first_seen_tick bigint,
    detail jsonb NOT NULL,
    recorded_at timestamp with time zone NOT NULL,
    source_kind text NOT NULL
);
-- @@ table public.ottoq_vehicle_wear
CREATE TABLE public.ottoq_vehicle_wear (
    vehicle_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    drive_km_total numeric NOT NULL,
    drive_hours_total numeric NOT NULL,
    backfilled_km numeric NOT NULL,
    backfilled_hours numeric NOT NULL,
    km_at_last_pm numeric NOT NULL,
    hours_at_last_calibration numeric NOT NULL,
    calibrated_at timestamp with time zone,
    soil_index numeric NOT NULL,
    cabin_litter_events integer NOT NULL,
    open_dtc_count integer NOT NULL,
    worst_open_dtc_rank smallint NOT NULL,
    last_advanced_tick bigint,
    last_advanced_sim_clock timestamp with time zone,
    km_per_tick_ema numeric NOT NULL,
    drive_ticks_observed integer NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_visit_cost_attribution
CREATE TABLE public.ottoq_visit_cost_attribution (
    attribution_id uuid NOT NULL,
    attribution_seq bigint NOT NULL,
    schedule_id uuid NOT NULL,
    visit_report_id uuid,
    vehicle_id uuid,
    fleet_operator_id uuid,
    depot_id uuid,
    visit_started_at timestamp with time zone,
    visit_completed_at timestamp with time zone,
    visit_duration_min numeric,
    kwh_delivered numeric,
    kwh_from_grid numeric,
    kwh_from_solar numeric,
    kwh_from_bess numeric,
    peak_kw_during_visit numeric,
    energy_cost_usd numeric,
    demand_charge_usd numeric,
    labor_cost_usd numeric,
    opportunity_cost_usd numeric,
    consumables_cost_usd numeric,
    total_cost_usd numeric,
    billable_amount_usd numeric,
    margin_usd numeric,
    margin_pct numeric,
    carbon_offset_kg_co2 numeric,
    grid_carbon_intensity_kg_per_kwh numeric,
    cost_components jsonb,
    computed_at timestamp with time zone NOT NULL,
    compute_method text,
    data_quality_score numeric,
    notes text
);
-- @@ table public.ottoq_visit_needs
CREATE TABLE public.ottoq_visit_needs (
    visit_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone NOT NULL,
    visit_key text NOT NULL,
    archetype text,
    urgency text NOT NULL,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb NOT NULL,
    status text NOT NULL,
    source text NOT NULL,
    meta jsonb,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_wave_plan
CREATE TABLE public.ottoq_wave_plan (
    plan_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    want_class text NOT NULL,
    charge_start_at timestamp with time zone,
    charge_end_at timestamp with time zone,
    charge_minutes numeric,
    target_soc numeric,
    due_at timestamp with time zone,
    feasible boolean NOT NULL,
    reason text,
    generator text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_wear_tick_status
CREATE TABLE public.ottoq_wear_tick_status (
    sim_run_id uuid NOT NULL,
    tick_seq bigint NOT NULL,
    sim_clock timestamp with time zone,
    attempted integer NOT NULL,
    written integer NOT NULL,
    note text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_weather_snapshots
CREATE TABLE public.ottoq_weather_snapshots (
    snapshot_id uuid NOT NULL,
    snapshot_seq bigint NOT NULL,
    depot_id uuid NOT NULL,
    sim_run_id uuid,
    sim_clock_at timestamp with time zone NOT NULL,
    solar_elevation_deg numeric,
    solar_azimuth_deg numeric,
    air_mass numeric,
    ambient_temp_c numeric,
    cloud_cover_pct numeric,
    wind_speed_kmh numeric,
    wind_direction_deg numeric,
    relative_humidity_pct numeric,
    precip_mm_per_hr numeric,
    precip_state text,
    ghi_wm2 numeric,
    dni_wm2 numeric,
    dhi_wm2 numeric,
    poa_wm2 numeric,
    conditions_label text,
    is_daytime boolean,
    data_source text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottoq_write_slimming_policy
CREATE TABLE public.ottoq_write_slimming_policy (
    policy_key text NOT NULL,
    enabled boolean NOT NULL,
    chain_event_types text[] NOT NULL,
    slim_created boolean NOT NULL,
    notes text,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottow_api_keys
CREATE TABLE public.ottow_api_keys (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    key_hash text NOT NULL,
    key_prefix text NOT NULL,
    source text NOT NULL,
    source_name text NOT NULL,
    allowed_platforms text[],
    is_active boolean NOT NULL,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    created_by_user_id uuid,
    data_source text NOT NULL,
    streams text[],
    revoked_at timestamp with time zone,
    revoke_reason text,
    fleet_operator_ids uuid[]
);
-- @@ table public.ottow_dispatch_rules
CREATE TABLE public.ottow_dispatch_rules (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    rule_name text NOT NULL,
    is_active boolean NOT NULL,
    match_incident_category text,
    match_priority text,
    match_source text,
    action text NOT NULL,
    auto_assign_driver boolean NOT NULL,
    max_driver_distance_miles numeric(6,2),
    required_certs text[],
    priority_order integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottow_drivers
CREATE TABLE public.ottow_drivers (
    id uuid NOT NULL,
    staff_user_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    status text NOT NULL,
    current_mission_id uuid,
    vehicle_class_certs text[],
    last_location_lat numeric(10,7),
    last_location_lng numeric(10,7),
    last_location_at timestamp with time zone,
    shift_start timestamp with time zone,
    shift_end timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.ottow_mission_events
CREATE TABLE public.ottow_mission_events (
    id uuid NOT NULL,
    mission_id uuid NOT NULL,
    event_type text NOT NULL,
    from_status text,
    to_status text,
    location_lat numeric(10,7),
    location_lng numeric(10,7),
    actor_id uuid,
    actor_type text,
    notes text,
    metadata jsonb,
    client_timestamp timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.ottow_missions
CREATE TABLE public.ottow_missions (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    exception_id uuid,
    vehicle_id uuid NOT NULL,
    driver_staff_id uuid,
    ottow_vehicle_id uuid,
    status text NOT NULL,
    priority text NOT NULL,
    incident_category text NOT NULL,
    pickup_location_lat numeric(10,7),
    pickup_location_lng numeric(10,7),
    pickup_address text,
    pickup_notes text,
    destination_stall_id uuid,
    destination_stall_type text,
    eta_minutes integer,
    distance_miles numeric(6,2),
    driver_lat numeric(10,7),
    driver_lng numeric(10,7),
    driver_heading numeric(5,1),
    driver_speed_mph numeric(5,1),
    driver_location_updated_at timestamp with time zone,
    dispatched_at timestamp with time zone,
    en_route_at timestamp with time zone,
    on_site_at timestamp with time zone,
    vehicle_secured_at timestamp with time zone,
    returning_at timestamp with time zone,
    arrived_depot_at timestamp with time zone,
    stall_assigned_at timestamp with time zone,
    vehicle_delivered_at timestamp with time zone,
    closed_at timestamp with time zone,
    cancelled_at timestamp with time zone,
    cancellation_reason text,
    notes text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    source text,
    external_reference_id text,
    notification_id uuid
);
-- @@ table public.ottow_notifications
CREATE TABLE public.ottow_notifications (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    source text NOT NULL,
    external_reference_id text,
    webhook_payload jsonb,
    status text NOT NULL,
    vehicle_id uuid,
    vehicle_platform text,
    vehicle_external_id text,
    vehicle_vin text,
    incident_category text NOT NULL,
    priority text NOT NULL,
    incident_lat numeric(10,7),
    incident_lng numeric(10,7),
    incident_address text,
    description text,
    exception_id uuid,
    auto_dispatch_eligible boolean NOT NULL,
    auto_dispatch_reason text,
    reviewed_by_user_id uuid,
    reviewed_at timestamp with time zone,
    rejection_reason text,
    mission_id uuid,
    dedup_key text NOT NULL,
    received_at timestamp with time zone NOT NULL,
    acknowledged_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.p3_phantom_smoke_2026_08_02
CREATE TABLE public.p3_phantom_smoke_2026_08_02 (
    id bigint NOT NULL,
    taken_at timestamp with time zone,
    phase text,
    k text,
    v text,
    note text
);
-- @@ table public.p3_smoke_restore_2026_08_02
CREATE TABLE public.p3_smoke_restore_2026_08_02 (
    kind text,
    obj_id uuid,
    col text,
    val text
);
-- @@ table public.p7_band_probe_2026_08_03
CREATE TABLE public.p7_band_probe_2026_08_03 (
    seq bigint NOT NULL,
    at_real timestamp with time zone,
    sim_run_id uuid,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    note text,
    detail jsonb
);
-- @@ table public.p7_cuopt_supply_proof_2026_08_03
CREATE TABLE public.p7_cuopt_supply_proof_2026_08_03 (
    seq bigint NOT NULL,
    at_real timestamp with time zone,
    step text,
    claim text,
    detail jsonb
);
-- @@ table public.phantom_provenance_proof_2026_08_02
CREATE TABLE public.phantom_provenance_proof_2026_08_02 (
    captured_at timestamp with time zone NOT NULL,
    phase text NOT NULL,
    detail jsonb NOT NULL
);
-- @@ table public.pre0002_approvals_evidence
CREATE TABLE public.pre0002_approvals_evidence (
    approval_id uuid,
    approval_type text,
    vehicle_id uuid,
    visit_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    status text,
    priority text,
    payload jsonb,
    requested_at timestamp with time zone,
    decide_after timestamp with time zone,
    expires_at timestamp with time zone,
    decided_at timestamp with time zone,
    decided_by text,
    created_at timestamp with time zone
);
-- @@ table public.prediction_accuracy_daily
CREATE TABLE public.prediction_accuracy_daily (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    report_date date NOT NULL,
    prediction_type text NOT NULL,
    time_horizon_hours integer,
    total_predictions integer NOT NULL,
    scored_predictions integer NOT NULL,
    mean_accuracy numeric(5,4),
    median_accuracy numeric(5,4),
    min_accuracy numeric(5,4),
    max_accuracy numeric(5,4),
    std_deviation numeric(5,4),
    mape numeric(5,4),
    rmse numeric(10,4),
    directional_accuracy numeric(5,4),
    accuracy_7d_avg numeric(5,4),
    accuracy_30d_avg numeric(5,4),
    trend_direction text,
    trend_slope numeric(8,6),
    actions_taken integer,
    actions_successful integer,
    actions_rolled_back integer,
    action_success_rate numeric(5,4),
    estimated_kwh_saved numeric(10,2),
    estimated_cost_saved numeric(10,2),
    demand_peaks_avoided integer,
    stall_conflicts_avoided integer,
    model_version integer,
    parameters_hash text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.prediction_explanations
CREATE TABLE public.prediction_explanations (
    id uuid NOT NULL,
    prediction_id uuid NOT NULL,
    top_similar_snapshots jsonb NOT NULL,
    external_factors_used jsonb NOT NULL,
    feature_importance jsonb NOT NULL,
    sensitivity_analysis jsonb,
    confidence_decomposition jsonb NOT NULL,
    risk_factor_weights jsonb,
    model_version_id uuid,
    ab_test_id uuid,
    ab_test_variant text,
    generation_method text NOT NULL,
    generated_at timestamp with time zone NOT NULL,
    generation_ms integer,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.prediction_outcomes
CREATE TABLE public.prediction_outcomes (
    id uuid NOT NULL,
    prediction_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    predicted_value jsonb NOT NULL,
    actual_value jsonb NOT NULL,
    accuracy_score numeric(5,4) NOT NULL,
    scoring_method text NOT NULL,
    time_horizon_hours integer NOT NULL,
    prediction_type text NOT NULL,
    scored_at timestamp with time zone NOT NULL,
    scoring_delay_ms integer,
    notes text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.preimport_depots_site_20260806
CREATE TABLE public.preimport_depots_site_20260806 (
    id uuid,
    name text,
    site_length_ft numeric,
    site_width_ft numeric,
    site_acres numeric,
    site_layout jsonb
);
-- @@ table public.preimport_released_reservations_20260806
CREATE TABLE public.preimport_released_reservations_20260806 (
    id uuid,
    depot_id uuid,
    stall_code text,
    status text,
    current_vehicle_id uuid,
    reserved_by uuid,
    reserved_at timestamp with time zone,
    reservation_expires_at timestamp with time zone,
    reserved_for_mission_id uuid,
    captured_at timestamp with time zone
);
-- @@ table public.preimport_site_structures_20260806
CREATE TABLE public.preimport_site_structures_20260806 (
    structure_id uuid,
    depot_id uuid,
    structure_code text,
    structure_kind text,
    title text,
    origin_x_ft numeric,
    origin_y_ft numeric,
    width_ft numeric,
    length_ft numeric,
    height_ft numeric,
    rotation_deg numeric,
    absolute_lat numeric,
    absolute_lng numeric,
    properties jsonb,
    status text,
    introduced_in text,
    created_at timestamp with time zone,
    preserved_at timestamp with time zone
);
-- @@ table public.preimport_stall_bookings_20260806
CREATE TABLE public.preimport_stall_bookings_20260806 (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text,
    booked_at_sim timestamp with time zone,
    stall_code text,
    stall_depot_id uuid,
    preserved_at timestamp with time zone
);
-- @@ table public.preimport_stalls_20260806
CREATE TABLE public.preimport_stalls_20260806 (
    id uuid,
    depot_id uuid,
    stall_code text,
    stall_type public.stall_type,
    display_name text,
    relative_x double precision,
    relative_y double precision,
    heading_degrees smallint,
    absolute_lat double precision,
    absolute_lng double precision,
    absolute_point public.geography(Point,4326),
    distance_from_entrance integer,
    status text,
    current_vehicle_id uuid,
    equipment_config jsonb,
    fiducial_marker_id text,
    uwb_beacon_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    zone text,
    reserved_for_mission_id uuid,
    connector_type text,
    connector_max_kw numeric,
    supported_inlet_types text[],
    ocpp_charger_id uuid,
    stall_kind text,
    canopy_code text,
    covered boolean,
    stall_width_ft numeric,
    stall_depth_ft numeric,
    reserved_by uuid,
    reserved_at timestamp with time zone,
    reservation_expires_at timestamp with time zone,
    staging_role text
);
-- @@ table public.preimport_structures_20260806
CREATE TABLE public.preimport_structures_20260806 (
    structure_id uuid,
    depot_id uuid,
    structure_code text,
    structure_kind text,
    title text,
    origin_x_ft numeric,
    origin_y_ft numeric,
    width_ft numeric,
    length_ft numeric,
    height_ft numeric,
    rotation_deg numeric,
    absolute_lat numeric,
    absolute_lng numeric,
    properties jsonb,
    status text,
    introduced_in text,
    created_at timestamp with time zone
);
-- @@ table public.preimport_vehicle_state_log_doomed_20260806
CREATE TABLE public.preimport_vehicle_state_log_doomed_20260806 (
    id uuid,
    vehicle_id uuid,
    depot_id uuid,
    previous_state public.vehicle_state,
    new_state public.vehicle_state,
    triggered_by public.trigger_source,
    trigger_user_id uuid,
    stall_id uuid,
    schedule_task_id uuid,
    vehicle_schedule_id uuid,
    metadata jsonb,
    created_at timestamp with time zone,
    stall_code text,
    preserved_at timestamp with time zone
);
-- @@ table public.prof0012_act
CREATE TABLE public.prof0012_act (
    id bigint NOT NULL,
    taken_at timestamp with time zone,
    pid integer,
    usename text,
    state text,
    wait_event_type text,
    wait_event text,
    xact_age_s numeric,
    query_age_s numeric,
    q text
);
-- @@ table public.prof0012_cron_prestate
CREATE TABLE public.prof0012_cron_prestate (
    jobid bigint,
    schedule text,
    command text,
    nodename text,
    nodeport integer,
    database text,
    username text,
    active boolean,
    jobname text,
    captured_at timestamp with time zone
);
-- @@ table public.prof0012_pgss
CREATE TABLE public.prof0012_pgss (
    id bigint NOT NULL,
    taken_at timestamp with time zone,
    label text,
    queryid bigint,
    calls bigint,
    total_exec_time double precision,
    rows bigint,
    query text
);
-- @@ table public.prof0012_tabstat
CREATE TABLE public.prof0012_tabstat (
    id bigint NOT NULL,
    taken_at timestamp with time zone,
    label text,
    relname text,
    seq_scan bigint,
    seq_tup_read bigint,
    idx_scan bigint,
    idx_tup_fetch bigint,
    n_tup_ins bigint,
    n_tup_upd bigint,
    n_tup_del bigint
);
-- @@ table public.prof0012_tick
CREATE TABLE public.prof0012_tick (
    id bigint NOT NULL,
    taken_at timestamp with time zone,
    sim_run_id uuid,
    tick integer,
    phase text,
    ms numeric,
    note jsonb
);
-- @@ table public.progression_decisions
CREATE TABLE public.progression_decisions (
    id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    task_id uuid,
    schedule_id uuid,
    depot_id uuid NOT NULL,
    fleet_operator_id uuid,
    decided_at timestamp with time zone NOT NULL,
    decision text NOT NULL,
    triggered_by text NOT NULL,
    triggered_by_id text,
    from_stall_id uuid,
    to_stall_id uuid,
    from_task_sequence integer,
    to_task_sequence integer,
    audit_note text,
    latency_ms integer,
    payload jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.proof0008_cron_prestate
CREATE TABLE public.proof0008_cron_prestate (
    jobid bigint,
    jobname text,
    schedule text,
    active boolean,
    command text,
    captured_at timestamp with time zone
);
-- @@ table public.proof0008_profile_prestate
CREATE TABLE public.proof0008_profile_prestate (
    vehicle_id uuid,
    profile_version text,
    drawn_for_run uuid,
    drawn_seed bigint,
    drawn_at timestamp with time zone,
    drawn_at_sim_clock timestamp with time zone,
    battery_soh_pct numeric,
    battery_chemistry text,
    charge_accept_kw numeric,
    pack_temp_c numeric,
    dcfc_safe boolean,
    dcfc_block_reason text,
    cell_balance_due_at timestamp with time zone,
    min_ready_soc_pct numeric,
    exterior_soil_level numeric,
    cabin_condition text,
    last_wash_at timestamp with time zone,
    last_deep_clean_at timestamp with time zone,
    wash_interval_h numeric,
    deep_clean_interval_h numeric,
    calib_interval_h numeric,
    calib_interval_km numeric,
    last_calibration_at timestamp with time zone,
    sensor_health_pct numeric,
    software_version text,
    sw_target_version text,
    sw_update_size_mb integer,
    odometer_km numeric,
    pm_interval_km numeric,
    km_at_last_pm numeric,
    last_pm_at timestamp with time zone,
    open_fault_codes text[],
    worst_fault_severity smallint,
    tire_tread_mm numeric,
    tire_rotation_due_km numeric,
    brake_wear_pct numeric,
    next_deploy_at timestamp with time zone,
    priority_class text,
    assigned_shift text,
    item_retrieval_pending boolean,
    item_reported_at timestamp with time zone,
    item_description text,
    updated_at timestamp with time zone,
    wear_km_applied numeric,
    wear_km_applied_run uuid
);
-- @@ table public.proof0008_soil_smoke
CREATE TABLE public.proof0008_soil_smoke (
    phase text,
    vehicle_id uuid,
    exterior_soil_level numeric,
    n_faults integer,
    open_fault_codes text[],
    worst_fault_severity integer,
    last_pm_at timestamp with time zone,
    last_wash_at timestamp with time zone,
    wear_soil_index numeric,
    captured_at timestamp with time zone
);
-- @@ table public.proof0008_wear_prestate
CREATE TABLE public.proof0008_wear_prestate (
    vehicle_id uuid,
    sim_run_id uuid,
    drive_km_total numeric,
    drive_hours_total numeric,
    backfilled_km numeric,
    backfilled_hours numeric,
    km_at_last_pm numeric,
    hours_at_last_calibration numeric,
    calibrated_at timestamp with time zone,
    soil_index numeric,
    cabin_litter_events integer,
    open_dtc_count integer,
    worst_open_dtc_rank smallint,
    last_advanced_tick bigint,
    last_advanced_sim_clock timestamp with time zone,
    km_per_tick_ema numeric,
    drive_ticks_observed integer,
    updated_at timestamp with time zone
);
-- @@ table public.proof0009_credit
CREATE TABLE public.proof0009_credit (
    label text,
    display_name text,
    vehicle_id uuid,
    work_order jsonb,
    old_code_would_have_credited jsonb,
    credited_now jsonb,
    false_credits_prevented integer,
    pm_before timestamp with time zone,
    pm_after timestamp with time zone,
    pm_moved boolean,
    cal_before timestamp with time zone,
    cal_after timestamp with time zone,
    calibration_moved boolean,
    faults_before integer,
    faults_after integer,
    sev_before smallint,
    sev_after smallint,
    soil_before numeric,
    soil_after numeric,
    soil_moved boolean
);
-- @@ table public.proof0009_eta
CREATE TABLE public.proof0009_eta (
    dispatch_id uuid,
    status_before text,
    status_after text,
    plan_before timestamp with time zone,
    plan_after timestamp with time zone,
    plan_survived boolean,
    plan_still_equals_dispatch_plan boolean,
    live_eta_before timestamp with time zone,
    live_eta_after timestamp with time zone,
    live_eta_moved boolean,
    returning_started_at timestamp with time zone,
    return_eta_minutes numeric,
    eta_refreshed_at timestamp with time zone,
    eta_source text,
    plan_minus_live_min_computed numeric,
    ev_plan text,
    ev_live text,
    ev_plan_minus_live_min text,
    ev_eta_source text,
    v6_sqlstate text,
    v6_message text
);
-- @@ table public.proof0012_428c9
CREATE TABLE public.proof0012_428c9 (
    checked_at timestamp with time zone,
    result text
);
-- @@ table public.proof0012_binding_blocker
CREATE TABLE public.proof0012_binding_blocker (
    booking_id uuid,
    sim_run_id uuid,
    state text,
    source text,
    purpose text,
    released_at timestamp with time zone,
    release_reason text,
    win_start timestamp with time zone,
    win_end timestamp with time zone,
    reserved_stall text,
    reserved_type text,
    vehicle_actual_stall text,
    actual_type text,
    vehicle_state text,
    finding text
);
-- @@ table public.proof0012_cron_before
CREATE TABLE public.proof0012_cron_before (
    phase text,
    jobid bigint,
    runid bigint,
    status text,
    return_message text,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    secs numeric
);
-- @@ table public.proof0012_fk
CREATE TABLE public.proof0012_fk (
    conname text,
    child text,
    parent text,
    orphans bigint
);
-- @@ table public.proof0012_fk_all
CREATE TABLE public.proof0012_fk_all (
    conname text,
    child text,
    parent text,
    orphans bigint
);
-- @@ table public.proof0012_prearrival_census
CREATE TABLE public.proof0012_prearrival_census (
    sim_run_id uuid,
    state text,
    n bigint
);
-- @@ table public.proof0012_ticks_before
CREATE TABLE public.proof0012_ticks_before (
    phase text,
    tick_seq integer,
    tick_compute_ms numeric,
    sim_advance_s numeric,
    real_started_at timestamp with time zone,
    real_ended_at timestamp with time zone
);
-- @@ table public.proof0012_window
CREATE TABLE public.proof0012_window (
    after_window_start timestamp with time zone,
    after_run uuid,
    before_run uuid,
    note text
);
-- @@ table public.retail_members
CREATE TABLE public.retail_members (
    id uuid NOT NULL,
    auth_user_id uuid,
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text NOT NULL,
    phone text,
    membership_tier text NOT NULL,
    membership_status text NOT NULL,
    home_depot_id uuid,
    auto_queue_enabled boolean NOT NULL,
    preferred_days jsonb,
    preferred_time_window jsonb,
    notification_preferences jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.rule_overrides_backup_20260805
CREATE TABLE public.rule_overrides_backup_20260805 (
    override_id uuid,
    rule_code text,
    rule_version integer,
    entity_type text,
    entity_id uuid,
    override_actor_type text,
    override_actor_id text,
    approved_by text,
    justification text,
    effective_from timestamp with time zone,
    effective_until timestamp with time zone,
    triggered_evaluation_id uuid,
    linked_event_id uuid,
    created_at timestamp with time zone,
    fleet_operator_id uuid,
    depot_id uuid,
    payload jsonb
);
-- @@ table public.schedule_modifications
CREATE TABLE public.schedule_modifications (
    id uuid NOT NULL,
    vehicle_schedule_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    modification_type public.modification_type NOT NULL,
    requested_by public.trigger_source NOT NULL,
    requested_by_user_id uuid,
    previous_values jsonb NOT NULL,
    new_values jsonb NOT NULL,
    deadline_at timestamp with time zone,
    deadline_passed boolean NOT NULL,
    override_required boolean NOT NULL,
    override_fee numeric(10,2),
    override_approved boolean,
    override_approved_by uuid,
    vehicles_affected integer,
    stalls_reassigned integer,
    wave_changes integer,
    demand_impact_kw numeric(8,2),
    reason text,
    status text NOT NULL,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.schedule_tasks
CREATE TABLE public.schedule_tasks (
    id uuid NOT NULL,
    vehicle_schedule_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    service_definition_id uuid NOT NULL,
    sequence_order integer NOT NULL,
    assigned_stall_id uuid,
    actual_stall_id uuid,
    scheduled_start timestamp with time zone NOT NULL,
    scheduled_end timestamp with time zone NOT NULL,
    actual_start timestamp with time zone,
    actual_end timestamp with time zone,
    post_completion_buffer_seconds integer NOT NULL,
    status public.task_status NOT NULL,
    confirmed_by_user_id uuid,
    confirmed_by_role public.staff_role,
    confirmation_timestamp timestamp with time zone,
    target_soc integer,
    soc_at_start integer,
    soc_at_end integer,
    energy_delivered_kwh numeric(8,3),
    peak_charge_rate_kw numeric(6,2),
    demand_paused boolean,
    notes text,
    exception_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    oem_acceptance_state text NOT NULL,
    oem_acceptance_requested_at timestamp with time zone,
    oem_acceptance_expires_at timestamp with time zone,
    oem_accepted_at timestamp with time zone,
    oem_accepted_by text,
    oem_rejection_reason text,
    tech_override_action text,
    tech_override_next_stall_id uuid,
    tech_override_reason text,
    tech_override_audit_note text,
    tech_override_by_user_id uuid,
    tech_override_at timestamp with time zone,
    abnormality_flagged boolean NOT NULL,
    abnormality_flagged_at timestamp with time zone,
    abnormality_flagged_by_role text,
    abnormality_flagged_by_id text,
    abnormality_resolved_at timestamp with time zone,
    abnormality_resolved_by_role text,
    abnormality_resolution_note text,
    scheduled_release_at timestamp with time zone,
    scheduled_release_fired_at timestamp with time zone,
    is_overnight_stage boolean NOT NULL,
    original_sequence_order integer,
    reordered_at timestamp with time zone,
    service_code text,
    schedule_id uuid
);
-- @@ table public.service_cadence_policy
CREATE TABLE public.service_cadence_policy (
    svc text NOT NULL,
    display_name text,
    category text,
    lane text,
    est_min_default numeric,
    interval_h numeric,
    interval_km numeric,
    cadence_kind text,
    due_soon_ratio numeric,
    due_ratio numeric,
    overdue_ratio numeric,
    critical_ratio numeric,
    must_do_at text NOT NULL,
    lane_stalls integer,
    observed_clear_pct numeric,
    sequence_order integer,
    notes text,
    is_active boolean NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.service_definitions
CREATE TABLE public.service_definitions (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    name text NOT NULL,
    code text NOT NULL,
    description text,
    stall_type_required public.stall_type NOT NULL,
    estimated_duration_minutes integer NOT NULL,
    min_duration_minutes integer,
    max_duration_minutes integer,
    is_duration_variable boolean NOT NULL,
    available_for jsonb NOT NULL,
    default_sequence_order integer,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.site_energy_snapshots
CREATE TABLE public.site_energy_snapshots (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    grid_import_kw numeric(10,2) NOT NULL,
    grid_export_kw numeric(10,2) NOT NULL,
    solar_generation_kw numeric(10,2),
    bess_output_kw numeric(10,2),
    total_ev_charging_kw numeric(10,2) NOT NULL,
    building_load_kw numeric(10,2),
    lighting_load_kw numeric(10,2),
    peak_demand_kw_15min numeric(10,2) NOT NULL,
    billing_period_peak_kw numeric(10,2),
    current_tariff_label public.tariff_label,
    current_rate_per_kwh numeric(8,4),
    created_at timestamp with time zone NOT NULL,
    sim_run_id uuid,
    data_source text,
    lmp_usd_mwh numeric,
    carbon_gco2_kwh numeric
);
-- @@ table public.smoke0005_profile_prestate
CREATE TABLE public.smoke0005_profile_prestate (
    vehicle_id uuid,
    exterior_soil_level numeric,
    cabin_condition text,
    odometer_km numeric,
    wear_km_applied numeric,
    wear_km_applied_run uuid,
    updated_at timestamp with time zone,
    captured_at timestamp with time zone
);
-- @@ table public.smoke0005_visit_needs_prestate
CREATE TABLE public.smoke0005_visit_needs_prestate (
    visit_id uuid,
    status text,
    atoms jsonb,
    captured_at timestamp with time zone
);
-- @@ table public.smoke890_bookings_2026_08_03
CREATE TABLE public.smoke890_bookings_2026_08_03 (
    booking_id uuid,
    sim_run_id uuid,
    stall_id uuid,
    vehicle_id uuid,
    visit_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    booked_at timestamp with time zone,
    booked_by text,
    released_at timestamp with time zone,
    release_reason text,
    source text,
    decision_id uuid,
    need_code text,
    need_atom text,
    need_source text,
    leg_source text,
    why text,
    decision_link text
);
-- @@ table public.space_conflict_ledger
CREATE TABLE public.space_conflict_ledger (
    conflict_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.space_conflict_ledger_conflict_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    recorded_at timestamp with time zone NOT NULL,
    sim_run_id uuid NOT NULL,
    depot_id uuid,
    sim_clock timestamp with time zone,
    tick_seq bigint,
    stall_id uuid NOT NULL,
    stall_type text,
    conflict_kind text NOT NULL,
    resolution text NOT NULL,
    present_vehicle_id uuid NOT NULL,
    present_vehicle_state text,
    displaced_vehicle_id uuid,
    displaced_booking_id uuid,
    displaced_state text,
    displaced_during tstzrange,
    displaced_leg_id uuid,
    displaced_booked_by text,
    new_booking_id uuid,
    decision_id uuid,
    detail jsonb
);
-- @@ table public.staff_users
CREATE TABLE public.staff_users (
    id uuid NOT NULL,
    auth_user_id uuid,
    depot_id uuid NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text NOT NULL,
    phone text,
    role public.staff_role NOT NULL,
    display_name text,
    is_on_shift boolean NOT NULL,
    current_zone text,
    shift_start timestamp with time zone,
    shift_end timestamp with time zone,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.stalls
CREATE TABLE public.stalls (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    stall_code text NOT NULL,
    stall_type public.stall_type NOT NULL,
    display_name text,
    relative_x double precision,
    relative_y double precision,
    heading_degrees smallint,
    absolute_lat double precision,
    absolute_lng double precision,
    absolute_point public.geography(Point,4326),
    distance_from_entrance integer,
    status text NOT NULL,
    current_vehicle_id uuid,
    equipment_config jsonb,
    fiducial_marker_id text,
    uwb_beacon_id text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    zone text,
    reserved_for_mission_id uuid,
    connector_type text,
    connector_max_kw numeric,
    supported_inlet_types text[],
    ocpp_charger_id uuid,
    stall_kind text,
    canopy_code text,
    covered boolean NOT NULL,
    stall_width_ft numeric,
    stall_depth_ft numeric,
    reserved_by uuid,
    reserved_at timestamp with time zone,
    reservation_expires_at timestamp with time zone,
    staging_role text
);
-- @@ table public.storage_cert_0006_retention
CREATE TABLE public.storage_cert_0006_retention (
    id bigint NOT NULL,
    note text,
    captured_at timestamp with time zone,
    payload jsonb
);
-- @@ table public.storage_cert_0006_samples
CREATE TABLE public.storage_cert_0006_samples (
    id bigint NOT NULL,
    label text,
    sampled_at timestamp with time zone,
    db_bytes bigint,
    events_rows bigint,
    events_bytes bigint,
    per_table jsonb
);
-- @@ table public.tariff_schedules
CREATE TABLE public.tariff_schedules (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    name text NOT NULL,
    utility_provider text NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    billing_cycle_day integer NOT NULL,
    periods jsonb NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.tuning_iterations
CREATE TABLE public.tuning_iterations (
    id uuid NOT NULL,
    tuning_run_id uuid NOT NULL,
    iteration_number integer NOT NULL,
    parameters jsonb NOT NULL,
    objective_value numeric(12,6) NOT NULL,
    is_best_so_far boolean NOT NULL,
    simplex_move_type text,
    simplex_size numeric(10,6),
    samples_evaluated integer NOT NULL,
    regularization_penalty numeric(10,6),
    evaluation_details jsonb,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.vehicle_need_profile
CREATE TABLE public.vehicle_need_profile (
    vehicle_id uuid NOT NULL,
    profile_version text NOT NULL,
    drawn_for_run uuid,
    drawn_seed bigint,
    drawn_at timestamp with time zone NOT NULL,
    drawn_at_sim_clock timestamp with time zone,
    battery_soh_pct numeric,
    battery_chemistry text,
    charge_accept_kw numeric,
    pack_temp_c numeric,
    dcfc_safe boolean NOT NULL,
    dcfc_block_reason text,
    cell_balance_due_at timestamp with time zone,
    min_ready_soc_pct numeric,
    exterior_soil_level numeric,
    cabin_condition text,
    last_wash_at timestamp with time zone,
    last_deep_clean_at timestamp with time zone,
    wash_interval_h numeric,
    deep_clean_interval_h numeric,
    calib_interval_h numeric,
    calib_interval_km numeric,
    last_calibration_at timestamp with time zone,
    sensor_health_pct numeric,
    software_version text,
    sw_target_version text,
    sw_update_size_mb integer,
    odometer_km numeric,
    pm_interval_km numeric,
    km_at_last_pm numeric,
    last_pm_at timestamp with time zone,
    open_fault_codes text[] NOT NULL,
    worst_fault_severity smallint NOT NULL,
    tire_tread_mm numeric,
    tire_rotation_due_km numeric,
    brake_wear_pct numeric,
    next_deploy_at timestamp with time zone,
    priority_class text,
    assigned_shift text,
    item_retrieval_pending boolean NOT NULL,
    item_reported_at timestamp with time zone,
    item_description text,
    updated_at timestamp with time zone NOT NULL,
    wear_km_applied numeric,
    wear_km_applied_run uuid,
    rider_flag_pending boolean NOT NULL,
    rider_flag_kind text,
    rider_flag_due_at timestamp with time zone
);
-- @@ table public.vehicle_schedules
CREATE TABLE public.vehicle_schedules (
    id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    wave_id uuid,
    scheduled_date date NOT NULL,
    arrival_time timestamp with time zone NOT NULL,
    departure_time timestamp with time zone,
    priority public.priority_tier NOT NULL,
    is_priority_override boolean NOT NULL,
    override_fee numeric(10,2),
    override_reason text,
    status public.schedule_status NOT NULL,
    actual_arrival timestamp with time zone,
    actual_departure timestamp with time zone,
    planned_services jsonb NOT NULL,
    original_arrival_time timestamp with time zone,
    modification_count integer NOT NULL,
    last_modified_by public.trigger_source,
    modification_deadline timestamp with time zone,
    booking_reference text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.vehicle_state_log
CREATE TABLE public.vehicle_state_log (
    id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid,
    previous_state public.vehicle_state,
    new_state public.vehicle_state NOT NULL,
    triggered_by public.trigger_source NOT NULL,
    trigger_user_id uuid,
    stall_id uuid,
    schedule_task_id uuid,
    vehicle_schedule_id uuid,
    metadata jsonb,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.vehicle_telemetry
CREATE TABLE public.vehicle_telemetry (
    id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid,
    "timestamp" timestamp with time zone NOT NULL,
    soc_percent integer,
    odometer_miles integer,
    tire_pressure jsonb,
    battery_temp_f numeric(5,1),
    ambient_temp_f numeric(5,1),
    location_lat double precision,
    location_lng double precision,
    is_occupied boolean,
    speed_mph numeric(5,1),
    source text,
    created_at timestamp with time zone NOT NULL
);
-- @@ table public.vehicles
CREATE TABLE public.vehicles (
    id uuid NOT NULL,
    fleet_operator_id uuid,
    retail_member_id uuid,
    home_depot_id uuid NOT NULL,
    category public.vehicle_category NOT NULL,
    vin text,
    make text,
    model text,
    year smallint,
    license_plate text,
    color text,
    display_name text,
    battery_capacity_kwh numeric(6,2),
    max_charge_rate_kw numeric(6,2),
    connector_type text,
    target_soc integer NOT NULL,
    current_soc integer,
    min_soc_threshold integer,
    platform public.av_platform NOT NULL,
    av_api_vehicle_id text,
    av_dispatch_capable boolean NOT NULL,
    current_state public.vehicle_state NOT NULL,
    current_stall_id uuid,
    current_depot_id uuid,
    last_state_change timestamp with time zone,
    default_service_sequence jsonb,
    config jsonb NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    inlet_type text,
    inlet_max_kw numeric,
    current_soc_updated_at timestamp with time zone,
    current_soc_source text,
    owning_sim_run_id uuid,
    robotic_tether_until timestamp with time zone,
    robotic_tether_stall_id uuid,
    robotic_tether_direction text,
    robotic_tether_phase text,
    vehicle_class_code text
);
-- @@ table public.verify0006_bench
CREATE TABLE public.verify0006_bench (
    what text,
    iters integer,
    total_ms numeric,
    us_per_op numeric
);
-- @@ table public.verify0006_drift
CREATE TABLE public.verify0006_drift (
    ord integer,
    severity text,
    check_name text,
    detail text
);
-- @@ table public.verify0006_protect
CREATE TABLE public.verify0006_protect (
    phase text,
    asset text,
    n bigint
);
-- @@ table public.verify0006_readcost
CREATE TABLE public.verify0006_readcost (
    what text,
    n integer,
    ms numeric,
    ms_per_row numeric
);
-- @@ table public.verify0006_retention
CREATE TABLE public.verify0006_retention (
    step text,
    result text,
    detail text,
    at timestamp with time zone
);
-- @@ table public.waves
CREATE TABLE public.waves (
    id uuid NOT NULL,
    depot_id uuid NOT NULL,
    wave_code text NOT NULL,
    scheduled_date date NOT NULL,
    arrival_window_start timestamp with time zone NOT NULL,
    arrival_window_end timestamp with time zone NOT NULL,
    departure_window_start timestamp with time zone,
    departure_window_end timestamp with time zone,
    vehicle_count integer NOT NULL,
    status text NOT NULL,
    notes text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
-- @@ table public.workload_determinism_proof_2026_08_02
CREATE TABLE public.workload_determinism_proof_2026_08_02 (
    id bigint NOT NULL,
    leg text NOT NULL,
    run_id uuid NOT NULL,
    seed bigint,
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text,
    captured_at timestamp with time zone NOT NULL,
    captured_after_stop boolean NOT NULL
);
-- @@ table twin.arm_cycles
CREATE TABLE twin.arm_cycles (
    cycle_id uuid NOT NULL,
    sim_run_id uuid,
    depot_id uuid,
    stall_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    session_id uuid,
    direction text NOT NULL,
    phase text NOT NULL,
    phase_started_at timestamp with time zone NOT NULL,
    phase_deadline timestamp with time zone NOT NULL,
    started_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    outcome text,
    retry_count integer NOT NULL,
    meta jsonb NOT NULL
);
-- @@ table twin.arm_registrations
CREATE TABLE twin.arm_registrations (
    registration_id uuid NOT NULL,
    cycle_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    stall_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    attempt integer NOT NULL,
    at timestamp with time zone NOT NULL,
    true_lateral_mm numeric NOT NULL,
    true_vertical_mm numeric NOT NULL,
    true_yaw_deg numeric NOT NULL,
    believed_lateral_mm numeric NOT NULL,
    believed_vertical_mm numeric NOT NULL,
    believed_yaw_deg numeric NOT NULL,
    error_lateral_mm numeric NOT NULL,
    error_vertical_mm numeric NOT NULL,
    error_yaw_deg numeric NOT NULL,
    error_radial_mm numeric NOT NULL,
    tol_lateral_mm numeric NOT NULL,
    tol_vertical_mm numeric NOT NULL,
    tol_yaw_deg numeric NOT NULL,
    fiducial_marker_id text,
    uwb_beacon_id text,
    fiducial_seen boolean NOT NULL,
    fix_source text NOT NULL,
    within_envelope boolean NOT NULL,
    within_reach boolean NOT NULL,
    verdict text NOT NULL
);
-- @@ table twin.ottoq_twin_drive_log
CREATE TABLE twin.ottoq_twin_drive_log (
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    sim_clock_at timestamp with time zone NOT NULL,
    speed_kmh numeric NOT NULL,
    dtc_code text,
    delivered boolean NOT NULL
);
-- @@ table twin.ottoq_twin_operator_log
CREATE TABLE twin.ottoq_twin_operator_log (
    log_id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME twin.ottoq_twin_operator_log_log_id_seq INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE) NOT NULL,
    sim_run_id uuid NOT NULL,
    command_id uuid NOT NULL,
    source_name text,
    vehicle_ref text,
    outcome text,
    reason_code text,
    refusal_reason text,
    walked_at timestamp with time zone,
    walks integer NOT NULL,
    read_at timestamp with time zone,
    ack jsonb,
    door jsonb
);
-- @@ table twin.ottoq_twin_operator_sequences
CREATE TABLE twin.ottoq_twin_operator_sequences (
    sim_run_id uuid NOT NULL,
    source_name text NOT NULL,
    vehicle_ref text NOT NULL,
    last_seq bigint NOT NULL
);
-- @@ table twin.ottoq_twin_operator_state
CREATE TABLE twin.ottoq_twin_operator_state (
    sim_run_id uuid NOT NULL,
    source_name text NOT NULL,
    directive_cursor bigint NOT NULL,
    pending jsonb NOT NULL,
    steps integer NOT NULL,
    last_step_clock timestamp with time zone
);
-- @@ table twin.ottoq_twin_operators
CREATE TABLE twin.ottoq_twin_operators (
    source_name text NOT NULL,
    depot_id uuid NOT NULL,
    key_id uuid NOT NULL,
    note text,
    created_at timestamp with time zone NOT NULL
);
