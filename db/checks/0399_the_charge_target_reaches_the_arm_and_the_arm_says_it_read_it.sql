-- 0399  **The charge-target experiment's first pair after 0533 (G258): the arm reads its own value now, and says so.**
--
--       Written on 2026-09-27 (17:15-18:00 UTC, 12:15-1:00 PM CT) after 0533 was applied. Read-only.

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
-- READ: pending (the pair runs about 20 minutes from 12:15 PM CT).

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
