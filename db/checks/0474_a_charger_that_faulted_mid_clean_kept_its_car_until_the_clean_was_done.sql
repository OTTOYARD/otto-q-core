-- 0474  **Run 8c0b2e04: two chargers that faulted while their cleaning arm was in the cabin kept the car on the dead
--        post until the 5.8-minute clean was done (309 and 339 s); no booking, car or session was ever sent to a
--        faulted charger.**
--        -> G506 (new; fixed by migration 0792 and ottoyarddepot-sim's armSessionInput, the same evening).
--        Chase, 2026-11-02, from the twin (a post with its fault beacon and red bay-closed marks, a car in it, the charge
--        arm in the car's port): "Looks like a faulted charger station was given a vehicle to charge/clean. Major issue.
--        resolve that".
--        Run 8c0b2e04-8ea9-49a8-bfed-bed10ddfbc8b: busy_day at the twin depot (rule 8), started 2026-11-03 03:37:10 UTC
--        (9:37 PM CT on 2026-11-02) by operator_demo, stopped by the operator at 03:47:13 UTC (9:47 PM CT), 129 ticks,
--        sim 14:03:27 to 14:29:58. Read against gxdrcyphqjzjsuhxuqtg, read-only, between 03:59:22 and 04:10:36 UTC
--        (9:59 and 10:10 PM CT), after the run had stopped. Sim times below are as stored (UTC). One run: single
--        readings, not ranges. The run's rows are engine-class and the next demo run's start purges them.
--
-- ══ §1 SIX CHARGERS FAULTED; TWO OF THEIR CARS WERE HELD BY THE CLEAN (reproduce: (1)) ═══════════════════════════════
--
--     post      car       fault (sim)  reason                  arm clean on that post at the fault   car left   held
--     DCFC-22   2cd2cbf3  14:04:15     thermal_emergency       14:03:53-14:09:41, credited done        14:09:54   339.1 s
--     DCFC-02   ca2624fc  14:04:45     session_aborted_other   14:03:53-14:09:41, credited done        14:09:54   309.2 s
--     DCFC-18   c3333333  14:06:32     connector_cable         none                                    14:06:43    11.7 s
--     DCFC-11   b2222222  14:09:00     communication_dropout   cancelled (left_the_cabin_robot at      14:09:00     0.0 s
--                                                               14:09:54), redone at DCFC-29 14:10:04
--     DCFC-29   5ea53696  14:24:39     session_aborted_other   none                                    14:24:39     0.0 s
--     DCFC-13   a1111111  14:27:36     connector_cable         none                                    14:27:36     0.0 s
--
--   (The 8-character ids a1111111, b2222222 and c3333333 are prefixes several cars share; the rows above are the cars of
--   the faulted sessions, by full id.) The two held cars were cleaned, credited, on a charger that had been out of
--   service for five minutes, and their cabin clean was the only reason they stayed.
--
-- ══ §2 WHY TWO PATHS: THE RE-QUEUE THRESHOLD, THEN 0760'S HOLD (reproduce: (2)) ═══════════════════════════════════════
--
--   twin.ottoq_sim_stop_charge_session (prosrc md5 877cf0bf) re-queues a faulted car at once only when it is more than 5
--   points under its target (`v_requeue`). A car within 5 points takes the robot's demate tether (11.5 s,
--   robotic_demate_seconds) and leaves when public.ottoq_release_expired_tethers (md5 bad69ddf) releases it. 0760's
--   predicate in that sweep keeps an expired demate tether while the stall's cleaning arm is at work, whatever ended the
--   charge. 2cd2cbf3 and ca2624fc were within 5 points (ca2624fc arrived at 95%), so the sweep waited for the clean.
--   Their bookings were released at the end of the demate window (`charge_session_faulted`, 14:04:26.98 and
--   14:04:56.89), so for five minutes the calendar called each post free while the car's pointer still stood in it.
--
-- ══ §3 NOTHING SENT A CAR TO A FAULTED CHARGER (reproduce: (3)) ══════════════════════════════════════════════════════
--
--   In each fault window (the fault to the charger's next session, or the run's stop): 0 sessions started, and no booking
--   for another car began before the drawn repair ended. DCFC-02 (repair 16 min, back 14:20:45) was next booked at
--   14:21:10; DCFC-11 (repair 14 min, back 14:23:00) at 14:23:14. As 0612 measured on fd6ed035: 0372's candidate source,
--   HW.002 and twin.ottoq_sim_recover_chargers hold.
--
-- ══ §4 WHAT THE TWIN DREW ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   The snapshot reported the post 'faulted' (0612) with the car still on it and the demate tether running. The renderer
--   kept the connector in the car's port: roboticService.armSessionInput holds a latched connector while the stall's
--   cleaning arm is not home, "whatever the charge or the tether says" (Chase's order for a charge that ENDS, 2026-10-19).
--   So the picture was a faulted post serving its car for five minutes.
--
-- ══ §5 GAPS FOUND ON THE WAY (recorded; not fixed by 0792) ═══════════════════════════════════════════════════════════
--
--   (a) The OCPP frames say a faulted charger is Available. Each of the run's 41 session ends (35 completed, 6 faulted)
--       sent TransactionEvent Ended and a StatusNotification, and on all 6 faults that StatusNotification reads
--       connectorStatus 'Available' (the stop step writes it unconditionally); a real 2.0.1 station sends 'Faulted', and
--       a charger back end reading this stream would offer the post. Nothing is sent when a repair ends. All 82 closing
--       frames carry no charger id (charger_id NULL), the half that 0723 (PENDING, not applied) fixes; reproduce (4)
--       joins through the session for that reason. The twin's fault and repair are right in ottoq_ocpp_chargers.
--   (b) The re-queue threshold `target - 5` predates rule 9's 100% (0539): a car whose charge a fault cut at 96% is not
--       re-queued at the fault. 0543's departure test and recheck send it back to a charger later (both held cars charged
--       again, at DCFC-26 from 14:18:54 and DCFC-27 from 14:14:45), so rule 9 holds, a few minutes late.
--   (c) Between the sweep's release and the arm's own exit the engine does not hold the car for the arm (0758's hold asks
--       about the stall the car stands on). The renderer's clean gate covers the drawn car (bounded 30 s); a real depot
--       needs the robot's clear signal for that window.
--
-- ══ REPRODUCE ═════════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) every faulted session: the arm's clean on that post at the fault, and when the car left the post
WITH r AS (SELECT '8c0b2e04-8ea9-49a8-bfed-bed10ddfbc8b'::uuid AS run),
fs AS (
  SELECT os.id AS session_id, os.vehicle_id, os.stall_id, s.stall_code, os.ended_at AS fault_at, os.stopped_reason
  FROM public.ocpp_sessions os JOIN public.stalls s ON s.id = os.stall_id, r
  WHERE os.sim_run_id = r.run AND os.status = 'faulted'
),
clean AS (
  SELECT fs.session_id, a->>'status' AS clean_status, (a->>'started_at')::timestamptz AS c_start,
         (a->>'ends_at')::timestamptz AS c_end
  FROM fs JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = fs.vehicle_id, r
  CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(vn.atoms) = 'array' THEN vn.atoms ELSE '[]' END) a
  WHERE vn.sim_run_id = r.run AND a->>'performed_by' = 'stall_cabin_robot' AND a->>'robot_stall_id' = fs.stall_id::text
    AND (a->>'started_at')::timestamptz <= fs.fault_at
    AND COALESCE((a->>'done_at')::timestamptz, (a->>'ends_at')::timestamptz) >= fs.fault_at
),
left_post AS (
  SELECT fs.session_id, min(e.sim_clock_at) AS left_at
  FROM fs JOIN public.ottoq_events e ON e.entity_id = fs.vehicle_id AND e.entity_type = 'vehicle', r
  WHERE e.sim_run_id = r.run AND e.event_type = 'vehicle.state_changed' AND e.sim_clock_at >= fs.fault_at
    AND e.payload->'diff' ? 'current_stall_id'
    AND (e.payload->'diff'->'current_stall_id'->>'to') IS DISTINCT FROM fs.stall_id::text
  GROUP BY fs.session_id
)
SELECT fs.stall_code, fs.vehicle_id, fs.stopped_reason, fs.fault_at, c.clean_status, c.c_start, c.c_end, l.left_at,
       round(extract(epoch FROM (l.left_at - fs.fault_at))::numeric, 1) AS held_s
FROM fs LEFT JOIN clean c USING (session_id) LEFT JOIN left_post l USING (session_id)
ORDER BY fs.fault_at;

-- (2) the two branches in the stop path and the hold in the sweep, as live
SELECT p.oid::regprocedure AS fn, md5(p.prosrc) AS md5,
       strpos(p.prosrc, 'v_requeue := (p_reason LIKE ''fault%'' AND v_vehicle.current_soc < v_vehicle.target_soc - 5)') > 0 AS has_requeue_threshold,
       strpos(p.prosrc, '0760 (G479)') > 0 AS has_0760_hold
FROM pg_proc p
WHERE p.oid IN ('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure,
                'public.ottoq_release_expired_tethers(timestamp with time zone)'::regprocedure);

-- (3) in each fault window: sessions started on the post, and bookings that overlap it
WITH r AS (SELECT '8c0b2e04-8ea9-49a8-bfed-bed10ddfbc8b'::uuid AS run),
win AS (
  SELECT os.stall_id, os.vehicle_id AS faulted_car, os.ended_at AS f_from,
         COALESCE((SELECT min(o2.started_at) FROM public.ocpp_sessions o2
                    WHERE o2.sim_run_id = os.sim_run_id AND o2.stall_id = os.stall_id AND o2.started_at >= os.ended_at),
                  (SELECT sim_clock_current FROM public.ottoq_sim_runs WHERE sim_run_id = os.sim_run_id)) AS f_to
  FROM public.ocpp_sessions os, r WHERE os.sim_run_id = r.run AND os.status = 'faulted'
)
SELECT s.stall_code, w.f_from, w.f_to,
  (SELECT count(*) FROM public.ocpp_sessions o, r
    WHERE o.sim_run_id = r.run AND o.stall_id = w.stall_id AND o.started_at > w.f_from AND o.started_at < w.f_to) AS sessions_in_window,
  (SELECT json_agg(json_build_object('car_is_faulted_car', b.vehicle_id = w.faulted_car, 'booked_at_sim', b.booked_at_sim,
                                     'during', b.during::text, 'release', b.release_reason))
     FROM public.ottoq_stall_bookings b, r
    WHERE b.stall_id = w.stall_id AND b.sim_run_id = r.run AND b.during && tstzrange(w.f_from, w.f_to)) AS bookings
FROM win w JOIN public.stalls s ON s.id = w.stall_id ORDER BY w.f_from;

-- (4) the closing frames of the six faulted sessions, joined through the session (their charger_id is NULL): the
--     StatusNotification at each fault reads 'Available' (§5 (a))
SELECT c.ocpp_identifier, m.sim_clock_at, m.message_type, m.charger_id IS NULL AS no_charger,
       COALESCE(m.payload->>'eventType', m.payload->>'connectorStatus') AS kind,
       m.payload->'customData'->>'twin_reason' AS twin_reason
FROM public.ottoq_ocpp_messages m
JOIN public.ocpp_sessions os ON os.id = m.ocpp_session_id
JOIN public.stalls s ON s.id = os.stall_id
JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
WHERE m.sim_run_id = '8c0b2e04-8ea9-49a8-bfed-bed10ddfbc8b' AND os.status = 'faulted'
  AND COALESCE(m.payload->>'eventType', m.payload->>'connectorStatus') IN ('Ended', 'Available', 'Faulted')
ORDER BY m.sim_clock_at, m.message_type;
