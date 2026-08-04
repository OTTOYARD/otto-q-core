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
-- ROW LEVEL SECURITY STATE  (schemas: public, ottoq, twin)  -- REFERENCE ONLY,
-- do not apply blindly
-- ----------------------------------------------------------------------------
-- Per-table RLS flag (relrowsecurity / relforcerowsecurity) + reconstructed
-- CREATE POLICY DDL from pg_policies. Read-only snapshot of the live security
-- posture, captured 2026-08-03.
--
-- Tables with RLS enabled: 133 of 282.  Total policies: 159.
-- (The 2026-07-13 snapshot read 121 of 149 tables and 145 policies. The table
--  count grew mostly from throwaway certification-evidence tables named
--  <phase|build|p#>_*_2026_08_0x / _424242 -- those are proof artifacts, not
--  product tables, and none of them carry RLS.)
--
-- SCHEMAS: the `ottoq` and `twin` schemas were created 2026-07-29 (migration
-- 437) and hold FUNCTIONS ONLY -- they contain no base tables, therefore no RLS
-- flags and no policies. Every row below is in `public`.
--
-- *** READ THE `-- roles:` LINE, NOT THE POLICY NAME. ***
-- A past incident had 31 policies NAMED "Service role full access" that were
-- actually scoped `TO PUBLIC`, so the publishable anon key could write
-- staff_users / fleet_operators / dispatch_commands / engine_config. That was
-- fixed 2026-07-30 by migration 466 (rescope_service_role_policies_off_public).
-- Each policy below is therefore preceded by its ACTUAL `pg_policies.roles`
-- value so that class of hole is visible in a diff.
--
-- Current role split across the 159 policies:
--   TO service_role .......... 63
--   TO public ................ 91   <-- mostly SELECT policies whose USING
--                                       clause itself tests auth.role(); these
--                                       are read-side, not the 2026-07-30 hole
--   TO authenticated / anon .. the remainder (5 policies name `anon`)
--
-- NOTE: `relforcerowsecurity` is false everywhere, so the table OWNER (and the
-- engine, which runs as owner) bypasses RLS entirely. RLS here constrains the
-- PostgREST-facing anon/authenticated keys, not the in-database engine.
-- ============================================================================

-- ------------------------- RLS ENABLEMENT PER TABLE -------------------------
-- public.ab_tests                                      rls_enabled=true  force_rls=false
ALTER TABLE public.ab_tests ENABLE ROW LEVEL SECURITY;
-- public.accuracy_alerts                               rls_enabled=true  force_rls=false
ALTER TABLE public.accuracy_alerts ENABLE ROW LEVEL SECURITY;
-- public.accuracy_slos                                 rls_enabled=true  force_rls=false
ALTER TABLE public.accuracy_slos ENABLE ROW LEVEL SECURITY;
-- public.action_guardrails                             rls_enabled=true  force_rls=false
ALTER TABLE public.action_guardrails ENABLE ROW LEVEL SECURITY;
-- public.ai_decision_log                               rls_enabled=true  force_rls=false
ALTER TABLE public.ai_decision_log ENABLE ROW LEVEL SECURITY;
-- public.api_integrations                              rls_enabled=true  force_rls=false
ALTER TABLE public.api_integrations ENABLE ROW LEVEL SECURITY;
-- public.autonomous_action_log                         rls_enabled=true  force_rls=false
ALTER TABLE public.autonomous_action_log ENABLE ROW LEVEL SECURITY;
-- public.availability_fix_proof_2026_08_03             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.availability_fix_proof_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.band_ab_compare_2026_08_01                    rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.band_ab_compare_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- public.band_calendar_proof_2026_08_01                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.band_calendar_proof_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- public.band_live_proof_run424242                     rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.band_live_proof_run424242 ENABLE ROW LEVEL SECURITY;
-- public.band_live_samples_2026_08_01                  rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.band_live_samples_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- public.band_live_samples_run424242                   rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.band_live_samples_run424242 ENABLE ROW LEVEL SECURITY;
-- public.band_verify_samples_2026_08_01                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.band_verify_samples_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- public.bay_reservation_reconcile_2026_08_02          rls_enabled=true  force_rls=false
ALTER TABLE public.bay_reservation_reconcile_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.bess_snapshots                                rls_enabled=true  force_rls=false
ALTER TABLE public.bess_snapshots ENABLE ROW LEVEL SECURITY;
-- public.booking_ledger_proof_2026_08_01               rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.booking_ledger_proof_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- public.booking_ledger_proof_bk_2026_08_01            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.booking_ledger_proof_bk_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- public.build1_smoke_result                           rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.build1_smoke_result ENABLE ROW LEVEL SECURITY;
-- public.build2_bookings_raw_2026_08_02                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.build2_bookings_raw_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.build2_cert_424242                            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.build2_cert_424242 ENABLE ROW LEVEL SECURITY;
-- public.build2_interrupted_recount_2026_08_02         rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.build2_interrupted_recount_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.build2_needscard_before_2026_08_02            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.build2_needscard_before_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.build2_visit_needs_raw_2026_08_02             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.build2_visit_needs_raw_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.build3_pre_bookings_2026_08_02                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.build3_pre_bookings_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.build3_pre_legs_2026_08_02                    rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.build3_pre_legs_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.build3_smoke_bookings_2026_08_02              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.build3_smoke_bookings_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.build3_smoke_legs_2026_08_02                  rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.build3_smoke_legs_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.busy_day_tick_probe_2026_08_01                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.busy_day_tick_probe_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- public.charger_cooldowns                             rls_enabled=true  force_rls=false
ALTER TABLE public.charger_cooldowns ENABLE ROW LEVEL SECURITY;
-- public.charger_health_scores                         rls_enabled=true  force_rls=false
ALTER TABLE public.charger_health_scores ENABLE ROW LEVEL SECURITY;
-- public.cuopt_enactment_proof_2026_08_01              rls_enabled=true  force_rls=false
ALTER TABLE public.cuopt_enactment_proof_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- public.cuopt_invocation_log                          rls_enabled=true  force_rls=false
ALTER TABLE public.cuopt_invocation_log ENABLE ROW LEVEL SECURITY;
-- public.cuopt_supply_before_2026_08_02                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.cuopt_supply_before_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.cuopt_supply_ledger_2026_08_03                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.cuopt_supply_ledger_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.cuopt_supply_proof_2026_08_02                 rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.cuopt_supply_proof_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.data_quality_errors                           rls_enabled=true  force_rls=false
ALTER TABLE public.data_quality_errors ENABLE ROW LEVEL SECURITY;
-- public.decision_fusion_log                           rls_enabled=true  force_rls=false
ALTER TABLE public.decision_fusion_log ENABLE ROW LEVEL SECURITY;
-- public.demand_management_log                         rls_enabled=true  force_rls=false
ALTER TABLE public.demand_management_log ENABLE ROW LEVEL SECURITY;
-- public.demand_shaping_plans                          rls_enabled=true  force_rls=false
ALTER TABLE public.demand_shaping_plans ENABLE ROW LEVEL SECURITY;
-- public.depot_state_snapshots                         rls_enabled=true  force_rls=false
ALTER TABLE public.depot_state_snapshots ENABLE ROW LEVEL SECURITY;
-- public.depot_visit_reports                           rls_enabled=true  force_rls=false
ALTER TABLE public.depot_visit_reports ENABLE ROW LEVEL SECURITY;
-- public.depots                                        rls_enabled=true  force_rls=false
ALTER TABLE public.depots ENABLE ROW LEVEL SECURITY;
-- public.dispatch_commands                             rls_enabled=true  force_rls=false
ALTER TABLE public.dispatch_commands ENABLE ROW LEVEL SECURITY;
-- public.downstream_action_contracts                   rls_enabled=true  force_rls=false
ALTER TABLE public.downstream_action_contracts ENABLE ROW LEVEL SECURITY;
-- public.early_recall_log                              rls_enabled=true  force_rls=false
ALTER TABLE public.early_recall_log ENABLE ROW LEVEL SECURITY;
-- public.emergency_queue_insertions                    rls_enabled=true  force_rls=false
ALTER TABLE public.emergency_queue_insertions ENABLE ROW LEVEL SECURITY;
-- public.emission_fix_smoke_2026_08_03                 rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.emission_fix_smoke_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.engine_config                                 rls_enabled=true  force_rls=false
ALTER TABLE public.engine_config ENABLE ROW LEVEL SECURITY;
-- public.exceptions                                    rls_enabled=true  force_rls=false
ALTER TABLE public.exceptions ENABLE ROW LEVEL SECURITY;
-- public.external_factor_sources                       rls_enabled=true  force_rls=false
ALTER TABLE public.external_factor_sources ENABLE ROW LEVEL SECURITY;
-- public.external_factors_log                          rls_enabled=true  force_rls=false
ALTER TABLE public.external_factors_log ENABLE ROW LEVEL SECURITY;
-- public.fleet_features_daily                          rls_enabled=true  force_rls=false
ALTER TABLE public.fleet_features_daily ENABLE ROW LEVEL SECURITY;
-- public.fleet_operators                               rls_enabled=true  force_rls=false
ALTER TABLE public.fleet_operators ENABLE ROW LEVEL SECURITY;
-- public.integration_health                            rls_enabled=true  force_rls=false
ALTER TABLE public.integration_health ENABLE ROW LEVEL SECURITY;
-- public.leg_why_smoke_2026_08_02                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.leg_why_smoke_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.maintenance_log                               rls_enabled=true  force_rls=false
ALTER TABLE public.maintenance_log ENABLE ROW LEVEL SECURITY;
-- public.maintenance_schedules                         rls_enabled=true  force_rls=false
ALTER TABLE public.maintenance_schedules ENABLE ROW LEVEL SECURITY;
-- public.model_parameters                              rls_enabled=true  force_rls=false
ALTER TABLE public.model_parameters ENABLE ROW LEVEL SECURITY;
-- public.model_tuning_runs                             rls_enabled=true  force_rls=false
ALTER TABLE public.model_tuning_runs ENABLE ROW LEVEL SECURITY;
-- public.model_versions                                rls_enabled=true  force_rls=false
ALTER TABLE public.model_versions ENABLE ROW LEVEL SECURITY;
-- public.notifications                                 rls_enabled=true  force_rls=false
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
-- public.ocpp_meter_values                             rls_enabled=true  force_rls=false
ALTER TABLE public.ocpp_meter_values ENABLE ROW LEVEL SECURITY;
-- public.ocpp_sessions                                 rls_enabled=true  force_rls=false
ALTER TABLE public.ocpp_sessions ENABLE ROW LEVEL SECURITY;
-- public.ottoq_ab_runs                                 rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_ab_runs ENABLE ROW LEVEL SECURITY;
-- public.ottoq_anomaly_detectors                       rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_anomaly_detectors ENABLE ROW LEVEL SECURITY;
-- public.ottoq_anomaly_observations                    rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_anomaly_observations ENABLE ROW LEVEL SECURITY;
-- public.ottoq_audit_bundles                           rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_audit_bundles ENABLE ROW LEVEL SECURITY;
-- public.ottoq_audit_reports                           rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_audit_reports ENABLE ROW LEVEL SECURITY;
-- public.ottoq_benchmark_frames                        rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_benchmark_frames ENABLE ROW LEVEL SECURITY;
-- public.ottoq_bess_units                              rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_bess_units ENABLE ROW LEVEL SECURITY;
-- public.ottoq_calibration_correlations                rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_calibration_correlations ENABLE ROW LEVEL SECURITY;
-- public.ottoq_calibration_datasets                    rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_calibration_datasets ENABLE ROW LEVEL SECURITY;
-- public.ottoq_calibration_distributions               rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_calibration_distributions ENABLE ROW LEVEL SECURITY;
-- public.ottoq_calibration_metrics                     rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_calibration_metrics ENABLE ROW LEVEL SECURITY;
-- public.ottoq_calibration_profiles                    rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_calibration_profiles ENABLE ROW LEVEL SECURITY;
-- public.ottoq_canopy_state                            rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_canopy_state ENABLE ROW LEVEL SECURITY;
-- public.ottoq_cert_queue                              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_cert_queue ENABLE ROW LEVEL SECURITY;
-- public.ottoq_cil_adoptions                           rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_cil_adoptions ENABLE ROW LEVEL SECURITY;
-- public.ottoq_comms_messages                          rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_comms_messages ENABLE ROW LEVEL SECURITY;
-- public.ottoq_counterfactuals                         rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_counterfactuals ENABLE ROW LEVEL SECURITY;
-- public.ottoq_cuopt_deferrals                         rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_cuopt_deferrals ENABLE ROW LEVEL SECURITY;
-- public.ottoq_cuopt_fire_log                          rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_cuopt_fire_log ENABLE ROW LEVEL SECURITY;
-- public.ottoq_data_drift_metrics                      rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_data_drift_metrics ENABLE ROW LEVEL SECURITY;
-- public.ottoq_decision_snapshots                      rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_decision_snapshots ENABLE ROW LEVEL SECURITY;
-- public.ottoq_decisions                               rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_decisions ENABLE ROW LEVEL SECURITY;
-- public.ottoq_deploy_log                              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_deploy_log ENABLE ROW LEVEL SECURITY;
-- public.ottoq_depot_benchmarks_daily                  rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_depot_benchmarks_daily ENABLE ROW LEVEL SECURITY;
-- public.ottoq_depot_cost_daily                        rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_depot_cost_daily ENABLE ROW LEVEL SECURITY;
-- public.ottoq_depot_shifts                            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_depot_shifts ENABLE ROW LEVEL SECURITY;
-- public.ottoq_depot_staffing                          rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_depot_staffing ENABLE ROW LEVEL SECURITY;
-- public.ottoq_depot_tariffs                           rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_depot_tariffs ENABLE ROW LEVEL SECURITY;
-- public.ottoq_dr_calls                                rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_dr_calls ENABLE ROW LEVEL SECURITY;
-- public.ottoq_dtc_catalog                             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_dtc_catalog ENABLE ROW LEVEL SECURITY;
-- public.ottoq_emergency_invocations                   rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_emergency_invocations ENABLE ROW LEVEL SECURITY;
-- public.ottoq_emergency_protocols                     rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_emergency_protocols ENABLE ROW LEVEL SECURITY;
-- public.ottoq_energy_commands                         rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_energy_commands ENABLE ROW LEVEL SECURITY;
-- public.ottoq_energy_plan                             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_energy_plan ENABLE ROW LEVEL SECURITY;
-- public.ottoq_event_types_catalog                     rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_event_types_catalog ENABLE ROW LEVEL SECURITY;
-- public.ottoq_events                                  rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_events ENABLE ROW LEVEL SECURITY;
-- public.ottoq_external_proposals                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_external_proposals ENABLE ROW LEVEL SECURITY;
-- public.ottoq_feature_values                          rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_feature_values ENABLE ROW LEVEL SECURITY;
-- public.ottoq_features                                rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_features ENABLE ROW LEVEL SECURITY;
-- public.ottoq_feed_activations                        rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_feed_activations ENABLE ROW LEVEL SECURITY;
-- public.ottoq_feed_plans                              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_feed_plans ENABLE ROW LEVEL SECURITY;
-- public.ottoq_fleet_operator_slas                     rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_fleet_operator_slas ENABLE ROW LEVEL SECURITY;
-- public.ottoq_fn_definition_backups                   rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_fn_definition_backups ENABLE ROW LEVEL SECURITY;
-- public.ottoq_grid_events                             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_grid_events ENABLE ROW LEVEL SECURITY;
-- public.ottoq_grid_snapshots                          rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_grid_snapshots ENABLE ROW LEVEL SECURITY;
-- public.ottoq_incident_reports                        rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_incident_reports ENABLE ROW LEVEL SECURITY;
-- public.ottoq_inference_log                           rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_inference_log ENABLE ROW LEVEL SECURITY;
-- public.ottoq_itinerary_legs                          rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_itinerary_legs ENABLE ROW LEVEL SECURITY;
-- public.ottoq_model_artifacts                         rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_model_artifacts ENABLE ROW LEVEL SECURITY;
-- public.ottoq_model_routes                            rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_model_routes ENABLE ROW LEVEL SECURITY;
-- public.ottoq_ocpp_chargers                           rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_ocpp_chargers ENABLE ROW LEVEL SECURITY;
-- public.ottoq_ocpp_messages                           rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_ocpp_messages ENABLE ROW LEVEL SECURITY;
-- public.ottoq_oem_webhook_log                         rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_oem_webhook_log ENABLE ROW LEVEL SECURITY;
-- public.ottoq_oem_webhook_patterns                    rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_oem_webhook_patterns ENABLE ROW LEVEL SECURITY;
-- public.ottoq_ops_approvals                           rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_ops_approvals ENABLE ROW LEVEL SECURITY;
-- public.ottoq_policy_param_catalog                    rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_policy_param_catalog ENABLE ROW LEVEL SECURITY;
-- public.ottoq_policy_params                           rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_policy_params ENABLE ROW LEVEL SECURITY;
-- public.ottoq_prediction_accuracy_heatmap             rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_prediction_accuracy_heatmap ENABLE ROW LEVEL SECURITY;
-- public.ottoq_prediction_rule_links                   rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_prediction_rule_links ENABLE ROW LEVEL SECURITY;
-- public.ottoq_prediction_types_catalog                rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_prediction_types_catalog ENABLE ROW LEVEL SECURITY;
-- public.ottoq_predictions                             rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_predictions ENABLE ROW LEVEL SECURITY;
-- public.ottoq_recommendations                         rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_recommendations ENABLE ROW LEVEL SECURITY;
-- public.ottoq_retention_state                         rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_retention_state ENABLE ROW LEVEL SECURITY;
-- public.ottoq_retraining_triggers                     rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_retraining_triggers ENABLE ROW LEVEL SECURITY;
-- public.ottoq_rule_evaluations                        rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_rule_evaluations ENABLE ROW LEVEL SECURITY;
-- public.ottoq_rule_overrides                          rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_rule_overrides ENABLE ROW LEVEL SECURITY;
-- public.ottoq_rule_parameters                         rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_rule_parameters ENABLE ROW LEVEL SECURITY;
-- public.ottoq_rules                                   rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_rules ENABLE ROW LEVEL SECURITY;
-- public.ottoq_run_archives                            rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_run_archives ENABLE ROW LEVEL SECURITY;
-- public.ottoq_scenarios                               rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_scenarios ENABLE ROW LEVEL SECURITY;
-- public.ottoq_schema_snapshots                        rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_schema_snapshots ENABLE ROW LEVEL SECURITY;
-- public.ottoq_signing_keys                            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_signing_keys ENABLE ROW LEVEL SECURITY;
-- public.ottoq_sim_runs                                rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_sim_runs ENABLE ROW LEVEL SECURITY;
-- public.ottoq_sim_scenarios                           rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_sim_scenarios ENABLE ROW LEVEL SECURITY;
-- public.ottoq_site_structures                         rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_site_structures ENABLE ROW LEVEL SECURITY;
-- public.ottoq_sla_conformance_daily                   rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_sla_conformance_daily ENABLE ROW LEVEL SECURITY;
-- public.ottoq_sla_violations                          rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_sla_violations ENABLE ROW LEVEL SECURITY;
-- public.ottoq_solar_output                            rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_solar_output ENABLE ROW LEVEL SECURITY;
-- public.ottoq_specialization_strategies               rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_specialization_strategies ENABLE ROW LEVEL SECURITY;
-- public.ottoq_stall_bookings                          rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_stall_bookings ENABLE ROW LEVEL SECURITY;
-- public.ottoq_state_transitions                       rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_state_transitions ENABLE ROW LEVEL SECURITY;
-- public.ottoq_t4_coverage_samples                     rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_t4_coverage_samples ENABLE ROW LEVEL SECURITY;
-- public.ottoq_tariff_windows                          rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_tariff_windows ENABLE ROW LEVEL SECURITY;
-- public.ottoq_telemetry_packets                       rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_telemetry_packets ENABLE ROW LEVEL SECURITY;
-- public.ottoq_tick_clock_log                          rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_tick_clock_log ENABLE ROW LEVEL SECURITY;
-- public.ottoq_tick_invariance_arms                    rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_tick_invariance_arms ENABLE ROW LEVEL SECURITY;
-- public.ottoq_tick_reservations                       rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_tick_reservations ENABLE ROW LEVEL SECURITY;
-- public.ottoq_training_runs                           rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_training_runs ENABLE ROW LEVEL SECURITY;
-- public.ottoq_variability_cards                       rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_variability_cards ENABLE ROW LEVEL SECURITY;
-- public.ottoq_variability_catalog                     rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_variability_catalog ENABLE ROW LEVEL SECURITY;
-- public.ottoq_variability_profiles                    rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_variability_profiles ENABLE ROW LEVEL SECURITY;
-- public.ottoq_vehicle_classes                         rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_vehicle_classes ENABLE ROW LEVEL SECURITY;
-- public.ottoq_vehicle_commands                        rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_vehicle_commands ENABLE ROW LEVEL SECURITY;
-- public.ottoq_vehicle_dispatches                      rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_vehicle_dispatches ENABLE ROW LEVEL SECURITY;
-- public.ottoq_vehicle_incidents                       rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_vehicle_incidents ENABLE ROW LEVEL SECURITY;
-- public.ottoq_vehicle_itineraries                     rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_vehicle_itineraries ENABLE ROW LEVEL SECURITY;
-- public.ottoq_vehicle_wear                            rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_vehicle_wear ENABLE ROW LEVEL SECURITY;
-- public.ottoq_visit_cost_attribution                  rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_visit_cost_attribution ENABLE ROW LEVEL SECURITY;
-- public.ottoq_visit_needs                             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_visit_needs ENABLE ROW LEVEL SECURITY;
-- public.ottoq_wave_plan                               rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.ottoq_wave_plan ENABLE ROW LEVEL SECURITY;
-- public.ottoq_wear_tick_status                        rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_wear_tick_status ENABLE ROW LEVEL SECURITY;
-- public.ottoq_weather_snapshots                       rls_enabled=true  force_rls=false
ALTER TABLE public.ottoq_weather_snapshots ENABLE ROW LEVEL SECURITY;
-- public.ottow_api_keys                                rls_enabled=true  force_rls=false
ALTER TABLE public.ottow_api_keys ENABLE ROW LEVEL SECURITY;
-- public.ottow_dispatch_rules                          rls_enabled=true  force_rls=false
ALTER TABLE public.ottow_dispatch_rules ENABLE ROW LEVEL SECURITY;
-- public.ottow_drivers                                 rls_enabled=true  force_rls=false
ALTER TABLE public.ottow_drivers ENABLE ROW LEVEL SECURITY;
-- public.ottow_mission_events                          rls_enabled=true  force_rls=false
ALTER TABLE public.ottow_mission_events ENABLE ROW LEVEL SECURITY;
-- public.ottow_missions                                rls_enabled=true  force_rls=false
ALTER TABLE public.ottow_missions ENABLE ROW LEVEL SECURITY;
-- public.ottow_notifications                           rls_enabled=true  force_rls=false
ALTER TABLE public.ottow_notifications ENABLE ROW LEVEL SECURITY;
-- public.p0_booking_test_2026_08_01                    rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p0_booking_test_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- public.p0_calendar_diagnosis_2026_08_02              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p0_calendar_diagnosis_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.p0_reopen_baseline_2026_08_03                 rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p0_reopen_baseline_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.p12_contaminated_run904_bookings              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p12_contaminated_run904_bookings ENABLE ROW LEVEL SECURITY;
-- public.p12_contaminated_run904_cuopt                 rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p12_contaminated_run904_cuopt ENABLE ROW LEVEL SECURITY;
-- public.p12_contaminated_run904_needs                 rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p12_contaminated_run904_needs ENABLE ROW LEVEL SECURITY;
-- public.p12_contaminated_run904_runrow                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p12_contaminated_run904_runrow ENABLE ROW LEVEL SECURITY;
-- public.p2_cuopt_first_refusal_smoke_2026_08_02       rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p2_cuopt_first_refusal_smoke_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.p2_eviction_proof_2026_08_03                  rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p2_eviction_proof_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.p2_guard_unit_2026_08_03                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p2_guard_unit_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.p2_unfreeze_proof_2026_08_01                  rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p2_unfreeze_proof_2026_08_01 ENABLE ROW LEVEL SECURITY;
-- public.p3_phantom_smoke_2026_08_02                   rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p3_phantom_smoke_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.p3_smoke_restore_2026_08_02                   rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p3_smoke_restore_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.p7_band_probe_2026_08_03                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p7_band_probe_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.p7_cuopt_supply_proof_2026_08_03              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.p7_cuopt_supply_proof_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phantom_provenance_proof_2026_08_02           rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phantom_provenance_proof_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.phase10_bookings_424242                       rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_bookings_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase10_cap_unit_2026_08_03                   rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_cap_unit_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase10_cert_424242                           rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_cert_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase10_cuopt_log_424242                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_cuopt_log_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase10_dispatches_424242                     rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_dispatches_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase10_eviction_evidence_424242              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_eviction_evidence_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase10_guard_unit_2026_08_03                 rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_guard_unit_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase10_interruption_retro_2026_08_03         rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_interruption_retro_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase10_replan_unit_2026_08_03                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_replan_unit_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase10_smoke_evidence_2026_08_03             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_smoke_evidence_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase10_smoke_mark2_2026_08_03                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_smoke_mark2_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase10_smoke_mark_2026_08_03                 rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_smoke_mark_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase10_smoke_needs_2026_08_03                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_smoke_needs_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase10_visit_needs_424242                    rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase10_visit_needs_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase11_bookings_424242                       rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_bookings_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase11_cert_424242                           rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_cert_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase11_cuopt_log_424242                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_cuopt_log_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase11_dispatches_424242                     rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_dispatches_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase11_eviction_evidence_424242              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_eviction_evidence_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase11_guard_smoke_2026_08_03                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_guard_smoke_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_harness_correction_424242             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_harness_correction_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase11_pre_bookings_2026_08_03               rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_pre_bookings_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_pre_legs_2026_08_03                   rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_pre_legs_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_pre_needs_2026_08_03                  rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_pre_needs_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_proof_2026_08_03                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_proof_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_resume_proof_2026_08_03               rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_resume_proof_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_run897_bookings_2026_08_03            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_run897_bookings_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_run897_cuopt_2026_08_03               rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_run897_cuopt_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_run897_dispatches_2026_08_03          rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_run897_dispatches_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_run897_harness_2026_08_03             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_run897_harness_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_run897_needs_2026_08_03               rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_run897_needs_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_run897_runrow_2026_08_03              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_run897_runrow_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_runid_2026_08_03                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_runid_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_runrow_424242                         rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_runrow_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase11_smoke_2026_08_03                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_smoke_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_smoke_bookings_2026_08_03             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_smoke_bookings_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_smoke_legs_2026_08_03                 rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_smoke_legs_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_smoke_needs_2026_08_03                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_smoke_needs_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase11_visit_needs_424242                    rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase11_visit_needs_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase1_busy_proof_424242                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase1_busy_proof_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase2_busy_proof_424242                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase2_busy_proof_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase3_bay_commands_2026_08_02                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase3_bay_commands_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.phase3_bay_proof_2026_08_02                   rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase3_bay_proof_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.phase3_cert_424242                            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase3_cert_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase4_cert_424242                            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase4_cert_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase5_cert_424242                            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase5_cert_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase5_cert_d78dd3b1                          rls_enabled=true  force_rls=false
ALTER TABLE public.phase5_cert_d78dd3b1 ENABLE ROW LEVEL SECURITY;
-- public.phase6_cert_424242                            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase6_cert_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase6_cert_424242_supply                     rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase6_cert_424242_supply ENABLE ROW LEVEL SECURITY;
-- public.phase6_cert_424242_telemetry                  rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase6_cert_424242_telemetry ENABLE ROW LEVEL SECURITY;
-- public.phase7_bookings_424242                        rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase7_bookings_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase7_cert_424242                            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase7_cert_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase7_cuopt_log_424242                       rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase7_cuopt_log_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase7_dispatches_424242                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase7_dispatches_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase7_prestop_bookings_424242                rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase7_prestop_bookings_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase7_reconcile_424242                       rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase7_reconcile_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_bookings_424242                        rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_bookings_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_cert_424242                            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_cert_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_dispatches_424242                      rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_dispatches_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_eviction_evidence_424242               rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_eviction_evidence_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_fix1_pre_2026_08_02                    rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_fix1_pre_2026_08_02 ENABLE ROW LEVEL SECURITY;
-- public.phase9_fix2_prefix_bookings_424242            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_fix2_prefix_bookings_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_fix2_prefix_evidence_424242            rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_fix2_prefix_evidence_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_fix3_post_424242                       rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_fix3_post_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_fix3_post_decisions_424242             rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_fix3_post_decisions_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_fix3_pre_424242                        rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_fix3_pre_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_fix3_pre_decisions_424242              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_fix3_pre_decisions_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_fix3_pre_legs_424242                   rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_fix3_pre_legs_424242 ENABLE ROW LEVEL SECURITY;
-- public.phase9_prior_bookings_2026_08_03              rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_prior_bookings_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase9_prior_runs_2026_08_03                  rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_prior_runs_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.phase9_visit_needs_424242                     rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.phase9_visit_needs_424242 ENABLE ROW LEVEL SECURITY;
-- public.prediction_accuracy_daily                     rls_enabled=true  force_rls=false
ALTER TABLE public.prediction_accuracy_daily ENABLE ROW LEVEL SECURITY;
-- public.prediction_explanations                       rls_enabled=true  force_rls=false
ALTER TABLE public.prediction_explanations ENABLE ROW LEVEL SECURITY;
-- public.prediction_outcomes                           rls_enabled=true  force_rls=false
ALTER TABLE public.prediction_outcomes ENABLE ROW LEVEL SECURITY;
-- public.progression_decisions                         rls_enabled=true  force_rls=false
ALTER TABLE public.progression_decisions ENABLE ROW LEVEL SECURITY;
-- public.retail_members                                rls_enabled=true  force_rls=false
ALTER TABLE public.retail_members ENABLE ROW LEVEL SECURITY;
-- public.schedule_modifications                        rls_enabled=true  force_rls=false
ALTER TABLE public.schedule_modifications ENABLE ROW LEVEL SECURITY;
-- public.schedule_tasks                                rls_enabled=true  force_rls=false
ALTER TABLE public.schedule_tasks ENABLE ROW LEVEL SECURITY;
-- public.service_cadence_policy                        rls_enabled=true  force_rls=false
ALTER TABLE public.service_cadence_policy ENABLE ROW LEVEL SECURITY;
-- public.service_definitions                           rls_enabled=true  force_rls=false
ALTER TABLE public.service_definitions ENABLE ROW LEVEL SECURITY;
-- public.site_energy_snapshots                         rls_enabled=true  force_rls=false
ALTER TABLE public.site_energy_snapshots ENABLE ROW LEVEL SECURITY;
-- public.smoke890_bookings_2026_08_03                  rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.smoke890_bookings_2026_08_03 ENABLE ROW LEVEL SECURITY;
-- public.space_conflict_ledger                         rls_enabled=true  force_rls=false
ALTER TABLE public.space_conflict_ledger ENABLE ROW LEVEL SECURITY;
-- public.staff_users                                   rls_enabled=true  force_rls=false
ALTER TABLE public.staff_users ENABLE ROW LEVEL SECURITY;
-- public.stalls                                        rls_enabled=true  force_rls=false
ALTER TABLE public.stalls ENABLE ROW LEVEL SECURITY;
-- public.tariff_schedules                              rls_enabled=true  force_rls=false
ALTER TABLE public.tariff_schedules ENABLE ROW LEVEL SECURITY;
-- public.tuning_iterations                             rls_enabled=true  force_rls=false
ALTER TABLE public.tuning_iterations ENABLE ROW LEVEL SECURITY;
-- public.vehicle_need_profile                          rls_enabled=true  force_rls=false
ALTER TABLE public.vehicle_need_profile ENABLE ROW LEVEL SECURITY;
-- public.vehicle_schedules                             rls_enabled=true  force_rls=false
ALTER TABLE public.vehicle_schedules ENABLE ROW LEVEL SECURITY;
-- public.vehicle_state_log                             rls_enabled=true  force_rls=false
ALTER TABLE public.vehicle_state_log ENABLE ROW LEVEL SECURITY;
-- public.vehicle_telemetry                             rls_enabled=true  force_rls=false
ALTER TABLE public.vehicle_telemetry ENABLE ROW LEVEL SECURITY;
-- public.vehicles                                      rls_enabled=true  force_rls=false
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
-- public.waves                                         rls_enabled=true  force_rls=false
ALTER TABLE public.waves ENABLE ROW LEVEL SECURITY;
-- public.workload_determinism_proof_2026_08_02         rls_enabled=false force_rls=false
-- (RLS DISABLED) ALTER TABLE public.workload_determinism_proof_2026_08_02 ENABLE ROW LEVEL SECURITY;

-- ------------------------------- POLICIES ----------------------------------
-- Each policy is preceded by its ACTUAL pg_policies.roles value. The NAME is
-- not evidence of scope; the roles line is.

-- roles: public
CREATE POLICY service_role_ab_tests ON public.ab_tests AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_alerts ON public.accuracy_alerts AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_slos ON public.accuracy_slos AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_guardrails ON public.action_guardrails AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.ai_decision_log AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.api_integrations AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY service_role_action_log ON public.autonomous_action_log AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.bess_snapshots AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.charger_cooldowns AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.charger_health_scores AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "service_role full access" ON public.cuopt_enactment_proof_2026_08_01 AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "service_role full access" ON public.cuopt_invocation_log AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY service_role_dq_errors ON public.data_quality_errors AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_fusion_log ON public.decision_fusion_log AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.demand_management_log AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.demand_shaping_plans AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY service_role_depot_snapshots ON public.depot_state_snapshots AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_visit_reports ON public.depot_visit_reports AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: anon, authenticated
CREATE POLICY "client keys read only" ON public.depots AS PERMISSIVE FOR SELECT TO anon, authenticated
    USING (true);

-- roles: service_role
CREATE POLICY "service_role writes world state" ON public.depots AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY "Fleet operators see own dispatches" ON public.dispatch_commands AS PERMISSIVE FOR SELECT TO public
    USING ((vehicle_id IN ( SELECT vehicles.id
   FROM vehicles
  WHERE (vehicles.fleet_operator_id = get_fleet_operator_id()))));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.dispatch_commands AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY service_role_contracts ON public.downstream_action_contracts AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.early_recall_log AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.emergency_queue_insertions AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.engine_config AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY "Fleet operators see own exceptions" ON public.exceptions AS PERMISSIVE FOR SELECT TO public
    USING ((vehicle_id IN ( SELECT vehicles.id
   FROM vehicles
  WHERE (vehicles.fleet_operator_id = get_fleet_operator_id()))));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.exceptions AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY "Staff see own depot exceptions" ON public.exceptions AS PERMISSIVE FOR SELECT TO public
    USING ((depot_id = get_staff_depot_id()));

-- roles: public
CREATE POLICY service_role_ext_sources ON public.external_factor_sources AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_ext_log ON public.external_factors_log AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_fleet_features ON public.fleet_features_daily AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.fleet_operators AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.integration_health AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.maintenance_log AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.maintenance_schedules AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY service_role_model_parameters ON public.model_parameters AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_tuning_runs ON public.model_tuning_runs AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_model_versions ON public.model_versions AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY "Fleet operators see own notifications" ON public.notifications AS PERMISSIVE FOR SELECT TO public
    USING ((fleet_operator_id = get_fleet_operator_id()));

-- roles: public
CREATE POLICY "Retail members see own notifications" ON public.notifications AS PERMISSIVE FOR SELECT TO public
    USING ((retail_member_id = get_retail_member_id()));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.notifications AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY "Staff see own depot notifications" ON public.notifications AS PERMISSIVE FOR SELECT TO public
    USING ((staff_user_id IN ( SELECT staff_users.id
   FROM staff_users
  WHERE (staff_users.auth_user_id = auth.uid()))));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.ocpp_meter_values AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.ocpp_sessions AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY p_ab_runs_read ON public.ottoq_ab_runs AS PERMISSIVE FOR SELECT TO public
    USING (true);

-- roles: public
CREATE POLICY detectors_read ON public.ottoq_anomaly_detectors AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY anomaly_obs_tenant_read ON public.ottoq_anomaly_observations AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: public
CREATE POLICY audit_bundles_tenant_read ON public.ottoq_audit_bundles AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR ((fleet_operator_id IS NOT NULL) AND ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text))))));

-- roles: public
CREATE POLICY audit_reports_tenant_read ON public.ottoq_audit_reports AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: authenticated
CREATE POLICY p_bess_units_read ON public.ottoq_bess_units AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: service_role
CREATE POLICY p_bess_units_write ON public.ottoq_bess_units AS PERMISSIVE FOR UPDATE TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY calib_corr_read ON public.ottoq_calibration_correlations AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY calib_datasets_read ON public.ottoq_calibration_datasets AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY calib_dist_read ON public.ottoq_calibration_distributions AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY calib_read ON public.ottoq_calibration_metrics AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY calib_prof_read ON public.ottoq_calibration_profiles AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: authenticated
CREATE POLICY p_canopy_read ON public.ottoq_canopy_state AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: service_role
CREATE POLICY p_canopy_write ON public.ottoq_canopy_state AS PERMISSIVE FOR UPDATE TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY counterfactuals_tenant_read ON public.ottoq_counterfactuals AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.ottoq_cuopt_deferrals AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY drift_read ON public.ottoq_data_drift_metrics AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY p_decision_snapshots_read ON public.ottoq_decision_snapshots AS PERMISSIVE FOR SELECT TO public
    USING (true);

-- roles: public
CREATE POLICY p_decisions_read ON public.ottoq_decisions AS PERMISSIVE FOR SELECT TO public
    USING (true);

-- roles: public
CREATE POLICY benchmarks_read ON public.ottoq_depot_benchmarks_daily AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY depot_cost_read ON public.ottoq_depot_cost_daily AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = 'service_role'::text));

-- roles: authenticated
CREATE POLICY p_dr_calls_read ON public.ottoq_dr_calls AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: public
CREATE POLICY emergency_invocations_read ON public.ottoq_emergency_invocations AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY emergency_protocols_read ON public.ottoq_emergency_protocols AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY ottoq_events_no_direct_writes ON public.ottoq_events AS PERMISSIVE FOR ALL TO public
    USING (false)
    WITH CHECK (false);

-- roles: public
CREATE POLICY ottoq_events_service_role_all ON public.ottoq_events AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY ottoq_events_tenant_select ON public.ottoq_events AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'authenticated'::text) AND ((fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text))))));

-- roles: public
CREATE POLICY feature_values_tenant_read ON public.ottoq_feature_values AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: public
CREATE POLICY features_read ON public.ottoq_features AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY slas_tenant_select ON public.ottoq_fleet_operator_slas AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: authenticated
CREATE POLICY p_grid_snap_read ON public.ottoq_grid_snapshots AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: public
CREATE POLICY incident_reports_tenant_read ON public.ottoq_incident_reports AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: public
CREATE POLICY inference_log_tenant_read ON public.ottoq_inference_log AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: public
CREATE POLICY model_artifacts_read ON public.ottoq_model_artifacts AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY model_routes_read ON public.ottoq_model_routes AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY ocpp_msgs_read ON public.ottoq_ocpp_messages AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));

-- roles: authenticated
CREATE POLICY p_webhook_log_admin_read ON public.ottoq_oem_webhook_log AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: service_role
CREATE POLICY p_webhook_log_service_write ON public.ottoq_oem_webhook_log AS PERMISSIVE FOR INSERT TO service_role
    WITH CHECK (true);

-- roles: authenticated
CREATE POLICY p_webhook_patterns_read ON public.ottoq_oem_webhook_patterns AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: public
CREATE POLICY pred_accuracy_tenant_read ON public.ottoq_prediction_accuracy_heatmap AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: public
CREATE POLICY pred_rule_links_read ON public.ottoq_prediction_rule_links AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY pred_types_read ON public.ottoq_prediction_types_catalog AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.ottoq_predictions AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY recs_tenant_read ON public.ottoq_recommendations AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: public
CREATE POLICY retrain_triggers_read ON public.ottoq_retraining_triggers AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY ottoq_evals_tenant_read ON public.ottoq_rule_evaluations AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: public
CREATE POLICY ottoq_overrides_tenant_read ON public.ottoq_rule_overrides AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (fleet_operator_id IS NULL) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: public
CREATE POLICY ottoq_rule_params_read ON public.ottoq_rule_parameters AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR ((scope_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: public
CREATE POLICY ottoq_rules_read ON public.ottoq_rules AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: service_role
CREATE POLICY "service_role full access" ON public.ottoq_run_archives AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY scenarios_read ON public.ottoq_scenarios AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY sim_runs_read ON public.ottoq_sim_runs AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));

-- roles: authenticated
CREATE POLICY p_scenarios_read ON public.ottoq_sim_scenarios AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: public
CREATE POLICY site_structures_read ON public.ottoq_site_structures AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY sla_conf_tenant_read ON public.ottoq_sla_conformance_daily AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: public
CREATE POLICY sla_viol_tenant_read ON public.ottoq_sla_violations AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: authenticated
CREATE POLICY p_solar_read ON public.ottoq_solar_output AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: public
CREATE POLICY specialization_read ON public.ottoq_specialization_strategies AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: authenticated
CREATE POLICY p_tariff_read ON public.ottoq_tariff_windows AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: public
CREATE POLICY telem_packets_read ON public.ottoq_telemetry_packets AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY training_runs_read ON public.ottoq_training_runs AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));

-- roles: anon, authenticated
CREATE POLICY p_varcat_read ON public.ottoq_variability_catalog AS PERMISSIVE FOR SELECT TO anon, authenticated
    USING (true);

-- roles: authenticated
CREATE POLICY p_varprofile_read ON public.ottoq_variability_profiles AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: service_role
CREATE POLICY p_varprofile_write ON public.ottoq_variability_profiles AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY vehicle_classes_read ON public.ottoq_vehicle_classes AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text])));

-- roles: anon, authenticated
CREATE POLICY "client keys read commands" ON public.ottoq_vehicle_commands AS PERMISSIVE FOR SELECT TO anon, authenticated
    USING (true);

-- roles: service_role
CREATE POLICY "service_role writes commands" ON public.ottoq_vehicle_commands AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY dispatches_read ON public.ottoq_vehicle_dispatches AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY incidents_read ON public.ottoq_vehicle_incidents AS PERMISSIVE FOR SELECT TO public
    USING ((auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text])));

-- roles: public
CREATE POLICY visit_cost_tenant_read ON public.ottoq_visit_cost_attribution AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR ((fleet_operator_id)::text = COALESCE(NULLIF(current_setting('request.jwt.claim.fleet_operator_id'::text, true), ''::text), (auth.jwt() ->> 'fleet_operator_id'::text)))));

-- roles: authenticated
CREATE POLICY p_weather_read ON public.ottoq_weather_snapshots AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: service_role
CREATE POLICY "Service role full access on ottow_api_keys" ON public.ottow_api_keys AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access on ottow_dispatch_rules" ON public.ottow_dispatch_rules AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY "Drivers can view own record" ON public.ottow_drivers AS PERMISSIVE FOR SELECT TO public
    USING (((staff_user_id = auth.uid()) OR (auth.role() = 'service_role'::text)));

-- roles: public
CREATE POLICY "Service role full access drivers" ON public.ottow_drivers AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY "Authenticated users can view mission events" ON public.ottow_mission_events AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (mission_id IN ( SELECT m.id
   FROM (ottow_missions m
     JOIN staff_users s ON ((s.depot_id = m.depot_id)))
  WHERE (s.auth_user_id = auth.uid())))));

-- roles: public
CREATE POLICY "Service role full access events" ON public.ottow_mission_events AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY "Authenticated users can view depot missions" ON public.ottow_missions AS PERMISSIVE FOR SELECT TO public
    USING (((auth.role() = 'service_role'::text) OR (depot_id IN ( SELECT staff_users.depot_id
   FROM staff_users
  WHERE (staff_users.auth_user_id = auth.uid())))));

-- roles: public
CREATE POLICY "Service role full access missions" ON public.ottow_missions AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text));

-- roles: service_role
CREATE POLICY "Service role full access on ottow_notifications" ON public.ottow_notifications AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "service_role full access" ON public.phase5_cert_d78dd3b1 AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY service_role_accuracy_daily ON public.prediction_accuracy_daily AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_explanations ON public.prediction_explanations AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_prediction_outcomes ON public.prediction_outcomes AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: public
CREATE POLICY service_role_progression_decisions ON public.progression_decisions AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.retail_members AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.schedule_modifications AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY "Fleet operators see own tasks" ON public.schedule_tasks AS PERMISSIVE FOR SELECT TO public
    USING ((vehicle_id IN ( SELECT vehicles.id
   FROM vehicles
  WHERE (vehicles.fleet_operator_id = get_fleet_operator_id()))));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.schedule_tasks AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY "Staff see own depot tasks" ON public.schedule_tasks AS PERMISSIVE FOR SELECT TO public
    USING ((depot_id = get_staff_depot_id()));

-- roles: service_role
CREATE POLICY service_cadence_policy_service_role ON public.service_cadence_policy AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.service_definitions AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.site_energy_snapshots AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: authenticated
CREATE POLICY p_site_energy_read ON public.site_energy_snapshots AS PERMISSIVE FOR SELECT TO authenticated
    USING (true);

-- roles: service_role
CREATE POLICY space_conflict_ledger_service_role ON public.space_conflict_ledger AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.staff_users AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: authenticated
CREATE POLICY "Staff read own record" ON public.staff_users AS PERMISSIVE FOR SELECT TO authenticated
    USING ((auth_user_id = auth.uid()));

-- roles: public
CREATE POLICY "Staff see own depot stalls" ON public.stalls AS PERMISSIVE FOR SELECT TO public
    USING ((depot_id = get_staff_depot_id()));

-- roles: anon, authenticated
CREATE POLICY "client keys read only" ON public.stalls AS PERMISSIVE FOR SELECT TO anon, authenticated
    USING (true);

-- roles: service_role
CREATE POLICY "service_role writes world state" ON public.stalls AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.tariff_schedules AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY service_role_tuning_iter ON public.tuning_iterations AS PERMISSIVE FOR ALL TO public
    USING ((auth.role() = 'service_role'::text))
    WITH CHECK ((auth.role() = 'service_role'::text));

-- roles: service_role
CREATE POLICY "vehicle_need_profile service role" ON public.vehicle_need_profile AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY "Fleet operators see own schedules" ON public.vehicle_schedules AS PERMISSIVE FOR SELECT TO public
    USING ((vehicle_id IN ( SELECT vehicles.id
   FROM vehicles
  WHERE (vehicles.fleet_operator_id = get_fleet_operator_id()))));

-- roles: public
CREATE POLICY "Retail members see own schedules" ON public.vehicle_schedules AS PERMISSIVE FOR SELECT TO public
    USING ((vehicle_id IN ( SELECT vehicles.id
   FROM vehicles
  WHERE (vehicles.retail_member_id = get_retail_member_id()))));

-- roles: service_role
CREATE POLICY "Service role full access" ON public.vehicle_schedules AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.vehicle_state_log AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.vehicle_telemetry AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: public
CREATE POLICY "Fleet operators see own vehicles" ON public.vehicles AS PERMISSIVE FOR SELECT TO public
    USING (((fleet_operator_id = get_fleet_operator_id()) OR (fleet_operator_id IS NULL)));

-- roles: public
CREATE POLICY "Retail members see own vehicles" ON public.vehicles AS PERMISSIVE FOR SELECT TO public
    USING ((retail_member_id = get_retail_member_id()));

-- roles: public
CREATE POLICY "Staff see own depot vehicles" ON public.vehicles AS PERMISSIVE FOR SELECT TO public
    USING (((current_depot_id = get_staff_depot_id()) OR (home_depot_id = get_staff_depot_id())));

-- roles: anon, authenticated
CREATE POLICY "client keys read only" ON public.vehicles AS PERMISSIVE FOR SELECT TO anon, authenticated
    USING (true);

-- roles: service_role
CREATE POLICY "service_role writes world state" ON public.vehicles AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- roles: service_role
CREATE POLICY "Service role full access" ON public.waves AS PERMISSIVE FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);
