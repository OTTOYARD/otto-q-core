-- 0471  **Replayed on the three busy days of the 30-post depot, serving first, among each owner's own cars, the cars a
--        charge sends home gives them back 9-17% of their time in the depot, every owner's on every day, feeds the
--        service bays as before, and costs the cars the bays hold 5-8 more minutes' wait for a post. Across owners it
--        would give back 15-20%, by putting one owner's cars ahead of another's: not built.** -> G501; 0781.
--        Chase, 2026-10-24: "Go find an edge and build." And: "we don't own our own vehicles, we manage for others- and
--        ideally multiple OEM's at the same depot eventually. So always base decisions off of that framing."
--        Runs 3389e651-6a4f-4267-a6f0-56d3a262bd92, 67290d0a-b527-4240-8dac-07eaf64c5d02 and
--        78c0624c-ff52-4594-8e54-9da254d4d867: busy_day at the twin depot (rule 8), sim 13:00 to about 22:00 UTC (8 AM to
--        5 PM CT sim), all three after 0763 (applied 2026-10-23 03:11 UTC): 30 robotic fast chargers, 2 service bays, 3
--        wash bays. Read-only against gxdrcyphqjzjsuhxuqtg: query (1) ran on 2026-10-24 between 17:40:55 and 17:53:58 UTC
--        (12:40 and 12:53 PM CT, the clock read either side), query (2) at 18:12:50 UTC (1:12 PM CT); the replay ran
--        offline, by 18:11:43 UTC (1:11 PM CT). The owners were read at 22:35:00 UTC (5:35 PM CT; query (3)) and the
--        replay within each owner ran by 22:36:24 UTC (5:36 PM CT).
--
-- ══ §1 THE CARS THE BAYS HOLD TAKE TWO THIRDS OF THE POSTS (reproduce: (1), (2)) ════════════════════════════════════════
--
--   A visit "owes service-bay work" when its atoms hold a mechanical PM, a sensor calibration, a fault repair or a
--   cosmetic repair (the service lane; 0470 §1 has the wash lanes, which are not the wall). Of the visits that charged:
--
--     run        visits that charged   owing service-bay work   their charge-minutes   reached a service bay
--     78c0624c         240                    127                 7,975 of 12,245            21
--     67290d0a         253                    128                 6,739 of 11,227            21
--     3389e651         199                    120                 8,438 of 12,708            19
--
--   The cars that owed none waited a mean 30.2, 23.3 and 57.4 minutes for a post; those that did, 90.3, 47.0 and 113.6.
--   (0470 §3 split visits by any bay work, wash included, so its 162 and 85 are not these.)
--
-- ══ §2 THE REPLAY (reproduce: (1), then scripts/replay_charge_line.py) ═════════════════════════════════════════════════
--
--   Each visit that charged joins the line at its arrival and takes its real charge minutes; a post is down from each
--   faulted charge to the next charge on it; 30 posts. Every order sees the same arrivals, minutes and repairs. The bay
--   line is read as 0781's public.ottoq_bay_line reads it: the cars at the depot owing service-bay work and not yet in a
--   bay, first come, each one's open minutes (est_min), and what is left of the cars in the bays now, over two bays.
--
--     run        order                                          exit-bound wait / time  bay-held wait  seats before charged  past 30 min
--     78c0624c   today (floor 90, minutes)                          28.9 /     7,536           65.0          5 (  192)        6,255
--     78c0624c   0781, each owner's own, margin 30                  23.1 /     6,884           70.2          5 (  202)        6,461
--     78c0624c   across owners, margin 30 (not built)               18.4 /     6,345           78.8          5 (  225)        7,143
--     78c0624c   across owners, hindsight's turns (not built)       17.0 /     6,197           75.9          3 (   81)        6,645
--     67290d0a   today (floor 90, minutes)                          18.6 /     6,813           30.9          3 (   46)        1,836
--     67290d0a   0781, each owner's own, margin 30                  11.5 /     5,922           39.2          3 (   47)        2,340
--     67290d0a   across owners, margin 30 (not built)               10.4 /     5,786           40.0          4 (   47)        2,392
--     67290d0a   across owners, hindsight's turns (not built)        9.9 /     5,724           42.3          2 (   35)        2,644
--     3389e651   today (floor 90, minutes)                          19.1 /     5,779           65.9          2 (  149)        5,817
--     3389e651   0781, each owner's own, margin 30                   7.1 /     4,827           72.4          3 (  158)        5,874
--     3389e651   across owners, margin 30 (not built)                4.8 /     4,651           73.6          2 (  147)        5,929
--     3389e651   across owners, hindsight's turns (not built)        4.6 /     4,631           72.9          1 (   66)        5,839
--
--   0781 reorders each owner's cars below the floor only among the places that owner's cars hold in today's line, its
--   cars whose charge is their exit first: no owner's car waits for another owner's car because of it. By owner, the
--   exit-bound cars' minutes in the depot fall on every day: Tesla Robotaxi TN 272, 140 and 194; Waymo Nashville 197,
--   696 and 529; Zoox Southeast 183, 55 and 230 (78c0624c, 67290d0a, 3389e651). Each owner's bay-held cars wait 3 to 9
--   minutes longer for a post. The owners are the engine's (query (3): 46 Waymo, 36 Tesla, 34 Zoox of the 116 cars).
--
--   "seats before charged": the car's first service seat that day came before the replayed charge ended (with the
--   minutes it was late in all); the service bays would not have had that car charged in time. "past 30 min": every
--   car's minutes past the owners' 30-minute queue wait. With a margin of 60 the exit-bound minutes read 6,862, 5,969
--   and 4,827 within each owner (6,336, 5,826 and 4,651 across owners). Ordering the bay line by deploy time instead of arrival reads within 140 minutes of these on every day.
--   A variant that also took the floor from the cars that yield gave the exit-bound cars at most 2.5 minutes more of
--   their wait back and about tripled the bay-held cars' cost (their wait 100.9, 59.8 and 92.3 minutes, with
--   hindsight's turns); it is not built.
--
-- ══ §3 WHAT THE REPLAY IS NOT ═════════════════════════════════════════════════════════════════════════════════════════
--
--   It does not replay the bays, the agent, the gate or the ticks, and its "today" waits less than the days did
--   (exit-bound 28.9 against 30.2, 18.6 against 23.3, 19.1 against 57.4: on 3389e651 the line had other delays the
--   replay leaves out). Three worlds of one seed: single readings, not ranges. The twin's answer is the demo run that
--   switches 0781 on (rule 12).

-- (1) the extraction the replay reads: visits with their bay atoms, readiness and owner, the charges, the bays' bookings
--     (the owner is the car's vehicles.fleet_operator_id as it stands when this runs; the 17:40 extraction did not carry
--     it, and the replay took the same owners from query (3))
WITH runs(r) AS (VALUES ('78c0624c-ff52-4594-8e54-9da254d4d867'::uuid), ('67290d0a-b527-4240-8dac-07eaf64c5d02'::uuid),
                        ('3389e651-6a4f-4267-a6f0-56d3a262bd92'::uuid))
SELECT jsonb_build_object(
  'visits', (SELECT jsonb_agg(jsonb_build_object(
       'run', left(vn.sim_run_id::text, 8), 'visit', vn.visit_id, 'car', vn.vehicle_id, 'arr', vn.arrived_at,
       'op', (SELECT v.fleet_operator_id FROM vehicles v WHERE v.id = vn.vehicle_id),
       'urg', vn.urgency, 'due', vn.dispatch_due_at, 'tgt', vn.target_soc, 'st', vn.status,
       'ready', (SELECT (a->>'done_at')::timestamptz FROM jsonb_array_elements(vn.atoms) a
                  WHERE a->>'svc' = 'readiness_check' AND a->>'status' = 'done' LIMIT 1),
       'bay', (SELECT jsonb_agg(jsonb_build_object('svc', a->>'svc', 'st', a->>'status', 'est', a->>'est_min',
                                                   'done', a->>'done_at', 'start', a->>'started_at'))
                 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'concurrency' = 'bay')))
     FROM ottoq_visit_needs vn JOIN runs ON runs.r = vn.sim_run_id),
  'sessions', (SELECT jsonb_agg(jsonb_build_object('run', left(o.sim_run_id::text, 8), 'car', o.vehicle_id, 'stall', o.stall_id,
       's', o.started_at, 'e', o.ended_at, 'soc0', o.soc_start, 'soc1', o.soc_end, 'stat', o.status, 'why', o.stopped_reason))
     FROM ocpp_sessions o JOIN runs ON runs.r = o.sim_run_id),
  'bays', (SELECT jsonb_agg(jsonb_build_object('run', left(b.sim_run_id::text, 8), 'car', b.vehicle_id, 'stall', b.stall_id,
       'type', st.stall_type, 'purpose', b.purpose, 'state', b.state, 's', lower(b.during), 'e', upper(b.during),
       'rel', b.released_at, 'why', b.release_reason, 'by', b.booked_by, 'bsim', b.booked_at_sim, 'atom', b.need_atom))
     FROM ottoq_stall_bookings b JOIN runs ON runs.r = b.sim_run_id JOIN stalls st ON st.id = b.stall_id
    WHERE st.stall_type IN ('service_bay', 'wash_bay')),
  'runs', (SELECT jsonb_agg(jsonb_build_object('run', left(r.sim_run_id::text, 8), 's', r.sim_clock_start, 'e', r.sim_clock_current, 'ticks', r.tick_count))
     FROM ottoq_sim_runs r JOIN runs ON runs.r = r.sim_run_id)
) AS d;
-- save the one row as JSON, then: python3 -I scripts/replay_charge_line.py EXTRACT.json [--margin 30] (the owners from
-- 'op'; an older extraction takes --owners OWNERS.csv, asset_id,owner, from (3))

-- (2) the census of §1, per run: visits that charged, those owing service-bay work, their charge-minutes, and how many
--     reached a service bay (the replay script prints the same from (1))
WITH runs(r) AS (VALUES ('78c0624c-ff52-4594-8e54-9da254d4d867'::uuid), ('67290d0a-b527-4240-8dac-07eaf64c5d02'::uuid),
                        ('3389e651-6a4f-4267-a6f0-56d3a262bd92'::uuid)),
v AS (
  SELECT vn.sim_run_id, vn.visit_id, vn.vehicle_id, vn.arrived_at,
         lead(vn.arrived_at) OVER (PARTITION BY vn.sim_run_id, vn.vehicle_id ORDER BY vn.arrived_at) AS nxt,
         EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                  WHERE a->>'svc' IN ('mechanical_pm', 'sensor_calibration', 'fault_repair', 'cosmetic_repair')) AS svc
    FROM ottoq_visit_needs vn JOIN runs ON runs.r = vn.sim_run_id),
c AS (
  SELECT v.*, (SELECT sum(extract(epoch FROM (coalesce(o.ended_at, r.sim_clock_current) - o.started_at)) / 60)
                 FROM ocpp_sessions o JOIN ottoq_sim_runs r ON r.sim_run_id = o.sim_run_id
                WHERE o.sim_run_id = v.sim_run_id AND o.vehicle_id = v.vehicle_id
                  AND o.started_at >= v.arrived_at - interval '1 minute' AND (v.nxt IS NULL OR o.started_at < v.nxt)) AS chg_min
    FROM v)
SELECT left(sim_run_id::text, 8) run, count(*) FILTER (WHERE chg_min IS NOT NULL) charged,
       count(*) FILTER (WHERE chg_min IS NOT NULL AND svc) owing_service,
       round(sum(chg_min) FILTER (WHERE svc)) service_charge_min, round(sum(chg_min)) all_charge_min
  FROM c GROUP BY 1 ORDER BY 1;

-- (3) the owners, at the twin depot: each car's fleet (22:35:00 UTC: Waymo Nashville 46, Tesla Robotaxi TN 36, Zoox
--     Southeast 34)
SELECT now() AS read_at, fo.name AS operator, v.fleet_operator_id, count(*) AS cars, jsonb_agg(v.id ORDER BY v.id) AS ids
  FROM vehicles v LEFT JOIN fleet_operators fo ON fo.id = v.fleet_operator_id
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
 GROUP BY fo.name, v.fleet_operator_id ORDER BY count(*) DESC;
