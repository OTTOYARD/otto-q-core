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

-- =====================================================================
-- §5  REFUTATION, 22:07 UTC — §3's GENERAL CLAIM IS WRONG
-- =====================================================================
-- §3 frames the stall as a general hazard of long work in pg_cron. A
-- controlled experiment, with its interpretation fixed in advance,
-- refutes that.
--
-- probe_sleeper - a cron job whose entire body is SELECT pg_sleep(90),
-- touching nothing - ran 22:01:00 -> 22:02:30, a full 90 seconds.
-- During that window:
--
--   ottoq-demo-metronome  '* * * * *'    fired 22:02:00  ON TIME
--   ottoq-depot-tick      '*/2 * * * *'  fired 22:02:00  ON TIME
--   ottoq-run-governor    '*/2 * * * *'  fired 22:02:00  ON TIME
--
-- A LONG-RUNNING pg_cron JOB DOES NOT STALL THE LAUNCHER. Duration is
-- not the cause. "Don't run long work in pg_cron" is not the lesson, and
-- §3's proposed mitigation - that cert pairs must not run as cron jobs -
-- is NOT established.
--
-- WHAT SURVIVES: the effect. No cron job of any kind launched between
-- 21:49 and 21:55, and the metronome resumed at 21:55:54, the minute the
-- pair committed. That was measured JOIN-FREE over cron.job_run_details,
-- so it is not an artifact of the query bug below.
--
-- WHAT IS REFUTED: the generalisation. The cause is specific to what a
-- certification pair DOES - it holds a long transaction AND writes
-- shared tables; a sleeper does neither.
--
-- WHAT REMAINS UNNAMED: the mechanism. The shape of the evidence is the
-- clue: during the stall there were NO RUN ROWS AT ALL, not rows sitting
-- blocked. Jobs merely waiting on the pair's row locks would still have
-- been dispatched and recorded. So the launcher was not dispatching, and
-- the sleeper proves a busy job alone does not cause that. Not guessed
-- here.
SELECT d.jobid,
       to_char(d.start_time AT TIME ZONE 'UTC','HH24:MI:SS') AS started,
       to_char(d.end_time   AT TIME ZONE 'UTC','HH24:MI:SS') AS ended,
       d.status,
       (SELECT j.jobname FROM cron.job j WHERE j.jobid=d.jobid) AS name_if_still_scheduled,
       left(COALESCE(d.command,''),50) AS cmd
  FROM cron.job_run_details d
 WHERE d.start_time BETWEEN '2026-09-03 22:00:00+00' AND '2026-09-03 22:04:00+00'
 ORDER BY d.start_time;

-- §6  A QUERY BUG WORTH KEEPING
-- ---------------------------------------------------------------------
-- The first read of this experiment used
--   FROM cron.job_run_details d JOIN cron.job j USING (jobid)
-- and showed NO probe_sleeper row - which read as "the sleeper never
-- fired". It HAD fired, for the full 90 s.
--
-- A self-unscheduling job DELETES ITS OWN cron.job ROW, so an inner join
-- silently drops every run it ever made. The same join also hid lane2a's
-- and lane2c's history.
--
-- Same family as the traps already collected here (0062's comment-grep,
-- 0066 §6's two false negatives, 0175's lookup that could only miss): a
-- query that cannot see the thing it is looking for returns an answer
-- that LOOKS like evidence of absence. Read cron.job_run_details
-- join-free and resolve the name with a scalar subquery.
