-- ===========================================================================
-- 0182  P0b-b: THE FOUR OFF-PATH WALL CLOCKS, JUDGED ONE AT A TIME
--       -- and a fifth nobody is guarding
-- ===========================================================================
-- Measured 2026-09-12 14:20-15:10 UTC (09:20-10:10 AM CT), read-only, while round 38
-- ran. Nothing was written; no run was started.
--
-- BUILD_QUEUE P0b-b: 0255 narrowed its own fix to the one wall-clock writer on the
-- determinism-pair path and filed the other four, each needing "its own argument about
-- which clock is correct". Those arguments follow. Three are closed with NO CHANGE and
-- the reasons differ; one stays latent. The fifth item was not on the list and is the
-- only one that needs a migration.
--
-- ---------------------------------------------------------------------------
-- 1. twin.ottoq_world_advance -- CORRECT AS WRITTEN. NO CHANGE.
-- ---------------------------------------------------------------------------
--
-- `v_now timestamptz := now()`, writes last_state_change=v_now. A true wall clock.
--
-- Its run selection, read from the body:
--     SELECT * INTO v_run FROM ottoq_sim_runs
--      WHERE run_by = 'production_live' AND status = 'running'
--      ORDER BY started_at DESC LIMIT 1;
--     IF NOT FOUND THEN RAISE WARNING '...no running production run'; RETURN; END IF;
--
-- It serves PRODUCTION only, and a production depot's world runs on the wall clock --
-- that IS its sim clock. So now() is not a defect here, it is the right clock, and
-- changing it would be the error. Measured state: zero production_live runs are
-- running, so it currently warns and returns every time it fires.
--
-- AND MY OWN HYPOTHESIS DIED HERE, recorded because it was the reason I opened this.
-- 0175 logged an unexplained wall stamp at arm start and I suspected this function,
-- since the metronome fires on the same minute boundary as the cert jobs. It cannot be:
-- cert runs are run_by='cert_harness' and never match that WHERE. The real answer was
-- elsewhere entirely (db/checks/0176, the BEFORE trigger).
--
-- A CORRECTION TO MY OWN CALLER COUNT, same class as 0173's sweep error. A
-- `prosrc ~ name` scan reported four callers; two were COMMENTS:
--     public.ottoq_cron_tick                  BEGIN PERFORM ottoq_world_advance(); ...   REAL
--     public.ottoq_sim_decide_and_dispatch    "-- beat (twin.ottoq_world_advance, ...)"  comment
--     twin.ottoq_sim_vehicle_exception_handler "-- reached from twin.ottoq_world_advance" comment
--     public.ottoq_production_start           (sets the GUC; real)
-- The second one mattered: decide_and_dispatch IS on the cert tick path, so had it been
-- a real call 0255's scope claim would have been wrong. It is a comment. A name-match
-- count over function source is not a call graph.
--
-- ---------------------------------------------------------------------------
-- 2/3. public.ottoq_cert_arm and public.ottoq_cert_arm_wave -- DORMANT. NO CHANGE.
-- ---------------------------------------------------------------------------
--
-- Both write last_state_change=v_now where v_now carries a wall clock
-- (cert_arm_wave declares `:= now()`; cert_arm uses `COALESCE(p_start, now())`).
-- Both are reachable from exactly one routine, public.ottoq_cert_battery_step, which has
-- ZERO in-database callers. Its only entry point is a cron job, and the job is OFF:
--
--     jobid 13  ottoq-cert-battery  '* * * * *'  active = FALSE
--     9,240 historical runs, last one 2026-07-30 12:54:00 UTC
--
-- That is better evidence than "zero tracked calls": the job exists, it has six weeks of
-- history, and somebody switched it off six weeks ago. So these two are a latent hazard
-- in a disabled harness. The correct action is to leave them and to record the
-- precondition: IF jobid 13 IS EVER RE-ENABLED, these two must be fixed first, because
-- they would stamp wall clocks into vehicles.last_state_change -- which endst hashes
-- (0180) -- on whatever depot they are pointed at.
--
-- ---------------------------------------------------------------------------
-- 4. twin.ottoq_sim_confirm_commands -- UNREACHABLE FALLBACK. NO CHANGE, BUT SAY WHY.
-- ---------------------------------------------------------------------------
--
-- `v_now := COALESCE(p_clock, now())`. It IS on the certification tick path, so the
-- now() half had to be proven unreachable rather than assumed. Its two real callers:
--
--     public.ottoq_sim_advance_tick_world:39  PERFORM ottoq_sim_confirm_commands(p_sim_run_id, v_new_sim_clock);
--     public.ottoq_api_twin_apply_commands:5  v_confirmed := ottoq_sim_confirm_commands(p_sim_run_id, v_clock);
--
-- and on the cert path v_new_sim_clock cannot be NULL, because eight lines earlier:
--
--     :30  v_new_sim_clock := v_run.sim_clock_current + (v_tick_minutes || ' minutes')::interval;
--     :31  IF v_new_sim_clock >= v_run.sim_clock_end THEN v_new_sim_clock := v_run.sim_clock_end; v_completed := TRUE; END IF;
--
-- It is assigned unconditionally and only ever clamped. So the fallback is dead on this
-- path. NOTE the distinction that matters for the 48-tick work: the out-parameter
-- `out_sim_clock_after` CAN be NULL at completion -- that is what route A of
-- ottoq_sim_advance_tick tests -- but the LOCAL v_new_sim_clock never is. Two different
-- things with similar names, and conflating them would have produced a fix for a bug
-- that does not exist.
--
-- ---------------------------------------------------------------------------
-- 5. THE ONE THAT WAS NOT ON THE LIST: A TICK WHOSE SIZE IS REAL ELAPSED TIME
-- ---------------------------------------------------------------------------
--
-- Found while reading advance_tick_world for item 4, twelve lines above it:
--
--     IF COALESCE(v_run.payload->>'playback_mode','fixed') = 'live' THEN
--       -- TRUE 1:1. clock_timestamp() (NOT now(), which is transaction time and does
--       -- not advance inside a transaction)...
--       v_tick_minutes := LEAST(10.0, GREATEST(0.0,
--         (EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_run.last_tick_at, clock_timestamp())))
--          * COALESCE((v_run.payload->>'speed_x')::numeric, 1.0)) / 60.0));
--     ELSE
--       v_tick_minutes := (v_run.tick_interval_seconds::numeric * v_run.time_scale) / 60.0;
--     END IF;
--
-- In 'live' mode THE SIZE OF EVERY TICK IS HOW MUCH REAL TIME PASSED. Deliberately, and
-- the comment is careful about why it uses clock_timestamp() rather than now(). For a
-- demo that is exactly right. For a certification it is fatal in a way nothing else on
-- this list is: it is not a stamp on a hashed column, it is the SIM CLOCK ITSELF, so
-- every downstream duration, deadline, booking and charge interval would differ between
-- two arms of the same pair. No fingerprint would be subtle about it; the pair simply
-- could never pass.
--
-- MEASURED -- it has never happened, and nothing prevents it:
--
--   run_by            playback_mode     runs   window
--   cert_harness      (null -> fixed)    971   2026-08-29 16:59 .. 2026-09-12 14:43
--   benchmark         (null -> fixed)      9
--   production_live   (null -> fixed)      8
--   operator_demo     'live'               1   2026-08-29 03:35  <-- the only one, ever
--   claude_v2_...     (null -> fixed)      1
--
-- And `ottoq_determinism_pair` contains ZERO mentions of 'playback': it does not check.
-- A scenario payload carrying playback_mode='live' would be accepted, would run, and
-- would produce a pair that fails for a reason no atom names -- or worse, a scenario
-- whose payload is edited between two pairs, making one column irreproducible with no
-- migration to blame.
--
-- THE FIX IS A PRE-FLIGHT REFUSAL, and the pair already has the pattern. It refuses a
-- scenario/depot mismatch today:
--     IF v_scen_depot IS DISTINCT FROM p_depot THEN
--       RAISE EXCEPTION 'determinism_pair: scenario % is bound to depot %, but the pair
--                        was told to run depot %. The arms would tick one world and be
--                        fingerprinted against another.' ...
-- One more refusal of the same shape, for the same reason, costs nothing and closes a
-- hole that is currently held shut by a NULL. Drafted as migration 0258,
-- forces_recert=FALSE (it adds a guard; it changes no value anything hashes).
--
-- ---------------------------------------------------------------------------
-- 6. THE SCORE
-- ---------------------------------------------------------------------------
--
--   twin.ottoq_world_advance            NO CHANGE -- the wall clock is correct there
--   public.ottoq_cert_arm               NO CHANGE -- dormant behind a disabled cron job
--   public.ottoq_cert_arm_wave          NO CHANGE -- same, same precondition
--   twin.ottoq_sim_confirm_commands     NO CHANGE -- fallback proven unreachable
--   advance_tick_world 'live' mode      GUARD IT  -- migration 0258
--
-- P0b-b closes with one migration and four written arguments, which is the point of
-- having made it a list item instead of sweeping all five in 0255. Three of the four
-- would have been WRONG to change.
--
-- ===========================================================================
-- RE-RUNNABLE MEASUREMENTS
-- ===========================================================================

-- 6.1  playback_mode across every run. 'live' must never appear on a cert_harness row.
SELECT COALESCE(run_by,'(null)') AS run_by,
       COALESCE(payload->>'playback_mode','(null -> fixed)') AS playback_mode,
       count(*) AS runs, min(started_at) AS first_seen, max(started_at) AS last_seen
  FROM public.ottoq_sim_runs
 GROUP BY 1,2
 ORDER BY runs DESC;

-- 6.2  THE ASSERTION. Must return zero rows. If it ever returns one, that column's
--      canon is void and no migration caused it.
SELECT sim_run_id, started_at, payload->>'playback_mode' AS playback_mode
  FROM public.ottoq_sim_runs
 WHERE run_by = 'cert_harness'
   AND COALESCE(payload->>'playback_mode','fixed') <> 'fixed'
 ORDER BY started_at DESC;

-- 6.3  The dormant harness. active=false is the load-bearing column.
SELECT j.jobid, j.jobname, j.schedule, j.active,
       (SELECT count(*) FROM cron.job_run_details d WHERE d.jobid = j.jobid) AS runs,
       (SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid) AS last_run
  FROM cron.job j
 WHERE j.command ~* 'cert_battery|cert_arm'
 ORDER BY j.jobid;

-- 6.4  Every writer of last_state_change with the expression it writes -- the sweep done
--      the way 0255 corrected 0173 into doing it, returning matched text not a boolean.
WITH r AS (
  SELECT n.nspname||'.'||p.proname AS fn,
         pg_get_function_identity_arguments(p.oid) AS args,
         p.prosrc AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin') AND p.prosrc LIKE '%last_state_change%'
)
SELECT fn, args,
       (SELECT string_agg(DISTINCT trim(x[1]), ' | ')
          FROM regexp_matches(src, 'last_state_change\s*=\s*([^,;\n]+)', 'g') x) AS assigned_exprs,
       (src ~ ':=\s*now\(\)') AS declares_a_wall_clock_local
  FROM r
 ORDER BY 1;
