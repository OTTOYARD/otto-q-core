-- =====================================================================
-- 0090  The two-lane cadence, and the scheduler that went quiet
-- =====================================================================
-- §1  ROUND 12 — 0180 certified, six of six, nothing moved
-- ---------------------------------------------------------------------
-- Twelve pairs, six columns, two each, every hash single-valued within
-- its column, every run passed, every cell identical to round 11. 0180's
-- prediction held on all 24 hash comparisons with NO column permitted to
-- move. Canons in db/canons/round12.md.
SELECT r.scenario_code, r.random_seed AS seed, r.tick_count AS ticks,
       count(*)/2 AS pairs,
       count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_cmd') AS d_cmd,
       count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_dec') AS d_dec,
       count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_bkg') AS d_bkg,
       count(DISTINCT r.validation_notes::jsonb->'arm_b'->>'h_nrg') AS d_nrg,
       count(*) FILTER (WHERE r.validation_notes::jsonb->>'outcome' <> 'passed') AS not_passed
  FROM ottoq_sim_runs r
 WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-03 17:18:00+00'
   AND r.started_at < '2026-09-03 21:40:00+00'
 GROUP BY 1,2,3 ORDER BY 1,2,3;

-- §2  THE TWO-LANE PROBE PASSED — and why wall time did not decide it
-- ---------------------------------------------------------------------
--   before 0180:  fixture lane blocked 75 s+, killed at 60 s, waiting on
--                 a tuple lock on vehicle_need_profile and a
--                 transactionid ShareLock on the flagship pair's xid
--   after  0180:  12.5 s, completed, every assertion green,
--                 pair_verdict_passed equal=true
--
-- db/checks/0089 §4 fixed the pass condition BEFORE the re-run and
-- excluded wall time on purpose: "a fast run that happened not to
-- collide proves nothing about isolation." The control that settles it
-- was taken AFTER the fixture lane finished:
--
--   now 21:55:17   flagship_still_running   1
--                  flagship_elapsed_s     438
--                  flagship_pairs_committed 0
--                  fixture_pairs_committed  1
--
-- The fixture lane STARTED AND COMMITTED while the flagship's
-- transaction was still open and uncommitted. Before 0180 that was
-- impossible by construction - it had to wait for the flagship's commit.
-- The claim is met by ENTAILMENT, not by a stopwatch, which is the
-- distinction 0089 insisted on in advance.
--
-- Anti-vacuity, the 0066 §6 rule applied to this probe: had the flagship
-- already committed, the two lanes would have been SEQUENTIAL and the
-- result meaningless. flagship_pairs_committed = 0 is what rules that
-- out. A probe that cannot distinguish concurrent from sequential is not
-- a probe.

-- §3  A SEPARATE, LARGER FINDING: A CERT PAIR HALTS pg_cron
-- ---------------------------------------------------------------------
-- Two attempts to run the second lane AS A CRON JOB (lane2b, lane2c)
-- never fired - no cron.job_run_details row at all, the silent shape
-- recorded in round 11. My first theory was insufficient lead time. That
-- was WRONG: lane2c had 129 s of lead and still never fired.
--
-- What the ledger actually shows: pg_cron launched NOTHING from 21:48:00
-- onward, while ottoq-demo-metronome is scheduled '* * * * *' and had
-- fired at :44, :45, :46, :47, :48. Five-plus consecutive missed
-- minutes. Every alternative cause was measured and excluded:
--
--   jobs disabled?        NO - all active=true, metronome included
--   worker exhaustion?    NO - 1 bg worker of max_worker_processes=6
--   job-slot cap?         NO - cron.max_running_jobs=32, one running
--   launcher lock-blocked? NO - pg_cron launcher alive, blocked_by=0,
--                          no wait_event
--
-- 21:48:00 is EXACTLY when the flagship certification pair started.
-- ottoq-depot-tick and ottoq-run-governor stopped with the metronome.
--
-- This is NOT 0180's doing and is NOT fixed by it. 0180 removed a
-- row-lock collision; this is the scheduler itself going quiet. Same
-- family as the ottoq_start_demo_run blockage in 0089 - a certification
-- habit with production consequences - but a different mechanism and a
-- wider blast radius: WHILE A CERT PAIR RUNS, THE PRODUCTION TICK
-- SCHEDULE STOPS.
--
-- CAUSATION CONFIRMED, not inferred. The confirming observation was
-- taken the moment the pair committed:
--
--   21:55:17  pair_running 1  last_cron_launch 21:48:00  launches_since 0
--   21:56:50  pair_running 0  last_cron_launch 21:56:06  launches_since 5
--             flagship_pairs_committed 1
--
-- pg_cron was silent for the entire 21:49-21:55 window and resumed in
-- the SAME MINUTE the pair committed, then caught up. The scheduler
-- stops for exactly the duration of a certification pair.
--
-- Recorded as an open investigation, not a fix: the mechanism is not yet
-- named. What IS established is the effect, its exact extent, and that
-- every cheap alternative explanation was measured and excluded.
SELECT to_char(max(d.start_time) AT TIME ZONE 'UTC','HH24:MI:SS') AS last_cron_launch,
       count(*) FILTER (WHERE d.start_time >= '2026-09-03 21:49:00+00') AS launches_after_pair_started
  FROM cron.job_run_details d;

SELECT jobname, schedule, active FROM cron.job
 WHERE jobname IN ('ottoq-demo-metronome','ottoq-depot-tick','ottoq-run-governor')
 ORDER BY jobname;

-- §4  METHOD CORRECTION, kept because it produced §3
-- ---------------------------------------------------------------------
-- Probe 1 worked because the fixture smoke ran INLINE from a client
-- session. Moving it to a cron job this round was my error - and it is
-- exactly what exposed the pg_cron stall. Had I repeated the working
-- method, §3 would still be invisible.
--
-- The correct probe method, recorded so the next one does not
-- rediscover it: FLAGSHIP VIA CRON, SECOND LANE INLINE FROM A SESSION.
