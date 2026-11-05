-- 07_defaults.sql: 1469 statements, exported from production's catalog
-- @@ default public.ab_tests.id
ALTER TABLE ONLY public.ab_tests ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.ab_tests.traffic_split_pct
ALTER TABLE ONLY public.ab_tests ALTER COLUMN traffic_split_pct SET DEFAULT 50;
-- @@ default public.ab_tests.primary_metric
ALTER TABLE ONLY public.ab_tests ALTER COLUMN primary_metric SET DEFAULT 'mean_accuracy'::text;
-- @@ default public.ab_tests.minimum_sample_size
ALTER TABLE ONLY public.ab_tests ALTER COLUMN minimum_sample_size SET DEFAULT 100;
-- @@ default public.ab_tests.minimum_detectable_effect
ALTER TABLE ONLY public.ab_tests ALTER COLUMN minimum_detectable_effect SET DEFAULT 0.020;
-- @@ default public.ab_tests.significance_level
ALTER TABLE ONLY public.ab_tests ALTER COLUMN significance_level SET DEFAULT 0.050;
-- @@ default public.ab_tests.power
ALTER TABLE ONLY public.ab_tests ALTER COLUMN power SET DEFAULT 0.800;
-- @@ default public.ab_tests.status
ALTER TABLE ONLY public.ab_tests ALTER COLUMN status SET DEFAULT 'draft'::text;
-- @@ default public.ab_tests.variant_a_samples
ALTER TABLE ONLY public.ab_tests ALTER COLUMN variant_a_samples SET DEFAULT 0;
-- @@ default public.ab_tests.variant_b_samples
ALTER TABLE ONLY public.ab_tests ALTER COLUMN variant_b_samples SET DEFAULT 0;
-- @@ default public.ab_tests.safety_stop_conditions
ALTER TABLE ONLY public.ab_tests ALTER COLUMN safety_stop_conditions SET DEFAULT '{}'::jsonb;
-- @@ default public.ab_tests.created_at
ALTER TABLE ONLY public.ab_tests ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ab_tests.created_by
ALTER TABLE ONLY public.ab_tests ALTER COLUMN created_by SET DEFAULT 'system'::text;
-- @@ default public.ab_tests.updated_at
ALTER TABLE ONLY public.ab_tests ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.accuracy_alerts.id
ALTER TABLE ONLY public.accuracy_alerts ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.accuracy_alerts.observed_at
ALTER TABLE ONLY public.accuracy_alerts ALTER COLUMN observed_at SET DEFAULT now();
-- @@ default public.accuracy_alerts.created_at
ALTER TABLE ONLY public.accuracy_alerts ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.accuracy_slos.id
ALTER TABLE ONLY public.accuracy_slos ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.accuracy_slos.evaluation_window_hours
ALTER TABLE ONLY public.accuracy_slos ALTER COLUMN evaluation_window_hours SET DEFAULT 168;
-- @@ default public.accuracy_slos.min_samples
ALTER TABLE ONLY public.accuracy_slos ALTER COLUMN min_samples SET DEFAULT 20;
-- @@ default public.accuracy_slos.alert_cooldown_min
ALTER TABLE ONLY public.accuracy_slos ALTER COLUMN alert_cooldown_min SET DEFAULT 60;
-- @@ default public.accuracy_slos.auto_rollback_on_breach
ALTER TABLE ONLY public.accuracy_slos ALTER COLUMN auto_rollback_on_breach SET DEFAULT false;
-- @@ default public.accuracy_slos.auto_rollback_confidence
ALTER TABLE ONLY public.accuracy_slos ALTER COLUMN auto_rollback_confidence SET DEFAULT 0.950;
-- @@ default public.accuracy_slos.is_active
ALTER TABLE ONLY public.accuracy_slos ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.accuracy_slos.created_at
ALTER TABLE ONLY public.accuracy_slos ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.accuracy_slos.updated_at
ALTER TABLE ONLY public.accuracy_slos ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.action_guardrails.id
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.action_guardrails.max_per_hour
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN max_per_hour SET DEFAULT 3;
-- @@ default public.action_guardrails.max_per_shift
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN max_per_shift SET DEFAULT 10;
-- @@ default public.action_guardrails.max_per_day
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN max_per_day SET DEFAULT 20;
-- @@ default public.action_guardrails.min_confidence
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN min_confidence SET DEFAULT 0.850;
-- @@ default public.action_guardrails.auto_execute_confidence
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN auto_execute_confidence SET DEFAULT 0.950;
-- @@ default public.action_guardrails.cooldown_minutes
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN cooldown_minutes SET DEFAULT 15;
-- @@ default public.action_guardrails.requires_human_approval
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN requires_human_approval SET DEFAULT false;
-- @@ default public.action_guardrails.enabled
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN enabled SET DEFAULT true;
-- @@ default public.action_guardrails.allow_rollback
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN allow_rollback SET DEFAULT true;
-- @@ default public.action_guardrails.max_vehicles_affected
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN max_vehicles_affected SET DEFAULT 5;
-- @@ default public.action_guardrails.created_at
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.action_guardrails.updated_at
ALTER TABLE ONLY public.action_guardrails ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ai_decision_log.id
ALTER TABLE ONLY public.ai_decision_log ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.ai_decision_log.constraints
ALTER TABLE ONLY public.ai_decision_log ALTER COLUMN constraints SET DEFAULT '[]'::jsonb;
-- @@ default public.ai_decision_log.status
ALTER TABLE ONLY public.ai_decision_log ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ai_decision_log.created_at
ALTER TABLE ONLY public.ai_decision_log ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.api_integrations.id
ALTER TABLE ONLY public.api_integrations ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.api_integrations.is_active
ALTER TABLE ONLY public.api_integrations ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.api_integrations.auth_type
ALTER TABLE ONLY public.api_integrations ALTER COLUMN auth_type SET DEFAULT 'oauth2'::text;
-- @@ default public.api_integrations.credentials
ALTER TABLE ONLY public.api_integrations ALTER COLUMN credentials SET DEFAULT '{}'::jsonb;
-- @@ default public.api_integrations.endpoint_config
ALTER TABLE ONLY public.api_integrations ALTER COLUMN endpoint_config SET DEFAULT '{}'::jsonb;
-- @@ default public.api_integrations.rate_limit_requests_per_min
ALTER TABLE ONLY public.api_integrations ALTER COLUMN rate_limit_requests_per_min SET DEFAULT 60;
-- @@ default public.api_integrations.rate_limit_requests_per_day
ALTER TABLE ONLY public.api_integrations ALTER COLUMN rate_limit_requests_per_day SET DEFAULT 10000;
-- @@ default public.api_integrations.created_at
ALTER TABLE ONLY public.api_integrations ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.api_integrations.updated_at
ALTER TABLE ONLY public.api_integrations ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.autonomous_action_log.id
ALTER TABLE ONLY public.autonomous_action_log ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.autonomous_action_log.action_parameters
ALTER TABLE ONLY public.autonomous_action_log ALTER COLUMN action_parameters SET DEFAULT '{}'::jsonb;
-- @@ default public.autonomous_action_log.pre_state
ALTER TABLE ONLY public.autonomous_action_log ALTER COLUMN pre_state SET DEFAULT '{}'::jsonb;
-- @@ default public.autonomous_action_log.risk_factors
ALTER TABLE ONLY public.autonomous_action_log ALTER COLUMN risk_factors SET DEFAULT '[]'::jsonb;
-- @@ default public.autonomous_action_log.status
ALTER TABLE ONLY public.autonomous_action_log ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.autonomous_action_log.rollback_performed
ALTER TABLE ONLY public.autonomous_action_log ALTER COLUMN rollback_performed SET DEFAULT false;
-- @@ default public.autonomous_action_log.created_at
ALTER TABLE ONLY public.autonomous_action_log ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.autonomous_action_log.updated_at
ALTER TABLE ONLY public.autonomous_action_log ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.autonomous_action_log.retry_count
ALTER TABLE ONLY public.autonomous_action_log ALTER COLUMN retry_count SET DEFAULT 0;
-- @@ default public.availability_fix_proof_2026_08_03.id
ALTER TABLE ONLY public.availability_fix_proof_2026_08_03 ALTER COLUMN id SET DEFAULT nextval('public.availability_fix_proof_2026_08_03_id_seq'::regclass);
-- @@ default public.availability_fix_proof_2026_08_03.at
ALTER TABLE ONLY public.availability_fix_proof_2026_08_03 ALTER COLUMN at SET DEFAULT now();
-- @@ default public.bay_reservation_reconcile_2026_08_02.id
ALTER TABLE ONLY public.bay_reservation_reconcile_2026_08_02 ALTER COLUMN id SET DEFAULT nextval('public.bay_reservation_reconcile_2026_08_02_id_seq'::regclass);
-- @@ default public.bay_reservation_reconcile_2026_08_02.logged_at
ALTER TABLE ONLY public.bay_reservation_reconcile_2026_08_02 ALTER COLUMN logged_at SET DEFAULT now();
-- @@ default public.bess_snapshots.id
ALTER TABLE ONLY public.bess_snapshots ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.bess_snapshots."timestamp"
ALTER TABLE ONLY public.bess_snapshots ALTER COLUMN "timestamp" SET DEFAULT now();
-- @@ default public.bess_snapshots.grid_import_kw
ALTER TABLE ONLY public.bess_snapshots ALTER COLUMN grid_import_kw SET DEFAULT 0;
-- @@ default public.bess_snapshots.grid_export_kw
ALTER TABLE ONLY public.bess_snapshots ALTER COLUMN grid_export_kw SET DEFAULT 0;
-- @@ default public.bess_snapshots.cycle_count
ALTER TABLE ONLY public.bess_snapshots ALTER COLUMN cycle_count SET DEFAULT 0;
-- @@ default public.bess_snapshots.status
ALTER TABLE ONLY public.bess_snapshots ALTER COLUMN status SET DEFAULT 'standby'::public.bess_status;
-- @@ default public.bess_snapshots.created_at
ALTER TABLE ONLY public.bess_snapshots ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.busy_day_tick_probe_2026_08_01.probe_id
ALTER TABLE ONLY public.busy_day_tick_probe_2026_08_01 ALTER COLUMN probe_id SET DEFAULT nextval('public.busy_day_tick_probe_2026_08_01_probe_id_seq'::regclass);
-- @@ default public.busy_day_tick_probe_2026_08_01.at_wall
ALTER TABLE ONLY public.busy_day_tick_probe_2026_08_01 ALTER COLUMN at_wall SET DEFAULT now();
-- @@ default public.cert0022_fk_orphan_sweep.measured_at
ALTER TABLE ONLY public.cert0022_fk_orphan_sweep ALTER COLUMN measured_at SET DEFAULT now();
-- @@ default public.cert0022_misc.at_ts
ALTER TABLE ONLY public.cert0022_misc ALTER COLUMN at_ts SET DEFAULT now();
-- @@ default public.cert0022_orphan_refusal.at_ts
ALTER TABLE ONLY public.cert0022_orphan_refusal ALTER COLUMN at_ts SET DEFAULT now();
-- @@ default public.cert0022_orphans_by_class.at_ts
ALTER TABLE ONLY public.cert0022_orphans_by_class ALTER COLUMN at_ts SET DEFAULT now();
-- @@ default public.cert0022_purge_receipt.at_ts
ALTER TABLE ONLY public.cert0022_purge_receipt ALTER COLUMN at_ts SET DEFAULT now();
-- @@ default public.cert0023_coldiff.at_ts
ALTER TABLE ONLY public.cert0023_coldiff ALTER COLUMN at_ts SET DEFAULT now();
-- @@ default public.cert0023_energy_probe.at_ts
ALTER TABLE ONLY public.cert0023_energy_probe ALTER COLUMN at_ts SET DEFAULT now();
-- @@ default public.cert0023_fk_orphan_sweep.phase
ALTER TABLE ONLY public.cert0023_fk_orphan_sweep ALTER COLUMN phase SET DEFAULT 'p0023_prior_session'::text;
-- @@ default public.cert0023_fk_orphan_sweep.at_ts
ALTER TABLE ONLY public.cert0023_fk_orphan_sweep ALTER COLUMN at_ts SET DEFAULT now();
-- @@ default public.cert0023_misc.at_ts
ALTER TABLE ONLY public.cert0023_misc ALTER COLUMN at_ts SET DEFAULT now();
-- @@ default public.cert0023_trigger_paths.at_ts
ALTER TABLE ONLY public.cert0023_trigger_paths ALTER COLUMN at_ts SET DEFAULT now();
-- @@ default public.charger_cooldowns.id
ALTER TABLE ONLY public.charger_cooldowns ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.charger_cooldowns.cooldown_required
ALTER TABLE ONLY public.charger_cooldowns ALTER COLUMN cooldown_required SET DEFAULT false;
-- @@ default public.charger_cooldowns.cooldown_minutes_total
ALTER TABLE ONLY public.charger_cooldowns ALTER COLUMN cooldown_minutes_total SET DEFAULT 0;
-- @@ default public.charger_cooldowns.reduced_rate_available
ALTER TABLE ONLY public.charger_cooldowns ALTER COLUMN reduced_rate_available SET DEFAULT false;
-- @@ default public.charger_cooldowns.resolved
ALTER TABLE ONLY public.charger_cooldowns ALTER COLUMN resolved SET DEFAULT false;
-- @@ default public.charger_cooldowns.created_at
ALTER TABLE ONLY public.charger_cooldowns ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.charger_cooldowns.updated_at
ALTER TABLE ONLY public.charger_cooldowns ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.charger_health_scores.id
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.charger_health_scores.health_score
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN health_score SET DEFAULT 100;
-- @@ default public.charger_health_scores.uptime_percent_7d
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN uptime_percent_7d SET DEFAULT 100;
-- @@ default public.charger_health_scores.uptime_percent_30d
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN uptime_percent_30d SET DEFAULT 100;
-- @@ default public.charger_health_scores.fault_count_7d
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN fault_count_7d SET DEFAULT 0;
-- @@ default public.charger_health_scores.fault_count_30d
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN fault_count_30d SET DEFAULT 0;
-- @@ default public.charger_health_scores.avg_session_success_rate
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN avg_session_success_rate SET DEFAULT 1.0;
-- @@ default public.charger_health_scores.avg_power_delivery_efficiency
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN avg_power_delivery_efficiency SET DEFAULT 1.0;
-- @@ default public.charger_health_scores.total_sessions
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN total_sessions SET DEFAULT 0;
-- @@ default public.charger_health_scores.failed_sessions
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN failed_sessions SET DEFAULT 0;
-- @@ default public.charger_health_scores.recommended_maintenance
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN recommended_maintenance SET DEFAULT false;
-- @@ default public.charger_health_scores.factors
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN factors SET DEFAULT '[]'::jsonb;
-- @@ default public.charger_health_scores.calculated_at
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN calculated_at SET DEFAULT now();
-- @@ default public.charger_health_scores.created_at
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.charger_health_scores.updated_at
ALTER TABLE ONLY public.charger_health_scores ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.cuopt_enactment_proof_2026_08_01.captured_at
ALTER TABLE ONLY public.cuopt_enactment_proof_2026_08_01 ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.cuopt_invocation_log.invocation_id
ALTER TABLE ONLY public.cuopt_invocation_log ALTER COLUMN invocation_id SET DEFAULT nextval('public.cuopt_invocation_log_invocation_id_seq'::regclass);
-- @@ default public.cuopt_invocation_log.stage
ALTER TABLE ONLY public.cuopt_invocation_log ALTER COLUMN stage SET DEFAULT 'edge'::text;
-- @@ default public.cuopt_invocation_log.called_at
ALTER TABLE ONLY public.cuopt_invocation_log ALTER COLUMN called_at SET DEFAULT now();
-- @@ default public.data_quality_errors.id
ALTER TABLE ONLY public.data_quality_errors ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.data_quality_errors.severity
ALTER TABLE ONLY public.data_quality_errors ALTER COLUMN severity SET DEFAULT 'warning'::text;
-- @@ default public.data_quality_errors.predictions_affected
ALTER TABLE ONLY public.data_quality_errors ALTER COLUMN predictions_affected SET DEFAULT 0;
-- @@ default public.data_quality_errors.actions_blocked
ALTER TABLE ONLY public.data_quality_errors ALTER COLUMN actions_blocked SET DEFAULT 0;
-- @@ default public.data_quality_errors.detected_at
ALTER TABLE ONLY public.data_quality_errors ALTER COLUMN detected_at SET DEFAULT now();
-- @@ default public.data_quality_errors.created_at
ALTER TABLE ONLY public.data_quality_errors ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.decision_fusion_log.id
ALTER TABLE ONLY public.decision_fusion_log ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.decision_fusion_log.trigger_details
ALTER TABLE ONLY public.decision_fusion_log ALTER COLUMN trigger_details SET DEFAULT '{}'::jsonb;
-- @@ default public.decision_fusion_log.signals
ALTER TABLE ONLY public.decision_fusion_log ALTER COLUMN signals SET DEFAULT '[]'::jsonb;
-- @@ default public.decision_fusion_log.fusion_method
ALTER TABLE ONLY public.decision_fusion_log ALTER COLUMN fusion_method SET DEFAULT 'weighted_sum'::text;
-- @@ default public.decision_fusion_log.fusion_parameters
ALTER TABLE ONLY public.decision_fusion_log ALTER COLUMN fusion_parameters SET DEFAULT '{}'::jsonb;
-- @@ default public.decision_fusion_log.categories_addressed
ALTER TABLE ONLY public.decision_fusion_log ALTER COLUMN categories_addressed SET DEFAULT '{}'::text[];
-- @@ default public.decision_fusion_log.created_at
ALTER TABLE ONLY public.decision_fusion_log ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.demand_management_log.id
ALTER TABLE ONLY public.demand_management_log ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.demand_management_log."timestamp"
ALTER TABLE ONLY public.demand_management_log ALTER COLUMN "timestamp" SET DEFAULT now();
-- @@ default public.demand_management_log.vehicles_affected
ALTER TABLE ONLY public.demand_management_log ALTER COLUMN vehicles_affected SET DEFAULT '[]'::jsonb;
-- @@ default public.demand_management_log.created_at
ALTER TABLE ONLY public.demand_management_log ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.demand_shaping_plans.id
ALTER TABLE ONLY public.demand_shaping_plans ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.demand_shaping_plans.generated_at
ALTER TABLE ONLY public.demand_shaping_plans ALTER COLUMN generated_at SET DEFAULT now();
-- @@ default public.demand_shaping_plans.constraints_satisfied
ALTER TABLE ONLY public.demand_shaping_plans ALTER COLUMN constraints_satisfied SET DEFAULT true;
-- @@ default public.demand_shaping_plans.constraint_violations
ALTER TABLE ONLY public.demand_shaping_plans ALTER COLUMN constraint_violations SET DEFAULT '[]'::jsonb;
-- @@ default public.demand_shaping_plans.status
ALTER TABLE ONLY public.demand_shaping_plans ALTER COLUMN status SET DEFAULT 'generated'::text;
-- @@ default public.demand_shaping_plans.created_at
ALTER TABLE ONLY public.demand_shaping_plans ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.depot_state_snapshots.id
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.depot_state_snapshots.snapshot_at
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN snapshot_at SET DEFAULT now();
-- @@ default public.depot_state_snapshots.vehicles_on_site
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN vehicles_on_site SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.vehicles_charging
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN vehicles_charging SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.vehicles_in_service
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN vehicles_in_service SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.vehicles_staged
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN vehicles_staged SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.vehicles_en_route
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN vehicles_en_route SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.stall_utilization
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN stall_utilization SET DEFAULT '{}'::jsonb;
-- @@ default public.depot_state_snapshots.active_exceptions
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN active_exceptions SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.active_ottow_missions
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN active_ottow_missions SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.current_demand_kw
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN current_demand_kw SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.peak_demand_kw_15min
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN peak_demand_kw_15min SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.queue_depth
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN queue_depth SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.tasks_pending
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN tasks_pending SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.tasks_in_progress
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN tasks_in_progress SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.tasks_completed_today
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN tasks_completed_today SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.solar_generation_kw
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN solar_generation_kw SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.bess_output_kw
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN bess_output_kw SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.active_wave_codes
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN active_wave_codes SET DEFAULT '{}'::text[];
-- @@ default public.depot_state_snapshots.vehicles_expected_next_2h
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN vehicles_expected_next_2h SET DEFAULT 0;
-- @@ default public.depot_state_snapshots.created_at
ALTER TABLE ONLY public.depot_state_snapshots ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.depot_visit_reports.id
ALTER TABLE ONLY public.depot_visit_reports ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.depot_visit_reports.actual_sequence
ALTER TABLE ONLY public.depot_visit_reports ALTER COLUMN actual_sequence SET DEFAULT '[]'::jsonb;
-- @@ default public.depot_visit_reports.deviation_count
ALTER TABLE ONLY public.depot_visit_reports ALTER COLUMN deviation_count SET DEFAULT 0;
-- @@ default public.depot_visit_reports.overrides_applied
ALTER TABLE ONLY public.depot_visit_reports ALTER COLUMN overrides_applied SET DEFAULT '[]'::jsonb;
-- @@ default public.depot_visit_reports.abnormalities
ALTER TABLE ONLY public.depot_visit_reports ALTER COLUMN abnormalities SET DEFAULT '[]'::jsonb;
-- @@ default public.depot_visit_reports.oem_interactions
ALTER TABLE ONLY public.depot_visit_reports ALTER COLUMN oem_interactions SET DEFAULT '[]'::jsonb;
-- @@ default public.depot_visit_reports.exceptions_raised
ALTER TABLE ONLY public.depot_visit_reports ALTER COLUMN exceptions_raised SET DEFAULT '[]'::jsonb;
-- @@ default public.depot_visit_reports.audit_trail_complete
ALTER TABLE ONLY public.depot_visit_reports ALTER COLUMN audit_trail_complete SET DEFAULT true;
-- @@ default public.depot_visit_reports.generated_at
ALTER TABLE ONLY public.depot_visit_reports ALTER COLUMN generated_at SET DEFAULT now();
-- @@ default public.depot_visit_reports.payload
ALTER TABLE ONLY public.depot_visit_reports ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.depots.id
ALTER TABLE ONLY public.depots ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.depots.country
ALTER TABLE ONLY public.depots ALTER COLUMN country SET DEFAULT 'US'::text;
-- @@ default public.depots.timezone
ALTER TABLE ONLY public.depots ALTER COLUMN timezone SET DEFAULT 'America/Chicago'::text;
-- @@ default public.depots.status
ALTER TABLE ONLY public.depots ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.depots.config
ALTER TABLE ONLY public.depots ALTER COLUMN config SET DEFAULT '{}'::jsonb;
-- @@ default public.depots.created_at
ALTER TABLE ONLY public.depots ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.depots.updated_at
ALTER TABLE ONLY public.depots ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.depots.dcfc_safety_margin_pct
ALTER TABLE ONLY public.depots ALTER COLUMN dcfc_safety_margin_pct SET DEFAULT 10.0;
-- @@ default public.depots.demand_response_active
ALTER TABLE ONLY public.depots ALTER COLUMN demand_response_active SET DEFAULT false;
-- @@ default public.depots.operating_timezone
ALTER TABLE ONLY public.depots ALTER COLUMN operating_timezone SET DEFAULT 'America/Chicago'::text;
-- @@ default public.depots.overnight_staging_threshold_minutes
ALTER TABLE ONLY public.depots ALTER COLUMN overnight_staging_threshold_minutes SET DEFAULT 120;
-- @@ default public.depots.shift_change_buffer_minutes
ALTER TABLE ONLY public.depots ALTER COLUMN shift_change_buffer_minutes SET DEFAULT 15;
-- @@ default public.depots.feed_mode
ALTER TABLE ONLY public.depots ALTER COLUMN feed_mode SET DEFAULT 'sim'::text;
-- @@ default public.dispatch_commands.id
ALTER TABLE ONLY public.dispatch_commands ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.dispatch_commands.issued_at
ALTER TABLE ONLY public.dispatch_commands ALTER COLUMN issued_at SET DEFAULT now();
-- @@ default public.dispatch_commands.timeout_seconds
ALTER TABLE ONLY public.dispatch_commands ALTER COLUMN timeout_seconds SET DEFAULT 300;
-- @@ default public.dispatch_commands.attempt_number
ALTER TABLE ONLY public.dispatch_commands ALTER COLUMN attempt_number SET DEFAULT 1;
-- @@ default public.dispatch_commands.retry_eligible
ALTER TABLE ONLY public.dispatch_commands ALTER COLUMN retry_eligible SET DEFAULT true;
-- @@ default public.dispatch_commands.created_at
ALTER TABLE ONLY public.dispatch_commands ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.downstream_action_contracts.id
ALTER TABLE ONLY public.downstream_action_contracts ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.downstream_action_contracts.auth_requirements
ALTER TABLE ONLY public.downstream_action_contracts ALTER COLUMN auth_requirements SET DEFAULT '{}'::jsonb;
-- @@ default public.downstream_action_contracts.retry_policy
ALTER TABLE ONLY public.downstream_action_contracts ALTER COLUMN retry_policy SET DEFAULT '{}'::jsonb;
-- @@ default public.downstream_action_contracts.timeout_ms
ALTER TABLE ONLY public.downstream_action_contracts ALTER COLUMN timeout_ms SET DEFAULT 10000;
-- @@ default public.downstream_action_contracts.supports_rollback
ALTER TABLE ONLY public.downstream_action_contracts ALTER COLUMN supports_rollback SET DEFAULT false;
-- @@ default public.downstream_action_contracts.is_implemented
ALTER TABLE ONLY public.downstream_action_contracts ALTER COLUMN is_implemented SET DEFAULT false;
-- @@ default public.downstream_action_contracts.created_at
ALTER TABLE ONLY public.downstream_action_contracts ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.downstream_action_contracts.updated_at
ALTER TABLE ONLY public.downstream_action_contracts ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.early_recall_log.id
ALTER TABLE ONLY public.early_recall_log ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.early_recall_log.assessed_at
ALTER TABLE ONLY public.early_recall_log ALTER COLUMN assessed_at SET DEFAULT now();
-- @@ default public.early_recall_log.disruption_impact
ALTER TABLE ONLY public.early_recall_log ALTER COLUMN disruption_impact SET DEFAULT 'none'::text;
-- @@ default public.early_recall_log.vehicles_displaced
ALTER TABLE ONLY public.early_recall_log ALTER COLUMN vehicles_displaced SET DEFAULT 0;
-- @@ default public.early_recall_log.created_at
ALTER TABLE ONLY public.early_recall_log ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.emergency_queue_insertions.id
ALTER TABLE ONLY public.emergency_queue_insertions ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.emergency_queue_insertions.services_needed
ALTER TABLE ONLY public.emergency_queue_insertions ALTER COLUMN services_needed SET DEFAULT '[]'::jsonb;
-- @@ default public.emergency_queue_insertions.oem_approval_required
ALTER TABLE ONLY public.emergency_queue_insertions ALTER COLUMN oem_approval_required SET DEFAULT false;
-- @@ default public.emergency_queue_insertions.status
ALTER TABLE ONLY public.emergency_queue_insertions ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.emergency_queue_insertions.disruption_score
ALTER TABLE ONLY public.emergency_queue_insertions ALTER COLUMN disruption_score SET DEFAULT 0;
-- @@ default public.emergency_queue_insertions.vehicles_displaced
ALTER TABLE ONLY public.emergency_queue_insertions ALTER COLUMN vehicles_displaced SET DEFAULT '[]'::jsonb;
-- @@ default public.emergency_queue_insertions.created_at
ALTER TABLE ONLY public.emergency_queue_insertions ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.emergency_queue_insertions.updated_at
ALTER TABLE ONLY public.emergency_queue_insertions ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.emission_fix_smoke_2026_08_03.id
ALTER TABLE ONLY public.emission_fix_smoke_2026_08_03 ALTER COLUMN id SET DEFAULT nextval('public.emission_fix_smoke_2026_08_03_id_seq'::regclass);
-- @@ default public.emission_fix_smoke_2026_08_03.at
ALTER TABLE ONLY public.emission_fix_smoke_2026_08_03 ALTER COLUMN at SET DEFAULT now();
-- @@ default public.engine_config.id
ALTER TABLE ONLY public.engine_config ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.engine_config.early_recall_soc_advisory
ALTER TABLE ONLY public.engine_config ALTER COLUMN early_recall_soc_advisory SET DEFAULT 25;
-- @@ default public.engine_config.early_recall_soc_recommended
ALTER TABLE ONLY public.engine_config ALTER COLUMN early_recall_soc_recommended SET DEFAULT 18;
-- @@ default public.engine_config.early_recall_soc_critical
ALTER TABLE ONLY public.engine_config ALTER COLUMN early_recall_soc_critical SET DEFAULT 12;
-- @@ default public.engine_config.early_recall_check_interval_min
ALTER TABLE ONLY public.engine_config ALTER COLUMN early_recall_check_interval_min SET DEFAULT 5;
-- @@ default public.engine_config.cooldown_temp_threshold_c
ALTER TABLE ONLY public.engine_config ALTER COLUMN cooldown_temp_threshold_c SET DEFAULT 55.0;
-- @@ default public.engine_config.cooldown_base_minutes
ALTER TABLE ONLY public.engine_config ALTER COLUMN cooldown_base_minutes SET DEFAULT 5;
-- @@ default public.engine_config.cooldown_per_degree_minutes
ALTER TABLE ONLY public.engine_config ALTER COLUMN cooldown_per_degree_minutes SET DEFAULT 0.5;
-- @@ default public.engine_config.demand_shaping_enabled
ALTER TABLE ONLY public.engine_config ALTER COLUMN demand_shaping_enabled SET DEFAULT true;
-- @@ default public.engine_config.demand_target_pct_of_limit
ALTER TABLE ONLY public.engine_config ALTER COLUMN demand_target_pct_of_limit SET DEFAULT 85;
-- @@ default public.engine_config.bess_arbitrage_enabled
ALTER TABLE ONLY public.engine_config ALTER COLUMN bess_arbitrage_enabled SET DEFAULT false;
-- @@ default public.engine_config.ai_enabled
ALTER TABLE ONLY public.engine_config ALTER COLUMN ai_enabled SET DEFAULT false;
-- @@ default public.engine_config.ai_auto_apply_confidence
ALTER TABLE ONLY public.engine_config ALTER COLUMN ai_auto_apply_confidence SET DEFAULT 0.90;
-- @@ default public.engine_config.ai_model
ALTER TABLE ONLY public.engine_config ALTER COLUMN ai_model SET DEFAULT 'claude-sonnet-4-20250514'::text;
-- @@ default public.engine_config.ai_max_response_time_ms
ALTER TABLE ONLY public.engine_config ALTER COLUMN ai_max_response_time_ms SET DEFAULT 10000;
-- @@ default public.engine_config.max_emergency_insertions_per_hr
ALTER TABLE ONLY public.engine_config ALTER COLUMN max_emergency_insertions_per_hr SET DEFAULT 5;
-- @@ default public.engine_config.disruption_approval_threshold
ALTER TABLE ONLY public.engine_config ALTER COLUMN disruption_approval_threshold SET DEFAULT 40;
-- @@ default public.engine_config.modification_deadline_hours
ALTER TABLE ONLY public.engine_config ALTER COLUMN modification_deadline_hours SET DEFAULT 24;
-- @@ default public.engine_config.late_modification_fee_base
ALTER TABLE ONLY public.engine_config ALTER COLUMN late_modification_fee_base SET DEFAULT 50.00;
-- @@ default public.engine_config.cb_failure_threshold
ALTER TABLE ONLY public.engine_config ALTER COLUMN cb_failure_threshold SET DEFAULT 5;
-- @@ default public.engine_config.cb_reset_timeout_ms
ALTER TABLE ONLY public.engine_config ALTER COLUMN cb_reset_timeout_ms SET DEFAULT 60000;
-- @@ default public.engine_config.cb_half_open_max_requests
ALTER TABLE ONLY public.engine_config ALTER COLUMN cb_half_open_max_requests SET DEFAULT 3;
-- @@ default public.engine_config.min_move_buffer_seconds
ALTER TABLE ONLY public.engine_config ALTER COLUMN min_move_buffer_seconds SET DEFAULT 30;
-- @@ default public.engine_config.max_simultaneous_moves
ALTER TABLE ONLY public.engine_config ALTER COLUMN max_simultaneous_moves SET DEFAULT 5;
-- @@ default public.engine_config.emergency_stop_propagation
ALTER TABLE ONLY public.engine_config ALTER COLUMN emergency_stop_propagation SET DEFAULT true;
-- @@ default public.engine_config.created_at
ALTER TABLE ONLY public.engine_config ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.engine_config.updated_at
ALTER TABLE ONLY public.engine_config ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.exceptions.id
ALTER TABLE ONLY public.exceptions ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.exceptions.status
ALTER TABLE ONLY public.exceptions ALTER COLUMN status SET DEFAULT 'open'::public.exception_status;
-- @@ default public.exceptions.photos
ALTER TABLE ONLY public.exceptions ALTER COLUMN photos SET DEFAULT '[]'::jsonb;
-- @@ default public.exceptions.stall_closed
ALTER TABLE ONLY public.exceptions ALTER COLUMN stall_closed SET DEFAULT false;
-- @@ default public.exceptions.credit_issued
ALTER TABLE ONLY public.exceptions ALTER COLUMN credit_issued SET DEFAULT false;
-- @@ default public.exceptions.tow_requested
ALTER TABLE ONLY public.exceptions ALTER COLUMN tow_requested SET DEFAULT false;
-- @@ default public.exceptions.created_at
ALTER TABLE ONLY public.exceptions ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.exceptions.updated_at
ALTER TABLE ONLY public.exceptions ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.exceptions.metadata
ALTER TABLE ONLY public.exceptions ALTER COLUMN metadata SET DEFAULT '{}'::jsonb;
-- @@ default public.exceptions.blocks_progression
ALTER TABLE ONLY public.exceptions ALTER COLUMN blocks_progression SET DEFAULT false;
-- @@ default public.exceptions.data_source
ALTER TABLE ONLY public.exceptions ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.external_factor_sources.id
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.external_factor_sources.config
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN config SET DEFAULT '{}'::jsonb;
-- @@ default public.external_factor_sources.poll_interval_sec
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN poll_interval_sec SET DEFAULT 900;
-- @@ default public.external_factor_sources.poll_mode
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN poll_mode SET DEFAULT 'pull'::text;
-- @@ default public.external_factor_sources.schema_version
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN schema_version SET DEFAULT 1;
-- @@ default public.external_factor_sources.required_fields
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN required_fields SET DEFAULT '{}'::text[];
-- @@ default public.external_factor_sources.staleness_tolerance_sec
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN staleness_tolerance_sec SET DEFAULT 1800;
-- @@ default public.external_factor_sources.consecutive_failures
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN consecutive_failures SET DEFAULT 0;
-- @@ default public.external_factor_sources.health_status
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN health_status SET DEFAULT 'unknown'::text;
-- @@ default public.external_factor_sources.is_active
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.external_factor_sources.fallback_strategy
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN fallback_strategy SET DEFAULT 'last_known'::text;
-- @@ default public.external_factor_sources.created_at
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.external_factor_sources.updated_at
ALTER TABLE ONLY public.external_factor_sources ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.external_factors_log.id
ALTER TABLE ONLY public.external_factors_log ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.external_factors_log.ingested_at
ALTER TABLE ONLY public.external_factors_log ALTER COLUMN ingested_at SET DEFAULT now();
-- @@ default public.external_factors_log.quality_score
ALTER TABLE ONLY public.external_factors_log ALTER COLUMN quality_score SET DEFAULT 1.000;
-- @@ default public.external_factors_log.is_interpolated
ALTER TABLE ONLY public.external_factors_log ALTER COLUMN is_interpolated SET DEFAULT false;
-- @@ default public.external_factors_log.created_at
ALTER TABLE ONLY public.external_factors_log ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.fleet_features_daily.id
ALTER TABLE ONLY public.fleet_features_daily ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.fleet_features_daily.features
ALTER TABLE ONLY public.fleet_features_daily ALTER COLUMN features SET DEFAULT '{}'::jsonb;
-- @@ default public.fleet_features_daily.sample_count
ALTER TABLE ONLY public.fleet_features_daily ALTER COLUMN sample_count SET DEFAULT 0;
-- @@ default public.fleet_features_daily.confidence
ALTER TABLE ONLY public.fleet_features_daily ALTER COLUMN confidence SET DEFAULT 0.500;
-- @@ default public.fleet_features_daily.lookback_days
ALTER TABLE ONLY public.fleet_features_daily ALTER COLUMN lookback_days SET DEFAULT 30;
-- @@ default public.fleet_features_daily.computed_at
ALTER TABLE ONLY public.fleet_features_daily ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.fleet_features_daily.created_at
ALTER TABLE ONLY public.fleet_features_daily ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.fleet_operators.id
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.fleet_operators.contract_tier
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN contract_tier SET DEFAULT 'standard'::text;
-- @@ default public.fleet_operators.priority
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN priority SET DEFAULT 'standard'::public.priority_tier;
-- @@ default public.fleet_operators.default_target_soc
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN default_target_soc SET DEFAULT 90;
-- @@ default public.fleet_operators.default_service_sequence
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN default_service_sequence SET DEFAULT '["charging", "cleaning", "staging"]'::jsonb;
-- @@ default public.fleet_operators.fleet_api_config
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN fleet_api_config SET DEFAULT '{}'::jsonb;
-- @@ default public.fleet_operators.notification_preferences
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN notification_preferences SET DEFAULT '{"daily_report": ["email"], "service_start": ["in_app", "webhook"], "vehicle_ready": ["in_app", "webhook"], "weekly_report": ["email"], "monthly_report": ["email"], "exception_raised": ["in_app", "webhook", "sms"], "service_complete": ["in_app", "webhook"]}'::jsonb;
-- @@ default public.fleet_operators.is_active
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.fleet_operators.created_at
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.fleet_operators.updated_at
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.fleet_operators.progression_acceptance_mode
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN progression_acceptance_mode SET DEFAULT 'oem_webhook_final_only'::text;
-- @@ default public.fleet_operators.oem_acceptance_timeout_seconds
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN oem_acceptance_timeout_seconds SET DEFAULT 180;
-- @@ default public.fleet_operators.oem_acceptance_on_timeout
ALTER TABLE ONLY public.fleet_operators ALTER COLUMN oem_acceptance_on_timeout SET DEFAULT 'auto_accept'::text;
-- @@ default public.fwd1_cert_424242.id
ALTER TABLE ONLY public.fwd1_cert_424242 ALTER COLUMN id SET DEFAULT nextval('public.fwd1_cert_424242_id_seq'::regclass);
-- @@ default public.fwd1_cert_424242.captured_at
ALTER TABLE ONLY public.fwd1_cert_424242 ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.fwd2_atom_samples.sampled_at
ALTER TABLE ONLY public.fwd2_atom_samples ALTER COLUMN sampled_at SET DEFAULT now();
-- @@ default public.fwd2_card_samples.sampled_at
ALTER TABLE ONLY public.fwd2_card_samples ALTER COLUMN sampled_at SET DEFAULT now();
-- @@ default public.fwd2_profile_samples.sampled_at
ALTER TABLE ONLY public.fwd2_profile_samples ALTER COLUMN sampled_at SET DEFAULT now();
-- @@ default public.fwd2_urgency_samples.sample_id
ALTER TABLE ONLY public.fwd2_urgency_samples ALTER COLUMN sample_id SET DEFAULT nextval('public.fwd2_urgency_samples_sample_id_seq'::regclass);
-- @@ default public.fwd2_urgency_samples.sampled_at
ALTER TABLE ONLY public.fwd2_urgency_samples ALTER COLUMN sampled_at SET DEFAULT now();
-- @@ default public.fwd3_gate_probe.at
ALTER TABLE ONLY public.fwd3_gate_probe ALTER COLUMN at SET DEFAULT clock_timestamp();
-- @@ default public.integration_health.id
ALTER TABLE ONLY public.integration_health ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.integration_health.circuit_state
ALTER TABLE ONLY public.integration_health ALTER COLUMN circuit_state SET DEFAULT 'closed'::public.circuit_breaker_state;
-- @@ default public.integration_health.consecutive_failures
ALTER TABLE ONLY public.integration_health ALTER COLUMN consecutive_failures SET DEFAULT 0;
-- @@ default public.integration_health.failure_threshold
ALTER TABLE ONLY public.integration_health ALTER COLUMN failure_threshold SET DEFAULT 5;
-- @@ default public.integration_health.avg_response_ms
ALTER TABLE ONLY public.integration_health ALTER COLUMN avg_response_ms SET DEFAULT 0;
-- @@ default public.integration_health.p95_response_ms
ALTER TABLE ONLY public.integration_health ALTER COLUMN p95_response_ms SET DEFAULT 0;
-- @@ default public.integration_health.p99_response_ms
ALTER TABLE ONLY public.integration_health ALTER COLUMN p99_response_ms SET DEFAULT 0;
-- @@ default public.integration_health.success_rate_1h
ALTER TABLE ONLY public.integration_health ALTER COLUMN success_rate_1h SET DEFAULT 100;
-- @@ default public.integration_health.success_rate_24h
ALTER TABLE ONLY public.integration_health ALTER COLUMN success_rate_24h SET DEFAULT 100;
-- @@ default public.integration_health.total_requests_24h
ALTER TABLE ONLY public.integration_health ALTER COLUMN total_requests_24h SET DEFAULT 0;
-- @@ default public.integration_health.created_at
ALTER TABLE ONLY public.integration_health ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.integration_health.updated_at
ALTER TABLE ONLY public.integration_health ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.leg_why_smoke_2026_08_02.captured_at
ALTER TABLE ONLY public.leg_why_smoke_2026_08_02 ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.maintenance_log.id
ALTER TABLE ONLY public.maintenance_log ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.maintenance_log.performed_at
ALTER TABLE ONLY public.maintenance_log ALTER COLUMN performed_at SET DEFAULT now();
-- @@ default public.maintenance_log.parts_used
ALTER TABLE ONLY public.maintenance_log ALTER COLUMN parts_used SET DEFAULT '[]'::jsonb;
-- @@ default public.maintenance_log.photos
ALTER TABLE ONLY public.maintenance_log ALTER COLUMN photos SET DEFAULT '[]'::jsonb;
-- @@ default public.maintenance_log.follow_up_required
ALTER TABLE ONLY public.maintenance_log ALTER COLUMN follow_up_required SET DEFAULT false;
-- @@ default public.maintenance_log.created_at
ALTER TABLE ONLY public.maintenance_log ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.maintenance_schedules.id
ALTER TABLE ONLY public.maintenance_schedules ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.maintenance_schedules.preferred_day_of_week
ALTER TABLE ONLY public.maintenance_schedules ALTER COLUMN preferred_day_of_week SET DEFAULT '[]'::jsonb;
-- @@ default public.maintenance_schedules.estimated_duration_minutes
ALTER TABLE ONLY public.maintenance_schedules ALTER COLUMN estimated_duration_minutes SET DEFAULT 60;
-- @@ default public.maintenance_schedules.status
ALTER TABLE ONLY public.maintenance_schedules ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.maintenance_schedules.is_auto_scheduled
ALTER TABLE ONLY public.maintenance_schedules ALTER COLUMN is_auto_scheduled SET DEFAULT true;
-- @@ default public.maintenance_schedules.created_at
ALTER TABLE ONLY public.maintenance_schedules ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.maintenance_schedules.updated_at
ALTER TABLE ONLY public.maintenance_schedules ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.mig0020_prestate.captured_at
ALTER TABLE ONLY public.mig0020_prestate ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.model_parameters.id
ALTER TABLE ONLY public.model_parameters ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.model_parameters.parameters
ALTER TABLE ONLY public.model_parameters ALTER COLUMN parameters SET DEFAULT '{}'::jsonb;
-- @@ default public.model_parameters.is_active
ALTER TABLE ONLY public.model_parameters ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.model_parameters.version
ALTER TABLE ONLY public.model_parameters ALTER COLUMN version SET DEFAULT 1;
-- @@ default public.model_parameters.tuned_by
ALTER TABLE ONLY public.model_parameters ALTER COLUMN tuned_by SET DEFAULT 'seed'::text;
-- @@ default public.model_parameters.performance_metrics
ALTER TABLE ONLY public.model_parameters ALTER COLUMN performance_metrics SET DEFAULT '{}'::jsonb;
-- @@ default public.model_parameters.created_at
ALTER TABLE ONLY public.model_parameters ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.model_parameters.updated_at
ALTER TABLE ONLY public.model_parameters ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.model_tuning_runs.id
ALTER TABLE ONLY public.model_tuning_runs ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.model_tuning_runs.parameter_diffs
ALTER TABLE ONLY public.model_tuning_runs ALTER COLUMN parameter_diffs SET DEFAULT '[]'::jsonb;
-- @@ default public.model_tuning_runs.samples_evaluated
ALTER TABLE ONLY public.model_tuning_runs ALTER COLUMN samples_evaluated SET DEFAULT 0;
-- @@ default public.model_tuning_runs.evaluation_window_hours
ALTER TABLE ONLY public.model_tuning_runs ALTER COLUMN evaluation_window_hours SET DEFAULT 168;
-- @@ default public.model_tuning_runs.tuning_method
ALTER TABLE ONLY public.model_tuning_runs ALTER COLUMN tuning_method SET DEFAULT 'gradient_free'::text;
-- @@ default public.model_tuning_runs.status
ALTER TABLE ONLY public.model_tuning_runs ALTER COLUMN status SET DEFAULT 'completed'::text;
-- @@ default public.model_tuning_runs.created_at
ALTER TABLE ONLY public.model_tuning_runs ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.model_tuning_runs.updated_at
ALTER TABLE ONLY public.model_tuning_runs ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.model_versions.id
ALTER TABLE ONLY public.model_versions ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.model_versions.status
ALTER TABLE ONLY public.model_versions ALTER COLUMN status SET DEFAULT 'draft'::text;
-- @@ default public.model_versions.accuracy_metrics
ALTER TABLE ONLY public.model_versions ALTER COLUMN accuracy_metrics SET DEFAULT '{}'::jsonb;
-- @@ default public.model_versions.created_at
ALTER TABLE ONLY public.model_versions ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.model_versions.created_by
ALTER TABLE ONLY public.model_versions ALTER COLUMN created_by SET DEFAULT 'system'::text;
-- @@ default public.model_versions.training_metadata
ALTER TABLE ONLY public.model_versions ALTER COLUMN training_metadata SET DEFAULT '{}'::jsonb;
-- @@ default public.model_versions.shadow_traffic_pct
ALTER TABLE ONLY public.model_versions ALTER COLUMN shadow_traffic_pct SET DEFAULT 0;
-- @@ default public.notifications.id
ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.notifications.status
ALTER TABLE ONLY public.notifications ALTER COLUMN status SET DEFAULT 'queued'::public.notification_status;
-- @@ default public.notifications.webhook_attempts
ALTER TABLE ONLY public.notifications ALTER COLUMN webhook_attempts SET DEFAULT 0;
-- @@ default public.notifications.created_at
ALTER TABLE ONLY public.notifications ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ocpp_meter_values.id
ALTER TABLE ONLY public.ocpp_meter_values ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.ocpp_meter_values.created_at
ALTER TABLE ONLY public.ocpp_meter_values ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ocpp_sessions.id
ALTER TABLE ONLY public.ocpp_sessions ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.ocpp_sessions.status
ALTER TABLE ONLY public.ocpp_sessions ALTER COLUMN status SET DEFAULT 'active'::public.ocpp_session_status;
-- @@ default public.ocpp_sessions.energy_delivered_kwh
ALTER TABLE ONLY public.ocpp_sessions ALTER COLUMN energy_delivered_kwh SET DEFAULT 0;
-- @@ default public.ocpp_sessions.peak_power_kw
ALTER TABLE ONLY public.ocpp_sessions ALTER COLUMN peak_power_kw SET DEFAULT 0;
-- @@ default public.ocpp_sessions.avg_power_kw
ALTER TABLE ONLY public.ocpp_sessions ALTER COLUMN avg_power_kw SET DEFAULT 0;
-- @@ default public.ocpp_sessions.meter_values_count
ALTER TABLE ONLY public.ocpp_sessions ALTER COLUMN meter_values_count SET DEFAULT 0;
-- @@ default public.ocpp_sessions.charging_profile_applied
ALTER TABLE ONLY public.ocpp_sessions ALTER COLUMN charging_profile_applied SET DEFAULT false;
-- @@ default public.ocpp_sessions.fault_count
ALTER TABLE ONLY public.ocpp_sessions ALTER COLUMN fault_count SET DEFAULT 0;
-- @@ default public.ocpp_sessions.created_at
ALTER TABLE ONLY public.ocpp_sessions ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ocpp_sessions.updated_at
ALTER TABLE ONLY public.ocpp_sessions ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_0249_start_log.id
ALTER TABLE ONLY public.ottoq_0249_start_log ALTER COLUMN id SET DEFAULT nextval('public.ottoq_0249_start_log_id_seq'::regclass);
-- @@ default public.ottoq_0249_start_log.at
ALTER TABLE ONLY public.ottoq_0249_start_log ALTER COLUMN at SET DEFAULT now();
-- @@ default public.ottoq_0249_start_log.payload
ALTER TABLE ONLY public.ottoq_0249_start_log ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_ab_runs.ab_run_id
ALTER TABLE ONLY public.ottoq_ab_runs ALTER COLUMN ab_run_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_ab_runs.scored_at
ALTER TABLE ONLY public.ottoq_ab_runs ALTER COLUMN scored_at SET DEFAULT now();
-- @@ default public.ottoq_agent_call_ledger.call_id
ALTER TABLE ONLY public.ottoq_agent_call_ledger ALTER COLUMN call_id SET DEFAULT nextval('public.ottoq_agent_call_ledger_call_id_seq'::regclass);
-- @@ default public.ottoq_agent_call_ledger.detail
ALTER TABLE ONLY public.ottoq_agent_call_ledger ALTER COLUMN detail SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_agent_call_ledger.called_at
ALTER TABLE ONLY public.ottoq_agent_call_ledger ALTER COLUMN called_at SET DEFAULT now();
-- @@ default public.ottoq_agent_charge_orders.order_id
ALTER TABLE ONLY public.ottoq_agent_charge_orders ALTER COLUMN order_id SET DEFAULT nextval('public.ottoq_agent_charge_orders_order_id_seq'::regclass);
-- @@ default public.ottoq_agent_charge_orders.recorded_at
ALTER TABLE ONLY public.ottoq_agent_charge_orders ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_agent_charge_orders.source_kind
ALTER TABLE ONLY public.ottoq_agent_charge_orders ALTER COLUMN source_kind SET DEFAULT 'live'::text;
-- @@ default public.ottoq_agent_demo_passcode.enabled
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ALTER COLUMN enabled SET DEFAULT false;
-- @@ default public.ottoq_agent_demo_passcode.session_minutes
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ALTER COLUMN session_minutes SET DEFAULT 240;
-- @@ default public.ottoq_agent_demo_passcode.set_at
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ALTER COLUMN set_at SET DEFAULT now();
-- @@ default public.ottoq_agent_demo_passcode.set_by
ALTER TABLE ONLY public.ottoq_agent_demo_passcode ALTER COLUMN set_by SET DEFAULT SESSION_USER;
-- @@ default public.ottoq_agent_pass_evidence.pass_id
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ALTER COLUMN pass_id SET DEFAULT nextval('public.ottoq_agent_pass_evidence_pass_id_seq'::regclass);
-- @@ default public.ottoq_agent_pass_evidence.seat
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ALTER COLUMN seat SET DEFAULT 'ottoq_prime'::text;
-- @@ default public.ottoq_agent_pass_evidence.levers
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ALTER COLUMN levers SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_agent_pass_evidence.decision_written
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ALTER COLUMN decision_written SET DEFAULT true;
-- @@ default public.ottoq_agent_pass_evidence.recorded_at
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_agent_pass_evidence.source_kind
ALTER TABLE ONLY public.ottoq_agent_pass_evidence ALTER COLUMN source_kind SET DEFAULT 'live'::text;
-- @@ default public.ottoq_agent_principals.principal_id
ALTER TABLE ONLY public.ottoq_agent_principals ALTER COLUMN principal_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_agent_principals.depot_id
ALTER TABLE ONLY public.ottoq_agent_principals ALTER COLUMN depot_id SET DEFAULT '11111111-1111-1111-1111-111111111111'::uuid;
-- @@ default public.ottoq_agent_principals.capabilities
ALTER TABLE ONLY public.ottoq_agent_principals ALTER COLUMN capabilities SET DEFAULT ARRAY['read'::text, 'note'::text];
-- @@ default public.ottoq_agent_principals.status
ALTER TABLE ONLY public.ottoq_agent_principals ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_agent_principals.rate_limit_per_min
ALTER TABLE ONLY public.ottoq_agent_principals ALTER COLUMN rate_limit_per_min SET DEFAULT 60;
-- @@ default public.ottoq_agent_principals.max_pending
ALTER TABLE ONLY public.ottoq_agent_principals ALTER COLUMN max_pending SET DEFAULT 20;
-- @@ default public.ottoq_agent_principals.created_at
ALTER TABLE ONLY public.ottoq_agent_principals ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_agent_principals.created_by
ALTER TABLE ONLY public.ottoq_agent_principals ALTER COLUMN created_by SET DEFAULT SESSION_USER;
-- @@ default public.ottoq_agent_principals.origin
ALTER TABLE ONLY public.ottoq_agent_principals ALTER COLUMN origin SET DEFAULT 'issued'::text;
-- @@ default public.ottoq_agent_prompts.first_seen_at
ALTER TABLE ONLY public.ottoq_agent_prompts ALTER COLUMN first_seen_at SET DEFAULT now();
-- @@ default public.ottoq_agent_requests.request_id
ALTER TABLE ONLY public.ottoq_agent_requests ALTER COLUMN request_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_agent_requests.payload
ALTER TABLE ONLY public.ottoq_agent_requests ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_agent_requests.priority
ALTER TABLE ONLY public.ottoq_agent_requests ALTER COLUMN priority SET DEFAULT 'normal'::text;
-- @@ default public.ottoq_agent_requests.status
ALTER TABLE ONLY public.ottoq_agent_requests ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_agent_requests.created_at
ALTER TABLE ONLY public.ottoq_agent_requests ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_anomaly_detectors.detector_id
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN detector_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_anomaly_detectors.parameters
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN parameters SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_anomaly_detectors.anomaly_score_threshold
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN anomaly_score_threshold SET DEFAULT 0.7;
-- @@ default public.ottoq_anomaly_detectors.severity_low_threshold
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN severity_low_threshold SET DEFAULT 0.5;
-- @@ default public.ottoq_anomaly_detectors.severity_high_threshold
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN severity_high_threshold SET DEFAULT 0.85;
-- @@ default public.ottoq_anomaly_detectors.severity_critical_threshold
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN severity_critical_threshold SET DEFAULT 0.95;
-- @@ default public.ottoq_anomaly_detectors.emit_event
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN emit_event SET DEFAULT true;
-- @@ default public.ottoq_anomaly_detectors.create_exception
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN create_exception SET DEFAULT false;
-- @@ default public.ottoq_anomaly_detectors.status
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_anomaly_detectors.created_at
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_anomaly_detectors.updated_at
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_anomaly_detectors.observations_total
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN observations_total SET DEFAULT 0;
-- @@ default public.ottoq_anomaly_detectors.observations_anomalous
ALTER TABLE ONLY public.ottoq_anomaly_detectors ALTER COLUMN observations_anomalous SET DEFAULT 0;
-- @@ default public.ottoq_anomaly_observations.observation_id
ALTER TABLE ONLY public.ottoq_anomaly_observations ALTER COLUMN observation_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_anomaly_observations.observation_seq
ALTER TABLE ONLY public.ottoq_anomaly_observations ALTER COLUMN observation_seq SET DEFAULT nextval('public.ottoq_anomaly_observations_observation_seq_seq'::regclass);
-- @@ default public.ottoq_anomaly_observations.observed_at
ALTER TABLE ONLY public.ottoq_anomaly_observations ALTER COLUMN observed_at SET DEFAULT now();
-- @@ default public.ottoq_anomaly_observations.context
ALTER TABLE ONLY public.ottoq_anomaly_observations ALTER COLUMN context SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_anomaly_observations.event_emitted
ALTER TABLE ONLY public.ottoq_anomaly_observations ALTER COLUMN event_emitted SET DEFAULT false;
-- @@ default public.ottoq_anomaly_observations.exception_created
ALTER TABLE ONLY public.ottoq_anomaly_observations ALTER COLUMN exception_created SET DEFAULT false;
-- @@ default public.ottoq_arbiter_assessments.assessment_id
ALTER TABLE ONLY public.ottoq_arbiter_assessments ALTER COLUMN assessment_id SET DEFAULT nextval('public.ottoq_arbiter_assessments_assessment_id_seq'::regclass);
-- @@ default public.ottoq_arbiter_assessments.assessed_at
ALTER TABLE ONLY public.ottoq_arbiter_assessments ALTER COLUMN assessed_at SET DEFAULT now();
-- @@ default public.ottoq_audit_bundles.bundle_id
ALTER TABLE ONLY public.ottoq_audit_bundles ALTER COLUMN bundle_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_audit_bundles.bundle_seq
ALTER TABLE ONLY public.ottoq_audit_bundles ALTER COLUMN bundle_seq SET DEFAULT nextval('public.ottoq_audit_bundles_bundle_seq_seq'::regclass);
-- @@ default public.ottoq_audit_bundles.format
ALTER TABLE ONLY public.ottoq_audit_bundles ALTER COLUMN format SET DEFAULT 'jsonl'::text;
-- @@ default public.ottoq_audit_bundles.signature_algorithm
ALTER TABLE ONLY public.ottoq_audit_bundles ALTER COLUMN signature_algorithm SET DEFAULT 'HMAC-SHA-256'::text;
-- @@ default public.ottoq_audit_bundles.generated_at
ALTER TABLE ONLY public.ottoq_audit_bundles ALTER COLUMN generated_at SET DEFAULT now();
-- @@ default public.ottoq_audit_bundles.download_count
ALTER TABLE ONLY public.ottoq_audit_bundles ALTER COLUMN download_count SET DEFAULT 0;
-- @@ default public.ottoq_audit_bundles.created_at
ALTER TABLE ONLY public.ottoq_audit_bundles ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_audit_reports.report_id
ALTER TABLE ONLY public.ottoq_audit_reports ALTER COLUMN report_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_audit_reports.report_seq
ALTER TABLE ONLY public.ottoq_audit_reports ALTER COLUMN report_seq SET DEFAULT nextval('public.ottoq_audit_reports_report_seq_seq'::regclass);
-- @@ default public.ottoq_audit_reports.requested_at
ALTER TABLE ONLY public.ottoq_audit_reports ALTER COLUMN requested_at SET DEFAULT now();
-- @@ default public.ottoq_audit_reports.generation_status
ALTER TABLE ONLY public.ottoq_audit_reports ALTER COLUMN generation_status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_audit_reports.signature_algorithm
ALTER TABLE ONLY public.ottoq_audit_reports ALTER COLUMN signature_algorithm SET DEFAULT 'HMAC-SHA-256'::text;
-- @@ default public.ottoq_audit_reports.format
ALTER TABLE ONLY public.ottoq_audit_reports ALTER COLUMN format SET DEFAULT 'json'::text;
-- @@ default public.ottoq_audit_reports.exclusions
ALTER TABLE ONLY public.ottoq_audit_reports ALTER COLUMN exclusions SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_audit_reports.created_at
ALTER TABLE ONLY public.ottoq_audit_reports ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_bay_binding_witness.witness_id
ALTER TABLE ONLY public.ottoq_bay_binding_witness ALTER COLUMN witness_id SET DEFAULT nextval('public.ottoq_bay_binding_witness_witness_id_seq'::regclass);
-- @@ default public.ottoq_bay_binding_witness.observed_real
ALTER TABLE ONLY public.ottoq_bay_binding_witness ALTER COLUMN observed_real SET DEFAULT now();
-- @@ default public.ottoq_benchmark_frames.id
ALTER TABLE ONLY public.ottoq_benchmark_frames ALTER COLUMN id SET DEFAULT nextval('public.ottoq_benchmark_frames_id_seq'::regclass);
-- @@ default public.ottoq_benchmark_frames.created_at
ALTER TABLE ONLY public.ottoq_benchmark_frames ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_bess_units.bess_id
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN bess_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_bess_units.current_state
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN current_state SET DEFAULT 'standby'::text;
-- @@ default public.ottoq_bess_units.current_state_updated_at
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN current_state_updated_at SET DEFAULT now();
-- @@ default public.ottoq_bess_units.soc_min_floor_pct
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN soc_min_floor_pct SET DEFAULT 10.0;
-- @@ default public.ottoq_bess_units.soc_max_ceiling_pct
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN soc_max_ceiling_pct SET DEFAULT 95.0;
-- @@ default public.ottoq_bess_units.temperature_max_c
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN temperature_max_c SET DEFAULT 50.0;
-- @@ default public.ottoq_bess_units.temperature_min_c
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN temperature_min_c SET DEFAULT '-10.0'::numeric;
-- @@ default public.ottoq_bess_units.created_at
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_bess_units.updated_at
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_bess_units.current_soh_pct
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN current_soh_pct SET DEFAULT 100.0;
-- @@ default public.ottoq_bess_units.current_cycle_count
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN current_cycle_count SET DEFAULT 0;
-- @@ default public.ottoq_bess_units.lifetime_kwh_charged
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN lifetime_kwh_charged SET DEFAULT 0;
-- @@ default public.ottoq_bess_units.lifetime_kwh_discharged
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN lifetime_kwh_discharged SET DEFAULT 0;
-- @@ default public.ottoq_bess_units.chemistry
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN chemistry SET DEFAULT 'LFP'::text;
-- @@ default public.ottoq_bess_units.roundtrip_efficiency_pct
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN roundtrip_efficiency_pct SET DEFAULT 0.96;
-- @@ default public.ottoq_bess_units.auxiliary_load_kw
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN auxiliary_load_kw SET DEFAULT 8.0;
-- @@ default public.ottoq_bess_units.hvac_setpoint_c
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN hvac_setpoint_c SET DEFAULT 25;
-- @@ default public.ottoq_bess_units.hvac_rated_ambient_c
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN hvac_rated_ambient_c SET DEFAULT 50;
-- @@ default public.ottoq_bess_units.hvac_rated_min_ambient_c
ALTER TABLE ONLY public.ottoq_bess_units ALTER COLUMN hvac_rated_min_ambient_c SET DEFAULT '-30'::integer;
-- @@ default public.ottoq_calibration_correlations.correlation_id
ALTER TABLE ONLY public.ottoq_calibration_correlations ALTER COLUMN correlation_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_calibration_correlations.method
ALTER TABLE ONLY public.ottoq_calibration_correlations ALTER COLUMN method SET DEFAULT 'pearson'::text;
-- @@ default public.ottoq_calibration_correlations.fitted_at
ALTER TABLE ONLY public.ottoq_calibration_correlations ALTER COLUMN fitted_at SET DEFAULT now();
-- @@ default public.ottoq_calibration_datasets.status
ALTER TABLE ONLY public.ottoq_calibration_datasets ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_calibration_datasets.created_at
ALTER TABLE ONLY public.ottoq_calibration_datasets ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_calibration_datasets.updated_at
ALTER TABLE ONLY public.ottoq_calibration_datasets ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_calibration_distributions.distribution_id
ALTER TABLE ONLY public.ottoq_calibration_distributions ALTER COLUMN distribution_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_calibration_distributions.segment
ALTER TABLE ONLY public.ottoq_calibration_distributions ALTER COLUMN segment SET DEFAULT 'global'::text;
-- @@ default public.ottoq_calibration_distributions.fitted_at
ALTER TABLE ONLY public.ottoq_calibration_distributions ALTER COLUMN fitted_at SET DEFAULT now();
-- @@ default public.ottoq_calibration_metrics.calibration_id
ALTER TABLE ONLY public.ottoq_calibration_metrics ALTER COLUMN calibration_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_calibration_metrics.computed_at
ALTER TABLE ONLY public.ottoq_calibration_metrics ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.ottoq_calibration_metrics.payload
ALTER TABLE ONLY public.ottoq_calibration_metrics ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_calibration_profiles.profile_id
ALTER TABLE ONLY public.ottoq_calibration_profiles ALTER COLUMN profile_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_calibration_profiles.fitted_at
ALTER TABLE ONLY public.ottoq_calibration_profiles ALTER COLUMN fitted_at SET DEFAULT now();
-- @@ default public.ottoq_canopy_state.nameplate_dc_kw
ALTER TABLE ONLY public.ottoq_canopy_state ALTER COLUMN nameplate_dc_kw SET DEFAULT 180;
-- @@ default public.ottoq_canopy_state.nameplate_ac_kw
ALTER TABLE ONLY public.ottoq_canopy_state ALTER COLUMN nameplate_ac_kw SET DEFAULT 150;
-- @@ default public.ottoq_canopy_state.tilt_deg
ALTER TABLE ONLY public.ottoq_canopy_state ALTER COLUMN tilt_deg SET DEFAULT 30;
-- @@ default public.ottoq_canopy_state.azimuth_deg
ALTER TABLE ONLY public.ottoq_canopy_state ALTER COLUMN azimuth_deg SET DEFAULT 180;
-- @@ default public.ottoq_canopy_state.current_soiling
ALTER TABLE ONLY public.ottoq_canopy_state ALTER COLUMN current_soiling SET DEFAULT 1.00;
-- @@ default public.ottoq_canopy_state.last_updated_at
ALTER TABLE ONLY public.ottoq_canopy_state ALTER COLUMN last_updated_at SET DEFAULT now();
-- @@ default public.ottoq_cert_columns.enabled
ALTER TABLE ONLY public.ottoq_cert_columns ALTER COLUMN enabled SET DEFAULT true;
-- @@ default public.ottoq_cert_columns.added_at
ALTER TABLE ONLY public.ottoq_cert_columns ALTER COLUMN added_at SET DEFAULT now();
-- @@ default public.ottoq_cert_lineage.forces_recert
ALTER TABLE ONLY public.ottoq_cert_lineage ALTER COLUMN forces_recert SET DEFAULT true;
-- @@ default public.ottoq_cert_lineage.classified_at
ALTER TABLE ONLY public.ottoq_cert_lineage ALTER COLUMN classified_at SET DEFAULT now();
-- @@ default public.ottoq_cert_queue.scenario
ALTER TABLE ONLY public.ottoq_cert_queue ALTER COLUMN scenario SET DEFAULT 'shift'::text;
-- @@ default public.ottoq_cert_queue.ticks
ALTER TABLE ONLY public.ottoq_cert_queue ALTER COLUMN ticks SET DEFAULT 24;
-- @@ default public.ottoq_cert_queue.fault_chargers
ALTER TABLE ONLY public.ottoq_cert_queue ALTER COLUMN fault_chargers SET DEFAULT 0;
-- @@ default public.ottoq_cert_queue.status
ALTER TABLE ONLY public.ottoq_cert_queue ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_cert_queue.enqueued_at
ALTER TABLE ONLY public.ottoq_cert_queue ALTER COLUMN enqueued_at SET DEFAULT now();
-- @@ default public.ottoq_certified_proposers.added_at
ALTER TABLE ONLY public.ottoq_certified_proposers ALTER COLUMN added_at SET DEFAULT now();
-- @@ default public.ottoq_certified_proposers.added_by
ALTER TABLE ONLY public.ottoq_certified_proposers ALTER COLUMN added_by SET DEFAULT CURRENT_USER;
-- @@ default public.ottoq_challenger_findings.finding_id
ALTER TABLE ONLY public.ottoq_challenger_findings ALTER COLUMN finding_id SET DEFAULT nextval('public.ottoq_challenger_findings_finding_id_seq'::regclass);
-- @@ default public.ottoq_challenger_findings.scans_seen
ALTER TABLE ONLY public.ottoq_challenger_findings ALTER COLUMN scans_seen SET DEFAULT 1;
-- @@ default public.ottoq_challenger_findings.peak
ALTER TABLE ONLY public.ottoq_challenger_findings ALTER COLUMN peak SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_challenger_findings.status
ALTER TABLE ONLY public.ottoq_challenger_findings ALTER COLUMN status SET DEFAULT 'open'::text;
-- @@ default public.ottoq_challenger_findings.detected_at
ALTER TABLE ONLY public.ottoq_challenger_findings ALTER COLUMN detected_at SET DEFAULT now();
-- @@ default public.ottoq_channel_health.health_id
ALTER TABLE ONLY public.ottoq_channel_health ALTER COLUMN health_id SET DEFAULT nextval('public.ottoq_channel_health_health_id_seq'::regclass);
-- @@ default public.ottoq_channel_health.observed
ALTER TABLE ONLY public.ottoq_channel_health ALTER COLUMN observed SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_channel_health.checked_at
ALTER TABLE ONLY public.ottoq_channel_health ALTER COLUMN checked_at SET DEFAULT now();
-- @@ default public.ottoq_charge_clock_fits.fit_id
ALTER TABLE ONLY public.ottoq_charge_clock_fits ALTER COLUMN fit_id SET DEFAULT nextval('public.ottoq_charge_clock_fits_fit_id_seq'::regclass);
-- @@ default public.ottoq_charge_clock_fits.fitted_at
ALTER TABLE ONLY public.ottoq_charge_clock_fits ALTER COLUMN fitted_at SET DEFAULT now();
-- @@ default public.ottoq_charge_clock_fits.fitted_by
ALTER TABLE ONLY public.ottoq_charge_clock_fits ALTER COLUMN fitted_by SET DEFAULT CURRENT_USER;
-- @@ default public.ottoq_charge_duration_ledger.recorded_at
ALTER TABLE ONLY public.ottoq_charge_duration_ledger ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_charge_duration_ledger.detail
ALTER TABLE ONLY public.ottoq_charge_duration_ledger ALTER COLUMN detail SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_charge_duration_ledger.capture_version
ALTER TABLE ONLY public.ottoq_charge_duration_ledger ALTER COLUMN capture_version SET DEFAULT 2;
-- @@ default public.ottoq_charge_fault_fits.fit_id
ALTER TABLE ONLY public.ottoq_charge_fault_fits ALTER COLUMN fit_id SET DEFAULT nextval('public.ottoq_charge_fault_fits_fit_id_seq'::regclass);
-- @@ default public.ottoq_charge_fault_fits.fitted_at
ALTER TABLE ONLY public.ottoq_charge_fault_fits ALTER COLUMN fitted_at SET DEFAULT now();
-- @@ default public.ottoq_charge_fault_fits.fitted_by
ALTER TABLE ONLY public.ottoq_charge_fault_fits ALTER COLUMN fitted_by SET DEFAULT CURRENT_USER;
-- @@ default public.ottoq_charge_order_attribution.computed_at
ALTER TABLE ONLY public.ottoq_charge_order_attribution ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.ottoq_charge_order_hindsight.moves
ALTER TABLE ONLY public.ottoq_charge_order_hindsight ALTER COLUMN moves SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_charge_order_hindsight.graded_at
ALTER TABLE ONLY public.ottoq_charge_order_hindsight ALTER COLUMN graded_at SET DEFAULT now();
-- @@ default public.ottoq_charge_order_reattributions.computed_at
ALTER TABLE ONLY public.ottoq_charge_order_reattributions ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.ottoq_charge_order_reattributions.reattributed_at
ALTER TABLE ONLY public.ottoq_charge_order_reattributions ALTER COLUMN reattributed_at SET DEFAULT clock_timestamp();
-- @@ default public.ottoq_charge_order_regrades.moves
ALTER TABLE ONLY public.ottoq_charge_order_regrades ALTER COLUMN moves SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_charge_order_regrades.graded_at
ALTER TABLE ONLY public.ottoq_charge_order_regrades ALTER COLUMN graded_at SET DEFAULT now();
-- @@ default public.ottoq_charge_order_regrades.regraded_at
ALTER TABLE ONLY public.ottoq_charge_order_regrades ALTER COLUMN regraded_at SET DEFAULT clock_timestamp();
-- @@ default public.ottoq_charge_order_snapshots.recorded_at
ALTER TABLE ONLY public.ottoq_charge_order_snapshots ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_charge_window_calibration.fitted_at
ALTER TABLE ONLY public.ottoq_charge_window_calibration ALTER COLUMN fitted_at SET DEFAULT now();
-- @@ default public.ottoq_cil_adoptions.adoption_id
ALTER TABLE ONLY public.ottoq_cil_adoptions ALTER COLUMN adoption_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_cil_adoptions.decided_at
ALTER TABLE ONLY public.ottoq_cil_adoptions ALTER COLUMN decided_at SET DEFAULT now();
-- @@ default public.ottoq_cil_adoptions.source
ALTER TABLE ONLY public.ottoq_cil_adoptions ALTER COLUMN source SET DEFAULT 'cil_heuristic'::text;
-- @@ default public.ottoq_command_actor_registry.registered_at
ALTER TABLE ONLY public.ottoq_command_actor_registry ALTER COLUMN registered_at SET DEFAULT now();
-- @@ default public.ottoq_comms_messages.msg_id
ALTER TABLE ONLY public.ottoq_comms_messages ALTER COLUMN msg_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_comms_messages.qos
ALTER TABLE ONLY public.ottoq_comms_messages ALTER COLUMN qos SET DEFAULT 1;
-- @@ default public.ottoq_comms_messages.status
ALTER TABLE ONLY public.ottoq_comms_messages ALTER COLUMN status SET DEFAULT 'sent'::text;
-- @@ default public.ottoq_comms_messages.created_at
ALTER TABLE ONLY public.ottoq_comms_messages ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_counterfactuals.counterfactual_id
ALTER TABLE ONLY public.ottoq_counterfactuals ALTER COLUMN counterfactual_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_counterfactuals.counterfactual_seq
ALTER TABLE ONLY public.ottoq_counterfactuals ALTER COLUMN counterfactual_seq SET DEFAULT nextval('public.ottoq_counterfactuals_counterfactual_seq_seq'::regclass);
-- @@ default public.ottoq_counterfactuals.ran_at
ALTER TABLE ONLY public.ottoq_counterfactuals ALTER COLUMN ran_at SET DEFAULT now();
-- @@ default public.ottoq_counterfactuals.alternate_inputs
ALTER TABLE ONLY public.ottoq_counterfactuals ALTER COLUMN alternate_inputs SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_counterfactuals.alternate_parameters
ALTER TABLE ONLY public.ottoq_counterfactuals ALTER COLUMN alternate_parameters SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_counterfactuals.status
ALTER TABLE ONLY public.ottoq_counterfactuals ALTER COLUMN status SET DEFAULT 'completed'::text;
-- @@ default public.ottoq_counterfactuals.payload
ALTER TABLE ONLY public.ottoq_counterfactuals ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_cuopt_deferrals.state
ALTER TABLE ONLY public.ottoq_cuopt_deferrals ALTER COLUMN state SET DEFAULT 'armed'::text;
-- @@ default public.ottoq_cuopt_deferrals.armed_at_real
ALTER TABLE ONLY public.ottoq_cuopt_deferrals ALTER COLUMN armed_at_real SET DEFAULT now();
-- @@ default public.ottoq_cuopt_deferrals.defer_count
ALTER TABLE ONLY public.ottoq_cuopt_deferrals ALTER COLUMN defer_count SET DEFAULT 0;
-- @@ default public.ottoq_data_drift_metrics.drift_id
ALTER TABLE ONLY public.ottoq_data_drift_metrics ALTER COLUMN drift_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_data_drift_metrics.scope
ALTER TABLE ONLY public.ottoq_data_drift_metrics ALTER COLUMN scope SET DEFAULT 'global'::text;
-- @@ default public.ottoq_data_drift_metrics.computed_at
ALTER TABLE ONLY public.ottoq_data_drift_metrics ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.ottoq_data_drift_metrics.retraining_triggered
ALTER TABLE ONLY public.ottoq_data_drift_metrics ALTER COLUMN retraining_triggered SET DEFAULT false;
-- @@ default public.ottoq_data_drift_metrics.alert_emitted
ALTER TABLE ONLY public.ottoq_data_drift_metrics ALTER COLUMN alert_emitted SET DEFAULT false;
-- @@ default public.ottoq_data_drift_metrics.payload
ALTER TABLE ONLY public.ottoq_data_drift_metrics ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_decision_snapshots.snapshot_id
ALTER TABLE ONLY public.ottoq_decision_snapshots ALTER COLUMN snapshot_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_decision_snapshots.captured_at
ALTER TABLE ONLY public.ottoq_decision_snapshots ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.ottoq_decision_snapshots.frame_counts
ALTER TABLE ONLY public.ottoq_decision_snapshots ALTER COLUMN frame_counts SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_decisions.decision_id
ALTER TABLE ONLY public.ottoq_decisions ALTER COLUMN decision_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_decisions.decision_seq
ALTER TABLE ONLY public.ottoq_decisions ALTER COLUMN decision_seq SET DEFAULT nextval('public.ottoq_decisions_decision_seq_seq'::regclass);
-- @@ default public.ottoq_decisions.overridden
ALTER TABLE ONLY public.ottoq_decisions ALTER COLUMN overridden SET DEFAULT false;
-- @@ default public.ottoq_decisions.rule_results
ALTER TABLE ONLY public.ottoq_decisions ALTER COLUMN rule_results SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_decisions.shield_disarm_flags
ALTER TABLE ONLY public.ottoq_decisions ALTER COLUMN shield_disarm_flags SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_decisions.safe_default_taken
ALTER TABLE ONLY public.ottoq_decisions ALTER COLUMN safe_default_taken SET DEFAULT false;
-- @@ default public.ottoq_decisions.l2_engine
ALTER TABLE ONLY public.ottoq_decisions ALTER COLUMN l2_engine SET DEFAULT 'deterministic_v1'::text;
-- @@ default public.ottoq_decisions.created_at
ALTER TABLE ONLY public.ottoq_decisions ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_deploy_log.deploy_id
ALTER TABLE ONLY public.ottoq_deploy_log ALTER COLUMN deploy_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_deploy_log.logged_at
ALTER TABLE ONLY public.ottoq_deploy_log ALTER COLUMN logged_at SET DEFAULT now();
-- @@ default public.ottoq_depot_benchmarks_daily.benchmark_id
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN benchmark_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_depot_benchmarks_daily.visits_completed
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN visits_completed SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.vehicles_served
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN vehicles_served SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.oems_served
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN oems_served SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.total_service_hours
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN total_service_hours SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.sla_violations_count
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN sla_violations_count SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.total_kwh_delivered
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN total_kwh_delivered SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.total_revenue_usd
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN total_revenue_usd SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.total_cost_usd
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN total_cost_usd SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.rule_failures_count
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN rule_failures_count SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.anomalies_count
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN anomalies_count SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.emergencies_count
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN emergencies_count SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.overrides_count
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN overrides_count SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.total_carbon_offset_kg
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN total_carbon_offset_kg SET DEFAULT 0;
-- @@ default public.ottoq_depot_benchmarks_daily.computed_at
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.ottoq_depot_benchmarks_daily.payload
ALTER TABLE ONLY public.ottoq_depot_benchmarks_daily ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_depot_cost_daily.depot_cost_daily_id
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN depot_cost_daily_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_depot_cost_daily.visits_completed
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN visits_completed SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.unique_vehicles
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN unique_vehicles SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.unique_fleet_operators
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN unique_fleet_operators SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_kwh_delivered
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_kwh_delivered SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_kwh_from_grid
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_kwh_from_grid SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_kwh_from_solar
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_kwh_from_solar SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_kwh_from_bess
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_kwh_from_bess SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_energy_cost_usd
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_energy_cost_usd SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_demand_charge_usd
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_demand_charge_usd SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_labor_cost_usd
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_labor_cost_usd SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_opportunity_cost_usd
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_opportunity_cost_usd SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.fixed_overhead_usd
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN fixed_overhead_usd SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_operating_cost_usd
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_operating_cost_usd SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_revenue_usd
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_revenue_usd SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_margin_usd
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_margin_usd SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.total_carbon_offset_kg
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN total_carbon_offset_kg SET DEFAULT 0;
-- @@ default public.ottoq_depot_cost_daily.computed_at
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.ottoq_depot_cost_daily.payload
ALTER TABLE ONLY public.ottoq_depot_cost_daily ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_depot_shifts.shift_id
ALTER TABLE ONLY public.ottoq_depot_shifts ALTER COLUMN shift_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_depot_shifts.days_of_week
ALTER TABLE ONLY public.ottoq_depot_shifts ALTER COLUMN days_of_week SET DEFAULT ARRAY[1, 2, 3, 4, 5, 6, 7];
-- @@ default public.ottoq_depot_shifts.min_techs
ALTER TABLE ONLY public.ottoq_depot_shifts ALTER COLUMN min_techs SET DEFAULT 1;
-- @@ default public.ottoq_depot_shifts.status
ALTER TABLE ONLY public.ottoq_depot_shifts ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_depot_shifts.created_at
ALTER TABLE ONLY public.ottoq_depot_shifts ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_depot_staffing.updated_at
ALTER TABLE ONLY public.ottoq_depot_staffing ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_depot_tariffs.tariff_row_id
ALTER TABLE ONLY public.ottoq_depot_tariffs ALTER COLUMN tariff_row_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_depot_tariffs.block_kw
ALTER TABLE ONLY public.ottoq_depot_tariffs ALTER COLUMN block_kw SET DEFAULT 1000;
-- @@ default public.ottoq_depot_tariffs.demand_basis
ALTER TABLE ONLY public.ottoq_depot_tariffs ALTER COLUMN demand_basis SET DEFAULT 'NCP_30min'::text;
-- @@ default public.ottoq_depot_tariffs.active
ALTER TABLE ONLY public.ottoq_depot_tariffs ALTER COLUMN active SET DEFAULT true;
-- @@ default public.ottoq_depot_tariffs.created_at
ALTER TABLE ONLY public.ottoq_depot_tariffs ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_determinism_verdict_ledger.verdict_id
ALTER TABLE ONLY public.ottoq_determinism_verdict_ledger ALTER COLUMN verdict_id SET DEFAULT nextval('public.ottoq_determinism_verdict_ledger_verdict_id_seq'::regclass);
-- @@ default public.ottoq_determinism_verdict_ledger.certified_at
ALTER TABLE ONLY public.ottoq_determinism_verdict_ledger ALTER COLUMN certified_at SET DEFAULT now();
-- @@ default public.ottoq_determinism_verdict_ledger.disagreeing_atoms
ALTER TABLE ONLY public.ottoq_determinism_verdict_ledger ALTER COLUMN disagreeing_atoms SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_determinism_verdict_ledger.null_atoms
ALTER TABLE ONLY public.ottoq_determinism_verdict_ledger ALTER COLUMN null_atoms SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_dial_experiments.experiment_id
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN experiment_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_dial_experiments.created_at
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_dial_experiments.fixed_params
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN fixed_params SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_dial_experiments.first_look_pairs
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN first_look_pairs SET DEFAULT 6;
-- @@ default public.ottoq_dial_experiments.final_look_pairs
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN final_look_pairs SET DEFAULT 12;
-- @@ default public.ottoq_dial_experiments.alpha
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN alpha SET DEFAULT 0.05;
-- @@ default public.ottoq_dial_experiments.guardrail_margin_pct
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN guardrail_margin_pct SET DEFAULT 2;
-- @@ default public.ottoq_dial_experiments.min_effect_pct
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN min_effect_pct SET DEFAULT 0.5;
-- @@ default public.ottoq_dial_experiments.guardrail_alpha
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN guardrail_alpha SET DEFAULT 0.20;
-- @@ default public.ottoq_dial_experiments.status
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_dial_experiments.sim_min_per_tick
ALTER TABLE ONLY public.ottoq_dial_experiments ALTER COLUMN sim_min_per_tick SET DEFAULT 30;
-- @@ default public.ottoq_dial_pair_ledger.ran_at
ALTER TABLE ONLY public.ottoq_dial_pair_ledger ALTER COLUMN ran_at SET DEFAULT now();
-- @@ default public.ottoq_dial_promotion_ledger.promotion_id
ALTER TABLE ONLY public.ottoq_dial_promotion_ledger ALTER COLUMN promotion_id SET DEFAULT nextval('public.ottoq_dial_promotion_ledger_promotion_id_seq'::regclass);
-- @@ default public.ottoq_dial_promotion_ledger.decided_at
ALTER TABLE ONLY public.ottoq_dial_promotion_ledger ALTER COLUMN decided_at SET DEFAULT now();
-- @@ default public.ottoq_dr_calls.dr_call_id
ALTER TABLE ONLY public.ottoq_dr_calls ALTER COLUMN dr_call_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_dr_calls.program
ALTER TABLE ONLY public.ottoq_dr_calls ALTER COLUMN program SET DEFAULT 'TVA_VOLUNTARY'::text;
-- @@ default public.ottoq_dr_calls.call_status
ALTER TABLE ONLY public.ottoq_dr_calls ALTER COLUMN call_status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_dr_calls.data_source
ALTER TABLE ONLY public.ottoq_dr_calls ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_dr_calls.created_at
ALTER TABLE ONLY public.ottoq_dr_calls ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_emergency_invocations.invocation_id
ALTER TABLE ONLY public.ottoq_emergency_invocations ALTER COLUMN invocation_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_emergency_invocations.invocation_seq
ALTER TABLE ONLY public.ottoq_emergency_invocations ALTER COLUMN invocation_seq SET DEFAULT nextval('public.ottoq_emergency_invocations_invocation_seq_seq'::regclass);
-- @@ default public.ottoq_emergency_invocations.triggered_at
ALTER TABLE ONLY public.ottoq_emergency_invocations ALTER COLUMN triggered_at SET DEFAULT now();
-- @@ default public.ottoq_emergency_invocations.source_payload
ALTER TABLE ONLY public.ottoq_emergency_invocations ALTER COLUMN source_payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_emergency_invocations.cascade_executed
ALTER TABLE ONLY public.ottoq_emergency_invocations ALTER COLUMN cascade_executed SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_emergency_invocations.outcome
ALTER TABLE ONLY public.ottoq_emergency_invocations ALTER COLUMN outcome SET DEFAULT 'in_progress'::text;
-- @@ default public.ottoq_emergency_protocols.protocol_id
ALTER TABLE ONLY public.ottoq_emergency_protocols ALTER COLUMN protocol_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_emergency_protocols.severity
ALTER TABLE ONLY public.ottoq_emergency_protocols ALTER COLUMN severity SET DEFAULT 'safety_critical'::text;
-- @@ default public.ottoq_emergency_protocols.external_references
ALTER TABLE ONLY public.ottoq_emergency_protocols ALTER COLUMN external_references SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_emergency_protocols.trigger_event_types
ALTER TABLE ONLY public.ottoq_emergency_protocols ALTER COLUMN trigger_event_types SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_emergency_protocols.cascade_actions
ALTER TABLE ONLY public.ottoq_emergency_protocols ALTER COLUMN cascade_actions SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_emergency_protocols.affects_scope
ALTER TABLE ONLY public.ottoq_emergency_protocols ALTER COLUMN affects_scope SET DEFAULT 'depot'::text;
-- @@ default public.ottoq_emergency_protocols.requires_manual_clear
ALTER TABLE ONLY public.ottoq_emergency_protocols ALTER COLUMN requires_manual_clear SET DEFAULT true;
-- @@ default public.ottoq_emergency_protocols.notify_actors
ALTER TABLE ONLY public.ottoq_emergency_protocols ALTER COLUMN notify_actors SET DEFAULT ARRAY['depot_supervisor'::text, 'command_center_operator'::text, 'fleet_operator_admin'::text, 'oem_dispatch_webhook'::text];
-- @@ default public.ottoq_emergency_protocols.status
ALTER TABLE ONLY public.ottoq_emergency_protocols ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_emergency_protocols.created_at
ALTER TABLE ONLY public.ottoq_emergency_protocols ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_enactment_branches.declared_at
ALTER TABLE ONLY public.ottoq_enactment_branches ALTER COLUMN declared_at SET DEFAULT now();
-- @@ default public.ottoq_energy_commands.command_id
ALTER TABLE ONLY public.ottoq_energy_commands ALTER COLUMN command_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_energy_commands.source
ALTER TABLE ONLY public.ottoq_energy_commands ALTER COLUMN source SET DEFAULT 'otto_q'::text;
-- @@ default public.ottoq_energy_commands.horizon_min
ALTER TABLE ONLY public.ottoq_energy_commands ALTER COLUMN horizon_min SET DEFAULT 15;
-- @@ default public.ottoq_energy_commands.status
ALTER TABLE ONLY public.ottoq_energy_commands ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_energy_commands.data_source
ALTER TABLE ONLY public.ottoq_energy_commands ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_energy_commands.created_at
ALTER TABLE ONLY public.ottoq_energy_commands ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_energy_plan.id
ALTER TABLE ONLY public.ottoq_energy_plan ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_energy_plan.created_at
ALTER TABLE ONLY public.ottoq_energy_plan ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_energy_plan.source
ALTER TABLE ONLY public.ottoq_energy_plan ALTER COLUMN source SET DEFAULT 'mpc'::text;
-- @@ default public.ottoq_energy_plan.plan_state
ALTER TABLE ONLY public.ottoq_energy_plan ALTER COLUMN plan_state SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_energy_rates.created_at
ALTER TABLE ONLY public.ottoq_energy_rates ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_event_state_anchor.created_at
ALTER TABLE ONLY public.ottoq_event_state_anchor ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_event_types_catalog.default_severity
ALTER TABLE ONLY public.ottoq_event_types_catalog ALTER COLUMN default_severity SET DEFAULT 'info'::text;
-- @@ default public.ottoq_event_types_catalog.deprecated
ALTER TABLE ONLY public.ottoq_event_types_catalog ALTER COLUMN deprecated SET DEFAULT false;
-- @@ default public.ottoq_event_types_catalog.created_at
ALTER TABLE ONLY public.ottoq_event_types_catalog ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_events.event_id
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN event_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_events.event_seq
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN event_seq SET DEFAULT nextval('public.ottoq_events_event_seq_seq'::regclass);
-- @@ default public.ottoq_events.occurred_at
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN occurred_at SET DEFAULT now();
-- @@ default public.ottoq_events.recorded_at
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_events.actor_metadata
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN actor_metadata SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_events.severity
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN severity SET DEFAULT 'info'::text;
-- @@ default public.ottoq_events.payload
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_events.correlation_id
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN correlation_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_events.causation_chain
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN causation_chain SET DEFAULT '{}'::uuid[];
-- @@ default public.ottoq_events.signature_algorithm
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN signature_algorithm SET DEFAULT 'HMAC-SHA-256'::text;
-- @@ default public.ottoq_events.ingest_source
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN ingest_source SET DEFAULT 'app'::text;
-- @@ default public.ottoq_events.schema_version
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN schema_version SET DEFAULT '1.0.0'::text;
-- @@ default public.ottoq_events.data_source
ALTER TABLE ONLY public.ottoq_events ALTER COLUMN data_source SET DEFAULT 'production'::text;
-- @@ default public.ottoq_evidence_regimes.regime_id
ALTER TABLE ONLY public.ottoq_evidence_regimes ALTER COLUMN regime_id SET DEFAULT nextval('public.ottoq_evidence_regimes_regime_id_seq'::regclass);
-- @@ default public.ottoq_evidence_regimes.scope
ALTER TABLE ONLY public.ottoq_evidence_regimes ALTER COLUMN scope SET DEFAULT '*'::text;
-- @@ default public.ottoq_evidence_regimes.recorded_by
ALTER TABLE ONLY public.ottoq_evidence_regimes ALTER COLUMN recorded_by SET DEFAULT CURRENT_USER;
-- @@ default public.ottoq_evidence_regimes.recorded_at
ALTER TABLE ONLY public.ottoq_evidence_regimes ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_external_proposals.proposal_id
ALTER TABLE ONLY public.ottoq_external_proposals ALTER COLUMN proposal_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_external_proposals.source
ALTER TABLE ONLY public.ottoq_external_proposals ALTER COLUMN source SET DEFAULT 'external'::text;
-- @@ default public.ottoq_external_proposals.status
ALTER TABLE ONLY public.ottoq_external_proposals ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_external_proposals.created_at
ALTER TABLE ONLY public.ottoq_external_proposals ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_feature_values.value_id
ALTER TABLE ONLY public.ottoq_feature_values ALTER COLUMN value_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_feature_values.value_seq
ALTER TABLE ONLY public.ottoq_feature_values ALTER COLUMN value_seq SET DEFAULT nextval('public.ottoq_feature_values_value_seq_seq'::regclass);
-- @@ default public.ottoq_feature_values.valid_from
ALTER TABLE ONLY public.ottoq_feature_values ALTER COLUMN valid_from SET DEFAULT now();
-- @@ default public.ottoq_feature_values.observation_time
ALTER TABLE ONLY public.ottoq_feature_values ALTER COLUMN observation_time SET DEFAULT now();
-- @@ default public.ottoq_feature_values.feature_version
ALTER TABLE ONLY public.ottoq_feature_values ALTER COLUMN feature_version SET DEFAULT 1;
-- @@ default public.ottoq_feature_values.is_imputed
ALTER TABLE ONLY public.ottoq_feature_values ALTER COLUMN is_imputed SET DEFAULT false;
-- @@ default public.ottoq_feature_values.is_outlier
ALTER TABLE ONLY public.ottoq_feature_values ALTER COLUMN is_outlier SET DEFAULT false;
-- @@ default public.ottoq_feature_values.created_at
ALTER TABLE ONLY public.ottoq_feature_values ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_features.is_realtime
ALTER TABLE ONLY public.ottoq_features ALTER COLUMN is_realtime SET DEFAULT false;
-- @@ default public.ottoq_features.freshness_sla_seconds
ALTER TABLE ONLY public.ottoq_features ALTER COLUMN freshness_sla_seconds SET DEFAULT 300;
-- @@ default public.ottoq_features.depends_on_features
ALTER TABLE ONLY public.ottoq_features ALTER COLUMN depends_on_features SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_features.depends_on_tables
ALTER TABLE ONLY public.ottoq_features ALTER COLUMN depends_on_tables SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_features.version
ALTER TABLE ONLY public.ottoq_features ALTER COLUMN version SET DEFAULT 1;
-- @@ default public.ottoq_features.status
ALTER TABLE ONLY public.ottoq_features ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_features.created_at
ALTER TABLE ONLY public.ottoq_features ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_features.updated_at
ALTER TABLE ONLY public.ottoq_features ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_feed_activations.activation_id
ALTER TABLE ONLY public.ottoq_feed_activations ALTER COLUMN activation_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_feed_activations.agent_model
ALTER TABLE ONLY public.ottoq_feed_activations ALTER COLUMN agent_model SET DEFAULT 'fallback'::text;
-- @@ default public.ottoq_feed_activations.activated_at
ALTER TABLE ONLY public.ottoq_feed_activations ALTER COLUMN activated_at SET DEFAULT now();
-- @@ default public.ottoq_feed_plan_promotions.promotion_id
ALTER TABLE ONLY public.ottoq_feed_plan_promotions ALTER COLUMN promotion_id SET DEFAULT nextval('public.ottoq_feed_plan_promotions_promotion_id_seq'::regclass);
-- @@ default public.ottoq_feed_plan_promotions.promoted_at
ALTER TABLE ONLY public.ottoq_feed_plan_promotions ALTER COLUMN promoted_at SET DEFAULT now();
-- @@ default public.ottoq_feed_plans.plan_id
ALTER TABLE ONLY public.ottoq_feed_plans ALTER COLUMN plan_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_feed_plans.status
ALTER TABLE ONLY public.ottoq_feed_plans ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_feed_plans.created_at
ALTER TABLE ONLY public.ottoq_feed_plans ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_fleet_buildout_active.applied_at
ALTER TABLE ONLY public.ottoq_fleet_buildout_active ALTER COLUMN applied_at SET DEFAULT clock_timestamp();
-- @@ default public.ottoq_fleet_buildout_active.backend_pid
ALTER TABLE ONLY public.ottoq_fleet_buildout_active ALTER COLUMN backend_pid SET DEFAULT pg_backend_pid();
-- @@ default public.ottoq_fleet_buildouts.basis
ALTER TABLE ONLY public.ottoq_fleet_buildouts ALTER COLUMN basis SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_fleet_operator_slas.sla_id
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN sla_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_fleet_operator_slas.effective_from
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN effective_from SET DEFAULT now();
-- @@ default public.ottoq_fleet_operator_slas.status
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_fleet_operator_slas.version
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN version SET DEFAULT 1;
-- @@ default public.ottoq_fleet_operator_slas.required_services_before_deploy
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN required_services_before_deploy SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_fleet_operator_slas.blocked_services
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN blocked_services SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_fleet_operator_slas.oem_acceptance_required
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN oem_acceptance_required SET DEFAULT true;
-- @@ default public.ottoq_fleet_operator_slas.oem_acceptance_timeout_seconds
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN oem_acceptance_timeout_seconds SET DEFAULT 180;
-- @@ default public.ottoq_fleet_operator_slas.oem_acceptance_on_timeout
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN oem_acceptance_on_timeout SET DEFAULT 'auto_accept'::text;
-- @@ default public.ottoq_fleet_operator_slas.oem_acceptance_mode
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN oem_acceptance_mode SET DEFAULT 'oem_webhook_final_only'::text;
-- @@ default public.ottoq_fleet_operator_slas.allow_maintenance_during_peak
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN allow_maintenance_during_peak SET DEFAULT false;
-- @@ default public.ottoq_fleet_operator_slas.reporting_frequency
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN reporting_frequency SET DEFAULT 'per_visit'::text;
-- @@ default public.ottoq_fleet_operator_slas.reports_must_be_signed
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN reports_must_be_signed SET DEFAULT true;
-- @@ default public.ottoq_fleet_operator_slas.audit_retention_days
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN audit_retention_days SET DEFAULT 2555;
-- @@ default public.ottoq_fleet_operator_slas.pii_redaction_required
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN pii_redaction_required SET DEFAULT false;
-- @@ default public.ottoq_fleet_operator_slas.penalty_schedule
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN penalty_schedule SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_fleet_operator_slas.created_at
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_fleet_operator_slas.updated_at
ALTER TABLE ONLY public.ottoq_fleet_operator_slas ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_cold_start.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_cold_start ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_dcfc_day_night.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_dcfc_day_night ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_dcfc_first.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_dcfc_first ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_demate_deadlock.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_demate_deadlock ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_frozen_target.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_frozen_target ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_geometry_contract.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_geometry_contract ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_night_waves.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_night_waves ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_plug_target_policy.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_plug_target_policy ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_single_run.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_single_run ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_soc_clamp.captured_at
ALTER TABLE ONLY public.ottoq_fn_backup_soc_clamp ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_stall_watchdog.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_stall_watchdog ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_supersede_churn.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_supersede_churn ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_backup_tick_observability.backed_up_at
ALTER TABLE ONLY public.ottoq_fn_backup_tick_observability ALTER COLUMN backed_up_at SET DEFAULT now();
-- @@ default public.ottoq_fn_definition_backups.backup_id
ALTER TABLE ONLY public.ottoq_fn_definition_backups ALTER COLUMN backup_id SET DEFAULT nextval('public.ottoq_fn_definition_backups_backup_id_seq'::regclass);
-- @@ default public.ottoq_fn_definition_backups.captured_at
ALTER TABLE ONLY public.ottoq_fn_definition_backups ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.ottoq_grant_boundary_backup.captured_at
ALTER TABLE ONLY public.ottoq_grant_boundary_backup ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.ottoq_grant_snapshot_0198.actions
ALTER TABLE ONLY public.ottoq_grant_snapshot_0198 ALTER COLUMN actions SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_grant_snapshot_0198.taken_at
ALTER TABLE ONLY public.ottoq_grant_snapshot_0198 ALTER COLUMN taken_at SET DEFAULT now();
-- @@ default public.ottoq_grid_events.grid_event_id
ALTER TABLE ONLY public.ottoq_grid_events ALTER COLUMN grid_event_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_grid_events.payload
ALTER TABLE ONLY public.ottoq_grid_events ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_grid_events.created_at
ALTER TABLE ONLY public.ottoq_grid_events ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_grid_snapshots.snapshot_id
ALTER TABLE ONLY public.ottoq_grid_snapshots ALTER COLUMN snapshot_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_grid_snapshots.snapshot_seq
ALTER TABLE ONLY public.ottoq_grid_snapshots ALTER COLUMN snapshot_seq SET DEFAULT nextval('public.ottoq_grid_snapshots_snapshot_seq_seq'::regclass);
-- @@ default public.ottoq_grid_snapshots.voltage_status
ALTER TABLE ONLY public.ottoq_grid_snapshots ALTER COLUMN voltage_status SET DEFAULT 'nominal'::text;
-- @@ default public.ottoq_grid_snapshots.frequency_status
ALTER TABLE ONLY public.ottoq_grid_snapshots ALTER COLUMN frequency_status SET DEFAULT 'nominal'::text;
-- @@ default public.ottoq_grid_snapshots.data_source
ALTER TABLE ONLY public.ottoq_grid_snapshots ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_grid_snapshots.created_at
ALTER TABLE ONLY public.ottoq_grid_snapshots ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_incident_reports.incident_report_id
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN incident_report_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_incident_reports.incident_report_seq
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN incident_report_seq SET DEFAULT nextval('public.ottoq_incident_reports_incident_report_seq_seq'::regclass);
-- @@ default public.ottoq_incident_reports.timeline
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN timeline SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_incident_reports.event_ids_in_timeline
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN event_ids_in_timeline SET DEFAULT '{}'::uuid[];
-- @@ default public.ottoq_incident_reports.rule_failures_in_window
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN rule_failures_in_window SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_incident_reports.predictions_in_window
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN predictions_in_window SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_incident_reports.recommendations_in_window
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN recommendations_in_window SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_incident_reports.contributing_factors
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN contributing_factors SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_incident_reports.systems_involved
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN systems_involved SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_incident_reports.actor_decisions
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN actor_decisions SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_incident_reports.recommendation_outcomes
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN recommendation_outcomes SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_incident_reports.events_in_window
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN events_in_window SET DEFAULT 0;
-- @@ default public.ottoq_incident_reports.rule_failures_count
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN rule_failures_count SET DEFAULT 0;
-- @@ default public.ottoq_incident_reports.anomaly_count
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN anomaly_count SET DEFAULT 0;
-- @@ default public.ottoq_incident_reports.override_count
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN override_count SET DEFAULT 0;
-- @@ default public.ottoq_incident_reports.vehicles_affected
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN vehicles_affected SET DEFAULT 0;
-- @@ default public.ottoq_incident_reports.stalls_affected
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN stalls_affected SET DEFAULT 0;
-- @@ default public.ottoq_incident_reports.generated_at
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN generated_at SET DEFAULT now();
-- @@ default public.ottoq_incident_reports.status
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN status SET DEFAULT 'auto_generated'::text;
-- @@ default public.ottoq_incident_reports.payload
ALTER TABLE ONLY public.ottoq_incident_reports ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_inference_log.inference_id
ALTER TABLE ONLY public.ottoq_inference_log ALTER COLUMN inference_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_inference_log.inference_seq
ALTER TABLE ONLY public.ottoq_inference_log ALTER COLUMN inference_seq SET DEFAULT nextval('public.ottoq_inference_log_inference_seq_seq'::regclass);
-- @@ default public.ottoq_inference_log.requested_at
ALTER TABLE ONLY public.ottoq_inference_log ALTER COLUMN requested_at SET DEFAULT now();
-- @@ default public.ottoq_inference_log.context
ALTER TABLE ONLY public.ottoq_inference_log ALTER COLUMN context SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_inference_log.is_shadow
ALTER TABLE ONLY public.ottoq_inference_log ALTER COLUMN is_shadow SET DEFAULT false;
-- @@ default public.ottoq_inference_log.status
ALTER TABLE ONLY public.ottoq_inference_log ALTER COLUMN status SET DEFAULT 'completed'::text;
-- @@ default public.ottoq_inference_log.created_at
ALTER TABLE ONLY public.ottoq_inference_log ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_intelligence_snapshot.decisions
ALTER TABLE ONLY public.ottoq_intelligence_snapshot ALTER COLUMN decisions SET DEFAULT 0;
-- @@ default public.ottoq_intelligence_snapshot.enacted
ALTER TABLE ONLY public.ottoq_intelligence_snapshot ALTER COLUMN enacted SET DEFAULT 0;
-- @@ default public.ottoq_intelligence_snapshot.computed_at
ALTER TABLE ONLY public.ottoq_intelligence_snapshot ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.ottoq_intelligence_snapshot.proposals
ALTER TABLE ONLY public.ottoq_intelligence_snapshot ALTER COLUMN proposals SET DEFAULT 0;
-- @@ default public.ottoq_intelligence_snapshot.proposals_enacted
ALTER TABLE ONLY public.ottoq_intelligence_snapshot ALTER COLUMN proposals_enacted SET DEFAULT 0;
-- @@ default public.ottoq_intelligence_sources.registered_at
ALTER TABLE ONLY public.ottoq_intelligence_sources ALTER COLUMN registered_at SET DEFAULT now();
-- @@ default public.ottoq_itinerary_legs.leg_id
ALTER TABLE ONLY public.ottoq_itinerary_legs ALTER COLUMN leg_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_itinerary_legs.duration_basis
ALTER TABLE ONLY public.ottoq_itinerary_legs ALTER COLUMN duration_basis SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_itinerary_legs.status
ALTER TABLE ONLY public.ottoq_itinerary_legs ALTER COLUMN status SET DEFAULT 'planned'::text;
-- @@ default public.ottoq_itinerary_legs.created_at
ALTER TABLE ONLY public.ottoq_itinerary_legs ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_kpi_touch_actor_types.classified_at
ALTER TABLE ONLY public.ottoq_kpi_touch_actor_types ALTER COLUMN classified_at SET DEFAULT now();
-- @@ default public.ottoq_kpi_touch_lanes.classified_at
ALTER TABLE ONLY public.ottoq_kpi_touch_lanes ALTER COLUMN classified_at SET DEFAULT now();
-- @@ default public.ottoq_learned_estimates.estimate_id
ALTER TABLE ONLY public.ottoq_learned_estimates ALTER COLUMN estimate_id SET DEFAULT nextval('public.ottoq_learned_estimates_estimate_id_seq'::regclass);
-- @@ default public.ottoq_learned_estimates.fitted_at
ALTER TABLE ONLY public.ottoq_learned_estimates ALTER COLUMN fitted_at SET DEFAULT now();
-- @@ default public.ottoq_learned_estimates.fitted_by
ALTER TABLE ONLY public.ottoq_learned_estimates ALTER COLUMN fitted_by SET DEFAULT CURRENT_USER;
-- @@ default public.ottoq_margin_prices.created_at
ALTER TABLE ONLY public.ottoq_margin_prices ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_model_artifacts.artifact_id
ALTER TABLE ONLY public.ottoq_model_artifacts ALTER COLUMN artifact_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_model_artifacts.uploaded_at
ALTER TABLE ONLY public.ottoq_model_artifacts ALTER COLUMN uploaded_at SET DEFAULT now();
-- @@ default public.ottoq_model_artifacts.is_active
ALTER TABLE ONLY public.ottoq_model_artifacts ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.ottoq_model_call_ledger.call_id
ALTER TABLE ONLY public.ottoq_model_call_ledger ALTER COLUMN call_id SET DEFAULT nextval('public.ottoq_model_call_ledger_call_id_seq'::regclass);
-- @@ default public.ottoq_model_call_ledger.detail
ALTER TABLE ONLY public.ottoq_model_call_ledger ALTER COLUMN detail SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_model_call_ledger.called_at
ALTER TABLE ONLY public.ottoq_model_call_ledger ALTER COLUMN called_at SET DEFAULT now();
-- @@ default public.ottoq_model_call_ledger.source_kind
ALTER TABLE ONLY public.ottoq_model_call_ledger ALTER COLUMN source_kind SET DEFAULT 'live'::text;
-- @@ default public.ottoq_model_routes.route_id
ALTER TABLE ONLY public.ottoq_model_routes ALTER COLUMN route_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_model_routes.effective_from
ALTER TABLE ONLY public.ottoq_model_routes ALTER COLUMN effective_from SET DEFAULT now();
-- @@ default public.ottoq_model_routes.priority
ALTER TABLE ONLY public.ottoq_model_routes ALTER COLUMN priority SET DEFAULT 100;
-- @@ default public.ottoq_model_routes.traffic_share_pct
ALTER TABLE ONLY public.ottoq_model_routes ALTER COLUMN traffic_share_pct SET DEFAULT 100.0;
-- @@ default public.ottoq_model_routes.shadow_mode
ALTER TABLE ONLY public.ottoq_model_routes ALTER COLUMN shadow_mode SET DEFAULT false;
-- @@ default public.ottoq_model_routes.created_at
ALTER TABLE ONLY public.ottoq_model_routes ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_oauth_auth_requests.request_id
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ALTER COLUMN request_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_oauth_auth_requests.status
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_oauth_auth_requests.created_at
ALTER TABLE ONLY public.ottoq_oauth_auth_requests ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_oauth_clients.redirect_uris
ALTER TABLE ONLY public.ottoq_oauth_clients ALTER COLUMN redirect_uris SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_oauth_clients.metadata
ALTER TABLE ONLY public.ottoq_oauth_clients ALTER COLUMN metadata SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_oauth_clients.status
ALTER TABLE ONLY public.ottoq_oauth_clients ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_oauth_clients.created_at
ALTER TABLE ONLY public.ottoq_oauth_clients ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_oauth_device_codes.status
ALTER TABLE ONLY public.ottoq_oauth_device_codes ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_oauth_device_codes.interval_s
ALTER TABLE ONLY public.ottoq_oauth_device_codes ALTER COLUMN interval_s SET DEFAULT 5;
-- @@ default public.ottoq_oauth_device_codes.created_at
ALTER TABLE ONLY public.ottoq_oauth_device_codes ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_oauth_device_codes.polls
ALTER TABLE ONLY public.ottoq_oauth_device_codes ALTER COLUMN polls SET DEFAULT 0;
-- @@ default public.ottoq_oauth_grants.created_at
ALTER TABLE ONLY public.ottoq_oauth_grants ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_oauth_tokens.issued_at
ALTER TABLE ONLY public.ottoq_oauth_tokens ALTER COLUMN issued_at SET DEFAULT now();
-- @@ default public.ottoq_ocpp_chargers.charger_id
ALTER TABLE ONLY public.ottoq_ocpp_chargers ALTER COLUMN charger_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_ocpp_chargers.ocpp_protocol_version
ALTER TABLE ONLY public.ottoq_ocpp_chargers ALTER COLUMN ocpp_protocol_version SET DEFAULT '2.0.1'::text;
-- @@ default public.ottoq_ocpp_chargers.station_state
ALTER TABLE ONLY public.ottoq_ocpp_chargers ALTER COLUMN station_state SET DEFAULT 'Unavailable'::text;
-- @@ default public.ottoq_ocpp_chargers.station_state_changed_at
ALTER TABLE ONLY public.ottoq_ocpp_chargers ALTER COLUMN station_state_changed_at SET DEFAULT now();
-- @@ default public.ottoq_ocpp_chargers.num_connectors
ALTER TABLE ONLY public.ottoq_ocpp_chargers ALTER COLUMN num_connectors SET DEFAULT 1;
-- @@ default public.ottoq_ocpp_chargers.connector_states
ALTER TABLE ONLY public.ottoq_ocpp_chargers ALTER COLUMN connector_states SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_ocpp_chargers.created_at
ALTER TABLE ONLY public.ottoq_ocpp_chargers ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_ocpp_chargers.updated_at
ALTER TABLE ONLY public.ottoq_ocpp_chargers ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_ocpp_messages.message_id
ALTER TABLE ONLY public.ottoq_ocpp_messages ALTER COLUMN message_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_ocpp_messages.message_seq
ALTER TABLE ONLY public.ottoq_ocpp_messages ALTER COLUMN message_seq SET DEFAULT nextval('public.ottoq_ocpp_messages_message_seq_seq'::regclass);
-- @@ default public.ottoq_ocpp_messages.message_at
ALTER TABLE ONLY public.ottoq_ocpp_messages ALTER COLUMN message_at SET DEFAULT now();
-- @@ default public.ottoq_ocpp_messages.ocpp_version
ALTER TABLE ONLY public.ottoq_ocpp_messages ALTER COLUMN ocpp_version SET DEFAULT '2.0.1'::text;
-- @@ default public.ottoq_ocpp_messages.data_source
ALTER TABLE ONLY public.ottoq_ocpp_messages ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_ocpp_messages.created_at
ALTER TABLE ONLY public.ottoq_ocpp_messages ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_oem_webhook_log.webhook_id
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN webhook_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_oem_webhook_log.webhook_seq
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN webhook_seq SET DEFAULT nextval('public.ottoq_oem_webhook_log_webhook_seq_seq'::regclass);
-- @@ default public.ottoq_oem_webhook_log.http_method
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN http_method SET DEFAULT 'POST'::text;
-- @@ default public.ottoq_oem_webhook_log.payload_complete
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN payload_complete SET DEFAULT true;
-- @@ default public.ottoq_oem_webhook_log.attempt_num
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN attempt_num SET DEFAULT 1;
-- @@ default public.ottoq_oem_webhook_log.is_retry
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN is_retry SET DEFAULT false;
-- @@ default public.ottoq_oem_webhook_log.is_duplicate
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN is_duplicate SET DEFAULT false;
-- @@ default public.ottoq_oem_webhook_log.is_out_of_order
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN is_out_of_order SET DEFAULT false;
-- @@ default public.ottoq_oem_webhook_log.real_at
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN real_at SET DEFAULT now();
-- @@ default public.ottoq_oem_webhook_log.data_source
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_oem_webhook_log.delivery_mode
ALTER TABLE ONLY public.ottoq_oem_webhook_log ALTER COLUMN delivery_mode SET DEFAULT 'simulated'::text;
-- @@ default public.ottoq_oem_webhook_patterns.latency_distribution
ALTER TABLE ONLY public.ottoq_oem_webhook_patterns ALTER COLUMN latency_distribution SET DEFAULT 'lognormal'::text;
-- @@ default public.ottoq_oem_webhook_patterns.server_error_5xx_pct
ALTER TABLE ONLY public.ottoq_oem_webhook_patterns ALTER COLUMN server_error_5xx_pct SET DEFAULT 0.002;
-- @@ default public.ottoq_oem_webhook_patterns.active
ALTER TABLE ONLY public.ottoq_oem_webhook_patterns ALTER COLUMN active SET DEFAULT true;
-- @@ default public.ottoq_oem_webhook_patterns.created_at
ALTER TABLE ONLY public.ottoq_oem_webhook_patterns ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_oem_webhook_patterns.updated_at
ALTER TABLE ONLY public.ottoq_oem_webhook_patterns ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_oem_webhook_patterns.live_delivery_enabled
ALTER TABLE ONLY public.ottoq_oem_webhook_patterns ALTER COLUMN live_delivery_enabled SET DEFAULT false;
-- @@ default public.ottoq_operation_catalog.pack_id
ALTER TABLE ONLY public.ottoq_operation_catalog ALTER COLUMN pack_id SET DEFAULT 'robotaxi'::text;
-- @@ default public.ottoq_operation_catalog.parallel_with_charge
ALTER TABLE ONLY public.ottoq_operation_catalog ALTER COLUMN parallel_with_charge SET DEFAULT false;
-- @@ default public.ottoq_operation_catalog.is_movement
ALTER TABLE ONLY public.ottoq_operation_catalog ALTER COLUMN is_movement SET DEFAULT false;
-- @@ default public.ottoq_operation_catalog.energy_bearing
ALTER TABLE ONLY public.ottoq_operation_catalog ALTER COLUMN energy_bearing SET DEFAULT false;
-- @@ default public.ottoq_operation_catalog.emits_sdr
ALTER TABLE ONLY public.ottoq_operation_catalog ALTER COLUMN emits_sdr SET DEFAULT true;
-- @@ default public.ottoq_operation_catalog.created_at
ALTER TABLE ONLY public.ottoq_operation_catalog ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_ops_approvals.approval_id
ALTER TABLE ONLY public.ottoq_ops_approvals ALTER COLUMN approval_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_ops_approvals.status
ALTER TABLE ONLY public.ottoq_ops_approvals ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_ops_approvals.priority
ALTER TABLE ONLY public.ottoq_ops_approvals ALTER COLUMN priority SET DEFAULT 'normal'::text;
-- @@ default public.ottoq_ops_approvals.created_at
ALTER TABLE ONLY public.ottoq_ops_approvals ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_owner_accounts.depot_id
ALTER TABLE ONLY public.ottoq_owner_accounts ALTER COLUMN depot_id SET DEFAULT '11111111-1111-1111-1111-111111111111'::uuid;
-- @@ default public.ottoq_owner_accounts.status
ALTER TABLE ONLY public.ottoq_owner_accounts ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_owner_accounts.created_at
ALTER TABLE ONLY public.ottoq_owner_accounts ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_owner_accounts.created_by
ALTER TABLE ONLY public.ottoq_owner_accounts ALTER COLUMN created_by SET DEFAULT SESSION_USER;
-- @@ default public.ottoq_owner_commands.command_id
ALTER TABLE ONLY public.ottoq_owner_commands ALTER COLUMN command_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_owner_commands.args
ALTER TABLE ONLY public.ottoq_owner_commands ALTER COLUMN args SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_owner_commands.vehicles
ALTER TABLE ONLY public.ottoq_owner_commands ALTER COLUMN vehicles SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_owner_commands.effects
ALTER TABLE ONLY public.ottoq_owner_commands ALTER COLUMN effects SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_owner_commands.created_at
ALTER TABLE ONLY public.ottoq_owner_commands ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_owner_settings.setting_id
ALTER TABLE ONLY public.ottoq_owner_settings ALTER COLUMN setting_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_owner_settings.status
ALTER TABLE ONLY public.ottoq_owner_settings ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_owner_settings.set_at
ALTER TABLE ONLY public.ottoq_owner_settings ALTER COLUMN set_at SET DEFAULT now();
-- @@ default public.ottoq_owner_settings.pending_reconcile
ALTER TABLE ONLY public.ottoq_owner_settings ALTER COLUMN pending_reconcile SET DEFAULT true;
-- @@ default public.ottoq_owner_settings.applied
ALTER TABLE ONLY public.ottoq_owner_settings ALTER COLUMN applied SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_policy_param_catalog.agent_writable
ALTER TABLE ONLY public.ottoq_policy_param_catalog ALTER COLUMN agent_writable SET DEFAULT false;
-- @@ default public.ottoq_policy_params.updated_by
ALTER TABLE ONLY public.ottoq_policy_params ALTER COLUMN updated_by SET DEFAULT 'system'::text;
-- @@ default public.ottoq_policy_params.updated_at
ALTER TABLE ONLY public.ottoq_policy_params ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_prediction_accuracy_heatmap.heatmap_id
ALTER TABLE ONLY public.ottoq_prediction_accuracy_heatmap ALTER COLUMN heatmap_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_prediction_accuracy_heatmap.computed_at
ALTER TABLE ONLY public.ottoq_prediction_accuracy_heatmap ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.ottoq_prediction_accuracy_heatmap.payload
ALTER TABLE ONLY public.ottoq_prediction_accuracy_heatmap ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_prediction_rule_links.link_id
ALTER TABLE ONLY public.ottoq_prediction_rule_links ALTER COLUMN link_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_prediction_rule_links.enabled
ALTER TABLE ONLY public.ottoq_prediction_rule_links ALTER COLUMN enabled SET DEFAULT true;
-- @@ default public.ottoq_prediction_rule_links.created_at
ALTER TABLE ONLY public.ottoq_prediction_rule_links ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_prediction_types_catalog.supported_horizons_minutes
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN supported_horizons_minutes SET DEFAULT ARRAY[60];
-- @@ default public.ottoq_prediction_types_catalog.default_horizon_minutes
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN default_horizon_minutes SET DEFAULT 60;
-- @@ default public.ottoq_prediction_types_catalog.required_features
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN required_features SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_prediction_types_catalog.optional_features
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN optional_features SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_prediction_types_catalog.freshness_sla_seconds
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN freshness_sla_seconds SET DEFAULT 300;
-- @@ default public.ottoq_prediction_types_catalog.latency_p95_ms
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN latency_p95_ms SET DEFAULT 200;
-- @@ default public.ottoq_prediction_types_catalog.status
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_prediction_types_catalog.ml_ready
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN ml_ready SET DEFAULT false;
-- @@ default public.ottoq_prediction_types_catalog.baseline_method
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN baseline_method SET DEFAULT 'heuristic'::text;
-- @@ default public.ottoq_prediction_types_catalog.created_at
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_prediction_types_catalog.updated_at
ALTER TABLE ONLY public.ottoq_prediction_types_catalog ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_predictions.id
ALTER TABLE ONLY public.ottoq_predictions ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.ottoq_predictions.supporting_data
ALTER TABLE ONLY public.ottoq_predictions ALTER COLUMN supporting_data SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_predictions.status
ALTER TABLE ONLY public.ottoq_predictions ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_predictions.created_at
ALTER TABLE ONLY public.ottoq_predictions ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_predictions.model_version
ALTER TABLE ONLY public.ottoq_predictions ALTER COLUMN model_version SET DEFAULT 1;
-- @@ default public.ottoq_predictions.action_parameters
ALTER TABLE ONLY public.ottoq_predictions ALTER COLUMN action_parameters SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_predictions.execution_status
ALTER TABLE ONLY public.ottoq_predictions ALTER COLUMN execution_status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_predictions.feature_snapshot_ids
ALTER TABLE ONLY public.ottoq_predictions ALTER COLUMN feature_snapshot_ids SET DEFAULT '{}'::uuid[];
-- @@ default public.ottoq_predictions.data_quality_score
ALTER TABLE ONLY public.ottoq_predictions ALTER COLUMN data_quality_score SET DEFAULT 1.000;
-- @@ default public.ottoq_predictions.shadow_only
ALTER TABLE ONLY public.ottoq_predictions ALTER COLUMN shadow_only SET DEFAULT false;
-- @@ default public.ottoq_proposal_disposition_ledger.disposition_id
ALTER TABLE ONLY public.ottoq_proposal_disposition_ledger ALTER COLUMN disposition_id SET DEFAULT nextval('public.ottoq_proposal_disposition_ledger_disposition_id_seq'::regclass);
-- @@ default public.ottoq_proposal_disposition_ledger.abstained
ALTER TABLE ONLY public.ottoq_proposal_disposition_ledger ALTER COLUMN abstained SET DEFAULT false;
-- @@ default public.ottoq_proposal_disposition_ledger.captured_at
ALTER TABLE ONLY public.ottoq_proposal_disposition_ledger ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.ottoq_proposal_disposition_ledger.source_kind
ALTER TABLE ONLY public.ottoq_proposal_disposition_ledger ALTER COLUMN source_kind SET DEFAULT 'live'::text;
-- @@ default public.ottoq_proposal_replay.captured_at
ALTER TABLE ONLY public.ottoq_proposal_replay ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.ottoq_proposer_fire_log.fire_id
ALTER TABLE ONLY public.ottoq_proposer_fire_log ALTER COLUMN fire_id SET DEFAULT nextval('public.ottoq_proposer_fire_log_fire_id_seq'::regclass);
-- @@ default public.ottoq_proposer_fire_log.fired_at
ALTER TABLE ONLY public.ottoq_proposer_fire_log ALTER COLUMN fired_at SET DEFAULT now();
-- @@ default public.ottoq_proposer_fire_log.n_rows
ALTER TABLE ONLY public.ottoq_proposer_fire_log ALTER COLUMN n_rows SET DEFAULT 0;
-- @@ default public.ottoq_proposer_fire_log.n_submitted
ALTER TABLE ONLY public.ottoq_proposer_fire_log ALTER COLUMN n_submitted SET DEFAULT 0;
-- @@ default public.ottoq_proposer_fire_log.proposal_ids
ALTER TABLE ONLY public.ottoq_proposer_fire_log ALTER COLUMN proposal_ids SET DEFAULT '{}'::uuid[];
-- @@ default public.ottoq_proposer_precedence.holds_tick
ALTER TABLE ONLY public.ottoq_proposer_precedence ALTER COLUMN holds_tick SET DEFAULT false;
-- @@ default public.ottoq_proposer_precedence.greedy_yields
ALTER TABLE ONLY public.ottoq_proposer_precedence ALTER COLUMN greedy_yields SET DEFAULT false;
-- @@ default public.ottoq_proposer_precedence.added_at
ALTER TABLE ONLY public.ottoq_proposer_precedence ALTER COLUMN added_at SET DEFAULT now();
-- @@ default public.ottoq_proposer_precedence.added_by
ALTER TABLE ONLY public.ottoq_proposer_precedence ALTER COLUMN added_by SET DEFAULT CURRENT_USER;
-- @@ default public.ottoq_ready_promise_updates.owner_read
ALTER TABLE ONLY public.ottoq_ready_promise_updates ALTER COLUMN owner_read SET DEFAULT false;
-- @@ default public.ottoq_ready_promise_updates.detail
ALTER TABLE ONLY public.ottoq_ready_promise_updates ALTER COLUMN detail SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_ready_promise_updates.recorded_at
ALTER TABLE ONLY public.ottoq_ready_promise_updates ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_ready_promises.detail
ALTER TABLE ONLY public.ottoq_ready_promises ALTER COLUMN detail SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_ready_promises.recorded_at
ALTER TABLE ONLY public.ottoq_ready_promises ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_recall_decisions.recall_id
ALTER TABLE ONLY public.ottoq_recall_decisions ALTER COLUMN recall_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_recall_decisions.decided_at
ALTER TABLE ONLY public.ottoq_recall_decisions ALTER COLUMN decided_at SET DEFAULT now();
-- @@ default public.ottoq_recall_decisions.inputs
ALTER TABLE ONLY public.ottoq_recall_decisions ALTER COLUMN inputs SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_recall_decisions.data_source
ALTER TABLE ONLY public.ottoq_recall_decisions ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_recall_refusals.refusal_id
ALTER TABLE ONLY public.ottoq_recall_refusals ALTER COLUMN refusal_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_recall_refusals.refused_at
ALTER TABLE ONLY public.ottoq_recall_refusals ALTER COLUMN refused_at SET DEFAULT now();
-- @@ default public.ottoq_recall_refusals.evidence
ALTER TABLE ONLY public.ottoq_recall_refusals ALTER COLUMN evidence SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_recall_refusals.data_source
ALTER TABLE ONLY public.ottoq_recall_refusals ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_recommendations.recommendation_id
ALTER TABLE ONLY public.ottoq_recommendations ALTER COLUMN recommendation_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_recommendations.recommendation_seq
ALTER TABLE ONLY public.ottoq_recommendations ALTER COLUMN recommendation_seq SET DEFAULT nextval('public.ottoq_recommendations_recommendation_seq_seq'::regclass);
-- @@ default public.ottoq_recommendations.emitted_at
ALTER TABLE ONLY public.ottoq_recommendations ALTER COLUMN emitted_at SET DEFAULT now();
-- @@ default public.ottoq_recommendations.action_parameters
ALTER TABLE ONLY public.ottoq_recommendations ALTER COLUMN action_parameters SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_recommendations.rules_evaluated
ALTER TABLE ONLY public.ottoq_recommendations ALTER COLUMN rules_evaluated SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_recommendations.status
ALTER TABLE ONLY public.ottoq_recommendations ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_recommendations.shadow_only
ALTER TABLE ONLY public.ottoq_recommendations ALTER COLUMN shadow_only SET DEFAULT false;
-- @@ default public.ottoq_recommendations.recommendation_payload
ALTER TABLE ONLY public.ottoq_recommendations ALTER COLUMN recommendation_payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_research_findings.depot_id
ALTER TABLE ONLY public.ottoq_research_findings ALTER COLUMN depot_id SET DEFAULT '11111111-1111-1111-1111-111111111111'::uuid;
-- @@ default public.ottoq_research_findings.metrics
ALTER TABLE ONLY public.ottoq_research_findings ALTER COLUMN metrics SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_research_findings.run_ids
ALTER TABLE ONLY public.ottoq_research_findings ALTER COLUMN run_ids SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_research_findings.created_at
ALTER TABLE ONLY public.ottoq_research_findings ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_research_findings.updated_at
ALTER TABLE ONLY public.ottoq_research_findings ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_retention_engine_allowlist.added_at
ALTER TABLE ONLY public.ottoq_retention_engine_allowlist ALTER COLUMN added_at SET DEFAULT now();
-- @@ default public.ottoq_retention_policy.enabled
ALTER TABLE ONLY public.ottoq_retention_policy ALTER COLUMN enabled SET DEFAULT true;
-- @@ default public.ottoq_retention_policy.keep_interval
ALTER TABLE ONLY public.ottoq_retention_policy ALTER COLUMN keep_interval SET DEFAULT '7 days'::interval;
-- @@ default public.ottoq_retention_policy.day_aligned
ALTER TABLE ONLY public.ottoq_retention_policy ALTER COLUMN day_aligned SET DEFAULT true;
-- @@ default public.ottoq_retention_policy.updated_at
ALTER TABLE ONLY public.ottoq_retention_policy ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_retention_state.cursor_block
ALTER TABLE ONLY public.ottoq_retention_state ALTER COLUMN cursor_block SET DEFAULT 0;
-- @@ default public.ottoq_retention_state.pass_deleted
ALTER TABLE ONLY public.ottoq_retention_state ALTER COLUMN pass_deleted SET DEFAULT 0;
-- @@ default public.ottoq_retention_state.updated_at
ALTER TABLE ONLY public.ottoq_retention_state ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_retraining_triggers.trigger_id
ALTER TABLE ONLY public.ottoq_retraining_triggers ALTER COLUMN trigger_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_retraining_triggers.condition
ALTER TABLE ONLY public.ottoq_retraining_triggers ALTER COLUMN condition SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_retraining_triggers.enabled
ALTER TABLE ONLY public.ottoq_retraining_triggers ALTER COLUMN enabled SET DEFAULT true;
-- @@ default public.ottoq_retraining_triggers.fire_count
ALTER TABLE ONLY public.ottoq_retraining_triggers ALTER COLUMN fire_count SET DEFAULT 0;
-- @@ default public.ottoq_retraining_triggers.created_at
ALTER TABLE ONLY public.ottoq_retraining_triggers ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_reward_weights.is_active
ALTER TABLE ONLY public.ottoq_reward_weights ALTER COLUMN is_active SET DEFAULT false;
-- @@ default public.ottoq_reward_weights.created_at
ALTER TABLE ONLY public.ottoq_reward_weights ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_rider_cleaning_flags.flag_id
ALTER TABLE ONLY public.ottoq_rider_cleaning_flags ALTER COLUMN flag_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_rider_cleaning_flags.status
ALTER TABLE ONLY public.ottoq_rider_cleaning_flags ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottoq_rider_cleaning_flags.return_trigger
ALTER TABLE ONLY public.ottoq_rider_cleaning_flags ALTER COLUMN return_trigger SET DEFAULT 'rider_flag_cleaning'::text;
-- @@ default public.ottoq_rider_cleaning_flags.created_at
ALTER TABLE ONLY public.ottoq_rider_cleaning_flags ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_rule_evaluations.evaluation_id
ALTER TABLE ONLY public.ottoq_rule_evaluations ALTER COLUMN evaluation_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_rule_evaluations.evaluation_seq
ALTER TABLE ONLY public.ottoq_rule_evaluations ALTER COLUMN evaluation_seq SET DEFAULT nextval('public.ottoq_rule_evaluations_evaluation_seq_seq'::regclass);
-- @@ default public.ottoq_rule_evaluations.evaluated_at
ALTER TABLE ONLY public.ottoq_rule_evaluations ALTER COLUMN evaluated_at SET DEFAULT now();
-- @@ default public.ottoq_rule_evaluations.parameters_used
ALTER TABLE ONLY public.ottoq_rule_evaluations ALTER COLUMN parameters_used SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_rule_evaluations.context
ALTER TABLE ONLY public.ottoq_rule_evaluations ALTER COLUMN context SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_rule_evaluations.result_payload
ALTER TABLE ONLY public.ottoq_rule_evaluations ALTER COLUMN result_payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_rule_overrides.override_id
ALTER TABLE ONLY public.ottoq_rule_overrides ALTER COLUMN override_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_rule_overrides.effective_from
ALTER TABLE ONLY public.ottoq_rule_overrides ALTER COLUMN effective_from SET DEFAULT now();
-- @@ default public.ottoq_rule_overrides.created_at
ALTER TABLE ONLY public.ottoq_rule_overrides ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_rule_overrides.payload
ALTER TABLE ONLY public.ottoq_rule_overrides ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_rule_parameters.parameter_id
ALTER TABLE ONLY public.ottoq_rule_parameters ALTER COLUMN parameter_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_rule_parameters.effective_from
ALTER TABLE ONLY public.ottoq_rule_parameters ALTER COLUMN effective_from SET DEFAULT now();
-- @@ default public.ottoq_rule_parameters.created_at
ALTER TABLE ONLY public.ottoq_rule_parameters ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_rules.rule_id
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN rule_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_rules.version
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN version SET DEFAULT 1;
-- @@ default public.ottoq_rules.severity
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN severity SET DEFAULT 'error'::text;
-- @@ default public.ottoq_rules.enforcement
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN enforcement SET DEFAULT 'block'::text;
-- @@ default public.ottoq_rules.override_allowed
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN override_allowed SET DEFAULT false;
-- @@ default public.ottoq_rules.default_parameters
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN default_parameters SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_rules.applies_to_actions
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN applies_to_actions SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_rules.applies_to_entities
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN applies_to_entities SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_rules.status
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_rules.created_at
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_rules.updated_at
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_rules.external_references
ALTER TABLE ONLY public.ottoq_rules ALTER COLUMN external_references SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_run_archives.archived_at
ALTER TABLE ONLY public.ottoq_run_archives ALTER COLUMN archived_at SET DEFAULT now();
-- @@ default public.ottoq_run_archives.metrics
ALTER TABLE ONLY public.ottoq_run_archives ALTER COLUMN metrics SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_run_archives.pack_id
ALTER TABLE ONLY public.ottoq_run_archives ALTER COLUMN pack_id SET DEFAULT 'robotaxi'::text;
-- @@ default public.ottoq_run_dial_ledger.captured_at
ALTER TABLE ONLY public.ottoq_run_dial_ledger ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.ottoq_run_dial_ledger.dials
ALTER TABLE ONLY public.ottoq_run_dial_ledger ALTER COLUMN dials SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_run_dial_ledger.dials_set_count
ALTER TABLE ONLY public.ottoq_run_dial_ledger ALTER COLUMN dials_set_count SET DEFAULT 0;
-- @@ default public.ottoq_run_once_claim.claimed_at
ALTER TABLE ONLY public.ottoq_run_once_claim ALTER COLUMN claimed_at SET DEFAULT now();
-- @@ default public.ottoq_run_scope_registry.registered_at
ALTER TABLE ONLY public.ottoq_run_scope_registry ALTER COLUMN registered_at SET DEFAULT now();
-- @@ default public.ottoq_scenarios.scenario_id
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN scenario_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_scenarios.fleet_operator_ids
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN fleet_operator_ids SET DEFAULT '{}'::uuid[];
-- @@ default public.ottoq_scenarios.sim_duration_minutes
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN sim_duration_minutes SET DEFAULT 480;
-- @@ default public.ottoq_scenarios.default_time_scale
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN default_time_scale SET DEFAULT 60.0;
-- @@ default public.ottoq_scenarios.tick_interval_seconds
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN tick_interval_seconds SET DEFAULT 30;
-- @@ default public.ottoq_scenarios.initial_conditions
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN initial_conditions SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_scenarios.arrival_profile
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN arrival_profile SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_scenarios.timeline
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN timeline SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_scenarios.random_seed
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN random_seed SET DEFAULT 42;
-- @@ default public.ottoq_scenarios.stress_params
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN stress_params SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_scenarios.status
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_scenarios.tags
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN tags SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_scenarios.created_at
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_scenarios.updated_at
ALTER TABLE ONLY public.ottoq_scenarios ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_schema_snapshots.snapshot_id
ALTER TABLE ONLY public.ottoq_schema_snapshots ALTER COLUMN snapshot_id SET DEFAULT nextval('public.ottoq_schema_snapshots_snapshot_id_seq'::regclass);
-- @@ default public.ottoq_schema_snapshots.taken_at
ALTER TABLE ONLY public.ottoq_schema_snapshots ALTER COLUMN taken_at SET DEFAULT now();
-- @@ default public.ottoq_service_detail_records.sdr_id
ALTER TABLE ONLY public.ottoq_service_detail_records ALTER COLUMN sdr_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_service_detail_records.sdr_seq
ALTER TABLE ONLY public.ottoq_service_detail_records ALTER COLUMN sdr_seq SET DEFAULT nextval('public.ottoq_sdr_seq'::regclass);
-- @@ default public.ottoq_service_detail_records.data_source
ALTER TABLE ONLY public.ottoq_service_detail_records ALTER COLUMN data_source SET DEFAULT 'production'::text;
-- @@ default public.ottoq_service_detail_records.pack_id
ALTER TABLE ONLY public.ottoq_service_detail_records ALTER COLUMN pack_id SET DEFAULT 'robotaxi'::text;
-- @@ default public.ottoq_service_detail_records.cost_components
ALTER TABLE ONLY public.ottoq_service_detail_records ALTER COLUMN cost_components SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_service_detail_records.currency
ALTER TABLE ONLY public.ottoq_service_detail_records ALTER COLUMN currency SET DEFAULT 'USD'::text;
-- @@ default public.ottoq_service_detail_records.signature_algorithm
ALTER TABLE ONLY public.ottoq_service_detail_records ALTER COLUMN signature_algorithm SET DEFAULT 'HMAC-SHA-256'::text;
-- @@ default public.ottoq_service_detail_records.status
ALTER TABLE ONLY public.ottoq_service_detail_records ALTER COLUMN status SET DEFAULT 'issued'::text;
-- @@ default public.ottoq_service_detail_records.schema_version
ALTER TABLE ONLY public.ottoq_service_detail_records ALTER COLUMN schema_version SET DEFAULT '2.0.0'::text;
-- @@ default public.ottoq_service_detail_records.issued_at
ALTER TABLE ONLY public.ottoq_service_detail_records ALTER COLUMN issued_at SET DEFAULT now();
-- @@ default public.ottoq_service_endpoints.updated_at
ALTER TABLE ONLY public.ottoq_service_endpoints ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_service_endpoints.updated_by
ALTER TABLE ONLY public.ottoq_service_endpoints ALTER COLUMN updated_by SET DEFAULT CURRENT_USER;
-- @@ default public.ottoq_service_point_capabilities.pack_id
ALTER TABLE ONLY public.ottoq_service_point_capabilities ALTER COLUMN pack_id SET DEFAULT 'robotaxi'::text;
-- @@ default public.ottoq_service_point_capabilities.active
ALTER TABLE ONLY public.ottoq_service_point_capabilities ALTER COLUMN active SET DEFAULT true;
-- @@ default public.ottoq_service_point_capabilities.source
ALTER TABLE ONLY public.ottoq_service_point_capabilities ALTER COLUMN source SET DEFAULT 'seed_0043'::text;
-- @@ default public.ottoq_service_point_capabilities.created_at
ALTER TABLE ONLY public.ottoq_service_point_capabilities ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_service_tariffs.tariff_id
ALTER TABLE ONLY public.ottoq_service_tariffs ALTER COLUMN tariff_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_service_tariffs.pack_id
ALTER TABLE ONLY public.ottoq_service_tariffs ALTER COLUMN pack_id SET DEFAULT 'robotaxi'::text;
-- @@ default public.ottoq_service_tariffs.window_label
ALTER TABLE ONLY public.ottoq_service_tariffs ALTER COLUMN window_label SET DEFAULT 'any'::text;
-- @@ default public.ottoq_service_tariffs.price_unit
ALTER TABLE ONLY public.ottoq_service_tariffs ALTER COLUMN price_unit SET DEFAULT 'per_event'::text;
-- @@ default public.ottoq_service_tariffs.currency
ALTER TABLE ONLY public.ottoq_service_tariffs ALTER COLUMN currency SET DEFAULT 'USD'::text;
-- @@ default public.ottoq_service_tariffs.effective_from
ALTER TABLE ONLY public.ottoq_service_tariffs ALTER COLUMN effective_from SET DEFAULT now();
-- @@ default public.ottoq_service_tariffs.active
ALTER TABLE ONLY public.ottoq_service_tariffs ALTER COLUMN active SET DEFAULT true;
-- @@ default public.ottoq_service_tariffs.created_at
ALTER TABLE ONLY public.ottoq_service_tariffs ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_service_tokens.token_id
ALTER TABLE ONLY public.ottoq_service_tokens ALTER COLUMN token_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_service_tokens.entitlements
ALTER TABLE ONLY public.ottoq_service_tokens ALTER COLUMN entitlements SET DEFAULT '{"operations": "*"}'::jsonb;
-- @@ default public.ottoq_service_tokens.status
ALTER TABLE ONLY public.ottoq_service_tokens ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_service_tokens.valid_from
ALTER TABLE ONLY public.ottoq_service_tokens ALTER COLUMN valid_from SET DEFAULT now();
-- @@ default public.ottoq_service_tokens.created_at
ALTER TABLE ONLY public.ottoq_service_tokens ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_signing_keys.algorithm
ALTER TABLE ONLY public.ottoq_signing_keys ALTER COLUMN algorithm SET DEFAULT 'HMAC-SHA-256'::text;
-- @@ default public.ottoq_signing_keys.is_active
ALTER TABLE ONLY public.ottoq_signing_keys ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.ottoq_signing_keys.activated_at
ALTER TABLE ONLY public.ottoq_signing_keys ALTER COLUMN activated_at SET DEFAULT now();
-- @@ default public.ottoq_signing_keys.created_at
ALTER TABLE ONLY public.ottoq_signing_keys ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_sim_runs.sim_run_id
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN sim_run_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_sim_runs.sim_run_seq
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN sim_run_seq SET DEFAULT nextval('public.ottoq_sim_runs_sim_run_seq_seq'::regclass);
-- @@ default public.ottoq_sim_runs.started_at
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN started_at SET DEFAULT now();
-- @@ default public.ottoq_sim_runs.time_scale
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN time_scale SET DEFAULT 60.0;
-- @@ default public.ottoq_sim_runs.tick_interval_seconds
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN tick_interval_seconds SET DEFAULT 30;
-- @@ default public.ottoq_sim_runs.tick_count
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN tick_count SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.random_seed
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN random_seed SET DEFAULT 42;
-- @@ default public.ottoq_sim_runs.status
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN status SET DEFAULT 'initializing'::text;
-- @@ default public.ottoq_sim_runs.events_generated
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN events_generated SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.vehicles_simulated
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN vehicles_simulated SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.charge_sessions
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN charge_sessions SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.tasks_completed
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN tasks_completed SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.anomalies_injected
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN anomalies_injected SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.emergencies_triggered
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN emergencies_triggered SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.rule_evaluations
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN rule_evaluations SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.rule_failures
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN rule_failures SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.predictions_emitted
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN predictions_emitted SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.recommendations_made
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN recommendations_made SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.timeline_cursor
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN timeline_cursor SET DEFAULT 0;
-- @@ default public.ottoq_sim_runs.validation_assertions
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN validation_assertions SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_sim_runs.payload
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_sim_runs.policy
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN policy SET DEFAULT 'otto_q'::text;
-- @@ default public.ottoq_sim_runs.demo_speed_x
ALTER TABLE ONLY public.ottoq_sim_runs ALTER COLUMN demo_speed_x SET DEFAULT 1.0;
-- @@ default public.ottoq_sim_scenarios.scenario_id
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN scenario_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_sim_scenarios.default_duration_hours
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN default_duration_hours SET DEFAULT 24;
-- @@ default public.ottoq_sim_scenarios.default_time_scale
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN default_time_scale SET DEFAULT 60;
-- @@ default public.ottoq_sim_scenarios.default_tick_seconds
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN default_tick_seconds SET DEFAULT 60;
-- @@ default public.ottoq_sim_scenarios.default_random_seed
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN default_random_seed SET DEFAULT 42;
-- @@ default public.ottoq_sim_scenarios.default_depot_id
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN default_depot_id SET DEFAULT '11111111-1111-1111-1111-111111111111'::uuid;
-- @@ default public.ottoq_sim_scenarios.weather_overrides
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN weather_overrides SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_sim_scenarios.fleet_overrides
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN fleet_overrides SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_sim_scenarios.charger_overrides
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN charger_overrides SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_sim_scenarios.grid_overrides
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN grid_overrides SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_sim_scenarios.fault_injection
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN fault_injection SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_sim_scenarios.status
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN status SET DEFAULT 'available'::text;
-- @@ default public.ottoq_sim_scenarios.created_at
ALTER TABLE ONLY public.ottoq_sim_scenarios ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_site_base_history.recorded_at
ALTER TABLE ONLY public.ottoq_site_base_history ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_site_buildout_active.applied_at
ALTER TABLE ONLY public.ottoq_site_buildout_active ALTER COLUMN applied_at SET DEFAULT clock_timestamp();
-- @@ default public.ottoq_site_buildout_active.backend_pid
ALTER TABLE ONLY public.ottoq_site_buildout_active ALTER COLUMN backend_pid SET DEFAULT pg_backend_pid();
-- @@ default public.ottoq_site_buildouts.convert_l2
ALTER TABLE ONLY public.ottoq_site_buildouts ALTER COLUMN convert_l2 SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_site_buildouts.created_at
ALTER TABLE ONLY public.ottoq_site_buildouts ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_site_buildouts.stall_set
ALTER TABLE ONLY public.ottoq_site_buildouts ALTER COLUMN stall_set SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_site_buildouts.buildable
ALTER TABLE ONLY public.ottoq_site_buildouts ALTER COLUMN buildable SET DEFAULT true;
-- @@ default public.ottoq_site_power_excursion_ledger.excursion_id
ALTER TABLE ONLY public.ottoq_site_power_excursion_ledger ALTER COLUMN excursion_id SET DEFAULT nextval('public.ottoq_site_power_excursion_ledger_excursion_id_seq'::regclass);
-- @@ default public.ottoq_site_power_excursion_ledger.detected_at
ALTER TABLE ONLY public.ottoq_site_power_excursion_ledger ALTER COLUMN detected_at SET DEFAULT now();
-- @@ default public.ottoq_site_power_excursion_ledger.source_kind
ALTER TABLE ONLY public.ottoq_site_power_excursion_ledger ALTER COLUMN source_kind SET DEFAULT 'live'::text;
-- @@ default public.ottoq_site_power_plan_ledger.plan_id
ALTER TABLE ONLY public.ottoq_site_power_plan_ledger ALTER COLUMN plan_id SET DEFAULT nextval('public.ottoq_site_power_plan_ledger_plan_id_seq'::regclass);
-- @@ default public.ottoq_site_power_plan_ledger.captured_at
ALTER TABLE ONLY public.ottoq_site_power_plan_ledger ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.ottoq_site_power_plan_ledger.source_kind
ALTER TABLE ONLY public.ottoq_site_power_plan_ledger ALTER COLUMN source_kind SET DEFAULT 'live'::text;
-- @@ default public.ottoq_site_structures.structure_id
ALTER TABLE ONLY public.ottoq_site_structures ALTER COLUMN structure_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_site_structures.rotation_deg
ALTER TABLE ONLY public.ottoq_site_structures ALTER COLUMN rotation_deg SET DEFAULT 0;
-- @@ default public.ottoq_site_structures.properties
ALTER TABLE ONLY public.ottoq_site_structures ALTER COLUMN properties SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_site_structures.status
ALTER TABLE ONLY public.ottoq_site_structures ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_site_structures.created_at
ALTER TABLE ONLY public.ottoq_site_structures ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_sla_conformance_daily.conformance_id
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ALTER COLUMN conformance_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_sla_conformance_daily.total_visits
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ALTER COLUMN total_visits SET DEFAULT 0;
-- @@ default public.ottoq_sla_conformance_daily.compliant_visits
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ALTER COLUMN compliant_visits SET DEFAULT 0;
-- @@ default public.ottoq_sla_conformance_daily.partial_visits
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ALTER COLUMN partial_visits SET DEFAULT 0;
-- @@ default public.ottoq_sla_conformance_daily.non_compliant_visits
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ALTER COLUMN non_compliant_visits SET DEFAULT 0;
-- @@ default public.ottoq_sla_conformance_daily.computed_at
ALTER TABLE ONLY public.ottoq_sla_conformance_daily ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.ottoq_sla_violations.violation_id
ALTER TABLE ONLY public.ottoq_sla_violations ALTER COLUMN violation_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_sla_violations.detected_at
ALTER TABLE ONLY public.ottoq_sla_violations ALTER COLUMN detected_at SET DEFAULT now();
-- @@ default public.ottoq_solar_output.output_id
ALTER TABLE ONLY public.ottoq_solar_output ALTER COLUMN output_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_solar_output.output_seq
ALTER TABLE ONLY public.ottoq_solar_output ALTER COLUMN output_seq SET DEFAULT nextval('public.ottoq_solar_output_output_seq_seq'::regclass);
-- @@ default public.ottoq_solar_output.inverter_clipped
ALTER TABLE ONLY public.ottoq_solar_output ALTER COLUMN inverter_clipped SET DEFAULT false;
-- @@ default public.ottoq_solar_output.inverter_blip
ALTER TABLE ONLY public.ottoq_solar_output ALTER COLUMN inverter_blip SET DEFAULT false;
-- @@ default public.ottoq_solar_output.data_source
ALTER TABLE ONLY public.ottoq_solar_output ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_solar_output.created_at
ALTER TABLE ONLY public.ottoq_solar_output ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_space_integrity_ledger.incident_id
ALTER TABLE ONLY public.ottoq_space_integrity_ledger ALTER COLUMN incident_id SET DEFAULT nextval('public.ottoq_space_integrity_ledger_incident_id_seq'::regclass);
-- @@ default public.ottoq_space_integrity_ledger.recorded_at
ALTER TABLE ONLY public.ottoq_space_integrity_ledger ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_space_integrity_ledger.detail
ALTER TABLE ONLY public.ottoq_space_integrity_ledger ALTER COLUMN detail SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_specialization_strategies.strategy_id
ALTER TABLE ONLY public.ottoq_specialization_strategies ALTER COLUMN strategy_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_specialization_strategies.enabled
ALTER TABLE ONLY public.ottoq_specialization_strategies ALTER COLUMN enabled SET DEFAULT true;
-- @@ default public.ottoq_specialization_strategies.min_samples_required
ALTER TABLE ONLY public.ottoq_specialization_strategies ALTER COLUMN min_samples_required SET DEFAULT 1000;
-- @@ default public.ottoq_specialization_strategies.min_days_of_history
ALTER TABLE ONLY public.ottoq_specialization_strategies ALTER COLUMN min_days_of_history SET DEFAULT 30;
-- @@ default public.ottoq_specialization_strategies.min_improvement_pct
ALTER TABLE ONLY public.ottoq_specialization_strategies ALTER COLUMN min_improvement_pct SET DEFAULT 5.0;
-- @@ default public.ottoq_specialization_strategies.created_at
ALTER TABLE ONLY public.ottoq_specialization_strategies ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_stall_bookings.booking_id
ALTER TABLE ONLY public.ottoq_stall_bookings ALTER COLUMN booking_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_stall_bookings.state
ALTER TABLE ONLY public.ottoq_stall_bookings ALTER COLUMN state SET DEFAULT 'held'::text;
-- @@ default public.ottoq_stall_bookings.booked_at
ALTER TABLE ONLY public.ottoq_stall_bookings ALTER COLUMN booked_at SET DEFAULT now();
-- @@ default public.ottoq_stall_bookings.booked_by
ALTER TABLE ONLY public.ottoq_stall_bookings ALTER COLUMN booked_by SET DEFAULT 'otto_q'::text;
-- @@ default public.ottoq_state_transitions.transition_id
ALTER TABLE ONLY public.ottoq_state_transitions ALTER COLUMN transition_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_state_transitions.allowed_actor_types
ALTER TABLE ONLY public.ottoq_state_transitions ALTER COLUMN allowed_actor_types SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_state_transitions.required_conditions
ALTER TABLE ONLY public.ottoq_state_transitions ALTER COLUMN required_conditions SET DEFAULT '{}'::text[];
-- @@ default public.ottoq_state_transitions.status
ALTER TABLE ONLY public.ottoq_state_transitions ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_state_transitions.created_at
ALTER TABLE ONLY public.ottoq_state_transitions ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_t4_coverage_samples.id
ALTER TABLE ONLY public.ottoq_t4_coverage_samples ALTER COLUMN id SET DEFAULT nextval('public.ottoq_t4_coverage_samples_id_seq1'::regclass);
-- @@ default public.ottoq_t4_coverage_samples.taken_at
ALTER TABLE ONLY public.ottoq_t4_coverage_samples ALTER COLUMN taken_at SET DEFAULT clock_timestamp();
-- @@ default public.ottoq_tariff_windows.tariff_id
ALTER TABLE ONLY public.ottoq_tariff_windows ALTER COLUMN tariff_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_tariff_windows.day_of_week_mask
ALTER TABLE ONLY public.ottoq_tariff_windows ALTER COLUMN day_of_week_mask SET DEFAULT 127;
-- @@ default public.ottoq_tariff_windows.season
ALTER TABLE ONLY public.ottoq_tariff_windows ALTER COLUMN season SET DEFAULT 'all'::text;
-- @@ default public.ottoq_tariff_windows.active
ALTER TABLE ONLY public.ottoq_tariff_windows ALTER COLUMN active SET DEFAULT true;
-- @@ default public.ottoq_tariff_windows.created_at
ALTER TABLE ONLY public.ottoq_tariff_windows ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_telemetry_packets.packet_id
ALTER TABLE ONLY public.ottoq_telemetry_packets ALTER COLUMN packet_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_telemetry_packets.packet_seq
ALTER TABLE ONLY public.ottoq_telemetry_packets ALTER COLUMN packet_seq SET DEFAULT nextval('public.ottoq_telemetry_packets_packet_seq_seq'::regclass);
-- @@ default public.ottoq_telemetry_packets.packet_at
ALTER TABLE ONLY public.ottoq_telemetry_packets ALTER COLUMN packet_at SET DEFAULT now();
-- @@ default public.ottoq_telemetry_packets.soc_source
ALTER TABLE ONLY public.ottoq_telemetry_packets ALTER COLUMN soc_source SET DEFAULT 'oem_telemetry'::text;
-- @@ default public.ottoq_telemetry_packets.data_source
ALTER TABLE ONLY public.ottoq_telemetry_packets ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_telemetry_packets.created_at
ALTER TABLE ONLY public.ottoq_telemetry_packets ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_throughput_scores.origin
ALTER TABLE ONLY public.ottoq_throughput_scores ALTER COLUMN origin SET DEFAULT 'writer'::text;
-- @@ default public.ottoq_throughput_scores.scored_at
ALTER TABLE ONLY public.ottoq_throughput_scores ALTER COLUMN scored_at SET DEFAULT now();
-- @@ default public.ottoq_throughput_sweep_arms.replicate
ALTER TABLE ONLY public.ottoq_throughput_sweep_arms ALTER COLUMN replicate SET DEFAULT false;
-- @@ default public.ottoq_throughput_sweep_arms.ran_at
ALTER TABLE ONLY public.ottoq_throughput_sweep_arms ALTER COLUMN ran_at SET DEFAULT clock_timestamp();
-- @@ default public.ottoq_throughput_sweep_cells.cell_id
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ALTER COLUMN cell_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_throughput_sweep_cells.fixed_params
ALTER TABLE ONLY public.ottoq_throughput_sweep_cells ALTER COLUMN fixed_params SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_throughput_sweeps.sweep_id
ALTER TABLE ONLY public.ottoq_throughput_sweeps ALTER COLUMN sweep_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_throughput_sweeps.replicates
ALTER TABLE ONLY public.ottoq_throughput_sweeps ALTER COLUMN replicates SET DEFAULT 1;
-- @@ default public.ottoq_throughput_sweeps.priority
ALTER TABLE ONLY public.ottoq_throughput_sweeps ALTER COLUMN priority SET DEFAULT 100;
-- @@ default public.ottoq_throughput_sweeps.status
ALTER TABLE ONLY public.ottoq_throughput_sweeps ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_throughput_sweeps.created_by
ALTER TABLE ONLY public.ottoq_throughput_sweeps ALTER COLUMN created_by SET DEFAULT 'research_wing'::text;
-- @@ default public.ottoq_throughput_sweeps.created_at
ALTER TABLE ONLY public.ottoq_throughput_sweeps ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_tick_invariance_arms.status
ALTER TABLE ONLY public.ottoq_tick_invariance_arms ALTER COLUMN status SET DEFAULT 'running'::text;
-- @@ default public.ottoq_tick_invariance_arms.started_at
ALTER TABLE ONLY public.ottoq_tick_invariance_arms ALTER COLUMN started_at SET DEFAULT now();
-- @@ default public.ottoq_tick_reservations.reservation_id
ALTER TABLE ONLY public.ottoq_tick_reservations ALTER COLUMN reservation_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_tick_reservations.created_at
ALTER TABLE ONLY public.ottoq_tick_reservations ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_training_runs.training_run_id
ALTER TABLE ONLY public.ottoq_training_runs ALTER COLUMN training_run_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_training_runs.started_at
ALTER TABLE ONLY public.ottoq_training_runs ALTER COLUMN started_at SET DEFAULT now();
-- @@ default public.ottoq_training_runs.hyperparameters
ALTER TABLE ONLY public.ottoq_training_runs ALTER COLUMN hyperparameters SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_training_runs.training_metrics
ALTER TABLE ONLY public.ottoq_training_runs ALTER COLUMN training_metrics SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_training_runs.test_metrics
ALTER TABLE ONLY public.ottoq_training_runs ALTER COLUMN test_metrics SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_training_runs.cross_validation
ALTER TABLE ONLY public.ottoq_training_runs ALTER COLUMN cross_validation SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_training_runs.status
ALTER TABLE ONLY public.ottoq_training_runs ALTER COLUMN status SET DEFAULT 'running'::text;
-- @@ default public.ottoq_training_runs.created_at
ALTER TABLE ONLY public.ottoq_training_runs ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_v2_cursors.applied
ALTER TABLE ONLY public.ottoq_v2_cursors ALTER COLUMN applied SET DEFAULT 0;
-- @@ default public.ottoq_v2_cursors.late
ALTER TABLE ONLY public.ottoq_v2_cursors ALTER COLUMN late SET DEFAULT 0;
-- @@ default public.ottoq_v2_cursors.gaps
ALTER TABLE ONLY public.ottoq_v2_cursors ALTER COLUMN gaps SET DEFAULT 0;
-- @@ default public.ottoq_v2_cursors.updated_at
ALTER TABLE ONLY public.ottoq_v2_cursors ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_v2_inbox.received_at
ALTER TABLE ONLY public.ottoq_v2_inbox ALTER COLUMN received_at SET DEFAULT now();
-- @@ default public.ottoq_v2_inbox.detail
ALTER TABLE ONLY public.ottoq_v2_inbox ALTER COLUMN detail SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_v2_signing_keys.created_at
ALTER TABLE ONLY public.ottoq_v2_signing_keys ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_variability_cards.meta
ALTER TABLE ONLY public.ottoq_variability_cards ALTER COLUMN meta SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_variability_cards.active
ALTER TABLE ONLY public.ottoq_variability_cards ALTER COLUMN active SET DEFAULT true;
-- @@ default public.ottoq_variability_cards.created_at
ALTER TABLE ONLY public.ottoq_variability_cards ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_variability_catalog.is_primary
ALTER TABLE ONLY public.ottoq_variability_catalog ALTER COLUMN is_primary SET DEFAULT false;
-- @@ default public.ottoq_variability_catalog.wired
ALTER TABLE ONLY public.ottoq_variability_catalog ALTER COLUMN wired SET DEFAULT false;
-- @@ default public.ottoq_variability_catalog.display_order
ALTER TABLE ONLY public.ottoq_variability_catalog ALTER COLUMN display_order SET DEFAULT 0;
-- @@ default public.ottoq_variability_catalog.created_at
ALTER TABLE ONLY public.ottoq_variability_catalog ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_variability_profiles.profile_id
ALTER TABLE ONLY public.ottoq_variability_profiles ALTER COLUMN profile_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_variability_profiles.knobs
ALTER TABLE ONLY public.ottoq_variability_profiles ALTER COLUMN knobs SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_variability_profiles.created_at
ALTER TABLE ONLY public.ottoq_variability_profiles ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_variability_profiles.updated_at
ALTER TABLE ONLY public.ottoq_variability_profiles ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_vehicle_classes.fast_charge_compatible
ALTER TABLE ONLY public.ottoq_vehicle_classes ALTER COLUMN fast_charge_compatible SET DEFAULT true;
-- @@ default public.ottoq_vehicle_classes.status
ALTER TABLE ONLY public.ottoq_vehicle_classes ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_vehicle_classes.created_at
ALTER TABLE ONLY public.ottoq_vehicle_classes ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_vehicle_classes.pack_id
ALTER TABLE ONLY public.ottoq_vehicle_classes ALTER COLUMN pack_id SET DEFAULT 'robotaxi'::text;
-- @@ default public.ottoq_vehicle_classes.charge_kinds
ALTER TABLE ONLY public.ottoq_vehicle_classes ALTER COLUMN charge_kinds SET DEFAULT ARRAY['l2'::text];
-- @@ default public.ottoq_vehicle_commands.command_id
ALTER TABLE ONLY public.ottoq_vehicle_commands ALTER COLUMN command_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_vehicle_commands.issued_by
ALTER TABLE ONLY public.ottoq_vehicle_commands ALTER COLUMN issued_by SET DEFAULT 'decide_tick'::text;
-- @@ default public.ottoq_vehicle_commands.status
ALTER TABLE ONLY public.ottoq_vehicle_commands ALTER COLUMN status SET DEFAULT 'issued'::text;
-- @@ default public.ottoq_vehicle_commands.created_at
ALTER TABLE ONLY public.ottoq_vehicle_commands ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_vehicle_commands.data_source
ALTER TABLE ONLY public.ottoq_vehicle_commands ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_vehicle_dispatches.dispatch_id
ALTER TABLE ONLY public.ottoq_vehicle_dispatches ALTER COLUMN dispatch_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_vehicle_dispatches.status
ALTER TABLE ONLY public.ottoq_vehicle_dispatches ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_vehicle_dispatches.data_source
ALTER TABLE ONLY public.ottoq_vehicle_dispatches ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_vehicle_dispatches.created_at
ALTER TABLE ONLY public.ottoq_vehicle_dispatches ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_vehicle_dispatches.heartbeat_count
ALTER TABLE ONLY public.ottoq_vehicle_dispatches ALTER COLUMN heartbeat_count SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_incidents.incident_id
ALTER TABLE ONLY public.ottoq_vehicle_incidents ALTER COLUMN incident_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_vehicle_incidents.recorded_at
ALTER TABLE ONLY public.ottoq_vehicle_incidents ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_vehicle_incidents.requires_tow
ALTER TABLE ONLY public.ottoq_vehicle_incidents ALTER COLUMN requires_tow SET DEFAULT false;
-- @@ default public.ottoq_vehicle_incidents.resolution_status
ALTER TABLE ONLY public.ottoq_vehicle_incidents ALTER COLUMN resolution_status SET DEFAULT 'open'::text;
-- @@ default public.ottoq_vehicle_incidents.data_source
ALTER TABLE ONLY public.ottoq_vehicle_incidents ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_vehicle_itineraries.itinerary_id
ALTER TABLE ONLY public.ottoq_vehicle_itineraries ALTER COLUMN itinerary_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_vehicle_itineraries.created_by
ALTER TABLE ONLY public.ottoq_vehicle_itineraries ALTER COLUMN created_by SET DEFAULT 'decide_tick'::text;
-- @@ default public.ottoq_vehicle_itineraries.status
ALTER TABLE ONLY public.ottoq_vehicle_itineraries ALTER COLUMN status SET DEFAULT 'active'::text;
-- @@ default public.ottoq_vehicle_itineraries.created_at
ALTER TABLE ONLY public.ottoq_vehicle_itineraries ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_vehicle_scout_findings.finding_id
ALTER TABLE ONLY public.ottoq_vehicle_scout_findings ALTER COLUMN finding_id SET DEFAULT nextval('public.ottoq_vehicle_scout_findings_finding_id_seq'::regclass);
-- @@ default public.ottoq_vehicle_scout_findings.detail
ALTER TABLE ONLY public.ottoq_vehicle_scout_findings ALTER COLUMN detail SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_vehicle_scout_findings.recorded_at
ALTER TABLE ONLY public.ottoq_vehicle_scout_findings ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.ottoq_vehicle_scout_findings.source_kind
ALTER TABLE ONLY public.ottoq_vehicle_scout_findings ALTER COLUMN source_kind SET DEFAULT 'live'::text;
-- @@ default public.ottoq_vehicle_wear.drive_km_total
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN drive_km_total SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.drive_hours_total
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN drive_hours_total SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.backfilled_km
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN backfilled_km SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.backfilled_hours
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN backfilled_hours SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.km_at_last_pm
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN km_at_last_pm SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.hours_at_last_calibration
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN hours_at_last_calibration SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.soil_index
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN soil_index SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.cabin_litter_events
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN cabin_litter_events SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.open_dtc_count
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN open_dtc_count SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.worst_open_dtc_rank
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN worst_open_dtc_rank SET DEFAULT 99;
-- @@ default public.ottoq_vehicle_wear.km_per_tick_ema
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN km_per_tick_ema SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.drive_ticks_observed
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN drive_ticks_observed SET DEFAULT 0;
-- @@ default public.ottoq_vehicle_wear.updated_at
ALTER TABLE ONLY public.ottoq_vehicle_wear ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottoq_visit_cost_attribution.attribution_id
ALTER TABLE ONLY public.ottoq_visit_cost_attribution ALTER COLUMN attribution_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_visit_cost_attribution.attribution_seq
ALTER TABLE ONLY public.ottoq_visit_cost_attribution ALTER COLUMN attribution_seq SET DEFAULT nextval('public.ottoq_visit_cost_attribution_attribution_seq_seq'::regclass);
-- @@ default public.ottoq_visit_cost_attribution.cost_components
ALTER TABLE ONLY public.ottoq_visit_cost_attribution ALTER COLUMN cost_components SET DEFAULT '{}'::jsonb;
-- @@ default public.ottoq_visit_cost_attribution.computed_at
ALTER TABLE ONLY public.ottoq_visit_cost_attribution ALTER COLUMN computed_at SET DEFAULT now();
-- @@ default public.ottoq_visit_cost_attribution.compute_method
ALTER TABLE ONLY public.ottoq_visit_cost_attribution ALTER COLUMN compute_method SET DEFAULT 'rule_based'::text;
-- @@ default public.ottoq_visit_needs.visit_id
ALTER TABLE ONLY public.ottoq_visit_needs ALTER COLUMN visit_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_visit_needs.urgency
ALTER TABLE ONLY public.ottoq_visit_needs ALTER COLUMN urgency SET DEFAULT 'standard'::text;
-- @@ default public.ottoq_visit_needs.atoms
ALTER TABLE ONLY public.ottoq_visit_needs ALTER COLUMN atoms SET DEFAULT '[]'::jsonb;
-- @@ default public.ottoq_visit_needs.status
ALTER TABLE ONLY public.ottoq_visit_needs ALTER COLUMN status SET DEFAULT 'open'::text;
-- @@ default public.ottoq_visit_needs.source
ALTER TABLE ONLY public.ottoq_visit_needs ALTER COLUMN source SET DEFAULT 'twin_generator'::text;
-- @@ default public.ottoq_visit_needs.created_at
ALTER TABLE ONLY public.ottoq_visit_needs ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_wave_plan.plan_id
ALTER TABLE ONLY public.ottoq_wave_plan ALTER COLUMN plan_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_wave_plan.feasible
ALTER TABLE ONLY public.ottoq_wave_plan ALTER COLUMN feasible SET DEFAULT true;
-- @@ default public.ottoq_wave_plan.generator
ALTER TABLE ONLY public.ottoq_wave_plan ALTER COLUMN generator SET DEFAULT 'edf_v1'::text;
-- @@ default public.ottoq_wave_plan.created_at
ALTER TABLE ONLY public.ottoq_wave_plan ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_wear_tick_status.attempted
ALTER TABLE ONLY public.ottoq_wear_tick_status ALTER COLUMN attempted SET DEFAULT 0;
-- @@ default public.ottoq_wear_tick_status.written
ALTER TABLE ONLY public.ottoq_wear_tick_status ALTER COLUMN written SET DEFAULT 0;
-- @@ default public.ottoq_wear_tick_status.created_at
ALTER TABLE ONLY public.ottoq_wear_tick_status ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_weather_snapshots.snapshot_id
ALTER TABLE ONLY public.ottoq_weather_snapshots ALTER COLUMN snapshot_id SET DEFAULT gen_random_uuid();
-- @@ default public.ottoq_weather_snapshots.snapshot_seq
ALTER TABLE ONLY public.ottoq_weather_snapshots ALTER COLUMN snapshot_seq SET DEFAULT nextval('public.ottoq_weather_snapshots_snapshot_seq_seq'::regclass);
-- @@ default public.ottoq_weather_snapshots.data_source
ALTER TABLE ONLY public.ottoq_weather_snapshots ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.ottoq_weather_snapshots.created_at
ALTER TABLE ONLY public.ottoq_weather_snapshots ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottoq_write_slimming_policy.enabled
ALTER TABLE ONLY public.ottoq_write_slimming_policy ALTER COLUMN enabled SET DEFAULT true;
-- @@ default public.ottoq_write_slimming_policy.chain_event_types
ALTER TABLE ONLY public.ottoq_write_slimming_policy ALTER COLUMN chain_event_types SET DEFAULT ARRAY['vehicle.state_changed'::text];
-- @@ default public.ottoq_write_slimming_policy.slim_created
ALTER TABLE ONLY public.ottoq_write_slimming_policy ALTER COLUMN slim_created SET DEFAULT true;
-- @@ default public.ottoq_write_slimming_policy.updated_at
ALTER TABLE ONLY public.ottoq_write_slimming_policy ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottow_api_keys.id
ALTER TABLE ONLY public.ottow_api_keys ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.ottow_api_keys.is_active
ALTER TABLE ONLY public.ottow_api_keys ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.ottow_api_keys.created_at
ALTER TABLE ONLY public.ottow_api_keys ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottow_api_keys.data_source
ALTER TABLE ONLY public.ottow_api_keys ALTER COLUMN data_source SET DEFAULT 'production'::text;
-- @@ default public.ottow_dispatch_rules.id
ALTER TABLE ONLY public.ottow_dispatch_rules ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.ottow_dispatch_rules.is_active
ALTER TABLE ONLY public.ottow_dispatch_rules ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.ottow_dispatch_rules.auto_assign_driver
ALTER TABLE ONLY public.ottow_dispatch_rules ALTER COLUMN auto_assign_driver SET DEFAULT false;
-- @@ default public.ottow_dispatch_rules.max_driver_distance_miles
ALTER TABLE ONLY public.ottow_dispatch_rules ALTER COLUMN max_driver_distance_miles SET DEFAULT 15.0;
-- @@ default public.ottow_dispatch_rules.priority_order
ALTER TABLE ONLY public.ottow_dispatch_rules ALTER COLUMN priority_order SET DEFAULT 100;
-- @@ default public.ottow_dispatch_rules.created_at
ALTER TABLE ONLY public.ottow_dispatch_rules ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottow_dispatch_rules.updated_at
ALTER TABLE ONLY public.ottow_dispatch_rules ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottow_drivers.id
ALTER TABLE ONLY public.ottow_drivers ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.ottow_drivers.status
ALTER TABLE ONLY public.ottow_drivers ALTER COLUMN status SET DEFAULT 'off_duty'::text;
-- @@ default public.ottow_drivers.vehicle_class_certs
ALTER TABLE ONLY public.ottow_drivers ALTER COLUMN vehicle_class_certs SET DEFAULT '{}'::text[];
-- @@ default public.ottow_drivers.created_at
ALTER TABLE ONLY public.ottow_drivers ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottow_drivers.updated_at
ALTER TABLE ONLY public.ottow_drivers ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottow_mission_events.id
ALTER TABLE ONLY public.ottow_mission_events ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.ottow_mission_events.actor_type
ALTER TABLE ONLY public.ottow_mission_events ALTER COLUMN actor_type SET DEFAULT 'driver'::text;
-- @@ default public.ottow_mission_events.metadata
ALTER TABLE ONLY public.ottow_mission_events ALTER COLUMN metadata SET DEFAULT '{}'::jsonb;
-- @@ default public.ottow_mission_events.created_at
ALTER TABLE ONLY public.ottow_mission_events ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottow_missions.id
ALTER TABLE ONLY public.ottow_missions ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.ottow_missions.status
ALTER TABLE ONLY public.ottow_missions ALTER COLUMN status SET DEFAULT 'reported'::text;
-- @@ default public.ottow_missions.priority
ALTER TABLE ONLY public.ottow_missions ALTER COLUMN priority SET DEFAULT 'standard'::text;
-- @@ default public.ottow_missions.incident_category
ALTER TABLE ONLY public.ottow_missions ALTER COLUMN incident_category SET DEFAULT 'other'::text;
-- @@ default public.ottow_missions.created_at
ALTER TABLE ONLY public.ottow_missions ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottow_missions.updated_at
ALTER TABLE ONLY public.ottow_missions ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.ottow_missions.source
ALTER TABLE ONLY public.ottow_missions ALTER COLUMN source SET DEFAULT 'manual_dispatch'::text;
-- @@ default public.ottow_notifications.id
ALTER TABLE ONLY public.ottow_notifications ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.ottow_notifications.status
ALTER TABLE ONLY public.ottow_notifications ALTER COLUMN status SET DEFAULT 'pending'::text;
-- @@ default public.ottow_notifications.incident_category
ALTER TABLE ONLY public.ottow_notifications ALTER COLUMN incident_category SET DEFAULT 'other'::text;
-- @@ default public.ottow_notifications.priority
ALTER TABLE ONLY public.ottow_notifications ALTER COLUMN priority SET DEFAULT 'standard'::text;
-- @@ default public.ottow_notifications.auto_dispatch_eligible
ALTER TABLE ONLY public.ottow_notifications ALTER COLUMN auto_dispatch_eligible SET DEFAULT false;
-- @@ default public.ottow_notifications.received_at
ALTER TABLE ONLY public.ottow_notifications ALTER COLUMN received_at SET DEFAULT now();
-- @@ default public.ottow_notifications.created_at
ALTER TABLE ONLY public.ottow_notifications ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.ottow_notifications.updated_at
ALTER TABLE ONLY public.ottow_notifications ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.p3_phantom_smoke_2026_08_02.id
ALTER TABLE ONLY public.p3_phantom_smoke_2026_08_02 ALTER COLUMN id SET DEFAULT nextval('public.p3_phantom_smoke_2026_08_02_id_seq'::regclass);
-- @@ default public.p3_phantom_smoke_2026_08_02.taken_at
ALTER TABLE ONLY public.p3_phantom_smoke_2026_08_02 ALTER COLUMN taken_at SET DEFAULT now();
-- @@ default public.p7_band_probe_2026_08_03.seq
ALTER TABLE ONLY public.p7_band_probe_2026_08_03 ALTER COLUMN seq SET DEFAULT nextval('public.p7_band_probe_2026_08_03_seq_seq'::regclass);
-- @@ default public.p7_band_probe_2026_08_03.at_real
ALTER TABLE ONLY public.p7_band_probe_2026_08_03 ALTER COLUMN at_real SET DEFAULT now();
-- @@ default public.p7_cuopt_supply_proof_2026_08_03.seq
ALTER TABLE ONLY public.p7_cuopt_supply_proof_2026_08_03 ALTER COLUMN seq SET DEFAULT nextval('public.p7_cuopt_supply_proof_2026_08_03_seq_seq'::regclass);
-- @@ default public.p7_cuopt_supply_proof_2026_08_03.at_real
ALTER TABLE ONLY public.p7_cuopt_supply_proof_2026_08_03 ALTER COLUMN at_real SET DEFAULT now();
-- @@ default public.phantom_provenance_proof_2026_08_02.captured_at
ALTER TABLE ONLY public.phantom_provenance_proof_2026_08_02 ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.prediction_accuracy_daily.id
ALTER TABLE ONLY public.prediction_accuracy_daily ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.prediction_accuracy_daily.total_predictions
ALTER TABLE ONLY public.prediction_accuracy_daily ALTER COLUMN total_predictions SET DEFAULT 0;
-- @@ default public.prediction_accuracy_daily.scored_predictions
ALTER TABLE ONLY public.prediction_accuracy_daily ALTER COLUMN scored_predictions SET DEFAULT 0;
-- @@ default public.prediction_accuracy_daily.actions_taken
ALTER TABLE ONLY public.prediction_accuracy_daily ALTER COLUMN actions_taken SET DEFAULT 0;
-- @@ default public.prediction_accuracy_daily.actions_successful
ALTER TABLE ONLY public.prediction_accuracy_daily ALTER COLUMN actions_successful SET DEFAULT 0;
-- @@ default public.prediction_accuracy_daily.actions_rolled_back
ALTER TABLE ONLY public.prediction_accuracy_daily ALTER COLUMN actions_rolled_back SET DEFAULT 0;
-- @@ default public.prediction_accuracy_daily.demand_peaks_avoided
ALTER TABLE ONLY public.prediction_accuracy_daily ALTER COLUMN demand_peaks_avoided SET DEFAULT 0;
-- @@ default public.prediction_accuracy_daily.stall_conflicts_avoided
ALTER TABLE ONLY public.prediction_accuracy_daily ALTER COLUMN stall_conflicts_avoided SET DEFAULT 0;
-- @@ default public.prediction_accuracy_daily.created_at
ALTER TABLE ONLY public.prediction_accuracy_daily ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.prediction_explanations.id
ALTER TABLE ONLY public.prediction_explanations ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.prediction_explanations.top_similar_snapshots
ALTER TABLE ONLY public.prediction_explanations ALTER COLUMN top_similar_snapshots SET DEFAULT '[]'::jsonb;
-- @@ default public.prediction_explanations.external_factors_used
ALTER TABLE ONLY public.prediction_explanations ALTER COLUMN external_factors_used SET DEFAULT '[]'::jsonb;
-- @@ default public.prediction_explanations.feature_importance
ALTER TABLE ONLY public.prediction_explanations ALTER COLUMN feature_importance SET DEFAULT '{}'::jsonb;
-- @@ default public.prediction_explanations.sensitivity_analysis
ALTER TABLE ONLY public.prediction_explanations ALTER COLUMN sensitivity_analysis SET DEFAULT '{}'::jsonb;
-- @@ default public.prediction_explanations.confidence_decomposition
ALTER TABLE ONLY public.prediction_explanations ALTER COLUMN confidence_decomposition SET DEFAULT '{}'::jsonb;
-- @@ default public.prediction_explanations.risk_factor_weights
ALTER TABLE ONLY public.prediction_explanations ALTER COLUMN risk_factor_weights SET DEFAULT '{}'::jsonb;
-- @@ default public.prediction_explanations.generation_method
ALTER TABLE ONLY public.prediction_explanations ALTER COLUMN generation_method SET DEFAULT 'at_prediction_time'::text;
-- @@ default public.prediction_explanations.generated_at
ALTER TABLE ONLY public.prediction_explanations ALTER COLUMN generated_at SET DEFAULT now();
-- @@ default public.prediction_explanations.created_at
ALTER TABLE ONLY public.prediction_explanations ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.prediction_outcomes.id
ALTER TABLE ONLY public.prediction_outcomes ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.prediction_outcomes.scored_at
ALTER TABLE ONLY public.prediction_outcomes ALTER COLUMN scored_at SET DEFAULT now();
-- @@ default public.prediction_outcomes.created_at
ALTER TABLE ONLY public.prediction_outcomes ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.prof0012_act.id
ALTER TABLE ONLY public.prof0012_act ALTER COLUMN id SET DEFAULT nextval('public.prof0012_act_id_seq'::regclass);
-- @@ default public.prof0012_act.taken_at
ALTER TABLE ONLY public.prof0012_act ALTER COLUMN taken_at SET DEFAULT clock_timestamp();
-- @@ default public.prof0012_pgss.id
ALTER TABLE ONLY public.prof0012_pgss ALTER COLUMN id SET DEFAULT nextval('public.prof0012_pgss_id_seq'::regclass);
-- @@ default public.prof0012_pgss.taken_at
ALTER TABLE ONLY public.prof0012_pgss ALTER COLUMN taken_at SET DEFAULT clock_timestamp();
-- @@ default public.prof0012_tabstat.id
ALTER TABLE ONLY public.prof0012_tabstat ALTER COLUMN id SET DEFAULT nextval('public.prof0012_tabstat_id_seq'::regclass);
-- @@ default public.prof0012_tabstat.taken_at
ALTER TABLE ONLY public.prof0012_tabstat ALTER COLUMN taken_at SET DEFAULT clock_timestamp();
-- @@ default public.prof0012_tick.id
ALTER TABLE ONLY public.prof0012_tick ALTER COLUMN id SET DEFAULT nextval('public.prof0012_tick_id_seq'::regclass);
-- @@ default public.prof0012_tick.taken_at
ALTER TABLE ONLY public.prof0012_tick ALTER COLUMN taken_at SET DEFAULT clock_timestamp();
-- @@ default public.progression_decisions.id
ALTER TABLE ONLY public.progression_decisions ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.progression_decisions.decided_at
ALTER TABLE ONLY public.progression_decisions ALTER COLUMN decided_at SET DEFAULT now();
-- @@ default public.progression_decisions.payload
ALTER TABLE ONLY public.progression_decisions ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
-- @@ default public.progression_decisions.created_at
ALTER TABLE ONLY public.progression_decisions ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.proof0008_soil_smoke.captured_at
ALTER TABLE ONLY public.proof0008_soil_smoke ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.proof0012_428c9.checked_at
ALTER TABLE ONLY public.proof0012_428c9 ALTER COLUMN checked_at SET DEFAULT now();
-- @@ default public.retail_members.id
ALTER TABLE ONLY public.retail_members ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.retail_members.membership_tier
ALTER TABLE ONLY public.retail_members ALTER COLUMN membership_tier SET DEFAULT 'standard'::text;
-- @@ default public.retail_members.membership_status
ALTER TABLE ONLY public.retail_members ALTER COLUMN membership_status SET DEFAULT 'active'::text;
-- @@ default public.retail_members.auto_queue_enabled
ALTER TABLE ONLY public.retail_members ALTER COLUMN auto_queue_enabled SET DEFAULT true;
-- @@ default public.retail_members.preferred_days
ALTER TABLE ONLY public.retail_members ALTER COLUMN preferred_days SET DEFAULT '[]'::jsonb;
-- @@ default public.retail_members.preferred_time_window
ALTER TABLE ONLY public.retail_members ALTER COLUMN preferred_time_window SET DEFAULT '{}'::jsonb;
-- @@ default public.retail_members.notification_preferences
ALTER TABLE ONLY public.retail_members ALTER COLUMN notification_preferences SET DEFAULT '{"vehicle_ready": ["in_app", "sms"], "weekly_summary": ["email"], "vehicle_received": ["in_app"], "booking_confirmed": ["in_app"], "service_in_progress": ["in_app"]}'::jsonb;
-- @@ default public.retail_members.created_at
ALTER TABLE ONLY public.retail_members ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.retail_members.updated_at
ALTER TABLE ONLY public.retail_members ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.schedule_modifications.id
ALTER TABLE ONLY public.schedule_modifications ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.schedule_modifications.deadline_passed
ALTER TABLE ONLY public.schedule_modifications ALTER COLUMN deadline_passed SET DEFAULT false;
-- @@ default public.schedule_modifications.override_required
ALTER TABLE ONLY public.schedule_modifications ALTER COLUMN override_required SET DEFAULT false;
-- @@ default public.schedule_modifications.override_fee
ALTER TABLE ONLY public.schedule_modifications ALTER COLUMN override_fee SET DEFAULT 0;
-- @@ default public.schedule_modifications.vehicles_affected
ALTER TABLE ONLY public.schedule_modifications ALTER COLUMN vehicles_affected SET DEFAULT 0;
-- @@ default public.schedule_modifications.stalls_reassigned
ALTER TABLE ONLY public.schedule_modifications ALTER COLUMN stalls_reassigned SET DEFAULT 0;
-- @@ default public.schedule_modifications.wave_changes
ALTER TABLE ONLY public.schedule_modifications ALTER COLUMN wave_changes SET DEFAULT 0;
-- @@ default public.schedule_modifications.demand_impact_kw
ALTER TABLE ONLY public.schedule_modifications ALTER COLUMN demand_impact_kw SET DEFAULT 0;
-- @@ default public.schedule_modifications.status
ALTER TABLE ONLY public.schedule_modifications ALTER COLUMN status SET DEFAULT 'applied'::text;
-- @@ default public.schedule_modifications.created_at
ALTER TABLE ONLY public.schedule_modifications ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.schedule_tasks.id
ALTER TABLE ONLY public.schedule_tasks ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.schedule_tasks.post_completion_buffer_seconds
ALTER TABLE ONLY public.schedule_tasks ALTER COLUMN post_completion_buffer_seconds SET DEFAULT 30;
-- @@ default public.schedule_tasks.status
ALTER TABLE ONLY public.schedule_tasks ALTER COLUMN status SET DEFAULT 'pending'::public.task_status;
-- @@ default public.schedule_tasks.demand_paused
ALTER TABLE ONLY public.schedule_tasks ALTER COLUMN demand_paused SET DEFAULT false;
-- @@ default public.schedule_tasks.created_at
ALTER TABLE ONLY public.schedule_tasks ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.schedule_tasks.updated_at
ALTER TABLE ONLY public.schedule_tasks ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.schedule_tasks.oem_acceptance_state
ALTER TABLE ONLY public.schedule_tasks ALTER COLUMN oem_acceptance_state SET DEFAULT 'not_required'::text;
-- @@ default public.schedule_tasks.abnormality_flagged
ALTER TABLE ONLY public.schedule_tasks ALTER COLUMN abnormality_flagged SET DEFAULT false;
-- @@ default public.schedule_tasks.is_overnight_stage
ALTER TABLE ONLY public.schedule_tasks ALTER COLUMN is_overnight_stage SET DEFAULT false;
-- @@ default public.service_cadence_policy.due_soon_ratio
ALTER TABLE ONLY public.service_cadence_policy ALTER COLUMN due_soon_ratio SET DEFAULT 0.75;
-- @@ default public.service_cadence_policy.due_ratio
ALTER TABLE ONLY public.service_cadence_policy ALTER COLUMN due_ratio SET DEFAULT 1.00;
-- @@ default public.service_cadence_policy.overdue_ratio
ALTER TABLE ONLY public.service_cadence_policy ALTER COLUMN overdue_ratio SET DEFAULT 1.25;
-- @@ default public.service_cadence_policy.critical_ratio
ALTER TABLE ONLY public.service_cadence_policy ALTER COLUMN critical_ratio SET DEFAULT 1.60;
-- @@ default public.service_cadence_policy.must_do_at
ALTER TABLE ONLY public.service_cadence_policy ALTER COLUMN must_do_at SET DEFAULT 'never'::text;
-- @@ default public.service_cadence_policy.sequence_order
ALTER TABLE ONLY public.service_cadence_policy ALTER COLUMN sequence_order SET DEFAULT 50;
-- @@ default public.service_cadence_policy.is_active
ALTER TABLE ONLY public.service_cadence_policy ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.service_cadence_policy.updated_at
ALTER TABLE ONLY public.service_cadence_policy ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.service_definitions.id
ALTER TABLE ONLY public.service_definitions ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.service_definitions.is_duration_variable
ALTER TABLE ONLY public.service_definitions ALTER COLUMN is_duration_variable SET DEFAULT false;
-- @@ default public.service_definitions.available_for
ALTER TABLE ONLY public.service_definitions ALTER COLUMN available_for SET DEFAULT '["autonomous", "retail"]'::jsonb;
-- @@ default public.service_definitions.default_sequence_order
ALTER TABLE ONLY public.service_definitions ALTER COLUMN default_sequence_order SET DEFAULT 0;
-- @@ default public.service_definitions.is_active
ALTER TABLE ONLY public.service_definitions ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.service_definitions.created_at
ALTER TABLE ONLY public.service_definitions ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.service_definitions.updated_at
ALTER TABLE ONLY public.service_definitions ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.site_energy_snapshots.id
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.site_energy_snapshots."timestamp"
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN "timestamp" SET DEFAULT now();
-- @@ default public.site_energy_snapshots.grid_import_kw
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN grid_import_kw SET DEFAULT 0;
-- @@ default public.site_energy_snapshots.grid_export_kw
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN grid_export_kw SET DEFAULT 0;
-- @@ default public.site_energy_snapshots.solar_generation_kw
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN solar_generation_kw SET DEFAULT 0;
-- @@ default public.site_energy_snapshots.bess_output_kw
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN bess_output_kw SET DEFAULT 0;
-- @@ default public.site_energy_snapshots.total_ev_charging_kw
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN total_ev_charging_kw SET DEFAULT 0;
-- @@ default public.site_energy_snapshots.building_load_kw
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN building_load_kw SET DEFAULT 0;
-- @@ default public.site_energy_snapshots.lighting_load_kw
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN lighting_load_kw SET DEFAULT 0;
-- @@ default public.site_energy_snapshots.peak_demand_kw_15min
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN peak_demand_kw_15min SET DEFAULT 0;
-- @@ default public.site_energy_snapshots.billing_period_peak_kw
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN billing_period_peak_kw SET DEFAULT 0;
-- @@ default public.site_energy_snapshots.created_at
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.site_energy_snapshots.data_source
ALTER TABLE ONLY public.site_energy_snapshots ALTER COLUMN data_source SET DEFAULT 'twin'::text;
-- @@ default public.space_conflict_ledger.recorded_at
ALTER TABLE ONLY public.space_conflict_ledger ALTER COLUMN recorded_at SET DEFAULT now();
-- @@ default public.staff_users.id
ALTER TABLE ONLY public.staff_users ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.staff_users.is_on_shift
ALTER TABLE ONLY public.staff_users ALTER COLUMN is_on_shift SET DEFAULT false;
-- @@ default public.staff_users.is_active
ALTER TABLE ONLY public.staff_users ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.staff_users.created_at
ALTER TABLE ONLY public.staff_users ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.staff_users.updated_at
ALTER TABLE ONLY public.staff_users ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.stalls.id
ALTER TABLE ONLY public.stalls ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.stalls.relative_x
ALTER TABLE ONLY public.stalls ALTER COLUMN relative_x SET DEFAULT 0;
-- @@ default public.stalls.relative_y
ALTER TABLE ONLY public.stalls ALTER COLUMN relative_y SET DEFAULT 0;
-- @@ default public.stalls.heading_degrees
ALTER TABLE ONLY public.stalls ALTER COLUMN heading_degrees SET DEFAULT 0;
-- @@ default public.stalls.distance_from_entrance
ALTER TABLE ONLY public.stalls ALTER COLUMN distance_from_entrance SET DEFAULT 0;
-- @@ default public.stalls.status
ALTER TABLE ONLY public.stalls ALTER COLUMN status SET DEFAULT 'available'::text;
-- @@ default public.stalls.equipment_config
ALTER TABLE ONLY public.stalls ALTER COLUMN equipment_config SET DEFAULT '{}'::jsonb;
-- @@ default public.stalls.created_at
ALTER TABLE ONLY public.stalls ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.stalls.updated_at
ALTER TABLE ONLY public.stalls ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.stalls.supported_inlet_types
ALTER TABLE ONLY public.stalls ALTER COLUMN supported_inlet_types SET DEFAULT '{}'::text[];
-- @@ default public.stalls.covered
ALTER TABLE ONLY public.stalls ALTER COLUMN covered SET DEFAULT false;
-- @@ default public.storage_cert_0006_retention.id
ALTER TABLE ONLY public.storage_cert_0006_retention ALTER COLUMN id SET DEFAULT nextval('public.storage_cert_0006_retention_id_seq'::regclass);
-- @@ default public.storage_cert_0006_retention.captured_at
ALTER TABLE ONLY public.storage_cert_0006_retention ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.storage_cert_0006_samples.id
ALTER TABLE ONLY public.storage_cert_0006_samples ALTER COLUMN id SET DEFAULT nextval('public.storage_cert_0006_samples_id_seq'::regclass);
-- @@ default public.storage_cert_0006_samples.sampled_at
ALTER TABLE ONLY public.storage_cert_0006_samples ALTER COLUMN sampled_at SET DEFAULT now();
-- @@ default public.tariff_schedules.id
ALTER TABLE ONLY public.tariff_schedules ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.tariff_schedules.billing_cycle_day
ALTER TABLE ONLY public.tariff_schedules ALTER COLUMN billing_cycle_day SET DEFAULT 1;
-- @@ default public.tariff_schedules.is_active
ALTER TABLE ONLY public.tariff_schedules ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.tariff_schedules.created_at
ALTER TABLE ONLY public.tariff_schedules ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.tariff_schedules.updated_at
ALTER TABLE ONLY public.tariff_schedules ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.tuning_iterations.id
ALTER TABLE ONLY public.tuning_iterations ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- @@ default public.tuning_iterations.is_best_so_far
ALTER TABLE ONLY public.tuning_iterations ALTER COLUMN is_best_so_far SET DEFAULT false;
-- @@ default public.tuning_iterations.samples_evaluated
ALTER TABLE ONLY public.tuning_iterations ALTER COLUMN samples_evaluated SET DEFAULT 0;
-- @@ default public.tuning_iterations.regularization_penalty
ALTER TABLE ONLY public.tuning_iterations ALTER COLUMN regularization_penalty SET DEFAULT 0;
-- @@ default public.tuning_iterations.evaluation_details
ALTER TABLE ONLY public.tuning_iterations ALTER COLUMN evaluation_details SET DEFAULT '{}'::jsonb;
-- @@ default public.tuning_iterations.created_at
ALTER TABLE ONLY public.tuning_iterations ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.vehicle_need_profile.profile_version
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN profile_version SET DEFAULT 'v1'::text;
-- @@ default public.vehicle_need_profile.drawn_at
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN drawn_at SET DEFAULT now();
-- @@ default public.vehicle_need_profile.battery_chemistry
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN battery_chemistry SET DEFAULT 'NMC'::text;
-- @@ default public.vehicle_need_profile.dcfc_safe
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN dcfc_safe SET DEFAULT true;
-- @@ default public.vehicle_need_profile.cabin_condition
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN cabin_condition SET DEFAULT 'clean'::text;
-- @@ default public.vehicle_need_profile.wash_interval_h
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN wash_interval_h SET DEFAULT 72;
-- @@ default public.vehicle_need_profile.deep_clean_interval_h
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN deep_clean_interval_h SET DEFAULT 336;
-- @@ default public.vehicle_need_profile.open_fault_codes
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN open_fault_codes SET DEFAULT '{}'::text[];
-- @@ default public.vehicle_need_profile.worst_fault_severity
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN worst_fault_severity SET DEFAULT 99;
-- @@ default public.vehicle_need_profile.priority_class
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN priority_class SET DEFAULT 'standard'::text;
-- @@ default public.vehicle_need_profile.assigned_shift
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN assigned_shift SET DEFAULT 'flex'::text;
-- @@ default public.vehicle_need_profile.item_retrieval_pending
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN item_retrieval_pending SET DEFAULT false;
-- @@ default public.vehicle_need_profile.updated_at
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.vehicle_need_profile.rider_flag_pending
ALTER TABLE ONLY public.vehicle_need_profile ALTER COLUMN rider_flag_pending SET DEFAULT false;
-- @@ default public.vehicle_schedules.id
ALTER TABLE ONLY public.vehicle_schedules ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.vehicle_schedules.priority
ALTER TABLE ONLY public.vehicle_schedules ALTER COLUMN priority SET DEFAULT 'standard'::public.priority_tier;
-- @@ default public.vehicle_schedules.is_priority_override
ALTER TABLE ONLY public.vehicle_schedules ALTER COLUMN is_priority_override SET DEFAULT false;
-- @@ default public.vehicle_schedules.override_fee
ALTER TABLE ONLY public.vehicle_schedules ALTER COLUMN override_fee SET DEFAULT 0;
-- @@ default public.vehicle_schedules.status
ALTER TABLE ONLY public.vehicle_schedules ALTER COLUMN status SET DEFAULT 'draft'::public.schedule_status;
-- @@ default public.vehicle_schedules.planned_services
ALTER TABLE ONLY public.vehicle_schedules ALTER COLUMN planned_services SET DEFAULT '[]'::jsonb;
-- @@ default public.vehicle_schedules.modification_count
ALTER TABLE ONLY public.vehicle_schedules ALTER COLUMN modification_count SET DEFAULT 0;
-- @@ default public.vehicle_schedules.created_at
ALTER TABLE ONLY public.vehicle_schedules ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.vehicle_schedules.updated_at
ALTER TABLE ONLY public.vehicle_schedules ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.vehicle_state_log.id
ALTER TABLE ONLY public.vehicle_state_log ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.vehicle_state_log.metadata
ALTER TABLE ONLY public.vehicle_state_log ALTER COLUMN metadata SET DEFAULT '{}'::jsonb;
-- @@ default public.vehicle_state_log.created_at
ALTER TABLE ONLY public.vehicle_state_log ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.vehicle_telemetry.id
ALTER TABLE ONLY public.vehicle_telemetry ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.vehicle_telemetry."timestamp"
ALTER TABLE ONLY public.vehicle_telemetry ALTER COLUMN "timestamp" SET DEFAULT now();
-- @@ default public.vehicle_telemetry.source
ALTER TABLE ONLY public.vehicle_telemetry ALTER COLUMN source SET DEFAULT 'vehicle_api'::text;
-- @@ default public.vehicle_telemetry.created_at
ALTER TABLE ONLY public.vehicle_telemetry ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.vehicles.id
ALTER TABLE ONLY public.vehicles ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.vehicles.connector_type
ALTER TABLE ONLY public.vehicles ALTER COLUMN connector_type SET DEFAULT 'CCS'::text;
-- @@ default public.vehicles.target_soc
ALTER TABLE ONLY public.vehicles ALTER COLUMN target_soc SET DEFAULT 100;
-- @@ default public.vehicles.min_soc_threshold
ALTER TABLE ONLY public.vehicles ALTER COLUMN min_soc_threshold SET DEFAULT 15;
-- @@ default public.vehicles.platform
ALTER TABLE ONLY public.vehicles ALTER COLUMN platform SET DEFAULT 'not_applicable'::public.av_platform;
-- @@ default public.vehicles.av_dispatch_capable
ALTER TABLE ONLY public.vehicles ALTER COLUMN av_dispatch_capable SET DEFAULT false;
-- @@ default public.vehicles.current_state
ALTER TABLE ONLY public.vehicles ALTER COLUMN current_state SET DEFAULT 'offline'::public.vehicle_state;
-- @@ default public.vehicles.config
ALTER TABLE ONLY public.vehicles ALTER COLUMN config SET DEFAULT '{}'::jsonb;
-- @@ default public.vehicles.is_active
ALTER TABLE ONLY public.vehicles ALTER COLUMN is_active SET DEFAULT true;
-- @@ default public.vehicles.created_at
ALTER TABLE ONLY public.vehicles ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.vehicles.updated_at
ALTER TABLE ONLY public.vehicles ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.verify0006_retention.at
ALTER TABLE ONLY public.verify0006_retention ALTER COLUMN at SET DEFAULT now();
-- @@ default public.waves.id
ALTER TABLE ONLY public.waves ALTER COLUMN id SET DEFAULT extensions.uuid_generate_v4();
-- @@ default public.waves.vehicle_count
ALTER TABLE ONLY public.waves ALTER COLUMN vehicle_count SET DEFAULT 0;
-- @@ default public.waves.status
ALTER TABLE ONLY public.waves ALTER COLUMN status SET DEFAULT 'planned'::text;
-- @@ default public.waves.created_at
ALTER TABLE ONLY public.waves ALTER COLUMN created_at SET DEFAULT now();
-- @@ default public.waves.updated_at
ALTER TABLE ONLY public.waves ALTER COLUMN updated_at SET DEFAULT now();
-- @@ default public.workload_determinism_proof_2026_08_02.id
ALTER TABLE ONLY public.workload_determinism_proof_2026_08_02 ALTER COLUMN id SET DEFAULT nextval('public.workload_determinism_proof_2026_08_02_id_seq'::regclass);
-- @@ default public.workload_determinism_proof_2026_08_02.captured_at
ALTER TABLE ONLY public.workload_determinism_proof_2026_08_02 ALTER COLUMN captured_at SET DEFAULT now();
-- @@ default public.workload_determinism_proof_2026_08_02.captured_after_stop
ALTER TABLE ONLY public.workload_determinism_proof_2026_08_02 ALTER COLUMN captured_after_stop SET DEFAULT true;
-- @@ default twin.arm_cycles.cycle_id
ALTER TABLE ONLY twin.arm_cycles ALTER COLUMN cycle_id SET DEFAULT gen_random_uuid();
-- @@ default twin.arm_cycles.retry_count
ALTER TABLE ONLY twin.arm_cycles ALTER COLUMN retry_count SET DEFAULT 0;
-- @@ default twin.arm_cycles.meta
ALTER TABLE ONLY twin.arm_cycles ALTER COLUMN meta SET DEFAULT '{}'::jsonb;
-- @@ default twin.arm_registrations.registration_id
ALTER TABLE ONLY twin.arm_registrations ALTER COLUMN registration_id SET DEFAULT gen_random_uuid();
-- @@ default twin.ottoq_twin_operator_log.walks
ALTER TABLE ONLY twin.ottoq_twin_operator_log ALTER COLUMN walks SET DEFAULT 0;
-- @@ default twin.ottoq_twin_operator_state.directive_cursor
ALTER TABLE ONLY twin.ottoq_twin_operator_state ALTER COLUMN directive_cursor SET DEFAULT 0;
-- @@ default twin.ottoq_twin_operator_state.pending
ALTER TABLE ONLY twin.ottoq_twin_operator_state ALTER COLUMN pending SET DEFAULT '[]'::jsonb;
-- @@ default twin.ottoq_twin_operator_state.steps
ALTER TABLE ONLY twin.ottoq_twin_operator_state ALTER COLUMN steps SET DEFAULT 0;
-- @@ default twin.ottoq_twin_operators.created_at
ALTER TABLE ONLY twin.ottoq_twin_operators ALTER COLUMN created_at SET DEFAULT now();
