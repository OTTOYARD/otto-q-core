-- 0388  **G245: the charger's sensors "finished" an interior inspection on cars that had already left the charger,
--       every time because a charger fault cut the charge short while the sensors were at work. 0519 makes the work
--       the stall's: done only if the car is still on the stall whose sensors started it, else pending again.**
--
--       Written on 2026-09-27 (07:00-07:55 UTC, 2:00-2:55 AM CT). Read-only.

-- ══ §1 BEFORE: SENSOR WORK DONE AFTER THE CAR'S CHARGE HAD ENDED ═══════════════════════════════════════════════

\echo '=== 0388 §1 — sensor work that finished after its charge ended: how the charge ended, and where the car was ==='
WITH ins AS (
  SELECT vn.sim_run_id, vn.vehicle_id, x->>'svc' AS svc, (x->>'started_at')::timestamptz AS ins_start,
         (x->>'done_at')::timestamptz AS ins_done
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id IN ('caf85837-8681-4afe-9744-03eecd796737','4bc19d29-790c-4cb0-9e2e-ae090a7da57b')
     AND x->>'performed_by' = 'charger_sensors' AND x->>'done_at' IS NOT NULL),
j AS (
  SELECT ins.*, os.stall_id AS charger_stall, os.started_at AS plug, os.ended_at AS unplug, os.stopped_reason
    FROM ins JOIN LATERAL (SELECT * FROM public.ocpp_sessions o WHERE o.sim_run_id = ins.sim_run_id AND o.vehicle_id = ins.vehicle_id
                  AND o.started_at <= ins.ins_start AND COALESCE(o.ended_at, 'infinity') > ins.ins_start - interval '5 seconds'
                ORDER BY o.started_at DESC LIMIT 1) os ON true)
SELECT left(j.sim_run_id::text, 8) AS run, v.display_name AS car, j.svc, j.stopped_reason,
       round(EXTRACT(epoch FROM j.unplug - j.plug) / 60, 1) AS charge_min,
       round(EXTRACT(epoch FROM j.ins_start - j.plug) / 60, 2) AS started_min_after_plug,
       round(EXTRACT(epoch FROM j.ins_done - j.unplug) / 60, 1) AS done_min_after_unplug,
       (SELECT CASE WHEN e.payload->'diff'->'current_stall_id'->>'to' IS NULL THEN '(no stall)'
                    WHEN (e.payload->'diff'->'current_stall_id'->>'to')::uuid = j.charger_stall THEN 'the same charger'
                    ELSE 'another ' || (SELECT s.stall_type::text FROM public.stalls s
                                          WHERE s.id = (e.payload->'diff'->'current_stall_id'->>'to')::uuid) || ' stall' END
          FROM public.ottoq_events e
         WHERE e.sim_run_id = j.sim_run_id AND e.entity_id = j.vehicle_id AND e.event_type = 'vehicle.state_changed'
           AND e.payload->'diff' ? 'current_stall_id' AND e.sim_clock_at <= j.ins_done
         ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1) AS car_was_on_at_done
  FROM j JOIN public.vehicles v ON v.id = j.vehicle_id
 WHERE j.unplug IS NOT NULL AND j.ins_done > j.unplug
 ORDER BY 1, j.ins_start;
-- READ (2026-09-27 07:00 UTC; 4bc19d29 still running, at sim 3 PM):
--     4bc19d29  Tesla-AV-054   interior_inspection  fault.connector_cable        4.5  0.42  0.9  another staging stall
--     4bc19d29  Tesla-AV-041   interior_inspection  fault.station_hardware       3.7  0.37  0.7  another staging stall
--     caf85837  Tesla-AV-050   interior_inspection  fault.session_aborted_other  4.2  0.44  1.3  another staging stall
--     caf85837  Waymo-AV-016   interior_inspection  fault.session_aborted_other  1.8  0.39  2.6  another l2 stall
--     caf85837  Tesla-AV-057   interior_inspection  fault.communication_dropout  3.9  0.38  1.4  another staging stall
--   Every one a charge cut by a fault within 5 minutes of the plug-in, every inspection started as 0511 meant (within
--   half a minute of the plug-in), and every car on another stall when the work was marked done: four in staging, and
--   Waymo-AV-016 on a second L2 (L2-19 faulted at 8:22:59, a staging stall, then L2-01 from 8:23:51). 0377 §4(d) said
--   016 "stayed parked" on its charger; the stall pointer says otherwise, and that note is corrected with this check.
--   No sensor work finished after a charge that ended normally: the sensors' 4-5 minutes fit inside every completed
--   charge. So the defect is not when the work starts but that its completion never asks where the car is.
--   Re-read at 07:45 UTC with both runs stopped: unchanged. Of 275 pieces of sensor work done on the two runs (179 and
--   96, 28 of them cabin-only triage checks), these 5 -- 1.8% -- finished after the unplug, all five inspections, all five
--   after a fault.

-- ══ §2 0519 AS APPLIED ══════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0388 §2 — 0519 in the migration ledger, and the two functions it left ==='
SELECT m.version, md5(m.statements[1]) AS body_md5,
       md5(pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)) AS starter_md5,
       md5(pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure)) AS completer_md5,
       (SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0519_pre') AS pre_snapshots
  FROM supabase_migrations.schema_migrations m
 WHERE m.name = 'the_charger_s_sensors_cannot_finish_an_inspection_on_a_car_that_has_left';
-- READ (2026-09-27 07:43 UTC): version 20260927074236 (2:42 AM CT), body md5 1d912844e924e975d3013dec3f300da3, the
--   file's body byte for byte; the starter after 0399fc87dec364503e3bdc6a6a3e3f3b (before 27afba5d125225f796058c1a894d0b93),
--   the completer after 9b3b0e4cdef4b1974d5237354f473f5a (before 6ce0e95a765046f7a98e9a7e4ceb8b1f), both kept as
--   `0519_pre`. Applied 54 seconds after 0518, so one sweep reads both. V3 passed in the dry run and the apply, on
--   4bc19d29 marked running inside the test, with a car planted on a free L2 against a visit whose charge and interior
--   inspection were still to do: the sensors started the inspection and stamped that L2; the car moved to staging, and
--   at the end of the inspection's 4 minutes it was pending again, with no start, end or performer and one interruption
--   (`left_the_charger`, the first L2); on a second L2 the sensors started it again with that stall, and it was done at
--   the end of its minutes with the interruption kept.
--   The dry run failed twice first, both times in V3's own set-up and both times on an invariant worth recording:
--   (a) a car one stall still points at cannot be moved onto another -- `idx_stalls_one_vehicle_per_stall`; the test now
--   plants a car no stall points at; and (b) a stall does not let go of a car that is charging -- the reassignment guard
--   on `stalls` keeps the pointer of a car mid-work, so a move and a plug-in written as one statement leave the old stall
--   holding the car; the engine moves first and plugs in after, and so does the test now.

-- ══ §3 THE SWEEP ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   With 0518; READ in `db/checks/0387` §3.

-- ══ §4 THE NEXT VALIDATION RUN, PREDICTED BEFORE IT STARTS ══════════════════════════════════════════════════════
--
--   PREDICTED on the next busy_day operator run: (a) every piece of sensor work started carries `sensor_stall_id`;
--   (b) none is marked done after its car has left that stall: sensor work done after its charge's unplug appears only
--   where the car stayed on the stall (0 of the kind in §1); (c) a fault that cuts a charge during the sensors' work
--   leaves the work pending with one `interrupted` entry, and the work is done later on another charger or by a
--   technician; (d) not predicted, read: how long an interrupted inspection waits to be done again, since the car's
--   next charger may be minutes or an hour away.

\echo '=== 0388 §4 — the validation run: sensor work by outcome, whether it carries its stall, and where the car was when it was done ==='
WITH a AS (
  SELECT vn.vehicle_id, x->>'svc' AS svc, COALESCE(x->>'status','pending') AS st, (x ? 'sensor_stall_id') AS stamped,
         (x->>'sensor_stall_id')::uuid AS sstall, (x->>'done_at')::timestamptz AS done_at,
         jsonb_array_length(COALESCE(x->'interrupted', '[]'::jsonb)) AS interruptions
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id = 'c4afb873-ce23-4ae7-b167-9fda79961fc7'
     AND (x->>'performed_by' = 'charger_sensors' OR x ? 'interrupted'))
SELECT a.svc, a.st, count(*) AS n, count(*) FILTER (WHERE a.stamped) AS stamp_key, count(*) FILTER (WHERE a.sstall IS NOT NULL) AS stamp_value,
       sum(a.interruptions) AS interruptions,
       count(*) FILTER (WHERE a.st = 'done' AND a.sstall IS NOT NULL
                          AND a.sstall = (SELECT (e.payload->'diff'->'current_stall_id'->>'to')::uuid FROM public.ottoq_events e
                                           WHERE e.sim_run_id = 'c4afb873-ce23-4ae7-b167-9fda79961fc7' AND e.entity_id = a.vehicle_id
                                             AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_stall_id'
                                             AND e.sim_clock_at <= a.done_at
                                           ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1)) AS done_with_car_on_that_stall
  FROM a GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 08:40 UTC; c4afb873, sim 8:00-9:55 AM):
--     interior_inspection  done         59  stamped 59 (57 with a stall)  1 interruption   57 done with the car on it
--     interior_inspection  in_progress   4          4 (4)                                  --
--     interior_inspection  pending       1          -- (0519 took the stamp)  1 interruption
--     triage_check         done          7          7 (6)                                  6
--   (a) HOLDS IN FORM, NOT IN SUBSTANCE: every one of the 70 pieces of sensor work started carries `sensor_stall_id`, but
--   3 carry it empty, because the car was on no stall when the sensors "started" -- and 3 more carry a staging stall.
--   That is G246, `db/checks/0390`: 6 of the run's 72 sensor starts were on no charger at all.
--   (b) HOLDS: no sensor work was done after its car's unplug (5 of 275 on the night's two earlier runs), and every one
--   of the 63 done with a stall stamped was done with the car on that stall -- 62 chargers and, G246 again, one staging
--   stall (Zoox-AV-091's second start). The 3 done with an empty stamp passed 0519's
--   check by having nothing to compare: Tesla-AV-043's inspection finished in a wash bay, Waymo-AV-027's inspection and
--   triage on a staging stall.
--   (c) NOT EXERCISED AS PREDICTED: no charge was cut by a fault during sensor work on this 116-minute run, so the case
--   0519 exists for did not occur. 0519's branch fired twice, both times on a car moved between two STAGING stalls
--   (Zoox-AV-091 from NASH-STG-I010 at 8:11:48, Waymo-AV-002 from I010 at 8:29:22), each returned to pending with one
--   `left_the_charger` interruption naming the staging stall -- the mechanism working, on a premise (G246) that was
--   false. 091's was started again 22 seconds later on the next staging stall, W021, and "done" there; 002's was still
--   pending when its visit was superseded.
--   (d) UNREAD: the one re-start (22 seconds) was on a staging stall, not a charger, and says nothing about how long an
--   inspection cut by a fault waits for the car's next charger. That needs a run long enough for faults to land in the
--   sensors' 3-5 minutes -- 5 in 12 sim-hours on the night's two earlier runs.
