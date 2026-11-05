-- 10_constraints_keys.sql: 399 statements, exported from production's catalog
-- @@ constraint_p public.ab_tests.ab_tests_pkey
ALTER TABLE ONLY public.ab_tests ADD CONSTRAINT ab_tests_pkey PRIMARY KEY (id);
-- @@ constraint_p public.accuracy_alerts.accuracy_alerts_pkey
ALTER TABLE ONLY public.accuracy_alerts ADD CONSTRAINT accuracy_alerts_pkey PRIMARY KEY (id);
-- @@ constraint_u public.accuracy_slos.accuracy_slos_depot_id_prediction_type_time_horizon_hours_key
ALTER TABLE ONLY public.accuracy_slos ADD CONSTRAINT accuracy_slos_depot_id_prediction_type_time_horizon_hours_key UNIQUE (depot_id, prediction_type, time_horizon_hours);
-- @@ constraint_p public.accuracy_slos.accuracy_slos_pkey
ALTER TABLE ONLY public.accuracy_slos ADD CONSTRAINT accuracy_slos_pkey PRIMARY KEY (id);
-- @@ constraint_u public.action_guardrails.action_guardrails_depot_id_action_type_key
ALTER TABLE ONLY public.action_guardrails ADD CONSTRAINT action_guardrails_depot_id_action_type_key UNIQUE (depot_id, action_type);
-- @@ constraint_p public.action_guardrails.action_guardrails_pkey
ALTER TABLE ONLY public.action_guardrails ADD CONSTRAINT action_guardrails_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ai_decision_log.ai_decision_log_pkey
ALTER TABLE ONLY public.ai_decision_log ADD CONSTRAINT ai_decision_log_pkey PRIMARY KEY (id);
-- @@ constraint_u public.ai_decision_log.ai_decision_log_request_id_key
ALTER TABLE ONLY public.ai_decision_log ADD CONSTRAINT ai_decision_log_request_id_key UNIQUE (request_id);
-- @@ constraint_u public.api_integrations.api_integrations_depot_id_platform_integration_name_key
ALTER TABLE ONLY public.api_integrations ADD CONSTRAINT api_integrations_depot_id_platform_integration_name_key UNIQUE (depot_id, platform, integration_name);
-- @@ constraint_p public.api_integrations.api_integrations_pkey
ALTER TABLE ONLY public.api_integrations ADD CONSTRAINT api_integrations_pkey PRIMARY KEY (id);
-- @@ constraint_p public.autonomous_action_log.autonomous_action_log_pkey
ALTER TABLE ONLY public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_pkey PRIMARY KEY (id);
-- @@ constraint_p public.availability_fix_proof_2026_08_03.availability_fix_proof_2026_08_03_pkey
ALTER TABLE ONLY public.availability_fix_proof_2026_08_03 ADD CONSTRAINT availability_fix_proof_2026_08_03_pkey PRIMARY KEY (id);
-- @@ constraint_p public.bay_reservation_reconcile_2026_08_02.bay_reservation_reconcile_2026_08_02_pkey
ALTER TABLE ONLY public.bay_reservation_reconcile_2026_08_02 ADD CONSTRAINT bay_reservation_reconcile_2026_08_02_pkey PRIMARY KEY (id);
-- @@ constraint_p public.bess_snapshots.bess_snapshots_pkey
ALTER TABLE ONLY public.bess_snapshots ADD CONSTRAINT bess_snapshots_pkey PRIMARY KEY (id);
-- @@ constraint_p public.busy_day_tick_probe_2026_08_01.busy_day_tick_probe_2026_08_01_pkey
ALTER TABLE ONLY public.busy_day_tick_probe_2026_08_01 ADD CONSTRAINT busy_day_tick_probe_2026_08_01_pkey PRIMARY KEY (probe_id);
-- @@ constraint_p public.cert0022_misc.cert0022_misc_pkey
ALTER TABLE ONLY public.cert0022_misc ADD CONSTRAINT cert0022_misc_pkey PRIMARY KEY (k);
-- @@ constraint_p public.cert0023_energy_probe.cert0023_energy_probe_pkey
ALTER TABLE ONLY public.cert0023_energy_probe ADD CONSTRAINT cert0023_energy_probe_pkey PRIMARY KEY (k);
-- @@ constraint_p public.cert0023_misc.cert0023_misc_pkey
ALTER TABLE ONLY public.cert0023_misc ADD CONSTRAINT cert0023_misc_pkey PRIMARY KEY (k);
-- @@ constraint_p public.charger_cooldowns.charger_cooldowns_pkey
ALTER TABLE ONLY public.charger_cooldowns ADD CONSTRAINT charger_cooldowns_pkey PRIMARY KEY (id);
-- @@ constraint_p public.charger_health_scores.charger_health_scores_pkey
ALTER TABLE ONLY public.charger_health_scores ADD CONSTRAINT charger_health_scores_pkey PRIMARY KEY (id);
-- @@ constraint_p public.cuopt_invocation_log.cuopt_invocation_log_pkey
ALTER TABLE ONLY public.cuopt_invocation_log ADD CONSTRAINT cuopt_invocation_log_pkey PRIMARY KEY (invocation_id);
-- @@ constraint_p public.data_quality_errors.data_quality_errors_pkey
ALTER TABLE ONLY public.data_quality_errors ADD CONSTRAINT data_quality_errors_pkey PRIMARY KEY (id);
-- @@ constraint_p public.decision_fusion_log.decision_fusion_log_pkey
ALTER TABLE ONLY public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_pkey PRIMARY KEY (id);
-- @@ constraint_p public.demand_management_log.demand_management_log_pkey
ALTER TABLE ONLY public.demand_management_log ADD CONSTRAINT demand_management_log_pkey PRIMARY KEY (id);
-- @@ constraint_p public.demand_shaping_plans.demand_shaping_plans_pkey
ALTER TABLE ONLY public.demand_shaping_plans ADD CONSTRAINT demand_shaping_plans_pkey PRIMARY KEY (id);
-- @@ constraint_p public.depot_state_snapshots.depot_state_snapshots_pkey
ALTER TABLE ONLY public.depot_state_snapshots ADD CONSTRAINT depot_state_snapshots_pkey PRIMARY KEY (id);
-- @@ constraint_p public.depot_visit_reports.depot_visit_reports_pkey
ALTER TABLE ONLY public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_pkey PRIMARY KEY (id);
-- @@ constraint_p public.depots.depots_pkey
ALTER TABLE ONLY public.depots ADD CONSTRAINT depots_pkey PRIMARY KEY (id);
-- @@ constraint_u public.depots.depots_slug_key
ALTER TABLE ONLY public.depots ADD CONSTRAINT depots_slug_key UNIQUE (slug);
-- @@ constraint_u public.dispatch_commands.dispatch_commands_idempotency_key_key
ALTER TABLE ONLY public.dispatch_commands ADD CONSTRAINT dispatch_commands_idempotency_key_key UNIQUE (idempotency_key);
-- @@ constraint_p public.dispatch_commands.dispatch_commands_pkey
ALTER TABLE ONLY public.dispatch_commands ADD CONSTRAINT dispatch_commands_pkey PRIMARY KEY (id);
-- @@ constraint_u public.downstream_action_contracts.downstream_action_contracts_action_type_downstream_system_key
ALTER TABLE ONLY public.downstream_action_contracts ADD CONSTRAINT downstream_action_contracts_action_type_downstream_system_key UNIQUE (action_type, downstream_system);
-- @@ constraint_p public.downstream_action_contracts.downstream_action_contracts_pkey
ALTER TABLE ONLY public.downstream_action_contracts ADD CONSTRAINT downstream_action_contracts_pkey PRIMARY KEY (id);
-- @@ constraint_p public.early_recall_log.early_recall_log_pkey
ALTER TABLE ONLY public.early_recall_log ADD CONSTRAINT early_recall_log_pkey PRIMARY KEY (id);
-- @@ constraint_p public.emergency_queue_insertions.emergency_queue_insertions_pkey
ALTER TABLE ONLY public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_pkey PRIMARY KEY (id);
-- @@ constraint_p public.emission_fix_smoke_2026_08_03.emission_fix_smoke_2026_08_03_pkey
ALTER TABLE ONLY public.emission_fix_smoke_2026_08_03 ADD CONSTRAINT emission_fix_smoke_2026_08_03_pkey PRIMARY KEY (id);
-- @@ constraint_p public.engine_config.engine_config_pkey
ALTER TABLE ONLY public.engine_config ADD CONSTRAINT engine_config_pkey PRIMARY KEY (id);
-- @@ constraint_u public.engine_config.one_config_per_depot
ALTER TABLE ONLY public.engine_config ADD CONSTRAINT one_config_per_depot UNIQUE (depot_id);
-- @@ constraint_p public.exceptions.exceptions_pkey
ALTER TABLE ONLY public.exceptions ADD CONSTRAINT exceptions_pkey PRIMARY KEY (id);
-- @@ constraint_p public.external_factor_sources.external_factor_sources_pkey
ALTER TABLE ONLY public.external_factor_sources ADD CONSTRAINT external_factor_sources_pkey PRIMARY KEY (id);
-- @@ constraint_u public.external_factor_sources.external_factor_sources_source_name_key
ALTER TABLE ONLY public.external_factor_sources ADD CONSTRAINT external_factor_sources_source_name_key UNIQUE (source_name);
-- @@ constraint_p public.external_factors_log.external_factors_log_pkey
ALTER TABLE ONLY public.external_factors_log ADD CONSTRAINT external_factors_log_pkey PRIMARY KEY (id);
-- @@ constraint_u public.fleet_features_daily.fleet_features_daily_feature_date_feature_group_scope_scope_key
ALTER TABLE ONLY public.fleet_features_daily ADD CONSTRAINT fleet_features_daily_feature_date_feature_group_scope_scope_key UNIQUE (feature_date, feature_group, scope, scope_id);
-- @@ constraint_p public.fleet_features_daily.fleet_features_daily_pkey
ALTER TABLE ONLY public.fleet_features_daily ADD CONSTRAINT fleet_features_daily_pkey PRIMARY KEY (id);
-- @@ constraint_p public.fleet_operators.fleet_operators_pkey
ALTER TABLE ONLY public.fleet_operators ADD CONSTRAINT fleet_operators_pkey PRIMARY KEY (id);
-- @@ constraint_u public.fleet_operators.fleet_operators_slug_key
ALTER TABLE ONLY public.fleet_operators ADD CONSTRAINT fleet_operators_slug_key UNIQUE (slug);
-- @@ constraint_p public.fwd1_cert_424242.fwd1_cert_424242_pkey
ALTER TABLE ONLY public.fwd1_cert_424242 ADD CONSTRAINT fwd1_cert_424242_pkey PRIMARY KEY (id);
-- @@ constraint_p public.fwd2_urgency_samples.fwd2_urgency_samples_pkey
ALTER TABLE ONLY public.fwd2_urgency_samples ADD CONSTRAINT fwd2_urgency_samples_pkey PRIMARY KEY (sample_id);
-- @@ constraint_u public.integration_health.integration_health_integration_name_key
ALTER TABLE ONLY public.integration_health ADD CONSTRAINT integration_health_integration_name_key UNIQUE (integration_name);
-- @@ constraint_p public.integration_health.integration_health_pkey
ALTER TABLE ONLY public.integration_health ADD CONSTRAINT integration_health_pkey PRIMARY KEY (id);
-- @@ constraint_p public.maintenance_log.maintenance_log_pkey
ALTER TABLE ONLY public.maintenance_log ADD CONSTRAINT maintenance_log_pkey PRIMARY KEY (id);
-- @@ constraint_p public.maintenance_schedules.maintenance_schedules_pkey
ALTER TABLE ONLY public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_pkey PRIMARY KEY (id);
-- @@ constraint_p public.mig0003_decoded.mig0003_decoded_pkey
ALTER TABLE ONLY public.mig0003_decoded ADD CONSTRAINT mig0003_decoded_pkey PRIMARY KEY (id);
-- @@ constraint_p public.mig0003_smoke.mig0003_smoke_pkey
ALTER TABLE ONLY public.mig0003_smoke ADD CONSTRAINT mig0003_smoke_pkey PRIMARY KEY (k);
-- @@ constraint_p public.mig0006_drift_src.mig0006_drift_src_pkey
ALTER TABLE ONLY public.mig0006_drift_src ADD CONSTRAINT mig0006_drift_src_pkey PRIMARY KEY (part);
-- @@ constraint_p public.mig0006_smoke.mig0006_smoke_pkey
ALTER TABLE ONLY public.mig0006_smoke ADD CONSTRAINT mig0006_smoke_pkey PRIMARY KEY (label);
-- @@ constraint_p public.mig0006_source.mig0006_source_pkey
ALTER TABLE ONLY public.mig0006_source ADD CONSTRAINT mig0006_source_pkey PRIMARY KEY (part);
-- @@ constraint_u public.model_parameters.model_parameters_depot_id_parameter_group_key
ALTER TABLE ONLY public.model_parameters ADD CONSTRAINT model_parameters_depot_id_parameter_group_key UNIQUE (depot_id, parameter_group);
-- @@ constraint_p public.model_parameters.model_parameters_pkey
ALTER TABLE ONLY public.model_parameters ADD CONSTRAINT model_parameters_pkey PRIMARY KEY (id);
-- @@ constraint_p public.model_tuning_runs.model_tuning_runs_pkey
ALTER TABLE ONLY public.model_tuning_runs ADD CONSTRAINT model_tuning_runs_pkey PRIMARY KEY (id);
-- @@ constraint_u public.model_versions.model_versions_depot_id_parameter_group_version_number_key
ALTER TABLE ONLY public.model_versions ADD CONSTRAINT model_versions_depot_id_parameter_group_version_number_key UNIQUE (depot_id, parameter_group, version_number);
-- @@ constraint_u public.model_versions.model_versions_depot_id_parameter_group_version_tag_key
ALTER TABLE ONLY public.model_versions ADD CONSTRAINT model_versions_depot_id_parameter_group_version_tag_key UNIQUE (depot_id, parameter_group, version_tag);
-- @@ constraint_p public.model_versions.model_versions_pkey
ALTER TABLE ONLY public.model_versions ADD CONSTRAINT model_versions_pkey PRIMARY KEY (id);
-- @@ constraint_p public.notifications.notifications_pkey
ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ocpp_meter_values.ocpp_meter_values_pkey
ALTER TABLE ONLY public.ocpp_meter_values ADD CONSTRAINT ocpp_meter_values_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ocpp_sessions.ocpp_sessions_pkey
ALTER TABLE ONLY public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_pkey PRIMARY KEY (id);
-- @@ constraint_u public.ocpp_sessions.ocpp_sessions_transaction_id_key
ALTER TABLE ONLY public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_transaction_id_key UNIQUE (transaction_id);
-- @@ constraint_p public.ottoq_0249_start_log.ottoq_0249_start_log_pkey
ALTER TABLE ONLY public.ottoq_0249_start_log ADD CONSTRAINT ottoq_0249_start_log_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ottoq_ab_runs.ottoq_ab_runs_pkey
ALTER TABLE ONLY public.ottoq_ab_runs ADD CONSTRAINT ottoq_ab_runs_pkey PRIMARY KEY (ab_run_id);
-- @@ constraint_p public.ottoq_agent_call_ledger.ottoq_agent_call_ledger_pkey
ALTER TABLE ONLY public.ottoq_agent_call_ledger ADD CONSTRAINT ottoq_agent_call_ledger_pkey PRIMARY KEY (call_id);
-- @@ constraint_p public.ottoq_agent_charge_orders.ottoq_agent_charge_orders_pkey
ALTER TABLE ONLY public.ottoq_agent_charge_orders ADD CONSTRAINT ottoq_agent_charge_orders_pkey PRIMARY KEY (order_id);
-- @@ constraint_p public.ottoq_agent_demo_passcode.ottoq_agent_demo_passcode_pkey
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ADD CONSTRAINT ottoq_agent_demo_passcode_pkey PRIMARY KEY (depot_id);
-- @@ constraint_u public.ottoq_agent_pass_evidence.ottoq_agent_pass_evidence_chain_id_key
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ADD CONSTRAINT ottoq_agent_pass_evidence_chain_id_key UNIQUE (chain_id);
-- @@ constraint_p public.ottoq_agent_pass_evidence.ottoq_agent_pass_evidence_pkey
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ADD CONSTRAINT ottoq_agent_pass_evidence_pkey PRIMARY KEY (pass_id);
-- @@ constraint_u public.ottoq_agent_principals.ottoq_agent_principals_name_key
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_name_key UNIQUE (name);
-- @@ constraint_p public.ottoq_agent_principals.ottoq_agent_principals_pkey
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_pkey PRIMARY KEY (principal_id);
-- @@ constraint_u public.ottoq_agent_principals.ottoq_agent_principals_token_hash_key
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_token_hash_key UNIQUE (token_hash);
-- @@ constraint_p public.ottoq_agent_prompts.ottoq_agent_prompts_pkey
ALTER TABLE ONLY public.ottoq_agent_prompts ADD CONSTRAINT ottoq_agent_prompts_pkey PRIMARY KEY (prompt_sha256);
-- @@ constraint_p public.ottoq_agent_requests.ottoq_agent_requests_pkey
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_pkey PRIMARY KEY (request_id);
-- @@ constraint_u public.ottoq_anomaly_detectors.ottoq_anomaly_detectors_detector_code_key
ALTER TABLE ONLY public.ottoq_anomaly_detectors ADD CONSTRAINT ottoq_anomaly_detectors_detector_code_key UNIQUE (detector_code);
-- @@ constraint_p public.ottoq_anomaly_detectors.ottoq_anomaly_detectors_pkey
ALTER TABLE ONLY public.ottoq_anomaly_detectors ADD CONSTRAINT ottoq_anomaly_detectors_pkey PRIMARY KEY (detector_id);
-- @@ constraint_u public.ottoq_anomaly_observations.ottoq_anomaly_observations_observation_seq_key
ALTER TABLE ONLY public.ottoq_anomaly_observations ADD CONSTRAINT ottoq_anomaly_observations_observation_seq_key UNIQUE (observation_seq);
-- @@ constraint_p public.ottoq_anomaly_observations.ottoq_anomaly_observations_pkey
ALTER TABLE ONLY public.ottoq_anomaly_observations ADD CONSTRAINT ottoq_anomaly_observations_pkey PRIMARY KEY (observation_id);
-- @@ constraint_p public.ottoq_arbiter_assessments.ottoq_arbiter_assessments_pkey
ALTER TABLE ONLY public.ottoq_arbiter_assessments ADD CONSTRAINT ottoq_arbiter_assessments_pkey PRIMARY KEY (assessment_id);
-- @@ constraint_u public.ottoq_audit_bundles.ottoq_audit_bundles_bundle_code_key
ALTER TABLE ONLY public.ottoq_audit_bundles ADD CONSTRAINT ottoq_audit_bundles_bundle_code_key UNIQUE (bundle_code);
-- @@ constraint_u public.ottoq_audit_bundles.ottoq_audit_bundles_bundle_seq_key
ALTER TABLE ONLY public.ottoq_audit_bundles ADD CONSTRAINT ottoq_audit_bundles_bundle_seq_key UNIQUE (bundle_seq);
-- @@ constraint_p public.ottoq_audit_bundles.ottoq_audit_bundles_pkey
ALTER TABLE ONLY public.ottoq_audit_bundles ADD CONSTRAINT ottoq_audit_bundles_pkey PRIMARY KEY (bundle_id);
-- @@ constraint_p public.ottoq_audit_reports.ottoq_audit_reports_pkey
ALTER TABLE ONLY public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_pkey PRIMARY KEY (report_id);
-- @@ constraint_u public.ottoq_audit_reports.ottoq_audit_reports_report_seq_key
ALTER TABLE ONLY public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_report_seq_key UNIQUE (report_seq);
-- @@ constraint_p public.ottoq_bay_binding_witness.ottoq_bay_binding_witness_pkey
ALTER TABLE ONLY public.ottoq_bay_binding_witness ADD CONSTRAINT ottoq_bay_binding_witness_pkey PRIMARY KEY (witness_id);
-- @@ constraint_p public.ottoq_benchmark_frames.ottoq_benchmark_frames_pkey
ALTER TABLE ONLY public.ottoq_benchmark_frames ADD CONSTRAINT ottoq_benchmark_frames_pkey PRIMARY KEY (id);
-- @@ constraint_u public.ottoq_bess_units.ottoq_bess_units_bess_identifier_key
ALTER TABLE ONLY public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_bess_identifier_key UNIQUE (bess_identifier);
-- @@ constraint_p public.ottoq_bess_units.ottoq_bess_units_pkey
ALTER TABLE ONLY public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_pkey PRIMARY KEY (bess_id);
-- @@ constraint_u public.ottoq_calibration_correlations.ottoq_calibration_correlation_dataset_code_variable_a_varia_key
ALTER TABLE ONLY public.ottoq_calibration_correlations ADD CONSTRAINT ottoq_calibration_correlation_dataset_code_variable_a_varia_key UNIQUE (dataset_code, variable_a, variable_b, method);
-- @@ constraint_p public.ottoq_calibration_correlations.ottoq_calibration_correlations_pkey
ALTER TABLE ONLY public.ottoq_calibration_correlations ADD CONSTRAINT ottoq_calibration_correlations_pkey PRIMARY KEY (correlation_id);
-- @@ constraint_p public.ottoq_calibration_datasets.ottoq_calibration_datasets_pkey
ALTER TABLE ONLY public.ottoq_calibration_datasets ADD CONSTRAINT ottoq_calibration_datasets_pkey PRIMARY KEY (dataset_code);
-- @@ constraint_u public.ottoq_calibration_distributions.ottoq_calibration_distributio_dataset_code_variable_name_se_key
ALTER TABLE ONLY public.ottoq_calibration_distributions ADD CONSTRAINT ottoq_calibration_distributio_dataset_code_variable_name_se_key UNIQUE (dataset_code, variable_name, segment);
-- @@ constraint_p public.ottoq_calibration_distributions.ottoq_calibration_distributions_pkey
ALTER TABLE ONLY public.ottoq_calibration_distributions ADD CONSTRAINT ottoq_calibration_distributions_pkey PRIMARY KEY (distribution_id);
-- @@ constraint_p public.ottoq_calibration_metrics.ottoq_calibration_metrics_pkey
ALTER TABLE ONLY public.ottoq_calibration_metrics ADD CONSTRAINT ottoq_calibration_metrics_pkey PRIMARY KEY (calibration_id);
-- @@ constraint_u public.ottoq_calibration_profiles.ottoq_calibration_profiles_dataset_code_profile_name_key
ALTER TABLE ONLY public.ottoq_calibration_profiles ADD CONSTRAINT ottoq_calibration_profiles_dataset_code_profile_name_key UNIQUE (dataset_code, profile_name);
-- @@ constraint_p public.ottoq_calibration_profiles.ottoq_calibration_profiles_pkey
ALTER TABLE ONLY public.ottoq_calibration_profiles ADD CONSTRAINT ottoq_calibration_profiles_pkey PRIMARY KEY (profile_id);
-- @@ constraint_p public.ottoq_canopy_state.ottoq_canopy_state_pkey
ALTER TABLE ONLY public.ottoq_canopy_state ADD CONSTRAINT ottoq_canopy_state_pkey PRIMARY KEY (canopy_code);
-- @@ constraint_p public.ottoq_cert_columns.ottoq_cert_columns_pkey
ALTER TABLE ONLY public.ottoq_cert_columns ADD CONSTRAINT ottoq_cert_columns_pkey PRIMARY KEY (depot_id, scenario, seed, ticks);
-- @@ constraint_p public.ottoq_cert_lineage.ottoq_cert_lineage_pkey
ALTER TABLE ONLY public.ottoq_cert_lineage ADD CONSTRAINT ottoq_cert_lineage_pkey PRIMARY KEY (name);
-- @@ constraint_p public.ottoq_cert_queue.ottoq_cert_queue_pkey
ALTER TABLE ONLY public.ottoq_cert_queue ADD CONSTRAINT ottoq_cert_queue_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ottoq_certified_proposers.ottoq_certified_proposers_pkey
ALTER TABLE ONLY public.ottoq_certified_proposers ADD CONSTRAINT ottoq_certified_proposers_pkey PRIMARY KEY (source);
-- @@ constraint_u public.ottoq_challenger_findings.ottoq_challenger_findings_episode
ALTER TABLE ONLY public.ottoq_challenger_findings ADD CONSTRAINT ottoq_challenger_findings_episode UNIQUE NULLS NOT DISTINCT (sim_run_id, question, episode_key);
-- @@ constraint_p public.ottoq_challenger_findings.ottoq_challenger_findings_pkey
ALTER TABLE ONLY public.ottoq_challenger_findings ADD CONSTRAINT ottoq_challenger_findings_pkey PRIMARY KEY (finding_id);
-- @@ constraint_p public.ottoq_channel_health.ottoq_channel_health_pkey
ALTER TABLE ONLY public.ottoq_channel_health ADD CONSTRAINT ottoq_channel_health_pkey PRIMARY KEY (health_id);
-- @@ constraint_p public.ottoq_charge_clock_fits.ottoq_charge_clock_fits_pkey
ALTER TABLE ONLY public.ottoq_charge_clock_fits ADD CONSTRAINT ottoq_charge_clock_fits_pkey PRIMARY KEY (fit_id);
-- @@ constraint_p public.ottoq_charge_duration_ledger.ottoq_charge_duration_ledger_pkey
ALTER TABLE ONLY public.ottoq_charge_duration_ledger ADD CONSTRAINT ottoq_charge_duration_ledger_pkey PRIMARY KEY (session_id);
-- @@ constraint_p public.ottoq_charge_fault_fits.ottoq_charge_fault_fits_pkey
ALTER TABLE ONLY public.ottoq_charge_fault_fits ADD CONSTRAINT ottoq_charge_fault_fits_pkey PRIMARY KEY (fit_id);
-- @@ constraint_p public.ottoq_charge_order_attribution.ottoq_charge_order_attribution_pkey
ALTER TABLE ONLY public.ottoq_charge_order_attribution ADD CONSTRAINT ottoq_charge_order_attribution_pkey PRIMARY KEY (order_id);
-- @@ constraint_p public.ottoq_charge_order_hindsight.ottoq_charge_order_hindsight_pkey
ALTER TABLE ONLY public.ottoq_charge_order_hindsight ADD CONSTRAINT ottoq_charge_order_hindsight_pkey PRIMARY KEY (order_id);
-- @@ constraint_p public.ottoq_charge_order_reattributions.ottoq_charge_order_reattributions_pkey
ALTER TABLE ONLY public.ottoq_charge_order_reattributions ADD CONSTRAINT ottoq_charge_order_reattributions_pkey PRIMARY KEY (order_id, code_md5);
-- @@ constraint_p public.ottoq_charge_order_regrades.ottoq_charge_order_regrades_pkey
ALTER TABLE ONLY public.ottoq_charge_order_regrades ADD CONSTRAINT ottoq_charge_order_regrades_pkey PRIMARY KEY (order_id, code_md5);
-- @@ constraint_p public.ottoq_charge_order_snapshots.ottoq_charge_order_snapshots_pkey
ALTER TABLE ONLY public.ottoq_charge_order_snapshots ADD CONSTRAINT ottoq_charge_order_snapshots_pkey PRIMARY KEY (order_id);
-- @@ constraint_p public.ottoq_charge_window_calibration.ottoq_charge_window_calibration_pkey
ALTER TABLE ONLY public.ottoq_charge_window_calibration ADD CONSTRAINT ottoq_charge_window_calibration_pkey PRIMARY KEY (calibration_id);
-- @@ constraint_p public.ottoq_cil_adoptions.ottoq_cil_adoptions_pkey
ALTER TABLE ONLY public.ottoq_cil_adoptions ADD CONSTRAINT ottoq_cil_adoptions_pkey PRIMARY KEY (adoption_id);
-- @@ constraint_p public.ottoq_command_actor_registry.ottoq_command_actor_registry_pkey
ALTER TABLE ONLY public.ottoq_command_actor_registry ADD CONSTRAINT ottoq_command_actor_registry_pkey PRIMARY KEY (actor);
-- @@ constraint_p public.ottoq_comms_messages.ottoq_comms_messages_pkey
ALTER TABLE ONLY public.ottoq_comms_messages ADD CONSTRAINT ottoq_comms_messages_pkey PRIMARY KEY (msg_id);
-- @@ constraint_u public.ottoq_counterfactuals.ottoq_counterfactuals_counterfactual_seq_key
ALTER TABLE ONLY public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_counterfactual_seq_key UNIQUE (counterfactual_seq);
-- @@ constraint_p public.ottoq_counterfactuals.ottoq_counterfactuals_pkey
ALTER TABLE ONLY public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_pkey PRIMARY KEY (counterfactual_id);
-- @@ constraint_p public.ottoq_cuopt_deferrals.ottoq_cuopt_deferrals_pkey
ALTER TABLE ONLY public.ottoq_cuopt_deferrals ADD CONSTRAINT ottoq_cuopt_deferrals_pkey PRIMARY KEY (sim_run_id, vehicle_id);
-- @@ constraint_p public.ottoq_cuopt_fire_log.ottoq_cuopt_fire_log_pkey
ALTER TABLE ONLY public.ottoq_cuopt_fire_log ADD CONSTRAINT ottoq_cuopt_fire_log_pkey PRIMARY KEY (sim_run_id);
-- @@ constraint_p public.ottoq_data_drift_metrics.ottoq_data_drift_metrics_pkey
ALTER TABLE ONLY public.ottoq_data_drift_metrics ADD CONSTRAINT ottoq_data_drift_metrics_pkey PRIMARY KEY (drift_id);
-- @@ constraint_p public.ottoq_decision_snapshots.ottoq_decision_snapshots_pkey
ALTER TABLE ONLY public.ottoq_decision_snapshots ADD CONSTRAINT ottoq_decision_snapshots_pkey PRIMARY KEY (snapshot_id);
-- @@ constraint_u public.ottoq_decision_snapshots.ottoq_decision_snapshots_sim_run_id_tick_seq_key
ALTER TABLE ONLY public.ottoq_decision_snapshots ADD CONSTRAINT ottoq_decision_snapshots_sim_run_id_tick_seq_key UNIQUE (sim_run_id, tick_seq);
-- @@ constraint_u public.ottoq_decisions.ottoq_decisions_decision_seq_key
ALTER TABLE ONLY public.ottoq_decisions ADD CONSTRAINT ottoq_decisions_decision_seq_key UNIQUE (decision_seq);
-- @@ constraint_p public.ottoq_decisions.ottoq_decisions_pkey
ALTER TABLE ONLY public.ottoq_decisions ADD CONSTRAINT ottoq_decisions_pkey PRIMARY KEY (decision_id);
-- @@ constraint_p public.ottoq_deploy_log.ottoq_deploy_log_pkey
ALTER TABLE ONLY public.ottoq_deploy_log ADD CONSTRAINT ottoq_deploy_log_pkey PRIMARY KEY (deploy_id);
-- @@ constraint_u public.ottoq_depot_benchmarks_daily.ottoq_depot_benchmarks_daily_depot_id_report_date_key
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ADD CONSTRAINT ottoq_depot_benchmarks_daily_depot_id_report_date_key UNIQUE (depot_id, report_date);
-- @@ constraint_p public.ottoq_depot_benchmarks_daily.ottoq_depot_benchmarks_daily_pkey
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ADD CONSTRAINT ottoq_depot_benchmarks_daily_pkey PRIMARY KEY (benchmark_id);
-- @@ constraint_u public.ottoq_depot_cost_daily.ottoq_depot_cost_daily_depot_id_report_date_key
ALTER TABLE ONLY public.ottoq_depot_cost_daily ADD CONSTRAINT ottoq_depot_cost_daily_depot_id_report_date_key UNIQUE (depot_id, report_date);
-- @@ constraint_p public.ottoq_depot_cost_daily.ottoq_depot_cost_daily_pkey
ALTER TABLE ONLY public.ottoq_depot_cost_daily ADD CONSTRAINT ottoq_depot_cost_daily_pkey PRIMARY KEY (depot_cost_daily_id);
-- @@ constraint_p public.ottoq_depot_shifts.ottoq_depot_shifts_pkey
ALTER TABLE ONLY public.ottoq_depot_shifts ADD CONSTRAINT ottoq_depot_shifts_pkey PRIMARY KEY (shift_id);
-- @@ constraint_p public.ottoq_depot_staffing.ottoq_depot_staffing_pkey
ALTER TABLE ONLY public.ottoq_depot_staffing ADD CONSTRAINT ottoq_depot_staffing_pkey PRIMARY KEY (depot_id, role);
-- @@ constraint_p public.ottoq_depot_tariffs.ottoq_depot_tariffs_pkey
ALTER TABLE ONLY public.ottoq_depot_tariffs ADD CONSTRAINT ottoq_depot_tariffs_pkey PRIMARY KEY (tariff_row_id);
-- @@ constraint_p public.ottoq_determinism_verdict_ledger.ottoq_determinism_verdict_ledger_pkey
ALTER TABLE ONLY public.ottoq_determinism_verdict_ledger ADD CONSTRAINT ottoq_determinism_verdict_ledger_pkey PRIMARY KEY (verdict_id);
-- @@ constraint_p public.ottoq_dial_experiments.ottoq_dial_experiments_pkey
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_pkey PRIMARY KEY (experiment_id);
-- @@ constraint_u public.ottoq_dial_pair_ledger.ottoq_dial_pair_ledger_one_seed_per_engine
ALTER TABLE ONLY public.ottoq_dial_pair_ledger ADD CONSTRAINT ottoq_dial_pair_ledger_one_seed_per_engine UNIQUE (experiment_id, seed, engine_hash);
-- @@ constraint_p public.ottoq_dial_pair_ledger.ottoq_dial_pair_ledger_pkey
ALTER TABLE ONLY public.ottoq_dial_pair_ledger ADD CONSTRAINT ottoq_dial_pair_ledger_pkey PRIMARY KEY (pair_id);
-- @@ constraint_p public.ottoq_dial_promotion_ledger.ottoq_dial_promotion_ledger_pkey
ALTER TABLE ONLY public.ottoq_dial_promotion_ledger ADD CONSTRAINT ottoq_dial_promotion_ledger_pkey PRIMARY KEY (promotion_id);
-- @@ constraint_p public.ottoq_dr_calls.ottoq_dr_calls_pkey
ALTER TABLE ONLY public.ottoq_dr_calls ADD CONSTRAINT ottoq_dr_calls_pkey PRIMARY KEY (dr_call_id);
-- @@ constraint_p public.ottoq_dtc_catalog.ottoq_dtc_catalog_pkey
ALTER TABLE ONLY public.ottoq_dtc_catalog ADD CONSTRAINT ottoq_dtc_catalog_pkey PRIMARY KEY (dtc_code);
-- @@ constraint_u public.ottoq_emergency_invocations.ottoq_emergency_invocations_invocation_seq_key
ALTER TABLE ONLY public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_invocation_seq_key UNIQUE (invocation_seq);
-- @@ constraint_p public.ottoq_emergency_invocations.ottoq_emergency_invocations_pkey
ALTER TABLE ONLY public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_pkey PRIMARY KEY (invocation_id);
-- @@ constraint_p public.ottoq_emergency_protocols.ottoq_emergency_protocols_pkey
ALTER TABLE ONLY public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_pkey PRIMARY KEY (protocol_id);
-- @@ constraint_u public.ottoq_emergency_protocols.ottoq_emergency_protocols_protocol_code_key
ALTER TABLE ONLY public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_protocol_code_key UNIQUE (protocol_code);
-- @@ constraint_p public.ottoq_enactment_branches.ottoq_enactment_branches_pkey
ALTER TABLE ONLY public.ottoq_enactment_branches ADD CONSTRAINT ottoq_enactment_branches_pkey PRIMARY KEY (resolved_action_context);
-- @@ constraint_p public.ottoq_energy_commands.ottoq_energy_commands_pkey
ALTER TABLE ONLY public.ottoq_energy_commands ADD CONSTRAINT ottoq_energy_commands_pkey PRIMARY KEY (command_id);
-- @@ constraint_p public.ottoq_energy_plan.ottoq_energy_plan_pkey
ALTER TABLE ONLY public.ottoq_energy_plan ADD CONSTRAINT ottoq_energy_plan_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ottoq_energy_rates.ottoq_energy_rates_pkey
ALTER TABLE ONLY public.ottoq_energy_rates ADD CONSTRAINT ottoq_energy_rates_pkey PRIMARY KEY (rate_code);
-- @@ constraint_p public.ottoq_event_state_anchor.ottoq_event_state_anchor_pkey
ALTER TABLE ONLY public.ottoq_event_state_anchor ADD CONSTRAINT ottoq_event_state_anchor_pkey PRIMARY KEY (run_key, event_type, entity_id, anchor_day);
-- @@ constraint_p public.ottoq_event_types_catalog.ottoq_event_types_catalog_pkey
ALTER TABLE ONLY public.ottoq_event_types_catalog ADD CONSTRAINT ottoq_event_types_catalog_pkey PRIMARY KEY (event_type);
-- @@ constraint_u public.ottoq_events.ottoq_events_keep_event_seq_key
ALTER TABLE ONLY public.ottoq_events ADD CONSTRAINT ottoq_events_keep_event_seq_key UNIQUE (event_seq);
-- @@ constraint_p public.ottoq_events.ottoq_events_keep_pkey
ALTER TABLE ONLY public.ottoq_events ADD CONSTRAINT ottoq_events_keep_pkey PRIMARY KEY (event_id);
-- @@ constraint_p public.ottoq_evidence_regimes.ottoq_evidence_regimes_pkey
ALTER TABLE ONLY public.ottoq_evidence_regimes ADD CONSTRAINT ottoq_evidence_regimes_pkey PRIMARY KEY (regime_id);
-- @@ constraint_p public.ottoq_external_proposals.ottoq_external_proposals_pkey
ALTER TABLE ONLY public.ottoq_external_proposals ADD CONSTRAINT ottoq_external_proposals_pkey PRIMARY KEY (proposal_id);
-- @@ constraint_p public.ottoq_feature_values.ottoq_feature_values_pkey
ALTER TABLE ONLY public.ottoq_feature_values ADD CONSTRAINT ottoq_feature_values_pkey PRIMARY KEY (value_id);
-- @@ constraint_u public.ottoq_feature_values.ottoq_feature_values_value_seq_key
ALTER TABLE ONLY public.ottoq_feature_values ADD CONSTRAINT ottoq_feature_values_value_seq_key UNIQUE (value_seq);
-- @@ constraint_p public.ottoq_features.ottoq_features_pkey
ALTER TABLE ONLY public.ottoq_features ADD CONSTRAINT ottoq_features_pkey PRIMARY KEY (feature_name);
-- @@ constraint_p public.ottoq_feed_activations.ottoq_feed_activations_pkey
ALTER TABLE ONLY public.ottoq_feed_activations ADD CONSTRAINT ottoq_feed_activations_pkey PRIMARY KEY (activation_id);
-- @@ constraint_u public.ottoq_feed_activations.ottoq_feed_activations_sim_run_id_var_key_key
ALTER TABLE ONLY public.ottoq_feed_activations ADD CONSTRAINT ottoq_feed_activations_sim_run_id_var_key_key UNIQUE (sim_run_id, var_key);
-- @@ constraint_p public.ottoq_feed_plan_promotions.ottoq_feed_plan_promotions_pkey
ALTER TABLE ONLY public.ottoq_feed_plan_promotions ADD CONSTRAINT ottoq_feed_plan_promotions_pkey PRIMARY KEY (promotion_id);
-- @@ constraint_p public.ottoq_feed_plans.ottoq_feed_plans_pkey
ALTER TABLE ONLY public.ottoq_feed_plans ADD CONSTRAINT ottoq_feed_plans_pkey PRIMARY KEY (plan_id);
-- @@ constraint_u public.ottoq_feed_plans.ottoq_feed_plans_var_key_version_key
ALTER TABLE ONLY public.ottoq_feed_plans ADD CONSTRAINT ottoq_feed_plans_var_key_version_key UNIQUE (var_key, version);
-- @@ constraint_p public.ottoq_fleet_buildout_active.ottoq_fleet_buildout_active_pkey
ALTER TABLE ONLY public.ottoq_fleet_buildout_active ADD CONSTRAINT ottoq_fleet_buildout_active_pkey PRIMARY KEY (depot_id);
-- @@ constraint_p public.ottoq_fleet_buildouts.ottoq_fleet_buildouts_pkey
ALTER TABLE ONLY public.ottoq_fleet_buildouts ADD CONSTRAINT ottoq_fleet_buildouts_pkey PRIMARY KEY (fleet_code);
-- @@ constraint_u public.ottoq_fleet_operator_slas.ottoq_fleet_operator_slas_fleet_operator_id_version_key
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_fleet_operator_id_version_key UNIQUE (fleet_operator_id, version);
-- @@ constraint_p public.ottoq_fleet_operator_slas.ottoq_fleet_operator_slas_pkey
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_pkey PRIMARY KEY (sla_id);
-- @@ constraint_p public.ottoq_fn_backup_cold_start.ottoq_fn_backup_cold_start_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_cold_start ADD CONSTRAINT ottoq_fn_backup_cold_start_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_dcfc_day_night.ottoq_fn_backup_dcfc_day_night_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_dcfc_day_night ADD CONSTRAINT ottoq_fn_backup_dcfc_day_night_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_dcfc_first.ottoq_fn_backup_dcfc_first_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_dcfc_first ADD CONSTRAINT ottoq_fn_backup_dcfc_first_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_demate_deadlock.ottoq_fn_backup_demate_deadlock_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_demate_deadlock ADD CONSTRAINT ottoq_fn_backup_demate_deadlock_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_frozen_target.ottoq_fn_backup_frozen_target_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_frozen_target ADD CONSTRAINT ottoq_fn_backup_frozen_target_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_geometry_contract.ottoq_fn_backup_geometry_contract_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_geometry_contract ADD CONSTRAINT ottoq_fn_backup_geometry_contract_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_night_waves.ottoq_fn_backup_night_waves_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_night_waves ADD CONSTRAINT ottoq_fn_backup_night_waves_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_plug_target_policy.ottoq_fn_backup_plug_target_policy_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_plug_target_policy ADD CONSTRAINT ottoq_fn_backup_plug_target_policy_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_single_run.ottoq_fn_backup_single_run_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_single_run ADD CONSTRAINT ottoq_fn_backup_single_run_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_stall_watchdog.ottoq_fn_backup_stall_watchdog_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_stall_watchdog ADD CONSTRAINT ottoq_fn_backup_stall_watchdog_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_supersede_churn.ottoq_fn_backup_supersede_churn_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_supersede_churn ADD CONSTRAINT ottoq_fn_backup_supersede_churn_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_backup_tick_observability.ottoq_fn_backup_tick_observability_pkey
ALTER TABLE ONLY public.ottoq_fn_backup_tick_observability ADD CONSTRAINT ottoq_fn_backup_tick_observability_pkey PRIMARY KEY (fn);
-- @@ constraint_p public.ottoq_fn_definition_backups.ottoq_fn_definition_backups_pkey
ALTER TABLE ONLY public.ottoq_fn_definition_backups ADD CONSTRAINT ottoq_fn_definition_backups_pkey PRIMARY KEY (backup_id);
-- @@ constraint_p public.ottoq_grant_snapshot_0198.ottoq_grant_snapshot_0198_pkey
ALTER TABLE ONLY public.ottoq_grant_snapshot_0198 ADD CONSTRAINT ottoq_grant_snapshot_0198_pkey PRIMARY KEY (schema_name, function_name, identity_args);
-- @@ constraint_p public.ottoq_grid_events.ottoq_grid_events_pkey
ALTER TABLE ONLY public.ottoq_grid_events ADD CONSTRAINT ottoq_grid_events_pkey PRIMARY KEY (grid_event_id);
-- @@ constraint_p public.ottoq_grid_snapshots.ottoq_grid_snapshots_pkey
ALTER TABLE ONLY public.ottoq_grid_snapshots ADD CONSTRAINT ottoq_grid_snapshots_pkey PRIMARY KEY (snapshot_id);
-- @@ constraint_u public.ottoq_incident_reports.ottoq_incident_reports_incident_report_seq_key
ALTER TABLE ONLY public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_incident_report_seq_key UNIQUE (incident_report_seq);
-- @@ constraint_p public.ottoq_incident_reports.ottoq_incident_reports_pkey
ALTER TABLE ONLY public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_pkey PRIMARY KEY (incident_report_id);
-- @@ constraint_u public.ottoq_inference_log.ottoq_inference_log_inference_seq_key
ALTER TABLE ONLY public.ottoq_inference_log ADD CONSTRAINT ottoq_inference_log_inference_seq_key UNIQUE (inference_seq);
-- @@ constraint_p public.ottoq_inference_log.ottoq_inference_log_pkey
ALTER TABLE ONLY public.ottoq_inference_log ADD CONSTRAINT ottoq_inference_log_pkey PRIMARY KEY (inference_id);
-- @@ constraint_p public.ottoq_intelligence_snapshot.ottoq_intelligence_snapshot_pkey
ALTER TABLE ONLY public.ottoq_intelligence_snapshot ADD CONSTRAINT ottoq_intelligence_snapshot_pkey PRIMARY KEY (source);
-- @@ constraint_u public.ottoq_intelligence_sources.ottoq_intelligence_sources_l2_engine_label_key
ALTER TABLE ONLY public.ottoq_intelligence_sources ADD CONSTRAINT ottoq_intelligence_sources_l2_engine_label_key UNIQUE (l2_engine_label);
-- @@ constraint_p public.ottoq_intelligence_sources.ottoq_intelligence_sources_pkey
ALTER TABLE ONLY public.ottoq_intelligence_sources ADD CONSTRAINT ottoq_intelligence_sources_pkey PRIMARY KEY (source);
-- @@ constraint_u public.ottoq_itinerary_legs.ottoq_itinerary_legs_itinerary_id_seq_key
ALTER TABLE ONLY public.ottoq_itinerary_legs ADD CONSTRAINT ottoq_itinerary_legs_itinerary_id_seq_key UNIQUE (itinerary_id, seq);
-- @@ constraint_p public.ottoq_itinerary_legs.ottoq_itinerary_legs_pkey
ALTER TABLE ONLY public.ottoq_itinerary_legs ADD CONSTRAINT ottoq_itinerary_legs_pkey PRIMARY KEY (leg_id);
-- @@ constraint_p public.ottoq_kpi_touch_actor_types.ottoq_kpi_touch_actor_types_pkey
ALTER TABLE ONLY public.ottoq_kpi_touch_actor_types ADD CONSTRAINT ottoq_kpi_touch_actor_types_pkey PRIMARY KEY (actor_type);
-- @@ constraint_p public.ottoq_kpi_touch_lanes.ottoq_kpi_touch_lanes_pkey
ALTER TABLE ONLY public.ottoq_kpi_touch_lanes ADD CONSTRAINT ottoq_kpi_touch_lanes_pkey PRIMARY KEY (lane);
-- @@ constraint_p public.ottoq_learned_estimates.ottoq_learned_estimates_pkey
ALTER TABLE ONLY public.ottoq_learned_estimates ADD CONSTRAINT ottoq_learned_estimates_pkey PRIMARY KEY (estimate_id);
-- @@ constraint_p public.ottoq_margin_prices.ottoq_margin_prices_pkey
ALTER TABLE ONLY public.ottoq_margin_prices ADD CONSTRAINT ottoq_margin_prices_pkey PRIMARY KEY (price_code);
-- @@ constraint_p public.ottoq_model_artifacts.ottoq_model_artifacts_pkey
ALTER TABLE ONLY public.ottoq_model_artifacts ADD CONSTRAINT ottoq_model_artifacts_pkey PRIMARY KEY (artifact_id);
-- @@ constraint_u public.ottoq_model_artifacts.ottoq_model_artifacts_storage_path_key
ALTER TABLE ONLY public.ottoq_model_artifacts ADD CONSTRAINT ottoq_model_artifacts_storage_path_key UNIQUE (storage_path);
-- @@ constraint_p public.ottoq_model_call_ledger.ottoq_model_call_ledger_pkey
ALTER TABLE ONLY public.ottoq_model_call_ledger ADD CONSTRAINT ottoq_model_call_ledger_pkey PRIMARY KEY (call_id);
-- @@ constraint_p public.ottoq_model_routes.ottoq_model_routes_pkey
ALTER TABLE ONLY public.ottoq_model_routes ADD CONSTRAINT ottoq_model_routes_pkey PRIMARY KEY (route_id);
-- @@ constraint_u public.ottoq_oauth_auth_requests.ottoq_oauth_auth_requests_code_hash_key
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ADD CONSTRAINT ottoq_oauth_auth_requests_code_hash_key UNIQUE (code_hash);
-- @@ constraint_p public.ottoq_oauth_auth_requests.ottoq_oauth_auth_requests_pkey
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ADD CONSTRAINT ottoq_oauth_auth_requests_pkey PRIMARY KEY (request_id);
-- @@ constraint_p public.ottoq_oauth_clients.ottoq_oauth_clients_pkey
ALTER TABLE ONLY public.ottoq_oauth_clients ADD CONSTRAINT ottoq_oauth_clients_pkey PRIMARY KEY (client_id);
-- @@ constraint_p public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_pkey
ALTER TABLE ONLY public.ottoq_oauth_device_codes ADD CONSTRAINT ottoq_oauth_device_codes_pkey PRIMARY KEY (device_code_hash);
-- @@ constraint_u public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_user_code_key
ALTER TABLE ONLY public.ottoq_oauth_device_codes ADD CONSTRAINT ottoq_oauth_device_codes_user_code_key UNIQUE (user_code);
-- @@ constraint_p public.ottoq_oauth_grants.ottoq_oauth_grants_pkey
ALTER TABLE ONLY public.ottoq_oauth_grants ADD CONSTRAINT ottoq_oauth_grants_pkey PRIMARY KEY (principal_id);
-- @@ constraint_p public.ottoq_oauth_tokens.ottoq_oauth_tokens_pkey
ALTER TABLE ONLY public.ottoq_oauth_tokens ADD CONSTRAINT ottoq_oauth_tokens_pkey PRIMARY KEY (token_hash);
-- @@ constraint_u public.ottoq_ocpp_chargers.ottoq_ocpp_chargers_ocpp_identifier_key
ALTER TABLE ONLY public.ottoq_ocpp_chargers ADD CONSTRAINT ottoq_ocpp_chargers_ocpp_identifier_key UNIQUE (ocpp_identifier);
-- @@ constraint_p public.ottoq_ocpp_chargers.ottoq_ocpp_chargers_pkey
ALTER TABLE ONLY public.ottoq_ocpp_chargers ADD CONSTRAINT ottoq_ocpp_chargers_pkey PRIMARY KEY (charger_id);
-- @@ constraint_u public.ottoq_ocpp_messages.ottoq_ocpp_messages_message_seq_key
ALTER TABLE ONLY public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_message_seq_key UNIQUE (message_seq);
-- @@ constraint_p public.ottoq_ocpp_messages.ottoq_ocpp_messages_pkey
ALTER TABLE ONLY public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_pkey PRIMARY KEY (message_id);
-- @@ constraint_p public.ottoq_oem_webhook_log.ottoq_oem_webhook_log_pkey
ALTER TABLE ONLY public.ottoq_oem_webhook_log ADD CONSTRAINT ottoq_oem_webhook_log_pkey PRIMARY KEY (webhook_id);
-- @@ constraint_p public.ottoq_oem_webhook_patterns.ottoq_oem_webhook_patterns_pkey
ALTER TABLE ONLY public.ottoq_oem_webhook_patterns ADD CONSTRAINT ottoq_oem_webhook_patterns_pkey PRIMARY KEY (oem_name);
-- @@ constraint_p public.ottoq_operation_catalog.ottoq_operation_catalog_pkey
ALTER TABLE ONLY public.ottoq_operation_catalog ADD CONSTRAINT ottoq_operation_catalog_pkey PRIMARY KEY (pack_id, operation_code);
-- @@ constraint_p public.ottoq_ops_approvals.ottoq_ops_approvals_pkey
ALTER TABLE ONLY public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_pkey PRIMARY KEY (approval_id);
-- @@ constraint_p public.ottoq_owner_accounts.ottoq_owner_accounts_pkey
ALTER TABLE ONLY public.ottoq_owner_accounts ADD CONSTRAINT ottoq_owner_accounts_pkey PRIMARY KEY (account_id);
-- @@ constraint_p public.ottoq_owner_commands.ottoq_owner_commands_pkey
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_pkey PRIMARY KEY (command_id);
-- @@ constraint_p public.ottoq_owner_settings.ottoq_owner_settings_pkey
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_pkey PRIMARY KEY (setting_id);
-- @@ constraint_p public.ottoq_policy_param_catalog.ottoq_policy_param_catalog_pkey
ALTER TABLE ONLY public.ottoq_policy_param_catalog ADD CONSTRAINT ottoq_policy_param_catalog_pkey PRIMARY KEY (param_key);
-- @@ constraint_p public.ottoq_policy_params.ottoq_policy_params_pkey
ALTER TABLE ONLY public.ottoq_policy_params ADD CONSTRAINT ottoq_policy_params_pkey PRIMARY KEY (scope_type, scope_id, param_key);
-- @@ constraint_u public.ottoq_prediction_accuracy_heatmap.ottoq_prediction_accuracy_hea_prediction_type_depot_id_flee_key
ALTER TABLE ONLY public.ottoq_prediction_accuracy_heatmap ADD CONSTRAINT ottoq_prediction_accuracy_hea_prediction_type_depot_id_flee_key UNIQUE (prediction_type, depot_id, fleet_operator_id, vehicle_class, horizon_minutes, hour_of_day, day_of_week, report_date, model_version_id);
-- @@ constraint_p public.ottoq_prediction_accuracy_heatmap.ottoq_prediction_accuracy_heatmap_pkey
ALTER TABLE ONLY public.ottoq_prediction_accuracy_heatmap ADD CONSTRAINT ottoq_prediction_accuracy_heatmap_pkey PRIMARY KEY (heatmap_id);
-- @@ constraint_p public.ottoq_prediction_rule_links.ottoq_prediction_rule_links_pkey
ALTER TABLE ONLY public.ottoq_prediction_rule_links ADD CONSTRAINT ottoq_prediction_rule_links_pkey PRIMARY KEY (link_id);
-- @@ constraint_u public.ottoq_prediction_rule_links.ottoq_prediction_rule_links_prediction_type_rule_code_relat_key
ALTER TABLE ONLY public.ottoq_prediction_rule_links ADD CONSTRAINT ottoq_prediction_rule_links_prediction_type_rule_code_relat_key UNIQUE (prediction_type, rule_code, relationship);
-- @@ constraint_p public.ottoq_prediction_types_catalog.ottoq_prediction_types_catalog_pkey
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ADD CONSTRAINT ottoq_prediction_types_catalog_pkey PRIMARY KEY (prediction_type);
-- @@ constraint_p public.ottoq_predictions.ottoq_predictions_pkey
ALTER TABLE ONLY public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ottoq_proposal_disposition_ledger.ottoq_proposal_disposition_ledger_pkey
ALTER TABLE ONLY public.ottoq_proposal_disposition_ledger ADD CONSTRAINT ottoq_proposal_disposition_ledger_pkey PRIMARY KEY (disposition_id);
-- @@ constraint_p public.ottoq_proposal_replay.ottoq_proposal_replay_pkey
ALTER TABLE ONLY public.ottoq_proposal_replay ADD CONSTRAINT ottoq_proposal_replay_pkey PRIMARY KEY (replay_id, seq);
-- @@ constraint_p public.ottoq_proposer_fire_log.ottoq_proposer_fire_log_pkey
ALTER TABLE ONLY public.ottoq_proposer_fire_log ADD CONSTRAINT ottoq_proposer_fire_log_pkey PRIMARY KEY (fire_id);
-- @@ constraint_p public.ottoq_proposer_precedence.ottoq_proposer_precedence_pkey
ALTER TABLE ONLY public.ottoq_proposer_precedence ADD CONSTRAINT ottoq_proposer_precedence_pkey PRIMARY KEY (source);
-- @@ constraint_u public.ottoq_ready_promise_updates.ottoq_ready_promise_updates_once
ALTER TABLE ONLY public.ottoq_ready_promise_updates ADD CONSTRAINT ottoq_ready_promise_updates_once UNIQUE (sim_run_id, visit_id, estimated_at);
-- @@ constraint_p public.ottoq_ready_promise_updates.ottoq_ready_promise_updates_pkey
ALTER TABLE ONLY public.ottoq_ready_promise_updates ADD CONSTRAINT ottoq_ready_promise_updates_pkey PRIMARY KEY (update_id);
-- @@ constraint_u public.ottoq_ready_promises.ottoq_ready_promises_one_per_visit
ALTER TABLE ONLY public.ottoq_ready_promises ADD CONSTRAINT ottoq_ready_promises_one_per_visit UNIQUE (sim_run_id, visit_id);
-- @@ constraint_p public.ottoq_ready_promises.ottoq_ready_promises_pkey
ALTER TABLE ONLY public.ottoq_ready_promises ADD CONSTRAINT ottoq_ready_promises_pkey PRIMARY KEY (promise_id);
-- @@ constraint_p public.ottoq_recall_decisions.ottoq_recall_decisions_pkey
ALTER TABLE ONLY public.ottoq_recall_decisions ADD CONSTRAINT ottoq_recall_decisions_pkey PRIMARY KEY (recall_id);
-- @@ constraint_u public.ottoq_recall_implementations.ottoq_recall_implementations_implementation_key
ALTER TABLE ONLY public.ottoq_recall_implementations ADD CONSTRAINT ottoq_recall_implementations_implementation_key UNIQUE (implementation);
-- @@ constraint_p public.ottoq_recall_implementations.ottoq_recall_implementations_pkey
ALTER TABLE ONLY public.ottoq_recall_implementations ADD CONSTRAINT ottoq_recall_implementations_pkey PRIMARY KEY (impl_id);
-- @@ constraint_p public.ottoq_recall_refusals.ottoq_recall_refusals_pkey
ALTER TABLE ONLY public.ottoq_recall_refusals ADD CONSTRAINT ottoq_recall_refusals_pkey PRIMARY KEY (refusal_id);
-- @@ constraint_p public.ottoq_recommendations.ottoq_recommendations_pkey
ALTER TABLE ONLY public.ottoq_recommendations ADD CONSTRAINT ottoq_recommendations_pkey PRIMARY KEY (recommendation_id);
-- @@ constraint_u public.ottoq_recommendations.ottoq_recommendations_recommendation_seq_key
ALTER TABLE ONLY public.ottoq_recommendations ADD CONSTRAINT ottoq_recommendations_recommendation_seq_key UNIQUE (recommendation_seq);
-- @@ constraint_u public.ottoq_research_findings.ottoq_research_findings_depot_id_slug_key
ALTER TABLE ONLY public.ottoq_research_findings ADD CONSTRAINT ottoq_research_findings_depot_id_slug_key UNIQUE (depot_id, slug);
-- @@ constraint_p public.ottoq_research_findings.ottoq_research_findings_pkey
ALTER TABLE ONLY public.ottoq_research_findings ADD CONSTRAINT ottoq_research_findings_pkey PRIMARY KEY (finding_id);
-- @@ constraint_p public.ottoq_retention_engine_allowlist.ottoq_retention_engine_allowlist_pkey
ALTER TABLE ONLY public.ottoq_retention_engine_allowlist ADD CONSTRAINT ottoq_retention_engine_allowlist_pkey PRIMARY KEY (table_name);
-- @@ constraint_p public.ottoq_retention_policy.ottoq_retention_policy_pkey
ALTER TABLE ONLY public.ottoq_retention_policy ADD CONSTRAINT ottoq_retention_policy_pkey PRIMARY KEY (policy_key);
-- @@ constraint_p public.ottoq_retention_state.ottoq_retention_state_pkey
ALTER TABLE ONLY public.ottoq_retention_state ADD CONSTRAINT ottoq_retention_state_pkey PRIMARY KEY (table_name);
-- @@ constraint_p public.ottoq_retraining_triggers.ottoq_retraining_triggers_pkey
ALTER TABLE ONLY public.ottoq_retraining_triggers ADD CONSTRAINT ottoq_retraining_triggers_pkey PRIMARY KEY (trigger_id);
-- @@ constraint_u public.ottoq_retraining_triggers.ottoq_retraining_triggers_trigger_code_key
ALTER TABLE ONLY public.ottoq_retraining_triggers ADD CONSTRAINT ottoq_retraining_triggers_trigger_code_key UNIQUE (trigger_code);
-- @@ constraint_p public.ottoq_reward_weights.ottoq_reward_weights_pkey
ALTER TABLE ONLY public.ottoq_reward_weights ADD CONSTRAINT ottoq_reward_weights_pkey PRIMARY KEY (weight_version);
-- @@ constraint_p public.ottoq_rider_cleaning_flags.ottoq_rider_cleaning_flags_pkey
ALTER TABLE ONLY public.ottoq_rider_cleaning_flags ADD CONSTRAINT ottoq_rider_cleaning_flags_pkey PRIMARY KEY (flag_id);
-- @@ constraint_u public.ottoq_rider_cleaning_flags.uq_rcf_run_vehicle
ALTER TABLE ONLY public.ottoq_rider_cleaning_flags ADD CONSTRAINT uq_rcf_run_vehicle UNIQUE (sim_run_id, vehicle_id);
-- @@ constraint_u public.ottoq_rule_evaluations.ottoq_rule_evaluations_evaluation_seq_key
ALTER TABLE ONLY public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_evaluation_seq_key UNIQUE (evaluation_seq);
-- @@ constraint_p public.ottoq_rule_evaluations.ottoq_rule_evaluations_pkey
ALTER TABLE ONLY public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_pkey PRIMARY KEY (evaluation_id);
-- @@ constraint_p public.ottoq_rule_overrides.ottoq_rule_overrides_pkey
ALTER TABLE ONLY public.ottoq_rule_overrides ADD CONSTRAINT ottoq_rule_overrides_pkey PRIMARY KEY (override_id);
-- @@ constraint_p public.ottoq_rule_parameters.ottoq_rule_parameters_pkey
ALTER TABLE ONLY public.ottoq_rule_parameters ADD CONSTRAINT ottoq_rule_parameters_pkey PRIMARY KEY (parameter_id);
-- @@ constraint_u public.ottoq_rule_parameters.ottoq_rule_parameters_rule_code_scope_scope_id_effective_fr_key
ALTER TABLE ONLY public.ottoq_rule_parameters ADD CONSTRAINT ottoq_rule_parameters_rule_code_scope_scope_id_effective_fr_key UNIQUE (rule_code, scope, scope_id, effective_from);
-- @@ constraint_p public.ottoq_rules.ottoq_rules_pkey
ALTER TABLE ONLY public.ottoq_rules ADD CONSTRAINT ottoq_rules_pkey PRIMARY KEY (rule_id);
-- @@ constraint_u public.ottoq_rules.ottoq_rules_rule_code_version_key
ALTER TABLE ONLY public.ottoq_rules ADD CONSTRAINT ottoq_rules_rule_code_version_key UNIQUE (rule_code, version);
-- @@ constraint_p public.ottoq_run_archives.ottoq_run_archives_pkey
ALTER TABLE ONLY public.ottoq_run_archives ADD CONSTRAINT ottoq_run_archives_pkey PRIMARY KEY (sim_run_id);
-- @@ constraint_p public.ottoq_run_dial_ledger.ottoq_run_dial_ledger_pkey
ALTER TABLE ONLY public.ottoq_run_dial_ledger ADD CONSTRAINT ottoq_run_dial_ledger_pkey PRIMARY KEY (sim_run_id);
-- @@ constraint_p public.ottoq_run_once_claim.ottoq_run_once_claim_pkey
ALTER TABLE ONLY public.ottoq_run_once_claim ADD CONSTRAINT ottoq_run_once_claim_pkey PRIMARY KEY (tag);
-- @@ constraint_p public.ottoq_run_scope_registry.ottoq_run_scope_registry_pkey
ALTER TABLE ONLY public.ottoq_run_scope_registry ADD CONSTRAINT ottoq_run_scope_registry_pkey PRIMARY KEY (table_schema, table_name, column_name);
-- @@ constraint_p public.ottoq_scenarios.ottoq_scenarios_pkey
ALTER TABLE ONLY public.ottoq_scenarios ADD CONSTRAINT ottoq_scenarios_pkey PRIMARY KEY (scenario_id);
-- @@ constraint_u public.ottoq_scenarios.ottoq_scenarios_scenario_code_key
ALTER TABLE ONLY public.ottoq_scenarios ADD CONSTRAINT ottoq_scenarios_scenario_code_key UNIQUE (scenario_code);
-- @@ constraint_p public.ottoq_schema_snapshots.ottoq_schema_snapshots_pkey
ALTER TABLE ONLY public.ottoq_schema_snapshots ADD CONSTRAINT ottoq_schema_snapshots_pkey PRIMARY KEY (snapshot_id);
-- @@ constraint_u public.ottoq_service_detail_records.ottoq_service_detail_records_leg_id_key
ALTER TABLE ONLY public.ottoq_service_detail_records ADD CONSTRAINT ottoq_service_detail_records_leg_id_key UNIQUE (leg_id);
-- @@ constraint_p public.ottoq_service_detail_records.ottoq_service_detail_records_pkey
ALTER TABLE ONLY public.ottoq_service_detail_records ADD CONSTRAINT ottoq_service_detail_records_pkey PRIMARY KEY (sdr_id);
-- @@ constraint_u public.ottoq_service_detail_records.ottoq_service_detail_records_schedule_task_id_key
ALTER TABLE ONLY public.ottoq_service_detail_records ADD CONSTRAINT ottoq_service_detail_records_schedule_task_id_key UNIQUE (schedule_task_id);
-- @@ constraint_p public.ottoq_service_endpoints.ottoq_service_endpoints_pkey
ALTER TABLE ONLY public.ottoq_service_endpoints ADD CONSTRAINT ottoq_service_endpoints_pkey PRIMARY KEY (service_key);
-- @@ constraint_p public.ottoq_service_point_capabilities.ottoq_service_point_capabilities_pkey
ALTER TABLE ONLY public.ottoq_service_point_capabilities ADD CONSTRAINT ottoq_service_point_capabilities_pkey PRIMARY KEY (stall_id, asset_class_code, operation_code);
-- @@ constraint_u public.ottoq_service_tariffs.ottoq_service_tariffs_pack_id_operation_code_asset_class_co_key
ALTER TABLE ONLY public.ottoq_service_tariffs ADD CONSTRAINT ottoq_service_tariffs_pack_id_operation_code_asset_class_co_key UNIQUE (pack_id, operation_code, asset_class_code, fleet_operator_id, window_label, effective_from);
-- @@ constraint_p public.ottoq_service_tariffs.ottoq_service_tariffs_pkey
ALTER TABLE ONLY public.ottoq_service_tariffs ADD CONSTRAINT ottoq_service_tariffs_pkey PRIMARY KEY (tariff_id);
-- @@ constraint_p public.ottoq_service_tokens.ottoq_service_tokens_pkey
ALTER TABLE ONLY public.ottoq_service_tokens ADD CONSTRAINT ottoq_service_tokens_pkey PRIMARY KEY (token_id);
-- @@ constraint_p public.ottoq_signing_keys.ottoq_signing_keys_pkey
ALTER TABLE ONLY public.ottoq_signing_keys ADD CONSTRAINT ottoq_signing_keys_pkey PRIMARY KEY (key_id);
-- @@ constraint_u public.ottoq_signing_keys.ottoq_signing_keys_scope_scope_id_is_active_key
ALTER TABLE ONLY public.ottoq_signing_keys ADD CONSTRAINT ottoq_signing_keys_scope_scope_id_is_active_key UNIQUE (scope, scope_id, is_active) DEFERRABLE INITIALLY DEFERRED;
-- @@ constraint_p public.ottoq_sim_runs.ottoq_sim_runs_pkey
ALTER TABLE ONLY public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_pkey PRIMARY KEY (sim_run_id);
-- @@ constraint_u public.ottoq_sim_runs.ottoq_sim_runs_sim_run_seq_key
ALTER TABLE ONLY public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_sim_run_seq_key UNIQUE (sim_run_seq);
-- @@ constraint_p public.ottoq_sim_scenarios.ottoq_sim_scenarios_pkey
ALTER TABLE ONLY public.ottoq_sim_scenarios ADD CONSTRAINT ottoq_sim_scenarios_pkey PRIMARY KEY (scenario_id);
-- @@ constraint_u public.ottoq_sim_scenarios.ottoq_sim_scenarios_scenario_code_key
ALTER TABLE ONLY public.ottoq_sim_scenarios ADD CONSTRAINT ottoq_sim_scenarios_scenario_code_key UNIQUE (scenario_code);
-- @@ constraint_p public.ottoq_site_base_history.ottoq_site_base_history_pkey
ALTER TABLE ONLY public.ottoq_site_base_history ADD CONSTRAINT ottoq_site_base_history_pkey PRIMARY KEY (change_code, stall_id);
-- @@ constraint_p public.ottoq_site_buildout_active.ottoq_site_buildout_active_pkey
ALTER TABLE ONLY public.ottoq_site_buildout_active ADD CONSTRAINT ottoq_site_buildout_active_pkey PRIMARY KEY (depot_id);
-- @@ constraint_p public.ottoq_site_buildouts.ottoq_site_buildouts_pkey
ALTER TABLE ONLY public.ottoq_site_buildouts ADD CONSTRAINT ottoq_site_buildouts_pkey PRIMARY KEY (buildout_code);
-- @@ constraint_p public.ottoq_site_power_excursion_ledger.ottoq_site_power_excursion_ledger_pkey
ALTER TABLE ONLY public.ottoq_site_power_excursion_ledger ADD CONSTRAINT ottoq_site_power_excursion_ledger_pkey PRIMARY KEY (excursion_id);
-- @@ constraint_p public.ottoq_site_power_plan_ledger.ottoq_site_power_plan_ledger_pkey
ALTER TABLE ONLY public.ottoq_site_power_plan_ledger ADD CONSTRAINT ottoq_site_power_plan_ledger_pkey PRIMARY KEY (plan_id);
-- @@ constraint_u public.ottoq_site_structures.ottoq_site_structures_depot_id_structure_code_key
ALTER TABLE ONLY public.ottoq_site_structures ADD CONSTRAINT ottoq_site_structures_depot_id_structure_code_key UNIQUE (depot_id, structure_code);
-- @@ constraint_p public.ottoq_site_structures.ottoq_site_structures_pkey
ALTER TABLE ONLY public.ottoq_site_structures ADD CONSTRAINT ottoq_site_structures_pkey PRIMARY KEY (structure_id);
-- @@ constraint_u public.ottoq_sla_conformance_daily.ottoq_sla_conformance_daily_fleet_operator_id_depot_id_repo_key
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ADD CONSTRAINT ottoq_sla_conformance_daily_fleet_operator_id_depot_id_repo_key UNIQUE (fleet_operator_id, depot_id, report_date);
-- @@ constraint_p public.ottoq_sla_conformance_daily.ottoq_sla_conformance_daily_pkey
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ADD CONSTRAINT ottoq_sla_conformance_daily_pkey PRIMARY KEY (conformance_id);
-- @@ constraint_p public.ottoq_sla_violations.ottoq_sla_violations_pkey
ALTER TABLE ONLY public.ottoq_sla_violations ADD CONSTRAINT ottoq_sla_violations_pkey PRIMARY KEY (violation_id);
-- @@ constraint_p public.ottoq_solar_output.ottoq_solar_output_pkey
ALTER TABLE ONLY public.ottoq_solar_output ADD CONSTRAINT ottoq_solar_output_pkey PRIMARY KEY (output_id);
-- @@ constraint_p public.ottoq_space_integrity_ledger.ottoq_space_integrity_ledger_pkey
ALTER TABLE ONLY public.ottoq_space_integrity_ledger ADD CONSTRAINT ottoq_space_integrity_ledger_pkey PRIMARY KEY (incident_id);
-- @@ constraint_u public.ottoq_specialization_strategies.ottoq_specialization_strategi_prediction_type_specializatio_key
ALTER TABLE ONLY public.ottoq_specialization_strategies ADD CONSTRAINT ottoq_specialization_strategi_prediction_type_specializatio_key UNIQUE (prediction_type, specialization_level);
-- @@ constraint_p public.ottoq_specialization_strategies.ottoq_specialization_strategies_pkey
ALTER TABLE ONLY public.ottoq_specialization_strategies ADD CONSTRAINT ottoq_specialization_strategies_pkey PRIMARY KEY (strategy_id);
-- @@ constraint_x public.ottoq_stall_bookings.ottoq_stall_bookings_no_overlap
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_no_overlap EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&) WHERE ((state = ANY (ARRAY['held'::text, 'active'::text])));
-- @@ constraint_x public.ottoq_stall_bookings.ottoq_stall_bookings_no_overlap_v2
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_no_overlap_v2 EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&) WHERE (((state = ANY (ARRAY['held'::text, 'active'::text, 'done'::text])) AND (booked_at >= '2026-08-02 03:19:00+00'::timestamp with time zone)));
-- @@ constraint_x public.ottoq_stall_bookings.ottoq_stall_bookings_no_overlap_v3
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_no_overlap_v3 EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&) WHERE (((state = ANY (ARRAY['held'::text, 'active'::text, 'done'::text, 'interrupted'::text])) AND (booked_at >= '2026-08-02 03:19:00+00'::timestamp with time zone)));
-- @@ constraint_p public.ottoq_stall_bookings.ottoq_stall_bookings_pkey
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_pkey PRIMARY KEY (booking_id);
-- @@ constraint_u public.ottoq_state_transitions.ottoq_state_transitions_entity_kind_from_state_to_state_key
ALTER TABLE ONLY public.ottoq_state_transitions ADD CONSTRAINT ottoq_state_transitions_entity_kind_from_state_to_state_key UNIQUE (entity_kind, from_state, to_state);
-- @@ constraint_p public.ottoq_state_transitions.ottoq_state_transitions_pkey
ALTER TABLE ONLY public.ottoq_state_transitions ADD CONSTRAINT ottoq_state_transitions_pkey PRIMARY KEY (transition_id);
-- @@ constraint_p public.ottoq_t4_coverage_samples.ottoq_t4_coverage_samples_pkey
ALTER TABLE ONLY public.ottoq_t4_coverage_samples ADD CONSTRAINT ottoq_t4_coverage_samples_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ottoq_tariff_windows.ottoq_tariff_windows_pkey
ALTER TABLE ONLY public.ottoq_tariff_windows ADD CONSTRAINT ottoq_tariff_windows_pkey PRIMARY KEY (tariff_id);
-- @@ constraint_u public.ottoq_telemetry_packets.ottoq_telemetry_packets_packet_seq_key
ALTER TABLE ONLY public.ottoq_telemetry_packets ADD CONSTRAINT ottoq_telemetry_packets_packet_seq_key UNIQUE (packet_seq);
-- @@ constraint_p public.ottoq_telemetry_packets.ottoq_telemetry_packets_pkey
ALTER TABLE ONLY public.ottoq_telemetry_packets ADD CONSTRAINT ottoq_telemetry_packets_pkey PRIMARY KEY (packet_id);
-- @@ constraint_p public.ottoq_throughput_scores.ottoq_throughput_scores_pkey
ALTER TABLE ONLY public.ottoq_throughput_scores ADD CONSTRAINT ottoq_throughput_scores_pkey PRIMARY KEY (score_id);
-- @@ constraint_p public.ottoq_throughput_sweep_arms.ottoq_throughput_sweep_arms_pkey
ALTER TABLE ONLY public.ottoq_throughput_sweep_arms ADD CONSTRAINT ottoq_throughput_sweep_arms_pkey PRIMARY KEY (arm_id);
-- @@ constraint_p public.ottoq_throughput_sweep_cells.ottoq_throughput_sweep_cells_pkey
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ADD CONSTRAINT ottoq_throughput_sweep_cells_pkey PRIMARY KEY (cell_id);
-- @@ constraint_u public.ottoq_throughput_sweep_cells.ottoq_throughput_sweep_cells_sweep_id_cell_code_key
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ADD CONSTRAINT ottoq_throughput_sweep_cells_sweep_id_cell_code_key UNIQUE (sweep_id, cell_code);
-- @@ constraint_u public.ottoq_throughput_sweep_cells.ottoq_throughput_sweep_cells_sweep_id_ord_key
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ADD CONSTRAINT ottoq_throughput_sweep_cells_sweep_id_ord_key UNIQUE (sweep_id, ord);
-- @@ constraint_p public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_pkey
ALTER TABLE ONLY public.ottoq_throughput_sweeps ADD CONSTRAINT ottoq_throughput_sweeps_pkey PRIMARY KEY (sweep_id);
-- @@ constraint_u public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_sweep_code_key
ALTER TABLE ONLY public.ottoq_throughput_sweeps ADD CONSTRAINT ottoq_throughput_sweeps_sweep_code_key UNIQUE (sweep_code);
-- @@ constraint_p public.ottoq_tick_clock_log.ottoq_tick_clock_log_pkey
ALTER TABLE ONLY public.ottoq_tick_clock_log ADD CONSTRAINT ottoq_tick_clock_log_pkey PRIMARY KEY (sim_run_id, tick_seq);
-- @@ constraint_p public.ottoq_tick_invariance_arms.ottoq_tick_invariance_arms_pkey
ALTER TABLE ONLY public.ottoq_tick_invariance_arms ADD CONSTRAINT ottoq_tick_invariance_arms_pkey PRIMARY KEY (cert_seed, tick_minutes);
-- @@ constraint_p public.ottoq_tick_reservations.ottoq_tick_reservations_pkey
ALTER TABLE ONLY public.ottoq_tick_reservations ADD CONSTRAINT ottoq_tick_reservations_pkey PRIMARY KEY (reservation_id);
-- @@ constraint_p public.ottoq_training_runs.ottoq_training_runs_pkey
ALTER TABLE ONLY public.ottoq_training_runs ADD CONSTRAINT ottoq_training_runs_pkey PRIMARY KEY (training_run_id);
-- @@ constraint_u public.ottoq_v2_cursors.ottoq_v2_cursors_one
ALTER TABLE ONLY public.ottoq_v2_cursors ADD CONSTRAINT ottoq_v2_cursors_one UNIQUE NULLS NOT DISTINCT (source_name, ce_source, sim_run_id);
-- @@ constraint_p public.ottoq_v2_cursors.ottoq_v2_cursors_pkey
ALTER TABLE ONLY public.ottoq_v2_cursors ADD CONSTRAINT ottoq_v2_cursors_pkey PRIMARY KEY (cursor_id);
-- @@ constraint_u public.ottoq_v2_inbox.ottoq_v2_inbox_once
ALTER TABLE ONLY public.ottoq_v2_inbox ADD CONSTRAINT ottoq_v2_inbox_once UNIQUE NULLS NOT DISTINCT (source_name, ce_source, ce_id, sim_run_id);
-- @@ constraint_p public.ottoq_v2_inbox.ottoq_v2_inbox_pkey
ALTER TABLE ONLY public.ottoq_v2_inbox ADD CONSTRAINT ottoq_v2_inbox_pkey PRIMARY KEY (inbox_id);
-- @@ constraint_p public.ottoq_v2_signal_ttl.ottoq_v2_signal_ttl_pkey
ALTER TABLE ONLY public.ottoq_v2_signal_ttl ADD CONSTRAINT ottoq_v2_signal_ttl_pkey PRIMARY KEY (data_source, vss_path);
-- @@ constraint_p public.ottoq_v2_signing_keys.ottoq_v2_signing_keys_pkey
ALTER TABLE ONLY public.ottoq_v2_signing_keys ADD CONSTRAINT ottoq_v2_signing_keys_pkey PRIMARY KEY (kid);
-- @@ constraint_p public.ottoq_variability_cards.ottoq_variability_cards_pkey
ALTER TABLE ONLY public.ottoq_variability_cards ADD CONSTRAINT ottoq_variability_cards_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ottoq_variability_catalog.ottoq_variability_catalog_pkey
ALTER TABLE ONLY public.ottoq_variability_catalog ADD CONSTRAINT ottoq_variability_catalog_pkey PRIMARY KEY (var_key);
-- @@ constraint_p public.ottoq_variability_profiles.ottoq_variability_profiles_pkey
ALTER TABLE ONLY public.ottoq_variability_profiles ADD CONSTRAINT ottoq_variability_profiles_pkey PRIMARY KEY (profile_id);
-- @@ constraint_p public.ottoq_vehicle_classes.ottoq_vehicle_classes_pkey
ALTER TABLE ONLY public.ottoq_vehicle_classes ADD CONSTRAINT ottoq_vehicle_classes_pkey PRIMARY KEY (vehicle_class_code);
-- @@ constraint_p public.ottoq_vehicle_commands.ottoq_vehicle_commands_pkey
ALTER TABLE ONLY public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_pkey PRIMARY KEY (command_id);
-- @@ constraint_p public.ottoq_vehicle_dispatches.ottoq_vehicle_dispatches_pkey
ALTER TABLE ONLY public.ottoq_vehicle_dispatches ADD CONSTRAINT ottoq_vehicle_dispatches_pkey PRIMARY KEY (dispatch_id);
-- @@ constraint_p public.ottoq_vehicle_incidents.ottoq_vehicle_incidents_pkey
ALTER TABLE ONLY public.ottoq_vehicle_incidents ADD CONSTRAINT ottoq_vehicle_incidents_pkey PRIMARY KEY (incident_id);
-- @@ constraint_p public.ottoq_vehicle_itineraries.ottoq_vehicle_itineraries_pkey
ALTER TABLE ONLY public.ottoq_vehicle_itineraries ADD CONSTRAINT ottoq_vehicle_itineraries_pkey PRIMARY KEY (itinerary_id);
-- @@ constraint_p public.ottoq_vehicle_scout_findings.ottoq_vehicle_scout_findings_pkey
ALTER TABLE ONLY public.ottoq_vehicle_scout_findings ADD CONSTRAINT ottoq_vehicle_scout_findings_pkey PRIMARY KEY (finding_id);
-- @@ constraint_u public.ottoq_vehicle_scout_findings.ottoq_vehicle_scout_once
ALTER TABLE ONLY public.ottoq_vehicle_scout_findings ADD CONSTRAINT ottoq_vehicle_scout_once UNIQUE NULLS NOT DISTINCT (sim_run_id, vehicle_id, scout, episode_key);
-- @@ constraint_p public.ottoq_vehicle_wear.ottoq_vehicle_wear_pkey
ALTER TABLE ONLY public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_pkey PRIMARY KEY (vehicle_id, sim_run_id);
-- @@ constraint_u public.ottoq_visit_cost_attribution.ottoq_visit_cost_attribution_attribution_seq_key
ALTER TABLE ONLY public.ottoq_visit_cost_attribution ADD CONSTRAINT ottoq_visit_cost_attribution_attribution_seq_key UNIQUE (attribution_seq);
-- @@ constraint_p public.ottoq_visit_cost_attribution.ottoq_visit_cost_attribution_pkey
ALTER TABLE ONLY public.ottoq_visit_cost_attribution ADD CONSTRAINT ottoq_visit_cost_attribution_pkey PRIMARY KEY (attribution_id);
-- @@ constraint_u public.ottoq_visit_cost_attribution.ottoq_visit_cost_attribution_schedule_id_key
ALTER TABLE ONLY public.ottoq_visit_cost_attribution ADD CONSTRAINT ottoq_visit_cost_attribution_schedule_id_key UNIQUE (schedule_id);
-- @@ constraint_p public.ottoq_visit_needs.ottoq_visit_needs_pkey
ALTER TABLE ONLY public.ottoq_visit_needs ADD CONSTRAINT ottoq_visit_needs_pkey PRIMARY KEY (visit_id);
-- @@ constraint_p public.ottoq_wave_plan.ottoq_wave_plan_pkey
ALTER TABLE ONLY public.ottoq_wave_plan ADD CONSTRAINT ottoq_wave_plan_pkey PRIMARY KEY (plan_id);
-- @@ constraint_p public.ottoq_wear_tick_status.ottoq_wear_tick_status_pkey
ALTER TABLE ONLY public.ottoq_wear_tick_status ADD CONSTRAINT ottoq_wear_tick_status_pkey PRIMARY KEY (sim_run_id, tick_seq);
-- @@ constraint_p public.ottoq_weather_snapshots.ottoq_weather_snapshots_pkey
ALTER TABLE ONLY public.ottoq_weather_snapshots ADD CONSTRAINT ottoq_weather_snapshots_pkey PRIMARY KEY (snapshot_id);
-- @@ constraint_p public.ottoq_write_slimming_policy.ottoq_write_slimming_policy_pkey
ALTER TABLE ONLY public.ottoq_write_slimming_policy ADD CONSTRAINT ottoq_write_slimming_policy_pkey PRIMARY KEY (policy_key);
-- @@ constraint_p public.ottow_api_keys.ottow_api_keys_pkey
ALTER TABLE ONLY public.ottow_api_keys ADD CONSTRAINT ottow_api_keys_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ottow_dispatch_rules.ottow_dispatch_rules_pkey
ALTER TABLE ONLY public.ottow_dispatch_rules ADD CONSTRAINT ottow_dispatch_rules_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ottow_drivers.ottow_drivers_pkey
ALTER TABLE ONLY public.ottow_drivers ADD CONSTRAINT ottow_drivers_pkey PRIMARY KEY (id);
-- @@ constraint_u public.ottow_drivers.ottow_drivers_staff_user_id_key
ALTER TABLE ONLY public.ottow_drivers ADD CONSTRAINT ottow_drivers_staff_user_id_key UNIQUE (staff_user_id);
-- @@ constraint_p public.ottow_mission_events.ottow_mission_events_pkey
ALTER TABLE ONLY public.ottow_mission_events ADD CONSTRAINT ottow_mission_events_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ottow_missions.ottow_missions_pkey
ALTER TABLE ONLY public.ottow_missions ADD CONSTRAINT ottow_missions_pkey PRIMARY KEY (id);
-- @@ constraint_p public.ottow_notifications.ottow_notifications_pkey
ALTER TABLE ONLY public.ottow_notifications ADD CONSTRAINT ottow_notifications_pkey PRIMARY KEY (id);
-- @@ constraint_p public.p3_phantom_smoke_2026_08_02.p3_phantom_smoke_2026_08_02_pkey
ALTER TABLE ONLY public.p3_phantom_smoke_2026_08_02 ADD CONSTRAINT p3_phantom_smoke_2026_08_02_pkey PRIMARY KEY (id);
-- @@ constraint_p public.p7_band_probe_2026_08_03.p7_band_probe_2026_08_03_pkey
ALTER TABLE ONLY public.p7_band_probe_2026_08_03 ADD CONSTRAINT p7_band_probe_2026_08_03_pkey PRIMARY KEY (seq);
-- @@ constraint_p public.p7_cuopt_supply_proof_2026_08_03.p7_cuopt_supply_proof_2026_08_03_pkey
ALTER TABLE ONLY public.p7_cuopt_supply_proof_2026_08_03 ADD CONSTRAINT p7_cuopt_supply_proof_2026_08_03_pkey PRIMARY KEY (seq);
-- @@ constraint_u public.prediction_accuracy_daily.prediction_accuracy_daily_depot_id_report_date_prediction_t_key
ALTER TABLE ONLY public.prediction_accuracy_daily ADD CONSTRAINT prediction_accuracy_daily_depot_id_report_date_prediction_t_key UNIQUE (depot_id, report_date, prediction_type, time_horizon_hours);
-- @@ constraint_p public.prediction_accuracy_daily.prediction_accuracy_daily_pkey
ALTER TABLE ONLY public.prediction_accuracy_daily ADD CONSTRAINT prediction_accuracy_daily_pkey PRIMARY KEY (id);
-- @@ constraint_p public.prediction_explanations.prediction_explanations_pkey
ALTER TABLE ONLY public.prediction_explanations ADD CONSTRAINT prediction_explanations_pkey PRIMARY KEY (id);
-- @@ constraint_u public.prediction_explanations.prediction_explanations_prediction_id_key
ALTER TABLE ONLY public.prediction_explanations ADD CONSTRAINT prediction_explanations_prediction_id_key UNIQUE (prediction_id);
-- @@ constraint_p public.prediction_outcomes.prediction_outcomes_pkey
ALTER TABLE ONLY public.prediction_outcomes ADD CONSTRAINT prediction_outcomes_pkey PRIMARY KEY (id);
-- @@ constraint_p public.prof0012_act.prof0012_act_pkey
ALTER TABLE ONLY public.prof0012_act ADD CONSTRAINT prof0012_act_pkey PRIMARY KEY (id);
-- @@ constraint_p public.prof0012_pgss.prof0012_pgss_pkey
ALTER TABLE ONLY public.prof0012_pgss ADD CONSTRAINT prof0012_pgss_pkey PRIMARY KEY (id);
-- @@ constraint_p public.prof0012_tabstat.prof0012_tabstat_pkey
ALTER TABLE ONLY public.prof0012_tabstat ADD CONSTRAINT prof0012_tabstat_pkey PRIMARY KEY (id);
-- @@ constraint_p public.prof0012_tick.prof0012_tick_pkey
ALTER TABLE ONLY public.prof0012_tick ADD CONSTRAINT prof0012_tick_pkey PRIMARY KEY (id);
-- @@ constraint_p public.progression_decisions.progression_decisions_pkey
ALTER TABLE ONLY public.progression_decisions ADD CONSTRAINT progression_decisions_pkey PRIMARY KEY (id);
-- @@ constraint_u public.retail_members.retail_members_email_key
ALTER TABLE ONLY public.retail_members ADD CONSTRAINT retail_members_email_key UNIQUE (email);
-- @@ constraint_p public.retail_members.retail_members_pkey
ALTER TABLE ONLY public.retail_members ADD CONSTRAINT retail_members_pkey PRIMARY KEY (id);
-- @@ constraint_p public.schedule_modifications.schedule_modifications_pkey
ALTER TABLE ONLY public.schedule_modifications ADD CONSTRAINT schedule_modifications_pkey PRIMARY KEY (id);
-- @@ constraint_p public.schedule_tasks.schedule_tasks_pkey
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_pkey PRIMARY KEY (id);
-- @@ constraint_p public.service_cadence_policy.service_cadence_policy_pkey
ALTER TABLE ONLY public.service_cadence_policy ADD CONSTRAINT service_cadence_policy_pkey PRIMARY KEY (svc);
-- @@ constraint_u public.service_definitions.service_definitions_depot_id_code_key
ALTER TABLE ONLY public.service_definitions ADD CONSTRAINT service_definitions_depot_id_code_key UNIQUE (depot_id, code);
-- @@ constraint_p public.service_definitions.service_definitions_pkey
ALTER TABLE ONLY public.service_definitions ADD CONSTRAINT service_definitions_pkey PRIMARY KEY (id);
-- @@ constraint_p public.site_energy_snapshots.site_energy_snapshots_pkey
ALTER TABLE ONLY public.site_energy_snapshots ADD CONSTRAINT site_energy_snapshots_pkey PRIMARY KEY (id);
-- @@ constraint_p public.space_conflict_ledger.space_conflict_ledger_pkey
ALTER TABLE ONLY public.space_conflict_ledger ADD CONSTRAINT space_conflict_ledger_pkey PRIMARY KEY (conflict_id);
-- @@ constraint_u public.staff_users.staff_users_email_key
ALTER TABLE ONLY public.staff_users ADD CONSTRAINT staff_users_email_key UNIQUE (email);
-- @@ constraint_p public.staff_users.staff_users_pkey
ALTER TABLE ONLY public.staff_users ADD CONSTRAINT staff_users_pkey PRIMARY KEY (id);
-- @@ constraint_u public.stalls.stalls_depot_id_stall_code_key
ALTER TABLE ONLY public.stalls ADD CONSTRAINT stalls_depot_id_stall_code_key UNIQUE (depot_id, stall_code);
-- @@ constraint_p public.stalls.stalls_pkey
ALTER TABLE ONLY public.stalls ADD CONSTRAINT stalls_pkey PRIMARY KEY (id);
-- @@ constraint_p public.storage_cert_0006_retention.storage_cert_0006_retention_pkey
ALTER TABLE ONLY public.storage_cert_0006_retention ADD CONSTRAINT storage_cert_0006_retention_pkey PRIMARY KEY (id);
-- @@ constraint_p public.storage_cert_0006_samples.storage_cert_0006_samples_pkey
ALTER TABLE ONLY public.storage_cert_0006_samples ADD CONSTRAINT storage_cert_0006_samples_pkey PRIMARY KEY (id);
-- @@ constraint_p public.tariff_schedules.tariff_schedules_pkey
ALTER TABLE ONLY public.tariff_schedules ADD CONSTRAINT tariff_schedules_pkey PRIMARY KEY (id);
-- @@ constraint_p public.tuning_iterations.tuning_iterations_pkey
ALTER TABLE ONLY public.tuning_iterations ADD CONSTRAINT tuning_iterations_pkey PRIMARY KEY (id);
-- @@ constraint_u public.tuning_iterations.tuning_iterations_tuning_run_id_iteration_number_key
ALTER TABLE ONLY public.tuning_iterations ADD CONSTRAINT tuning_iterations_tuning_run_id_iteration_number_key UNIQUE (tuning_run_id, iteration_number);
-- @@ constraint_p public.vehicle_need_profile.vehicle_need_profile_pkey
ALTER TABLE ONLY public.vehicle_need_profile ADD CONSTRAINT vehicle_need_profile_pkey PRIMARY KEY (vehicle_id);
-- @@ constraint_p public.vehicle_schedules.vehicle_schedules_pkey
ALTER TABLE ONLY public.vehicle_schedules ADD CONSTRAINT vehicle_schedules_pkey PRIMARY KEY (id);
-- @@ constraint_u public.vehicle_schedules.vehicle_schedules_vehicle_id_scheduled_date_key
ALTER TABLE ONLY public.vehicle_schedules ADD CONSTRAINT vehicle_schedules_vehicle_id_scheduled_date_key UNIQUE (vehicle_id, scheduled_date);
-- @@ constraint_p public.vehicle_state_log.vehicle_state_log_pkey
ALTER TABLE ONLY public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_pkey PRIMARY KEY (id);
-- @@ constraint_p public.vehicle_telemetry.vehicle_telemetry_pkey
ALTER TABLE ONLY public.vehicle_telemetry ADD CONSTRAINT vehicle_telemetry_pkey PRIMARY KEY (id);
-- @@ constraint_p public.vehicles.vehicles_pkey
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_pkey PRIMARY KEY (id);
-- @@ constraint_u public.vehicles.vehicles_vin_key
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_vin_key UNIQUE (vin);
-- @@ constraint_u public.waves.waves_depot_id_wave_code_key
ALTER TABLE ONLY public.waves ADD CONSTRAINT waves_depot_id_wave_code_key UNIQUE (depot_id, wave_code);
-- @@ constraint_p public.waves.waves_pkey
ALTER TABLE ONLY public.waves ADD CONSTRAINT waves_pkey PRIMARY KEY (id);
-- @@ constraint_p public.workload_determinism_proof_2026_08_02.workload_determinism_proof_2026_08_02_pkey
ALTER TABLE ONLY public.workload_determinism_proof_2026_08_02 ADD CONSTRAINT workload_determinism_proof_2026_08_02_pkey PRIMARY KEY (id);
-- @@ constraint_p twin.arm_cycles.arm_cycles_pkey
ALTER TABLE ONLY twin.arm_cycles ADD CONSTRAINT arm_cycles_pkey PRIMARY KEY (cycle_id);
-- @@ constraint_p twin.arm_registrations.arm_registrations_pkey
ALTER TABLE ONLY twin.arm_registrations ADD CONSTRAINT arm_registrations_pkey PRIMARY KEY (registration_id);
-- @@ constraint_p twin.ottoq_twin_drive_log.ottoq_twin_drive_log_pkey
ALTER TABLE ONLY twin.ottoq_twin_drive_log ADD CONSTRAINT ottoq_twin_drive_log_pkey PRIMARY KEY (sim_run_id, vehicle_id, sim_clock_at);
-- @@ constraint_u twin.ottoq_twin_operator_log.ottoq_twin_operator_log_once
ALTER TABLE ONLY twin.ottoq_twin_operator_log ADD CONSTRAINT ottoq_twin_operator_log_once UNIQUE (sim_run_id, command_id);
-- @@ constraint_p twin.ottoq_twin_operator_log.ottoq_twin_operator_log_pkey
ALTER TABLE ONLY twin.ottoq_twin_operator_log ADD CONSTRAINT ottoq_twin_operator_log_pkey PRIMARY KEY (log_id);
-- @@ constraint_p twin.ottoq_twin_operator_sequences.ottoq_twin_operator_sequences_pkey
ALTER TABLE ONLY twin.ottoq_twin_operator_sequences ADD CONSTRAINT ottoq_twin_operator_sequences_pkey PRIMARY KEY (sim_run_id, source_name, vehicle_ref);
-- @@ constraint_p twin.ottoq_twin_operator_state.ottoq_twin_operator_state_pkey
ALTER TABLE ONLY twin.ottoq_twin_operator_state ADD CONSTRAINT ottoq_twin_operator_state_pkey PRIMARY KEY (sim_run_id, source_name);
-- @@ constraint_u twin.ottoq_twin_operators.ottoq_twin_operators_key_id_key
ALTER TABLE ONLY twin.ottoq_twin_operators ADD CONSTRAINT ottoq_twin_operators_key_id_key UNIQUE (key_id);
-- @@ constraint_p twin.ottoq_twin_operators.ottoq_twin_operators_pkey
ALTER TABLE ONLY twin.ottoq_twin_operators ADD CONSTRAINT ottoq_twin_operators_pkey PRIMARY KEY (source_name);
