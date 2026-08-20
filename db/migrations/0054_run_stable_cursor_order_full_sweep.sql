-- migration-version: 20260820040000
-- migration-name:    run_stable_cursor_order_full_sweep
-- 0054 — C7 FOLLOW-UP #8, found by re-certification #8 (post-0053 arms
-- c1389c7b vs 5d986813: 1/20 identical, first divergence sim-min 60). The
-- tick-2 frame diff: 9 vehicles swapped between charge_complete_holding and
-- staged_for_departure with every SoC paired — a capacity-limited promotion
-- picking WHICH finished vehicles to advance in heap order. 0053's cleaner
-- world (no stale charge plans staggering completions) exposed it two ticks
-- in: many vehicles now finish charging simultaneously, so tie-heavy cursor
-- order decides who advances. The proximate offender is
-- twin.ottoq_sim_wash_triage (cursor over charge_complete_holding, no ORDER
-- BY); the full sweep found 21 unordered per-tick cursor sites across 16
-- functions that 0050's twin-only pass did not cover — including the decide
-- path itself (2.5 names determinism under fixed seed a kernel requirement).
--
-- MECHANISM. Unlike 0050 (full pasted bodies), this migration patches each
-- function IN PLACE, server-side: for every site it (1) asserts the
-- function's CURRENT md5(pg_get_functiondef) equals the pinned pre-image
-- (below), (2) asserts the anchor text occurs EXACTLY once, (3) applies the
-- single-site replace and EXECUTEs the result. Any mismatch raises and the
-- whole transaction rolls back — nothing partial, no transcription drift by
-- construction. Every insertion is an ORDER BY on run-stable identity keys
-- (vehicle.id / stall.id / bess_id / select-position), never per-run-random
-- UUIDs (dispatch/session/booking/itinerary ids) and never real-clock
-- columns; for LIMIT cursors the ORDER BY lands before the LIMIT, so the
-- selected subset becomes stable too. Scheduling semantics are unchanged —
-- these cursors' orders were previously ARBITRARY (heap order); they are now
-- the same arbitrary choice made stably.
--
-- SKIPPED (documented): public.ottoq_check_fence_containment — read-only
-- geometry audit, not on the tick path, order affects report row order only.
--
-- Pre-image md5 pins (also asserted at apply time):
--   ottoq.ottoq_place_unplaced_vehicles  764f70ef6480f7f8dcdfd2e317c031a9
--   ottoq.ottoq_plan_opportunistic_charges  b5936fdd10d298e8cdeefe2101ebb2c1
--   ottoq.ottoq_release_vacated_spaces  b44ad5c1cb650c7981a8d721940625fc
--   ottoq.ottoq_reoptimize_reservation_book  2f4be5960e01934fbee23ca048efbc83
--   ottoq.ottoq_sim_prearrival_contracts  b2d6c2f7f6b269dab435f93e3eb3c61d
--   public.ottoq_comms_advance  76fa6fb0118204993d76ad60738e5a62
--   public.ottoq_decide_tick  1cc0353849b690d2de8a21756bf03a66
--   public.ottoq_forecast_net_load  903370a9d53f142bdb37fcb83ba64058
--   twin.ottoq_report_charger_fault  d63b11857ba3147a8d46b510653e88be
--   twin.ottoq_sim_advance_flow_contract  856808181e3d743f1492398b7d9a1fda
--   twin.ottoq_sim_advance_visit_atoms  a4510f8211d68f2428f1a3aa7c224b11
--   twin.ottoq_sim_generate_arrival_manifests  711c9e7f46d7b0efdbcbef54fe0f2205
--   twin.ottoq_sim_materialize_schedule  ee6d0fdbf76f4b7d65cc039c6fba6fb3
--   twin.ottoq_sim_overnight_service_drain  0a89e2651487ae3a5ed8f1d22255a576
--   twin.ottoq_sim_reconcile_charge_sessions  828051a73ef0e13fcc2097cc26225a09
--   twin.ottoq_sim_wash_triage  856d3133b79a11eb1902d15a70d76474

DO $do$
DECLARE
  p RECORD; v_oid oid; v_src text; v_cnt int; v_done jsonb := '{}'::jsonb;
BEGIN
  FOR p IN
    SELECT * FROM (VALUES
    ('twin','ottoq_sim_wash_triage','856d3133b79a11eb1902d15a70d76474',$anchor$SELECT id, config FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND current_state = 'charge_complete_holding'$anchor$,$anchor$SELECT id, config FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND current_state = 'charge_complete_holding'
     ORDER BY id   -- 0054: run-stable cursor order (fleet identity, never heap order)$anchor$),
    ('twin','ottoq_sim_materialize_schedule','ee6d0fdbf76f4b7d65cc039c6fba6fb3',$anchor$AND v.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','service_complete_holding',
                               'staged_awaiting_service','staged_for_departure')$anchor$,$anchor$AND v.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','service_complete_holding',
                               'staged_awaiting_service','staged_for_departure')
     ORDER BY v.id   -- 0054: run-stable cursor order$anchor$),
    ('twin','ottoq_sim_generate_arrival_manifests','711c9e7f46d7b0efdbcbef54fe0f2205',$anchor$AND current_state = 'arrived_at_gate'
       AND NOT (COALESCE(config,'{}'::jsonb) ? 'service_manifest')$anchor$,$anchor$AND current_state = 'arrived_at_gate'
       AND NOT (COALESCE(config,'{}'::jsonb) ? 'service_manifest')
     ORDER BY id   -- 0054: run-stable cursor order$anchor$),
    ('twin','ottoq_sim_overnight_service_drain','0a89e2651487ae3a5ed8f1d22255a576',$anchor$AND config->>'svc_step' = 'overnight_draining'
       AND (config->>'service_ends_at') IS NOT NULL
       AND (config->>'service_ends_at')::timestamptz <= p_sim_clock$anchor$,$anchor$AND config->>'svc_step' = 'overnight_draining'
       AND (config->>'service_ends_at') IS NOT NULL
       AND (config->>'service_ends_at')::timestamptz <= p_sim_clock
     ORDER BY id   -- 0054: run-stable cursor order$anchor$),
    ('twin','ottoq_sim_reconcile_charge_sessions','828051a73ef0e13fcc2097cc26225a09',$anchor$AND NOT EXISTS (SELECT 1 FROM ocpp_sessions s
                        WHERE s.vehicle_id = v.id AND s.status = 'active' AND s.id_token LIKE 'TWIN-%')$anchor$,$anchor$AND NOT EXISTS (SELECT 1 FROM ocpp_sessions s
                        WHERE s.vehicle_id = v.id AND s.status = 'active' AND s.id_token LIKE 'TWIN-%')
     ORDER BY v.id   -- 0054: run-stable cursor order$anchor$),
    ('twin','ottoq_sim_advance_visit_atoms','a4510f8211d68f2428f1a3aa7c224b11',$anchor$OR (v.current_state = 'staged_for_departure'
             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                          WHERE a->>'svc' = 'readiness_check' AND COALESCE(a->>'status','pending') = 'pending')))$anchor$,$anchor$OR (v.current_state = 'staged_for_departure'
             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                          WHERE a->>'svc' = 'readiness_check' AND COALESCE(a->>'status','pending') = 'pending')))
     ORDER BY vn.vehicle_id   -- 0054: run-stable cursor order$anchor$),
    ('twin','ottoq_sim_advance_flow_contract','856808181e3d743f1492398b7d9a1fda',$anchor$AND NOT EXISTS (SELECT 1 FROM ottoq_itinerary_legs l2
                        WHERE l2.itinerary_id = l.itinerary_id AND l2.status = 'active')
     GROUP BY 1, 2$anchor$,$anchor$AND NOT EXISTS (SELECT 1 FROM ottoq_itinerary_legs l2
                        WHERE l2.itinerary_id = l.itinerary_id AND l2.status = 'active')
     GROUP BY 1, 2
     ORDER BY 2, 3   -- 0054: vehicle identity then earliest late leg, never per-run itinerary UUIDs$anchor$),
    ('twin','ottoq_sim_advance_flow_contract','856808181e3d743f1492398b7d9a1fda',$anchor$AND v.current_state NOT IN ('charging_dcfc','charging_l2')
       AND v.current_soc >= COALESCE((a->>'target_soc')::numeric, public.ottoq_default_target_soc()) - 2$anchor$,$anchor$AND v.current_state NOT IN ('charging_dcfc','charging_l2')
       AND v.current_soc >= COALESCE((a->>'target_soc')::numeric, public.ottoq_default_target_soc()) - 2
     ORDER BY 1   -- 0054: run-stable cursor order$anchor$),
    ('twin','ottoq_report_charger_fault','d63b11857ba3147a8d46b510653e88be',$anchor$FROM stalls s WHERE s.ocpp_charger_id = p_charger_id$anchor$,$anchor$FROM stalls s WHERE s.ocpp_charger_id = p_charger_id
     ORDER BY s.id   -- 0054: run-stable cursor order$anchor$),
    ('twin','ottoq_report_charger_fault','d63b11857ba3147a8d46b510653e88be',$anchor$SELECT v.* FROM vehicles v
       WHERE v.id IN (v_stall.current_vehicle_id, v_stall.reserved_by) AND v.id IS NOT NULL$anchor$,$anchor$SELECT v.* FROM vehicles v
       WHERE v.id IN (v_stall.current_vehicle_id, v_stall.reserved_by) AND v.id IS NOT NULL
       ORDER BY v.id   -- 0054: run-stable cursor order$anchor$),
    ('ottoq','ottoq_place_unplaced_vehicles','764f70ef6480f7f8dcdfd2e317c031a9',$anchor$AND v.home_depot_id = p_depot_id
     LIMIT GREATEST(p_max, 1)$anchor$,$anchor$AND v.home_depot_id = p_depot_id
     ORDER BY 1   -- 0054: run-stable order before LIMIT
     LIMIT GREATEST(p_max, 1)$anchor$),
    ('ottoq','ottoq_plan_opportunistic_charges','b5936fdd10d298e8cdeefe2101ebb2c1',$anchor$LIMIT GREATEST(0, v_free_chargers - v_gate_needy)$anchor$,$anchor$ORDER BY vn.vehicle_id   -- 0054: run-stable order before LIMIT
       LIMIT GREATEST(0, v_free_chargers - v_gate_needy)$anchor$),
    ('ottoq','ottoq_release_vacated_spaces','b44ad5c1cb650c7981a8d721940625fc',$anchor$SELECT * FROM upd WHERE new_state = 'interrupted'$anchor$,$anchor$SELECT * FROM upd WHERE new_state = 'interrupted' ORDER BY vehicle_id, stall_id   -- 0054: run-stable order (never per-run booking UUIDs)$anchor$),
    ('ottoq','ottoq_reoptimize_reservation_book','2f4be5960e01934fbee23ca048efbc83',$anchor$AND s.stall_type::text <> 'dcfc'
     LIMIT 10$anchor$,$anchor$AND s.stall_type::text <> 'dcfc'
     ORDER BY v.id   -- 0054: run-stable order before LIMIT
     LIMIT 10$anchor$),
    ('ottoq','ottoq_sim_prearrival_contracts','b2d6c2f7f6b269dab435f93e3eb3c61d',$anchor$AND NOT EXISTS (SELECT 1 FROM stalls s WHERE s.reserved_by = v.id
                         AND s.reservation_expires_at > p_clock)
     LIMIT 40$anchor$,$anchor$AND NOT EXISTS (SELECT 1 FROM stalls s WHERE s.reserved_by = v.id
                         AND s.reservation_expires_at > p_clock)
     ORDER BY v.id   -- 0054: run-stable order before LIMIT
     LIMIT 40$anchor$),
    ('ottoq','ottoq_sim_prearrival_contracts','b2d6c2f7f6b269dab435f93e3eb3c61d',$anchor$AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                        WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress'))
     LIMIT 40$anchor$,$anchor$AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                        WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress'))
     ORDER BY v.id   -- 0054: run-stable order before LIMIT
     LIMIT 40$anchor$),
    ('public','ottoq_comms_advance','76fa6fb0118204993d76ad60738e5a62',$anchor$FROM ottoq_vehicle_dispatches dp
     WHERE dp.sim_run_id = p_run AND dp.status IN ('active','returning')$anchor$,$anchor$FROM ottoq_vehicle_dispatches dp
     WHERE dp.sim_run_id = p_run AND dp.status IN ('active','returning')
     ORDER BY dp.vehicle_id   -- 0054: vehicle identity, never per-run dispatch UUIDs$anchor$),
    ('public','ottoq_decide_tick','1cc0353849b690d2de8a21756bf03a66',$anchor$AND v.current_state = 'arrived_at_gate'
       AND v.current_stall_id IS NULL
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                    WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') <> 'done'))$anchor$,$anchor$AND v.current_state = 'arrived_at_gate'
       AND v.current_stall_id IS NULL
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                    WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') <> 'done'))
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id   -- 0054: the sibling cursors' own fairness idiom, made explicit here too$anchor$),
    ('public','ottoq_decide_tick','1cc0353849b690d2de8a21756bf03a66',$anchor$SELECT bess_id, current_soc_pct FROM ottoq_bess_units WHERE depot_id = v_depot$anchor$,$anchor$SELECT bess_id, current_soc_pct FROM ottoq_bess_units WHERE depot_id = v_depot ORDER BY bess_id   -- 0054: run-stable cursor order$anchor$),
    ('public','ottoq_forecast_net_load','903370a9d53f142bdb37fcb83ba64058',$anchor$WHERE s.status='active' AND s.sim_run_id=p_sim_run_id$anchor$,$anchor$WHERE s.status='active' AND s.sim_run_id=p_sim_run_id
    ORDER BY st.id   -- 0054: stall identity, never per-run session UUIDs$anchor$),
    ('public','ottoq_forecast_net_load','903370a9d53f142bdb37fcb83ba64058',$anchor$AND d.scheduled_return_at >  p_sim_clock - interval '30 min'$anchor$,$anchor$AND d.scheduled_return_at >  p_sim_clock - interval '30 min'
      ORDER BY v.id   -- 0054: run-stable cursor order$anchor$)
    ) AS t(sch, fn, pre_md5, old, new)
  LOOP
    SELECT pr.oid INTO STRICT v_oid
      FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = p.sch AND pr.proname = p.fn;
    v_src := pg_get_functiondef(v_oid);
    -- pre-image pin: only the audited body may be patched. A function already
    -- patched by an EARLIER site in this same run is exempt from the pin (its
    -- md5 legitimately moved); the anchor-count check still protects it.
    IF NOT (v_done ? (p.sch || '.' || p.fn)) AND md5(v_src) <> p.pre_md5 THEN
      RAISE EXCEPTION '0054: %.% pre-image md5 % != pinned %', p.sch, p.fn, md5(v_src), p.pre_md5;
    END IF;
    v_cnt := (length(v_src) - length(replace(v_src, p.old, ''))) / length(p.old);
    IF v_cnt <> 1 THEN
      RAISE EXCEPTION '0054: %.% anchor occurs % times (need exactly 1): %', p.sch, p.fn, v_cnt, left(p.old, 80);
    END IF;
    EXECUTE replace(v_src, p.old, p.new);
    v_done := v_done || jsonb_build_object(p.sch || '.' || p.fn, true);
    RAISE NOTICE '0054 patched %.% -> md5 %', p.sch, p.fn,
      (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
        JOIN pg_namespace n ON n.oid = pr.pronamespace
       WHERE n.nspname = p.sch AND pr.proname = p.fn);
  END LOOP;
END
$do$;
