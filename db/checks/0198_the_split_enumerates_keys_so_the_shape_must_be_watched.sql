-- 0198  THE SPLIT ENUMERATES KEYS, SO THE SHAPE MUST BE WATCHED
--
-- STANDING CHECK. Run it in every round report, beside ottoq_cert_matrix and
-- ottoq_cert_residue. It exists because migration 0266 traded one property for
-- another and the trade is only safe while this check is run.
--
-- ITS CARRIER IS scripts/round-report.sql §3, which inlines C1 below so the round
-- report cannot be produced without evaluating it. That carrier exists because a
-- review asked the right question about this file -- is a standing check nobody
-- is scheduled to run a real mitigation, or a comfort? -- and the honest answer
-- at the time was: a comfort. Nothing in this repo or the database ran db/checks
-- at all. It is now at least a command someone runs and a diff someone reviews.
-- It is still not automation: that is task G12, "CI runs the SQL".
--
-- WHAT WAS TRADED. Before 0266 the canon's end-state atom was
--     md5((arm_a->'endst')::text)
-- one opaque digest over the WHOLE object. That expression covers every key the
-- fingerprint emits BY CONSTRUCTION: it cannot miss one, ever, because it never
-- names one. 0266 replaced it with two digests that each ENUMERATE their keys --
-- seven paths in ottoq_cert_matrix, four in ottoq_cert_residue -- because that is
-- what splitting the run's own end state from other runs' residue requires.
--
-- THE COST, NAMED PLAINLY: an enumerated list is exactly the thing that drifts.
-- If public.ottoq_boot_state_fingerprint ever gains an eighth top-level key, or a
-- third sub-key under one of the four sections, that atom is streaked by NEITHER
-- instrument. It leaves the canon silently, while ottoq_determinism_pair goes on
-- enforcing it inside the whole-object comparison -- the comparison becoming
-- narrower than the enforcement, which is precisely the G25/G28 defect.
--
-- AND THE PAIR VERDICT CANNOT COVER FOR IT. The obvious hope is that the arms
-- would disagree and the pair would fail. They will not: measured across all 446
-- pairs carrying endst, the arms agree on every section (db/checks/0196 M2). A
-- new key that is equal WITHIN a pair and moves BETWEEN rounds is G46's own
-- failure class wearing a different name, and an arm-vs-arm check is blind to it
-- by construction.
--
-- 0266's assertion A9 closes this at APPLY TIME. This file closes it AFTERWARDS,
-- which is where the risk actually lives: the fingerprint is a live function that
-- a later migration can extend, and nothing in the database forces whoever
-- extends it to revisit two key lists in two other functions.
--
-- IF THIS CHECK FAILS: do not "fix" it by widening the lists silently. The new
-- key is a new atom, and the blind-spot promotion doctrine (CLAUDE.md 2.9a)
-- applies to it as it did to endst, h_nrg and the rest -- MEASURED first, and
-- ENFORCED only after a flagship round shows the arms agree on it.

-- ---------------------------------------------------------------------------
-- C1. THE SHAPE, AS THE TWO INSTRUMENTS ASSUME IT. Empty result = healthy.
--     Any row means endst has outgrown the key lists in ottoq_cert_matrix
--     (c_endst) and/or ottoq_cert_residue (c_fgn).
-- ---------------------------------------------------------------------------
WITH pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at)
         r.depot_id, r.started_at, (r.validation_notes::jsonb)->'arm_a'->'endst' AS e
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness' AND r.validation_notes IS NOT NULL
     AND r.validation_status IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a') = 'object'
     AND (r.validation_notes::jsonb)->'arm_a' ? 'endst'
     AND r.started_at >= public.ottoq_cert_recert_floor()
     --: The G48 predicate, so this walks the same population the canon does.
     AND (r.validation_notes::jsonb ->> 'replay') IS NULL
     AND COALESCE((r.validation_notes::jsonb->'arm_a'->>'replay_injected')::int, 0) = 0
     AND COALESCE((r.validation_notes::jsonb->'arm_b'->>'replay_injected')::int, 0) = 0
   ORDER BY r.depot_id, r.started_at, r.sim_run_id)
SELECT depot_id, started_at,
       (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k)                 AS top_keys,
       (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'visit_needs') k)  AS visit_needs_keys,
       (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'bookings') k)     AS bookings_keys,
       (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'legs') k)         AS legs_keys,
       (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'dispatches') k)   AS dispatches_keys
  FROM pair
 WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k)
         IS DISTINCT FROM ARRAY['bookings','calibration','chargers','dispatches','legs','visit_needs','world']
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'visit_needs') k)
         IS DISTINCT FROM ARRAY['fgn','vis']
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'bookings') k)
         IS DISTINCT FROM ARRAY['fgn','vis']
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'legs') k)
         IS DISTINCT FROM ARRAY['fgn','vis']
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e->'dispatches') k)
         IS DISTINCT FROM ARRAY['fgn','vis'];
-- MEASURED 2026-09-13, before 0266 was applied: 0 rows over 30 post-floor pairs.
-- The live shape is exactly ARRAY['bookings','calibration','chargers',
-- 'dispatches','legs','visit_needs','world'] with {fgn,vis} under each of the
-- four sections.

-- ---------------------------------------------------------------------------
-- C2. THE OTHER END OF THE SAME RISK: the fingerprint FUNCTION itself. C1 reads
--     what pairs have already recorded, so it only fires once a pair has run
--     under a changed fingerprint. This reads the source, so it fires the moment
--     the function is changed -- before the next round, not after it.
--
--     The md5 is 0266's A8 pin. A mismatch is NOT automatically a fault: it
--     means somebody changed the fingerprint, which is allowed. It means the two
--     key lists must be re-derived and this file's ARRAY literals updated in the
--     same change, and the new atom promoted MEASURED-then-ENFORCED.
-- ---------------------------------------------------------------------------
SELECT p.proname,
       md5(p.prosrc)                                    AS prosrc_md5,
       (md5(p.prosrc) = '90d490c24ae084d03477a8a782a9f856') AS matches_the_0266_pin,
       --: The seven top-level keys, read straight out of the body, so a reader
       --: can see the source of truth beside the assumption.
       (SELECT count(*) FROM regexp_matches(p.prosrc, '''(visit_needs|bookings|legs|dispatches|chargers|calibration|world)'',\s*jsonb_build_object', 'g')) AS sections_built
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_boot_state_fingerprint';

-- ---------------------------------------------------------------------------
-- C3. AND THE CONSUMERS, so the three places that must agree are visible at
--     once: the fingerprint emits, the matrix enumerates seven, the residue
--     enumerates four. Each name should appear in exactly the instrument that
--     is supposed to carry it.
-- ---------------------------------------------------------------------------
SELECT p.proname,
       (position('''visit_needs'', p.j->''arm_a''->''endst''->''visit_needs''->''vis''' in p.prosrc) > 0) AS matrix_takes_vis,
       (position('''visit_needs'', p.j->''arm_a''->''endst''->''visit_needs''->''fgn''' in p.prosrc) > 0) AS residue_takes_fgn,
       (position('''chargers''' in p.prosrc) > 0)    AS mentions_chargers,
       (position('''calibration''' in p.prosrc) > 0) AS mentions_calibration,
       (position('''world''' in p.prosrc) > 0)       AS mentions_world
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname IN ('ottoq_cert_matrix', 'ottoq_cert_residue')
 ORDER BY 1;
-- EXPECTED after 0266: ottoq_cert_matrix true/false/true/true/true,
--                      ottoq_cert_residue false/true/false/false/false.
-- The world keys belong to the OWN half only; if the residue ever mentions them
-- the split has been drawn twice and one of the two digests is double-counting.
