-- ===========================================================================
-- 0180  THE SECOND FLOOR READS HASH-ENFORCED DATA
--       -- which is the good news, and which is also what prices the 4h fix
-- ===========================================================================
-- Measured 2026-09-12 15:00-15:10 UTC (10:00-10:10 AM CT), read-only, pinned to run
-- 5d00244c-10c8-4ffc-b6c0-20dff04024bb. Nothing was written; no run was started.
--
-- db/checks/0177 showed service_completion is computable from atoms[].status and
-- observed that both arms of four round-38 pairs agreed exactly. That was an
-- OBSERVATION. This check asks whether it is a GUARANTEE, and the answer changes both
-- what may be claimed for the metric and what the next fix costs.
--
-- ---------------------------------------------------------------------------
-- 1. atoms IS INSIDE AN ENFORCED VERDICT ATOM
-- ---------------------------------------------------------------------------
--
-- public.ottoq_determinism_pair, read from the live body:
--
--   line  44   v_boot := public.ottoq_boot_state_fingerprint(p_depot, v_run);
--   line  60     'endst', public.ottoq_boot_state_fingerprint(p_depot, v_run),
--   line 118        AND (v_arms[1]->'endst') = (v_arms[2]->'endst');
--
-- So `endst` -- one of the fourteen ENFORCED atoms, unlike `boot`, which 0125 made
-- diagnostic -- is the boot-state fingerprint evaluated after the last tick. And that
-- function's visit_needs CTE hashes the row like this:
--
--   md5((to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta')::text)
--
-- `atoms` is not in the exclusion list, so the whole jsonb array -- every svc, status,
-- est_min, started_at, ends_at, done_at, closed_at, closed_by -- is inside the hash.
-- Demonstrated rather than read off the column list, on the two widest rows of the run:
--
--   visit 2091a513 (8 atoms)  hashed as endst does 414c29bf...  with atoms removed 42cbc1d8...
--   visit e1c3b502 (7 atoms)  hashed as endst does f4031d4b...  with atoms removed dd4c04b1...
--
-- Different both times. atoms is inside the hash.
--
-- ---------------------------------------------------------------------------
-- 2. WHAT THAT LICENSES FOR THE METRIC
-- ---------------------------------------------------------------------------
--
-- The arm-identity 0177 observed is not luck and does not need re-observing each round:
-- if two arms of a pair ever disagreed on any atom's status, est_min or timestamps, the
-- pair would FAIL on endst. So `ottoq_kpi_service_completion` (0257) reads a substrate
-- whose byte-identity across arms is already a standing, enforced certification result.
--
-- That is a stronger sentence than the company usually gets to say about a KPI, and it
-- is worth saying precisely: the number is not merely reproducible when checked -- its
-- inputs are inside the fourteen-atom verdict that is checked every round. 0257's A3
-- still pins it on one pair, because an assertion that depends on another instrument
-- staying correct should also stand on its own measurement.
--
-- WHAT IT DOES NOT LICENSE. endst enforces that the two arms of ONE pair agree. It says
-- nothing about two pairs agreeing with each other -- that is 0193's separate bar, the
-- one busy_day/171717/48t keeps failing and 0255/0256 address. A completion number
-- quoted across rounds still rests on that bar, not on this one.
--
-- ---------------------------------------------------------------------------
-- 3. AND WHAT IT COSTS THE 4h FIX -- THE POINT OF WRITING THIS DOWN
-- ---------------------------------------------------------------------------
--
-- BUILD_QUEUE 4h is: the charge satisfaction path stamps closed_at but no start and no
-- end, so 100% of charge completions have no duration. The obvious fix is to have
-- ottoq.ottoq_close_satisfied_charge_needs stamp started_at/ends_at like the
-- atom-execution path does.
--
-- That fix CHANGES THE CONTENT OF atoms, which is inside endst, which is enforced.
-- Therefore:
--
--   * it is forces_recert=TRUE, necessarily -- every canon in the matrix is invalidated
--     and must be re-earned over a full round;
--   * it must land at the START of an apply window with a whole round behind it, the
--     same discipline 0255 followed;
--   * and it should be BATCHED with other recert-forcing changes rather than applied
--     alone, because the cost is per-window, not per-migration.
--
-- So 4h is not the small change it looks like. It is a one-round change. That is not an
-- argument against it -- a duration model that cannot see the dominant operation is
-- worse -- but it is the reason not to slip it in beside a read-only view.
--
-- THE GENERAL RULE THIS MAKES EXPLICIT, because it will come up again: any change to a
-- column or jsonb key that ottoq_boot_state_fingerprint's projections do not exclude is
-- a recert-forcing change, however cosmetic it looks. The exclusion list is the
-- boundary between "free" and "costs a round", and it is four keys long:
-- visit_id, sim_run_id, created_at, updated_at, meta.
--
-- ===========================================================================
-- RE-RUNNABLE MEASUREMENTS
-- ===========================================================================

-- 3.1  atoms is inside the hash endst computes. Both columns must differ.
SELECT t.visit_id,
       jsonb_array_length(COALESCE(t.atoms,'[]'::jsonb)) AS n_atoms,
       md5((to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta')::text)
         AS hashed_as_endst_does,
       md5((to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta' - 'atoms')::text)
         AS same_but_atoms_removed,
       (md5((to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta')::text)
        <> md5((to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta' - 'atoms')::text))
         AS atoms_is_inside_the_hash
  FROM public.ottoq_visit_needs t
 WHERE t.sim_run_id = '5d00244c-10c8-4ffc-b6c0-20dff04024bb'::uuid
 ORDER BY n_atoms DESC
 LIMIT 2;

-- 3.2  endst is the boot-state fingerprint, and it is in the equality chain.
WITH s AS (
  SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair'
), l AS (SELECT row_number() OVER () AS ln, line
           FROM s, regexp_split_to_table(s.prosrc, E'\n') AS line)
SELECT ln, line FROM l
 WHERE line ILIKE '%endst%' OR line ILIKE '%boot_state_fingerprint%'
 ORDER BY ln;

-- 3.3  The four-key exclusion list -- the boundary between a free change and a
--      recert-forcing one. If this stops returning 1, section 3's rule has moved.
SELECT (SELECT count(*) FROM regexp_matches(p.prosrc,
          E'- ''visit_id'' - ''sim_run_id'' - ''created_at'' - ''updated_at'' - ''meta''', 'g'))
         AS needs_projection_sites
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_boot_state_fingerprint';
