-- migration-version: PENDING
-- migration-name:    a_signed_in_owner_changes_production_under_their_own_name
--
-- 0721  **A signed-in owner changes production under their own name, and every owner command says which door it came
--        through.** OTTO-Command becomes the one filter and executor between an owner's personal agent and OTTO-Q
--        (Chase, 2026-10-14: "It should just act as both a query LLM bot to provide answers and search results, and also
--        execute for OTTO-Q when preferences are changed via personal agents like Hermes, Grok, etc. So request comes in
--        from personal agents, OTTOCommand processes and acts and returns info back. So it will act as the filter and
--        executor there."). The agent gateway's half (the MCP tool ask_ottocommand, the wider reads, the 50-second cap)
--        is in edge-functions/_shared/; this file is the database's half. CLAUDE.md rules 9 and 10; db/checks/0449.
--
--        AND WHAT AN OWNER SETS IS SAVED TO THE CAR; OTTO-COMMAND SEARCHES OTTO-Q AND THE WEB. Chase, 2026-10-14, his
--        message read at 12:35 PM CT: "Search should cover OTTO-Q and web. It can be ask and tools as well." and
--        "Everything you listed looks great from a default perspective", which accepted: a vehicle owner's settings
--        persist per vehicle (they are the owner's, by contract, until the owner changes them), and OTTO-Command answers
--        questions from OTTO-Q's data and the web and executes owner changes, as the filter and executor for personal
--        agents (Hermes, Grok, ...). Earlier the same day (8:58 AM CT): "request comes in from personal agents,
--        OTTOCommand processes and acts and returns info back. So it will act as the filter and executor there. All
--        services must be completed before vehicle leaves depot." §9-§13 below are that decision's database half; the
--        gateway's half (web search, the read-only tool ottocommand_search, the model ledger call) is in the TypeScript.
--
-- ══ §1 WHY (read-only on the live catalog, 2026-10-14: stamped reads 14:54:24-14:54:35 and 15:18:23-15:18:52 UTC,
--    9:54 and 10:18 AM CT; reproduce: db/checks/0449) ════════════════════════════════════════════════════════════════
--
--   (a) PRODUCTION IS REFUSED TO EVERY OWNER. public.ottoq_owner_command (md5 533b275b976b5287f1f48b245132139f) sets
--       v_demo := run_by = 'operator_demo' and refuses anything else as no_live_demo. Since 0718 (applied
--       20261013210801) production's world step, twin.ottoq_world_advance, applies owner settings at every tick
--       (ottoq.ottoq_owner_orders_tick before the visit atoms), so the engine side is ready and the door is the only
--       thing between an owner and their own cars in production. The one owner command ever recorded is the 2026-10-04
--       smoke test's preview, refused no_live_demo.
--   (b) NO PERSON IS RECORDED. ottoq_owner_commands carries principal_id and principal_name, the AGENT
--       ("oauth.hermes-agent.08e94d9e"), and nothing names the person behind it, so rule 10's "in production no setting
--       changes except under a person's name" cannot be read off the record. An agent signed in through 0700 has one:
--       ottoq_oauth_grants ties its principal to an ottoq_owner_accounts row (chase@ottoyard.com, linked to Tesla Robotaxi
--       TN, the one account). A passcode session (0607) and an issued key (0559) name no one.
--   (c) NO RECORD OF WHICH DOOR. ottoq_agent_call knows the transport ('rest', 'mcp', 'ask') and does not pass it on, so
--       a command OTTO-Command made reads exactly like one the agent's own model made.
--   (d) LOWERING A CHARGE LIMIT IS ONE CALL. Rule 9: a lower limit is the owner's, "set verified and confirmed". 0605
--       counts an explicit apply as the confirmation, which holds on a demo run. In production a lower limit should be
--       applied only as the confirm of a preview OTTO-Q itself recorded, by the same agent and recently, so the plan
--       confirmed is the plan applied. A plan hash alone does not do that: it is md5 of data the token can already
--       read, so an agent could compute it and skip the preview.
--
--   §9-§13 (read-only on the live catalog, 2026-10-14 between 17:59 and 18:17 UTC, 12:59-1:17 PM CT):
--   (e) NOTHING AN OWNER SETS OUTLIVES ITS RUN. ottoq_owner_settings is registered class 'engine' on sim_run_id, holds 0
--       rows, and has three writers: ottoq_owner_command, ottoq.ottoq_owner_orders_tick and the run's end,
--       ottoq_tg_lift_owner_settings_on_terminal (md5 e7d0a3f35a057175f7de8ffc88c98b99), which lifts every active setting
--       when its run reaches completed, failed or aborted and stamps lifted_at on the commands; ottoq_purge_prior_runs
--       (called by ottoq_start_demo_run) then deletes them with their run by registry lookup (production_live runs
--       excepted); ottoq_retention_purge_runs's allowlist (7 tables) does not hold it; ottoq_start_demo_run,
--       ottoq_operator_start_run and ottoq_production_start carry nothing over. So a charge limit or an every-return order
--       set today is gone at the next run, in production too. ottoq_effective_target_soc_at reads the limit only through
--       the run in scope (public.ottoq_owner_charge_limit). 0605 §4 chose this for the demo (Chase 2026-10-02: reset at
--       stop); Chase's 12:35 PM CT decision makes a setting the owner's until the owner changes it.
--   (f) NO OTTO-COMMAND MODEL CALL IS LEDGERED. public.ottoq_model_call_ledger (class evidence) holds nvidia_cuopt,
--       nvidia_nemotron and cpsat_service and no Anthropic row: the owner door's model calls are nowhere (rule 6). Its
--       writer public.ottoq_log_model_call (md5 482dcde3ae386e07da3e8ebcf5188373) is executable by authenticated as well
--       as service_role: a finding reported, not changed here.
--   (g) THE SETTINGS TABLE HAS NO GUARD OF ITS OWN. Only postgres holds privileges on ottoq_owner_settings (RLS on, no
--       policy), and the three writers above are the only functions that write it. But postgres is also the SQL editor and
--       the Management API, and a row written there needs no command: the commands table refuses edits by trigger, the
--       settings table refused nothing.
--   (h) THE DEMO PASSCODE READS PRODUCTION. ottoq_agent_public_call (md5 222ec84d178ea9063e820347b71a9c3f) issues a
--       session whatever run is live, and a session's reads (my_fleet, whoami, ...) are served on a production run: 0721's
--       gate refuses only its changes there.
--
--   §14 (read-only on the live catalog, 2026-10-14 between 20:09:44 and 20:14:17 UTC, 3:09-3:14 PM CT, two queries' own now()):
--   (i) A SAVED SETTING COULD NOT BE SAVED WITH NO RUN LIVE. The owner command answered no_live_demo before it planned
--       anything, so an owner's charge limit or every-return order, which §9 makes the car's from run to run, could be set
--       only while a demo or production run was live. ottoq_owner_commands.sim_run_id is nullable evidence (0605, class
--       'evidence', no FK); ottoq_owner_settings.sim_run_id is NOT NULL (class 'engine'), so a command with no run can
--       write the saved table only. 0605's ottoq_owner_commands_mode_outcome_check admits applied, no_change and refused
--       for an apply; the one command with no run is the 2026-10-04 smoke test's refusal (1 row, outcome refused), so no
--       preview yet has no run and a binding by "no run" cannot meet an old row. Seven functions read
--       ottoq_owner_commands; the two cockpit boards (ottoq_owner_board md5 84e756310bb785ea99bd434662fba37d,
--       ottoq_depot_owner_board md5 deb3c6e8b686ac79a6419099314fb3ae) list every command but previews, show a
--       confirmation code for outcome 'applied' only, and mark a command live_run when its run IS NOT DISTINCT FROM the
--       live one.

-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   THREE COLUMNS on ottoq_owner_commands (class evidence in the run-scope registry: none is a run key, so check (a) has
--   nothing to register; V4 asserts the registry stays clean):
--     acting_person        the email of the OTTOYARD account behind an agent signed in through 0700, when that account is
--                          still linked and active and owns the agent's fleet; NULL for a passcode session or an issued key.
--     via                  who formed the command, set by the database from the gateway's transport and the binding (c
--                          below), never taken from an argument. NULL on rows written before this file (never backfilled).
--                            ottocommand  an OTTO-Command model read the owner's words and called the tool (transport
--                                         'ask': POST /v1/ask or the MCP tool ask_ottocommand, sent with text);
--                            confirm      the agent confirmed a recorded preview: the apply bound to it, and the row
--                                         names it in confirms_command_id. No model is involved, whether the confirm went
--                                         through the confirm door of POST /v1/ask or ask_ottocommand (transport
--                                         'confirm', which applyConfirms in ottocommand_owner.ts always uses) or as a
--                                         typed tool naming the preview;
--                            direct       the agent itself made the call (a typed tool over MCP or REST, or a confirm
--                                         object that bound to no preview and is recorded as a new one), or any other
--                                         caller.
--     confirms_command_id  the preview an apply confirmed (c below). A unique index: one preview confirms one apply.
--   All three join the immutability guard (ottoq_owner_commands_guard, md5 758eff5a6a274b176573c6674840dc55). Two CHECKs
--   make via 'confirm' and confirms_command_id one fact: a row that names a preview is an apply that applied (or changed
--   nothing) recorded as 'confirm', and a 'confirm' row always names one. A BEFORE INSERT backstop
--   (ottoq_owner_commands_backstop_trg) refuses, whoever writes the row, an APPLIED command on a production_live run
--   with no acting_person (rule 10), and a confirms_command_id that is not a preview by the same principal, on the same
--   run, of the same tool and plan hash, made at most 15 minutes before the apply.
--
--   THREE FUNCTIONS (and the backstop's trigger function)
--     ottoq_owner_acting_person(principal)  the person, as above (one primary-key probe per table).
--     ottoq_owner_confirm_binding(...)      is this apply the confirm of a recorded preview (c below), and if not, why.
--     ottoq_owner_write_gate(principal, run) may this agent change settings on this run, and under whose name:
--         operator_demo run                       allowed, as before (person stamped when there is one)
--         production_live run, a person           allowed, recorded under that person
--         production_live run, no person          refused production_needs_a_person, with why for each kind of
--                                                 credential and what to do (sign in; reading works as it is)
--         no run, or any other run                refused no_live_demo, the 0605 words unchanged
--
--   ottoq_owner_command GAINS ITS DOOR AND THE BINDING. The body moves, by anchored substitution of the live definition
--   (each anchor asserted to occur exactly once), to a four-argument form ottoq_owner_command(principal, tool, args, p_via):
--     a. the 0605 demo-only refusal is replaced by the gate's answer;
--     b. a command that LOWERS how full a car charges is marked: set_charge_limit below the limit in force, or an
--        undo_command that puts back a lower limit than the one in force;
--     c. THE BINDING. An apply must be the confirm of a recorded preview when (i) it lowers a limit on a production run,
--        (ii) it came through the confirm door (transport 'confirm'), or (iii) it names a preview (the new argument
--        confirms_command_id). It names its preview by expect_plan_hash and/or confirms_command_id, and binds only to an
--        ottoq_owner_commands row with outcome 'previewed', made by the SAME principal, on the same sim_run_id, of the
--        same tool and arguments (mode, note and the words of a hold's time aside), with the same plan_hash, created at
--        most 15 minutes ago, and not already confirmed. The apply records that row as confirms_command_id, and via
--        'confirm'. An apply that must bind and does not is NOT applied: it is recorded as a preview (mode 'preview',
--        outcome 'previewed', its own plan_hash and command id) and answered 422 confirm_required, with the reason
--        (not_named, no_recorded_preview, not_a_preview, preview_already_confirmed, preview_expired,
--        preview_does_not_match) and that preview's confirm object, so the next confirm can bind to it. A stale hash is
--        still plan_changed (0605). Raising or clearing a limit, holds, service orders, cancelling the owner's own
--        unstarted orders and an undo that does not lower a limit stay one call, as does any change on a demo run sent
--        as a typed tool that names no preview (0605 unchanged). A call through transport 'ask' that carries
--        expect_plan_hash or confirms_command_id is refused confirm_not_through_ottocommand: an OTTO-Command model never
--        confirms (the gateway strips both from what the model may send);
--     d. every command row records acting_person and via, and an applied confirm its confirms_command_id;
--     e. the receipt says "until the production run ends" on a production run.
--   The three-argument form is kept as a one-line delegate (via 'direct') for any direct caller. ottoq_agent_call
--   (md5 ae935f897ee25b6db3eacfbb9215797d) admits 'confirm' as a transport, passes its transport on, and answers a
--   confirm_required preview 422. The receipt (ottoq_owner_command_reply, md5 bd0c86d127a2a84903fa2fb812ee1ac5) shows
--   acting_person, via and confirms_command_id and the run's own end, and a preview's confirm object names the preview
--   (confirms_command_id). whoami (ottoq_agent_read_whoami, md5 53aa8a6690ecc6274e4cd1dc73972006) adds
--   live_production_run and the gate's answer as `changes`, so OTTO-Command knows before it acts.
--
--   WHAT OTTO-Q ENFORCES, AND WHAT IT CANNOT. It enforces preview-then-confirm by the same signed-in principal within 15
--   minutes, one apply per preview, recorded under the person that principal is signed in as. It cannot see a person's
--   yes: the confirm is relayed by the person's own agent, which holds the same token that made the preview, so an agent
--   that previews and confirms on its own reads here exactly like one that asked its person in between. A person-only
--   surface would close that: the confirm taken in the owner's own OTTOYARD account session (auth.uid()), as 0700
--   already does for approving a device sign-in. It is NOT built here, and is an open option for Chase.
--
--   Writes stay in the owner tables. Nothing here calls ottoq_policy_set or writes a setting: an owner's requirement is
--   the owner's (rule 9), applied at OTTO-Q's tick. No command can skip, defer or shorten a service OTTO-Q found needed:
--   cancel_service is 0605's, unchanged, and takes off only the owner's own orders (an engine-found need stays, a
--   started service finishes). Production still never self-tunes (rule 10): no agent writes a setting there, and every
--   owner change in production is recorded under the person whose agent made it.
--
--   §9 WHAT A SIGNED-IN OWNER SETS IS SAVED TO THE CAR. A new table, public.ottoq_owner_saved_settings (no run key, so
--     the purge never reaches it; RLS on, no grants; guarded), holds per car a charge limit or an every-return order made
--     by an applied command recorded under a person. Saving is a BEFORE INSERT trigger on ottoq_owner_settings (the
--     owner command's body is not changed for it); a person's replace, clear, cancel or undo ends or restores the saved
--     row (AFTER UPDATE OF status). Every new demo or production run at the depot (INSERT, or a status change to running
--     or paused) carries each saved row onto the run as an ordinary ottoq_owner_settings row naming it (saved_id), once,
--     inside the contract in force; the engine's readers are unchanged. The run's end lifts it from the run and no longer
--     stamps its command lifted. WHAT IS PER-RUN BY DESIGN: a hold (a time on that run's clock), a one-time order (now,
--     next_return: consumed when served, lifted with the run if not), and anything set through a passcode session or an
--     issued key (no person). Because a signed-in owner's lower limit is now carried into production, it is confirmed
--     the way production confirms one, on every run: preview, then the same principal's confirm within 15 minutes (the
--     binding's condition becomes "lowers AND (production OR a person)"; the gate says lower_limit_needs_preview). Undo
--     works on the run a command was made on; on a later run it says the setting is saved and how to change it
--     (made_on_an_earlier_run). my_settings adds `saved`. A person's command decides what is saved to the cars it names
--     WHATEVER ROW THE RUN HOLDS (the re-review): a clear, a limit at the ceiling and a cancel end the saved row, and a
--     limit saves itself, even where the run's own row is not the saved one (a passcode session or an issued key replaced
--     or withdrew it) or there is none (the carry skipped it for the contract). There the saved change is an effect of its
--     own (key saved:charge_limit or saved:service:<svc>, public.ottoq_owner_saved_effect): shown in the receipt, hashed
--     into the plan, so the outcome is applied rather than no_change, and applied after the run's writes under the
--     person's name. Without it a person's clear left a lower limit saved and the next production run carried it back.
--     One known limit: undo reverses what a command set ON ITS RUN, so a saved limit that was the command's only change
--     (the run already held that value) is not reversed by an undo; set the limit again, or clear it.
--   §10 THE OWNER TABLES' OWN GUARD (re-review item 10): BEFORE INSERT/UPDATE/DELETE on ottoq_owner_settings refuses a
--     row that is not what an applied owner command set (on its run, or carried from a row that command saved), an edit
--     of what was set, a status change no command, tick or run end makes, a replace or withdraw by anything but an
--     applied command, and any DELETE but the purge's (ottoq.retention); the saved table gets the same and refuses DELETE
--     and TRUNCATE. ottoq.agent_ledger_unlock opens both, as it opens the commands table.
--   §11 my_settings reads `saved` (public.ottoq_owner_settings_read wraps 0605's ottoq_owner_read, md5 pinned), only for
--     an agent signed in to an OTTOYARD account: a demo passcode session or an issued key gets no `saved` block and no line
--     about it, and who saved a row and its command are shown only to that same person (the re-review: a passcode session
--     read the account holder's email here).
--   §12 THE PASSCODE DOOR IN PRODUCTION (re-review item 11): enter_passcode refuses to issue a session while a
--     production_live run is running or paused at the depot (403 production_live, before the passcode is checked), and
--     the dispatcher refuses every call of a passcode session for as long as one is (403 production_live, ledgered). No
--     change to sign-up, OAuth, keys or any grant.
--   §13 THE MODEL LEDGER: public.ottoq_ottocommand_record_model_call(jsonb), service_role only, records one OTTO-Command
--     model call through ottoq_log_model_call as provider anthropic_ottocommand, role owner_agent: ids, counts, codes and
--     the model's name, every field validated and unknown fields refused, so no prompt, answer or thinking is stored.
--   §14 WITH NO RUN LIVE, A SIGNED-IN OWNER STILL SAVES TO THE CARS. ottoq_owner_write_gate answers a person with no run
--     live as allowed, run_kind 'none', saved_only (whoami's `changes` says so): set_charge_limit (set, change, at the
--     ceiling), clear_charge_limit, request_service with when every_return, and cancel_service (an every-return order saved
--     to the car) are planned against what is saved to the car (ottoq_owner_saved_effect: every change a saved: effect, a
--     limit already saved or none to clear a no_change) and write ottoq_owner_saved_settings ONLY, never a run's settings;
--     a hold, a one-time order and an undo are refused needs_a_live_run with why. The command is recorded in
--     ottoq_owner_commands with sim_run_id NULL, its person and door, and the new outcome 'saved' (0605's CHECK replaced by
--     the same CHECK admitting it; ottoq_owner_commands_saved_check: a 'saved' row has no run and a person); a no_change
--     stays no_change. A lowering is confirmed as everywhere else for a person: preview, then the same principal's confirm
--     within 15 minutes, the binding now keyed by run IS NOT DISTINCT FROM, so a preview with no run binds only with no
--     run live (a run starting in between changes the plan hash: plan_changed). The receipt says it applies from the next
--     demo or production run, the dispatcher answers 201 as for an applied command, and the guards admit a 'saved' command
--     where they admit an applied one (the saved table's insert and end, and the carry of its row onto a run). The next
--     operator_demo or production_live run carries it exactly as it carries any saved row (§9, unchanged). An undo of a
--     'saved' command on a later run is refused made_with_no_run_live, with what to do instead. A passcode session or an
--     issued key with no run live is refused no_live_demo, 0605's words, with a hint that it names no person.
--
--   THE GATEWAY'S HALF (TypeScript, committed beside this file, not deployed): edge-functions/_shared/ottocommand_owner.ts
--   replays every assistant turn verbatim (thinking, server_tool_use, web_search_tool_result, cited text, tool_use,
--   fallback blocks), resumes a paused turn (pause_turn, at most 3, inside the 50 s budget), answers a model refusal as a
--   plain failure with no tool run, sets output_config.effort explicitly (OTTOCOMMAND_EFFORT, default low), max_tokens
--   8000, the server-side fallback on the models that take it, and a default model when the deployment names none
--   (OTTOCOMMAND_OWNER_MODEL overrides, else ANTHROPIC_MODEL, which the gateway deployed on 2026-10-04 reads, so a
--   deployment that sets only it keeps its model); treats outcome 'saved' as a change made (§14); offers the web search server tool (max_uses 3 per model call, the API's own
--   per-request cap, so an ask's total is at most 3 x its model calls, at most 9, inside the 50 s budget;
--   OTTOCOMMAND_WEB_SEARCH=off disables it, OTTOCOMMAND_WEB_MAX_USES 1..5, located at the depot); refuses in code every
--   change after a web result has entered an ask (a web_search_tool_result, or any result of the code execution dynamic
--   filtering runs over the pages; an ask that read the web returns no confirm objects, names no refused change's
--   arguments, and ships no model text that claims a change); returns cited sources (URLs in the answer, titles only in
--   the sources list, cleaned and capped); adds the read-only
--   MCP tool ottocommand_search and POST /v1/search (scope ottoq | web | both: reads and the web only, never a command);
--   and records each model call through §13, fire-and-forget. edge-functions/_shared/agent_gateway.ts carries the catalog
--   entries, routes and the ledger writer; ottoq-agent-gateway/index.ts reads the configuration.

-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════
--
--   Every body this file replaces is the agent door (ottoq_agent_call, ottoq_owner_command, its receipt, whoami) or a
--   trigger on ottoq_owner_commands. No certification, dial or sweep arm calls any of them, and the engine's readers of
--   owner settings (ottoq_effective_target_soc_at, ottoq_departure_clear, ottoq_owner_departure_blocked,
--   ottoq.ottoq_owner_orders_tick, both world steps) are untouched. Does changing WHO may write owner settings change a
--   certified run? No: a certification run has no owner commands. Its arms are cert_harness / ab_harness runs that the
--   gate refuses; they run in one uncommitted transaction no agent's session can see; and every test-day runner refuses
--   to start while ANY run is running or paused, with no run_by predicate (read live today: cron 746, the recert runner,
--   "IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN RETURN"; the same guard in
--   ottoq_dial_experiment_runner, ottoq_dial_pair, ottoq_throughput_sweep_arm and ottoq_throughput_sweep_runner). So a
--   setting on a production_live run is never in force while an arm runs, exactly 0605 §1(g)'s argument for demo runs.
--   §9-§13 change the same answer nowhere: the run-start triggers have WHEN run_by IN ('operator_demo','production_live')
--   (no arm has either), so they never execute in an arm's transaction; the lift's patch changes only which commands get
--   lifted_at stamped, and returns at its first line on a run with no owner settings (every arm); the guards and the save
--   triggers fire only on writes to the owner tables, which no arm makes; the passcode door and the ledger function are
--   agent doors. The engine's readers of owner settings remain untouched. §14 writes no run's rows at all: a 'saved'
--   command writes only the saved table, which a run sees only through the carry above.
--
-- ══ §4 WHAT IT DELIBERATELY DOES NOT DO ═════════════════════════════════════════════════════════════════════════════
--
--   * No persistence for what has no person behind it: a passcode session's or an issued key's settings, holds and
--     one-time orders lift when their run ends, as 0605 §4 decided (§9 says why each). An unserved one-time order is not
--     carried to the next run (an open option). With no run live (§14) only a signed-in owner's charge limit and
--     every-return orders can be saved; a hold, a one-time order and an undo still need a run.
--   * The two cockpit boards (0606/0608, live, not patched here) list a 'saved' command with its outcome and summary but no
--     confirmation code (they give one to 'applied' only, so the receipt of a 'saved' command carries none either, and the
--     codes the owner sees always match the boards), and mark it live_run while no run is live, as they already mark the
--     2026-10-04 smoke test's refusal; patching them is two more live bodies, left for the cockpit's own file.
--   * A saved setting made while two runs are live is carried onto the other at its next start, not at once.
--   * No new credential, and passcode sessions and issued keys keep working on demo runs exactly as before (and open
--     nothing while a production run is live, §12).
--   * ottoq_log_model_call keeps its live grant to authenticated (§1(f)): narrowing it is a separate decision, recorded as
--     FINDINGS G442 (OPEN; a signed-in caller can append a row of its own choosing, any provider, status, proposal count
--     and detail, to the append-only evidence ledger; remedy: the 0701 family's grant census, db/checks/0438 (4)).
--   * No shield probe on owner writes (the inventory's item 7): the contract checks and the gate are the owner door's.
--   * The cockpit chat seat (ottoq-ottocommand, finding S-03) is not touched.
--
-- ══ §5 VALIDATED ON A SCRATCH CLUSTER ═══════════════════════════════════════════════════════════════════════════════
--
--   tests/test_ottocommand_executor_sql.py builds the stub engine with 0559, 0560, 0605-0608 and 0700 applied from their
--   files, asserts every body this file reads is byte for byte the live one (md5), reproduces (a)-(d) before this file,
--   applies it, and drives the gate, the binding (unbound, bound once, twice, expired, another principal, a hash with no
--   preview, an undo that lowers), the one-call changes, the doors, the stamps, the guard, the backstop and the grants;
--   and (§9-§13) saving, carrying onto demo and production runs, the run's end, undo across runs, the settings guards,
--   the passcode door in production and the model ledger door, over tests/fixtures/model_call_ledger_stub.sql (the live
--   ledger's bodies, md5-asserted); and (§14) saving with no run live (a limit set, raised, at the ceiling, cleared, and
--   lowered only as a bound confirm; an every-return order saved and withdrawn; a hold, a one-time order and an undo
--   refused; a passcode session and an issued key refused with why), the 'saved' outcome's CHECKs, a preview with no run
--   that a run's start invalidates, and the carry onto the next demo and production runs. V3 below cannot probe §14 on
--   the live catalog (it needs no run live when the file is applied); V1 asserts its bodies.
--
-- ══ §6 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE every definition in ottoq_schema_snapshots WHERE label = '0721_pre' (the three-argument
--   ottoq_owner_command, ottoq_agent_call, ottoq_owner_command_reply, ottoq_agent_read_whoami,
--   ottoq_owner_commands_guard). The four-argument form, ottoq_owner_write_gate, ottoq_owner_acting_person and
--   ottoq_owner_confirm_binding are then unread and may stay. The backstop trigger keeps firing on every INSERT; it is
--   harmless after a rollback, because the restored three-argument body applies nothing on a production run (it refuses
--   every run but a demo run) and writes no confirms_command_id, so neither of the trigger's checks can fire on a row it
--   writes. To remove it: DROP TRIGGER ottoq_owner_commands_backstop_trg ON
--   public.ottoq_owner_commands. The three columns, their CHECKs and the unique index may stay (NULL is their old
--   meaning), but the restored guard no longer holds the columns immutable. DELETE this file's ottoq_cert_lineage row.
--   §9-§13: the snapshot also holds ottoq_tg_lift_owner_settings_on_terminal and ottoq_agent_public_call. Then DROP TRIGGER
--   ottoq_sim_runs_carry_saved_owner_settings and ottoq_sim_runs_carry_saved_owner_settings_on_start ON
--   public.ottoq_sim_runs (nothing is carried any more), and the restored dispatcher no longer reads `saved` or refuses a
--   passcode session in production. The saved table, saved_id, the guards and the ledger function may stay: without the
--   carry nothing reads a saved row, and the guard's rules hold for every writer the restored bodies have. §14: the
--   restored bodies refuse every change with no run live (no_live_demo) and write no 'saved' row; the widened
--   mode/outcome CHECK and ottoq_owner_commands_saved_check stay (a 'saved' row already written must stay valid evidence).
--
-- ══ §7 ORDER: THE GATEWAY FIRST ═════════════════════════════════════════════════════════════════════════════════
--
--   After this file a preview's confirm object carries confirms_command_id. The gateway in this branch accepts that
--   argument and sends a confirm with transport 'confirm'; a gateway built before it refuses an unknown argument
--   (additionalProperties false) and would answer a confirm 400. So deploy ottoq-agent-gateway from this branch first,
--   then apply this file. Against the database before this file the new gateway works as it did: confirms_command_id is
--   an argument the 0605 body never reads, and the 0559 dispatcher ledgers transport 'confirm' as 'other'. Which
--   gateway version is deployed now was not read here. Before this file the gateway's model-ledger call
--   (ottoq_ottocommand_record_model_call) answers 404 from PostgREST: the gateway logs it and the ask is unaffected.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0721 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies this file was written against, and the premises it relies on ──
DO $premises$
DECLARE v_bad text; v_src text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0721_a_signed_in_owner_changes_production_under_their_own_name') THEN
    RAISE EXCEPTION '0721 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0700_an_owner_signs_in_and_connects_their_own_agent') THEN
    RAISE EXCEPTION '0721 P1: 0700 (an owner signs in) is not applied; a person exists only through it';
  END IF;
  -- md5(pg_get_functiondef), read on the live catalog 2026-10-14 and on a scratch cluster with 0559-0608 and 0700
  -- applied from their files over the stub engine: identical, every one
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_agent_call(text,text,jsonb,text,jsonb)',                                  'ae935f897ee25b6db3eacfbb9215797d'),
      ('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)',                 '533b275b976b5287f1f48b245132139f'),
      ('public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)',                'bd0c86d127a2a84903fa2fb812ee1ac5'),
      ('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)',                        '53aa8a6690ecc6274e4cd1dc73972006'),
      ('public.ottoq_owner_commands_guard()',                                                  '758eff5a6a274b176573c6674840dc55')) x(f, want)
   WHERE to_regprocedure(f) IS NULL
      OR md5(pg_get_functiondef(to_regprocedure(f))) IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 P1: not the body this file was written against (re-measure before applying): %', v_bad;
  END IF;
  -- the four reads OTTO-Command now offers an owner's agent (edge-functions/_shared/ottocommand_owner.ts), whose scope
  -- was read in these bodies: depot_status counts only the token's fleet, vehicle_card and recent_decisions keep to it
  -- through ottoq_agent_vehicle_in_scope and a fleet filter, stall_availability carries no vehicle id, name or owner.
  -- A change to any of them is a reason to read its scope again before OTTO-Command reads it for an owner.
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_agent_read_depot(public.ottoq_agent_principals)',                         '9c3ef3ebfdfc1452d430e922aedd6370'),
      ('public.ottoq_agent_read_vehicle(public.ottoq_agent_principals,jsonb)',                 'a19d1d66275fd3e459fb3ec4263634e5'),
      ('public.ottoq_agent_read_decisions(public.ottoq_agent_principals,jsonb)',               '7d1f7e652d8c840b95b52286d78cbae4'),
      ('public.ottoq_agent_read_stalls(public.ottoq_agent_principals,jsonb)',                  '17156c4b0f42b11af1ec3d0e9d511b03'),
      ('public.ottoq_agent_vehicle_in_scope(public.ottoq_agent_principals,uuid)',              '339598e6cad0c62d1d62aabdde5ded52')) x(f, want)
   WHERE to_regprocedure(f) IS NULL
      OR md5(pg_get_functiondef(to_regprocedure(f))) IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 P1: a read OTTO-Command offers is not the body whose scope was read: %', v_bad;
  END IF;
  -- production applies what an owner sets (0718): otherwise a production command accepted here would be a placebo
  v_src := (SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g')
              FROM pg_proc p WHERE p.oid = to_regprocedure('twin.ottoq_world_advance()'));
  IF v_src IS NULL OR strpos(v_src, 'ottoq.ottoq_owner_orders_tick(v_run.sim_run_id') = 0
     OR v_src !~ 'run_by\s*=\s*''production_live''' THEN
    RAISE EXCEPTION '0721 P1: production''s world step does not apply owner settings on a production_live run (0718)';
  END IF;
  IF to_regclass('public.ottoq_oauth_grants') IS NULL OR to_regclass('public.ottoq_owner_accounts') IS NULL THEN
    RAISE EXCEPTION '0721 P1: 0700''s grants or accounts table is missing';
  END IF;
  -- §9-§13: the bodies the saved settings, the passcode door and the model ledger patch or call, read on the live
  -- catalog 2026-10-14 between 17:59 and 18:17 UTC (12:59-1:17 PM CT) and identical on the scratch chain
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_tg_lift_owner_settings_on_terminal()',                                    'e7d0a3f35a057175f7de8ffc88c98b99'),
      ('public.ottoq_agent_public_call(text,jsonb,text,jsonb,timestamp with time zone)',      '222ec84d178ea9063e820347b71a9c3f'),
      ('public.ottoq_owner_read(public.ottoq_agent_principals,text,jsonb)',                    '69bd022e5af9e79fc6f15d5de21edc8f'),
      ('public.ottoq_log_model_call(text,text,text,uuid,uuid,bigint,timestamp with time zone,text,text,text,integer,integer,integer,boolean,jsonb,text)',
                                                                                                '482dcde3ae386e07da3e8ebcf5188373')) x(f, want)
   WHERE to_regprocedure(f) IS NULL
      OR md5(pg_get_functiondef(to_regprocedure(f))) IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 P1: not the body §9-§13 were written against (re-measure before applying): %', v_bad;
  END IF;
  IF to_regclass('public.ottoq_model_call_ledger') IS NULL OR to_regprocedure('public.ottoq_agent_no_truncate()') IS NULL THEN
    RAISE EXCEPTION '0721 P1: the model call ledger (0340) or the no-truncate guard (0559) is missing';
  END IF;
  -- §9: the owner settings table is the engine-class, run-keyed table 0605 made, and nothing writes it but the three
  -- functions §1(g) names (a fourth writer would have to learn the saved settings and the guard)
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_name = 'ottoq_owner_settings' AND column_name = 'sim_run_id' AND class = 'engine') THEN
    RAISE EXCEPTION '0721 P1: ottoq_owner_settings is not registered as engine data on sim_run_id';
  END IF;
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY 1) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin')
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g')
         ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?ottoq_owner_settings\M'
     AND p.proname NOT IN ('ottoq_owner_command', 'ottoq_tg_lift_owner_settings_on_terminal', 'ottoq_owner_orders_tick');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 P1: a writer of ottoq_owner_settings this file does not know: %', v_bad;
  END IF;
  -- §14: the outcomes 0605's CHECK admits, read on the live catalog 2026-10-14 20:09:44 UTC (3:09 PM CT), which this file
  -- replaces by the same CHECK admitting 'saved'
  IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
       WHERE c.conrelid = 'public.ottoq_owner_commands'::regclass AND c.conname = 'ottoq_owner_commands_mode_outcome_check')
     IS DISTINCT FROM 'CHECK ((((mode = ''preview''::text) AND (outcome = ANY (ARRAY[''previewed''::text, ''refused''::text]))) OR ((mode = ''apply''::text) AND (outcome = ANY (ARRAY[''applied''::text, ''no_change''::text, ''refused''::text])))))' THEN
    RAISE EXCEPTION '0721 P1: ottoq_owner_commands_mode_outcome_check is not 0605''s CHECK this file replaces';
  END IF;
  -- §14: a no-run preview binds by "no run" (IS NOT DISTINCT FROM), so no recorded preview or apply may already have no run
  -- (read live at the same moment: the one command with no run is the 2026-10-04 smoke test's refusal)
  IF EXISTS (SELECT 1 FROM public.ottoq_owner_commands c WHERE c.sim_run_id IS NULL AND c.outcome <> 'refused') THEN
    RAISE EXCEPTION '0721 P1: an owner command with no run that is not a refusal already exists';
  END IF;
END $premises$;

-- ── P2: nothing this file creates exists yet, and the registry guard is clean before it is touched ──
DO $fresh$
DECLARE v_block int;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'ottoq_owner_commands'
                AND column_name IN ('acting_person', 'via', 'confirms_command_id')) THEN
    RAISE EXCEPTION '0721 P2: ottoq_owner_commands already has acting_person, via or confirms_command_id';
  END IF;
  IF to_regclass('public.ottoq_owner_commands_confirms_idx') IS NOT NULL THEN
    RAISE EXCEPTION '0721 P2: the index ottoq_owner_commands_confirms_idx already exists';
  END IF;
  IF to_regclass('public.ottoq_owner_saved_settings') IS NOT NULL
     OR EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'ottoq_owner_settings' AND column_name = 'saved_id')
     OR to_regprocedure('public.ottoq_owner_saved_carry(uuid)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_saved_effect(public.vehicles,text,text,numeric,numeric)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_settings_guard()') IS NOT NULL
     OR to_regprocedure('public.ottoq_ottocommand_record_model_call(jsonb)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.ottoq_owner_commands'::regclass
                   AND conname = 'ottoq_owner_commands_saved_check') THEN
    RAISE EXCEPTION '0721 P2: the saved settings, their guard, the saved outcome''s CHECK or the model ledger door already exist';
  END IF;
  IF to_regprocedure('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb,text)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_write_gate(public.ottoq_agent_principals,jsonb)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_acting_person(public.ottoq_agent_principals)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_confirm_binding(public.ottoq_agent_principals,uuid,text,jsonb,text,text,uuid,boolean)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_commands_backstop()') IS NOT NULL THEN
    RAISE EXCEPTION '0721 P2: a function this file creates already exists';
  END IF;
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0721 P2: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $fresh$;

-- ── the rollback snapshot of the seven bodies this file replaces ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0721_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure,
                 'public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)'::regprocedure,
                 'public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure,
                 'public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure,
                 'public.ottoq_owner_commands_guard()'::regprocedure,
                 'public.ottoq_tg_lift_owner_settings_on_terminal()'::regprocedure,
                 'public.ottoq_agent_public_call(text,jsonb,text,jsonb,timestamp with time zone)'::regprocedure);

-- ══ 1. the three columns ════════════════════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.ottoq_owner_commands
  ADD COLUMN acting_person text,
  ADD COLUMN via text,
  ADD COLUMN confirms_command_id uuid,
  ADD CONSTRAINT ottoq_owner_commands_confirms_command_id_fkey FOREIGN KEY (confirms_command_id)
    REFERENCES public.ottoq_owner_commands (command_id),
  ADD CONSTRAINT ottoq_owner_commands_acting_person_check CHECK (
    acting_person IS NULL OR (acting_person = lower(btrim(acting_person)) AND acting_person ~ '^[^@[:space:]]+@[^@[:space:]]+$')),
  ADD CONSTRAINT ottoq_owner_commands_via_check CHECK (via IS NULL OR via IN ('ottocommand', 'confirm', 'direct')),
  --: a row that names a preview is an apply that went through (or changed nothing), recorded as a confirm
  ADD CONSTRAINT ottoq_owner_commands_confirms_check CHECK (
    confirms_command_id IS NULL OR (mode = 'apply' AND outcome IN ('applied', 'no_change', 'saved') AND via = 'confirm')),
  --: §14: an apply made while no run is live changes only what is saved to the cars; its outcome is 'saved' (0605's CHECK
  --: is replaced by the same one admitting it), and a 'saved' row has no run and always a person
  DROP CONSTRAINT ottoq_owner_commands_mode_outcome_check,
  ADD CONSTRAINT ottoq_owner_commands_mode_outcome_check CHECK (
       (mode = 'preview' AND outcome IN ('previewed', 'refused'))
    OR (mode = 'apply'   AND outcome IN ('applied', 'no_change', 'refused', 'saved'))),
  ADD CONSTRAINT ottoq_owner_commands_saved_check CHECK (
    outcome IS DISTINCT FROM 'saved' OR (sim_run_id IS NULL AND acting_person IS NOT NULL)),
  --: and a row recorded as a confirm always names the preview it confirmed: via 'confirm' iff confirms_command_id
  ADD CONSTRAINT ottoq_owner_commands_confirm_is_bound_check CHECK (
    via IS DISTINCT FROM 'confirm' OR confirms_command_id IS NOT NULL);

--: one preview confirms one apply
CREATE UNIQUE INDEX ottoq_owner_commands_confirms_idx ON public.ottoq_owner_commands (confirms_command_id)
  WHERE confirms_command_id IS NOT NULL;

COMMENT ON COLUMN public.ottoq_owner_commands.acting_person IS
'0721. The person the command is recorded under: the email of the OTTOYARD account (ottoq_owner_accounts, through ottoq_oauth_grants) behind an agent signed in through 0700, while that account is active and owns the agent''s fleet. NULL for a passcode session or an issued key, which name no one. On a production_live run an applied command always has one (ottoq_owner_commands_backstop_trg). It records whose agent sent the command; OTTO-Q cannot see whether that person said yes.';
COMMENT ON COLUMN public.ottoq_owner_commands.via IS
'0721. Who formed the command, set by the database from the gateway''s transport and the binding, never taken from an argument. ottocommand: an OTTO-Command model read the owner''s words and called the tool with the owner''s own token (transport ask: POST /v1/ask or the MCP tool ask_ottocommand, sent with text). confirm: the agent confirmed a recorded preview: the apply bound to an outcome previewed row the same principal made on the same run in the last 15 minutes, named in confirms_command_id (always set on a confirm row, by CHECK); no model was involved, whether it was sent through the confirm door of /v1/ask and ask_ottocommand (transport confirm) or as a typed tool naming the preview. direct: the agent itself made the call (a typed tool over MCP or REST, or a confirm object that bound to no preview and was recorded as a new preview), or any other caller. OTTO-Q enforces preview-then-confirm by the same signed-in principal within 15 minutes; it cannot see a person''s yes, which the person''s own agent relays. NULL on rows written before 0721; never backfilled.';
COMMENT ON COLUMN public.ottoq_owner_commands.confirms_command_id IS
'0721. The preview this apply confirmed: an outcome previewed row by the same principal, on the same run, of the same tool, arguments and plan_hash, made at most 15 minutes before it and confirmed by no other apply (unique). On a production run every applied lowering of a charge limit has one. OTTO-Q enforces preview-then-confirm by the same principal; the confirm itself is relayed by the person''s agent, and OTTO-Q cannot see the person''s yes.';

-- ══ 1b. what a signed-in owner saves to a car (§9 fills it; created here so the receipt and whoami can read it) ══════
--
-- One row per car and saved setting: a charge limit, or an every-return service order, set by an applied command
-- recorded under a person. It has no run key: it is not run-scoped data, so the run-scope registry has nothing to
-- register and ottoq_purge_prior_runs (which deletes by the registry's engine class) never reaches it. Each run's
-- ottoq_owner_settings rows are still the engine's working set; a saved row is carried onto every new demo or production
-- run at the depot (§9), and names the setting that carried it (ottoq_owner_settings.saved_id).

CREATE TABLE public.ottoq_owner_saved_settings (
  saved_id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  depot_id             uuid NOT NULL,
  fleet_operator_id    uuid NOT NULL,
  vehicle_id           uuid NOT NULL,
  kind                 text NOT NULL,
  charge_limit_pct     numeric,
  service              text,
  --: the applied command that set it, and the person it was recorded under
  command_id           uuid NOT NULL REFERENCES public.ottoq_owner_commands (command_id),
  acting_person        text NOT NULL,
  status               text NOT NULL DEFAULT 'active',
  saved_at             timestamptz NOT NULL DEFAULT now(),
  ended_at             timestamptz,
  ended_reason         text,
  ended_by_command_id  uuid REFERENCES public.ottoq_owner_commands (command_id),
  CONSTRAINT ottoq_owner_saved_settings_kind_check CHECK (
       (kind = 'charge_limit' AND charge_limit_pct BETWEEN 50 AND 100 AND service IS NULL)
    OR (kind = 'service' AND service IS NOT NULL AND charge_limit_pct IS NULL)),
  CONSTRAINT ottoq_owner_saved_settings_status_check CHECK (status IN ('active', 'ended')),
  CONSTRAINT ottoq_owner_saved_settings_ended_check CHECK (
    (status = 'active') = (ended_at IS NULL) AND (ended_at IS NULL) = (ended_reason IS NULL)),
  CONSTRAINT ottoq_owner_saved_settings_person_check CHECK (
    acting_person = lower(btrim(acting_person)) AND acting_person ~ '^[^@[:space:]]+@[^@[:space:]]+$')
);
CREATE UNIQUE INDEX ottoq_owner_saved_settings_one_limit_idx
  ON public.ottoq_owner_saved_settings (vehicle_id) WHERE kind = 'charge_limit' AND status = 'active';
CREATE UNIQUE INDEX ottoq_owner_saved_settings_one_service_idx
  ON public.ottoq_owner_saved_settings (vehicle_id, service) WHERE kind = 'service' AND status = 'active';
CREATE INDEX ottoq_owner_saved_settings_depot_idx ON public.ottoq_owner_saved_settings (depot_id) WHERE status = 'active';
CREATE INDEX ottoq_owner_saved_settings_command_idx ON public.ottoq_owner_saved_settings (command_id);

COMMENT ON TABLE public.ottoq_owner_saved_settings IS
'0721 (Chase 2026-10-14, 12:35 PM CT: a vehicle owner''s settings persist per vehicle, the owner''s by contract until the owner changes them). What an owner signed in to their OTTOYARD account saved to a car: a charge limit, or an every-return service order. Carried onto every new demo or production run at the depot as that run''s ottoq_owner_settings row (ottoq_owner_saved_carry), so the engine reads it exactly as it reads a setting made on the run. Ended only by an applied command recorded under a person (a new limit, a clear, a cancelled order, an undo), and put back by an undo. Holds, one-time orders and anything set through a passcode session or an issued key are not saved: they belong to their run. Not run-scoped (no run key), so no purge reaches it; guarded (ottoq_owner_saved_settings_guard_trg): no row without an applied command that set it, no DELETE, no TRUNCATE.';

ALTER TABLE public.ottoq_owner_settings
  ADD COLUMN saved_id uuid REFERENCES public.ottoq_owner_saved_settings (saved_id);
CREATE INDEX ottoq_owner_settings_saved_idx ON public.ottoq_owner_settings (saved_id) WHERE saved_id IS NOT NULL;
COMMENT ON COLUMN public.ottoq_owner_settings.saved_id IS
'0721. The saved setting (ottoq_owner_saved_settings) this run-scoped row carries: set when a signed-in owner''s command saves it, or when ottoq_owner_saved_carry carries a saved setting onto a new run. NULL for a setting that belongs to its run only (a hold, a one-time order, anything set without a person).';

ALTER TABLE public.ottoq_owner_saved_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ottoq_owner_saved_settings FROM PUBLIC, anon, authenticated, service_role;

--: (§9, the 0721 re-review) one car's change to what is saved to it, as an effect of a signed-in owner's command, for the
--: case the run's own rows do not carry (and, §14, every change a signed-in owner makes while no run is live: p_kind
--: 'every_return' saves an order, and a limit already saved, or none to clear, is an effect that changes nothing): the run's setting was made by a session without a person (it replaced or withdrew
--: the carried one), or the carry skipped the saved setting for the contract. Key 'saved:charge_limit' or
--: 'saved:service:<svc>'; ottoq_owner_command shows it in the receipt, hashes it into the plan and applies it after the run's
--: writes. Without it a person's clear, a limit at the ceiling or a cancel left the saved row in force, and the next run
--: (production included) carried back a lower limit the owner had removed.
CREATE OR REPLACE FUNCTION public.ottoq_owner_saved_effect(p_v public.vehicles, p_kind text, p_service text,
                                                          p_before numeric, p_after numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_name text := COALESCE(p_v.display_name, p_v.id::text);
  v_base jsonb := jsonb_build_object('vehicle_id', p_v.id, 'vehicle', COALESCE(p_v.display_name, p_v.id::text),
                                     'state', p_v.current_state::text, 'soc', p_v.current_soc, 'change', true);
  v_svc  text;
BEGIN
  --: §14 (no run live): a limit already saved, or none to clear, changes nothing
  IF p_kind = 'charge_limit' AND p_before IS NOT DISTINCT FROM p_after THEN
    RETURN v_base || jsonb_build_object('key', 'saved:charge_limit', 'before', p_before, 'after', p_after, 'change', false,
      'group', 'saved_unchanged',
      'group_one', CASE WHEN p_after IS NULL THEN 'has no limit saved to it: it charges full on every run'
                        ELSE format('already has %s%% saved to it', p_after) END,
      'group_many', CASE WHEN p_after IS NULL THEN 'have no limit saved to them: they charge full on every run'
                         ELSE format('already have %s%% saved to them', p_after) END,
      'now', CASE WHEN p_after IS NULL THEN format('%s has no charge limit saved to it, so it charges full on every run; nothing changes.', v_name)
                  ELSE format('%s already has %s%% saved to it for every run; nothing changes.', v_name, p_after) END);
  END IF;
  IF p_kind = 'charge_limit' AND p_after IS NOT NULL THEN
    RETURN v_base || jsonb_build_object('key', 'saved:charge_limit', 'before', p_before, 'after', p_after,
      'group', 'saved_limit_' || p_after,
      'group_one', format('has %s%% saved to it for every run', p_after),
      'group_many', format('have %s%% saved to them for every run', p_after),
      'now', format('%s: %s%% is saved to it for every run%s.', v_name, p_after,
                    CASE WHEN p_before IS NULL THEN '' ELSE format(', in place of %s%%', p_before) END));
  ELSIF p_kind = 'charge_limit' THEN
    RETURN v_base || jsonb_build_object('key', 'saved:charge_limit', 'before', p_before, 'after', NULL,
      'group', 'saved_cleared',
      'group_one', 'has the limit saved to it cleared: it charges full on every run',
      'group_many', 'have the limits saved to them cleared: they charge full on every run',
      'now', format('%s: the %s%% limit saved to it is cleared, so it charges full on every run.', v_name, p_before));
  END IF;
  SELECT c.display_name INTO v_svc FROM public.service_cadence_policy c WHERE c.svc = p_service;
  --: §14 (no run live): an every-return order saved to the car, unless it already has one for that service
  IF p_kind = 'every_return' THEN
    IF EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings s
                WHERE s.vehicle_id = p_v.id AND s.kind = 'service' AND s.service = p_service AND s.status = 'active') THEN
      RETURN v_base || jsonb_build_object('key', 'saved:service:' || p_service, 'service', p_service,
        'before', 'every_return', 'after', 'every_return', 'change', false,
        'group', 'saved_already_ordered',
        'group_one', 'already has it saved to it for every return', 'group_many', 'already have it saved to them for every return',
        'now', format('%s already has %s on every return saved to it; nothing changes.', v_name,
                      public.ottoq_owner_lc(COALESCE(v_svc, p_service))));
    END IF;
    RETURN v_base || jsonb_build_object('key', 'saved:service:' || p_service, 'service', p_service,
      'before', NULL, 'after', 'every_return',
      'group', 'saved_ordered',
      'group_one', 'has it saved to it: it gets it on every return, from the next run on',
      'group_many', 'have it saved to them: they get it on every return, from the next run on',
      'now', format('%s: %s on every return is saved to it, from the next demo or production run on.', v_name,
                    public.ottoq_owner_lc(COALESCE(v_svc, p_service))));
  END IF;
  RETURN v_base || jsonb_build_object('key', 'saved:service:' || p_service, 'service', p_service,
    'before', 'every_return', 'after', NULL,
    'group', 'saved_withdrawn',
    'group_one', 'has the every-return order saved to it withdrawn, for every run',
    'group_many', 'have the every-return orders saved to them withdrawn, for every run',
    'now', format('%s: the every-return order for %s saved to it is withdrawn, for every run.', v_name,
                  public.ottoq_owner_lc(COALESCE(v_svc, p_service))));
END $fn$;
REVOKE ALL ON FUNCTION public.ottoq_owner_saved_effect(public.vehicles, text, text, numeric, numeric)
  FROM PUBLIC, anon, authenticated, service_role;

-- ══ 2. who the person is, and whether this agent may change settings on this run ═══════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_owner_acting_person(p_agent public.ottoq_agent_principals)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  -- 0721. The person behind an agent: the OTTOYARD account an agent signed in through (0700), only while the account is
  -- active and owns the agent's fleet at the agent's depot. A passcode session or an issued key names no one: NULL.
  SELECT a.email
    FROM public.ottoq_oauth_grants g
    JOIN public.ottoq_owner_accounts a ON a.account_id = g.account_id
   WHERE p_agent.origin = 'oauth' AND p_agent.status = 'active'
     AND g.principal_id = p_agent.principal_id
     AND a.status = 'active'
     AND a.fleet_operator_id = p_agent.fleet_operator_id
     AND a.depot_id = p_agent.depot_id
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_write_gate(p_agent public.ottoq_agent_principals, p_run jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721. May this agent change its own cars' settings on this run (p_run: ottoq_agent_live_run's answer), and under
   whose name. A demo run, as 0605 allowed. A production run only for an agent signed in to its owner's OTTOYARD account,
   so that every production change is recorded under a person (CLAUDE.md rule 10). No run (§14): only that signed-in
   owner, and only to save a charge limit or an every-return order to the cars (run_kind 'none', saved_only). Wherever a person is recorded, what
   they set is saved to the car (§9), and a lower charge limit is applied only as the confirm of a preview the same agent
   recorded in the last 15 minutes (rule 9). Every refusal says why and what to do instead. Read by ottoq_owner_command
   and by whoami, so OTTO-Command knows before it acts. */
DECLARE
  v_person text := public.ottoq_owner_acting_person(p_agent);
  v_kind   text := CASE WHEN p_run IS NULL THEN NULL
                        WHEN p_run ->> 'run_by' = 'operator_demo' THEN 'demo'
                        WHEN p_run ->> 'run_by' = 'production_live' THEN 'production'
                        ELSE 'other' END;
BEGIN
  IF v_kind = 'demo' AND v_person IS NULL THEN
    RETURN jsonb_build_object('allowed', true, 'run_kind', 'demo',
      'message', 'A demo run is live: settings apply to it and lift when it ends.');
  ELSIF v_kind = 'demo' THEN
    --: §9: what a signed-in owner sets is saved to the car and carried into production, so a lower limit is confirmed
    --: here the way production confirms one
    RETURN jsonb_build_object('allowed', true, 'run_kind', 'demo', 'person', v_person, 'saved', true,
      'lower_limit_needs_preview', true, 'confirm_window_minutes', 15,
      'message', format('A demo run is live. You are signed in as %s, so a charge limit or an every-return service you set is saved to your cars and stays from run to run, production included, until you change it; holds and one-time orders last until the run ends. A lower charge limit (or an undo that puts one back) applies only as the confirm of a preview this agent recorded in the last 15 minutes. Everything else is one call.', v_person));
  ELSIF v_kind = 'production' AND v_person IS NOT NULL THEN
    RETURN jsonb_build_object('allowed', true, 'run_kind', 'production', 'person', v_person, 'saved', true,
      'lower_limit_needs_preview', true, 'confirm_window_minutes', 15,
      'message', format('A production run is live. Changes are recorded under %s. A charge limit or an every-return service is saved to your cars and stays from run to run until you change it; holds and one-time orders last until the run ends. Lowering how full a car charges (a lower limit, or an undo that puts one back) applies only as the confirm of a preview this agent recorded in the last 15 minutes; an apply that names no such preview is recorded as a preview and answered confirm_required. Everything else is one call.', v_person));
  ELSIF v_kind = 'production' THEN
    RETURN jsonb_build_object('allowed', false, 'run_kind', 'production', 'code', 'production_needs_a_person',
      'message', CASE p_agent.origin
        WHEN 'passcode' THEN 'The live run at the twin depot is a production run, and a passcode session can read your cars there but not change them: in production every change is recorded under the person who made it, and a passcode names no one.'
        WHEN 'oauth'    THEN 'The live run at the twin depot is a production run, and the OTTOYARD account this agent signed in with is not linked to this fleet, so there is no person to record the change under.'
        ELSE 'The live run at the twin depot is a production run, and an issued key names no person: in production every change is recorded under the person who made it.' END,
      'hint', 'Sign your agent in to your OTTOYARD account (PERSONAL_AGENT.md section 10) and send it again. Reading your cars works as it is.');
  ELSIF v_kind IS NULL AND v_person IS NOT NULL THEN
    --: §14: with no run live a signed-in owner still saves to the cars (a charge limit, or an every-return order): it is
    --: recorded under the person and carried onto the next demo or production run. Nothing else is a change with no run.
    RETURN jsonb_build_object('allowed', true, 'run_kind', 'none', 'person', v_person, 'saved', true, 'saved_only', true,
      'lower_limit_needs_preview', true, 'confirm_window_minutes', 15,
      'message', format('No run is live at the twin depot. You are signed in as %s, so you can still save a charge limit (set, change or clear it) or an every-return service order (or withdraw one) to your cars: it is recorded under you, carried onto the next demo or production run, and stays from run to run until you change it. A lower charge limit applies only as the confirm of a preview this agent recorded in the last 15 minutes. Holds, one-time orders and undo need a live run.', v_person));
  ELSIF v_kind IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'code', 'no_live_demo',
      'message', 'No demo run is live at the twin depot. Start one in OTTO-TWIN; what you set applies to that run and resets when it ends.',
      --: §14: and why it cannot save to the cars instead: nothing names a person
      'hint', CASE p_agent.origin
        WHEN 'passcode' THEN 'A passcode session names no person, so it cannot save a setting to your cars while no run is live. To save a charge limit or an every-return order now, sign your agent in to your OTTOYARD account (PERSONAL_AGENT.md section 10).'
        WHEN 'oauth'    THEN 'The OTTOYARD account this agent signed in with is not linked to this fleet, so there is no person to save a setting under while no run is live.'
        ELSE 'An issued key names no person, so it cannot save a setting to your cars while no run is live. To save a charge limit or an every-return order now, sign your agent in to your OTTOYARD account (PERSONAL_AGENT.md section 10).' END);
  END IF;
  RETURN jsonb_build_object('allowed', false, 'run_kind', 'other', 'code', 'no_live_demo',
    'message', 'The live run at the twin depot is not a demo run, and owner settings apply only to demo runs.');
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_confirm_binding(p_agent public.ottoq_agent_principals, p_run uuid, p_tool text,
                                                              p_args jsonb, p_hash text, p_expect text, p_confirms uuid,
                                                              p_lowering boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721 (CLAUDE.md rule 9). Is this apply the confirm of a preview OTTO-Q recorded? It binds only to a row with outcome
   'previewed' made by the SAME principal, on the same run (§14: or, made while no run was live, with none live now), of
   the same tool and arguments (mode, note and the words of a
   hold's time aside: its resolved until_sim stays in), with the same plan hash, created at most 15 minutes ago and
   confirmed by no apply yet. The apply names it by p_expect (the plan hash) and/or p_confirms (its command_id); naming
   neither binds nothing. Answers {"bound": <command_id>} (the preview row is locked until the apply commits; the unique
   index ottoq_owner_commands_confirms_idx refuses a second apply that raced it), or confirm_required with the reason and
   what to do. Called by ottoq_owner_command only; no client role reaches it.
   What it cannot know is whether a person said yes: the confirm comes from the person's agent, with the token that made
   the preview. A person-only surface (the OTTOYARD account session) is not built. */
DECLARE
  v_bound uuid;
  v_named public.ottoq_owner_commands;
  v_why   text;
  v_prod  boolean := EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run AND r.run_by = 'production_live');
BEGIN
  IF p_expect IS NULL AND p_confirms IS NULL THEN
    v_why := 'not_named';
  ELSE
    SELECT p.command_id INTO v_bound
      FROM public.ottoq_owner_commands p
     WHERE p.principal_id = p_agent.principal_id
       AND p.outcome = 'previewed'
       AND p.sim_run_id IS NOT DISTINCT FROM p_run   --: §14: a preview made while no run was live binds only with none live
       AND p.tool = p_tool
       AND p.plan_hash = p_hash
       AND (p_expect IS NULL OR p.plan_hash = p_expect)
       AND (p_confirms IS NULL OR p.command_id = p_confirms)
       AND (p.args - 'mode' - 'note' - 'until' - 'for_minutes') = (p_args - 'mode' - 'note' - 'until' - 'for_minutes')
       AND p.created_at >= now() - interval '15 minutes'
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_commands a WHERE a.confirms_command_id = p.command_id)
     ORDER BY p.created_at DESC, p.command_id
     LIMIT 1
       FOR UPDATE OF p;
    IF v_bound IS NOT NULL THEN
      RETURN jsonb_build_object('bound', v_bound);
    END IF;
    --: why not, in words that name nothing outside this principal's own commands
    IF p_confirms IS NOT NULL THEN
      SELECT * INTO v_named FROM public.ottoq_owner_commands p
       WHERE p.command_id = p_confirms AND p.principal_id = p_agent.principal_id;
    ELSE
      SELECT * INTO v_named FROM public.ottoq_owner_commands p
       WHERE p.principal_id = p_agent.principal_id AND p.outcome = 'previewed' AND p.sim_run_id IS NOT DISTINCT FROM p_run
         AND p.tool = p_tool AND p.plan_hash = p_expect
       ORDER BY p.created_at DESC, p.command_id LIMIT 1;
    END IF;
    v_why := CASE
      WHEN v_named.command_id IS NULL THEN 'no_recorded_preview'
      WHEN v_named.outcome <> 'previewed' THEN 'not_a_preview'
      WHEN EXISTS (SELECT 1 FROM public.ottoq_owner_commands a WHERE a.confirms_command_id = v_named.command_id)
        THEN 'preview_already_confirmed'
      WHEN v_named.created_at < now() - interval '15 minutes' THEN 'preview_expired'
      ELSE 'preview_does_not_match' END;
  END IF;
  RETURN jsonb_build_object('code', 'confirm_required', 'reason', v_why,
    'message', CASE WHEN p_lowering AND v_prod
                    THEN 'This is a production run, so lowering how full a car charges applies only as the confirm of a preview this agent recorded in the last 15 minutes. '
                    WHEN p_lowering
                    THEN 'A lower charge limit you set while signed in is saved to your cars and carried into production, so it applies only as the confirm of a preview this agent recorded in the last 15 minutes. '
                    ELSE 'A confirm applies only a preview this agent recorded in the last 15 minutes. ' END
            || CASE v_why
                 WHEN 'not_named'                 THEN 'This apply named no preview (expect_plan_hash or confirms_command_id). '
                 WHEN 'no_recorded_preview'       THEN CASE WHEN p_run IS NULL THEN 'This agent recorded no such preview while no run was live. '
                                                             ELSE 'This agent recorded no such preview on this run. ' END
                 WHEN 'not_a_preview'             THEN 'The command it names is not a preview. '
                 WHEN 'preview_already_confirmed' THEN 'That preview was already confirmed once, and a preview confirms one apply. '
                 WHEN 'preview_expired'           THEN 'That preview is more than 15 minutes old. '
                 ELSE 'That preview does not match this command (its tool, cars, arguments or plan differ). ' END
            || 'Nothing was applied. It is recorded as a new preview, and confirming that applies it.',
    'hint', 'Show your person the plan. Once they say yes, send the confirm object this answer carries (it names this preview) within 15 minutes, from this same agent. Raising or clearing a limit, holds, service orders and cancelling your own orders need no preview.');
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_owner_acting_person(public.ottoq_agent_principals) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_owner_write_gate(public.ottoq_agent_principals, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_owner_confirm_binding(public.ottoq_agent_principals, uuid, text, jsonb, text, text, uuid, boolean)
  FROM PUBLIC, anon, authenticated, service_role;

-- ══ 3. the owner command learns its door, its person, production and the binding ═══════════════════════════════════
--
-- The live body, by anchored substitution, under a four-argument signature. Every anchor is asserted to occur exactly
-- once in the definition read here; the md5 premise above pins the definition itself.
DO $command$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)'::regprocedure);
  v_new text;
  v_pair text[];
  v_pairs text[][] := ARRAY[
    -- a. the signature: the door the command came through
    ARRAY[E'p_tool text, p_args jsonb)\n RETURNS jsonb\n',
          E'p_tool text, p_args jsonb, p_via text)\n RETURNS jsonb\n'],
    -- b. the declarations
    ARRAY[E'  v_cphrase  text;\nBEGIN\n',
          E'  v_cphrase  text;\n'
       || E'  --: 0721: who may change settings on this run and under whose name, which door (from the transport and the binding,\n'
       || E'  --: never from an argument), whether the command lowers a limit, and the preview an apply confirms\n'
       || E'  v_gate        jsonb;\n'
       || E'  v_production  boolean := false;\n'
       || E'  v_person      text;\n'
       || E'  v_door        text := CASE p_via WHEN ''ask'' THEN ''ottocommand'' ELSE ''direct'' END;   --: a model, or the agent itself\n'
       || E'  v_via         text := v_door;                                    --: ''confirm'' once the apply binds to a preview\n'
       || E'  v_lowers      boolean := false;\n'
       || E'  v_confirms    uuid;\n'
       || E'  v_bind        jsonb;\n'
       || E'  v_bound       uuid;\n'
       || E'  v_confirm_req jsonb;\n'
       || E'  v_sv          public.ottoq_owner_saved_settings;   --: §9: what is saved to a car, where the run does not carry it\n'
       || E'BEGIN\n'],
    -- b2. the preview an apply names (the confirm object a preview returns carries it)
    ARRAY[E'      DETAIL = ''expect_plan_hash is the 32-character plan_hash a preview returned.'';\n  END IF;\n',
          E'      DETAIL = ''expect_plan_hash is the 32-character plan_hash a preview returned.'';\n  END IF;\n'
       || E'  --: 0721: the preview this apply confirms, by its command_id\n'
       || E'  v_confirms := public.ottoq_agent_arg_uuid(v_args, ''confirms_command_id'');\n'
       || E'  IF v_confirms IS NOT NULL AND v_mode <> ''apply'' THEN\n'
       || E'    RAISE EXCEPTION USING ERRCODE = ''OQA01'', MESSAGE = ''invalid_arguments'',\n'
       || E'      DETAIL = ''confirms_command_id is for mode apply: it names the preview this apply confirms.'';\n'
       || E'  END IF;\n'],
    -- c. the gate, beside 0605's demo test
    ARRAY[E'  v_demo := v_run IS NOT NULL AND v_run ->> ''run_by'' = ''operator_demo'';\n',
          E'  v_demo := v_run IS NOT NULL AND v_run ->> ''run_by'' = ''operator_demo'';\n'
       || E'  --: 0721: a demo run, or a production run for an agent signed in to its owner''s account (ottoq_owner_write_gate)\n'
       || E'  v_gate := public.ottoq_owner_write_gate(p_agent, v_run);\n'
       || E'  v_production := COALESCE(v_gate ->> ''run_kind'', '''') = ''production'';\n'
       || E'  v_person := v_gate ->> ''person'';\n'],
    -- d. the gate's answer replaces the demo-only refusal (its no-run and other-run words are 0605's, unchanged)
    ARRAY[E'  IF v_refusal IS NULL AND NOT v_demo THEN\n'
       || E'    v_refusal := jsonb_build_object(''code'', ''no_live_demo'',\n'
       || E'      ''message'', CASE WHEN v_run IS NULL THEN ''No demo run is live at the twin depot. Start one in OTTO-TWIN; what you set applies to that run and resets when it ends.''\n'
       || E'                      ELSE ''The live run at the twin depot is not a demo run, and owner settings apply only to demo runs.'' END);\n'
       || E'  END IF;\n',
          E'  --: 0721: the gate: a demo run, or a production run under a signed-in person; why not, and what to do, otherwise\n'
       || E'  IF v_refusal IS NULL AND NOT COALESCE((v_gate ->> ''allowed'')::boolean, false) THEN\n'
       || E'    v_refusal := jsonb_strip_nulls(jsonb_build_object(''code'', v_gate ->> ''code'', ''message'', v_gate ->> ''message'',\n'
       || E'                                                      ''hint'', v_gate ->> ''hint''));\n'
       || E'  END IF;\n'
       || E'  --: 0721 §14: with no run live a signed-in owner saves to the cars only: a charge limit (set, change or clear) or an\n'
       || E'  --: every-return order (or its withdrawal). A hold, a one-time order and an undo belong to a run.\n'
       || E'  IF v_refusal IS NULL AND v_run_id IS NULL\n'
       || E'     AND NOT (v_tool IN (''set_charge_limit'', ''clear_charge_limit'', ''cancel_service'')\n'
       || E'              OR (v_tool = ''request_service'' AND v_when = ''every_return'')) THEN\n'
       || E'    v_refusal := jsonb_build_object(''code'', ''needs_a_live_run'',\n'
       || E'      ''message'', CASE v_tool\n'
       || E'        WHEN ''request_service'' THEN ''No run is live at the twin depot, and a one-time service order (now or next_return) belongs to a run. With no run live you can save an every-return order (when every_return) or a charge limit to your cars.''\n'
       || E'        WHEN ''undo_command''    THEN ''No run is live at the twin depot, and undo works on the run a command was made on. To change what is saved to your cars now, set a new charge limit, clear it (clear_charge_limit), or withdraw an every-return order (cancel_service).''\n'
       || E'        ELSE ''No run is live at the twin depot, and a hold belongs to a run (it is a time on that run''''s clock). With no run live you can save a charge limit or an every-return service order to your cars.'' END,\n'
       || E'      ''hint'', ''Start a demo run in OTTO-TWIN, or wait for the next run, to hold a car, order a one-time service or undo a command.'');\n'
       || E'  END IF;\n'],
    -- e. a new limit below the one in force lowers how full the car charges
    ARRAY[E'      v_before := LEAST(v_ceiling, COALESCE(v_old.charge_limit_pct, v_ceiling));\n',
          E'      v_before := LEAST(v_ceiling, COALESCE(v_old.charge_limit_pct, v_ceiling));\n'
       || E'      IF v_pct < v_before THEN v_lowers := true; END IF;   --: 0721: this command lowers how full the car charges\n'
       || E'      --: §9: a signed-in owner''s limit is saved and carried into production, so it also lowers when it is below the\n'
       || E'      --: limit saved to the car (or the ceiling, when none is), whatever a session without a person set on this run\n'
       || E'      IF v_person IS NOT NULL\n'
       || E'         AND v_pct < LEAST(v_ceiling, COALESCE((SELECT s.charge_limit_pct FROM public.ottoq_owner_saved_settings s\n'
       || E'                                                 WHERE s.vehicle_id = v_veh.id AND s.kind = ''charge_limit''\n'
       || E'                                                   AND s.status = ''active''), v_ceiling)) THEN\n'
       || E'        v_lowers := true;\n'
       || E'      END IF;\n'],
    -- e2. so does an undo that puts back a lower limit than the one in force
    ARRAY[E'          v_grp := ''limit_back'';\n',
          E'          v_grp := ''limit_back'';\n'
       || E'          --: 0721: putting back a lower limit than the one in force lowers how full the car charges\n'
       || E'          IF LEAST(v_ceiling, COALESCE(v_old.charge_limit_pct, v_ceiling)) < LEAST(v_ceiling, v_set.charge_limit_pct) THEN\n'
       || E'            v_lowers := true;\n'
       || E'          END IF;\n'],
    -- e3. (§9, the re-review) a signed-in owner's limit, or its clear, decides what is saved to the car whatever row the run
    --     holds: where the run's own write does not carry the saved limit (the run's limit was set by a session without a
    --     person, or the carry skipped it for the contract), the saved change is an effect of its own
    ARRAY[E'      v_effects := v_effects || jsonb_build_array(public.ottoq_owner_limit_effect(v_veh, v_before, v_pct)\n'
       || E'                                                  || jsonb_build_object(''key'', ''charge_limit''));\n',
          E'      v_effects := v_effects || jsonb_build_array(public.ottoq_owner_limit_effect(v_veh, v_before, v_pct)\n'
       || E'                                                  || jsonb_build_object(''key'', ''charge_limit''));\n'
       || E'      --: 0721 §9: what a person sets or clears is what is saved to the car. The run''s own write carries it when the\n'
       || E'      --: run''s row is the saved one (a clear withdraws it) or when the run gets a new row (the save trigger); otherwise\n'
       || E'      --: the saved limit changes as an effect of its own, shown, hashed and applied after the run''s writes\n'
       || E'      IF v_person IS NOT NULL THEN\n'
       || E'        v_sv := NULL;\n'
       || E'        SELECT * INTO v_sv FROM public.ottoq_owner_saved_settings s\n'
       || E'         WHERE s.vehicle_id = v_veh.id AND s.kind = ''charge_limit'' AND s.status = ''active''\n'
       || E'           AND s.fleet_operator_id = p_agent.fleet_operator_id AND s.depot_id = p_agent.depot_id\n'
       || E'         FOR UPDATE;\n'
       || E'        IF (v_pct >= v_ceiling AND v_sv.saved_id IS NOT NULL\n'
       || E'            AND NOT (v_before <> v_pct AND v_old.saved_id IS NOT DISTINCT FROM v_sv.saved_id))\n'
       || E'           OR (v_pct < v_ceiling AND v_before = v_pct AND v_sv.charge_limit_pct IS DISTINCT FROM v_pct) THEN\n'
       || E'          v_effects := v_effects || jsonb_build_array(public.ottoq_owner_saved_effect(v_veh, ''charge_limit'', NULL,\n'
       || E'                         v_sv.charge_limit_pct, CASE WHEN v_pct < v_ceiling THEN v_pct END));\n'
       || E'        END IF;\n'
       || E'      END IF;\n'],
    -- e4. (§9, the re-review) so does a signed-in owner's cancel: an every-return order saved to the car that no run row
    --     withdrawn here carries (a session without a person replaced or cancelled the carried one) is withdrawn as its own effect
    ARRAY[E'      END LOOP;\n    END LOOP;\n    v_head := CASE WHEN v_service IS NULL THEN format(''Your service orders on %s are withdrawn.'', v_cphrase)\n',
          E'      END LOOP;\n'
       || E'      --: 0721 §9: every-return orders saved to the car that no run row withdrawn above carries\n'
       || E'      IF v_person IS NOT NULL THEN\n'
       || E'        FOR v_sv IN SELECT * FROM public.ottoq_owner_saved_settings s\n'
       || E'                     WHERE s.vehicle_id = v_veh.id AND s.kind = ''service'' AND s.status = ''active''\n'
       || E'                       AND s.fleet_operator_id = p_agent.fleet_operator_id AND s.depot_id = p_agent.depot_id\n'
       || E'                       AND (v_service IS NULL OR s.service = v_service)\n'
       || E'                       AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_settings o\n'
       || E'                                        WHERE o.sim_run_id = v_run_id AND o.saved_id = s.saved_id AND o.status = ''active'')\n'
       || E'                     ORDER BY s.service\n'
       || E'                     FOR UPDATE LOOP\n'
       || E'          v_effects := v_effects || jsonb_build_array(public.ottoq_owner_saved_effect(v_veh, ''service'', v_sv.service, NULL, NULL));\n'
       || E'        END LOOP;\n'
       || E'      END IF;\n'
       || E'    END LOOP;\n    v_head := CASE WHEN v_service IS NULL THEN format(''Your service orders on %s are withdrawn.'', v_cphrase)\n'],
    -- l. (§14) no run is live: a signed-in owner's limit, or its clear, is saved to the cars only. The limit in force is the
    --    one saved to the car, and each car's change is a saved: effect, applied after the record under the person's name
    ARRAY[E'  IF v_refusal IS NULL AND v_tool IN (''set_charge_limit'', ''clear_charge_limit'') THEN\n',
          E'  IF v_refusal IS NULL AND v_tool IN (''set_charge_limit'', ''clear_charge_limit'') AND v_run_id IS NULL THEN\n'
       || E'    --: 0721 §14: no run is live (the gate admits only a signed-in owner): the limit is saved to the cars only\n'
       || E'    v_pct := CASE WHEN v_tool = ''set_charge_limit'' THEN LEAST(v_pct, v_ceiling) ELSE v_ceiling END;\n'
       || E'    FOR v_car IN SELECT x FROM jsonb_array_elements(v_cars) x LOOP\n'
       || E'      SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = (v_car ->> ''id'')::uuid;\n'
       || E'      v_sv := NULL;\n'
       || E'      SELECT * INTO v_sv FROM public.ottoq_owner_saved_settings s\n'
       || E'       WHERE s.vehicle_id = v_veh.id AND s.kind = ''charge_limit'' AND s.status = ''active''\n'
       || E'         AND s.fleet_operator_id = p_agent.fleet_operator_id AND s.depot_id = p_agent.depot_id\n'
       || E'       FOR UPDATE;\n'
       || E'      --: below the limit saved to the car (or the ceiling, when none is): it lowers how full the car charges\n'
       || E'      IF v_pct < LEAST(v_ceiling, COALESCE(v_sv.charge_limit_pct, v_ceiling)) THEN v_lowers := true; END IF;\n'
       || E'      v_effects := v_effects || jsonb_build_array(public.ottoq_owner_saved_effect(v_veh, ''charge_limit'', NULL,\n'
       || E'                     v_sv.charge_limit_pct, CASE WHEN v_pct < v_ceiling THEN v_pct END));\n'
       || E'    END LOOP;\n'
       || E'    v_head := CASE WHEN jsonb_array_length(v_cars) = 1 THEN NULL\n'
       || E'                   WHEN v_pct < v_ceiling THEN format(''%s charge to at most %s%% on every run, from the next one on.'', v_cphrase, v_pct)\n'
       || E'                   ELSE format(''%s charge to the full %s%% on every run, from the next one on.'', v_cphrase, v_ceiling) END;\n'
       || E'  ELSIF v_refusal IS NULL AND v_tool IN (''set_charge_limit'', ''clear_charge_limit'') THEN\n'],
    -- m. (§14) no run is live: a signed-in owner's every-return order is saved to the cars only
    ARRAY[E'  ELSIF v_refusal IS NULL AND v_tool = ''request_service'' THEN\n',
          E'  ELSIF v_refusal IS NULL AND v_tool = ''request_service'' AND v_run_id IS NULL THEN\n'
       || E'    --: 0721 §14: no run is live (the gate admits only a signed-in owner, and only when every_return): saved to the cars only\n'
       || E'    SELECT c.display_name, c.est_min_default INTO v_svc_name, v_svc_min\n'
       || E'      FROM public.service_cadence_policy c WHERE c.svc = v_service AND c.is_active;\n'
       || E'    FOR v_car IN SELECT x FROM jsonb_array_elements(v_cars) x LOOP\n'
       || E'      SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = (v_car ->> ''id'')::uuid;\n'
       || E'      v_effects := v_effects || jsonb_build_array(public.ottoq_owner_saved_effect(v_veh, ''every_return'', v_service, NULL, NULL));\n'
       || E'    END LOOP;\n'
       || E'    v_head := CASE WHEN jsonb_array_length(v_cars) > 1\n'
       || E'                   THEN format(''%s get %s (%s, about %s min) on every return, from the next demo or production run on.'', v_cphrase,\n'
       || E'                               public.ottoq_owner_lc(v_svc_name), public.ottoq_owner_service_where(v_service), v_svc_min) END;\n'
       || E'    v_tail := ''OTTO-Q decides when and where: work in a bay comes after the charge, work at the car runs during it, and no car leaves with it undone.'';\n'
       || E'  ELSIF v_refusal IS NULL AND v_tool = ''request_service'' THEN\n'],
    -- n. (§14) an apply made with no run live is recorded as 'saved': it changed what is saved to the cars, not a run
    ARRAY[E'WHEN v_changed = 0 THEN ''no_change'' ELSE ''applied'' END,',
          E'WHEN v_changed = 0 THEN ''no_change'' WHEN v_run_id IS NULL THEN ''saved'' ELSE ''applied'' END,'],
    ARRAY[E'    IF v_cmd.outcome = ''applied'' THEN\n',
          E'    IF v_cmd.outcome IN (''applied'', ''saved'') THEN   --: 0721 §14: a saved command writes only its saved: effects\n'],
    -- o. (§14) an undo of a command made with no run live (with a run live now: with none, the gate refused it above)
    ARRAY[E'    ELSIF v_target.outcome <> ''applied'' THEN\n',
          E'    ELSIF v_target.outcome = ''saved'' THEN\n'
       || E'      --: 0721 §14: it changed only what is saved to the cars, on no run; undo works on the run a command was made on\n'
       || E'      v_refusal := jsonb_build_object(''code'', ''made_with_no_run_live'', ''message'', ''That command was made while no run was live, and changed only what is saved to your cars. Undo works on the run a command was made on; to change what is saved now, set a new charge limit, clear it (clear_charge_limit), or withdraw the order (cancel_service).'');\n'
       || E'    ELSIF v_target.outcome <> ''applied'' THEN\n'],
    -- f. the binding (rule 9), after 0605's stale-hash refusal
    ARRAY[E'      ''message'', ''The plan changed since it was previewed (a car''''s settings moved). Nothing was applied. Read the new plan and confirm it with its hash.'');\n'
       || E'  END IF;\n',
          E'      ''message'', ''The plan changed since it was previewed (a car''''s settings moved). Nothing was applied. Read the new plan and confirm it with its hash.'');\n'
       || E'  END IF;\n'
       || E'  --: 0721 (CLAUDE.md rule 9: a lower limit is the owner''s, "set verified and confirmed"). An OTTO-Command model never\n'
       || E'  --: confirms a plan: the gateway strips both binding arguments from what it may send, and a call that carries one is refused.\n'
       || E'  IF v_refusal IS NULL AND v_mode = ''apply'' AND v_door = ''ottocommand'' AND (v_expect IS NOT NULL OR v_confirms IS NOT NULL) THEN\n'
       || E'    v_refusal := jsonb_build_object(''code'', ''confirm_not_through_ottocommand'',\n'
       || E'      ''message'', ''OTTO-Command does not confirm a plan. Nothing was applied. A preview is confirmed by sending its confirm object back: to ask_ottocommand or POST /v1/ask as confirm, or as the typed tool call it describes.'');\n'
       || E'  END IF;\n'
       || E'  --: An apply must be the confirm of a recorded preview (ottoq_owner_confirm_binding: same principal, run, tool, arguments\n'
       || E'  --: and plan hash, at most 15 minutes old, not confirmed before) when it lowers a limit on a production run or for a\n'
       || E'  --: signed-in owner (whose limit is saved and carried into production, §9), when it came\n'
       || E'  --: through the confirm door, or when it names a preview. One that does not bind applies nothing: it is recorded as a\n'
       || E'  --: preview, with its own plan hash and id, and answered confirm_required, so the next confirm can name it. One that\n'
       || E'  --: binds is recorded as via ''confirm'', whichever way it was sent: the agent confirmed a recorded preview.\n'
       || E'  IF v_refusal IS NULL AND v_mode = ''apply''\n'
       || E'     AND (p_via IS NOT DISTINCT FROM ''confirm'' OR v_confirms IS NOT NULL OR (v_lowers AND (v_production OR v_person IS NOT NULL))) THEN\n'
       || E'    v_bind := public.ottoq_owner_confirm_binding(p_agent, v_run_id, v_tool, v_norm, v_hash, v_expect, v_confirms,\n'
       || E'                                                 v_lowers AND (v_production OR v_person IS NOT NULL));\n'
       || E'    v_bound := (v_bind ->> ''bound'')::uuid;\n'
       || E'    IF v_bound IS NULL THEN\n'
       || E'      v_confirm_req := v_bind;\n'
       || E'      v_mode := ''preview'';\n'
       || E'      v_norm := v_norm || jsonb_build_object(''mode'', ''preview'');\n'
       || E'    ELSE\n'
       || E'      v_via := ''confirm'';\n'
       || E'    END IF;\n'
       || E'  END IF;\n'],
    -- g. the receipt names the run that ends it
    --: §9: what a signed-in owner sets as a limit or an every-return order is saved, and the receipt says so
    ARRAY[E'E''\\nThis lasts until the demo run ends or you undo it.''',
          E'CASE WHEN v_run_id IS NULL THEN E''\\nNo run is live: this is saved to your cars, applies from the next demo or production run, and stays from run to run, production included, until you change it.'' WHEN v_person IS NOT NULL AND (v_tool IN (''set_charge_limit'', ''clear_charge_limit'') OR (v_tool = ''request_service'' AND v_when = ''every_return'') OR (v_tool = ''cancel_service'' AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_effects) e WHERE e ->> ''before'' = ''every_return''))) THEN E''\\nThis is saved to your cars: it stays from run to run, production included, until you change it.'' WHEN v_production THEN E''\\nThis lasts until the production run ends or you undo it.'' ELSE E''\\nThis lasts until the demo run ends or you undo it.'' END'],
    -- g2. an apply recorded as a preview says so, and how to confirm it
    ARRAY[E'    WHEN v_mode = ''preview'' THEN ''Preview only, nothing has changed. If you confirm: ''\n',
          E'    WHEN v_confirm_req IS NOT NULL THEN ''Not applied yet: '' || (v_confirm_req ->> ''message'') || E''\\nIf you confirm: ''\n'
       || E'         || public.ottoq_owner_summarize(v_head, v_effects, v_tail)\n'
       || E'         || format(E''\\nTo confirm, send the same command with mode "apply", expect_plan_hash "%s" and confirms_command_id "%s".'', v_hash, v_cmd.command_id)\n'
       || E'    WHEN v_mode = ''preview'' THEN ''Preview only, nothing has changed. If you confirm: ''\n'],
    -- h. the record: the person, the door and the preview confirmed, on every row
    ARRAY[E'       args, vehicles, effects, refusal, summary, plan_hash, link, idempotency_key, undoes_command_id)\n',
          E'       args, vehicles, effects, refusal, summary, plan_hash, link, idempotency_key, undoes_command_id, acting_person, via,\n'
       || E'       confirms_command_id)\n'],
    ARRAY[E'       CASE WHEN v_tool = ''undo_command'' AND v_target.command_id IS NOT NULL THEN v_target.command_id END)\n',
          E'       CASE WHEN v_tool = ''undo_command'' AND v_target.command_id IS NOT NULL THEN v_target.command_id END,\n'
       || E'       v_person, v_via, v_bound)\n'],
    ARRAY[E'       vehicles, effects, refusal, summary, plan_hash)\n',
          E'       vehicles, effects, refusal, summary, plan_hash, acting_person, via)\n'],
    ARRAY[E'Nothing was applied; send it again.'', v_hash)\n',
          E'Nothing was applied; send it again.'', v_hash, v_person, v_door)\n'],
    -- i. (§9) an undo of a command made on an earlier run whose setting is saved says so, and what to do instead
    ARRAY[E'      v_refusal := jsonb_build_object(''code'', ''run_ended'', ''message'', ''That command applied to a run that has ended; its settings were lifted with it.'');
',
          E'      --: 0721 (§9): what a signed-in owner saved outlives its run; undo works on the run a command was made on
      v_refusal := CASE WHEN EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings s
                                      WHERE s.command_id = v_target.command_id AND s.status = ''active'')
        THEN jsonb_build_object(''code'', ''made_on_an_earlier_run'', ''message'', ''That command was made on an earlier run, and what it set is saved to your cars and still in force: it stays from run to run. Undo works on the run a command was made on; to change it now, set a new charge limit, clear it (clear_charge_limit), or withdraw the order (cancel_service).'')
        ELSE jsonb_build_object(''code'', ''run_ended'', ''message'', ''That command applied to a run that has ended; its settings were lifted with it.'') END;
'],
    -- i2. (§9, the re-review) the run's writes take the run's effects only; a saved change is applied after them, under the
    --     person's name, ending the saved row (a clear, a cancel) or saving the new limit in its place
    ARRAY[E'      FOR v_e IN SELECT e FROM jsonb_array_elements(v_effects) e WHERE COALESCE((e ->> ''change'')::boolean, false) LOOP\n',
          E'      FOR v_e IN SELECT e FROM jsonb_array_elements(v_effects) e WHERE COALESCE((e ->> ''change'')::boolean, false)\n'
       || E'                                                                   AND COALESCE(e ->> ''key'', '''') NOT LIKE ''saved:%'' LOOP\n'],
    ARRAY[E'      IF v_tool = ''undo_command'' THEN\n'
       || E'        UPDATE public.ottoq_owner_commands c SET undone_by_command_id = v_cmd.command_id, undone_at = now()\n',
          E'      --: 0721 §9: what is saved to the cars where no run row carried it (the plan''s saved: effects)\n'
       || E'      FOR v_e IN SELECT e FROM jsonb_array_elements(v_effects) e\n'
       || E'                  WHERE COALESCE(e ->> ''key'', '''') LIKE ''saved:%'' AND COALESCE((e ->> ''change'')::boolean, false) LOOP\n'
       || E'        UPDATE public.ottoq_owner_saved_settings s\n'
       || E'           SET status = ''ended'', ended_at = now(), ended_by_command_id = v_cmd.command_id,\n'
       || E'               ended_reason = CASE WHEN v_e ->> ''after'' IS NOT NULL THEN ''replaced by a new setting''\n'
       || E'                                   WHEN v_tool = ''cancel_service'' THEN ''cancelled by the owner'' ELSE ''cleared by the owner'' END\n'
       || E'         WHERE s.vehicle_id = (v_e ->> ''vehicle_id'')::uuid AND s.status = ''active''\n'
       || E'           AND s.fleet_operator_id = p_agent.fleet_operator_id AND s.depot_id = p_agent.depot_id\n'
       || E'           AND CASE WHEN v_e ->> ''key'' = ''saved:charge_limit'' THEN s.kind = ''charge_limit''\n'
       || E'                    ELSE s.kind = ''service'' AND ''saved:service:'' || s.service = v_e ->> ''key'' END;\n'
       || E'        IF v_e ->> ''key'' = ''saved:charge_limit'' AND v_e ->> ''after'' IS NOT NULL THEN\n'
       || E'          INSERT INTO public.ottoq_owner_saved_settings (depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct,\n'
       || E'                                                         command_id, acting_person)\n'
       || E'          VALUES (p_agent.depot_id, p_agent.fleet_operator_id, (v_e ->> ''vehicle_id'')::uuid, ''charge_limit'',\n'
       || E'                  (v_e ->> ''after'')::numeric, v_cmd.command_id, v_person);\n'
       || E'        ELSIF v_e ->> ''key'' LIKE ''saved:service:%'' AND v_e ->> ''after'' = ''every_return'' THEN\n'
       || E'          --: §14: an every-return order saved with no run live\n'
       || E'          INSERT INTO public.ottoq_owner_saved_settings (depot_id, fleet_operator_id, vehicle_id, kind, service, command_id,\n'
       || E'                                                         acting_person)\n'
       || E'          VALUES (p_agent.depot_id, p_agent.fleet_operator_id, (v_e ->> ''vehicle_id'')::uuid, ''service'', v_e ->> ''service'',\n'
       || E'                  v_cmd.command_id, v_person);\n'
       || E'        END IF;\n'
       || E'      END LOOP;\n'
       || E'      IF v_tool = ''undo_command'' THEN\n'
       || E'        UPDATE public.ottoq_owner_commands c SET undone_by_command_id = v_cmd.command_id, undone_at = now()\n'],
    -- j. an apply recorded as a preview answers confirm_required (ottoq_agent_call: 422), naming that preview
    ARRAY[E'  RETURN public.ottoq_owner_command_reply(v_cmd, false);\n',
          E'  RETURN public.ottoq_owner_command_reply(v_cmd, false)\n'
       || E'         || CASE WHEN v_confirm_req IS NOT NULL AND v_cmd.outcome = ''previewed''\n'
       || E'                 THEN jsonb_build_object(''refusal'', v_confirm_req || jsonb_build_object(''preview_command_id'', v_cmd.command_id))\n'
       || E'                 ELSE ''{}''::jsonb END;\n']];
  v_n int;
BEGIN
  v_new := v_def;
  FOREACH v_pair SLICE 1 IN ARRAY v_pairs LOOP
    v_n := (length(v_new) - length(replace(v_new, v_pair[1], ''))) / length(v_pair[1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0721: an anchor of ottoq_owner_command occurs % times, expected exactly 1: %', v_n, left(v_pair[1], 120);
    END IF;
    v_new := replace(v_new, v_pair[1], v_pair[2]);
  END LOOP;
  EXECUTE v_new;
END $command$;

REVOKE ALL ON FUNCTION public.ottoq_owner_command(public.ottoq_agent_principals, text, jsonb, text) FROM PUBLIC, anon, authenticated, service_role;

--: the three-argument form keeps its name, grants and signature for any direct caller, and is the four-argument one
CREATE OR REPLACE FUNCTION public.ottoq_owner_command(p_agent public.ottoq_agent_principals, p_tool text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721. The owner command's body is ottoq_owner_command(principal, tool, args, p_via), which also records the door a
   command came through and the person behind it. ottoq_agent_call calls that form with its transport; a caller of this
   form is recorded as via 'direct'. */
BEGIN
  RETURN public.ottoq_owner_command(p_agent, p_tool, p_args, NULL::text);
END $fn$;

-- ══ 4. the dispatcher admits the confirm door, passes its transport, and answers confirm_required 422 ════════════════
DO $call$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure);
  v_new text;
  v_pair text[];
  v_pairs text[][] := ARRAY[
    ARRAY[E'  v_transport text := CASE WHEN p_transport IN (''rest'', ''mcp'', ''ask'') THEN p_transport ELSE ''other'' END;\n',
          E'  --: 0721: ''confirm'' is the gateway''s confirm door (a preview''s confirm object sent back, no model involved)\n'
       || E'  v_transport text := CASE WHEN p_transport IN (''rest'', ''mcp'', ''ask'', ''confirm'') THEN p_transport ELSE ''other'' END;\n'],
    ARRAY[E'      ELSE public.ottoq_owner_command(v_agent, v_tool, v_args)\n',
          E'      ELSE public.ottoq_owner_command(v_agent, v_tool, v_args, v_transport)   --: 0721: the door it came through\n'],
    --: §12: no read and no change for a demo passcode session while a production run is live at its depot
    ARRAY[E'  UPDATE public.ottoq_agent_principals a SET last_used_at = now()
',
          E'  --: 0721 (§12): a demo passcode session serves nothing, not even a read, while a production run is live at its depot
  IF v_agent.origin = ''passcode'' AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                                              WHERE r.depot_id = v_agent.depot_id AND r.run_by = ''production_live''
                                                AND r.status IN (''running'', ''paused'')) THEN
    INSERT INTO public.ottoq_agent_call_ledger (principal_id, principal_name, transport, tool, http_method, path, ok,
                                               http_status, error_code, latency_ms, depot_id, fleet_operator_id, detail)
    VALUES (v_agent.principal_id, v_agent.name, v_transport, v_tool, v_meta ->> ''http_method'', v_meta ->> ''path'',
            false, 403, ''production_live'', (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer,
            v_agent.depot_id, v_agent.fleet_operator_id, v_meta - ''http_method'' - ''path'')
    RETURNING call_id INTO v_call;
    RETURN jsonb_build_object(''ok'', false, ''http_status'', 403, ''tool'', v_tool, ''call_id'', v_call,
      ''error'', jsonb_build_object(''code'', ''production_live'',
        ''message'', ''A production run is live at the twin depot, and the demo passcode opens nothing while it is: production is read and changed only by an agent signed in to its owner''''s OTTOYARD account. This session works again once the production run ends, until it expires.'',
        ''hint'', ''Sign your agent in to your OTTOYARD account (PERSONAL_AGENT.md section 10) to read and change your cars in production.''));
  END IF;

  UPDATE public.ottoq_agent_principals a SET last_used_at = now()
'],
    --: §11: my_settings also says what is saved to the cars, and stops saying everything lifts at the run's end
    ARRAY[E'      WHEN ''my_settings''        THEN public.ottoq_owner_read(v_agent, ''my_settings'', v_args)
',
          E'      WHEN ''my_settings''        THEN public.ottoq_owner_settings_read(v_agent, public.ottoq_owner_read(v_agent, ''my_settings'', v_args))   --: 0721 §11: and what is saved
'],
    ARRAY[E'      v_status := CASE WHEN v_data ->> ''outcome'' = ''refused'' THEN 422\n',
          E'      --: 0721: an apply that had to confirm a preview and did not is recorded as one, and answered as not done\n'
       || E'      v_status := CASE WHEN v_data ->> ''outcome'' = ''refused'' OR v_data #>> ''{refusal,code}'' = ''confirm_required'' THEN 422\n'],
    --: §14: a command that saved to the cars with no run live created something, as an applied one does
    ARRAY[E'                       WHEN v_data ->> ''outcome'' = ''applied'' AND NOT COALESCE((v_data ->> ''duplicate'')::boolean, false) THEN 201\n',
          E'                       WHEN v_data ->> ''outcome'' IN (''applied'', ''saved'') AND NOT COALESCE((v_data ->> ''duplicate'')::boolean, false) THEN 201\n']];
  v_n int;
BEGIN
  v_new := v_def;
  FOREACH v_pair SLICE 1 IN ARRAY v_pairs LOOP
    v_n := (length(v_new) - length(replace(v_new, v_pair[1], ''))) / length(v_pair[1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0721: an anchor of ottoq_agent_call occurs % times, expected exactly 1: %', v_n, left(v_pair[1], 120);
    END IF;
    v_new := replace(v_new, v_pair[1], v_pair[2]);
  END LOOP;
  EXECUTE v_new;
END $call$;

-- ══ 5. the receipt shows the person, the door, the preview confirmed and the run that ends it; a confirm names its preview
DO $reply$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure);
  v_new text;
  v_pair text[];
  v_pairs text[][] := ARRAY[
    ARRAY[E'      ''lifted_at'', p_c.lifted_at, ''lifted_reason'', p_c.lifted_reason),\n',
          E'      ''lifted_at'', p_c.lifted_at, ''lifted_reason'', p_c.lifted_reason,\n'
       || E'      --: 0721: the person the command is recorded under, the door it came through, and the preview it confirmed\n'
       || E'      ''acting_person'', p_c.acting_person, ''via'', p_c.via, ''confirms_command_id'', p_c.confirms_command_id),\n'],
    ARRAY[E'                         || jsonb_build_object(''mode'', ''apply'', ''expect_plan_hash'', p_c.plan_hash),\n'
       || E'                 ''note'', ''Send this to apply exactly the plan shown. If the cars or settings change first, OTTO-Q refuses with the new plan.'') END,\n',
          E'                         --: 0721: the confirm names this preview, which confirms one apply\n'
       || E'                         || jsonb_build_object(''mode'', ''apply'', ''expect_plan_hash'', p_c.plan_hash, ''confirms_command_id'', p_c.command_id),\n'
       || E'                 ''note'', ''Send this to apply exactly the plan shown, from the agent that previewed it, within 15 minutes; it confirms this preview once. If the cars or settings change first, OTTO-Q refuses with the new plan.'') END,\n'],
    --: §14: a command made with no run live (outcome saved) has a receipt that says what it changed and when it applies
    ARRAY[E'    ''expires'', CASE WHEN p_c.outcome = ''applied'' AND p_c.tool <> ''undo_command''\n',
          E'    ''expires'', CASE WHEN p_c.outcome IN (''applied'', ''saved'') AND p_c.tool <> ''undo_command''\n'],
    ARRAY[E'                    THEN ''Lasts until this demo run ends or you undo it; a stop or reset of the twin puts every car back to baseline.'' END))\n',
          E'                    THEN CASE WHEN p_c.outcome = ''saved''\n'
       || E'                              THEN ''Made while no run was live: it changes what is saved to the cars, applies from the next demo or production run, and stays from run to run until the owner changes it.''\n'
       || E'                              WHEN EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings s\n'
       || E'                                            WHERE s.command_id = p_c.command_id AND s.status = ''active'')\n'
       || E'                              THEN ''Saved to the cars: it stays from run to run, production included, until the owner changes it.''\n'
       || E'                              WHEN (SELECT r.run_by FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_c.sim_run_id) = ''production_live''\n'
       || E'                              THEN ''Lasts until this production run ends or you undo it; when the run ends every car goes back to its baseline.''\n'
       || E'                              ELSE ''Lasts until this demo run ends or you undo it; a stop or reset of the twin puts every car back to baseline.'' END END))\n']];
  v_n int;
BEGIN
  v_new := v_def;
  FOREACH v_pair SLICE 1 IN ARRAY v_pairs LOOP
    v_n := (length(v_new) - length(replace(v_new, v_pair[1], ''))) / length(v_pair[1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0721: an anchor of ottoq_owner_command_reply occurs % times, expected exactly 1: %', v_n, left(v_pair[1], 120);
    END IF;
    v_new := replace(v_new, v_pair[1], v_pair[2]);
  END LOOP;
  EXECUTE v_new;
END $reply$;

-- ══ 6. whoami says whether this agent may change settings now, and under whose name ═════════════════════════════════
DO $whoami$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure);
  c_old1 constant text := E'      ''live_demo_run'', CASE WHEN v_run ->> ''run_by'' = ''operator_demo'' THEN v_run -> ''sim_run_id'' END,\n';
  c_new1 constant text := E'      ''live_demo_run'', CASE WHEN v_run ->> ''run_by'' = ''operator_demo'' THEN v_run -> ''sim_run_id'' END,\n'
                       || E'      --: 0721: a production run, and the gate: may this agent change settings now, under whose name, and why not\n'
                       || E'      ''live_production_run'', CASE WHEN v_run ->> ''run_by'' = ''production_live'' THEN v_run -> ''sim_run_id'' END,\n'
                       || E'      ''changes'', public.ottoq_owner_write_gate(p_agent, v_run),\n';
  c_old2 constant text := E'undoable, and lifted when the demo run ends.'',\n';
  c_new2 constant text := E'and undoable on the run it was made on. A charge limit or an every-return service set by an agent signed in to the owner''''s OTTOYARD account is saved to the car and stays from run to run, production included, until the owner changes it; holds, one-time orders and anything set through a passcode session or an issued key lift when the run ends. On a production run only an agent signed in to its owner''''s OTTOYARD account may change them, each change is recorded under that person, and wherever a person is recorded a lower charge limit (or an undo that puts one back) applies only as the confirm of a preview the same agent recorded in the last 15 minutes. With no run live, that signed-in agent may still save a charge limit or an every-return order to the cars; it is carried onto the next demo or production run.'',\n';
  v_n1 int; v_n2 int;
BEGIN
  v_n1 := (length(v_def) - length(replace(v_def, c_old1, ''))) / length(c_old1);
  v_n2 := (length(v_def) - length(replace(v_def, c_old2, ''))) / length(c_old2);
  IF v_n1 <> 1 OR v_n2 <> 1 THEN
    RAISE EXCEPTION '0721: whoami''s anchors occur % and % times, expected exactly 1 each', v_n1, v_n2;
  END IF;
  EXECUTE replace(replace(v_def, c_old1, c_new1), c_old2, c_new2);
END $whoami$;

-- ══ 7. the guard: who, which door and which preview are as immutable as what was commanded ══════════════════════
DO $guard$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_commands_guard()'::regprocedure);
  c_old1 constant text := E'NEW.plan_hash, NEW.link, NEW.idempotency_key, NEW.undoes_command_id, NEW.created_at)';
  c_new1 constant text := E'NEW.plan_hash, NEW.link, NEW.idempotency_key, NEW.undoes_command_id, NEW.created_at, NEW.acting_person, NEW.via,\n'
                       || E'      NEW.confirms_command_id)';
  c_old2 constant text := E'OLD.plan_hash, OLD.link, OLD.idempotency_key, OLD.undoes_command_id, OLD.created_at)';
  c_new2 constant text := E'OLD.plan_hash, OLD.link, OLD.idempotency_key, OLD.undoes_command_id, OLD.created_at, OLD.acting_person, OLD.via,\n'
                       || E'      OLD.confirms_command_id)';
  v_n1 int; v_n2 int;
BEGIN
  v_n1 := (length(v_def) - length(replace(v_def, c_old1, ''))) / length(c_old1);
  v_n2 := (length(v_def) - length(replace(v_def, c_old2, ''))) / length(c_old2);
  IF v_n1 <> 1 OR v_n2 <> 1 THEN
    RAISE EXCEPTION '0721: ottoq_owner_commands_guard''s tuples occur % and % times, expected exactly 1 each', v_n1, v_n2;
  END IF;
  EXECUTE replace(replace(v_def, c_old1, c_new1), c_old2, c_new2);
END $guard$;

-- ══ 8. the backstop, whoever writes the row: no applied production command without a person (rule 10), and no confirm
--      of anything but a preview this apply may confirm (rule 9) ══════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_owner_commands_backstop()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721. Under the door, for any writer. CLAUDE.md rule 10: in production no setting changes except under a person's
   name, so an applied command on a production_live run carries acting_person. Rule 9: a confirms_command_id names a
   preview (outcome 'previewed') by the same principal, on the same run, of the same tool and plan hash, made at most
   15 minutes before the apply; the unique index ottoq_owner_commands_confirms_idx lets it confirm one apply. */
DECLARE
  v_p public.ottoq_owner_commands;
BEGIN
  IF NEW.outcome = 'applied' AND NEW.acting_person IS NULL AND NEW.sim_run_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id AND r.run_by = 'production_live') THEN
    RAISE EXCEPTION 'owner command on production run %: an applied change needs the person it is recorded under (acting_person)',
      NEW.sim_run_id USING ERRCODE = '42501';
  END IF;
  IF NEW.confirms_command_id IS NOT NULL THEN
    SELECT * INTO v_p FROM public.ottoq_owner_commands p WHERE p.command_id = NEW.confirms_command_id;
    IF v_p.command_id IS NULL OR v_p.outcome IS DISTINCT FROM 'previewed' OR v_p.principal_id IS DISTINCT FROM NEW.principal_id
       OR v_p.sim_run_id IS DISTINCT FROM NEW.sim_run_id OR v_p.tool IS DISTINCT FROM NEW.tool
       OR v_p.plan_hash IS DISTINCT FROM NEW.plan_hash
       OR v_p.created_at < NEW.created_at - interval '15 minutes' OR v_p.created_at > NEW.created_at THEN
      RAISE EXCEPTION 'owner command %: confirms_command_id % is not a preview this apply may confirm (the same principal, run, tool and plan, at most 15 minutes before it)',
        NEW.command_id, NEW.confirms_command_id USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_owner_commands_backstop() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER ottoq_owner_commands_backstop_trg
  BEFORE INSERT ON public.ottoq_owner_commands
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_commands_backstop();

-- ══ 9. what a signed-in owner sets is saved to the car, and carried onto every new run (Chase 2026-10-14) ════════════
--
-- Saving: a BEFORE INSERT trigger on ottoq_owner_settings. An active charge limit or every-return order, written for an
-- applied command recorded under a person, gets a saved row (ending the one it replaces) and names it in saved_id. The
-- owner command's body is unchanged for this: the trigger reads the command row it already wrote.
-- Following: an AFTER UPDATE OF status trigger. When an applied command recorded under a person replaces or withdraws a
-- saved setting on a run, the saved row ends with it; when an undo puts a replaced setting back, its saved row comes back
-- (unless the car has another saved one of that kind by then). The run's end ('lifted'), the tick ('fulfilled') and a
-- change made without a person (a passcode session, an issued key) leave the saved row as it is: they belong to the run.
-- Carrying: when a demo or production run at the depot starts (INSERT, or a status change to running or paused), each
-- active saved row becomes that run's ottoq_owner_settings row, once per run, through ottoq_owner_saved_carry: only while
-- the car is still that owner's at that depot, only when the run has no setting of that kind for the car already, a
-- limit only inside the contract in force then (below its minimum or at its ceiling it is not carried, and the car
-- charges full), and an order only for a service still requestable and not blocked. A failure is a WARNING: a run's start
-- never fails for an owner's setting. The engine then reads it exactly as it reads a setting made on the run
-- (ottoq_effective_target_soc_at, ottoq_departure_clear, the tick, the visit trigger), none of which changes here.
-- The run's end: ottoq_tg_lift_owner_settings_on_terminal is patched so that it stamps lifted_at only on commands nothing
-- saved is still carrying: what a saved command set is lifted from the run, and is not lifted from the car.

CREATE OR REPLACE FUNCTION public.ottoq_owner_settings_save()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721 §9. A setting a signed-in owner makes that outlives its run (a charge limit, an every-return order) is saved to the
   car. Carried rows (saved_id set by ottoq_owner_saved_carry) and anything else are left as they are. A failure here is
   raised: an owner told a setting is saved must not find it was not. */
DECLARE
  c public.ottoq_owner_commands;
  v_saved uuid;
BEGIN
  IF NEW.saved_id IS NOT NULL OR NEW.status <> 'active'
     OR NOT (NEW.kind = 'charge_limit' OR (NEW.kind = 'service' AND NEW.service_when = 'every_return')) THEN
    RETURN NEW;
  END IF;
  SELECT * INTO c FROM public.ottoq_owner_commands x WHERE x.command_id = NEW.command_id;
  IF c.acting_person IS NULL OR c.outcome IS DISTINCT FROM 'applied' THEN
    RETURN NEW;
  END IF;
  UPDATE public.ottoq_owner_saved_settings s
     SET status = 'ended', ended_at = now(), ended_reason = 'replaced by a new setting', ended_by_command_id = c.command_id
   WHERE s.vehicle_id = NEW.vehicle_id AND s.status = 'active' AND s.kind = NEW.kind
     AND (NEW.kind = 'charge_limit' OR s.service = NEW.service);
  INSERT INTO public.ottoq_owner_saved_settings (depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct, service,
                                                 command_id, acting_person)
  VALUES (NEW.depot_id, NEW.fleet_operator_id, NEW.vehicle_id, NEW.kind,
          CASE WHEN NEW.kind = 'charge_limit' THEN NEW.charge_limit_pct END,
          CASE WHEN NEW.kind = 'service' THEN NEW.service END, c.command_id, c.acting_person)
  RETURNING saved_id INTO v_saved;
  NEW.saved_id := v_saved;
  RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_settings_saved_follow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721 §9. A saved setting follows what a person does to it on a run: replaced or withdrawn by an applied command recorded
   under a person, it ends; put back by an undo, it comes back. Anything else (the run's end, the tick, a change made
   without a person) leaves it. */
BEGIN
  IF NEW.saved_id IS NULL OR OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NULL;
  END IF;
  IF OLD.status = 'active' AND NEW.status IN ('replaced', 'withdrawn')
     AND EXISTS (SELECT 1 FROM public.ottoq_owner_commands c
                  WHERE c.command_id = NEW.closed_by_command_id AND c.outcome = 'applied' AND c.acting_person IS NOT NULL) THEN
    UPDATE public.ottoq_owner_saved_settings s
       SET status = 'ended', ended_at = now(),
           ended_reason = CASE NEW.status WHEN 'replaced' THEN 'replaced by a new setting'
                                          ELSE COALESCE(NEW.closed_reason, 'withdrawn by the owner') END,
           ended_by_command_id = NEW.closed_by_command_id
     WHERE s.saved_id = NEW.saved_id AND s.status = 'active';
  ELSIF OLD.status = 'replaced' AND NEW.status = 'active' THEN
    UPDATE public.ottoq_owner_saved_settings s
       SET status = 'active', ended_at = NULL, ended_reason = NULL, ended_by_command_id = NULL
     WHERE s.saved_id = NEW.saved_id AND s.status = 'ended'
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings x
                        WHERE x.vehicle_id = s.vehicle_id AND x.status = 'active' AND x.kind = s.kind
                          AND (x.kind = 'charge_limit' OR x.service = s.service));
  END IF;
  RETURN NULL;
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_saved_carry(p_run uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721 §9. Carry every active saved setting at a run's depot onto that run, once. Only demo and production runs; returns
   how many settings were carried. Called by the run-start triggers; safe to call again (it carries nothing twice). */
DECLARE
  r       public.ottoq_sim_runs;
  s       public.ottoq_owner_saved_settings;
  v_clock timestamptz;
  v_ctr   jsonb;
  v_max   numeric;
  v_n     integer := 0;
BEGIN
  SELECT * INTO r FROM public.ottoq_sim_runs x WHERE x.sim_run_id = p_run;
  IF r.sim_run_id IS NULL OR r.run_by IS NULL OR r.run_by NOT IN ('operator_demo', 'production_live')
     OR r.status NOT IN ('running', 'paused') THEN
    RETURN 0;
  END IF;
  v_clock := COALESCE(r.sim_clock_current, now());
  FOR s IN SELECT * FROM public.ottoq_owner_saved_settings x
            WHERE x.depot_id = r.depot_id AND x.status = 'active'
            ORDER BY x.saved_at, x.saved_id LOOP
    --: once per run: a pause and a resume never bring back what was withdrawn on the run
    CONTINUE WHEN EXISTS (SELECT 1 FROM public.ottoq_owner_settings o WHERE o.sim_run_id = p_run AND o.saved_id = s.saved_id);
    --: the car is still this owner's, at this depot
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM public.vehicles v
                               WHERE v.id = s.vehicle_id AND v.fleet_operator_id = s.fleet_operator_id
                                 AND (v.home_depot_id = s.depot_id OR v.current_depot_id = s.depot_id));
    --: a setting of that kind already made on this run stands
    CONTINUE WHEN EXISTS (SELECT 1 FROM public.ottoq_owner_settings o
                           WHERE o.sim_run_id = p_run AND o.vehicle_id = s.vehicle_id AND o.status = 'active'
                             AND o.kind = s.kind AND (s.kind = 'charge_limit' OR o.service = s.service));
    v_ctr := public.ottoq_owner_contract(s.fleet_operator_id, v_clock);
    IF s.kind = 'charge_limit' THEN
      v_max := COALESCE((v_ctr ->> 'max_charge_pct')::numeric, public.ottoq_default_target_soc());
      --: only inside the contract in force now; outside it the car charges full (rule 9 errs toward a fuller car)
      CONTINUE WHEN v_ctr IS NULL OR s.charge_limit_pct < (v_ctr ->> 'min_charge_pct')::numeric OR s.charge_limit_pct >= v_max;
      INSERT INTO public.ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct,
                                              command_id, set_at_sim, saved_id)
      VALUES (p_run, s.depot_id, s.fleet_operator_id, s.vehicle_id, 'charge_limit', s.charge_limit_pct, s.command_id, v_clock,
              s.saved_id);
    ELSE
      CONTINUE WHEN NOT (s.service = ANY (public.ottoq_owner_requestable_services()))
                 OR COALESCE((v_ctr -> 'blocked_services') ? s.service, false);
      INSERT INTO public.ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, service, service_when,
                                              include_current_visit, command_id, set_at_sim, saved_id)
      VALUES (p_run, s.depot_id, s.fleet_operator_id, s.vehicle_id, 'service', s.service, 'every_return', true, s.command_id,
              v_clock, s.saved_id);
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_tg_owner_saved_on_run_start()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721 §9. A demo or production run that starts (or resumes) carries what owners saved to their cars. Never fails the
   run's start: a failure is a WARNING, and the cars charge full until an owner sets it again. */
BEGIN
  BEGIN
    PERFORM public.ottoq_owner_saved_carry(NEW.sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'carrying saved owner settings onto run % failed: % %', NEW.sim_run_id, SQLSTATE, SQLERRM;
  END;
  RETURN NULL;
END $fn$;

CREATE TRIGGER ottoq_owner_settings_save_trg
  BEFORE INSERT ON public.ottoq_owner_settings
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_settings_save();
CREATE TRIGGER ottoq_owner_settings_saved_follow_trg
  AFTER UPDATE OF status ON public.ottoq_owner_settings
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_settings_saved_follow();
--: no arm is a demo or production run, so these never fire inside a certification, a dial pair or a sweep arm
CREATE TRIGGER ottoq_sim_runs_carry_saved_owner_settings
  AFTER INSERT ON public.ottoq_sim_runs
  FOR EACH ROW
  WHEN (new.run_by = ANY (ARRAY['operator_demo'::text, 'production_live'::text])
        AND new.status = ANY (ARRAY['running'::text, 'paused'::text]))
  EXECUTE FUNCTION public.ottoq_tg_owner_saved_on_run_start();
CREATE TRIGGER ottoq_sim_runs_carry_saved_owner_settings_on_start
  AFTER UPDATE OF status ON public.ottoq_sim_runs
  FOR EACH ROW
  WHEN (old.status IS DISTINCT FROM new.status
        AND new.run_by = ANY (ARRAY['operator_demo'::text, 'production_live'::text])
        AND new.status = ANY (ARRAY['running'::text, 'paused'::text]))
  EXECUTE FUNCTION public.ottoq_tg_owner_saved_on_run_start();

--: the run's end lifts a saved command's settings from the run, and does not stamp the command as lifted
DO $lift$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_tg_lift_owner_settings_on_terminal()'::regprocedure);
  c_old constant text := E'     WHERE c.command_id = ANY (COALESCE(v_cmds, ARRAY[]::uuid[])) AND c.lifted_at IS NULL;\n';
  c_new constant text := E'     WHERE c.command_id = ANY (COALESCE(v_cmds, ARRAY[]::uuid[])) AND c.lifted_at IS NULL\n'
                      || E'       --: 0721 §9: a command whose setting is saved to the car is carried to the next run, not lifted\n'
                      || E'       AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings s\n'
                      || E'                        WHERE s.command_id = c.command_id AND s.status = ''active'');\n';
  v_n int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0721: the lift''s anchor occurs % times, expected exactly 1', v_n;
  END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $lift$;

-- ══ 10. the owner tables' own guard: no setting without an applied command that set it (the 0721 re-review, item 10) ═
--
-- Measured (§1(g)): only postgres holds privileges on ottoq_owner_settings, and only ottoq_owner_command, the tick and the
-- run's end write it; but postgres is also the SQL editor and the Management API, and nothing below the door refused a
-- row no command made. Now, whoever writes:
--   INSERT  a row is what an applied owner command set: same fleet and depot, a car the command names, the kind the tool
--           sets with the value it set, and either on the command's own run or carried from a saved row that command made;
--   UPDATE  what was set is immutable; status moves only active -> replaced | withdrawn | fulfilled | lifted, or
--           replaced -> active (an undo); replaced and withdrawn only by an applied owner command;
--   DELETE  only the run purge (ottoq.retention, armed by ottoq_purge_prior_runs; registry check (d) requires it).
-- The saved table: a row only for an applied command recorded under a person that set exactly that; status and its end
-- are all that move; never deleted or truncated. ottoq.agent_ledger_unlock (the owner ledger's existing escape hatch,
-- to be named in a migration) opens both.

CREATE OR REPLACE FUNCTION public.ottoq_owner_settings_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  c  public.ottoq_owner_commands;
  sv public.ottoq_owner_saved_settings;
  v_ok boolean;
BEGIN
  IF COALESCE(current_setting('ottoq.agent_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF COALESCE(current_setting('ottoq.retention', true), '') = 'on' THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'ottoq_owner_settings: DELETE refused; an owner setting is withdrawn by an owner command, lifted at its run''s end, and cleared only by the run purge (ottoq.retention)'
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO c FROM public.ottoq_owner_commands x WHERE x.command_id = NEW.command_id;
    --: §14: a 'saved' command (no run live) set nothing on a run, so it reaches a run only as the carry below
    v_ok := c.command_id IS NOT NULL AND c.mode = 'apply' AND c.outcome IN ('applied', 'saved') AND NEW.status = 'active'
        AND c.fleet_operator_id = NEW.fleet_operator_id AND c.depot_id = NEW.depot_id
        AND c.vehicles @> jsonb_build_array(jsonb_build_object('id', NEW.vehicle_id::text))
        AND CASE NEW.kind
              WHEN 'charge_limit' THEN c.tool = 'set_charge_limit' AND (c.args ->> 'percent')::numeric = NEW.charge_limit_pct
              WHEN 'hold'         THEN c.tool = 'hold_vehicle' AND (c.args ->> 'until_sim')::timestamptz = NEW.hold_until_sim
              WHEN 'service'      THEN c.tool = 'request_service' AND c.args ->> 'service' = NEW.service
                                       AND c.args ->> 'when' = NEW.service_when
              ELSE false END;
    IF v_ok AND c.sim_run_id IS DISTINCT FROM NEW.sim_run_id THEN
      --: on another run: only as the carry of a saved row this very command made
      SELECT * INTO sv FROM public.ottoq_owner_saved_settings x WHERE x.saved_id = NEW.saved_id;
      v_ok := sv.saved_id IS NOT NULL AND sv.status = 'active' AND sv.command_id = NEW.command_id
          AND sv.vehicle_id = NEW.vehicle_id AND sv.kind = NEW.kind
          AND sv.charge_limit_pct IS NOT DISTINCT FROM NEW.charge_limit_pct AND sv.service IS NOT DISTINCT FROM NEW.service;
    END IF;
    IF NOT COALESCE(v_ok, false) THEN
      RAISE EXCEPTION 'owner setting for car %: refused, it is not what an applied owner command set (on its run, or saved by it)',
        NEW.vehicle_id USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;
  --: UPDATE
  IF (NEW.setting_id, NEW.sim_run_id, NEW.depot_id, NEW.fleet_operator_id, NEW.vehicle_id, NEW.kind, NEW.charge_limit_pct,
      NEW.hold_until_sim, NEW.service, NEW.service_when, NEW.include_current_visit, NEW.command_id, NEW.set_at, NEW.set_at_sim,
      NEW.saved_id)
     IS DISTINCT FROM
     (OLD.setting_id, OLD.sim_run_id, OLD.depot_id, OLD.fleet_operator_id, OLD.vehicle_id, OLD.kind, OLD.charge_limit_pct,
      OLD.hold_until_sim, OLD.service, OLD.service_when, OLD.include_current_visit, OLD.command_id, OLD.set_at, OLD.set_at_sim,
      OLD.saved_id)
     OR (NEW.replaces_setting_id IS DISTINCT FROM OLD.replaces_setting_id AND NEW.replaces_setting_id IS NOT NULL) THEN
    RAISE EXCEPTION 'owner setting %: what was set is immutable', OLD.setting_id USING ERRCODE = '42501';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT ((OLD.status = 'active' AND NEW.status IN ('replaced', 'withdrawn', 'fulfilled', 'lifted'))
            OR (OLD.status = 'replaced' AND NEW.status = 'active')) THEN
      RAISE EXCEPTION 'owner setting %: % -> % is not a change an owner command, the tick or the run''s end makes',
        OLD.setting_id, OLD.status, NEW.status USING ERRCODE = '42501';
    END IF;
    IF NEW.status IN ('replaced', 'withdrawn')
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_commands x
                        WHERE x.command_id = NEW.closed_by_command_id AND x.outcome = 'applied'
                          AND x.fleet_operator_id = NEW.fleet_operator_id) THEN
      RAISE EXCEPTION 'owner setting %: replaced or withdrawn only by an applied owner command of its fleet', OLD.setting_id
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_saved_settings_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE c public.ottoq_owner_commands;
BEGIN
  IF COALESCE(current_setting('ottoq.agent_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'ottoq_owner_saved_settings keeps what owners saved: DELETE refused; an owner command ends a saved setting'
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO c FROM public.ottoq_owner_commands x WHERE x.command_id = NEW.command_id;
    IF NOT COALESCE(c.mode = 'apply' AND c.outcome IN ('applied', 'saved') AND c.acting_person IS NOT NULL
                    AND c.acting_person = NEW.acting_person AND NEW.status = 'active'
                    AND c.fleet_operator_id = NEW.fleet_operator_id AND c.depot_id = NEW.depot_id
                    AND c.vehicles @> jsonb_build_array(jsonb_build_object('id', NEW.vehicle_id::text))
                    AND CASE NEW.kind
                          WHEN 'charge_limit' THEN c.tool = 'set_charge_limit'
                                                   AND (c.args ->> 'percent')::numeric = NEW.charge_limit_pct
                          WHEN 'service'      THEN c.tool = 'request_service' AND c.args ->> 'service' = NEW.service
                                                   AND c.args ->> 'when' = 'every_return'
                          ELSE false END, false) THEN
      RAISE EXCEPTION 'saved owner setting for car %: refused, it is not what an applied command recorded under a person set',
        NEW.vehicle_id USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;
  IF (NEW.saved_id, NEW.depot_id, NEW.fleet_operator_id, NEW.vehicle_id, NEW.kind, NEW.charge_limit_pct, NEW.service,
      NEW.command_id, NEW.acting_person, NEW.saved_at)
     IS DISTINCT FROM
     (OLD.saved_id, OLD.depot_id, OLD.fleet_operator_id, OLD.vehicle_id, OLD.kind, OLD.charge_limit_pct, OLD.service,
      OLD.command_id, OLD.acting_person, OLD.saved_at) THEN
    RAISE EXCEPTION 'saved owner setting %: what was saved is immutable', OLD.saved_id USING ERRCODE = '42501';
  END IF;
  IF OLD.status = 'active' AND NEW.status = 'ended'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_commands x
                      WHERE x.command_id = NEW.ended_by_command_id AND x.outcome IN ('applied', 'saved') AND x.acting_person IS NOT NULL
                        AND x.fleet_operator_id = NEW.fleet_operator_id) THEN
    RAISE EXCEPTION 'saved owner setting %: ended only by an applied owner command recorded under a person', OLD.saved_id
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $fn$;

CREATE TRIGGER ottoq_owner_settings_guard_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.ottoq_owner_settings
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_settings_guard();
CREATE TRIGGER ottoq_owner_saved_settings_guard_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.ottoq_owner_saved_settings
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_saved_settings_guard();
CREATE TRIGGER ottoq_owner_saved_settings_no_truncate_trg
  BEFORE TRUNCATE ON public.ottoq_owner_saved_settings
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();

-- ══ 11. my_settings says what is saved to the cars ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_owner_settings_read(p_agent public.ottoq_agent_principals, p_read jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721 §11. my_settings (0605's read, unchanged) plus `saved`: what an owner signed in to their OTTOYARD account saved to
   this fleet's cars at this depot, carried from run to run. The summary no longer says everything lifts at the run's end.
   `saved` is shown only to an agent signed in to an OTTOYARD account (ottoq_owner_acting_person): a demo passcode
   session or an issued key gets no `saved` block and no line about it, because what is saved is the account holder's,
   bound for production, and names the person (the re-review: a passcode session read the holder's email here). Who saved
   a row (saved_by) and the command that saved it are shown only to that same person. */
DECLARE
  v_saved  jsonb;
  v_lines  text;
  v_sum    text := COALESCE(p_read ->> 'summary', '');
  v_person text := public.ottoq_owner_acting_person(p_agent);
BEGIN
  v_sum := replace(v_sum, ' Everything lifts when the run ends.',
                   ' Holds, one-time orders and anything set without signing in lift when the run ends.');
  v_sum := replace(v_sum, 'No run is live, so nothing is in force: every car is at baseline.', 'No run is live, so nothing is in force now.');
  IF v_person IS NULL THEN
    RETURN COALESCE(p_read, '{}'::jsonb) || jsonb_build_object('summary', v_sum);
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'saved_id', s.saved_id, 'vehicle_id', s.vehicle_id, 'vehicle', v.display_name, 'kind', s.kind,
           'charge_limit_pct', s.charge_limit_pct, 'service', s.service, 'service_name', c.display_name,
           'when', CASE WHEN s.kind = 'service' THEN 'every_return' END,
           'saved_at', s.saved_at, 'saved_at_local', public.ottoq_owner_clock(s.saved_at, false))
           || CASE WHEN s.acting_person = v_person
                   THEN jsonb_build_object('saved_by', s.acting_person, 'command_id', s.command_id)
                   ELSE '{}'::jsonb END
           ORDER BY s.kind, v.display_name, s.service), '[]'::jsonb)
    INTO v_saved
    FROM public.ottoq_owner_saved_settings s
    JOIN public.vehicles v ON v.id = s.vehicle_id
    LEFT JOIN public.service_cadence_policy c ON c.svc = s.service
   WHERE s.fleet_operator_id = p_agent.fleet_operator_id AND s.depot_id = p_agent.depot_id AND s.status = 'active';
  SELECT string_agg(x.line, '; ' ORDER BY x.ord) INTO v_lines FROM (
    SELECT 1 AS ord, count(*) || CASE WHEN count(*) = 1 THEN ' car charges' ELSE ' cars charge' END
                     || ' to at most ' || (e ->> 'charge_limit_pct') || '%' AS line
      FROM jsonb_array_elements(v_saved) e WHERE e ->> 'kind' = 'charge_limit' GROUP BY e ->> 'charge_limit_pct'
    UNION ALL
    SELECT 2, count(*) || CASE WHEN count(*) = 1 THEN ' car has ' ELSE ' cars have ' END
              || public.ottoq_owner_lc(COALESCE(e ->> 'service_name', e ->> 'service')) || ' on every return'
      FROM jsonb_array_elements(v_saved) e WHERE e ->> 'kind' = 'service' GROUP BY COALESCE(e ->> 'service_name', e ->> 'service')) x;
  IF v_lines IS NOT NULL THEN
    v_sum := v_sum || ' Saved to your cars for every run, production included: ' || v_lines || '.';
  END IF;
  RETURN COALESCE(p_read, '{}'::jsonb) || jsonb_build_object('summary', v_sum, 'saved', v_saved);
END $fn$;

-- ══ 12. the demo passcode opens nothing while a production run is live (the 0721 re-review, item 11) ═══════════════
--
-- Measured (§1(h)): enter_passcode issued a session whatever the live run, and the session read the fleet's cars in
-- production (0721's gate refused only its changes). Now the door refuses to issue one while a production_live run is
-- running or paused at the depot (before the passcode is checked, so it says nothing about the passcode), and §4 refuses
-- every call of a session opened earlier for as long as that run is live. Sign-up, OAuth, keys and every grant are as
-- they were.
DO $door$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_public_call(text,jsonb,text,jsonb,timestamp with time zone)'::regprocedure);
  c_old constant text := E'  -- ── the door: on, and the passcode right ──\n  IF v_status IS NULL THEN\n';
  c_new constant text := E'  -- ── 0721 §12: no session opens while a production run is live at the depot ──\n'
                      || E'  IF v_status IS NULL AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r\n'
                      || E'                                   WHERE r.depot_id = c_twin AND r.run_by = ''production_live''\n'
                      || E'                                     AND r.status IN (''running'', ''paused'')) THEN\n'
                      || E'    v_status := 403; v_code := ''production_live'';\n'
                      || E'    v_msg := ''A production run is live at the twin depot, so the demo passcode opens nothing right now: production is read and changed only by an agent signed in to its owner''''s OTTOYARD account. Nothing was opened. Try again once the production run ends, or sign your agent in to your OTTOYARD account.'';\n'
                      || E'  END IF;\n\n'
                      || E'  -- ── the door: on, and the passcode right ──\n  IF v_status IS NULL THEN\n';
  v_n int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0721: the passcode door''s anchor occurs % times, expected exactly 1', v_n;
  END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $door$;

-- ══ 13. every OTTO-Command model call in the evidence ledger (CLAUDE.md rule 6) ═════════════════════════════════════
--
-- Measured (§1(f)): public.ottoq_model_call_ledger holds no Anthropic row: the owner door's model calls were nowhere.
-- The gateway now records each one after it returns, fire-and-forget (a ledger failure never fails an ask), through this
-- function, which only service_role (the gateway's key) may execute. It takes a closed object of ids, counts, codes and
-- the model's name, validates every field, and writes through 0340's writer (public.ottoq_log_model_call) as provider
-- 'anthropic_ottocommand', role 'owner_agent' (not 'agent': the view's agent_calls_with_no_l1_rules counts the tick's
-- advisor, and an owner's ask is judged by the owner door, not the shield), endpoint the Messages API, chain_id the ask.
-- No prompt, no answer, no thinking and no owner words can reach it: an unknown key is refused, and every text field is
-- an enum or a pattern no sentence fits.
CREATE OR REPLACE FUNCTION public.ottoq_ottocommand_record_model_call(p_entry jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  e       jsonb := COALESCE(p_entry, '{}'::jsonb);
  v_bad   text;
  c_keys  constant text[] := ARRAY['ask_id', 'ask_kind', 'round', 'model_requested', 'model', 'http_status', 'latency_ms',
                                   'outcome', 'stop_reason', 'web_search_requests', 'input_tokens', 'output_tokens',
                                   'fell_back', 'refusal_category', 'effort', 'depot_id', 'sim_run_id', 'gateway_call_id'];
  c_model constant text := '^[A-Za-z0-9][A-Za-z0-9._:@\[\]-]{0,99}$';
  c_uuid  constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_int   constant text := '^[0-9]{1,9}$';
BEGIN
  IF jsonb_typeof(e) <> 'object' THEN
    RAISE EXCEPTION 'ottoq_ottocommand_record_model_call: the entry is a JSON object' USING ERRCODE = '22023';
  END IF;
  SELECT string_agg(k, ', ' ORDER BY k) INTO v_bad FROM jsonb_object_keys(e) k WHERE k <> ALL (c_keys);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'ottoq_ottocommand_record_model_call: unknown field(s) %', v_bad USING ERRCODE = '22023';
  END IF;
  v_bad := concat_ws(', ',
    CASE WHEN COALESCE(e ->> 'ask_id', '') !~ '^[A-Za-z0-9-]{1,64}$' THEN 'ask_id' END,
    CASE WHEN COALESCE(e ->> 'ask_kind', '') NOT IN ('ask', 'search') THEN 'ask_kind' END,
    CASE WHEN COALESCE(e ->> 'round', '') !~ v_int OR (e ->> 'round')::int NOT BETWEEN 1 AND 50 THEN 'round' END,
    CASE WHEN jsonb_typeof(e -> 'model_requested') NOT IN ('null', 'string') OR COALESCE(e ->> 'model_requested', 'x') !~ c_model THEN 'model_requested' END,
    CASE WHEN jsonb_typeof(e -> 'model') NOT IN ('null', 'string') OR COALESCE(e ->> 'model', 'x') !~ c_model THEN 'model' END,
    CASE WHEN e ? 'http_status' AND jsonb_typeof(e -> 'http_status') <> 'null'
              AND (COALESCE(e ->> 'http_status', '') !~ v_int OR (e ->> 'http_status')::int NOT BETWEEN 100 AND 599) THEN 'http_status' END,
    CASE WHEN COALESCE(e ->> 'latency_ms', '') !~ v_int OR (e ->> 'latency_ms')::int > 600000 THEN 'latency_ms' END,
    CASE WHEN COALESCE(e ->> 'outcome', '') NOT IN ('answered', 'refused', 'error') THEN 'outcome' END,
    CASE WHEN jsonb_typeof(e -> 'stop_reason') NOT IN ('null', 'string') OR COALESCE(e ->> 'stop_reason', 'x') !~ '^[a-z_]{1,40}$' THEN 'stop_reason' END,
    CASE WHEN COALESCE(e ->> 'web_search_requests', '') !~ v_int OR (e ->> 'web_search_requests')::int > 50 THEN 'web_search_requests' END,
    CASE WHEN jsonb_typeof(e -> 'input_tokens') NOT IN ('null', 'number') OR COALESCE(e ->> 'input_tokens', '0') !~ v_int THEN 'input_tokens' END,
    CASE WHEN jsonb_typeof(e -> 'output_tokens') NOT IN ('null', 'number') OR COALESCE(e ->> 'output_tokens', '0') !~ v_int THEN 'output_tokens' END,
    CASE WHEN jsonb_typeof(e -> 'fell_back') IS DISTINCT FROM 'boolean' THEN 'fell_back' END,
    CASE WHEN jsonb_typeof(e -> 'refusal_category') NOT IN ('null', 'string') OR COALESCE(e ->> 'refusal_category', 'x') !~ '^[a-z_]{1,40}$' THEN 'refusal_category' END,
    CASE WHEN jsonb_typeof(e -> 'effort') NOT IN ('null', 'string') OR COALESCE(e ->> 'effort', 'low') NOT IN ('low', 'medium', 'high', 'xhigh', 'max') THEN 'effort' END,
    CASE WHEN jsonb_typeof(e -> 'depot_id') NOT IN ('null', 'string') OR COALESCE(e ->> 'depot_id', '00000000-0000-0000-0000-000000000000') !~ c_uuid THEN 'depot_id' END,
    CASE WHEN jsonb_typeof(e -> 'sim_run_id') NOT IN ('null', 'string') OR COALESCE(e ->> 'sim_run_id', '00000000-0000-0000-0000-000000000000') !~ c_uuid THEN 'sim_run_id' END,
    CASE WHEN jsonb_typeof(e -> 'gateway_call_id') NOT IN ('null', 'number') OR COALESCE(e ->> 'gateway_call_id', '0') !~ '^[0-9]{1,18}$' THEN 'gateway_call_id' END);
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'ottoq_ottocommand_record_model_call: invalid field(s) %', v_bad USING ERRCODE = '22023';
  END IF;
  RETURN public.ottoq_log_model_call(
    p_provider    := 'anthropic_ottocommand',
    p_role        := 'owner_agent',
    p_outcome     := e ->> 'outcome',
    p_sim_run_id  := (e ->> 'sim_run_id')::uuid,
    p_depot_id    := (e ->> 'depot_id')::uuid,
    p_chain_id    := e ->> 'ask_id',
    p_model       := COALESCE(e ->> 'model', e ->> 'model_requested'),
    p_endpoint    := 'https://api.anthropic.com/v1/messages',
    p_http_status := (e ->> 'http_status')::int,
    p_latency_ms  := (e ->> 'latency_ms')::int,
    p_rationale_present := false,
    p_detail      := jsonb_strip_nulls(jsonb_build_object(
                       'ask_kind', e ->> 'ask_kind', 'round', (e ->> 'round')::int,
                       'model_requested', e ->> 'model_requested', 'stop_reason', e ->> 'stop_reason',
                       'web_search_requests', (e ->> 'web_search_requests')::int,
                       'input_tokens', (e ->> 'input_tokens')::bigint, 'output_tokens', (e ->> 'output_tokens')::bigint,
                       'fell_back', (e ->> 'fell_back')::boolean, 'refusal_category', e ->> 'refusal_category',
                       'effort', e ->> 'effort', 'gateway_call_id', (e ->> 'gateway_call_id')::bigint)),
    p_source_kind := 'live');
END $fn$;

REVOKE ALL ON FUNCTION
  public.ottoq_owner_settings_save(),
  public.ottoq_owner_settings_saved_follow(),
  public.ottoq_owner_saved_carry(uuid),
  public.ottoq_tg_owner_saved_on_run_start(),
  public.ottoq_owner_settings_guard(),
  public.ottoq_owner_saved_settings_guard(),
  public.ottoq_owner_settings_read(public.ottoq_agent_principals, jsonb),
  public.ottoq_ottocommand_record_model_call(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
--: the one grant this file makes: the gateway records its own model calls (the Supabase docs on calling a database
--: function through the REST API: https://supabase.com/docs/guides/database/functions, read 2026-10-14)
GRANT EXECUTE ON FUNCTION public.ottoq_ottocommand_record_model_call(jsonb) TO service_role;

COMMENT ON FUNCTION public.ottoq_ottocommand_record_model_call(jsonb) IS
'0721. Records one OTTO-Command model call (the owner door of ottoq-agent-gateway: an ask or a search) in public.ottoq_model_call_ledger as provider anthropic_ottocommand, role owner_agent: ids, counts, codes and the model''s name only, every field validated, unknown fields refused, so no prompt, answer, thinking or owner words can be stored. service_role only (the gateway). CLAUDE.md rule 6.';
COMMENT ON FUNCTION public.ottoq_owner_saved_carry(uuid) IS
'0721. Carries every active saved owner setting at a run''s depot onto that run (a demo or production run), once per run: only while the car is still that owner''s, when the run has no setting of that kind for the car, a limit only inside the contract in force, an order only for a requestable, unblocked service. Called by the run-start triggers ottoq_sim_runs_carry_saved_owner_settings(_on_start).';

-- ══ V1: the bodies say what this file says they do ══════════════════════════════════════════════════════════════════
DO $v1$
DECLARE
  v_cmd   text := pg_get_functiondef('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb,text)'::regprocedure);
  v_three text := pg_get_functiondef('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)'::regprocedure);
  v_call  text := pg_get_functiondef('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure);
  v_reply text := pg_get_functiondef('public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure);
  v_who   text := pg_get_functiondef('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure);
  v_guard text := pg_get_functiondef('public.ottoq_owner_commands_guard()'::regprocedure);
  v_bind  text := pg_get_functiondef('public.ottoq_owner_confirm_binding(public.ottoq_agent_principals,uuid,text,jsonb,text,text,uuid,boolean)'::regprocedure);
BEGIN
  IF strpos(v_cmd, 'v_gate := public.ottoq_owner_write_gate(p_agent, v_run);') = 0
     OR strpos(v_cmd, 'v_bind := public.ottoq_owner_confirm_binding(p_agent, v_run_id, v_tool, v_norm, v_hash, v_expect, v_confirms,') = 0
     OR strpos(v_cmd, 'v_door        text := CASE p_via WHEN ''ask'' THEN ''ottocommand'' ELSE ''direct'' END;') = 0
     OR strpos(v_cmd, 'ELSE' || chr(10) || '      v_via := ''confirm'';') = 0
     OR strpos(v_cmd, '''confirm_not_through_ottocommand''') = 0
     OR strpos(v_cmd, 'v_person, v_via, v_bound)') = 0
     OR strpos(v_cmd, 'IF v_refusal IS NULL AND NOT v_demo THEN') > 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the four-argument owner command is not the patched body';
  END IF;
  IF strpos(v_three, 'RETURN public.ottoq_owner_command(p_agent, p_tool, p_args, NULL::text);') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the three-argument owner command does not delegate';
  END IF;
  IF strpos(v_call, 'public.ottoq_owner_command(v_agent, v_tool, v_args, v_transport)') = 0
     OR strpos(v_call, 'p_transport IN (''rest'', ''mcp'', ''ask'', ''confirm'')') = 0
     OR strpos(v_call, 'v_data #>> ''{refusal,code}'' = ''confirm_required'' THEN 422') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: ottoq_agent_call does not admit the confirm door, pass its transport or answer confirm_required 422';
  END IF;
  IF strpos(v_reply, '''acting_person'', p_c.acting_person, ''via'', p_c.via, ''confirms_command_id'', p_c.confirms_command_id') = 0
     OR strpos(v_reply, '''expect_plan_hash'', p_c.plan_hash, ''confirms_command_id'', p_c.command_id') = 0
     OR strpos(v_who, '''changes'', public.ottoq_owner_write_gate(p_agent, v_run)') = 0
     OR strpos(v_guard, 'NEW.confirms_command_id)') = 0 OR strpos(v_guard, 'OLD.confirms_command_id)') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the receipt, whoami or the guard is not patched';
  END IF;
  IF strpos(v_bind, 'p.created_at >= now() - interval ''15 minutes''') = 0 OR strpos(v_bind, 'p.principal_id = p_agent.principal_id') = 0
     OR strpos(v_bind, 'a.confirms_command_id = p.command_id') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the binding does not hold a confirm to the same principal, 15 minutes and one apply';
  END IF;
  -- §9-§13
  IF strpos(v_cmd, '(v_lowers AND (v_production OR v_person IS NOT NULL))') = 0
     OR strpos(v_cmd, 'AND v_pct < LEAST(v_ceiling, COALESCE((SELECT s.charge_limit_pct FROM public.ottoq_owner_saved_settings s') = 0
     OR strpos(v_cmd, '''made_on_an_earlier_run''') = 0
     OR strpos(v_cmd, 'This is saved to your cars: it stays from run to run, production included, until you change it.') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the owner command does not bind a signed-in owner''s lowering, or does not say what is saved';
  END IF;
  --: §9 (the re-review): a person's clear, limit or cancel decides what is saved even where no run row carries it
  IF strpos(v_cmd, 'public.ottoq_owner_saved_effect(v_veh, ''charge_limit'', NULL,') = 0
     OR strpos(v_cmd, 'public.ottoq_owner_saved_effect(v_veh, ''service'', v_sv.service, NULL, NULL)') = 0
     OR strpos(v_cmd, 'AND COALESCE(e ->> ''key'', '''') NOT LIKE ''saved:%'' LOOP') = 0
     OR strpos(v_cmd, 'WHERE COALESCE(e ->> ''key'', '''') LIKE ''saved:%'' AND COALESCE((e ->> ''change'')::boolean, false) LOOP') = 0
     OR strpos(v_cmd, '(v_e ->> ''after'')::numeric, v_cmd.command_id, v_person);') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the owner command does not carry a person''s change to what is saved where the run does not';
  END IF;
  IF strpos(v_call, 'IF v_agent.origin = ''passcode'' AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r') = 0
     OR strpos(v_call, 'public.ottoq_owner_settings_read(v_agent, public.ottoq_owner_read(v_agent, ''my_settings'', v_args))') = 0
     OR strpos(v_reply, 'Saved to the cars: it stays from run to run') = 0
     OR strpos(v_who, 'is saved to the car and stays from run to run') = 0
     OR strpos(pg_get_functiondef('public.ottoq_tg_lift_owner_settings_on_terminal()'::regprocedure),
               'AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings s') = 0
     OR strpos(pg_get_functiondef('public.ottoq_agent_public_call(text,jsonb,text,jsonb,timestamp with time zone)'::regprocedure),
               'v_status := 403; v_code := ''production_live'';') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the dispatcher, the receipt, whoami, the run''s end or the passcode door is not patched for §9-§12';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_owner_settings_guard_trg' AND tgrelid = 'public.ottoq_owner_settings'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_owner_settings_save_trg' AND tgrelid = 'public.ottoq_owner_settings'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_owner_saved_settings_guard_trg')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_sim_runs_carry_saved_owner_settings')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_sim_runs_carry_saved_owner_settings_on_start') THEN
    RAISE EXCEPTION '0721 V1 FAILED: a §9/§10 trigger is missing';
  END IF;
  --: §14: with no run live a signed-in owner saves to the cars only, recorded as 'saved', and a preview binds by "no run"
  IF strpos(v_cmd, 'IF v_refusal IS NULL AND v_tool IN (''set_charge_limit'', ''clear_charge_limit'') AND v_run_id IS NULL THEN') = 0
     OR strpos(v_cmd, 'ELSIF v_refusal IS NULL AND v_tool = ''request_service'' AND v_run_id IS NULL THEN') = 0
     OR strpos(v_cmd, '''needs_a_live_run''') = 0 OR strpos(v_cmd, '''made_with_no_run_live''') = 0
     OR strpos(v_cmd, 'WHEN v_changed = 0 THEN ''no_change'' WHEN v_run_id IS NULL THEN ''saved'' ELSE ''applied'' END,') = 0
     OR strpos(v_cmd, 'IF v_cmd.outcome IN (''applied'', ''saved'') THEN') = 0
     OR strpos(v_cmd, 'public.ottoq_owner_saved_effect(v_veh, ''every_return'', v_service, NULL, NULL)') = 0
     OR strpos(v_bind, 'p.sim_run_id IS NOT DISTINCT FROM p_run') = 0 OR strpos(v_bind, 'p.sim_run_id = p_run') > 0
     OR strpos(v_reply, '''expires'', CASE WHEN p_c.outcome IN (''applied'', ''saved'')') = 0
     OR strpos(v_call, 'WHEN v_data ->> ''outcome'' IN (''applied'', ''saved'') AND NOT COALESCE') = 0
     OR strpos(pg_get_functiondef('public.ottoq_owner_write_gate(public.ottoq_agent_principals,jsonb)'::regprocedure),
               '''run_kind'', ''none'', ''person'', v_person, ''saved'', true, ''saved_only'', true') = 0
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.ottoq_owner_commands'::regclass
                       AND conname = 'ottoq_owner_commands_saved_check')
     OR strpos((SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_owner_commands'::regclass
                   AND c.conname = 'ottoq_owner_commands_mode_outcome_check'), '''saved''::text') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the owner door does not save to the cars with no run live (§14)';
  END IF;
  RAISE NOTICE '0721 V1 PASSED';
END $v1$;

-- ══ V2: no client role reaches anything new; the gateway's one door is unchanged ════════════════════════════════════
DO $v2$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(f || ' ' || r, ', ') INTO v_bad
    FROM unnest(ARRAY['public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb,text)',
                      'public.ottoq_owner_write_gate(public.ottoq_agent_principals,jsonb)',
                      'public.ottoq_owner_acting_person(public.ottoq_agent_principals)',
                      'public.ottoq_owner_confirm_binding(public.ottoq_agent_principals,uuid,text,jsonb,text,text,uuid,boolean)',
                      'public.ottoq_owner_commands_backstop()',
                      'public.ottoq_owner_settings_save()',
                      'public.ottoq_owner_settings_saved_follow()',
                      'public.ottoq_owner_saved_carry(uuid)',
                      'public.ottoq_owner_saved_effect(public.vehicles,text,text,numeric,numeric)',
                      'public.ottoq_tg_owner_saved_on_run_start()',
                      'public.ottoq_owner_settings_guard()',
                      'public.ottoq_owner_saved_settings_guard()',
                      'public.ottoq_owner_settings_read(public.ottoq_agent_principals,jsonb)']) f
   CROSS JOIN unnest(ARRAY['anon', 'authenticated', 'service_role']) r
   WHERE has_function_privilege(r, f, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 V2 FAILED: a client role can execute %', v_bad;
  END IF;
  -- §13: the model ledger's door is the gateway's (service_role) and no browser role's
  IF NOT has_function_privilege('service_role', 'public.ottoq_ottocommand_record_model_call(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_ottocommand_record_model_call(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_ottocommand_record_model_call(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '0721 V2 FAILED: ottoq_ottocommand_record_model_call is not service_role only';
  END IF;
  -- §9-§10: no client role holds any privilege on the owner tables
  SELECT string_agg(t || ' ' || r, ', ') INTO v_bad
    FROM unnest(ARRAY['public.ottoq_owner_saved_settings', 'public.ottoq_owner_settings']) t
   CROSS JOIN unnest(ARRAY['anon', 'authenticated', 'service_role']) r
   WHERE has_table_privilege(r, t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 V2 FAILED: a client role holds a privilege on %', v_bad;
  END IF;
  IF NOT has_function_privilege('service_role', 'public.ottoq_agent_call(text,text,jsonb,text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '0721 V2 FAILED: the gateway (service_role) lost ottoq_agent_call';
  END IF;
  RAISE NOTICE '0721 V2 PASSED';
END $v2$;

-- ══ V3: a production session at the twin depot, probed end to end through the dispatcher, then rolled back ══════════
--
-- Everything it writes -- a paused production_live run copied from the newest twin-depot run (paused, so the
-- one-running-run index never meets it; the newest run, so ottoq_agent_live_run answers with it), a probe sign-in (client,
-- account, two connections, their access tokens), a passcode session, an issued key, their commands and settings, the
-- ledger rows -- is in a block that raises at its end and is rolled back. Only the answers, held in variables, survive it.
-- It probes the binding (rule 9): a lowering sent in one call is recorded as a preview and applies nothing; its confirm,
-- sent by the OTHER connection, applies nothing; sent by the agent that made it, applies once and is recorded as via
-- 'confirm' naming the preview; sent again, applies nothing; a raise is one call; the undo of that raise (which puts the
-- lower limit back) is gated the same way and applies only as its own preview's confirm. A preview older than 15 minutes
-- cannot be made inside one transaction (now() does not move), so expiry is proved by the test suite, not here.
DO $v3$
DECLARE
  c_twin   constant uuid := '11111111-1111-1111-1111-111111111111';
  c_email  constant text := 'v0721.probe@ottoyard.invalid';
  v_run    uuid := gen_random_uuid();
  v_tpl    uuid;
  v_cols   text;
  v_fleet  uuid;
  v_ctr    jsonb;
  v_low    numeric;
  v_mid    numeric;
  v_client text := 'oqc_' || md5('0721-client' || clock_timestamp()::text);
  v_acct   uuid := gen_random_uuid();
  v_pid    uuid;
  v_oauth  text := 'oqt_' || md5('0721-oauth-a' || clock_timestamp()::text) || md5('0721-oauth-b' || clock_timestamp()::text);
  v_pid2   uuid;
  v_oauth2 text := 'oqt_' || md5('0721-oauth-c' || clock_timestamp()::text) || md5('0721-oauth-d' || clock_timestamp()::text);
  v_pass   text := 'oqs_' || md5('0721-pass-a' || clock_timestamp()::text) || md5('0721-pass-b' || clock_timestamp()::text);
  v_key    text;
  v_th     text;
  v_car    uuid;
  r_whoami jsonb; r_lower jsonb; r_confirm jsonb; r_again jsonb; r_mid jsonb; r_undo jsonb; r_clear jsonb;
  r_pass jsonb; r_key jsonb; r_demo jsonb; r_other jsonb; r_undone jsonb;
  v_t_confirm numeric;
  v_t_undo    numeric;
  v_t_other   numeric;
  v_t_undone  numeric;
  v_prev   uuid;
  v_cmd    uuid;
  v_ledger text;
  v_twice  text := 'not reached';
  v_bogus  text := 'not reached';
  v_guard  text := 'not reached';
  v_back   text := 'not reached';
  --: §9-§13
  v_run2      uuid := gen_random_uuid();
  v_saved     int;
  v_carried   int;
  v_t_carried numeric;
  v_lifted    timestamptz;
  v_saved_after int;
  r_enter     jsonb;
  v_fake      text := 'not reached';
  v_del       text := 'not reached';
  v_upd       text := 'not reached';
  v_ledger_id bigint;
  v_ledger_row text;
  v_ledger_bad text := 'not reached';
BEGIN
  SELECT r.sim_run_id INTO v_tpl FROM public.ottoq_sim_runs r WHERE r.depot_id = c_twin ORDER BY r.started_at DESC LIMIT 1;
  --: the twin depot's owner with the most cars and a contract range at least 3 points wide (a lower limit, then a raise
  --: that stays under the top)
  SELECT v.fleet_operator_id INTO v_fleet
    FROM public.vehicles v
   WHERE (v.current_depot_id = c_twin OR v.home_depot_id = c_twin) AND v.fleet_operator_id IS NOT NULL
     AND (public.ottoq_owner_contract(v.fleet_operator_id, now()) ->> 'min_charge_pct')::numeric + 3
         <= (public.ottoq_owner_contract(v.fleet_operator_id, now()) ->> 'max_charge_pct')::numeric
   GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1;
  IF v_tpl IS NULL OR v_fleet IS NULL THEN
    RAISE EXCEPTION '0721 V3: no twin-depot run to copy, or no owner at the twin depot with a contract range to probe';
  END IF;
  v_ctr := public.ottoq_owner_contract(v_fleet, now());
  v_low := GREATEST((v_ctr ->> 'min_charge_pct')::numeric, (v_ctr ->> 'max_charge_pct')::numeric - 5);
  v_mid := v_low + 2;
  SELECT string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position) INTO v_cols
    FROM information_schema.columns c
   WHERE c.table_schema = 'public' AND c.table_name = 'ottoq_sim_runs'
     AND c.column_name NOT IN ('sim_run_id', 'status', 'started_at', 'run_by')
     AND COALESCE(c.column_default, '') NOT LIKE 'nextval(%' AND c.is_identity = 'NO' AND c.is_generated = 'NEVER';

  BEGIN
    EXECUTE format('INSERT INTO public.ottoq_sim_runs (sim_run_id, status, started_at, run_by, %1$s) '
                   'SELECT $1, ''paused'', clock_timestamp(), ''production_live'', %1$s FROM public.ottoq_sim_runs WHERE sim_run_id = $2',
                   v_cols) USING v_run, v_tpl;
    INSERT INTO public.ottoq_oauth_clients (client_id, client_name, grant_types)
    VALUES (v_client, '0721 probe', ARRAY['urn:ietf:params:oauth:grant-type:device_code']);
    INSERT INTO public.ottoq_owner_accounts (account_id, email, fleet_operator_id, note)
    VALUES (v_acct, c_email, v_fleet, '0721 V3 probe, rolled back');
    v_pid := public.ottoq_oauth_connect(v_acct, v_client, 'ottoyard:owner', 'https://probe.invalid/account/mcp', 'device_code');
    INSERT INTO public.ottoq_oauth_tokens (token_hash, kind, principal_id, expires_at)
    VALUES (public.ottoq_oauth_sha256(v_oauth), 'access', v_pid, now() + interval '10 minutes');
    --: a second agent signed in to the same person's account: another principal, which confirms only its own previews
    v_pid2 := public.ottoq_oauth_connect(v_acct, v_client, 'ottoyard:owner', 'https://probe.invalid/account/mcp', 'device_code');
    INSERT INTO public.ottoq_oauth_tokens (token_hash, kind, principal_id, expires_at)
    VALUES (public.ottoq_oauth_sha256(v_oauth2), 'access', v_pid2, now() + interval '10 minutes');
    INSERT INTO public.ottoq_agent_principals (name, kind, depot_id, fleet_operator_id, capabilities, token_hash, token_prefix,
                                              origin, display_name, expires_at, note)
    VALUES ('v0721-probe-passcode', 'personal', c_twin, v_fleet, ARRAY['note', 'owner_settings', 'read'],
            public.ottoq_oauth_sha256(v_pass), left(v_pass, 12), 'passcode', '0721 probe', now() + interval '10 minutes',
            '0721 V3 probe, rolled back');
    v_key := public.ottoq_agent_issue_token('v0721-probe-key', 'personal', ARRAY['read', 'note', 'owner_settings'], v_fleet,
                                            c_twin, '0721 V3 probe, rolled back', 600, 20) ->> 'token';
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.fleet_operator_id = v_fleet AND (v.current_depot_id = c_twin OR v.home_depot_id = c_twin)
     ORDER BY v.display_name, v.id LIMIT 1;
    v_th := public.ottoq_oauth_sha256(v_oauth);

    r_whoami := public.ottoq_agent_call(v_th, 'whoami', '{}'::jsonb, 'mcp', '{}'::jsonb);
    -- 1. the person's agent lowers the limit in one call: nothing is applied; OTTO-Q records it as a preview under the
    --    person and answers confirm_required
    r_lower := public.ottoq_agent_call(v_th, 'set_charge_limit', jsonb_build_object('vehicles', 'all', 'percent', v_low),
                                       'mcp', '{}'::jsonb);
    v_prev := (r_lower #>> '{data,command,command_id}')::uuid;
    -- 1b. that preview's confirm, sent by another agent signed in to the same account: not its preview, so nothing applies
    r_other := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_oauth2), r_lower #>> '{data,confirm,tool}',
                                       r_lower #> '{data,confirm,args}', 'confirm', '{}'::jsonb);
    v_t_other := public.ottoq_effective_target_soc_at(v_car, now());
    -- 2. that preview's confirm object, sent back through the confirm door: applied once, bound to the preview
    r_confirm := public.ottoq_agent_call(v_th, r_lower #>> '{data,confirm,tool}', r_lower #> '{data,confirm,args}', 'confirm',
                                         '{}'::jsonb);
    v_t_confirm := public.ottoq_effective_target_soc_at(v_car, now());
    v_cmd := (r_confirm #>> '{data,command,command_id}')::uuid;
    -- 2b. (§9) what the person confirmed is saved to the cars, and carried onto the next production run: a second run,
    --     started earlier than the probe run so the probe run stays the live one, carries it; ending that run lifts it from
    --     the run and does not stamp the command as lifted
    SELECT count(*) INTO v_saved FROM public.ottoq_owner_saved_settings s WHERE s.command_id = v_cmd AND s.status = 'active';
    EXECUTE format('INSERT INTO public.ottoq_sim_runs (sim_run_id, status, started_at, run_by, %1$s) '
                   'SELECT $1, ''paused'', clock_timestamp() - interval ''1 day'', ''production_live'', %1$s FROM public.ottoq_sim_runs WHERE sim_run_id = $2',
                   v_cols) USING v_run2, v_tpl;
    SELECT count(*) INTO v_carried FROM public.ottoq_owner_settings o
     WHERE o.sim_run_id = v_run2 AND o.saved_id IS NOT NULL AND o.status = 'active' AND o.command_id = v_cmd;
    PERFORM set_config('ottoq.sim_run_id', v_run2::text, true);
    v_t_carried := public.ottoq_effective_target_soc_at(v_car, now());
    PERFORM set_config('ottoq.sim_run_id', '', true);
    UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = v_run2;
    SELECT c.lifted_at INTO v_lifted FROM public.ottoq_owner_commands c WHERE c.command_id = v_cmd;
    SELECT count(*) INTO v_saved_after FROM public.ottoq_owner_saved_settings s WHERE s.command_id = v_cmd AND s.status = 'active';
    SELECT l.transport INTO v_ledger FROM public.ottoq_agent_call_ledger l WHERE l.call_id = (r_confirm ->> 'call_id')::bigint;
    -- 3. the same confirm again applies nothing; a second apply naming the preview, written straight into the table, is
    --    refused by the unique index; and a confirm naming a command that is no preview is refused by the backstop
    r_again := public.ottoq_agent_call(v_th, r_lower #>> '{data,confirm,tool}', r_lower #> '{data,confirm,args}', 'confirm',
                                       '{}'::jsonb);
    BEGIN
      INSERT INTO public.ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool, mode,
                                               outcome, summary, plan_hash, acting_person, via, confirms_command_id)
      VALUES (v_pid, '0721 probe', v_fleet, c_twin, v_run, 'set_charge_limit', 'apply', 'applied', '0721 double-confirm probe',
              r_lower #>> '{data,command,plan_hash}', c_email, 'confirm', v_prev);
      v_twice := 'inserted';
    EXCEPTION WHEN unique_violation THEN v_twice := 'refused';
    END;
    BEGIN
      INSERT INTO public.ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool, mode,
                                               outcome, summary, plan_hash, acting_person, via, confirms_command_id)
      VALUES (v_pid, '0721 probe', v_fleet, c_twin, v_run, 'set_charge_limit', 'apply', 'applied', '0721 bogus-confirm probe',
              r_confirm #>> '{data,command,plan_hash}', c_email, 'confirm', v_cmd);
      v_bogus := 'inserted';
    EXCEPTION WHEN insufficient_privilege THEN v_bogus := 'refused';
    END;
    -- 4. raising is one call; undoing that raise puts the lower limit back, so it is gated like a new lower limit
    r_mid := public.ottoq_agent_call(v_th, 'set_charge_limit', jsonb_build_object('vehicles', 'all', 'percent', v_mid),
                                     'rest', '{}'::jsonb);
    r_undo := public.ottoq_agent_call(v_th, 'undo_command', jsonb_build_object('command_id', r_mid #>> '{data,command,command_id}'),
                                      'mcp', '{}'::jsonb);
    v_t_undo := public.ottoq_effective_target_soc_at(v_car, now());
    --    the undo's recorded preview, confirmed by the agent that made it: applied, bound to it, the lower limit back
    r_undone := public.ottoq_agent_call(v_th, r_undo #>> '{data,confirm,tool}', r_undo #> '{data,confirm,args}', 'confirm',
                                        '{}'::jsonb);
    v_t_undone := public.ottoq_effective_target_soc_at(v_car, now());
    -- 5. the guard holds the person, the door and the preview; the backstop refuses an applied production row with no person
    BEGIN
      UPDATE public.ottoq_owner_commands SET via = 'direct', confirms_command_id = NULL WHERE command_id = v_cmd;
      v_guard := 'updated';
    EXCEPTION WHEN insufficient_privilege THEN v_guard := 'refused';
    END;
    BEGIN
      INSERT INTO public.ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool,
                                               mode, outcome, summary)
      VALUES (v_pid, '0721 probe', v_fleet, c_twin, v_run, 'clear_charge_limit', 'apply', 'applied', '0721 backstop probe');
      v_back := 'inserted';
    EXCEPTION WHEN insufficient_privilege THEN v_back := 'refused';
    END;
    -- 6. clearing back to full is one call, and a "via" among the arguments is ignored: the door is the transport's
    r_clear := public.ottoq_agent_call(v_th, 'clear_charge_limit', jsonb_build_object('vehicles', 'all', 'via', 'ottocommand'),
                                       'rest', '{}'::jsonb);
    -- 7. a passcode session and an issued key name no person: refused in production
    r_pass := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_pass), 'set_charge_limit',
                jsonb_build_object('vehicles', 'all', 'percent', v_low, 'mode', 'preview'), 'mcp', '{}'::jsonb);
    r_key := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_key), 'hold_vehicle',
               jsonb_build_object('vehicles', 'all', 'for_minutes', 30), 'rest', '{}'::jsonb);
    -- 7b. (§12) and the demo passcode opens no new session while the production run is live
    r_enter := public.ottoq_agent_call(NULL, 'enter_passcode', jsonb_build_object('passcode', 'v0721-not-the-passcode', 'agent', 'probe'),
                                       'mcp', '{"ip": "192.0.2.211"}'::jsonb);
    -- 7c. (§10) a setting no command made, a deletion, and an edit of what was set are refused, whoever writes them
    BEGIN
      INSERT INTO public.ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct,
                                              command_id, set_at_sim)
      VALUES (v_run, c_twin, v_fleet, v_car, 'charge_limit', 50, (r_mid #>> '{data,command,command_id}')::uuid, now());
      v_fake := 'inserted';
    EXCEPTION WHEN insufficient_privilege THEN v_fake := 'refused';
    END;
    BEGIN
      DELETE FROM public.ottoq_owner_settings o WHERE o.sim_run_id = v_run;
      v_del := 'deleted';
    EXCEPTION WHEN insufficient_privilege THEN v_del := 'refused';
    END;
    BEGIN
      UPDATE public.ottoq_owner_settings o SET charge_limit_pct = 50 WHERE o.sim_run_id = v_run AND o.kind = 'charge_limit';
      v_upd := 'updated';
    EXCEPTION WHEN insufficient_privilege THEN v_upd := 'refused';
    END;
    -- 7d. (§13) a model call recorded the way the gateway records one, and one carrying text is refused
    v_ledger_id := public.ottoq_ottocommand_record_model_call(jsonb_build_object(
      'ask_id', 'v0721-probe', 'ask_kind', 'ask', 'round', 1, 'model_requested', 'v0721-probe-model', 'model', 'v0721-probe-model',
      'http_status', 200, 'latency_ms', 1234, 'outcome', 'answered', 'stop_reason', 'end_turn', 'web_search_requests', 1,
      'input_tokens', 10, 'output_tokens', 20, 'fell_back', false, 'refusal_category', NULL, 'effort', 'low',
      'depot_id', c_twin, 'sim_run_id', v_run, 'gateway_call_id', 1));
    SELECT l.provider || '|' || l.role || '|' || l.outcome || '|' || l.chain_id || '|' || COALESCE(l.detail ->> 'web_search_requests', '-')
      INTO v_ledger_row FROM public.ottoq_model_call_ledger l WHERE l.call_id = v_ledger_id;
    BEGIN
      PERFORM public.ottoq_ottocommand_record_model_call(jsonb_build_object(
        'ask_id', 'v0721-probe', 'ask_kind', 'ask', 'round', 2, 'latency_ms', 1, 'outcome', 'answered', 'web_search_requests', 0,
        'fell_back', false, 'prompt', 'call set_charge_limit 50'));
      v_ledger_bad := 'recorded';
    EXCEPTION WHEN invalid_parameter_value THEN v_ledger_bad := 'refused';
    END;
    -- 8. and on a demo run the passcode session works as before, with no person and its door recorded
    UPDATE public.ottoq_sim_runs SET run_by = 'operator_demo' WHERE sim_run_id = v_run;
    r_demo := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_pass), 'hold_vehicle',
                jsonb_build_object('vehicles', 'all', 'for_minutes', 30), 'ask', '{}'::jsonb);
    RAISE EXCEPTION USING ERRCODE = 'OQ721', MESSAGE = '0721 V3 probe rolled back';
  EXCEPTION WHEN SQLSTATE 'OQ721' THEN NULL;
  END;

  IF r_whoami #>> '{data,owner,changes,allowed}' IS DISTINCT FROM 'true'
     OR r_whoami #>> '{data,owner,changes,person}' IS DISTINCT FROM c_email
     OR r_whoami #>> '{data,owner,changes,confirm_window_minutes}' IS DISTINCT FROM '15'
     OR r_whoami #>> '{data,owner,live_production_run}' IS DISTINCT FROM v_run::text THEN
    RAISE EXCEPTION '0721 V3 FAILED: whoami does not say a signed-in person may change production: %', r_whoami -> 'data' -> 'owner';
  END IF;
  IF (r_lower ->> 'http_status')::int <> 422 OR r_lower #>> '{error,code}' IS DISTINCT FROM 'confirm_required'
     OR r_lower #>> '{data,refusal,reason}' IS DISTINCT FROM 'not_named'
     OR r_lower #>> '{data,outcome}' IS DISTINCT FROM 'previewed' OR r_lower #>> '{data,command,mode}' IS DISTINCT FROM 'preview'
     OR r_lower #>> '{data,command,acting_person}' IS DISTINCT FROM c_email OR r_lower #>> '{data,command,via}' IS DISTINCT FROM 'direct'
     OR r_lower #>> '{data,confirm,args,confirms_command_id}' IS DISTINCT FROM v_prev::text THEN
    RAISE EXCEPTION '0721 V3 FAILED: a production limit lowered in one call was not recorded as a preview and answered confirm_required: %', r_lower;
  END IF;
  IF (r_confirm ->> 'http_status')::int <> 201 OR r_confirm #>> '{data,outcome}' IS DISTINCT FROM 'applied'
     OR r_confirm #>> '{data,command,acting_person}' IS DISTINCT FROM c_email
     OR r_confirm #>> '{data,command,via}' IS DISTINCT FROM 'confirm'
     OR r_confirm #>> '{data,command,confirms_command_id}' IS DISTINCT FROM v_prev::text
     OR strpos(r_confirm #>> '{data,summary}', 'This is saved to your cars: it stays from run to run, production included') = 0
     OR strpos(r_confirm #>> '{data,expires}', 'Saved to the cars') = 0 OR v_ledger IS DISTINCT FROM 'confirm' THEN
    RAISE EXCEPTION '0721 V3 FAILED: the confirm of the recorded preview was not applied, bound and recorded under the person: % (ledger %)', r_confirm, v_ledger;
  END IF;
  IF v_t_confirm IS DISTINCT FROM v_low THEN
    RAISE EXCEPTION '0721 V3 FAILED: the engine reads % as the car''s target, not the owner''s confirmed %', v_t_confirm, v_low;
  END IF;
  IF r_again #>> '{data,outcome}' = 'applied' OR v_twice <> 'refused' OR v_bogus <> 'refused' THEN
    RAISE EXCEPTION '0721 V3 FAILED: a preview confirmed a second apply (% / %) or a non-preview was confirmed (%)', r_again, v_twice, v_bogus;
  END IF;
  IF r_mid #>> '{data,outcome}' IS DISTINCT FROM 'applied' OR r_mid #>> '{data,command,via}' IS DISTINCT FROM 'direct'
     OR (r_undo ->> 'http_status')::int <> 422 OR r_undo #>> '{error,code}' IS DISTINCT FROM 'confirm_required'
     OR r_undo #>> '{data,outcome}' IS DISTINCT FROM 'previewed' OR v_t_undo IS DISTINCT FROM v_mid THEN
    RAISE EXCEPTION '0721 V3 FAILED: a raise took more than one call, or an undo that lowers was applied unconfirmed (target %): % / %', v_t_undo, r_mid, r_undo;
  END IF;
  IF r_other #>> '{error,code}' IS DISTINCT FROM 'confirm_required' OR r_other #>> '{data,refusal,reason}' IS DISTINCT FROM 'no_recorded_preview'
     OR r_other #>> '{data,outcome}' IS DISTINCT FROM 'previewed' OR r_other #>> '{data,command,via}' IS DISTINCT FROM 'direct'
     OR v_t_other IS DISTINCT FROM (v_ctr ->> 'max_charge_pct')::numeric THEN
    RAISE EXCEPTION '0721 V3 FAILED: another principal confirmed a preview it did not make (target %): %', v_t_other, r_other;
  END IF;
  IF r_undone #>> '{data,outcome}' IS DISTINCT FROM 'applied' OR r_undone #>> '{data,command,via}' IS DISTINCT FROM 'confirm'
     OR r_undone #>> '{data,command,confirms_command_id}' IS DISTINCT FROM r_undo #>> '{data,command,command_id}'
     OR v_t_undone IS DISTINCT FROM v_low THEN
    RAISE EXCEPTION '0721 V3 FAILED: the confirm of the undo''s recorded preview was not applied and bound (target %): %', v_t_undone, r_undone;
  END IF;
  IF v_guard <> 'refused' OR v_back <> 'refused' THEN
    RAISE EXCEPTION '0721 V3 FAILED: the guard (%) or the production backstop (%) let the row through', v_guard, v_back;
  END IF;
  IF r_clear #>> '{data,outcome}' IS DISTINCT FROM 'applied' OR r_clear #>> '{data,command,via}' IS DISTINCT FROM 'direct' THEN
    RAISE EXCEPTION '0721 V3 FAILED: clearing the limit in production took more than one call, or the arguments set the door: %', r_clear;
  END IF;
  -- §12: a passcode session is refused before any tool while production is live; an issued key reaches the gate
  IF (r_pass ->> 'http_status')::int <> 403 OR r_pass #>> '{error,code}' IS DISTINCT FROM 'production_live'
     OR r_key #>> '{error,code}' IS DISTINCT FROM 'production_needs_a_person' THEN
    RAISE EXCEPTION '0721 V3 FAILED: a passcode session or an issued key was not refused in production: % / %', r_pass, r_key;
  END IF;
  IF (r_enter ->> 'http_status')::int <> 403 OR r_enter #>> '{error,code}' IS DISTINCT FROM 'production_live' THEN
    RAISE EXCEPTION '0721 V3 FAILED: the demo passcode door opened (or tried to) while production was live: %', r_enter;
  END IF;
  -- §9: saved, carried, read by the engine on the carried run, lifted from the run and not from the car
  IF v_saved < 1 OR v_carried <> v_saved OR v_t_carried IS DISTINCT FROM v_low OR v_lifted IS NOT NULL OR v_saved_after <> v_saved THEN
    RAISE EXCEPTION '0721 V3 FAILED: the confirmed limit was not saved (%), carried (%), read on the carried run (%), or survived its end (lifted %, saved after %)',
      v_saved, v_carried, v_t_carried, v_lifted, v_saved_after;
  END IF;
  -- §10 and §13
  IF v_fake <> 'refused' OR v_del <> 'refused' OR v_upd <> 'refused' THEN
    RAISE EXCEPTION '0721 V3 FAILED: the owner settings guard let a row through (insert %, delete %, update %)', v_fake, v_del, v_upd;
  END IF;
  IF v_ledger_row IS DISTINCT FROM 'anthropic_ottocommand|owner_agent|answered|v0721-probe|1' OR v_ledger_bad <> 'refused' THEN
    RAISE EXCEPTION '0721 V3 FAILED: the model ledger door wrote % (and a call carrying text was %)', v_ledger_row, v_ledger_bad;
  END IF;
  IF r_demo #>> '{data,outcome}' IS DISTINCT FROM 'applied' OR r_demo #> '{data,command}' ? 'acting_person'
     OR r_demo #>> '{data,command,via}' IS DISTINCT FROM 'ottocommand' THEN
    RAISE EXCEPTION '0721 V3 FAILED: a passcode session on a demo run: %', r_demo;
  END IF;
  -- nothing the probe wrote survived it
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run)
     OR EXISTS (SELECT 1 FROM public.ottoq_owner_accounts WHERE account_id = v_acct)
     OR EXISTS (SELECT 1 FROM public.ottoq_agent_principals WHERE principal_id IN (v_pid, v_pid2))
     OR EXISTS (SELECT 1 FROM public.ottoq_agent_principals WHERE name IN ('v0721-probe-passcode', 'v0721-probe-key'))
     OR EXISTS (SELECT 1 FROM public.ottoq_owner_commands WHERE acting_person = c_email OR sim_run_id = v_run)
     OR EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run2)
     OR EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings WHERE acting_person = c_email)
     OR EXISTS (SELECT 1 FROM public.ottoq_model_call_ledger WHERE chain_id = 'v0721-probe') THEN
    RAISE EXCEPTION '0721 V3 FAILED: the probe left rows behind';
  END IF;
  RAISE NOTICE '0721 V3 PASSED: production at the twin depot takes a signed-in person (% on %), refuses a passcode (and opens none) and a key, lowers a limit (or undoes a raise) only as the one confirm of a preview the same principal recorded, saves it and carries it onto the next run, refuses a setting no command made, and ledgers a model call', c_email, v_run;
END $v3$;

-- ══ V4: the run-scope registry stays clean ════════════════════════════════════════════════════════════════════════
DO $v4$
DECLARE v_block int; v_mine int;
BEGIN
  SELECT count(*) FILTER (WHERE severity = 'block'), count(*) FILTER (WHERE table_name = 'ottoq_owner_commands')
    INTO v_block, v_mine FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 OR v_mine > 0 THEN
    RAISE EXCEPTION '0721 V4 FAILED: the registry reports % block(s) and % row(s) for ottoq_owner_commands', v_block, v_mine;
  END IF;
  RAISE NOTICE '0721 V4 PASSED';
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0721_a_signed_in_owner_changes_production_under_their_own_name', false, false,
  'OTTO-Command as the filter and executor for owners'' agents (Chase 2026-10-14): ottoq_owner_commands records the '
  'person (acting_person, from a 0700 sign-in), the door (via: ottocommand, confirm or direct) and the preview an apply '
  'confirmed (confirms_command_id); production_live runs take owner commands from a signed-in person only, and lower a '
  'charge limit there only as the one confirm of a preview the same principal recorded in the last 15 minutes (rule 9); '
  'a backstop refuses an applied production command with no person (rule 10) and a confirm of anything but such a '
  'preview. Agent door only: ottoq_agent_call, ottoq_owner_command, its '
  'receipt, whoami and the owner-commands guard. No arm reaches any of them, and no arm can run while a run is live '
  '(every runner''s guard), so no certified run changes: FALSE/FALSE. And (Chase 2026-10-14, 12:35 PM CT) what a '
  'signed-in owner sets as a charge limit or an every-return order is saved to the car (ottoq_owner_saved_settings) and '
  'carried onto every new demo or production run, by triggers whose WHEN no arm meets; owner tables guarded against rows '
  'no command made; the demo passcode opens nothing while production is live; OTTO-Command model calls ledgered. With no '
  'run live a signed-in owner still saves a charge limit or an every-return order to the cars (outcome saved, no run, the '
  'saved table only), carried onto the next demo or production run.',
  now());

COMMIT;
