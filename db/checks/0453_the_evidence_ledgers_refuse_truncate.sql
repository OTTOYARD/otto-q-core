-- 0453  **The evidence ledgers, TRUNCATE and DROP: what the grants allowed, what nothing does, and the guards 0748 and
--        0749 build.**
--        G456 named the gap when 0742's grants check refused its first apply; this file measures it and records the dry
--        run of its fix; §4 measures the dropped evidence tables and the guard 0749 builds. -> G456, G462, G463.
--        Read-only, against gxdrcyphqjzjsuhxuqtg, 2026-10-17 between 7:54 and 8:07 PM CT (00:54 and 01:07 UTC Oct 18,
--        bounded by clock reads). Every number below names the query that reproduces it.
--
-- ══ §1 THE EVIDENCE CLASS AND ITS GRANTS (reproduce: (1), (2), (3)) ═══════════════════════════════════════════════════
--
--   The run-scope registry classes 202 tables as evidence; 100 exist and 102 do not (all in public, all named for the
--   August proof and scratch work). Of the 100:
--     service_role holds TRUNCATE (and DELETE and UPDATE)       93   the default privileges postgres holds in public
--                                                                     give service_role every right on a new table
--     anon or authenticated holds TRUNCATE                       0
--     a BEFORE TRUNCATE trigger refuses                           3   ottoq_agent_requests, ottoq_owner_commands
--                                                                     (ottoq_agent_no_truncate), ottoq_feed_plan_promotions
--     a trigger on UPDATE or DELETE                              23
--     no trigger on UPDATE or DELETE                             77   70 frozen snapshots by name; 7 live ledgers whose
--                                                                     rows are rewritten (ottoq_ab_runs 97 updates and
--                                                                     262 deletes, ottoq_challenger_findings 7,501
--                                                                     updates, ottoq_dial_pair_ledger 10 and 54,
--                                                                     ottoq_run_dial_ledger 13 and 3,
--                                                                     ottoq_dial_promotion_ledger 1, ottoq_proposer_fire_log
--                                                                     2 deletes, ottoq_model_artifacts none yet)
--   The counters are pg_stat_user_tables' since its last reset. md5 of the 100 tables' sorted names (C collation):
--   5819248fb39a693829e5835fcd8c5fd3, the set 0748's P1 pins.
--
-- ══ §2 NOTHING TRUNCATES THEM, AND ONLY MIGRATIONS WRITE THE REGISTRY (reproduce: (4), (5)) ════════════════════════════
--
--   No function body names TRUNCATE (comments stripped) but public.ottoq_agent_no_truncate, the guard, and
--   public.ottoq_assert_anon_rpc_surface, an assertion. No cron command names it; every cron job runs as postgres. No
--   edge function or app in the twelve repositories issues one (the tests do, on scratch databases). No function writes
--   ottoq_run_scope_registry, and service_role may INSERT, UPDATE and DELETE it (no row security): an UPDATE of a
--   ledger's class to 'engine' would have let the next demo run's ottoq_purge_prior_runs delete from it, since the purge
--   finds its tables by registry lookup (G462). ottoq_cert_lineage is also writable by service_role, and two engine
--   functions write it (public.ottoq_promote_dial_experiment, public.ottoq_recert_promotion_guard), so it is left alone.
--   The database keeps no record of DDL (its six event triggers are Supabase's own), so when the 102 missing evidence
--   tables were dropped, and by what, is not established (G463).
--
-- ══ §3 THE DRY RUN OF 0748 (rolled back by its own final RAISE; reproduce: the file) ════════════════════════════════════
--
--   2026-10-17 between 8:07 and 8:15 PM CT: every premise and check passed; the executable part (the text between
--   "BEGIN;\n" and the newline before "COMMIT;") read back by md5(current_query()) equal to the file's, 9e00d2d3, 15,821
--   characters; 98 tables carried the new trigger (97 evidence tables and the registry); the assert returned no rows;
--   service_role held TRUNCATE on 0 of the 100 evidence tables and read but did not write the registry; a TRUNCATE of
--   public.ottoq_model_call_ledger as postgres was refused with this file's message. Read at 8:15 PM CT after the
--   rollback: no trigger, function, pre-image or lineage row of 0748 remains, and the grants and rows are as before
--   (public.ottoq_model_call_ledger 37,179 rows).
--
-- ══ §4 THE DROPPED EVIDENCE TABLES, AND 0749 (reproduce: (6), (7), (8)) ════════════════════════════════════════════════
--
--   Read 2026-10-17 between 8:24 and 8:47 PM CT. The 102 missing evidence tables were all registered at 2026-08-08
--   18:22:26 UTC with the note "certification / scratch evidence: deliberately outlives its run" (8); 59 of them are in
--   the 2026-08-04 baseline (db/baseline/tables.sql), and no file in this repo drops one. No function body drops a table
--   but two PostGIS helpers and public.ottoq_baseline_fifo, which drops its own temporary tables, and no cron command
--   drops anything (6). The database's six event triggers are Supabase's own (7); nothing records DDL.
--   postgres may create an event trigger here (a probe at 8:35 PM CT, rolled back, read back after it: none left).
--   0749's guard was then tried on live, in pieces, each rolled back by its own RAISE:
--     - the function and the event trigger as written, created: returned at once (8:43 PM CT);
--     - with them, a probe table registered as evidence refused its DROP in 5 ms with 0749's refusal (8:43 PM CT);
--     - the whole dry run (twice), a DROP the trigger lets through, and the same with a do-nothing trigger function:
--       no answer within the connector's 60 seconds, and none of the four is in the database's own log, so none of them
--       ran. The Supabase connector holds a statement with a DROP for a person's approval (MIGRATION_LOG, 0647); which
--       statements it holds is its rule, not measured here. Each time: no session left running, nothing left behind,
--       and the checkpointer and the cron launcher up since 2026-08-09, so no backend crashed.
--   Testing the guard on the scratch database found one defect before it shipped: an event trigger runs with the
--   privileges of the role that issued the statement (Supabase, "PostgreSQL Event Triggers without superuser access",
--   2025-05-08, https://supabase.com/blog/event-triggers-wo-superuser), so as an ordinary function it refused the DROP
--   of a role that cannot read the registry, its own tables included. 0749's function is SECURITY DEFINER.

-- (1) The evidence class: registered tables, those that exist, those that do not.
WITH ev AS (SELECT DISTINCT table_schema, table_name,
                   to_regclass(quote_ident(table_schema) || '.' || quote_ident(table_name)) AS rel
              FROM public.ottoq_run_scope_registry WHERE class = 'evidence')
SELECT table_schema, count(*) AS registered, count(rel) AS existing, count(*) - count(rel) AS missing
  FROM ev GROUP BY 1 ORDER BY 1;

-- (2) Each existing evidence table: who may truncate, which triggers guard it, how its rows have moved.
WITH ev AS (SELECT DISTINCT table_schema, table_name,
                   to_regclass(quote_ident(table_schema) || '.' || quote_ident(table_name)) AS rel
              FROM public.ottoq_run_scope_registry WHERE class = 'evidence'),
x AS (SELECT ev.*,
             has_table_privilege('service_role', rel, 'TRUNCATE') AS sr_truncate,
             has_table_privilege('anon', rel, 'TRUNCATE') OR has_table_privilege('authenticated', rel, 'TRUNCATE') AS browser_truncate,
             EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = rel AND NOT t.tgisinternal AND t.tgenabled IN ('O', 'A')
                        AND (t.tgtype & 32) <> 0 AND (t.tgtype & 2) <> 0) AS truncate_guard,
             EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = rel AND NOT t.tgisinternal AND t.tgenabled IN ('O', 'A')
                        AND (t.tgtype & (8 | 16)) <> 0) AS update_delete_trigger,
             s.n_tup_upd, s.n_tup_del,
             (table_name !~ '^ottoq_' OR table_name ~ '^ottoq_layout_backup' OR table_schema <> 'public') AS frozen_by_name
        FROM ev LEFT JOIN pg_stat_user_tables s ON s.relid = ev.rel
       WHERE rel IS NOT NULL)
SELECT count(*) AS tables,
       count(*) FILTER (WHERE sr_truncate) AS service_role_truncate,
       count(*) FILTER (WHERE browser_truncate) AS browser_truncate,
       count(*) FILTER (WHERE truncate_guard) AS truncate_guard,
       count(*) FILTER (WHERE update_delete_trigger) AS update_delete_trigger,
       count(*) FILTER (WHERE NOT update_delete_trigger AND frozen_by_name) AS unguarded_frozen,
       string_agg(table_name || ' ' || n_tup_upd || 'u/' || n_tup_del || 'd', ', ' ORDER BY table_name)
         FILTER (WHERE NOT update_delete_trigger AND NOT frozen_by_name) AS unguarded_live,
       md5(string_agg(table_schema || '.' || table_name, ',' ORDER BY table_schema || '.' || table_name COLLATE "C")) AS set_md5
  FROM x;

-- (3) The default privileges postgres holds in public.
SELECT pg_get_userbyid(d.defaclrole) AS for_role, n.nspname, d.defaclobjtype, d.defaclacl::text
  FROM pg_default_acl d JOIN pg_namespace n ON n.oid = d.defaclnamespace
 WHERE n.nspname = 'public' ORDER BY 1, 3;

-- (4) Nothing truncates: function bodies (comments stripped) and cron commands that name TRUNCATE, cron's users, and
--     the functions that write the registry or the lineage.
WITH f AS (SELECT n.nspname || '.' || p.proname AS fn,
                  regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g') AS src
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.prolang <> 13)
SELECT 'function bodies naming TRUNCATE' AS what, string_agg(fn, ', ' ORDER BY fn) AS which FROM f WHERE src ~* '\mtruncate\M'
UNION ALL
SELECT 'cron commands naming TRUNCATE', count(*)::text FROM cron.job WHERE command ~* '\mtruncate\M'
UNION ALL
SELECT 'cron users', string_agg(DISTINCT username, ', ') FROM cron.job
UNION ALL
SELECT 'writers of ' || t.tbl, string_agg(f.fn, ', ' ORDER BY f.fn)
  FROM (VALUES ('ottoq_run_scope_registry'), ('ottoq_cert_lineage')) t(tbl)
  LEFT JOIN f ON f.src ~* ('(insert[[:space:]]+into|update|delete[[:space:]]+from|truncate)[[:space:]]+(only[[:space:]]+)?(public\.)?'
                           || t.tbl || '\M')
 GROUP BY t.tbl;

-- (5) Who may write the registry, and whether row security stands in the way.
SELECT r.rolname,
       has_table_privilege(r.rolname, 'public.ottoq_run_scope_registry', 'SELECT') AS reads,
       has_table_privilege(r.rolname, 'public.ottoq_run_scope_registry', 'INSERT, UPDATE, DELETE') AS writes,
       has_table_privilege(r.rolname, 'public.ottoq_run_scope_registry', 'TRUNCATE') AS truncates,
       (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.ottoq_run_scope_registry'::regclass) AS row_security
  FROM (VALUES ('anon'), ('authenticated'), ('service_role')) r(rolname);

-- (6) What drops a table: function bodies (comments stripped) with DROP TABLE or DROP SCHEMA, and cron commands with
--     DROP.
WITH f AS (SELECT n.nspname || '.' || p.proname AS fn,
                  regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g') AS src
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'extensions', 'graphql', 'graphql_public',
                                    'pgbouncer', 'realtime', 'storage', 'vault', 'auth', 'supabase_functions', 'net',
                                    'cron', 'pgsodium', 'pgsodium_masks')
              AND p.prolang <> 13)
SELECT 'function bodies with DROP TABLE or SCHEMA' AS what, string_agg(fn, ', ' ORDER BY fn) AS which
  FROM f WHERE src ~* '\mdrop[[:space:]]+(table|schema)\M'
UNION ALL
SELECT 'cron commands with DROP', count(*)::text FROM cron.job WHERE command ~* '\mdrop\M';

-- (7) The event triggers on the database, and their owners.
SELECT evtname, evtevent, pg_get_userbyid(evtowner) AS owner, evtfoid::regproc::text AS fn, evtenabled::text
  FROM pg_event_trigger ORDER BY evtname;

-- (8) The registry rows whose evidence table no longer exists: when they were registered, and with what note.
SELECT min(registered_at), max(registered_at), count(*) AS rows, count(DISTINCT table_name) AS tables,
       count(DISTINCT note) AS notes, min(note) AS note
  FROM public.ottoq_run_scope_registry
 WHERE class = 'evidence' AND to_regclass(quote_ident(table_schema) || '.' || quote_ident(table_name)) IS NULL;
