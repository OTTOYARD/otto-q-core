-- 0377  **G236, decided: a car that charges has its interior inspection at the charger, during the charge, by the
--       charger's sensors, and the same sensors give the verdict on an uncertain interior tidy (confirm, clear or
--       escalate). Before this, most such inspections started before the car was plugged in, most of the cars were also
--       sent to the arrival inspection lane, and every verdict waited for a technician's triage check.**
--
--       The decision (Chase, 2026-09-27, 10:00 PM CT): "Let's continue to have the interior inspection occur while the
--       vehicle is charging. Ideally, all charging will be robotic and they will just be sensors that potentially view
--       and approve or deny or confirm and clean, etc., while they are charging. This will suffice the idea of while
--       they're just sitting charging they could be easily interior cleaned, or at least inspected."
--
--       Baseline read on validation run 964cf17b (busy_day, twin depot, stopped at sim 11:17 AM). Takes the run as a
--       psql variable:
--
--           \set run '<sim_run_id>'

-- ══ §1 WHERE AND WHEN THE INTERIOR INSPECTIONS HAPPENED ═════════════════════════════════════════════════════════

\echo '=== 0377 §1 — interior inspections by whether the visit charges: started during a charge, before it, sent to the lane ==='
WITH a AS (
  SELECT vn.visit_id, vn.vehicle_id, x->>'status' AS status, (x->>'started_at')::timestamptz AS started_at,
         x->>'performed_by' AS performed_by,
         EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) y WHERE y->>'svc' = 'charge') AS visit_charges
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id = :'run' AND x->>'svc' = 'interior_inspection'),
j AS (
  SELECT a.*,
         EXISTS (SELECT 1 FROM public.ocpp_sessions os
                  WHERE os.sim_run_id = :'run' AND os.vehicle_id = a.vehicle_id
                    AND os.started_at <= a.started_at AND COALESCE(os.ended_at, 'infinity') > a.started_at) AS during_charge,
         (SELECT min(os.started_at) FROM public.ocpp_sessions os
           WHERE os.sim_run_id = :'run' AND os.vehicle_id = a.vehicle_id
             AND os.started_at >= a.started_at - interval '6 hours') AS next_session_start,
         (SELECT count(*) FROM public.ottoq_stall_bookings b
           WHERE b.sim_run_id = :'run' AND b.vehicle_id = a.vehicle_id AND b.purpose = 'inspect') AS lane_bookings
    FROM a)
SELECT visit_charges, count(*) AS atoms, count(*) FILTER (WHERE status = 'done') AS done,
       count(*) FILTER (WHERE started_at IS NOT NULL) AS started,
       count(*) FILTER (WHERE during_charge) AS started_during_a_charge,
       count(*) FILTER (WHERE started_at IS NOT NULL AND NOT during_charge AND next_session_start > started_at) AS started_before_its_charge,
       count(*) FILTER (WHERE performed_by = 'charger_sensors') AS by_the_chargers_sensors,
       count(*) FILTER (WHERE lane_bookings > 0) AS car_also_sent_to_the_lane
  FROM j GROUP BY 1 ORDER BY 1;
-- READ on 964cf17b: of 128 interior inspections on visits that charge, 101 started, and only 12 of them during a charge;
--   71 started before the car's charge began, and 77 of the cars were also sent to the arrival inspection lane. Of 9 on
--   visits with no charge, 7 started, 6 of those cars sent to the lane. (0374 §3 read the same shape on 66 lane visits:
--   the inspection overlapped 17, came after 19, and was already done before 12.)

\echo '=== 0377 §1(b) — triage checks by whether the visit charges and whether every need they judge is in the cabin ==='
WITH a AS (
  SELECT vn.visit_id, vn.vehicle_id, x->>'status' AS status, (x->>'started_at')::timestamptz AS started_at,
         x->>'performed_by' AS performed_by,
         EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) y WHERE y->>'svc' = 'charge') AS visit_charges,
         NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) y
                      WHERE (y ? 'triage_verdict' OR COALESCE((y->>'confirm_required')::boolean, false))
                        AND y->>'concurrency' IS DISTINCT FROM 'cabin') AS judges_only_the_cabin
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id = :'run' AND x->>'svc' = 'triage_check'),
j AS (
  SELECT a.*,
         EXISTS (SELECT 1 FROM public.ocpp_sessions os
                  WHERE os.sim_run_id = :'run' AND os.vehicle_id = a.vehicle_id
                    AND os.started_at <= a.started_at AND COALESCE(os.ended_at, 'infinity') > a.started_at) AS during_charge
    FROM a)
SELECT visit_charges, judges_only_the_cabin, count(*) AS triage_checks,
       count(*) FILTER (WHERE started_at IS NOT NULL) AS started,
       count(*) FILTER (WHERE during_charge) AS started_during_a_charge,
       count(*) FILTER (WHERE performed_by = 'charger_sensors') AS by_the_chargers_sensors
  FROM j GROUP BY 1, 2 ORDER BY 1, 2;
-- READ on 964cf17b: on visits that charge, 18 triage checks judged only the cabin (every one an uncertain interior
--   tidy); 17 started, 3 of them during a charge, none by the charger's sensors. 6 more also judged an exterior or bay
--   need (a sensor clean, a cosmetic repair), none during a charge. 2 on visits with no charge. The verdicts on the
--   run's 19 judged tidies: 10 confirmed, 6 cleared, 3 escalated to a deep clean.

-- ══ §2 THE MECHANISM ════════════════════════════════════════════════════════════════════════════════════════════
--
--   The service catalogue already means it to happen at the charger: `service_cadence_policy` gives
--   `interior_inspection` the lane `cabin`, "Cheap tech-pool lane at the charge stall", and the planner writes a
--   charging visit's cabin legs "concurrent with the charge" (`duration_basis.concurrent_with = 'charge'`). Two things
--   ignore that:
--   (1) `ottoq_decide_tick` calls `ottoq_start_concurrent_atoms` when it enacts a charge, before the car has driven to
--       the charger, and that starter starts every pending cabin atom wherever the car is. The twin's own starter
--       (`twin.ottoq_sim_advance_visit_atoms`) already holds a cabin atom until the car is charging, with two catch-ups
--       (still on the charger after the charge; staged for departure).
--   (2) `ottoq.ottoq_enact_inspection_seam` sends any car with a planned, unbound `inspect` leg for the interior
--       inspection to an `arrival_inspection` stall, including the legs the planner marked concurrent with the charge.
--   And the starter meters every cabin atom against the 10 general technicians (founder spec, July: "plug in, 3-5 min
--   interior clean, inspect"). Under the decision the charger's sensors inspect, so an inspection at the charger takes
--   no technician; the interior tidy stays a technician's job.
--   The triage: a need whose confidence falls in the confirm band (`confirm_band_lo`..`hi`, 0.40-0.75 by default)
--   carries `confirm_required` and cannot start; the starter adds one `triage_check` (cabin, 3 min, a technician), and
--   when it completes the twin draws each such need's verdict from its confidence: confirm, clear (cancelled, never
--   credited), or escalate (a tidy becomes a deep clean in the detail bay). The charger's sensors see the cabin, so a
--   triage that judges only cabin needs is theirs to perform; the verdict is drawn exactly as before, whoever
--   performed the check, so only the actor and the moment move.

\echo '=== 0377 §2 — the catalogue, and the planner''s tag on a charging visit''s inspection legs ==='
SELECT (SELECT lane || ' / ' || notes FROM public.service_cadence_policy WHERE svc = 'interior_inspection') AS catalogue,
       count(*) FILTER (WHERE l.duration_basis->>'concurrent_with' = 'charge') AS inspect_legs_planned_with_the_charge,
       count(*) FILTER (WHERE COALESCE(l.duration_basis->>'concurrent_with', '') <> 'charge') AS inspect_legs_standalone,
       count(*) FILTER (WHERE l.duration_basis->>'concurrent_with' = 'charge'
                          AND EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                                       WHERE b.leg_id = l.leg_id AND b.purpose = 'inspect')) AS planned_with_the_charge_but_lane_booked
  FROM public.ottoq_itinerary_legs l
 WHERE l.sim_run_id = :'run' AND l.leg_type = 'inspect'
   AND COALESCE(l.duration_basis->>'atom', 'interior_inspection') = 'interior_inspection';
-- READ on 964cf17b: the catalogue reads `cabin / Cheap tech-pool lane at the charge stall.`; 115 interior inspection
--   legs were planned with the charge and 17 standalone, and the seam booked the lane for 54 of the 115.

-- ══ §3 THE APPLY (0511), AND THE CANON UNDER IT ═════════════════════════════════════════════════════════════════
--
--   0511 (`the_interior_inspection_happens_during_the_charge`): while a visit still has its charge to do, its cabin
--   atoms start only on the charger (or in the twin's two catch-ups); an interior inspection on the charger, and a
--   triage check that judges only the cabin, are done by its sensors (`performed_by = 'charger_sensors'`) and take no
--   technician; the seam passes over an inspection leg planned with the charge; and a leg nothing bound to a stall
--   records where the car was when the work finished.

\echo '=== 0377 §3 — 0511 as applied ==='
SELECT m.version, m.name, md5(m.statements[1]) AS stored_md5
  FROM supabase_migrations.schema_migrations m
 WHERE m.name = 'the_interior_inspection_happens_during_the_charge';
-- READ (2026-09-27 03:43 UTC, 10:43 PM CT): version 20260927034307, stored md5 f9591188831781de1e386d7a0aee58ed, the
--   file's body byte for byte. Applied once the canon had passed all nine columns under 0510 (verdicts 457-465), with
--   no pair in flight and no run live. V3 passed on the stopped run 964cf17b, rolled back: (a) a charging visit's cabin
--   work held in staging, the triage check added but not started; (b) on the charger with no general technician free,
--   the inspection and the cabin-only triage started, performed by the charger's sensors, while the item retrieval
--   waited for a technician and the tidy for the triage's verdict; (b2) with an uncertain sensor clean added the triage
--   waited for a technician; (c) a technician's inspection once the charge was done; (d) the seam passed over the car
--   whose leg was planned with its charge and considered the other; (e) the inspection leg closed on the charger's
--   stall and its one service record names it. The first dry run failed (d) on the rig, not the change: the seam's
--   first step closes a planned inspection leg that already has a done lane booking, and the stopped run had booked
--   the lane for the replanted leg; V3 now detaches those bookings. Bodies after: starter 27afba5d125225f796058c1a894d0b93,
--   seam 7188902a73038886a3f7077b5bdc975f, closer f4605207eaf4860749deb4406b521239; `0511_pre` snapshots 3.

-- ══ §4 THE NEXT VALIDATION RUN, PREDICTED BEFORE IT STARTS ══════════════════════════════════════════════════════
--
--   PREDICTED on the next busy_day operator run, read with §1 and §2 above on it: (a) on visits that charge, every
--   interior inspection that starts, starts during a charge or in a catch-up on the charger, and none before the car's
--   charge (71 of 101 on 964cf17b); (b) those started on the charger carry `performed_by = 'charger_sensors'`;
--   (c) no car whose inspection leg was planned with its charge is booked into the arrival lane (54 of 115 legs on
--   964cf17b); (d) a done interior inspection leg names a stall, the charger's when it was done there; read with §1(b):
--   (f) on visits that charge, every triage check that judges only the cabin and starts, starts on the charger by its
--   sensors (3 of 17 during a charge on 964cf17b, none by sensors), and (g) one that also judges an exterior or bay need
--   is still a technician's; (h) the verdict mix stays the twin's draw (10 confirm / 6 clear / 3 escalate of 19 on
--   964cf17b is one sample of it, not a target). Not predicted: what freeing the technicians of inspections and cabin
--   triage does to the other cabin and exterior work, which (e) reads.

\echo '=== 0377 §4(d) — done interior inspection legs by the kind of stall they name ==='
SELECT COALESCE(st.stall_type::text, '(none)') AS stall_type, count(*) AS done_legs
  FROM public.ottoq_itinerary_legs l
  LEFT JOIN public.stalls st ON st.id = l.to_stall_id
 WHERE l.sim_run_id = :'run' AND l.leg_type = 'inspect' AND l.status = 'done'
   AND COALESCE(l.duration_basis->>'atom', 'interior_inspection') = 'interior_inspection'
 GROUP BY 1 ORDER BY 2 DESC;
-- READ: pending.

\echo '=== 0377 §4(e) — cabin and exterior atoms: started, and sim-minutes from the car''s arrival to the start ==='
SELECT x->>'svc' AS svc, count(*) AS atoms, count(*) FILTER (WHERE x->>'started_at' IS NOT NULL) AS started,
       count(*) FILTER (WHERE x->>'performed_by' = 'charger_sensors') AS by_sensors,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM (x->>'started_at')::timestamptz - vn.arrived_at) / 60)
              FILTER (WHERE x->>'started_at' IS NOT NULL AND vn.arrived_at IS NOT NULL))::numeric, 1) AS p50_min_arrival_to_start
  FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
 WHERE vn.sim_run_id = :'run' AND x->>'concurrency' IN ('cabin', 'exterior')
 GROUP BY 1 ORDER BY 1;
-- READ before 0511, on 964cf17b: interior_inspection 137 atoms, 108 started, a median 4.9 sim-minutes from arrival
--   to start; interior_tidy 43 / 24 / 11.7; item_retrieval 12 / 10 / 3.9; sensor_clean 7 / 4 / 2.0; triage_check 26 /
--   25 / 6.5; none by sensors. Expected after: the inspection's arrival-to-start grows to about the wait for a charger
--   (it now starts at the plug), and costs no depot time, because a 4-minute inspection runs inside a charge of 40-75.
--   (Both clocks are sim: `arrived_at` is the visit's sim arrival and `started_at` the atom's sim start; the row's
--   `created_at` is real time and never enters this.)
-- READ after: pending.
