-- 0390  **G246: the charger's sensors were credited with work on cars that were on no charger -- a car the gate
--       intake held on staging with no charge to do, a car between its charger and a bay -- because the starter read
--       "on the charger" from the car's state. 0521 reads it from the car's stall.**
--
--       Written on 2026-09-27 (08:35-09:00 UTC, 3:35-4:00 AM CT), from validation run c4afb873 (`db/checks/0388` §4).
--       Read-only.

-- ══ §1 BEFORE: WHERE THE SENSORS STARTED, BY THE STALL 0519 STAMPED ═════════════════════════════════════════════

\echo '=== 0390 §1 — every sensor start on c4afb873, by the kind of stall stamped, and whether the car charged there ==='
-- A start is the atom's current one or one that 0519 returned to pending (kept in `interrupted`, with its stall).
WITH starts AS (
  SELECT vn.vehicle_id, x->>'svc' AS svc, COALESCE(x->>'status','pending') AS st, (x->>'sensor_stall_id')::uuid AS stall
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id = 'c4afb873-ce23-4ae7-b167-9fda79961fc7' AND x->>'performed_by' = 'charger_sensors'
  UNION ALL
  SELECT vn.vehicle_id, x->>'svc', 'returned to pending (0519)', (i->>'stall_id')::uuid
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x, jsonb_array_elements(x->'interrupted') i
   WHERE vn.sim_run_id = 'c4afb873-ce23-4ae7-b167-9fda79961fc7')
SELECT COALESCE(s.stall_type::text, '(no stall)') AS sensor_stall, st.st AS outcome, count(*) AS starts,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ocpp_sessions os
                                       WHERE os.sim_run_id = 'c4afb873-ce23-4ae7-b167-9fda79961fc7'
                                         AND os.vehicle_id = st.vehicle_id AND os.stall_id = st.stall)) AS with_a_session_there
  FROM starts st LEFT JOIN public.stalls s ON s.id = st.stall
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 08:47 UTC, 3:47 AM CT; the run stopped at 3:32 AM CT, sim 9:55 AM):
--     dcfc        done 23, in progress 1    every one with a charge session on that stall
--     l2          done 39, in progress 3    every one with a charge session on that stall
--     staging     done 1, returned to pending by 0519 2    none with a session
--     (no stall)  done 3                    none with a session
--   72 sensor starts; 66 on a charger the car charged on, 6 on no charger at all, and those 6 produced 4 of the run's 66
--   sensor completions. The cars (states and stalls from the signed event stream):
--     Zoox-AV-091   arrived 8:08 AM near full with no charge on its visit; the gate intake put it in charge_complete_holding
--                   on NASH-STG-I010 (staging). The sensors started its inspection there; it was moved to NASH-STG-W021
--                   3.5 minutes later, 0519 returned the work to pending, the sensors started it again on W021, and it
--                   was "done" there at 8:15.
--     Waymo-AV-002  arrived 8:24 AM with no charge on the run, the same intake stall, the same state; its inspection
--                   started there and went back to pending when it moved to NASH-STG-B005. Still pending (its visit since
--                   superseded) when the run stopped.
--     Tesla-AV-043  charged on NASH-L2-STALL-14 until 8:05:53 AM and left it (stall pointer cleared, state still
--                   charge_complete_holding); 30 seconds later, with no stall, the sensors started its inspection, in the
--                   tick it entered NASH-WSH-01 (state in_detail_bay). "Done" in that bay at 8:10.
--     Waymo-AV-027  arrived 8:22 AM with no charge on the run; charge_complete_holding at the gate, no stall; the sensors
--                   started an inspection and a cabin triage at 8:24:13, the tick it was parked on NASH-STG-I011 (staging),
--                   both "done" there at 8:27.
--   So `charge_complete_holding` is two things the starter took for one: "still on the charger after the charge" (0511's
--   catch-up) and "held, with no charge to do or none left" (the gate intake's parking state, and the state a car keeps
--   as it leaves its charger). 0519 could
--   not have caught this class: it compares the car's stall with the stall stamped, and a stall of staging, or none,
--   compares clean. It caught 2 of the 6 only because two cars moved between staging stalls mid-inspection.

\echo '=== 0390 §1(b) — the night''s two earlier runs, from the signed event stream (a floor: one tick''s changes cannot be ordered) ==='
WITH a AS (
  SELECT vn.sim_run_id, vn.vehicle_id, (x->>'started_at')::timestamptz AS started_at
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id IN ('4bc19d29-790c-4cb0-9e2e-ae090a7da57b','caf85837-8681-4afe-9744-03eecd796737')
     AND x->>'performed_by' = 'charger_sensors' AND x ? 'started_at'),
b AS (
  SELECT a.*,
         (SELECT (e.payload->'diff'->'current_stall_id'->>'to')::uuid
            FROM public.ottoq_events e
           WHERE e.sim_run_id = a.sim_run_id AND e.entity_id = a.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_stall_id' AND e.sim_clock_at <= a.started_at
           ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1) AS stall_at_start
    FROM a)
SELECT left(b.sim_run_id::text, 8) AS run, COALESCE(s.stall_type::text, '(no stall)') AS stall_at_start, count(*) AS sensor_starts,
       string_agg(to_char(b.started_at AT TIME ZONE 'America/Chicago', 'HH24:MI'), ', ' ORDER BY b.started_at)
         FILTER (WHERE COALESCE(s.stall_type::text, '') NOT IN ('dcfc','l2')) AS off_charger_at_ct
  FROM b LEFT JOIN public.stalls s ON s.id = b.stall_at_start
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 08:47 UTC):
--     4bc19d29  dcfc 85, l2 97, staging 1 (8:13 AM), wash_bay 1 (1:47 PM)
--     caf85837  dcfc 38, l2 58, staging 2 (8:02 AM, 8:02 AM)
--   4 of 282 by the event stream, against 6 of 72 by 0519's stamp on c4afb873: the stream cannot see a start made in the
--   tick a car changes stall, which is where 3 of c4afb873's 6 were, so these counts are floors. Most are in a run's
--   first half hour, when the fleet the reset parks at 97-99% comes through the gate with nothing to charge, but not
--   all (4bc19d29's wash bay at 1:47 PM).

\echo '=== 0390 §1(c) — who puts a car in charge_complete_holding, and who reads it ==='
SELECT p.oid::regprocedure::text AS writer, m[1] AS statement
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
       regexp_matches(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'),
                      '([^\n]*current_state\s*=\s*''charge_complete_holding''[^\n]*)', 'g') AS m
 WHERE n.nspname IN ('public','ottoq','twin')
   AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'SET[^;]*current_state\s*=\s*''charge_complete_holding'''
 ORDER BY 1;
-- READ (2026-09-27 08:58 UTC): the query finds three writers, the three that write the state with a literal `SET`:
--   `twin.ottoq_sim_stop_charge_session` after a charge, which is the meaning 0511 assumed; and two at the gate,
--   `twin.ottoq_world_advance`'s "gate disposition (target-aware): an arrival already at/above its OWN charge target needs
--   no charge -> hold for onward disposition (wash/deploy)" and the older `ottoq_sim_advance_tick_world`'s (SoC >= 85).
--   Reading every line that names the state (33 functions, comment-stripped) found two more the regex cannot see:
--   `twin.ottoq_sim_bay_fault_handler` assigns it through a variable when a wash bay faults, and
--   `twin.ottoq_sim_seed_fleet` seeds most of the fleet into it. So the overload is by design, not a slip: "charge
--   complete" is written for "no charge needed", "out of a faulted bay" and "the fleet as seeded" too.
--   Of the 33 readers, read line by line and the two nearest a charger in context (`ottoq_decide_tick`'s charge
--   disposition, `twin.ottoq_sim_emit_depot_heartbeats`), only the starter took the state to mean "on a charger" in order
--   to credit work there; the rest group it as "holding, ready for the next step" -- a disposition, a count, a list of
--   in-depot states -- which holds wherever the car stands. The decide tick's cursor calls itself "the charge-stall ->
--   wash-bay door", but what it does, send a holding car to a bay or to staging, is as right from a staging stall.
--   Noted, not changed: the gate disposition judges "no charge needed" as SoC >= the VEHICLE's `target_soc`, while
--   0518's one rule is SoC >= the visit's (or step's) target - 1. A car at target - 1 is "needs no charge" to the deriver,
--   the cursor and the flow contract, and not held by the gate. A fourth place that asks the question, on a fourth rule.

-- ══ §2 0521 AS APPLIED ══════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0390 §2 — 0521 in the migration ledger, and the starter it left ==='
SELECT m.version, md5(m.statements[1]) AS body_md5,
       md5(pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)) AS starter_md5,
       (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0521_pre') AS starter_before_md5,
       (SELECT forces_recert FROM public.ottoq_cert_lineage WHERE name = '0521_the_charger_s_sensors_see_only_a_car_on_a_charger') AS forces_recert
  FROM supabase_migrations.schema_migrations m WHERE m.name = 'the_charger_s_sensors_see_only_a_car_on_a_charger';
-- READ (2026-09-27 08:52 UTC): version 20260927085218 (3:52 AM CT), body md5 98fcfc13b30657cba523ed03bcc8d5ca, the
--   file's body byte for byte; the starter after 8f362785be818b2d5a0794e109da2984 (before 0399fc87dec364503e3bdc6a6a3e3f3b,
--   0519's, kept as `0521_pre`); forces_recert TRUE, and all nine canon columns fell below the floor. Applied with no run
--   live and no rig in flight: the dial runner was paused at 3:45 AM CT, the pair then running (energy experiment
--   82c5568b, 9.7 minutes) was let finish, and the runner was re-enabled after the apply, to wait behind the recert
--   sweep as it must. The dry run and the apply both passed on the first attempt, V3 included: a car planted in
--   `charge_complete_holding` against a visit with no charge got no sensor credit on a staging stall or on no stall;
--   on an L2 the sensors took its inspection and stamped that L2; given an open charge step, on staging its inspection
--   stayed pending, and on the L2 the sensors took it.
--   First drafted to change only the sensors, and widened before the dry run: the same state list is the cabin hold's
--   exemption, and Waymo-AV-002 -- parked on staging, its charge step still open -- is that case on this very run. The
--   draft's header had called it "a case never seen"; §1's table, read one column further, showed it.

-- ══ §3 THE SWEEP ════════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0390 §3 — the verdicts since 0521 ==='
SELECT l.verdict_id, l.scenario, l.seed, l.ticks, l.outcome, l.equal, l.complete, l.disagreeing_atoms,
       left(l.engine_hash, 8) AS engine, to_char(l.certified_at AT TIME ZONE 'America/Chicago', 'HH24:MI:SS') AS certified_ct
  FROM public.ottoq_determinism_verdict_ledger l
 WHERE l.certified_at > (SELECT classified_at FROM public.ottoq_cert_lineage
                          WHERE name = '0521_the_charger_s_sensors_see_only_a_car_on_a_charger')
 ORDER BY l.verdict_id;
-- READ (2026-09-27 10:09 UTC, 5:09 AM CT): all nine columns passed on the first attempt, verdicts 486-494 between
--   3:53:00 and 4:13:54 AM CT, every one equal and complete with no disagreeing atom, all on engine f03cf4ee. The dial
--   runner waited behind the sweep, as certification has priority, and took its first pair at 4:30.

\echo '=== 0390 §3(b) — per column, the digests 0521 moved against the column''s last verdict before it ==='
WITH cut AS (SELECT classified_at FROM public.ottoq_cert_lineage
              WHERE name = '0521_the_charger_s_sensors_see_only_a_car_on_a_charger'),
v AS (
  SELECT l.verdict_id, l.scenario, l.seed, l.ticks, l.certified_at > (SELECT classified_at FROM cut) AS after_0521,
         l.verdict->'arm_a' AS a,
         row_number() OVER (PARTITION BY l.scenario, l.seed, l.ticks, l.certified_at > (SELECT classified_at FROM cut)
                            ORDER BY l.verdict_id DESC) AS rn
    FROM public.ottoq_determinism_verdict_ledger l
   WHERE l.outcome = 'passed' AND jsonb_typeof(l.verdict->'arm_a') = 'object')
SELECT c.scenario, c.seed, c.ticks, c.verdict_id AS now_v, p.verdict_id AS before_v,
       COALESCE((SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(c.a) k
                  WHERE k LIKE 'h\_%' AND c.a->>k IS DISTINCT FROM p.a->>k), '(none)') AS moved_digests
  FROM v c JOIN v p ON (p.scenario, p.seed, p.ticks) = (c.scenario, c.seed, c.ticks) AND p.rn = 1 AND NOT p.after_0521
 WHERE c.rn = 1 AND c.after_0521
 ORDER BY c.ticks, c.scenario, c.seed;
-- READ (2026-09-27 10:09 UTC):
--     grid_smoke 239001/6, 424242/6       (none)                                  against 477, 478
--     busy_day 171717/12, normal_day 171717/12   h_bkg h_cmd h_dec h_evt h_rule h_sdr   against 479, 482
--     busy_day 314159/12                  the same and h_nrg                      against 480
--     busy_day 424242/12, 171717/24       the same, h_nrg and h_rcl               against 481, 483
--     busy_day 424242/24, 171717/48       the same, h_nrg, h_prop and h_rcl       against 484, 485
--   A clean attribution, unlike 0387 §3's: every "before" verdict was on engine 1f067bbf with the week's new priors,
--   and h_cal moved in no column. So 0521 alone moved 6-9 of 11 digests on every busy and normal day, from the
--   12-tick columns up. That fits §1(c): the fleet seeder puts most of the fleet into charge_complete_holding, so from
--   the first tick of a certified arm the starter was crediting sensors on cars that were not on a charger, and now
--   gives those inspections to technicians -- who are counted against the pool, which moves what else starts. The two
--   grid_smoke columns (a separate fixture depot, three sim-hours) moved nothing; why was not looked into, since a
--   column that did not move is not one 0521 could have broken.

-- ══ §4 THE NEXT VALIDATION RUN, PREDICTED BEFORE IT STARTS ══════════════════════════════════════════════════════
--
--   PREDICTED on the next busy_day operator run: (a) every sensor start is stamped with a dcfc or l2 stall the car has
--   a charge session on (66 of 72 on c4afb873); (b) no sensor start is on staging, in a bay or on no stall (6 of 72);
--   (c) the inspections of cars held on the intake row with nothing to charge are started by technicians, so the
--   technician pool is busier in the first half hour than on c4afb873 -- read, not predicted in size: how long those
--   cars wait for one, since the opening burst is when the pool is shortest.

\echo '=== 0390 §4(a)(b) — the first operator run after 0521: every sensor start, by the kind of stall stamped ==='
WITH r AS (SELECT sr.sim_run_id FROM public.ottoq_sim_runs sr
            WHERE sr.run_by = 'operator_demo' AND sr.payload->>'playback_mode' = 'live'   -- G248: not a fixed-cadence run
              AND sr.payload->'seed_fleet'->>'ok' = 'true'                                -- G249: not an unseeded run (0392)
              AND sr.started_at > (SELECT classified_at FROM public.ottoq_cert_lineage
                                    WHERE name = '0521_the_charger_s_sensors_see_only_a_car_on_a_charger')
            ORDER BY sr.started_at LIMIT 1),
starts AS (
  SELECT vn.sim_run_id, vn.vehicle_id, COALESCE(x->>'status','pending') AS st, (x->>'sensor_stall_id')::uuid AS stall
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id = (SELECT sim_run_id FROM r) AND x->>'performed_by' = 'charger_sensors'
  UNION ALL
  SELECT vn.sim_run_id, vn.vehicle_id, 'returned to pending (0519)', (i->>'stall_id')::uuid
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x, jsonb_array_elements(x->'interrupted') i
   WHERE vn.sim_run_id = (SELECT sim_run_id FROM r))
SELECT left(st.sim_run_id::text, 8) AS run, COALESCE(s.stall_type::text, '(no stall)') AS sensor_stall, st.st AS outcome,
       count(*) AS starts,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ocpp_sessions os
                                       WHERE os.sim_run_id = st.sim_run_id AND os.vehicle_id = st.vehicle_id
                                         AND os.stall_id = st.stall)) AS with_a_session_there
  FROM starts st LEFT JOIN public.stalls s ON s.id = st.stall
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- READ (2026-09-27 13:25 UTC, 8:25 AM CT; the run is 6ddd827e, the first live, seeded operator run after 0521, ended by
--   the governor at 540 sim-minutes): (a) HOLDS -- 209 sensor starts, every one stamped with a DCFC or L2 stall the car
--   had a charge session on: DCFC 88 done and 1 returned to pending by 0519 (a charge fault, 0388 §4(b)), L2 120 done.
--   (b) HOLDS -- none on staging, in a bay or on no stall (6 of 72 on c4afb873 before 0521).

\echo '=== 0390 §4(c) — interior inspections by who did them and whether the visit charges, with the wait from arrival ==='
WITH r AS (SELECT sr.sim_run_id FROM public.ottoq_sim_runs sr
            WHERE sr.run_by = 'operator_demo' AND sr.payload->>'playback_mode' = 'live'   -- G248: not a fixed-cadence run
              AND sr.payload->'seed_fleet'->>'ok' = 'true'                                -- G249: not an unseeded run (0392)
              AND sr.started_at > (SELECT classified_at FROM public.ottoq_cert_lineage
                                    WHERE name = '0521_the_charger_s_sensors_see_only_a_car_on_a_charger')
            ORDER BY sr.started_at LIMIT 1),
insp AS (
  SELECT vn.sim_run_id, vn.arrived_at, (x->>'started_at')::timestamptz AS started_at, x->>'performed_by' AS performed_by,
         EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) c WHERE c->>'svc' = 'charge') AS visit_charges
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id IN ((SELECT sim_run_id FROM r), 'c4afb873-ce23-4ae7-b167-9fda79961fc7')
     AND x->>'svc' = 'interior_inspection' AND x ? 'started_at')
SELECT left(sim_run_id::text, 8) AS run, COALESCE(performed_by, '(technician)') AS by, visit_charges, count(*) AS n,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM started_at - arrived_at) / 60)::numeric, 1) AS p50_wait_min,
       round(percentile_cont(0.9) WITHIN GROUP (ORDER BY extract(epoch FROM started_at - arrived_at) / 60)::numeric, 1) AS p90_wait_min,
       round(max(extract(epoch FROM started_at - arrived_at) / 60)::numeric, 1) AS max_wait_min
  FROM insp GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- BASELINE (2026-09-27 09:10 UTC, c4afb873 before 0521): technician, no charge 6 (p50 2.9 min, p90 4.9, max 5.5);
--   technician, charging visit 3 (the exit catch-up, p50 2.0); charger_sensors, no charge 3 (p50 7.0 -- all three G246's
--   false credits, cars on staging or on no stall); charger_sensors, charging visit 60 (p50 4.6, p90 40.6, max 67.0 --
--   the wait for the charge itself). After 0521 the third row can hold only a car really on a charger under a visit with
--   no charge left (one still parked on its charger after the charge); §4(a)(b) says whether any is.
-- READ (2026-09-27 13:25 UTC, 6ddd827e complete): technician, no charge 12 (p50 3.6 min, p90 243.1, max 267.5);
--   technician, charging visit 2 (p50 10.4); charger_sensors, charging visit 188 (p50 15.4, p90 207.4, max 474.1 -- the
--   wait for a charger on a busy day, which the inspection rides); charger_sensors, no charge: none -- the third row is
--   gone, as 0521 intended. (c) HOLDS for 9 of the 12: technicians took the no-charge inspections within minutes. The
--   other 3 are the p90: they waited 240 minutes for the deploy gate's escape hatch, because the twin never offered them
--   to a technician while their cars waited for a bay (G251, `db/checks/0394`, fixed by 0526).
