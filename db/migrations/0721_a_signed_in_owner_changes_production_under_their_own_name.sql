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
--
--   §17 (the review, round 3; read-only on the live catalog 2026-10-15 13:15:42-13:23 UTC, 8:15-8:23 AM CT, and re-read
--   2026-10-17 14:45:14-14:47:49 UTC, 9:45-9:47 AM CT, every body this file pins unchanged and 0721 still not applied;
--   each finding reproduced on the scratch chain at 2b1678f first, 2026-10-15 from 8:35 AM CT):
--   (j) THE OWNER DOOR WENT TO THE NEWEST-STARTED LIVE RUN. ottoq_agent_live_run (md5 75c2e8545f7d92fc39215723ddc70aea)
--       is the run running or paused at the depot with the latest started_at, and the owner command, whoami, 0605's
--       owner read and both cockpit boards read it. The engine's one read of an owner limit with nothing pinned,
--       public.ottoq_owner_charge_limit (md5 9de03ba377929ea4419975cb82aa7279), took the most recently set active limit on
--       ANY running or paused run. So with production running and a demo run started after it and paused, an issued key's
--       80% went to the paused demo, ottoq_effective_target_soc_at (md5 1fbe1e28294cd87d6f28920b3a68e7e6) and
--       ottoq_departure_clear (md5 9cc535e83e981ed6deacdc068e9908f6) read it with no run pinned, production's owner tick
--       stamped it (twin.ottoq_world_advance calls the tick first, before anything pins ottoq.sim_run_id), a car could
--       leave production at 80%, and whoami named the demo (R1). The live catalog keeps one running run per depot
--       (ottoq_one_running_run_per_depot: UNIQUE (depot_id) WHERE status = 'running'), so "the running run" is one run.
--   (k) TWO PRODUCTION RUNS LIVE AT ONCE. ottoq_production_start(uuid) (md5 ea2945cbb0435c58ce73b4f5e038c501) refuses
--       only a RUNNING run at the depot and inserts its run running; ottoq_production_stop(text) (md5
--       499ea8d51f65cd62463838ba940e075e) completes only the running production run; ottoq_pause_run(uuid,text) (md5
--       1e3ec33aca6f4f3b008a0d83bff08c51) and ottoq_resume_run(uuid) (md5 b693dc33284db3914381f89bd7f21724) only move a
--       run between running and paused. So a paused production run and a new one are live together, and round 2's
--       takeover (§16 (d)) lifted only demo runs' settings: the paused production run's 85% stayed in force, a person's
--       clear on the new run left it there, the unpinned reads returned it, the car could leave at 85%, and stopping the
--       new run made it the answer again (R3, S5).
--   (l) STAMPS THAT OUTLIVED THEIR LIMIT. A limit withdrawn on a paused run is not reconciled until that run ticks again,
--       the run's end returned before re-stamping when nothing on the run was active, and the takeover re-stamped only
--       the cars whose limits it lifted: a passcode session's 80% withdrawn on a paused demo stayed stamped
--       (vehicles.target_soc, which production's gate disposition reads) into production (R4).
--   (m) WHAT IS SAVED CHANGED ON ONE RUN ONLY. A person's clear or raise ended or replaced what is saved, and every other
--       live run kept the row it had carried: production resumed holding the old lower limit, a car could leave at 84%, a
--       second clear answered no_change, and an undo there saved a lower limit back with no preview (R2).
--   (n) THE PLAN HASH COULD BE COMPUTED, AND A COMMAND ID ALONE BOUND. A preview's plan_hash was md5 of the plan as 0605
--       hashes it (tool, run, arguments, effects), every part of which the receipt shows, and an apply that named a
--       preview by confirms_command_id alone bound to it (S1).

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
--     owner command's body is not changed for it); a person's new limit or every-return order replaces the saved row, and
--     a person's clear, cancel or undo ends or restores it (AFTER UPDATE OF status). Every new demo or production run at the depot (INSERT, or a status change to running
--     or paused) carries each saved row onto the run as an ordinary ottoq_owner_settings row naming it (saved_id), once
--     (unless what stood for it there is gone, §17 (d)), inside the contract in force; the engine's readers are unchanged.
--     The run's end lifts it from the run and no longer
--     stamps its command lifted. WHAT IS PER-RUN BY DESIGN: a hold (a time on that run's clock), a one-time order (now,
--     next_return: consumed when served, lifted with the run if not), and anything set through a passcode session or an
--     issued key (no person). A one-time order is an extra service, never a withdrawal (the review, round 1): over an
--     every-return order of the same service it leaves what is saved to the car as it is, and on the run the every-return
--     order is back once the one-time order is done; the receipt says so. And (the review, round 2, §16 (c)) where that
--     every-return order already covers what the one-time order asks for, the one-time order is already ordered and
--     changes nothing. Because a signed-in owner's lower limit is now carried into production, it is confirmed
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
--   §10 THE OWNER TABLES' OWN GUARD (re-review item 10; tightened by the review, round 1): every write to
--     ottoq_owner_settings or ottoq_owner_saved_settings is refused unless it comes from a function that makes owner
--     settings, each named for its own call by a function-level setting, ottoq.owner_settings_writer: the owner command
--     ('owner_command'), the tick ('tick', 0605's body unchanged, md5 pinned), the run's end ('run_end'), the carry
--     ('carry') and (the review, round 2, §16 (d)) a production run taking over its depot ('production_start', which only
--     lifts); the saved table takes the owner command only. So a plain INSERT, UPDATE, DELETE or TRUNCATE, as postgres
--     (the SQL editor, the Management API) or anyone else, is refused. Then each move only from the writer that makes it:
--     a row is what an applied command set in this transaction (on its run), or a saved row carried; replaced and
--     withdrawn only by the applied command recorded in this transaction that names the car; fulfilled only by the tick on
--     its own test; lifted only by the run's end (or a production run's takeover); put back only by an undo or (an
--     every-return order, §9) by the tick
--     once the one-time order that replaced it is done; any DELETE but the purge's (ottoq.retention) refused; the saved
--     table's end and restore only by such a command, how it ended immutable. ottoq.agent_ledger_unlock opens both, as it
--     opens the commands table.
--   §11 my_settings reads `saved` (public.ottoq_owner_settings_read wraps 0605's ottoq_owner_read, md5 pinned), only for
--     an agent signed in to an OTTOYARD account: a demo passcode session or an issued key gets no `saved` block and no line
--     about it, and who saved a row and its command are shown only to that same person (the re-review: a passcode session
--     read the account holder's email here). And (the review, round 2, §16 (a)) every command id in my_settings, my_fleet
--     and my_vehicle goes only to the agent that made the command or to the person it is recorded under.
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
--   §15 THE COCKPIT BOARDS (the review, round 1): ottoq_owner_board and ottoq_depot_owner_board, anon-readable since
--     0606/0608, leave out a production run's settings in force and every production command, every command a person
--     made with no run live, a person's note (their own words) on the owner board's highlight, and the id and code of
--     such a command on a demo run's carried setting. Demo runs read as before. Nothing is granted or revoked.
--   §16 THE REVIEW, ROUND 2 (the night of 2026-10-14 CT; each finding reproduced on the scratch chain first):
--     (a) A COMMAND'S ID ONLY TO ITS MAKER OR ITS PERSON. my_settings (§11's wrapper) and my_fleet and my_vehicle (through
--         public.ottoq_owner_read_shown, in the dispatcher; 0605's bodies unchanged) return every command_id the reader
--         did not make, and that is not recorded under the reader's person, as null. A passcode session or an issued key
--         read the ids of a person's carried production and no-run commands there, which §15 keeps off the boards.
--     (b) A SAVED ROW COMES BACK ONLY BY A PERSON'S UNDO OF THE COMMAND THAT ENDED IT. The follow puts it back on the saved
--         guard's own condition (and that command is the one that replaced the run row being restored), so a passcode
--         session's or an issued key's undo restores its run's row and leaves the saved row ended. It answered 500 under
--         the guard, and with the guard's unlock on it put a person's ended lower limit back for every later run.
--     (c) A ONE-TIME ORDER NEVER TAKES THE PLACE OF AN EVERY-RETURN ORDER THAT COVERS IT (rule 9). Over an every-return
--         order of the same service that includes this visit (for now or next_return) or any (for next_return), it is
--         already ordered: no_change, the every-return row and its atom untouched. Taking its place unmerged the service
--         from the car's current visit at the next tick, and the next_return order waited for the car to leave again, so
--         the car could leave without it while the receipt said no car leaves with it undone. A 'now' over an every-return
--         order that skips this visit is an extra service as before (round 1's resume), and the receipt's "back on the
--         car" line is written only when an every-return order really was replaced.
--     (d) A PRODUCTION RUN TAKES OVER ITS DEPOT'S CARS (rule 9). When one starts, resumes or pauses, every owner setting of
--         any other run still live at the depot is lifted, the cars that carried a limit go back to their target, and the
--         commands are stamped lifted unless what they set is saved (ottoq_owner_settings_yield_to_production, writer
--         'production_start', run first by §9's run-start trigger, its failure not caught). ottoq_production_start
--         refuses only a RUNNING run, so a paused demo run's passcode 80% stayed stamped on the car and in the engine's
--         reads with no run pinned, and a car could leave production at 80% while OTTO-Q told the owner it charges full.
--         (Round 3 re-measured and widened it, §17 (c): as the production run becomes the running run, not as it pauses;
--         every other live run's per-run settings, a paused production run's included; what is saved stays; every car
--         at the depot re-stamped pinned to the production run.)
--     (e) THE GATEWAY: an ask that read the web hands back none of the words that say how to confirm a preview (the plan
--         hash, the preview's id), and the model is never shown them; only the text of the turn that ends the model's
--         reply is an answer (a note beside a tool call never is: stopped with nothing done, the door fails with its
--         code); and the text written before a pause_turn is kept.
--
--   §17 THE REVIEW, ROUND 3 (2026-10-15 to 17 CT; CLAUDE.md rule 9; every finding of §1 (j)-(n) reproduced first, then
--     fixed and tested, tests/test_ottocommand_executor_sql.py's round-3 section):
--     (a) ONE OWNERS' RUN PER DEPOT. public.ottoq_owner_run_id(depot): the running run (at most one, by the index), else
--         the newest paused production run, else the newest paused demo run, NULL when there is none (§14);
--         public.ottoq_owner_live_run returns it in ottoq_agent_live_run's shape. The owner command (and through it the
--         write gate), whoami, my_settings, my_fleet, my_vehicle and both cockpit boards read it, and so does
--         ottoq_owner_charge_limit's unpinned branch (only the owners' run's rows at the setting's depot; a pinned read,
--         a run or 'none', is 0605's, unchanged), so ottoq_effective_target_soc_at and ottoq_departure_clear with no run
--         pinned answer for the owners' run only. ottoq_agent_live_run itself is unchanged, and so are its seven other
--         callers (FINDINGS G495).
--     (b) EVERY RE-STAMP PINNED. public.ottoq_owner_target_on_run(car, run, as_of) computes a car's target with that run
--         pinned (NULL pins none), and its function-level SET restores the caller's ottoq.sim_run_id as it returns; the
--         owner tick computes its own run's targets through it, and public.ottoq_owner_restamp(depot, run, cars) re-stamps
--         vehicles.target_soc through it. The run's end now also runs for a run whose only limit rows were withdrawn or
--         replaced and not reconciled, and re-stamps those cars with the lifted ones, pinned to the owners' run the depot
--         has once the run has ended (none: no run).
--     (c) THE TAKEOVER, WIDENED AND NARROWED. A production run takes over when it becomes the running run (inserted
--         running, or resumed), not as it pauses: every other live run's per-run settings at the depot are lifted, a
--         paused production run's included, while a row that carries a person's saved setting stays (it is the car's on
--         every run, and (d) keeps it in step); then what is saved is carried onto the production run, and every car at
--         the depot is re-stamped pinned to it. ottoq_production_start, ottoq_production_stop, ottoq_pause_run and
--         ottoq_resume_run are not changed. The run settings' guard admits a production_start lift of exactly such a row.
--     (d) WHAT IS SAVED HOLDS ON EVERY LIVE RUN. public.ottoq_owner_saved_propagate(command), the owner command's last
--         write for an applied command recorded under a person: every live run's active row that carries a saved row the
--         command ended now is withdrawn by that command ('what is saved to the car changed on another run'; the guard
--         admits exactly that), and every other live demo or production run at the depot carries what is saved now. An
--         undo acts on its own run only; one that finds nothing of the command's there says why (a clear, the full
--         charge, a cancel or a release leaves no setting of its own: nothing_to_undo; settings a takeover lifted:
--         lifted); and one that puts back a limit below what is saved to the car is a lowering, gated like one. The
--         carry's once-per-run rule becomes a chain rule: a copy of the saved row on the run, or what replaced it there,
--         stands in the way while it is in force or was withdrawn by a command still standing; one a takeover lifted, or
--         one a command since undone withdrew, does not, so a demo run resumed after production gets what is saved back.
--         The run settings' guard admits that carry onto a command's own run: it refused it (a WARNING), so the resumed
--         demo lost the person's order or limit for the rest of the run, and a person's confirmed undo on production that
--         brought a saved limit back failed with 500 (found writing this section's tests, 2026-10-17 9:30 AM CT).
--     (e) THE PLAN HASH IS A SALTED CREDENTIAL. A preview's plan_hash is md5(plan_salt || the plan as 0605 hashes it),
--         plan_salt a fresh random 32-hex value kept with the preview (a CHECK: only a preview carries one); a confirm's
--         plan is recomputed under that salt. The hash is given only inside the preview's confirm object: not in the
--         command object (so not in my_commands), never in a summary or a plan_changed refusal. An apply binds only when
--         it names that hash (expect_plan_hash); confirms_command_id beside it must name the same preview, and alone it
--         binds nothing (confirm_required, not_named, recorded as a new preview). The backstop refuses a confirm of a
--         preview that carries no salt, whoever writes the row.
--     (f) AND THE ANSWERS. A cancel that finds nothing of the owner's to withdraw says why (a service OTTO-Q found needed
--         stays until it is done and the car does not leave without it; or there is no order of theirs), and a one-time
--         order an every-return order covers, already done on this visit, says it was done.
--     What stays open: a contract ceiling lowered mid-run is re-stamped only at a takeover, the run's end or an owner
--     change (FINDINGS G494, toward a fuller car).
--
--   THE GATEWAY'S HALF (TypeScript, committed beside this file, not deployed): edge-functions/_shared/ottocommand_owner.ts
--   replays every assistant turn verbatim (thinking, server_tool_use, web_search_tool_result, cited text, tool_use,
--   fallback blocks), resumes a paused turn (pause_turn, at most 3, inside the 50 s budget), answers a model refusal as a
--   plain failure with no tool run, sets output_config.effort explicitly (OTTOCOMMAND_EFFORT, default low), max_tokens
--   8000, the server-side fallback on the models that take it, and a default model when the deployment names none
--   (OTTOCOMMAND_OWNER_MODEL overrides, else ANTHROPIC_MODEL, which the gateway deployed on 2026-10-04 reads, so a
--   deployment that sets only it keeps its model); treats outcome 'saved' as a change made (§14); offers the web search server tool (max_uses 3 per model call, the API's own
--   per-request cap, so an ask's total is at most max_uses x its model calls, and an ask makes at most 9 model calls:
--   at most 27 searches at the default of 3, inside the 50 s budget;
--   OTTOCOMMAND_WEB_SEARCH=off disables it, OTTOCOMMAND_WEB_MAX_USES 1..5, located at the depot); refuses in code every
--   change after a web result has entered an ask (a web_search_tool_result, or any result of the code execution dynamic
--   filtering runs over the pages; an ask that read the web returns no confirm objects, names no refused change's
--   arguments, and its answer OPENS with that refusal); never screens or drops the model's text by pattern (the review,
--   round 1): every ask and search answer instead carries `changes`, a block built in code from OTTO-Q's receipts only
--   (none, or each applied, saved, previewed, no_change or refused change with its command id, and each change refused
--   unsent because the ask read the web), the only record of what an ask changed, also written at the end of `answer`;
--   a search's block says a search changes nothing; returns cited sources (URLs in the answer, titles only in
--   the sources list, cleaned and capped); adds the read-only
--   MCP tool ottocommand_search and POST /v1/search (scope ottoq | web | both: reads and the web only, never a command);
--   and records each model call through §13, fire-and-forget. edge-functions/_shared/agent_gateway.ts carries the catalog
--   entries, routes and the ledger writer; ottoq-agent-gateway/index.ts reads the configuration.

-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════
--
--   Every body this file replaces is the agent door (ottoq_agent_call, ottoq_owner_command, its receipt, whoami) or a
--   trigger on ottoq_owner_commands. No certification, dial or sweep arm calls any of them, and the engine's readers of
--   owner settings (ottoq_effective_target_soc_at, ottoq_departure_clear, ottoq_owner_departure_blocked,
--   ottoq.ottoq_owner_orders_tick, both world steps) are untouched (but for §17's two lines, below). Does changing WHO
--   may write owner settings change a certified run? No: a certification run has no owner commands. Its arms are
--   cert_harness / ab_harness runs that the gate refuses; they run in one uncommitted transaction no agent's session can
--   see; and every test-day runner refuses to start while ANY run is running or paused, with no run_by predicate (read
--   live today: cron 746, the recert runner,
--   "IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN RETURN"; the same guard in
--   ottoq_dial_experiment_runner, ottoq_dial_pair, ottoq_throughput_sweep_arm and ottoq_throughput_sweep_runner). So a
--   setting on a production_live run is never in force while an arm runs, exactly 0605 §1(g)'s argument for demo runs.
--   §9-§13 change the same answer nowhere: the run-start triggers have WHEN run_by IN ('operator_demo','production_live')
--   (no arm has either), so they never execute in an arm's transaction; the lift's patch changes only which commands get
--   lifted_at stamped, and returns at its first line on a run with no owner settings (every arm); the guards and the save
--   triggers fire only on writes to the owner tables, which no arm makes; the passcode door and the ledger function are
--   agent doors. The engine's readers of owner settings remain untouched. §14 writes no run's rows at all: a 'saved'
--   command writes only the saved table, which a run sees only through the carry above. §10's writer setting is added to
--   ottoq.ottoq_owner_orders_tick with its body unchanged (P1 pins it, the snapshot holds it): for the length of the tick's
--   own call it names the tick as a writer of the owner tables, which an arm never writes, so an arm's tick does exactly
--   what it did. The guard's other writers are the owner command, the run's end and the carry, all as above.
--   §16 (the review, round 2) changes the same answer nowhere: the production takeover runs only in §9's run-start
--   trigger, whose WHEN no arm meets (and only for a production_live run); the command-id mask wraps three agent reads;
--   the follow only narrows when a saved row comes back; and the one-time order branch is the owner command's own. The
--   engine's readers of owner settings stay untouched.
--   §17 (the review, round 3) touches two of the engine's readers of owner settings, and each only where an arm has
--   nothing to read: ottoq_owner_charge_limit's changed branch is its unpinned one, and it is called only from
--   ottoq_effective_target_soc_at's EXISTS on an active owner limit, which no arm has (no arm holds owner rows, and the
--   runners above refuse to start while any run that could hold one is live); the tick's changed line is inside its loop
--   over pending owner limits, and the tick returns at its first statement on a run with no owner rows. The run's end's
--   widened first line finds nothing on an arm (no owner rows of any status), so it returns where it did. The takeover,
--   the re-stamps and the carry run only from §9's run-start triggers, whose WHEN no arm meets, and the propagation only
--   from the owner command. A determinism pair's arms carry no owner rows. So the same answer: forces_recert FALSE,
--   forces_dial_restart FALSE.
--
-- ══ §4 WHAT IT DELIBERATELY DOES NOT DO ═════════════════════════════════════════════════════════════════════════════
--
--   * No persistence for what has no person behind it: a passcode session's or an issued key's settings, holds and
--     one-time orders lift when their run ends, as 0605 §4 decided (§9 says why each). An unserved one-time order is not
--     carried to the next run (an open option). With no run live (§14) only a signed-in owner's charge limit and
--     every-return orders can be saved; a hold, a one-time order and an undo still need a run.
--   * The two cockpit boards (0606/0608) stay anon-readable demo cockpits: §15 only leaves production, a person's no-run
--     commands and a person's words out of them. They give a confirmation code to 'applied' commands only, so the receipt
--     of a 'saved' command carries none either. A passcode session's command still shows its note on the owner board's
--     highlight, as 0606 decided for demo runs (the note is the visitor's ask text when OTTO-Command sent it).
--   * A saved setting made while two runs are live was carried onto the other at its next start; since the review,
--     round 3 (§17 (d)) a person's change to what is saved reaches every live run at the depot at once.
--   * ottoq_agent_live_run and its seven callers that are not the owner door (three agent reads, 0559's request door,
--     the two welcomes) keep the newest-started live run (FINDINGS G495); and a contract ceiling lowered mid-run is not
--     re-stamped on the cars until a takeover, the run's end or an owner change (FINDINGS G494).
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
--   the live catalog (it needs no run live when the file is applied); V1 asserts its bodies. And (the review, round 1)
--   every plain write to the owner tables refused as postgres and as service_role, a write in an owner command's own
--   transaction refused, each move refused from any writer but its own (G1-G5), a one-time order leaving what is saved,
--   and the cockpit boards read as anon with production, a person's no-run commands and a person's words left out. And
--   (§16, the review, round 2) a passcode session's and an issued key's my_settings, my_fleet and my_vehicle holding none
--   of a person's command ids, on the run they were made on and the next run that carries them, while the person (through
--   either of two signed-in agents) reads all of them; a passcode undo over a person's ended saved row applying with
--   nothing saved and the next demo and production runs charging full, with the guard's unlock off and on; a one-time
--   order over an every-return order that covers it answered no_change, the service still on the visit and the car not
--   leaving until it is done, and over one that skips this visit still an extra service; and a production run started
--   while a demo run is paused lifting the demo's settings, the car back at 100% (stamped, read with and without a run
--   pinned, and the departure test), the person's saved settings carried onto production. And (§17, the review, round 3)
--   each of the review's sequences, reproduced on 2b1678f first: a paused demo started after production is not the
--   owners' run (an issued key refused on production, the reads, stamps and departure test production's, pinned or not);
--   an active limit on another live run reaches no unpinned read; a person's clear and raise on a demo run hold on the
--   paused production run it resumes; an undo saves no lower limit back without its preview, judged against what is saved
--   too; a second production run takes over from a paused one and a clear there holds on both; a limit withdrawn on a
--   paused run never stays stamped (clear, undo, and the run's end); a paused production run stays the owners' run, and a
--   demo resumed after it has only what is saved; the tick and the re-stamp read the run they are given and leave the
--   caller's pin; a demo resumed after production gets the saved order and limit back, and a person's undo on production
--   brings a saved limit back to the demo run it was made on; a confirm binds only by its preview's salted hash (a
--   command id alone, the unsalted fingerprint and a salt-less preview bind nothing); each no-change answer says why; P3
--   refuses a running twin run; and V1 reads code, not comments. Fourteen mutations, each undoing one §17 fix in a copy
--   of this file (its V blocks silenced, but for the one that mutates V1), each fail a named test.
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
--   passcode session in production. The saved table, saved_id, the saved table's guard and the ledger function may stay:
--   without the carry nothing reads a saved row. §10: the snapshot restores the tick, the run's end and the three-argument
--   owner command WITHOUT their writer setting, so the run settings' guard would then refuse every write they make: DROP
--   TRIGGER ottoq_owner_settings_guard_trg ON public.ottoq_owner_settings in the same transaction (the TRUNCATE trigger may
--   stay), or name them writers again as §10 does. §15: the snapshot holds both cockpit boards. §14: the
--   restored bodies refuse every change with no run live (no_live_demo) and write no 'saved' row; the widened
--   mode/outcome CHECK and ottoq_owner_commands_saved_check stay (a 'saved' row already written must stay valid evidence).
--   §16: the snapshot's dispatcher routes my_fleet and my_vehicle without the command-id mask again; dropping the two
--   run-start triggers (above) stops the production takeover with the carry. ottoq_owner_read_shown,
--   ottoq_owner_mask_command_ids and ottoq_owner_settings_yield_to_production may stay, unread.
--   §17: the snapshot (twelve bodies) also holds ottoq_owner_charge_limit and ottoq_owner_read, so restoring it puts the
--   engine's unpinned limit read, the tick's target and the owner reads back to 0605's (and the boards, whoami and the
--   command to their pre-0721 runs). ottoq_owner_run_id, ottoq_owner_live_run, ottoq_owner_target_on_run,
--   ottoq_owner_restamp and ottoq_owner_saved_propagate are then unread and may stay; plan_salt and its CHECK may stay
--   (NULL is their old meaning: the restored bodies write no salt, and the backstop's salt check fires only on a row that
--   names a preview, which the restored three-argument body never writes).
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
--
--   AND NOTHING RUNNING AT THE TWIN DEPOT (§17, P3). V3 probes the owner door on a paused production run of its own, which
--   a running run outranks as the owners' run, so this file refuses to apply while a run is running at the twin depot:
--   pause or stop it (ottoq_pause_run, ottoq_production_stop), then apply. Read 2026-10-17 14:45:14 UTC (9:45 AM CT): no
--   run was running or paused there. After this file a confirm is the confirm object sent back as it is: its plan hash is
--   given nowhere else, so nothing can rebuild one from a receipt.

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
  -- §15 (the review, round 1): the two cockpit boards, read on the live catalog 2026-10-14 21:03:34 UTC (4:03 PM CT), both
  -- EXECUTE for anon, authenticated and service_role, and identical on the scratch chain (0606, 0608 from their files); and
  -- §10's one writer of the run's owner settings this file does not otherwise replace, the tick (0605), which §10 names as
  -- a writer by a function-level setting (read live 2026-10-14 23:09:53 UTC, 6:09 PM CT; proconfig the search_path only)
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_owner_board(uuid,uuid,uuid)',                                             '84e756310bb785ea99bd434662fba37d'),
      ('public.ottoq_depot_owner_board(uuid,integer)',                                         'deb3c6e8b686ac79a6419099314fb3ae'),
      ('ottoq.ottoq_owner_orders_tick(uuid,timestamp with time zone)',                         '5f01d0881bd65d80b155dba04033e09f')) x(f, want)
   WHERE to_regprocedure(f) IS NULL
      OR md5(pg_get_functiondef(to_regprocedure(f))) IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 P1: not the cockpit board or the tick §10 and §15 were written against (re-measure before applying): %', v_bad;
  END IF;
  -- §17 (the review, round 3): the engine's one read of an owner limit, whose unpinned branch this file narrows to the
  -- owners' run, read on the live catalog 2026-10-15 13:17:20 UTC (8:17 AM CT) and identical on the scratch chain (0605's
  -- file); its one caller is ottoq_effective_target_soc_at (read 13:15:42 UTC)
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_owner_charge_limit(uuid)',                                                '9de03ba377929ea4419975cb82aa7279')) x(f, want)
   WHERE to_regprocedure(f) IS NULL
      OR md5(pg_get_functiondef(to_regprocedure(f))) IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0721 P1: not the owner-limit read §17 was written against (re-measure before applying): %', v_bad;
  END IF;
  -- §17: the owners' run is "the running run" because at most one run runs at a depot (read live 13:15:42 UTC:
  -- ottoq_one_running_run_per_depot, unique on depot_id WHERE status = 'running')
  IF NOT EXISTS (SELECT 1 FROM pg_index i
                  WHERE i.indrelid = 'public.ottoq_sim_runs'::regclass AND i.indisunique
                    AND pg_get_indexdef(i.indexrelid) ~ '\(depot_id\) WHERE \(status = ''running''::text\)$') THEN
    RAISE EXCEPTION '0721 P1: no unique index keeps one running run per depot (ottoq_one_running_run_per_depot), so "the running run" is not one run';
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
                AND column_name IN ('acting_person', 'via', 'confirms_command_id', 'plan_salt')) THEN
    RAISE EXCEPTION '0721 P2: ottoq_owner_commands already has acting_person, via, confirms_command_id or plan_salt';
  END IF;
  --: §17 (the review, round 3)
  IF to_regprocedure('public.ottoq_owner_run_id(uuid)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_live_run(uuid)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_target_on_run(uuid,uuid,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_restamp(uuid,uuid,uuid[])') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_saved_propagate(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0721 P2: a function §17 creates already exists';
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
     --: the review, round 2
     OR to_regprocedure('public.ottoq_owner_settings_yield_to_production(uuid)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_mask_command_ids(jsonb,uuid,text)') IS NOT NULL
     OR to_regprocedure('public.ottoq_owner_read_shown(public.ottoq_agent_principals,jsonb)') IS NOT NULL
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
  IF EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL unnest(p.proconfig) c(setting)
              WHERE c.setting LIKE 'ottoq.owner_settings_writer=%') THEN
    RAISE EXCEPTION '0721 P2: a function already names itself a writer of the owner settings (ottoq.owner_settings_writer)';
  END IF;
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0721 P2: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $fresh$;

-- ── P3 (the review, round 3): nothing runs at the twin depot. §17 makes the owners' run the RUNNING run first, and V3's
--    probe inserts a paused production run that is the owners' run only while nothing runs there (a run that ran would
--    take the probe's commands). Applying this file needs the depot idle or paused: pause or stop the running run first. ──
DO $idle$
DECLARE v_running uuid;
BEGIN
  SELECT r.sim_run_id INTO v_running FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'running' LIMIT 1;
  IF v_running IS NOT NULL THEN
    RAISE EXCEPTION '0721 P3: run % is running at the twin depot; V3 probes the owner door on a paused production run, which a running run outranks. Pause or stop it, then apply', v_running;
  END IF;
END $idle$;

-- ── the rollback snapshot of the twelve bodies this file replaces or re-sets (the tick: its §10 writer setting and §17's
--    one line) ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0721_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure,
                 'public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)'::regprocedure,
                 'public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure,
                 'public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure,
                 'public.ottoq_owner_commands_guard()'::regprocedure,
                 'public.ottoq_tg_lift_owner_settings_on_terminal()'::regprocedure,
                 'public.ottoq_agent_public_call(text,jsonb,text,jsonb,timestamp with time zone)'::regprocedure,
                 'public.ottoq_owner_board(uuid,uuid,uuid)'::regprocedure,
                 'public.ottoq_depot_owner_board(uuid,integer)'::regprocedure,
                 'ottoq.ottoq_owner_orders_tick(uuid,timestamp with time zone)'::regprocedure,
                 --: §17 (the review, round 3)
                 'public.ottoq_owner_charge_limit(uuid)'::regprocedure,
                 'public.ottoq_owner_read(public.ottoq_agent_principals,text,jsonb)'::regprocedure);

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
    via IS DISTINCT FROM 'confirm' OR confirms_command_id IS NOT NULL),
  --: §17 (the review, round 3): a preview's plan hash is salted with a random value kept here and nowhere else, so it is no
  --: longer md5 of data the token can read; only a preview has one
  ADD COLUMN plan_salt text,
  ADD CONSTRAINT ottoq_owner_commands_plan_salt_check CHECK (
    plan_salt IS NULL OR (outcome = 'previewed' AND plan_salt ~ '^[0-9a-f]{32}$'));

--: one preview confirms one apply
CREATE UNIQUE INDEX ottoq_owner_commands_confirms_idx ON public.ottoq_owner_commands (confirms_command_id)
  WHERE confirms_command_id IS NOT NULL;

COMMENT ON COLUMN public.ottoq_owner_commands.acting_person IS
'0721. The person the command is recorded under: the email of the OTTOYARD account (ottoq_owner_accounts, through ottoq_oauth_grants) behind an agent signed in through 0700, while that account is active and owns the agent''s fleet. NULL for a passcode session or an issued key, which name no one. On a production_live run an applied command always has one (ottoq_owner_commands_backstop_trg). It records whose agent sent the command; OTTO-Q cannot see whether that person said yes.';
COMMENT ON COLUMN public.ottoq_owner_commands.via IS
'0721. Who formed the command, set by the database from the gateway''s transport and the binding, never taken from an argument. ottocommand: an OTTO-Command model read the owner''s words and called the tool with the owner''s own token (transport ask: POST /v1/ask or the MCP tool ask_ottocommand, sent with text). confirm: the agent confirmed a recorded preview: the apply bound to an outcome previewed row the same principal made on the same run in the last 15 minutes, named in confirms_command_id (always set on a confirm row, by CHECK); no model was involved, whether it was sent through the confirm door of /v1/ask and ask_ottocommand (transport confirm) or as a typed tool naming the preview. direct: the agent itself made the call (a typed tool over MCP or REST, or a confirm object that bound to no preview and was recorded as a new preview), or any other caller. OTTO-Q enforces preview-then-confirm by the same signed-in principal within 15 minutes; it cannot see a person''s yes, which the person''s own agent relays. NULL on rows written before 0721; never backfilled.';
COMMENT ON COLUMN public.ottoq_owner_commands.confirms_command_id IS
'0721. The preview this apply confirmed: an outcome previewed row by the same principal, on the same run, of the same tool, arguments and plan_hash, made at most 15 minutes before it and confirmed by no other apply (unique). On a production run every applied lowering of a charge limit has one. An apply binds only when it names the preview''s plan hash (expect_plan_hash); a command id alone binds nothing (the review, round 3). OTTO-Q enforces preview-then-confirm by the same principal; the confirm itself is relayed by the person''s agent, and OTTO-Q cannot see the person''s yes.';
COMMENT ON COLUMN public.ottoq_owner_commands.plan_salt IS
'0721 (the review, round 3). A preview''s random salt (32 hex characters): its plan_hash is md5(plan_salt || the plan as 0605 hashes it), so the hash cannot be computed from what the token can read. Never returned by any read: the hash itself reaches only the principal that made the preview, inside that preview''s confirm object, and a confirm is checked by recomputing the plan under this salt. NULL on every row but a preview, and on rows written before 0721.';

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

-- ══ 1c. (the review, round 3) the owners' run, and a car's target read with a run pinned ═══════════════════════════════
--
-- ONE answer to "which run do owners' settings belong to at this depot", used by every owner path: the owner command, the
-- write gate (through the run the command passes it), whoami, my_settings/my_fleet/my_vehicle (0605's ottoq_owner_read),
-- the two cockpit boards, and the engine's one read of an owner limit with no run pinned (ottoq_owner_charge_limit, so
-- ottoq_effective_target_soc_at and ottoq_departure_clear read only the owners' run's rows when nothing is pinned). It is
-- the run RUNNING at the depot (at most one: ottoq_one_running_run_per_depot), else the newest paused production run, else
-- the newest paused demo run. The newest-started live run (ottoq_agent_live_run, unchanged for the reads that are not the
-- owner door's) sent every owner command to a paused demo started after production while production ran (the review's R1).

CREATE OR REPLACE FUNCTION public.ottoq_owner_run_id(p_depot_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  -- 0721 (the review, round 3). The owners' run at a depot: the running run, else the newest paused production run, else
  -- the newest paused demo run; NULL when there is none (§14: a signed-in owner then saves to the cars only).
  SELECT r.sim_run_id
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = p_depot_id
     AND (r.status = 'running' OR (r.status = 'paused' AND r.run_by IN ('production_live', 'operator_demo')))
   ORDER BY (r.status = 'running') DESC, (r.run_by = 'production_live') DESC, r.started_at DESC NULLS LAST, r.sim_run_id
   LIMIT 1
$fn$;

--: the owners' run in ottoq_agent_live_run's shape, so each owner path swaps one call for the other
CREATE OR REPLACE FUNCTION public.ottoq_owner_live_run(p_depot_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT jsonb_build_object('sim_run_id', r.sim_run_id, 'status', r.status, 'scenario', r.scenario_code,
                            'seed', r.random_seed::text, 'sim_clock', r.sim_clock_current, 'tick', r.tick_count,
                            'speed_x', r.demo_speed_x, 'started_at', r.started_at, 'run_by', r.run_by)
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = public.ottoq_owner_run_id(p_depot_id)
$fn$;

--: how full a car charges, read with a run pinned explicitly (p_run; NULL pins no run, 'none'): every re-stamp of
--: vehicles.target_soc an owner change causes goes through here, never an unpinned read. The pin is the function's own: its
--: SET clause restores the caller's ottoq.sim_run_id when it returns, so a caller's pin (a tick, a pair arm, a stop) and
--: ottoq.ottoq_active_sim_run_id's cache (the same setting) are left exactly as they were
CREATE OR REPLACE FUNCTION public.ottoq_owner_target_on_run(p_vehicle_id uuid, p_run uuid, p_as_of timestamptz)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET ottoq.sim_run_id TO 'none'
AS $fn$
BEGIN
  IF p_run IS NOT NULL THEN
    PERFORM set_config('ottoq.sim_run_id', p_run::text, true);
  END IF;
  RETURN public.ottoq_effective_target_soc_at(p_vehicle_id, p_as_of);
END $fn$;

--: re-stamp the cars (p_cars, or every car homed or standing at the depot) whose vehicles.target_soc is not the target
--: pinned to p_run (NULL: no run). Called as a production run takes over (every car), at a run's end (the cars that held a
--: limit there, reconciled or not) and by nothing else; the tick re-stamps its own cars the same way
CREATE OR REPLACE FUNCTION public.ottoq_owner_restamp(p_depot_id uuid, p_run uuid, p_cars uuid[] DEFAULT NULL)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_clock timestamptz := COALESCE((SELECT r.sim_clock_current FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run), now());
  v_n     integer;
BEGIN
  WITH t AS (
    SELECT v.id, round(public.ottoq_owner_target_on_run(v.id, p_run, v_clock))::int AS tgt
      FROM public.vehicles v
     WHERE CASE WHEN p_cars IS NULL THEN v.home_depot_id = p_depot_id OR v.current_depot_id = p_depot_id
                ELSE v.id = ANY (p_cars) END)
  UPDATE public.vehicles v
     SET target_soc = t.tgt
    FROM t
   WHERE v.id = t.id AND t.tgt IS NOT NULL AND v.target_soc IS DISTINCT FROM t.tgt;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_owner_run_id(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_owner_live_run(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_owner_target_on_run(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_owner_restamp(uuid, uuid, uuid[]) FROM PUBLIC, anon, authenticated, service_role;

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
                                                              p_args jsonb, p_plan text, p_expect text, p_confirms uuid,
                                                              p_lowering boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721 (CLAUDE.md rule 9). Is this apply the confirm of a preview OTTO-Q recorded? It binds only to a row with outcome
   'previewed' made by the SAME principal, on the same run (§14: or, made while no run was live, with none live now), of
   the same tool and arguments (mode, note and the words of a hold's time aside: its resolved until_sim stays in), whose
   plan hash the apply names (p_expect) and is still the plan under that preview's own salt (p_plan, the plan as 0605
   hashes it: md5(plan_salt || p_plan) = plan_hash), created at most 15 minutes ago and confirmed by no apply yet.
   (The review, round 3; S1) The plan hash is the credential: an apply that names its preview by command id alone
   (p_confirms, no p_expect) binds nothing, and the hash is salted with a random value kept with the preview, so it cannot
   be computed from what the token can read and reaches only the principal that made the preview, inside its confirm
   object. A command id named beside the hash must be that same preview. Answers {"bound": <command_id>} (the preview row
   is locked until the apply commits; the unique index ottoq_owner_commands_confirms_idx refuses a second apply that raced
   it), or confirm_required with the reason and what to do. Called by ottoq_owner_command only; no client role reaches it.
   What it cannot know is whether a person said yes: the confirm comes from the person's agent, with the token that made
   the preview. A person-only surface (the OTTOYARD account session) is not built. */
DECLARE
  v_bound uuid;
  v_named public.ottoq_owner_commands;
  v_why   text;
  v_prod  boolean := EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run AND r.run_by = 'production_live');
BEGIN
  IF p_expect IS NULL THEN
    --: (the review, round 3; S1) a command id alone names no plan: it binds nothing
    v_why := 'not_named';
  ELSE
    SELECT p.command_id INTO v_bound
      FROM public.ottoq_owner_commands p
     WHERE p.principal_id = p_agent.principal_id
       AND p.outcome = 'previewed'
       AND p.sim_run_id IS NOT DISTINCT FROM p_run   --: §14: a preview made while no run was live binds only with none live
       AND p.tool = p_tool
       AND p.plan_hash = p_expect
       AND p.plan_salt IS NOT NULL AND md5(p.plan_salt || p_plan) = p.plan_hash   --: round 3: the plan, under its own salt
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
                 WHEN 'not_named'                 THEN CASE WHEN p_confirms IS NOT NULL
                                                             THEN 'This apply named its preview by command id only, and a confirm names its preview by the plan hash its confirm object carries; a command id alone confirms nothing. '
                                                             ELSE 'This apply named no preview by its plan hash. ' END
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
    -- a2. (the review, round 3; rule 9) the owners' run, not the newest-started live run: a paused demo started after
    --     production took every owner command while production ran (R1)
    ARRAY[E'  v_run := public.ottoq_agent_live_run(p_agent.depot_id);\n',
          E'  --: 0721 (the review, round 3): the owners'' run (ottoq_owner_run_id): the running run, else the newest paused\n'
       || E'  --: production run, else the newest paused demo run\n'
       || E'  v_run := public.ottoq_owner_live_run(p_agent.depot_id);\n'],
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
       || E'  --: (the review, round 3) the plan as 0605 hashes it; the salt of the preview an apply names, or of this preview;\n'
       || E'  --: and how many effects there were before a car''s cancel, to say why nothing changes for it\n'
       || E'  v_plan        text;\n'
       || E'  v_salt        text;\n'
       || E'  v_k           int;\n'
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
       || E'          END IF;\n'
       || E'          --: (the review, round 3; rule 9) and so does putting back a lower limit than the one saved to the car (or the\n'
       || E'          --: ceiling, when none is): a person''s undo brings a saved limit back with its run row (§9''s follow), so no\n'
       || E'          --: undo saves a lower limit again without the preview-then-confirm, whatever the run''s own row says\n'
       || E'          IF v_person IS NOT NULL\n'
       || E'             AND LEAST(v_ceiling, COALESCE(v_old.charge_limit_pct, v_ceiling))\n'
       || E'                 < LEAST(v_ceiling, COALESCE((SELECT s.charge_limit_pct FROM public.ottoq_owner_saved_settings s\n'
       || E'                                               WHERE s.vehicle_id = v_veh.id AND s.kind = ''charge_limit''\n'
       || E'                                                 AND s.status = ''active''), v_ceiling)) THEN\n'
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
       || E'      --: 0721 (the review, round 3): a car with nothing of the owner''s to withdraw says why, not "Nothing to change.":\n'
       || E'      --: a service OTTO-Q found needed stays until it is done (rule 9), and there may simply be no order of theirs\n'
       || E'      IF jsonb_array_length(v_effects) = v_k THEN\n'
       || E'        v_atom := NULL;\n'
       || E'        IF v_service IS NOT NULL AND v_run_id IS NOT NULL THEN\n'
       || E'          SELECT a INTO v_atom\n'
       || E'            FROM (SELECT vn.atoms FROM public.ottoq_visit_needs vn\n'
       || E'                   WHERE vn.vehicle_id = v_veh.id AND vn.sim_run_id = v_run_id AND vn.status IN (''open'', ''in_progress'')\n'
       || E'                   ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) w\n'
       || E'            CROSS JOIN LATERAL jsonb_array_elements(w.atoms) a\n'
       || E'           WHERE a ->> ''svc'' = v_service AND COALESCE(a ->> ''status'', ''pending'') NOT IN (''done'', ''cancelled'')\n'
       || E'           LIMIT 1;\n'
       || E'        END IF;\n'
       || E'        v_svc_name := (SELECT c.display_name FROM public.service_cadence_policy c WHERE c.svc = v_service);\n'
       || E'        v_effects := v_effects || jsonb_build_array(jsonb_build_object(\n'
       || E'          ''vehicle_id'', v_veh.id, ''vehicle'', v_veh.display_name, ''state'', v_veh.current_state::text, ''soc'', v_veh.current_soc,\n'
       || E'          ''key'', ''service:'' || COALESCE(v_service, ''*''), ''before'', NULL, ''after'', NULL, ''change'', false,\n'
       || E'          ''group'', CASE WHEN v_atom IS NOT NULL THEN ''needed_no_order'' ELSE ''no_order'' END,\n'
       || E'          ''group_one'', CASE WHEN v_atom IS NOT NULL THEN ''has no order of yours to withdraw; OTTO-Q found it needed, so it stays until it is done''\n'
       || E'                            ELSE ''has no order of yours to withdraw'' END,\n'
       || E'          ''group_many'', CASE WHEN v_atom IS NOT NULL THEN ''have no order of yours to withdraw; OTTO-Q found it needed, so it stays until it is done''\n'
       || E'                             ELSE ''have no order of yours to withdraw'' END,\n'
       || E'          ''now'', CASE WHEN v_atom IS NOT NULL\n'
       || E'                      THEN format(''%s has no order of yours for %s to withdraw: OTTO-Q found it needed on this visit, so it stays until it is done, and the car does not leave without it.'',\n'
       || E'                                  v_veh.display_name, public.ottoq_owner_lc(COALESCE(v_svc_name, v_service)))\n'
       || E'                      WHEN v_run_id IS NULL AND v_service IS NOT NULL\n'
       || E'                      THEN format(''%s has no every-return order for %s saved to it, so there is nothing to withdraw.'',\n'
       || E'                                  v_veh.display_name, public.ottoq_owner_lc(COALESCE(v_svc_name, v_service)))\n'
       || E'                      WHEN v_run_id IS NULL\n'
       || E'                      THEN format(''%s has no every-return order saved to it, so there is nothing to withdraw.'', v_veh.display_name)\n'
       || E'                      WHEN v_service IS NOT NULL\n'
       || E'                      THEN format(''%s has no order of yours for %s to withdraw, so nothing changes.'',\n'
       || E'                                  v_veh.display_name, public.ottoq_owner_lc(COALESCE(v_svc_name, v_service)))\n'
       || E'                      ELSE format(''%s has no service order of yours to withdraw, so nothing changes.'', v_veh.display_name) END));\n'
       || E'      END IF;\n'
       || E'    END LOOP;\n    v_head := CASE WHEN v_service IS NULL THEN format(''Your service orders on %s are withdrawn.'', v_cphrase)\n'],
    -- e4a. (the review, round 3) the count of effects before each car's cancel, so a car that had nothing says so
    ARRAY[E'      SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = (v_car ->> ''id'')::uuid;\n'
       || E'      FOR v_old IN SELECT * FROM public.ottoq_owner_settings o\n',
          E'      SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = (v_car ->> ''id'')::uuid;\n'
       || E'      v_k := jsonb_array_length(v_effects);   --: 0721 (the review, round 3)\n'
       || E'      FOR v_old IN SELECT * FROM public.ottoq_owner_settings o\n'],
    -- p. (the review, round 2; rule 9) a one-time order (now, next_return) never takes the place of an every-return order of
    --    the same service that already covers it: one that includes this visit, or any for next_return (it covers the next
    --    return). Taking its place took the order's pending atom off the car's current visit at the next tick (0605's
    --    unmerge) and applied the next_return order only after the car left again, so the car could leave without the
    --    service while the receipt said "no car leaves with it undone". It is already ordered: no change, and the
    --    every-return row and its atom stay as they are. A 'now' over an every-return order that does NOT include this
    --    visit is still an extra service for this visit, as before (the every-return order is back once it is done, §9)
    ARRAY[E'        v_one := ''already has this order''; v_many := ''already have this order'';\n'
       || E'      ELSIF v_when = ''next_return'' OR (v_when = ''every_return'' AND NOT v_incl) THEN\n',
          E'        v_one := ''already has this order''; v_many := ''already have this order'';\n'
       || E'      --: 0721 (the review, round 2; rule 9): an every-return order of this service already covers what a one-time order\n'
       || E'      --: asks for (this visit, when it includes it; the next return, always). Taking its place took the service off\n'
       || E'      --: the car''s current visit, so the car could leave without it: it is already ordered, and nothing changes\n'
       || E'      ELSIF v_old.setting_id IS NOT NULL AND v_old.service_when = ''every_return'' AND v_when IN (''now'', ''next_return'')\n'
       || E'            AND (v_when = ''next_return'' OR COALESCE(v_old.include_current_visit, true)) THEN\n'
       || E'        v_grp := ''already_every_return'';\n'
       || E'        --: (the review, round 3) and when this visit''s service is already done, the words say so\n'
       || E'        v_now := CASE WHEN v_when = ''now'' AND v_atom IS NOT NULL AND v_atom ->> ''status'' = ''done''\n'
       || E'                      THEN format(''%s already gets %s on every return (an every-return order) and had it on this visit, so nothing changes.'',\n'
       || E'                                  v_veh.display_name, public.ottoq_owner_lc(v_svc_name))\n'
       || E'                      ELSE format(''%s already gets %s on every return (an every-return order), %s included, so nothing changes.'',\n'
       || E'                        v_veh.display_name, public.ottoq_owner_lc(v_svc_name),\n'
       || E'                        CASE WHEN v_when = ''next_return'' THEN ''its next return''\n'
       || E'                             WHEN EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn\n'
       || E'                                           WHERE vn.vehicle_id = v_veh.id AND vn.sim_run_id = v_run_id\n'
       || E'                                             AND vn.status IN (''open'', ''in_progress'')) THEN ''this visit''\n'
       || E'                             ELSE ''its next visit'' END) END;\n'
       || E'        v_one := ''already gets it on every return, so nothing changes'';\n'
       || E'        v_many := ''already get it on every return, so nothing changes'';\n'
       || E'      ELSIF v_when = ''next_return'' OR (v_when = ''every_return'' AND NOT v_incl) THEN\n'],
    ARRAY[E'        ''after'', v_when || CASE WHEN v_when = ''every_return'' AND NOT v_incl THEN '':later'' ELSE '''' END,\n',
          E'        --: 0721 (the review, round 2): an order an every-return order already covers changes nothing: after is before\n'
       || E'        ''after'', CASE WHEN v_grp = ''already_every_return''\n'
       || E'                      THEN v_old.service_when || CASE WHEN NOT COALESCE(v_old.include_current_visit, true) THEN '':later'' ELSE '''' END\n'
       || E'                      ELSE v_when || CASE WHEN v_when = ''every_return'' AND NOT v_incl THEN '':later'' ELSE '''' END END,\n'],
    ARRAY[E'        ''change'', v_grp <> ''already_ordered'',\n',
          E'        ''change'', v_grp NOT IN (''already_ordered'', ''already_every_return''),   --: 0721 (the review, round 2)\n'],
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
    -- u. (the review, round 3) an undo acts on the run it is sent on (a saved command's rows are carried onto other live
    --    runs too, and follow what is saved there), and a command with nothing of its own on the run says why
    ARRAY[E'                           WHERE o.command_id = v_target.command_id), ''[]''::jsonb);\n'
       || E'      v_cphrase := public.ottoq_owner_cars_phrase(v_cars, false);\n'
       || E'      FOR v_set IN SELECT * FROM public.ottoq_owner_settings o WHERE o.command_id = v_target.command_id\n',
          E'                           WHERE o.command_id = v_target.command_id AND o.sim_run_id = v_run_id), ''[]''::jsonb);\n'
       || E'      --: 0721 (the review, round 3): an undo acts on the run it is sent on. A saved command''s rows are also carried onto the\n'
       || E'      --: other live runs at the depot (§9), and those follow what is saved (ottoq_owner_saved_propagate), not this undo\n'
       || E'      IF jsonb_array_length(v_cars) = 0 THEN\n'
       || E'        --: and a command that left no setting of its own on this run has nothing to take back: the answer says why\n'
       || E'        v_refusal := jsonb_build_object(''code'', ''nothing_to_undo'', ''message'', CASE v_target.tool\n'
       || E'          WHEN ''clear_charge_limit'' THEN ''That command cleared a charge limit. A clear takes a setting away and leaves none of its own, so there is nothing to undo; to put a limit back, set it again (set_charge_limit).''\n'
       || E'          WHEN ''set_charge_limit''   THEN ''That command set the full charge, which clears a limit, or changed only what is saved to your cars, so it left no setting of its own on this run and there is nothing to undo; to put a limit back, set it again (set_charge_limit).''\n'
       || E'          WHEN ''cancel_service''     THEN ''That command withdrew service orders, which leaves no setting of its own, so there is nothing to undo; to order a service again, request it (request_service).''\n'
       || E'          WHEN ''release_hold''       THEN ''That command released a hold, which leaves no setting of its own, so there is nothing to undo; to hold a car again, hold it (hold_vehicle).''\n'
       || E'          ELSE ''That command left no setting of its own on this run, so there is nothing to undo.'' END);\n'
       || E'      END IF;\n'
       || E'      v_cphrase := public.ottoq_owner_cars_phrase(v_cars, false);\n'
       || E'      FOR v_set IN SELECT * FROM public.ottoq_owner_settings o WHERE o.command_id = v_target.command_id AND o.sim_run_id = v_run_id\n'],
    -- f. the binding (rule 9) and (the review, round 3; S1) the plan hash: 0605's stale-hash refusal now checks the plan
    --    under the salt of the preview the apply names; only that hash binds (a command id alone binds nothing); a
    --    preview's own hash is salted with a fresh random value kept with it (plan_salt)
    ARRAY[E'  v_hash := md5(jsonb_build_object(\n'
       || E'              ''tool'', v_tool, ''run'', v_run_id,\n'
       || E'              ''args'', v_norm - ''mode'' - ''note'' - ''vehicles'' - ''expect_plan_hash'' - ''idempotency_key'' - ''until'' - ''for_minutes'',\n'
       || E'              ''plan'', COALESCE((SELECT jsonb_agg(jsonb_build_array(e ->> ''vehicle_id'', e ->> ''key'', e -> ''before'', e -> ''after'', e -> ''change'')\n'
       || E'                                                 ORDER BY e ->> ''vehicle_id'', e ->> ''key'')\n'
       || E'                                  FROM jsonb_array_elements(v_effects) e), ''[]''::jsonb))::text);\n'
       || E'  IF v_refusal IS NULL AND v_mode = ''apply'' AND v_expect IS NOT NULL AND v_expect <> v_hash THEN\n'
       || E'    v_refusal := jsonb_build_object(''code'', ''plan_changed'', ''plan_hash'', v_hash,\n'
       || E'      ''message'', ''The plan changed since it was previewed (a car''''s settings moved). Nothing was applied. Read the new plan and confirm it with its hash.'');\n'
       || E'  END IF;\n',
          E'  --: 0721 (the review, round 3; S1): 0605''s plan, unchanged, kept as text. Its own md5 is what an apply that names no\n'
       || E'  --: preview, a refusal and a no_change record (0605''s fingerprint). A PREVIEW''s hash is salted with a random value kept\n'
       || E'  --: with it (plan_salt), so it is no longer md5 of data the token can read, and it reaches only the principal that made\n'
       || E'  --: the preview, inside that preview''s confirm object\n'
       || E'  v_plan := jsonb_build_object(\n'
       || E'              ''tool'', v_tool, ''run'', v_run_id,\n'
       || E'              ''args'', v_norm - ''mode'' - ''note'' - ''vehicles'' - ''expect_plan_hash'' - ''idempotency_key'' - ''until'' - ''for_minutes'',\n'
       || E'              ''plan'', COALESCE((SELECT jsonb_agg(jsonb_build_array(e ->> ''vehicle_id'', e ->> ''key'', e -> ''before'', e -> ''after'', e -> ''change'')\n'
       || E'                                                 ORDER BY e ->> ''vehicle_id'', e ->> ''key'')\n'
       || E'                                  FROM jsonb_array_elements(v_effects) e), ''[]''::jsonb))::text;\n'
       || E'  v_hash := md5(v_plan);\n'
       || E'  --: an apply that names a plan hash names the preview this principal recorded with it, and the plan is checked under\n'
       || E'  --: that preview''s salt; a hash this principal recorded no preview with names none, and the binding below says so\n'
       || E'  IF v_mode = ''apply'' AND v_expect IS NOT NULL THEN\n'
       || E'    SELECT p.plan_salt INTO v_salt FROM public.ottoq_owner_commands p\n'
       || E'     WHERE p.principal_id = p_agent.principal_id AND p.outcome = ''previewed'' AND p.plan_hash = v_expect\n'
       || E'       AND p.plan_salt IS NOT NULL\n'
       || E'     ORDER BY p.created_at DESC, p.command_id LIMIT 1;\n'
       || E'    IF v_salt IS NOT NULL THEN\n'
       || E'      v_hash := md5(v_salt || v_plan);\n'
       || E'    END IF;\n'
       || E'  END IF;\n'
       || E'  IF v_refusal IS NULL AND v_mode = ''apply'' AND v_salt IS NOT NULL AND v_expect <> v_hash THEN\n'
       || E'    v_refusal := jsonb_build_object(''code'', ''plan_changed'',\n'
       || E'      ''message'', ''The plan changed since it was previewed (a car''''s settings moved). Nothing was applied. Preview it again, and confirm the new preview with the confirm object it returns.'');\n'
       || E'  END IF;\n'
       || E'  --: 0721 (CLAUDE.md rule 9: a lower limit is the owner''s, "set verified and confirmed"). An OTTO-Command model never\n'
       || E'  --: confirms a plan: the gateway strips both binding arguments from what it may send, and a call that carries one is refused.\n'
       || E'  IF v_refusal IS NULL AND v_mode = ''apply'' AND v_door = ''ottocommand'' AND (v_expect IS NOT NULL OR v_confirms IS NOT NULL) THEN\n'
       || E'    v_refusal := jsonb_build_object(''code'', ''confirm_not_through_ottocommand'',\n'
       || E'      ''message'', ''OTTO-Command does not confirm a plan. Nothing was applied. A preview is confirmed by sending its confirm object back: to ask_ottocommand or POST /v1/ask as confirm, or as the typed tool call it describes.'');\n'
       || E'  END IF;\n'
       || E'  --: An apply must be the confirm of a recorded preview (ottoq_owner_confirm_binding: same principal, run, tool, arguments\n'
       || E'  --: and plan hash, at most 15 minutes old, not confirmed before) when it lowers a limit on a production run or for a\n'
       || E'  --: signed-in owner (whose limit is saved and carried into production, §9), when it came through the confirm door, or\n'
       || E'  --: when it names a preview, by its plan hash or its command id (the review, round 3: only the hash binds; an id alone\n'
       || E'  --: binds nothing). One that does not bind applies nothing: it is recorded as a preview, with its own plan hash and id,\n'
       || E'  --: and answered confirm_required, so the next confirm can name it. One that binds is recorded as via ''confirm'', whichever\n'
       || E'  --: way it was sent: the agent confirmed a recorded preview.\n'
       || E'  IF v_refusal IS NULL AND v_mode = ''apply''\n'
       || E'     AND (p_via IS NOT DISTINCT FROM ''confirm'' OR v_confirms IS NOT NULL OR v_expect IS NOT NULL\n'
       || E'          OR (v_lowers AND (v_production OR v_person IS NOT NULL))) THEN\n'
       || E'    v_bind := public.ottoq_owner_confirm_binding(p_agent, v_run_id, v_tool, v_norm, v_plan, v_expect, v_confirms,\n'
       || E'                                                 v_lowers AND (v_production OR v_person IS NOT NULL));\n'
       || E'    v_bound := (v_bind ->> ''bound'')::uuid;\n'
       || E'    IF v_bound IS NULL THEN\n'
       || E'      v_confirm_req := v_bind;\n'
       || E'      v_mode := ''preview'';\n'
       || E'      v_norm := v_norm || jsonb_build_object(''mode'', ''preview'');\n'
       || E'    ELSE\n'
       || E'      v_via := ''confirm'';\n'
       || E'    END IF;\n'
       || E'  END IF;\n'
       || E'  --: (the review, round 3; S1) the hash this row records: a preview''s own, under a fresh random salt kept with it; a bound\n'
       || E'  --: apply''s, its preview''s (the plan was checked above under that preview''s salt); anything else, 0605''s fingerprint\n'
       || E'  IF v_refusal IS NULL AND v_mode = ''preview'' THEN\n'
       || E'    v_salt := replace(gen_random_uuid()::text, ''-'', '''');\n'
       || E'    v_hash := md5(v_salt || v_plan);\n'
       || E'  ELSE\n'
       || E'    v_salt := NULL;\n'
       || E'    IF v_bound IS NULL THEN\n'
       || E'      v_hash := md5(v_plan);\n'
       || E'    END IF;\n'
       || E'  END IF;\n'],
    -- g. the receipt names the run that ends it
    --: §9: what a signed-in owner sets as a limit or an every-return order is saved, and the receipt says so
    ARRAY[E'E''\\nThis lasts until the demo run ends or you undo it.''',
          E'CASE WHEN v_run_id IS NULL THEN E''\\nNo run is live: this is saved to your cars, applies from the next demo or production run, and stays from run to run, production included, until you change it.'' WHEN v_person IS NOT NULL AND (v_tool IN (''set_charge_limit'', ''clear_charge_limit'') OR (v_tool = ''request_service'' AND v_when = ''every_return'') OR (v_tool = ''cancel_service'' AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_effects) e WHERE e ->> ''before'' = ''every_return''))) THEN E''\\nThis is saved to your cars: it stays from run to run, production included, until you change it.'' WHEN v_production THEN E''\\nThis lasts until the production run ends or you undo it.'' ELSE E''\\nThis lasts until the demo run ends or you undo it.'' END || CASE WHEN v_tool = ''request_service'' AND v_when IN (''now'', ''next_return'') AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_effects) e WHERE COALESCE((e ->> ''change'')::boolean, false) AND e ->> ''before'' LIKE ''every_return%'') THEN format(E''\\nThe every-return order for %s stays: on this run it is back on the car once this one is done%s.'', public.ottoq_owner_lc(COALESCE(v_svc_name, v_service)), CASE WHEN EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings s WHERE s.kind = ''service'' AND s.service = v_service AND s.status = ''active'' AND v_cars @> jsonb_build_array(jsonb_build_object(''id'', s.vehicle_id::text))) THEN '', and it stays saved to the car for every run'' ELSE '''' END) ELSE '''' END'],
    -- g2. an apply recorded as a preview says so, and how to confirm it; (the review, round 3; S1) no summary carries the
    --     plan hash or the preview's id (the summary is stored, and my_commands returns it): only the confirm object does
    ARRAY[E'    WHEN v_mode = ''preview'' THEN ''Preview only, nothing has changed. If you confirm: ''\n'
       || E'         || public.ottoq_owner_summarize(v_head, v_effects, v_tail)\n'
       || E'         || format(E''\\nTo confirm, send the same command with mode "apply" and expect_plan_hash "%s".'', v_hash)\n',
          E'    WHEN v_confirm_req IS NOT NULL THEN ''Not applied yet: '' || (v_confirm_req ->> ''message'') || E''\\nIf you confirm: ''\n'
       || E'         || public.ottoq_owner_summarize(v_head, v_effects, v_tail)\n'
       || E'         || E''\\nTo confirm, send back the confirm object this answer carries, unchanged, from this same agent within 15 minutes.''\n'
       || E'    WHEN v_mode = ''preview'' THEN ''Preview only, nothing has changed. If you confirm: ''\n'
       || E'         || public.ottoq_owner_summarize(v_head, v_effects, v_tail)\n'
       || E'         || E''\\nTo confirm, send back the confirm object this answer carries, unchanged, from this same agent within 15 minutes.''\n'],
    -- h. the record: the person, the door and the preview confirmed, on every row
    ARRAY[E'       args, vehicles, effects, refusal, summary, plan_hash, link, idempotency_key, undoes_command_id)\n',
          E'       args, vehicles, effects, refusal, summary, plan_hash, link, idempotency_key, undoes_command_id, acting_person, via,\n'
       || E'       confirms_command_id, plan_salt)\n'],
    ARRAY[E'       CASE WHEN v_tool = ''undo_command'' AND v_target.command_id IS NOT NULL THEN v_target.command_id END)\n',
          E'       CASE WHEN v_tool = ''undo_command'' AND v_target.command_id IS NOT NULL THEN v_target.command_id END,\n'
       || E'       v_person, v_via, v_bound, v_salt)\n'],
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
        --: (the review, round 3) lifted on this very run, as a production run took over the depot
        WHEN v_target.sim_run_id IS NOT DISTINCT FROM v_run_id AND v_target.lifted_at IS NOT NULL
        THEN jsonb_build_object(''code'', ''lifted'', ''message'', format(''That command''''s settings were lifted (%s), so there is nothing left of it to undo.'', v_target.lifted_reason))
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
    -- q. (the review, round 3; rule 9) a person's change to what is saved reaches every live run's rows that carry it
    ARRAY[E'         WHERE c.command_id = v_target.command_id AND c.undone_at IS NULL;\n'
       || E'      END IF;\n'
       || E'    END IF;\n'
       || E'  EXCEPTION WHEN unique_violation THEN\n',
          E'         WHERE c.command_id = v_target.command_id AND c.undone_at IS NULL;\n'
       || E'      END IF;\n'
       || E'      --: 0721 (the review, round 3; rule 9): what this person changed in what is saved to the cars holds on every live run\n'
       || E'      --: at the depot: a run''s row carrying a saved row this command ended is withdrawn by it, and every other live demo or\n'
       || E'      --: production run there carries what is saved now (ottoq_owner_saved_propagate). Before, a person''s clear or raise on a\n'
       || E'      --: demo run left a paused production run holding the lower limit, and production resumed with it\n'
       || E'      IF v_cmd.outcome = ''applied'' AND v_person IS NOT NULL THEN\n'
       || E'        PERFORM public.ottoq_owner_saved_propagate(v_cmd.command_id);\n'
       || E'      END IF;\n'
       || E'    END IF;\n'
       || E'  EXCEPTION WHEN unique_violation THEN\n'],
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
        ''message'', ''A production run is live at the twin depot, and the demo passcode opens nothing while it is: production is changed only by an agent signed in to its owner''''s OTTOYARD account, and an owner''''s settings and commands there are read only with that owner''''s own credentials, never a demo passcode. This session works again once the production run ends, until it expires.'',
        ''hint'', ''Sign your agent in to your OTTOYARD account (PERSONAL_AGENT.md section 10) to read and change your cars in production.''));
  END IF;

  UPDATE public.ottoq_agent_principals a SET last_used_at = now()
'],
    --: §11: my_settings also says what is saved to the cars, and stops saying everything lifts at the run's end
    ARRAY[E'      WHEN ''my_settings''        THEN public.ottoq_owner_read(v_agent, ''my_settings'', v_args)
',
          E'      WHEN ''my_settings''        THEN public.ottoq_owner_settings_read(v_agent, public.ottoq_owner_read(v_agent, ''my_settings'', v_args))   --: 0721 §11: and what is saved
'],
    --: §11 (the review, round 2): my_fleet and my_vehicle name a command only to the agent that made it, or its person
    ARRAY[E'      WHEN ''my_fleet''           THEN public.ottoq_owner_read(v_agent, ''my_fleet'', v_args)
',
          E'      WHEN ''my_fleet''           THEN public.ottoq_owner_read_shown(v_agent, public.ottoq_owner_read(v_agent, ''my_fleet'', v_args))   --: 0721 §11: a command id only to its maker
'],
    ARRAY[E'      WHEN ''my_vehicle''         THEN public.ottoq_owner_read(v_agent, ''my_vehicle'', v_args)
',
          E'      WHEN ''my_vehicle''         THEN public.ottoq_owner_read_shown(v_agent, public.ottoq_owner_read(v_agent, ''my_vehicle'', v_args))   --: 0721 §11: a command id only to its maker
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
       || E'                 ''note'', ''Send this, unchanged, to apply exactly the plan shown, from the agent that previewed it, within 15 minutes; it confirms this preview once, and it is the only place this preview''''s plan hash is given. If the cars or settings change first, OTTO-Q refuses it, and a new preview shows the new plan.'') END,\n'],
    --: (the review, round 3; S1) the recorded command no longer shows its plan hash (my_commands returns it too): a preview's
    --: hash is returned only inside its confirm object, to the principal that made it
    ARRAY[E'      ''args'', p_c.args, ''plan_hash'', p_c.plan_hash, ''sim_run_id'', p_c.sim_run_id,\n',
          E'      ''args'', p_c.args, ''sim_run_id'', p_c.sim_run_id,\n'],
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
  --: (the review, round 3; rule 9) whoami names the owners' run, the one the owner door sends a command to
  c_old3 constant text := E'    v_run := public.ottoq_agent_live_run(p_agent.depot_id);\n';
  c_new3 constant text := E'    v_run := public.ottoq_owner_live_run(p_agent.depot_id);   --: 0721 (the review, round 3): the owners'' run\n';
  v_n1 int; v_n2 int; v_n3 int;
BEGIN
  v_n1 := (length(v_def) - length(replace(v_def, c_old1, ''))) / length(c_old1);
  v_n2 := (length(v_def) - length(replace(v_def, c_old2, ''))) / length(c_old2);
  v_n3 := (length(v_def) - length(replace(v_def, c_old3, ''))) / length(c_old3);
  IF v_n1 <> 1 OR v_n2 <> 1 OR v_n3 <> 1 THEN
    RAISE EXCEPTION '0721: whoami''s anchors occur %, % and % times, expected exactly 1 each', v_n1, v_n2, v_n3;
  END IF;
  EXECUTE replace(replace(replace(v_def, c_old1, c_new1), c_old2, c_new2), c_old3, c_new3);
END $whoami$;

-- ══ 7. the guard: who, which door and which preview are as immutable as what was commanded ══════════════════════
DO $guard$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_commands_guard()'::regprocedure);
  c_old1 constant text := E'NEW.plan_hash, NEW.link, NEW.idempotency_key, NEW.undoes_command_id, NEW.created_at)';
  c_new1 constant text := E'NEW.plan_hash, NEW.link, NEW.idempotency_key, NEW.undoes_command_id, NEW.created_at, NEW.acting_person, NEW.via,\n'
                       || E'      NEW.confirms_command_id, NEW.plan_salt)';
  c_old2 constant text := E'OLD.plan_hash, OLD.link, OLD.idempotency_key, OLD.undoes_command_id, OLD.created_at)';
  c_new2 constant text := E'OLD.plan_hash, OLD.link, OLD.idempotency_key, OLD.undoes_command_id, OLD.created_at, OLD.acting_person, OLD.via,\n'
                       || E'      OLD.confirms_command_id, OLD.plan_salt)';
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
   preview (outcome 'previewed', with the salted plan hash the door gives a preview: the review, round 3) by the same
   principal, on the same run, of the same tool and plan hash, made at most 15 minutes before the apply; the unique index
   ottoq_owner_commands_confirms_idx lets it confirm one apply. */
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
       --: (the review, round 3; S1) a preview the door recorded, with its salted hash
       OR v_p.plan_salt IS NULL
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
-- Following: an AFTER UPDATE OF status trigger. When an applied command recorded under a person withdraws a saved
-- setting on a run (a clear, a cancel, an undo), the saved row ends with it; when an undo puts a replaced setting back, its
-- saved row comes back (unless the car has another saved one of that kind by then). A REPLACE ends nothing here (the
-- review, round 1): a person's new limit or every-return order saves itself in its place (the save above ends the old
-- saved row), and a one-time order over an every-return order is an extra service, not a withdrawal; on the run, the
-- every-return order is back once that one-time order is done (the tick's fulfil). The run's end ('lifted'), the tick
-- and a change made without a person (a passcode session, an issued key) leave the saved row as it is.
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
/* 0721 §9. A saved setting follows what a person does to it on a run: withdrawn by an applied command recorded under a
   person (a clear, a cancel, an undo), it ends; put back by an undo, it comes back. REPLACED, it stays: a person's new
   limit or every-return order saves itself in its place (ottoq_owner_settings_save ends the old saved row as the new
   one is written), and a one-time order (now, next_return) that takes an every-return order's place on the run is an
   extra service, not a withdrawal (the 0721 review, round 1: ending the saved order there lost it for every later run,
   production included, while the receipt said the one-time order lasts only until the run ends). And on the run, an
   every-return order a one-time order replaced resumes once that order is done (the tick marks it fulfilled), so a
   standing order is never lost for the rest of a run either (rule 9). Anything else (the run's end, a change made
   without a person) leaves the saved row as it is. */
DECLARE
  v_cur  public.ottoq_owner_settings;
  v_prev public.ottoq_owner_settings;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NULL;
  END IF;
  --: (the review, round 1) a one-time order done: the every-return order of that service it (or the one-time orders
  --: before it) replaced on this run is in force again. Walked back through replaces_setting_id, each step the row the
  --: next one closed; never fails the tick that fulfilled the order
  IF OLD.status = 'active' AND NEW.status = 'fulfilled' AND NEW.kind = 'service' AND NEW.service_when IN ('now', 'next_return') THEN
    BEGIN
      v_cur := NEW;
      FOR i IN 1 .. 50 LOOP
        v_prev := NULL;
        SELECT * INTO v_prev FROM public.ottoq_owner_settings p WHERE p.setting_id = v_cur.replaces_setting_id;
        EXIT WHEN v_prev.setting_id IS NULL OR v_prev.status <> 'replaced'
               OR v_prev.closed_by_command_id IS DISTINCT FROM v_cur.command_id
               OR v_prev.sim_run_id <> NEW.sim_run_id OR v_prev.vehicle_id <> NEW.vehicle_id
               OR v_prev.kind <> 'service' OR v_prev.service IS DISTINCT FROM NEW.service;
        IF v_prev.service_when = 'every_return' THEN
          UPDATE public.ottoq_owner_settings o
             SET status = 'active', closed_at = NULL, closed_at_sim = NULL, closed_reason = NULL, closed_by_command_id = NULL,
                 pending_reconcile = true
           WHERE o.setting_id = v_prev.setting_id AND o.status = 'replaced'
             AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_settings x
                              WHERE x.sim_run_id = o.sim_run_id AND x.vehicle_id = o.vehicle_id AND x.kind = 'service'
                                AND x.service = o.service AND x.status = 'active');
          EXIT;
        END IF;
        v_cur := v_prev;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'resuming the every-return order of car % after setting % was fulfilled failed: % %',
        NEW.vehicle_id, NEW.setting_id, SQLSTATE, SQLERRM;
    END;
    RETURN NULL;
  END IF;
  IF NEW.saved_id IS NULL THEN
    RETURN NULL;
  END IF;
  IF OLD.status = 'active' AND NEW.status = 'withdrawn'
     AND EXISTS (SELECT 1 FROM public.ottoq_owner_commands c
                  WHERE c.command_id = NEW.closed_by_command_id AND c.outcome = 'applied' AND c.acting_person IS NOT NULL) THEN
    UPDATE public.ottoq_owner_saved_settings s
       SET status = 'ended', ended_at = now(), ended_reason = COALESCE(NEW.closed_reason, 'withdrawn by the owner'),
           ended_by_command_id = NEW.closed_by_command_id
     WHERE s.saved_id = NEW.saved_id AND s.status = 'active';
  ELSIF OLD.status = 'replaced' AND NEW.status = 'active'
        --: an undo (the owner command's write); an every-return order resuming in the tick leaves what is saved as it is
        AND COALESCE(current_setting('ottoq.owner_settings_writer', true), '') = 'owner_command' THEN
    --: (the review, round 2) and only a person's undo of the command that ENDED the saved row puts it back: the saved
    --: guard's own condition, held here too, so it holds with the guard's unlock on. Any other undo that restores this run
    --: row (a passcode session's or an issued key's undo of its own command, which replaced the row after a person's later
    --: command had ended what was saved) restores the run's row and leaves the saved row ended: before, it brought back a
    --: lower limit the person had replaced, with no person and no preview, and the next production run carried it (and
    --: with the guard on, the undo failed 500). The undo restoring this row undoes the command that replaced it, so that is
    --: the command that must have ended the saved row
    UPDATE public.ottoq_owner_saved_settings s
       SET status = 'active', ended_at = NULL, ended_reason = NULL, ended_by_command_id = NULL
     WHERE s.saved_id = NEW.saved_id AND s.status = 'ended'
       AND s.ended_by_command_id = OLD.closed_by_command_id
       AND EXISTS (SELECT 1 FROM public.ottoq_owner_commands u
                    WHERE u.tool = 'undo_command' AND u.outcome = 'applied' AND u.acting_person IS NOT NULL
                      AND u.undoes_command_id = s.ended_by_command_id AND u.created_at = now())
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
    --: once per run: a pause and a resume never bring back what was withdrawn on the run. (The review, round 3) What stands
    --: in the way is a copy of this saved row on the run, or what replaced it there, that is in force or was withdrawn by a
    --: command that still stands. A copy whose replacement a production run lifted as it took over the depot (a session's
    --: one-time order or limit over it), or that a command since undone withdrew (§17's propagation), does not: what is
    --: saved to the car is carried again, so a demo run resumed after production gets the saved orders and limit back
    CONTINUE WHEN EXISTS (
      WITH RECURSIVE ch AS (
        SELECT o.setting_id, o.status, o.closed_by_command_id, 1 AS n
          FROM public.ottoq_owner_settings o WHERE o.sim_run_id = p_run AND o.saved_id = s.saved_id
        UNION ALL
        SELECT x.setting_id, x.status, x.closed_by_command_id, ch.n + 1
          FROM ch JOIN public.ottoq_owner_settings x ON x.replaces_setting_id = ch.setting_id AND x.sim_run_id = p_run
         WHERE ch.status = 'replaced' AND ch.n < 50)
      SELECT 1 FROM ch
       WHERE ch.status = 'active'
          OR (ch.status = 'withdrawn' AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_commands u
                                                       WHERE u.command_id = ch.closed_by_command_id AND u.undone_at IS NOT NULL)));
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

--: (the review, round 2; rule 9) a production run takes over its depot's cars. Measured on the scratch chain (the review's
--: scen_p2, reproduced the evening of 2026-10-14 CT) and read on the live catalog (SELECT only, 2026-10-15 00:22:51 UTC,
--: 7:22 PM CT on the 14th): ottoq_production_start (md5 ea2945cbb0435c58ce73b4f5e038c501) refuses only a RUNNING run at the
--: depot, the one-running-run index is on status = 'running', and nothing ends a PAUSED run when production starts
--: (ottoq_start_demo_run aborts every non-production run, production never does). So a passcode session's 80% on a paused
--: demo run stayed in force in production: the demo's tick had stamped it on the car (vehicles.target_soc, which
--: production's gate disposition reads), the engine's reads with no run pinned returned it, ottoq_departure_clear let the
--: car leave at 80%, and OTTO-Q told the signed-in owner the car charges to 100%.
--: (The review, round 3; rule 9) re-measured and widened. A production run takes over when it becomes the RUNNING run at
--: the depot: at its start (inserted running) and at its resume (paused -> running). Then (1) every OTHER live run's
--: per-run owner settings at the depot are lifted, a paused production run's included (R3/S5: two production runs, and
--: ottoq_production_start and ottoq_production_stop are not changed: start refuses only a running run, stop stops only
--: the running one); a row that carries a person's saved setting (saved_id) stays, because §17's propagation keeps every
--: live run's saved rows in step with what is saved, and it is the car's on every run; (2) the run-start trigger carries
--: what is saved onto the production run; and (3) EVERY car at the depot whose vehicles.target_soc is not the target
--: pinned to the production run is re-stamped (ottoq_owner_restamp), so a stamp left by any run's tick, a limit withdrawn
--: on a paused run that no tick reconciled (R4), or a run's end that found nothing active, cannot outlive the takeover.
--: Nothing happens as production pauses: the paused production run is still the owners' run (ottoq_owner_run_id ranks a
--: paused production run above a paused demo run), no other run there holds per-run settings after the takeover, and no
--: owner path reaches another run while production is the owners' run. The lifted settings' commands are stamped lifted
--: (it names the takeover), unless what they set is saved.
CREATE OR REPLACE FUNCTION public.ottoq_owner_settings_yield_to_production(p_run uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  r       public.ottoq_sim_runs;
  v_cmds  uuid[];
  v_n     integer;
BEGIN
  SELECT * INTO r FROM public.ottoq_sim_runs x WHERE x.sim_run_id = p_run;
  IF r.sim_run_id IS NULL OR r.run_by IS DISTINCT FROM 'production_live' OR r.status IS DISTINCT FROM 'running' THEN
    RETURN 0;
  END IF;
  WITH lifted AS (
    UPDATE public.ottoq_owner_settings s
       SET status = 'lifted', closed_at = now(), closed_at_sim = o.sim_clock_current,
           closed_reason = 'a production run took over the depot', pending_reconcile = false
      FROM public.ottoq_sim_runs o
     WHERE o.sim_run_id = s.sim_run_id AND o.depot_id = r.depot_id AND o.sim_run_id <> r.sim_run_id
       AND o.status IN ('running', 'paused')
       AND s.status = 'active' AND s.saved_id IS NULL
    RETURNING s.command_id)
  SELECT array_agg(DISTINCT l.command_id), count(*) INTO v_cmds, v_n FROM lifted l;
  UPDATE public.ottoq_owner_commands c
     SET lifted_at = now(), lifted_reason = 'a production run took over the depot'
   WHERE c.command_id = ANY (COALESCE(v_cmds, ARRAY[]::uuid[])) AND c.lifted_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings s WHERE s.command_id = c.command_id AND s.status = 'active');
  RETURN COALESCE(v_n, 0);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_tg_owner_saved_on_run_start()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0721 §9. A demo or production run that starts (or resumes) carries what owners saved to their cars. Never fails the
   run's start for that: a carry failure is a WARNING, and the cars charge full until an owner sets it again.
   (The review, rounds 2 and 3; rule 9) A production run that becomes the running run (it starts, or resumes) first takes
   over the depot's cars: no other live run's per-run owner setting stays in force there
   (ottoq_owner_settings_yield_to_production); then, once what is saved is carried onto it, every car at the depot is
   re-stamped to its target pinned to this production run (ottoq_owner_restamp), never read with no run pinned (this
   trigger runs inside ottoq_production_start's INSERT, before it pins ottoq.sim_run_id). Neither is caught: a production
   run does not start while another run's lower limit, or a stamp it left, would stay in force on its cars. */
BEGIN
  IF NEW.run_by = 'production_live' AND NEW.status = 'running' THEN
    PERFORM public.ottoq_owner_settings_yield_to_production(NEW.sim_run_id);
  END IF;
  BEGIN
    PERFORM public.ottoq_owner_saved_carry(NEW.sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'carrying saved owner settings onto run % failed: % %', NEW.sim_run_id, SQLSTATE, SQLERRM;
  END;
  IF NEW.run_by = 'production_live' AND NEW.status = 'running' THEN
    PERFORM public.ottoq_owner_restamp(NEW.depot_id, NEW.sim_run_id, NULL);
  END IF;
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

--: the run's end lifts a saved command's settings from the run, and does not stamp the command as lifted. (The review,
--: round 3; rule 9, R4) It also runs for a run whose only charge-limit rows were withdrawn or replaced and never reconciled
--: (no tick ran since: a paused run), and it re-stamps those cars as well as the lifted ones, each pinned to the owners' run
--: the depot has once this run has ended (or to no run), never read with no run pinned
DO $lift$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_tg_lift_owner_settings_on_terminal()'::regprocedure);
  v_new text;
  v_pair text[];
  v_pairs text[][] := ARRAY[
    ARRAY[E'     WHERE c.command_id = ANY (COALESCE(v_cmds, ARRAY[]::uuid[])) AND c.lifted_at IS NULL;\n',
          E'     WHERE c.command_id = ANY (COALESCE(v_cmds, ARRAY[]::uuid[])) AND c.lifted_at IS NULL\n'
       || E'       --: 0721 §9: a command whose setting is saved to the car is carried to the next run, not lifted\n'
       || E'       AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings s\n'
       || E'                        WHERE s.command_id = c.command_id AND s.status = ''active'');\n'],
    ARRAY[E'  IF NOT EXISTS (SELECT 1 FROM public.ottoq_owner_settings s WHERE s.sim_run_id = NEW.sim_run_id AND s.status = ''active'') THEN\n',
          E'  --: 0721 (the review, round 3): or a limit withdrawn or replaced on the run that no tick reconciled\n'
       || E'  IF NOT EXISTS (SELECT 1 FROM public.ottoq_owner_settings s WHERE s.sim_run_id = NEW.sim_run_id\n'
       || E'                    AND (s.status = ''active'' OR (s.kind = ''charge_limit'' AND s.pending_reconcile))) THEN\n'],
    ARRAY[E'    UPDATE public.vehicles v\n'
       || E'       SET target_soc = round(public.ottoq_effective_target_soc_at(v.id, v_clock))::int\n'
       || E'     WHERE v.id = ANY (COALESCE(v_cars, ARRAY[]::uuid[]))\n'
       || E'       AND v.target_soc IS DISTINCT FROM round(public.ottoq_effective_target_soc_at(v.id, v_clock))::int;\n',
          E'    --: 0721 (the review, round 3): those cars and every car whose limit here was withdrawn or replaced but not yet\n'
       || E'    --: reconciled, re-stamped pinned to the owners'' run the depot has now (ottoq_owner_run_id; none: no run)\n'
       || E'    PERFORM public.ottoq_owner_restamp(NEW.depot_id, public.ottoq_owner_run_id(NEW.depot_id),\n'
       || E'              ARRAY(SELECT DISTINCT x.id FROM unnest(COALESCE(v_cars, ARRAY[]::uuid[])\n'
       || E'                                                  || ARRAY(SELECT s.vehicle_id FROM public.ottoq_owner_settings s\n'
       || E'                                                            WHERE s.sim_run_id = NEW.sim_run_id AND s.kind = ''charge_limit''\n'
       || E'                                                              AND s.pending_reconcile)) x(id)));\n']];
  v_n int;
BEGIN
  v_new := v_def;
  FOREACH v_pair SLICE 1 IN ARRAY v_pairs LOOP
    v_n := (length(v_new) - length(replace(v_new, v_pair[1], ''))) / length(v_pair[1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0721: an anchor of the lift occurs % times, expected exactly 1: %', v_n, left(v_pair[1], 120);
    END IF;
    v_new := replace(v_new, v_pair[1], v_pair[2]);
  END LOOP;
  EXECUTE v_new;
END $lift$;

--: (the review, round 3; rule 9, R2) what a person changed in what is saved to the cars holds on every live run at the
--: depot, not only the run the command was sent on. Measured on the scratch chain (the review's scen3 s10, s10b, s11 and
--: scen_follow_demo, reproduced 2026-10-15 8:36 AM CT): a person's clear or raise on a demo run while production was
--: paused left production holding the lower limit it had carried, production resumed with it, the car could leave at 84%,
--: a second clear answered no_change, and an undo on production then saved a lower limit back with no preview. Called by
--: the owner command, as its last write, for an applied command recorded under a person: (1) every live run's row that
--: carries a saved row this command ended is withdrawn by this command (the guard admits exactly that, §10), and (2) every
--: other live demo or production run at the depot carries what is saved now (ottoq_owner_saved_carry), so a new or
--: restored saved row is on each of them at once. Each run's tick reconciles its own rows (pending), and a production run
--: re-stamps every car as it takes over. No writer setting of its own: it runs inside the owner command's.
CREATE OR REPLACE FUNCTION public.ottoq_owner_saved_propagate(p_cmd uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  c   public.ottoq_owner_commands;
  r   record;
  v_n integer := 0;
  v_k integer;
BEGIN
  SELECT * INTO c FROM public.ottoq_owner_commands x WHERE x.command_id = p_cmd;
  IF c.command_id IS NULL OR c.mode <> 'apply' OR c.outcome IS DISTINCT FROM 'applied' OR c.acting_person IS NULL
     OR c.created_at <> now() THEN
    RETURN 0;
  END IF;
  UPDATE public.ottoq_owner_settings o
     SET status = 'withdrawn', closed_at = now(), closed_at_sim = x.sim_clock_current, closed_by_command_id = c.command_id,
         pending_reconcile = true, closed_reason = 'what is saved to the car changed on another run'
    FROM public.ottoq_owner_saved_settings s, public.ottoq_sim_runs x
   WHERE o.saved_id = s.saved_id AND s.status = 'ended' AND s.ended_by_command_id = c.command_id AND s.ended_at = now()
     AND o.status = 'active' AND x.sim_run_id = o.sim_run_id AND x.status IN ('running', 'paused');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  FOR r IN SELECT x.sim_run_id FROM public.ottoq_sim_runs x
            WHERE x.depot_id = c.depot_id AND x.status IN ('running', 'paused')
              AND x.run_by IN ('operator_demo', 'production_live') AND x.sim_run_id IS DISTINCT FROM c.sim_run_id
            ORDER BY x.started_at, x.sim_run_id LOOP
    v_k := public.ottoq_owner_saved_carry(r.sim_run_id);
    v_n := v_n + COALESCE(v_k, 0);
  END LOOP;
  RETURN v_n;
END $fn$;

--: (the review, round 3) the owner tick computes each car's target with its own run pinned, never unpinned: in production's
--: world step it runs first, before anything pins ottoq.sim_run_id (twin.ottoq_world_advance, read live 2026-10-15). The
--: tick's body is 0605's otherwise (P1 pins it); this one line is the change
DO $tick$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_owner_orders_tick(uuid,timestamp with time zone)'::regprocedure);
  c_old constant text := E'    v_tgt := public.ottoq_effective_target_soc_at(r.vehicle_id, p_clock);\n';
  c_new constant text := E'    --: 0721 (the review, round 3): with this tick''s run pinned (ottoq_owner_target_on_run), never unpinned\n'
                      || E'    v_tgt := public.ottoq_owner_target_on_run(r.vehicle_id, p_sim_run_id, p_clock);\n';
  v_n int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0721: the tick''s anchor occurs % times, expected exactly 1', v_n;
  END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $tick$;

--: (the review, round 3; rule 9) the engine's one read of an owner limit with no run pinned takes only the owners' run's
--: rows. It took the most recently set active limit on ANY running or paused run, so a paused demo's or an older paused
--: production run's lower limit reached ottoq_effective_target_soc_at and ottoq_departure_clear (and the owner tick and
--: every re-stamp, when they ran unpinned) while production ran (R1, R3, S5). A pinned read ('none', or a run) is 0605's,
--: unchanged; only the unpinned branch moves
DO $climit$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_charge_limit(uuid)'::regprocedure);
  c_old constant text := E'              ELSE EXISTS (SELECT 1 FROM public.ottoq_sim_runs r\n'
                      || E'                            WHERE r.sim_run_id = o.sim_run_id AND r.status IN (''running'', ''paused'')) END\n';
  c_new constant text := E'              --: 0721 (the review, round 3): with nothing pinned, the owners'' run at the setting''s depot only\n'
                      || E'              ELSE o.sim_run_id = public.ottoq_owner_run_id(o.depot_id) END\n';
  v_n int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0721: the owner limit read''s anchor occurs % times, expected exactly 1', v_n;
  END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $climit$;

--: (the review, round 3; rule 9) my_settings, my_fleet and my_vehicle read the owners' run, the one the owner door sends a
--: command to (0605's body otherwise, P1 pins it)
DO $oread$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_owner_read(public.ottoq_agent_principals,text,jsonb)'::regprocedure);
  c_old constant text := E'  v_run      jsonb := public.ottoq_agent_live_run(p_agent.depot_id);\n';
  c_new constant text := E'  v_run      jsonb := public.ottoq_owner_live_run(p_agent.depot_id);   --: 0721 (the review, round 3): the owners'' run\n';
  v_n int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0721: the owner read''s anchor occurs % times, expected exactly 1', v_n;
  END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $oread$;

-- ══ 10. the owner tables' own guard: no setting without an applied command that set it (the 0721 re-review, item 10) ═
--
-- Measured (§1(g)): only postgres holds privileges on ottoq_owner_settings, and only ottoq_owner_command, the tick and the
-- run's end write it (read live 2026-10-14 23:09:07 UTC, 6:09 PM CT: the three functions whose source writes the table);
-- but postgres is also the SQL editor and the Management API, and nothing below the door refused a row no command made.
-- The review, round 1, then wrote plain UPDATEs as postgres that put back a lower limit a person had raised (G4, G1), a
-- saved row from a command the person had since cleared (G2), an every-return order marked fulfilled (G5), and TRUNCATEd
-- the run's settings (G3): each check below asked "is there an applied command that could have done this", and a bare
-- write could name one.
-- So the rule is now WHO writes, first: every write to either table is refused unless it comes from one of the functions
-- that make owner settings, each of which names itself for its own call with a function-level setting
-- (ottoq.owner_settings_writer, SET on the function, so it is in force only while that function runs and is gone when it
-- returns, never left on in the caller's transaction):
--   'owner_command'  public.ottoq_owner_command (the four-argument body every owner command runs), and the triggers it
--                    fires (the save, the follow, the saved table's writes);
--   'tick'           ottoq.ottoq_owner_orders_tick (0605's body, unchanged; only the setting is added, md5 pinned in P1);
--   'run_end'        public.ottoq_tg_lift_owner_settings_on_terminal;
--   'carry'          public.ottoq_owner_saved_carry;
--   'production_start' public.ottoq_owner_settings_yield_to_production (the review, round 2: §9's run-start trigger, as a
--                    production run starts, resumes or pauses).
-- A plain INSERT, UPDATE or DELETE as postgres, as service_role or as anyone else is refused (service_role and the
-- browser roles hold no privilege on either table anyway, V2), and so is TRUNCATE (a statement trigger on each table).
-- Then each move only from the writer that makes it, as it makes it:
--   INSERT  by the owner command, on its own run, of what that command (recorded in this transaction) set; or by the
--           carry, of a saved row that command made. Same fleet and depot, a car the command names, the kind and value.
--   UPDATE  what was set is immutable. replaced | withdrawn: the owner command, by the applied command recorded in this
--           transaction that names the car, of a tool that makes that change. fulfilled: the tick, for a hold whose time
--           has come or a one-time order whose service is done. lifted: the run's end, on an ended run, or a production
--           run taking over the depot, on a run that is not production while one is live there. replaced -> active: the
--           owner command's undo of the command that replaced it, or the tick, for an every-return order whose one-time
--           order is done (§9). Other columns (pending_reconcile, applied): the owner command or the tick.
--   DELETE  only the run purge (ottoq.retention, armed by ottoq_purge_prior_runs; registry check (d) requires it).
-- The saved table: written by the owner command only; a row only for an applied (or saved) command recorded under a
-- person that set exactly that, in this transaction; status moves active -> ended by such a command naming the car, and
-- ended -> active only by a person's undo, in this transaction, of the command that ended it (the follow puts it back on
-- that condition only, unlock or not: the review, round 2); how a row ended is immutable;
-- never deleted or truncated. ottoq.agent_ledger_unlock (the owner ledger's existing escape hatch, to be named in a
-- migration that says why) opens both, as it opens the commands table.

CREATE OR REPLACE FUNCTION public.ottoq_owner_settings_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  c  public.ottoq_owner_commands;
  sv public.ottoq_owner_saved_settings;
  v_ok boolean;
  --: (the review, round 1) which function is writing: each writer sets this for its own call (§10's header)
  v_writer text := COALESCE(current_setting('ottoq.owner_settings_writer', true), '');
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
  IF v_writer NOT IN ('owner_command', 'tick', 'run_end', 'carry', 'production_start') THEN
    RAISE EXCEPTION 'ottoq_owner_settings: % refused; an owner setting is written only by an owner command, OTTO-Q''s tick, its run''s end, the carry of what an owner saved or a production run taking over its depot, never by a plain write',
      TG_OP USING ERRCODE = '42501',
      HINT = 'A migration that must write one sets ottoq.agent_ledger_unlock = on and says why.';
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
    IF v_ok AND (c.sim_run_id IS DISTINCT FROM NEW.sim_run_id OR v_writer = 'carry') THEN
      --: on another run: only the carry, of a saved row this very command made. (The review, round 3) And the carry on the
      --: command's own run, once what stood for its row there is gone (ottoq_owner_saved_carry's chain rule: a production
      --: run lifted what replaced it, or a command since undone withdrew it): refused, a demo run resumed after production
      --: lost the person's order or limit for the rest of the run, and a person's undo that brought a saved row back on
      --: another run failed outright (§17's propagation carries it here)
      SELECT * INTO sv FROM public.ottoq_owner_saved_settings x WHERE x.saved_id = NEW.saved_id;
      v_ok := v_writer = 'carry' AND sv.saved_id IS NOT NULL AND sv.status = 'active' AND sv.command_id = NEW.command_id
          AND sv.vehicle_id = NEW.vehicle_id AND sv.kind = NEW.kind
          AND sv.charge_limit_pct IS NOT DISTINCT FROM NEW.charge_limit_pct AND sv.service IS NOT DISTINCT FROM NEW.service;
    ELSIF v_ok THEN
      --: on its own run: only the owner command, as the command records itself (the review, round 1): a row an old
      --: command once set, written again after the owner changed it, is a replay, not what any command did now
      v_ok := v_writer = 'owner_command' AND c.created_at = now();
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
  IF NEW.status IS NOT DISTINCT FROM OLD.status AND v_writer NOT IN ('owner_command', 'tick') THEN
    --: the bookkeeping columns (pending_reconcile, applied) are the owner command's and the tick's
    RAISE EXCEPTION 'owner setting %: only an owner command or OTTO-Q''s tick updates it without a change of status', OLD.setting_id
      USING ERRCODE = '42501';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT ((OLD.status = 'active' AND NEW.status IN ('replaced', 'withdrawn', 'fulfilled', 'lifted'))
            OR (OLD.status = 'replaced' AND NEW.status = 'active')) THEN
      RAISE EXCEPTION 'owner setting %: % -> % is not a change an owner command, the tick or the run''s end makes',
        OLD.setting_id, OLD.status, NEW.status USING ERRCODE = '42501';
    END IF;
    --: (the review, round 1) each move only as the writer that makes it makes it
    IF NEW.status IN ('replaced', 'withdrawn') THEN
      --: by the applied owner command recording itself in this transaction, on this run, naming this car, of a tool that
      --: makes this change (0605's writes: a new limit, hold or order replaces; a clear, a full limit, a release, a
      --: cancel or an undo withdraws)
      c := NULL;
      SELECT * INTO c FROM public.ottoq_owner_commands x WHERE x.command_id = NEW.closed_by_command_id;
      v_ok := v_writer = 'owner_command'
          AND c.command_id IS NOT NULL AND c.mode = 'apply' AND c.outcome = 'applied' AND c.created_at = now()
          AND c.sim_run_id = NEW.sim_run_id AND c.fleet_operator_id = NEW.fleet_operator_id AND c.depot_id = NEW.depot_id
          AND c.vehicles @> jsonb_build_array(jsonb_build_object('id', NEW.vehicle_id::text))
          AND CASE WHEN NEW.status = 'replaced'
                   THEN c.tool = CASE NEW.kind WHEN 'charge_limit' THEN 'set_charge_limit' WHEN 'hold' THEN 'hold_vehicle'
                                               ELSE 'request_service' END
                   ELSE c.tool = ANY (CASE NEW.kind WHEN 'charge_limit' THEN ARRAY['set_charge_limit', 'clear_charge_limit', 'undo_command']
                                                    WHEN 'hold' THEN ARRAY['release_hold', 'undo_command']
                                                    ELSE ARRAY['cancel_service', 'undo_command'] END) END;
      --: (the review, round 3) or withdrawn on another live run, by the applied command recorded under a person in this
      --: transaction that ended the saved row this row carries (ottoq_owner_saved_propagate): what is saved holds on every run
      IF NOT COALESCE(v_ok, false) AND NEW.status = 'withdrawn' AND OLD.saved_id IS NOT NULL THEN
        v_ok := v_writer = 'owner_command'
            AND c.command_id IS NOT NULL AND c.mode = 'apply' AND c.outcome = 'applied' AND c.created_at = now()
            AND c.acting_person IS NOT NULL
            AND c.fleet_operator_id = NEW.fleet_operator_id AND c.depot_id = NEW.depot_id
            AND c.vehicles @> jsonb_build_array(jsonb_build_object('id', NEW.vehicle_id::text))
            AND EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings x
                         WHERE x.saved_id = OLD.saved_id AND x.status = 'ended' AND x.ended_by_command_id = c.command_id
                           AND x.ended_at = now())
            AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id AND r.status IN ('running', 'paused'));
      END IF;
      IF NOT COALESCE(v_ok, false) THEN
        RAISE EXCEPTION 'owner setting %: replaced or withdrawn only by the applied owner command that names its car, as that command records itself',
          OLD.setting_id USING ERRCODE = '42501';
      END IF;
    ELSIF NEW.status = 'fulfilled' THEN
      --: by the tick only, on its own test: a hold whose time has come, or a one-time order whose service is done on a visit
      --: of the run. An every-return order and a charge limit are never fulfilled
      v_ok := v_writer = 'tick' AND CASE OLD.kind
                WHEN 'hold' THEN NEW.closed_at_sim IS NOT NULL AND OLD.hold_until_sim <= NEW.closed_at_sim
                WHEN 'service' THEN OLD.service_when IN ('now', 'next_return')
                  AND EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
                               WHERE vn.vehicle_id = OLD.vehicle_id AND vn.sim_run_id = OLD.sim_run_id
                                 AND jsonb_typeof(a -> 'owner_setting_ids') = 'array'
                                 AND (a -> 'owner_setting_ids') @> jsonb_build_array(OLD.setting_id::text)
                                 AND a ->> 'status' = 'done')
                ELSE false END;
      IF NOT COALESCE(v_ok, false) THEN
        RAISE EXCEPTION 'owner setting %: fulfilled only by the tick, for a hold whose time has come or a one-time order whose service is done',
          OLD.setting_id USING ERRCODE = '42501';
      END IF;
    ELSIF NEW.status = 'lifted' THEN
      --: by the run's end: its run has ended; or (the review, rounds 2 and 3) by a production run taking over its depot
      --: (ottoq_owner_settings_yield_to_production): a per-run row (no saved_id) of another live run, a paused production
      --: run's included, while a production run RUNS at the depot. Exactly the takeover's lifts and nothing more
      IF NOT ((v_writer = 'run_end'
               AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                            WHERE r.sim_run_id = OLD.sim_run_id AND r.status IN ('completed', 'failed', 'aborted')))
              OR (v_writer = 'production_start' AND OLD.saved_id IS NULL
                  AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                                JOIN public.ottoq_sim_runs p ON p.depot_id = r.depot_id AND p.sim_run_id <> r.sim_run_id
                               WHERE r.sim_run_id = OLD.sim_run_id AND r.status IN ('running', 'paused')
                                 AND p.run_by = 'production_live' AND p.status = 'running'))) THEN
        RAISE EXCEPTION 'owner setting %: lifted only when its run ends, or when a production run takes over its depot',
          OLD.setting_id USING ERRCODE = '42501';
      END IF;
    ELSE
      --: replaced -> active: (a) an undo, in this transaction: the row that replaced it (the one its closing command made) is
      --: withdrawn by an applied undo of that command; or (b) an every-return order resuming once the one-time order(s) that
      --: took its place on the run are done (ottoq_owner_settings_saved_follow)
      v_ok := v_writer = 'owner_command' AND EXISTS (SELECT 1 FROM public.ottoq_owner_settings r
                        JOIN public.ottoq_owner_commands u ON u.command_id = r.closed_by_command_id
                       WHERE r.replaces_setting_id = OLD.setting_id AND r.command_id = OLD.closed_by_command_id
                         AND r.status = 'withdrawn' AND u.tool = 'undo_command' AND u.outcome = 'applied'
                         AND u.undoes_command_id = r.command_id AND u.created_at = now());
      IF NOT v_ok AND v_writer = 'tick' AND OLD.kind = 'service' AND OLD.service_when = 'every_return' THEN
        WITH RECURSIVE ch AS (
          SELECT r.setting_id, r.status, r.closed_by_command_id, 1 AS n
            FROM public.ottoq_owner_settings r
           WHERE r.replaces_setting_id = OLD.setting_id AND r.command_id = OLD.closed_by_command_id
             AND r.sim_run_id = OLD.sim_run_id AND r.vehicle_id = OLD.vehicle_id AND r.kind = 'service'
             AND r.service = OLD.service AND r.service_when IN ('now', 'next_return')
          UNION ALL
          SELECT r.setting_id, r.status, r.closed_by_command_id, ch.n + 1
            FROM ch JOIN public.ottoq_owner_settings r
                      ON r.replaces_setting_id = ch.setting_id AND r.command_id = ch.closed_by_command_id
           WHERE ch.status = 'replaced' AND ch.n < 50 AND r.sim_run_id = OLD.sim_run_id AND r.vehicle_id = OLD.vehicle_id
             AND r.kind = 'service' AND r.service = OLD.service AND r.service_when IN ('now', 'next_return'))
        SELECT EXISTS (SELECT 1 FROM ch WHERE ch.status = 'fulfilled') INTO v_ok;
      END IF;
      IF NOT COALESCE(v_ok, false) THEN
        RAISE EXCEPTION 'owner setting %: put back only by an undo of the command that replaced it, or (an every-return order) once the one-time order that took its place is done',
          OLD.setting_id USING ERRCODE = '42501';
      END IF;
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
  --: (the review, round 1) written by the owner command only (§10's header), never by a plain write
  IF COALESCE(current_setting('ottoq.owner_settings_writer', true), '') <> 'owner_command' THEN
    RAISE EXCEPTION 'ottoq_owner_saved_settings: % refused; what an owner saved to a car is written only by an owner command, never by a plain write',
      TG_OP USING ERRCODE = '42501',
      HINT = 'A migration that must write one sets ottoq.agent_ledger_unlock = on and says why.';
  END IF;
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO c FROM public.ottoq_owner_commands x WHERE x.command_id = NEW.command_id;
    --: and only as that command records itself (the review, round 1): a saved row written again from an old command after
    --: the owner cleared or replaced it is a replay, not what any command did now
    IF NOT COALESCE(c.mode = 'apply' AND c.outcome IN ('applied', 'saved') AND c.acting_person IS NOT NULL
                    AND c.created_at = now()
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
  IF OLD.status = NEW.status THEN
    --: (the review, round 1) how a saved row ended is as immutable as what was saved
    IF (NEW.ended_at, NEW.ended_reason, NEW.ended_by_command_id) IS DISTINCT FROM (OLD.ended_at, OLD.ended_reason, OLD.ended_by_command_id) THEN
      RAISE EXCEPTION 'saved owner setting %: how it ended is immutable', OLD.saved_id USING ERRCODE = '42501';
    END IF;
  ELSIF OLD.status = 'active' AND NEW.status = 'ended' THEN
    --: by an applied (or saved) command recorded under a person, as it records itself, naming this car
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_owner_commands x
                    WHERE x.command_id = NEW.ended_by_command_id AND x.outcome IN ('applied', 'saved') AND x.acting_person IS NOT NULL
                      AND x.created_at = now()
                      AND x.fleet_operator_id = NEW.fleet_operator_id AND x.depot_id = NEW.depot_id
                      AND x.vehicles @> jsonb_build_array(jsonb_build_object('id', NEW.vehicle_id::text))) THEN
      RAISE EXCEPTION 'saved owner setting %: ended only by an applied owner command recorded under a person', OLD.saved_id
        USING ERRCODE = '42501';
    END IF;
  ELSIF OLD.status = 'ended' AND NEW.status = 'active' THEN
    --: (the review, round 1) put back only by an undo, in this transaction, of the command that ended it, while the run row
    --: that carries it is in force again (ottoq_owner_settings_saved_follow, on the undo's restore)
    IF NOT (EXISTS (SELECT 1 FROM public.ottoq_owner_commands u
                     WHERE u.tool = 'undo_command' AND u.outcome = 'applied' AND u.acting_person IS NOT NULL
                       AND u.undoes_command_id = OLD.ended_by_command_id AND u.created_at = now())
            AND EXISTS (SELECT 1 FROM public.ottoq_owner_settings o WHERE o.saved_id = OLD.saved_id AND o.status = 'active')) THEN
      RAISE EXCEPTION 'saved owner setting %: put back only by an undo of the command that ended it', OLD.saved_id
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END $fn$;

--: the writers name themselves, each for its own call (a function-level setting: in force while the function runs, gone
--: when it returns). The tick's body is unchanged; only this setting is added (P1 pins its body, the snapshot holds it)
ALTER FUNCTION public.ottoq_owner_command(public.ottoq_agent_principals, text, jsonb, text) SET ottoq.owner_settings_writer = 'owner_command';
ALTER FUNCTION ottoq.ottoq_owner_orders_tick(uuid, timestamp with time zone) SET ottoq.owner_settings_writer = 'tick';
ALTER FUNCTION public.ottoq_tg_lift_owner_settings_on_terminal() SET ottoq.owner_settings_writer = 'run_end';
ALTER FUNCTION public.ottoq_owner_saved_carry(uuid) SET ottoq.owner_settings_writer = 'carry';
ALTER FUNCTION public.ottoq_owner_settings_yield_to_production(uuid) SET ottoq.owner_settings_writer = 'production_start';

CREATE TRIGGER ottoq_owner_settings_guard_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.ottoq_owner_settings
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_settings_guard();
CREATE TRIGGER ottoq_owner_saved_settings_guard_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.ottoq_owner_saved_settings
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_saved_settings_guard();
CREATE TRIGGER ottoq_owner_saved_settings_no_truncate_trg
  BEFORE TRUNCATE ON public.ottoq_owner_saved_settings
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();
--: (the review, round 1) a row trigger cannot see TRUNCATE: the run's settings refuse it too. The run purge deletes row by
--: row under ottoq.retention, and no function on the live catalog truncates anything (read 2026-10-14 21:06:44 UTC, 4:06 PM
--: CT: the one function whose source names TRUNCATE is ottoq_agent_no_truncate itself)
CREATE TRIGGER ottoq_owner_settings_no_truncate_trg
  BEFORE TRUNCATE ON public.ottoq_owner_settings
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();

-- ══ 11. my_settings says what is saved to the cars ═════════════════════════════════════════════════════════════════
--
-- And (the review, round 2) a command's id goes only to the agent that made the command, or to the person it is recorded
-- under. Measured on the scratch chain (the review's a2b_hidden_ids, reproduced the evening of 2026-10-14 CT): 0605's
-- reads list every active setting of the fleet on the run with its command_id (my_settings' settings, my_fleet's and
-- my_vehicle's yours.orders), whoever made it, and §9 now carries a person's production and no-run commands onto demo
-- runs: so a passcode session and an issued key on the same fleet read the ids of a person's commands that §15 keeps off
-- the cockpit boards, and §11's "its command is shown only to that same person" did not hold. 0605's bodies stay as they
-- are (md5-pinned): ottoq_owner_read_shown returns their answer with every command_id the reader did not make, and that is
-- not recorded under the reader's person, set to null. The setting itself is still shown (the fleet's cars are the
-- reader's to read); my_commands lists only the reader's own commands already.

--: every "command_id" in a read, at any depth, kept only when the command is the reader's (same principal) or recorded
--: under the reader's person; otherwise null. A read with no command_id in it is returned as it is
CREATE OR REPLACE FUNCTION public.ottoq_owner_mask_command_ids(p_json jsonb, p_principal uuid, p_person text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_out jsonb;
  v_key text;
  v_val jsonb;
BEGIN
  IF p_json IS NULL OR jsonb_typeof(p_json) NOT IN ('object', 'array') OR strpos(p_json::text, '"command_id"') = 0 THEN
    RETURN p_json;
  END IF;
  IF jsonb_typeof(p_json) = 'array' THEN
    SELECT COALESCE(jsonb_agg(public.ottoq_owner_mask_command_ids(x.e, p_principal, p_person) ORDER BY x.o), '[]'::jsonb)
      INTO v_out FROM jsonb_array_elements(p_json) WITH ORDINALITY x(e, o);
    RETURN v_out;
  END IF;
  v_out := '{}'::jsonb;
  FOR v_key, v_val IN SELECT k.key, k.value FROM jsonb_each(p_json) k LOOP
    IF v_key = 'command_id' THEN
      IF jsonb_typeof(v_val) IS DISTINCT FROM 'null'
         AND NOT (jsonb_typeof(v_val) = 'string'
                  AND (v_val #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                  AND EXISTS (SELECT 1 FROM public.ottoq_owner_commands c
                               WHERE c.command_id = (v_val #>> '{}')::uuid
                                 AND (c.principal_id = p_principal
                                      OR (c.acting_person IS NOT NULL AND c.acting_person = p_person)))) THEN
        v_val := 'null'::jsonb;
      END IF;
    ELSE
      v_val := public.ottoq_owner_mask_command_ids(v_val, p_principal, p_person);
    END IF;
    v_out := v_out || jsonb_build_object(v_key, v_val);
  END LOOP;
  RETURN v_out;
END $fn$;

--: my_fleet and my_vehicle (0605's reads) as this reader may see them: a command id only to its own maker, or its person
CREATE OR REPLACE FUNCTION public.ottoq_owner_read_shown(p_agent public.ottoq_agent_principals, p_read jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT public.ottoq_owner_mask_command_ids(p_read, p_agent.principal_id, public.ottoq_owner_acting_person(p_agent))
$fn$;

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
   a row (saved_by) and the command that saved it are shown only to that same person. And (the review, round 2) the run's
   settings name their command only to the agent that made it or its person (ottoq_owner_mask_command_ids): a passcode
   session or an issued key read the ids of a person's carried production and no-run commands here. */
DECLARE
  v_saved  jsonb;
  v_lines  text;
  v_sum    text := COALESCE(p_read ->> 'summary', '');
  v_person text := public.ottoq_owner_acting_person(p_agent);
BEGIN
  p_read := public.ottoq_owner_mask_command_ids(p_read, p_agent.principal_id, v_person);
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
                      || E'    v_msg := ''A production run is live at the twin depot, so the demo passcode opens nothing right now: production is changed only by an agent signed in to its owner''''s OTTOYARD account, and an owner''''s settings and commands there are read only with that owner''''s own credentials, never a demo passcode. Nothing was opened. Try again once the production run ends, or sign your agent in to your OTTOYARD account.'';\n'
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
  public.ottoq_owner_settings_yield_to_production(uuid),
  public.ottoq_owner_saved_propagate(uuid),
  public.ottoq_owner_mask_command_ids(jsonb, uuid, text),
  public.ottoq_owner_read_shown(public.ottoq_agent_principals, jsonb),
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

-- ══ 15. the cockpit boards keep production and a person's own words to the person's own agent (the review, round 1) ═══
--
-- Measured (read live 2026-10-14 21:03:34 UTC, 4:03 PM CT): ottoq_owner_board(uuid,uuid,uuid) and
-- ottoq_depot_owner_board(uuid,integer) are EXECUTE for anon, authenticated and service_role (0606 and 0608 granted anon
-- for the demo cockpits, OrchestrAV, OTTO-PULSE and OTTO-TWIN, which read with the publishable key). They list the settings
-- in force on the live run and the depot's last owner commands, and the owner board's highlight returns a command's
-- arguments, note included. Before this file no production run took an owner command, so that exposure was a demo's. With
-- this file a signed-in owner changes production, and the gateway sets every OTTO-Command command's note to the person's own
-- words: on a scratch run a production command's id, its note and the production run's settings in force were all
-- readable as anon. Both boards now leave out (a) the settings in force when the live run is a production run, (b) every
-- command made on a production run and every command a person made with no run live (a 'saved' command and its
-- refusals), (c) in the owner board's highlight, the note of any command recorded under a person, and (d) on a demo run,
-- the command id (and the depot board's confirmation code) of a setting carried there from what a person saved, when that
-- command is one of (b). A demo run's settings and commands read otherwise exactly as before, and nothing is granted or
-- revoked: the boards stay the demo cockpits' read, and an owner reads production through their own signed-in agent
-- (my_settings, my_commands). The 'resets' line says what is saved.
-- What each page loses (the twin app read in ottoyarddepot-sim at de7dbda, 2026-10-14: it calls only
-- ottoq_depot_owner_board, from src/hooks/useOwnerBoard.ts, and reads run, in_force, by_vehicle, commands, agents, counts and resets;
-- never args or a note): while a production run is live, the owner markers on the 3D depot
-- (components/canvas/three/OwnerMarkers.tsx), the owner line on a car's dot and card (VehicleDot.tsx, VehicleQCard.tsx)
-- and the owner commands in the live feed, the agent tab and the bottom bar (liveFeed.ts, TwinAgentTab.tsx,
-- BottomBar.tsx) show nothing; on any run, a signed-in owner's commands made with no run live are not in the feed; and a
-- carried setting's chip shows no confirmation code when its command is hidden. Demo runs otherwise draw as before.
-- ottoq_owner_board's readers (OrchestrAV, OTTO-PULSE) are not in this session's repositories and were not read: from the
-- body, while production is live their in-force lists are empty, production commands are not listed, a receipt link to a
-- production command or a no-run command finds no highlight, and a signed-in owner's demo command shows no note.
DO $boards$
DECLARE
  c_prod constant text := 'AND NOT (c.sim_run_id IS NULL AND c.acting_person IS NOT NULL) '
                       || 'AND NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = c.sim_run_id AND r.run_by = ''production_live'')';
  c_why  constant text := '--: 0721 §15: not a production command, and not a person''s command made with no run live';
  v_def   text;
  v_new   text;
  v_pair  text[];
  v_pairs text[];
  v_n     int;
BEGIN
  -- ottoq_owner_board
  v_def := pg_get_functiondef('public.ottoq_owner_board(uuid,uuid,uuid)'::regprocedure);
  v_pairs := ARRAY[
    --: (the review, round 3) the board reads the owners' run, the one every owner path uses
    ARRAY[E'  v_run := public.ottoq_agent_live_run(p_depot_id);\n',
          E'  v_run := public.ottoq_owner_live_run(p_depot_id);   --: 0721 (the review, round 3): the owners'' run\n'],
    ARRAY[E'           ''command_id'', o.command_id, ''waiting_for_tick'', o.pending_reconcile))\n',
          E'           --: 0721 §15: a setting carried from what a person saved names its command only when this board shows it\n'
       || E'           ''command_id'', CASE WHEN EXISTS (SELECT 1 FROM public.ottoq_owner_commands c WHERE c.command_id = o.command_id\n'
       || E'                                     ' || c_prod || E') THEN o.command_id END,\n'
       || E'           ''waiting_for_tick'', o.pending_reconcile))\n'],
    ARRAY[E'   WHERE o.sim_run_id = v_run_id AND o.fleet_operator_id = p_fleet_operator_id AND o.depot_id = p_depot_id\n     AND o.status = ''active'';\n',
          E'   WHERE o.sim_run_id = v_run_id AND o.fleet_operator_id = p_fleet_operator_id AND o.depot_id = p_depot_id\n     AND o.status = ''active''\n'
       || E'     --: 0721 §15: a production run''s settings are read by the owner''s own signed-in agent, not by this board\n'
       || E'     AND v_run ->> ''run_by'' IS DISTINCT FROM ''production_live'';\n'],
    ARRAY[E'           WHERE c.fleet_operator_id = p_fleet_operator_id AND c.depot_id = p_depot_id AND c.outcome <> ''previewed''\n',
          E'           WHERE c.fleet_operator_id = p_fleet_operator_id AND c.depot_id = p_depot_id AND c.outcome <> ''previewed''\n'
       || '             ' || c_why || E'\n             ' || c_prod || E'\n'],
    ARRAY[E'     WHERE c.command_id = p_command_id AND c.fleet_operator_id = p_fleet_operator_id AND c.outcome <> ''previewed'';\n',
          E'     WHERE c.command_id = p_command_id AND c.fleet_operator_id = p_fleet_operator_id AND c.outcome <> ''previewed''\n'
       || '       ' || c_why || E'\n       ' || c_prod || E';\n'],
    ARRAY[E'''args'', c.args - ''idempotency_key'',',
          E'''args'', CASE WHEN c.acting_person IS NULL THEN c.args - ''idempotency_key'' ELSE c.args - ''idempotency_key'' - ''note'' END,   --: 0721 §15: a person''s own words stay theirs'],
    ARRAY['''resets'', ''Everything an agent sets lasts until the demo run ends or the agent undoes it; a stop or reset of the twin puts every car back to baseline.'',',
          '''resets'', ''What an agent sets lasts until the demo run ends or the agent undoes it, except a charge limit or an every-return order set by an owner signed in to their OTTOYARD account: that is saved to the car and carried onto every run until the owner changes it; a stop or reset of the twin puts every other setting back to baseline. A production run''''s settings and commands are not shown here; an owner reads them through their own signed-in agent.'',']];
  v_new := v_def;
  FOREACH v_pair SLICE 1 IN ARRAY v_pairs LOOP
    v_n := (length(v_new) - length(replace(v_new, v_pair[1], ''))) / length(v_pair[1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0721 §15: an anchor of ottoq_owner_board occurs % times, expected exactly 1: %', v_n, left(v_pair[1], 80);
    END IF;
    v_new := replace(v_new, v_pair[1], v_pair[2]);
  END LOOP;
  EXECUTE v_new;
  -- ottoq_depot_owner_board
  v_def := pg_get_functiondef('public.ottoq_depot_owner_board(uuid,integer)'::regprocedure);
  v_pairs := ARRAY[
    --: (the review, round 3) the board reads the owners' run, the one every owner path uses
    ARRAY[E'  v_run := public.ottoq_agent_live_run(p_depot_id);\n',
          E'  v_run := public.ottoq_owner_live_run(p_depot_id);   --: 0721 (the review, round 3): the owners'' run\n'],
    ARRAY[E'           ''command_id'', o.command_id,\n           ''confirmation_code'', public.ottoq_owner_confirmation_code(o.command_id),\n',
          E'           --: 0721 §15: a setting carried from what a person saved names its command (and code) only when this board shows it\n'
       || E'           ''command_id'', CASE WHEN v_shown THEN o.command_id END,\n'
       || E'           ''confirmation_code'', CASE WHEN v_shown THEN public.ottoq_owner_confirmation_code(o.command_id) END,\n'],
    ARRAY[E'    LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = cmd.principal_id\n   WHERE o.sim_run_id = v_run_id',
          E'    LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = cmd.principal_id\n'
       || E'    CROSS JOIN LATERAL (SELECT EXISTS (SELECT 1 FROM public.ottoq_owner_commands c WHERE c.command_id = o.command_id\n'
       || E'                                         ' || c_prod || E')) sh(v_shown)\n'
       || E'   WHERE o.sim_run_id = v_run_id'],
    ARRAY[E'   WHERE o.sim_run_id = v_run_id AND o.depot_id = p_depot_id AND o.status = ''active'';\n',
          E'   WHERE o.sim_run_id = v_run_id AND o.depot_id = p_depot_id AND o.status = ''active''\n'
       || E'     --: 0721 §15: a production run''s settings are read by each owner''s own signed-in agent, not by this board\n'
       || E'     AND v_run ->> ''run_by'' IS DISTINCT FROM ''production_live'';\n'],
    ARRAY[E'           WHERE c.depot_id = p_depot_id AND c.outcome <> ''previewed''\n',
          E'           WHERE c.depot_id = p_depot_id AND c.outcome <> ''previewed''\n'
       || '             ' || c_why || E'\n             ' || c_prod || E'\n'],
    ARRAY['''resets'', ''Everything an owner''''s agent sets lasts until the demo run ends or the agent undoes it; a stop or reset of the twin puts every car back to baseline and ends every passcode session.'',',
          '''resets'', ''What an owner''''s agent sets lasts until the demo run ends or the agent undoes it, except a charge limit or an every-return order set by an owner signed in to their OTTOYARD account: that is saved to the car and carried onto every run until the owner changes it. A stop or reset of the twin puts every other setting back to baseline and ends every passcode session. A production run''''s settings and commands are not shown here; each owner reads them through their own signed-in agent.'',']];
  v_new := v_def;
  FOREACH v_pair SLICE 1 IN ARRAY v_pairs LOOP
    v_n := (length(v_new) - length(replace(v_new, v_pair[1], ''))) / length(v_pair[1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0721 §15: an anchor of ottoq_depot_owner_board occurs % times, expected exactly 1: %', v_n, left(v_pair[1], 80);
    END IF;
    v_new := replace(v_new, v_pair[1], v_pair[2]);
  END LOOP;
  EXECUTE v_new;
END $boards$;

-- ══ V1: the bodies say what this file says they do ══════════════════════════════════════════════════════════════════
--
-- (The review, round 3) Every check reads CODE: each body is read with its comments taken out first (block comments,
-- then line comments), so a branch that is commented out, or kept only as a comment, fails V1. Before, a string search
-- over pg_get_functiondef passed with the round-2 fixes commented out (the review's mutations M1 and M3).
DO $v1$
DECLARE
  c_strip_line constant text := '--[^' || chr(10) || ']*';
  v_src   text;
  v_cmd   text := pg_get_functiondef('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb,text)'::regprocedure);
  v_three text := pg_get_functiondef('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb)'::regprocedure);
  v_call  text := pg_get_functiondef('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure);
  v_reply text := pg_get_functiondef('public.ottoq_owner_command_reply(public.ottoq_owner_commands,boolean)'::regprocedure);
  v_who   text := pg_get_functiondef('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure);
  v_guard text := pg_get_functiondef('public.ottoq_owner_commands_guard()'::regprocedure);
  v_bind  text := pg_get_functiondef('public.ottoq_owner_confirm_binding(public.ottoq_agent_principals,uuid,text,jsonb,text,text,uuid,boolean)'::regprocedure);
  v_lift  text := pg_get_functiondef('public.ottoq_tg_lift_owner_settings_on_terminal()'::regprocedure);
  v_door  text := pg_get_functiondef('public.ottoq_agent_public_call(text,jsonb,text,jsonb,timestamp with time zone)'::regprocedure);
  v_gate  text := pg_get_functiondef('public.ottoq_owner_write_gate(public.ottoq_agent_principals,jsonb)'::regprocedure);
  v_sg    text := pg_get_functiondef('public.ottoq_owner_settings_guard()'::regprocedure);
  v_svg   text := pg_get_functiondef('public.ottoq_owner_saved_settings_guard()'::regprocedure);
  v_sread text := pg_get_functiondef('public.ottoq_owner_settings_read(public.ottoq_agent_principals,jsonb)'::regprocedure);
  v_fol   text := pg_get_functiondef('public.ottoq_owner_settings_saved_follow()'::regprocedure);
  v_start text := pg_get_functiondef('public.ottoq_tg_owner_saved_on_run_start()'::regprocedure);
  v_board text := pg_get_functiondef('public.ottoq_owner_board(uuid,uuid,uuid)'::regprocedure);
  v_dbrd  text := pg_get_functiondef('public.ottoq_depot_owner_board(uuid,integer)'::regprocedure);
  v_yield text := pg_get_functiondef('public.ottoq_owner_settings_yield_to_production(uuid)'::regprocedure);
  v_carry text := pg_get_functiondef('public.ottoq_owner_saved_carry(uuid)'::regprocedure);
  v_tick  text := pg_get_functiondef('ottoq.ottoq_owner_orders_tick(uuid,timestamp with time zone)'::regprocedure);
  v_lim   text := pg_get_functiondef('public.ottoq_owner_charge_limit(uuid)'::regprocedure);
  v_read  text := pg_get_functiondef('public.ottoq_owner_read(public.ottoq_agent_principals,text,jsonb)'::regprocedure);
  v_prop  text := pg_get_functiondef('public.ottoq_owner_saved_propagate(uuid)'::regprocedure);
  v_runid text := pg_get_functiondef('public.ottoq_owner_run_id(uuid)'::regprocedure);
  v_pin   text := pg_get_functiondef('public.ottoq_owner_target_on_run(uuid,uuid,timestamp with time zone)'::regprocedure);
  v_bad   text;
BEGIN
  --: the code of each body, comments taken out
  v_cmd   := regexp_replace(regexp_replace(v_cmd,   '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_three := regexp_replace(regexp_replace(v_three, '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_call  := regexp_replace(regexp_replace(v_call,  '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_reply := regexp_replace(regexp_replace(v_reply, '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_who   := regexp_replace(regexp_replace(v_who,   '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_guard := regexp_replace(regexp_replace(v_guard, '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_bind  := regexp_replace(regexp_replace(v_bind,  '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_lift  := regexp_replace(regexp_replace(v_lift,  '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_door  := regexp_replace(regexp_replace(v_door,  '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_gate  := regexp_replace(regexp_replace(v_gate,  '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_sg    := regexp_replace(regexp_replace(v_sg,    '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_svg   := regexp_replace(regexp_replace(v_svg,   '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_sread := regexp_replace(regexp_replace(v_sread, '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_fol   := regexp_replace(regexp_replace(v_fol,   '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_start := regexp_replace(regexp_replace(v_start, '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_board := regexp_replace(regexp_replace(v_board, '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_dbrd  := regexp_replace(regexp_replace(v_dbrd,  '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_yield := regexp_replace(regexp_replace(v_yield, '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_carry := regexp_replace(regexp_replace(v_carry, '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_tick  := regexp_replace(regexp_replace(v_tick,  '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_lim   := regexp_replace(regexp_replace(v_lim,   '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_read  := regexp_replace(regexp_replace(v_read,  '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_prop  := regexp_replace(regexp_replace(v_prop,  '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_runid := regexp_replace(regexp_replace(v_runid, '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  v_pin   := regexp_replace(regexp_replace(v_pin,   '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  --: and the stripping itself must be what it says: a commented-out branch is gone, and code is kept
  v_src := regexp_replace(regexp_replace(E'a := 1; --: b := 2;\n/* c := 3; */ d := 4;', '/\*.*?\*/', '', 'g'), c_strip_line, '', 'g');
  IF strpos(v_src, 'b := 2') > 0 OR strpos(v_src, 'c := 3') > 0 OR strpos(v_src, 'a := 1') = 0 OR strpos(v_src, 'd := 4') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the comment stripping does not take out comments and keep code: %', v_src;
  END IF;

  IF strpos(v_cmd, 'v_gate := public.ottoq_owner_write_gate(p_agent, v_run);') = 0
     OR strpos(v_cmd, 'v_bind := public.ottoq_owner_confirm_binding(p_agent, v_run_id, v_tool, v_norm, v_plan, v_expect, v_confirms,') = 0
     OR strpos(v_cmd, 'v_door        text := CASE p_via WHEN ''ask'' THEN ''ottocommand'' ELSE ''direct'' END;') = 0
     OR strpos(v_cmd, 'ELSE' || chr(10) || '      v_via := ''confirm'';') = 0
     OR strpos(v_cmd, '''confirm_not_through_ottocommand''') = 0
     OR strpos(v_cmd, 'v_person, v_via, v_bound, v_salt)') = 0
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
     OR strpos(v_guard, 'NEW.confirms_command_id, NEW.plan_salt)') = 0 OR strpos(v_guard, 'OLD.confirms_command_id, OLD.plan_salt)') = 0 THEN
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
     OR strpos(v_lift, 'AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings s') = 0
     OR strpos(v_door, 'v_status := 403; v_code := ''production_live'';') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the dispatcher, the receipt, whoami, the run''s end or the passcode door is not patched for §9-§12';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_owner_settings_guard_trg' AND tgrelid = 'public.ottoq_owner_settings'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_owner_settings_save_trg' AND tgrelid = 'public.ottoq_owner_settings'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_owner_saved_settings_guard_trg')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_sim_runs_carry_saved_owner_settings')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_sim_runs_carry_saved_owner_settings_on_start') THEN
    RAISE EXCEPTION '0721 V1 FAILED: a §9/§10 trigger is missing';
  END IF;
  --: §10 (the review, round 1): the five writers name themselves and nothing else does; the guards refuse every other
  --: write first; TRUNCATE is refused on both tables
  SELECT string_agg(x.f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_owner_command(public.ottoq_agent_principals,text,jsonb,text)', 'owner_command'),
      ('ottoq.ottoq_owner_orders_tick(uuid,timestamp with time zone)', 'tick'),
      ('public.ottoq_tg_lift_owner_settings_on_terminal()', 'run_end'),
      ('public.ottoq_owner_saved_carry(uuid)', 'carry'),
      ('public.ottoq_owner_settings_yield_to_production(uuid)', 'production_start')) x(f, w)
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(x.f)
                        AND ('ottoq.owner_settings_writer=' || x.w) = ANY (p.proconfig));
  IF v_bad IS NOT NULL
     OR (SELECT count(*) FROM pg_proc p CROSS JOIN LATERAL unnest(p.proconfig) c(setting)
          WHERE c.setting LIKE 'ottoq.owner_settings_writer=%') <> 5
     OR strpos(v_sg, 'IF v_writer NOT IN (''owner_command'', ''tick'', ''run_end'', ''carry'', ''production_start'') THEN') = 0
     OR strpos(v_svg, 'IF COALESCE(current_setting(''ottoq.owner_settings_writer'', true), '''') <> ''owner_command'' THEN') = 0
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_owner_settings_no_truncate_trg'
                       AND tgrelid = 'public.ottoq_owner_settings'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_owner_saved_settings_no_truncate_trg'
                       AND tgrelid = 'public.ottoq_owner_saved_settings'::regclass) THEN
    RAISE EXCEPTION '0721 V1 FAILED: the owner tables are not written by their named writers only (%)', COALESCE(v_bad, 'a guard or a TRUNCATE trigger');
  END IF;
  --: the review, round 2: a command id only to its maker in my_settings, my_fleet and my_vehicle; a saved row put back
  --: only by a person's undo of the command that ended it; a one-time order never takes an every-return order's place
  --: where that order covers it; a production run takes over its depot as it becomes the running run
  IF strpos(v_call, 'public.ottoq_owner_read_shown(v_agent, public.ottoq_owner_read(v_agent, ''my_fleet'', v_args))') = 0
     OR strpos(v_call, 'public.ottoq_owner_read_shown(v_agent, public.ottoq_owner_read(v_agent, ''my_vehicle'', v_args))') = 0
     OR strpos(v_sread, 'p_read := public.ottoq_owner_mask_command_ids(p_read, p_agent.principal_id, v_person);') = 0
     OR strpos(v_fol, 'AND s.ended_by_command_id = OLD.closed_by_command_id') = 0
     OR strpos(v_cmd, 'v_grp := ''already_every_return'';') = 0
     OR strpos(v_cmd, '''change'', v_grp NOT IN (''already_ordered'', ''already_every_return'')') = 0
     OR strpos(v_cmd, 'e ->> ''before'' LIKE ''every_return%''') = 0
     OR strpos(v_start, 'IF NEW.run_by = ''production_live'' AND NEW.status = ''running'' THEN' || chr(10)
                        || '    PERFORM public.ottoq_owner_settings_yield_to_production(NEW.sim_run_id);') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: a fix of the review, round 2 is not in its body';
  END IF;
  --: §15: the cockpit boards leave out production and a person's words
  IF strpos(v_board, 'AND NOT (c.sim_run_id IS NULL AND c.acting_person IS NOT NULL)') = 0
     OR strpos(v_board, 'AND v_run ->> ''run_by'' IS DISTINCT FROM ''production_live''') = 0
     OR strpos(v_dbrd, 'AND NOT (c.sim_run_id IS NULL AND c.acting_person IS NOT NULL)') = 0
     OR strpos(v_dbrd, 'AND v_run ->> ''run_by'' IS DISTINCT FROM ''production_live''') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: a cockpit board is not patched for §15';
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
     OR strpos(v_gate, '''run_kind'', ''none'', ''person'', v_person, ''saved'', true, ''saved_only'', true') = 0
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.ottoq_owner_commands'::regclass
                       AND conname = 'ottoq_owner_commands_saved_check')
     OR strpos((SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_owner_commands'::regclass
                   AND c.conname = 'ottoq_owner_commands_mode_outcome_check'), '''saved''::text') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: the owner door does not save to the cars with no run live (§14)';
  END IF;
  --: §17 (the review, round 3): the owners' run everywhere an owner path reads one, and in the engine's unpinned read
  IF strpos(v_runid, 'ORDER BY (r.status = ''running'') DESC, (r.run_by = ''production_live'') DESC, r.started_at DESC NULLS LAST') = 0
     OR strpos(v_cmd, 'v_run := public.ottoq_owner_live_run(p_agent.depot_id);') = 0
     OR strpos(v_cmd, 'ottoq_agent_live_run') > 0
     OR strpos(v_who, 'v_run := public.ottoq_owner_live_run(p_agent.depot_id);') = 0 OR strpos(v_who, 'ottoq_agent_live_run') > 0
     OR strpos(v_read, 'v_run      jsonb := public.ottoq_owner_live_run(p_agent.depot_id);') = 0 OR strpos(v_read, 'ottoq_agent_live_run') > 0
     OR strpos(v_board, 'v_run := public.ottoq_owner_live_run(p_depot_id);') = 0 OR strpos(v_board, 'ottoq_agent_live_run') > 0
     OR strpos(v_dbrd, 'v_run := public.ottoq_owner_live_run(p_depot_id);') = 0 OR strpos(v_dbrd, 'ottoq_agent_live_run') > 0
     OR strpos(v_lim, 'ELSE o.sim_run_id = public.ottoq_owner_run_id(o.depot_id) END') = 0
     OR strpos(v_lim, 'r.status IN (''running'', ''paused'')') > 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: an owner path or the engine''s unpinned limit read does not use the owners'' run (§17)';
  END IF;
  --: §17: every re-stamp pinned to its run; the takeover lifts every other live run's per-run settings, carries, and
  --: re-stamps every car; the run's end re-stamps unreconciled cars too
  IF strpos(v_pin, 'PERFORM set_config(''ottoq.sim_run_id'', p_run::text, true);') = 0
     OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public.ottoq_owner_target_on_run(uuid,uuid,timestamp with time zone)'::regprocedure
                       AND 'ottoq.sim_run_id=none' = ANY (p.proconfig))
     OR strpos(v_tick, 'v_tgt := public.ottoq_owner_target_on_run(r.vehicle_id, p_sim_run_id, p_clock);') = 0
     OR strpos(v_tick, 'ottoq_effective_target_soc_at') > 0
     OR strpos(v_yield, 'AND s.status = ''active'' AND s.saved_id IS NULL') = 0
     OR strpos(v_yield, 'run_by IS DISTINCT FROM ''production_live'' AND o.status') > 0
     OR strpos(v_yield, 'r.status IS DISTINCT FROM ''running''') = 0
     OR strpos(v_start, 'PERFORM public.ottoq_owner_restamp(NEW.depot_id, NEW.sim_run_id, NULL);') = 0
     OR strpos(v_lift, 'PERFORM public.ottoq_owner_restamp(NEW.depot_id, public.ottoq_owner_run_id(NEW.depot_id),') = 0
     OR strpos(v_lift, 'AND (s.status = ''active'' OR (s.kind = ''charge_limit'' AND s.pending_reconcile))) THEN') = 0
     OR strpos(v_lift, 'ottoq_effective_target_soc_at') > 0
     OR strpos(v_sg, 'OR (v_writer = ''production_start'' AND OLD.saved_id IS NULL') = 0
     OR strpos(v_sg, 'AND p.run_by = ''production_live'' AND p.status = ''running''') = 0 THEN
    RAISE EXCEPTION '0721 V1 FAILED: a re-stamp is not pinned, or the takeover or the run''s end is not the §17 one';
  END IF;
  --: §17: a person's change to what is saved holds on every live run; the carry brings back what only a takeover took off;
  --: an undo acts on its own run; the plan hash is salted and binds only by the hash
  IF strpos(v_cmd, 'PERFORM public.ottoq_owner_saved_propagate(v_cmd.command_id);') = 0
     OR strpos(v_prop, 'SET status = ''withdrawn''') = 0 OR strpos(v_prop, 'public.ottoq_owner_saved_carry(r.sim_run_id)') = 0
     OR strpos(v_sg, 'IF NOT COALESCE(v_ok, false) AND NEW.status = ''withdrawn'' AND OLD.saved_id IS NOT NULL THEN') = 0
     OR strpos(v_sg, 'IF v_ok AND (c.sim_run_id IS DISTINCT FROM NEW.sim_run_id OR v_writer = ''carry'') THEN') = 0
     OR strpos(v_carry, 'WITH RECURSIVE ch AS (') = 0
     OR strpos(v_cmd, 'WHERE o.command_id = v_target.command_id AND o.sim_run_id = v_run_id), ''[]''::jsonb);') = 0
     OR strpos(v_cmd, 'FOR v_set IN SELECT * FROM public.ottoq_owner_settings o WHERE o.command_id = v_target.command_id AND o.sim_run_id = v_run_id') = 0
     OR strpos(v_cmd, 'v_salt := replace(gen_random_uuid()::text, ''-'', '''');') = 0
     OR strpos(v_cmd, 'v_hash := md5(v_salt || v_plan);') = 0
     OR strpos(v_cmd, 'expect_plan_hash "%s"') > 0 OR strpos(v_cmd, 'confirms_command_id "%s"') > 0
     OR strpos(v_cmd, '''plan_changed'', ''plan_hash''') > 0
     OR strpos(v_bind, 'IF p_expect IS NULL THEN') = 0
     OR strpos(v_bind, 'AND p.plan_salt IS NOT NULL AND md5(p.plan_salt || p_plan) = p.plan_hash') = 0
     OR strpos(v_reply, '''plan_hash'', p_c.plan_hash') > 0
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.ottoq_owner_commands'::regclass
                       AND conname = 'ottoq_owner_commands_plan_salt_check') THEN
    RAISE EXCEPTION '0721 V1 FAILED: the propagation, the carry, the undo or the salted plan hash is not the §17 one';
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
                      'public.ottoq_owner_settings_yield_to_production(uuid)',
                      'public.ottoq_owner_mask_command_ids(jsonb,uuid,text)',
                      --: §17 (the review, round 3)
                      'public.ottoq_owner_run_id(uuid)',
                      'public.ottoq_owner_live_run(uuid)',
                      'public.ottoq_owner_target_on_run(uuid,uuid,timestamp with time zone)',
                      'public.ottoq_owner_restamp(uuid,uuid,uuid[])',
                      'public.ottoq_owner_saved_propagate(uuid)',
                      'public.ottoq_owner_read_shown(public.ottoq_agent_principals,jsonb)',
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
-- one-running-run index never meets it; with nothing running there (P3), the newest paused production run is the owners'
-- run, §17), a paused demo run started after it (which the owners' run must NOT become), a probe sign-in (client,
-- account, two connections, their access tokens), a passcode session, an issued key, their commands and settings, the
-- ledger rows -- is in a block that raises at its end and is rolled back. Only the answers, held in variables, survive it.
-- It probes the binding (rule 9): a lowering sent in one call is recorded as a preview and applies nothing; its confirm,
-- sent by the OTHER connection, applies nothing; sent by the agent that made it, applies once and is recorded as via
-- 'confirm' naming the preview; sent again, applies nothing; a raise is one call; the undo of that raise (which puts the
-- lower limit back) is gated the same way and applies only as its own preview's confirm. A preview older than 15 minutes
-- cannot be made inside one transaction (now() does not move), so expiry is proved by the test suite, not here.
-- (The review, round 3) It also probes the salted plan hash (a preview's receipt names its hash only inside its confirm
-- object; a confirm by command id alone binds nothing) and the owners' run (a paused demo run started after production
-- does not take production's commands or whoami). It does not start or resume a production run, so the takeover (which
-- re-stamps every car at the depot) is proved by the test suite, not here: on live it would hold a row lock on every car
-- for the length of the probe.
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
  --: §17 (the review, round 3)
  r_idonly    jsonb;
  v_t_idonly  numeric;
  r_who2      jsonb;
  v_demo_run  uuid := gen_random_uuid();
  v_hash      text;
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
    v_hash := r_lower #>> '{data,confirm,args,expect_plan_hash}';
    -- 1a. (§17) the same preview confirmed by its command id alone, through the confirm door: binds nothing, applies
    --     nothing, and is recorded as a new preview
    r_idonly := public.ottoq_agent_call(v_th, r_lower #>> '{data,confirm,tool}', (r_lower #> '{data,confirm,args}') - 'expect_plan_hash',
                                        'confirm', '{}'::jsonb);
    v_t_idonly := public.ottoq_effective_target_soc_at(v_car, now());
    -- 1b. that preview's confirm, sent by another agent signed in to the same account: not its preview, so nothing applies
    r_other := public.ottoq_agent_call(public.ottoq_oauth_sha256(v_oauth2), r_lower #>> '{data,confirm,tool}',
                                       r_lower #> '{data,confirm,args}', 'confirm', '{}'::jsonb);
    v_t_other := public.ottoq_effective_target_soc_at(v_car, now());
    -- 2. that preview's confirm object, sent back through the confirm door: applied once, bound to the preview
    r_confirm := public.ottoq_agent_call(v_th, r_lower #>> '{data,confirm,tool}', r_lower #> '{data,confirm,args}', 'confirm',
                                         '{}'::jsonb);
    v_t_confirm := public.ottoq_effective_target_soc_at(v_car, now());
    v_cmd := (r_confirm #>> '{data,command,command_id}')::uuid;
    -- 2a. (§17) a paused demo run started after the production run: the owners' run is still production (whoami names it,
    --     and the raise below goes to it). It stays paused to the end of the probe: ending a demo run ends every passcode
    --     session (0607), the probe's own included
    EXECUTE format('INSERT INTO public.ottoq_sim_runs (sim_run_id, status, started_at, run_by, %1$s) '
                   'SELECT $1, ''paused'', clock_timestamp(), ''operator_demo'', %1$s FROM public.ottoq_sim_runs WHERE sim_run_id = $2',
                   v_cols) USING v_demo_run, v_tpl;
    r_who2 := public.ottoq_agent_call(v_th, 'whoami', '{}'::jsonb, 'mcp', '{}'::jsonb);
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
              r_lower #>> '{data,confirm,args,expect_plan_hash}', c_email, 'confirm', v_prev);
      v_twice := 'inserted';
    EXCEPTION WHEN unique_violation THEN v_twice := 'refused';
    END;
    BEGIN
      INSERT INTO public.ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool, mode,
                                               outcome, summary, plan_hash, acting_person, via, confirms_command_id)
      VALUES (v_pid, '0721 probe', v_fleet, c_twin, v_run, 'set_charge_limit', 'apply', 'applied', '0721 bogus-confirm probe',
              r_lower #>> '{data,confirm,args,expect_plan_hash}', c_email, 'confirm', v_cmd);
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
  -- §17: the preview's hash only in its confirm object, salted; a command id alone binds nothing
  IF v_hash IS NULL OR v_hash !~ '^[0-9a-f]{32}$' OR r_lower #> '{data,command}' ? 'plan_hash'
     OR strpos(r_lower #>> '{data,summary}', v_hash) > 0 OR strpos(r_lower #>> '{data,summary}', v_prev::text) > 0 THEN
    RAISE EXCEPTION '0721 V3 FAILED: a preview''s receipt carries its plan hash or id outside its confirm object: %', r_lower;
  END IF;
  IF (r_idonly ->> 'http_status')::int <> 422 OR r_idonly #>> '{error,code}' IS DISTINCT FROM 'confirm_required'
     OR r_idonly #>> '{data,refusal,reason}' IS DISTINCT FROM 'not_named' OR r_idonly #>> '{data,outcome}' IS DISTINCT FROM 'previewed'
     OR v_t_idonly IS DISTINCT FROM (v_ctr ->> 'max_charge_pct')::numeric THEN
    RAISE EXCEPTION '0721 V3 FAILED: a confirm by command id alone was not refused (target %): %', v_t_idonly, r_idonly;
  END IF;
  IF r_who2 #>> '{data,owner,live_production_run}' IS DISTINCT FROM v_run::text OR r_who2 #> '{data,owner}' ->> 'live_demo_run' IS NOT NULL
     OR (r_mid #>> '{data,command,sim_run_id}') IS DISTINCT FROM v_run::text THEN
    RAISE EXCEPTION '0721 V3 FAILED: a paused demo run started after production took the owners'' run: % / %', r_who2 -> 'data' -> 'owner', r_mid;
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
     OR EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id IN (v_run2, v_demo_run))
     OR EXISTS (SELECT 1 FROM public.ottoq_owner_saved_settings WHERE acting_person = c_email)
     OR EXISTS (SELECT 1 FROM public.ottoq_model_call_ledger WHERE chain_id = 'v0721-probe') THEN
    RAISE EXCEPTION '0721 V3 FAILED: the probe left rows behind';
  END IF;
  RAISE NOTICE '0721 V3 PASSED: production at the twin depot takes a signed-in person (% on %), refuses a passcode (and opens none) and a key, lowers a limit (or undoes a raise) only as the one confirm of a preview the same principal recorded, by its salted plan hash and never by its id alone, keeps the owners'' run on production over a newer paused demo, saves the limit and carries it onto the next run, refuses a setting no command made, and ledgers a model call', c_email, v_run;
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
  'saved table only), carried onto the next demo or production run. The review, round 2: a command id only to the agent '
  'that made it or its person; a saved row back only by a person''s undo of the command that ended it; a one-time order '
  'an every-return order already covers changes nothing; a production run lifts every other live run''s owner settings '
  'at its depot as it starts (its trigger''s WHEN no arm meets). The review, round 3: one owners'' run per depot (the '
  'running run, else the newest paused production run, else the newest paused demo run) for every owner path and for '
  'the engine''s unpinned owner-limit read; every re-stamp pinned to its run; a production run that becomes the running '
  'run lifts every other live run''s per-run settings and re-stamps every car; a person''s change to what is saved holds '
  'on every live run; a plan hash salted and binding only by itself. The two engine readers touched (the unpinned branch '
  'of ottoq_owner_charge_limit, the tick''s target line) are reached only with owner rows, which no arm has: FALSE/FALSE.',
  now());

COMMIT;
