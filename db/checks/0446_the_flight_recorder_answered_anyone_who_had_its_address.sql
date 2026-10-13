-- 0446  **The flight recorder answered anyone who had its address.** The edge function ottoq-run-blackbox (v7,
--        verify_jwt off, no credential check, reading with the service role) gave any caller, with no key at all,
--        every run-scoped table of any run, the depot's vehicles, stalls and charge sessions, and the source of 49
--        engine functions. Fixed in the repo by edge-functions/_shared/blackbox_auth.ts and run_blackbox.ts
--        (branch build/edge-run-blackbox-auth); NOT DEPLOYED by the session that wrote this file. Measured
--        2026-10-13 between 18:04:23 and 18:32:12 UTC (1:04-1:32 PM CT; the first is the first query's now(), the
--        second the clock read after the last query), read-only.
--        The twin depot 11111111-... is the only site in it (CLAUDE.md rule 8): both runs named below ran there.
--
-- ══ §1 WHAT WAS OPEN (reproduce (1)-(3)) ═════════════════════════════════════════════════════════════════════════
--
--   (a) Deployed: ottoq-run-blackbox version 7, ACTIVE, verify_jwt false (Supabase get_edge_function, read at the
--       start of the window).
--       The deployed index.ts is byte-identical to this repo's copy before the change: sha256 0f63f9cf...318317e for
--       both, the hash _MANIFEST.md already carries (its "version 5" is the API's older number; same source). So the
--       repo copy was the right base, and the change was built on it.
--   (b) The source checks no credential: OPTIONS, then straight to createClient(SUPABASE_URL, SERVICE_ROLE_KEY).
--   (c) Probed with NO header at all, GET ?run=not-a-uuid at 18:07:22 UTC (1:07 PM CT): HTTP 500,
--       {"error":"invalid input syntax for type uuid: \"not-a-uuid\""}. That is Postgres answering, so an anonymous
--       request reached the database. The function_edge_logs row for it: GET | 500, curl/8.5.0, no apikey prefix.
--       (The probe used an invalid id on purpose: it returns no data.)
--   (d) What a valid id returns (from the source and the catalog, not downloaded): every relation
--       ottoq_run_blackbox_meta lists, 90 today (71 tables, 19 views, every public relation named ottoq% with a
--       sim_run_id column), each paged to 500,000+ rows; vehicles, stalls and ocpp_sessions at the run's depot; and
--       executed_code, the full source of the 49 public functions its pattern matches (315,910 characters: the
--       decide tick, the shield, the policy reads and writes, the sim, the cuOpt bridge). With no ?run it defaults to
--       the latest operator_demo run (176b2912-..., ended 16:22 UTC today).
--   (e) Of the 74 tables it reads (71 + vehicles, stalls, ocpp_sessions), the public key may SELECT 4 directly:
--       ottoq_comms_messages, ottoq_decisions, ottoq_external_proposals, ottoq_proposal_disposition_ledger, the
--       ones 0658 left on its allowlist. The other 70 0658 closed to the public key on 2026-10-10; this function
--       served all 74 to a caller holding nothing, the public key included. Reproduce (2).
--   (f) Size: the largest run-table in the database is 816bd28c-... (operator_demo, the twin depot, ended
--       2026-10-01 19:06 UTC) with 327,222 rows in ottoq_rule_evaluations, and 327,222 again in the view
--       ottoq_rule_evaluation_effect over it; then ocpp_messages 91,314, decisions 71,429, comms 53,352, recall
--       decisions and telemetry packets 52,686 each. v7 put all of it in one response. Reproduce (4).
--
-- ══ §2 WHO CALLS IT, AND WITH WHAT ═══════════════════════════════════════════════════════════════════════════════
--
--   Searched every repository under /home/user (ottoyarddepot-sim, ottoyard-OTTO-Q, ottoyard-field-ops,
--   otto-q-workspace, OTTOYARD-SITE, otto-q-core, OTTOYARD, OTTO-Defense, Otto-charge-arm, ottoq-intelligence,
--   ottoyard-agent-context, otto-q-core-snapshot) for run-blackbox / run_blackbox / blackbox, node_modules excluded.
--   ONE caller:
--     ottoyarddepot-sim src/lib/blackbox.ts downloadBlackbox(), lines 83-90, from the Runs tab's "Black Box" button
--     (src/components/tabs/TwinHistoryTab.tsx BlackBoxButton). It sends the PUBLIC key, OTTOQ_ANON_KEY (a legacy
--     anon JWT shipped in the bundle), as both apikey and Authorization: Bearer.
--   Everything else is prose: ottoyard-agent-context memory/project_blackbox_selfaudit.md ("verify_jwt=false,
--   apikey/anon ok": the open door was the design), docs/10_KNOWN_ISSUES.md P2-15, otto-q-workspace
--   OTTOQ_OEM_READINESS_SCORECARD.md (which already flagged "the open ottoq-run-blackbox export" as a carve-out from
--   the founder-deferred security gate), MOAT_AUDIT.md, and a snapshot copy of the function. No script, cron job or
--   database function calls it (0213 found the same: no DB caller).
--   Function logs, 2026-10-05 20:31 UTC (the oldest row the API returned) to 2026-10-13 18:10 UTC, read as eight
--   24-hour windows of function_edge_logs: ZERO requests to ottoq-run-blackbox except the probe in §1 (c). The
--   button has not been pressed in eight days.
--
-- ══ §3 WHAT THE CHANGE DOES (edge-functions/ottoq-run-blackbox/index.ts, _shared/blackbox_auth.ts, _shared/run_blackbox.ts) ══
--
--   (a) A credential first. A request needs the service-role key (Authorization: Bearer or apikey, compared with
--       SUPABASE_SERVICE_ROLE_KEY) or an operator export token (x-ottoq-export-token, compared with the new edge
--       secret OTTOQ_BLACKBOX_TOKEN; unset or shorter than 32 characters means only the service key opens it).
--       Anything else: 401 {"error":"unauthorized","detail":...} with WWW-Authenticate, before the URL, the body or
--       the database are read. Both sides are SHA-256 hashed and the digests compared with a no-early-exit XOR
--       fold; every applicable comparison runs before any result is read. The channels do not cross.
--   (b) At most 50,000 rows per table per request, with a cursor: ?page=n (or "page" in a POST body) returns rows
--       [50,000n, 50,000n + 50,000) of every table. The bundle gains one key, export_paging {row_cap_per_table, page,
--       first_row, tables_with_more_rows, next_page, next, order}, and the response one header, X-OTTOQ-Next-Page
--       (a number or "none"). Page 0 is what a caller that never sends page gets. A later page's file name ends
--       "-p<n>.json".
--   (c) Everything else as v7: the default run, the meta RPC, the table list, the depot tables, _export_error rows,
--       the 404 and 500 answers, page 0's file name. The CORS allow list adds x-ottoq-export-token, so a browser may
--       send it; a page that is not a whole number 0..1000 is a 400 (after the credential, before the database).
--   (d) The cursor is an OFFSET in the order the database returns sim_run_id = run with no ORDER BY, which is the
--       order v7 already relied on between its own 1,000-row pages. The 90 relations share no key to order by (70
--       tables carry 53 different primary-key column lists, one table has none, 19 are views). On a stopped run the
--       order holds; on a run still writing, a later page can repeat or miss rows. export_paging.order says so.
--   tests/run_blackbox_auth.test.mjs: 27 tests, 27 pass (node 22.22). Mutation-checked: removing the 401 gate fails
--   5; raising the cap to 500,000 fails 5; short-circuiting the comparisons fails 1; a plain === in the comparator
--   fails 1. tsc --strict over the two shared modules and the shell (with a Deno shim): clean.
--
-- ══ §4 THE TWIN APP'S BLACK BOX BUTTON WILL ANSWER 401 AFTER DEPLOY, AND THE SMALLEST SAFE PATH ══════════════════
--
--   Not silently: downloadBlackbox throws "Black Box download failed (401): " plus the first 200 characters of the
--   body, and the Runs tab shows it as a toast, so the operator reads "unauthorized ... Send the operator export
--   token in x-ottoq-export-token ...". It is the only caller, and §2 shows nobody pressed it in eight days.
--   There is NO operator-authenticated route in the twin app to send it through. otto-twin-control runs in
--   "DEMO MODE — open on a private link": its authOk() is not enforced (void authOk), and the app's operator key
--   (localStorage otto_operator_key) is optional and checked by nothing. A /blackbox route there would move the hole,
--   not close it. And the service key must never go to a browser.
--   SMALLEST SAFE PATH (a twin-app change, not made here; ottoyarddepot-sim is Lovable-synced, so it is a PR for
--   Chase):
--     src/lib/blackbox.ts, downloadBlackbox: read an export token the operator pasted once
--     (localStorage 'otto_blackbox_token', set beside the existing operator key) and add it to the fetch headers as
--     "x-ottoq-export-token". If none is set, show "Paste the Black Box export token to download" instead of calling.
--     About five lines; the token lives in that operator's browser only, never in the bundle. The edge function's CORS
--     list already allows the header. Until then the lead (or Chase) downloads with curl and the token, §6 (h).
--   OPEN-ITEM: the twin app's Black Box button sends the public key and answers 401 once this deploys; it needs the export-token header (§4)
--
-- ══ §5 NOT CHANGED HERE, AND STILL OPEN ══════════════════════════════════════════════════════════════════════════
--
--   (a) THE SAME EXPORT HAS A SECOND DOOR IN THE DATABASE, and this change does not close it. Two SECURITY DEFINER
--       functions carry ACL {postgres, authenticated, service_role} (anon: no):
--         public.ottoq_run_blackbox(uuid)       md5 4f96d37ef15bcf3fac9a79023f99c729: the monolithic v1. It returns
--                                               the WHOLE bundle: every listed relation to 200,000 rows each, the
--                                               depot tables and the 49 function sources, under a 150 s local
--                                               statement_timeout.
--         public.ottoq_run_blackbox_meta(uuid)  md5 06ec6069b1f08a5ce51a18e2e2764123: the run row and the sources.
--       Any signed-in user reaches both through PostgREST (/rest/v1/rpc/...), without the edge function; the
--       field-ops demo logins share one password in a public repo (G393/G394). No caller of the first exists in any
--       repo here (the edge function calls only the second, with the service role), so revoking EXECUTE on both from
--       authenticated should break nothing; it is a migration, one concern, and not this item. Reproduce (1).
--   OPEN-ITEM: ottoq_run_blackbox(uuid) and ottoq_run_blackbox_meta(uuid) are EXECUTE-able by authenticated, a second door to the whole export (§5 a)
--   (b) The four tables 0658 left readable by the public key stay readable (its own §3 names them as next).
--   (c) A keyset cursor needs each table's key from ottoq_run_blackbox_meta: a migration, if offset paging bites.
--   (d) Only the legacy service-role JWT in SUPABASE_SERVICE_ROLE_KEY is accepted as the service key. A caller
--       holding only an sb_secret_ key uses the export token.
--   (e) No migration, no forces_recert, no tick path: the change is an edge function nobody's run reads.
--
-- ══ §6 AFTER DEPLOY: THE PROBES, AND WHAT EACH MUST RETURN ═══════════════════════════════════════════════════════
--
--   Deploy (a person; this session deployed nothing):
--     supabase secrets set OTTOQ_BLACKBOX_TOKEN=$(openssl rand -hex 32) --project-ref gxdrcyphqjzjsuhxuqtg
--     supabase functions deploy ottoq-run-blackbox --project-ref gxdrcyphqjzjsuhxuqtg --no-verify-jwt
--   or the Supabase MCP deploy_edge_function with THREE files (entrypoint ottoq-run-blackbox/index.ts, plus
--   _shared/blackbox_auth.ts and _shared/run_blackbox.ts) and verify_jwt false; then read it back with
--   get_edge_function and hash the three files against the repo (_MANIFEST.md footnote 11 is the procedure).
--   verify_jwt must stay FALSE: the gateway refuses legacy JWT keys and the export token is not a JWT.
--
--     B=https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-run-blackbox
--     ANON=<OTTOQ_ANON_KEY from ottoyarddepot-sim src/lib/ottoTwin.ts>   PUB=<the project's sb_publishable_ key>
--     SVC=<the service-role key>   TOK=<OTTOQ_BLACKBOX_TOKEN>             (keep the last two out of files and history)
--
--   (a) curl -sS -w '\n%{http_code}\n' "$B?run=not-a-uuid"
--         401 {"error":"unauthorized",...}. THE DISCRIMINATING PROBE: v7 answered this exact URL with 500 and
--         Postgres's uuid error (§1 c). A 401 here proves the credential is checked before the database.
--   (b) curl -sS -o /dev/null -w '%{http_code}\n' "$B"                                                       401
--   (c) curl -sS -o /dev/null -w '%{http_code}\n' -H "apikey: $ANON" -H "Authorization: Bearer $ANON" "$B?run=not-a-uuid"
--         401: the twin app's own call
--   (d) curl -sS -o /dev/null -w '%{http_code}\n' -H "apikey: $PUB" "$B?run=not-a-uuid"                     401
--   (e) curl -sS -o /dev/null -w '%{http_code}\n' -H "x-ottoq-export-token: $(printf '0%.0s' {1..64})" "$B?run=not-a-uuid"
--         401
--   (f) curl -sS -w '\n%{http_code}\n' -H "Authorization: Bearer $SVC" "$B?run=not-a-uuid"
--         500 and the uuid error: the service key passes and reaches Postgres
--   (g) curl -sS -D h0.txt -o p0.json -H "Authorization: Bearer $SVC" "$B?run=816bd28c-e103-40ce-8839-f473af1d6416"
--         200; h0.txt carries X-OTTOQ-Next-Page: 1;
--         jq -c '.export_paging | {row_cap_per_table, page, next_page, tables_with_more_rows}' p0.json
--           {"row_cap_per_table":50000,"page":0,"next_page":1,"tables_with_more_rows":["ottoq_comms_messages",
--            "ottoq_decisions","ottoq_ocpp_messages","ottoq_recall_decisions","ottoq_rule_evaluation_effect",
--            "ottoq_rule_evaluations","ottoq_telemetry_packets"]}
--         jq '.data.ottoq_rule_evaluations | length' p0.json          50000
--         (no other relation of that run holds more than 50,000 rows: views measured up to 1,409, depot tables 2,753
--         charge sessions, 116 vehicles, 158 stalls. If (4) no longer finds the run, (4b) names one over the cap.)
--         Page 1: tables_with_more_rows ["ottoq_rule_evaluation_effect","ottoq_rule_evaluations"], ocpp_messages 41,314.
--   (h) curl -sS -D h6.txt -o p6.json -H "x-ottoq-export-token: $TOK" "$B?run=816bd28c-e103-40ce-8839-f473af1d6416&page=6"
--         200 with the token; X-OTTOQ-Next-Page: none; .data.ottoq_rule_evaluations | length = 27222
--         (327,222 - 300,000); .export_paging.next_page null. Pages 0-6 together: 327,222 rows, (4)'s count.
--   (i) curl -sS -D hd.txt -o pd.json -H "apikey: $SVC" "$B"
--         200 for the latest operator_demo run (176b2912-... at the time of writing, whose largest table holds 49,389
--         rows): X-OTTOQ-Next-Page: none, a file name without "-p".
--   (j) curl -sS -i -X OPTIONS "$B" | grep -i access-control-allow-headers
--         ... apikey, content-type, x-ottoq-export-token
--   (k) The logs: reproduce (5) over the probe window. Every probe above appears with the status listed, and the
--       function's own console lines read {"auth":"refused","reason":...} for (a)-(e) and {"auth":"accepted",
--       "via":"service_role"|"export_token",...} for (f)-(i), with no key in any line.
--
-- ══ REPRODUCE (read-only) ══

-- (1) the two export RPCs: definitions (md5 as of this file) and who may execute them. Expect
--     ottoq_run_blackbox(uuid)       4f96d37ef15bcf3fac9a79023f99c729, prosecdef true, anon false, authenticated TRUE, service_role true
--     ottoq_run_blackbox_meta(uuid)  06ec6069b1f08a5ce51a18e2e2764123, prosecdef true, anon false, authenticated TRUE, service_role true
--     (authenticated TRUE is §5 (a), still open; when its migration lands both read false). No cron job and no
--     function names the edge function: the last two columns read 0 and 0.
SELECT p.oid::regprocedure AS sig, md5(pg_get_functiondef(p.oid)) AS md5, p.prosecdef,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_exec,
       (SELECT count(*) FROM cron.job WHERE command ILIKE '%blackbox%') AS cron_jobs_naming_blackbox,
       (SELECT count(*) FROM pg_proc q WHERE q.prosrc ILIKE '%run-blackbox%') AS functions_naming_the_edge_function
  FROM pg_proc p
 WHERE p.oid IN ('public.ottoq_run_blackbox(uuid)'::regprocedure, 'public.ottoq_run_blackbox_meta(uuid)'::regprocedure)
 ORDER BY 1;

-- (2) the relations the export reads, and how many the public key reads without it.
--     Expect (2026-10-13): relations 74, anon_readable 4 (the 0658 allowlist's four named in §1 e).
WITH t AS (
  SELECT DISTINCT c.table_name
    FROM information_schema.columns c JOIN information_schema.tables tb USING (table_schema, table_name)
   WHERE c.table_schema = 'public' AND c.column_name = 'sim_run_id' AND c.table_name LIKE 'ottoq%'
     AND tb.table_type = 'BASE TABLE'
  UNION SELECT 'vehicles' UNION SELECT 'stalls' UNION SELECT 'ocpp_sessions'),
x AS (
  SELECT t.table_name, cl.relrowsecurity AS rls,
         has_table_privilege('anon', format('public.%I', t.table_name), 'SELECT') AS anon_select,
         EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = t.table_name
                    AND p.cmd IN ('SELECT', 'ALL') AND ('anon' = ANY (p.roles) OR 'public' = ANY (p.roles))) AS anon_policy
    FROM t JOIN pg_class cl ON cl.relname = t.table_name AND cl.relnamespace = 'public'::regnamespace)
SELECT count(*) AS relations,
       count(*) FILTER (WHERE anon_select AND (NOT rls OR anon_policy)) AS anon_readable,
       string_agg(table_name, ' ' ORDER BY table_name) FILTER (WHERE anon_select AND (NOT rls OR anon_policy)) AS which
  FROM x;

-- (3) what the export lists and ships besides the tables. Expect: 90 relations (71 tables, 19 views); 49 functions,
--     315,910 characters of source (both move as functions and tables are added).
SELECT (SELECT count(*) FROM information_schema.columns c JOIN information_schema.tables tb USING (table_schema, table_name)
         WHERE c.table_schema = 'public' AND c.column_name = 'sim_run_id' AND c.table_name LIKE 'ottoq%') AS relations,
       (SELECT count(*) FROM information_schema.columns c JOIN information_schema.tables tb USING (table_schema, table_name)
         WHERE c.table_schema = 'public' AND c.column_name = 'sim_run_id' AND c.table_name LIKE 'ottoq%'
           AND tb.table_type = 'VIEW') AS views,
       (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
         AND proname ~ '^ottoq_(sim_|decide_tick|greedy_tick|fifo_tick|manual_tick|l2_|cuopt_|energy_orchestrate|orchestrator_trigger|apply_ops_action|demo_metronome|deploy_target|policy_get|policy_set|shield|plan_visit|itin_leg|mark_visit|record_event|active_charge_cap|deploy_target_fraction|run_blackbox|sim_stop_and_reset)') AS functions_in_executed_code,
       (SELECT sum(length(pg_get_functiondef(oid))) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
         AND proname ~ '^ottoq_(sim_|decide_tick|greedy_tick|fifo_tick|manual_tick|l2_|cuopt_|energy_orchestrate|orchestrator_trigger|apply_ops_action|demo_metronome|deploy_target|policy_get|policy_set|shield|plan_visit|itin_leg|mark_visit|record_event|active_charge_cap|deploy_target_fraction|run_blackbox|sim_stop_and_reset)') AS source_chars;

-- (4) the probe run for §6 (g)-(h): still there, the twin depot, stopped, and over the cap. Expect depot
--     11111111-1111-1111-1111-111111111111, operator_demo, completed, ottoq_rule_evaluations 327222.
SELECT r.sim_run_id, r.depot_id, r.run_by, r.status, r.ended_at,
       (SELECT count(*) FROM public.ottoq_rule_evaluations e WHERE e.sim_run_id = r.sim_run_id) AS rule_evaluations
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '816bd28c-e103-40ce-8839-f473af1d6416';
-- (4b) if the purge has taken it: the twin-depot runs over the cap, largest first (one GROUP BY over the table).
SELECT e.sim_run_id, count(*) AS rule_evaluations
  FROM public.ottoq_rule_evaluations e JOIN public.ottoq_sim_runs r USING (sim_run_id)
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed'
 GROUP BY e.sim_run_id HAVING count(*) > 50000 ORDER BY 2 DESC LIMIT 3;

-- (5) the probes in the logs (Supabase logs query, ClickHouse; set the window to the probe minutes):
--   SELECT timestamp, log_attributes['request.method'] AS method, log_attributes['response.status_code'] AS status,
--          log_attributes['request.search'] AS search, log_attributes['request.sb.apikey.authorization.prefix'] AS key_prefix
--     FROM logs
--    WHERE source = 'function_edge_logs' AND log_attributes['request.pathname'] LIKE '%ottoq-run-blackbox%'
--    ORDER BY timestamp;
--   and the function's own lines:
--   SELECT timestamp, event_message FROM logs
--    WHERE source = 'function_logs' AND event_message LIKE '%ottoq-run-blackbox%' ORDER BY timestamp;
