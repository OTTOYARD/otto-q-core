-- coverage-guard.sql — THE STANDING ANSWER TO "WHAT EXISTS AND IS NEVER CALLED?"
--
-- Read-only. Run it like a round; it takes no arguments.
--
-- WHY IT EXISTS. `BUILD_QUEUE.md` names the most predictive heuristic this codebase
-- has: **do not look for what is missing — look for what exists and is never
-- called.** As of 2026-09-20 that heuristic has produced six findings
-- (`ottoq_purge_prior_runs` with no scheduler; `ottoq_cert_matrix.stale` with no
-- consumer; `0167`'s six assert functions with no caller; `0168`'s whole cost chain
-- unreachable at link 1; **G82**, 0360's reservation reclaimer wired into a function
-- the live metronome never calls; **G86**, `perimeter_walkaround` produced for 90%
-- of arrivals, mandatory, and with no executor anywhere). Every one was found by
-- hand. Two of the six were found on the same night, which is the argument for
-- mechanising it.
--
-- The same file's discipline table lists two of these as instruments that do not
-- exist yet — *"Which routines has nothing ever called?"* (built, ad-hoc) and
-- *"Which declared capability has no test?"* (MISSING). Sections 1 and 2 are those.
--
-- ══════════════════════════════════════════════════════════════════════════════
-- READ THE CAVEATS BEFORE THE OUTPUT. Static reachability inside the database
-- cannot see three real caller classes, so **a row here is a QUESTION, never a
-- verdict**:
--   * edge functions and the API call routines over PostgREST/RPC by name in
--     TypeScript — invisible here;
--   * `EXECUTE format(...)` builds names at run time — `ottoq_purge_prior_runs`
--     itself works this way, by registry lookup;
--   * a name that is a PREFIX of another is the trap that produced G82.
--     `position('ottoq_sim_advance_tick' in prosrc)` matches
--     `ottoq_sim_advance_tick_world`. **This file therefore matches on `name(`,
--     never on the bare name**, and that single decision is most of its value.
--   And it strips `--` comment lines before matching, because a routine named only
--   in a comment that explains why it was removed is not a caller (`0371`'s own P9
--   failed exactly that way).
-- ══════════════════════════════════════════════════════════════════════════════

\echo '=== 1. FUNCTIONS WITH NO IN-DATABASE CALLER ==================================='

WITH fns AS (
  SELECT p.oid, n.nspname AS sch, p.proname AS nm,
         --: executable text only; a name in a comment is not a call
         (SELECT COALESCE(string_agg(l, E'\n'), '')
            FROM unnest(string_to_array(p.prosrc, E'\n')) AS t(l)
           WHERE ltrim(l) NOT LIKE '--%')                       AS body
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     --: PROCEDURES TOO. The first cut said prokind='f' and therefore did not contain
     --: `ottoq_demo_metronome`, which is a PROCEDURE invoked by `CALL` from cron job
     --: 12. Excluding it made every routine the live metronome drives look
     --: unreachable in section 1b, including `ottoq_sim_advance_tick_world`. One
     --: character of over-narrowing, and the instrument lies in the direction that
     --: manufactures findings.
     AND p.prokind IN ('f','p')
), callers AS (
  SELECT f.nm,
         --: MATCH THE CALL SYNTAX, NOT THE BARE NAME. This is the G82 fix.
         (SELECT count(*) FROM fns g
           WHERE g.oid <> f.oid AND position(f.nm || '(' in g.body) > 0)     AS fn_callers,
         (SELECT count(*) FROM pg_views v
           WHERE v.schemaname IN ('public','ottoq','twin')
             AND position(f.nm || '(' in v.definition) > 0)                  AS view_callers,
         (SELECT count(*) FROM pg_trigger t
           WHERE NOT t.tgisinternal
             AND position(f.nm in pg_get_triggerdef(t.oid)) > 0)             AS trigger_callers,
         (SELECT count(*) FROM cron.job j
           WHERE position(f.nm in j.command) > 0)                            AS cron_callers,
         --: a function used as a column DEFAULT is reachable too
         (SELECT count(*) FROM pg_attrdef d
           WHERE position(f.nm || '(' in pg_get_expr(d.adbin, d.adrelid)) > 0) AS default_callers,
         f.sch
    FROM fns f
)
-- UNFILTERED THIS RETURNS 883 OF 1,335 ROUTINES AND IS THEREFORE USELESS: most of
-- them are the RPC surface the UI and edge functions call by name over PostgREST,
-- which no in-database query can see. So it is narrowed to the class where "exists
-- and is never called" has actually been a bug every time -- MAINTENANCE routines,
-- the ones that reclaim, sweep, reconcile, expire, purge or replan. Every one of the
-- six historical instances of the heuristic is in that class, G82 included. Widen the
-- regex when you want the long tail; do not read the long tail as findings.
SELECT sch, nm, fn_callers, view_callers, trigger_callers, cron_callers, default_callers
  FROM callers
 WHERE fn_callers + view_callers + trigger_callers + cron_callers + default_callers = 0
   --: the engine's own API surface is called from TypeScript and is expected here
   AND nm NOT LIKE 'ottoq_api_%'
   AND nm NOT LIKE '%_rpc'
   AND (nm ~ '_(release|reclaim|gc|sweep|reconcile|detect|purge|advance|recover|expire|close|settle|bind|repair|rebook|replan)_'
     OR nm ~ '_(release|reclaim|gc|sweep|reconcile|detect|purge|advance|recover|expire|close|settle|bind|repair|rebook|replan)$')
 ORDER BY sch, nm;

-- VALIDATED OUTPUT, 2026-09-20 04:58 UTC — eleven rows, which is a list a person can
-- actually work through:
--
--   ottoq.ottoq_release_stall_reservation         ottoq.ottoq_stage_advance_approval
--   public.ottoq_energy_mpc_replan (×3 overloads) public.ottoq_gc_stale_reservations
--   public.ottoq_purge_orphan_rows               public.ottoq_sim_advance_due_runs
--   public.ottoq_sweep_orphaned_visit_artifacts  twin.ottoq_sim_advance_clock
--                                                twin.ottoq_sim_advance_grid
--
-- Two of those are already understood and neither is a new finding:
-- `ottoq_gc_stale_reservations` is **G77** — its sim/wall clock defect was fixed by
-- 0360 and it was deliberately never scheduled, because 0367 and 0369 replaced what
-- it was for; and `ottoq_energy_mpc_replan` is the shape of an edge-function entry
-- point (`ottoq-energy-mpc` calls it), which is precisely the caller class this query
-- cannot see. The rest are unexamined and are questions for whoever runs this next.

\echo ''
\echo '=== 1b. AND THE SHARPER QUESTION: CALLED, BUT NOT FROM THE LIVE TICK PATH ====='
-- G82's actual shape. `ottoq_release_unusable_reservations` had a caller -- it was
-- called from `ottoq_sim_advance_tick`, which nothing calls. Section 1 would have
-- said "fine". So: which functions are reachable ONLY through a function that is
-- itself unreachable from the live entry points?
--
-- The live entry points, named explicitly rather than inferred, are the cron
-- commands plus the two the metronome drives directly.

WITH RECURSIVE fns AS (
  SELECT p.oid, n.nspname AS sch, p.proname AS nm, p.prokind,
         (SELECT COALESCE(string_agg(l, E'\n'), '')
            FROM unnest(string_to_array(p.prosrc, E'\n')) AS t(l)
           WHERE ltrim(l) NOT LIKE '--%') AS body
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')
), roots AS (
  SELECT DISTINCT f.nm
    FROM fns f
   WHERE EXISTS (SELECT 1 FROM cron.job j
                  WHERE j.active AND position(f.nm in j.command) > 0)
      OR EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE NOT t.tgisinternal
                    AND position(f.nm in pg_get_triggerdef(t.oid)) > 0)
), reach AS (
  SELECT nm FROM roots
  UNION
  SELECT g.nm
    FROM reach r
    JOIN fns caller ON caller.nm = r.nm
    JOIN fns g      ON g.oid <> caller.oid
                   AND position(g.nm || '(' in caller.body) > 0
)
SELECT f.sch, f.nm, f.prokind,
       --: it HAS callers (so section 1 is silent) but none of them run
       (SELECT count(*) FROM fns g WHERE g.oid <> f.oid
         AND position(f.nm || '(' in g.body) > 0) AS in_db_callers
  FROM fns f
 WHERE f.nm NOT IN (SELECT nm FROM reach)
   AND EXISTS (SELECT 1 FROM fns g WHERE g.oid <> f.oid
                AND position(f.nm || '(' in g.body) > 0)
   AND f.nm NOT LIKE 'ottoq_api_%'
   AND f.nm NOT LIKE '%_rpc'
   AND (f.nm ~ '_(release|reclaim|gc|sweep|reconcile|detect|purge|advance|recover|expire|close|settle|bind|repair|rebook|replan)_'
     OR f.nm ~ '_(release|reclaim|gc|sweep|reconcile|detect|purge|advance|recover|expire|close|settle|bind|repair|rebook|replan)$')
 ORDER BY f.sch, f.nm;

-- VALIDATED OUTPUT, 2026-09-20 04:55 UTC — 45 roots, 314 routines reachable from
-- them, and FOUR rows here, which is what a sharp instrument looks like:
--
--   public.ottoq_sim_advance_tick              10 in-db callers   <- **G82, mechanically**
--   public.ottoq_sim_advance_and_snapshot        5
--   public.ottoq_purge_prior_runs                1   (known: called by dynamic SQL
--                                                     from ottoq_start_demo_run,
--                                                     which is RPC-invoked)
--   ottoq.ottoq_replan_after_charger_fault       1   <- **G88, and it led to 0372**
--
-- The validation that matters is the false positive that DISAPPEARED:
-- `ottoq_sim_advance_tick_world` was flagged by the prokind='f' version and is gone
-- from the fixed one, while `ottoq_sim_advance_tick` — the true finding — stayed. An
-- instrument that loses its known false positive and keeps its known true positive
-- is one you can believe on a row you have not seen before.

\echo ''
\echo '=== 2. SERVICES THE ENGINE DERIVES THAT NOTHING CAN COMPLETE =================='
-- G86's shape, mechanised. A service is suspicious when its atoms exist, none is
-- `done`, and some carry `must_do`. The `functions_naming_it` column is a FLOOR --
-- it cannot tell a producer from a completer -- so read a low number as "go trace
-- this by hand", which is exactly what `db/checks/0261` did for perimeter_walkaround.

WITH atoms AS (
  SELECT a->>'svc' AS svc, a->>'status' AS status, a->>'must_do' AS must_do,
         a->>'requires_bay' AS requires_bay
    FROM public.ottoq_visit_needs n
    CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
), rolled AS (
  SELECT svc,
         count(*)                                                      AS atoms,
         count(*) FILTER (WHERE status = 'done')                        AS done,
         count(*) FILTER (WHERE COALESCE(must_do,'') IN ('true','t'))   AS must_do,
         max(requires_bay)                                             AS requires_bay
    FROM atoms GROUP BY svc
)
SELECT z.svc, z.atoms, z.done, z.must_do, z.requires_bay,
       c.lane_stalls AS declared_lane_stalls,
       (c.svc IS NULL) AS undeclared_in_cadence_policy,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname IN ('public','ottoq','twin')
           AND position(z.svc in p.prosrc) > 0)                         AS functions_naming_it,
       CASE WHEN z.done = 0 AND z.must_do > 0 THEN '*** MANDATORY AND NEVER COMPLETED'
            WHEN z.done = 0 AND z.atoms > 0   THEN 'derived, never completed'
            WHEN c.svc IS NULL                THEN 'undeclared in the cadence policy'
            ELSE 'ok' END                                              AS verdict
  FROM rolled z
  LEFT JOIN public.service_cadence_policy c ON c.svc = z.svc
 ORDER BY (z.done = 0 AND z.must_do > 0) DESC, z.atoms DESC;

\echo ''
\echo '=== 3. EVENT TYPES EMITTED BUT NOT REGISTERED ================================='
-- C7 step 2's audit. Read the count as a FLOOR, not a total: `ottoq_events` is
-- run-scoped and the demo purge takes prior runs, so this sees only what the
-- surviving runs emitted. On run 3fb415d8 it was 25 of 57 -- including
-- `ottoq.refusal_escalated`, the single most informative event in the G82-G86
-- investigation. Cite the run, not the table.

SELECT z.event_type, z.emitted,
       (SELECT count(*) FROM pg_proc p WHERE position(z.event_type in p.prosrc) > 0) AS emitters
  FROM (SELECT e.event_type, count(*) AS emitted
          FROM public.ottoq_events e GROUP BY 1) z
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_event_types_catalog c
                    WHERE c.event_type = z.event_type)
 ORDER BY z.emitted DESC;

\echo ''
\echo '=== 4. DECLARED LANE CAPACITY THAT DOES NOT EXIST ============================='
-- The `interior_deep_clean` shape from `0260` §3(b): a service declaring
-- `lane_stalls = 0` while its bookings land on another lane's stalls. This is what
-- C11's `PACK_SPEC.md` validation has to assert for a pack to be called conformant,
-- so it belongs in a coverage instrument rather than in one check file.

SELECT c.svc, c.lane, c.lane_stalls AS declared, c.is_active,
       (SELECT count(*) FROM public.stalls s
         WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
           AND s.stall_type::text = c.lane)                            AS stalls_of_that_type,
       CASE WHEN c.lane_stalls = 0 THEN '*** declares zero capacity'
            WHEN c.lane_stalls IS NULL THEN 'no declaration'
            WHEN c.lane_stalls <> (SELECT count(*) FROM public.stalls s
                                    WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
                                      AND s.stall_type::text = c.lane)
              AND EXISTS (SELECT 1 FROM public.stalls s
                           WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
                             AND s.stall_type::text = c.lane)
              THEN 'declared count disagrees with the depot'
            ELSE 'ok' END                                              AS verdict
  FROM public.service_cadence_policy c
 WHERE c.is_active
 ORDER BY (c.lane_stalls = 0) DESC NULLS LAST, c.svc;
