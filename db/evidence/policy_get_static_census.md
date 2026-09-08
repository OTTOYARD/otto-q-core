# `ottoq_policy_get`'s 64 callers — the full static census

**Captured 2026-09-08 17:01 UTC**, ahead of `r28_g` (18:25 UTC), so that the
per-caller division G21b needs is arithmetic at that point and not archaeology.

`db/checks/0139` Q6 ran this exact query but recorded only its top and a summary
("64 functions, 179 mentions, `ottoq_recall_naive_threshold_v1` leads with 16
and has no loop"). The rest was never written down. This is the whole thing.

## What it is for, and the trap it carries

`ottoq_policy_get` was called **13,217,464 times in one 24-tick pair**
(`db/checks/0141`). Which callers make those calls is **not established** — and
this table cannot establish it, which is the point 0139 spent a paragraph on:

> `ottoq_recall_naive_threshold_v1` leads on mentions (16) and has **no loop at
> all**; `ottoq_decide_tick` has 9 mentions and both a loop and a FOR-SELECT.
> **Mentions are not calls.**

So this file is the *denominator*, not the answer. The answer is `r28_g`'s
`pg_stat_user_functions` delta (`scripts/fn-delta.py` against
`db/evidence/r28_g_fn_baseline.md`), and this table is what each caller's
measured per-pair delta gets divided by. A caller with 1 mention and a large
delta is inside a hot loop; a caller with 16 mentions and a small delta is
`ottoq_recall_naive_threshold_v1`.

**Four wrong guesses were already spent on G19 by reasoning from static
structure.** This table is not to be used to name a caller on its own.

## The rows

Format: `schema|function|mentions|has_LOOP|has_FOR_SELECT`

```
public|ottoq_recall_naive_threshold_v1|16|0|0
twin|ottoq_arm_registration_check|13|0|0
public|ottoq_arm_timings|9|0|0
public|ottoq_decide_tick|9|1|1
twin|ottoq_sim_vehicle_exception_handler|7|1|1
public|ottoq_demo_metronome|6|1|1
twin|ottoq_sim_auto_dispatch_tick|6|1|1
twin|ottoq_sim_advance_service_flow|5|1|1
public|ottoq_energy_orchestrate|4|0|0
public|ottoq_indepot_reassignment_guard|4|0|0
ottoq|ottoq_plan_dispatch_tick|4|1|1
ottoq|ottoq_reconcile_bay_reservations|4|1|1
twin|ottoq_sim_advance_wear_counters|4|1|0
public|ottoq_site_geometry|4|0|0
public|ottoq_agent_board|3|0|0
public|ottoq_decide_indepot_approvals|3|1|1
public|ottoq_itin_travel_leg|3|0|0
ottoq|ottoq_readmit_reopened_needs|3|1|1
public|ottoq_run_boot_draw|3|1|1
public|ottoq_run_governor_auto_stop|3|1|1
ottoq|ottoq_stall_free_between|3|0|0
public|ottoq_target_soc_cap|3|0|0
public|ottoq_apply_ops_action|2|0|0
twin|ottoq_arm_advance_cycles|2|1|1
ottoq|ottoq_bind_unbooked_bay_occupants|2|1|1
ottoq|ottoq_book_stall|2|0|0
public|ottoq_cil_propose|2|0|0
public|ottoq_cron_tick|2|0|0
public|ottoq_cuopt_refresh|2|0|0
public|ottoq_is_depot_night|2|0|0
ottoq|ottoq_observe_asset|2|0|0
public|ottoq_recall_fixed_window_dummy|2|0|0
ottoq|ottoq_release_vacated_spaces|2|1|0
ottoq|ottoq_reserve_inbound_bays|2|0|0
public|ottoq_scenario_apply_fleet_overrides|2|1|1
twin|ottoq_sim_bay_fault_handler|2|1|1
public|ottoq_sim_decide_and_dispatch|2|0|0
twin|ottoq_sim_prime_deployment|2|1|1
twin|ottoq_sim_start_run|2|0|0
public|ottoq_work_side_accepts|2|0|0
public|ottoq_charge_plan_for_visit|1|0|0
public|ottoq_cuopt_defer_hold|1|0|0
public|ottoq_cuopt_first_refusal_arm|1|0|0
public|ottoq_default_target_soc|1|0|0
public|ottoq_evaluate_return_need|1|0|0
public|ottoq_hw_set_return_threshold|1|0|0
public|ottoq_hw_vehicle_status|1|0|0
public|ottoq_l2_optimize_assignments|1|1|1
public|ottoq_l2_propose_service|1|0|0
public|ottoq_l2_propose_stall_assignment|1|0|0
public|ottoq_nl_status_brief|1|0|0
public|ottoq_ops_set_rush_valve|1|0|0
ottoq|ottoq_plan_overnight_drain_admissions|1|1|1
public|ottoq_plan_overnight_wave|1|1|1
public|ottoq_plan_visit_itinerary|1|1|1
public|ottoq_policy_set|1|0|0
ottoq|ottoq_readmit_resumed_visits|1|1|1
ottoq|ottoq_release_expired_bookings|1|1|1
public|ottoq_reopen_visit_atoms|1|1|1
public|ottoq_return_eta_minutes|1|0|0
public|ottoq_sim_advance_tick_world|1|0|0
ottoq|ottoq_stage_advance_approval|1|0|0
public|ottoq_topoff_threshold_soc|1|0|0
twin|ottoq_world_advance|1|0|0
```

## What is already legible without the delta

**25 of the 64 have a LOOP, and 23 of those also have a FOR-SELECT** — those are
the candidates. The other 39 have neither and can only contribute a bounded
number of calls per invocation, however many times they mention it.

(Those three counts were first written 24 / 22 / 40, from reading the table
rather than counting it, and corrected before this file was committed. The
totals that matter — 64 callers and 179 mentions — reproduce `0139` Q6 exactly.)

The three highest mention counts — `ottoq_recall_naive_threshold_v1` (16),
`twin.ottoq_arm_registration_check` (13), `ottoq_arm_timings` (9) — are **all
loop-free**, so the leaderboard by mentions and the leaderboard by calls almost
certainly disagree. That is the trap restated with names in it, and it is why
this file is a denominator.
