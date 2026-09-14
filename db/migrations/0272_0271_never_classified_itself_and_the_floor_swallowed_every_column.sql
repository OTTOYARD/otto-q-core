-- migration-version: 20260913232252
-- migration-name:    0272_0271_never_classified_itself_and_the_floor_swallowed_every_column
--
-- 0272  0271 NEVER CLASSIFIED ITSELF AND THE FLOOR SWALLOWED EVERY COLUMN
--
-- ---------------------------------------------------------------------------
-- WHAT HAPPENED, AND THAT IT HAS HAPPENED BEFORE
--
-- 0271 applied cleanly at 2026-09-13 23:17:58 UTC. It argued forces_recert =
-- FALSE at length in its header and proved it in A7. It did not write the row
-- that makes that argument mean anything.
--
-- ottoq_cert_recert_floor() reads supabase_migrations.schema_migrations LEFT
-- JOIN ottoq_cert_lineage and takes COALESCE(l.forces_recert, TRUE). No
-- lineage row is not "unknown", it is "forces recert". So the floor jumped
-- from 2026-09-12 16:50:23.319089+00 to 2026-09-13 23:17:58+00 and every
-- certification column's streak restarted -- for a migration that adds a
-- provenance column no hash reads.
--
-- This is the SECOND time. 0268 exists because 0267 did the same thing, and
-- its note says "bookkeeping only". Twice is not a slip, it is a missing
-- guard, so this migration does two things rather than one:
--
--   1. writes the two lineage rows (0271's and its own), which restores the
--      floor; and
--   2. is committed together with a repo-side hygiene assertion --
--      tests/test_migration_hygiene.py::test_recent_migrations_classify
--      themselves -- that refuses any migration file numbered 0255 or higher
--      whose body never mentions ottoq_cert_lineage. 0267 and 0271 are the
--      two allowlisted exceptions, each named with the bookkeeping migration
--      that repaired it. A guard in CI is the half a database migration
--      cannot provide: it fires while the file is being written, not after
--      the floor has already moved.
--
-- Touches no engine object. forces_recert = FALSE for the same reason 0268's
-- was: it writes classification rows and nothing else.
-- ---------------------------------------------------------------------------

DO $pre$
DECLARE v_floor timestamptz;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE regexp_replace(name,'^[0-9]{4}[a-z]?_','')
                  = 'the_outbound_command_stream_is_the_only_stream_without_provenance') THEN
    RAISE EXCEPTION '0272 P1: 0271 is already classified -- nothing to repair, refusing to double-apply';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
                  WHERE version = '20260913231758') THEN
    RAISE EXCEPTION '0272 P2: 0271 is not in the migration ledger; classify nothing until it is';
  END IF;
  -- P3: the floor is standing on 0271 right now. If it is not, this migration
  -- is repairing something it has not diagnosed.
  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor <> '2026-09-13 23:17:58+00'::timestamptz THEN
    RAISE EXCEPTION '0272 P3: recert floor is % , expected 0271''s apply stamp 2026-09-13 23:17:58+00', v_floor;
  END IF;
  RAISE NOTICE '0272 pre: floor is standing on 0271 at %', v_floor;
END $pre$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0271_the_outbound_command_stream_is_the_only_stream_without_provenance', false,
   'Adds ottoq_vehicle_commands.data_source (NOT NULL DEFAULT ''twin'', catalog-only, no rewrite), '
   'a BEFORE INSERT/UPDATE OF depot_id trigger that stamps it from depots.feed_mode (0073''s rule as '
   '0228 propagated it), and switches ottoq_fleet_pending_commands from the sim_run_id IS NULL '
   'workaround to that column. FALSE with proof, not assertion: all three h_cmd producers '
   '(ottoq_determinism_pair, ottoq_determinism_pair_replay, ottoq_ab_arm_atoms) build the command '
   'hash from an explicit six-column list -- issued_at|vehicle_id|command_type|stall_id|status|'
   'reason_code -- which 0271 P5 checks positively, so a new column cannot enter the verdict; and '
   '0271 A7 re-verified the pair''s prosrc pin 8a35b8c874fed154cc216140faec0274 unchanged after '
   'the change. The outbound fleet API is not on the decide path and has no engine caller.',
   now()),
  ('0272_0271_never_classified_itself_and_the_floor_swallowed_every_column', false,
   'Bookkeeping only: writes the ottoq_cert_lineage row 0271 omitted, and this one. Touches no '
   'engine object, no function, no table but ottoq_cert_lineage. Ships with the CI guard '
   '(tests/test_migration_hygiene.py::test_recent_migrations_classify_themselves) that makes the '
   'omission impossible to repeat silently -- this is the second occurrence, after 0267/0268.',
   now());

DO $post$
DECLARE v_floor timestamptz; v_n int;
BEGIN
  -- A1: both rows landed, both FALSE.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage
   WHERE name IN ('0271_the_outbound_command_stream_is_the_only_stream_without_provenance',
                  '0272_0271_never_classified_itself_and_the_floor_swallowed_every_column')
     AND forces_recert = false;
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0272 A1: expected 2 non-forcing lineage rows, found %', v_n;
  END IF;

  -- A2: the floor came back down. This is the assertion that could not have
  -- passed before the INSERT above, and the whole point of the migration.
  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor <> '2026-09-12 16:50:23.319089+00'::timestamptz THEN
    RAISE EXCEPTION '0272 A2: recert floor is % after classification, expected the pre-0271 floor '
                    '2026-09-12 16:50:23.319089+00', v_floor;
  END IF;

  -- A3: and 0272 itself did not raise it. Its own row is FALSE, and it has no
  -- schema_migrations version yet at the moment this runs, so the only way it
  -- could move the floor is through the classified_at branch -- which reads
  -- only forcing rows. Assert the branch directly rather than trusting that.
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE forces_recert AND classified_at > '2026-09-12 16:50:23.319089+00'::timestamptz) THEN
    RAISE EXCEPTION '0272 A3: a forcing lineage row is dated after the restored floor';
  END IF;

  RAISE NOTICE '0272: floor restored to % ; 0271 and 0272 both classified FALSE', v_floor;
END $post$;

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- Applied 2026-09-13 23:22:52 UTC as version 20260913232252 (6:22 PM CT).
--
-- Dry-run byte for byte inside BEGIN ... ROLLBACK first: P1-P3 and A1-A3
-- passed and the floor came back to 2026-09-12 16:50:23.319089+00.
--
-- LIVE VERIFICATION AFTER APPLY:
--
--   ottoq_cert_recert_floor()  ->  2026-09-12 16:50:23.319089+00
--                                  (was 2026-09-13 23:17:58+00, standing on 0271)
--   ottoq_cert_lineage rows for 0270 / 0271 / 0272  ->  3, all forces_recert = false
--
-- 0272's own schema_migrations row is dated after the restored floor and does
-- not raise it, because its lineage row says FALSE -- which is the whole
-- mechanism this migration exists to demonstrate working.
--
-- The CI guard shipped in the same commit was proven two-sided before that
-- commit: with 0271 removed from CLASSIFY_EXEMPT the test fails naming exactly
-- 0271_the_outbound_command_stream_is_the_only_stream_without_provenance.sql;
-- restored, it passes. An allowlist entry for a file that no longer exists
-- fails a second test, so the exemption list cannot rot into a hiding place.
-- ---------------------------------------------------------------------------
