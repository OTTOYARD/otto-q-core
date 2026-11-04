-- 13_indexes.sql: 490 statements, exported from production's catalog
-- @@ index public.bay_res_recon_booking_idx
CREATE INDEX bay_res_recon_booking_idx ON public.bay_reservation_reconcile_2026_08_02 USING btree (booking_id, action);
-- @@ index public.bay_res_recon_run_idx
CREATE INDEX bay_res_recon_run_idx ON public.bay_reservation_reconcile_2026_08_02 USING btree (sim_run_id);
-- @@ index public.cuopt_invocation_log_called_at_idx
CREATE INDEX cuopt_invocation_log_called_at_idx ON public.cuopt_invocation_log USING btree (called_at DESC);
-- @@ index public.cuopt_invocation_log_run_time_idx
CREATE INDEX cuopt_invocation_log_run_time_idx ON public.cuopt_invocation_log USING btree (sim_run_id, called_at DESC);
-- @@ index public.exceptions_sim_run_id_idx
CREATE INDEX exceptions_sim_run_id_idx ON public.exceptions USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.fwd2_card_samples_veh
CREATE INDEX fwd2_card_samples_veh ON public.fwd2_card_samples USING btree (vehicle_id, sampled_at);
-- @@ index public.idx_ab_runs_group
CREATE INDEX idx_ab_runs_group ON public.ottoq_ab_runs USING btree (ab_group_id, policy);
-- @@ index public.idx_ab_tests_depot_status
CREATE INDEX idx_ab_tests_depot_status ON public.ab_tests USING btree (depot_id, status, started_at DESC);
-- @@ index public.idx_ab_tests_running
CREATE INDEX idx_ab_tests_running ON public.ab_tests USING btree (parameter_group, depot_id) WHERE (status = 'running'::text);
-- @@ index public.idx_accuracy_daily_depot_date
CREATE INDEX idx_accuracy_daily_depot_date ON public.prediction_accuracy_daily USING btree (depot_id, report_date DESC);
-- @@ index public.idx_accuracy_daily_trend
CREATE INDEX idx_accuracy_daily_trend ON public.prediction_accuracy_daily USING btree (depot_id, trend_direction, report_date DESC);
-- @@ index public.idx_accuracy_daily_type
CREATE INDEX idx_accuracy_daily_type ON public.prediction_accuracy_daily USING btree (depot_id, prediction_type, report_date DESC);
-- @@ index public.idx_action_log_depot_time
CREATE INDEX idx_action_log_depot_time ON public.autonomous_action_log USING btree (depot_id, created_at DESC);
-- @@ index public.idx_action_log_prediction
CREATE INDEX idx_action_log_prediction ON public.autonomous_action_log USING btree (prediction_id);
-- @@ index public.idx_action_log_status
CREATE INDEX idx_action_log_status ON public.autonomous_action_log USING btree (depot_id, status, created_at DESC);
-- @@ index public.idx_action_log_type
CREATE INDEX idx_action_log_type ON public.autonomous_action_log USING btree (depot_id, action_type, created_at DESC);
-- @@ index public.idx_ai_log_depot
CREATE INDEX idx_ai_log_depot ON public.ai_decision_log USING btree (depot_id, created_at DESC);
-- @@ index public.idx_ai_log_status
CREATE INDEX idx_ai_log_status ON public.ai_decision_log USING btree (status) WHERE (status = 'pending'::text);
-- @@ index public.idx_alerts_depot_time
CREATE INDEX idx_alerts_depot_time ON public.accuracy_alerts USING btree (depot_id, observed_at DESC);
-- @@ index public.idx_alerts_slo
CREATE INDEX idx_alerts_slo ON public.accuracy_alerts USING btree (slo_id, observed_at DESC);
-- @@ index public.idx_alerts_unresolved
CREATE INDEX idx_alerts_unresolved ON public.accuracy_alerts USING btree (severity, observed_at DESC) WHERE (resolved_at IS NULL);
-- @@ index public.idx_anomaly_detectors_active
CREATE INDEX idx_anomaly_detectors_active ON public.ottoq_anomaly_detectors USING btree (target_feature, status) WHERE (status = 'active'::text);
-- @@ index public.idx_anomaly_detectors_category
CREATE INDEX idx_anomaly_detectors_category ON public.ottoq_anomaly_detectors USING btree (category, status);
-- @@ index public.idx_anomaly_obs_anomalous
CREATE INDEX idx_anomaly_obs_anomalous ON public.ottoq_anomaly_observations USING btree (observed_at DESC) WHERE (is_anomaly = true);
-- @@ index public.idx_anomaly_obs_detector_time
CREATE INDEX idx_anomaly_obs_detector_time ON public.ottoq_anomaly_observations USING btree (detector_id, observed_at DESC);
-- @@ index public.idx_anomaly_obs_entity_time
CREATE INDEX idx_anomaly_obs_entity_time ON public.ottoq_anomaly_observations USING btree (entity_type, entity_id, observed_at DESC);
-- @@ index public.idx_anomaly_obs_linked_event
CREATE INDEX idx_anomaly_obs_linked_event ON public.ottoq_anomaly_observations USING btree (linked_event_id);
-- @@ index public.idx_anomaly_obs_seq_brin
CREATE INDEX idx_anomaly_obs_seq_brin ON public.ottoq_anomaly_observations USING brin (observation_seq);
-- @@ index public.idx_anomaly_obs_tenant
CREATE INDEX idx_anomaly_obs_tenant ON public.ottoq_anomaly_observations USING btree (fleet_operator_id, observed_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_api_integrations_depot
CREATE INDEX idx_api_integrations_depot ON public.api_integrations USING btree (depot_id) WHERE (is_active = true);
-- @@ index public.idx_api_integrations_platform
CREATE INDEX idx_api_integrations_platform ON public.api_integrations USING btree (platform) WHERE (is_active = true);
-- @@ index public.idx_audit_bundles_code
CREATE INDEX idx_audit_bundles_code ON public.ottoq_audit_bundles USING btree (bundle_code);
-- @@ index public.idx_audit_bundles_tenant_time
CREATE INDEX idx_audit_bundles_tenant_time ON public.ottoq_audit_bundles USING btree (fleet_operator_id, generated_at DESC);
-- @@ index public.idx_audit_reports_depot_time
CREATE INDEX idx_audit_reports_depot_time ON public.ottoq_audit_reports USING btree (depot_id, window_end DESC) WHERE (depot_id IS NOT NULL);
-- @@ index public.idx_audit_reports_source_event
CREATE INDEX idx_audit_reports_source_event ON public.ottoq_audit_reports USING btree (source_event_id);
-- @@ index public.idx_audit_reports_status
CREATE INDEX idx_audit_reports_status ON public.ottoq_audit_reports USING btree (generation_status, requested_at DESC) WHERE (generation_status = ANY (ARRAY['pending'::text, 'generating'::text]));
-- @@ index public.idx_audit_reports_tenant_time
CREATE INDEX idx_audit_reports_tenant_time ON public.ottoq_audit_reports USING btree (fleet_operator_id, window_end DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_audit_reports_type
CREATE INDEX idx_audit_reports_type ON public.ottoq_audit_reports USING btree (report_type, requested_at DESC);
-- @@ index public.idx_bench_frames_comp
CREATE INDEX idx_bench_frames_comp ON public.ottoq_benchmark_frames USING btree (comparison_id, policy, tick);
-- @@ index public.idx_bess_depot_time
CREATE INDEX idx_bess_depot_time ON public.bess_snapshots USING btree (depot_id, "timestamp" DESC);
-- @@ index public.idx_bess_system
CREATE INDEX idx_bess_system ON public.bess_snapshots USING btree (system_id, "timestamp" DESC);
-- @@ index public.idx_calib_dist_dataset
CREATE INDEX idx_calib_dist_dataset ON public.ottoq_calibration_distributions USING btree (dataset_code);
-- @@ index public.idx_calib_dist_variable
CREATE INDEX idx_calib_dist_variable ON public.ottoq_calibration_distributions USING btree (variable_name, segment);
-- @@ index public.idx_calib_model
CREATE INDEX idx_calib_model ON public.ottoq_calibration_metrics USING btree (model_version_id, computed_at DESC) WHERE (model_version_id IS NOT NULL);
-- @@ index public.idx_calib_type_time
CREATE INDEX idx_calib_type_time ON public.ottoq_calibration_metrics USING btree (prediction_type, computed_at DESC);
-- @@ index public.idx_charger_health_score
CREATE INDEX idx_charger_health_score ON public.charger_health_scores USING btree (health_score);
-- @@ index public.idx_charger_health_stall
CREATE UNIQUE INDEX idx_charger_health_stall ON public.charger_health_scores USING btree (stall_id);
-- @@ index public.idx_contracts_action
CREATE INDEX idx_contracts_action ON public.downstream_action_contracts USING btree (action_type);
-- @@ index public.idx_contracts_implemented
CREATE INDEX idx_contracts_implemented ON public.downstream_action_contracts USING btree (is_implemented, action_type);
-- @@ index public.idx_cooldowns_available
CREATE INDEX idx_cooldowns_available ON public.charger_cooldowns USING btree (available_at) WHERE (resolved = false);
-- @@ index public.idx_cooldowns_depot
CREATE INDEX idx_cooldowns_depot ON public.charger_cooldowns USING btree (depot_id) WHERE (resolved = false);
-- @@ index public.idx_cooldowns_stall
CREATE INDEX idx_cooldowns_stall ON public.charger_cooldowns USING btree (stall_id) WHERE (resolved = false);
-- @@ index public.idx_counterfactuals_scenario
CREATE INDEX idx_counterfactuals_scenario ON public.ottoq_counterfactuals USING btree (scenario_label, ran_at DESC);
-- @@ index public.idx_counterfactuals_source
CREATE INDEX idx_counterfactuals_source ON public.ottoq_counterfactuals USING btree (source_kind, source_id);
-- @@ index public.idx_counterfactuals_src_event
CREATE INDEX idx_counterfactuals_src_event ON public.ottoq_counterfactuals USING btree (source_event_id);
-- @@ index public.idx_counterfactuals_tenant_time
CREATE INDEX idx_counterfactuals_tenant_time ON public.ottoq_counterfactuals USING btree (fleet_operator_id, ran_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_cuopt_deferrals_run_state
CREATE INDEX idx_cuopt_deferrals_run_state ON public.ottoq_cuopt_deferrals USING btree (sim_run_id, state, spent_at_tick);
-- @@ index public.idx_decision_snapshots_depot_clock
CREATE INDEX idx_decision_snapshots_depot_clock ON public.ottoq_decision_snapshots USING btree (depot_id, sim_clock);
-- @@ index public.idx_decision_snapshots_run_tick
CREATE INDEX idx_decision_snapshots_run_tick ON public.ottoq_decision_snapshots USING btree (sim_run_id, tick_seq);
-- @@ index public.idx_decisions_action
CREATE INDEX idx_decisions_action ON public.ottoq_decisions USING btree (action_context, outcome_status);
-- @@ index public.idx_decisions_run_entity_redeploy
CREATE INDEX idx_decisions_run_entity_redeploy ON public.ottoq_decisions USING btree (sim_run_id, entity_id, tick_seq) WHERE ((action_context = 'redeployment'::text) AND (outcome_status = 'enacted'::text));
-- @@ index public.idx_decisions_run_tick
CREATE INDEX idx_decisions_run_tick ON public.ottoq_decisions USING btree (sim_run_id, tick_seq);
-- @@ index public.idx_demand_log_depot_time
CREATE INDEX idx_demand_log_depot_time ON public.demand_management_log USING btree (depot_id, "timestamp" DESC);
-- @@ index public.idx_demand_plans_depot
CREATE INDEX idx_demand_plans_depot ON public.demand_shaping_plans USING btree (depot_id, generated_at DESC);
-- @@ index public.idx_depot_benchmarks_date
CREATE INDEX idx_depot_benchmarks_date ON public.ottoq_depot_benchmarks_daily USING btree (report_date DESC);
-- @@ index public.idx_depot_benchmarks_depot_date
CREATE INDEX idx_depot_benchmarks_depot_date ON public.ottoq_depot_benchmarks_daily USING btree (depot_id, report_date DESC);
-- @@ index public.idx_depot_cost_daily_date
CREATE INDEX idx_depot_cost_daily_date ON public.ottoq_depot_cost_daily USING btree (report_date DESC);
-- @@ index public.idx_depot_shifts_active
CREATE INDEX idx_depot_shifts_active ON public.ottoq_depot_shifts USING btree (depot_id) WHERE (status = 'active'::text);
-- @@ index public.idx_depot_snapshots_depot_time
CREATE INDEX idx_depot_snapshots_depot_time ON public.depot_state_snapshots USING btree (depot_id, snapshot_at DESC);
-- @@ index public.idx_depot_tariffs_lookup
CREATE INDEX idx_depot_tariffs_lookup ON public.ottoq_depot_tariffs USING btree (depot_id, season) WHERE active;
-- @@ index public.idx_depots_slug
CREATE INDEX idx_depots_slug ON public.depots USING btree (slug);
-- @@ index public.idx_depots_status
CREATE INDEX idx_depots_status ON public.depots USING btree (status);
-- @@ index public.idx_dispatch_depot
CREATE INDEX idx_dispatch_depot ON public.dispatch_commands USING btree (depot_id, issued_at DESC);
-- @@ index public.idx_dispatch_idempotency
CREATE INDEX idx_dispatch_idempotency ON public.dispatch_commands USING btree (idempotency_key);
-- @@ index public.idx_dispatch_vehicle
CREATE INDEX idx_dispatch_vehicle ON public.dispatch_commands USING btree (vehicle_id, issued_at DESC);
-- @@ index public.idx_dispatches_active
CREATE INDEX idx_dispatches_active ON public.ottoq_vehicle_dispatches USING btree (status) WHERE (status = ANY (ARRAY['active'::text, 'returning'::text]));
-- @@ index public.idx_dispatches_sim_run
CREATE INDEX idx_dispatches_sim_run ON public.ottoq_vehicle_dispatches USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.idx_dispatches_vehicle
CREATE INDEX idx_dispatches_vehicle ON public.ottoq_vehicle_dispatches USING btree (vehicle_id, dispatched_at DESC);
-- @@ index public.idx_dq_errors_depot_time
CREATE INDEX idx_dq_errors_depot_time ON public.data_quality_errors USING btree (depot_id, detected_at DESC);
-- @@ index public.idx_dq_errors_source
CREATE INDEX idx_dq_errors_source ON public.data_quality_errors USING btree (source_table, source_id);
-- @@ index public.idx_dq_errors_type
CREATE INDEX idx_dq_errors_type ON public.data_quality_errors USING btree (error_type, detected_at DESC);
-- @@ index public.idx_dq_errors_unresolved
CREATE INDEX idx_dq_errors_unresolved ON public.data_quality_errors USING btree (severity, detected_at DESC) WHERE (resolved_at IS NULL);
-- @@ index public.idx_dr_calls_active
CREATE INDEX idx_dr_calls_active ON public.ottoq_dr_calls USING btree (depot_id, call_status, expires_at);
-- @@ index public.idx_drift_detected
CREATE INDEX idx_drift_detected ON public.ottoq_data_drift_metrics USING btree (computed_at DESC) WHERE (drift_detected = true);
-- @@ index public.idx_drift_feature_time
CREATE INDEX idx_drift_feature_time ON public.ottoq_data_drift_metrics USING btree (feature_name, computed_at DESC);
-- @@ index public.idx_em_inv_active
CREATE INDEX idx_em_inv_active ON public.ottoq_emergency_invocations USING btree (depot_id, triggered_at DESC) WHERE (cleared_at IS NULL);
-- @@ index public.idx_em_inv_correlation
CREATE INDEX idx_em_inv_correlation ON public.ottoq_emergency_invocations USING btree (correlation_id);
-- @@ index public.idx_em_inv_protocol_time
CREATE INDEX idx_em_inv_protocol_time ON public.ottoq_emergency_invocations USING btree (protocol_code, triggered_at DESC);
-- @@ index public.idx_emerg_inv_linked_event
CREATE INDEX idx_emerg_inv_linked_event ON public.ottoq_emergency_invocations USING btree (linked_event_id);
-- @@ index public.idx_emerg_inv_trig_event
CREATE INDEX idx_emerg_inv_trig_event ON public.ottoq_emergency_invocations USING btree (triggered_by_event_id);
-- @@ index public.idx_emergency_depot
CREATE INDEX idx_emergency_depot ON public.emergency_queue_insertions USING btree (depot_id, created_at DESC);
-- @@ index public.idx_emergency_protocols_active
CREATE INDEX idx_emergency_protocols_active ON public.ottoq_emergency_protocols USING btree (status, category);
-- @@ index public.idx_emergency_status
CREATE INDEX idx_emergency_status ON public.emergency_queue_insertions USING btree (status) WHERE (status = 'pending'::text);
-- @@ index public.idx_exceptions_blocking
CREATE INDEX idx_exceptions_blocking ON public.exceptions USING btree (vehicle_id, status) WHERE ((blocks_progression = true) AND (status = ANY (ARRAY['open'::public.exception_status, 'acknowledged'::public.exception_status, 'in_progress'::public.exception_status, 'escalated'::public.exception_status])));
-- @@ index public.idx_exceptions_depot
CREATE INDEX idx_exceptions_depot ON public.exceptions USING btree (depot_id, created_at DESC);
-- @@ index public.idx_exceptions_severity
CREATE INDEX idx_exceptions_severity ON public.exceptions USING btree (severity, status);
-- @@ index public.idx_exceptions_status
CREATE INDEX idx_exceptions_status ON public.exceptions USING btree (status) WHERE (status <> 'resolved'::public.exception_status);
-- @@ index public.idx_exceptions_vehicle
CREATE INDEX idx_exceptions_vehicle ON public.exceptions USING btree (vehicle_id);
-- @@ index public.idx_explanations_model
CREATE INDEX idx_explanations_model ON public.prediction_explanations USING btree (model_version_id);
-- @@ index public.idx_explanations_prediction
CREATE INDEX idx_explanations_prediction ON public.prediction_explanations USING btree (prediction_id);
-- @@ index public.idx_ext_log_dedup_hash
CREATE INDEX idx_ext_log_dedup_hash ON public.external_factors_log USING btree (source_id, data_hash) WHERE (data_hash IS NOT NULL);
-- @@ index public.idx_ext_log_depot_type_time
CREATE INDEX idx_ext_log_depot_type_time ON public.external_factors_log USING btree (depot_id, factor_type, observed_at DESC);
-- @@ index public.idx_ext_log_global_type_time
CREATE INDEX idx_ext_log_global_type_time ON public.external_factors_log USING btree (factor_type, observed_at DESC) WHERE (depot_id IS NULL);
-- @@ index public.idx_ext_log_source_time
CREATE INDEX idx_ext_log_source_time ON public.external_factors_log USING btree (source_id, ingested_at DESC);
-- @@ index public.idx_ext_log_valid_window
CREATE INDEX idx_ext_log_valid_window ON public.external_factors_log USING btree (factor_type, valid_from, valid_to);
-- @@ index public.idx_ext_sources_depot
CREATE INDEX idx_ext_sources_depot ON public.external_factor_sources USING btree (depot_id, is_active);
-- @@ index public.idx_ext_sources_health
CREATE INDEX idx_ext_sources_health ON public.external_factor_sources USING btree (health_status, is_active);
-- @@ index public.idx_ext_sources_type
CREATE INDEX idx_ext_sources_type ON public.external_factor_sources USING btree (factor_type, is_active);
-- @@ index public.idx_feature_values_src_event
CREATE INDEX idx_feature_values_src_event ON public.ottoq_feature_values USING btree (source_event_id);
-- @@ index public.idx_features_category
CREATE INDEX idx_features_category ON public.ottoq_features USING btree (category, status);
-- @@ index public.idx_features_realtime
CREATE INDEX idx_features_realtime ON public.ottoq_features USING btree (is_realtime, status);
-- @@ index public.idx_feed_plans_active
CREATE INDEX idx_feed_plans_active ON public.ottoq_feed_plans USING btree (var_key) WHERE (status = 'active'::text);
-- @@ index public.idx_fleet_features_lookup
CREATE INDEX idx_fleet_features_lookup ON public.fleet_features_daily USING btree (feature_group, scope, scope_id, feature_date DESC);
-- @@ index public.idx_fleet_features_recent
CREATE INDEX idx_fleet_features_recent ON public.fleet_features_daily USING btree (feature_date DESC);
-- @@ index public.idx_fleet_operators_auth
CREATE INDEX idx_fleet_operators_auth ON public.fleet_operators USING btree (auth_user_id);
-- @@ index public.idx_fleet_slas_active
CREATE INDEX idx_fleet_slas_active ON public.ottoq_fleet_operator_slas USING btree (fleet_operator_id, status, effective_from, effective_until);
-- @@ index public.idx_fusion_action
CREATE INDEX idx_fusion_action ON public.decision_fusion_log USING btree (emitted_action_id);
-- @@ index public.idx_fusion_depot_time
CREATE INDEX idx_fusion_depot_time ON public.decision_fusion_log USING btree (depot_id, created_at DESC);
-- @@ index public.idx_fusion_prediction
CREATE INDEX idx_fusion_prediction ON public.decision_fusion_log USING btree (emitted_prediction_id);
-- @@ index public.idx_fusion_trigger
CREATE INDEX idx_fusion_trigger ON public.decision_fusion_log USING btree (trigger_type, created_at DESC);
-- @@ index public.idx_fv_active
CREATE INDEX idx_fv_active ON public.ottoq_feature_values USING btree (feature_name, entity_id) WHERE (valid_until IS NULL);
-- @@ index public.idx_fv_entity_feature_time
CREATE INDEX idx_fv_entity_feature_time ON public.ottoq_feature_values USING btree (entity_type, entity_id, feature_name, valid_from DESC);
-- @@ index public.idx_fv_feature_time
CREATE INDEX idx_fv_feature_time ON public.ottoq_feature_values USING btree (feature_name, valid_from DESC);
-- @@ index public.idx_fv_observation_brin
CREATE INDEX idx_fv_observation_brin ON public.ottoq_feature_values USING brin (observation_time);
-- @@ index public.idx_grid_events_active
CREATE INDEX idx_grid_events_active ON public.ottoq_grid_events USING btree (depot_id, event_type) WHERE (cleared_at IS NULL);
-- @@ index public.idx_grid_events_depot_time
CREATE INDEX idx_grid_events_depot_time ON public.ottoq_grid_events USING btree (depot_id, effective_at DESC);
-- @@ index public.idx_grid_snap_depot
CREATE INDEX idx_grid_snap_depot ON public.ottoq_grid_snapshots USING btree (depot_id, sim_clock_at DESC);
-- @@ index public.idx_grid_snap_run
CREATE INDEX idx_grid_snap_run ON public.ottoq_grid_snapshots USING btree (sim_run_id, sim_clock_at DESC);
-- @@ index public.idx_guardrails_depot
CREATE INDEX idx_guardrails_depot ON public.action_guardrails USING btree (depot_id, enabled);
-- @@ index public.idx_incident_rep_trig_event
CREATE INDEX idx_incident_rep_trig_event ON public.ottoq_incident_reports USING btree (triggering_event_id);
-- @@ index public.idx_incident_reports_correlation
CREATE INDEX idx_incident_reports_correlation ON public.ottoq_incident_reports USING btree (source_correlation_id);
-- @@ index public.idx_incident_reports_depot_time
CREATE INDEX idx_incident_reports_depot_time ON public.ottoq_incident_reports USING btree (depot_id, triggered_at DESC) WHERE (depot_id IS NOT NULL);
-- @@ index public.idx_incident_reports_tenant_time
CREATE INDEX idx_incident_reports_tenant_time ON public.ottoq_incident_reports USING btree (fleet_operator_id, triggered_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_incident_reports_type
CREATE INDEX idx_incident_reports_type ON public.ottoq_incident_reports USING btree (incident_type, triggered_at DESC);
-- @@ index public.idx_incidents_open
CREATE INDEX idx_incidents_open ON public.ottoq_vehicle_incidents USING btree (resolution_status, occurred_at DESC) WHERE (resolution_status <> 'resolved'::text);
-- @@ index public.idx_incidents_sim_run
CREATE INDEX idx_incidents_sim_run ON public.ottoq_vehicle_incidents USING btree (sim_run_id);
-- @@ index public.idx_incidents_vehicle
CREATE INDEX idx_incidents_vehicle ON public.ottoq_vehicle_incidents USING btree (vehicle_id, occurred_at DESC);
-- @@ index public.idx_inference_log_correlation
CREATE INDEX idx_inference_log_correlation ON public.ottoq_inference_log USING btree (correlation_id);
-- @@ index public.idx_inference_log_failed
CREATE INDEX idx_inference_log_failed ON public.ottoq_inference_log USING btree (status, requested_at DESC) WHERE (status = ANY (ARRAY['failed'::text, 'timed_out'::text]));
-- @@ index public.idx_inference_log_inputs_hash
CREATE INDEX idx_inference_log_inputs_hash ON public.ottoq_inference_log USING btree (inputs_hash) WHERE (inputs_hash IS NOT NULL);
-- @@ index public.idx_inference_log_model
CREATE INDEX idx_inference_log_model ON public.ottoq_inference_log USING btree (model_version_id, requested_at DESC) WHERE (model_version_id IS NOT NULL);
-- @@ index public.idx_inference_log_seq_brin
CREATE INDEX idx_inference_log_seq_brin ON public.ottoq_inference_log USING brin (inference_seq);
-- @@ index public.idx_inference_log_shadow
CREATE INDEX idx_inference_log_shadow ON public.ottoq_inference_log USING btree (is_shadow, requested_at DESC) WHERE (is_shadow = true);
-- @@ index public.idx_inference_log_tenant
CREATE INDEX idx_inference_log_tenant ON public.ottoq_inference_log USING btree (fleet_operator_id, requested_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_inference_log_type_time
CREATE INDEX idx_inference_log_type_time ON public.ottoq_inference_log USING btree (prediction_type, requested_at DESC);
-- @@ index public.idx_integration_health_state
CREATE INDEX idx_integration_health_state ON public.integration_health USING btree (circuit_state) WHERE (circuit_state <> 'closed'::public.circuit_breaker_state);
-- @@ index public.idx_itin_legs_run_live
CREATE INDEX idx_itin_legs_run_live ON public.ottoq_itinerary_legs USING btree (sim_run_id, status) WHERE (status = ANY (ARRAY['planned'::text, 'active'::text]));
-- @@ index public.idx_itin_legs_run_vehicle
CREATE INDEX idx_itin_legs_run_vehicle ON public.ottoq_itinerary_legs USING btree (sim_run_id, vehicle_id);
-- @@ index public.idx_itin_legs_vehicle
CREATE INDEX idx_itin_legs_vehicle ON public.ottoq_itinerary_legs USING btree (vehicle_id, status);
-- @@ index public.idx_itineraries_run_vehicle
CREATE INDEX idx_itineraries_run_vehicle ON public.ottoq_vehicle_itineraries USING btree (sim_run_id, vehicle_id) WHERE (status = 'active'::text);
-- @@ index public.idx_maint_log_vehicle
CREATE INDEX idx_maint_log_vehicle ON public.maintenance_log USING btree (vehicle_id, performed_at DESC);
-- @@ index public.idx_maintenance_depot
CREATE INDEX idx_maintenance_depot ON public.maintenance_schedules USING btree (depot_id);
-- @@ index public.idx_maintenance_next
CREATE INDEX idx_maintenance_next ON public.maintenance_schedules USING btree (next_scheduled_date) WHERE (status = 'active'::text);
-- @@ index public.idx_maintenance_vehicle
CREATE INDEX idx_maintenance_vehicle ON public.maintenance_schedules USING btree (vehicle_id);
-- @@ index public.idx_meter_values_session
CREATE INDEX idx_meter_values_session ON public.ocpp_meter_values USING btree (ocpp_session_id, seq_no);
-- @@ index public.idx_meter_values_time
CREATE INDEX idx_meter_values_time ON public.ocpp_meter_values USING btree (depot_id, "timestamp" DESC);
-- @@ index public.idx_model_artifacts_active
CREATE INDEX idx_model_artifacts_active ON public.ottoq_model_artifacts USING btree (format, uploaded_at DESC) WHERE (is_active = true);
-- @@ index public.idx_model_params_depot
CREATE INDEX idx_model_params_depot ON public.model_parameters USING btree (depot_id, is_active);
-- @@ index public.idx_model_routes_scope
CREATE INDEX idx_model_routes_scope ON public.ottoq_model_routes USING btree (prediction_type, fleet_operator_id, depot_id, vehicle_class);
-- @@ index public.idx_model_routes_type
CREATE INDEX idx_model_routes_type ON public.ottoq_model_routes USING btree (prediction_type, priority DESC);
-- @@ index public.idx_model_versions_active
CREATE INDEX idx_model_versions_active ON public.model_versions USING btree (depot_id, parameter_group, status) WHERE (status = ANY (ARRAY['active'::text, 'candidate'::text]));
-- @@ index public.idx_model_versions_lineage
CREATE INDEX idx_model_versions_lineage ON public.model_versions USING btree (parent_version_id);
-- @@ index public.idx_model_versions_oem
CREATE INDEX idx_model_versions_oem ON public.model_versions USING btree (oem_id, prediction_type) WHERE (oem_id IS NOT NULL);
-- @@ index public.idx_model_versions_predtype_active
CREATE INDEX idx_model_versions_predtype_active ON public.model_versions USING btree (prediction_type, status) WHERE (status = 'active'::text);
-- @@ index public.idx_model_versions_stage
CREATE INDEX idx_model_versions_stage ON public.model_versions USING btree (deployment_stage);
-- @@ index public.idx_model_versions_tuning
CREATE INDEX idx_model_versions_tuning ON public.model_versions USING btree (tuning_run_id);
-- @@ index public.idx_modifications_depot
CREATE INDEX idx_modifications_depot ON public.schedule_modifications USING btree (depot_id, created_at DESC);
-- @@ index public.idx_modifications_schedule
CREATE INDEX idx_modifications_schedule ON public.schedule_modifications USING btree (vehicle_schedule_id, created_at DESC);
-- @@ index public.idx_notifications_event
CREATE INDEX idx_notifications_event ON public.notifications USING btree (event_type, created_at DESC);
-- @@ index public.idx_notifications_fleet
CREATE INDEX idx_notifications_fleet ON public.notifications USING btree (fleet_operator_id, created_at DESC);
-- @@ index public.idx_notifications_retail
CREATE INDEX idx_notifications_retail ON public.notifications USING btree (retail_member_id, created_at DESC);
-- @@ index public.idx_notifications_staff
CREATE INDEX idx_notifications_staff ON public.notifications USING btree (staff_user_id, created_at DESC);
-- @@ index public.idx_notifications_status
CREATE INDEX idx_notifications_status ON public.notifications USING btree (status) WHERE (status = ANY (ARRAY['queued'::public.notification_status, 'sent'::public.notification_status]));
-- @@ index public.idx_ocpp_msgs_charger
CREATE INDEX idx_ocpp_msgs_charger ON public.ottoq_ocpp_messages USING btree (charger_id, message_at DESC);
-- @@ index public.idx_ocpp_msgs_seq_brin
CREATE INDEX idx_ocpp_msgs_seq_brin ON public.ottoq_ocpp_messages USING brin (message_seq);
-- @@ index public.idx_ocpp_msgs_session
CREATE INDEX idx_ocpp_msgs_session ON public.ottoq_ocpp_messages USING btree (ocpp_session_id, message_at);
-- @@ index public.idx_ocpp_msgs_sim_run
CREATE INDEX idx_ocpp_msgs_sim_run ON public.ottoq_ocpp_messages USING btree (sim_run_id, message_at) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.idx_ocpp_msgs_type
CREATE INDEX idx_ocpp_msgs_type ON public.ottoq_ocpp_messages USING btree (message_type, message_at DESC);
-- @@ index public.idx_ocpp_sessions_active
CREATE INDEX idx_ocpp_sessions_active ON public.ocpp_sessions USING btree (status) WHERE (status = 'active'::public.ocpp_session_status);
-- @@ index public.idx_ocpp_sessions_active_run
CREATE INDEX idx_ocpp_sessions_active_run ON public.ocpp_sessions USING btree (depot_id, sim_run_id) WHERE (status = 'active'::public.ocpp_session_status);
-- @@ index public.idx_ocpp_sessions_charge_point
CREATE INDEX idx_ocpp_sessions_charge_point ON public.ocpp_sessions USING btree (charge_point_id, started_at DESC);
-- @@ index public.idx_ocpp_sessions_depot
CREATE INDEX idx_ocpp_sessions_depot ON public.ocpp_sessions USING btree (depot_id, started_at DESC);
-- @@ index public.idx_ocpp_sessions_sim_run
CREATE INDEX idx_ocpp_sessions_sim_run ON public.ocpp_sessions USING btree (sim_run_id);
-- @@ index public.idx_ocpp_sessions_stall
CREATE INDEX idx_ocpp_sessions_stall ON public.ocpp_sessions USING btree (stall_id);
-- @@ index public.idx_ocpp_sessions_transaction
CREATE INDEX idx_ocpp_sessions_transaction ON public.ocpp_sessions USING btree (transaction_id);
-- @@ index public.idx_ocpp_sessions_vehicle
CREATE INDEX idx_ocpp_sessions_vehicle ON public.ocpp_sessions USING btree (vehicle_id) WHERE (vehicle_id IS NOT NULL);
-- @@ index public.idx_ops_approvals_pending
CREATE INDEX idx_ops_approvals_pending ON public.ottoq_ops_approvals USING btree (depot_id, status, approval_type);
-- @@ index public.idx_ops_approvals_sim_run_id
CREATE INDEX idx_ops_approvals_sim_run_id ON public.ottoq_ops_approvals USING btree (sim_run_id);
-- @@ index public.idx_ops_approvals_vehicle
CREATE INDEX idx_ops_approvals_vehicle ON public.ottoq_ops_approvals USING btree (vehicle_id, created_at DESC);
-- @@ index public.idx_ops_approvals_visit_id
CREATE INDEX idx_ops_approvals_visit_id ON public.ottoq_ops_approvals USING btree (visit_id);
-- @@ index public.idx_ottoq_bess_depot
CREATE INDEX idx_ottoq_bess_depot ON public.ottoq_bess_units USING btree (depot_id, current_state);
-- @@ index public.idx_ottoq_bess_state
CREATE INDEX idx_ottoq_bess_state ON public.ottoq_bess_units USING btree (current_state, current_state_updated_at);
-- @@ index public.idx_ottoq_energy_cmd_active
CREATE INDEX idx_ottoq_energy_cmd_active ON public.ottoq_energy_commands USING btree (sim_run_id, depot_id, command_type, issued_at DESC);
-- @@ index public.idx_ottoq_energy_cmd_pending
CREATE INDEX idx_ottoq_energy_cmd_pending ON public.ottoq_energy_commands USING btree (depot_id, status) WHERE (status = 'pending'::text);
-- @@ index public.idx_ottoq_evals_correlation
CREATE INDEX idx_ottoq_evals_correlation ON public.ottoq_rule_evaluations USING btree (correlation_id);
-- @@ index public.idx_ottoq_evals_depot
CREATE INDEX idx_ottoq_evals_depot ON public.ottoq_rule_evaluations USING btree (depot_id, evaluated_at DESC) WHERE (depot_id IS NOT NULL);
-- @@ index public.idx_ottoq_evals_entity_time
CREATE INDEX idx_ottoq_evals_entity_time ON public.ottoq_rule_evaluations USING btree (entity_type, entity_id, evaluated_at DESC);
-- @@ index public.idx_ottoq_evals_failed
CREATE INDEX idx_ottoq_evals_failed ON public.ottoq_rule_evaluations USING btree (evaluated_at DESC) WHERE (passed = false);
-- @@ index public.idx_ottoq_evals_rule_time
CREATE INDEX idx_ottoq_evals_rule_time ON public.ottoq_rule_evaluations USING btree (rule_code, evaluated_at DESC);
-- @@ index public.idx_ottoq_evals_seq_brin
CREATE INDEX idx_ottoq_evals_seq_brin ON public.ottoq_rule_evaluations USING brin (evaluation_seq);
-- @@ index public.idx_ottoq_evals_sim_run
CREATE INDEX idx_ottoq_evals_sim_run ON public.ottoq_rule_evaluations USING btree (sim_run_id, evaluation_seq) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.idx_ottoq_evals_tenant
CREATE INDEX idx_ottoq_evals_tenant ON public.ottoq_rule_evaluations USING btree (fleet_operator_id, evaluated_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_ottoq_event_state_anchor_sim_run
CREATE INDEX idx_ottoq_event_state_anchor_sim_run ON public.ottoq_event_state_anchor USING btree (sim_run_id);
-- @@ index public.idx_ottoq_ocpp_chargers_depot
CREATE INDEX idx_ottoq_ocpp_chargers_depot ON public.ottoq_ocpp_chargers USING btree (depot_id, station_state);
-- @@ index public.idx_ottoq_ocpp_chargers_state
CREATE INDEX idx_ottoq_ocpp_chargers_state ON public.ottoq_ocpp_chargers USING btree (station_state, station_state_changed_at);
-- @@ index public.idx_ottoq_overrides_actor
CREATE INDEX idx_ottoq_overrides_actor ON public.ottoq_rule_overrides USING btree (override_actor_type, override_actor_id, created_at DESC);
-- @@ index public.idx_ottoq_overrides_rule
CREATE INDEX idx_ottoq_overrides_rule ON public.ottoq_rule_overrides USING btree (rule_code, created_at DESC);
-- @@ index public.idx_ottoq_recall_decisions_run
CREATE INDEX idx_ottoq_recall_decisions_run ON public.ottoq_recall_decisions USING btree (sim_run_id, decided_at_sim, vehicle_id);
-- @@ index public.idx_ottoq_rule_parameters_lookup
CREATE INDEX idx_ottoq_rule_parameters_lookup ON public.ottoq_rule_parameters USING btree (rule_code, scope, scope_id, effective_from, effective_until);
-- @@ index public.idx_ottoq_rules_action
CREATE INDEX idx_ottoq_rules_action ON public.ottoq_rules USING gin (applies_to_actions);
-- @@ index public.idx_ottoq_rules_category
CREATE INDEX idx_ottoq_rules_category ON public.ottoq_rules USING btree (category, status);
-- @@ index public.idx_ottoq_rules_code_active
CREATE INDEX idx_ottoq_rules_code_active ON public.ottoq_rules USING btree (rule_code) WHERE (status = 'active'::text);
-- @@ index public.idx_ottoq_run_archives_archived_at
CREATE INDEX idx_ottoq_run_archives_archived_at ON public.ottoq_run_archives USING btree (archived_at DESC);
-- @@ index public.idx_ottoq_state_trans_lookup
CREATE INDEX idx_ottoq_state_trans_lookup ON public.ottoq_state_transitions USING btree (entity_kind, from_state, to_state) WHERE (status = 'active'::text);
-- @@ index public.idx_ottow_api_keys_hash
CREATE INDEX idx_ottow_api_keys_hash ON public.ottow_api_keys USING btree (key_hash) WHERE (is_active = true);
-- @@ index public.idx_ottow_dispatch_rules_depot_order
CREATE INDEX idx_ottow_dispatch_rules_depot_order ON public.ottow_dispatch_rules USING btree (depot_id, priority_order) WHERE (is_active = true);
-- @@ index public.idx_ottow_drivers_depot_status
CREATE INDEX idx_ottow_drivers_depot_status ON public.ottow_drivers USING btree (depot_id, status);
-- @@ index public.idx_ottow_drivers_staff
CREATE INDEX idx_ottow_drivers_staff ON public.ottow_drivers USING btree (staff_user_id);
-- @@ index public.idx_ottow_events_mission_time
CREATE INDEX idx_ottow_events_mission_time ON public.ottow_mission_events USING btree (mission_id, created_at);
-- @@ index public.idx_ottow_events_type
CREATE INDEX idx_ottow_events_type ON public.ottow_mission_events USING btree (mission_id, event_type);
-- @@ index public.idx_ottow_missions_active
CREATE INDEX idx_ottow_missions_active ON public.ottow_missions USING btree (depot_id, status) WHERE (status <> ALL (ARRAY['closed'::text, 'cancelled'::text]));
-- @@ index public.idx_ottow_missions_depot_status
CREATE INDEX idx_ottow_missions_depot_status ON public.ottow_missions USING btree (depot_id, status);
-- @@ index public.idx_ottow_missions_driver
CREATE INDEX idx_ottow_missions_driver ON public.ottow_missions USING btree (driver_staff_id, status);
-- @@ index public.idx_ottow_missions_exception
CREATE INDEX idx_ottow_missions_exception ON public.ottow_missions USING btree (exception_id);
-- @@ index public.idx_ottow_missions_notification
CREATE INDEX idx_ottow_missions_notification ON public.ottow_missions USING btree (notification_id) WHERE (notification_id IS NOT NULL);
-- @@ index public.idx_ottow_missions_vehicle
CREATE INDEX idx_ottow_missions_vehicle ON public.ottow_missions USING btree (vehicle_id);
-- @@ index public.idx_ottow_notifications_dedup
CREATE UNIQUE INDEX idx_ottow_notifications_dedup ON public.ottow_notifications USING btree (dedup_key) WHERE (status <> 'rejected'::text);
-- @@ index public.idx_ottow_notifications_depot_time
CREATE INDEX idx_ottow_notifications_depot_time ON public.ottow_notifications USING btree (depot_id, received_at DESC);
-- @@ index public.idx_ottow_notifications_pending
CREATE INDEX idx_ottow_notifications_pending ON public.ottow_notifications USING btree (depot_id, status) WHERE (status = 'pending'::text);
-- @@ index public.idx_ottow_notifications_vehicle
CREATE INDEX idx_ottow_notifications_vehicle ON public.ottow_notifications USING btree (vehicle_id, status);
-- @@ index public.idx_pred_accuracy_depot
CREATE INDEX idx_pred_accuracy_depot ON public.ottoq_prediction_accuracy_heatmap USING btree (depot_id, prediction_type, report_date DESC) WHERE (depot_id IS NOT NULL);
-- @@ index public.idx_pred_accuracy_model
CREATE INDEX idx_pred_accuracy_model ON public.ottoq_prediction_accuracy_heatmap USING btree (model_version_id, report_date DESC) WHERE (model_version_id IS NOT NULL);
-- @@ index public.idx_pred_accuracy_tenant
CREATE INDEX idx_pred_accuracy_tenant ON public.ottoq_prediction_accuracy_heatmap USING btree (fleet_operator_id, prediction_type, report_date DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_pred_accuracy_type_date
CREATE INDEX idx_pred_accuracy_type_date ON public.ottoq_prediction_accuracy_heatmap USING btree (prediction_type, report_date DESC);
-- @@ index public.idx_prediction_outcomes_accuracy
CREATE INDEX idx_prediction_outcomes_accuracy ON public.prediction_outcomes USING btree (depot_id, accuracy_score, scored_at DESC);
-- @@ index public.idx_prediction_outcomes_depot_time
CREATE INDEX idx_prediction_outcomes_depot_time ON public.prediction_outcomes USING btree (depot_id, scored_at DESC);
-- @@ index public.idx_prediction_outcomes_prediction
CREATE INDEX idx_prediction_outcomes_prediction ON public.prediction_outcomes USING btree (prediction_id);
-- @@ index public.idx_prediction_outcomes_type
CREATE INDEX idx_prediction_outcomes_type ON public.prediction_outcomes USING btree (depot_id, prediction_type, scored_at DESC);
-- @@ index public.idx_predictions_ab_test
CREATE INDEX idx_predictions_ab_test ON public.ottoq_predictions USING btree (ab_test_id, ab_test_variant, created_at DESC) WHERE (ab_test_id IS NOT NULL);
-- @@ index public.idx_predictions_actionable
CREATE INDEX idx_predictions_actionable ON public.ottoq_predictions USING btree (depot_id, execution_status, action_type) WHERE ((action_type IS NOT NULL) AND (execution_status = ANY (ARRAY['pending'::text, 'approved'::text])));
-- @@ index public.idx_predictions_baseline
CREATE INDEX idx_predictions_baseline ON public.ottoq_predictions USING btree (prediction_baseline, prediction_type, created_at DESC);
-- @@ index public.idx_predictions_depot
CREATE INDEX idx_predictions_depot ON public.ottoq_predictions USING btree (depot_id, created_at DESC);
-- @@ index public.idx_predictions_event
CREATE INDEX idx_predictions_event ON public.ottoq_predictions USING btree (event_id) WHERE (event_id IS NOT NULL);
-- @@ index public.idx_predictions_horizon
CREATE INDEX idx_predictions_horizon ON public.ottoq_predictions USING btree (depot_id, time_horizon_hours, created_at DESC) WHERE (time_horizon_hours IS NOT NULL);
-- @@ index public.idx_predictions_inputs_hash
CREATE INDEX idx_predictions_inputs_hash ON public.ottoq_predictions USING btree (inputs_hash) WHERE (inputs_hash IS NOT NULL);
-- @@ index public.idx_predictions_model_version
CREATE INDEX idx_predictions_model_version ON public.ottoq_predictions USING btree (model_version_id, created_at DESC);
-- @@ index public.idx_predictions_status
CREATE INDEX idx_predictions_status ON public.ottoq_predictions USING btree (status) WHERE (status = 'pending'::text);
-- @@ index public.idx_predictions_target_at
CREATE INDEX idx_predictions_target_at ON public.ottoq_predictions USING btree (target_at);
-- @@ index public.idx_predictions_tenant_time
CREATE INDEX idx_predictions_tenant_time ON public.ottoq_predictions USING btree (fleet_operator_id, created_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_predictions_vehicle
CREATE INDEX idx_predictions_vehicle ON public.ottoq_predictions USING btree (vehicle_id, created_at DESC);
-- @@ index public.idx_prog_decisions_decision
CREATE INDEX idx_prog_decisions_decision ON public.progression_decisions USING btree (decision, decided_at DESC);
-- @@ index public.idx_prog_decisions_depot
CREATE INDEX idx_prog_decisions_depot ON public.progression_decisions USING btree (depot_id, decided_at DESC);
-- @@ index public.idx_prog_decisions_fleet
CREATE INDEX idx_prog_decisions_fleet ON public.progression_decisions USING btree (fleet_operator_id, decided_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_prog_decisions_schedule
CREATE INDEX idx_prog_decisions_schedule ON public.progression_decisions USING btree (schedule_id, decided_at) WHERE (schedule_id IS NOT NULL);
-- @@ index public.idx_prog_decisions_vehicle
CREATE INDEX idx_prog_decisions_vehicle ON public.progression_decisions USING btree (vehicle_id, decided_at DESC);
-- @@ index public.idx_rcf_run_status
CREATE INDEX idx_rcf_run_status ON public.ottoq_rider_cleaning_flags USING btree (sim_run_id, status);
-- @@ index public.idx_rcf_vehicle
CREATE INDEX idx_rcf_vehicle ON public.ottoq_rider_cleaning_flags USING btree (vehicle_id, sim_run_id);
-- @@ index public.idx_recall_depot
CREATE INDEX idx_recall_depot ON public.early_recall_log USING btree (depot_id, assessed_at DESC);
-- @@ index public.idx_recall_urgency
CREATE INDEX idx_recall_urgency ON public.early_recall_log USING btree (urgency) WHERE (urgency <> 'none'::public.recall_urgency);
-- @@ index public.idx_recall_vehicle
CREATE INDEX idx_recall_vehicle ON public.early_recall_log USING btree (vehicle_id, assessed_at DESC);
-- @@ index public.idx_recs_correlation
CREATE INDEX idx_recs_correlation ON public.ottoq_recommendations USING btree (correlation_id);
-- @@ index public.idx_recs_pending
CREATE INDEX idx_recs_pending ON public.ottoq_recommendations USING btree (emitted_at DESC) WHERE (status = ANY (ARRAY['pending'::text, 'validating'::text, 'shadow'::text]));
-- @@ index public.idx_recs_prediction
CREATE INDEX idx_recs_prediction ON public.ottoq_recommendations USING btree (prediction_id) WHERE (prediction_id IS NOT NULL);
-- @@ index public.idx_recs_status_time
CREATE INDEX idx_recs_status_time ON public.ottoq_recommendations USING btree (status, emitted_at DESC);
-- @@ index public.idx_recs_tenant_time
CREATE INDEX idx_recs_tenant_time ON public.ottoq_recommendations USING btree (fleet_operator_id, emitted_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_retail_members_auth
CREATE INDEX idx_retail_members_auth ON public.retail_members USING btree (auth_user_id);
-- @@ index public.idx_retail_members_depot
CREATE INDEX idx_retail_members_depot ON public.retail_members USING btree (home_depot_id);
-- @@ index public.idx_rule_evals_linked_event
CREATE INDEX idx_rule_evals_linked_event ON public.ottoq_rule_evaluations USING btree (linked_event_id);
-- @@ index public.idx_rule_evals_trig_event
CREATE INDEX idx_rule_evals_trig_event ON public.ottoq_rule_evaluations USING btree (triggered_by_event_id);
-- @@ index public.idx_rule_overrides_linked_evt
CREATE INDEX idx_rule_overrides_linked_evt ON public.ottoq_rule_overrides USING btree (linked_event_id);
-- @@ index public.idx_run_archives_repro_key
CREATE INDEX idx_run_archives_repro_key ON public.ottoq_run_archives USING btree (policy, pack_id, random_seed, config_hash);
-- @@ index public.idx_scenarios_category
CREATE INDEX idx_scenarios_category ON public.ottoq_scenarios USING btree (category, status);
-- @@ index public.idx_scenarios_depot
CREATE INDEX idx_scenarios_depot ON public.ottoq_scenarios USING btree (depot_id, status);
-- @@ index public.idx_schedule_tasks_abnormality_open
CREATE INDEX idx_schedule_tasks_abnormality_open ON public.schedule_tasks USING btree (vehicle_id, depot_id) WHERE ((abnormality_flagged = true) AND (abnormality_resolved_at IS NULL));
-- @@ index public.idx_schedule_tasks_oem_pending
CREATE INDEX idx_schedule_tasks_oem_pending ON public.schedule_tasks USING btree (oem_acceptance_expires_at) WHERE (oem_acceptance_state = 'pending'::text);
-- @@ index public.idx_schedule_tasks_overnight_release
CREATE INDEX idx_schedule_tasks_overnight_release ON public.schedule_tasks USING btree (scheduled_release_at) WHERE ((is_overnight_stage = true) AND (scheduled_release_fired_at IS NULL));
-- @@ index public.idx_schedule_tasks_schedule_id
CREATE INDEX idx_schedule_tasks_schedule_id ON public.schedule_tasks USING btree (schedule_id);
-- @@ index public.idx_schedules_arrival
CREATE INDEX idx_schedules_arrival ON public.vehicle_schedules USING btree (arrival_time);
-- @@ index public.idx_schedules_depot_date
CREATE INDEX idx_schedules_depot_date ON public.vehicle_schedules USING btree (depot_id, scheduled_date);
-- @@ index public.idx_schedules_status
CREATE INDEX idx_schedules_status ON public.vehicle_schedules USING btree (status);
-- @@ index public.idx_schedules_vehicle
CREATE INDEX idx_schedules_vehicle ON public.vehicle_schedules USING btree (vehicle_id);
-- @@ index public.idx_schedules_wave
CREATE INDEX idx_schedules_wave ON public.vehicle_schedules USING btree (wave_id);
-- @@ index public.idx_sdr_operation
CREATE INDEX idx_sdr_operation ON public.ottoq_service_detail_records USING btree (pack_id, operation_code, ended_at);
-- @@ index public.idx_sdr_operator
CREATE INDEX idx_sdr_operator ON public.ottoq_service_detail_records USING btree (fleet_operator_id, ended_at);
-- @@ index public.idx_sdr_run
CREATE INDEX idx_sdr_run ON public.ottoq_service_detail_records USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.idx_sim_runs_scenario
CREATE INDEX idx_sim_runs_scenario ON public.ottoq_sim_runs USING btree (scenario_id, started_at DESC);
-- @@ index public.idx_sim_runs_status
CREATE INDEX idx_sim_runs_status ON public.ottoq_sim_runs USING btree (status, next_tick_due_at) WHERE (status = 'running'::text);
-- @@ index public.idx_site_energy_depot_time
CREATE INDEX idx_site_energy_depot_time ON public.site_energy_snapshots USING btree (depot_id, "timestamp" DESC);
-- @@ index public.idx_site_energy_snapshots_created_at
CREATE INDEX idx_site_energy_snapshots_created_at ON public.site_energy_snapshots USING btree (created_at DESC);
-- @@ index public.idx_site_energy_snapshots_sim_run
CREATE INDEX idx_site_energy_snapshots_sim_run ON public.site_energy_snapshots USING btree (sim_run_id, "timestamp");
-- @@ index public.idx_site_structures_depot
CREATE INDEX idx_site_structures_depot ON public.ottoq_site_structures USING btree (depot_id, structure_kind);
-- @@ index public.idx_sla_conf_depot_date
CREATE INDEX idx_sla_conf_depot_date ON public.ottoq_sla_conformance_daily USING btree (depot_id, report_date DESC) WHERE (depot_id IS NOT NULL);
-- @@ index public.idx_sla_conf_tenant_date
CREATE INDEX idx_sla_conf_tenant_date ON public.ottoq_sla_conformance_daily USING btree (fleet_operator_id, report_date DESC);
-- @@ index public.idx_sla_violations_linked_evt
CREATE INDEX idx_sla_violations_linked_evt ON public.ottoq_sla_violations USING btree (linked_event_id);
-- @@ index public.idx_sla_violations_rule
CREATE INDEX idx_sla_violations_rule ON public.ottoq_sla_violations USING btree (rule_code, detected_at DESC);
-- @@ index public.idx_sla_violations_tenant_time
CREATE INDEX idx_sla_violations_tenant_time ON public.ottoq_sla_violations USING btree (fleet_operator_id, detected_at DESC);
-- @@ index public.idx_sla_violations_vehicle
CREATE INDEX idx_sla_violations_vehicle ON public.ottoq_sla_violations USING btree (vehicle_id, detected_at DESC) WHERE (vehicle_id IS NOT NULL);
-- @@ index public.idx_slos_active
CREATE INDEX idx_slos_active ON public.accuracy_slos USING btree (depot_id, prediction_type, is_active);
-- @@ index public.idx_solar_canopy
CREATE INDEX idx_solar_canopy ON public.ottoq_solar_output USING btree (canopy_code, sim_clock_at DESC);
-- @@ index public.idx_solar_depot_clock
CREATE INDEX idx_solar_depot_clock ON public.ottoq_solar_output USING btree (depot_id, sim_clock_at DESC);
-- @@ index public.idx_solar_sim_run
CREATE INDEX idx_solar_sim_run ON public.ottoq_solar_output USING btree (sim_run_id, sim_clock_at DESC);
-- @@ index public.idx_staff_depot
CREATE INDEX idx_staff_depot ON public.staff_users USING btree (depot_id);
-- @@ index public.idx_staff_role
CREATE INDEX idx_staff_role ON public.staff_users USING btree (depot_id, role);
-- @@ index public.idx_staff_shift
CREATE INDEX idx_staff_shift ON public.staff_users USING btree (is_on_shift) WHERE (is_on_shift = true);
-- @@ index public.idx_stalls_depot
CREATE INDEX idx_stalls_depot ON public.stalls USING btree (depot_id);
-- @@ index public.idx_stalls_distance
CREATE INDEX idx_stalls_distance ON public.stalls USING btree (depot_id, stall_type, distance_from_entrance DESC);
-- @@ index public.idx_stalls_one_vehicle_per_stall
CREATE UNIQUE INDEX idx_stalls_one_vehicle_per_stall ON public.stalls USING btree (current_vehicle_id) WHERE (current_vehicle_id IS NOT NULL);
-- @@ index public.idx_stalls_reserved_by
CREATE INDEX idx_stalls_reserved_by ON public.stalls USING btree (reserved_by) WHERE (reserved_by IS NOT NULL);
-- @@ index public.idx_stalls_reserved_mission
CREATE INDEX idx_stalls_reserved_mission ON public.stalls USING btree (reserved_for_mission_id) WHERE (reserved_for_mission_id IS NOT NULL);
-- @@ index public.idx_stalls_status
CREATE INDEX idx_stalls_status ON public.stalls USING btree (depot_id, status);
-- @@ index public.idx_stalls_type
CREATE INDEX idx_stalls_type ON public.stalls USING btree (depot_id, stall_type);
-- @@ index public.idx_state_log_depot_time
CREATE INDEX idx_state_log_depot_time ON public.vehicle_state_log USING btree (depot_id, created_at DESC);
-- @@ index public.idx_state_log_state
CREATE INDEX idx_state_log_state ON public.vehicle_state_log USING btree (new_state, created_at DESC);
-- @@ index public.idx_state_log_trigger
CREATE INDEX idx_state_log_trigger ON public.vehicle_state_log USING btree (triggered_by);
-- @@ index public.idx_state_log_vehicle_time
CREATE INDEX idx_state_log_vehicle_time ON public.vehicle_state_log USING btree (vehicle_id, created_at DESC);
-- @@ index public.idx_tariffs_depot
CREATE INDEX idx_tariffs_depot ON public.tariff_schedules USING btree (depot_id) WHERE (is_active = true);
-- @@ index public.idx_tasks_schedule
CREATE INDEX idx_tasks_schedule ON public.schedule_tasks USING btree (vehicle_schedule_id);
-- @@ index public.idx_tasks_sequence
CREATE INDEX idx_tasks_sequence ON public.schedule_tasks USING btree (vehicle_schedule_id, sequence_order);
-- @@ index public.idx_tasks_stall
CREATE INDEX idx_tasks_stall ON public.schedule_tasks USING btree (assigned_stall_id);
-- @@ index public.idx_tasks_status
CREATE INDEX idx_tasks_status ON public.schedule_tasks USING btree (status);
-- @@ index public.idx_tasks_timing
CREATE INDEX idx_tasks_timing ON public.schedule_tasks USING btree (scheduled_start, scheduled_end);
-- @@ index public.idx_tasks_vehicle
CREATE INDEX idx_tasks_vehicle ON public.schedule_tasks USING btree (vehicle_id);
-- @@ index public.idx_telem_dropped
CREATE INDEX idx_telem_dropped ON public.ottoq_telemetry_packets USING btree (packet_at DESC) WHERE (packet_integrity = 'dropped'::text);
-- @@ index public.idx_telem_seq_brin
CREATE INDEX idx_telem_seq_brin ON public.ottoq_telemetry_packets USING brin (packet_seq);
-- @@ index public.idx_telem_sim_run
CREATE INDEX idx_telem_sim_run ON public.ottoq_telemetry_packets USING btree (sim_run_id, sim_clock_at) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.idx_telem_state
CREATE INDEX idx_telem_state ON public.ottoq_telemetry_packets USING btree (vehicle_state, sim_clock_at DESC);
-- @@ index public.idx_telem_vehicle_time
CREATE INDEX idx_telem_vehicle_time ON public.ottoq_telemetry_packets USING btree (vehicle_id, sim_clock_at DESC);
-- @@ index public.idx_telemetry_depot
CREATE INDEX idx_telemetry_depot ON public.vehicle_telemetry USING btree (depot_id, "timestamp" DESC);
-- @@ index public.idx_telemetry_vehicle_time
CREATE INDEX idx_telemetry_vehicle_time ON public.vehicle_telemetry USING btree (vehicle_id, "timestamp" DESC);
-- @@ index public.idx_tick_clock_log_run_time
CREATE INDEX idx_tick_clock_log_run_time ON public.ottoq_tick_clock_log USING btree (sim_run_id, real_started_at DESC);
-- @@ index public.idx_tick_reservations_run_tick
CREATE INDEX idx_tick_reservations_run_tick ON public.ottoq_tick_reservations USING btree (sim_run_id, tick_seq, resource);
-- @@ index public.idx_training_runs_status
CREATE INDEX idx_training_runs_status ON public.ottoq_training_runs USING btree (status, started_at DESC);
-- @@ index public.idx_training_runs_type_time
CREATE INDEX idx_training_runs_type_time ON public.ottoq_training_runs USING btree (prediction_type, started_at DESC);
-- @@ index public.idx_tuning_iter_best
CREATE INDEX idx_tuning_iter_best ON public.tuning_iterations USING btree (tuning_run_id, is_best_so_far);
-- @@ index public.idx_tuning_iter_run
CREATE INDEX idx_tuning_iter_run ON public.tuning_iterations USING btree (tuning_run_id, iteration_number);
-- @@ index public.idx_tuning_runs_depot_time
CREATE INDEX idx_tuning_runs_depot_time ON public.model_tuning_runs USING btree (depot_id, created_at DESC);
-- @@ index public.idx_tuning_runs_group
CREATE INDEX idx_tuning_runs_group ON public.model_tuning_runs USING btree (depot_id, parameter_group, created_at DESC);
-- @@ index public.idx_tuning_runs_status
CREATE INDEX idx_tuning_runs_status ON public.model_tuning_runs USING btree (status, created_at DESC);
-- @@ index public.idx_vehicle_classes_oem
CREATE INDEX idx_vehicle_classes_oem ON public.ottoq_vehicle_classes USING btree (oem_name, status);
-- @@ index public.idx_vehicle_commands_run
CREATE INDEX idx_vehicle_commands_run ON public.ottoq_vehicle_commands USING btree (sim_run_id, status);
-- @@ index public.idx_vehicle_commands_vehicle
CREATE INDEX idx_vehicle_commands_vehicle ON public.ottoq_vehicle_commands USING btree (vehicle_id, issued_at DESC);
-- @@ index public.idx_vehicle_wear_run
CREATE INDEX idx_vehicle_wear_run ON public.ottoq_vehicle_wear USING btree (sim_run_id);
-- @@ index public.idx_vehicles_active
CREATE INDEX idx_vehicles_active ON public.vehicles USING btree (is_active) WHERE (is_active = true);
-- @@ index public.idx_vehicles_depot
CREATE INDEX idx_vehicles_depot ON public.vehicles USING btree (home_depot_id);
-- @@ index public.idx_vehicles_fleet
CREATE INDEX idx_vehicles_fleet ON public.vehicles USING btree (fleet_operator_id) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_vehicles_owning_sim_run
CREATE INDEX idx_vehicles_owning_sim_run ON public.vehicles USING btree (owning_sim_run_id);
-- @@ index public.idx_vehicles_retail
CREATE INDEX idx_vehicles_retail ON public.vehicles USING btree (retail_member_id) WHERE (retail_member_id IS NOT NULL);
-- @@ index public.idx_vehicles_state
CREATE INDEX idx_vehicles_state ON public.vehicles USING btree (current_state);
-- @@ index public.idx_visit_cost_depot_time
CREATE INDEX idx_visit_cost_depot_time ON public.ottoq_visit_cost_attribution USING btree (depot_id, visit_completed_at DESC) WHERE (depot_id IS NOT NULL);
-- @@ index public.idx_visit_cost_tenant_time
CREATE INDEX idx_visit_cost_tenant_time ON public.ottoq_visit_cost_attribution USING btree (fleet_operator_id, visit_completed_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_visit_needs_open_by_vehicle
CREATE INDEX idx_visit_needs_open_by_vehicle ON public.ottoq_visit_needs USING btree (vehicle_id, created_at DESC) WHERE (status = ANY (ARRAY['open'::text, 'in_progress'::text]));
-- @@ index public.idx_visit_needs_run_status
CREATE INDEX idx_visit_needs_run_status ON public.ottoq_visit_needs USING btree (sim_run_id, status);
-- @@ index public.idx_visit_needs_vehicle
CREATE INDEX idx_visit_needs_vehicle ON public.ottoq_visit_needs USING btree (vehicle_id, created_at DESC);
-- @@ index public.idx_visit_reports_depot
CREATE INDEX idx_visit_reports_depot ON public.depot_visit_reports USING btree (depot_id, generated_at DESC);
-- @@ index public.idx_visit_reports_fleet
CREATE INDEX idx_visit_reports_fleet ON public.depot_visit_reports USING btree (fleet_operator_id, generated_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.idx_visit_reports_schedule_unique
CREATE UNIQUE INDEX idx_visit_reports_schedule_unique ON public.depot_visit_reports USING btree (schedule_id);
-- @@ index public.idx_visit_reports_vehicle
CREATE INDEX idx_visit_reports_vehicle ON public.depot_visit_reports USING btree (vehicle_id, generated_at DESC);
-- @@ index public.idx_wave_plan_run
CREATE INDEX idx_wave_plan_run ON public.ottoq_wave_plan USING btree (sim_run_id, created_at DESC);
-- @@ index public.idx_waves_depot_date
CREATE INDEX idx_waves_depot_date ON public.waves USING btree (depot_id, scheduled_date);
-- @@ index public.idx_waves_status
CREATE INDEX idx_waves_status ON public.waves USING btree (status);
-- @@ index public.idx_weather_depot_clock
CREATE INDEX idx_weather_depot_clock ON public.ottoq_weather_snapshots USING btree (depot_id, sim_clock_at DESC);
-- @@ index public.idx_weather_sim_run
CREATE INDEX idx_weather_sim_run ON public.ottoq_weather_snapshots USING btree (sim_run_id, sim_clock_at DESC);
-- @@ index public.idx_webhook_log_oem_type
CREATE INDEX idx_webhook_log_oem_type ON public.ottoq_oem_webhook_log USING btree (oem_name, webhook_type);
-- @@ index public.idx_webhook_log_sim_run
CREATE INDEX idx_webhook_log_sim_run ON public.ottoq_oem_webhook_log USING btree (sim_run_id, sim_clock_emitted_at DESC);
-- @@ index public.idx_webhook_log_status
CREATE INDEX idx_webhook_log_status ON public.ottoq_oem_webhook_log USING btree (delivery_status, validation_result);
-- @@ index public.idx_webhook_log_vehicle
CREATE INDEX idx_webhook_log_vehicle ON public.ottoq_oem_webhook_log USING btree (vehicle_id, sim_clock_emitted_at DESC);
-- @@ index public.ix_comms_corr
CREATE INDEX ix_comms_corr ON public.ottoq_comms_messages USING btree (correlation_id);
-- @@ index public.ix_comms_run_veh
CREATE INDEX ix_comms_run_veh ON public.ottoq_comms_messages USING btree (sim_run_id, vehicle_id, created_at);
-- @@ index public.ix_vcards_current
CREATE INDEX ix_vcards_current ON public.ottoq_variability_cards USING btree (sim_run_id, var_key, scope_instance) WHERE active;
-- @@ index public.ocpp_sessions_runscope_load_idx
CREATE INDEX ocpp_sessions_runscope_load_idx ON public.ocpp_sessions USING btree (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid), depot_id, status, started_at);
-- @@ index public.ottoq_agent_call_ledger_at_idx
CREATE INDEX ottoq_agent_call_ledger_at_idx ON public.ottoq_agent_call_ledger USING btree (called_at DESC);
-- @@ index public.ottoq_agent_call_ledger_principal_idx
CREATE INDEX ottoq_agent_call_ledger_principal_idx ON public.ottoq_agent_call_ledger USING btree (principal_id, called_at DESC);
-- @@ index public.ottoq_agent_call_ledger_unauth_idx
CREATE INDEX ottoq_agent_call_ledger_unauth_idx ON public.ottoq_agent_call_ledger USING btree (called_at) WHERE (principal_id IS NULL);
-- @@ index public.ottoq_agent_charge_orders_chain_idx
CREATE INDEX ottoq_agent_charge_orders_chain_idx ON public.ottoq_agent_charge_orders USING btree (sim_run_id, chain_id);
-- @@ index public.ottoq_agent_charge_orders_live_idx
CREATE INDEX ottoq_agent_charge_orders_live_idx ON public.ottoq_agent_charge_orders USING btree (sim_run_id, order_id DESC) WHERE (status = ANY (ARRAY['accepted'::text, 'partial'::text]));
-- @@ index public.ottoq_agent_pass_evidence_day_idx
CREATE INDEX ottoq_agent_pass_evidence_day_idx ON public.ottoq_agent_pass_evidence USING btree (recorded_at DESC);
-- @@ index public.ottoq_agent_pass_evidence_run_idx
CREATE INDEX ottoq_agent_pass_evidence_run_idx ON public.ottoq_agent_pass_evidence USING btree (sim_run_id, pass_id DESC);
-- @@ index public.ottoq_agent_principals_open_sessions_idx
CREATE INDEX ottoq_agent_principals_open_sessions_idx ON public.ottoq_agent_principals USING btree (depot_id) WHERE ((origin = 'passcode'::text) AND (status = 'active'::text));
-- @@ index public.ottoq_agent_requests_idempotency_idx
CREATE UNIQUE INDEX ottoq_agent_requests_idempotency_idx ON public.ottoq_agent_requests USING btree (principal_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);
-- @@ index public.ottoq_agent_requests_inbox_idx
CREATE INDEX ottoq_agent_requests_inbox_idx ON public.ottoq_agent_requests USING btree (depot_id, status, created_at DESC);
-- @@ index public.ottoq_agent_requests_operator_idx
CREATE INDEX ottoq_agent_requests_operator_idx ON public.ottoq_agent_requests USING btree (fleet_operator_id, created_at DESC) WHERE (fleet_operator_id IS NOT NULL);
-- @@ index public.ottoq_agent_requests_principal_idx
CREATE INDEX ottoq_agent_requests_principal_idx ON public.ottoq_agent_requests USING btree (principal_id, created_at DESC);
-- @@ index public.ottoq_agent_requests_run_idx
CREATE INDEX ottoq_agent_requests_run_idx ON public.ottoq_agent_requests USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.ottoq_agent_requests_vehicle_idx
CREATE INDEX ottoq_agent_requests_vehicle_idx ON public.ottoq_agent_requests USING btree (vehicle_id, status) WHERE (vehicle_id IS NOT NULL);
-- @@ index public.ottoq_bay_binding_witness_booking_idx
CREATE INDEX ottoq_bay_binding_witness_booking_idx ON public.ottoq_bay_binding_witness USING btree (booking_id, observed_real);
-- @@ index public.ottoq_bay_binding_witness_run_idx
CREATE INDEX ottoq_bay_binding_witness_run_idx ON public.ottoq_bay_binding_witness USING btree (sim_run_id, observed_real);
-- @@ index public.ottoq_challenger_findings_run_status
CREATE INDEX ottoq_challenger_findings_run_status ON public.ottoq_challenger_findings USING btree (sim_run_id, status);
-- @@ index public.ottoq_channel_health_channel_idx
CREATE INDEX ottoq_channel_health_channel_idx ON public.ottoq_channel_health USING btree (channel, health_id DESC);
-- @@ index public.ottoq_charge_clock_fits_latest_idx
CREATE INDEX ottoq_charge_clock_fits_latest_idx ON public.ottoq_charge_clock_fits USING btree (depot_id, fit_id DESC);
-- @@ index public.ottoq_charge_duration_ledger_fit_idx
CREATE INDEX ottoq_charge_duration_ledger_fit_idx ON public.ottoq_charge_duration_ledger USING btree (charger_type, stopped_reason);
-- @@ index public.ottoq_charge_duration_ledger_run_idx
CREATE INDEX ottoq_charge_duration_ledger_run_idx ON public.ottoq_charge_duration_ledger USING btree (sim_run_id);
-- @@ index public.ottoq_charge_fault_fits_latest_idx
CREATE INDEX ottoq_charge_fault_fits_latest_idx ON public.ottoq_charge_fault_fits USING btree (depot_id, fit_id DESC);
-- @@ index public.ottoq_charge_order_hindsight_depot_idx
CREATE INDEX ottoq_charge_order_hindsight_depot_idx ON public.ottoq_charge_order_hindsight USING btree (depot_id, graded_at);
-- @@ index public.ottoq_charge_order_hindsight_run_idx
CREATE INDEX ottoq_charge_order_hindsight_run_idx ON public.ottoq_charge_order_hindsight USING btree (sim_run_id, order_id);
-- @@ index public.ottoq_charge_order_snapshots_run_idx
CREATE INDEX ottoq_charge_order_snapshots_run_idx ON public.ottoq_charge_order_snapshots USING btree (sim_run_id, order_id);
-- @@ index public.ottoq_deploy_log_run_idx
CREATE INDEX ottoq_deploy_log_run_idx ON public.ottoq_deploy_log USING btree (sim_run_id);
-- @@ index public.ottoq_dial_experiments_one_active
CREATE UNIQUE INDEX ottoq_dial_experiments_one_active ON public.ottoq_dial_experiments USING btree (depot_id, param_key) WHERE (status = 'active'::text);
-- @@ index public.ottoq_dial_pair_ledger_runs
CREATE INDEX ottoq_dial_pair_ledger_runs ON public.ottoq_dial_pair_ledger USING btree (run_a, run_b);
-- @@ index public.ottoq_dvl_canon_idx
CREATE INDEX ottoq_dvl_canon_idx ON public.ottoq_determinism_verdict_ledger USING btree (depot_id, scenario, seed, ticks, certified_at DESC);
-- @@ index public.ottoq_energy_plan_applied
CREATE INDEX ottoq_energy_plan_applied ON public.ottoq_energy_plan USING btree (sim_run_id, depot_id) WHERE (plan_state = 'applied'::text);
-- @@ index public.ottoq_energy_plan_lookup
CREATE INDEX ottoq_energy_plan_lookup ON public.ottoq_energy_plan USING btree (sim_run_id, depot_id, created_at DESC);
-- @@ index public.ottoq_event_state_anchor_day_idx
CREATE INDEX ottoq_event_state_anchor_day_idx ON public.ottoq_event_state_anchor USING btree (anchor_day);
-- @@ index public.ottoq_events_keep_correlation_id_idx
CREATE INDEX ottoq_events_keep_correlation_id_idx ON public.ottoq_events USING btree (correlation_id);
-- @@ index public.ottoq_events_keep_depot_id_occurred_at_idx
CREATE INDEX ottoq_events_keep_depot_id_occurred_at_idx ON public.ottoq_events USING btree (depot_id, occurred_at DESC) WHERE (depot_id IS NOT NULL);
-- @@ index public.ottoq_events_keep_entity_type_entity_id_occurred_at_idx
CREATE INDEX ottoq_events_keep_entity_type_entity_id_occurred_at_idx ON public.ottoq_events USING btree (entity_type, entity_id, occurred_at DESC);
-- @@ index public.ottoq_events_keep_event_type_occurred_at_idx
CREATE INDEX ottoq_events_keep_event_type_occurred_at_idx ON public.ottoq_events USING btree (event_type, occurred_at DESC);
-- @@ index public.ottoq_events_keep_occurred_at_idx
CREATE INDEX ottoq_events_keep_occurred_at_idx ON public.ottoq_events USING btree (occurred_at DESC) WHERE (severity = ANY (ARRAY['critical'::text, 'safety_critical'::text]));
-- @@ index public.ottoq_events_keep_occurred_at_idx1
CREATE INDEX ottoq_events_keep_occurred_at_idx1 ON public.ottoq_events USING brin (occurred_at);
-- @@ index public.ottoq_events_keep_parent_event_id_idx
CREATE INDEX ottoq_events_keep_parent_event_id_idx ON public.ottoq_events USING btree (parent_event_id) WHERE (parent_event_id IS NOT NULL);
-- @@ index public.ottoq_events_keep_sim_run_id_idx
CREATE INDEX ottoq_events_keep_sim_run_id_idx ON public.ottoq_events USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.ottoq_events_occurred_at_retention_idx
CREATE INDEX ottoq_events_occurred_at_retention_idx ON public.ottoq_events USING btree (occurred_at);
-- @@ index public.ottoq_evidence_regimes_lookup_idx
CREATE INDEX ottoq_evidence_regimes_lookup_idx ON public.ottoq_evidence_regimes USING btree (model, starts_at DESC);
-- @@ index public.ottoq_extprop_lookup_idx
CREATE INDEX ottoq_extprop_lookup_idx ON public.ottoq_external_proposals USING btree (sim_run_id, action_context, entity_type, entity_id, status);
-- @@ index public.ottoq_fn_definition_backups_sig_idx
CREATE INDEX ottoq_fn_definition_backups_sig_idx ON public.ottoq_fn_definition_backups USING btree (fn_signature, captured_at DESC);
-- @@ index public.ottoq_learned_estimates_latest_idx
CREATE INDEX ottoq_learned_estimates_latest_idx ON public.ottoq_learned_estimates USING btree (depot_id, model, estimate_id DESC);
-- @@ index public.ottoq_model_call_ledger_chain_idx
CREATE INDEX ottoq_model_call_ledger_chain_idx ON public.ottoq_model_call_ledger USING btree (chain_id) WHERE (chain_id IS NOT NULL);
-- @@ index public.ottoq_model_call_ledger_provider_at_idx
CREATE INDEX ottoq_model_call_ledger_provider_at_idx ON public.ottoq_model_call_ledger USING btree (provider, called_at DESC);
-- @@ index public.ottoq_model_call_ledger_run_idx
CREATE INDEX ottoq_model_call_ledger_run_idx ON public.ottoq_model_call_ledger USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.ottoq_oauth_grants_account_idx
CREATE INDEX ottoq_oauth_grants_account_idx ON public.ottoq_oauth_grants USING btree (account_id, created_at DESC);
-- @@ index public.ottoq_oauth_tokens_principal_idx
CREATE INDEX ottoq_oauth_tokens_principal_idx ON public.ottoq_oauth_tokens USING btree (principal_id, kind, issued_at DESC);
-- @@ index public.ottoq_one_running_run_per_depot
CREATE UNIQUE INDEX ottoq_one_running_run_per_depot ON public.ottoq_sim_runs USING btree (depot_id) WHERE (status = 'running'::text);
-- @@ index public.ottoq_owner_commands_idempotency_idx
CREATE UNIQUE INDEX ottoq_owner_commands_idempotency_idx ON public.ottoq_owner_commands USING btree (principal_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);
-- @@ index public.ottoq_owner_commands_operator_idx
CREATE INDEX ottoq_owner_commands_operator_idx ON public.ottoq_owner_commands USING btree (fleet_operator_id, depot_id, created_at DESC);
-- @@ index public.ottoq_owner_commands_principal_idx
CREATE INDEX ottoq_owner_commands_principal_idx ON public.ottoq_owner_commands USING btree (principal_id, created_at DESC);
-- @@ index public.ottoq_owner_commands_run_idx
CREATE INDEX ottoq_owner_commands_run_idx ON public.ottoq_owner_commands USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.ottoq_owner_settings_command_idx
CREATE INDEX ottoq_owner_settings_command_idx ON public.ottoq_owner_settings USING btree (command_id);
-- @@ index public.ottoq_owner_settings_one_hold_idx
CREATE UNIQUE INDEX ottoq_owner_settings_one_hold_idx ON public.ottoq_owner_settings USING btree (sim_run_id, vehicle_id) WHERE ((kind = 'hold'::text) AND (status = 'active'::text));
-- @@ index public.ottoq_owner_settings_one_limit_idx
CREATE UNIQUE INDEX ottoq_owner_settings_one_limit_idx ON public.ottoq_owner_settings USING btree (sim_run_id, vehicle_id) WHERE ((kind = 'charge_limit'::text) AND (status = 'active'::text));
-- @@ index public.ottoq_owner_settings_one_service_idx
CREATE UNIQUE INDEX ottoq_owner_settings_one_service_idx ON public.ottoq_owner_settings USING btree (sim_run_id, vehicle_id, service) WHERE ((kind = 'service'::text) AND (status = 'active'::text));
-- @@ index public.ottoq_owner_settings_replaces_idx
CREATE INDEX ottoq_owner_settings_replaces_idx ON public.ottoq_owner_settings USING btree (replaces_setting_id) WHERE (replaces_setting_id IS NOT NULL);
-- @@ index public.ottoq_owner_settings_tick_idx
CREATE INDEX ottoq_owner_settings_tick_idx ON public.ottoq_owner_settings USING btree (sim_run_id) WHERE ((status = 'active'::text) OR pending_reconcile);
-- @@ index public.ottoq_owner_settings_vehicle_active_idx
CREATE INDEX ottoq_owner_settings_vehicle_active_idx ON public.ottoq_owner_settings USING btree (vehicle_id, kind) WHERE (status = 'active'::text);
-- @@ index public.ottoq_proposal_disposition_ledger_run_idx
CREATE INDEX ottoq_proposal_disposition_ledger_run_idx ON public.ottoq_proposal_disposition_ledger USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.ottoq_proposal_disposition_ledger_source_idx
CREATE INDEX ottoq_proposal_disposition_ledger_source_idx ON public.ottoq_proposal_disposition_ledger USING btree (source, disposed_at DESC);
-- @@ index public.ottoq_proposal_disposition_ledger_status_idx
CREATE INDEX ottoq_proposal_disposition_ledger_status_idx ON public.ottoq_proposal_disposition_ledger USING btree (status, source);
-- @@ index public.ottoq_proposal_replay_tick_idx
CREATE INDEX ottoq_proposal_replay_tick_idx ON public.ottoq_proposal_replay USING btree (replay_id, tick_seq);
-- @@ index public.ottoq_proposer_fire_log_run_idx
CREATE INDEX ottoq_proposer_fire_log_run_idx ON public.ottoq_proposer_fire_log USING btree (sim_run_id, fired_at);
-- @@ index public.ottoq_ready_promise_updates_run_idx
CREATE INDEX ottoq_ready_promise_updates_run_idx ON public.ottoq_ready_promise_updates USING btree (sim_run_id, visit_id, estimated_at);
-- @@ index public.ottoq_ready_promises_run_idx
CREATE INDEX ottoq_ready_promises_run_idx ON public.ottoq_ready_promises USING btree (sim_run_id, promised_at);
-- @@ index public.ottoq_recall_refusals_recall_idx
CREATE INDEX ottoq_recall_refusals_recall_idx ON public.ottoq_recall_refusals USING btree (recall_id);
-- @@ index public.ottoq_recall_refusals_run_idx
CREATE INDEX ottoq_recall_refusals_run_idx ON public.ottoq_recall_refusals USING btree (sim_run_id, refused_at_sim);
-- @@ index public.ottoq_recall_refusals_vehicle_idx
CREATE INDEX ottoq_recall_refusals_vehicle_idx ON public.ottoq_recall_refusals USING btree (sim_run_id, vehicle_id, refused_at_sim DESC);
-- @@ index public.ottoq_rider_cleaning_flags_recalled_visit_id_idx
CREATE INDEX ottoq_rider_cleaning_flags_recalled_visit_id_idx ON public.ottoq_rider_cleaning_flags USING btree (recalled_visit_id);
-- @@ index public.ottoq_schema_snapshots_lookup
CREATE INDEX ottoq_schema_snapshots_lookup ON public.ottoq_schema_snapshots USING btree (label, object_kind, object_name);
-- @@ index public.ottoq_site_base_history_stall
CREATE INDEX ottoq_site_base_history_stall ON public.ottoq_site_base_history USING btree (stall_id, valid_until);
-- @@ index public.ottoq_site_power_excursion_ledger_armed_uq
CREATE UNIQUE INDEX ottoq_site_power_excursion_ledger_armed_uq ON public.ottoq_site_power_excursion_ledger USING btree (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)) WHERE (severity_tier = 'armed'::text);
-- @@ index public.ottoq_site_power_excursion_ledger_depot_idx
CREATE INDEX ottoq_site_power_excursion_ledger_depot_idx ON public.ottoq_site_power_excursion_ledger USING btree (depot_id, detected_at DESC);
-- @@ index public.ottoq_site_power_excursion_ledger_run_idx
CREATE INDEX ottoq_site_power_excursion_ledger_run_idx ON public.ottoq_site_power_excursion_ledger USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.ottoq_site_power_excursion_ledger_snapshot_uq
CREATE UNIQUE INDEX ottoq_site_power_excursion_ledger_snapshot_uq ON public.ottoq_site_power_excursion_ledger USING btree (snapshot_id, severity_tier) WHERE (severity_tier <> 'armed'::text);
-- @@ index public.ottoq_site_power_plan_ledger_command_uq
CREATE UNIQUE INDEX ottoq_site_power_plan_ledger_command_uq ON public.ottoq_site_power_plan_ledger USING btree (command_id);
-- @@ index public.ottoq_site_power_plan_ledger_depot_idx
CREATE INDEX ottoq_site_power_plan_ledger_depot_idx ON public.ottoq_site_power_plan_ledger USING btree (depot_id, issued_at DESC);
-- @@ index public.ottoq_space_integrity_ledger_incident_uk
CREATE UNIQUE INDEX ottoq_space_integrity_ledger_incident_uk ON public.ottoq_space_integrity_ledger USING btree (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid), stall_id, expected_vehicle_id, evaluated_at);
-- @@ index public.ottoq_space_integrity_ledger_run_idx
CREATE INDEX ottoq_space_integrity_ledger_run_idx ON public.ottoq_space_integrity_ledger USING btree (sim_run_id, evaluated_at DESC);
-- @@ index public.ottoq_stall_bookings_decision_idx
CREATE INDEX ottoq_stall_bookings_decision_idx ON public.ottoq_stall_bookings USING btree (decision_id) WHERE (decision_id IS NOT NULL);
-- @@ index public.ottoq_stall_bookings_during_idx
CREATE INDEX ottoq_stall_bookings_during_idx ON public.ottoq_stall_bookings USING gist (during) WHERE (state = ANY (ARRAY['held'::text, 'active'::text]));
-- @@ index public.ottoq_stall_bookings_leg_idx
CREATE INDEX ottoq_stall_bookings_leg_idx ON public.ottoq_stall_bookings USING btree (leg_id) WHERE (leg_id IS NOT NULL);
-- @@ index public.ottoq_stall_bookings_live_stall_idx
CREATE INDEX ottoq_stall_bookings_live_stall_idx ON public.ottoq_stall_bookings USING btree (sim_run_id, stall_id) WHERE (state = ANY (ARRAY['held'::text, 'active'::text, 'done'::text, 'interrupted'::text]));
-- @@ index public.ottoq_stall_bookings_run_simclock_idx
CREATE INDEX ottoq_stall_bookings_run_simclock_idx ON public.ottoq_stall_bookings USING btree (sim_run_id, booked_at_sim);
-- @@ index public.ottoq_stall_bookings_vehicle_idx
CREATE INDEX ottoq_stall_bookings_vehicle_idx ON public.ottoq_stall_bookings USING btree (sim_run_id, vehicle_id, state);
-- @@ index public.ottoq_throughput_scores_key_idx
CREATE INDEX ottoq_throughput_scores_key_idx ON public.ottoq_throughput_scores USING btree (scenario_code, random_seed, tick_count);
-- @@ index public.ottoq_throughput_scores_run_idx
CREATE INDEX ottoq_throughput_scores_run_idx ON public.ottoq_throughput_scores USING btree (sim_run_id);
-- @@ index public.ottoq_throughput_sweep_arms_key_idx
CREATE INDEX ottoq_throughput_sweep_arms_key_idx ON public.ottoq_throughput_sweep_arms USING btree (cell_id, seed, replicate, ran_at);
-- @@ index public.ottoq_throughput_sweep_arms_run_idx
CREATE INDEX ottoq_throughput_sweep_arms_run_idx ON public.ottoq_throughput_sweep_arms USING btree (sim_run_id);
-- @@ index public.ottoq_v2_cursors_run
CREATE INDEX ottoq_v2_cursors_run ON public.ottoq_v2_cursors USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.ottoq_v2_inbox_run
CREATE INDEX ottoq_v2_inbox_run ON public.ottoq_v2_inbox USING btree (sim_run_id) WHERE (sim_run_id IS NOT NULL);
-- @@ index public.ottoq_v2_inbox_vehicle_time
CREATE INDEX ottoq_v2_inbox_vehicle_time ON public.ottoq_v2_inbox USING btree (vehicle_id, ce_time DESC);
-- @@ index public.ottoq_v2_signing_keys_one_active
CREATE UNIQUE INDEX ottoq_v2_signing_keys_one_active ON public.ottoq_v2_signing_keys USING btree ((true)) WHERE (retired_at IS NULL);
-- @@ index public.ottoq_vehicle_commands_refused_unreacted
CREATE INDEX ottoq_vehicle_commands_refused_unreacted ON public.ottoq_vehicle_commands USING btree (sim_run_id, issued_at) WHERE ((status = 'refused'::text) AND (reacted_at IS NULL));
-- @@ index public.ottoq_vehicle_itineraries_visit_idx
CREATE INDEX ottoq_vehicle_itineraries_visit_idx ON public.ottoq_vehicle_itineraries USING btree (visit_id) WHERE (visit_id IS NOT NULL);
-- @@ index public.ottoq_vehicle_scout_findings_run_idx
CREATE INDEX ottoq_vehicle_scout_findings_run_idx ON public.ottoq_vehicle_scout_findings USING btree (sim_run_id, finding_id DESC);
-- @@ index public.ottoq_vehicle_scout_findings_scout_idx
CREATE INDEX ottoq_vehicle_scout_findings_scout_idx ON public.ottoq_vehicle_scout_findings USING btree (scout, recorded_at DESC);
-- @@ index public.ottoq_visit_needs_vehicle_visit_run_uk
CREATE UNIQUE INDEX ottoq_visit_needs_vehicle_visit_run_uk ON public.ottoq_visit_needs USING btree (vehicle_id, visit_key, COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid));
-- @@ index public.service_cadence_policy_active_idx
CREATE INDEX service_cadence_policy_active_idx ON public.service_cadence_policy USING btree (is_active, svc);
-- @@ index public.space_conflict_ledger_run_idx
CREATE INDEX space_conflict_ledger_run_idx ON public.space_conflict_ledger USING btree (sim_run_id, recorded_at DESC);
-- @@ index public.space_conflict_ledger_stall_idx
CREATE INDEX space_conflict_ledger_stall_idx ON public.space_conflict_ledger USING btree (stall_id);
-- @@ index public.uniq_ocpp_active_session_per_stall
CREATE UNIQUE INDEX uniq_ocpp_active_session_per_stall ON public.ocpp_sessions USING btree (stall_id) WHERE (status = 'active'::public.ocpp_session_status);
-- @@ index public.uq_action_idempotency
CREATE UNIQUE INDEX uq_action_idempotency ON public.autonomous_action_log USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);
-- @@ index public.uq_varprofile_name
CREATE UNIQUE INDEX uq_varprofile_name ON public.ottoq_variability_profiles USING btree (name);
-- @@ index public.uq_varprofile_run
CREATE UNIQUE INDEX uq_varprofile_run ON public.ottoq_variability_profiles USING btree (sim_run_id);
-- @@ index public.ux_vcards_epoch
CREATE UNIQUE INDEX ux_vcards_epoch ON public.ottoq_variability_cards USING btree (sim_run_id, var_key, scope_instance, bucket_key);
-- @@ index public.vehicle_need_profile_next_deploy_idx
CREATE INDEX vehicle_need_profile_next_deploy_idx ON public.vehicle_need_profile USING btree (next_deploy_at);
-- @@ index public.vehicle_need_profile_run_idx
CREATE INDEX vehicle_need_profile_run_idx ON public.vehicle_need_profile USING btree (drawn_for_run);
-- @@ index public.vehicles_robotic_tether_idx
CREATE INDEX vehicles_robotic_tether_idx ON public.vehicles USING btree (robotic_tether_until) WHERE (robotic_tether_until IS NOT NULL);
-- @@ index twin.arm_cycles_one_open_per_stall
CREATE UNIQUE INDEX arm_cycles_one_open_per_stall ON twin.arm_cycles USING btree (stall_id) WHERE (ended_at IS NULL);
-- @@ index twin.arm_cycles_open_idx
CREATE INDEX arm_cycles_open_idx ON twin.arm_cycles USING btree (sim_run_id, phase_deadline) WHERE (ended_at IS NULL);
-- @@ index twin.arm_cycles_stall_idx
CREATE INDEX arm_cycles_stall_idx ON twin.arm_cycles USING btree (stall_id, started_at DESC);
-- @@ index twin.arm_cycles_vehicle_idx
CREATE INDEX arm_cycles_vehicle_idx ON twin.arm_cycles USING btree (vehicle_id, started_at DESC);
-- @@ index twin.arm_registrations_cycle_idx
CREATE INDEX arm_registrations_cycle_idx ON twin.arm_registrations USING btree (cycle_id, attempt);
-- @@ index twin.arm_registrations_run_idx
CREATE INDEX arm_registrations_run_idx ON twin.arm_registrations USING btree (sim_run_id, at DESC);
-- @@ index twin.arm_registrations_stall_idx
CREATE INDEX arm_registrations_stall_idx ON twin.arm_registrations USING btree (stall_id, at DESC);
