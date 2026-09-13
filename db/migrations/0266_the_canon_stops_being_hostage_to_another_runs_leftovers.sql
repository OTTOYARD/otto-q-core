-- migration-version: PENDING
-- migration-name: 0266_the_canon_stops_being_hostage_to_another_runs_leftovers
--
-- 0266  THE CANON STOPS BEING HOSTAGE TO ANOTHER RUN'S LEFTOVERS  (G46 + G48)
--
-- TWO FINDINGS, ONE FILE, and not for convenience: db/checks/0190 says G48's fix
-- "belongs in the same migration as G46's ... because it is the same function, the
-- same round, and the same recert conversation." Both change what
-- ottoq_cert_matrix admits to a canon; applying them separately would mean two
-- recert conversations about one instrument. G48 is section 1's `pair` CTE
-- predicate and assertions A10/A10b; everything else is G46.
--
-- WHY. Round 41 passed 10 of 10 pairs with 13 of 14 atoms byte-identical to round
-- 40 in all nine columns, and the canon rebased anyway. The one atom that moved was
-- endst.legs.fgn.n, 13 -> 9: nine pre-janitor legs belonging to ANOTHER run were
-- retired between the rounds. The engine did not change. The streak reset.
--
-- WHAT IS ACTUALLY BEING FIXED, measured rather than argued (db/checks/0196):
--
--   M1  endst.legs.fgn is the ONLY sub-path of the entire fourteen-atom verdict
--       that has taken more than one value since the recert floor. Every other
--       sub-path -- all eight vis sections, chargers, calibration, world -- has
--       exactly one value across all 30 post-floor pairs.
--   M2  The fgn sections are identical between arm_a and arm_b in 446 of 446
--       pairs. They contribute NOTHING to the intra-pair verdict and all of
--       G46's noise to the inter-round one.
--   M3  There are ZERO rows with a NULL sim_run_id in any of the four tables,
--       database-wide, so the `vis` branch is in fact `sim_run_id = p_run`.
--   M4  The canon digest is formed in ONE line of ottoq_cert_matrix, from the
--       endst object the pair already recorded. So the split is computable from
--       data already on disk: it is RETROACTIVE and re-runs nothing.
--   M5  Applying the split to the real history: every flagship column becomes
--       unbroken back to the floor, and BOTH GRID COLUMNS DO NOT MOVE. The grid
--       depot has no other runs leaving residue in it; if this were a blanket
--       weakening the grid numbers would have moved too.
--
-- WHY THERE IS NO GATE. Both designs reviewed in db/checks/0193 were admissibility
-- gates on the boot image, and both came back unsound. Every one of that review's
-- blockers is void here by construction, because nothing is gated: there is no
-- admissibility predicate (so not two definitions of one), no `c_fgn = 0` to fail
-- open on NULL, no GREATEST to swallow a NULL, no boot fingerprint in
-- ottoq_cert_coverage and therefore none of its 8.2 s (the 0098 class), and the
-- metronome firing every minute cannot stall a column because no column waits on
-- the boot image.
--
-- WHAT THIS DOES NOT TOUCH. ottoq_determinism_pair is NOT MODIFIED. It keeps
--   (v_arms[1]->'endst') = (v_arms[2]->'endst')
-- whole, fgn included. Nothing about what a certification ENFORCES moves, so no
-- arm's output can change and this cannot invalidate a round. The ONLY behaviour
-- that changes is how a reporting function groups what is already recorded.
--
-- TWO STREAKS, TWO CLAIMS, BOTH PUBLISHED. This is the G25/G28 discipline applied
-- to the fix rather than suspended for it. Nothing the pair enforces becomes
-- invisible: the own half is streaked by ottoq_cert_matrix, the foreign half is
-- streaked by ottoq_cert_residue (new, below), and the honest sentence names which
-- is which. "N consecutive rounds byte-identical" may never again stand for both.
--
-- NO new table, NO new column, NO DROP, nothing written to ottoq_events, one
-- function replaced and one added. CREATE OR REPLACE preserves privileges on the
-- replaced one (A6 asserts proacl is unchanged). The replaced function keeps its
-- EXACT signature, including the name and type of every RETURNS TABLE column --
-- `canon_endst` keeps its name and changes its meaning, which is stated in the
-- function's COMMENT -- because widening the row would be a return-type change,
-- which CREATE OR REPLACE refuses and which would require the DROP that
-- scripts/APPLYING.md forbids.

-- ---------------------------------------------------------------------------
-- P. NOTHING IN FLIGHT. pg_stat_activity is the only authority: a pair runs both
--    arms in ONE transaction, so its ottoq_sim_runs rows are invisible until it
--    commits.
-- ---------------------------------------------------------------------------
DO $p$
DECLARE v_busy int; v_jobs int; v_live int;
BEGIN
  SELECT count(*) INTO v_busy FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_sim_advance_tick%'
          OR query ILIKE '%ottoq_ab_pair%');
  IF v_busy > 0 THEN
    RAISE EXCEPTION '0266 P: % certification/pair call(s) in flight', v_busy;
  END IF;
  SELECT count(*) INTO v_jobs FROM cron.job WHERE active AND jobname ~ '^r[0-9]+_';
  IF v_jobs > 0 THEN
    RAISE EXCEPTION '0266 P: % round job(s) still scheduled', v_jobs;
  END IF;
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_live > 0 THEN
    RAISE EXCEPTION '0266 P: % run(s) running or paused', v_live;
  END IF;
END $p$;

-- ---------------------------------------------------------------------------
-- S. PRE-IMAGE. Recorded so the APPLY LOG can show exactly what moved, and so a
--    reader can tell a replaced body from an unchanged one without guessing.
-- ---------------------------------------------------------------------------
SELECT p.proname, md5(p.prosrc) AS prosrc_md5, md5(pg_get_functiondef(p.oid)) AS def_md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_cert_matrix','ottoq_determinism_pair','ottoq_boot_state_fingerprint')
 ORDER BY 1;
-- PRE-IMAGE MEASURED 2026-09-13:
--   ottoq_boot_state_fingerprint  prosrc 90d490c24ae084d03477a8a782a9f856
--   ottoq_cert_matrix             prosrc f5bb81931feae44871c3ecd86d4f86b4
--   ottoq_determinism_pair        prosrc 8a35b8c874fed154cc216140faec0274   <- the pin
-- Only ottoq_cert_matrix may move. A8 asserts the other two do not.

-- ---------------------------------------------------------------------------
-- 1. THE MATRIX. Byte-for-byte the live body except for the c_endst expression
--    in `keyed` and its comment. Everything else -- the pair CTE, the key, inc,
--    col, ranked, canon, marked, streak, hist, the final SELECT and its ORDER BY
--    -- is copied verbatim from pg_get_functiondef, so the only variable is the
--    split.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_cert_matrix(
  p_since timestamp with time zone DEFAULT (now() - '30 days'::interval))
 RETURNS TABLE(depot uuid, seed bigint, ticks integer, scenario text, pairs_seen integer,
               consecutive_passes integer, green boolean, last_pair_at timestamp with time zone,
               canon_fp text, canon_cmd text, canon_dec text, canon_evt text, canon_bkg text,
               canon_nrg text, last_run_a uuid, last_run_b uuid, history text, stale boolean,
               recert_floor timestamp with time zone, inconclusive_pairs integer,
               canon_prop text, canon_defr text, canon_cal text, canon_rule text,
               canon_rcl text, canon_sdr text, canon_endst text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
WITH fl AS (
  SELECT public.ottoq_cert_recert_floor() AS rf
), pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at)
         r.depot_id                              AS c_depot,
         r.started_at                            AS t0,
         r.validation_status                     AS st,
         (r.validation_status = 'passed')        AS ok,
         (r.validation_notes::jsonb)             AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness'
     AND r.started_at >= p_since
     AND r.validation_status IS NOT NULL
     AND r.validation_notes IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb) -> 'arm_a') = 'object'
     /* 0266 (G48, db/checks/0190): A REPLAY PAIR IS NOT A CERTIFICATION.
        ottoq_determinism_pair_replay builds its arms with the SAME
        run_by='cert_harness' and the SAME validation_notes shape, then injects a
        captured proposal stream into both. It asks a different question -- can a
        NONDETERMINISTIC proposer's recorded stream be re-consumed identically --
        with proposals deliberately present, where a certification runs the core
        alone (0152). Their h_prop atoms are SUPPOSED to differ.
        Two failure modes, and the second is the dangerous one: a failing replay
        breaks a column's streak (noise), and a PASSING replay becomes the
        column's canon, whose h_prop is then the injected stream's hash -- so
        every later honest certification disagrees with it, correctly, and the
        column reads as an engine regression. That is G46's silent rebase with a
        worse story. Nine replay pairs already exist; the only thing protecting
        today's canon is that all nine predate the recert floor.
        BOTH clauses, deliberately. The first excludes a pair that names a
        replay_id; the second survives a future replay that forgets to. And
        neither excludes the two ZERO-INJECTION CONTROL pairs, which are honest
        certification data: `replay` is present with a NULL VALUE on a control,
        so the obvious `NOT (notes ? 'replay')` would wrongly drop them.
        THREE clauses, not the two db/checks/0190 specified, and the deviation is
        deliberate: 0190's predicate reads arm_a only. Read structurally,
        ottoq_determinism_pair_replay writes 'replay_injected' ONCE, inside the
        per-arm object built in its 1..2 arm loop, so both arms carry it and
        today they never disagree (measured: 0 of 500 pairs). But that is a
        SYMMETRY THE PREDICATE WOULD BE DEPENDING ON WITHOUT ENFORCING -- an
        asymmetric future injection would leave arm_a at 0 and slip a replay into
        a canon. Reading both arms costs nothing (measured: the same 7 pairs are
        excluded either way) and removes the dependency. Two COALESCE'd clauses
        rather than GREATEST, because GREATEST swallows a NULL and 0193 (iii)
        names that exact failure. */
     AND (r.validation_notes::jsonb ->> 'replay') IS NULL
     AND COALESCE((r.validation_notes::jsonb -> 'arm_a' ->> 'replay_injected')::int, 0) = 0
     AND COALESCE((r.validation_notes::jsonb -> 'arm_b' ->> 'replay_injected')::int, 0) = 0
   ORDER BY r.depot_id, r.started_at, r.sim_run_id
), keyed AS (
  SELECT p.c_depot, p.t0, p.ok, p.st,
         (p.j->>'seed')::bigint                    AS c_seed,
         COALESCE((p.j->>'ticks')::int, -1)        AS c_ticks,
         COALESCE(p.j->>'scenario', '?')           AS c_scen,
         p.j->'arm_a'->>'fp'                       AS c_fp,
         p.j->'arm_a'->>'h_cmd'                    AS c_cmd,
         p.j->'arm_a'->>'h_dec'                    AS c_dec,
         p.j->'arm_a'->>'h_evt'                    AS c_evt,
         p.j->'arm_a'->>'h_bkg'                    AS c_bkg,
         p.j->'arm_a'->>'h_nrg'                    AS c_nrg,
         p.j->'arm_a'->>'h_prop'                   AS c_prop,   -- 0199; NULL before 0199
         p.j->'arm_a'->>'h_defr'                   AS c_defr,   -- 0199; NULL before 0199
         p.j->'arm_a'->>'h_rule'                   AS c_rule,   -- 0203; NULL before 0203; reported, not judged (G15)
         p.j->'arm_a'->>'h_rcl'                    AS c_rcl,
         p.j->'arm_a'->>'h_cal'                    AS c_cal,    -- 0201; NULL before 0201
         p.j->'arm_a'->>'h_sdr'                    AS c_sdr,    -- 0217/0219; NULL before 0217
         /* 0266 (G46): THE RUN'S OWN END STATE, not the depot's.
            Was md5((p.j->'arm_a'->'endst')::text) -- one opaque digest over all
            seven top-level keys, the four `fgn` sub-objects included. Those four
            count OTHER runs' rows left in live states, and retiring nine such
            legs between round 40 and round 41 rebased every flagship canon while
            the engine was byte-identical.
            Rebuilt explicitly rather than by subtraction so the key set is
            visible here and cannot drift with the fingerprint's shape: the four
            `vis` halves (this run's own rows -- measured M3, there are no
            untagged rows anywhere, so `vis` IS sim_run_id = p_run) plus the three
            world keys the run genuinely ended in.
            NULL when the pair predates endst, preserving the 0139/0199/0201/0225
            convention that an instrument cannot judge a pair older than itself;
            the NULL-tolerant comparison in `marked` is unchanged. */
         CASE WHEN (p.j->'arm_a') ? 'endst' THEN md5(jsonb_build_object(
                'visit_needs', p.j->'arm_a'->'endst'->'visit_needs'->'vis',
                'bookings',    p.j->'arm_a'->'endst'->'bookings'->'vis',
                'legs',        p.j->'arm_a'->'endst'->'legs'->'vis',
                'dispatches',  p.j->'arm_a'->'endst'->'dispatches'->'vis',
                'chargers',    p.j->'arm_a'->'endst'->'chargers',
                'calibration', p.j->'arm_a'->'endst'->'calibration',
                'world',       p.j->'arm_a'->'endst'->'world')::text) END AS c_endst,
         (p.j->'arm_a'->>'run')::uuid              AS c_run_a,
         (p.j->'arm_b'->>'run')::uuid              AS c_run_b
    FROM pair p
), inc AS (
  SELECT c_depot, c_seed, c_ticks, c_scen, count(*)::int AS n_inc
    FROM keyed WHERE st = 'inconclusive'
   GROUP BY c_depot, c_seed, c_ticks, c_scen
), col AS (
  SELECT * FROM keyed WHERE st <> 'inconclusive'
), ranked AS (
  SELECT c.*, row_number() OVER (PARTITION BY c.c_depot, c.c_seed, c.c_ticks, c.c_scen
                                 ORDER BY c.t0 DESC, c.c_run_a DESC) AS rn
    FROM col c
), canon AS (
  SELECT rk.c_depot, rk.c_seed, rk.c_ticks, rk.c_scen,
         rk.c_fp, rk.c_cmd, rk.c_dec, rk.c_evt, rk.c_bkg, rk.c_nrg, rk.c_prop, rk.c_defr, rk.c_cal, rk.c_rule, rk.c_rcl,
         rk.c_sdr, rk.c_endst
    FROM ranked rk WHERE rk.rn = 1
), marked AS (
  SELECT r.c_depot, r.c_seed, r.c_ticks, r.c_scen, r.rn,
         (r.ok
          AND r.t0 >= fl.rf
          AND r.c_fp  IS NOT DISTINCT FROM k.c_fp
          AND r.c_cmd IS NOT DISTINCT FROM k.c_cmd
          AND r.c_dec IS NOT DISTINCT FROM k.c_dec
          AND r.c_evt IS NOT DISTINCT FROM k.c_evt
          AND r.c_bkg IS NOT DISTINCT FROM k.c_bkg
          AND r.c_nrg IS NOT DISTINCT FROM k.c_nrg
          -- 0199: a pair hashed before the instrument existed cannot be judged by it
          AND (r.c_prop IS NULL OR k.c_prop IS NULL OR r.c_prop = k.c_prop)
          AND (r.c_defr IS NULL OR k.c_defr IS NULL OR r.c_defr = k.c_defr)
          -- 0201: same rule for the priors fingerprint
          AND (r.c_cal  IS NULL OR k.c_cal  IS NULL OR r.c_cal  = k.c_cal)
          -- 0225: the four atoms the pair enforced and the matrix could not see
          -- (db/checks/0134). NULL-tolerant for the same reason as 0199 and
          -- 0201: a pair hashed before the instrument existed cannot be judged
          -- by it.
          AND (r.c_rule  IS NULL OR k.c_rule  IS NULL OR r.c_rule  = k.c_rule)
          AND (r.c_rcl   IS NULL OR k.c_rcl   IS NULL OR r.c_rcl   = k.c_rcl)
          AND (r.c_sdr   IS NULL OR k.c_sdr   IS NULL OR r.c_sdr   = k.c_sdr)
          AND (r.c_endst IS NULL OR k.c_endst IS NULL OR r.c_endst = k.c_endst)) AS on_canon
    FROM ranked r
    JOIN canon k ON k.c_depot = r.c_depot AND k.c_seed = r.c_seed
                AND k.c_ticks = r.c_ticks AND k.c_scen = r.c_scen
    CROSS JOIN fl
), streak AS (
  SELECT x.c_depot, x.c_seed, x.c_ticks, x.c_scen,
         count(*) FILTER (WHERE x.unbroken)::int AS n_pass
    FROM (
      SELECT m.c_depot, m.c_seed, m.c_ticks, m.c_scen,
             bool_and(m.on_canon) OVER (PARTITION BY m.c_depot, m.c_seed, m.c_ticks, m.c_scen
                                        ORDER BY m.rn
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS unbroken
        FROM marked m
    ) x
   GROUP BY x.c_depot, x.c_seed, x.c_ticks, x.c_scen
), hist AS (
  SELECT c.c_depot, c.c_seed, c.c_ticks, c.c_scen,
         string_agg(CASE WHEN c.ok THEN 'P' ELSE 'f' END, '' ORDER BY c.t0) AS h_hist,
         count(*)::int AS n_pairs
    FROM col c GROUP BY c.c_depot, c.c_seed, c.c_ticks, c.c_scen
)
SELECT h.c_depot, h.c_seed, h.c_ticks, h.c_scen, h.n_pairs,
       COALESCE(s.n_pass, 0),
       (COALESCE(s.n_pass, 0) >= 2 AND l.t0 >= fl.rf),
       l.t0, l.c_fp, l.c_cmd, l.c_dec, l.c_evt, l.c_bkg, l.c_nrg, l.c_run_a, l.c_run_b,
       h.h_hist,
       (l.t0 < fl.rf),
       fl.rf,
       COALESCE(i.n_inc, 0),
       l.c_prop, l.c_defr, l.c_cal, l.c_rule, l.c_rcl, l.c_sdr, l.c_endst
  FROM hist h
  JOIN streak s ON s.c_depot = h.c_depot AND s.c_seed = h.c_seed AND s.c_ticks = h.c_ticks AND s.c_scen = h.c_scen
  JOIN ranked l ON l.c_depot = h.c_depot AND l.c_seed = h.c_seed AND l.c_ticks = h.c_ticks
               AND l.c_scen = h.c_scen AND l.rn = 1
  LEFT JOIN inc i ON i.c_depot = h.c_depot AND i.c_seed = h.c_seed AND i.c_ticks = h.c_ticks AND i.c_scen = h.c_scen
  CROSS JOIN fl
 ORDER BY h.c_depot, h.c_ticks DESC, h.c_scen, h.c_seed;
$function$;

COMMENT ON FUNCTION public.ottoq_cert_matrix(timestamptz) IS
'The canon matrix. 0266 (G46): canon_endst is the digest of the run''s OWN end state -- the four vis sections plus chargers, calibration and world -- and NO LONGER includes the four fgn sections, which count other runs'' rows left in live states and which rebased every flagship canon in round 41 while the engine was byte-identical. The pair verdict is unchanged and still enforces endst whole, so nothing enforced became invisible: the foreign half has its own canon and its own streak in public.ottoq_cert_residue, and a round report prints both. "N consecutive rounds byte-identical" names the engine columns only; the residue column is a hygiene number and is quoted separately.';

-- ---------------------------------------------------------------------------
-- 2. THE RESIDUE INSTRUMENT. The other half of "two streaks, two claims": the
--    four fgn sections, with their own canon, their own streak and their own
--    history string, so a change in what other runs leave lying around is
--    REPORTED rather than either ignored or charged to the engine.
--
--    Deliberately NOT folded into ottoq_cert_matrix: adding a column to a
--    RETURNS TABLE is a return-type change, which CREATE OR REPLACE refuses and
--    which would require a DROP (forbidden, scripts/APPLYING.md) and discard the
--    function's privileges.
--
--    `sections_moved` names WHICH of the four moved against the canon, so the
--    hygiene finding is actionable rather than a bare mismatch -- round 41's was
--    legs, and naming it is what led to the nine pre-janitor rows.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_cert_residue(
  p_since timestamp with time zone DEFAULT (now() - '30 days'::interval))
 RETURNS TABLE(depot uuid, seed bigint, ticks integer, scenario text, pairs_seen integer,
               consecutive_same integer, last_pair_at timestamp with time zone,
               canon_fgn text, history text, recert_floor timestamp with time zone,
               sections_moved text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
WITH fl AS (
  SELECT public.ottoq_cert_recert_floor() AS rf
), pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at)
         r.depot_id                       AS c_depot,
         r.started_at                     AS t0,
         r.validation_status              AS st,
         (r.validation_notes::jsonb)      AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness'
     AND r.started_at >= p_since
     AND r.validation_status IS NOT NULL
     AND r.validation_notes IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb) -> 'arm_a') = 'object'
     --: G48, the SAME predicate as the matrix, verbatim. The two instruments
     --: must agree about which pairs exist or A5's column-set equality is a
     --: coincidence rather than a guarantee.
     AND (r.validation_notes::jsonb ->> 'replay') IS NULL
     AND COALESCE((r.validation_notes::jsonb -> 'arm_a' ->> 'replay_injected')::int, 0) = 0
     AND COALESCE((r.validation_notes::jsonb -> 'arm_b' ->> 'replay_injected')::int, 0) = 0
   ORDER BY r.depot_id, r.started_at, r.sim_run_id
), keyed AS (
  SELECT p.c_depot, p.t0, p.st,
         (p.j->>'seed')::bigint             AS c_seed,
         COALESCE((p.j->>'ticks')::int, -1) AS c_ticks,
         COALESCE(p.j->>'scenario', '?')    AS c_scen,
         (p.j->'arm_a'->>'run')::uuid       AS c_run_a,
         --: The four sections, kept individually so sections_moved can name the
         --: one that moved, and hashed together for the canon value.
         (p.j->'arm_a'->'endst'->'visit_needs'->'fgn')::text AS f_vn,
         (p.j->'arm_a'->'endst'->'bookings'->'fgn')::text    AS f_bk,
         (p.j->'arm_a'->'endst'->'legs'->'fgn')::text        AS f_lg,
         (p.j->'arm_a'->'endst'->'dispatches'->'fgn')::text  AS f_dp,
         CASE WHEN (p.j->'arm_a') ? 'endst' THEN md5(jsonb_build_object(
                'visit_needs', p.j->'arm_a'->'endst'->'visit_needs'->'fgn',
                'bookings',    p.j->'arm_a'->'endst'->'bookings'->'fgn',
                'legs',        p.j->'arm_a'->'endst'->'legs'->'fgn',
                'dispatches',  p.j->'arm_a'->'endst'->'dispatches'->'fgn')::text) END AS c_fgn
    FROM pair p
), col AS (
  --: Same exclusion as the matrix: an inconclusive pair is invisible, not red
  --: (db/checks/0193 finding 4). Stated here so the two instruments cannot
  --: disagree about which pairs exist.
  SELECT * FROM keyed WHERE st <> 'inconclusive'
), ranked AS (
  SELECT c.*, row_number() OVER (PARTITION BY c.c_depot, c.c_seed, c.c_ticks, c.c_scen
                                 ORDER BY c.t0 DESC, c.c_run_a DESC) AS rn
    FROM col c
), canon AS (
  SELECT rk.c_depot, rk.c_seed, rk.c_ticks, rk.c_scen, rk.c_fgn,
         rk.f_vn, rk.f_bk, rk.f_lg, rk.f_dp
    FROM ranked rk WHERE rk.rn = 1
), marked AS (
  SELECT r.c_depot, r.c_seed, r.c_ticks, r.c_scen, r.rn,
         (r.t0 >= fl.rf
          AND (r.c_fgn IS NULL OR k.c_fgn IS NULL OR r.c_fgn = k.c_fgn)) AS same,
         --: FLOOR-SCOPED, exactly as `same` is. Without the floor predicate a
         --: caller using the default 30-day p_since would have sections_moved
         --: report differences from pairs the streak cannot see -- an
         --: instrument disagreeing with itself about which pairs count.
         (r.t0 >= fl.rf AND r.f_vn IS DISTINCT FROM k.f_vn) AS m_vn,
         (r.t0 >= fl.rf AND r.f_bk IS DISTINCT FROM k.f_bk) AS m_bk,
         (r.t0 >= fl.rf AND r.f_lg IS DISTINCT FROM k.f_lg) AS m_lg,
         (r.t0 >= fl.rf AND r.f_dp IS DISTINCT FROM k.f_dp) AS m_dp
    FROM ranked r
    JOIN canon k ON k.c_depot = r.c_depot AND k.c_seed = r.c_seed
                AND k.c_ticks = r.c_ticks AND k.c_scen = r.c_scen
    CROSS JOIN fl
), streak AS (
  SELECT x.c_depot, x.c_seed, x.c_ticks, x.c_scen,
         count(*) FILTER (WHERE x.unbroken)::int AS n_same
    FROM (
      SELECT m.c_depot, m.c_seed, m.c_ticks, m.c_scen,
             bool_and(m.same) OVER (PARTITION BY m.c_depot, m.c_seed, m.c_ticks, m.c_scen
                                    ORDER BY m.rn
                                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS unbroken
        FROM marked m
    ) x
   GROUP BY x.c_depot, x.c_seed, x.c_ticks, x.c_scen
), moved AS (
  --: Which sections differ from the canon anywhere in the post-floor window.
  SELECT m.c_depot, m.c_seed, m.c_ticks, m.c_scen,
         NULLIF(concat_ws(',',
           CASE WHEN bool_or(m.m_vn) THEN 'visit_needs' END,
           CASE WHEN bool_or(m.m_bk) THEN 'bookings'    END,
           CASE WHEN bool_or(m.m_lg) THEN 'legs'        END,
           CASE WHEN bool_or(m.m_dp) THEN 'dispatches'  END), '') AS secs
    FROM marked m GROUP BY 1,2,3,4
), hist AS (
  SELECT c.c_depot, c.c_seed, c.c_ticks, c.c_scen,
         count(*)::int AS n_pairs
    FROM col c GROUP BY c.c_depot, c.c_seed, c.c_ticks, c.c_scen
), hstr AS (
  --: 'S' where this pair's foreign half equals the canon's, '.' where it does
  --: not -- oldest first, the same orientation as the matrix's history.
  SELECT m.c_depot, m.c_seed, m.c_ticks, m.c_scen,
         string_agg(CASE WHEN m.same THEN 'S' ELSE '.' END, '' ORDER BY m.rn DESC) AS h
    FROM marked m GROUP BY 1,2,3,4
)
SELECT h.c_depot, h.c_seed, h.c_ticks, h.c_scen, h.n_pairs,
       COALESCE(s.n_same, 0), l.t0, l.c_fgn, hs.h, fl.rf, mv.secs
  FROM hist h
  JOIN streak s ON s.c_depot=h.c_depot AND s.c_seed=h.c_seed AND s.c_ticks=h.c_ticks AND s.c_scen=h.c_scen
  JOIN hstr  hs ON hs.c_depot=h.c_depot AND hs.c_seed=h.c_seed AND hs.c_ticks=h.c_ticks AND hs.c_scen=h.c_scen
  JOIN moved mv ON mv.c_depot=h.c_depot AND mv.c_seed=h.c_seed AND mv.c_ticks=h.c_ticks AND mv.c_scen=h.c_scen
  JOIN ranked l ON l.c_depot=h.c_depot AND l.c_seed=h.c_seed AND l.c_ticks=h.c_ticks
               AND l.c_scen=h.c_scen AND l.rn = 1
  CROSS JOIN fl
 ORDER BY h.c_depot, h.c_ticks DESC, h.c_scen, h.c_seed;
$function$;

--: Granted to match ottoq_cert_matrix exactly -- same rows, same readers -- and
--: explicitly rather than by PostgreSQL's default EXECUTE-to-PUBLIC, so the
--: privilege is a decision in this file and not an omission. A7b asserts it.
REVOKE ALL ON FUNCTION public.ottoq_cert_residue(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_cert_residue(timestamptz)
   TO postgres, anon, authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_cert_residue(timestamptz) IS
'0266 (G46). The half of endst that ottoq_cert_matrix no longer streaks: the four fgn sections, which count OTHER runs'' rows left in live states at this depot. Its own canon, its own streak, its own history. A break here is a HYGIENE finding (G13''s janitor), not a determinism finding -- measured 2026-09-13, these sections are identical between arm_a and arm_b in 446 of 446 pairs, so they have never once been evidence about the engine. sections_moved names which of the four differ from the canon, so the finding is actionable. Read this beside ottoq_cert_matrix in every round report; neither number may be quoted as the other.';

-- ---------------------------------------------------------------------------
-- 3. LINEAGE. forces_recert = FALSE, and the reasoning has to survive being
--    read back hostilely, because a migration that RECOVERS streaks and
--    classifies itself as non-forcing is exactly the shape a self-serving
--    classification would take.
--
--    The test the lineage classification asks is whether a change can alter what
--    an arm PRODUCES. This one cannot: ottoq_determinism_pair is not modified
--    (A8 asserts its prosrc md5 is unchanged), ottoq_boot_state_fingerprint is
--    not modified (A8), no table, column, policy, or engine function is touched,
--    and the replaced function is STABLE, is called by no engine path, and reads
--    only ottoq_sim_runs.validation_notes. A recert floor exists to invalidate
--    canons that a behaviour change made meaningless; nothing here changed a
--    behaviour, so forcing one would discard nine columns of true history to no
--    purpose.
--
--    What it DOES change -- what the matrix compares -- is stated in the note and
--    in the COMMENT, and the streaks it recovers are measured in db/checks/0196
--    M5 and predicted there as P1 so they can be judged rather than asserted.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0266_the_canon_stops_being_hostage_to_another_runs_leftovers', false,
        'G46. ottoq_cert_matrix''s canon_endst becomes the run''s OWN end state (four vis sections + chargers + calibration + world); the four fgn sections move to the new ottoq_cert_residue with their own canon and streak. ottoq_determinism_pair is NOT modified and still enforces endst whole, so no arm''s output can change and nothing enforced became invisible. Non-forcing because nothing an arm produces can differ; the change is to how a STABLE reporting function groups what is already recorded. Measured effect on the existing history: db/checks/0196 M5.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ---------------------------------------------------------------------------
-- 4. ASSERTIONS. Every one refuses the migration rather than warning.
-- ---------------------------------------------------------------------------
DO $a$
DECLARE
  v_rf timestamptz; v_n int; v_bad int; v_txt text;
BEGIN
  v_rf := public.ottoq_cert_recert_floor();

  --: A1. THE RECERT FLOOR DID NOT MOVE. The lineage row is non-forcing, so the
  --:     floor must be exactly where it was before this file ran. If this fails
  --:     the classification in section 3 is wrong and every streak below is
  --:     measured against the wrong baseline.
  IF v_rf <> '2026-09-12 16:50:23.319089+00'::timestamptz THEN
    RAISE EXCEPTION '0266 A1: recert floor moved to % (expected 2026-09-12 16:50:23.319089+00)', v_rf;
  END IF;

  --: A2. THE POSITIVE CONTROL, and the one that would catch a typo'd key name.
  --:     canon_endst must be NON-NULL on every post-floor column. A misspelled
  --:     path (say 'vis ' or 'visitneeds') still produces a valid md5 of an
  --:     object full of JSON nulls -- identical for every pair -- which would
  --:     make every column green for the wrong reason and pass A3 and A4. So
  --:     A2 checks the digest is not the digest of an all-null object.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_matrix(v_rf) WHERE canon_endst IS NULL;
  IF v_n > 0 THEN
    RAISE EXCEPTION '0266 A2: % post-floor column(s) have a NULL canon_endst', v_n;
  END IF;
  v_txt := md5(jsonb_build_object('visit_needs', NULL::jsonb, 'bookings', NULL::jsonb,
                                  'legs', NULL::jsonb, 'dispatches', NULL::jsonb,
                                  'chargers', NULL::jsonb, 'calibration', NULL::jsonb,
                                  'world', NULL::jsonb)::text);
  SELECT count(*) INTO v_bad FROM public.ottoq_cert_matrix(v_rf) WHERE canon_endst = v_txt;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A2: % column(s) digest an all-null object -- a key path is misspelled', v_bad;
  END IF;

  --: A3. THE GRID COLUMNS DO NOT MOVE. This is the control that separates a
  --:     targeted fix from a blanket weakening: the grid depot has no other runs
  --:     leaving residue in it, so its streaks must be exactly what they were
  --:     (3 each, measured 0196 M5). If the split made things green generally,
  --:     these would move too.
  SELECT count(*) INTO v_bad FROM public.ottoq_cert_matrix(v_rf)
   WHERE depot = 'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid
     AND (consecutive_passes <> 3 OR pairs_seen <> 3 OR NOT green);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A3: % grid column(s) moved; the split is not targeted', v_bad;
  END IF;

  --: A4. PREDICTION P1 OF db/checks/0196, asserted rather than hoped: every
  --:     post-floor column's streak now equals its pair count.
  SELECT count(*) INTO v_bad FROM public.ottoq_cert_matrix(v_rf)
   WHERE consecutive_passes <> pairs_seen;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A4: % column(s) still short of their pair count', v_bad;
  END IF;

  --: A5. THE RESIDUE INSTRUMENT COVERS EXACTLY THE SAME COLUMNS. The failure
  --:     0193 finding 4 warned about is an instrument that goes quiet while
  --:     another keeps reporting. If these two ever disagree about which columns
  --:     exist, one of them is hiding a column.
  SELECT count(*) INTO v_bad FROM (
    SELECT depot, seed, ticks, scenario FROM public.ottoq_cert_matrix(v_rf)
    EXCEPT
    SELECT depot, seed, ticks, scenario FROM public.ottoq_cert_residue(v_rf)) x;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A5: % column(s) in the matrix and not in the residue instrument', v_bad;
  END IF;
  SELECT count(*) INTO v_bad FROM (
    SELECT depot, seed, ticks, scenario FROM public.ottoq_cert_residue(v_rf)
    EXCEPT
    SELECT depot, seed, ticks, scenario FROM public.ottoq_cert_matrix(v_rf)) x;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A5: % column(s) in the residue instrument and not in the matrix', v_bad;
  END IF;

  --: A6. THE RESIDUE INSTRUMENT STILL SEES THE THING THAT WAS LOST. Prediction
  --:     P2: the flagship columns must show the fgn break round 41 surfaced, and
  --:     name `legs` as the section that moved. An instrument that reported
  --:     everything stable would mean the hygiene fact was dropped, not
  --:     relocated -- which is the only way this migration could be dishonest.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_residue(v_rf)
   WHERE depot = '11111111-1111-1111-1111-111111111111'::uuid
     AND sections_moved = 'legs';
  IF v_n < 7 THEN
    RAISE EXCEPTION '0266 A6: only % flagship column(s) report the legs residue move (expected 7); the hygiene fact was dropped, not relocated', v_n;
  END IF;

  --: A7. PRIVILEGES UNCHANGED on the replaced function, pinned to the ACL
  --:     measured in the pre-image rather than to another function's. CREATE OR
  --:     REPLACE preserves proacl by definition; this asserts the definition
  --:     held, which is the only thing worth checking.
  SELECT array_to_string(p.proacl::text[], ' | ') INTO v_txt
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';
  IF v_txt IS DISTINCT FROM '=X/postgres | postgres=X/postgres | anon=X/postgres | authenticated=X/postgres | service_role=X/postgres' THEN
    RAISE EXCEPTION '0266 A7: ottoq_cert_matrix privileges changed to %', COALESCE(v_txt, '(default)');
  END IF;

  --: A7b. AND THE NEW FUNCTION IS GRANTED DELIBERATELY, not by PostgreSQL's
  --:      default of EXECUTE-to-PUBLIC. It is a reporting read over the same
  --:      rows ottoq_cert_matrix already exposes to the same roles, so it gets
  --:      the same grants and no more -- stated here because a new function
  --:      that inherits a default grant is a privilege decision nobody made.
  SELECT array_to_string(p.proacl::text[], ' | ') INTO v_txt
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_residue';
  IF v_txt IS NULL OR position('service_role=X' in v_txt) = 0 THEN
    RAISE EXCEPTION '0266 A7b: ottoq_cert_residue has no explicit grant (proacl %)', COALESCE(v_txt, '(default)');
  END IF;

  --: A8. THE ENGINE DID NOT MOVE. The two functions this migration must not
  --:     touch, pinned by content. ottoq_determinism_pair's md5 is the standing
  --:     pin; the boot fingerprint is what it calls.
  SELECT count(*) INTO v_bad FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair'
     AND md5(p.prosrc) <> '8a35b8c874fed154cc216140faec0274';
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A8: ottoq_determinism_pair moved; this migration must not touch it';
  END IF;
  SELECT count(*) INTO v_bad FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_boot_state_fingerprint'
     AND md5(p.prosrc) <> '90d490c24ae084d03477a8a782a9f856';
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A8: ottoq_boot_state_fingerprint moved; this migration must not touch it';
  END IF;

  --: A9. THE COMPARISON IS NOT NARROWER THAN THE ENFORCEMENT (G25/G28). The two
  --:     digests together must cover every leaf the pair enforces: for every
  --:     post-floor pair, own-digest AND fgn-digest equal between the arms iff
  --:     endst is equal between the arms. Checked on the real recorded pairs
  --:     rather than argued from the construction.
  SELECT count(*) INTO v_bad FROM (
    SELECT (r.validation_notes::jsonb) AS j FROM public.ottoq_sim_runs r
     WHERE r.run_by='cert_harness' AND r.started_at >= v_rf
       AND r.validation_notes IS NOT NULL
       AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
       AND (r.validation_notes::jsonb)->'arm_a' ? 'endst') q
   WHERE ((q.j->'arm_a'->'endst') = (q.j->'arm_b'->'endst'))
      <> ( md5(jsonb_build_object(
             'visit_needs', q.j->'arm_a'->'endst'->'visit_needs'->'vis',
             'bookings',    q.j->'arm_a'->'endst'->'bookings'->'vis',
             'legs',        q.j->'arm_a'->'endst'->'legs'->'vis',
             'dispatches',  q.j->'arm_a'->'endst'->'dispatches'->'vis',
             'chargers',    q.j->'arm_a'->'endst'->'chargers',
             'calibration', q.j->'arm_a'->'endst'->'calibration',
             'world',       q.j->'arm_a'->'endst'->'world')::text)
           = md5(jsonb_build_object(
             'visit_needs', q.j->'arm_b'->'endst'->'visit_needs'->'vis',
             'bookings',    q.j->'arm_b'->'endst'->'bookings'->'vis',
             'legs',        q.j->'arm_b'->'endst'->'legs'->'vis',
             'dispatches',  q.j->'arm_b'->'endst'->'dispatches'->'vis',
             'chargers',    q.j->'arm_b'->'endst'->'chargers',
             'calibration', q.j->'arm_b'->'endst'->'calibration',
             'world',       q.j->'arm_b'->'endst'->'world')::text)
         AND md5(jsonb_build_object(
             'visit_needs', q.j->'arm_a'->'endst'->'visit_needs'->'fgn',
             'bookings',    q.j->'arm_a'->'endst'->'bookings'->'fgn',
             'legs',        q.j->'arm_a'->'endst'->'legs'->'fgn',
             'dispatches',  q.j->'arm_a'->'endst'->'dispatches'->'fgn')::text)
           = md5(jsonb_build_object(
             'visit_needs', q.j->'arm_b'->'endst'->'visit_needs'->'fgn',
             'bookings',    q.j->'arm_b'->'endst'->'bookings'->'fgn',
             'legs',        q.j->'arm_b'->'endst'->'legs'->'fgn',
             'dispatches',  q.j->'arm_b'->'endst'->'dispatches'->'fgn')::text) );
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A9: on % pair(s) the two digests together do not decide endst equality; the split loses a leaf', v_bad;
  END IF;

  --: A10. G48: THE REPLAY PREDICATE EXCLUDES REPLAYS AND KEEPS THE CONTROLS.
  --:      Run over a WIDE window on purpose. All nine existing replay pairs
  --:      predate the recert floor -- that coincidence is the only thing
  --:      protecting today's canon -- so an assertion scoped to the floor would
  --:      examine zero replay pairs and pass vacuously, which is exactly the
  --:      failure this file must not ship.
  --:
  --:      TWO NUMBERS, and the second is the one that matters. Excluding 7 is
  --:      easy; KEEPING the 2 zero-injection controls is what a near-miss
  --:      predicate gets wrong. `replay` is present with a NULL VALUE on a
  --:      control, so `NOT (notes ? 'replay')` would drop honest certification
  --:      data and this assertion would catch it.
  SELECT count(*) FILTER (WHERE NOT ((j->>'replay') IS NULL
                            AND COALESCE((j->'arm_a'->>'replay_injected')::int, 0) = 0
                            AND COALESCE((j->'arm_b'->>'replay_injected')::int, 0) = 0)),
         count(*) FILTER (WHERE (j ? 'replay') AND (j->>'replay') IS NULL
                            AND COALESCE((j->'arm_a'->>'replay_injected')::int, 0) = 0
                            AND COALESCE((j->'arm_b'->>'replay_injected')::int, 0) = 0)
    INTO v_n, v_bad
    FROM (SELECT DISTINCT ON (r.depot_id, r.started_at) (r.validation_notes::jsonb) AS j
            FROM public.ottoq_sim_runs r
           WHERE r.run_by='cert_harness' AND r.validation_notes IS NOT NULL
             AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
           ORDER BY r.depot_id, r.started_at, r.sim_run_id) q;
  IF v_n <> 7 THEN
    RAISE EXCEPTION '0266 A10: predicate excludes % pair(s), expected the 7 injected replays', v_n;
  END IF;
  IF v_bad <> 2 THEN
    RAISE EXCEPTION '0266 A10: % zero-injection control pair(s) survive, expected 2; the predicate is dropping honest certification data', v_bad;
  END IF;

  --: A10b. AND THE INSTRUMENT AGREES WITH THE PREDICATE. The matrix's own pair
  --:       count over the same wide window must equal the non-inconclusive pairs
  --:       that pass the predicate -- so the clause is actually in the body and
  --:       not merely in a comment.
  SELECT count(*) INTO v_n
    FROM (SELECT DISTINCT ON (r.depot_id, r.started_at) r.validation_status AS vs,
                 (r.validation_notes::jsonb) AS j
            FROM public.ottoq_sim_runs r
           WHERE r.run_by='cert_harness' AND r.validation_notes IS NOT NULL
             AND r.validation_status IS NOT NULL
             AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
             AND r.started_at >= '2000-01-01'::timestamptz
           ORDER BY r.depot_id, r.started_at, r.sim_run_id) q
   WHERE q.vs <> 'inconclusive'
     AND (q.j->>'replay') IS NULL
     AND COALESCE((q.j->'arm_a'->>'replay_injected')::int, 0) = 0
     AND COALESCE((q.j->'arm_b'->>'replay_injected')::int, 0) = 0;
  SELECT COALESCE(sum(pairs_seen), 0) INTO v_bad
    FROM public.ottoq_cert_matrix('2000-01-01'::timestamptz);
  IF v_n <> v_bad THEN
    RAISE EXCEPTION '0266 A10b: matrix reports % pairs, the predicate admits %', v_bad, v_n;
  END IF;

  RAISE NOTICE '0266: A1-A10b passed; recert floor unmoved at %', v_rf;
END $a$;

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- (not yet applied)
-- ---------------------------------------------------------------------------
