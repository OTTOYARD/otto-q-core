-- migration-version: 20260913135634
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
--   M2  The fgn sections are identical between arm_a and arm_b in 445 of 446
--       pairs -- bookings.fgn differs in exactly one, a pre-0139 pair; legs,
--       visit_needs and dispatches differ in zero. They contribute essentially
--       nothing to the intra-pair verdict and all of G46's noise to the
--       inter-round one. (An earlier draft rounded this to "446 of 446" in three
--       places, one of which shipped into the database as a function COMMENT.)
--   M3  There are ZERO rows with a NULL sim_run_id in any of the four tables,
--       database-wide, so the `vis` branch is in fact `sim_run_id = p_run`.
--       THIS IS AN OBSERVATION, NOT A GUARANTEE -- 0196 M3 says so and an earlier
--       draft of this bullet dropped the caveat. Measured: legs and bookings are
--       NOT NULL in the schema; visit_needs and dispatches are NULLABLE. A future
--       writer can reintroduce an untagged row, it would land in `vis`, and it
--       would rebase the canon exactly as the nine legs did. db/checks/0198 C4
--       counts untagged rows for that reason.
--   M4  The canon digest is formed in ONE line of ottoq_cert_matrix, from the
--       endst object the pair already recorded. So the split is computable from
--       data already on disk: it is RETROACTIVE and re-runs nothing.
--   M5  Applying the split to the real history: every flagship column becomes
--       unbroken back to the floor, and BOTH GRID COLUMNS DO NOT MOVE. The grid
--       depot has no other runs leaving residue in it; if this were a blanket
--       weakening the grid numbers would have moved too.
--
-- WHY THERE IS NO GATE. Both designs reviewed in db/checks/0193 were admissibility
-- gates on the boot image, and both came back unsound. Blockers (ii) and (iii)
-- are void here BY CONSTRUCTION, because nothing is gated: there is no
-- admissibility predicate (so not two definitions of one), no `c_fgn = 0` to fail
-- open on NULL, no GREATEST to swallow a NULL, no boot fingerprint in
-- ottoq_cert_coverage and therefore none of its 8.2 s (the 0098 class), and the
-- metronome firing every minute cannot stall a column because no column waits on
-- the boot image.
--
-- BLOCKER (i) IS NOT VOID, AND AN EARLIER DRAFT OF THIS PARAGRAPH SAID IT WAS.
-- (i) held that the run's own digest is not residue-independent because it hashes
-- run-UNTAGGED state. 0196 M3 answers that for the four row-sections (there are no
-- untagged rows anywhere) and says so as an OBSERVATION. It does NOT answer it for
-- chargers, calibration and world, which have no run filter at all and which this
-- split KEEPS inside c_endst.
--
-- Measured over 30 days rather than the 11-hour post-floor window M1 uses, the
-- untagged half is the MORE volatile one, not the quietest:
--
--     column (flagship)      chargers   calibration   world   legs.fgn
--     314159/12t busy_day      15            1          2        6
--     171717/12t normal_day    12            1          2        6
--     171717/24t busy_day      14            1          2        6
--     171717/48t busy_day       5            1          7        4
--
-- `chargers` hashes ottoq_ocpp_chargers at the depot including station_state and
-- last_heartbeat_at, which the metronome moves every minute, so another run's
-- activity rebases the canon through a door this split does not close. It did not
-- show in M1 only because all 30 post-floor pairs fell inside one quiet window.
--
-- THE SPLIT IS STILL THE RIGHT CUT -- charger and world state is what the run
-- ENDED IN and belongs to its own end state, and 0244 put `world` there
-- deliberately so two arms ending in different fleet states could not pass. What
-- changes is the claim and the watch: (i) survives, it is named here rather than
-- declared void, and db/checks/0198 C4 makes a rebase through that door
-- attributable instead of mysterious.
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
-- replaced one (A7 asserts proacl is unchanged; A6 is the residue check). The
-- replaced function keeps its
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
  --: TWO BRANCHES WITH DELIBERATELY DIFFERENT SEMANTICS, and the asymmetry is
  --: the point rather than an oversight.
  --:
  --: ROUND JOBS: EXISTENCE, not activeness -- which is 0221's semantics, copied
  --: as APPLYING.md requires. An earlier draft of this block wrote
  --: `WHERE active AND (...)` to cover the second branch and thereby NARROWED
  --: the first one it had copied. A round paused mid-flight for investigation
  --: (cron.alter_job(..., active := false)) leaves its r<N>_* jobs present but
  --: inactive: scripts/schedule-round.sql refuses to schedule over exactly that
  --: state, and the narrowed predicate would have applied straight through it.
  --: A migration that walks past a paused round is the thing this block exists
  --: to prevent.
  --:
  --: THE CERT BATTERY: activeness, because it is a STANDING job (jobid 13,
  --: '* * * * *') that is disabled rather than deleted when not in use, so
  --: existence alone would refuse every migration forever. Matching on the
  --: COMMAND rather than the name also means a certification path added later
  --: is covered without anyone remembering to widen a regex.
  SELECT count(*) INTO v_jobs FROM cron.job
   WHERE (jobname ~ '^r[0-9]+_')
      OR (active AND (command ILIKE '%ottoq_determinism_pair%'
                      OR command ILIKE '%ottoq_cert_battery_step%'));
  IF v_jobs > 0 THEN
    RAISE EXCEPTION '0266 P: % certification job(s) still scheduled', v_jobs;
  END IF;
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_live > 0 THEN
    RAISE EXCEPTION '0266 P: % run(s) running or paused', v_live;
  END IF;
END $p$;

-- ---------------------------------------------------------------------------
-- S. PRE-IMAGE, PRINTED. Its earlier comment claimed it was "recorded so the
--    APPLY LOG can show exactly what moved", which is not what it does: applied
--    through apply_migration (APPLYING.md 4a) or `supabase db push` (4b) a bare
--    SELECT's result set is discarded and reaches no log at all.
--    It is kept because it is useful to a HUMAN running this file by hand, and
--    it is now honest about being only that. The durable record is S2's
--    ottoq_schema_snapshots row; the guard that actually refuses a moved body is
--    section G. Both were added after review found the file had neither.
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
-- G. THE MD5 GUARD AND THE PRE-IMAGE SNAPSHOT (scripts/APPLYING.md step 2).
--    ADDED AFTER REVIEW. The first draft had NEITHER for the one function it
--    replaces, and the review was right to call that a blocker: section S was a
--    bare SELECT whose result apply_migration discards, with the expected digest
--    living only in a hand-written comment, and A8 pinned md5 on the two
--    functions this file must NOT touch while leaving the one it DOES touch
--    unpinned -- and A8 runs AFTER the replace in any case.
--
--    What that combination costs, concretely: if anyone hotfixes
--    ottoq_cert_matrix in the SQL editor between the moment these digests were
--    measured and the moment this file runs, CREATE OR REPLACE silently deletes
--    their fix and there is no snapshot row to recover the body from. That is
--    exactly the scenario APPLYING.md's step 2 exists for, and 0261, 0265 and
--    db/migrations/0001_EXAMPLE_template.sql all carry both halves.
-- ---------------------------------------------------------------------------
DO $g$
DECLARE v_src text; v_def text; v_len int; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cert_matrix';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0266 G: expected exactly 1 ottoq_cert_matrix, found % -- an overload would make the replace ambiguous', v_n;
  END IF;
  SELECT p.prosrc, md5(pg_get_functiondef(p.oid)), length(p.prosrc)
    INTO v_src, v_def, v_len
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cert_matrix'
     AND pg_get_function_identity_arguments(p.oid) = 'p_since timestamp with time zone';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0266 G: no ottoq_cert_matrix(timestamptz) -- the signature this file replaces does not exist';
  END IF;
  IF md5(v_src) <> 'f5bb81931feae44871c3ecd86d4f86b4' THEN
    RAISE EXCEPTION '0266 G: ottoq_cert_matrix prosrc md5 is %, expected f5bb81931feae44871c3ecd86d4f86b4 -- the body moved since this file was written; re-derive the copy before replacing it', md5(v_src);
  END IF;
  IF v_def <> '4c00ae1ae666230eb286c7fd864a0717' THEN
    RAISE EXCEPTION '0266 G: ottoq_cert_matrix functiondef md5 is %, expected 4c00ae1ae666230eb286c7fd864a0717', v_def;
  END IF;
  IF v_len <> 5934 THEN
    RAISE EXCEPTION '0266 G: ottoq_cert_matrix prosrc length is %, expected 5934', v_len;
  END IF;
  --: The new function must NOT already exist: this file creates it, and a
  --: CREATE OR REPLACE over someone else's ottoq_cert_residue would be the same
  --: silent overwrite the guard above exists to prevent.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cert_residue';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0266 G: ottoq_cert_residue already exists (% row(s)); this file creates it', v_n;
  END IF;
END $g$;

-- ---------------------------------------------------------------------------
-- S2. THE PRE-IMAGE SNAPSHOT ITSELF (APPLYING.md step 2). Section S above prints
--     the digests for the APPLY LOG; THIS is the row a later reader recovers the
--     body from. The two functions this file must not touch are snapshotted
--     alongside, because A8 pins them and a reader needs the version pinned.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0266-pre', 'function', 'public',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_cert_matrix', 'ottoq_determinism_pair', 'ottoq_boot_state_fingerprint');

-- ---------------------------------------------------------------------------
-- 1. THE MATRIX. TWO changes from the live body, and the header used to claim
--    one -- which is the 0228 defect class (a header asserting something the
--    body does not do) in the section a reviewer is most likely to skim:
--      (a) the c_endst expression in `keyed` and its comment  [G46, the split]
--      (b) two WHERE clauses in the `pair` CTE and their comment  [G48, replay]
--    Everything else -- the key, inc, col, ranked, canon, marked, streak, hist,
--    the final SELECT and its ORDER BY -- is copied verbatim from
--    pg_get_functiondef, and A4 pins all thirteen canon conjuncts against the
--    POST-IMAGE body so a conjunct dropped during the copy cannot pass silently.
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
            VISIBLE here: the four `vis` halves (this run's own rows -- measured
            M3, there are no untagged rows anywhere TODAY, which is an
            observation and not a schema guarantee: visit_needs and dispatches
            are still nullable, and db/checks/0198 C4 watches the count) plus the three world keys the run genuinely
            ended in.
            AND THE COST OF THAT CHOICE, STATED RATHER THAN GLOSSED. An earlier
            draft of this comment claimed the explicit list "cannot drift with
            the fingerprint's shape". That is exactly backwards, and the review
            caught it: the OLD opaque md5 over the whole object covered every key
            BY CONSTRUCTION and could not drift; an enumerated list is precisely
            what drifts. If ottoq_boot_state_fingerprint ever gains an eighth
            top-level key, that atom is streaked by NEITHER instrument and
            silently leaves the canon -- and A9's arm-vs-arm shape check cannot
            see it either, because the arms agree on every fgn section in 445 of 446 pairs
            and on endst as a whole in 30 of 30 post-floor pairs, so
            a key that is equal WITHIN a pair but moves BETWEEN rounds is G46's
            own failure class wearing a new name.
            The blind spot is therefore closed deliberately and in two places:
            A9 refuses this migration unless endst is exactly these seven keys
            with exactly {vis,fgn} beneath the four sections, and
            db/checks/0198 registers the same assertion as a standing check,
            scripts/round-report.sql §3 inlines it so the round report cannot be
            produced without evaluating it, and
            tests/test_endst_split_key_lists_agree.py holds the three COMMITTED
            key lists together in CI. What none of those reaches is the
            fingerprint function itself, which lives only in the database -- that
            corner is discipline until G12 ("CI runs the SQL") lands, and it is
            named rather than papered over.
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
         (r.t0 >= fl.rf) AS above_floor,
         --: The equality alone, floor-free, so `history` can report it honestly
         --: at any p_since while the STREAK stays floor-scoped.
         (r.c_fgn IS NULL OR k.c_fgn IS NULL OR r.c_fgn = k.c_fgn) AS fgn_same,
         (r.t0 >= fl.rf
          AND (r.c_fgn IS NULL OR k.c_fgn IS NULL OR r.c_fgn = k.c_fgn)) AS same,
         --: FLOOR-SCOPED, exactly as `same` is. Without the floor predicate a
         --: caller using the default 30-day p_since would have sections_moved
         --: report differences from pairs the streak cannot see -- an
         --: instrument disagreeing with itself about which pairs count.
         --: AND NULL-GUARDED, exactly as `same` is. `IS DISTINCT FROM` alone
         --: would call a missing section "moved" while `same` called the same
         --: pair matching -- one instrument disagreeing with itself about how to
         --: treat `unknown`, which is the NULL asymmetry db/checks/0193 (iii)
         --: convicted the previous designs for. Unreachable today (A2 proves
         --: every post-floor pair carries all seven paths) and guarded anyway.
         (r.t0 >= fl.rf AND r.f_vn IS NOT NULL AND k.f_vn IS NOT NULL AND r.f_vn <> k.f_vn) AS m_vn,
         (r.t0 >= fl.rf AND r.f_bk IS NOT NULL AND k.f_bk IS NOT NULL AND r.f_bk <> k.f_bk) AS m_bk,
         (r.t0 >= fl.rf AND r.f_lg IS NOT NULL AND k.f_lg IS NOT NULL AND r.f_lg <> k.f_lg) AS m_lg,
         (r.t0 >= fl.rf AND r.f_dp IS NOT NULL AND k.f_dp IS NOT NULL AND r.f_dp <> k.f_dp) AS m_dp
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
  --: THREE STATES, oldest first (the same orientation as the matrix's history).
  --:   'S' this pair's foreign half equals the canon's
  --:   '.' it does not -- the foreign residue moved
  --:   '-' the pair is BELOW the recert floor, so it is not judged at all
  --: The '-' is not cosmetic. `same` is floor-scoped (it must be: the streak is),
  --: so an earlier draft rendered every pre-floor pair as '.', i.e. as MOVED.
  --: Measured by the review at the function's own default p_since of 30 days:
  --: grid column 424242/6t rendered '.................SSS' where the truth is
  --: twenty S's -- seventeen false claims of movement on a column whose foreign
  --: half has never moved, in the instrument whose whole job is to say when it
  --: does. The glyph now reports fgn equality alone and the floor gets its own
  --: mark, so the string is true at every p_since a caller may pass.
  SELECT m.c_depot, m.c_seed, m.c_ticks, m.c_scen,
         string_agg(CASE WHEN NOT m.above_floor THEN '-'
                         WHEN m.fgn_same       THEN 'S'
                         ELSE '.' END, '' ORDER BY m.rn DESC) AS h
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

--: Granted EXPLICITLY rather than by PostgreSQL's default EXECUTE-to-PUBLIC, so
--: the privilege is a decision in this file and not an omission.
--: DELIBERATELY NOT IDENTICAL to ottoq_cert_matrix's, and an earlier draft of
--: this comment wrongly said it was: the matrix's ACL carries a leading
--: `=X/postgres`, which IS the PUBLIC grant, for historical reasons. The residue
--: revokes PUBLIC and names the four roles. Same rows, one fewer grantee -- the
--: safer direction, and A7b pins the exact string rather than merely checking
--: the ACL is non-empty (which would still pass with PUBLIC holding EXECUTE).
REVOKE ALL ON FUNCTION public.ottoq_cert_residue(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_cert_residue(timestamptz)
   TO postgres, anon, authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_cert_residue(timestamptz) IS
'0266 (G46). The half of endst that ottoq_cert_matrix no longer streaks: the four fgn sections, which count OTHER runs'' rows left in live states at this depot. Its own canon, its own streak, its own history. A break here is a hygiene finding OR a change in the engine''s own cleanup, reset or supersede path -- it is NOT attributable to the janitor by itself, and an earlier version of this comment said it was. The engine demonstrably touches foreign live rows (db/checks/0187 §4: four legs that vanished between rounds 40 and 41 were closed by a later run''s supersede), so a future widening of ottoq_tick_invariance_reset_fleet or ottoq_sim_release_depot to retire foreign rows would land HERE while both arms still agreed and the pair still passed. Before charging a residue break to the janitor, check whether any migration since the last round touched those paths. What IS measured: these sections are identical between arm_a and arm_b in 445 of 446 pairs (bookings.fgn differs in one pre-0139 pair), so they are close to worthless as evidence about INTRA-PAIR determinism. sections_moved names which of the four differ from the canon, so the finding is actionable. Read this beside ottoq_cert_matrix in every round report -- scripts/round-report.sql prints both plus the shape check, and exists because a review found this sentence was relying on a report that had no carrier anywhere in the repo. Neither number may be quoted as the other.';

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
--
--    REWRITTEN 2026-09-13 AFTER AN ADVERSARIAL REVIEW CONVICTED THE FIRST SET.
--    The review (db/checks/0197) found that three of the four assertions
--    carrying this file's central honesty claims could not fail, and it proved
--    each one by simulation rather than by argument. The specific convictions,
--    kept here because the replacements only make sense against them:
--
--      A9 was a TAUTOLOGY. It asserted
--         (arm_a.endst = arm_b.endst) <> (own_eq AND fgn_eq)
--      and every post-floor pair has arm_a.endst = arm_b.endst (measured: 60 of
--      60 rows), so the left side is constantly TRUE; whole-object equality
--      trivially implies both digests equal, so the right side is constantly
--      TRUE. The reviewer replaced the entire right-hand side with a constant
--      compared to itself, reading nothing from the pair at all, and it still
--      returned zero. It also never called either function -- it retyped both
--      expressions -- so a typo in the SHIPPED body was invisible to it.
--
--      A2 WAS NOT THE POSITIVE CONTROL IT CLAIMED. Its own comment named the
--      defect ("a misspelled path still produces a valid md5 of an object full
--      of JSON nulls") and then guarded only the case where ALL SEVEN paths are
--      wrong at once. One misspelled path yields six real values and one JSON
--      null, whose digest is neither NULL nor the all-null constant: measured,
--      0 of 30 pairs caught, and 9 distinct digests -- indistinguishable from
--      correct by any count.
--
--      A3 AND A4 COULD NOT TELL THE SPLIT FROM DELETING endst ENTIRELY. The
--      grid columns were already at their ceiling (3 of 3, green) before this
--      file, so no weakening of any kind can move them upward; and A4 asserted
--      greenness, which is the outcome the rewrite was built to produce. The
--      reviewer simulated the maximal weakening -- the whole endst conjunct
--      deleted from `marked`, no split at all -- and got a3_would_fire = 0,
--      a4_would_fire = 0.
--
--    The replacements below assert SHAPE, ATTRIBUTABILITY and the SHIPPED BODY,
--    which are falsifiable on today's data, instead of equalities that are
--    constantly true.
-- ---------------------------------------------------------------------------
DO $a$
DECLARE
  v_rf timestamptz; v_n int; v_bad int; v_worse int; v_txt text; v_src text;
  --: A3b's spoiler. DECLARED, because the first draft of A3b wrote it as a
  --: bare literal that Python's implicit string concatenation had silently
  --: stripped the quotes from -- `to_jsonb(v_sentinel)` is a
  --: COLUMN REFERENCE, so the whole DO block would have raised 42703 at
  --: apply time, after seven assertions had already run, with an error
  --: naming a missing column rather than a failed check. Caught by a
  --: reviewer's live probe, not by me.
  v_sentinel text := '__0266_sentinel__';
  v_conj text;
  v_conjuncts text[] := ARRAY[
    'r.c_fp  IS NOT DISTINCT FROM k.c_fp',
    'r.c_cmd IS NOT DISTINCT FROM k.c_cmd',
    'r.c_dec IS NOT DISTINCT FROM k.c_dec',
    'r.c_evt IS NOT DISTINCT FROM k.c_evt',
    'r.c_bkg IS NOT DISTINCT FROM k.c_bkg',
    'r.c_nrg IS NOT DISTINCT FROM k.c_nrg',
    '(r.c_prop IS NULL OR k.c_prop IS NULL OR r.c_prop = k.c_prop)',
    '(r.c_defr IS NULL OR k.c_defr IS NULL OR r.c_defr = k.c_defr)',
    '(r.c_cal  IS NULL OR k.c_cal  IS NULL OR r.c_cal  = k.c_cal)',
    '(r.c_rule  IS NULL OR k.c_rule  IS NULL OR r.c_rule  = k.c_rule)',
    '(r.c_rcl   IS NULL OR k.c_rcl   IS NULL OR r.c_rcl   = k.c_rcl)',
    '(r.c_sdr   IS NULL OR k.c_sdr   IS NULL OR r.c_sdr   = k.c_sdr)',
    '(r.c_endst IS NULL OR k.c_endst IS NULL OR r.c_endst = k.c_endst)'];
BEGIN
  v_rf := public.ottoq_cert_recert_floor();

  --: A0. ANTI-VACUITY, FIRST, because the review found that A2, A4 and A5 all
  --:     pass on an EMPTY matrix. An assertion suite whose subject can be the
  --:     empty set is not a suite. Nine columns exist today; fewer than nine
  --:     means the instrument lost one and every count below is measured over
  --:     the wrong population.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_matrix(v_rf);
  IF v_n <> 9 THEN
    RAISE EXCEPTION '0266 A0: matrix returns % post-floor column(s), expected 9', v_n;
  END IF;

  --: A1. THE RECERT FLOOR DID NOT MOVE. The lineage row is non-forcing, so the
  --:     floor must be exactly where it was before this file ran. If this fails
  --:     the classification in section 3 is wrong and every streak below is
  --:     measured against the wrong baseline.
  IF v_rf <> '2026-09-12 16:50:23.319089+00'::timestamptz THEN
    RAISE EXCEPTION '0266 A1: recert floor moved to % (expected 2026-09-12 16:50:23.319089+00)', v_rf;
  END IF;

  --: A2. THE REAL POSITIVE CONTROL: PER-PATH, NOT PER-DIGEST. Every one of the
  --:     seven jsonb paths the split enumerates must EXTRACT SOMETHING on every
  --:     post-floor pair. This fires on exactly ONE misspelled path, which is
  --:     the failure the old A2 described and did not catch. Verified both ways
  --:     before installing: with the paths correct, 0 of 60 arm rows (30 pairs)
  --:     violate it; with `->'vis'` misspelled as `->'viss'` on visit_needs
  --:     alone, 60 of 60 violate it. SIXTY, not thirty: neither subquery has a
  --:     DISTINCT ON, so both walk arm ROWS. Harmless to the verdict (both arms
  --:     carry the same validation_notes) and mislabelled until a reviewer said
  --:     so, in the same file that added "the denominator, carried on every row"
  --:     to db/checks/0198.
  SELECT count(*) INTO v_bad FROM (
    SELECT (r.validation_notes::jsonb)->'arm_a'->'endst' AS e
      FROM public.ottoq_sim_runs r
     WHERE r.run_by='cert_harness' AND r.validation_notes IS NOT NULL
       AND r.validation_status IS NOT NULL
       AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
       AND r.started_at >= v_rf
       --: THE SAME G48 PREDICATE THE SHIPPED BODIES USE. Without it these two
       --: assertions walk a population the canon does not, and they depend on
       --: the very coincidence A10's comment says must not be depended on --
       --: that all nine replay pairs happen to predate the floor. Costs nothing
       --: today (measured: the same 60 rows) and removes the dependency.
       AND (r.validation_notes::jsonb ->> 'replay') IS NULL
       AND COALESCE((r.validation_notes::jsonb->'arm_a'->>'replay_injected')::int, 0) = 0
       AND COALESCE((r.validation_notes::jsonb->'arm_b'->>'replay_injected')::int, 0) = 0) q
   WHERE (q.e->'visit_needs'->'vis') IS NULL OR (q.e->'bookings'->'vis') IS NULL
      OR (q.e->'legs'->'vis') IS NULL       OR (q.e->'dispatches'->'vis') IS NULL
      OR (q.e->'chargers') IS NULL          OR (q.e->'calibration') IS NULL
      OR (q.e->'world') IS NULL;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A2: % post-floor pair(s) have a NULL at one of the seven split paths -- a key is misspelled or the fingerprint shape moved', v_bad;
  END IF;
  --: The second net, kept: all seven wrong at once still produces a valid digest.
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
    RAISE EXCEPTION '0266 A2: % column(s) digest an all-null object', v_bad;
  END IF;

  --: A9. THE SHAPE, which is what G25/G28 actually needs and what the tautology
  --:     was standing in for. The split enumerates seven paths; if
  --:     ottoq_boot_state_fingerprint ever grows an eighth top-level key, or a
  --:     third sub-key under a section, the split would silently drop it from
  --:     the canon while the pair went on enforcing it -- the comparison
  --:     becoming narrower than the enforcement, which is the exact thing this
  --:     file promises cannot happen. An equality between two things that are
  --:     always equal cannot detect that; a key-set assertion can, and it fires
  --:     the day the shape moves.
  --:     (Numbered A9 to keep the file's existing numbering; it runs here
  --:     because A9's subject is the same population A2 just walked.)
  SELECT count(*) INTO v_bad FROM (
    SELECT (r.validation_notes::jsonb)->'arm_a'->'endst' AS e
      FROM public.ottoq_sim_runs r
     WHERE r.run_by='cert_harness' AND r.validation_notes IS NOT NULL
       AND r.validation_status IS NOT NULL
       AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
       AND r.started_at >= v_rf
       --: THE SAME G48 PREDICATE THE SHIPPED BODIES USE. Without it these two
       --: assertions walk a population the canon does not, and they depend on
       --: the very coincidence A10's comment says must not be depended on --
       --: that all nine replay pairs happen to predate the floor. Costs nothing
       --: today (measured: the same 60 rows) and removes the dependency.
       AND (r.validation_notes::jsonb ->> 'replay') IS NULL
       AND COALESCE((r.validation_notes::jsonb->'arm_a'->>'replay_injected')::int, 0) = 0
       AND COALESCE((r.validation_notes::jsonb->'arm_b'->>'replay_injected')::int, 0) = 0) q
   WHERE NOT (q.e ?& array['visit_needs','bookings','legs','dispatches','chargers','calibration','world'])
      OR (SELECT count(*) FROM jsonb_object_keys(q.e)) <> 7
      OR NOT ((q.e->'visit_needs') ?& array['vis','fgn'])
      OR (SELECT count(*) FROM jsonb_object_keys(q.e->'visit_needs')) <> 2
      OR NOT ((q.e->'bookings')    ?& array['vis','fgn'])
      OR (SELECT count(*) FROM jsonb_object_keys(q.e->'bookings'))    <> 2
      OR NOT ((q.e->'legs')        ?& array['vis','fgn'])
      OR (SELECT count(*) FROM jsonb_object_keys(q.e->'legs'))        <> 2
      OR NOT ((q.e->'dispatches')  ?& array['vis','fgn'])
      OR (SELECT count(*) FROM jsonb_object_keys(q.e->'dispatches'))  <> 2;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A9: % post-floor pair(s) whose endst is not exactly the 7 keys x {vis,fgn} the split enumerates; a leaf would be dropped from the canon while the pair still enforces it', v_bad;
  END IF;

  --: A9b. AND THE DIGESTS ARE READ FROM THE SHIPPED FUNCTIONS, not retyped.
  --:      The old A9 recomputed both expressions inline, so it tested its own
  --:      copy and not the bodies being installed. This takes canon_endst from
  --:      ottoq_cert_matrix and canon_fgn from ottoq_cert_residue and checks
  --:      them against an INDEPENDENT recomputation from the canon pair's own
  --:      validation_notes. A typo in either shipped body fails here.
  --:
  --:      PROVEN DISCRIMINATING BEFORE INSTALLING, which is the standard this
  --:      file's earlier assertions failed. Run read-only against the PRE-image
  --:      matrix -- which still returns the whole-object digest -- A9b's
  --:      reconciliation succeeds on 0 of 9 columns. It can only pass once the
  --:      new body is actually in place. An assertion that passes both before
  --:      and after the change it is guarding is measuring nothing, and two of
  --:      this file's first-draft assertions were exactly that.
  SELECT count(*) INTO v_bad
    FROM public.ottoq_cert_matrix(v_rf) m
    JOIN public.ottoq_cert_residue(v_rf) s
      ON s.depot=m.depot AND s.seed=m.seed AND s.ticks=m.ticks AND s.scenario=m.scenario
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = m.last_run_a
   WHERE m.canon_endst IS DISTINCT FROM md5(jsonb_build_object(
           'visit_needs', (r.validation_notes::jsonb)->'arm_a'->'endst'->'visit_needs'->'vis',
           'bookings',    (r.validation_notes::jsonb)->'arm_a'->'endst'->'bookings'->'vis',
           'legs',        (r.validation_notes::jsonb)->'arm_a'->'endst'->'legs'->'vis',
           'dispatches',  (r.validation_notes::jsonb)->'arm_a'->'endst'->'dispatches'->'vis',
           'chargers',    (r.validation_notes::jsonb)->'arm_a'->'endst'->'chargers',
           'calibration', (r.validation_notes::jsonb)->'arm_a'->'endst'->'calibration',
           'world',       (r.validation_notes::jsonb)->'arm_a'->'endst'->'world')::text)
      OR s.canon_fgn IS DISTINCT FROM md5(jsonb_build_object(
           'visit_needs', (r.validation_notes::jsonb)->'arm_a'->'endst'->'visit_needs'->'fgn',
           'bookings',    (r.validation_notes::jsonb)->'arm_a'->'endst'->'bookings'->'fgn',
           'legs',        (r.validation_notes::jsonb)->'arm_a'->'endst'->'legs'->'fgn',
           'dispatches',  (r.validation_notes::jsonb)->'arm_a'->'endst'->'dispatches'->'fgn')::text);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A9b: % column(s) where a shipped function''s canon digest disagrees with an independent recomputation', v_bad;
  END IF;
  --: AND IT MUST HAVE EXAMINED ALL NINE. The join above is an INNER join on
  --: last_run_a: a column whose arm_a row is absent -- purged, or a future
  --: change to which arm's row survives -- drops out silently and A9b passes on
  --: the remainder. That is the vacuity A0 exists to prevent, and A9b was the
  --: one assertion in the suite without the guard.
  SELECT count(*) INTO v_n
    FROM public.ottoq_cert_matrix(v_rf) m
    JOIN public.ottoq_cert_residue(v_rf) s
      ON s.depot=m.depot AND s.seed=m.seed AND s.ticks=m.ticks AND s.scenario=m.scenario
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = m.last_run_a;
  IF v_n <> 9 THEN
    RAISE EXCEPTION '0266 A9b: reconciled % column(s), expected 9 -- the check ran on a subset', v_n;
  END IF;

  --: A4. THE TWELVE OTHER ATOMS SURVIVED THE COPY. Section 1 claims the body is
  --:     the live one except for the split and the G48 predicate, and until now
  --:     nothing checked it -- so accidentally deleting any conjunct during the
  --:     rewrite would have left every assertion green, because 0196 M1 measured
  --:     that all twelve non-endst atoms already match on every post-floor pair
  --:     and therefore none of them is load-bearing on today's data. Pinned by
  --:     substring against the POST-IMAGE body, which is the only way a dropped
  --:     conjunct is visible at all.
  --: INTO STRICT, and the reason is the same defect class A8 was just inverted
  --: for. A bare SELECT ... INTO leaves v_src NULL when the function is absent,
  --: `position(x in NULL)` is NULL, `NULL = 0` is NULL, and `IF NULL THEN` does
  --: not fire -- so the whole loop would pass on a missing function. STRICT
  --: raises on zero rows AND on more than one, which also refuses an overload
  --: appearing between section G and here.
  SELECT p.prosrc INTO STRICT v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix'
     AND pg_get_function_identity_arguments(p.oid) = 'p_since timestamp with time zone';
  FOREACH v_conj IN ARRAY v_conjuncts LOOP
    --: EXACTLY ONCE, not merely present: a conjunct appearing twice would mean
    --: the copy duplicated a region, which `> 0` would wave through.
    IF (length(v_src) - length(replace(v_src, v_conj, ''))) / length(v_conj) <> 1 THEN
      RAISE EXCEPTION '0266 A4: the installed ottoq_cert_matrix does not contain the canon conjunct % exactly once', v_conj;
    END IF;
  END LOOP;

  --: A3. ATTRIBUTABILITY, AND ONLY THAT -- said plainly because the previous two
  --:     versions of this assertion each claimed to be the control against a
  --:     blanket weakening and neither was.
  --:
  --:     What it does: computes the OLD digest alongside the new one, runs the
  --:     same streak logic over both, and asserts the difference set exactly --
  --:     7 flagship columns improved, 0 others improved, 0 regressed. That is
  --:     worth asserting: it fires if a NON-flagship column improves, which is
  --:     one real shape a careless change could take.
  --:
  --:     WHAT IT CANNOT DO, and the second reviewer proved it by simulation
  --:     after the rewrite was supposed to have fixed exactly this: it has NO
  --:     POWER against a blanket weakening. Both grid columns sit at their
  --:     ceiling before this file (n_old = 3 = pairs_seen), so `n_new > n_old`
  --:     is unsatisfiable for them under ANY change -- the same ceiling defect
  --:     the first A3 was convicted for, surviving a rewrite aimed at it.
  --:     Simulated on live data: the real split gives 7/0/0, and deleting the
  --:     endst conjunct entirely gives the identical counters.
  --:     The defence against a blanket weakening is A3b (sensitivity), A4 (the
  --:     thirteen conjuncts pinned in the installed body) and A9b (the shipped
  --:     digests reconciled independently). A3 is a one-sided count and is
  --:     labelled as one.
  WITH fl AS (SELECT v_rf AS rf),
  pair AS (
    SELECT DISTINCT ON (r.depot_id, r.started_at)
           r.depot_id c_depot, r.started_at t0, r.validation_status st,
           (r.validation_status='passed') ok, (r.validation_notes::jsonb) j
      FROM public.ottoq_sim_runs r
     WHERE r.run_by='cert_harness' AND r.started_at >= v_rf
       AND r.validation_status IS NOT NULL AND r.validation_notes IS NOT NULL
       AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
       AND (r.validation_notes::jsonb ->> 'replay') IS NULL
       AND COALESCE((r.validation_notes::jsonb->'arm_a'->>'replay_injected')::int,0) = 0
       AND COALESCE((r.validation_notes::jsonb->'arm_b'->>'replay_injected')::int,0) = 0
     ORDER BY r.depot_id, r.started_at, r.sim_run_id),
  keyed AS (
    SELECT p.c_depot, p.t0, p.ok, p.st, (p.j->>'seed')::bigint c_seed,
           COALESCE((p.j->>'ticks')::int,-1) c_ticks, COALESCE(p.j->>'scenario','?') c_scen,
           (p.j->'arm_a'->>'run')::uuid c_run_a,
           md5((p.j->'arm_a'->'endst')::text) AS d_old,
           CASE WHEN (p.j->'arm_a') ? 'endst' THEN md5(jsonb_build_object(
             'visit_needs', p.j->'arm_a'->'endst'->'visit_needs'->'vis',
             'bookings',    p.j->'arm_a'->'endst'->'bookings'->'vis',
             'legs',        p.j->'arm_a'->'endst'->'legs'->'vis',
             'dispatches',  p.j->'arm_a'->'endst'->'dispatches'->'vis',
             'chargers',    p.j->'arm_a'->'endst'->'chargers',
             'calibration', p.j->'arm_a'->'endst'->'calibration',
             'world',       p.j->'arm_a'->'endst'->'world')::text) END AS d_new
      FROM pair p),
  col AS (SELECT * FROM keyed WHERE st <> 'inconclusive'),
  ranked AS (SELECT c.*, row_number() OVER (PARTITION BY c_depot,c_seed,c_ticks,c_scen
                                            ORDER BY t0 DESC, c_run_a DESC) rn FROM col c),
  canon AS (SELECT * FROM ranked WHERE rn=1),
  marked AS (
    SELECT r.c_depot,r.c_seed,r.c_ticks,r.c_scen,r.rn,
           (r.ok AND r.t0>=fl.rf AND (r.d_old IS NULL OR k.d_old IS NULL OR r.d_old=k.d_old)) AS ok_old,
           (r.ok AND r.t0>=fl.rf AND (r.d_new IS NULL OR k.d_new IS NULL OR r.d_new=k.d_new)) AS ok_new
      FROM ranked r JOIN canon k USING (c_depot,c_seed,c_ticks,c_scen) CROSS JOIN fl),
  st AS (
    SELECT c_depot,c_seed,c_ticks,c_scen,
           count(*) FILTER (WHERE u_old)::int n_old,
           count(*) FILTER (WHERE u_new)::int n_new
      FROM (SELECT m.*,
              bool_and(ok_old) OVER (PARTITION BY c_depot,c_seed,c_ticks,c_scen
                       ORDER BY rn ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) u_old,
              bool_and(ok_new) OVER (PARTITION BY c_depot,c_seed,c_ticks,c_scen
                       ORDER BY rn ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) u_new
            FROM marked m) x
     GROUP BY 1,2,3,4)
  SELECT count(*) FILTER (WHERE n_new > n_old AND c_depot = '11111111-1111-1111-1111-111111111111'::uuid),
         count(*) FILTER (WHERE n_new > n_old AND c_depot <> '11111111-1111-1111-1111-111111111111'::uuid),
         count(*) FILTER (WHERE n_new < n_old)
    INTO v_n, v_bad, v_worse
    FROM st;
  IF v_n <> 7 THEN
    RAISE EXCEPTION '0266 A3: % flagship column(s) improved, expected exactly 7 (the columns foreign residue was rebasing)', v_n;
  END IF;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A3: % NON-flagship column(s) improved; the split is not targeted and is weakening the canon generally', v_bad;
  END IF;
  IF v_worse > 0 THEN
    RAISE EXCEPTION '0266 A3: % column(s) got WORSE under the split', v_worse;
  END IF;

  --: A3b. THE SENSITIVITY CONTROL -- the direction A3 cannot fail in.
  --:
  --: A3 counts which columns improved. That is useful and it is NOT a defence
  --: against a blanket weakening, for the reason stated above it. The question
  --: a control has to answer is different and sharper: DOES THE DIGEST ACTUALLY
  --: DEPEND ON EACH KEY THE SPLIT ENUMERATES?
  --:
  --: So perturb one path at a time and require the digest to move. If a key were
  --: dropped from the enumeration -- the exact silent narrowing this migration
  --: creates by trading an opaque whole-object hash for a list -- then spoiling
  --: that key would change nothing and its perturbation would equal the truth.
  --: Nothing else in this suite can see that: A2 sees a NULL, A9 sees the shape
  --: of what was RECORDED, and neither notices a key the DIGEST ignores.
  --:
  --: MEASURED read-only before installing: 9 columns x 7 own keys = 63 distinct
  --: perturbations, 0 inert; and 9 x 4 fgn keys, 0 inert.
  WITH canon AS (
    SELECT m.depot, m.canon_endst, s.canon_fgn,
           (r.validation_notes::jsonb)->'arm_a'->'endst' AS e
      FROM public.ottoq_cert_matrix(v_rf) m
      JOIN public.ottoq_cert_residue(v_rf) s
        ON s.depot=m.depot AND s.seed=m.seed AND s.ticks=m.ticks AND s.scenario=m.scenario
      JOIN public.ottoq_sim_runs r ON r.sim_run_id = m.last_run_a)
  SELECT count(*) FILTER (WHERE md5(jsonb_build_object('visit_needs', e->'visit_needs'->'vis', 'bookings', e->'bookings'->'vis', 'legs', e->'legs'->'vis', 'dispatches', e->'dispatches'->'vis', 'chargers', e->'chargers', 'calibration', e->'calibration', 'world', e->'world')::text) = ANY(ARRAY[
             md5(jsonb_build_object('visit_needs', to_jsonb(v_sentinel), 'bookings', e->'bookings'->'vis', 'legs', e->'legs'->'vis', 'dispatches', e->'dispatches'->'vis', 'chargers', e->'chargers', 'calibration', e->'calibration', 'world', e->'world')::text),
             md5(jsonb_build_object('visit_needs', e->'visit_needs'->'vis', 'bookings', to_jsonb(v_sentinel), 'legs', e->'legs'->'vis', 'dispatches', e->'dispatches'->'vis', 'chargers', e->'chargers', 'calibration', e->'calibration', 'world', e->'world')::text),
             md5(jsonb_build_object('visit_needs', e->'visit_needs'->'vis', 'bookings', e->'bookings'->'vis', 'legs', to_jsonb(v_sentinel), 'dispatches', e->'dispatches'->'vis', 'chargers', e->'chargers', 'calibration', e->'calibration', 'world', e->'world')::text),
             md5(jsonb_build_object('visit_needs', e->'visit_needs'->'vis', 'bookings', e->'bookings'->'vis', 'legs', e->'legs'->'vis', 'dispatches', to_jsonb(v_sentinel), 'chargers', e->'chargers', 'calibration', e->'calibration', 'world', e->'world')::text),
             md5(jsonb_build_object('visit_needs', e->'visit_needs'->'vis', 'bookings', e->'bookings'->'vis', 'legs', e->'legs'->'vis', 'dispatches', e->'dispatches'->'vis', 'chargers', to_jsonb(v_sentinel), 'calibration', e->'calibration', 'world', e->'world')::text),
             md5(jsonb_build_object('visit_needs', e->'visit_needs'->'vis', 'bookings', e->'bookings'->'vis', 'legs', e->'legs'->'vis', 'dispatches', e->'dispatches'->'vis', 'chargers', e->'chargers', 'calibration', to_jsonb(v_sentinel), 'world', e->'world')::text),
             md5(jsonb_build_object('visit_needs', e->'visit_needs'->'vis', 'bookings', e->'bookings'->'vis', 'legs', e->'legs'->'vis', 'dispatches', e->'dispatches'->'vis', 'chargers', e->'chargers', 'calibration', e->'calibration', 'world', to_jsonb(v_sentinel))::text)])),
         count(*) FILTER (WHERE md5(jsonb_build_object('visit_needs', e->'visit_needs'->'fgn', 'bookings', e->'bookings'->'fgn', 'legs', e->'legs'->'fgn', 'dispatches', e->'dispatches'->'fgn')::text) = ANY(ARRAY[
             md5(jsonb_build_object('visit_needs', to_jsonb(v_sentinel), 'bookings', e->'bookings'->'fgn', 'legs', e->'legs'->'fgn', 'dispatches', e->'dispatches'->'fgn')::text),
             md5(jsonb_build_object('visit_needs', e->'visit_needs'->'fgn', 'bookings', to_jsonb(v_sentinel), 'legs', e->'legs'->'fgn', 'dispatches', e->'dispatches'->'fgn')::text),
             md5(jsonb_build_object('visit_needs', e->'visit_needs'->'fgn', 'bookings', e->'bookings'->'fgn', 'legs', to_jsonb(v_sentinel), 'dispatches', e->'dispatches'->'fgn')::text),
             md5(jsonb_build_object('visit_needs', e->'visit_needs'->'fgn', 'bookings', e->'bookings'->'fgn', 'legs', e->'legs'->'fgn', 'dispatches', to_jsonb(v_sentinel))::text)])),
         count(*)
    INTO v_n, v_bad, v_worse
    FROM canon;
  IF v_worse <> 9 THEN
    RAISE EXCEPTION '0266 A3b: sensitivity examined % column(s), expected 9 -- the control must not run on a subset', v_worse;
  END IF;
  IF v_n > 0 THEN
    RAISE EXCEPTION '0266 A3b: on % column(s) the own digest is INSENSITIVE to at least one of the seven paths it enumerates -- a key is being silently dropped from the canon', v_n;
  END IF;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A3b: on % column(s) the foreign digest is INSENSITIVE to at least one of its four paths', v_bad;
  END IF;

  --: A5. THE RESIDUE INSTRUMENT COVERS EXACTLY THE SAME COLUMNS -- over the WIDE
  --:     window, not the floor. Scoped to the floor this examined zero replay
  --:     pairs (all nine predate it), so it was blind to precisely the
  --:     divergence the new G48 predicate could introduce if a later edit
  --:     dropped it from one instrument and not the other. The file already
  --:     makes this argument for A10 and failed to apply it here.
  SELECT count(*) INTO v_bad FROM (
    SELECT depot, seed, ticks, scenario FROM public.ottoq_cert_matrix('2000-01-01'::timestamptz)
    EXCEPT
    SELECT depot, seed, ticks, scenario FROM public.ottoq_cert_residue('2000-01-01'::timestamptz)) x;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A5: % column(s) in the matrix and not in the residue instrument', v_bad;
  END IF;
  SELECT count(*) INTO v_bad FROM (
    SELECT depot, seed, ticks, scenario FROM public.ottoq_cert_residue('2000-01-01'::timestamptz)
    EXCEPT
    SELECT depot, seed, ticks, scenario FROM public.ottoq_cert_matrix('2000-01-01'::timestamptz)) x;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A5: % column(s) in the residue instrument and not in the matrix', v_bad;
  END IF;

  --: A6. THE RESIDUE INSTRUMENT STILL SEES THE THING THAT WAS LOST. Prediction
  --:     P2: the flagship columns must show the fgn break round 41 surfaced, and
  --:     name `legs` as the section that moved. An instrument that reported
  --:     everything stable would mean the hygiene fact was dropped, not
  --:     relocated -- which is the only way this migration could be dishonest.
  --: MEMBERSHIP, not equality. sections_moved is a concat_ws list; if another
  --: fgn section also moves before this file runs -- another run leaving a
  --: booking or dispatch in a live state, which is the very phenomenon this
  --: migration exists to tolerate -- the value becomes 'bookings,legs' and an
  --: equality test would refuse the migration for a reason unrelated to what
  --: A6 is checking.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_residue(v_rf)
   WHERE depot = '11111111-1111-1111-1111-111111111111'::uuid
     AND 'legs' = ANY(string_to_array(COALESCE(sections_moved, ''), ','));
  IF v_n <> 7 THEN
    RAISE EXCEPTION '0266 A6: % flagship column(s) report the legs residue move (expected 7); the hygiene fact was dropped, not relocated', v_n;
  END IF;

  --: A7. PRIVILEGES UNCHANGED on the replaced function, pinned to the ACL
  --:     measured in the pre-image. CREATE OR REPLACE preserves proacl by
  --:     definition; this asserts the definition held.
  SELECT array_to_string(p.proacl::text[], ' | ') INTO STRICT v_txt
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';
  IF v_txt IS DISTINCT FROM '=X/postgres | postgres=X/postgres | anon=X/postgres | authenticated=X/postgres | service_role=X/postgres' THEN
    RAISE EXCEPTION '0266 A7: ottoq_cert_matrix privileges changed to %', COALESCE(v_txt, '(default)');
  END IF;

  --: A7b. THE NEW FUNCTION'S ACL, PINNED EXACTLY -- not merely "non-null and
  --:      mentions service_role", which the review showed still passes with
  --:      PUBLIC holding EXECUTE if the REVOKE line is deleted. The expected
  --:      string DELIBERATELY DIFFERS from A7's by the leading `=X/postgres`:
  --:      that entry IS the PUBLIC grant, the matrix carries it for historical
  --:      reasons and the residue does not. An earlier draft of the comment
  --:      above the GRANT said the residue was "granted to match
  --:      ottoq_cert_matrix exactly"; A7's own pinned string refutes that, and
  --:      the comment has been corrected rather than the grant loosened.
  SELECT array_to_string(p.proacl::text[], ' | ') INTO STRICT v_txt
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_residue';
  IF v_txt IS DISTINCT FROM 'postgres=X/postgres | anon=X/postgres | authenticated=X/postgres | service_role=X/postgres' THEN
    RAISE EXCEPTION '0266 A7b: ottoq_cert_residue ACL is %, expected PUBLIC revoked and the four roles granted', COALESCE(v_txt, '(default: PUBLIC holds EXECUTE)');
  END IF;

  --: A8. THE ENGINE DID NOT MOVE -- as a POSITIVE count, because the old shape
  --:     (`count(*) WHERE proname=X AND md5 <> pin`, refuse if > 0) passes when
  --:     the function does not exist at all. That is the NOT-EXISTS-skips-the-row
  --:     failure db/checks/0193 blocker (iii) already convicted in the previous
  --:     design; it must not be reintroduced in the fix for it. Requiring
  --:     exactly one match also refuses a second overload appearing.
  SELECT count(*) INTO v_bad FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair'
     AND md5(p.prosrc) = '8a35b8c874fed154cc216140faec0274';
  IF v_bad <> 1 THEN
    RAISE EXCEPTION '0266 A8: expected exactly 1 ottoq_determinism_pair at the pinned md5, found %', v_bad;
  END IF;
  SELECT count(*) INTO v_bad FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_boot_state_fingerprint'
     AND md5(p.prosrc) = '90d490c24ae084d03477a8a782a9f856';
  IF v_bad <> 1 THEN
    RAISE EXCEPTION '0266 A8: expected exactly 1 ottoq_boot_state_fingerprint at the pinned md5, found %', v_bad;
  END IF;

  --: A10. G48: THE REPLAY PREDICATE EXCLUDES REPLAYS AND KEEPS THE CONTROLS.
  --:      Run over a WIDE window on purpose. All nine existing replay pairs
  --:      predate the recert floor -- that coincidence is the only thing
  --:      protecting today's canon -- so an assertion scoped to the floor would
  --:      examine zero replay pairs and pass vacuously.
  --:      `validation_status IS NOT NULL` included so this walks the SAME
  --:      population the matrix's own pair CTE does; without it the predicate
  --:      was validated over 500 pairs while protecting 493.
  --:      TWO NUMBERS, and the second is the one that matters. Excluding 7 is
  --:      easy; KEEPING the 2 zero-injection controls is what a near-miss
  --:      predicate gets wrong, because `replay` is present with a NULL VALUE on
  --:      a control and `NOT (notes ? 'replay')` would drop honest data.
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
             AND r.validation_status IS NOT NULL
             AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
           ORDER BY r.depot_id, r.started_at, r.sim_run_id) q;
  IF v_n <> 7 THEN
    RAISE EXCEPTION '0266 A10: predicate excludes % pair(s), expected the 7 injected replays', v_n;
  END IF;
  IF v_bad <> 2 THEN
    RAISE EXCEPTION '0266 A10: % zero-injection control pair(s) survive, expected 2; the predicate is dropping honest certification data', v_bad;
  END IF;

  --: A10b. AND THE INSTRUMENT AGREES WITH THE PREDICATE, AS A SET. A count
  --:       comparison balances if a mis-written predicate drops seven DIFFERENT
  --:       pairs, so compare the pairs themselves. The matrix does not expose
  --:       per-pair identity, so the set is compared through `last_run_a` of
  --:       each column plus the pair totals: any column whose admitted pair
  --:       count differs from the predicate's own count for that column fails.
  SELECT count(*) INTO v_bad FROM (
    SELECT m.depot, m.seed, m.ticks, m.scenario, m.pairs_seen,
           --: THE PREDICATE IN THE SAME POSITION THE BODY PUTS IT: inside the
           --: WHERE, BEFORE DISTINCT ON. An earlier draft filtered after
           --: DISTINCT ON, which is a different operation -- if a
           --: (depot_id, started_at) group ever held both a replay row and a
           --: non-replay row the two formulations would disagree, and A10b's
           --: whole purpose is to prove the clause is in the shipped body.
           --: (Measured: 500 groups, 0 mixed, so they agree today; the point is
           --: that agreement should not depend on that.)
           (SELECT count(*) FROM (
              SELECT DISTINCT ON (r.depot_id, r.started_at) r.validation_status vs,
                     (r.validation_notes::jsonb) j, r.depot_id
                FROM public.ottoq_sim_runs r
               WHERE r.run_by='cert_harness' AND r.validation_notes IS NOT NULL
                 AND r.validation_status IS NOT NULL
                 AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
                 AND (r.validation_notes::jsonb ->> 'replay') IS NULL
                 AND COALESCE((r.validation_notes::jsonb->'arm_a'->>'replay_injected')::int,0) = 0
                 AND COALESCE((r.validation_notes::jsonb->'arm_b'->>'replay_injected')::int,0) = 0
               ORDER BY r.depot_id, r.started_at, r.sim_run_id) z
             WHERE z.depot_id = m.depot
               AND (z.j->>'seed')::bigint = m.seed
               AND COALESCE((z.j->>'ticks')::int,-1) = m.ticks
               AND COALESCE(z.j->>'scenario','?') = m.scenario
               AND z.vs <> 'inconclusive') AS expected
      FROM public.ottoq_cert_matrix('2000-01-01'::timestamptz) m) w
   WHERE w.pairs_seen IS DISTINCT FROM w.expected;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0266 A10b: % column(s) where the matrix pair count disagrees with the predicate applied independently', v_bad;
  END IF;

  RAISE NOTICE '0266: A0-A10b passed; recert floor unmoved at %; 7 flagship columns improved, 0 grid columns moved', v_rf;
END $a$;

-- ---------------------------------------------------------------------------
-- PRE-APPLY DRY RUNS (APPLYING.md 3b). Every assertion whose SQL could not be
-- checked by reading was rendered runnable and executed READ-ONLY against the
-- live database before this file was ever applied. This section exists because
-- the first draft of A3b would have ABORTED the migration -- a generated literal
-- had lost its quotes and became a column reference -- and no amount of reading
-- caught it; a reviewer's live probe did.
--
--   A3b  the file's own text, with v_rf -> the live floor, v_sentinel -> its
--        declared literal, and ottoq_cert_residue (which does not exist yet)
--        -> an inline equivalent. All eleven perturbations:
--            own_inert 0 | fgn_inert 0 | columns_examined 9
--   A9b  same rendering, run against the PRE-image matrix: reconciles 0 of 9.
--        It can only pass once the new body is installed, which is what makes it
--        a control rather than a decoration.
--   A2/A9  0 violations over 60 post-floor arm rows; with one path deliberately
--        misspelled, 60 of 60 violate -- so the positive control is positive.
--   A10  7 excluded / 2 controls kept, over the wide window.
--   A10b against the PRE-image matrix returns 2 (497 vs 490 pairs), 0 after.
--   C1 of db/checks/0198: 0 shape violations over 30 post-floor pairs.
--
-- AND A SCAN FOR THE ROOT CAUSE ACROSS THE WHOLE FILE: no bare __token__
-- identifier survives outside a string literal anywhere in 1,200 lines.
--
-- THEN THE REAL TEST, which no amount of reading substitutes for: the new
-- function was CREATED, EXERCISED AND ROLLED BACK inside one transaction against
-- the live database. Rollback was proven to be honoured first, with a throwaway
-- function that did not survive it, so this could not leave anything behind.
--
--   CREATE OR REPLACE ottoq_cert_residue   parsed and installed
--   returns exactly 9 columns              (matches ottoq_cert_matrix's 9)
--   A6: sections_moved names `legs` on     exactly 7 flagship columns
--   grid columns reporting movement        0
--   history glyph vocabulary               only S, . and -
--   over the WIDE window every column      renders a pre-floor '-'
--        -- which is the three-state fix working: the earlier version rendered
--        -- those pairs as '.', i.e. as MOVED, on columns that never moved
--   after ROLLBACK, ottoq_cert_residue     does not exist
--
-- This is the half the six reviews could only reason about. It is now executed.
-- What remains unexecuted as a whole is the file end to end; every other section
-- has been run individually, and section G's four pins, A1's floor and A7's ACL
-- were each read straight off the live database.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- APPLY LOG
--
-- APPLIED 2026-09-13 13:56:34 UTC (8:56 AM CT) as migration version
-- 20260913135634, via apply_migration so the ledger records it. Window verified
-- clean immediately before: 0 pair calls in pg_stat_activity, 0 certification
-- jobs scheduled, 0 runs running or paused, ottoq_cert_residue absent,
-- ottoq_cert_matrix at the pinned prosrc md5 f5bb81931feae44871c3ecd86d4f86b4,
-- recert floor at 2026-09-12 16:50:23.319089+00, the retention purge ~18 h away.
--
-- Every assertion A0 through A10b passed; the DO block raises on any failure and
-- the migration returned success, so the whole suite ran. POST-IMAGE measured:
--
--   ottoq_cert_matrix prosrc md5  f5bb8193... -> cd15c67d283e17eb273eb8f011489206
--   ottoq_cert_residue            absent      -> present, 9 columns
--   recert floor                  UNMOVED at 2026-09-12 16:50:23.319089+00
--   ottoq_schema_snapshots        3 rows at label '0266-pre'
--   ottoq_cert_lineage            forces_recert = false, as classified
--
-- THE ENGINE MATRIX, all nine columns green, at the recert floor:
--   11111111 171717 48t busy_day   6 pairs  streak 6  PPPPPP
--   11111111 171717 24t busy_day   3 pairs  streak 3  PPP
--   11111111 424242 24t busy_day   3 pairs  streak 3  PPP
--   11111111 171717 12t busy_day   3 pairs  streak 3  PPP
--   11111111 314159 12t busy_day   3 pairs  streak 3  PPP
--   11111111 424242 12t busy_day   3 pairs  streak 3  PPP
--   11111111 171717 12t normal_day 3 pairs  streak 3  PPP
--   aacd0bb0 239001  6t grid_smoke 3 pairs  streak 3  PPP
--   aacd0bb0 424242  6t grid_smoke 3 pairs  streak 3  PPP
--
-- THE RESIDUE INSTRUMENT, and this is the half that proves the fact was
-- RELOCATED rather than dropped -- the seven flagship columns name `legs` as the
-- section that moved, which is round 41's rebase, still visible, now in the
-- instrument whose job it is:
--   11111111 171717 48t busy_day   streak 2  ....SS  legs
--   11111111 171717 24t busy_day   streak 1  ..S     legs
--   11111111 424242 24t busy_day   streak 1  ..S     legs
--   11111111 171717 12t busy_day   streak 1  ..S     legs
--   11111111 314159 12t busy_day   streak 1  ..S     legs
--   11111111 424242 12t busy_day   streak 1  ..S     legs
--   11111111 171717 12t normal_day streak 1  ..S     legs
--   aacd0bb0 239001  6t grid_smoke streak 3  SSS     (none)
--   aacd0bb0 424242  6t grid_smoke streak 3  SSS     (none)
--
-- All seven flagship columns share one canon_fgn (2d1315b9...) and both grid
-- columns share another (13e2e154...), which is what a depot-scoped hygiene
-- number should look like: the residue is a property of the DEPOT at a moment,
-- not of the seed or the tick count.
--
-- ONE PRE-APPLY SCARE, RESOLVED RATHER THAN WAVED THROUGH, because the resolution
-- is the point. The payload generator's unbalanced-quote detector -- the one that
-- caught the comment-stripper mangling nine lines earlier in the same session --
-- reported 37 flagged lines where an earlier build of the same payload reported
-- zero. Rather than assume a false positive, the payload was run through a real
-- PostgreSQL lexer (dollar-quote tags, '' escaping, line and block comments).
-- Three independent results, and no one of them alone would have been enough:
--   (1) the lexer terminates in CODE with no open dollar-quote tag, so nothing is
--       truncated or unterminated;
--   (2) all 37 flagged lines START inside a dollar-quoted function body, which is
--       exactly the detector's documented blind spot -- it excludes only lines
--       CONTAINING a `$`, not lines BETWEEN the tags;
--   (3) decisively: the dry-run payload already executed against this database
--       and rolled back reports the SAME 37, and diffs against the apply payload
--       at 29 blank lines and a trailing newline, zero content difference.
-- The detector is now known to be line-local; sqllex-style lexing is the check
-- that answers the question it raises.
-- ---------------------------------------------------------------------------
