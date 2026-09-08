-- migration-version: PENDING
-- migration-name:    the_recert_floor_reads_a_name_the_ledger_never_writes
-- ---------------------------------------------------------------------------
-- 0226 — the recert floor can read the classifications that were written for
--        it, and an unreadable one stops being silent.
--
-- forces_recert: FALSE, and this file is the one place that phrase has to be
-- read carefully, because 0226 is the migration that makes the phrase mean
-- something again. It changes no engine behaviour: `ottoq_cert_recert_floor`
-- is a STABLE read called by the matrix and by the pair's own
-- short-arm/floor logic, never by the decide path. No canon can move. What it
-- changes is which pairs COUNT, and that is stated up front rather than
-- discovered: the floor drops from 2026-09-08 13:41:09 to 2026-09-07
-- 21:36:53, so rounds 26 and 27 come back into scope.
--
-- THE DEFECT (db/checks/0135, task G28). The floor joins
--
--     supabase_migrations.schema_migrations m
--     LEFT JOIN public.ottoq_cert_lineage l ON l.name = m.name
--     WHERE COALESCE(l.forces_recert, true)
--
-- The default is right: a migration nobody classified must be assumed to move
-- the world. The join is what fails. Since 2026-09-04 15:00 every lineage row
-- has been written with the `NNNN_` file prefix while `schema_migrations.name`
-- carries the unprefixed name the apply call was given, so 33 of 92 lineage
-- rows join nothing and fall through to the default. Twenty-one of those 33
-- declare forces_recert FALSE. Every one of them forced a recertification.
--
-- The measured cost, from 0135 Q5: not one certification column is green, six
-- of seven are stale, and `busy_day/424242/24t` carries twenty-six consecutive
-- passing pairs against a consecutive_passes of zero.
--
-- WHY NORMALISE THE JOIN RATHER THAN REWRITE THE ROWS. Rewriting the 33
-- prefixed names would fix today and leave the next convention drift to do
-- this again — and it would edit an audit ledger, which is the wrong instinct
-- for a table whose job is to record what was decided and when. Normalising
-- the comparison leaves all 92 rows exactly as written and stops the function
-- caring which convention wrote them.
--
-- AND NORMALISE BOTH SIDES. 0135 Q3 records the correction: stripping the
-- prefix from `l.name` alone raises the reachable count from 60 to 69, not 70,
-- because it breaks the one case where schema_migrations itself carries a
-- prefixed name (0208) — turning a match into a miss. A one-sided fix for a
-- two-sided mismatch trades one defect for another.
--
-- PART B, AND THE REASON IT IS NOT OPTIONAL. This survived four days because a
-- lineage row that joins nothing looks exactly like one that joins: present,
-- correct, and never asked whether it was consulted. So the migration also
-- installs `public.ottoq_cert_lineage_orphans()`, which lists lineage rows
-- matching no migration under the normalised key. A1 asserts it is empty at
-- apply time; from then on a mis-named row is a question anyone can ask in one
-- statement instead of a silence nobody hears.
--
-- APPLY BEFORE 0225, DELIBERATELY. Lowering the floor puts many more pairs in
-- scope, which makes 0225's P3 precondition ("no column already disagrees with
-- itself on a newly compared atom") a far harder test. If P3 then refuses,
-- that is the check doing its job on the real evidence set rather than on a
-- floor that admitted a single pair.
-- ---------------------------------------------------------------------------

DO $mig$
DECLARE
  v_def       text;
  v_pin       constant text := '060b11c830bfe7709b8c8b0c69ed1a0d';  -- read from the live catalog 2026-09-08 14:40 UTC
  v_before    timestamptz;
  v_after     timestamptz;
  v_orphans   int;
  v_n         int;
BEGIN
  ------------------------------------------------------------------ P- ------
  -- pg_stat_activity is the only authority on an in-flight pair; the cron log
  -- reports a running two-statement job as 'succeeded' at ~1 s
  -- (db/canons/round25.md).
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE query ILIKE '%ottoq_determinism_pair%' AND state='active'
                AND pid <> pg_backend_pid()) THEN
    RAISE EXCEPTION '0226 P-: a determinism pair is active right now';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ '^r[0-9]+_' AND active) THEN
    RAISE EXCEPTION '0226 P-: certification jobs are still scheduled (%). This '
                    'migration changes which pairs count; do not move the floor '
                    'under a running round.',
                    (SELECT string_agg(jobname, ', ') FROM cron.job
                      WHERE jobname ~ '^r[0-9]+_' AND active);
  END IF;

  ------------------------------------------------------------------ P0 ------
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_recert_floor';
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0226 P0: public.ottoq_cert_recert_floor does not exist';
  END IF;
  IF md5(v_def) <> v_pin THEN
    RAISE EXCEPTION '0226 P0: pre-image is %, expected %. The floor function '
                    'moved since this was written; re-derive, do not force.',
                    md5(v_def), v_pin;
  END IF;
  IF v_def NOT LIKE '%ON l.name = m.name%' THEN
    RAISE EXCEPTION '0226 P0: the defective join is not in the body; it has '
                    'already been changed. Re-derive before applying.';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_def, 'COALESCE\(l\.forces_recert, true\)', 'g')) <> 1 THEN
    RAISE EXCEPTION '0226 P0: expected exactly one COALESCE default, found %',
      (SELECT count(*) FROM regexp_matches(v_def, 'COALESCE\(l\.forces_recert, true\)', 'g'));
  END IF;

  ------------------------------------------------------------------ P1 ------
  -- The claim that makes forces_recert FALSE true here: no decide-path
  -- function reads the floor. The matrix and the pair's own bookkeeping may.
  SELECT string_agg(n.nspname||'.'||p.proname, ', ') INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.prosrc ILIKE '%ottoq_cert_recert_floor%'
     AND p.proname NOT IN ('ottoq_cert_recert_floor','ottoq_cert_matrix',
                           'ottoq_determinism_pair')
     AND p.proname NOT LIKE 'ottoq_fn_backup_%';
  IF v_def IS NOT NULL THEN
    RAISE EXCEPTION '0226 P1: an unexpected function reads the recert floor: %. '
                    'forces_recert FALSE rests on the floor being read only by '
                    'the certification bookkeeping.', v_def;
  END IF;

  ------------------------------------------------------------------ P2 ------
  -- Nothing since the naming boundary may be GENUINELY unclassified, or the
  -- floor would be moving for a real reason and this fix would mask it.
  SELECT count(*) INTO v_n
    FROM supabase_migrations.schema_migrations m
   WHERE m.version ~ '^[0-9]{14}$'
     AND m.version > '20260904150000'
     AND NOT EXISTS (
       SELECT 1 FROM public.ottoq_cert_lineage l
        WHERE regexp_replace(l.name,'^[0-9]{4}[a-z]?_','')
            = regexp_replace(m.name,'^[0-9]{4}[a-z]?_',''));
  IF v_n > 0 THEN
    RAISE EXCEPTION '0226 P2: % migration(s) since the naming boundary have no '
                    'lineage row under the normalised key. The floor is moving '
                    'because they are unclassified, not only because of the '
                    'join. Classify them first: %', v_n,
      (SELECT string_agg(m.name, ', ') FROM supabase_migrations.schema_migrations m
        WHERE m.version ~ '^[0-9]{14}$' AND m.version > '20260904150000'
          AND NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage l
                           WHERE regexp_replace(l.name,'^[0-9]{4}[a-z]?_','')
                               = regexp_replace(m.name,'^[0-9]{4}[a-z]?_','')));
  END IF;

  v_before := public.ottoq_cert_recert_floor();

  ------------------------------------------------------------- part A -------
  CREATE OR REPLACE FUNCTION public.ottoq_cert_recert_floor()
  RETURNS timestamp with time zone
  LANGUAGE sql
  STABLE SECURITY DEFINER
  SET search_path TO 'public', 'supabase_migrations', 'extensions'
  AS $function$
    SELECT GREATEST(
      -- migrations registered by the CLI/apply_migration path; an unclassified
      -- one forces recert. 0226: the join key is the migration name with any
      -- leading NNNN_ file prefix removed FROM BOTH SIDES. The lineage table
      -- holds two conventions (unprefixed before 2026-09-04 15:00, prefixed
      -- after) and schema_migrations holds both too, so comparing raw names
      -- made 33 of 92 classifications unreachable and every one of them fell
      -- through to the default above. See db/checks/0135.
      (SELECT max(make_timestamptz(
                substr(m.version,1,4)::int,  substr(m.version,5,2)::int,
                substr(m.version,7,2)::int,  substr(m.version,9,2)::int,
                substr(m.version,11,2)::int, substr(m.version,13,2)::numeric, 'UTC'))
         FROM supabase_migrations.schema_migrations m
         LEFT JOIN public.ottoq_cert_lineage l
                ON regexp_replace(l.name, '^[0-9]{4}[a-z]?_', '')
                 = regexp_replace(m.name, '^[0-9]{4}[a-z]?_', '')
        WHERE COALESCE(l.forces_recert, true)
          AND m.version ~ '^[0-9]{14}$'),
      -- 0199: migrations applied through the SQL endpoint have no
      -- schema_migrations row; their lineage classification is the only record
      -- and it must count.
      (SELECT max(l.classified_at)
         FROM public.ottoq_cert_lineage l
        WHERE l.forces_recert));
  $function$;

  ------------------------------------------------------------- part B -------
  -- A lineage row that matches no migration is a classification nobody can
  -- reach. It looked identical to a working one for four days; now it is one
  -- statement away from being seen.
  CREATE OR REPLACE FUNCTION public.ottoq_cert_lineage_orphans()
  RETURNS TABLE(name text, forces_recert boolean, classified_at timestamp with time zone)
  LANGUAGE sql
  STABLE SECURITY DEFINER
  SET search_path TO 'public', 'supabase_migrations', 'extensions'
  AS $function$
    SELECT l.name, l.forces_recert, l.classified_at
      FROM public.ottoq_cert_lineage l
     WHERE NOT EXISTS (
       SELECT 1 FROM supabase_migrations.schema_migrations m
        WHERE m.version ~ '^[0-9]{14}$'
          AND regexp_replace(m.name, '^[0-9]{4}[a-z]?_', '')
            = regexp_replace(l.name, '^[0-9]{4}[a-z]?_', ''))
     ORDER BY l.classified_at DESC;
  $function$;

  COMMENT ON FUNCTION public.ottoq_cert_lineage_orphans() IS
    '0226 (G28, db/checks/0135). Lineage rows whose migration cannot be found '
    'under the normalised name key — i.e. classifications that ottoq_cert_'
    'recert_floor cannot consult, and which therefore fall through to its '
    'conservative default. Should be empty. A non-empty result means someone '
    'classified a migration under a name the apply path never wrote.';

  ------------------------------------------------------------------ A1 ------
  SELECT count(*) INTO v_orphans FROM public.ottoq_cert_lineage_orphans();
  IF v_orphans > 0 THEN
    RAISE EXCEPTION '0226 A1: % lineage row(s) still match no migration under '
                    'the normalised key: %. The join fix does not cover them '
                    'and the floor is still ignoring their classification.',
                    v_orphans,
      (SELECT string_agg(name, ', ') FROM public.ottoq_cert_lineage_orphans());
  END IF;

  ------------------------------------------------------------------ A2 ------
  -- The floor must actually move, and must land exactly on 0208 — the newest
  -- migration that DECLARES forces_recert TRUE. Landing anywhere else means
  -- the normalisation reached further than intended.
  v_after := public.ottoq_cert_recert_floor();
  IF v_after >= v_before THEN
    RAISE EXCEPTION '0226 A2: floor did not drop (% -> %). Either the join was '
                    'already fine or the rewrite did not take.', v_before, v_after;
  END IF;
  IF v_after <> (SELECT max(l.classified_at) FROM public.ottoq_cert_lineage l
                  WHERE l.forces_recert) THEN
    RAISE EXCEPTION '0226 A2: floor landed at %, not on the newest '
                    'forces_recert TRUE classification (%). The normalisation '
                    'reached further than the evidence.',
      v_after, (SELECT max(l.classified_at) FROM public.ottoq_cert_lineage l
                 WHERE l.forces_recert);
  END IF;

  ------------------------------------------------------------------ A3 ------
  -- The conservative default must SURVIVE the fix. A migration with no lineage
  -- row at all must still force a recert — that is the property protecting us
  -- from an unreviewed change, and it would be easy to lose while making the
  -- join more generous.
  IF NOT EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations m
     WHERE m.version ~ '^[0-9]{14}$'
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage l
                        WHERE regexp_replace(l.name,'^[0-9]{4}[a-z]?_','')
                            = regexp_replace(m.name,'^[0-9]{4}[a-z]?_',''))) THEN
    RAISE EXCEPTION '0226 A3: no unclassified migration exists to prove the '
                    'conservative default still applies; assert it another way '
                    'rather than assuming it';
  END IF;
  SELECT count(*) INTO v_n
    FROM supabase_migrations.schema_migrations m
    LEFT JOIN public.ottoq_cert_lineage l
           ON regexp_replace(l.name,'^[0-9]{4}[a-z]?_','')
            = regexp_replace(m.name,'^[0-9]{4}[a-z]?_','')
   WHERE m.version ~ '^[0-9]{14}$' AND COALESCE(l.forces_recert, true);
  IF v_n < 700 THEN
    RAISE EXCEPTION '0226 A3: only % migrations now count as forcing; the '
                    'default has been weakened, not just made reachable', v_n;
  END IF;

  ------------------------------------------------------------------ A4 ------
  -- And the columns must come back. Not a cosmetic check: the whole point is
  -- that pairs which passed now count, so at least one column must stop being
  -- stale that was stale before.
  IF (SELECT count(*) FROM public.ottoq_cert_matrix(now() - interval '10 days')
       WHERE depot='11111111-1111-1111-1111-111111111111' AND NOT stale) < 2 THEN
    RAISE EXCEPTION '0226 A4: fewer than two flagship columns are current after '
                    'the fix; the floor moved but the pairs did not come back '
                    'into scope, which means the diagnosis was wrong';
  END IF;

  RAISE NOTICE '0226 applied: recert floor % -> %, orphaned lineage rows now %, '
               'flagship columns not stale: %',
    v_before, v_after, v_orphans,
    (SELECT count(*) FROM public.ottoq_cert_matrix(now() - interval '10 days')
      WHERE depot='11111111-1111-1111-1111-111111111111' AND NOT stale);
END $mig$;

-- Register the classification. Written with the UNPREFIXED name, which is what
-- schema_migrations carries and therefore what the join — old or new — can
-- read. The normalised key makes either form work; using the form the apply
-- path writes means this row would have been reachable even without part A.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('the_recert_floor_reads_a_name_the_ledger_never_writes', false,
        'G28 / db/checks/0135. Normalises the recert floor join on both sides '
        'so classifications written with the NNNN_ file prefix are reachable, '
        'and adds ottoq_cert_lineage_orphans() so an unreachable one is one '
        'statement away from being seen. No engine behaviour changes and no '
        'canon can move; the floor drops from 0224 to 0208, which is the '
        'newest migration that actually declares forces_recert TRUE.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
