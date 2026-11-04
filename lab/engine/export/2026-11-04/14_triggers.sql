-- 14_triggers.sql: 237 statements, exported from production's catalog
-- @@ trigger public.api_integrations.trg_api_integrations_updated
CREATE TRIGGER trg_api_integrations_updated BEFORE UPDATE ON public.api_integrations FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.bay_reservation_reconcile_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.bay_reservation_reconcile_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.booking_ledger_proof_2026_08_01.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.booking_ledger_proof_2026_08_01 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.booking_ledger_proof_bk_2026_08_01.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.booking_ledger_proof_bk_2026_08_01 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.build2_bookings_raw_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.build2_bookings_raw_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.build2_cert_424242.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.build2_cert_424242 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.build2_interrupted_recount_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.build2_interrupted_recount_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.build2_visit_needs_raw_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.build2_visit_needs_raw_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.build3_pre_bookings_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.build3_pre_bookings_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.build3_pre_legs_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.build3_pre_legs_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.build3_smoke_bookings_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.build3_smoke_bookings_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.build3_smoke_legs_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.build3_smoke_legs_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.busy_day_tick_probe_2026_08_01.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.busy_day_tick_probe_2026_08_01 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0020_runa_snapshot.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0020_runa_snapshot FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_a_after_b.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_a_after_b FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_a_bookings.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_a_bookings FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_a_dispatches.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_a_dispatches FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_a_flags.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_a_flags FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_a_runrow.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_a_runrow FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_a_visitneeds.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_a_visitneeds FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_b_bookings.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_b_bookings FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_b_dispatches.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_b_dispatches FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_b_flags.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_b_flags FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_b_runrow.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_b_runrow FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0022_b_visitneeds.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0022_b_visitneeds FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_a_bookings.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_a_bookings FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_a_dispatches.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_a_dispatches FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_a_energy.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_a_energy FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_a_flags.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_a_flags FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_a_running.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_a_running FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_a_runrow.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_a_runrow FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_a_visitneeds.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_a_visitneeds FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_b_bookings.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_b_bookings FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_b_dispatches.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_b_dispatches FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_b_energy.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_b_energy FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_b_flags.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_b_flags FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_b_runrow.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_b_runrow FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_b_visitneeds.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_b_visitneeds FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_c_needs_before.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_c_needs_before FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_c_needs_terminal.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_c_needs_terminal FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cert0023_stop_pre.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cert0023_stop_pre FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.charger_cooldowns.trg_cooldowns_updated
CREATE TRIGGER trg_cooldowns_updated BEFORE UPDATE ON public.charger_cooldowns FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.charger_health_scores.trg_charger_health_updated
CREATE TRIGGER trg_charger_health_updated BEFORE UPDATE ON public.charger_health_scores FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.cuopt_invocation_log.cuopt_invocation_log_no_update
CREATE TRIGGER cuopt_invocation_log_no_update BEFORE UPDATE ON public.cuopt_invocation_log FOR EACH ROW EXECUTE FUNCTION public.cuopt_invocation_log_append_only();
-- @@ trigger public.cuopt_invocation_log.ottoq_capture_cuopt_model_call_trg
CREATE TRIGGER ottoq_capture_cuopt_model_call_trg AFTER INSERT ON public.cuopt_invocation_log FOR EACH ROW WHEN ((new.http_status IS NOT NULL)) EXECUTE FUNCTION public.ottoq_capture_cuopt_model_call();
-- @@ trigger public.cuopt_supply_before_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cuopt_supply_before_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cuopt_supply_ledger_2026_08_03.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cuopt_supply_ledger_2026_08_03 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.cuopt_supply_proof_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.cuopt_supply_proof_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.depots.trg_depots_updated
CREATE TRIGGER trg_depots_updated BEFORE UPDATE ON public.depots FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.emergency_queue_insertions.trg_emergency_insertions_updated
CREATE TRIGGER trg_emergency_insertions_updated BEFORE UPDATE ON public.emergency_queue_insertions FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.engine_config.trg_engine_config_updated
CREATE TRIGGER trg_engine_config_updated BEFORE UPDATE ON public.engine_config FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.exceptions.trg_exceptions_updated
CREATE TRIGGER trg_exceptions_updated BEFORE UPDATE ON public.exceptions FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.fleet_operators.trg_fleet_operators_updated
CREATE TRIGGER trg_fleet_operators_updated BEFORE UPDATE ON public.fleet_operators FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.fwd2_pre909_card.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.fwd2_pre909_card FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.fwd2_pre909_runrow.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.fwd2_pre909_runrow FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.fwd2_urgency_samples.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.fwd2_urgency_samples FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.fwd3_postboot_wear.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.fwd3_postboot_wear FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.fwd3_postrun_bookings.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.fwd3_postrun_bookings FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.fwd3_postrun_legs.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.fwd3_postrun_legs FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.fwd3_postrun_wear.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.fwd3_postrun_wear FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.fwd3_prerun_wear.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.fwd3_prerun_wear FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.integration_health.trg_integration_health_updated
CREATE TRIGGER trg_integration_health_updated BEFORE UPDATE ON public.integration_health FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.maintenance_schedules.trg_maintenance_schedules_updated
CREATE TRIGGER trg_maintenance_schedules_updated BEFORE UPDATE ON public.maintenance_schedules FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.mig0003_smoke_receipt_bookings.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.mig0003_smoke_receipt_bookings FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.mig0003_smoke_receipt_decisions.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.mig0003_smoke_receipt_decisions FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.mig0006_runrows.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.mig0006_runrows FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.mig0006_smoke.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.mig0006_smoke FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.mig0009_pre_dispatches.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.mig0009_pre_dispatches FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.mig0009_pre_visit_needs.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.mig0009_pre_visit_needs FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.mig0009_run920_dispatches.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.mig0009_run920_dispatches FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ocpp_sessions.ottoq_capture_charge_duration_trg
CREATE TRIGGER ottoq_capture_charge_duration_trg AFTER UPDATE OF stopped_reason ON public.ocpp_sessions FOR EACH ROW WHEN (((new.stopped_reason IS NOT NULL) AND (old.stopped_reason IS NULL))) EXECUTE FUNCTION public.ottoq_capture_charge_duration();
-- @@ trigger public.ocpp_sessions.trg_ocpp_sessions_updated
CREATE TRIGGER trg_ocpp_sessions_updated BEFORE UPDATE ON public.ocpp_sessions FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.ottoq_ab_runs.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_ab_runs FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_agent_call_ledger.ottoq_agent_call_ledger_append_only_trg
CREATE TRIGGER ottoq_agent_call_ledger_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_agent_call_ledger FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_ledger_append_only();
-- @@ trigger public.ottoq_agent_call_ledger.ottoq_agent_call_ledger_no_truncate_trg
CREATE TRIGGER ottoq_agent_call_ledger_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_agent_call_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- @@ trigger public.ottoq_agent_charge_orders.ottoq_agent_charge_orders_append_only_trg
CREATE TRIGGER ottoq_agent_charge_orders_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_agent_charge_orders FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_charge_orders_append_only();
-- @@ trigger public.ottoq_agent_charge_orders.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_agent_charge_orders FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_agent_pass_evidence.ottoq_agent_pass_evidence_append_only_trg
CREATE TRIGGER ottoq_agent_pass_evidence_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_agent_pass_evidence FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_evidence_append_only();
-- @@ trigger public.ottoq_agent_pass_evidence.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_agent_pass_evidence FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_agent_principals.ottoq_agent_principals_guard_trg
CREATE TRIGGER ottoq_agent_principals_guard_trg BEFORE DELETE OR UPDATE ON public.ottoq_agent_principals FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_principals_guard();
-- @@ trigger public.ottoq_agent_principals.ottoq_agent_principals_no_truncate_trg
CREATE TRIGGER ottoq_agent_principals_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_agent_principals FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- @@ trigger public.ottoq_agent_prompts.ottoq_agent_prompts_append_only_trg
CREATE TRIGGER ottoq_agent_prompts_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_agent_prompts FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_evidence_append_only();
-- @@ trigger public.ottoq_agent_requests.ottoq_agent_requests_guard_trg
CREATE TRIGGER ottoq_agent_requests_guard_trg BEFORE DELETE OR UPDATE ON public.ottoq_agent_requests FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_requests_guard();
-- @@ trigger public.ottoq_agent_requests.ottoq_agent_requests_no_truncate_trg
CREATE TRIGGER ottoq_agent_requests_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_agent_requests FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- @@ trigger public.ottoq_anomaly_observations.trg_ottoq_anomaly_observations_no_delete
CREATE TRIGGER trg_ottoq_anomaly_observations_no_delete BEFORE DELETE ON public.ottoq_anomaly_observations FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_arbiter_assessments.ottoq_arbiter_assessments_append_only_trg
CREATE TRIGGER ottoq_arbiter_assessments_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_arbiter_assessments FOR EACH ROW EXECUTE FUNCTION public.ottoq_hindsight_append_only();
-- @@ trigger public.ottoq_bess_units.trg_ottoq_bess_units_state_change
CREATE TRIGGER trg_ottoq_bess_units_state_change AFTER UPDATE OF current_state ON public.ottoq_bess_units FOR EACH ROW WHEN ((new.current_state IS DISTINCT FROM old.current_state)) EXECUTE FUNCTION public.ottoq_bess_units_state_change();
-- @@ trigger public.ottoq_calibration_correlations.ottoq_calibration_write_guard
CREATE TRIGGER ottoq_calibration_write_guard BEFORE INSERT OR DELETE OR UPDATE ON public.ottoq_calibration_correlations FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_calibration_write_guard();
-- @@ trigger public.ottoq_calibration_datasets.ottoq_calibration_write_guard
CREATE TRIGGER ottoq_calibration_write_guard BEFORE INSERT OR DELETE OR UPDATE ON public.ottoq_calibration_datasets FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_calibration_write_guard();
-- @@ trigger public.ottoq_calibration_distributions.ottoq_calibration_write_guard
CREATE TRIGGER ottoq_calibration_write_guard BEFORE INSERT OR DELETE OR UPDATE ON public.ottoq_calibration_distributions FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_calibration_write_guard();
-- @@ trigger public.ottoq_calibration_profiles.ottoq_calibration_write_guard
CREATE TRIGGER ottoq_calibration_write_guard BEFORE INSERT OR DELETE OR UPDATE ON public.ottoq_calibration_profiles FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_calibration_write_guard();
-- @@ trigger public.ottoq_challenger_findings.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_challenger_findings FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_channel_health.ottoq_channel_health_append_only_trg
CREATE TRIGGER ottoq_channel_health_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_channel_health FOR EACH ROW EXECUTE FUNCTION public.ottoq_channel_health_append_only();
-- @@ trigger public.ottoq_channel_health.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_channel_health FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_charge_clock_fits.ottoq_charge_clock_fits_append_only_trg
CREATE TRIGGER ottoq_charge_clock_fits_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_charge_clock_fits FOR EACH ROW EXECUTE FUNCTION public.ottoq_charge_clock_fits_append_only();
-- @@ trigger public.ottoq_charge_duration_ledger.ottoq_charge_duration_ledger_append_only_trg
CREATE TRIGGER ottoq_charge_duration_ledger_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_charge_duration_ledger FOR EACH ROW EXECUTE FUNCTION public.ottoq_charge_duration_ledger_append_only();
-- @@ trigger public.ottoq_charge_duration_ledger.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_charge_duration_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_charge_fault_fits.ottoq_charge_fault_fits_append_only_trg
CREATE TRIGGER ottoq_charge_fault_fits_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_charge_fault_fits FOR EACH ROW EXECUTE FUNCTION public.ottoq_charge_fault_fits_append_only();
-- @@ trigger public.ottoq_charge_order_attribution.ottoq_charge_order_attribution_append_only_trg
CREATE TRIGGER ottoq_charge_order_attribution_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_charge_order_attribution FOR EACH ROW EXECUTE FUNCTION public.ottoq_hindsight_append_only();
-- @@ trigger public.ottoq_charge_order_attribution.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_charge_order_attribution FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_charge_order_hindsight.ottoq_charge_order_hindsight_append_only_trg
CREATE TRIGGER ottoq_charge_order_hindsight_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_charge_order_hindsight FOR EACH ROW EXECUTE FUNCTION public.ottoq_hindsight_append_only();
-- @@ trigger public.ottoq_charge_order_hindsight.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_charge_order_hindsight FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_charge_order_reattributions.ottoq_charge_order_reattributions_append_only_trg
CREATE TRIGGER ottoq_charge_order_reattributions_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_charge_order_reattributions FOR EACH ROW EXECUTE FUNCTION public.ottoq_hindsight_append_only();
-- @@ trigger public.ottoq_charge_order_reattributions.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_charge_order_reattributions FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_charge_order_regrades.ottoq_charge_order_regrades_append_only_trg
CREATE TRIGGER ottoq_charge_order_regrades_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_charge_order_regrades FOR EACH ROW EXECUTE FUNCTION public.ottoq_hindsight_append_only();
-- @@ trigger public.ottoq_charge_order_regrades.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_charge_order_regrades FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_charge_order_snapshots.ottoq_charge_order_snapshots_append_only_trg
CREATE TRIGGER ottoq_charge_order_snapshots_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_charge_order_snapshots FOR EACH ROW EXECUTE FUNCTION public.ottoq_charge_order_snapshots_append_only();
-- @@ trigger public.ottoq_charge_order_snapshots.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_charge_order_snapshots FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_charge_window_calibration.ottoq_charge_window_calibration_append_only_trg
CREATE TRIGGER ottoq_charge_window_calibration_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_charge_window_calibration FOR EACH ROW EXECUTE FUNCTION public.ottoq_charge_window_calibration_append_only();
-- @@ trigger public.ottoq_counterfactuals.trg_ottoq_counterfactuals_no_delete
CREATE TRIGGER trg_ottoq_counterfactuals_no_delete BEFORE DELETE ON public.ottoq_counterfactuals FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_decisions.ottoq_capture_decision_model_call_trg
CREATE TRIGGER ottoq_capture_decision_model_call_trg AFTER INSERT ON public.ottoq_decisions FOR EACH ROW WHEN (((new.l2_engine = ANY (ARRAY['nemotron'::text, 'forward_lex'::text, 'llm_advisor'::text])) OR ((new.resolved_action_context = 'orchestrator_agent'::text) AND (new.l2_engine = 'deterministic_fallback'::text) AND (COALESCE(new.propose_latency_ms, 0) > 0)))) EXECUTE FUNCTION public.ottoq_capture_decision_model_call();
-- @@ trigger public.ottoq_decisions.trg_ottoq_stamp_l2_engine
CREATE TRIGGER trg_ottoq_stamp_l2_engine BEFORE INSERT ON public.ottoq_decisions FOR EACH ROW EXECUTE FUNCTION public.ottoq_stamp_l2_engine();
-- @@ trigger public.ottoq_determinism_verdict_ledger.ottoq_dvl_append_only
CREATE TRIGGER ottoq_dvl_append_only BEFORE DELETE OR UPDATE ON public.ottoq_determinism_verdict_ledger FOR EACH ROW EXECUTE FUNCTION public.ottoq_determinism_verdict_ledger_append_only();
-- @@ trigger public.ottoq_determinism_verdict_ledger.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_determinism_verdict_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_dial_pair_ledger.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_dial_pair_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_dial_promotion_ledger.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_dial_promotion_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_emergency_invocations.trg_ottoq_emergency_invocations_no_delete
CREATE TRIGGER trg_ottoq_emergency_invocations_no_delete BEFORE DELETE ON public.ottoq_emergency_invocations FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_energy_commands.ottoq_capture_site_power_plan_trg
CREATE TRIGGER ottoq_capture_site_power_plan_trg AFTER INSERT ON public.ottoq_energy_commands FOR EACH ROW EXECUTE FUNCTION public.ottoq_capture_site_power_plan();
-- @@ trigger public.ottoq_events.ottoq_events_slim_new_state_bi
CREATE TRIGGER ottoq_events_slim_new_state_bi BEFORE INSERT ON public.ottoq_events FOR EACH ROW EXECUTE FUNCTION public.ottoq_events_slim_new_state();
-- @@ trigger public.ottoq_events.trg_ottoq_auto_incident_report
CREATE TRIGGER trg_ottoq_auto_incident_report AFTER INSERT ON public.ottoq_events FOR EACH ROW EXECUTE FUNCTION public.ottoq_auto_generate_incident_report();
-- @@ trigger_state public.ottoq_events.trg_ottoq_auto_incident_report
ALTER TABLE public.ottoq_events DISABLE TRIGGER trg_ottoq_auto_incident_report;
-- @@ trigger public.ottoq_events.trg_ottoq_events_no_update
CREATE TRIGGER trg_ottoq_events_no_update BEFORE DELETE OR UPDATE ON public.ottoq_events FOR EACH ROW EXECUTE FUNCTION public.ottoq_events_block_mutation();
-- @@ trigger public.ottoq_evidence_regimes.ottoq_evidence_regimes_append_only_trg
CREATE TRIGGER ottoq_evidence_regimes_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_evidence_regimes FOR EACH ROW EXECUTE FUNCTION public.ottoq_evidence_regimes_append_only();
-- @@ trigger public.ottoq_external_proposals.ottoq_capture_proposal_disposition_trg
CREATE TRIGGER ottoq_capture_proposal_disposition_trg AFTER UPDATE OF status ON public.ottoq_external_proposals FOR EACH ROW EXECUTE FUNCTION public.ottoq_capture_proposal_disposition();
-- @@ trigger public.ottoq_feature_values.trg_ottoq_feature_values_no_delete
CREATE TRIGGER trg_ottoq_feature_values_no_delete BEFORE DELETE ON public.ottoq_feature_values FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_feed_plan_promotions.ottoq_feed_plan_promotions_append_only
CREATE TRIGGER ottoq_feed_plan_promotions_append_only BEFORE DELETE OR UPDATE OR TRUNCATE ON public.ottoq_feed_plan_promotions FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_feed_plan_promotions_append_only();
-- @@ trigger public.ottoq_feed_plans.ottoq_feed_plans_person_promotes
CREATE TRIGGER ottoq_feed_plans_person_promotes BEFORE INSERT OR UPDATE ON public.ottoq_feed_plans FOR EACH ROW EXECUTE FUNCTION public.ottoq_feed_plans_person_promotes();
-- @@ trigger public.ottoq_fleet_buildout_active.ottoq_fleet_buildout_never_commits
CREATE CONSTRAINT TRIGGER ottoq_fleet_buildout_never_commits AFTER INSERT ON public.ottoq_fleet_buildout_active DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.ottoq_fleet_buildout_must_not_commit();
-- @@ trigger public.ottoq_incident_reports.trg_ottoq_incident_reports_no_delete
CREATE TRIGGER trg_ottoq_incident_reports_no_delete BEFORE DELETE ON public.ottoq_incident_reports FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_inference_log.trg_ottoq_inference_log_no_delete
CREATE TRIGGER trg_ottoq_inference_log_no_delete BEFORE DELETE ON public.ottoq_inference_log FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_intelligence_sources.ottoq_intelligence_labels_guard_trg
CREATE TRIGGER ottoq_intelligence_labels_guard_trg BEFORE INSERT OR UPDATE OF source, l2_engine_label, l2_engine_labels ON public.ottoq_intelligence_sources FOR EACH ROW EXECUTE FUNCTION public.ottoq_intelligence_labels_guard();
-- @@ trigger public.ottoq_itinerary_legs.trg_0043_leg_done_sdr
CREATE TRIGGER trg_0043_leg_done_sdr AFTER UPDATE OF status ON public.ottoq_itinerary_legs FOR EACH ROW WHEN (((new.status = 'done'::text) AND (old.status IS DISTINCT FROM 'done'::text))) EXECUTE FUNCTION public.ottoq_trg_leg_done_sdr();
-- @@ trigger public.ottoq_layout_backup_0011_stall_bookings.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_layout_backup_0011_stall_bookings FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_learned_estimates.ottoq_learned_estimates_append_only_trg
CREATE TRIGGER ottoq_learned_estimates_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_learned_estimates FOR EACH ROW EXECUTE FUNCTION public.ottoq_learned_estimates_append_only();
-- @@ trigger public.ottoq_model_artifacts.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_model_artifacts FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_model_call_ledger.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_model_call_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_model_call_ledger.ottoq_model_call_ledger_append_only_trg
CREATE TRIGGER ottoq_model_call_ledger_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_model_call_ledger FOR EACH ROW EXECUTE FUNCTION public.ottoq_model_call_ledger_append_only();
-- @@ trigger public.ottoq_oauth_auth_requests.ottoq_oauth_auth_requests_keep_rows_trg
CREATE TRIGGER ottoq_oauth_auth_requests_keep_rows_trg BEFORE DELETE ON public.ottoq_oauth_auth_requests FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
-- @@ trigger public.ottoq_oauth_auth_requests.ottoq_oauth_auth_requests_no_truncate_trg
CREATE TRIGGER ottoq_oauth_auth_requests_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_oauth_auth_requests FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- @@ trigger public.ottoq_oauth_clients.ottoq_oauth_clients_keep_rows_trg
CREATE TRIGGER ottoq_oauth_clients_keep_rows_trg BEFORE DELETE ON public.ottoq_oauth_clients FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
-- @@ trigger public.ottoq_oauth_clients.ottoq_oauth_clients_no_truncate_trg
CREATE TRIGGER ottoq_oauth_clients_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_oauth_clients FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- @@ trigger public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_keep_rows_trg
CREATE TRIGGER ottoq_oauth_device_codes_keep_rows_trg BEFORE DELETE ON public.ottoq_oauth_device_codes FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
-- @@ trigger public.ottoq_oauth_device_codes.ottoq_oauth_device_codes_no_truncate_trg
CREATE TRIGGER ottoq_oauth_device_codes_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_oauth_device_codes FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- @@ trigger public.ottoq_oauth_grants.ottoq_oauth_grants_keep_rows_trg
CREATE TRIGGER ottoq_oauth_grants_keep_rows_trg BEFORE DELETE ON public.ottoq_oauth_grants FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
-- @@ trigger public.ottoq_oauth_grants.ottoq_oauth_grants_no_truncate_trg
CREATE TRIGGER ottoq_oauth_grants_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_oauth_grants FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- @@ trigger public.ottoq_oauth_tokens.ottoq_oauth_tokens_keep_rows_trg
CREATE TRIGGER ottoq_oauth_tokens_keep_rows_trg BEFORE DELETE ON public.ottoq_oauth_tokens FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
-- @@ trigger public.ottoq_oauth_tokens.ottoq_oauth_tokens_no_truncate_trg
CREATE TRIGGER ottoq_oauth_tokens_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_oauth_tokens FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- @@ trigger public.ottoq_ops_approvals.trg_0753_reopen_declined_repair
CREATE TRIGGER trg_0753_reopen_declined_repair AFTER UPDATE OF status ON public.ottoq_ops_approvals FOR EACH ROW WHEN (((new.approval_type = 'tech_greenlight'::text) AND (new.status = 'declined'::text) AND (old.status = 'pending'::text))) EXECUTE FUNCTION public.ottoq_reopen_declined_repair();
-- @@ trigger public.ottoq_owner_accounts.ottoq_owner_accounts_keep_rows_trg
CREATE TRIGGER ottoq_owner_accounts_keep_rows_trg BEFORE DELETE ON public.ottoq_owner_accounts FOR EACH ROW EXECUTE FUNCTION public.ottoq_oauth_keep_rows();
-- @@ trigger public.ottoq_owner_accounts.ottoq_owner_accounts_no_truncate_trg
CREATE TRIGGER ottoq_owner_accounts_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_owner_accounts FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- @@ trigger public.ottoq_owner_commands.ottoq_owner_commands_guard_trg
CREATE TRIGGER ottoq_owner_commands_guard_trg BEFORE DELETE OR UPDATE ON public.ottoq_owner_commands FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_commands_guard();
-- @@ trigger public.ottoq_owner_commands.ottoq_owner_commands_no_truncate_trg
CREATE TRIGGER ottoq_owner_commands_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_owner_commands FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
-- @@ trigger public.ottoq_proposal_disposition_ledger.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_proposal_disposition_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_proposal_disposition_ledger.ottoq_proposal_disposition_ledger_append_only_trg
CREATE TRIGGER ottoq_proposal_disposition_ledger_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_proposal_disposition_ledger FOR EACH ROW EXECUTE FUNCTION public.ottoq_proposal_disposition_ledger_append_only();
-- @@ trigger public.ottoq_proposer_fire_log.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_proposer_fire_log FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_ready_promise_updates.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_ready_promise_updates FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_ready_promise_updates.ottoq_ready_promise_updates_append_only_trg
CREATE TRIGGER ottoq_ready_promise_updates_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_ready_promise_updates FOR EACH ROW EXECUTE FUNCTION public.ottoq_ready_promise_updates_append_only();
-- @@ trigger public.ottoq_ready_promises.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_ready_promises FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_ready_promises.ottoq_ready_promises_append_only_trg
CREATE TRIGGER ottoq_ready_promises_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_ready_promises FOR EACH ROW EXECUTE FUNCTION public.ottoq_ready_promises_append_only();
-- @@ trigger public.ottoq_recall_decisions.trg_ottoq_recall_decisions_append_only
CREATE TRIGGER trg_ottoq_recall_decisions_append_only BEFORE DELETE OR UPDATE ON public.ottoq_recall_decisions FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_recall_refusals.ottoq_recall_refusals_no_update
CREATE TRIGGER ottoq_recall_refusals_no_update BEFORE DELETE OR UPDATE ON public.ottoq_recall_refusals FOR EACH ROW EXECUTE FUNCTION public.ottoq_recall_refusals_append_only();
-- @@ trigger public.ottoq_recommendations.trg_ottoq_recommendations_no_delete
CREATE TRIGGER trg_ottoq_recommendations_no_delete BEFORE DELETE ON public.ottoq_recommendations FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_rider_cleaning_flags.trg_ottoq_rider_flag_placement_guard
CREATE TRIGGER trg_ottoq_rider_flag_placement_guard BEFORE INSERT OR UPDATE ON public.ottoq_rider_cleaning_flags FOR EACH ROW EXECUTE FUNCTION public.ottoq_rider_flag_placement_guard();
-- @@ trigger public.ottoq_rule_evaluations.ottoq_capture_space_integrity_incident_trg
CREATE TRIGGER ottoq_capture_space_integrity_incident_trg AFTER INSERT ON public.ottoq_rule_evaluations FOR EACH ROW WHEN (((new.passed = false) AND (new.rule_code ~~ 'HW.006%'::text) AND (new.result_payload ? 'expected_vehicle_id'::text))) EXECUTE FUNCTION public.ottoq_capture_space_integrity_incident();
-- @@ trigger public.ottoq_rule_evaluations.trg_ottoq_rule_evaluations_no_delete
CREATE TRIGGER trg_ottoq_rule_evaluations_no_delete BEFORE DELETE ON public.ottoq_rule_evaluations FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_rule_overrides.trg_ottoq_rule_overrides_no_delete
CREATE TRIGGER trg_ottoq_rule_overrides_no_delete BEFORE DELETE ON public.ottoq_rule_overrides FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_run_archives.trg_ottoq_capture_run_dials
CREATE TRIGGER trg_ottoq_capture_run_dials AFTER INSERT ON public.ottoq_run_archives FOR EACH ROW EXECUTE FUNCTION public.ottoq_capture_run_dials();
-- @@ trigger public.ottoq_run_dial_ledger.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_run_dial_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_run_scope_registry.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_run_scope_registry FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_run_scope_registry.ottoq_run_scope_registry_guards_evidence_trg
CREATE TRIGGER ottoq_run_scope_registry_guards_evidence_trg AFTER INSERT OR UPDATE OF class, table_schema, table_name ON public.ottoq_run_scope_registry FOR EACH ROW WHEN ((new.class = 'evidence'::text)) EXECUTE FUNCTION public.ottoq_run_scope_registry_guards_evidence();
-- @@ trigger public.ottoq_sim_runs.ottoq_sim_runs_close_needs
CREATE TRIGGER ottoq_sim_runs_close_needs AFTER UPDATE OF status ON public.ottoq_sim_runs FOR EACH ROW WHEN (((old.status = ANY (ARRAY['initializing'::text, 'running'::text, 'paused'::text])) AND (new.status = ANY (ARRAY['completed'::text, 'failed'::text, 'aborted'::text])))) EXECUTE FUNCTION public.ottoq_tg_close_run_needs_on_terminal();
-- @@ trigger public.ottoq_sim_runs.ottoq_sim_runs_end_passcode_sessions
CREATE TRIGGER ottoq_sim_runs_end_passcode_sessions AFTER UPDATE OF status ON public.ottoq_sim_runs FOR EACH ROW WHEN (((old.status = ANY (ARRAY['initializing'::text, 'running'::text, 'paused'::text])) AND (new.status = ANY (ARRAY['completed'::text, 'failed'::text, 'aborted'::text])) AND (new.run_by = 'operator_demo'::text))) EXECUTE FUNCTION public.ottoq_tg_end_passcode_sessions_on_terminal();
-- @@ trigger public.ottoq_sim_runs.ottoq_sim_runs_lift_owner_settings
CREATE TRIGGER ottoq_sim_runs_lift_owner_settings AFTER UPDATE OF status ON public.ottoq_sim_runs FOR EACH ROW WHEN (((old.status = ANY (ARRAY['initializing'::text, 'running'::text, 'paused'::text])) AND (new.status = ANY (ARRAY['completed'::text, 'failed'::text, 'aborted'::text])))) EXECUTE FUNCTION public.ottoq_tg_lift_owner_settings_on_terminal();
-- @@ trigger public.ottoq_sim_runs.trg_ottoq_reanchor_rider_flags
CREATE TRIGGER trg_ottoq_reanchor_rider_flags AFTER UPDATE OF sim_clock_start ON public.ottoq_sim_runs FOR EACH ROW WHEN ((new.sim_clock_start IS DISTINCT FROM old.sim_clock_start)) EXECUTE FUNCTION public.ottoq_reanchor_rider_flags_on_clock_rebase();
-- @@ trigger public.ottoq_site_base_history.ottoq_site_base_history_no_truncate
CREATE TRIGGER ottoq_site_base_history_no_truncate BEFORE TRUNCATE ON public.ottoq_site_base_history FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_site_base_history_append_only();
-- @@ trigger public.ottoq_site_base_history.ottoq_site_base_history_no_update
CREATE TRIGGER ottoq_site_base_history_no_update BEFORE DELETE OR UPDATE ON public.ottoq_site_base_history FOR EACH ROW EXECUTE FUNCTION public.ottoq_site_base_history_append_only();
-- @@ trigger public.ottoq_site_buildout_active.ottoq_site_buildout_never_commits
CREATE CONSTRAINT TRIGGER ottoq_site_buildout_never_commits AFTER INSERT ON public.ottoq_site_buildout_active DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.ottoq_site_buildout_must_not_commit();
-- @@ trigger public.ottoq_site_power_excursion_ledger.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_site_power_excursion_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_site_power_excursion_ledger.ottoq_site_power_excursion_ledger_append_only_trg
CREATE TRIGGER ottoq_site_power_excursion_ledger_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_site_power_excursion_ledger FOR EACH ROW EXECUTE FUNCTION public.ottoq_site_power_excursion_ledger_append_only();
-- @@ trigger public.ottoq_site_power_plan_ledger.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_site_power_plan_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_site_power_plan_ledger.ottoq_site_power_plan_ledger_append_only_trg
CREATE TRIGGER ottoq_site_power_plan_ledger_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_site_power_plan_ledger FOR EACH ROW EXECUTE FUNCTION public.ottoq_site_power_plan_ledger_append_only();
-- @@ trigger public.ottoq_sla_violations.trg_ottoq_sla_violations_no_delete
CREATE TRIGGER trg_ottoq_sla_violations_no_delete BEFORE DELETE ON public.ottoq_sla_violations FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_space_integrity_ledger.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_space_integrity_ledger FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_space_integrity_ledger.ottoq_space_integrity_ledger_append_only_trg
CREATE TRIGGER ottoq_space_integrity_ledger_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_space_integrity_ledger FOR EACH ROW EXECUTE FUNCTION public.ottoq_space_integrity_ledger_append_only();
-- @@ trigger public.ottoq_stall_bookings.ottoq_stall_bookings_stamp_sim
CREATE TRIGGER ottoq_stall_bookings_stamp_sim BEFORE INSERT ON public.ottoq_stall_bookings FOR EACH ROW EXECUTE FUNCTION public.ottoq_stamp_booked_at_sim();
-- @@ trigger public.ottoq_stall_bookings.ottoq_witness_booking_transition_trg
CREATE TRIGGER ottoq_witness_booking_transition_trg AFTER UPDATE ON public.ottoq_stall_bookings FOR EACH ROW WHEN (((old.state IS DISTINCT FROM new.state) OR (old.source IS DISTINCT FROM new.source))) EXECUTE FUNCTION ottoq.ottoq_witness_booking_transition();
-- @@ trigger public.ottoq_throughput_scores.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_throughput_scores FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_throughput_scores.trg_ottoq_throughput_scores_append_only
CREATE TRIGGER trg_ottoq_throughput_scores_append_only BEFORE DELETE OR UPDATE ON public.ottoq_throughput_scores FOR EACH ROW EXECUTE FUNCTION public.ottoq_throughput_scores_append_only();
-- @@ trigger public.ottoq_throughput_sweep_arms.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_throughput_sweep_arms FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_throughput_sweep_arms.trg_ottoq_throughput_sweep_arms_append_only
CREATE TRIGGER trg_ottoq_throughput_sweep_arms_append_only BEFORE DELETE OR UPDATE ON public.ottoq_throughput_sweep_arms FOR EACH ROW EXECUTE FUNCTION public.ottoq_throughput_sweep_arms_append_only();
-- @@ trigger public.ottoq_throughput_sweep_cells.trg_ottoq_throughput_sweep_cells_control
CREATE TRIGGER trg_ottoq_throughput_sweep_cells_control BEFORE INSERT OR UPDATE ON public.ottoq_throughput_sweep_cells FOR EACH ROW EXECUTE FUNCTION public.ottoq_throughput_sweep_cells_control();
-- @@ trigger public.ottoq_training_runs.trg_ottoq_training_runs_no_delete
CREATE TRIGGER trg_ottoq_training_runs_no_delete BEFORE DELETE ON public.ottoq_training_runs FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();
-- @@ trigger public.ottoq_vehicle_commands.ottoq_vehicle_commands_provenance
CREATE TRIGGER ottoq_vehicle_commands_provenance BEFORE INSERT OR UPDATE OF depot_id ON public.ottoq_vehicle_commands FOR EACH ROW EXECUTE FUNCTION public.ottoq_vehicle_commands_stamp_provenance();
-- @@ trigger public.ottoq_vehicle_dispatches.trg_dispatch_bump_wash_cycle
CREATE TRIGGER trg_dispatch_bump_wash_cycle AFTER INSERT ON public.ottoq_vehicle_dispatches FOR EACH ROW WHEN ((new.status = 'active'::text)) EXECUTE FUNCTION public.ottoq_dispatch_bump_wash_cycle();
-- @@ trigger public.ottoq_vehicle_dispatches.trg_dispatch_departure_clear
CREATE TRIGGER trg_dispatch_departure_clear BEFORE INSERT ON public.ottoq_vehicle_dispatches FOR EACH ROW WHEN ((new.status = 'active'::text)) EXECUTE FUNCTION public.ottoq_refuse_unfinished_departure();
-- @@ trigger public.ottoq_vehicle_dispatches.trg_dispatch_eta_provenance_ins
CREATE TRIGGER trg_dispatch_eta_provenance_ins BEFORE INSERT ON public.ottoq_vehicle_dispatches FOR EACH ROW WHEN ((new.return_eta_minutes IS NOT NULL)) EXECUTE FUNCTION public.ottoq_assert_eta_provenance();
-- @@ trigger public.ottoq_vehicle_dispatches.trg_dispatch_eta_provenance_upd
CREATE TRIGGER trg_dispatch_eta_provenance_upd BEFORE UPDATE ON public.ottoq_vehicle_dispatches FOR EACH ROW WHEN (((new.return_eta_minutes IS NOT NULL) AND (new.return_eta_minutes IS DISTINCT FROM old.return_eta_minutes))) EXECUTE FUNCTION public.ottoq_assert_eta_provenance();
-- @@ trigger public.ottoq_vehicle_scout_findings.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.ottoq_vehicle_scout_findings FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.ottoq_vehicle_scout_findings.ottoq_vehicle_scout_findings_append_only_trg
CREATE TRIGGER ottoq_vehicle_scout_findings_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_vehicle_scout_findings FOR EACH ROW EXECUTE FUNCTION public.ottoq_vehicle_scout_findings_append_only();
-- @@ trigger public.ottoq_visit_cost_attribution.trg_0043_attribution_attach
CREATE TRIGGER trg_0043_attribution_attach AFTER INSERT ON public.ottoq_visit_cost_attribution FOR EACH ROW EXECUTE FUNCTION public.ottoq_trg_attribution_attach();
-- @@ trigger public.ottoq_visit_needs.ottoq_visit_needs_owner_orders_trg
CREATE TRIGGER ottoq_visit_needs_owner_orders_trg BEFORE INSERT ON public.ottoq_visit_needs FOR EACH ROW EXECUTE FUNCTION public.ottoq_tg_owner_orders_on_new_visit();
-- @@ trigger public.ottoq_visit_needs.trg_0753_ask_repair_green_light
CREATE TRIGGER trg_0753_ask_repair_green_light AFTER UPDATE OF atoms ON public.ottoq_visit_needs FOR EACH ROW WHEN (((new.atoms @> '[{"status": "done", "requires_tech_greenlight": true}]'::jsonb) AND (new.atoms IS DISTINCT FROM old.atoms))) EXECUTE FUNCTION public.ottoq_ask_repair_green_light();
-- @@ trigger public.ottoq_visit_needs.trg_ottoq_rider_flag_mark_served
CREATE TRIGGER trg_ottoq_rider_flag_mark_served AFTER UPDATE ON public.ottoq_visit_needs FOR EACH ROW WHEN ((((new.meta ->> 'rider_flagged'::text) = 'true'::text) AND (old.atoms IS DISTINCT FROM new.atoms))) EXECUTE FUNCTION public.ottoq_rider_flag_mark_served();
-- @@ trigger public.ottow_api_keys.ottow_api_keys_guard
CREATE TRIGGER ottow_api_keys_guard BEFORE INSERT OR UPDATE ON public.ottow_api_keys FOR EACH ROW EXECUTE FUNCTION public.ottow_api_keys_guard();
-- @@ trigger public.ottow_dispatch_rules.set_ottow_dispatch_rules_updated_at
CREATE TRIGGER set_ottow_dispatch_rules_updated_at BEFORE UPDATE ON public.ottow_dispatch_rules FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- @@ trigger public.ottow_drivers.set_updated_at_ottow_drivers
CREATE TRIGGER set_updated_at_ottow_drivers BEFORE UPDATE ON public.ottow_drivers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- @@ trigger public.ottow_missions.set_updated_at_ottow_missions
CREATE TRIGGER set_updated_at_ottow_missions BEFORE UPDATE ON public.ottow_missions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- @@ trigger public.ottow_notifications.set_ottow_notifications_updated_at
CREATE TRIGGER set_ottow_notifications_updated_at BEFORE UPDATE ON public.ottow_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- @@ trigger public.p7_band_probe_2026_08_03.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.p7_band_probe_2026_08_03 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.pre0002_approvals_evidence.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.pre0002_approvals_evidence FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.preimport_stall_bookings_20260806.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.preimport_stall_bookings_20260806 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.prof0012_tick.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.prof0012_tick FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.progression_decisions.trg_ottoq_pd_audit_note
CREATE TRIGGER trg_ottoq_pd_audit_note BEFORE INSERT OR UPDATE ON public.progression_decisions FOR EACH ROW EXECUTE FUNCTION public.ottoq_progression_decisions_enforce_audit_note();
-- @@ trigger public.proof0008_wear_prestate.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.proof0008_wear_prestate FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.proof0012_binding_blocker.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.proof0012_binding_blocker FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.proof0012_prearrival_census.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.proof0012_prearrival_census FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.retail_members.trg_retail_members_updated
CREATE TRIGGER trg_retail_members_updated BEFORE UPDATE ON public.retail_members FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.schedule_tasks.trg_0043_task_completed_sdr
CREATE TRIGGER trg_0043_task_completed_sdr AFTER UPDATE OF status ON public.schedule_tasks FOR EACH ROW WHEN (((new.status = 'completed'::public.task_status) AND (old.status IS DISTINCT FROM 'completed'::public.task_status))) EXECUTE FUNCTION public.ottoq_trg_task_completed_sdr();
-- @@ trigger public.schedule_tasks.trg_ottoq_schedule_tasks_state_change
CREATE TRIGGER trg_ottoq_schedule_tasks_state_change AFTER INSERT OR UPDATE ON public.schedule_tasks FOR EACH ROW EXECUTE FUNCTION public.ottoq_schedule_tasks_state_change();
-- @@ trigger public.schedule_tasks.trg_schedule_tasks_updated
CREATE TRIGGER trg_schedule_tasks_updated BEFORE UPDATE ON public.schedule_tasks FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.smoke890_bookings_2026_08_03.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.smoke890_bookings_2026_08_03 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
-- @@ trigger public.staff_users.trg_staff_users_updated
CREATE TRIGGER trg_staff_users_updated BEFORE UPDATE ON public.staff_users FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.stalls.trg_ottoq_stall_seat_is_exclusive
CREATE TRIGGER trg_ottoq_stall_seat_is_exclusive BEFORE INSERT OR UPDATE OF current_vehicle_id ON public.stalls FOR EACH ROW EXECUTE FUNCTION public.ottoq_stall_seat_is_exclusive();
-- @@ trigger public.stalls.trg_ottoq_stalls_state_change
CREATE TRIGGER trg_ottoq_stalls_state_change AFTER INSERT OR UPDATE ON public.stalls FOR EACH ROW EXECUTE FUNCTION public.ottoq_stalls_state_change();
-- @@ trigger public.stalls.trg_reassignment_guard
CREATE TRIGGER trg_reassignment_guard BEFORE UPDATE ON public.stalls FOR EACH ROW EXECUTE FUNCTION public.ottoq_trg_reassignment_guard();
-- @@ trigger public.stalls.trg_stalls_updated
CREATE TRIGGER trg_stalls_updated BEFORE UPDATE ON public.stalls FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.tariff_schedules.trg_tariffs_updated
CREATE TRIGGER trg_tariffs_updated BEFORE UPDATE ON public.tariff_schedules FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.vehicle_schedules.trg_update_wave_count
CREATE TRIGGER trg_update_wave_count AFTER INSERT OR DELETE OR UPDATE ON public.vehicle_schedules FOR EACH ROW EXECUTE FUNCTION public.update_wave_count();
-- @@ trigger public.vehicle_schedules.trg_vehicle_schedules_updated
CREATE TRIGGER trg_vehicle_schedules_updated BEFORE UPDATE ON public.vehicle_schedules FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.vehicles.ottoq_arm_interlock
CREATE TRIGGER ottoq_arm_interlock BEFORE UPDATE OF current_stall_id ON public.vehicles FOR EACH ROW WHEN ((old.current_stall_id IS DISTINCT FROM new.current_stall_id)) EXECUTE FUNCTION public.ottoq_arm_interlock_guard();
-- @@ trigger public.vehicles.ottoq_trg_log_deploy
CREATE TRIGGER ottoq_trg_log_deploy AFTER UPDATE OF current_state ON public.vehicles FOR EACH ROW WHEN (((new.current_state = ANY (ARRAY['en_route_to_deployment'::public.vehicle_state, 'deployed'::public.vehicle_state])) AND (old.current_state IS DISTINCT FROM new.current_state) AND (old.current_state <> ALL (ARRAY['en_route_to_deployment'::public.vehicle_state, 'deployed'::public.vehicle_state])))) EXECUTE FUNCTION public.ottoq_log_deploy_event();
-- @@ trigger public.vehicles.trg_ottoq_vehicles_state_change
CREATE TRIGGER trg_ottoq_vehicles_state_change AFTER INSERT OR UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.ottoq_vehicles_state_change();
-- @@ trigger public.vehicles.trg_sync_stall_occupancy
CREATE TRIGGER trg_sync_stall_occupancy AFTER UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.sync_stall_occupancy();
-- @@ trigger public.vehicles.trg_vehicle_state_change
CREATE TRIGGER trg_vehicle_state_change BEFORE UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.log_vehicle_state_change();
-- @@ trigger public.vehicles.trg_vehicle_state_change_wait_bank
CREATE TRIGGER trg_vehicle_state_change_wait_bank BEFORE UPDATE OF current_state ON public.vehicles FOR EACH ROW WHEN ((old.current_state IS DISTINCT FROM new.current_state)) EXECUTE FUNCTION public.ottoq_vehicle_charge_wait_bank();
-- @@ trigger public.vehicles.trg_vehicles_updated
CREATE TRIGGER trg_vehicles_updated BEFORE UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
-- @@ trigger public.workload_determinism_proof_2026_08_02.ottoq_evidence_no_truncate_trg
CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON public.workload_determinism_proof_2026_08_02 FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate();
