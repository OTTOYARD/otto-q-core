-- migration-version: PENDING
-- migration-name: 0258_the_comment_states_the_invariant_and_no_code_holds_it
-- ===========================================================================
-- 0258  THE COMMENT STATES THE INVARIANT AND NO CODE HOLDS IT
-- ===========================================================================
-- probe:          db/checks/0182 section 5; BUILD_QUEUE P0b-b
-- forces_recert:  FALSE -- asserted, not assumed: A5 measures that no cert or benchmark
--                 run has ever carried the payload this guard refuses, so no existing
--                 verdict could have been computed differently, and A6 pins the world
--                 fingerprint and the pair by md5.
--
-- APPLY THIRD, after 0256 and 0257. 0257's A6 pins ottoq_determinism_pair by md5 and
-- this migration does not touch it -- but the window order is 0256 -> 0257 -> 0258
-- regardless, because 0257 asserts the state of the tree it was written against.
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT. pg_stat_activity is the only authority.
--
-- ---------------------------------------------------------------------------
-- THE DEFECT, IN THE FUNCTION'S OWN WORDS
-- ---------------------------------------------------------------------------
--
-- public.ottoq_sim_advance_tick_world, lines 15-20, verbatim:
--
--   -- PLAYBACK CLOCK. 'live' = TRUE 1:1 (sim advances by REAL elapsed x speed_x, so
--   -- one real second is one sim second at 1x). 'fixed' (default) keeps the historical
--   -- tick_interval_seconds * time_scale behaviour so certs/benchmarks stay deterministic.
--   -- The 0.05..10 clamp keeps a stalled metronome or a long GC pause from teleporting
--   -- the world; it never applies in fixed mode.
--   IF COALESCE(v_run.payload->>'playback_mode','fixed') = 'live' THEN
--
-- The comment names the invariant -- "'fixed' ... so certs/benchmarks stay
-- deterministic" -- and nothing enforces it. In 'live' mode the size of every tick is
-- real elapsed wall time:
--
--   v_tick_minutes := LEAST(10.0, GREATEST(0.0,
--     (EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_run.last_tick_at, clock_timestamp())))
--      * COALESCE((v_run.payload->>'speed_x')::numeric, 1.0)) / 60.0));
--
-- WHY THIS IS NOT LIKE THE OTHER WALL CLOCKS ON P0b-b's LIST. Every other one stamps a
-- column. This one sets the SIM CLOCK ITSELF, so every downstream duration, deadline,
-- booking window and charge interval in the arm would differ. It would not be subtle and
-- no single atom would name it; the pair simply could never pass, and the cause would be
-- a jsonb key with no migration behind it.
--
-- AND IT IS HELD SHUT BY A NULL, WHICH IS NOT A GUARD. Measured across every run ever:
--
--   run_by            playback_mode      runs   window
--   cert_harness      (null -> fixed)     971   2026-08-29 16:59 .. 2026-09-12 14:43
--   benchmark         (null -> fixed)       9
--   production_live   (null -> fixed)       8
--   operator_demo     'live'                1   2026-08-29 03:35  <- the only one, ever
--   claude_v2_...     (null -> fixed)       1
--
-- twin.ottoq_sim_start_run never writes the key, so a cert run gets 'fixed' by absence.
-- ottoq_determinism_pair contains zero mentions of 'playback', so it does not check.
-- One UPDATE to ottoq_sim_runs.payload -- by a demo path, an operator tool, or a hand at
-- a console -- is all it takes, and because the key is read EVERY TICK rather than once
-- at start, it can be set on a run already in flight.
--
-- ---------------------------------------------------------------------------
-- WHY THE GUARD GOES HERE AND NOT IN THE PAIR'S PRE-FLIGHT
-- ---------------------------------------------------------------------------
--
-- My first draft was a pre-flight refusal in ottoq_determinism_pair, beside the
-- scenario/depot refusal it already carries. Wrong place, for a reason worth recording:
-- the SCENARIO does not carry playback_mode. ottoq_scenarios has no such column and
-- start_run never copies one, so a pre-flight read of the scenario would have asserted
-- nothing at all -- a guard that always passes, which is worse than none because it
-- reads like cover. And a pre-flight on the RUN would still miss the case that actually
-- worries me, the payload edited after tick one.
--
-- So the guard goes at the point of use, in the function that reads the key, where it
-- covers a mid-run edit too.
--
-- IT REFUSES RATHER THAN COERCING. Silently forcing a cert run back to 'fixed' would
-- produce a run that disagrees with its own payload -- a second thing to be wrong about.
-- A certification whose clock is not the clock it claims must not produce a verdict at
-- all. The scope is exactly the two run classes the comment names, cert_harness and
-- benchmark: production and demo runs keep 'live' mode untouched, which is what it was
-- built for.
--
-- This is the narrowest change that makes the comment true.
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
SELECT '0258_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_advance_tick_world';

-- ---------------------------------------------------------------------------
-- 2. The change, by anchored substitution. One anchor, asserted unique before use,
--    and both md5s pinned so a hotfix since I read it raises instead of being
--    silently overwritten.
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE
  d text; nd text; a1 text; v_src text;
BEGIN
  a1 := E'  IF COALESCE(v_run.payload->>''playback_mode'',''fixed'') = ''live'' THEN\n';

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_advance_tick_world';
  IF md5(v_src) <> '62f1f30165d2f4ac61635b38db191824' THEN
    RAISE EXCEPTION 'GUARD FAILED: ottoq_sim_advance_tick_world body is % (% chars), expected '
                    '62f1f30165d2f4ac61635b38db191824 at 9826. Someone changed it since I '
                    'read it; the anchor below is against the wrong source.',
                    md5(v_src), length(v_src);
  END IF;

  d := pg_get_functiondef('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure);
  IF md5(d) <> '7ef368f36476e38b0985af722e1f7062' THEN
    RAISE EXCEPTION 'GUARD FAILED: functiondef md5 is % (% chars), expected '
                    '7ef368f36476e38b0985af722e1f7062 at 10198', md5(d), length(d);
  END IF;

  IF (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 THEN
    RAISE EXCEPTION 'ANCHOR 1 occurs % time(s), expected 1', (length(d)-length(replace(d,a1,'')))/length(a1);
  END IF;

  nd := replace(d, a1,
        E'  /* 0258: THE COMMENT ABOVE STATES THE INVARIANT AND NOTHING HELD IT. In ''live'' mode\n'
     || E'     v_tick_minutes is REAL ELAPSED TIME, so the sim clock itself -- not merely a stamp --\n'
     || E'     would differ between two arms of one pair, and every duration, deadline, booking and\n'
     || E'     charge interval downstream with it. A cert run got ''fixed'' only because\n'
     || E'     twin.ottoq_sim_start_run never writes the key: held shut by a NULL. The key is read\n'
     || E'     EVERY tick, so it can also be set on a run already in flight, which is why the guard\n'
     || E'     is here at the point of use rather than in the pair''s pre-flight (and why a\n'
     || E'     pre-flight read of the SCENARIO would have asserted nothing -- ottoq_scenarios has\n'
     || E'     no such column). It REFUSES rather than coercing: a certification whose clock is not\n'
     || E'     the clock its payload claims must not produce a verdict. Scope is exactly the two run\n'
     || E'     classes the comment names; production and demo keep ''live'' untouched.\n'
     || E'     db/checks/0182 section 5. Measured: 0 of 980 cert/benchmark runs have ever carried it. */\n'
     || E'  IF COALESCE(v_run.payload->>''playback_mode'',''fixed'') = ''live''\n'
     || E'     AND COALESCE(v_run.run_by,'''') IN (''cert_harness'',''benchmark'') THEN\n'
     || E'    RAISE EXCEPTION ''ottoq_sim_advance_tick_world: run % is run_by=% with ''\n'
     || E'                    ''playback_mode=live. A cert or benchmark run may not advance on the ''\n'
     || E'                    ''wall clock -- the tick SIZE would be real elapsed time and the two ''\n'
     || E'                    ''arms of a pair could never agree. Refused rather than coerced to ''\n'
     || E'                    ''fixed, so the run cannot disagree with its own payload. 0258.'',\n'
     || E'                    p_sim_run_id, v_run.run_by USING ERRCODE = ''P0001'';\n'
     || E'  END IF;\n'
     || a1);

  EXECUTE nd;
END
$mig$;

-- ---------------------------------------------------------------------------
-- 3. Classify. FALSE, and A5/A6 measure it.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
('0258_the_comment_states_the_invariant_and_no_code_holds_it', false,
 'Adds a refusal to ottoq_sim_advance_tick_world: a run_by cert_harness/benchmark run whose payload '
 'says playback_mode=live now raises instead of advancing the sim clock by real elapsed wall time. '
 'Pure guard -- no value any fingerprint hashes changes, and A5 measures that no cert or benchmark '
 'run in the table''s history has ever carried that payload, so no existing verdict could have been '
 'computed differently. The other branch (fixed) is byte-identical. Probe db/checks/0182 section 5.')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. Assertions.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_src text; v_live int; v_fixed_runs int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_advance_tick_world';

  -- A1. The guard exists and names both classes.
  IF v_src !~ 'cert_harness' OR v_src !~ 'benchmark' THEN
    RAISE EXCEPTION 'A1 FAILED: the guard does not name both protected run classes';
  END IF;

  -- A2. It RAISES. A coercion would be a different change and is not this one.
  IF v_src !~ 'playback_mode=live' THEN
    RAISE EXCEPTION 'A2 FAILED: no refusal message for the live case';
  END IF;

  -- A3. The live branch SURVIVES for everyone else. Deleting it would break the demo
  --     path this guard is explicitly not about.
  IF (SELECT count(*) FROM regexp_matches(v_src, 'playback_mode', 'g')) < 2 THEN
    RAISE EXCEPTION 'A3 FAILED: % mentions of playback_mode, expected the guard AND the original branch',
      (SELECT count(*) FROM regexp_matches(v_src, 'playback_mode', 'g'));
  END IF;
  IF v_src !~ 'clock_timestamp\(\) - COALESCE\(v_run\.last_tick_at' THEN
    RAISE EXCEPTION 'A3 FAILED: the live-mode tick computation is gone';
  END IF;

  -- A4. The fixed branch is untouched -- the one every certification takes.
  IF v_src !~ 'v_tick_minutes := \(v_run\.tick_interval_seconds::numeric \* v_run\.time_scale\) / 60\.0' THEN
    RAISE EXCEPTION 'A4 FAILED: the fixed-mode tick computation changed';
  END IF;

  -- A5. forces_recert=FALSE IS A MEASUREMENT. No cert or benchmark run has ever carried
  --     the payload this guard refuses, so no past verdict could have differed.
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') IN ('cert_harness','benchmark')
     AND COALESCE(payload->>'playback_mode','fixed') <> 'fixed';
  IF v_live > 0 THEN
    RAISE EXCEPTION 'A5 FAILED: % cert/benchmark run(s) carry a non-fixed playback_mode. This '
                    'migration may NOT claim forces_recert=FALSE -- those runs advanced on a wall '
                    'clock and their canons are void', v_live;
  END IF;
  SELECT count(*) INTO v_fixed_runs FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') IN ('cert_harness','benchmark');
  IF v_fixed_runs < 100 THEN
    RAISE EXCEPTION 'A5 FAILED: only % cert/benchmark runs exist -- too few for the clean '
                    'measurement above to mean anything', v_fixed_runs;
  END IF;

  -- A6. Nothing hashed moved.
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='ottoq' AND p.proname='ottoq_world_fingerprint')
     <> '945fa4b9e7bfd0d1c027fd92dc85fa06' THEN
    RAISE EXCEPTION 'A6 FAILED: ottoq_world_fingerprint moved';
  END IF;

  RAISE NOTICE '0258 OK: guard added; % cert/benchmark runs checked, 0 non-fixed', v_fixed_runs;
END $$;

-- ---------------------------------------------------------------------------
-- 5. Snapshot after.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0258_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_advance_tick_world';

SELECT md5(p.prosrc) AS body_md5_post, length(p.prosrc) AS len_post,
       public.ottoq_cert_recert_floor() AS recert_floor_unchanged
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_advance_tick_world';
