-- migration-version: 20260920162559
-- migration-name:    my_own_new_detector_raises_on_the_malformed_data_it_exists_to_find
--
-- 0384  HARDENING `public.ottoq_atom_class_coverage` (0383) AGAINST THE ONE INPUT IT IS
--       MOST LIKELY TO MEET: AN ATOM WHOSE `started_at` IS NOT A TIMESTAMP.
--
-- `forces_recert` **FALSE**. One function replaced, read-only, no schema, no data, no tick
-- path. Safe to apply while a run is live, and one is.
--
-- ══ WHY THIS IS NOT PREMATURE ══════════════════════════════════════════════
--
-- 0383 shipped the detector with `(e->>'started_at')::timestamptz` unguarded. Every value
-- present today is written by `ottoq_start_concurrent_atoms` as `to_jsonb(p_clock)`, so
-- every cast succeeds and the function ran clean in 0383's P4. **That is exactly the
-- argument that should not be trusted here.** `ottoq_visit_needs.atoms` is a free-form jsonb
-- array written by several functions and extended by triage escalation at runtime; nothing
-- in the schema constrains an atom's keys, and a future writer that stamps `'now'`, `''` or
-- a bare date puts a value in there that a hard cast rejects.
--
-- And the consequence is specifically the defect `0376` exists to prevent. A detector whose
-- job is *"this class of atom exists and has never moved"* is read to establish an absence.
-- If a single malformed atom makes it raise 22007 instead of returning rows, its output is
-- missing — and **a missing answer and a clean answer are the same silence to the reader**,
-- which is what `0376` was written to make impossible for the power-excursion detector.
-- Applying that lesson to my own code from the same day, rather than waiting to be taught it
-- again, is the whole of this migration.
--
-- `pg_input_is_valid` (PostgreSQL 16+; this server is 17.6) is the right instrument: it
-- answers whether the cast would succeed without attempting it, so a bad value becomes a
-- NULL `first_start`/`last_start` for that class while every count in the row stays exact.
-- The counts are what an ORPHAN_CLASS verdict is computed from, so the verdict cannot be
-- changed by this — only the two timestamp columns can degrade, and they degrade to NULL,
-- which `gate`/`anchor`/`bay` already legitimately return.

DO $p0$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_atom_class_coverage';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0384 P0: expected 1 ottoq_atom_class_coverage, found % -- 0383 must be applied first', v_n;
  END IF;
  RAISE NOTICE '0384 P0: 0383''s detector is present';
END $p0$;

CREATE OR REPLACE FUNCTION public.ottoq_atom_class_coverage(p_sim_run_id uuid DEFAULT NULL)
 RETURNS TABLE(concurrency text, services text[], atoms bigint, pending bigint,
               in_progress bigint, done bigint, cancelled bigint, ever_started bigint,
               first_start timestamptz, last_start timestamptz, verdict text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  WITH a AS (
    SELECT COALESCE(e->>'concurrency','(none)')        AS cls,
           e->>'svc'                                   AS svc,
           COALESCE(e->>'status','pending')             AS st,
           -- 0384: never a bare cast. A single atom carrying a non-timestamp started_at
           -- would make this function RAISE, and a detector that raises reports an absence
           -- indistinguishable from a clean answer -- 0376's defect, in my own code.
           CASE WHEN pg_input_is_valid(COALESCE(e->>'started_at',''), 'timestamptz')
                THEN (e->>'started_at')::timestamptz END AS started_at
      FROM public.ottoq_visit_needs vn,
           jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) e
     WHERE (p_sim_run_id IS NULL OR vn.sim_run_id = p_sim_run_id)
       AND (e->>'svc') IS NOT NULL)
  SELECT cls,
         array_agg(DISTINCT svc ORDER BY svc),
         count(*),
         count(*) FILTER (WHERE st = 'pending'),
         count(*) FILTER (WHERE st = 'in_progress'),
         count(*) FILTER (WHERE st = 'done'),
         count(*) FILTER (WHERE st = 'cancelled'),
         count(*) FILTER (WHERE st IN ('in_progress','done')),
         min(started_at), max(started_at),
         CASE
           WHEN count(*) FILTER (WHERE st IN ('in_progress','done')) > 0 THEN 'executing'
           WHEN count(*) FILTER (WHERE st = 'cancelled') = count(*)      THEN 'all_cancelled'
           ELSE 'ORPHAN_CLASS: ' || count(*)
                || ' atoms, none ever reached in_progress or done'
         END
    FROM a GROUP BY cls ORDER BY count(*) DESC;
$function$;

COMMENT ON FUNCTION public.ottoq_atom_class_coverage(uuid) IS
'0383/G86, hardened by 0384. One row per concurrency class observed in ottoq_visit_needs.atoms. An ORPHAN_CLASS verdict means atoms of that class exist and not one has ever reached in_progress or done -- a service the engine derives and no executor can perform. This is how G86 hid: perimeter_walkaround was derived into class ''hold'', which no starter admits, and sat at 63 atoms / 0 started while every other class completed. DELIBERATELY EVIDENCE-BASED, NOT A SOURCE PROBE: the in-place starter (ottoq_start_concurrent_atoms) names only cabin/exterior/digital, while bay, anchor and gate are executed by the bay-exit, charge-session and departure seams respectively, so no single function''s text is the authority on what is executable -- and a text probe is the pattern-match class of error that produced 0383 section 1''s retracted attribution. started_at is read through pg_input_is_valid rather than a bare cast (0384): a malformed atom must degrade first_start/last_start to NULL, never make this function raise, because a detector that raises reports an absence a reader cannot tell from a clean answer. The counts and therefore the verdict are unaffected by that guard. Pass a sim_run_id to scope to one run (atoms are class=engine and purge with their run); NULL reads whatever survives. WHAT IT DOES NOT CATCH: a class that completes without the work happening -- the credited/satisfied shapes ottoq_kpi_service_completion separates. It answers "can this class ever move", not "did the work occur".';

-- ══ POSTFLIGHT ════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_rec RECORD; v_rows int := 0; v_hold_seen boolean := false;
BEGIN
  -- Invoke, never string-match: 0381's lesson.
  FOR v_rec IN SELECT * FROM public.ottoq_atom_class_coverage() LOOP
    v_rows := v_rows + 1;
    IF v_rec.atoms <> v_rec.pending + v_rec.in_progress + v_rec.done + v_rec.cancelled THEN
      RAISE EXCEPTION '0384 P1: class % does not sum -- % vs %+%+%+%',
        v_rec.concurrency, v_rec.atoms, v_rec.pending, v_rec.in_progress,
        v_rec.done, v_rec.cancelled;
    END IF;
    IF v_rec.concurrency = 'hold' THEN v_hold_seen := true; END IF;
  END LOOP;
  IF v_rows = 0 THEN
    RAISE EXCEPTION '0384 P1: the detector returned no classes';
  END IF;
  IF NOT v_hold_seen THEN
    RAISE WARNING '0384 P1: class ''hold'' is no longer present -- expected while run 562bf027''s stored atoms survive (0383 does not backfill them); this is only a surprise if that run was not purged';
  END IF;
  RAISE NOTICE '0384 P1: detector returned % classes and every one sums', v_rows;
END $p1$;

DO $p2$
DECLARE v_bad_first timestamptz; v_n bigint;
BEGIN
  -- The guard must be exercised, not merely present: prove the predicate rejects the
  -- values that would have raised, and that a valid value still reads through.
  IF pg_input_is_valid('not-a-timestamp','timestamptz')
     OR pg_input_is_valid('','timestamptz') THEN
    RAISE EXCEPTION '0384 P2: pg_input_is_valid accepted a value that cannot cast -- the guard is not a guard';
  END IF;
  IF NOT pg_input_is_valid('2026-09-21T07:30:00+00:00','timestamptz') THEN
    RAISE EXCEPTION '0384 P2: pg_input_is_valid rejected the exact format ottoq_start_concurrent_atoms writes';
  END IF;

  -- and the detector still reports real start times where they exist
  SELECT count(*) INTO v_n FROM public.ottoq_atom_class_coverage()
   WHERE first_start IS NOT NULL;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0384 P2: no class reports a first_start -- the guard has nulled every timestamp';
  END IF;
  RAISE NOTICE '0384 P2: guard rejects junk, accepts the written format, % classes still time-stamped', v_n;
END $p2$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0384_my_own_new_detector_raises_on_the_malformed_data_it_exists_to_find', false,
  'Hardens public.ottoq_atom_class_coverage from 0383. Its started_at read was a bare '
  '(e->>''started_at'')::timestamptz over free-form jsonb, so one atom carrying a '
  'non-timestamp value would make the function raise 22007 -- and a detector whose purpose '
  'is to establish that a class of atom has never moved reports, when it raises, an absence '
  'the reader cannot distinguish from a clean answer. That is precisely 0376''s defect, '
  'applied to code written the same day, so it is fixed now rather than after being taught '
  'again. Read through pg_input_is_valid (PG16+; server 17.6) so a bad value nulls '
  'first_start/last_start for that class while every count stays exact -- the counts are '
  'what the ORPHAN_CLASS verdict is computed from, so no verdict can change, and NULL '
  'timestamps are already legitimately returned by the gate, anchor and bay classes whose '
  'atoms are credited without a start. P2 exercises the predicate rather than asserting its '
  'presence. Read-only, no schema, no data, no tick path, so no canon is invalidated.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
