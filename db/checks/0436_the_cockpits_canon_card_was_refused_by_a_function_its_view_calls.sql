-- 0436  **The twin app's determinism canon card has been refused by the public API: its view calls a function the
--        public key may not call. 0658's check could not have seen it, and a count(*) probe cannot either.** (G394;
--        fixed by 0699.) Measured 2026-10-10 between 08:46:00 and 08:53:06 UTC (3:46-3:53 AM CT, both read from the
--        clock), read-only, preparing to verify 0658 from outside.
--
-- ══ §1 WHAT THE PUBLIC KEY GETS THROUGH THE API, BEFORE 0658 (the probe; reproduce (1)) ═══════════════════════════
--
--   Through https://gxdrcyphqjzjsuhxuqtg.supabase.co/rest/v1/<relation>?select=*&limit=1 with the public key, both the
--   legacy anon key and the publishable key, at 08:48 UTC: 14 of 0658's 15 listed relations answer 200;
--   ottoq_determinism_canon answers 401, code 42501. The six unlisted relations probed (ottoq_events,
--   ottoq_stall_bookings, ottoq_visit_needs, stalls, ottoq_sim_runs, ocpp_sessions) still answer 200: those are what
--   0658 closes. (The probe: scratchpad tools/probe_0658.py, status codes only.)
--
-- ══ §2 THE COCKPIT HAS BEEN REFUSED, NOT ONLY THE PROBE (edge logs; reproduce (2)) ════════════════════════════════
--
--   In the 24 hours before the probe, every public-key request for /rest/v1/ottoq_determinism_canon answered 401: 4
--   requests, the last at 05:31 UTC. The only other public-key refusals in that window: ottoq_agent_oauth 404 (another
--   session's 0700, not yet applied), ottow_api_keys 403 (at 23:32:35 UTC, 12 seconds after 0649 applied: most likely
--   its own probe, not traced), and one 500 each from
--   ottoq_twin_run_list and ottoq_sim_stop_and_reset at 13:00 UTC on 10-09 (errors, not permissions; not followed here).
--
-- ══ §3 WHY (reproduce (3)) ══════════════════════════════════════════════════════════════════════════════════════
--
--   The view's tables (ottoq_cert_columns, ottoq_determinism_verdict_ledger) are read with its owner's rights. Its
--   function is not: "Functions called in the view are treated the same as if they had been called directly from the
--   query using the view. Therefore, the user of a view must have permissions to call all functions used by the view"
--   (PostgreSQL 17, CREATE VIEW, Notes, https://www.postgresql.org/docs/17/sql-createview.html, read 2026-10-10; the
--   engine runs 17.6). The view calls public.ottoq_cert_recert_floor(), STABLE and SECURITY DEFINER, whose ACL is
--   {postgres=X/postgres,service_role=X/postgres}. 0141 made it SECURITY DEFINER so the public key could read the
--   floor; 0198 took EXECUTE on every SECURITY DEFINER function in public from anon and PUBLIC.
--
--   Two instruments miss it, and both are the reusable part:
--     - 0658's V2 checks the two views by privilege (has_table_privilege), which is true for the canon view: the
--       refusal is a function privilege the view's SELECT grant does not cover;
--     - a probe that reads count(*) through the view never calls the function a column is built on (the planner drops
--       the unused column), so it reads while the cockpit's select=* is refused. 0699's first local run made exactly
--       this mistake; its probe now reads whole rows (count(to_jsonb(c))), as the cockpit does.
--
-- ══ §4 WHAT FOLLOWS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   0699: GRANT EXECUTE on public.ottoq_cert_recert_floor() to anon, after 0658. One STABLE function returning one
--   timestamp; 0198's rule (nobody anonymous changes the world) stands. Its P2 and V1 read the view as the public key
--   with whole rows, with a control table that must still refuse. After both apply, the probe of §1 is run again: the
--   15 must answer 200 and the six 401.
--
-- ══ REPRODUCE (read-only) ══

-- (1) the probe: python3 -I tools/probe_0658.py <key file>   (status codes only; never prints the key)

-- (2) the edge logs (Supabase logs query, ClickHouse; the 24 hours to 2026-10-10 08:48 UTC):
--   SELECT log_attributes['request.path'] AS path, log_attributes['response.status_code'] AS status, count() AS n,
--          max(timestamp) AS last_seen
--     FROM logs
--    WHERE source = 'edge_logs' AND log_attributes['request.path'] LIKE '/rest/v1/%'
--      AND log_attributes['request.sb.jwt.authorization.payload.role'] IN ('anon', '')
--      AND log_attributes['response.status_code'] NOT IN ('200', '201', '204', '206', '304')
--    GROUP BY path, status ORDER BY n DESC;

-- (3) the view, what it calls, and who may call it
SELECT c.relname, has_table_privilege('anon', c.oid, 'SELECT') AS anon_selects_the_view,
       (SELECT string_agg(DISTINCT p.oid::regprocedure::text || ' ' || CASE WHEN has_function_privilege('anon', p.oid, 'EXECUTE')
                          THEN 'anon may call' ELSE 'anon may NOT call' END, '; ')
          FROM pg_depend d JOIN pg_rewrite rw ON rw.oid = d.objid JOIN pg_proc p ON p.oid = d.refobjid
         WHERE rw.ev_class = c.oid AND d.classid = 'pg_rewrite'::regclass AND d.refclassid = 'pg_proc'::regclass) AS functions,
       (SELECT proacl::text FROM pg_proc WHERE oid = 'public.ottoq_cert_recert_floor()'::regprocedure) AS floor_acl
  FROM pg_class c WHERE c.oid = 'public.ottoq_determinism_canon'::regclass;
