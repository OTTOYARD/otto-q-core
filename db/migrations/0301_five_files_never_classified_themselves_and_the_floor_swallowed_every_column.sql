-- migration-version: 20260914105943
-- migration-name:    0301_five_files_never_classified_themselves_and_the_floor_swallowed_every_column
--
-- 0301  FIVE FILES NEVER CLASSIFIED THEMSELVES, AND THE FLOOR SWALLOWED EVERY
--       CERTIFICATION COLUMN
--
-- Bookkeeping repair, the third of its kind: 0268 repaired 0267, 0272 repaired
-- 0271, and this one repairs FIVE AT ONCE -- 0296, 0297, 0298, 0299 and 0300.
-- The test that catches it, tests/test_migration_hygiene.py::
-- test_recent_migrations_classify_themselves, says in its own docstring that
-- twice "is once more than an argument in a header can be trusted to prevent."
-- I then did it five times in a row, and each of those five headers argued at
-- length that the file changes nothing hashed.
--
-- ---------------------------------------------------------------------------
-- THE MECHANISM, AND WHY AN ARGUMENT IN A HEADER IS WORTH NOTHING HERE
--
-- public.ottoq_cert_recert_floor() is
--
--     GREATEST(
--       (SELECT max(<apply timestamp>) FROM schema_migrations m
--          LEFT JOIN ottoq_cert_lineage l ON <name, prefix-stripped both sides>
--         WHERE COALESCE(l.forces_recert, true) ...),
--       (SELECT max(l.classified_at) FROM ottoq_cert_lineage l WHERE l.forces_recert))
--
-- COALESCE(l.forces_recert, TRUE). A MISSING ROW IS NOT "UNKNOWN" -- IT IS
-- "FORCES RECERT". So a migration that says forces_recert=false in prose and
-- never writes the row has, in the only place the engine reads, said the exact
-- opposite of what it meant.
--
-- MEASURED, before this file:
--
--   ottoq_cert_recert_floor()                     2026-09-14 10:51:35+00
--
-- which is 0300's own apply time. The floor had been dragged forward to my most
-- recent migration, so EVERY certification column's streak was restarted -- by
-- five files that insert catalog rows and replace two reporting views with no
-- consumer.
--
-- PREDICTED after this file, computed against the live catalog before writing it:
--
--   ottoq_cert_recert_floor()                     2026-09-12 16:50:23.319089+00
--
-- set by 0256_the_trigger_restamps_what_the_teardown_fixed, which is a
-- genuinely forcing migration and was the floor before I touched anything. Both
-- branches of the GREATEST land on 0256; branch 2 carries the microseconds and
-- therefore wins.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS DID AND DID NOT COST, stated exactly
--
-- DID NOT: no certification pair has run since 0296 was applied at 10:17:44
-- UTC. Measured -- 0 rows in ottoq_sim_runs with run_by='cert_harness' at or
-- after that moment, and the last pair started 2026-09-13 16:36:00 UTC. So no
-- streak was actually consumed against the wrong floor. The damage was latent
-- and is being caught before a round, not after one.
--
-- DID: for roughly forty minutes the engine's own answer to "how far back does
-- a certification streak reach" was wrong by about forty-two hours, and
-- anything that had asked it in that window would have been told, correctly
-- per the data and incorrectly per the facts, that every column was
-- unstreaked. That is the same class as G28 -- an instrument answering a
-- slightly different question than the one being asked -- and it is the third
-- instrument defect in this session alone.
--
-- ---------------------------------------------------------------------------
-- WHY BOOKKEEPING AND NOT AN EDIT TO THE FIVE FILES
--
-- All five are applied. Editing them now would make the committed file differ
-- from the SQL that actually ran -- and for each of the five that SQL was
-- proven byte-identical to the file by digest against
-- supabase_migrations.schema_migrations. APPLYING.md's whole premise is that
-- the file is the record of what ran. So the repair goes in a new file, and the
-- five are listed in CLASSIFY_EXEMPT naming THIS migration, exactly as the
-- test's own failure message instructs and exactly as 0268 and 0272 did.
--
-- This file classifies ITSELF as well, or it would be the sixth omission.
--
-- forces_recert = FALSE for all six. The five insert catalog rows and replace
-- two consumer-less reporting views; this one writes to ottoq_cert_lineage,
-- which is read by the recert floor -- a reproducibility instrument, not a
-- decide or tick path. 0268 and 0272 are both false for the same reason.
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0301 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0301 P-: a determinism pair is running right now -- repairing '
                    'the floor underneath a pair in flight is how a verdict gets '
                    'judged against two different floors';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0301 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0301 P-: nothing in flight';
END $inflight$;

-- P0. THE FIVE ARE APPLIED AND UNCLASSIFIED. Both halves matter: classifying a
-- migration that was never applied would put a row in the lineage for something
-- the ledger has never seen.
DO $p0$
DECLARE
  v_applied int; v_classified int;
  v_names text[] := ARRAY[
    '0296_the_gap_view_cannot_see_five_of_its_own_call_sites',
    '0297_seven_gates_whose_range_is_the_comparison_itself',
    '0298_four_hours_three_probabilities_and_a_dial_that_is_half_wired',
    '0299_a_dial_that_defaults_for_a_checked_column_inherits_the_check',
    '0300_three_dials_whose_floor_is_on_the_other_side_of_the_assignment'];
BEGIN
  SELECT count(*) INTO v_applied FROM supabase_migrations.schema_migrations
   WHERE name = ANY (v_names);
  IF v_applied <> 5 THEN
    RAISE EXCEPTION '0301 P0: only % of the five are in the migration ledger; this '
                    'file would classify something that never ran', v_applied;
  END IF;
  SELECT count(*) INTO v_classified FROM public.ottoq_cert_lineage
   WHERE name = ANY (v_names);
  IF v_classified <> 0 THEN
    RAISE EXCEPTION '0301 P0: % of the five already carry a lineage row; re-read '
                    'before overwriting someone else''s classification', v_classified;
  END IF;
  RAISE NOTICE '0301 P0: five applied, none classified -- the repair is needed';
END $p0$;

-- P1. THE HARM IS REAL, NOT ARGUED. The floor must currently BE the wrong
-- value, or this file is repairing something that is not broken.
DO $p1$
DECLARE v_floor timestamptz;
BEGIN
  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor IS DISTINCT FROM '2026-09-14 10:51:35+00'::timestamptz THEN
    RAISE EXCEPTION '0301 P1: the recert floor is %, not the 2026-09-14 10:51:35+00 '
                    '(0300''s apply time) this file measured. Something else has '
                    'moved it; re-measure before repairing.', v_floor;
  END IF;
  RAISE NOTICE '0301 P1: floor is at 0300''s apply time -- every column unstreaked';
END $p1$;

-- P2. NO PAIR RAN AGAINST THE WRONG FLOOR. If one did, the claim in this
-- file's header that nothing was consumed is false and must be rewritten
-- before it is committed as the record.
DO $p2$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM public.ottoq_sim_runs
   WHERE run_by = 'cert_harness' AND started_at >= '2026-09-14 10:17:44+00'::timestamptz;
  IF v_pairs <> 0 THEN
    RAISE EXCEPTION '0301 P2: % certification run(s) started after 0296 was applied, '
                    'so a streak WAS judged against the wrong floor and this file''s '
                    'header understates the cost. Rewrite it.', v_pairs;
  END IF;
  RAISE NOTICE '0301 P2: no certification pair ran in the window -- latent, not consumed';
END $p2$;

-- ===========================================================================
-- THE CHANGE -- six rows: the five that were missed, and this file itself
-- ===========================================================================

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0296_the_gap_view_cannot_see_five_of_its_own_call_sites', false,
   'Replaces public.ottoq_policy_catalog_gap and adds public.ottoq_policy_read_site_census. '
   'Reporting views only: P1 asserted at apply time that no function body mentions the gap '
   'view and no view depends on it, and that ottoq_policy_get does not read '
   'ottoq_policy_param_catalog. Nothing on any decide or tick path can observe either view. '
   'forces_recert=false.', now()),

  ('0297_seven_gates_whose_range_is_the_comparison_itself', false,
   'Ten rows into ottoq_policy_param_catalog. ottoq_policy_get never reads that table -- it '
   'resolves run -> depot -> global -> caller default -- so a catalog row cannot change any '
   'value in force. All ten keys had zero live rows in ottoq_policy_params. forces_recert=false.',
   now()),

  ('0298_four_hours_three_probabilities_and_a_dial_that_is_half_wired', false,
   'Eight rows into ottoq_policy_param_catalog. Same argument as 0297. Three of the eight had '
   'live GLOBAL rows and A3 read all three back afterwards with an impossible caller default '
   'of -1 to prove no value in force had moved. Also RECORDS G64 (db/checks/0227) in the '
   'overnight_recall_end_hour description without changing any code. forces_recert=false.',
   now()),

  ('0299_a_dial_that_defaults_for_a_checked_column_inherits_the_check', false,
   'Four rows into ottoq_policy_param_catalog, one of them bounded by copying '
   'vehicles_target_soc_check rather than by reading code. Catalog inserts only; the two keys '
   'with live rows were read back unchanged. forces_recert=false.', now()),

  ('0300_three_dials_whose_floor_is_on_the_other_side_of_the_assignment', false,
   'Three rows into ottoq_policy_param_catalog, none of the three with any live row, so no '
   'value in force could move. Catalog inserts only. forces_recert=false.', now()),

  ('0301_five_files_never_classified_themselves_and_the_floor_swallowed_every_column', false,
   'This bookkeeping repair. Writes six rows into ottoq_cert_lineage and nothing else. That '
   'table is read by public.ottoq_cert_recert_floor, a reproducibility instrument, not by any '
   'decide or tick path. Pulls the floor back from 2026-09-14 10:51:35+00 (0300''s apply time, '
   'where five missing rows had dragged it) to 2026-09-12 16:50:23.319089+00, set by 0256, '
   'which is where it belonged. Third repair of this class after 0268 and 0272, both also '
   'forces_recert=false. forces_recert=false.', now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ===========================================================================
-- ASSERTIONS
-- ===========================================================================

-- A1. All six rows exist and every one of them says false.
DO $a1$
DECLARE v_n int; v_forcing text;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage
   WHERE name IN ('0296_the_gap_view_cannot_see_five_of_its_own_call_sites',
                  '0297_seven_gates_whose_range_is_the_comparison_itself',
                  '0298_four_hours_three_probabilities_and_a_dial_that_is_half_wired',
                  '0299_a_dial_that_defaults_for_a_checked_column_inherits_the_check',
                  '0300_three_dials_whose_floor_is_on_the_other_side_of_the_assignment',
                  '0301_five_files_never_classified_themselves_and_the_floor_swallowed_every_column');
  IF v_n <> 6 THEN
    RAISE EXCEPTION 'A1 FAILED: % of the six lineage rows exist', v_n;
  END IF;
  SELECT string_agg(name, ', ' ORDER BY name) INTO v_forcing
    FROM public.ottoq_cert_lineage
   WHERE name LIKE '029[6-9]%' OR name LIKE '030[01]%';
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE (name LIKE '029[6-9]%' OR name LIKE '030[01]%') AND forces_recert) THEN
    RAISE EXCEPTION 'A1 FAILED: one of these still forces recert: %', v_forcing;
  END IF;
  RAISE NOTICE 'A1 OK: six rows, all forces_recert=false';
END $a1$;

-- A2. THE FLOOR MOVED BACK TO WHERE IT BELONGED, and to a value this file
-- predicted before it was written -- not merely "somewhere earlier".
DO $a2$
DECLARE v_floor timestamptz; v_owner text;
BEGIN
  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor IS DISTINCT FROM '2026-09-12 16:50:23.319089+00'::timestamptz THEN
    RAISE EXCEPTION 'A2 FAILED: the floor is now %, predicted 2026-09-12 16:50:23.319089+00. '
                    'A floor that lands somewhere other than predicted means something '
                    'ELSE is unclassified too.', v_floor;
  END IF;
  SELECT l.name INTO v_owner FROM public.ottoq_cert_lineage l
   WHERE l.forces_recert AND l.classified_at = v_floor;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'A2 FAILED: no forcing lineage row owns the new floor %; it is '
                    'being set by an UNCLASSIFIED migration instead, which is the '
                    'same defect one file older', v_floor;
  END IF;
  RAISE NOTICE 'A2 OK: floor 2026-09-14 10:51:35+00 -> %, owned by %', v_floor, v_owner;
END $a2$;

-- A3. NOTHING ELSE IS UNCLASSIFIED ABOVE THE FLOOR CONVENTION. The repair is
-- worthless if the next file inherits the same hole, so this counts every
-- migration at or above 0255 whose lineage row is missing. It must be zero.
DO $a3$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(m.name, ', ' ORDER BY m.name) INTO v_missing
    FROM supabase_migrations.schema_migrations m
    LEFT JOIN public.ottoq_cert_lineage l
           ON regexp_replace(l.name, '^[0-9]{4}[a-z]?_', '')
            = regexp_replace(m.name, '^[0-9]{4}[a-z]?_', '')
   WHERE l.name IS NULL
     AND m.name ~ '^[0-9]{4}_'
     AND substring(m.name from 1 for 4)::int >= 255;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'A3 FAILED: still unclassified at or above 0255: %', v_missing;
  END IF;
  RAISE NOTICE 'A3 OK: every applied migration from 0255 up carries a lineage row';
END $a3$;

-- ===========================================================================
-- APPLIED 20260914105943. All four P blocks and A1-A3 passed, and the SQL that
-- ran md5s to 28adeedd6a4ab9c9ef7369fb2e3c2d78 -- identical to this file with
-- its trailing newline stripped, measured before the apply.
--
--   ottoq_cert_recert_floor()   2026-09-14 10:51:35+00
--                            -> 2026-09-12 16:50:23.319089+00
--   owned by                    0256_the_trigger_restamps_what_the_teardown_fixed
--   the six lineage rows        all present, all forces_recert=false
--
-- CORRECTION, AND IT IS THE SAME CLASS THIS FILE IS ABOUT.
--
-- A1's SECOND check could not fail. It reads
--
--     WHERE (name LIKE '029[6-9]%' OR name LIKE '030[01]%') AND forces_recert
--
-- and SQL LIKE has no character classes -- only % and _. Those patterns match
-- a LITERAL '029[6-9]' prefix, so they select zero rows and the EXISTS is
-- always false. Measured after the apply: that predicate returns 0 rows, while
-- the six rows plainly exist under an explicit IN list. A1's FIRST check (the
-- IN list, v_n <> 6) is real and did the work.
--
-- THE PROPERTY IS STILL PROVEN, by A2 rather than by the assertion written for
-- it: if any of the six carried forces_recert=true, the floor's second branch
-- (max classified_at WHERE forces_recert) would have been this file's own
-- now() -- 2026-09-14 10:59:43 -- and A2 asserts the floor is
-- 2026-09-12 16:50:23.319089+00 exactly. A2 passed, so none of the six forces
-- recert. Verified again directly afterwards, six rows, all false.
--
-- Recorded rather than edited, because the executable half is the SQL that
-- ran. The lesson is the one this whole file exists for: an argument -- or an
-- assertion -- that the engine cannot actually evaluate is worth nothing, and
-- writing three P blocks that can fail does not excuse one A block that cannot.
-- ===========================================================================
