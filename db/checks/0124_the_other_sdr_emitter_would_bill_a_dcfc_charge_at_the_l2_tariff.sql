-- ---------------------------------------------------------------------------
-- 0124 — the other SDR emitter would bill a DCFC charge at the L2 tariff, and
--        has been dormant since June.
--
-- Traced 2026-09-08 against gxdrcyphqjzjsuhxuqtg, immediately after 0216, by
-- asking the follow-up 0216 obliges: if the SDR terminus picked with an
-- unordered LIMIT 1, do its siblings? There is exactly one sibling, and it does
-- — twice.
--
-- Recorded as a check rather than fixed on the spot because the fix is not an
-- ORDER BY (see Q3) and because round 25 was in flight. Task G20.
-- ---------------------------------------------------------------------------

-- Q1. THE TWO EMITTERS. Only one other function calls ottoq_emit_sdr.
SELECT n.nspname||'.'||p.proname AS caller
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','twin','ottoq')
  AND p.prosrc ILIKE '%ottoq_emit_sdr%' AND p.proname <> 'ottoq_emit_sdr'
ORDER BY 1;

-- Q2. IT IS LIVE. AFTER UPDATE OF status ON schedule_tasks, WHEN completed.
SELECT tgname, pg_get_triggerdef(t.oid) AS def
FROM pg_trigger t
WHERE NOT t.tgisinternal AND t.tgfoid='public.ottoq_trg_task_completed_sdr'::regproc;

-- Q3. AND ITS FIRST LOOKUP IS AMBIGUOUS, ON THE ONE OPERATION THAT COSTS MONEY.
--     Of 18 emits_sdr rows in the catalog, exactly one svc_code maps to two:
--
--         charge -> robotaxi/charge_dcfc  AND  robotaxi/charge_l2
--
--     ottoq_emit_sdr resolves the tariff by (pack_id, operation_code), so a
--     completed charge task is labelled DCFC or L2 by the heap and TARIFFED
--     ACCORDINGLY. Not merely irreproducible — wrong-priced, about half the time.
--
--     THE FIX IS NOT AN ORDER BY. Deterministically choosing charge_dcfc is
--     still wrong for every L2 charge. The trigger must decide from the TASK.
--     The discriminator is already in its hands: it computes
--     COALESCE(NEW.actual_stall_id, NEW.assigned_stall_id) and passes it to
--     emit_sdr, and stalls.stall_type is one of dcfc / l2 / service_bay /
--     staging / wash_bay. dcfc -> charge_dcfc, l2 -> charge_l2. A total ORDER BY
--     is then the tie-break of last resort, not the answer.
SELECT svc_code, count(*) AS catalog_rows,
       string_agg(pack_id||'/'||operation_code, ', ' ORDER BY pack_id, operation_code) AS candidates
FROM public.ottoq_operation_catalog
WHERE emits_sdr AND svc_code IS NOT NULL
GROUP BY svc_code HAVING count(*) > 1;

-- Q4. WHY NOTHING HAS BURNED. The path is dead and the trigger post-dates it.
--     101 of 113 schedule_tasks are 'completed'; the last completed
--     2026-06-18 04:07 UTC. Migration 0043 installed the trigger 2026-08-19 —
--     two months later. It is live, and it has never once fired.
SELECT (SELECT count(*) FROM public.schedule_tasks) AS tasks,
       (SELECT count(*) FROM public.schedule_tasks WHERE status='completed') AS completed,
       (SELECT max(updated_at) FROM public.schedule_tasks WHERE status='completed') AS last_completion,
       (SELECT max(created_at) FROM public.schedule_tasks) AS last_task_created,
       (SELECT count(*) FROM public.ottoq_service_detail_records
         WHERE source_kind='schedule_task') AS sdrs_this_path_has_ever_produced;

-- Q5. WHAT THAT MEANS FOR THE C3 CLAIM, stated plainly because the docs do not.
--     CLAUDE.md 2.6: "Every completed operation terminates in an SDR,
--     structurally (C3 enforces)." That holds on the itinerary-leg path, which
--     is live and, after 0216, deterministic. On the schedule_task path it is
--     structurally present and NEVER EXERCISED. Structural and proven are not
--     the same word.
--
--     The two paths, by what they have actually produced:
SELECT COALESCE(source_kind,'(null)') AS source_kind, count(*) AS sdrs,
       min(issued_at)::date AS first, max(issued_at)::date AS last
FROM public.ottoq_service_detail_records
GROUP BY 1 ORDER BY 2 DESC;
