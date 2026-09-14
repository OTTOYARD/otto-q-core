-- ---------------------------------------------------------------------------
-- 0190 — G48: THE CANON MATRIX CANNOT TELL A REPLAY PAIR FROM A CERTIFICATION,
-- ALTHOUGH THE VERDICT SAYS SO IN PLAIN TEXT.
--
-- Found 2026-09-13 05:20 UTC while preparing the record-and-replay proof the D3
-- demo still owes (Posture B, migrations 0237/0239): before running a replay pair
-- I asked what key it would land on, and the answer is "a certification column's".
--
-- ottoq_determinism_pair_replay(seed, ticks, scenario, depot, sim_start, budget,
-- replay_id) creates its arms exactly like the certification pair does -- SAME
-- run_by = 'cert_harness', SAME validation_notes shape with an arm_a object --
-- and then injects a captured proposal stream into both arms. ottoq_cert_matrix
-- selects on run_by='cert_harness' AND jsonb_typeof(arm_a)='object', so a replay
-- pair is indistinguishable from a certification pair to the instrument that
-- decides whether a column is green. Its verdict even carries the marker
-- ('replay_injected') the matrix would need -- and does not read.
-- ---------------------------------------------------------------------------

-- 1. IT HAS ALREADY HAPPENED. Nine replay pairs, on two canon columns, one of
--    them FAILED -- and a failed pair is an 'f' in that column's history.
SELECT (r.validation_notes::jsonb->>'scenario')||'/'||(r.validation_notes::jsonb->>'seed')
         ||'/'||(r.validation_notes::jsonb->>'ticks')||'t'        AS col,
       r.validation_status,
       count(*)                                                  AS arm_runs,
       count(DISTINCT r.started_at)                              AS pairs,
       min(r.started_at)::date                                   AS first,
       max(r.started_at)::date                                   AS last,
       (min(r.started_at) >= public.ottoq_cert_recert_floor())    AS above_floor
  FROM public.ottoq_sim_runs r
 WHERE r.run_by = 'cert_harness' AND r.validation_notes::text LIKE '%replay_injected%'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- MEASURED 2026-09-13 (text match on 'replay_injected'):
--   busy_day/314159/12t  | failed | 2 arm runs | 1 pair | 2026-09-09 | above_floor FALSE
--   busy_day/314159/12t  | passed | 4 arm runs | 2 pairs| 2026-09-09 | above_floor FALSE
--   grid_smoke/239001/6t | passed |12 arm runs | 6 pairs| 2026-09-09 | above_floor FALSE
-- Nine pairs carry the marker, all on 2026-09-09, all BELOW the current recert
-- floor (2026-09-12 16:50:23.319089). That is the only reason today's canon is clean.
--
-- CORRECTION, and it matters for the predicate (measured 05:40 UTC, §4 below):
-- NINE pairs carry the replay KEY but only SEVEN actually injected anything. Two
-- are zero-injection controls -- run through the replay function with no stream --
-- and those two are honest certification data. Of the seven real replays, ONE
-- failed (busy_day/314159/12t at 05:24; the same replay_id passed at 05:50). So the
-- sentence is "seven replay pairs, one of which failed, plus two controls", not
-- "nine replay pairs".

-- 2. AND THE MATRIX COUNTS THEM. Read the matrix from before the floor and the
--    replay pairs appear in pairs_seen and as 'f' in history.
WITH m AS (SELECT * FROM public.ottoq_cert_matrix('2026-09-09 00:00:00+00'::timestamptz))
SELECT scenario, seed, ticks, pairs_seen, consecutive_passes, green, history
  FROM m ORDER BY ticks DESC, scenario, seed;
-- MEASURED: busy_day/314159/12t -> pairs_seen 16, history 'PfPPfPPfPPPPPPPP'.
-- Three of those four 'f's are replay pairs, not certification failures. Every
-- other flagship column reads 11 pairs and one 'f'; grid_smoke/239001/6t reads 13.
-- Compare the same matrix from the current floor: 3 pairs per flagship column,
-- history 'PPP', no f at all. The difference is entirely replay pairs and pre-floor
-- history.

-- 3. THE MARKER THE MATRIX DOES NOT READ. It is right there in the verdict.
SELECT to_char(r.started_at,'MM-DD HH24:MI')                     AS at_utc,
       r.validation_status,
       substring(r.validation_notes FROM 'replay[^,"}]*')         AS marker,
       jsonb_typeof(r.validation_notes::jsonb->'arm_a')           AS arm_a_type,
       r.run_by
  FROM public.ottoq_sim_runs r
 WHERE r.run_by='cert_harness' AND r.validation_notes::text LIKE '%replay_injected%'
 ORDER BY r.started_at LIMIT 4;
-- MEASURED: marker 'replay_injected' on every row; arm_a_type 'object';
-- run_by 'cert_harness'. The instrument has everything it needs to exclude them
-- and excludes nothing.

-- 4. THE EXACT SHAPE, because the predicate depends on it and a near-miss here
--    would silently drop honest certification pairs.
SELECT to_char(started_at,'MM-DD HH24:MI')                                  AS at_utc,
       (validation_notes::jsonb->>'replay')                                 AS replay_id,
       (validation_notes::jsonb->'arm_a'->>'replay_injected')               AS arm_a_injected,
       (validation_notes::jsonb->'arm_b'->>'replay_injected')               AS arm_b_injected,
       validation_status,
       (validation_notes::jsonb->>'scenario')||'/'||(validation_notes::jsonb->>'seed')
         ||'/'||(validation_notes::jsonb->>'ticks')||'t'                     AS col
  FROM public.ottoq_sim_runs
 WHERE run_by='cert_harness' AND validation_notes IS NOT NULL
   AND jsonb_typeof((validation_notes::jsonb)->'arm_a')='object'
   AND (validation_notes::jsonb ? 'replay')
 ORDER BY started_at;
-- MEASURED 2026-09-13 05:40 UTC, 18 arm runs = 9 pairs:
--   `replay` is a TOP-LEVEL key holding the replay_id uuid, and it is PRESENT WITH
--   A NULL VALUE on a control pair. The injected count lives per arm as
--   arm_a/arm_b -> 'replay_injected'.
--     09-09 03:24  replay_id NULL                 injected 0/0   passed  grid/239001/6t
--     09-09 03:26  0239aaaa-...0001               injected 24/24 passed  grid/239001/6t  (x2 pairs)
--     09-09 03:26  0239aaaa-...0002               injected 24/24 passed  grid/239001/6t
--     09-09 03:27  0239aaaa-...0003               injected 24/24 passed  grid/239001/6t
--     09-09 05:24  01590000-...00cc               injected 5/5   FAILED  busy/314159/12t
--     09-09 05:40  replay_id NULL                 injected 0/0   passed  busy/314159/12t
--     09-09 05:50  01590000-...00cc               injected 5/5   passed  busy/314159/12t
--     09-09 09:55  0239aaaa-...0001               injected 24/24 passed  grid/239001/6t
--   Out of 1,000 pair-verdict arm runs since 2026-08-30, exactly 18 carry the key
--   and 14 carry a non-null replay_id. Both arms of every pair always agree on the
--   injected count, which is the replay rig working correctly.

-- ---------------------------------------------------------------------------
-- WHY THIS MATTERS MORE THAN IT LOOKS
--
-- A replay pair asks a DIFFERENT QUESTION from a certification pair. The
-- certification asks "does the deterministic core reproduce itself byte for
-- byte?" with the proposers quiesced (0152). The replay asks "can a
-- NONDETERMINISTIC proposer's recorded stream be re-consumed identically?" with
-- proposals deliberately injected. Their h_prop atoms are therefore supposed to
-- differ, and a replay pair that fails is telling you something about the replay
-- mechanism, not about the core.
--
-- Mixing them has two failure modes, and the second is the dangerous one:
--   (a) A failing replay pair reads as a certification failure and breaks a
--       column's streak -- noise that costs a round.
--   (b) A PASSING replay pair becomes the column's CANON (the matrix takes the
--       newest pair), so the canon's h_prop silently becomes the injected
--       stream's hash. Every later certification pair then disagrees with it --
--       correctly -- and the column reads as a regression in the engine. That is
--       G46's silent-rebase failure with a different cause and a worse story.
--
-- Nothing prevents either today. The protection is coincidence: the nine existing
-- replay pairs predate the recert floor.
--
-- THE FIX IS ONE PREDICATE, and it belongs in the same migration as G46's
-- (db/checks/0187) because it is the same function, the same round, and the same
-- recert conversation:
--
--   * In ottoq_cert_matrix's `pair` CTE, exclude verdicts that CONSUMED an injected
--     stream. The shape is now measured (§4), so the predicate is exact:
--
--       AND (r.validation_notes::jsonb ->> 'replay') IS NULL
--       AND COALESCE((r.validation_notes::jsonb -> 'arm_a' ->> 'replay_injected')::int, 0) = 0
--
--     Both clauses, deliberately: the first excludes a pair that names a replay_id,
--     the second survives a future replay that forgets to. Note what they do NOT
--     exclude -- the two zero-injection control pairs, which are honest
--     certification data and must stay in the canon. A predicate of the form
--     `? 'replay'` would wrongly drop them, because the key is PRESENT with a null
--     value on a control.
--   * Better, additionally: give replay pairs their own run_by ('replay_harness')
--     so the exclusion does not depend on a jsonb key at all. That is a change to
--     ottoq_determinism_pair_replay, which means an md5 pin and a reversal
--     assertion, and it must not disturb the certification pair it shares code with.
--   * And ottoq_cert_coverage should then report replay pairs separately rather
--     than not at all: a replay that has not run in N days is its own kind of
--     stale, and Posture B's claim rests on it.
--
-- UNTIL THIS LANDS: the D3 replay proof must NOT use a canon column's
-- (depot, seed, ticks, scenario). Use a dedicated seed so the pair cannot touch a
-- canon, and say in the demo notes that the isolation was deliberate.
-- ---------------------------------------------------------------------------
