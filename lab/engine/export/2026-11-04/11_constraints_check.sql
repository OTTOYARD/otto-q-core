-- 11_constraints_check.sql: 411 statements, exported from production's catalog
-- @@ constraint_c public.ab_tests.ab_tests_status_check
ALTER TABLE ONLY public.ab_tests ADD CONSTRAINT ab_tests_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'running'::text, 'analyzing'::text, 'concluded'::text, 'cancelled'::text, 'aborted'::text])));
-- @@ constraint_c public.ab_tests.ab_tests_traffic_split_pct_check
ALTER TABLE ONLY public.ab_tests ADD CONSTRAINT ab_tests_traffic_split_pct_check CHECK (((traffic_split_pct >= 0) AND (traffic_split_pct <= 100)));
-- @@ constraint_c public.accuracy_alerts.accuracy_alerts_severity_check
ALTER TABLE ONLY public.accuracy_alerts ADD CONSTRAINT accuracy_alerts_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'critical'::text])));
-- @@ constraint_c public.accuracy_slos.accuracy_slos_accuracy_threshold_check
ALTER TABLE ONLY public.accuracy_slos ADD CONSTRAINT accuracy_slos_accuracy_threshold_check CHECK (((accuracy_threshold > (0)::numeric) AND (accuracy_threshold <= (1)::numeric)));
-- @@ constraint_c public.accuracy_slos.accuracy_slos_slo_target_check
ALTER TABLE ONLY public.accuracy_slos ADD CONSTRAINT accuracy_slos_slo_target_check CHECK (((slo_target > (0)::numeric) AND (slo_target <= (1)::numeric)));
-- @@ constraint_c public.ai_decision_log.ai_decision_log_status_check
ALTER TABLE ONLY public.ai_decision_log ADD CONSTRAINT ai_decision_log_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'auto_applied'::text, 'approved'::text, 'rejected'::text, 'expired'::text, 'error'::text])));
-- @@ constraint_c public.api_integrations.api_integrations_auth_type_check
ALTER TABLE ONLY public.api_integrations ADD CONSTRAINT api_integrations_auth_type_check CHECK ((auth_type = ANY (ARRAY['api_key'::text, 'oauth2'::text, 'mtls'::text, 'custom'::text])));
-- @@ constraint_c public.autonomous_action_log.autonomous_action_log_approval_method_check
ALTER TABLE ONLY public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_approval_method_check CHECK ((approval_method = ANY (ARRAY['auto_threshold'::text, 'human_approved'::text, 'claude_reasoning'::text, 'cron_triggered'::text])));
-- @@ constraint_c public.autonomous_action_log.autonomous_action_log_confidence_check
ALTER TABLE ONLY public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)));
-- @@ constraint_c public.autonomous_action_log.autonomous_action_log_status_check
ALTER TABLE ONLY public.autonomous_action_log ADD CONSTRAINT autonomous_action_log_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'executing'::text, 'completed'::text, 'failed'::text, 'rolled_back'::text, 'skipped'::text])));
-- @@ constraint_c public.cuopt_invocation_log.cuopt_invocation_log_stage_check
ALTER TABLE ONLY public.cuopt_invocation_log ADD CONSTRAINT cuopt_invocation_log_stage_check CHECK ((stage = ANY (ARRAY['sql_gate'::text, 'edge'::text])));
-- @@ constraint_c public.data_quality_errors.data_quality_errors_error_type_check
ALTER TABLE ONLY public.data_quality_errors ADD CONSTRAINT data_quality_errors_error_type_check CHECK ((error_type = ANY (ARRAY['null_required_field'::text, 'schema_mismatch'::text, 'out_of_range'::text, 'duplicate'::text, 'stale'::text, 'monotonic_violation'::text, 'referential_integrity'::text, 'unit_mismatch'::text, 'physical_implausibility'::text, 'contract_violation'::text, 'other'::text])));
-- @@ constraint_c public.data_quality_errors.data_quality_errors_severity_check
ALTER TABLE ONLY public.data_quality_errors ADD CONSTRAINT data_quality_errors_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'error'::text, 'critical'::text])));
-- @@ constraint_c public.decision_fusion_log.decision_fusion_log_fusion_method_check
ALTER TABLE ONLY public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_fusion_method_check CHECK ((fusion_method = ANY (ARRAY['weighted_sum'::text, 'bayesian'::text, 'rule_cascade'::text, 'claude_reasoning'::text, 'ensemble_vote'::text, 'hybrid'::text])));
-- @@ constraint_c public.decision_fusion_log.decision_fusion_log_trigger_type_check
ALTER TABLE ONLY public.decision_fusion_log ADD CONSTRAINT decision_fusion_log_trigger_type_check CHECK ((trigger_type = ANY (ARRAY['scheduled_cycle'::text, 'threshold_breach'::text, 'external_event'::text, 'schedule_change'::text, 'manual_request'::text, 'cascade'::text])));
-- @@ constraint_c public.demand_shaping_plans.demand_shaping_plans_status_check
ALTER TABLE ONLY public.demand_shaping_plans ADD CONSTRAINT demand_shaping_plans_status_check CHECK ((status = ANY (ARRAY['generated'::text, 'applied'::text, 'superseded'::text, 'rejected'::text])));
-- @@ constraint_c public.depot_visit_reports.depot_visit_reports_redeployment_status_check
ALTER TABLE ONLY public.depot_visit_reports ADD CONSTRAINT depot_visit_reports_redeployment_status_check CHECK (((redeployment_status IS NULL) OR (redeployment_status = ANY (ARRAY['redeployed'::text, 'held'::text, 'sequestered'::text, 'maintenance_required'::text, 'incomplete'::text]))));
-- @@ constraint_c public.depots.chk_depot_feed_mode
ALTER TABLE ONLY public.depots ADD CONSTRAINT chk_depot_feed_mode CHECK ((feed_mode = ANY (ARRAY['sim'::text, 'external'::text])));
-- @@ constraint_c public.depots.depots_status_check
ALTER TABLE ONLY public.depots ADD CONSTRAINT depots_status_check CHECK ((status = ANY (ARRAY['planning'::text, 'construction'::text, 'active'::text, 'maintenance'::text, 'decommissioned'::text])));
-- @@ constraint_c public.downstream_action_contracts.downstream_action_contracts_downstream_system_check
ALTER TABLE ONLY public.downstream_action_contracts ADD CONSTRAINT downstream_action_contracts_downstream_system_check CHECK ((downstream_system = ANY (ARRAY['ocpp_charger'::text, 'fleet_dispatch'::text, 'core_scheduler'::text, 'bess_controller'::text, 'solar_inverter'::text, 'hvac_controller'::text, 'ops_notification'::text, 'utility_api'::text, 'field_ops_app'::text, 'none'::text])));
-- @@ constraint_c public.downstream_action_contracts.downstream_action_contracts_transport_method_check
ALTER TABLE ONLY public.downstream_action_contracts ADD CONSTRAINT downstream_action_contracts_transport_method_check CHECK ((transport_method = ANY (ARRAY['http_post'::text, 'http_put'::text, 'websocket'::text, 'mqtt'::text, 'grpc'::text, 'ocpp_messaging'::text, 'internal_call'::text])));
-- @@ constraint_c public.early_recall_log.early_recall_log_disruption_impact_check
ALTER TABLE ONLY public.early_recall_log ADD CONSTRAINT early_recall_log_disruption_impact_check CHECK ((disruption_impact = ANY (ARRAY['none'::text, 'minor'::text, 'moderate'::text, 'major'::text])));
-- @@ constraint_c public.emergency_queue_insertions.emergency_queue_insertions_disruption_score_check
ALTER TABLE ONLY public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_disruption_score_check CHECK (((disruption_score >= 0) AND (disruption_score <= 100)));
-- @@ constraint_c public.emergency_queue_insertions.emergency_queue_insertions_status_check
ALTER TABLE ONLY public.emergency_queue_insertions ADD CONSTRAINT emergency_queue_insertions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'completed'::text, 'cancelled'::text])));
-- @@ constraint_c public.exceptions.exceptions_required_resolver_role_check
ALTER TABLE ONLY public.exceptions ADD CONSTRAINT exceptions_required_resolver_role_check CHECK (((required_resolver_role IS NULL) OR (required_resolver_role = ANY (ARRAY['tech'::text, 'oem'::text, 'either'::text]))));
-- @@ constraint_c public.exceptions.exceptions_resolution_required_before_check
ALTER TABLE ONLY public.exceptions ADD CONSTRAINT exceptions_resolution_required_before_check CHECK (((resolution_required_before IS NULL) OR (resolution_required_before = ANY (ARRAY['next_stall'::text, 'next_service'::text, 'redeployment'::text]))));
-- @@ constraint_c public.external_factor_sources.external_factor_sources_factor_type_check
ALTER TABLE ONLY public.external_factor_sources ADD CONSTRAINT external_factor_sources_factor_type_check CHECK ((factor_type = ANY (ARRAY['weather'::text, 'grid_pricing'::text, 'grid_dr_signal'::text, 'traffic'::text, 'incident_feed'::text, 'air_quality'::text, 'calendar_event'::text, 'solar_forecast'::text, 'carbon_intensity'::text, 'utility_curtailment'::text, 'custom'::text])));
-- @@ constraint_c public.external_factor_sources.external_factor_sources_fallback_strategy_check
ALTER TABLE ONLY public.external_factor_sources ADD CONSTRAINT external_factor_sources_fallback_strategy_check CHECK ((fallback_strategy = ANY (ARRAY['last_known'::text, 'historical_average'::text, 'manual_override'::text, 'fail_closed'::text])));
-- @@ constraint_c public.external_factor_sources.external_factor_sources_health_status_check
ALTER TABLE ONLY public.external_factor_sources ADD CONSTRAINT external_factor_sources_health_status_check CHECK ((health_status = ANY (ARRAY['healthy'::text, 'degraded'::text, 'stale'::text, 'down'::text, 'unknown'::text])));
-- @@ constraint_c public.external_factor_sources.external_factor_sources_poll_mode_check
ALTER TABLE ONLY public.external_factor_sources ADD CONSTRAINT external_factor_sources_poll_mode_check CHECK ((poll_mode = ANY (ARRAY['pull'::text, 'push'::text, 'scheduled_batch'::text])));
-- @@ constraint_c public.fleet_features_daily.fleet_features_daily_confidence_check
ALTER TABLE ONLY public.fleet_features_daily ADD CONSTRAINT fleet_features_daily_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)));
-- @@ constraint_c public.fleet_features_daily.fleet_features_daily_feature_group_check
ALTER TABLE ONLY public.fleet_features_daily ADD CONSTRAINT fleet_features_daily_feature_group_check CHECK ((feature_group = ANY (ARRAY['charge_patterns'::text, 'service_patterns'::text, 'demand_patterns'::text, 'arrival_patterns'::text, 'incident_patterns'::text, 'energy_patterns'::text, 'queue_patterns'::text, 'cross_depot_cohort'::text])));
-- @@ constraint_c public.fleet_features_daily.fleet_features_daily_scope_check
ALTER TABLE ONLY public.fleet_features_daily ADD CONSTRAINT fleet_features_daily_scope_check CHECK ((scope = ANY (ARRAY['fleet'::text, 'oem'::text, 'region'::text, 'depot_size_cohort'::text, 'vehicle_model'::text, 'service_type'::text])));
-- @@ constraint_c public.fleet_operators.fleet_operators_contract_tier_check
ALTER TABLE ONLY public.fleet_operators ADD CONSTRAINT fleet_operators_contract_tier_check CHECK ((contract_tier = ANY (ARRAY['standard'::text, 'premium'::text])));
-- @@ constraint_c public.fleet_operators.fleet_operators_default_target_soc_check
ALTER TABLE ONLY public.fleet_operators ADD CONSTRAINT fleet_operators_default_target_soc_check CHECK (((default_target_soc >= 20) AND (default_target_soc <= 100)));
-- @@ constraint_c public.fleet_operators.fleet_operators_oem_acceptance_on_timeout_check
ALTER TABLE ONLY public.fleet_operators ADD CONSTRAINT fleet_operators_oem_acceptance_on_timeout_check CHECK ((oem_acceptance_on_timeout = ANY (ARRAY['auto_accept'::text, 'hold'::text, 'escalate'::text])));
-- @@ constraint_c public.fleet_operators.fleet_operators_progression_acceptance_mode_check
ALTER TABLE ONLY public.fleet_operators ADD CONSTRAINT fleet_operators_progression_acceptance_mode_check CHECK ((progression_acceptance_mode = ANY (ARRAY['auto'::text, 'oem_webhook_final_only'::text, 'oem_webhook_required'::text, 'tech_confirm_only'::text])));
-- @@ constraint_c public.maintenance_log.maintenance_log_pass_fail_check
ALTER TABLE ONLY public.maintenance_log ADD CONSTRAINT maintenance_log_pass_fail_check CHECK ((pass_fail = ANY (ARRAY['pass'::text, 'fail'::text, 'conditional'::text])));
-- @@ constraint_c public.maintenance_schedules.maintenance_schedules_status_check
ALTER TABLE ONLY public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'completed'::text, 'cancelled'::text])));
-- @@ constraint_c public.model_tuning_runs.model_tuning_runs_status_check
ALTER TABLE ONLY public.model_tuning_runs ADD CONSTRAINT model_tuning_runs_status_check CHECK ((status = ANY (ARRAY['running'::text, 'completed'::text, 'evaluating'::text, 'confirmed'::text, 'rolled_back'::text, 'failed'::text])));
-- @@ constraint_c public.model_tuning_runs.model_tuning_runs_trigger_type_check
ALTER TABLE ONLY public.model_tuning_runs ADD CONSTRAINT model_tuning_runs_trigger_type_check CHECK ((trigger_type = ANY (ARRAY['scheduled'::text, 'accuracy_drift'::text, 'manual'::text, 'threshold_breach'::text])));
-- @@ constraint_c public.model_tuning_runs.model_tuning_runs_tuning_method_check
ALTER TABLE ONLY public.model_tuning_runs ADD CONSTRAINT model_tuning_runs_tuning_method_check CHECK ((tuning_method = ANY (ARRAY['gradient_free'::text, 'bayesian'::text, 'grid_search'::text, 'manual_override'::text, 'rollback'::text])));
-- @@ constraint_c public.model_versions.model_versions_deployment_stage_check
ALTER TABLE ONLY public.model_versions ADD CONSTRAINT model_versions_deployment_stage_check CHECK (((deployment_stage IS NULL) OR (deployment_stage = ANY (ARRAY['training'::text, 'staging'::text, 'canary'::text, 'active'::text, 'rollback'::text, 'retired'::text]))));
-- @@ constraint_c public.model_versions.model_versions_source_check
ALTER TABLE ONLY public.model_versions ADD CONSTRAINT model_versions_source_check CHECK ((source = ANY (ARRAY['seed'::text, 'manual'::text, 'nelder_mead_tuning'::text, 'bayesian_tuning'::text, 'grid_search'::text, 'ab_test_winner'::text, 'rollback'::text, 'partner_override'::text])));
-- @@ constraint_c public.model_versions.model_versions_status_check
ALTER TABLE ONLY public.model_versions ADD CONSTRAINT model_versions_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'candidate'::text, 'active'::text, 'archived'::text, 'deprecated'::text, 'rollback_target'::text])));
-- @@ constraint_c public.ottoq_ab_runs.ottoq_ab_runs_policy_check
ALTER TABLE ONLY public.ottoq_ab_runs ADD CONSTRAINT ottoq_ab_runs_policy_check CHECK ((policy = ANY (ARRAY['otto_q'::text, 'greedy'::text, 'fifo'::text, 'manual'::text])));
-- @@ constraint_c public.ottoq_agent_charge_orders.ottoq_agent_charge_orders_status_check
ALTER TABLE ONLY public.ottoq_agent_charge_orders ADD CONSTRAINT ottoq_agent_charge_orders_status_check CHECK ((status = ANY (ARRAY['accepted'::text, 'partial'::text, 'rejected'::text, 'refused'::text])));
-- @@ constraint_c public.ottoq_agent_demo_passcode.ottoq_agent_demo_passcode_hash_check
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ADD CONSTRAINT ottoq_agent_demo_passcode_hash_check CHECK (((passcode_hash IS NULL) OR (passcode_hash ~ '^\$2[abxy]?\$[0-9]{2}\$'::text)));
-- @@ constraint_c public.ottoq_agent_demo_passcode.ottoq_agent_demo_passcode_minutes_check
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ADD CONSTRAINT ottoq_agent_demo_passcode_minutes_check CHECK (((session_minutes >= 15) AND (session_minutes <= 1440)));
-- @@ constraint_c public.ottoq_agent_demo_passcode.ottoq_agent_demo_passcode_on_check
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ADD CONSTRAINT ottoq_agent_demo_passcode_on_check CHECK (((NOT enabled) OR (passcode_hash IS NOT NULL)));
-- @@ constraint_c public.ottoq_agent_demo_passcode.ottoq_agent_demo_passcode_twin_check
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ADD CONSTRAINT ottoq_agent_demo_passcode_twin_check CHECK ((depot_id = '11111111-1111-1111-1111-111111111111'::uuid));
-- @@ constraint_c public.ottoq_agent_pass_evidence.ottoq_agent_pass_board_hash_matches
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ADD CONSTRAINT ottoq_agent_pass_board_hash_matches CHECK (((board_sha256_client IS NULL) OR (board_sha256_client = board_sha256)));
-- @@ constraint_c public.ottoq_agent_pass_evidence.ottoq_agent_pass_consulted_coherent
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ADD CONSTRAINT ottoq_agent_pass_consulted_coherent CHECK (((outcome_class = 'solver_only'::text) = (NOT consulted)));
-- @@ constraint_c public.ottoq_agent_pass_evidence.ottoq_agent_pass_evidence_prompt_sha256_check
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ADD CONSTRAINT ottoq_agent_pass_evidence_prompt_sha256_check CHECK (((prompt_sha256 IS NULL) OR (prompt_sha256 ~ '^[0-9a-f]{64}$'::text)));
-- @@ constraint_c public.ottoq_agent_pass_evidence.ottoq_agent_pass_outcome_class_known
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ADD CONSTRAINT ottoq_agent_pass_outcome_class_known CHECK ((outcome_class = ANY (ARRAY['changed_state'::text, 'echo'::text, 'advisory'::text, 'no_effect'::text, 'solver_only'::text, 'fallback'::text, 'failed'::text])));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_capabilities_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_capabilities_check CHECK (((cardinality(capabilities) > 0) AND (capabilities <@ ARRAY['read'::text, 'note'::text, 'request_recall'::text, 'request_ops_action'::text, 'request_adjustment'::text, 'owner_settings'::text])));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_depot_ops_scope_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_depot_ops_scope_check CHECK (((kind <> 'depot_ops'::text) OR (fleet_operator_id IS NULL)));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_display_name_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_display_name_check CHECK (((display_name IS NULL) OR (((length(display_name) >= 1) AND (length(display_name) <= 60)) AND (display_name !~ '[[:cntrl:]]'::text))));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_fleet_scope_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_fleet_scope_check CHECK (((kind <> 'fleet_operator'::text) OR (fleet_operator_id IS NOT NULL)));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_kind_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_kind_check CHECK ((kind = ANY (ARRAY['personal'::text, 'fleet_operator'::text, 'depot_ops'::text])));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_name_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_name_check CHECK ((name ~ '^[a-z0-9][a-z0-9_.-]{1,62}$'::text));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_ops_scope_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_ops_scope_check CHECK (((NOT ('request_ops_action'::text = ANY (capabilities))) OR (fleet_operator_id IS NULL)));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_origin_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_origin_check CHECK ((origin = ANY (ARRAY['issued'::text, 'passcode'::text, 'oauth'::text])));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_origin_shape_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_origin_shape_check CHECK (
CASE origin
    WHEN 'issued'::text THEN ((token_prefix ~~ 'oqa\_%'::text) AND (expires_at IS NULL))
    WHEN 'passcode'::text THEN ((token_prefix ~~ 'oqs\_%'::text) AND (expires_at IS NOT NULL) AND (display_name IS NOT NULL) AND (fleet_operator_id IS NOT NULL) AND (kind = 'personal'::text) AND (capabilities = ARRAY['note'::text, 'owner_settings'::text, 'read'::text]))
    WHEN 'oauth'::text THEN ((token_prefix ~~ 'oqt\_%'::text) AND (expires_at IS NULL) AND (display_name IS NOT NULL) AND (fleet_operator_id IS NOT NULL) AND (kind = 'personal'::text) AND (capabilities = ARRAY['note'::text, 'owner_settings'::text, 'read'::text]))
    ELSE false
END);
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_owner_scope_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_owner_scope_check CHECK (((NOT ('owner_settings'::text = ANY (capabilities))) OR (fleet_operator_id IS NOT NULL)));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_pending_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_pending_check CHECK (((max_pending >= 1) AND (max_pending <= 200)));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_rate_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_rate_check CHECK (((rate_limit_per_min >= 1) AND (rate_limit_per_min <= 600)));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_revoked_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_revoked_check CHECK (((status = 'revoked'::text) = (revoked_at IS NOT NULL)));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_status_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_status_check CHECK ((status = ANY (ARRAY['active'::text, 'revoked'::text])));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_token_hash_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_token_hash_check CHECK ((token_hash ~ '^[0-9a-f]{64}$'::text));
-- @@ constraint_c public.ottoq_agent_principals.ottoq_agent_principals_token_prefix_check
ALTER TABLE ONLY public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_token_prefix_check CHECK ((token_prefix ~ '^oq[ast]_[0-9a-f]{8}$'::text));
-- @@ constraint_c public.ottoq_agent_prompts.ottoq_agent_prompts_key_is_text_hash
ALTER TABLE ONLY public.ottoq_agent_prompts ADD CONSTRAINT ottoq_agent_prompts_key_is_text_hash CHECK ((prompt_sha256 = text_sha256));
-- @@ constraint_c public.ottoq_agent_prompts.ottoq_agent_prompts_prompt_sha256_check
ALTER TABLE ONLY public.ottoq_agent_prompts ADD CONSTRAINT ottoq_agent_prompts_prompt_sha256_check CHECK ((prompt_sha256 ~ '^[0-9a-f]{64}$'::text));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_body_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_body_check CHECK (((body IS NULL) OR (char_length(body) <= 4000)));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_decider_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_decider_check CHECK (((decided_by_kind IS NULL) OR (decided_by_kind = ANY (ARRAY['crew'::text, 'operator'::text]))));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_decision_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_decision_check CHECK ((((status = 'pending'::text) AND (decision IS NULL) AND (decided_at IS NULL)) OR ((status = 'expired'::text) AND (decision IS NULL) AND (decided_at IS NULL)) OR ((status = 'declined'::text) AND (decision = 'declined'::text) AND (decided_at IS NOT NULL) AND (decided_by_kind IS NOT NULL)) OR ((status = ANY (ARRAY['acknowledged'::text, 'applied'::text, 'refused_by_engine'::text, 'approved_no_engine_door'::text, 'approved_not_applied'::text, 'apply_failed'::text])) AND (decision = 'approved'::text) AND (decided_at IS NOT NULL) AND (decided_by_kind IS NOT NULL))));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_expiry_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_expiry_check CHECK ((expires_at > created_at));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_idempotency_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_idempotency_check CHECK (((idempotency_key IS NULL) OR (idempotency_key ~ '^[A-Za-z0-9._:-]{1,100}$'::text)));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_kind_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_kind_check CHECK ((kind = ANY (ARRAY['note'::text, 'recall_vehicle'::text, 'ops_action'::text, 'adjustment'::text])));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_kind_status_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_kind_status_check CHECK ((((kind = 'note'::text) AND (status = ANY (ARRAY['pending'::text, 'declined'::text, 'expired'::text, 'acknowledged'::text]))) OR ((kind <> 'note'::text) AND (status <> 'acknowledged'::text))));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_ops_action_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_ops_action_check CHECK (((kind <> 'ops_action'::text) OR ((payload ? 'action'::text) AND (vehicle_id IS NULL))));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_payload_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_payload_check CHECK (((jsonb_typeof(payload) = 'object'::text) AND (octet_length((payload)::text) <= 4000)));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_priority_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_recall_vehicle_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_recall_vehicle_check CHECK (((kind <> 'recall_vehicle'::text) OR (vehicle_id IS NOT NULL)));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_status_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'declined'::text, 'expired'::text, 'acknowledged'::text, 'applied'::text, 'refused_by_engine'::text, 'approved_no_engine_door'::text, 'approved_not_applied'::text, 'apply_failed'::text])));
-- @@ constraint_c public.ottoq_agent_requests.ottoq_agent_requests_title_check
ALTER TABLE ONLY public.ottoq_agent_requests ADD CONSTRAINT ottoq_agent_requests_title_check CHECK (((char_length(title) >= 1) AND (char_length(title) <= 140)));
-- @@ constraint_c public.ottoq_anomaly_detectors.ottoq_anomaly_detectors_category_check
ALTER TABLE ONLY public.ottoq_anomaly_detectors ADD CONSTRAINT ottoq_anomaly_detectors_category_check CHECK ((category = ANY (ARRAY['charging'::text, 'washing'::text, 'calibration'::text, 'arrival'::text, 'state_of_charge'::text, 'telemetry'::text, 'energy'::text, 'operational'::text])));
-- @@ constraint_c public.ottoq_anomaly_detectors.ottoq_anomaly_detectors_method_check
ALTER TABLE ONLY public.ottoq_anomaly_detectors ADD CONSTRAINT ottoq_anomaly_detectors_method_check CHECK ((method = ANY (ARRAY['threshold'::text, 'z_score'::text, 'iqr'::text, 'rate_of_change'::text, 'rolling_window'::text, 'ml_isoforest'::text, 'ml_lstm'::text, 'custom'::text])));
-- @@ constraint_c public.ottoq_anomaly_detectors.ottoq_anomaly_detectors_status_check
ALTER TABLE ONLY public.ottoq_anomaly_detectors ADD CONSTRAINT ottoq_anomaly_detectors_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'shadow'::text, 'active'::text, 'deprecated'::text, 'archived'::text])));
-- @@ constraint_c public.ottoq_anomaly_observations.ottoq_anomaly_observations_severity_check
ALTER TABLE ONLY public.ottoq_anomaly_observations ADD CONSTRAINT ottoq_anomaly_observations_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
-- @@ constraint_c public.ottoq_audit_bundles.ottoq_audit_bundles_format_check
ALTER TABLE ONLY public.ottoq_audit_bundles ADD CONSTRAINT ottoq_audit_bundles_format_check CHECK ((format = ANY (ARRAY['jsonl'::text, 'json'::text, 'csv'::text, 'zip'::text, 'pdf'::text, 'custom'::text])));
-- @@ constraint_c public.ottoq_audit_reports.ottoq_audit_reports_check
ALTER TABLE ONLY public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_check CHECK ((window_end > window_start));
-- @@ constraint_c public.ottoq_audit_reports.ottoq_audit_reports_format_check
ALTER TABLE ONLY public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_format_check CHECK ((format = ANY (ARRAY['json'::text, 'csv'::text, 'pdf'::text, 'xml'::text, 'custom'::text])));
-- @@ constraint_c public.ottoq_audit_reports.ottoq_audit_reports_generation_status_check
ALTER TABLE ONLY public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_generation_status_check CHECK ((generation_status = ANY (ARRAY['pending'::text, 'generating'::text, 'completed'::text, 'failed'::text, 'expired'::text])));
-- @@ constraint_c public.ottoq_audit_reports.ottoq_audit_reports_report_type_check
ALTER TABLE ONLY public.ottoq_audit_reports ADD CONSTRAINT ottoq_audit_reports_report_type_check CHECK ((report_type = ANY (ARRAY['sla_conformance'::text, 'visit_summary'::text, 'incident_forensic'::text, 'energy_attribution'::text, 'predictive_accuracy'::text, 'safety_event_summary'::text, 'override_audit'::text, 'cross_depot_benchmark'::text, 'regulatory_export'::text, 'oem_dashboard_snapshot'::text, 'counterfactual_analysis'::text, 'custom'::text])));
-- @@ constraint_c public.ottoq_bess_units.ottoq_bess_units_current_state_check
ALTER TABLE ONLY public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_current_state_check CHECK ((current_state = ANY (ARRAY['online'::text, 'offline'::text, 'charging'::text, 'discharging'::text, 'standby'::text, 'fault'::text])));
-- @@ constraint_c public.ottoq_bess_units.ottoq_bess_units_hvac_rated_ambient_c_check
ALTER TABLE ONLY public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_hvac_rated_ambient_c_check CHECK (((hvac_rated_ambient_c >= (20)::numeric) AND (hvac_rated_ambient_c <= (70)::numeric)));
-- @@ constraint_c public.ottoq_bess_units.ottoq_bess_units_hvac_rated_kw_check
ALTER TABLE ONLY public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_hvac_rated_kw_check CHECK (((hvac_rated_kw IS NULL) OR (hvac_rated_kw >= (0)::numeric)));
-- @@ constraint_c public.ottoq_bess_units.ottoq_bess_units_hvac_rated_min_ambient_c_check
ALTER TABLE ONLY public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_hvac_rated_min_ambient_c_check CHECK (((hvac_rated_min_ambient_c >= ('-60'::integer)::numeric) AND (hvac_rated_min_ambient_c <= (10)::numeric)));
-- @@ constraint_c public.ottoq_bess_units.ottoq_bess_units_hvac_setpoint_c_check
ALTER TABLE ONLY public.ottoq_bess_units ADD CONSTRAINT ottoq_bess_units_hvac_setpoint_c_check CHECK (((hvac_setpoint_c >= (0)::numeric) AND (hvac_setpoint_c <= (45)::numeric)));
-- @@ constraint_c public.ottoq_calibration_correlations.ottoq_calibration_correlations_method_check
ALTER TABLE ONLY public.ottoq_calibration_correlations ADD CONSTRAINT ottoq_calibration_correlations_method_check CHECK ((method = ANY (ARRAY['pearson'::text, 'spearman'::text, 'kendall'::text])));
-- @@ constraint_c public.ottoq_calibration_datasets.ottoq_calibration_datasets_domain_check
ALTER TABLE ONLY public.ottoq_calibration_datasets ADD CONSTRAINT ottoq_calibration_datasets_domain_check CHECK ((domain = ANY (ARRAY['charging'::text, 'arrivals'::text, 'incidents'::text, 'weather'::text, 'grid'::text, 'reliability'::text, 'fleet'::text, 'energy'::text])));
-- @@ constraint_c public.ottoq_calibration_datasets.ottoq_calibration_datasets_status_check
ALTER TABLE ONLY public.ottoq_calibration_datasets ADD CONSTRAINT ottoq_calibration_datasets_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'ingested'::text, 'stale'::text, 'failed'::text, 'partial'::text])));
-- @@ constraint_c public.ottoq_calibration_profiles.ottoq_calibration_profiles_profile_kind_check
ALTER TABLE ONLY public.ottoq_calibration_profiles ADD CONSTRAINT ottoq_calibration_profiles_profile_kind_check CHECK ((profile_kind = ANY (ARRAY['hourly_24'::text, 'daily_7'::text, 'monthly_12'::text, 'custom'::text])));
-- @@ constraint_c public.ottoq_cert_queue.ottoq_cert_queue_policy_check
ALTER TABLE ONLY public.ottoq_cert_queue ADD CONSTRAINT ottoq_cert_queue_policy_check CHECK ((policy = ANY (ARRAY['otto_q'::text, 'greedy'::text, 'fifo'::text])));
-- @@ constraint_c public.ottoq_cert_queue.ottoq_cert_queue_scenario_check
ALTER TABLE ONLY public.ottoq_cert_queue ADD CONSTRAINT ottoq_cert_queue_scenario_check CHECK ((scenario = ANY (ARRAY['shift'::text, 'wave'::text])));
-- @@ constraint_c public.ottoq_cert_queue.ottoq_cert_queue_status_check
ALTER TABLE ONLY public.ottoq_cert_queue ADD CONSTRAINT ottoq_cert_queue_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'done'::text, 'error'::text])));
-- @@ constraint_c public.ottoq_challenger_findings.ottoq_challenger_findings_grade_check
ALTER TABLE ONLY public.ottoq_challenger_findings ADD CONSTRAINT ottoq_challenger_findings_grade_check CHECK ((grade = ANY (ARRAY['confirmed'::text, 'refuted'::text, 'inconclusive'::text])));
-- @@ constraint_c public.ottoq_challenger_findings.ottoq_challenger_findings_question_check
ALTER TABLE ONLY public.ottoq_challenger_findings ADD CONSTRAINT ottoq_challenger_findings_question_check CHECK ((question = ANY (ARRAY['charging_above_floor_while_cars_wait'::text, 'charger_offerable_while_cars_wait'::text, 'charger_faulted_while_cars_wait'::text])));
-- @@ constraint_c public.ottoq_challenger_findings.ottoq_challenger_findings_status_check
ALTER TABLE ONLY public.ottoq_challenger_findings ADD CONSTRAINT ottoq_challenger_findings_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])));
-- @@ constraint_c public.ottoq_channel_health.ottoq_channel_health_channel
ALTER TABLE ONLY public.ottoq_channel_health ADD CONSTRAINT ottoq_channel_health_channel CHECK ((channel = ANY (ARRAY['cron'::text, 'run_tick'::text, 'agent_passes'::text, 'agent_model'::text, 'cpsat'::text, 'pg_net'::text])));
-- @@ constraint_c public.ottoq_channel_health.ottoq_channel_health_status
ALTER TABLE ONLY public.ottoq_channel_health ADD CONSTRAINT ottoq_channel_health_status CHECK ((status = ANY (ARRAY['green'::text, 'amber'::text, 'red'::text, 'idle'::text, 'unknown'::text])));
-- @@ constraint_c public.ottoq_charge_clock_fits.ottoq_charge_clock_fits_model_check
ALTER TABLE ONLY public.ottoq_charge_clock_fits ADD CONSTRAINT ottoq_charge_clock_fits_model_check CHECK ((model = 'charge_time_v2'::text));
-- @@ constraint_c public.ottoq_charge_duration_ledger.ottoq_charge_duration_ledger_source_kind_check
ALTER TABLE ONLY public.ottoq_charge_duration_ledger ADD CONSTRAINT ottoq_charge_duration_ledger_source_kind_check CHECK ((source_kind = ANY (ARRAY['capture'::text, 'backfill'::text])));
-- @@ constraint_c public.ottoq_charge_fault_fits.ottoq_charge_fault_fits_model_check
ALTER TABLE ONLY public.ottoq_charge_fault_fits ADD CONSTRAINT ottoq_charge_fault_fits_model_check CHECK ((model = 'charge_fault_v1'::text));
-- @@ constraint_c public.ottoq_charge_order_hindsight.ottoq_charge_order_hindsight_outcome_ck
ALTER TABLE ONLY public.ottoq_charge_order_hindsight ADD CONSTRAINT ottoq_charge_order_hindsight_outcome_ck CHECK ((outcome = ANY (ARRAY['right_take'::text, 'neutral_take'::text, 'wrong_take'::text, 'missed_win'::text, 'right_refusal'::text, 'no_decision'::text, 'no_decision_mattered'::text])));
-- @@ constraint_c public.ottoq_charge_order_reattributions.ottoq_charge_order_reattributions_defect_ck
ALTER TABLE ONLY public.ottoq_charge_order_reattributions ADD CONSTRAINT ottoq_charge_order_reattributions_defect_ck CHECK ((defect ~ '^[a-z][a-z0-9_]{2,62}$'::text));
-- @@ constraint_c public.ottoq_charge_order_reattributions.ottoq_charge_order_reattributions_new_code_ck
ALTER TABLE ONLY public.ottoq_charge_order_reattributions ADD CONSTRAINT ottoq_charge_order_reattributions_new_code_ck CHECK ((supersedes_code_md5 <> code_md5));
-- @@ constraint_c public.ottoq_charge_order_regrades.ottoq_charge_order_hindsight_outcome_ck
ALTER TABLE ONLY public.ottoq_charge_order_regrades ADD CONSTRAINT ottoq_charge_order_hindsight_outcome_ck CHECK ((outcome = ANY (ARRAY['right_take'::text, 'neutral_take'::text, 'wrong_take'::text, 'missed_win'::text, 'right_refusal'::text, 'no_decision'::text, 'no_decision_mattered'::text])));
-- @@ constraint_c public.ottoq_charge_order_regrades.ottoq_charge_order_regrades_defect_ck
ALTER TABLE ONLY public.ottoq_charge_order_regrades ADD CONSTRAINT ottoq_charge_order_regrades_defect_ck CHECK ((defect ~ '^[a-z][a-z0-9_]{2,62}$'::text));
-- @@ constraint_c public.ottoq_charge_order_regrades.ottoq_charge_order_regrades_new_code_ck
ALTER TABLE ONLY public.ottoq_charge_order_regrades ADD CONSTRAINT ottoq_charge_order_regrades_new_code_ck CHECK ((supersedes_code_md5 <> code_md5));
-- @@ constraint_c public.ottoq_charge_window_calibration.ottoq_charge_window_calibration_alpha_check
ALTER TABLE ONLY public.ottoq_charge_window_calibration ADD CONSTRAINT ottoq_charge_window_calibration_alpha_check CHECK (((alpha > (0)::numeric) AND (alpha < 0.5)));
-- @@ constraint_c public.ottoq_charge_window_calibration.ottoq_charge_window_calibration_c0_check
ALTER TABLE ONLY public.ottoq_charge_window_calibration ADD CONSTRAINT ottoq_charge_window_calibration_c0_check CHECK ((c0 > (1)::numeric));
-- @@ constraint_c public.ottoq_charge_window_calibration.ottoq_charge_window_calibration_min_group_n_check
ALTER TABLE ONLY public.ottoq_charge_window_calibration ADD CONSTRAINT ottoq_charge_window_calibration_min_group_n_check CHECK ((min_group_n >= 1));
-- @@ constraint_c public.ottoq_command_actor_registry.ottoq_command_actor_registry_kind_check
ALTER TABLE ONLY public.ottoq_command_actor_registry ADD CONSTRAINT ottoq_command_actor_registry_kind_check CHECK ((kind = ANY (ARRAY['self'::text, 'operator'::text, 'external'::text])));
-- @@ constraint_c public.ottoq_counterfactuals.ottoq_counterfactuals_delta_direction_check
ALTER TABLE ONLY public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_delta_direction_check CHECK (((delta_direction IS NULL) OR (delta_direction = ANY (ARRAY['better'::text, 'worse'::text, 'neutral'::text, 'ambiguous'::text]))));
-- @@ constraint_c public.ottoq_counterfactuals.ottoq_counterfactuals_source_kind_check
ALTER TABLE ONLY public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_source_kind_check CHECK ((source_kind = ANY (ARRAY['decision'::text, 'recommendation'::text, 'prediction'::text, 'rule_evaluation'::text, 'override'::text])));
-- @@ constraint_c public.ottoq_counterfactuals.ottoq_counterfactuals_status_check
ALTER TABLE ONLY public.ottoq_counterfactuals ADD CONSTRAINT ottoq_counterfactuals_status_check CHECK ((status = ANY (ARRAY['running'::text, 'completed'::text, 'failed'::text, 'review'::text])));
-- @@ constraint_c public.ottoq_cuopt_deferrals.ottoq_cuopt_deferrals_state_ck
ALTER TABLE ONLY public.ottoq_cuopt_deferrals ADD CONSTRAINT ottoq_cuopt_deferrals_state_ck CHECK ((state = ANY (ARRAY['armed'::text, 'spent'::text, 'clear'::text])));
-- @@ constraint_c public.ottoq_data_drift_metrics.ottoq_data_drift_metrics_drift_severity_check
ALTER TABLE ONLY public.ottoq_data_drift_metrics ADD CONSTRAINT ottoq_data_drift_metrics_drift_severity_check CHECK ((drift_severity = ANY (ARRAY['none'::text, 'minor'::text, 'moderate'::text, 'severe'::text])));
-- @@ constraint_c public.ottoq_data_drift_metrics.ottoq_data_drift_metrics_scope_check
ALTER TABLE ONLY public.ottoq_data_drift_metrics ADD CONSTRAINT ottoq_data_drift_metrics_scope_check CHECK ((scope = ANY (ARRAY['global'::text, 'fleet_operator'::text, 'depot'::text, 'vehicle_class'::text])));
-- @@ constraint_c public.ottoq_decisions.ottoq_decisions_gate_check
ALTER TABLE ONLY public.ottoq_decisions ADD CONSTRAINT ottoq_decisions_gate_check CHECK ((gate = ANY (ARRAY['A'::text, 'B'::text])));
-- @@ constraint_c public.ottoq_decisions.ottoq_decisions_outcome_status_check
ALTER TABLE ONLY public.ottoq_decisions ADD CONSTRAINT ottoq_decisions_outcome_status_check CHECK ((outcome_status = ANY (ARRAY['enacted'::text, 'overridden_to_default'::text, 'deferred_noop'::text, 'errored'::text, 'noop_no_candidate'::text, 'shield_disarmed'::text, 'deferred_stale_entity'::text, 'context_insufficient'::text, 'deferred_site_power_cap'::text, 'deferred_tick_budget'::text])));
-- @@ constraint_c public.ottoq_depot_shifts.ottoq_depot_shifts_status_check
ALTER TABLE ONLY public.ottoq_depot_shifts ADD CONSTRAINT ottoq_depot_shifts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'draft'::text, 'archived'::text])));
-- @@ constraint_c public.ottoq_depot_staffing.ottoq_depot_staffing_headcount_check
ALTER TABLE ONLY public.ottoq_depot_staffing ADD CONSTRAINT ottoq_depot_staffing_headcount_check CHECK ((headcount >= 0));
-- @@ constraint_c public.ottoq_depot_staffing.ottoq_depot_staffing_role_check
ALTER TABLE ONLY public.ottoq_depot_staffing ADD CONSTRAINT ottoq_depot_staffing_role_check CHECK ((role = ANY (ARRAY['general_tech'::text, 'wash_supervisor'::text, 'service_tech'::text])));
-- @@ constraint_c public.ottoq_depot_tariffs.ottoq_depot_tariffs_season_check
ALTER TABLE ONLY public.ottoq_depot_tariffs ADD CONSTRAINT ottoq_depot_tariffs_season_check CHECK ((season = ANY (ARRAY['summer'::text, 'winter'::text, 'transition'::text])));
-- @@ constraint_c public.ottoq_determinism_verdict_ledger.ottoq_dvl_equal_matches_outcome
ALTER TABLE ONLY public.ottoq_determinism_verdict_ledger ADD CONSTRAINT ottoq_dvl_equal_matches_outcome CHECK (((outcome = 'passed'::text) = (equal AND complete)));
-- @@ constraint_c public.ottoq_determinism_verdict_ledger.ottoq_dvl_outcome_known
ALTER TABLE ONLY public.ottoq_determinism_verdict_ledger ADD CONSTRAINT ottoq_dvl_outcome_known CHECK ((outcome = ANY (ARRAY['passed'::text, 'failed'::text, 'inconclusive'::text])));
-- @@ constraint_c public.ottoq_determinism_verdict_ledger.ottoq_dvl_passed_means_no_disagreement
ALTER TABLE ONLY public.ottoq_determinism_verdict_ledger ADD CONSTRAINT ottoq_dvl_passed_means_no_disagreement CHECK (((outcome <> 'passed'::text) OR (cardinality(disagreeing_atoms) = 0)));
-- @@ constraint_c public.ottoq_dial_experiments.ottoq_dial_experiments_alpha
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_alpha CHECK (((alpha > (0)::numeric) AND (alpha <= 0.10)));
-- @@ constraint_c public.ottoq_dial_experiments.ottoq_dial_experiments_better
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_better CHECK ((primary_better = ANY (ARRAY['lower'::text, 'higher'::text])));
-- @@ constraint_c public.ottoq_dial_experiments.ottoq_dial_experiments_fixed
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_fixed CHECK (((jsonb_typeof(fixed_params) = 'object'::text) AND (NOT (fixed_params ? param_key))));
-- @@ constraint_c public.ottoq_dial_experiments.ottoq_dial_experiments_looks
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_looks CHECK (((first_look_pairs >= 6) AND (final_look_pairs >= first_look_pairs) AND (final_look_pairs <= 40)));
-- @@ constraint_c public.ottoq_dial_experiments.ottoq_dial_experiments_margins
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_margins CHECK (((guardrail_margin_pct >= (0)::numeric) AND (min_effect_pct >= (0)::numeric) AND (guardrail_alpha > (0)::numeric) AND (guardrail_alpha <= 0.5)));
-- @@ constraint_c public.ottoq_dial_experiments.ottoq_dial_experiments_not_harness
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_not_harness CHECK ((param_key <> ALL (ARRAY['cuopt_propose_enabled'::text, 'cuopt_first_refusal_max_defers'::text, 'orchestrator_agent_enabled'::text, 'proposer_seat'::text])));
-- @@ constraint_c public.ottoq_dial_experiments.ottoq_dial_experiments_sim_min_per_tick_chk
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_sim_min_per_tick_chk CHECK (((sim_min_per_tick >= 0.5) AND (sim_min_per_tick <= (30)::numeric)));
-- @@ constraint_c public.ottoq_dial_experiments.ottoq_dial_experiments_status
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_status CHECK ((status = ANY (ARRAY['active'::text, 'concluded'::text, 'abandoned'::text])));
-- @@ constraint_c public.ottoq_dial_experiments.ottoq_dial_experiments_ticks
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_ticks CHECK (((ticks >= 12) AND (ticks <= 96)));
-- @@ constraint_c public.ottoq_dial_experiments.ottoq_dial_experiments_values_differ
ALTER TABLE ONLY public.ottoq_dial_experiments ADD CONSTRAINT ottoq_dial_experiments_values_differ CHECK ((treatment_value <> control_value));
-- @@ constraint_c public.ottoq_dtc_catalog.ottoq_dtc_catalog_category_check
ALTER TABLE ONLY public.ottoq_dtc_catalog ADD CONSTRAINT ottoq_dtc_catalog_category_check CHECK ((category = ANY (ARRAY['perception'::text, 'planning'::text, 'hardware'::text, 'software'::text, 'weather_road'::text, 'operator'::text, 'powertrain'::text, 'sensor'::text])));
-- @@ constraint_c public.ottoq_dtc_catalog.ottoq_dtc_catalog_severity_check
ALTER TABLE ONLY public.ottoq_dtc_catalog ADD CONSTRAINT ottoq_dtc_catalog_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'minor'::text, 'moderate'::text, 'major'::text, 'safety_critical'::text])));
-- @@ constraint_c public.ottoq_emergency_invocations.ottoq_emergency_invocations_outcome_check
ALTER TABLE ONLY public.ottoq_emergency_invocations ADD CONSTRAINT ottoq_emergency_invocations_outcome_check CHECK ((outcome = ANY (ARRAY['in_progress'::text, 'completed'::text, 'partial'::text, 'failed'::text, 'cleared'::text])));
-- @@ constraint_c public.ottoq_emergency_protocols.ottoq_emergency_protocols_affects_scope_check
ALTER TABLE ONLY public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_affects_scope_check CHECK ((affects_scope = ANY (ARRAY['depot'::text, 'region'::text, 'system'::text, 'single_stall'::text, 'single_vehicle'::text])));
-- @@ constraint_c public.ottoq_emergency_protocols.ottoq_emergency_protocols_category_check
ALTER TABLE ONLY public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_category_check CHECK ((category = ANY (ARRAY['fire'::text, 'grid'::text, 'security'::text, 'weather'::text, 'connectivity'::text, 'sensor_failure'::text, 'manual_killswitch'::text, 'hazmat'::text, 'medical'::text, 'tornado'::text, 'flood'::text, 'earthquake'::text, 'other'::text])));
-- @@ constraint_c public.ottoq_emergency_protocols.ottoq_emergency_protocols_severity_check
ALTER TABLE ONLY public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_severity_check CHECK ((severity = ANY (ARRAY['warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
-- @@ constraint_c public.ottoq_emergency_protocols.ottoq_emergency_protocols_status_check
ALTER TABLE ONLY public.ottoq_emergency_protocols ADD CONSTRAINT ottoq_emergency_protocols_status_check CHECK ((status = ANY (ARRAY['active'::text, 'deprecated'::text, 'draft'::text])));
-- @@ constraint_c public.ottoq_enactment_branches.ottoq_enactment_branches_writer_side_check
ALTER TABLE ONLY public.ottoq_enactment_branches ADD CONSTRAINT ottoq_enactment_branches_writer_side_check CHECK ((writer_side = ANY (ARRAY['engine'::text, 'twin'::text, 'external'::text])));
-- @@ constraint_c public.ottoq_energy_commands.ottoq_energy_commands_command_type_check
ALTER TABLE ONLY public.ottoq_energy_commands ADD CONSTRAINT ottoq_energy_commands_command_type_check CHECK ((command_type = ANY (ARRAY['charge_cap_kw'::text, 'bess_setpoint_kw'::text, 'load_shed'::text, 'tou_shift'::text, 'clear'::text])));
-- @@ constraint_c public.ottoq_energy_commands.ottoq_energy_commands_status_check
ALTER TABLE ONLY public.ottoq_energy_commands ADD CONSTRAINT ottoq_energy_commands_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'executed'::text, 'superseded'::text, 'failed'::text])));
-- @@ constraint_c public.ottoq_energy_rates.ottoq_energy_rates_energy_cents_kwh_check
ALTER TABLE ONLY public.ottoq_energy_rates ADD CONSTRAINT ottoq_energy_rates_energy_cents_kwh_check CHECK ((energy_cents_kwh >= (0)::numeric));
-- @@ constraint_c public.ottoq_energy_rates.ottoq_energy_rates_fixed_usd_month_check
ALTER TABLE ONLY public.ottoq_energy_rates ADD CONSTRAINT ottoq_energy_rates_fixed_usd_month_check CHECK ((fixed_usd_month >= (0)::numeric));
-- @@ constraint_c public.ottoq_energy_rates.ottoq_energy_rates_fuel_adj_cents_kwh_check
ALTER TABLE ONLY public.ottoq_energy_rates ADD CONSTRAINT ottoq_energy_rates_fuel_adj_cents_kwh_check CHECK ((fuel_adj_cents_kwh >= (0)::numeric));
-- @@ constraint_c public.ottoq_energy_rates.ottoq_energy_rates_rate_code_check
ALTER TABLE ONLY public.ottoq_energy_rates ADD CONSTRAINT ottoq_energy_rates_rate_code_check CHECK ((rate_code ~ '^[a-z0-9_]+$'::text));
-- @@ constraint_c public.ottoq_energy_rates.ottoq_energy_rates_sources_check
ALTER TABLE ONLY public.ottoq_energy_rates ADD CONSTRAINT ottoq_energy_rates_sources_check CHECK (((jsonb_typeof(sources) = 'array'::text) AND (jsonb_array_length(sources) > 0)));
-- @@ constraint_c public.ottoq_event_types_catalog.ottoq_event_types_catalog_category_check
ALTER TABLE ONLY public.ottoq_event_types_catalog ADD CONSTRAINT ottoq_event_types_catalog_category_check CHECK ((category = ANY (ARRAY['state_change'::text, 'rule_evaluation'::text, 'prediction'::text, 'action'::text, 'audit'::text, 'safety_event'::text, 'business_event'::text, 'system_event'::text, 'integration_event'::text])));
-- @@ constraint_c public.ottoq_event_types_catalog.ottoq_event_types_catalog_default_severity_check
ALTER TABLE ONLY public.ottoq_event_types_catalog ADD CONSTRAINT ottoq_event_types_catalog_default_severity_check CHECK ((default_severity = ANY (ARRAY['debug'::text, 'info'::text, 'warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
-- @@ constraint_c public.ottoq_events.event_id_in_chain_consistency
ALTER TABLE ONLY public.ottoq_events ADD CONSTRAINT event_id_in_chain_consistency CHECK (((parent_event_id IS NULL) OR (cardinality(causation_chain) = 0) OR (causation_chain[cardinality(causation_chain)] = parent_event_id)));
-- @@ constraint_c public.ottoq_events.no_future_events
ALTER TABLE ONLY public.ottoq_events ADD CONSTRAINT no_future_events CHECK ((occurred_at <= (recorded_at + '00:01:00'::interval)));
-- @@ constraint_c public.ottoq_events.ottoq_events_actor_type_check
ALTER TABLE ONLY public.ottoq_events ADD CONSTRAINT ottoq_events_actor_type_check CHECK ((actor_type = ANY (ARRAY['fleet_operator_admin'::text, 'fleet_operator_viewer'::text, 'oem_dispatch_webhook'::text, 'oem_admin_console'::text, 'depot_tech'::text, 'depot_supervisor'::text, 'command_center_operator'::text, 'ottoq_engine'::text, 'ottow_driver'::text, 'ottow_dispatcher'::text, 'otto_response_agent'::text, 'system_scheduler'::text, 'external_sensor'::text, 'ocpp_charger'::text, 'av_vehicle'::text, 'bess_controller'::text, 'solar_controller'::text, 'migration_script'::text, 'system'::text, 'unknown'::text])));
-- @@ constraint_c public.ottoq_events.ottoq_events_data_source_check
ALTER TABLE ONLY public.ottoq_events ADD CONSTRAINT ottoq_events_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text, 'replay'::text, 'shadow'::text])));
-- @@ constraint_c public.ottoq_events.ottoq_events_outcome_check
ALTER TABLE ONLY public.ottoq_events ADD CONSTRAINT ottoq_events_outcome_check CHECK ((outcome = ANY (ARRAY['pending'::text, 'in_progress'::text, 'succeeded'::text, 'failed'::text, 'rolled_back'::text, 'partial'::text, 'timed_out'::text])));
-- @@ constraint_c public.ottoq_events.ottoq_events_severity_check
ALTER TABLE ONLY public.ottoq_events ADD CONSTRAINT ottoq_events_severity_check CHECK ((severity = ANY (ARRAY['debug'::text, 'info'::text, 'warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
-- @@ constraint_c public.ottoq_evidence_regimes.ottoq_evidence_regimes_model_check
ALTER TABLE ONLY public.ottoq_evidence_regimes ADD CONSTRAINT ottoq_evidence_regimes_model_check CHECK ((model = 'charge_time_v2'::text));
-- @@ constraint_c public.ottoq_evidence_regimes.ottoq_evidence_regimes_reason_check
ALTER TABLE ONLY public.ottoq_evidence_regimes ADD CONSTRAINT ottoq_evidence_regimes_reason_check CHECK ((length(btrim(reason)) >= 20));
-- @@ constraint_c public.ottoq_evidence_regimes.ottoq_evidence_regimes_scope
ALTER TABLE ONLY public.ottoq_evidence_regimes ADD CONSTRAINT ottoq_evidence_regimes_scope CHECK (((model <> 'charge_time_v2'::text) OR (scope = ANY (ARRAY['*'::text, 'dcfc'::text, 'l2'::text]))));
-- @@ constraint_c public.ottoq_evidence_regimes.ottoq_evidence_regimes_source_check
ALTER TABLE ONLY public.ottoq_evidence_regimes ADD CONSTRAINT ottoq_evidence_regimes_source_check CHECK ((length(btrim(source)) >= 3));
-- @@ constraint_c public.ottoq_features.ottoq_features_category_check
ALTER TABLE ONLY public.ottoq_features ADD CONSTRAINT ottoq_features_category_check CHECK ((category = ANY (ARRAY['vehicle'::text, 'stall'::text, 'depot'::text, 'task'::text, 'schedule'::text, 'fleet'::text, 'external'::text, 'calendar'::text, 'derived'::text, 'synthetic'::text])));
-- @@ constraint_c public.ottoq_features.ottoq_features_data_type_check
ALTER TABLE ONLY public.ottoq_features ADD CONSTRAINT ottoq_features_data_type_check CHECK ((data_type = ANY (ARRAY['numeric'::text, 'integer'::text, 'boolean'::text, 'text'::text, 'timestamp'::text, 'json'::text, 'array'::text, 'enum'::text])));
-- @@ constraint_c public.ottoq_features.ottoq_features_status_check
ALTER TABLE ONLY public.ottoq_features ADD CONSTRAINT ottoq_features_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'deprecated'::text, 'archived'::text])));
-- @@ constraint_c public.ottoq_feed_plan_promotions.ottoq_feed_plan_promotions_promoted_by_check
ALTER TABLE ONLY public.ottoq_feed_plan_promotions ADD CONSTRAINT ottoq_feed_plan_promotions_promoted_by_check CHECK ((length(btrim(promoted_by)) >= 2));
-- @@ constraint_c public.ottoq_feed_plan_promotions.ottoq_feed_plan_promotions_reason_check
ALTER TABLE ONLY public.ottoq_feed_plan_promotions ADD CONSTRAINT ottoq_feed_plan_promotions_reason_check CHECK ((length(btrim(reason)) >= 10));
-- @@ constraint_c public.ottoq_feed_plans.ottoq_feed_plans_status_check
ALTER TABLE ONLY public.ottoq_feed_plans ADD CONSTRAINT ottoq_feed_plans_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'superseded'::text])));
-- @@ constraint_c public.ottoq_fleet_buildouts.ottoq_fleet_buildouts_borrow_by_class_check
ALTER TABLE ONLY public.ottoq_fleet_buildouts ADD CONSTRAINT ottoq_fleet_buildouts_borrow_by_class_check CHECK ((jsonb_typeof(borrow_by_class) = 'object'::text));
-- @@ constraint_c public.ottoq_fleet_buildouts.ottoq_fleet_buildouts_check
ALTER TABLE ONLY public.ottoq_fleet_buildouts ADD CONSTRAINT ottoq_fleet_buildouts_check CHECK ((lender_depot_id <> depot_id));
-- @@ constraint_c public.ottoq_fleet_buildouts.ottoq_fleet_buildouts_fleet_code_check
ALTER TABLE ONLY public.ottoq_fleet_buildouts ADD CONSTRAINT ottoq_fleet_buildouts_fleet_code_check CHECK ((fleet_code ~ '^[a-z0-9_]+$'::text));
-- @@ constraint_c public.ottoq_fleet_buildouts.ottoq_fleet_buildouts_fleet_size_check
ALTER TABLE ONLY public.ottoq_fleet_buildouts ADD CONSTRAINT ottoq_fleet_buildouts_fleet_size_check CHECK ((fleet_size > 0));
-- @@ constraint_c public.ottoq_fleet_operator_slas.ottoq_fleet_operator_slas_oem_acceptance_mode_check
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_oem_acceptance_mode_check CHECK ((oem_acceptance_mode = ANY (ARRAY['auto'::text, 'tech_confirm_only'::text, 'oem_webhook_final_only'::text, 'oem_webhook_required'::text])));
-- @@ constraint_c public.ottoq_fleet_operator_slas.ottoq_fleet_operator_slas_oem_acceptance_on_timeout_check
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_oem_acceptance_on_timeout_check CHECK ((oem_acceptance_on_timeout = ANY (ARRAY['auto_accept'::text, 'auto_reject'::text, 'hold_for_manual'::text])));
-- @@ constraint_c public.ottoq_fleet_operator_slas.ottoq_fleet_operator_slas_reporting_frequency_check
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_reporting_frequency_check CHECK ((reporting_frequency = ANY (ARRAY['per_visit'::text, 'daily'::text, 'weekly'::text, 'monthly'::text, 'on_demand'::text])));
-- @@ constraint_c public.ottoq_fleet_operator_slas.ottoq_fleet_operator_slas_status_check
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ADD CONSTRAINT ottoq_fleet_operator_slas_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'expired'::text, 'suspended'::text, 'archived'::text])));
-- @@ constraint_c public.ottoq_grid_events.ottoq_grid_events_event_type_check
ALTER TABLE ONLY public.ottoq_grid_events ADD CONSTRAINT ottoq_grid_events_event_type_check CHECK ((event_type = ANY (ARRAY['demand_response_called'::text, 'demand_response_released'::text, 'brownout'::text, 'overvoltage'::text, 'undervoltage'::text, 'frequency_high'::text, 'frequency_low'::text, 'grid_trip'::text, 'grid_restored'::text, 'tariff_window_change'::text, 'curtailment_request'::text])));
-- @@ constraint_c public.ottoq_grid_events.ottoq_grid_events_severity_check
ALTER TABLE ONLY public.ottoq_grid_events ADD CONSTRAINT ottoq_grid_events_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
-- @@ constraint_c public.ottoq_incident_reports.ottoq_incident_reports_incident_type_check
ALTER TABLE ONLY public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_incident_type_check CHECK ((incident_type = ANY (ARRAY['emergency_cascade'::text, 'safety_event'::text, 'oem_rejection'::text, 'sustained_rule_failure'::text, 'sensor_blackout'::text, 'energy_overrun'::text, 'sla_critical_breach'::text, 'anomaly_critical'::text, 'manual_report'::text, 'other'::text])));
-- @@ constraint_c public.ottoq_incident_reports.ottoq_incident_reports_status_check
ALTER TABLE ONLY public.ottoq_incident_reports ADD CONSTRAINT ottoq_incident_reports_status_check CHECK ((status = ANY (ARRAY['auto_generated'::text, 'under_review'::text, 'reviewed'::text, 'closed'::text, 'reopened'::text])));
-- @@ constraint_c public.ottoq_inference_log.ottoq_inference_log_status_check
ALTER TABLE ONLY public.ottoq_inference_log ADD CONSTRAINT ottoq_inference_log_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'failed'::text, 'timed_out'::text, 'cancelled'::text])));
-- @@ constraint_c public.ottoq_intelligence_sources.ottoq_intelligence_sources_kind_check
ALTER TABLE ONLY public.ottoq_intelligence_sources ADD CONSTRAINT ottoq_intelligence_sources_kind_check CHECK ((kind = ANY (ARRAY['deterministic'::text, 'solver_external'::text, 'solver_local'::text, 'llm'::text, 'heuristic'::text, 'baseline'::text, 'fallback'::text, 'probe'::text])));
-- @@ constraint_c public.ottoq_itinerary_legs.ottoq_itinerary_legs_leg_type_check
ALTER TABLE ONLY public.ottoq_itinerary_legs ADD CONSTRAINT ottoq_itinerary_legs_leg_type_check CHECK ((leg_type = ANY (ARRAY['arrive'::text, 'taxi'::text, 'charge_dcfc'::text, 'charge_l2'::text, 'wash'::text, 'detail'::text, 'service'::text, 'inspect'::text, 'settle'::text, 'stage'::text, 'depart'::text, 'interior_tidy'::text, 'sensor_clean'::text, 'item_retrieval'::text, 'interior_deep_clean'::text, 'software_update'::text, 'remote_diagnostics'::text, 'triage_check'::text, 'sensor_calibration'::text, 'mechanical_pm'::text, 'fault_repair'::text, 'cosmetic_repair'::text, 'perimeter_walkaround'::text])));
-- @@ constraint_c public.ottoq_itinerary_legs.ottoq_itinerary_legs_status_check
ALTER TABLE ONLY public.ottoq_itinerary_legs ADD CONSTRAINT ottoq_itinerary_legs_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'active'::text, 'done'::text, 'skipped'::text, 'amended'::text])));
-- @@ constraint_c public.ottoq_learned_estimates.ottoq_learned_estimates_model_check
ALTER TABLE ONLY public.ottoq_learned_estimates ADD CONSTRAINT ottoq_learned_estimates_model_check CHECK ((model = ANY (ARRAY['charge_time_v1'::text, 'return_v1'::text])));
-- @@ constraint_c public.ottoq_margin_prices.ottoq_margin_prices_check
ALTER TABLE ONLY public.ottoq_margin_prices ADD CONSTRAINT ottoq_margin_prices_check CHECK (((low <= point) AND (point <= high)));
-- @@ constraint_c public.ottoq_margin_prices.ottoq_margin_prices_confidence_check
ALTER TABLE ONLY public.ottoq_margin_prices ADD CONSTRAINT ottoq_margin_prices_confidence_check CHECK ((confidence = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
-- @@ constraint_c public.ottoq_margin_prices.ottoq_margin_prices_price_code_check
ALTER TABLE ONLY public.ottoq_margin_prices ADD CONSTRAINT ottoq_margin_prices_price_code_check CHECK ((price_code ~ '^[a-z0-9_]+$'::text));
-- @@ constraint_c public.ottoq_margin_prices.ottoq_margin_prices_sources_check
ALTER TABLE ONLY public.ottoq_margin_prices ADD CONSTRAINT ottoq_margin_prices_sources_check CHECK (((jsonb_typeof(sources) = 'array'::text) AND (jsonb_array_length(sources) > 0)));
-- @@ constraint_c public.ottoq_model_artifacts.ottoq_model_artifacts_format_check
ALTER TABLE ONLY public.ottoq_model_artifacts ADD CONSTRAINT ottoq_model_artifacts_format_check CHECK ((format = ANY (ARRAY['onnx'::text, 'pmml'::text, 'joblib'::text, 'params_only'::text, 'tflite'::text, 'pickle'::text, 'custom'::text])));
-- @@ constraint_c public.ottoq_oauth_auth_requests.ottoq_oauth_auth_requests_challenge_check
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ADD CONSTRAINT ottoq_oauth_auth_requests_challenge_check CHECK ((code_challenge ~ '^[A-Za-z0-9_-]{43,128}$'::text));
-- @@ constraint_c public.ottoq_oauth_auth_requests.ottoq_oauth_auth_requests_code_check
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ADD CONSTRAINT ottoq_oauth_auth_requests_code_check CHECK (((status = ANY (ARRAY['approved'::text, 'consumed'::text])) = (code_hash IS NOT NULL)));
-- @@ constraint_c public.ottoq_oauth_auth_requests.ottoq_oauth_auth_requests_state_check
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ADD CONSTRAINT ottoq_oauth_auth_requests_state_check CHECK (((state IS NULL) OR ((length(state) <= 512) AND (state !~ '[[:cntrl:]]'::text))));
-- @@ constraint_c public.ottoq_oauth_auth_requests.ottoq_oauth_auth_requests_status_check
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ADD CONSTRAINT ottoq_oauth_auth_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'denied'::text, 'consumed'::text])));
-- @@ constraint_c public.ottoq_oauth_clients.ottoq_oauth_clients_grants_check
ALTER TABLE ONLY public.ottoq_oauth_clients ADD CONSTRAINT ottoq_oauth_clients_grants_check CHECK (((cardinality(grant_types) > 0) AND (grant_types <@ ARRAY['authorization_code'::text, 'refresh_token'::text, 'urn:ietf:params:oauth:grant-type:device_code'::text])));
-- @@ constraint_c public.ottoq_oauth_clients.ottoq_oauth_clients_id_check
ALTER TABLE ONLY public.ottoq_oauth_clients ADD CONSTRAINT ottoq_oauth_clients_id_check CHECK ((client_id ~ '^oqc_[0-9a-f]{32}$'::text));
-- @@ constraint_c public.ottoq_oauth_clients.ottoq_oauth_clients_name_check
ALTER TABLE ONLY public.ottoq_oauth_clients ADD CONSTRAINT ottoq_oauth_clients_name_check CHECK ((((length(client_name) >= 1) AND (length(client_name) <= 60)) AND (client_name !~ '[[:cntrl:]]'::text)));
-- @@ constraint_c public.ottoq_oauth_clients.ottoq_oauth_clients_status_check
ALTER TABLE ONLY public.ottoq_oauth_clients ADD CONSTRAINT ottoq_oauth_clients_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text])));
-- @@ constraint_c public.ottoq_oauth_clients.ottoq_oauth_clients_uris_check
ALTER TABLE ONLY public.ottoq_oauth_clients ADD CONSTRAINT ottoq_oauth_clients_uris_check CHECK ((cardinality(redirect_uris) <= 10));
-- @@ constraint_c public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_account_check
ALTER TABLE ONLY public.ottoq_oauth_device_codes ADD CONSTRAINT ottoq_oauth_device_codes_account_check CHECK (((status = 'pending'::text) OR (account_id IS NOT NULL)));
-- @@ constraint_c public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_decided_check
ALTER TABLE ONLY public.ottoq_oauth_device_codes ADD CONSTRAINT ottoq_oauth_device_codes_decided_check CHECK (((status = 'pending'::text) = (decided_at IS NULL)));
-- @@ constraint_c public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_hash_check
ALTER TABLE ONLY public.ottoq_oauth_device_codes ADD CONSTRAINT ottoq_oauth_device_codes_hash_check CHECK ((device_code_hash ~ '^[0-9a-f]{64}$'::text));
-- @@ constraint_c public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_interval_check
ALTER TABLE ONLY public.ottoq_oauth_device_codes ADD CONSTRAINT ottoq_oauth_device_codes_interval_check CHECK (((interval_s >= 1) AND (interval_s <= 60)));
-- @@ constraint_c public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_status_check
ALTER TABLE ONLY public.ottoq_oauth_device_codes ADD CONSTRAINT ottoq_oauth_device_codes_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'denied'::text, 'consumed'::text])));
-- @@ constraint_c public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_user_code_check
ALTER TABLE ONLY public.ottoq_oauth_device_codes ADD CONSTRAINT ottoq_oauth_device_codes_user_code_check CHECK ((user_code ~ '^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$'::text));
-- @@ constraint_c public.ottoq_oauth_grants.ottoq_oauth_grants_via_check
ALTER TABLE ONLY public.ottoq_oauth_grants ADD CONSTRAINT ottoq_oauth_grants_via_check CHECK ((created_via = ANY (ARRAY['device_code'::text, 'authorization_code'::text])));
-- @@ constraint_c public.ottoq_oauth_tokens.ottoq_oauth_tokens_hash_check
ALTER TABLE ONLY public.ottoq_oauth_tokens ADD CONSTRAINT ottoq_oauth_tokens_hash_check CHECK ((token_hash ~ '^[0-9a-f]{64}$'::text));
-- @@ constraint_c public.ottoq_oauth_tokens.ottoq_oauth_tokens_kind_check
ALTER TABLE ONLY public.ottoq_oauth_tokens ADD CONSTRAINT ottoq_oauth_tokens_kind_check CHECK ((kind = ANY (ARRAY['access'::text, 'refresh'::text])));
-- @@ constraint_c public.ottoq_oauth_tokens.ottoq_oauth_tokens_revoked_check
ALTER TABLE ONLY public.ottoq_oauth_tokens ADD CONSTRAINT ottoq_oauth_tokens_revoked_check CHECK (((revoked_at IS NULL) = (revoked_reason IS NULL)));
-- @@ constraint_c public.ottoq_oauth_tokens.ottoq_oauth_tokens_rotation_check
ALTER TABLE ONLY public.ottoq_oauth_tokens ADD CONSTRAINT ottoq_oauth_tokens_rotation_check CHECK (((kind = 'refresh'::text) OR ((used_at IS NULL) AND (replaced_by IS NULL))));
-- @@ constraint_c public.ottoq_ocpp_chargers.ottoq_ocpp_chargers_station_state_check
ALTER TABLE ONLY public.ottoq_ocpp_chargers ADD CONSTRAINT ottoq_ocpp_chargers_station_state_check CHECK ((station_state = ANY (ARRAY['Available'::text, 'Occupied'::text, 'Reserved'::text, 'Unavailable'::text, 'Faulted'::text, 'Maintenance'::text])));
-- @@ constraint_c public.ottoq_ocpp_messages.ottoq_ocpp_messages_data_source_check
ALTER TABLE ONLY public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text, 'replay'::text, 'shadow'::text])));
-- @@ constraint_c public.ottoq_ocpp_messages.ottoq_ocpp_messages_direction_check
ALTER TABLE ONLY public.ottoq_ocpp_messages ADD CONSTRAINT ottoq_ocpp_messages_direction_check CHECK ((direction = ANY (ARRAY['cs_to_csms'::text, 'csms_to_cs'::text])));
-- @@ constraint_c public.ottoq_oem_webhook_log.ottoq_oem_webhook_log_delivery_mode_check
ALTER TABLE ONLY public.ottoq_oem_webhook_log ADD CONSTRAINT ottoq_oem_webhook_log_delivery_mode_check CHECK ((delivery_mode = ANY (ARRAY['simulated'::text, 'live'::text])));
-- @@ constraint_c public.ottoq_oem_webhook_log.ottoq_oem_webhook_log_delivery_status_check
ALTER TABLE ONLY public.ottoq_oem_webhook_log ADD CONSTRAINT ottoq_oem_webhook_log_delivery_status_check CHECK ((delivery_status = ANY (ARRAY['delivered'::text, 'failed'::text, 'timed_out'::text, 'rate_limited'::text, 'auth_failed'::text, 'server_error'::text, 'dropped'::text, 'sent'::text, 'pending_retry'::text, 'rejected_other'::text])));
-- @@ constraint_c public.ottoq_operation_catalog.ottoq_operation_catalog_category_check
ALTER TABLE ONLY public.ottoq_operation_catalog ADD CONSTRAINT ottoq_operation_catalog_category_check CHECK ((category = ANY (ARRAY['energy'::text, 'clean'::text, 'data'::text, 'maintenance'::text, 'inspection'::text, 'movement'::text, 'staging'::text])));
-- @@ constraint_c public.ottoq_ops_approvals.ottoq_ops_approvals_approval_type_check
ALTER TABLE ONLY public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_approval_type_check CHECK ((approval_type = ANY (ARRAY['opportunistic_charge'::text, 'tech_greenlight'::text, 'indepot_reassign'::text])));
-- @@ constraint_c public.ottoq_ops_approvals.ottoq_ops_approvals_priority_check
ALTER TABLE ONLY public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_priority_check CHECK ((priority = ANY (ARRAY['normal'::text, 'high'::text])));
-- @@ constraint_c public.ottoq_ops_approvals.ottoq_ops_approvals_status_check
ALTER TABLE ONLY public.ottoq_ops_approvals ADD CONSTRAINT ottoq_ops_approvals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'declined'::text, 'expired'::text])));
-- @@ constraint_c public.ottoq_owner_accounts.ottoq_owner_accounts_depot_check
ALTER TABLE ONLY public.ottoq_owner_accounts ADD CONSTRAINT ottoq_owner_accounts_depot_check CHECK ((depot_id = '11111111-1111-1111-1111-111111111111'::uuid));
-- @@ constraint_c public.ottoq_owner_accounts.ottoq_owner_accounts_disabled_check
ALTER TABLE ONLY public.ottoq_owner_accounts ADD CONSTRAINT ottoq_owner_accounts_disabled_check CHECK (((status = 'disabled'::text) = (disabled_at IS NOT NULL)));
-- @@ constraint_c public.ottoq_owner_accounts.ottoq_owner_accounts_email_check
ALTER TABLE ONLY public.ottoq_owner_accounts ADD CONSTRAINT ottoq_owner_accounts_email_check CHECK (((email = lower(btrim(email))) AND (email ~ '^[^@[:space:]]+@[^@[:space:]]+$'::text)));
-- @@ constraint_c public.ottoq_owner_accounts.ottoq_owner_accounts_status_check
ALTER TABLE ONLY public.ottoq_owner_accounts ADD CONSTRAINT ottoq_owner_accounts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text])));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_args_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_args_check CHECK (((jsonb_typeof(args) = 'object'::text) AND (octet_length((args)::text) <= 8000)));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_effects_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_effects_check CHECK ((jsonb_typeof(effects) = 'array'::text));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_idempotency_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_idempotency_check CHECK (((idempotency_key IS NULL) OR ((mode = 'apply'::text) AND (idempotency_key ~ '^[A-Za-z0-9._:-]{1,100}$'::text))));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_lifted_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_lifted_check CHECK (((lifted_at IS NULL) = (lifted_reason IS NULL)));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_mode_outcome_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_mode_outcome_check CHECK ((((mode = 'preview'::text) AND (outcome = ANY (ARRAY['previewed'::text, 'refused'::text]))) OR ((mode = 'apply'::text) AND (outcome = ANY (ARRAY['applied'::text, 'no_change'::text, 'refused'::text])))));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_refusal_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_refusal_check CHECK (((outcome = 'refused'::text) = (refusal IS NOT NULL)));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_summary_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_summary_check CHECK (((char_length(summary) >= 1) AND (char_length(summary) <= 6000)));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_tool_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_tool_check CHECK ((tool = ANY (ARRAY['set_charge_limit'::text, 'clear_charge_limit'::text, 'request_service'::text, 'cancel_service'::text, 'hold_vehicle'::text, 'release_hold'::text, 'undo_command'::text])));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_undo_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_undo_check CHECK (((undoes_command_id IS NULL) OR (tool = 'undo_command'::text)));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_undone_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_undone_check CHECK (((undone_at IS NULL) = (undone_by_command_id IS NULL)));
-- @@ constraint_c public.ottoq_owner_commands.ottoq_owner_commands_vehicles_check
ALTER TABLE ONLY public.ottoq_owner_commands ADD CONSTRAINT ottoq_owner_commands_vehicles_check CHECK ((jsonb_typeof(vehicles) = 'array'::text));
-- @@ constraint_c public.ottoq_owner_settings.ottoq_owner_settings_applied_check
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_applied_check CHECK ((jsonb_typeof(applied) = 'object'::text));
-- @@ constraint_c public.ottoq_owner_settings.ottoq_owner_settings_charge_limit_check
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_charge_limit_check CHECK (((kind <> 'charge_limit'::text) OR (((charge_limit_pct >= (50)::numeric) AND (charge_limit_pct <= (100)::numeric)) AND (hold_until_sim IS NULL) AND (service IS NULL) AND (service_when IS NULL))));
-- @@ constraint_c public.ottoq_owner_settings.ottoq_owner_settings_closed_check
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_closed_check CHECK (((status = 'active'::text) = (closed_at IS NULL)));
-- @@ constraint_c public.ottoq_owner_settings.ottoq_owner_settings_hold_check
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_hold_check CHECK (((kind <> 'hold'::text) OR ((hold_until_sim IS NOT NULL) AND (charge_limit_pct IS NULL) AND (service IS NULL) AND (service_when IS NULL))));
-- @@ constraint_c public.ottoq_owner_settings.ottoq_owner_settings_kind_check
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_kind_check CHECK ((kind = ANY (ARRAY['charge_limit'::text, 'hold'::text, 'service'::text])));
-- @@ constraint_c public.ottoq_owner_settings.ottoq_owner_settings_service_check
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_service_check CHECK (((kind <> 'service'::text) OR ((service IS NOT NULL) AND (service_when = ANY (ARRAY['now'::text, 'next_return'::text, 'every_return'::text])) AND (charge_limit_pct IS NULL) AND (hold_until_sim IS NULL))));
-- @@ constraint_c public.ottoq_owner_settings.ottoq_owner_settings_status_check
ALTER TABLE ONLY public.ottoq_owner_settings ADD CONSTRAINT ottoq_owner_settings_status_check CHECK ((status = ANY (ARRAY['active'::text, 'replaced'::text, 'withdrawn'::text, 'fulfilled'::text, 'lifted'::text])));
-- @@ constraint_c public.ottoq_policy_params.ottoq_policy_params_proposer_seat_run_scoped
ALTER TABLE ONLY public.ottoq_policy_params ADD CONSTRAINT ottoq_policy_params_proposer_seat_run_scoped CHECK (((param_key <> 'proposer_seat'::text) OR (scope_type = 'run'::text)));
-- @@ constraint_c public.ottoq_policy_params.ottoq_policy_params_scope_type_check
ALTER TABLE ONLY public.ottoq_policy_params ADD CONSTRAINT ottoq_policy_params_scope_type_check CHECK ((scope_type = ANY (ARRAY['global'::text, 'depot'::text, 'run'::text])));
-- @@ constraint_c public.ottoq_prediction_rule_links.ottoq_prediction_rule_links_relationship_check
ALTER TABLE ONLY public.ottoq_prediction_rule_links ADD CONSTRAINT ottoq_prediction_rule_links_relationship_check CHECK ((relationship = ANY (ARRAY['predicts_violation'::text, 'predicts_compliance'::text, 'predicts_proximity'::text, 'informs_threshold'::text])));
-- @@ constraint_c public.ottoq_prediction_types_catalog.ottoq_prediction_types_catalog_category_check
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ADD CONSTRAINT ottoq_prediction_types_catalog_category_check CHECK ((category = ANY (ARRAY['vehicle'::text, 'stall'::text, 'depot'::text, 'fleet'::text, 'energy'::text, 'anomaly'::text, 'operational'::text, 'quality'::text])));
-- @@ constraint_c public.ottoq_prediction_types_catalog.ottoq_prediction_types_catalog_output_kind_check
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ADD CONSTRAINT ottoq_prediction_types_catalog_output_kind_check CHECK ((output_kind = ANY (ARRAY['regression'::text, 'classification'::text, 'time_series'::text, 'multi_class'::text, 'anomaly_score'::text, 'distribution'::text])));
-- @@ constraint_c public.ottoq_prediction_types_catalog.ottoq_prediction_types_catalog_status_check
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ADD CONSTRAINT ottoq_prediction_types_catalog_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'shadow'::text, 'active'::text, 'deprecated'::text, 'archived'::text])));
-- @@ constraint_c public.ottoq_predictions.ottoq_predictions_ab_test_variant_check
ALTER TABLE ONLY public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_ab_test_variant_check CHECK (((ab_test_variant = ANY (ARRAY['A'::text, 'B'::text])) OR (ab_test_variant IS NULL)));
-- @@ constraint_c public.ottoq_predictions.ottoq_predictions_execution_status_check
ALTER TABLE ONLY public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_execution_status_check CHECK ((execution_status = ANY (ARRAY['pending'::text, 'approved'::text, 'executing'::text, 'executed'::text, 'failed'::text, 'rolled_back'::text, 'expired'::text])));
-- @@ constraint_c public.ottoq_predictions.ottoq_predictions_status_check
ALTER TABLE ONLY public.ottoq_predictions ADD CONSTRAINT ottoq_predictions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'proposed'::text, 'sent_to_user'::text, 'approved'::text, 'executing'::text, 'accepted'::text, 'rejected'::text, 'expired'::text, 'auto_applied'::text, 'completed'::text])));
-- @@ constraint_c public.ottoq_proposer_fire_log.ottoq_proposer_fire_log_status_check
ALTER TABLE ONLY public.ottoq_proposer_fire_log ADD CONSTRAINT ottoq_proposer_fire_log_status_check CHECK ((status = ANY (ARRAY['submitted'::text, 'empty'::text, 'refused'::text, 'error'::text])));
-- @@ constraint_c public.ottoq_ready_promise_updates.ottoq_ready_promise_updates_bundle_check
ALTER TABLE ONLY public.ottoq_ready_promise_updates ADD CONSTRAINT ottoq_ready_promise_updates_bundle_check CHECK ((bundle = ANY (ARRAY['bay'::text, 'no_bay'::text])));
-- @@ constraint_c public.ottoq_ready_promise_updates.ottoq_ready_promise_updates_ordered
ALTER TABLE ONLY public.ottoq_ready_promise_updates ADD CONSTRAINT ottoq_ready_promise_updates_ordered CHECK (((ready_p50_min IS NULL) OR ((ready_p90_min >= ready_p50_min) AND (ready_p50_min >= (0)::numeric))));
-- @@ constraint_c public.ottoq_ready_promise_updates.ottoq_ready_promise_updates_situation_check
ALTER TABLE ONLY public.ottoq_ready_promise_updates ADD CONSTRAINT ottoq_ready_promise_updates_situation_check CHECK ((situation = ANY (ARRAY['in_line'::text, 'charging'::text, 'holds_charger'::text, 'unplanned'::text, 'no_charge'::text, 'after_charge'::text, 'ready'::text])));
-- @@ constraint_c public.ottoq_ready_promises.ottoq_ready_promises_bundle_check
ALTER TABLE ONLY public.ottoq_ready_promises ADD CONSTRAINT ottoq_ready_promises_bundle_check CHECK ((bundle = ANY (ARRAY['bay'::text, 'no_bay'::text])));
-- @@ constraint_c public.ottoq_ready_promises.ottoq_ready_promises_ordered
ALTER TABLE ONLY public.ottoq_ready_promises ADD CONSTRAINT ottoq_ready_promises_ordered CHECK (((ready_p90_min >= ready_p50_min) AND (ready_p50_min >= (0)::numeric)));
-- @@ constraint_c public.ottoq_ready_promises.ottoq_ready_promises_situation_check
ALTER TABLE ONLY public.ottoq_ready_promises ADD CONSTRAINT ottoq_ready_promises_situation_check CHECK ((situation = ANY (ARRAY['in_line'::text, 'charging'::text, 'holds_charger'::text, 'unplanned'::text, 'no_charge'::text, 'after_charge'::text, 'ready'::text])));
-- @@ constraint_c public.ottoq_recall_implementations.ottoq_recall_implementations_status_check
ALTER TABLE ONLY public.ottoq_recall_implementations ADD CONSTRAINT ottoq_recall_implementations_status_check CHECK ((status = ANY (ARRAY['active'::text, 'parked'::text, 'retired'::text])));
-- @@ constraint_c public.ottoq_recall_refusals.ottoq_recall_refusals_reason_code_check
ALTER TABLE ONLY public.ottoq_recall_refusals ADD CONSTRAINT ottoq_recall_refusals_reason_code_check CHECK ((reason_code = ANY (ARRAY['mission_overrun'::text, 'passenger_onboard'::text, 'safety_hold'::text, 'operator_override'::text, 'unreachable'::text])));
-- @@ constraint_c public.ottoq_recall_refusals.ottoq_recall_refusals_retry_after_min_check
ALTER TABLE ONLY public.ottoq_recall_refusals ADD CONSTRAINT ottoq_recall_refusals_retry_after_min_check CHECK (((retry_after_min > (0)::numeric) AND (retry_after_min <= (720)::numeric)));
-- @@ constraint_c public.ottoq_recommendations.ottoq_recommendations_status_check
ALTER TABLE ONLY public.ottoq_recommendations ADD CONSTRAINT ottoq_recommendations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'validating'::text, 'admitted'::text, 'rejected'::text, 'shadow'::text, 'expired'::text, 'executed'::text, 'rolled_back'::text])));
-- @@ constraint_c public.ottoq_research_findings.ottoq_research_findings_item_check
ALTER TABLE ONLY public.ottoq_research_findings ADD CONSTRAINT ottoq_research_findings_item_check CHECK ((item ~ '^(E[0-9]{1,2}|P[0-9]\.[0-9])$'::text));
-- @@ constraint_c public.ottoq_research_findings.ottoq_research_findings_kind_check
ALTER TABLE ONLY public.ottoq_research_findings ADD CONSTRAINT ottoq_research_findings_kind_check CHECK ((kind = ANY (ARRAY['measurement'::text, 'build'::text, 'safety'::text, 'recommendation'::text, 'lab'::text])));
-- @@ constraint_c public.ottoq_research_findings.ottoq_research_findings_metrics_check
ALTER TABLE ONLY public.ottoq_research_findings ADD CONSTRAINT ottoq_research_findings_metrics_check CHECK ((jsonb_typeof(metrics) = 'object'::text));
-- @@ constraint_c public.ottoq_research_findings.ottoq_research_findings_phase_check
ALTER TABLE ONLY public.ottoq_research_findings ADD CONSTRAINT ottoq_research_findings_phase_check CHECK ((phase ~ '^P[0-9]$'::text));
-- @@ constraint_c public.ottoq_research_findings.ottoq_research_findings_slug_check
ALTER TABLE ONLY public.ottoq_research_findings ADD CONSTRAINT ottoq_research_findings_slug_check CHECK ((slug ~ '^[a-z0-9][a-z0-9-]{2,79}$'::text));
-- @@ constraint_c public.ottoq_research_findings.ottoq_research_findings_status_check
ALTER TABLE ONLY public.ottoq_research_findings ADD CONSTRAINT ottoq_research_findings_status_check CHECK ((status = ANY (ARRAY['in_progress'::text, 'measured'::text, 'built'::text, 'recommended'::text, 'shipped'::text, 'not_verified'::text, 'retracted'::text])));
-- @@ constraint_c public.ottoq_research_findings.ottoq_research_findings_summary_check
ALTER TABLE ONLY public.ottoq_research_findings ADD CONSTRAINT ottoq_research_findings_summary_check CHECK (((length(summary) >= 8) AND (length(summary) <= 2000)));
-- @@ constraint_c public.ottoq_research_findings.ottoq_research_findings_title_check
ALTER TABLE ONLY public.ottoq_research_findings ADD CONSTRAINT ottoq_research_findings_title_check CHECK (((length(title) >= 8) AND (length(title) <= 200)));
-- @@ constraint_c public.ottoq_retraining_triggers.ottoq_retraining_triggers_condition_kind_check
ALTER TABLE ONLY public.ottoq_retraining_triggers ADD CONSTRAINT ottoq_retraining_triggers_condition_kind_check CHECK ((condition_kind = ANY (ARRAY['drift_psi'::text, 'accuracy_decline'::text, 'calibration_decline'::text, 'time_based'::text, 'sample_threshold'::text, 'manual'::text])));
-- @@ constraint_c public.ottoq_rider_cleaning_flags.chk_rcf_kind
ALTER TABLE ONLY public.ottoq_rider_cleaning_flags ADD CONSTRAINT chk_rcf_kind CHECK ((flag_kind = ANY (ARRAY['interior'::text, 'exterior'::text])));
-- @@ constraint_c public.ottoq_rider_cleaning_flags.chk_rcf_status
ALTER TABLE ONLY public.ottoq_rider_cleaning_flags ADD CONSTRAINT chk_rcf_status CHECK ((status = ANY (ARRAY['pending'::text, 'recalled'::text, 'served'::text])));
-- @@ constraint_c public.ottoq_rule_evaluations.ottoq_rule_evaluations_enforcement_taken_check
ALTER TABLE ONLY public.ottoq_rule_evaluations ADD CONSTRAINT ottoq_rule_evaluations_enforcement_taken_check CHECK ((enforcement_taken = ANY (ARRAY['allowed'::text, 'blocked'::text, 'warned'::text, 'logged'::text, 'overridden'::text, 'shadow_pass'::text, 'shadow_fail'::text])));
-- @@ constraint_c public.ottoq_rule_overrides.ottoq_rule_overrides_justification_check
ALTER TABLE ONLY public.ottoq_rule_overrides ADD CONSTRAINT ottoq_rule_overrides_justification_check CHECK ((length(TRIM(BOTH FROM justification)) >= 10));
-- @@ constraint_c public.ottoq_rule_parameters.ottoq_rule_parameters_scope_check
ALTER TABLE ONLY public.ottoq_rule_parameters ADD CONSTRAINT ottoq_rule_parameters_scope_check CHECK ((scope = ANY (ARRAY['fleet_operator'::text, 'depot'::text, 'vehicle_class'::text])));
-- @@ constraint_c public.ottoq_rules.ottoq_rules_category_check
ALTER TABLE ONLY public.ottoq_rules ADD CONSTRAINT ottoq_rules_category_check CHECK ((category = ANY (ARRAY['hardware_safety'::text, 'energy_safety'::text, 'sla_contract'::text, 'state_machine'::text, 'audit_integrity'::text, 'time_window'::text, 'concurrency'::text, 'emergency_cascade'::text, 'sensor_liveness'::text, 'role_authorization'::text])));
-- @@ constraint_c public.ottoq_rules.ottoq_rules_enforcement_check
ALTER TABLE ONLY public.ottoq_rules ADD CONSTRAINT ottoq_rules_enforcement_check CHECK ((enforcement = ANY (ARRAY['block'::text, 'warn'::text, 'log_only'::text, 'shadow'::text])));
-- @@ constraint_c public.ottoq_rules.ottoq_rules_scope_check
ALTER TABLE ONLY public.ottoq_rules ADD CONSTRAINT ottoq_rules_scope_check CHECK ((scope = ANY (ARRAY['system'::text, 'fleet_operator'::text, 'depot'::text, 'vehicle_class'::text])));
-- @@ constraint_c public.ottoq_rules.ottoq_rules_severity_check
ALTER TABLE ONLY public.ottoq_rules ADD CONSTRAINT ottoq_rules_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'error'::text, 'critical'::text, 'safety_critical'::text])));
-- @@ constraint_c public.ottoq_rules.ottoq_rules_status_check
ALTER TABLE ONLY public.ottoq_rules ADD CONSTRAINT ottoq_rules_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'shadow'::text, 'active'::text, 'deprecated'::text, 'archived'::text])));
-- @@ constraint_c public.ottoq_run_scope_registry.ottoq_run_scope_registry_class_check
ALTER TABLE ONLY public.ottoq_run_scope_registry ADD CONSTRAINT ottoq_run_scope_registry_class_check CHECK ((class = ANY (ARRAY['engine'::text, 'stamp'::text, 'evidence'::text, 'run_ledger'::text])));
-- @@ constraint_c public.ottoq_scenarios.ottoq_scenarios_category_check
ALTER TABLE ONLY public.ottoq_scenarios ADD CONSTRAINT ottoq_scenarios_category_check CHECK ((category = ANY (ARRAY['normal_operations'::text, 'stress_test'::text, 'emergency_drill'::text, 'edge_case'::text, 'soak_test'::text, 'regression'::text, 'demo'::text])));
-- @@ constraint_c public.ottoq_scenarios.ottoq_scenarios_status_check
ALTER TABLE ONLY public.ottoq_scenarios ADD CONSTRAINT ottoq_scenarios_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'deprecated'::text, 'archived'::text])));
-- @@ constraint_c public.ottoq_service_detail_records.ottoq_service_detail_records_check
ALTER TABLE ONLY public.ottoq_service_detail_records ADD CONSTRAINT ottoq_service_detail_records_check CHECK (((leg_id IS NOT NULL) OR (schedule_task_id IS NOT NULL) OR (source_kind = 'manual'::text)));
-- @@ constraint_c public.ottoq_service_detail_records.ottoq_service_detail_records_source_kind_check
ALTER TABLE ONLY public.ottoq_service_detail_records ADD CONSTRAINT ottoq_service_detail_records_source_kind_check CHECK ((source_kind = ANY (ARRAY['itinerary_leg'::text, 'schedule_task'::text, 'manual'::text, 'backfill_leg'::text, 'backfill_task'::text])));
-- @@ constraint_c public.ottoq_service_detail_records.ottoq_service_detail_records_status_check
ALTER TABLE ONLY public.ottoq_service_detail_records ADD CONSTRAINT ottoq_service_detail_records_status_check CHECK ((status = ANY (ARRAY['issued'::text, 'voided'::text, 'superseded'::text])));
-- @@ constraint_c public.ottoq_service_endpoints.ottoq_service_endpoints_url_shape
ALTER TABLE ONLY public.ottoq_service_endpoints ADD CONSTRAINT ottoq_service_endpoints_url_shape CHECK ((base_url ~ '^https?://[^[:space:]/]+(/[^[:space:]]*)?$'::text));
-- @@ constraint_c public.ottoq_service_tariffs.ottoq_service_tariffs_price_unit_check
ALTER TABLE ONLY public.ottoq_service_tariffs ADD CONSTRAINT ottoq_service_tariffs_price_unit_check CHECK ((price_unit = ANY (ARRAY['per_event'::text, 'per_minute'::text, 'per_kwh'::text])));
-- @@ constraint_c public.ottoq_service_tokens.ottoq_service_tokens_status_check
ALTER TABLE ONLY public.ottoq_service_tokens ADD CONSTRAINT ottoq_service_tokens_status_check CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'revoked'::text])));
-- @@ constraint_c public.ottoq_signing_keys.ottoq_signing_keys_scope_check
ALTER TABLE ONLY public.ottoq_signing_keys ADD CONSTRAINT ottoq_signing_keys_scope_check CHECK ((scope = ANY (ARRAY['system'::text, 'fleet_operator'::text, 'depot'::text])));
-- @@ constraint_c public.ottoq_sim_runs.ottoq_sim_runs_policy_check
ALTER TABLE ONLY public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_policy_check CHECK ((policy = ANY (ARRAY['otto_q'::text, 'greedy'::text, 'fifo'::text, 'manual'::text])));
-- @@ constraint_c public.ottoq_sim_runs.ottoq_sim_runs_status_check
ALTER TABLE ONLY public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_status_check CHECK ((status = ANY (ARRAY['initializing'::text, 'running'::text, 'paused'::text, 'completed'::text, 'failed'::text, 'aborted'::text])));
-- @@ constraint_c public.ottoq_sim_runs.ottoq_sim_runs_validation_status_check
ALTER TABLE ONLY public.ottoq_sim_runs ADD CONSTRAINT ottoq_sim_runs_validation_status_check CHECK ((validation_status = ANY (ARRAY['pending'::text, 'passed'::text, 'failed'::text, 'inconclusive'::text])));
-- @@ constraint_c public.ottoq_site_buildouts.ottoq_site_buildouts_buildout_code_check
ALTER TABLE ONLY public.ottoq_site_buildouts ADD CONSTRAINT ottoq_site_buildouts_buildout_code_check CHECK ((buildout_code ~ '^[a-z0-9_]+$'::text));
-- @@ constraint_c public.ottoq_site_buildouts.ottoq_site_buildouts_dcfc_max_concurrent_kw_check
ALTER TABLE ONLY public.ottoq_site_buildouts ADD CONSTRAINT ottoq_site_buildouts_dcfc_max_concurrent_kw_check CHECK ((dcfc_max_concurrent_kw > (0)::numeric));
-- @@ constraint_c public.ottoq_site_buildouts.ottoq_site_buildouts_dcfc_posts_check
ALTER TABLE ONLY public.ottoq_site_buildouts ADD CONSTRAINT ottoq_site_buildouts_dcfc_posts_check CHECK ((dcfc_posts > 0));
-- @@ constraint_c public.ottoq_site_buildouts.ottoq_site_buildouts_service_max_kw_check
ALTER TABLE ONLY public.ottoq_site_buildouts ADD CONSTRAINT ottoq_site_buildouts_service_max_kw_check CHECK ((service_max_kw > (0)::numeric));
-- @@ constraint_c public.ottoq_site_buildouts.ottoq_site_buildouts_stall_set_check
ALTER TABLE ONLY public.ottoq_site_buildouts ADD CONSTRAINT ottoq_site_buildouts_stall_set_check CHECK ((jsonb_typeof(stall_set) = 'array'::text));
-- @@ constraint_c public.ottoq_site_power_excursion_ledger.ottoq_site_power_excursion_ledger_severity_tier_check
ALTER TABLE ONLY public.ottoq_site_power_excursion_ledger ADD CONSTRAINT ottoq_site_power_excursion_ledger_severity_tier_check CHECK ((severity_tier = ANY (ARRAY['excursion'::text, 'high_water'::text, 'armed'::text, 'ev_over_published_cap'::text])));
-- @@ constraint_c public.ottoq_site_power_plan_ledger.ottoq_site_power_plan_ledger_finding_check
ALTER TABLE ONLY public.ottoq_site_power_plan_ledger ADD CONSTRAINT ottoq_site_power_plan_ledger_finding_check CHECK ((finding = 'plan_over_contract'::text));
-- @@ constraint_c public.ottoq_site_structures.ottoq_site_structures_status_check
ALTER TABLE ONLY public.ottoq_site_structures ADD CONSTRAINT ottoq_site_structures_status_check CHECK ((status = ANY (ARRAY['active'::text, 'planned'::text, 'decommissioned'::text])));
-- @@ constraint_c public.ottoq_site_structures.ottoq_site_structures_structure_kind_check
ALTER TABLE ONLY public.ottoq_site_structures ADD CONSTRAINT ottoq_site_structures_structure_kind_check CHECK ((structure_kind = ANY (ARRAY['office_building'::text, 'service_building'::text, 'wash_building'::text, 'bess_compound'::text, 'solar_canopy'::text, 'metal_canopy'::text, 'gate'::text, 'fence_segment'::text, 'transformer'::text, 'lane_marker'::text, 'sign'::text, 'lighting_pole'::text, 'perimeter_wall'::text])));
-- @@ constraint_c public.ottoq_sla_conformance_daily.ottoq_sla_conformance_daily_check
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ADD CONSTRAINT ottoq_sla_conformance_daily_check CHECK ((((compliant_visits + partial_visits) + non_compliant_visits) <= total_visits));
-- @@ constraint_c public.ottoq_sla_violations.ottoq_sla_violations_severity_check
ALTER TABLE ONLY public.ottoq_sla_violations ADD CONSTRAINT ottoq_sla_violations_severity_check CHECK ((severity = ANY (ARRAY['warning'::text, 'breach'::text, 'critical_breach'::text])));
-- @@ constraint_c public.ottoq_space_integrity_ledger.ottoq_space_integrity_ledger_incident_kind_check
ALTER TABLE ONLY public.ottoq_space_integrity_ledger ADD CONSTRAINT ottoq_space_integrity_ledger_incident_kind_check CHECK ((incident_kind = ANY (ARRAY['pointer_empty'::text, 'holds_different_vehicle'::text])));
-- @@ constraint_c public.ottoq_specialization_strategies.ottoq_specialization_strategies_specialization_level_check
ALTER TABLE ONLY public.ottoq_specialization_strategies ADD CONSTRAINT ottoq_specialization_strategies_specialization_level_check CHECK ((specialization_level = ANY (ARRAY['generic'::text, 'per_oem'::text, 'per_vehicle_class'::text, 'per_oem_depot'::text])));
-- @@ constraint_c public.ottoq_stall_bookings.ottoq_stall_bookings_purpose_check
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_purpose_check CHECK ((purpose = ANY (ARRAY['charge_dcfc'::text, 'charge_l2'::text, 'wash'::text, 'detail'::text, 'service'::text, 'inspect'::text, 'temp_hold'::text, 'perimeter_hold'::text, 'staging'::text])));
-- @@ constraint_c public.ottoq_stall_bookings.ottoq_stall_bookings_release_after_book_sim
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_release_after_book_sim CHECK (((released_at IS NULL) OR (booked_at_sim IS NULL) OR (released_at >= booked_at_sim)));
-- @@ constraint_c public.ottoq_stall_bookings.ottoq_stall_bookings_state_check
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_state_check CHECK ((state = ANY (ARRAY['held'::text, 'active'::text, 'done'::text, 'released'::text, 'superseded'::text, 'interrupted'::text])));
-- @@ constraint_c public.ottoq_stall_bookings.ottoq_stall_bookings_window_check
ALTER TABLE ONLY public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_window_check CHECK (((NOT isempty(during)) AND (lower(during) IS NOT NULL) AND (upper(during) IS NOT NULL)));
-- @@ constraint_c public.ottoq_state_transitions.ottoq_state_transitions_entity_kind_check
ALTER TABLE ONLY public.ottoq_state_transitions ADD CONSTRAINT ottoq_state_transitions_entity_kind_check CHECK ((entity_kind = ANY (ARRAY['vehicle'::text, 'task'::text, 'stall'::text, 'schedule'::text, 'bess'::text])));
-- @@ constraint_c public.ottoq_state_transitions.ottoq_state_transitions_status_check
ALTER TABLE ONLY public.ottoq_state_transitions ADD CONSTRAINT ottoq_state_transitions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'deprecated'::text, 'draft'::text])));
-- @@ constraint_c public.ottoq_telemetry_packets.ottoq_telemetry_packets_data_source_check
ALTER TABLE ONLY public.ottoq_telemetry_packets ADD CONSTRAINT ottoq_telemetry_packets_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text, 'replay'::text, 'shadow'::text])));
-- @@ constraint_c public.ottoq_telemetry_packets.ottoq_telemetry_packets_packet_integrity_check
ALTER TABLE ONLY public.ottoq_telemetry_packets ADD CONSTRAINT ottoq_telemetry_packets_packet_integrity_check CHECK ((packet_integrity = ANY (ARRAY['full'::text, 'partial'::text, 'dropped'::text])));
-- @@ constraint_c public.ottoq_throughput_sweep_cells.ottoq_throughput_sweep_cells_control_not_self
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ADD CONSTRAINT ottoq_throughput_sweep_cells_control_not_self CHECK ((control_cell_code IS DISTINCT FROM cell_code));
-- @@ constraint_c public.ottoq_throughput_sweep_cells.ottoq_throughput_sweep_cells_fixed_params_check
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ADD CONSTRAINT ottoq_throughput_sweep_cells_fixed_params_check CHECK ((jsonb_typeof(fixed_params) = 'object'::text));
-- @@ constraint_c public.ottoq_throughput_sweep_cells.ottoq_throughput_sweep_cells_seat_check
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ADD CONSTRAINT ottoq_throughput_sweep_cells_seat_check CHECK ((seat = ANY (ARRAY['otto_q'::text, 'fifo'::text, 'greedy'::text])));
-- @@ constraint_c public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_replicates_check
ALTER TABLE ONLY public.ottoq_throughput_sweeps ADD CONSTRAINT ottoq_throughput_sweeps_replicates_check CHECK ((replicates >= 0));
-- @@ constraint_c public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_seeds_check
ALTER TABLE ONLY public.ottoq_throughput_sweeps ADD CONSTRAINT ottoq_throughput_sweeps_seeds_check CHECK ((cardinality(seeds) > 0));
-- @@ constraint_c public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_sim_min_per_tick_check
ALTER TABLE ONLY public.ottoq_throughput_sweeps ADD CONSTRAINT ottoq_throughput_sweeps_sim_min_per_tick_check CHECK (((sim_min_per_tick > (0)::numeric) AND (sim_min_per_tick <= (30)::numeric)));
-- @@ constraint_c public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_status_check
ALTER TABLE ONLY public.ottoq_throughput_sweeps ADD CONSTRAINT ottoq_throughput_sweeps_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'concluded'::text])));
-- @@ constraint_c public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_sweep_code_check
ALTER TABLE ONLY public.ottoq_throughput_sweeps ADD CONSTRAINT ottoq_throughput_sweeps_sweep_code_check CHECK ((sweep_code ~ '^[a-z0-9_]+$'::text));
-- @@ constraint_c public.ottoq_throughput_sweeps.ottoq_throughput_sweeps_ticks_check
ALTER TABLE ONLY public.ottoq_throughput_sweeps ADD CONSTRAINT ottoq_throughput_sweeps_ticks_check CHECK ((ticks > 0));
-- @@ constraint_c public.ottoq_training_runs.ottoq_training_runs_status_check
ALTER TABLE ONLY public.ottoq_training_runs ADD CONSTRAINT ottoq_training_runs_status_check CHECK ((status = ANY (ARRAY['running'::text, 'succeeded'::text, 'failed'::text, 'cancelled'::text])));
-- @@ constraint_c public.ottoq_v2_inbox.ottoq_v2_inbox_data_source_check
ALTER TABLE ONLY public.ottoq_v2_inbox ADD CONSTRAINT ottoq_v2_inbox_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text, 'replay'::text, 'shadow'::text])));
-- @@ constraint_c public.ottoq_v2_inbox.ottoq_v2_inbox_disposition_check
ALTER TABLE ONLY public.ottoq_v2_inbox ADD CONSTRAINT ottoq_v2_inbox_disposition_check CHECK ((disposition = ANY (ARRAY['applied'::text, 'late'::text])));
-- @@ constraint_c public.ottoq_v2_signal_ttl.ottoq_v2_signal_ttl_data_source_check
ALTER TABLE ONLY public.ottoq_v2_signal_ttl ADD CONSTRAINT ottoq_v2_signal_ttl_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text, 'replay'::text, 'shadow'::text])));
-- @@ constraint_c public.ottoq_v2_signal_ttl.ottoq_v2_signal_ttl_ttl_s_check
ALTER TABLE ONLY public.ottoq_v2_signal_ttl ADD CONSTRAINT ottoq_v2_signal_ttl_ttl_s_check CHECK ((ttl_s > 0));
-- @@ constraint_c public.ottoq_v2_signing_keys.ottoq_v2_signing_keys_kid_check
ALTER TABLE ONLY public.ottoq_v2_signing_keys ADD CONSTRAINT ottoq_v2_signing_keys_kid_check CHECK ((kid ~ '^[A-Za-z0-9._-]{1,64}$'::text));
-- @@ constraint_c public.ottoq_vehicle_classes.ottoq_vehicle_classes_status_check
ALTER TABLE ONLY public.ottoq_vehicle_classes ADD CONSTRAINT ottoq_vehicle_classes_status_check CHECK ((status = ANY (ARRAY['active'::text, 'deprecated'::text, 'archived'::text])));
-- @@ constraint_c public.ottoq_vehicle_commands.ottoq_vehicle_commands_command_type_check
ALTER TABLE ONLY public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_command_type_check CHECK ((command_type = ANY (ARRAY['dispatch'::text, 'begin_charge'::text, 'proceed_to_stall'::text, 'enter_wash'::text, 'enter_service'::text, 'stage'::text, 'hold'::text])));
-- @@ constraint_c public.ottoq_vehicle_commands.ottoq_vehicle_commands_data_source_check
ALTER TABLE ONLY public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text])));
-- @@ constraint_c public.ottoq_vehicle_commands.ottoq_vehicle_commands_reason_code_check
ALTER TABLE ONLY public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_reason_code_check CHECK (((reason_code IS NULL) OR (reason_code = ANY (ARRAY['target_occupied'::text, 'resource_faulted'::text, 'target_unknown'::text, 'vehicle_unresponsive'::text, 'command_malformed'::text, 'no_capacity'::text, 'superseded'::text, 'vehicle_state_incompatible'::text, 'run_ended'::text, 'vehicle_declined'::text]))));
-- @@ constraint_c public.ottoq_vehicle_commands.ottoq_vehicle_commands_refusal_has_code
ALTER TABLE ONLY public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_refusal_has_code CHECK (((status <> 'refused'::text) OR (reason_code IS NOT NULL))) NOT VALID;
-- @@ constraint_c public.ottoq_vehicle_commands.ottoq_vehicle_commands_status_check
ALTER TABLE ONLY public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_status_check CHECK ((status = ANY (ARRAY['issued'::text, 'confirmed'::text, 'executed'::text, 'refused'::text, 'expired'::text])));
-- @@ constraint_c public.ottoq_vehicle_dispatches.chk_completed_has_return_trigger
ALTER TABLE ONLY public.ottoq_vehicle_dispatches ADD CONSTRAINT chk_completed_has_return_trigger CHECK (((status <> 'completed'::text) OR (return_trigger IS NOT NULL))) NOT VALID;
-- @@ constraint_c public.ottoq_vehicle_dispatches.ottoq_vehicle_dispatches_status_check
ALTER TABLE ONLY public.ottoq_vehicle_dispatches ADD CONSTRAINT ottoq_vehicle_dispatches_status_check CHECK ((status = ANY (ARRAY['active'::text, 'returning'::text, 'completed'::text, 'aborted'::text])));
-- @@ constraint_c public.ottoq_vehicle_incidents.ottoq_vehicle_incidents_incident_type_check
ALTER TABLE ONLY public.ottoq_vehicle_incidents ADD CONSTRAINT ottoq_vehicle_incidents_incident_type_check CHECK ((incident_type = ANY (ARRAY['collision_minor'::text, 'collision_moderate'::text, 'collision_major'::text, 'breakdown_mechanical'::text, 'breakdown_electrical'::text, 'stranded_low_soc'::text, 'tire_failure'::text, 'sensor_critical_fail'::text, 'manual_safety_takeover'::text, 'third_party_impact'::text])));
-- @@ constraint_c public.ottoq_vehicle_incidents.ottoq_vehicle_incidents_resolution_status_check
ALTER TABLE ONLY public.ottoq_vehicle_incidents ADD CONSTRAINT ottoq_vehicle_incidents_resolution_status_check CHECK ((resolution_status = ANY (ARRAY['open'::text, 'tow_dispatched'::text, 'resolved'::text])));
-- @@ constraint_c public.ottoq_vehicle_incidents.ottoq_vehicle_incidents_severity_check
ALTER TABLE ONLY public.ottoq_vehicle_incidents ADD CONSTRAINT ottoq_vehicle_incidents_severity_check CHECK ((severity = ANY (ARRAY['minor'::text, 'moderate'::text, 'major'::text, 'safety_critical'::text])));
-- @@ constraint_c public.ottoq_vehicle_itineraries.ottoq_vehicle_itineraries_status_check
ALTER TABLE ONLY public.ottoq_vehicle_itineraries ADD CONSTRAINT ottoq_vehicle_itineraries_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'amended'::text, 'cancelled'::text])));
-- @@ constraint_c public.ottoq_vehicle_scout_findings.ottoq_vehicle_scout_known
ALTER TABLE ONLY public.ottoq_vehicle_scout_findings ADD CONSTRAINT ottoq_vehicle_scout_known CHECK ((scout = ANY (ARRAY['interval_due_departure'::text, 'same_trigger_rebound'::text, 'departed_below_target'::text, 'contract_wait_breach'::text, 'stranded_open_must_do'::text, 'legacy_task_residue'::text])));
-- @@ constraint_c public.ottoq_vehicle_scout_findings.ottoq_vehicle_scout_severity
ALTER TABLE ONLY public.ottoq_vehicle_scout_findings ADD CONSTRAINT ottoq_vehicle_scout_severity CHECK ((severity = ANY (ARRAY['critical'::text, 'high'::text, 'medium'::text, 'low'::text])));
-- @@ constraint_c public.ottoq_vehicle_wear.ottoq_vehicle_wear_cabin_litter_events_check
ALTER TABLE ONLY public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_cabin_litter_events_check CHECK ((cabin_litter_events >= 0));
-- @@ constraint_c public.ottoq_vehicle_wear.ottoq_vehicle_wear_drive_hours_total_check
ALTER TABLE ONLY public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_drive_hours_total_check CHECK ((drive_hours_total >= (0)::numeric));
-- @@ constraint_c public.ottoq_vehicle_wear.ottoq_vehicle_wear_drive_km_total_check
ALTER TABLE ONLY public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_drive_km_total_check CHECK ((drive_km_total >= (0)::numeric));
-- @@ constraint_c public.ottoq_vehicle_wear.ottoq_vehicle_wear_open_dtc_count_check
ALTER TABLE ONLY public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_open_dtc_count_check CHECK ((open_dtc_count >= 0));
-- @@ constraint_c public.ottoq_vehicle_wear.ottoq_vehicle_wear_soil_index_check
ALTER TABLE ONLY public.ottoq_vehicle_wear ADD CONSTRAINT ottoq_vehicle_wear_soil_index_check CHECK (((soil_index >= (0)::numeric) AND (soil_index <= (1)::numeric)));
-- @@ constraint_c public.ottoq_visit_needs.ottoq_visit_needs_status_check
ALTER TABLE ONLY public.ottoq_visit_needs ADD CONSTRAINT ottoq_visit_needs_status_check CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'complete'::text, 'carried_over'::text, 'superseded'::text])));
-- @@ constraint_c public.ottoq_visit_needs.ottoq_visit_needs_urgency_check
ALTER TABLE ONLY public.ottoq_visit_needs ADD CONSTRAINT ottoq_visit_needs_urgency_check CHECK ((urgency = ANY (ARRAY['immediate_dispatch'::text, 'standard'::text, 'overnight_hold'::text, 'tech_hold'::text])));
-- @@ constraint_c public.ottow_api_keys.ottow_api_keys_data_source_check
ALTER TABLE ONLY public.ottow_api_keys ADD CONSTRAINT ottow_api_keys_data_source_check CHECK ((data_source = ANY (ARRAY['production'::text, 'twin'::text, 'replay'::text, 'shadow'::text])));
-- @@ constraint_c public.ottow_api_keys.ottow_api_keys_source_check
ALTER TABLE ONLY public.ottow_api_keys ADD CONSTRAINT ottow_api_keys_source_check CHECK ((source = ANY (ARRAY['oem_webhook'::text, 'fleet_api'::text, 'vehicle_telemetry'::text])));
-- @@ constraint_c public.ottow_api_keys.ottow_api_keys_streams_check
ALTER TABLE ONLY public.ottow_api_keys ADD CONSTRAINT ottow_api_keys_streams_check CHECK (((streams IS NULL) OR ((cardinality(streams) > 0) AND (streams <@ ARRAY['energy'::text, 'telemetry'::text, 'ocpp'::text, 'arrival'::text, 'incident'::text]))));
-- @@ constraint_c public.ottow_dispatch_rules.ottow_dispatch_rules_action_check
ALTER TABLE ONLY public.ottow_dispatch_rules ADD CONSTRAINT ottow_dispatch_rules_action_check CHECK ((action = ANY (ARRAY['auto_dispatch'::text, 'queue_for_review'::text, 'reject'::text, 'alert_ops'::text])));
-- @@ constraint_c public.ottow_drivers.ottow_drivers_status_check
ALTER TABLE ONLY public.ottow_drivers ADD CONSTRAINT ottow_drivers_status_check CHECK ((status = ANY (ARRAY['available'::text, 'on_mission'::text, 'off_duty'::text, 'break'::text])));
-- @@ constraint_c public.ottow_mission_events.ottow_mission_events_actor_type_check
ALTER TABLE ONLY public.ottow_mission_events ADD CONSTRAINT ottow_mission_events_actor_type_check CHECK ((actor_type = ANY (ARRAY['driver'::text, 'dispatcher'::text, 'otto_q_engine'::text, 'system'::text])));
-- @@ constraint_c public.ottow_mission_events.ottow_mission_events_event_type_check
ALTER TABLE ONLY public.ottow_mission_events ADD CONSTRAINT ottow_mission_events_event_type_check CHECK ((event_type = ANY (ARRAY['status_change'::text, 'location_update'::text, 'note_added'::text, 'eta_updated'::text, 'stall_requested'::text, 'stall_assigned'::text, 'photo_attached'::text, 'driver_assigned'::text, 'priority_changed'::text, 'cancellation'::text, 'vehicle_condition_report'::text])));
-- @@ constraint_c public.ottow_missions.ottow_missions_incident_category_check
ALTER TABLE ONLY public.ottow_missions ADD CONSTRAINT ottow_missions_incident_category_check CHECK ((incident_category = ANY (ARRAY['battery_thermal'::text, 'mechanical'::text, 'collision'::text, 'sensor_failure'::text, 'flat_tire'::text, 'software_lockup'::text, 'vandalism'::text, 'interior_damage'::text, 'charger_fault'::text, 'other'::text])));
-- @@ constraint_c public.ottow_missions.ottow_missions_priority_check
ALTER TABLE ONLY public.ottow_missions ADD CONSTRAINT ottow_missions_priority_check CHECK ((priority = ANY (ARRAY['critical'::text, 'high'::text, 'standard'::text, 'low'::text])));
-- @@ constraint_c public.ottow_missions.ottow_missions_status_check
ALTER TABLE ONLY public.ottow_missions ADD CONSTRAINT ottow_missions_status_check CHECK ((status = ANY (ARRAY['reported'::text, 'dispatched'::text, 'en_route'::text, 'on_site'::text, 'vehicle_secured'::text, 'returning'::text, 'arrived_depot'::text, 'stall_assigned'::text, 'vehicle_delivered'::text, 'closed'::text, 'cancelled'::text])));
-- @@ constraint_c public.ottow_notifications.ottow_notifications_incident_category_check
ALTER TABLE ONLY public.ottow_notifications ADD CONSTRAINT ottow_notifications_incident_category_check CHECK ((incident_category = ANY (ARRAY['battery_thermal'::text, 'mechanical'::text, 'collision'::text, 'sensor_failure'::text, 'flat_tire'::text, 'software_lockup'::text, 'vandalism'::text, 'interior_damage'::text, 'charger_fault'::text, 'other'::text])));
-- @@ constraint_c public.ottow_notifications.ottow_notifications_priority_check
ALTER TABLE ONLY public.ottow_notifications ADD CONSTRAINT ottow_notifications_priority_check CHECK ((priority = ANY (ARRAY['critical'::text, 'high'::text, 'standard'::text, 'low'::text])));
-- @@ constraint_c public.ottow_notifications.ottow_notifications_source_check
ALTER TABLE ONLY public.ottow_notifications ADD CONSTRAINT ottow_notifications_source_check CHECK ((source = ANY (ARRAY['manual_dispatch'::text, 'oem_webhook'::text, 'fleet_api'::text, 'otto_q_engine'::text, 'vehicle_telemetry'::text])));
-- @@ constraint_c public.ottow_notifications.ottow_notifications_status_check
ALTER TABLE ONLY public.ottow_notifications ADD CONSTRAINT ottow_notifications_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'acknowledged'::text, 'mission_created'::text, 'rejected'::text])));
-- @@ constraint_c public.prediction_accuracy_daily.prediction_accuracy_daily_trend_direction_check
ALTER TABLE ONLY public.prediction_accuracy_daily ADD CONSTRAINT prediction_accuracy_daily_trend_direction_check CHECK ((trend_direction = ANY (ARRAY['improving'::text, 'stable'::text, 'declining'::text, 'insufficient_data'::text])));
-- @@ constraint_c public.prediction_explanations.prediction_explanations_generation_method_check
ALTER TABLE ONLY public.prediction_explanations ADD CONSTRAINT prediction_explanations_generation_method_check CHECK ((generation_method = ANY (ARRAY['at_prediction_time'::text, 'on_demand'::text, 'cached_recomputed'::text])));
-- @@ constraint_c public.prediction_outcomes.prediction_outcomes_accuracy_score_check
ALTER TABLE ONLY public.prediction_outcomes ADD CONSTRAINT prediction_outcomes_accuracy_score_check CHECK (((accuracy_score >= (0)::numeric) AND (accuracy_score <= (1)::numeric)));
-- @@ constraint_c public.prediction_outcomes.prediction_outcomes_scoring_method_check
ALTER TABLE ONLY public.prediction_outcomes ADD CONSTRAINT prediction_outcomes_scoring_method_check CHECK ((scoring_method = ANY (ARRAY['exact_match'::text, 'range_check'::text, 'mape'::text, 'directional'::text, 'rmse_normalized'::text])));
-- @@ constraint_c public.progression_decisions.progression_decisions_decision_check
ALTER TABLE ONLY public.progression_decisions ADD CONSTRAINT progression_decisions_decision_check CHECK ((decision = ANY (ARRAY['auto_advanced'::text, 'all_services_complete'::text, 'oem_gate_pending'::text, 'oem_accepted'::text, 'oem_rejected'::text, 'oem_timeout_auto_accepted'::text, 'oem_timeout_held'::text, 'oem_timeout_escalated'::text, 'oem_flagged_mid_flow'::text, 'tech_override_skip'::text, 'tech_override_reroute'::text, 'tech_override_hold'::text, 'tech_override_defer'::text, 'tech_override_flag_exception'::text, 'tech_override_escalate'::text, 'abnormality_blocked'::text, 'abnormality_resolved'::text, 'held_stall_unavailable'::text, 'overnight_staged'::text, 'scheduled_release_fired'::text, 'scheduled_release_deferred'::text])));
-- @@ constraint_c public.progression_decisions.progression_decisions_triggered_by_check
ALTER TABLE ONLY public.progression_decisions ADD CONSTRAINT progression_decisions_triggered_by_check CHECK ((triggered_by = ANY (ARRAY['tech_confirm'::text, 'ocpp_stop'::text, 'oem_webhook'::text, 'oem_console'::text, 'virtual_driver'::text, 'scheduler'::text, 'manual'::text, 'system'::text])));
-- @@ constraint_c public.retail_members.retail_members_membership_status_check
ALTER TABLE ONLY public.retail_members ADD CONSTRAINT retail_members_membership_status_check CHECK ((membership_status = ANY (ARRAY['active'::text, 'paused'::text, 'cancelled'::text, 'past_due'::text])));
-- @@ constraint_c public.retail_members.retail_members_membership_tier_check
ALTER TABLE ONLY public.retail_members ADD CONSTRAINT retail_members_membership_tier_check CHECK ((membership_tier = ANY (ARRAY['standard'::text, 'pro'::text])));
-- @@ constraint_c public.schedule_modifications.schedule_modifications_status_check
ALTER TABLE ONLY public.schedule_modifications ADD CONSTRAINT schedule_modifications_status_check CHECK ((status = ANY (ARRAY['requested'::text, 'approved'::text, 'applied'::text, 'rejected'::text, 'rolled_back'::text])));
-- @@ constraint_c public.schedule_tasks.schedule_tasks_abnormality_flagged_by_role_check
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_abnormality_flagged_by_role_check CHECK (((abnormality_flagged_by_role IS NULL) OR (abnormality_flagged_by_role = ANY (ARRAY['tech'::text, 'oem'::text, 'system'::text]))));
-- @@ constraint_c public.schedule_tasks.schedule_tasks_abnormality_resolved_by_role_check
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_abnormality_resolved_by_role_check CHECK (((abnormality_resolved_by_role IS NULL) OR (abnormality_resolved_by_role = ANY (ARRAY['tech'::text, 'oem'::text, 'system'::text]))));
-- @@ constraint_c public.schedule_tasks.schedule_tasks_oem_acceptance_state_check
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_oem_acceptance_state_check CHECK ((oem_acceptance_state = ANY (ARRAY['not_required'::text, 'pending'::text, 'accepted'::text, 'rejected'::text, 'auto_accepted_on_timeout'::text, 'held_on_timeout'::text, 'escalated_on_timeout'::text])));
-- @@ constraint_c public.schedule_tasks.schedule_tasks_tech_override_action_check
ALTER TABLE ONLY public.schedule_tasks ADD CONSTRAINT schedule_tasks_tech_override_action_check CHECK (((tech_override_action IS NULL) OR (tech_override_action = ANY (ARRAY['skip'::text, 'reroute'::text, 'hold'::text, 'flag_exception'::text, 'defer'::text, 'escalate'::text]))));
-- @@ constraint_c public.stalls.stalls_connector_type_check
ALTER TABLE ONLY public.stalls ADD CONSTRAINT stalls_connector_type_check CHECK (((connector_type IS NULL) OR (connector_type = ANY (ARRAY['CCS1'::text, 'CCS2'::text, 'NACS'::text, 'CHAdeMO'::text, 'Type1'::text, 'Type2'::text, 'Tesla_Proprietary'::text, 'MCS'::text, 'Multi'::text, 'NonCharging'::text, 'Other'::text]))));
-- @@ constraint_c public.stalls.stalls_heading_degrees_check
ALTER TABLE ONLY public.stalls ADD CONSTRAINT stalls_heading_degrees_check CHECK (((heading_degrees >= 0) AND (heading_degrees < 360)));
-- @@ constraint_c public.stalls.stalls_staging_role_check
ALTER TABLE ONLY public.stalls ADD CONSTRAINT stalls_staging_role_check CHECK ((staging_role = ANY (ARRAY['temp'::text, 'long'::text])));
-- @@ constraint_c public.stalls.stalls_status_check
ALTER TABLE ONLY public.stalls ADD CONSTRAINT stalls_status_check CHECK ((status = ANY (ARRAY['available'::text, 'occupied'::text, 'reserved'::text, 'maintenance'::text, 'closed'::text])));
-- @@ constraint_c public.tariff_schedules.tariff_schedules_billing_cycle_day_check
ALTER TABLE ONLY public.tariff_schedules ADD CONSTRAINT tariff_schedules_billing_cycle_day_check CHECK (((billing_cycle_day >= 1) AND (billing_cycle_day <= 28)));
-- @@ constraint_c public.tuning_iterations.tuning_iterations_simplex_move_type_check
ALTER TABLE ONLY public.tuning_iterations ADD CONSTRAINT tuning_iterations_simplex_move_type_check CHECK ((simplex_move_type = ANY (ARRAY['initial'::text, 'reflect'::text, 'expand'::text, 'contract_outside'::text, 'contract_inside'::text, 'shrink'::text])));
-- @@ constraint_c public.vehicle_need_profile.chk_vnp_rider_flag_kind
ALTER TABLE ONLY public.vehicle_need_profile ADD CONSTRAINT chk_vnp_rider_flag_kind CHECK (((rider_flag_kind IS NULL) OR (rider_flag_kind = ANY (ARRAY['interior'::text, 'exterior'::text]))));
-- @@ constraint_c public.vehicles.vehicle_owner_check
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicle_owner_check CHECK ((((fleet_operator_id IS NOT NULL) AND (retail_member_id IS NULL) AND (category = 'autonomous'::public.vehicle_category)) OR ((fleet_operator_id IS NULL) AND (retail_member_id IS NOT NULL) AND (category = 'retail'::public.vehicle_category)) OR ((fleet_operator_id IS NULL) AND (retail_member_id IS NULL))));
-- @@ constraint_c public.vehicles.vehicles_current_soc_source_check
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_current_soc_source_check CHECK (((current_soc_source IS NULL) OR (current_soc_source = ANY (ARRAY['oem_telemetry'::text, 'ocpp_meter'::text, 'manual'::text, 'estimated'::text]))));
-- @@ constraint_c public.vehicles.vehicles_inlet_type_check
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_inlet_type_check CHECK (((inlet_type IS NULL) OR (inlet_type = ANY (ARRAY['CCS1'::text, 'CCS2'::text, 'NACS'::text, 'CHAdeMO'::text, 'Type1'::text, 'Type2'::text, 'Tesla_Proprietary'::text, 'MCS'::text, 'Other'::text]))));
-- @@ constraint_c public.vehicles.vehicles_target_soc_check
ALTER TABLE ONLY public.vehicles ADD CONSTRAINT vehicles_target_soc_check CHECK (((target_soc >= 20) AND (target_soc <= 100)));
-- @@ constraint_c public.waves.waves_status_check
ALTER TABLE ONLY public.waves ADD CONSTRAINT waves_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'arriving'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])));
-- @@ constraint_c twin.arm_cycles.arm_cycles_direction_check
ALTER TABLE ONLY twin.arm_cycles ADD CONSTRAINT arm_cycles_direction_check CHECK ((direction = ANY (ARRAY['mate'::text, 'demate'::text])));
-- @@ constraint_c twin.arm_cycles.arm_cycles_outcome_check
ALTER TABLE ONLY twin.arm_cycles ADD CONSTRAINT arm_cycles_outcome_check CHECK ((outcome = ANY (ARRAY['latched'::text, 'cleared'::text, 'failed'::text, 'abandoned'::text, 'restaged'::text, 'emergency_released'::text])));
-- @@ constraint_c twin.arm_cycles.arm_cycles_phase_check
ALTER TABLE ONLY twin.arm_cycles ADD CONSTRAINT arm_cycles_phase_check CHECK ((phase = ANY (ARRAY['stowed'::text, 'unstow'::text, 'approach'::text, 'align'::text, 'insert'::text, 'latch'::text, 'charging'::text, 'unlatch'::text, 'extract'::text, 'retract'::text, 'clear'::text, 'fault'::text])));
-- @@ constraint_c twin.arm_registrations.arm_registrations_fix_source_check
ALTER TABLE ONLY twin.arm_registrations ADD CONSTRAINT arm_registrations_fix_source_check CHECK ((fix_source = ANY (ARRAY['fiducial_uwb'::text, 'uwb_only'::text, 'none'::text])));
-- @@ constraint_c twin.arm_registrations.arm_registrations_verdict_check
ALTER TABLE ONLY twin.arm_registrations ADD CONSTRAINT arm_registrations_verdict_check CHECK ((verdict = ANY (ARRAY['latched'::text, 'retry'::text, 'restage'::text])));
-- @@ constraint_c twin.ottoq_twin_operator_log.ottoq_twin_operator_log_outcome_check
ALTER TABLE ONLY twin.ottoq_twin_operator_log ADD CONSTRAINT ottoq_twin_operator_log_outcome_check CHECK ((outcome = ANY (ARRAY['executed'::text, 'refused'::text])));
-- @@ constraint_c twin.ottoq_twin_operators.ottoq_twin_operators_source_name_check
ALTER TABLE ONLY twin.ottoq_twin_operators ADD CONSTRAINT ottoq_twin_operators_source_name_check CHECK ((source_name ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'::text));
