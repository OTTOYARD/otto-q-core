-- 12_constraints_fk.sql: 345 statements, exported from production's catalog
-- @@ constraint_f public.ab_tests.ab_tests_depot_id_fkey
ALTER TABLE ONLY public.ab_tests ADD CONSTRAINT ab_tests_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ab_tests.ab_tests_variant_a_version_id_fkey
ALTER TABLE ONLY public.ab_tests ADD CONSTRAINT ab_tests_variant_a_version_id_fkey FOREIGN KEY (variant_a_version_id) REFERENCES public.model_versions(id);
-- @@ constraint_f public.ab_tests.ab_tests_variant_b_version_id_fkey
ALTER TABLE ONLY public.ab_tests ADD CONSTRAINT ab_tests_variant_b_version_id_fkey FOREIGN KEY (variant_b_version_id) REFERENCES public.model_versions(id);
-- @@ constraint_f public.ab_tests.ab_tests_winner_version_id_fkey
ALTER TABLE ONLY public.ab_tests ADD CONSTRAINT ab_tests_winner_version_id_fkey FOREIGN KEY (winner_version_id) REFERENCES public.model_versions(id);
-- @@ constraint_f public.accuracy_alerts.accuracy_alerts_depot_id_fkey
ALTER TABLE ONLY public.accuracy_alerts ADD CONSTRAINT accuracy_alerts_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.accuracy_alerts.accuracy_alerts_slo_id_fkey
ALTER TABLE ONLY public.accuracy_alerts ADD CONSTRAINT accuracy_alerts_slo_id_fkey FOREIGN KEY (slo_id) REFERENCES public.accuracy_slos(id) ON DELETE CASCADE;
-- @@ constraint_f public.accuracy_slos.accuracy_slos_depot_id_fkey
ALTER TABLE ONLY public.accuracy_slos ADD CONSTRAINT accuracy_slos_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.action_guardrails.action_guardrails_depot_id_fkey
ALTER TABLE ONLY public.action_guardrails ADD CONSTRAINT action_guardrails_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ai_decision_log.ai_decision_log_depot_id_fkey
ALTER TABLE ONLY public.ai_decision_log ADD CONSTRAINT ai_decision_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ai_decision_log.ai_decision_log_vehicle_id_fkey
ALTER TABLE ONLY public.ai_decision_log ADD CONSTRAINT ai_decision_log_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.api_integrations.api_integrations_depot_id_fkey
ALTER TABLE ONLY public.api_integrations ADD CONSTRAINT api_integrations_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.api_integrations.api_integrations_fleet_operator_id_fkey
ALTER TABLE ONLY public.api_integrations ADD CONSTRAINT api_integrations_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id);
-- @@ constraint_f public.autonomous_action_log.autonomous_action_log_ab_test_id_fkey
ALTER TABLE ONLY public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_ab_test_id_fkey FOREIGN KEY (ab_test_id) REFERENCES public.ab_tests(id) ON DELETE SET NULL;
-- @@ constraint_f public.autonomous_action_log.autonomous_action_log_contract_id_fkey
ALTER TABLE ONLY public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.downstream_action_contracts(id) ON DELETE SET NULL;
-- @@ constraint_f public.autonomous_action_log.autonomous_action_log_depot_id_fkey
ALTER TABLE ONLY public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.autonomous_action_log.autonomous_action_log_fusion_log_id_fkey
ALTER TABLE ONLY public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_fusion_log_id_fkey FOREIGN KEY (fusion_log_id) REFERENCES public.decision_fusion_log(id) ON DELETE SET NULL;
-- @@ constraint_f public.autonomous_action_log.autonomous_action_log_prediction_id_fkey
ALTER TABLE ONLY public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_prediction_id_fkey FOREIGN KEY (prediction_id) REFERENCES public.ottoq_predictions(id) ON DELETE SET NULL;
-- @@ constraint_f public.bess_snapshots.bess_snapshots_depot_id_fkey
ALTER TABLE ONLY public.bess_snapshots ADD CONSTRAINT bess_snapshots_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.charger_cooldowns.charger_cooldowns_depot_id_fkey
ALTER TABLE ONLY public.charger_cooldowns ADD CONSTRAINT charger_cooldowns_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.charger_cooldowns.charger_cooldowns_last_session_id_fkey
ALTER TABLE ONLY public.charger_cooldowns ADD CONSTRAINT charger_cooldowns_last_session_id_fkey FOREIGN KEY (last_session_id) REFERENCES public.ocpp_sessions(id);
-- @@ constraint_f public.charger_cooldowns.charger_cooldowns_stall_id_fkey
ALTER TABLE ONLY public.charger_cooldowns ADD CONSTRAINT charger_cooldowns_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES public.stalls(id) ON DELETE CASCADE;
-- @@ constraint_f public.charger_health_scores.charger_health_scores_depot_id_fkey
ALTER TABLE ONLY public.charger_health_scores ADD CONSTRAINT charger_health_scores_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.charger_health_scores.charger_health_scores_stall_id_fkey
ALTER TABLE ONLY public.charger_health_scores ADD CONSTRAINT charger_health_scores_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES public.stalls(id) ON DELETE CASCADE;
-- @@ constraint_f public.cuopt_invocation_log.fk_cuopt_invocation_log_sim_run
ALTER TABLE ONLY public.cuopt_invocation_log ADD CONSTRAINT fk_cuopt_invocation_log_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.data_quality_errors.data_quality_errors_depot_id_fkey
ALTER TABLE ONLY public.data_quality_errors ADD CONSTRAINT data_quality_errors_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.decision_fusion_log.decision_fusion_log_depot_id_fkey
ALTER TABLE ONLY public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.decision_fusion_log.decision_fusion_log_emitted_action_id_fkey
ALTER TABLE ONLY public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_emitted_action_id_fkey FOREIGN KEY (emitted_action_id) REFERENCES public.autonomous_action_log(id) ON DELETE SET NULL;
-- @@ constraint_f public.decision_fusion_log.decision_fusion_log_emitted_prediction_id_fkey
ALTER TABLE ONLY public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_emitted_prediction_id_fkey FOREIGN KEY (emitted_prediction_id) REFERENCES public.ottoq_predictions(id) ON DELETE SET NULL;
-- @@ constraint_f public.demand_management_log.demand_management_log_depot_id_fkey
ALTER TABLE ONLY public.demand_management_log ADD CONSTRAINT demand_management_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.demand_shaping_plans.demand_shaping_plans_depot_id_fkey
ALTER TABLE ONLY public.demand_shaping_plans ADD CONSTRAINT demand_shaping_plans_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.depot_state_snapshots.depot_state_snapshots_depot_id_fkey
ALTER TABLE ONLY public.depot_state_snapshots ADD CONSTRAINT depot_state_snapshots_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.depot_visit_reports.depot_visit_reports_depot_id_fkey
ALTER TABLE ONLY public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.depot_visit_reports.depot_visit_reports_fleet_operator_id_fkey
ALTER TABLE ONLY public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.depot_visit_reports.depot_visit_reports_schedule_id_fkey
ALTER TABLE ONLY public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES public.vehicle_schedules(id) ON DELETE CASCADE;
-- @@ constraint_f public.depot_visit_reports.depot_visit_reports_vehicle_id_fkey
ALTER TABLE ONLY public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.dispatch_commands.dispatch_commands_depot_id_fkey
ALTER TABLE ONLY public.dispatch_commands ADD CONSTRAINT dispatch_commands_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.dispatch_commands.dispatch_commands_destination_stall_id_fkey
ALTER TABLE ONLY public.dispatch_commands ADD CONSTRAINT dispatch_commands_destination_stall_id_fkey FOREIGN KEY (destination_stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.dispatch_commands.dispatch_commands_retry_of_id_fkey
ALTER TABLE ONLY public.dispatch_commands ADD CONSTRAINT dispatch_commands_retry_of_id_fkey FOREIGN KEY (retry_of_id) REFERENCES public.dispatch_commands(id);
-- @@ constraint_f public.dispatch_commands.dispatch_commands_vehicle_id_fkey
ALTER TABLE ONLY public.dispatch_commands ADD CONSTRAINT dispatch_commands_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.early_recall_log.early_recall_log_affected_wave_id_fkey
ALTER TABLE ONLY public.early_recall_log ADD CONSTRAINT early_recall_log_affected_wave_id_fkey FOREIGN KEY (affected_wave_id) REFERENCES public.waves(id);
-- @@ constraint_f public.early_recall_log.early_recall_log_depot_id_fkey
ALTER TABLE ONLY public.early_recall_log ADD CONSTRAINT early_recall_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.early_recall_log.early_recall_log_vehicle_id_fkey
ALTER TABLE ONLY public.early_recall_log ADD CONSTRAINT early_recall_log_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.early_recall_log.early_recall_log_vehicle_schedule_id_fkey
ALTER TABLE ONLY public.early_recall_log ADD CONSTRAINT early_recall_log_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES public.vehicle_schedules(id);
-- @@ constraint_f public.emergency_queue_insertions.emergency_queue_insertions_assigned_stall_id_fkey
ALTER TABLE ONLY public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_assigned_stall_id_fkey FOREIGN KEY (assigned_stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.emergency_queue_insertions.emergency_queue_insertions_assigned_wave_id_fkey
ALTER TABLE ONLY public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_assigned_wave_id_fkey FOREIGN KEY (assigned_wave_id) REFERENCES public.waves(id);
-- @@ constraint_f public.emergency_queue_insertions.emergency_queue_insertions_depot_id_fkey
ALTER TABLE ONLY public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.emergency_queue_insertions.emergency_queue_insertions_vehicle_id_fkey
ALTER TABLE ONLY public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.emergency_queue_insertions.emergency_queue_insertions_vehicle_schedule_id_fkey
ALTER TABLE ONLY public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES public.vehicle_schedules(id);
-- @@ constraint_f public.engine_config.engine_config_depot_id_fkey
ALTER TABLE ONLY public.engine_config ADD CONSTRAINT engine_config_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.exceptions.exceptions_depot_id_fkey
ALTER TABLE ONLY public.exceptions ADD CONSTRAINT exceptions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.exceptions.exceptions_schedule_task_id_fkey
ALTER TABLE ONLY public.exceptions ADD CONSTRAINT exceptions_schedule_task_id_fkey FOREIGN KEY (schedule_task_id) REFERENCES public.schedule_tasks(id);
-- @@ constraint_f public.exceptions.exceptions_sim_run_id_fkey
ALTER TABLE ONLY public.exceptions ADD CONSTRAINT exceptions_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.exceptions.exceptions_stall_id_fkey
ALTER TABLE ONLY public.exceptions ADD CONSTRAINT exceptions_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.exceptions.exceptions_vehicle_id_fkey
ALTER TABLE ONLY public.exceptions ADD CONSTRAINT exceptions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.exceptions.exceptions_vehicle_schedule_id_fkey
ALTER TABLE ONLY public.exceptions ADD CONSTRAINT exceptions_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES public.vehicle_schedules(id);
-- @@ constraint_f public.external_factor_sources.external_factor_sources_depot_id_fkey
ALTER TABLE ONLY public.external_factor_sources ADD CONSTRAINT external_factor_sources_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.external_factors_log.external_factors_log_depot_id_fkey
ALTER TABLE ONLY public.external_factors_log ADD CONSTRAINT external_factors_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.external_factors_log.external_factors_log_source_id_fkey
ALTER TABLE ONLY public.external_factors_log ADD CONSTRAINT external_factors_log_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.external_factor_sources(id) ON DELETE CASCADE;
-- @@ constraint_f public.external_factors_log.external_factors_log_supersedes_id_fkey
ALTER TABLE ONLY public.external_factors_log ADD CONSTRAINT external_factors_log_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES public.external_factors_log(id) ON DELETE SET NULL;
-- @@ constraint_f public.maintenance_log.maintenance_log_depot_id_fkey
ALTER TABLE ONLY public.maintenance_log ADD CONSTRAINT maintenance_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.maintenance_log.maintenance_log_maintenance_schedule_id_fkey
ALTER TABLE ONLY public.maintenance_log ADD CONSTRAINT maintenance_log_maintenance_schedule_id_fkey FOREIGN KEY (maintenance_schedule_id) REFERENCES public.maintenance_schedules(id);
-- @@ constraint_f public.maintenance_log.maintenance_log_stall_id_fkey
ALTER TABLE ONLY public.maintenance_log ADD CONSTRAINT maintenance_log_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.maintenance_log.maintenance_log_vehicle_id_fkey
ALTER TABLE ONLY public.maintenance_log ADD CONSTRAINT maintenance_log_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.maintenance_schedules.maintenance_schedules_assigned_stall_id_fkey
ALTER TABLE ONLY public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_assigned_stall_id_fkey FOREIGN KEY (assigned_stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.maintenance_schedules.maintenance_schedules_depot_id_fkey
ALTER TABLE ONLY public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.maintenance_schedules.maintenance_schedules_vehicle_id_fkey
ALTER TABLE ONLY public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.model_parameters.model_parameters_depot_id_fkey
ALTER TABLE ONLY public.model_parameters ADD CONSTRAINT model_parameters_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.model_tuning_runs.model_tuning_runs_depot_id_fkey
ALTER TABLE ONLY public.model_tuning_runs ADD CONSTRAINT model_tuning_runs_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.model_versions.model_versions_depot_id_fkey
ALTER TABLE ONLY public.model_versions ADD CONSTRAINT model_versions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.model_versions.model_versions_parent_version_id_fkey
ALTER TABLE ONLY public.model_versions ADD CONSTRAINT model_versions_parent_version_id_fkey FOREIGN KEY (parent_version_id) REFERENCES public.model_versions(id) ON DELETE SET NULL;
-- @@ constraint_f public.model_versions.model_versions_tuning_run_id_fkey
ALTER TABLE ONLY public.model_versions ADD CONSTRAINT model_versions_tuning_run_id_fkey FOREIGN KEY (tuning_run_id) REFERENCES public.model_tuning_runs(id) ON DELETE SET NULL;
-- @@ constraint_f public.notifications.notifications_depot_id_fkey
ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.notifications.notifications_exception_id_fkey
ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_exception_id_fkey FOREIGN KEY (exception_id) REFERENCES public.exceptions(id);
-- @@ constraint_f public.notifications.notifications_fleet_operator_id_fkey
ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id);
-- @@ constraint_f public.notifications.notifications_retail_member_id_fkey
ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_retail_member_id_fkey FOREIGN KEY (retail_member_id) REFERENCES public.retail_members(id);
-- @@ constraint_f public.notifications.notifications_schedule_task_id_fkey
ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_schedule_task_id_fkey FOREIGN KEY (schedule_task_id) REFERENCES public.schedule_tasks(id);
-- @@ constraint_f public.notifications.notifications_staff_user_id_fkey
ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_staff_user_id_fkey FOREIGN KEY (staff_user_id) REFERENCES public.staff_users(id);
-- @@ constraint_f public.notifications.notifications_vehicle_id_fkey
ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.ocpp_meter_values.ocpp_meter_values_depot_id_fkey
ALTER TABLE ONLY public.ocpp_meter_values ADD CONSTRAINT ocpp_meter_values_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ocpp_meter_values.ocpp_meter_values_ocpp_session_id_fkey
ALTER TABLE ONLY public.ocpp_meter_values ADD CONSTRAINT ocpp_meter_values_ocpp_session_id_fkey FOREIGN KEY (ocpp_session_id) REFERENCES public.ocpp_sessions(id) ON DELETE CASCADE;
-- @@ constraint_f public.ocpp_sessions.fk_ocpp_sessions_sim_run
ALTER TABLE ONLY public.ocpp_sessions ADD CONSTRAINT fk_ocpp_sessions_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ocpp_sessions.ocpp_sessions_depot_id_fkey
ALTER TABLE ONLY public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ocpp_sessions.ocpp_sessions_schedule_task_id_fkey
ALTER TABLE ONLY public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_schedule_task_id_fkey FOREIGN KEY (schedule_task_id) REFERENCES public.schedule_tasks(id);
-- @@ constraint_f public.ocpp_sessions.ocpp_sessions_stall_id_fkey
ALTER TABLE ONLY public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.ocpp_sessions.ocpp_sessions_vehicle_id_fkey
ALTER TABLE ONLY public.ocpp_sessions ADD CONSTRAINT ocpp_sessions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.ottoq_agent_call_ledger.ottoq_agent_call_ledger_principal_id_fkey
ALTER TABLE ONLY public.ottoq_agent_call_ledger ADD CONSTRAINT ottoq_agent_call_ledger_principal_id_fkey FOREIGN KEY (principal_id) REFERENCES public.ottoq_agent_principals(principal_id);
-- @@ constraint_f public.ottoq_agent_demo_passcode.ottoq_agent_demo_passcode_depot_id_fkey
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ADD CONSTRAINT ottoq_agent_demo_passcode_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_agent_demo_passcode.ottoq_agent_demo_passcode_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ADD CONSTRAINT ottoq_agent_demo_passcode_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id);
-- @@ constraint_f public.ottoq_agent_principals.ottoq_agent_principals_depot_id_fkey
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_agent_principals.ottoq_agent_principals_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id);
-- @@ constraint_f public.ottoq_agent_requests.ottoq_agent_requests_principal_id_fkey
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_principal_id_fkey FOREIGN KEY (principal_id) REFERENCES public.ottoq_agent_principals(principal_id);
-- @@ constraint_f public.ottoq_anomaly_observations.ottoq_anomaly_observations_detector_id_fkey
ALTER TABLE ONLY public.ottoq_anomaly_observations ADD CONSTRAINT ottoq_anomaly_observations_detector_id_fkey FOREIGN KEY (detector_id) REFERENCES public.ottoq_anomaly_detectors(detector_id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_anomaly_observations.ottoq_anomaly_observations_linked_event_id_fkey
ALTER TABLE ONLY public.ottoq_anomaly_observations ADD CONSTRAINT ottoq_anomaly_observations_linked_event_id_fkey FOREIGN KEY (linked_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_audit_bundles.ottoq_audit_bundles_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_audit_bundles ADD CONSTRAINT ottoq_audit_bundles_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_audit_reports.ottoq_audit_reports_depot_id_fkey
ALTER TABLE ONLY public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_audit_reports.ottoq_audit_reports_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_audit_reports.ottoq_audit_reports_parent_report_id_fkey
ALTER TABLE ONLY public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_parent_report_id_fkey FOREIGN KEY (parent_report_id) REFERENCES public.ottoq_audit_reports(report_id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_audit_reports.ottoq_audit_reports_source_event_id_fkey
ALTER TABLE ONLY public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_source_event_id_fkey FOREIGN KEY (source_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_bay_binding_witness.fk_ottoq_bay_binding_witness_sim_run
ALTER TABLE ONLY public.ottoq_bay_binding_witness ADD CONSTRAINT fk_ottoq_bay_binding_witness_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_bess_units.ottoq_bess_units_depot_id_fkey
ALTER TABLE ONLY public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_calibration_correlations.ottoq_calibration_correlations_dataset_code_fkey
ALTER TABLE ONLY public.ottoq_calibration_correlations ADD CONSTRAINT ottoq_calibration_correlations_dataset_code_fkey FOREIGN KEY (dataset_code) REFERENCES public.ottoq_calibration_datasets(dataset_code) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_calibration_distributions.ottoq_calibration_distributions_dataset_code_fkey
ALTER TABLE ONLY public.ottoq_calibration_distributions ADD CONSTRAINT ottoq_calibration_distributions_dataset_code_fkey FOREIGN KEY (dataset_code) REFERENCES public.ottoq_calibration_datasets(dataset_code) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_calibration_metrics.ottoq_calibration_metrics_model_version_id_fkey
ALTER TABLE ONLY public.ottoq_calibration_metrics ADD CONSTRAINT ottoq_calibration_metrics_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES public.model_versions(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_calibration_profiles.ottoq_calibration_profiles_dataset_code_fkey
ALTER TABLE ONLY public.ottoq_calibration_profiles ADD CONSTRAINT ottoq_calibration_profiles_dataset_code_fkey FOREIGN KEY (dataset_code) REFERENCES public.ottoq_calibration_datasets(dataset_code) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_cil_adoptions.fk_ottoq_cil_adoptions_sim_run
ALTER TABLE ONLY public.ottoq_cil_adoptions ADD CONSTRAINT fk_ottoq_cil_adoptions_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_comms_messages.fk_ottoq_comms_messages_sim_run
ALTER TABLE ONLY public.ottoq_comms_messages ADD CONSTRAINT fk_ottoq_comms_messages_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_counterfactuals.ottoq_counterfactuals_depot_id_fkey
ALTER TABLE ONLY public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_counterfactuals.ottoq_counterfactuals_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_counterfactuals.ottoq_counterfactuals_source_event_id_fkey
ALTER TABLE ONLY public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_source_event_id_fkey FOREIGN KEY (source_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_cuopt_deferrals.fk_ottoq_cuopt_deferrals_sim_run
ALTER TABLE ONLY public.ottoq_cuopt_deferrals ADD CONSTRAINT fk_ottoq_cuopt_deferrals_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_cuopt_fire_log.fk_ottoq_cuopt_fire_log_sim_run
ALTER TABLE ONLY public.ottoq_cuopt_fire_log ADD CONSTRAINT fk_ottoq_cuopt_fire_log_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_decision_snapshots.fk_ottoq_decision_snapshots_sim_run
ALTER TABLE ONLY public.ottoq_decision_snapshots ADD CONSTRAINT fk_ottoq_decision_snapshots_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_decisions.fk_ottoq_decisions_sim_run
ALTER TABLE ONLY public.ottoq_decisions ADD CONSTRAINT fk_ottoq_decisions_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_deploy_log.fk_ottoq_deploy_log_sim_run
ALTER TABLE ONLY public.ottoq_deploy_log ADD CONSTRAINT fk_ottoq_deploy_log_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_depot_benchmarks_daily.ottoq_depot_benchmarks_daily_depot_id_fkey
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ADD CONSTRAINT ottoq_depot_benchmarks_daily_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_depot_cost_daily.ottoq_depot_cost_daily_depot_id_fkey
ALTER TABLE ONLY public.ottoq_depot_cost_daily ADD CONSTRAINT ottoq_depot_cost_daily_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_depot_shifts.ottoq_depot_shifts_depot_id_fkey
ALTER TABLE ONLY public.ottoq_depot_shifts ADD CONSTRAINT ottoq_depot_shifts_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_depot_staffing.ottoq_depot_staffing_depot_id_fkey
ALTER TABLE ONLY public.ottoq_depot_staffing ADD CONSTRAINT ottoq_depot_staffing_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_dial_experiments.ottoq_dial_experiments_param_key_fkey
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_param_key_fkey FOREIGN KEY (param_key) REFERENCES public.ottoq_policy_param_catalog(param_key);
-- @@ constraint_f public.ottoq_dial_pair_ledger.ottoq_dial_pair_ledger_experiment_id_fkey
ALTER TABLE ONLY public.ottoq_dial_pair_ledger ADD CONSTRAINT ottoq_dial_pair_ledger_experiment_id_fkey FOREIGN KEY (experiment_id) REFERENCES public.ottoq_dial_experiments(experiment_id);
-- @@ constraint_f public.ottoq_dial_promotion_ledger.ottoq_dial_promotion_ledger_rolled_back_of_fkey
ALTER TABLE ONLY public.ottoq_dial_promotion_ledger ADD CONSTRAINT ottoq_dial_promotion_ledger_rolled_back_of_fkey FOREIGN KEY (rolled_back_of) REFERENCES public.ottoq_dial_promotion_ledger(promotion_id);
-- @@ constraint_f public.ottoq_dr_calls.fk_ottoq_dr_calls_sim_run
ALTER TABLE ONLY public.ottoq_dr_calls ADD CONSTRAINT fk_ottoq_dr_calls_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_emergency_invocations.ottoq_emergency_invocations_depot_id_fkey
ALTER TABLE ONLY public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_emergency_invocations.ottoq_emergency_invocations_linked_event_id_fkey
ALTER TABLE ONLY public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_linked_event_id_fkey FOREIGN KEY (linked_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_emergency_invocations.ottoq_emergency_invocations_triggered_by_event_id_fkey
ALTER TABLE ONLY public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_triggered_by_event_id_fkey FOREIGN KEY (triggered_by_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_energy_commands.fk_ottoq_energy_commands_sim_run
ALTER TABLE ONLY public.ottoq_energy_commands ADD CONSTRAINT fk_ottoq_energy_commands_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_energy_plan.fk_ottoq_energy_plan_sim_run
ALTER TABLE ONLY public.ottoq_energy_plan ADD CONSTRAINT fk_ottoq_energy_plan_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_event_state_anchor.fk_ottoq_event_state_anchor_sim_run
ALTER TABLE ONLY public.ottoq_event_state_anchor ADD CONSTRAINT fk_ottoq_event_state_anchor_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_events.fk_ottoq_events_sim_run
ALTER TABLE ONLY public.ottoq_events ADD CONSTRAINT fk_ottoq_events_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id) NOT VALID;
-- @@ constraint_f public.ottoq_events.ottoq_events_parent_event_id_fkey
ALTER TABLE ONLY public.ottoq_events ADD CONSTRAINT ottoq_events_parent_event_id_fkey FOREIGN KEY (parent_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_external_proposals.fk_ottoq_external_proposals_sim_run
ALTER TABLE ONLY public.ottoq_external_proposals ADD CONSTRAINT fk_ottoq_external_proposals_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_feature_values.ottoq_feature_values_depot_id_fkey
ALTER TABLE ONLY public.ottoq_feature_values ADD CONSTRAINT ottoq_feature_values_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_feature_values.ottoq_feature_values_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_feature_values ADD CONSTRAINT ottoq_feature_values_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_feature_values.ottoq_feature_values_source_event_id_fkey
ALTER TABLE ONLY public.ottoq_feature_values ADD CONSTRAINT ottoq_feature_values_source_event_id_fkey FOREIGN KEY (source_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_feed_activations.fk_ottoq_feed_activations_sim_run
ALTER TABLE ONLY public.ottoq_feed_activations ADD CONSTRAINT fk_ottoq_feed_activations_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_feed_activations.ottoq_feed_activations_plan_id_fkey
ALTER TABLE ONLY public.ottoq_feed_activations ADD CONSTRAINT ottoq_feed_activations_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.ottoq_feed_plans(plan_id);
-- @@ constraint_f public.ottoq_fleet_buildout_active.ottoq_fleet_buildout_active_depot_id_fkey
ALTER TABLE ONLY public.ottoq_fleet_buildout_active ADD CONSTRAINT ottoq_fleet_buildout_active_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_fleet_buildout_active.ottoq_fleet_buildout_active_fleet_code_fkey
ALTER TABLE ONLY public.ottoq_fleet_buildout_active ADD CONSTRAINT ottoq_fleet_buildout_active_fleet_code_fkey FOREIGN KEY (fleet_code) REFERENCES public.ottoq_fleet_buildouts(fleet_code);
-- @@ constraint_f public.ottoq_fleet_buildouts.ottoq_fleet_buildouts_depot_id_fkey
ALTER TABLE ONLY public.ottoq_fleet_buildouts ADD CONSTRAINT ottoq_fleet_buildouts_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_fleet_buildouts.ottoq_fleet_buildouts_lender_depot_id_fkey
ALTER TABLE ONLY public.ottoq_fleet_buildouts ADD CONSTRAINT ottoq_fleet_buildouts_lender_depot_id_fkey FOREIGN KEY (lender_depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_fleet_operator_slas.ottoq_fleet_operator_slas_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_grid_events.ottoq_grid_events_depot_id_fkey
ALTER TABLE ONLY public.ottoq_grid_events ADD CONSTRAINT ottoq_grid_events_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_grid_snapshots.fk_ottoq_grid_snapshots_sim_run
ALTER TABLE ONLY public.ottoq_grid_snapshots ADD CONSTRAINT fk_ottoq_grid_snapshots_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_incident_reports.ottoq_incident_reports_audit_bundle_id_fkey
ALTER TABLE ONLY public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_audit_bundle_id_fkey FOREIGN KEY (audit_bundle_id) REFERENCES public.ottoq_audit_bundles(bundle_id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_incident_reports.ottoq_incident_reports_audit_report_id_fkey
ALTER TABLE ONLY public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_audit_report_id_fkey FOREIGN KEY (audit_report_id) REFERENCES public.ottoq_audit_reports(report_id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_incident_reports.ottoq_incident_reports_depot_id_fkey
ALTER TABLE ONLY public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_incident_reports.ottoq_incident_reports_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_incident_reports.ottoq_incident_reports_triggering_event_id_fkey
ALTER TABLE ONLY public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_triggering_event_id_fkey FOREIGN KEY (triggering_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_inference_log.ottoq_inference_log_model_version_id_fkey
ALTER TABLE ONLY public.ottoq_inference_log ADD CONSTRAINT ottoq_inference_log_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES public.model_versions(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_inference_log.ottoq_inference_log_route_id_fkey
ALTER TABLE ONLY public.ottoq_inference_log ADD CONSTRAINT ottoq_inference_log_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.ottoq_model_routes(route_id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_itinerary_legs.fk_ottoq_itinerary_legs_sim_run
ALTER TABLE ONLY public.ottoq_itinerary_legs ADD CONSTRAINT fk_ottoq_itinerary_legs_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_itinerary_legs.ottoq_itinerary_legs_itinerary_id_fkey
ALTER TABLE ONLY public.ottoq_itinerary_legs ADD CONSTRAINT ottoq_itinerary_legs_itinerary_id_fkey FOREIGN KEY (itinerary_id) REFERENCES public.ottoq_vehicle_itineraries(itinerary_id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_model_routes.ottoq_model_routes_fallback_model_version_id_fkey
ALTER TABLE ONLY public.ottoq_model_routes ADD CONSTRAINT ottoq_model_routes_fallback_model_version_id_fkey FOREIGN KEY (fallback_model_version_id) REFERENCES public.model_versions(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_model_routes.ottoq_model_routes_model_version_id_fkey
ALTER TABLE ONLY public.ottoq_model_routes ADD CONSTRAINT ottoq_model_routes_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES public.model_versions(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_oauth_auth_requests.ottoq_oauth_auth_requests_client_id_fkey
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ADD CONSTRAINT ottoq_oauth_auth_requests_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.ottoq_oauth_clients(client_id);
-- @@ constraint_f public.ottoq_oauth_auth_requests.ottoq_oauth_auth_requests_principal_id_fkey
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ADD CONSTRAINT ottoq_oauth_auth_requests_principal_id_fkey FOREIGN KEY (principal_id) REFERENCES public.ottoq_agent_principals(principal_id);
-- @@ constraint_f public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_client_id_fkey
ALTER TABLE ONLY public.ottoq_oauth_device_codes ADD CONSTRAINT ottoq_oauth_device_codes_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.ottoq_oauth_clients(client_id);
-- @@ constraint_f public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_principal_id_fkey
ALTER TABLE ONLY public.ottoq_oauth_device_codes ADD CONSTRAINT ottoq_oauth_device_codes_principal_id_fkey FOREIGN KEY (principal_id) REFERENCES public.ottoq_agent_principals(principal_id);
-- @@ constraint_f public.ottoq_oauth_grants.ottoq_oauth_grants_client_id_fkey
ALTER TABLE ONLY public.ottoq_oauth_grants ADD CONSTRAINT ottoq_oauth_grants_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.ottoq_oauth_clients(client_id);
-- @@ constraint_f public.ottoq_oauth_grants.ottoq_oauth_grants_principal_id_fkey
ALTER TABLE ONLY public.ottoq_oauth_grants ADD CONSTRAINT ottoq_oauth_grants_principal_id_fkey FOREIGN KEY (principal_id) REFERENCES public.ottoq_agent_principals(principal_id);
-- @@ constraint_f public.ottoq_oauth_tokens.ottoq_oauth_tokens_principal_id_fkey
ALTER TABLE ONLY public.ottoq_oauth_tokens ADD CONSTRAINT ottoq_oauth_tokens_principal_id_fkey FOREIGN KEY (principal_id) REFERENCES public.ottoq_agent_principals(principal_id);
-- @@ constraint_f public.ottoq_ocpp_chargers.ottoq_ocpp_chargers_depot_id_fkey
ALTER TABLE ONLY public.ottoq_ocpp_chargers ADD CONSTRAINT ottoq_ocpp_chargers_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_ocpp_messages.fk_ottoq_ocpp_messages_sim_run
ALTER TABLE ONLY public.ottoq_ocpp_messages ADD CONSTRAINT fk_ottoq_ocpp_messages_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_ocpp_messages.ottoq_ocpp_messages_charger_id_fkey
ALTER TABLE ONLY public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_charger_id_fkey FOREIGN KEY (charger_id) REFERENCES public.ottoq_ocpp_chargers(charger_id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_ocpp_messages.ottoq_ocpp_messages_ocpp_session_id_fkey
ALTER TABLE ONLY public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_ocpp_session_id_fkey FOREIGN KEY (ocpp_session_id) REFERENCES public.ocpp_sessions(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_oem_webhook_log.fk_ottoq_oem_webhook_log_sim_run
ALTER TABLE ONLY public.ottoq_oem_webhook_log ADD CONSTRAINT fk_ottoq_oem_webhook_log_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_ops_approvals.fk_ottoq_ops_approvals_sim_run
ALTER TABLE ONLY public.ottoq_ops_approvals ADD CONSTRAINT fk_ottoq_ops_approvals_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_ops_approvals.ottoq_ops_approvals_vehicle_id_fkey
ALTER TABLE ONLY public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.ottoq_ops_approvals.ottoq_ops_approvals_visit_id_fkey
ALTER TABLE ONLY public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES public.ottoq_visit_needs(visit_id);
-- @@ constraint_f public.ottoq_owner_accounts.ottoq_owner_accounts_depot_id_fkey
ALTER TABLE ONLY public.ottoq_owner_accounts ADD CONSTRAINT ottoq_owner_accounts_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_owner_accounts.ottoq_owner_accounts_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_owner_accounts ADD CONSTRAINT ottoq_owner_accounts_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id);
-- @@ constraint_f public.ottoq_owner_commands.ottoq_owner_commands_principal_id_fkey
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_principal_id_fkey FOREIGN KEY (principal_id) REFERENCES public.ottoq_agent_principals(principal_id);
-- @@ constraint_f public.ottoq_owner_commands.ottoq_owner_commands_undoes_command_id_fkey
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_undoes_command_id_fkey FOREIGN KEY (undoes_command_id) REFERENCES public.ottoq_owner_commands(command_id);
-- @@ constraint_f public.ottoq_owner_commands.ottoq_owner_commands_undone_by_command_id_fkey
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_undone_by_command_id_fkey FOREIGN KEY (undone_by_command_id) REFERENCES public.ottoq_owner_commands(command_id);
-- @@ constraint_f public.ottoq_owner_settings.ottoq_owner_settings_closed_by_command_id_fkey
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_closed_by_command_id_fkey FOREIGN KEY (closed_by_command_id) REFERENCES public.ottoq_owner_commands(command_id);
-- @@ constraint_f public.ottoq_owner_settings.ottoq_owner_settings_command_id_fkey
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_command_id_fkey FOREIGN KEY (command_id) REFERENCES public.ottoq_owner_commands(command_id);
-- @@ constraint_f public.ottoq_owner_settings.ottoq_owner_settings_replaces_setting_id_fkey
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_replaces_setting_id_fkey FOREIGN KEY (replaces_setting_id) REFERENCES public.ottoq_owner_settings(setting_id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_owner_settings.ottoq_owner_settings_sim_run_id_fkey
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_policy_params.ottoq_policy_params_param_key_fkey
ALTER TABLE ONLY public.ottoq_policy_params ADD CONSTRAINT ottoq_policy_params_param_key_fkey FOREIGN KEY (param_key) REFERENCES public.ottoq_policy_param_catalog(param_key) ON UPDATE CASCADE ON DELETE RESTRICT;
-- @@ constraint_f public.ottoq_prediction_accuracy_heatmap.ottoq_prediction_accuracy_heatmap_depot_id_fkey
ALTER TABLE ONLY public.ottoq_prediction_accuracy_heatmap ADD CONSTRAINT ottoq_prediction_accuracy_heatmap_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_prediction_accuracy_heatmap.ottoq_prediction_accuracy_heatmap_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_prediction_accuracy_heatmap ADD CONSTRAINT ottoq_prediction_accuracy_heatmap_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_predictions.ottoq_predictions_ab_test_id_fkey
ALTER TABLE ONLY public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_ab_test_id_fkey FOREIGN KEY (ab_test_id) REFERENCES public.ab_tests(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_predictions.ottoq_predictions_depot_id_fkey
ALTER TABLE ONLY public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_predictions.ottoq_predictions_explanation_id_fkey
ALTER TABLE ONLY public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_explanation_id_fkey FOREIGN KEY (explanation_id) REFERENCES public.prediction_explanations(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_predictions.ottoq_predictions_fusion_log_id_fkey
ALTER TABLE ONLY public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_fusion_log_id_fkey FOREIGN KEY (fusion_log_id) REFERENCES public.decision_fusion_log(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_predictions.ottoq_predictions_model_version_id_fkey
ALTER TABLE ONLY public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES public.model_versions(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_predictions.ottoq_predictions_vehicle_id_fkey
ALTER TABLE ONLY public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.ottoq_recall_decisions.ottoq_recall_decisions_sim_run_id_fkey
ALTER TABLE ONLY public.ottoq_recall_decisions ADD CONSTRAINT ottoq_recall_decisions_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_recall_refusals.ottoq_recall_refusals_recall_id_fkey
ALTER TABLE ONLY public.ottoq_recall_refusals ADD CONSTRAINT ottoq_recall_refusals_recall_id_fkey FOREIGN KEY (recall_id) REFERENCES public.ottoq_recall_decisions(recall_id);
-- @@ constraint_f public.ottoq_recall_refusals.ottoq_recall_refusals_sim_run_id_fkey
ALTER TABLE ONLY public.ottoq_recall_refusals ADD CONSTRAINT ottoq_recall_refusals_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_rider_cleaning_flags.fk_ottoq_rider_cleaning_flags_sim_run
ALTER TABLE ONLY public.ottoq_rider_cleaning_flags ADD CONSTRAINT fk_ottoq_rider_cleaning_flags_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_rider_cleaning_flags.ottoq_rider_cleaning_flags_recalled_visit_id_fkey
ALTER TABLE ONLY public.ottoq_rider_cleaning_flags ADD CONSTRAINT ottoq_rider_cleaning_flags_recalled_visit_id_fkey FOREIGN KEY (recalled_visit_id) REFERENCES public.ottoq_visit_needs(visit_id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_rule_evaluations.fk_ottoq_rule_evaluations_sim_run
ALTER TABLE ONLY public.ottoq_rule_evaluations ADD CONSTRAINT fk_ottoq_rule_evaluations_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id) NOT VALID;
-- @@ constraint_f public.ottoq_rule_evaluations.ottoq_rule_evaluations_depot_id_fkey
ALTER TABLE ONLY public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_rule_evaluations.ottoq_rule_evaluations_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_rule_evaluations.ottoq_rule_evaluations_linked_event_id_fkey
ALTER TABLE ONLY public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_linked_event_id_fkey FOREIGN KEY (linked_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_rule_evaluations.ottoq_rule_evaluations_triggered_by_event_id_fkey
ALTER TABLE ONLY public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_triggered_by_event_id_fkey FOREIGN KEY (triggered_by_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_rule_overrides.ottoq_rule_overrides_depot_id_fkey
ALTER TABLE ONLY public.ottoq_rule_overrides ADD CONSTRAINT ottoq_rule_overrides_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_rule_overrides.ottoq_rule_overrides_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_rule_overrides ADD CONSTRAINT ottoq_rule_overrides_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_rule_overrides.ottoq_rule_overrides_linked_event_id_fkey
ALTER TABLE ONLY public.ottoq_rule_overrides ADD CONSTRAINT ottoq_rule_overrides_linked_event_id_fkey FOREIGN KEY (linked_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_scenarios.ottoq_scenarios_depot_id_fkey
ALTER TABLE ONLY public.ottoq_scenarios ADD CONSTRAINT ottoq_scenarios_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_service_detail_records.ottoq_service_detail_records_pack_id_operation_code_fkey
ALTER TABLE ONLY public.ottoq_service_detail_records ADD CONSTRAINT ottoq_service_detail_records_pack_id_operation_code_fkey FOREIGN KEY (pack_id, operation_code) REFERENCES public.ottoq_operation_catalog(pack_id, operation_code);
-- @@ constraint_f public.ottoq_service_detail_records.ottoq_service_detail_records_sim_run_id_fkey
ALTER TABLE ONLY public.ottoq_service_detail_records ADD CONSTRAINT ottoq_service_detail_records_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_service_detail_records.ottoq_service_detail_records_tariff_id_fkey
ALTER TABLE ONLY public.ottoq_service_detail_records ADD CONSTRAINT ottoq_service_detail_records_tariff_id_fkey FOREIGN KEY (tariff_id) REFERENCES public.ottoq_service_tariffs(tariff_id);
-- @@ constraint_f public.ottoq_service_detail_records.ottoq_service_detail_records_vehicle_id_fkey
ALTER TABLE ONLY public.ottoq_service_detail_records ADD CONSTRAINT ottoq_service_detail_records_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_service_point_capabilities.ottoq_service_point_capabilities_asset_class_code_fkey
ALTER TABLE ONLY public.ottoq_service_point_capabilities ADD CONSTRAINT ottoq_service_point_capabilities_asset_class_code_fkey FOREIGN KEY (asset_class_code) REFERENCES public.ottoq_vehicle_classes(vehicle_class_code);
-- @@ constraint_f public.ottoq_service_point_capabilities.ottoq_service_point_capabilities_pack_id_operation_code_fkey
ALTER TABLE ONLY public.ottoq_service_point_capabilities ADD CONSTRAINT ottoq_service_point_capabilities_pack_id_operation_code_fkey FOREIGN KEY (pack_id, operation_code) REFERENCES public.ottoq_operation_catalog(pack_id, operation_code);
-- @@ constraint_f public.ottoq_service_point_capabilities.ottoq_service_point_capabilities_stall_id_fkey
ALTER TABLE ONLY public.ottoq_service_point_capabilities ADD CONSTRAINT ottoq_service_point_capabilities_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES public.stalls(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_service_tariffs.ottoq_service_tariffs_asset_class_code_fkey
ALTER TABLE ONLY public.ottoq_service_tariffs ADD CONSTRAINT ottoq_service_tariffs_asset_class_code_fkey FOREIGN KEY (asset_class_code) REFERENCES public.ottoq_vehicle_classes(vehicle_class_code);
-- @@ constraint_f public.ottoq_service_tariffs.ottoq_service_tariffs_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_service_tariffs ADD CONSTRAINT ottoq_service_tariffs_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_service_tariffs.ottoq_service_tariffs_pack_id_operation_code_fkey
ALTER TABLE ONLY public.ottoq_service_tariffs ADD CONSTRAINT ottoq_service_tariffs_pack_id_operation_code_fkey FOREIGN KEY (pack_id, operation_code) REFERENCES public.ottoq_operation_catalog(pack_id, operation_code);
-- @@ constraint_f public.ottoq_service_tokens.ottoq_service_tokens_asset_class_code_fkey
ALTER TABLE ONLY public.ottoq_service_tokens ADD CONSTRAINT ottoq_service_tokens_asset_class_code_fkey FOREIGN KEY (asset_class_code) REFERENCES public.ottoq_vehicle_classes(vehicle_class_code);
-- @@ constraint_f public.ottoq_service_tokens.ottoq_service_tokens_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_service_tokens ADD CONSTRAINT ottoq_service_tokens_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_service_tokens.ottoq_service_tokens_vehicle_id_fkey
ALTER TABLE ONLY public.ottoq_service_tokens ADD CONSTRAINT ottoq_service_tokens_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_sim_runs.ottoq_sim_runs_depot_id_fkey
ALTER TABLE ONLY public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_sim_runs.ottoq_sim_runs_scenario_id_fkey
ALTER TABLE ONLY public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES public.ottoq_scenarios(scenario_id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_site_base_history.ottoq_site_base_history_depot_id_fkey
ALTER TABLE ONLY public.ottoq_site_base_history ADD CONSTRAINT ottoq_site_base_history_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_site_base_history.ottoq_site_base_history_stall_id_fkey
ALTER TABLE ONLY public.ottoq_site_base_history ADD CONSTRAINT ottoq_site_base_history_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.ottoq_site_buildout_active.ottoq_site_buildout_active_buildout_code_fkey
ALTER TABLE ONLY public.ottoq_site_buildout_active ADD CONSTRAINT ottoq_site_buildout_active_buildout_code_fkey FOREIGN KEY (buildout_code) REFERENCES public.ottoq_site_buildouts(buildout_code);
-- @@ constraint_f public.ottoq_site_buildout_active.ottoq_site_buildout_active_depot_id_fkey
ALTER TABLE ONLY public.ottoq_site_buildout_active ADD CONSTRAINT ottoq_site_buildout_active_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_site_buildouts.ottoq_site_buildouts_depot_id_fkey
ALTER TABLE ONLY public.ottoq_site_buildouts ADD CONSTRAINT ottoq_site_buildouts_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_site_structures.ottoq_site_structures_depot_id_fkey
ALTER TABLE ONLY public.ottoq_site_structures ADD CONSTRAINT ottoq_site_structures_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_sla_conformance_daily.ottoq_sla_conformance_daily_depot_id_fkey
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ADD CONSTRAINT ottoq_sla_conformance_daily_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_sla_conformance_daily.ottoq_sla_conformance_daily_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ADD CONSTRAINT ottoq_sla_conformance_daily_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_sla_violations.ottoq_sla_violations_depot_id_fkey
ALTER TABLE ONLY public.ottoq_sla_violations ADD CONSTRAINT ottoq_sla_violations_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_sla_violations.ottoq_sla_violations_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_sla_violations ADD CONSTRAINT ottoq_sla_violations_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_sla_violations.ottoq_sla_violations_linked_event_id_fkey
ALTER TABLE ONLY public.ottoq_sla_violations ADD CONSTRAINT ottoq_sla_violations_linked_event_id_fkey FOREIGN KEY (linked_event_id) REFERENCES public.ottoq_events(event_id) ON DELETE SET NULL NOT VALID;
-- @@ constraint_f public.ottoq_solar_output.fk_ottoq_solar_output_sim_run
ALTER TABLE ONLY public.ottoq_solar_output ADD CONSTRAINT fk_ottoq_solar_output_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_stall_bookings.fk_ottoq_stall_bookings_sim_run
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT fk_ottoq_stall_bookings_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_stall_bookings.ottoq_stall_bookings_stall_id_fkey
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES public.stalls(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_stall_bookings.ottoq_stall_bookings_vehicle_id_fkey
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_t4_coverage_samples.fk_ottoq_t4_coverage_samples_sim_run
ALTER TABLE ONLY public.ottoq_t4_coverage_samples ADD CONSTRAINT fk_ottoq_t4_coverage_samples_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_telemetry_packets.fk_ottoq_telemetry_packets_sim_run
ALTER TABLE ONLY public.ottoq_telemetry_packets ADD CONSTRAINT fk_ottoq_telemetry_packets_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_throughput_sweep_arms.ottoq_throughput_sweep_arms_cell_id_fkey
ALTER TABLE ONLY public.ottoq_throughput_sweep_arms ADD CONSTRAINT ottoq_throughput_sweep_arms_cell_id_fkey FOREIGN KEY (cell_id) REFERENCES public.ottoq_throughput_sweep_cells(cell_id);
-- @@ constraint_f public.ottoq_throughput_sweep_arms.ottoq_throughput_sweep_arms_sweep_id_fkey
ALTER TABLE ONLY public.ottoq_throughput_sweep_arms ADD CONSTRAINT ottoq_throughput_sweep_arms_sweep_id_fkey FOREIGN KEY (sweep_id) REFERENCES public.ottoq_throughput_sweeps(sweep_id);
-- @@ constraint_f public.ottoq_throughput_sweep_cells.ottoq_throughput_sweep_cells_buildout_code_fkey
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ADD CONSTRAINT ottoq_throughput_sweep_cells_buildout_code_fkey FOREIGN KEY (buildout_code) REFERENCES public.ottoq_site_buildouts(buildout_code);
-- @@ constraint_f public.ottoq_throughput_sweep_cells.ottoq_throughput_sweep_cells_control_fk
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ADD CONSTRAINT ottoq_throughput_sweep_cells_control_fk FOREIGN KEY (sweep_id, control_cell_code) REFERENCES public.ottoq_throughput_sweep_cells(sweep_id, cell_code);
-- @@ constraint_f public.ottoq_throughput_sweep_cells.ottoq_throughput_sweep_cells_sweep_id_fkey
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ADD CONSTRAINT ottoq_throughput_sweep_cells_sweep_id_fkey FOREIGN KEY (sweep_id) REFERENCES public.ottoq_throughput_sweeps(sweep_id);
-- @@ constraint_f public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_depot_id_fkey
ALTER TABLE ONLY public.ottoq_throughput_sweeps ADD CONSTRAINT ottoq_throughput_sweeps_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_fleet_code_fkey
ALTER TABLE ONLY public.ottoq_throughput_sweeps ADD CONSTRAINT ottoq_throughput_sweeps_fleet_code_fkey FOREIGN KEY (fleet_code) REFERENCES public.ottoq_fleet_buildouts(fleet_code);
-- @@ constraint_f public.ottoq_tick_clock_log.fk_ottoq_tick_clock_log_sim_run
ALTER TABLE ONLY public.ottoq_tick_clock_log ADD CONSTRAINT fk_ottoq_tick_clock_log_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_tick_invariance_arms.fk_ottoq_tick_invariance_arms_sim_run
ALTER TABLE ONLY public.ottoq_tick_invariance_arms ADD CONSTRAINT fk_ottoq_tick_invariance_arms_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_tick_reservations.fk_ottoq_tick_reservations_sim_run
ALTER TABLE ONLY public.ottoq_tick_reservations ADD CONSTRAINT fk_ottoq_tick_reservations_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_training_runs.ottoq_training_runs_parent_model_version_id_fkey
ALTER TABLE ONLY public.ottoq_training_runs ADD CONSTRAINT ottoq_training_runs_parent_model_version_id_fkey FOREIGN KEY (parent_model_version_id) REFERENCES public.model_versions(id);
-- @@ constraint_f public.ottoq_training_runs.ottoq_training_runs_resulting_model_version_id_fkey
ALTER TABLE ONLY public.ottoq_training_runs ADD CONSTRAINT ottoq_training_runs_resulting_model_version_id_fkey FOREIGN KEY (resulting_model_version_id) REFERENCES public.model_versions(id);
-- @@ constraint_f public.ottoq_v2_cursors.ottoq_v2_cursors_sim_run_id_fkey
ALTER TABLE ONLY public.ottoq_v2_cursors ADD CONSTRAINT ottoq_v2_cursors_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_v2_inbox.ottoq_v2_inbox_depot_id_fkey
ALTER TABLE ONLY public.ottoq_v2_inbox ADD CONSTRAINT ottoq_v2_inbox_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.ottoq_v2_inbox.ottoq_v2_inbox_key_id_fkey
ALTER TABLE ONLY public.ottoq_v2_inbox ADD CONSTRAINT ottoq_v2_inbox_key_id_fkey FOREIGN KEY (key_id) REFERENCES public.ottow_api_keys(id);
-- @@ constraint_f public.ottoq_v2_inbox.ottoq_v2_inbox_sim_run_id_fkey
ALTER TABLE ONLY public.ottoq_v2_inbox ADD CONSTRAINT ottoq_v2_inbox_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_v2_inbox.ottoq_v2_inbox_vehicle_id_fkey
ALTER TABLE ONLY public.ottoq_v2_inbox ADD CONSTRAINT ottoq_v2_inbox_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.ottoq_variability_cards.fk_ottoq_variability_cards_sim_run
ALTER TABLE ONLY public.ottoq_variability_cards ADD CONSTRAINT fk_ottoq_variability_cards_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_variability_profiles.fk_ottoq_variability_profiles_sim_run
ALTER TABLE ONLY public.ottoq_variability_profiles ADD CONSTRAINT fk_ottoq_variability_profiles_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_vehicle_classes.ottoq_vehicle_classes_oem_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_vehicle_classes ADD CONSTRAINT ottoq_vehicle_classes_oem_fleet_operator_id_fkey FOREIGN KEY (oem_fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_vehicle_commands.fk_ottoq_vehicle_commands_sim_run
ALTER TABLE ONLY public.ottoq_vehicle_commands ADD CONSTRAINT fk_ottoq_vehicle_commands_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_vehicle_commands.ottoq_vehicle_commands_vehicle_id_fkey
ALTER TABLE ONLY public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.ottoq_vehicle_dispatches.fk_ottoq_vehicle_dispatches_sim_run
ALTER TABLE ONLY public.ottoq_vehicle_dispatches ADD CONSTRAINT fk_ottoq_vehicle_dispatches_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_vehicle_incidents.fk_ottoq_vehicle_incidents_sim_run
ALTER TABLE ONLY public.ottoq_vehicle_incidents ADD CONSTRAINT fk_ottoq_vehicle_incidents_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_vehicle_itineraries.fk_ottoq_vehicle_itineraries_sim_run
ALTER TABLE ONLY public.ottoq_vehicle_itineraries ADD CONSTRAINT fk_ottoq_vehicle_itineraries_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_vehicle_wear.fk_ottoq_vehicle_wear_sim_run
ALTER TABLE ONLY public.ottoq_vehicle_wear ADD CONSTRAINT fk_ottoq_vehicle_wear_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_vehicle_wear.ottoq_vehicle_wear_vehicle_id_fkey
ALTER TABLE ONLY public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottoq_visit_cost_attribution.ottoq_visit_cost_attribution_depot_id_fkey
ALTER TABLE ONLY public.ottoq_visit_cost_attribution ADD CONSTRAINT ottoq_visit_cost_attribution_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_visit_cost_attribution.ottoq_visit_cost_attribution_fleet_operator_id_fkey
ALTER TABLE ONLY public.ottoq_visit_cost_attribution ADD CONSTRAINT ottoq_visit_cost_attribution_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottoq_visit_needs.fk_ottoq_visit_needs_sim_run
ALTER TABLE ONLY public.ottoq_visit_needs ADD CONSTRAINT fk_ottoq_visit_needs_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_visit_needs.ottoq_visit_needs_vehicle_id_fkey
ALTER TABLE ONLY public.ottoq_visit_needs ADD CONSTRAINT ottoq_visit_needs_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.ottoq_wave_plan.fk_ottoq_wave_plan_sim_run
ALTER TABLE ONLY public.ottoq_wave_plan ADD CONSTRAINT fk_ottoq_wave_plan_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_wear_tick_status.fk_ottoq_wear_tick_status_sim_run
ALTER TABLE ONLY public.ottoq_wear_tick_status ADD CONSTRAINT fk_ottoq_wear_tick_status_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottoq_weather_snapshots.fk_ottoq_weather_snapshots_sim_run
ALTER TABLE ONLY public.ottoq_weather_snapshots ADD CONSTRAINT fk_ottoq_weather_snapshots_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.ottow_api_keys.ottow_api_keys_depot_id_fkey
ALTER TABLE ONLY public.ottow_api_keys ADD CONSTRAINT ottow_api_keys_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottow_dispatch_rules.ottow_dispatch_rules_depot_id_fkey
ALTER TABLE ONLY public.ottow_dispatch_rules ADD CONSTRAINT ottow_dispatch_rules_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottow_drivers.fk_ottow_drivers_current_mission
ALTER TABLE ONLY public.ottow_drivers ADD CONSTRAINT fk_ottow_drivers_current_mission FOREIGN KEY (current_mission_id) REFERENCES public.ottow_missions(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottow_drivers.ottow_drivers_depot_id_fkey
ALTER TABLE ONLY public.ottow_drivers ADD CONSTRAINT ottow_drivers_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottow_drivers.ottow_drivers_staff_user_id_fkey
ALTER TABLE ONLY public.ottow_drivers ADD CONSTRAINT ottow_drivers_staff_user_id_fkey FOREIGN KEY (staff_user_id) REFERENCES public.staff_users(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottow_mission_events.ottow_mission_events_mission_id_fkey
ALTER TABLE ONLY public.ottow_mission_events ADD CONSTRAINT ottow_mission_events_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES public.ottow_missions(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottow_missions.ottow_missions_depot_id_fkey
ALTER TABLE ONLY public.ottow_missions ADD CONSTRAINT ottow_missions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottow_missions.ottow_missions_destination_stall_id_fkey
ALTER TABLE ONLY public.ottow_missions ADD CONSTRAINT ottow_missions_destination_stall_id_fkey FOREIGN KEY (destination_stall_id) REFERENCES public.stalls(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottow_missions.ottow_missions_driver_staff_id_fkey
ALTER TABLE ONLY public.ottow_missions ADD CONSTRAINT ottow_missions_driver_staff_id_fkey FOREIGN KEY (driver_staff_id) REFERENCES public.staff_users(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottow_missions.ottow_missions_exception_id_fkey
ALTER TABLE ONLY public.ottow_missions ADD CONSTRAINT ottow_missions_exception_id_fkey FOREIGN KEY (exception_id) REFERENCES public.exceptions(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottow_missions.ottow_missions_ottow_vehicle_id_fkey
ALTER TABLE ONLY public.ottow_missions ADD CONSTRAINT ottow_missions_ottow_vehicle_id_fkey FOREIGN KEY (ottow_vehicle_id) REFERENCES public.vehicles(id) ON DELETE SET NULL;
-- @@ constraint_f public.ottow_missions.ottow_missions_vehicle_id_fkey
ALTER TABLE ONLY public.ottow_missions ADD CONSTRAINT ottow_missions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottow_notifications.ottow_notifications_depot_id_fkey
ALTER TABLE ONLY public.ottow_notifications ADD CONSTRAINT ottow_notifications_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.ottow_notifications.ottow_notifications_vehicle_id_fkey
ALTER TABLE ONLY public.ottow_notifications ADD CONSTRAINT ottow_notifications_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE SET NULL;
-- @@ constraint_f public.prediction_accuracy_daily.prediction_accuracy_daily_depot_id_fkey
ALTER TABLE ONLY public.prediction_accuracy_daily ADD CONSTRAINT prediction_accuracy_daily_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.prediction_explanations.prediction_explanations_ab_test_id_fkey
ALTER TABLE ONLY public.prediction_explanations ADD CONSTRAINT prediction_explanations_ab_test_id_fkey FOREIGN KEY (ab_test_id) REFERENCES public.ab_tests(id);
-- @@ constraint_f public.prediction_explanations.prediction_explanations_model_version_id_fkey
ALTER TABLE ONLY public.prediction_explanations ADD CONSTRAINT prediction_explanations_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES public.model_versions(id);
-- @@ constraint_f public.prediction_explanations.prediction_explanations_prediction_id_fkey
ALTER TABLE ONLY public.prediction_explanations ADD CONSTRAINT prediction_explanations_prediction_id_fkey FOREIGN KEY (prediction_id) REFERENCES public.ottoq_predictions(id) ON DELETE CASCADE;
-- @@ constraint_f public.prediction_outcomes.prediction_outcomes_depot_id_fkey
ALTER TABLE ONLY public.prediction_outcomes ADD CONSTRAINT prediction_outcomes_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.prediction_outcomes.prediction_outcomes_prediction_id_fkey
ALTER TABLE ONLY public.prediction_outcomes ADD CONSTRAINT prediction_outcomes_prediction_id_fkey FOREIGN KEY (prediction_id) REFERENCES public.ottoq_predictions(id) ON DELETE CASCADE;
-- @@ constraint_f public.progression_decisions.progression_decisions_depot_id_fkey
ALTER TABLE ONLY public.progression_decisions ADD CONSTRAINT progression_decisions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.progression_decisions.progression_decisions_fleet_operator_id_fkey
ALTER TABLE ONLY public.progression_decisions ADD CONSTRAINT progression_decisions_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.progression_decisions.progression_decisions_from_stall_id_fkey
ALTER TABLE ONLY public.progression_decisions ADD CONSTRAINT progression_decisions_from_stall_id_fkey FOREIGN KEY (from_stall_id) REFERENCES public.stalls(id) ON DELETE SET NULL;
-- @@ constraint_f public.progression_decisions.progression_decisions_schedule_id_fkey
ALTER TABLE ONLY public.progression_decisions ADD CONSTRAINT progression_decisions_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES public.vehicle_schedules(id) ON DELETE CASCADE;
-- @@ constraint_f public.progression_decisions.progression_decisions_task_id_fkey
ALTER TABLE ONLY public.progression_decisions ADD CONSTRAINT progression_decisions_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.schedule_tasks(id) ON DELETE SET NULL;
-- @@ constraint_f public.progression_decisions.progression_decisions_to_stall_id_fkey
ALTER TABLE ONLY public.progression_decisions ADD CONSTRAINT progression_decisions_to_stall_id_fkey FOREIGN KEY (to_stall_id) REFERENCES public.stalls(id) ON DELETE SET NULL;
-- @@ constraint_f public.progression_decisions.progression_decisions_vehicle_id_fkey
ALTER TABLE ONLY public.progression_decisions ADD CONSTRAINT progression_decisions_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.retail_members.retail_members_home_depot_id_fkey
ALTER TABLE ONLY public.retail_members ADD CONSTRAINT retail_members_home_depot_id_fkey FOREIGN KEY (home_depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.schedule_modifications.schedule_modifications_depot_id_fkey
ALTER TABLE ONLY public.schedule_modifications ADD CONSTRAINT schedule_modifications_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.schedule_modifications.schedule_modifications_vehicle_id_fkey
ALTER TABLE ONLY public.schedule_modifications ADD CONSTRAINT schedule_modifications_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);
-- @@ constraint_f public.schedule_modifications.schedule_modifications_vehicle_schedule_id_fkey
ALTER TABLE ONLY public.schedule_modifications ADD CONSTRAINT schedule_modifications_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES public.vehicle_schedules(id) ON DELETE CASCADE;
-- @@ constraint_f public.schedule_tasks.fk_task_exception
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT fk_task_exception FOREIGN KEY (exception_id) REFERENCES public.exceptions(id) ON DELETE SET NULL;
-- @@ constraint_f public.schedule_tasks.schedule_tasks_actual_stall_id_fkey
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_actual_stall_id_fkey FOREIGN KEY (actual_stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.schedule_tasks.schedule_tasks_assigned_stall_id_fkey
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_assigned_stall_id_fkey FOREIGN KEY (assigned_stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.schedule_tasks.schedule_tasks_depot_id_fkey
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.schedule_tasks.schedule_tasks_service_definition_id_fkey
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_service_definition_id_fkey FOREIGN KEY (service_definition_id) REFERENCES public.service_definitions(id);
-- @@ constraint_f public.schedule_tasks.schedule_tasks_tech_override_next_stall_id_fkey
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_tech_override_next_stall_id_fkey FOREIGN KEY (tech_override_next_stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.schedule_tasks.schedule_tasks_vehicle_id_fkey
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.schedule_tasks.schedule_tasks_vehicle_schedule_id_fkey
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES public.vehicle_schedules(id) ON DELETE CASCADE;
-- @@ constraint_f public.service_definitions.service_definitions_depot_id_fkey
ALTER TABLE ONLY public.service_definitions ADD CONSTRAINT service_definitions_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.site_energy_snapshots.fk_site_energy_snapshots_sim_run
ALTER TABLE ONLY public.site_energy_snapshots ADD CONSTRAINT fk_site_energy_snapshots_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.site_energy_snapshots.site_energy_snapshots_depot_id_fkey
ALTER TABLE ONLY public.site_energy_snapshots ADD CONSTRAINT site_energy_snapshots_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.space_conflict_ledger.fk_space_conflict_ledger_sim_run
ALTER TABLE ONLY public.space_conflict_ledger ADD CONSTRAINT fk_space_conflict_ledger_sim_run FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f public.staff_users.staff_users_depot_id_fkey
ALTER TABLE ONLY public.staff_users ADD CONSTRAINT staff_users_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.stalls.fk_stalls_current_vehicle
ALTER TABLE ONLY public.stalls ADD CONSTRAINT fk_stalls_current_vehicle FOREIGN KEY (current_vehicle_id) REFERENCES public.vehicles(id) ON DELETE SET NULL;
-- @@ constraint_f public.stalls.stalls_depot_id_fkey
ALTER TABLE ONLY public.stalls ADD CONSTRAINT stalls_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.stalls.stalls_ocpp_charger_id_fkey
ALTER TABLE ONLY public.stalls ADD CONSTRAINT stalls_ocpp_charger_id_fkey FOREIGN KEY (ocpp_charger_id) REFERENCES public.ottoq_ocpp_chargers(charger_id) ON DELETE SET NULL;
-- @@ constraint_f public.stalls.stalls_reserved_for_mission_id_fkey
ALTER TABLE ONLY public.stalls ADD CONSTRAINT stalls_reserved_for_mission_id_fkey FOREIGN KEY (reserved_for_mission_id) REFERENCES public.ottow_missions(id) ON DELETE SET NULL;
-- @@ constraint_f public.tariff_schedules.tariff_schedules_depot_id_fkey
ALTER TABLE ONLY public.tariff_schedules ADD CONSTRAINT tariff_schedules_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.tuning_iterations.tuning_iterations_tuning_run_id_fkey
ALTER TABLE ONLY public.tuning_iterations ADD CONSTRAINT tuning_iterations_tuning_run_id_fkey FOREIGN KEY (tuning_run_id) REFERENCES public.model_tuning_runs(id) ON DELETE CASCADE;
-- @@ constraint_f public.vehicle_need_profile.vehicle_need_profile_vehicle_id_fkey
ALTER TABLE ONLY public.vehicle_need_profile ADD CONSTRAINT vehicle_need_profile_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.vehicle_schedules.vehicle_schedules_depot_id_fkey
ALTER TABLE ONLY public.vehicle_schedules ADD CONSTRAINT vehicle_schedules_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f public.vehicle_schedules.vehicle_schedules_vehicle_id_fkey
ALTER TABLE ONLY public.vehicle_schedules ADD CONSTRAINT vehicle_schedules_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.vehicle_schedules.vehicle_schedules_wave_id_fkey
ALTER TABLE ONLY public.vehicle_schedules ADD CONSTRAINT vehicle_schedules_wave_id_fkey FOREIGN KEY (wave_id) REFERENCES public.waves(id) ON DELETE SET NULL;
-- @@ constraint_f public.vehicle_state_log.vehicle_state_log_depot_id_fkey
ALTER TABLE ONLY public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.vehicle_state_log.vehicle_state_log_schedule_task_id_fkey
ALTER TABLE ONLY public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_schedule_task_id_fkey FOREIGN KEY (schedule_task_id) REFERENCES public.schedule_tasks(id);
-- @@ constraint_f public.vehicle_state_log.vehicle_state_log_stall_id_fkey
ALTER TABLE ONLY public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_stall_id_fkey FOREIGN KEY (stall_id) REFERENCES public.stalls(id);
-- @@ constraint_f public.vehicle_state_log.vehicle_state_log_vehicle_id_fkey
ALTER TABLE ONLY public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.vehicle_state_log.vehicle_state_log_vehicle_schedule_id_fkey
ALTER TABLE ONLY public.vehicle_state_log ADD CONSTRAINT vehicle_state_log_vehicle_schedule_id_fkey FOREIGN KEY (vehicle_schedule_id) REFERENCES public.vehicle_schedules(id);
-- @@ constraint_f public.vehicle_telemetry.vehicle_telemetry_depot_id_fkey
ALTER TABLE ONLY public.vehicle_telemetry ADD CONSTRAINT vehicle_telemetry_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.vehicle_telemetry.vehicle_telemetry_vehicle_id_fkey
ALTER TABLE ONLY public.vehicle_telemetry ADD CONSTRAINT vehicle_telemetry_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;
-- @@ constraint_f public.vehicles.fk_vehicles_owning_sim_run
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT fk_vehicles_owning_sim_run FOREIGN KEY (owning_sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id) ON DELETE SET NULL;
-- @@ constraint_f public.vehicles.vehicles_current_depot_id_fkey
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_current_depot_id_fkey FOREIGN KEY (current_depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.vehicles.vehicles_current_stall_id_fkey
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_current_stall_id_fkey FOREIGN KEY (current_stall_id) REFERENCES public.stalls(id) ON DELETE SET NULL;
-- @@ constraint_f public.vehicles.vehicles_fleet_operator_id_fkey
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_fleet_operator_id_fkey FOREIGN KEY (fleet_operator_id) REFERENCES public.fleet_operators(id) ON DELETE SET NULL;
-- @@ constraint_f public.vehicles.vehicles_home_depot_id_fkey
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_home_depot_id_fkey FOREIGN KEY (home_depot_id) REFERENCES public.depots(id);
-- @@ constraint_f public.vehicles.vehicles_retail_member_id_fkey
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_retail_member_id_fkey FOREIGN KEY (retail_member_id) REFERENCES public.retail_members(id) ON DELETE SET NULL;
-- @@ constraint_f public.vehicles.vehicles_vehicle_class_code_fkey
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_vehicle_class_code_fkey FOREIGN KEY (vehicle_class_code) REFERENCES public.ottoq_vehicle_classes(vehicle_class_code);
-- @@ constraint_f public.waves.waves_depot_id_fkey
ALTER TABLE ONLY public.waves ADD CONSTRAINT waves_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id) ON DELETE CASCADE;
-- @@ constraint_f twin.arm_cycles.arm_cycles_sim_run_id_fkey
ALTER TABLE ONLY twin.arm_cycles ADD CONSTRAINT arm_cycles_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f twin.arm_registrations.arm_registrations_sim_run_id_fkey
ALTER TABLE ONLY twin.arm_registrations ADD CONSTRAINT arm_registrations_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f twin.ottoq_twin_drive_log.ottoq_twin_drive_log_sim_run_id_fkey
ALTER TABLE ONLY twin.ottoq_twin_drive_log ADD CONSTRAINT ottoq_twin_drive_log_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f twin.ottoq_twin_operator_log.ottoq_twin_operator_log_sim_run_id_fkey
ALTER TABLE ONLY twin.ottoq_twin_operator_log ADD CONSTRAINT ottoq_twin_operator_log_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f twin.ottoq_twin_operator_sequences.ottoq_twin_operator_sequences_sim_run_id_fkey
ALTER TABLE ONLY twin.ottoq_twin_operator_sequences ADD CONSTRAINT ottoq_twin_operator_sequences_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f twin.ottoq_twin_operator_state.ottoq_twin_operator_state_sim_run_id_fkey
ALTER TABLE ONLY twin.ottoq_twin_operator_state ADD CONSTRAINT ottoq_twin_operator_state_sim_run_id_fkey FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);
-- @@ constraint_f twin.ottoq_twin_operator_state.ottoq_twin_operator_state_source_name_fkey
ALTER TABLE ONLY twin.ottoq_twin_operator_state ADD CONSTRAINT ottoq_twin_operator_state_source_name_fkey FOREIGN KEY (source_name) REFERENCES twin.ottoq_twin_operators(source_name);
-- @@ constraint_f twin.ottoq_twin_operators.ottoq_twin_operators_depot_id_fkey
ALTER TABLE ONLY twin.ottoq_twin_operators ADD CONSTRAINT ottoq_twin_operators_depot_id_fkey FOREIGN KEY (depot_id) REFERENCES public.depots(id);
-- @@ constraint_f twin.ottoq_twin_operators.ottoq_twin_operators_key_id_fkey
ALTER TABLE ONLY twin.ottoq_twin_operators ADD CONSTRAINT ottoq_twin_operators_key_id_fkey FOREIGN KEY (key_id) REFERENCES public.ottow_api_keys(id);
