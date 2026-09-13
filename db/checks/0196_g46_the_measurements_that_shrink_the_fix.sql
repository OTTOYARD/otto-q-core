-- 0196  G46 — THE MEASUREMENTS THAT SHRINK THE FIX
--
-- Two designs for G46 were reviewed and both came back unsound (db/checks/0193).
-- Both were gates: an admissibility test on the boot image deciding whether a pair
-- may join a canon. This file is the revision brief, and its finding is that the
-- gate was never the right instrument -- because THE THING BEING GATED IS ONE
-- SUB-PATH, and it is one the pair verdict provably does not need.
--
-- Five measurements, 2026-09-13. The first four remove work from the fix; the
-- fifth computes the fix's effect on the real history before any of it is applied.

-- ---------------------------------------------------------------------------
-- M1. WHAT ACTUALLY MOVES BETWEEN ROUNDS. For every canon column since the
--     recert floor, the number of DISTINCT values each endst sub-path took.
--     A sub-path with more than one value is a canon-rebasing source; a
--     sub-path with exactly one cannot be.
-- ---------------------------------------------------------------------------
WITH pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at)
         r.depot_id, r.started_at, (r.validation_notes::jsonb) AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness' AND r.validation_notes IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a') = 'object'
     AND (r.validation_notes::jsonb)->'arm_a' ? 'endst'
     AND r.started_at >= public.ottoq_cert_recert_floor()
   ORDER BY r.depot_id, r.started_at, r.sim_run_id),
k AS (SELECT depot_id, (j->>'seed') AS seed, (j->>'ticks') AS ticks,
             (j->>'scenario') AS scenario, j->'arm_a'->'endst' AS e FROM pair)
SELECT depot_id, seed, ticks, scenario, count(*) AS pairs,
       count(DISTINCT (e->'visit_needs'->'vis')::text) AS vn_vis,
       count(DISTINCT (e->'visit_needs'->'fgn')::text) AS vn_fgn,
       count(DISTINCT (e->'bookings'->'vis')::text)    AS bk_vis,
       count(DISTINCT (e->'bookings'->'fgn')::text)    AS bk_fgn,
       count(DISTINCT (e->'legs'->'vis')::text)        AS lg_vis,
       count(DISTINCT (e->'legs'->'fgn')::text)        AS lg_fgn,
       count(DISTINCT (e->'dispatches'->'vis')::text)  AS dp_vis,
       count(DISTINCT (e->'dispatches'->'fgn')::text)  AS dp_fgn,
       count(DISTINCT (e->'chargers')::text)           AS chargers,
       count(DISTINCT (e->'calibration')::text)        AS calibration,
       count(DISTINCT (e->'world')::text)              AS world
  FROM k GROUP BY 1,2,3,4 ORDER BY pairs DESC;
--
-- MEASURED: nine columns (seven flagship, two grid), 30 pairs.
--
--   EVERY column:           lg_fgn = 2  on all seven flagship columns
--   EVERY column:           every other sub-path = 1
--
-- `endst.legs.fgn` is the ONLY sub-path in the entire fourteen-atom verdict that
-- has taken more than one value since the floor. It is the whole of G46. The two
-- grid columns show 1 -- the grid depot has no other runs leaving residue in it,
-- which is why the grid lane never exhibited this and the flagship lane did.
--
-- The carrier is already named (db/checks/0187): nine pre-janitor legs on run
-- 9291ec6d, retired between rounds, moving legs.fgn.n from 13 to 9.

-- ---------------------------------------------------------------------------
-- M2. THE FOREIGN SECTIONS CONTRIBUTE NOTHING TO THE PAIR VERDICT. Restated
--     from 0193 finding 5 because it is now load-bearing rather than
--     incidental: across all 446 pairs carrying endst, endst.legs.fgn is
--     IDENTICAL between arm_a and arm_b in 100% of them; visit_needs.fgn and
--     dispatches.fgn differ in zero; bookings.fgn in exactly one (pre-0139).
--
--     So the fgn sections are, empirically: worth nothing to the intra-pair
--     claim, and the entire cost of the inter-round claim.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- M3. THE `vis` HALF IS RUN-TAGGED, WHICH CONTRADICTS BLOCKER (i) OF 0193.
--     The review's first blocker read: "the run's own digest is
--     residue-independent is FALSE -- endst's own half still hashes run-UNTAGGED
--     physical state." That is true of chargers/calibration/world. It was
--     ASSUMED to be true of the four sections too, because their `vis` branch is
--     `NOT fgn` = (sim_run_id IS NULL OR sim_run_id = p_run) -- so an untagged
--     row would land in `vis`.
--
--     Measured: THERE ARE NO UNTAGGED ROWS. Not at the flagship depot, not at
--     any depot, in any of the four tables. The NULL branch is dead.
-- ---------------------------------------------------------------------------
SELECT 'visit_needs' AS section, count(*) FILTER (WHERE sim_run_id IS NULL) AS untagged,
       count(*) AS total FROM public.ottoq_visit_needs
UNION ALL SELECT 'bookings',   count(*) FILTER (WHERE sim_run_id IS NULL), count(*)
            FROM public.ottoq_stall_bookings
UNION ALL SELECT 'legs',       count(*) FILTER (WHERE sim_run_id IS NULL), count(*)
            FROM public.ottoq_itinerary_legs
UNION ALL SELECT 'dispatches', count(*) FILTER (WHERE sim_run_id IS NULL), count(*)
            FROM public.ottoq_vehicle_dispatches;
-- MEASURED 2026-09-13: 0 untagged in all four, database-wide.
--
-- So `vis` IS `sim_run_id = p_run` in fact, and the four vis sections ARE
-- residue-independent. Blocker (i) survives only for chargers/calibration/world
-- -- and M1 shows all three have been constant across every pair since the floor.
-- THIS IS AN OBSERVATION, NOT A GUARANTEE: nothing in the schema forbids a NULL
-- sim_run_id, so a future writer could reintroduce one and it would land in
-- `vis`. It is recorded here as the reason the fix does not need to re-cut the
-- vis/fgn line, not as a claim that the line is enforced.

-- ---------------------------------------------------------------------------
-- M4. WHERE THE CANON DIGEST IS FORMED, which is the only place that has to
--     change. ottoq_cert_matrix does not read the boot fingerprint and does not
--     re-run anything: it reads the endst object the pair already recorded, as
--         md5((p.j->'arm_a'->'endst')::text) AS c_endst
--     one opaque digest over all seven top-level keys, fgn included. That single
--     line is the whole of G46's mechanism.
--
--     TWO CONSEQUENCES THAT DECIDE THE DESIGN:
--
--     (a) The split is computable from data ALREADY STORED, so it is
--         RETROACTIVE. Every historical pair re-keys without re-running a
--         single tick, and round 42 does not have to establish a canon from
--         nothing -- it inherits the history that is already on disk.
--
--     (b) No gate is needed, so every blocker in 0193 (iii) is void by
--         construction: there is no admissibility predicate, so there are not
--         two definitions of it; no `c_fgn = 0` to fail open on NULL; no
--         GREATEST to swallow a NULL; no boot fingerprint in
--         ottoq_cert_coverage and therefore none of its 8.2 s (the 0098 class);
--         no substitution anchor in a body whose spacing was wrong.
--         Blocker (ii) -- that boot-dirty/end-clean is the normal mode because
--         the metronome fires every minute -- is void for the same reason: with
--         nothing gated on the boot image, the metronome cannot stall a column.
-- ---------------------------------------------------------------------------
SELECT 'ottoq_cert_matrix' AS fn,
       (position('md5((p.j->''arm_a''->''endst'')::text)' in p.prosrc) > 0) AS forms_one_opaque_digest,
       md5(p.prosrc) AS src_md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';
-- MEASURED: true, md5 f5bb81931feae44871c3ecd86d4f86b4.


-- ---------------------------------------------------------------------------
-- M5. THE SPLIT, COMPUTED OVER THE REAL HISTORY BEFORE ANY OF IT IS APPLIED.
--     ottoq_cert_matrix's streak logic, copied verbatim, with c_endst replaced
--     by the own-half digest and everything else held identical -- so the only
--     variable in the comparison is the split itself. Run read-only 2026-09-13.
--
--       depot      seed    ticks scenario     today  own  recovered
--       flagship   171717   48   busy_day       2     6     +4
--       flagship   171717   24   busy_day       1     3     +2
--       flagship   424242   24   busy_day       1     3     +2
--       flagship   171717   12   busy_day       1     3     +2
--       flagship   314159   12   busy_day       1     3     +2
--       flagship   424242   12   busy_day       1     3     +2
--       flagship   171717   12   normal_day     1     3     +2
--       grid       239001    6   grid_smoke     3     3      0
--       grid       424242    6   grid_smoke     3     3      0
--
--     EVERY flagship column becomes unbroken back to the recert floor -- its
--     streak equals its pair count. And BOTH GRID COLUMNS ARE UNCHANGED, which
--     is the part that makes this evidence rather than flattery: the grid depot
--     has no other runs leaving residue in it, so if the split were a blanket
--     weakening the grid numbers would have moved too. They do not move. The
--     split only touches columns that were being rebased by another run's
--     leftovers.
--
--     A RESULT THIS FLATTERING IS A REASON FOR HOSTILE REVIEW, NOT A REASON TO
--     APPLY. Stated as a falsifiable prediction for round 42, so it can be wrong
--     out loud:
--
--       P1  After the migration, ottoq_cert_matrix(floor) returns n_pass equal
--           to n_pairs for all seven flagship columns and 3 for both grid
--           columns -- i.e. exactly the `own` column above, before round 42 adds
--           anything.
--       P2  The residue instrument reports 2 distinct fgn values on all seven
--           flagship columns and 1 on both grid columns, so the hygiene fact
--           round 41 surfaced is not lost, only relocated.
--       P3  Round 42 then extends every flagship column by one and breaks none,
--           UNLESS the nine legs move again in the interval -- in which case P3
--           fails on the residue column only and the engine columns still
--           extend. That last clause is the whole claim of this fix, and round
--           42 is where it is tested rather than argued.
--
--     WHY 6 of 9 COLUMNS ARE NOT GREEN TODAY and become green: the greenness
--     test is n_pass >= 2. The `eng` half of on_canon -- all twelve non-endst
--     atoms -- already matches on every one of these pairs; endst was their only
--     mismatch, and legs.fgn was endst's only mover (M1). So what is being
--     recovered is not a weakened standard, it is streaks that another run's
--     backlog reset.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- THE DESIGN THESE FIVE MEASUREMENTS LEAVE
--
--   The pair verdict is UNCHANGED. ottoq_determinism_pair keeps
--   `(arm_a->'endst') = (arm_b->'endst')` exactly as it stands, whole, fgn
--   included. Nothing about what a certification enforces moves, so no arm's
--   output can change and nothing here can invalidate a round in flight.
--
--   The MATRIX stops forming one digest and forms two from the same object:
--     c_endst      := md5 over endst with the four `fgn` sub-objects removed
--                     (the run's own end state + the world it ended in)
--     c_endst_fgn  := md5 over just the four `fgn` sub-objects
--                     (what OTHER runs left lying in live states)
--   The streak is computed on the first. The second is reported with its own
--   canon and its own streak, by a companion function, because a change in it
--   is a HYGIENE fact (G13's janitor) and not a determinism fact.
--
--   TWO STREAKS, TWO CLAIMS, BOTH PUBLISHED -- and the honest sentence names
--   which is which. "N consecutive rounds byte-identical" may never again stand
--   for both at once. That is the G25/G28 discipline applied to this fix rather
--   than suspended for it: nothing the pair enforces becomes invisible to the
--   matrix, it becomes visible in the column that describes it.
--
--   WHY A COMPANION FUNCTION AND NOT A WIDER ottoq_cert_matrix: adding a column
--   to a RETURNS TABLE is a return-type change, which CREATE OR REPLACE refuses
--   and which would require DROP -- forbidden by scripts/APPLYING.md, and it
--   would discard the function's privileges. `c_endst` keeps its name and type
--   and changes meaning; the meaning is stated in the function's COMMENT and
--   here.
--
--   WHAT THIS DOES NOT DO, said plainly: it does not clean the nine legs. They
--   are pre-janitor backlog from a run that ended 12h50m before 0089 shipped the
--   janitor (0193 finding 2), the correct terminal value for a 'planned' leg is
--   'skipped', and retiring them is a nine-row, depot-scoped, run-scoped,
--   ROW_COUNT-asserted UPDATE -- not this migration, and not the retention purge
--   (0193 finding 3: 939 runs, ~3.9M rows, to retire nine).
-- ---------------------------------------------------------------------------
