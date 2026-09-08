-- ============================================================================
-- check-drift.sql  —  THE SMOKE ALARM
-- ============================================================================
-- Question this answers, in one sentence:
--   "Has anything been applied to the live OTTO-Q brain that is NOT represented
--    by a committed migration file in this repo?"
--
-- READ-ONLY. This script never writes, never creates, never drops. It is safe
-- to run at any time, including during a live demo.
-- It does NOT touch ottoq_events (9 GB of an 11 GB database).
--
-- ---------------------------------------------------------------------------
-- HOW TO RUN IT
-- ---------------------------------------------------------------------------
--   1. Open the Supabase SQL editor for project gxdrcyphqjzjsuhxuqtg
--      ("otto-q-core"), paste this whole file, and run it.
--   OR run it through the Supabase MCP `execute_sql` tool.
--   2. Read the RESULT column top to bottom. Row 1 is the verdict.
--
-- ---------------------------------------------------------------------------
-- WHY THE MANIFEST IS EMBEDDED IN THIS FILE (the design decision)
-- ---------------------------------------------------------------------------
-- SQL cannot read the filesystem, so it cannot see db/migrations/ by itself.
-- Two options were considered:
--
--   (a) Keep a separate committed manifest (APPLIED.tsv) and paste it in.
--       Rejected: two places to update = they drift from each other, and the
--       drift checker drifting is the worst possible failure.
--
--   (b) THE FILES ARE THE SOURCE OF TRUTH. Every migration file declares its
--       own applied version in its header:
--           -- migration-version: 20260804153000
--           -- migration-name:    p3_short_name
--       `scripts/gen-drift-sql.sh` scrapes those headers straight out of
--       db/migrations/*.sql and rewrites the GENERATED MANIFEST block below,
--       in place. You then commit this file along with the migration.
--
-- (b) was chosen. One source of truth (the migration files), one command to
-- refresh, and the refreshed file is committed — so the manifest itself is
-- reviewable in a diff.
--
--   To refresh:  bash scripts/gen-drift-sql.sh
--
-- Do not hand-edit the GENERATED MANIFEST block. If you do, the generator will
-- overwrite you on the next run, and for one commit the smoke alarm will have
-- been lying.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS CHECK CANNOT SEE — read this, it matters
-- ---------------------------------------------------------------------------
-- Sections A/B/C compare the repo against the LEDGER
-- (supabase_migrations.schema_migrations). The ledger is only written when a
-- change is applied AS a migration (Supabase CLI, the MCP apply_migration tool,
-- or the dashboard's migration path).
--
-- A CREATE OR REPLACE typed straight into the SQL editor changes the brain and
-- writes NO ledger row at all. Sections A/B/C are blind to that by construction.
-- Section D is the backstop for it: it compares the live count of user-defined
-- routines against the counts this repo's baseline recorded. If A and B are
-- clean but D disagrees, somebody edited the brain outside the migration path.
--
-- Section D is a coarse detector — it counts routines, it does not compare their
-- bodies. A same-count body edit still slips past it. The real fix for that is
-- re-exporting db/baseline/ periodically and diffing. Stated plainly so nobody
-- mistakes a green Section D for a guarantee.
--
-- Edge functions are not in Postgres and cannot be checked from SQL at all.
-- See scripts/APPLYING.md for the edge-function procedure.
-- ============================================================================

WITH
-- ---------------------------------------------------------------------------
-- The baseline cut. Everything applied at or before this ledger version is
-- represented by db/baseline/ (the 2026-08-04 snapshot), NOT by a migration
-- file, and is therefore not drift. This is the 621st and newest row that
-- existed when the baseline was taken.
-- Only change this line when db/baseline/ is genuinely re-exported.
-- ---------------------------------------------------------------------------
cut(baseline_through, baseline_rows) AS (
  VALUES ('20260803210034'::text, 621)
),

-- ---------------------------------------------------------------------------
-- The repo's migration files. Generated — see the header.
-- ---------------------------------------------------------------------------
repo_manifest(version, name, file) AS (
  VALUES
-- >>> BEGIN GENERATED MANIFEST — do not edit by hand; run scripts/gen-drift-sql.sh
    ('20260804140958'::text, 'approval_gate_decider'::text, '0002_approval_gate_decider.sql'::text),
    ('20260804183836'::text, 'bay_work_recovery'::text, '0003_bay_work_recovery.sql'::text),
    ('20260804232058'::text, 'close_ledger_loop'::text, '0004_close_ledger_loop.sql'::text),
    ('20260805020029'::text, 'inspection_and_condition_resets'::text, '0005_inspection_and_condition_resets.sql'::text),
    ('20260805142711'::text, 'slim_writes_and_arm_retention'::text, '0006_slim_writes_and_arm_retention.sql'::text),
    ('20260805032907'::text, 'add_site_energy_snapshots_created_at_idx'::text, '0007_add_site_energy_snapshots_created_at_idx.sql'::text),
    ('20260805230731'::text, 'soil_gate_and_retention_walk'::text, '0008_soil_gate_and_retention_walk.sql'::text),
    ('20260806030248'::text, 'honest_completion_and_eta'::text, '0009_honest_completion_and_eta.sql'::text),
    ('20260806223619'::text, 'unify_depot_layout'::text, '0010_unify_depot_layout.sql'::text),
    ('20260806231121'::text, 'forward_bay_reservation_at_return_signal'::text, '0011_forward_bay_reservation_at_return_signal.sql'::text),
    ('20260807001645'::text, 'tick_cost_and_metronome_ceiling'::text, '0012_tick_cost_and_metronome_ceiling.sql'::text),
    ('20260807002716'::text, 'metronome_guard_reads_the_real_timeout'::text, '0013_metronome_guard_reads_the_real_timeout.sql'::text),
    ('20260807005437'::text, 'bay_binding_witness'::text, '0014_bay_binding_witness.sql'::text),
    ('20260807013120'::text, 'early_activation_and_untagged_event_flood'::text, '0015_early_activation_and_untagged_event_flood.sql'::text),
    ('20260807015854'::text, 'bay_seat_writes_the_twin_service_timer'::text, '0016_bay_seat_writes_the_twin_service_timer.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'stop_is_two_phase_so_a_run_can_always_be_stopped'::text, '0017_stop_is_two_phase_so_a_run_can_always_be_stopped.sql'::text),
    ('20260808041455'::text, 'rider_flagged_cleaning_recall'::text, '0018_rider_flagged_cleaning_recall.sql'::text),
    ('20260808153457'::text, 'rider_flag_holds_the_vehicle'::text, '0019_rider_flag_holds_the_vehicle.sql'::text),
    ('20260808165323'::text, 'rider_flag_consume_and_place_is_atomic'::text, '0020_rider_flag_consume_and_place_is_atomic.sql'::text),
    ('20260808170813'::text, 'one_vehicle_one_stall'::text, '0021_one_vehicle_one_stall.sql'::text),
    ('20260808182226'::text, 'a_run_owns_its_rows'::text, '0022_a_run_owns_its_rows.sql'::text),
    ('20260808193142'::text, 'a_finished_run_is_read_only'::text, '0023_a_finished_run_is_read_only.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'run_governor_auto_stop'::text, '0025_run_governor_auto_stop.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'fix_staging_sort'::text, '0026_fix_staging_sort.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'shift_east_column'::text, '0027_shift_east_column.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'wash_monte_carlo'::text, '0028_wash_monte_carlo.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'reassignment_guard'::text, '0029_reassignment_guard.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'geometry_guard_db'::text, '0030_geometry_guard_db.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'geometry_guard_minimal'::text, '0031_geometry_guard_minimal.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'cuopt_batch_enactment'::text, '0032_cuopt_batch_enactment.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'reservation_gc'::text, '0033_reservation_gc.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'revert_0005_condition_resets_part2'::text, '0034_revert_0005_condition_resets_part2.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'drop_decorative_column'::text, '0035_drop_decorative_column.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'refusal_path'::text, '0036_refusal_path.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'purge_orphans'::text, '0037_purge_orphans.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'drop_ottoq_recommendations'::text, '0038_drop_ottoq_recommendations.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'ottoq_boundary'::text, '0039_ottoq_boundary.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'restore_tick_pipeline'::text, '0040_restore_tick_pipeline.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'fix_metronome_ceiling'::text, '0041_fix_metronome_ceiling.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'cleanup_orphan_data'::text, '0042_cleanup_orphan_data.sql'::text),
    ('20260819161838'::text, 'schema_v2_service_objects'::text, '0043_schema_v2_service_objects.sql'::text),
    ('20260819161926'::text, 'canonical_kpis'::text, '0044_canonical_kpis.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'twin_determinism_and_playback'::text, '0045_twin_determinism_and_playback.sql'::text),
    ('20260819185342'::text, 'twin_determinism_and_playback'::text, '0045_twin_determinism_and_playback.sql'::text),
    ('20260819185611'::text, 'twin_determinism_and_playback'::text, '0045_twin_determinism_and_playback.sql'::text),
    ('20260819185759'::text, 'twin_determinism_and_playback'::text, '0045_twin_determinism_and_playback.sql'::text),
    ('20260819190050'::text, 'twin_determinism_and_playback'::text, '0045_twin_determinism_and_playback.sql'::text),
    ('20260819190142'::text, 'twin_determinism_and_playback'::text, '0045_twin_determinism_and_playback.sql'::text),
    ('20260819190226'::text, 'site_alpha_pack_classes'::text, '0046_site_alpha_pack_classes.sql'::text),
    ('20260819192606'::text, 'twin_determinism_charge_session_salts'::text, '0047_twin_determinism_charge_session_salts.sql'::text),
    ('20260819210107'::text, 'twin_service_flow_admit_order_and_deal_salts'::text, '0048_twin_service_flow_admit_order_and_deal_salts.sql'::text),
    ('20260819211753'::text, 'twin_arm_refuse_move_clock_domain'::text, '0049_twin_arm_refuse_move_clock_domain.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'twin_deterministic_cursor_order'::text, '0050_twin_deterministic_cursor_order.sql'::text),
    ('20260819221057'::text, 'twin_deterministic_cursor_order'::text, '0050_twin_deterministic_cursor_order.sql'::text),
    ('20260819221205'::text, 'twin_deterministic_cursor_order'::text, '0050_twin_deterministic_cursor_order.sql'::text),
    ('20260819221507'::text, 'twin_deterministic_cursor_order'::text, '0050_twin_deterministic_cursor_order.sql'::text),
    ('20260819221603'::text, 'twin_deterministic_cursor_order'::text, '0050_twin_deterministic_cursor_order.sql'::text),
    ('20260819221809'::text, 'twin_deterministic_cursor_order'::text, '0050_twin_deterministic_cursor_order.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'twin_assigner_salt_and_tiebreak'::text, '0051_twin_assigner_salt_and_tiebreak.sql'::text),
    ('20260819231755'::text, 'twin_assigner_salt_and_tiebreak'::text, '0051_twin_assigner_salt_and_tiebreak.sql'::text),
    ('20260819231841'::text, 'twin_assigner_salt_and_tiebreak'::text, '0051_twin_assigner_salt_and_tiebreak.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'twin_holdout_and_comms_run_relative_salts'::text, '0052_twin_holdout_and_comms_run_relative_salts.sql'::text),
    ('20260819233610'::text, 'twin_holdout_and_comms_run_relative_salts'::text, '0052_twin_holdout_and_comms_run_relative_salts.sql'::text),
    ('20260819233630'::text, 'twin_holdout_and_comms_run_relative_salts'::text, '0052_twin_holdout_and_comms_run_relative_salts.sql'::text),
    ('20260820014345'::text, 'benchmark_reset_config_residue'::text, '0053_benchmark_reset_config_residue.sql'::text),
    ('20260820031245'::text, 'run_stable_cursor_order_full_sweep'::text, '0054_run_stable_cursor_order_full_sweep.sql'::text),
    ('20260820040308'::text, 'manifest_run_relative_draw_salt'::text, '0055_manifest_run_relative_draw_salt.sql'::text),
    ('20260820042552'::text, 'cuopt_propose_enabled_cert_quiesce'::text, '0056_cuopt_propose_enabled_cert_quiesce.sql'::text),
    ('20260820121029'::text, 'vehicle_state_trigger_preserve_caller_clock'::text, '0057_vehicle_state_trigger_preserve_caller_clock.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'variability_card_run_stable_draw_scope'::text, '0058_variability_card_run_stable_draw_scope.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'refusal_reactor_run_stable_order'::text, '0059_refusal_reactor_run_stable_order.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'confirm_and_selection_run_stable_order'::text, '0060_confirm_and_selection_run_stable_order.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'state_stamp_default_is_sim_domain'::text, '0061_state_stamp_default_is_sim_domain.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'confirm_supersede_total_order'::text, '0062_confirm_supersede_total_order.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'booking_pick_total_order'::text, '0063_booking_pick_total_order.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'hold_outlives_its_command'::text, '0064_hold_outlives_its_command.sql'::text),
    ('20260822004802'::text, 'cert_arm_pinned_sim_start'::text, '0065_cert_arm_pinned_sim_start.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'one_begin_charge_per_enactment'::text, '0066_one_begin_charge_per_enactment.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'greedy_stall_pick_total_order_and_sim_domain'::text, '0067_greedy_stall_pick_total_order_and_sim_domain.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'proposer_never_reuses_another_vehicles_hold'::text, '0068_proposer_never_reuses_another_vehicles_hold.sql'::text),
    ('20260822200504'::text, 'cert_arm_finish_releases_tethers'::text, '0069_cert_arm_finish_releases_tethers.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'cert_arm_start_pins_the_world'::text, '0070_cert_arm_start_pins_the_world.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'cert_arm_step_raises_on_short_advance'::text, '0071_cert_arm_step_raises_on_short_advance.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'cert_arm_step_null_safe_run_guard'::text, '0072_cert_arm_step_null_safe_run_guard.sql'::text),
    ('20260829160154'::text, 'provenance_says_what_it_is'::text, '0073_provenance_says_what_it_is.sql'::text),
    ('20260829160215'::text, 'the_archive_carries_its_key'::text, '0074_the_archive_carries_its_key.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'deploy_decision_idempotency'::text, '0075_deploy_decision_idempotency.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'command_reason_codes'::text, '0076_command_reason_codes.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'revert_reason_code_on_commands'::text, '0078_revert_reason_code_on_commands.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'activity_feed'::text, '0079_activity_feed.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'charge_first_mutual_exclusion'::text, '0080_charge_first_mutual_exclusion.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'bay_routing_seats_the_vehicle'::text, '0081_bay_routing_seats_the_vehicle.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'wash_hours_clock_backstop'::text, '0082_wash_hours_clock_backstop.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'deep_clean_cabin_condition'::text, '0083_deep_clean_cabin_condition.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'deep_clean_flag_ordering'::text, '0084_deep_clean_flag_ordering.sql'::text),
    ('UNVERIFIED-NO-LEDGER-ROW'::text, 'wash_must_do_flag_reconciliation'::text, '0085_wash_must_do_flag_reconciliation.sql'::text),
    ('20260829162450'::text, 'refusals_carry_their_reason'::text, '0086_refusals_carry_their_reason.sql'::text),
    ('20260829162640'::text, 'no_command_left_dangling'::text, '0087_no_command_left_dangling.sql'::text),
    ('20260829162810'::text, 'occupied_refusals_reach_the_conflict_ledger'::text, '0088_occupied_refusals_reach_the_conflict_ledger.sql'::text),
    ('20260829164021'::text, 'a_leg_closes_with_its_work'::text, '0089_a_leg_closes_with_its_work.sql'::text),
    ('20260829164858'::text, 'cuopt_enactments_carry_their_verb'::text, '0090_cuopt_enactments_carry_their_verb.sql'::text),
    ('20260829165759'::text, 'the_kernel_defends_the_verb'::text, '0091_the_kernel_defends_the_verb.sql'::text),
    ('20260829171141'::text, 'events_carry_their_run'::text, '0092_events_carry_their_run.sql'::text),
    ('20260829171749'::text, 'a_run_leaves_no_plan_residue'::text, '0093_a_run_leaves_no_plan_residue.sql'::text),
    ('20260829171855'::text, 'canonical_means_constant_not_null'::text, '0094_canonical_means_constant_not_null.sql'::text),
    ('20260829172404'::text, 'the_reset_keeps_a_whitelist_not_a_blacklist'::text, '0095_the_reset_keeps_a_whitelist_not_a_blacklist.sql'::text),
    ('20260829172453'::text, 'target_soc_pins_to_the_seeded_constant'::text, '0096_target_soc_pins_to_the_seeded_constant.sql'::text),
    ('20260829173602'::text, 'no_approval_outlives_its_run'::text, '0097_no_approval_outlives_its_run.sql'::text),
    ('20260829214014'::text, 'the_drain_admission_is_not_a_coin_flip'::text, '0098_the_drain_admission_is_not_a_coin_flip.sql'::text),
    ('20260829214918'::text, 'the_latest_need_is_not_a_heap_order'::text, '0099_the_latest_need_is_not_a_heap_order.sql'::text),
    ('20260829215922'::text, 'service_flow_admissions_close_their_order'::text, '0100_service_flow_admissions_close_their_order.sql'::text),
    ('20260829222635'::text, 'natural_completion_finalizes'::text, '0101_natural_completion_finalizes.sql'::text),
    ('20260829222909'::text, 'finalize_at_the_driver_not_mid_world'::text, '0102_finalize_at_the_driver_not_mid_world.sql'::text),
    ('20260829223107'::text, 'the_live_completion_seam'::text, '0103_the_live_completion_seam.sql'::text),
    ('20260829230116'::text, 'the_tech_verdict_is_not_a_coin_from_another_run'::text, '0104_the_tech_verdict_is_not_a_coin_from_another_run.sql'::text),
    ('20260829230554'::text, 'the_cert_run_quiesces_the_llm_proposer'::text, '0105_the_cert_run_quiesces_the_llm_proposer.sql'::text),
    ('20260829231202'::text, 'the_production_brain_stands_off_a_cert_run'::text, '0106_the_production_brain_stands_off_a_cert_run.sql'::text),
    ('20260830034718'::text, 'the_run_draws_its_own_world'::text, '0107_the_run_draws_its_own_world.sql'::text),
    ('20260830035542'::text, 'the_atom_admission_closes_its_order'::text, '0108_the_atom_admission_closes_its_order.sql'::text),
    ('20260830040601'::text, 'the_watermark_does_not_outlive_its_run'::text, '0109_the_watermark_does_not_outlive_its_run.sql'::text),
    ('20260830042119'::text, 'the_one_command_determinism_check'::text, '0110_the_one_command_determinism_check.sql'::text),
    ('20260830042328'::text, '0110b_pair_verdict_within_status_vocabulary'::text, '0110b_pair_verdict_within_status_vocabulary.sql'::text),
    ('20260830043106'::text, 'the_production_session_lifecycle'::text, '0111_the_production_session_lifecycle.sql'::text),
    ('20260830043153'::text, 'the_agent_gate_is_a_policy'::text, '0112_the_agent_gate_is_a_policy.sql'::text),
    ('20260830044116'::text, 'the_switch_must_exist_before_it_can_be_off'::text, '0113_the_switch_must_exist_before_it_can_be_off.sql'::text),
    ('20260830050414'::text, 'the_release_takes_its_shape_from_the_feed'::text, '0114_the_release_takes_its_shape_from_the_feed.sql'::text),
    ('20260830052403'::text, 'the_soc_state_belongs_to_the_run'::text, '0115_the_soc_state_belongs_to_the_run.sql'::text),
    ('20260830053720'::text, 'the_reservations_timestamp_dies_with_it'::text, '0116_the_reservations_timestamp_dies_with_it.sql'::text),
    ('20260830055459'::text, 'the_runs_claims_die_with_it'::text, '0117_the_runs_claims_die_with_it.sql'::text),
    ('20260830131520'::text, 'the_clock_of_record_is_the_runs'::text, '0118_the_clock_of_record_is_the_runs.sql'::text),
    ('20260830134026'::text, 'the_coin_had_two_holds'::text, '0119_the_coin_had_two_holds.sql'::text),
    ('20260830135956'::text, 'the_whitelist_kept_a_moving_part'::text, '0120_the_whitelist_kept_a_moving_part.sql'::text),
    ('20260830141928'::text, 'the_odometer_is_dealt_not_inherited'::text, '0121_the_odometer_is_dealt_not_inherited.sql'::text),
    ('20260830142542'::text, 'the_odometer_draw_calls_the_twin'::text, '0121b_the_odometer_draw_calls_the_twin.sql'::text),
    ('20260830165520'::text, 'the_sweep_reads_the_clock_the_stamp_was_written_in'::text, '0122_the_sweep_reads_the_clock_the_stamp_was_written_in.sql'::text),
    ('20260830182110'::text, 'the_latest_need_belongs_to_the_run'::text, '0123_the_latest_need_belongs_to_the_run.sql'::text),
    ('20260830185547'::text, 'the_visit_ledger_belongs_to_the_run'::text, '0124_the_visit_ledger_belongs_to_the_run.sql'::text),
    ('20260830213611'::text, 'the_pair_reads_its_own_boot_state'::text, '0125_the_pair_reads_its_own_boot_state.sql'::text),
    ('20260830213715'::text, 'the_dead_enactor_is_archived'::text, '0126_the_dead_enactor_is_archived.sql'::text),
    ('20260830214923'::text, 'the_teardown_retires_the_interrupted'::text, '0127_the_teardown_retires_the_interrupted.sql'::text),
    ('20260830221659'::text, 'the_adoption_pick_gains_its_content_keys'::text, '0128_the_adoption_pick_gains_its_content_keys.sql'::text),
    ('20260831000801'::text, 'every_pick_orders_itself_completely'::text, '0129_every_pick_orders_itself_completely.sql'::text),
    ('20260831012206'::text, 'the_deferral_queue_orders_itself_completely'::text, '0130_the_deferral_queue_orders_itself_completely.sql'::text),
    ('20260831020239'::text, 'the_matrix_reads_itself_from_the_ledger'::text, '0131_the_matrix_reads_itself_from_the_ledger.sql'::text),
    ('20260831133729'::text, 'the_power_cap_is_a_constraint'::text, '0132_the_power_cap_is_a_constraint.sql'::text),
    ('20260831150515'::text, 'the_energy_path_joins_the_certification'::text, '0133_the_energy_path_joins_the_certification.sql'::text),
    ('20260831182816'::text, 'the_energy_path_reads_only_its_own_run'::text, '0134_the_energy_path_reads_only_its_own_run.sql'::text),
    ('20260831185034'::text, 'the_battery_starts_cold_and_the_fingerprint_sees_it'::text, '0135_the_battery_starts_cold_and_the_fingerprint_sees_it.sql'::text),
    ('20260831202425'::text, 'the_site_limit_is_an_input'::text, '0136_the_site_limit_is_an_input.sql'::text),
    ('20260831231230'::text, 'the_fingerprint_stops_hashing_a_write_timestamp'::text, '0137_the_fingerprint_stops_hashing_a_write_timestamp.sql'::text),
    ('20260901002249'::text, 'the_demand_we_cause_carries_the_run_id'::text, '0138_the_demand_we_cause_carries_the_run_id.sql'::text),
    ('20260901011004'::text, 'the_end_state_is_part_of_the_verdict'::text, '0139_the_end_state_is_part_of_the_verdict.sql'::text),
    ('20260901005506'::text, 'the_matrix_knows_when_it_went_stale'::text, '0140_the_matrix_knows_when_it_went_stale.sql'::text),
    ('20260901010048'::text, 'the_floor_reads_the_ledger_for_every_caller'::text, '0141_the_floor_reads_the_ledger_for_every_caller.sql'::text),
    ('20260901010305'::text, 'a_migration_classifies_itself'::text, '0142_a_migration_classifies_itself.sql'::text),
    ('20260901011644'::text, 'a_short_arm_is_inconclusive_and_a_streak_starts_at_the_floor'::text, '0143_a_short_arm_is_inconclusive_and_a_streak_starts_at_the_floor.sql'::text),
    ('20260901075119'::text, 'the_reset_stamp_leaves_the_wall_clock'::text, '0144_the_reset_stamp_leaves_the_wall_clock.sql'::text),
    ('20260901135321'::text, 'the_preflight_validator_reads_only_its_own_run'::text, '0145_the_preflight_validator_reads_only_its_own_run.sql'::text),
    ('20260901172745'::text, 'the_load_sum_reads_only_its_own_run_and_depot'::text, '0146_the_load_sum_reads_only_its_own_run_and_depot.sql'::text),
    ('20260901182823'::text, 'the_noise_salt_is_not_a_random_id'::text, '0147_the_noise_salt_is_not_a_random_id.sql'::text),
    ('20260901234940'::text, 'the_verdict_sorts_by_every_field_it_hashes_and_hears_the_energy_stream'::text, '0148_the_verdict_sorts_by_every_field_it_hashes_and_hears_the_energy_stream.sql'::text),
    ('20260901235044'::text, 'the_matrix_is_keyed_by_depot_and_reads_the_energy_canon'::text, '0149_the_matrix_is_keyed_by_depot_and_reads_the_energy_canon.sql'::text),
    ('20260902121232'::text, 'the_odometer_sums_only_its_own_run'::text, '0150_the_odometer_sums_only_its_own_run.sql'::text),
    ('20260902121253'::text, 'the_fleet_api_returns_only_production_commands'::text, '0151_the_fleet_api_returns_only_production_commands.sql'::text),
    ('20260902121334'::text, 'the_certification_runs_the_deterministic_core_alone'::text, '0152_the_certification_runs_the_deterministic_core_alone.sql'::text),
    ('20260902124926'::text, 'a_grid_fixture_the_engine_cannot_tell_from_a_depot'::text, '0153_a_grid_fixture_the_engine_cannot_tell_from_a_depot.sql'::text),
    ('20260902125859'::text, 'the_assertion_matched_a_key_only_one_verb_carries'::text, '0154_the_assertion_matched_a_key_only_one_verb_carries.sql'::text),
    ('20260902190425'::text, 'the_site_meter_reports_the_power_that_flowed'::text, '0155_the_site_meter_reports_the_power_that_flowed.sql'::text),
    ('20260902191145'::text, 'a_point_that_fits_beats_a_point_that_starves'::text, '0156_a_point_that_fits_beats_a_point_that_starves.sql'::text),
    ('20260902191331'::text, 'the_assertions_state_the_rule_the_engine_actually_has'::text, '0157_the_assertions_state_the_rule_the_engine_actually_has.sql'::text),
    ('20260902194149'::text, 'the_sixth_kpi_did_the_asset_make_its_due_time'::text, '0158_the_sixth_kpi_did_the_asset_make_its_due_time.sql'::text),
    ('20260902194751'::text, 'wait_or_take_what_fits_is_a_policy_not_a_constant'::text, '0159_wait_or_take_what_fits_is_a_policy_not_a_constant.sql'::text),
    ('20260902195045'::text, 'the_need_check_learns_about_holds_and_reservations'::text, '0160_the_need_check_learns_about_holds_and_reservations.sql'::text),
    ('20260902195148'::text, 'repair_0160_the_anchor_must_be_unique_not_merely_present'::text, '0160r_repair_the_anchor_must_be_unique_not_merely_present.sql'::text),
    ('20260902195819'::text, 'the_grid_can_be_broken_on_purpose_and_must_prove_it'::text, '0161_the_grid_can_be_broken_on_purpose_and_must_prove_it.sql'::text),
    ('20260902200201'::text, 'a_declared_fault_is_part_of_the_seeded_world'::text, '0162_a_declared_fault_is_part_of_the_seeded_world.sql'::text),
    ('20260902200406'::text, 'a_fault_needs_a_clock_and_a_repair_time'::text, '0163_a_fault_needs_a_clock_and_a_repair_time.sql'::text),
    ('20260902200433'::text, 'drop_the_two_arg_grid_fault_overload'::text, '0164_drop_the_two_arg_grid_fault_overload.sql'::text),
    ('20260902200851'::text, 'the_fault_assertion_learns_that_faults_end'::text, '0165_the_fault_assertion_learns_that_faults_end.sql'::text),
    ('20260902201059'::text, 'starved_means_below_its_own_target_not_below_ninety'::text, '0166_starved_means_below_its_own_target_not_below_ninety.sql'::text),
    ('20260902205647'::text, 'the_run_key_hashed_the_outcome_and_the_wait_was_always_zero'::text, '0167_the_run_key_hashed_the_outcome_and_the_wait_was_always_zero.sql'::text),
    ('20260902234153'::text, 'the_kpi_view_recomputed_every_run_to_answer_about_one'::text, '0168_the_kpi_view_recomputed_every_run_to_answer_about_one.sql'::text),
    ('20260903025526'::text, 'the_engine_can_say_it_found_nothing_but_not_that_it_never_looked'::text, '0169_the_engine_can_say_it_found_nothing_but_not_that_it_never_looked.sql'::text),
    ('20260902235023'::text, 'unserved_counted_the_horizon_not_the_engine'::text, '0170_unserved_counted_the_horizon_not_the_engine.sql'::text),
    ('20260902235218'::text, 'the_plan_lookup_reached_back_past_its_own_return'::text, '0171_the_plan_lookup_reached_back_past_its_own_return.sql'::text),
    ('20260903003438'::text, 'a_return_stamped_after_the_run_ended_never_happened'::text, '0172_a_return_stamped_after_the_run_ended_never_happened.sql'::text),
    ('20260903023713'::text, 'the_overnight_planner_had_nashville_baked_in'::text, '0173_the_overnight_planner_had_nashville_baked_in.sql'::text),
    ('20260903024009'::text, 'a_rule_that_cannot_fire_should_not_look_like_one_that_enforces'::text, '0174_a_rule_that_cannot_fire_should_not_look_like_one_that_enforces.sql'::text),
    ('20260903031500'::text, 'the_pair_and_the_scenario_must_name_the_same_world'::text, '0175_the_pair_and_the_scenario_must_name_the_same_world.sql'::text),
    ('20260903034836'::text, 'a_deadline_past_the_end_of_the_run_was_never_missed'::text, '0176_a_deadline_past_the_end_of_the_run_was_never_missed.sql'::text),
    ('20260903113902'::text, 'the_cold_start_guard_looked_at_every_depot'::text, '0177_the_cold_start_guard_looked_at_every_depot.sql'::text),
    ('20260903035049'::text, 'an_asset_that_arrived_on_the_last_tick_never_had_a_turn'::text, '0178_an_asset_that_arrived_on_the_last_tick_never_had_a_turn.sql'::text),
    ('20260903075250'::text, 'the_recorder_wrote_a_status_the_table_refused'::text, '0179_the_recorder_wrote_a_status_the_table_refused.sql'::text),
    ('20260903171637'::text, 'the_watermark_sweep_cleared_every_depot'::text, '0180_the_watermark_sweep_cleared_every_depot.sql'::text),
    ('20260903225200'::text, 'the_teardown_recorded_a_return_that_never_happened'::text, '0181_the_teardown_recorded_a_return_that_never_happened.sql'::text),
    ('20260903225512'::text, 'kpi_one_reported_more_hours_than_the_window_could_hold'::text, '0182_kpi_one_reported_more_hours_than_the_window_could_hold.sql'::text),
    ('20260903230222'::text, 'kpi_two_counted_a_booking_nobody_kept_as_a_turn'::text, '0183_kpi_two_counted_a_booking_nobody_kept_as_a_turn.sql'::text),
    ('20260903230800'::text, 'kpi_four_divided_by_the_same_bad_denominator'::text, '0184_kpi_four_divided_by_the_same_bad_denominator.sql'::text),
    ('20260904013402'::text, 'the_correction_nobody_could_see_from_the_one_command'::text, '0185_the_correction_nobody_could_see_from_the_one_command.sql'::text),
    ('20260904013840'::text, 'the_hours_were_filed_under_a_day_they_did_not_happen_on'::text, '0186_the_hours_were_filed_under_a_day_they_did_not_happen_on.sql'::text),
    ('20260904014708'::text, 'the_kpi_that_scanned_two_and_a_half_million_rows_per_call'::text, '0187_the_kpi_that_scanned_two_and_a_half_million_rows_per_call.sql'::text),
    ('20260904015708'::text, 'the_percentile_that_dropped_its_worst_cases'::text, '0188_the_percentile_that_dropped_its_worst_cases.sql'::text),
    ('20260904015843'::text, 'the_population_reaches_the_command_that_ships_the_number'::text, '0189_the_population_reaches_the_command_that_ships_the_number.sql'::text),
    ('20260904020600'::text, 'the_index_that_closed_the_unattributed_five_seconds'::text, '0190_the_index_that_closed_the_unattributed_five_seconds.sql'::text),
    ('20260904140914'::text, 'a_baseline_to_measure_ourselves_against'::text, '0191_a_baseline_to_measure_ourselves_against.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'an_atom_that_can_be_required_must_be_retirable'::text, '0192_an_atom_that_can_be_required_must_be_retirable.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_eta_was_read_from_every_run_that_ever_dispatched_the_car'::text, '0193_the_eta_was_read_from_every_run_that_ever_dispatched_the_car.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'three_wall_clocks_in_the_world_the_fingerprint_hashes'::text, '0194_three_wall_clocks_in_the_world_the_fingerprint_hashes.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_bay_queue_was_ordered_by_a_number_drawn_fresh_each_run'::text, '0195_the_bay_queue_was_ordered_by_a_number_drawn_fresh_each_run.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'two_flags_that_die_with_the_transaction_and_the_pair_is_one_transaction'::text, '0196_two_flags_that_die_with_the_transaction_and_the_pair_is_one_transaction.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'an_assignment_the_calendar_refused_is_not_an_assignment'::text, '0197_an_assignment_the_calendar_refused_is_not_an_assignment.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'nobody_anonymous_changes_the_world_and_identity_is_the_servers_to_assign'::text, '0198_nobody_anonymous_changes_the_world_and_identity_is_the_servers_to_assign.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_verdict_hears_the_proposers_and_the_floor_hears_every_recert'::text, '0199_the_verdict_hears_the_proposers_and_the_floor_hears_every_recert.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_twin_observes_the_kernel_derives_and_a_real_vehicle_stops_rolling_dice'::text, '0200_the_twin_observes_the_kernel_derives_and_a_real_vehicle_stops_rolling_dice.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_priors_are_part_of_the_world_and_the_verdict_now_names_them'::text, '0201_the_priors_are_part_of_the_world_and_the_verdict_now_names_them.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'every_evaluation_names_its_run_and_a_pair_stops_sharing_one_clock'::text, '0202_every_evaluation_names_its_run_and_a_pair_stops_sharing_one_clock.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_verdict_hears_the_shield_measured_before_it_may_fail_a_pair'::text, '0203_the_verdict_hears_the_shield_measured_before_it_may_fail_a_pair.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_run_has_one_clock_and_the_shield_and_the_events_read_it'::text, '0204_the_run_has_one_clock_and_the_shield_and_the_events_read_it.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'h_rule_may_now_fail_a_pair'::text, '0205_h_rule_may_now_fail_a_pair.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'every_recall_decision_is_a_ledger_row_and_the_implementation_is_a_name'::text, '0206_every_recall_decision_is_a_ledger_row_and_the_implementation_is_a_name.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'a_tie_in_the_command_walk_is_settled_by_the_issuance_sequence_not_the_heap'::text, '0207_a_tie_in_the_command_walk_is_settled_by_the_issuance_sequence_not_the_heap.sql'::text),
    ('20260907213653'::text, 'the_verdict_sees_what_the_shield_read'::text, '0208_the_verdict_sees_what_the_shield_read.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_frame_carries_the_join_key_and_the_plug'::text, '0209_the_frame_carries_the_join_key_and_the_plug.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'a_production_run_does_not_recall_on_a_parked_implementation'::text, '0210_a_production_run_does_not_recall_on_a_parked_implementation.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_work_side_can_refuse_a_recall_and_the_refusal_is_a_ledger_row'::text, '0211_the_work_side_can_refuse_a_recall_and_the_refusal_is_a_ledger_row.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_tick_asks_the_work_side_before_it_books_the_stall'::text, '0212_the_tick_asks_the_work_side_before_it_books_the_stall.sql'::text),
    ('20260908111702'::text, 'kpi_four_counted_seven_actor_types_that_cannot_exist'::text, '0213_kpi_four_counted_seven_actor_types_that_cannot_exist.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'the_cheap_answer_costs_eight_queries_because_i_asked_last'::text, '0214_the_cheap_answer_costs_eight_queries_because_i_asked_last.sql'::text),
    ('APPLIED-NO-LEDGER-ROW'::text, 'a_standing_refusal_stands_whatever_the_rate_is_now'::text, '0215_a_standing_refusal_stands_whatever_the_rate_is_now.sql'::text),
    ('20260908081848'::text, 'the_settlement_record_binds_to_whichever_booking_the_heap_returned_first'::text, '0216_the_settlement_record_binds_to_whichever_booking_the_heap_returned_first.sql'::text),
    ('20260908082227'::text, 'the_verdict_sees_the_settlement_record_and_h_rcl_may_now_fail_a_pair'::text, '0217_the_verdict_sees_the_settlement_record_and_h_rcl_may_now_fail_a_pair.sql'::text),
    ('20260908084304'::text, 'h_sdr_hashed_a_signature_computed_over_a_run_scoped_id'::text, '0218_h_sdr_hashed_a_signature_computed_over_a_run_scoped_id.sql'::text),
    ('20260908111547'::text, 'h_sdr_may_now_fail_a_pair'::text, '0219_h_sdr_may_now_fail_a_pair.sql'::text),
    ('20260908111846'::text, 'the_schedule_task_emitter_asks_the_stall_what_kind_of_charge_it_was'::text, '0220_the_schedule_task_emitter_asks_the_stall_what_kind_of_charge_it_was.sql'::text),
    ('20260908111950'::text, 'the_run_scope_predicate_no_index_can_read'::text, '0221_the_run_scope_predicate_no_index_can_read.sql'::text),
    ('20260908112038'::text, 'the_fingerprint_hashed_a_million_rows_to_report_thirteen'::text, '0222_the_fingerprint_hashed_a_million_rows_to_report_thirteen.sql'::text),
    ('20260908133954'::text, 'the_load_meter_asks_which_run_is_running_once_per_row'::text, '0223_the_load_meter_asks_which_run_is_running_once_per_row.sql'::text),
    ('20260908134109'::text, 'the_refusal_reactor_says_production_and_hands_you_a_sim_run_id'::text, '0224_the_refusal_reactor_says_production_and_hands_you_a_sim_run_id.sql'::text),
    ('PENDING'::text, 'the_canon_comparison_sees_every_atom_the_pair_enforces'::text, '0225_the_canon_comparison_sees_every_atom_the_pair_enforces.sql'::text),
    ('PENDING'::text, 'the_recert_floor_reads_a_name_the_ledger_never_writes'::text, '0226_the_recert_floor_reads_a_name_the_ledger_never_writes.sql'::text),
    ('PENDING'::text, 'the_load_meter_scans_forty_five_thousand_rows_to_sum_three_hundred'::text, '0227_the_load_meter_scans_forty_five_thousand_rows_to_sum_three_hundred.sql'::text),
    ('PENDING'::text, 'provenance_asks_the_depot_not_the_run_id'::text, '0228_provenance_asks_the_depot_not_the_run_id.sql'::text)
-- <<< END GENERATED MANIFEST
),

-- Three header values mean "there is no ledger version to compare against",
-- and each means something different. Keeping them apart is the whole point:
-- calling an applied migration PENDING would have been a comfortable lie.
--
--   PENDING                   written, deliberately not yet applied
--   APPLIED-NO-LEDGER-ROW     applied through execute_sql or the dashboard SQL
--                             editor, neither of which writes a
--                             supabase_migrations row. The file's own APPLIED
--                             footer is the only record that it is live.
--   UNVERIFIED-NO-LEDGER-ROW  no ledger row AND nothing in the file saying it
--                             was applied. Live-or-not is genuinely unknown.
--
-- Only real timestamps can join the ledger, so mf excludes all three. Sections
-- A/B/C therefore say nothing about them — Section E does, out loud, so they
-- cannot quietly become permanent.
no_version AS (
  SELECT version, name, file FROM repo_manifest
   WHERE version IN ('PENDING','APPLIED-NO-LEDGER-ROW','UNVERIFIED-NO-LEDGER-ROW')
),
mf AS (
  SELECT version, name, file FROM repo_manifest
   WHERE version IS NOT NULL
     AND version NOT IN ('PENDING','APPLIED-NO-LEDGER-ROW','UNVERIFIED-NO-LEDGER-ROW')
),
led AS (
  SELECT version, name FROM supabase_migrations.schema_migrations
),

-- A. Applied to the database, no file in this repo.  ← THIS IS THE ALARM
drift AS (
  SELECT d.version, d.name
  FROM led d CROSS JOIN cut c
  WHERE d.version > c.baseline_through
    AND NOT EXISTS (SELECT 1 FROM mf m WHERE m.version = d.version)
),

-- B. File in this repo, never applied to the database.
pending AS (
  SELECT m.version, m.name, m.file
  FROM mf m
  WHERE NOT EXISTS (SELECT 1 FROM led d WHERE d.version = m.version)
),

-- B2. Files still marked PENDING (written but not yet applied). Informational.
unapplied AS (
  SELECT m.name, m.file FROM no_version m WHERE m.version = 'PENDING'
),

-- E. Applied, or possibly applied, with no ledger row to prove it either way.
--    Not drift and not pending — a third state the ledger simply cannot see.
unledgered AS (
  SELECT m.version, m.name, m.file FROM no_version m WHERE m.version <> 'PENDING'
),

-- C. Same version, different name — the file and the ledger disagree.
mismatch AS (
  SELECT m.version, m.name AS file_says, d.name AS db_says, m.file
  FROM mf m JOIN led d ON d.version = m.version
  WHERE d.name IS DISTINCT FROM m.name
),

-- D. Backstop: live routine counts vs the counts db/baseline/ recorded.
--
-- These are EXPECTED counts, not frozen ones. A migration that legitimately adds
-- or removes a routine must move the number here in the same commit, or the smoke
-- alarm cries wolf forever and people learn to ignore it.
--
-- Change log for this line — every edit needs a reason and a committed file:
--   2026-08-04  public 336 -> 337.  db/migrations/0002_approval_gate_decider.sql
--               (ledger version 20260804140958) added exactly one routine,
--               public.ottoq_decide_indepot_approvals. VERIFIED by diffing the live
--               public routine list against db/baseline/functions_public.sql: one
--               name added, zero names removed. The other five functions that
--               migration replaced were CREATE OR REPLACE, so they do not move a count.
--   2026-08-05  public 337 -> 339.  db/migrations/0006_slim_writes_and_arm_retention.sql
--               (ledger version 20260805142711) added exactly two routines:
--                 public.ottoq_events_slim_new_state  -- the BEFORE INSERT trigger fn
--                                                        that stops re-writing new_state
--                 public.ottoq_event_new_state(uuid)  -- the rebuild-on-read reader
--               VERIFIED BY NAME, not by arithmetic. The live public routine list was
--               diffed against db/baseline/functions_public.sql (332 distinct names):
--               live 335, ADDED = {ottoq_decide_indepot_approvals (0002),
--               ottoq_event_new_state, ottoq_events_slim_new_state}, REMOVED = {} .
--               Zero names removed is the load-bearing half of that check -- 0006
--               drops nothing, and this proves it rather than asserting it.
--               The three routines 0006 REPLACED (ottoq_purge_prior_runs,
--               ottoq_retention_purge_worker 4-arg, ottoq_events_block_mutation) were
--               CREATE OR REPLACE and do not move a count. The 3-arg overload of
--               ottoq_retention_purge_worker was deliberately left in place (never
--               drop), so the procedure count is unchanged at 2 overloads.
--   2026-08-07  ottoq 48 -> 51.  db/migrations/0011_forward_bay_reservation_at_return_signal.sql
--               (ledger version 20260806231121) added exactly three routines, all in the
--               ottoq schema:
--                 ottoq.ottoq_book_workflow_legs(uuid,uuid,uuid,timestamptz,int,int,text[],timestamptz,text)
--                 ottoq.ottoq_reserve_inbound_bays(uuid,uuid,uuid,timestamptz,timestamptz)
--                 ottoq.ottoq_svc_to_stall_type(text,uuid)
--               VERIFIED BY NAME. The 6-arg ottoq_book_workflow was NOT dropped — 0011
--               turned it into a thin delegate via CREATE OR REPLACE, so it does not move
--               a count. Everything else 0011 touched was CREATE OR REPLACE.
--   2026-08-07  no count change.  db/migrations/0012_tick_cost_and_metronome_ceiling.sql
--               (20260807001645) adds one INDEX and CREATE OR REPLACEs one procedure, and
--               db/migrations/0013_metronome_guard_reads_the_real_timeout.sql
--               (20260807002716) CREATE OR REPLACEs that same procedure again. Neither
--               adds or removes a routine, so public stays 339 and twin stays 71.
--   2026-08-07  ottoq 51 -> 52.  db/migrations/0014_bay_binding_witness.sql
--               (20260807005437) adds exactly ONE routine to the ottoq schema:
--                 ottoq.ottoq_witness_booking_transition()   -- AFTER UPDATE trigger fn
--               VERIFIED BY NAME against the live catalogue, not inferred from a count.
--               0014 is purely additive: it also creates one table
--               (public.ottoq_bay_binding_witness), two indexes on it, and one trigger
--               (ottoq_witness_booking_transition_trg on public.ottoq_stall_bookings).
--               Tables, indexes and triggers are not routines, so ONLY the ottoq count
--               moves. Nothing was dropped or replaced, so public stays 339 and twin
--               stays 71.
--   2026-08-07  ottoq 52 -> 54.  db/migrations/0015_early_activation_and_untagged_event_flood.sql
--               (20260807013120) adds exactly TWO routines, both in the ottoq schema:
--                 ottoq.ottoq_vehicle_bay_ready(uuid,uuid,timestamptz)  -- is the car
--                       physically free to be seated in a bay right now (no unfinished
--                       charge leg). This is what narrows the activation window gate.
--                 ottoq.ottoq_active_sim_run_id()                       -- the live run,
--                       memoised transaction-locally, so the row triggers can tag their
--                       events with the run instead of writing them as production.
--               VERIFIED BY NAME against the live catalogue, not inferred from a count:
--               the live ottoq name list is 54 long, ADDED = {ottoq_active_sim_run_id,
--               ottoq_vehicle_bay_ready}, REMOVED = {} — all 52 prior names are still
--               present, including ottoq_svc_to_stall_type. The five functions 0015
--               replaced (ottoq_activate_due_bay_reservations,
--               ottoq_reconcile_bay_reservations, public.ottoq_vehicles_state_change,
--               public.ottoq_stalls_state_change, public.ottoq_evaluate_rule_core) were
--               CREATE OR REPLACE and do not move a count, so public stays 339 and twin
--               stays 71. Nothing was dropped.
--   2026-08-08  ottoq 54 -> 55, public 339 -> 340.
--               db/migrations/0019_rider_flag_holds_the_vehicle.sql (20260808153457)
--               adds exactly TWO routines, one in each schema:
--                 public.ottoq_rider_flag_due(uuid,uuid,timestamptz)  -- the shared,
--                       TOTAL predicate both dispatch gates consult: is this vehicle
--                       carrying a rider cleaning flag that is pending AND due?
--                 ottoq.ottoq_rider_flag_indepot_sweep(uuid,uuid,timestamptz) -- gives a
--                       flag maturing on a PARKED car a path, by appending the cleaning
--                       atom to the visit it is already having.
--               VERIFIED BY NAME against the live catalogue, not inferred from a count.
--               The four functions 0019 replaced (ottoq.ottoq_plan_dispatch_tick,
--               twin.ottoq_sim_dispatch_vehicle, twin.ottoq_sim_auto_dispatch_tick,
--               public.ottoq_evaluate_return_need) were CREATE OR REPLACE and do not move
--               a count, so twin stays 71. Nothing was dropped.
--               Until this bump, Section D read INVESTIGATE at +1/+1 on every run.
--
--               0020 and 0021 then move `public` again -- see below.
--
--               db/migrations/0020_rider_flag_consume_and_place_is_atomic.sql
--               (20260808165323) adds exactly THREE routines, all trigger functions
--               in public (public 340 -> 343):
--                 public.ottoq_rider_flag_placement_guard
--                 public.ottoq_rider_flag_mark_served
--                 public.ottoq_reanchor_rider_flags_on_clock_rebase
--
--               0020 also REPLACES twin.ottoq_sim_generate_service_manifest and
--               ottoq.ottoq_rider_flag_indepot_sweep by CREATE OR REPLACE, which does
--               not move a count, so twin stays 71.  Nothing was dropped.  The one
--               object 0020 removes is a CONSTRAINT
--               (ottoq_visit_needs_vehicle_id_visit_key_key, replaced by the
--               run-scoped unique index ottoq_visit_needs_vehicle_visit_run_uk);
--               constraints are not routines, so no count moves for it, and its exact
--               definition is preserved in public.mig0020_prestate.
--   2026-08-08  public 343 -> 344.  db/migrations/0021_one_vehicle_one_stall.sql
--               (20260808170813) adds exactly ONE routine, a trigger function in
--               public: public.ottoq_stall_seat_is_exclusive. VERIFIED BY NAME.
--               It replaces nothing and drops nothing, so ottoq stays 55 and twin
--               stays 71. The trigger it installs is not a routine.
--   2026-08-08  public 344 -> 346.  db/migrations/0022_a_run_owns_its_rows.sql
--               (20260808182226) adds exactly TWO routines, both in public:
--                 public.ottoq_check_run_scope_registry()  -- the run-scope drift guard:
--                       one row per defect (unclassified run-scoped column, engine/stamp
--                       table missing its FK, or an FK that has become ON DELETE CASCADE),
--                       graded 'block' vs 'warn'.
--                 public.ottoq_current_sim_run_id()        -- the run a run-blind reader
--                       must scope to: the running run, else the most recently started.
--               VERIFIED BY NAME against the live catalogue, not inferred from a count:
--               live public is 346, ADDED = {ottoq_check_run_scope_registry,
--               ottoq_current_sim_run_id}, REMOVED = {}.
--               The three routines 0022 REPLACED (public.ottoq_purge_prior_runs,
--               public.ottoq_build_decision_frame, public.ottoq_twin_snapshot) were all
--               CREATE OR REPLACE and do not move a count — all three are still present.
--               Their pre-images are in ottoq_schema_snapshots under label '0022_pre'.
--               So ottoq stays 55 and twin stays 71. Nothing was dropped.
--               0022 also adds 45 FOREIGN KEY constraints, 2 tables
--               (ottoq_run_scope_registry, p0022_orphan_quarantine) and 2 indexes;
--               none of those are routines, so they move no count.
--   2026-08-08  public 346 -> 349.  db/migrations/0023_a_finished_run_is_read_only.sql
--               (20260808193142) adds exactly THREE routines, all in public:
--                 public.ottoq_close_run_needs(uuid, text)  -- closes ONE run's own
--                       still-open visit needs, scoped to the run named. This is the
--                       write that replaces the old depot-wide cross-run supersede.
--                 public.ottoq_tg_close_run_needs_on_terminal()  -- the trigger function
--                       behind trigger ottoq_sim_runs_close_needs: a run's needs close
--                       when the RUN ends, on every path out of a live status.
--                 public.ottoq_build_decision_frame(uuid, uuid)  -- an OVERLOAD, not a
--                       replacement. The 1-arg form is kept and now delegates to it with
--                       ottoq_current_sim_run_id(), so run-blind callers are unchanged.
--               VERIFIED BY NAME against the live catalogue, not inferred from a count:
--               live public is 349, ADDED = {ottoq_close_run_needs,
--               ottoq_tg_close_run_needs_on_terminal,
--               ottoq_build_decision_frame(uuid,uuid)}, REMOVED = {}.
--               The five routines 0023 REPLACED in place (ottoq_sim_run_scenario,
--               ottoq_build_decision_frame(uuid), ottoq_capture_decision_snapshot,
--               ottoq_api_twin_get_state, ottoq_score_run, ottoq_energy_cost_for_run)
--               were all CREATE OR REPLACE under an md5 guard and move no count; their
--               pre-images are in ottoq_schema_snapshots under label '0023_pre'.
--               So ottoq stays 55 and twin stays 71. NOTHING WAS DROPPED.
--               0023 also adds 1 trigger (ottoq_sim_runs_close_needs on
--               public.ottoq_sim_runs); a trigger is not a routine and moves no count.
baseline_counts(sch, n) AS (
  VALUES ('public', 349), ('ottoq', 55), ('twin', 71)
),
live_counts AS (
  SELECT n.nspname::text AS sch, count(*)::int AS n
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'ottoq', 'twin')
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend dd
      WHERE dd.objid = p.oid AND dd.deptype = 'e'   -- exclude extension-owned (PostGIS etc.)
    )
  GROUP BY 1
),
counts AS (
  SELECT b.sch, b.n AS baseline_n, COALESCE(l.n, 0) AS live_n
  FROM baseline_counts b LEFT JOIN live_counts l ON l.sch = b.sch
),

-- Totals used by the verdict line.
tally AS (
  SELECT
    (SELECT count(*) FROM drift)     AS n_drift,
    (SELECT count(*) FROM pending)   AS n_pending,
    (SELECT count(*) FROM mismatch)  AS n_mismatch,
    (SELECT count(*) FROM unapplied) AS n_unapplied,
    (SELECT count(*) FROM unledgered WHERE version = 'APPLIED-NO-LEDGER-ROW')    AS n_unledgered_applied,
    (SELECT count(*) FROM unledgered WHERE version = 'UNVERIFIED-NO-LEDGER-ROW') AS n_unledgered_unknown,
    (SELECT count(*) FROM counts WHERE live_n <> baseline_n) AS n_countdiff,
    (SELECT count(*) FROM led)       AS n_ledger,
    (SELECT count(*) FROM mf)        AS n_files
)

-- ===========================================================================
-- OUTPUT
-- ===========================================================================
SELECT ord, severity, check_name, detail FROM (

  -- ---- verdict -------------------------------------------------------------
  SELECT 0 AS ord,
         CASE WHEN t.n_drift > 0 OR t.n_mismatch > 0 THEN 'DRIFT'
              WHEN t.n_countdiff > 0
                OR t.n_unledgered_unknown > 0        THEN 'INVESTIGATE'
              ELSE 'CLEAN' END AS severity,
         'VERDICT' AS check_name,
         CASE WHEN t.n_drift > 0 OR t.n_mismatch > 0
              THEN t.n_drift || ' migration(s) applied with no file in this repo, '
                   || t.n_mismatch || ' name mismatch(es). The repo is NOT the source of truth right now.'
              WHEN t.n_countdiff > 0 OR t.n_unledgered_unknown > 0
              THEN 'Ledger and repo agree on everything the ledger can see. '
                   || t.n_unledgered_unknown || ' file(s) have no ledger row and no APPLIED note (Section E2); '
                   || t.n_countdiff || ' schema(s) differ from the baseline routine count (Section D).'
              ELSE 'Every applied migration is accounted for. Repo is the source of truth.'
         END AS detail
  FROM tally t

  UNION ALL
  SELECT 1, 'INFO', 'SCOPE',
         'Ledger rows: ' || t.n_ledger || '. Baseline covers everything up to version '
         || (SELECT baseline_through FROM cut) || ' (' || (SELECT baseline_rows FROM cut)
         || ' rows). Migration files in repo: ' || t.n_files
         || '. Files written but not yet applied: ' || t.n_unapplied
         || '. Files with no ledger row at all: ' || t.n_unledgered_applied || ' applied, '
         || t.n_unledgered_unknown || ' unverified (Section E).'
  FROM tally t

  -- ---- A. drift ------------------------------------------------------------
  UNION ALL
  SELECT 10, 'CRITICAL', 'A. IN DATABASE, NOT IN REPO',
         d.version || '  ' || COALESCE(d.name, '(unnamed)')
         || '   -> write db/migrations/NNNN_' || COALESCE(d.name, 'unnamed') || '.sql TODAY'
  FROM drift d

  UNION ALL
  SELECT 11, 'OK', 'A. IN DATABASE, NOT IN REPO',
         'none — nothing has been applied past the baseline without a file'
  FROM tally t WHERE t.n_drift = 0

  -- ---- B. pending ----------------------------------------------------------
  UNION ALL
  SELECT 20, 'WARN', 'B. IN REPO, NOT IN DATABASE',
         p.file || '  (claims version ' || p.version || ', name ' || COALESCE(p.name, '?') || ')'
         || '   -> either apply it, or fix its header if it was never applied'
  FROM pending p

  UNION ALL
  SELECT 21, 'OK', 'B. IN REPO, NOT IN DATABASE',
         'none — every committed migration file is applied'
  FROM tally t WHERE t.n_pending = 0

  UNION ALL
  SELECT 25, 'INFO', 'B2. WRITTEN, NOT YET APPLIED',
         u.file || '  (header says PENDING — expected while the change is in flight)'
  FROM unapplied u

  -- ---- C. mismatch ---------------------------------------------------------
  UNION ALL
  SELECT 30, 'CRITICAL', 'C. NAME MISMATCH',
         m.version || '  file says "' || COALESCE(m.file_says, '?')
         || '", database says "' || COALESCE(m.db_says, '?') || '"  (' || m.file || ')'
  FROM mismatch m

  UNION ALL
  SELECT 31, 'OK', 'C. NAME MISMATCH',
         'none — file names and ledger names agree'
  FROM tally t WHERE t.n_mismatch = 0

  -- ---- E. no ledger row at all ---------------------------------------------
  -- These cannot appear in A, B or C: there is no version to join on. They are
  -- reported so the gap stays visible instead of becoming the normal state.
  UNION ALL
  SELECT 34, 'WARN', 'E. APPLIED WITH NO LEDGER ROW',
         e.file || '  (its own APPLIED footer is the only record — applied through a path '
         || 'that writes no supabase_migrations row)'
  FROM unledgered e WHERE e.version = 'APPLIED-NO-LEDGER-ROW'

  UNION ALL
  SELECT 35, 'CRITICAL', 'E2. LIVE STATE UNKNOWN',
         e.file || '  (no ledger row AND no APPLIED note in the file — nothing anywhere '
         || 'records whether this is in the database)'
  FROM unledgered e WHERE e.version = 'UNVERIFIED-NO-LEDGER-ROW'

  UNION ALL
  SELECT 36, 'OK', 'E. APPLIED WITH NO LEDGER ROW',
         'none — every file either carries a real ledger version or is honestly PENDING'
  FROM tally t WHERE t.n_unledgered_applied = 0 AND t.n_unledgered_unknown = 0

  -- ---- D. counts backstop --------------------------------------------------
  UNION ALL
  SELECT 40,
         CASE WHEN c.live_n = c.baseline_n THEN 'OK' ELSE 'INVESTIGATE' END,
         'D. ROUTINE COUNT vs BASELINE',
         'schema ' || rpad(c.sch, 7) || ' baseline ' || c.baseline_n
         || ', live ' || c.live_n
         || CASE WHEN c.live_n = c.baseline_n THEN '  (match)'
                 ELSE '  (differs by ' || (c.live_n - c.baseline_n)
                      || ' — expected if a migration added/removed routines; '
                      || 'if Sections A and B are clean, this means the brain was '
                      || 'edited OUTSIDE the migration path)' END
  FROM counts c

) AS report
ORDER BY ord, detail;
