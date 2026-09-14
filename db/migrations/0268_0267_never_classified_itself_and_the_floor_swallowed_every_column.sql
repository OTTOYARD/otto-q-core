-- migration-version: 20260913142959
-- migration-name:    0268_0267_never_classified_itself_and_the_floor_swallowed_every_column
--
-- 0268  0267 NEVER CLASSIFIED ITSELF, AND THE FLOOR SWALLOWED EVERY COLUMN
--
-- ---------------------------------------------------------------------------
-- WHAT HAPPENED, AND IT IS THE MACHINERY WORKING
--
-- 0267 applied at 2026-09-13 14:14:38 UTC and did NOT insert a row into
-- public.ottoq_cert_lineage. Per 0142 ("a migration classifies itself") an
-- unclassified migration is treated as forcing recertification, so
-- ottoq_cert_recert_floor() moved:
--
--   before 0267   2026-09-12 16:50:23.319089+00
--   after  0267   2026-09-13 14:14:38+00      <- 0267's own apply time
--
-- No pair has run since 14:14:38, so BOTH instruments went dark:
--   ottoq_cert_matrix(floor)   -> 0 rows   (9 at the old floor)
--   ottoq_cert_residue(floor)  -> 0 rows
--
-- THIS IS NOT A BUG IN THE FLOOR. It is the floor doing exactly its job, and it
-- caught my omission within ten minutes: 0266 carried its lineage row in
-- section 3 and I did not carry the pattern across to 0267. Recorded rather
-- than quietly fixed, because "the instrument went silent and I assumed the
-- data was gone" is the failure mode db/checks/0193 finding 4 already convicted
-- once (an inconclusive pair is invisible, not red). The first thing I checked
-- was whether the purge had eaten the pairs. It had not: 892 cert pairs still
-- carry endst, and ottoq_sim_runs is not in the retention allowlist, so no run
-- header was ever at risk.
--
-- WHY forces_recert = false, argued rather than assumed:
--   * 0267 added ONE foreign key to public.ottoq_proposer_fire_log. It changes
--     no function, no fingerprint, no decide-path behaviour.
--   * A constraint on that table cannot alter any of the fourteen atoms. It
--     constrains INSERTs into the fire log, and the fire log is written by the
--     proposer bridge OUTSIDE the tick -- and a certification runs the
--     deterministic core alone with the proposer quiesced (0152), so no fire-log
--     row is written during a pair at all.
--   * Nothing an arm produces can differ. That is the same test 0266 was
--     classified under, and it is the only test that matters here.
--
-- ONE THING THIS IS NOT. The floor's join STRIPS a leading NNNN_ prefix from
-- both the lineage name and the ledger name (0226, for db/checks/0135), so the
-- separate 0266 slip recorded in db/checks/0199 -- its ledger row registered
-- without its 0NNN_ prefix -- never affected the floor at all. That was a
-- scripts/check-drift.sql Section C defect. This is a missing row. Same
-- afternoon, same table family, two unrelated faults, and conflating them would
-- send the next reader looking in the wrong place.
--
-- AND THE RESTORED FLOOR IS WHAT MAKES ROUND 42 MEAN ANYTHING. db/checks/0196
-- makes an observed purge pass the precondition for round 42, and the purge ran
-- to completion at 14:25 UTC (7,300,205 rows, db/checks/0201). The test it sets
-- up is a CONTINUITY test: the engine columns must still match canons recorded
-- BEFORE the purge, while the residue column moves. With the floor sitting at
-- 14:14:38 every column would start a fresh streak and round 42 would prove
-- nothing at all -- a green matrix with no history behind it. Leaving the floor
-- moved would not be the cautious choice; it would be the one that destroys the
-- evidence.
-- ---------------------------------------------------------------------------

DO $p$
DECLARE v_busy int; v_jobs int; v_live int;
BEGIN
  SELECT count(*) INTO v_busy FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_sim_advance_tick%'
          OR query ILIKE '%ottoq_ab_pair%');
  IF v_busy > 0 THEN
    RAISE EXCEPTION '0268 P: % certification/pair call(s) in flight', v_busy;
  END IF;
  SELECT count(*) INTO v_jobs FROM cron.job
   WHERE (jobname ~ '^r[0-9]+_')
      OR (active AND (command ILIKE '%ottoq_determinism_pair%'
                      OR command ILIKE '%ottoq_cert_battery_step%'));
  IF v_jobs > 0 THEN
    RAISE EXCEPTION '0268 P: % certification job(s) still scheduled', v_jobs;
  END IF;
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_live > 0 THEN
    RAISE EXCEPTION '0268 P: % run(s) running or paused', v_live;
  END IF;
END $p$;

-- ---------------------------------------------------------------------------
-- G. THE PRE-IMAGE. The floor must be AT 0267's apply time and the matrix must
--    be EMPTY -- i.e. the defect this file fixes must actually be present. If
--    somebody classified 0267 in between, this file has nothing to do and must
--    say so rather than silently re-stamping a classification.
-- ---------------------------------------------------------------------------
DO $g$
DECLARE v_rf timestamptz; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage
   WHERE name = '0267_the_fire_log_registered_a_stamp_and_never_bound_it_to_a_run';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0268 G: 0267 already carries a lineage row; nothing to classify';
  END IF;

  v_rf := public.ottoq_cert_recert_floor();
  IF v_rf <> '2026-09-13 14:14:38+00'::timestamptz THEN
    RAISE EXCEPTION '0268 G: recert floor is %, expected 0267''s apply time 2026-09-13 14:14:38+00 -- the premise of this file is wrong', v_rf;
  END IF;

  SELECT count(*) INTO v_n FROM public.ottoq_cert_matrix(v_rf);
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0268 G: matrix returns % column(s) at the moved floor, expected 0', v_n;
  END IF;

  --: AND THE COLUMNS ARE STILL THERE UNDERNEATH, at the floor 0267 displaced.
  --: This is the fact that distinguishes "the floor moved" from "the purge ate
  --: the evidence", and it is asserted rather than remembered.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_matrix('2026-09-12 16:50:23.319089+00'::timestamptz);
  IF v_n <> 9 THEN
    RAISE EXCEPTION '0268 G: only % column(s) survive at the pre-0267 floor, expected 9 -- this is NOT a classification problem', v_n;
  END IF;
END $g$;

-- ---------------------------------------------------------------------------
-- 1. THE CLASSIFICATION 0267 SHOULD HAVE CARRIED.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0267_the_fire_log_registered_a_stamp_and_never_bound_it_to_a_run', false,
        'G23. Adds FOREIGN KEY (sim_run_id) REFERENCES ottoq_sim_runs(sim_run_id) NO ACTION to ottoq_proposer_fire_log, which 0260 created with tick_seq registered class=stamp and no foreign keys at all -- the one blocking run-scope defect that made ottoq_retention_purge_runs refuse. Non-forcing: the file changes no function, no fingerprint and no decide-path behaviour, and the constraint governs INSERTs into a table the proposer bridge writes OUTSIDE the tick, which a certification does not write at all because it runs the deterministic core alone (0152). Nothing an arm produces can differ. Classified late, by 0268, because 0267 omitted its own lineage row and the floor correctly swallowed every column until it was supplied.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ---------------------------------------------------------------------------
-- 2. AND 0268 CLASSIFIES ITSELF, which is the whole point of 0142 and is exactly
--    what 0267 failed to do. A file whose subject is an unclassified migration
--    must not become one.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0268_0267_never_classified_itself_and_the_floor_swallowed_every_column', false,
        'Bookkeeping only: inserts the ottoq_cert_lineage row 0267 omitted, and this one. Touches no function, no table data outside ottoq_cert_lineage, and no engine behaviour. Non-forcing for the same reason 0267 is.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ---------------------------------------------------------------------------
-- 3. ASSERTIONS. A1 and A2 are discriminating by construction: section G
--    refused to proceed unless the floor was at 14:14:38 with 0 columns, so
--    neither can pass except by this file's own INSERTs.
-- ---------------------------------------------------------------------------
DO $a$
DECLARE v_rf timestamptz; v_n int; v_m int;
BEGIN
  --: A1. THE FLOOR IS BACK WHERE IT WAS, to the microsecond.
  v_rf := public.ottoq_cert_recert_floor();
  IF v_rf <> '2026-09-12 16:50:23.319089+00'::timestamptz THEN
    RAISE EXCEPTION '0268 A1: recert floor is %, expected 2026-09-12 16:50:23.319089+00', v_rf;
  END IF;

  --: A2. AND BOTH INSTRUMENTS SEE THEIR NINE COLUMNS AGAIN -- both, because
  --:     0266's A5 established that the matrix and the residue must cover
  --:     exactly the same column set, and a fix that restored one and not the
  --:     other would be a new G25/G28.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_matrix(v_rf);
  SELECT count(*) INTO v_m FROM public.ottoq_cert_residue(v_rf);
  IF v_n <> 9 OR v_m <> 9 THEN
    RAISE EXCEPTION '0268 A2: matrix % column(s), residue % column(s), expected 9 and 9', v_n, v_m;
  END IF;

  --: A3. EVERY ENGINE COLUMN IS STILL GREEN. The purge deleted 7,300,205 rows
  --:     between the canon pairs and now; if that had moved an engine canon the
  --:     right response would be alarm, not a classification. It did not, and it
  --:     could not: the matrix reads validation_notes off ottoq_sim_runs, which
  --:     the purge never touches.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_matrix(v_rf) WHERE green;
  IF v_n <> 9 THEN
    RAISE EXCEPTION '0268 A3: % of 9 column(s) green', v_n;
  END IF;

  --: A4. NO MIGRATION IS LEFT UNCLASSIFIED. The generalisation of the defect,
  --:     not just its instance: if any recently applied migration lacks a
  --:     lineage row, the floor is about to move again for the same reason and
  --:     someone should hear about it now.
  --:
  --:     THE JOIN IS THE FLOOR'S OWN, COPIED VERBATIM, not a plausible-looking
  --:     equality. ottoq_cert_recert_floor() strips a leading NNNN_ (or NNNNa_)
  --:     prefix FROM BOTH SIDES before joining -- 0226's fix for db/checks/0135,
  --:     where comparing raw names left 33 of 92 classifications unreachable and
  --:     silently forcing. A first draft of this assertion wrote
  --:     `l.name = m.name`, which is STRICTER than the floor: it would have
  --:     reported columns at risk that the floor is perfectly happy with, and it
  --:     would have been asserting a rule the system does not have. It also
  --:     happens to be why 0266's ledger name being registered without its
  --:     0NNN_ prefix (db/checks/0199) never moved the floor -- that slip was
  --:     visible to scripts/check-drift.sql Section C and invisible here, and
  --:     the two must not be conflated.
  SELECT count(*) INTO v_n
    FROM supabase_migrations.schema_migrations m
   WHERE m.version ~ '^[0-9]{14}$'
     AND m.version >= '20260912000000'
     AND NOT EXISTS (
       SELECT 1 FROM public.ottoq_cert_lineage l
        WHERE regexp_replace(l.name, '^[0-9]{4}[a-z]?_', '')
            = regexp_replace(m.name, '^[0-9]{4}[a-z]?_', ''));
  IF v_n > 0 THEN
    RAISE EXCEPTION '0268 A4: % recent migration(s) carry no ottoq_cert_lineage row under the floor''s own join; the floor will move again', v_n;
  END IF;

  RAISE NOTICE '0268: A1-A4 passed; floor restored to %, nine columns green in both instruments', v_rf;
END $a$;

-- ---------------------------------------------------------------------------
-- APPLY LOG
--
-- APPLIED 2026-09-13 14:29:59 UTC (9:29 AM CT) as version 20260913142959.
-- A1-A4 passed. Pre-image confirmed by section G before anything was written:
-- 0267 unclassified, floor at 14:14:38, matrix 0 columns at that floor, 9 at
-- the pre-0267 floor.
--
-- POST-IMAGE -- byte-identical to the reading taken at 13:58, before 0267:
--   recert floor  2026-09-12 16:50:23.319089+00   (restored exactly)
--   matrix        9 columns, 9 green
--   residue       9 columns
--   11111111 171717 48t busy_day   6 pairs  streak 6  PPPPPP  endst 5a3ec345
--   11111111 171717 24t busy_day   3        3         PPP     dc344d68
--   11111111 424242 24t busy_day   3        3         PPP     7fb3eca5
--   11111111 171717 12t busy_day   3        3         PPP     8b5a0ad4
--   11111111 314159 12t busy_day   3        3         PPP     660898c9
--   11111111 424242 12t busy_day   3        3         PPP     4f1879cf
--   11111111 171717 12t normal_day 3        3         PPP     d801f3ce
--   aacd0bb0 239001  6t grid_smoke 3        3         PPP     f37e1d96
--   aacd0bb0 424242  6t grid_smoke 3        3         PPP     92c84f61
--   residue: flagship 2d1315b9 on all seven, sections_moved 'legs';
--            grid 13e2e154 on both, sections_moved NULL.
--
-- A3 IS THE ONE WORTH READING TWICE. Every engine column is still green across
-- a purge that deleted 7,300,205 rows (db/checks/0201) -- because the matrix
-- reads validation_notes off ottoq_sim_runs, and ottoq_sim_runs is not in
-- ottoq_retention_engine_allowlist. The canons are stored hashes; the purge
-- changed the WORLD, not the record. Whether the engine still REPRODUCES those
-- hashes from the purged world is a different question, and only round 42
-- answers it.
-- ---------------------------------------------------------------------------
