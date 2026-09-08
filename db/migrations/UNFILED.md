# Migrations applied to the engine with no file in this repo

Enumerated 2026-09-08, the day `scripts/check-drift.sql`'s Section A became able
to fire for the first time (see task G18). APPLYING.md's first line is *"if it
isn't a committed file, it didn't happen."* These happened.

## What this is

`supabase_migrations.schema_migrations` records every migration applied through
`apply_migration`, **including the SQL it was given**. Cross-referencing that
ledger against `db/migrations/` finds 83 applied migrations past the drift
check's baseline with no file. Of those:

| | count | disposition |
|---|---|---|
| split applications — one file, several ledger rows | 14 | not a gap; `0045a..e`, `0050a..e`, `0051a/b`, `0052a/b` have files under the parent number |
| recovered on 2026-09-08 | 2 | `0110b`, `0121b` — restored verbatim, byte counts confirmed against the ledger |
| **listed below — no file, never had one** | **67** | **open** |

All 67 are from **2026-08-10 to 2026-08-16**: the arm / tether / demate / charge-target
period. They total **734,007 characters** of SQL, averaging 11 KB and peaking at
82 KB (`a_tethered_vehicle_is_not_an_indepot_move_candidate`). (The whole
2026-08-08 → 2026-08-19 ledger window is 73 rows and 985,619 characters; the six
that do have files — `0018`–`0023` — account for the difference.)

## Why they are not recovered here

They are recoverable — the ledger holds the exact statements, and that is how
`0110b` and `0121b` were restored. Two reasons this file enumerates them instead:

1. **Most are long dead.** `0110b` showed the shape: it is an `ottoq_determinism_pair`
   body superseded by eleven later migrations, and re-running it today would
   silently undo all eleven. The same is almost certainly true of most of the 67 —
   the arm and charge-target logic has been rewritten many times since. Recovering
   them adds ~1 MB of SQL that must never be executed, each needing its own
   DO-NOT-RE-RUN banner.
2. **It is a judgement about the repo, not a defect to fix quietly.** Whether a
   megabyte of historical bodies belongs in `db/migrations/` is Chase's call. The
   engineering value is in *knowing the gap exists and how large it is*, which is
   what this file is for.

What is NOT in question: for this window the repo is **not** the source of truth
for the engine, and no amount of reading `db/migrations/` will tell you what
happened between 08-10 and 08-16.

## How to recover any one of them

```sql
SELECT array_to_string(statements, E'\n')
  FROM supabase_migrations.schema_migrations
 WHERE version = '<version>';
```

Write it to `db/migrations/NNNN_<name>.sql` with a `-- migration-version:` header
carrying that version, a `RECOVERED <date>, not authored then` banner, and — if
the object it touches has been replaced since — a **DO NOT RE-RUN** notice naming
what would be undone. Confirm the recovery is verbatim by comparing character
counts against the `length()` in the table below, the check used for `0110b`
(4,277) and `0121b` (1,157).

## The 67

| version | bytes | name |
|---|---|---|
| `20260810194053` | 6,173 | a_mated_vehicle_cannot_move |
| `20260810200742` | 16,775 | a_mated_vehicle_keeps_the_plug_until_the_robot_demates |
| `20260810200757` | 8,045 | a_tethered_vehicle_is_not_a_dispatch_candidate |
| `20260810200847` | 82,210 | a_tethered_vehicle_is_not_an_indepot_move_candidate |
| `20260810200916` | 9,172 | a_finished_demate_frees_the_plug_every_tick |
| `20260810200917` | 11,436 | the_cockpit_can_see_a_live_tether |
| `20260810201054` | 4,376 | the_world_tick_can_confirm_a_stall_command |
| `20260810201358` | 4,919 | the_command_confirm_seam_is_a_total_function |
| `20260810202758` | 2,694 | the_tether_sweep_actually_frees_the_stall |
| `20260810213646` | 26,417 | the_indepot_gate_protects_work_in_progress_not_every_release |
| `20260810215137` | 8,773 | a_confirmed_command_changes_the_vehicle_not_just_the_stall |
| `20260810220553` | 9,637 | soc_is_derived_from_cumulative_energy_not_incremented |
| `20260810222915` | 18,377 | deployed_vehicles_actually_discharge |
| `20260810223547` | 11,281 | the_demate_window_is_one_named_knob |
| `20260810224258` | 5,105 | the_global_policy_tier_is_reachable |
| `20260811031512` | 2,970 | continuous_playback_ceiling_is_eight_x |
| `20260811033531` | 11,838 | a_bad_command_cannot_abort_the_world_tick |
| `20260811035357` | 4,410 | the_depot_starts_with_real_fast_charge_demand |
| `20260811124543` | 3,473 | demo_start_honours_the_eight_x_ceiling |
| `20260811140510` | 9,302 | deploy_release_per_tick_budget_scales_with_tick_length |
| `20260811140716` | 9,225 | deploy_plan_call_passes_actual_tick_minutes |
| `20260811182857` | 14,667 | twin_snapshot_publish_open_visit_needs |
| `20260811184244` | 20,863 | the_depot_is_158_stalls_in_both_worlds |
| `20260811190550` | 1,836 | a_layout_backup_is_not_public_property |
| `20260812002735` | 3,679 | charging_must_never_lower_a_battery |
| `20260812183708` | 7,548 | the_browser_key_cannot_write_the_world |
| `20260812193637` | 15,413 | arm_motion_timings_have_exactly_one_home |
| `20260812195141` | 38,464 | the_arm_holds_the_car_from_approach_until_clear |
| `20260812200007` | 31,697 | the_arm_only_latches_when_it_actually_found_the_inlet |
| `20260812202754` | 13,321 | a_mate_cycle_is_never_lost_to_the_demate_behind_it |
| `20260812205753` | 10,923 | the_perimeter_is_a_long_hold_not_a_front_door |
| `20260812220135` | 8,893 | a_stall_reserved_for_a_vehicle_says_which_vehicle |
| `20260812221202` | 8,080 | every_stall_knows_how_far_it_is_from_the_gate |
| `20260812221324` | 7,558 | the_hold_ladder_has_no_unreachable_rung |
| `20260812225121` | 8,957 | a_charge_session_cannot_meter_energy_the_battery_did_not_take |
| `20260812225413` | 12,333 | a_run_only_advances_its_own_charge_sessions |
| `20260812225555` | 8,991 | a_finished_run_lets_go_of_its_cars |
| `20260813005932` | 15,719 | an_arm_fault_has_a_sanctioned_way_to_let_go |
| `20260813010244` | 12,309 | the_twins_own_movers_ask_the_arm_before_they_move_a_car |
| `20260813013102` | 12,074 | a_tethered_car_cannot_be_moved_by_anything_that_did_not_ask |
| `20260813014140` | 10,593 | the_arm_does_not_reach_for_a_car_that_needs_nothing |
| `20260813015215` | 10,035 | a_charger_fault_releases_the_arm_through_the_front_door |
| `20260813015414` | 9,095 | routine_movers_refuse_a_held_car_and_fault_recovery_unplugs_it |
| `20260813015624` | 7,581 | the_run_length_ceiling_has_exactly_one_home |
| `20260813023922` | 11,220 | a_satisfied_charge_need_is_a_done_need |
| `20260813025257` | 7,857 | a_full_charge_is_one_hundred_percent_and_has_one_home |
| `20260813025513` | 7,280 | no_target_soc_fallback_survives_anywhere |
| `20260813025623` | 8,265 | a_car_below_ninety_in_the_depot_gets_topped_off |
| `20260813031054` | 4,815 | the_deploy_floor_is_not_the_topoff_trigger |
| `20260813040822` | 9,693 | a_fast_plug_stops_at_ninety_by_day |
| `20260813040908` | 6,126 | a_run_starts_with_cars_in_the_world |
| `20260813041011` | 3,439 | a_run_can_outlast_a_full_charge |
| `20260813125109` | 8,210 | a_demating_car_keeps_its_stall_until_the_arm_lets_go |
| `20260813131333` | 10,015 | a_stalled_run_does_not_look_alive |
| `20260813132943` | 4,182 | a_charge_target_is_fixed_when_the_plug_goes_in |
| `20260813133041` | 9,374 | the_fast_plug_target_comes_from_policy_not_a_literal |
| `20260813143236` | 9,533 | night_waves_run_from_eleven_to_six_emptiest_first |
| `20260813143355` | 9,201 | a_fast_plug_is_always_first_choice_and_l2_is_overflow |
| `20260813153633` | 8,163 | a_swallowed_tick_failure_is_still_recorded |
| `20260813202521` | 9,048 | the_site_geometry_contract_has_one_home |
| `20260813205501` | 7,221 | the_geometry_contract_says_which_numbers_are_drawable |
| `20260814131003` | 8,233 | a_reissued_command_does_not_supersede_itself |
| `20260814131251` | 7,606 | only_one_run_moves_the_world_at_a_time |
| `20260815030126` | 7,646 | the_contract_says_how_to_animate_a_vehicle |
| `20260815220148` | 6,757 | a_real_robot_reports_across_the_same_seam |
| `20260815222925` | 1,660 | the_robovac_dock_counts_as_a_charger |
| `20260816034545` | 11,226 | a_cockpit_can_recall_a_vehicle_and_set_its_reserve |

**67 migrations, 734,007 characters.** Counts read from the ledger on 2026-09-08;
re-read them before trusting any recovery, per the rule in `db/checks/0098`.
