-- scripts/round-report.sql — THE ROUND REPORT, AS A FILE RATHER THAN A HABIT
--
-- WHY THIS EXISTS. Migration 0266 split the certification canon in two and its
-- own comments lean on two post-apply mitigations: "read this beside
-- ottoq_cert_matrix in every round report", and db/checks/0198 "registered as a
-- STANDING check". A review pointed out that neither had a carrier — the phrase
-- "round report" occurred in exactly two files, both of which were asserting
-- that the report existed; there was no template, no script, and nothing in the
-- database or the repo called ottoq_cert_residue at all. A mitigation nobody can
-- run is not a mitigation, and 0266 was relying on two of them.
--
-- So this is the report, as one file, printing everything a round verdict needs
-- in the order it has to be read. It is READ-ONLY: every statement is a SELECT.
-- Run it against otto-q-core after every certification round, and paste the
-- output into db/canons/round<N>.md.
--
-- IT DOES NOT REPLACE db/checks/0198. 0198 is the reasoning; §3 below is its
-- assertion, inlined so the report cannot be run without evaluating it. And it
-- does not replace G12 ("CI runs the SQL"): nothing runs THIS file automatically
-- either. What it changes is that the mitigation is now a command someone can
-- run and a diff someone can review, instead of a sentence in a comment.

\echo '=============================================================='
\echo '1. THE ENGINE COLUMNS — what the reproducibility claim is about'
\echo '=============================================================='
-- consecutive_passes is the number this company quotes. After 0266 it describes
-- the run's OWN end state and twelve other atoms; it no longer moves when
-- another run leaves rows lying around.
SELECT depot, seed, ticks, scenario, pairs_seen, consecutive_passes AS streak,
       green, stale, inconclusive_pairs AS inconc, history,
       last_pair_at, recert_floor
  FROM public.ottoq_cert_matrix(public.ottoq_cert_recert_floor())
 ORDER BY depot, ticks DESC, scenario, seed;

\echo ''
\echo '=============================================================='
\echo '2. THE RESIDUE COLUMNS — hygiene, NOT determinism'
\echo '=============================================================='
-- A break here means OTHER runs left different rows in live states between the
-- rounds. It is a G13 janitor finding. It is NOT evidence about the engine, and
-- its number may never be quoted as the engine's: measured across 446 pairs, the
-- two arms of a certification agree on these sections in 100% of them, so they
-- have never once been evidence about reproducibility.
-- 'S' = equal to canon, '.' = moved, '-' = below the recert floor, not judged.
SELECT depot, seed, ticks, scenario, pairs_seen, consecutive_same AS streak,
       sections_moved, history, last_pair_at
  FROM public.ottoq_cert_residue(public.ottoq_cert_recert_floor())
 ORDER BY depot, ticks DESC, scenario, seed;

\echo ''
\echo '=============================================================='
\echo '3. THE SHAPE — db/checks/0198, inlined so it cannot be skipped'
\echo '=============================================================='
-- EMPTY RESULT = HEALTHY. Any row means public.ottoq_boot_state_fingerprint has
-- outgrown the key lists that ottoq_cert_matrix (7 paths) and
-- ottoq_cert_residue (4 paths) enumerate — so an atom is streaked by NEITHER
-- while ottoq_determinism_pair goes on enforcing it. That is the G25/G28 defect,
-- and the pair verdict cannot catch it: the arms agree on every section, so a
-- key equal WITHIN a pair and moving BETWEEN rounds is invisible to any
-- arm-vs-arm check.
-- IF THIS RETURNS ROWS: do not widen the lists silently. The new key is a new
-- atom and gets the blind-spot promotion (CLAUDE.md 2.9a) — MEASURED first,
-- ENFORCED only after a flagship round shows the arms agree on it.
WITH pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at)
         r.depot_id, r.started_at, (r.validation_notes::jsonb)->'arm_a'->'endst' AS e
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness' AND r.validation_notes IS NOT NULL
     AND r.validation_status IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a') = 'object'
     AND (r.validation_notes::jsonb)->'arm_a' ? 'endst'
     AND r.started_at >= public.ottoq_cert_recert_floor()
     AND (r.validation_notes::jsonb ->> 'replay') IS NULL
     AND COALESCE((r.validation_notes::jsonb->'arm_a'->>'replay_injected')::int, 0) = 0
     AND COALESCE((r.validation_notes::jsonb->'arm_b'->>'replay_injected')::int, 0) = 0
   ORDER BY r.depot_id, r.started_at, r.sim_run_id)
SELECT depot_id, started_at,
       (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k) AS top_keys
  FROM pair
 WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k)
         IS DISTINCT FROM ARRAY['bookings','calibration','chargers','dispatches','legs','visit_needs','world']
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'visit_needs') k) IS DISTINCT FROM ARRAY['fgn','vis']
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'bookings') k)    IS DISTINCT FROM ARRAY['fgn','vis']
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'legs') k)        IS DISTINCT FROM ARRAY['fgn','vis']
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'dispatches') k)  IS DISTINCT FROM ARRAY['fgn','vis'];

\echo ''
\echo '=============================================================='
\echo '4. THE FINGERPRINT ITSELF — fires before the next round, not after'
\echo '=============================================================='
-- §3 reads what pairs have ALREADY recorded, so it only fires once a pair has
-- run under a changed fingerprint. This reads the source, so it fires the moment
-- the function changes. A mismatch is not automatically a fault — it means the
-- key lists in both instruments and in db/checks/0198 must be re-derived in the
-- same change that changed the fingerprint.
SELECT p.proname, md5(p.prosrc) AS prosrc_md5,
       (md5(p.prosrc) = '90d490c24ae084d03477a8a782a9f856') AS matches_the_0266_pin
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_boot_state_fingerprint';

\echo ''
\echo '=============================================================='
\echo '5. REPLAY PAIRS — excluded from every number above (G48)'
\echo '=============================================================='
-- A replay pair asks a different question from a certification and is kept out
-- of the canon by 0266. Printed here so "excluded" stays visible rather than
-- silent: a replay that ran and was correctly ignored should still be known to
-- have run.
SELECT (j->>'scenario')||'/'||(j->>'seed')||'/'||(j->>'ticks')||'t' AS col,
       (j->>'replay')                                       AS replay_id,
       (j->'arm_a'->>'replay_injected')                     AS injected_a,
       (j->'arm_b'->>'replay_injected')                     AS injected_b,
       vs                                                   AS verdict,
       t0                                                   AS at_utc,
       (t0 >= public.ottoq_cert_recert_floor())             AS above_floor
  FROM (SELECT DISTINCT ON (r.depot_id, r.started_at)
               r.started_at t0, r.validation_status vs, (r.validation_notes::jsonb) j
          FROM public.ottoq_sim_runs r
         WHERE r.run_by='cert_harness' AND r.validation_notes IS NOT NULL
           AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
           AND (r.validation_notes::jsonb) ? 'replay'
         ORDER BY r.depot_id, r.started_at, r.sim_run_id) q
 ORDER BY t0;

\echo ''
\echo 'HOW TO READ THIS. The engine streak (§1) is the reproducibility claim and'
\echo 'the only one that may be quoted as such. The residue streak (§2) is a'
\echo 'hygiene number. §3 and §4 must both be clean or the split has stopped'
\echo 'covering the atom set the pair enforces. §5 must contain nothing above the'
\echo 'recert floor that was not deliberately run as a replay.'
