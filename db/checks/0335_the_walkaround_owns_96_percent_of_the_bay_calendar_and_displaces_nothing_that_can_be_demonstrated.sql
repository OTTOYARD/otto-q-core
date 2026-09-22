-- 0335  **`perimeter_walkaround` — a service performed AT THE VEHICLE that needs no bay — holds 95.9% of
--       every service-bay booking-minute on the twin depot. And it displaces nothing that can be
--       demonstrated: mandatory bay completion rises monotonically with run length (17.0% → 44.4% →
--       57.1%), which is the signature of runs ENDING, not of a resource being contended.**
--
--       Opened as G145 to answer "does it displace real work?" The answer is **not demonstrated**, and
--       the finding that survives is waste plus a corrupted KPI, not a capacity wall.
--
--       **And I nearly published the opposite conclusion twice in ten minutes**, from two different
--       defects in my own queries. §4 is the part worth keeping.
--
--       Measured 2026-09-22 ~14:0x UTC (09:0x CT), twin depot only per rule 8.
--
-- ══ §1 THE BAY CALENDAR, AND IT IS NOT CLOSE ═════════════════════════════════
--
-- Every `service_bay` booking on `depot_id='11111111-…'` carrying a `sim_run_id`:
--
--     need_atom               bookings   bay-minutes   % of minutes   mean min   runs
--     ---------------------  ---------  ------------  -------------  ---------  -----
--     perimeter_walkaround       2,579        38,358       **95.9%**       14.9     38
--     (no need_atom)                71         1,653          4.1%         23.3     14
--
-- **There is no third row.** No bay-requiring service atom books a service bay by `need_atom` at all;
-- the only other bookings carry `need_atom IS NULL`, which `0383` established is what a parking hold
-- looks like. So on this depot the service-bay calendar is, to 96%, a record of a service that is
-- performed at the vehicle.
--
-- **That is enough on its own to matter, for a reason that is not capacity:** any bay-utilisation number
-- read off this calendar is 96% an artifact. `2.9`'s KPI 2 is `service_point_turns_per_point_per_day`.
-- Computed over service bays today it would be measuring the walkaround.
--
-- ══ §2 DISPLACEMENT: NOT DEMONSTRATED, AND THE SHAPE SAYS WHY ════════════════
--
-- Mandatory (`must_do`) bay atoms on the twin depot, bucketed by how long their run lasted:
--
--     run_by           run length     runs   must_do bay   done   % done
--     --------------  -------------  -----  ------------  -----  -------
--     cert_harness     12-23 ticks      24           810    138   **17.0%**
--     cert_harness     24-47 ticks       8           324    144   **44.4%**
--     cert_harness     48+ ticks         4           196    112   **57.1%**
--     operator_demo    48+ ticks         1            38      8     21.1%
--     production_live  <12 ticks         1             6      2     33.3%
--
-- **Monotone in run length across the cert arms: 17.0 → 44.4 → 57.1.** A 12-tick pair is six sim-hours.
-- Bay work scheduled beyond the horizon does not happen because the run stopped, not because a bay was
-- busy. If the walkaround were starving the bays, completion would be flat or falling in run length —
-- a longer run gives the walkaround more time to hold the calendar too.
--
-- **What that does NOT establish.** 57.1% at 48 ticks is not 100%, so a real effect could live inside
-- the residual. It cannot be isolated here: the 48-tick bucket is **one canon column, 196 atoms**, and
-- the twin's only long runs are cert arms. **The honest verdict is "not demonstrated", not "absent".**
-- Settling it needs a 48-tick run with the walkaround's bay bookings suppressed, compared under CRN
-- against one without — which is a `0421`-style pair with a policy variation, i.e. exactly the
-- instrument `C5` describes and the one thing `db/checks/0145` says does not yet exist.
--
-- ══ §3 SO WHAT SHOULD CHANGE ═════════════════════════════════════════════════
--
--   1. **Stop booking a bay for a vehicle-side service.** `0383` made the walkaround
--      `concurrency='exterior'` with `lane_stalls=NULL`; the booking is left over from when it was
--      `hold`. This is waste and a KPI contaminant whether or not it displaces anything.
--   2. **It is also the direct cause of `0333`'s HW.006 noise** — the probe resolves a stall by
--      `need_atom`, finds one of these 2,579, and hands HW.006 a bay the work was never in. Fixing (1)
--      fixes that without touching the probe, which is the better order.
--   3. **Do not quote service-bay utilisation from this calendar** until (1) lands.
--
-- ══ §4 TWO DEFECTS IN MY OWN QUERIES, TEN MINUTES APART, OPPOSITE DIRECTIONS ═
--
-- **(a) `<>` IS NOT `IS DISTINCT FROM`, and it cost the whole conclusion.** The first pass counted
-- unfinished mandatory bay atoms with `status <> 'done'` and reported **4** — i.e. 99.7% completion, "no
-- displacement, nothing to see." The real number is **970**, because **966 of the 1,374 atoms carry
-- `status IS NULL`** (plus 4 `open`) and `NULL <> 'done'` evaluates to NULL, which a `FILTER` drops. One operator,
-- three-valued logic, and a count of unfinished work off by a factor of **242** in the flattering direction.
--
--     status    n
--     --------  ---
--     (NULL)    966
--     done      404
--     open        4
--
-- **(b) And then the day-partition looked like it had caught (a), which it had not.** Applying `0334`'s
-- brand-new rule — partition before quoting — moved 99.7% to 29.4% and I briefly read that as the
-- partition working. It was not: both figures come from the same day. **The partition was innocent and
-- the operator was guilty**, and crediting the wrong fix would have left the real one in place.
--
-- **The rule that generalises, and it is narrower than "be careful":** a count of things that did NOT
-- happen must use `IS DISTINCT FROM`, because "did not happen" is exactly the state most likely to be
-- recorded as NULL. Every `FILTER (WHERE x <> 'done')` in this repo is suspect for the same reason.
--
-- **Eighth instance of the family** after `0329`, `0413`, `0326` §1, `0331`, `0332` and `0334`: a
-- measurement that answers a different question than the one asked. This is the first where the cause
-- is a SQL operator rather than a semantic mismatch, which makes it the easiest to grep for and the
-- easiest to repeat.

\echo '=== 0335 §1 — 96% of the twin depot bay calendar is a service that needs no bay ==='
WITH bk AS (
  SELECT b.sim_run_id, b.need_atom,
         EXTRACT(epoch FROM (upper(b.during) - lower(b.during)))/60.0 AS minutes
    FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id=b.stall_id
   WHERE s.depot_id='11111111-1111-1111-1111-111111111111' AND s.stall_type='service_bay'
     AND b.sim_run_id IS NOT NULL
)
SELECT COALESCE(need_atom,'(no need_atom)') AS need_atom,
       count(*) AS bookings,
       round(sum(minutes)) AS total_bay_minutes,
       round(100.0*sum(minutes)/SUM(sum(minutes)) OVER (),1) AS pct_of_bay_minutes,
       round(avg(minutes),1) AS mean_minutes, count(DISTINCT sim_run_id) AS runs
  FROM bk GROUP BY 1 ORDER BY total_bay_minutes DESC NULLS LAST;
-- Two rows, and the second is parking holds (need_atom IS NULL, per 0383). No bay-requiring service
-- atom books a service bay by need_atom at all.

\echo '=== 0335 §2 — completion is monotone in RUN LENGTH: truncation, not contention ==='
WITH atoms AS (
  SELECT vn.sim_run_id, r.tick_count, r.run_by, a->>'status' AS status
    FROM public.ottoq_visit_needs vn
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = vn.sim_run_id
   CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
   WHERE vn.depot_id='11111111-1111-1111-1111-111111111111'
     AND a->>'concurrency'='bay' AND COALESCE((a->>'must_do')::boolean,false)
)
SELECT run_by,
       CASE WHEN tick_count < 12 THEN 'a: <12 ticks' WHEN tick_count < 24 THEN 'b: 12-23'
            WHEN tick_count < 48 THEN 'c: 24-47'     ELSE 'd: 48+' END AS run_length,
       count(DISTINCT sim_run_id) AS runs, count(*) AS must_do_bay,
       count(*) FILTER (WHERE status='done') AS done,
       round(100.0*count(*) FILTER (WHERE status='done')/count(*),1) AS pct_done
  FROM atoms GROUP BY 1,2 ORDER BY 1,2;
-- 17.0 -> 44.4 -> 57.1 across the cert arms. Starvation would not improve with a longer run; the
-- walkaround holds the calendar for longer too.

\echo '=== 0335 §4 — the operator that cost the conclusion. Both counts, same rows ==='
WITH atoms AS (
  SELECT a->>'status' AS status
    FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
   WHERE vn.depot_id='11111111-1111-1111-1111-111111111111'
     AND a->>'concurrency'='bay' AND COALESCE((a->>'must_do')::boolean,false)
)
SELECT count(*) AS must_do_bay_atoms,
       count(*) FILTER (WHERE status = 'done')               AS done,
       count(*) FILTER (WHERE status <> 'done')              AS not_done_WRONG,
       count(*) FILTER (WHERE status IS DISTINCT FROM 'done') AS not_done_RIGHT,
       count(*) FILTER (WHERE status IS NULL)                AS status_is_null
  FROM atoms;
-- 1,374 / 404 done / not_done_WRONG = 4 / not_done_RIGHT = 970 / status_is_null = 966. NULL <> 'done' is NULL, and FILTER
-- drops it. A count of things that did NOT happen must use IS DISTINCT FROM, because "did not happen"
-- is the state most likely to be stored as NULL.

-- ══════════════════════════════════════════════════════════════════════════════
-- §5  THE G147 AUDIT, RUN RATHER THAN PROMISED — AND IT COMES BACK CLEAN
--     (appended 2026-09-22 ~14:1x UTC / 09:1x CT, same session)
-- ══════════════════════════════════════════════════════════════════════════════
--
-- §4 ended "every `FILTER (WHERE x <> '…')` in this repo is suspect" and filed the sweep as undone.
-- Done now. **The engine is clean; the defect was in my ad-hoc query and nowhere else.**
--
--     database functions using `<>` anywhere                        125
--     ... of which inside a FILTER (the dangerous shape)            **2**
--     ... of which actually able to fail open                       **0**
--     `ottoq_assert*` functions using `<>`                            5
--     ... of which inside a FILTER                                    0
--     ... of which actually able to fail open                       **0**
--
-- **The two FILTER sites, and why each is safe:**
--
--   * `ottoq_twin_determinism_verdict` — `FILTER (WHERE ma IS NOT NULL AND mb IS NOT NULL AND ha <> hb)`.
--     **Explicitly NULL-guarded on both sides before the comparison.** This is the function that decides
--     whether two arms disagree, i.e. the single place where this bug class would have been worst, and
--     it was written correctly.
--   * `ottoq_rules_headline` — `FILTER (WHERE status='active' AND reality<>'enforcing')` beside
--     `FILTER (WHERE status='active' AND reality='enforcing')`. A NULL `reality` would fall into neither
--     bucket, so the test is arithmetic rather than textual: **26 + 4 = 30 = `registered_active`.** The
--     partition sums, so nothing is being dropped.
--
-- **The five `ottoq_assert*` sites:** `ottoq_assert_kpi_touch_vocabulary` compares a `count(*)` (never
-- NULL); `ottoq_assert_snapshot_integrity` compares `content_hash`, which is `NOT NULL` with 0 nulls in
-- 1,746 rows; `ottoq_assert_policy_default_coherence` guards with `a.cat IS NOT NULL` in the same
-- predicate; `ottoq_assert_bess_state_vocabulary` compares two `COALESCE(..., '{}')` arrays; and
-- `ottoq_assert_clock_invariant`'s `f.playback_mode <> 'live'` is an early-return guard that fails in the
-- **safe** direction (a NULL mode over-asserts rather than under-asserts) and is bailed out two lines
-- later by an explicit `IS NULL` check.
--
-- ══ WHAT TO TAKE FROM A CLEAN RESULT ═════════════════════════════════════════
--
-- **The reusable guard is arithmetic, not vigilance.** `ottoq_rules_headline` was settled in one query
-- by asking whether its buckets sum to its total — not by reading its source. `0417`'s
-- `classes_sum_to_calls` and `0341` (a view that silently bucketed 1,161 of 1,676 rows nowhere) are the
-- same instrument. **Any partition of a population into named buckets should assert that the buckets sum
-- to the population**, and then a NULL cannot hide in the gap between them.
--
-- **And the honest shape of this finding: the codebase already knew the rule in two places and I did not
-- apply it in a throwaway query.** The engine's verdict function guards its NULLs; the intelligence view
-- asserts its classes sum. The failure was mine, it was ad hoc, and it never reached a migration or a
-- stored function. That is the blast radius, and it is worth stating as plainly as the finding would
-- have been.

\echo '=== 0335 §5 — the two FILTER sites in the whole function catalog, and both are safe ==='
WITH s AS (
  SELECT n.nspname||'.'||p.proname AS fn,
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq') AND p.prokind='f'
)
SELECT count(*) FILTER (WHERE position('<>' in src) > 0)            AS fns_using_neq,
       count(*) FILTER (WHERE src ~* 'FILTER\s*\(\s*WHERE[^)]*<>')  AS fns_with_neq_INSIDE_a_filter,
       count(*) FILTER (WHERE src ~* 'IS DISTINCT FROM')            AS fns_using_is_distinct_from,
       (SELECT jsonb_agg(fn ORDER BY fn) FROM s WHERE src ~* 'FILTER\s*\(\s*WHERE[^)]*<>') AS the_two_sites
  FROM s;
-- 125 / 2 / 42. The two sites are ottoq_twin_determinism_verdict (NULL-guarded on both sides) and
-- ottoq_rules_headline (settled by the sum below).

\echo '=== 0335 §5b — the arithmetic that settles ottoq_rules_headline without reading its source ==='
WITH h AS (SELECT public.ottoq_rules_headline() AS j)
SELECT (j->>'registered_active')::int      AS registered_active,
       (j->>'observed_enforcing')::int     AS observed_enforcing,
       (j->>'not_observed_in_window')::int AS not_observed_in_window,
       ((j->>'observed_enforcing')::int + (j->>'not_observed_in_window')::int
          = (j->>'registered_active')::int) AS buckets_sum_to_total
  FROM h;
-- 30 / 26 / 4 / true. A NULL `reality` would fall into neither bucket and break the sum. It does not.
-- This is the guard to reuse: assert the partition sums, and a NULL cannot hide between the buckets.
