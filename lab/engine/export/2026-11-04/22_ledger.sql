-- 22_ledger.sql: 1337 statements, exported from production's catalog
-- @@ ledger 20260618035454
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260618035454', 'hw001_charging_scope_guard', 'chase@ottoyard.com');
-- @@ ledger 20260618035521
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260618035521', 'hw003_charging_scope_guard', 'chase@ottoyard.com');
-- @@ ledger 20260618040448
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260618040448', 'ottoq_progress_commit_rpc', 'chase@ottoyard.com');
-- @@ ledger 20260618040725
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260618040725', 'ottoq_progress_commit_rpc_searchpath_fix', 'chase@ottoyard.com');
-- @@ ledger 20260618041641
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260618041641', 'ottoq_amend_apply_rpc', 'chase@ottoyard.com');
-- @@ ledger 20260618174359
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260618174359', 'oq9_add_wash_detail_service_bays', 'chase@ottoyard.com');
-- @@ ledger 20260618181713
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260618181713', 'ottoq_cleaning_due_cadence', 'chase@ottoyard.com');
-- @@ ledger 20260618182301
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260618182301', 'ottoq_cleaning_due_fix_arrayappend', 'chase@ottoyard.com');
-- @@ ledger 20260619132620
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619132620', 'ottoq_continuous_tick_cron', 'chase@ottoyard.com');
-- @@ ledger 20260619132824
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619132824', 'ottoq_cron_tick_timeout_fix', 'chase@ottoyard.com');
-- @@ ledger 20260619155631
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619155631', 'ottoq_world_advance_production', 'chase@ottoyard.com');
-- @@ ledger 20260619160017
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619160017', 'ottoq_cron_tick_add_world_advance', 'chase@ottoyard.com');
-- @@ ledger 20260619161117
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619161117', 'ottoq_shield_and_log_primitive', 'chase@ottoyard.com');
-- @@ ledger 20260619192423
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619192423', 'oq_u5a_benchmark_depot_clone_v2', 'chase@ottoyard.com');
-- @@ ledger 20260619193309
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619193309', 'oq_u5b_manual_baseline_tick', 'chase@ottoyard.com');
-- @@ ledger 20260619193337
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619193337', 'oq_u5b_advance_tick_route_manual', 'chase@ottoyard.com');
-- @@ ledger 20260619201253
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619201253', 'oq_u5b_charge_session_reconciler', 'chase@ottoyard.com');
-- @@ ledger 20260619201338
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619201338', 'oq_u5b_advance_tick_wire_reconciler', 'chase@ottoyard.com');
-- @@ ledger 20260619201954
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619201954', 'oq_u5b_incident_trigger_skip_benchmark', 'chase@ottoyard.com');
-- @@ ledger 20260619202311
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619202311', 'oq_u5b_incident_trigger_skip_benchmark_depot', 'chase@ottoyard.com');
-- @@ ledger 20260619203149
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619203149', 'oq_u5b_manual_concurrent_cap', 'chase@ottoyard.com');
-- @@ ledger 20260619203736
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619203736', 'oq_u5b_advance_tick_service_flow', 'chase@ottoyard.com');
-- @@ ledger 20260619204422
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260619204422', 'oq_u5b_greedy_no_double_serviceflow', 'chase@ottoyard.com');
-- @@ ledger 20260620021414
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260620021414', 'oq_u5c_scorerun_throughput_metrics', 'chase@ottoyard.com');
-- @@ ledger 20260620022113
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260620022113', 'oq_u5d_benchmark_driver_helpers', 'chase@ottoyard.com');
-- @@ ledger 20260620035730
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260620035730', 'oq_u6_twin_arrival_cycle_wire', 'chase@ottoyard.com');
-- @@ ledger 20260620035757
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260620035757', 'oq_u6_advance_tick_twin_dispatch', 'chase@ottoyard.com');
-- @@ ledger 20260620040000
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260620040000', 'oq_u6_prime_deployment', 'chase@ottoyard.com');
-- @@ ledger 20260620040038
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260620040038', 'oq_u6_run_scenario_prime_call', 'chase@ottoyard.com');
-- @@ ledger 20260620040224
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260620040224', 'oq_u6_prime_event_type_and_order', 'chase@ottoyard.com');
-- @@ ledger 20260620041051
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260620041051', 'oq_u6_prime_gentle_spread', 'chase@ottoyard.com');
-- @@ ledger 20260621040000
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260621040000', 'oq_u6b_proposer_charger_aware', 'chase@ottoyard.com');
-- @@ ledger 20260621043915
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260621043915', 'oq_u6c_charger_recovery_and_highsoc_triage', 'chase@ottoyard.com');
-- @@ ledger 20260621044522
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260621044522', 'oq_u6d_wash_cadence_and_recovery_tune', 'chase@ottoyard.com');
-- @@ ledger 20260621045358
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260621045358', 'oq_u6e_realistic_charger_fault_rate', 'chase@ottoyard.com');
-- @@ ledger 20260621045902
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260621045902', 'oq_u6f_fix_charge_session_elapsed_clock', 'chase@ottoyard.com');
-- @@ ledger 20260622024815
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260622024815', 'oq_u7_energy_orchestration_seam', 'chase@ottoyard.com');
-- @@ ledger 20260622230341
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260622230341', 'oq_u7b_energy_orchestrate', 'chase@ottoyard.com');
-- @@ ledger 20260622230538
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260622230538', 'oq_u7c_advance_tick_energy_loop', 'chase@ottoyard.com');
-- @@ ledger 20260622231510
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260622231510', 'oq_u7d_decide_tick_respect_charge_cap', 'chase@ottoyard.com');
-- @@ ledger 20260622232148
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260622232148', 'oq_u7e_dispatch_respect_deploy_floor', 'chase@ottoyard.com');
-- @@ ledger 20260622235947
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260622235947', 'oq_u7f_energy_cost_for_run', 'chase@ottoyard.com');
-- @@ ledger 20260623002233
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623002233', 'oq_u8_service_manifest_generator', 'chase@ottoyard.com');
-- @@ ledger 20260623012712
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623012712', 'oq_u8b_manifest_driven_service_triage', 'chase@ottoyard.com');
-- @@ ledger 20260623013430
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623013430', 'oq_u9_charger_fault_auto_reroute', 'chase@ottoyard.com');
-- @@ ledger 20260623013859
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623013859', 'oq_u9b_faults_only_midcharge', 'chase@ottoyard.com');
-- @@ ledger 20260623015058
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623015058', 'oq_u9c_vehicle_exception_handler', 'chase@ottoyard.com');
-- @@ ledger 20260623015144
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623015144', 'oq_u9d_advance_tick_exception_handler', 'chase@ottoyard.com');
-- @@ ledger 20260623015337
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623015337', 'oq_u9c2_fix_technician_actor_type', 'chase@ottoyard.com');
-- @@ ledger 20260623015946
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623015946', 'oq_u9e_seed_fleet_clear_exception', 'chase@ottoyard.com');
-- @@ ledger 20260623020341
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623020341', 'oq_e4a_snapshot_run_attribution', 'chase@ottoyard.com');
-- @@ ledger 20260623021150
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623021150', 'oq_e4b_fix_charger_load_status_and_peak_scope', 'chase@ottoyard.com');
-- @@ ledger 20260623022120
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623022120', 'oq_e4c_initial_meter_value_on_session_start', 'chase@ottoyard.com');
-- @@ ledger 20260623024254
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623024254', 'oq_e4d_proposer_realistic_requested_kw', 'chase@ottoyard.com');
-- @@ ledger 20260623025535
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623025535', 'oq_e4e_decide_tick_committed_kw_actual_draw', 'chase@ottoyard.com');
-- @@ ledger 20260623031328
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623031328', 'oq_dn1_deploy_target_fraction', 'chase@ottoyard.com');
-- @@ ledger 20260623031422
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623031422', 'oq_dn2_decide_tick_daynight_deploy', 'chase@ottoyard.com');
-- @@ ledger 20260623031509
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623031509', 'oq_dn3_autodispatch_daynight_and_scenario_peak', 'chase@ottoyard.com');
-- @@ ledger 20260623031546
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623031546', 'oq_dn4_prime_deployment_daynight', 'chase@ottoyard.com');
-- @@ ledger 20260623032114
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623032114', 'oq_dn5_autodispatch_commute_surge_catchup', 'chase@ottoyard.com');
-- @@ ledger 20260623032743
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623032743', 'oq_s2b_overnight_service_drain', 'chase@ottoyard.com');
-- @@ ledger 20260623032809
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623032809', 'oq_s2b2_wire_overnight_drain_into_tick', 'chase@ottoyard.com');
-- @@ ledger 20260623033104
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623033104', 'oq_s2b3_drain_route_by_bay_type', 'chase@ottoyard.com');
-- @@ ledger 20260623033301
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623033301', 'oq_s2b4_drain_overnight_crew_capacity', 'chase@ottoyard.com');
-- @@ ledger 20260623185904
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623185904', 'oq_s3c_bay_fault_reroute', 'chase@ottoyard.com');
-- @@ ledger 20260623185926
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623185926', 'oq_s3c2_wire_bay_fault_into_tick', 'chase@ottoyard.com');
-- @@ ledger 20260623190505
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623190505', 'oq_p1_predictive_arrival_forecast', 'chase@ottoyard.com');
-- @@ ledger 20260623190522
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623190522', 'oq_p1b_wire_forecast_into_tick', 'chase@ottoyard.com');
-- @@ ledger 20260623191239
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260623191239', 'oq_p2_energy_orchestrate_forecast_aware_bess', 'chase@ottoyard.com');
-- @@ ledger 20260624002651
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624002651', 'oq_p3_energy_predictive_cooptimizer', 'chase@ottoyard.com');
-- @@ ledger 20260624004801
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624004801', 'oq_ai1_inloop_multiobjective_assignment', 'chase@ottoyard.com');
-- @@ ledger 20260624004822
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624004822', 'oq_ai1b_wire_optimizer_into_tick', 'chase@ottoyard.com');
-- @@ ledger 20260624005431
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624005431', 'oq_s2b6_arrival_manifest_generation', 'chase@ottoyard.com');
-- @@ ledger 20260624005452
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624005452', 'oq_s2b7_wire_arrival_manifests', 'chase@ottoyard.com');
-- @@ ledger 20260624012545
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624012545', 'oq_ai2_seam_prefer_real_cuopt', 'chase@ottoyard.com');
-- @@ ledger 20260624013351
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624013351', 'oq_ai3_cuopt_cadence_refresh', 'chase@ottoyard.com');
-- @@ ledger 20260624015137
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624015137', 'oq_ai4_cuopt_demand_driven_debounced', 'chase@ottoyard.com');
-- @@ ledger 20260624015203
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624015203', 'oq_ai4b_wire_demand_cuopt_into_tick', 'chase@ottoyard.com');
-- @@ ledger 20260624023415
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624023415', 'oq_fc0_policy_param_substrate', 'chase@ottoyard.com');
-- @@ ledger 20260624023445
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624023445', 'oq_fc0b_wire_policy_and_dryrun_guard', 'chase@ottoyard.com');
-- @@ ledger 20260624023628
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624023628', 'oq_fc1_twin_in_loop_mpc', 'chase@ottoyard.com');
-- @@ ledger 20260624025810
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624025810', 'oq_fc1b_dryrun_skip_event_logging', 'chase@ottoyard.com');
-- @@ ledger 20260624030245
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624030245', 'oq_fc1c_dryrun_shield_eval_only', 'chase@ottoyard.com');
-- @@ ledger 20260624030720
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624030720', 'oq_fc1d_general_multiobjective_mpc', 'chase@ottoyard.com');
-- @@ ledger 20260624030852
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624030852', 'oq_fc1e_wire_deploy_lever_to_policy', 'chase@ottoyard.com');
-- @@ ledger 20260624040605
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624040605', 'oq_fc_energy1_active_session_throttle', 'chase@ottoyard.com');
-- @@ ledger 20260624041712
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624041712', 'oq_fc_energy2_battery_obeys_ottoq', 'chase@ottoyard.com');
-- @@ ledger 20260624042052
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260624042052', 'oq_fc_energy3_coherent_reserve_aware_strategy', 'chase@ottoyard.com');
-- @@ ledger 20260625015253
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260625015253', 'oq_fc2_self_improving_loop', 'chase@ottoyard.com');
-- @@ ledger 20260625020308
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260625020308', 'oq_fc3_uncertainty_aware_reserve', 'chase@ottoyard.com');
-- @@ ledger 20260625021013
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260625021013', 'oq_fc4_agentic_nl_primitives', 'chase@ottoyard.com');
-- @@ ledger 20260625023122
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260625023122', 'oq_energy_ab_toggle', 'chase@ottoyard.com');
-- @@ ledger 20260626032711
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260626032711', 'oq_fc_energy4_charge_freeze_fix', 'chase@ottoyard.com');
-- @@ ledger 20260626033929
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260626033929', 'oq_fc_energy5_demand_aware_bess_recharge', 'chase@ottoyard.com');
-- @@ ledger 20260626035152
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260626035152', 'oq_fc_energy6_snapshot_after_charge', 'chase@ottoyard.com');
-- @@ ledger 20260626035308
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260626035308', 'oq_fc_energy7_throttle_exact_desired', 'chase@ottoyard.com');
-- @@ ledger 20260626040749
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260626040749', 'oq_fc_energy8_zero_initial_meter', 'chase@ottoyard.com');
-- @@ ledger 20260626222022
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260626222022', 'oq_twin_v1_lifespan_map', 'chase@ottoyard.com');
-- @@ ledger 20260627025059
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627025059', 'oq_twin_v1b_deal_engine', 'chase@ottoyard.com');
-- @@ ledger 20260627032248
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627032248', 'oq_twin_v1c_latent_fault_cards', 'chase@ottoyard.com');
-- @@ ledger 20260627033836
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627033836', 'oq_twin_v1d_eta_disruption', 'chase@ottoyard.com');
-- @@ ledger 20260627034656
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627034656', 'oq_twin_v1e_scenario_decks', 'chase@ottoyard.com');
-- @@ ledger 20260627041633
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627041633', 'oq_twin_v1f_refit_distribution', 'chase@ottoyard.com');
-- @@ ledger 20260627042109
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627042109', 'oq_twin_v1f_live_rotation_cron', 'chase@ottoyard.com');
-- @@ ledger 20260627153737
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627153737', 'oq_twin_v1g_weather_daily_regime', 'chase@ottoyard.com');
-- @@ ledger 20260627154144
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627154144', 'oq_twin_v1g_grid_daily_regime', 'chase@ottoyard.com');
-- @@ ledger 20260627155037
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627155037', 'oq_twin_v1h_correlation_web', 'chase@ottoyard.com');
-- @@ ledger 20260627161626
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627161626', 'oq_pillar2_comms_lines', 'chase@ottoyard.com');
-- @@ ledger 20260627163208
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627163208', 'oq_pillar2_comms_live_wire', 'chase@ottoyard.com');
-- @@ ledger 20260627174900
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627174900', 'oq_energy_grid_hourly_shape_accessor_fix', 'chase@ottoyard.com');
-- @@ ledger 20260627181904
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627181904', 'oq_pillar2_teleop_human_loop', 'chase@ottoyard.com');
-- @@ ledger 20260627184544
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627184544', 'oq_pillar2_agent_comms_bridge', 'chase@ottoyard.com');
-- @@ ledger 20260627190625
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627190625', 'oq_twin_v2_precip_weather_eta_coupling', 'chase@ottoyard.com');
-- @@ ledger 20260627202213
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627202213', 'oq_twin_v2b_eta_dayfix_incident_weather', 'chase@ottoyard.com');
-- @@ ledger 20260627202422
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627202422', 'oq_twin_v2c_arrival_soc_weather_drain', 'chase@ottoyard.com');
-- @@ ledger 20260627205030
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627205030', 'oq_twin_v2d_weather_block_carding', 'chase@ottoyard.com');
-- @@ ledger 20260627205220
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627205220', 'oq_twin_deal_uniform_bucket_crn_fix', 'chase@ottoyard.com');
-- @@ ledger 20260627210127
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260627210127', 'oq_twin_v2e_service_duration_per_visit', 'chase@ottoyard.com');
-- @@ ledger 20260628211653
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260628211653', 'twin_sparse_start_randomized_arrivals', 'chase@ottoyard.com');
-- @@ ledger 20260701024428
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260701024428', 'cron_tick_commit_wave_admit', 'chase@ottoyard.com');
-- @@ ledger 20260701033645
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260701033645', 'l2_propose_spatial_nearest_wash', 'chase@ottoyard.com');
-- @@ ledger 20260702023154
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260702023154', 'decide_tick_congestion_staging_fallback', 'chase@ottoyard.com');
-- @@ ledger 20260702023225
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260702023225', 'exception_handler_tow_retrieval_staging', 'chase@ottoyard.com');
-- @@ ledger 20260707172311
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260707172311', 'cuopt_tightening_shadow_debounce_sweep', 'chase@ottoyard.com');
-- @@ ledger 20260708020603
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260708020603', 'fix_run_list_timeout_and_start_supersede', 'chase@ottoyard.com');
-- @@ ledger 20260708023331
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260708023331', 'run_list_true_scan_bounds', 'chase@ottoyard.com');
-- @@ ledger 20260708030006
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260708030006', 'run_list_v4_recent_counters_only', 'chase@ottoyard.com');
-- @@ ledger 20260708031917
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260708031917', 'raise_service_role_statement_timeout', 'chase@ottoyard.com');
-- @@ ledger 20260708185631
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260708185631', 'retention_mode_and_background_purge', 'chase@ottoyard.com');
-- @@ ledger 20260709002945
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709002945', 'itinerary_contract_b1_and_janitor_v2', 'chase@ottoyard.com');
-- @@ ledger 20260709004808
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709004808', 'retention_worker_table_scoping', 'chase@ottoyard.com');
-- @@ ledger 20260709005508
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709005508', 'retention_worker_block_cursor', 'chase@ottoyard.com');
-- @@ ledger 20260709021620
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709021620', 'itinerary_b2_leg_emission', 'chase@ottoyard.com');
-- @@ ledger 20260709021715
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709021715', 'itinerary_b2_service_legs', 'chase@ottoyard.com');
-- @@ ledger 20260709021945
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709021945', 'itinerary_b2_subtick_service_close', 'chase@ottoyard.com');
-- @@ ledger 20260709175531
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709175531', 'feed_agent_substrate_and_charger_reliability', 'chase@ottoyard.com');
-- @@ ledger 20260709175613
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709175613', 'feed_agent_repair_payload_wiring', 'chase@ottoyard.com');
-- @@ ledger 20260709182843
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709182843', 'tariff_agent_v1_real_nes_rates', 'chase@ottoyard.com');
-- @@ ledger 20260709185132
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709185132', 'lmp_agent_v1_miso_calibrated', 'chase@ottoyard.com');
-- @@ ledger 20260709222020
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260709222020', 'temperature_agent_v1_noaa_normals', 'chase@ottoyard.com');
-- @@ ledger 20260710010417
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710010417', 'rain_agent_v1_unified_ghcn', 'chase@ottoyard.com');
-- @@ ledger 20260710011523
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710011523', 'service_manifest_agent_v1_pervisit', 'chase@ottoyard.com');
-- @@ ledger 20260710040609
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710040609', 'vehicle_first_n1_no_defer_bess_plan', 'chase@ottoyard.com');
-- @@ ledger 20260710123746
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710123746', 'vehicle_first_n1b_bess_plan_horizon_35min', 'chase@ottoyard.com');
-- @@ ledger 20260710214730
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710214730', 'needs_contract_m1_table_roles_generator_v3', 'chase@ottoyard.com');
-- @@ ledger 20260710215823
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710215823', 'needs_contract_m2_sequencer_concurrency', 'chase@ottoyard.com');
-- @@ ledger 20260710220626
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710220626', 'needs_contract_m2b_atom_start_retry', 'chase@ottoyard.com');
-- @@ ledger 20260710221929
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710221929', 'needs_contract_m3a_table_triage_atoms', 'chase@ottoyard.com');
-- @@ ledger 20260710222610
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710222610', 'needs_contract_m3b_opportunistic_scan', 'chase@ottoyard.com');
-- @@ ledger 20260710222645
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710222645', 'needs_contract_m3c_gates_wiring_reset', 'chase@ottoyard.com');
-- @@ ledger 20260710223034
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260710223034', 'needs_contract_m3d_scan_tick_granularity', 'chase@ottoyard.com');
-- @@ ledger 20260711015432
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711015432', 'needs_contract_m4_flow_contract', 'chase@ottoyard.com');
-- @@ ledger 20260711015829
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711015829', 'needs_contract_m4b_hotfix_leg_vocabulary', 'chase@ottoyard.com');
-- @@ ledger 20260711020157
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711020157', 'needs_contract_m4c_atom_legs_amend_guard', 'chase@ottoyard.com');
-- @@ ledger 20260711022507
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711022507', 'n3_prearrival_cuopt_revival_assignment', 'chase@ottoyard.com');
-- @@ ledger 20260711022636
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711022636', 'n3b_hotfix_prearrival_enum_cast', 'chase@ottoyard.com');
-- @@ ledger 20260711025129
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711025129', 'n4_agent_board_digest', 'chase@ottoyard.com');
-- @@ ledger 20260711025422
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711025422', 'n4b_board_volatile', 'chase@ottoyard.com');
-- @@ ledger 20260711140201
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711140201', 'n4_command_seam_dual_write', 'chase@ottoyard.com');
-- @@ ledger 20260711141232
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711141232', 'arrival_realism_95_init_scatter', 'chase@ottoyard.com');
-- @@ ledger 20260711144612
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711144612', 'b15_calibrated_charge_curves', 'chase@ottoyard.com');
-- @@ ledger 20260711155440
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260711155440', 'benchmark_reset_zombie_self_heal', 'chase@ottoyard.com');
-- @@ ledger 20260712220724
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260712220724', 'demo_metronome_server_side_world_clock', 'chase@ottoyard.com');
-- @@ ledger 20260712224915
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260712224915', 'metronome_lock_timeout_hardening', 'chase@ottoyard.com');
-- @@ ledger 20260714025646
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714025646', 'defuse_01_split_sim_advance_tick', 'chase@ottoyard.com');
-- @@ ledger 20260714030126
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714030126', 'defuse_02_metronome_split_path', 'chase@ottoyard.com');
-- @@ ledger 20260714032006
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714032006', 'seam_01_api_contract_facades', 'chase@ottoyard.com');
-- @@ ledger 20260714032218
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714032218', 'seam_01b_fix_facade_search_path', 'chase@ottoyard.com');
-- @@ ledger 20260714041853
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714041853', 'nvidia_01_decision_provenance', 'chase@ottoyard.com');
-- @@ ledger 20260714042124
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714042124', 'nvidia_02_fix_nemotron_policy_lever', 'chase@ottoyard.com');
-- @@ ledger 20260714124321
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714124321', 'shield_01_en001_actual_demand', 'chase@ottoyard.com');
-- @@ ledger 20260714124545
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714124545', 'shield_02_cuopt_freshness_guard', 'chase@ottoyard.com');
-- @@ ledger 20260714132537
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714132537', 'fid_a_run_scope_charger_load', 'chase@ottoyard.com');
-- @@ ledger 20260714132747
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714132747', 'fid_b_load_responsive_brownout', 'chase@ottoyard.com');
-- @@ ledger 20260714191922
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714191922', 'cert_01_symmetric_dispatch_execution', 'chase@ottoyard.com');
-- @@ ledger 20260714221111
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714221111', 'cert_02_bess_shave_no_throttle', 'chase@ottoyard.com');
-- @@ ledger 20260714232943
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260714232943', 'cert_03_bess_recharge_valley_only', 'chase@ottoyard.com');
-- @@ ledger 20260715044428
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715044428', 'fr1_energy_plan_table_and_replan', 'chase@ottoyard.com');
-- @@ ledger 20260715044716
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715044716', 'fr1_replan_fire_and_ingest', 'chase@ottoyard.com');
-- @@ ledger 20260715044947
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715044947', 'fr1_orchestrate_follow_mpc_plan', 'chase@ottoyard.com');
-- @@ ledger 20260715051450
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715051450', 'fr1_cert_arm_and_replan_anchor', 'chase@ottoyard.com');
-- @@ ledger 20260715053131
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715053131', 'fr1_replan_forecast_from_run', 'chase@ottoyard.com');
-- @@ ledger 20260715054024
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715054024', 'fr1_reactive_baseline_analysis', 'chase@ottoyard.com');
-- @@ ledger 20260715055057
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715055057', 'fix_score_run_energy_peak_run_scoped', 'chase@ottoyard.com');
-- @@ ledger 20260715135236
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715135236', 'fr1b_bess_reserve_target', 'chase@ottoyard.com');
-- @@ ledger 20260715135347
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715135347', 'fr1b_orchestrate_reserve_shave', 'chase@ottoyard.com');
-- @@ ledger 20260715142331
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715142331', 'fr1b_cumulative_load_forecaster', 'chase@ottoyard.com');
-- @@ ledger 20260715152907
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715152907', 'safety_cert_drained_fleet_arm', 'chase@ottoyard.com');
-- @@ ledger 20260715170813
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715170813', 'demo_nemotron_advisory_conductor', 'chase@ottoyard.com');
-- @@ ledger 20260715174932
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715174932', 'demo_speed_control_paced_metronome', 'chase@ottoyard.com');
-- @@ ledger 20260715175152
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715175152', 'expose_demo_speed_in_state_feed', 'chase@ottoyard.com');
-- @@ ledger 20260715175348
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715175348', 'fix_metronome_pacing_from_now', 'chase@ottoyard.com');
-- @@ ledger 20260715180223
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715180223', 'fix_metronome_clock_timestamp_pacing', 'chase@ottoyard.com');
-- @@ ledger 20260715185657
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260715185657', 'demo_start_persistent_run_control', 'chase@ottoyard.com');
-- @@ ledger 20260716223610
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260716223610', 'metronome_idle_exit_and_budget_guard', 'chase@ottoyard.com');
-- @@ ledger 20260716231434
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260716231434', 'ottoq_vehicle_cards_read_endpoints', 'chase@ottoyard.com');
-- @@ ledger 20260717174427
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717174427', 'fr3_cuopt_solve_window_params_and_debounce', 'chase@ottoyard.com');
-- @@ ledger 20260717174456
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717174456', 'fr3_metronome_cuopt_solve_window', 'chase@ottoyard.com');
-- @@ ledger 20260717174741
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717174741', 'fr4_ops_action_dispatcher', 'chase@ottoyard.com');
-- @@ ledger 20260717174840
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717174840', 'fr4_orchestrator_event_trigger', 'chase@ottoyard.com');
-- @@ ledger 20260717175237
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717175237', 'fr3_metronome_deterministic_poll_window', 'chase@ottoyard.com');
-- @@ ledger 20260717175314
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717175314', 'fr3_milp_local_yields_to_cuopt', 'chase@ottoyard.com');
-- @@ ledger 20260717180008
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717180008', 'fr4_wire_event_trigger_into_decide', 'chase@ottoyard.com');
-- @@ ledger 20260717215905
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717215905', 'deploy_pressure_defer_optional_wash', 'chase@ottoyard.com');
-- @@ ledger 20260717220620
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717220620', 'recharge_stranded_underfloor_vehicles', 'chase@ottoyard.com');
-- @@ ledger 20260717222229
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717222229', 'deploy_target_depot_scoped_fleet', 'chase@ottoyard.com');
-- @@ ledger 20260717223041
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260717223041', 'selfheal_null_timer_bay_deadlock', 'chase@ottoyard.com');
-- @@ ledger 20260718000029
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718000029', 'blackbox_run_export_engine', 'chase@ottoyard.com');
-- @@ ledger 20260718000349
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718000349', 'blackbox_stop_reset_and_purge', 'chase@ottoyard.com');
-- @@ ledger 20260718014856
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718014856', 'blackbox_start_single_live_run_guarantee', 'chase@ottoyard.com');
-- @@ ledger 20260718015744
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718015744', 'blackbox_latest_run_discovery_rpc', 'chase@ottoyard.com');
-- @@ ledger 20260718033120
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718033120', 'twin_snapshot_scope_fleet_to_run_depot', 'chase@ottoyard.com');
-- @@ ledger 20260718033328
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718033328', 'stop_reset_backfill_run_counters', 'chase@ottoyard.com');
-- @@ ledger 20260718044835
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718044835', 'svc_L1_invert_seed_fleet_mostly_deployed', 'chase@ottoyard.com');
-- @@ ledger 20260718045317
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718045317', 'svc_L5_deploy_operating_curve_and_targeted_seed', 'chase@ottoyard.com');
-- @@ ledger 20260718045819
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718045819', 'svc_L5_aggressive_redeploy_pull', 'chase@ottoyard.com');
-- @@ ledger 20260718050224
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718050224', 'svc_demo_daytime_simclock_start', 'chase@ottoyard.com');
-- @@ ledger 20260718051655
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718051655', 'ai_A1_A3_extend_proposal_seam_redeploy_service', 'chase@ottoyard.com');
-- @@ ledger 20260718053809
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718053809', 'ai_A5prod_unify_production_brain', 'chase@ottoyard.com');
-- @@ ledger 20260718234156
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260718234156', 'ai_A2_service_sequencing_priority_proposer', 'chase@ottoyard.com');
-- @@ ledger 20260719004539
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719004539', 'gate_pileup_rebalance_seed_cohort', 'chase@ottoyard.com');
-- @@ ledger 20260719020500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719020500', 'gate_disposition_no_limbo', 'chase@ottoyard.com');
-- @@ ledger 20260719160241
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719160241', 'breach_counter_real_metered_dcfc_draw', 'chase@ottoyard.com');
-- @@ ledger 20260719200004
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719200004', 'history_based_run_certification', 'chase@ottoyard.com');
-- @@ ledger 20260719200211
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719200211', 'dispatch_completed_requires_return_trigger', 'chase@ottoyard.com');
-- @@ ledger 20260719204305
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719204305', 'stop_and_reset_records_run_stopped_trigger', 'chase@ottoyard.com');
-- @@ ledger 20260719204548
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719204548', 'metronome_hard_tick_ceiling_backstop', 'chase@ottoyard.com');
-- @@ ledger 20260719224416
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719224416', 'charger_state_self_healing_reconciler', 'chase@ottoyard.com');
-- @@ ledger 20260719224522
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719224522', 'wire_charger_reconciler_into_both_ticks', 'chase@ottoyard.com');
-- @@ ledger 20260719224632
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719224632', 'admit_stranded_offline_vehicles', 'chase@ottoyard.com');
-- @@ ledger 20260719225520
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719225520', 'stop_charge_session_idempotent_resource_release', 'chase@ottoyard.com');
-- @@ ledger 20260719225652
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719225652', 'capacity_gated_admission_wired_into_tick', 'chase@ottoyard.com');
-- @@ ledger 20260719230756
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719230756', 'seed_fleet_operator_slas_and_effective_target', 'chase@ottoyard.com');
-- @@ ledger 20260719231023
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719231023', 'stop_and_reset_releases_chargers', 'chase@ottoyard.com');
-- @@ ledger 20260719232701
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719232701', 'release_visit_artifacts_on_redeploy', 'chase@ottoyard.com');
-- @@ ledger 20260719233028
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719233028', 'metronome_fences_cert_harness_runs', 'chase@ottoyard.com');
-- @@ ledger 20260719233455
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260719233455', 'suppress_parked_reevaluation_churn', 'chase@ottoyard.com');
-- @@ ledger 20260720000912
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720000912', 'sim_clock_pinned_soc_resolvers', 'chase@ottoyard.com');
-- @@ ledger 20260720001048
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720001048', 'arrival_decoupling_substrate', 'chase@ottoyard.com');
-- @@ ledger 20260720002956
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720002956', 'arrival_decoupled_from_return_timer', 'chase@ottoyard.com');
-- @@ ledger 20260720010039
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720010039', 'ap2_wear_substrate_table_and_helpers', 'chase@ottoyard.com');
-- @@ ledger 20260720010137
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720010137', 'ap2_wear_advancer', 'chase@ottoyard.com');
-- @@ ledger 20260720010330
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720010330', 'ap2_wire_wear_advancer_into_tick', 'chase@ottoyard.com');
-- @@ ledger 20260720011506
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720011506', 'rls_on_wear_substrate_tables', 'chase@ottoyard.com');
-- @@ ledger 20260720020807
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720020807', 'delete_fabricated_vehicle_comms_provenance', 'chase@ottoyard.com');
-- @@ ledger 20260720221138
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720221138', 'honest_optimizer_engine_label', 'chase@ottoyard.com');
-- @@ ledger 20260720221507
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720221507', 'ocpp_align_to_16j', 'chase@ottoyard.com');
-- @@ ledger 20260720221739
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720221739', 'cuopt_attribution_carry_source_into_proposal', 'chase@ottoyard.com');
-- @@ ledger 20260720222916
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720222916', 'wire1_webhook_live_delivery_schema', 'chase@ottoyard.com');
-- @@ ledger 20260720222950
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720222950', 'wire1_webhook_live_delivery_functions', 'chase@ottoyard.com');
-- @@ ledger 20260720223227
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720223227', 'wire1_webhook_delivery_status_add_sent', 'chase@ottoyard.com');
-- @@ ledger 20260720223445
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720223445', 'wire1_route_emit_live_vs_simulated', 'chase@ottoyard.com');
-- @@ ledger 20260720224112
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720224112', 'wire1_autoreconcile_webhook_responses_in_tick', 'chase@ottoyard.com');
-- @@ ledger 20260720224208
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720224208', 'wire1_autoreconcile_webhook_in_production_tick', 'chase@ottoyard.com');
-- @@ ledger 20260720224542
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720224542', 'ap3_seed_return_trigger_thresholds_depot', 'chase@ottoyard.com');
-- @@ ledger 20260720224805
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720224805', 'ap3_evaluate_return_need', 'chase@ottoyard.com');
-- @@ ledger 20260720230741
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720230741', 'ap3_cutover_return_trigger_to_evaluator', 'chase@ottoyard.com');
-- @@ ledger 20260720232853
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720232853', 'ap4_book_appointment_handshake', 'chase@ottoyard.com');
-- @@ ledger 20260720232957
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720232957', 'ap4_advancer_book_at_needfire', 'chase@ottoyard.com');
-- @@ ledger 20260720233630
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720233630', 'ap4_prearrival_backstop_m1', 'chase@ottoyard.com');
-- @@ ledger 20260720234306
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260720234306', 'ap5_honour_reservation_helper', 'chase@ottoyard.com');
-- @@ ledger 20260721013234
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260721013234', 'ap7_holdout_helper_and_trough', 'chase@ottoyard.com');
-- @@ ledger 20260721013355
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260721013355', 'ap7_evaluate_return_need_holdout_straggler', 'chase@ottoyard.com');
-- @@ ledger 20260721013542
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260721013542', 'ap7_surplus_recall_in_homeostat', 'chase@ottoyard.com');
-- @@ ledger 20260721020345
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260721020345', 'ap7b_overnight_drain_fix', 'chase@ottoyard.com');
-- @@ ledger 20260721020502
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260721020502', 'ap7b_production_loop_parity', 'chase@ottoyard.com');
-- @@ ledger 20260721030219
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260721030219', 'ap7b_world_advance_gate_holding_parity', 'chase@ottoyard.com');
-- @@ ledger 20260721123500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260721123500', 'ap6_twin_appointments_read_rpc', 'chase@ottoyard.com');
-- @@ ledger 20260722001110
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260722001110', 'montecarlo_fresh_seed_per_run', 'chase@ottoyard.com');
-- @@ ledger 20260722001643
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260722001643', 'bounded_demo_default_days_1', 'chase@ottoyard.com');
-- @@ ledger 20260722215253
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260722215253', 'vehicle_condition_cards_boot_draw', 'chase@ottoyard.com');
-- @@ ledger 20260722215512
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260722215512', 'veh_condition_consumers_wired', 'chase@ottoyard.com');
-- @@ ledger 20260722215735
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260722215735', 'manifest_v4_condition_coherent', 'chase@ottoyard.com');
-- @@ ledger 20260722215905
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260722215905', 'fix_search_path_extensions', 'chase@ottoyard.com');
-- @@ ledger 20260722233605
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260722233605', 'orch1_timed_workflow_plan', 'chase@ottoyard.com');
-- @@ ledger 20260723010100
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723010100', 'orch2_rush_valve_orch1b_replan', 'chase@ottoyard.com');
-- @@ ledger 20260723010308
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723010308', 'rush_valve_actor_type_fix', 'chase@ottoyard.com');
-- @@ ledger 20260723010414
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723010414', 'rush_valve_data_source_fix', 'chase@ottoyard.com');
-- @@ ledger 20260723010907
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723010907', 'register_rush_valve_policies', 'chase@ottoyard.com');
-- @@ ledger 20260723013452
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723013452', 'adversarial_review_tier1_fixes', 'chase@ottoyard.com');
-- @@ ledger 20260723013548
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723013548', 'guard_telemetry_booking_call', 'chase@ottoyard.com');
-- @@ ledger 20260723123121
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723123121', 'crn_seed_from_random_seed', 'chase@ottoyard.com');
-- @@ ledger 20260723123553
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723123553', 'crn_seed_prime_deployment', 'chase@ottoyard.com');
-- @@ ledger 20260723123909
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723123909', 'revert_prime_crn_seed', 'chase@ottoyard.com');
-- @@ ledger 20260723125401
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723125401', 'run_scenario_receipts_seed_prime', 'chase@ottoyard.com');
-- @@ ledger 20260723125608
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723125608', 'seed_fleet_abort_stale_dispatches', 'chase@ottoyard.com');
-- @@ ledger 20260723125747
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723125747', 'crn_seed_prime_deployment_v2', 'chase@ottoyard.com');
-- @@ ledger 20260723130734
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723130734', 'ingest_vehicle_signal_rpc', 'chase@ottoyard.com');
-- @@ ledger 20260723131355
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723131355', 'crn_seed_emit_telemetry', 'chase@ottoyard.com');
-- @@ ledger 20260723131510
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723131510', 'crn_seed_stragglers_energy_assign_session', 'chase@ottoyard.com');
-- @@ ledger 20260723181232
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723181232', 'depot_feed_mode_switch', 'chase@ottoyard.com');
-- @@ ledger 20260723181547
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723181547', 'feed_mode_gate_world_advance', 'chase@ottoyard.com');
-- @@ ledger 20260723181608
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723181608', 'feed_mode_gate_demotick_injectors', 'chase@ottoyard.com');
-- @@ ledger 20260723182145
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723182145', 'oem_outbound_command_seam', 'chase@ottoyard.com');
-- @@ ledger 20260723185544
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723185544', 'ingest_provenance_columns', 'chase@ottoyard.com');
-- @@ ledger 20260723190808
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723190808', 'service_flow_external_completion_split', 'chase@ottoyard.com');
-- @@ ledger 20260723190834
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723190834', 'ingest_service_complete_rpc', 'chase@ottoyard.com');
-- @@ ledger 20260723191000
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260723191000', 'gate_overnight_drain_external', 'chase@ottoyard.com');
-- @@ ledger 20260724015340
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724015340', 'cutover_atoms_triage_manifest_external', 'chase@ottoyard.com');
-- @@ ledger 20260724025412
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724025412', 'cert_battery_queue_runner', 'chase@ottoyard.com');
-- @@ ledger 20260724025446
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724025446', 'cert_arm_wave_scarcity', 'chase@ottoyard.com');
-- @@ ledger 20260724025538
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724025538', 'service_complete_matched_count', 'chase@ottoyard.com');
-- @@ ledger 20260724025705
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724025705', 'orch3_inbound_forecast_surface', 'chase@ottoyard.com');
-- @@ ledger 20260724030421
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724030421', 'wave_fault_order_l2_first_and_sweep_enqueue', 'chase@ottoyard.com');
-- @@ ledger 20260724033238
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724033238', 'wave_v2_end_of_shift_soc', 'chase@ottoyard.com');
-- @@ ledger 20260724124510
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724124510', 'score_run_cumulative_metrics_v2', 'chase@ottoyard.com');
-- @@ ledger 20260724124604
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724124604', 'orch3_forecast_into_decide_tick', 'chase@ottoyard.com');
-- @@ ledger 20260724130013
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724130013', 'proposal_lifecycle_honest_attribution', 'chase@ottoyard.com');
-- @@ ledger 20260724172907
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724172907', 'reservation_book_reoptimizer', 'chase@ottoyard.com');
-- @@ ledger 20260724175156
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724175156', 'indepot_reassignment_gate_and_reopt_timing_v2', 'chase@ottoyard.com');
-- @@ ledger 20260724175231
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260724175231', 'approvals_allow_indepot_reassign', 'chase@ottoyard.com');
-- @@ ledger 20260725014242
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725014242', 'reopt_widen_cuopt_claim_window', 'chase@ottoyard.com');
-- @@ ledger 20260725014951
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725014951', 'cuopt_refresh_trigger_enroute_cohort', 'chase@ottoyard.com');
-- @@ ledger 20260725031256
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725031256', 'overnight_wave_scheduler_phase1', 'chase@ottoyard.com');
-- @@ ledger 20260725032655
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725032655', 'wave_capex_feasibility_cert', 'chase@ottoyard.com');
-- @@ ledger 20260725134100
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725134100', 'wave_capex_cert_v2_partial_charge', 'chase@ottoyard.com');
-- @@ ledger 20260725134225
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725134225', 'wave_capex_cert_v2_clean_fix', 'chase@ottoyard.com');
-- @@ ledger 20260725173627
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725173627', 'depot_capacity_sizing_model', 'chase@ottoyard.com');
-- @@ ledger 20260725180533
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725180533', 'depot_capacity_v2_parallel_service', 'chase@ottoyard.com');
-- @@ ledger 20260725183333
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725183333', 'depot_capacity_v3_zone_techs', 'chase@ottoyard.com');
-- @@ ledger 20260725191359
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725191359', 'charge_time_integrator_and_mix_model', 'chase@ottoyard.com');
-- @@ ledger 20260725200337
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725200337', 'charge_policy_chemistry_and_charger_fault_requeue', 'chase@ottoyard.com');
-- @@ ledger 20260725200458
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725200458', 'fix_nmc_balance_charge_tracking', 'chase@ottoyard.com');
-- @@ ledger 20260725202007
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725202007', 'wire_balance_charge_stamp_on_completion', 'chase@ottoyard.com');
-- @@ ledger 20260725202537
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725202537', 'wire_charge_policy_into_booking', 'chase@ottoyard.com');
-- @@ ledger 20260725202754
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725202754', 'charge_plan_reason_honesty_on_override', 'chase@ottoyard.com');
-- @@ ledger 20260725203047
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725203047', 'sla004_enforce_visit_manifest_and_charge_target', 'chase@ottoyard.com');
-- @@ ledger 20260725203136
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725203136', 'sla004_fix_visit_needs_pk_column', 'chase@ottoyard.com');
-- @@ ledger 20260725203301
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725203301', 'booking_stamps_charge_target_onto_manifest_atom', 'chase@ottoyard.com');
-- @@ ledger 20260725203351
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725203351', 'sla004_supervisor_override_valve', 'chase@ottoyard.com');
-- @@ ledger 20260725203749
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725203749', 'idx_visit_needs_open_by_vehicle', 'chase@ottoyard.com');
-- @@ ledger 20260725221425
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725221425', 'revised_service_mechanics_m1_m2_m3_m5', 'chase@ottoyard.com');
-- @@ ledger 20260725221516
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725221516', 'wash_rotation_balanced_groups', 'chase@ottoyard.com');
-- @@ ledger 20260725222020
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725222020', 'fix_charger_load_enum_cast_defeating_index', 'chase@ottoyard.com');
-- @@ ledger 20260725222059
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725222059', 'fix_remaining_ocpp_status_cast_index_defeats', 'chase@ottoyard.com');
-- @@ ledger 20260725222337
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260725222337', 'wash_rotation_demote_cycle_backstop', 'chase@ottoyard.com');
-- @@ ledger 20260726011111
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726011111', 'service_flow_durations_to_founder_spec', 'chase@ottoyard.com');
-- @@ ledger 20260726011224
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726011224', 'staffing_role_pools_founder_spec', 'chase@ottoyard.com');
-- @@ ledger 20260726011251
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726011251', 'wire_staffing_pools_into_gates', 'chase@ottoyard.com');
-- @@ ledger 20260726011402
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726011402', 'soil_decay_tick_size_invariant', 'chase@ottoyard.com');
-- @@ ledger 20260726011603
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726011603', 'fix_production_tick_minutes_15x_disagreement', 'chase@ottoyard.com');
-- @@ ledger 20260726011915
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726011915', 'restore_decide_and_dispatch_after_bad_drop', 'chase@ottoyard.com');
-- @@ ledger 20260726012046
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726012046', 'replay_post_0718_splices_onto_decide_and_dispatch', 'chase@ottoyard.com');
-- @@ ledger 20260726012218
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726012218', 'fix_15x_tick_minutes_via_run_payload', 'chase@ottoyard.com');
-- @@ ledger 20260726015716
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726015716', 'playback_clock_live_mode_and_speed', 'chase@ottoyard.com');
-- @@ ledger 20260726015838
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726015838', 'jump_forward_with_planning_pause_v2', 'chase@ottoyard.com');
-- @@ ledger 20260726021707
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726021707', 'tick_size_invariance_harness_v2', 'chase@ottoyard.com');
-- @@ ledger 20260726021836
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726021836', 'invariance_arm_release_depot_on_finish', 'chase@ottoyard.com');
-- @@ ledger 20260726022225
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726022225', 'invariance_arm_primed_fleet_start', 'chase@ottoyard.com');
-- @@ ledger 20260726022516
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726022516', 'invariance_arm_deterministic_fleet_reset', 'chase@ottoyard.com');
-- @@ ledger 20260726023321
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726023321', 'return_need_thresholds_ticks_to_minutes', 'chase@ottoyard.com');
-- @@ ledger 20260726031038
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726031038', 'deploy_cap_per_minute_not_per_tick', 'chase@ottoyard.com');
-- @@ ledger 20260726035405
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726035405', 'fix_wait_estimate_units_tick_invariant', 'chase@ottoyard.com');
-- @@ ledger 20260726040337
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726040337', 'overnight_recall_cap_per_minute_v2', 'chase@ottoyard.com');
-- @@ ledger 20260726042716
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726042716', 'fence_invariance_arms_from_metronome', 'chase@ottoyard.com');
-- @@ ledger 20260726043932
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726043932', 'invariance_metrics_normalised_ratios', 'chase@ottoyard.com');
-- @@ ledger 20260726044312
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726044312', 'snapshot_publishes_playback_state_v2', 'chase@ottoyard.com');
-- @@ ledger 20260726153706
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726153706', 'enforce_one_active_charge_session_per_stall', 'chase@ottoyard.com');
-- @@ ledger 20260726153739
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726153739', 'fix_baseline_charge_assigner_phantom_capacity', 'chase@ottoyard.com');
-- @@ ledger 20260726153921
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726153921', 'seed_fleet_drop_phantom_in_progress_label_both_overloads', 'chase@ottoyard.com');
-- @@ ledger 20260726154125
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726154125', 'cert_arm_chunkable_start_step_finish', 'chase@ottoyard.com');
-- @@ ledger 20260726155911
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726155911', 'score_run_scope_charge_sessions_to_run', 'chase@ottoyard.com');
-- @@ ledger 20260726204612
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726204612', 'drop_never_scanned_ottoq_events_indexes', 'chase@ottoyard.com');
-- @@ ledger 20260726222428
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726222428', 'fix_deploy_leak_align_gates_and_sweep_stranded', 'chase@ottoyard.com');
-- @@ ledger 20260726222453
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726222453', 'wire_stranded_deploy_sweep_into_tick', 'chase@ottoyard.com');
-- @@ ledger 20260726222647
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726222647', 'bess_default_add_demand_limiting_to_baseline', 'chase@ottoyard.com');
-- @@ ledger 20260726222715
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726222715', 'score_run_productive_deploys_require_dispatch', 'chase@ottoyard.com');
-- @@ ledger 20260726223452
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260726223452', 'decide_tick_stop_mutating_vehicle_state_brain_twin_separation', 'chase@ottoyard.com');
-- @@ ledger 20260727011750
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727011750', 'twin_honours_brain_deploy_choice', 'chase@ottoyard.com');
-- @@ ledger 20260727013900
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727013900', 'clock_fidelity_measure_real_vs_sim_ratio', 'chase@ottoyard.com');
-- @@ ledger 20260727014024
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727014024', 'tick_clock_log_authoritative_realtime_instrument', 'chase@ottoyard.com');
-- @@ ledger 20260727014118
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727014118', 'clock_fidelity_v2_on_authoritative_log', 'chase@ottoyard.com');
-- @@ ledger 20260727014328
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727014328', 'clock_fidelity_fix_percentile_numeric_cast', 'chase@ottoyard.com');
-- @@ ledger 20260727014430
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727014430', 'fix_live_clock_frozen_now_and_coarse_floor', 'chase@ottoyard.com');
-- @@ ledger 20260727014602
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727014602', 'fix_tick_stamp_clock_timestamp_not_now', 'chase@ottoyard.com');
-- @@ ledger 20260727014804
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727014804', 'live_clock_anchor_at_tick_start_not_end', 'chase@ottoyard.com');
-- @@ ledger 20260727015229
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727015229', 't2_metronome_paces_off_playback_speed_single_clock', 'chase@ottoyard.com');
-- @@ ledger 20260727015407
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727015407', 't5_snapshot_publishes_measured_clock_ratio', 'chase@ottoyard.com');
-- @@ ledger 20260727015447
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727015447', 't6_assert_playback_never_reaches_decisions', 'chase@ottoyard.com');
-- @@ ledger 20260727022643
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727022643', 't3_travel_leg_emitter', 'chase@ottoyard.com');
-- @@ ledger 20260727022747
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727022747', 't3_wire_travel_legs_arrival_and_departure', 'chase@ottoyard.com');
-- @@ ledger 20260727023139
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727023139', 't3_travel_leg_fix_check_constraint_values', 'chase@ottoyard.com');
-- @@ ledger 20260727023239
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727023239', 't3_travel_leg_resolve_itinerary_and_seq', 'chase@ottoyard.com');
-- @@ ledger 20260727023507
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727023507', 't3_travel_leg_reject_degenerate_origin', 'chase@ottoyard.com');
-- @@ ledger 20260727023954
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727023954', 't3_travel_leg_resolve_true_origin_from_history', 'chase@ottoyard.com');
-- @@ ledger 20260727024301
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727024301', 't3_snapshot_exposes_active_legs_render_contract', 'chase@ottoyard.com');
-- @@ ledger 20260727031515
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727031515', 'fix_travel_leg_scale_feet_and_load_bay_coords', 'chase@ottoyard.com');
-- @@ ledger 20260727031629
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727031629', 't3_wire_wash_and_service_entry_travel_legs', 'chase@ottoyard.com');
-- @@ ledger 20260727033423
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727033423', 't3_wire_bay_exit_travel_legs_wash_and_service', 'chase@ottoyard.com');
-- @@ ledger 20260727041546
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727041546', 't4_snapshot_legs_select_by_time_not_stale_status', 'chase@ottoyard.com');
-- @@ ledger 20260727042144
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727042144', 't4a_close_travel_legs_and_measure_deviation', 'chase@ottoyard.com');
-- @@ ledger 20260727042243
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727042243', 't4b_durable_leg_selection_plus_coverage_meta', 'chase@ottoyard.com');
-- @@ ledger 20260727042605
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727042605', 't4c_close_travel_legs_on_plan_end_not_twin_teleport', 'chase@ottoyard.com');
-- @@ ledger 20260727043914
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727043914', 't4d_render_contract_coverage_probe', 'chase@ottoyard.com');
-- @@ ledger 20260727044436
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727044436', 't4d_coverage_sample_table_and_stepper', 'chase@ottoyard.com');
-- @@ ledger 20260727045136
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260727045136', 't4e_coverage_fix_join_key_and_state_vocabulary', 'chase@ottoyard.com');
-- @@ ledger 20260728022544
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728022544', 'ottoq_twin_events_window', 'chase@ottoyard.com');
-- @@ ledger 20260728030634
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728030634', 'ottoq_twin_spread_stat', 'chase@ottoyard.com');
-- @@ ledger 20260728030807
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728030807', 'ottoq_twin_fleet_condition', 'chase@ottoyard.com');
-- @@ ledger 20260728031459
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728031459', 'ottoq_twin_run_context', 'chase@ottoyard.com');
-- @@ ledger 20260728123536
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728123536', 'ottoq_twin_labor_window', 'chase@ottoyard.com');
-- @@ ledger 20260728124917
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728124917', 'ottoq_twin_offsite_window', 'chase@ottoyard.com');
-- @@ ledger 20260728125455
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728125455', 'ottoq_twin_offsite_window_jitter_detail', 'chase@ottoyard.com');
-- @@ ledger 20260728131125
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728131125', 'snapshot_publish_humidity', 'chase@ottoyard.com');
-- @@ ledger 20260728131329
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728131329', 'ottoq_twin_wear_window', 'chase@ottoyard.com');
-- @@ ledger 20260728131446
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728131446', 'run_context_observed_policy', 'chase@ottoyard.com');
-- @@ ledger 20260728150121
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728150121', 'decide_tick_honour_charging_staff', 'chase@ottoyard.com');
-- @@ ledger 20260728150905
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728150905', 'labor_window_charge_lane_cap', 'chase@ottoyard.com');
-- @@ ledger 20260728222051
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728222051', 'fn_definition_backups', 'chase@ottoyard.com');
-- @@ ledger 20260728230920
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260728230920', 'stall_bookings_forward_calendar', 'chase@ottoyard.com');
-- @@ ledger 20260729021218
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729021218', 'stall_booking_api', 'chase@ottoyard.com');
-- @@ ledger 20260729021331
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729021331', 'hold_stall_prefer_true_perimeter', 'chase@ottoyard.com');
-- @@ ledger 20260729021443
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729021443', 'stage_advance_auto_approval', 'chase@ottoyard.com');
-- @@ ledger 20260729022943
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729022943', 'tick_only_on_start_and_random_clock', 'chase@ottoyard.com');
-- @@ ledger 20260729023151
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729023151', 'arrival_disposition_no_auto_park', 'chase@ottoyard.com');
-- @@ ledger 20260729023247
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729023247', 'arrival_disposition_flag_precision', 'chase@ottoyard.com');
-- @@ ledger 20260729031859
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729031859', 'arrival_disposition_never_wait_at_gate', 'chase@ottoyard.com');
-- @@ ledger 20260729031929
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729031929', 'drop_stale_overloads', 'chase@ottoyard.com');
-- @@ ledger 20260729032021
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729032021', 'tech_hold_flag_precision', 'chase@ottoyard.com');
-- @@ ledger 20260729034224
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729034224', 'fix_reservation_null_ordering', 'chase@ottoyard.com');
-- @@ ledger 20260729034321
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729034321', 'charger_fault_temp_stage_not_gate', 'chase@ottoyard.com');
-- @@ ledger 20260729123425
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729123425', 'book_whole_workflow', 'chase@ottoyard.com');
-- @@ ledger 20260729123624
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729123624', 'wire_arrival_disposition_into_decide_tick', 'chase@ottoyard.com');
-- @@ ledger 20260729130111
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729130111', 'deadlock_breaker_temp_stage_not_gate', 'chase@ottoyard.com');
-- @@ ledger 20260729145613
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729145613', 'fix_opportunistic_gate_bounce_and_booking_release', 'chase@ottoyard.com');
-- @@ ledger 20260729145701
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729145701', 'place_unplaced_vehicles_reconciler', 'chase@ottoyard.com');
-- @@ ledger 20260729145734
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729145734', 'wire_placement_reconciler_into_tick', 'chase@ottoyard.com');
-- @@ ledger 20260729150015
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729150015', 'stop_and_reset_releases_bookings', 'chase@ottoyard.com');
-- @@ ledger 20260729150619
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729150619', 'reconciler_place_redeploy_waiters', 'chase@ottoyard.com');
-- @@ ledger 20260729155620
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729155620', 'twin_day_night_arrival_distribution', 'chase@ottoyard.com');
-- @@ ledger 20260729161106
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729161106', 'return_trigger_wash_cadence_day_based', 'chase@ottoyard.com');
-- @@ ledger 20260729163636
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729163636', 'bay_leg_duration_is_service_time_only', 'chase@ottoyard.com');
-- @@ ledger 20260729173503
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729173503', 'preseparation_schema_snapshot', 'chase@ottoyard.com');
-- @@ ledger 20260729173811
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729173811', 'world_tables_read_only_for_client_keys', 'chase@ottoyard.com');
-- @@ ledger 20260729175059
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729175059', 'revoke_anon_execute_on_destructive_control_plane', 'chase@ottoyard.com');
-- @@ ledger 20260729175148
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729175148', 'revoke_public_execute_on_destructive_functions', 'chase@ottoyard.com');
-- @@ ledger 20260729175913
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729175913', 'create_twin_ottoq_schemas_and_pin_search_path', 'chase@ottoyard.com');
-- @@ ledger 20260729180118
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729180118', 'fix_txn_control_routines_search_path', 'chase@ottoyard.com');
-- @@ ledger 20260729181320
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729181320', 'split_charger_fault_observation_from_decision', 'chase@ottoyard.com');
-- @@ ledger 20260729191442
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729191442', 'split_8_ingest_vehicle_signal', 'chase@ottoyard.com');
-- @@ ledger 20260729191651
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729191651', 'split_3_wash_triage', 'chase@ottoyard.com');
-- @@ ledger 20260729192126
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729192126', 'split_5_overnight_service_drain', 'chase@ottoyard.com');
-- @@ ledger 20260729193450
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729193450', 'split_2_vehicle_exception_handler', 'chase@ottoyard.com');
-- @@ ledger 20260729193556
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729193556', 'split_7_opportunistic_scan', 'chase@ottoyard.com');
-- @@ ledger 20260729194258
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729194258', 'split_6_auto_dispatch_tick', 'chase@ottoyard.com');
-- @@ ledger 20260729194352
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729194352', 'split_4a_stranded_undercharge_decision', 'chase@ottoyard.com');
-- @@ ledger 20260729221417
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729221417', 'split_4b_advance_service_flow_twin', 'chase@ottoyard.com');
-- @@ ledger 20260729223322
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729223322', 'move_decision_functions_wave1_to_ottoq', 'chase@ottoyard.com');
-- @@ ledger 20260729223613
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729223613', 'move_decision_functions_wave2_to_ottoq', 'chase@ottoyard.com');
-- @@ ledger 20260729230420
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729230420', 'step2_command_contract_hardening_v3', 'chase@ottoyard.com');
-- @@ ledger 20260729230535
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729230535', 'step2_emit_returns_command_id', 'chase@ottoyard.com');
-- @@ ledger 20260729230707
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729230707', 'step2_confirm_preconditions_and_refusal', 'chase@ottoyard.com');
-- @@ ledger 20260729230901
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729230901', 'step2_reaction_loop', 'chase@ottoyard.com');
-- @@ ledger 20260729232529
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260729232529', 'step2_reaction_reserve_first_walk_v2', 'chase@ottoyard.com');
-- @@ ledger 20260730002808
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730002808', 'doctrine_ottoq_preflight_twin_pure_executor', 'chase@ottoyard.com');
-- @@ ledger 20260730003409
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730003409', 'move_twin_engine_functions_to_twin_schema_v2', 'chase@ottoyard.com');
-- @@ ledger 20260730030344
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730030344', 'drop_never_used_ottoq_events_indexes', 'chase@ottoyard.com');
-- @@ ledger 20260730124248
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730124248', 'stop_writing_previous_state_in_state_change_triggers', 'chase@ottoyard.com');
-- @@ ledger 20260730125700
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730125700', 'suppress_timestamp_only_state_change_events', 'chase@ottoyard.com');
-- @@ ledger 20260730173421
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730173421', 'audit_completeness_reject_empty_and_purged_windows', 'chase@ottoyard.com');
-- @@ ledger 20260730173536
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730173536', 'audit_completeness_coalesce_null_exclusions', 'chase@ottoyard.com');
-- @@ ledger 20260730173718
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730173718', 'audit_completeness_replace_not_append_evidence', 'chase@ottoyard.com');
-- @@ ledger 20260730174337
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730174337', 'resolve_signing_secret_from_vault', 'chase@ottoyard.com');
-- @@ ledger 20260730174431
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730174431', 'fix_audit_completeness_verification_field_names', 'chase@ottoyard.com');
-- @@ ledger 20260730174608
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730174608', 'revoke_signing_internals_from_public_anon_authenticated', 'chase@ottoyard.com');
-- @@ ledger 20260730180656
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730180656', 'rescope_service_role_policies_off_public', 'chase@ottoyard.com');
-- @@ ledger 20260730180810
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260730180810', 'revoke_record_event_from_anon_authenticated', 'chase@ottoyard.com');
-- @@ ledger 20260731031246
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260731031246', 'stop_archives_run_log_before_reset', 'chase@ottoyard.com');
-- @@ ledger 20260731031315
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260731031315', 'stop_and_reset_calls_archive_first', 'chase@ottoyard.com');
-- @@ ledger 20260731031458
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260731031458', 'purge_must_not_delete_run_archives', 'chase@ottoyard.com');
-- @@ ledger 20260731032255
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260731032255', 'first_class_pause_resume_with_clock_anchor_reset', 'chase@ottoyard.com');
-- @@ ledger 20260731222513
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260731222513', 'cuopt_fire_and_forget_remove_blocking_solve_window', 'chase@ottoyard.com');
-- @@ ledger 20260801042846
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801042846', 'l2_external_proposal_sim_clock_domain_fix', 'chase@ottoyard.com');
-- @@ ledger 20260801043046
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801043046', 'l2_external_proposal_charger_check_uses_sim_clock', 'chase@ottoyard.com');
-- @@ ledger 20260801163600
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801163600', 'cuopt_fire_after_decide_so_answer_waits_for_next_tick', 'chase@ottoyard.com');
-- @@ ledger 20260801164908
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801164908', 'total_svc_to_leg_type_mapper', 'chase@ottoyard.com');
-- @@ ledger 20260801165008
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801165008', 'itinerary_legs_map_svc_to_leg_type_totally', 'chase@ottoyard.com');
-- @@ ledger 20260801181400
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801181400', 'cuopt_split_tick_ordering', 'chase@ottoyard.com');
-- @@ ledger 20260801181619
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801181619', 'snapshot_and_keep_external_proposals_for_cuopt_proof', 'chase@ottoyard.com');
-- @@ ledger 20260801184048
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801184048', 'preserve_cuopt_first_enactment_proof', 'chase@ottoyard.com');
-- @@ ledger 20260801184118
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801184118', 'revert_purge_keeplist_now_proof_is_preserved', 'chase@ottoyard.com');
-- @@ ledger 20260801192327
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801192327', 'booking_ledger_records_enacted_decision', 'chase@ottoyard.com');
-- @@ ledger 20260801201600
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801201600', 'calendar_completeness_01_book_stall_total_function', 'chase@ottoyard.com');
-- @@ ledger 20260801201640
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801201640', 'calendar_completeness_02_stall_free_between_occupancy_guard', 'chase@ottoyard.com');
-- @@ ledger 20260801201928
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801201928', 'calendar_completeness_03_decide_tick_record_every_space', 'chase@ottoyard.com');
-- @@ ledger 20260801202928
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801202928', 'approach_band_01_derived_zone_view_and_guard', 'chase@ottoyard.com');
-- @@ ledger 20260801203309
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801203309', 'approach_band_02_revoke_anon', 'chase@ottoyard.com');
-- @@ ledger 20260801204457
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801204457', 'calendar_band_03_register_policy_knobs_in_catalog', 'chase@ottoyard.com');
-- @@ ledger 20260801212522
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801212522', 'zonec_hardware_fault_predicate_fix', 'chase@ottoyard.com');
-- @@ ledger 20260801212734
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801212734', 'live_clock_write_tick_minutes_actual_demo_path', 'chase@ottoyard.com');
-- @@ ledger 20260801212848
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801212848', 'live_clock_mode_aware_runaway_backstop_v2', 'chase@ottoyard.com');
-- @@ ledger 20260801212918
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801212918', 'live_clock_default_for_demo_runs', 'chase@ottoyard.com');
-- @@ ledger 20260801221425
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801221425', 'service_need_gate_2026_08_01', 'chase@ottoyard.com');
-- @@ ledger 20260801234644
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801234644', 'busy_day_scenario_register', 'chase@ottoyard.com');
-- @@ ledger 20260801234720
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801234720', 'busy_day_starter_fn', 'chase@ottoyard.com');
-- @@ ledger 20260801235754
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801235754', 'vehicle_need_profile_table', 'chase@ottoyard.com');
-- @@ ledger 20260801235920
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260801235920', 'ottoq_seed_vehicle_need_profiles', 'chase@ottoyard.com');
-- @@ ledger 20260802000115
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802000115', 'ottoq_vehicle_needs_card_view', 'chase@ottoyard.com');
-- @@ ledger 20260802000252
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802000252', 'vnp_seeder_cadence_tune', 'chase@ottoyard.com');
-- @@ ledger 20260802000442
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802000442', 'needs_card_urgency_ladder_and_statement', 'chase@ottoyard.com');
-- @@ ledger 20260802000518
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802000518', 'boot_draw_seeds_need_profiles', 'chase@ottoyard.com');
-- @@ ledger 20260802000707
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802000707', 'ottoq_need_to_leg_type_helper', 'chase@ottoyard.com');
-- @@ ledger 20260802000937
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802000937', 'vnp_seeder_lifetime_odometer_and_reachable_tiers', 'chase@ottoyard.com');
-- @@ ledger 20260802001200
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802001200', 'vehicle_need_profile_hardening', 'chase@ottoyard.com');
-- @@ ledger 20260802001216
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802001216', 'vehicle_need_profile_seeder_revoke_public', 'chase@ottoyard.com');
-- @@ ledger 20260802002041
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802002041', 'cadence_escalation_policy_table', 'chase@ottoyard.com');
-- @@ ledger 20260802002108
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802002108', 'cadence_escalation_policy_seed', 'chase@ottoyard.com');
-- @@ ledger 20260802002127
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802002127', 'cadence_escalation_functions', 'chase@ottoyard.com');
-- @@ ledger 20260802002556
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802002556', 'cadence_escalation_needs_card_view', 'chase@ottoyard.com');
-- @@ ledger 20260802002800
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802002800', 'cadence_escalation_apply_fn', 'chase@ottoyard.com');
-- @@ ledger 20260802003639
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802003639', 'phase1_busy_proof_evidence_table', 'chase@ottoyard.com');
-- @@ ledger 20260802020947
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802020947', 'p0_record_enacted_booking_helper', 'chase@ottoyard.com');
-- @@ ledger 20260802021031
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802021031', 'p0_decide_tick_enactment_books_atomically', 'chase@ottoyard.com');
-- @@ ledger 20260802021313
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802021313', 'p0_record_enacted_booking_idempotency_hardening', 'chase@ottoyard.com');
-- @@ ledger 20260802022747
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802022747', 'p1_enact_space_assignment_helper', 'chase@ottoyard.com');
-- @@ ledger 20260802022827
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802022827', 'p1_release_vacated_spaces_sweeper', 'chase@ottoyard.com');
-- @@ ledger 20260802023138
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802023138', 'p1_decide_tick_needs_card_space_routing', 'chase@ottoyard.com');
-- @@ ledger 20260802024523
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802024523', 'p2_orphan_charge_session_sweep_unfreeze_enactment', 'chase@ottoyard.com');
-- @@ ledger 20260802025159
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802025159', 'phase2_busy_proof_evidence_table', 'chase@ottoyard.com');
-- @@ ledger 20260802031919
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802031919', 'phase3_p0_rearm_overlap_guard_v2', 'chase@ottoyard.com');
-- @@ ledger 20260802032058
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802032058', 'phase3_p0_booking_lifecycle_occupancy', 'chase@ottoyard.com');
-- @@ ledger 20260802032136
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802032136', 'phase3_p0_picker_consults_calendar', 'chase@ottoyard.com');
-- @@ ledger 20260802032220
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802032220', 'phase3_p0_enacted_booking_never_blocked', 'chase@ottoyard.com');
-- @@ ledger 20260802032258
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802032258', 'phase3_p0_wire_activation_into_decide_tick', 'chase@ottoyard.com');
-- @@ ledger 20260802033429
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802033429', 'phase3_bay_unification_snapshot_guard', 'chase@ottoyard.com');
-- @@ ledger 20260802033519
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802033519', 'phase3_record_enacted_booking_carry_leg_and_visit', 'chase@ottoyard.com');
-- @@ ledger 20260802033600
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802033600', 'phase3_enact_space_honours_forward_reservation', 'chase@ottoyard.com');
-- @@ ledger 20260802033634
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802033634', 'phase3_release_bay_on_exit_transition', 'chase@ottoyard.com');
-- @@ ledger 20260802033731
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802033731', 'phase3_bind_unbooked_bay_occupants', 'chase@ottoyard.com');
-- @@ ledger 20260802033929
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802033929', 'phase3_decide_tick_gate_bay_entry_on_booking', 'chase@ottoyard.com');
-- @@ ledger 20260802034017
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802034017', 'phase3_decide_tick_correct_stale_bay_comment', 'chase@ottoyard.com');
-- @@ ledger 20260802034505
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802034505', 'phase3_bind_unbooked_bay_occupants_writes_decision', 'chase@ottoyard.com');
-- @@ ledger 20260802034829
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802034829', 'phase3_smoke_corrections_honour_activate_truncate', 'chase@ottoyard.com');
-- @@ ledger 20260802034904
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802034904', 'phase3_honour_only_reservations_that_cover_now', 'chase@ottoyard.com');
-- @@ ledger 20260802035923
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802035923', 'phase3_cuopt_invocation_log', 'chase@ottoyard.com');
-- @@ ledger 20260802040018
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802040018', 'phase3_cuopt_gate_logger', 'chase@ottoyard.com');
-- @@ ledger 20260802040044
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802040044', 'phase3_cuopt_refresh_telemetry', 'chase@ottoyard.com');
-- @@ ledger 20260802040713
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802040713', 'phase3_cuopt_invocation_log_grant_tighten', 'chase@ottoyard.com');
-- @@ ledger 20260802050732
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802050732', 'phase3_cert_424242_evidence_table', 'chase@ottoyard.com');
-- @@ ledger 20260802053816
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802053816', 'space_conflict_ledger_and_booking_provenance', 'chase@ottoyard.com');
-- @@ ledger 20260802053925
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802053925', 'reconcile_displace_stale_claim', 'chase@ottoyard.com');
-- @@ ledger 20260802053953
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802053953', 'record_enacted_booking_stamps_source', 'chase@ottoyard.com');
-- @@ ledger 20260802054049
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802054049', 'bind_unbooked_bay_occupants_displace_authority', 'chase@ottoyard.com');
-- @@ ledger 20260802054124
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802054124', 'calendar_ledger_integrity_view', 'chase@ottoyard.com');
-- @@ ledger 20260802055639
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802055639', 'booking_why_columns_and_resolver', 'chase@ottoyard.com');
-- @@ ledger 20260802055723
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802055723', 'record_enacted_booking_carries_leg_and_need', 'chase@ottoyard.com');
-- @@ ledger 20260802055749
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802055749', 'late_bind_leg_at_leg_open_and_why_view', 'chase@ottoyard.com');
-- @@ ledger 20260802060427
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802060427', 'late_bind_leg_source_provenance_fix', 'chase@ottoyard.com');
-- @@ ledger 20260802060551
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802060551', 'book_stall_stamps_why_for_every_writer', 'chase@ottoyard.com');
-- @@ ledger 20260802060716
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802060716', 'booking_why_atom_match_excludes_dedicated_lanes', 'chase@ottoyard.com');
-- @@ ledger 20260802071029
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802071029', 'phase4_cert_424242_evidence_table', 'chase@ottoyard.com');
-- @@ ledger 20260802143903
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802143903', 'p0_scenario_apply_fleet_overrides', 'chase@ottoyard.com');
-- @@ ledger 20260802143935
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802143935', 'p0_prime_honors_target_fraction', 'chase@ottoyard.com');
-- @@ ledger 20260802144033
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802144033', 'p0_run_scenario_applies_overrides', 'chase@ottoyard.com');
-- @@ ledger 20260802144114
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802144114', 'p0_busy_day_sustained_profile', 'chase@ottoyard.com');
-- @@ ledger 20260802144244
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802144244', 'p0_workload_harness', 'chase@ottoyard.com');
-- @@ ledger 20260802145931
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802145931', 'p1_align_validate_assignment_with_overlap_v2', 'chase@ottoyard.com');
-- @@ ledger 20260802151307
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802151307', 'p2_cuopt_deferral_ledger', 'chase@ottoyard.com');
-- @@ ledger 20260802151358
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802151358', 'p2_cuopt_gate_candidate_predicate_and_arm', 'chase@ottoyard.com');
-- @@ ledger 20260802151445
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802151445', 'p2_decide_tick_defer_to_cuopt_one_tick', 'chase@ottoyard.com');
-- @@ ledger 20260802152312
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802152312', 'p2_gate_predicate_a_charge_stalls_only', 'chase@ottoyard.com');
-- @@ ledger 20260802153242
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802153242', 'p3_booking_authorship_and_decision_link', 'chase@ottoyard.com');
-- @@ ledger 20260802153300
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802153300', 'p3_record_enacted_booking_honest_authorship', 'chase@ottoyard.com');
-- @@ ledger 20260802153311
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802153311', 'p3_decide_tick_link_bookings_to_decisions', 'chase@ottoyard.com');
-- @@ ledger 20260802153330
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802153330', 'p3_reconciler_stamp_decision_link', 'chase@ottoyard.com');
-- @@ ledger 20260802153925
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802153925', 'p3_staging_authorship_through_classifier', 'chase@ottoyard.com');
-- @@ ledger 20260802163643
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802163643', 'preserve_phase5_certification_evidence', 'chase@ottoyard.com');
-- @@ ledger 20260802170105
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802170105', 'cuopt_supply_fix_pin_instance_and_real_first_refusal', 'chase@ottoyard.com');
-- @@ ledger 20260802211949
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802211949', 'p6_cuopt_fix2_run_the_healthy_beat', 'chase@ottoyard.com');
-- @@ ledger 20260802214110
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802214110', 'booking_provenance_audit_and_failclosed_authorship', 'chase@ottoyard.com');
-- @@ ledger 20260802214210
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802214210', 'gate_intake_booking_id_exact_provenance', 'chase@ottoyard.com');
-- @@ ledger 20260802214353
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802214353', 'provenance_audit_temporal_tightening', 'chase@ottoyard.com');
-- @@ ledger 20260802220008
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802220008', 'prime_deployment_stratified_stagger_2026_08_02', 'chase@ottoyard.com');
-- @@ ledger 20260802220215
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802220215', 'departure_staging_readiness_gate_2026_08_02', 'chase@ottoyard.com');
-- @@ ledger 20260802230804
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802230804', 'phase6_cert_424242_capture', 'chase@ottoyard.com');
-- @@ ledger 20260802234605
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260802234605', 'bay_reservation_reconcile_honour_or_replan', 'chase@ottoyard.com');
-- @@ ledger 20260803013316
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803013316', 'build1_bay_fault_handler_no_mid_service_eviction', 'chase@ottoyard.com');
-- @@ ledger 20260803014950
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803014950', 'build2_interrupted_state_and_threshold_helpers', 'chase@ottoyard.com');
-- @@ ledger 20260803015053
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803015053', 'build2_reopen_atoms_and_release_interrupted', 'chase@ottoyard.com');
-- @@ ledger 20260803015116
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803015116', 'build2_overlap_guard_v3_includes_interrupted', 'chase@ottoyard.com');
-- @@ ledger 20260803015228
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803015228', 'build2_work_metric_counts_only_finished_work', 'chase@ottoyard.com');
-- @@ ledger 20260803015432
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803015432', 'build2_reopen_atoms_also_unhides_outstanding_need', 'chase@ottoyard.com');
-- @@ ledger 20260803015807
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803015807', 'build2_fix_interrupted_audit_event_data_source', 'chase@ottoyard.com');
-- @@ ledger 20260803021038
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803021038', 'build3_enact_space_assignment_inspect_zone', 'chase@ottoyard.com');
-- @@ ledger 20260803021143
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803021143', 'build3_inspection_seam_function', 'chase@ottoyard.com');
-- @@ ledger 20260803021212
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803021212', 'build3_decide_tick_call_inspection_seam', 'chase@ottoyard.com');
-- @@ ledger 20260803022823
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803022823', 'build3_inspection_seam_v2_widen_and_release', 'chase@ottoyard.com');
-- @@ ledger 20260803030743
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803030743', 'phase9_fix1a_reopen_visit_atoms_fallback', 'chase@ottoyard.com');
-- @@ ledger 20260803030831
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803030831', 'phase9_fix1b_unstrand_bound_legs_on_interrupt', 'chase@ottoyard.com');
-- @@ ledger 20260803031220
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803031220', 'phase9_fix1a_reopen_visit_atoms_targeted_fallback', 'chase@ottoyard.com');
-- @@ ledger 20260803031312
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803031312', 'phase9_fix1b_add_needs_open_after_telemetry', 'chase@ottoyard.com');
-- @@ ledger 20260803032549
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803032549', 'phase9_fix2a_indepot_guard_revive_deferred_branch', 'chase@ottoyard.com');
-- @@ ledger 20260803032704
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803032704', 'phase9_fix2b_gate_vehicle_exception_handler_evictions', 'chase@ottoyard.com');
-- @@ ledger 20260803034243
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803034243', 'phase9_fix3_inspect_seam_reach_and_unsquat_inspection', 'chase@ottoyard.com');
-- @@ ledger 20260803034822
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803034822', 'phase9_fix3b_inspect_seam_command_emit_schema_and_isolation', 'chase@ottoyard.com');
-- @@ ledger 20260803035345
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803035345', 'phase9_fix3c_reroute_picker_excludes_inspection_zone', 'chase@ottoyard.com');
-- @@ ledger 20260803130345
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803130345', 'phase10_critical_severity_routes_through_gate', 'chase@ottoyard.com');
-- @@ ledger 20260803130436
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803130436', 'phase10_reopen_visit_atoms_write_always', 'chase@ottoyard.com');
-- @@ ledger 20260803130602
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803130602', 'phase10_exception_handler_gate_critical_preserve_work', 'chase@ottoyard.com');
-- @@ ledger 20260803134521
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803134521', 'phase11_book_stall_zone_and_dup_guards', 'chase@ottoyard.com');
-- @@ ledger 20260803134546
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803134546', 'phase11_enacted_booking_releases_sibling_holds', 'chase@ottoyard.com');
-- @@ ledger 20260803134614
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803134614', 'phase11_decide_tick_gate_intake_excludes_inspection_zone', 'chase@ottoyard.com');
-- @@ ledger 20260803134710
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803134710', 'phase11_harness_honest_inspection_denominator', 'chase@ottoyard.com');
-- @@ ledger 20260803140954
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803140954', 'p7_cuopt_first_refusal_supply_recovery', 'chase@ottoyard.com');
-- @@ ledger 20260803141119
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803141119', 'p7_cuopt_gate_widen_and_wire_first_refusal', 'chase@ottoyard.com');
-- @@ ledger 20260803155025
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803155025', 'phase11_readmit_resumed_visits', 'chase@ottoyard.com');
-- @@ ledger 20260803172421
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803172421', 'emit_booking_interrupted_shared_emitter', 'chase@ottoyard.com');
-- @@ ledger 20260803172549
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803172549', 'release_expired_bookings_emit_interrupted', 'chase@ottoyard.com');
-- @@ ledger 20260803172618
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803172618', 'release_expired_bookings_emit_no_temp_table', 'chase@ottoyard.com');
-- @@ ledger 20260803174410
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803174410', 'phase11_booked_at_sim_clock_domain', 'chase@ottoyard.com');
-- @@ ledger 20260803174426
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803174426', 'phase11_booked_at_sim_stamp_trigger', 'chase@ottoyard.com');
-- @@ ledger 20260803174555
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803174555', 'phase11_activate_due_bay_reservations', 'chase@ottoyard.com');
-- @@ ledger 20260803174648
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803174648', 'phase11_release_vacated_activate_before_grace', 'chase@ottoyard.com');
-- @@ ledger 20260803201404
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803201404', 'p0_readmit_reopened_needs_first_class_demand', 'chase@ottoyard.com');
-- @@ ledger 20260803201437
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803201437', 'p0_wire_readmit_reopened_needs_into_decide_tick', 'chase@ottoyard.com');
-- @@ ledger 20260803201627
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803201627', 'p0b_bay_reconcile_sibling_stall_walk', 'chase@ottoyard.com');
-- @@ ledger 20260803203318
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803203318', 'p1_align_calendar_reads_with_v3_guard', 'chase@ottoyard.com');
-- @@ ledger 20260803203712
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803203712', 'p1_harness_invariant_free_stalls_undercount', 'chase@ottoyard.com');
-- @@ ledger 20260803205820
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803205820', 'p2_eviction_service_incompatible_gate', 'chase@ottoyard.com');
-- @@ ledger 20260803210009
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803210009', 'p2_fault_class_taxonomy_and_honest_defer_stamp', 'chase@ottoyard.com');
-- @@ ledger 20260803210034
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260803210034', 'p2_demand_rebook_after_eviction', 'chase@ottoyard.com');
-- @@ ledger 20260804140958
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260804140958', 'approval_gate_decider', 'chase@ottoyard.com');
-- @@ ledger 20260804183836
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260804183836', 'bay_work_recovery', 'chase@ottoyard.com');
-- @@ ledger 20260804232058
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260804232058', 'close_ledger_loop', 'chase@ottoyard.com');
-- @@ ledger 20260805020029
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260805020029', 'inspection_and_condition_resets', 'chase@ottoyard.com');
-- @@ ledger 20260805032907
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260805032907', 'add_site_energy_snapshots_created_at_idx', 'chase@ottoyard.com');
-- @@ ledger 20260805142711
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260805142711', 'slim_writes_and_arm_retention', NULL);
-- @@ ledger 20260805230731
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260805230731', 'soil_gate_and_retention_walk', 'chase@ottoyard.com');
-- @@ ledger 20260806030248
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260806030248', 'honest_completion_and_eta', 'chase@ottoyard.com');
-- @@ ledger 20260806223619
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260806223619', 'unify_depot_layout', NULL);
-- @@ ledger 20260806231121
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260806231121', 'forward_bay_reservation_at_return_signal', NULL);
-- @@ ledger 20260807001645
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260807001645', 'tick_cost_and_metronome_ceiling', 'chase@ottoyard.com');
-- @@ ledger 20260807002716
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260807002716', 'metronome_guard_reads_the_real_timeout', 'chase@ottoyard.com');
-- @@ ledger 20260807005437
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260807005437', 'bay_binding_witness', 'chase@ottoyard.com');
-- @@ ledger 20260807013120
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260807013120', 'early_activation_and_untagged_event_flood', 'chase@ottoyard.com');
-- @@ ledger 20260807015854
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260807015854', 'bay_seat_writes_the_twin_service_timer', 'chase@ottoyard.com');
-- @@ ledger 20260808041455
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260808041455', 'rider_flagged_cleaning_recall', 'stream_apply_management_api');
-- @@ ledger 20260808153457
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260808153457', 'rider_flag_holds_the_vehicle', 'stream-apply: POST /v1/projects/{ref}/database/query, file sent byte-exact from disk');
-- @@ ledger 20260808165323
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260808165323', 'rider_flag_consume_and_place_is_atomic', 'chase@ottoyard.com');
-- @@ ledger 20260808170813
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260808170813', 'one_vehicle_one_stall', 'chase@ottoyard.com');
-- @@ ledger 20260808182226
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260808182226', 'a_run_owns_its_rows', 'chase@ottoyard.com');
-- @@ ledger 20260808193142
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260808193142', 'a_finished_run_is_read_only', 'chase@ottoyard.com');
-- @@ ledger 20260810194053
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810194053', 'a_mated_vehicle_cannot_move', 'chase@ottoyard.com');
-- @@ ledger 20260810200742
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810200742', 'a_mated_vehicle_keeps_the_plug_until_the_robot_demates', 'chase@ottoyard.com');
-- @@ ledger 20260810200757
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810200757', 'a_tethered_vehicle_is_not_a_dispatch_candidate', 'chase@ottoyard.com');
-- @@ ledger 20260810200847
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810200847', 'a_tethered_vehicle_is_not_an_indepot_move_candidate', 'chase@ottoyard.com');
-- @@ ledger 20260810200916
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810200916', 'a_finished_demate_frees_the_plug_every_tick', 'chase@ottoyard.com');
-- @@ ledger 20260810200917
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810200917', 'the_cockpit_can_see_a_live_tether', 'chase@ottoyard.com');
-- @@ ledger 20260810201054
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810201054', 'the_world_tick_can_confirm_a_stall_command', 'chase@ottoyard.com');
-- @@ ledger 20260810201358
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810201358', 'the_command_confirm_seam_is_a_total_function', 'chase@ottoyard.com');
-- @@ ledger 20260810202758
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810202758', 'the_tether_sweep_actually_frees_the_stall', 'chase@ottoyard.com');
-- @@ ledger 20260810213646
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810213646', 'the_indepot_gate_protects_work_in_progress_not_every_release', 'chase@ottoyard.com');
-- @@ ledger 20260810215137
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810215137', 'a_confirmed_command_changes_the_vehicle_not_just_the_stall', 'chase@ottoyard.com');
-- @@ ledger 20260810220553
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810220553', 'soc_is_derived_from_cumulative_energy_not_incremented', 'chase@ottoyard.com');
-- @@ ledger 20260810222915
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810222915', 'deployed_vehicles_actually_discharge', 'chase@ottoyard.com');
-- @@ ledger 20260810223547
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810223547', 'the_demate_window_is_one_named_knob', 'chase@ottoyard.com');
-- @@ ledger 20260810224258
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260810224258', 'the_global_policy_tier_is_reachable', 'chase@ottoyard.com');
-- @@ ledger 20260811031512
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260811031512', 'continuous_playback_ceiling_is_eight_x', 'chase@ottoyard.com');
-- @@ ledger 20260811033531
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260811033531', 'a_bad_command_cannot_abort_the_world_tick', 'chase@ottoyard.com');
-- @@ ledger 20260811035357
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260811035357', 'the_depot_starts_with_real_fast_charge_demand', 'chase@ottoyard.com');
-- @@ ledger 20260811124543
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260811124543', 'demo_start_honours_the_eight_x_ceiling', 'chase@ottoyard.com');
-- @@ ledger 20260811140510
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260811140510', 'deploy_release_per_tick_budget_scales_with_tick_length', 'chase@ottoyard.com');
-- @@ ledger 20260811140716
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260811140716', 'deploy_plan_call_passes_actual_tick_minutes', 'chase@ottoyard.com');
-- @@ ledger 20260811182857
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260811182857', 'twin_snapshot_publish_open_visit_needs', 'chase@ottoyard.com');
-- @@ ledger 20260811184244
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260811184244', 'the_depot_is_158_stalls_in_both_worlds', 'chase@ottoyard.com');
-- @@ ledger 20260811190550
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260811190550', 'a_layout_backup_is_not_public_property', 'chase@ottoyard.com');
-- @@ ledger 20260812002735
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812002735', 'charging_must_never_lower_a_battery', 'chase@ottoyard.com');
-- @@ ledger 20260812183708
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812183708', 'the_browser_key_cannot_write_the_world', 'chase@ottoyard.com');
-- @@ ledger 20260812193637
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812193637', 'arm_motion_timings_have_exactly_one_home', 'chase@ottoyard.com');
-- @@ ledger 20260812195141
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812195141', 'the_arm_holds_the_car_from_approach_until_clear', 'chase@ottoyard.com');
-- @@ ledger 20260812200007
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812200007', 'the_arm_only_latches_when_it_actually_found_the_inlet', 'chase@ottoyard.com');
-- @@ ledger 20260812202754
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812202754', 'a_mate_cycle_is_never_lost_to_the_demate_behind_it', 'chase@ottoyard.com');
-- @@ ledger 20260812205753
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812205753', 'the_perimeter_is_a_long_hold_not_a_front_door', 'chase@ottoyard.com');
-- @@ ledger 20260812220135
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812220135', 'a_stall_reserved_for_a_vehicle_says_which_vehicle', 'chase@ottoyard.com');
-- @@ ledger 20260812221202
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812221202', 'every_stall_knows_how_far_it_is_from_the_gate', 'chase@ottoyard.com');
-- @@ ledger 20260812221324
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812221324', 'the_hold_ladder_has_no_unreachable_rung', 'chase@ottoyard.com');
-- @@ ledger 20260812225121
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812225121', 'a_charge_session_cannot_meter_energy_the_battery_did_not_take', 'chase@ottoyard.com');
-- @@ ledger 20260812225413
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812225413', 'a_run_only_advances_its_own_charge_sessions', 'chase@ottoyard.com');
-- @@ ledger 20260812225555
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260812225555', 'a_finished_run_lets_go_of_its_cars', 'chase@ottoyard.com');
-- @@ ledger 20260813005932
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813005932', 'an_arm_fault_has_a_sanctioned_way_to_let_go', 'chase@ottoyard.com');
-- @@ ledger 20260813010244
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813010244', 'the_twins_own_movers_ask_the_arm_before_they_move_a_car', 'chase@ottoyard.com');
-- @@ ledger 20260813013102
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813013102', 'a_tethered_car_cannot_be_moved_by_anything_that_did_not_ask', 'chase@ottoyard.com');
-- @@ ledger 20260813014140
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813014140', 'the_arm_does_not_reach_for_a_car_that_needs_nothing', 'chase@ottoyard.com');
-- @@ ledger 20260813015215
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813015215', 'a_charger_fault_releases_the_arm_through_the_front_door', 'chase@ottoyard.com');
-- @@ ledger 20260813015414
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813015414', 'routine_movers_refuse_a_held_car_and_fault_recovery_unplugs_it', 'chase@ottoyard.com');
-- @@ ledger 20260813015624
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813015624', 'the_run_length_ceiling_has_exactly_one_home', 'chase@ottoyard.com');
-- @@ ledger 20260813023922
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813023922', 'a_satisfied_charge_need_is_a_done_need', 'chase@ottoyard.com');
-- @@ ledger 20260813025257
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813025257', 'a_full_charge_is_one_hundred_percent_and_has_one_home', 'chase@ottoyard.com');
-- @@ ledger 20260813025513
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813025513', 'no_target_soc_fallback_survives_anywhere', 'chase@ottoyard.com');
-- @@ ledger 20260813025623
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813025623', 'a_car_below_ninety_in_the_depot_gets_topped_off', 'chase@ottoyard.com');
-- @@ ledger 20260813031054
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813031054', 'the_deploy_floor_is_not_the_topoff_trigger', 'chase@ottoyard.com');
-- @@ ledger 20260813040822
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813040822', 'a_fast_plug_stops_at_ninety_by_day', 'chase@ottoyard.com');
-- @@ ledger 20260813040908
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813040908', 'a_run_starts_with_cars_in_the_world', 'chase@ottoyard.com');
-- @@ ledger 20260813041011
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813041011', 'a_run_can_outlast_a_full_charge', 'chase@ottoyard.com');
-- @@ ledger 20260813125109
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813125109', 'a_demating_car_keeps_its_stall_until_the_arm_lets_go', 'chase@ottoyard.com');
-- @@ ledger 20260813131333
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813131333', 'a_stalled_run_does_not_look_alive', 'chase@ottoyard.com');
-- @@ ledger 20260813132943
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813132943', 'a_charge_target_is_fixed_when_the_plug_goes_in', 'chase@ottoyard.com');
-- @@ ledger 20260813133041
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813133041', 'the_fast_plug_target_comes_from_policy_not_a_literal', 'chase@ottoyard.com');
-- @@ ledger 20260813143236
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813143236', 'night_waves_run_from_eleven_to_six_emptiest_first', 'chase@ottoyard.com');
-- @@ ledger 20260813143355
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813143355', 'a_fast_plug_is_always_first_choice_and_l2_is_overflow', 'chase@ottoyard.com');
-- @@ ledger 20260813153633
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813153633', 'a_swallowed_tick_failure_is_still_recorded', 'chase@ottoyard.com');
-- @@ ledger 20260813202521
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813202521', 'the_site_geometry_contract_has_one_home', 'chase@ottoyard.com');
-- @@ ledger 20260813205501
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260813205501', 'the_geometry_contract_says_which_numbers_are_drawable', 'chase@ottoyard.com');
-- @@ ledger 20260814131003
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260814131003', 'a_reissued_command_does_not_supersede_itself', 'chase@ottoyard.com');
-- @@ ledger 20260814131251
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260814131251', 'only_one_run_moves_the_world_at_a_time', 'chase@ottoyard.com');
-- @@ ledger 20260815030126
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260815030126', 'the_contract_says_how_to_animate_a_vehicle', 'chase@ottoyard.com');
-- @@ ledger 20260815220148
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260815220148', 'a_real_robot_reports_across_the_same_seam', 'chase@ottoyard.com');
-- @@ ledger 20260815222925
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260815222925', 'the_robovac_dock_counts_as_a_charger', 'chase@ottoyard.com');
-- @@ ledger 20260816034545
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260816034545', 'a_cockpit_can_recall_a_vehicle_and_set_its_reserve', 'chase@ottoyard.com');
-- @@ ledger 20260819161838
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819161838', 'schema_v2_service_objects_0043', 'chase@ottoyard.com');
-- @@ ledger 20260819161926
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819161926', 'canonical_kpis_0044', 'chase@ottoyard.com');
-- @@ ledger 20260819185342
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819185342', '0045a_twin_determinism_salt_and_telemetry', 'chase@ottoyard.com');
-- @@ ledger 20260819185611
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819185611', '0045b_twin_determinism_grid_energy_weather', 'chase@ottoyard.com');
-- @@ ledger 20260819185759
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819185759', '0045c_twin_determinism_bayfault_bess_dispatch', 'chase@ottoyard.com');
-- @@ ledger 20260819190050
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819190050', '0045d_twin_determinism_webhook_exception', 'chase@ottoyard.com');
-- @@ ledger 20260819190142
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819190142', '0045e_twin_cert_events_playback_ab_retention', 'chase@ottoyard.com');
-- @@ ledger 20260819190226
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819190226', '0046_site_alpha_pack_classes', 'chase@ottoyard.com');
-- @@ ledger 20260819192606
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819192606', '0047_twin_determinism_charge_session_salts', 'chase@ottoyard.com');
-- @@ ledger 20260819210107
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819210107', '0048_twin_service_flow_admit_order_and_deal_salts', 'chase@ottoyard.com');
-- @@ ledger 20260819211753
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819211753', '0049_twin_arm_refuse_move_clock_domain', 'chase@ottoyard.com');
-- @@ ledger 20260819221057
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819221057', '0050a_cursor_order_deployed_telemetry', 'chase@ottoyard.com');
-- @@ ledger 20260819221205
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819221205', '0050b_cursor_order_charge_sessions', 'chase@ottoyard.com');
-- @@ ledger 20260819221507
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819221507', '0050c_cursor_order_service_flow', 'chase@ottoyard.com');
-- @@ ledger 20260819221603
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819221603', '0050d_cursor_order_bay_fault', 'chase@ottoyard.com');
-- @@ ledger 20260819221809
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819221809', '0050e_cursor_order_exception_handler', 'chase@ottoyard.com');
-- @@ ledger 20260819231755
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819231755', 'twin_assigner_salt_and_tiebreak_0051a', 'chase@ottoyard.com');
-- @@ ledger 20260819231841
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819231841', 'twin_assigner_salt_and_tiebreak_0051b', 'chase@ottoyard.com');
-- @@ ledger 20260819233610
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819233610', 'twin_holdout_and_comms_run_relative_salts_0052a', 'chase@ottoyard.com');
-- @@ ledger 20260819233630
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260819233630', 'twin_holdout_and_comms_run_relative_salts_0052b', 'chase@ottoyard.com');
-- @@ ledger 20260820014345
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260820014345', 'benchmark_reset_config_residue_0053', 'chase@ottoyard.com');
-- @@ ledger 20260820031245
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260820031245', 'run_stable_cursor_order_full_sweep_0054', 'chase@ottoyard.com');
-- @@ ledger 20260820040308
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260820040308', 'manifest_run_relative_draw_salt_0055', 'chase@ottoyard.com');
-- @@ ledger 20260820042552
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260820042552', 'cuopt_propose_enabled_cert_quiesce_0056', 'chase@ottoyard.com');
-- @@ ledger 20260820121029
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260820121029', 'vehicle_state_trigger_preserve_caller_clock_0057', 'chase@ottoyard.com');
-- @@ ledger 20260822004802
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260822004802', 'cert_arm_pinned_sim_start', 'chase@ottoyard.com');
-- @@ ledger 20260822200504
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260822200504', 'cert_arm_finish_releases_tethers', 'chase@ottoyard.com');
-- @@ ledger 20260829160154
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829160154', 'provenance_says_what_it_is_0073', 'chase@ottoyard.com');
-- @@ ledger 20260829160215
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829160215', 'the_archive_carries_its_key_0074', 'chase@ottoyard.com');
-- @@ ledger 20260829162450
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829162450', 'refusals_carry_their_reason_0086', 'chase@ottoyard.com');
-- @@ ledger 20260829162640
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829162640', 'no_command_left_dangling_0087', 'chase@ottoyard.com');
-- @@ ledger 20260829162810
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829162810', 'occupied_refusals_reach_the_conflict_ledger_0088', 'chase@ottoyard.com');
-- @@ ledger 20260829164021
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829164021', 'a_leg_closes_with_its_work', 'chase@ottoyard.com');
-- @@ ledger 20260829164858
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829164858', 'cuopt_enactments_carry_their_verb', 'chase@ottoyard.com');
-- @@ ledger 20260829165759
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829165759', 'the_kernel_defends_the_verb', 'chase@ottoyard.com');
-- @@ ledger 20260829171141
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829171141', 'events_carry_their_run', 'chase@ottoyard.com');
-- @@ ledger 20260829171749
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829171749', 'a_run_leaves_no_plan_residue', 'chase@ottoyard.com');
-- @@ ledger 20260829171855
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829171855', 'canonical_means_constant_not_null', 'chase@ottoyard.com');
-- @@ ledger 20260829172404
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829172404', 'the_reset_keeps_a_whitelist_not_a_blacklist', 'chase@ottoyard.com');
-- @@ ledger 20260829172453
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829172453', 'target_soc_pins_to_the_seeded_constant', 'chase@ottoyard.com');
-- @@ ledger 20260829173602
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829173602', 'no_approval_outlives_its_run', 'chase@ottoyard.com');
-- @@ ledger 20260829214014
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829214014', 'the_drain_admission_is_not_a_coin_flip', 'chase@ottoyard.com');
-- @@ ledger 20260829214918
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829214918', 'the_latest_need_is_not_a_heap_order', 'chase@ottoyard.com');
-- @@ ledger 20260829215922
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829215922', 'service_flow_admissions_close_their_order', 'chase@ottoyard.com');
-- @@ ledger 20260829222635
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829222635', 'natural_completion_finalizes', 'chase@ottoyard.com');
-- @@ ledger 20260829222909
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829222909', 'finalize_at_the_driver_not_mid_world', 'chase@ottoyard.com');
-- @@ ledger 20260829223107
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829223107', 'the_live_completion_seam', 'chase@ottoyard.com');
-- @@ ledger 20260829230116
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829230116', '0104_the_tech_verdict_is_not_a_coin_from_another_run', 'chase@ottoyard.com');
-- @@ ledger 20260829230554
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829230554', '0105_the_cert_run_quiesces_the_llm_proposer', 'chase@ottoyard.com');
-- @@ ledger 20260829231202
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260829231202', '0106_the_production_brain_stands_off_a_cert_run', 'chase@ottoyard.com');
-- @@ ledger 20260830034718
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830034718', '0107_the_run_draws_its_own_world', 'chase@ottoyard.com');
-- @@ ledger 20260830035542
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830035542', '0108_the_atom_admission_closes_its_order', 'chase@ottoyard.com');
-- @@ ledger 20260830040601
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830040601', '0109_the_watermark_does_not_outlive_its_run', 'chase@ottoyard.com');
-- @@ ledger 20260830042119
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830042119', '0110_the_one_command_determinism_check', 'chase@ottoyard.com');
-- @@ ledger 20260830042328
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830042328', '0110b_pair_verdict_within_status_vocabulary', 'chase@ottoyard.com');
-- @@ ledger 20260830043106
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830043106', '0111_the_production_session_lifecycle', 'chase@ottoyard.com');
-- @@ ledger 20260830043153
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830043153', '0112_the_agent_gate_is_a_policy', 'chase@ottoyard.com');
-- @@ ledger 20260830044116
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830044116', '0113_the_switch_must_exist_before_it_can_be_off', 'chase@ottoyard.com');
-- @@ ledger 20260830050414
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830050414', 'the_release_takes_its_shape_from_the_feed', 'chase@ottoyard.com');
-- @@ ledger 20260830052403
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830052403', 'the_soc_state_belongs_to_the_run', 'chase@ottoyard.com');
-- @@ ledger 20260830053720
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830053720', 'the_reservations_timestamp_dies_with_it', 'chase@ottoyard.com');
-- @@ ledger 20260830055459
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830055459', 'the_runs_claims_die_with_it', 'chase@ottoyard.com');
-- @@ ledger 20260830131520
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830131520', 'the_clock_of_record_is_the_runs', 'chase@ottoyard.com');
-- @@ ledger 20260830134026
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830134026', 'the_coin_had_two_holds', 'chase@ottoyard.com');
-- @@ ledger 20260830135956
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830135956', 'the_whitelist_kept_a_moving_part', 'chase@ottoyard.com');
-- @@ ledger 20260830141928
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830141928', 'the_odometer_is_dealt_not_inherited', 'chase@ottoyard.com');
-- @@ ledger 20260830142542
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830142542', 'the_odometer_draw_calls_the_twin', 'chase@ottoyard.com');
-- @@ ledger 20260830165520
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830165520', 'the_sweep_reads_the_clock_the_stamp_was_written_in', 'chase@ottoyard.com');
-- @@ ledger 20260830182110
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830182110', 'the_latest_need_belongs_to_the_run', 'chase@ottoyard.com');
-- @@ ledger 20260830185547
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830185547', 'the_visit_ledger_belongs_to_the_run', 'chase@ottoyard.com');
-- @@ ledger 20260830213611
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830213611', 'the_pair_reads_its_own_boot_state', 'chase@ottoyard.com');
-- @@ ledger 20260830213715
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830213715', 'the_dead_enactor_is_archived', 'chase@ottoyard.com');
-- @@ ledger 20260830214923
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830214923', 'the_teardown_retires_the_interrupted', 'chase@ottoyard.com');
-- @@ ledger 20260830221659
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260830221659', 'the_adoption_pick_gains_its_content_keys', 'chase@ottoyard.com');
-- @@ ledger 20260831000801
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260831000801', 'every_pick_orders_itself_completely', 'chase@ottoyard.com');
-- @@ ledger 20260831012206
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260831012206', 'the_deferral_queue_orders_itself_completely', 'chase@ottoyard.com');
-- @@ ledger 20260831020239
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260831020239', 'the_matrix_reads_itself_from_the_ledger', 'chase@ottoyard.com');
-- @@ ledger 20260831133729
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260831133729', 'the_power_cap_is_a_constraint', 'chase@ottoyard.com');
-- @@ ledger 20260831150515
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260831150515', 'the_energy_path_joins_the_certification', 'chase@ottoyard.com');
-- @@ ledger 20260831182816
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260831182816', 'the_energy_path_reads_only_its_own_run', 'chase@ottoyard.com');
-- @@ ledger 20260831185034
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260831185034', 'the_battery_starts_cold_and_the_fingerprint_sees_it', 'chase@ottoyard.com');
-- @@ ledger 20260831202425
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260831202425', 'the_site_limit_is_an_input', 'chase@ottoyard.com');
-- @@ ledger 20260831231230
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260831231230', 'the_fingerprint_stops_hashing_a_write_timestamp', 'chase@ottoyard.com');
-- @@ ledger 20260901002249
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901002249', 'the_demand_we_cause_carries_the_run_id', 'chase@ottoyard.com');
-- @@ ledger 20260901005506
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901005506', 'the_matrix_knows_when_it_went_stale', 'chase@ottoyard.com');
-- @@ ledger 20260901010048
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901010048', 'the_floor_reads_the_ledger_for_every_caller', 'chase@ottoyard.com');
-- @@ ledger 20260901010305
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901010305', 'a_migration_classifies_itself', 'chase@ottoyard.com');
-- @@ ledger 20260901011004
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901011004', 'the_end_state_is_part_of_the_verdict', 'chase@ottoyard.com');
-- @@ ledger 20260901011644
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901011644', 'a_short_arm_is_inconclusive_and_a_streak_starts_at_the_floor', 'chase@ottoyard.com');
-- @@ ledger 20260901075119
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901075119', 'the_reset_stamp_leaves_the_wall_clock', 'chase@ottoyard.com');
-- @@ ledger 20260901135321
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901135321', 'the_preflight_validator_reads_only_its_own_run', 'chase@ottoyard.com');
-- @@ ledger 20260901172745
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901172745', 'the_load_sum_reads_only_its_own_run_and_depot', 'chase@ottoyard.com');
-- @@ ledger 20260901182823
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901182823', 'the_noise_salt_is_not_a_random_id', 'chase@ottoyard.com');
-- @@ ledger 20260901234940
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901234940', 'the_verdict_sorts_by_every_field_it_hashes_and_hears_the_energy_stream', 'chase@ottoyard.com');
-- @@ ledger 20260901235044
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260901235044', 'the_matrix_is_keyed_by_depot_and_reads_the_energy_canon', 'chase@ottoyard.com');
-- @@ ledger 20260902121232
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902121232', 'the_odometer_sums_only_its_own_run', 'chase@ottoyard.com');
-- @@ ledger 20260902121253
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902121253', 'the_fleet_api_returns_only_production_commands', 'chase@ottoyard.com');
-- @@ ledger 20260902121334
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902121334', 'the_certification_runs_the_deterministic_core_alone', 'chase@ottoyard.com');
-- @@ ledger 20260902124926
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902124926', 'a_grid_fixture_the_engine_cannot_tell_from_a_depot', 'chase@ottoyard.com');
-- @@ ledger 20260902125859
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902125859', 'the_assertion_matched_a_key_only_one_verb_carries', 'chase@ottoyard.com');
-- @@ ledger 20260902190425
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902190425', 'the_site_meter_reports_the_power_that_flowed', 'chase@ottoyard.com');
-- @@ ledger 20260902191145
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902191145', 'a_point_that_fits_beats_a_point_that_starves', 'chase@ottoyard.com');
-- @@ ledger 20260902191331
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902191331', 'the_assertions_state_the_rule_the_engine_actually_has', 'chase@ottoyard.com');
-- @@ ledger 20260902194149
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902194149', 'the_sixth_kpi_did_the_asset_make_its_due_time', 'chase@ottoyard.com');
-- @@ ledger 20260902194751
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902194751', 'wait_or_take_what_fits_is_a_policy_not_a_constant', 'chase@ottoyard.com');
-- @@ ledger 20260902195045
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902195045', 'the_need_check_learns_about_holds_and_reservations', 'chase@ottoyard.com');
-- @@ ledger 20260902195148
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902195148', 'repair_0160_the_anchor_must_be_unique_not_merely_present', 'chase@ottoyard.com');
-- @@ ledger 20260902195819
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902195819', 'the_grid_can_be_broken_on_purpose_and_must_prove_it', 'chase@ottoyard.com');
-- @@ ledger 20260902200201
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902200201', 'a_declared_fault_is_part_of_the_seeded_world', 'chase@ottoyard.com');
-- @@ ledger 20260902200406
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902200406', 'a_fault_needs_a_clock_and_a_repair_time', 'chase@ottoyard.com');
-- @@ ledger 20260902200433
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902200433', 'drop_the_two_arg_grid_fault_overload', 'chase@ottoyard.com');
-- @@ ledger 20260902200851
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902200851', 'the_fault_assertion_learns_that_faults_end', 'chase@ottoyard.com');
-- @@ ledger 20260902201059
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902201059', 'starved_means_below_its_own_target_not_below_ninety', 'chase@ottoyard.com');
-- @@ ledger 20260902205647
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902205647', 'the_run_key_hashed_the_outcome_and_the_wait_was_always_zero', 'chase@ottoyard.com');
-- @@ ledger 20260902234153
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902234153', 'the_kpi_view_recomputed_every_run_to_answer_about_one', 'chase@ottoyard.com');
-- @@ ledger 20260902235023
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902235023', 'unserved_counted_the_horizon_not_the_engine', 'chase@ottoyard.com');
-- @@ ledger 20260902235218
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260902235218', 'the_plan_lookup_reached_back_past_its_own_return', 'chase@ottoyard.com');
-- @@ ledger 20260903003438
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903003438', 'a_return_stamped_after_the_run_ended_never_happened', 'chase@ottoyard.com');
-- @@ ledger 20260903023713
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903023713', 'the_overnight_planner_had_nashville_baked_in', 'chase@ottoyard.com');
-- @@ ledger 20260903024009
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903024009', 'a_rule_that_cannot_fire_should_not_look_like_one_that_enforces', 'chase@ottoyard.com');
-- @@ ledger 20260903025526
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903025526', 'the_engine_can_say_it_found_nothing_but_not_that_it_never_looked', 'chase@ottoyard.com');
-- @@ ledger 20260903031500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903031500', 'the_pair_and_the_scenario_must_name_the_same_world', 'chase@ottoyard.com');
-- @@ ledger 20260903034836
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903034836', 'a_deadline_past_the_end_of_the_run_was_never_missed', 'chase@ottoyard.com');
-- @@ ledger 20260903035049
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903035049', 'an_asset_that_arrived_on_the_last_tick_never_had_a_turn', 'chase@ottoyard.com');
-- @@ ledger 20260903075250
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903075250', 'the_recorder_wrote_a_status_the_table_refused', 'chase@ottoyard.com');
-- @@ ledger 20260903113902
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903113902', 'the_cold_start_guard_looked_at_every_depot', 'chase@ottoyard.com');
-- @@ ledger 20260903171637
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903171637', 'the_watermark_sweep_cleared_every_depot', 'chase@ottoyard.com');
-- @@ ledger 20260903225200
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903225200', 'the_teardown_recorded_a_return_that_never_happened', 'chase@ottoyard.com');
-- @@ ledger 20260903225512
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903225512', 'kpi_one_reported_more_hours_than_the_window_could_hold', 'chase@ottoyard.com');
-- @@ ledger 20260903230222
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903230222', 'kpi_two_counted_a_booking_nobody_kept_as_a_turn', 'chase@ottoyard.com');
-- @@ ledger 20260903230800
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260903230800', 'kpi_four_divided_by_the_same_bad_denominator', 'chase@ottoyard.com');
-- @@ ledger 20260904013402
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260904013402', 'the_correction_nobody_could_see_from_the_one_command', 'chase@ottoyard.com');
-- @@ ledger 20260904013840
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260904013840', 'the_hours_were_filed_under_a_day_they_did_not_happen_on', 'chase@ottoyard.com');
-- @@ ledger 20260904014708
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260904014708', 'the_kpi_that_scanned_two_and_a_half_million_rows_per_call', 'chase@ottoyard.com');
-- @@ ledger 20260904015708
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260904015708', 'the_percentile_that_dropped_its_worst_cases', 'chase@ottoyard.com');
-- @@ ledger 20260904015843
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260904015843', 'the_population_reaches_the_command_that_ships_the_number', 'chase@ottoyard.com');
-- @@ ledger 20260904020600
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260904020600', 'the_index_that_closed_the_unattributed_five_seconds', 'chase@ottoyard.com');
-- @@ ledger 20260904140914
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260904140914', 'a_baseline_to_measure_ourselves_against', 'chase@ottoyard.com');
-- @@ ledger 20260907213653
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260907213653', '0208_the_verdict_sees_what_the_shield_read', 'chase@ottoyard.com');
-- @@ ledger 20260908081848
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908081848', 'the_settlement_record_binds_to_whichever_booking_the_heap_returned_first', 'chase@ottoyard.com');
-- @@ ledger 20260908082227
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908082227', 'the_verdict_sees_the_settlement_record_and_h_rcl_may_now_fail_a_pair', 'chase@ottoyard.com');
-- @@ ledger 20260908084304
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908084304', 'h_sdr_hashed_a_signature_computed_over_a_run_scoped_id', 'chase@ottoyard.com');
-- @@ ledger 20260908111547
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908111547', 'h_sdr_may_now_fail_a_pair', 'chase@ottoyard.com');
-- @@ ledger 20260908111702
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908111702', 'kpi_four_counted_seven_actor_types_that_cannot_exist', 'chase@ottoyard.com');
-- @@ ledger 20260908111846
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908111846', 'the_schedule_task_emitter_asks_the_stall_what_kind_of_charge_it_was', 'chase@ottoyard.com');
-- @@ ledger 20260908111950
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908111950', 'the_run_scope_predicate_no_index_can_read', 'chase@ottoyard.com');
-- @@ ledger 20260908112038
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908112038', 'the_fingerprint_hashed_a_million_rows_to_report_thirteen', 'chase@ottoyard.com');
-- @@ ledger 20260908133954
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908133954', 'the_load_meter_asks_which_run_is_running_once_per_row', 'chase@ottoyard.com');
-- @@ ledger 20260908134109
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908134109', 'the_refusal_reactor_says_production_and_hands_you_a_sim_run_id', 'chase@ottoyard.com');
-- @@ ledger 20260908161239
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908161239', 'the_recert_floor_reads_a_name_the_ledger_never_writes', 'chase@ottoyard.com');
-- @@ ledger 20260908161615
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908161615', 'the_canon_comparison_sees_every_atom_the_pair_enforces', 'chase@ottoyard.com');
-- @@ ledger 20260908161809
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908161809', 'the_load_meter_scans_forty_five_thousand_rows_to_sum_three_hundred', 'chase@ottoyard.com');
-- @@ ledger 20260908162004
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908162004', 'provenance_asks_the_depot_not_the_run_id', 'chase@ottoyard.com');
-- @@ ledger 20260908204137
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908204137', 'the_approach_band_scans_every_run_to_answer_about_one', 'chase@ottoyard.com');
-- @@ ledger 20260908220518
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908220518', 'a_score_that_cannot_be_gamed_by_not_checking', 'chase@ottoyard.com');
-- @@ ledger 20260908222953
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908222953', 'a_comparative_score_may_read_only_what_every_arm_writes', 'chase@ottoyard.com');
-- @@ ledger 20260908224618
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260908224618', 'a_vehicle_the_arm_is_holding_is_not_a_candidate', 'chase@ottoyard.com');
-- @@ ledger 20260909003956
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909003956', 'a_session_may_only_be_closed_on_its_own_timeline', 'chase@ottoyard.com');
-- @@ ledger 20260909004734
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909004734', 'the_tether_is_run_written_residue_too', 'chase@ottoyard.com');
-- @@ ledger 20260909015606
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909015606', 'the_ab_rig_takes_a_clock_anchor_and_ignores_it', 'chase@ottoyard.com');
-- @@ ledger 20260909021833
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909021833', 'a_proposal_must_know_which_tick_it_was_made_in', 'chase@ottoyard.com');
-- @@ ledger 20260909022308
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909022308', 'record_and_replay_an_agent_proposal_stream', 'chase@ottoyard.com');
-- @@ ledger 20260909031507
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909031507', 'the_proposal_selector_orders_by_a_clock_that_does_not_tick', 'chase@ottoyard.com');
-- @@ ledger 20260909032347
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909032347', 'a_certification_that_replays_a_recorded_agent_stream', 'chase@ottoyard.com');
-- @@ ledger 20260909051802
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909051802', 'the_gate_that_opens_the_nvidia_door_leaves_a_ledger_row_v2', 'chase@ottoyard.com');
-- @@ ledger 20260909051917
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909051917', 'a_certification_hears_only_the_proposers_it_certified', 'chase@ottoyard.com');
-- @@ ledger 20260909052026
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909052026', 'a_capture_records_only_what_the_run_cannot_regenerate', 'chase@ottoyard.com');
-- @@ ledger 20260909060909
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909060909', '0243_the_start_of_run_world_hash_cannot_see_a_vehicle_mid_tether', 'chase@ottoyard.com');
-- @@ ledger 20260909075534
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909075534', '0244_the_end_state_fingerprint_cannot_see_the_assets_either', 'chase@ottoyard.com');
-- @@ ledger 20260909075605
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909075605', '0245_current_depot_id_is_written_in_the_tick_and_cleared_by_nothing', 'chase@ottoyard.com');
-- @@ ledger 20260909094627
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909094627', '0246_the_world_hash_is_id_blind_everywhere_except_inside_config', 'chase@ottoyard.com');
-- @@ ledger 20260909133254
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909133254', '0247_a_dead_runs_working_rows_outlive_it_because_nothing_deletes_them', 'chase@ottoyard.com');
-- @@ ledger 20260909133442
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909133442', '0248_the_refusal_ledger_was_registered_engine_without_the_key_that_makes_it_true', 'chase@ottoyard.com');
-- @@ ledger 20260909133615
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909133615', '0249_the_purge_loop_variable_shadowed_the_table_it_was_selecting_from', 'chase@ottoyard.com');
-- @@ ledger 20260909134546
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260909134546', '0250_the_engine_class_is_not_a_delete_list_and_it_holds_the_moat', 'chase@ottoyard.com');
-- @@ ledger 20260912033615
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912033615', '0252_a_certification_column_nobody_schedules_is_invisible', 'chase@ottoyard.com');
-- @@ ledger 20260912033843
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912033843', '0253_sm006_points_at_a_five_argument_evaluator_and_the_dispatcher_passes_four', 'chase@ottoyard.com');
-- @@ ledger 20260912034252
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912034252', '0251_a_purged_run_must_say_gone_not_zero', 'chase@ottoyard.com');
-- @@ ledger 20260912035032
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912035032', '0254_the_world_hash_moved_and_could_not_say_where', 'chase@ottoyard.com');
-- @@ ledger 20260912130622
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912130622', '0255_the_teardown_stamps_the_wall_clock_into_a_hashed_column', 'chase@ottoyard.com');
-- @@ ledger 20260912165023
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912165023', '0256_the_trigger_restamps_what_the_teardown_fixed', 'chase@ottoyard.com');
-- @@ ledger 20260912165137
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912165137', '0257_the_second_floor_ships_as_a_count_with_its_own_limits_attached', 'chase@ottoyard.com');
-- @@ ledger 20260912165243
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912165243', '0258_the_comment_states_the_invariant_and_no_code_holds_it', 'chase@ottoyard.com');
-- @@ ledger 20260912205202
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912205202', '0259_the_proposer_seat_is_declared_data_not_three_literals', 'chase@ottoyard.com');
-- @@ ledger 20260912205301
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912205301', '0260_every_proposer_fire_is_a_ledger_row', 'chase@ottoyard.com');
-- @@ ledger 20260912233647
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260912233647', '0261_the_policy_is_what_proposes_the_kernel_disposes', 'chase@ottoyard.com');
-- @@ ledger 20260913011239
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913011239', '0262_the_hold_key_the_setter_refused', 'chase@ottoyard.com');
-- @@ ledger 20260913122605
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913122605', '0265_the_frame_carries_what_the_selector_filters_on', 'chase@ottoyard.com');
-- @@ ledger 20260913135634
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913135634', '0266_the_canon_stops_being_hostage_to_another_runs_leftovers', 'chase@ottoyard.com');
-- @@ ledger 20260913141438
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913141438', '0267_the_fire_log_registered_a_stamp_and_never_bound_it_to_a_run', 'chase@ottoyard.com');
-- @@ ledger 20260913142959
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913142959', '0268_0267_never_classified_itself_and_the_floor_swallowed_every_column', 'chase@ottoyard.com');
-- @@ ledger 20260913205636
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913205636', '0269_the_purge_cannot_see_a_scheduled_round_only_a_running_pair', 'chase@ottoyard.com');
-- @@ ledger 20260913225716
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913225716', '0270_the_only_queue_depth_rule_crashes_on_two_states_that_do_not_exist', 'chase@ottoyard.com');
-- @@ ledger 20260913231758
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913231758', 'the_outbound_command_stream_is_the_only_stream_without_provenance', 'chase@ottoyard.com');
-- @@ ledger 20260913232252
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913232252', '0272_0271_never_classified_itself_and_the_floor_swallowed_every_column', 'chase@ottoyard.com');
-- @@ ledger 20260913233201
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913233201', '0273_the_uplink_is_written_by_the_same_transaction_as_the_downlink', 'chase@ottoyard.com');
-- @@ ledger 20260913234605
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260913234605', '0274_there_is_no_queue_so_the_asset_cannot_be_told_its_place_in_one', 'chase@ottoyard.com');
-- @@ ledger 20260914001937
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914001937', '0275_no_single_place_says_which_intelligence_sources_are_actually_on', 'chase@ottoyard.com');
-- @@ ledger 20260914005147
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914005147', '0276_cpsat_enacted_three_times_and_the_scoreboard_called_it_a_stranger', 'chase@ottoyard.com');
-- @@ ledger 20260914012023
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914012023', '0277_a_source_that_has_proposed_and_one_that_has_never_existed_read_the_same', 'chase@ottoyard.com');
-- @@ ledger 20260914040338
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914040338', '0278_arming_the_agentic_layer_is_a_five_key_hand_ritual_and_the_demo_got_four', 'chase@ottoyard.com');
-- @@ ledger 20260914040837
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914040837', '0279_the_dial_that_can_kill_a_certification_arm_is_not_in_the_catalog', 'chase@ottoyard.com');
-- @@ ledger 20260914043322
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914043322', '0280_a_tamper_check_that_cannot_tell_tampering_from_a_fresh_uuid', 'chase@ottoyard.com');
-- @@ ledger 20260914054506
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914054506', '0281_the_setter_refuses_ninety_two_of_the_keys_the_engine_reads', 'chase@ottoyard.com');
-- @@ ledger 20260914061049
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914061049', '0282_two_dials_whose_ranges_the_database_already_declares', 'chase@ottoyard.com');
-- @@ ledger 20260914062112
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914062112', '0283_five_floors_the_engine_already_writes_down_and_two_ceilings_it_does_not', 'chase@ottoyard.com');
-- @@ ledger 20260914064710
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914064710', '0284_a_hold_whose_outcome_is_invisible_can_only_be_argued_about', 'chase@ottoyard.com');
-- @@ ledger 20260914065559
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914065559', '0285_nine_more_dials_and_two_ceilings_the_rng_declares', 'chase@ottoyard.com');
-- @@ ledger 20260914071810
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914071810', '0286_eleven_dials_and_the_ceiling_a_check_constraint_hands_you', 'chase@ottoyard.com');
-- @@ ledger 20260914073900
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914073900', '0287_the_two_halves_disagree_about_what_already_placed_means', 'chase@ottoyard.com');
-- @@ ledger 20260914081939
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914081939', '0289_five_gates_and_the_one_that_tests_a_different_threshold', 'chase@ottoyard.com');
-- @@ ledger 20260914083734
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914083734', '0290_three_geometry_dials_and_one_the_catalog_cannot_express', 'chase@ottoyard.com');
-- @@ ledger 20260914085632
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914085632', '0291_eighteen_dials_whose_consumer_already_wrote_the_range', 'chase@ottoyard.com');
-- @@ ledger 20260914090954
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914090954', '0292_the_proposer_cannot_see_its_own_pending_plans', 'chase@ottoyard.com');
-- @@ ledger 20260914093107
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914093107', '0293_the_nightly_run_purge_has_never_once_run', 'chase@ottoyard.com');
-- @@ ledger 20260914094551
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914094551', '0294_the_purge_commits_inside_a_cursor_loop', 'chase@ottoyard.com');
-- @@ ledger 20260914095529
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914095529', '0295_a_procedure_with_a_set_clause_cannot_commit', 'chase@ottoyard.com');
-- @@ ledger 20260914101744
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914101744', '0296_the_gap_view_cannot_see_five_of_its_own_call_sites', 'chase@ottoyard.com');
-- @@ ledger 20260914102812
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914102812', '0297_seven_gates_whose_range_is_the_comparison_itself', 'chase@ottoyard.com');
-- @@ ledger 20260914103801
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914103801', '0298_four_hours_three_probabilities_and_a_dial_that_is_half_wired', 'chase@ottoyard.com');
-- @@ ledger 20260914104618
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914104618', '0299_a_dial_that_defaults_for_a_checked_column_inherits_the_check', 'chase@ottoyard.com');
-- @@ ledger 20260914105135
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914105135', '0300_three_dials_whose_floor_is_on_the_other_side_of_the_assignment', 'chase@ottoyard.com');
-- @@ ledger 20260914105943
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914105943', '0301_five_files_never_classified_themselves_and_the_floor_swallowed_every_column', 'chase@ottoyard.com');
-- @@ ledger 20260914121021
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914121021', '0302_the_only_agent_that_tunes_dials_is_the_one_that_bypasses_the_catalog', 'chase@ottoyard.com');
-- @@ ledger 20260914122818
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914122818', '0303_a_bound_that_cannot_be_clamped_must_refuse', 'chase@ottoyard.com');
-- @@ ledger 20260914124522
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914124522', '0304_five_more_floors_and_six_dials_admitted_without_a_clamp', 'chase@ottoyard.com');
-- @@ ledger 20260914125444
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914125444', '0305_the_catalog_becomes_the_allow_list_for_every_writer', 'chase@ottoyard.com');
-- @@ ledger 20260914131308
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914131308', '0306_a_null_dial_value_silently_wrote_the_maximum', 'chase@ottoyard.com');
-- @@ ledger 20260914134225
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914134225', '0307_the_dial_audit_reads_functions_and_never_looked_at_a_view', 'chase@ottoyard.com');
-- @@ ledger 20260914144046
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914144046', '0308_the_loop_may_not_tune_a_depot_the_harness_certifies_on', 'chase@ottoyard.com');
-- @@ ledger 20260914144547
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914144547', '0309_benchmark_had_everything_except_a_scenario', 'chase@ottoyard.com');
-- @@ ledger 20260914150516
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914150516', '0310_two_migrations_argued_forces_recert_false_and_never_wrote_the_row', 'chase@ottoyard.com');
-- @@ ledger 20260914153500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914153500', '0311_a_column_that_looks_like_the_price_and_is_not', 'chase@ottoyard.com');
-- @@ ledger 20260914161504
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914161504', '0312_the_forward_curve_reads_the_soc_the_twin_already_tracks', 'chase@ottoyard.com');
-- @@ ledger 20260914163515
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914163515', '0313_the_predictive_recall_rung_takes_eight_values_and_none_of_them_is_the_vehicle', 'chase@ottoyard.com');
-- @@ ledger 20260914164237
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914164237', '0314_vehicles_get_a_position_and_the_eta_stops_being_a_constant', 'chase@ottoyard.com');
-- @@ ledger 20260914164649
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914164649', '0315_the_speed_cancelled_out_of_my_own_eta', 'chase@ottoyard.com');
-- @@ ledger 20260914165752
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914165752', '0316_the_eta_function_starts_answering_its_own_arguments', 'chase@ottoyard.com');
-- @@ ledger 20260914170416
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914170416', '0317_the_twin_writes_where_each_asset_is_not_only_how_charged', 'chase@ottoyard.com');
-- @@ ledger 20260914170807
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914170807', '0318_the_engine_stopped_guessing_and_the_label_kept_saying_guess', 'chase@ottoyard.com');
-- @@ ledger 20260914171845
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914171845', '0319_i_seeded_a_deterministic_draw_on_a_random_uuid', 'chase@ottoyard.com');
-- @@ ledger 20260914192115
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914192115', '0320_one_function_writes_the_return_eta_and_writes_its_label_with_it', 'chase@ottoyard.com');
-- @@ ledger 20260914192306
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914192306', '0321_each_writer_of_the_eta_states_its_own_provenance_and_active_vehicles_get_a_forecast', 'chase@ottoyard.com');
-- @@ ledger 20260914192410
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914192410', '0322_the_eta_and_its_provenance_move_together_or_the_write_is_refused', 'chase@ottoyard.com');
-- @@ ledger 20260914192648
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914192648', '0323_nothing_that_starts_a_run_ever_armed_the_agentic_layer', 'chase@ottoyard.com');
-- @@ ledger 20260914192738
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914192738', '0324_the_one_world_guard_says_this_depot_and_has_no_depot_predicate', 'chase@ottoyard.com');
-- @@ ledger 20260914193928
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914193928', '0326_the_stamp_must_be_present_and_not_older_not_different', 'chase@ottoyard.com');
-- @@ ledger 20260914214010
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914214010', '0325_energy_commands_get_the_dock_that_vehicle_commands_already_have', 'chase@ottoyard.com');
-- @@ ledger 20260914214102
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914214102', '0327_the_ledger_comment_claims_a_protection_that_has_never_existed', 'chase@ottoyard.com');
-- @@ ledger 20260914235653
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260914235653', '0328_the_conflict_ledger_records_who_was_there_and_not_what_they_were_doing', 'chase@ottoyard.com');
-- @@ ledger 20260915001355
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260915001355', '0329_the_departure_release_covers_five_of_the_flagships_one_hundred_and_fifty_eight_stalls', 'chase@ottoyard.com');
-- @@ ledger 20260916000638
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260916000638', 'the_agent_hands_one_solver_request_to_the_kernel', 'chase@ottoyard.com');
-- @@ ledger 20260916002025
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260916002025', 'one_agent_claim_per_run_tick', 'chase@ottoyard.com');
-- @@ ledger 20260916144203
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260916144203', 'every_solver_proposal_gets_a_deterministic_disposition', 'chase@ottoyard.com');
-- @@ ledger 20260916180920
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260916180920', 'a_newer_solver_packet_explains_what_it_superseded', 'chase@ottoyard.com');
-- @@ ledger 20260916194021
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260916194021', 'cp_sat_becomes_the_primary_agent_solver', 'chase@ottoyard.com');
-- @@ ledger 20260917122803
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260917122803', 'the_proposal_finalizer_accepts_the_kernel_tick_type', 'chase@ottoyard.com');
-- @@ ledger 20260917123453
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260917123453', 'the_agent_chain_gets_first_refusal_before_greedy_dispatch', 'chase@ottoyard.com');
-- @@ ledger 20260917124150
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260917124150', 'one_inflight_agent_gets_a_bounded_solver_window', 'chase@ottoyard.com');
-- @@ ledger 20260919042514
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919042514', 'the_charge_stall_was_reserved_before_any_solver_could_see_it', 'chase@ottoyard.com');
-- @@ ledger 20260919045051
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919045051', 'every_external_model_call_gets_a_ledger_that_outlives_its_run', 'chase@ottoyard.com');
-- @@ ledger 20260919045936
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919045936', 'the_intelligence_view_dropped_two_thirds_of_its_own_rows', 'chase@ottoyard.com');
-- @@ ledger 20260919052746
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919052746', 'the_agent_never_learns_what_the_kernel_did_with_its_objective', 'chase@ottoyard.com');
-- @@ ledger 20260919053350
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919053350', 'the_review_joined_on_the_tick_and_the_chain_crosses_ticks', 'chase@ottoyard.com');
-- @@ ledger 20260919154650
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919154650', 'the_purge_cannot_complete_and_the_twin_start_door_has_no_handler', 'chase@ottoyard.com');
-- @@ ledger 20260919155936
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919155936', 'the_purge_deletes_engine_tables_alphabetically_not_by_dependency', 'chase@ottoyard.com');
-- @@ ledger 20260919161129
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919161129', '0330_sweep_two_asks_if_the_vehicle_is_in_the_stall_and_never_if_it_is_coming', 'chase@ottoyard.com');
-- @@ ledger 20260919161259
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919161259', 'the_cockpits_solver_join_has_never_matched_a_row', 'chase@ottoyard.com');
-- @@ ledger 20260919163943
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919163943', 'one_missing_index_made_the_twin_start_door_cost_six_thousand_gigabytes', 'chase@ottoyard.com');
-- @@ ledger 20260919170057
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919170057', 'a_six_row_table_held_the_twin_start_door_shut_because_its_guard_never_learned_the_purge_protocol', 'chase@ottoyard.com');
-- @@ ledger 20260919173442
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919173442', 'a_run_reads_armed_while_its_rank_zero_proposer_is_unreachable', 'chase@ottoyard.com');
-- @@ ledger 20260919185656
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919185656', 'the_agent_orchestrates_a_depot_from_eleven_hundred_characters_of_counters_part1_depth_function', 'chase@ottoyard.com');
-- @@ ledger 20260919191701
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919191701', 'the_agent_orchestrates_a_depot_from_eleven_hundred_characters_of_counters', 'chase@ottoyard.com');
-- @@ ledger 20260919195941
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919195941', 'the_intelligence_layers_are_real_and_nothing_assembles_them_into_a_stack', 'chase@ottoyard.com');
-- @@ ledger 20260919205659
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919205659', 'the_agents_dial_limits_live_in_edge_typescript_and_not_in_this_database', 'chase@ottoyard.com');
-- @@ ledger 20260919210336
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919210336', 'the_shield_gains_a_fifth_probe_point_and_the_ai_write_path_finally_lands_in_its_ledger', 'chase@ottoyard.com');
-- @@ ledger 20260919224417
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919224417', 'the_review_judged_the_whole_run_from_three_chains_and_a_ledger_that_never_held_cuopt', NULL);
-- @@ ledger 20260919235525
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919235525', 'the_energy_shield_declared_five_block_rules_at_the_moment_power_flows_and_none_had_ever_run', NULL);
-- @@ ledger 20260919235738
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260919235738', 'the_shield_finally_sees_the_moment_power_begins', NULL);
-- @@ ledger 20260920004021
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920004021', 'the_booking_calendar_keeps_three_timestamps_on_two_clocks_and_says_so_nowhere', NULL);
-- @@ ledger 20260920005644
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920005644', 'a_single_stall_proposal_gives_the_disposer_nothing_to_dispose_over', NULL);
-- @@ ledger 20260920010111
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920010111', 'a_promoted_candidate_must_carry_its_own_kilowatts_or_the_shield_judges_the_wrong_load', NULL);
-- @@ ledger 20260920022145
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920022145', 'a_stall_reservation_outlives_the_vehicle_that_can_no_longer_use_it', NULL);
-- @@ ledger 20260920023610
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920023610', 'a_proposer_that_declines_is_not_a_proposer_that_named_a_bad_stall', NULL);
-- @@ ledger 20260920024530
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920024530', 'a_worse_ranked_proposer_removes_a_better_one_from_the_pool_before_rank_is_read', NULL);
-- @@ ledger 20260920025230
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920025230', 'the_gate_0362_installed_could_never_be_opened', NULL);
-- @@ ledger 20260920033500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920033500', 'the_overstay_has_a_name_and_no_reader_so_give_it_one', NULL);
-- @@ ledger 20260920034500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920034500', 'the_frame_now_says_which_vehicles_are_overstaying_a_charge_stall', NULL);
-- @@ ledger 20260920035200
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920035200', 'a_proposers_hit_rate_is_deleted_by_the_next_run_that_starts', NULL);
-- @@ ledger 20260920041236
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920041236', 'the_reroute_hunted_the_scarcest_stall_type_for_vehicles_that_wanted_the_most_plentiful', NULL);
-- @@ ledger 20260920041500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920041500', 'the_reclaimer_0360_installed_has_never_run_on_the_live_metronome_path', NULL);
-- @@ ledger 20260920041750
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920041750', 'a_vehicle_parked_in_one_stall_was_still_holding_another', NULL);
-- @@ ledger 20260920042835
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920042835', 'fifty_nine_calendar_claims_were_already_overruled_and_the_ledger_held_none_of_them', NULL);
-- @@ ledger 20260920043723
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920043723', 'i_put_a_nondeterminism_source_inside_the_tick_path_taking_it_back_out', NULL);
-- @@ ledger 20260920045844
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920045844', 'the_shared_candidate_source_offered_charge_stalls_whose_charger_was_faulted', NULL);
-- @@ ledger 20260920050351
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920050351', 'three_comments_that_stop_the_next_person_repeating_tonight', NULL);
-- @@ ledger 20260920123000
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920123000', 'two_legal_decisions_summed_past_the_service_contract_and_the_meter_that_would_have_seen_it_is_not_read', NULL);
-- @@ ledger 20260920124500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920124500', 'my_own_new_column_says_throttle_the_vehicles_when_the_answer_is_defer_the_battery', NULL);
-- @@ ledger 20260920131500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920131500', 'i_built_a_detector_whose_silence_cannot_be_told_from_absence_which_is_the_defect_i_spent_tonight_fixing', NULL);
-- @@ ledger 20260920132449
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920132449', 'the_engine_exceeding_its_own_published_budget_is_only_observable_at_tick_time', NULL);
-- @@ ledger 20260920132500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920132500', 'removing_the_one_row_my_own_path_test_left_in_an_evidence_table', NULL);
-- @@ ledger 20260920134500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920134500', 'the_entire_causal_record_of_the_excursion_is_class_engine_and_dies_with_the_next_demo_run', NULL);
-- @@ ledger 20260920135731
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920135731', 'joining_an_evidence_table_to_sim_runs_silently_undoes_the_reason_it_is_evidence', NULL);
-- @@ ledger 20260920141533
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920141533', 'the_published_reliability_field_names_an_action_that_never_happened_and_undercounts_the_one_that_did', NULL);
-- @@ ledger 20260920155947
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920155947', 'a_column_named_for_a_fifteen_minute_quantity_that_is_a_running_peak_in_sim_and_not_even_that_in_production', NULL);
-- @@ ledger 20260920161631
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920161631', 'the_whole_of_g86_is_one_concurrency_class_that_no_executor_admits_and_the_walkaround_is_its_only_member', NULL);
-- @@ ledger 20260920162559
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920162559', 'my_own_new_detector_raises_on_the_malformed_data_it_exists_to_find', NULL);
-- @@ ledger 20260920172340
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920172340', 'the_catch_up_that_stopped_one_state_short_strands_a_vehicle_for_the_whole_run', NULL);
-- @@ ledger 20260920173700
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920173700', 'the_fourteen_atom_verdict_is_the_one_thing_the_permanent_run_record_does_not_keep', NULL);
-- @@ ledger 20260920185425
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920185425', 'two_critical_state_machine_rules_had_a_caller_shaped_hole_and_the_input_they_need_did_not_exist', NULL);
-- @@ ledger 20260920185739
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920185739', 'my_own_new_probe_writes_blocked_into_a_log_where_that_word_means_something_it_did_not_do', NULL);
-- @@ ledger 20260920194102
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260920194102', 'cp_sat_was_told_the_site_could_draw_2500_kw_while_the_engine_was_enforcing_795', NULL);
-- @@ ledger 20260921000517
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921000517', 'an_abstention_is_not_a_claim_and_two_predicates_counted_it_as_one', NULL);
-- @@ ledger 20260921001618
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921001618', 'kpi_four_stops_counting_the_shields_own_safe_defaults_as_human_labour', NULL);
-- @@ ledger 20260921002608
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921002608', 'the_shields_coverage_was_only_ever_counted_from_the_rules_side_so_two_enacting_branches_were_invisible', NULL);
-- @@ ledger 20260921004457
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921004457', 'the_branch_i_led_0392_with_is_gated_at_a_probe_point_i_did_not_look_for', NULL);
-- @@ ledger 20260921005249
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921005249', 'shield_expected_was_the_wrong_question_an_hour_after_i_shipped_it_ask_which_effects_are_gated_where', NULL);
-- @@ ledger 20260921012521
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921012521', 'my_one_shot_cron_guard_read_before_it_wrote_and_started_two_runs_fourteen_seconds_apart', NULL);
-- @@ ledger 20260921025959
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921025959', 'choose_the_clock_before_you_build_the_world_g107', NULL);
-- @@ ledger 20260921031935
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921031935', 'one_word_for_rest_and_the_dwell_that_lived_in_two_missing_rows_g96', NULL);
-- @@ ledger 20260921073824
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921073824', 'the_address_of_a_service_that_moves_belongs_in_data_g108', 'chase@ottoyard.com');
-- @@ ledger 20260921122812
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921122812', 'the_bess_state_machine_gets_its_caller_and_the_table_gets_its_first_trigger_g96', 'chase@ottoyard.com');
-- @@ ledger 20260921165330
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921165330', 'a_determinism_verdict_can_finally_state_the_clock_it_was_earned_at_g112', 'chase@ottoyard.com');
-- @@ ledger 20260921172038
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921172038', 'the_dials_outlive_their_run_so_reanalysis_becomes_possible_g116', 'chase@ottoyard.com');
-- @@ ledger 20260921174317
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921174317', 'the_reward_function_and_dial_promotion_behind_hard_evidence_gates_g116', 'chase@ottoyard.com');
-- @@ ledger 20260921190250
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921190250', 'the_cockpit_gets_its_reads_back_after_0198_revoked_them_on_a_grep_over_the_wrong_repo', 'chase@ottoyard.com');
-- @@ ledger 20260921190457
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921190457', 'thirteen_writers_were_reachable_with_the_browser_key_including_three_i_shipped_this_afternoon', 'chase@ottoyard.com');
-- @@ ledger 20260921191243
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921191243', 'the_fault_reroute_gets_the_gate_it_was_missing_and_hears_its_own_gate_say_no_g114', 'chase@ottoyard.com');
-- @@ ledger 20260921192817
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921192817', 'the_deploy_dial_gets_one_value_and_the_pointer_gate_gets_switched_on_g114', 'chase@ottoyard.com');
-- @@ ledger 20260921193848
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921193848', 'a_busy_day_demo_starts_at_a_uniformly_random_hour_so_a_third_of_them_open_in_the_overnight_trough', NULL);
-- @@ ledger 20260921203327
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921203327', 'arm_event_vocabulary_and_two_registry_readers', 'chase@ottoyard.com');
-- @@ ledger 20260921203917
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921203917', 'evidence_join_loss_reports_archive_recoverability', 'chase@ottoyard.com');
-- @@ ledger 20260921204952
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921204952', 'the_fourth_time_a_header_argued_forces_recert_false_at_length_and_did_not_write_the_row_the_floor_reads', 'chase@ottoyard.com');
-- @@ ledger 20260921210548
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260921210548', 'the_purge_hardcodes_public_so_the_two_twin_tables_it_was_meant_to_clear_would_have_shut_the_start_door', 'chase@ottoyard.com');
-- @@ ledger 20260922042212
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922042212', 'the_state_machine_never_learned_that_a_vehicle_can_break_while_parked', 'chase@ottoyard.com');
-- @@ ledger 20260922043506
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922043506', 'a_fault_hazard_denominated_in_scheduler_ticks_is_not_a_fault_rate', 'chase@ottoyard.com');
-- @@ ledger 20260922050100
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922050100', 'the_agent_envelope_was_advertised_and_judged_and_enforced_by_nobody', NULL);
-- @@ ledger 20260922053000
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922053000', 'the_ledger_called_an_empty_frame_an_abstention_and_a_decision_a_call', NULL);
-- @@ ledger 20260922065233
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922065233', 'the_drift_cap_was_a_fraction_in_a_percent_column_so_it_froze_the_dial_it_was_meant_to_bound', 'chase@ottoyard.com');
-- @@ ledger 20260922070445
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922070445', 'the_agents_advice_carries_the_tick_it_was_computed_from_and_the_tick_it_was_applied_at_and_nobody_had_ever_subtracted_them', 'chase@ottoyard.com');
-- @@ ledger 20260922073820
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922073820', 'the_probe_for_the_one_unprobed_context_the_engine_actually_exercises_built_and_proven_but_not_wired', 'chase@ottoyard.com');
-- @@ ledger 20260922074145
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922074145', 'my_own_abstention_counter_counted_two_of_the_four_abstentions_as_real_verdicts', 'chase@ottoyard.com');
-- @@ ledger 20260922080856
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922080856', 'i_converted_the_hazard_with_the_metronome_cadence_instead_of_the_sim_time_the_tick_actually_advances', 'chase@ottoyard.com');
-- @@ ledger 20260922125637
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922125637', 'a_certified_arms_evidence_is_rewritten_by_the_next_arms_fleet_reset', 'chase@ottoyard.com');
-- @@ ledger 20260922134041
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922134041', 'wiring_the_task_completion_probe_so_the_rule_that_names_g121_can_finally_fire', 'chase@ottoyard.com');
-- @@ ledger 20260922134203
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922134203', 'a_vehicle_can_power_down_from_any_state_and_the_catalog_never_knew_it', 'chase@ottoyard.com');
-- @@ ledger 20260922150552
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922150552', 'a_charger_heartbeat_written_after_the_charge_starts_is_a_liveness_check_that_cannot_pass', 'chase@ottoyard.com');
-- @@ ledger 20260922155332
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922155332', 'the_walkaround_claims_a_service_bay_because_its_leg_type_falls_through_and_the_one_line_fix_would_have_broken_the_planner', 'chase@ottoyard.com');
-- @@ ledger 20260922155423
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922155423', 'a_charge_only_rule_fails_every_walkaround_because_my_probe_spells_the_service_key_svc_and_it_reads_service', 'chase@ottoyard.com');
-- @@ ledger 20260922163008
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922163008', '0427_the_presence_rule_finally_gets_a_stall_by_probing_where_a_charge_actually_ends', 'chase@ottoyard.com');
-- @@ ledger 20260922170157
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922170157', '0428_the_first_advisory_checkpoint_becomes_enforcing_and_refusing_by_raise_would_have_erased_its_own_evidence', 'chase@ottoyard.com');
-- @@ ledger 20260922171450
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922171450', '0429_the_depot_is_in_entity_id_and_every_query_written_to_this_repos_own_mandated_predicate_reads_zero', NULL);
-- @@ ledger 20260922172845
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922172845', '0430_the_ledger_says_blocked_and_cannot_say_whether_anything_was_blocked_so_it_learns_to_say_both', NULL);
-- @@ ledger 20260922224038
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922224038', 'a_quarter_of_departures_skipped_the_readiness_check_because_it_runs_before_the_vehicle_is_staged', 'chase@ottoyard.com');
-- @@ ledger 20260922231738
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260922231738', 'the_agent_could_rewrite_the_simulated_demand_it_is_measured_against_and_could_not_see_its_own_clamps', 'chase@ottoyard.com');
-- @@ ledger 20260923012038
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923012038', 'a_demand_response_reduction_was_read_as_the_depots_whole_charging_ceiling_and_the_gate_forgot_the_battery', 'chase@ottoyard.com');
-- @@ ledger 20260923012128
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923012128', 'three_consumers_of_the_deploy_demand_defaulted_it_three_ways_and_one_saw_double', 'chase@ottoyard.com');
-- @@ ledger 20260923012432
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923012432', 'the_battery_planned_eight_hours_ahead_on_a_forecast_where_charging_stops_and_was_empty_before_the_expensive_afternoon', 'chase@ottoyard.com');
-- @@ ledger 20260923012457
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923012457', 'the_twins_afternoon_peaked_at_eight_pm_because_a_sine_was_written_where_its_comment_meant_a_cosine', 'chase@ottoyard.com');
-- @@ ledger 20260923012530
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923012530', 'the_readiness_check_had_a_second_door_out_of_the_depot_and_0431_only_guarded_one', 'chase@ottoyard.com');
-- @@ ledger 20260923012821
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923012821', 'three_of_the_agents_five_dials_did_nothing_and_its_board_never_said_so', 'chase@ottoyard.com');
-- @@ ledger 20260923020808
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923020808', 'the_learning_loop_had_nothing_to_compare_so_it_now_runs_its_own_experiments', 'chase@ottoyard.com');
-- @@ ledger 20260923021253
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923021253', 'the_dial_runner_lost_its_lock_to_the_recert_heartbeat_on_every_minute_they_share', 'chase@ottoyard.com');
-- @@ ledger 20260923023300
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923023300', 'the_physical_pointer_defect_is_safety_evidence_and_it_evaporates_on_the_next_demo_run', NULL);
-- @@ ledger 20260923042027
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923042027', 'the_sites_forward_schedule_was_computed_every_tick_and_published_nowhere', 'chase@ottoyard.com');
-- @@ ledger 20260923042056
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923042056', 'the_ab_pair_filed_its_second_arms_fleet_reset_as_the_first_arms_evidence', 'chase@ottoyard.com');
-- @@ ledger 20260923042223
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923042223', 'the_day_plan_could_not_see_the_fleet_waiting_to_charge_so_the_boot_surge_set_the_billed_peak', 'chase@ottoyard.com');
-- @@ ledger 20260923042310
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923042310', 'the_battery_was_dispatched_before_the_ticks_new_sessions_started_so_it_answered_one_tick_late', 'chase@ottoyard.com');
-- @@ ledger 20260923042353
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923042353', 'two_fast_chargers_looped_on_vehicles_already_at_their_daytime_cap_delivering_nothing', 'chase@ottoyard.com');
-- @@ ledger 20260923042423
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923042423', 'the_readiness_gates_hold_clock_lived_on_the_vehicle_so_an_old_runs_stamp_released_fresh_holds', 'chase@ottoyard.com');
-- @@ ledger 20260923042526
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923042526', 'the_recall_policy_and_the_visit_planner_disagreed_about_maintenance_so_vehicles_looped', 'chase@ottoyard.com');
-- @@ ledger 20260923042610
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923042610', 'the_twins_september_afternoon_was_hotter_than_nashvilles_record_because_it_widened_around_the_yearly_mean', 'chase@ottoyard.com');
-- @@ ledger 20260923042708
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923042708', 'the_twins_battery_paid_for_a_cooling_system_it_never_got_so_it_sat_out_a_demand_response_call', 'chase@ottoyard.com');
-- @@ ledger 20260923053740
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923053740', 'the_intelligence_panel_counted_failures_as_refusals_and_showed_every_runs_solver_calls_as_this_ones', 'chase@ottoyard.com');
-- @@ ledger 20260923060345
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923060345', 'the_decisions_stream_restated_every_waiting_vehicle_every_tick_and_the_ledger_never_saw_a_failed_agent_call', 'chase@ottoyard.com');
-- @@ ledger 20260923060733
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923060733', 'a_repeat_is_the_next_decide_tick_and_standing_is_per_action', 'chase@ottoyard.com');
-- @@ ledger 20260923061135
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923061135', 'events_are_their_own_rows_and_a_waiting_vehicle_is_one_row', 'chase@ottoyard.com');
-- @@ ledger 20260923061500
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923061500', 'every_decision_in_the_stream_says_what_it_decided_and_why', 'chase@ottoyard.com');
-- @@ ledger 20260923062252
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923062252', 'the_kernel_card_counted_abstentions_as_refused_proposals', 'chase@ottoyard.com');
-- @@ ledger 20260923063827
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260923063827', 'a_held_deploy_is_a_state_not_an_event', 'chase@ottoyard.com');
-- @@ ledger 20260925200000
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260925200000', 'the_cockpits_could_not_read_the_card_they_were_built_on_and_it_never_said_where_a_vehicle_was_booked', NULL);
-- @@ ledger 20260926032129
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926032129', 'the_depot_card_migration_never_classified_itself_so_the_recert_floor_restarted_every_column', 'chase@ottoyard.com');
-- @@ ledger 20260926033237
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926033237', 'a_bay_door_seated_cars_for_no_time_and_the_bay_could_not_credit_the_need_it_was_seated_for', 'chase@ottoyard.com');
-- @@ ledger 20260926033252
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926033252', 'stopping_a_run_relabelled_every_interrupted_bay_booking_so_the_interruption_record_vanished', 'chase@ottoyard.com');
-- @@ ledger 20260926040843
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926040843', '0462_the_events_feed_printed_real_time_painted_passing_rules_critical_and_restated_every_tick', 'chase@ottoyard.com');
-- @@ ledger 20260926045441
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926045441', '0466_the_run_list_counted_no_charge_sessions_for_any_run_and_printed_its_row_cap_as_a_count', 'chase@ottoyard.com');
-- @@ ledger 20260926045517
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926045517', '0463_a_charge_that_completed_below_its_visit_target_stayed_open_and_the_deploy_gate_looped_the_car_through_the_service_bay', 'chase@ottoyard.com');
-- @@ ledger 20260926045544
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926045544', '0464_the_deploy_gate_sent_every_kind_of_open_work_to_the_service_bay_and_named_the_wrong_work_as_missing', 'chase@ottoyard.com');
-- @@ ledger 20260926045604
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926045604', '0465_the_command_door_dropped_the_step_a_gate_intake_carried_so_the_car_was_never_moved_again', 'chase@ottoyard.com');
-- @@ ledger 20260926052522
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926052522', 'the_gate_intake_picked_a_stall_its_own_gate_refused_and_each_refusal_left_a_phantom_hold', 'chase@ottoyard.com');
-- @@ ledger 20260926055955
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926055955', 'the_service_bay_admitted_cars_on_their_step_alone_and_seated_the_boot_cohort_for_work_that_did_not_exist', 'chase@ottoyard.com');
-- @@ ledger 20260926060017
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926060017', 'the_service_sequencer_sent_every_ready_car_a_stage_command_every_tick_that_the_door_executed_as_nothing', 'chase@ottoyard.com');
-- @@ ledger 20260926062937
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926062937', 'the_run_list_showed_certification_arms_and_pushed_the_operators_own_runs_off_it', 'chase@ottoyard.com');
-- @@ ledger 20260926063850
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926063850', 'the_staging_hold_booked_stalls_promised_to_another_car_and_left_each_refused_booking_held', 'chase@ottoyard.com');
-- @@ ledger 20260926070905
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926070905', 'the_inspection_seam_sent_cars_the_gate_intake_had_already_sent_and_the_door_kept_one_by_stall_id', 'chase@ottoyard.com');
-- @@ ledger 20260926070924
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926070924', 'the_inspection_seam_served_the_readiness_leg_as_a_second_interior_inspection', 'chase@ottoyard.com');
-- @@ ledger 20260926112238
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926112238', 'a_car_moved_off_a_faulted_charger_was_staged_with_no_step_so_no_gate_read_it', 'chase@ottoyard.com');
-- @@ ledger 20260926112312
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926112312', 'the_deploy_gates_technician_flag_was_never_cleared_and_took_service_bay_seats_in_later_runs', 'chase@ottoyard.com');
-- @@ ledger 20260926112337
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926112337', 'the_gate_intake_booked_over_the_cars_own_hold_and_ran_with_no_booking', 'chase@ottoyard.com');
-- @@ ledger 20260926112403
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926112403', 'the_energy_command_hashed_the_day_plans_solve_time_so_a_reserve_shaving_depot_could_not_certify', 'chase@ottoyard.com');
-- @@ ledger 20260926115337
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926115337', 'the_dial_setter_kept_a_rows_first_writer_so_a_dial_named_who_created_it_not_who_set_it', 'chase@ottoyard.com');
-- @@ ledger 20260926115429
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926115429', 'the_solar_canopies_soiling_was_shared_by_every_run_so_an_arm_inherited_the_panels_the_last_run_left', 'chase@ottoyard.com');
-- @@ ledger 20260926115449
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926115449', 'the_reserve_shave_promotion_is_measured_again_on_arms_that_start_on_the_same_panels', 'chase@ottoyard.com');
-- @@ ledger 20260926122216
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926122216', 'a_dial_promotion_the_canon_keeps_failing_under_now_rolls_itself_back', 'chase@ottoyard.com');
-- @@ ledger 20260926122233
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926122233', 'the_dial_runner_opens_and_closes_its_own_overnight_window', 'chase@ottoyard.com');
-- @@ ledger 20260926132036
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926132036', 'a_recalled_cars_charge_was_closed_on_the_soc_it_left_with_before_the_arrival_drain', 'chase@ottoyard.com');
-- @@ ledger 20260926132059
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926132059', 'a_finished_charge_kept_its_charger_booked_and_reserved_so_the_car_held_it_from_staging', 'chase@ottoyard.com');
-- @@ ledger 20260926143555
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926143555', 'the_dial_window_stays_closed_while_the_build_is_still_moving', 'chase@ottoyard.com');
-- @@ ledger 20260926145308
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926145308', 'the_battery_drains_while_the_car_is_out_and_otto_q_rereads_its_charge_need_every_tick', 'chase@ottoyard.com');
-- @@ ledger 20260926152610
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926152610', 'the_crew_decides_first_and_the_engine_applies_it', 'chase@ottoyard.com');
-- @@ ledger 20260926160930
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926160930', 'the_wave_admission_edge_function_stops_moving_cars_under_the_live_tick', 'chase@ottoyard.com');
-- @@ ledger 20260926161825
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926161825', 'the_completion_probe_reads_the_stall_the_work_was_done_in', 'chase@ottoyard.com');
-- @@ ledger 20260926161853
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926161853', 'the_refusal_reactor_leaves_a_car_the_decide_path_has_already_replanned', 'chase@ottoyard.com');
-- @@ ledger 20260926170743
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926170743', 'an_ops_action_outside_the_whitelist_is_refused_and_says_so', 'chase@ottoyard.com');
-- @@ ledger 20260926170804
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926170804', 'the_orphan_sweep_ends_a_twin_session_on_its_runs_clock', 'chase@ottoyard.com');
-- @@ ledger 20260926183701
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926183701', 'a_refused_charge_books_nothing_and_a_charging_car_holds_no_other_charger', 'chase@ottoyard.com');
-- @@ ledger 20260926190651
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926190651', 'the_charge_proposer_offers_only_a_charger_the_gate_accepts', 'chase@ottoyard.com');
-- @@ ledger 20260926200223
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926200223', 'the_intelligence_card_reads_the_playback_speed_the_run_is_paced_by', 'chase@ottoyard.com');
-- @@ ledger 20260926201658
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926201658', 'the_greedy_optimizer_offers_only_a_charger_the_gate_accepts', 'chase@ottoyard.com');
-- @@ ledger 20260926204519
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926204519', 'a_run_seed_goes_to_the_cockpit_as_text', 'chase@ottoyard.com');
-- @@ ledger 20260926210609
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926210609', 'the_cp_sat_frame_reads_the_calendar_the_gate_refuses_on', 'chase@ottoyard.com');
-- @@ ledger 20260926210943
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926210943', 'the_proposal_selector_asks_the_calendar_the_gate_refuses_on', 'chase@ottoyard.com');
-- @@ ledger 20260926214200
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926214200', 'a_parking_hold_lasts_as_long_as_its_car_is_parked', 'chase@ottoyard.com');
-- @@ ledger 20260926221345
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926221345', 'the_wait_for_a_charger_is_measured_beside_kpi_5', 'chase@ottoyard.com');
-- @@ ledger 20260926232454
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926232454', 'the_recall_appointment_picks_a_staging_stall_the_gate_accepts', 'chase@ottoyard.com');
-- @@ ledger 20260926232527
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926232527', 'the_refusal_reactor_leaves_a_refused_staging_appointment_to_the_cars_arrival', 'chase@ottoyard.com');
-- @@ ledger 20260926235621
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260926235621', 'an_inspection_closes_its_own_leg_not_the_readiness_check', 'chase@ottoyard.com');
-- @@ ledger 20260927002850
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927002850', 'a_twin_command_records_when_it_executed', 'chase@ottoyard.com');
-- @@ ledger 20260927004648
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927004648', 'a_vehicle_card_names_its_steps_and_says_when_one_is_overdue', 'chase@ottoyard.com');
-- @@ ledger 20260927005114
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927005114', 'a_vehicle_card_ends_the_current_step_when_it_will_end', 'chase@ottoyard.com');
-- @@ ledger 20260927012721
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927012721', 'a_charge_is_recorded_when_its_session_ends_with_the_energy_it_delivered', 'chase@ottoyard.com');
-- @@ ledger 20260927020531
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927020531', 'a_charging_card_ends_when_the_charge_physics_says_it_will', 'chase@ottoyard.com');
-- @@ ledger 20260927030227
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927030227', 'one_air_temperature_for_the_whole_depot', 'chase@ottoyard.com');
-- @@ ledger 20260927034307
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927034307', 'the_interior_inspection_happens_during_the_charge', 'chase@ottoyard.com');
-- @@ ledger 20260927050506
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927050506', 'the_weekly_refit_could_not_see_the_recert_runner_and_wrote_the_priors_under_a_pair', 'chase@ottoyard.com');
-- @@ ledger 20260927050956
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927050956', 'the_cards_say_who_did_the_work', 'chase@ottoyard.com');
-- @@ ledger 20260927052757
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927052757', 'the_charges_that_teach_the_booking_window_are_purged_with_their_run', 'chase@ottoyard.com');
-- @@ ledger 20260927060333
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927060333', 'the_ledger_records_what_the_charge_was_booked_for_and_aimed_at', 'chase@ottoyard.com');
-- @@ ledger 20260927061451
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927061451', 'the_booking_window_is_fitted_from_the_charges_with_the_run_s_stop_counted', 'chase@ottoyard.com');
-- @@ ledger 20260927062217
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927062217', 'a_calibrated_charge_window_behind_a_dial', 'chase@ottoyard.com');
-- @@ ledger 20260927074142
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927074142', 'one_rule_for_whether_a_car_needs_its_charge', 'chase@ottoyard.com');
-- @@ ledger 20260927074236
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927074236', 'the_charger_s_sensors_cannot_finish_an_inspection_on_a_car_that_has_left', 'chase@ottoyard.com');
-- @@ ledger 20260927081719
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927081719', 'a_paired_experiment_can_judge_the_booking_window_at_a_charge_s_own_cadence', 'chase@ottoyard.com');
-- @@ ledger 20260927085218
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927085218', 'the_charger_s_sensors_see_only_a_car_on_a_charger', 'chase@ottoyard.com');
-- @@ ledger 20260927111501
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927111501', 'the_dial_window_closes_before_its_last_pair_could_outlast_it', 'chase@ottoyard.com');
-- @@ ledger 20260927122408
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927122408', 'a_dial_experiment_restarts_only_for_a_change_that_can_move_an_arm', 'chase@ottoyard.com');
-- @@ ledger 20260927131711
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927131711', 'a_start_stops_the_live_run_and_a_failed_seed_starts_nothing', 'chase@ottoyard.com');
-- @@ ledger 20260927131932
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927131932', 'the_charge_evidence_records_the_cadence_it_was_observed_at', 'chase@ottoyard.com');
-- @@ ledger 20260927140637
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927140637', 'a_visit_with_no_charge_does_its_cabin_work_where_the_car_is_parked', 'chase@ottoyard.com');
-- @@ ledger 20260927140742
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927140742', 'kpi_two_counts_a_turn_when_a_car_leaves_a_service_point', 'chase@ottoyard.com');
-- @@ ledger 20260927150822
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927150822', 'kpi_four_counts_the_technicians_and_divides_by_the_cars_that_came_in', 'chase@ottoyard.com');
-- @@ ledger 20260927151819
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927151819', 'a_guardrail_that_moves_off_zero_is_judged_and_the_verdict_names_the_unmeasured', 'chase@ottoyard.com');
-- @@ ledger 20260927153902
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927153902', 'unmet_demand_is_measured_from_the_cars_actually_out', 'chase@ottoyard.com');
-- @@ ledger 20260927161230
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927161230', 'the_learners_arms_start_through_the_operators_door', 'chase@ottoyard.com');
-- @@ ledger 20260927164827
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927164827', 'the_challenger_asks_whether_the_chargers_could_do_more_while_cars_wait', 'chase@ottoyard.com');
-- @@ ledger 20260927171208
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927171208', 'the_charge_target_an_arm_is_given_is_the_one_it_charges_to', 'chase@ottoyard.com');
-- @@ ledger 20260927173711
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927173711', 'an_experiment_can_wait_its_turn', 'chase@ottoyard.com');
-- @@ ledger 20260927175201
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927175201', 'a_top_off_is_offered_to_a_car_still_waiting_for_one', 'chase@ottoyard.com');
-- @@ ledger 20260927180246
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927180246', 'the_cockpits_see_what_the_brain_questions_and_what_it_learns', 'chase@ottoyard.com');
-- @@ ledger 20260927194349
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927194349', 'a_question_is_one_the_next_scan_still_sees', 'chase@ottoyard.com');
-- @@ ledger 20260927210230
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927210230', 'a_challenger_grade_says_what_it_measures_and_what_tests_its_lever', 'chase@ottoyard.com');
-- @@ ledger 20260927223621
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927223621', 'a_car_charges_to_full_and_nothing_the_depot_decides_lowers_it', 'chase@ottoyard.com');
-- @@ ledger 20260927230739
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927230739', 'every_result_the_learner_reaches_is_a_recommendation_a_person_ships', 'chase@ottoyard.com');
-- @@ ledger 20260927230859
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260927230859', 'a_car_charging_to_its_target_is_never_a_question', 'chase@ottoyard.com');
-- @@ ledger 20260928003702
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928003702', 'a_car_that_owes_its_charge_goes_to_the_charger_and_no_gate_sends_a_car_out_unfinished', 'chase@ottoyard.com');
-- @@ ledger 20260928013804
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928013804', 'no_car_leaves_the_depot_with_a_service_still_needed', 'chase@ottoyard.com');
-- @@ ledger 20260928033602
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928033602', 'a_car_that_is_not_finished_cannot_be_dispatched', 'chase@ottoyard.com');
-- @@ ledger 20260928034458
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928034458', 'no_queue_starves_a_car_that_cannot_leave_until_it_is_finished', 'chase@ottoyard.com');
-- @@ ledger 20260928053318
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928053318', 'a_car_waiting_for_a_charger_keeps_its_place_in_line', 'chase@ottoyard.com');
-- @@ ledger 20260928074913
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928074913', 'a_charger_its_car_has_left_for_a_bay_is_free', 'chase@ottoyard.com');
-- @@ ledger 20260928093601
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928093601', 'a_paired_test_can_keep_a_fast_charger_for_a_car_that_wants_one', 'chase@ottoyard.com');
-- @@ ledger 20260928111517
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928111517', 'a_car_seated_in_a_bay_early_is_served_now', 'chase@ottoyard.com');
-- @@ ledger 20260928163347
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928163347', 'a_charger_fault_from_the_cockpit_stops_the_charge', 'chase@ottoyard.com');
-- @@ ledger 20260928170009
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928170009', 'the_fault_door_waits_for_the_tick_instead_of_deadlocking_with_it', 'chase@ottoyard.com');
-- @@ ledger 20260928180804
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928180804', 'a_car_keeps_its_place_in_the_charge_line_through_a_fault', 'chase@ottoyard.com');
-- @@ ledger 20260928184413
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928184413', 'a_hold_gives_way_and_a_car_is_in_a_bay_only_when_it_stands_in_one', 'chase@ottoyard.com');
-- @@ ledger 20260928212503
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928212503', 'a_faulted_car_is_repaired_and_the_gate_flag_is_a_note', 'chase@ottoyard.com');
-- @@ ledger 20260928220015
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928220015', 'a_faulted_car_is_repaired_before_it_charges', 'chase@ottoyard.com');
-- @@ ledger 20260928235524
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260928235524', 'a_faulted_cars_repair_goes_first_in_its_plan', 'chase@ottoyard.com');
-- @@ ledger 20260929014318
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260929014318', 'every_charger_stall_is_angled_and_the_database_says_so', 'chase@ottoyard.com');
-- @@ ledger 20260929024700
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260929024700', 'a_manual_start_interrupts_a_running_check', 'chase@ottoyard.com');
-- @@ ledger 20260929183923
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260929183923', 'a_scorecard_that_counts_cars_served', 'chase@ottoyard.com');
-- @@ ledger 20260929184316
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260929184316', 'the_scorecard_reads_the_step_a_run_actually_took', 'chase@ottoyard.com');
-- @@ ledger 20260929191451
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260929191451', 'a_charger_build_out_lives_only_inside_a_test_day', 'chase@ottoyard.com');
-- @@ ledger 20260929192241
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260929192241', 'each_charger_choice_says_what_it_chose_from', 'chase@ottoyard.com');
-- @@ ledger 20260929193249
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260929193249', 'an_overnight_sweep_scores_one_test_day_at_a_time', 'chase@ottoyard.com');
-- @@ ledger 20260929200104
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260929200104', 'a_margin_ledger_prices_what_the_twin_measured', 'chase@ottoyard.com');
-- @@ ledger 20260930113817
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260930113817', 'the_batch_optimizer_can_serve_cars_in_the_order_the_cursor_does', 'chase@ottoyard.com');
-- @@ ledger 20260930114255
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260930114255', 'a_sweep_measures_a_dial_against_its_own_control', 'chase@ottoyard.com');
-- @@ ledger 20260930114616
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260930114616', 'a_fleet_build_out_borrows_cars_for_one_test_day', 'chase@ottoyard.com');
-- @@ ledger 20260930114742
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260930114742', 'a_replicate_is_judged_on_what_it_did_not_on_its_own_run_id', 'chase@ottoyard.com');
-- @@ ledger 20260930115308
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260930115308', 'every_charge_and_service_takes_the_time_public_data_says', 'chase@ottoyard.com');
-- @@ ledger 20260930115405
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260930115405', 'the_twin_prices_power_at_nashvilles_published_rate', 'chase@ottoyard.com');
-- @@ ledger 20260930115452
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260930115452', 'night_two_measures_what_a_customer_is_paying_for', 'chase@ottoyard.com');
-- @@ ledger 20260930115650
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260930115650', 'the_value_tab_reads_what_night_two_measured', 'chase@ottoyard.com');
-- @@ ledger 20260930115753
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20260930115753', 'a_test_days_opening_surge_is_not_the_depots_peak', 'chase@ottoyard.com');
-- @@ ledger 20261001232134
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261001232134', 'the_staging_stall_beside_the_gate_fills_last', 'chase@ottoyard.com');
-- @@ ledger 20261001233144
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261001233144', 'a_vehicle_card_names_each_steps_station_and_the_plan_it_replaced', 'chase@ottoyard.com');
-- @@ ledger 20261002014128
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261002014128', 'the_entrance_sign_stands_outside_the_fence_where_the_twin_draws_it', 'chase@ottoyard.com');
-- @@ ledger 20261002194411
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261002194411', 'the_in_flight_probe_sees_an_overnight_sweep_arm', 'chase@ottoyard.com');
-- @@ ledger 20261002194524
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261002194524', 'the_overnight_sweep_keeps_its_own_window_and_starts_no_arm_it_cannot_finish', 'chase@ottoyard.com');
-- @@ ledger 20261002195422
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261002195422', 'the_value_tab_names_the_test_a_charger_claim_failed', 'chase@ottoyard.com');
-- @@ ledger 20261002195507
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261002195507', 'a_run_that_has_ended_dispatches_no_car', 'chase@ottoyard.com');
-- @@ ledger 20261002195616
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261002195616', 'the_battery_never_charges_itself_into_the_billed_half_hour', 'chase@ottoyard.com');
-- @@ ledger 20261002200039
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261002200039', 'the_battery_forecast_charges_a_waiting_car_at_the_rate_its_battery_accepts', 'chase@ottoyard.com');
-- @@ ledger 20261002200316
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261002200316', 'every_test_day_can_say_whether_its_fast_chargers_went_to_the_cars_that_needed_them', 'chase@ottoyard.com');
-- @@ ledger 20261004111417
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261004111417', 'an_outside_agent_asks_through_one_door_and_a_person_decides', 'chase@ottoyard.com');
-- @@ ledger 20261004111501
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261004111501', 'the_fleet_owner_cockpit_reads_its_own_agent_requests', 'chase@ottoyard.com');
-- @@ ledger 20261004112442
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261004112442', 'an_owners_agent_sets_what_its_own_cars_need_and_the_runs_end_puts_it_back', 'chase@ottoyard.com');
-- @@ ledger 20261004112719
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261004112719', 'the_fleet_owner_cockpit_reads_what_its_agent_set', 'chase@ottoyard.com');
-- @@ ledger 20261004113110
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261004113110', 'any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends', 'chase@ottoyard.com');
-- @@ ledger 20261004113230
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261004113230', 'the_crew_and_the_twin_see_what_every_owners_agent_set_with_its_confirmation_code', 'chase@ottoyard.com');
-- @@ ledger 20261007024116
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261007024116', 'the_kpi_tab_reads_uptime_turnaround_service_and_energy', 'chase@ottoyard.com');
-- @@ ledger 20261007024824
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261007024824', 'the_kpi_boards_turnaround_in_one_pass', 'chase@ottoyard.com');
-- @@ ledger 20261007031040
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261007031040', 'the_kpi_board_prices_the_demand_charge', 'chase@ottoyard.com');
-- @@ ledger 20261007131113
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261007131113', 'the_twin_sees_a_faulted_charger_and_when_it_comes_back', 'chase@ottoyard.com');
-- @@ ledger 20261007135127
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261007135127', 'the_planners_learn_inside_the_run_where_their_offers_went', 'chase@ottoyard.com');
-- @@ ledger 20261007181946
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261007181946', 'the_agent_can_order_the_charge_line_and_the_decide_path_disposes', 'chase@ottoyard.com');
-- @@ ledger 20261007183516
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261007183516', 'an_operators_demo_run_takes_the_agents_charge_order', 'chase@ottoyard.com');
-- @@ ledger 20261007184459
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261007184459', 'the_order_usage_counts_the_orders_that_seated_cars', 'chase@ottoyard.com');
-- @@ ledger 20261007202316
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261007202316', 'a_car_named_for_the_kind_not_free_waits_behind_the_cars_not_named', 'chase@ottoyard.com');
-- @@ ledger 20261007203510
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261007203510', 'the_kernel_checks_the_agents_charge_order_against_its_own_before_taking_it', 'chase@ottoyard.com');
-- @@ ledger 20261008132327
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261008132327', 'the_kernel_learns_how_long_a_charge_takes_and_when_a_car_comes_back', 'chase@ottoyard.com');
-- @@ ledger 20261008134303
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261008134303', 'the_kernel_takes_an_agent_order_only_when_it_wins_most_futures', 'chase@ottoyard.com');
-- @@ ledger 20261008144612
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261008144612', 'the_kernel_grades_its_own_check_in_hindsight', 'chase@ottoyard.com');
-- @@ ledger 20261008162412
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261008162412', 'the_kernel_learns_each_cars_charge_clock_from_its_own_charges', 'chase@ottoyard.com');
-- @@ ledger 20261008191129
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261008191129', 'the_check_sees_cars_leave_and_come_back', 'chase@ottoyard.com');
-- @@ ledger 20261008204412
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261008204412', 'the_check_reads_each_cars_open_work', 'chase@ottoyard.com');
-- @@ ledger 20261008214932
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261008214932', 'a_learned_model_knows_when_its_world_changed', 'chase@ottoyard.com');
-- @@ ledger 20261008225037
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261008225037', 'the_self_review_judges_the_clock_within_runs_and_ranks_what_to_build', 'chase@ottoyard.com');
-- @@ ledger 20261009002205
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009002205', 'the_futures_call_cars_home_the_way_the_kernel_does', 'chase@ottoyard.com');
-- @@ ledger 20261009021006
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009021006', 'the_futures_drain_each_car_at_its_own_rate', 'chase@ottoyard.com');
-- @@ ledger 20261009033733
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009033733', 'a_production_session_is_armed_and_no_agent_write_reaches_it', 'chase@ottoyard.com');
-- @@ ledger 20261009100905
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009100905', 'the_grader_reads_a_runs_stop_as_the_stop', 'chase@ottoyard.com');
-- @@ ledger 20261009101257
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009101257', 'a_fault_owns_the_charge_it_cut', 'chase@ottoyard.com');
-- @@ ledger 20261009101743
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009101743', 'the_charge_clock_reads_the_air', 'chase@ottoyard.com');
-- @@ ledger 20261009102050
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009102050', 'the_futures_spread_each_arrival_as_the_returns_show', 'chase@ottoyard.com');
-- @@ ledger 20261009102518
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009102518', 'a_drain_is_timed_only_from_a_dispatch_the_depot_saw_begin', 'chase@ottoyard.com');
-- @@ ledger 20261009103141
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009103141', 'the_futures_take_chargers_down_as_the_depots_chargers_fail', 'chase@ottoyard.com');
-- @@ ledger 20261009103417
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009103417', 'the_charge_clocks_spread_is_what_its_charges_show', 'chase@ottoyard.com');
-- @@ ledger 20261009103821
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009103821', 'the_futures_read_the_latest_return_model_that_was_usable', 'chase@ottoyard.com');
-- @@ ledger 20261009104044
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009104044', 'the_self_review_remembers_what_it_found', 'chase@ottoyard.com');
-- @@ ledger 20261009104324
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009104324', 'the_futures_hold_a_charger_for_the_car_the_calendar_names', 'chase@ottoyard.com');
-- @@ ledger 20261009104502
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009104502', 'the_agent_sees_the_chargers_the_calendar_holds', 'chase@ottoyard.com');
-- @@ ledger 20261009104632
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009104632', 'the_agent_sees_the_kernels_own_plan', 'chase@ottoyard.com');
-- @@ ledger 20261009123213
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009123213', 'the_kernel_serves_a_long_wait_first_and_times_its_line_in_minutes', 'chase@ottoyard.com');
-- @@ ledger 20261009132013
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009132013', 'the_research_wing_tests_0642s_two_keys_in_the_twin', 'chase@ottoyard.com');
-- @@ ledger 20261009174701
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009174701', 'the_research_safety_check_judges_cars_not_served_across_a_look', 'chase@ottoyard.com');
-- @@ ledger 20261009232411
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009232411', 'the_public_key_reads_no_vehicle_and_no_command', 'chase@ottoyard.com');
-- @@ ledger 20261009232737
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009232737', 'the_command_dock_answers_only_the_platform', 'chase@ottoyard.com');
-- @@ ledger 20261009233223
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261009233223', 'source_keys_are_issued_by_the_platform_and_bind_a_depot_and_a_data_source', 'chase@ottoyard.com');
-- @@ ledger 20261010005456
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010005456', 'the_v2_door_takes_cloudevents_keeps_their_time_drops_duplicates_and_orders_them', 'chase@ottoyard.com');
-- @@ ledger 20261010005934
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010005934', 'a_directive_leaves_with_an_id_a_version_an_expiry_and_the_depots_signing_key', 'chase@ottoyard.com');
-- @@ ledger 20261010010118
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010010118', 'the_twin_applies_the_directives_it_is_handed_and_answers_each_with_an_ack', 'chase@ottoyard.com');
-- @@ ledger 20261010013631
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010013631', 'the_twin_speaks_to_otto_q_as_two_operators', 'chase@ottoyard.com');
-- @@ ledger 20261010014628
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010014628', 'the_walk_reports_to_the_twin_and_the_ticks_let_its_operators_answer_first', 'chase@ottoyard.com');
-- @@ ledger 20261010031137
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010031137', 'the_finalizer_leaves_a_directive_its_operator_answered_as_it_was_answered', 'chase@ottoyard.com');
-- @@ ledger 20261010031436
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010031436', 'the_research_wing_measures_the_operator_door_in_the_twin', 'chase@ottoyard.com');
-- @@ ledger 20261010110559
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010110559', 'the_public_key_reads_only_what_a_cockpit_shows', 'chase@ottoyard.com');
-- @@ ledger 20261010110724
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010110724', 'the_twin_apps_determinism_canon_card_reads_again', 'chase@ottoyard.com');
-- @@ ledger 20261010110931
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010110931', 'the_twins_chargers_can_be_depot_grade_and_the_research_wing_measures_it', 'chase@ottoyard.com');
-- @@ ledger 20261010111333
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010111333', 'the_dispatch_ledger_counts_the_miles_the_car_drove', 'chase@ottoyard.com');
-- @@ ledger 20261010111411
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010111411', 'an_owner_signs_in_and_connects_their_own_agent', 'chase@ottoyard.com');
-- @@ ledger 20261010111503
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010111503', 'a_twin_operators_fault_report_goes_with_its_run', 'chase@ottoyard.com');
-- @@ ledger 20261010111739
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010111739', 'the_twins_operators_send_telemetry_and_faults_through_the_door', 'chase@ottoyard.com');
-- @@ ledger 20261010112022
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010112022', 'a_car_leaving_the_depot_is_reported_through_the_door', 'chase@ottoyard.com');
-- @@ ledger 20261010112739
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010112739', 'the_twins_chargers_speak_ocpp_2_0_1', 'chase@ottoyard.com');
-- @@ ledger 20261010112938
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010112938', 'the_readiness_check_is_the_last_thing_a_visit_does', 'chase@ottoyard.com');
-- @@ ledger 20261010113609
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010113609', 'an_autonomous_cars_data_comes_off_while_it_charges', 'chase@ottoyard.com');
-- @@ ledger 20261010113746
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010113746', 'the_twins_roads_crash_at_the_filed_rate_and_the_cold_is_counted_once', 'chase@ottoyard.com');
-- @@ ledger 20261010113923
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261010113923', 'a_new_visit_carries_the_work_the_visit_it_replaces_still_owes', 'chase@ottoyard.com');
-- @@ ledger 20261013150710
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013150710', 'every_agent_pass_keeps_what_it_saw_and_what_it_changed', 'chase@ottoyard.com');
-- @@ ledger 20261013151002
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013151002', 'every_car_has_a_deterministic_scout_and_the_agent_reads_what_they_find', 'chase@ottoyard.com');
-- @@ ledger 20261013151112
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013151112', 'the_agent_is_consulted_when_something_changes_not_on_every_beat', 'chase@ottoyard.com');
-- @@ ledger 20261013152102
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013152102', 'the_agents_return_wave_counts_this_runs_cars_not_every_run_ever', 'chase@ottoyard.com');
-- @@ ledger 20261013180020
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013180020', 'the_wake_gate_reads_the_record_the_claim_reads', 'chase@ottoyard.com');
-- @@ ledger 20261013180804
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013180804', 'the_wake_gate_wakes_on_a_change_that_matters_not_on_every_wobble', 'chase@ottoyard.com');
-- @@ ledger 20261013181932
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013181932', 'the_checks_futures_are_drawn_from_the_world_not_from_the_runs_minted_id', 'chase@ottoyard.com');
-- @@ ledger 20261013182717
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013182717', 'one_agent_pass_holds_its_claim_for_as_long_as_a_pass_can_take', 'chase@ottoyard.com');
-- @@ ledger 20261013184608
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013184608', 'the_feed_agents_propose_the_twins_world_and_a_person_promotes_it', 'chase@ottoyard.com');
-- @@ ledger 20261013191424
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013191424', 'a_charger_is_not_held_for_a_car_still_on_its_way_back', 'chase@ottoyard.com');
-- @@ ledger 20261013193522
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013193522', 'the_engine_notices_when_a_channel_goes_dark', 'chase@ottoyard.com');
-- @@ ledger 20261013195202
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013195202', 'the_promotion_gate_can_ask_whether_the_check_tells_a_winning_order_from_a_losing_one', 'chase@ottoyard.com');
-- @@ ledger 20261013201139
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013201139', 'the_board_calls_eighty_percent_a_priority_band_not_a_floor', 'chase@ottoyard.com');
-- @@ ledger 20261013210801
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013210801', 'production_runs_the_world_phases_the_twin_certifies', 'chase@ottoyard.com');
-- @@ ledger 20261013210919
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013210919', 'the_order_built_from_the_newest_board_stands_and_an_outranked_order_never_does', 'chase@ottoyard.com');
-- @@ ledger 20261013211005
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261013211005', 'production_start_takes_the_world_as_the_operator_door_does', 'chase@ottoyard.com');
-- @@ ledger 20261014144327
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261014144327', 'a_car_with_maintenance_or_calibration_due_gets_it_before_it_leaves', 'chase@ottoyard.com');
-- @@ ledger 20261017060928
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017060928', 'forty_robotic_fast_chargers_are_a_test_day_before_they_are_the_depot', 'chase@ottoyard.com');
-- @@ ledger 20261017063328
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017063328', 'forty_fast_chargers_on_a_normal_day_where_the_service_bays_are_not_the_wall', 'chase@ottoyard.com');
-- @@ ledger 20261017072652
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017072652', 'a_shared_power_cabinet_divides_its_power_and_the_twin_can_model_one', 'chase@ottoyard.com');
-- @@ ledger 20261017072928
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017072928', 'the_site_power_gate_can_read_the_meter_instead_of_guessing', 'chase@ottoyard.com');
-- @@ ledger 20261017073142
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017073142', 'forty_robotic_chargers_on_todays_service_through_shared_cabinets', 'chase@ottoyard.com');
-- @@ ledger 20261017081553
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017081553', 'a_site_that_divides_its_power_is_judged_by_the_limit_it_holds', 'chase@ottoyard.com');
-- @@ ledger 20261017082241
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017082241', 'twenty_fast_chargers_on_the_same_normal_day_to_find_the_knee', 'chase@ottoyard.com');
-- @@ ledger 20261017083042
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017083042', 'the_battery_plans_for_the_bill_the_value_view_reads', 'chase@ottoyard.com');
-- @@ ledger 20261017105250
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017105250', 'two_more_seeds_for_the_four_cells_the_recommendation_rests_on', 'chase@ottoyard.com');
-- @@ ledger 20261017110658
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017110658', 'a_shared_pool_gives_a_new_car_what_it_has_spare', 'chase@ottoyard.com');
-- @@ ledger 20261017111846
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017111846', 'the_same_morning_at_half_the_tick_to_measure_what_the_tick_costs', 'chase@ottoyard.com');
-- @@ ledger 20261017161641
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017161641', 'a_car_answers_a_command_in_the_tick_it_is_given', 'chase@ottoyard.com');
-- @@ ledger 20261017163802
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017163802', 'a_realistic_promise_at_arrival_and_its_grade', 'chase@ottoyard.com');
-- @@ ledger 20261017164907
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017164907', 'a_held_site_powers_the_cars_due_first', 'chase@ottoyard.com');
-- @@ ledger 20261017173306
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017173306', 'a_promise_counts_the_cars_still_waiting', 'chase@ottoyard.com');
-- @@ ledger 20261017174210
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017174210', 'a_promise_on_the_busy_day', 'chase@ottoyard.com');
-- @@ ledger 20261017182220
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017182220', 'the_promise_is_graded_beside_what_the_owner_app_says', 'chase@ottoyard.com');
-- @@ ledger 20261017185512
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261017185512', 'a_promise_stays_honest_while_the_car_waits', 'chase@ottoyard.com');
-- @@ ledger 20261018110944
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018110944', 'the_bay_calendar_seats_each_car_on_its_own', 'chase@ottoyard.com');
-- @@ ledger 20261018111140
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018111140', 'a_bay_hold_follows_a_charge_that_runs_past_its_plan', 'chase@ottoyard.com');
-- @@ ledger 20261018111301
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018111301', 'the_itinerary_plans_each_charge_on_a_charger_the_depot_has', 'chase@ottoyard.com');
-- @@ ledger 20261018111429
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018111429', 'robotic_wash_lanes_and_bay_work_timed_by_the_work', 'chase@ottoyard.com');
-- @@ ledger 20261018111537
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018111537', 'the_bay_line_serves_the_car_that_rejoins_service_soonest', 'chase@ottoyard.com');
-- @@ ledger 20261018111650
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018111650', 'an_evidence_table_refuses_truncate_and_only_a_migration_says_what_is_evidence', 'chase@ottoyard.com');
-- @@ ledger 20261018112027
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018112027', 'every_bay_seat_ends_in_its_leg_and_its_service_record', 'chase@ottoyard.com');
-- @@ ledger 20261018112154
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018112154', 'in_production_only_a_person_answers_a_technician_question', 'chase@ottoyard.com');
-- @@ ledger 20261018112438
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018112438', 'a_service_reported_done_ends_in_its_leg_and_its_service_record', 'chase@ottoyard.com');
-- @@ ledger 20261018112725
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018112725', 'a_repair_waits_for_its_green_light_at_every_door', 'chase@ottoyard.com');
-- @@ ledger 20261018112908
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018112908', 'a_billed_half_hour_holds_thirty_minutes', 'chase@ottoyard.com');
-- @@ ledger 20261018113339
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018113339', 'a_proposal_ages_on_the_clock_it_was_stamped_in', 'chase@ottoyard.com');
-- @@ ledger 20261018113640
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261018113640', 'a_bay_seat_that_finished_early_is_done', 'chase@ottoyard.com');
-- @@ ledger 20261019134637
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261019134637', 'a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges', 'chase@ottoyard.com');
-- @@ ledger 20261020213742
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261020213742', 'a_car_the_cleaning_arm_is_cleaning_keeps_its_stall_when_the_charge_arm_lets_go', 'chase@ottoyard.com');
-- @@ ledger 20261020225005
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261020225005', 'a_car_held_at_its_charger_is_passed_over_by_the_bay_doors', 'chase@ottoyard.com');
-- @@ ledger 20261021022543
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261021022543', 'the_snapshot_says_when_each_cars_bay_work_started_and_ends', 'chase@ottoyard.com');
-- @@ ledger 20261024044503
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261024044503', 'the_agents_board_reads_the_arrival_forecast_without_writing_it', 'chase@ottoyard.com');
-- @@ ledger 20261024163830
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261024163830', 'a_car_that_owes_no_charge_is_ready_for_its_bay_whatever_its_plan_says', 'chase@ottoyard.com');
-- @@ ledger 20261102140211
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261102140211', 'a_car_on_a_charger_comes_to_its_bay_when_the_charge_it_is_on_ends', 'chase@ottoyard.com');
-- @@ ledger 20261103041827
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261103041827', 'a_faulted_post_lets_its_car_go_whatever_the_cleaning_arm_is_doing', 'chase@ottoyard.com');
-- @@ ledger 20261103155140
INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES ('20261103155140', 'the_research_wing_writes_its_findings_where_the_twin_can_read_them', 'chase@ottoyard.com');
