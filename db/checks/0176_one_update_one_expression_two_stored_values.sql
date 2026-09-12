-- ===========================================================================
-- 0176  ONE UPDATE, ONE EXPRESSION, TWO STORED VALUES
--       (P0b-c convicted: the trigger re-stamps what 0255 fixed)
-- ===========================================================================
-- Measured 2026-09-12 14:21-14:26 UTC (09:21-09:26 AM CT), read-only, while round 38
-- was mid-flight (five of ten pairs fired). Nothing was written; no run was started.
-- pg_stat_activity showed no pair in flight at the time of the reads.
--
-- BUILD_QUEUE P0b-c asked what stamped a WALL clock on vehicles very early inside a
-- cert pair's transaction, invisible to the `endst` atom. It is answered. The answer
-- also says 0255 IS INCOMPLETE, and it says so BEFORE the round that was meant to
-- judge 0255 gets to the only pairs that test it (15:23 and 15:55 UTC).
--
-- ---------------------------------------------------------------------------
-- 1. THE MEASUREMENT THAT DECIDES IT, AND WHY IT NEEDS NO THIRD QUERY
-- ---------------------------------------------------------------------------
--
-- vehicles.last_state_change, both cert depots, 14:21 UTC -- i.e. the world left
-- behind by round 38's 14:15 pair (normal_day/171717/12t) and 13:43 pair (grid):
--
--   depot      state    last_state_change                  n    domain
--   flagship   offline  2026-09-01 08:00:00+00            96    SIM   (02:00 + 12*30min)
--   flagship   offline  2026-09-12 14:15:00.155073+00     20    WALL  (= now(), job 558)
--   grid       offline  2026-09-01 05:00:00+00             3    SIM   (02:00 + 6*30min)
--   grid       offline  2026-09-12 13:43:00.080838+00      1    WALL  (= now(), job 555)
--
-- Every one of those 116 + 4 rows was written by ONE statement -- the teardown's
-- unplace in public.ottoq_sim_release_depot (line 158 of its body):
--
--     UPDATE vehicles
--        SET current_state='offline'::vehicle_state, current_stall_id=NULL,
--            last_state_change=COALESCE(v_sim_clock, now()),   /* 0255 */
--      ...  AND current_state <> 'offline'::vehicle_state;
--
-- ONE statement. ONE expression. v_sim_clock is read once into a local at the top of
-- the function, so the expression evaluates to ONE value for every row of the
-- statement. 96 rows stored 08:00:00 -- so v_sim_clock WAS NOT NULL and 0255's fix
-- DID fire. 20 rows of the same statement stored the transaction timestamp instead.
--
-- A single UPDATE cannot store two values for one expression. Therefore a BEFORE
-- trigger rewrote the column on a subset of the rows. No further query is needed to
-- establish that; the split IS the proof.
--
-- ---------------------------------------------------------------------------
-- 2. THE TRIGGER, AND THE RULE THAT SELECTS THE SUBSET
-- ---------------------------------------------------------------------------
--
--   trg_vehicle_state_change  BEFORE UPDATE ON vehicles -> public.log_vehicle_state_change()
--   body md5 64d128c6550424329b5e0a2e5d4fbff1, 3089 chars, as measured 14:26 UTC
--
-- Its tail, verbatim (the guard 0057 added and 0061 narrowed):
--
--     IF NEW.last_state_change IS NOT DISTINCT FROM OLD.last_state_change THEN
--       NEW.last_state_change = COALESCE(
--         (SELECT r.sim_clock_current FROM public.ottoq_sim_runs r
--           WHERE r.status = 'running'
--             AND r.depot_id = COALESCE(NEW.current_depot_id, NEW.home_depot_id)
--           ORDER BY r.started_at DESC, r.sim_run_id
--           LIMIT 1),
--         NOW());
--     END IF;
--
-- So the subset is exactly: vehicles whose state changed in this UPDATE **and** whose
-- previous stamp already equalled the value being written. At a teardown the value
-- being written IS the run's final sim clock, so the subset is precisely the vehicles
-- that last changed state during the final tick. 20 of 116 at 12 ticks; 1 of 4 on the
-- grid. The other 96 had an older stamp, so NEW was DISTINCT from OLD, the guard never
-- fired, and they kept 0255's sim-domain value.
--
-- ---------------------------------------------------------------------------
-- 3. WHY THE FALLBACK REACHES now() AND NOT THE SIM CLOCK
-- ---------------------------------------------------------------------------
--
-- The guard's first COALESCE branch is meant to supply a sim clock. It cannot, at a
-- teardown, because by then the run is no longer `running`. Both teardown routes flip
-- the status FIRST -- and both say so in their own comments:
--
--   route A, stopped arm:  public.ottoq_sim_stop_and_reset
--       "once mark_stopped flips the status, the lookup path can no longer find it"
--       PERFORM set_config('ottoq.sim_run_id', ..., true);
--       v_marked := ottoq_sim_mark_stopped(...);      <-- status flips here
--       RETURN ottoq_sim_release_depot(...);          <-- trigger fires in here
--
--   route B, natural completion: public.ottoq_sim_advance_tick
--       "0103: advance_tick_world writes status='completed' mid-function and still
--        returns a non-NULL clock"
--       PERFORM set_config('ottoq.sim_run_id', ..., true);
--       PERFORM ottoq_sim_release_depot(p_sim_run_id, 'sim_clock_end_reached');
--
-- status <> 'running' -> the subquery returns no row -> COALESCE falls through to
-- NOW(). The 2026-09-12 14:15:00.155073 and 13:43:00.080838 values above are that
-- NOW(), to the millisecond of each cron job's transaction start.
--
-- Note what both routes already do, one line before: they PIN THE RUN IN A GUC,
-- 'ottoq.sim_run_id', added by 0092 for this exact defect class -- a teardown whose
-- own writes can no longer find the run they are tearing down. The trigger is the one
-- teardown reader that does not consult it.
--
-- ---------------------------------------------------------------------------
-- 4. WHY THIS HAS BEEN INVISIBLE, AND WHERE IT IS NOT
-- ---------------------------------------------------------------------------
--
-- INVISIBLE INSIDE A PAIR, ALWAYS. now() is the TRANSACTION timestamp and both arms
-- of a pair are one transaction, so both arms stamp the identical wall clock. A pair
-- can never fail on this. It is not a defect the 14-atom verdict can see.
--
-- INVISIBLE ACROSS PAIRS AT 6, 12 AND 24 TICKS. Those horizons never reach the
-- scenario's end (every scenario is sim_duration_minutes = 1440 and a tick is 30 sim
-- minutes, so only 48 ticks arrives), so their only teardown is route A, at line 102
-- of ottoq_determinism_pair -- AFTER the arm's atoms, `endst` included, are captured.
-- The wall stamp lands in a world that the NEXT pair's ottoq_tick_invariance_reset_fleet
-- canonicalizes back to p_sim_start before anything hashes it. That is exactly why
-- 0175 measured grid endst.world STABLE across three days and across 0255 while the
-- grid depot is, right now, carrying a 13:43 wall clock on one of its four vehicles.
--
-- VISIBLE AT 48 TICKS. There, route B fires INSIDE tick 48, inside the pair's tick
-- loop, BEFORE the atoms are captured. The wall clock is in the world that
-- ottoq.ottoq_world_fingerprint hashes (it hashes last_state_change in its vehicles
-- section), so it enters `endst.world` and `wsec.vehicles`. Two pairs of the same
-- column in one round run in two different transactions, get two different now()s,
-- and disagree. That is 0193's inter-pair bar, and it is the only bar pointed at a
-- column that runs twice per round.
--
-- This is the same carrier 0173 convicted and 0255 was written to kill. 0255 killed
-- the literal now() in release_depot's own UPDATE. It did not -- could not -- stop a
-- BEFORE trigger from overwriting the value that UPDATE supplies.
--
-- ---------------------------------------------------------------------------
-- 5. PREDICTION, COMMITTED 2026-09-12 14:30 UTC, BEFORE THE PAIRS THAT TEST IT
-- ---------------------------------------------------------------------------
--
-- Round 38's 48-tick pairs fire at 15:23 and 15:55 UTC (jobs 562, 563), both
-- busy_day/171717/48t. They are the round's only test of 0255.
--
--   PREDICTION 1 -- THEY WILL STILL DISAGREE WITH EACH OTHER. endst will differ in
--   `world`, and wsec will name `vehicles`, exactly as in round 37. Each pair will
--   pass internally (all 14 atoms equal, both arms sharing one now()); the inter-pair
--   comparison will fail. 0255 fixed the explicit write; the trigger re-stamps it.
--
--   PREDICTION 2 -- THE FAILING VALUE WILL BE EACH PAIR'S OWN TRANSACTION START.
--   After the round, flagship vehicles will hold two distinct last_state_change
--   values: 2026-09-02 02:00:00+00 (the 48-tick sim end: 02:00 + 48*30min) for the
--   majority, and 2026-09-12 15:55:00.xxx (job 563's now()) for the subset that last
--   changed state in tick 48. Same shape as the 96/20 split measured above, at a
--   different clock.
--
--   PREDICTION 3 -- THE SIX 12t/24t COLUMNS WILL NOT MOVE. Their teardown is route A,
--   after their atoms are captured, so the wall stamp cannot reach their verdict. If
--   any of them moves, section 4's route-A/route-B distinction is wrong and this
--   whole conviction needs re-opening.
--
-- If PREDICTION 1 is wrong -- if the two 48t pairs agree -- then the trigger path is
-- not reached at 48 ticks and 0255 was sufficient. That is a real possible outcome and
-- it is written here so it cannot be explained away afterwards.
--
-- ---------------------------------------------------------------------------
-- 6. THE FIX (migration 0256, drafted; applies only after round 38's last pair)
-- ---------------------------------------------------------------------------
--
-- Give the trigger's fallback the GUC both teardown routes already set, as a second
-- COALESCE branch, status-independent:
--
--     COALESCE(
--       (running run for this depot -- unchanged, first, so no existing behaviour moves),
--       (SELECT r.sim_clock_current FROM public.ottoq_sim_runs r   /* 0256 */
--         WHERE r.sim_run_id = NULLIF(current_setting('ottoq.sim_run_id', true),'')::uuid),
--       NOW())
--
-- Production is unchanged by construction: a real-feed depot has no sim run and no GUC
-- (set_config(...,true) is transaction-local), so it still falls to NOW() exactly as
-- before. The new branch can only fire where the old code was already falling through
-- to a wall clock. It forces a recert: it changes a value inside a hashed column.
--
-- ===========================================================================
-- RE-RUNNABLE MEASUREMENTS
-- ===========================================================================

-- 6.1  The split. Run after any cert pair: two domains in one column means the
--      trigger rewrote a subset of one statement's rows.
SELECT d.name AS depot,
       v.current_state,
       v.last_state_change,
       CASE WHEN v.last_state_change > now() - interval '24 hours'
                 AND v.last_state_change <= now() THEN 'WALL'
            ELSE 'SIM' END AS clock_domain,
       count(*) AS n
  FROM public.vehicles v
  JOIN public.depots d ON d.id = v.current_depot_id
 WHERE v.current_depot_id IN ('11111111-1111-1111-1111-111111111111'::uuid,
                              'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid)
   AND v.category = 'autonomous'
 GROUP BY 1,2,3,4
 ORDER BY 1, 3 DESC;

-- 6.2  The trigger body, pinned. If this md5 moves, re-read section 2 before
--      trusting anything above it.
SELECT p.proname,
       md5(p.prosrc) AS body_md5,
       length(p.prosrc) AS len,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'NOW\(\)', 'g')) AS now_sites
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'log_vehicle_state_change';

-- 6.3  Every routine that writes last_state_change, with the expression it writes.
--      The complete sweep 0173 attempted and got wrong by reading for a literal
--      now() instead of for the assignment. 39 routines at the time of writing.
WITH r AS (
  SELECT n.nspname||'.'||p.proname AS fn,
         pg_get_function_identity_arguments(p.oid) AS args,
         p.prosrc AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin') AND p.prosrc LIKE '%last_state_change%'
)
SELECT fn, args,
       (SELECT string_agg(DISTINCT trim(x[1]), ' | ')
          FROM regexp_matches(src, 'last_state_change\s*=\s*([^,;\n]+)', 'g') x) AS assigned_exprs
  FROM r
 ORDER BY 1;

-- 6.4  The inter-pair question this predicts. Run after 15:55 UTC.
SELECT to_char(sr.started_at,'MM-DD HH24:MI') AS fired,
       (sr.validation_notes::jsonb->>'ticks') AS ticks,
       (sr.validation_notes::jsonb->'arm_a'->'endst'->>'world') AS endst_world,
       (sr.validation_notes::jsonb->'arm_a'->'wsec'->>'vehicles') AS wsec_vehicles
  FROM public.ottoq_sim_runs sr
 WHERE sr.run_by = 'cert_harness'
   AND sr.depot_id = '11111111-1111-1111-1111-111111111111'::uuid
   AND jsonb_typeof(sr.validation_notes::jsonb->'arm_a') = 'object'
   AND (sr.validation_notes::jsonb->>'ticks')::int = 48
   AND sr.started_at > '2026-09-12 00:00:00+00'
 GROUP BY 1,2,3,4
 ORDER BY 1;
