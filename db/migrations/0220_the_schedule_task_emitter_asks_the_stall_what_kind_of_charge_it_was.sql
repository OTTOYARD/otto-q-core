-- migration-version: 20260908111846
-- migration-name:    the_schedule_task_emitter_asks_the_stall_what_kind_of_charge_it_was
--
-- ---------------------------------------------------------------------------
-- 0220 — the schedule_task SDR emitter asks the stall what kind of charge it
--        was, instead of asking the heap.
--
-- Task G20, convicted in db/checks/0124. 0216 fixed one unordered LIMIT 1 on
-- the itinerary-leg SDR terminus. The follow-up question 0216 obliges — do its
-- siblings do the same? — found exactly one sibling, ottoq_trg_task_completed_sdr,
-- and it does it twice.
--
-- THE ONE THAT COSTS MONEY. The trigger resolves a completed schedule_task to a
-- catalog operation with
--
--     SELECT oc.pack_id, oc.operation_code INTO v_op
--       FROM ottoq_operation_catalog oc
--      WHERE oc.emits_sdr AND (oc.svc_code = NEW.service_code OR oc.svc_code = <def code>)
--      LIMIT 1;
--
-- Of the 17 emits_sdr rows in the catalog, exactly one svc_code maps to two
-- operations:
--
--     charge  ->  robotaxi/charge_dcfc   AND   robotaxi/charge_l2
--
-- ottoq_emit_sdr resolves the ServiceTariff by (pack_id, operation_code). So a
-- completed charge task is labelled DCFC or L2 by whichever row the heap
-- returned first and TARIFFED ACCORDINGLY. Not merely irreproducible —
-- wrong-priced, about half the time, on the one operation in the catalog where
-- the price difference is the whole point.
--
-- AND THE FIX IS NOT AN ORDER BY. Deterministically choosing charge_dcfc is
-- still wrong for every L2 charge; it would convert a coin flip into a
-- consistent overcharge, which is worse, not better. The discriminator is
-- already in the trigger's hands: it computes
-- COALESCE(NEW.actual_stall_id, NEW.assigned_stall_id) and hands it to
-- emit_sdr, and stalls.stall_type is one of dcfc / l2 / service_bay / staging /
-- wash_bay (22 / 64 / 5 / 232 / 7 rows today). A charge that ran on a dcfc
-- stall is charge_dcfc; on an l2 stall, charge_l2. The stall is the physical
-- fact; the catalog row is the accounting label for it.
--
-- WHEN THE STALL CANNOT ANSWER — no stall on the task, or a charge task
-- recorded against a wash bay — this deliberately falls through to
-- generic_service rather than guessing. An unclassified SDR is visible and
-- queryable; a confidently mis-tariffed one is not. That choice is a defect
-- report, not a silent default.
--
-- THE SECOND LIMIT 1 is the generic_service fallback. It is unambiguous today
-- (one row) and latent: the second the yard-logistics pack lands its own
-- generic_service row, it becomes the same defect. It gets a total ORDER BY
-- here — tie-break of last resort, which is what an ORDER BY is for once the
-- semantic question has been answered properly.
--
-- The same is true of the primary lookup once a second pack ships an operation
-- for a shared svc_code. It gets ORDER BY (svc_code IS DISTINCT FROM
-- NEW.service_code), pack_id, operation_code: prefer the row that matched the
-- task's own service_code over the row that matched its service_definition,
-- then a stable name order. The first term makes explicit a preference the old
-- OR left to the heap.
--
-- WHY THIS HAS NOT BURNED ANYONE, stated so the fix is not mistaken for an
-- incident: the path is dead. 113 schedule_tasks exist, 101 completed, the last
-- completion 2026-06-18 04:07 UTC and the last task created 2026-06-19. The
-- trigger was installed by 0043 on 2026-08-19 — two months after the last row
-- it could have fired on — and public.ottoq_service_detail_records holds 0 rows
-- with source_kind='schedule_task'. It is live, correct-looking, and has never
-- executed once.
--
-- WHICH IS ALSO THE HONEST FOOTNOTE TO A CLAIM IN CLAUDE.md 2.6. "Every
-- completed operation terminates in an SDR, structurally (C3 enforces)" holds
-- on the itinerary-leg path, which is live and — after 0216 — deterministic.
-- On the schedule_task path it is structurally present and never exercised.
-- Structural and proven are not the same word. This migration makes the
-- unexercised path correct; it does not make it evidence.
--
-- forces_recert: FALSE, and not on the usual "it looks unrelated" reasoning.
-- The certification pair cannot reach this trigger: it fires AFTER UPDATE OF
-- status ON schedule_tasks WHEN new.status='completed', only three functions
-- write that table (ottoq_amend_apply, ottoq_progress_commit,
-- twin.ottoq_sim_materialize_schedule), and the twin one has NO CALLERS
-- anywhere in the database. P2 below asserts the caller count is still zero at
-- apply time rather than trusting this paragraph.
-- ---------------------------------------------------------------------------

BEGIN;

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
-- The standing constraint: never apply while a certification pair is running or
-- scheduled. Until 2026-09-08 that was enforced by the operator remembering it,
-- for three of the four migrations queued behind round 25. It is a file now.
--
-- All three checks are needed and the middle one is the load-bearing one.
-- ottoq_sim_runs cannot see an in-flight pair AT ALL: both arms run inside one
-- transaction, so their rows are uncommitted and invisible until it ends. And
-- cron.job_run_details reports an in-flight pair of this shape as
-- status='succeeded', return_message='SET', duration ~1 s, because the job
-- command is two statements and the row reflects the first (db/canons/round25.md).
-- pg_stat_activity is the only authority.
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0220 P-: certification jobs are still scheduled (%) — migrations wait for '
                    'the round, and unscheduling them is the deliberate act that says it is over',
                    v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0220 P-: a determinism pair is running right now';
  END IF;

  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0220 P-: % sim run(s) are in flight', v_runs;
  END IF;

  RAISE NOTICE '0220 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0220_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_trg_task_completed_sdr';

-- P0. THE BODY IS THE ONE THIS WAS WRITTEN AGAINST --------------------------
DO $p0$
DECLARE v_md5 text; v_n int;
BEGIN
  SELECT left(md5(pg_get_functiondef(p.oid)),8) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_trg_task_completed_sdr';
  IF v_md5 IS DISTINCT FROM '39ad8e0a' THEN
    RAISE EXCEPTION '0220 P0: ottoq_trg_task_completed_sdr is %, pinned 39ad8e0a', v_md5;
  END IF;
  SELECT (length(p.prosrc)-length(replace(p.prosrc,'LIMIT 1','')))/length('LIMIT 1') INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_trg_task_completed_sdr';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0220 P0: expected exactly 2 unordered LIMIT 1 sites, found %', v_n;
  END IF;
  RAISE NOTICE '0220 P0: body 39ad8e0a, two LIMIT 1 sites';
END $p0$;

-- P1. THE AMBIGUITY IS REAL, AND IT IS ONLY charge ---------------------------
-- If the catalog has changed shape since 0124 traced it, the fix below is
-- aimed at the wrong thing and should not be applied blind.
DO $p1$
DECLARE v_amb text; v_dcfc int; v_l2 int;
BEGIN
  SELECT string_agg(svc_code, ',' ORDER BY svc_code) INTO v_amb
    FROM (SELECT svc_code FROM public.ottoq_operation_catalog
           WHERE emits_sdr AND svc_code IS NOT NULL
           GROUP BY svc_code HAVING count(*) > 1) s;
  IF v_amb IS DISTINCT FROM 'charge' THEN
    RAISE EXCEPTION '0220 P1: ambiguous svc_codes are [%], expected exactly [charge]',
                    COALESCE(v_amb,'none');
  END IF;
  SELECT count(*) FILTER (WHERE operation_code='charge_dcfc'),
         count(*) FILTER (WHERE operation_code='charge_l2')
    INTO v_dcfc, v_l2
    FROM public.ottoq_operation_catalog WHERE emits_sdr AND svc_code='charge';
  IF v_dcfc <> 1 OR v_l2 <> 1 THEN
    RAISE EXCEPTION '0220 P1: charge maps to % dcfc and % l2 rows, expected 1 and 1', v_dcfc, v_l2;
  END IF;
  RAISE NOTICE '0220 P1: charge is the only ambiguous svc_code, 1 dcfc + 1 l2';
END $p1$;

-- P2. THE PATH IS STILL UNREACHABLE FROM THE CERTIFICATION -------------------
-- This is what forces_recert=FALSE rests on. If something has started writing
-- schedule_tasks since 0124 traced it, that claim needs re-deriving, not
-- repeating.
DO $p2$
DECLARE v_callers int;
BEGIN
  SELECT count(*) INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','twin','ottoq')
     AND p.prosrc ILIKE '%ottoq_sim_materialize_schedule%'
     AND p.proname <> 'ottoq_sim_materialize_schedule';
  IF v_callers <> 0 THEN
    RAISE EXCEPTION '0220 P2: twin.ottoq_sim_materialize_schedule now has % caller(s) — the '
                    'certification may reach schedule_tasks and forces_recert must be re-derived',
                    v_callers;
  END IF;
  RAISE NOTICE '0220 P2: the twin schedule materializer still has no callers';
END $p2$;

CREATE OR REPLACE FUNCTION public.ottoq_trg_task_completed_sdr()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_op        record;
  v_stall_id  uuid;
  v_stall_ty  text;
  v_def_code  text;
  v_charge_op text;
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);

  v_stall_id := COALESCE(NEW.actual_stall_id, NEW.assigned_stall_id);

  SELECT sd.code INTO v_def_code
    FROM service_definitions sd WHERE sd.id = NEW.service_definition_id;

  --: 0220. The physical fact that settles the accounting label. A charge that
  --: ran on a dcfc stall is charge_dcfc; on an l2 stall, charge_l2. Any other
  --: stall type -- or no stall at all -- leaves this NULL, and the predicate
  --: below then matches no charge row, so the task falls through to
  --: generic_service rather than being tariffed as a guess.
  SELECT s.stall_type::text INTO v_stall_ty FROM stalls s WHERE s.id = v_stall_id;
  v_charge_op := CASE v_stall_ty WHEN 'dcfc' THEN 'charge_dcfc'
                                 WHEN 'l2'   THEN 'charge_l2' END;

  SELECT oc.pack_id, oc.operation_code INTO v_op
    FROM ottoq_operation_catalog oc
   WHERE oc.emits_sdr
     AND (oc.svc_code = NEW.service_code OR oc.svc_code = v_def_code)
     --: 0220. 'charge' is the one svc_code mapping to two operations with two
     --: tariffs. Before this, LIMIT 1 over an unordered scan picked one.
     AND (oc.svc_code <> 'charge' OR oc.operation_code = v_charge_op)
   --: 0220. Total order, tie-break of last resort: prefer the row matched by
   --: the task's own service_code over the one matched by its
   --: service_definition, then a stable name order. Only reachable once a
   --: second pack ships an operation for a shared svc_code.
   ORDER BY (oc.svc_code IS DISTINCT FROM NEW.service_code), oc.pack_id, oc.operation_code
   LIMIT 1;

  IF v_op IS NULL THEN
    SELECT oc.pack_id, oc.operation_code INTO v_op
      FROM ottoq_operation_catalog oc
     WHERE oc.operation_code = 'generic_service' AND oc.emits_sdr
     --: 0220. One row today, two the moment a second pack ships one.
     ORDER BY oc.pack_id
     LIMIT 1;
  END IF;
  IF v_op IS NULL THEN RETURN NEW; END IF;

  PERFORM ottoq_emit_sdr(
    'schedule_task', v_op.operation_code, v_op.pack_id,
    NEW.vehicle_id, NULL,
    NULL, NEW.id, NULL, NULL,
    v_stall_id, NEW.depot_id,
    NEW.actual_start, COALESCE(NEW.actual_end, now()),
    NEW.energy_delivered_kwh, NEW.peak_charge_rate_kw);
  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.ottoq_trg_task_completed_sdr() IS
  '0043, corrected by 0220: emits the ServiceDetailRecord for a completed schedule_task. '
  'Resolves the catalog operation from the task''s service_code or service_definition, and '
  'discriminates the one ambiguous svc_code (charge -> charge_dcfc | charge_l2) by the '
  'stall_type of the stall the task actually ran on. Falls through to generic_service when the '
  'stall cannot answer, rather than tariffing a guess. Both lookups carry a total ORDER BY as '
  'tie-break of last resort. The path is dormant: no schedule_task has completed since '
  '2026-06-18 and this trigger has never fired.';

-- A1. THE DISCRIMINATOR IS IN THE BODY AND THE HEAP IS NOT ------------------
DO $a1$
DECLARE v_def text; v_flat text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_trg_task_completed_sdr';
  v_flat := regexp_replace(v_def, '\s+', ' ', 'g');
  IF position('v_charge_op' in v_flat) = 0 THEN
    RAISE EXCEPTION '0220 A1: the stall_type discriminator is not in the body';
  END IF;
  IF position('ORDER BY (oc.svc_code IS DISTINCT FROM NEW.service_code), oc.pack_id, oc.operation_code' in v_flat) = 0 THEN
    RAISE EXCEPTION '0220 A1: the primary lookup has no total order';
  END IF;
  IF position('ORDER BY oc.pack_id LIMIT 1' in v_flat) = 0 THEN
    RAISE EXCEPTION '0220 A1: the generic_service fallback has no order';
  END IF;
  RAISE NOTICE '0220 A1: discriminator present, both lookups ordered';
END $a1$;

-- A2. THE RESOLUTION IS NOW TOTAL AND CORRECT -------------------------------
-- Replays the trigger's discriminator predicate over every (svc_code,
-- stall_type) pair the depot can actually produce -- every stall_type present
-- in public.stalls, plus the no-stall case -- and asserts exactly one operation
-- survives, and that for charge it is the one the stall names. This is the
-- behavioural guard: against the pre-0220 body ('charge', anything) yields 2
-- candidates and it fails.
--
-- What it does NOT cover: the ORDER BY's first term compares the matched
-- svc_code against the task's own service_code, which is constant inside this
-- replay and only bites once a second pack ships an operation for a shared
-- svc_code. A1 asserts that clause textually; there is no row in the catalog
-- today that can exercise it.
DO $a2$
DECLARE r record; v_bad text := '';
BEGIN
  FOR r IN
    WITH sty AS (SELECT DISTINCT stall_type::text AS stall_type FROM public.stalls
                 UNION ALL SELECT NULL::text),
         svc AS (SELECT DISTINCT svc_code FROM public.ottoq_operation_catalog
                  WHERE emits_sdr AND svc_code IS NOT NULL)
    SELECT svc.svc_code, sty.stall_type,
           (SELECT count(*) FROM public.ottoq_operation_catalog oc
             WHERE oc.emits_sdr AND oc.svc_code = svc.svc_code
               AND (oc.svc_code <> 'charge'
                    OR oc.operation_code = CASE sty.stall_type WHEN 'dcfc' THEN 'charge_dcfc'
                                                               WHEN 'l2'   THEN 'charge_l2' END)
           ) AS n,
           (SELECT oc.operation_code FROM public.ottoq_operation_catalog oc
             WHERE oc.emits_sdr AND oc.svc_code = svc.svc_code
               AND (oc.svc_code <> 'charge'
                    OR oc.operation_code = CASE sty.stall_type WHEN 'dcfc' THEN 'charge_dcfc'
                                                               WHEN 'l2'   THEN 'charge_l2' END)
             ORDER BY oc.pack_id, oc.operation_code
             LIMIT 1) AS picked
      FROM svc CROSS JOIN sty
  LOOP
    -- charge resolves to exactly one row on a charging stall and to NONE
    -- elsewhere -- the deliberate fall-through to generic_service.
    IF r.svc_code = 'charge' THEN
      IF r.stall_type IS NOT DISTINCT FROM 'dcfc' THEN
        IF r.picked IS DISTINCT FROM 'charge_dcfc' OR r.n <> 1 THEN
          v_bad := v_bad || format(' charge@dcfc->%s (%s rows);', COALESCE(r.picked,'none'), r.n);
        END IF;
      ELSIF r.stall_type IS NOT DISTINCT FROM 'l2' THEN
        IF r.picked IS DISTINCT FROM 'charge_l2' OR r.n <> 1 THEN
          v_bad := v_bad || format(' charge@l2->%s (%s rows);', COALESCE(r.picked,'none'), r.n);
        END IF;
      ELSIF r.n <> 0 THEN
        v_bad := v_bad || format(' charge@%s resolved to %s;',
                                 COALESCE(r.stall_type,'(no stall)'), COALESCE(r.picked,'?'));
      END IF;
    ELSIF r.n <> 1 THEN
      v_bad := v_bad || format(' %s@%s->%s rows;',
                               r.svc_code, COALESCE(r.stall_type,'(no stall)'), r.n);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION '0220 A2: resolution is not total/correct:%', v_bad;
  END IF;
  RAISE NOTICE '0220 A2: every svc_code resolves to exactly one operation; charge follows the stall';
END $a2$;

-- A3. AND THE OLD PREDICATE REALLY WAS AMBIGUOUS -----------------------------
-- The mutation control. Without the discriminator, 'charge' yields 2 rows and
-- LIMIT 1 picks by heap order. If this stops being true the defect was never
-- there and A2 proves nothing.
DO $a3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_operation_catalog oc
   WHERE oc.emits_sdr AND oc.svc_code = 'charge';
  IF v_n < 2 THEN
    RAISE EXCEPTION '0220 A3: the pre-fix lookup yields % row(s) for charge — the ambiguity '
                    'this migration removes does not exist and A2 is vacuous', v_n;
  END IF;
  RAISE NOTICE '0220 A3: pre-fix, charge yielded % candidate operations with no order', v_n;
END $a3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0220_the_schedule_task_emitter_asks_the_stall_what_kind_of_charge_it_was', FALSE,
        'G20 / db/checks/0124. ottoq_trg_task_completed_sdr resolved a completed schedule_task '
        'to a catalog operation with an unordered LIMIT 1. charge is the only svc_code mapping '
        'to two operations (charge_dcfc, charge_l2) and ottoq_emit_sdr tariffs by '
        '(pack_id, operation_code), so a completed charge was priced DCFC or L2 by heap order. '
        'Fixed by discriminating on stalls.stall_type of the stall the task ran on, NOT by an '
        'ORDER BY — deterministically picking dcfc would be a consistent overcharge instead of a '
        'coin flip. Unresolvable stall types fall through to generic_service by design. Both '
        'lookups also gain a total order for the latent multi-pack case. forces_recert FALSE and '
        'P2 asserts why: no function calls twin.ottoq_sim_materialize_schedule, so the '
        'certification cannot reach schedule_tasks. The path is dormant — 0 SDRs with '
        'source_kind=schedule_task, last task completion 2026-06-18, trigger installed '
        '2026-08-19.',
        now());

COMMIT;
