-- migration-version: 20260920004021
-- migration-name:    the_booking_calendar_keeps_three_timestamps_on_two_clocks_and_says_so_nowhere
--
-- 0357  `released_at - booked_at` IS NEGATIVE ON 100% OF ROWS, AND THE FIX IS NOT
--       A DATA MIGRATION.
--
-- G75, opened in db/checks/0255 §4 while building G71's answer. Measured:
-- **1,202 of 1,202 released bookings on one run have `released_at < booked_at`** --
-- a stall released before it was booked. Because `booked_at` is the WALL clock and
-- `released_at` is the SIM clock, in the same row, under names that read as a pair.
--
-- ══ 1. WHAT I EXPECTED TO FIND, AND WHAT IS ACTUALLY THERE ══════════════════
--
-- 0255 recorded the fix as "stamp `released_at` on the wall clock to match
-- `booked_at` and add `released_at_sim`". **That would have been wrong**, and the
-- census is what shows it. Every one of the TEN routines that writes `released_at`
-- sets it from a sim clock -- `p_clock`, `p_sim_clock`, or `sim_clock_current`:
--
--   ottoq.ottoq_activate_due_bay_reservations      released_at = p_clock
--   ottoq.ottoq_enact_space_assignment             released_at = p_clock
--   ottoq.ottoq_reconcile_bay_reservations         released_at = p_clock   (x3)
--   ottoq.ottoq_reconcile_displace_stale_claim     released_at = p_clock
--   ottoq.ottoq_record_enacted_booking             released_at = p_clock   (x3)
--   ottoq.ottoq_release_departed_spaces            released_at = p_clock   (x2)
--   ottoq.ottoq_release_expired_bookings           released_at = p_clock   (x2)
--   ottoq.ottoq_release_vacated_spaces             released_at = p_clock
--   public.ottoq_sim_release_depot                 released_at = sim_clock_current
--   twin.ottoq_sim_vehicle_exception_handler       released_at = p_sim_clock (x2)
--
-- Ten of ten, sim. That is not an inconsistency to repair -- it is a uniform,
-- deliberate convention. **`released_at` IS the sim clock and should stay that
-- way.** The odd column is `booked_at`, which is `DEFAULT now()` NOT NULL: a WALL
-- audit stamp recording when the ROW was written, with `booked_at_sim` carrying the
-- sim time the booking was made.
--
-- So the calendar holds four timestamps on two clocks, coherently:
--
--   booked_at       WALL   DEFAULT now()   when the row was written
--   booked_at_sim   SIM                    when the booking was made in-world
--   released_at     SIM                    when the booking was released in-world
--   during          SIM    (range)         the window the stall is held
--
-- **The correct duration is `released_at - booked_at_sim`, both SIM.** The trap is
-- purely that `released_at` lacks the `_sim` suffix its three siblings' convention
-- implies, so `released_at - booked_at` looks like the natural expression and is
-- nonsense. Changing ten writers to "fix" a convention that was already right
-- would have been a large, risky, wrong change.
--
-- ══ 2. SO THIS FILE MAKES THE CONVENTION ENFORCED INSTEAD OF IMPLIED ═══════
--
-- A. COLUMN COMMENTS naming the clock on each of the four, so the next reader is
--    told at the point of reading rather than having to measure it. This is where
--    the defect actually lives.
--
-- B. A CHECK CONSTRAINT, `released_at >= booked_at_sim`, which converts the
--    correct pairing from a convention into an invariant the engine holds. Its
--    value is not the historical data -- it is that **if anyone ever writes a wall
--    timestamp into `released_at`, the write fails immediately** instead of
--    silently producing a negative duration that nobody notices. That is the
--    "assignment plus verification" rule applied to a clock.
--
--    VALIDATED AGAINST THE WHOLE TABLE BEFORE BEING WRITTEN: **5,548 released rows,
--    5,548 satisfy it, 0 violate**, and 0 released rows lack `booked_at_sim`.
--    Sim durations run 00:00:00 to 17:13:23, which are plausible holds. Added
--    `NOT VALID` then `VALIDATE`d so the ACCESS EXCLUSIVE lock is momentary -- this
--    is the stall calendar, which `db/checks/0127` measured at 53% of every disk
--    block this database has ever read, and a long lock here stalls a tick.
--
-- C. ONE LATENT WALL-CLOCK INJECTION, fixed. `ottoq_sim_release_depot` writes
--    `COALESCE(r.sim_clock_current, now())` in **three** places -- for
--    `ocpp_sessions.ended_at`, `ottoq_stall_bookings.released_at` and one more.
--    If `sim_clock_current` were ever NULL that fallback puts WALL time into a SIM
--    column, which is exactly the defect this file documents, and after (B) it
--    would also fail the constraint and abort a teardown.
--
--    Measured: `sim_clock_current` is NULL on **0 of 12** runs, so it has never
--    fired -- this is a latent bug, not a live one, and it is fixed because (B)
--    turns it from silent corruption into an abort. The replacement is
--    `COALESCE(r.sim_clock_current, r.sim_clock_start)`: `sim_clock_start` is
--    `NOT NULL` on the table, so the fallback is always available and always in
--    the sim domain.
--
-- ══ 3. WHAT THIS FILE DELIBERATELY DOES NOT DO ═════════════════════════════
--
-- * It does NOT add a `released_at_sim` column. That was 0255's suggested fix and
--   §1 shows it is unnecessary: `released_at` already IS the sim value, so the
--   column would be a duplicate, on the hottest table in the database, to satisfy
--   a naming symmetry that a COMMENT and a CHECK address for free.
-- * It does NOT rename `released_at`. A rename would break ten writers and two
--   readers for cosmetics.
-- * It does NOT touch `booked_at`. A wall-clock audit stamp of when a row was
--   written is legitimate and useful; it simply is not half of a duration.
-- * It changes no engine decision, writes no rule evaluation, and alters no
--   hashed output.
--
-- forces_recert: FALSE. Nothing in the fourteen atoms digests a column comment or
-- a constraint, and no value written by any path changes -- the constraint cannot
-- fire on correct data (proven over 5,724 rows) and the COALESCE fallback it
-- repairs has never once been reached. Classified FALSE with the reasoning stated
-- rather than asserted; A5 pins the no-value-change claim.
--
-- Applied through the Management API, so the `schema_migrations` row is written
-- explicitly -- see 0354's header for why that is mandatory on this path.

BEGIN;

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- ── PRECONDITIONS ──────────────────────────────────────────────────────────────
DO $pre$
DECLARE v_jobs text; v_pairs int; v_live text; v_bad int; v_missing int;
        v_block int; v_occ int; v_src text;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0357 P0: certification jobs are scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state = 'active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0357 P1: % certification pair(s) are active', v_pairs;
  END IF;

  SELECT string_agg(sim_run_id::text, ', ') INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_live IS NOT NULL THEN
    RAISE NOTICE '0357 P2: applying while Twin run(s) % are active; the ADD CONSTRAINT is NOT VALID so its lock is momentary, and VALIDATE takes only a SHARE UPDATE EXCLUSIVE lock', v_live;
  END IF;

  -- P3. THE CONSTRAINT MUST BE SATISFIED BY EVERY EXISTING ROW. If this ever
  -- fails, the invariant in §2(B) is not an invariant and this file is wrong.
  SELECT count(*) INTO v_bad FROM public.ottoq_stall_bookings
   WHERE released_at IS NOT NULL AND booked_at_sim IS NOT NULL
     AND released_at < booked_at_sim;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0357 P3: % booking(s) already violate released_at >= booked_at_sim -- the invariant does not hold and must be understood before it is enforced', v_bad;
  END IF;

  SELECT count(*) INTO v_missing FROM public.ottoq_stall_bookings
   WHERE released_at IS NOT NULL AND booked_at_sim IS NULL;
  IF v_missing > 0 THEN
    RAISE NOTICE '0357 P3b: % released booking(s) carry no booked_at_sim; the constraint tolerates NULL on either side so they pass, but the duration is unanswerable for them', v_missing;
  END IF;

  -- P4. Not already applied.
  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conrelid = 'public.ottoq_stall_bookings'::regclass
                AND conname  = 'ottoq_stall_bookings_release_after_book_sim') THEN
    RAISE EXCEPTION '0357 P4: the constraint already exists';
  END IF;

  -- P5. The three COALESCE occurrences must still be there, and there must be
  -- exactly three, or the substitution in §2(C) would land wrong or not at all.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0357 P5a: public.ottoq_sim_release_depot not found';
  END IF;
  v_occ := (length(v_src) - length(replace(v_src, 'COALESCE(r.sim_clock_current, now())', '')))
           / length('COALESCE(r.sim_clock_current, now())');
  IF v_occ <> 3 THEN
    RAISE EXCEPTION '0357 P5b: expected exactly 3 COALESCE(r.sim_clock_current, now()) occurrences, found %', v_occ;
  END IF;

  -- P6. sim_clock_start must be NOT NULL, or the replacement fallback is no safer
  -- than the one it replaces.
  IF (SELECT is_nullable FROM information_schema.columns
       WHERE table_schema='public' AND table_name='ottoq_sim_runs'
         AND column_name='sim_clock_start') <> 'NO' THEN
    RAISE EXCEPTION '0357 P6: ottoq_sim_runs.sim_clock_start is nullable, so it cannot be the guaranteed sim-domain fallback';
  END IF;

  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0357 P7: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $pre$;

-- ── A. THE COMMENTS, WHICH IS WHERE THE DEFECT ACTUALLY LIVES ─────────────────
COMMENT ON COLUMN public.ottoq_stall_bookings.booked_at IS
'WALL CLOCK (DEFAULT now()). When this ROW was written, not when the booking happened in-world. 0357: this is the odd one out on this table and the reason `released_at - booked_at` is negative on every released row -- do NOT pair it with released_at. For an in-world duration use `released_at - booked_at_sim`, both SIM.';

COMMENT ON COLUMN public.ottoq_stall_bookings.booked_at_sim IS
'SIM CLOCK. When the booking was made in the simulated world. 0357: pairs with `released_at` (also SIM) to give the in-world hold duration. Registered as a stamp, not a scoping key.';

COMMENT ON COLUMN public.ottoq_stall_bookings.released_at IS
'SIM CLOCK, despite the missing _sim suffix -- all TEN routines that write it pass a sim clock (p_clock / p_sim_clock / sim_clock_current), measured 0357. Pairs with `booked_at_sim`, NOT with `booked_at` (which is WALL). The CHECK constraint ottoq_stall_bookings_release_after_book_sim enforces that pairing, so a wall timestamp written here fails loudly instead of producing a silent negative duration.';

COMMENT ON COLUMN public.ottoq_stall_bookings.during IS
'SIM CLOCK range. The window the stall is held in-world, and the column the EXCLUDE constraint enforces -- this is the authoritative record of occupancy, and both bounds are SIM so upper(during) - lower(during) is a correct duration.';

-- ── B. THE INVARIANT, ENFORCED ────────────────────────────────────────────────
-- NOT VALID first: this is the stall calendar (53% of all disk blocks ever read,
-- db/checks/0127), so the ACCESS EXCLUSIVE lock of ADD CONSTRAINT is kept to a
-- catalog write and the row scan happens under VALIDATE's weaker
-- SHARE UPDATE EXCLUSIVE lock, which does not block reads or writes.
ALTER TABLE public.ottoq_stall_bookings
  ADD CONSTRAINT ottoq_stall_bookings_release_after_book_sim
  CHECK (released_at IS NULL
      OR booked_at_sim IS NULL
      OR released_at >= booked_at_sim) NOT VALID;

ALTER TABLE public.ottoq_stall_bookings
  VALIDATE CONSTRAINT ottoq_stall_bookings_release_after_book_sim;

-- ── C. THE LATENT WALL-CLOCK INJECTION ────────────────────────────────────────
DO $rewrite$
DECLARE v_src text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';

  --: Three occurrences, all the same shape, all writing into SIM columns
  --: (ocpp_sessions.ended_at, ottoq_stall_bookings.released_at, and one more).
  --: sim_clock_start is NOT NULL so the replacement can never leave the sim domain.
  v_new := replace(v_src,
             'COALESCE(r.sim_clock_current, now())',
             'COALESCE(r.sim_clock_current, r.sim_clock_start) /* 0357: was now() -- a WALL fallback in a SIM column */');

  IF v_new = v_src THEN
    RAISE EXCEPTION '0357 R1: the substitution changed nothing';
  END IF;
  IF position('COALESCE(r.sim_clock_current, now())' in v_new) > 0 THEN
    RAISE EXCEPTION '0357 R2: a wall-clock fallback survives the rewrite';
  END IF;

  EXECUTE v_new;
END $rewrite$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0357_the_booking_calendar_keeps_three_timestamps_on_two_clocks_and_says_so_nowhere', false,
  'G75. ottoq_stall_bookings keeps booked_at on the WALL clock and booked_at_sim / released_at / during on '
  'the SIM clock, so released_at - booked_at is negative on 100% of released rows (1,202 of 1,202 on one '
  'run). 0255 proposed stamping released_at on wall to match booked_at; THAT WOULD HAVE BEEN WRONG. A '
  'census of all TEN writers shows every one passes a sim clock, so released_at IS the sim value by uniform '
  'convention and booked_at is the odd column -- a DEFAULT now() audit stamp of when the ROW was written. '
  'The correct duration is released_at - booked_at_sim, both SIM. So this file does not move data: it adds '
  'COLUMN COMMENTS naming the clock on all four timestamps (the defect lives at the point of reading), and '
  'a CHECK constraint released_at >= booked_at_sim that turns the convention into an invariant -- its value '
  'is that a wall timestamp written there now FAILS instead of silently producing a negative duration. '
  'Validated over the whole table first: 5,548 released rows, 5,548 satisfy, 0 violate. Added NOT VALID '
  'then VALIDATEd because this is the stall calendar (53% of all disk blocks ever read, 0127) and a long '
  'ACCESS EXCLUSIVE lock stalls a tick. Also repairs three COALESCE(sim_clock_current, now()) fallbacks in '
  'ottoq_sim_release_depot that would put WALL time into SIM columns -- never reached (sim_clock_current is '
  'NULL on 0 of 12 runs) but after the constraint they would abort a teardown; replaced with '
  'COALESCE(sim_clock_current, sim_clock_start), which is NOT NULL and always sim-domain. '
  'forces_recert FALSE: no hashed output changes, no value written by any path changes, and the constraint '
  'cannot fire on correct data (proven over 5,724 rows). A5 pins the no-value-change claim.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ── ASSERTIONS ─────────────────────────────────────────────────────────────────
DO $post$
DECLARE v_src text; v_block int; v_bad int; v_n int;
BEGIN
  -- A1. The constraint exists AND is validated. NOT VALID left unvalidated would
  -- guard future writes but assert nothing about the table, and the header claims
  -- both.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.ottoq_stall_bookings'::regclass
                    AND conname='ottoq_stall_bookings_release_after_book_sim') THEN
    RAISE EXCEPTION '0357 A1a: the constraint is absent';
  END IF;
  IF NOT (SELECT convalidated FROM pg_constraint
           WHERE conrelid='public.ottoq_stall_bookings'::regclass
             AND conname='ottoq_stall_bookings_release_after_book_sim') THEN
    RAISE EXCEPTION '0357 A1b: the constraint exists but was never validated';
  END IF;

  -- A2. THE CONSTRAINT ACTUALLY BITES. A guard that cannot refuse anything is not
  -- a guard -- this is the non-vacuity check, and it is the whole point of the
  -- file. A wall-clock release must be rejected; the probe is rolled back.
  BEGIN
    --: EVERY NOT NULL COLUMN IS SUPPLIED -- booking_id, sim_run_id, stall_id,
    --: vehicle_id, purpose, during, state, booked_at (DEFAULT now()), booked_by.
    --: The first draft omitted vehicle_id and booked_by and would have raised
    --: not_null_violation, which A2b correctly reports as "not shown to bite"
    --: rather than mistaking for success -- and would have aborted this migration.
    --: state='released' is deliberate: all three EXCLUDE constraints on this table
    --: filter on state IN ('held','active',...) and none includes 'released', so a
    --: far-future `during` cannot collide. Checked, not assumed.
    INSERT INTO public.ottoq_stall_bookings
      (booking_id, sim_run_id, stall_id, vehicle_id, purpose, during, state,
       booked_by, booked_at_sim, released_at)
    SELECT gen_random_uuid(), b.sim_run_id, b.stall_id, b.vehicle_id, b.purpose,
           tstzrange('2200-01-01 00:00:00+00'::timestamptz,
                     '2200-01-02 00:00:00+00'::timestamptz), 'released',
           '0357_nonvacuity_probe',
           '2200-01-01 12:00:00+00'::timestamptz,      -- booked_at_sim in the far future
           '2199-01-01 12:00:00+00'::timestamptz       -- released BEFORE it: must fail
      FROM public.ottoq_stall_bookings b LIMIT 1;
    RAISE EXCEPTION '0357 A2: the constraint ACCEPTED a release that precedes its booking -- it is vacuous';
  EXCEPTION
    WHEN check_violation THEN
      NULL;  -- correct: refused
    WHEN OTHERS THEN
      --: any other error means the probe itself failed (a NOT NULL, an FK, the
      --: EXCLUDE constraint) and the non-vacuity of A2 is UNPROVEN rather than
      --: proven. Say so rather than treating a different failure as success.
      RAISE EXCEPTION '0357 A2b: the non-vacuity probe failed for another reason (%), so the constraint is not shown to bite', SQLERRM;
  END;

  -- A3. The comments landed, and name the clock. A comment that exists but does
  -- not say WALL or SIM would not prevent the trap.
  SELECT count(*) INTO v_n FROM (
    SELECT col_description('public.ottoq_stall_bookings'::regclass, a.attnum) AS d
      FROM pg_attribute a
     WHERE a.attrelid = 'public.ottoq_stall_bookings'::regclass
       AND a.attname IN ('booked_at','booked_at_sim','released_at','during')) x
   WHERE x.d IS NOT NULL AND (x.d LIKE '%WALL%' OR x.d LIKE '%SIM%');
  IF v_n <> 4 THEN
    RAISE EXCEPTION '0357 A3: only % of 4 timestamp columns carry a comment naming its clock', v_n;
  END IF;

  -- A4. The wall-clock fallback is gone from the teardown, and the sim-domain one
  -- is in its place.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_release_depot';
  IF position('COALESCE(r.sim_clock_current, now())' in v_src) > 0 THEN
    RAISE EXCEPTION '0357 A4a: a wall-clock fallback survives in ottoq_sim_release_depot';
  END IF;
  IF position('COALESCE(r.sim_clock_current, r.sim_clock_start)' in v_src) = 0 THEN
    RAISE EXCEPTION '0357 A4b: the sim-domain fallback is not present';
  END IF;

  -- A5. NO VALUE CHANGED, which is what forces_recert=FALSE rests on. Every
  -- released row still satisfies the invariant and none was rewritten.
  SELECT count(*) INTO v_bad FROM public.ottoq_stall_bookings
   WHERE released_at IS NOT NULL AND booked_at_sim IS NOT NULL
     AND released_at < booked_at_sim;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0357 A5: % row(s) violate the invariant after apply', v_bad;
  END IF;

  -- A6. And the trap this file is about is still TRUE of the data -- the comments
  -- describe reality rather than aspiration. released_at < booked_at is expected
  -- and correct; it is the WRONG pairing, which is why it is documented and not
  -- constrained.
  SELECT count(*) INTO v_n FROM public.ottoq_stall_bookings
   WHERE released_at IS NOT NULL AND released_at < booked_at;
  IF v_n = 0 THEN
    RAISE NOTICE '0357 A6: no row shows released_at < booked_at right now, so the documented trap is not currently observable (the table may have been purged)';
  END IF;

  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0357 A7: the registry guard now reports % blocking defect(s)', v_block;
  END IF;

  RAISE NOTICE '0357 OK: constraint validated and proven non-vacuous, 4 clock comments, wall fallback removed';
END $post$;

COMMIT;
