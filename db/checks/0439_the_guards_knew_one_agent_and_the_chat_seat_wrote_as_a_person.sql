-- 0439  **The guards knew one agent, and the chat seat wrote as a person.** (G4xx; fixed by db/migrations/0702.)
--        public.ottoq_is_agent_actor, the one function every guard asks "is this writer an agent", knew only
--        'ottoq_prime'. The OttoCommand chat seat ('ottocommand', an LLM writing a depot dial), the self-tuner ('cil') and
--        the feed agents passed the rule-10 production guard, the agent_writable guard and the agent envelope as people.
--        Measured 2026-10-13, read-only, against otto-q-core (gxdrcyphqjzjsuhxuqtg): the first and last live reads
--        stamped by the database's own clock were 14:47:52 and 15:13:47 UTC (9:47 and 10:13 AM CT). Query (4) was run
--        before 0702 at 15:12:22 UTC and gave the "before" answers in its notes. Re-read after 0716 landed (applied
--        18:46:08 UTC, 1:46 PM CT, adding the predicate's sixth caller): the reads stamped 19:03:47 to 19:16:21 UTC
--        (2:03 to 2:16 PM CT) gave (1)'s six callers, (10)'s "before" answers and every premise of 0702's P0/P1.
--
-- ══ §1 WHAT WAS MEASURED BEFORE 0702 (reproduce (1)-(4), (10)) ═══════════════════════════════════════════════════════
--
--   (a) The predicate (definition md5 f349c63ad2c48b7756633024d6da263b, IMMUTABLE, SECURITY INVOKER): with no list the
--       actors are ARRAY['ottoq_prime']. Six callers, comment-stripped: ottoq_policy_set (0432 guard), ottoq_dial_clamp
--       (0414 envelope), ottoq_production_write_refusal (0629, rule 10), ottoq_production_start (inherited-settings
--       report), ottoq_rule_eval_agent_dial_envelope (AI.001, its own list from the rule's parameters, ["ottoq_prime"]),
--       and since 0716 ottoq_feed_plan_promote (only a person makes a twin feed plan active; SECURITY DEFINER). The
--       promote door also decides by literal patterns of its own: v_by ILIKE 'nemotron%', '%agent%' or 'ottocommand%'.
--       Those only add refusals, so it is at least as strict as the setter; before 0702 it let 'cil' and
--       'auto_learning_loop' promote. The only other literal agent list is ARRAY['ottoq_prime'], in the predicate and in
--       AI.001's fallback. No index, constraint, default or view depends on the predicate. (1), (10)
--   (b) ottoq_policy_set's p_by defaults to 'ottocommand'. Of its 11 call sites in the database, one names nobody:
--       ottoq_fr1_cert_arm, a retired benchmark procedure on the benchmark depot, called by nothing, whose PERFORMed
--       energy_mpc_follow write stands as 'ottocommand' (2026-07-15, on a run that no longer exists). 5 cron jobs call
--       the setter, all named. (2)
--   (c) Who wrote: 43 distinct updated_by names have a row standing from the last 30 days; 11 distinct names attempted
--       a write through the setter (AI.001's log, which survives from 2026-09-30 only, class 'engine'). Agents among
--       them: ottoq_prime (250 rows, 57 runs) and ottoq_prime:promoter (1 depot row). No 'ottocommand' or 'cil' write in
--       the window; ottoq_cil_adoptions holds 0 rows. In the API and Postgres logs for the 24 hours before a query run
--       between the reads stamped 14:51:35 and 15:12:22 UTC, no client called ottoq_policy_set over REST; crons 784 and
--       785 called it, named; ottoq-ottocommand took two POSTs at 13:34 UTC, answered 400 and 401. (3)
--   (d) The chat seat: edge function ottoq-ottocommand, verify_jwt true, deployed body = the committed file; its
--       set_energy_aggressiveness tool writes energy_demand_factor_peak at DEPOT scope (the depot the request names) as
--       'ottocommand', 0.90 down to 0.15. Its self_improve tool calls ottoq_cil_tick, which writes at depot scope as 'cil'.
--   (e) On the live functions, in 0702's own P2 (each write in a block that rolls itself back; the numbers are 0702's
--       file run on the stub engine and must be re-read at apply): the chat seat's write to the newest twin-depot
--       production run was taken; its exact tool write at depot scope while a production session was live was taken at
--       0.25 (the engine floor; the agent floor is 0.30); on a twin run it could write deploy_peak_fraction, which no
--       agent may; AI.001 said "actor ottocommand is not an agent". (4) reproduces the read-only half of this.
--
-- ══ §2 WHAT 0702 DOES, AND WHAT EACH QUERY BELOW MUST RETURN AFTER IT (reproduce (5)-(10)) ═══════════════════════════
--
--   public.ottoq_agent_actors (7 rows, append-only, RLS, SELECT for service_role only); the predicate reads it with no
--   list (ottoq_prime kept as a floor; a list passed is the list alone, as before), STABLE SECURITY DEFINER, executable
--   by anon, authenticated, service_role and supabase_read_only_user, no longer by PUBLIC; AI.001 judges a registry name
--   or a parameter name; FR1 names itself; the production guard's comment. The promote door is not changed and refuses
--   'cil' and 'auto_learning_loop' through the predicate. Each query below says what it must return. A query that
--   returns anything else is a finding.
--
-- ══ §3 WHAT 0702 DOES NOT CLAIM ═══════════════════════════════════════════════════════════════════════════════════
--
--   - The registry classifies the engine's own writers; it is not authentication. Any caller holding the service key can
--     still write any name. The chat seat holds it.
--   - A name the registry does not list is still a person to every guard. The setter's default p_by is the chat seat's,
--     so a caller that names nobody fails closed; a caller that invents a new name does not.
--   - The chat seat still writes at whatever depot its request names (no depot check in ottoq-ottocommand); rule 8 makes
--     the twin depot the only test site, and that edge function is not changed here.
--   - Owner agents (0605, 0700) write owner_settings through the gateway, never ottoq_policy_set; an owner's requirement
--     is the owner's (rule 9), outside this guard by design.
--   - "SELECT for service_role only" is a statement about grants. A member of pg_read_all_data that bypasses row
--     security reads the registry whatever its grants say (supabase_read_only_user and supabase_etl_admin on live).
--   - The platform's own service roles (dashboard_user, pgbouncer, supabase_*_admin, supabase_privileged_role) reached
--     the predicate only through PUBLIC and no longer do; a guard called as one of them now fails "permission denied".
--     None of them issued a statement naming a guard or the predicate since pg_stat_statements' reset on 2026-07-30.
--   - An explicit p_by NULL still reads as a person (the predicate compares COALESCE(p_by, '')); only an omitted p_by is
--     the chat seat's. A write that names nobody is still recorded under updated_by 'ottocommand'.

-- ══ queries (read-only) ══

-- (1) the predicate, its callers, and what depends on it
SELECT p.oid::regprocedure AS sig, p.provolatile, p.prosecdef, p.proconfig, p.proacl::text,
       md5(pg_get_functiondef(p.oid)) AS def_md5, md5(p.prosrc) AS src_md5
  FROM pg_proc p WHERE p.oid = 'public.ottoq_is_agent_actor(text,text[])'::regprocedure;
SELECT p.oid::regprocedure AS caller
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.prokind IN ('f', 'p')
   AND p.oid <> 'public.ottoq_is_agent_actor(text,text[])'::regprocedure
   AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g') ~ 'ottoq_is_agent_actor\s*\('
 ORDER BY 1;
--   must return, after 0702: the six callers named in §1(a), unchanged.
SELECT count(*) AS dependents FROM pg_depend d
 WHERE d.refclassid = 'pg_proc'::regclass AND d.refobjid = 'public.ottoq_is_agent_actor(text,text[])'::regprocedure;
--   must return 0.

-- (2) the setter's call sites that name nobody (they are the chat seat's after 0702), in functions and in cron
WITH calls AS (
  SELECT p.oid::regprocedure::text AS sig, m[1] AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   CROSS JOIN LATERAL regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g'),
                                     'ottoq_policy_set\s*\(((?:[^()]|\([^()]*\))*)\)', 'g') AS m
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.prokind IN ('f', 'p')
     AND p.oid <> 'public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure),
flat AS (SELECT sig, args, regexp_replace(regexp_replace(args, '''[^'']*''', '''''', 'g'), '\([^()]*\)', '()', 'g') AS a FROM calls)
SELECT count(*) AS call_sites,
       count(*) FILTER (WHERE length(a) - length(replace(a, ',', '')) < 4 AND a !~* 'p_by\s*:?=') AS naming_nobody,
       string_agg(sig, ' | ') FILTER (WHERE length(a) - length(replace(a, ',', '')) < 4 AND a !~* 'p_by\s*:?=') AS which
  FROM flat;
--   must return, after 0702: call_sites 11, naming_nobody 0 (before: 1, ottoq_fr1_cert_arm).
SELECT j.jobid, j.jobname, left(j.command, 160) FROM cron.job j WHERE j.command ~ 'ottoq_policy_set' ORDER BY 1;
--   must return 5 jobs (761-763, 784, 785), each passing a name as its fifth argument.

-- (3) who wrote settings, last 30 days, and what the predicate calls each (run before and after 0702)
SELECT now() AS read_at, updated_by, public.ottoq_is_agent_actor(updated_by) AS agent, count(*) AS rows,
       count(DISTINCT scope_id) AS scopes, max(updated_at) AS last_at
  FROM public.ottoq_policy_params WHERE updated_at >= now() - interval '30 days'
 GROUP BY updated_by ORDER BY agent DESC, rows DESC;
SELECT now() AS read_at, e.context ->> 'by' AS by, public.ottoq_is_agent_actor(e.context ->> 'by') AS agent,
       COALESCE(r.run_by, '(no run)') AS run_by, count(*) AS attempts, count(*) FILTER (WHERE NOT e.passed) AS failed,
       min(e.evaluated_at) AS first_at, max(e.evaluated_at) AS last_at
  FROM public.ottoq_rule_evaluations e LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
 WHERE e.rule_code = 'AI.001.agent_dial_within_envelope' AND e.evaluated_at >= now() - interval '30 days'
 GROUP BY 2, 3, 4 ORDER BY 2, 4;
--   must return, after 0702: agent = true for ottoq_prime and ottoq_prime:promoter and for any ottocommand, cil,
--   nemotron-3-ultra or auto_learning_loop row; false for every other name (the engine's and people's).

-- (4) every guard's verdict for the chat seat and the self-tuner, read-only (the STABLE halves of the setter)
WITH prod AS (SELECT sim_run_id FROM public.ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND run_by = 'production_live'
               ORDER BY started_at DESC LIMIT 1),
by_ AS (SELECT unnest(ARRAY['ottoq_prime', 'ottoq_prime:agent_gateway:x', 'ottocommand', 'cil', 'production_start',
                            'scenario_loader', 'chase']) AS by)
SELECT b.by,
       public.ottoq_is_agent_actor(b.by) AS agent,
       public.ottoq_production_write_refusal('run', (SELECT sim_run_id FROM prod), b.by) AS on_the_production_run,
       public.ottoq_production_write_refusal('depot', '11111111-1111-1111-1111-111111111111', b.by) AS at_the_twin_depot_now,
       public.ottoq_dial_clamp('energy_demand_factor_peak', 0.15, b.by) AS clamp_of_0_15,
       public.ottoq_is_agent_actor(b.by)
         AND NOT (SELECT agent_writable FROM public.ottoq_policy_param_catalog WHERE param_key = 'deploy_peak_fraction')
         AS deploy_peak_fraction_refused,
       (public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
          jsonb_build_object('param_key', 'energy_demand_factor_peak', 'requested', 0.15, 'by', b.by),
          (SELECT default_parameters FROM public.ottoq_rules WHERE rule_code = 'AI.001.agent_dial_within_envelope'
            ORDER BY version DESC LIMIT 1))).reason AS ai001
  FROM by_ b;
--   must return, after 0702:
--     ottoq_prime, ottoq_prime:agent_gateway:x, ottocommand, cil: agent t, on_the_production_run 'production_run',
--       clamp_of_0_15 0.3, deploy_peak_fraction_refused t, ai001 'energy_demand_factor_peak = 0.15 is below the agent
--       floor 0.3';
--     production_start, scenario_loader, chase: agent f, on_the_production_run NULL, clamp_of_0_15 0.25,
--       deploy_peak_fraction_refused f, ai001 'actor <name> is not an agent'.
--     at_the_twin_depot_now is 'depot_hosts_a_live_production_session' for the four agents only while a production
--     session is running or paused there, and NULL otherwise (0702's V1 proved the live case in a reopened session).
--   before 0702 (measured): ottocommand and cil read like the people (agent f, NULL, 0.25, f, 'is not an agent').

-- (5) the registry
SELECT actor, kind, added_in, added_at, left(note, 100) AS note FROM public.ottoq_agent_actors ORDER BY actor COLLATE "C";
--   must return 7 rows: auto_learning_loop self_tuner, cil self_tuner, nemotron-3-ultra feed_agent, ottocommand
--   chat_tool, ottoq_prime llm_agent, ottoq_prime:agent_gateway llm_agent, ottoq_prime:promoter self_tuner.
SELECT r AS role, has_table_privilege(r, 'public.ottoq_agent_actors', 'SELECT') AS sel,
       has_table_privilege(r, 'public.ottoq_agent_actors', 'INSERT,UPDATE,DELETE,TRUNCATE') AS write,
       has_function_privilege(r, 'public.ottoq_is_agent_actor(text,text[])', 'EXECUTE') AS predicate
  FROM unnest(ARRAY['anon', 'authenticated', 'service_role', 'supabase_read_only_user', 'dashboard_user']) r;
--   must return: anon f f t; authenticated f f t; service_role t f t; supabase_read_only_user t f t (its SELECT is
--   pg_read_all_data's, not a grant); dashboard_user f f f (it had the predicate only through PUBLIC).
SELECT c.relrowsecurity, (SELECT string_agg(polname, ',') FROM pg_policy WHERE polrelid = c.oid) AS policies,
       (SELECT string_agg(tgname, ',' ORDER BY tgname) FROM pg_trigger WHERE tgrelid = c.oid AND NOT tgisinternal) AS triggers,
       c.relacl::text
  FROM pg_class c WHERE c.oid = 'public.ottoq_agent_actors'::regclass;
--   must return: t, ottoq_agent_actors_service_read, ottoq_agent_actors_append_only_trg,ottoq_agent_actors_no_truncate_trg,
--   and an ACL naming postgres and service_role=r only.

-- (6) the four replaced bodies, as 0702 wrote them (md5 of prosrc: independent of the server's pg_get_functiondef format)
SELECT p.oid::regprocedure AS sig, md5(p.prosrc) AS src_md5, md5(pg_get_functiondef(p.oid)) AS def_md5,
       p.provolatile, p.prosecdef, p.proconfig
  FROM pg_proc p
 WHERE p.oid IN ('public.ottoq_is_agent_actor(text,text[])'::regprocedure,
                 'public.ottoq_rule_eval_agent_dial_envelope(text,uuid,jsonb,jsonb)'::regprocedure,
                 'public.ottoq_production_write_refusal(text,uuid,text)'::regprocedure,
                 'public.ottoq_fr1_cert_arm(uuid,bigint,uuid,integer,timestamp with time zone,boolean)'::regprocedure)
 ORDER BY 1;
--   must return src_md5:
--     ottoq_fr1_cert_arm                   6a4aae6f80becf24297f0427524d4ce5
--     ottoq_is_agent_actor                 713b1ad12171ec2952a33219a566abac  (s, true, {"search_path=public, pg_temp"})
--     ottoq_production_write_refusal       2ec5bbb09de9bf1a882056acd45244db
--     ottoq_rule_eval_agent_dial_envelope  0fa35238210c5363ce60f30fb708db00
--   (def_md5 on the PostgreSQL 16 scratch server: f31abed6dc53ad8a1c1f3076800ad4fb, 56b70c1c91c15c8266708ccdca102deb,
--   7d2ed27eb62e14b50f428bd5e1eb56fe, 68478b0fd4297747d701ab5429b741cc; the live server's should match, since the
--   three patched bodies are their live pre-images with literal replacements.)

-- (7) the apply's own records
SELECT name, forces_recert, forces_dial_restart, classified_at FROM public.ottoq_cert_lineage
 WHERE name = '0702_the_production_guard_knows_every_agent_by_name';
--   must return one row, false, false.
SELECT object_name, def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0702_pre' ORDER BY object_name;
--   must return 4 rows: fr1 2c7b9c06574bfff33de5bfe664deba56, is_agent_actor f349c63ad2c48b7756633024d6da263b,
--   production_write_refusal d9e972c68f66b15b7239b256d64d1cee, AI.001 evaluator 7af6e2b784ec1e358b39f162efe0f31e.

-- (8) the production session a person must see: the settings it would inherit at the twin depot under an agent's name
SELECT pp.scope_type, pp.param_key, pp.param_value, pp.updated_by, pp.updated_at
  FROM public.ottoq_policy_params pp
 WHERE ((pp.scope_type = 'depot' AND pp.scope_id = '11111111-1111-1111-1111-111111111111') OR pp.scope_type = 'global')
   AND public.ottoq_is_agent_actor(pp.updated_by)
 ORDER BY 1, 2;
--   must return the one row it returned before 0702: depot energy_reserve_shave 1, ottoq_prime:promoter, 2026-09-26
--   (G370), unless someone has since written a setting there under an agent's name.

-- (9) watch, after 0702: any attempt by a newly registered agent, and what it got
SELECT e.context ->> 'by' AS by, e.context ->> 'param_key' AS param, e.context ->> 'scope_type' AS scope,
       COALESCE(r.run_by, '(no run)') AS run_by, e.passed, e.reason, e.evaluated_at
  FROM public.ottoq_rule_evaluations e LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
 WHERE e.rule_code = 'AI.001.agent_dial_within_envelope'
   AND e.evaluated_at >= (SELECT classified_at FROM public.ottoq_cert_lineage
                           WHERE name = '0702_the_production_guard_knows_every_agent_by_name')
   AND public.ottoq_is_agent_actor(e.context ->> 'by')
   AND NOT public.ottoq_is_agent_actor(e.context ->> 'by', ARRAY['ottoq_prime'])
 ORDER BY e.evaluated_at DESC LIMIT 50;
--   rows are expected only when someone uses the chat seat or the self-tuner; each must read as judged (passed false
--   below 0.3 or on a dial no agent owns), and no row may stand in ottoq_policy_params under one of those names on a
--   production_live run:
SELECT pp.* FROM public.ottoq_policy_params pp JOIN public.ottoq_sim_runs r ON r.sim_run_id = pp.scope_id
 WHERE pp.scope_type = 'run' AND r.run_by = 'production_live' AND public.ottoq_is_agent_actor(pp.updated_by)
   AND pp.updated_at >= (SELECT classified_at FROM public.ottoq_cert_lineage
                          WHERE name = '0702_the_production_guard_knows_every_agent_by_name');
--   must return 0 rows.

-- (10) 0716's promote door: still asks the predicate, and whom it refuses (the door's own test, read-only; the door itself
--      writes, so it is not called here)
SELECT now() AS read_at,
       strpos(regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_feed_plan_promote(uuid,text,text)'::regprocedure),
                                            '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g'),
              'public.ottoq_is_agent_actor(v_by) OR v_by ILIKE ''nemotron%'' OR v_by ILIKE ''%agent%'' OR v_by ILIKE ''ottocommand%''') > 0
         AS door_reads_the_predicate;
--   must return true.
SELECT n AS name, public.ottoq_is_agent_actor(n) AS predicate,
       public.ottoq_is_agent_actor(n) OR n ILIKE 'nemotron%' OR n ILIKE '%agent%' OR n ILIKE 'ottocommand%' AS door_refuses
  FROM unnest(ARRAY['nemotron-3-ultra', 'cil', 'auto_learning_loop', 'ottoq_prime', 'ottocommand', 'chase',
                    'research_wing:claude_code']) n;
--   must return, after 0702: door_refuses true for nemotron-3-ultra, cil, auto_learning_loop, ottoq_prime and ottocommand
--   (predicate true for all five), false for chase and research_wing:claude_code (predicate false).
--   before 0702 (measured 19:12:15 UTC): cil and auto_learning_loop were predicate f, door_refuses f; nemotron-3-ultra
--   and ottocommand predicate f, door_refuses t (the door's own patterns); ottoq_prime t, t.
SELECT count(*) AS promotions FROM public.ottoq_feed_plan_promotions
 WHERE promoted_by IN (SELECT n FROM unnest(ARRAY['cil', 'auto_learning_loop']) n) OR promoted_by ~ '^(cil|auto_learning_loop):';
--   must return 0.
