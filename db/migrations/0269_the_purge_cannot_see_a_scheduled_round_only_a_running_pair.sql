-- migration-version: 20260913205636
-- migration-name:    0269_the_purge_cannot_see_a_scheduled_round_only_a_running_pair
--
-- 0269  THE PURGE CANNOT SEE A SCHEDULED ROUND, ONLY A RUNNING PAIR  (G23)
--
-- ---------------------------------------------------------------------------
-- THE DEFECT, DEMONSTRATED LIVE RATHER THAN READ OFF THE BODY
--
-- db/checks/0202 established from the source that ottoq_retention_purge_runs
-- guards on a determinism pair ACTIVE in pg_stat_activity but has no guard on a
-- SCHEDULED round. Before writing this file that was demonstrated:
--
--   cron.schedule('r999_0269_probe', '0 0 1 1 *', ...)   -- a round job exists
--   CALL ottoq_retention_purge_runs(5, 100, '48 hours', true);
--   -> "PROCEEDED (no exception) | elapsed_ms=1051"
--
-- It walked straight past a scheduled round and did 1,051 ms of work. The probe
-- job was unscheduled immediately (verified: 0 jobs matching ^r[0-9]+_ remain).
--
-- WHY IT MATTERS. A round is ten pairs on 14-minute slots; a 12-tick pair runs
-- ~130 s and a 24-tick ~270 s. For most of a ~112-minute round NOTHING is in
-- pg_stat_activity, so a nightly purge lands in a gap, passes every guard the
-- procedure has, and moves the residue canon BETWEEN two pairs of one round.
-- After 0266 that cannot break an engine streak -- round 42 measured exactly
-- that, nine of nine canons re-derived across a 7,300,205-row purge -- but it
-- leaves a round's residue history half pre-purge and half post-purge, and
-- `sections_moved` naming a section that moved DURING the round.
--
-- It is latent today only because the run purge is on no cron job at all
-- (jobid 11 is the three-table WORKER, a different procedure -- db/checks/0200).
-- This file is the precondition for scheduling it, which is G23's last item.
--
-- ---------------------------------------------------------------------------
-- WHAT AN ADVERSARIAL REVIEW CHANGED, AND WHY THE FIRST DRAFT WAS WRONG
--
-- A first draft of this file was reviewed by three independent lenses with every
-- finding adversarially verified (13 confirmed, 4 refuted). Two confirmed
-- findings were defects of DESIGN, not of wording, and both are fixed here. They
-- are recorded because the reasoning is the useful part:
--
--  (1) PRESENCE-BASED WOULD HAVE MADE THE PURGE SKIP FOREVER.  The first draft
--      blocked whenever ANY job matching ^r[0-9]+_ existed. But round jobs are
--      never torn down: scripts/schedule-round.sql writes date-pinned one-shots
--      (`MI HH DD MM *`) whose command is only the pair call, and the only
--      `unschedule` in that script is an error message telling a human to do it
--      by hand. db/canons/round27-apply-window.md:102 records the consequence --
--      "round 27's seven stay active after firing ... but cron.job.active does
--      not know that". So once the purge went on cron, the FIRST round to finish
--      without manual cleanup would silently disable the purge indefinitely,
--      while cron.job_run_details reported success every night. That is strictly
--      worse than today's honest state ("the run purge is on no cron job at
--      all"), because it looks like it is working. Note that gating on
--      `active` -- which 0225, 0226, 0227, 0228, 0262 and 0265 all do -- does
--      NOT fix it: a fired date-pinned job stays active = true.
--
--      THE FIX: the round branch is TIME-BOUNDED. A round job blocks only if its
--      fire time, reconstructed from its own date-pinned schedule, is within
--      +/- 3 hours of now(). A round spans ~112 minutes, so that covers a whole
--      round from before its first pair to after its last, and excludes a round
--      that fired on an earlier day. A schedule that is NOT the date-pinned
--      shape is not understood by this predicate, so it BLOCKS -- unrecognised
--      means unsafe, never "assume it is stale".
--
--  (2) PLACING IT FIRST MADE THREE INTEGRITY REFUSALS UNREACHABLE.  The first
--      draft spliced the guard immediately after the advisory lock and ahead of
--      the run-scope check, deviating from db/checks/0202 section 3 on the
--      grounds that a skip should be cheap. Measured, that buys tens of
--      milliseconds (the whole dry call is 1,051 ms cold / 59 ms warm). What it
--      costs is that under the guard condition the run-scope refusal, GUARD 1
--      (allow-list wider than class=engine) and GUARD 2 (allow-listed parent of
--      a NO ACTION/RESTRICT FK) all become unreachable -- and none of the three
--      has any other standing reader, so a defect they exist to catch would go
--      unreported for as long as a round was scheduled.
--
--      THE FIX: the guard goes where 0202 section 3 specified in the first
--      place -- immediately before the pair-in-flight guard, AFTER all three
--      integrity checks. There is now NO deviation from the spec to declare.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS FILE ASSERTS -- INCLUDING, THIS TIME, THAT THE GUARD CAN FIRE
--
-- The first draft's five assertions were all text operations over prosrc. They
-- would every one have passed on a semantically dead guard: changing the regex
-- to '^zzz[0-9]+_' in both copies left A1-A5 green, because the file compared
-- its two copies of the predicate only against each other. db/checks/0202
-- section 3 had already named the assertion that closes this -- "schedule one
-- dummy r999_* job, CALL the purge in dry-run, require it to skip, unschedule"
-- -- and the draft dropped it without declaring that as a deviation.
--
-- A6 restores it, two-sided, and it is now the discriminating assertion:
--   * the predicate is written ONCE, as v_pred, and the installed block is built
--     from it, so the text A6 evaluates is the text A1 proves is installed;
--   * with an imminent round job scheduled, v_pred must be TRUE;
--   * with only a round job that fired 26 hours ago, v_pred must be FALSE --
--     this is defect (1) above, asserted rather than described;
--   * with a schedule of an unrecognised shape, v_pred must be TRUE (fail safe).
-- All three cases were dry-run against the live catalog before this file was
-- committed: baseline=f, imminent=t, stale=f, unparseable=t, and cron.schedule
-- / cron.unschedule both work from the applying role inside a DO block.
--
-- NO NON-DRY CALL IS MADE, HERE OR AFTER APPLY. The first draft deferred its
-- behavioural proof to a post-apply NON-dry purge, on the premise that 0 rows
-- were purgeable so it would be a data no-op touching only
-- ottoq_retention_state.updated_at. That premise is a claim about a moment:
-- db/checks/0200 and 0201 together put ~2.7 runs/hour crossing the 48-hour
-- boundary at ~7,775 engine rows each, and 0251's stamp is SET-WIDE -- one row
-- crossing causes `UPDATE ottoq_sim_runs SET purged_at = now() WHERE sim_run_id
-- = ANY(v_doomed)`, permanently making ottoq_kpi_five report those runs GONE.
-- An irreversible production delete is not an acceptable price for a test, and
-- A6 makes it unnecessary.
-- ---------------------------------------------------------------------------

DO $p$
DECLARE v_busy int; v_jobs int; v_live int; v_block int;
BEGIN
  SELECT count(*) INTO v_busy FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_sim_advance_tick%'
          OR query ILIKE '%ottoq_ab_pair%');
  IF v_busy > 0 THEN
    RAISE EXCEPTION '0269 P1: % certification/pair call(s) in flight', v_busy;
  END IF;

  -- Deliberately PRESENCE-based here, unlike the guard this file installs. A
  -- preflight asks "is it safe to change the brain right now", and any round job
  -- at all -- imminent, stale or paused -- means a human is mid-workflow. The
  -- guard asks a different question ("should tonight's purge run") and must not
  -- latch, which is what defect (1) above is about. Same regex, opposite duty.
  SELECT count(*) INTO v_jobs FROM cron.job
   WHERE (jobname ~ '^r[0-9]+_')
      OR (active AND (command ILIKE '%ottoq_determinism_pair%'
                      OR command ILIKE '%ottoq_cert_battery_step%'));
  IF v_jobs > 0 THEN
    RAISE EXCEPTION '0269 P2: % certification job(s) still scheduled', v_jobs;
  END IF;

  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_live > 0 THEN
    RAISE EXCEPTION '0269 P3: % run(s) running or paused', v_live;
  END IF;

  -- A5 and A6 CALL the live procedure, whose first act after the lock is to
  -- refuse on a blocking run-scope defect -- db/checks/0200 section 2 records
  -- exactly that call failing that way earlier today. Without this, an unrelated
  -- registry defect would abort the file AFTER the procedure had been replaced.
  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0269 P4: % blocking run-scope defect(s) -- A5/A6 would abort after the splice', v_block;
  END IF;
END $p$;

-- ---------------------------------------------------------------------------
-- G. THE PRE-IMAGE, PINNED.
--
--    ORDER MATTERS, and the first draft had it backwards. The guard-already-
--    present check is FIRST, because re-running this file after it is applied is
--    the likeliest operator event and it deserves the message written for it. In
--    the first draft the md5 pin came first, so that branch could never be
--    reached and the operator got "the body moved; re-derive the splice", which
--    misdirects. The draft's length and prosrc-anchor checks were dropped: md5
--    fixes the byte string, so both were unreachable once the pin passed. The
--    live anchor check is the one in section 1, against pg_get_functiondef,
--    which this file never pins.
-- ---------------------------------------------------------------------------
DO $g$
DECLARE v_n int; v_src text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_retention_purge_runs';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0269 G1: expected exactly 1 ottoq_retention_purge_runs, found %', v_n;
  END IF;

  SELECT p.prosrc INTO STRICT v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_retention_purge_runs';

  IF position('a certification round is scheduled' in v_src) > 0 THEN
    RAISE EXCEPTION '0269 G2: the round guard is already present; this file installs it';
  END IF;

  IF md5(v_src) <> 'b786dbd09548e39f5f35abe22dd467bb' THEN
    RAISE EXCEPTION '0269 G3: prosrc md5 is %, expected b786dbd09548e39f5f35abe22dd467bb -- the body moved; re-derive the splice', md5(v_src);
  END IF;
END $g$;

-- ---------------------------------------------------------------------------
-- S. PRE-IMAGE SNAPSHOT, so a reader can recover the body this file replaced.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0269-pre', 'procedure', 'public',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';

-- ---------------------------------------------------------------------------
-- 1. THE SPLICE. Rebuilt from pg_get_functiondef so every line this file does
--    not name stays byte-identical, the way 0204 and 0225 did it.
--
--    SKIP, NOT RAISE. This procedure is meant to run from cron. A nightly job
--    that throws an exception every time a round is scheduled fills the cron log
--    with errors and trains people to ignore it. The pair-in-flight guard it
--    sits beside already establishes RAISE NOTICE + RETURN as the shape for
--    "not now"; RAISE EXCEPTION is reserved for "something is wrong".
--
--    TWO BRANCHES, DELIBERATELY ASYMMETRIC:
--      * THE CERT BATTERY by ACTIVENESS -- jobid 13 is a standing job disabled
--        rather than deleted, so existence alone would block the purge forever.
--        Matching on COMMAND rather than name also catches a renamed cert
--        battery job that the ^r[0-9]+_ regex would miss.
--      * ROUND JOBS by IMMINENCE -- see defect (1) in the header. Existence
--        latches, activeness latches too (a fired date-pinned job stays
--        active = true), so the only non-latching question is WHEN it fires.
--
--    (The first draft called this asymmetry "the same deliberate asymmetry every
--    migration preflight in this repo uses". That was false and is withdrawn:
--    0225, 0226, 0227, 0228, 0262 and 0265 all gate the round branch on
--    activeness, and the two-branch form exists only in 0266-0269. The same
--    overclaim was propagated into db/checks/0202 and is corrected there too.)
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE v_def text; v_blk text; v_pred text; v_n int;
BEGIN
  v_pred := $pred$EXISTS (
      SELECT 1 FROM cron.job j
       WHERE (j.active AND (j.command ILIKE '%ottoq_determinism_pair%'
                         OR j.command ILIKE '%ottoq_cert_battery_step%'))
          OR (j.jobname ~ '^r[0-9]+_' AND
              CASE WHEN j.schedule ~ '^[0-9]+ [0-9]+ [0-9]+ [0-9]+ \*$'
                   THEN make_timestamptz(extract(year from now())::int,
                                         split_part(j.schedule,' ',4)::int,
                                         split_part(j.schedule,' ',3)::int,
                                         split_part(j.schedule,' ',2)::int,
                                         split_part(j.schedule,' ',1)::int, 0, 'UTC')
                        BETWEEN now() - interval '3 hours' AND now() + interval '3 hours'
                   ELSE true END))$pred$;

  v_blk := $b$  -- 0269 (G23): A SCHEDULED ROUND, not merely a running pair.
  -- db/checks/0202: a round is ten pairs on 14-minute slots and a pair runs
  -- 130-270 s, so for most of a round nothing is in pg_stat_activity and the
  -- guard below sees an idle system. A purge landing in one of those gaps moves
  -- the residue canon BETWEEN two pairs of the same round. Placed here, after
  -- the run-scope check and both allow-list guards, so those three refusals stay
  -- reachable; skips rather than raises, because this runs from cron.
  -- Round jobs are matched by IMMINENCE (+/- 3 h of their own date-pinned fire
  -- time), never by existence: nothing unschedules them after they fire, so an
  -- existence test would disable the purge permanently after the first round.
  -- An unrecognised schedule shape blocks -- unrecognised means unsafe.
  IF $b$ || v_pred || $b$ THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE NOTICE 'retention purge: a certification round is scheduled - skipped';
    RETURN;
  END IF;

$b$;

  SELECT pg_get_functiondef(p.oid) INTO STRICT v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_retention_purge_runs';

  v_n := (length(v_def) - length(replace(v_def,
            '  SELECT count(*) INTO v_pairs FROM pg_stat_activity','')))
         / length('  SELECT count(*) INTO v_pairs FROM pg_stat_activity');
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0269 splice: anchor occurs % time(s) in the functiondef, expected 1', v_n;
  END IF;

  v_def := replace(v_def,
    '  SELECT count(*) INTO v_pairs FROM pg_stat_activity',
    v_blk || '  SELECT count(*) INTO v_pairs FROM pg_stat_activity');

  EXECUTE v_def;
  RAISE NOTICE '0269: ottoq_retention_purge_runs rebuilt from the catalog with the round guard';
END $mig$;

COMMENT ON PROCEDURE public.ottoq_retention_purge_runs(integer,integer,interval,boolean) IS
'0247 created it, 0250 gave it the allow-list, 0251 the purged_at stamp, 0269 the round guard. Deletes child rows of doomed runs (not running, not production_live, older than the engine_rows keep interval, already archived) across ottoq_retention_engine_allowlist only -- never ottoq_sim_runs itself, so validation_notes and every certification pair survive. Refuses on a blocking run-scope defect, on an allow-list wider than class=engine, and on an allow-listed parent of a NO ACTION/RESTRICT FK. SKIPS while a determinism pair is in flight OR while a certification round is imminent (0269: the second was missing, and a purge in a 14-minute inter-pair gap moves the residue canon mid-round). Round jobs are matched by imminence, not existence, because nothing unschedules them after they fire.';

-- ---------------------------------------------------------------------------
-- 2. CLASSIFICATION. Deliberately BEFORE the assertions, not after.
--
--    0267 shipped without its lineage row and the recert floor swallowed every
--    column until 0268 repaired it. A5/A6 below call the live procedure, which
--    can refuse for reasons that have nothing to do with this change; if that
--    happened with the INSERT last, a non-atomic apply would leave the procedure
--    replaced and unclassified -- the 0267 state exactly. 0266 and 0268 both put
--    the lineage row ahead of their assertions; so does this.
--
--    Non-forcing: this changes WHEN a maintenance procedure declines to run. It
--    touches no engine function, no fingerprint, no twin path and no verdict
--    atom, so nothing an arm produces can differ.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0269_the_purge_cannot_see_a_scheduled_round_only_a_running_pair', false,
        'G23. Adds a SCHEDULED-ROUND guard to ottoq_retention_purge_runs, which previously guarded only on a determinism pair ACTIVE in pg_stat_activity -- demonstrated live before the fix: with a round job scheduled the purge proceeded and did 1,051 ms of work. The guard sits immediately before the pair-in-flight guard, AFTER the run-scope check and both allow-list guards, so those three refusals stay reachable. Round jobs are matched by IMMINENCE (+/- 3 h of their reconstructed date-pinned fire time), never existence: nothing unschedules a round job after it fires, so an existence test would have disabled the purge permanently after the first round while cron reported success. Skips (NOTICE + RETURN) rather than raising, because the procedure is meant to run from cron. Non-forcing: no engine function, no fingerprint, no verdict atom. This file is the precondition for G23 last item, scheduling the run purge.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ---------------------------------------------------------------------------
-- 3. ASSERTIONS. A6 is the discriminating one -- it is the only assertion that
--    would fail on a guard that is installed but semantically dead. A1-A4 are
--    text assertions that say "this block was inserted and nothing else moved";
--    A5 says the normal path still runs. See the header.
-- ---------------------------------------------------------------------------
DO $a$
DECLARE
  v_src text; v_blk text; v_pred text; v_n int; v_hit boolean;
  v_pos_lock int; v_pos_runscope int; v_pos_guard int; v_pos_pair int;
  v_frag text; v_frags text[] := ARRAY[
    'IF NOT pg_try_advisory_lock(hashtext(''ottoq_retention_purge'')) THEN',
    'SELECT count(*) FILTER (WHERE severity = ''block'') INTO v_block',
    'purge refused: allow-listed but not class=engine',
    'purge refused: allow-listed table is the parent of a NO ACTION/RESTRICT FK',
    'certification pair(s) in flight - skipped',
    'nothing older than % is archived and finished',
    'PERFORM pg_advisory_unlock(hashtext(''ottoq_retention_purge''));'];
BEGIN
  -- v_pred and v_blk are rebuilt here EXACTLY as section 1 built them. This is
  -- what makes A6 mean something: the text A6 evaluates is the text A1 proves is
  -- installed in the live body.
  v_pred := $pred$EXISTS (
      SELECT 1 FROM cron.job j
       WHERE (j.active AND (j.command ILIKE '%ottoq_determinism_pair%'
                         OR j.command ILIKE '%ottoq_cert_battery_step%'))
          OR (j.jobname ~ '^r[0-9]+_' AND
              CASE WHEN j.schedule ~ '^[0-9]+ [0-9]+ [0-9]+ [0-9]+ \*$'
                   THEN make_timestamptz(extract(year from now())::int,
                                         split_part(j.schedule,' ',4)::int,
                                         split_part(j.schedule,' ',3)::int,
                                         split_part(j.schedule,' ',2)::int,
                                         split_part(j.schedule,' ',1)::int, 0, 'UTC')
                        BETWEEN now() - interval '3 hours' AND now() + interval '3 hours'
                   ELSE true END))$pred$;

  v_blk := $b$  -- 0269 (G23): A SCHEDULED ROUND, not merely a running pair.
  -- db/checks/0202: a round is ten pairs on 14-minute slots and a pair runs
  -- 130-270 s, so for most of a round nothing is in pg_stat_activity and the
  -- guard below sees an idle system. A purge landing in one of those gaps moves
  -- the residue canon BETWEEN two pairs of the same round. Placed here, after
  -- the run-scope check and both allow-list guards, so those three refusals stay
  -- reachable; skips rather than raises, because this runs from cron.
  -- Round jobs are matched by IMMINENCE (+/- 3 h of their own date-pinned fire
  -- time), never by existence: nothing unschedules them after they fire, so an
  -- existence test would disable the purge permanently after the first round.
  -- An unrecognised schedule shape blocks -- unrecognised means unsafe.
  IF $b$ || v_pred || $b$ THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE NOTICE 'retention purge: a certification round is scheduled - skipped';
    RETURN;
  END IF;

$b$;

  SELECT p.prosrc INTO STRICT v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_retention_purge_runs';

  --: A1. THE BLOCK IS PRESENT, EXACTLY ONCE, and it contains v_pred verbatim.
  --:     Fails before this file, passes after.
  v_n := (length(v_src) - length(replace(v_src, v_blk, ''))) / length(v_blk);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0269 A1: the round guard occurs % time(s) in the installed body, expected exactly 1', v_n;
  END IF;

  --: A2. AND NOTHING ELSE MOVED. Remove the block and the body must md5 back to
  --:     the pre-image pin. NOT a discriminator on its own (removing an absent
  --:     block is a no-op, so this passes before the splice too) -- it is the
  --:     other half of A1, and the pair is what means "inserted, nothing else".
  IF md5(replace(v_src, v_blk, '')) <> 'b786dbd09548e39f5f35abe22dd467bb' THEN
    RAISE EXCEPTION '0269 A2: with the guard removed the body does not revert to the pre-image pin; the splice changed something else';
  END IF;

  --: A3. AND IT IS IN THE RIGHT PLACE, PINNED ON BOTH SIDES. The first draft
  --:     pinned only the right-hand boundary, so a consistent edit of the anchor
  --:     could have relocated the block above the lock, or inside the lock's
  --:     failure branch, with every assertion still green.
  v_pos_lock     := position('IF NOT pg_try_advisory_lock' in v_src);
  v_pos_runscope := position('SELECT count(*) FILTER (WHERE severity = ''block'') INTO v_block' in v_src);
  v_pos_guard    := position('a certification round is scheduled' in v_src);
  v_pos_pair     := position('certification pair(s) in flight - skipped' in v_src);
  IF NOT (v_pos_lock > 0 AND v_pos_lock < v_pos_runscope
          AND v_pos_runscope < v_pos_guard AND v_pos_guard < v_pos_pair) THEN
    RAISE EXCEPTION '0269 A3: lock/run-scope/guard/pair order is %/%/%/%, expected strictly increasing',
                    v_pos_lock, v_pos_runscope, v_pos_guard, v_pos_pair;
  END IF;

  --: A4. EVERY PRE-EXISTING REFUSAL SURVIVED. Redundant with A2 by construction
  --:     -- A2 would already fire if any of these had gone. It is kept as a
  --:     named, readable inventory of what must not disappear. (The first draft
  --:     justified it as "if A2 fires, A4 says which guard went", which is
  --:     impossible: A2 raises, and an unhandled RAISE aborts this block before
  --:     A4 runs. That rationale is withdrawn.)
  FOREACH v_frag IN ARRAY v_frags LOOP
    IF position(v_frag in v_src) = 0 THEN
      RAISE EXCEPTION '0269 A4: the installed body no longer contains %', v_frag;
    END IF;
  END LOOP;

  --: A5. AND THE PROCEDURE STILL RUNS. A dry-run call must complete without
  --:     raising. Guarded twice, because a bare CALL here could pass without
  --:     executing anything: the procedure's first act is pg_try_advisory_lock,
  --:     and if another session held that lock this would take the NOTICE +
  --:     RETURN branch and prove nothing. So take the lock ourselves first to
  --:     prove it is free, release it, then call.
  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE EXCEPTION '0269 A5: another session holds the retention purge advisory lock; a dry call would silently skip';
  END IF;
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
  CALL public.ottoq_retention_purge_runs(3, 100, '48 hours', true);

  --: A6. AND THE GUARD CAN ACTUALLY FIRE -- the discriminating assertion, and
  --:     the one db/checks/0202 section 3 asked for. Three cases, each a real
  --:     cron job created and removed inside this block. Wrapped so that a
  --:     failure cannot leave a dummy job behind: a stray r999_* would itself
  --:     block the purge for three hours.
  BEGIN
    -- (a) an imminent round MUST block
    PERFORM cron.schedule('r999_0269_imminent', to_char(now(),'MI HH24 DD MM')||' *', 'SELECT 1');
    EXECUTE 'SELECT ' || v_pred INTO v_hit;
    IF NOT v_hit THEN
      RAISE EXCEPTION '0269 A6a: an imminent round job does not trip the guard -- the predicate is dead';
    END IF;
    PERFORM cron.unschedule('r999_0269_imminent');

    -- (b) a round that already fired must NOT block -- defect (1), asserted
    PERFORM cron.schedule('r998_0269_stale', to_char(now() - interval '26 hours','MI HH24 DD MM')||' *', 'SELECT 1');
    EXECUTE 'SELECT ' || v_pred INTO v_hit;
    IF v_hit THEN
      RAISE EXCEPTION '0269 A6b: a round job that fired 26 h ago still blocks the purge -- the guard latches, and once on cron it would never run again';
    END IF;
    PERFORM cron.unschedule('r998_0269_stale');

    -- (c) an unrecognised schedule shape MUST block -- fail safe
    PERFORM cron.schedule('r997_0269_weird', '*/5 * * * *', 'SELECT 1');
    EXECUTE 'SELECT ' || v_pred INTO v_hit;
    IF NOT v_hit THEN
      RAISE EXCEPTION '0269 A6c: a round job with an unrecognised schedule does not block -- unrecognised must mean unsafe';
    END IF;
    PERFORM cron.unschedule('r997_0269_weird');
  EXCEPTION WHEN OTHERS THEN
    PERFORM cron.unschedule(jobname) FROM cron.job
     WHERE jobname IN ('r999_0269_imminent','r998_0269_stale','r997_0269_weird');
    RAISE;
  END;

  -- belt and braces: nothing this block created may survive it
  SELECT count(*) INTO v_n FROM cron.job
   WHERE jobname IN ('r999_0269_imminent','r998_0269_stale','r997_0269_weird');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0269 A6: % dummy job(s) survived the assertion block', v_n;
  END IF;

  RAISE NOTICE '0269: A1-A6 passed; the guard is installed, correctly placed, fires on an imminent round, does NOT latch on a fired one, and fails safe on an unknown schedule';
END $a$;

-- ---------------------------------------------------------------------------
-- APPLY LOG
--
-- APPLIED 2026-09-13 20:56:36 UTC (3:56 PM CT) as version 20260913205636,
-- name 0269_the_purge_cannot_see_a_scheduled_round_only_a_running_pair
-- (prefix included -- 0266 was registered without its 0NNN_ prefix and had to be
-- repaired by hand about twenty minutes later; check-drift Section C compares on
-- the full name).
--
-- Window at apply: pairs_in_flight 0, cert_jobs 0, runs_live 0,
-- blocking run-scope defects 0, pre-image md5 b786dbd09548e39f5f35abe22dd467bb.
--
-- PRE -> POST
--   prosrc md5    b786dbd09548e39f5f35abe22dd467bb -> 65051f58027f73f07797110e0abbf726
--   prosrc length 5900 -> 7735
--   (the post-image md5 is byte-identical to the one the whole-file dry run
--    predicted before commit, so what ran is what was tested)
--   ottoq_cert_lineage row present, forces_recert = false
--   ottoq_schema_snapshots '0269-pre' present
--   ottoq_cert_recert_floor() 2026-09-12 16:50:23.319089+00 -- UNMOVED. This is
--   the 0267 defect not recurring: 0267 shipped without its lineage row and the
--   floor jumped to its apply time, blanking both instruments until 0268.
--
-- VERIFIED -- and "applied without error" is not verification, so this is the
-- behaviour, measured on the INSTALLED procedure, in dry-run only.
--
--   The observable: the guard sits immediately before the procedure reads
--   ottoq_retention_policy, so that table's scan counter separates "skipped"
--   from "proceeded". THE FIRST TWO ATTEMPTS AT THIS INSTRUMENT READ ZERO IN
--   BOTH ARMS AND WERE WRONG, NOT THE GUARD: stats_fetch_consistency = 'cache'
--   serves one snapshot per transaction, and pg_stat_force_next_flush() only
--   flushes at transaction end -- so a probe that CALLs and reads inside a
--   single DO block cannot move. Split across transactions it discriminates:
--
--     no round scheduled            delta +1   PROCEEDED past the guard
--     imminent round scheduled      delta  0   SKIPPED before the policy read
--     round that fired 26 h ago     delta +1   PROCEEDED -- the guard does not latch
--     stray r9xx_ jobs afterwards       0
--
--   The third line is the one that matters: it is defect (1) from the header,
--   observed rather than argued. A presence-based guard would have read 0 there
--   and, once the purge was on cron, stayed 0 every night forever.
--
--   In-migration, A6 proved the same three cases against live cron.job rows, and
--   both counterfactuals were measured before apply: A6 RAISES on a dead regex
--   ('^zzz[0-9]+_' -- the mutation that passed all five of the first draft's
--   assertions), and A6 RAISES on the first draft's own presence-based
--   predicate. An assertion that convicts the design it replaced has power.
--
-- NOT DONE, DELIBERATELY: no non-dry call was made. See the header -- 0251's
-- purged_at stamp is set-wide, so a single run crossing the 48-hour boundary
-- during the test would have marked every doomed run GONE to ottoq_kpi_five,
-- irreversibly, to prove something A6 proves for free.
--
-- NEXT: G23's last item -- schedule ottoq_retention_purge_runs on cron. That is
-- now safe with respect to rounds and was not before this file.
-- ---------------------------------------------------------------------------
