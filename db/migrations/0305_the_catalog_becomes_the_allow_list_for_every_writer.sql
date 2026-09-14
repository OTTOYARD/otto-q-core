-- migration-version: 20260914125444
-- migration-name:    0305_the_catalog_becomes_the_allow_list_for_every_writer
--
-- 0305  THE CATALOG BECOMES THE ALLOW-LIST FOR EVERY WRITER, NOT JUST THE SETTER
--
-- G62 part two. One constraint:
--
--   ALTER TABLE ottoq_policy_params ADD FOREIGN KEY (param_key)
--     REFERENCES ottoq_policy_param_catalog(param_key)
--
-- ---------------------------------------------------------------------------
-- WHY THIS IS THE POINT OF THE LAST TWENTY FILES
--
-- ottoq_policy_set refuses any key the catalog does not hold. That gate is
-- real, and it protects exactly one door. MEASURED 2026-09-14, EIGHT other
-- in-database functions INSERT into ottoq_policy_params directly, and roughly
-- forty more `updated_by` identities exist with no corresponding database
-- function at all -- edge functions, proposer_bridge, scenario_loader,
-- ottoq_prime, UIs. Every one of them walks past the gate.
--
-- A foreign key is the only mechanism that gates a table rather than a
-- function. After this, "the catalog is the allow-list" is true of the
-- DATABASE, not of one code path, and it stays true for writers that do not
-- exist yet.
--
-- This is what bounds the agent layer. A tuning agent that can only write keys
-- the catalog admits, only within bounds the catalog clamps, has a worst case
-- fixed BY CONSTRUCTION rather than by review -- and 0302 already showed why
-- that matters: ottoq_cil_tick carried its own undocumented floor
-- (GREATEST(0.15, ...) on energy_demand_factor_peak) while the catalog floors
-- the same dial at 0.25, and until 0302 the undocumented one was the one in
-- the path.
--
-- ---------------------------------------------------------------------------
-- WHY IT IS POSSIBLE ONLY NOW
--
-- This constraint has been the obvious move for weeks and could not be made.
-- It was blocked by six live rows across four uncatalogued keys --
-- contention_wait_cap_ticks (x2, depot), timer_backstop_ticks (x2, depot),
-- l2_overflow_penalty (global), metres_per_plan_unit (global). 0303 catalogued
-- the last of those and 0304 the other three. MEASURED NOW: 0 of 2,779 live
-- rows reference a key the catalog does not hold (P0 re-executes it).
--
-- Completing the dial catalogue was not done in order to unblock this. It
-- unblocked it anyway, and that is the larger result of task #117.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS CHANGES FOR EACH EXISTING WRITER, measured rather than assumed
--
-- FIVE write LITERAL keys, so they are statically checkable. Across all five
-- the complete literal set is six keys -- cuopt_propose_enabled,
-- cuopt_first_refusal_max_defers, orchestrator_agent_enabled, proposer_seat,
-- energy_demand_factor_peak, energy_demand_factor_expensive -- and P3 asserts
-- every one is catalogued:
--   public.ottoq_ab_pair, public.ottoq_cert_arm_start,
--   public.ottoq_determinism_pair, public.ottoq_determinism_pair_replay,
--   public.ottoq_mpc_energy_lookahead
-- Nothing changes for them. NOTE this set includes THE CERTIFICATION ITSELF:
-- ottoq_determinism_pair and ottoq_cert_arm_start write cuopt_propose_enabled
-- to quiesce the proposer, and a pair that could not write it would not run.
--
-- ONE copies rather than composes. twin.ottoq_grid_fixture_create does
--   INSERT INTO ottoq_policy_params (...) SELECT 'depot', v_depot, p.param_key
--     ... FROM ottoq_policy_params p WHERE p.scope_type='depot' AND ...
-- so every key it writes is already a key in the table and therefore already
-- satisfies the FK. Safe by construction, and P4 pins the SELECT so it stays
-- that way.
--
-- ONE is the gated one. public.ottoq_policy_set.
--
-- ONE IS THE GENUINE RISK, and it is named rather than waved at.
-- public.ottoq_mpc_lookahead writes
--   FOR k, val IN SELECT * FROM jsonb_each_text(v_params) LOOP
--     INSERT INTO ottoq_policy_params(...) VALUES ('run',p_sim_run_id,k,...)
-- where v_params comes from the caller's p_plans. The key is a VARIABLE; no
-- static check can bound it. Under this FK, a plan naming an uncatalogued key
-- RAISES instead of silently writing a dial nothing reads.
--
-- THAT IS THE INTENDED BEHAVIOUR -- a silent write of an unknown dial is worse
-- than a loud refusal -- and it is still a behaviour change, so it is measured
-- rather than asserted. ottoq_mpc_lookahead has exactly ONE caller in the
-- database, public.ottoq_cil_tick, and ottoq_cil_tick:
--   * has no in-database caller of its own,
--   * has no cron schedule,
--   * has written 0 rows with updated_by='cil', recorded 0 adoptions, and
--     emitted 0 ottoq.cil_decision events -- it has never run.
-- Its only reachable caller is an edge function (ottoq-ottocommand), invoked
-- by an operator. So this FK cannot reach a certification pair, and P5
-- executes all of that rather than restating it.
--
-- ---------------------------------------------------------------------------
-- ON DELETE RESTRICT, ON UPDATE CASCADE, and why those two
--
-- RESTRICT on delete: a catalog row that is in force somewhere must not be
-- removable, because deleting it would leave a live value whose bounds nobody
-- can look up -- silently, which is this build's most expensive failure mode.
-- MEASURED: no database function deletes from ottoq_policy_param_catalog
-- (P6), so RESTRICT cannot break an existing path; it only forecloses a future
-- one.
--
-- CASCADE on update: renaming a catalog key should carry its live values with
-- it rather than orphan them. No function updates param_key today either, so
-- this is likewise a forward-looking choice.
--
-- ---------------------------------------------------------------------------
-- EXPECTED EFFECT, PREDICTED BEFORE APPLYING
--   constraints on ottoq_policy_params        3 -> 4  (the FK is new)
--   rows in ottoq_policy_params               2,779, all surviving validation
--   an INSERT of a catalogued key             still succeeds      (A3)
--   an INSERT of an uncatalogued key          now raises 23503    (A2)
--   ottoq_policy_set end to end               unchanged           (A4)
--   DELETE of an in-force catalog row         now raises 23503    (A5)
--   recert floor                              UNMOVED
--
-- forces_recert = FALSE, and this one is argued more carefully than the
-- catalog files because a constraint is not a comment. The claim is NOT "a
-- constraint cannot change behaviour" -- it can, and here it deliberately
-- does. The claim is narrower and is what P0/P3/P4/P5 measure: no live row
-- violates it, every writer reachable from a tick or a certification writes
-- only catalogued keys, and the single writer whose key is not statically
-- checkable is reachable only from a function that has never run and is not
-- scheduled. A pair run before and after this file sees the same writes
-- succeed.
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0305 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0305 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0305 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0305 P-: nothing in flight';
END $inflight$;

-- P0. NO LIVE ROW VIOLATES THE CONSTRAINT. Without this the ALTER fails
-- anyway, but it fails with a row-level message that names one row; this names
-- every offending key at once and refuses before anything is locked.
DO $p0$
DECLARE v_bad text; v_rows int;
BEGIN
  SELECT count(*) INTO v_rows FROM public.ottoq_policy_params;
  IF v_rows = 0 THEN
    RAISE EXCEPTION '0305 P0: ottoq_policy_params is empty; the FK would validate '
                    'vacuously and A2 would prove nothing about real data';
  END IF;
  SELECT string_agg(DISTINCT pp.param_key, ', ' ORDER BY pp.param_key) INTO v_bad
    FROM public.ottoq_policy_params pp
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog c
                      WHERE c.param_key = pp.param_key);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0305 P0: uncatalogued key(s) still in force (%). Catalogue them '
                    'first -- do NOT delete the rows to make the constraint fit.', v_bad;
  END IF;
  RAISE NOTICE '0305 P0: % live rows, all referencing a catalogued key', v_rows;
END $p0$;

-- P1. THE CONSTRAINT DOES NOT ALREADY EXIST, and the FK target is a real key.
DO $p1$
DECLARE v_n int; v_pk int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE conrelid = 'public.ottoq_policy_params'::regclass AND contype = 'f';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0305 P1: ottoq_policy_params already has % foreign key(s); '
                    're-read before adding another', v_n;
  END IF;
  SELECT count(*) INTO v_pk FROM pg_constraint
   WHERE conrelid = 'public.ottoq_policy_param_catalog'::regclass
     AND contype = 'p'
     AND pg_get_constraintdef(oid) = 'PRIMARY KEY (param_key)';
  IF v_pk <> 1 THEN
    RAISE EXCEPTION '0305 P1: ottoq_policy_param_catalog has no PRIMARY KEY (param_key); '
                    'a foreign key cannot reference it';
  END IF;
  RAISE NOTICE '0305 P1: no existing FK; catalog PK on param_key is present';
END $p1$;

-- P2. THE CHILD COLUMN IS NOT NULL, so the FK cannot be dodged with a NULL key.
DO $p2$
DECLARE v_nullable text;
BEGIN
  SELECT is_nullable INTO v_nullable FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_policy_params'
     AND column_name='param_key';
  IF v_nullable IS DISTINCT FROM 'NO' THEN
    RAISE EXCEPTION '0305 P2: ottoq_policy_params.param_key is nullable (%); a NULL key '
                    'would satisfy the FK and bypass the allow-list', v_nullable;
  END IF;
  RAISE NOTICE '0305 P2: param_key is NOT NULL';
END $p2$;

-- P3. EVERY LITERAL KEY THE FIVE STATIC WRITERS EMIT IS CATALOGUED. This set
-- includes the two keys the CERTIFICATION writes to quiesce the proposer, so a
-- failure here means the FK would stop a pair from running.
DO $p3$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(k, ', ' ORDER BY k) INTO v_bad
    FROM unnest(ARRAY['cuopt_propose_enabled','cuopt_first_refusal_max_defers',
                      'orchestrator_agent_enabled','proposer_seat',
                      'energy_demand_factor_peak','energy_demand_factor_expensive']) AS k
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog c WHERE c.param_key = k);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0305 P3: a literal key written by the cert/AB/MPC writers is '
                    'uncatalogued (%). Under the FK those writers would RAISE -- '
                    'including the certification.', v_bad;
  END IF;
  RAISE NOTICE '0305 P3: all six literal keys catalogued, certification quiesce included';
END $p3$;

-- P4. THE FIXTURE COPIES RATHER THAN COMPOSES. Its safety is structural, so
-- the structure is pinned: if it ever starts naming keys instead of selecting
-- them from the table, this fails and the argument is re-made.
DO $p4$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_grid_fixture_create';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0305 P4: twin.ottoq_grid_fixture_create does not exist';
  END IF;
  IF position('SELECT ''depot'', v_depot, p.param_key, p.param_value, ''grid_fixture:''||p_slug' in v_src) = 0
     OR position('FROM public.ottoq_policy_params p WHERE p.scope_type = ''depot''' in v_src) = 0 THEN
    RAISE EXCEPTION '0305 P4: the fixture no longer copies its param keys out of '
                    'ottoq_policy_params; its FK safety was structural and must be re-argued';
  END IF;
  RAISE NOTICE '0305 P4: fixture copies keys from existing rows; safe by construction';
END $p4$;

-- P5. THE ONE VARIABLE-KEY WRITER CANNOT REACH A CERTIFICATION. Four separate
-- facts, each executed: the variable key is really there; its only caller is
-- ottoq_cil_tick; ottoq_cil_tick has no in-database caller and no cron job;
-- and it has never run.
DO $p5$
DECLARE v_src text; v_callers text; v_jobs int; v_rows int; v_adopt int; v_evt int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_mpc_lookahead';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0305 P5: public.ottoq_mpc_lookahead does not exist';
  END IF;
  IF position('VALUES (''run'',p_sim_run_id,k,val::numeric,''mpc'')' in v_src) = 0 THEN
    RAISE EXCEPTION '0305 P5: ottoq_mpc_lookahead no longer writes a variable key; '
                    'the risk analysis in this header is stale, re-read it';
  END IF;

  SELECT string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY n.nspname||'.'||p.proname)
    INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.proname <> 'ottoq_mpc_lookahead'
     AND p.prosrc ~ 'ottoq_mpc_lookahead';
  IF v_callers IS DISTINCT FROM 'public.ottoq_cil_tick' THEN
    RAISE EXCEPTION '0305 P5: ottoq_mpc_lookahead''s callers are now [%], not just '
                    'ottoq_cil_tick. A new caller may sit inside a tick path, which '
                    'is exactly what this file argued could not happen.', COALESCE(v_callers,'none');
  END IF;

  SELECT count(*) INTO v_callers FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.proname <> 'ottoq_cil_tick' AND p.prosrc ~ 'ottoq_cil_tick';
  IF v_callers::int > 0 THEN
    RAISE EXCEPTION '0305 P5: ottoq_cil_tick now has % in-database caller(s); it was '
                    'unreachable when this file was written', v_callers;
  END IF;

  SELECT count(*) INTO v_jobs FROM cron.job WHERE command ~ 'ottoq_cil_tick';
  IF v_jobs > 0 THEN
    RAISE EXCEPTION '0305 P5: ottoq_cil_tick is now scheduled (% job(s)); the '
                    '"has never run" argument no longer holds', v_jobs;
  END IF;

  SELECT count(*) INTO v_rows FROM public.ottoq_policy_params WHERE updated_by = 'cil';
  SELECT count(*) INTO v_adopt FROM public.ottoq_cil_adoptions;
  SELECT count(*) INTO v_evt FROM public.ottoq_events WHERE event_type = 'ottoq.cil_decision';
  IF v_rows > 0 OR v_adopt > 0 OR v_evt > 0 THEN
    RAISE EXCEPTION '0305 P5: the CIL loop HAS run (% param rows, % adoptions, % events). '
                    'That is not a reason to refuse the FK -- it is a reason to re-measure '
                    'which keys it writes before adding one.', v_rows, v_adopt, v_evt;
  END IF;
  RAISE NOTICE '0305 P5: the variable-key writer is reachable only from a function that '
               'has never run, is unscheduled, and has no in-database caller';
END $p5$;

-- P6. NOTHING DELETES OR RENAMES CATALOG KEYS, so RESTRICT/CASCADE cannot
-- break a path that exists today.
DO $p6$
DECLARE v_del text;
BEGIN
  SELECT string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY n.nspname||'.'||p.proname)
    INTO v_del
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.prosrc ~* 'delete\s+from\s+(public\.)?ottoq_policy_param_catalog';
  IF v_del IS NOT NULL THEN
    RAISE EXCEPTION '0305 P6: function(s) delete catalog rows (%); ON DELETE RESTRICT '
                    'would start failing there', v_del;
  END IF;
  RAISE NOTICE '0305 P6: no function deletes from the catalog';
END $p6$;

-- ===========================================================================
-- THE CONSTRAINT
-- ===========================================================================

ALTER TABLE public.ottoq_policy_params
  ADD CONSTRAINT ottoq_policy_params_param_key_fkey
  FOREIGN KEY (param_key)
  REFERENCES public.ottoq_policy_param_catalog (param_key)
  ON UPDATE CASCADE
  ON DELETE RESTRICT;

COMMENT ON CONSTRAINT ottoq_policy_params_param_key_fkey ON public.ottoq_policy_params IS
  '0305 (G62): the catalog is the allow-list for EVERY writer, not just '
  'ottoq_policy_set. Eight in-database functions and ~40 external updated_by '
  'identities INSERT here directly; a foreign key gates the table rather than a '
  'function, so it covers writers that do not exist yet. ON DELETE RESTRICT '
  'because removing a catalog row that is in force would leave a live value whose '
  'bounds nobody can look up. Unblocked by 0303+0304, which catalogued the last '
  'four uncatalogued keys.';

-- ===========================================================================
-- A1. THE CONSTRAINT IS THERE, AND IS THE ONE THIS FILE DESCRIBES.
DO $a1$
DECLARE v_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
   WHERE conrelid = 'public.ottoq_policy_params'::regclass
     AND conname = 'ottoq_policy_params_param_key_fkey';
  IF v_def IS NULL THEN
    RAISE EXCEPTION 'A1 FAILED: the foreign key was not created';
  END IF;
  IF v_def <> 'FOREIGN KEY (param_key) REFERENCES ottoq_policy_param_catalog(param_key) '
              'ON UPDATE CASCADE ON DELETE RESTRICT' THEN
    RAISE EXCEPTION 'A1 FAILED: the constraint is % -- not what this file specified', v_def;
  END IF;
  RAISE NOTICE 'A1 OK: %', v_def;
END $a1$;

-- A2. AN UNCATALOGUED KEY IS NOW REFUSED AT THE TABLE. This is the whole file,
-- and it is proved by a real INSERT that bypasses ottoq_policy_set entirely --
-- the same shape the eight bypassing writers use -- not by a call to the setter.
DO $a2$
DECLARE v_scope uuid := '00000000-0000-0000-0000-0000030500cc'::uuid; v_state text;
BEGIN
  BEGIN
    BEGIN
      INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
      VALUES ('run', v_scope, 'no_such_dial_0305', 1, '0305_proof');
      RAISE EXCEPTION 'A2 FAILED: a direct INSERT of an uncatalogued key SUCCEEDED; '
                      'the foreign key is not gating the table';
    EXCEPTION
      WHEN foreign_key_violation THEN
        RAISE NOTICE 'A2 OK: direct INSERT of an uncatalogued key raised 23503';
    END;
    RAISE EXCEPTION 'A2_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A2_OK_ROLLBACK' THEN RAISE; END IF;
  END;
END $a2$;

-- A3. A CATALOGUED KEY STILL WRITES. The FK must gate the unknown, not the
-- known -- and this uses the certification's own quiesce key, so a failure
-- here is a failure of the cert path.
DO $a3$
DECLARE v_scope uuid := '00000000-0000-0000-0000-0000030500cc'::uuid; v_n int;
BEGIN
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_scope, 'cuopt_propose_enabled', 0, '0305_proof');
    SELECT count(*) INTO v_n FROM public.ottoq_policy_params
     WHERE scope_id = v_scope AND param_key = 'cuopt_propose_enabled';
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'A3 FAILED: the certification quiesce key did not write (% rows)', v_n;
    END IF;
    RAISE EXCEPTION 'A3_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A3_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A3 OK: the certification quiesce key still writes through a direct INSERT';
END $a3$;

-- A4. ottoq_policy_set IS UNCHANGED END TO END, including its own refusal path
-- -- which must still answer unknown_param rather than raising 23503, because
-- callers read that JSON.
DO $a4$
DECLARE v_scope uuid := '00000000-0000-0000-0000-0000030500cc'::uuid; v_r jsonb;
BEGIN
  BEGIN
    v_r := public.ottoq_policy_set('run', v_scope, 'staging_hold_default_min', 77, '0305_proof');
    IF NOT COALESCE((v_r->>'ok')::boolean, false)
       OR COALESCE((v_r->>'applied')::numeric, -1) <> 77 THEN
      RAISE EXCEPTION 'A4 FAILED: a normal set stopped working: %', v_r;
    END IF;
    v_r := public.ottoq_policy_set('run', v_scope, 'no_such_dial_0305', 1, '0305_proof');
    IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'unknown_param' THEN
      RAISE EXCEPTION 'A4 FAILED: the setter must still REFUSE an unknown key with JSON, '
                      'not let it reach the constraint: %', v_r;
    END IF;
    RAISE EXCEPTION 'A4_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A4_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A4 OK: setter writes catalogued keys and still refuses unknown ones in JSON';
END $a4$;

-- A5. AN IN-FORCE CATALOG ROW CANNOT BE DELETED. The other half of the
-- constraint, and the half that protects a live value from losing its bounds.
DO $a5$
DECLARE v_key text;
BEGIN
  SELECT pp.param_key INTO v_key FROM public.ottoq_policy_params pp LIMIT 1;
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'A5 FAILED: no live param row to test RESTRICT with';
  END IF;
  BEGIN
    BEGIN
      DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = v_key;
      RAISE EXCEPTION 'A5 FAILED: deleted catalog row % while it was in force', v_key;
    EXCEPTION
      WHEN foreign_key_violation THEN
        RAISE NOTICE 'A5 OK: deleting in-force catalog row % raised 23503', v_key;
    END;
    RAISE EXCEPTION 'A5_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A5_OK_ROLLBACK' THEN RAISE; END IF;
  END;
END $a5$;

-- A6. NO RESIDUE, AND NO ROW LOST. The ALTER validates 2,779 existing rows; if
-- the count moved, something other than validation happened.
DO $a6$
DECLARE v_n int; v_rows int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE scope_id = '00000000-0000-0000-0000-0000030500cc'::uuid
      OR updated_by = '0305_proof';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A6 FAILED: % probe row(s) survived', v_n;
  END IF;
  SELECT count(*) INTO v_rows FROM public.ottoq_policy_params;
  IF v_rows <> 2779 THEN
    RAISE EXCEPTION 'A6 FAILED: ottoq_policy_params holds % rows, P0 counted 2779; '
                    'adding a constraint must not change the data', v_rows;
  END IF;
  RAISE NOTICE 'A6 OK: no probe rows, and all 2779 rows survived validation';
END $a6$;

-- ===========================================================================
-- LINEAGE, written here in the migration (0296-0300 argued forces_recert=false
-- in their headers and never wrote the row; ottoq_cert_recert_floor reads
-- COALESCE(forces_recert, TRUE), so a missing row says the opposite).
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0305_the_catalog_becomes_the_allow_list_for_every_writer', false,
        'Adds a FOREIGN KEY on ottoq_policy_params.param_key and changes no function. '
        'A constraint CAN change behaviour and this one deliberately does -- an '
        'uncatalogued key now raises instead of writing silently. forces_recert=false '
        'rests on four measured facts, not on the constraint being inert: (1) P0, no '
        'live row violates it; (2) P3, all six literal keys the cert/AB/MPC writers '
        'emit are catalogued, including the certification quiesce keys; (3) P4, the '
        'fixture copies keys out of the table so it satisfies the FK structurally; '
        '(4) P5, the one writer whose key is not statically checkable '
        '(ottoq_mpc_lookahead) is reachable only from ottoq_cil_tick, which has no '
        'in-database caller, no cron schedule, and has never run. A pair run before '
        'and after sees the same writes succeed.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- A7. THE FLOOR DID NOT MOVE.
DO $a7$
DECLARE v_floor timestamptz;
BEGIN
  SELECT public.ottoq_cert_recert_floor() INTO v_floor;
  IF v_floor <> '2026-09-12 16:50:23.319089+00'::timestamptz THEN
    RAISE EXCEPTION 'A7 FAILED: recert floor moved to % -- this file classified itself '
                    'forces_recert=false and must not unstreak any column', v_floor;
  END IF;
  RAISE NOTICE 'A7 OK: recert floor unmoved at %', v_floor;
END $a7$;
