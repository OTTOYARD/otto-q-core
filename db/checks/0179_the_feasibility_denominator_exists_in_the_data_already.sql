-- ===========================================================================
-- 0179  THE FEASIBILITY DENOMINATOR EXISTS IN THE DATA ALREADY
--       (and 0172's "the deadline is a constant" is half right)
-- ===========================================================================
-- Measured 2026-09-12 14:55-15:10 UTC (09:55-10:10 AM CT), read-only, pinned to run
-- 5d00244c-10c8-4ffc-b6c0-20dff04024bb (busy_day/424242/12t, fired 14:29 UTC) while
-- round 38 ran. Nothing was written; no run was started.
--
-- BUILD_QUEUE 4d blocks #4 step 1 (tardy_minutes) on this: "A tardiness figure must
-- never ship without its feasibility denominator." db/checks/0172 opened it, having
-- caught me about to publish "54 of 57 deadlines missed, 95%" off a flat deadline. The
-- denominator is now measured, and it did not need anything built -- the atoms already
-- carry the flow-shop structure.
--
-- ---------------------------------------------------------------------------
-- 1. THE STRUCTURE THAT WAS ALREADY THERE
-- ---------------------------------------------------------------------------
--
-- Each atom in ottoq_visit_needs.atoms carries, besides its svc and status:
--
--   est_min        the bundle's own duration estimate for this operation
--   concurrency    a LANE -- anchor / gate / cabin / exterior / digital / hold /
--                  detail / wash_bay / service_bay. The same vocabulary as
--                  service_cadence_policy.lane (db/checks/0178).
--   predecessors   null, or ["*"] meaning "after everything else"
--   must_do        whether the bundle requires it
--
-- That is CLAUDE.md 2.3's flow shop, in data: operations in the SAME lane are serial
-- with each other, different lanes run in PARALLEL, and a ["*"] atom is the tail. So a
-- lower bound on time-to-ready is computable per visit with no model to invent:
--
--   feasible_min = max over lanes( sum est_min of must_do atoms in that lane )
--                + sum est_min of must_do atoms whose predecessors include "*"
--
-- WHAT THE BOUND ASSUMES, stated because it decides what the number may be used for: no
-- resource contention (a point is always free), no queueing, no travel between points,
-- and est_min taken at face value. It is therefore a LOWER BOUND. If it exceeds the
-- deadline, no schedule whatsoever can meet that deadline -- that direction is sound.
-- The other direction is NOT: "feasible" here means "not provably unachievable", never
-- "achievable in this depot on this day".
--
-- ---------------------------------------------------------------------------
-- 2. WHAT IT SAYS -- AND WHERE 0172 WAS OVER-STATED
-- ---------------------------------------------------------------------------
--
-- Of 116 visits in the run, 53 carry both arrived_at and dispatch_due_at. 63 carry NO
-- dispatch_due_at at all (arrived_at is never null). Those 63 are outside any tardiness
-- metric by construction and must be REPORTED, never dropped.
--
--   archetype                    urgency             n   feasible_min       deadline   unachievable
--                                                        min  avg   max     min  max
--   C_overnight                  overnight_hold     36    15   42.3  161    360  540        0
--   M_pass_through_or_P_triage   immediate_dispatch 15     7   14.0   40     45   45        0
--   D_charge_and_go              immediate_dispatch  1    78   78.0   78     45   45        1
--   A_charge_clean_go            immediate_dispatch  1    89   89.0   89     45   45        1
--
-- TWO CORRECTIONS TO 0172, both in the direction of less drama:
--
--   (a) THE DEADLINE IS NOT A UNIVERSAL CONSTANT. It is constant PER URGENCY CLASS.
--       Every immediate_dispatch window is exactly 45 minutes -- 0172 measured that and
--       it holds. But overnight_hold windows take FIVE distinct values between 360 and
--       540 minutes in this one run. 0172's sentence generalised from the immediate
--       class to the table. The defect is narrower than it claimed.
--
--   (b) THE DEADLINE IS MOSTLY ACHIEVABLE. 2 of 53, 3.8%, are provably unachievable --
--       not the 95% the flat-deadline reading produced. And the two are exactly the
--       archetypes that put a CHARGE inside an immediate_dispatch window: 78 and 89
--       minutes of critical path against 45. The pass-through/triage archetype, which
--       has no charge, needs 7-40 minutes against the same 45 and is comfortable.
--
-- SO THE REAL DEFECT IS SPECIFIC AND SMALL: the 45-minute immediate_dispatch window is
-- written without consulting the bundle, and for the two charge-bearing archetypes it is
-- arithmetically impossible before the vehicle has parked. That is a deadline bug in two
-- archetypes, not a broken metric -- and it is exactly the "derive dispatch_due_at from
-- the required bundle" fix 4d asked for, now with the numbers to size it.
--
-- ---------------------------------------------------------------------------
-- 3. THE TARDINESS METRIC THIS LICENSES, AND THE ONE IT DOES NOT
-- ---------------------------------------------------------------------------
--
-- LICENSED: tardiness over the 51 visits whose deadline is not provably unachievable,
-- published beside (i) the 2 excluded as infeasible, with their archetypes, and (ii) the
-- 63 with no deadline at all. Three numbers, always together. 116 = 51 + 2 + 63.
--
-- NOT LICENSED, and this is from db/checks/0177 §3: any tardiness figure computed from
-- an atom's ACTUAL duration. 58.3% of completed atoms have no start/end pair, and for
-- `charge` it is 100% -- the satisfaction path stamps closed_at only. So tardiness can be
-- measured against the READY time the run reached (which the first floor,
-- ottoq_kpi_dispatch_readiness, already does from ocpp_sessions) but NOT against
-- per-operation durations. Two different instruments; do not mix them.
--
-- ---------------------------------------------------------------------------
-- 4. A BUG I WROTE AND CAUGHT, recorded because the failure mode is silent
-- ---------------------------------------------------------------------------
--
-- The first version of §1's query returned feasible_min = 3.0 for all 53 visits --
-- min = avg = p95 = max = 3.0. It looked like an answer. It was the readiness_check atom
-- alone, because I wrote
--
--     (e->'predecessors') ? '*'            AS after_all
--
-- and jsonb `?` against a NULL predecessors returns NULL, not false. `FILTER (WHERE NOT
-- after_all)` then drops every NULL row, so the parallel span was 0 and only the ["*"]
-- tail survived. The fix is COALESCE(..., false). What saved it was not the SQL: it was
-- that an identical value for all 53 visits is implausible for a quantity that should
-- vary with SoC and bundle. Same class as the sim/wall join in 0172 that returned 0 rows
-- with no error. THE RULE: a three-valued predicate inside a FILTER silently narrows the
-- population, and the symptom is a suspiciously tidy number.
--
-- ===========================================================================
-- RE-RUNNABLE MEASUREMENTS
-- ===========================================================================

-- 4.1  The denominator. Three populations that must always be published together.
WITH n AS (
  SELECT vn.visit_id, vn.arrived_at, vn.dispatch_due_at, vn.archetype, vn.urgency, vn.atoms
    FROM public.ottoq_visit_needs vn
   WHERE vn.sim_run_id = '5d00244c-10c8-4ffc-b6c0-20dff04024bb'::uuid
), a AS (
  SELECT n.visit_id, n.arrived_at, n.dispatch_due_at,
         COALESCE((e->>'est_min')::numeric,0) AS est_min,
         COALESCE((e->>'concurrency'),'(none)') AS lane,
         COALESCE((e->'predecessors') ? '*', false) AS after_all   /* COALESCE: see section 4 */
    FROM n, jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) e
   WHERE COALESCE((e->>'must_do')::boolean,false)
     AND n.arrived_at IS NOT NULL AND n.dispatch_due_at IS NOT NULL
), lanes AS (
  SELECT visit_id, arrived_at, dispatch_due_at, lane, after_all, sum(est_min) AS lane_min
    FROM a GROUP BY 1,2,3,4,5
), cp AS (
  SELECT visit_id,
         COALESCE(max(lane_min) FILTER (WHERE NOT after_all),0)
       + COALESCE(sum(lane_min) FILTER (WHERE after_all),0) AS feasible_min,
         EXTRACT(epoch FROM (max(dispatch_due_at) - max(arrived_at)))/60 AS deadline_min
    FROM lanes GROUP BY 1
)
SELECT (SELECT count(*) FROM n) AS visits_total,
       (SELECT count(*) FROM n WHERE dispatch_due_at IS NULL) AS no_deadline_at_all,
       count(*) FILTER (WHERE feasible_min >  deadline_min) AS provably_unachievable,
       count(*) FILTER (WHERE feasible_min <= deadline_min) AS scorable,
       round(avg(feasible_min),1) AS avg_feasible_min
  FROM cp;

-- 4.2  Per archetype, which is where the two infeasible windows live.
WITH n AS (
  SELECT vn.visit_id, vn.arrived_at, vn.dispatch_due_at, vn.archetype, vn.urgency, vn.atoms
    FROM public.ottoq_visit_needs vn
   WHERE vn.sim_run_id = '5d00244c-10c8-4ffc-b6c0-20dff04024bb'::uuid
     AND vn.arrived_at IS NOT NULL AND vn.dispatch_due_at IS NOT NULL
), a AS (
  SELECT n.visit_id, n.archetype, n.urgency, n.arrived_at, n.dispatch_due_at,
         COALESCE((e->>'est_min')::numeric,0) AS est_min,
         COALESCE((e->>'concurrency'),'(none)') AS lane,
         COALESCE((e->'predecessors') ? '*', false) AS after_all
    FROM n, jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) e
   WHERE COALESCE((e->>'must_do')::boolean,false)
), lanes AS (
  SELECT visit_id, archetype, urgency, arrived_at, dispatch_due_at, lane, after_all,
         sum(est_min) AS lane_min
    FROM a GROUP BY 1,2,3,4,5,6,7
), cp AS (
  SELECT visit_id, archetype, urgency,
         COALESCE(max(lane_min) FILTER (WHERE NOT after_all),0)
       + COALESCE(sum(lane_min) FILTER (WHERE after_all),0) AS feasible_min,
         EXTRACT(epoch FROM (max(dispatch_due_at) - max(arrived_at)))/60 AS deadline_min
    FROM lanes GROUP BY 1,2,3
)
SELECT archetype, urgency, count(*) AS visits,
       round(min(feasible_min),0) AS min_feas,
       round(avg(feasible_min),1) AS avg_feas,
       round(max(feasible_min),0) AS max_feas,
       round(min(deadline_min),0) AS min_deadline,
       round(max(deadline_min),0) AS max_deadline,
       count(*) FILTER (WHERE feasible_min > deadline_min) AS provably_unachievable
  FROM cp
 GROUP BY 1,2
 ORDER BY visits DESC;

-- 4.3  The deadline is constant per urgency class, not per table. 0172's correction.
SELECT COALESCE(urgency,'(null)') AS urgency,
       count(*) AS visits,
       count(DISTINCT round((EXTRACT(epoch FROM (dispatch_due_at - arrived_at))/60)::numeric,0))
         AS distinct_windows,
       string_agg(DISTINCT round((EXTRACT(epoch FROM (dispatch_due_at - arrived_at))/60)::numeric,0)::text, ',')
         AS windows_min
  FROM public.ottoq_visit_needs
 WHERE sim_run_id = '5d00244c-10c8-4ffc-b6c0-20dff04024bb'::uuid
   AND arrived_at IS NOT NULL AND dispatch_due_at IS NOT NULL
 GROUP BY 1
 ORDER BY visits DESC;
