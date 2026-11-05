-- 16_rls.sql: 413 statements, exported from production's catalog
-- @@ rls public.ab_tests
ALTER TABLE public.ab_tests ENABLE ROW LEVEL SECURITY;
-- @@ rls public.accuracy_alerts
ALTER TABLE public.accuracy_alerts ENABLE ROW LEVEL SECURITY;
-- @@ rls public.accuracy_slos
ALTER TABLE public.accuracy_slos ENABLE ROW LEVEL SECURITY;
-- @@ rls public.action_guardrails
ALTER TABLE public.action_guardrails ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ai_decision_log
ALTER TABLE public.ai_decision_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.api_integrations
ALTER TABLE public.api_integrations ENABLE ROW LEVEL SECURITY;
-- @@ rls public.autonomous_action_log
ALTER TABLE public.autonomous_action_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.bay_reservation_reconcile_2026_08_02
ALTER TABLE public.bay_reservation_reconcile_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- @@ rls public.bess_snapshots
ALTER TABLE public.bess_snapshots ENABLE ROW LEVEL SECURITY;
-- @@ rls public.charger_cooldowns
ALTER TABLE public.charger_cooldowns ENABLE ROW LEVEL SECURITY;
-- @@ rls public.charger_health_scores
ALTER TABLE public.charger_health_scores ENABLE ROW LEVEL SECURITY;
-- @@ rls public.cuopt_enactment_proof_2026_08_01
ALTER TABLE public.cuopt_enactment_proof_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- @@ rls public.cuopt_invocation_log
ALTER TABLE public.cuopt_invocation_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.data_quality_errors
ALTER TABLE public.data_quality_errors ENABLE ROW LEVEL SECURITY;
-- @@ rls public.decision_fusion_log
ALTER TABLE public.decision_fusion_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.demand_management_log
ALTER TABLE public.demand_management_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.demand_shaping_plans
ALTER TABLE public.demand_shaping_plans ENABLE ROW LEVEL SECURITY;
-- @@ rls public.depot_state_snapshots
ALTER TABLE public.depot_state_snapshots ENABLE ROW LEVEL SECURITY;
-- @@ rls public.depot_visit_reports
ALTER TABLE public.depot_visit_reports ENABLE ROW LEVEL SECURITY;
-- @@ rls public.depots
ALTER TABLE public.depots ENABLE ROW LEVEL SECURITY;
-- @@ rls public.dispatch_commands
ALTER TABLE public.dispatch_commands ENABLE ROW LEVEL SECURITY;
-- @@ rls public.downstream_action_contracts
ALTER TABLE public.downstream_action_contracts ENABLE ROW LEVEL SECURITY;
-- @@ rls public.early_recall_log
ALTER TABLE public.early_recall_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.emergency_queue_insertions
ALTER TABLE public.emergency_queue_insertions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.engine_config
ALTER TABLE public.engine_config ENABLE ROW LEVEL SECURITY;
-- @@ rls public.exceptions
ALTER TABLE public.exceptions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.external_factor_sources
ALTER TABLE public.external_factor_sources ENABLE ROW LEVEL SECURITY;
-- @@ rls public.external_factors_log
ALTER TABLE public.external_factors_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.fleet_features_daily
ALTER TABLE public.fleet_features_daily ENABLE ROW LEVEL SECURITY;
-- @@ rls public.fleet_operators
ALTER TABLE public.fleet_operators ENABLE ROW LEVEL SECURITY;
-- @@ rls public.integration_health
ALTER TABLE public.integration_health ENABLE ROW LEVEL SECURITY;
-- @@ rls public.maintenance_log
ALTER TABLE public.maintenance_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.maintenance_schedules
ALTER TABLE public.maintenance_schedules ENABLE ROW LEVEL SECURITY;
-- @@ rls public.model_parameters
ALTER TABLE public.model_parameters ENABLE ROW LEVEL SECURITY;
-- @@ rls public.model_tuning_runs
ALTER TABLE public.model_tuning_runs ENABLE ROW LEVEL SECURITY;
-- @@ rls public.model_versions
ALTER TABLE public.model_versions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.notifications
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ocpp_meter_values
ALTER TABLE public.ocpp_meter_values ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ocpp_sessions
ALTER TABLE public.ocpp_sessions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_ab_runs
ALTER TABLE public.ottoq_ab_runs ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_agent_call_ledger
ALTER TABLE public.ottoq_agent_call_ledger ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_agent_charge_orders
ALTER TABLE public.ottoq_agent_charge_orders ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_agent_demo_passcode
ALTER TABLE public.ottoq_agent_demo_passcode ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_agent_pass_evidence
ALTER TABLE public.ottoq_agent_pass_evidence ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_agent_principals
ALTER TABLE public.ottoq_agent_principals ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_agent_prompts
ALTER TABLE public.ottoq_agent_prompts ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_agent_requests
ALTER TABLE public.ottoq_agent_requests ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_anomaly_detectors
ALTER TABLE public.ottoq_anomaly_detectors ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_anomaly_observations
ALTER TABLE public.ottoq_anomaly_observations ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_arbiter_assessments
ALTER TABLE public.ottoq_arbiter_assessments ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_audit_bundles
ALTER TABLE public.ottoq_audit_bundles ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_audit_reports
ALTER TABLE public.ottoq_audit_reports ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_bess_units
ALTER TABLE public.ottoq_bess_units ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_calibration_correlations
ALTER TABLE public.ottoq_calibration_correlations ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_calibration_datasets
ALTER TABLE public.ottoq_calibration_datasets ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_calibration_distributions
ALTER TABLE public.ottoq_calibration_distributions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_calibration_metrics
ALTER TABLE public.ottoq_calibration_metrics ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_calibration_profiles
ALTER TABLE public.ottoq_calibration_profiles ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_canopy_state
ALTER TABLE public.ottoq_canopy_state ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_cert_lineage
ALTER TABLE public.ottoq_cert_lineage ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_channel_health
ALTER TABLE public.ottoq_channel_health ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_charge_clock_fits
ALTER TABLE public.ottoq_charge_clock_fits ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_charge_fault_fits
ALTER TABLE public.ottoq_charge_fault_fits ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_charge_order_attribution
ALTER TABLE public.ottoq_charge_order_attribution ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_charge_order_hindsight
ALTER TABLE public.ottoq_charge_order_hindsight ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_charge_order_reattributions
ALTER TABLE public.ottoq_charge_order_reattributions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_charge_order_regrades
ALTER TABLE public.ottoq_charge_order_regrades ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_charge_order_snapshots
ALTER TABLE public.ottoq_charge_order_snapshots ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_counterfactuals
ALTER TABLE public.ottoq_counterfactuals ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_cuopt_deferrals
ALTER TABLE public.ottoq_cuopt_deferrals ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_data_drift_metrics
ALTER TABLE public.ottoq_data_drift_metrics ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_decision_snapshots
ALTER TABLE public.ottoq_decision_snapshots ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_decisions
ALTER TABLE public.ottoq_decisions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_depot_benchmarks_daily
ALTER TABLE public.ottoq_depot_benchmarks_daily ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_depot_cost_daily
ALTER TABLE public.ottoq_depot_cost_daily ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_dr_calls
ALTER TABLE public.ottoq_dr_calls ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_emergency_invocations
ALTER TABLE public.ottoq_emergency_invocations ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_emergency_protocols
ALTER TABLE public.ottoq_emergency_protocols ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_energy_rates
ALTER TABLE public.ottoq_energy_rates ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_events
ALTER TABLE public.ottoq_events ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_evidence_regimes
ALTER TABLE public.ottoq_evidence_regimes ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_feature_values
ALTER TABLE public.ottoq_feature_values ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_features
ALTER TABLE public.ottoq_features ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_feed_plan_promotions
ALTER TABLE public.ottoq_feed_plan_promotions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_fleet_buildout_active
ALTER TABLE public.ottoq_fleet_buildout_active ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_fleet_buildouts
ALTER TABLE public.ottoq_fleet_buildouts ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_fleet_operator_slas
ALTER TABLE public.ottoq_fleet_operator_slas ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_fn_backup_soc_clamp
ALTER TABLE public.ottoq_fn_backup_soc_clamp ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_grant_boundary_backup
ALTER TABLE public.ottoq_grant_boundary_backup ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_grid_snapshots
ALTER TABLE public.ottoq_grid_snapshots ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_incident_reports
ALTER TABLE public.ottoq_incident_reports ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_inference_log
ALTER TABLE public.ottoq_inference_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_layout_backup_0010_depots
ALTER TABLE public.ottoq_layout_backup_0010_depots ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_layout_backup_0010_stalls
ALTER TABLE public.ottoq_layout_backup_0010_stalls ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_layout_backup_0010_structures
ALTER TABLE public.ottoq_layout_backup_0010_structures ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_layout_backup_0011_stall_bookings
ALTER TABLE public.ottoq_layout_backup_0011_stall_bookings ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_layout_backup_0011_stalls
ALTER TABLE public.ottoq_layout_backup_0011_stalls ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_layout_backup_0011_vehicle_state_log
ALTER TABLE public.ottoq_layout_backup_0011_vehicle_state_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_learned_estimates
ALTER TABLE public.ottoq_learned_estimates ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_margin_prices
ALTER TABLE public.ottoq_margin_prices ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_model_artifacts
ALTER TABLE public.ottoq_model_artifacts ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_model_routes
ALTER TABLE public.ottoq_model_routes ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_oauth_auth_requests
ALTER TABLE public.ottoq_oauth_auth_requests ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_oauth_clients
ALTER TABLE public.ottoq_oauth_clients ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_oauth_device_codes
ALTER TABLE public.ottoq_oauth_device_codes ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_oauth_grants
ALTER TABLE public.ottoq_oauth_grants ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_oauth_tokens
ALTER TABLE public.ottoq_oauth_tokens ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_ocpp_messages
ALTER TABLE public.ottoq_ocpp_messages ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_oem_webhook_log
ALTER TABLE public.ottoq_oem_webhook_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_oem_webhook_patterns
ALTER TABLE public.ottoq_oem_webhook_patterns ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_operation_catalog
ALTER TABLE public.ottoq_operation_catalog ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_owner_accounts
ALTER TABLE public.ottoq_owner_accounts ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_owner_commands
ALTER TABLE public.ottoq_owner_commands ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_owner_settings
ALTER TABLE public.ottoq_owner_settings ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_prediction_accuracy_heatmap
ALTER TABLE public.ottoq_prediction_accuracy_heatmap ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_prediction_rule_links
ALTER TABLE public.ottoq_prediction_rule_links ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_prediction_types_catalog
ALTER TABLE public.ottoq_prediction_types_catalog ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_predictions
ALTER TABLE public.ottoq_predictions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_ready_promise_updates
ALTER TABLE public.ottoq_ready_promise_updates ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_ready_promises
ALTER TABLE public.ottoq_ready_promises ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_recommendations
ALTER TABLE public.ottoq_recommendations ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_research_findings
ALTER TABLE public.ottoq_research_findings ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_retraining_triggers
ALTER TABLE public.ottoq_retraining_triggers ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_rider_cleaning_flags
ALTER TABLE public.ottoq_rider_cleaning_flags ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_rule_evaluations
ALTER TABLE public.ottoq_rule_evaluations ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_rule_overrides
ALTER TABLE public.ottoq_rule_overrides ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_rule_parameters
ALTER TABLE public.ottoq_rule_parameters ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_rules
ALTER TABLE public.ottoq_rules ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_run_archives
ALTER TABLE public.ottoq_run_archives ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_scenarios
ALTER TABLE public.ottoq_scenarios ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_service_detail_records
ALTER TABLE public.ottoq_service_detail_records ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_service_point_capabilities
ALTER TABLE public.ottoq_service_point_capabilities ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_service_tariffs
ALTER TABLE public.ottoq_service_tariffs ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_service_tokens
ALTER TABLE public.ottoq_service_tokens ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_sim_runs
ALTER TABLE public.ottoq_sim_runs ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_sim_scenarios
ALTER TABLE public.ottoq_sim_scenarios ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_site_base_history
ALTER TABLE public.ottoq_site_base_history ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_site_buildout_active
ALTER TABLE public.ottoq_site_buildout_active ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_site_buildouts
ALTER TABLE public.ottoq_site_buildouts ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_site_structures
ALTER TABLE public.ottoq_site_structures ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_sla_conformance_daily
ALTER TABLE public.ottoq_sla_conformance_daily ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_sla_violations
ALTER TABLE public.ottoq_sla_violations ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_solar_output
ALTER TABLE public.ottoq_solar_output ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_specialization_strategies
ALTER TABLE public.ottoq_specialization_strategies ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_tariff_windows
ALTER TABLE public.ottoq_tariff_windows ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_telemetry_packets
ALTER TABLE public.ottoq_telemetry_packets ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_throughput_scores
ALTER TABLE public.ottoq_throughput_scores ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_throughput_sweep_arms
ALTER TABLE public.ottoq_throughput_sweep_arms ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_throughput_sweep_cells
ALTER TABLE public.ottoq_throughput_sweep_cells ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_throughput_sweeps
ALTER TABLE public.ottoq_throughput_sweeps ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_training_runs
ALTER TABLE public.ottoq_training_runs ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_v2_cursors
ALTER TABLE public.ottoq_v2_cursors ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_v2_inbox
ALTER TABLE public.ottoq_v2_inbox ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_v2_signal_ttl
ALTER TABLE public.ottoq_v2_signal_ttl ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_v2_signing_keys
ALTER TABLE public.ottoq_v2_signing_keys ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_variability_catalog
ALTER TABLE public.ottoq_variability_catalog ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_variability_profiles
ALTER TABLE public.ottoq_variability_profiles ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_vehicle_classes
ALTER TABLE public.ottoq_vehicle_classes ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_vehicle_commands
ALTER TABLE public.ottoq_vehicle_commands ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_vehicle_dispatches
ALTER TABLE public.ottoq_vehicle_dispatches ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_vehicle_incidents
ALTER TABLE public.ottoq_vehicle_incidents ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_vehicle_scout_findings
ALTER TABLE public.ottoq_vehicle_scout_findings ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_vehicle_wear
ALTER TABLE public.ottoq_vehicle_wear ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_visit_cost_attribution
ALTER TABLE public.ottoq_visit_cost_attribution ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_wear_tick_status
ALTER TABLE public.ottoq_wear_tick_status ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottoq_weather_snapshots
ALTER TABLE public.ottoq_weather_snapshots ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottow_api_keys
ALTER TABLE public.ottow_api_keys ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottow_dispatch_rules
ALTER TABLE public.ottow_dispatch_rules ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottow_drivers
ALTER TABLE public.ottow_drivers ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottow_mission_events
ALTER TABLE public.ottow_mission_events ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottow_missions
ALTER TABLE public.ottow_missions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.ottow_notifications
ALTER TABLE public.ottow_notifications ENABLE ROW LEVEL SECURITY;
-- @@ rls public.prediction_accuracy_daily
ALTER TABLE public.prediction_accuracy_daily ENABLE ROW LEVEL SECURITY;
-- @@ rls public.prediction_explanations
ALTER TABLE public.prediction_explanations ENABLE ROW LEVEL SECURITY;
-- @@ rls public.prediction_outcomes
ALTER TABLE public.prediction_outcomes ENABLE ROW LEVEL SECURITY;
-- @@ rls public.preimport_depots_site_20260806
ALTER TABLE public.preimport_depots_site_20260806 ENABLE ROW LEVEL SECURITY;
-- @@ rls public.preimport_stalls_20260806
ALTER TABLE public.preimport_stalls_20260806 ENABLE ROW LEVEL SECURITY;
-- @@ rls public.preimport_structures_20260806
ALTER TABLE public.preimport_structures_20260806 ENABLE ROW LEVEL SECURITY;
-- @@ rls public.progression_decisions
ALTER TABLE public.progression_decisions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.retail_members
ALTER TABLE public.retail_members ENABLE ROW LEVEL SECURITY;
-- @@ rls public.schedule_modifications
ALTER TABLE public.schedule_modifications ENABLE ROW LEVEL SECURITY;
-- @@ rls public.schedule_tasks
ALTER TABLE public.schedule_tasks ENABLE ROW LEVEL SECURITY;
-- @@ rls public.service_cadence_policy
ALTER TABLE public.service_cadence_policy ENABLE ROW LEVEL SECURITY;
-- @@ rls public.service_definitions
ALTER TABLE public.service_definitions ENABLE ROW LEVEL SECURITY;
-- @@ rls public.site_energy_snapshots
ALTER TABLE public.site_energy_snapshots ENABLE ROW LEVEL SECURITY;
-- @@ rls public.space_conflict_ledger
ALTER TABLE public.space_conflict_ledger ENABLE ROW LEVEL SECURITY;
-- @@ rls public.staff_users
ALTER TABLE public.staff_users ENABLE ROW LEVEL SECURITY;
-- @@ rls public.stalls
ALTER TABLE public.stalls ENABLE ROW LEVEL SECURITY;
-- @@ rls public.tariff_schedules
ALTER TABLE public.tariff_schedules ENABLE ROW LEVEL SECURITY;
-- @@ rls public.tuning_iterations
ALTER TABLE public.tuning_iterations ENABLE ROW LEVEL SECURITY;
-- @@ rls public.vehicle_need_profile
ALTER TABLE public.vehicle_need_profile ENABLE ROW LEVEL SECURITY;
-- @@ rls public.vehicle_schedules
ALTER TABLE public.vehicle_schedules ENABLE ROW LEVEL SECURITY;
-- @@ rls public.vehicle_state_log
ALTER TABLE public.vehicle_state_log ENABLE ROW LEVEL SECURITY;
-- @@ rls public.vehicle_telemetry
ALTER TABLE public.vehicle_telemetry ENABLE ROW LEVEL SECURITY;
-- @@ rls public.vehicles
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
-- @@ rls public.waves
ALTER TABLE public.waves ENABLE ROW LEVEL SECURITY;
-- @@ rls twin.arm_cycles
ALTER TABLE twin.arm_cycles ENABLE ROW LEVEL SECURITY;
-- @@ rls twin.arm_registrations
ALTER TABLE twin.arm_registrations ENABLE ROW LEVEL SECURITY;
-- @@ rls twin.ottoq_twin_drive_log
ALTER TABLE twin.ottoq_twin_drive_log ENABLE ROW LEVEL SECURITY;
-- @@ rls twin.ottoq_twin_operator_log
ALTER TABLE twin.ottoq_twin_operator_log ENABLE ROW LEVEL SECURITY;
-- @@ rls twin.ottoq_twin_operator_sequences
ALTER TABLE twin.ottoq_twin_operator_sequences ENABLE ROW LEVEL SECURITY;
-- @@ rls twin.ottoq_twin_operator_state
ALTER TABLE twin.ottoq_twin_operator_state ENABLE ROW LEVEL SECURITY;
-- @@ rls twin.ottoq_twin_operators
ALTER TABLE twin.ottoq_twin_operators ENABLE ROW LEVEL SECURITY;
-- @@ policy public.ab_tests."client keys read only"
CREATE POLICY "client keys read only" ON public.ab_tests AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.ab_tests."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.ab_tests AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.accuracy_alerts."client keys read only"
CREATE POLICY "client keys read only" ON public.accuracy_alerts AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.accuracy_alerts."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.accuracy_alerts AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.accuracy_slos."client keys read only"
CREATE POLICY "client keys read only" ON public.accuracy_slos AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.accuracy_slos."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.accuracy_slos AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.action_guardrails."client keys read only"
CREATE POLICY "client keys read only" ON public.action_guardrails AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.action_guardrails."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.action_guardrails AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ai_decision_log."Service role full access"
CREATE POLICY "Service role full access" ON public.ai_decision_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.api_integrations."Service role full access"
CREATE POLICY "Service role full access" ON public.api_integrations AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.autonomous_action_log."client keys read only"
CREATE POLICY "client keys read only" ON public.autonomous_action_log AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.autonomous_action_log."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.autonomous_action_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.bess_snapshots."Service role full access"
CREATE POLICY "Service role full access" ON public.bess_snapshots AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.charger_cooldowns."Service role full access"
CREATE POLICY "Service role full access" ON public.charger_cooldowns AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.charger_health_scores."Service role full access"
CREATE POLICY "Service role full access" ON public.charger_health_scores AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.cuopt_enactment_proof_2026_08_01."service_role full access"
CREATE POLICY "service_role full access" ON public.cuopt_enactment_proof_2026_08_01 AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.cuopt_invocation_log."service_role full access"
CREATE POLICY "service_role full access" ON public.cuopt_invocation_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.data_quality_errors."client keys read only"
CREATE POLICY "client keys read only" ON public.data_quality_errors AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.data_quality_errors."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.data_quality_errors AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.decision_fusion_log."client keys read only"
CREATE POLICY "client keys read only" ON public.decision_fusion_log AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.decision_fusion_log."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.decision_fusion_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.demand_management_log."Service role full access"
CREATE POLICY "Service role full access" ON public.demand_management_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.demand_shaping_plans."Service role full access"
CREATE POLICY "Service role full access" ON public.demand_shaping_plans AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.depot_state_snapshots."client keys read only"
CREATE POLICY "client keys read only" ON public.depot_state_snapshots AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.depot_state_snapshots."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.depot_state_snapshots AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.depot_visit_reports."client keys read only"
CREATE POLICY "client keys read only" ON public.depot_visit_reports AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.depot_visit_reports."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.depot_visit_reports AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.depots."client keys read only"
CREATE POLICY "client keys read only" ON public.depots AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.depots."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.depots AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.dispatch_commands."Fleet operators see own dispatches"
CREATE POLICY "Fleet operators see own dispatches" ON public.dispatch_commands AS PERMISSIVE FOR SELECT TO PUBLIC USING ((vehicle_id IN ( SELECT vehicles.id
   FROM public.vehicles
  WHERE (vehicles.fleet_operator_id = public.get_fleet_operator_id()))));
-- @@ policy public.dispatch_commands."Service role full access"
CREATE POLICY "Service role full access" ON public.dispatch_commands AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.downstream_action_contracts."client keys read only"
CREATE POLICY "client keys read only" ON public.downstream_action_contracts AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.downstream_action_contracts."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.downstream_action_contracts AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.early_recall_log."Service role full access"
CREATE POLICY "Service role full access" ON public.early_recall_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.emergency_queue_insertions."Service role full access"
CREATE POLICY "Service role full access" ON public.emergency_queue_insertions AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.engine_config."Service role full access"
CREATE POLICY "Service role full access" ON public.engine_config AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.exceptions."Fleet operators see own exceptions"
CREATE POLICY "Fleet operators see own exceptions" ON public.exceptions AS PERMISSIVE FOR SELECT TO PUBLIC USING ((vehicle_id IN ( SELECT vehicles.id
   FROM public.vehicles
  WHERE (vehicles.fleet_operator_id = public.get_fleet_operator_id()))));
-- @@ policy public.exceptions."Service role full access"
CREATE POLICY "Service role full access" ON public.exceptions AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.exceptions."Staff see own depot exceptions"
CREATE POLICY "Staff see own depot exceptions" ON public.exceptions AS PERMISSIVE FOR SELECT TO PUBLIC USING ((depot_id = public.get_staff_depot_id()));
-- @@ policy public.external_factor_sources."client keys read only"
CREATE POLICY "client keys read only" ON public.external_factor_sources AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.external_factor_sources."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.external_factor_sources AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.external_factors_log."client keys read only"
CREATE POLICY "client keys read only" ON public.external_factors_log AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.external_factors_log."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.external_factors_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.fleet_features_daily."client keys read only"
CREATE POLICY "client keys read only" ON public.fleet_features_daily AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.fleet_features_daily."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.fleet_features_daily AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.fleet_operators."Service role full access"
CREATE POLICY "Service role full access" ON public.fleet_operators AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.integration_health."Service role full access"
CREATE POLICY "Service role full access" ON public.integration_health AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.maintenance_log."Service role full access"
CREATE POLICY "Service role full access" ON public.maintenance_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.maintenance_schedules."Service role full access"
CREATE POLICY "Service role full access" ON public.maintenance_schedules AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.model_parameters."client keys read only"
CREATE POLICY "client keys read only" ON public.model_parameters AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.model_parameters."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.model_parameters AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.model_tuning_runs."client keys read only"
CREATE POLICY "client keys read only" ON public.model_tuning_runs AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.model_tuning_runs."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.model_tuning_runs AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.model_versions."client keys read only"
CREATE POLICY "client keys read only" ON public.model_versions AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.model_versions."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.model_versions AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.notifications."Fleet operators see own notifications"
CREATE POLICY "Fleet operators see own notifications" ON public.notifications AS PERMISSIVE FOR SELECT TO PUBLIC USING ((fleet_operator_id = public.get_fleet_operator_id()));
-- @@ policy public.notifications."Retail members see own notifications"
CREATE POLICY "Retail members see own notifications" ON public.notifications AS PERMISSIVE FOR SELECT TO PUBLIC USING ((retail_member_id = public.get_retail_member_id()));
-- @@ policy public.notifications."Service role full access"
CREATE POLICY "Service role full access" ON public.notifications AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.notifications."Staff see own depot notifications"
CREATE POLICY "Staff see own depot notifications" ON public.notifications AS PERMISSIVE FOR SELECT TO PUBLIC USING ((staff_user_id IN ( SELECT staff_users.id
   FROM public.staff_users
  WHERE (staff_users.auth_user_id = auth.uid()))));
-- @@ policy public.ocpp_meter_values."Service role full access"
CREATE POLICY "Service role full access" ON public.ocpp_meter_values AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ocpp_sessions."Service role full access"
CREATE POLICY "Service role full access" ON public.ocpp_sessions AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_ab_runs.p_ab_runs_read
CREATE POLICY p_ab_runs_read ON public.ottoq_ab_runs AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_agent_charge_orders.ottoq_agent_charge_orders_read
CREATE POLICY ottoq_agent_charge_orders_read ON public.ottoq_agent_charge_orders AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_anomaly_detectors.detectors_read
CREATE POLICY detectors_read ON public.ottoq_anomaly_detectors AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_anomaly_observations.anomaly_obs_tenant_read
CREATE POLICY anomaly_obs_tenant_read ON public.ottoq_anomaly_observations AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_arbiter_assessments.ottoq_arbiter_assessments_read
CREATE POLICY ottoq_arbiter_assessments_read ON public.ottoq_arbiter_assessments AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_audit_bundles.audit_bundles_tenant_read
CREATE POLICY audit_bundles_tenant_read ON public.ottoq_audit_bundles AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR ((fleet_operator_id IS NOT NULL) AND ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text))))));
-- @@ policy public.ottoq_audit_reports.audit_reports_tenant_read
CREATE POLICY audit_reports_tenant_read ON public.ottoq_audit_reports AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_bess_units.p_bess_units_read
CREATE POLICY p_bess_units_read ON public.ottoq_bess_units AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottoq_bess_units.p_bess_units_write
CREATE POLICY p_bess_units_write ON public.ottoq_bess_units AS PERMISSIVE FOR UPDATE TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_calibration_correlations.calib_corr_read
CREATE POLICY calib_corr_read ON public.ottoq_calibration_correlations AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_calibration_datasets.calib_datasets_read
CREATE POLICY calib_datasets_read ON public.ottoq_calibration_datasets AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_calibration_distributions.calib_dist_read
CREATE POLICY calib_dist_read ON public.ottoq_calibration_distributions AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_calibration_metrics.calib_read
CREATE POLICY calib_read ON public.ottoq_calibration_metrics AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));
-- @@ policy public.ottoq_calibration_profiles.calib_prof_read
CREATE POLICY calib_prof_read ON public.ottoq_calibration_profiles AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_canopy_state.p_canopy_read
CREATE POLICY p_canopy_read ON public.ottoq_canopy_state AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottoq_canopy_state.p_canopy_write
CREATE POLICY p_canopy_write ON public.ottoq_canopy_state AS PERMISSIVE FOR UPDATE TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_charge_clock_fits.ottoq_charge_clock_fits_read
CREATE POLICY ottoq_charge_clock_fits_read ON public.ottoq_charge_clock_fits AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_charge_fault_fits.ottoq_charge_fault_fits_read
CREATE POLICY ottoq_charge_fault_fits_read ON public.ottoq_charge_fault_fits AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_charge_order_attribution.ottoq_charge_order_attribution_read
CREATE POLICY ottoq_charge_order_attribution_read ON public.ottoq_charge_order_attribution AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_charge_order_hindsight.ottoq_charge_order_hindsight_read
CREATE POLICY ottoq_charge_order_hindsight_read ON public.ottoq_charge_order_hindsight AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_charge_order_reattributions.ottoq_charge_order_reattributions_read
CREATE POLICY ottoq_charge_order_reattributions_read ON public.ottoq_charge_order_reattributions AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_charge_order_regrades.ottoq_charge_order_regrades_read
CREATE POLICY ottoq_charge_order_regrades_read ON public.ottoq_charge_order_regrades AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_charge_order_snapshots.ottoq_charge_order_snapshots_read
CREATE POLICY ottoq_charge_order_snapshots_read ON public.ottoq_charge_order_snapshots AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_counterfactuals.counterfactuals_tenant_read
CREATE POLICY counterfactuals_tenant_read ON public.ottoq_counterfactuals AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_cuopt_deferrals."Service role full access"
CREATE POLICY "Service role full access" ON public.ottoq_cuopt_deferrals AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_data_drift_metrics.drift_read
CREATE POLICY drift_read ON public.ottoq_data_drift_metrics AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_decision_snapshots.p_decision_snapshots_read
CREATE POLICY p_decision_snapshots_read ON public.ottoq_decision_snapshots AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_decisions.p_decisions_read
CREATE POLICY p_decisions_read ON public.ottoq_decisions AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_depot_benchmarks_daily.benchmarks_read
CREATE POLICY benchmarks_read ON public.ottoq_depot_benchmarks_daily AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));
-- @@ policy public.ottoq_depot_cost_daily.depot_cost_read
CREATE POLICY depot_cost_read ON public.ottoq_depot_cost_daily AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = 'service_role'::text));
-- @@ policy public.ottoq_dr_calls.p_dr_calls_read
CREATE POLICY p_dr_calls_read ON public.ottoq_dr_calls AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottoq_emergency_invocations.emergency_invocations_read
CREATE POLICY emergency_invocations_read ON public.ottoq_emergency_invocations AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));
-- @@ policy public.ottoq_emergency_protocols.emergency_protocols_read
CREATE POLICY emergency_protocols_read ON public.ottoq_emergency_protocols AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_energy_rates.ottoq_energy_rates_read
CREATE POLICY ottoq_energy_rates_read ON public.ottoq_energy_rates AS PERMISSIVE FOR SELECT TO authenticated, service_role USING (true);
-- @@ policy public.ottoq_events."client keys read only"
CREATE POLICY "client keys read only" ON public.ottoq_events AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.ottoq_events."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.ottoq_events AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_events.ottoq_events_service_role_all
CREATE POLICY ottoq_events_service_role_all ON public.ottoq_events AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = 'service_role'::text));
-- @@ policy public.ottoq_events.ottoq_events_tenant_select
CREATE POLICY ottoq_events_tenant_select ON public.ottoq_events AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'authenticated'::text) AND ((fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text))))));
-- @@ policy public.ottoq_evidence_regimes.ottoq_evidence_regimes_read
CREATE POLICY ottoq_evidence_regimes_read ON public.ottoq_evidence_regimes AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_feature_values.feature_values_tenant_read
CREATE POLICY feature_values_tenant_read ON public.ottoq_feature_values AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_features.features_read
CREATE POLICY features_read ON public.ottoq_features AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_feed_plan_promotions.ottoq_feed_plan_promotions_service
CREATE POLICY ottoq_feed_plan_promotions_service ON public.ottoq_feed_plan_promotions AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_fleet_buildouts.ottoq_fleet_buildouts_read
CREATE POLICY ottoq_fleet_buildouts_read ON public.ottoq_fleet_buildouts AS PERMISSIVE FOR SELECT TO authenticated, service_role USING (true);
-- @@ policy public.ottoq_fleet_operator_slas.slas_tenant_select
CREATE POLICY slas_tenant_select ON public.ottoq_fleet_operator_slas AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_grid_snapshots.p_grid_snap_read
CREATE POLICY p_grid_snap_read ON public.ottoq_grid_snapshots AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottoq_incident_reports.incident_reports_tenant_read
CREATE POLICY incident_reports_tenant_read ON public.ottoq_incident_reports AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_inference_log.inference_log_tenant_read
CREATE POLICY inference_log_tenant_read ON public.ottoq_inference_log AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_learned_estimates.ottoq_learned_estimates_read
CREATE POLICY ottoq_learned_estimates_read ON public.ottoq_learned_estimates AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
-- @@ policy public.ottoq_margin_prices.ottoq_margin_prices_read
CREATE POLICY ottoq_margin_prices_read ON public.ottoq_margin_prices AS PERMISSIVE FOR SELECT TO authenticated, service_role USING (true);
-- @@ policy public.ottoq_model_artifacts.model_artifacts_read
CREATE POLICY model_artifacts_read ON public.ottoq_model_artifacts AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_model_routes.model_routes_read
CREATE POLICY model_routes_read ON public.ottoq_model_routes AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_ocpp_messages.ocpp_msgs_read
CREATE POLICY ocpp_msgs_read ON public.ottoq_ocpp_messages AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));
-- @@ policy public.ottoq_oem_webhook_log.p_webhook_log_admin_read
CREATE POLICY p_webhook_log_admin_read ON public.ottoq_oem_webhook_log AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottoq_oem_webhook_log.p_webhook_log_service_write
CREATE POLICY p_webhook_log_service_write ON public.ottoq_oem_webhook_log AS PERMISSIVE FOR INSERT TO service_role WITH CHECK (true);
-- @@ policy public.ottoq_oem_webhook_patterns.p_webhook_patterns_read
CREATE POLICY p_webhook_patterns_read ON public.ottoq_oem_webhook_patterns AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottoq_prediction_accuracy_heatmap.pred_accuracy_tenant_read
CREATE POLICY pred_accuracy_tenant_read ON public.ottoq_prediction_accuracy_heatmap AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_prediction_rule_links.pred_rule_links_read
CREATE POLICY pred_rule_links_read ON public.ottoq_prediction_rule_links AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_prediction_types_catalog.pred_types_read
CREATE POLICY pred_types_read ON public.ottoq_prediction_types_catalog AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_predictions."Service role full access"
CREATE POLICY "Service role full access" ON public.ottoq_predictions AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_recommendations.recs_tenant_read
CREATE POLICY recs_tenant_read ON public.ottoq_recommendations AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_retraining_triggers.retrain_triggers_read
CREATE POLICY retrain_triggers_read ON public.ottoq_retraining_triggers AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_rider_cleaning_flags.rcf_service_role_all
CREATE POLICY rcf_service_role_all ON public.ottoq_rider_cleaning_flags AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_rule_evaluations.ottoq_evals_tenant_read
CREATE POLICY ottoq_evals_tenant_read ON public.ottoq_rule_evaluations AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_rule_overrides.ottoq_overrides_tenant_read
CREATE POLICY ottoq_overrides_tenant_read ON public.ottoq_rule_overrides AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_rule_parameters.ottoq_rule_params_read
CREATE POLICY ottoq_rule_params_read ON public.ottoq_rule_parameters AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR ((scope_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_rules.ottoq_rules_read
CREATE POLICY ottoq_rules_read ON public.ottoq_rules AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_run_archives."service_role full access"
CREATE POLICY "service_role full access" ON public.ottoq_run_archives AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_scenarios.scenarios_read
CREATE POLICY scenarios_read ON public.ottoq_scenarios AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_sim_runs.sim_runs_read
CREATE POLICY sim_runs_read ON public.ottoq_sim_runs AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));
-- @@ policy public.ottoq_sim_scenarios.p_scenarios_read
CREATE POLICY p_scenarios_read ON public.ottoq_sim_scenarios AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottoq_site_base_history.ottoq_site_base_history_read
CREATE POLICY ottoq_site_base_history_read ON public.ottoq_site_base_history AS PERMISSIVE FOR SELECT TO authenticated, service_role USING (true);
-- @@ policy public.ottoq_site_buildouts.ottoq_site_buildouts_read
CREATE POLICY ottoq_site_buildouts_read ON public.ottoq_site_buildouts AS PERMISSIVE FOR SELECT TO authenticated, service_role USING (true);
-- @@ policy public.ottoq_site_structures.site_structures_read
CREATE POLICY site_structures_read ON public.ottoq_site_structures AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_sla_conformance_daily.sla_conf_tenant_read
CREATE POLICY sla_conf_tenant_read ON public.ottoq_sla_conformance_daily AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_sla_violations.sla_viol_tenant_read
CREATE POLICY sla_viol_tenant_read ON public.ottoq_sla_violations AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_solar_output.p_solar_read
CREATE POLICY p_solar_read ON public.ottoq_solar_output AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottoq_specialization_strategies.specialization_read
CREATE POLICY specialization_read ON public.ottoq_specialization_strategies AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_tariff_windows.p_tariff_read
CREATE POLICY p_tariff_read ON public.ottoq_tariff_windows AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottoq_telemetry_packets.telem_packets_read
CREATE POLICY telem_packets_read ON public.ottoq_telemetry_packets AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));
-- @@ policy public.ottoq_throughput_scores.ottoq_throughput_scores_read
CREATE POLICY ottoq_throughput_scores_read ON public.ottoq_throughput_scores AS PERMISSIVE FOR SELECT TO authenticated, service_role USING (true);
-- @@ policy public.ottoq_throughput_sweep_arms.ottoq_throughput_sweep_arms_read
CREATE POLICY ottoq_throughput_sweep_arms_read ON public.ottoq_throughput_sweep_arms AS PERMISSIVE FOR SELECT TO authenticated, service_role USING (true);
-- @@ policy public.ottoq_throughput_sweep_cells.ottoq_throughput_sweep_cells_read
CREATE POLICY ottoq_throughput_sweep_cells_read ON public.ottoq_throughput_sweep_cells AS PERMISSIVE FOR SELECT TO authenticated, service_role USING (true);
-- @@ policy public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_read
CREATE POLICY ottoq_throughput_sweeps_read ON public.ottoq_throughput_sweeps AS PERMISSIVE FOR SELECT TO authenticated, service_role USING (true);
-- @@ policy public.ottoq_training_runs.training_runs_read
CREATE POLICY training_runs_read ON public.ottoq_training_runs AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));
-- @@ policy public.ottoq_variability_catalog.p_varcat_read
CREATE POLICY p_varcat_read ON public.ottoq_variability_catalog AS PERMISSIVE FOR SELECT TO authenticated, anon USING (true);
-- @@ policy public.ottoq_variability_profiles.p_varprofile_read
CREATE POLICY p_varprofile_read ON public.ottoq_variability_profiles AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottoq_variability_profiles.p_varprofile_write
CREATE POLICY p_varprofile_write ON public.ottoq_variability_profiles AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_vehicle_classes.vehicle_classes_read
CREATE POLICY vehicle_classes_read ON public.ottoq_vehicle_classes AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));
-- @@ policy public.ottoq_vehicle_commands."Depot staff read own depot commands"
CREATE POLICY "Depot staff read own depot commands" ON public.ottoq_vehicle_commands AS PERMISSIVE FOR SELECT TO authenticated USING ((depot_id = ( SELECT public.get_staff_depot_id() AS get_staff_depot_id)));
-- @@ policy public.ottoq_vehicle_commands."retired 0647: client keys read commands"
CREATE POLICY "retired 0647: client keys read commands" ON public.ottoq_vehicle_commands AS PERMISSIVE FOR SELECT TO service_role USING (true);
-- @@ policy public.ottoq_vehicle_commands."service_role writes commands"
CREATE POLICY "service_role writes commands" ON public.ottoq_vehicle_commands AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottoq_vehicle_dispatches.dispatches_read
CREATE POLICY dispatches_read ON public.ottoq_vehicle_dispatches AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));
-- @@ policy public.ottoq_vehicle_incidents.incidents_read
CREATE POLICY incidents_read ON public.ottoq_vehicle_incidents AS PERMISSIVE FOR SELECT TO PUBLIC USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));
-- @@ policy public.ottoq_visit_cost_attribution.visit_cost_tenant_read
CREATE POLICY visit_cost_tenant_read ON public.ottoq_visit_cost_attribution AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));
-- @@ policy public.ottoq_weather_snapshots.p_weather_read
CREATE POLICY p_weather_read ON public.ottoq_weather_snapshots AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.ottow_api_keys."Service role full access on ottow_api_keys"
CREATE POLICY "Service role full access on ottow_api_keys" ON public.ottow_api_keys AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottow_dispatch_rules."Service role full access on ottow_dispatch_rules"
CREATE POLICY "Service role full access on ottow_dispatch_rules" ON public.ottow_dispatch_rules AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottow_drivers."Drivers can view own record"
CREATE POLICY "Drivers can view own record" ON public.ottow_drivers AS PERMISSIVE FOR SELECT TO PUBLIC USING (((staff_user_id = auth.uid()) OR (auth.role() = 'service_role'::text)));
-- @@ policy public.ottow_drivers."client keys read only"
CREATE POLICY "client keys read only" ON public.ottow_drivers AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.ottow_drivers."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.ottow_drivers AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottow_mission_events."Authenticated users can view mission events"
CREATE POLICY "Authenticated users can view mission events" ON public.ottow_mission_events AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (mission_id IN ( SELECT m.id
   FROM (public.ottow_missions m
     JOIN public.staff_users s ON ((s.depot_id = m.depot_id)))
  WHERE (s.auth_user_id = auth.uid())))));
-- @@ policy public.ottow_mission_events."client keys read only"
CREATE POLICY "client keys read only" ON public.ottow_mission_events AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.ottow_mission_events."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.ottow_mission_events AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottow_missions."Authenticated users can view depot missions"
CREATE POLICY "Authenticated users can view depot missions" ON public.ottow_missions AS PERMISSIVE FOR SELECT TO PUBLIC USING (((auth.role() = 'service_role'::text) OR (depot_id IN ( SELECT staff_users.depot_id
   FROM public.staff_users
  WHERE (staff_users.auth_user_id = auth.uid())))));
-- @@ policy public.ottow_missions."client keys read only"
CREATE POLICY "client keys read only" ON public.ottow_missions AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.ottow_missions."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.ottow_missions AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.ottow_notifications."Service role full access on ottow_notifications"
CREATE POLICY "Service role full access on ottow_notifications" ON public.ottow_notifications AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.prediction_accuracy_daily."client keys read only"
CREATE POLICY "client keys read only" ON public.prediction_accuracy_daily AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.prediction_accuracy_daily."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.prediction_accuracy_daily AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.prediction_explanations."client keys read only"
CREATE POLICY "client keys read only" ON public.prediction_explanations AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.prediction_explanations."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.prediction_explanations AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.prediction_outcomes."client keys read only"
CREATE POLICY "client keys read only" ON public.prediction_outcomes AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.prediction_outcomes."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.prediction_outcomes AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.progression_decisions."client keys read only"
CREATE POLICY "client keys read only" ON public.progression_decisions AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.progression_decisions."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.progression_decisions AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.retail_members."Service role full access"
CREATE POLICY "Service role full access" ON public.retail_members AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.schedule_modifications."Service role full access"
CREATE POLICY "Service role full access" ON public.schedule_modifications AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.schedule_tasks."Fleet operators see own tasks"
CREATE POLICY "Fleet operators see own tasks" ON public.schedule_tasks AS PERMISSIVE FOR SELECT TO PUBLIC USING ((vehicle_id IN ( SELECT vehicles.id
   FROM public.vehicles
  WHERE (vehicles.fleet_operator_id = public.get_fleet_operator_id()))));
-- @@ policy public.schedule_tasks."Service role full access"
CREATE POLICY "Service role full access" ON public.schedule_tasks AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.schedule_tasks."Staff see own depot tasks"
CREATE POLICY "Staff see own depot tasks" ON public.schedule_tasks AS PERMISSIVE FOR SELECT TO PUBLIC USING ((depot_id = public.get_staff_depot_id()));
-- @@ policy public.service_cadence_policy.service_cadence_policy_service_role
CREATE POLICY service_cadence_policy_service_role ON public.service_cadence_policy AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.service_definitions."Service role full access"
CREATE POLICY "Service role full access" ON public.service_definitions AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.site_energy_snapshots."Service role full access"
CREATE POLICY "Service role full access" ON public.site_energy_snapshots AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.site_energy_snapshots.p_site_energy_read
CREATE POLICY p_site_energy_read ON public.site_energy_snapshots AS PERMISSIVE FOR SELECT TO authenticated USING (true);
-- @@ policy public.space_conflict_ledger.space_conflict_ledger_service_role
CREATE POLICY space_conflict_ledger_service_role ON public.space_conflict_ledger AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.staff_users."Service role full access"
CREATE POLICY "Service role full access" ON public.staff_users AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.staff_users."Staff read own record"
CREATE POLICY "Staff read own record" ON public.staff_users AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_user_id = auth.uid()));
-- @@ policy public.stalls."Staff see own depot stalls"
CREATE POLICY "Staff see own depot stalls" ON public.stalls AS PERMISSIVE FOR SELECT TO PUBLIC USING ((depot_id = public.get_staff_depot_id()));
-- @@ policy public.stalls."client keys read only"
CREATE POLICY "client keys read only" ON public.stalls AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.stalls."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.stalls AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.tariff_schedules."Service role full access"
CREATE POLICY "Service role full access" ON public.tariff_schedules AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.tuning_iterations."client keys read only"
CREATE POLICY "client keys read only" ON public.tuning_iterations AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy public.tuning_iterations."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.tuning_iterations AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.vehicle_need_profile."vehicle_need_profile service role"
CREATE POLICY "vehicle_need_profile service role" ON public.vehicle_need_profile AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.vehicle_schedules."Fleet operators see own schedules"
CREATE POLICY "Fleet operators see own schedules" ON public.vehicle_schedules AS PERMISSIVE FOR SELECT TO PUBLIC USING ((vehicle_id IN ( SELECT vehicles.id
   FROM public.vehicles
  WHERE (vehicles.fleet_operator_id = public.get_fleet_operator_id()))));
-- @@ policy public.vehicle_schedules."Retail members see own schedules"
CREATE POLICY "Retail members see own schedules" ON public.vehicle_schedules AS PERMISSIVE FOR SELECT TO PUBLIC USING ((vehicle_id IN ( SELECT vehicles.id
   FROM public.vehicles
  WHERE (vehicles.retail_member_id = public.get_retail_member_id()))));
-- @@ policy public.vehicle_schedules."Service role full access"
CREATE POLICY "Service role full access" ON public.vehicle_schedules AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.vehicle_state_log."Service role full access"
CREATE POLICY "Service role full access" ON public.vehicle_state_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.vehicle_telemetry."Service role full access"
CREATE POLICY "Service role full access" ON public.vehicle_telemetry AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.vehicles."Fleet operators see own vehicles"
CREATE POLICY "Fleet operators see own vehicles" ON public.vehicles AS PERMISSIVE FOR SELECT TO authenticated USING ((fleet_operator_id = ( SELECT public.get_fleet_operator_id() AS get_fleet_operator_id)));
-- @@ policy public.vehicles."Retail members see own vehicles"
CREATE POLICY "Retail members see own vehicles" ON public.vehicles AS PERMISSIVE FOR SELECT TO PUBLIC USING ((retail_member_id = public.get_retail_member_id()));
-- @@ policy public.vehicles."Staff see own depot vehicles"
CREATE POLICY "Staff see own depot vehicles" ON public.vehicles AS PERMISSIVE FOR SELECT TO PUBLIC USING (((current_depot_id = public.get_staff_depot_id()) OR (home_depot_id = public.get_staff_depot_id())));
-- @@ policy public.vehicles."retired 0647: client keys read only"
CREATE POLICY "retired 0647: client keys read only" ON public.vehicles AS PERMISSIVE FOR SELECT TO service_role USING (true);
-- @@ policy public.vehicles."service_role writes world state"
CREATE POLICY "service_role writes world state" ON public.vehicles AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy public.waves."Service role full access"
CREATE POLICY "Service role full access" ON public.waves AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy twin.arm_cycles.arm_cycles_read_only
CREATE POLICY arm_cycles_read_only ON twin.arm_cycles AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy twin.arm_cycles.arm_cycles_service_role_all
CREATE POLICY arm_cycles_service_role_all ON twin.arm_cycles AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
-- @@ policy twin.arm_registrations.arm_registrations_read_only
CREATE POLICY arm_registrations_read_only ON twin.arm_registrations AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
-- @@ policy twin.arm_registrations.arm_registrations_service_role_all
CREATE POLICY arm_registrations_service_role_all ON twin.arm_registrations AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
