-- migration-version: 20260912130622
-- migration-name: 0255_the_teardown_stamps_the_wall_clock_into_a_hashed_column
-- ===========================================================================
-- 0255  THE TEARDOWN STAMPS THE WALL CLOCK INTO A HASHED COLUMN
-- ===========================================================================
-- probe:          db/checks/0173; db/canons/round37.md; BUILD_QUEUE P0b (G46)
-- forces_recert:  TRUE  -- and the row is inserted by this migration, not later
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT. pg_stat_activity is the only
-- authority: ottoq_sim_runs cannot see an in-flight pair (both arms are one
-- uncommitted transaction) and cron.job_run_details reports one as succeeded in
-- about a second.
--
-- THE DEFECT, convicted in 0173 from round 37's own verdicts
--
-- public.ottoq_sim_advance_tick -- the function the certification's own tick loop
-- calls -- reaches the natural-completion teardown (0102) when the sim clock hits the
-- scenario end, and calls ottoq_sim_release_depot. That function stamps
--
--     last_state_change=now()
--
-- on every vehicle at the depot, and ottoq.ottoq_world_fingerprint HASHES that column
-- (0115, behind a pair-17 probe). Measured on run 1d1b43de (busy_day/171717/48t,
-- 06:20 UTC): all 116 vehicles carry the single value 2026-09-12 06:20:00.190665 --
-- the wall-clock instant the cron job fired -- against a sim clock of Sep 1-2.
--
-- WHY IT IS INVISIBLE TO THE INSTRUMENT BUILT TO CATCH IT. now() is the TRANSACTION
-- timestamp. ottoq_determinism_pair runs both arms in ONE transaction, so arm A and
-- arm B receive the IDENTICAL stamp and the pair CANNOT EVER FAIL on this column.
-- Only two separate pairs can see it, which is exactly what 0193's bar does and why
-- busy_day/171717/48t has failed it twice (2026-09-09 and 2026-09-12) while the six
-- 12t/24t columns reproduced across three rounds spanning three days: the teardown
-- fires only at 1,440 sim minutes, and at 30 sim-minutes per tick that is EXACTLY
-- tick 48. The shorter arms exit on tick count before reaching it.
--
-- WHY FIX THE WRITE AND NOT THE HASH. The alternative was to stop hashing
-- last_state_change, as 0137 did for current_soc_updated_at. Rejected: 0115 added the
-- column behind a probe, a vehicle's last transition time genuinely is start-relevant
-- world state (a cold-start or dwell rule would read it), and the wall-clock write is
-- wrong independently of whether anything hashes it -- it makes a twin run's end state
-- depend on when the run happened. The fingerprint catching it is the fingerprint
-- DOING ITS JOB. Third instance of the G15 / 0137 family.
--
-- WHY PRODUCTION IS UNTOUCHED, read from the body rather than assumed. The write sits
-- inside `IF v_world_reset THEN`, and v_world_reset is derived two lines from the top:
--     SELECT COALESCE(d.feed_mode,'sim') INTO v_feed FROM depots d WHERE d.id = v_depot;
--     v_world_reset := (v_feed = 'sim');
-- So an external-feed (production) depot never enters the branch -- 0114's rule, "a
-- sim-feed world is a fixture and resets to empty; an external-feed world is reality".
-- ottoq_production_stop, one of release_depot's three callers, therefore cannot reach
-- the changed line at all.
--
-- THE PRECEDENT FOR THE REPLACEMENT VALUE IS ALREADY IN THE TREE. 0065 made exactly
-- this fix for ottoq_cert_arm_start, whose body still carries its marker:
--     last_state_change=v_sim0   /* 0065: sim domain */
-- This migration follows it: the run's own sim clock, with now() kept only as the
-- fallback for a run row that somehow has no clock, so the function can never fail
-- on a NULL.
--
-- ---------------------------------------------------------------------------
-- SCOPE -- NARROWER THAN db/checks/0173 ORIGINALLY CLAIMED, AND THE CLAIM IS
-- CORRECTED IN THAT FILE RATHER THAN QUIETLY NARROWED HERE
-- ---------------------------------------------------------------------------
--
-- 0173 said its sweep was done "the general way" and named three routines. Re-measured
-- today with the regexp returning the MATCHED TEXT rather than a boolean, two of its
-- three claims were wrong:
--
--   * twin.ottoq_sim_seed_fleet is TWO OVERLOADS (2-arg and 3-arg) with ONE site each,
--     not "two sites"; and the write is `NOW() - ((r.stagger*90)||' min')::interval`,
--     a staggered wall clock rather than a plain now().
--   * public.ottoq_benchmark_reset has NO clock argument at all -- its signature is
--     (p_depot, p_arrival_soc, p_target_soc) -- so 0173's "stamp its own sim-start
--     argument" was not a thing it could do.
--   * and the sweep MISSED a whole shape: it matched `col = now()` literally, so a
--     variable assigned from now() and used later was invisible. Found by re-measuring:
--       twin.ottoq_world_advance()        v_now timestamptz := now()    -- TRUE wall clock
--       public.ottoq_cert_arm_wave        v_now timestamptz := now()    -- TRUE wall clock
--       twin.ottoq_sim_confirm_commands   v_now := COALESCE(p_clock, now())  -- SAFE on the
--                                         cert path, which passes p_clock; the now()
--                                         fallback is a latent hazard, not a live one
--       public.ottoq_cert_arm             v_now := COALESCE(p_start, now())  -- same shape
--
-- NONE of those four is on the determinism-pair path: the pair calls
-- ottoq_sim_advance_tick -> ottoq_sim_advance_tick_world (which stamps
-- v_new_sim_clock), never twin.ottoq_world_advance (the demo metronome's entry point),
-- and never the cert_arm family. seed_fleet's only caller is ottoq_sim_run_scenario,
-- which the pair does not call either -- the pair uses twin.ottoq_sim_start_run.
--
-- SO THIS MIGRATION CHANGES EXACTLY ONE FUNCTION: the one carrier that is both
-- wall-clock and on the certified path. The other wall-clock writers are real but off
-- that path, each needs its own argument about which clock is correct, and widening
-- this change to them would be exactly the drive-by that CLAUDE.md Part 1 §4 forbids.
-- They are filed as BUILD_QUEUE P0b-b.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- P. NOTHING IN FLIGHT. pg_stat_activity only.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND query ILIKE '%ottoq_determinism_pair%';
  IF v_n > 0 THEN
    RAISE EXCEPTION 'P FAILED: % certification pair(s) in flight', v_n;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 1. Snapshot before replacing, per APPLYING.md step 2.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0255_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';

-- ---------------------------------------------------------------------------
-- 2. The change, by anchored substitution. Three anchors, each asserted to occur
--    exactly once BEFORE it is used, and the body md5 pinned so a hotfix since I
--    read it raises instead of being silently overwritten.
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE
  d   text;
  nd  text;
  a1  text := E'DECLARE v_depot uuid; v_veh int := 0; v_sess int := 0; v_archive jsonb;';
  a2  text := E'  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;';
  a3  text := E'           last_state_change=now(),';
  v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_release_depot';
  IF md5(v_src) <> '46738ed8edc6d3bd8082508c3bf66613' THEN
    RAISE EXCEPTION 'GUARD FAILED: ottoq_sim_release_depot body is % (% chars), expected '
                    '46738ed8edc6d3bd8082508c3bf66613 at 12780. Someone changed it since '
                    'I read it; the anchors below are against the wrong source.',
                    md5(v_src), length(v_src);
  END IF;

  d := pg_get_functiondef('public.ottoq_sim_release_depot(uuid,text)'::regprocedure);

  IF (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 THEN
    RAISE EXCEPTION 'ANCHOR 1 occurs % time(s), expected 1', (length(d)-length(replace(d,a1,'')))/length(a1);
  END IF;
  IF (length(d)-length(replace(d,a2,'')))/length(a2) <> 1 THEN
    RAISE EXCEPTION 'ANCHOR 2 occurs % time(s), expected 1', (length(d)-length(replace(d,a2,'')))/length(a2);
  END IF;
  IF (length(d)-length(replace(d,a3,'')))/length(a3) <> 1 THEN
    RAISE EXCEPTION 'ANCHOR 3 occurs % time(s), expected 1', (length(d)-length(replace(d,a3,'')))/length(a3);
  END IF;

  nd := replace(d, a1,
        E'DECLARE v_depot uuid; v_veh int := 0; v_sess int := 0; v_archive jsonb;\n        v_sim_clock timestamptz;   /* 0255 */');

  nd := replace(nd, a2,
        E'  SELECT depot_id, sim_clock_current INTO v_depot, v_sim_clock\n    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;   /* 0255: the run''s own clock */');

  nd := replace(nd, a3,
        E'           last_state_change=COALESCE(v_sim_clock, now()),   /* 0255: sim domain, per 0065. now() here is a\n              wall clock inside a column ottoq_world_fingerprint hashes, and because now() is the TRANSACTION\n              timestamp both arms of a pair got the same value -- so the pair could never fail on it and only\n              two separate pairs could. db/checks/0173. */');

  EXECUTE nd;
END
$mig$;

-- ---------------------------------------------------------------------------
-- 3. Classify, in the SAME migration so it cannot be forgotten. The floor MOVES
--    and every canon must be re-earned -- that is the accepted, stated cost.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
('0255_the_teardown_stamps_the_wall_clock_into_a_hashed_column', true,
 'Replaces last_state_change=now() with COALESCE(v_sim_clock, now()) inside ottoq_sim_release_depot''s '
 'sim-only v_world_reset branch, so the natural-completion teardown stamps the run''s own sim clock. '
 'END-STATE VALUES CHANGE on any column whose run reaches the scenario sim-clock end -- busy_day/171717/48t '
 'at exactly tick 48 -- so endst moves there and the floor moves for all. This is the carrier convicted in '
 'db/checks/0173 for the 48-tick column failing 0193''s bar twice. Production is unreachable from the changed '
 'line: v_world_reset = (depots.feed_mode = ''sim'').')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. Assertions.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_src text; v_n int; v_floor timestamptz;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_release_depot';

  -- A1. The wall clock is gone from the stamp, and gone for the right reason:
  --     no bare `last_state_change=now()` survives anywhere in the body.
  IF v_src ~ 'last_state_change[[:space:]]*=[[:space:]]*now\(\)' THEN
    RAISE EXCEPTION 'A1 FAILED: a bare last_state_change=now() still survives';
  END IF;

  -- A2. It was REPLACED, not deleted. The column must still be written -- a teardown
  --     that stops stamping it would leave stale transition times, which is a
  --     different defect, not a fix.
  IF v_src !~ 'last_state_change[[:space:]]*=[[:space:]]*COALESCE\(v_sim_clock, now\(\)\)' THEN
    RAISE EXCEPTION 'A2 FAILED: the stamp is not COALESCE(v_sim_clock, now())';
  END IF;

  -- A3. The clock is actually fetched, and from the run this teardown is for.
  IF v_src !~ 'SELECT depot_id, sim_clock_current INTO v_depot, v_sim_clock' THEN
    RAISE EXCEPTION 'A3 FAILED: v_sim_clock is never read from the run row';
  END IF;
  IF v_src !~ 'v_sim_clock timestamptz' THEN
    RAISE EXCEPTION 'A3 FAILED: v_sim_clock is not declared';
  END IF;

  -- A4. PRODUCTION IS STILL UNREACHABLE FROM THE CHANGED LINE. The sim/production
  --     gate must survive verbatim, or this migration has quietly changed what
  --     happens to a real depot on an external feed (0114, and P2 of 0039).
  IF v_src !~ 'v_world_reset := \(v_feed = ''sim''\)' THEN
    RAISE EXCEPTION 'A4 FAILED: the sim-only feed gate is gone or altered';
  END IF;
  IF v_src !~ 'IF v_world_reset THEN' THEN
    RAISE EXCEPTION 'A4 FAILED: the v_world_reset guard around the fleet reset is gone';
  END IF;

  -- A5. Nothing else moved. The body is the old one plus exactly the three
  --     substitutions, so its length must have grown and the snapshot must exist.
  SELECT count(*) INTO v_n FROM public.ottoq_schema_snapshots
   WHERE label='0255_pre' AND object_name='ottoq_sim_release_depot';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A5 FAILED: % pre-change snapshot(s) recorded, expected 1', v_n;
  END IF;
  IF length(v_src) <= 12780 THEN
    RAISE EXCEPTION 'A5 FAILED: body is % chars, expected longer than the 12780 it replaced', length(v_src);
  END IF;

  -- A6. The world fingerprint is UNTOUCHED -- this migration fixes the write, never
  --     the hash. If it had edited the fingerprint, fp would move for a second,
  --     unrelated reason and the round behind this would be uninterpretable.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_world_fingerprint';
  IF md5(v_src) <> '945fa4b9e7bfd0d1c027fd92dc85fa06' THEN
    RAISE EXCEPTION 'A6 FAILED: ottoq_world_fingerprint changed (%); it must not', md5(v_src);
  END IF;

  -- A7. forces_recert is recorded and the floor has therefore MOVED. Asserting the
  --     cost was paid deliberately rather than discovered later.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage
   WHERE name='0255_the_teardown_stamps_the_wall_clock_into_a_hashed_column' AND forces_recert;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A7 FAILED: the forces_recert=TRUE lineage row is missing';
  END IF;
  SELECT public.ottoq_cert_recert_floor() INTO v_floor;
  IF v_floor <= '2026-09-09 09:46:27.088143+00'::timestamptz THEN
    RAISE EXCEPTION 'A7 FAILED: the recert floor did not move (still %); a forces_recert '
                    'migration that leaves the floor alone means canons stay green on a '
                    'changed engine', v_floor;
  END IF;

  RAISE NOTICE 'A1-A7 PASSED. Teardown now stamps sim time; production gate intact; '
               'fingerprint untouched; recert floor moved to %', v_floor;
END $$;

-- ===========================================================================
-- WHAT THIS DOES NOT DO
--
-- It does not certify busy_day/171717/48t. That needs two consecutive 48-tick pairs
-- above the NEW floor agreeing with each other on all fourteen atoms AND on
-- wsec.vehicles. Round 38 is the test and its prediction is committed separately
-- before it fires.
--
-- It does not touch the four other wall-clock writers found while scoping this
-- (twin.ottoq_world_advance, public.ottoq_cert_arm_wave, and the now() fallbacks in
-- twin.ottoq_sim_confirm_commands and public.ottoq_cert_arm). None is on the
-- determinism-pair path; each needs its own argument about the correct clock.
-- BUILD_QUEUE P0b-b.
-- ===========================================================================

-- ===========================================================================
-- APPLIED 2026-09-12 13:06:22 UTC (08:06 AM CT) -- version 20260912130622
--
-- A1-A7 all passed. Submitted WHOLE (exec-digest.py --check: safe, no comments inside
-- a stored body). Post-state, measured:
--     ottoq_sim_release_depot   md5 714f812d30e8f06df3f659b15d70f451, 13,247 chars
--                               (was 46738ed8edc6d3bd8082508c3bf66613, 12,780)
--     ottoq_world_fingerprint   945fa4b9e7bfd0d1c027fd92dc85fa06 -- UNCHANGED (A6)
--     recert floor              2026-09-09 09:46:27.088143 -> 2026-09-12 13:06:22.289808
--
-- THE BODY IS NOT DIGEST-COMPARABLE TO THIS FILE, and that is inherent to anchored
-- substitution: the file contains the three anchors and their replacements, never the
-- resulting body. So the pin above IS the record -- 714f812d... is what a later drift
-- check must compare against, not anything extractable from this file. Noted because
-- every other migration this week could be verified by digesting its own $function$
-- block, and this one cannot.
--
-- IMMEDIATE, EXPECTED CONSEQUENCE: every canon is now below the floor and must be
-- re-earned. ottoq_cert_coverage() dropped from nine OK to three within the same
-- minute -- not from this migration but because the six 6-hour columns aged past
-- max_age while the window ran. Both facts point the same way: round 38 re-earns
-- everything.
-- ===========================================================================
