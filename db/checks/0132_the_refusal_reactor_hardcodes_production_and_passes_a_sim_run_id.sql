-- ---------------------------------------------------------------------------
-- 0132 — 71,944 events say `data_source = 'production'` AND carry a sim run id.
--        A row cannot be both. This one is not a GUC accident like 0131; it is
--        a hardcoded literal, two lines apart from the run id it contradicts.
--
-- Found 2026-09-08 12:25 UTC by widening 0131's question from one event type to
-- all of them. 0131 asked "what did the fleet reset write"; this asks "what is
-- labelled production in this database, and is any of it production".
-- ---------------------------------------------------------------------------

-- Q1. THE WHOLE PRODUCTION-LABELLED POPULATION, by what wrote it:
--
--      event_type                  ingest_source     rows   batches   last seen
--      ottoq.refusal_escalated     production      71,944       251   12:13:00
--      vehicle.state_changed       trigger         26,856       246   12:13:00
--      stall.created               trigger             10         1   09-03
--      stall.state_changed         trigger             10         1   09-03
--      recall_refused              app                  6         1   07:03
--      vehicle.created             trigger              4         1   09-03
--      production.session_stopped  engine               2         2   08-30
--      production.session_started  engine               2         2   08-30
--
--     Both of the last two timestamps in the top two rows —
--     2026-09-08 12:13:00.150047 — are the transaction-start instant of round
--     26's column c. The entire top of this table is the certification harness.
--
--     Against the whole stream: 2,183,442 rows labelled `twin`, 98,834 labelled
--     `production`. Of those 98,834, the two harness patterns account for
--     98,800. **The production half of this database's signed event stream is
--     99.97% certification harness.**
SELECT event_type, ingest_source, count(*) AS n, count(DISTINCT recorded_at) AS batches,
       max(recorded_at) AT TIME ZONE 'UTC' AS last_seen
FROM public.ottoq_events WHERE data_source='production'
GROUP BY 1,2 ORDER BY 3 DESC;

SELECT data_source, count(*) FROM public.ottoq_events GROUP BY 1 ORDER BY 2 DESC;

-- Q2. THE CONTRADICTION, stated as a count. A row whose data_source is
--     'production' and whose sim_run_id is not null is asserting two
--     incompatible things about its own provenance:
--
--       production-labelled rows carrying a sim run id   71,954
--         of which ottoq.refusal_escalated               71,944
--       distinct sim runs implicated                        494
SELECT count(*) AS production_labelled_with_a_sim_run,
       count(*) FILTER (WHERE event_type='ottoq.refusal_escalated') AS refusal_escalated,
       count(DISTINCT sim_run_id) AS distinct_runs
FROM public.ottoq_events WHERE data_source='production' AND sim_run_id IS NOT NULL;

-- Q3. THE LINE. ottoq.ottoq_react_to_refusals, both escalation branches:
--
--       PERFORM ottoq_record_event(
--         p_actor_type:='ottoq_engine', p_actor_id:='refusal_reactor',
--         p_event_type:='ottoq.refusal_escalated', …
--         p_ingest_source:='production', p_data_source:='production',
--         p_sim_run_id:=p_sim_run_id);
--
--     `p_data_source:='production'` and `p_sim_run_id:=p_sim_run_id` on
--     consecutive lines. Compare the state-change triggers, which get it right:
--
--       p_data_source := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END
--
--     Note also `EXCEPTION WHEN OTHERS THEN NULL` around both writes: an audit
--     record whose failure is swallowed in silence. Recorded, not fixed here.

-- Q4. THE CENSUS. Twelve hardcoded 'production' writes across ten functions,
--     against seven conditional ones across three:
--
--       hardcoded                                   conditional (CASE on run)
--       ottoq.ottoq_react_to_refusals          2    ottoq_evaluate_rule_core     3
--       ottoq_ingest_service_complete          2    ottoq_stalls_state_change    2
--       ottoq_ack_vehicle_command              1    ottoq_vehicles_state_change  2
--       ottoq_hw_recall_vehicle                1
--       ottoq_hw_set_return_threshold          1
--       ottoq_hw_vehicle_status                1
--       ottoq_production_start                 1
--       ottoq_production_stop                  1
--       ottoq_trg_attribution_attach           1
--       twin.ottoq_report_charger_fault        1
--
--     Some hardcodes are honest: ottoq_production_start / _stop only ever run
--     on the production path. FOUR ARE THE SAME DEFECT AS THE REFUSAL REACTOR —
--     'production' hardcoded on one line, a sim run id passed on another:
--
--       function                        event_type                          run argument
--       ottoq_trg_attribution_attach    sdr_costs_attached                  NULL (hardcoded too)
--       ottoq_ingest_service_complete   ops.services_completed_reported     v_run.sim_run_id
--       ottoq_ingest_service_complete   ops.service_marked_complete         v_run.sim_run_id
--       ottoq_ack_vehicle_command       vehicle.command_ack                 v_cmd.sim_run_id
--       twin.ottoq_report_charger_fault ops.charger_fault_confirmed         v_run
--
--     AND ALL FIVE EVENT TYPES RETURN ZERO ROWS TODAY. Stated with the
--     qualification 0131 Q5 had to add about itself: ottoq_events is purged
--     nightly, so "zero rows now" is a statement about the CURRENT RETENTION
--     WINDOW, not about all time. These paths may have fired before the window
--     and left nothing behind. What the zero does establish is that they are
--     not firing NOW — latent rather than bleeding, the same shape as G20,
--     where the second SDR emitter would have billed a DCFC charge at the L2
--     tariff and had simply never fired since the trigger was installed.
--
--     That is why 0224 is scoped to the one function with 71,944 rows of
--     evidence and not to all five. It is also why the other four should be
--     fixed BEFORE those paths are woken rather than after: the cost of fixing a
--     latent defect is one line, and the cost of fixing it later includes
--     whatever it wrote in between, which cannot be re-labelled because it is
--     signed.
--
--     twin.ottoq_report_charger_fault deserves a second look on its own terms:
--     a function in the TWIN schema, whose whole job is to inject a simulated
--     fault, labelling its event 'production'.
SELECT event_type, data_source, count(*) AS n,
       count(*) FILTER (WHERE sim_run_id IS NOT NULL) AS with_run
FROM public.ottoq_events
WHERE event_type IN ('sdr_costs_attached','ops.services_completed_reported',
                     'ops.service_marked_complete','vehicle.command_ack',
                     'ops.charger_fault_confirmed')
GROUP BY 1,2 ORDER BY 3 DESC;
--     -> zero rows, 2026-09-08 12:35 UTC
SELECT n.nspname||'.'||p.proname AS fn,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'data_source[^,;\n]{0,12}''production''', 'g')) AS hardcoded,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'data_source[^,;\n]{0,20}CASE', 'gi')) AS conditional
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','twin','ottoq')
  AND (p.prosrc ~ 'data_source[^,;\n]{0,12}''production''' OR p.prosrc ~* 'data_source[^,;\n]{0,20}CASE')
ORDER BY 2 DESC, 1;

-- Q5. THE FIX IS ONE EXPRESSION, AND IT IS PROVABLY HASH-NEUTRAL.
--
--     Replace the two literals with the expression the state-change triggers
--     already use. Why no atom can move: h_evt hashes THIS, from the live body
--     of ottoq_determinism_pair —
--
--       md5(string_agg(
--         event_type||'|'||
--         CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
--              THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||
--         COALESCE(e.sim_clock_at::text,'-'),
--         E'\n' ORDER BY event_type, …, e.sim_clock_at))
--       FROM ottoq_events e WHERE e.sim_run_id = v_run
--
--     — event_type, entity_id and sim_clock_at. **data_source is not in the
--     hashed content and not in the ORDER BY.** The row set is selected by
--     sim_run_id, which the fix does not touch. So the change is invisible to
--     h_evt by construction, not by hope, and forces_recert is FALSE with a
--     reason rather than an assurance.
SELECT substr(p.prosrc, GREATEST(1, position('h_evt' in p.prosrc)), 520) AS h_evt_expression
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';

-- Q6. WHAT NOT TO CHANGE, and this one was measured rather than assumed.
--     The same two call sites also hardcode `p_ingest_source:='production'`,
--     which is equally untrue — the writer is the engine. Leave it, but for the
--     right reason.
--
--     THE WRONG REASON, recorded because I nearly shipped it. The first draft of
--     this section said two functions BRANCH on ingest_source —
--     public.ottoq_emit_sdr and public.ottoq_trg_attribution_attach, both on the
--     enforced SDR path — so changing it would be a settlement change in
--     disguise. They do not branch on it. Both merely WRITE
--     `p_ingest_source => 'kernel'`, and my pattern `ingest_source\s*(=|IN|<>)`
--     matched the `=` inside the named-parameter arrow `=>`. Tightened to
--     `\mingest_source\M\s*(=[^>]|IN|<>|!=)` the answer is ZERO. A regex that
--     cannot tell a write from a read is the same instrument that produced the
--     rejected LIMIT-without-ORDER-BY lint in G12, and it produced a
--     confident, wrong justification here too.
--
--     THE RIGHT REASON. ingest_source has no CHECK constraint, and its live
--     vocabulary is eight values including two spellings of one word:
--
--       trigger  1,781,838     ottoq     15,159
--       twin       272,761     otto_q     6,804
--       kernel     130,843     app        2,923
--       production  71,944     engine         4
--
--     'production' appears there ONLY from this one function — 71,944, exactly
--     the refusal_escalated count — and 'engine' has four rows in the whole
--     database. Choosing the correct value is a vocabulary decision on an
--     unconstrained column, which is the shape of G17 (KPI-4's actor vocabulary,
--     closed by pinning a table to the live CHECK), not a typo fix. It gets its
--     own work, not a smuggled line in someone else's migration.
--
--     data_source is the opposite case on every axis: it HAS a CHECK
--     ('production','twin','replay','shadow'), CLAUDE.md 2.8 names it as the
--     separator between twin and real telemetry, and it is equally unbranched-on
--     — so the fix is both well-defined and inert downstream.
--
--     By contrast, nothing branches on ottoq_events.data_source at all. A naive
--     grep turns up three functions; run down individually:
--
--       ottoq_emit_sdr                 WRITES data_source, does not branch on it
--       ottoq_trg_attribution_attach   WRITES `p_data_source => 'production',
--                                      p_sim_run_id => NULL` — itself a hardcode
--                                      worth its own look, not a read
--       ottoq_hw_vehicle_status        genuinely reads `data_source = 'production'`
--                                      — but from ottoq_telemetry_packets, a
--                                      DIFFERENT TABLE
--
--     So the count of things that branch on ottoq_events.data_source is zero,
--     and the count that branch on ingest_source is two, both on the enforced
--     settlement path. That asymmetry is the whole reason one of these two
--     one-word fixes is safe today and the other is not — and 0224's P2 guard
--     is scoped to functions that mention ottoq_events precisely so it does not
--     fire on the telemetry-packets reader and get ignored.
-- the tightened form: (=[^>]) excludes the named-parameter arrow, which is what
-- made the loose version report writers as readers. Returns zero rows.
SELECT n.nspname||'.'||p.proname AS branches_on_ingest_source
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','twin','ottoq')
  AND p.prosrc ~* '\mingest_source\M\s*(=[^>]|IN|<>|!=)'
ORDER BY 1;

-- and the vocabulary itself, which is the reason not to touch it here
SELECT ingest_source, count(*) AS n FROM public.ottoq_events GROUP BY 1 ORDER BY 2 DESC;
