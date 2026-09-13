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
-- MEASURED 2026-09-13:
--   busy_day/314159/12t  | failed | 2 arm runs | 1 pair | 2026-09-09 | above_floor FALSE
--   busy_day/314159/12t  | passed | 4 arm runs | 2 pairs| 2026-09-09 | above_floor FALSE
--   grid_smoke/239001/6t | passed |12 arm runs | 6 pairs| 2026-09-09 | above_floor FALSE
-- Nine pairs in total, all on 2026-09-09, all BELOW the current recert floor
-- (2026-09-12 16:50:23.319089). That is the only reason today's canon is clean.

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
--   * In ottoq_cert_matrix's `pair` CTE, exclude verdicts carrying the replay
--     marker:  AND (r.validation_notes::jsonb ->> 'replay_injected') IS NULL
--     (confirm the key's exact spelling from §3 before writing it -- it is matched
--     here as text, which is evidence of presence, not of shape).
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
