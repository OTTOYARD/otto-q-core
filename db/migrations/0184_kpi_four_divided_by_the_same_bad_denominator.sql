-- =====================================================================
-- 0184  KPI 4 divided by the same bad denominator
-- =====================================================================
-- forces_recert = FALSE. View only; sole reader is ottoq_kpi_five.
--
-- 0093 recorded ottoq_kpi_touch_events_per_turn as UNAUDITED and guessed
-- it might share KPI 2's denominator. It does - and not by reading the
-- KPI 2 view, which is why 0183 did not reach it. It carries an INLINE
-- COPY of the same filter:
--
--   turns AS (SELECT b.sim_run_id,
--        count(*) FILTER (WHERE b.state = ANY (ARRAY['done','released','interrupted']))
--        FROM ottoq_stall_bookings b GROUP BY b.sim_run_id)
--
-- Same defect, opposite sign: KPI 2 counted non-turns as turns and
-- OVERSTATED throughput 3.72x; KPI 4 divides by that same inflated count
-- and UNDERSTATES human intervention.
--
--   turns denominator          488,594  ->  131,372
--   avg touch_events_per_turn   0.0375  ->    0.1544      (4.1x)
--
-- A copied predicate is worse than a shared one: the two KPIs could not
-- disagree today only because they were wrong identically. Noted rather
-- than fixed here - making KPI 4 read KPI 2's turns_completed would
-- couple two views whose grains differ (KPI 2 is per run per DAY, KPI 4
-- is per run) and is a refactor, not a correction.
--
-- THREE MORE DEFECTS IN THE SAME VIEW
-- ---------------------------------------------------------------------
-- (2) AN UNSCOPED READ, and a term that cannot be attributed:
--
--       confirms AS (SELECT NULL::uuid AS sim_run_id, count(*) AS n
--                      FROM schedule_tasks t_1
--                     WHERE t_1.confirmed_by_user_id IS NOT NULL
--                        OR t_1.tech_override_at IS NOT NULL)
--
--     joined ON true, added to touch_events when sim_run_id IS NULL. No
--     run filter of any kind - the 0145 / 0053 / 0054 / 0177 / 0180
--     class. It contributes 0 today for two independent reasons: the
--     view returns 585 rows and NONE has a NULL sim_run_id, and 0 of
--     schedule_tasks' 113 rows match the predicate anyway.
--
--     REMOVED rather than scoped, because it cannot be scoped:
--     schedule_tasks has depot_id but NO run key, so a confirmation on
--     it is not attributable to any run. Reinstating this term needs a
--     run key on that table - a schema change, not a view change. Left
--     in place it would, the moment the vehicle and asset feeds create
--     the first production row, add every human confirmation in the
--     table's whole history to one row.
--
-- (3) THE HEADLINE DID NOT MATCH ITS OWN NUMERATOR. touch_events
--     INCLUDED the confirms term; touch_events_per_turn EXCLUDED it. So
--     touch_events / turns <> touch_events_per_turn on exactly the rows
--     the term applied to. Removing the term makes the two agree by
--     construction, which is the only reason the identity is worth
--     having.
--
-- (4) A DENOMINATOR OF ZERO, MASKED AS ONE. GREATEST(1, t.n) meant a run
--     with no completed turn reported its entire touch count as a
--     per-turn rate. Exactly 1 run has bookings but zero completed
--     occupancies, and it was reporting a ratio built on a fabricated
--     denominator. Now NULL: a rate with no denominator has no value,
--     and NULL says so where division by an invented 1 lies. Callers
--     must handle it - ottoq_kpi_five will emit null for that run, which
--     is the correct thing for it to emit.
--
-- Three diagnostic columns appended per the 0176 / 0182 / 0183 pattern:
-- bookings_not_a_turn (so turns + bookings_not_a_turn reproduces the old
-- denominator), touch_events_operator and touch_events_override (so the
-- numerator is decomposable rather than a single opaque count).
-- =====================================================================

CREATE OR REPLACE VIEW public.ottoq_kpi_touch_events_per_turn AS
WITH touches AS (
  SELECT e.sim_run_id, count(*) AS n
    FROM ottoq_events e
   WHERE e.actor_type = ANY (ARRAY['command_center_operator'::text, 'depot_staff'::text,
         'technician'::text, 'charging_tech'::text, 'cleaning_tech'::text,
         'maintenance_tech'::text, 'yard_supervisor'::text, 'ops_manager'::text])
   GROUP BY e.sim_run_id
), overrides AS (
  SELECT d.sim_run_id, count(*) AS n
    FROM ottoq_decisions d
   WHERE d.overridden OR d.override_id IS NOT NULL
   GROUP BY d.sim_run_id
-- 0184: the `confirms` CTE is gone. It read schedule_tasks with NO run
-- filter (0145/0053/0054/0177/0180 class) and could not be given one:
-- that table has depot_id but no run key, so a confirmation on it is not
-- attributable to a run. It also made touch_events disagree with
-- touch_events_per_turn, which included the term in one and not the
-- other. Reinstating it requires a run key on schedule_tasks.
), turns AS (
  -- 0184: a turn is a completed occupancy - state 'done' - matching 0183.
  -- This was an INLINE COPY of KPI 2's filter, which is why fixing the
  -- KPI 2 view did not reach it: 488,594 -> 131,372 across all history,
  -- understating touch_events_per_turn by 4.1x (0.0375 -> 0.1544).
  SELECT b.sim_run_id,
         count(*) FILTER (WHERE b.state = 'done'::text)  AS n,
         count(*) FILTER (WHERE b.state <> 'done'::text) AS not_a_turn
    FROM ottoq_stall_bookings b
   GROUP BY b.sim_run_id
)
SELECT
  t.sim_run_id,
  COALESCE(tc.n, 0::bigint) + COALESCE(o.n, 0::bigint) AS touch_events,
  t.n AS turns,
  -- 0184: NULL, not division by a fabricated 1. GREATEST(1, t.n) meant a
  -- run with no completed turn reported its whole touch count as a rate.
  CASE WHEN t.n > 0
       THEN round((COALESCE(tc.n, 0::bigint) + COALESCE(o.n, 0::bigint))::numeric / t.n::numeric, 3)
       ELSE NULL::numeric END AS touch_events_per_turn,
  -- 0184 diagnostics
  t.not_a_turn                AS bookings_not_a_turn,
  COALESCE(tc.n, 0::bigint)   AS touch_events_operator,
  COALESCE(o.n, 0::bigint)    AS touch_events_override
FROM turns t
  LEFT JOIN touches   tc ON NOT tc.sim_run_id IS DISTINCT FROM t.sim_run_id
  LEFT JOIN overrides o  ON NOT o.sim_run_id  IS DISTINCT FROM t.sim_run_id;

COMMENT ON VIEW public.ottoq_kpi_touch_events_per_turn IS
  'Canonical KPI 4 (CLAUDE.md 2.9). Human interventions per completed asset-turn. 0184: the turns denominator was an inline copy of KPI 2''s defective filter (state IN done/released/interrupted), so 0183 did not reach it - 488,594 against 131,372 real completed occupancies, understating the rate 4.1x (0.0375 -> 0.1544). Also removed: a confirms term reading schedule_tasks with no run filter, which could not be scoped because that table carries no run key, and which made touch_events disagree with touch_events_per_turn. touch_events_per_turn is now NULL when turns = 0 rather than dividing by a fabricated 1. turns + bookings_not_a_turn reproduces the old denominator.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('kpi_four_divided_by_the_same_bad_denominator', false,
        'public.ottoq_kpi_touch_events_per_turn - canonical KPI 4 - carried an INLINE COPY of KPI 2''s defective turns filter (state IN done/released/interrupted) rather than reading the KPI 2 view, which is why 0183 did not reach it. Same defect, opposite sign: KPI 2 counted non-turns as turns and overstated throughput 3.72x, KPI 4 divides by that inflated count and understated human intervention. Denominator 488,594 -> 131,372; avg touch_events_per_turn 0.0375 -> 0.1544, a 4.1x understatement. A copied predicate is worse than a shared one - the two KPIs could not disagree only because they were wrong identically; making KPI 4 read KPI 2''s turns_completed is left undone because their grains differ (KPI 2 is per run per day, KPI 4 per run) and that is a refactor, not a correction. Three further defects in the same view, all fixed: (a) a confirms CTE read schedule_tasks with NO run filter at all - the 0145/0053/0054/0177/0180 class - contributing 0 today because none of the view''s 585 rows has a NULL sim_run_id and 0 of schedule_tasks'' 113 rows match its predicate; removed rather than scoped because schedule_tasks has depot_id but no run key, so a confirmation on it is not attributable to a run and reinstating the term needs a schema change - left in place it would add every human confirmation in that table''s history to one row the moment the vehicle and asset feeds create the first production row; (b) touch_events INCLUDED the confirms term while touch_events_per_turn EXCLUDED it, so the headline did not match its own numerator - removing the term makes them agree by construction; (c) GREATEST(1, turns) meant a run with no completed turn reported its whole touch count as a per-turn rate (exactly 1 such run exists), so touch_events_per_turn is now NULL there and ottoq_kpi_five will emit null for it, which is correct. Three diagnostics appended per the 0176/0182/0183 pattern; turns + bookings_not_a_turn reproduces the old denominator. forces_recert=false: view only, sole reader ottoq_kpi_five.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
