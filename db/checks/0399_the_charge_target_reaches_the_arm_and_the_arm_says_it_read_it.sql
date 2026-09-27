-- 0399  **The charge-target experiment's first pair after 0533 (G258): the arm reads its own value now, and says so.**
--
--       Written on 2026-09-27 (17:15-19:10 UTC, 12:15-2:10 PM CT) after 0533 and 0535 were applied. Read-only.

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
-- READ (2026-09-27 19:06 UTC): after 0535, cron 768 (1:30 PM CT) ran the same seed again and wrote pair 102: complete,
--   valid and read by both arms. §1(b) reads it.

\echo '=== 0399 §1(b) — the day''s scorecard, arm against arm ==='
SELECT k.key, p.metrics_a->k.key AS control_90, p.metrics_b->k.key AS treatment_85, p.delta->k.key AS delta
  FROM public.ottoq_dial_pair_ledger p,
       unnest(ARRAY['unmet_demand_car_hours','unmet_demand_pct','deployed_car_hours','peak_shortfall','trips_completed',
                    'charge_sessions','charge_wait_p50_min','charge_wait_p95_min','asset_hours_available_per_day',
                    'service_point_turns_per_point_per_day','peak_site_kw','energy_cost_usd','returns_unserved',
                    'safety_critical_refused','safety_critical_unprevented']) AS k(key)
 WHERE p.experiment_id = '08262943-e487-4a24-9ddb-0686737bcf98' AND p.ran_at >= public.ottoq_dial_pair_floor()
 ORDER BY p.pair_id, k.key;
-- READ (2026-09-27 19:06 UTC): pair 102, cron 768 after 0535 (18:30:00-19:02:49 UTC, 1:30-2:02 PM CT), the same seed
--   as pair 95 (812326339305302355). The first pair of this experiment that both arms can be judged on:
--     - valid: complete, world_identical, both_paid_shield;
--     - **each arm read its own dial** (`dial_read_a` and `dial_read_b` true, 0533's witness);
--     - **the arms differ**: 11 atoms moved (endst, h_arr, h_bkg, h_cmd, h_dec, h_evt, h_nrg, h_prop, h_rcl, h_rule,
--       h_sdr), where pair 95 moved none;
--     - **no arm error** (0535): the 85% arm ran through tick 75, where cron 766's probe died, to the end.
--   The control arm reproduced pair 95 on the primary exactly (336.3 unmet car-hours, 76.4%), so what moved is the dial.
--
--     key                                       control 90   treatment 85      delta
--     unmet_demand_car_hours (primary, lower)        336.3          352.4      +16.1  (+4.8%, worse)
--     unmet_demand_pct                                76.4           80.1       +3.7
--     deployed_car_hours                             103.7           87.6      -16.1
--     trips_completed                                  206            188        -18
--     asset_hours_available_per_day (KPI 1)          141.10         120.59     -20.51  (-14.5%)
--     charge_sessions                                  180            209        +29
--     charge_wait_p50_min / p95_min                30 / 288    24 / 215.4    -6 / -72.6
--     returns_unserved                                  15              0        -15
--     service_point_turns_per_point_per_day (KPI 2)    4.40           5.06      +0.66
--     touch_events_per_turn (KPI 4)                   0.563          0.601     +0.038  (+6.7%)
--     peak_site_kw (KPI 3), peak_shortfall          1,251 / 50     1,251 / 50        0
--     energy_cost_usd / site_cost_usd_per_day     630.93 / 1,346.82   558.13 / 1,294.28   -72.80 / -52.54
--     safety_critical_refused / _unprevented          12 / 0          12 / 0          0
--     arm wall seconds                                 569.4        1,399.8     +830.4
--
--   **On this seed the charger freed at 85% was used, and it did not pay.** The queue shortened as G257 predicted: the
--   wait for a charger fell at the median and at p95, and no return went unserved (15 in the control). But every car
--   left with 5 points less charge and came back sooner: 29 more charge sessions, 18 fewer trips, 16.1 fewer deployed
--   car-hours -- exactly the rise in unmet demand. The taper tax (0398 §3) priced the charger-minutes above the floor and
--   not the driving those minutes buy. That is the challenger's Q1 claim meeting its paired test: Q1's hindsight grade is
--   local (this car charged on while the next car waited), and the pair measures the whole day. A local grade that
--   confirms what the day refutes is why a challenger question earns a proposer seat only through a paired experiment.
--   One seed is one observation; the first look needs six (tonight's window). The verdict reads `collecting`, 1 of 6.
--
--   Also measured, not the cause:
--     - the 85% arm raised **74 top-off approvals** against the control's 2: the top-off threshold is 90, above the
--       cap, so every capped car qualifies (G260). None was enacted (30 declined, 36 expired at the run's end, 8 as
--       `vehicle_moved_on` -- 0535 (a) working), so they do not explain the result;
--     - the 85% arm took **2.5x the control's wall time** (1,399.8 s against 569.4). Cause not established: the pair
--       runs in one transaction, so no row carries a per-tick wall time. At 33 minutes a pair, the runner's last start of
--       the night (10:40 UTC) can run to about 11:13 UTC, 6:13 AM CT, past the window's 10:41 close (G261).

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
