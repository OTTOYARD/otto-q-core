-- migration-version: 20260914150516
-- migration-name:    0310_two_migrations_argued_forces_recert_false_and_never_wrote_the_row
--
-- 0310  0308 AND 0309 EACH ARGUED forces_recert=false AT LENGTH AND NEITHER
--       WROTE THE ROW THE FLOOR ACTUALLY READS
--
-- THIRD OCCURRENCE. 0268 repaired 0267. 0272 repaired 0271 and shipped the CI
-- guard. 0301 repaired five at once. This one repairs two more -- and unlike
-- 0301's batch, which was caught latent because no pair ran in the window,
-- THIS ONE DID DAMAGE THAT WAS ALREADY VISIBLE.
--
-- ---------------------------------------------------------------------------
-- WHAT HAPPENED, MEASURED
--
-- public.ottoq_cert_recert_floor() reads schema_migrations LEFT JOIN
-- ottoq_cert_lineage and takes COALESCE(l.forces_recert, TRUE). A MISSING ROW
-- IS NOT "UNKNOWN", IT IS "FORCES RECERT". So:
--
--   floor before 0308      2026-09-12 16:50:23.319089+00
--   floor after 0309       2026-09-14 14:45:47+00        (0309's apply stamp)
--   ottoq_cert_lineage rows for 0308/0309                0
--   ottoq_cert_matrix(floor)                             NULL -- EMPTY
--
-- Every certification column was swallowed. Not one pair predates the new
-- floor, so the matrix returns no rows at all.
--
-- AND THE PARTICULAR STING. Earlier the same morning, db/checks/0234 converted
-- 0303-0307's forces_recert=false classifications from claims into
-- measurement: grid_smoke 239001/6t reproduced its canon across twelve atoms
-- at 14:24 UTC, and busy_day 171717/12t across thirteen atoms at 14:37, each
-- compared against hashes READ BEFORE the pair was fired. Both columns went
-- PPPP -> PPPPP. Three minutes after the second one, 0308 applied and wiped
-- the instrument that had just recorded it -- and the reason was not an engine
-- change but two bookkeeping rows I did not write while writing two headers
-- that each argued, correctly, that nothing hashed had changed.
--
-- The argument was right. The row is what the floor reads.
--
-- ---------------------------------------------------------------------------
-- WHY THE GUARD DID NOT STOP IT (it did, just not in time)
--
-- tests/test_migration_hygiene.py::test_recent_migrations_classify_themselves
-- shipped with 0272 precisely for this, and it FIRED -- it is why this is being
-- repaired at all. But it runs in CI, and CI ran after the migrations were
-- applied to the live engine, not before. The guard is a repo-side check on a
-- file; applying is a separate act. For a change-control flow where the file is
-- committed and then applied by hand, "CI will catch it" arrives after the
-- floor has already moved.
--
-- That gap is not closed here, and this header will not pretend it is. The
-- honest statement: the guard makes the omission impossible to MERGE, not
-- impossible to APPLY. Closing it properly means the apply step itself refusing
-- an unclassified migration -- which is G12 ("CI runs the SQL") territory and
-- wants its own change. Recorded so the fourth occurrence has somewhere to
-- start.
--
-- ---------------------------------------------------------------------------
-- forces_recert: FALSE, for the same reason 0268's, 0272's and 0301's were.
-- This migration writes classification rows and nothing else. It touches no
-- function, no engine table, nothing but ottoq_cert_lineage.
-- ===========================================================================

DO $pre$
DECLARE v_floor timestamptz; v_n int; v_cols int;
BEGIN
  -- P1. THE DEFECT IS PRESENT. Repairing something already repaired would mean
  --     this migration has not diagnosed what it is fixing.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage
   WHERE name IN ('0308_the_loop_may_not_tune_a_depot_the_harness_certifies_on',
                  '0309_benchmark_had_everything_except_a_scenario');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0310 P1: % lineage row(s) for 0308/0309 already exist; nothing to repair', v_n;
  END IF;

  -- P2. THE FLOOR IS STANDING ON 0309 RIGHT NOW.
  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor <> '2026-09-14 14:45:47+00'::timestamptz THEN
    RAISE EXCEPTION '0310 P2: recert floor is %, expected 0309''s apply stamp 2026-09-14 14:45:47+00', v_floor;
  END IF;

  -- P3. AND THE MATRIX IS EMPTY BECAUSE OF IT. This is the damage, asserted
  --     rather than described, so A3 below is a real before/after.
  SELECT count(*) INTO v_cols FROM public.ottoq_cert_matrix(v_floor);
  IF v_cols <> 0 THEN
    RAISE EXCEPTION '0310 P3: matrix already returns % column(s); the damage this repairs is not present', v_cols;
  END IF;

  RAISE NOTICE '0310 pre: floor standing on 0309 at %, matrix empty', v_floor;
END $pre$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0308_the_loop_may_not_tune_a_depot_the_harness_certifies_on', false,
   'Adds public.ottoq_cil_tune_refusal(uuid) and a refusal branch at the top of ottoq_cil_tick, so '
   'the self-improvement loop cannot write depot-scoped dials on a depot the harness certifies on. '
   'FALSE with proof, not assertion: the loop HAS NEVER BEEN CALLED -- 0308 P1 asserted 0 rows in '
   'ottoq_cil_adoptions, 0 rows in ottoq_policy_params with updated_by=''cil'', and 0 '
   'ottoq.cil_decision events, and the apply passed. No certified run has executed a line of '
   'ottoq_cil_tick, so no canon can depend on its behaviour. ottoq_policy_get, ottoq_policy_set, '
   'ottoq_decide_tick, ottoq_determinism_pair and the twin are all untouched; A1 re-asserted the '
   'proconfig search_path survived CREATE OR REPLACE. Independently corroborated after the fact: '
   'the busy_day 171717/12t pair fired at 14:36 UTC -- after 0303-0307 and before 0308 -- '
   'reproduced all thirteen canon atoms (db/checks/0234).',
   now()),
  ('0309_benchmark_had_everything_except_a_scenario', false,
   'Inserts five bench_* rows into ottoq_scenarios on depot 22222222 (Benchmark), cloned from the '
   'flagship scenarios of the same names with depot_id as the only changed field. FALSE with proof: '
   '0309 A2 asserted that ottoq_cert_columns references neither the Benchmark depot nor any bench_ '
   'scenario, so no certification column can read any of these rows; A3 asserted the flagship '
   'library is unchanged at its original 7 rows. No function, no engine table, no existing row was '
   'modified. scenario_id is derived md5(...)::uuid rather than minted, so the insert is idempotent '
   'and introduces no fresh random value into a table.',
   now()),
  ('0310_two_migrations_argued_forces_recert_false_and_never_wrote_the_row', false,
   'Bookkeeping only: writes the ottoq_cert_lineage rows 0308 and 0309 omitted, and this one. '
   'Touches no engine object, no function, no table but ottoq_cert_lineage. Third occurrence of '
   'this omission after 0267/0268 and 0271/0272, and the first where the damage was already '
   'visible rather than latent -- the floor had moved to 0309''s apply stamp and '
   'ottoq_cert_matrix returned zero columns. The CI guard from 0272 is what caught it; it fires on '
   'the file, which is after the apply, and that gap is named in 0310''s header rather than '
   'papered over.',
   now());

DO $post$
DECLARE v_floor timestamptz; v_n int; v_cols int; v_green int;
BEGIN
  -- A1. THREE ROWS, ALL NON-FORCING.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage
   WHERE name IN ('0308_the_loop_may_not_tune_a_depot_the_harness_certifies_on',
                  '0309_benchmark_had_everything_except_a_scenario',
                  '0310_two_migrations_argued_forces_recert_false_and_never_wrote_the_row')
     AND forces_recert = false;
  IF v_n <> 3 THEN
    RAISE EXCEPTION '0310 A1: expected 3 non-forcing lineage rows, found %', v_n;
  END IF;

  -- A2. THE FLOOR IS BACK WHERE IT WAS BEFORE 0308.
  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor <> '2026-09-12 16:50:23.319089+00'::timestamptz THEN
    RAISE EXCEPTION '0310 A2: floor is % , expected the pre-0308 value 2026-09-12 16:50:23.319089+00', v_floor;
  END IF;

  -- A3. AND THE COLUMNS ARE BACK. P3 asserted the matrix was EMPTY; this
  --     asserts it is not, and that the streaks survived rather than merely
  --     the rows. The morning's two verified columns must each be green again
  --     with at least the five consecutive passes db/checks/0234 recorded.
  SELECT count(*) INTO v_cols FROM public.ottoq_cert_matrix(v_floor);
  IF v_cols < 9 THEN
    RAISE EXCEPTION '0310 A3: matrix returns % column(s), expected at least the 9 that existed before 0308', v_cols;
  END IF;

  SELECT count(*) INTO v_green FROM public.ottoq_cert_matrix(v_floor)
   WHERE green AND consecutive_passes >= 5
     AND ( (scenario = 'grid_smoke' AND seed = 239001 AND ticks = 6)
        OR (scenario = 'busy_day'   AND seed = 171717 AND ticks = 12) );
  IF v_green <> 2 THEN
    RAISE EXCEPTION '0310 A3: the two columns db/checks/0234 verified this morning are not both '
                    'green with >=5 consecutive passes (found %); the repair restored rows but not streaks', v_green;
  END IF;

  RAISE NOTICE '0310 post: floor restored to %, % columns, both verified columns green', v_floor, v_cols;
END $post$;
