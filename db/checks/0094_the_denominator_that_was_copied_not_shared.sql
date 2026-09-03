-- =====================================================================
-- 0094  The denominator that was copied, not shared
-- =====================================================================
-- 0093 §4 recorded ottoq_kpi_touch_events_per_turn as NOT AUDITED and
-- guessed - explicitly labelled a guess - that it might share KPI 2's
-- denominator. It does. The guess was right and the reason it mattered
-- was not the one stated: it does not READ the KPI 2 view, it carries an
-- INLINE COPY of the same filter, which is why 0183 did not reach it.
--
-- SECTION 1 — SAME DEFECT, OPPOSITE SIGN
-- ---------------------------------------------------------------------
--   KPI 2  counted non-turns as turns   -> OVERSTATED throughput  3.72x
--   KPI 4  divides by that same count   -> UNDERSTATED touches    4.1x
--
--   turns denominator          488,594  ->  131,372
--   avg touch_events_per_turn   0.0375  ->    0.1546
--
-- A copied predicate is worse than a shared one. Two KPIs that disagree
-- get noticed; two that were wrong identically cannot disagree, so the
-- copy bought silence. It is left as a copy for now - making KPI 4 read
-- KPI 2's turns_completed would couple views whose grains differ (KPI 2
-- is per run per DAY, KPI 4 per run), and that is a refactor, not a
-- correction. Recorded so the next person does not have to rediscover
-- that the two are only coincidentally in agreement.
--
-- SECTION 2 — THREE MORE, IN THE SAME VIEW
-- ---------------------------------------------------------------------
-- (2) AN UNSCOPED READ. The `confirms` CTE read schedule_tasks with no
--     run filter of any kind and joined it ON true - the
--     0145/0053/0054/0177/0180 class, and the seventh instance.
--
--     Contributes 0 today for two independent reasons, both measured:
--     the view returns 585 rows and NONE has a NULL sim_run_id (the only
--     rows the term applied to), and 0 of schedule_tasks' 113 rows match
--     its predicate anyway.
--
--     REMOVED, not scoped, because it cannot be scoped: schedule_tasks
--     has depot_id but NO run key, so a confirmation on it is not
--     attributable to a run. Reinstating the term needs a run key on
--     that table - a schema change. This is the 0181 §7 situation again:
--     a mechanism whose blast radius is empty only until the vehicle and
--     asset feeds write the first production row, at which point it
--     would add every human confirmation in the table's whole history to
--     one row.
--
-- (3) THE HEADLINE DID NOT MATCH ITS OWN NUMERATOR. touch_events
--     INCLUDED the confirms term; touch_events_per_turn EXCLUDED it. On
--     the rows the term applied to, touch_events / turns was not
--     touch_events_per_turn. Now they agree by construction, which is
--     the only way that identity is worth anything.
--
-- (4) A DENOMINATOR OF ZERO, MASKED AS ONE. GREATEST(1, turns) meant a
--     run with no completed turn reported its ENTIRE touch count as a
--     per-turn rate. Exactly 1 run has bookings and zero completed
--     occupancies. It now reports NULL. A rate with no denominator has
--     no value, and NULL says that where division by an invented 1 lies.
--
--     Note this moved the headline slightly in the honest direction:
--     the corrected average is 0.1546, not the 0.1544 predicted before
--     applying, because that one run no longer contributes a fabricated
--     number to the average at all.
--
-- SECTION 3 — MEASURED AFTER
-- ---------------------------------------------------------------------
--   rows                       585
--   turns_total            131,372
--   avg touch_events_per_turn  0.1546
--   rows with NULL ratio         1   (the zero-turn run)
--   touch_events = operator + override on every row:  true
--
-- SECTION 4 — THE CLI, END TO END
-- ---------------------------------------------------------------------
-- ottoq_kpi_five on grid-fixture run d2f80255. This is the whole point:
-- one command, run ID in, five KPIs out, each now corrected.
--
--   run_key      scenario grid_smoke, seed 424242, policy otto_q,
--                config_hash f00bdd3d..., engine_hash 5f5c8afa...
--   asset_hours_available_per_day        {2026-09-01: 9.50}
--   service_point_turns_per_point_per_day {2026-09-01: 0.20}
--   peak_site_kw                         176.2
--   peak_site_kw_demand                  167.1
--   touch_events_per_turn                0.500
--   p95_time_to_service_min               28.5
--   p50_time_to_service_min               15.0
--   returns_unserved                         0
--   provenance.not_reproducible             []
--
-- Three of the five headline numbers moved in this campaign: KPI 1 from
-- a value 11.75x its own physical ceiling, KPI 2 from 1.50 to 0.20, and
-- KPI 4 from 0.067 (1/15) to 0.500. The run_key was already correct and
-- is what makes any of them quotable.
--
-- SECTION 5 — WHAT IS STILL NOT DONE
-- ---------------------------------------------------------------------
-- - 0181's PREDICTION IS STILL UNVERIFIED: all six certification columns
--   must reproduce round 12 exactly. Needs a full round. Nothing in
--   0092/0093/0094 tests it.
-- - The diagnostic columns from 0182, 0183 and 0184 still do not reach
--   ottoq_kpi_five. Four of the five KPIs now carry an audit trail
--   invisible from the one command that ships the number. That is the
--   next migration and it changes the run-ID payload shape.
-- - KPI 5's denominator over the 345 historical past-horizon dispatch
--   rows (0092 §5d) is still not re-examined.
-- - KPI 2's points_used denominator is still every stall with any
--   booking that day (0093 §4). Unchanged on purpose; it is a
--   definitional choice, not a defect.
-- - Both peak_site_kw views take max() across depots on a multi-depot
--   run, so "site" would mean "busiest single depot" (0093 §1). Every
--   run today is one depot, so no number is currently wrong.
-- =====================================================================

-- §1 — the denominator, before and after
WITH t AS (
  SELECT sim_run_id,
         count(*) FILTER (WHERE state IN ('done','released','interrupted')) AS turns_old,
         count(*) FILTER (WHERE state = 'done')                             AS turns_new
    FROM public.ottoq_stall_bookings GROUP BY sim_run_id
)
SELECT sum(turns_old) AS denominator_before, sum(turns_new) AS denominator_after,
       round(sum(turns_old)::numeric / NULLIF(sum(turns_new),0), 2) AS factor
  FROM t;

-- §2(2) — the unscoped read was empty, twice over
SELECT (SELECT count(*) FROM public.schedule_tasks)                                AS schedule_tasks_rows,
       (SELECT count(*) FROM public.schedule_tasks
         WHERE confirmed_by_user_id IS NOT NULL OR tech_override_at IS NOT NULL)   AS rows_the_cte_counted,
       (SELECT count(*) FROM public.ottoq_kpi_touch_events_per_turn
         WHERE sim_run_id IS NULL)                                                 AS rows_the_term_applied_to;

-- §3 — after. numerator_decomposes must be true or the headline lies again.
SELECT count(*) AS rows,
       sum(turns) AS turns_total,
       round(avg(touch_events_per_turn),4) AS avg_ratio,
       count(*) FILTER (WHERE touch_events_per_turn IS NULL) AS null_ratio_rows,
       bool_and(touch_events = touch_events_operator + touch_events_override) AS numerator_decomposes
  FROM public.ottoq_kpi_touch_events_per_turn;

-- §4 — the CLI, end to end
SELECT jsonb_pretty(public.ottoq_kpi_five('d2f80255-3bba-49f4-b5e5-054d181dea24'::uuid)) AS five;
