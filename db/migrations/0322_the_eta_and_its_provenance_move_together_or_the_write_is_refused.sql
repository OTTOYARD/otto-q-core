-- migration-version: PENDING
-- migration-name:    0322_the_eta_and_its_provenance_move_together_or_the_write_is_refused
--
-- 0322  THE INVARIANT BECOMES PHYSICAL
--
-- 0320 and 0321 fixed the four writers of ottoq_vehicle_dispatches
-- .return_eta_minutes so each states its own provenance. This file makes it so
-- a FIFTH writer cannot forget.
--
-- The rule, in one sentence: A WRITE THAT PUTS A FORECAST IN
-- return_eta_minutes MUST ALSO MOVE eta_refreshed_at AND NAME AN eta_source.
--
-- ---------------------------------------------------------------------------
-- WHY A TRIGGER AND NOT A CONVENTION
--
-- db/checks/0240 §B measured the convention failing: 21 of 61 dispatch rows
-- labelled 'policy_constant:return_eta_minutes' while holding 17 distinct
-- values between 1.6 and 48.8 minutes. Every writer was individually correct.
-- The pair of columns, read together, was wrong -- and nothing in the database
-- could notice.
--
-- 0318 already tried the other approach. It is named "the engine stopped
-- guessing and the label kept saying guess", it fixed labelling inside ONE
-- writer, and the defect survived it by one migration because there were four.
-- A fifth careful site is a fifth thing that can fall out of step with a sixth.
--
-- This is the repo's own pattern, not a new idea: ottoq_stall_bookings makes
-- double-booking impossible with an EXCLUDE constraint rather than asking
-- callers to be careful, and 0302/0305 made the dial catalogue the allow-list
-- for every writer rather than for one function. CLAUDE.md 2.3 states the
-- principle as "assignment plus verification, always."
--
-- ---------------------------------------------------------------------------
-- WHAT THE RULE DELIBERATELY DOES NOT COVER, each measured rather than assumed
--
--  i. CLEARING the ETA. The guard fires only when NEW.return_eta_minutes IS NOT
--     NULL. A teardown or reset that nulls the column is not writing a
--     forecast and must not be refused. Measured: no function today assigns
--     `return_eta_minutes = NULL` (§P3), so this exemption costs nothing today and
--     buys safety against a purge path added later.
--
-- ii. THE 72,164 HISTORICAL ROWS that hold an ETA with no eta_refreshed_at.
--     They are pre-0318 and their provenance is genuinely unknown. The trigger
--     is not retroactive -- it constrains writes, not rows -- and they are NOT
--     backfilled. Backfilling would mean inventing a provenance, which is the
--     0311 lesson said the other way round: a dead column that says what it is
--     beats a populated one that says something untrue.
--
-- iii. DEFECT 3, and this is the interesting one. The delay card stamps
--     eta_refreshed_at/eta_source while moving scheduled_return_at -- an
--     INSTANT -- and never touches return_eta_minutes, a DURATION. This trigger
--     does NOT fire on that write, because the ETA did not change. So defect 3
--     survives 0322 intact, and survives it VISIBLY: after this file, a stamp
--     that moves without the ETA moving is the ONLY remaining way the two
--     columns can disagree, which makes it findable with one query instead of
--     by reading four functions. Named in 0321's header, named again here, and
--     left for its own file rather than smuggled into a trigger that would
--     then be enforcing two different rules.
--
-- ---------------------------------------------------------------------------
-- ORDERING: 0320 -> 0321 -> 0322, and this file LAST for a concrete reason.
-- A trigger installed before 0321 would refuse twin.ottoq_sim_prime_deployment
-- at t=0 of the very next run -- measured in §P2: it is the ONE inserter that
-- names return_eta_minutes, and today it does not stamp. P1/P2 refuse to apply
-- this file until 0321 has fixed that.
--
-- forces_recert: TRUE. A trigger that raises changes what the engine can do,
-- and the honest position is that a guard which has never fired is a guard
-- that has never been tested. Round 44 runs the pairs; if a pair aborts with
-- ottoq_assert_eta_provenance in the message, that is the trigger working and a
-- writer this file did not find.
-- ===========================================================================

DO $pre$
DECLARE v_bad text; v_hist bigint; v_nullers int;
BEGIN
  -- P1. 0321 MUST BE IN PLACE. Checked by behaviour (does prime_deployment
  --     stamp?) rather than by looking for a migration name, because the name
  --     proves a row in a ledger and the behaviour is what the trigger meets.
  SELECT string_agg(n.nspname||'.'||p.proname, ', ')
    INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc ~* 'INSERT\s+INTO\s+(public\.)?ottoq_vehicle_dispatches'
     AND p.prosrc ~ 'return_eta_minutes'
     AND p.prosrc !~ 'eta_refreshed_at';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0322 P1: % insert(s) a return_eta_minutes without an eta_refreshed_at; '
                    'apply 0321 first or this trigger refuses the next run at t=0', v_bad;
  END IF;

  -- P2. THE SAME FOR UPDATE SITES.
  SELECT string_agg(n.nspname||'.'||p.proname, ', ')
    INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc ~ 'return_eta_minutes\s*=' 
     AND p.prosrc !~ 'eta_refreshed_at'
     AND p.proname <> 'ottoq_return_eta_minutes';   -- reads a DIAL of the same name, writes nothing
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0322 P2: % assign(s) return_eta_minutes without eta_refreshed_at; '
                    'apply 0321 first', v_bad;
  END IF;

  -- P3. THE "CLEARING IS EXEMPT" CARVE-OUT IS CURRENTLY UNUSED, recorded as a
  --     measurement so the exemption is known to be precautionary rather than
  --     load-bearing. If this ever becomes non-zero the exemption is doing real
  --     work and deserves its own note.
  SELECT count(*) INTO v_nullers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc ~* 'return_eta_minutes\s*=\s*NULL';
  RAISE NOTICE '0322 P3: % function(s) currently clear the ETA (exemption is precautionary at 0)', v_nullers;

  -- P4. THE HISTORICAL ROWS, counted so the "not retroactive" claim has a number.
  SELECT count(*) INTO v_hist FROM public.ottoq_vehicle_dispatches
   WHERE return_eta_minutes IS NOT NULL AND eta_refreshed_at IS NULL;
  RAISE NOTICE '0322 P4: % rows hold an ETA with no stamp; NOT backfilled, NOT refused', v_hist;
END $pre$;

CREATE OR REPLACE FUNCTION public.ottoq_assert_eta_provenance()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.eta_refreshed_at IS NULL OR NEW.eta_source IS NULL THEN
      RAISE EXCEPTION
        'ottoq_assert_eta_provenance: dispatch % inserts return_eta_minutes=% with '
        'eta_refreshed_at=% and eta_source=%. A forecast must carry a stamp and a source '
        '(0322; the defect measured in db/checks/0240 was 21 of 61 rows whose label '
        'described an earlier write).',
        NEW.dispatch_id, NEW.return_eta_minutes, NEW.eta_refreshed_at, COALESCE(NEW.eta_source,'NULL');
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE. The stamp must actually MOVE: carrying the previous write's
  -- eta_refreshed_at forward is exactly how the label goes stale.
  IF NEW.eta_refreshed_at IS NOT DISTINCT FROM OLD.eta_refreshed_at THEN
    RAISE EXCEPTION
      'ottoq_assert_eta_provenance: dispatch % changes return_eta_minutes % -> % without '
      'moving eta_refreshed_at (still %). The value and its provenance move together (0322).',
      NEW.dispatch_id, COALESCE(OLD.return_eta_minutes::text,'NULL'),
      NEW.return_eta_minutes, COALESCE(OLD.eta_refreshed_at::text,'NULL');
  END IF;
  IF NEW.eta_source IS NULL THEN
    RAISE EXCEPTION
      'ottoq_assert_eta_provenance: dispatch % writes return_eta_minutes=% with a NULL '
      'eta_source. Name the origin (0322).', NEW.dispatch_id, NEW.return_eta_minutes;
  END IF;
  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_eta_provenance() IS
'Refuses any write that puts a value in ottoq_vehicle_dispatches.return_eta_minutes without '
'also moving eta_refreshed_at and naming an eta_source. Makes physical the invariant that four '
'separately-correct writers could not keep by convention -- db/checks/0240 measured 21 of 61 '
'rows labelled policy_constant while holding 17 distinct values. Clearing the ETA to NULL is '
'exempt (a teardown is not a forecast). Does NOT fire when the stamp moves without the ETA '
'moving, which is how the delay card writes scheduled_return_at -- that is defect 3, left '
'deliberately visible rather than folded into a trigger enforcing two rules. 0322.';

-- CREATE OR REPLACE TRIGGER: PostgreSQL 14+, and this database is 17.6. Used
-- instead of DROP ... IF EXISTS + CREATE because scripts/APPLYING.md forbids
-- DROP, and rightly: a dropped trigger between two statements is a window in
-- which the invariant does not hold.
CREATE OR REPLACE TRIGGER trg_dispatch_eta_provenance_ins
  BEFORE INSERT ON public.ottoq_vehicle_dispatches
  FOR EACH ROW
  WHEN (NEW.return_eta_minutes IS NOT NULL)
  EXECUTE FUNCTION public.ottoq_assert_eta_provenance();

CREATE OR REPLACE TRIGGER trg_dispatch_eta_provenance_upd
  BEFORE UPDATE ON public.ottoq_vehicle_dispatches
  FOR EACH ROW
  -- NOT NULL: clearing is exempt (§ii). IS DISTINCT FROM: an UPDATE that
  -- rewrites the same value is not a new forecast and need not re-stamp.
  WHEN (NEW.return_eta_minutes IS NOT NULL
        AND NEW.return_eta_minutes IS DISTINCT FROM OLD.return_eta_minutes)
  EXECUTE FUNCTION public.ottoq_assert_eta_provenance();

DO $post$
DECLARE v_n int; v_victim uuid; v_fired boolean; v_allowed boolean;
BEGIN
  -- A1. BOTH TRIGGERS EXIST AND ARE ENABLED. A disabled trigger is a comment.
  SELECT count(*) INTO v_n FROM pg_trigger
   WHERE tgrelid = 'public.ottoq_vehicle_dispatches'::regclass
     AND tgname IN ('trg_dispatch_eta_provenance_ins','trg_dispatch_eta_provenance_upd')
     AND tgenabled = 'O';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0322 A1: expected 2 enabled provenance triggers, found %', v_n;
  END IF;

  -- A2/A3 need a row that already carries an ETA. Measured at draft time:
  -- 72,164 such rows. Asserted rather than assumed, because a self-test that
  -- silently updates ZERO rows would report the guard as broken in A2 and as
  -- working in A3, and both readings would be wrong.
  SELECT dispatch_id INTO v_victim FROM public.ottoq_vehicle_dispatches
   WHERE return_eta_minutes IS NOT NULL ORDER BY dispatch_id LIMIT 1;
  IF v_victim IS NULL THEN
    RAISE EXCEPTION '0322 A2: no dispatch row carries an ETA, so the guard cannot be exercised; '
                    'refusing to install a trigger this migration has not seen fire';
  END IF;

  -- A2. THE GUARD ACTUALLY FIRES. A guard that has never fired has never been
  --     tested -- 0161 convicted exactly that (an atom enforced without being
  --     measured first). The plpgsql EXCEPTION block is an implicit savepoint,
  --     so when the guard raises, this UPDATE is rolled back and nothing
  --     persists.
  BEGIN
    UPDATE public.ottoq_vehicle_dispatches
       SET return_eta_minutes = return_eta_minutes + 1
     WHERE dispatch_id = v_victim;
    v_fired := false;   -- no exception: the guard did NOT fire, and the row IS now dirty
  EXCEPTION WHEN raise_exception THEN
    v_fired := (SQLERRM ~ 'ottoq_assert_eta_provenance');
  END;
  IF NOT v_fired THEN
    -- Raising here aborts the whole migration, which also discards the dirty row.
    RAISE EXCEPTION '0322 A2: the guard did not refuse an unstamped ETA write; it is installed '
                    'but not effective';
  END IF;
  RAISE NOTICE '0322 A2: the guard refused an unstamped write, as designed';

  -- A3. AND IT DOES NOT REFUSE A LEGITIMATE ONE -- the more important half,
  --     since a guard that refuses EVERYTHING would also pass A2.
  --
  --     The write must be undone, and it is undone by DESIGN rather than by a
  --     compensating UPDATE: the block raises a sentinel after the write, which
  --     rolls the implicit savepoint back. An earlier draft instead reverted by
  --     hand with `eta_refreshed_at = COALESCE(eta_refreshed_at, now()) + 1s`
  --     and then subtracting a second -- which would have left a WALL CLOCK
  --     value in a run-scoped row whose stamp had been NULL, in a migration
  --     whose entire subject is that this column must mean something. A literal
  --     sentinel timestamp is used for the same reason: obviously synthetic,
  --     and never persisted.
  BEGIN
    UPDATE public.ottoq_vehicle_dispatches
       SET return_eta_minutes = return_eta_minutes + 1,
           eta_refreshed_at   = TIMESTAMPTZ '2000-01-01 00:00:00+00',
           eta_source         = 'migration_selftest:0322'
     WHERE dispatch_id = v_victim;
    RAISE EXCEPTION 'ottoq_0322_selftest_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'ottoq_0322_selftest_rollback' THEN
      v_allowed := true;     -- the write succeeded, and this savepoint rollback undid it
    ELSE
      RAISE EXCEPTION '0322 A3: the guard refused a correctly stamped write: %', SQLERRM;
    END IF;
  END;
  IF NOT COALESCE(v_allowed, false) THEN
    RAISE EXCEPTION '0322 A3: the correctly stamped write did not complete';
  END IF;
  RAISE NOTICE '0322 A3: a correctly stamped write was allowed, and rolled back';

  -- A4. NOTHING WAS LEFT BEHIND. The sentinel must not exist in data anyone
  --     later reads as provenance.
  IF EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches
              WHERE eta_source = 'migration_selftest:0322') THEN
    RAISE EXCEPTION '0322 A4: the self-test sentinel survived; the savepoint did not roll back';
  END IF;
  RAISE NOTICE '0322 A4: no self-test residue';
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0322_the_eta_and_its_provenance_move_together_or_the_write_is_refused', true,
   'Two BEFORE triggers on ottoq_vehicle_dispatches refusing any write that puts a value in '
   'return_eta_minutes without also moving eta_refreshed_at and naming an eta_source. Makes '
   'physical what four separately-correct writers could not keep by convention (db/checks/0240 '
   'SecB). Clearing to NULL is exempt; the 72k historical unstamped rows are neither backfilled '
   'nor refused, since the trigger constrains writes and not rows. Defect 3 (a stamp that moves '
   'without the ETA moving -- the delay card) is deliberately NOT covered, and becomes the only '
   'remaining way the two columns can disagree. A2/A3 prove the guard both refuses a bad write '
   'and permits a good one, inside the migration, and revert their own mutations. '
   'forces_recert TRUE: a guard that has never fired has never been tested.',
   now())
ON CONFLICT (name) DO NOTHING;
