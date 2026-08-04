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
-- TABLE + VIEW SCHEMA (schema: public)
-- ----------------------------------------------------------------------------
-- Reconstructed from live catalogs (pg_attribute/pg_attrdef/pg_constraint/
-- pg_index/pg_get_viewdef). Columns show type, NOT NULL and DEFAULT; PK/FK/
-- UNIQUE/CHECK are emitted as ALTER TABLE ADD CONSTRAINT (pg_get_constraintdef);
-- secondary indexes via pg_get_indexdef. Read-only snapshot. Row counts are
-- live-tuple estimates (pg_stat_user_tables.n_live_tup) at export time.
-- Base tables: 283   |   Views: 45
-- ----------------------------------------------------------------------------
-- Re-exported 2026-08-03 (previous snapshot: 2026-07-13).
--   Base tables  149 -> 283      Views        40 -> 45
--   Primary keys 149 -> 184      Foreign keys 220 -> 225
--   UNIQUE constraints 73  |  CHECK constraints 207
--   Indexes: 642 total, of which 382 are secondary (non-constraint-backed).
-- Schemas `ottoq` and `twin` contain NO tables, views or indexes -- they hold
-- FUNCTIONS ONLY (see functions_ottoq.sql / functions_twin.sql). Verified: 0
-- relations of kind r/p/v/m in either schema. This file therefore remains
-- public-only, exactly as the 2026-07-13 snapshot was.
-- NOTE: a large share of the +134 new base tables are dated scratch/evidence
-- tables written by the Aug 1-3 certification runs (band_*, build2_*, build3_*,
-- phase7_*/phase9_*/phase10_*/phase11_*, p0_*/p2_*/p3_*/p7_*, *_proof_*,
-- *_smoke_*). They are real objects in the live DB and are exported verbatim,
-- but they are working artefacts, not product schema.
-- ============================================================================

-- TABLE INVENTORY (name : approx live rows)
--   ab_tests                                    0
--   accuracy_alerts                             0
--   accuracy_slos                               0
--   action_guardrails                           0
--   ai_decision_log                             0
--   api_integrations                            0
--   autonomous_action_log                       0
--   availability_fix_proof_2026_08_03           26
--   band_ab_compare_2026_08_01                  37
--   band_calendar_proof_2026_08_01              41
--   band_live_proof_run424242                   13
--   band_live_samples_2026_08_01                131
--   band_live_samples_run424242                 12,960
--   band_verify_samples_2026_08_01              237
--   bay_reservation_reconcile_2026_08_02        276
--   bess_snapshots                              31,008
--   booking_ledger_proof_2026_08_01             301
--   booking_ledger_proof_bk_2026_08_01          1,108
--   build1_smoke_result                         9
--   build2_bookings_raw_2026_08_02              302
--   build2_cert_424242                          31
--   build2_interrupted_recount_2026_08_02       24
--   build2_needscard_before_2026_08_02          10
--   build2_visit_needs_raw_2026_08_02           116
--   build3_pre_bookings_2026_08_02              302
--   build3_pre_legs_2026_08_02                  626
--   build3_smoke_bookings_2026_08_02            190
--   build3_smoke_legs_2026_08_02                356
--   busy_day_tick_probe_2026_08_01              11
--   charger_cooldowns                           0
--   charger_health_scores                       0
--   cuopt_enactment_proof_2026_08_01            74
--   cuopt_invocation_log                        5,729
--   cuopt_supply_before_2026_08_02              427
--   cuopt_supply_ledger_2026_08_03              3,022
--   cuopt_supply_proof_2026_08_02               1,514
--   data_quality_errors                         0
--   decision_fusion_log                         0
--   demand_management_log                       0
--   demand_shaping_plans                        0
--   depot_state_snapshots                       40
--   depot_visit_reports                         0
--   depots                                      1
--   dispatch_commands                           0
--   downstream_action_contracts                 0
--   early_recall_log                            0
--   emergency_queue_insertions                  0
--   emission_fix_smoke_2026_08_03               8
--   engine_config                               0
--   exceptions                                  0
--   external_factor_sources                     0
--   external_factors_log                        0
--   fleet_features_daily                        0
--   fleet_operators                             0
--   integration_health                          0
--   leg_why_smoke_2026_08_02                    10
--   maintenance_log                             0
--   maintenance_schedules                       0
--   model_parameters                            0
--   model_tuning_runs                           0
--   model_versions                              0
--   notifications                               0
--   ocpp_meter_values                           0
--   ocpp_sessions                               61,846
--   ottoq_ab_runs                               0
--   ottoq_anomaly_detectors                     9
--   ottoq_anomaly_observations                  2
--   ottoq_audit_bundles                         1
--   ottoq_audit_reports                         2
--   ottoq_benchmark_frames                      556
--   ottoq_bess_units                            2
--   ottoq_calibration_correlations              1
--   ottoq_calibration_datasets                  9
--   ottoq_calibration_distributions             41
--   ottoq_calibration_metrics                   0
--   ottoq_calibration_profiles                  8
--   ottoq_canopy_state                          4
--   ottoq_cert_queue                            38
--   ottoq_cil_adoptions                         0
--   ottoq_comms_messages                        33,864
--   ottoq_counterfactuals                       0
--   ottoq_cuopt_deferrals                       70
--   ottoq_cuopt_fire_log                        12
--   ottoq_data_drift_metrics                    0
--   ottoq_decision_snapshots                    294
--   ottoq_decisions                             86,999
--   ottoq_deploy_log                            606
--   ottoq_depot_benchmarks_daily                0
--   ottoq_depot_cost_daily                      0
--   ottoq_depot_shifts                          0
--   ottoq_depot_staffing                        6
--   ottoq_depot_tariffs                         6
--   ottoq_dr_calls                              5
--   ottoq_dtc_catalog                           22
--   ottoq_emergency_invocations                 5
--   ottoq_emergency_protocols                   9
--   ottoq_energy_commands                       1,078
--   ottoq_energy_plan                           0
--   ottoq_event_types_catalog                   130
--   ottoq_events                                4,146,387
--   ottoq_external_proposals                    137
--   ottoq_feature_values                        1
--   ottoq_features                              22
--   ottoq_feed_activations                      0
--   ottoq_feed_plans                            6
--   ottoq_fleet_operator_slas                   4
--   ottoq_fn_definition_backups                 25
--   ottoq_grid_events                           5
--   ottoq_grid_snapshots                        5,215
--   ottoq_incident_reports                      284,923
--   ottoq_inference_log                         0
--   ottoq_itinerary_legs                        847
--   ottoq_model_artifacts                       0
--   ottoq_model_routes                          72
--   ottoq_ocpp_chargers                         90
--   ottoq_ocpp_messages                         16,872
--   ottoq_oem_webhook_log                       262
--   ottoq_oem_webhook_patterns                  3
--   ottoq_ops_approvals                         40
--   ottoq_policy_param_catalog                  26
--   ottoq_policy_params                         680
--   ottoq_prediction_accuracy_heatmap           0
--   ottoq_prediction_rule_links                 7
--   ottoq_prediction_types_catalog              8
--   ottoq_predictions                           1
--   ottoq_recommendations                       83,812
--   ottoq_retention_state                       1
--   ottoq_retraining_triggers                   5
--   ottoq_rule_evaluations                      900,769
--   ottoq_rule_overrides                        1
--   ottoq_rule_parameters                       0
--   ottoq_rules                                 52
--   ottoq_run_archives                          39
--   ottoq_scenarios                             7
--   ottoq_schema_snapshots                      6,491
--   ottoq_signing_keys                          1
--   ottoq_sim_runs                              7
--   ottoq_sim_scenarios                         9
--   ottoq_site_structures                       12
--   ottoq_sla_conformance_daily                 1
--   ottoq_sla_violations                        0
--   ottoq_solar_output                          20,620
--   ottoq_specialization_strategies             12
--   ottoq_stall_bookings                        858
--   ottoq_state_transitions                     82
--   ottoq_t4_coverage_samples                   0
--   ottoq_tariff_windows                        12
--   ottoq_telemetry_packets                     44,009
--   ottoq_tick_clock_log                        523
--   ottoq_tick_invariance_arms                  0
--   ottoq_tick_reservations                     212
--   ottoq_training_runs                         0
--   ottoq_variability_cards                     1,871
--   ottoq_variability_catalog                   47
--   ottoq_variability_profiles                  19
--   ottoq_vehicle_classes                       7
--   ottoq_vehicle_commands                      1,183
--   ottoq_vehicle_dispatches                    581
--   ottoq_vehicle_incidents                     0
--   ottoq_vehicle_itineraries                   304
--   ottoq_vehicle_wear                          207
--   ottoq_visit_cost_attribution                0
--   ottoq_visit_needs                           23,618
--   ottoq_wave_plan                             0
--   ottoq_wear_tick_status                      523
--   ottoq_weather_snapshots                     5,214
--   ottow_api_keys                              0
--   ottow_dispatch_rules                        0
--   ottow_drivers                               0
--   ottow_mission_events                        0
--   ottow_missions                              0
--   ottow_notifications                         0
--   p0_booking_test_2026_08_01                  9
--   p0_calendar_diagnosis_2026_08_02            11
--   p0_reopen_baseline_2026_08_03               38
--   p12_contaminated_run904_bookings            1,579
--   p12_contaminated_run904_cuopt               5,413
--   p12_contaminated_run904_needs               23,524
--   p12_contaminated_run904_runrow              1
--   p2_cuopt_first_refusal_smoke_2026_08_02     20
--   p2_eviction_proof_2026_08_03                165
--   p2_guard_unit_2026_08_03                    4
--   p2_unfreeze_proof_2026_08_01                26
--   p3_phantom_smoke_2026_08_02                 7
--   p3_smoke_restore_2026_08_02                 13
--   p7_band_probe_2026_08_03                    1
--   p7_cuopt_supply_proof_2026_08_03            7
--   phantom_provenance_proof_2026_08_02         3
--   phase10_bookings_424242                     761
--   phase10_cap_unit_2026_08_03                 5
--   phase10_cert_424242                         60
--   phase10_cuopt_log_424242                    480
--   phase10_dispatches_424242                   124
--   phase10_eviction_evidence_424242            197
--   phase10_guard_unit_2026_08_03               4
--   phase10_interruption_retro_2026_08_03       1
--   phase10_replan_unit_2026_08_03              8
--   phase10_smoke_evidence_2026_08_03           40
--   phase10_smoke_mark2_2026_08_03              1
--   phase10_smoke_mark_2026_08_03               1
--   phase10_smoke_needs_2026_08_03              13
--   phase10_visit_needs_424242                  133
--   phase11_bookings_424242                     736
--   phase11_cert_424242                         63
--   phase11_cuopt_log_424242                    487
--   phase11_dispatches_424242                   117
--   phase11_eviction_evidence_424242            203
--   phase11_guard_smoke_2026_08_03              6
--   phase11_harness_correction_424242           7
--   phase11_pre_bookings_2026_08_03             761
--   phase11_pre_legs_2026_08_03                 736
--   phase11_pre_needs_2026_08_03                133
--   phase11_proof_2026_08_03                    16
--   phase11_resume_proof_2026_08_03             4
--   phase11_run897_bookings_2026_08_03          719
--   phase11_run897_cuopt_2026_08_03             455
--   phase11_run897_dispatches_2026_08_03        121
--   phase11_run897_harness_2026_08_03           35
--   phase11_run897_needs_2026_08_03             118
--   phase11_run897_runrow_2026_08_03            1
--   phase11_runid_2026_08_03                    1
--   phase11_runrow_424242                       1
--   phase11_smoke_2026_08_03                    6
--   phase11_smoke_bookings_2026_08_03           719
--   phase11_smoke_legs_2026_08_03               660
--   phase11_smoke_needs_2026_08_03              118
--   phase11_visit_needs_424242                  117
--   phase1_busy_proof_424242                    120
--   phase2_busy_proof_424242                    51
--   phase3_bay_commands_2026_08_02              10
--   phase3_bay_proof_2026_08_02                 1,131
--   phase3_cert_424242                          73
--   phase4_cert_424242                          82
--   phase5_cert_424242                          7
--   phase5_cert_d78dd3b1                        468
--   phase6_cert_424242                          28
--   phase6_cert_424242_supply                   3
--   phase6_cert_424242_telemetry                407
--   phase7_bookings_424242                      302
--   phase7_cert_424242                          60
--   phase7_cuopt_log_424242                     443
--   phase7_dispatches_424242                    115
--   phase7_prestop_bookings_424242              302
--   phase7_reconcile_424242                     24
--   phase9_bookings_424242                      720
--   phase9_cert_424242                          59
--   phase9_dispatches_424242                    114
--   phase9_eviction_evidence_424242             125
--   phase9_fix1_pre_2026_08_02                  6
--   phase9_fix2_prefix_bookings_424242          312
--   phase9_fix2_prefix_evidence_424242          62
--   phase9_fix3_post_424242                     558
--   phase9_fix3_post_decisions_424242           1,316
--   phase9_fix3_pre_424242                      341
--   phase9_fix3_pre_decisions_424242            3,433
--   phase9_fix3_pre_legs_424242                 1,918
--   phase9_prior_bookings_2026_08_03            535
--   phase9_prior_runs_2026_08_03                3
--   phase9_visit_needs_424242                   170
--   prediction_accuracy_daily                   0
--   prediction_explanations                     0
--   prediction_outcomes                         0
--   progression_decisions                       1
--   retail_members                              0
--   schedule_modifications                      8
--   schedule_tasks                              113
--   service_cadence_policy                      15
--   service_definitions                         9
--   site_energy_snapshots                       30,963
--   smoke890_bookings_2026_08_03                190
--   space_conflict_ledger                       26
--   spatial_ref_sys                             0
--   staff_users                                 0
--   stalls                                      300
--   tariff_schedules                            0
--   tuning_iterations                           0
--   vehicle_need_profile                        116
--   vehicle_schedules                           54
--   vehicle_state_log                           571,850
--   vehicle_telemetry                           0
--   vehicles                                    220
--   waves                                       0
--   workload_determinism_proof_2026_08_02       60

-- ===== ab_tests =====
CREATE TABLE public.ab_tests (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    parameter_group text NOT NULL,
    test_name text NOT NULL,
    variant_a_version_id uuid NOT NULL,
    variant_b_version_id uuid NOT NULL,
    traffic_split_pct integer NOT NULL DEFAULT 50,
    hypothesis text,
    primary_metric text NOT NULL DEFAULT 'mean_accuracy'::text,
    minimum_sample_size integer NOT NULL DEFAULT 100,
    minimum_detectable_effect numeric(5,4) DEFAULT 0.020,
    significance_level numeric(4,3) NOT NULL DEFAULT 0.050,
    power numeric(4,3) NOT NULL DEFAULT 0.800,
    status text NOT NULL DEFAULT 'draft'::text,
    started_at timestamp with time zone,
    planned_end_at timestamp with time zone,
    ended_at timestamp with time zone,
    variant_a_samples integer DEFAULT 0,
    variant_b_samples integer DEFAULT 0,
    variant_a_metric numeric(10,6),
    variant_b_metric numeric(10,6),
    effect_size numeric(10,6),
    confidence_interval jsonb,
    p_value numeric(10,8),
    winner_version_id uuid,
    conclusion text,
    safety_stop_conditions jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by text DEFAULT 'system'::text,
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ab_tests ADD CONSTRAINT ab_tests_pkey PRIMARY KEY (id);
ALTER TABLE public.ab_tests ADD CONSTRAINT ab_tests_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ab_tests ADD CONSTRAINT ab_tests_variant_a_version_id_fkey FOREIGN KEY (variant_a_version_id) REFERENCES model_versions(id);
ALTER TABLE public.ab_tests ADD CONSTRAINT ab_tests_variant_b_version_id_fkey FOREIGN KEY (variant_b_version_id) REFERENCES model_versions(id);
ALTER TABLE public.ab_tests ADD CONSTRAINT ab_tests_winner_version_id_fkey FOREIGN KEY (winner_version_id) REFERENCES model_versions(id);
ALTER TABLE public.ab_tests ADD CONSTRAINT ab_tests_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'running'::text, 'analyzing'::text, 'concluded'::text, 'cancelled'::text, 'aborted'::text])));
ALTER TABLE public.ab_tests ADD CONSTRAINT ab_tests_traffic_split_pct_check CHECK (((traffic_split_pct >= 0) AND (traffic_split_pct <= 100)));
CREATE INDEX idx_ab_tests_depot_status ON public.ab_tests USING btree (depot_id, status, started_at DESC);
CREATE INDEX idx_ab_tests_running ON public.ab_tests USING btree (parameter_group, depot_id) WHERE (status = 'running'::text);

-- ===== accuracy_alerts =====
CREATE TABLE public.accuracy_alerts (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    slo_id uuid NOT NULL,
    depot_id uuid,
    prediction_type text NOT NULL,
    time_horizon_hours integer,
    severity text NOT NULL,
    observed_at timestamp with time zone NOT NULL DEFAULT now(),
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
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.accuracy_alerts ADD CONSTRAINT accuracy_alerts_pkey PRIMARY KEY (id);
ALTER TABLE public.accuracy_alerts ADD CONSTRAINT accuracy_alerts_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.accuracy_alerts ADD CONSTRAINT accuracy_alerts_slo_id_fkey FOREIGN KEY (slo_id) REFERENCES accuracy_slos(id) ON DELETE CASCADE;
ALTER TABLE public.accuracy_alerts ADD CONSTRAINT accuracy_alerts_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'critical'::text])));
CREATE INDEX idx_alerts_depot_time ON public.accuracy_alerts USING btree (depot_id, observed_at DESC);
CREATE INDEX idx_alerts_slo ON public.accuracy_alerts USING btree (slo_id, observed_at DESC);
CREATE INDEX idx_alerts_unresolved ON public.accuracy_alerts USING btree (severity, observed_at DESC) WHERE (resolved_at IS NULL);

-- ===== accuracy_slos =====
CREATE TABLE public.accuracy_slos (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid,
    prediction_type text NOT NULL,
    time_horizon_hours integer,
    slo_target numeric(4,3) NOT NULL,
    accuracy_threshold numeric(4,3) NOT NULL,
    evaluation_window_hours integer NOT NULL DEFAULT 168,
    min_samples integer NOT NULL DEFAULT 20,
    warning_at numeric(4,3),
    critical_at numeric(4,3),
    alert_cooldown_min integer NOT NULL DEFAULT 60,
    auto_rollback_on_breach boolean NOT NULL DEFAULT false,
    auto_rollback_confidence numeric(4,3) DEFAULT 0.950,
    is_active boolean NOT NULL DEFAULT true,
    owner text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.accuracy_slos ADD CONSTRAINT accuracy_slos_depot_id_prediction_type_time_horizon_hours_key UNIQUE (depot_id, prediction_type, time_horizon_hours);
ALTER TABLE public.accuracy_slos ADD CONSTRAINT accuracy_slos_pkey PRIMARY KEY (id);
ALTER TABLE public.accuracy_slos ADD CONSTRAINT accuracy_slos_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.accuracy_slos ADD CONSTRAINT accuracy_slos_accuracy_threshold_check CHECK (((accuracy_threshold > (0)::numeric) AND (accuracy_threshold <= (1)::numeric)));
ALTER TABLE public.accuracy_slos ADD CONSTRAINT accuracy_slos_slo_target_check CHECK (((slo_target > (0)::numeric) AND (slo_target <= (1)::numeric)));
CREATE INDEX idx_slos_active ON public.accuracy_slos USING btree (depot_id, prediction_type, is_active);

-- ===== action_guardrails =====
CREATE TABLE public.action_guardrails (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    action_type text NOT NULL,
    max_per_hour integer NOT NULL DEFAULT 3,
    max_per_shift integer NOT NULL DEFAULT 10,
    max_per_day integer NOT NULL DEFAULT 20,
    min_confidence numeric(4,3) NOT NULL DEFAULT 0.850,
    auto_execute_confidence numeric(4,3) NOT NULL DEFAULT 0.950,
    cooldown_minutes integer NOT NULL DEFAULT 15,
    blackout_start time without time zone,
    blackout_end time without time zone,
    requires_human_approval boolean NOT NULL DEFAULT false,
    enabled boolean NOT NULL DEFAULT true,
    allow_rollback boolean NOT NULL DEFAULT true,
    max_vehicles_affected integer DEFAULT 5,
    max_demand_impact_kw numeric(10,2),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.action_guardrails ADD CONSTRAINT action_guardrails_depot_id_action_type_key UNIQUE (depot_id, action_type);
ALTER TABLE public.action_guardrails ADD CONSTRAINT action_guardrails_pkey PRIMARY KEY (id);
ALTER TABLE public.action_guardrails ADD CONSTRAINT action_guardrails_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
CREATE INDEX idx_guardrails_depot ON public.action_guardrails USING btree (depot_id, enabled);

-- ===== ai_decision_log =====
CREATE TABLE public.ai_decision_log (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    vehicle_id uuid,
    request_id text NOT NULL,
    context text NOT NULL,
    urgency text NOT NULL,
    question text NOT NULL,
    depot_state jsonb NOT NULL,
    specific_data jsonb NOT NULL,
    constraints jsonb DEFAULT '[]'::jsonb,
    model_used text,
    decisions jsonb,
    reasoning_chain text,
    requires_human_approval boolean,
    auto_apply_eligible boolean,
    status text NOT NULL DEFAULT 'pending'::text,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    applied_at timestamp with time zone,
    token_usage_input integer,
    token_usage_output integer,
    latency_ms integer,
    error_message text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ai_decision_log ADD CONSTRAINT ai_decision_log_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_decision_log ADD CONSTRAINT ai_decision_log_request_id_key UNIQUE (request_id);
ALTER TABLE public.ai_decision_log ADD CONSTRAINT ai_decision_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.ai_decision_log ADD CONSTRAINT ai_decision_log_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
ALTER TABLE public.ai_decision_log ADD CONSTRAINT ai_decision_log_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'auto_applied'::text, 'approved'::text, 'rejected'::text, 'expired'::text, 'error'::text])));
CREATE INDEX idx_ai_log_depot ON public.ai_decision_log USING btree (depot_id, created_at DESC);
CREATE INDEX idx_ai_log_status ON public.ai_decision_log USING btree (status) WHERE (status = 'pending'::text);

-- ===== api_integrations =====
CREATE TABLE public.api_integrations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    fleet_operator_id uuid,
    platform av_platform NOT NULL,
    integration_name text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    api_base_url text NOT NULL,
    auth_type text NOT NULL DEFAULT 'oauth2'::text,
    credentials jsonb NOT NULL DEFAULT '{}'::jsonb,
    endpoint_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    callback_url text,
    callback_secret text,
    rate_limit_requests_per_min integer DEFAULT 60,
    rate_limit_requests_per_day integer DEFAULT 10000,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.api_integrations ADD CONSTRAINT api_integrations_depot_id_platform_integration_name_key UNIQUE (depot_id, platform, integration_name);
ALTER TABLE public.api_integrations ADD CONSTRAINT api_integrations_pkey PRIMARY KEY (id);
ALTER TABLE public.api_integrations ADD CONSTRAINT api_integrations_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.api_integrations ADD CONSTRAINT api_integrations_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id);
ALTER TABLE public.api_integrations ADD CONSTRAINT api_integrations_auth_type_check CHECK ((auth_type = ANY (ARRAY['api_key'::text, 'oauth2'::text, 'mtls'::text, 'custom'::text])));
CREATE INDEX idx_api_integrations_depot ON public.api_integrations USING btree (depot_id) WHERE (is_active = true);
CREATE INDEX idx_api_integrations_platform ON public.api_integrations USING btree (platform) WHERE (is_active = true);

-- ===== autonomous_action_log =====
CREATE TABLE public.autonomous_action_log (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    prediction_id uuid,
    action_type text NOT NULL,
    action_parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    action_summary text,
    pre_state jsonb NOT NULL DEFAULT '{}'::jsonb,
    post_state jsonb,
    confidence numeric(4,3) NOT NULL,
    approval_method text NOT NULL,
    approved_by text,
    risk_factors jsonb DEFAULT '[]'::jsonb,
    estimated_impact text,
    status text NOT NULL DEFAULT 'pending'::text,
    execution_started_at timestamp with time zone,
    execution_completed_at timestamp with time zone,
    execution_duration_ms integer,
    error_message text,
    rollback_data jsonb,
    rollback_performed boolean NOT NULL DEFAULT false,
    rollback_at timestamp with time zone,
    rollback_reason text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    downstream_system text,
    executed_payload jsonb,
    downstream_response jsonb,
    downstream_status_code integer,
    idempotency_key text,
    retry_count integer DEFAULT 0,
    contract_id uuid,
    ab_test_id uuid,
    fusion_log_id uuid
);
ALTER TABLE public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_pkey PRIMARY KEY (id);
ALTER TABLE public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_ab_test_id_fkey FOREIGN KEY (ab_test_id) REFERENCES ab_tests(id) ON DELETE SET NULL;
ALTER TABLE public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES downstream_action_contracts(id) ON DELETE SET NULL;
ALTER TABLE public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_fusion_log_id_fkey FOREIGN KEY (fusion_log_id) REFERENCES decision_fusion_log(id) ON DELETE SET NULL;
ALTER TABLE public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_prediction_id_fkey FOREIGN KEY (prediction_id) REFERENCES ottoq_predictions(id) ON DELETE SET NULL;
ALTER TABLE public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_approval_method_check CHECK ((approval_method = ANY (ARRAY['auto_threshold'::text, 'human_approved'::text, 'claude_reasoning'::text, 'cron_triggered'::text])));
ALTER TABLE public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)));
ALTER TABLE public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'executing'::text, 'completed'::text, 'failed'::text, 'rolled_back'::text, 'skipped'::text])));
CREATE INDEX idx_action_log_depot_time ON public.autonomous_action_log USING btree (depot_id, created_at DESC);
CREATE INDEX idx_action_log_prediction ON public.autonomous_action_log USING btree (prediction_id);
CREATE INDEX idx_action_log_status ON public.autonomous_action_log USING btree (depot_id, status, created_at DESC);
CREATE INDEX idx_action_log_type ON public.autonomous_action_log USING btree (depot_id, action_type, created_at DESC);
CREATE UNIQUE INDEX uq_action_idempotency ON public.autonomous_action_log USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);

-- ===== availability_fix_proof_2026_08_03 =====
CREATE TABLE public.availability_fix_proof_2026_08_03 (
    id bigint NOT NULL DEFAULT nextval('availability_fix_proof_2026_08_03_id_seq'::regclass),
    at timestamp with time zone NOT NULL DEFAULT now(),
    phase text NOT NULL,
    metric text NOT NULL,
    value numeric,
    note text
);
ALTER TABLE public.availability_fix_proof_2026_08_03 ADD CONSTRAINT availability_fix_proof_2026_08_03_pkey PRIMARY KEY (id);

-- ===== band_ab_compare_2026_08_01 =====
CREATE TABLE public.band_ab_compare_2026_08_01 (
    sampled_at timestamp with time zone DEFAULT now(),
    sim_run_id uuid,
    tick_count integer,
    vehicles integer,
    old_hw integer,
    new_hw integer,
    flag integer,
    stalls_occupied integer
);

-- ===== band_calendar_proof_2026_08_01 =====
CREATE TABLE public.band_calendar_proof_2026_08_01 (
    phase text,
    metric text,
    k text,
    v numeric,
    note text,
    captured_at timestamp with time zone DEFAULT now()
);

-- ===== band_live_proof_run424242 =====
CREATE TABLE public.band_live_proof_run424242 (
    metric text,
    k text,
    v numeric,
    note text,
    captured_at timestamp with time zone DEFAULT now()
);

-- ===== band_live_samples_2026_08_01 =====
CREATE TABLE public.band_live_samples_2026_08_01 (
    sampled_at timestamp with time zone DEFAULT now(),
    sim_run_id uuid,
    tick_count integer,
    sim_clock timestamp with time zone,
    zone text,
    zone_reason text,
    n integer,
    free_stalls integer,
    at_gate integer,
    proposals integer
);

-- ===== band_live_samples_run424242 =====
CREATE TABLE public.band_live_samples_run424242 (
    sample_id bigint NOT NULL DEFAULT nextval('band_live_samples_run424242_sample_id_seq'::regclass),
    sampled_at timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
    sim_run_id uuid,
    tick_count integer,
    sim_clock_current timestamp with time zone,
    vehicle_id uuid,
    zone text,
    zone_reason text,
    minutes_out numeric,
    current_state text
);
ALTER TABLE public.band_live_samples_run424242 ADD CONSTRAINT band_live_samples_run424242_pkey PRIMARY KEY (sample_id);

-- ===== band_verify_samples_2026_08_01 =====
CREATE TABLE public.band_verify_samples_2026_08_01 (
    sampled_at timestamp with time zone DEFAULT now(),
    sim_run_id uuid,
    tick_count integer,
    sim_clock timestamp with time zone,
    zone text,
    zone_reason text,
    n integer,
    free_stalls integer,
    at_gate integer
);

-- ===== bay_reservation_reconcile_2026_08_02 =====
CREATE TABLE public.bay_reservation_reconcile_2026_08_02 (
    id bigint NOT NULL DEFAULT nextval('bay_reservation_reconcile_2026_08_02_id_seq'::regclass),
    logged_at timestamp with time zone NOT NULL DEFAULT now(),
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
ALTER TABLE public.bay_reservation_reconcile_2026_08_02 ADD CONSTRAINT bay_reservation_reconcile_2026_08_02_pkey PRIMARY KEY (id);
CREATE INDEX bay_res_recon_booking_idx ON public.bay_reservation_reconcile_2026_08_02 USING btree (booking_id, action);
CREATE INDEX bay_res_recon_run_idx ON public.bay_reservation_reconcile_2026_08_02 USING btree (sim_run_id);

-- ===== bess_snapshots =====
CREATE TABLE public.bess_snapshots (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    system_id text NOT NULL,
    timestamp timestamp with time zone NOT NULL DEFAULT now(),
    soc_percent numeric(5,2) NOT NULL,
    capacity_kwh numeric(10,2) NOT NULL,
    usable_capacity_kwh numeric(10,2) NOT NULL,
    current_output_kw numeric(10,2) NOT NULL,
    max_discharge_kw numeric(10,2) NOT NULL,
    max_charge_kw numeric(10,2) NOT NULL,
    grid_import_kw numeric(10,2) DEFAULT 0,
    grid_export_kw numeric(10,2) DEFAULT 0,
    temperature_c numeric(5,1),
    health_percent numeric(5,2),
    cycle_count integer DEFAULT 0,
    status bess_status NOT NULL DEFAULT 'standby'::bess_status,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.bess_snapshots ADD CONSTRAINT bess_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.bess_snapshots ADD CONSTRAINT bess_snapshots_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
CREATE INDEX idx_bess_depot_time ON public.bess_snapshots USING btree (depot_id, "timestamp" DESC);
CREATE INDEX idx_bess_system ON public.bess_snapshots USING btree (system_id, "timestamp" DESC);

-- ===== booking_ledger_proof_2026_08_01 =====
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

-- ===== booking_ledger_proof_bk_2026_08_01 =====
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

-- ===== build1_smoke_result =====
CREATE TABLE public.build1_smoke_result (
    step text,
    metric text,
    value numeric,
    note text
);

-- ===== build2_bookings_raw_2026_08_02 =====
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

-- ===== build2_cert_424242 =====
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

-- ===== build2_interrupted_recount_2026_08_02 =====
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

-- ===== build2_needscard_before_2026_08_02 =====
CREATE TABLE public.build2_needscard_before_2026_08_02 (
    vehicle_id uuid,
    open_work_min numeric,
    open_must_do_min numeric,
    need_statement jsonb,
    captured_at timestamp with time zone
);

-- ===== build2_visit_needs_raw_2026_08_02 =====
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

-- ===== build3_pre_bookings_2026_08_02 =====
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

-- ===== build3_pre_legs_2026_08_02 =====
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

-- ===== build3_smoke_bookings_2026_08_02 =====
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

-- ===== build3_smoke_legs_2026_08_02 =====
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

-- ===== busy_day_tick_probe_2026_08_01 =====
CREATE TABLE public.busy_day_tick_probe_2026_08_01 (
    probe_id bigint NOT NULL DEFAULT nextval('busy_day_tick_probe_2026_08_01_probe_id_seq'::regclass),
    run_id uuid,
    tick_no integer,
    at_wall timestamp with time zone DEFAULT now(),
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
ALTER TABLE public.busy_day_tick_probe_2026_08_01 ADD CONSTRAINT busy_day_tick_probe_2026_08_01_pkey PRIMARY KEY (probe_id);

-- ===== charger_cooldowns =====
CREATE TABLE public.charger_cooldowns (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    stall_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    charge_point_id text NOT NULL,
    last_session_id uuid,
    last_session_end timestamp with time zone NOT NULL,
    last_session_peak_kw numeric(8,2) NOT NULL,
    last_session_energy_kwh numeric(10,3) NOT NULL,
    connector_temp_c numeric(5,1) NOT NULL,
    ambient_temp_c numeric(5,1),
    cooldown_required boolean NOT NULL DEFAULT false,
    cooldown_minutes_total integer NOT NULL DEFAULT 0,
    cooldown_started_at timestamp with time zone NOT NULL,
    available_at timestamp with time zone NOT NULL,
    reduced_rate_available boolean DEFAULT false,
    reduced_rate_max_kw numeric(8,2),
    resolved boolean NOT NULL DEFAULT false,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.charger_cooldowns ADD CONSTRAINT charger_cooldowns_pkey PRIMARY KEY (id);
ALTER TABLE public.charger_cooldowns ADD CONSTRAINT charger_cooldowns_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.charger_cooldowns ADD CONSTRAINT charger_cooldowns_last_session_id_fkey FOREIGN KEY (last_session_id) REFERENCES ocpp_sessions(id);
ALTER TABLE public.charger_cooldowns ADD CONSTRAINT charger_cooldowns_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES stalls(id) ON DELETE CASCADE;
CREATE INDEX idx_cooldowns_available ON public.charger_cooldowns USING btree (available_at) WHERE (resolved = false);
CREATE INDEX idx_cooldowns_depot ON public.charger_cooldowns USING btree (depot_id) WHERE (resolved = false);
CREATE INDEX idx_cooldowns_stall ON public.charger_cooldowns USING btree (stall_id) WHERE (resolved = false);

-- ===== charger_health_scores =====
CREATE TABLE public.charger_health_scores (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    stall_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    charge_point_id text NOT NULL,
    health_score numeric(5,2) NOT NULL DEFAULT 100,
    uptime_percent_7d numeric(5,2) DEFAULT 100,
    uptime_percent_30d numeric(5,2) DEFAULT 100,
    fault_count_7d integer DEFAULT 0,
    fault_count_30d integer DEFAULT 0,
    avg_session_success_rate numeric(5,4) DEFAULT 1.0,
    avg_power_delivery_efficiency numeric(5,4) DEFAULT 1.0,
    last_fault_at timestamp with time zone,
    last_fault_type text,
    total_sessions integer DEFAULT 0,
    failed_sessions integer DEFAULT 0,
    recommended_maintenance boolean DEFAULT false,
    last_maintenance_at timestamp with time zone,
    factors jsonb DEFAULT '[]'::jsonb,
    calculated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.charger_health_scores ADD CONSTRAINT charger_health_scores_pkey PRIMARY KEY (id);
ALTER TABLE public.charger_health_scores ADD CONSTRAINT charger_health_scores_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.charger_health_scores ADD CONSTRAINT charger_health_scores_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES stalls(id) ON DELETE CASCADE;
CREATE INDEX idx_charger_health_score ON public.charger_health_scores USING btree (health_score);
CREATE UNIQUE INDEX idx_charger_health_stall ON public.charger_health_scores USING btree (stall_id);

-- ===== cuopt_enactment_proof_2026_08_01 =====
CREATE TABLE public.cuopt_enactment_proof_2026_08_01 (
    captured_at timestamp with time zone NOT NULL DEFAULT now(),
    kind text NOT NULL,
    row_data jsonb NOT NULL
);

-- ===== cuopt_invocation_log =====
CREATE TABLE public.cuopt_invocation_log (
    invocation_id bigint NOT NULL DEFAULT nextval('cuopt_invocation_log_invocation_id_seq'::regclass),
    sim_run_id uuid,
    stage text NOT NULL DEFAULT 'edge'::text,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    called_at timestamp with time zone NOT NULL DEFAULT now(),
    candidates_in integer,
    free_stalls_in integer,
    proposals_out integer,
    abstained_reason text,
    latency_ms integer,
    http_status integer,
    source_note text,
    detail jsonb
);
ALTER TABLE public.cuopt_invocation_log ADD CONSTRAINT cuopt_invocation_log_pkey PRIMARY KEY (invocation_id);
ALTER TABLE public.cuopt_invocation_log ADD CONSTRAINT cuopt_invocation_log_stage_check CHECK ((stage = ANY (ARRAY['sql_gate'::text, 'edge'::text])));
CREATE INDEX cuopt_invocation_log_called_at_idx ON public.cuopt_invocation_log USING btree (called_at DESC);
CREATE INDEX cuopt_invocation_log_run_time_idx ON public.cuopt_invocation_log USING btree (sim_run_id, called_at DESC);

-- ===== cuopt_supply_before_2026_08_02 =====
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

-- ===== cuopt_supply_ledger_2026_08_03 =====
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

-- ===== cuopt_supply_proof_2026_08_02 =====
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

-- ===== data_quality_errors =====
CREATE TABLE public.data_quality_errors (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid,
    source_table text NOT NULL,
    source_id uuid,
    source_name text,
    error_type text NOT NULL,
    severity text NOT NULL DEFAULT 'warning'::text,
    field_name text,
    expected text,
    actual text,
    message text NOT NULL,
    payload_sample jsonb,
    predictions_affected integer DEFAULT 0,
    actions_blocked integer DEFAULT 0,
    detected_at timestamp with time zone NOT NULL DEFAULT now(),
    resolved_at timestamp with time zone,
    resolved_by text,
    resolution_notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.data_quality_errors ADD CONSTRAINT data_quality_errors_pkey PRIMARY KEY (id);
ALTER TABLE public.data_quality_errors ADD CONSTRAINT data_quality_errors_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.data_quality_errors ADD CONSTRAINT data_quality_errors_error_type_check CHECK ((error_type = ANY (ARRAY['null_required_field'::text, 'schema_mismatch'::text, 'out_of_range'::text, 'duplicate'::text, 'stale'::text, 'monotonic_violation'::text, 'referential_integrity'::text, 'unit_mismatch'::text, 'physical_implausibility'::text, 'contract_violation'::text, 'other'::text])));
ALTER TABLE public.data_quality_errors ADD CONSTRAINT data_quality_errors_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'error'::text, 'critical'::text])));
CREATE INDEX idx_dq_errors_depot_time ON public.data_quality_errors USING btree (depot_id, detected_at DESC);
CREATE INDEX idx_dq_errors_source ON public.data_quality_errors USING btree (source_table, source_id);
CREATE INDEX idx_dq_errors_type ON public.data_quality_errors USING btree (error_type, detected_at DESC);
CREATE INDEX idx_dq_errors_unresolved ON public.data_quality_errors USING btree (severity, detected_at DESC) WHERE (resolved_at IS NULL);

-- ===== decision_fusion_log =====
CREATE TABLE public.decision_fusion_log (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    trigger_type text NOT NULL,
    trigger_details jsonb NOT NULL DEFAULT '{}'::jsonb,
    signals jsonb NOT NULL DEFAULT '[]'::jsonb,
    fusion_method text NOT NULL DEFAULT 'weighted_sum'::text,
    fusion_parameters jsonb DEFAULT '{}'::jsonb,
    fusion_output jsonb NOT NULL,
    confidence numeric(4,3) NOT NULL,
    categories_addressed text[] DEFAULT '{}'::text[],
    emitted_prediction_id uuid,
    emitted_action_id uuid,
    outcome_link jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_pkey PRIMARY KEY (id);
ALTER TABLE public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_emitted_action_id_fkey FOREIGN KEY (emitted_action_id) REFERENCES autonomous_action_log(id) ON DELETE SET NULL;
ALTER TABLE public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_emitted_prediction_id_fkey FOREIGN KEY (emitted_prediction_id) REFERENCES ottoq_predictions(id) ON DELETE SET NULL;
ALTER TABLE public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_fusion_method_check CHECK ((fusion_method = ANY (ARRAY['weighted_sum'::text, 'bayesian'::text, 'rule_cascade'::text, 'claude_reasoning'::text, 'ensemble_vote'::text, 'hybrid'::text])));
ALTER TABLE public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_trigger_type_check CHECK ((trigger_type = ANY (ARRAY['scheduled_cycle'::text, 'threshold_breach'::text, 'external_event'::text, 'schedule_change'::text, 'manual_request'::text, 'cascade'::text])));
CREATE INDEX idx_fusion_action ON public.decision_fusion_log USING btree (emitted_action_id);
CREATE INDEX idx_fusion_depot_time ON public.decision_fusion_log USING btree (depot_id, created_at DESC);
CREATE INDEX idx_fusion_prediction ON public.decision_fusion_log USING btree (emitted_prediction_id);
CREATE INDEX idx_fusion_trigger ON public.decision_fusion_log USING btree (trigger_type, created_at DESC);

-- ===== demand_management_log =====
CREATE TABLE public.demand_management_log (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    timestamp timestamp with time zone NOT NULL DEFAULT now(),
    active_dcfc_count integer NOT NULL,
    active_l2_count integer NOT NULL,
    total_draw_kw numeric(10,2) NOT NULL,
    peak_limit_kw numeric(10,2),
    utilization_pct numeric(5,2),
    action text NOT NULL,
    vehicles_affected jsonb DEFAULT '[]'::jsonb,
    details text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.demand_management_log ADD CONSTRAINT demand_management_log_pkey PRIMARY KEY (id);
ALTER TABLE public.demand_management_log ADD CONSTRAINT demand_management_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
CREATE INDEX idx_demand_log_depot_time ON public.demand_management_log USING btree (depot_id, "timestamp" DESC);

-- ===== demand_shaping_plans =====
CREATE TABLE public.demand_shaping_plans (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    generated_at timestamp with time zone NOT NULL DEFAULT now(),
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
    constraints_satisfied boolean NOT NULL DEFAULT true,
    constraint_violations jsonb DEFAULT '[]'::jsonb,
    status text NOT NULL DEFAULT 'generated'::text,
    applied_at timestamp with time zone,
    applied_by trigger_source,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.demand_shaping_plans ADD CONSTRAINT demand_shaping_plans_pkey PRIMARY KEY (id);
ALTER TABLE public.demand_shaping_plans ADD CONSTRAINT demand_shaping_plans_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.demand_shaping_plans ADD CONSTRAINT demand_shaping_plans_status_check CHECK ((status = ANY (ARRAY['generated'::text, 'applied'::text, 'superseded'::text, 'rejected'::text])));
CREATE INDEX idx_demand_plans_depot ON public.demand_shaping_plans USING btree (depot_id, generated_at DESC);

-- ===== depot_state_snapshots =====
CREATE TABLE public.depot_state_snapshots (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    snapshot_at timestamp with time zone NOT NULL DEFAULT now(),
    vehicles_on_site integer NOT NULL DEFAULT 0,
    vehicles_charging integer NOT NULL DEFAULT 0,
    vehicles_in_service integer NOT NULL DEFAULT 0,
    vehicles_staged integer NOT NULL DEFAULT 0,
    vehicles_en_route integer NOT NULL DEFAULT 0,
    stall_utilization jsonb NOT NULL DEFAULT '{}'::jsonb,
    active_exceptions integer NOT NULL DEFAULT 0,
    active_ottow_missions integer NOT NULL DEFAULT 0,
    current_demand_kw numeric(10,2) NOT NULL DEFAULT 0,
    peak_demand_kw_15min numeric(10,2) DEFAULT 0,
    queue_depth integer NOT NULL DEFAULT 0,
    tasks_pending integer NOT NULL DEFAULT 0,
    tasks_in_progress integer NOT NULL DEFAULT 0,
    tasks_completed_today integer NOT NULL DEFAULT 0,
    current_tariff_label text,
    current_rate_per_kwh numeric(8,4),
    solar_generation_kw numeric(10,2) DEFAULT 0,
    bess_output_kw numeric(10,2) DEFAULT 0,
    weather_data jsonb,
    active_wave_codes text[] DEFAULT '{}'::text[],
    next_wave_eta_minutes integer,
    vehicles_expected_next_2h integer DEFAULT 0,
    depot_health_score numeric(4,3),
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.depot_state_snapshots ADD CONSTRAINT depot_state_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.depot_state_snapshots ADD CONSTRAINT depot_state_snapshots_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
CREATE INDEX idx_depot_snapshots_depot_time ON public.depot_state_snapshots USING btree (depot_id, snapshot_at DESC);

-- ===== depot_visit_reports =====
CREATE TABLE public.depot_visit_reports (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id uuid NOT NULL,
    schedule_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    fleet_operator_id uuid,
    visit_started_at timestamp with time zone NOT NULL,
    visit_completed_at timestamp with time zone,
    planned_sequence jsonb NOT NULL,
    actual_sequence jsonb NOT NULL DEFAULT '[]'::jsonb,
    deviation_count integer NOT NULL DEFAULT 0,
    overrides_applied jsonb NOT NULL DEFAULT '[]'::jsonb,
    abnormalities jsonb NOT NULL DEFAULT '[]'::jsonb,
    oem_interactions jsonb NOT NULL DEFAULT '[]'::jsonb,
    exceptions_raised jsonb NOT NULL DEFAULT '[]'::jsonb,
    planned_duration_min numeric(10,2),
    actual_duration_min numeric(10,2),
    variance_minutes numeric(10,2),
    redeployment_status text,
    audit_trail_complete boolean NOT NULL DEFAULT true,
    generated_at timestamp with time zone NOT NULL DEFAULT now(),
    payload jsonb NOT NULL DEFAULT '{}'::jsonb
);
ALTER TABLE public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_pkey PRIMARY KEY (id);
ALTER TABLE public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
ALTER TABLE public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES vehicle_schedules(id) ON DELETE CASCADE;
ALTER TABLE public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
ALTER TABLE public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_redeployment_status_check CHECK (((redeployment_status IS NULL) OR (redeployment_status = ANY (ARRAY['redeployed'::text, 'held'::text, 'sequestered'::text, 'maintenance_required'::text, 'incomplete'::text]))));
CREATE INDEX idx_visit_reports_depot ON public.depot_visit_reports USING btree (depot_id, generated_at DESC);
CREATE INDEX idx_visit_reports_fleet ON public.depot_visit_reports USING btree (fleet_operator_id, generated_at DESC) WHERE (fleet_operator_id IS NOT NULL);
CREATE UNIQUE INDEX idx_visit_reports_schedule_unique ON public.depot_visit_reports USING btree (schedule_id);
CREATE INDEX idx_visit_reports_vehicle ON public.depot_visit_reports USING btree (vehicle_id, generated_at DESC);

-- ===== depots =====
CREATE TABLE public.depots (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    slug text NOT NULL,
    address text,
    city text,
    state text,
    zip text,
    country text DEFAULT 'US'::text,
    origin_lat double precision,
    origin_lng double precision,
    origin_point geography(Point,4326),
    geofence geography(Polygon,4326),
    timezone text NOT NULL DEFAULT 'America/Chicago'::text,
    status text NOT NULL DEFAULT 'active'::text,
    config jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    service_voltage numeric,
    service_max_kw numeric,
    service_max_kva numeric,
    service_provider text,
    service_tariff_code text,
    dcfc_max_concurrent_kw numeric,
    dcfc_safety_margin_pct numeric DEFAULT 10.0,
    demand_charge_threshold_kw numeric,
    demand_response_program text,
    demand_response_active boolean DEFAULT false,
    operating_timezone text DEFAULT 'America/Chicago'::text,
    operational_hours_start time without time zone,
    operational_hours_end time without time zone,
    overnight_staging_threshold_minutes integer DEFAULT 120,
    quiet_hours_start time without time zone,
    quiet_hours_end time without time zone,
    shift_change_buffer_minutes integer DEFAULT 15,
    site_length_ft numeric,
    site_width_ft numeric,
    site_acres numeric,
    site_layout jsonb,
    daily_throughput_target integer,
    feed_mode text NOT NULL DEFAULT 'sim'::text
);
ALTER TABLE public.depots ADD CONSTRAINT depots_pkey PRIMARY KEY (id);
ALTER TABLE public.depots ADD CONSTRAINT depots_slug_key UNIQUE (slug);
ALTER TABLE public.depots ADD CONSTRAINT chk_depot_feed_mode CHECK ((feed_mode = ANY (ARRAY['sim'::text, 'external'::text])));
ALTER TABLE public.depots ADD CONSTRAINT depots_status_check CHECK ((status = ANY (ARRAY['planning'::text, 'construction'::text, 'active'::text, 'maintenance'::text, 'decommissioned'::text])));
CREATE INDEX idx_depots_slug ON public.depots USING btree (slug);
CREATE INDEX idx_depots_status ON public.depots USING btree (status);

-- ===== dispatch_commands =====
CREATE TABLE public.dispatch_commands (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    platform av_platform NOT NULL,
    av_api_vehicle_id text NOT NULL,
    command_type text NOT NULL,
    destination_lat double precision,
    destination_lng double precision,
    destination_stall_id uuid,
    destination_stall_code text,
    idempotency_key text NOT NULL,
    issued_at timestamp with time zone NOT NULL DEFAULT now(),
    issued_by trigger_source NOT NULL,
    issued_by_user_id uuid,
    timeout_seconds integer NOT NULL DEFAULT 300,
    success boolean,
    platform_command_id text,
    estimated_arrival_seconds integer,
    error_code text,
    error_message text,
    platform_response jsonb,
    attempt_number integer NOT NULL DEFAULT 1,
    retry_of_id uuid,
    retry_eligible boolean DEFAULT true,
    completed_at timestamp with time zone,
    vehicle_arrived_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.dispatch_commands ADD CONSTRAINT dispatch_commands_idempotency_key_key UNIQUE (idempotency_key);
ALTER TABLE public.dispatch_commands ADD CONSTRAINT dispatch_commands_pkey PRIMARY KEY (id);
ALTER TABLE public.dispatch_commands ADD CONSTRAINT dispatch_commands_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.dispatch_commands ADD CONSTRAINT dispatch_commands_destination_stall_id_fkey FOREIGN KEY (destination_stall_id) REFERENCES stalls(id);
ALTER TABLE public.dispatch_commands ADD CONSTRAINT dispatch_commands_retry_of_id_fkey FOREIGN KEY (retry_of_id) REFERENCES dispatch_commands(id);
ALTER TABLE public.dispatch_commands ADD CONSTRAINT dispatch_commands_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
CREATE INDEX idx_dispatch_depot ON public.dispatch_commands USING btree (depot_id, issued_at DESC);
CREATE INDEX idx_dispatch_idempotency ON public.dispatch_commands USING btree (idempotency_key);
CREATE INDEX idx_dispatch_vehicle ON public.dispatch_commands USING btree (vehicle_id, issued_at DESC);

-- ===== downstream_action_contracts =====
CREATE TABLE public.downstream_action_contracts (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    action_type text NOT NULL,
    downstream_system text NOT NULL,
    payload_schema jsonb NOT NULL,
    example_payload jsonb,
    transport_method text NOT NULL,
    endpoint_template text,
    auth_requirements jsonb DEFAULT '{}'::jsonb,
    retry_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
    idempotency_key_source text,
    timeout_ms integer NOT NULL DEFAULT 10000,
    supports_rollback boolean NOT NULL DEFAULT false,
    rollback_strategy text,
    rollback_payload_template jsonb,
    is_implemented boolean NOT NULL DEFAULT false,
    implementation_notes text,
    partner_contact text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.downstream_action_contracts ADD CONSTRAINT downstream_action_contracts_action_type_downstream_system_key UNIQUE (action_type, downstream_system);
ALTER TABLE public.downstream_action_contracts ADD CONSTRAINT downstream_action_contracts_pkey PRIMARY KEY (id);
ALTER TABLE public.downstream_action_contracts ADD CONSTRAINT downstream_action_contracts_downstream_system_check CHECK ((downstream_system = ANY (ARRAY['ocpp_charger'::text, 'fleet_dispatch'::text, 'core_scheduler'::text, 'bess_controller'::text, 'solar_inverter'::text, 'hvac_controller'::text, 'ops_notification'::text, 'utility_api'::text, 'field_ops_app'::text, 'none'::text])));
ALTER TABLE public.downstream_action_contracts ADD CONSTRAINT downstream_action_contracts_transport_method_check CHECK ((transport_method = ANY (ARRAY['http_post'::text, 'http_put'::text, 'websocket'::text, 'mqtt'::text, 'grpc'::text, 'ocpp_messaging'::text, 'internal_call'::text])));
CREATE INDEX idx_contracts_action ON public.downstream_action_contracts USING btree (action_type);
CREATE INDEX idx_contracts_implemented ON public.downstream_action_contracts USING btree (is_implemented, action_type);

-- ===== early_recall_log =====
CREATE TABLE public.early_recall_log (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    vehicle_schedule_id uuid,
    assessed_at timestamp with time zone NOT NULL DEFAULT now(),
    current_soc integer NOT NULL,
    predicted_soc_at_arrival integer NOT NULL,
    confidence_low integer NOT NULL,
    confidence_high integer NOT NULL,
    min_soc_threshold integer NOT NULL,
    distance_to_depot_miles numeric(8,2),
    energy_to_depot_kwh numeric(8,2),
    can_reach_depot boolean NOT NULL,
    urgency recall_urgency NOT NULL,
    recommended_action recall_action NOT NULL,
    reason text NOT NULL,
    disruption_impact text NOT NULL DEFAULT 'none'::text,
    affected_wave_id uuid,
    vehicles_displaced integer DEFAULT 0,
    wave_can_absorb boolean,
    action_taken recall_action,
    action_taken_at timestamp with time zone,
    action_taken_by trigger_source,
    override_reason text,
    scheduled_arrival timestamp with time zone NOT NULL,
    recommended_arrival timestamp with time zone,
    actual_arrival timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.early_recall_log ADD CONSTRAINT early_recall_log_pkey PRIMARY KEY (id);
ALTER TABLE public.early_recall_log ADD CONSTRAINT early_recall_log_affected_wave_id_fkey FOREIGN KEY (affected_wave_id) REFERENCES waves(id);
ALTER TABLE public.early_recall_log ADD CONSTRAINT early_recall_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.early_recall_log ADD CONSTRAINT early_recall_log_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
ALTER TABLE public.early_recall_log ADD CONSTRAINT early_recall_log_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES vehicle_schedules(id);
ALTER TABLE public.early_recall_log ADD CONSTRAINT early_recall_log_disruption_impact_check CHECK ((disruption_impact = ANY (ARRAY['none'::text, 'minor'::text, 'moderate'::text, 'major'::text])));
CREATE INDEX idx_recall_depot ON public.early_recall_log USING btree (depot_id, assessed_at DESC);
CREATE INDEX idx_recall_urgency ON public.early_recall_log USING btree (urgency) WHERE (urgency <> 'none'::recall_urgency);
CREATE INDEX idx_recall_vehicle ON public.early_recall_log USING btree (vehicle_id, assessed_at DESC);

-- ===== emergency_queue_insertions =====
CREATE TABLE public.emergency_queue_insertions (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    reason emergency_reason NOT NULL,
    priority_override priority_tier NOT NULL,
    services_needed jsonb NOT NULL DEFAULT '[]'::jsonb,
    estimated_arrival_minutes integer NOT NULL,
    current_soc integer,
    special_instructions text,
    requested_by trigger_source NOT NULL,
    requested_by_user_id uuid,
    oem_approval_required boolean NOT NULL DEFAULT false,
    oem_reference_id text,
    status text NOT NULL DEFAULT 'pending'::text,
    approved_by uuid,
    approved_at timestamp with time zone,
    assigned_wave_id uuid,
    assigned_stall_id uuid,
    assigned_arrival_time timestamp with time zone,
    vehicle_schedule_id uuid,
    disruption_score integer NOT NULL DEFAULT 0,
    vehicles_displaced jsonb DEFAULT '[]'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_pkey PRIMARY KEY (id);
ALTER TABLE public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_assigned_stall_id_fkey FOREIGN KEY (assigned_stall_id) REFERENCES stalls(id);
ALTER TABLE public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_assigned_wave_id_fkey FOREIGN KEY (assigned_wave_id) REFERENCES waves(id);
ALTER TABLE public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
ALTER TABLE public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES vehicle_schedules(id);
ALTER TABLE public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_disruption_score_check CHECK (((disruption_score >= 0) AND (disruption_score <= 100)));
ALTER TABLE public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'completed'::text, 'cancelled'::text])));
CREATE INDEX idx_emergency_depot ON public.emergency_queue_insertions USING btree (depot_id, created_at DESC);
CREATE INDEX idx_emergency_status ON public.emergency_queue_insertions USING btree (status) WHERE (status = 'pending'::text);

-- ===== emission_fix_smoke_2026_08_03 =====
CREATE TABLE public.emission_fix_smoke_2026_08_03 (
    id bigint NOT NULL DEFAULT nextval('emission_fix_smoke_2026_08_03_id_seq'::regclass),
    at timestamp with time zone DEFAULT now(),
    step text,
    note text,
    ok boolean
);
ALTER TABLE public.emission_fix_smoke_2026_08_03 ADD CONSTRAINT emission_fix_smoke_2026_08_03_pkey PRIMARY KEY (id);

-- ===== engine_config =====
CREATE TABLE public.engine_config (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    early_recall_soc_advisory integer NOT NULL DEFAULT 25,
    early_recall_soc_recommended integer NOT NULL DEFAULT 18,
    early_recall_soc_critical integer NOT NULL DEFAULT 12,
    early_recall_check_interval_min integer NOT NULL DEFAULT 5,
    cooldown_temp_threshold_c numeric(5,1) NOT NULL DEFAULT 55.0,
    cooldown_base_minutes integer NOT NULL DEFAULT 5,
    cooldown_per_degree_minutes numeric(4,2) NOT NULL DEFAULT 0.5,
    demand_shaping_enabled boolean NOT NULL DEFAULT true,
    demand_target_pct_of_limit integer NOT NULL DEFAULT 85,
    bess_arbitrage_enabled boolean NOT NULL DEFAULT false,
    ai_enabled boolean NOT NULL DEFAULT false,
    ai_auto_apply_confidence numeric(4,3) NOT NULL DEFAULT 0.90,
    ai_model text NOT NULL DEFAULT 'claude-sonnet-4-20250514'::text,
    ai_max_response_time_ms integer NOT NULL DEFAULT 10000,
    max_emergency_insertions_per_hr integer NOT NULL DEFAULT 5,
    disruption_approval_threshold integer NOT NULL DEFAULT 40,
    modification_deadline_hours integer NOT NULL DEFAULT 24,
    late_modification_fee_base numeric(10,2) NOT NULL DEFAULT 50.00,
    cb_failure_threshold integer NOT NULL DEFAULT 5,
    cb_reset_timeout_ms integer NOT NULL DEFAULT 60000,
    cb_half_open_max_requests integer NOT NULL DEFAULT 3,
    min_move_buffer_seconds integer NOT NULL DEFAULT 30,
    max_simultaneous_moves integer NOT NULL DEFAULT 5,
    emergency_stop_propagation boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.engine_config ADD CONSTRAINT engine_config_pkey PRIMARY KEY (id);
ALTER TABLE public.engine_config ADD CONSTRAINT one_config_per_depot UNIQUE (depot_id);
ALTER TABLE public.engine_config ADD CONSTRAINT engine_config_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;

-- ===== exceptions =====
CREATE TABLE public.exceptions (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    schedule_task_id uuid,
    vehicle_schedule_id uuid,
    stall_id uuid,
    exception_type exception_type NOT NULL,
    severity exception_severity NOT NULL,
    status exception_status NOT NULL DEFAULT 'open'::exception_status,
    title text NOT NULL,
    description text,
    photos jsonb DEFAULT '[]'::jsonb,
    reported_by_user_id uuid,
    reported_by_role staff_role,
    assigned_to_user_id uuid,
    assigned_to_role staff_role,
    resolution_action text,
    resolution_notes text,
    resolved_by_user_id uuid,
    resolved_by_role staff_role,
    stall_closed boolean DEFAULT false,
    stall_reopened_at timestamp with time zone,
    schedule_impact text,
    credit_issued boolean DEFAULT false,
    credit_amount numeric(10,2),
    tow_requested boolean DEFAULT false,
    tow_dispatch_id text,
    tow_eta timestamp with time zone,
    tow_completed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    acknowledged_at timestamp with time zone,
    resolved_at timestamp with time zone,
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    metadata jsonb DEFAULT '{}'::jsonb,
    blocks_progression boolean NOT NULL DEFAULT false,
    resolution_required_before text,
    required_resolver_role text,
    audit_note text,
    data_source text DEFAULT 'twin'::text
);
ALTER TABLE public.exceptions ADD CONSTRAINT exceptions_pkey PRIMARY KEY (id);
ALTER TABLE public.exceptions ADD CONSTRAINT exceptions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.exceptions ADD CONSTRAINT exceptions_schedule_task_id_fkey FOREIGN KEY (schedule_task_id) REFERENCES schedule_tasks(id);
ALTER TABLE public.exceptions ADD CONSTRAINT exceptions_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES stalls(id);
ALTER TABLE public.exceptions ADD CONSTRAINT exceptions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
ALTER TABLE public.exceptions ADD CONSTRAINT exceptions_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES vehicle_schedules(id);
ALTER TABLE public.exceptions ADD CONSTRAINT exceptions_required_resolver_role_check CHECK (((required_resolver_role IS NULL) OR (required_resolver_role = ANY (ARRAY['tech'::text, 'oem'::text, 'either'::text]))));
ALTER TABLE public.exceptions ADD CONSTRAINT exceptions_resolution_required_before_check CHECK (((resolution_required_before IS NULL) OR (resolution_required_before = ANY (ARRAY['next_stall'::text, 'next_service'::text, 'redeployment'::text]))));
CREATE INDEX idx_exceptions_blocking ON public.exceptions USING btree (vehicle_id, status) WHERE ((blocks_progression = true) AND (status = ANY (ARRAY['open'::exception_status, 'acknowledged'::exception_status, 'in_progress'::exception_status, 'escalated'::exception_status])));
CREATE INDEX idx_exceptions_depot ON public.exceptions USING btree (depot_id, created_at DESC);
CREATE INDEX idx_exceptions_severity ON public.exceptions USING btree (severity, status);
CREATE INDEX idx_exceptions_status ON public.exceptions USING btree (status) WHERE (status <> 'resolved'::exception_status);
CREATE INDEX idx_exceptions_vehicle ON public.exceptions USING btree (vehicle_id);

-- ===== external_factor_sources =====
CREATE TABLE public.external_factor_sources (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid,
    factor_type text NOT NULL,
    source_name text NOT NULL,
    provider text,
    source_url text,
    config jsonb NOT NULL DEFAULT '{}'::jsonb,
    poll_interval_sec integer NOT NULL DEFAULT 900,
    poll_mode text NOT NULL DEFAULT 'pull'::text,
    schema_version integer NOT NULL DEFAULT 1,
    required_fields text[] DEFAULT '{}'::text[],
    staleness_tolerance_sec integer NOT NULL DEFAULT 1800,
    last_polled_at timestamp with time zone,
    last_success_at timestamp with time zone,
    last_error_at timestamp with time zone,
    last_error text,
    consecutive_failures integer NOT NULL DEFAULT 0,
    health_status text NOT NULL DEFAULT 'unknown'::text,
    is_active boolean NOT NULL DEFAULT true,
    fallback_strategy text DEFAULT 'last_known'::text,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.external_factor_sources ADD CONSTRAINT external_factor_sources_pkey PRIMARY KEY (id);
ALTER TABLE public.external_factor_sources ADD CONSTRAINT external_factor_sources_source_name_key UNIQUE (source_name);
ALTER TABLE public.external_factor_sources ADD CONSTRAINT external_factor_sources_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.external_factor_sources ADD CONSTRAINT external_factor_sources_factor_type_check CHECK ((factor_type = ANY (ARRAY['weather'::text, 'grid_pricing'::text, 'grid_dr_signal'::text, 'traffic'::text, 'incident_feed'::text, 'air_quality'::text, 'calendar_event'::text, 'solar_forecast'::text, 'carbon_intensity'::text, 'utility_curtailment'::text, 'custom'::text])));
ALTER TABLE public.external_factor_sources ADD CONSTRAINT external_factor_sources_fallback_strategy_check CHECK ((fallback_strategy = ANY (ARRAY['last_known'::text, 'historical_average'::text, 'manual_override'::text, 'fail_closed'::text])));
ALTER TABLE public.external_factor_sources ADD CONSTRAINT external_factor_sources_health_status_check CHECK ((health_status = ANY (ARRAY['healthy'::text, 'degraded'::text, 'stale'::text, 'down'::text, 'unknown'::text])));
ALTER TABLE public.external_factor_sources ADD CONSTRAINT external_factor_sources_poll_mode_check CHECK ((poll_mode = ANY (ARRAY['pull'::text, 'push'::text, 'scheduled_batch'::text])));
CREATE INDEX idx_ext_sources_depot ON public.external_factor_sources USING btree (depot_id, is_active);
CREATE INDEX idx_ext_sources_health ON public.external_factor_sources USING btree (health_status, is_active);
CREATE INDEX idx_ext_sources_type ON public.external_factor_sources USING btree (factor_type, is_active);

-- ===== external_factors_log =====
CREATE TABLE public.external_factors_log (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    source_id uuid NOT NULL,
    depot_id uuid,
    factor_type text NOT NULL,
    observed_at timestamp with time zone NOT NULL,
    ingested_at timestamp with time zone NOT NULL DEFAULT now(),
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone,
    payload jsonb NOT NULL,
    data_hash text,
    quality_score numeric(4,3) DEFAULT 1.000,
    is_interpolated boolean NOT NULL DEFAULT false,
    supersedes_id uuid,
    consumed_by_predictions uuid[],
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.external_factors_log ADD CONSTRAINT external_factors_log_pkey PRIMARY KEY (id);
ALTER TABLE public.external_factors_log ADD CONSTRAINT external_factors_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.external_factors_log ADD CONSTRAINT external_factors_log_source_id_fkey FOREIGN KEY (source_id) REFERENCES external_factor_sources(id) ON DELETE CASCADE;
ALTER TABLE public.external_factors_log ADD CONSTRAINT external_factors_log_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES external_factors_log(id) ON DELETE SET NULL;
CREATE INDEX idx_ext_log_dedup_hash ON public.external_factors_log USING btree (source_id, data_hash) WHERE (data_hash IS NOT NULL);
CREATE INDEX idx_ext_log_depot_type_time ON public.external_factors_log USING btree (depot_id, factor_type, observed_at DESC);
CREATE INDEX idx_ext_log_global_type_time ON public.external_factors_log USING btree (factor_type, observed_at DESC) WHERE (depot_id IS NULL);
CREATE INDEX idx_ext_log_source_time ON public.external_factors_log USING btree (source_id, ingested_at DESC);
CREATE INDEX idx_ext_log_valid_window ON public.external_factors_log USING btree (factor_type, valid_from, valid_to);

-- ===== fleet_features_daily =====
CREATE TABLE public.fleet_features_daily (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    feature_date date NOT NULL,
    feature_group text NOT NULL,
    scope text NOT NULL,
    scope_id text NOT NULL,
    features jsonb NOT NULL DEFAULT '{}'::jsonb,
    sample_count integer NOT NULL DEFAULT 0,
    confidence numeric(4,3) NOT NULL DEFAULT 0.500,
    lookback_days integer NOT NULL DEFAULT 30,
    computed_at timestamp with time zone NOT NULL DEFAULT now(),
    compute_duration_ms integer,
    compute_method text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.fleet_features_daily ADD CONSTRAINT fleet_features_daily_feature_date_feature_group_scope_scope_key UNIQUE (feature_date, feature_group, scope, scope_id);
ALTER TABLE public.fleet_features_daily ADD CONSTRAINT fleet_features_daily_pkey PRIMARY KEY (id);
ALTER TABLE public.fleet_features_daily ADD CONSTRAINT fleet_features_daily_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)));
ALTER TABLE public.fleet_features_daily ADD CONSTRAINT fleet_features_daily_feature_group_check CHECK ((feature_group = ANY (ARRAY['charge_patterns'::text, 'service_patterns'::text, 'demand_patterns'::text, 'arrival_patterns'::text, 'incident_patterns'::text, 'energy_patterns'::text, 'queue_patterns'::text, 'cross_depot_cohort'::text])));
ALTER TABLE public.fleet_features_daily ADD CONSTRAINT fleet_features_daily_scope_check CHECK ((scope = ANY (ARRAY['fleet'::text, 'oem'::text, 'region'::text, 'depot_size_cohort'::text, 'vehicle_model'::text, 'service_type'::text])));
CREATE INDEX idx_fleet_features_lookup ON public.fleet_features_daily USING btree (feature_group, scope, scope_id, feature_date DESC);
CREATE INDEX idx_fleet_features_recent ON public.fleet_features_daily USING btree (feature_date DESC);

-- ===== fleet_operators =====
CREATE TABLE public.fleet_operators (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    company text NOT NULL,
    slug text NOT NULL,
    contact_name text,
    contact_email text,
    contact_phone text,
    contract_tier text NOT NULL DEFAULT 'standard'::text,
    priority priority_tier NOT NULL DEFAULT 'standard'::priority_tier,
    monthly_rate_per_vehicle numeric(10,2),
    default_target_soc integer NOT NULL DEFAULT 90,
    default_service_sequence jsonb NOT NULL DEFAULT '["charging", "cleaning", "staging"]'::jsonb,
    webhook_url text,
    api_key_hash text,
    fleet_api_config jsonb DEFAULT '{}'::jsonb,
    notification_preferences jsonb NOT NULL DEFAULT '{"daily_report": ["email"], "service_start": ["in_app", "webhook"], "vehicle_ready": ["in_app", "webhook"], "weekly_report": ["email"], "monthly_report": ["email"], "exception_raised": ["in_app", "webhook", "sms"], "service_complete": ["in_app", "webhook"]}'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    auth_user_id uuid,
    progression_acceptance_mode text NOT NULL DEFAULT 'oem_webhook_final_only'::text,
    oem_acceptance_timeout_seconds integer NOT NULL DEFAULT 180,
    oem_acceptance_on_timeout text NOT NULL DEFAULT 'auto_accept'::text,
    oem_flag_inbound_secret text
);
ALTER TABLE public.fleet_operators ADD CONSTRAINT fleet_operators_pkey PRIMARY KEY (id);
ALTER TABLE public.fleet_operators ADD CONSTRAINT fleet_operators_slug_key UNIQUE (slug);
ALTER TABLE public.fleet_operators ADD CONSTRAINT fleet_operators_contract_tier_check CHECK ((contract_tier = ANY (ARRAY['standard'::text, 'premium'::text])));
ALTER TABLE public.fleet_operators ADD CONSTRAINT fleet_operators_default_target_soc_check CHECK (((default_target_soc >= 20) AND (default_target_soc <= 100)));
ALTER TABLE public.fleet_operators ADD CONSTRAINT fleet_operators_oem_acceptance_on_timeout_check CHECK ((oem_acceptance_on_timeout = ANY (ARRAY['auto_accept'::text, 'hold'::text, 'escalate'::text])));
ALTER TABLE public.fleet_operators ADD CONSTRAINT fleet_operators_progression_acceptance_mode_check CHECK ((progression_acceptance_mode = ANY (ARRAY['auto'::text, 'oem_webhook_final_only'::text, 'oem_webhook_required'::text, 'tech_confirm_only'::text])));
CREATE INDEX idx_fleet_operators_auth ON public.fleet_operators USING btree (auth_user_id);

-- ===== integration_health =====
CREATE TABLE public.integration_health (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    integration_name text NOT NULL,
    platform av_platform,
    endpoint text NOT NULL,
    circuit_state circuit_breaker_state NOT NULL DEFAULT 'closed'::circuit_breaker_state,
    consecutive_failures integer NOT NULL DEFAULT 0,
    failure_threshold integer NOT NULL DEFAULT 5,
    last_success_at timestamp with time zone,
    last_failure_at timestamp with time zone,
    last_error_message text,
    last_error_code text,
    avg_response_ms integer NOT NULL DEFAULT 0,
    p95_response_ms integer NOT NULL DEFAULT 0,
    p99_response_ms integer NOT NULL DEFAULT 0,
    success_rate_1h numeric(5,2) NOT NULL DEFAULT 100,
    success_rate_24h numeric(5,2) NOT NULL DEFAULT 100,
    total_requests_24h integer NOT NULL DEFAULT 0,
    circuit_opened_at timestamp with time zone,
    circuit_half_open_at timestamp with time zone,
    next_retry_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.integration_health ADD CONSTRAINT integration_health_integration_name_key UNIQUE (integration_name);
ALTER TABLE public.integration_health ADD CONSTRAINT integration_health_pkey PRIMARY KEY (id);
CREATE INDEX idx_integration_health_state ON public.integration_health USING btree (circuit_state) WHERE (circuit_state <> 'closed'::circuit_breaker_state);

-- ===== leg_why_smoke_2026_08_02 =====
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
    captured_at timestamp with time zone DEFAULT now()
);

-- ===== maintenance_log =====
CREATE TABLE public.maintenance_log (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    maintenance_schedule_id uuid,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    category maintenance_category NOT NULL,
    performed_at timestamp with time zone NOT NULL DEFAULT now(),
    performed_by_user_id uuid,
    stall_id uuid,
    duration_minutes integer,
    findings text,
    actions_taken text,
    parts_used jsonb DEFAULT '[]'::jsonb,
    photos jsonb DEFAULT '[]'::jsonb,
    pass_fail text,
    follow_up_required boolean DEFAULT false,
    follow_up_notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.maintenance_log ADD CONSTRAINT maintenance_log_pkey PRIMARY KEY (id);
ALTER TABLE public.maintenance_log ADD CONSTRAINT maintenance_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.maintenance_log ADD CONSTRAINT maintenance_log_maintenance_schedule_id_fkey FOREIGN KEY (maintenance_schedule_id) REFERENCES maintenance_schedules(id);
ALTER TABLE public.maintenance_log ADD CONSTRAINT maintenance_log_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES stalls(id);
ALTER TABLE public.maintenance_log ADD CONSTRAINT maintenance_log_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
ALTER TABLE public.maintenance_log ADD CONSTRAINT maintenance_log_pass_fail_check CHECK ((pass_fail = ANY (ARRAY['pass'::text, 'fail'::text, 'conditional'::text])));
CREATE INDEX idx_maint_log_vehicle ON public.maintenance_log USING btree (vehicle_id, performed_at DESC);

-- ===== maintenance_schedules =====
CREATE TABLE public.maintenance_schedules (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    category maintenance_category NOT NULL,
    frequency maintenance_frequency NOT NULL,
    description text,
    preferred_day_of_week jsonb DEFAULT '[]'::jsonb,
    preferred_time_start time without time zone,
    preferred_time_end time without time zone,
    estimated_duration_minutes integer NOT NULL DEFAULT 60,
    last_performed_at timestamp with time zone,
    last_performed_by uuid,
    next_scheduled_date date,
    next_scheduled_time timestamp with time zone,
    assigned_stall_id uuid,
    trigger_miles_interval integer,
    last_trigger_miles integer,
    current_miles integer,
    status text NOT NULL DEFAULT 'active'::text,
    is_auto_scheduled boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_pkey PRIMARY KEY (id);
ALTER TABLE public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_assigned_stall_id_fkey FOREIGN KEY (assigned_stall_id) REFERENCES stalls(id);
ALTER TABLE public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
ALTER TABLE public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'completed'::text, 'cancelled'::text])));
CREATE INDEX idx_maintenance_depot ON public.maintenance_schedules USING btree (depot_id);
CREATE INDEX idx_maintenance_next ON public.maintenance_schedules USING btree (next_scheduled_date) WHERE (status = 'active'::text);
CREATE INDEX idx_maintenance_vehicle ON public.maintenance_schedules USING btree (vehicle_id);

-- ===== model_parameters =====
CREATE TABLE public.model_parameters (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    parameter_group text NOT NULL,
    parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    version integer NOT NULL DEFAULT 1,
    last_tuned_at timestamp with time zone,
    tuned_by text DEFAULT 'seed'::text,
    performance_metrics jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.model_parameters ADD CONSTRAINT model_parameters_depot_id_parameter_group_key UNIQUE (depot_id, parameter_group);
ALTER TABLE public.model_parameters ADD CONSTRAINT model_parameters_pkey PRIMARY KEY (id);
ALTER TABLE public.model_parameters ADD CONSTRAINT model_parameters_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
CREATE INDEX idx_model_params_depot ON public.model_parameters USING btree (depot_id, is_active);

-- ===== model_tuning_runs =====
CREATE TABLE public.model_tuning_runs (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    parameter_group text NOT NULL,
    trigger_type text NOT NULL,
    parameters_before jsonb NOT NULL,
    parameters_after jsonb NOT NULL,
    parameter_diffs jsonb NOT NULL DEFAULT '[]'::jsonb,
    accuracy_before numeric(5,4) NOT NULL,
    accuracy_after numeric(5,4),
    samples_evaluated integer NOT NULL DEFAULT 0,
    evaluation_window_hours integer NOT NULL DEFAULT 168,
    tuning_method text NOT NULL DEFAULT 'gradient_free'::text,
    status text NOT NULL DEFAULT 'completed'::text,
    improvement_pct numeric(6,3),
    confirmed_at timestamp with time zone,
    rolled_back_at timestamp with time zone,
    rollback_reason text,
    notes text,
    error_message text,
    duration_ms integer,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.model_tuning_runs ADD CONSTRAINT model_tuning_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.model_tuning_runs ADD CONSTRAINT model_tuning_runs_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.model_tuning_runs ADD CONSTRAINT model_tuning_runs_status_check CHECK ((status = ANY (ARRAY['running'::text, 'completed'::text, 'evaluating'::text, 'confirmed'::text, 'rolled_back'::text, 'failed'::text])));
ALTER TABLE public.model_tuning_runs ADD CONSTRAINT model_tuning_runs_trigger_type_check CHECK ((trigger_type = ANY (ARRAY['scheduled'::text, 'accuracy_drift'::text, 'manual'::text, 'threshold_breach'::text])));
ALTER TABLE public.model_tuning_runs ADD CONSTRAINT model_tuning_runs_tuning_method_check CHECK ((tuning_method = ANY (ARRAY['gradient_free'::text, 'bayesian'::text, 'grid_search'::text, 'manual_override'::text, 'rollback'::text])));
CREATE INDEX idx_tuning_runs_depot_time ON public.model_tuning_runs USING btree (depot_id, created_at DESC);
CREATE INDEX idx_tuning_runs_group ON public.model_tuning_runs USING btree (depot_id, parameter_group, created_at DESC);
CREATE INDEX idx_tuning_runs_status ON public.model_tuning_runs USING btree (status, created_at DESC);

-- ===== model_versions =====
CREATE TABLE public.model_versions (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    parameter_group text NOT NULL,
    version_tag text NOT NULL,
    version_number integer NOT NULL,
    parameters jsonb NOT NULL,
    parameters_hash text NOT NULL,
    parent_version_id uuid,
    source text NOT NULL,
    tuning_run_id uuid,
    status text NOT NULL DEFAULT 'draft'::text,
    approved_by text,
    approved_at timestamp with time zone,
    promoted_to_active_at timestamp with time zone,
    archived_at timestamp with time zone,
    accuracy_metrics jsonb DEFAULT '{}'::jsonb,
    promotion_notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by text DEFAULT 'system'::text,
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
    training_metadata jsonb DEFAULT '{}'::jsonb,
    training_run_id uuid,
    shadow_traffic_pct numeric DEFAULT 0,
    expected_latency_p95_ms integer
);
ALTER TABLE public.model_versions ADD CONSTRAINT model_versions_depot_id_parameter_group_version_number_key UNIQUE (depot_id, parameter_group, version_number);
ALTER TABLE public.model_versions ADD CONSTRAINT model_versions_depot_id_parameter_group_version_tag_key UNIQUE (depot_id, parameter_group, version_tag);
ALTER TABLE public.model_versions ADD CONSTRAINT model_versions_pkey PRIMARY KEY (id);
ALTER TABLE public.model_versions ADD CONSTRAINT model_versions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.model_versions ADD CONSTRAINT model_versions_parent_version_id_fkey FOREIGN KEY (parent_version_id) REFERENCES model_versions(id) ON DELETE SET NULL;
ALTER TABLE public.model_versions ADD CONSTRAINT model_versions_tuning_run_id_fkey FOREIGN KEY (tuning_run_id) REFERENCES model_tuning_runs(id) ON DELETE SET NULL;
ALTER TABLE public.model_versions ADD CONSTRAINT model_versions_deployment_stage_check CHECK (((deployment_stage IS NULL) OR (deployment_stage = ANY (ARRAY['training'::text, 'staging'::text, 'canary'::text, 'active'::text, 'rollback'::text, 'retired'::text]))));
ALTER TABLE public.model_versions ADD CONSTRAINT model_versions_source_check CHECK ((source = ANY (ARRAY['seed'::text, 'manual'::text, 'nelder_mead_tuning'::text, 'bayesian_tuning'::text, 'grid_search'::text, 'ab_test_winner'::text, 'rollback'::text, 'partner_override'::text])));
ALTER TABLE public.model_versions ADD CONSTRAINT model_versions_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'candidate'::text, 'active'::text, 'archived'::text, 'deprecated'::text, 'rollback_target'::text])));
CREATE INDEX idx_model_versions_active ON public.model_versions USING btree (depot_id, parameter_group, status) WHERE (status = ANY (ARRAY['active'::text, 'candidate'::text]));
CREATE INDEX idx_model_versions_lineage ON public.model_versions USING btree (parent_version_id);
CREATE INDEX idx_model_versions_oem ON public.model_versions USING btree (oem_id, prediction_type) WHERE (oem_id IS NOT NULL);
CREATE INDEX idx_model_versions_predtype_active ON public.model_versions USING btree (prediction_type, status) WHERE (status = 'active'::text);
CREATE INDEX idx_model_versions_stage ON public.model_versions USING btree (deployment_stage);
CREATE INDEX idx_model_versions_tuning ON public.model_versions USING btree (tuning_run_id);

-- ===== notifications =====
CREATE TABLE public.notifications (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid,
    fleet_operator_id uuid,
    retail_member_id uuid,
    staff_user_id uuid,
    channel notification_channel NOT NULL,
    status notification_status NOT NULL DEFAULT 'queued'::notification_status,
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
    webhook_attempts integer DEFAULT 0,
    scheduled_for timestamp with time zone,
    sent_at timestamp with time zone,
    delivered_at timestamp with time zone,
    read_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_exception_id_fkey FOREIGN KEY (exception_id) REFERENCES exceptions(id);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_retail_member_id_fkey FOREIGN KEY (retail_member_id) REFERENCES retail_members(id);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_schedule_task_id_fkey FOREIGN KEY (schedule_task_id) REFERENCES schedule_tasks(id);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_staff_user_id_fkey FOREIGN KEY (staff_user_id) REFERENCES staff_users(id);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
CREATE INDEX idx_notifications_event ON public.notifications USING btree (event_type, created_at DESC);
CREATE INDEX idx_notifications_fleet ON public.notifications USING btree (fleet_operator_id, created_at DESC);
CREATE INDEX idx_notifications_retail ON public.notifications USING btree (retail_member_id, created_at DESC);
CREATE INDEX idx_notifications_staff ON public.notifications USING btree (staff_user_id, created_at DESC);
CREATE INDEX idx_notifications_status ON public.notifications USING btree (status) WHERE (status = ANY (ARRAY['queued'::notification_status, 'sent'::notification_status]));

-- ===== ocpp_meter_values =====
CREATE TABLE public.ocpp_meter_values (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    ocpp_session_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    charge_point_id text NOT NULL,
    evse_id integer NOT NULL,
    seq_no integer NOT NULL,
    timestamp timestamp with time zone NOT NULL,
    soc_percent integer,
    power_import_kw numeric(8,2),
    energy_import_kwh numeric(10,3),
    voltage_v numeric(6,1),
    current_a numeric(6,1),
    temperature_c numeric(5,1),
    raw_sampled_values jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ocpp_meter_values ADD CONSTRAINT ocpp_meter_values_pkey PRIMARY KEY (id);
ALTER TABLE public.ocpp_meter_values ADD CONSTRAINT ocpp_meter_values_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.ocpp_meter_values ADD CONSTRAINT ocpp_meter_values_ocpp_session_id_fkey FOREIGN KEY (ocpp_session_id) REFERENCES ocpp_sessions(id) ON DELETE CASCADE;
CREATE INDEX idx_meter_values_session ON public.ocpp_meter_values USING btree (ocpp_session_id, seq_no);
CREATE INDEX idx_meter_values_time ON public.ocpp_meter_values USING btree (depot_id, "timestamp" DESC);

-- ===== ocpp_sessions =====
CREATE TABLE public.ocpp_sessions (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    stall_id uuid NOT NULL,
    vehicle_id uuid,
    schedule_task_id uuid,
    charge_point_id text NOT NULL,
    transaction_id text NOT NULL,
    evse_id integer NOT NULL,
    connector_id integer NOT NULL,
    status ocpp_session_status NOT NULL DEFAULT 'active'::ocpp_session_status,
    started_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    soc_start integer,
    soc_end integer,
    energy_delivered_kwh numeric(10,3) NOT NULL DEFAULT 0,
    peak_power_kw numeric(8,2) NOT NULL DEFAULT 0,
    avg_power_kw numeric(8,2) NOT NULL DEFAULT 0,
    connector_temp_c_max numeric(5,1),
    connector_temp_c_final numeric(5,1),
    ambient_temp_c numeric(5,1),
    stopped_reason text,
    id_token text,
    meter_values_count integer NOT NULL DEFAULT 0,
    last_meter_value jsonb,
    charging_profile_applied boolean DEFAULT false,
    max_rate_limit_kw numeric(8,2),
    fault_count integer DEFAULT 0,
    last_fault_message text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    sim_run_id uuid
);
ALTER TABLE public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_pkey PRIMARY KEY (id);
ALTER TABLE public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_transaction_id_key UNIQUE (transaction_id);
ALTER TABLE public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_schedule_task_id_fkey FOREIGN KEY (schedule_task_id) REFERENCES schedule_tasks(id);
ALTER TABLE public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES stalls(id);
ALTER TABLE public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
CREATE INDEX idx_ocpp_sessions_active ON public.ocpp_sessions USING btree (status) WHERE (status = 'active'::ocpp_session_status);
CREATE INDEX idx_ocpp_sessions_active_run ON public.ocpp_sessions USING btree (depot_id, sim_run_id) WHERE (status = 'active'::ocpp_session_status);
CREATE INDEX idx_ocpp_sessions_charge_point ON public.ocpp_sessions USING btree (charge_point_id, started_at DESC);
CREATE INDEX idx_ocpp_sessions_depot ON public.ocpp_sessions USING btree (depot_id, started_at DESC);
CREATE INDEX idx_ocpp_sessions_stall ON public.ocpp_sessions USING btree (stall_id);
CREATE INDEX idx_ocpp_sessions_transaction ON public.ocpp_sessions USING btree (transaction_id);
CREATE INDEX idx_ocpp_sessions_vehicle ON public.ocpp_sessions USING btree (vehicle_id) WHERE (vehicle_id IS NOT NULL);
CREATE UNIQUE INDEX uniq_ocpp_active_session_per_stall ON public.ocpp_sessions USING btree (stall_id) WHERE (status = 'active'::ocpp_session_status);

-- ===== ottoq_ab_runs =====
CREATE TABLE public.ottoq_ab_runs (
    ab_run_id uuid NOT NULL DEFAULT gen_random_uuid(),
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
    scored_at timestamp with time zone NOT NULL DEFAULT now(),
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
ALTER TABLE public.ottoq_ab_runs ADD CONSTRAINT ottoq_ab_runs_pkey PRIMARY KEY (ab_run_id);
ALTER TABLE public.ottoq_ab_runs ADD CONSTRAINT ottoq_ab_runs_policy_check CHECK ((policy = ANY (ARRAY['otto_q'::text, 'greedy'::text, 'fifo'::text, 'manual'::text])));
CREATE INDEX idx_ab_runs_group ON public.ottoq_ab_runs USING btree (ab_group_id, policy);

-- ===== ottoq_anomaly_detectors =====
CREATE TABLE public.ottoq_anomaly_detectors (
    detector_id uuid NOT NULL DEFAULT gen_random_uuid(),
    detector_code text NOT NULL,
    category text NOT NULL,
    method text NOT NULL,
    target_feature text,
    target_entity_type text NOT NULL,
    observation_source text,
    parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    anomaly_score_threshold numeric NOT NULL DEFAULT 0.7,
    severity_low_threshold numeric DEFAULT 0.5,
    severity_high_threshold numeric DEFAULT 0.85,
    severity_critical_threshold numeric DEFAULT 0.95,
    emit_event boolean NOT NULL DEFAULT true,
    create_exception boolean NOT NULL DEFAULT false,
    required_resolver_role text,
    title text NOT NULL,
    description text NOT NULL,
    rationale text,
    status text NOT NULL DEFAULT 'active'::text,
    introduced_in text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    observations_total bigint NOT NULL DEFAULT 0,
    observations_anomalous bigint NOT NULL DEFAULT 0,
    last_anomaly_at timestamp with time zone,
    last_observation_at timestamp with time zone
);
ALTER TABLE public.ottoq_anomaly_detectors ADD CONSTRAINT ottoq_anomaly_detectors_detector_code_key UNIQUE (detector_code);
ALTER TABLE public.ottoq_anomaly_detectors ADD CONSTRAINT ottoq_anomaly_detectors_pkey PRIMARY KEY (detector_id);
ALTER TABLE public.ottoq_anomaly_detectors ADD CONSTRAINT ottoq_anomaly_detectors_category_check CHECK ((category = ANY (ARRAY['charging'::text, 'washing'::text, 'calibration'::text, 'arrival'::text, 'state_of_charge'::text, 'telemetry'::text, 'energy'::text, 'operational'::text])));
ALTER TABLE public.ottoq_anomaly_detectors ADD CONSTRAINT ottoq_anomaly_detectors_method_check CHECK ((method = ANY (ARRAY['threshold'::text, 'z_score'::text, 'iqr'::text, 'rate_of_change'::text, 'rolling_window'::text, 'ml_isoforest'::text, 'ml_lstm'::text, 'custom'::text])));
ALTER TABLE public.ottoq_anomaly_detectors ADD CONSTRAINT ottoq_anomaly_detectors_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'shadow'::text, 'active'::text, 'deprecated'::text, 'archived'::text])));
CREATE INDEX idx_anomaly_detectors_active ON public.ottoq_anomaly_detectors USING btree (target_feature, status) WHERE (status = 'active'::text);
CREATE INDEX idx_anomaly_detectors_category ON public.ottoq_anomaly_detectors USING btree (category, status);

-- ===== ottoq_anomaly_observations =====
CREATE TABLE public.ottoq_anomaly_observations (
    observation_id uuid NOT NULL DEFAULT gen_random_uuid(),
    observation_seq bigint NOT NULL DEFAULT nextval('ottoq_anomaly_observations_observation_seq_seq'::regclass),
    detector_id uuid NOT NULL,
    detector_code text NOT NULL,
    observed_at timestamp with time zone NOT NULL DEFAULT now(),
    entity_type text NOT NULL,
    entity_id uuid,
    feature_name text,
    observed_value jsonb,
    anomaly_score numeric NOT NULL,
    is_anomaly boolean NOT NULL,
    severity text NOT NULL,
    context jsonb NOT NULL DEFAULT '{}'::jsonb,
    event_emitted boolean NOT NULL DEFAULT false,
    exception_created boolean NOT NULL DEFAULT false,
    linked_event_id uuid,
    exception_id uuid,
    fleet_operator_id uuid,
    depot_id uuid,
    correlation_id uuid
);
ALTER TABLE public.ottoq_anomaly_observations ADD CONSTRAINT ottoq_anomaly_observations_observation_seq_key UNIQUE (observation_seq);
ALTER TABLE public.ottoq_anomaly_observations ADD CONSTRAINT ottoq_anomaly_observations_pkey PRIMARY KEY (observation_id);
ALTER TABLE public.ottoq_anomaly_observations ADD CONSTRAINT ottoq_anomaly_observations_detector_id_fkey FOREIGN KEY (detector_id) REFERENCES ottoq_anomaly_detectors(detector_id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_anomaly_observations ADD CONSTRAINT ottoq_anomaly_observations_linked_event_id_fkey FOREIGN KEY (linked_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_anomaly_observations ADD CONSTRAINT ottoq_anomaly_observations_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
CREATE INDEX idx_anomaly_obs_anomalous ON public.ottoq_anomaly_observations USING btree (observed_at DESC) WHERE (is_anomaly = true);
CREATE INDEX idx_anomaly_obs_detector_time ON public.ottoq_anomaly_observations USING btree (detector_id, observed_at DESC);
CREATE INDEX idx_anomaly_obs_entity_time ON public.ottoq_anomaly_observations USING btree (entity_type, entity_id, observed_at DESC);
CREATE INDEX idx_anomaly_obs_linked_event ON public.ottoq_anomaly_observations USING btree (linked_event_id);
CREATE INDEX idx_anomaly_obs_seq_brin ON public.ottoq_anomaly_observations USING brin (observation_seq);
CREATE INDEX idx_anomaly_obs_tenant ON public.ottoq_anomaly_observations USING btree (fleet_operator_id, observed_at DESC) WHERE (fleet_operator_id IS NOT NULL);

-- ===== ottoq_audit_bundles =====
CREATE TABLE public.ottoq_audit_bundles (
    bundle_id uuid NOT NULL DEFAULT gen_random_uuid(),
    bundle_seq bigint NOT NULL DEFAULT nextval('ottoq_audit_bundles_bundle_seq_seq'::regclass),
    bundle_code text NOT NULL,
    fleet_operator_id uuid NOT NULL,
    report_ids uuid[] NOT NULL,
    event_id_range_low bigint,
    event_id_range_high bigint,
    window_start timestamp with time zone NOT NULL,
    window_end timestamp with time zone NOT NULL,
    format text NOT NULL DEFAULT 'jsonl'::text,
    storage_path text,
    size_bytes bigint,
    sha256 text NOT NULL,
    signature text NOT NULL,
    signature_key_id text NOT NULL,
    signature_algorithm text NOT NULL DEFAULT 'HMAC-SHA-256'::text,
    manifest jsonb NOT NULL,
    public_verification_url text,
    generated_at timestamp with time zone NOT NULL DEFAULT now(),
    generated_by_actor_type text,
    generated_by_actor_id text,
    delivered_to text,
    delivered_at timestamp with time zone,
    download_count integer NOT NULL DEFAULT 0,
    last_downloaded_at timestamp with time zone,
    expires_at timestamp with time zone,
    revoked_at timestamp with time zone,
    revocation_reason text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_audit_bundles ADD CONSTRAINT ottoq_audit_bundles_bundle_code_key UNIQUE (bundle_code);
ALTER TABLE public.ottoq_audit_bundles ADD CONSTRAINT ottoq_audit_bundles_bundle_seq_key UNIQUE (bundle_seq);
ALTER TABLE public.ottoq_audit_bundles ADD CONSTRAINT ottoq_audit_bundles_pkey PRIMARY KEY (bundle_id);
ALTER TABLE public.ottoq_audit_bundles ADD CONSTRAINT ottoq_audit_bundles_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_audit_bundles ADD CONSTRAINT ottoq_audit_bundles_format_check CHECK ((format = ANY (ARRAY['jsonl'::text, 'json'::text, 'csv'::text, 'zip'::text, 'pdf'::text, 'custom'::text])));
CREATE INDEX idx_audit_bundles_code ON public.ottoq_audit_bundles USING btree (bundle_code);
CREATE INDEX idx_audit_bundles_tenant_time ON public.ottoq_audit_bundles USING btree (fleet_operator_id, generated_at DESC);

-- ===== ottoq_audit_reports =====
CREATE TABLE public.ottoq_audit_reports (
    report_id uuid NOT NULL DEFAULT gen_random_uuid(),
    report_seq bigint NOT NULL DEFAULT nextval('ottoq_audit_reports_report_seq_seq'::regclass),
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
    requested_at timestamp with time zone NOT NULL DEFAULT now(),
    generation_started_at timestamp with time zone,
    generation_completed_at timestamp with time zone,
    generation_status text NOT NULL DEFAULT 'pending'::text,
    generation_duration_ms integer,
    generation_error text,
    payload jsonb,
    payload_hash text,
    signature text,
    signature_key_id text,
    signature_algorithm text DEFAULT 'HMAC-SHA-256'::text,
    event_count bigint,
    rule_eval_count bigint,
    prediction_count bigint,
    anomaly_count bigint,
    override_count bigint,
    emergency_count bigint,
    visit_count bigint,
    title text,
    description text,
    format text DEFAULT 'json'::text,
    expires_at timestamp with time zone,
    parent_report_id uuid,
    source_event_id uuid,
    audit_trail_complete boolean,
    data_quality_score numeric,
    exclusions jsonb DEFAULT '[]'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_pkey PRIMARY KEY (report_id);
ALTER TABLE public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_report_seq_key UNIQUE (report_seq);
ALTER TABLE public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_parent_report_id_fkey FOREIGN KEY (parent_report_id) REFERENCES ottoq_audit_reports(report_id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_source_event_id_fkey FOREIGN KEY (source_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_check CHECK ((window_end > window_start));
ALTER TABLE public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_format_check CHECK ((format = ANY (ARRAY['json'::text, 'csv'::text, 'pdf'::text, 'xml'::text, 'custom'::text])));
ALTER TABLE public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_generation_status_check CHECK ((generation_status = ANY (ARRAY['pending'::text, 'generating'::text, 'completed'::text, 'failed'::text, 'expired'::text])));
ALTER TABLE public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_report_type_check CHECK ((report_type = ANY (ARRAY['sla_conformance'::text, 'visit_summary'::text, 'incident_forensic'::text, 'energy_attribution'::text, 'predictive_accuracy'::text, 'safety_event_summary'::text, 'override_audit'::text, 'cross_depot_benchmark'::text, 'regulatory_export'::text, 'oem_dashboard_snapshot'::text, 'counterfactual_analysis'::text, 'custom'::text])));
CREATE INDEX idx_audit_reports_depot_time ON public.ottoq_audit_reports USING btree (depot_id, window_end DESC) WHERE (depot_id IS NOT NULL);
CREATE INDEX idx_audit_reports_source_event ON public.ottoq_audit_reports USING btree (source_event_id);
CREATE INDEX idx_audit_reports_status ON public.ottoq_audit_reports USING btree (generation_status, requested_at DESC) WHERE (generation_status = ANY (ARRAY['pending'::text, 'generating'::text]));
CREATE INDEX idx_audit_reports_tenant_time ON public.ottoq_audit_reports USING btree (fleet_operator_id, window_end DESC) WHERE (fleet_operator_id IS NOT NULL);
CREATE INDEX idx_audit_reports_type ON public.ottoq_audit_reports USING btree (report_type, requested_at DESC);

-- ===== ottoq_benchmark_frames =====
CREATE TABLE public.ottoq_benchmark_frames (
    id bigint NOT NULL DEFAULT nextval('ottoq_benchmark_frames_id_seq'::regclass),
    comparison_id uuid NOT NULL,
    policy text NOT NULL,
    tick integer NOT NULL,
    frame jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_benchmark_frames ADD CONSTRAINT ottoq_benchmark_frames_pkey PRIMARY KEY (id);
CREATE INDEX idx_bench_frames_comp ON public.ottoq_benchmark_frames USING btree (comparison_id, policy, tick);

-- ===== ottoq_bess_units =====
CREATE TABLE public.ottoq_bess_units (
    bess_id uuid NOT NULL DEFAULT gen_random_uuid(),
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
    current_state text NOT NULL DEFAULT 'idle'::text,
    current_power_kw numeric,
    current_state_updated_at timestamp with time zone NOT NULL DEFAULT now(),
    last_heartbeat_at timestamp with time zone,
    soc_min_floor_pct numeric NOT NULL DEFAULT 10.0,
    soc_max_ceiling_pct numeric NOT NULL DEFAULT 95.0,
    temperature_max_c numeric NOT NULL DEFAULT 50.0,
    temperature_min_c numeric NOT NULL DEFAULT '-10.0'::numeric,
    last_fault_code text,
    last_fault_at timestamp with time zone,
    last_fault_payload jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    current_soh_pct numeric DEFAULT 100.0,
    current_cycle_count numeric DEFAULT 0,
    lifetime_kwh_charged numeric DEFAULT 0,
    lifetime_kwh_discharged numeric DEFAULT 0,
    chemistry text DEFAULT 'LFP'::text,
    roundtrip_efficiency_pct numeric DEFAULT 0.96,
    auxiliary_load_kw numeric DEFAULT 8.0
);
ALTER TABLE public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_bess_identifier_key UNIQUE (bess_identifier);
ALTER TABLE public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_pkey PRIMARY KEY (bess_id);
ALTER TABLE public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_current_state_check CHECK ((current_state = ANY (ARRAY['idle'::text, 'charging'::text, 'discharging'::text, 'maintenance'::text, 'fault'::text, 'offline'::text])));
CREATE INDEX idx_ottoq_bess_depot ON public.ottoq_bess_units USING btree (depot_id, current_state);
CREATE INDEX idx_ottoq_bess_state ON public.ottoq_bess_units USING btree (current_state, current_state_updated_at);

-- ===== ottoq_calibration_correlations =====
CREATE TABLE public.ottoq_calibration_correlations (
    correlation_id uuid NOT NULL DEFAULT gen_random_uuid(),
    dataset_code text NOT NULL,
    variable_a text NOT NULL,
    variable_b text NOT NULL,
    coefficient numeric NOT NULL,
    method text NOT NULL DEFAULT 'pearson'::text,
    sample_count bigint,
    fitted_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_calibration_correlations ADD CONSTRAINT ottoq_calibration_correlation_dataset_code_variable_a_varia_key UNIQUE (dataset_code, variable_a, variable_b, method);
ALTER TABLE public.ottoq_calibration_correlations ADD CONSTRAINT ottoq_calibration_correlations_pkey PRIMARY KEY (correlation_id);
ALTER TABLE public.ottoq_calibration_correlations ADD CONSTRAINT ottoq_calibration_correlations_dataset_code_fkey FOREIGN KEY (dataset_code) REFERENCES ottoq_calibration_datasets(dataset_code) ON DELETE CASCADE;
ALTER TABLE public.ottoq_calibration_correlations ADD CONSTRAINT ottoq_calibration_correlations_method_check CHECK ((method = ANY (ARRAY['pearson'::text, 'spearman'::text, 'kendall'::text])));

-- ===== ottoq_calibration_datasets =====
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
    status text NOT NULL DEFAULT 'pending'::text,
    data_quality_score numeric,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_calibration_datasets ADD CONSTRAINT ottoq_calibration_datasets_pkey PRIMARY KEY (dataset_code);
ALTER TABLE public.ottoq_calibration_datasets ADD CONSTRAINT ottoq_calibration_datasets_domain_check CHECK ((domain = ANY (ARRAY['charging'::text, 'arrivals'::text, 'incidents'::text, 'weather'::text, 'grid'::text, 'reliability'::text, 'fleet'::text, 'energy'::text])));
ALTER TABLE public.ottoq_calibration_datasets ADD CONSTRAINT ottoq_calibration_datasets_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'ingested'::text, 'stale'::text, 'failed'::text, 'partial'::text])));

-- ===== ottoq_calibration_distributions =====
CREATE TABLE public.ottoq_calibration_distributions (
    distribution_id uuid NOT NULL DEFAULT gen_random_uuid(),
    dataset_code text NOT NULL,
    variable_name text NOT NULL,
    segment text NOT NULL DEFAULT 'global'::text,
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
    fitted_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_calibration_distributions ADD CONSTRAINT ottoq_calibration_distributio_dataset_code_variable_name_se_key UNIQUE (dataset_code, variable_name, segment);
ALTER TABLE public.ottoq_calibration_distributions ADD CONSTRAINT ottoq_calibration_distributions_pkey PRIMARY KEY (distribution_id);
ALTER TABLE public.ottoq_calibration_distributions ADD CONSTRAINT ottoq_calibration_distributions_dataset_code_fkey FOREIGN KEY (dataset_code) REFERENCES ottoq_calibration_datasets(dataset_code) ON DELETE CASCADE;
CREATE INDEX idx_calib_dist_dataset ON public.ottoq_calibration_distributions USING btree (dataset_code);
CREATE INDEX idx_calib_dist_variable ON public.ottoq_calibration_distributions USING btree (variable_name, segment);

-- ===== ottoq_calibration_metrics =====
CREATE TABLE public.ottoq_calibration_metrics (
    calibration_id uuid NOT NULL DEFAULT gen_random_uuid(),
    prediction_type text NOT NULL,
    model_version_id uuid,
    computed_at timestamp with time zone NOT NULL DEFAULT now(),
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
    payload jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_calibration_metrics ADD CONSTRAINT ottoq_calibration_metrics_pkey PRIMARY KEY (calibration_id);
ALTER TABLE public.ottoq_calibration_metrics ADD CONSTRAINT ottoq_calibration_metrics_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES model_versions(id) ON DELETE SET NULL;
CREATE INDEX idx_calib_model ON public.ottoq_calibration_metrics USING btree (model_version_id, computed_at DESC) WHERE (model_version_id IS NOT NULL);
CREATE INDEX idx_calib_type_time ON public.ottoq_calibration_metrics USING btree (prediction_type, computed_at DESC);

-- ===== ottoq_calibration_profiles =====
CREATE TABLE public.ottoq_calibration_profiles (
    profile_id uuid NOT NULL DEFAULT gen_random_uuid(),
    dataset_code text NOT NULL,
    profile_name text NOT NULL,
    profile_kind text NOT NULL,
    profile_data jsonb NOT NULL,
    units text,
    description text,
    normalization text,
    fitted_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_calibration_profiles ADD CONSTRAINT ottoq_calibration_profiles_dataset_code_profile_name_key UNIQUE (dataset_code, profile_name);
ALTER TABLE public.ottoq_calibration_profiles ADD CONSTRAINT ottoq_calibration_profiles_pkey PRIMARY KEY (profile_id);
ALTER TABLE public.ottoq_calibration_profiles ADD CONSTRAINT ottoq_calibration_profiles_dataset_code_fkey FOREIGN KEY (dataset_code) REFERENCES ottoq_calibration_datasets(dataset_code) ON DELETE CASCADE;
ALTER TABLE public.ottoq_calibration_profiles ADD CONSTRAINT ottoq_calibration_profiles_profile_kind_check CHECK ((profile_kind = ANY (ARRAY['hourly_24'::text, 'daily_7'::text, 'monthly_12'::text, 'custom'::text])));

-- ===== ottoq_canopy_state =====
CREATE TABLE public.ottoq_canopy_state (
    canopy_code text NOT NULL,
    depot_id uuid NOT NULL,
    structure_id uuid,
    nameplate_dc_kw numeric NOT NULL DEFAULT 180,
    nameplate_ac_kw numeric NOT NULL DEFAULT 150,
    tilt_deg numeric NOT NULL DEFAULT 30,
    azimuth_deg numeric NOT NULL DEFAULT 180,
    current_soiling numeric NOT NULL DEFAULT 1.00,
    last_rain_clean_at timestamp with time zone,
    last_updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_canopy_state ADD CONSTRAINT ottoq_canopy_state_pkey PRIMARY KEY (canopy_code);

-- ===== ottoq_cert_queue =====
CREATE TABLE public.ottoq_cert_queue (
    id bigint NOT NULL,
    scenario text NOT NULL DEFAULT 'shift'::text,
    seed bigint NOT NULL,
    policy text NOT NULL,
    ab_group uuid NOT NULL,
    ticks integer NOT NULL DEFAULT 24,
    fault_chargers integer NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'pending'::text,
    error text,
    enqueued_at timestamp with time zone NOT NULL DEFAULT now(),
    started_at timestamp with time zone,
    finished_at timestamp with time zone
);
ALTER TABLE public.ottoq_cert_queue ADD CONSTRAINT ottoq_cert_queue_pkey PRIMARY KEY (id);
ALTER TABLE public.ottoq_cert_queue ADD CONSTRAINT ottoq_cert_queue_policy_check CHECK ((policy = ANY (ARRAY['otto_q'::text, 'greedy'::text, 'fifo'::text])));
ALTER TABLE public.ottoq_cert_queue ADD CONSTRAINT ottoq_cert_queue_scenario_check CHECK ((scenario = ANY (ARRAY['shift'::text, 'wave'::text])));
ALTER TABLE public.ottoq_cert_queue ADD CONSTRAINT ottoq_cert_queue_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'done'::text, 'error'::text])));

-- ===== ottoq_cil_adoptions =====
CREATE TABLE public.ottoq_cil_adoptions (
    adoption_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid,
    depot_id uuid,
    decided_at timestamp with time zone DEFAULT now(),
    adopted boolean,
    plan_label text,
    params jsonb,
    score_current numeric,
    score_adopted numeric,
    source text DEFAULT 'cil_heuristic'::text,
    rationale text,
    eval jsonb
);
ALTER TABLE public.ottoq_cil_adoptions ADD CONSTRAINT ottoq_cil_adoptions_pkey PRIMARY KEY (adoption_id);

-- ===== ottoq_comms_messages =====
CREATE TABLE public.ottoq_comms_messages (
    msg_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid,
    vehicle_id uuid,
    correlation_id uuid,
    direction text NOT NULL,
    topic text NOT NULL,
    msg_type text NOT NULL,
    qos smallint NOT NULL DEFAULT 1,
    header jsonb NOT NULL,
    payload jsonb NOT NULL,
    status text NOT NULL DEFAULT 'sent'::text,
    latency_ms integer,
    sim_clock_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_comms_messages ADD CONSTRAINT ottoq_comms_messages_pkey PRIMARY KEY (msg_id);
CREATE INDEX ix_comms_corr ON public.ottoq_comms_messages USING btree (correlation_id);
CREATE INDEX ix_comms_run_veh ON public.ottoq_comms_messages USING btree (sim_run_id, vehicle_id, created_at);

-- ===== ottoq_counterfactuals =====
CREATE TABLE public.ottoq_counterfactuals (
    counterfactual_id uuid NOT NULL DEFAULT gen_random_uuid(),
    counterfactual_seq bigint NOT NULL DEFAULT nextval('ottoq_counterfactuals_counterfactual_seq_seq'::regclass),
    source_kind text NOT NULL,
    source_id uuid NOT NULL,
    source_event_id uuid,
    source_correlation_id uuid,
    ran_at timestamp with time zone NOT NULL DEFAULT now(),
    source_decision_at timestamp with time zone,
    scenario_label text NOT NULL,
    scenario_description text,
    alternate_inputs jsonb NOT NULL DEFAULT '{}'::jsonb,
    alternate_model_version_id uuid,
    alternate_parameters jsonb DEFAULT '{}'::jsonb,
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
    status text NOT NULL DEFAULT 'completed'::text,
    ran_by_actor_type text,
    ran_by_actor_id text,
    payload jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_counterfactual_seq_key UNIQUE (counterfactual_seq);
ALTER TABLE public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_pkey PRIMARY KEY (counterfactual_id);
ALTER TABLE public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_source_event_id_fkey FOREIGN KEY (source_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_delta_direction_check CHECK (((delta_direction IS NULL) OR (delta_direction = ANY (ARRAY['better'::text, 'worse'::text, 'neutral'::text, 'ambiguous'::text]))));
ALTER TABLE public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_source_kind_check CHECK ((source_kind = ANY (ARRAY['decision'::text, 'recommendation'::text, 'prediction'::text, 'rule_evaluation'::text, 'override'::text])));
ALTER TABLE public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_status_check CHECK ((status = ANY (ARRAY['running'::text, 'completed'::text, 'failed'::text, 'review'::text])));
CREATE INDEX idx_counterfactuals_scenario ON public.ottoq_counterfactuals USING btree (scenario_label, ran_at DESC);
CREATE INDEX idx_counterfactuals_source ON public.ottoq_counterfactuals USING btree (source_kind, source_id);
CREATE INDEX idx_counterfactuals_src_event ON public.ottoq_counterfactuals USING btree (source_event_id);
CREATE INDEX idx_counterfactuals_tenant_time ON public.ottoq_counterfactuals USING btree (fleet_operator_id, ran_at DESC) WHERE (fleet_operator_id IS NOT NULL);

-- ===== ottoq_cuopt_deferrals =====
CREATE TABLE public.ottoq_cuopt_deferrals (
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    state text NOT NULL DEFAULT 'armed'::text,
    armed_at_tick bigint,
    armed_at_sim timestamp with time zone,
    armed_at_real timestamp with time zone DEFAULT now(),
    spent_at_tick bigint,
    cleared_at_tick bigint,
    net_request_id bigint,
    defer_count integer NOT NULL DEFAULT 0
);
ALTER TABLE public.ottoq_cuopt_deferrals ADD CONSTRAINT ottoq_cuopt_deferrals_pkey PRIMARY KEY (sim_run_id, vehicle_id);
ALTER TABLE public.ottoq_cuopt_deferrals ADD CONSTRAINT ottoq_cuopt_deferrals_state_ck CHECK ((state = ANY (ARRAY['armed'::text, 'spent'::text, 'clear'::text])));
CREATE INDEX idx_cuopt_deferrals_run_state ON public.ottoq_cuopt_deferrals USING btree (sim_run_id, state, spent_at_tick);

-- ===== ottoq_cuopt_fire_log =====
CREATE TABLE public.ottoq_cuopt_fire_log (
    sim_run_id uuid NOT NULL,
    fired_at timestamp with time zone NOT NULL
);
ALTER TABLE public.ottoq_cuopt_fire_log ADD CONSTRAINT ottoq_cuopt_fire_log_pkey PRIMARY KEY (sim_run_id);

-- ===== ottoq_data_drift_metrics =====
CREATE TABLE public.ottoq_data_drift_metrics (
    drift_id uuid NOT NULL DEFAULT gen_random_uuid(),
    feature_name text NOT NULL,
    scope text NOT NULL DEFAULT 'global'::text,
    scope_id text,
    computed_at timestamp with time zone NOT NULL DEFAULT now(),
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
    retraining_triggered boolean NOT NULL DEFAULT false,
    alert_emitted boolean NOT NULL DEFAULT false,
    payload jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_data_drift_metrics ADD CONSTRAINT ottoq_data_drift_metrics_pkey PRIMARY KEY (drift_id);
ALTER TABLE public.ottoq_data_drift_metrics ADD CONSTRAINT ottoq_data_drift_metrics_drift_severity_check CHECK ((drift_severity = ANY (ARRAY['none'::text, 'minor'::text, 'moderate'::text, 'severe'::text])));
ALTER TABLE public.ottoq_data_drift_metrics ADD CONSTRAINT ottoq_data_drift_metrics_scope_check CHECK ((scope = ANY (ARRAY['global'::text, 'fleet_operator'::text, 'depot'::text, 'vehicle_class'::text])));
CREATE INDEX idx_drift_detected ON public.ottoq_data_drift_metrics USING btree (computed_at DESC) WHERE (drift_detected = true);
CREATE INDEX idx_drift_feature_time ON public.ottoq_data_drift_metrics USING btree (feature_name, computed_at DESC);

-- ===== ottoq_decision_snapshots =====
CREATE TABLE public.ottoq_decision_snapshots (
    snapshot_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid NOT NULL,
    tick_seq bigint NOT NULL,
    depot_id uuid NOT NULL,
    captured_at timestamp with time zone NOT NULL DEFAULT now(),
    sim_clock timestamp with time zone NOT NULL,
    content_hash text NOT NULL,
    frame jsonb NOT NULL,
    frame_counts jsonb NOT NULL DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_decision_snapshots ADD CONSTRAINT ottoq_decision_snapshots_pkey PRIMARY KEY (snapshot_id);
ALTER TABLE public.ottoq_decision_snapshots ADD CONSTRAINT ottoq_decision_snapshots_sim_run_id_tick_seq_key UNIQUE (sim_run_id, tick_seq);
CREATE INDEX idx_decision_snapshots_depot_clock ON public.ottoq_decision_snapshots USING btree (depot_id, sim_clock);
CREATE INDEX idx_decision_snapshots_run_tick ON public.ottoq_decision_snapshots USING btree (sim_run_id, tick_seq);

-- ===== ottoq_decisions =====
CREATE TABLE public.ottoq_decisions (
    decision_id uuid NOT NULL DEFAULT gen_random_uuid(),
    decision_seq bigint NOT NULL DEFAULT nextval('ottoq_decisions_decision_seq_seq'::regclass),
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
    overridden boolean NOT NULL DEFAULT false,
    override_rule_code text,
    override_rule_codes text[],
    override_reason text,
    override_id uuid,
    rule_results jsonb NOT NULL DEFAULT '[]'::jsonb,
    shield_verdict jsonb,
    shield_disarm_flags jsonb NOT NULL DEFAULT '[]'::jsonb,
    safe_default_taken boolean NOT NULL DEFAULT false,
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
    l2_engine text DEFAULT 'deterministic_v1'::text,
    confidence numeric,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_decisions ADD CONSTRAINT ottoq_decisions_decision_seq_key UNIQUE (decision_seq);
ALTER TABLE public.ottoq_decisions ADD CONSTRAINT ottoq_decisions_pkey PRIMARY KEY (decision_id);
ALTER TABLE public.ottoq_decisions ADD CONSTRAINT ottoq_decisions_gate_check CHECK ((gate = ANY (ARRAY['A'::text, 'B'::text])));
ALTER TABLE public.ottoq_decisions ADD CONSTRAINT ottoq_decisions_outcome_status_check CHECK ((outcome_status = ANY (ARRAY['enacted'::text, 'overridden_to_default'::text, 'deferred_noop'::text, 'errored'::text, 'noop_no_candidate'::text, 'shield_disarmed'::text, 'deferred_stale_entity'::text, 'context_insufficient'::text])));
CREATE INDEX idx_decisions_action ON public.ottoq_decisions USING btree (action_context, outcome_status);
CREATE INDEX idx_decisions_run_entity_redeploy ON public.ottoq_decisions USING btree (sim_run_id, entity_id, tick_seq) WHERE ((action_context = 'redeployment'::text) AND (outcome_status = 'enacted'::text));
CREATE INDEX idx_decisions_run_tick ON public.ottoq_decisions USING btree (sim_run_id, tick_seq);

-- ===== ottoq_deploy_log =====
CREATE TABLE public.ottoq_deploy_log (
    deploy_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    policy text,
    sim_clock timestamp with time zone,
    soc_at_deploy numeric,
    floor_at_deploy numeric,
    is_productive boolean,
    from_state text,
    to_state text,
    logged_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_deploy_log ADD CONSTRAINT ottoq_deploy_log_pkey PRIMARY KEY (deploy_id);
CREATE INDEX ottoq_deploy_log_run_idx ON public.ottoq_deploy_log USING btree (sim_run_id);

-- ===== ottoq_depot_benchmarks_daily =====
CREATE TABLE public.ottoq_depot_benchmarks_daily (
    benchmark_id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    report_date date NOT NULL,
    visits_completed integer NOT NULL DEFAULT 0,
    vehicles_served integer NOT NULL DEFAULT 0,
    oems_served integer NOT NULL DEFAULT 0,
    total_service_hours numeric NOT NULL DEFAULT 0,
    stall_utilization_pct numeric,
    avg_sla_compliance_pct numeric,
    worst_sla_compliance_pct numeric,
    sla_violations_count integer NOT NULL DEFAULT 0,
    total_kwh_delivered numeric NOT NULL DEFAULT 0,
    peak_demand_kw numeric,
    solar_self_consumption_pct numeric,
    bess_cycles_today numeric,
    total_revenue_usd numeric NOT NULL DEFAULT 0,
    total_cost_usd numeric NOT NULL DEFAULT 0,
    margin_pct numeric,
    cost_per_visit_usd numeric,
    cost_per_kwh_blended_usd numeric,
    rule_failures_count integer NOT NULL DEFAULT 0,
    anomalies_count integer NOT NULL DEFAULT 0,
    emergencies_count integer NOT NULL DEFAULT 0,
    overrides_count integer NOT NULL DEFAULT 0,
    avg_prediction_mape numeric,
    avg_prediction_coverage_80 numeric,
    total_carbon_offset_kg numeric NOT NULL DEFAULT 0,
    computed_at timestamp with time zone NOT NULL DEFAULT now(),
    payload jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_depot_benchmarks_daily ADD CONSTRAINT ottoq_depot_benchmarks_daily_depot_id_report_date_key UNIQUE (depot_id, report_date);
ALTER TABLE public.ottoq_depot_benchmarks_daily ADD CONSTRAINT ottoq_depot_benchmarks_daily_pkey PRIMARY KEY (benchmark_id);
ALTER TABLE public.ottoq_depot_benchmarks_daily ADD CONSTRAINT ottoq_depot_benchmarks_daily_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
CREATE INDEX idx_depot_benchmarks_date ON public.ottoq_depot_benchmarks_daily USING btree (report_date DESC);
CREATE INDEX idx_depot_benchmarks_depot_date ON public.ottoq_depot_benchmarks_daily USING btree (depot_id, report_date DESC);

-- ===== ottoq_depot_cost_daily =====
CREATE TABLE public.ottoq_depot_cost_daily (
    depot_cost_daily_id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    report_date date NOT NULL,
    visits_completed integer NOT NULL DEFAULT 0,
    unique_vehicles integer NOT NULL DEFAULT 0,
    unique_fleet_operators integer NOT NULL DEFAULT 0,
    total_kwh_delivered numeric NOT NULL DEFAULT 0,
    total_kwh_from_grid numeric NOT NULL DEFAULT 0,
    total_kwh_from_solar numeric NOT NULL DEFAULT 0,
    total_kwh_from_bess numeric NOT NULL DEFAULT 0,
    peak_demand_kw numeric,
    solar_self_consumption_pct numeric,
    total_energy_cost_usd numeric NOT NULL DEFAULT 0,
    total_demand_charge_usd numeric NOT NULL DEFAULT 0,
    total_labor_cost_usd numeric NOT NULL DEFAULT 0,
    total_opportunity_cost_usd numeric NOT NULL DEFAULT 0,
    fixed_overhead_usd numeric NOT NULL DEFAULT 0,
    total_operating_cost_usd numeric NOT NULL DEFAULT 0,
    total_revenue_usd numeric NOT NULL DEFAULT 0,
    total_margin_usd numeric NOT NULL DEFAULT 0,
    margin_pct numeric,
    total_carbon_offset_kg numeric NOT NULL DEFAULT 0,
    carbon_intensity_avg numeric,
    avg_kwh_per_visit numeric,
    avg_cost_per_visit_usd numeric,
    avg_margin_per_visit_usd numeric,
    cost_per_kwh_blended_usd numeric,
    computed_at timestamp with time zone NOT NULL DEFAULT now(),
    payload jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_depot_cost_daily ADD CONSTRAINT ottoq_depot_cost_daily_depot_id_report_date_key UNIQUE (depot_id, report_date);
ALTER TABLE public.ottoq_depot_cost_daily ADD CONSTRAINT ottoq_depot_cost_daily_pkey PRIMARY KEY (depot_cost_daily_id);
ALTER TABLE public.ottoq_depot_cost_daily ADD CONSTRAINT ottoq_depot_cost_daily_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
CREATE INDEX idx_depot_cost_daily_date ON public.ottoq_depot_cost_daily USING btree (report_date DESC);

-- ===== ottoq_depot_shifts =====
CREATE TABLE public.ottoq_depot_shifts (
    shift_id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    shift_name text NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    days_of_week integer[] NOT NULL DEFAULT ARRAY[1, 2, 3, 4, 5, 6, 7],
    min_techs integer NOT NULL DEFAULT 1,
    notes text,
    status text NOT NULL DEFAULT 'active'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_depot_shifts ADD CONSTRAINT ottoq_depot_shifts_pkey PRIMARY KEY (shift_id);
ALTER TABLE public.ottoq_depot_shifts ADD CONSTRAINT ottoq_depot_shifts_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_depot_shifts ADD CONSTRAINT ottoq_depot_shifts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'draft'::text, 'archived'::text])));
CREATE INDEX idx_depot_shifts_active ON public.ottoq_depot_shifts USING btree (depot_id) WHERE (status = 'active'::text);

-- ===== ottoq_depot_staffing =====
CREATE TABLE public.ottoq_depot_staffing (
    depot_id uuid NOT NULL,
    role text NOT NULL,
    headcount integer NOT NULL,
    notes text,
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_depot_staffing ADD CONSTRAINT ottoq_depot_staffing_pkey PRIMARY KEY (depot_id, role);
ALTER TABLE public.ottoq_depot_staffing ADD CONSTRAINT ottoq_depot_staffing_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_depot_staffing ADD CONSTRAINT ottoq_depot_staffing_headcount_check CHECK ((headcount >= 0));
ALTER TABLE public.ottoq_depot_staffing ADD CONSTRAINT ottoq_depot_staffing_role_check CHECK ((role = ANY (ARRAY['general_tech'::text, 'wash_supervisor'::text, 'service_tech'::text])));

-- ===== ottoq_depot_tariffs =====
CREATE TABLE public.ottoq_depot_tariffs (
    tariff_row_id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    schedule_code text NOT NULL,
    utility text NOT NULL,
    season text NOT NULL,
    season_months integer[] NOT NULL,
    demand_first_block_usd_kw numeric NOT NULL,
    demand_excess_usd_kw numeric NOT NULL,
    block_kw numeric NOT NULL DEFAULT 1000,
    fixed_monthly_usd numeric,
    energy_base_cents_kwh numeric,
    demand_basis text NOT NULL DEFAULT 'NCP_30min'::text,
    effective_from date NOT NULL,
    provenance jsonb NOT NULL,
    active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_depot_tariffs ADD CONSTRAINT ottoq_depot_tariffs_pkey PRIMARY KEY (tariff_row_id);
ALTER TABLE public.ottoq_depot_tariffs ADD CONSTRAINT ottoq_depot_tariffs_season_check CHECK ((season = ANY (ARRAY['summer'::text, 'winter'::text, 'transition'::text])));
CREATE INDEX idx_depot_tariffs_lookup ON public.ottoq_depot_tariffs USING btree (depot_id, season) WHERE active;

-- ===== ottoq_dr_calls =====
CREATE TABLE public.ottoq_dr_calls (
    dr_call_id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    sim_run_id uuid,
    issued_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    duration_minutes numeric,
    required_load_cap_kw numeric NOT NULL,
    reason text,
    program text NOT NULL DEFAULT 'TVA_VOLUNTARY'::text,
    call_status text NOT NULL DEFAULT 'active'::text,
    cleared_at timestamp with time zone,
    compliance_score numeric,
    data_source text NOT NULL DEFAULT 'twin'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_dr_calls ADD CONSTRAINT ottoq_dr_calls_pkey PRIMARY KEY (dr_call_id);
CREATE INDEX idx_dr_calls_active ON public.ottoq_dr_calls USING btree (depot_id, call_status, expires_at);

-- ===== ottoq_dtc_catalog =====
CREATE TABLE public.ottoq_dtc_catalog (
    dtc_code text NOT NULL,
    category text NOT NULL,
    severity text NOT NULL,
    title text NOT NULL,
    description text,
    introduced_in text
);
ALTER TABLE public.ottoq_dtc_catalog ADD CONSTRAINT ottoq_dtc_catalog_pkey PRIMARY KEY (dtc_code);
ALTER TABLE public.ottoq_dtc_catalog ADD CONSTRAINT ottoq_dtc_catalog_category_check CHECK ((category = ANY (ARRAY['perception'::text, 'planning'::text, 'hardware'::text, 'software'::text, 'weather_road'::text, 'operator'::text, 'powertrain'::text, 'sensor'::text])));
ALTER TABLE public.ottoq_dtc_catalog ADD CONSTRAINT ottoq_dtc_catalog_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'minor'::text, 'moderate'::text, 'major'::text, 'safety_critical'::text])));

-- ===== ottoq_emergency_invocations =====
CREATE TABLE public.ottoq_emergency_invocations (
    invocation_id uuid NOT NULL DEFAULT gen_random_uuid(),
    invocation_seq bigint NOT NULL DEFAULT nextval('ottoq_emergency_invocations_invocation_seq_seq'::regclass),
    protocol_code text NOT NULL,
    triggered_at timestamp with time zone NOT NULL DEFAULT now(),
    cleared_at timestamp with time zone,
    triggered_by_actor_type text NOT NULL,
    triggered_by_actor_id text,
    triggered_by_event_id uuid,
    source_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    depot_id uuid,
    affects_scope text,
    cascade_executed jsonb NOT NULL DEFAULT '[]'::jsonb,
    outcome text NOT NULL DEFAULT 'in_progress'::text,
    failure_payload jsonb,
    cleared_by_actor_type text,
    cleared_by_actor_id text,
    resolution_note text,
    linked_event_id uuid,
    correlation_id uuid
);
ALTER TABLE public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_invocation_seq_key UNIQUE (invocation_seq);
ALTER TABLE public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_pkey PRIMARY KEY (invocation_id);
ALTER TABLE public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_linked_event_id_fkey FOREIGN KEY (linked_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_triggered_by_event_id_fkey FOREIGN KEY (triggered_by_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_outcome_check CHECK ((outcome = ANY (ARRAY['in_progress'::text, 'completed'::text, 'partial'::text, 'failed'::text, 'cleared'::text])));
CREATE INDEX idx_em_inv_active ON public.ottoq_emergency_invocations USING btree (depot_id, triggered_at DESC) WHERE (cleared_at IS NULL);
CREATE INDEX idx_em_inv_correlation ON public.ottoq_emergency_invocations USING btree (correlation_id);
CREATE INDEX idx_em_inv_protocol_time ON public.ottoq_emergency_invocations USING btree (protocol_code, triggered_at DESC);
CREATE INDEX idx_emerg_inv_linked_event ON public.ottoq_emergency_invocations USING btree (linked_event_id);
CREATE INDEX idx_emerg_inv_trig_event ON public.ottoq_emergency_invocations USING btree (triggered_by_event_id);

-- ===== ottoq_emergency_protocols =====
CREATE TABLE public.ottoq_emergency_protocols (
    protocol_id uuid NOT NULL DEFAULT gen_random_uuid(),
    protocol_code text NOT NULL,
    category text NOT NULL,
    severity text NOT NULL DEFAULT 'safety_critical'::text,
    title text NOT NULL,
    description text NOT NULL,
    rationale text,
    external_references jsonb DEFAULT '{}'::jsonb,
    trigger_event_types text[] NOT NULL DEFAULT '{}'::text[],
    cascade_actions jsonb NOT NULL DEFAULT '[]'::jsonb,
    affects_scope text NOT NULL DEFAULT 'depot'::text,
    requires_manual_clear boolean NOT NULL DEFAULT true,
    auto_clear_after_seconds integer,
    notify_actors text[] NOT NULL DEFAULT ARRAY['depot_supervisor'::text, 'command_center_operator'::text, 'fleet_operator_admin'::text, 'oem_dispatch_webhook'::text],
    external_notify_webhooks text[],
    status text NOT NULL DEFAULT 'active'::text,
    introduced_in text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_pkey PRIMARY KEY (protocol_id);
ALTER TABLE public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_protocol_code_key UNIQUE (protocol_code);
ALTER TABLE public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_affects_scope_check CHECK ((affects_scope = ANY (ARRAY['depot'::text, 'region'::text, 'system'::text, 'single_stall'::text, 'single_vehicle'::text])));
ALTER TABLE public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_category_check CHECK ((category = ANY (ARRAY['fire'::text, 'grid'::text, 'security'::text, 'weather'::text, 'connectivity'::text, 'sensor_failure'::text, 'manual_killswitch'::text, 'hazmat'::text, 'medical'::text, 'tornado'::text, 'flood'::text, 'earthquake'::text, 'other'::text])));
ALTER TABLE public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_severity_check CHECK ((severity = ANY (ARRAY['warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
ALTER TABLE public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_status_check CHECK ((status = ANY (ARRAY['active'::text, 'deprecated'::text, 'draft'::text])));
CREATE INDEX idx_emergency_protocols_active ON public.ottoq_emergency_protocols USING btree (status, category);

-- ===== ottoq_energy_commands =====
CREATE TABLE public.ottoq_energy_commands (
    command_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid,
    depot_id uuid NOT NULL,
    tick_seq bigint,
    issued_at timestamp with time zone NOT NULL,
    source text NOT NULL DEFAULT 'otto_q'::text,
    command_type text NOT NULL,
    setpoint_kw numeric,
    horizon_min numeric DEFAULT 15,
    reason jsonb,
    status text NOT NULL DEFAULT 'pending'::text,
    executed_at timestamp with time zone,
    executed_note text,
    data_source text NOT NULL DEFAULT 'twin'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_energy_commands ADD CONSTRAINT ottoq_energy_commands_pkey PRIMARY KEY (command_id);
ALTER TABLE public.ottoq_energy_commands ADD CONSTRAINT ottoq_energy_commands_command_type_check CHECK ((command_type = ANY (ARRAY['charge_cap_kw'::text, 'bess_setpoint_kw'::text, 'load_shed'::text, 'tou_shift'::text, 'clear'::text])));
ALTER TABLE public.ottoq_energy_commands ADD CONSTRAINT ottoq_energy_commands_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'executed'::text, 'superseded'::text, 'failed'::text])));
CREATE INDEX idx_ottoq_energy_cmd_active ON public.ottoq_energy_commands USING btree (sim_run_id, depot_id, command_type, issued_at DESC);
CREATE INDEX idx_ottoq_energy_cmd_pending ON public.ottoq_energy_commands USING btree (depot_id, status) WHERE (status = 'pending'::text);

-- ===== ottoq_energy_plan =====
CREATE TABLE public.ottoq_energy_plan (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    plan_start_clock timestamp with time zone NOT NULL,
    tick_minutes numeric NOT NULL,
    horizon_steps integer NOT NULL,
    bess_setpoint_kw numeric[] NOT NULL,
    grid_import_kw numeric[],
    forecast_load_kw numeric[],
    predicted_peak_kw numeric,
    solver text,
    status text,
    source text NOT NULL DEFAULT 'mpc'::text,
    request_id bigint,
    latency_ms integer,
    plan_state text NOT NULL DEFAULT 'pending'::text
);
ALTER TABLE public.ottoq_energy_plan ADD CONSTRAINT ottoq_energy_plan_pkey PRIMARY KEY (id);
CREATE INDEX ottoq_energy_plan_lookup ON public.ottoq_energy_plan USING btree (sim_run_id, depot_id, created_at DESC);

-- ===== ottoq_event_types_catalog =====
CREATE TABLE public.ottoq_event_types_catalog (
    event_type text NOT NULL,
    category text NOT NULL,
    description text NOT NULL,
    payload_schema jsonb,
    emitter text,
    default_severity text NOT NULL DEFAULT 'info'::text,
    introduced_in text,
    deprecated boolean NOT NULL DEFAULT false,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_event_types_catalog ADD CONSTRAINT ottoq_event_types_catalog_pkey PRIMARY KEY (event_type);
ALTER TABLE public.ottoq_event_types_catalog ADD CONSTRAINT ottoq_event_types_catalog_category_check CHECK ((category = ANY (ARRAY['state_change'::text, 'rule_evaluation'::text, 'prediction'::text, 'action'::text, 'audit'::text, 'safety_event'::text, 'business_event'::text, 'system_event'::text, 'integration_event'::text])));
ALTER TABLE public.ottoq_event_types_catalog ADD CONSTRAINT ottoq_event_types_catalog_default_severity_check CHECK ((default_severity = ANY (ARRAY['debug'::text, 'info'::text, 'warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));

-- ===== ottoq_events =====
CREATE TABLE public.ottoq_events (
    event_id uuid NOT NULL DEFAULT gen_random_uuid(),
    event_seq bigint NOT NULL DEFAULT nextval('ottoq_events_event_seq_seq'::regclass),
    occurred_at timestamp with time zone NOT NULL DEFAULT now(),
    recorded_at timestamp with time zone NOT NULL DEFAULT now(),
    actor_type text NOT NULL,
    actor_id text,
    actor_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    event_type text NOT NULL,
    event_category text NOT NULL,
    severity text NOT NULL DEFAULT 'info'::text,
    entity_type text NOT NULL,
    entity_id uuid,
    fleet_operator_id uuid,
    depot_id uuid,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    previous_state jsonb,
    new_state jsonb,
    correlation_id uuid NOT NULL DEFAULT gen_random_uuid(),
    parent_event_id uuid,
    causation_chain uuid[] NOT NULL DEFAULT '{}'::uuid[],
    related_task_id uuid,
    related_schedule_id uuid,
    related_decision_id uuid,
    payload_hash text NOT NULL,
    signature text,
    signature_key_id text,
    signature_algorithm text NOT NULL DEFAULT 'HMAC-SHA-256'::text,
    outcome text,
    outcome_recorded_at timestamp with time zone,
    latency_ms integer,
    ingest_source text DEFAULT 'app'::text,
    schema_version text NOT NULL DEFAULT '1.0.0'::text,
    data_source text NOT NULL DEFAULT 'production'::text,
    sim_run_id uuid
);
ALTER TABLE public.ottoq_events ADD CONSTRAINT ottoq_events_keep_event_seq_key UNIQUE (event_seq);
ALTER TABLE public.ottoq_events ADD CONSTRAINT ottoq_events_keep_pkey PRIMARY KEY (event_id);
ALTER TABLE public.ottoq_events ADD CONSTRAINT ottoq_events_parent_event_id_fkey FOREIGN KEY (parent_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_events ADD CONSTRAINT event_id_in_chain_consistency CHECK (((parent_event_id IS NULL) OR (cardinality(causation_chain) = 0) OR (causation_chain[cardinality(causation_chain)] = parent_event_id)));
ALTER TABLE public.ottoq_events ADD CONSTRAINT no_future_events CHECK ((occurred_at <= (recorded_at + '00:01:00'::interval)));
ALTER TABLE public.ottoq_events ADD CONSTRAINT ottoq_events_actor_type_check CHECK ((actor_type = ANY (ARRAY['fleet_operator_admin'::text, 'fleet_operator_viewer'::text, 'oem_dispatch_webhook'::text, 'oem_admin_console'::text, 'depot_tech'::text, 'depot_supervisor'::text, 'command_center_operator'::text, 'ottoq_engine'::text, 'ottow_driver'::text, 'ottow_dispatcher'::text, 'otto_response_agent'::text, 'system_scheduler'::text, 'external_sensor'::text, 'ocpp_charger'::text, 'av_vehicle'::text, 'bess_controller'::text, 'solar_controller'::text, 'migration_script'::text, 'system'::text, 'unknown'::text])));
ALTER TABLE public.ottoq_events ADD CONSTRAINT ottoq_events_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text, 'replay'::text, 'shadow'::text])));
ALTER TABLE public.ottoq_events ADD CONSTRAINT ottoq_events_outcome_check CHECK ((outcome = ANY (ARRAY['pending'::text, 'in_progress'::text, 'succeeded'::text, 'failed'::text, 'rolled_back'::text, 'partial'::text, 'timed_out'::text])));
ALTER TABLE public.ottoq_events ADD CONSTRAINT ottoq_events_severity_check CHECK ((severity = ANY (ARRAY['debug'::text, 'info'::text, 'warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
CREATE INDEX ottoq_events_keep_correlation_id_idx ON public.ottoq_events USING btree (correlation_id);
CREATE INDEX ottoq_events_keep_depot_id_occurred_at_idx ON public.ottoq_events USING btree (depot_id, occurred_at DESC) WHERE (depot_id IS NOT NULL);
CREATE INDEX ottoq_events_keep_entity_type_entity_id_occurred_at_idx ON public.ottoq_events USING btree (entity_type, entity_id, occurred_at DESC);
CREATE INDEX ottoq_events_keep_event_type_occurred_at_idx ON public.ottoq_events USING btree (event_type, occurred_at DESC);
CREATE INDEX ottoq_events_keep_occurred_at_idx ON public.ottoq_events USING btree (occurred_at DESC) WHERE (severity = ANY (ARRAY['critical'::text, 'safety_critical'::text]));
CREATE INDEX ottoq_events_keep_occurred_at_idx1 ON public.ottoq_events USING brin (occurred_at);
CREATE INDEX ottoq_events_keep_parent_event_id_idx ON public.ottoq_events USING btree (parent_event_id) WHERE (parent_event_id IS NOT NULL);
CREATE INDEX ottoq_events_keep_sim_run_id_idx ON public.ottoq_events USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);

-- ===== ottoq_external_proposals =====
CREATE TABLE public.ottoq_external_proposals (
    proposal_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid NOT NULL,
    depot_id uuid,
    action_context text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    proposal jsonb NOT NULL,
    source text NOT NULL DEFAULT 'external'::text,
    status text NOT NULL DEFAULT 'pending'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    expires_at timestamp with time zone
);
ALTER TABLE public.ottoq_external_proposals ADD CONSTRAINT ottoq_external_proposals_pkey PRIMARY KEY (proposal_id);
CREATE INDEX ottoq_extprop_lookup_idx ON public.ottoq_external_proposals USING btree (sim_run_id, action_context, entity_type, entity_id, status);

-- ===== ottoq_feature_values =====
CREATE TABLE public.ottoq_feature_values (
    value_id uuid NOT NULL DEFAULT gen_random_uuid(),
    value_seq bigint NOT NULL DEFAULT nextval('ottoq_feature_values_value_seq_seq'::regclass),
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
    valid_from timestamp with time zone NOT NULL DEFAULT now(),
    valid_until timestamp with time zone,
    observation_time timestamp with time zone NOT NULL DEFAULT now(),
    source text,
    source_event_id uuid,
    computed_by text,
    feature_version integer NOT NULL DEFAULT 1,
    quality_score numeric,
    is_imputed boolean NOT NULL DEFAULT false,
    is_outlier boolean NOT NULL DEFAULT false,
    fleet_operator_id uuid,
    depot_id uuid,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_feature_values ADD CONSTRAINT ottoq_feature_values_pkey PRIMARY KEY (value_id);
ALTER TABLE public.ottoq_feature_values ADD CONSTRAINT ottoq_feature_values_value_seq_key UNIQUE (value_seq);
ALTER TABLE public.ottoq_feature_values ADD CONSTRAINT ottoq_feature_values_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_feature_values ADD CONSTRAINT ottoq_feature_values_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_feature_values ADD CONSTRAINT ottoq_feature_values_source_event_id_fkey FOREIGN KEY (source_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
CREATE INDEX idx_feature_values_src_event ON public.ottoq_feature_values USING btree (source_event_id);
CREATE INDEX idx_fv_active ON public.ottoq_feature_values USING btree (feature_name, entity_id) WHERE (valid_until IS NULL);
CREATE INDEX idx_fv_entity_feature_time ON public.ottoq_feature_values USING btree (entity_type, entity_id, feature_name, valid_from DESC);
CREATE INDEX idx_fv_feature_time ON public.ottoq_feature_values USING btree (feature_name, valid_from DESC);
CREATE INDEX idx_fv_observation_brin ON public.ottoq_feature_values USING brin (observation_time);

-- ===== ottoq_features =====
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
    is_realtime boolean NOT NULL DEFAULT false,
    refresh_frequency text,
    freshness_sla_seconds integer NOT NULL DEFAULT 300,
    depends_on_features text[] NOT NULL DEFAULT '{}'::text[],
    depends_on_tables text[] NOT NULL DEFAULT '{}'::text[],
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
    version integer NOT NULL DEFAULT 1,
    status text NOT NULL DEFAULT 'active'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_features ADD CONSTRAINT ottoq_features_pkey PRIMARY KEY (feature_name);
ALTER TABLE public.ottoq_features ADD CONSTRAINT ottoq_features_category_check CHECK ((category = ANY (ARRAY['vehicle'::text, 'stall'::text, 'depot'::text, 'task'::text, 'schedule'::text, 'fleet'::text, 'external'::text, 'calendar'::text, 'derived'::text, 'synthetic'::text])));
ALTER TABLE public.ottoq_features ADD CONSTRAINT ottoq_features_data_type_check CHECK ((data_type = ANY (ARRAY['numeric'::text, 'integer'::text, 'boolean'::text, 'text'::text, 'timestamp'::text, 'json'::text, 'array'::text, 'enum'::text])));
ALTER TABLE public.ottoq_features ADD CONSTRAINT ottoq_features_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'deprecated'::text, 'archived'::text])));
CREATE INDEX idx_features_category ON public.ottoq_features USING btree (category, status);
CREATE INDEX idx_features_realtime ON public.ottoq_features USING btree (is_realtime, status);

-- ===== ottoq_feed_activations =====
CREATE TABLE public.ottoq_feed_activations (
    activation_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid NOT NULL,
    var_key text NOT NULL,
    plan_id uuid NOT NULL,
    agent_model text NOT NULL DEFAULT 'fallback'::text,
    agent_notes text,
    activated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_feed_activations ADD CONSTRAINT ottoq_feed_activations_pkey PRIMARY KEY (activation_id);
ALTER TABLE public.ottoq_feed_activations ADD CONSTRAINT ottoq_feed_activations_sim_run_id_var_key_key UNIQUE (sim_run_id, var_key);
ALTER TABLE public.ottoq_feed_activations ADD CONSTRAINT ottoq_feed_activations_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES ottoq_feed_plans(plan_id);

-- ===== ottoq_feed_plans =====
CREATE TABLE public.ottoq_feed_plans (
    plan_id uuid NOT NULL DEFAULT gen_random_uuid(),
    var_key text NOT NULL,
    version integer NOT NULL,
    status text NOT NULL DEFAULT 'active'::text,
    method text NOT NULL,
    plan jsonb NOT NULL,
    provenance jsonb NOT NULL,
    authored_by text NOT NULL,
    rationale text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_feed_plans ADD CONSTRAINT ottoq_feed_plans_pkey PRIMARY KEY (plan_id);
ALTER TABLE public.ottoq_feed_plans ADD CONSTRAINT ottoq_feed_plans_var_key_version_key UNIQUE (var_key, version);
ALTER TABLE public.ottoq_feed_plans ADD CONSTRAINT ottoq_feed_plans_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'superseded'::text])));
CREATE INDEX idx_feed_plans_active ON public.ottoq_feed_plans USING btree (var_key) WHERE (status = 'active'::text);

-- ===== ottoq_fleet_operator_slas =====
CREATE TABLE public.ottoq_fleet_operator_slas (
    sla_id uuid NOT NULL DEFAULT gen_random_uuid(),
    fleet_operator_id uuid NOT NULL,
    contract_reference text,
    effective_from timestamp with time zone NOT NULL DEFAULT now(),
    effective_until timestamp with time zone,
    status text NOT NULL DEFAULT 'active'::text,
    version integer NOT NULL DEFAULT 1,
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
    required_services_before_deploy text[] DEFAULT '{}'::text[],
    blocked_services text[] DEFAULT '{}'::text[],
    oem_acceptance_required boolean NOT NULL DEFAULT true,
    oem_acceptance_timeout_seconds integer DEFAULT 180,
    oem_acceptance_on_timeout text DEFAULT 'auto_accept'::text,
    oem_webhook_callback_url text,
    oem_acceptance_mode text DEFAULT 'oem_webhook_final_only'::text,
    maintenance_window_start time without time zone,
    maintenance_window_end time without time zone,
    allow_maintenance_during_peak boolean NOT NULL DEFAULT false,
    reporting_email text,
    reporting_webhook text,
    reporting_frequency text DEFAULT 'per_visit'::text,
    reports_must_be_signed boolean NOT NULL DEFAULT true,
    audit_retention_days integer DEFAULT 2555,
    pii_redaction_required boolean NOT NULL DEFAULT false,
    penalty_schedule jsonb DEFAULT '{}'::jsonb,
    notes text,
    signed_by_oem text,
    signed_by_depot text,
    signed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    return_reserve_soc_pct numeric
);
ALTER TABLE public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_fleet_operator_id_version_key UNIQUE (fleet_operator_id, version);
ALTER TABLE public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_pkey PRIMARY KEY (sla_id);
ALTER TABLE public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_oem_acceptance_mode_check CHECK ((oem_acceptance_mode = ANY (ARRAY['auto'::text, 'tech_confirm_only'::text, 'oem_webhook_final_only'::text, 'oem_webhook_required'::text])));
ALTER TABLE public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_oem_acceptance_on_timeout_check CHECK ((oem_acceptance_on_timeout = ANY (ARRAY['auto_accept'::text, 'auto_reject'::text, 'hold_for_manual'::text])));
ALTER TABLE public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_reporting_frequency_check CHECK ((reporting_frequency = ANY (ARRAY['per_visit'::text, 'daily'::text, 'weekly'::text, 'monthly'::text, 'on_demand'::text])));
ALTER TABLE public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'expired'::text, 'suspended'::text, 'archived'::text])));
CREATE INDEX idx_fleet_slas_active ON public.ottoq_fleet_operator_slas USING btree (fleet_operator_id, status, effective_from, effective_until);

-- ===== ottoq_fn_definition_backups =====
CREATE TABLE public.ottoq_fn_definition_backups (
    backup_id bigint NOT NULL DEFAULT nextval('ottoq_fn_definition_backups_backup_id_seq'::regclass),
    captured_at timestamp with time zone NOT NULL DEFAULT now(),
    reason text NOT NULL,
    fn_signature text NOT NULL,
    fn_definition text NOT NULL,
    def_md5 text NOT NULL
);
ALTER TABLE public.ottoq_fn_definition_backups ADD CONSTRAINT ottoq_fn_definition_backups_pkey PRIMARY KEY (backup_id);
CREATE INDEX ottoq_fn_definition_backups_sig_idx ON public.ottoq_fn_definition_backups USING btree (fn_signature, captured_at DESC);

-- ===== ottoq_grid_events =====
CREATE TABLE public.ottoq_grid_events (
    grid_event_id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid,
    event_type text NOT NULL,
    severity text NOT NULL,
    effective_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone,
    source text,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    cleared_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_grid_events ADD CONSTRAINT ottoq_grid_events_pkey PRIMARY KEY (grid_event_id);
ALTER TABLE public.ottoq_grid_events ADD CONSTRAINT ottoq_grid_events_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_grid_events ADD CONSTRAINT ottoq_grid_events_event_type_check CHECK ((event_type = ANY (ARRAY['demand_response_called'::text, 'demand_response_released'::text, 'brownout'::text, 'overvoltage'::text, 'undervoltage'::text, 'frequency_high'::text, 'frequency_low'::text, 'grid_trip'::text, 'grid_restored'::text, 'tariff_window_change'::text, 'curtailment_request'::text])));
ALTER TABLE public.ottoq_grid_events ADD CONSTRAINT ottoq_grid_events_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
CREATE INDEX idx_grid_events_active ON public.ottoq_grid_events USING btree (depot_id, event_type) WHERE (cleared_at IS NULL);
CREATE INDEX idx_grid_events_depot_time ON public.ottoq_grid_events USING btree (depot_id, effective_at DESC);

-- ===== ottoq_grid_snapshots =====
CREATE TABLE public.ottoq_grid_snapshots (
    snapshot_id uuid NOT NULL DEFAULT gen_random_uuid(),
    snapshot_seq bigint NOT NULL DEFAULT nextval('ottoq_grid_snapshots_snapshot_seq_seq'::regclass),
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
    voltage_status text NOT NULL DEFAULT 'nominal'::text,
    frequency_status text NOT NULL DEFAULT 'nominal'::text,
    lmp_usd_per_mwh numeric,
    current_tariff_label text,
    current_rate_usd_per_kwh numeric,
    active_dr_call_id uuid,
    dr_required_load_cap_kw numeric,
    data_source text NOT NULL DEFAULT 'twin'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_grid_snapshots ADD CONSTRAINT ottoq_grid_snapshots_pkey PRIMARY KEY (snapshot_id);
CREATE INDEX idx_grid_snap_depot ON public.ottoq_grid_snapshots USING btree (depot_id, sim_clock_at DESC);
CREATE INDEX idx_grid_snap_run ON public.ottoq_grid_snapshots USING btree (sim_run_id, sim_clock_at DESC);

-- ===== ottoq_incident_reports =====
CREATE TABLE public.ottoq_incident_reports (
    incident_report_id uuid NOT NULL DEFAULT gen_random_uuid(),
    incident_report_seq bigint NOT NULL DEFAULT nextval('ottoq_incident_reports_incident_report_seq_seq'::regclass),
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
    timeline jsonb NOT NULL DEFAULT '[]'::jsonb,
    event_ids_in_timeline uuid[] NOT NULL DEFAULT '{}'::uuid[],
    rule_failures_in_window jsonb NOT NULL DEFAULT '[]'::jsonb,
    predictions_in_window jsonb NOT NULL DEFAULT '[]'::jsonb,
    recommendations_in_window jsonb NOT NULL DEFAULT '[]'::jsonb,
    root_cause_summary text,
    contributing_factors jsonb DEFAULT '[]'::jsonb,
    systems_involved text[] DEFAULT '{}'::text[],
    actor_decisions jsonb DEFAULT '[]'::jsonb,
    recommendation_outcomes jsonb DEFAULT '[]'::jsonb,
    duration_seconds integer,
    events_in_window integer NOT NULL DEFAULT 0,
    rule_failures_count integer NOT NULL DEFAULT 0,
    anomaly_count integer NOT NULL DEFAULT 0,
    override_count integer NOT NULL DEFAULT 0,
    vehicles_affected integer NOT NULL DEFAULT 0,
    stalls_affected integer NOT NULL DEFAULT 0,
    generated_at timestamp with time zone NOT NULL DEFAULT now(),
    generated_by_actor_type text,
    generated_by_actor_id text,
    status text NOT NULL DEFAULT 'auto_generated'::text,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    review_notes text,
    audit_report_id uuid,
    audit_bundle_id uuid,
    payload jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_incident_report_seq_key UNIQUE (incident_report_seq);
ALTER TABLE public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_pkey PRIMARY KEY (incident_report_id);
ALTER TABLE public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_audit_bundle_id_fkey FOREIGN KEY (audit_bundle_id) REFERENCES ottoq_audit_bundles(bundle_id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_audit_report_id_fkey FOREIGN KEY (audit_report_id) REFERENCES ottoq_audit_reports(report_id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_triggering_event_id_fkey FOREIGN KEY (triggering_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_incident_type_check CHECK ((incident_type = ANY (ARRAY['emergency_cascade'::text, 'safety_event'::text, 'oem_rejection'::text, 'sustained_rule_failure'::text, 'sensor_blackout'::text, 'energy_overrun'::text, 'sla_critical_breach'::text, 'anomaly_critical'::text, 'manual_report'::text, 'other'::text])));
ALTER TABLE public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_status_check CHECK ((status = ANY (ARRAY['auto_generated'::text, 'under_review'::text, 'reviewed'::text, 'closed'::text, 'reopened'::text])));
CREATE INDEX idx_incident_rep_trig_event ON public.ottoq_incident_reports USING btree (triggering_event_id);
CREATE INDEX idx_incident_reports_correlation ON public.ottoq_incident_reports USING btree (source_correlation_id);
CREATE INDEX idx_incident_reports_depot_time ON public.ottoq_incident_reports USING btree (depot_id, triggered_at DESC) WHERE (depot_id IS NOT NULL);
CREATE INDEX idx_incident_reports_tenant_time ON public.ottoq_incident_reports USING btree (fleet_operator_id, triggered_at DESC) WHERE (fleet_operator_id IS NOT NULL);
CREATE INDEX idx_incident_reports_type ON public.ottoq_incident_reports USING btree (incident_type, triggered_at DESC);

-- ===== ottoq_inference_log =====
CREATE TABLE public.ottoq_inference_log (
    inference_id uuid NOT NULL DEFAULT gen_random_uuid(),
    inference_seq bigint NOT NULL DEFAULT nextval('ottoq_inference_log_inference_seq_seq'::regclass),
    requested_at timestamp with time zone NOT NULL DEFAULT now(),
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
    context jsonb DEFAULT '{}'::jsonb,
    predicted_value jsonb,
    p10 numeric,
    p50 numeric,
    p90 numeric,
    confidence numeric,
    prediction_id uuid,
    uncertainty_method text,
    ab_test_id uuid,
    ab_test_variant text,
    is_shadow boolean NOT NULL DEFAULT false,
    shadow_compared_to uuid,
    shadow_disagreement numeric,
    status text NOT NULL DEFAULT 'completed'::text,
    error_message text,
    error_code text,
    correlation_id uuid,
    parent_event_id uuid,
    event_id uuid,
    cost_estimate_cents numeric,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_inference_log ADD CONSTRAINT ottoq_inference_log_inference_seq_key UNIQUE (inference_seq);
ALTER TABLE public.ottoq_inference_log ADD CONSTRAINT ottoq_inference_log_pkey PRIMARY KEY (inference_id);
ALTER TABLE public.ottoq_inference_log ADD CONSTRAINT ottoq_inference_log_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES model_versions(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_inference_log ADD CONSTRAINT ottoq_inference_log_route_id_fkey FOREIGN KEY (route_id) REFERENCES ottoq_model_routes(route_id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_inference_log ADD CONSTRAINT ottoq_inference_log_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'failed'::text, 'timed_out'::text, 'cancelled'::text])));
CREATE INDEX idx_inference_log_correlation ON public.ottoq_inference_log USING btree (correlation_id);
CREATE INDEX idx_inference_log_failed ON public.ottoq_inference_log USING btree (status, requested_at DESC) WHERE (status = ANY (ARRAY['failed'::text, 'timed_out'::text]));
CREATE INDEX idx_inference_log_inputs_hash ON public.ottoq_inference_log USING btree (inputs_hash) WHERE (inputs_hash IS NOT NULL);
CREATE INDEX idx_inference_log_model ON public.ottoq_inference_log USING btree (model_version_id, requested_at DESC) WHERE (model_version_id IS NOT NULL);
CREATE INDEX idx_inference_log_seq_brin ON public.ottoq_inference_log USING brin (inference_seq);
CREATE INDEX idx_inference_log_shadow ON public.ottoq_inference_log USING btree (is_shadow, requested_at DESC) WHERE (is_shadow = true);
CREATE INDEX idx_inference_log_tenant ON public.ottoq_inference_log USING btree (fleet_operator_id, requested_at DESC) WHERE (fleet_operator_id IS NOT NULL);
CREATE INDEX idx_inference_log_type_time ON public.ottoq_inference_log USING btree (prediction_type, requested_at DESC);

-- ===== ottoq_itinerary_legs =====
CREATE TABLE public.ottoq_itinerary_legs (
    leg_id uuid NOT NULL DEFAULT gen_random_uuid(),
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
    duration_basis jsonb NOT NULL DEFAULT '{}'::jsonb,
    actual_start_sim timestamp with time zone,
    actual_end_sim timestamp with time zone,
    status text NOT NULL DEFAULT 'planned'::text,
    deviation_s integer,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_itinerary_legs ADD CONSTRAINT ottoq_itinerary_legs_itinerary_id_seq_key UNIQUE (itinerary_id, seq);
ALTER TABLE public.ottoq_itinerary_legs ADD CONSTRAINT ottoq_itinerary_legs_pkey PRIMARY KEY (leg_id);
ALTER TABLE public.ottoq_itinerary_legs ADD CONSTRAINT ottoq_itinerary_legs_itinerary_id_fkey FOREIGN KEY (itinerary_id) REFERENCES ottoq_vehicle_itineraries(itinerary_id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_itinerary_legs ADD CONSTRAINT ottoq_itinerary_legs_leg_type_check CHECK ((leg_type = ANY (ARRAY['arrive'::text, 'taxi'::text, 'charge_dcfc'::text, 'charge_l2'::text, 'wash'::text, 'detail'::text, 'service'::text, 'inspect'::text, 'settle'::text, 'stage'::text, 'depart'::text, 'interior_tidy'::text, 'sensor_clean'::text, 'item_retrieval'::text, 'interior_deep_clean'::text, 'software_update'::text, 'remote_diagnostics'::text, 'triage_check'::text, 'sensor_calibration'::text, 'mechanical_pm'::text, 'fault_repair'::text, 'cosmetic_repair'::text])));
ALTER TABLE public.ottoq_itinerary_legs ADD CONSTRAINT ottoq_itinerary_legs_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'active'::text, 'done'::text, 'skipped'::text, 'amended'::text])));
CREATE INDEX idx_itin_legs_run_live ON public.ottoq_itinerary_legs USING btree (sim_run_id, status) WHERE (status = ANY (ARRAY['planned'::text, 'active'::text]));
CREATE INDEX idx_itin_legs_vehicle ON public.ottoq_itinerary_legs USING btree (vehicle_id, status);

-- ===== ottoq_model_artifacts =====
CREATE TABLE public.ottoq_model_artifacts (
    artifact_id uuid NOT NULL DEFAULT gen_random_uuid(),
    storage_path text NOT NULL,
    format text NOT NULL,
    size_bytes bigint NOT NULL,
    sha256 text NOT NULL,
    uploaded_at timestamp with time zone NOT NULL DEFAULT now(),
    uploaded_by text,
    description text,
    source_run_id uuid,
    is_active boolean NOT NULL DEFAULT true,
    retired_at timestamp with time zone
);
ALTER TABLE public.ottoq_model_artifacts ADD CONSTRAINT ottoq_model_artifacts_pkey PRIMARY KEY (artifact_id);
ALTER TABLE public.ottoq_model_artifacts ADD CONSTRAINT ottoq_model_artifacts_storage_path_key UNIQUE (storage_path);
ALTER TABLE public.ottoq_model_artifacts ADD CONSTRAINT ottoq_model_artifacts_format_check CHECK ((format = ANY (ARRAY['onnx'::text, 'pmml'::text, 'joblib'::text, 'params_only'::text, 'tflite'::text, 'pickle'::text, 'custom'::text])));
CREATE INDEX idx_model_artifacts_active ON public.ottoq_model_artifacts USING btree (format, uploaded_at DESC) WHERE (is_active = true);

-- ===== ottoq_model_routes =====
CREATE TABLE public.ottoq_model_routes (
    route_id uuid NOT NULL DEFAULT gen_random_uuid(),
    prediction_type text NOT NULL,
    fleet_operator_id uuid,
    depot_id uuid,
    vehicle_class text,
    model_version_id uuid,
    fallback_model_version_id uuid,
    effective_from timestamp with time zone NOT NULL DEFAULT now(),
    effective_until timestamp with time zone,
    priority integer NOT NULL DEFAULT 100,
    traffic_share_pct numeric NOT NULL DEFAULT 100.0,
    shadow_mode boolean NOT NULL DEFAULT false,
    ab_test_id uuid,
    rationale text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by text
);
ALTER TABLE public.ottoq_model_routes ADD CONSTRAINT ottoq_model_routes_pkey PRIMARY KEY (route_id);
ALTER TABLE public.ottoq_model_routes ADD CONSTRAINT ottoq_model_routes_fallback_model_version_id_fkey FOREIGN KEY (fallback_model_version_id) REFERENCES model_versions(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_model_routes ADD CONSTRAINT ottoq_model_routes_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES model_versions(id) ON DELETE SET NULL;
CREATE INDEX idx_model_routes_scope ON public.ottoq_model_routes USING btree (prediction_type, fleet_operator_id, depot_id, vehicle_class);
CREATE INDEX idx_model_routes_type ON public.ottoq_model_routes USING btree (prediction_type, priority DESC);

-- ===== ottoq_ocpp_chargers =====
CREATE TABLE public.ottoq_ocpp_chargers (
    charger_id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid,
    ocpp_identifier text NOT NULL,
    vendor text,
    model text,
    serial_number text,
    firmware_version text,
    ocpp_protocol_version text DEFAULT '2.0.1'::text,
    station_state text NOT NULL DEFAULT 'Unavailable'::text,
    station_state_changed_at timestamp with time zone NOT NULL DEFAULT now(),
    last_heartbeat_at timestamp with time zone,
    max_kw numeric,
    num_connectors integer NOT NULL DEFAULT 1,
    connector_states jsonb NOT NULL DEFAULT '{}'::jsonb,
    last_fault_code text,
    last_fault_at timestamp with time zone,
    last_fault_payload jsonb,
    installed_at timestamp with time zone,
    decommissioned_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_ocpp_chargers ADD CONSTRAINT ottoq_ocpp_chargers_ocpp_identifier_key UNIQUE (ocpp_identifier);
ALTER TABLE public.ottoq_ocpp_chargers ADD CONSTRAINT ottoq_ocpp_chargers_pkey PRIMARY KEY (charger_id);
ALTER TABLE public.ottoq_ocpp_chargers ADD CONSTRAINT ottoq_ocpp_chargers_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_ocpp_chargers ADD CONSTRAINT ottoq_ocpp_chargers_station_state_check CHECK ((station_state = ANY (ARRAY['Available'::text, 'Occupied'::text, 'Reserved'::text, 'Unavailable'::text, 'Faulted'::text, 'Maintenance'::text])));
CREATE INDEX idx_ottoq_ocpp_chargers_depot ON public.ottoq_ocpp_chargers USING btree (depot_id, station_state);
CREATE INDEX idx_ottoq_ocpp_chargers_state ON public.ottoq_ocpp_chargers USING btree (station_state, station_state_changed_at);

-- ===== ottoq_ocpp_messages =====
CREATE TABLE public.ottoq_ocpp_messages (
    message_id uuid NOT NULL DEFAULT gen_random_uuid(),
    message_seq bigint NOT NULL DEFAULT nextval('ottoq_ocpp_messages_message_seq_seq'::regclass),
    ocpp_session_id uuid,
    charger_id uuid,
    vehicle_id uuid,
    sim_run_id uuid,
    message_at timestamp with time zone NOT NULL DEFAULT now(),
    sim_clock_at timestamp with time zone,
    direction text NOT NULL,
    message_type text NOT NULL,
    ocpp_version text NOT NULL DEFAULT '2.0.1'::text,
    payload jsonb NOT NULL,
    data_source text NOT NULL DEFAULT 'twin'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_message_seq_key UNIQUE (message_seq);
ALTER TABLE public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_pkey PRIMARY KEY (message_id);
ALTER TABLE public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_charger_id_fkey FOREIGN KEY (charger_id) REFERENCES ottoq_ocpp_chargers(charger_id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_ocpp_session_id_fkey FOREIGN KEY (ocpp_session_id) REFERENCES ocpp_sessions(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text, 'replay'::text, 'shadow'::text])));
ALTER TABLE public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_direction_check CHECK ((direction = ANY (ARRAY['cs_to_csms'::text, 'csms_to_cs'::text])));
CREATE INDEX idx_ocpp_msgs_charger ON public.ottoq_ocpp_messages USING btree (charger_id, message_at DESC);
CREATE INDEX idx_ocpp_msgs_seq_brin ON public.ottoq_ocpp_messages USING brin (message_seq);
CREATE INDEX idx_ocpp_msgs_session ON public.ottoq_ocpp_messages USING btree (ocpp_session_id, message_at);
CREATE INDEX idx_ocpp_msgs_sim_run ON public.ottoq_ocpp_messages USING btree (sim_run_id, message_at) WHERE (sim_run_id IS NOT NULL);
CREATE INDEX idx_ocpp_msgs_type ON public.ottoq_ocpp_messages USING btree (message_type, message_at DESC);

-- ===== ottoq_oem_webhook_log =====
CREATE TABLE public.ottoq_oem_webhook_log (
    webhook_id uuid NOT NULL DEFAULT gen_random_uuid(),
    webhook_seq bigint NOT NULL DEFAULT nextval('ottoq_oem_webhook_log_webhook_seq_seq'::regclass),
    sim_run_id uuid,
    vehicle_id uuid,
    fleet_operator_id uuid,
    oem_name text NOT NULL,
    webhook_type text NOT NULL,
    http_method text NOT NULL DEFAULT 'POST'::text,
    endpoint_url text,
    payload jsonb,
    payload_complete boolean NOT NULL DEFAULT true,
    payload_missing_fields text[],
    attempt_num integer NOT NULL DEFAULT 1,
    is_retry boolean NOT NULL DEFAULT false,
    is_duplicate boolean NOT NULL DEFAULT false,
    is_out_of_order boolean NOT NULL DEFAULT false,
    parent_webhook_id uuid,
    latency_ms integer,
    http_status integer,
    response_payload jsonb,
    delivery_status text NOT NULL,
    validation_result text,
    sim_clock_emitted_at timestamp with time zone NOT NULL,
    sim_clock_delivered_at timestamp with time zone,
    real_at timestamp with time zone NOT NULL DEFAULT now(),
    data_source text NOT NULL DEFAULT 'twin'::text,
    delivery_mode text NOT NULL DEFAULT 'simulated'::text,
    http_request_id bigint,
    signature text
);
ALTER TABLE public.ottoq_oem_webhook_log ADD CONSTRAINT ottoq_oem_webhook_log_pkey PRIMARY KEY (webhook_id);
ALTER TABLE public.ottoq_oem_webhook_log ADD CONSTRAINT ottoq_oem_webhook_log_delivery_mode_check CHECK ((delivery_mode = ANY (ARRAY['simulated'::text, 'live'::text])));
ALTER TABLE public.ottoq_oem_webhook_log ADD CONSTRAINT ottoq_oem_webhook_log_delivery_status_check CHECK ((delivery_status = ANY (ARRAY['delivered'::text, 'failed'::text, 'timed_out'::text, 'rate_limited'::text, 'auth_failed'::text, 'server_error'::text, 'dropped'::text, 'sent'::text, 'pending_retry'::text, 'rejected_other'::text])));
CREATE INDEX idx_webhook_log_oem_type ON public.ottoq_oem_webhook_log USING btree (oem_name, webhook_type);
CREATE INDEX idx_webhook_log_sim_run ON public.ottoq_oem_webhook_log USING btree (sim_run_id, sim_clock_emitted_at DESC);
CREATE INDEX idx_webhook_log_status ON public.ottoq_oem_webhook_log USING btree (delivery_status, validation_result);
CREATE INDEX idx_webhook_log_vehicle ON public.ottoq_oem_webhook_log USING btree (vehicle_id, sim_clock_emitted_at DESC);

-- ===== ottoq_oem_webhook_patterns =====
CREATE TABLE public.ottoq_oem_webhook_patterns (
    oem_name text NOT NULL,
    fleet_operator_id uuid,
    webhook_endpoint text NOT NULL,
    payload_schema_version text NOT NULL,
    latency_mean_ms integer NOT NULL,
    latency_p99_ms integer NOT NULL,
    latency_distribution text NOT NULL DEFAULT 'lognormal'::text,
    retry_policy jsonb NOT NULL,
    payload_completeness_pct numeric NOT NULL,
    duplicate_send_pct numeric NOT NULL,
    out_of_order_pct numeric NOT NULL,
    auth_failure_pct numeric NOT NULL,
    rate_limit_pct numeric NOT NULL,
    network_timeout_pct numeric NOT NULL,
    server_error_5xx_pct numeric NOT NULL DEFAULT 0.002,
    required_fields jsonb NOT NULL,
    optional_fields jsonb NOT NULL,
    notes text,
    active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    live_delivery_enabled boolean NOT NULL DEFAULT false,
    live_endpoint_url text,
    signing_secret_ref text
);
ALTER TABLE public.ottoq_oem_webhook_patterns ADD CONSTRAINT ottoq_oem_webhook_patterns_pkey PRIMARY KEY (oem_name);

-- ===== ottoq_ops_approvals =====
CREATE TABLE public.ottoq_ops_approvals (
    approval_id uuid NOT NULL DEFAULT gen_random_uuid(),
    approval_type text NOT NULL,
    vehicle_id uuid NOT NULL,
    visit_id uuid,
    sim_run_id uuid,
    depot_id uuid,
    status text NOT NULL DEFAULT 'pending'::text,
    priority text NOT NULL DEFAULT 'normal'::text,
    payload jsonb,
    requested_at timestamp with time zone NOT NULL,
    decide_after timestamp with time zone,
    expires_at timestamp with time zone,
    decided_at timestamp with time zone,
    decided_by text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_pkey PRIMARY KEY (approval_id);
ALTER TABLE public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
ALTER TABLE public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES ottoq_visit_needs(visit_id);
ALTER TABLE public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_approval_type_check CHECK ((approval_type = ANY (ARRAY['opportunistic_charge'::text, 'tech_greenlight'::text, 'indepot_reassign'::text])));
ALTER TABLE public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_priority_check CHECK ((priority = ANY (ARRAY['normal'::text, 'high'::text])));
ALTER TABLE public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'declined'::text, 'expired'::text])));
CREATE INDEX idx_ops_approvals_pending ON public.ottoq_ops_approvals USING btree (depot_id, status, approval_type);
CREATE INDEX idx_ops_approvals_vehicle ON public.ottoq_ops_approvals USING btree (vehicle_id, created_at DESC);

-- ===== ottoq_policy_param_catalog =====
CREATE TABLE public.ottoq_policy_param_catalog (
    param_key text NOT NULL,
    description text,
    default_value numeric,
    min_value numeric,
    max_value numeric,
    affects text
);
ALTER TABLE public.ottoq_policy_param_catalog ADD CONSTRAINT ottoq_policy_param_catalog_pkey PRIMARY KEY (param_key);

-- ===== ottoq_policy_params =====
CREATE TABLE public.ottoq_policy_params (
    scope_type text NOT NULL,
    scope_id uuid NOT NULL,
    param_key text NOT NULL,
    param_value numeric NOT NULL,
    updated_by text DEFAULT 'system'::text,
    updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.ottoq_policy_params ADD CONSTRAINT ottoq_policy_params_pkey PRIMARY KEY (scope_type, scope_id, param_key);
ALTER TABLE public.ottoq_policy_params ADD CONSTRAINT ottoq_policy_params_scope_type_check CHECK ((scope_type = ANY (ARRAY['global'::text, 'depot'::text, 'run'::text])));

-- ===== ottoq_prediction_accuracy_heatmap =====
CREATE TABLE public.ottoq_prediction_accuracy_heatmap (
    heatmap_id uuid NOT NULL DEFAULT gen_random_uuid(),
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
    computed_at timestamp with time zone NOT NULL DEFAULT now(),
    payload jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_prediction_accuracy_heatmap ADD CONSTRAINT ottoq_prediction_accuracy_hea_prediction_type_depot_id_flee_key UNIQUE (prediction_type, depot_id, fleet_operator_id, vehicle_class, horizon_minutes, hour_of_day, day_of_week, report_date, model_version_id);
ALTER TABLE public.ottoq_prediction_accuracy_heatmap ADD CONSTRAINT ottoq_prediction_accuracy_heatmap_pkey PRIMARY KEY (heatmap_id);
ALTER TABLE public.ottoq_prediction_accuracy_heatmap ADD CONSTRAINT ottoq_prediction_accuracy_heatmap_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_prediction_accuracy_heatmap ADD CONSTRAINT ottoq_prediction_accuracy_heatmap_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
CREATE INDEX idx_pred_accuracy_depot ON public.ottoq_prediction_accuracy_heatmap USING btree (depot_id, prediction_type, report_date DESC) WHERE (depot_id IS NOT NULL);
CREATE INDEX idx_pred_accuracy_model ON public.ottoq_prediction_accuracy_heatmap USING btree (model_version_id, report_date DESC) WHERE (model_version_id IS NOT NULL);
CREATE INDEX idx_pred_accuracy_tenant ON public.ottoq_prediction_accuracy_heatmap USING btree (fleet_operator_id, prediction_type, report_date DESC) WHERE (fleet_operator_id IS NOT NULL);
CREATE INDEX idx_pred_accuracy_type_date ON public.ottoq_prediction_accuracy_heatmap USING btree (prediction_type, report_date DESC);

-- ===== ottoq_prediction_rule_links =====
CREATE TABLE public.ottoq_prediction_rule_links (
    link_id uuid NOT NULL DEFAULT gen_random_uuid(),
    prediction_type text NOT NULL,
    rule_code text NOT NULL,
    relationship text NOT NULL,
    comparison text,
    threshold_source text,
    threshold_param text,
    enabled boolean NOT NULL DEFAULT true,
    rationale text,
    introduced_in text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_prediction_rule_links ADD CONSTRAINT ottoq_prediction_rule_links_pkey PRIMARY KEY (link_id);
ALTER TABLE public.ottoq_prediction_rule_links ADD CONSTRAINT ottoq_prediction_rule_links_prediction_type_rule_code_relat_key UNIQUE (prediction_type, rule_code, relationship);
ALTER TABLE public.ottoq_prediction_rule_links ADD CONSTRAINT ottoq_prediction_rule_links_relationship_check CHECK ((relationship = ANY (ARRAY['predicts_violation'::text, 'predicts_compliance'::text, 'predicts_proximity'::text, 'informs_threshold'::text])));

-- ===== ottoq_prediction_types_catalog =====
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
    supported_horizons_minutes integer[] NOT NULL DEFAULT ARRAY[60],
    default_horizon_minutes integer NOT NULL DEFAULT 60,
    required_features text[] NOT NULL DEFAULT '{}'::text[],
    optional_features text[] NOT NULL DEFAULT '{}'::text[],
    freshness_sla_seconds integer NOT NULL DEFAULT 300,
    latency_p95_ms integer NOT NULL DEFAULT 200,
    status text NOT NULL DEFAULT 'active'::text,
    introduced_in text,
    ml_ready boolean NOT NULL DEFAULT false,
    baseline_method text NOT NULL DEFAULT 'heuristic'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_prediction_types_catalog ADD CONSTRAINT ottoq_prediction_types_catalog_pkey PRIMARY KEY (prediction_type);
ALTER TABLE public.ottoq_prediction_types_catalog ADD CONSTRAINT ottoq_prediction_types_catalog_category_check CHECK ((category = ANY (ARRAY['vehicle'::text, 'stall'::text, 'depot'::text, 'fleet'::text, 'energy'::text, 'anomaly'::text, 'operational'::text, 'quality'::text])));
ALTER TABLE public.ottoq_prediction_types_catalog ADD CONSTRAINT ottoq_prediction_types_catalog_output_kind_check CHECK ((output_kind = ANY (ARRAY['regression'::text, 'classification'::text, 'time_series'::text, 'multi_class'::text, 'anomaly_score'::text, 'distribution'::text])));
ALTER TABLE public.ottoq_prediction_types_catalog ADD CONSTRAINT ottoq_prediction_types_catalog_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'shadow'::text, 'active'::text, 'deprecated'::text, 'archived'::text])));

-- ===== ottoq_predictions =====
CREATE TABLE public.ottoq_predictions (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    vehicle_id uuid,
    prediction_type text NOT NULL,
    title text,
    description text,
    recommendation jsonb,
    confidence numeric(4,3),
    supporting_data jsonb DEFAULT '{}'::jsonb,
    analysis_window_start timestamp with time zone,
    analysis_window_end timestamp with time zone,
    status text NOT NULL DEFAULT 'pending'::text,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    applied_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    expires_at timestamp with time zone,
    time_horizon_hours integer,
    model_version integer DEFAULT 1,
    action_type text,
    action_parameters jsonb DEFAULT '{}'::jsonb,
    execution_status text DEFAULT 'pending'::text,
    executed_at timestamp with time zone,
    executed_by text,
    rollback_data jsonb,
    model_version_id uuid,
    ab_test_id uuid,
    ab_test_variant text,
    feature_snapshot_ids uuid[] DEFAULT '{}'::uuid[],
    fleet_feature_date date,
    fusion_log_id uuid,
    explanation_id uuid,
    data_quality_score numeric(4,3) DEFAULT 1.000,
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
    shadow_only boolean NOT NULL DEFAULT false
);
ALTER TABLE public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_pkey PRIMARY KEY (id);
ALTER TABLE public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_ab_test_id_fkey FOREIGN KEY (ab_test_id) REFERENCES ab_tests(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_explanation_id_fkey FOREIGN KEY (explanation_id) REFERENCES prediction_explanations(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_fusion_log_id_fkey FOREIGN KEY (fusion_log_id) REFERENCES decision_fusion_log(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES model_versions(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
ALTER TABLE public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_ab_test_variant_check CHECK (((ab_test_variant = ANY (ARRAY['A'::text, 'B'::text])) OR (ab_test_variant IS NULL)));
ALTER TABLE public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_execution_status_check CHECK ((execution_status = ANY (ARRAY['pending'::text, 'approved'::text, 'executing'::text, 'executed'::text, 'failed'::text, 'rolled_back'::text, 'expired'::text])));
ALTER TABLE public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'proposed'::text, 'sent_to_user'::text, 'approved'::text, 'executing'::text, 'accepted'::text, 'rejected'::text, 'expired'::text, 'auto_applied'::text, 'completed'::text])));
CREATE INDEX idx_predictions_ab_test ON public.ottoq_predictions USING btree (ab_test_id, ab_test_variant, created_at DESC) WHERE (ab_test_id IS NOT NULL);
CREATE INDEX idx_predictions_actionable ON public.ottoq_predictions USING btree (depot_id, execution_status, action_type) WHERE ((action_type IS NOT NULL) AND (execution_status = ANY (ARRAY['pending'::text, 'approved'::text])));
CREATE INDEX idx_predictions_baseline ON public.ottoq_predictions USING btree (prediction_baseline, prediction_type, created_at DESC);
CREATE INDEX idx_predictions_depot ON public.ottoq_predictions USING btree (depot_id, created_at DESC);
CREATE INDEX idx_predictions_event ON public.ottoq_predictions USING btree (event_id) WHERE (event_id IS NOT NULL);
CREATE INDEX idx_predictions_horizon ON public.ottoq_predictions USING btree (depot_id, time_horizon_hours, created_at DESC) WHERE (time_horizon_hours IS NOT NULL);
CREATE INDEX idx_predictions_inputs_hash ON public.ottoq_predictions USING btree (inputs_hash) WHERE (inputs_hash IS NOT NULL);
CREATE INDEX idx_predictions_model_version ON public.ottoq_predictions USING btree (model_version_id, created_at DESC);
CREATE INDEX idx_predictions_status ON public.ottoq_predictions USING btree (status) WHERE (status = 'pending'::text);
CREATE INDEX idx_predictions_target_at ON public.ottoq_predictions USING btree (target_at);
CREATE INDEX idx_predictions_tenant_time ON public.ottoq_predictions USING btree (fleet_operator_id, created_at DESC) WHERE (fleet_operator_id IS NOT NULL);
CREATE INDEX idx_predictions_vehicle ON public.ottoq_predictions USING btree (vehicle_id, created_at DESC);

-- ===== ottoq_recommendations =====
CREATE TABLE public.ottoq_recommendations (
    recommendation_id uuid NOT NULL DEFAULT gen_random_uuid(),
    recommendation_seq bigint NOT NULL DEFAULT nextval('ottoq_recommendations_recommendation_seq_seq'::regclass),
    emitted_at timestamp with time zone NOT NULL DEFAULT now(),
    prediction_id uuid,
    prediction_type text,
    proposed_action text NOT NULL,
    action_parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    entity_type text NOT NULL,
    entity_id uuid,
    fleet_operator_id uuid,
    depot_id uuid,
    rules_evaluated jsonb DEFAULT '[]'::jsonb,
    rules_blocked_by text[],
    status text NOT NULL DEFAULT 'pending'::text,
    decided_at timestamp with time zone,
    decision_reason text,
    executed_at timestamp with time zone,
    executed_by text,
    execution_event_id uuid,
    execution_outcome text,
    expires_at timestamp with time zone,
    shadow_only boolean NOT NULL DEFAULT false,
    correlation_id uuid,
    parent_event_id uuid,
    recommendation_payload jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_recommendations ADD CONSTRAINT ottoq_recommendations_pkey PRIMARY KEY (recommendation_id);
ALTER TABLE public.ottoq_recommendations ADD CONSTRAINT ottoq_recommendations_recommendation_seq_key UNIQUE (recommendation_seq);
ALTER TABLE public.ottoq_recommendations ADD CONSTRAINT ottoq_recommendations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'validating'::text, 'admitted'::text, 'rejected'::text, 'shadow'::text, 'expired'::text, 'executed'::text, 'rolled_back'::text])));
CREATE INDEX idx_recs_correlation ON public.ottoq_recommendations USING btree (correlation_id);
CREATE INDEX idx_recs_pending ON public.ottoq_recommendations USING btree (emitted_at DESC) WHERE (status = ANY (ARRAY['pending'::text, 'validating'::text, 'shadow'::text]));
CREATE INDEX idx_recs_prediction ON public.ottoq_recommendations USING btree (prediction_id) WHERE (prediction_id IS NOT NULL);
CREATE INDEX idx_recs_status_time ON public.ottoq_recommendations USING btree (status, emitted_at DESC);
CREATE INDEX idx_recs_tenant_time ON public.ottoq_recommendations USING btree (fleet_operator_id, emitted_at DESC) WHERE (fleet_operator_id IS NOT NULL);

-- ===== ottoq_retention_state =====
CREATE TABLE public.ottoq_retention_state (
    table_name text NOT NULL,
    cursor_block bigint NOT NULL DEFAULT 0,
    pass_deleted bigint NOT NULL DEFAULT 0,
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_retention_state ADD CONSTRAINT ottoq_retention_state_pkey PRIMARY KEY (table_name);

-- ===== ottoq_retraining_triggers =====
CREATE TABLE public.ottoq_retraining_triggers (
    trigger_id uuid NOT NULL DEFAULT gen_random_uuid(),
    trigger_code text NOT NULL,
    prediction_type text NOT NULL,
    condition_kind text NOT NULL,
    condition jsonb NOT NULL DEFAULT '{}'::jsonb,
    enabled boolean NOT NULL DEFAULT true,
    description text,
    last_fired_at timestamp with time zone,
    fire_count bigint NOT NULL DEFAULT 0,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_retraining_triggers ADD CONSTRAINT ottoq_retraining_triggers_pkey PRIMARY KEY (trigger_id);
ALTER TABLE public.ottoq_retraining_triggers ADD CONSTRAINT ottoq_retraining_triggers_trigger_code_key UNIQUE (trigger_code);
ALTER TABLE public.ottoq_retraining_triggers ADD CONSTRAINT ottoq_retraining_triggers_condition_kind_check CHECK ((condition_kind = ANY (ARRAY['drift_psi'::text, 'accuracy_decline'::text, 'calibration_decline'::text, 'time_based'::text, 'sample_threshold'::text, 'manual'::text])));

-- ===== ottoq_rule_evaluations =====
CREATE TABLE public.ottoq_rule_evaluations (
    evaluation_id uuid NOT NULL DEFAULT gen_random_uuid(),
    evaluation_seq bigint NOT NULL DEFAULT nextval('ottoq_rule_evaluations_evaluation_seq_seq'::regclass),
    evaluated_at timestamp with time zone NOT NULL DEFAULT now(),
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
    parameters_used jsonb NOT NULL DEFAULT '{}'::jsonb,
    context jsonb NOT NULL DEFAULT '{}'::jsonb,
    result_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    override_id uuid,
    linked_event_id uuid,
    correlation_id uuid
);
ALTER TABLE public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_evaluation_seq_key UNIQUE (evaluation_seq);
ALTER TABLE public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_pkey PRIMARY KEY (evaluation_id);
ALTER TABLE public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_linked_event_id_fkey FOREIGN KEY (linked_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_triggered_by_event_id_fkey FOREIGN KEY (triggered_by_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_enforcement_taken_check CHECK ((enforcement_taken = ANY (ARRAY['allowed'::text, 'blocked'::text, 'warned'::text, 'logged'::text, 'overridden'::text, 'shadow_pass'::text, 'shadow_fail'::text])));
CREATE INDEX idx_ottoq_evals_correlation ON public.ottoq_rule_evaluations USING btree (correlation_id);
CREATE INDEX idx_ottoq_evals_depot ON public.ottoq_rule_evaluations USING btree (depot_id, evaluated_at DESC) WHERE (depot_id IS NOT NULL);
CREATE INDEX idx_ottoq_evals_entity_time ON public.ottoq_rule_evaluations USING btree (entity_type, entity_id, evaluated_at DESC);
CREATE INDEX idx_ottoq_evals_failed ON public.ottoq_rule_evaluations USING btree (evaluated_at DESC) WHERE (passed = false);
CREATE INDEX idx_ottoq_evals_rule_time ON public.ottoq_rule_evaluations USING btree (rule_code, evaluated_at DESC);
CREATE INDEX idx_ottoq_evals_seq_brin ON public.ottoq_rule_evaluations USING brin (evaluation_seq);
CREATE INDEX idx_ottoq_evals_tenant ON public.ottoq_rule_evaluations USING btree (fleet_operator_id, evaluated_at DESC) WHERE (fleet_operator_id IS NOT NULL);
CREATE INDEX idx_rule_evals_linked_event ON public.ottoq_rule_evaluations USING btree (linked_event_id);
CREATE INDEX idx_rule_evals_trig_event ON public.ottoq_rule_evaluations USING btree (triggered_by_event_id);

-- ===== ottoq_rule_overrides =====
CREATE TABLE public.ottoq_rule_overrides (
    override_id uuid NOT NULL DEFAULT gen_random_uuid(),
    rule_code text NOT NULL,
    rule_version integer NOT NULL,
    entity_type text,
    entity_id uuid,
    override_actor_type text NOT NULL,
    override_actor_id text,
    approved_by text,
    justification text NOT NULL,
    effective_from timestamp with time zone NOT NULL DEFAULT now(),
    effective_until timestamp with time zone,
    triggered_evaluation_id uuid,
    linked_event_id uuid,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    fleet_operator_id uuid,
    depot_id uuid,
    payload jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_rule_overrides ADD CONSTRAINT ottoq_rule_overrides_pkey PRIMARY KEY (override_id);
ALTER TABLE public.ottoq_rule_overrides ADD CONSTRAINT ottoq_rule_overrides_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_rule_overrides ADD CONSTRAINT ottoq_rule_overrides_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_rule_overrides ADD CONSTRAINT ottoq_rule_overrides_linked_event_id_fkey FOREIGN KEY (linked_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_rule_overrides ADD CONSTRAINT ottoq_rule_overrides_justification_check CHECK ((length(TRIM(BOTH FROM justification)) >= 10));
CREATE INDEX idx_ottoq_overrides_actor ON public.ottoq_rule_overrides USING btree (override_actor_type, override_actor_id, created_at DESC);
CREATE INDEX idx_ottoq_overrides_rule ON public.ottoq_rule_overrides USING btree (rule_code, created_at DESC);
CREATE INDEX idx_rule_overrides_linked_evt ON public.ottoq_rule_overrides USING btree (linked_event_id);

-- ===== ottoq_rule_parameters =====
CREATE TABLE public.ottoq_rule_parameters (
    parameter_id uuid NOT NULL DEFAULT gen_random_uuid(),
    rule_code text NOT NULL,
    scope text NOT NULL,
    scope_id uuid NOT NULL,
    parameters jsonb NOT NULL,
    effective_from timestamp with time zone NOT NULL DEFAULT now(),
    effective_until timestamp with time zone,
    reason text,
    approved_by text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by text
);
ALTER TABLE public.ottoq_rule_parameters ADD CONSTRAINT ottoq_rule_parameters_pkey PRIMARY KEY (parameter_id);
ALTER TABLE public.ottoq_rule_parameters ADD CONSTRAINT ottoq_rule_parameters_rule_code_scope_scope_id_effective_fr_key UNIQUE (rule_code, scope, scope_id, effective_from);
ALTER TABLE public.ottoq_rule_parameters ADD CONSTRAINT ottoq_rule_parameters_scope_check CHECK ((scope = ANY (ARRAY['fleet_operator'::text, 'depot'::text, 'vehicle_class'::text])));
CREATE INDEX idx_ottoq_rule_parameters_lookup ON public.ottoq_rule_parameters USING btree (rule_code, scope, scope_id, effective_from, effective_until);

-- ===== ottoq_rules =====
CREATE TABLE public.ottoq_rules (
    rule_id uuid NOT NULL DEFAULT gen_random_uuid(),
    rule_code text NOT NULL,
    version integer NOT NULL DEFAULT 1,
    category text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    rationale text NOT NULL,
    severity text NOT NULL DEFAULT 'error'::text,
    enforcement text NOT NULL DEFAULT 'block'::text,
    override_allowed boolean NOT NULL DEFAULT false,
    override_min_role text,
    scope text NOT NULL,
    evaluator_function text NOT NULL,
    default_parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    applies_to_actions text[] NOT NULL DEFAULT '{}'::text[],
    applies_to_entities text[] NOT NULL DEFAULT '{}'::text[],
    status text NOT NULL DEFAULT 'active'::text,
    introduced_in text NOT NULL,
    deprecated_at timestamp with time zone,
    deprecation_reason text,
    successor_rule_code text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by text,
    external_references jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.ottoq_rules ADD CONSTRAINT ottoq_rules_pkey PRIMARY KEY (rule_id);
ALTER TABLE public.ottoq_rules ADD CONSTRAINT ottoq_rules_rule_code_version_key UNIQUE (rule_code, version);
ALTER TABLE public.ottoq_rules ADD CONSTRAINT ottoq_rules_category_check CHECK ((category = ANY (ARRAY['hardware_safety'::text, 'energy_safety'::text, 'sla_contract'::text, 'state_machine'::text, 'audit_integrity'::text, 'time_window'::text, 'concurrency'::text, 'emergency_cascade'::text, 'sensor_liveness'::text, 'role_authorization'::text])));
ALTER TABLE public.ottoq_rules ADD CONSTRAINT ottoq_rules_enforcement_check CHECK ((enforcement = ANY (ARRAY['block'::text, 'warn'::text, 'log_only'::text, 'shadow'::text])));
ALTER TABLE public.ottoq_rules ADD CONSTRAINT ottoq_rules_scope_check CHECK ((scope = ANY (ARRAY['system'::text, 'fleet_operator'::text, 'depot'::text, 'vehicle_class'::text])));
ALTER TABLE public.ottoq_rules ADD CONSTRAINT ottoq_rules_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
ALTER TABLE public.ottoq_rules ADD CONSTRAINT ottoq_rules_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'shadow'::text, 'active'::text, 'deprecated'::text, 'archived'::text])));
CREATE INDEX idx_ottoq_rules_action ON public.ottoq_rules USING gin (applies_to_actions);
CREATE INDEX idx_ottoq_rules_category ON public.ottoq_rules USING btree (category, status);
CREATE INDEX idx_ottoq_rules_code_active ON public.ottoq_rules USING btree (rule_code) WHERE (status = 'active'::text);

-- ===== ottoq_run_archives =====
CREATE TABLE public.ottoq_run_archives (
    sim_run_id uuid NOT NULL,
    archived_at timestamp with time zone NOT NULL DEFAULT now(),
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
    metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
    run_payload jsonb
);
ALTER TABLE public.ottoq_run_archives ADD CONSTRAINT ottoq_run_archives_pkey PRIMARY KEY (sim_run_id);
CREATE INDEX idx_ottoq_run_archives_archived_at ON public.ottoq_run_archives USING btree (archived_at DESC);

-- ===== ottoq_scenarios =====
CREATE TABLE public.ottoq_scenarios (
    scenario_id uuid NOT NULL DEFAULT gen_random_uuid(),
    scenario_code text NOT NULL,
    category text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    validates text,
    expected_outcome text,
    depot_id uuid,
    fleet_operator_ids uuid[] DEFAULT '{}'::uuid[],
    sim_duration_minutes integer NOT NULL DEFAULT 480,
    default_time_scale numeric NOT NULL DEFAULT 60.0,
    tick_interval_seconds integer NOT NULL DEFAULT 30,
    initial_conditions jsonb NOT NULL DEFAULT '{}'::jsonb,
    arrival_profile jsonb NOT NULL DEFAULT '{}'::jsonb,
    timeline jsonb NOT NULL DEFAULT '[]'::jsonb,
    random_seed bigint NOT NULL DEFAULT 42,
    stress_params jsonb DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'active'::text,
    tags text[] DEFAULT '{}'::text[],
    introduced_in text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_scenarios ADD CONSTRAINT ottoq_scenarios_pkey PRIMARY KEY (scenario_id);
ALTER TABLE public.ottoq_scenarios ADD CONSTRAINT ottoq_scenarios_scenario_code_key UNIQUE (scenario_code);
ALTER TABLE public.ottoq_scenarios ADD CONSTRAINT ottoq_scenarios_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_scenarios ADD CONSTRAINT ottoq_scenarios_category_check CHECK ((category = ANY (ARRAY['normal_operations'::text, 'stress_test'::text, 'emergency_drill'::text, 'edge_case'::text, 'soak_test'::text, 'regression'::text, 'demo'::text])));
ALTER TABLE public.ottoq_scenarios ADD CONSTRAINT ottoq_scenarios_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'deprecated'::text, 'archived'::text])));
CREATE INDEX idx_scenarios_category ON public.ottoq_scenarios USING btree (category, status);
CREATE INDEX idx_scenarios_depot ON public.ottoq_scenarios USING btree (depot_id, status);

-- ===== ottoq_schema_snapshots =====
CREATE TABLE public.ottoq_schema_snapshots (
    snapshot_id bigint NOT NULL DEFAULT nextval('ottoq_schema_snapshots_snapshot_id_seq'::regclass),
    taken_at timestamp with time zone NOT NULL DEFAULT now(),
    label text NOT NULL,
    object_kind text NOT NULL,
    schema_name text NOT NULL,
    object_name text NOT NULL,
    definition text NOT NULL,
    def_md5 text NOT NULL
);
ALTER TABLE public.ottoq_schema_snapshots ADD CONSTRAINT ottoq_schema_snapshots_pkey PRIMARY KEY (snapshot_id);
CREATE INDEX ottoq_schema_snapshots_lookup ON public.ottoq_schema_snapshots USING btree (label, object_kind, object_name);

-- ===== ottoq_signing_keys =====
CREATE TABLE public.ottoq_signing_keys (
    key_id text NOT NULL,
    scope text NOT NULL,
    scope_id uuid,
    algorithm text NOT NULL DEFAULT 'HMAC-SHA-256'::text,
    secret_ref text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    activated_at timestamp with time zone NOT NULL DEFAULT now(),
    rotated_at timestamp with time zone,
    rotation_reason text,
    created_by text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_signing_keys ADD CONSTRAINT ottoq_signing_keys_pkey PRIMARY KEY (key_id);
ALTER TABLE public.ottoq_signing_keys ADD CONSTRAINT ottoq_signing_keys_scope_scope_id_is_active_key UNIQUE (scope, scope_id, is_active) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE public.ottoq_signing_keys ADD CONSTRAINT ottoq_signing_keys_scope_check CHECK ((scope = ANY (ARRAY['system'::text, 'fleet_operator'::text, 'depot'::text])));

-- ===== ottoq_sim_runs =====
CREATE TABLE public.ottoq_sim_runs (
    sim_run_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_seq bigint NOT NULL DEFAULT nextval('ottoq_sim_runs_sim_run_seq_seq'::regclass),
    scenario_id uuid NOT NULL,
    scenario_code text NOT NULL,
    started_at timestamp with time zone NOT NULL DEFAULT now(),
    ended_at timestamp with time zone,
    last_tick_at timestamp with time zone,
    next_tick_due_at timestamp with time zone,
    sim_clock_start timestamp with time zone NOT NULL,
    sim_clock_current timestamp with time zone NOT NULL,
    sim_clock_end timestamp with time zone NOT NULL,
    time_scale numeric NOT NULL DEFAULT 60.0,
    tick_interval_seconds integer NOT NULL DEFAULT 30,
    tick_count integer NOT NULL DEFAULT 0,
    depot_id uuid,
    random_seed bigint NOT NULL DEFAULT 42,
    status text NOT NULL DEFAULT 'initializing'::text,
    failure_reason text,
    events_generated bigint NOT NULL DEFAULT 0,
    vehicles_simulated integer NOT NULL DEFAULT 0,
    charge_sessions integer NOT NULL DEFAULT 0,
    tasks_completed integer NOT NULL DEFAULT 0,
    anomalies_injected integer NOT NULL DEFAULT 0,
    emergencies_triggered integer NOT NULL DEFAULT 0,
    rule_evaluations bigint NOT NULL DEFAULT 0,
    rule_failures bigint NOT NULL DEFAULT 0,
    predictions_emitted bigint NOT NULL DEFAULT 0,
    recommendations_made bigint NOT NULL DEFAULT 0,
    timeline_cursor integer NOT NULL DEFAULT 0,
    validation_status text,
    validation_notes text,
    validation_assertions jsonb DEFAULT '[]'::jsonb,
    run_by text,
    notes text,
    payload jsonb DEFAULT '{}'::jsonb,
    policy text NOT NULL DEFAULT 'otto_q'::text,
    ab_group_id uuid,
    crn_streams jsonb,
    demo_speed_x numeric NOT NULL DEFAULT 1.0
);
ALTER TABLE public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_pkey PRIMARY KEY (sim_run_id);
ALTER TABLE public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_sim_run_seq_key UNIQUE (sim_run_seq);
ALTER TABLE public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES ottoq_scenarios(scenario_id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_policy_check CHECK ((policy = ANY (ARRAY['otto_q'::text, 'greedy'::text, 'fifo'::text, 'manual'::text])));
ALTER TABLE public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_status_check CHECK ((status = ANY (ARRAY['initializing'::text, 'running'::text, 'paused'::text, 'completed'::text, 'failed'::text, 'aborted'::text])));
ALTER TABLE public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_validation_status_check CHECK ((validation_status = ANY (ARRAY['pending'::text, 'passed'::text, 'failed'::text, 'inconclusive'::text])));
CREATE INDEX idx_sim_runs_scenario ON public.ottoq_sim_runs USING btree (scenario_id, started_at DESC);
CREATE INDEX idx_sim_runs_status ON public.ottoq_sim_runs USING btree (status, next_tick_due_at) WHERE (status = 'running'::text);
CREATE UNIQUE INDEX ottoq_one_running_run_per_depot ON public.ottoq_sim_runs USING btree (depot_id) WHERE (status = 'running'::text);

-- ===== ottoq_sim_scenarios =====
CREATE TABLE public.ottoq_sim_scenarios (
    scenario_id uuid NOT NULL DEFAULT gen_random_uuid(),
    scenario_code text NOT NULL,
    title text NOT NULL,
    description text,
    default_duration_hours numeric NOT NULL DEFAULT 24,
    default_time_scale numeric NOT NULL DEFAULT 60,
    default_tick_seconds integer NOT NULL DEFAULT 60,
    default_random_seed bigint NOT NULL DEFAULT 42,
    default_depot_id uuid NOT NULL DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
    weather_overrides jsonb DEFAULT '{}'::jsonb,
    fleet_overrides jsonb DEFAULT '{}'::jsonb,
    charger_overrides jsonb DEFAULT '{}'::jsonb,
    grid_overrides jsonb DEFAULT '{}'::jsonb,
    fault_injection jsonb DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'available'::text,
    introduced_in text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_sim_scenarios ADD CONSTRAINT ottoq_sim_scenarios_pkey PRIMARY KEY (scenario_id);
ALTER TABLE public.ottoq_sim_scenarios ADD CONSTRAINT ottoq_sim_scenarios_scenario_code_key UNIQUE (scenario_code);

-- ===== ottoq_site_structures =====
CREATE TABLE public.ottoq_site_structures (
    structure_id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    structure_code text NOT NULL,
    structure_kind text NOT NULL,
    title text,
    origin_x_ft numeric NOT NULL,
    origin_y_ft numeric NOT NULL,
    width_ft numeric,
    length_ft numeric,
    height_ft numeric,
    rotation_deg numeric DEFAULT 0,
    absolute_lat numeric,
    absolute_lng numeric,
    properties jsonb NOT NULL DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'active'::text,
    introduced_in text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_site_structures ADD CONSTRAINT ottoq_site_structures_depot_id_structure_code_key UNIQUE (depot_id, structure_code);
ALTER TABLE public.ottoq_site_structures ADD CONSTRAINT ottoq_site_structures_pkey PRIMARY KEY (structure_id);
ALTER TABLE public.ottoq_site_structures ADD CONSTRAINT ottoq_site_structures_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_site_structures ADD CONSTRAINT ottoq_site_structures_status_check CHECK ((status = ANY (ARRAY['active'::text, 'planned'::text, 'decommissioned'::text])));
ALTER TABLE public.ottoq_site_structures ADD CONSTRAINT ottoq_site_structures_structure_kind_check CHECK ((structure_kind = ANY (ARRAY['office_building'::text, 'service_building'::text, 'wash_building'::text, 'bess_compound'::text, 'solar_canopy'::text, 'metal_canopy'::text, 'gate'::text, 'fence_segment'::text, 'transformer'::text, 'lane_marker'::text, 'sign'::text, 'lighting_pole'::text, 'perimeter_wall'::text])));
CREATE INDEX idx_site_structures_depot ON public.ottoq_site_structures USING btree (depot_id, structure_kind);

-- ===== ottoq_sla_conformance_daily =====
CREATE TABLE public.ottoq_sla_conformance_daily (
    conformance_id uuid NOT NULL DEFAULT gen_random_uuid(),
    fleet_operator_id uuid NOT NULL,
    depot_id uuid,
    report_date date NOT NULL,
    sla_contract_reference text,
    total_visits integer NOT NULL DEFAULT 0,
    compliant_visits integer NOT NULL DEFAULT 0,
    partial_visits integer NOT NULL DEFAULT 0,
    non_compliant_visits integer NOT NULL DEFAULT 0,
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
    computed_at timestamp with time zone NOT NULL DEFAULT now(),
    rule_eval_sample_ids uuid[],
    visit_report_sample_ids uuid[]
);
ALTER TABLE public.ottoq_sla_conformance_daily ADD CONSTRAINT ottoq_sla_conformance_daily_fleet_operator_id_depot_id_repo_key UNIQUE (fleet_operator_id, depot_id, report_date);
ALTER TABLE public.ottoq_sla_conformance_daily ADD CONSTRAINT ottoq_sla_conformance_daily_pkey PRIMARY KEY (conformance_id);
ALTER TABLE public.ottoq_sla_conformance_daily ADD CONSTRAINT ottoq_sla_conformance_daily_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_sla_conformance_daily ADD CONSTRAINT ottoq_sla_conformance_daily_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_sla_conformance_daily ADD CONSTRAINT ottoq_sla_conformance_daily_check CHECK ((((compliant_visits + partial_visits) + non_compliant_visits) <= total_visits));
CREATE INDEX idx_sla_conf_depot_date ON public.ottoq_sla_conformance_daily USING btree (depot_id, report_date DESC) WHERE (depot_id IS NOT NULL);
CREATE INDEX idx_sla_conf_tenant_date ON public.ottoq_sla_conformance_daily USING btree (fleet_operator_id, report_date DESC);

-- ===== ottoq_sla_violations =====
CREATE TABLE public.ottoq_sla_violations (
    violation_id uuid NOT NULL DEFAULT gen_random_uuid(),
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
    detected_at timestamp with time zone NOT NULL DEFAULT now(),
    acknowledged_at timestamp with time zone,
    acknowledged_by text,
    remediation_note text,
    linked_event_id uuid,
    correlation_id uuid
);
ALTER TABLE public.ottoq_sla_violations ADD CONSTRAINT ottoq_sla_violations_pkey PRIMARY KEY (violation_id);
ALTER TABLE public.ottoq_sla_violations ADD CONSTRAINT ottoq_sla_violations_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_sla_violations ADD CONSTRAINT ottoq_sla_violations_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_sla_violations ADD CONSTRAINT ottoq_sla_violations_linked_event_id_fkey FOREIGN KEY (linked_event_id) REFERENCES ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.ottoq_sla_violations ADD CONSTRAINT ottoq_sla_violations_severity_check CHECK ((severity = ANY (ARRAY['warning'::text, 'breach'::text, 'critical_breach'::text])));
CREATE INDEX idx_sla_violations_linked_evt ON public.ottoq_sla_violations USING btree (linked_event_id);
CREATE INDEX idx_sla_violations_rule ON public.ottoq_sla_violations USING btree (rule_code, detected_at DESC);
CREATE INDEX idx_sla_violations_tenant_time ON public.ottoq_sla_violations USING btree (fleet_operator_id, detected_at DESC);
CREATE INDEX idx_sla_violations_vehicle ON public.ottoq_sla_violations USING btree (vehicle_id, detected_at DESC) WHERE (vehicle_id IS NOT NULL);

-- ===== ottoq_solar_output =====
CREATE TABLE public.ottoq_solar_output (
    output_id uuid NOT NULL DEFAULT gen_random_uuid(),
    output_seq bigint NOT NULL DEFAULT nextval('ottoq_solar_output_output_seq_seq'::regclass),
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
    inverter_clipped boolean NOT NULL DEFAULT false,
    inverter_blip boolean NOT NULL DEFAULT false,
    data_source text NOT NULL DEFAULT 'twin'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_solar_output ADD CONSTRAINT ottoq_solar_output_pkey PRIMARY KEY (output_id);
CREATE INDEX idx_solar_canopy ON public.ottoq_solar_output USING btree (canopy_code, sim_clock_at DESC);
CREATE INDEX idx_solar_depot_clock ON public.ottoq_solar_output USING btree (depot_id, sim_clock_at DESC);
CREATE INDEX idx_solar_sim_run ON public.ottoq_solar_output USING btree (sim_run_id, sim_clock_at DESC);

-- ===== ottoq_specialization_strategies =====
CREATE TABLE public.ottoq_specialization_strategies (
    strategy_id uuid NOT NULL DEFAULT gen_random_uuid(),
    prediction_type text NOT NULL,
    specialization_level text NOT NULL,
    enabled boolean NOT NULL DEFAULT true,
    min_samples_required integer NOT NULL DEFAULT 1000,
    min_days_of_history integer NOT NULL DEFAULT 30,
    min_improvement_pct numeric NOT NULL DEFAULT 5.0,
    description text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_specialization_strategies ADD CONSTRAINT ottoq_specialization_strategi_prediction_type_specializatio_key UNIQUE (prediction_type, specialization_level);
ALTER TABLE public.ottoq_specialization_strategies ADD CONSTRAINT ottoq_specialization_strategies_pkey PRIMARY KEY (strategy_id);
ALTER TABLE public.ottoq_specialization_strategies ADD CONSTRAINT ottoq_specialization_strategies_specialization_level_check CHECK ((specialization_level = ANY (ARRAY['generic'::text, 'per_oem'::text, 'per_vehicle_class'::text, 'per_oem_depot'::text])));

-- ===== ottoq_stall_bookings =====
CREATE TABLE public.ottoq_stall_bookings (
    booking_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid NOT NULL,
    stall_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    visit_id uuid,
    leg_id uuid,
    purpose text NOT NULL,
    during tstzrange NOT NULL,
    state text NOT NULL DEFAULT 'held'::text,
    booked_at timestamp with time zone NOT NULL DEFAULT now(),
    booked_by text NOT NULL DEFAULT 'otto_q'::text,
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
ALTER TABLE public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_pkey PRIMARY KEY (booking_id);
ALTER TABLE public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES stalls(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_purpose_check CHECK ((purpose = ANY (ARRAY['charge_dcfc'::text, 'charge_l2'::text, 'wash'::text, 'detail'::text, 'service'::text, 'inspect'::text, 'temp_hold'::text, 'perimeter_hold'::text, 'staging'::text])));
ALTER TABLE public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_state_check CHECK ((state = ANY (ARRAY['held'::text, 'active'::text, 'done'::text, 'released'::text, 'superseded'::text, 'interrupted'::text])));
ALTER TABLE public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_window_check CHECK (((NOT isempty(during)) AND (lower(during) IS NOT NULL) AND (upper(during) IS NOT NULL)));
CREATE INDEX ottoq_stall_bookings_decision_idx ON public.ottoq_stall_bookings USING btree (decision_id) WHERE (decision_id IS NOT NULL);
CREATE INDEX ottoq_stall_bookings_during_idx ON public.ottoq_stall_bookings USING gist (during) WHERE (state = ANY (ARRAY['held'::text, 'active'::text]));
CREATE INDEX ottoq_stall_bookings_run_simclock_idx ON public.ottoq_stall_bookings USING btree (sim_run_id, booked_at_sim);
CREATE INDEX ottoq_stall_bookings_vehicle_idx ON public.ottoq_stall_bookings USING btree (sim_run_id, vehicle_id, state);

-- ===== ottoq_state_transitions =====
CREATE TABLE public.ottoq_state_transitions (
    transition_id uuid NOT NULL DEFAULT gen_random_uuid(),
    entity_kind text NOT NULL,
    from_state text NOT NULL,
    to_state text NOT NULL,
    trigger_event text,
    allowed_actor_types text[] NOT NULL DEFAULT '{}'::text[],
    required_conditions text[] DEFAULT '{}'::text[],
    description text,
    introduced_in text,
    status text NOT NULL DEFAULT 'active'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_state_transitions ADD CONSTRAINT ottoq_state_transitions_entity_kind_from_state_to_state_key UNIQUE (entity_kind, from_state, to_state);
ALTER TABLE public.ottoq_state_transitions ADD CONSTRAINT ottoq_state_transitions_pkey PRIMARY KEY (transition_id);
ALTER TABLE public.ottoq_state_transitions ADD CONSTRAINT ottoq_state_transitions_entity_kind_check CHECK ((entity_kind = ANY (ARRAY['vehicle'::text, 'task'::text, 'stall'::text, 'schedule'::text, 'bess'::text])));
ALTER TABLE public.ottoq_state_transitions ADD CONSTRAINT ottoq_state_transitions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'deprecated'::text, 'draft'::text])));
CREATE INDEX idx_ottoq_state_trans_lookup ON public.ottoq_state_transitions USING btree (entity_kind, from_state, to_state) WHERE (status = 'active'::text);

-- ===== ottoq_t4_coverage_samples =====
CREATE TABLE public.ottoq_t4_coverage_samples (
    id bigint NOT NULL DEFAULT nextval('ottoq_t4_coverage_samples_id_seq1'::regclass),
    sim_run_id uuid NOT NULL,
    taken_at timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
    moving integer,
    covered integer,
    ratio numeric,
    open_legs integer,
    states jsonb,
    orphan_legs integer
);
ALTER TABLE public.ottoq_t4_coverage_samples ADD CONSTRAINT ottoq_t4_coverage_samples_pkey PRIMARY KEY (id);

-- ===== ottoq_tariff_windows =====
CREATE TABLE public.ottoq_tariff_windows (
    tariff_id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    label text NOT NULL,
    rate_usd_per_kwh numeric NOT NULL,
    hour_start integer NOT NULL,
    hour_end integer NOT NULL,
    day_of_week_mask integer NOT NULL DEFAULT 127,
    season text NOT NULL DEFAULT 'all'::text,
    active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_tariff_windows ADD CONSTRAINT ottoq_tariff_windows_pkey PRIMARY KEY (tariff_id);

-- ===== ottoq_telemetry_packets =====
CREATE TABLE public.ottoq_telemetry_packets (
    packet_id uuid NOT NULL DEFAULT gen_random_uuid(),
    packet_seq bigint NOT NULL DEFAULT nextval('ottoq_telemetry_packets_packet_seq_seq'::regclass),
    vehicle_id uuid NOT NULL,
    sim_run_id uuid,
    fleet_operator_id uuid,
    packet_at timestamp with time zone NOT NULL DEFAULT now(),
    sim_clock_at timestamp with time zone,
    soc_pct numeric,
    soc_source text DEFAULT 'oem_telemetry'::text,
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
    data_source text NOT NULL DEFAULT 'twin'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_telemetry_packets ADD CONSTRAINT ottoq_telemetry_packets_packet_seq_key UNIQUE (packet_seq);
ALTER TABLE public.ottoq_telemetry_packets ADD CONSTRAINT ottoq_telemetry_packets_pkey PRIMARY KEY (packet_id);
ALTER TABLE public.ottoq_telemetry_packets ADD CONSTRAINT ottoq_telemetry_packets_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text, 'replay'::text, 'shadow'::text])));
ALTER TABLE public.ottoq_telemetry_packets ADD CONSTRAINT ottoq_telemetry_packets_packet_integrity_check CHECK ((packet_integrity = ANY (ARRAY['full'::text, 'partial'::text, 'dropped'::text])));
CREATE INDEX idx_telem_dropped ON public.ottoq_telemetry_packets USING btree (packet_at DESC) WHERE (packet_integrity = 'dropped'::text);
CREATE INDEX idx_telem_seq_brin ON public.ottoq_telemetry_packets USING brin (packet_seq);
CREATE INDEX idx_telem_sim_run ON public.ottoq_telemetry_packets USING btree (sim_run_id, sim_clock_at) WHERE (sim_run_id IS NOT NULL);
CREATE INDEX idx_telem_state ON public.ottoq_telemetry_packets USING btree (vehicle_state, sim_clock_at DESC);
CREATE INDEX idx_telem_vehicle_time ON public.ottoq_telemetry_packets USING btree (vehicle_id, sim_clock_at DESC);

-- ===== ottoq_tick_clock_log =====
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
ALTER TABLE public.ottoq_tick_clock_log ADD CONSTRAINT ottoq_tick_clock_log_pkey PRIMARY KEY (sim_run_id, tick_seq);
CREATE INDEX idx_tick_clock_log_run_time ON public.ottoq_tick_clock_log USING btree (sim_run_id, real_started_at DESC);

-- ===== ottoq_tick_invariance_arms =====
CREATE TABLE public.ottoq_tick_invariance_arms (
    cert_seed bigint NOT NULL,
    tick_minutes numeric NOT NULL,
    sim_run_id uuid,
    scenario_code text NOT NULL,
    sim_minutes numeric NOT NULL,
    status text NOT NULL DEFAULT 'running'::text,
    metrics jsonb,
    started_at timestamp with time zone NOT NULL DEFAULT now(),
    finished_at timestamp with time zone
);
ALTER TABLE public.ottoq_tick_invariance_arms ADD CONSTRAINT ottoq_tick_invariance_arms_pkey PRIMARY KEY (cert_seed, tick_minutes);

-- ===== ottoq_tick_reservations =====
CREATE TABLE public.ottoq_tick_reservations (
    reservation_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid NOT NULL,
    tick_seq bigint NOT NULL,
    depot_id uuid NOT NULL,
    resource text NOT NULL,
    entity_id uuid,
    amount_kw numeric NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_tick_reservations ADD CONSTRAINT ottoq_tick_reservations_pkey PRIMARY KEY (reservation_id);
CREATE INDEX idx_tick_reservations_run_tick ON public.ottoq_tick_reservations USING btree (sim_run_id, tick_seq, resource);

-- ===== ottoq_training_runs =====
CREATE TABLE public.ottoq_training_runs (
    training_run_id uuid NOT NULL DEFAULT gen_random_uuid(),
    prediction_type text NOT NULL,
    model_family text,
    parent_model_version_id uuid,
    resulting_model_version_id uuid,
    started_at timestamp with time zone NOT NULL DEFAULT now(),
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
    hyperparameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    trainer text,
    trainer_user text,
    notebook_url text,
    git_commit_sha text,
    training_metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
    test_metrics jsonb DEFAULT '{}'::jsonb,
    cross_validation jsonb DEFAULT '{}'::jsonb,
    artifact_storage_path text,
    artifact_format text,
    artifact_size_bytes bigint,
    artifact_sha256 text,
    status text NOT NULL DEFAULT 'running'::text,
    failure_reason text,
    fleet_operator_id uuid,
    depot_id uuid,
    vehicle_class text,
    triggered_by text,
    triggered_by_alert_id uuid,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_training_runs ADD CONSTRAINT ottoq_training_runs_pkey PRIMARY KEY (training_run_id);
ALTER TABLE public.ottoq_training_runs ADD CONSTRAINT ottoq_training_runs_parent_model_version_id_fkey FOREIGN KEY (parent_model_version_id) REFERENCES model_versions(id);
ALTER TABLE public.ottoq_training_runs ADD CONSTRAINT ottoq_training_runs_resulting_model_version_id_fkey FOREIGN KEY (resulting_model_version_id) REFERENCES model_versions(id);
ALTER TABLE public.ottoq_training_runs ADD CONSTRAINT ottoq_training_runs_status_check CHECK ((status = ANY (ARRAY['running'::text, 'succeeded'::text, 'failed'::text, 'cancelled'::text])));
CREATE INDEX idx_training_runs_status ON public.ottoq_training_runs USING btree (status, started_at DESC);
CREATE INDEX idx_training_runs_type_time ON public.ottoq_training_runs USING btree (prediction_type, started_at DESC);

-- ===== ottoq_variability_cards =====
CREATE TABLE public.ottoq_variability_cards (
    id bigint NOT NULL,
    sim_run_id uuid NOT NULL,
    var_key text NOT NULL,
    scope_instance text NOT NULL,
    lifespan text NOT NULL,
    bucket_key text NOT NULL,
    value numeric,
    meta jsonb NOT NULL DEFAULT '{}'::jsonb,
    active boolean NOT NULL DEFAULT true,
    drawn_at_clock timestamp with time zone,
    drawn_at_tick bigint,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_variability_cards ADD CONSTRAINT ottoq_variability_cards_pkey PRIMARY KEY (id);
CREATE INDEX ix_vcards_current ON public.ottoq_variability_cards USING btree (sim_run_id, var_key, scope_instance) WHERE active;
CREATE UNIQUE INDEX ux_vcards_epoch ON public.ottoq_variability_cards USING btree (sim_run_id, var_key, scope_instance, bucket_key);

-- ===== ottoq_variability_catalog =====
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
    is_primary boolean NOT NULL DEFAULT false,
    wired boolean NOT NULL DEFAULT false,
    generator text,
    display_order integer NOT NULL DEFAULT 0,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    lifespan text,
    scope text,
    redraw_event text
);
ALTER TABLE public.ottoq_variability_catalog ADD CONSTRAINT ottoq_variability_catalog_pkey PRIMARY KEY (var_key);

-- ===== ottoq_variability_profiles =====
CREATE TABLE public.ottoq_variability_profiles (
    profile_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid,
    name text,
    knobs jsonb NOT NULL DEFAULT '{}'::jsonb,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_variability_profiles ADD CONSTRAINT ottoq_variability_profiles_pkey PRIMARY KEY (profile_id);
CREATE UNIQUE INDEX uq_varprofile_name ON public.ottoq_variability_profiles USING btree (name);
CREATE UNIQUE INDEX uq_varprofile_run ON public.ottoq_variability_profiles USING btree (sim_run_id);

-- ===== ottoq_vehicle_classes =====
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
    fast_charge_compatible boolean DEFAULT true,
    status text NOT NULL DEFAULT 'active'::text,
    introduced_in text,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_vehicle_classes ADD CONSTRAINT ottoq_vehicle_classes_pkey PRIMARY KEY (vehicle_class_code);
ALTER TABLE public.ottoq_vehicle_classes ADD CONSTRAINT ottoq_vehicle_classes_oem_fleet_operator_id_fkey FOREIGN KEY (oem_fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_vehicle_classes ADD CONSTRAINT ottoq_vehicle_classes_status_check CHECK ((status = ANY (ARRAY['active'::text, 'deprecated'::text, 'archived'::text])));
CREATE INDEX idx_vehicle_classes_oem ON public.ottoq_vehicle_classes USING btree (oem_name, status);

-- ===== ottoq_vehicle_commands =====
CREATE TABLE public.ottoq_vehicle_commands (
    command_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid,
    depot_id uuid,
    vehicle_id uuid NOT NULL,
    command_type text NOT NULL,
    payload jsonb,
    issued_at timestamp with time zone NOT NULL,
    issued_by text NOT NULL DEFAULT 'decide_tick'::text,
    status text NOT NULL DEFAULT 'issued'::text,
    confirmed_at timestamp with time zone,
    confirmed_by text,
    executed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    reason_code text,
    reason_detail text,
    reacted_at timestamp with time zone
);
ALTER TABLE public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_pkey PRIMARY KEY (command_id);
ALTER TABLE public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
ALTER TABLE public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_command_type_check CHECK ((command_type = ANY (ARRAY['dispatch'::text, 'begin_charge'::text, 'proceed_to_stall'::text, 'enter_wash'::text, 'enter_service'::text, 'stage'::text, 'hold'::text])));
ALTER TABLE public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_reason_code_check CHECK (((reason_code IS NULL) OR (reason_code = ANY (ARRAY['target_occupied'::text, 'resource_faulted'::text, 'target_unknown'::text, 'vehicle_unresponsive'::text, 'command_malformed'::text, 'no_capacity'::text, 'superseded'::text]))));
ALTER TABLE public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_status_check CHECK ((status = ANY (ARRAY['issued'::text, 'confirmed'::text, 'executed'::text, 'refused'::text, 'expired'::text])));
CREATE INDEX idx_vehicle_commands_run ON public.ottoq_vehicle_commands USING btree (sim_run_id, status);
CREATE INDEX idx_vehicle_commands_vehicle ON public.ottoq_vehicle_commands USING btree (vehicle_id, issued_at DESC);
CREATE INDEX ottoq_vehicle_commands_refused_unreacted ON public.ottoq_vehicle_commands USING btree (sim_run_id, issued_at) WHERE ((status = 'refused'::text) AND (reacted_at IS NULL));

-- ===== ottoq_vehicle_dispatches =====
CREATE TABLE public.ottoq_vehicle_dispatches (
    dispatch_id uuid NOT NULL DEFAULT gen_random_uuid(),
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
    status text NOT NULL DEFAULT 'active'::text,
    data_source text DEFAULT 'twin'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    returning_started_at timestamp with time zone,
    return_eta_minutes numeric,
    return_evidence jsonb,
    heartbeat_count integer NOT NULL DEFAULT 0
);
ALTER TABLE public.ottoq_vehicle_dispatches ADD CONSTRAINT ottoq_vehicle_dispatches_pkey PRIMARY KEY (dispatch_id);
ALTER TABLE public.ottoq_vehicle_dispatches ADD CONSTRAINT chk_completed_has_return_trigger CHECK (((status <> 'completed'::text) OR (return_trigger IS NOT NULL))) NOT VALID;
ALTER TABLE public.ottoq_vehicle_dispatches ADD CONSTRAINT ottoq_vehicle_dispatches_status_check CHECK ((status = ANY (ARRAY['active'::text, 'returning'::text, 'completed'::text, 'aborted'::text])));
CREATE INDEX idx_dispatches_active ON public.ottoq_vehicle_dispatches USING btree (status) WHERE (status = ANY (ARRAY['active'::text, 'returning'::text]));
CREATE INDEX idx_dispatches_sim_run ON public.ottoq_vehicle_dispatches USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
CREATE INDEX idx_dispatches_vehicle ON public.ottoq_vehicle_dispatches USING btree (vehicle_id, dispatched_at DESC);

-- ===== ottoq_vehicle_incidents =====
CREATE TABLE public.ottoq_vehicle_incidents (
    incident_id uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id uuid NOT NULL,
    sim_run_id uuid,
    occurred_at timestamp with time zone NOT NULL,
    recorded_at timestamp with time zone NOT NULL DEFAULT now(),
    incident_type text NOT NULL,
    severity text NOT NULL,
    at_lat numeric,
    at_lng numeric,
    speed_kmh_at_event numeric,
    soc_pct_at_event numeric,
    description text,
    requires_tow boolean NOT NULL DEFAULT false,
    resolution_status text DEFAULT 'open'::text,
    data_source text NOT NULL DEFAULT 'twin'::text,
    linked_event_id uuid
);
ALTER TABLE public.ottoq_vehicle_incidents ADD CONSTRAINT ottoq_vehicle_incidents_pkey PRIMARY KEY (incident_id);
ALTER TABLE public.ottoq_vehicle_incidents ADD CONSTRAINT ottoq_vehicle_incidents_incident_type_check CHECK ((incident_type = ANY (ARRAY['collision_minor'::text, 'collision_moderate'::text, 'collision_major'::text, 'breakdown_mechanical'::text, 'breakdown_electrical'::text, 'stranded_low_soc'::text, 'tire_failure'::text, 'sensor_critical_fail'::text, 'manual_safety_takeover'::text, 'third_party_impact'::text])));
ALTER TABLE public.ottoq_vehicle_incidents ADD CONSTRAINT ottoq_vehicle_incidents_resolution_status_check CHECK ((resolution_status = ANY (ARRAY['open'::text, 'tow_dispatched'::text, 'resolved'::text])));
ALTER TABLE public.ottoq_vehicle_incidents ADD CONSTRAINT ottoq_vehicle_incidents_severity_check CHECK ((severity = ANY (ARRAY['minor'::text, 'moderate'::text, 'major'::text, 'safety_critical'::text])));
CREATE INDEX idx_incidents_open ON public.ottoq_vehicle_incidents USING btree (resolution_status, occurred_at DESC) WHERE (resolution_status <> 'resolved'::text);
CREATE INDEX idx_incidents_sim_run ON public.ottoq_vehicle_incidents USING btree (sim_run_id);
CREATE INDEX idx_incidents_vehicle ON public.ottoq_vehicle_incidents USING btree (vehicle_id, occurred_at DESC);

-- ===== ottoq_vehicle_itineraries =====
CREATE TABLE public.ottoq_vehicle_itineraries (
    itinerary_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    created_by text NOT NULL DEFAULT 'decide_tick'::text,
    status text NOT NULL DEFAULT 'active'::text,
    sim_created_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_vehicle_itineraries ADD CONSTRAINT ottoq_vehicle_itineraries_pkey PRIMARY KEY (itinerary_id);
ALTER TABLE public.ottoq_vehicle_itineraries ADD CONSTRAINT ottoq_vehicle_itineraries_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'amended'::text, 'cancelled'::text])));
CREATE INDEX idx_itineraries_run_vehicle ON public.ottoq_vehicle_itineraries USING btree (sim_run_id, vehicle_id) WHERE (status = 'active'::text);

-- ===== ottoq_vehicle_wear =====
CREATE TABLE public.ottoq_vehicle_wear (
    vehicle_id uuid NOT NULL,
    sim_run_id uuid NOT NULL,
    drive_km_total numeric NOT NULL DEFAULT 0,
    drive_hours_total numeric NOT NULL DEFAULT 0,
    backfilled_km numeric NOT NULL DEFAULT 0,
    backfilled_hours numeric NOT NULL DEFAULT 0,
    km_at_last_pm numeric NOT NULL DEFAULT 0,
    hours_at_last_calibration numeric NOT NULL DEFAULT 0,
    calibrated_at timestamp with time zone,
    soil_index numeric NOT NULL DEFAULT 0,
    cabin_litter_events integer NOT NULL DEFAULT 0,
    open_dtc_count integer NOT NULL DEFAULT 0,
    worst_open_dtc_rank smallint NOT NULL DEFAULT 99,
    last_advanced_tick bigint,
    last_advanced_sim_clock timestamp with time zone,
    km_per_tick_ema numeric NOT NULL DEFAULT 0,
    drive_ticks_observed integer NOT NULL DEFAULT 0,
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_pkey PRIMARY KEY (vehicle_id, sim_run_id);
ALTER TABLE public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
ALTER TABLE public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_cabin_litter_events_check CHECK ((cabin_litter_events >= 0));
ALTER TABLE public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_drive_hours_total_check CHECK ((drive_hours_total >= (0)::numeric));
ALTER TABLE public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_drive_km_total_check CHECK ((drive_km_total >= (0)::numeric));
ALTER TABLE public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_open_dtc_count_check CHECK ((open_dtc_count >= 0));
ALTER TABLE public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_soil_index_check CHECK (((soil_index >= (0)::numeric) AND (soil_index <= (1)::numeric)));
CREATE INDEX idx_vehicle_wear_run ON public.ottoq_vehicle_wear USING btree (sim_run_id);

-- ===== ottoq_visit_cost_attribution =====
CREATE TABLE public.ottoq_visit_cost_attribution (
    attribution_id uuid NOT NULL DEFAULT gen_random_uuid(),
    attribution_seq bigint NOT NULL DEFAULT nextval('ottoq_visit_cost_attribution_attribution_seq_seq'::regclass),
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
    cost_components jsonb DEFAULT '{}'::jsonb,
    computed_at timestamp with time zone NOT NULL DEFAULT now(),
    compute_method text DEFAULT 'rule_based'::text,
    data_quality_score numeric,
    notes text
);
ALTER TABLE public.ottoq_visit_cost_attribution ADD CONSTRAINT ottoq_visit_cost_attribution_attribution_seq_key UNIQUE (attribution_seq);
ALTER TABLE public.ottoq_visit_cost_attribution ADD CONSTRAINT ottoq_visit_cost_attribution_pkey PRIMARY KEY (attribution_id);
ALTER TABLE public.ottoq_visit_cost_attribution ADD CONSTRAINT ottoq_visit_cost_attribution_schedule_id_key UNIQUE (schedule_id);
ALTER TABLE public.ottoq_visit_cost_attribution ADD CONSTRAINT ottoq_visit_cost_attribution_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE SET NULL;
ALTER TABLE public.ottoq_visit_cost_attribution ADD CONSTRAINT ottoq_visit_cost_attribution_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
CREATE INDEX idx_visit_cost_depot_time ON public.ottoq_visit_cost_attribution USING btree (depot_id, visit_completed_at DESC) WHERE (depot_id IS NOT NULL);
CREATE INDEX idx_visit_cost_tenant_time ON public.ottoq_visit_cost_attribution USING btree (fleet_operator_id, visit_completed_at DESC) WHERE (fleet_operator_id IS NOT NULL);

-- ===== ottoq_visit_needs =====
CREATE TABLE public.ottoq_visit_needs (
    visit_id uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id uuid NOT NULL,
    sim_run_id uuid,
    depot_id uuid,
    arrived_at timestamp with time zone NOT NULL,
    visit_key text NOT NULL,
    archetype text,
    urgency text NOT NULL DEFAULT 'standard'::text,
    dispatch_due_at timestamp with time zone,
    target_soc numeric,
    atoms jsonb NOT NULL DEFAULT '[]'::jsonb,
    status text NOT NULL DEFAULT 'open'::text,
    source text NOT NULL DEFAULT 'twin_generator'::text,
    meta jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_visit_needs ADD CONSTRAINT ottoq_visit_needs_pkey PRIMARY KEY (visit_id);
ALTER TABLE public.ottoq_visit_needs ADD CONSTRAINT ottoq_visit_needs_vehicle_id_visit_key_key UNIQUE (vehicle_id, visit_key);
ALTER TABLE public.ottoq_visit_needs ADD CONSTRAINT ottoq_visit_needs_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
ALTER TABLE public.ottoq_visit_needs ADD CONSTRAINT ottoq_visit_needs_status_check CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'complete'::text, 'carried_over'::text, 'superseded'::text])));
ALTER TABLE public.ottoq_visit_needs ADD CONSTRAINT ottoq_visit_needs_urgency_check CHECK ((urgency = ANY (ARRAY['immediate_dispatch'::text, 'standard'::text, 'overnight_hold'::text, 'tech_hold'::text])));
CREATE INDEX idx_visit_needs_open_by_vehicle ON public.ottoq_visit_needs USING btree (vehicle_id, created_at DESC) WHERE (status = ANY (ARRAY['open'::text, 'in_progress'::text]));
CREATE INDEX idx_visit_needs_run_status ON public.ottoq_visit_needs USING btree (sim_run_id, status);
CREATE INDEX idx_visit_needs_vehicle ON public.ottoq_visit_needs USING btree (vehicle_id, created_at DESC);

-- ===== ottoq_wave_plan =====
CREATE TABLE public.ottoq_wave_plan (
    plan_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sim_run_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    want_class text NOT NULL,
    charge_start_at timestamp with time zone,
    charge_end_at timestamp with time zone,
    charge_minutes numeric,
    target_soc numeric,
    due_at timestamp with time zone,
    feasible boolean NOT NULL DEFAULT true,
    reason text,
    generator text NOT NULL DEFAULT 'edf_v1'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_wave_plan ADD CONSTRAINT ottoq_wave_plan_pkey PRIMARY KEY (plan_id);
CREATE INDEX idx_wave_plan_run ON public.ottoq_wave_plan USING btree (sim_run_id, created_at DESC);

-- ===== ottoq_wear_tick_status =====
CREATE TABLE public.ottoq_wear_tick_status (
    sim_run_id uuid NOT NULL,
    tick_seq bigint NOT NULL,
    sim_clock timestamp with time zone,
    attempted integer NOT NULL DEFAULT 0,
    written integer NOT NULL DEFAULT 0,
    note text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_wear_tick_status ADD CONSTRAINT ottoq_wear_tick_status_pkey PRIMARY KEY (sim_run_id, tick_seq);

-- ===== ottoq_weather_snapshots =====
CREATE TABLE public.ottoq_weather_snapshots (
    snapshot_id uuid NOT NULL DEFAULT gen_random_uuid(),
    snapshot_seq bigint NOT NULL DEFAULT nextval('ottoq_weather_snapshots_snapshot_seq_seq'::regclass),
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
    data_source text NOT NULL DEFAULT 'twin'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_weather_snapshots ADD CONSTRAINT ottoq_weather_snapshots_pkey PRIMARY KEY (snapshot_id);
CREATE INDEX idx_weather_depot_clock ON public.ottoq_weather_snapshots USING btree (depot_id, sim_clock_at DESC);
CREATE INDEX idx_weather_sim_run ON public.ottoq_weather_snapshots USING btree (sim_run_id, sim_clock_at DESC);

-- ===== ottow_api_keys =====
CREATE TABLE public.ottow_api_keys (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    key_hash text NOT NULL,
    key_prefix text NOT NULL,
    source text NOT NULL,
    source_name text NOT NULL,
    allowed_platforms text[],
    is_active boolean NOT NULL DEFAULT true,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by_user_id uuid
);
ALTER TABLE public.ottow_api_keys ADD CONSTRAINT ottow_api_keys_pkey PRIMARY KEY (id);
ALTER TABLE public.ottow_api_keys ADD CONSTRAINT ottow_api_keys_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ottow_api_keys ADD CONSTRAINT ottow_api_keys_source_check CHECK ((source = ANY (ARRAY['oem_webhook'::text, 'fleet_api'::text, 'vehicle_telemetry'::text])));
CREATE INDEX idx_ottow_api_keys_hash ON public.ottow_api_keys USING btree (key_hash) WHERE (is_active = true);

-- ===== ottow_dispatch_rules =====
CREATE TABLE public.ottow_dispatch_rules (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    rule_name text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    match_incident_category text,
    match_priority text,
    match_source text,
    action text NOT NULL,
    auto_assign_driver boolean NOT NULL DEFAULT false,
    max_driver_distance_miles numeric(6,2) DEFAULT 15.0,
    required_certs text[],
    priority_order integer NOT NULL DEFAULT 100,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottow_dispatch_rules ADD CONSTRAINT ottow_dispatch_rules_pkey PRIMARY KEY (id);
ALTER TABLE public.ottow_dispatch_rules ADD CONSTRAINT ottow_dispatch_rules_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ottow_dispatch_rules ADD CONSTRAINT ottow_dispatch_rules_action_check CHECK ((action = ANY (ARRAY['auto_dispatch'::text, 'queue_for_review'::text, 'reject'::text, 'alert_ops'::text])));
CREATE INDEX idx_ottow_dispatch_rules_depot_order ON public.ottow_dispatch_rules USING btree (depot_id, priority_order) WHERE (is_active = true);

-- ===== ottow_drivers =====
CREATE TABLE public.ottow_drivers (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    staff_user_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'off_duty'::text,
    current_mission_id uuid,
    vehicle_class_certs text[] DEFAULT '{}'::text[],
    last_location_lat numeric(10,7),
    last_location_lng numeric(10,7),
    last_location_at timestamp with time zone,
    shift_start timestamp with time zone,
    shift_end timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottow_drivers ADD CONSTRAINT ottow_drivers_pkey PRIMARY KEY (id);
ALTER TABLE public.ottow_drivers ADD CONSTRAINT ottow_drivers_staff_user_id_key UNIQUE (staff_user_id);
ALTER TABLE public.ottow_drivers ADD CONSTRAINT fk_ottow_drivers_current_mission FOREIGN KEY (current_mission_id) REFERENCES ottow_missions(id) ON DELETE SET NULL;
ALTER TABLE public.ottow_drivers ADD CONSTRAINT ottow_drivers_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ottow_drivers ADD CONSTRAINT ottow_drivers_staff_user_id_fkey FOREIGN KEY (staff_user_id) REFERENCES staff_users(id) ON DELETE CASCADE;
ALTER TABLE public.ottow_drivers ADD CONSTRAINT ottow_drivers_status_check CHECK ((status = ANY (ARRAY['available'::text, 'on_mission'::text, 'off_duty'::text, 'break'::text])));
CREATE INDEX idx_ottow_drivers_depot_status ON public.ottow_drivers USING btree (depot_id, status);
CREATE INDEX idx_ottow_drivers_staff ON public.ottow_drivers USING btree (staff_user_id);

-- ===== ottow_mission_events =====
CREATE TABLE public.ottow_mission_events (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    mission_id uuid NOT NULL,
    event_type text NOT NULL,
    from_status text,
    to_status text,
    location_lat numeric(10,7),
    location_lng numeric(10,7),
    actor_id uuid,
    actor_type text DEFAULT 'driver'::text,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb,
    client_timestamp timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottow_mission_events ADD CONSTRAINT ottow_mission_events_pkey PRIMARY KEY (id);
ALTER TABLE public.ottow_mission_events ADD CONSTRAINT ottow_mission_events_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES ottow_missions(id) ON DELETE CASCADE;
ALTER TABLE public.ottow_mission_events ADD CONSTRAINT ottow_mission_events_actor_type_check CHECK ((actor_type = ANY (ARRAY['driver'::text, 'dispatcher'::text, 'otto_q_engine'::text, 'system'::text])));
ALTER TABLE public.ottow_mission_events ADD CONSTRAINT ottow_mission_events_event_type_check CHECK ((event_type = ANY (ARRAY['status_change'::text, 'location_update'::text, 'note_added'::text, 'eta_updated'::text, 'stall_requested'::text, 'stall_assigned'::text, 'photo_attached'::text, 'driver_assigned'::text, 'priority_changed'::text, 'cancellation'::text, 'vehicle_condition_report'::text])));
CREATE INDEX idx_ottow_events_mission_time ON public.ottow_mission_events USING btree (mission_id, created_at);
CREATE INDEX idx_ottow_events_type ON public.ottow_mission_events USING btree (mission_id, event_type);

-- ===== ottow_missions =====
CREATE TABLE public.ottow_missions (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    exception_id uuid,
    vehicle_id uuid NOT NULL,
    driver_staff_id uuid,
    ottow_vehicle_id uuid,
    status text NOT NULL DEFAULT 'reported'::text,
    priority text NOT NULL DEFAULT 'standard'::text,
    incident_category text NOT NULL DEFAULT 'other'::text,
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
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    source text DEFAULT 'manual_dispatch'::text,
    external_reference_id text,
    notification_id uuid
);
ALTER TABLE public.ottow_missions ADD CONSTRAINT ottow_missions_pkey PRIMARY KEY (id);
ALTER TABLE public.ottow_missions ADD CONSTRAINT ottow_missions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ottow_missions ADD CONSTRAINT ottow_missions_destination_stall_id_fkey FOREIGN KEY (destination_stall_id) REFERENCES stalls(id) ON DELETE SET NULL;
ALTER TABLE public.ottow_missions ADD CONSTRAINT ottow_missions_driver_staff_id_fkey FOREIGN KEY (driver_staff_id) REFERENCES staff_users(id) ON DELETE SET NULL;
ALTER TABLE public.ottow_missions ADD CONSTRAINT ottow_missions_exception_id_fkey FOREIGN KEY (exception_id) REFERENCES exceptions(id) ON DELETE SET NULL;
ALTER TABLE public.ottow_missions ADD CONSTRAINT ottow_missions_ottow_vehicle_id_fkey FOREIGN KEY (ottow_vehicle_id) REFERENCES vehicles(id) ON DELETE SET NULL;
ALTER TABLE public.ottow_missions ADD CONSTRAINT ottow_missions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
ALTER TABLE public.ottow_missions ADD CONSTRAINT ottow_missions_incident_category_check CHECK ((incident_category = ANY (ARRAY['battery_thermal'::text, 'mechanical'::text, 'collision'::text, 'sensor_failure'::text, 'flat_tire'::text, 'software_lockup'::text, 'vandalism'::text, 'interior_damage'::text, 'charger_fault'::text, 'other'::text])));
ALTER TABLE public.ottow_missions ADD CONSTRAINT ottow_missions_priority_check CHECK ((priority = ANY (ARRAY['critical'::text, 'high'::text, 'standard'::text, 'low'::text])));
ALTER TABLE public.ottow_missions ADD CONSTRAINT ottow_missions_status_check CHECK ((status = ANY (ARRAY['reported'::text, 'dispatched'::text, 'en_route'::text, 'on_site'::text, 'vehicle_secured'::text, 'returning'::text, 'arrived_depot'::text, 'stall_assigned'::text, 'vehicle_delivered'::text, 'closed'::text, 'cancelled'::text])));
CREATE INDEX idx_ottow_missions_active ON public.ottow_missions USING btree (depot_id, status) WHERE (status <> ALL (ARRAY['closed'::text, 'cancelled'::text]));
CREATE INDEX idx_ottow_missions_depot_status ON public.ottow_missions USING btree (depot_id, status);
CREATE INDEX idx_ottow_missions_driver ON public.ottow_missions USING btree (driver_staff_id, status);
CREATE INDEX idx_ottow_missions_exception ON public.ottow_missions USING btree (exception_id);
CREATE INDEX idx_ottow_missions_notification ON public.ottow_missions USING btree (notification_id) WHERE (notification_id IS NOT NULL);
CREATE INDEX idx_ottow_missions_vehicle ON public.ottow_missions USING btree (vehicle_id);

-- ===== ottow_notifications =====
CREATE TABLE public.ottow_notifications (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    source text NOT NULL,
    external_reference_id text,
    webhook_payload jsonb,
    status text NOT NULL DEFAULT 'pending'::text,
    vehicle_id uuid,
    vehicle_platform text,
    vehicle_external_id text,
    vehicle_vin text,
    incident_category text NOT NULL DEFAULT 'other'::text,
    priority text NOT NULL DEFAULT 'standard'::text,
    incident_lat numeric(10,7),
    incident_lng numeric(10,7),
    incident_address text,
    description text,
    exception_id uuid,
    auto_dispatch_eligible boolean NOT NULL DEFAULT false,
    auto_dispatch_reason text,
    reviewed_by_user_id uuid,
    reviewed_at timestamp with time zone,
    rejection_reason text,
    mission_id uuid,
    dedup_key text NOT NULL,
    received_at timestamp with time zone NOT NULL DEFAULT now(),
    acknowledged_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.ottow_notifications ADD CONSTRAINT ottow_notifications_pkey PRIMARY KEY (id);
ALTER TABLE public.ottow_notifications ADD CONSTRAINT ottow_notifications_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.ottow_notifications ADD CONSTRAINT ottow_notifications_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE SET NULL;
ALTER TABLE public.ottow_notifications ADD CONSTRAINT ottow_notifications_incident_category_check CHECK ((incident_category = ANY (ARRAY['battery_thermal'::text, 'mechanical'::text, 'collision'::text, 'sensor_failure'::text, 'flat_tire'::text, 'software_lockup'::text, 'vandalism'::text, 'interior_damage'::text, 'charger_fault'::text, 'other'::text])));
ALTER TABLE public.ottow_notifications ADD CONSTRAINT ottow_notifications_priority_check CHECK ((priority = ANY (ARRAY['critical'::text, 'high'::text, 'standard'::text, 'low'::text])));
ALTER TABLE public.ottow_notifications ADD CONSTRAINT ottow_notifications_source_check CHECK ((source = ANY (ARRAY['manual_dispatch'::text, 'oem_webhook'::text, 'fleet_api'::text, 'otto_q_engine'::text, 'vehicle_telemetry'::text])));
ALTER TABLE public.ottow_notifications ADD CONSTRAINT ottow_notifications_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'acknowledged'::text, 'mission_created'::text, 'rejected'::text])));
CREATE UNIQUE INDEX idx_ottow_notifications_dedup ON public.ottow_notifications USING btree (dedup_key) WHERE (status <> 'rejected'::text);
CREATE INDEX idx_ottow_notifications_depot_time ON public.ottow_notifications USING btree (depot_id, received_at DESC);
CREATE INDEX idx_ottow_notifications_pending ON public.ottow_notifications USING btree (depot_id, status) WHERE (status = 'pending'::text);
CREATE INDEX idx_ottow_notifications_vehicle ON public.ottow_notifications USING btree (vehicle_id, status);

-- ===== p0_booking_test_2026_08_01 =====
CREATE TABLE public.p0_booking_test_2026_08_01 (
    step integer,
    note text,
    booking_id uuid,
    rows_after integer,
    purpose text,
    win_min numeric,
    tick_alive boolean,
    ran_at timestamp with time zone DEFAULT now()
);

-- ===== p0_calendar_diagnosis_2026_08_02 =====
CREATE TABLE public.p0_calendar_diagnosis_2026_08_02 (
    id bigint NOT NULL DEFAULT nextval('p0_calendar_diagnosis_2026_08_02_id_seq'::regclass),
    run_id uuid,
    phase text,
    metric text,
    k text,
    v text,
    denom text,
    note text,
    captured_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.p0_calendar_diagnosis_2026_08_02 ADD CONSTRAINT p0_calendar_diagnosis_2026_08_02_pkey PRIMARY KEY (id);

-- ===== p0_reopen_baseline_2026_08_03 =====
CREATE TABLE public.p0_reopen_baseline_2026_08_03 (
    booking_id uuid,
    vehicle_id uuid,
    stall_id uuid,
    purpose text,
    state text,
    release_reason text,
    booked_at_sim timestamp with time zone,
    released_at timestamp with time zone,
    win_lo timestamp with time zone,
    win_hi timestamp with time zone,
    exc_status text,
    exc_immobilizing text,
    exc_flagged_at text,
    has_open_reopen_need boolean,
    held_a_space_after bigint
);

-- ===== p12_contaminated_run904_bookings =====
CREATE TABLE public.p12_contaminated_run904_bookings (
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

-- ===== p12_contaminated_run904_cuopt =====
CREATE TABLE public.p12_contaminated_run904_cuopt (
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

-- ===== p12_contaminated_run904_needs =====
CREATE TABLE public.p12_contaminated_run904_needs (
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

-- ===== p12_contaminated_run904_runrow =====
CREATE TABLE public.p12_contaminated_run904_runrow (
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

-- ===== p2_cuopt_first_refusal_smoke_2026_08_02 =====
CREATE TABLE public.p2_cuopt_first_refusal_smoke_2026_08_02 (
    seq bigint NOT NULL DEFAULT nextval('p2_cuopt_first_refusal_smoke_2026_08_02_seq_seq'::regclass),
    at_real timestamp with time zone DEFAULT now(),
    step text,
    claim text,
    detail jsonb
);
ALTER TABLE public.p2_cuopt_first_refusal_smoke_2026_08_02 ADD CONSTRAINT p2_cuopt_first_refusal_smoke_2026_08_02_pkey PRIMARY KEY (seq);

-- ===== p2_eviction_proof_2026_08_03 =====
CREATE TABLE public.p2_eviction_proof_2026_08_03 (
    bucket text,
    event_id uuid,
    event_type text,
    entity_id uuid,
    occurred_at timestamp with time zone,
    payload jsonb
);

-- ===== p2_guard_unit_2026_08_03 =====
CREATE TABLE public.p2_guard_unit_2026_08_03 (
    ran_at timestamp with time zone DEFAULT now(),
    case_name text,
    vehicle_id uuid,
    state text,
    result jsonb,
    side_effect_cleaned integer
);

-- ===== p2_unfreeze_proof_2026_08_01 =====
CREATE TABLE public.p2_unfreeze_proof_2026_08_01 (
    id bigint NOT NULL DEFAULT nextval('p2_unfreeze_proof_2026_08_01_id_seq'::regclass),
    section text,
    metric text,
    k text,
    v text,
    denom text,
    note text,
    captured_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.p2_unfreeze_proof_2026_08_01 ADD CONSTRAINT p2_unfreeze_proof_2026_08_01_pkey PRIMARY KEY (id);

-- ===== p3_phantom_smoke_2026_08_02 =====
CREATE TABLE public.p3_phantom_smoke_2026_08_02 (
    id bigint NOT NULL DEFAULT nextval('p3_phantom_smoke_2026_08_02_id_seq'::regclass),
    taken_at timestamp with time zone DEFAULT now(),
    phase text,
    k text,
    v text,
    note text
);
ALTER TABLE public.p3_phantom_smoke_2026_08_02 ADD CONSTRAINT p3_phantom_smoke_2026_08_02_pkey PRIMARY KEY (id);

-- ===== p3_smoke_restore_2026_08_02 =====
CREATE TABLE public.p3_smoke_restore_2026_08_02 (
    kind text,
    obj_id uuid,
    col text,
    val text
);

-- ===== p7_band_probe_2026_08_03 =====
CREATE TABLE public.p7_band_probe_2026_08_03 (
    seq bigint NOT NULL DEFAULT nextval('p7_band_probe_2026_08_03_seq_seq'::regclass),
    at_real timestamp with time zone DEFAULT now(),
    sim_run_id uuid,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    note text,
    detail jsonb
);
ALTER TABLE public.p7_band_probe_2026_08_03 ADD CONSTRAINT p7_band_probe_2026_08_03_pkey PRIMARY KEY (seq);

-- ===== p7_cuopt_supply_proof_2026_08_03 =====
CREATE TABLE public.p7_cuopt_supply_proof_2026_08_03 (
    seq bigint NOT NULL DEFAULT nextval('p7_cuopt_supply_proof_2026_08_03_seq_seq'::regclass),
    at_real timestamp with time zone DEFAULT now(),
    step text,
    claim text,
    detail jsonb
);
ALTER TABLE public.p7_cuopt_supply_proof_2026_08_03 ADD CONSTRAINT p7_cuopt_supply_proof_2026_08_03_pkey PRIMARY KEY (seq);

-- ===== phantom_provenance_proof_2026_08_02 =====
CREATE TABLE public.phantom_provenance_proof_2026_08_02 (
    captured_at timestamp with time zone NOT NULL DEFAULT now(),
    phase text NOT NULL,
    detail jsonb NOT NULL
);

-- ===== phase10_bookings_424242 =====
CREATE TABLE public.phase10_bookings_424242 (
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

-- ===== phase10_cap_unit_2026_08_03 =====
CREATE TABLE public.phase10_cap_unit_2026_08_03 (
    call_no integer,
    ret integer,
    attempts integer,
    escalated boolean,
    status text,
    note text
);

-- ===== phase10_cert_424242 =====
CREATE TABLE public.phase10_cert_424242 (
    sim_run_id uuid,
    captured_at timestamp with time zone DEFAULT now(),
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text
);

-- ===== phase10_cuopt_log_424242 =====
CREATE TABLE public.phase10_cuopt_log_424242 (
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

-- ===== phase10_dispatches_424242 =====
CREATE TABLE public.phase10_dispatches_424242 (
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
    heartbeat_count integer
);

-- ===== phase10_eviction_evidence_424242 =====
CREATE TABLE public.phase10_eviction_evidence_424242 (
    event_id uuid,
    event_type text,
    entity_id uuid,
    severity text,
    occurred_at timestamp with time zone,
    payload jsonb
);

-- ===== phase10_guard_unit_2026_08_03 =====
CREATE TABLE public.phase10_guard_unit_2026_08_03 (
    case_name text,
    severity text,
    immobilizing text,
    policy_req numeric,
    allowed boolean,
    mode text,
    defer_class text,
    preserve_work text,
    expected text,
    verdict text
);

-- ===== phase10_interruption_retro_2026_08_03 =====
CREATE TABLE public.phase10_interruption_retro_2026_08_03 (
    run text,
    interrupted_bookings integer,
    events_actually_emitted integer,
    emission_ratio_as_shipped numeric,
    would_have_emitted integer,
    emission_ratio_corrected numeric,
    atoms_reopened_gt0 integer,
    atoms_gt0_rate_corrected numeric,
    non_bay_charging integer,
    bay integer
);

-- ===== phase10_replan_unit_2026_08_03 =====
CREATE TABLE public.phase10_replan_unit_2026_08_03 (
    case_name text,
    replayed_from text,
    p_svcs text[],
    prior_status text,
    ret_atoms_reopened integer,
    m_from_done integer,
    m_from_active integer,
    m_already_due integer,
    m_outstanding_restored integer,
    final_status text,
    meta_reopen_reason text,
    needs_open_after integer,
    atoms_after jsonb,
    phase9_result text,
    verdict text
);

-- ===== phase10_smoke_evidence_2026_08_03 =====
CREATE TABLE public.phase10_smoke_evidence_2026_08_03 (
    event_id uuid,
    event_type text,
    entity_id uuid,
    severity text,
    occurred_at timestamp with time zone,
    payload jsonb
);

-- ===== phase10_smoke_mark2_2026_08_03 =====
CREATE TABLE public.phase10_smoke_mark2_2026_08_03 (
    mark_at timestamp with time zone
);

-- ===== phase10_smoke_mark_2026_08_03 =====
CREATE TABLE public.phase10_smoke_mark_2026_08_03 (
    mark_at timestamp with time zone,
    sim_clock timestamp with time zone
);

-- ===== phase10_smoke_needs_2026_08_03 =====
CREATE TABLE public.phase10_smoke_needs_2026_08_03 (
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

-- ===== phase10_visit_needs_424242 =====
CREATE TABLE public.phase10_visit_needs_424242 (
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

-- ===== phase11_bookings_424242 =====
CREATE TABLE public.phase11_bookings_424242 (
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

-- ===== phase11_cert_424242 =====
CREATE TABLE public.phase11_cert_424242 (
    sim_run_id uuid,
    captured_at timestamp with time zone,
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text
);

-- ===== phase11_cuopt_log_424242 =====
CREATE TABLE public.phase11_cuopt_log_424242 (
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

-- ===== phase11_dispatches_424242 =====
CREATE TABLE public.phase11_dispatches_424242 (
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
    heartbeat_count integer
);

-- ===== phase11_eviction_evidence_424242 =====
CREATE TABLE public.phase11_eviction_evidence_424242 (
    event_id uuid,
    event_type text,
    entity_id uuid,
    severity text,
    occurred_at timestamp with time zone,
    payload jsonb
);

-- ===== phase11_guard_smoke_2026_08_03 =====
CREATE TABLE public.phase11_guard_smoke_2026_08_03 (
    test text,
    want text,
    got text,
    pass boolean,
    at timestamp with time zone DEFAULT now()
);

-- ===== phase11_harness_correction_424242 =====
CREATE TABLE public.phase11_harness_correction_424242 (
    sim_run_id uuid,
    captured_at timestamp with time zone,
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text
);

-- ===== phase11_pre_bookings_2026_08_03 =====
CREATE TABLE public.phase11_pre_bookings_2026_08_03 (
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

-- ===== phase11_pre_legs_2026_08_03 =====
CREATE TABLE public.phase11_pre_legs_2026_08_03 (
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

-- ===== phase11_pre_needs_2026_08_03 =====
CREATE TABLE public.phase11_pre_needs_2026_08_03 (
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

-- ===== phase11_proof_2026_08_03 =====
CREATE TABLE public.phase11_proof_2026_08_03 (
    captured_at timestamp with time zone DEFAULT now(),
    topic text,
    finding text,
    value text
);

-- ===== phase11_resume_proof_2026_08_03 =====
CREATE TABLE public.phase11_resume_proof_2026_08_03 (
    test text,
    tag text,
    interrupted_pairs bigint,
    rebooked bigint,
    captured_at timestamp with time zone
);

-- ===== phase11_run897_bookings_2026_08_03 =====
CREATE TABLE public.phase11_run897_bookings_2026_08_03 (
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

-- ===== phase11_run897_cuopt_2026_08_03 =====
CREATE TABLE public.phase11_run897_cuopt_2026_08_03 (
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

-- ===== phase11_run897_dispatches_2026_08_03 =====
CREATE TABLE public.phase11_run897_dispatches_2026_08_03 (
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
    heartbeat_count integer
);

-- ===== phase11_run897_harness_2026_08_03 =====
CREATE TABLE public.phase11_run897_harness_2026_08_03 (
    sim_run_id uuid,
    captured_at timestamp with time zone,
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text
);

-- ===== phase11_run897_needs_2026_08_03 =====
CREATE TABLE public.phase11_run897_needs_2026_08_03 (
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

-- ===== phase11_run897_runrow_2026_08_03 =====
CREATE TABLE public.phase11_run897_runrow_2026_08_03 (
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

-- ===== phase11_runid_2026_08_03 =====
CREATE TABLE public.phase11_runid_2026_08_03 (
    sim_run_id uuid,
    created_at timestamp with time zone DEFAULT now()
);

-- ===== phase11_runrow_424242 =====
CREATE TABLE public.phase11_runrow_424242 (
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

-- ===== phase11_smoke_2026_08_03 =====
CREATE TABLE public.phase11_smoke_2026_08_03 (
    case_name text,
    expected text,
    observed text,
    passed boolean,
    detail text
);

-- ===== phase11_smoke_bookings_2026_08_03 =====
CREATE TABLE public.phase11_smoke_bookings_2026_08_03 (
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

-- ===== phase11_smoke_legs_2026_08_03 =====
CREATE TABLE public.phase11_smoke_legs_2026_08_03 (
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

-- ===== phase11_smoke_needs_2026_08_03 =====
CREATE TABLE public.phase11_smoke_needs_2026_08_03 (
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

-- ===== phase11_visit_needs_424242 =====
CREATE TABLE public.phase11_visit_needs_424242 (
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

-- ===== phase1_busy_proof_424242 =====
CREATE TABLE public.phase1_busy_proof_424242 (
    id bigint NOT NULL DEFAULT nextval('phase1_busy_proof_424242_id_seq'::regclass),
    run_id uuid,
    section text,
    metric text,
    k text,
    v text,
    denom text,
    note text,
    captured_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.phase1_busy_proof_424242 ADD CONSTRAINT phase1_busy_proof_424242_pkey PRIMARY KEY (id);

-- ===== phase2_busy_proof_424242 =====
CREATE TABLE public.phase2_busy_proof_424242 (
    id bigint NOT NULL DEFAULT nextval('phase2_busy_proof_424242_id_seq'::regclass),
    run_id uuid,
    section text,
    metric text,
    k text,
    v text,
    denom text,
    note text,
    captured_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.phase2_busy_proof_424242 ADD CONSTRAINT phase2_busy_proof_424242_pkey PRIMARY KEY (id);

-- ===== phase3_bay_commands_2026_08_02 =====
CREATE TABLE public.phase3_bay_commands_2026_08_02 (
    phase text,
    command_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    command_type text,
    payload jsonb,
    issued_at timestamp with time zone,
    executed_at timestamp with time zone,
    status text
);

-- ===== phase3_bay_proof_2026_08_02 =====
CREATE TABLE public.phase3_bay_proof_2026_08_02 (
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
    release_reason text,
    stall_type text
);

-- ===== phase3_cert_424242 =====
CREATE TABLE public.phase3_cert_424242 (
    id bigint NOT NULL DEFAULT nextval('phase3_cert_424242_id_seq'::regclass),
    run_id uuid,
    section text,
    metric text,
    k text,
    v text,
    denom text,
    rate text,
    baseline text,
    note text,
    captured_at timestamp with time zone NOT NULL DEFAULT now(),
    final_sim_clock timestamp with time zone,
    captured_after_stop boolean NOT NULL DEFAULT true
);
ALTER TABLE public.phase3_cert_424242 ADD CONSTRAINT phase3_cert_424242_pkey PRIMARY KEY (id);

-- ===== phase4_cert_424242 =====
CREATE TABLE public.phase4_cert_424242 (
    id bigint NOT NULL DEFAULT nextval('phase4_cert_424242_id_seq'::regclass),
    run_id uuid,
    section text,
    metric text,
    k text,
    v text,
    denom text,
    rate text,
    baseline text,
    note text,
    captured_at timestamp with time zone DEFAULT now(),
    final_sim_clock timestamp with time zone,
    captured_after_stop boolean
);
ALTER TABLE public.phase4_cert_424242 ADD CONSTRAINT phase4_cert_424242_pkey PRIMARY KEY (id);

-- ===== phase5_cert_424242 =====
CREATE TABLE public.phase5_cert_424242 (
    id bigint NOT NULL DEFAULT nextval('phase5_cert_424242_id_seq'::regclass),
    run_id uuid,
    section text,
    metric text,
    k text,
    v text,
    denom text,
    rate text,
    baseline text,
    note text,
    captured_at timestamp with time zone NOT NULL DEFAULT now(),
    final_sim_clock timestamp with time zone,
    captured_after_stop boolean NOT NULL DEFAULT false
);
ALTER TABLE public.phase5_cert_424242 ADD CONSTRAINT phase5_cert_424242_pkey PRIMARY KEY (id);

-- ===== phase5_cert_d78dd3b1 =====
CREATE TABLE public.phase5_cert_d78dd3b1 (
    captured_at timestamp with time zone NOT NULL DEFAULT now(),
    kind text NOT NULL,
    row_data jsonb NOT NULL
);

-- ===== phase6_cert_424242 =====
CREATE TABLE public.phase6_cert_424242 (
    sim_run_id uuid,
    captured_at timestamp with time zone,
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text
);

-- ===== phase6_cert_424242_supply =====
CREATE TABLE public.phase6_cert_424242_supply (
    ledger_stage text,
    invocations bigint,
    edge_cands bigint,
    free_stalls_in bigint,
    proposals bigint,
    would_trim_by_cap bigint,
    trimmed_by_cap bigint
);

-- ===== phase6_cert_424242_telemetry =====
CREATE TABLE public.phase6_cert_424242_telemetry (
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

-- ===== phase7_bookings_424242 =====
CREATE TABLE public.phase7_bookings_424242 (
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
    stall_type text,
    stall_kind text
);

-- ===== phase7_cert_424242 =====
CREATE TABLE public.phase7_cert_424242 (
    sim_run_id uuid,
    captured_at timestamp with time zone DEFAULT now(),
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text
);

-- ===== phase7_cuopt_log_424242 =====
CREATE TABLE public.phase7_cuopt_log_424242 (
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

-- ===== phase7_dispatches_424242 =====
CREATE TABLE public.phase7_dispatches_424242 (
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
    heartbeat_count integer
);

-- ===== phase7_prestop_bookings_424242 =====
CREATE TABLE public.phase7_prestop_bookings_424242 (
    booking_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    stall_id uuid,
    purpose text,
    state text,
    release_reason text,
    released_at timestamp with time zone,
    during tstzrange,
    booked_at timestamp with time zone,
    booked_by text,
    source text,
    leg_id uuid,
    stall_type text,
    stall_kind text
);

-- ===== phase7_reconcile_424242 =====
CREATE TABLE public.phase7_reconcile_424242 (
    id bigint,
    logged_at timestamp with time zone,
    sim_run_id uuid,
    booking_id uuid,
    vehicle_id uuid,
    stall_id uuid,
    purpose text,
    sim_clock timestamp with time zone,
    action text,
    reason text,
    blocked_by text,
    old_from timestamp with time zone,
    old_to timestamp with time zone,
    new_from timestamp with time zone,
    new_to timestamp with time zone,
    defer_seq integer,
    eta timestamp with time zone
);

-- ===== phase9_bookings_424242 =====
CREATE TABLE public.phase9_bookings_424242 (
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

-- ===== phase9_cert_424242 =====
CREATE TABLE public.phase9_cert_424242 (
    sim_run_id uuid,
    captured_at timestamp with time zone,
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text
);

-- ===== phase9_dispatches_424242 =====
CREATE TABLE public.phase9_dispatches_424242 (
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
    heartbeat_count integer
);

-- ===== phase9_eviction_evidence_424242 =====
CREATE TABLE public.phase9_eviction_evidence_424242 (
    event_id uuid,
    event_type text,
    entity_id uuid,
    severity text,
    occurred_at timestamp with time zone,
    payload jsonb
);

-- ===== phase9_fix1_pre_2026_08_02 =====
CREATE TABLE public.phase9_fix1_pre_2026_08_02 (
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
    captured_at timestamp with time zone
);

-- ===== phase9_fix2_prefix_bookings_424242 =====
CREATE TABLE public.phase9_fix2_prefix_bookings_424242 (
    booking_id uuid,
    sim_run_id uuid,
    vehicle_id uuid,
    stall_id uuid,
    leg_id uuid,
    purpose text,
    during tstzrange,
    state text,
    release_reason text,
    booked_at timestamp with time zone,
    released_at timestamp with time zone
);

-- ===== phase9_fix2_prefix_evidence_424242 =====
CREATE TABLE public.phase9_fix2_prefix_evidence_424242 (
    event_id uuid,
    sim_run_id uuid,
    event_type text,
    actor_id text,
    severity text,
    occurred_at timestamp with time zone,
    entity_id uuid,
    payload jsonb
);

-- ===== phase9_fix3_post_424242 =====
CREATE TABLE public.phase9_fix3_post_424242 (
    booking_id uuid,
    vehicle_id uuid,
    purpose text,
    state text,
    zone text,
    staging_role text,
    stall_code text,
    leg_id uuid,
    why text,
    source text,
    booked_by text,
    need_code text,
    t0 timestamp with time zone,
    t1 timestamp with time zone
);

-- ===== phase9_fix3_post_decisions_424242 =====
CREATE TABLE public.phase9_fix3_post_decisions_424242 (
    decision_id uuid,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    vehicle_id uuid,
    outcome_status text,
    src text,
    verb text,
    reason text,
    command_error text
);

-- ===== phase9_fix3_pre_424242 =====
CREATE TABLE public.phase9_fix3_pre_424242 (
    kind text,
    id text,
    a text,
    b_ text,
    c text,
    d text,
    e text,
    f text,
    t0 timestamp with time zone,
    t1 timestamp with time zone
);

-- ===== phase9_fix3_pre_decisions_424242 =====
CREATE TABLE public.phase9_fix3_pre_decisions_424242 (
    decision_id uuid,
    tick_seq bigint,
    sim_clock timestamp with time zone,
    outcome_status text,
    src text,
    verb text,
    reason text
);

-- ===== phase9_fix3_pre_legs_424242 =====
CREATE TABLE public.phase9_fix3_pre_legs_424242 (
    leg_id uuid,
    vehicle_id uuid,
    leg_type text,
    status text,
    to_stall_id uuid,
    seq integer
);

-- ===== phase9_prior_bookings_2026_08_03 =====
CREATE TABLE public.phase9_prior_bookings_2026_08_03 (
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

-- ===== phase9_prior_runs_2026_08_03 =====
CREATE TABLE public.phase9_prior_runs_2026_08_03 (
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

-- ===== phase9_visit_needs_424242 =====
CREATE TABLE public.phase9_visit_needs_424242 (
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

-- ===== prediction_accuracy_daily =====
CREATE TABLE public.prediction_accuracy_daily (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    depot_id uuid NOT NULL,
    report_date date NOT NULL,
    prediction_type text NOT NULL,
    time_horizon_hours integer,
    total_predictions integer NOT NULL DEFAULT 0,
    scored_predictions integer NOT NULL DEFAULT 0,
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
    actions_taken integer DEFAULT 0,
    actions_successful integer DEFAULT 0,
    actions_rolled_back integer DEFAULT 0,
    action_success_rate numeric(5,4),
    estimated_kwh_saved numeric(10,2),
    estimated_cost_saved numeric(10,2),
    demand_peaks_avoided integer DEFAULT 0,
    stall_conflicts_avoided integer DEFAULT 0,
    model_version integer,
    parameters_hash text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.prediction_accuracy_daily ADD CONSTRAINT prediction_accuracy_daily_depot_id_report_date_prediction_t_key UNIQUE (depot_id, report_date, prediction_type, time_horizon_hours);
ALTER TABLE public.prediction_accuracy_daily ADD CONSTRAINT prediction_accuracy_daily_pkey PRIMARY KEY (id);
ALTER TABLE public.prediction_accuracy_daily ADD CONSTRAINT prediction_accuracy_daily_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.prediction_accuracy_daily ADD CONSTRAINT prediction_accuracy_daily_trend_direction_check CHECK ((trend_direction = ANY (ARRAY['improving'::text, 'stable'::text, 'declining'::text, 'insufficient_data'::text])));
CREATE INDEX idx_accuracy_daily_depot_date ON public.prediction_accuracy_daily USING btree (depot_id, report_date DESC);
CREATE INDEX idx_accuracy_daily_trend ON public.prediction_accuracy_daily USING btree (depot_id, trend_direction, report_date DESC);
CREATE INDEX idx_accuracy_daily_type ON public.prediction_accuracy_daily USING btree (depot_id, prediction_type, report_date DESC);

-- ===== prediction_explanations =====
CREATE TABLE public.prediction_explanations (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    prediction_id uuid NOT NULL,
    top_similar_snapshots jsonb NOT NULL DEFAULT '[]'::jsonb,
    external_factors_used jsonb NOT NULL DEFAULT '[]'::jsonb,
    feature_importance jsonb NOT NULL DEFAULT '{}'::jsonb,
    sensitivity_analysis jsonb DEFAULT '{}'::jsonb,
    confidence_decomposition jsonb NOT NULL DEFAULT '{}'::jsonb,
    risk_factor_weights jsonb DEFAULT '{}'::jsonb,
    model_version_id uuid,
    ab_test_id uuid,
    ab_test_variant text,
    generation_method text NOT NULL DEFAULT 'at_prediction_time'::text,
    generated_at timestamp with time zone NOT NULL DEFAULT now(),
    generation_ms integer,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.prediction_explanations ADD CONSTRAINT prediction_explanations_pkey PRIMARY KEY (id);
ALTER TABLE public.prediction_explanations ADD CONSTRAINT prediction_explanations_prediction_id_key UNIQUE (prediction_id);
ALTER TABLE public.prediction_explanations ADD CONSTRAINT prediction_explanations_ab_test_id_fkey FOREIGN KEY (ab_test_id) REFERENCES ab_tests(id);
ALTER TABLE public.prediction_explanations ADD CONSTRAINT prediction_explanations_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES model_versions(id);
ALTER TABLE public.prediction_explanations ADD CONSTRAINT prediction_explanations_prediction_id_fkey FOREIGN KEY (prediction_id) REFERENCES ottoq_predictions(id) ON DELETE CASCADE;
ALTER TABLE public.prediction_explanations ADD CONSTRAINT prediction_explanations_generation_method_check CHECK ((generation_method = ANY (ARRAY['at_prediction_time'::text, 'on_demand'::text, 'cached_recomputed'::text])));
CREATE INDEX idx_explanations_model ON public.prediction_explanations USING btree (model_version_id);
CREATE INDEX idx_explanations_prediction ON public.prediction_explanations USING btree (prediction_id);

-- ===== prediction_outcomes =====
CREATE TABLE public.prediction_outcomes (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    prediction_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    predicted_value jsonb NOT NULL,
    actual_value jsonb NOT NULL,
    accuracy_score numeric(5,4) NOT NULL,
    scoring_method text NOT NULL,
    time_horizon_hours integer NOT NULL,
    prediction_type text NOT NULL,
    scored_at timestamp with time zone NOT NULL DEFAULT now(),
    scoring_delay_ms integer,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.prediction_outcomes ADD CONSTRAINT prediction_outcomes_pkey PRIMARY KEY (id);
ALTER TABLE public.prediction_outcomes ADD CONSTRAINT prediction_outcomes_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.prediction_outcomes ADD CONSTRAINT prediction_outcomes_prediction_id_fkey FOREIGN KEY (prediction_id) REFERENCES ottoq_predictions(id) ON DELETE CASCADE;
ALTER TABLE public.prediction_outcomes ADD CONSTRAINT prediction_outcomes_accuracy_score_check CHECK (((accuracy_score >= (0)::numeric) AND (accuracy_score <= (1)::numeric)));
ALTER TABLE public.prediction_outcomes ADD CONSTRAINT prediction_outcomes_scoring_method_check CHECK ((scoring_method = ANY (ARRAY['exact_match'::text, 'range_check'::text, 'mape'::text, 'directional'::text, 'rmse_normalized'::text])));
CREATE INDEX idx_prediction_outcomes_accuracy ON public.prediction_outcomes USING btree (depot_id, accuracy_score, scored_at DESC);
CREATE INDEX idx_prediction_outcomes_depot_time ON public.prediction_outcomes USING btree (depot_id, scored_at DESC);
CREATE INDEX idx_prediction_outcomes_prediction ON public.prediction_outcomes USING btree (prediction_id);
CREATE INDEX idx_prediction_outcomes_type ON public.prediction_outcomes USING btree (depot_id, prediction_type, scored_at DESC);

-- ===== progression_decisions =====
CREATE TABLE public.progression_decisions (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id uuid NOT NULL,
    task_id uuid,
    schedule_id uuid,
    depot_id uuid NOT NULL,
    fleet_operator_id uuid,
    decided_at timestamp with time zone NOT NULL DEFAULT now(),
    decision text NOT NULL,
    triggered_by text NOT NULL,
    triggered_by_id text,
    from_stall_id uuid,
    to_stall_id uuid,
    from_task_sequence integer,
    to_task_sequence integer,
    audit_note text,
    latency_ms integer,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.progression_decisions ADD CONSTRAINT progression_decisions_pkey PRIMARY KEY (id);
ALTER TABLE public.progression_decisions ADD CONSTRAINT progression_decisions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.progression_decisions ADD CONSTRAINT progression_decisions_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
ALTER TABLE public.progression_decisions ADD CONSTRAINT progression_decisions_from_stall_id_fkey FOREIGN KEY (from_stall_id) REFERENCES stalls(id) ON DELETE SET NULL;
ALTER TABLE public.progression_decisions ADD CONSTRAINT progression_decisions_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES vehicle_schedules(id) ON DELETE CASCADE;
ALTER TABLE public.progression_decisions ADD CONSTRAINT progression_decisions_task_id_fkey FOREIGN KEY (task_id) REFERENCES schedule_tasks(id) ON DELETE SET NULL;
ALTER TABLE public.progression_decisions ADD CONSTRAINT progression_decisions_to_stall_id_fkey FOREIGN KEY (to_stall_id) REFERENCES stalls(id) ON DELETE SET NULL;
ALTER TABLE public.progression_decisions ADD CONSTRAINT progression_decisions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
ALTER TABLE public.progression_decisions ADD CONSTRAINT progression_decisions_decision_check CHECK ((decision = ANY (ARRAY['auto_advanced'::text, 'all_services_complete'::text, 'oem_gate_pending'::text, 'oem_accepted'::text, 'oem_rejected'::text, 'oem_timeout_auto_accepted'::text, 'oem_timeout_held'::text, 'oem_timeout_escalated'::text, 'oem_flagged_mid_flow'::text, 'tech_override_skip'::text, 'tech_override_reroute'::text, 'tech_override_hold'::text, 'tech_override_defer'::text, 'tech_override_flag_exception'::text, 'tech_override_escalate'::text, 'abnormality_blocked'::text, 'abnormality_resolved'::text, 'held_stall_unavailable'::text, 'overnight_staged'::text, 'scheduled_release_fired'::text, 'scheduled_release_deferred'::text])));
ALTER TABLE public.progression_decisions ADD CONSTRAINT progression_decisions_triggered_by_check CHECK ((triggered_by = ANY (ARRAY['tech_confirm'::text, 'ocpp_stop'::text, 'oem_webhook'::text, 'oem_console'::text, 'virtual_driver'::text, 'scheduler'::text, 'manual'::text, 'system'::text])));
CREATE INDEX idx_prog_decisions_decision ON public.progression_decisions USING btree (decision, decided_at DESC);
CREATE INDEX idx_prog_decisions_depot ON public.progression_decisions USING btree (depot_id, decided_at DESC);
CREATE INDEX idx_prog_decisions_fleet ON public.progression_decisions USING btree (fleet_operator_id, decided_at DESC) WHERE (fleet_operator_id IS NOT NULL);
CREATE INDEX idx_prog_decisions_schedule ON public.progression_decisions USING btree (schedule_id, decided_at) WHERE (schedule_id IS NOT NULL);
CREATE INDEX idx_prog_decisions_vehicle ON public.progression_decisions USING btree (vehicle_id, decided_at DESC);

-- ===== retail_members =====
CREATE TABLE public.retail_members (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    auth_user_id uuid,
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text NOT NULL,
    phone text,
    membership_tier text NOT NULL DEFAULT 'standard'::text,
    membership_status text NOT NULL DEFAULT 'active'::text,
    home_depot_id uuid,
    auto_queue_enabled boolean NOT NULL DEFAULT true,
    preferred_days jsonb DEFAULT '[]'::jsonb,
    preferred_time_window jsonb DEFAULT '{}'::jsonb,
    notification_preferences jsonb NOT NULL DEFAULT '{"vehicle_ready": ["in_app", "sms"], "weekly_summary": ["email"], "vehicle_received": ["in_app"], "booking_confirmed": ["in_app"], "service_in_progress": ["in_app"]}'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.retail_members ADD CONSTRAINT retail_members_email_key UNIQUE (email);
ALTER TABLE public.retail_members ADD CONSTRAINT retail_members_pkey PRIMARY KEY (id);
ALTER TABLE public.retail_members ADD CONSTRAINT retail_members_home_depot_id_fkey FOREIGN KEY (home_depot_id) REFERENCES depots(id);
ALTER TABLE public.retail_members ADD CONSTRAINT retail_members_membership_status_check CHECK ((membership_status = ANY (ARRAY['active'::text, 'paused'::text, 'cancelled'::text, 'past_due'::text])));
ALTER TABLE public.retail_members ADD CONSTRAINT retail_members_membership_tier_check CHECK ((membership_tier = ANY (ARRAY['standard'::text, 'pro'::text])));
CREATE INDEX idx_retail_members_auth ON public.retail_members USING btree (auth_user_id);
CREATE INDEX idx_retail_members_depot ON public.retail_members USING btree (home_depot_id);

-- ===== schedule_modifications =====
CREATE TABLE public.schedule_modifications (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    vehicle_schedule_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    modification_type modification_type NOT NULL,
    requested_by trigger_source NOT NULL,
    requested_by_user_id uuid,
    previous_values jsonb NOT NULL,
    new_values jsonb NOT NULL,
    deadline_at timestamp with time zone,
    deadline_passed boolean NOT NULL DEFAULT false,
    override_required boolean NOT NULL DEFAULT false,
    override_fee numeric(10,2) DEFAULT 0,
    override_approved boolean,
    override_approved_by uuid,
    vehicles_affected integer DEFAULT 0,
    stalls_reassigned integer DEFAULT 0,
    wave_changes integer DEFAULT 0,
    demand_impact_kw numeric(8,2) DEFAULT 0,
    reason text,
    status text NOT NULL DEFAULT 'applied'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.schedule_modifications ADD CONSTRAINT schedule_modifications_pkey PRIMARY KEY (id);
ALTER TABLE public.schedule_modifications ADD CONSTRAINT schedule_modifications_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.schedule_modifications ADD CONSTRAINT schedule_modifications_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id);
ALTER TABLE public.schedule_modifications ADD CONSTRAINT schedule_modifications_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES vehicle_schedules(id) ON DELETE CASCADE;
ALTER TABLE public.schedule_modifications ADD CONSTRAINT schedule_modifications_status_check CHECK ((status = ANY (ARRAY['requested'::text, 'approved'::text, 'applied'::text, 'rejected'::text, 'rolled_back'::text])));
CREATE INDEX idx_modifications_depot ON public.schedule_modifications USING btree (depot_id, created_at DESC);
CREATE INDEX idx_modifications_schedule ON public.schedule_modifications USING btree (vehicle_schedule_id, created_at DESC);

-- ===== schedule_tasks =====
CREATE TABLE public.schedule_tasks (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
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
    post_completion_buffer_seconds integer NOT NULL DEFAULT 30,
    status task_status NOT NULL DEFAULT 'pending'::task_status,
    confirmed_by_user_id uuid,
    confirmed_by_role staff_role,
    confirmation_timestamp timestamp with time zone,
    target_soc integer,
    soc_at_start integer,
    soc_at_end integer,
    energy_delivered_kwh numeric(8,3),
    peak_charge_rate_kw numeric(6,2),
    demand_paused boolean DEFAULT false,
    notes text,
    exception_id uuid,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    oem_acceptance_state text NOT NULL DEFAULT 'not_required'::text,
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
    abnormality_flagged boolean NOT NULL DEFAULT false,
    abnormality_flagged_at timestamp with time zone,
    abnormality_flagged_by_role text,
    abnormality_flagged_by_id text,
    abnormality_resolved_at timestamp with time zone,
    abnormality_resolved_by_role text,
    abnormality_resolution_note text,
    scheduled_release_at timestamp with time zone,
    scheduled_release_fired_at timestamp with time zone,
    is_overnight_stage boolean NOT NULL DEFAULT false,
    original_sequence_order integer,
    reordered_at timestamp with time zone,
    service_code text,
    schedule_id uuid
);
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_pkey PRIMARY KEY (id);
ALTER TABLE public.schedule_tasks ADD CONSTRAINT fk_task_exception FOREIGN KEY (exception_id) REFERENCES exceptions(id) ON DELETE SET NULL;
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_actual_stall_id_fkey FOREIGN KEY (actual_stall_id) REFERENCES stalls(id);
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_assigned_stall_id_fkey FOREIGN KEY (assigned_stall_id) REFERENCES stalls(id);
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_service_definition_id_fkey FOREIGN KEY (service_definition_id) REFERENCES service_definitions(id);
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_tech_override_next_stall_id_fkey FOREIGN KEY (tech_override_next_stall_id) REFERENCES stalls(id);
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES vehicle_schedules(id) ON DELETE CASCADE;
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_abnormality_flagged_by_role_check CHECK (((abnormality_flagged_by_role IS NULL) OR (abnormality_flagged_by_role = ANY (ARRAY['tech'::text, 'oem'::text, 'system'::text]))));
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_abnormality_resolved_by_role_check CHECK (((abnormality_resolved_by_role IS NULL) OR (abnormality_resolved_by_role = ANY (ARRAY['tech'::text, 'oem'::text, 'system'::text]))));
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_oem_acceptance_state_check CHECK ((oem_acceptance_state = ANY (ARRAY['not_required'::text, 'pending'::text, 'accepted'::text, 'rejected'::text, 'auto_accepted_on_timeout'::text, 'held_on_timeout'::text, 'escalated_on_timeout'::text])));
ALTER TABLE public.schedule_tasks ADD CONSTRAINT schedule_tasks_tech_override_action_check CHECK (((tech_override_action IS NULL) OR (tech_override_action = ANY (ARRAY['skip'::text, 'reroute'::text, 'hold'::text, 'flag_exception'::text, 'defer'::text, 'escalate'::text]))));
CREATE INDEX idx_schedule_tasks_abnormality_open ON public.schedule_tasks USING btree (vehicle_id, depot_id) WHERE ((abnormality_flagged = true) AND (abnormality_resolved_at IS NULL));
CREATE INDEX idx_schedule_tasks_oem_pending ON public.schedule_tasks USING btree (oem_acceptance_expires_at) WHERE (oem_acceptance_state = 'pending'::text);
CREATE INDEX idx_schedule_tasks_overnight_release ON public.schedule_tasks USING btree (scheduled_release_at) WHERE ((is_overnight_stage = true) AND (scheduled_release_fired_at IS NULL));
CREATE INDEX idx_schedule_tasks_schedule_id ON public.schedule_tasks USING btree (schedule_id);
CREATE INDEX idx_tasks_schedule ON public.schedule_tasks USING btree (vehicle_schedule_id);
CREATE INDEX idx_tasks_sequence ON public.schedule_tasks USING btree (vehicle_schedule_id, sequence_order);
CREATE INDEX idx_tasks_stall ON public.schedule_tasks USING btree (assigned_stall_id);
CREATE INDEX idx_tasks_status ON public.schedule_tasks USING btree (status);
CREATE INDEX idx_tasks_timing ON public.schedule_tasks USING btree (scheduled_start, scheduled_end);
CREATE INDEX idx_tasks_vehicle ON public.schedule_tasks USING btree (vehicle_id);

-- ===== service_cadence_policy =====
CREATE TABLE public.service_cadence_policy (
    svc text NOT NULL,
    display_name text,
    category text,
    lane text,
    est_min_default numeric,
    interval_h numeric,
    interval_km numeric,
    cadence_kind text,
    due_soon_ratio numeric DEFAULT 0.75,
    due_ratio numeric DEFAULT 1.00,
    overdue_ratio numeric DEFAULT 1.25,
    critical_ratio numeric DEFAULT 1.60,
    must_do_at text NOT NULL DEFAULT 'never'::text,
    lane_stalls integer,
    seed_phase_max numeric,
    observed_clear_pct numeric,
    sequence_order integer DEFAULT 50,
    notes text,
    is_active boolean NOT NULL DEFAULT true,
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.service_cadence_policy ADD CONSTRAINT service_cadence_policy_pkey PRIMARY KEY (svc);
CREATE INDEX service_cadence_policy_active_idx ON public.service_cadence_policy USING btree (is_active, svc);

-- ===== service_definitions =====
CREATE TABLE public.service_definitions (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    name text NOT NULL,
    code text NOT NULL,
    description text,
    stall_type_required stall_type NOT NULL,
    estimated_duration_minutes integer NOT NULL,
    min_duration_minutes integer,
    max_duration_minutes integer,
    is_duration_variable boolean NOT NULL DEFAULT false,
    available_for jsonb NOT NULL DEFAULT '["autonomous", "retail"]'::jsonb,
    default_sequence_order integer DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.service_definitions ADD CONSTRAINT service_definitions_depot_id_code_key UNIQUE (depot_id, code);
ALTER TABLE public.service_definitions ADD CONSTRAINT service_definitions_pkey PRIMARY KEY (id);
ALTER TABLE public.service_definitions ADD CONSTRAINT service_definitions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;

-- ===== site_energy_snapshots =====
CREATE TABLE public.site_energy_snapshots (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    timestamp timestamp with time zone NOT NULL DEFAULT now(),
    grid_import_kw numeric(10,2) NOT NULL DEFAULT 0,
    grid_export_kw numeric(10,2) NOT NULL DEFAULT 0,
    solar_generation_kw numeric(10,2) DEFAULT 0,
    bess_output_kw numeric(10,2) DEFAULT 0,
    total_ev_charging_kw numeric(10,2) NOT NULL DEFAULT 0,
    building_load_kw numeric(10,2) DEFAULT 0,
    lighting_load_kw numeric(10,2) DEFAULT 0,
    peak_demand_kw_15min numeric(10,2) NOT NULL DEFAULT 0,
    billing_period_peak_kw numeric(10,2) DEFAULT 0,
    current_tariff_label tariff_label,
    current_rate_per_kwh numeric(8,4),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    sim_run_id uuid,
    data_source text DEFAULT 'twin'::text,
    lmp_usd_mwh numeric,
    carbon_gco2_kwh numeric
);
ALTER TABLE public.site_energy_snapshots ADD CONSTRAINT site_energy_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.site_energy_snapshots ADD CONSTRAINT site_energy_snapshots_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
CREATE INDEX idx_site_energy_depot_time ON public.site_energy_snapshots USING btree (depot_id, "timestamp" DESC);
CREATE INDEX idx_site_energy_snapshots_sim_run ON public.site_energy_snapshots USING btree (sim_run_id, "timestamp");

-- ===== smoke890_bookings_2026_08_03 =====
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

-- ===== space_conflict_ledger =====
CREATE TABLE public.space_conflict_ledger (
    conflict_id bigint NOT NULL,
    recorded_at timestamp with time zone NOT NULL DEFAULT now(),
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
ALTER TABLE public.space_conflict_ledger ADD CONSTRAINT space_conflict_ledger_pkey PRIMARY KEY (conflict_id);
CREATE INDEX space_conflict_ledger_run_idx ON public.space_conflict_ledger USING btree (sim_run_id, recorded_at DESC);
CREATE INDEX space_conflict_ledger_stall_idx ON public.space_conflict_ledger USING btree (stall_id);

-- ===== spatial_ref_sys =====
CREATE TABLE public.spatial_ref_sys (
    srid integer NOT NULL,
    auth_name character varying(256),
    auth_srid integer,
    srtext character varying(2048),
    proj4text character varying(2048)
);
ALTER TABLE public.spatial_ref_sys ADD CONSTRAINT spatial_ref_sys_pkey PRIMARY KEY (srid);
ALTER TABLE public.spatial_ref_sys ADD CONSTRAINT spatial_ref_sys_srid_check CHECK (((srid > 0) AND (srid <= 998999)));

-- ===== staff_users =====
CREATE TABLE public.staff_users (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    auth_user_id uuid,
    depot_id uuid NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text NOT NULL,
    phone text,
    role staff_role NOT NULL,
    display_name text,
    is_on_shift boolean NOT NULL DEFAULT false,
    current_zone text,
    shift_start timestamp with time zone,
    shift_end timestamp with time zone,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.staff_users ADD CONSTRAINT staff_users_email_key UNIQUE (email);
ALTER TABLE public.staff_users ADD CONSTRAINT staff_users_pkey PRIMARY KEY (id);
ALTER TABLE public.staff_users ADD CONSTRAINT staff_users_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
CREATE INDEX idx_staff_depot ON public.staff_users USING btree (depot_id);
CREATE INDEX idx_staff_role ON public.staff_users USING btree (depot_id, role);
CREATE INDEX idx_staff_shift ON public.staff_users USING btree (is_on_shift) WHERE (is_on_shift = true);

-- ===== stalls =====
CREATE TABLE public.stalls (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    stall_code text NOT NULL,
    stall_type stall_type NOT NULL,
    display_name text,
    relative_x double precision DEFAULT 0,
    relative_y double precision DEFAULT 0,
    heading_degrees smallint DEFAULT 0,
    absolute_lat double precision,
    absolute_lng double precision,
    absolute_point geography(Point,4326),
    distance_from_entrance integer DEFAULT 0,
    status text NOT NULL DEFAULT 'available'::text,
    current_vehicle_id uuid,
    equipment_config jsonb DEFAULT '{}'::jsonb,
    fiducial_marker_id text,
    uwb_beacon_id text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    zone text,
    reserved_for_mission_id uuid,
    connector_type text,
    connector_max_kw numeric,
    supported_inlet_types text[] DEFAULT '{}'::text[],
    ocpp_charger_id uuid,
    stall_kind text,
    canopy_code text,
    covered boolean NOT NULL DEFAULT false,
    stall_width_ft numeric,
    stall_depth_ft numeric,
    reserved_by uuid,
    reserved_at timestamp with time zone,
    reservation_expires_at timestamp with time zone,
    staging_role text
);
ALTER TABLE public.stalls ADD CONSTRAINT stalls_depot_id_stall_code_key UNIQUE (depot_id, stall_code);
ALTER TABLE public.stalls ADD CONSTRAINT stalls_pkey PRIMARY KEY (id);
ALTER TABLE public.stalls ADD CONSTRAINT fk_stalls_current_vehicle FOREIGN KEY (current_vehicle_id) REFERENCES vehicles(id) ON DELETE SET NULL;
ALTER TABLE public.stalls ADD CONSTRAINT stalls_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.stalls ADD CONSTRAINT stalls_ocpp_charger_id_fkey FOREIGN KEY (ocpp_charger_id) REFERENCES ottoq_ocpp_chargers(charger_id) ON DELETE SET NULL;
ALTER TABLE public.stalls ADD CONSTRAINT stalls_reserved_for_mission_id_fkey FOREIGN KEY (reserved_for_mission_id) REFERENCES ottow_missions(id) ON DELETE SET NULL;
ALTER TABLE public.stalls ADD CONSTRAINT stalls_connector_type_check CHECK (((connector_type IS NULL) OR (connector_type = ANY (ARRAY['CCS1'::text, 'CCS2'::text, 'NACS'::text, 'CHAdeMO'::text, 'Type1'::text, 'Type2'::text, 'Tesla_Proprietary'::text, 'MCS'::text, 'Multi'::text, 'NonCharging'::text, 'Other'::text]))));
ALTER TABLE public.stalls ADD CONSTRAINT stalls_heading_degrees_check CHECK (((heading_degrees >= 0) AND (heading_degrees < 360)));
ALTER TABLE public.stalls ADD CONSTRAINT stalls_staging_role_check CHECK ((staging_role = ANY (ARRAY['temp'::text, 'long'::text])));
ALTER TABLE public.stalls ADD CONSTRAINT stalls_status_check CHECK ((status = ANY (ARRAY['available'::text, 'occupied'::text, 'reserved'::text, 'maintenance'::text, 'closed'::text])));
CREATE INDEX idx_stalls_depot ON public.stalls USING btree (depot_id);
CREATE INDEX idx_stalls_distance ON public.stalls USING btree (depot_id, stall_type, distance_from_entrance DESC);
CREATE UNIQUE INDEX idx_stalls_one_vehicle_per_stall ON public.stalls USING btree (current_vehicle_id) WHERE (current_vehicle_id IS NOT NULL);
CREATE INDEX idx_stalls_reserved_by ON public.stalls USING btree (reserved_by) WHERE (reserved_by IS NOT NULL);
CREATE INDEX idx_stalls_reserved_mission ON public.stalls USING btree (reserved_for_mission_id) WHERE (reserved_for_mission_id IS NOT NULL);
CREATE INDEX idx_stalls_status ON public.stalls USING btree (depot_id, status);
CREATE INDEX idx_stalls_type ON public.stalls USING btree (depot_id, stall_type);

-- ===== tariff_schedules =====
CREATE TABLE public.tariff_schedules (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    name text NOT NULL,
    utility_provider text NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    billing_cycle_day integer NOT NULL DEFAULT 1,
    periods jsonb NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.tariff_schedules ADD CONSTRAINT tariff_schedules_pkey PRIMARY KEY (id);
ALTER TABLE public.tariff_schedules ADD CONSTRAINT tariff_schedules_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.tariff_schedules ADD CONSTRAINT tariff_schedules_billing_cycle_day_check CHECK (((billing_cycle_day >= 1) AND (billing_cycle_day <= 28)));
CREATE INDEX idx_tariffs_depot ON public.tariff_schedules USING btree (depot_id) WHERE (is_active = true);

-- ===== tuning_iterations =====
CREATE TABLE public.tuning_iterations (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    tuning_run_id uuid NOT NULL,
    iteration_number integer NOT NULL,
    parameters jsonb NOT NULL,
    objective_value numeric(12,6) NOT NULL,
    is_best_so_far boolean NOT NULL DEFAULT false,
    simplex_move_type text,
    simplex_size numeric(10,6),
    samples_evaluated integer NOT NULL DEFAULT 0,
    regularization_penalty numeric(10,6) DEFAULT 0,
    evaluation_details jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.tuning_iterations ADD CONSTRAINT tuning_iterations_pkey PRIMARY KEY (id);
ALTER TABLE public.tuning_iterations ADD CONSTRAINT tuning_iterations_tuning_run_id_iteration_number_key UNIQUE (tuning_run_id, iteration_number);
ALTER TABLE public.tuning_iterations ADD CONSTRAINT tuning_iterations_tuning_run_id_fkey FOREIGN KEY (tuning_run_id) REFERENCES model_tuning_runs(id) ON DELETE CASCADE;
ALTER TABLE public.tuning_iterations ADD CONSTRAINT tuning_iterations_simplex_move_type_check CHECK ((simplex_move_type = ANY (ARRAY['initial'::text, 'reflect'::text, 'expand'::text, 'contract_outside'::text, 'contract_inside'::text, 'shrink'::text])));
CREATE INDEX idx_tuning_iter_best ON public.tuning_iterations USING btree (tuning_run_id, is_best_so_far);
CREATE INDEX idx_tuning_iter_run ON public.tuning_iterations USING btree (tuning_run_id, iteration_number);

-- ===== vehicle_need_profile =====
CREATE TABLE public.vehicle_need_profile (
    vehicle_id uuid NOT NULL,
    profile_version text NOT NULL DEFAULT 'v1'::text,
    drawn_for_run uuid,
    drawn_seed bigint,
    drawn_at timestamp with time zone NOT NULL DEFAULT now(),
    drawn_at_sim_clock timestamp with time zone,
    battery_soh_pct numeric,
    battery_chemistry text DEFAULT 'NMC'::text,
    charge_accept_kw numeric,
    pack_temp_c numeric,
    dcfc_safe boolean NOT NULL DEFAULT true,
    dcfc_block_reason text,
    cell_balance_due_at timestamp with time zone,
    min_ready_soc_pct numeric,
    exterior_soil_level numeric,
    cabin_condition text DEFAULT 'clean'::text,
    last_wash_at timestamp with time zone,
    last_deep_clean_at timestamp with time zone,
    wash_interval_h numeric DEFAULT 72,
    deep_clean_interval_h numeric DEFAULT 336,
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
    open_fault_codes text[] NOT NULL DEFAULT '{}'::text[],
    worst_fault_severity smallint NOT NULL DEFAULT 99,
    tire_tread_mm numeric,
    tire_rotation_due_km numeric,
    brake_wear_pct numeric,
    next_deploy_at timestamp with time zone,
    priority_class text DEFAULT 'standard'::text,
    assigned_shift text DEFAULT 'flex'::text,
    item_retrieval_pending boolean NOT NULL DEFAULT false,
    item_reported_at timestamp with time zone,
    item_description text,
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.vehicle_need_profile ADD CONSTRAINT vehicle_need_profile_pkey PRIMARY KEY (vehicle_id);
ALTER TABLE public.vehicle_need_profile ADD CONSTRAINT vehicle_need_profile_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
CREATE INDEX vehicle_need_profile_next_deploy_idx ON public.vehicle_need_profile USING btree (next_deploy_at);
CREATE INDEX vehicle_need_profile_run_idx ON public.vehicle_need_profile USING btree (drawn_for_run);

-- ===== vehicle_schedules =====
CREATE TABLE public.vehicle_schedules (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    vehicle_id uuid NOT NULL,
    depot_id uuid NOT NULL,
    wave_id uuid,
    scheduled_date date NOT NULL,
    arrival_time timestamp with time zone NOT NULL,
    departure_time timestamp with time zone,
    priority priority_tier NOT NULL DEFAULT 'standard'::priority_tier,
    is_priority_override boolean NOT NULL DEFAULT false,
    override_fee numeric(10,2) DEFAULT 0,
    override_reason text,
    status schedule_status NOT NULL DEFAULT 'draft'::schedule_status,
    actual_arrival timestamp with time zone,
    actual_departure timestamp with time zone,
    planned_services jsonb NOT NULL DEFAULT '[]'::jsonb,
    original_arrival_time timestamp with time zone,
    modification_count integer NOT NULL DEFAULT 0,
    last_modified_by trigger_source,
    modification_deadline timestamp with time zone,
    booking_reference text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.vehicle_schedules ADD CONSTRAINT vehicle_schedules_pkey PRIMARY KEY (id);
ALTER TABLE public.vehicle_schedules ADD CONSTRAINT vehicle_schedules_vehicle_id_scheduled_date_key UNIQUE (vehicle_id, scheduled_date);
ALTER TABLE public.vehicle_schedules ADD CONSTRAINT vehicle_schedules_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.vehicle_schedules ADD CONSTRAINT vehicle_schedules_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
ALTER TABLE public.vehicle_schedules ADD CONSTRAINT vehicle_schedules_wave_id_fkey FOREIGN KEY (wave_id) REFERENCES waves(id) ON DELETE SET NULL;
CREATE INDEX idx_schedules_arrival ON public.vehicle_schedules USING btree (arrival_time);
CREATE INDEX idx_schedules_depot_date ON public.vehicle_schedules USING btree (depot_id, scheduled_date);
CREATE INDEX idx_schedules_status ON public.vehicle_schedules USING btree (status);
CREATE INDEX idx_schedules_vehicle ON public.vehicle_schedules USING btree (vehicle_id);
CREATE INDEX idx_schedules_wave ON public.vehicle_schedules USING btree (wave_id);

-- ===== vehicle_state_log =====
CREATE TABLE public.vehicle_state_log (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    vehicle_id uuid NOT NULL,
    depot_id uuid,
    previous_state vehicle_state,
    new_state vehicle_state NOT NULL,
    triggered_by trigger_source NOT NULL,
    trigger_user_id uuid,
    stall_id uuid,
    schedule_task_id uuid,
    vehicle_schedule_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_pkey PRIMARY KEY (id);
ALTER TABLE public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_schedule_task_id_fkey FOREIGN KEY (schedule_task_id) REFERENCES schedule_tasks(id);
ALTER TABLE public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES stalls(id);
ALTER TABLE public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
ALTER TABLE public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES vehicle_schedules(id);
CREATE INDEX idx_state_log_depot_time ON public.vehicle_state_log USING btree (depot_id, created_at DESC);
CREATE INDEX idx_state_log_state ON public.vehicle_state_log USING btree (new_state, created_at DESC);
CREATE INDEX idx_state_log_trigger ON public.vehicle_state_log USING btree (triggered_by);
CREATE INDEX idx_state_log_vehicle_time ON public.vehicle_state_log USING btree (vehicle_id, created_at DESC);

-- ===== vehicle_telemetry =====
CREATE TABLE public.vehicle_telemetry (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    vehicle_id uuid NOT NULL,
    depot_id uuid,
    timestamp timestamp with time zone NOT NULL DEFAULT now(),
    soc_percent integer,
    odometer_miles integer,
    tire_pressure jsonb,
    battery_temp_f numeric(5,1),
    ambient_temp_f numeric(5,1),
    location_lat double precision,
    location_lng double precision,
    is_occupied boolean,
    speed_mph numeric(5,1),
    source text DEFAULT 'vehicle_api'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.vehicle_telemetry ADD CONSTRAINT vehicle_telemetry_pkey PRIMARY KEY (id);
ALTER TABLE public.vehicle_telemetry ADD CONSTRAINT vehicle_telemetry_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id);
ALTER TABLE public.vehicle_telemetry ADD CONSTRAINT vehicle_telemetry_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;
CREATE INDEX idx_telemetry_depot ON public.vehicle_telemetry USING btree (depot_id, "timestamp" DESC);
CREATE INDEX idx_telemetry_vehicle_time ON public.vehicle_telemetry USING btree (vehicle_id, "timestamp" DESC);

-- ===== vehicles =====
CREATE TABLE public.vehicles (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    fleet_operator_id uuid,
    retail_member_id uuid,
    home_depot_id uuid NOT NULL,
    category vehicle_category NOT NULL,
    vin text,
    make text,
    model text,
    year smallint,
    license_plate text,
    color text,
    display_name text,
    battery_capacity_kwh numeric(6,2),
    max_charge_rate_kw numeric(6,2),
    connector_type text DEFAULT 'CCS'::text,
    target_soc integer NOT NULL DEFAULT 90,
    current_soc integer,
    min_soc_threshold integer DEFAULT 15,
    platform av_platform NOT NULL DEFAULT 'not_applicable'::av_platform,
    av_api_vehicle_id text,
    av_dispatch_capable boolean NOT NULL DEFAULT false,
    current_state vehicle_state NOT NULL DEFAULT 'offline'::vehicle_state,
    current_stall_id uuid,
    current_depot_id uuid,
    last_state_change timestamp with time zone,
    default_service_sequence jsonb,
    config jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    inlet_type text,
    inlet_max_kw numeric,
    current_soc_updated_at timestamp with time zone,
    current_soc_source text,
    owning_sim_run_id uuid
);
ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_pkey PRIMARY KEY (id);
ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_vin_key UNIQUE (vin);
ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_current_depot_id_fkey FOREIGN KEY (current_depot_id) REFERENCES depots(id);
ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_current_stall_id_fkey FOREIGN KEY (current_stall_id) REFERENCES stalls(id) ON DELETE SET NULL;
ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES fleet_operators(id) ON DELETE SET NULL;
ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_home_depot_id_fkey FOREIGN KEY (home_depot_id) REFERENCES depots(id);
ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_retail_member_id_fkey FOREIGN KEY (retail_member_id) REFERENCES retail_members(id) ON DELETE SET NULL;
ALTER TABLE public.vehicles ADD CONSTRAINT vehicle_owner_check CHECK ((((fleet_operator_id IS NOT NULL) AND (retail_member_id IS NULL) AND (category = 'autonomous'::vehicle_category)) OR ((fleet_operator_id IS NULL) AND (retail_member_id IS NOT NULL) AND (category = 'retail'::vehicle_category)) OR ((fleet_operator_id IS NULL) AND (retail_member_id IS NULL))));
ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_current_soc_source_check CHECK (((current_soc_source IS NULL) OR (current_soc_source = ANY (ARRAY['oem_telemetry'::text, 'ocpp_meter'::text, 'manual'::text, 'estimated'::text]))));
ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_inlet_type_check CHECK (((inlet_type IS NULL) OR (inlet_type = ANY (ARRAY['CCS1'::text, 'CCS2'::text, 'NACS'::text, 'CHAdeMO'::text, 'Type1'::text, 'Type2'::text, 'Tesla_Proprietary'::text, 'MCS'::text, 'Other'::text]))));
ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_target_soc_check CHECK (((target_soc >= 20) AND (target_soc <= 100)));
CREATE INDEX idx_vehicles_active ON public.vehicles USING btree (is_active) WHERE (is_active = true);
CREATE INDEX idx_vehicles_depot ON public.vehicles USING btree (home_depot_id);
CREATE INDEX idx_vehicles_fleet ON public.vehicles USING btree (fleet_operator_id) WHERE (fleet_operator_id IS NOT NULL);
CREATE INDEX idx_vehicles_owning_sim_run ON public.vehicles USING btree (owning_sim_run_id);
CREATE INDEX idx_vehicles_retail ON public.vehicles USING btree (retail_member_id) WHERE (retail_member_id IS NOT NULL);
CREATE INDEX idx_vehicles_state ON public.vehicles USING btree (current_state);

-- ===== waves =====
CREATE TABLE public.waves (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    depot_id uuid NOT NULL,
    wave_code text NOT NULL,
    scheduled_date date NOT NULL,
    arrival_window_start timestamp with time zone NOT NULL,
    arrival_window_end timestamp with time zone NOT NULL,
    departure_window_start timestamp with time zone,
    departure_window_end timestamp with time zone,
    vehicle_count integer NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'planned'::text,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.waves ADD CONSTRAINT waves_depot_id_wave_code_key UNIQUE (depot_id, wave_code);
ALTER TABLE public.waves ADD CONSTRAINT waves_pkey PRIMARY KEY (id);
ALTER TABLE public.waves ADD CONSTRAINT waves_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES depots(id) ON DELETE CASCADE;
ALTER TABLE public.waves ADD CONSTRAINT waves_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'arriving'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])));
CREATE INDEX idx_waves_depot_date ON public.waves USING btree (depot_id, scheduled_date);
CREATE INDEX idx_waves_status ON public.waves USING btree (status);

-- ===== workload_determinism_proof_2026_08_02 =====
CREATE TABLE public.workload_determinism_proof_2026_08_02 (
    id bigint NOT NULL DEFAULT nextval('workload_determinism_proof_2026_08_02_id_seq'::regclass),
    leg text NOT NULL,
    run_id uuid NOT NULL,
    seed bigint,
    section text,
    metric text,
    value numeric,
    denom numeric,
    per_arrival numeric,
    detail text,
    captured_at timestamp with time zone NOT NULL DEFAULT now(),
    captured_after_stop boolean NOT NULL DEFAULT true
);
ALTER TABLE public.workload_determinism_proof_2026_08_02 ADD CONSTRAINT workload_determinism_proof_2026_08_02_pkey PRIMARY KEY (id);


-- ============================================================================
-- VIEWS (schema: public)
-- ============================================================================

-- ===== VIEW: calendar_ledger_integrity =====
CREATE OR REPLACE VIEW public.calendar_ledger_integrity AS
 SELECT b.sim_run_id,
    b.booking_id,
    b.vehicle_id,
    b.stall_id,
    s.stall_type::text AS stall_type,
    b.state,
    b.release_reason,
    b.booked_by,
    b.source,
    b.decision_id,
    b.decision_id IS NOT NULL AS backed_by_key,
    b.source IS NOT NULL AS has_provenance,
    (EXISTS ( SELECT 1
           FROM ottoq_decisions d
          WHERE d.sim_run_id = b.sim_run_id AND d.outcome_status = 'enacted'::text AND d.entity_id = b.vehicle_id AND NULLIF(d.enacted_action ->> 'stall_id'::text, ''::text)::uuid = b.stall_id)) AS backed_by_inference,
    b.booked_by = 'otto_q_enacted'::text AND b.decision_id IS NULL AND b.source IS NULL AND NOT (EXISTS ( SELECT 1
           FROM ottoq_decisions d
          WHERE d.sim_run_id = b.sim_run_id AND d.outcome_status = 'enacted'::text AND d.entity_id = b.vehicle_id AND NULLIF(d.enacted_action ->> 'stall_id'::text, ''::text)::uuid = b.stall_id)) AS is_phantom
   FROM ottoq_stall_bookings b
     JOIN stalls s ON s.id = b.stall_id;

-- ===== VIEW: geography_columns =====
CREATE OR REPLACE VIEW public.geography_columns AS
 SELECT current_database() AS f_table_catalog,
    n.nspname AS f_table_schema,
    c.relname AS f_table_name,
    a.attname AS f_geography_column,
    postgis_typmod_dims(a.atttypmod) AS coord_dimension,
    postgis_typmod_srid(a.atttypmod) AS srid,
    postgis_typmod_type(a.atttypmod) AS type
   FROM pg_class c,
    pg_attribute a,
    pg_type t,
    pg_namespace n
  WHERE t.typname = 'geography'::name AND a.attisdropped = false AND a.atttypid = t.oid AND a.attrelid = c.oid AND c.relnamespace = n.oid AND (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", 'm'::"char", 'f'::"char", 'p'::"char"])) AND NOT pg_is_other_temp_schema(c.relnamespace) AND has_table_privilege(c.oid, 'SELECT'::text);

-- ===== VIEW: geometry_columns =====
CREATE OR REPLACE VIEW public.geometry_columns AS
 SELECT current_database()::character varying(256) AS f_table_catalog,
    n.nspname AS f_table_schema,
    c.relname AS f_table_name,
    a.attname AS f_geometry_column,
    COALESCE(postgis_typmod_dims(a.atttypmod), sn.ndims, 2) AS coord_dimension,
    COALESCE(NULLIF(postgis_typmod_srid(a.atttypmod), 0), sr.srid, 0) AS srid,
    replace(replace(COALESCE(NULLIF(upper(postgis_typmod_type(a.atttypmod)), 'GEOMETRY'::text), st.type, 'GEOMETRY'::text), 'ZM'::text, ''::text), 'Z'::text, ''::text)::character varying(30) AS type
   FROM pg_class c
     JOIN pg_attribute a ON a.attrelid = c.oid AND NOT a.attisdropped
     JOIN pg_namespace n ON c.relnamespace = n.oid
     JOIN pg_type t ON a.atttypid = t.oid
     LEFT JOIN ( SELECT s.connamespace,
            s.conrelid,
            s.conkey,
            replace(split_part(s.consrc, ''''::text, 2), ')'::text, ''::text) AS type
           FROM ( SELECT pg_constraint.connamespace,
                    pg_constraint.conrelid,
                    pg_constraint.conkey,
                    pg_get_constraintdef(pg_constraint.oid) AS consrc
                   FROM pg_constraint) s
          WHERE s.consrc ~~* '%geometrytype(% = %'::text) st ON st.connamespace = n.oid AND st.conrelid = c.oid AND (a.attnum = ANY (st.conkey))
     LEFT JOIN ( SELECT s.connamespace,
            s.conrelid,
            s.conkey,
            replace(split_part(s.consrc, ' = '::text, 2), ')'::text, ''::text)::integer AS ndims
           FROM ( SELECT pg_constraint.connamespace,
                    pg_constraint.conrelid,
                    pg_constraint.conkey,
                    pg_get_constraintdef(pg_constraint.oid) AS consrc
                   FROM pg_constraint) s
          WHERE s.consrc ~~* '%ndims(% = %'::text) sn ON sn.connamespace = n.oid AND sn.conrelid = c.oid AND (a.attnum = ANY (sn.conkey))
     LEFT JOIN ( SELECT s.connamespace,
            s.conrelid,
            s.conkey,
            replace(replace(split_part(s.consrc, ' = '::text, 2), ')'::text, ''::text), '('::text, ''::text)::integer AS srid
           FROM ( SELECT pg_constraint.connamespace,
                    pg_constraint.conrelid,
                    pg_constraint.conkey,
                    pg_get_constraintdef(pg_constraint.oid) AS consrc
                   FROM pg_constraint) s
          WHERE s.consrc ~~* '%srid(% = %'::text) sr ON sr.connamespace = n.oid AND sr.conrelid = c.oid AND (a.attnum = ANY (sr.conkey))
  WHERE (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", 'm'::"char", 'f'::"char", 'p'::"char"])) AND NOT c.relname = 'raster_columns'::name AND t.typname = 'geometry'::name AND NOT pg_is_other_temp_schema(c.relnamespace) AND has_table_privilege(c.oid, 'SELECT'::text);

-- ===== VIEW: ottoq_accuracy_trend_daily =====
CREATE OR REPLACE VIEW public.ottoq_accuracy_trend_daily AS
 SELECT prediction_type,
    report_date,
    count(*) AS cells,
    sum(n_scored) AS total_scored,
    round(avg(mae), 3) AS avg_mae,
    round(avg(mape), 2) AS avg_mape,
    round(avg(coverage_80), 3) AS avg_coverage_80,
    round(avg(bias), 3) AS avg_bias
   FROM ottoq_prediction_accuracy_heatmap
  WHERE report_date >= (CURRENT_DATE - 30)
  GROUP BY prediction_type, report_date
  ORDER BY prediction_type, report_date DESC;

-- ===== VIEW: ottoq_accuracy_weak_spots =====
CREATE OR REPLACE VIEW public.ottoq_accuracy_weak_spots AS
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
   FROM ottoq_prediction_accuracy_heatmap
  WHERE report_date >= (CURRENT_DATE - 30) AND n_scored >= 20 AND (mape > 20::numeric OR coverage_80 < 0.6)
  ORDER BY mape DESC NULLS LAST, coverage_80;

-- ===== VIEW: ottoq_active_emergencies =====
CREATE OR REPLACE VIEW public.ottoq_active_emergencies AS
 SELECT i.invocation_id,
    i.protocol_code,
    p.title,
    p.category,
    p.severity,
    i.depot_id,
    i.triggered_at,
    EXTRACT(epoch FROM now() - i.triggered_at)::integer AS active_seconds,
    i.outcome,
    i.cascade_executed,
    i.correlation_id
   FROM ottoq_emergency_invocations i
     JOIN ottoq_emergency_protocols p ON p.protocol_code = i.protocol_code
  WHERE i.cleared_at IS NULL
  ORDER BY i.triggered_at DESC;

-- ===== VIEW: ottoq_active_layer2_recommendations =====
CREATE OR REPLACE VIEW public.ottoq_active_layer2_recommendations AS
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
    EXTRACT(epoch FROM now() - emitted_at)::integer AS age_seconds
   FROM ottoq_recommendations r
  WHERE (status = ANY (ARRAY['pending'::text, 'validating'::text, 'admitted'::text, 'shadow'::text])) AND (expires_at IS NULL OR expires_at > now())
  ORDER BY emitted_at DESC;

-- ===== VIEW: ottoq_active_predictions =====
CREATE OR REPLACE VIEW public.ottoq_active_predictions AS
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
   FROM ottoq_predictions p
  WHERE (status = ANY (ARRAY['proposed'::text, 'approved'::text, 'executing'::text])) AND (expires_at IS NULL OR expires_at > now());

-- ===== VIEW: ottoq_active_sim_runs =====
CREATE OR REPLACE VIEW public.ottoq_active_sim_runs AS
 SELECT sr.sim_run_id,
    sr.scenario_code,
    s.title AS scenario_title,
    s.category,
    sr.status,
    sr.depot_id,
    sr.sim_clock_start,
    sr.sim_clock_current,
    sr.sim_clock_end,
    round(100.0 * EXTRACT(epoch FROM sr.sim_clock_current - sr.sim_clock_start) / NULLIF(EXTRACT(epoch FROM sr.sim_clock_end - sr.sim_clock_start), 0::numeric), 1) AS pct_complete,
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
   FROM ottoq_sim_runs sr
     JOIN ottoq_scenarios s ON s.scenario_id = sr.scenario_id
  WHERE sr.status = ANY (ARRAY['running'::text, 'paused'::text, 'initializing'::text])
  ORDER BY sr.started_at DESC;

-- ===== VIEW: ottoq_approach_band =====
CREATE OR REPLACE VIEW public.ottoq_approach_band AS
 WITH r AS MATERIALIZED (
         SELECT rr.sim_run_id,
            rr.depot_id,
            rr.sim_clock_current,
            GREATEST(ottoq_policy_get(rr.sim_run_id, 'approach_freeze_minutes'::text, 10::numeric), 0::numeric) AS freeze_min,
            GREATEST(ottoq_policy_get(rr.sim_run_id, 'approach_horizon_minutes'::text, 30::numeric), 1::numeric) AS horizon_min,
            GREATEST(ottoq_policy_get(rr.sim_run_id, 'approach_stale_heartbeat_sec'::text, 90::numeric), 1::numeric) AS hb_sec
           FROM ottoq_sim_runs rr
          WHERE rr.depot_id IS NOT NULL
        ), d AS (
         SELECT DISTINCT ON (dd.sim_run_id, dd.vehicle_id) dd.sim_run_id,
            dd.vehicle_id,
            dd.scheduled_return_at,
            dd.status
           FROM ottoq_vehicle_dispatches dd
          WHERE (dd.status = ANY (ARRAY['active'::text, 'returning'::text])) AND dd.actual_return_at IS NULL
          ORDER BY dd.sim_run_id, dd.vehicle_id, dd.dispatched_at DESC NULLS LAST
        ), b AS (
         SELECT r.sim_run_id,
            r.depot_id,
            r.sim_clock_current,
            r.freeze_min,
            r.horizon_min,
            v.id AS vehicle_id,
            v.current_state::text AS current_state,
            v.category::text AS category,
            v.current_soc,
            v.inlet_type,
            v.inlet_max_kw,
            v.current_stall_id,
            d.scheduled_return_at,
                CASE
                    WHEN d.scheduled_return_at IS NOT NULL AND r.sim_clock_current IS NOT NULL THEN round(EXTRACT(epoch FROM d.scheduled_return_at - r.sim_clock_current) / 60.0, 2)
                    ELSE NULL::numeric
                END AS minutes_out,
            (EXISTS ( SELECT 1
                   FROM stalls s
                     LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
                  WHERE (s.reserved_by = v.id OR s.current_vehicle_id = v.id OR s.id = v.current_stall_id) AND ((s.status = ANY (ARRAY['maintenance'::text, 'closed'::text])) OR s.ocpp_charger_id IS NOT NULL AND (c.station_state = ANY (ARRAY['Faulted'::text, 'Unavailable'::text, 'Maintenance'::text])) OR s.ocpp_charger_id IS NOT NULL AND c.charger_id IS NULL OR s.ocpp_charger_id IS NOT NULL AND c.charger_id IS NOT NULL AND c.last_fault_code IS NOT NULL AND r.sim_clock_current IS NOT NULL AND c.last_heartbeat_at < (r.sim_clock_current - ((r.hb_sec || ' seconds'::text)::interval))))) AS c_hardware,
            (v.current_state::text = ANY (ARRAY['tow_requested'::text, 'out_of_service'::text, 'emergency_staged'::text])) OR (EXISTS ( SELECT 1
                   FROM ottoq_ops_approvals a
                  WHERE a.vehicle_id = v.id AND a.sim_run_id = r.sim_run_id AND a.status = 'pending'::text AND (a.approval_type = ANY (ARRAY['indepot_reassign'::text, 'tech_greenlight'::text])))) AS c_flag
           FROM r
             JOIN vehicles v ON v.home_depot_id = r.depot_id
             LEFT JOIN d ON d.sim_run_id = r.sim_run_id AND d.vehicle_id = v.id
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
            WHEN (current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) AND minutes_out IS NOT NULL AND minutes_out > freeze_min THEN 'A'::text
            WHEN c_hardware OR c_flag THEN 'C'::text
            ELSE 'B'::text
        END AS zone,
        CASE
            WHEN (current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) AND minutes_out IS NOT NULL AND minutes_out > freeze_min THEN
            CASE
                WHEN minutes_out <= horizon_min THEN 'open:in_cuopt_window'::text
                ELSE 'open:beyond_cuopt_horizon'::text
            END
            WHEN c_hardware THEN 'reopened:hardware_malfunction'::text
            WHEN c_flag THEN 'reopened:flag'::text
            WHEN (current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) AND minutes_out IS NOT NULL THEN 'frozen:approached'::text
            WHEN current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text]) THEN 'frozen:fail_closed_no_eta'::text
            WHEN current_state = ANY (ARRAY['arrived_at_gate'::text, 'staged_awaiting_service'::text, 'charging_dcfc'::text, 'charging_l2'::text, 'charge_complete_holding'::text, 'in_wash_bay'::text, 'in_detail_bay'::text, 'in_service_bay'::text, 'service_complete_holding'::text, 'staged_for_departure'::text, 'emergency_staged'::text, 'tow_requested'::text]) THEN 'frozen:entered'::text
            ELSE 'frozen:not_inbound'::text
        END AS zone_reason,
    (current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) AND (minutes_out IS NULL OR minutes_out <= freeze_min) AS approached,
    current_state = ANY (ARRAY['arrived_at_gate'::text, 'staged_awaiting_service'::text, 'charging_dcfc'::text, 'charging_l2'::text, 'charge_complete_holding'::text, 'in_wash_bay'::text, 'in_detail_bay'::text, 'in_service_bay'::text, 'service_complete_holding'::text, 'staged_for_departure'::text, 'emergency_staged'::text, 'tow_requested'::text]) AS entered,
    (current_state = ANY (ARRAY['deployed'::text, 'en_route_to_depot'::text])) AND minutes_out IS NOT NULL AND minutes_out > freeze_min AND minutes_out <= horizon_min AS in_cuopt_window,
    c_hardware AS zone_c_hardware,
    c_flag AS zone_c_flag
   FROM b;

-- ===== VIEW: ottoq_booking_why_v1 =====
CREATE OR REPLACE VIEW public.ottoq_booking_why_v1 AS
 SELECT b.booking_id,
    b.sim_run_id,
    b.vehicle_id,
    b.stall_id,
    s.stall_code,
    s.stall_type::text AS stall_type,
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
    l.duration_basis ->> 'atom'::text AS leg_atom,
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
    b.leg_id IS NOT NULL AS has_leg,
    b.need_code IS NOT NULL OR b.leg_id IS NOT NULL AS answers_why
   FROM ottoq_stall_bookings b
     LEFT JOIN stalls s ON s.id = b.stall_id
     LEFT JOIN ottoq_itinerary_legs l ON l.leg_id = b.leg_id
     LEFT JOIN ottoq_visit_needs vn ON vn.visit_id = b.visit_id;

-- ===== VIEW: ottoq_calibration_status =====
CREATE OR REPLACE VIEW public.ottoq_calibration_status AS
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
   FROM ottoq_calibration_datasets d
     LEFT JOIN ottoq_calibration_distributions dist ON dist.dataset_code = d.dataset_code
     LEFT JOIN ottoq_calibration_profiles p ON p.dataset_code = d.dataset_code
  GROUP BY d.domain, d.dataset_code, d.source_name, d.status, d.record_count, d.date_range_start, d.date_range_end, d.ingested_at
  ORDER BY d.domain, d.dataset_code;

-- ===== VIEW: ottoq_counterfactual_summary_30d =====
CREATE OR REPLACE VIEW public.ottoq_counterfactual_summary_30d AS
 SELECT scenario_label,
    source_kind,
    count(*) AS runs,
    count(*) FILTER (WHERE delta_direction = 'better'::text) AS better_count,
    count(*) FILTER (WHERE delta_direction = 'worse'::text) AS worse_count,
    count(*) FILTER (WHERE delta_direction = 'neutral'::text) AS neutral_count,
    avg(delta) AS avg_delta,
    percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (delta::double precision)) AS median_delta,
    min(delta) AS min_delta,
    max(delta) AS max_delta
   FROM ottoq_counterfactuals
  WHERE ran_at > (now() - '30 days'::interval) AND delta IS NOT NULL
  GROUP BY scenario_label, source_kind;

-- ===== VIEW: ottoq_cross_depot_ranking_30d =====
CREATE OR REPLACE VIEW public.ottoq_cross_depot_ranking_30d AS
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
   FROM depots d
     LEFT JOIN ottoq_depot_benchmarks_daily b ON b.depot_id = d.id AND b.report_date >= (CURRENT_DATE - 30)
  GROUP BY d.id, d.name;

-- ===== VIEW: ottoq_depot_economics_summary =====
CREATE OR REPLACE VIEW public.ottoq_depot_economics_summary AS
 SELECT depot_id,
    date_trunc('month'::text, report_date::timestamp with time zone) AS month_start,
    sum(visits_completed) AS visits,
    sum(total_kwh_delivered) AS kwh_delivered,
    sum(total_operating_cost_usd) AS operating_cost,
    sum(total_revenue_usd) AS revenue,
    sum(total_margin_usd) AS margin,
    round(sum(total_margin_usd) / NULLIF(sum(total_revenue_usd), 0::numeric) * 100::numeric, 2) AS margin_pct,
    sum(total_carbon_offset_kg) AS carbon_offset_kg,
    avg(solar_self_consumption_pct) AS avg_solar_self_consumption_pct
   FROM ottoq_depot_cost_daily
  GROUP BY depot_id, (date_trunc('month'::text, report_date::timestamp with time zone));

-- ===== VIEW: ottoq_event_stream =====
CREATE OR REPLACE VIEW public.ottoq_event_stream AS
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
    signature IS NOT NULL AS is_signed
   FROM ottoq_events
  ORDER BY event_seq DESC;

-- ===== VIEW: ottoq_features_live =====
CREATE OR REPLACE VIEW public.ottoq_features_live AS
 SELECT fv.feature_name,
    fv.entity_type,
    fv.entity_id,
    COALESCE(to_jsonb(fv.value_numeric), to_jsonb(fv.value_integer), to_jsonb(fv.value_boolean), to_jsonb(fv.value_text), to_jsonb(fv.value_timestamp), fv.value_json) AS value,
    fv.valid_from,
    fv.observation_time,
    EXTRACT(epoch FROM now() - fv.observation_time)::integer AS age_seconds,
    fv.quality_score,
    fv.is_imputed,
    fv.is_outlier,
    fv.fleet_operator_id,
    fv.depot_id,
    fv.feature_version,
    f.freshness_sla_seconds,
    EXTRACT(epoch FROM now() - fv.observation_time) <= f.freshness_sla_seconds::numeric AS is_fresh
   FROM ottoq_feature_values fv
     LEFT JOIN ottoq_features f ON f.feature_name = fv.feature_name
  WHERE fv.valid_until IS NULL;

-- ===== VIEW: ottoq_inference_failures =====
CREATE OR REPLACE VIEW public.ottoq_inference_failures AS
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
   FROM ottoq_inference_log
  WHERE (status = ANY (ARRAY['failed'::text, 'timed_out'::text])) AND requested_at > (now() - '24:00:00'::interval)
  ORDER BY requested_at DESC;

-- ===== VIEW: ottoq_inference_latency_summary =====
CREATE OR REPLACE VIEW public.ottoq_inference_latency_summary AS
 SELECT prediction_type,
    model_version_id,
    count(*) AS calls_last_hour,
    count(*) FILTER (WHERE status = 'completed'::text) AS succeeded,
    count(*) FILTER (WHERE status = ANY (ARRAY['failed'::text, 'timed_out'::text])) AS failed,
    round(avg(latency_ms))::integer AS avg_latency_ms,
    percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (latency_ms::double precision))::integer AS p50_ms,
    percentile_cont(0.95::double precision) WITHIN GROUP (ORDER BY (latency_ms::double precision))::integer AS p95_ms,
    percentile_cont(0.99::double precision) WITHIN GROUP (ORDER BY (latency_ms::double precision))::integer AS p99_ms,
    max(latency_ms) AS max_ms,
    round(avg(cost_estimate_cents), 4) AS avg_cost_cents
   FROM ottoq_inference_log
  WHERE requested_at > (now() - '01:00:00'::interval)
  GROUP BY prediction_type, model_version_id;

-- ===== VIEW: ottoq_network_summary_weekly =====
CREATE OR REPLACE VIEW public.ottoq_network_summary_weekly AS
 SELECT date_trunc('week'::text, report_date::timestamp with time zone) AS week_start,
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
   FROM ottoq_depot_benchmarks_daily
  WHERE report_date >= (CURRENT_DATE - 90)
  GROUP BY (date_trunc('week'::text, report_date::timestamp with time zone))
  ORDER BY (date_trunc('week'::text, report_date::timestamp with time zone)) DESC;

-- ===== VIEW: ottoq_oem_anomaly_summary =====
CREATE OR REPLACE VIEW public.ottoq_oem_anomaly_summary AS
 SELECT ao.fleet_operator_id,
    ao.depot_id,
    ao.detector_code,
    ad.category AS detector_category,
    ad.title AS detector_title,
    count(*) AS observations_7d,
    count(*) FILTER (WHERE ao.is_anomaly) AS anomalies_7d,
    count(*) FILTER (WHERE ao.severity = ANY (ARRAY['critical'::text, 'safety_critical'::text])) AS critical_7d,
    max(ao.observed_at) FILTER (WHERE ao.is_anomaly) AS last_anomaly_at,
    round(100.0 * count(*) FILTER (WHERE ao.is_anomaly)::numeric / NULLIF(count(*), 0)::numeric, 2) AS anomaly_rate_pct
   FROM ottoq_anomaly_observations ao
     JOIN ottoq_anomaly_detectors ad ON ad.detector_code = ao.detector_code
  WHERE ao.observed_at > (now() - '7 days'::interval)
  GROUP BY ao.fleet_operator_id, ao.depot_id, ao.detector_code, ad.category, ad.title;

-- ===== VIEW: ottoq_oem_dashboard_summary =====
CREATE OR REPLACE VIEW public.ottoq_oem_dashboard_summary AS
 SELECT fo.id AS fleet_operator_id,
    fo.name AS fleet_operator_name,
    d.id AS depot_id,
    d.name AS depot_name,
    ( SELECT count(*) AS count
           FROM ottoq_events e
          WHERE e.fleet_operator_id = fo.id AND (e.depot_id = d.id OR e.depot_id IS NULL) AND e.occurred_at > (now() - '24:00:00'::interval)) AS events_24h,
    ( SELECT count(*) AS count
           FROM ottoq_predictions p
          WHERE p.fleet_operator_id = fo.id AND (p.depot_id = d.id OR p.depot_id IS NULL) AND p.created_at > (now() - '24:00:00'::interval)) AS predictions_24h,
    ( SELECT count(*) AS count
           FROM ottoq_anomaly_observations a
          WHERE a.fleet_operator_id = fo.id AND (a.depot_id = d.id OR a.depot_id IS NULL) AND a.is_anomaly = true AND a.observed_at > (now() - '24:00:00'::interval)) AS anomalies_24h,
    ( SELECT count(*) AS count
           FROM ottoq_rule_evaluations re
          WHERE re.fleet_operator_id = fo.id AND (re.depot_id = d.id OR re.depot_id IS NULL) AND re.passed = false AND re.evaluated_at > (now() - '24:00:00'::interval)) AS rule_failures_24h,
    ( SELECT count(*) AS count
           FROM ottoq_sla_violations v
          WHERE v.fleet_operator_id = fo.id AND (v.depot_id = d.id OR v.depot_id IS NULL) AND v.detected_at > (now() - '24:00:00'::interval)) AS sla_violations_24h,
    ( SELECT count(*) AS count
           FROM ottoq_emergency_invocations ei
          WHERE ei.depot_id = d.id AND ei.triggered_at > (now() - '24:00:00'::interval)) AS emergencies_24h,
    ( SELECT count(*) AS count
           FROM ottoq_emergency_invocations ei
          WHERE ei.depot_id = d.id AND ei.cleared_at IS NULL) AS active_emergencies,
    ( SELECT count(*) AS count
           FROM ottoq_recommendations r
          WHERE r.fleet_operator_id = fo.id AND (r.status = ANY (ARRAY['pending'::text, 'validating'::text, 'admitted'::text])) AND (r.expires_at IS NULL OR r.expires_at > now())) AS active_recommendations,
    ( SELECT sc.overall_compliance_pct
           FROM ottoq_sla_conformance_daily sc
          WHERE sc.fleet_operator_id = fo.id AND (sc.depot_id = d.id OR sc.depot_id IS NULL AND d.id IS NULL)
          ORDER BY sc.report_date DESC
         LIMIT 1) AS last_compliance_pct,
    ( SELECT sc.composite_grade
           FROM ottoq_sla_conformance_daily sc
          WHERE sc.fleet_operator_id = fo.id AND (sc.depot_id = d.id OR sc.depot_id IS NULL AND d.id IS NULL)
          ORDER BY sc.report_date DESC
         LIMIT 1) AS last_grade
   FROM fleet_operators fo
     CROSS JOIN depots d
  WHERE fo.is_active = true;

-- ===== VIEW: ottoq_oem_model_coverage =====
CREATE OR REPLACE VIEW public.ottoq_oem_model_coverage AS
 SELECT r.prediction_type,
    fo.name AS oem_name,
    fo.id AS fleet_operator_id,
    r.vehicle_class,
    r.model_version_id IS NOT NULL AS has_trained_model,
    mv.version_tag,
    mv.deployment_stage,
    mv.artifact_format,
    r.shadow_mode,
    r.created_at AS route_created_at
   FROM ottoq_model_routes r
     LEFT JOIN fleet_operators fo ON fo.id = r.fleet_operator_id
     LEFT JOIN model_versions mv ON mv.id = r.model_version_id
  WHERE r.effective_from <= now() AND (r.effective_until IS NULL OR r.effective_until > now())
  ORDER BY r.prediction_type, fo.name NULLS FIRST, r.vehicle_class NULLS FIRST;

-- ===== VIEW: ottoq_oem_override_summary =====
CREATE OR REPLACE VIEW public.ottoq_oem_override_summary AS
 SELECT fleet_operator_id,
    depot_id,
    count(*) FILTER (WHERE enforcement_taken = 'overridden'::text) AS overrides_7d,
    count(DISTINCT entity_id) FILTER (WHERE enforcement_taken = 'overridden'::text) AS unique_entities,
    count(DISTINCT rule_code) FILTER (WHERE enforcement_taken = 'overridden'::text) AS unique_rules_overridden,
    count(*) FILTER (WHERE enforcement_taken = ANY (ARRAY['blocked'::text, 'warned'::text])) AS blocks_or_warnings_7d
   FROM ottoq_rule_evaluations re
  WHERE evaluated_at > (now() - '7 days'::interval)
  GROUP BY fleet_operator_id, depot_id;

-- ===== VIEW: ottoq_oem_recent_predictions =====
CREATE OR REPLACE VIEW public.ottoq_oem_recent_predictions AS
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
   FROM ottoq_predictions p
     LEFT JOIN ottoq_prediction_types_catalog pt ON pt.prediction_type = p.prediction_type
  WHERE p.created_at > (now() - '24:00:00'::interval)
  ORDER BY p.created_at DESC;

-- ===== VIEW: ottoq_oem_rule_failure_top =====
CREATE OR REPLACE VIEW public.ottoq_oem_rule_failure_top AS
 SELECT re.fleet_operator_id,
    re.depot_id,
    re.rule_code,
    r.title,
    r.severity AS rule_severity,
    count(*) AS failure_count,
    count(DISTINCT re.entity_id) AS unique_entities_affected,
    max(re.evaluated_at) AS most_recent
   FROM ottoq_rule_evaluations re
     JOIN ottoq_rules r ON r.rule_code = re.rule_code AND r.version = re.rule_version
  WHERE re.passed = false AND re.evaluated_at > (now() - '7 days'::interval)
  GROUP BY re.fleet_operator_id, re.depot_id, re.rule_code, r.title, r.severity
  ORDER BY (count(*)) DESC;

-- ===== VIEW: ottoq_oem_unit_economics_30d =====
CREATE OR REPLACE VIEW public.ottoq_oem_unit_economics_30d AS
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
   FROM ottoq_visit_cost_attribution
  WHERE visit_completed_at > (now() - '30 days'::interval)
  GROUP BY fleet_operator_id;

-- ===== VIEW: ottoq_oem_visit_history =====
CREATE OR REPLACE VIEW public.ottoq_oem_visit_history AS
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
   FROM depot_visit_reports vr
  ORDER BY visit_completed_at DESC NULLS LAST;

-- ===== VIEW: ottoq_recent_audit_bundles =====
CREATE OR REPLACE VIEW public.ottoq_recent_audit_bundles AS
 SELECT b.bundle_id,
    b.bundle_code,
    b.fleet_operator_id,
    fo.name AS fleet_operator_name,
    b.window_start,
    b.window_end,
    b.format,
    b.size_bytes,
    b.sha256,
    b.signature IS NOT NULL AND b.signature !~~ 'UNSIGNED:%'::text AS is_signed,
    b.signature_key_id,
    b.manifest,
    b.generated_at,
    b.generated_by_actor_type,
    b.download_count,
    b.last_downloaded_at,
    b.expires_at,
    b.revoked_at
   FROM ottoq_audit_bundles b
     LEFT JOIN fleet_operators fo ON fo.id = b.fleet_operator_id
  WHERE b.generated_at > (now() - '90 days'::interval)
  ORDER BY b.generated_at DESC;

-- ===== VIEW: ottoq_recent_audit_reports =====
CREATE OR REPLACE VIEW public.ottoq_recent_audit_reports AS
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
    signature IS NOT NULL AS is_signed,
    signature_key_id,
    format,
    expires_at
   FROM ottoq_audit_reports r
  WHERE requested_at > (now() - '30 days'::interval)
  ORDER BY requested_at DESC;

-- ===== VIEW: ottoq_recent_rule_evaluations =====
CREATE OR REPLACE VIEW public.ottoq_recent_rule_evaluations AS
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
   FROM ottoq_rule_evaluations e
     LEFT JOIN ottoq_rules r ON r.rule_code = e.rule_code AND r.version = e.rule_version
  WHERE e.evaluated_at > (now() - '24:00:00'::interval)
  ORDER BY e.evaluation_seq DESC;

-- ===== VIEW: ottoq_recommendation_outcomes_24h =====
CREATE OR REPLACE VIEW public.ottoq_recommendation_outcomes_24h AS
 SELECT prediction_type,
    proposed_action,
    count(*) FILTER (WHERE status = 'admitted'::text) AS admitted,
    count(*) FILTER (WHERE status = 'rejected'::text) AS rejected,
    count(*) FILTER (WHERE status = 'executed'::text) AS executed,
    count(*) FILTER (WHERE execution_outcome = 'succeeded'::text) AS execution_succeeded,
    count(*) FILTER (WHERE status = 'shadow'::text) AS shadow_only_count,
    count(*) AS total,
    round(100.0 * count(*) FILTER (WHERE status = ANY (ARRAY['admitted'::text, 'executed'::text]))::numeric / NULLIF(count(*) FILTER (WHERE NOT shadow_only), 0)::numeric, 2) AS admission_rate_pct
   FROM ottoq_recommendations
  WHERE emitted_at > (now() - '24:00:00'::interval)
  GROUP BY prediction_type, proposed_action;

-- ===== VIEW: ottoq_rule_failures =====
CREATE OR REPLACE VIEW public.ottoq_rule_failures AS
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
   FROM ottoq_rule_evaluations e
     JOIN ottoq_rules r ON r.rule_code = e.rule_code AND r.version = e.rule_version
  WHERE e.passed = false AND e.evaluated_at > (now() - '7 days'::interval)
  ORDER BY (
        CASE e.severity
            WHEN 'safety_critical'::text THEN 1
            WHEN 'critical'::text THEN 2
            WHEN 'error'::text THEN 3
            WHEN 'warning'::text THEN 4
            ELSE 5
        END), e.evaluated_at DESC;

-- ===== VIEW: ottoq_rules_with_predictive_coverage =====
CREATE OR REPLACE VIEW public.ottoq_rules_with_predictive_coverage AS
 SELECT r.rule_code,
    r.title AS rule_title,
    r.category AS rule_category,
    r.severity,
    count(prl.prediction_type) AS predictor_count,
    array_agg(prl.prediction_type) FILTER (WHERE prl.enabled) AS predicting_types
   FROM ottoq_rules r
     LEFT JOIN ottoq_prediction_rule_links prl ON prl.rule_code = r.rule_code
  WHERE r.status = 'active'::text
  GROUP BY r.rule_code, r.title, r.category, r.severity
  ORDER BY (count(prl.prediction_type)) DESC, r.rule_code;

-- ===== VIEW: ottoq_safety_events =====
CREATE OR REPLACE VIEW public.ottoq_safety_events AS
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
   FROM ottoq_events
  WHERE severity = ANY (ARRAY['critical'::text, 'safety_critical'::text])
  ORDER BY event_seq DESC;

-- ===== VIEW: ottoq_shadow_disagreements =====
CREATE OR REPLACE VIEW public.ottoq_shadow_disagreements AS
 SELECT prediction_type,
    model_version_id,
    count(*) AS shadow_calls,
    avg(shadow_disagreement) AS avg_disagreement,
    max(shadow_disagreement) AS max_disagreement
   FROM ottoq_inference_log
  WHERE is_shadow = true AND shadow_compared_to IS NOT NULL AND requested_at > (now() - '7 days'::interval)
  GROUP BY prediction_type, model_version_id
  ORDER BY (avg(shadow_disagreement)) DESC NULLS LAST;

-- ===== VIEW: ottoq_sla_conformance_monthly =====
CREATE OR REPLACE VIEW public.ottoq_sla_conformance_monthly AS
 SELECT fleet_operator_id,
    depot_id,
    date_trunc('month'::text, report_date::timestamp with time zone)::date AS month_start,
    count(*) AS days_with_data,
    sum(total_visits) AS total_visits,
    sum(compliant_visits) AS compliant_visits,
    sum(non_compliant_visits) AS non_compliant_visits,
    round(avg(overall_compliance_pct), 2) AS avg_compliance_pct,
    round(avg(pct_meeting_min_soc), 2) AS avg_min_soc_pct,
    round(avg(pct_meeting_max_visit_time), 2) AS avg_visit_time_pct,
    round(avg(pct_meeting_required_services), 2) AS avg_services_pct,
    round(avg(pct_meeting_oem_gate), 2) AS avg_oem_gate_pct
   FROM ottoq_sla_conformance_daily
  GROUP BY fleet_operator_id, depot_id, (date_trunc('month'::text, report_date::timestamp with time zone));

-- ===== VIEW: ottoq_sla_conformance_weekly =====
CREATE OR REPLACE VIEW public.ottoq_sla_conformance_weekly AS
 SELECT fleet_operator_id,
    depot_id,
    date_trunc('week'::text, report_date::timestamp with time zone)::date AS week_start,
    count(*) AS days_with_data,
    sum(total_visits) AS total_visits,
    sum(compliant_visits) AS compliant_visits,
    sum(non_compliant_visits) AS non_compliant_visits,
    round(avg(overall_compliance_pct), 2) AS avg_compliance_pct,
    min(overall_compliance_pct) AS worst_day_pct,
    max(overall_compliance_pct) AS best_day_pct,
    min(composite_grade) AS worst_grade
   FROM ottoq_sla_conformance_daily
  GROUP BY fleet_operator_id, depot_id, (date_trunc('week'::text, report_date::timestamp with time zone));

-- ===== VIEW: ottoq_swap_test_scoreboard =====
CREATE OR REPLACE VIEW public.ottoq_swap_test_scoreboard AS
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
   FROM ottoq_ab_runs
  GROUP BY scenario_code, policy;

-- ===== VIEW: ottoq_vehicle_needs_card =====
CREATE OR REPLACE VIEW public.ottoq_vehicle_needs_card AS
 WITH run AS (
         SELECT DISTINCT ON (r_1.depot_id) r_1.depot_id,
            r_1.sim_run_id,
            COALESCE(r_1.sim_clock_current, r_1.sim_clock_start, now()) AS sim_clock
           FROM ottoq_sim_runs r_1
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
           FROM vehicle_need_profile p
             JOIN vehicles v ON v.id = p.vehicle_id
             LEFT JOIN run r_1 ON r_1.depot_id = v.home_depot_id
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
                    WHEN b.next_deploy_at IS NULL THEN NULL::integer
                    ELSE round(EXTRACT(epoch FROM b.next_deploy_at - b.sim_clock) / 60.0)::integer
                END AS minutes_to_deploy,
            GREATEST(0::numeric, COALESCE(b.min_ready_soc_pct, 80::numeric) - COALESCE(b.current_soc, 0)::numeric) AS soc_deficit_to_sla,
            GREATEST(0, COALESCE(b.target_soc, 90) - COALESCE(b.current_soc, 0)) AS soc_deficit_to_target,
            round(COALESCE(ottoq_estimate_charge_minutes(COALESCE(b.current_soc, 50)::numeric, COALESCE(b.target_soc, 90)::numeric, 150::numeric, COALESCE(b.inlet_max_kw, 150::numeric), COALESCE(b.battery_capacity_kwh, 75::numeric), COALESCE(b.pack_temp_c, 25::numeric), COALESCE(b.battery_soh_pct, 95::numeric), 1.0), 0::numeric))::integer AS est_charge_min,
            round(EXTRACT(epoch FROM b.sim_clock - b.last_wash_at) / 3600.0 / NULLIF(b.wash_interval_h, 0::numeric), 3) AS wash_ratio,
            round(EXTRACT(epoch FROM b.sim_clock - b.last_deep_clean_at) / 3600.0 / NULLIF(b.deep_clean_interval_h, 0::numeric), 3) AS deep_clean_ratio,
            round(EXTRACT(epoch FROM b.sim_clock - b.last_calibration_at) / 3600.0 / NULLIF(b.calib_interval_h, 0::numeric), 3) AS calib_ratio,
            round(GREATEST(0::numeric, b.odometer_km - COALESCE(b.km_at_last_pm, 0::numeric)) / NULLIF(b.pm_interval_km, 0::numeric), 3) AS pm_ratio,
            b.last_wash_at + make_interval(hours => COALESCE(b.wash_interval_h, 72::numeric)::integer) AS wash_due_at,
            b.last_deep_clean_at + make_interval(hours => COALESCE(b.deep_clean_interval_h, 336::numeric)::integer) AS deep_clean_due_at,
            b.last_calibration_at + make_interval(hours => COALESCE(b.calib_interval_h, 250::numeric)::integer) AS calib_due_at,
            GREATEST(0::numeric, b.odometer_km - COALESCE(b.km_at_last_pm, 0::numeric)) AS km_since_pm,
            b.software_version IS DISTINCT FROM b.sw_target_version AS sw_behind,
            ( SELECT COALESCE(sum((a.value ->> 'est_min'::text)::numeric), 0::numeric) AS "coalesce"
                   FROM ottoq_visit_needs n,
                    LATERAL jsonb_array_elements(n.atoms) a(value)
                  WHERE n.vehicle_id = b.vehicle_id AND n.status = 'open'::text) AS open_work_min,
            ( SELECT COALESCE(sum((a.value ->> 'est_min'::text)::numeric), 0::numeric) AS "coalesce"
                   FROM ottoq_visit_needs n,
                    LATERAL jsonb_array_elements(n.atoms) a(value)
                  WHERE n.vehicle_id = b.vehicle_id AND n.status = 'open'::text AND COALESCE((a.value ->> 'must_do'::text)::boolean, false)) AS open_must_do_min
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
                    WHEN c.soc_deficit_to_sla > 0::numeric AND COALESCE(c.minutes_to_deploy, 999999) < c.est_charge_min THEN 'critical'::text
                    WHEN c.soc_deficit_to_sla > 0::numeric THEN 'due'::text
                    WHEN c.soc_deficit_to_target > 5 THEN 'due_soon'::text
                    ELSE 'ok'::text
                END AS energy_urgency,
            ottoq_urgency_max(ottoq_service_urgency('exterior_wash'::text, c.wash_ratio),
                CASE
                    WHEN c.exterior_soil_level >= 0.85 THEN 'overdue'::text
                    WHEN c.exterior_soil_level >= 0.65 THEN 'due'::text
                    WHEN c.exterior_soil_level >= 0.45 THEN 'due_soon'::text
                    ELSE 'ok'::text
                END) AS wash_urgency,
            ottoq_urgency_max(ottoq_service_urgency('interior_deep_clean'::text, c.deep_clean_ratio),
                CASE
                    WHEN c.cabin_condition = 'biohazard'::text THEN 'critical'::text
                    WHEN c.cabin_condition = 'soiled'::text THEN 'overdue'::text
                    WHEN c.cabin_condition = 'light_litter'::text THEN 'due_soon'::text
                    ELSE 'ok'::text
                END) AS cabin_urgency,
            ottoq_urgency_max(ottoq_service_urgency('sensor_calibration'::text, c.calib_ratio),
                CASE
                    WHEN c.sensor_health_pct < 89::numeric THEN 'due'::text
                    WHEN c.sensor_health_pct < 91::numeric THEN 'due_soon'::text
                    ELSE 'ok'::text
                END) AS calib_urgency,
            ottoq_service_urgency('mechanical_pm'::text, c.pm_ratio) AS pm_urgency,
            ottoq_service_urgency('fault_repair'::text,
                CASE
                    WHEN c.worst_fault_severity = 1 THEN 2.00
                    WHEN c.worst_fault_severity <= 3 THEN 1.30
                    WHEN c.worst_fault_severity <= 5 THEN 0.80
                    ELSE 0.00
                END) AS fault_urgency,
                CASE
                    WHEN c.tire_tread_mm < 2.7 THEN 'critical'::text
                    WHEN c.tire_tread_mm < 3.0 THEN 'due'::text
                    WHEN c.tire_tread_mm < 4.0 THEN 'due_soon'::text
                    ELSE 'ok'::text
                END AS tire_urgency,
                CASE
                    WHEN c.brake_wear_pct >= 82::numeric THEN 'critical'::text
                    WHEN c.brake_wear_pct >= 80::numeric THEN 'due'::text
                    WHEN c.brake_wear_pct >= 65::numeric THEN 'due_soon'::text
                    ELSE 'ok'::text
                END AS brake_urgency,
            ottoq_service_urgency('software_update'::text,
                CASE
                    WHEN NOT c.software_version IS DISTINCT FROM c.sw_target_version THEN 0.00
                    WHEN c.software_version = '2026.26.2'::text THEN 1.30
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
            ottoq_urgency_max(g.pm_urgency, ottoq_urgency_max(g.tire_urgency, g.brake_urgency)) AS mech_urgency
           FROM grade g
        ), cand AS (
         SELECT m.vehicle_id,
            x.svc,
            x.urg,
            ottoq_service_must_do(x.svc, x.urg) AS is_must_do
           FROM mech m
             CROSS JOIN LATERAL ( VALUES ('charge'::text,m.energy_urgency,m.energy_urgency <> 'ok'::text), ('exterior_wash'::text,m.wash_urgency,true), ('interior_deep_clean'::text,m.cabin_urgency,true), ('sensor_calibration'::text,m.calib_urgency,true), ('mechanical_pm'::text,m.mech_urgency,true), ('fault_repair'::text,m.fault_urgency,COALESCE(m.worst_fault_severity::integer, 99) <= 3), ('software_update'::text,m.software_urgency,m.sw_behind), ('item_retrieval'::text,m.item_urgency,m.item_retrieval_pending)) x(svc, urg, applies)
          WHERE x.applies
        ), agg AS (
         SELECT cand.vehicle_id,
            COALESCE(array_agg(DISTINCT cand.svc) FILTER (WHERE cand.is_must_do), '{}'::text[]) AS must_do_now,
            COALESCE(array_agg(DISTINCT cand.svc) FILTER (WHERE NOT cand.is_must_do AND ottoq_urgency_rank(cand.urg) >= 2), '{}'::text[]) AS deferrable_now
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
            COALESCE(a.deferrable_now, '{}'::text[]) AS deferrable_now_raw
           FROM mech m
             LEFT JOIN agg a ON a.vehicle_id = m.vehicle_id
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
    must_do_now_raw AS must_do_now,
    deferrable_now_raw AS deferrable_now,
    open_work_min,
    open_must_do_min,
        CASE
            WHEN minutes_to_deploy IS NULL THEN true
            ELSE minutes_to_deploy::numeric >= GREATEST(est_charge_min::numeric, open_must_do_min)
        END AS fits_window,
    ( SELECT ottoq_urgency_max(ottoq_urgency_max(ottoq_urgency_max(ottoq_urgency_max(r.energy_urgency, r.wash_urgency), ottoq_urgency_max(r.cabin_urgency, r.calib_urgency)), ottoq_urgency_max(r.mech_urgency, r.fault_urgency)), ottoq_urgency_max(
                CASE
                    WHEN r.priority_class = 'critical'::text THEN 'critical'::text
                    ELSE 'ok'::text
                END, ottoq_urgency_max(r.software_urgency, r.item_urgency))) AS ottoq_urgency_max) AS overall_urgency,
    ( SELECT array_agg(DISTINCT ottoq_need_to_leg_type(x.x, r.dcfc_safe)) AS array_agg
           FROM unnest(r.must_do_now_raw) x(x)) AS must_do_legs,
    jsonb_build_object('vehicle_id', vehicle_id, 'av_id', av_id, 'as_of', sim_clock, 'commitment', jsonb_build_object('next_deploy_at', next_deploy_at, 'minutes_to_deploy', minutes_to_deploy, 'priority_class', priority_class, 'assigned_shift', assigned_shift), 'energy', jsonb_build_object('soc_pct', current_soc, 'target_soc_pct', target_soc, 'min_ready_soc_pct', min_ready_soc_pct, 'est_charge_min', est_charge_min, 'battery_soh_pct', battery_soh_pct, 'charge_accept_kw', charge_accept_kw, 'pack_temp_c', pack_temp_c, 'dcfc_safe', dcfc_safe, 'dcfc_block_reason', dcfc_block_reason, 'urgency', energy_urgency), 'cleanliness', jsonb_build_object('exterior_soil_level', exterior_soil_level, 'cabin_condition', cabin_condition, 'wash_due_at', wash_due_at, 'wash_ratio', wash_ratio, 'wash_urgency', wash_urgency, 'deep_clean_due_at', deep_clean_due_at, 'cabin_urgency', cabin_urgency), 'sensor_software', jsonb_build_object('calib_due_at', calib_due_at, 'calib_ratio', calib_ratio, 'calib_urgency', calib_urgency, 'sensor_health_pct', sensor_health_pct, 'software_version', software_version, 'sw_target_version', sw_target_version, 'sw_behind', sw_behind, 'software_urgency', software_urgency), 'mechanical', jsonb_build_object('odometer_km', odometer_km, 'km_since_pm', km_since_pm, 'pm_ratio', pm_ratio, 'pm_urgency', pm_urgency, 'open_fault_codes', to_jsonb(open_fault_codes), 'worst_fault_severity', worst_fault_severity, 'fault_urgency', fault_urgency, 'tire_tread_mm', tire_tread_mm, 'tire_urgency', tire_urgency, 'brake_wear_pct', brake_wear_pct, 'brake_urgency', brake_urgency), 'items', jsonb_build_object('pending', item_retrieval_pending, 'description', item_description, 'reported_at', item_reported_at), 'must_do_now', to_jsonb(must_do_now_raw), 'deferrable_now', to_jsonb(deferrable_now_raw), 'must_do_legs', to_jsonb(( SELECT array_agg(DISTINCT ottoq_need_to_leg_type(x.x, r.dcfc_safe)) AS array_agg
           FROM unnest(r.must_do_now_raw) x(x))), 'open_work_min', open_work_min, 'open_must_do_min', open_must_do_min) AS need_statement
   FROM roll r;

-- ===== VIEW: v_charger_status =====
CREATE OR REPLACE VIEW public.v_charger_status AS
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
    GREATEST(0::numeric, EXTRACT(epoch FROM cc.available_at - now()) / 60::numeric)::integer AS cooldown_minutes_remaining,
    chs.health_score AS charger_health,
    chs.recommended_maintenance
   FROM stalls s
     LEFT JOIN vehicles v ON v.id = s.current_vehicle_id
     LEFT JOIN ocpp_sessions os ON os.stall_id = s.id AND os.status = 'active'::ocpp_session_status
     LEFT JOIN charger_cooldowns cc ON cc.stall_id = s.id AND cc.resolved = false
     LEFT JOIN charger_health_scores chs ON chs.stall_id = s.id
  WHERE s.stall_type = ANY (ARRAY['dcfc'::stall_type, 'l2'::stall_type]);

-- ===== VIEW: v_depot_status =====
CREATE OR REPLACE VIEW public.v_depot_status AS
 SELECT d.id AS depot_id,
    d.name AS depot_name,
    d.slug,
    count(DISTINCT v.id) FILTER (WHERE v.current_depot_id = d.id AND v.current_state <> 'offline'::vehicle_state) AS vehicles_on_site,
    count(DISTINCT s.id) FILTER (WHERE s.stall_type = 'dcfc'::stall_type AND s.status = 'occupied'::text) AS dcfc_in_use,
    count(DISTINCT s.id) FILTER (WHERE s.stall_type = 'dcfc'::stall_type AND s.status = 'available'::text) AS dcfc_available,
    count(DISTINCT s.id) FILTER (WHERE s.stall_type = 'l2'::stall_type AND s.status = 'occupied'::text) AS l2_in_use,
    count(DISTINCT s.id) FILTER (WHERE s.stall_type = 'l2'::stall_type AND s.status = 'available'::text) AS l2_available,
    count(DISTINCT s.id) FILTER (WHERE s.stall_type = 'wash_bay'::stall_type AND s.status = 'occupied'::text) AS wash_bays_in_use,
    count(DISTINCT s.id) FILTER (WHERE s.stall_type = 'wash_bay'::stall_type AND s.status = 'available'::text) AS wash_bays_available,
    count(DISTINCT s.id) FILTER (WHERE s.stall_type = 'service_bay'::stall_type AND s.status = 'occupied'::text) AS service_bays_in_use,
    count(DISTINCT e.id) FILTER (WHERE e.status = ANY (ARRAY['open'::exception_status, 'acknowledged'::exception_status, 'in_progress'::exception_status])) AS active_exceptions
   FROM depots d
     LEFT JOIN stalls s ON s.depot_id = d.id
     LEFT JOIN vehicles v ON v.current_depot_id = d.id
     LEFT JOIN exceptions e ON e.depot_id = d.id
  WHERE d.status = 'active'::text
  GROUP BY d.id, d.name, d.slug;

-- ===== VIEW: v_energy_status =====
CREATE OR REPLACE VIEW public.v_energy_status AS
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
    (d.config ->> 'peak_demand_kw_limit'::text)::numeric AS demand_limit_kw,
        CASE
            WHEN ((d.config ->> 'peak_demand_kw_limit'::text)::numeric) > 0::numeric THEN round(ses.peak_demand_kw_15min / ((d.config ->> 'peak_demand_kw_limit'::text)::numeric) * 100::numeric, 1)
            ELSE 0::numeric
        END AS demand_utilization_pct
   FROM depots d
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
           FROM site_energy_snapshots
          WHERE site_energy_snapshots.depot_id = d.id
          ORDER BY site_energy_snapshots."timestamp" DESC
         LIMIT 1) ses ON true
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
           FROM bess_snapshots
          WHERE bess_snapshots.depot_id = d.id
          ORDER BY bess_snapshots."timestamp" DESC
         LIMIT 1) bs ON true
  WHERE d.status = 'active'::text;

-- ===== VIEW: v_vehicle_service_history =====
CREATE OR REPLACE VIEW public.v_vehicle_service_history AS
 SELECT v.id AS vehicle_id,
    v.display_name,
    v.vin,
    fo.name AS fleet_operator,
    count(DISTINCT vs.id) AS total_visits,
    count(DISTINCT st.id) AS total_services,
    count(DISTINCT st.id) FILTER (WHERE st.status = 'completed'::task_status) AS completed_services,
    count(DISTINCT st.id) FILTER (WHERE st.status = 'exception'::task_status) AS exception_services,
    avg(EXTRACT(epoch FROM st.actual_end - st.actual_start) / 60::numeric) FILTER (WHERE st.status = 'completed'::task_status) AS avg_service_duration_minutes,
    max(vs.actual_arrival) AS last_visit,
    sum(st.energy_delivered_kwh) FILTER (WHERE st.energy_delivered_kwh IS NOT NULL) AS total_kwh_delivered
   FROM vehicles v
     LEFT JOIN fleet_operators fo ON fo.id = v.fleet_operator_id
     LEFT JOIN vehicle_schedules vs ON vs.vehicle_id = v.id
     LEFT JOIN schedule_tasks st ON st.vehicle_schedule_id = vs.id
  GROUP BY v.id, v.display_name, v.vin, fo.name;

-- ===== VIEW: workload_harness_report =====
CREATE OR REPLACE VIEW public.workload_harness_report AS
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
   FROM ( SELECT ottoq_sim_runs.sim_run_id,
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
           FROM ottoq_sim_runs
          WHERE COALESCE(ottoq_sim_runs.run_by, ''::text) <> 'production_live'::text
          ORDER BY ottoq_sim_runs.started_at DESC
         LIMIT 1) r
     CROSS JOIN LATERAL workload_harness_metrics(r.sim_run_id) m(section, metric, value, denom, per_arrival, detail);
