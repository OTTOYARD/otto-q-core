-- 0438  **Anyone who signs up could read the key that signs every event, SDR and audit bundle, and sign or purge with
--        it; the post-apply proof that 0701 closed the key, the signers and the purge, and the surface it leaves,
--        including the 35 doors through which a signed-in caller still gets a system-signed event.** (FINDINGS
--        G428, the study's CI-1; G417's grant half.) Measured read-only on 2026-10-13 on the live catalog
--        (gxdrcyphqjzjsuhxuqtg, PostgreSQL 17.6) and the API logs, ending 15:19 UTC (10:19 AM CT, read from the clock
--        after the last query); re-measured after review from 18:57:27 UTC (1:57 PM CT) to 19:06:30 UTC (2:06 PM CT,
--        read from the clock), unchanged, with (E) added. Every query below is read-only and none calls the resolver
--        or a signer: reading the key to prove it is closed would be the defect.
--
-- ══ §1 WHAT WAS OPEN (before 0701; reproduce (A)-(D)) ═══════════════════════════════════════════════════════════
--
--   Eighteen SECURITY DEFINER signatures (sixteen names) executable by authenticated, three of them by anon and PUBLIC
--   too (A). The resolver returns the Vault secret of 'system:v1', the only signing key; the three signers return an
--   HMAC under it of whatever the caller passes; ottoq_oem_deliver_live reads any Vault secret by a caller-supplied
--   name and POSTs a payload signed with it to a caller-supplied URL. 0198 is how the signing four reached
--   authenticated (B): it found them at {postgres=X,service_role=X} on 2026-09-06 03:21:56 UTC and granted them. The
--   resolver read two settings before Vault and cached the key for the whole session. Every caller of the resolver
--   and the signers inside the database is SECURITY DEFINER (C). In the logs the API holds (2026-10-10 15:06 UTC to
--   2026-10-13 14:50 UTC) no role asked for any of the sixteen, and the only signed-in RPC requests were 10, to
--   0700's sign-in doors (D).
--
-- ══ §2 WHAT 0701 MUST LEAVE (run (1)-(7) after the apply) ════════════════════════════════════════════════════════
--
--   (1) the eighteen: 18 rows, every one anon false, authenticated false, public_entry false, service_role true.
--   (2) the resolver: one row, prosrc_md5 ae44bc24121d3b33e6dcfc94b54b8c28, definer true, volatile v, the same
--       search_path, and no override read, no session-scope cache.
--   (3) postgres's default privileges for functions: six rows,
--         (global)   {postgres=X/postgres}                          new: the only form that drops PUBLIC
--         extensions {=X/postgres}                                  new: keeps PUBLIC there
--         ottoq      {service_role=X/postgres}                      new
--         public     {postgres=X/postgres,service_role=X/postgres}  anon and authenticated gone
--         storage    {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--                    untouched: Supabase's, and postgres owns no function in storage (measured before 0701)
--         twin       {service_role=X/postgres}                      new
--       The test: outside storage no row grants anon or authenticated, and outside extensions none grants PUBLIC.
--   (4) the browser roles' census (VOLATILE SECURITY DEFINER non-trigger functions in public that anon or authenticated
--       may execute) equals the 124 below: zero rows. 112 of them carry no file naming a signed-in reader (basis
--       'OPEN'); that list is the next item, not a clean bill.
--   (5) ottoq_assert_anon_rpc_surface(): zero rows (it returned ottoq_fit_charge_fault_model before).
--   (6) the lineage row FALSE/FALSE, carrying Chase's go-ahead with its date and CT time (0701 §0, P0a), and 31
--       restore statements under '0701_pre' (1 function, 24 grants, 6 defaults).
--   (7) the engine still signs: every SDR issued after the apply carries a signature (signed = issued; issued > 0 once
--       any run has produced one since).
--   (8) the API after the apply: no service_role request for any of the sixteen refused (401/403); a browser request
--       for one, if any, refused. Run in the Supabase logs explorer over a window starting at the apply.
--
-- ══ §3 WHAT IS NOT PROVED HERE ═══════════════════════════════════════════════════════════════════════════════════
--
--   Whether the key was read before 0701. The API logs reach back three days and show no request for the resolver,
--   but the grant has existed since 2026-09-06. Rotating the key is Chase's decision (FINDINGS G428), and it changes
--   every signature from then on, which no atom reads (0701 §3).
--   That a signed-in caller can no longer get a system signature at all. It cannot read the key or call a signer, but
--   (E) lists 35 SECURITY DEFINER functions it may still execute that write a signed event (measured 2026-10-13 18:58
--   UTC: 35, 21 directly, none by anon); authenticated may SELECT ottoq_events.signature, and
--   ottoq_verify_event_signature returns the HMAC it computes for any existing event. Those go with the 124 in (4).

-- (1) the eighteen, after 0701
SELECT p.proname || '(' || oidvectortypes(p.proargtypes) || ')' AS fn,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated,
       EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0) AS public_entry,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('ottoq_resolve_signing_secret', 'ottoq_sign_event', 'ottoq_sign_sdr', 'ottoq_sign_bundle',
                     'ottoq_oem_deliver_live', 'ottoq_energy_mpc_replan', 'ottoq_purge_prior_runs', 'ottoq_start_busy_run',
                     'ottoq_start_busy_run_once', 'ottoq_release_unusable_reservations', 'ottoq_fit_charge_fault_model',
                     'ottoq_record_event', 'ottoq_emit_sdr', 'ottoq_generate_audit_bundle', 'ottoq_complete_audit_report',
                     'ottoq_probe_task_completion')
 ORDER BY 1;

-- (2) the resolver, after 0701
SELECT md5(p.prosrc) AS prosrc_md5, p.prosecdef AS definer, p.provolatile AS volatile, p.proconfig,
       regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'signing_secret_default|ottoq\.signing_secret_' AS reads_an_override,
       regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'set_config\([^)]*,\s*false\s*\)' AS session_scope_cache,
       md5(pg_get_functiondef(p.oid)) AS def_md5_for_the_applied_footer
  FROM pg_proc p WHERE p.oid = 'public.ottoq_resolve_signing_secret(text)'::regprocedure;

-- (3) postgres's default privileges for functions, after 0701
SELECT CASE WHEN d.defaclnamespace = 0 THEN '(global)' ELSE d.defaclnamespace::regnamespace::text END AS schema, d.defaclacl::text AS acl,
       EXISTS (SELECT 1 FROM aclexplode(d.defaclacl) a WHERE a.grantee IN ('anon'::regrole, 'authenticated'::regrole)) AS grants_a_browser_role,
       EXISTS (SELECT 1 FROM aclexplode(d.defaclacl) a WHERE a.grantee = 0) AS grants_public
  FROM pg_default_acl d
 WHERE d.defaclrole = 'postgres'::regrole AND d.defaclobjtype = 'f'
 ORDER BY 1;

-- (4) the census against the reviewed list: zero rows after 0701
WITH allow(fn, role, basis) AS (VALUES
    ('cuopt_log_gate(uuid, text, integer, jsonb, timestamp with time zone, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_account_disconnect(uuid)', 'authenticated', '0700: the sign-in page'),
    ('ottoq_agent_board(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_agent_request_decide(uuid, text, text)', 'authenticated', '0559: a person decides an agent request'),
    ('ottoq_amend_apply(uuid, jsonb, text, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_api_otto_q_decide(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_api_twin_apply_commands(uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_apply_bess_setpoint(uuid, numeric, numeric, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_apply_need_escalation(uuid, boolean)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_apply_ops_action(uuid, uuid, text, jsonb, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_archive_run(uuid, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_assert_bess_state_vocabulary()', 'anon', 'read-only assert, PUBLIC by default'),
    ('ottoq_assert_dispatch_time_coherence(uuid)', 'anon', 'read-only assert, PUBLIC by default'),
    ('ottoq_assert_snapshot_integrity(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_benchmark_reset(uuid, numeric, numeric)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_build_workflow_plan(uuid, uuid, timestamp with time zone, jsonb)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_capture_decision_snapshot(uuid, bigint, uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_check_fence_containment(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_check_stall_overlap(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_claim_tick_kw(uuid, bigint, uuid, numeric, uuid, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_close_atom_leg(uuid, uuid, text, timestamp with time zone, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_close_run_needs(uuid, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_comms_advance(uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_comms_emit_telemetry(uuid, uuid, timestamp with time zone, numeric, numeric, numeric, numeric)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_comms_escalate(uuid, uuid, text, jsonb, timestamp with time zone, text, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_comms_manager_escalate(text, text, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_comms_send_command(uuid, uuid, text, jsonb, timestamp with time zone, boolean)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_comms_teleop_respond(uuid, text, text, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_comms_teleop_review(uuid, uuid, uuid, text, jsonb, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_compute_accuracy_for_window(text, uuid, uuid, text, integer, date, integer, integer, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_compute_audit_trail_completeness(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_compute_depot_benchmark(uuid, date)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_compute_sla_conformance_for_day(uuid, uuid, date)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_compute_visit_cost(uuid, uuid, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, uuid, uuid, uuid, timestamp with time zone, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_cuopt_defer_arm(uuid, bigint, uuid[], bigint)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_cuopt_defer_hold(uuid, uuid, bigint)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_cuopt_defer_roll(uuid, bigint)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_cuopt_first_refusal_arm(uuid, bigint)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_cuopt_refresh(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_decide_indepot_approvals(uuid, uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_decide_tick(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_emit_recommendation(text, uuid, text, jsonb, text, uuid, uuid, uuid, boolean, uuid, uuid, integer)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_energy_mpc_ingest(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_energy_mpc_ingest_run(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_energy_orchestrate(uuid, uuid, timestamp with time zone, bigint)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_evaluate_return_need(uuid, uuid, timestamp with time zone, numeric, numeric)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_evaluate_rule(text, text, uuid, jsonb, text, uuid, uuid, uuid, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_evaluate_rule_core(text, text, uuid, jsonb, text, uuid, uuid, uuid, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_evaluate_rules_for_action(text, text, uuid, jsonb, uuid, uuid, uuid, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_fn_backup_enact_cuopt_batch(uuid, uuid, timestamp with time zone, bigint, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_gc_stale_reservations()', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_generate_incident_report(uuid, text, integer, integer, text, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_greedy_tick(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_honour_reservation_proposal(uuid, uuid, uuid, jsonb)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_hw_recall_vehicle(uuid, text, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_hw_set_return_threshold(uuid, integer, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_indepot_reassignment_guard(uuid, uuid, text, jsonb)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_ingest_service_complete(uuid, text, text, text[])', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_ingest_vehicle_signal(uuid, numeric, numeric, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_intelligence_refresh()', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_itin_close_travel_legs(uuid, timestamp with time zone, integer)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_itin_travel_leg(uuid, uuid, uuid, uuid, uuid, timestamp with time zone, text, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_l1_override_authorized(text, text, text, text, text, uuid, uuid, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_l2_optimize_assignments(uuid, uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_log_inference_complete(uuid, jsonb, numeric, numeric, numeric, numeric, text, uuid, integer, integer, text, text, text, uuid, numeric, numeric)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_log_inference_start(text, uuid, uuid, text, uuid, uuid, uuid, text, jsonb, uuid[], text, uuid, text, boolean, uuid, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_log_model_call(text, text, text, uuid, uuid, bigint, timestamp with time zone, text, text, text, integer, integer, integer, boolean, jsonb, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_mark_recommendation_executed(uuid, text, text, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_mark_visit_atoms_done(uuid, text[], timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_mirror_dr_call(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_mirror_grid_event_to_ottoq(uuid, text, timestamp with time zone, timestamp with time zone, jsonb, boolean)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_oauth_device_decide(text, text)', 'authenticated', '0700: the sign-in page'),
    ('ottoq_oauth_device_lookup(text)', 'authenticated', '0700: the sign-in page'),
    ('ottoq_oauth_request_decide(uuid, text)', 'authenticated', '0700: the sign-in page'),
    ('ottoq_oem_webhook_collect_responses()', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_onboard_vehicle_battery(uuid, text, numeric, integer, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_ops_approval_decide(uuid, text, text)', 'authenticated', '0487: the crew decides'),
    ('ottoq_ops_set_rush_valve(uuid, boolean, text, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_pause_run(uuid, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_plan_overnight_wave(uuid, timestamp with time zone, integer, numeric, numeric)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_plan_visit_itinerary(uuid, uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_progress_commit(text, uuid, uuid, uuid, text, uuid, uuid, integer, integer, uuid, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_promote_dials(uuid, boolean)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_promote_proposal_candidates(uuid, bigint, timestamp with time zone, integer)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_proposal_replay_capture(uuid, uuid, text[])', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_proposal_replay_inject(uuid, uuid, integer)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_recall_fixed_window_dummy(uuid, uuid, timestamp with time zone, numeric, numeric)', 'authenticated', '0206: recall implementation'),
    ('ottoq_recall_interval_scheduled_v1(uuid, uuid, timestamp with time zone, numeric, numeric)', 'authenticated', '0448: recall implementation'),
    ('ottoq_recall_naive_threshold_v1(uuid, uuid, timestamp with time zone, numeric, numeric)', 'authenticated', '0206: recall implementation'),
    ('ottoq_reconcile_charger_states(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_record_balance_charge(uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_record_counterfactual(text, uuid, text, text, jsonb, uuid, jsonb, jsonb, jsonb, text, numeric, numeric, text, uuid, uuid, uuid, text, text, uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_record_feature_value(text, text, uuid, numeric, bigint, boolean, text, timestamp with time zone, jsonb, timestamp with time zone, timestamp with time zone, text, uuid, text, uuid, uuid, numeric, boolean, boolean)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_record_prediction(text, uuid, uuid, uuid, jsonb, numeric, numeric, numeric, numeric, text, text, timestamp with time zone, integer, text, text, jsonb, text, jsonb, uuid, uuid, text, jsonb, uuid[], integer, boolean, uuid, uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_record_sla_violation(uuid, uuid, uuid, uuid, text, uuid, text, text, jsonb, jsonb, numeric, text, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_record_tick_failure(uuid, text, text, text)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_refresh_return_eta(uuid, uuid, timestamp with time zone, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_register_audit_report(text, text, uuid, uuid, timestamp with time zone, timestamp with time zone, text, text, text, text, text, timestamp with time zone, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_release_expired_tethers(timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_reopen_visit_atoms(uuid, text[], timestamp with time zone, text, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_resume_run(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_rollback_dial_promotion(bigint)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_run_archive_stamp(uuid, text, jsonb)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_run_boot_draw(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_run_policy_to_end(uuid, integer)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_score_observation(text, text, uuid, jsonb, numeric, timestamp with time zone, uuid, uuid, jsonb)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_score_run(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_seed_vehicle_need_profiles(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_service_priority_propose(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_shield_and_log(uuid, bigint, uuid, jsonb, boolean)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_shield_probe(text, text, uuid, jsonb, uuid, uuid, uuid, uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_sim_run_scenario(text, bigint, text, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_start_concurrent_atoms(uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_submit_external_proposal(uuid, uuid, text, text, uuid, jsonb, text, integer)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_sweep_orphaned_visit_artifacts(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_sweep_stranded_deployments(uuid, timestamp with time zone, integer)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_twin_appointments(uuid)', 'anon', '0405: the twin app (public key)'),
    ('ottoq_twin_arrival_soc_drain(uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_twin_climate_stress(uuid, integer)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_twin_incident_weather_mult(uuid, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_twin_snapshot(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_verify_audit_bundle(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_verify_event_signature(uuid)', 'authenticated', 'OPEN: no file names a signed-in reader'),
    ('ottoq_wear_mark_serviced(uuid, uuid, text, timestamp with time zone)', 'authenticated', 'OPEN: no file names a signed-in reader')
), census AS (
  SELECT p.proname || '(' || oidvectortypes(p.proargtypes) || ')' AS fn,
         CASE WHEN has_function_privilege('anon', p.oid, 'EXECUTE') THEN 'anon' ELSE 'authenticated' END AS role
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace AND p.prosecdef AND p.provolatile = 'v' AND p.prokind = 'f'
     AND p.prorettype <> 'trigger'::regtype
     AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE')))
SELECT coalesce(c.fn, a.fn) AS fn,
       CASE WHEN a.fn IS NULL THEN 'NEW: executable by ' || c.role || ', on no list'
            WHEN c.fn IS NULL THEN 'GONE: on the list, no longer executable by a browser role (update the list)'
            ELSE 'ROLE CHANGED: ' || a.role || ' -> ' || c.role END AS finding
  FROM census c FULL JOIN allow a ON a.fn = c.fn
 WHERE a.fn IS NULL OR c.fn IS NULL OR a.role <> c.role
 ORDER BY 1;

-- (5) the standing anon gate: zero rows after 0701
SELECT * FROM public.ottoq_assert_anon_rpc_surface();

-- (6) the lineage row, Chase's go-ahead in its note, and the restore statements
--     must read: lineage 'false/false', go_ahead_recorded true, restore_statements 'default_privileges 6, function 1, grant 24'
SELECT (SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage
         WHERE name = '0701_a_signed_in_user_cannot_read_the_signing_key_or_call_the_signers_or_purge') AS lineage,
       (SELECT note ~ 'Chase''s go-ahead \(FINDINGS G417\): .*2026-\d\d-\d\d' AND note ~* '\d{1,2}:\d\d\s*(AM|PM)\s+CT'
               AND note !~ 'go-ahead \(FINDINGS G417\): PENDING'
          FROM public.ottoq_cert_lineage
         WHERE name = '0701_a_signed_in_user_cannot_read_the_signing_key_or_call_the_signers_or_purge') AS go_ahead_recorded,
       (SELECT string_agg(k || ' ' || n, ', ' ORDER BY k)
          FROM (SELECT object_kind AS k, count(*) AS n FROM public.ottoq_schema_snapshots WHERE label = '0701_pre'
                 GROUP BY object_kind) s) AS restore_statements;

-- (7) the engine still signs: SDRs issued since the apply (the lineage row's classified_at is the apply's now())
SELECT count(*) AS issued, count(signature) AS signed, max(issued_at) AS newest
  FROM public.ottoq_service_detail_records
 WHERE issued_at >= (SELECT classified_at FROM public.ottoq_cert_lineage
                      WHERE name = '0701_a_signed_in_user_cannot_read_the_signing_key_or_call_the_signers_or_purge');

-- (8) the API after the apply (Supabase logs, ClickHouse; a window from the apply, at most 24 hours):
--   SELECT log_attributes['request.path'] AS path, log_attributes['request.sb.jwt.authorization.payload.role'] AS role,
--          log_attributes['response.status_code'] AS status, count() AS n, max(timestamp) AS last_seen
--     FROM logs
--    WHERE source = 'edge_logs'
--      AND match(log_attributes['request.path'], '^/rest/v1/rpc/ottoq_(resolve_signing_secret|sign_(event|sdr|bundle)|oem_deliver_live|energy_mpc_replan|purge_prior_runs|start_busy_run(_once)?|release_unusable_reservations|fit_charge_fault_model|record_event|emit_sdr|generate_audit_bundle|complete_audit_report|probe_task_completion)$')
--    GROUP BY path, role, status ORDER BY n DESC;
--   Must show: no 401/403 for service_role (role '' with the secret key); otto-twin-control's ottoq_record_event 200.

-- ══ REPRODUCE §1 (read-only; these describe the state BEFORE 0701 and read differently after it) ══

-- (A) the eighteen before: authenticated true on all, anon and a PUBLIC entry on three
--   (the query in (1); before the apply it read authenticated true x18, anon true x3, public_entry true x3)

-- (B) how the signing four reached authenticated
SELECT function_name, acl_before, actions, taken_at
  FROM public.ottoq_grant_snapshot_0198
 WHERE function_name IN ('ottoq_resolve_signing_secret', 'ottoq_sign_event', 'ottoq_record_event', 'ottoq_purge_prior_runs')
 ORDER BY 1;

-- (C) every SECURITY INVOKER caller of the sixteen, comment-stripped (before and after: the same 13; the resolver and
--     the three signers have none). Measured 2026-10-13: four triggers, on tables no browser role may write
--     (browser_writes_its_table false x4); three not callable by authenticated; six callable (ottoq_cil_tick,
--     ottoq_mpc_lookahead, ottoq_mpc_energy_lookahead, ottoq_predict_arrivals, ottoq_production_start,
--     ottoq_production_stop), which after 0701 fail at ottoq_record_event for authenticated as they already did for anon.
SELECT n.nspname || '.' || p.proname AS caller, p.prorettype = 'trigger'::regtype AS is_trigger,
       CASE WHEN p.prorettype = 'trigger'::regtype THEN NULL
            ELSE has_function_privilege('authenticated', p.oid, 'EXECUTE')
                 AND has_schema_privilege('authenticated', p.pronamespace, 'USAGE') END AS authenticated_can_call,
       CASE WHEN p.prorettype = 'trigger'::regtype THEN
              EXISTS (SELECT 1 FROM pg_trigger tg, unnest(ARRAY['anon', 'authenticated']) r(rname)
                       WHERE tg.tgfoid = p.oid AND NOT tg.tgisinternal
                         AND (has_any_column_privilege(r.rname, tg.tgrelid, 'INSERT')
                              OR has_any_column_privilege(r.rname, tg.tgrelid, 'UPDATE'))) END AS browser_writes_its_table
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND NOT p.prosecdef
   AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
       ~ '\m(ottoq_resolve_signing_secret|ottoq_sign_event|ottoq_sign_sdr|ottoq_sign_bundle|ottoq_oem_deliver_live|ottoq_energy_mpc_replan|ottoq_purge_prior_runs|ottoq_start_busy_run|ottoq_start_busy_run_once|ottoq_release_unusable_reservations|ottoq_fit_charge_fault_model|ottoq_record_event|ottoq_emit_sdr|ottoq_generate_audit_bundle|ottoq_complete_audit_report|ottoq_probe_task_completion)\s*\('
 ORDER BY 1;

-- (D) the API logs before (Supabase logs, one 24-hour window per query; 2026-10-10 15:06 UTC is the earliest row held):
--   SELECT log_attributes['request.path'] AS path, log_attributes['response.status_code'] AS status, count() AS n
--     FROM logs
--    WHERE source = 'edge_logs' AND log_attributes['request.path'] LIKE '/rest/v1/rpc/%'
--      AND log_attributes['request.sb.jwt.authorization.payload.role'] = 'authenticated'
--    GROUP BY path, status;
--   2026-10-10T14:50Z-10-11T14:50Z: ottoq_account_me 5, ottoq_oauth_device_decide 2, ottoq_oauth_device_lookup 2,
--   ottoq_account_disconnect 1 (all 200); the two later windows: 0. The same three windows hold 0 requests, from any
--   role, whose path names any of the sixteen.

-- (E) what a signed-in caller can still get signed, after 0701 as before it: SECURITY DEFINER functions in public,
--     outside the eighteen, that a browser role may execute and that reach ottoq_record_event within six calls
--     (comment-stripped prosrc, plpgsql and sql bodies in public, twin and ottoq; name-based, so it over-approximates a
--     call through a same-named function and cannot see dynamic SQL). Measured 2026-10-13 18:58 UTC: doors 35, direct
--     21, anon_doors 0. After 0701 it must read the same 35 (0701 closes none of them; the next item does).
WITH RECURSIVE f AS (
  SELECT p.oid, p.proname, p.prosecdef, n.nspname, p.prorettype,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') AS s
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
   WHERE n.nspname IN ('public', 'twin', 'ottoq') AND l.lanname IN ('plpgsql', 'sql') AND p.prokind IN ('f', 'p')),
reach(oid, depth) AS (
  SELECT f.oid, 1 FROM f WHERE f.s ~ '\mottoq_record_event\s*\(' AND f.proname <> 'ottoq_record_event'
  UNION
  SELECT c.oid, r.depth + 1 FROM reach r JOIN f callee ON callee.oid = r.oid
    JOIN f c ON c.s ~ ('\m' || callee.proname || '\s*\(') AND c.oid <> callee.oid
   WHERE r.depth < 6),
door AS (
  SELECT f.oid, f.proname AS fn, min(r.depth) AS d
    FROM reach r JOIN f ON f.oid = r.oid
   WHERE f.prosecdef AND f.nspname = 'public' AND f.prorettype <> 'trigger'::regtype
     AND f.proname <> ALL (ARRAY['ottoq_resolve_signing_secret', 'ottoq_sign_event', 'ottoq_sign_sdr', 'ottoq_sign_bundle',
                                 'ottoq_oem_deliver_live', 'ottoq_energy_mpc_replan', 'ottoq_purge_prior_runs',
                                 'ottoq_start_busy_run', 'ottoq_start_busy_run_once', 'ottoq_release_unusable_reservations',
                                 'ottoq_fit_charge_fault_model', 'ottoq_record_event', 'ottoq_emit_sdr',
                                 'ottoq_generate_audit_bundle', 'ottoq_complete_audit_report', 'ottoq_probe_task_completion'])
     AND (has_function_privilege('authenticated', f.oid, 'EXECUTE') OR has_function_privilege('anon', f.oid, 'EXECUTE'))
   GROUP BY 1, 2)
SELECT count(*) AS doors, count(*) FILTER (WHERE d = 1) AS direct,
       count(*) FILTER (WHERE has_function_privilege('anon', oid, 'EXECUTE')) AS anon_doors,
       string_agg(fn, ', ' ORDER BY fn) AS doors_list,
       has_column_privilege('authenticated', 'public.ottoq_events', 'signature', 'SELECT') AS authenticated_reads_signatures
  FROM door;
