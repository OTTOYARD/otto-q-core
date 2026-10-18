-- 0455  **At a depot a real feed drives, the twin's simulated technician answers OTTO-Q's top-off and green-light
--        questions, and enacts the top-offs it approves.** -> G465, fixed by db/migrations/0751.
--        Found while reading the production seam for G464's last gap (ottoq_ingest_service_complete): the twin's
--        completion raises a technician green-light, and before copying that into the production seam the question was
--        who answers a green-light in production. Read-only, against gxdrcyphqjzjsuhxuqtg, 2026-10-18 between 12:37 and
--        12:55 AM CT (05:37 and 05:55 UTC), bounded by clock reads, inside the sweep window (catalog reads and three
--        small table reads only). Every claim names its query.
--
-- ══ §1 WHAT THE SCAN DOES (reproduce: (1)) ═══════════════════════════════════════════════════════════════════════════════
--
--   twin.ottoq_opportunistic_scan (prosrc md5 fce0e060, 6,526 characters) first asks OTTO-Q's planner for new top-off
--   questions (ottoq.ottoq_plan_opportunistic_charges), then, in a loop headed "TWIN: the simulated tech verdict", takes
--   every pending opportunistic_charge and tech_greenlight question at the run's depot whose decide_after has passed and
--   whose expires_at has not, and decides it: COALESCE(the crew's recorded verdict = 'approved',
--   ottoq_sim_seeded_random(seed, 'techdecide:' || car || type || requested_at) < p), with p 0.70 for a top-off and 0.92
--   for a green-light (ottoq_feed_plan('service_manifest') sets neither key, so these are the scan's own fallbacks).
--   decided_by is 'operator:<who>' for a recorded verdict and 'twin_tech_sim' otherwise. An approved top-off is enacted:
--   the car is set to staged_awaiting_service, ottoq.ottoq_enact_opportunistic_charge runs, and the charger it names is
--   claimed. The body never names a feed mode, (1).
--
-- ══ §2 WHO CALLS IT, AND WHEN (reproduce: (2)) ═══════════════════════════════════════════════════════════════════════════
--
--   Two callers, both tick paths, and both call it unconditionally, (2):
--     twin.ottoq_world_advance (md5 361c6d44), the production_live tick: in its "PRE-TELEMETRY ORCHESTRATION" block,
--       between ottoq_sim_advance_visit_atoms and ottoq_sim_advance_flow_contract, before its first IF v_feed_sim. The
--       twin's fabricators it calls (prearrival contracts, the confirm walk, the arm, charge sessions, energy, telemetry,
--       wear, heartbeats, charger recovery, arrival manifests, the exception and bay-fault handlers) sit inside
--       IF v_feed_sim blocks. Of the twin functions it calls outside them, the visit atoms, the service flow and the wash
--       triage each read the depot's feed mode and gate their own simulated parts, and the flow contract is
--       feed-agnostic by design (it completes a charge on the car's real state of charge). The scan has no gate at all.
--     public.ottoq_sim_advance_tick_world, the demo and certification path: likewise, beside the visit atoms.
--   The cutover receipt of 2026-07-23 (ottoyard-agent-context/memory/project_realdata_ingestion_seam.md) lists what
--   external mode switches off: "telemetry, charge sessions, site energy, wear, heartbeats, charger auto-recovery,
--   prearrival + arrival-manifest generation, confirm_commands ACK-sim, mock EMS energy_controller, fault injectors",
--   and later the visit atoms' timer completions and triage dice. The simulated technician is not on it.
--
-- ══ §3 WHICH QUESTIONS IT WOULD ANSWER IN PRODUCTION (reproduce: (3)) ══════════════════════════════════════════════════
--
--   Four functions insert into ottoq_ops_approvals, (3). Two raise the scan's two kinds:
--     ottoq.ottoq_plan_opportunistic_charges (OTTO-Q's half; the scan calls it every tick, in both modes): every top-off
--       question, with decide_after the clock plus 2-4 minutes (a seeded draw, the twin's technician response time) and
--       expires_at the clock plus 35 minutes. These are exactly the rows the draw selects, so in production the draw
--       would answer every top-off question and enact the approved ones.
--     twin.ottoq_sim_advance_visit_atoms raises a green-light after a completed atom that requires one, inside its
--       sim-only completion branch (it carries the feed gate); ottoq.ottoq_stage_advance_approval raises one pending only
--       when tech_approvals_required is set, and names neither decide_after nor expires_at, both NULL by the table's
--       definition, so the draw's filter never selects it. So today no production green-light reaches the draw. A
--       green-light raised at the production seam with both times set, as the twin's completion raises one, would.
--   The fourth, public.ottoq_indepot_reassignment_guard, raises indepot_reassign questions, which OTTO-Q's own decider
--   answers (public.ottoq_decide_indepot_approvals); the scan's cursor excludes them by type (0002).
--   The crew's door, public.ottoq_ops_approval_decide (md5 5edd194c, 0487), records a verdict on the row
--   (payload.operator_verdict: verdict, by 'pulse', uid, note) and leaves the row pending; the scan applies it on the
--   next tick. So in production the scan must keep running: it is the only applier of a person's verdict.
--
-- ══ §4 NOT LIVE (reproduce: (4)) ═════════════════════════════════════════════════════════════════════════════════════════
--
--   No cron job calls twin.ottoq_world_advance; no production_live run is running (nine on record, all completed, eight of
--   them at the twin depot in sim mode, the ninth at the retired P2 fixture); two depots are in external mode, the
--   one-stall OTTOYARD Hardware Lab and the retired P2 Ledger-Only Proof Rig; and the table holds no top-off or
--   green-light question at either. Nothing has been answered this way. The defect is the day of the cutover.
--
-- ══ §5 THE FIX AND WHAT IT LEAVES (0751) ══════════════════════════════════════════════════════════════════════════════
--
--   0751 has the scan read its depot's feed mode and pass over, at a depot the twin does not feed, any question no person
--   answered. A recorded verdict is applied as before, and the expiry sweep still lapses an unanswered question at its
--   expires_at. Executed on the scratch PostgreSQL against the live body (tests/test_production_technician_sql.py, 8
--   tests): unpatched, an externally fed depot's green-light comes back "approved by twin_tech_sim"; patched, it stays
--   pending, and a person's verdict is applied in their name.
--   Left as it is, and named in G465: the planner's seeded 2-4 minute decide_after, which in production only delays when
--   a person's verdict is applied; and the crew door's event, which records data_source 'twin' whatever the depot.

-- (1) the scan never names a feed mode, draws the verdict, signs it twin_tech_sim and enacts a top-off
SELECT md5(p.prosrc) AS md5, length(p.prosrc) AS len,
       p.prosrc ~ 'feed_mode' AS reads_feed_mode,
       p.prosrc ~ 'ottoq_sim_seeded_random\(v_seed, ''techdecide:''' AS draws_the_verdict,
       p.prosrc ~ '''twin_tech_sim''' AS signs_twin_tech_sim,
       p.prosrc ~ 'ottoq_enact_opportunistic_charge' AS enacts_the_top_off
  FROM pg_proc p
 WHERE p.oid = 'twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure;

-- (2) who calls it, with the text around each call
WITH f AS (
  SELECT n.nspname || '.' || p.proname AS fn, md5(p.prosrc) AS md5, p.prosrc AS d
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ 'ottoq_opportunistic_scan'
     AND p.proname <> 'ottoq_opportunistic_scan')
SELECT fn, md5, (regexp_matches(d, '.{0,250}ottoq_opportunistic_scan.{0,120}', 'g'))[1] AS around_the_call
  FROM f ORDER BY fn;

-- (3) who raises questions, of which kind, with which times
SELECT n.nspname || '.' || p.proname AS fn,
       p.prosrc ~ '''opportunistic_charge''' AS raises_top_off, p.prosrc ~ '''tech_greenlight''' AS raises_green_light,
       p.prosrc ~ 'decide_after' AS names_decide_after, p.prosrc ~ 'expires_at' AS names_expires_at,
       p.prosrc ~ 'v_feed_sim' AS has_a_feed_gate
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~* 'insert\s+into\s+(public\.)?ottoq_ops_approvals'
 ORDER BY 1;

-- (4) production is not live
SELECT 'cron calling world_advance' AS k, count(*)::text AS v FROM cron.job WHERE command ILIKE '%world_advance%'
UNION ALL
SELECT 'production_live runs: ' || r.status || ' / ' || COALESCE(d.feed_mode, '?'), count(*)::text
  FROM public.ottoq_sim_runs r LEFT JOIN public.depots d ON d.id = r.depot_id
 WHERE r.run_by = 'production_live' GROUP BY r.status, d.feed_mode
UNION ALL
SELECT 'external depot: ' || COALESCE(d.name, d.id::text),
       (SELECT count(*) FROM public.stalls s WHERE s.depot_id = d.id)::text || ' stalls'
  FROM public.depots d WHERE d.feed_mode = 'external'
UNION ALL
SELECT 'questions at an external depot: ' || a.approval_type || ' / ' || a.status, count(*)::text
  FROM public.ottoq_ops_approvals a JOIN public.depots d ON d.id = a.depot_id
 WHERE d.feed_mode = 'external' GROUP BY a.approval_type, a.status;
