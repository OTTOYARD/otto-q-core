-- migration-version: PENDING
-- migration-name:    the_production_guard_knows_every_agent_by_name
--
-- 0702  **The production guard knows every agent by name: one registry of agent actors, read by every guard that asks
--        "is this an agent". The OttoCommand chat seat and the self-tuner are agents, not people.** (G4xx; db/checks/0439;
--        CLAUDE.md rule 10: "in production no setting changes except under a person's name".)
--
-- ══ §1 WHY (measured 2026-10-13, read-only; reproduce: db/checks/0439) ═════════════════════════════════════════════════
--   The window: the first and last live reads stamped by the database's own clock, 14:47:52 and 15:13:47 UTC (9:47 and
--   10:13 AM CT); catalog reads before the first are unstamped. Logs: the 24 hours before a query run between the reads
--   stamped 14:51:35 and 15:12:22 UTC (the logs tool's default window; its own end was not read).
--   Re-read after 0716 landed (applied 18:46:08 UTC, 1:46 PM CT): the reads stamped 19:03:47 to 19:16:21 UTC (2:03 to
--   2:16 PM CT) found the predicate's sixth caller, the grants and roles in §2(c), and every premise of P1 holding, also
--   after 0562 landed at 19:14:24 UTC (forces_recert TRUE). P0 read 1 in flight at 19:16:01 and 0 at 19:16:21: a recert
--   after 0562 may hold it, and the file refuses until nothing is in flight.
--
--   (a) ONE FUNCTION DECIDES WHO IS AN AGENT, AND IT KNEW ONE NAME. public.ottoq_is_agent_actor(p_by, p_actors DEFAULT
--       NULL) is TRUE when p_by equals an actor or starts with "<actor>:", and with no list the actors are
--       ARRAY['ottoq_prime'] (definition md5 f349c63ad2c48b7756633024d6da263b, IMMUTABLE). Its callers, comment-stripped,
--       six since 0716 (applied 18:46:08 UTC, 1:46 PM CT; re-read at 19:03:56 UTC):
--         ottoq_policy_set                     the 0432 guard: an agent may write only an agent_writable dial
--         ottoq_dial_clamp                     the 0414 clamp: an agent is held to agent_min_value..agent_max_value
--         ottoq_production_write_refusal       the 0629 guard (rule 10): no agent write reaches a production session
--         ottoq_production_start               reports the settings a session inherits that an agent last wrote
--         ottoq_rule_eval_agent_dial_envelope  AI.001, which passes its own list from the rule's parameters
--                                              ({"agent_actors": ["ottoq_prime"]})
--         ottoq_feed_plan_promote              0716's door (definition md5 a6c7351618b4844c5e61d33e13c89047): only a
--                                              person makes a twin feed plan version active. It asks the predicate
--                                              with no list, about the promoter (v_by) and about the plan's author.
--       Literal tests on a writer's name exist in three places, not one. The predicate's default and AI.001's fallback
--       are both ARRAY['ottoq_prime']. And 0716's door refuses by patterns of its own as well as by the predicate:
--       v_by ILIKE 'nemotron%' OR '%agent%' OR 'ottocommand%' (and 'nemotron%' again in its author test). Those
--       patterns only add refusals on top of the predicate, so the door is at least as strict as the setter: a name with
--       'agent' in it is refused a promotion and still writes a setting as a person. 0702 leaves the patterns as they
--       are (one concern per file); after it, the door also refuses 'cil' and 'auto_learning_loop' through the predicate
--       (V1). The other literal 'nemotron' and 'cil' tests in the database (ottoq_agent_review, ottoq_agent_wake,
--       ottoq_capture_decision_model_call, ottoq_cil_tick) read a decision's engine or name an event's actor; none of
--       them decides whether a writer is an agent.
--
--   (b) THE AGENTS IT DID NOT KNOW.
--       - 'ottocommand', the OttoCommand chat seat: edge function ottoq-ottocommand runs an Anthropic model in a tool loop
--         (verify_jwt on; the deployed body is the committed one). Its set_energy_aggressiveness tool writes
--         energy_demand_factor_peak at DEPOT scope, at whatever depot_id the request names, as p_by 'ottocommand', a
--         model-chosen value from 0.90 down to 0.15. As a "person" it got the engine floor 0.25, not the agent floor 0.30,
--         could write dials no agent may write, and was not refused by the rule-10 guard. 0629's own V2 asserted
--         ottoq_production_write_refusal('run', <production run>, 'ottocommand') IS NULL, i.e. it listed the chat seat
--         among the people. Read-only on the live functions at 15:12:22 UTC (db/checks/0439 (4)), 'ottocommand' and
--         'cil' answer exactly as the person 'chase' does: no production refusal on the newest twin-depot production run
--         (c4ee1572), a clamp of 0.15 to 0.25, deploy_peak_fraction allowed, and AI.001's "actor ottocommand is not an
--         agent". P2 below re-measures it at apply by writing, each write in a block that rolls back: the chat seat's
--         write to that production run is TAKEN, its exact tool write (depot scope, 0.15) is TAKEN at 0.25 while a
--         production session is live at the depot, and on a twin run it writes deploy_peak_fraction (proven on the stub
--         engine, tests/test_agent_actor_registry_sql.py; P2 raises if live answers otherwise).
--       - 'cil', the continuous-improvement loop (ottoq_cil_tick): it A/B-tests settings in the twin and adopts the
--         winner at DEPOT scope (deploy_peak_fraction, not agent-writable, and energy_demand_factor_peak). Its own source
--         calls it "the ONE agent in the engine that changes a dial on its own judgement". ottoq_cil_tune_refusal refuses a
--         production RUN, but a depot-scoped write is read by every run at the depot, a live production session included.
--         Reachable from OttoCommand's self_improve tool and by RPC. Latent today: ottoq_cil_adoptions holds 0 rows and
--         the twin depot carries 7 enabled certification columns, so cil_tune_refusal refuses it there.
--       - the feed agents (ottoq-feed-agents, NVIDIA Nemotron 3 Ultra) write ottoq_feed_plans as 'nemotron-3-ultra'
--         (since 0716 as drafts that only a person promotes), and otto-q-api's forecast learning loop writes
--         model_parameters as 'auto_learning_loop'. Neither reaches a setting today; registered so that if one ever does,
--         it is an agent there, and so that 0716's promote door refuses them through the predicate and not only through
--         its own 'nemotron%' pattern.
--       Outside agents through the 0559 door write as 'ottoq_prime:agent_gateway:<principal>' and the promoter as
--       'ottoq_prime:promoter': both were already agents through the prefix. Owner agents (0605, 0700) reach
--       owner_settings, never ottoq_policy_set: an owner's requirement is the owner's (rule 9), not OTTO-Q's setting.
--
--   (c) WHO WROTE SETTINGS, LAST 30 DAYS, AND WHAT THEY ARE. ottoq_policy_params keeps the last writer per key and has
--       no history table and no trigger; the shield's AI.001 log keeps every attempt through the setter (its rows
--       survive from 2026-09-30, the purge took the rest). 43 distinct updated_by names wrote a row still standing; 11
--       distinct names attempted a write through the setter. Agents among them: 'ottoq_prime' (250 run-scope rows, 57
--       runs; 25 attempts, 3 of them on a production_live run at 04:17 UTC on 2026-10-09) and 'ottoq_prime:promoter' (1
--       depot row, 2026-09-26). Every other name is the engine or a person: migration and harness names (0152_cert_quiesce,
--       0439_dial_*, 0568_sweep_*, scenario_loader, auto:<run_by> from the agentic arm, proposer_bridge, production_start),
--       the window crons (dial_window_cron:*, sweep_window_cron:*), and people or engineering sessions (chase_e2e_watch,
--       operator_*, claude_*, codex_*, research_wing_*). No 'ottocommand' or 'cil' write in the window; the last
--       'ottocommand' rows standing are two from 2026-07-15 (the FR1 procedure's, see (e), and one at the benchmark
--       depot), 'orchestra_ui' one person's UI write at the twin depot (2026-07-20).
--
--   (d) THE REGISTRY, NOT AN ALLOW-LIST OF PEOPLE, AND WHY. Inverting the predicate to "anything not a listed person is
--       an agent" would refuse the engine. production_start arms a session through the setter with 12 dials none of which
--       is agent-writable, and ottoq_agentic_arm raises on any refused write, so no production session could start; the
--       agentic arm writes as 'auto:<run_by>' on every operator run and sweep; the scenario loader, the window crons and
--       every migration that sets a dial write under free-form names (41 of the 43 standing names are not agents, most
--       of them one-off). A list of every non-agent name would have to grow with every migration and would refuse the
--       first one that forgot. The agents are few, known and named by code; so the registry lists them.
--       The registry's weak point is a name it does not know, and the commonest such name is closed by construction:
--       ottoq_policy_set's p_by DEFAULTS to 'ottocommand', which is now an agent, so a caller that names nobody is
--       treated as the chat seat: refused in production, clamped to the agent envelope, refused on a dial no agent may
--       write. Fail-closed, which is rule 10's direction. The registry is a classification of the engine's own writers,
--       not authentication: a caller holding the service key can still write any name (the chat seat, for one, holds it).
--
--   (e) THE ONE ENGINE CALLER THAT RELIED ON THE DEFAULT. Of the 11 call sites of ottoq_policy_set in the database, one
--       passes no p_by: public.ottoq_fr1_cert_arm, a retired benchmark procedure on the benchmark depot (rule 8: not a
--       test site; it is called by no function, no cron job and nothing in this repo), whose energy_mpc_follow write
--       (not agent-writable) stands as 'ottocommand' on a run that no longer exists. It PERFORMs the call, discarding the
--       verdict, so with 'ottocommand' an agent a revived FR1 would silently run without MPC follow. It names itself
--       here, so its write stays a harness's. No cron job calls the setter without a name (5 call it, all named).
--       Outside the database, of the 12 repositories on disk no running code calls the setter without a name. Two places
--       write it without one, and both now fail closed rather than write: ottoyarddepot-sim's armTimings.test.ts:69
--       describes a person's acceptance step as ottoq_policy_set('global', null, 'robotic_arm_retract_seconds', 9.0), a
--       dial no agent may write, so that call now returns not_agent_writable (and production_never_self_tunes while a
--       production session is live): the person passes their own name. And otto-q-workspace's applied 2026-08-12
--       migration (..._the_arm_only_latches_when_it_actually_found_the_inlet) made twelve unnamed robotic_* writes in a
--       one-off DO block that is not re-run. One standing 'ottocommand' row is not the chat seat's and not FR1's: depot
--       energy_reserve_shave = 0 at the benchmark depot, 2026-07-15 14:26 UTC. The chat seat's only setter call writes
--       energy_demand_factor_peak, so some caller outside the function census (manual SQL, most likely) relied on the
--       default. The params table keeps only the last writer per key, so callers like that one can be undercounted.
--
--   (f) THE SHIELD JUDGED ITS OWN LIST. AI.001 (log_only) reads its actors from its parameters, so after (a) alone the
--       setter would clamp and refuse the chat seat while the shield's ledger said "actor ottocommand is not an agent".
--       It now judges an actor the registry names OR its parameters name, so a second identity can still be added as
--       data, and the shield and the setter cannot disagree about who is an agent.
--
-- ══ §2 WHAT CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_agent_actors, new: one row per agent actor (actor, kind in llm_agent | self_tuner | feed_agent |
--       chat_tool, note, added_in, added_at). An actor matches p_by equal to it or "<actor>:<anything>", as before.
--       Lower-case names only, no '%' or '\' (a wildcard could make every engine name an agent). Append-only: UPDATE,
--       DELETE and TRUNCATE are refused (removing an agent makes its writes a person's), overridable only with
--       ottoq.agent_actors_unlock=on in a migration that says why. RLS on; SELECT for service_role only; no client role
--       may read or write it; rows are added by a migration (postgres). "Only service_role" is true of the grants, not
--       of every role: members of pg_read_all_data that also bypass row security read it regardless (on live,
--       supabase_read_only_user and supabase_etl_admin; postgres owns it). Nothing in it is secret (it is this file).
--   (b) Seven rows: ottoq_prime (llm_agent), ottoq_prime:promoter (self_tuner), ottoq_prime:agent_gateway (llm_agent),
--       ottocommand (chat_tool), cil (self_tuner), nemotron-3-ultra (feed_agent), auto_learning_loop (self_tuner).
--   (c) public.ottoq_is_agent_actor, same signature and default: with no list it reads the registry, plus 'ottoq_prime'
--       as a floor (the one name it knew; an emptied registry cannot make the agent a person). With a list, the list
--       alone, as before. The same equality-or-prefix LIKE test, so every answer for a name the registry does not add is
--       unchanged (V2 proves it over every name with a standing row and every name that tried in the window). STABLE (it reads a table; nothing depended on
--       IMMUTABLE: no index, constraint, default or view), SECURITY DEFINER with search_path public, pg_temp (the
--       registry is closed to the roles every guard runs as). EXECUTE: anon, authenticated and service_role as before,
--       and supabase_read_only_user where that role exists; PUBLIC revoked (0198: no SECURITY DEFINER function is
--       PUBLIC's). It returns one boolean and writes nothing.
--       What the PUBLIC revoke costs, measured at 19:05:42 UTC: every role on live may execute the guards, all through
--       PUBLIC, so a role granted neither the predicate nor a role that holds it would now get "permission denied for
--       function ottoq_is_agent_actor" from inside a guard. supabase_read_only_user is granted explicitly because it is
--       the read-only diagnostic role (db/checks/0439's queries (3), (4), (8) and (9) call the predicate); it reads the
--       registry through pg_read_all_data anyway, so the grant gives it nothing new. cli_login_postgres acts as postgres
--       (SET ROLE) and authenticator as anon, authenticated or service_role, which keep it. The rest are the platform's
--       service roles (dashboard_user, pgbouncer, supabase_auth_admin, supabase_etl_admin, supabase_functions_admin,
--       supabase_privileged_role, supabase_realtime_admin, supabase_replication_admin, supabase_storage_admin): they
--       lose it. pg_stat_statements since its reset on 2026-07-30 shows only service_role (21,322 calls) and postgres
--       (112) issuing a statement that names any guard or the predicate.
--   (d) public.ottoq_rule_eval_agent_dial_envelope (AI.001): judges an actor the registry names or its parameters name.
--   (e) public.ottoq_fr1_cert_arm: passes p_by 'fr1_cert_arm' to its one setter call.
--   (f) public.ottoq_production_write_refusal: its comment named only ottoq_prime; now it names the registry. Comments
--       only: the comment-stripped body is unchanged (V5).
--   NOT changed: ottoq_policy_set, ottoq_dial_clamp, ottoq_production_start and ottoq_feed_plan_promote (their calls
--   already read the predicate with no list, so they read the registry); the promote door's own ILIKE patterns; the
--   setter's default p_by; anything in production that is a person's.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   Every answer for 'ottoq_prime' and every name not newly registered is unchanged (V1: the 0629 probes, the arm and
--   the person's writes read back byte for byte; V2: the predicate over every name that wrote). The answers that change are for 'ottocommand', 'cil',
--   'nemotron-3-ultra' and 'auto_learning_loop', and none of them writes in a certification arm, a dial pair or a sweep:
--   certification arms write their dials directly (0 policy_write attempts on a cert_harness run in the window), and
--   dial pairs and sweeps write as auto:ab_harness, scenario_loader, 0439_dial_* and 0568_sweep_*. FR1 is not a canon
--   column and has no caller. AI.001's payload is digested by ottoq_hash_rule_evaluations; it changes only for those
--   four names. The promote door now also refuses 'cil' and 'auto_learning_loop'; no run reads who promoted a plan, and
--   no plan has been promoted (ottoq_feed_plan_promotions: 0 rows at 19:04:15 UTC).
--
-- ══ §4 ROLLBACK ════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0702_pre' (CREATE OR REPLACE restores IMMUTABLE,
--   SECURITY INVOKER and no search_path on the predicate); GRANT EXECUTE ON FUNCTION public.ottoq_is_agent_actor(text,
--   text[]) TO PUBLIC (and REVOKE it from supabase_read_only_user, which held it only through PUBLIC before); DELETE FROM
--   ottoq_cert_lineage WHERE name = '0702_the_production_guard_knows_every_agent_by_name'.
--   The registry stays (never DROP); nothing reads it once the predicate is restored.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0702 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
DECLARE
  r record; v_set text; v_callers text; v_unnamed text; v_n int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0629_a_production_session_is_armed_and_no_agent_write_reaches_it') THEN
    RAISE EXCEPTION '0702 P1: 0629 is not classified; this file amends its guard';
  END IF;
  IF to_regclass('public.ottoq_agent_actors') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0702_the_production_guard_knows_every_agent_by_name') THEN
    RAISE EXCEPTION '0702 P1: already applied';
  END IF;

  -- the four definitions this file replaces, as read
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_is_agent_actor(text,text[])',                                             'f349c63ad2c48b7756633024d6da263b'),
    ('public.ottoq_rule_eval_agent_dial_envelope(text,uuid,jsonb,jsonb)',                    '7af6e2b784ec1e358b39f162efe0f31e'),
    ('public.ottoq_production_write_refusal(text,uuid,text)',                                'd9e972c68f66b15b7239b256d64d1cee'),
    ('public.ottoq_fr1_cert_arm(uuid,bigint,uuid,integer,timestamp with time zone,boolean)', '2c7b9c06574bfff33de5bfe664deba56')
  ) AS t(sig, def_md5) LOOP
    IF to_regprocedure(r.sig) IS NULL THEN
      RAISE EXCEPTION '0702 P1: % does not exist', r.sig;
    END IF;
    IF md5(pg_get_functiondef(to_regprocedure(r.sig))) IS DISTINCT FROM r.def_md5 THEN
      RAISE EXCEPTION '0702 P1: % is not the definition this file was written against (md5 %); read it again',
        r.sig, md5(pg_get_functiondef(to_regprocedure(r.sig)));
    END IF;
  END LOOP;

  -- the setter reads the predicate with no list, clamps by p_by, refuses by p_by, and defaults p_by to the chat seat
  v_set := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure),
                                         '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF strpos(v_set, 'public.ottoq_is_agent_actor(p_by)') = 0
     OR strpos(v_set, 'public.ottoq_dial_clamp(p_param_key, p_param_value, p_by)') = 0
     OR strpos(v_set, 'public.ottoq_production_write_refusal(p_scope_type, p_scope_id, p_by)') = 0
     OR strpos(pg_get_function_arguments('public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure),
               'p_by text DEFAULT ''ottocommand''::text') = 0 THEN
    RAISE EXCEPTION '0702 P1: ottoq_policy_set does not read the predicate, clamp and refuse by p_by with the default '
                    '''ottocommand'' as this file assumes';
  END IF;

  -- the callers of the predicate are the six this file was written against (comment-stripped; a seventh is re-read)
  SELECT string_agg(p.oid::regprocedure::text, ' | ' ORDER BY p.oid::regprocedure::text COLLATE "C") INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.prokind IN ('f', 'p')
     AND p.oid <> 'public.ottoq_is_agent_actor(text,text[])'::regprocedure
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g') ~ 'ottoq_is_agent_actor\s*\(';
  IF v_callers IS DISTINCT FROM
     'ottoq_dial_clamp(text,numeric,text) | ottoq_feed_plan_promote(uuid,text,text) | '
     'ottoq_policy_set(text,uuid,text,numeric,text) | ottoq_production_start(uuid) | '
     'ottoq_production_write_refusal(text,uuid,text) | ottoq_rule_eval_agent_dial_envelope(text,uuid,jsonb,jsonb)' THEN
    RAISE EXCEPTION '0702 P1: the predicate''s callers are not the six read: %', v_callers;
  END IF;

  -- 0716's promote door asks the predicate with no list, about the promoter and about the author (V1 probes it)
  v_set := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_feed_plan_promote(uuid,text,text)'::regprocedure),
                                         '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF strpos(v_set, 'public.ottoq_is_agent_actor(v_by)') = 0
     OR strpos(v_set, 'public.ottoq_is_agent_actor(v_new.authored_by)') = 0
     OR to_regclass('public.ottoq_feed_plans') IS NULL OR to_regclass('public.ottoq_feed_plan_promotions') IS NULL THEN
    RAISE EXCEPTION '0702 P1: ottoq_feed_plan_promote does not ask the predicate about the promoter and the author as '
                    'this file assumes';
  END IF;

  -- the one call site of the setter that names nobody is FR1's (a new one would become the chat seat's; re-read it)
  WITH calls AS (
    SELECT p.oid::regprocedure::text AS sig, m[1] AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     CROSS JOIN LATERAL regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g'),
                                       'ottoq_policy_set\s*\(((?:[^()]|\([^()]*\))*)\)', 'g') AS m
     WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.prokind IN ('f', 'p')
       AND p.oid <> 'public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure),
  flat AS (
    SELECT sig, args, regexp_replace(regexp_replace(args, '''[^'']*''', '''''', 'g'), '\([^()]*\)', '()', 'g') AS a FROM calls)
  SELECT string_agg(sig || ': ' || args, ' | ' ORDER BY sig), count(*) INTO v_unnamed, v_n
    FROM flat WHERE length(a) - length(replace(a, ',', '')) < 4 AND a !~* 'p_by\s*:?=';
  IF v_n <> 1 OR v_unnamed NOT LIKE 'ottoq_fr1_cert_arm(%' THEN
    RAISE EXCEPTION '0702 P1: the setter''s unnamed call sites are not FR1''s one: % (%)', v_unnamed, v_n;
  END IF;
  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE $q$
      SELECT count(*) FROM cron.job j
       CROSS JOIN LATERAL regexp_matches(j.command, 'ottoq_policy_set\s*\(((?:[^()]|\([^()]*\))*)\)', 'g') AS m
       CROSS JOIN LATERAL (SELECT regexp_replace(regexp_replace(m[1], '''[^'']*''', '''''', 'g'), '\([^()]*\)', '()', 'g') AS a) x
       WHERE length(x.a) - length(replace(x.a, ',', '')) < 4 AND x.a !~* 'p_by\s*:?='$q$ INTO v_n;
    IF v_n <> 0 THEN
      RAISE EXCEPTION '0702 P1: % cron job(s) call the setter without a name; they would become the chat seat''s', v_n;
    END IF;
  END IF;

  -- AI.001 carries the one-name list this file widens
  IF to_regclass('public.ottoq_rules') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.ottoq_rules WHERE rule_code = 'AI.001.agent_dial_within_envelope'
                                          AND default_parameters -> 'agent_actors' = '["ottoq_prime"]'::jsonb) THEN
    RAISE EXCEPTION '0702 P1: AI.001''s agent_actors parameter is not ["ottoq_prime"]';
  END IF;

  -- the catalog the probes read: the agent floor on the chat seat's dial, and a dial no agent may write
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'energy_demand_factor_peak'
                    AND agent_writable AND min_value = 0.25 AND agent_min_value = 0.3)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'deploy_peak_fraction'
                       AND NOT agent_writable) THEN
    RAISE EXCEPTION '0702 P1: the catalog''s energy_demand_factor_peak (0.25 / agent 0.3) or deploy_peak_fraction '
                    '(not agent-writable) is not as read';
  END IF;
END $premises$;

-- ── snapshot: the four definitions as they stood ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0702_pre', 'function', n.nspname, p.oid::regprocedure::text, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_is_agent_actor(text,text[])'::regprocedure,
                 'public.ottoq_rule_eval_agent_dial_envelope(text,uuid,jsonb,jsonb)'::regprocedure,
                 'public.ottoq_production_write_refusal(text,uuid,text)'::regprocedure,
                 'public.ottoq_fr1_cert_arm(uuid,bigint,uuid,integer,timestamp with time zone,boolean)'::regprocedure);

-- ══ the probes: every guard the predicate feeds, before and after, each write in a block that rolls itself back ══════
CREATE TEMP TABLE p0702 (phase text PRIMARY KEY, r jsonb) ON COMMIT DROP;

CREATE FUNCTION pg_temp.p0702_probe(p_phase text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  c_twin   constant uuid  := '11111111-1111-1111-1111-111111111111';
  c_global constant uuid  := '00000000-0000-0000-0000-000000000000';
  c_person constant text  := '0702_probe_person';
  c_params constant jsonb := '{"agent_actors": ["ottoq_prime"]}';   -- AI.001's live parameters (P1)
  c_plan   constant uuid  := '00000000-0000-0000-0000-000000000702'; -- the promote door's probe plan (rolled back)
  v_prod uuid; v_demo uuid; v_r jsonb := '{}'::jsonb; v_x jsonb; v_y jsonb; v_arm jsonb; v_msg text; v_name text;
BEGIN
  SELECT sim_run_id INTO v_prod FROM public.ottoq_sim_runs
   WHERE depot_id = c_twin AND run_by = 'production_live' ORDER BY started_at DESC LIMIT 1;
  --: an operator run that is over: the probes upsert its run-scope rows, and a running run's agent writes the same keys
  SELECT sim_run_id INTO v_demo FROM public.ottoq_sim_runs
   WHERE depot_id = c_twin AND run_by = 'operator_demo' AND status NOT IN ('running', 'paused')
   ORDER BY started_at DESC LIMIT 1;
  IF v_prod IS NULL OR v_demo IS NULL THEN
    RAISE EXCEPTION '0702 probe: the twin depot has no production run or no finished operator run to probe';
  END IF;

  -- AI.001's verdicts (read-only), with the live rule's parameters
  v_r := jsonb_build_object('ai001', jsonb_build_object(
    'ottocommand', to_jsonb(public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
                     jsonb_build_object('param_key', 'energy_demand_factor_peak', 'requested', 0.15, 'by', 'ottocommand'), c_params)),
    'cil_not_writable', to_jsonb(public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
                     jsonb_build_object('param_key', 'deploy_peak_fraction', 'requested', 0.5, 'by', 'cil'), c_params)),
    'ottoq_prime', to_jsonb(public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
                     jsonb_build_object('param_key', 'energy_demand_factor_peak', 'requested', 0.15, 'by', 'ottoq_prime'), c_params)),
    'promoter', to_jsonb(public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
                     jsonb_build_object('param_key', 'deploy_peak_fraction', 'requested', 0.5, 'by', 'ottoq_prime:promoter'), c_params)),
    'person', to_jsonb(public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
                     jsonb_build_object('param_key', 'energy_demand_factor_peak', 'requested', 0.15, 'by', c_person), c_params))));

  BEGIN
    -- (0) 0629's production arm on the newest production run, as 0629's V5 ran it
    v_arm := public.ottoq_agentic_arm(v_prod, '0702_probe_arm');
    v_r := v_r || jsonb_build_object('arm', jsonb_build_object(
      'ok', v_arm -> 'ok',
      'applied', (SELECT jsonb_object_agg(x ->> 'param', x -> 'applied') FROM jsonb_array_elements(v_arm -> 'receipts') x),
      'verdict', v_arm #> '{arming,verdict}'));

    -- (1) the newest twin-depot production run (over): run scope, as 0629's V3 probed it, and the two new agents
    v_x := jsonb_build_object('ottoq_prime', public.ottoq_policy_set('run', v_prod, 'energy_reserve_shave', 1, 'ottoq_prime'));
    v_x := v_x || jsonb_build_object('gateway', public.ottoq_policy_set('run', v_prod, 'energy_demand_factor_peak', 0.5,
                                                                         'ottoq_prime:agent_gateway:0702'));
    v_x := v_x || jsonb_build_object('ops', public.ottoq_apply_ops_action(v_prod, c_twin, 'extend_forecast_horizon',
                                                                           '{}'::jsonb, 'ottoq_prime'));
    v_x := v_x || jsonb_build_object('ottocommand', public.ottoq_policy_set('run', v_prod, 'energy_demand_factor_peak', 0.5,
                                                                             'ottocommand'));
    v_x := v_x || jsonb_build_object('cil', public.ottoq_policy_set('run', v_prod, 'energy_demand_factor_peak', 0.5, 'cil'));
    v_x := v_x || jsonb_build_object('person', public.ottoq_policy_set('run', v_prod, 'energy_demand_factor_peak', 0.5, c_person));
    v_r := v_r || jsonb_build_object('prod_run', v_x);

    -- (2) the newest operator run on the twin: the agent envelope and the agent_writable guard
    v_x := jsonb_build_object('ottocommand_low', public.ottoq_policy_set('run', v_demo, 'energy_demand_factor_peak', 0.15,
                                                                          'ottocommand'));
    v_x := v_x || jsonb_build_object('ottocommand_not_writable', public.ottoq_policy_set('run', v_demo, 'deploy_peak_fraction',
                                                                                          0.5, 'ottocommand'));
    v_x := v_x || jsonb_build_object('cil_not_writable', public.ottoq_policy_set('run', v_demo, 'deploy_peak_fraction', 0.5, 'cil'));
    v_x := v_x || jsonb_build_object('ottoq_prime_low', public.ottoq_policy_set('run', v_demo, 'energy_demand_factor_peak', 0.15,
                                                                                 'ottoq_prime'));
    v_x := v_x || jsonb_build_object('ottoq_prime_not_writable', public.ottoq_policy_set('run', v_demo, 'deploy_peak_fraction',
                                                                                          0.5, 'ottoq_prime'));
    v_x := v_x || jsonb_build_object('person_low', public.ottoq_policy_set('run', v_demo, 'energy_demand_factor_peak', 0.15,
                                                                            c_person));
    v_x := v_x || jsonb_build_object('person_not_writable', public.ottoq_policy_set('run', v_demo, 'deploy_peak_fraction', 0.5,
                                                                                     c_person));
    v_r := v_r || jsonb_build_object('twin_run', v_x);

    -- (3) a live production session: the same production run reopened, paused (live to the guard, and clear of the
    --     one-running-run-per-depot index; no trigger fires on completed -> paused). The chat seat's own tool write.
    UPDATE public.ottoq_sim_runs SET status = 'paused' WHERE sim_run_id = v_prod AND status NOT IN ('running', 'paused');
    v_x := jsonb_build_object('ottocommand_depot', public.ottoq_policy_set('depot', c_twin, 'energy_demand_factor_peak', 0.15,
                                                                            'ottocommand'));
    v_x := v_x || jsonb_build_object('ottocommand_global', public.ottoq_policy_set('global', c_global, 'energy_demand_factor_peak',
                                                                                    0.5, 'ottocommand'));
    v_x := v_x || jsonb_build_object('cil_depot', public.ottoq_policy_set('depot', c_twin, 'deploy_peak_fraction', 0.5, 'cil'));
    v_x := v_x || jsonb_build_object('ottoq_prime_depot', public.ottoq_policy_set('depot', c_twin, 'energy_demand_factor_peak',
                                                                                   0.5, 'ottoq_prime'));
    v_x := v_x || jsonb_build_object('person_depot', public.ottoq_policy_set('depot', c_twin, 'energy_demand_factor_peak', 0.5,
                                                                              c_person));
    v_r := v_r || jsonb_build_object('live_session', v_x);

    -- (4) 0716's promote door: a draft twin feed plan of the probe's own (no real plan is touched), and who may make it
    --     active. Each promotion rolls itself back, so every name is asked about the same draft.
    INSERT INTO public.ottoq_feed_plans (plan_id, var_key, version, status, method, plan, provenance, authored_by, rationale)
    VALUES (c_plan, '__0702_probe', 1, 'draft', 'probe', '{}'::jsonb, '{}'::jsonb, 'nemotron-3-ultra', '0702 probe');
    v_x := '{}'::jsonb;
    FOREACH v_name IN ARRAY ARRAY['nemotron-3-ultra', 'cil', 'auto_learning_loop', 'ottoq_prime', c_person] LOOP
      BEGIN
        v_y := public.ottoq_feed_plan_promote(c_plan, v_name, '0702 probe: who may promote a twin feed plan');
        v_x := v_x || jsonb_build_object(v_name, jsonb_build_object('promoted', v_y));
        RAISE EXCEPTION USING ERRCODE = 'P0702', MESSAGE = '0702 promote probe rolled back';
      EXCEPTION
        WHEN insufficient_privilege THEN v_x := v_x || jsonb_build_object(v_name, jsonb_build_object('refused', SQLERRM));
        WHEN SQLSTATE 'P0702' THEN NULL;
      END;
    END LOOP;
    v_r := v_r || jsonb_build_object('promote', v_x);
    RAISE EXCEPTION '0702 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0702 PROBED' THEN
    RAISE EXCEPTION '0702 probe % failed: %', p_phase, v_msg;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_feed_plans WHERE plan_id = c_plan OR var_key = '__0702_probe')
     OR EXISTS (SELECT 1 FROM public.ottoq_feed_plan_promotions WHERE plan_id = c_plan) THEN
    RAISE EXCEPTION '0702 probe %: the promote door''s probe plan survived its rollback', p_phase;
  END IF;
  INSERT INTO p0702 VALUES (p_phase, v_r);
END $fn$;

-- the predicate over every name that wrote or tried to (last 30 days) and the names this file is about
CREATE TEMP TABLE p0702_names (name text PRIMARY KEY, before boolean, after boolean) ON COMMIT DROP;
DO $names$
BEGIN
  INSERT INTO p0702_names (name)
  SELECT DISTINCT updated_by FROM public.ottoq_policy_params WHERE updated_by IS NOT NULL
  UNION
  SELECT unnest(ARRAY['ottoq_prime', 'ottoq_prime:promoter', 'ottoq_prime:agent_gateway:0702', 'ottocommand',
                      'ottocommand:x', 'cil', 'cil:x', 'nemotron-3-ultra', 'auto_learning_loop', 'production_start',
                      'auto:operator_demo', 'auto:ab_harness', 'scenario_loader', 'proposer_bridge', 'dial_window_cron:close',
                      'sweep_window_cron:open', 'research_wing_kernel_arm', 'fr1_cert_arm', 'orchestra_ui', 'cockpit_operator',
                      'cil_heuristic', 'ottocommander', 'OTTOCOMMAND', 'mpc', '']);
  IF to_regclass('public.ottoq_rule_evaluations') IS NOT NULL THEN
    EXECUTE $q$
      INSERT INTO p0702_names (name)
      SELECT DISTINCT e.context ->> 'by' FROM public.ottoq_rule_evaluations e
       WHERE e.rule_code = 'AI.001.agent_dial_within_envelope' AND e.evaluated_at >= now() - interval '30 days'
         AND e.context ->> 'by' IS NOT NULL
      ON CONFLICT (name) DO NOTHING$q$;
  END IF;
  UPDATE p0702_names SET before = public.ottoq_is_agent_actor(name);
END $names$;

-- the settings a production session at the twin depot would be told it inherits from an agent (production_start's query)
CREATE TEMP TABLE p0702_inherited (phase text PRIMARY KEY, r jsonb) ON COMMIT DROP;
INSERT INTO p0702_inherited
SELECT 'before', COALESCE(jsonb_agg(jsonb_build_object('scope_type', pp.scope_type, 'param_key', pp.param_key,
                                                       'value', pp.param_value, 'updated_by', pp.updated_by)
                                    ORDER BY pp.scope_type, pp.param_key), '[]'::jsonb)
  FROM public.ottoq_policy_params pp
 WHERE ((pp.scope_type = 'depot' AND pp.scope_id = '11111111-1111-1111-1111-111111111111') OR pp.scope_type = 'global')
   AND public.ottoq_is_agent_actor(pp.updated_by);

-- ── P2: the defect, on the live functions: the chat seat and the self-tuner write as people ──
DO $p2$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.p0702_probe('before');
  SELECT r INTO v FROM p0702 WHERE phase = 'before';
  IF v #>> '{prod_run,ottocommand,ok}' IS DISTINCT FROM 'true'
     OR v #>> '{prod_run,cil,ok}' IS DISTINCT FROM 'true'
     OR v #>> '{live_session,ottocommand_depot,ok}' IS DISTINCT FROM 'true'
     OR (v #>> '{live_session,ottocommand_depot,applied}')::numeric IS DISTINCT FROM 0.25
     OR (v #>> '{twin_run,ottocommand_low,applied}')::numeric IS DISTINCT FROM 0.25
     OR v #>> '{twin_run,ottocommand_not_writable,ok}' IS DISTINCT FROM 'true'
     OR v #>> '{twin_run,cil_not_writable,ok}' IS DISTINCT FROM 'true'
     OR v #>> '{ai001,ottocommand,reason}' IS DISTINCT FROM 'actor ottocommand is not an agent'
     OR v #>> '{prod_run,ottoq_prime,error}' IS DISTINCT FROM 'production_never_self_tunes'
     -- 0716's door: the feed agent and the agent refused, the self-tuners and a person let through
     OR v #>> '{promote,nemotron-3-ultra,refused}' IS NULL
     OR v #>> '{promote,ottoq_prime,refused}' IS NULL
     OR v #>> '{promote,cil,promoted,ok}' IS DISTINCT FROM 'true'
     OR v #>> '{promote,auto_learning_loop,promoted,ok}' IS DISTINCT FROM 'true'
     OR v #>> '{promote,0702_probe_person,promoted,ok}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '0702 P2: the live guards did not treat the chat seat and the self-tuner as people (%); this file''s '
                    'premise is wrong', v;
  END IF;
  RAISE NOTICE '0702 P2: before: the chat seat on production run: %; its depot write in a live session: %; AI.001: %; '
               'the promote door for cil: %',
    v #> '{prod_run,ottocommand}', v #> '{live_session,ottocommand_depot}', v #>> '{ai001,ottocommand,reason}',
    v #> '{promote,cil}';
END $p2$;

-- ══ (a) the registry ═══════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_agent_actors (
  --: matched as ottoq_is_agent_actor always has: p_by equal to it, or "<actor>:<anything>". Lower-case, no wildcard.
  actor    text PRIMARY KEY
           CONSTRAINT ottoq_agent_actors_actor_shape
           CHECK (actor ~ '^[a-z0-9][a-z0-9_.:-]*[a-z0-9_.-]$' AND length(actor) <= 120),
  kind     text NOT NULL CHECK (kind IN ('llm_agent', 'self_tuner', 'feed_agent', 'chat_tool')),
  --: what it is, where its writes come from, and what it writes
  note     text NOT NULL CHECK (length(btrim(note)) >= 20),
  --: the migration (or the person) that added it
  added_in text NOT NULL CHECK (length(btrim(added_in)) >= 3),
  added_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_agent_actors IS
'0702 (CLAUDE.md rule 10). Every writer that is an agent, not a person: an LLM agent, a self-tuner, a feed agent or a chat '
'tool. public.ottoq_is_agent_actor reads it (with ottoq_prime as a floor) for every guard that asks: the agent_writable '
'guard and the envelope clamp in ottoq_policy_set, the production guard (ottoq_production_write_refusal: in production no '
'setting changes under an agent''s name), production_start''s report, AI.001 and 0716''s feed plan promote door (only a '
'person makes a twin feed plan active). A row names p_by equal to `actor` or '
'starting "<actor>:". Append-only (removing an agent makes its writes a person''s; override: ottoq.agent_actors_unlock=on, '
'in a migration that says why). Read by service_role; added to by a migration.';

CREATE FUNCTION public.ottoq_agent_actors_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.agent_actors_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_agent_actors is append-only: % refused. Removing or renaming an agent turns its writes into a person''s '
    '(CLAUDE.md rule 10). Set ottoq.agent_actors_unlock=on in a migration that says why.', TG_OP
    USING ERRCODE = '42501';
END $fn$;
REVOKE ALL ON FUNCTION public.ottoq_agent_actors_append_only() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER ottoq_agent_actors_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_agent_actors
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_actors_append_only();
CREATE TRIGGER ottoq_agent_actors_no_truncate_trg
  BEFORE TRUNCATE ON public.ottoq_agent_actors
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_actors_append_only();

ALTER TABLE public.ottoq_agent_actors ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_agent_actors_service_read ON public.ottoq_agent_actors FOR SELECT TO service_role USING (true);
REVOKE ALL ON public.ottoq_agent_actors FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_agent_actors TO service_role;

-- ══ (b) the agents, as read on 2026-10-13 ══════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_agent_actors (actor, kind, note, added_in) VALUES
  ('ottoq_prime', 'llm_agent',
   'OTTO-Q''s orchestrator agent (edge function ottoq-orchestrator-agent, NVIDIA Nemotron): set_policy and ops_action '
   'write as p_by ottoq_prime. The prefix also covers every ottoq_prime:<suffix> writer. The one name '
   'ottoq_is_agent_actor knew before 0702; the function keeps it as a floor.', '0702'),
  ('ottoq_prime:promoter', 'self_tuner',
   'Dial promotion (ottoq_promote_dials, ottoq_promote_dial_experiment, ottoq_rollback_dial_promotion) writes at depot '
   'scope as ottoq_prime:promoter. Automatic promotion is off since 0540; one promoted setting is still in force at the '
   'twin depot (G370). Already an agent through the ottoq_prime prefix; listed for its kind.', '0702'),
  ('ottoq_prime:agent_gateway', 'llm_agent',
   'An outside agent''s ops request a person approved (0559, ottoq_agent_request_decide) runs ottoq_apply_ops_action as '
   'ottoq_prime:agent_gateway:<principal>. Already an agent through the ottoq_prime prefix; listed for its kind.', '0702'),
  ('ottocommand', 'chat_tool',
   'The OttoCommand chat seat (edge function ottoq-ottocommand, an Anthropic model in a tool loop): '
   'set_energy_aggressiveness writes energy_demand_factor_peak at depot scope as p_by ottocommand, at the depot the '
   'request names, a model-chosen value down to 0.15; self_improve calls ottoq_cil_tick. Also ottoq_policy_set''s default '
   'p_by, so a write that names nobody is treated as this agent''s.', '0702'),
  ('cil', 'self_tuner',
   'The continuous-improvement loop, ottoq_cil_tick: A/B-tests settings in the twin and adopts the winner at depot scope '
   '(deploy_peak_fraction, energy_demand_factor_peak) as p_by cil. ottoq_cil_tune_refusal refuses a production run but '
   'not a depot write another run reads. Called by OttoCommand''s self_improve tool and by RPC.', '0702'),
  ('nemotron-3-ultra', 'feed_agent',
   'The twin''s feed agents (edge function ottoq-feed-agents, NVIDIA Nemotron 3 Ultra) rewrite simulation sampling plans in '
   'ottoq_feed_plans as authored_by nemotron-3-ultra, as drafts since 0716. They reach no setting today; listed so that if '
   'one ever does, it is an agent there, and so that 0716''s promote door (ottoq_feed_plan_promote) refuses them through '
   'this registry and not only through its own nemotron% pattern.', '0702'),
  ('auto_learning_loop', 'self_tuner',
   'otto-q-api''s forecast learning loop retunes model_parameters as tuned_by auto_learning_loop. It reaches no setting '
   'today; listed so that if it ever does, it is an agent there. 0716''s promote door refuses it through this row.', '0702');

-- ══ (c) the predicate reads the registry ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_is_agent_actor(p_by text, p_actors text[] DEFAULT NULL::text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  --: 0702 (CLAUDE.md rule 10). TRUE when p_by is an agent's name: equal to an actor, or the actor followed by ':' and
  --: anything. With no list (every guard asks so) the actors are public.ottoq_agent_actors plus 'ottoq_prime', the one
  --: name this function knew before 0702, kept as a floor so an emptied registry cannot make the agent a person. With a
  --: list, the list alone, as before (AI.001 passes its parameters'). The same LIKE as before, so a '_' in an actor
  --: matches any one character, as it always has for 'ottoq_prime'. SECURITY DEFINER because the registry is closed to
  --: the roles the guards run as; it returns one boolean and writes nothing.
  SELECT EXISTS (
    SELECT 1
      FROM unnest(COALESCE(p_actors,
                           ARRAY['ottoq_prime'] || ARRAY(SELECT r.actor FROM public.ottoq_agent_actors r))) AS a(actor)
     WHERE COALESCE(p_by,'') = a.actor OR COALESCE(p_by,'') LIKE a.actor || ':%'
  );
$function$;

COMMENT ON FUNCTION public.ottoq_is_agent_actor(text, text[]) IS
'0702. TRUE when p_by names an agent: equal to an actor or "<actor>:..." for an actor in public.ottoq_agent_actors (or '
'ottoq_prime), or in p_actors when a list is passed. Read by ottoq_policy_set (agent_writable guard), ottoq_dial_clamp '
'(agent envelope), ottoq_production_write_refusal (rule 10), ottoq_production_start, AI.001 and ottoq_feed_plan_promote '
'(0716).';

REVOKE ALL ON FUNCTION public.ottoq_is_agent_actor(text, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_is_agent_actor(text, text[]) TO anon, authenticated, service_role;
--: the read-only diagnostic role reached the guards and the predicate through PUBLIC; it keeps the predicate by name
--: (it reads the registry through pg_read_all_data anyway). The platform's service roles lose it: §2(c).
DO $ro$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_read_only_user') THEN
    GRANT EXECUTE ON FUNCTION public.ottoq_is_agent_actor(text, text[]) TO supabase_read_only_user;
  END IF;
END $ro$;

-- ══ (d)-(f) the anchored patches: each anchor once, each stored definition read back as patched ══════════════════════
CREATE TEMP TABLE _0702_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

-- (d) AI.001 judges an actor the registry names, or its parameters name
INSERT INTO _0702_patch VALUES
('public.ottoq_rule_eval_agent_dial_envelope(text,uuid,jsonb,jsonb)', 1,
$old$  IF NOT public.ottoq_is_agent_actor(v_by, v_actors) THEN  -- 0414: prefix-aware, so ottoq_prime:promoter is judged
$old$,
$new$  --: 0702: judged when the registry names the actor (public.ottoq_agent_actors, read by ottoq_is_agent_actor with no
  --: list) or this rule's own agent_actors parameter does (0353's data path, kept). Before 0702 only the parameter
  --: counted, so the chat seat and the self-tuner, which the setter clamps and refuses as agents, passed here unjudged.
  IF NOT (public.ottoq_is_agent_actor(v_by) OR public.ottoq_is_agent_actor(v_by, v_actors)) THEN  -- 0414: prefix-aware, so ottoq_prime:promoter is judged
$new$);

-- (e) FR1 names itself
INSERT INTO _0702_patch VALUES
('public.ottoq_fr1_cert_arm(uuid,bigint,uuid,integer,timestamp with time zone,boolean)', 1,
$old$  IF p_mpc THEN PERFORM ottoq_policy_set('run', p_run, 'energy_mpc_follow', 1); END IF;
$old$,
$new$  --: 0702: named. The setter's default p_by is the chat seat's, an agent since 0702, which may not write this dial.
  IF p_mpc THEN PERFORM ottoq_policy_set('run', p_run, 'energy_mpc_follow', 1, 'fr1_cert_arm'); END IF;
$new$);

-- (f) the production guard's comment names the registry
INSERT INTO _0702_patch VALUES
('public.ottoq_production_write_refusal(text,uuid,text)', 1,
$old$  --: a production session. ottoq_is_agent_actor names ottoq_prime and every ottoq_prime:<suffix>: the agent, the
  --: promoter, and an outside agent's request a person approved (0559 keeps the agent's name on it on purpose). A
  --: person's write is never refused here.
$old$,
$new$  --: a production session. ottoq_is_agent_actor names every actor in public.ottoq_agent_actors (0702): ottoq_prime and
  --: every ottoq_prime:<suffix> (the agent, the promoter, and an outside agent's request a person approved, 0559 keeping
  --: the agent's name on it on purpose), the OttoCommand chat seat, the self-tuner and the feed agents. A person's write
  --: is never refused here.
$new$);

-- the guard's logic, comments stripped and whitespace collapsed, to prove (f) changed only its words (V5)
CREATE TEMP TABLE _0702_src_before ON COMMIT DROP AS
SELECT btrim(regexp_replace(regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g'),
                            '\s+', ' ', 'g')) AS src
  FROM pg_proc WHERE oid = 'public.ottoq_production_write_refusal(text,uuid,text)'::regprocedure;

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0702_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0702_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0702 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0702 %: not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ V1: the guards, after: the chat seat and the self-tuner are agents everywhere; everyone else reads back unchanged ══
DO $v1$
DECLARE b jsonb; a jsonb; k text;
BEGIN
  PERFORM pg_temp.p0702_probe('after');
  SELECT r INTO b FROM p0702 WHERE phase = 'before';
  SELECT r INTO a FROM p0702 WHERE phase = 'after';

  -- rule 10: refused in production, at run scope (a session live or over) and at the depot and global scope while live
  IF a #>> '{prod_run,ottocommand,error}' IS DISTINCT FROM 'production_never_self_tunes'
     OR a #>> '{prod_run,ottocommand,reason}' IS DISTINCT FROM 'production_run'
     OR a #>> '{prod_run,cil,error}' IS DISTINCT FROM 'production_never_self_tunes'
     OR a #>> '{live_session,ottocommand_depot,error}' IS DISTINCT FROM 'production_never_self_tunes'
     OR a #>> '{live_session,ottocommand_depot,reason}' IS DISTINCT FROM 'depot_hosts_a_live_production_session'
     OR a #>> '{live_session,ottocommand_global,reason}' IS DISTINCT FROM 'a_production_session_is_live'
     OR a #>> '{live_session,cil_depot,reason}' IS DISTINCT FROM 'depot_hosts_a_live_production_session' THEN
    RAISE EXCEPTION '0702 V1 FAILED: the production guard did not refuse the chat seat or the self-tuner: %', a;
  END IF;
  -- the twin: the agent envelope (0.30, not the engine's 0.25) and the agent_writable guard
  IF a #>> '{twin_run,ottocommand_low,ok}' IS DISTINCT FROM 'true'
     OR (a #>> '{twin_run,ottocommand_low,applied}')::numeric IS DISTINCT FROM 0.3
     OR a #>> '{twin_run,ottocommand_low,clamped}' IS DISTINCT FROM 'true'
     OR a #>> '{twin_run,ottocommand_not_writable,error}' IS DISTINCT FROM 'not_agent_writable'
     OR a #>> '{twin_run,cil_not_writable,error}' IS DISTINCT FROM 'not_agent_writable' THEN
    RAISE EXCEPTION '0702 V1 FAILED: the chat seat or the self-tuner is not held to the agent envelope on a twin run: %',
      a -> 'twin_run';
  END IF;
  -- AI.001 judges them now
  IF a #>> '{ai001,ottocommand,passed}' IS DISTINCT FROM 'false'
     OR a #>> '{ai001,ottocommand,severity_override}' IS DISTINCT FROM 'critical'
     OR a #>> '{ai001,ottocommand,suggested_action}' IS DISTINCT FROM 'clamp_to_agent_envelope'
     OR a #>> '{ai001,cil_not_writable,suggested_action}' IS DISTINCT FROM 'set_agent_writable_or_block_the_actor' THEN
    RAISE EXCEPTION '0702 V1 FAILED: AI.001 does not judge the chat seat or the self-tuner: %', a -> 'ai001';
  END IF;
  -- 0716's door: it only gets stricter. The self-tuners are refused now, through the predicate
  IF a #>> '{promote,cil,refused}'
       IS DISTINCT FROM 'ottoq_feed_plan_promote: cil is an agent; a person promotes a feed plan (0716, rule 10)'
     OR a #>> '{promote,auto_learning_loop,refused}'
       IS DISTINCT FROM 'ottoq_feed_plan_promote: auto_learning_loop is an agent; a person promotes a feed plan (0716, rule 10)' THEN
    RAISE EXCEPTION '0702 V1 FAILED: the promote door does not refuse the self-tuners: %', a -> 'promote';
  END IF;
  -- ottoq_prime, its gateway and promoter, the 0629 arm and a person: byte for byte as before
  FOREACH k IN ARRAY ARRAY['{arm}', '{prod_run,ottoq_prime}', '{prod_run,gateway}', '{prod_run,person}',
                           '{twin_run,ottoq_prime_low}', '{twin_run,ottoq_prime_not_writable}', '{twin_run,person_low}',
                           '{twin_run,person_not_writable}', '{live_session,ottoq_prime_depot}', '{live_session,person_depot}',
                           '{ai001,ottoq_prime}', '{ai001,promoter}', '{ai001,person}', '{promote,nemotron-3-ultra}',
                           '{promote,ottoq_prime}', '{promote,0702_probe_person}'] LOOP
    IF a #> k::text[] IS DISTINCT FROM b #> k::text[] OR a #> k::text[] IS NULL THEN
      RAISE EXCEPTION '0702 V1 FAILED: % moved: % -> %', k, b #> k::text[], a #> k::text[];
    END IF;
  END LOOP;
  IF a #>> '{prod_run,ops,status}' IS DISTINCT FROM b #>> '{prod_run,ops,status}'
     OR a #>> '{prod_run,ops,reason}' IS DISTINCT FROM b #>> '{prod_run,ops,reason}'
     OR a #>> '{prod_run,ops,status}' IS DISTINCT FROM 'refused' THEN
    RAISE EXCEPTION '0702 V1 FAILED: the ops door moved for ottoq_prime: % -> %', b #> '{prod_run,ops}', a #> '{prod_run,ops}';
  END IF;
  -- 0629's own: the arm still lands as built, the person still writes
  IF a #>> '{arm,ok}' IS DISTINCT FROM 'true' OR (a #>> '{arm,applied,proposer_hold_enabled}')::numeric IS DISTINCT FROM 0
     OR (a #>> '{arm,applied,agent_charge_order_ttl_ticks}')::numeric IS DISTINCT FROM 3
     OR a #>> '{prod_run,person,ok}' IS DISTINCT FROM 'true' OR a #>> '{live_session,person_depot,ok}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '0702 V1 FAILED: 0629''s arm or a person''s write did not land: %', a;
  END IF;
  IF a #>> '{promote,0702_probe_person,promoted,ok}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '0702 V1 FAILED: a person may no longer promote a feed plan: %', a -> 'promote';
  END IF;
  RAISE NOTICE '0702 V1 PASSED: the chat seat on a production run: %; its depot write in a live session: %; on a twin run: %; '
               'the promote door refuses cil and auto_learning_loop and lets a person through; all rolled back',
    a #>> '{prod_run,ottocommand,error}', a #>> '{live_session,ottocommand_depot,reason}',
    a #>> '{twin_run,ottocommand_low,applied}';
END $v1$;

-- ══ V2: the predicate over every writer's name: only newly registered names move, and only from person to agent ════════
DO $v2$
DECLARE v_moved text; v_bad text;
BEGIN
  UPDATE p0702_names SET after = public.ottoq_is_agent_actor(name);
  SELECT string_agg(name, ', ' ORDER BY name) INTO v_bad FROM p0702_names n
   WHERE n.before IS DISTINCT FROM n.after
     AND NOT (n.before = false AND n.after = true
              AND EXISTS (SELECT 1 FROM public.ottoq_agent_actors r
                           WHERE r.actor <> 'ottoq_prime' AND (n.name = r.actor OR n.name LIKE r.actor || ':%')));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0702 V2 FAILED: names whose answer moved without a registry row to move it: %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM p0702_names WHERE after IS DISTINCT FROM (name IN (
               'ottoq_prime', 'ottoq_prime:promoter', 'ottoq_prime:agent_gateway:0702', 'ottocommand', 'ottocommand:x',
               'cil', 'cil:x', 'nemotron-3-ultra', 'auto_learning_loop'))
                     AND name IN ('ottoq_prime', 'ottoq_prime:promoter', 'ottoq_prime:agent_gateway:0702', 'ottocommand',
                                  'ottocommand:x', 'cil', 'cil:x', 'nemotron-3-ultra', 'auto_learning_loop',
                                  'production_start', 'auto:operator_demo', 'auto:ab_harness', 'scenario_loader',
                                  'proposer_bridge', 'dial_window_cron:close', 'sweep_window_cron:open',
                                  'research_wing_kernel_arm', 'fr1_cert_arm', 'orchestra_ui', 'cockpit_operator',
                                  'cil_heuristic', 'ottocommander', 'OTTOCOMMAND', 'mpc', ''))
     OR public.ottoq_is_agent_actor(NULL)
     -- a list passed is the list alone, as before
     OR public.ottoq_is_agent_actor('ottocommand', ARRAY['ottoq_prime'])
     OR NOT public.ottoq_is_agent_actor('ottoq_prime:promoter', ARRAY['ottoq_prime'])
     OR public.ottoq_is_agent_actor('ottoq_prime', '{}'::text[]) THEN
    RAISE EXCEPTION '0702 V2 FAILED: the truth table is not as built: %',
      (SELECT jsonb_object_agg(name, after) FROM p0702_names);
  END IF;
  -- production_start's report at the twin depot is the one before
  IF (SELECT COALESCE(jsonb_agg(jsonb_build_object('scope_type', pp.scope_type, 'param_key', pp.param_key,
                                                   'value', pp.param_value, 'updated_by', pp.updated_by)
                                ORDER BY pp.scope_type, pp.param_key), '[]'::jsonb)
        FROM public.ottoq_policy_params pp
       WHERE ((pp.scope_type = 'depot' AND pp.scope_id = '11111111-1111-1111-1111-111111111111') OR pp.scope_type = 'global')
         AND public.ottoq_is_agent_actor(pp.updated_by))
     IS DISTINCT FROM (SELECT r FROM p0702_inherited WHERE phase = 'before') THEN
    RAISE EXCEPTION '0702 V2 FAILED: the twin depot''s inherited agent settings moved';
  END IF;
  SELECT string_agg(name, ', ' ORDER BY name) INTO v_moved FROM p0702_names WHERE before IS DISTINCT FROM after;
  RAISE NOTICE '0702 V2 PASSED: % names read; now agents that were not: %', (SELECT count(*) FROM p0702_names), v_moved;
END $v2$;

-- ══ V3: the registry is closed, append-only and wildcard-free; the predicate is what was written ════════════════════════
DO $v3$
DECLARE v_state text; r text;
BEGIN
  IF (SELECT count(*) FROM public.ottoq_agent_actors) <> 7
     OR (SELECT string_agg(actor || '=' || kind, ',' ORDER BY actor COLLATE "C") FROM public.ottoq_agent_actors)
        IS DISTINCT FROM 'auto_learning_loop=self_tuner,cil=self_tuner,nemotron-3-ultra=feed_agent,ottocommand=chat_tool,'
                         'ottoq_prime=llm_agent,ottoq_prime:agent_gateway=llm_agent,ottoq_prime:promoter=self_tuner' THEN
    RAISE EXCEPTION '0702 V3 FAILED: the registry is not the seven rows written';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF has_table_privilege(r, 'public.ottoq_agent_actors', 'SELECT')
       OR has_table_privilege(r, 'public.ottoq_agent_actors', 'INSERT') THEN
      RAISE EXCEPTION '0702 V3 FAILED: % may read or write the registry', r;
    END IF;
  END LOOP;
  IF NOT has_table_privilege('service_role', 'public.ottoq_agent_actors', 'SELECT')
     OR has_table_privilege('service_role', 'public.ottoq_agent_actors', 'INSERT')
     OR has_table_privilege('service_role', 'public.ottoq_agent_actors', 'UPDATE')
     OR has_table_privilege('service_role', 'public.ottoq_agent_actors', 'DELETE')
     OR has_table_privilege('service_role', 'public.ottoq_agent_actors', 'TRUNCATE')
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.ottoq_agent_actors'::regclass) THEN
    RAISE EXCEPTION '0702 V3 FAILED: the registry''s grants or row security are not as written';
  END IF;
  BEGIN
    DELETE FROM public.ottoq_agent_actors WHERE actor = 'cil';
    v_state := 'deleted';
  EXCEPTION WHEN insufficient_privilege THEN v_state := 'refused';
  END;
  IF v_state <> 'refused' THEN RAISE EXCEPTION '0702 V3 FAILED: a DELETE was not refused'; END IF;
  BEGIN
    UPDATE public.ottoq_agent_actors SET kind = 'llm_agent' WHERE actor = 'cil';
    v_state := 'updated';
  EXCEPTION WHEN insufficient_privilege THEN v_state := 'refused';
  END;
  IF v_state <> 'refused' THEN RAISE EXCEPTION '0702 V3 FAILED: an UPDATE was not refused'; END IF;
  BEGIN
    TRUNCATE public.ottoq_agent_actors;
    v_state := 'truncated';
  EXCEPTION WHEN insufficient_privilege THEN v_state := 'refused';
  END;
  IF v_state <> 'refused' THEN RAISE EXCEPTION '0702 V3 FAILED: a TRUNCATE was not refused'; END IF;
  BEGIN
    INSERT INTO public.ottoq_agent_actors (actor, kind, note, added_in)
    VALUES ('%', 'llm_agent', 'a wildcard would make every name with a colon an agent', '0702_v3');
    v_state := 'inserted';
  EXCEPTION WHEN check_violation THEN v_state := 'refused';
  END;
  IF v_state <> 'refused' THEN RAISE EXCEPTION '0702 V3 FAILED: a wildcard actor was admitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'public.ottoq_is_agent_actor(text,text[])'::regprocedure
                    AND provolatile = 's' AND prosecdef AND proconfig = ARRAY['search_path=public, pg_temp']
                    AND pg_get_function_arguments(oid) = 'p_by text, p_actors text[] DEFAULT NULL::text[]') THEN
    RAISE EXCEPTION '0702 V3 FAILED: the predicate is not STABLE SECURITY DEFINER with its search_path and signature';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_agent_actors) <> 7 THEN
    RAISE EXCEPTION '0702 V3 FAILED: a refused write changed the registry';
  END IF;
END $v3$;

-- ══ V4: as each client role: the registry is closed, and the predicate answers through it ═══════════════════════════════
CREATE FUNCTION pg_temp.p0702_as(p_role text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_msg text;
BEGIN
  BEGIN
    PERFORM set_config('role', p_role, true);
    DECLARE v_read text; v_pred text; v_n bigint;
    BEGIN
      BEGIN
        SELECT count(*) INTO v_n FROM public.ottoq_agent_actors;
        v_read := 'read ' || v_n;
      EXCEPTION WHEN insufficient_privilege THEN v_read := 'refused';
      END;
      BEGIN
        v_pred := CASE WHEN public.ottoq_is_agent_actor('ottocommand') AND NOT public.ottoq_is_agent_actor('production_start')
                       THEN 'agent' ELSE 'person' END;
      EXCEPTION WHEN insufficient_privilege THEN v_pred := 'refused';
      END;
      RAISE EXCEPTION 'AS %|registry %|predicate %', p_role, v_read, v_pred;
    END;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  RETURN v_msg;
END $fn$;

DO $v4$
DECLARE v_anon text := pg_temp.p0702_as('anon'); v_auth text := pg_temp.p0702_as('authenticated');
        v_svc text := pg_temp.p0702_as('service_role'); r text; c text;
BEGIN
  IF v_anon IS DISTINCT FROM 'AS anon|registry refused|predicate agent'
     OR v_auth IS DISTINCT FROM 'AS authenticated|registry refused|predicate agent'
     OR v_svc IS DISTINCT FROM 'AS service_role|registry read 7|predicate agent' THEN
    RAISE EXCEPTION '0702 V4 FAILED: % / % / %', v_anon, v_auth, v_svc;
  END IF;
  -- every client role, and the read-only diagnostic role, that may call a guard may call the predicate it reads (0629's
  -- V6), and PUBLIC may not. (The five are the SECURITY INVOKER callers: their call runs as the caller. 0716's promote
  -- door is SECURITY DEFINER, so its call runs as its owner, postgres, whatever role calls the door.)
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated', 'service_role']
                     || ARRAY(SELECT rolname::text FROM pg_roles WHERE rolname = 'supabase_read_only_user') LOOP
    FOREACH c IN ARRAY ARRAY['public.ottoq_policy_set(text,uuid,text,numeric,text)', 'public.ottoq_dial_clamp(text,numeric,text)',
                             'public.ottoq_production_write_refusal(text,uuid,text)', 'public.ottoq_production_start(uuid)',
                             'public.ottoq_rule_eval_agent_dial_envelope(text,uuid,jsonb,jsonb)'] LOOP
      IF has_function_privilege(r, c, 'EXECUTE')
         AND NOT has_function_privilege(r, 'public.ottoq_is_agent_actor(text,text[])', 'EXECUTE') THEN
        RAISE EXCEPTION '0702 V4 FAILED: % may call % and not the predicate it reads', r, c;
      END IF;
    END LOOP;
  END LOOP;
  IF (SELECT proacl::text FROM pg_proc WHERE oid = 'public.ottoq_is_agent_actor(text,text[])'::regprocedure) ~ '(^|[{,])=X/' THEN
    RAISE EXCEPTION '0702 V4 FAILED: PUBLIC may still call the SECURITY DEFINER predicate';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE oid IN ('public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure,
                                                 'public.ottoq_dial_clamp(text,numeric,text)'::regprocedure,
                                                 'public.ottoq_production_write_refusal(text,uuid,text)'::regprocedure,
                                                 'public.ottoq_production_start(uuid)'::regprocedure,
                                                 'public.ottoq_rule_eval_agent_dial_envelope(text,uuid,jsonb,jsonb)'::regprocedure)
                                    AND prosecdef)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_feed_plan_promote(uuid,text,text)'::regprocedure) THEN
    RAISE EXCEPTION '0702 V4 FAILED: the five guards are not SECURITY INVOKER or the promote door is not SECURITY DEFINER, '
                    'as the parity check above assumes';
  END IF;
  RAISE NOTICE '0702 V4 PASSED: % | % | %; rolled back', v_anon, v_auth, v_svc;
END $v4$;

-- ══ V5: the patched three: FR1 names itself and no setter call names nobody; the guard's logic is unchanged ════════════
DO $v5$
DECLARE v_n int;
BEGIN
  IF strpos(pg_get_functiondef('public.ottoq_fr1_cert_arm(uuid,bigint,uuid,integer,timestamp with time zone,boolean)'::regprocedure),
            'PERFORM ottoq_policy_set(''run'', p_run, ''energy_mpc_follow'', 1, ''fr1_cert_arm'');') = 0 THEN
    RAISE EXCEPTION '0702 V5 FAILED: FR1 does not name itself';
  END IF;
  WITH calls AS (
    SELECT m[1] AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     CROSS JOIN LATERAL regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g'),
                                       'ottoq_policy_set\s*\(((?:[^()]|\([^()]*\))*)\)', 'g') AS m
     WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.prokind IN ('f', 'p')
       AND p.oid <> 'public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure),
  flat AS (SELECT regexp_replace(regexp_replace(args, '''[^'']*''', '''''', 'g'), '\([^()]*\)', '()', 'g') AS a FROM calls)
  SELECT count(*) INTO v_n FROM flat WHERE length(a) - length(replace(a, ',', '')) < 4 AND a !~* 'p_by\s*:?=';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0702 V5 FAILED: % setter call site(s) still name nobody', v_n;
  END IF;
  IF (SELECT btrim(regexp_replace(regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g'),
                                  '\s+', ' ', 'g'))
        FROM pg_proc WHERE oid = 'public.ottoq_production_write_refusal(text,uuid,text)'::regprocedure)
     IS DISTINCT FROM (SELECT src FROM _0702_src_before) THEN
    RAISE EXCEPTION '0702 V5 FAILED: the production guard''s logic changed; only its comment was to';
  END IF;
  IF strpos(pg_get_functiondef('public.ottoq_rule_eval_agent_dial_envelope(text,uuid,jsonb,jsonb)'::regprocedure),
            'IF NOT (public.ottoq_is_agent_actor(v_by) OR public.ottoq_is_agent_actor(v_by, v_actors)) THEN') = 0 THEN
    RAISE EXCEPTION '0702 V5 FAILED: AI.001 does not read the registry';
  END IF;
END $v5$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0702_the_production_guard_knows_every_agent_by_name', false, false,
  'G4xx (db/checks/0439): public.ottoq_agent_actors (append-only, RLS, service_role SELECT) names every agent actor; '
  'ottoq_is_agent_actor reads it with no list (ottoq_prime kept as a floor; an explicit list unchanged), STABLE SECURITY '
  'DEFINER; AI.001 judges an actor the registry or its parameters name; ottoq_fr1_cert_arm names itself; the production '
  'guard''s comment. Newly agents: ottocommand (chat seat, and the setter''s default p_by), cil, nemotron-3-ultra, '
  'auto_learning_loop (0716''s feed plan promote door, the predicate''s sixth caller, now refuses cil and '
  'auto_learning_loop too). FALSE/FALSE: every answer for ottoq_prime and every other name is unchanged (V1, V2); none of '
  'the four new names writes in a certification arm, a dial pair or a sweep.',
  now());

COMMIT;
