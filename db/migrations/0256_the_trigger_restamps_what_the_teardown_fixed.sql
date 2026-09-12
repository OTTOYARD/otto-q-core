-- migration-version: 20260912165023
-- migration-name: 0256_the_trigger_restamps_what_the_teardown_fixed
-- ===========================================================================
-- 0256  THE TRIGGER RE-STAMPS WHAT THE TEARDOWN FIXED
-- ===========================================================================
-- probe:          db/checks/0176; BUILD_QUEUE P0b-c; follows 0255, 0092, 0061, 0057
-- forces_recert:  TRUE  -- the row is inserted by this migration, not later
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT. pg_stat_activity is the only
-- authority: ottoq_sim_runs cannot see an in-flight pair (both arms are one
-- uncommitted transaction) and cron.job_run_details reports one as succeeded in
-- about a second.
--
-- ---------------------------------------------------------------------------
-- THE DEFECT
-- ---------------------------------------------------------------------------
--
-- 0255 replaced `last_state_change=now()` with `COALESCE(v_sim_clock, now())` in
-- ottoq_sim_release_depot's teardown unplace. The fix fired. It was not sufficient,
-- and db/checks/0176 measured why in one query: after the 14:15 UTC pair on
-- 2026-09-12, 96 flagship vehicles held 2026-09-01 08:00:00 (the run's sim clock) and
-- 20 held 2026-09-12 14:15:00.155073 (the transaction's wall clock) -- two values, from
-- ONE statement with ONE expression. A BEFORE trigger rewrote the subset.
--
-- The trigger is trg_vehicle_state_change -> public.log_vehicle_state_change(), and the
-- rewriting rule is the guard 0057 added and 0061 narrowed:
--
--     IF NEW.last_state_change IS NOT DISTINCT FROM OLD.last_state_change THEN
--       NEW.last_state_change = COALESCE(
--         (SELECT r.sim_clock_current FROM public.ottoq_sim_runs r
--           WHERE r.status = 'running' AND r.depot_id = COALESCE(...)
--           ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1),
--         NOW());
--     END IF;
--
-- At a teardown the value written IS the run's final sim clock, so for every vehicle
-- that last changed state during the final tick, NEW equals OLD, the guard fires, and
-- the fallback runs. The fallback's sim branch then cannot help, because BOTH teardown
-- routes flip the run's status BEFORE release_depot touches a vehicle:
--
--   route A, stopped arm -- ottoq_sim_stop_and_reset, in its own words:
--     "once mark_stopped flips the status, the lookup path can no longer find it"
--   route B, natural completion -- ottoq_sim_advance_tick, in its own words (0103):
--     "advance_tick_world writes status='completed' mid-function"
--
-- status <> 'running' -> no row -> COALESCE falls to NOW(). A wall clock, inside a
-- column ottoq.ottoq_world_fingerprint hashes in its vehicles section.
--
-- WHY IT MATTERS ONLY AT 48 TICKS, which is also why 0255 looked like enough. Route A
-- runs at line 102 of ottoq_determinism_pair, AFTER the arm's atoms are captured, so
-- the 6/12/24-tick columns cannot see it (0175 measured grid endst.world stable across
-- three days while the grid depot carried a 13:43 wall stamp). Route B runs INSIDE tick
-- 48, before the atoms. Only busy_day/171717/48t runs twice per round, so it is the one
-- column 0193's inter-pair bar can judge -- and the one that keeps failing it.
--
-- ---------------------------------------------------------------------------
-- THE FIX, AND WHY THE MECHANISM IS ALREADY IN THE TREE
-- ---------------------------------------------------------------------------
--
-- Both teardown routes already pin the run in a transaction-local GUC one line before
-- they call release_depot:
--
--     PERFORM set_config('ottoq.sim_run_id', p_sim_run_id::text, true);
--
-- 0092 added that for precisely this defect class -- a teardown whose own writes can no
-- longer find the run they are tearing down, because the status has moved. Five
-- routines set it today. The trigger is the one teardown reader that never consults it.
--
-- So: a SECOND COALESCE branch, status-independent, reading the GUC. It is inserted
-- AFTER the existing running-run branch, so no path that resolves today changes at all;
-- the new branch can only fire where the old code was already falling through to a wall
-- clock. Two narrowings, both deliberate:
--
--   * `r.depot_id = COALESCE(NEW.current_depot_id, NEW.home_depot_id)` is repeated on
--     the new branch. A GUC naming a run on another depot must not stamp this vehicle.
--   * `r.run_by <> 'production_live'` excludes production. Measured: all 8
--     production_live runs carry a non-NULL sim_clock_current tracking the real clock,
--     and ottoq_production_start/ottoq_production_stop are two of the five GUC setters,
--     so without this predicate the branch WOULD fire in production and replace NOW()
--     with a near-now value. That is probably more correct and definitely untested
--     here, so it stays out: production keeps NOW(), byte-for-byte as before. 0255's
--     rule, inverted -- it proved production unreachable; this proves it excluded.
--
--   * the GUC is parsed defensively. current_setting(..., true) returns NULL when
--     unset, and a malformed value would raise a cast error INSIDE A TRIGGER on every
--     vehicle state change -- so the cast happens only behind a 36-char uuid shape
--     test, and anything else yields NULL and falls through to NOW(). A trigger on the
--     decide path must never be able to abort a tick.
--
-- WHY NOT STOP HASHING THE COLUMN. Same answer as 0255, which is the same answer as
-- 0137's, and it has not changed: a vehicle's last transition time is genuinely
-- start-relevant world state, the wall-clock write is wrong independently of what
-- hashes it, and the fingerprint catching it is the fingerprint doing its job.
--
-- ---------------------------------------------------------------------------
-- WHY THIS IS SUFFICIENT AND NOT ANOTHER PARTIAL FIX -- THE ONE THING THAT COULD
-- HAVE MADE IT PARTIAL, MEASURED
-- ---------------------------------------------------------------------------
--
-- 0255 supplies COALESCE(v_sim_clock, now()), where v_sim_clock is read from the run
-- row. If the natural-completion route left that column NULL -- and route B is entered
-- precisely when `w.out_sim_clock_after IS NULL` -- then 0255 would be falling back to
-- now() on its own, before the trigger ever got involved, and this migration would fix
-- only half of the path. Measured on the four most recent 48-tick cert runs (two pairs,
-- 2026-09-12 05:48 and 06:20):
--
--   sim_clock_start    2026-09-01 02:00:00+00
--   sim_clock_current  2026-09-02 02:00:00+00   <- NOT NULL, and exactly 02:00 + 48*30min
--   sim_clock_end      2026-09-02 02:00:00+00
--
-- So the run row keeps its clock through the completion, 0255's branch does resolve on
-- route B, and the ONLY thing replacing its value is the trigger. After this migration
-- all 116 flagship vehicles should hold the single value 2026-09-02 02:00:00+00 after a
-- 48-tick run -- one value, from one expression, in the sim domain. That is the check
-- to run first, and db/checks/0176 §6.1 is the query.
--
-- WHY NOT CHANGE release_depot INSTEAD. It cannot win. Whatever value it supplies, the
-- guard compares it to OLD and takes the column away whenever they match. The only
-- place the equal-value case can be handled is the guard itself.
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
SELECT '0256_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'log_vehicle_state_change';

-- ---------------------------------------------------------------------------
-- 2. The change, by anchored substitution. One anchor, asserted to occur exactly
--    once before it is used, and the body md5 pinned so a hotfix since I read it
--    raises instead of being silently overwritten.
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE
  d     text;
  nd    text;
  a1    text;
  v_src text;
BEGIN
  a1 := E'          LIMIT 1),\n        NOW())' || chr(59);

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='log_vehicle_state_change';
  IF md5(v_src) <> '64d128c6550424329b5e0a2e5d4fbff1' THEN
    RAISE EXCEPTION 'GUARD FAILED: log_vehicle_state_change body is % (% chars), expected '
                    '64d128c6550424329b5e0a2e5d4fbff1 at 3089. Someone changed it since '
                    'I read it; the anchor below is against the wrong source.',
                    md5(v_src), length(v_src);
  END IF;

  d := pg_get_functiondef('public.log_vehicle_state_change()'::regprocedure);
  IF md5(d) <> '1b88f383405ea52d1deedea6b83fd666' THEN
    RAISE EXCEPTION 'GUARD FAILED: functiondef md5 is % (% chars), expected '
                    '1b88f383405ea52d1deedea6b83fd666 at 3269', md5(d), length(d);
  END IF;

  IF (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 THEN
    RAISE EXCEPTION 'ANCHOR 1 occurs % time(s), expected 1', (length(d)-length(replace(d,a1,'')))/length(a1);
  END IF;

  nd := replace(d, a1,
        E'          LIMIT 1),\n'
     || E'        /* 0256: THE SECOND BRANCH. The branch above asks for a RUNNING run, and at a\n'
     || E'           teardown there is none -- ottoq_sim_stop_and_reset flips the status via\n'
     || E'           mark_stopped, and ottoq_sim_advance_tick_world writes status=''completed''\n'
     || E'           mid-function (0103), both BEFORE ottoq_sim_release_depot touches a vehicle. So\n'
     || E'           the equal-value case the 0061 guard exists to catch fell through to NOW() at\n'
     || E'           every teardown, putting a WALL clock into a column ottoq_world_fingerprint\n'
     || E'           hashes -- 20 of 116 flagship vehicles, measured in db/checks/0176, in the same\n'
     || E'           statement whose other 96 rows took 0255''s sim clock. Both teardown routes pin\n'
     || E'           the run in this GUC one line before they call release_depot (0092, added for\n'
     || E'           this exact class of blindness); this branch reads it, status-independent.\n'
     || E'           Same depot predicate as above: a GUC naming another depot''s run must not stamp\n'
     || E'           this vehicle. run_by excludes production, which keeps NOW() unchanged -- all 8\n'
     || E'           production_live runs carry a real-clock sim_clock_current and production_start\n'
     || E'           /_stop are themselves GUC setters, so the branch would otherwise change\n'
     || E'           production behaviour that nothing here can test. The uuid shape test is not\n'
     || E'           decoration: a bad cast inside this trigger would abort a tick. */\n'
     || E'        (SELECT r.sim_clock_current FROM public.ottoq_sim_runs r\n'
     || E'          WHERE r.sim_run_id = (CASE WHEN COALESCE(current_setting(''ottoq.sim_run_id'', true), '''')\n'
     || E'                                          ~ ''^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$''\n'
     || E'                                     THEN current_setting(''ottoq.sim_run_id'', true)::uuid END)\n'
     || E'            AND r.depot_id = COALESCE(NEW.current_depot_id, NEW.home_depot_id)\n'
     || E'            AND COALESCE(r.run_by, '''') <> ''production_live''),\n'
     || E'        NOW())' || chr(59));

  EXECUTE nd;
END
$mig$;

-- ---------------------------------------------------------------------------
-- 3. Classify, in the SAME migration so it cannot be forgotten.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
('0256_the_trigger_restamps_what_the_teardown_fixed', true,
 'Adds a GUC-based sim-clock branch to log_vehicle_state_change''s equal-value fallback, so a '
 'teardown stamp stays in the sim domain after the run status has already moved. END-STATE VALUES '
 'CHANGE on any column whose run reaches the scenario sim-clock end -- busy_day/171717/48t at tick '
 '48 -- because 0255''s sim clock now survives the trigger instead of being overwritten with now(). '
 'Completes 0255, which fixed the write but could not stop a BEFORE trigger from replacing it. '
 'Probe db/checks/0176: 96 rows sim, 20 rows wall, one UPDATE, one expression. Production keeps '
 'NOW() by an explicit run_by <> production_live predicate.')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. Assertions.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_src text; v_pos_run int; v_pos_guc int; v_clock timestamptz; v_run uuid;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='log_vehicle_state_change';

  -- A1. The new branch exists.
  IF v_src !~ 'ottoq\.sim_run_id' THEN
    RAISE EXCEPTION 'A1 FAILED: the GUC branch is not in the body';
  END IF;

  -- A2. The existing running-run branch survives AND still comes FIRST, so no path
  --     that resolved before this migration resolves differently after it.
  v_pos_run := position('''running''' in v_src);
  v_pos_guc := position('ottoq.sim_run_id' in v_src);
  IF v_pos_run = 0 OR v_pos_guc = 0 OR v_pos_run > v_pos_guc THEN
    RAISE EXCEPTION 'A2 FAILED: running-run branch at %, GUC branch at % -- order wrong or a branch missing',
      v_pos_run, v_pos_guc;
  END IF;

  -- A3. NOW() is still the last resort. Removing it would make the column NULL-able
  --     in production, which is a different defect, not a fix.
  IF v_src !~ 'NOW\(\)\)' THEN
    RAISE EXCEPTION 'A3 FAILED: the NOW() fallback is gone';
  END IF;

  -- A4. Production is excluded explicitly, not by luck.
  IF v_src !~ 'production_live' THEN
    RAISE EXCEPTION 'A4 FAILED: the production exclusion predicate is missing';
  END IF;

  -- A5. Exactly one assignment to the column. A second one would mean the
  --     substitution duplicated the block instead of extending it.
  IF (SELECT count(*) FROM regexp_matches(v_src, 'NEW\.last_state_change = COALESCE\(', 'g')) <> 1 THEN
    RAISE EXCEPTION 'A5 FAILED: % assignment sites, expected 1',
      (SELECT count(*) FROM regexp_matches(v_src, 'NEW\.last_state_change = COALESCE\(', 'g'));
  END IF;

  -- A6. The trigger is still attached, still BEFORE UPDATE, still enabled.
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
     WHERE c.relname='vehicles' AND t.tgname='trg_vehicle_state_change'
       AND NOT t.tgisinternal AND t.tgenabled='O' AND (t.tgtype & 2)=2 AND (t.tgtype & 16)>0
  ) THEN
    RAISE EXCEPTION 'A6 FAILED: trg_vehicle_state_change is not an enabled BEFORE UPDATE trigger any more';
  END IF;

  -- A7. THE BEHAVIOURAL PROOF, without writing to a vehicle. Evaluate the new branch's
  --     own expression against a COMPLETED cert run: the whole point is that it
  --     resolves for a run whose status has already moved, which the old branch cannot.
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.run_by='cert_harness' AND r.status <> 'running' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE EXCEPTION 'A7 FAILED: no completed cert run with a clock to test against';
  END IF;
  PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
  SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = (CASE WHEN COALESCE(current_setting('ottoq.sim_run_id', true), '')
                                   ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                              THEN current_setting('ottoq.sim_run_id', true)::uuid END)
     AND COALESCE(r.run_by,'') <> 'production_live';
  IF v_clock IS NULL THEN
    RAISE EXCEPTION 'A7 FAILED: the GUC branch resolved to NULL for completed run %', v_run;
  END IF;
  RAISE NOTICE 'A7 OK: GUC branch resolves a stopped run (% -> %)', v_run, v_clock;

  -- A8. And it yields NOTHING when the GUC is empty -- the production path. If this
  --     resolved, the branch would be stamping sim clocks on real vehicles.
  PERFORM set_config('ottoq.sim_run_id', '', true);
  SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = (CASE WHEN COALESCE(current_setting('ottoq.sim_run_id', true), '')
                                   ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                              THEN current_setting('ottoq.sim_run_id', true)::uuid END);
  IF v_clock IS NOT NULL THEN
    RAISE EXCEPTION 'A8 FAILED: an empty GUC resolved to %', v_clock;
  END IF;

  -- A9. A malformed GUC must yield NULL, not an exception. This is the assertion that
  --     keeps a bad set_config from aborting every vehicle state change in a tick.
  PERFORM set_config('ottoq.sim_run_id', 'not-a-uuid', true);
  BEGIN
    SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r
     WHERE r.sim_run_id = (CASE WHEN COALESCE(current_setting('ottoq.sim_run_id', true), '')
                                     ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                                THEN current_setting('ottoq.sim_run_id', true)::uuid END);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'A9 FAILED: a malformed GUC raised % -- a trigger could abort a tick', SQLERRM;
  END;
  IF v_clock IS NOT NULL THEN
    RAISE EXCEPTION 'A9 FAILED: a malformed GUC resolved to %', v_clock;
  END IF;
  PERFORM set_config('ottoq.sim_run_id', '', true);

  RAISE NOTICE '0256 OK: all assertions passed';
END $$;

-- ---------------------------------------------------------------------------
-- 5. Snapshot after, and report the floor this migration moved.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0256_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'log_vehicle_state_change';

SELECT md5(p.prosrc) AS body_md5_post, length(p.prosrc) AS len_post,
       public.ottoq_cert_recert_floor() AS recert_floor_after
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'log_vehicle_state_change';
