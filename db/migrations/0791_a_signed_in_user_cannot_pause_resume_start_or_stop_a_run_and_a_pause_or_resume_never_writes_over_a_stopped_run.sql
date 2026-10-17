-- migration-version: PENDING
-- migration-name:    a_signed_in_user_cannot_pause_resume_start_or_stop_a_run_and_a_pause_or_resume_never_writes_over_a_stopped_run
--
-- 0791  **A signed-in user can no longer pause, resume, start, reset or fast-forward a run through /rest/v1/rpc, and a
--        pause or resume that waited behind a stop no longer writes over the stopped run.** Seventeen run-control
--        routines lose EXECUTE for PUBLIC, anon and authenticated and keep it for postgres and service_role: five of them
--        were SECURITY DEFINER doors that any account holder could use on any run, a production session included, and
--        the other twelve run as the caller and could not do harm today (FINDINGS G493; db/checks/0438 (4) lists the five
--        as "OPEN: no file names a signed-in reader"; db/checks/0448 §2 noted production start and stop). And
--        ottoq_pause_run and ottoq_resume_run now carry the status they read into their UPDATE and answer from the row
--        count, as the twin app's own pause and resume do (G492, recorded by 0790 §5).
--        Measured read-only on the live catalog, the 30 live edge functions, the API logs and every repository under
--        /home/user, on 2026-10-15 from 13:14:57 UTC (8:14 AM CT, the first query's own now()) to 13:41 UTC (8:41 AM CT),
--        and re-read on 2026-10-17, after 0724-0734 were applied that morning, from 14:04:05 UTC (9:04 AM CT) to 14:12:25
--        UTC (9:12 AM CT); G492's premises from 14:25:16 UTC (9:25 AM CT) to 14:46:41 UTC (9:46 AM CT), each query's own
--        clock. Every ACL, md5, caller and census row below read the same on both days. The P0/P1 dry run is in §5.
--
-- ══ §0 STATUS: WRITTEN AND EXECUTED ON A STUB; NOT APPLIED ══════════════════════════════════════════════════════════
--
--   tests/test_run_control_grants_sql.py runs this file on tests/fixtures/run_control_grants_stub.sql, which carries the
--   seventeen live definitions byte for byte (md5-pinned) and their live ACLs, with ottoq_sim_runs (and its live
--   one-running-run-per-depot index), ottoq_scenarios, their live grants and row-security policies, and the callees
--   production start and stop reach. Before this file a signed-in caller pauses a running run and resumes it, which it
--   cannot do to the table directly; a signed-in production start or stop is refused one call deeper, at a callee only
--   service_role may run; and, in two real sessions, a pause or resume that waited behind a stop writes over the
--   stopped run. After it, all seventeen refuse authenticated and anon with 42501 naming the routine, service_role still
--   pauses, resumes, starts and stops, the same waits update nothing and answer that the run is no longer running or
--   paused, and the restore statements in §4 put every ACL and both definitions back.
--   Applying it is a grant change, which FINDINGS leaves to Chase with the rest of the 0701 family (G417's rule, as G442
--   records it), and G492's patch goes with it, in the same transaction. Its order against 0701 and 0790 (both pending)
--   does not matter: 0701 takes EXECUTE on three other run-control functions (§2) and this file's census accepts them in
--   either state; 0790 pins the stop door's definition and reads the metronome's body, neither of which this file
--   changes (of the metronome it takes only the browser grants), and this file pins nothing 0790 changes.
--   Once it is applied, db/checks/0438 (4) reads "GONE" for the five SECURITY DEFINER doors (its own instruction: update
--   the list); do that in the sitting that writes this file's APPLIED footer, not before, since until then the list is
--   true of live.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) THE FIVE DOORS (bodies read on both days; each is SECURITY DEFINER, owner postgres, search_path twin, ottoq,
--       public, extensions, and EXECUTE-able by authenticated; anon holds no grant and there is no PUBLIC entry).
--       ottoq_pause_run(uuid, text), md5 1e3ec33aca6f4f3b008a0d83bff08c51, ACL {postgres=X/postgres,service_role=X/
--         postgres,authenticated=X/postgres}: takes ANY run whose status is 'running' to 'paused', clears
--         next_tick_due_at and records twin.sim_run_paused. It reads no run_by, so a production_live session is paused
--         like a demo. Every world step skips a run that is not running (twin.ottoq_world_advance() and
--         ottoq_sim_advance_tick_world both read status = 'running'), so a pause stops the session's tick until someone
--         resumes it.
--       ottoq_resume_run(uuid), md5 b693dc33284db3914381f89bd7f21724, the same ACL: takes any paused run back to
--         'running' and re-anchors its clock, whoever paused it. Once 0721 (pending) is applied, either door on a demo or
--         production run also fires 0721 §9's ottoq_sim_runs_carry_saved_owner_settings_on_start, and on a production
--         run its takeover (§16 (d)): every owner setting active on another run at the depot is lifted.
--       ottoq_sim_run_scenario(text, bigint, text, timestamptz), md5 77452e4a4d02700ddea8a450f468daee, ACL
--         {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}: stops and resets every running or paused
--         run at the scenario's depot through ottoq_sim_stop_and_reset (no run_by predicate, so a production session at the
--         twin depot too) and starts a new run under a run_by the caller names.
--       ottoq_run_policy_to_end(uuid, integer), md5 1b40f798b8f5f8326bff260d0002cc09, the second ACL: advances any running
--         run by up to p_max_ticks ticks (default 48) through ottoq_sim_advance_tick, an engine function only postgres and
--         service_role may run, which it calls as its owner, then captures a decision snapshot.
--       ottoq_benchmark_reset(uuid, numeric, numeric), md5 17986725fa7566b0c6670c58af5f3d8f, the first ACL: refuses a
--         depot whose slug is not benchmark%; at the benchmark depot it aborts every running run and resets its stalls,
--         chargers, charge sessions and vehicles.
--       Sign-up is open (FINDINGS G428), so "authenticated" is anyone with an email address. At 14:07 UTC on 2026-10-17 no
--       run was running or paused; ottoq_sim_runs holds 9 production_live sessions (8 at the twin depot), all completed.
--   (b) THE CENSUS. A run-control routine is (i) one whose own comment-stripped body inserts into ottoq_sim_runs, deletes
--       from it, or sets a row's status; (ii) a SECURITY DEFINER routine that reaches one of (i) through other routines,
--       by name, within eight calls; or (iii) one of the families the brief names that changes runs without (i): the
--       retention purge, which deletes ended runs' rows and stamps the run's purged_at. In public, a browser role may
--       execute these (prokind f = function, p = procedure; "PUBLIC" = {=X/postgres,postgres=X/postgres,anon=X/postgres,
--       authenticated=X/postgres,service_role=X/postgres}):
--         routine                                                      kind  security  browser EXECUTE   rule  0791
--         ottoq_pause_run(uuid, text)                                    f   DEFINER   authenticated     (i)   revoke
--         ottoq_resume_run(uuid)                                         f   DEFINER   authenticated     (i)   revoke
--         ottoq_sim_run_scenario(text, bigint, text, timestamptz)        f   DEFINER   authenticated     (i)   revoke
--         ottoq_benchmark_reset(uuid, numeric, numeric)                  f   DEFINER   authenticated     (i)   revoke
--         ottoq_run_policy_to_end(uuid, integer)                         f   DEFINER   authenticated     (ii)  revoke
--         ottoq_production_start(uuid)                                   f   INVOKER   PUBLIC            (i)   revoke
--         ottoq_production_stop(text)                                    f   INVOKER   PUBLIC            (i)   revoke
--         ottoq_cert_arm_start(bigint, text, uuid, integer)              f   INVOKER   PUBLIC            (i)   revoke
--         ottoq_cert_arm_finish(uuid)                                    f   INVOKER   PUBLIC            (i)   revoke
--         ottoq_cert_arm(bigint, text, uuid, integer, timestamptz, int)  p   INVOKER   PUBLIC            (i)   revoke
--         ottoq_cert_arm_wave(bigint, text, uuid, integer, integer)      p   INVOKER   PUBLIC            (i)   revoke
--         ottoq_fr1_cert_arm(uuid, bigint, uuid, int, timestamptz, bool) p   INVOKER   PUBLIC            (i)   revoke
--         ottoq_safety_cert_arm(uuid, bigint, uuid, int, timestamptz, n) p   INVOKER   PUBLIC            (i)   revoke
--         ottoq_demo_metronome(integer)                                  p   INVOKER   PUBLIC            (i)   revoke
--         ottoq_retention_purge_runs(integer, integer, interval, bool)   p   INVOKER   PUBLIC            (iii) revoke
--         ottoq_retention_purge_worker(integer, integer, interval, text[]) p INVOKER   PUBLIC            (iii) revoke
--         ottoq_retention_purge_worker(integer, integer, interval)       p   INVOKER   PUBLIC            (iii) revoke
--         ottoq_purge_prior_runs(uuid)                                   f   DEFINER   authenticated     (i)   0701's
--         ottoq_start_busy_run(numeric, integer, bigint)                 f   DEFINER   authenticated     (ii)  0701's
--         ottoq_start_busy_run_once(text, numeric, integer, bigint)      f   DEFINER   authenticated     (ii)  0701's
--       The rest of the brief's list is already postgres and service_role only: ottoq_operator_start_run,
--       ottoq_start_demo_run, ottoq_sim_stop_and_reset, ottoq_sim_mark_stopped, ottoq_set_playback, ottoq_set_demo_speed,
--       ottoq_run_governor_auto_stop, ottoq_sim_release_depot, ottoq_world_yield_to_start, ottoq_purge_orphan_rows,
--       ottoq_sim_advance_tick and ottoq_sim_advance_tick_world, ottoq_cert_battery_step, ottoq_agent_chain_claim,
--       ottoq_throughput_sweep_arm, ottoq_dial_pair, ottoq_tick_invariance_arm and _reset_fleet, and every twin.* and
--       ottoq.* writer (twin.ottoq_sim_start_run, twin.ottoq_sim_end_run, twin.ottoq_sim_advance_clock; no browser role
--       holds USAGE on twin or ottoq).
--   (c) CALLERS, MEASURED. A routine with a signed-in browser caller would not be revoked; none of the seventeen has one.
--       - Apps: no code in any repository under /home/user calls any of them (ottoyarddepot-sim, ottoyard-OTTO-Q,
--         OTTOYARD-SITE, ottoyard-field-ops, OTTOYARD, OTTO-Defense, Otto-charge-arm, ottoq-intelligence, otto-q-core's
--         edge-functions and scripts; docs and tests aside). The twin app pauses and resumes through otto-twin-control,
--         which updates the row itself with the service role.
--       - Edge functions: all 30 live functions read with get_edge_function (versions as listed on both days, unchanged);
--         every one that touches the database builds its client from SUPABASE_SERVICE_ROLE_KEY. Two name a target:
--         ottoq-benchmark-run v9 calls ottoq_benchmark_reset as service_role, and otto-twin-control v30 names
--         ottoq_sim_run_scenario only in a comment (it starts through ottoq_operator_start_run). The repository copy of
--         otto-twin-control in ottoyarddepot-sim calls ottoq_sim_run_scenario directly, also as service_role.
--       - API logs: from 2026-10-09 20:55:34 UTC (the oldest edge_logs row held on 2026-10-15) to 2026-10-17 14:03:00 UTC,
--         no /rest/v1/rpc request names any of the seventeen, or 0701's three, from any role.
--       - pg_stat_statements (since 2026-07-30 02:59 UTC, 159 deallocations, so silence there is not proof): only postgres
--         and service_role (30 PostgREST calls of ottoq_sim_run_scenario) ever ran one. authenticated's statements are
--         0700's sign-in doors, ottoq_nl_status_brief, ottoq_twin_snapshot and table reads.
--       - SQL: every caller, comment-stripped, is SECURITY DEFINER and runs as postgres (ottoq_operator_start_run,
--         ottoq_start_demo_run, ottoq_dial_pair, ottoq_throughput_sweep_arm and ottoq_cert_battery_step), or is itself a
--         target (the cert-arm routines call ottoq_benchmark_reset, and run as postgres). ottoq_kpi_five and
--         ottoq_start_busy_run name a target only inside a string. No view, policy, column default or trigger depends on
--         one. All 24 cron jobs run as postgres; jobs 11 and 625 (the retention purge), 12 (the metronome) and 13 (the
--         cert battery, inactive) call targets. otto-q-workspace's tier4 scripts call ottoq_sim_run_scenario and
--         ottoq_run_policy_to_end through the Management API, which runs as postgres.
--   (d) THE TWELVE THAT RUN AS THE CALLER, AND 0448 RE-READ. They need the caller's own table privileges, and neither
--       browser role holds INSERT, UPDATE or DELETE on ottoq_sim_runs (anon holds nothing on it). So 0448's conclusion
--       stands, with one premise corrected: it reads that neither role holds SELECT on ottoq_sim_runs or ottoq_scenarios,
--       and authenticated does (authenticated=rxtm/postgres on both, read 2026-10-15 13:20 UTC, under policies every
--       signed-in caller passes). A signed-in ottoq_production_start therefore reads both and stops at
--       ottoq_world_yield_to_start (since 0719), and ottoq_production_stop at ottoq_sim_release_depot; only postgres and
--       service_role may run either callee, and the stub reproduces both refusals. The eight procedures have no browser
--       door at all: PostgREST calls functions, not procedures ("Stored Procedures are not supported", PostgREST docs,
--       main branch, docs/references/api/functions.rst, https://github.com/postgrest/postgrest/blob/main/docs/references/
--       api/functions.rst, read 2026-10-15). They are revoked with the rest so that no browser role holds EXECUTE on a
--       run-control routine; the cost is nothing, since cron and every caller run them as postgres. One of them,
--       ottoq_retention_purge_worker(integer, integer, interval), cannot be called by name at all: every call that fits
--       it also fits the text[] overload, whose fourth argument has a default, and PostgreSQL refuses the call as
--       ambiguous (42725) before it checks a privilege; cron job 11 calls the four-argument one (read 14:44:52 UTC).
--
--   (e) THE OVERWRITE (G492, recorded by 0790 §5). Both doors read the run with a plain SELECT * INTO v_run, answer a
--       no-op unless it reads 'running' (pause) or 'paused' (resume), then UPDATE ottoq_sim_runs SET status = 'paused'
--       (or 'running') WHERE sim_run_id = p_sim_run_id, with no status predicate, and answer 'paused' (or 'running')
--       from what they read. A stop holds the run's row from ottoq_sim_mark_stopped's UPDATE (with 0790, on a running
--       run, from the stop door's first statement) to its commit. A pause or resume that read the status before that
--       commit waits on the row, and PostgreSQL then re-checks only its WHERE on the row the stop left (READ COMMITTED),
--       so it writes over 'completed'. On the stub, with both live bodies and two real sessions (one holds the run's row
--       FOR NO KEY UPDATE and completes it as mark_stopped does; the other pauses or resumes as service_role and waits):
--         - a pause behind a stop of a running run leaves the run 'paused' with ended_at set and failure_reason
--           'operator_stop', and records twin.sim_run_paused;
--         - a resume behind a stop of a paused run leaves it 'running' with the same stop stamps, a stopped run every
--           world step would tick again, and records twin.sim_run_resumed;
--         - when the stop's transaction also starts another run at the depot (the operator start does), live's
--           ottoq_one_running_run_per_depot (UNIQUE (depot_id) WHERE status = 'running', read 14:34:53 UTC) refuses the
--           resume with 23505;
--         - behind the demo start's abort-then-purge (the run marked 'aborted', then deleted) the UPDATE takes nothing
--           and the door goes on to record its event for a run that is gone. Live's ottoq_record_event writes the run's
--           id into ottoq_events, whose foreign key to the run (fk_ottoq_events_sim_run, NOT VALID, which still checks
--           every new row; read 14:38:25 UTC) refuses it with 23503, so the door fails instead of answering. (G492's row
--           reads that the resume answers 'running' for the gone run: measured on a stand-in without that key. The stub
--           here carries it.)
--       Once 0721 (pending) is applied, an overwrite would also fire its trigger
--       ottoq_sim_runs_carry_saved_owner_settings_on_start (AFTER UPDATE OF status, when the status changes to 'running'
--       or 'paused' on an operator_demo or production_live run) on the stopped run. Neither door has a caller in the
--       database (2,075 routines outside pg_catalog and information_schema, comment-stripped and raw), in cron.job or in
--       any repository, and nothing depends on either (read 14:28:05 UTC, 9:28 AM CT); no run was running or paused at
--       14:34:53 UTC. The twin app's own pause and resume (edge-functions/otto-twin-control, pauseRun and resumeRun)
--       PATCH the row with .eq("status", "running") and .eq("status", "paused") and answer 409 when no row comes back,
--       and ottoq_sim_mark_stopped carries its own predicate (status IN ('running','paused')) and answers from ROW_COUNT.
--       This file gives the two doors the same.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   On the seventeen: REVOKE EXECUTE FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO service_role (explicit, as in
--   0720, so service_role keeps the right however it held it). postgres keeps its owner's right.
--   On two of them, ottoq_pause_run and ottoq_resume_run (G492), after a snapshot of both definitions, one anchored patch
--   each, its anchor asserted to occur exactly once in the definition P1 pinned by md5:
--     - pause: the UPDATE gains AND status = 'running', and when it takes nothing (FOUND false) the door reads the row
--       again and returns {"ok": false, "error": "run not found"} if it is gone, or else the answer it already gives a
--       run that is not running: {"ok": true, "noop": true, "status": <the status now>, "note": "run was not running"};
--     - resume: AND status = 'paused', and the same answer with "run was not paused".
--     Either returns before its event, so a door that wrote nothing records nothing, and neither answers 'paused' or
--     'running' for a write it did not make. Nothing else in either moves: V3 undoes both patches and compares the whole
--     definition, header included, with the snapshot, and checks the other fifteen byte for byte; V5 reads both bodies
--     comment-stripped and fails if a predicate, or the answer from the row count, is missing. CREATE OR REPLACE keeps
--     the grants, the owner and SECURITY DEFINER.
--   NOT CHANGED:
--     - 0701's three (ottoq_purge_prior_runs, ottoq_start_busy_run, ottoq_start_busy_run_once). 0701 (pending, waiting on
--       Chase's go-ahead) takes them; this file neither duplicates that nor depends on it, and V4 names them if they are
--       still open.
--     - otto-twin-control's own door. It is deployed with verify_jwt off and its mutation gate commented out ("DEMO MODE
--       — open on a private link (Chase's call)"), and it writes with the service role, so anyone holding its URL can
--       still pause, resume, stop or start a run, production included (FINDINGS G394). This file closes the RPC door, not
--       that one.
--     - SECURITY INVOKER engine and research paths a browser role may still execute: ottoq_determinism_pair and
--       _replay, ottoq_cert_arm_step, ottoq_mpc_lookahead, ottoq_mpc_energy_lookahead, ottoq_cil_tick and
--       ottoq_t4_step_and_sample. Each reaches a run write only through a routine only service_role may run or one this
--       file closes, so a browser call stops at 42501. They belong with db/checks/0438's census.
--     - Routines named like run control that do not control a run: ottoq_demo_start_clock (computes a start clock and
--       writes nothing), ottoq_archive_run (writes an archive row), ottoq_agentic_arm (writes a run's dials),
--       ottoq_close_run_needs, and the reads (ottoq_active_sim_run, ottoq_depot_running_run, ottoq_blackbox_latest_run,
--       ottoq_production_write_refusal, ottoq_assert_scenario_start_windows, the run digests and lists).
--     - db/checks/0438's allowlist, until this file is applied (§0).
--     - The pause's other answers: its frozen_at_sim_clock and tick_count, and its event's tick_count, still come from
--       the unlocked read, so a tick that commits between that read and the UPDATE (which waits for it and then pauses
--       the run) leaves them one tick behind the row. That writes nothing and is not G492.
--     - A stop that waits behind a pause or resume: mark_stopped's own predicate (running or paused) takes the run
--       either way.
--     - G491: a run the prior-run purge chose while paused and that is resumed before the purge deletes it is still
--       deleted while running. The purge holds nothing on the row when the resume writes it, so the resume's predicate
--       holds, and the purge's DELETE, which re-checks only sim_run_id, follows it.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ══════════════════════════════════════════════════════════════
--
--   The grants: no atom reads a grant. The engine runs these routines as postgres (cron 11, 12, 13 and 625; the SECURITY
--   DEFINER callers; the recert runner) or as service_role (otto-twin-control, ottoq-benchmark-run), and both keep
--   EXECUTE.
--   The patches: no certified harness calls either door. No routine outside the two, in any schema, names
--   ottoq_pause_run or ottoq_resume_run, comment-stripped or raw; no cron job does; nothing depends on them (read
--   2026-10-17 14:28:05 UTC, 9:28 AM CT, over 2,075 routines; P1 asserts it before anything is written). So the
--   determinism and dial pairs, the recert runner, the cert arms and the sweeps never reach them; their callers are
--   clients (the platform as service_role, the SQL editor as postgres). And in one session the patched doors behave as
--   before: their read and their UPDATE see the same row, so the predicate holds whenever the old door would have
--   written, and only another session's commit between the two makes it take nothing. FALSE/FALSE.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   One paste: run the lines between the two markers below in the SQL editor (as postgres). The GRANTs give back exactly
--   what this file takes: authenticated on the five SECURITY DEFINER doors; PUBLIC, anon and authenticated on the other
--   twelve. The last line puts back the two definitions this file patched, from ottoq_schema_snapshots WHERE label =
--   '0791_pre' AND object_kind = 'function' (2 rows); leave it out to re-open the grants and keep G492's fix. The same
--   GRANTs are kept, one per (routine, grantee), in the rows WHERE label = '0791_pre' AND object_kind = 'grant' (41 rows;
--   EXECUTE them in snapshot_id order to the same effect). Neither definition holds a secret, which matters because that
--   table is readable by every signed-in caller (G438). Rolling back the grants re-opens pause, resume,
--   start-a-scenario, run-to-end and benchmark reset to everyone who signs up; rolling back the definitions re-opens
--   G492.
/* 0791 RESTORE BEGIN
GRANT EXECUTE ON FUNCTION public.ottoq_pause_run(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_resume_run(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_sim_run_scenario(text, bigint, text, timestamp with time zone) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_benchmark_reset(uuid, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_run_policy_to_end(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_production_start(uuid) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_production_stop(text) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_cert_arm_start(bigint, text, uuid, integer) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_cert_arm_finish(uuid) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_cert_arm(bigint, text, uuid, integer, timestamp with time zone, integer) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_cert_arm_wave(bigint, text, uuid, integer, integer) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_fr1_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, boolean) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_safety_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, numeric) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_demo_metronome(integer) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_runs(integer, integer, interval, boolean) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_worker(integer, integer, interval, text[]) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_worker(integer, integer, interval) TO PUBLIC, anon, authenticated;
DO $restore$ DECLARE r record; BEGIN FOR r IN SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0791_pre' AND object_kind = 'function' ORDER BY snapshot_id LOOP EXECUTE r.definition; END LOOP; END $restore$;
0791 RESTORE END */
--
-- ══ §5 THE DRY RUN, READ-ONLY, AGAINST LIVE ══════════════════════════════════════════════════════════════════════
--
--   P0 and every P1 premise, as one SELECT on live (read-only), at 2026-10-17 14:50:30 UTC (9:50 AM CT, the query's own
--   clock_timestamp()), with the patches' anchors and replacements exactly as this file carries them:
--     P0  ottoq_certification_in_flight(true) = 0.
--     P1  no 0791 lineage row and no '0791_pre' snapshot; 17 of the 17 signatures, and the sixteen names have 17
--         routines; every owner, kind, security and ACL as read; pause 1e3ec33aca6f4f3b008a0d83bff08c51 and resume
--         b693dc33284db3914381f89bd7f21724; no browser-reachable SECURITY INVOKER caller; no dependent; every cron job
--         runs as postgres; the census reads 17 routines, the 14 this file names and 0701's three, and misses none; the
--         probe id is no run; both patched signatures exist; no routine (the catalogs and temporary schemas aside) and
--         no cron job names ottoq_pause_run or ottoq_resume_run.
--     The patches: each anchor occurs exactly once in its live definition, and the replaced texts' md5s are
--         28cba3966f9831f23705fb5c2341e691 (pause) and 3950a271cc07b6374a4fb2db70680e74 (resume), the two definitions
--         the stub carries after this file. No run was running or paused.
--   The grant premises alone read the same at 14:16:46 UTC (9:16 AM CT). P2, the snapshots, the patches, the grant
--   change and V1-V5 write, so they ran on the stub only (§0).

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0791 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── the seventeen as read on live (2026-10-15 and 2026-10-17): kind, security and ACL ──
CREATE TEMP TABLE p0791_targets (sig regprocedure PRIMARY KEY, kind "char" NOT NULL, definer boolean NOT NULL,
                                 acl text NOT NULL, census boolean NOT NULL) ON COMMIT DROP;
INSERT INTO p0791_targets
SELECT to_regprocedure(v.s), v.k::"char", v.d, v.a, v.c
  FROM (VALUES
    ('public.ottoq_pause_run(uuid, text)', 'f', true,
     '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}', true),
    ('public.ottoq_resume_run(uuid)', 'f', true,
     '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}', true),
    ('public.ottoq_sim_run_scenario(text, bigint, text, timestamp with time zone)', 'f', true,
     '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_benchmark_reset(uuid, numeric, numeric)', 'f', true,
     '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}', true),
    ('public.ottoq_run_policy_to_end(uuid, integer)', 'f', true,
     '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_production_start(uuid)', 'f', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_production_stop(text)', 'f', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_cert_arm_start(bigint, text, uuid, integer)', 'f', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_cert_arm_finish(uuid)', 'f', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_cert_arm(bigint, text, uuid, integer, timestamp with time zone, integer)', 'p', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_cert_arm_wave(bigint, text, uuid, integer, integer)', 'p', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_fr1_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, boolean)', 'p', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_safety_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, numeric)', 'p', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_demo_metronome(integer)', 'p', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true),
    ('public.ottoq_retention_purge_runs(integer, integer, interval, boolean)', 'p', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', false),
    ('public.ottoq_retention_purge_worker(integer, integer, interval, text[])', 'p', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', false),
    ('public.ottoq_retention_purge_worker(integer, integer, interval)', 'p', false,
     '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', false)
  ) AS v(s, k, d, a, c)
 WHERE to_regprocedure(v.s) IS NOT NULL;

-- 0701's three: 0701 (pending) closes them; the census accepts them while they are open and never requires them
CREATE TEMP TABLE p0791_0701 (sig regprocedure PRIMARY KEY) ON COMMIT DROP;
INSERT INTO p0791_0701
SELECT to_regprocedure(s)
  FROM unnest(ARRAY['public.ottoq_purge_prior_runs(uuid)', 'public.ottoq_start_busy_run(numeric, integer, bigint)',
                    'public.ottoq_start_busy_run_once(text, numeric, integer, bigint)']) AS s
 WHERE to_regprocedure(s) IS NOT NULL;

-- ── G492: the two patches, anchor and replacement; the anchors are byte for byte in the definitions P1 pins by md5 ──
CREATE TEMP TABLE p0791_patches (sig regprocedure PRIMARY KEY, anchor text NOT NULL, patched text NOT NULL) ON COMMIT DROP;
INSERT INTO p0791_patches
SELECT to_regprocedure(v.s), v.a, v.n
  FROM (VALUES
    ('public.ottoq_pause_run(uuid, text)',
$a$                   || jsonb_build_object('paused_at', clock_timestamp(), 'pause_reason', p_reason)
   WHERE sim_run_id = p_sim_run_id;
$a$,
$n$                   || jsonb_build_object('paused_at', clock_timestamp(), 'pause_reason', p_reason)
   WHERE sim_run_id = p_sim_run_id
     AND status = 'running';
  -- 0791 (G492): the read above takes no lock, so a stop can hold this row between that read and this UPDATE, which
  -- then waits for the stop and re-checks its WHERE on the row the stop left. A run that is no longer running is not
  -- paused, and the answer comes from the row as it is now: never 'paused', and no event.
  IF NOT FOUND THEN
    SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
    RETURN jsonb_build_object('ok', true, 'noop', true, 'status', v_run.status,
                              'note', 'run was not running');
  END IF;
$n$),
    ('public.ottoq_resume_run(uuid)',
$a$                   || jsonb_build_object('last_pause_seconds', round(v_paused_s, 2))
   WHERE sim_run_id = p_sim_run_id;
$a$,
$n$                   || jsonb_build_object('last_pause_seconds', round(v_paused_s, 2))
   WHERE sim_run_id = p_sim_run_id
     AND status = 'paused';
  -- 0791 (G492): as in ottoq_pause_run. A stop, or the demo start's abort-then-purge, can hold this row between the
  -- read above and this UPDATE, which then waits and re-checks its WHERE on the row it left. A run that is no longer
  -- paused is not resumed, and the answer comes from the row as it is now: never 'running', and no event.
  IF NOT FOUND THEN
    SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
    RETURN jsonb_build_object('ok', true, 'noop', true, 'status', v_run.status,
                              'note', 'run was not paused');
  END IF;
$n$)
  ) AS v(s, a, n)
 WHERE to_regprocedure(v.s) IS NOT NULL;

-- ── the run-control census (§1 (b) (i) and (ii)): the routines in public a browser role may execute that start a run,
--    set a run's status or delete a run, and the SECURITY DEFINER ones that reach such a routine within eight calls.
--    Comment-stripped and name-based: a name in a string counts, as dynamic SQL would carry it. ──
CREATE FUNCTION pg_temp.p0791_census() RETURNS SETOF oid LANGUAGE sql STABLE AS $fn$
  WITH RECURSIVE f AS (
    SELECT p.oid, p.proname::text AS proname, p.prosecdef, n.nspname::text AS nspname, p.prorettype,
           regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') AS s
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
     WHERE n.nspname IN ('public', 'twin', 'ottoq') AND l.lanname IN ('plpgsql', 'sql') AND p.prokind IN ('f', 'p')),
  w AS (
    SELECT f.oid FROM f
     WHERE f.s ~* '\mUPDATE\s+(ONLY\s+)?(public\.)?ottoq_sim_runs\M(\s+(AS\s+)?[a-z_][a-z0-9_]*)?\s+SET\s+((?!\mWHERE\M)[^;])*\mstatus\s*='
        OR f.s ~* '\mINSERT\s+INTO\s+(public\.)?ottoq_sim_runs\M'
        OR f.s ~* '\mDELETE\s+FROM\s+(ONLY\s+)?(public\.)?ottoq_sim_runs\M'),
  reach(oid, depth) AS (
    SELECT w.oid, 0 FROM w
    UNION
    SELECT c.oid, r.depth + 1
      FROM reach r JOIN f callee ON callee.oid = r.oid
      JOIN f c ON c.oid <> callee.oid AND c.s ~ ('\m' || callee.proname || '\s*\(')
     WHERE r.depth < 8)
  SELECT DISTINCT f.oid
    FROM reach r JOIN f ON f.oid = r.oid
   WHERE f.nspname = 'public' AND f.prorettype <> 'trigger'::regtype AND (r.depth = 0 OR f.prosecdef)
     AND (has_function_privilege('anon', f.oid, 'EXECUTE') OR has_function_privilege('authenticated', f.oid, 'EXECUTE'))
$fn$;

-- ── P1: what this file was written against ──
DO $premises$
DECLARE
  v_names constant text[] := ARRAY['ottoq_pause_run', 'ottoq_resume_run', 'ottoq_sim_run_scenario', 'ottoq_benchmark_reset',
    'ottoq_run_policy_to_end', 'ottoq_production_start', 'ottoq_production_stop', 'ottoq_cert_arm_start',
    'ottoq_cert_arm_finish', 'ottoq_cert_arm', 'ottoq_cert_arm_wave', 'ottoq_fr1_cert_arm', 'ottoq_safety_cert_arm',
    'ottoq_demo_metronome', 'ottoq_retention_purge_runs', 'ottoq_retention_purge_worker'];
  v_n int; v_bad text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0791\_%')
     OR EXISTS (SELECT 1 FROM public.ottoq_schema_snapshots WHERE label = '0791_pre') THEN
    RAISE EXCEPTION '0791 P1: 0791 has run already';
  END IF;
  SELECT count(*) INTO v_n FROM p0791_targets;
  IF v_n <> 17 THEN
    RAISE EXCEPTION '0791 P1: % of the 17 signatures exist', v_n;
  END IF;
  -- no routine of these sixteen names, in any schema, is missing from the list
  SELECT count(*) INTO v_n FROM pg_proc p WHERE p.proname = ANY (v_names);
  IF v_n <> 17 THEN
    RAISE EXCEPTION '0791 P1: the sixteen names have % routines, not 17; one is not on the list', v_n;
  END IF;
  -- owner, kind, security and ACL as read: the defect is that a browser role may execute every one
  SELECT string_agg(t.sig::text || ' ' || COALESCE(p.proacl::text, 'NULL'), '; ') INTO v_bad
    FROM p0791_targets t JOIN pg_proc p ON p.oid = t.sig
   WHERE p.proowner <> 'postgres'::regrole OR p.prokind <> t.kind OR p.prosecdef <> t.definer
      OR p.proacl IS NULL OR p.proacl::text <> t.acl;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0791 P1: not as read (owner postgres, kind, security, ACL): %', v_bad;
  END IF;
  -- the two the probes below call, byte for byte as read
  IF md5(pg_get_functiondef('public.ottoq_pause_run(uuid, text)'::regprocedure)) <> '1e3ec33aca6f4f3b008a0d83bff08c51' THEN
    RAISE EXCEPTION '0791 P1: ottoq_pause_run is not the definition this file was written against (md5 %)',
      md5(pg_get_functiondef('public.ottoq_pause_run(uuid, text)'::regprocedure));
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_resume_run(uuid)'::regprocedure)) <> 'b693dc33284db3914381f89bd7f21724' THEN
    RAISE EXCEPTION '0791 P1: ottoq_resume_run is not the definition this file was written against (md5 %)',
      md5(pg_get_functiondef('public.ottoq_resume_run(uuid)'::regprocedure));
  END IF;
  -- no SECURITY INVOKER routine outside the seventeen names one (comment-stripped; a name in a string counts) and is
  -- reachable by a browser role: a function it may execute, or a trigger on a table it may write. Revoking would break
  -- such a caller for that role, so it must be read first. The callers read on both days are SECURITY DEFINER or
  -- targets themselves.
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND NOT p.prosecdef
     AND p.oid NOT IN (SELECT t.sig FROM p0791_targets t)
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
         ~* ('\m(' || array_to_string(v_names, '|') || ')\M')
     AND CASE WHEN p.prorettype = 'trigger'::regtype THEN
                EXISTS (SELECT 1 FROM pg_trigger tg, unnest(ARRAY['anon', 'authenticated']) r(rname)
                         WHERE tg.tgfoid = p.oid AND NOT tg.tgisinternal
                           AND (   (tg.tgtype & 4  <> 0 AND has_any_column_privilege(r.rname, tg.tgrelid, 'INSERT'))
                                OR (tg.tgtype & 16 <> 0 AND has_any_column_privilege(r.rname, tg.tgrelid, 'UPDATE'))
                                OR (tg.tgtype & 8  <> 0 AND has_table_privilege(r.rname, tg.tgrelid, 'DELETE'))
                                OR (tg.tgtype & 32 <> 0 AND has_table_privilege(r.rname, tg.tgrelid, 'TRUNCATE'))))
              ELSE EXISTS (SELECT 1 FROM unnest(ARRAY['anon', 'authenticated']) r(rname)
                            WHERE has_function_privilege(r.rname, p.oid, 'EXECUTE')
                              AND has_schema_privilege(r.rname, p.pronamespace, 'USAGE'))
         END;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0791 P1: a browser role reaches a run-control routine through a SECURITY INVOKER caller; read it before revoking: %', v_bad;
  END IF;
  -- nor does a view, a policy, a column default or anything else that records a dependency (a browser role querying a
  -- view needs EXECUTE on the functions it calls)
  SELECT string_agg(DISTINCT pg_describe_object(d.classid, d.objid, d.objsubid), ', ') INTO v_bad
    FROM pg_depend d
   WHERE d.refclassid = 'pg_proc'::regclass AND d.refobjid IN (SELECT t.sig FROM p0791_targets t)
     AND d.classid <> 'pg_proc'::regclass;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0791 P1: an object depends on a run-control routine: %', v_bad;
  END IF;
  -- cron runs as postgres, which keeps its owner's right
  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE 'SELECT string_agg(DISTINCT username, '', '') FROM cron.job WHERE username <> ''postgres''' INTO v_bad;
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION '0791 P1: cron jobs run as %, not only postgres', v_bad;
    END IF;
  END IF;
  -- the census reads exactly the fourteen it names here, plus 0701's three while they are open: a new door is read
  -- before this file runs, and a census that has stopped finding the fourteen is not trusted to say V4 is empty
  SELECT string_agg(c::regprocedure::text, ', ' ORDER BY c::regprocedure::text) INTO v_bad
    FROM pg_temp.p0791_census() c
   WHERE c NOT IN (SELECT t.sig FROM p0791_targets t WHERE t.census) AND c NOT IN (SELECT o.sig FROM p0791_0701 o);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0791 P1: a browser role may execute a run-control routine this file does not name; read it before revoking: %', v_bad;
  END IF;
  SELECT string_agg(t.sig::text, ', ' ORDER BY t.sig::text) INTO v_bad
    FROM p0791_targets t WHERE t.census AND t.sig NOT IN (SELECT c FROM pg_temp.p0791_census() c);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0791 P1: the census no longer finds %; re-read it before trusting V4', v_bad;
  END IF;
  -- the probes below ask for a run that does not exist, so they change no run
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = '00000000-0000-4000-8000-000000000791') THEN
    RAISE EXCEPTION '0791 P1: the probe run id belongs to a run';
  END IF;
  -- §3's classification of the patches: no routine outside the two names either door (comment-stripped; a name in a
  -- string counts), in any schema but the catalogs and the temporary ones, and no cron job does, so no certified
  -- harness reaches the patched bodies. A caller found here may be one whose output the patch could move: read it first.
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_(toast|temp_)'
     AND p.oid NOT IN (SELECT x.sig FROM p0791_patches x)
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') ~* '\mottoq_(pause|resume)_run\M';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0791 P1: a routine calls ottoq_pause_run or ottoq_resume_run, so §3''s FALSE/FALSE is not proven; read it first: %', v_bad;
  END IF;
  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE 'SELECT string_agg(jobid::text, '', '' ORDER BY jobid) FROM cron.job WHERE command ~* ''ottoq_(pause|resume)_run''' INTO v_bad;
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION '0791 P1: cron jobs % call ottoq_pause_run or ottoq_resume_run; read them first', v_bad;
    END IF;
  END IF;
  IF (SELECT count(*) FROM p0791_patches) <> 2 THEN
    RAISE EXCEPTION '0791 P1: % of the 2 patched signatures exist', (SELECT count(*) FROM p0791_patches);
  END IF;
END $premises$;

-- every definition as it stands, for V3
CREATE TEMP TABLE p0791_md5_before ON COMMIT DROP AS
SELECT t.sig, md5(pg_get_functiondef(t.sig)) AS def_md5 FROM p0791_targets t;

-- ── the probe: as one role, pause and resume a run that does not exist; rolled back either way ──
-- 'answered' means the door ran and gave its own answer for an unknown run ({"ok": false, "error": "run not found"},
-- after one indexed read and no write); 'refused' means EXECUTE was denied (42501). The calls go through EXECUTE, never
-- as a PL/pgSQL expression, so each role's right is checked as that role (0720 measured why: a simple expression keeps
-- its executor state, and the EXECUTE check with it, for the rest of the transaction).
CREATE FUNCTION pg_temp.p0791_as(p_role text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_msg text;
BEGIN
  BEGIN
    PERFORM set_config('role', p_role, true);
    DECLARE
      v_pause text; v_resume text;
    BEGIN
      BEGIN
        EXECUTE 'SELECT CASE WHEN public.ottoq_pause_run($1, $2) ->> ''error'' = ''run not found'' THEN ''answered'' ELSE ''other'' END'
          INTO v_pause USING '00000000-0000-4000-8000-000000000791'::uuid, '0791 probe';
      EXCEPTION WHEN insufficient_privilege THEN v_pause := 'refused';
      END;
      BEGIN
        EXECUTE 'SELECT CASE WHEN public.ottoq_resume_run($1) ->> ''error'' = ''run not found'' THEN ''answered'' ELSE ''other'' END'
          INTO v_resume USING '00000000-0000-4000-8000-000000000791'::uuid;
      EXCEPTION WHEN insufficient_privilege THEN v_resume := 'refused';
      END;
      -- current_user is the control: it proves the role switch happened
      RAISE EXCEPTION 'AS %|user %|pause %|resume %', p_role, current_user, v_pause, v_resume;
    END;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RETURN v_msg;
END $fn$;

CREATE TEMP TABLE p0791 (phase text PRIMARY KEY, r text) ON COMMIT DROP;

-- ── P2: the defect, as each role: a signed-in caller reaches both doors; the public key does not; the platform does ──
DO $before$
DECLARE
  v_auth text := pg_temp.p0791_as('authenticated');
  v_anon text := pg_temp.p0791_as('anon');
  v_svc text := pg_temp.p0791_as('service_role');
BEGIN
  IF v_auth IS DISTINCT FROM 'AS authenticated|user authenticated|pause answered|resume answered'
     OR v_anon IS DISTINCT FROM 'AS anon|user anon|pause refused|resume refused'
     OR v_svc IS DISTINCT FROM 'AS service_role|user service_role|pause answered|resume answered' THEN
    RAISE EXCEPTION '0791 P2: before this file, as each role: % / % / % (expected authenticated and service_role answered, anon refused)',
      v_auth, v_anon, v_svc;
  END IF;
  INSERT INTO p0791 VALUES ('as_authenticated_before', v_auth);
  RAISE NOTICE '0791 P2: before: %; %; %', v_auth, v_anon, v_svc;
END $before$;

-- ── snapshot: the two definitions this file patches, whole, as they stand (G492's restore statements) ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0791_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN (SELECT x.sig FROM p0791_patches x)
 ORDER BY p.proname COLLATE "C";

-- ── snapshot: one GRANT per (routine, PUBLIC, anon or authenticated) this file takes: the restore statements ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0791_pre', 'grant', 'public', g.sig || '::' || g.grantee, g.stmt, md5(g.stmt)
  FROM (SELECT p.oid::regprocedure::text AS sig,
               CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS grantee,
               format('GRANT EXECUTE ON %s public.%I(%s) TO %s;',
                      CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
                      p.proname, pg_get_function_identity_arguments(p.oid),
                      CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END) AS stmt
          FROM p0791_targets t JOIN pg_proc p ON p.oid = t.sig CROSS JOIN LATERAL aclexplode(p.proacl) a
         WHERE a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR a.grantee IN ('anon'::regrole, 'authenticated'::regrole))) g
 ORDER BY g.sig COLLATE "C", g.grantee COLLATE "C";   -- byte order: the snapshot_id order is the same on every cluster

-- ── G492: the patches, each anchor asserted to match exactly once ──
CREATE FUNCTION pg_temp.p0791_patch(p_sig regprocedure, p_anchor text, p_new text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_def text := pg_get_functiondef(p_sig);
BEGIN
  IF (length(v_def) - length(replace(v_def, p_anchor, ''))) / length(p_anchor) <> 1 THEN
    RAISE EXCEPTION '0791: the anchor in % does not match exactly once: %', p_sig, left(p_anchor, 80);
  END IF;
  RETURN replace(v_def, p_anchor, p_new);
END $fn$;

DO $sub$
DECLARE r record;
BEGIN
  FOR r IN SELECT x.sig, x.anchor, x.patched FROM p0791_patches x ORDER BY x.sig::text COLLATE "C" LOOP
    EXECUTE pg_temp.p0791_patch(r.sig, r.anchor, r.patched);
  END LOOP;
END $sub$;

-- ── the change: closed to PUBLIC and the browser roles, kept for the platform ──
REVOKE EXECUTE ON FUNCTION
  public.ottoq_pause_run(uuid, text), public.ottoq_resume_run(uuid),
  public.ottoq_sim_run_scenario(text, bigint, text, timestamp with time zone),
  public.ottoq_benchmark_reset(uuid, numeric, numeric), public.ottoq_run_policy_to_end(uuid, integer),
  public.ottoq_production_start(uuid), public.ottoq_production_stop(text),
  public.ottoq_cert_arm_start(bigint, text, uuid, integer), public.ottoq_cert_arm_finish(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON PROCEDURE
  public.ottoq_cert_arm(bigint, text, uuid, integer, timestamp with time zone, integer),
  public.ottoq_cert_arm_wave(bigint, text, uuid, integer, integer),
  public.ottoq_fr1_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, boolean),
  public.ottoq_safety_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, numeric),
  public.ottoq_demo_metronome(integer),
  public.ottoq_retention_purge_runs(integer, integer, interval, boolean),
  public.ottoq_retention_purge_worker(integer, integer, interval, text[]),
  public.ottoq_retention_purge_worker(integer, integer, interval)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.ottoq_pause_run(uuid, text), public.ottoq_resume_run(uuid),
  public.ottoq_sim_run_scenario(text, bigint, text, timestamp with time zone),
  public.ottoq_benchmark_reset(uuid, numeric, numeric), public.ottoq_run_policy_to_end(uuid, integer),
  public.ottoq_production_start(uuid), public.ottoq_production_stop(text),
  public.ottoq_cert_arm_start(bigint, text, uuid, integer), public.ottoq_cert_arm_finish(uuid)
  TO service_role;
GRANT EXECUTE ON PROCEDURE
  public.ottoq_cert_arm(bigint, text, uuid, integer, timestamp with time zone, integer),
  public.ottoq_cert_arm_wave(bigint, text, uuid, integer, integer),
  public.ottoq_fr1_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, boolean),
  public.ottoq_safety_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, numeric),
  public.ottoq_demo_metronome(integer),
  public.ottoq_retention_purge_runs(integer, integer, interval, boolean),
  public.ottoq_retention_purge_worker(integer, integer, interval, text[]),
  public.ottoq_retention_purge_worker(integer, integer, interval)
  TO service_role;

-- ── V1: the catalog: no PUBLIC, no browser role; service_role and the owner keep all seventeen ──
DO $vone$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text || ' ' || COALESCE(p.proacl::text, 'NULL'), '; ') INTO v_bad
    FROM p0791_targets t JOIN pg_proc p ON p.oid = t.sig
   WHERE has_function_privilege('anon', p.oid, 'EXECUTE')
      OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
      OR NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
      OR NOT has_function_privilege('postgres', p.oid, 'EXECUTE')
      OR p.proacl IS NULL
      OR p.proacl::text <> '{postgres=X/postgres,service_role=X/postgres}';
  IF v_bad IS NOT NULL OR (SELECT count(*) FROM p0791_targets) <> 17 THEN
    RAISE EXCEPTION '0791 V1 FAILED: grants not as written: %', v_bad;
  END IF;
  RAISE NOTICE '0791 V1 PASSED: all 17 ACLs read {postgres=X/postgres,service_role=X/postgres}';
END $vone$;

-- ── V2: as each role: authenticated and anon are refused (42501); service_role still reaches both doors ──
DO $vtwo$
DECLARE
  v_auth text := pg_temp.p0791_as('authenticated');
  v_anon text := pg_temp.p0791_as('anon');
  v_svc text := pg_temp.p0791_as('service_role');
BEGIN
  IF v_auth IS DISTINCT FROM 'AS authenticated|user authenticated|pause refused|resume refused'
     OR v_anon IS DISTINCT FROM 'AS anon|user anon|pause refused|resume refused'
     OR v_svc IS DISTINCT FROM 'AS service_role|user service_role|pause answered|resume answered' THEN
    RAISE EXCEPTION '0791 V2 FAILED: % / % / %', v_auth, v_anon, v_svc;
  END IF;
  RAISE NOTICE '0791 V2 PASSED: before: %; after: %; %; %; rolled back',
    (SELECT r FROM p0791 WHERE phase = 'as_authenticated_before'), v_auth, v_anon, v_svc;
END $vtwo$;

-- ── V3: the fifteen this file does not patch are byte for byte as P1 read them; the two it patches changed, and undoing
--    each patch gives back its snapshot byte for byte (header included, so the signature, SECURITY DEFINER and the
--    search_path are proven unchanged; CREATE OR REPLACE keeps the grants and the owner) ──
DO $vthree$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(b.sig::text, ', ') INTO v_bad
    FROM p0791_md5_before b
   WHERE b.sig NOT IN (SELECT x.sig FROM p0791_patches x) AND b.def_md5 <> md5(pg_get_functiondef(b.sig));
  IF v_bad IS NOT NULL OR (SELECT count(*) FROM p0791_md5_before) <> 17 THEN
    RAISE EXCEPTION '0791 V3 FAILED: a definition this file does not patch changed: %', v_bad;
  END IF;
  SELECT string_agg(x.sig::text, ', ') INTO v_bad
    FROM p0791_patches x JOIN pg_proc p ON p.oid = x.sig
    LEFT JOIN public.ottoq_schema_snapshots s ON s.label = '0791_pre' AND s.object_kind = 'function' AND s.object_name = p.proname
   WHERE s.definition IS NULL
      OR md5(s.definition) IS DISTINCT FROM (SELECT b.def_md5 FROM p0791_md5_before b WHERE b.sig = x.sig)
      OR pg_get_functiondef(x.sig) = s.definition
      OR replace(pg_get_functiondef(x.sig), x.patched, x.anchor) IS DISTINCT FROM s.definition;
  IF v_bad IS NOT NULL OR (SELECT count(*) FROM p0791_patches) <> 2
     OR (SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0791_pre' AND object_kind = 'function') <> 2 THEN
    RAISE EXCEPTION '0791 V3 FAILED: changed by more than its patch, or not at all: %', v_bad;
  END IF;
  RAISE NOTICE '0791 V3 PASSED: the fifteen unpatched definitions unchanged; ottoq_pause_run (1e3ec33a, now %) and ottoq_resume_run (b693dc33, now %) changed by their patch alone',
    left(md5(pg_get_functiondef('public.ottoq_pause_run(uuid, text)'::regprocedure)), 8),
    left(md5(pg_get_functiondef('public.ottoq_resume_run(uuid)'::regprocedure)), 8);
END $vthree$;

-- ── V4: the census after: no run-control routine is executable by a browser role, except 0701's while they are open ──
DO $vfour$
DECLARE v_bad text; v_left text;
BEGIN
  SELECT string_agg(c::regprocedure::text, ', ' ORDER BY c::regprocedure::text) INTO v_bad
    FROM pg_temp.p0791_census() c WHERE c NOT IN (SELECT o.sig FROM p0791_0701 o);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0791 V4 FAILED: a browser role may still execute a run-control routine: %', v_bad;
  END IF;
  SELECT string_agg(c::regprocedure::text, ', ' ORDER BY c::regprocedure::text) INTO v_left FROM pg_temp.p0791_census() c;
  RAISE NOTICE '0791 V4 PASSED: no run-control routine a browser role may execute%',
    COALESCE(', except 0701''s, which 0701 closes: ' || v_left, '');
END $vfour$;

-- ── V5: G492, comment-stripped and whitespace-tolerant: each door's one UPDATE of ottoq_sim_runs carries the status it
--    read, and when it takes nothing the door answers from the row as it is now, before its event ──
DO $vfive$
DECLARE v_src text; v_n int; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_pause_run(uuid, text)'::regprocedure, 'paused', 'running', 'run was not running'),
      ('public.ottoq_resume_run(uuid)'::regprocedure, 'running', 'paused', 'run was not paused')) AS v(sig, sets, reads, note)
  LOOP
    SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
      FROM pg_proc p WHERE p.oid = r.sig;
    SELECT count(*) INTO v_n FROM regexp_matches(v_src, '\mUPDATE\s+(ONLY\s+)?(public\.)?ottoq_sim_runs\M', 'gi');
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0791 V5 FAILED: % has % UPDATEs of ottoq_sim_runs, not 1', r.sig, v_n;
    END IF;
    IF v_src !~* ('\mUPDATE\s+(public\.)?ottoq_sim_runs\s+SET\s+status\s*=\s*''' || r.sets || '''[^;]*\mWHERE\s+'
                  || 'sim_run_id\s*=\s*p_sim_run_id\s+AND\s+status\s*=\s*''' || r.reads || '''\s*;') THEN
      RAISE EXCEPTION '0791 V5 FAILED: %''s UPDATE does not carry AND status = ''%''', r.sig, r.reads;
    END IF;
    IF v_src !~* ('\mAND\s+status\s*=\s*''' || r.reads || '''\s*;\s*IF\s+NOT\s+FOUND\s+THEN\s+'
                  || 'SELECT\s+\*\s+INTO\s+v_run\s+FROM\s+(public\.)?ottoq_sim_runs\s+WHERE\s+sim_run_id\s*=\s*p_sim_run_id\s*;\s*'
                  || 'IF\s+NOT\s+FOUND\s+THEN\s+RETURN\s+jsonb_build_object\(\s*''ok''\s*,\s*false\s*,\s*''error''\s*,\s*'
                  || '''run not found''\s*\)\s*;\s*END\s+IF\s*;\s*'
                  || 'RETURN\s+jsonb_build_object\(\s*''ok''\s*,\s*true\s*,\s*''noop''\s*,\s*true\s*,\s*''status''\s*,\s*'
                  || 'v_run\.status\s*,\s*''note''\s*,\s*''' || r.note || '''\s*\)\s*;\s*END\s+IF\s*;\s*'
                  || 'PERFORM\s+ottoq_record_event\(') THEN
      RAISE EXCEPTION '0791 V5 FAILED: % does not answer from the row count, before its event, when its UPDATE takes nothing', r.sig;
    END IF;
  END LOOP;
  RAISE NOTICE '0791 V5 PASSED: ottoq_pause_run updates only a running run and ottoq_resume_run only a paused one, and each answers from the row as it is now when its UPDATE takes nothing';
END $vfive$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0791_a_signed_in_user_cannot_pause_resume_start_or_stop_a_run_and_a_pause_or_resume_never_writes_over_a_stopped_run',
  false, false,
  'G493: REVOKE EXECUTE FROM PUBLIC, anon and authenticated on 17 run-control routines, service_role and postgres kept. '
  'Five were SECURITY DEFINER doors any signed-in caller could use on any run, production included: ottoq_pause_run, '
  'ottoq_resume_run, ottoq_sim_run_scenario (stops and resets the depot''s runs and starts one), ottoq_run_policy_to_end '
  '(ticks a run up to N ticks) and ottoq_benchmark_reset. Twelve run as the caller and could do no harm: '
  'ottoq_production_start and _stop (0448), ottoq_cert_arm_start and _finish, and eight procedures PostgREST cannot '
  'call (the cert arms, the metronome, the retention purge). No browser caller in any repository, live edge function, '
  'API log or SQL caller. 0701''s three are left to 0701; otto-twin-control''s open routes (G394) are unchanged. '
  'G492: ottoq_pause_run and ottoq_resume_run updated by sim_run_id alone after an unlocked read, so one that waited '
  'behind a stop wrote paused or running over the stopped run; each UPDATE now carries the status it read (running, '
  'paused) and a door whose UPDATE takes nothing answers from the row as it is now (noop, or run not found), before '
  'its event. Anchored on the md5-pinned bodies (1e3ec33a, b693dc33), nothing else moved (V3), predicates asserted (V5). '
  'No routine in any schema, no cron job and no dependent names either door (P1), so no certified harness reaches '
  'them; in one session the read and the UPDATE see the same row and the doors write as before; grants are read by '
  'no atom: FALSE/FALSE.',
  now());

COMMIT;
