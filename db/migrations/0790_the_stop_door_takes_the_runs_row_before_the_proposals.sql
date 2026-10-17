-- migration-version: PENDING
-- migration-name:    the_stop_door_takes_the_runs_row_before_the_proposals
--
-- 0790  **The stop door takes the live run's row before the run's proposals, the order the metronome's beat takes them
--        in, so a stop during a beat waits for the beat instead of deadlocking with it.** (G440)
--        The foreign-key wait behind 0450 §5's 7.35-second decision insert (G490) is measured here and NOT changed: the
--        first draft of this file weakened the tick's own row lock to fix it, and two refuters showed that lets a proposal
--        commit in the middle of a beat, after which the decide step records the wrong proposal as enacted (§1 (b)).
--        Two defects its review found are recorded and NOT changed here (§3, §5): the prior-run purge never locks the runs
--        it chooses, so a run resumed mid-purge is deleted while running, and a stop on that run inside the window now
--        deadlocks with a lone purge (G491); and ottoq_pause_run and ottoq_resume_run rewrite a stopped run's status (G492).
--        This file WIDENS G492 for the pause (§4): a pause that arrives during a stop's dispose used to commit first and
--        be completed by the stop, and now waits and writes 'paused' over 'completed'. 0791 closes G492, so apply 0791
--        with this file or before it.
--
-- ══ §1 WHY (measured 2026-10-14, read-only: the catalog, c5f4ff34's tables and the database's log) ═══════════════════
--
--   Line numbers of ottoq_decide_tick in this file are its PL/pgSQL lines as they were on 2026-10-14, the ones the log
--   quotes: A3 at 1226-1243, its enact UPDATE at 1228, its supersede at 1237, its dispose call at 1244. 0727 (applied
--   2026-10-17 07:29 UTC) moved them ten lines down, to 1238, 1247 and 1254, without changing A3: the span from its
--   '  -- A3: close' anchor to the dispose call still has md5 7bef452b (re-read 2026-10-17 14:24:11 UTC, 9:24 AM CT),
--   which is how the test pins it.
--
--   (a) THE STOP DOOR'S DEADLOCK (G440, 0450 §6), from the log. public.ottoq_sim_stop_and_reset disposes the run's
--   pending proposals (ottoq_dispose_external_proposals(run, NULL, NULL, true), an UPDATE of ottoq_external_proposals) and
--   only then updates the run's row (ottoq_sim_mark_stopped). The metronome's beat locks the run's row first (the world
--   step's first statement, FOR UPDATE) and writes the same proposals in its decide step (ottoq_decide_tick's UPDATE ...
--   SET status='enacted', its dispose, or the seat proposer's supersede). One order each way, so a stop during a beat is
--   a cycle:
--     16:42:42.981 UTC  door (operator start -> run_scenario line 81 -> stop_and_reset -> mark_stopped) waits on the
--                       metronome's transaction 33080312 for the run's row (25,17) of 1f325969; the metronome waits on
--                       the door's transaction 33080341 "while updating tuple (1674,1) in relation
--                       ottoq_external_proposals" at ottoq_decide_tick line 1228. The metronome's decide is the victim.
--     16:40:04.205 UTC  the same door edge on the run's row (1,28); the metronome's edge was not logged (the door was
--                       chosen first). It was released before decide_tick's line 53 (its next line, 0.2 s later), and the
--                       only rows the door had written by then were the run's proposals (and their disposition-ledger
--                       rows). The decide step writes those before decide_tick too (ottoq_service_priority_propose ->
--                       ottoq_submit_external_proposal supersedes a car's pending proposal by UPDATE), so that is the
--                       likely edge; it is not in the log. The door is the victim.
--   Nothing else in the door's transaction is in the cycle: ottoq_operator_start_run's advisory lock (the recert
--   runner's key) is taken by no function on the metronome's path (the census of pg_advisory* calls: the metronome takes
--   none), and ottoq_sim_run_scenario writes nothing the beat writes before it reaches the stop (an ON CONFLICT DO
--   NOTHING on ottoq_scenarios, which only it and twin.ottoq_grid_fixture_create write; the rest are reads).
--
--   (b) THE FOREIGN-KEY WAIT (G490), AND WHY THIS FILE DOES NOT TOUCH IT. 58 foreign keys on 58 tables reference
--   public.ottoq_sim_runs(sim_run_id) (pg_constraint, contype 'f', 2 of them NOT VALID; read 23:07:25 UTC, 6:07 PM CT;
--   the first draft's "61" did not reproduce), ottoq_decisions and ottoq_external_proposals among them. Every insert
--   into one of them checks the key with
--     SELECT 1 FROM ONLY "public"."ottoq_sim_runs" x WHERE "sim_run_id" OPERATOR(pg_catalog.=) $1 FOR KEY SHARE OF x
--   and FOR KEY SHARE conflicts with FOR UPDATE alone (PostgreSQL 17, the version live runs, 17.6: "Conflicting
--   Row-Level Locks", https://www.postgresql.org/docs/17/explicit-locking.html#LOCKING-ROWS, read 2026-10-17; the 16
--   page the scratch tests run against says the same, read 2026-10-14). The world step and both charger-fault doors take
--   the live run's row FOR UPDATE, and the metronome commits a beat after its world and decide steps, so while a beat
--   is in flight every insert from another session that references the live run waits for it.
--   On c5f4ff34, 36 of the run's 239 agent decision inserts began inside a world step and waited a mean 4.14 s (p50
--   4.26, p90 6.16, max 8.13); 27 begun in the 5 s after a decide beat's world step a mean 1.76 s (max 7.345, 0450 §5's
--   insert); the other 176 a mean 0.07 s. Each wait runs from the decision's created_at to its pass's evidence row, so
--   it is an upper bound on the insert's wait, not the wait itself. 0450 §8 and (9) carry the split and the bound
--   (re-read 23:09:23 UTC, 6:09 PM CT).
--   The first draft took those three sites FOR NO KEY UPDATE, which a key check does not wait on. It is withdrawn,
--   because the wait is load-bearing. Under FOR UPDATE no row that references the run can be inserted by another session
--   during a beat, and the world step's first statement also waits for any inserter already in flight (FOR UPDATE and FOR
--   KEY SHARE conflict both ways), so the decide step's set-based statements read a frozen set of such rows. One of them
--   is ottoq_decide_tick line 1228 (A3), which marks enacted every pending proposal of the run whose (entity, source)
--   matches an enacted decision of this tick, with no reference to the proposal the kernel took; and
--   ottoq_submit_external_proposal supersedes a car's pending proposal by UPDATE and then INSERTs the new one, with no
--   lock on the run's row. So with the weaker lock, a proposer's batch that resubmits for a car the beat has just
--   enacted commits mid-beat, and line 1228 marks the NEW proposal enacted while the one the kernel took reads
--   'superseded / newer_proposal_same_entity'; ottoq_proposal_disposition_ledger (class evidence, survives the purge,
--   captures stall_id) keeps the stall the kernel never chose. Two refuters reproduced it on scratch, 3 of 3 runs
--   each way, and tests/test_tick_lock_sql.py now carries it on the eleven live bodies (md5-pinned) with decide_tick's
--   A3 verbatim (md5-pinned too; the withdrawn half is applied by the test to a throwaway database only). Under FOR
--   UPDATE the same interleaving is a deadlock: the batch's insert waits on the run's row, which the beat holds, and
--   line 1228 waits on the row the batch superseded. One side loses with 40P01: the batch, or the beat's decide with
--   every enactment of that tick. PostgreSQL does not fix which ("Exactly which transaction will be aborted is
--   difficult to predict and should not be relied upon", PostgreSQL 17, 13.3.4,
--   https://www.postgresql.org/docs/17/explicit-locking.html#LOCKING-DEADLOCKS, read 2026-10-17; the same sentence on
--   the 16 page, read 2026-10-15). A waiter looks
--   for a deadlock when it has waited deadlock_timeout (1 s on live, read 2026-10-14 23:59:36 UTC), and the first
--   waiter to look after the cycle has closed is the one aborted: usually the batch, which began waiting first, and the
--   beat when its own wait begins more than that long after the batch's (giving the batch's session a 3 s
--   deadlock_timeout makes the beat lose every time on scratch). Either way the ledger records no proposal the kernel
--   did not take: the batch's one sub-transaction rolls back and the old proposal reads 'enacted', or the decide rolls
--   back, nothing is enacted, the old proposal reads 'superseded / newer_proposal_same_entity' and the new one waits
--   pending for the next beat (the test forces each side by deadlock_timeout and also runs the race at 1 s). The weaker
--   lock would have turned a visible, retried deadlock into a silent mislabel of evidence.
--   That interleaving is constructed by the test. The 17:34:06 UTC deadlock in the log is of the same class and is not
--   that case. What can be read of it (read 2026-10-15 between 01:25:14 and 01:34:42 UTC, 8:25-8:34 PM CT on 10-14):
--   the one log line is PostgREST's pid 3655901, ottoq_proposer_submit_batch line 37 -> ottoq_submit_external_proposal
--   line 64 (its INSERT's key check), "detected deadlock while waiting for ShareLock on transaction 33105693 after
--   1000.105 ms", at 17:34:06.298 on c5f4ff34's row (1,24) of ottoq_sim_runs, "Process holding the lock: 3658494", which
--   cron.job_run_details names as job 12, CALL public.ottoq_demo_metronome(50), started 17:34:00.282999. So the batch's
--   key check waited on the run's row held by the beat, from about 17:34:05.298. The batch was forward_lex's, the CP-SAT
--   proposer's (ottoq_proposer_fire_log fire 15859: begun 17:34:05.295311, 13 rows, status error, '40P01: deadlock
--   detected'). The beat's edge was not logged, and it was not line 1228: in ottoq_proposal_disposition_ledger, for
--   c5f4ff34's tick 594 (the beat's transaction began 17:34:01.781348, the rows' captured_at; its world step 03.786757,
--   ottoq_tick_clock_log), line 1228 enacted c57852e7 at 17:34:05.829024 and line 1237 superseded 4 rows at
--   05.830803-05.831284, both while the batch was already waiting, and the dispose was entered at 06.300286 (the 11
--   rows it refused carry its v_wall), after the batch had been aborted.
--   G490's fix therefore needs, before the tick's lock is weakened: one lock order for proposal writers
--   (ottoq_submit_external_proposal taking the run's row FOR SHARE before its supersede, which a refuter tested correct
--   on scratch for this interleaving) or line 1228 scoped to the proposal the kernel took; AND an audit of every
--   set-based statement in the beat over rows that reference the run, since the log shows other sessions writing such
--   rows during beats (the agent's decisions, and proposers' batches such as forward_lex's, through PostgREST;
--   ottoq_cron_tick's cuopt_invocation_log and ottoq_cuopt_deferrals through pg_cron) and the deferral arm and
--   hold-or-spend and the dispose were all written against the frozen view. Not this file.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   One function, two anchored patches, each anchor asserted to match exactly once, the function md5-guarded:
--   ottoq_sim_stop_and_reset takes a running run's row FOR NO KEY UPDATE before it disposes the proposals: the beat's
--   order. A stop during a beat now waits for the beat to commit and then disposes what is left; a beat that starts
--   during a stop waits for the stop and then finds the run stopped (the world step reads the row's status after its
--   lock and answers completed). It takes the row under the 8 s mark_stopped already gives the same row, and puts the
--   caller's lock_timeout back before the teardown goes on, so every other statement runs under the setting it ran
--   under before (mark_stopped still sets 8 s from there on, as it did). The fix is in the stop, so every caller gets
--   it: the operator start (through ottoq_sim_run_scenario), the cockpit's Stop, the governor, the metronome's own
--   ceiling stop, and the harness arms that stop their own runs. The world step and both fault doors are not touched
--   (§1 (b)). Only a running run: the statement carries status = 'running', and a stop on a run in any other status
--   (paused, completed, aborted) takes no lock before its dispose, exactly as before (§3 says why). That keeps the door
--   out of the prior-run purge's way on every run the purge chooses and that stays not running, but not on a run the
--   purge chose while it was paused and that is resumed before the purge deletes it: the door reads that run as running
--   and takes its row first, and a lone purge then deadlocks with it (§3, G491, open; before this file both finish, and
--   the purge deletes the running run). Nothing else in the function moves (V1 reverses both patches and compares the
--   whole definition, header included, with the snapshot). A lock wait that runs out raises where the same row's lock
--   already raised before (mark_stopped's UPDATE), now before the door has touched anything.
--
-- ══ §3 WHY FOR NO KEY UPDATE, AND NOT FOR UPDATE; AND WHY ONLY A RUNNING RUN ═════════════════════════════════════════
--
--   It conflicts with the FOR UPDATE the world step and both fault doors take, so the door and a beat (or a fault door)
--   serialize, in the beat's order. It does not conflict with a key check, and neither did anything the door held
--   before: its first lock on the row was mark_stopped's UPDATE, which takes this same mode because it assigns no key
--   column. FOR UPDATE would add a cycle the door does not have today: a proposal writer that supersedes (a row lock on
--   the old proposal) and then inserts (a key check on the run) would wait on the door while the door's dispose waits on
--   the superseded row (the test runs that interleaving: before this file and after it both finish, and with the door's
--   lock taken FOR UPDATE one of them gets 40P01). And the door now holds the row while it disposes, so a session that
--   wrote the run's proposals and then wanted the row in a mode this one conflicts with (an UPDATE or DELETE of it, or
--   FOR SHARE and stronger) would be a new cycle.
--   Read on live 23:11:32 UTC (6:11 PM CT), comment-stripped over public, twin and ottoq: 39 functions update or lock
--   ottoq_sim_runs, and none of them writes ottoq_external_proposals itself (P2 asserts it). Two of them call a
--   proposal writer: ottoq_sim_decide_and_dispatch, which under the otto_q policy updates the run's row before its
--   first proposal writer (position 1791, against 2691 for the first, ottoq_reoptimize_reservation_book) and under the
--   other policies does not take the row at all, and ottoq_determinism_pair_replay, a certification harness on its own
--   run (§4). Of the ten functions that write the proposals, one calls a writer of the run's row: ottoq_cron_tick,
--   whose twin.ottoq_world_advance comes before its proposal sweep (308 against 427). So every writer that census can
--   read takes the beat's order or no order. The census is static: it reads the statements written out in a function's
--   source, and cannot see a statement built at run time. One writer that builds its statements takes the other order.
--   ottoq_purge_prior_runs (the demo start's last step, and granted EXECUTE to authenticated and service_role: read
--   2026-10-15 00:16:48 UTC, 7:16 PM CT) deletes a run's rows in every run-scoped table by dynamic SQL, children first,
--   the proposals among them, and the run's row last, by a DELETE, which conflicts with every row lock. The first
--   version of this file took any run's row first, and a stale stop on a stopped run that still had a pending proposal,
--   arriving in the middle of that purge, then held the run's row while its dispose waited on a proposal the purge had
--   deleted, and the purge's DELETE waited on the door: a deadlock this file added (found by a reviewer on scratch; the
--   test runs it: before 0790 both finish, under the first version one gets 40P01). Pending proposals do outlive their
--   runs: ottoq_cron_tick's hygiene sweep expired 3 on runs no longer running, 2026-09-27 to 09-29 (the evidence
--   ledger, read 2026-10-15 00:03:30 UTC). So the door takes the row first only while the run is running, the one
--   status a beat ticks, and the purge chooses its runs once with status <> 'running' (read live 00:13:28 UTC; P2
--   asserts that statement and that the purge deletes the rows of those runs and no others).
--   That keeps a running run out of the purge's choice. It does not keep the purge off a run that is running when the
--   purge deletes it: the purge never locks the runs it chooses and never re-checks their status, and its last
--   statement deletes them by sim_run_id = ANY(v_doomed) alone (live md5 46f1f29f, read 2026-10-15 01:25:14 UTC, 8:25 PM
--   CT on 10-14). A paused run it chose and that is resumed before that DELETE (ottoq_resume_run's UPDATE, or the twin
--   app's PATCH in edge-functions/otto-twin-control, each of which goes straight through on the unlocked row) is
--   deleted while running, before this file as after it. And a stop on that run inside the window now reads it as
--   running and takes its row first; its dispose then waits on a proposal the purge deleted, and the purge's DELETE
--   waits on the door: a deadlock with a lone purge that this file adds (the test runs it: before 0790 both finish, the
--   running run is deleted and the door marks nothing; after, one of them gets 40P01, on scratch the door in 13 of 13
--   draws, 10 with the PATCH and 3 with the live ottoq_resume_run, and the purge then deletes the running run all the
--   same). Only a direct call of the purge reaches it: its one caller in the database, ottoq_start_demo_run, marks
--   running and paused runs aborted before it purges, so a resume waits behind that UPDATE and then finds the run
--   deleted (on scratch, the PATCH and the live ottoq_resume_run both; on live the latter then fails with 23503, its
--   event naming a run that is gone: G492); no cron job and no client in this repo calls the
--   purge; and on live authenticated and service_role may EXECUTE it (read 01:25:14 UTC, unchanged at 2026-10-15
--   12:39:02 UTC, 7:39 AM CT), authenticated until pending 0701 revokes it. The fix is the purge's, not the door's
--   (G491, §5).
--   Of 28 plpgsql functions with dynamic SQL, 3 read the run-scope registry (read 00:13:49 and 00:13:56 UTC): the purge;
--   ottoq_evidence_join_loss, which neither names the proposals nor writes or locks the run's row; and the nightly
--   ottoq_retention_purge_runs, which chooses its runs the same way as the purge, whose allowlist (7 tables, read
--   00:14:08 UTC) does not hold the proposals, and which never deletes a run's row (it refuses an allow-listed table
--   that is the parent of a NO ACTION foreign key, and its source deletes no ottoq_sim_runs row; md5 890d2de1, read
--   01:36:24 UTC).
--   Not mark_stopped's predicate (running or paused): the purge takes paused runs too, so taking a paused run's row
--   first adds the same deadlock for a paused run (the test runs it). For a paused run this file changes nothing, and
--   that includes a deadlock it leaves where it was. ottoq_start_demo_run first marks every running and paused run
--   aborted (an UPDATE of their rows) and purges them afterwards, the opposite order to the purge called on its own
--   (md5 45c9519e, read 00:16:48 UTC), so a stop on a paused run deadlocks with the demo start before and after 0790,
--   and finishes beside a lone purge before and after while it stays paused. No door order is safe against both while
--   those two take a paused run in opposite orders; that needs the purge to take its runs' rows first (G491), not this
--   file. A stop on a running run and the demo start now take the row in the same order: they deadlocked before 0790
--   and serialize after (the test runs all of it).
--   The mode promises the holder will not delete the row or change a key column. The key columns, for a row lock, are
--   those under a unique index a foreign key can use, partial and expression indexes excluded (the page above):
--   sim_run_id (the primary key) and sim_run_seq (unique); ottoq_one_running_run_per_depot is partial (P2 asserts the
--   set). Comment-stripped over public, twin and ottoq, no UPDATE of ottoq_sim_runs assigns either column, and the one
--   DELETE of the table is ottoq_purge_prior_runs (prior runs, called by the demo start), which the door does not reach
--   (P2 asserts all three). mark_stopped UPDATEs status, ended_at, next_tick_due_at and failure_reason: no key. And if
--   a later statement ever did, PostgreSQL takes the stronger lock there, so the mode can cost a wait, never a wrong
--   row.
--
-- ══ §4 forces_recert FALSE; forces_dial_restart FALSE ════════════════════════════════════════════════════════════════
--
--   A row lock decides only which other sessions wait, and the statement added reads nothing into any variable. Every
--   certified output is computed inside one function call, so inside one transaction: ottoq_determinism_pair runs both
--   arms in one, and so do the dial and A/B pairs and the sweep and tick-invariance arms. The run row an arm ticks is one
--   it inserted itself and has not committed, which no other session can see, and every harness that stops a run stops
--   its own (stop_and_reset(v_run, '..._arm_complete'), read 2026-10-14), so the new lock never waits inside an arm and
--   the arm reads and writes the same rows at the same moments; none of the fourteen atoms reads a lock; lock_timeout is
--   put back to what it was. Dial pairs score KPIs from the same single-transaction arms: FALSE.
--   On a live run this is not timing alone, and the difference is the point: a stop that lands during a beat used to end
--   with one side losing to 40P01 (the door's start retried, or the beat's decide lost, its enactments rolled back); now
--   the beat commits, its enactments stand, and the stop expires only what the beat left pending ('run_finalized'). A
--   beat that starts during a stop's dispose used to take the row at once and then deadlock with it; now it waits and
--   finds the run stopped (the test runs it: before this file one of the two gets 40P01; after it the beat's world step
--   answers completed, no decide runs, the proposals expire 'run_finalized' and the tick count does not move). Not on a
--   paused run, which this file leaves as it was: the door takes no early lock on one, so if the run is resumed during
--   the stop's dispose and a beat starts, the two still deadlock, before this file and after it (G440's residual, which
--   the test runs; on scratch the beat's decide or the stop itself loses, by timing). Step (2) of G491's fix, the early
--   lock widened to a paused run, closes it: on scratch the resume then waits behind the stop and no beat finds a
--   running run (the live ottoq_resume_run would then write running over completed, until 0791). The inserts that reference
--   the run never waited for the door before and do not now (§3). A writer of the run's row itself (the agent's lease,
--   ottoq_set_playback) now waits from the door's first statement rather than from mark_stopped, one dispose longer, and
--   §3's census shows none of them holds a proposal as it waits.
--   ONE OF THOSE WRITERS IS THE OPERATOR'S PAUSE, AND FOR IT THE LONGER WAIT IS NOT TIMING ALONE (G492). ottoq_pause_run
--   (live md5 1e3ec33a) reads the status without a lock and updates the run's row by sim_run_id alone. Before this file
--   nothing held a running run's row during the stop's dispose, so a pause arriving then committed first and
--   mark_stopped completed the paused run: it ended 'completed'. After it the pause reads 'running', waits behind the
--   door's early lock, and once the stop commits writes 'paused' over 'completed', with ended_at already set (a
--   reviewer's reproduction on scratch with the live body, and the test runs it both ways). So this file widens G492's
--   window for the pause from mark_stopped's UPDATE back to the door's first statement. The resume's is unchanged: the
--   door takes no early lock on a paused run. 0791 closes G492 (the pause and the resume update only while the status
--   is still the one they read), so 0791 is applied with this file or before it.
--   A stop on a run that is not running takes no lock before its dispose and runs exactly as it did before.
--
-- ══ §5 NOT IN THIS FILE ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - G490, the foreign-key wait: §1 (b). An insert that references the live run still waits for the beat's commit.
--   - G491, OPEN: the prior-run purge chooses its runs without locking them and deletes them without re-checking their
--     status (§3). A run it chose while paused and that is resumed before it deletes the runs' rows is deleted while
--     running, before this file as after it; a stop on that run inside the window deadlocks with a lone purge since
--     this file (before it, both finish); and a stop on a paused run still deadlocks with ottoq_start_demo_run's
--     abort-then-purge, as before. Closing it needs the purge to take its doomed runs' rows first, with their status
--     re-checked under the lock (on scratch, against the stub purge so changed, a resume mid-purge then waits and
--     updates nothing); then the door's early lock widened to a paused run, which with the first ends the paused run's
--     deadlock with the demo start too (on scratch; the first alone does not); and pending 0701's revoke of
--     authenticated's EXECUTE on the purge.
--   - G492, OPEN, WIDENED BY THIS FILE FOR THE PAUSE (§4), CLOSED BY 0791: ottoq_pause_run (live md5 1e3ec33a) and
--     ottoq_resume_run (b693dc33) read the run's status without a lock and update its row by sim_run_id alone, so one
--     that waited behind a stop writes paused, or running, over the stopped run. On scratch with both live bodies:
--     behind a stop that has reached mark_stopped, before and after this file (the resume is refused with 23505 only
--     when the stop's transaction started another run at the depot); behind a stop still in its dispose, the pause
--     writes over the stop only after this file. 0791 (built, pending, on PR #248's branch) adds AND status =
--     'running' to the pause's UPDATE and AND status = 'paused' to the resume's, as the twin app's PATCH carries, and
--     returns its no-op answer when nothing is updated; apply it with this file or before it.
--   - G441 (a two-step start races the first tick) is untouched.
--   - The doors outside the stop that write into a live run (vehicle commands, approvals) are not swept (0552 §4).
--
-- ══ §6 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0790_pre' (one row);
--   DELETE FROM ottoq_cert_lineage WHERE name = '0790_the_stop_door_takes_the_runs_row_before_the_proposals'.
--
-- ══ §7 APPLY ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Dry-run every P block by hand against live in the window, before the apply (scripts/APPLYING.md step 3b): P0's
--   in-flight count, P1's md5 and each P2 premise as the SELECT it is. Done read-only 2026-10-17 14:25:53 UTC (9:25 AM
--   CT): P0 none in flight; P1 bc8ee182; every P2 premise held (keys sim_run_id and sim_run_seq; no key-column UPDATE;
--   the purge the one deleter, choosing only runs not running; FOR UPDATE at the world step and the two fault doors and
--   nothing FOR NO KEY UPDATE; mark_stopped and the dispose as read; no proposal writer that takes the run's row; the
--   metronome's world step before its decide with no COMMIT between; decide_tick's enact UPDATE). A reviewer's dry-run
--   at 2026-10-17 14:11 UTC (9:11 AM CT) passed every P0-P2 check too. Apply 0791 with this file or before it (§4).

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0790 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the definition this file patches ──
DO $pins$
DECLARE v_md5 text := md5(pg_get_functiondef('public.ottoq_sim_stop_and_reset(uuid,text)'::regprocedure));
BEGIN
  IF v_md5 IS DISTINCT FROM 'bc8ee182436dfcd6bd53f62547ad5d5e' THEN
    RAISE EXCEPTION '0790 P1: public.ottoq_sim_stop_and_reset(uuid,text) is not the definition this file was written against (md5 %)', v_md5;
  END IF;
END $pins$;

-- ── P2: the premises §1 (a) and §3 rest on ──
DO $premises$
DECLARE v_keys text; v_n int; v_fns text; v_src text; v_world int; v_decide int; v_doomed text;
BEGIN
  -- the key columns a row lock sees: unique, not partial, not an expression
  SELECT string_agg(a.attname, ',' ORDER BY a.attname) INTO v_keys
    FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
   WHERE i.indrelid = 'public.ottoq_sim_runs'::regclass AND i.indisunique AND i.indpred IS NULL AND i.indexprs IS NULL;
  IF v_keys IS DISTINCT FROM 'sim_run_id,sim_run_seq' THEN
    RAISE EXCEPTION '0790 P2: ottoq_sim_runs''s key columns are %, not sim_run_id and sim_run_seq', v_keys;
  END IF;
  IF to_regclass('twin.ottoq_sim_runs') IS NOT NULL OR to_regclass('ottoq.ottoq_sim_runs') IS NOT NULL THEN
    RAISE EXCEPTION '0790 P2: an ottoq_sim_runs outside public would capture the unqualified name below';
  END IF;
  -- no UPDATE of the table assigns a key column; the one DELETE is the prior-run purge
  SELECT count(*), string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_n, v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g'),
                        'UPDATE\s+(public\.)?ottoq_sim_runs\M[^;]*?(\mSET|,)\s*(\w+\.)?(sim_run_id|sim_run_seq)\s*=', 'gi') m
   WHERE n.nspname IN ('public', 'twin', 'ottoq');
  IF v_n > 0 THEN
    RAISE EXCEPTION '0790 P2: % UPDATE(s) of ottoq_sim_runs assign a key column (%)', v_n, v_fns;
  END IF;
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'twin', 'ottoq')
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
         ~* 'DELETE\s+FROM\s+(public\.)?ottoq_sim_runs\M';
  IF v_fns IS DISTINCT FROM 'public.ottoq_purge_prior_runs' THEN
    RAISE EXCEPTION '0790 P2: the functions that delete ottoq_sim_runs rows are %, not the prior-run purge alone', v_fns;
  END IF;
  -- §3's other order, which the census below cannot read: the purge deletes a run's rows by dynamic SQL and the run's
  -- row last. The door takes the row first only on a running run, so the purge must not choose one: it chooses its
  -- runs once, with status <> 'running' and no OR, and deletes the rows of those runs and of no others. It neither locks
  -- them nor re-checks their status, so a run resumed after the choice is deleted while running, and a stop on it in
  -- that window deadlocks with a lone purge (G491, open; this asserts the choice, which is all the purge has today)
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p WHERE p.oid = 'public.ottoq_purge_prior_runs(uuid)'::regprocedure;
  v_doomed := substring(v_src from '(?i)INTO\s+v_doomed\s+FROM\s+public\.ottoq_sim_runs\s+WHERE\s[^;]*;');
  IF v_doomed IS NULL OR v_doomed !~* '\mstatus\s*<>\s*''running''' OR v_doomed ~* '\mOR\M'
     OR (SELECT count(*) FROM regexp_matches(v_src, '\mINTO\s+v_doomed\M', 'gi')) <> 1 OR v_src ~* '\mv_doomed\s*:='
     OR (SELECT count(*) FROM regexp_matches(v_src, 'DELETE\s+FROM\s+(public\.)?ottoq_sim_runs\M', 'gi')) <> 1
     OR v_src !~* 'DELETE\s+FROM\s+public\.ottoq_sim_runs\s+WHERE\s+sim_run_id\s*=\s*ANY\s*\(\s*v_doomed\s*\)\s*;' THEN
    RAISE EXCEPTION '0790 P2: the prior-run purge no longer chooses only runs that are not running (it chooses: %)',
      COALESCE(v_doomed, 'no runs by the statement this file read');
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
              WHERE p.oid IN ('public.ottoq_sim_stop_and_reset(uuid,text)'::regprocedure,
                              'public.ottoq_sim_mark_stopped(uuid,text)'::regprocedure,
                              'public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean)'::regprocedure)
                AND p.prosrc ~* 'ottoq_purge_prior_runs') THEN
    RAISE EXCEPTION '0790 P2: the stop door, mark_stopped or the dispose calls the prior-run purge';
  END IF;
  -- the beat and both fault doors take the run's row FOR UPDATE (which the door's mode conflicts with), and nothing on
  -- the table is taken FOR NO KEY UPDATE yet
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY n.nspname, p.proname) INTO v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g'),
                        'ottoq_sim_runs\M[^;]*?\mFOR\s+(NO\s+KEY\s+)?UPDATE\M', 'gi') m
   WHERE n.nspname IN ('public', 'twin', 'ottoq');
  IF v_fns IS DISTINCT FROM 'public.ottoq_sim_advance_tick_world, public.ottoq_twin_inject_charger_fault, twin.ottoq_report_charger_fault' THEN
    RAISE EXCEPTION '0790 P2: the statements that take ottoq_sim_runs FOR (NO KEY) UPDATE are %, not the world step and the two fault doors', v_fns;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public', 'twin', 'ottoq')
                AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
                    ~* 'ottoq_sim_runs\M[^;]*?\mFOR\s+NO\s+KEY\s+UPDATE\M') THEN
    RAISE EXCEPTION '0790 P2: something already takes ottoq_sim_runs FOR NO KEY UPDATE';
  END IF;
  -- the stop's second edge: mark_stopped updates the run's row; dispose writes the proposals
  IF regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_sim_mark_stopped(uuid,text)'::regprocedure),
       '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') !~* 'UPDATE\s+ottoq_sim_runs\s+SET\s+status'
     OR regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean)'::regprocedure),
       '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') !~* 'UPDATE\s+public\.ottoq_external_proposals\s' THEN
    RAISE EXCEPTION '0790 P2: mark_stopped no longer updates the run''s row, or dispose no longer writes the proposals';
  END IF;
  -- §3's reverse order: nothing that writes the run's proposals also takes the run's row in a mode the door's lock
  -- conflicts with, which with the door holding the row while it disposes would be a cycle 0790 adds
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY n.nspname, p.proname) INTO v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'twin', 'ottoq')
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
         ~* '(UPDATE|INSERT\s+INTO)\s+(public\.)?ottoq_external_proposals\M'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
         ~* '(UPDATE\s+(public\.)?ottoq_sim_runs\M|ottoq_sim_runs\M[^;]*?\mFOR\s+(NO\s+KEY\s+)?(UPDATE|SHARE)\M)';
  IF v_fns IS NOT NULL THEN
    RAISE EXCEPTION '0790 P2: % write(s) the run''s proposals and also update(s) or lock(s) ottoq_sim_runs', v_fns;
  END IF;
  -- the beat's order: the world step before the decide step, with no COMMIT between them
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p WHERE p.oid = 'public.ottoq_demo_metronome(integer)'::regprocedure;
  v_world := strpos(v_src, 'public.ottoq_sim_advance_tick_world(');
  v_decide := strpos(v_src, 'public.ottoq_sim_decide_and_dispatch(');
  IF v_world = 0 OR v_decide <= v_world OR substr(v_src, v_world, v_decide - v_world) ~* '\mCOMMIT\M' THEN
    RAISE EXCEPTION '0790 P2: the metronome no longer runs the world step and then the decide step in one transaction';
  END IF;
  -- and the decide step writes the proposals (the metronome's second edge)
  IF regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure),
       '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') !~* 'UPDATE\s+ottoq_external_proposals\s+p\s+SET\s+status\s*=\s*''enacted''' THEN
    RAISE EXCEPTION '0790 P2: ottoq_decide_tick no longer enacts proposals by UPDATE';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0790_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_sim_stop_and_reset(uuid,text)'::regprocedure;

-- ── the patches: each anchor asserted to match exactly once ──
CREATE FUNCTION pg_temp.p0790_patch(p_sig text, p_anchor text, p_new text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_def text := pg_get_functiondef(p_sig::regprocedure);
BEGIN
  IF (length(v_def) - length(replace(v_def, p_anchor, ''))) / length(p_anchor) <> 1 THEN
    RAISE EXCEPTION '0790: an anchor in % does not match exactly once: %', p_sig, left(p_anchor, 80);
  END IF;
  RETURN replace(v_def, p_anchor, p_new);
END $fn$;

DO $sub$
DECLARE
  v_stop_a1 constant text := $a$DECLARE v_marked boolean;
$a$;
  v_stop_n1 constant text := $n$DECLARE v_marked boolean;
  v_lock_prev text := current_setting('lock_timeout');   -- 0790 (G440)
$n$;
  v_stop_a2 constant text := $a$  PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, NULL, NULL, true);
$a$;
  v_stop_n2 constant text := $n$  -- 0790 (G440): A RUNNING RUN'S ROW FIRST, before the proposals. The metronome's beat locks this row first (FOR
  -- UPDATE) and then writes the run's proposals; this door disposed the proposals first and then waited for the row in
  -- ottoq_sim_mark_stopped, so a stop during a beat deadlocked with it (2026-10-14 16:40:04 and 16:42:42 UTC). FOR NO KEY
  -- UPDATE, the mode mark_stopped's UPDATE takes: it waits for a beat, and a key check (a proposal's insert) does not wait
  -- for it. Only while the run is running, the one status a beat ticks: the prior-run purge deletes a run's proposals
  -- and then its row, on runs it chose while they were not running, so a stop on any other run keeps its old order (a
  -- run resumed after the purge chose it is not covered: G491). Under the 8 s mark_stopped gives the same row; the
  -- caller's lock_timeout is back for the rest of the teardown.
  PERFORM set_config('lock_timeout', '8000', true);
  PERFORM 1 FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id AND status = 'running' FOR NO KEY UPDATE;
  PERFORM set_config('lock_timeout', v_lock_prev, true);
  PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, NULL, NULL, true);
$n$;
BEGIN
  EXECUTE pg_temp.p0790_patch('public.ottoq_sim_stop_and_reset(uuid,text)', v_stop_a1, v_stop_n1);
  EXECUTE pg_temp.p0790_patch('public.ottoq_sim_stop_and_reset(uuid,text)', v_stop_a2, v_stop_n2);
END $sub$;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

DO $v$
DECLARE
  v_fns text; v_src text; v_lock int; v_dispose int; v_mark int; v_set8 int; v_restore int;
BEGIN
  --: V1 nothing else moved: undoing both patches gives back the snapshot byte for byte (header included, so SECURITY
  --:    DEFINER and the search_path are proven unchanged; CREATE OR REPLACE keeps the grants)
  IF replace(replace(pg_get_functiondef('public.ottoq_sim_stop_and_reset(uuid,text)'::regprocedure),
       $n$  v_lock_prev text := current_setting('lock_timeout');   -- 0790 (G440)
$n$, ''),
       $n$  -- 0790 (G440): A RUNNING RUN'S ROW FIRST, before the proposals. The metronome's beat locks this row first (FOR
  -- UPDATE) and then writes the run's proposals; this door disposed the proposals first and then waited for the row in
  -- ottoq_sim_mark_stopped, so a stop during a beat deadlocked with it (2026-10-14 16:40:04 and 16:42:42 UTC). FOR NO KEY
  -- UPDATE, the mode mark_stopped's UPDATE takes: it waits for a beat, and a key check (a proposal's insert) does not wait
  -- for it. Only while the run is running, the one status a beat ticks: the prior-run purge deletes a run's proposals
  -- and then its row, on runs it chose while they were not running, so a stop on any other run keeps its old order (a
  -- run resumed after the purge chose it is not covered: G491). Under the 8 s mark_stopped gives the same row; the
  -- caller's lock_timeout is back for the rest of the teardown.
  PERFORM set_config('lock_timeout', '8000', true);
  PERFORM 1 FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id AND status = 'running' FOR NO KEY UPDATE;
  PERFORM set_config('lock_timeout', v_lock_prev, true);
$n$, '')
     IS DISTINCT FROM (SELECT s.definition FROM public.ottoq_schema_snapshots s
                        WHERE s.label = '0790_pre' AND s.object_name = 'ottoq_sim_stop_and_reset'
                        ORDER BY s.snapshot_id DESC LIMIT 1) THEN
    RAISE EXCEPTION '0790 V1 FAILED: public.ottoq_sim_stop_and_reset(uuid,text) changed by more than its row lock';
  END IF;

  --: V2 the catalog, comment-stripped: the world step and both fault doors still take ottoq_sim_runs FOR UPDATE (G490
  --:    is not changed here), and the stop door is the one site that takes it FOR NO KEY UPDATE
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY n.nspname, p.proname) INTO v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g'),
                        'ottoq_sim_runs\M[^;]*?\mFOR\s+UPDATE\M', 'gi') m
   WHERE n.nspname IN ('public', 'twin', 'ottoq');
  IF v_fns IS DISTINCT FROM 'public.ottoq_sim_advance_tick_world, public.ottoq_twin_inject_charger_fault, twin.ottoq_report_charger_fault' THEN
    RAISE EXCEPTION '0790 V2 FAILED: the FOR UPDATE sites on ottoq_sim_runs are %', v_fns;
  END IF;
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY n.nspname, p.proname) INTO v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g'),
                        'ottoq_sim_runs\M[^;]*?\mFOR\s+NO\s+KEY\s+UPDATE\M', 'gi') m
   WHERE n.nspname IN ('public', 'twin', 'ottoq');
  IF v_fns IS DISTINCT FROM 'public.ottoq_sim_stop_and_reset' THEN
    RAISE EXCEPTION '0790 V2 FAILED: the FOR NO KEY UPDATE sites on ottoq_sim_runs are %', v_fns;
  END IF;

  --: V3 the stop door, comment-stripped: 8 s, the row, the caller's timeout back, then the proposals, then mark_stopped
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p WHERE p.oid = 'public.ottoq_sim_stop_and_reset(uuid,text)'::regprocedure;
  v_set8 := strpos(v_src, 'set_config(''lock_timeout'', ''8000'', true)');
  v_lock := strpos(v_src, 'FOR NO KEY UPDATE');
  v_restore := strpos(v_src, 'set_config(''lock_timeout'', v_lock_prev, true)');
  v_dispose := strpos(v_src, 'ottoq_dispose_external_proposals(');
  v_mark := strpos(v_src, 'ottoq_sim_mark_stopped(');
  IF NOT (0 < v_set8 AND v_set8 < v_lock AND v_lock < v_restore AND v_restore < v_dispose AND v_dispose < v_mark) THEN
    RAISE EXCEPTION '0790 V3 FAILED: the stop door does not take the run''s row first under 8 s and then dispose';
  END IF;
  --: and only a running run's (§3): a stop on any other run keeps the order it had, which keeps it out of the prior-run
  --: purge's way on a run that stays not running (not on one resumed after the purge chose it: G491)
  IF v_src !~* 'ottoq_sim_runs\s+WHERE\s+sim_run_id\s*=\s*p_sim_run_id\s+AND\s+status\s*=\s*''running''\s+FOR\s+NO\s+KEY\s+UPDATE\s*;' THEN
    RAISE EXCEPTION '0790 V3 FAILED: the stop door''s early lock is not limited to a running run';
  END IF;
  RAISE NOTICE '0790 V1-V3 PASSED: the stop door takes a running run''s row before the proposals, the tick''s own lock is unchanged, and nothing else moved';
END $v$;

-- ── V4: the patched door runs (a run that does not exist, in a subtransaction rolled back) and marks nothing ──
--    It does not check that the door gives the caller's lock_timeout back, and cannot from here: rolling the
--    subtransaction back reverts every set_config(..., true) made inside it, and by the time the door returns
--    mark_stopped has set 8 s whether the door restored the caller's value or not. V3 asserts the restore's place;
--    tests/test_tick_lock_sql.py::test_0790_the_teardown_runs_under_the_lock_timeout_it_ran_under_before asserts its
--    effect (the rescue step runs under the caller's 15 s), and a door without the restore fails it.
DO $vrun$
DECLARE v_res jsonb;
        v_none constant uuid := '00000000-0000-0000-0000-000000000724';
BEGIN
  BEGIN
    v_res := public.ottoq_sim_stop_and_reset(v_none, '0790_v4');
    RAISE EXCEPTION USING ERRCODE = 'P0790', MESSAGE = v_res::text;
  EXCEPTION WHEN SQLSTATE 'P0790' THEN
    v_res := SQLERRM::jsonb;
  END;
  IF v_res ->> 'marked_stopped' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION '0790 V4 FAILED: the stop door answered % for a run that does not exist', v_res;
  END IF;
  RAISE NOTICE '0790 V4 PASSED: the patched stop door runs, marks nothing for a run that does not exist, and is rolled back';
END $vrun$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0790_the_stop_door_takes_the_runs_row_before_the_proposals', false, false,
  'G440: ottoq_sim_stop_and_reset disposed the run''s proposals before mark_stopped locked the run''s row, the reverse '
  'of the metronome beat''s order, and deadlocked with it (2026-10-14 16:40:04, 16:42:42 UTC); it now takes a running '
  'run''s row first, FOR NO KEY UPDATE (mark_stopped''s own mode, which a proposal''s key check does not wait on) under '
  'mark_stopped''s 8 s, caller''s lock_timeout restored. Only a running run''s: the prior-run purge writes a run''s rows '
  'before its row, on runs it chose while they were not running (P2), so a stop on any other run keeps its old order. '
  'The purge never locks the runs it chose, so one resumed mid-purge is deleted while running, and a stop on it in that '
  'window now deadlocks with a lone purge (G491, open, not changed here; before 0790 both finish). '
  'Anchored and md5-guarded (bc8ee182), nothing else moved (V1). '
  'The tick''s FOR UPDATE is unchanged: weakening it (G490) lets a proposal commit mid-beat and decide_tick''s A3 '
  'enact UPDATE (line 1228 on 2026-10-14, 1238 since 0727) mark the wrong one enacted. 0790 widens G492 for the pause '
  '(a pause during the stop''s dispose now writes paused over completed); 0791 closes it and goes with or before 0790. '
  'Every certified output is computed inside one transaction, where the added lock waits on nothing and reads nothing '
  'into a variable; no atom reads a lock: FALSE/FALSE.',
  now());

COMMIT;
