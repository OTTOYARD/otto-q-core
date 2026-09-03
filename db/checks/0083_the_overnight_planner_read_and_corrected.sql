-- 0083  The overnight planner: read, corrected, and what is still unproven.
--       Written 9:55 PM CT, 2026-09-02.
--
-- Chase ratified the overnight model tonight: vehicles return home nightly for
-- charge, cleaning, inspection and service; non-urgent work queues for that
-- window unless needed sooner or a daytime reservation is free. He delegated
-- the deterministic-vs-agentic placement, answered in docs/DECISION_BOUNDARY.md.
--
-- Before building anything new, CLAUDE.md 5 requires checking what exists. It
-- turned out most of it does.
--
--
-- §1  The machinery exists; the planner was orphaned
-- ---------------------------------------------------
--   ottoq_is_depot_night               live, 2 callers
--   ottoq_is_overnight_holdout         live, 2 callers
--   twin.ottoq_sim_overnight_service_drain  live, 2 callers
--   service_cadence_policy             15 rows
--   ottoq_plan_overnight_wave          ZERO callers
--   ottoq_wave_plan                    ZERO rows
--   TW.002.overnight_staging rule      active, evaluator exists, ZERO evaluations
--
-- The night predicate is wired and the twin drains overnight, but the planner
-- that would schedule the wave is dead code and the rule that would encode the
-- policy has never run. Chase's model is the architecture on paper; the piece
-- that acts on it is disconnected.
--
--
-- §2  It is a real planner, not a stub - read before judging
-- ----------------------------------------------------------
-- Earliest-deadline-first over vehicles below target, L2 PREFERRED so scarce
-- DCFC is saved for assets that genuinely need it, slot-based capacity
-- reservation across the window, and vehicles that cannot be fitted are RECORDED
-- as stranded with reason 'no_charger_block_meets_deadline' rather than dropped.
-- It returns a peak-concurrent-chargers figure as a CapEx signal.
--
-- That is good design and it matches what Chase described. Its own comments call
-- the per-vehicle deploy time a "founder-ratify item" - it was written as a draft
-- awaiting exactly the ratification it got tonight.
--
--
-- §3  Three defects, fixed in 0173 while it is still safe to
-- -----------------------------------------------------------
-- The safety argument is the interesting part: a function with ZERO callers
-- cannot participate in a run, so it cannot move a canon. forces_recert=false is
-- therefore CHECKABLE rather than asserted, and 0173's header carries the query
-- to re-check it. Re-verified immediately before applying: 0 callers.
--
--  a. NASHVILLE HARDCODED. The deadline was computed in a literal
--     'America/Chicago' inside a kernel CLAUDE.md 2.2 requires to be
--     site-agnostic. Both depots ARE America/Chicago, which is exactly why it
--     survived - a constant matching every row of your data is invisible until a
--     second timezone exists. Now reads depots.operating_timezone.
--
--  b. THE 5AM DEPLOY HOUR was a magic number in a 5h/29h interval branch. Both
--     depots run 00:00-23:59, so it cannot be derived from their hours - it is a
--     genuine policy choice. Now the policy param overnight_deploy_hour_local at
--     its current value of 5. Same treatment 0159 gave wait-vs-slower-charger.
--
--  c. A WALL-CLOCK FALLBACK. COALESCE(sim_clock_current, now()) would silently
--     plan against real time. That is precisely today's 0172 defect in another
--     column, and it hid there for the same reason. A planner with no clock now
--     REFUSES: {"ok": false, "reason": "run_has_no_sim_clock"}.
--
-- EDF ordering, L2-first preference, slot arithmetic, stranded accounting and
-- the returned CapEx signal are byte-for-byte unchanged.
--
--
-- §4  What is proven, and what is NOT
-- ------------------------------------
-- PROVEN by executing it against run 1773 (the 48-tick pair):
--   * it runs at all - this function had never been executed before tonight
--   * timezone comes from the depot: "timezone": "America/Chicago" resolved,
--     not literal
--   * the policy param is honoured: deploy_hour_local 5, deadline
--     2026-09-02T10:00Z = 5:00 AM CT
--   * resources read correctly: 10 DCFC, 30 L2 at the flagship
--   * it returned planned 0, stranded 0 - and that is CORRECT, not a filter bug:
--     all 116 flagship vehicles are 'offline', the post-run resting state, so
--     the worklist is genuinely empty. Verified independently rather than
--     assumed, because a planner that returns zero for everything looks
--     identical to one that works.
--
-- NOT PROVEN, and this is the honest limit:
--   * that it plans CORRECTLY on a live fleet. Every observation above comes
--     from an idle post-run world. The EDF ordering, the L2-before-DCFC
--     preference and the slot reservation have not been exercised on vehicles
--     that actually need charge.
--
-- That test needs the planner called DURING a tick, which is the wiring work,
-- which is an engine change and its own forces_recert round. Do not treat "it
-- ran and returned ok" as evidence that it schedules well. It is evidence that
-- it no longer has Nashville baked in.
--
--
-- §5  What wiring it will require
-- --------------------------------
--  1. A consumer. ottoq_wave_plan is written by nothing and read by nothing.
--     A plan no one honours is a second opinion, not orchestration.
--  2. A decision about precedence when the plan and the live decide path
--     disagree. By docs/DECISION_BOUNDARY.md the deterministic path disposes,
--     so the wave plan is an INPUT to seating, never an override of it.
--  3. TW.002.overnight_staging needs its action announced before it can fire
--     (docs/DECISION_BOUNDARY.md, the rules-layer finding).
--  4. A certification round: it changes what the engine decides, so h_bkg moves
--     and every canon in db/canons/round8.md must be re-taken deliberately.
--
--
-- §6  Queries
-- ------------

-- 6.1 the zero-caller check 0173's safety classification rests on (expect 0)
SELECT count(*) AS callers_of_planner
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.prokind='f' AND n.nspname IN ('public','twin')
   AND p.proname <> 'ottoq_plan_overnight_wave'
   AND pg_get_functiondef(p.oid) ILIKE '%ottoq_plan_overnight_wave%';

-- 6.2 run the planner and read its resolved timezone / deploy hour
SELECT jsonb_pretty(public.ottoq_plan_overnight_wave(
  (SELECT sim_run_id FROM ottoq_sim_runs ORDER BY sim_run_seq DESC LIMIT 1)));

-- 6.3 why planned=0 is correct on an idle fleet - check before calling it a bug
SELECT count(*) AS total_autonomous,
       count(*) FILTER (WHERE v.current_state::text IN ('deployed','en_route_to_depot',
             'arrived_at_gate','staged_awaiting_service','charge_complete_holding')) AS in_qualifying_state,
       count(*) FILTER (WHERE v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 2) AS below_target,
       string_agg(DISTINCT v.current_state::text, ', ') AS states_present
  FROM vehicles v
 WHERE v.home_depot_id='11111111-1111-1111-1111-111111111111' AND v.category='autonomous';
