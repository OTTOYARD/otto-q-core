-- 0446  **The flight recorder answered anyone who had its address.** The edge function ottoq-run-blackbox (v7,
--        verify_jwt off, no credential check, reading with the service role) gave any caller, with no key at all,
--        every run-scoped table of any run, the depot's vehicles, stalls and charge sessions, and the source of 49
--        engine functions. Fixed in the repo by edge-functions/_shared/blackbox_auth.ts and run_blackbox.ts
--        (branch build/edge-run-blackbox-auth); NOT DEPLOYED by the session that wrote this file.
--        Measured 2026-10-13, read-only, in two windows: 18:04:23-18:32:12 UTC (1:04-1:32 PM CT) for the first draft,
--        and 19:11:13-19:26:52 UTC (2:11-2:26 PM CT) for this revision, after a review measured that the first draft's
--        cap did not bound a response. Each window runs from its first query's now() to its last query's now().
--        The twin depot 11111111-... is the only site in it (CLAUDE.md rule 8): every run named below ran there.
--
-- ══ §1 WHAT WAS OPEN (reproduce (1)-(3)) ═════════════════════════════════════════════════════════════════════════
--
--   (a) Deployed: ottoq-run-blackbox version 7, ACTIVE, verify_jwt false (Supabase get_edge_function; re-read beside
--       the 19:11:13 UTC catalog read: still version 7, updated_at 2026-07-18 00:23:16 UTC, ezbr_sha256 dfc5e156...).
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
--       sim_run_id column, sorted by name), each paged to 500,000+ rows; vehicles, stalls and ocpp_sessions at the
--       run's depot; and executed_code, the full source of the 49 public functions its pattern matches (315,910
--       characters: the decide tick, the shield, the policy reads and writes, the sim, the cuOpt bridge). With no
--       ?run it defaults to the latest operator_demo run, whichever that is at the moment of the request.
--   (e) Of the 74 tables it reads (71 + vehicles, stalls, ocpp_sessions), the public key may SELECT 4 directly:
--       ottoq_comms_messages, ottoq_decisions, ottoq_external_proposals, ottoq_proposal_disposition_ledger, the
--       ones 0658 left on its allowlist. The other 70 0658 closed to the public key on 2026-10-10; this function
--       served all 74 to a caller holding nothing, the public key included. Reproduce (2).
--   (f) SIZE, AND WHY A PER-TABLE CAP WAS NOT A LIMIT. Estimated as rows times the mean row_to_json length of a
--       sample (reproduce (4b); Postgres prints jsonb with spaces that JSON.stringify drops, so these run a little
--       high), the stopped twin-depot runs hold:
--         816bd28c-...  (operator_demo, ended 2026-10-01 19:06 UTC)  about 1,295 MB in 1,020,692 rows: shield
--                       evaluations 327,222 rows at 1,132 bytes (370 MB), DECISION SNAPSHOTS 1,282 rows at
--                       178,627 bytes (229 MB), decisions 71,429 at 2,903 (207 MB), the shield-effect view 327,222
--                       at 544 (178 MB), ocpp messages 91,314 at 1,034 (94 MB), then comms, telemetry, recall.
--         176b2912-...  (operator_demo, ended 2026-10-13 16:22 UTC)  about 448 MB.
--         d3938f36-...  (operator_demo, ended 2026-10-13 02:11 UTC)  about 95 MB.
--         a626c6e8-...  (operator_demo, ended 2026-10-11 22:00 UTC)  about 15 MB, the smallest of the last six days.
--       In every one of the three the widest relation is ottoq_decision_snapshots, at 176,024-178,627 bytes a row.
--       v7 put a whole run in one response. The platform allows a request 256 MB of memory and 2 s of CPU
--       (https://supabase.com/docs/guides/functions/limits, read 2026-10-13; the page states no response-size limit),
--       so v7 could not have served any of the first three: worse, one of v7's 1,000-row reads of the decision
--       snapshots is about 178 MB of JSON on its own. The first draft of this change capped each table at 50,000 rows
--       a request, which still put about 448 MB in 816bd28c's first response (a review measured it); this revision
--       limits the response and the read (§3 b).
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
--   (b) ONE RESPONSE CARRIES AT MOST 20,000,000 BYTES OF JSON, header included, counted in the UTF-8 bytes actually
--       sent: each row is serialised once as it is read, and the body is those bytes joined. When the next row would
--       pass the budget (less 64,000 bytes kept for export_paging), the response ends and its cursor names that row.
--       Every response carries at least one row, so a walk ends. READS ARE SIZED TOO: a relation's first read in a
--       request asks for 25 rows, and each later one for as many as fit 4,000,000 bytes at the widest row seen so far
--       (and no more than the budget has room for), never more than 1,000, so the decision snapshots come about 22 at
--       a time, not 1,000. Over a fixture with the live row widths (tests/run_blackbox_auth.test.mjs, 117 MB) the
--       walk took 7 responses of at most 19,936,587 bytes, every row once and in order; the only read over 4 MB was
--       the snapshots' first, 25 rows at 4,465,675 bytes. Node 22 on the build runner took 187-469 ms a 20 MB response
--       with a fake client that does not parse JSON; that is a local reading, not the platform's CPU meter.
--   (c) THE CURSOR. `v1.<page>.<offset>.<relation>.<run>`, in export_paging.next_cursor and the X-OTTOQ-Next-Cursor
--       header ("none" on the last), and export_paging.next is the query string to send (?run=...&cursor=...). A
--       cursor carries its run: a later request with a cursor and no run reads the cursor's run, never "the latest",
--       which can change between pages. A cursor with a different run is a 400 and a malformed one a 400, both before
--       a database client is made; one naming a relation the export no longer lists is a 409, after the meta read
--       and before any relation is read.
--   (d) A RUN UNDER THE BUDGET IS v7's BUNDLE EXACTLY, in one response, plus one key, export_paging {response_byte_budget,
--       page, cursor, next_cursor, next, complete, relations [{name, first_row, rows, complete, error?}], run_status,
--       run_ended_at, warning, order, merge}. A larger run comes as several responses; every one repeats the header
--       (run row, executed_code, data_tables) so each file stands alone, and `data` holds only the relations, or the
--       part of one, that it carries. Concatenating data[<relation>] across pages in page order gives the whole run.
--       A later page's file name ends "-p<n>.json".
--   (e) The cursor is an OFFSET, read with no ORDER BY, in the order v7 already relied on between its own 1,000-row
--       pages: the 90 relations share no key to order by (70 tables carry 53 different primary-key column lists, one
--       table has none, 19 are views). On a run that has ended the order is usually stable between requests, but
--       Postgres does not promise it (a plan can change as the offset grows; a synchronized sequential scan can start
--       mid-table). On a run still writing, a later page can repeat or miss rows: export_paging.warning says so, on
--       every page, whenever the run's ended_at is null.
--   (f) Everything else as v7: the default run, the meta RPC, the relation list and its order, the depot tables,
--       _export_error rows, the 404 and 500 answers, the first response's file name. CORS allows x-ottoq-export-token
--       and exposes Content-Disposition and X-OTTOQ-Next-Cursor, so a browser can send the one and read the others.
--   tests/run_blackbox_auth.test.mjs: 31 tests, 31 pass (node 22.22). Mutation-checked, each on a scratch copy:
--   removing the budget check fails 2; 1,000-row first reads fail 1; unsized later reads fail 1; a cursor not bound
--   to its run fails 1; a cursor one row late fails 3; no one-row progress guarantee fails 1; removing the 401 gate
--   fails 5; the review's localeCompare bypass in the comparator fails 1; dropping the expose header fails 1;
--   dropping $ from the cursor's relation grammar fails 1.
--   tsc 6.0.2 --strict --noUnusedLocals --noUnusedParameters over the two shared modules and the shell (with a Deno
--   shim): clean.
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
--   Chase), in src/lib/blackbox.ts downloadBlackbox:
--     1. Read an export token the operator pasted once (localStorage 'otto_blackbox_token', set beside the existing
--        operator key) and send it as "x-ottoq-export-token" instead of the public key. If none is set, show "Paste
--        the Black Box export token to download" instead of calling.
--     2. FOLLOW THE CURSOR. Save each response as its own file (the function names them -p1, -p2, ...) and request
--        export_paging.next until next_cursor is null, showing "page n" as it goes. A button that saves only the first
--        response hands the operator a truncated bundle that reads as whole: every twin-depot run measured in §1 (f)
--        but the smallest is more than one response. If the loop is stopped early, the toast says the bundle is
--        incomplete and names the last page saved.
--   About twenty lines; the token lives in that operator's browser only, never in the bundle. Until then the lead (or
--   Chase) downloads with curl and the token, §6 (h).
--   OPEN-ITEM: the twin app's Black Box button sends the public key and answers 401 once this deploys; it needs the export-token header and a loop over export_paging.next (§4)
--
-- ══ §5 NOT CHANGED HERE, AND STILL OPEN ══════════════════════════════════════════════════════════════════════════
--
--   (a) THE SAME EXPORT HAS A SECOND DOOR IN THE DATABASE, and this change does not close it. Two SECURITY DEFINER
--       functions carry ACL {postgres, authenticated, service_role} (anon: no), re-read 19:11 UTC:
--         public.ottoq_run_blackbox(uuid)       md5 4f96d37ef15bcf3fac9a79023f99c729: the monolithic v1. It returns
--                                               the WHOLE bundle: every listed relation to 200,000 rows each, the
--                                               depot tables and the 49 function sources, under a 150 s local
--                                               statement_timeout, so it is a load lever as well as a read.
--         public.ottoq_run_blackbox_meta(uuid)  md5 06ec6069b1f08a5ce51a18e2e2764123: the run row and the sources.
--       Any signed-in user reaches both through PostgREST (/rest/v1/rpc/...), without the edge function; the
--       field-ops demo logins share one password in a public repo (G393/G394). No caller of the first exists in any
--       repo here (the edge function calls only the second, with the service role), so revoking EXECUTE on both from
--       authenticated should break nothing; it is a migration, one concern, and not this item. Reproduce (1).
--   OPEN-ITEM: ottoq_run_blackbox(uuid) and ottoq_run_blackbox_meta(uuid) are EXECUTE-able by authenticated, a second door to the whole export (§5 a)
--   (a') ADDED 2026-10-14 (db/migrations/0720 §2; FINDINGS G438): the two functions are not the only door. 0720
--       (pending) revokes EXECUTE on both, and that closes the RPC door only: measured read-only 16:34:47-16:37:57 UTC
--       (11:34-11:37 AM CT), authenticated holds SELECT on 78 of the 93 run-scoped relations the export reads, 76 of
--       them open to a signed-in caller under their row security (67 every row, ottoq_sim_runs and
--       ottoq_telemetry_packets among them), and ottoq_schema_snapshots (row security off) holds earlier versions of
--       45 of the 49 function sources. What 0720 takes is the one-call export, the current sources, and what row
--       security or a missing grant withholds as tables (17 run-scoped relations, vehicles, ocpp_sessions).
--   OPEN-ITEM: G438 - after 0720 a signed-in user (sign-up is open) still reads 76 of the 93 run-scoped relations through /rest/v1/<relation>; the remedy is the authenticated-role census 0701 §2 defers (§5 a')
--   (b) The four tables 0658 left readable by the public key stay readable (its own §3 names them as next).
--   (c) A keyset cursor needs each relation's key from ottoq_run_blackbox_meta: a migration, if offset paging bites.
--       Deep offsets cost little today: the heaviest view, ottoq_rule_evaluation_effect, read 1,000 rows at offset
--       326,000 of 816bd28c in 1.06 s (EXPLAIN ANALYZE, between 19:15:45 and 19:21:20 UTC), against the service role's 20 s statement_timeout.
--   (d) Only the legacy service-role JWT in SUPABASE_SERVICE_ROLE_KEY is accepted as the service key. A caller
--       holding only an sb_secret_ key uses the export token.
--   (e) The export token is ONE long-lived shared secret: no expiry, no per-person identity, no ledger beyond the
--       function logs, and the §4 design keeps it in a browser's localStorage, where any script injected into the twin
--       app can read it. A stopgap that closes the anonymous door, not an access model. Rotate it by setting a new
--       secret; the old one stops working at once.
--   (f) Downloading a large run is slow: 816bd28c is about 66 responses. That is the size of the run, not the cap.
--   (g) No migration, no forces_recert, no tick path: the change is an edge function no engine path reads.
--
-- ══ §6 AFTER DEPLOY: THE PROBES, AND WHAT EACH MUST RETURN ═══════════════════════════════════════════════════════
--
--   Deploy (a person; this session deployed nothing):
--     1. Set the token: supabase secrets set OTTOQ_BLACKBOX_TOKEN=$(openssl rand -hex 32) --project-ref gxdrcyphqjzjsuhxuqtg
--        (or the dashboard's Edge Function Secrets page).
--     2. Deploy through the Supabase MCP deploy_edge_function with THREE files, as _MANIFEST.md footnote 11 did for
--        ottoq-depot-v2: entrypoint ottoq-run-blackbox/index.ts, plus _shared/blackbox_auth.ts and
--        _shared/run_blackbox.ts, verify_jwt FALSE. `supabase functions deploy` does not work from this repo as it
--        stands: there is no supabase/ directory or config.toml (the functions live under edge-functions/).
--     3. Read it back with get_edge_function, save the response to a file, and hash all three files against the
--        repo. On branch build/edge-run-blackbox-auth as written: index.ts sha256 63656ff3..., _shared/blackbox_auth.ts
--        3b71f124... (unchanged since the first draft), _shared/run_blackbox.ts ec51556c.... Before deploying, re-read
--        the live v7 and confirm it still hashes to 0f63f9cf...; if not, it changed since and needs a merge. Do not lean on scripts/check-edge-drift.sh for the _shared files: whether it compares them depends on
--        where `supabase functions download --use-api` writes them, and that was not checked here.
--   verify_jwt must stay FALSE: the gateway refuses legacy JWT keys and the export token is not a JWT.
--   Run (6) first. If a run is live at the twin depot, wait: the probes below read only stopped runs, but they read
--   the engine's tables during its ticks.
--
--   In a private scratch directory, with the keys out of history and out of every process's argv (printf is a shell
--   builtin, and curl reads -H @file itself):
--     umask 077; D=$(mktemp -d); cd "$D"
--     B=https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-run-blackbox
--     read -rs SVC; read -rs TOK            # paste the service-role key, then OTTOQ_BLACKBOX_TOKEN; nothing echoes
--     printf 'Authorization: Bearer %s\n' "$SVC" > svc.h;  printf 'apikey: %s\n' "$SVC" > svc_apikey.h
--     printf 'x-ottoq-export-token: %s\n' "$TOK" > tok.h
--     ANON=<OTTOQ_ANON_KEY from ottoyarddepot-sim src/lib/ottoTwin.ts>   PUB=<the project's sb_publishable_ key>
--     printf 'apikey: %s\nAuthorization: Bearer %s\n' "$ANON" "$ANON" > anon.h
--
--   (a) curl -sS -w '\n%{http_code}\n' "$B?run=not-a-uuid"
--         401 {"error":"unauthorized",...}. THE DISCRIMINATING PROBE: v7 answered this exact URL with 500 and
--         Postgres's uuid error (§1 c). A 401 here proves the credential is checked before the database.
--   (b) curl -sS -o /dev/null -w '%{http_code}\n' "$B"                                                        401
--   (c) curl -sS -o /dev/null -w '%{http_code}\n' -H @anon.h "$B?run=not-a-uuid"             401: the twin app's own call
--   (d) curl -sS -o /dev/null -w '%{http_code}\n' -H "apikey: $PUB" "$B?run=not-a-uuid"                      401
--   (e) curl -sS -o /dev/null -w '%{http_code}\n' -H "x-ottoq-export-token: $(printf '0%.0s' {1..64})" "$B?run=not-a-uuid"
--         401
--   (f) curl -sS -w '\n%{http_code}\n' -H @svc.h "$B?run=not-a-uuid"
--         500 and the uuid error: the service key passes and reaches Postgres.
--   (g) THE BUDGET ON THE LARGEST RUN (one response; do not walk it, it is about 66):
--         curl -sS -H @svc.h -D g.h -o g.json -w '%{http_code} %{size_download}\n' "$B?run=816bd28c-e103-40ce-8839-f473af1d6416"
--         200 and a size of at most 20000000. NOT 546 (WORKER_LIMIT): the first draft of this change would have
--         answered 546 here. grep -i x-ottoq-next-cursor g.h names v1.1.<n>.ottoq_comms_messages.816bd28c-...;
--         jq -c '.export_paging | {page, complete, response_byte_budget, last: .relations[-1]}' g.json
--           page 0, complete false, response_byte_budget 20000000, and the last relation ottoq_comms_messages,
--           complete false, first_row 0, rows <n> (about 14,000 by the size estimate: the relations before it in name
--           order hold about 2.96 MB, reproduce (4c)).
--   (g2) THE WIDE ROWS, by a cursor made by hand at the decision snapshots (a cursor is plain text, so this is legal):
--         curl -sS -H @svc.h -o g2.json -w '%{http_code} %{size_download}\n' "$B?cursor=v1.1.0.ottoq_decision_snapshots.816bd28c-e103-40ce-8839-f473af1d6416"
--         200, at most 20000000 bytes, and
--         jq -c '.export_paging | {page, next_cursor, r: .relations[0]}' g2.json
--           page 1; r.name ottoq_decision_snapshots, first_row 0, complete false, rows <m> > 0 (about 110 by the
--           estimate); next_cursor exactly v1.2.<m>.ottoq_decision_snapshots.816bd28c-... (the offset is the row
--           count). This is the table one of v7's reads would have put 178 MB into.
--   (h) A WHOLE RUN WALKED, WITH THE EXPORT TOKEN: d3938f36 (about 95 MB, so about 5 responses):
--         q="?run=d3938f36-6f60-4c70-8ab3-7d503185f8d0"; k=0
--         while :; do
--           curl -sS -H @tok.h -D "h$k.txt" -o "p$k.json" -w '%{http_code} %{size_download}\n' "$B$q" | tee -a walk.log
--           n=$(jq -r '.export_paging.next // empty' "p$k.json"); [ -z "$n" ] && break
--           q="$n"; k=$((k+1)); [ "$k" -gt 30 ] && { echo STOPPED; break; }
--         done
--         Every walk.log line 200 with a size of at most 20000000; the last h<k>.txt carries X-OTTOQ-Next-Cursor:
--         none; pages are numbered 0..k and their files end -p1 .. -p<k>. Then the merged counts:
--         jq -s 'map(.data | to_entries[] | {k: .key, n: (.value | length)}) | group_by(.k) | map({(.[0].k): (map(.n) | add)}) | add' p*.json
--           equal, relation by relation, to (4d) read in the same minute (rule_evaluations 16034, decisions 2416,
--           decision_snapshots 69, vehicles 116, stalls 158; ocpp_sessions grows if any later run charges, so compare
--           it to (4d)'s reading, not to this file).
--         jq -s '[.[].data.ottoq_rule_evaluations[]?.evaluation_id] | [length, (unique | length)]' p*.json   [16034,16034]
--         jq -s '[.[].data.ottoq_decision_snapshots[]?.snapshot_id] | [length, (unique | length)]' p*.json   [69,69]
--         No repeat and no gap on a stopped run; if either pair differs, the offset order moved between requests
--         (§3 e) and that is the finding.
--   (i) THE APIKEY CHANNEL: curl -sS -H @svc_apikey.h -o i.json -w '%{http_code} %{size_download}\n' "$B?run=a626c6e8-f9d5-4dc1-ae03-0095df91f819"
--         200, at most 20000000 bytes; a626c6e8 is the smallest recent run (about 15 MB, plus the header and the depot tables), so one response or two.
--   (i2) THE DEFAULT RUN, ONLY IF (6) READS running_now = 0: curl -sS -H @svc.h -o i2.json -w '%{http_code}\n' "$B"
--         200, and jq -r .sim_run_id i2.json equals (6)'s latest_operator_demo_run. If a run is live, skip it: the
--         default is that run, and it is still being written.
--   (j) curl -sS -i -X OPTIONS "$B" | grep -i '^access-control'
--         allow-headers ... apikey, content-type, x-ottoq-export-token; expose-headers Content-Disposition,
--         X-OTTOQ-Next-Cursor.
--   (k) The logs: reproduce (5) over the probe window. Every probe above appears with the status listed and none with
--       546 or 504. The function's own lines read {"auth":"refused","reason":...} for (a)-(e), and
--       {"auth":"accepted","via":"service_role"|"export_token",...} then {"page":...,"bytes":...} for (f)-(i2), with
--       bytes at most 20000000 and no key in any line.
--   (l) cd / && rm -rf "$D" && unset SVC TOK. The files hold run data and function source; nothing of them goes into
--       a repository.
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

-- (3) what the export lists and ships besides the tables, and that every relation name fits the cursor's grammar
--     ([A-Za-z_][A-Za-z0-9_$]{0,62}, a Postgres identifier's alphabet). Expect: 90 relations (19 views); 0 names outside the grammar; 49 functions, 315,910
--     characters of source (both move as functions and tables are added).
SELECT (SELECT count(*) FROM information_schema.columns c JOIN information_schema.tables tb USING (table_schema, table_name)
         WHERE c.table_schema = 'public' AND c.column_name = 'sim_run_id' AND c.table_name LIKE 'ottoq%') AS relations,
       (SELECT count(*) FROM information_schema.columns c JOIN information_schema.tables tb USING (table_schema, table_name)
         WHERE c.table_schema = 'public' AND c.column_name = 'sim_run_id' AND c.table_name LIKE 'ottoq%'
           AND tb.table_type = 'VIEW') AS views,
       (SELECT count(*) FROM information_schema.columns c
         WHERE c.table_schema = 'public' AND c.column_name = 'sim_run_id' AND c.table_name LIKE 'ottoq%'
           AND c.table_name !~ '^[A-Za-z_][A-Za-z0-9_$]{0,62}$') AS names_outside_cursor_grammar,
       (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
         AND proname ~ '^ottoq_(sim_|decide_tick|greedy_tick|fifo_tick|manual_tick|l2_|cuopt_|energy_orchestrate|orchestrator_trigger|apply_ops_action|demo_metronome|deploy_target|policy_get|policy_set|shield|plan_visit|itin_leg|mark_visit|record_event|active_charge_cap|deploy_target_fraction|run_blackbox|sim_stop_and_reset)') AS functions_in_executed_code,
       (SELECT sum(length(pg_get_functiondef(oid))) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
         AND proname ~ '^ottoq_(sim_|decide_tick|greedy_tick|fifo_tick|manual_tick|l2_|cuopt_|energy_orchestrate|orchestrator_trigger|apply_ops_action|demo_metronome|deploy_target|policy_get|policy_set|shield|plan_visit|itin_leg|mark_visit|record_event|active_charge_cap|deploy_target_fraction|run_blackbox|sim_stop_and_reset)') AS source_chars;

-- (4) the probe runs for §6 (g)-(i): still there, the twin depot, ended. Expect three rows, each depot
--     11111111-1111-1111-1111-111111111111, operator_demo, completed, ended_at set; rule_evaluations
--     816bd28c 327222, a626c6e8 2575, d3938f36 16034. If one is gone (the run purge, 0645/0646), pick another
--     stopped twin-depot run of a similar size with (4b) and use it in its probe.
SELECT r.sim_run_id, r.depot_id, r.run_by, r.status, r.ended_at,
       (SELECT count(*) FROM public.ottoq_rule_evaluations e WHERE e.sim_run_id = r.sim_run_id) AS rule_evaluations
  FROM public.ottoq_sim_runs r
 WHERE r.sim_run_id IN ('816bd28c-e103-40ce-8839-f473af1d6416', 'd3938f36-6f60-4c70-8ab3-7d503185f8d0',
                        'a626c6e8-f9d5-4dc1-ae03-0095df91f819')
 ORDER BY r.sim_run_id;

-- (4b) each probe run's size as JSON, estimated: rows times the mean row_to_json length of up to 2,000 rows, per
--      relation (one count and one sample per relation; about a minute on the largest). Expect, 2026-10-13:
--      816bd28c about 1,295 MB in 1,020,692 rows, ottoq_decision_snapshots the widest at 178,627 bytes a row;
--      d3938f36 about 95 MB; a626c6e8 about 15 MB; ottoq_decision_snapshots the widest relation in all three. Postgres prints jsonb with spaces JSON.stringify drops, so the
--      bytes sent run a little lower.
WITH runs(run) AS (VALUES ('816bd28c-e103-40ce-8839-f473af1d6416'::text), ('d3938f36-6f60-4c70-8ab3-7d503185f8d0'),
                          ('a626c6e8-f9d5-4dc1-ae03-0095df91f819')),
t AS (SELECT DISTINCT table_name::text AS table_name FROM information_schema.columns
       WHERE table_schema = 'public' AND column_name = 'sim_run_id' AND table_name LIKE 'ottoq%'),
c AS (SELECT run, table_name,
        (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM public.%I WHERE sim_run_id = %L', table_name, run), false, true, '')))[1]::text::bigint AS n
        FROM runs, t),
s AS (SELECT run, table_name, n,
        CASE WHEN n > 0 THEN (xpath('/row/b/text()', query_to_xml(format('SELECT avg(octet_length(row_to_json(x)::text))::bigint AS b FROM (SELECT * FROM public.%I WHERE sim_run_id = %L LIMIT 2000) x', table_name, run), false, true, '')))[1]::text::bigint ELSE 0 END AS avg_b
        FROM c)
SELECT run, sum(n) AS rows_total, round(sum(n * avg_b) / 1e6, 1) AS est_mb,
       (array_agg(table_name ORDER BY avg_b DESC))[1] AS widest_relation, max(avg_b) AS widest_avg_bytes
  FROM s GROUP BY run ORDER BY run;

-- (4c) where §6 (g)'s first response of 816bd28c should end: the non-empty relations in the export's own order, with
--      the running size estimate. Expect the running total to stay under 20 MB up to ottoq_charge_duration_ledger
--      (about 2.96 MB) and the next non-empty relation to be ottoq_comms_messages (53,352 rows, about 64 MB), so
--      the response ends inside it.
WITH t AS (SELECT DISTINCT table_name::text AS table_name FROM information_schema.columns
            WHERE table_schema = 'public' AND column_name = 'sim_run_id' AND table_name LIKE 'ottoq%'),
c AS (SELECT table_name,
        (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM public.%I WHERE sim_run_id = %L', table_name, '816bd28c-e103-40ce-8839-f473af1d6416'), false, true, '')))[1]::text::bigint AS n
        FROM t),
s AS (SELECT table_name, n,
        CASE WHEN n > 0 THEN (xpath('/row/b/text()', query_to_xml(format('SELECT avg(octet_length(row_to_json(x)::text))::bigint AS b FROM (SELECT * FROM public.%I WHERE sim_run_id = %L LIMIT 2000) x', table_name, '816bd28c-e103-40ce-8839-f473af1d6416'), false, true, '')))[1]::text::bigint ELSE 0 END AS avg_b
        FROM c)
SELECT table_name, n, avg_b, round(sum(n * avg_b) OVER (ORDER BY table_name COLLATE "C") / 1e6, 2) AS running_mb
  FROM s WHERE n > 0 ORDER BY table_name COLLATE "C" LIMIT 8;

-- (4d) what §6 (h)'s merged walk of d3938f36 must count, relation by relation, with the handler's own filters. Read it
--      in the same minute as the walk. Expect (2026-10-13 19:15 UTC) among others ottoq_rule_evaluations 16034,
--      ottoq_decisions 2416, ottoq_decision_snapshots 69, vehicles 116, stalls 158, ocpp_sessions 430 (the last grows
--      with any later run at the depot: it read 493 at the dry run of this query, between 19:21:50 and 19:25:10 UTC, while run
--      02ac27b3 was charging).
WITH t AS (SELECT DISTINCT table_name::text AS table_name FROM information_schema.columns
            WHERE table_schema = 'public' AND column_name = 'sim_run_id' AND table_name LIKE 'ottoq%')
SELECT table_name AS relation,
       (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM public.%I WHERE sim_run_id = %L', table_name, 'd3938f36-6f60-4c70-8ab3-7d503185f8d0'), false, true, '')))[1]::text::bigint AS n
  FROM t
UNION ALL SELECT 'vehicles', count(*) FROM public.vehicles
           WHERE owning_sim_run_id = 'd3938f36-6f60-4c70-8ab3-7d503185f8d0' OR current_depot_id = '11111111-1111-1111-1111-111111111111'
UNION ALL SELECT 'stalls', count(*) FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111'
UNION ALL SELECT 'ocpp_sessions', count(*) FROM public.ocpp_sessions
           WHERE depot_id = '11111111-1111-1111-1111-111111111111'
             AND started_at >= (SELECT started_at FROM public.ottoq_sim_runs WHERE sim_run_id = 'd3938f36-6f60-4c70-8ab3-7d503185f8d0')
ORDER BY 1;

-- (5) the probes in the logs (Supabase logs query, ClickHouse; set the window to the probe minutes):
--   SELECT timestamp, log_attributes['request.method'] AS method, log_attributes['response.status_code'] AS status,
--          log_attributes['request.search'] AS search, log_attributes['request.sb.apikey.authorization.prefix'] AS key_prefix
--     FROM logs
--    WHERE source = 'function_edge_logs' AND log_attributes['request.pathname'] LIKE '%ottoq-run-blackbox%'
--    ORDER BY timestamp;
--   and the function's own lines:
--   SELECT timestamp, event_message FROM logs
--    WHERE source = 'function_logs' AND event_message LIKE '%ottoq-run-blackbox%' ORDER BY timestamp;

-- (6) before the probes: is a run live at the twin depot, and which run would a request with no ?run read? Expect
--     running_now 0 before probing at all (§6); latest_operator_demo_run is what (i2) must return. At 19:15 UTC it
--     was 57188f55-4503-4c5c-82c8-b42000f73ba2 (ended 19:12:00 UTC); at the dry run of this query, between 19:21:50 and
--     19:25:10 UTC, it was 02ac27b3-fe50-42b1-bf1b-82ac2a50445f and RUNNING (running_now 1). It changes with every demo run.
SELECT (SELECT count(*) FROM public.ottoq_sim_runs
         WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running') AS running_now,
       (SELECT sim_run_id FROM public.ottoq_sim_runs WHERE run_by = 'operator_demo'
         ORDER BY started_at DESC LIMIT 1) AS latest_operator_demo_run,
       (SELECT status FROM public.ottoq_sim_runs WHERE run_by = 'operator_demo'
         ORDER BY started_at DESC LIMIT 1) AS its_status;
