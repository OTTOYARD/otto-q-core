-- =====================================================================
-- 0187  The KPI that scanned two and a half million rows per call
-- =====================================================================
-- forces_recert = FALSE. PERFORMANCE ONLY. Not one published value may
-- move, and the check is a checksum over the entire view.
--
-- HOW IT SURFACED
-- ---------------------------------------------------------------------
-- 0186 pushed ottoq_kpi_five past the client's 60 s timeout. Profiling
-- the CLI:
--
--   ottoq_kpi_five(one run)                 54,609 ms
--     KPI 1 view (0186, with a constant)         1.5 ms
--     KPI 1 view (via a bound parameter)         1.5 ms
--     KPI 5 view                               356 ms
--     KPI 4 view                            22,330 ms   <-- here
--
-- 0186 was not the cause. It was the trigger: the CLI has been slow all
-- along and nobody had timed it. What 0186 did was push it over a wall
-- where it became visible.
--
-- 0185 DID make it worse, and that is mine. Surfacing the audit block
-- added a SECOND read of the KPI 4 view, taking the CLI from roughly one
-- 22 s scan to two. A 2x regression on top of a pre-existing 22 s
-- defect.
--
-- THE CAUSE, from the plan rather than from reasoning
-- ---------------------------------------------------------------------
--   Parallel Seq Scan on ottoq_events      Rows Removed by Filter: 1,235,759 (x2 workers)
--   Parallel Seq Scan on ottoq_decisions   Rows Removed by Filter:   666,590 (x2 workers)
--   Join Filter: (NOT (e.sim_run_id IS DISTINCT FROM b.sim_run_id))
--
-- The view joined its aggregate CTEs with IS NOT DISTINCT FROM - a
-- null-safe equality so a production row (sim_run_id NULL) would match.
-- The planner cannot propagate a run filter through that operator, so
-- WHERE sim_run_id = <a run> reached ottoq_stall_bookings (index scan)
-- and NOT ottoq_events or ottoq_decisions. Both were scanned in full,
-- for every call, whatever run was asked for.
--
-- Note the row counts: ottoq_events holds ~2.49M rows. CLAUDE.md Part 3
-- records 20,799, which was true at the 2026-08-18 pull and is now two
-- orders of magnitude stale. A view that scans the whole table gets
-- worse every day the twin runs.
--
-- Suitable indexes existed the whole time and were simply unreachable:
--   ottoq_events_keep_sim_run_id_idx  (sim_run_id) WHERE sim_run_id IS NOT NULL
--   idx_decisions_run_tick            (sim_run_id, tick_seq)
--
-- THE FIX, and why the obvious version is not enough
-- ---------------------------------------------------------------------
-- Rewriting the join as
--   (e.sim_run_id = t.sim_run_id OR (e.sim_run_id IS NULL AND t.sim_run_id IS NULL))
-- fixes ottoq_decisions (bitmap index scan) but NOT ottoq_events: that
-- index is PARTIAL on sim_run_id IS NOT NULL, so an OR-branch mentioning
-- IS NULL makes it unusable and the seq scan stays. Measured: 13,192 ms.
-- Better, still wrong.
--
-- What works is keeping the two cases in separate expressions, so the
-- non-null branch is a plain equality the partial index serves and the
-- null branch is never planned into it:
--
--   CASE WHEN t.sim_run_id IS NOT NULL
--        THEN (SELECT count(*) ... WHERE e.sim_run_id = t.sim_run_id ...)
--        ELSE (SELECT count(*) ... WHERE e.sim_run_id IS NULL ...)
--   END
--
-- Measured on the same run: Index Scan using
-- ottoq_events_keep_sim_run_id_idx, NULL branch "never executed",
-- 6.991 ms against 22,330 ms. Roughly 3,000x.
--
-- SEMANTICS ARE UNCHANGED. The CASE reproduces IS NOT DISTINCT FROM
-- exactly: a run-scoped row counts rows with that run id, a production
-- row (NULL) counts rows with a NULL run id. The check is a checksum
-- over every column of all 597 rows of the view, before and after -
-- 241093e014e86e907aaa1f577eddd0ea. A performance migration that moves a
-- number is a behaviour migration wearing a disguise.
--
-- WHAT IS NOT FIXED HERE
-- ---------------------------------------------------------------------
-- - KPI 5 at 356 ms per read is read FOUR times by ottoq_kpi_five
--   (p95, p50, returns_unserved, and the 0185 audit block), so ~1.4 s.
--   Its plan shows an index scan on ottoq_itinerary_legs by vehicle_id
--   with sim_run_id applied as a filter afterwards - 3,065 rows discarded
--   per loop across 118 loops. A composite index would fix it. Left
--   alone: it is a different table, a different index decision, and this
--   migration is about one view.
-- - ottoq_kpi_five reads several views twice (headline and audit). That
--   is the shape 0185 chose for clarity and it is now cheap enough not to
--   matter; it would matter again if another view regressed.
-- =====================================================================

CREATE OR REPLACE VIEW public.ottoq_kpi_touch_events_per_turn AS
WITH turns AS (
  -- 0184: a turn is a completed occupancy - state 'done'.
  SELECT b.sim_run_id,
         count(*) FILTER (WHERE b.state = 'done'::text)  AS n,
         count(*) FILTER (WHERE b.state <> 'done'::text) AS not_a_turn
    FROM ottoq_stall_bookings b
   GROUP BY b.sim_run_id
), counted AS (
  -- 0187: the two run-key cases are kept in SEPARATE expressions so the
  -- non-null branch is a plain equality the partial index
  -- ottoq_events_keep_sim_run_id_idx can serve. Previously these were
  -- aggregate CTEs joined with IS NOT DISTINCT FROM, through which the
  -- planner cannot propagate a run filter - so every call seq-scanned
  -- ottoq_events (~2.49M rows) and ottoq_decisions (~667k). 22,330 ms
  -- per read; 6.991 ms now. Semantics identical: a run-scoped row counts
  -- its own run, a production row (NULL) counts NULL-run rows.
  SELECT t.sim_run_id, t.n, t.not_a_turn,
    CASE WHEN t.sim_run_id IS NOT NULL
      THEN (SELECT count(*) FROM ottoq_events e
             WHERE e.sim_run_id = t.sim_run_id
               AND e.actor_type = ANY (ARRAY['command_center_operator'::text, 'depot_staff'::text,
                     'technician'::text, 'charging_tech'::text, 'cleaning_tech'::text,
                     'maintenance_tech'::text, 'yard_supervisor'::text, 'ops_manager'::text]))
      ELSE (SELECT count(*) FROM ottoq_events e
             WHERE e.sim_run_id IS NULL
               AND e.actor_type = ANY (ARRAY['command_center_operator'::text, 'depot_staff'::text,
                     'technician'::text, 'charging_tech'::text, 'cleaning_tech'::text,
                     'maintenance_tech'::text, 'yard_supervisor'::text, 'ops_manager'::text]))
    END AS n_op,
    CASE WHEN t.sim_run_id IS NOT NULL
      THEN (SELECT count(*) FROM ottoq_decisions d
             WHERE d.sim_run_id = t.sim_run_id
               AND (d.overridden OR d.override_id IS NOT NULL))
      ELSE (SELECT count(*) FROM ottoq_decisions d
             WHERE d.sim_run_id IS NULL
               AND (d.overridden OR d.override_id IS NOT NULL))
    END AS n_ov
   FROM turns t
)
SELECT
  sim_run_id,
  n_op + n_ov AS touch_events,
  n AS turns,
  -- 0184: NULL, not division by a fabricated 1.
  CASE WHEN n > 0 THEN round((n_op + n_ov)::numeric / n::numeric, 3)
       ELSE NULL::numeric END AS touch_events_per_turn,
  not_a_turn AS bookings_not_a_turn,
  n_op        AS touch_events_operator,
  n_ov        AS touch_events_override
FROM counted;

COMMENT ON VIEW public.ottoq_kpi_touch_events_per_turn IS
  'Canonical KPI 4 (CLAUDE.md 2.9). Human interventions per completed asset-turn (state = done, 0184). 0187: performance only, no value changed - the view joined its aggregate CTEs with IS NOT DISTINCT FROM, through which the planner cannot propagate a run filter, so every call sequentially scanned ottoq_events (~2.49M rows) and ottoq_decisions (~667k) despite suitable indexes existing. 22,330 ms per read; 6.991 ms after. The two run-key cases are now separate expressions so the non-null branch is a plain equality the partial index ottoq_events_keep_sim_run_id_idx serves.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_kpi_that_scanned_two_and_a_half_million_rows_per_call', false,
        'public.ottoq_kpi_touch_events_per_turn - canonical KPI 4 - joined its aggregate CTEs with IS NOT DISTINCT FROM, a null-safe equality so production rows (sim_run_id NULL) would match. The planner cannot propagate a run filter through that operator, so WHERE sim_run_id = <a run> reached ottoq_stall_bookings by index and NOT ottoq_events or ottoq_decisions: both were sequentially scanned in full on every call, whatever run was asked for. Measured 22,330 ms per read, with 1,235,759 and 666,590 rows removed by filter per parallel worker. Surfaced because 0186 pushed ottoq_kpi_five past the 60 s client timeout, which forced the first profiling the CLI has ever had: 54,609 ms total, of which KPI 4 was two reads. 0186 was the trigger, not the cause - the CLI has been slow all along. 0185 IS partly responsible and that is mine: surfacing the audit block added a second read of this view, a 2x regression on top of a pre-existing 22 s defect. Also recorded: ottoq_events holds ~2.49M rows against the 20,799 in CLAUDE.md Part 3, true at the 2026-08-18 pull and now two orders of magnitude stale - a view that scans the whole table gets worse every day the twin runs. Suitable indexes existed the whole time and were simply unreachable. The obvious rewrite (a = b OR (a IS NULL AND b IS NULL)) fixes ottoq_decisions via bitmap index scan but NOT ottoq_events, whose index is PARTIAL on sim_run_id IS NOT NULL so an OR-branch mentioning IS NULL makes it unusable: 13,192 ms, better and still wrong. The fix keeps the two cases in separate CASE expressions so the non-null branch is a plain equality the partial index serves and the null branch is never planned into it - 6.991 ms, roughly 3,000x, with the null branch reported never executed. Semantics identical; the check is a checksum over every column of all 597 rows before and after, 241093e014e86e907aaa1f577eddd0ea, because a performance migration that moves a number is a behaviour migration wearing a disguise. Not fixed here: KPI 5 at 356 ms per read is read four times by ottoq_kpi_five (~1.4 s) and its plan shows an index scan on ottoq_itinerary_legs by vehicle_id with sim_run_id filtered afterwards, 3,065 rows discarded per loop across 118 loops - a composite index would fix it, but it is a different table and a different index decision. forces_recert=false: view only, no value changed.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
