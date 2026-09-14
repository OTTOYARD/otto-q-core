-- ---------------------------------------------------------------------------
-- 0193 — THE G46 DESIGN REVIEW: BOTH CANDIDATES UNSAFE, AND THE SKETCH IN 0187
-- WOULD HAVE TOUCHED 2,301 ROWS ON TWO DEPOTS TO RETIRE NINE.
--
-- Two designs for G46 (db/checks/0187) plus a judge plus two adversarial
-- reviewers, 2026-09-13 05:00-05:50 UTC. Verdicts: "sound_with_changes" from the
-- instrument lens, **"unsound"** from the migration-discipline lens. NOTHING WAS
-- APPLIED. This file records what the review established, because five of its
-- findings correct things THIS REPOSITORY already says, including two I wrote
-- tonight.
-- ---------------------------------------------------------------------------

-- 1. THE ONE IN MY OWN WRITE-UP. db/checks/0187 candidate (a) sketched "a scoped
--    UPDATE on legs whose run is not running". Measured, that predicate is
--    depot-blind:
SELECT v.home_depot_id AS depot, r.run_by, l.status, count(*) AS n,
       count(DISTINCT l.sim_run_id) AS runs
  FROM public.ottoq_itinerary_legs l
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = l.sim_run_id
  LEFT JOIN public.vehicles v ON v.id = l.vehicle_id
 WHERE l.status IN ('planned','active') AND r.status <> 'running'
 GROUP BY 1,2,3 ORDER BY n DESC;
-- MEASURED 2026-09-13 05:52 UTC:
--   22222222… | benchmark     | planned | 2,128 | 9 runs
--   22222222… | benchmark     | active  |   164 | 9 runs
--   11111111… | operator_demo | planned |     9 | 1 run
-- 2,301 rows across TWO depots and TEN runs, to retire NINE on one depot. And
-- every assertion 0187 sketched (no run left 'running', residue reaches 0, the
-- nine are gone) would have PASSED on that outcome. The mandatory additions are
-- a depot predicate, a run-id predicate, and `GET DIAGNOSTICS ROW_COUNT = 9`
-- with a refusal on any other value -- a count assertion, not a property one.

-- 2. THE JANITOR ALREADY EXISTS, so 0187 and 0191 both reasoned from a gap that
--    was closed eight days before the residue was measured. 0089 put
--    planned -> 'skipped' and active -> 'amended' inside
--    public.ottoq_sim_release_depot, and its own comment names THIS run.
SELECT p.proname,
       (position('skipped' in p.prosrc) > 0)                       AS sets_skipped,
       (position('amended' in p.prosrc) > 0)                       AS sets_amended,
       (position('9291ec6d' in p.prosrc) > 0)                      AS names_the_run
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.proname = 'ottoq_sim_release_depot';
-- The nine legs are PRE-JANITOR BACKLOG: run 9291ec6d ended 2026-08-29 03:50:12
-- UTC and 0089 applied 12h50m later. Two consequences:
--   * the correct terminal value for a 'planned' leg is **'skipped'**, not the
--     'amended' 0187 sketched (amended is for 'active');
--   * G13's janitor gap is narrower than BUILD_QUEUE says for this path.

-- 3. AND THE PURGE IS THE WRONG HAMMER FOR IT. db/checks/0191 recommended "fix
--    the instrument and let the janitor clean the floor", meaning the retention
--    purge. Measured by the review: the doomed set is 939 runs carrying roughly
--    3.9 MILLION rows across four tables (1,133,286 ottoq_events, 915,817
--    ottoq_stall_bookings, 591,871 ottoq_itinerary_legs, and the remainder).
--    Running an irreversible multi-million-row delete to retire nine legs is
--    disproportionate, and 0191 should not be read as proposing it.
SELECT count(*) AS doomed_runs
  FROM public.ottoq_sim_runs sr
 WHERE sr.status <> 'running'
   AND COALESCE(sr.run_by,'') <> 'production_live'
   AND sr.started_at < now() - COALESCE((SELECT keep_interval FROM public.ottoq_retention_policy
                                          WHERE policy_key='engine_rows' AND enabled),
                                        interval '48 hours')
   AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id);
-- MEASURED: 939. The purge stays the right mechanism for RETENTION. It is not the
-- right mechanism for THIS residue: a nine-row, depot-scoped, run-scoped,
-- count-asserted UPDATE is.

-- 4. 'inconclusive' IS INVISIBLE, NOT RED — which convicts 0187's candidate (a).
--    ottoq_cert_matrix strips inconclusive rows in its `col` CTE, BEFORE ranked,
--    canon, marked, streak and hist. So such a pair adds 1 to inconclusive_pairs
--    and changes nothing else: it cannot break a streak, cannot de-green, does not
--    advance last_pair_at, and is not counted in pairs_seen. A window whose only
--    pairs are inconclusive returns NO MATRIX ROW AT ALL -- while
--    ottoq_cert_coverage, which has no status filter, keeps reporting that column
--    OK. Candidate (a) would have traded "cries wolf, then re-baselines" for
--    "goes silent, and nothing says so".
SELECT 'see ottoq_cert_matrix: col AS (SELECT * FROM keyed WHERE st <> ''inconclusive'')' AS mechanism;

-- 5. AND THE ARM-VS-ARM ARGUMENT FOR KEEPING fgn HAS NO EMPIRICAL SUPPORT.
--    0187 candidate (b) proposed keeping fgn for arm-vs-arm equality "where it is
--    correct and cheap". Measured across ALL 446 certification pairs carrying
--    endst: endst.legs.fgn is IDENTICAL between arm_a and arm_b in 100% of them.
--    visit_needs.fgn and dispatches.fgn differ in zero pairs; bookings.fgn differs
--    in exactly one (a pre-0139 passed pair). 0125's stated expectation that the
--    fgn sections "differ by construction" is falsified by the current engine.
WITH pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at) (r.validation_notes::jsonb) AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by='cert_harness' AND r.validation_notes IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
     AND (r.validation_notes::jsonb)->'arm_a' ? 'endst'
   ORDER BY r.depot_id, r.started_at, r.sim_run_id)
SELECT count(*) AS pairs_with_endst,
       count(*) FILTER (WHERE (j->'arm_a'->'endst'->'legs'->'fgn')
                           IS DISTINCT FROM (j->'arm_b'->'endst'->'legs'->'fgn')) AS legs_fgn_differs,
       count(*) FILTER (WHERE (j->'arm_a'->'endst'->'bookings'->'fgn')
                           IS DISTINCT FROM (j->'arm_b'->'endst'->'bookings'->'fgn')) AS bkg_fgn_differs
  FROM pair;

-- 6. THE VERDICT IS PER PAIR, NOT PER ARM — so "20 of 20 arm runs passed" is ten
--    pair verdicts stamped on twenty rows. One statement at the end of
--    ottoq_determinism_pair writes the same outcome to both arm rows:
--      UPDATE ottoq_sim_runs SET validation_status = v_outcome, ... WHERE sim_run_id IN (arm_a, arm_b)
--    db/canons/round41.md is corrected accordingly. It is not wrong, but it reads
--    as twenty independent checks and it is ten.

-- ---------------------------------------------------------------------------
-- WHY NOTHING WAS APPLIED, AND WHAT THE REVISION MUST CLOSE
--
-- Beyond the five corrections above, the reviews named blockers in the plan
-- itself. The three that decide the shape:
--
--  (i) "THE RUN'S OWN DIGEST IS RESIDUE-INDEPENDENT" IS FALSE. endst's own half
--      still hashes run-UNTAGGED physical state (chargers.world, world,
--      calibration). A dirty pair can therefore still rebase the own digest
--      through the untagged half, and the proposed arrangement would mark the
--      dirty canon blocked while blaming the LATER CLEAN pairs that mismatch it.
--
-- (ii) BOOT-DIRTY / END-CLEAN IS THE NORMAL OPERATING MODE, not an exotic case:
--      cron jobid 12 (ottoq-demo-metronome) fires EVERY MINUTE and jobid 17
--      (ottoq-run-governor) every two, and both can stop a non-cert run mid-pair.
--      An admissibility gate keyed on the boot image would stall columns
--      permanently and silently -- the same failure mode as candidate (a).
--
-- (iii) TWO DEFINITIONS OF ADMISSIBLE, and the louder instrument using the
--      narrower one, recreates G25/G28 INSIDE the fix for G46. Plus: `AND c_fgn = 0`
--      fails OPEN on NULL (bool_and skips NULLs), GREATEST swallows the helper's
--      NULL so "unknown is not clean" is not what gets installed, embedding the
--      boot fingerprint in ottoq_cert_coverage costs 8.2 s cold against 188 ms
--      today (the db/checks/0098 class), one substitution anchor does not occur in
--      the live body (spacing) and would produce a double comma, and the coverage
--      file carried no pre-image snapshot and no nothing-in-flight block.
--
-- ROUND 42 STAYS BLOCKED. The revision brief is those findings plus the five
-- corrections here. What does NOT need revisiting: the decision to guard the canon
-- where it is DERIVED rather than in the function that measures or in a script
-- somebody has to remember to run, and the decision that a column which stops
-- certifying must say so out loud rather than going quiet.
-- ---------------------------------------------------------------------------
