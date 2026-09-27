-- migration-version: 20260921204952
-- migration-name:    the_fourth_time_a_header_argued_forces_recert_false_at_length_and_did_not_write_the_row_the_floor_reads
--
-- 0410  **Bookkeeping. `0408` and `0409` each argue `forces_recert=false` in their headers, each
--       argument is correct, and neither wrote the `ottoq_cert_lineage` row that
--       `ottoq_cert_recert_floor()` actually reads. This is the FOURTH occurrence in this repo.**
--
--       Writes nothing but `ottoq_cert_lineage`: no engine object, no view, no function, no data.
--
-- ══ THE TALLY, WHICH IS THE POINT ══════════════════════════════════════════
--
--   0267            -> repaired by 0268
--   0271            -> repaired by 0272
--   0296–0300 (5)   -> repaired by 0301   (latent; no pair ran in the window)
--   0308–0309 (2)   -> repaired by 0310   (visible; ottoq_cert_matrix returned ZERO columns)
--   **0408–0409 (2) -> repaired by THIS FILE**  (visible; all nine columns read
--                                               "stale: predates the recert floor")
--
-- `tests/test_migration_hygiene.py::test_recent_migrations_classify_themselves` exists because of
-- the first two, and its docstring says the quiet part: *"which is once more than an argument in a
-- header can be trusted to prevent."* **It was right, and it caught me — but only in CI, after
-- both migrations were already applied to the live engine.** That gap between "impossible to
-- merge" and "impossible to apply" is named in `0310`'s header and belongs to G12. It has now cost
-- four repairs, and the guard cannot close it, because the guard reads a file and I applied a
-- string.
--
-- ══ WHAT HAPPENED, MEASURED ════════════════════════════════════════════════
--
--   floor before 0408              2026-09-21 19:38:48.259266+00   (0407, genuinely invalidating)
--   floor after 0409               2026-09-21 20:39:17+00          (0409's own apply stamp)
--   lineage rows for 0408/0409     0
--   canon columns `current`        0 of 9  — every one "stale: predates the recert floor"
--
-- Nineteen passing verdicts, the whole sweep of `0400`/`0401`/`0407`, discarded. And the sting is
-- the same one `0310` records: the matrix had reached **8 of 9** on that sweep and I had just told
-- Chase the change was safe for it. Ninety seconds later it was 0 of 9.
--
-- ══ THIS FILE IS THE RECORD OF A REPAIR ALREADY MADE, AND SAYS SO ══════════
--
-- Unlike `0310`, the repair here was applied **out of band** — through `execute_sql` at ~20:47
-- UTC, the moment the stale matrix was noticed — because a classification is metadata ABOUT an
-- applied migration and applying it AS a migration registers a row that needs its own
-- classification. So this file's preflight asserts the repair is ALREADY IN PLACE rather than
-- asserting the defect is present (`0310` P1's mirror image), and its INSERT is idempotent. What
-- it adds that the out-of-band statement could not: **its own lineage row**, without which this
-- very migration would move the floor and repeat the defect it documents.
--
-- ══ AND THE NAMING TRAP, WHICH IS WHY THE ROWS ARE NOT NAMED AFTER THEIR FILES ══
--
-- `ottoq_cert_recert_floor()` joins on `schema_migrations.name` with `^[0-9]{4}[a-z]?_` stripped
-- from BOTH sides. For every prior repair the file stem and the applied name were identical, so
-- `0308_<file stem>` joined. **For `0408`/`0409` they are not identical:** I passed short names to
-- `apply_migration` while the files carry long descriptive ones. A row named after the FILE would
-- therefore never join and the floor would stay broken while looking repaired — the worst
-- available outcome. The rows are named after the APPLIED name with the file's number prefix, and
-- preflight P4 proves each one actually joins rather than trusting that it does.
--
-- **This file's own name is passed to `apply_migration` verbatim, restoring the convention.**
-- `db/checks/0135` already records that a name-convention mismatch made 33 of 92 classifications
-- unreachable; that was an accident of two conventions, and this was me creating one by choosing a
-- careless argument. See `db/checks/0318` §10.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_floor timestamptz;
  v_n     int;
  v_bad   text;
BEGIN
  -- P1. THE OUT-OF-BAND REPAIR IS IN PLACE. If these rows are missing, this file is not
  --     bookkeeping — it is the repair itself, and the floor is still standing on 0409.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage
   WHERE name IN ('0408_arm_event_vocabulary_and_two_registry_readers',
                  '0409_evidence_join_loss_reports_archive_recoverability')
     AND forces_recert = false;
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0410 P1: expected 2 forces_recert=false rows for 0408/0409, found % -- the '
                    'out-of-band repair described in this header is not present', v_n;
  END IF;

  -- P2. THE FLOOR IS BACK ON 0407, the last genuinely invalidating migration. Any other value
  --     means something moved it since and this file's account of the timeline is wrong.
  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor < '2026-09-21 19:38:48+00'::timestamptz
     OR v_floor >= '2026-09-21 19:38:49+00'::timestamptz THEN
    RAISE EXCEPTION '0410 P2: recert floor is %, expected 0407''s stamp 2026-09-21 19:38:48+xx', v_floor;
  END IF;

  -- P3. THIS MIGRATION HAS NOT CLASSIFIED ITSELF YET. Re-running is fine (the INSERT is
  --     idempotent) but a pre-existing row means a second copy applied under another name.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage
   WHERE name LIKE '0410\_%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0410 P3: a 0410 lineage row already exists (%)', v_n;
  END IF;

  -- P4. EACH ROW ACTUALLY JOINS. This is the assertion the naming trap demands: a lineage row
  --     that does not join is indistinguishable from no row at all to the floor, while looking
  --     perfectly correct in the table.
  SELECT string_agg(l.name, ', ') INTO v_bad
    FROM public.ottoq_cert_lineage l
   WHERE l.name IN ('0408_arm_event_vocabulary_and_two_registry_readers',
                    '0409_evidence_join_loss_reports_archive_recoverability')
     AND NOT EXISTS (
       SELECT 1 FROM supabase_migrations.schema_migrations m
        WHERE regexp_replace(m.name, '^[0-9]{4}[a-z]?_', '')
            = regexp_replace(l.name, '^[0-9]{4}[a-z]?_', ''));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0410 P4: these lineage rows join to no applied migration, so the floor '
                    'cannot see them: % -- rename them to the APPLIED migration name', v_bad;
  END IF;

  RAISE NOTICE '0410 preflight: repair present, floor on 0407, both rows join';
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- The two repaired rows, re-asserted idempotently so this file stands alone as
-- the record, plus THIS migration's own row — without which 0410 becomes the
-- fifth occurrence of the defect it documents.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0408_arm_event_vocabulary_and_two_registry_readers', false,
  'Replaces two READ-ONLY check functions and inserts 8 ottoq_event_types_catalog rows. Nothing '
  'in the decide path or the tick path is touched. ottoq_record_event does NOT validate against '
  'the catalogue, so the catalogue rows change no emitted event and therefore no events atom. '
  'ottoq_check_run_scope_registry is called by ottoq_purge_prior_runs, which runs at demo START '
  'and not inside a determinism pair, and the widening adds only severity=warn rows, which the '
  'purge ignores. None of the fourteen atoms can move. NAME NOTE: keyed on the APPLIED migration '
  'name, not the file stem -- the file is '
  '0408_the_registry_gate_that_catches_unclassified_run_tables_cannot_see_the_twin_schema_and_one_'
  'evidence_check_has_been_dead_since_this_afternoon.sql. See 0410 and db/checks/0318 section 10.'),
 ('0409_evidence_join_loss_reports_archive_recoverability', false,
  'Drops and recreates ottoq_evidence_join_loss (read-only, STABLE) plus its passthrough view, '
  'adding two OUT columns. No database function calls it -- only the view '
  'ottoq_evidence_join_loss_now -- and nothing in the engine reads either. None of the fourteen '
  'atoms can move. NAME NOTE: keyed on the APPLIED migration name, not the file stem -- the file '
  'is 0409_the_evidence_ledgers_look_98_percent_unattributable_and_95_percent_of_that_is_'
  'recoverable_from_the_archive.sql. See 0410 and db/checks/0318 section 10.'),
 ('0410_the_fourth_time_a_header_argued_forces_recert_false_at_length_and_did_not_write_the_row_the_floor_reads', false,
  'Pure bookkeeping: writes ottoq_cert_lineage rows for 0408, 0409 and itself and touches nothing '
  'else -- no engine object, no view, no function, no data. It cannot change anything hashed, so '
  'it cannot invalidate a canon column. Fourth repair of this class after 0268, 0272, 0301 and '
  '0310.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_floor timestamptz;
  v_n     int;
  v_cur   int;
  v_cols  int;
BEGIN
  -- V1. All three rows present and false.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage
   WHERE forces_recert = false
     AND (name LIKE '0408\_%' OR name LIKE '0409\_%' OR name LIKE '0410\_%');
  IF v_n <> 3 THEN
    RAISE EXCEPTION '0410 V1: % of 3 lineage rows present and false', v_n;
  END IF;

  -- V2. The floor did NOT move. A bookkeeping migration that moves the floor is the defect.
  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor < '2026-09-21 19:38:48+00'::timestamptz
     OR v_floor >= '2026-09-21 19:38:49+00'::timestamptz THEN
    RAISE EXCEPTION '0410 V2: floor moved to % -- this migration was supposed to be inert', v_floor;
  END IF;

  -- V3. And the instrument this whole class of defect destroys is intact.
  SELECT count(*), count(*) FILTER (WHERE status = 'current')
    INTO v_cols, v_cur FROM public.ottoq_determinism_canon;
  IF v_cols = 0 THEN
    RAISE EXCEPTION '0410 V3: ottoq_determinism_canon returned zero columns -- the 0310 symptom';
  END IF;
  IF v_cur <> v_cols THEN
    RAISE WARNING '0410 V3: % of % canon columns current. Not a failure here -- a column can be '
                  'stale for reasons this file does not touch -- but 9 of 9 was the state when '
                  'this was written.', v_cur, v_cols;
  END IF;

  RAISE NOTICE '0410 verify: 3 lineage rows false, floor held at %, % of % canon columns current',
               v_floor, v_cur, v_cols;
END $post$;

COMMIT;
