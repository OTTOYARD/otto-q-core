# `pg_stat_user_functions` AFTER `r28_g`

Captured 2026-09-08 18:37:41 UTC, immediately after `r28_g` completed (330 s,
`busy_day / 171717 / 12 ticks`, `track_functions='all'` in its own cron session).
Zero pairs in flight at capture.

Diff against `db/evidence/r28_g_fn_baseline.md` with `scripts/fn-delta.py`.
The delta is exactly `r28_g`'s pair: `track_functions` is `'none'` globally and
only this column sets it, a property re-verified row-by-row at 17:10 UTC across
three intervening certification pairs with not one counter moving.

## The rows

Format: `schema|function|calls|self_time_ms`

```
public|ottoq_policy_get|20529255|882806.0
twin|ottoq_sim_seeded_random|496059|1233.2
public|ottoq_sim_compute_charge_rate|369093|2674.2
public|ottoq_urgency_rank|352760|9976.1
public|ottoq_urgency_max|175488|1748.5
public|ottoq_service_urgency|129360|2614.9
ottoq|ottoq_active_sim_run_id|127848|1545.6
public|ottoq_service_must_do|63148|859.0
public|update_timestamp|48597|338.3
public|ottoq_evaluate_rule_core|42708|45717.1
public|ottoq_resolve_rule_parameters|42708|2778.9
ottoq|ottoq_run_now|39802|699.7
public|ottoq_jsonb_diff|37064|6750.2
public|ottoq_canonicalize_payload|35279|652.1
public|ottoq_compute_event_hash|35279|1134.3
public|ottoq_resolve_signing_secret|35279|424.6
public|ottoq_record_event|33395|62249.2
public|ottoq_sign_event|33395|665.1
public|ottoq_events_slim_new_state|31936|2617.6
public|ottoq_estimate_charge_minutes|30848|1328.3
public|log_vehicle_state_change|27870|6205.7
public|ottoq_vehicles_state_change|27864|6818.3
public|sync_stall_occupancy|27742|1797.1
extensions|digest|23985|356.3
extensions|hmac|23792|102.7
public|ottoq_profile_rate_mult|21007|525.0
public|ottoq_trg_reassignment_guard|18768|487.2
public|ottoq_stalls_state_change|18723|3444.9
ottoq|ottoq_book_stall|17832|14890.4
ottoq|ottoq_find_and_book_stall|15268|16368.9
ottoq|ottoq_stall_free_between|13232|57731.7
public|ottoq_stall_seat_is_exclusive|11942|254.2
public|ottoq_stamp_l2_engine|11655|166.5
public|ottoq_reserve_stall|11217|1789.7
ottoq|ottoq_witness_booking_transition|9372|5239.1
public|ottoq_sample_calibrated|9238|771.5
public|ottoq_depot_local_time|8220|207.4
public|ottoq_approach_zone|7972|37975.4
ottoq|ottoq_booking_why|7400|4260.3
twin|ottoq_sim_clock_salt|7390|599.9
public|ottoq_apply_profile|7198|177.5
public|ottoq_precip_daily_mm|5510|358.9
public|ottoq_stamp_booked_at_sim|5496|298.1
ottoq|ottoq_book_workflow_legs|5452|2325.3
public|ottoq_twin_climate_stress|5371|409.2
public|ottoq_build_decision_context|5168|723.3
ottoq|ottoq_book_hold_stall|4640|13818.7
ottoq|ottoq_arrival_disposition|4352|3750.1
twin|ottoq_sim_lane_capacity|4250|94.2
ottoq|ottoq_emit_vehicle_command|4244|6200.6
ottoq|ottoq_validate_assignment|4244|5659.1
public|ottoq_shield_probe|4167|2071.1
public|ottoq_crn_draw|4032|66.9
ottoq|ottoq_book_workflow|4012|226.7
extensions|uuid_generate_v4|4010|51.8
public|ottoq_eval_en_001_grid_capacity|3924|63078.7
public|ottoq_eval_en_005_grid_event_hardstop|3924|303.0
public|ottoq_eval_hw_001_connector_compatibility|3924|323.0
public|ottoq_eval_hw_002_charger_state|3924|364.7
twin|ottoq_sim_emit_ocpp|3908|4738.8
public|ottoq_arm_interlock_guard|3786|41.2
ottoq|ottoq_vehicle_bay_ready|3554|329.9
public|ottoq_twin_deal|3101|938.5
public|ottoq_eval_hw_003_sensor_liveness|2925|124.5
public|ottoq_trg_leg_done_sdr|2884|392.8
public|ottoq_eval_en_002_stall_power_ceiling|2740|33.6
public|ottoq_eval_en_004_demand_response|2740|170.6
public|ottoq_eval_hw_005_vehicle_one_task|2740|241.6
public|ottoq_eval_sla_006_maintenance_window|2740|97.3
public|ottoq_eval_sm_transition_validity|2740|45.5
public|ottoq_eval_tw_001_operational_hours|2740|173.5
public|ottoq_eval_tw_003_quiet_hours|2740|95.2
public|ottoq_eval_tw_005_shift_buffer|2740|216.6
public|ottoq_comms_envelope|2574|230.6
public|ottoq_cuopt_defer_hold|2528|87.2
public|ottoq_evaluate_return_need|2495|2365.0
public|ottoq_twin_incident_weather_mult|2495|42.9
twin|ottoq_sim_compute_discharge_rate|2495|82.4
twin|ottoq_sim_emit_telemetry|2495|4390.1
twin|ottoq_sim_maybe_incident|2495|36.9
twin|ottoq_sim_maybe_spawn_dtc|2495|38.0
public|ottoq_vehicle_is_tethered|2330|225.6
public|ottoq_l2_external_proposal|2293|270.1
public|ottoq_recall_naive_threshold_v1|2266|5582.1
public|ottoq_depot_running_run|2208|394.1
twin|ottoq_sim_compute_charger_load_kw|2134|18360.0
public|ottoq_honour_reservation_proposal|2127|424.3
public|ottoq_start_concurrent_atoms|2115|2600.6
public|ottoq_plan_visit_itinerary|1995|4430.5
public|ottoq_depot_current_demand_kw|1988|144.6
ottoq|ottoq_atom_retirable|1966|30.4
ottoq|ottoq_record_enacted_booking|1906|10033.3
public|ottoq_emit_sdr|1884|3527.1
public|ottoq_sign_sdr|1884|60.3
public|ottoq_l2_propose_stall_assignment|1827|126247.2
public|ottoq_eval_sm_002_task_transition|1794|94.4
public|ottoq_depot_staffing_count|1782|282.9
public|ottoq_feed_plan|1776|64.6
public|ottoq_comms_emit_telemetry|1767|2278.7
public|ottoq_twin_deal_eta_card|1750|364.8
public|ottoq_return_eta_minutes|1507|25.0
public|ottoq_is_overnight_holdout|1506|67.0
public|ottoq_target_soc_cap|1494|50.9
public|ottoq_get_active_sla|1472|395.6
public|ottoq_auto_generate_incident_report|1459|535.6
public|ottoq_rider_flag_due|1446|32.7
public|ottoq_l2_propose_service|1376|1102.7
public|ottoq_charge_minutes_between|1325|115.3
public|ottoq_twin_deal_fault_card|1323|750.3
ottoq|ottoq_enact_space_assignment|1282|5827.7
public|ottoq_eval_hw_004_stall_concurrency|1184|89.1
public|ottoq_itin_travel_leg|1184|1340.2
public|ottoq_effective_deploy_floor_at|1157|61.5
public|ottoq_effective_reserve_soc|1157|159.8
public|ottoq_close_atom_leg|1146|781.7
twin|ottoq_arm_gauss|990|11.7
public|ottoq_comms_send_command|958|2271.3
public|ottoq_wear_mark_serviced|940|502.6
public|ottoq_is_depot_night|906|177.3
public|ottoq_arm_timings|872|65.4
ottoq|ottoq_decide_wash_triage|838|165.1
public|ottoq_claim_tick_kw|814|699.4
public|ottoq_itin_leg_open|799|2806.1
public|ottoq_brain_deploy_rank|766|73.2
public|ottoq_itin_leg_close|745|191.8
twin|ottoq_sim_sample_lognormal_ms|742|80.8
twin|ottoq_sim_generate_service_manifest|729|1148.0
public|ottoq_twin_arrival_soc_drain|728|13.5
twin|ottoq_sim_build_arrival_payload|728|1246.2
twin|ottoq_sim_emit_arrival_webhook|728|1438.0
ottoq|ottoq_derive_visit_needs|718|3445.7
twin|ottoq_sim_observe_asset|718|396.8
twin|ottoq_sim_poa_irradiance|695|26.4
public|ottoq_dispatch_bump_wash_cycle|610|87.5
public|ottoq_log_deploy_event|610|586.8
twin|ottoq_arm_refuse_move|596|58.9
public|ottoq_indepot_reassignment_guard|582|845.2
twin|ottoq_sim_start_charge_session|561|2929.2
public|ottoq_build_workflow_plan|541|144.1
ottoq|ottoq_book_appointment|525|1968.9
ottoq|ottoq_atom_retirable_set|486|126.3
ottoq|ottoq_atoms_guard|486|135.8
twin|ottoq_sim_service_minutes|451|22.7
twin|ottoq_sim_stop_charge_session|451|1867.0
public|ottoq_visit_wants_detail|416|158.5
public|ottoq_charge_plan_for_visit|413|141.6
public|ottoq_l2_propose_charge_disposition|386|233.8
twin|ottoq_arm_begin_cycle|334|526.8
public|ottoq_mark_visit_atoms_done|326|192.9
twin|ottoq_sim_cell_temp_c|288|4.6
twin|ottoq_sim_pv_dc_power_kw|288|3.3
public|ottoq_record_balance_charge|280|146.9
twin|ottoq_sim_current_tariff|278|85.7
public|ottoq_work_side_accepts|232|24.5
public|ottoq_predict_arrivals|221|320.3
public|ottoq_deploy_target_fraction|219|9.5
public|ottoq_apply_bess_setpoint|195|105.4
public|ottoq_eval_sla_001_min_soc_at_deployment|185|51.3
public|ottoq_eval_sla_003_max_visit_duration|185|4.3
public|ottoq_eval_sla_004_required_services|185|69.2
public|ottoq_eval_sla_005_oem_acceptance_timing|185|10.3
public|ottoq_eval_sla_007_redeployment_readiness|185|40.7
public|ottoq_l2_propose_deploy|185|16.0
public|ottoq_sim_advance_tick|184|182.3
public|ottoq_sim_advance_tick_world|184|3830.8
twin|ottoq_arm_registration_check|165|305.5
ottoq|ottoq_replan_stranded_undercharge|164|21.9
public|ottoq_reconcile_charger_states|145|692.3
ottoq|ottoq_admit_stranded_vehicles|139|676.9
ottoq|ottoq_reoptimize_reservation_book|139|495.9
ottoq|ottoq_sim_prearrival_contracts|139|2176.0
public|ottoq_capture_decision_snapshot|139|1434.9
public|ottoq_comms_advance|139|1426.6
public|ottoq_cuopt_refresh|139|290.6
public|ottoq_decide_tick|139|13424.0
public|ottoq_energy_orchestrate|139|1293.5
public|ottoq_inbound_forecast|139|2698.9
public|ottoq_l2_optimize_assignments|139|1324.1
public|ottoq_l2_propose_bess|139|1064.5
public|ottoq_oem_webhook_collect_responses|139|157.3
public|ottoq_service_priority_propose|139|125.5
public|ottoq_sim_decide_and_dispatch|139|600.7
twin|ottoq_opportunistic_scan|139|416.6
twin|ottoq_sim_advance_all_energy|139|167.2
twin|ottoq_sim_advance_bess|139|591.2
twin|ottoq_sim_advance_charge_sessions|139|2346.8
twin|ottoq_sim_advance_deployed_telemetry|139|3653.0
twin|ottoq_sim_advance_flow_contract|139|13844.6
twin|ottoq_sim_advance_grid|139|5149.8
twin|ottoq_sim_advance_service_flow|139|10774.6
twin|ottoq_sim_advance_site_energy|139|7512.6
twin|ottoq_sim_advance_visit_atoms|139|3333.2
twin|ottoq_sim_advance_wear_counters|139|1243.0
twin|ottoq_sim_advance_weather_and_solar|139|2259.5
twin|ottoq_sim_auto_dispatch_tick|139|778.2
twin|ottoq_sim_bay_fault_handler|139|79.0
twin|ottoq_sim_bess_apply_degradation|139|56.7
twin|ottoq_sim_bess_step|139|944.6
twin|ottoq_sim_clear_sky_ghi_wm2|139|22.3
twin|ottoq_sim_compute_building_load_kw|139|29.3
twin|ottoq_sim_emit_depot_heartbeats|139|2438.5
twin|ottoq_sim_energy_controller|139|252.8
twin|ottoq_sim_generate_arrival_manifests|139|96.3
twin|ottoq_sim_maybe_ignite_dr_call|139|34.8
twin|ottoq_sim_overnight_service_drain|139|614.9
twin|ottoq_sim_reconcile_charge_sessions|139|251.3
twin|ottoq_sim_recover_chargers|139|25.8
twin|ottoq_sim_sample_carbon_intensity|139|302.3
twin|ottoq_sim_sample_frequency_hz|139|11.0
twin|ottoq_sim_sample_lmp_usd_mwh|139|113.6
twin|ottoq_sim_sample_precip_state|139|27.5
twin|ottoq_sim_sample_voltage_event|139|13.3
twin|ottoq_sim_solar_elevation_deg|139|161.5
twin|ottoq_sim_vehicle_exception_handler|139|1738.9
twin|ottoq_sim_wash_triage|139|606.5
ottoq|ottoq_release_visit_artifacts|118|1718.2
twin|ottoq_sim_dispatch_vehicle|118|558.7
ottoq|ottoq_activate_due_bay_reservations|96|1257.6
ottoq|ottoq_activate_present_bookings|96|1905.5
ottoq|ottoq_bind_unbooked_bay_occupants|96|6441.2
ottoq|ottoq_close_satisfied_charge_needs|96|369.6
ottoq|ottoq_enact_inspection_seam|96|19876.4
ottoq|ottoq_link_bookings_to_decisions|96|2270.1
ottoq|ottoq_place_unplaced_vehicles|96|1642.2
ottoq|ottoq_plan_opportunistic_charges|96|544.4
ottoq|ottoq_plan_overnight_drain_admissions|96|388.9
ottoq|ottoq_react_to_refusals|96|1687.2
ottoq|ottoq_readmit_reopened_needs|96|54.3
ottoq|ottoq_reconcile_bay_reservations|96|9484.7
ottoq|ottoq_release_expired_bookings|96|2110.1
ottoq|ottoq_release_vacated_spaces|96|1413.0
ottoq|ottoq_rider_flag_indepot_sweep|96|53.0
public|cuopt_log_gate|96|38.8
public|ottoq_cuopt_defer_roll|96|19.1
public|ottoq_cuopt_first_refusal_arm|96|2.2
public|ottoq_decide_indepot_approvals|96|128.1
public|ottoq_itin_close_travel_legs|96|425.4
public|ottoq_release_expired_tethers|96|183.1
public|ottoq_sweep_stranded_deployments|96|22.8
twin|ottoq_arm_advance_cycles|96|512.9
twin|ottoq_sim_confirm_commands|96|4415.4
ottoq|ottoq_readmit_resumed_visits|94|31.3
public|ottoq_comms_teleop_review|84|137.7
public|ottoq_generate_incident_report|77|1794.8
public|ottoq_replay_window|77|1671.2
public|ottoq_forecast_uncertainty|74|10.2
public|ottoq_build_decision_frame|72|795.3
public|ottoq_effective_charge_cap_kw|72|4.5
public|ottoq_topoff_threshold_soc|72|0.9
twin|ottoq_sim_cloud_attenuated_ghi|72|3.2
ottoq|ottoq_reconcile_displace_stale_claim|68|639.8
ottoq|ottoq_plan_dispatch_tick|66|477.9
public|ottoq_eval_en_003_bess_limits|58|34.8
twin|ottoq_sim_bess_compute_max_power_kw|58|21.2
public|ottoq_rider_flag_mark_served|54|5.1
public|ottoq_rider_flag_placement_guard|48|7.0
twin|ottoq_arm_emergency_release|44|9.3
public|ottoq_bess_reserve_target|43|84.9
public|ottoq_forecast_net_load|43|127.3
public|ottoq_l1_safe_default_deploy|40|0.6
ottoq|ottoq_svc_to_stall_type|38|10.8
pg_catalog|round|32|0.9
ottoq|ottoq_enact_opportunistic_charge|30|20.2
public|ottoq_svc_to_leg_type|30|3.2
ottoq|ottoq_stage_after_tow_retrieval|26|9.6
net|http_post|24|299.7
public|ottoq_submit_external_proposal|16|13.1
public|ottoq_reopen_visit_atoms|12|17.8
public|ottoq_run_config_key|12|29.9
twin|ottoq_sim_prime_deployment|12|815.4
public|ottoq_boot_state_fingerprint|8|4638.1
public|ottoq_calibration_fingerprint|8|28.7
public|ottoq_caller_identity|8|3.4
public|ottoq_engine_hash|8|8.7
public|ottoq_run_config_hash|8|1.0
twin|ottoq_demand_rebook_after_eviction|8|13.4
extensions|pgrst_ddl_watch|6|1.9
ottoq|ottoq_emit_booking_interrupted|6|2.9
public|ottoq_archive_run|6|90.1
public|ottoq_close_run_needs|6|157.9
public|ottoq_mark_reassign_granted|6|0.7
public|ottoq_run_boot_draw|6|693.1
public|ottoq_seed_vehicle_need_profiles|6|154.2
public|ottoq_sim_mark_stopped|6|4.2
public|ottoq_sim_release_depot|6|1185.4
public|ottoq_sim_stop_and_reset|6|3.2
public|ottoq_tg_close_run_needs_on_terminal|6|2.1
public|ottoq_tick_invariance_reset_fleet|6|409.7
twin|ottoq_sim_start_run|6|68.8
ottoq|ottoq_world_fingerprint|4|79.1
public|ottoq_hash_deferrals|4|1.3
public|ottoq_hash_proposals|4|2.5
public|ottoq_hash_recall_decisions|4|5.5
public|ottoq_hash_rule_evaluations|4|332.0
public|ottoq_hash_sdrs|4|158.8
vault|_crypto_aead_det_decrypt|4|7.8
public|ottoq_determinism_pair|3|255965.4
net|_encode_url_with_params_array|2|6.5
net|wake|2|0.5
ottoq|ottoq_booking_authorship|2|0.2
public|ottoq_l1_safe_default_bess|2|0.1
public|ottoq_active_charge_cap_kw|1|0.6
public|ottoq_build_decision_frame|1|7.1
public|ottoq_orchestrator_trigger|1|0.4
```

## Transcription verified 18:54 UTC — and the first check was wrong

These 304 rows were transcribed by hand from the query result. Every G21b number
in `db/checks/0144` rests on them, so they were checksummed against the live view
(safe: `track_functions` is `'none'` globally, so the counters have not moved
since the 18:37 capture).

| | file | database | |
|---|---|---|---|
| rows | 304 | 304 | exact |
| **total calls** | **23,254,422** | **23,254,422** | **exact** |
| calls, `twin` | 537,560 | 537,560 | exact |
| calls, `ottoq` | 271,932 | 271,932 | exact |
| calls, `public` | 22,393,073 | 22,393,073 | exact |
| total self ms | 1,937,195.9 | 1,937,195.8 | **differs by 0.1** |

**The first run of this check printed `*** TRANSCRIPTION ERROR ***`, and the check
was what was wrong.** It compared the float sums with a tolerance of ±0.05. The
database computes `round(sum(self_time), 1)` — full-precision values summed, then
rounded once. The file holds 304 values each already rounded to one decimal, then
summed. Those two operations can legitimately differ by up to `0.05 × 304 = ±15.2 ms`;
the observed difference is **0.1 ms**, three orders of magnitude inside the real
tolerance. A ±0.05 bound on a sum of 304 one-decimal values is arithmetically
impossible to satisfy and should never have been written.

**The integers are what settle it.** Call counts cannot round: an exact match on
23,254,422 across 304 rows, and on all three per-schema subtotals independently,
is conclusive. The transcription is correct.

Recorded because the failure mode — an assertion firing on correct data and being
believed — is the same one that made `cron.job_run_details` claim a running pair
had finished in one second, twice, earlier the same afternoon.
