-- =====================================================================
-- 0071  The certification was not running the deterministic core alone
--       The pair harness never quiesced the cuOpt proposer. 0152 drafted.
-- =====================================================================
--
-- Chase, 7:45 PM CT Sep 1: "disable whatever you need. Keep moving
-- forward with our deterministic layer alone."
--
-- §1  What every round-6 arm actually ran (first 12 arms, 7:05-7:50 PM CT)
-- -----------------------------------------------------------------------
-- ottoq_policy_get(arm, 'cuopt_propose_enabled', 1) resolved 1 on every
-- arm. No arm had a run-scoped policy row. Per arm, cuopt_invocation_log:
--
--   at CT  column               arm       enabled  posted  debounce  first_refusal_arm  edge/no_candidates  deferral_rows  proposals
--   7:05   busy_day/171717/12t  5f3b6e9a  1        1       11        7                  1                   58             3
--   7:05   busy_day/171717/12t  f526d6b9  1        1       11        7                  1                   58             3
--   7:14   busy_day/171717/12t  167b5d66  1        1       11        7                  1                   58             3
--   7:14   busy_day/171717/12t  60b69328  1        1       11        7                  1                   58             3
--   7:23   busy_day/314159/12t  05c2b9b1  1        1       11        7                  1                   58             6
--   7:23   busy_day/314159/12t  b53c382d  1        1       11        7                  1                   58             6
--   7:32   busy_day/314159/12t  febc9e3b  1        1       11        7                  1                   58             6
--   7:32   busy_day/314159/12t  fedf28a6  1        1       11        7                  1                   58             6
--   7:41   busy_day/424242/12t  0a8e8b62  1        1       11        5                  1                   57             4
--   7:41   busy_day/424242/12t  c73c5441  1        1       11        5                  1                   57             4
--   7:50   busy_day/424242/12t  5dc6b8f2  1        1       11        5                  1                   57             4
--   7:50   busy_day/424242/12t  b47a7ccf  1        1       11        5                  1                   57             4
--
-- Deferral rows across the 12 arms: 692 (688 'clear', 4 'spent' on the
-- final tick). Every row was armed, consumed for exactly one tick, then
-- cleared - 692 vehicle-ticks in which ottoq_cuopt_defer_hold held a
-- vehicle OUT of the greedy stall cursor. The 'proposals' column is the
-- engine's own deterministic proposers (greedy_constrained,
-- ottoq_service_priority) - not cuOpt; those stay.
--
-- §2  The mechanism
-- -----------------
-- ottoq_sim_decide_and_dispatch, every tick:
--   1. ottoq_cuopt_refresh(run) when the fire-beat heartbeat is stale
--      (always, for a cert arm - there is no metronome). Gate:
--      ottoq_policy_get(run,'cuopt_propose_enabled',1) < 1 -> 'policy_disabled'.
--      Otherwise: debounce (REAL 3 s), candidate predicate, pg_net POST to
--      ottoq-cuopt-propose, then ottoq_cuopt_defer_arm on the posted set.
--   2. ottoq_cuopt_first_refusal_arm(run, tick). Gate:
--      ottoq_policy_get(run,'cuopt_first_refusal_max_defers',1) = 0 -> return.
--      Otherwise arms a deferral row for every eligible at-gate vehicle.
--   3. ottoq_decide_tick's stall cursor: AND NOT ottoq_cuopt_defer_hold(run, v, tick)
--      which is TRUE iff propose_enabled >= 1 AND a row is 'spent' at this
--      tick AND no pending cuopt proposal exists for the vehicle.
-- So with the proposer enabled, the hold ledger shapes assignment order
-- even when cuOpt never answers - which it never did (0 NVIDIA calls).
--
-- §3  Why the pairs passed anyway
-- -------------------------------
-- The debounce compares fire_log.fired_at to now() - 3 s. now() is
-- frozen for the life of a transaction and the pair runs both arms in
-- ONE transaction, so after the first post every call is debounced
-- identically on both arms (posted=1, debounce=11 on every 12-tick arm).
-- The pg_net POST cannot transmit until commit, so the edge function
-- re-validates against a world that has no such run and abstains
-- ('no_candidates_in_instance', 0 proposals out, latency up to 10,459 ms).
-- Determinism held by an accident of transaction shape. A production
-- tick has neither property: one transaction per tick, real seconds
-- between them. That is the 0056 finding verbatim (33 invocations each,
-- 50 vs 47 holds, assignment order shifted), which quiesced the OLD cert
-- harness - ottoq_cert_arm_start, run_by='benchmark' - and never reached
-- this one - ottoq_determinism_pair, run_by='cert_harness'.
--
-- ottoq_production_start quiesces its run (cuopt_propose_enabled=0,
-- updated_by='production_start', 2026-08-30 05:06 UTC). Demo runs and
-- cert arms did not.
--
-- §4  The ledger, last 48 h, run_by = cert_harness
-- ------------------------------------------------
--   sql_gate/debounce                 3,374   latency total 9 ms
--   sql_gate/first_refusal_arm        1,618
--   edge/no_candidates_in_instance      244   latency avg 635 ms, max 10,459 ms, proposals_out 0
--   sql_gate/posted (reason NULL)       242
--   sql_gate/policy_disabled              0   <- the switch existed since 0056 and was never thrown here
-- NVIDIA calls: 0 (no http_status on any row).
--
-- §5  What changes (0152, drafted 8:05 PM CT, applies after round 6)
-- ------------------------------------------------------------------
-- (A) Global policy tier: cuopt_propose_enabled = 0 and
--     cuopt_first_refusal_max_defers = 0. ottoq_policy_get resolves
--     run -> depot -> global -> literal default, so every run without an
--     explicit override runs the deterministic core alone. Refusals are
--     still logged ('policy_disabled'), so the count stays honest.
--     Re-enable per run with a run-scoped 1 when the agentic layer comes.
-- (B) ottoq_determinism_pair pins both keys to 0 on every arm it starts,
--     so a later global re-enable cannot reach inside a certification.
-- forces_recert = TRUE. The canon will move (~57 held vehicle-ticks per
-- 12-tick arm now enter the cursor a tick earlier). Round 6 is the last
-- baseline with the proposer in the loop; round 7 establishes the
-- deterministic-only canon.
--
-- §6  Queries
-- -----------

-- 6.1 per-arm state and activity for a round (edit the started_at bound)
WITH arms AS (
  SELECT r.sim_run_id, to_char(r.started_at AT TIME ZONE 'America/Chicago','HH12:MI') AS ct,
         (r.validation_notes::jsonb->>'scenario')||'/'||(r.validation_notes::jsonb->>'seed')||'/'||(r.validation_notes::jsonb->>'ticks')||'t' AS col
    FROM ottoq_sim_runs r WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-02 00:00:00+00')
SELECT a.ct, a.col, left(a.sim_run_id::text,8) AS run,
       public.ottoq_policy_get(a.sim_run_id,'cuopt_propose_enabled',1) AS propose_enabled,
       public.ottoq_policy_get(a.sim_run_id,'cuopt_first_refusal_max_defers',1) AS max_defers,
       (SELECT count(*) FROM ottoq_policy_params pp WHERE pp.scope_type='run' AND pp.scope_id=a.sim_run_id) AS run_param_rows,
       (SELECT string_agg(k||'='||c, ' ') FROM (SELECT COALESCE(l.stage||'/'||l.abstained_reason, l.stage||'/posted') k, count(*) c
                                                 FROM cuopt_invocation_log l WHERE l.sim_run_id=a.sim_run_id GROUP BY 1 ORDER BY 1) z) AS invocations,
       (SELECT count(*) FROM ottoq_cuopt_deferrals d WHERE d.sim_run_id=a.sim_run_id) AS deferral_rows,
       (SELECT count(*) FROM ottoq_external_proposals x WHERE x.sim_run_id=a.sim_run_id) AS proposal_rows
  FROM arms a ORDER BY a.ct, a.sim_run_id;

-- 6.2 deferral rows by state and proposals by source for the same arms
WITH arms AS (SELECT sim_run_id FROM ottoq_sim_runs WHERE run_by='cert_harness' AND started_at >= '2026-09-02 00:00:00+00')
SELECT 'proposals' AS t, x.source||'/'||x.status||'/'||x.action_context AS k, count(*) AS n, count(DISTINCT x.sim_run_id) AS arms
  FROM ottoq_external_proposals x JOIN arms USING (sim_run_id) GROUP BY 2
UNION ALL
SELECT 'deferrals', d.state||'/defer_count='||d.defer_count, count(*), count(DISTINCT d.sim_run_id)
  FROM ottoq_cuopt_deferrals d JOIN arms USING (sim_run_id) GROUP BY 2
ORDER BY 1,2;

-- 6.3 the ledger by reason, last 48 h
SELECT r.run_by, l.stage, l.abstained_reason, l.http_status,
       count(*) AS n, sum(l.latency_ms) AS latency_ms_total,
       round(avg(l.latency_ms)) AS latency_ms_avg, max(l.latency_ms) AS latency_ms_max,
       sum(l.proposals_out) AS proposals_out
  FROM cuopt_invocation_log l LEFT JOIN ottoq_sim_runs r ON r.sim_run_id = l.sim_run_id
 WHERE l.called_at > now() - interval '48 hours'
 GROUP BY 1,2,3,4 ORDER BY n DESC;

-- 6.4 every reader of the two switches, and every caller of the proposer path
SELECT n.nspname||'.'||p.proname AS fn,
       (p.prosrc ILIKE '%cuopt_propose_enabled%')          AS reads_propose_enabled,
       (p.prosrc ILIKE '%cuopt_first_refusal_max_defers%') AS reads_max_defers,
       (p.prosrc ILIKE '%ottoq_cuopt_refresh(%')           AS calls_refresh,
       (p.prosrc ILIKE '%ottoq_cuopt_first_refusal_arm(%') AS calls_first_refusal_arm,
       (p.prosrc ILIKE '%ottoq_cuopt_defer_hold(%')        AS calls_defer_hold
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname NOT IN ('pg_catalog','information_schema')
   AND (p.prosrc ILIKE '%cuopt_propose_enabled%' OR p.prosrc ILIKE '%cuopt_first_refusal_max_defers%'
        OR p.prosrc ILIKE '%ottoq_cuopt_refresh(%' OR p.prosrc ILIKE '%ottoq_cuopt_first_refusal_arm(%'
        OR p.prosrc ILIKE '%ottoq_cuopt_defer_hold(%')
 ORDER BY 1;
-- Result 8:00 PM CT: ottoq_cert_arm_start (reads enabled), ottoq_cron_tick (reads enabled),
-- ottoq_cuopt_defer_hold (reads enabled), ottoq_cuopt_first_refusal_arm (reads max_defers),
-- ottoq_cuopt_refresh (reads enabled), ottoq_decide_tick (calls defer_hold),
-- ottoq_demo_metronome (calls refresh), ottoq_production_start (reads enabled),
-- ottoq_sim_decide_and_dispatch (calls refresh + first_refusal_arm).

-- 6.5 after 0152: expected on every new cert arm
--   propose_enabled = 0, max_defers = 0, run_param_rows >= 2,
--   invocations = 'sql_gate/policy_disabled=N' only, deferral_rows = 0.
