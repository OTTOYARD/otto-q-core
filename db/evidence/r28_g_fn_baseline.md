# `pg_stat_user_functions` baseline for `r28_g`

**Captured 2026-09-08 16:23:39 UTC. All 304 rows, not a hand-picked subset —
which is the whole point.** `r27_g`'s baseline recorded fourteen rows I expected
to matter, so no delta was computable for anything outside that list, and
`db/checks/0141` Q5 could not name the caller of 13.2M `ottoq_policy_get` calls.
`db/canons/round28.md` instructs `r28_g` to avoid exactly that.

## Why this capture is valid from now until `r28_g` fires

`SHOW track_functions` is **`none`** globally, and only the instrumented column
sets it (`'all'`, in its own cron session). So nothing between this capture and
`r28_g` contributes a single counter, and the post-`g` delta is exactly `g`'s
pair. The same property was verified row-by-row for `r27_g` across 91 minutes
and a container restart, and not one counter had moved.

## What the totals already say, before `r28_g` runs

These are **lifetime** totals dominated by the two instrumented pairs ever run
(`r25_g` at 12 ticks under `track_functions='pl'`, `r27_g` at 24 ticks under
`'all'`), so they are not per-pair figures. But one thing is legible without any
delta:

| function | lifetime calls |
|---|---|
| `public.ottoq_policy_get` | **15,634,388** |
| `twin.ottoq_sim_seeded_random` | 356,072 |
| `public.ottoq_sim_compute_charge_rate` | 266,181 |
| `public.ottoq_urgency_rank` | 242,552 |
| `public.ottoq_urgency_max` | 120,704 |
| `ottoq.ottoq_active_sim_run_id` | 91,244 |
| `public.ottoq_service_urgency` | 89,040 |

**`ottoq_policy_get` is 44x the next function and roughly an order of magnitude
more than every other tracked function combined.** That is the shape of a
function called from SQL the profiler cannot attribute — inline expressions in
the engine's queries — rather than from plpgsql bodies, because no tracked
caller has anything like the call count needed to produce it.

Two candidate ratios worth checking against `r28_g`'s delta rather than
believing now: 13,217,464 / 242,552 = **54.5 per `ottoq_urgency_rank`**, and
13,217,464 / 266,181 = **49.7 per `ottoq_sim_compute_charge_rate`**. Neither is
a suspiciously round number and both are arithmetic on lifetime totals against a
single-pair delta, which is not a valid comparison. **They are written down as
things to test, not as findings.** `db/checks/0139` spent its closing paragraph
refusing to guess the caller; this file keeps that discipline.

## The rows

Format: `schema|function|calls|self_time_ms`

```
public|ottoq_policy_get|15634388|683157.5
twin|ottoq_sim_seeded_random|356072|902.7
public|ottoq_sim_compute_charge_rate|266181|1936.7
public|ottoq_urgency_rank|242552|6935.8
public|ottoq_urgency_max|120704|1222.0
ottoq|ottoq_active_sim_run_id|91244|1114.4
public|ottoq_service_urgency|89040|1830.1
public|ottoq_service_must_do|41359|569.6
public|update_timestamp|34815|247.3
public|ottoq_resolve_rule_parameters|30908|2067.8
public|ottoq_evaluate_rule_core|30908|35064.3
ottoq|ottoq_run_now|28236|492.8
public|ottoq_jsonb_diff|26686|4897.6
public|ottoq_compute_event_hash|25321|1049.4
public|ottoq_canonicalize_payload|25321|472.7
public|ottoq_resolve_signing_secret|25321|316.4
public|ottoq_sign_event|23987|481.5
public|ottoq_record_event|23987|49274.5
public|ottoq_estimate_charge_minutes|23236|975.8
public|ottoq_events_slim_new_state|22528|1852.5
public|log_vehicle_state_change|20352|4829.2
public|ottoq_vehicles_state_change|20348|4903.1
public|sync_stall_occupancy|20250|1274.1
public|ottoq_profile_rate_mult|15683|421.8
ottoq|ottoq_book_stall|15136|11108.0
extensions|digest|14003|208.3
extensions|hmac|13834|59.2
public|ottoq_trg_reassignment_guard|13022|369.3
public|ottoq_stalls_state_change|13001|2332.6
ottoq|ottoq_find_and_book_stall|11242|15923.4
public|ottoq_stamp_l2_engine|8679|128.5
ottoq|ottoq_stall_free_between|8362|39557.6
public|ottoq_stall_seat_is_exclusive|8310|186.5
public|ottoq_reserve_stall|7521|1255.0
public|ottoq_sample_calibrated|6700|629.9
ottoq|ottoq_witness_booking_transition|6414|3708.8
public|ottoq_depot_local_time|5946|153.2
public|ottoq_approach_zone|5636|27794.8
public|ottoq_apply_profile|5460|142.5
ottoq|ottoq_booking_why|5024|3526.9
twin|ottoq_sim_clock_salt|4504|372.5
public|ottoq_precip_daily_mm|4034|301.7
ottoq|ottoq_book_workflow_legs|4012|2056.8
public|ottoq_twin_climate_stress|3919|321.1
public|ottoq_stamp_booked_at_sim|3738|208.2
public|ottoq_build_decision_context|3702|556.4
ottoq|ottoq_book_hold_stall|3498|10883.2
ottoq|ottoq_arrival_disposition|3288|2836.3
twin|ottoq_sim_lane_capacity|3115|74.0
ottoq|ottoq_emit_vehicle_command|3018|4570.1
ottoq|ottoq_validate_assignment|3018|5460.0
public|ottoq_shield_probe|3015|1574.4
twin|ottoq_sim_emit_ocpp|2830|3831.6
public|ottoq_eval_hw_001_connector_compatibility|2778|240.1
public|ottoq_eval_hw_002_charger_state|2778|264.1
public|ottoq_eval_en_005_grid_event_hardstop|2778|233.9
public|ottoq_eval_en_001_grid_capacity|2778|63024.1
public|ottoq_arm_interlock_guard|2658|29.2
ottoq|ottoq_book_workflow|2572|158.9
ottoq|ottoq_vehicle_bay_ready|2462|258.8
extensions|uuid_generate_v4|2322|30.8
public|ottoq_crn_draw|2284|39.0
public|ottoq_twin_deal|2207|775.2
public|ottoq_eval_hw_003_sensor_liveness|2167|99.6
public|ottoq_trg_leg_done_sdr|2064|279.7
public|ottoq_vehicle_is_tethered|2038|207.6
public|ottoq_eval_tw_003_quiet_hours|1982|69.9
public|ottoq_eval_en_004_demand_response|1982|125.1
public|ottoq_eval_en_002_stall_power_ceiling|1982|24.5
public|ottoq_eval_tw_001_operational_hours|1982|128.0
public|ottoq_eval_tw_005_shift_buffer|1982|151.9
public|ottoq_eval_sla_006_maintenance_window|1982|71.7
public|ottoq_eval_hw_005_vehicle_one_task|1982|178.9
public|ottoq_eval_sm_transition_validity|1982|34.1
twin|ottoq_sim_maybe_spawn_dtc|1873|31.4
twin|ottoq_sim_compute_discharge_rate|1873|68.6
twin|ottoq_sim_emit_telemetry|1873|3753.9
public|ottoq_evaluate_return_need|1873|2064.4
public|ottoq_twin_incident_weather_mult|1873|34.2
twin|ottoq_sim_maybe_incident|1873|29.8
public|ottoq_recall_naive_threshold_v1|1644|4444.3
public|ottoq_comms_envelope|1616|143.2
public|ottoq_cuopt_defer_hold|1522|54.5
public|ottoq_start_concurrent_atoms|1467|1927.8
public|ottoq_honour_reservation_proposal|1465|329.1
public|ottoq_auto_generate_incident_report|1459|535.6
public|ottoq_rider_flag_due|1446|32.7
public|ottoq_comms_emit_telemetry|1377|1984.6
public|ottoq_twin_deal_eta_card|1360|308.6
public|ottoq_l2_external_proposal|1355|160.5
public|ottoq_plan_visit_itinerary|1349|3292.4
public|ottoq_emit_sdr|1334|2635.1
public|ottoq_sign_sdr|1334|44.0
ottoq|ottoq_record_enacted_booking|1288|7165.5
public|ottoq_l2_propose_stall_assignment|1259|125712.4
public|ottoq_depot_running_run|1204|220.1
twin|ottoq_sim_compute_charger_load_kw|1130|17899.0
public|ottoq_get_active_sla|1074|280.7
public|ottoq_eval_sm_002_task_transition|1036|55.2
public|ottoq_depot_current_demand_kw|1032|81.6
ottoq|ottoq_atom_retirable|1024|16.4
public|ottoq_l2_propose_service|1018|830.5
public|ottoq_feed_plan|1014|41.3
public|ottoq_depot_staffing_count|973|157.2
public|ottoq_twin_deal_fault_card|971|659.9
public|ottoq_return_eta_minutes|953|16.4
public|ottoq_is_overnight_holdout|926|43.3
public|ottoq_charge_minutes_between|903|80.6
public|ottoq_itin_travel_leg|890|1035.5
ottoq|ottoq_enact_space_assignment|890|4632.8
public|ottoq_target_soc_cap|850|29.2
public|ottoq_close_atom_leg|830|710.1
public|ottoq_eval_hw_004_stall_concurrency|796|63.2
public|ottoq_effective_deploy_floor_at|767|47.5
public|ottoq_effective_reserve_soc|767|137.2
public|ottoq_brain_deploy_rank|766|73.2
twin|ottoq_arm_gauss|708|8.3
public|ottoq_comms_send_command|696|1776.8
public|ottoq_wear_mark_serviced|674|395.2
public|ottoq_arm_timings|634|48.0
ottoq|ottoq_decide_wash_triage|584|112.5
twin|ottoq_sim_poa_irradiance|575|25.7
public|ottoq_itin_leg_open|571|2145.0
public|ottoq_itin_leg_close|565|163.9
twin|ottoq_sim_sample_lognormal_ms|506|64.3
public|ottoq_is_depot_night|504|100.1
twin|ottoq_sim_generate_service_manifest|497|1118.1
twin|ottoq_sim_build_arrival_payload|496|893.9
twin|ottoq_sim_emit_arrival_webhook|496|1129.9
public|ottoq_twin_arrival_soc_drain|496|9.8
ottoq|ottoq_derive_visit_needs|486|2624.7
twin|ottoq_sim_observe_asset|486|275.8
public|ottoq_indepot_reassignment_guard|454|657.8
public|ottoq_dispatch_bump_wash_cycle|446|84.7
public|ottoq_log_deploy_event|446|470.9
public|ottoq_claim_tick_kw|426|378.7
twin|ottoq_arm_refuse_move|416|40.8
twin|ottoq_sim_start_charge_session|395|2353.0
twin|ottoq_sim_service_minutes|377|21.1
public|ottoq_build_workflow_plan|375|109.1
ottoq|ottoq_book_appointment|361|1436.9
twin|ottoq_sim_stop_charge_session|337|1403.5
public|ottoq_charge_plan_for_visit|287|121.7
public|ottoq_l2_propose_charge_disposition|278|178.5
public|ottoq_mark_visit_atoms_done|258|165.8
ottoq|ottoq_atoms_guard|254|72.9
ottoq|ottoq_atom_retirable_set|254|66.0
public|ottoq_visit_wants_detail|244|95.8
twin|ottoq_arm_begin_cycle|234|382.3
twin|ottoq_sim_current_tariff|230|80.6
public|ottoq_record_balance_charge|202|108.9
twin|ottoq_sim_pv_dc_power_kw|192|2.3
twin|ottoq_sim_cell_temp_c|192|3.1
public|ottoq_predict_arrivals|191|286.6
public|ottoq_eval_sla_005_oem_acceptance_timing|185|10.3
public|ottoq_eval_sla_001_min_soc_at_deployment|185|51.3
public|ottoq_eval_sla_003_max_visit_duration|185|4.3
public|ottoq_eval_sla_007_redeployment_readiness|185|40.7
public|ottoq_eval_sla_004_required_services|185|69.2
public|ottoq_l2_propose_deploy|185|16.0
public|ottoq_apply_bess_setpoint|165|101.4
public|ottoq_sim_advance_tick|160|178.1
public|ottoq_sim_advance_tick_world|160|3636.7
public|ottoq_work_side_accepts|158|16.9
public|ottoq_deploy_target_fraction|147|6.3
ottoq|ottoq_replan_stranded_undercharge|120|16.6
public|ottoq_reconcile_charger_states|119|549.4
ottoq|ottoq_release_visit_artifacts|118|1718.2
twin|ottoq_sim_dispatch_vehicle|118|558.7
twin|ottoq_arm_registration_check|118|225.8
public|ottoq_comms_advance|115|1358.6
twin|ottoq_sim_advance_service_flow|115|8949.6
public|ottoq_energy_orchestrate|115|1165.9
twin|ottoq_sim_vehicle_exception_handler|115|1397.0
twin|ottoq_sim_wash_triage|115|434.0
twin|ottoq_sim_advance_weather_and_solar|115|2093.3
twin|ottoq_sim_solar_elevation_deg|115|159.2
twin|ottoq_sim_bess_apply_degradation|115|51.8
twin|ottoq_sim_compute_building_load_kw|115|27.9
twin|ottoq_sim_advance_site_energy|115|7369.5
twin|ottoq_sim_sample_lmp_usd_mwh|115|106.9
twin|ottoq_sim_advance_visit_atoms|115|2343.4
twin|ottoq_sim_advance_wear_counters|115|1044.3
twin|ottoq_sim_sample_carbon_intensity|115|301.4
twin|ottoq_sim_bay_fault_handler|115|65.1
public|ottoq_inbound_forecast|115|2107.2
twin|ottoq_sim_sample_voltage_event|115|12.6
twin|ottoq_sim_clear_sky_ghi_wm2|115|22.0
public|ottoq_sim_decide_and_dispatch|115|551.6
twin|ottoq_opportunistic_scan|115|397.6
twin|ottoq_sim_auto_dispatch_tick|115|633.6
public|ottoq_capture_decision_snapshot|115|1347.4
public|ottoq_l2_propose_bess|115|858.2
public|ottoq_service_priority_propose|115|114.5
twin|ottoq_sim_bess_step|115|895.4
twin|ottoq_sim_sample_frequency_hz|115|10.4
public|ottoq_oem_webhook_collect_responses|115|152.1
twin|ottoq_sim_sample_precip_state|115|26.6
twin|ottoq_sim_recover_chargers|115|23.0
ottoq|ottoq_reoptimize_reservation_book|115|467.3
twin|ottoq_sim_overnight_service_drain|115|484.5
twin|ottoq_sim_maybe_ignite_dr_call|115|32.8
public|ottoq_l2_optimize_assignments|115|978.7
ottoq|ottoq_admit_stranded_vehicles|115|576.3
twin|ottoq_sim_advance_deployed_telemetry|115|2891.6
twin|ottoq_sim_advance_charge_sessions|115|1850.8
twin|ottoq_sim_advance_grid|115|5087.1
ottoq|ottoq_sim_prearrival_contracts|115|1605.1
twin|ottoq_sim_generate_arrival_manifests|115|78.5
public|ottoq_cuopt_refresh|115|288.7
twin|ottoq_sim_advance_all_energy|115|155.3
public|ottoq_decide_tick|115|11005.5
twin|ottoq_sim_energy_controller|115|232.4
twin|ottoq_sim_advance_bess|115|502.0
twin|ottoq_sim_advance_flow_contract|115|12136.6
twin|ottoq_sim_emit_depot_heartbeats|115|1947.0
twin|ottoq_sim_reconcile_charge_sessions|115|208.1
public|ottoq_generate_incident_report|77|1794.8
public|ottoq_replay_window|77|1671.2
public|ottoq_release_expired_tethers|72|138.6
ottoq|ottoq_activate_present_bookings|72|1411.2
ottoq|ottoq_close_satisfied_charge_needs|72|277.2
ottoq|ottoq_link_bookings_to_decisions|72|1574.1
ottoq|ottoq_plan_opportunistic_charges|72|453.8
ottoq|ottoq_plan_overnight_drain_admissions|72|288.6
ottoq|ottoq_react_to_refusals|72|1439.9
ottoq|ottoq_rider_flag_indepot_sweep|72|35.8
public|ottoq_itin_close_travel_legs|72|334.1
ottoq|ottoq_bind_unbooked_bay_occupants|72|4559.3
ottoq|ottoq_release_vacated_spaces|72|1093.9
ottoq|ottoq_reconcile_bay_reservations|72|6813.6
ottoq|ottoq_readmit_reopened_needs|72|41.9
ottoq|ottoq_enact_inspection_seam|72|16825.4
ottoq|ottoq_release_expired_bookings|72|1598.9
ottoq|ottoq_activate_due_bay_reservations|72|971.4
public|cuopt_log_gate|72|28.5
public|ottoq_cuopt_defer_roll|72|13.8
public|ottoq_cuopt_first_refusal_arm|72|1.6
public|ottoq_decide_indepot_approvals|72|98.1
ottoq|ottoq_place_unplaced_vehicles|72|1273.9
public|ottoq_sweep_stranded_deployments|72|16.5
twin|ottoq_arm_advance_cycles|72|384.9
twin|ottoq_sim_confirm_commands|72|3304.9
ottoq|ottoq_readmit_resumed_visits|70|23.1
public|ottoq_comms_teleop_review|62|107.5
ottoq|ottoq_plan_dispatch_tick|56|383.3
ottoq|ottoq_reconcile_displace_stale_claim|54|500.0
twin|ottoq_sim_bess_compute_max_power_kw|52|20.0
public|ottoq_eval_en_003_bess_limits|52|33.2
public|ottoq_forecast_uncertainty|50|7.5
public|ottoq_build_decision_frame|48|571.0
public|ottoq_topoff_threshold_soc|48|0.6
public|ottoq_effective_charge_cap_kw|48|2.9
twin|ottoq_sim_cloud_attenuated_ghi|48|2.1
public|ottoq_forecast_net_load|43|127.3
public|ottoq_bess_reserve_target|43|84.9
public|ottoq_l1_safe_default_deploy|40|0.6
twin|ottoq_arm_emergency_release|34|7.1
public|ottoq_rider_flag_mark_served|32|3.4
public|ottoq_rider_flag_placement_guard|28|4.4
net|http_post|24|299.7
ottoq|ottoq_enact_opportunistic_charge|22|15.1
ottoq|ottoq_svc_to_stall_type|22|6.7
ottoq|ottoq_stage_after_tow_retrieval|18|6.9
pg_catalog|round|17|0.5
public|ottoq_svc_to_leg_type|15|1.5
public|ottoq_submit_external_proposal|12|11.1
public|ottoq_reopen_visit_atoms|10|14.4
twin|ottoq_sim_prime_deployment|8|563.0
twin|ottoq_demand_rebook_after_eviction|6|8.0
extensions|pgrst_ddl_watch|6|1.9
ottoq|ottoq_emit_booking_interrupted|6|2.9
public|ottoq_run_config_key|6|15.1
public|ottoq_tick_invariance_reset_fleet|4|287.0
public|ottoq_run_config_hash|4|0.5
public|ottoq_tg_close_run_needs_on_terminal|4|1.3
public|ottoq_sim_stop_and_reset|4|2.2
public|ottoq_run_boot_draw|4|475.1
public|ottoq_engine_hash|4|4.7
public|ottoq_close_run_needs|4|120.8
public|ottoq_mark_reassign_granted|4|0.5
public|ottoq_boot_state_fingerprint|4|3651.7
public|ottoq_archive_run|4|77.5
twin|ottoq_sim_start_run|4|58.1
public|ottoq_caller_identity|4|1.7
public|ottoq_calibration_fingerprint|4|16.8
public|ottoq_seed_vehicle_need_profiles|4|109.0
public|ottoq_sim_mark_stopped|4|2.8
public|ottoq_sim_release_depot|4|876.7
vault|_crypto_aead_det_decrypt|3|7.7
public|ottoq_hash_deferrals|2|0.7
public|ottoq_hash_sdrs|2|101.7
net|_encode_url_with_params_array|2|6.5
net|wake|2|0.5
public|ottoq_hash_rule_evaluations|2|195.3
public|ottoq_determinism_pair|2|255864.6
public|ottoq_hash_recall_decisions|2|4.0
ottoq|ottoq_world_fingerprint|2|40.6
public|ottoq_l1_safe_default_bess|2|0.1
public|ottoq_hash_proposals|2|1.3
public|ottoq_build_decision_frame|1|7.1
public|ottoq_active_charge_cap_kw|1|0.6
ottoq|ottoq_booking_authorship|1|0.1
public|ottoq_orchestrator_trigger|1|0.4
```

## ADDENDUM 2026-09-08 16:53 UTC — this file has two rows for one name

Found while testing `scripts/fn-delta.py` against this file, before `r28_g`
fires. `public|ottoq_build_decision_frame` appears **twice** — 48 calls / 571.0 ms
at line 303 and 1 call / 7.1 ms at line 353.

That is not a capture error. `pg_stat_user_functions` is keyed by **`funcid`**,
and `ottoq_build_decision_frame` is **overloaded** — two functions, one name, two
rows. The capture is faithful; what it omits is the argument types that would
tell the two apart.

**Consequence for the `r28_g` diff:** the delta is computed by summing rows that
share a schema and name, so the total per name is right and per-overload
attribution is unavailable. The tool prints that aggregation rather than
silently collapsing it. This affects exactly one of 303 names, and it is not one
of the names `r28_g` is being run to measure (`ottoq_sim_compute_charger_load_kw`,
`ottoq_policy_get`, and `ottoq_policy_get`'s callers), so no conclusion of round
28 rests on it.

**For the next instrumented column:** select `funcid` alongside the four columns
so overloads are separable. This baseline cannot be re-captured — `r28_g`'s
validity depends on it having been taken before the pair — so the fix lands in
the capture that follows, not in this one.
