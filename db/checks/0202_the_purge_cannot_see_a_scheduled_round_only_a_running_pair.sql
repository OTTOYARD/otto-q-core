-- ---------------------------------------------------------------------------
-- 0202 — THE PURGE CANNOT SEE A SCHEDULED ROUND, ONLY A RUNNING PAIR. THAT IS
-- WHY ottoq_retention_purge_runs IS STILL NOT ON CRON.
--
-- Found 2026-09-13 16:55 UTC while closing G23's last item after round 42.
-- The finding is a REASON NOT TO SCHEDULE, not a fix, and nothing is applied.
-- ---------------------------------------------------------------------------

-- 1. THE GUARD SET, MEASURED FROM THE BODY RATHER THAN ASSUMED.
SELECT (position('cron.job'          in p.prosrc) > 0) AS guards_on_cron_job,
       (position('jobname'           in p.prosrc) > 0) AS guards_on_jobname,
       (position('pg_stat_activity'  in p.prosrc) > 0) AS guards_on_pg_stat_activity,
       (position('advisory'          in p.prosrc) > 0) AS uses_advisory_lock
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';
-- MEASURED: cron_job FALSE, jobname FALSE, pg_stat_activity TRUE, advisory TRUE.
--
-- So the purge refuses/skips on: another purge holding the advisory lock; a
-- blocking run-scope defect; an allow-list wider than class=engine; an
-- allow-listed parent of a NO ACTION/RESTRICT FK; and a determinism pair
-- ACTIVE IN pg_stat_activity RIGHT NOW.
--
-- It has NO guard on a SCHEDULED round. Every migration in this repo carries one
-- (`jobname ~ '^r[0-9]+_'`, by EXISTENCE not activeness, so a round paused
-- mid-flight still blocks). The purge does not.

-- 2. WHY THAT MATTERS, AND WHY IT IS NOT AN EMERGENCY.
--    A round is ten pairs on 14-minute slots. A 12-tick pair runs ~130 s and a
--    24-tick ~270 s, so for most of a 112-minute round NOTHING is in
--    pg_stat_activity. A nightly purge landing in one of those gaps would see no
--    pair, pass every guard it has, and delete — moving the residue canon
--    BETWEEN two pairs of the same round.
--
--    AFTER 0266 that can no longer break an engine streak, which is the whole
--    point of today's work and is now measured rather than argued (round 42:
--    nine of nine engine canons re-derived unchanged across a 7,300,205-row
--    purge). The damage is confined to the residue column — but it is still
--    damage: a round whose residue history is half pre-purge and half post-purge
--    is internally inconsistent, and `sections_moved` would name a section that
--    moved *during* the round rather than before it.
--
--    IT IS LATENT, NOT ACTIVE. ottoq_retention_purge_runs is on NO cron job
--    (db/checks/0200 §1: jobid 11 is the three-table WORKER, a different
--    procedure). Nothing can fire mid-round today. The defect only becomes real
--    the moment someone schedules it — which is exactly the thing G23's last
--    item asks for.

-- 3. THE FIX, SPECIFIED BUT DELIBERATELY NOT APPLIED.
--    Splice the same two-branch predicate the migrations use, immediately before
--    the existing pair-in-flight guard, and SKIP rather than RAISE — a nightly
--    job that throws an exception every time a round is scheduled fills the cron
--    log with errors and trains people to ignore it, where the pair-in-flight
--    guard already establishes `RAISE NOTICE ... RETURN` as the right shape:
--
--      IF EXISTS (SELECT 1 FROM cron.job
--                  WHERE jobname ~ '^r[0-9]+_'
--                     OR (active AND (command ILIKE '%ottoq_determinism_pair%'
--                                  OR command ILIKE '%ottoq_cert_battery_step%')))
--      THEN
--        PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
--        RAISE NOTICE 'retention purge: a certification round is scheduled - skipped';
--        RETURN;
--      END IF;
--
--    CREATE OR REPLACE from pg_get_functiondef under an md5 pin on prosrc
--    (currently b786dbd09548e39f5f35abe22dd467bb), anchored substitution asserted
--    to occur exactly once, the way 0204 and 0225 did it. The discriminating
--    assertion is available and cheap: schedule one dummy `r999_*` job, CALL the
--    purge in dry-run, require it to skip, unschedule. That fails before the
--    splice and passes after.

-- ---------------------------------------------------------------------------
-- WHY THIS IS A CHECK FILE AND NOT MIGRATION 0269 TODAY
--
-- Three migrations were applied today (0266, 0267, 0268) plus an irreversible
-- 7,300,205-row purge and a ten-pair round. 0267 shipped WITHOUT its
-- ottoq_cert_lineage row and blanked both certification instruments until 0268
-- supplied it — a slip of exactly the kind that a fourth careful migration at
-- the end of a long day invites. The defect here is latent and costs nothing to
-- leave open tonight, because the thing that would make it bite (scheduling the
-- purge) is the same thing this file says not to do yet.
--
-- THE ORDER, THEREFORE:
--   1. migration 0269 — the round-job guard, with the dummy-job assertion above
--   2. VERIFY it skips against a scheduled round, and still purges without one
--   3. only then schedule ottoq_retention_purge_runs, and pick the cadence
--   4. separately, and needing a maintenance window Chase must approve:
--      VACUUM FULL / REINDEX. Not doable casually — cron jobids 10, 12 and 17
--      fire every one to two minutes against these tables, and VACUUM FULL takes
--      ACCESS EXCLUSIVE. The rows are gone and autovacuum has already reclaimed
--      them for REUSE (n_dead_tup ~0); what has not come back is FILE size
--      (ottoq_events 3429 MB, ottoq_rule_evaluations 5657 MB, database 17 GB).
--      "7.3 million rows deleted" is true; "the database got smaller" is not.
-- ---------------------------------------------------------------------------
