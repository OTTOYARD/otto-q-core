-- migration-version: PENDING
-- migration-name:    the_canon_comparison_sees_every_atom_the_pair_enforces
-- ---------------------------------------------------------------------------
-- 0225 — the across-round comparison sees all fourteen atoms the pair
--        enforces, not nine of them.
--
-- forces_recert: FALSE — and this one needs the reasoning spelled out, because
-- a migration that changes what `green` means looks exactly like one that
-- should force a recertification. It does not, for two reasons. (1) No engine
-- behaviour changes: `ottoq_cert_matrix` is a STABLE pure read called by
-- nothing in the decide path (0131 established that and it is re-asserted in
-- P1 below). No canon can move because nothing that produces a canon is
-- touched. (2) P3 asserts that no column which is green under the nine-atom
-- comparison stops being green under the fourteen-atom one — the property the
-- certification claim actually rests on. If P3 fails the migration refuses
-- rather than landing and looking like a regression.
--
-- THE DEFECT, from db/checks/0134. Two different jobs share the word
-- "certification":
--
--   ottoq_determinism_pair compares ARM A TO ARM B — did this seed produce the
--   same run twice. It enforces FOURTEEN equalities.
--
--   ottoq_cert_matrix compares THIS PAIR TO THE CANON — did today's migrations
--   move anything. It compares NINE.
--
-- The five it does not compare are ticks (structural) and h_rule, h_rcl,
-- h_sdr, endst — every one of them ENFORCED by the pair, promoted deliberately
-- in 0205, 0217, 0219 and 0139 respectively. A defect that moves one of them
-- IDENTICALLY ON BOTH ARMS passes the pair, passes on_canon, advances
-- consecutive_passes, and leaves `green` true while the canon silently changes.
--
-- Two of the four are worse than omitted: c_rule and c_rcl are extracted,
-- carried into the canon CTE and RETURNED as `canon_rule` / `canon_rcl` —
-- three mentions each in the live body, not one of them a comparison. A reader
-- sees `canon_rule` beside `canon_cmd` with no way to know that one can break
-- the streak and the other cannot. An omitted column is a gap; a displayed
-- column that is never judged is a false assurance.
--
-- WHY NOW, AND NOT LATER. 0134 Q6's argument was that extending a comparison
-- is cheapest when there is least history to disagree with, and at the
-- 2026-09-08 13:02 floor every column held exactly one pair, so nothing could
-- be off-canon.
--
-- **That argument no longer applies as stated, and the correction matters.**
-- 0226 lowers the floor to 2026-09-07 21:36:53 — the floor the classifications
-- already specify, which G28 showed was never being read. This migration is
-- applied AFTER 0226, deliberately, so the window P3 examines is much larger:
-- seven columns and up to six pairs each, not four columns of one pair. The
-- dry-run of that combination is db/checks/0140, and it is the reason P3 was
-- rewritten before this file was ever applied.
--
-- The timing argument that survives is weaker and still sufficient: history
-- only grows, so the newly compared atoms only accumulate more chances to
-- disagree. What changed is that "no disagreement anywhere" stopped being an
-- achievable bar, so P3 now tests the bar that matters instead.
--
-- WHAT CHANGES, precisely five edits to a body that is otherwise byte-identical:
--   1. `keyed` extracts c_sdr and c_endst.
--   2. `canon` carries them.
--   3. `marked` compares c_rule, c_rcl, c_sdr and c_endst, in the 0199/0201
--      NULL-tolerant form.
--   4. RETURNS TABLE gains canon_sdr and canon_endst, appended.
--   5. the final SELECT returns them.
--
-- endst is compared as md5 of its jsonb text, NOT as the object. The pair
-- itself compares `->` and not `->>` (0139), and jsonb's text rendering is
-- canonical, so the md5 is a stable stand-in that fits a text column beside
-- the other canons. A NULL endst (pre-0139) md5s to NULL and is tolerated.
--
-- WHY A DROP AND NOT A REPLACE. The return type changes, and Postgres refuses
-- to change a function's OUT columns with CREATE OR REPLACE. P2 asserts no
-- object depends on the function before dropping it, so the drop is not a
-- CASCADE in disguise.
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT. P- enforces it. Round 27 was
-- running when this was drafted, which is exactly why it is drafted and not
-- applied: 0134 says the cheapest moment is "NOW or immediately after round
-- 27", and round 27 is judging 0223 and 0224. A third change mid-round would
-- make none of the three attributable.
-- ---------------------------------------------------------------------------

-- The A2 snapshot has to be taken while the OLD function is still installed,
-- so it is a statement of its own ahead of the DO block. TEMP + ON COMMIT DROP
-- so it cannot survive as residue in public if anything goes wrong; the whole
-- migration runs in one transaction, so `now()` is the same instant here and
-- in A2 and the two 30-day windows are identical rather than merely similar.
CREATE TEMP TABLE _0225_before ON COMMIT DROP AS
SELECT depot, seed, ticks, scenario, green, consecutive_passes
  FROM public.ottoq_cert_matrix(now() - interval '30 days');

DO $mig$
DECLARE
  --------------------------------------------------------------- anchors ----
  -- Dollar-quoted so the SQL inside them is the SQL as it appears in the live
  -- body, not an escaped transcription of it. Each is asserted to occur
  -- EXACTLY ONCE before any replacement happens: a missed anchor is a silent
  -- no-op and a doubled anchor patches a site nobody looked at.
  a1_old constant text := $a$         p.j->'arm_a'->>'h_cal'                    AS c_cal,    -- 0201; NULL before 0201$a$;
  a1_new constant text := $a$         p.j->'arm_a'->>'h_cal'                    AS c_cal,    -- 0201; NULL before 0201
         p.j->'arm_a'->>'h_sdr'                    AS c_sdr,    -- 0217/0219; NULL before 0217
         md5((p.j->'arm_a'->'endst')::text)        AS c_endst,  -- 0139; NULL before 0139$a$;

  a2_old constant text := $a$         rk.c_fp, rk.c_cmd, rk.c_dec, rk.c_evt, rk.c_bkg, rk.c_nrg, rk.c_prop, rk.c_defr, rk.c_cal, rk.c_rule, rk.c_rcl$a$;
  a2_new constant text := $a$         rk.c_fp, rk.c_cmd, rk.c_dec, rk.c_evt, rk.c_bkg, rk.c_nrg, rk.c_prop, rk.c_defr, rk.c_cal, rk.c_rule, rk.c_rcl,
         rk.c_sdr, rk.c_endst$a$;

  a3_old constant text := $a$          AND (r.c_cal  IS NULL OR k.c_cal  IS NULL OR r.c_cal  = k.c_cal)) AS on_canon$a$;
  a3_new constant text := $a$          AND (r.c_cal  IS NULL OR k.c_cal  IS NULL OR r.c_cal  = k.c_cal)
          -- 0225: the four atoms the pair enforced and the matrix could not see
          -- (db/checks/0134). NULL-tolerant for the same reason as 0199 and
          -- 0201: a pair hashed before the instrument existed cannot be judged
          -- by it.
          AND (r.c_rule  IS NULL OR k.c_rule  IS NULL OR r.c_rule  = k.c_rule)
          AND (r.c_rcl   IS NULL OR k.c_rcl   IS NULL OR r.c_rcl   = k.c_rcl)
          AND (r.c_sdr   IS NULL OR k.c_sdr   IS NULL OR r.c_sdr   = k.c_sdr)
          AND (r.c_endst IS NULL OR k.c_endst IS NULL OR r.c_endst = k.c_endst)) AS on_canon$a$;

  a4_old constant text := $a$canon_rule text, canon_rcl text)$a$;
  a4_new constant text := $a$canon_rule text, canon_rcl text, canon_sdr text, canon_endst text)$a$;

  a5_old constant text := $a$       l.c_prop, l.c_defr, l.c_cal, l.c_rule, l.c_rcl
$a$;
  a5_new constant text := $a$       l.c_prop, l.c_defr, l.c_cal, l.c_rule, l.c_rcl, l.c_sdr, l.c_endst
$a$;
  v_def        text;
  v_new        text;
  v_pin        constant text := '34628fff3b2d0c3964d427d725ed2d1b';
  v_len_before int;
  v_n          int;
  v_bad        text;
  v_streaks    text;
BEGIN
  ------------------------------------------------------------------ P- ------
  -- pg_stat_activity is the ONLY authority on whether a pair is running.
  -- ottoq_sim_runs cannot see one (both arms are one transaction) and
  -- cron.job_run_details reports an in-flight two-statement job as
  -- 'succeeded' at ~1 s (db/canons/round25.md).
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
                AND pid <> pg_backend_pid()) THEN
    RAISE EXCEPTION '0225 P-: a determinism pair is active right now';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ '^r[0-9]+_' AND active) THEN
    RAISE EXCEPTION '0225 P-: certification jobs are still scheduled (%). '
                    'Unschedule the round before changing what green means.',
                    (SELECT string_agg(jobname, ', ') FROM cron.job
                      WHERE jobname ~ '^r[0-9]+_' AND active);
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE status = 'running' AND run_by = 'cert_harness') THEN
    RAISE EXCEPTION '0225 P-: a cert_harness sim run is still marked running';
  END IF;

  ------------------------------------------------------------------ P0 ------
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cert_matrix';
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0225 P0: public.ottoq_cert_matrix does not exist';
  END IF;
  IF md5(v_def) <> v_pin THEN
    RAISE EXCEPTION '0225 P0: pre-image is %, expected %. The body moved since '
                    'this migration was written; re-derive it, do not force.',
                    md5(v_def), v_pin;
  END IF;
  v_len_before := length(v_def);

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0225 P0: % overloads of ottoq_cert_matrix; the DROP below '
                    'names one signature and would leave the others', v_n;
  END IF;

  ------------------------------------------------------------------ P1 ------
  -- The function is a pure read with no caller in the decide path. This is
  -- what makes forces_recert FALSE true rather than assumed.
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public','ottoq','twin')
       AND p.proname <> 'ottoq_cert_matrix'
       AND p.prosrc ILIKE '%ottoq_cert_matrix%'
       AND p.proname NOT LIKE 'ottoq_fn_backup_%') THEN
    RAISE EXCEPTION '0225 P1: some function calls ottoq_cert_matrix: %',
      (SELECT string_agg(n.nspname||'.'||p.proname, ', ')
         FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname IN ('public','ottoq','twin')
          AND p.proname <> 'ottoq_cert_matrix'
          AND p.prosrc ILIKE '%ottoq_cert_matrix%'
          AND p.proname NOT LIKE 'ottoq_fn_backup_%');
  END IF;

  ------------------------------------------------------------------ P2 ------
  -- Nothing may depend on the function, or the DROP is a CASCADE wearing a
  -- different word. Views are the realistic case.
  SELECT string_agg(DISTINCT cl.relname, ', ') INTO v_bad
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class   cl ON cl.oid = rw.ev_class
   WHERE d.refobjid = (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                        WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0225 P2: these views depend on ottoq_cert_matrix and the '
                    'DROP would take them: %', v_bad;
  END IF;

  ------------------------------------------------------------------ P3 ------
  -- REVISED 2026-09-08 15:35 UTC, before the migration was ever applied, on
  -- db/checks/0140. The first draft of P3 refused, and it refused for the
  -- wrong reason, on two columns. What it got right is that it refused rather
  -- than landing quietly; what it got wrong is all three of these:
  --
  --   1. It grouped by (scenario, seed, ticks) and DROPPED depot_id, which it
  --      selected and then discarded — while ottoq_cert_matrix keys by
  --      (depot, seed, ticks, scenario). Two depots running one scenario would
  --      have collapsed into one row. Inert today only because 0138 proved the
  --      Benchmark depot has zero runs, so a second lane would activate it.
  --   2. It judged `grid_smoke` — the 6-tick fixture from 0153 — as though a
  --      certification claim rested on it. Its d_sdr was 0: not "one value",
  --      but *no* values, every pair predating h_sdr.
  --   3. Worst, its bar was stricter than the property it exists to protect.
  --      It refused on ANY disagreement in the window while its message
  --      claimed streaks "would break". On busy_day/314159/12t the disagreeing
  --      pair is the 08:25:00 one, eighteen minutes before 0218 fixed the
  --      run-scoped-id signature it hashed, and while 0219 still had h_sdr
  --      measured rather than enforced. Traced through the matrix's own
  --      `bool_and ... ORDER BY rn` from the newest pair backwards, that
  --      column goes from 6 consecutive passes to 3 — and green needs 2. It
  --      stays green. P3 refused a change that costs three streak rows for a
  --      disagreement that cannot recur.
  --
  -- So P3 now tests the property, not a proxy for it: **does any column that
  -- is green under the nine-atom comparison stop being green under the
  -- fourteen-atom one?** Same key as the matrix, same NULL-tolerant form, same
  -- streak window, same >= 2 threshold, evaluated at whatever floor is live
  -- when this runs. A fixture that was never green cannot lose green, so
  -- grid_smoke drops out on its own rather than by being special-cased. And a
  -- historical disagreement that does not cost a column its green no longer
  -- blocks a change whose entire purpose is to compare more atoms.
  --
  -- Note what is deliberately NOT done: the floor is not raised past 08:25 and
  -- that pair is not touched. It is correct history — the measured phase
  -- catching an arm-unstable hash before enforcement — and it is the evidence
  -- that motivated 0218. A migration that becomes applicable by hiding
  -- evidence is worse than one that refuses.
  -- Computed ONCE into a temp table and read twice — by the refusal test and
  -- by the record that feeds A5. The first draft of this block carried the
  -- same sixty-line predicate twice; two copies of the rule that guards the
  -- certification is how the two copies drift.
  CREATE TEMP TABLE _0225_streaks ON COMMIT DROP AS
  WITH fl AS (SELECT public.ottoq_cert_recert_floor() AS rf),
  pair AS (
    SELECT DISTINCT ON (r.depot_id, r.started_at)
           r.depot_id AS c_depot, r.started_at AS t0,
           (r.validation_status = 'passed') AS ok, r.validation_status AS st,
           (r.validation_notes::jsonb) AS j
      FROM public.ottoq_sim_runs r
     WHERE r.run_by = 'cert_harness'
       AND r.started_at >= (now() - interval '30 days')
       AND r.validation_status IS NOT NULL AND r.validation_notes IS NOT NULL
       AND jsonb_typeof((r.validation_notes::jsonb) -> 'arm_a') = 'object'
     ORDER BY r.depot_id, r.started_at, r.sim_run_id
  ), keyed AS (
    SELECT p.c_depot, p.t0, p.ok, p.st,
           (p.j->>'seed')::bigint             AS c_seed,
           COALESCE((p.j->>'ticks')::int, -1) AS c_ticks,
           COALESCE(p.j->>'scenario','?')     AS c_scen,
           p.j->'arm_a'->>'fp'     AS c_fp,   p.j->'arm_a'->>'h_cmd'  AS c_cmd,
           p.j->'arm_a'->>'h_dec'  AS c_dec,  p.j->'arm_a'->>'h_evt'  AS c_evt,
           p.j->'arm_a'->>'h_bkg'  AS c_bkg,  p.j->'arm_a'->>'h_nrg'  AS c_nrg,
           p.j->'arm_a'->>'h_prop' AS c_prop, p.j->'arm_a'->>'h_defr' AS c_defr,
           p.j->'arm_a'->>'h_cal'  AS c_cal,  p.j->'arm_a'->>'h_rule' AS c_rule,
           p.j->'arm_a'->>'h_rcl'  AS c_rcl,  p.j->'arm_a'->>'h_sdr'  AS c_sdr,
           md5((p.j->'arm_a'->'endst')::text) AS c_endst,
           (p.j->'arm_a'->>'run')::uuid       AS c_run_a
      FROM pair p
  ), ranked AS (
    -- Same tiebreaker as the matrix (t0 DESC, c_run_a DESC), so rn means the
    -- same thing here as it does there. t0 is already unique per depot via the
    -- DISTINCT ON above, so it cannot fire — carried for fidelity, because a
    -- P3 that mirrors the matrix approximately is what 0140 was written about.
    SELECT k.*, row_number() OVER (PARTITION BY k.c_depot,k.c_seed,k.c_ticks,k.c_scen
                                   ORDER BY k.t0 DESC, k.c_run_a DESC) AS rn
      FROM keyed k WHERE k.st <> 'inconclusive'
  ), canon AS (SELECT * FROM ranked WHERE rn = 1),
  marked AS (
    SELECT r.c_depot, r.c_seed, r.c_ticks, r.c_scen, r.rn,
           (r.ok AND r.t0 >= fl.rf
            AND r.c_fp  IS NOT DISTINCT FROM k.c_fp
            AND r.c_cmd IS NOT DISTINCT FROM k.c_cmd
            AND r.c_dec IS NOT DISTINCT FROM k.c_dec
            AND r.c_evt IS NOT DISTINCT FROM k.c_evt
            AND r.c_bkg IS NOT DISTINCT FROM k.c_bkg
            AND r.c_nrg IS NOT DISTINCT FROM k.c_nrg
            AND (r.c_prop IS NULL OR k.c_prop IS NULL OR r.c_prop = k.c_prop)
            AND (r.c_defr IS NULL OR k.c_defr IS NULL OR r.c_defr = k.c_defr)
            AND (r.c_cal  IS NULL OR k.c_cal  IS NULL OR r.c_cal  = k.c_cal)) AS on9,
           (r.ok AND r.t0 >= fl.rf
            AND r.c_fp  IS NOT DISTINCT FROM k.c_fp
            AND r.c_cmd IS NOT DISTINCT FROM k.c_cmd
            AND r.c_dec IS NOT DISTINCT FROM k.c_dec
            AND r.c_evt IS NOT DISTINCT FROM k.c_evt
            AND r.c_bkg IS NOT DISTINCT FROM k.c_bkg
            AND r.c_nrg IS NOT DISTINCT FROM k.c_nrg
            AND (r.c_prop IS NULL OR k.c_prop IS NULL OR r.c_prop = k.c_prop)
            AND (r.c_defr IS NULL OR k.c_defr IS NULL OR r.c_defr = k.c_defr)
            AND (r.c_cal  IS NULL OR k.c_cal  IS NULL OR r.c_cal  = k.c_cal)
            AND (r.c_rule IS NULL OR k.c_rule IS NULL OR r.c_rule = k.c_rule)
            AND (r.c_rcl  IS NULL OR k.c_rcl  IS NULL OR r.c_rcl  = k.c_rcl)
            AND (r.c_sdr  IS NULL OR k.c_sdr  IS NULL OR r.c_sdr  = k.c_sdr)
            AND (r.c_endst IS NULL OR k.c_endst IS NULL OR r.c_endst = k.c_endst)) AS on14
      FROM ranked r
      JOIN canon k ON k.c_depot=r.c_depot AND k.c_seed=r.c_seed
                  AND k.c_ticks=r.c_ticks AND k.c_scen=r.c_scen
      CROSS JOIN fl
  )
  SELECT c_depot, c_seed, c_ticks, c_scen,
         count(*) FILTER (WHERE u9)::int  AS n9,
         count(*) FILTER (WHERE u14)::int AS n14
    FROM (SELECT m.*, bool_and(m.on9) OVER w AS u9, bool_and(m.on14) OVER w AS u14
            FROM marked m
          WINDOW w AS (PARTITION BY m.c_depot,m.c_seed,m.c_ticks,m.c_scen
                       ORDER BY m.rn ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) x
   GROUP BY 1,2,3,4;

  -- (a) THE REFUSAL: does any column green under nine atoms lose green?
  SELECT string_agg(format('%s/%s/%st depot=%s: green now (streak %s) but '
                           'streak %s after', c_scen, c_seed, c_ticks,
                           left(c_depot::text,8), n9, n14), '; ')
    INTO v_bad
    FROM _0225_streaks
   WHERE n9 >= 2 AND n14 < 2;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0225 P3: extending the comparison would take these columns '
                    'out of green: %. That is a real regression in the '
                    'certification claim, not a bookkeeping change. Investigate '
                    'the disagreeing atom before applying.', v_bad;
  END IF;
  RAISE NOTICE '0225 P3: no green column loses green under the fourteen-atom '
               'comparison';

  -- (b) THE RECORD, printed by A5. P3 proves nothing goes green -> not-green.
  -- It does NOT prove no streak moves, and one will: db/checks/0140 traced
  -- busy_day/314159/12t from six consecutive passes to three, because the
  -- 08:25 pair (pre-0218 h_sdr) becomes off-canon under the wider comparison.
  -- That is a published number changing and this migration is the cause, so it
  -- is captured here while the old comparison still exists.
  SELECT string_agg(format('%s/%s/%st: %s -> %s', c_scen, c_seed, c_ticks, n9, n14),
                    '; ' ORDER BY c_scen, c_seed, c_ticks)
    INTO v_streaks
    FROM _0225_streaks WHERE n9 <> n14;
  ------------------------------------------------------- catalog rewrite ----
  -- Every anchor asserted at exactly one occurrence FIRST, then all five
  -- applied. Counting by length delta rather than by regex so an anchor
  -- containing regex metacharacters cannot be miscounted.
  FOREACH v_bad IN ARRAY ARRAY[a1_old, a2_old, a3_old, a4_old, a5_old] LOOP
    v_n := (length(v_def) - length(replace(v_def, v_bad, ''))) / length(v_bad);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0225: anchor occurs % times, expected exactly 1: %',
                      v_n, left(v_bad, 70);
    END IF;
  END LOOP;

  v_new := v_def;
  v_new := replace(v_new, a1_old, a1_new);
  v_new := replace(v_new, a2_old, a2_new);
  v_new := replace(v_new, a3_old, a3_new);
  v_new := replace(v_new, a4_old, a4_new);
  v_new := replace(v_new, a5_old, a5_new);

  -- The body must have grown by exactly the sum of the five substitution
  -- deltas. Any other number means a replacement hit something the anchor
  -- check did not see.
  IF length(v_new) - v_len_before <>
       (length(a1_new) - length(a1_old)) + (length(a2_new) - length(a2_old))
     + (length(a3_new) - length(a3_old)) + (length(a4_new) - length(a4_old))
     + (length(a5_new) - length(a5_old)) THEN
    RAISE EXCEPTION '0225: body grew by % characters, expected %',
      length(v_new) - v_len_before,
      (length(a1_new) - length(a1_old)) + (length(a2_new) - length(a2_old))
      + (length(a3_new) - length(a3_old)) + (length(a4_new) - length(a4_old))
      + (length(a5_new) - length(a5_old));
  END IF;

  ----------------------------------------------------------------- apply ----
  DROP FUNCTION public.ottoq_cert_matrix(timestamp with time zone);
  EXECUTE v_new;

  ------------------------------------------------------------------ A1 ------
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cert_matrix';

  IF (SELECT count(*) FROM regexp_matches(v_def, 'r\.c_(rule|rcl|sdr|endst)\s+IS NULL', 'g')) <> 4 THEN
    RAISE EXCEPTION '0225 A1: expected 4 new comparisons in the installed body, found %',
      (SELECT count(*) FROM regexp_matches(v_def, 'r\.c_(rule|rcl|sdr|endst)\s+IS NULL', 'g'));
  END IF;
  IF v_def NOT LIKE '%canon_sdr text, canon_endst text)%' THEN
    RAISE EXCEPTION '0225 A1: the return table did not gain canon_sdr/canon_endst';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_def, 'IS NOT DISTINCT FROM', 'g')) <> 6 THEN
    RAISE EXCEPTION '0225 A1: the six strict compares were disturbed';
  END IF;

  ------------------------------------------------------------------ A2 ------
  -- The load-bearing one. Extending a comparison must not retroactively
  -- change any column's verdict, and P3 is the argument that it will not; A2
  -- is the measurement. Recomputed against the snapshot taken before the drop.
  IF EXISTS (SELECT 1 FROM _0225_before b
              FULL JOIN public.ottoq_cert_matrix(now() - interval '30 days') a
                ON a.depot = b.depot AND a.seed = b.seed
               AND a.ticks = b.ticks AND a.scenario = b.scenario
             WHERE a.green IS DISTINCT FROM b.green
                OR a.consecutive_passes IS DISTINCT FROM b.consecutive_passes
                OR a.depot IS NULL OR b.depot IS NULL) THEN
    RAISE EXCEPTION '0225 A2: a column changed green or streak: %',
      (SELECT string_agg(format('%s/%s/%s: %s/%s -> %s/%s', b.scenario, b.seed, b.ticks,
                                b.green, b.consecutive_passes, a.green, a.consecutive_passes), '; ')
         FROM _0225_before b
         FULL JOIN public.ottoq_cert_matrix(now() - interval '30 days') a
           ON a.depot=b.depot AND a.seed=b.seed AND a.ticks=b.ticks AND a.scenario=b.scenario
        WHERE a.green IS DISTINCT FROM b.green
           OR a.consecutive_passes IS DISTINCT FROM b.consecutive_passes
           OR a.depot IS NULL OR b.depot IS NULL);
  END IF;

  ------------------------------------------------------------------ A3 ------
  -- The new clause has teeth, proven on the expression rather than on
  -- history: it must reject a real difference and tolerate a pre-instrument
  -- NULL. Both halves, because either alone is satisfiable by a mistake.
  IF (SELECT (a IS NULL OR b IS NULL OR a = b)
        FROM (SELECT 'aaa'::text AS a, 'bbb'::text AS b) t) THEN
    RAISE EXCEPTION '0225 A3: the NULL-tolerant compare accepted aaa = bbb';
  END IF;
  IF NOT (SELECT (a IS NULL OR b IS NULL OR a = b)
            FROM (SELECT NULL::text AS a, 'bbb'::text AS b) t) THEN
    RAISE EXCEPTION '0225 A3: the NULL-tolerant compare rejected a pre-instrument NULL';
  END IF;

  ------------------------------------------------------------------ A4 ------
  -- The two newly carried atoms must actually arrive non-NULL for the live
  -- flagship columns; 0217 and 0139 both predate the current recert floor, so
  -- a NULL here would mean the extraction expression is wrong rather than that
  -- the data is absent.
  SELECT string_agg(format('%s/%s/%st', scenario, seed, ticks), ', ') INTO v_bad
    FROM public.ottoq_cert_matrix(now() - interval '30 days')
   WHERE depot = '11111111-1111-1111-1111-111111111111'
     AND NOT stale
     AND (canon_sdr IS NULL OR canon_endst IS NULL);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0225 A4: canon_sdr or canon_endst came back NULL for a '
                    'current flagship column (%), which means the extraction '
                    'is wrong, not that the atom is missing', v_bad;
  END IF;

  ------------------------------------------------------------------ A5 ------
  -- Report the streak movement captured in P3. Not an assertion: P3 already
  -- proved no column loses green, and a shortened streak on a column that
  -- stays green is the correct consequence of comparing more atoms, not a
  -- regression. It is printed because it is a published number that this
  -- migration moves, and a number that moves without a stated cause is how
  -- 0134 happened in the first place.
  IF v_streaks IS NULL THEN
    RAISE NOTICE '0225 A5: no column''s consecutive_passes changed';
  ELSE
    RAISE NOTICE '0225 A5: consecutive_passes moved on these columns (expected; '
                 'they compare four more atoms now): %', v_streaks;
  END IF;

  RAISE NOTICE '0225 applied: body % -> %, length % -> %',
               v_pin, md5(v_def), v_len_before, length(v_def);
END $mig$;

-- Register the classification. Written with the UNPREFIXED name, which is what
-- apply_migration writes into supabase_migrations.schema_migrations and
-- therefore what ottoq_cert_recert_floor can join to.
--
-- This row was MISSING from the first draft of this file, and its absence would
-- have been invisible and expensive: with no lineage row, the floor function's
-- COALESCE(l.forces_recert, true) treats the migration as unclassified and
-- jumps the recert floor to this migration's own timestamp — restarting every
-- column's streak in the same apply window in which 0226 fixed exactly that.
-- G28 (db/checks/0135) is what made the omission findable at all; before it,
-- every migration was doing this and nobody could see it.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('the_canon_comparison_sees_every_atom_the_pair_enforces', false,
        'G25 / db/checks/0134. Extends ottoq_cert_matrix so the across-round '
        'comparison judges all fourteen atoms the pair enforces, not nine: '
        'carries c_sdr and c_endst, and moves c_rule and c_rcl from '
        'carried-and-printed to compared. NULL-tolerant in the 0199/0201 form. '
        'ottoq_cert_matrix is a STABLE pure read called by nothing in the '
        'decide path, so no engine behaviour changes and no canon can move; P3 '
        'refuses to apply if any column that is green under the nine-atom '
        'comparison would stop being green under the fourteen-atom one, and '
        'A5 reports every column whose consecutive_passes moves without '
        'losing green (db/checks/0140).',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ---------------------------------------------------------------------------
-- REVISION NOTE — 2026-09-08 15:32 UTC, before this file was ever applied.
--
-- P3 was rewritten. The first draft asserted that every column's newly compared
-- atoms were single-valued at the recert floor. Dry-run against the floor 0226
-- installs (db/checks/0140) that assertion FAILED on two of seven columns, and
-- inspection showed all three of its problems were in P3 rather than in the
-- data: it dropped depot from a key the matrix carries, it judged a fixture
-- scenario, and its bar was stricter than the property it names. It would have
-- refused this migration for a disagreement that costs no column its green.
--
-- The rewrite tests the property directly: no column green under nine atoms
-- stops being green under fourteen.
--
-- **NOT YET DRY-RUN.** The replacement P3 is written but has not been executed
-- against the live catalog — round 27 column f was firing. It must be run
-- read-only, as a standalone SELECT, and seen to return no rows before this
-- migration is applied. Recorded here rather than assumed, because 0140 exists
-- precisely because the previous P3 was never run in the configuration it
-- would meet.
-- ---------------------------------------------------------------------------

