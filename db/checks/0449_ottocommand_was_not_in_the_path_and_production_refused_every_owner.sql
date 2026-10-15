-- 0449  **OTTO-Command was not in the path, and production refused every owner.** Hermes is connected to Chase's
--        OTTOYARD account and has never called a tool; an owner command on anything but a demo run is refused; no
--        command names the person behind it or the door it came through. -> 0721 (and the gateway's ask_ottocommand).
--        Chase, 2026-10-14: OTTO-Command should be "the filter and executor" between personal agents and OTTO-Q.
--        Measured 2026-10-14, read-only, in one statement stamped 15:18:23.83-15:18:23.93 UTC (10:18 AM CT) by its own
--        now() and clock_timestamp(); the catalog reads behind §4 also ran at 14:54:24-14:54:35 UTC (9:54 AM CT).
--
-- ══ §1 NOTHING IS SET, AND THE ONE COMMAND EVER SENT WAS REFUSED no_live_demo (reproduce: (1)) ══════════════════════
--
--   ottoq_owner_settings: 0 rows. ottoq_owner_commands: 1 row, the 2026-10-04 11:42:10 UTC smoke test's
--   set_charge_limit preview, refused no_live_demo. No run is running or paused at the twin depot.
--
-- ══ §2 HERMES IS CONNECTED AND HAS NEVER ASKED ANYTHING (reproduce: (2)) ═══════════════════════════════════════════
--
--   oauth.hermes-agent.08e94d9e (origin oauth, active, created 2026-10-10 17:04:21 UTC): 1,886 MCP handshakes (first
--   2026-10-10 17:04:21, last 2026-10-14 15:16:07 UTC) and 94 calls at the token endpoint. Tool calls: 0. Its own model
--   would call the typed tools directly; OTTO-Command is reachable only through REST (POST /v1/ask), and the call ledger
--   holds one transport 'ask' row in its life, the 2026-10-04 11:45:17 UTC smoke test's handshake, with http_status 200
--   (query (2)'s second statement; re-read 2026-10-14 17:36:51 UTC, 12:36 PM CT, by its own clock_timestamp()). That 200
--   is the handshake's. The ask behind it was answered 503 ask_not_configured by the gateway itself (PERSONAL_AGENT.md
--   section 9), an HTTP answer the ledger never records, so a reader re-running (2) finds 200 and no 503, as expected.
--   Whether the gateway's model secrets are set now is not readable from SQL and is not established here.
--
-- ══ §3 THE OWNER DOOR IS DEMO-ONLY, AND RECORDS NEITHER A PERSON NOR A DOOR (reproduce: (3)) ═══════════════════════
--
--   public.ottoq_owner_command sets v_demo := run_by = 'operator_demo' and refuses anything else (IF v_refusal IS NULL AND
--   NOT v_demo THEN ... 'no_live_demo'). A production_live run is refused for every owner, a signed-in one included,
--   although production's world step applies owner settings since 0718. public.ottoq_agent_call calls
--   ottoq_owner_command(v_agent, v_tool, v_args): its transport ('rest', 'mcp', 'ask') never reaches the record.
--   ottoq_owner_commands has no acting_person and no via column, so rule 10's "under a person's name" cannot be read
--   off a command.
--
-- ══ §4 THE BODIES 0721 WAS WRITTEN AGAINST (reproduce: (4)) ════════════════════════════════════════════════════════
--
--   md5(pg_get_functiondef): ottoq_agent_call ae935f897ee25b6db3eacfbb9215797d, ottoq_owner_command
--   533b275b976b5287f1f48b245132139f, ottoq_owner_command_reply bd0c86d127a2a84903fa2fb812ee1ac5,
--   ottoq_agent_read_whoami 53aa8a6690ecc6274e4cd1dc73972006, ottoq_owner_commands_guard
--   758eff5a6a274b176573c6674840dc55. A scratch cluster with 0559, 0560, 0605-0608 and 0700 applied from their files over
--   the stub engine gives the same five (tests/test_ottocommand_executor_sql.py, first test). 0721 is not applied.
--
-- ══ QUERIES ══

-- (1) what is set, what was ever commanded, and whether a run is live at the twin depot
SELECT (SELECT count(*) FROM public.ottoq_owner_settings) AS owner_settings,
       (SELECT jsonb_agg(jsonb_build_object('at', c.created_at, 'tool', c.tool, 'mode', c.mode, 'outcome', c.outcome,
                                            'refusal', c.refusal ->> 'code') ORDER BY c.created_at)
          FROM public.ottoq_owner_commands c) AS owner_commands,
       (SELECT jsonb_agg(jsonb_build_object('run', r.sim_run_id, 'status', r.status, 'run_by', r.run_by))
          FROM public.ottoq_sim_runs r
         WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status IN ('running', 'paused')) AS live_runs,
       now() AS measured_at;

-- (2) Hermes's calls, by transport and tool, and every 'ask' row the ledger has ever held
SELECT l.transport, l.tool, count(*) AS calls, min(l.called_at) AS first, max(l.called_at) AS last
  FROM public.ottoq_agent_call_ledger l
  JOIN public.ottoq_agent_principals a ON a.principal_id = l.principal_id
 WHERE a.name = 'oauth.hermes-agent.08e94d9e'
 GROUP BY 1, 2 ORDER BY 1, 2;
SELECT l.called_at, l.tool, l.http_status, l.principal_name FROM public.ottoq_agent_call_ledger l WHERE l.transport = 'ask';

-- (3) the demo-only gate, the transport the dispatcher keeps, and the columns that do not exist
SELECT strpos(c.prosrc, 'IF v_refusal IS NULL AND NOT v_demo THEN') > 0 AS refuses_every_run_but_a_demo,
       d.prosrc ~ 'ELSE public\.ottoq_owner_command\(v_agent, v_tool, v_args\)\n' AS transport_not_passed,
       (SELECT count(*) FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'ottoq_owner_commands'
           AND column_name IN ('acting_person', 'via')) AS person_or_door_columns
  FROM pg_proc c, pg_proc d
 WHERE c.oid = 'public.ottoq_owner_command(ottoq_agent_principals,text,jsonb)'::regprocedure
   AND d.oid = 'public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure;

-- (4) the five bodies 0721 replaces, as 0721's P1 pins them
SELECT p.proname, md5(pg_get_functiondef(p.oid)) AS def_md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_agent_call', 'ottoq_owner_command', 'ottoq_owner_command_reply', 'ottoq_agent_read_whoami',
                     'ottoq_owner_commands_guard')
 ORDER BY 1;
