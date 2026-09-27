-- 0399  **The charge-target experiment's first pair after 0533 (G258): the arm reads its own value now, and says so.**
--
--       Written on 2026-09-27 (17:15-19:00 UTC, 12:15-2:00 PM CT) after 0533 was applied. Read-only.

-- ══ §1 THE PROBE PAIR ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0533 made `ottoq_target_soc_cap` read the run in scope. It also gave the ledger a read witness per arm. Pair 95
--   (0398 §1(a)) ran the same seed before the fix and moved nothing. This is that seed again, run by a one-shot cron
--   job (766, removing itself when done) at 12:15 PM CT. The dial runner stays off until tonight's window.
--   Three questions, in order:
--     - did each arm read its own value of the dial;
--     - did the arms differ;
--     - by how much on the primary.

\echo '=== 0399 §1(a) — the pair: valid, the same world, the witness, what moved ==='
SELECT p.pair_id, p.seed, p.ran_at, p.complete, p.world_identical, p.both_paid_shield,
       p.dial_read_a, p.dial_read_b, p.differs, p.moved, p.wall_s,
       p.metrics_a->'unmet_demand_car_hours' AS unmet_a, p.metrics_b->'unmet_demand_car_hours' AS unmet_b,
       p.metrics_a->'unmet_demand_pct' AS unmet_pct_a, p.metrics_b->'unmet_demand_pct' AS unmet_pct_b
  FROM public.ottoq_dial_pair_ledger p
 WHERE p.experiment_id = '08262943-e487-4a24-9ddb-0686737bcf98' ORDER BY p.pair_id;
-- READ (2026-09-27 17:32 UTC): NO ROW. The probe (cron 766, 17:15:00-17:31:42 UTC) caught an exception, logged it and
--   removed itself: `duplicate key value violates unique constraint "idx_stalls_one_vehicle_per_stall"`. A pair aborted by
--   an engine error wrote nothing to the ledger. The runner picks the first seed not yet paired, so it would have re-run
--   this seed every twenty minutes all night. That is 0535 (b): an arm's error is now recorded and the pair survives it.
--   The control arm (90) ran as pair 95's arms did; the error was in the treatment arm, the first ever to charge a
--   daytime DCFC to 85. §2 is what it hit.

\echo '=== 0399 §1(b) — the day''s scorecard, arm against arm ==='
SELECT k.key, p.metrics_a->k.key AS control_90, p.metrics_b->k.key AS treatment_85, p.delta->k.key AS delta
  FROM public.ottoq_dial_pair_ledger p,
       unnest(ARRAY['unmet_demand_car_hours','unmet_demand_pct','deployed_car_hours','peak_shortfall','trips_completed',
                    'charge_sessions','charge_wait_p50_min','charge_wait_p95_min','asset_hours_available_per_day',
                    'service_point_turns_per_point_per_day','peak_site_kw','energy_cost_usd','returns_unserved',
                    'safety_critical_refused','safety_critical_unprevented']) AS k(key)
 WHERE p.experiment_id = '08262943-e487-4a24-9ddb-0686737bcf98' AND p.ran_at >= public.ottoq_dial_pair_floor()
 ORDER BY p.pair_id, k.key;
-- READ: pending.

-- ══ §2 WHAT THE 85% ARM HIT: A TOP-OFF THAT MOVED A CAR OUT OF THE WASH BAY (G259) ═══════════════════════════════════
--
--   The treatment arm alone, replayed tick by tick in a rolled-back one-shot job (cron 767, 17:38-17:44 UTC). Each tick
--   was in its own subtransaction; on an error the job logged the message, the call stack and the car's state as it
--   stood before the failing tick.
--
-- READ (from the job's log lines, 2026-09-27 17:44:44 UTC):
--   - Tick 75 (sim 20:24 UTC, 3:24 PM CT) failed. Key (current_vehicle_id)=(02ff42a9-...) already exists: a Tesla,
--     svc_step `washing`, charge plan `dcfc` target 85 (reason `nmc_periodic_balance_charge`).
--   - The stack:
--       ottoq_sim_advance_tick -> ottoq_sim_advance_tick_world (line 56)
--       -> twin.ottoq_opportunistic_scan (line 73, `UPDATE vehicles SET current_stall_id = v_stall`)
--       -> sync_stall_occupancy (line 18, occupy the new stall).
--   - The car's last events, at the end of tick 74: demated from its DCFC (`current_stall_id` 9753cfd9 -> null,
--     tether cleared), then into the wash bay.
--   - What happened, from the scan's and the triggers' source:
--       1. an opportunistic-charge approval raised while the car sat at 84.5% after the capped session, below the
--          90% top-off threshold, was approved at tick 75;
--       2. the scan moved the car to a charger without asking where the car now was. The release of its other stall
--          was refused by `trg_reassignment_guard`, which will not vacate a bay mid-wash and says so by keeping the
--          pointer (`NEW.current_vehicle_id := OLD.current_vehicle_id`), not by raising;
--       3. the claim then met a car already in the wash bay.
--   - At the 90% cap a session ended at 89.5, a hair under the threshold, so the ask-to-verdict window almost never
--     held a car that had moved on. The defect is the engine's, not the experiment's. Fixed by 0535 (a): the top-off
--     is enacted only for a car still staged or holding; otherwise it expires as `vehicle_moved_on`.

\echo '=== 0399 §2 — top-off approvals that expired because the car had moved on (0535 onward) ==='
SELECT a.sim_run_id, a.payload->>'vehicle_state' AS found_in, count(*) AS expired_moved_on
  FROM public.ottoq_ops_approvals a
 WHERE a.approval_type = 'opportunistic_charge' AND a.payload->>'expired_reason' = 'vehicle_moved_on'
 GROUP BY 1, 2 ORDER BY 1, 3 DESC;
-- READ: pending (the next pair and the next operator run).
