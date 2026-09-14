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
       --: The denominator, carried on every row so the verdict is never read
       --: without the population it was measured over.
       (SELECT count(*) FROM pair)                                                  AS post_floor_pairs_examined,
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
-- 0 ROWS IS NOT THE SAME AS HEALTHY, and the difference matters most exactly
-- when this check is most needed. C1 reads RECORDED pairs above the recert
-- floor, so it returns nothing when the shape is fine AND when there are no
-- post-floor pairs at all. After any forces_recert migration the floor jumps to
-- that migration and the population is EMPTY until a round runs -- which is
-- precisely the window in which a fingerprint change is most likely to have just
-- landed. Read the population count printed below beside the verdict: 0 rows out
-- of 0 pairs is UNKNOWN, not clean. C2 is the half that still works in that
-- window, because it reads the function source rather than recorded output; when
-- C1's population is 0, C2 is the line to trust.
--
-- MEASURED 2026-09-13, before 0266 was applied: 0 rows over 30 post-floor pairs.
-- The live shape is exactly ARRAY['bookings','calibration','chargers',
-- 'dispatches','legs','visit_needs','world'] with {fgn,vis} under each of the
-- four sections.

-- C1b. THE POPULATION, PRINTED UNCONDITIONALLY. C1 above returns nothing when
--      healthy, so it cannot tell you what it looked at. This can.
SELECT count(*) AS post_floor_pairs_examined,
       min(started_at) AS oldest, max(started_at) AS newest,
       public.ottoq_cert_recert_floor() AS recert_floor,
       (count(*) = 0) AS verdict_is_UNKNOWN_not_clean
  FROM (SELECT DISTINCT ON (r.depot_id, r.started_at) r.depot_id, r.started_at
          FROM public.ottoq_sim_runs r
         WHERE r.run_by = 'cert_harness' AND r.validation_notes IS NOT NULL
           AND r.validation_status IS NOT NULL
           AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a') = 'object'
           AND (r.validation_notes::jsonb)->'arm_a' ? 'endst'
           AND r.started_at >= public.ottoq_cert_recert_floor()
           AND (r.validation_notes::jsonb ->> 'replay') IS NULL
           AND COALESCE((r.validation_notes::jsonb->'arm_a'->>'replay_injected')::int, 0) = 0
           AND COALESCE((r.validation_notes::jsonb->'arm_b'->>'replay_injected')::int, 0) = 0
         ORDER BY r.depot_id, r.started_at, r.sim_run_id) p;

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

-- ---------------------------------------------------------------------------
-- C4. THE DOOR THE SPLIT DOES NOT CLOSE (0193 blocker (i), which survives).
--
--     ADDED after a reviewer showed that 0266's header claimed every blocker
--     from db/checks/0193 was "void by construction". Blocker (i) is not: it held
--     that the run's OWN digest is not residue-independent because it hashes
--     run-UNTAGGED state, and 0196 M3 answers that only for the four row-sections.
--     `chargers`, `calibration` and `world` have no run filter at all, and the
--     split KEEPS all three inside c_endst.
--
--     MEASURED over 30 days rather than the 11-hour post-floor window M1 used,
--     the untagged half is the MORE volatile one:
--
--         column (flagship)      chargers  calibration  world  legs.fgn
--         314159/12t busy_day       15          1         2       6
--         171717/12t normal_day     12          1         2       6
--         171717/24t busy_day       14          1         2       6
--         171717/48t busy_day        5          1         7       4
--
--     `chargers` hashes ottoq_ocpp_chargers at the depot including station_state
--     and last_heartbeat_at, which the metronome moves every minute. M1 showed 1
--     only because all 30 post-floor pairs fell inside one quiet window.
--
--     THIS IS NOT AN ARGUMENT TO MOVE THEM OUT. Charger and world state is what
--     the run ENDED IN and belongs to its own end state; 0244 put `world` there
--     deliberately so two arms ending in different fleet states could not pass.
--     It is an argument that a canon rebase through this door must be
--     ATTRIBUTABLE rather than mysterious -- which is exactly the complaint that
--     started G46.
-- ---------------------------------------------------------------------------
WITH pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at)
         r.depot_id, r.started_at, (r.validation_notes::jsonb) AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness' AND r.validation_notes IS NOT NULL
     AND r.validation_status IS NOT NULL AND r.validation_status <> 'inconclusive'
     AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a') = 'object'
     AND (r.validation_notes::jsonb)->'arm_a' ? 'endst'
     AND r.started_at >= public.ottoq_cert_recert_floor()
     AND (r.validation_notes::jsonb ->> 'replay') IS NULL
     AND COALESCE((r.validation_notes::jsonb->'arm_a'->>'replay_injected')::int, 0) = 0
     AND COALESCE((r.validation_notes::jsonb->'arm_b'->>'replay_injected')::int, 0) = 0
   ORDER BY r.depot_id, r.started_at, r.sim_run_id)
SELECT depot_id,
       (j->>'scenario')||'/'||(j->>'seed')||'/'||(j->>'ticks')||'t' AS col,
       count(*)                                                     AS pairs,
       count(DISTINCT (j->'arm_a'->'endst'->'chargers')::text)       AS chargers_values,
       count(DISTINCT (j->'arm_a'->'endst'->'calibration')::text)    AS calibration_values,
       count(DISTINCT (j->'arm_a'->'endst'->'world')::text)          AS world_values,
       --: More than one value in ANY of these three means the canon moved for a
       --: reason that is NOT the engine's own rows and NOT the foreign residue
       --: the split relocated -- the third door, which nothing else reports.
       (count(DISTINCT (j->'arm_a'->'endst'->'chargers')::text) > 1
        OR count(DISTINCT (j->'arm_a'->'endst'->'calibration')::text) > 1
        OR count(DISTINCT (j->'arm_a'->'endst'->'world')::text) > 1)  AS untagged_half_moved
  FROM pair
 GROUP BY 1, 2
 ORDER BY 1, 2;

-- ---------------------------------------------------------------------------
-- C4b. AND THE PREMISE OF M3 ITSELF, counted rather than assumed.
--      0196 M3 measured zero untagged rows database-wide and stated explicitly
--      that this is an OBSERVATION, not a guarantee. 0266's first draft restated
--      it as fact. Two of the four tables are still NULLABLE, so the observation
--      can stop being true without anything raising:
--          ottoq_itinerary_legs.sim_run_id     NOT NULL
--          ottoq_stall_bookings.sim_run_id     NOT NULL
--          ottoq_visit_needs.sim_run_id        NULLABLE
--          ottoq_vehicle_dispatches.sim_run_id NULLABLE
--      A NULL-tagged row lands in `vis` -- the run's OWN half -- and rebases the
--      canon exactly as the nine legs did. EXPECT ZERO IN EVERY COLUMN.
-- ---------------------------------------------------------------------------
SELECT 'visit_needs' AS tbl, count(*) FILTER (WHERE sim_run_id IS NULL) AS untagged,
       count(*) AS total FROM public.ottoq_visit_needs
UNION ALL SELECT 'bookings',   count(*) FILTER (WHERE sim_run_id IS NULL), count(*)
            FROM public.ottoq_stall_bookings
UNION ALL SELECT 'legs',       count(*) FILTER (WHERE sim_run_id IS NULL), count(*)
            FROM public.ottoq_itinerary_legs
UNION ALL SELECT 'dispatches', count(*) FILTER (WHERE sim_run_id IS NULL), count(*)
            FROM public.ottoq_vehicle_dispatches;
