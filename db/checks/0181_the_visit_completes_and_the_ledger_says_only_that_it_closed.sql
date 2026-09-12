-- ===========================================================================
-- 0181  THE VISIT COMPLETES, AND THE LEDGER SAYS ONLY THAT IT CLOSED
--       (the completion transition is wired, on the tick path, and has
--        produced zero rows in 110,601)
-- ===========================================================================
-- Measured 2026-09-12 15:00-15:15 UTC (10:00-10:15 AM CT), read-only, while round 38
-- ran. Nothing was written; no run was started.
--
-- A read-only workflow (run wf_3c9381c5-f7a, five investigators plus adversarial
-- verify) was asked whether ottoq_visit_needs is an append-only derivation log by
-- design or has a never-wired completion transition. Its direction was right. ITS
-- HEADLINE REASON WAS WRONG, and the difference matters, so this file records what I
-- measured from the function bodies rather than what it reported.
--
-- ---------------------------------------------------------------------------
-- 1. WHAT IT CLAIMED, AND THE ONE QUERY THAT REFUTES IT
-- ---------------------------------------------------------------------------
--
-- CLAIMED: "'complete' has exactly ONE writer and it is unreachable: derive_visit_needs
-- sets status='complete' only on a row it found with status='carried_over', and NOTHING
-- anywhere writes 'carried_over' -- both occurrences of that literal are read predicates."
--
-- MEASURED -- every routine in public/ottoq/twin mentioning the literal, with context:
--
--   ottoq.ottoq_derive_visit_needs            WHERE ... status = 'carried_over'      READ
--   ottoq.ottoq_release_visit_artifacts       status IN (...,'carried_over')         READ
--   public.ottoq_agent_board                  WHERE ... status='carried_over'        READ
--   public.ottoq_boot_state_fingerprint       st IN (...,'carried_over')  x2          READ
--   public.ottoq_sweep_orphaned_visit_artifacts  vn.status IN (...,'carried_over')   READ
--   twin.ottoq_sim_advance_visit_atoms        THEN 'carried_over' ELSE 'complete' END  ** WRITE **
--
-- There IS a writer, it writes BOTH terminal values, and it is not obscure: it is the
-- last statement of twin.ottoq_sim_advance_visit_atoms, which ottoq_sim_advance_tick_world
-- calls at line 34 OF EVERY TICK.
--
-- ---------------------------------------------------------------------------
-- 2. THE TRANSITION, AS WRITTEN
-- ---------------------------------------------------------------------------
--
--   UPDATE ottoq_visit_needs vn SET status =
--     CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
--                        WHERE COALESCE((a->>'carryover_eligible')::boolean,false)
--                          AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))
--          THEN 'carried_over' ELSE 'complete' END
--   FROM vehicles v
--   WHERE v.id = vn.vehicle_id AND vn.depot_id = v_depot
--     AND vn.status IN ('open','in_progress') AND <run scope>
--     AND v.current_state IN ('deployed','en_route_to_deployment');
--
-- The semantics are right and worth saying plainly: a visit is COMPLETE when the asset
-- has gone back out, and CARRIED_OVER when it went out with deferrable work still
-- undone. That is exactly the distinction a service ledger should make.
--
-- ---------------------------------------------------------------------------
-- 3. AND IT HAS NEVER FIRED. 110,601 ROWS, ONE VALUE
-- ---------------------------------------------------------------------------
--
--   needs rows, all time   110,601
--   status census          superseded: 110,601
--   status = 'complete'              0
--   status = 'carried_over'          0
--
-- WHY, under the otto_q path, by construction rather than by luck. Both halves live in
-- ONE function, twin.ottoq_sim_dispatch_vehicle, eleven lines apart with no tick
-- boundary between them:
--
--   line 79  UPDATE vehicles
--   line 80     SET current_state = 'deployed'::vehicle_state, ...
--   line 90  BEGIN PERFORM ottoq_release_visit_artifacts(p_vehicle_id, p_sim_run_id,
--                                                       p_sim_clock_now, 'redeployed');
--
-- and release_visit_artifacts supersedes status IN ('open','in_progress','carried_over').
-- So the moment a vehicle becomes eligible for the terminal UPDATE, the same function
-- has already taken the row out of the set that UPDATE scans. The next tick looks for
-- open/in_progress + deployed and finds nothing. The window is not small; it is empty.
--
-- WHAT I AM NOT CLAIMING. Thirteen routines write a deployed state and only
-- dispatch_vehicle calls release:
--
--   busy_day_probe_tick, ottoq_cert_arm, ottoq_cert_arm_start, ottoq_cert_arm_wave,
--   ottoq_fifo_tick, ottoq_fr1_cert_arm, ottoq_manual_tick, ottoq_plan_dispatch_tick,
--   ottoq_sim_advance_and_snapshot, twin.ottoq_sim_dispatch_vehicle,
--   twin.ottoq_sim_prime_deployment, twin.ottoq_sim_start_run,
--   ottoq_sweep_stranded_deployments
--
-- so reachability is NOT provably zero everywhere -- a fifo or manual tick sets
-- en_route_to_deployment directly and does not release. It has simply never produced a
-- row. Most of those twelve write the state at run START, before any need exists
-- (prime_deployment, start_run), or belong to dormant harnesses (the cert_arm family,
-- measured at zero tracked calls). "Unreachable under otto_q" is established; "dead
-- code" is not, and is not asserted.
--
-- ---------------------------------------------------------------------------
-- 4. WHY THIS IS A PRODUCT FINDING AND NOT A CURIOSITY
-- ---------------------------------------------------------------------------
--
-- The row status cannot distinguish A VISIT THAT FINISHED from A VISIT THAT WAS
-- ABANDONED. Both read 'superseded' -- the redeploy release writes it, the run-end
-- janitor writes it, and the pre-insert supersede writes it. A ledger that records
-- closure and not completion cannot answer "was this asset serviced before it left?"
-- at the row level.
--
-- That is exactly why db/checks/0177 had to read atoms[].status to build the intent's
-- second floor, and why 0257's metric is defined over atoms rather than rows. The
-- workaround is sound and the substrate is hash-enforced (0180). But the kernel's own
-- visit object is a worse record than the jsonb inside it, and CLAUDE.md 2.6's
-- strategic instruction -- "every completed operation terminates in an SDR" -- is about
-- exactly this seam. An SDR emitter that asked the row whether the visit completed would
-- get 'superseded' every time.
--
-- THE FIX IS SMALL AND ORDERED, not a redesign: have the redeploy release DISTINGUISH
-- its own case. ottoq_release_visit_artifacts is called with a reason ('redeployed'),
-- and a redeploy is precisely the condition the terminal UPDATE tests for. So the
-- release should apply the same CASE -- complete / carried_over when the reason is
-- redeployed, superseded only when the visit is being abandoned. That also makes the
-- terminal UPDATE in advance_visit_atoms redundant under otto_q, which is the honest
-- shape: one writer for one transition.
--
-- COST, from 0180: ottoq_visit_needs rows are hashed into `endst` (the projection
-- excludes only visit_id, sim_run_id, created_at, updated_at, meta -- `status` is in).
-- Changing which terminal value a row carries MOVES endst. So this is forces_recert=TRUE
-- and belongs in the same batched window as 4h, not in front of it. Filed, not drafted.
--
-- ---------------------------------------------------------------------------
-- 5. METHOD NOTE
-- ---------------------------------------------------------------------------
--
-- The workflow's error is instructive and is the reason its verdict was not taken on
-- report: it classified `THEN 'carried_over' ELSE 'complete' END` as a read. A literal
-- inside a CASE on the right-hand side of SET is a write, and no regexp over prosrc
-- distinguishes the two without looking at the statement. Third instance in this repo of
-- the same class -- 0173's sweep missed `v_now := now()` indirection, 0255 recorded it,
-- and an instrument's coverage is a claim needing its own evidence (0167).
--
-- ===========================================================================
-- RE-RUNNABLE MEASUREMENTS
-- ===========================================================================

-- 5.1  The census. One value, all time.
SELECT status, count(*) AS rows
  FROM public.ottoq_visit_needs
 GROUP BY 1
 ORDER BY rows DESC;

-- 5.2  Every mention of the terminal literals, with enough context to tell a read from
--      a write. The query the workflow's verdict needed and did not run.
WITH r AS (
  SELECT n.nspname||'.'||p.proname AS fn, p.prosrc AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND (p.prosrc LIKE '%carried_over%' OR p.prosrc LIKE '%''complete''%')
)
SELECT fn,
       (SELECT string_agg(trim(x[1]), ' ~~ ')
          FROM regexp_matches(src, '([^\n]{0,90}(carried_over|''complete'')[^\n]{0,40})', 'g') x)
         AS contexts
  FROM r
 ORDER BY fn;

-- 5.3  The pre-emption, in one function. Line 80 deploys, line 90 supersedes.
WITH s AS (
  SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_dispatch_vehicle'
), l AS (SELECT row_number() OVER () AS ln, line
           FROM s, regexp_split_to_table(s.prosrc, E'\n') AS line)
SELECT ln, line FROM l
 WHERE line ~ 'release_visit_artifacts|current_state\s*=|UPDATE vehicles'
 ORDER BY ln;

-- 5.4  Who else can leave a vehicle deployed without releasing its need. Thirteen
--      writers; exactly one calls release. This is the reason section 3 stops short of
--      "dead code".
SELECT n.nspname||'.'||p.proname AS writes_a_deployed_state,
       (p.prosrc ~ '\mottoq_release_visit_artifacts\M') AS also_releases
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','twin','ottoq')
   AND p.prosrc ~ 'current_state\s*=\s*''(deployed|en_route_to_deployment)'''
 ORDER BY 2 DESC, 1;
