-- migration-version: 20260914124522
-- migration-name:    0304_five_more_floors_and_six_dials_admitted_without_a_clamp
--
-- 0304  FIVE MORE FLOORS, AND SIX DIALS ADMITTED WITHOUT A CLAMP
--
-- The last eleven. 92 -> 0.
--
-- db/checks/0228 grouped the twelve survivors A-E and said they were "not
-- waiting on more reading." That was wrong about three of them, and the reason
-- is worth stating plainly: 0228 grouped them by reading the READ SITE and
-- stopping there. Three of the twelve have their bound one line further out --
-- in the expression that ENCLOSES the read, or in the function that WRITES the
-- value the read is compared against. Reading one line further changed the
-- answer for five dials.
--
-- 0303 closed (E). This file closes the rest, in two halves.
--
-- ===========================================================================
-- HALF ONE: FIVE DIALS WHOSE BOUND WAS ONE LINE OUTSIDE THE READ
--
-- ---------------------------------------------------------------------------
-- 1-2.  staging_hold_default_min   min 1  no ceiling  dflt 30
--       staging_hold_max_min       min 1  no ceiling  dflt 480
--
-- 0228 filed both under "BOTH SIGNS ARE MEANINGFUL -- negative is a hold that
-- has already expired." It cannot be. public.ottoq_decide_tick:
--
--     v_stage_until := GREATEST(
--       LEAST(
--         COALESCE(v_stage_until,
--                  v_clock + make_interval(mins => ottoq_policy_get(...,'staging_hold_default_min',30)::int)),
--         v_clock + make_interval(mins => ottoq_policy_get(...,'staging_hold_max_min',480)::int)),
--       v_clock + interval '1 minute');
--
-- 0228 quoted the make_interval line. It did not quote the GREATEST that
-- encloses it. That GREATEST floors the RESULT at v_clock + 1 minute, so no
-- value of either dial can produce a hold that has already expired: every
-- value at or below 1 collapses onto a one-minute staging hold. min 1 -- not
-- 0 -- because 1 is the smallest value that is distinguishable from the floor.
--
-- This is derivation 4 from 0228 section B, "a clamp on the RESULT one line
-- later," which 0228 had already named and then failed to apply here.
--
-- Neither has a ceiling. staging_hold_max_min IS the ceiling; and a default
-- above it is made inert by the LEAST, but that is a relation between two
-- dials, not a fixed bound -- the same thing 0300 recorded for the two deploy
-- gates and G61's second class. Written into both descriptions.
--
-- ---------------------------------------------------------------------------
-- 3-4.  indepot_defer_max_min            min 0  no ceiling  dflt 45
--       indepot_defer_max_min_critical   min 0  no ceiling  dflt 10
--
-- 0228 filed these under "THE ONLY CATALOGUED SIBLING'S BOUND IS ITS AUTHOR'S
-- CHOICE" and said "the comparison that consumes v_budget has not been read."
-- It has now. twin.ottoq_sim_vehicle_exception_handler:
--
--     ELSIF (v_rec.config->'exception'->>'flagged_at')::timestamptz
--             <= p_sim_clock - (v_budget || ' minutes')::interval THEN
--
-- and the writer of flagged_at is THE SAME FUNCTION, twice:
--
--     jsonb_build_object('type','vehicle_fault','severity',v_sev,'flagged_at',p_sim_clock, ...
--
-- So flagged_at is stamped from p_sim_clock and read at a later p_sim_clock:
-- flagged_at <= p_sim_clock holds BY CONSTRUCTION, not by sampling. Therefore
-- any budget <= 0 makes the predicate unconditionally true and the defer
-- budget expires on the first evaluation. Every value <= 0 is one behaviour;
-- 0 is the smallest that says anything.
--
-- I checked this against live rows first and the check was WRONG: 2 of 23
-- vehicles carry a flagged_at LATER than now(), which looks like a violation
-- and is not one -- flagged_at is SIM time and now() is wall time. The comment
-- at line 351 of the same function says so explicitly. A data sample compared
-- against the wrong clock would have refuted a true premise; the writer proves
-- it outright. Recording the wrong check because the class of error -- a probe
-- answering a slightly different question than the one asked -- is the one
-- that has cost this build the most.
--
-- Neither gets the immobilizing sibling's 10..720. 0228 was right about that:
-- 720 is reasoning ABOUT the engine, and copying the 10 would forbid a
-- five-minute critical budget while the critical arm's own default IS 10.
--
-- ---------------------------------------------------------------------------
-- 5.  l2_overflow_penalty   min 0  no ceiling  dflt 100
--
-- 0228 filed this under "NOT A SCALAR BOUND AT ALL ... a min/max pair is the
-- wrong shape for it." Half right. public.ottoq_l2_optimize_assignments:
--
--     ORDER BY
--       ( CASE WHEN s.stall_type = 'dcfc' THEN 0
--              ELSE ottoq_policy_get(p_sim_run_id, 'l2_overflow_penalty', 100) END )
--       + COALESCE(s.distance_from_entrance, 50) * 0.1
--     ASC,
--
-- Lower score wins, and the comment above it states the intent: "L2 carries a
-- penalty large enough that no amount of distance advantage can outbid a free
-- fast plug."
--
--   * A NEGATIVE penalty makes an L2 stall beat a DCFC stall at equal
--     distance. That INVERTS the documented ordering -- 0290's derivation
--     exactly -- so min 0. At 0 the two types rank on distance alone, which is
--     a real setting ("no DCFC preference"), not an error.
--   * The CEILING is where 0228 was right. Measured today, stalls.
--     distance_from_entrance spans 0..368, so the distance term spans 0..36.8
--     and any penalty at or above 36.8 is fully dominant -- every larger value
--     behaves identically. But that collapse point is derived from MUTABLE
--     DEPOT DATA, not from a constraint or from code, and it sits BELOW the
--     caller default of 100. Pinning max 36.8 would silently clamp a caller
--     asking for the code's own default and report clamped=true for a write
--     that changes nothing. No ceiling; the collapse point goes in the
--     description, where it is information rather than a trap.
--
-- ===========================================================================
-- HALF TWO: SIX DIALS ADMITTED WITHOUT A CLAMP -- min NULL, max NULL
--
--   timer_backstop_min           dflt = timer_backstop_ticks * 30
--   timer_backstop_ticks         dflt 48
--   contention_wait_cap_min      dflt = contention_wait_cap_ticks * 30
--   contention_wait_cap_ticks    dflt 4
--   overnight_recall_hysteresis  dflt 2
--   service_hold_patience_min    dflt 120
--
-- For these six 0228's finding stands, re-verified: the consumer does
-- something real and distinguishable with a negative.
--
--   timer_backstop_min       p_sim_clock_now >= scheduled_return_at +
--                            (v_backstop_ticks || ' minutes')::interval
--                            -- negative fires BEFORE the scheduled return.
--                            No enclosing clamp; I looked this time.
--   overnight_recall_hysteresis
--                            GREATEST(0, deployed - desired - v_hyst)
--                            -- the GREATEST floors the RESULT, but a negative
--                            hysteresis still recalls MORE than the surplus,
--                            which is a different fleet count, not a collapse.
--   service_hold_patience_min
--                            COALESCE(v_wait_min,0) <= v_patience
--                            -- the COALESCE makes 0 reachable, so patience 0
--                            (hold a zero-length wait) and patience -1 (never
--                            hold) differ.
--   contention_wait_cap_min  LEAST(v_wait_ticks * 30.0, v_wait_cap) <= v_max_wait_min.
--                            v_wait_ticks >= 0 by its own CASE, so a negative
--                            cap collapses ONLY IF v_max_wait_min >= 0.
--                            v_max_wait_min reads ottoq_fleet_operator_slas.
--                            max_queue_wait_minutes, and MEASURED TODAY that
--                            column carries NO CHECK CONSTRAINT -- all four
--                            live rows hold 30, but 30 is data and data moves.
--                            A bound resting on today's rows is the 0098
--                            mistake. Unbounded, stated as unbounded.
--   the two _ticks siblings  supply the CALLER DEFAULT of their _min sibling
--                            as get(..._ticks, N) * 30, so they take effect
--                            only when the _min dial has no row. Their range
--                            is their sibling's divided by 30, and their
--                            sibling is unbounded.
--
-- THE CONVENTION, AND WHY IT IS NOT A SHRUG
--
-- ottoq_policy_set REFUSES any key absent from the catalog -- {"ok":false,
-- "error":"unknown_param"}. So the catalog has two jobs that have been
-- conflated: it is the ALLOW-LIST (a key in it can be written) and it is the
-- CLAMP (how far). Leaving a dial out because no bound can be READ silently
-- converts "I have no bound" into "this must never be written," which is a
-- different and larger claim, and the one that actually costs something: it
-- makes the dial invisible to the agent layer.
--
-- The clamp is GREATEST(v_min, LEAST(v_max, value)) and LEAST/GREATEST IGNORE
-- NULLS, so a row with min_value NULL and max_value NULL admits the key and
-- clamps nothing. 0228 flagged that nothing established this convention --
-- none of the then-148 rows had a NULL min_value. 0303 made the first one
-- (metres_per_plan_unit, NULL/NULL inclusive with an exclusive floor). These
-- six make it a stated convention rather than an accident, every description
-- opens with "UNBOUNDED BY DESIGN" so no reader mistakes one for an
-- unfinished row, and A3 proves the admit-without-clamp behaviour at both
-- extremes instead of asserting it.
--
-- What is NOT claimed: that these six are safe to set to anything. They are
-- admitted, not blessed. An unbounded dial is a dial whose safety lives in the
-- caller, and that is a real gap -- tracked as G61's third class, alongside
-- the two-dial invariants 0300 recorded.
--
-- ===========================================================================
-- EXPECTED EFFECT, PREDICTED BEFORE APPLYING
--   ottoq_policy_param_catalog rows              149 -> 160
--   ottoq_policy_catalog_gap, read_uncatalogued   11 ->   0
--   catalogued_unread                              8 ->   8  (untouched)
--   every existing key's clamp                    unchanged
--   live values violating a new bound                 0  (P4 proves it first)
--   recert floor                                  UNMOVED
--
-- forces_recert = FALSE. This file inserts catalog rows and changes no
-- function. ottoq_policy_get never reads the catalog (P1 re-proves it), so no
-- value any tick observes can move.
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0304 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0304 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0304 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0304 P-: nothing in flight';
END $inflight$;

-- P0. THE ELEVEN ARE STILL THE ELEVEN. -------------------------------------
DO $p0$
DECLARE v_gap int; v_cat int; v_missing text;
BEGIN
  SELECT count(*) INTO v_gap FROM public.ottoq_policy_catalog_gap
   WHERE status = 'read_uncatalogued';
  IF v_gap <> 11 THEN
    RAISE EXCEPTION '0304 P0: gap is %, this file was written against 11', v_gap;
  END IF;
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog;
  IF v_cat <> 149 THEN
    RAISE EXCEPTION '0304 P0: catalog holds % rows, this file was written against 149', v_cat;
  END IF;
  SELECT string_agg(k, ', ' ORDER BY k) INTO v_missing
    FROM unnest(ARRAY['staging_hold_default_min','staging_hold_max_min',
                      'indepot_defer_max_min','indepot_defer_max_min_critical',
                      'l2_overflow_penalty','timer_backstop_min','timer_backstop_ticks',
                      'contention_wait_cap_min','contention_wait_cap_ticks',
                      'overnight_recall_hysteresis','service_hold_patience_min']) AS k
   WHERE k NOT IN (SELECT param_key FROM public.ottoq_policy_catalog_gap
                    WHERE status = 'read_uncatalogued');
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0304 P0: these are not in the gap any more (%); the eleven moved', v_missing;
  END IF;
  RAISE NOTICE '0304 P0: catalog 149, gap 11, and all eleven named keys are in it';
END $p0$;

-- P1. ottoq_policy_get STILL IGNORES THE CATALOG. The forces_recert=false
-- argument for every catalog file, re-executed rather than inherited.
DO $p1$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get'
     AND p.prosrc ~ 'ottoq_policy_param_catalog';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0304 P1: ottoq_policy_get now reads the catalog; forces_recert=false is void';
  END IF;
  RAISE NOTICE '0304 P1: ottoq_policy_get still ignores the catalog';
END $p1$;

-- P2. THE STAGING CLAMP ENCLOSES BOTH READS. This is the whole derivation for
-- dials 1-2 and the exact thing 0228 failed to look at. Pinned by ORDER and by
-- ADJACENCY, so neither a second GREATEST nor the second occurrence of the
-- one-minute literal elsewhere in the function can satisfy it by accident.
DO $p2$
DECLARE v_src text; p_g int; p_d int; p_m int; p_f int; v_n int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_decide_tick';
  IF v_src IS NULL THEN RAISE EXCEPTION '0304 P2: ottoq_decide_tick does not exist'; END IF;

  p_g := position('v_stage_until := GREATEST(' in v_src);
  p_d := position('''staging_hold_default_min'',30)::int))' in v_src);
  p_m := position('''staging_hold_max_min'',480)::int))' in v_src);
  p_f := position('v_clock + interval ''1 minute'');' in v_src);
  IF p_g = 0 OR p_d = 0 OR p_m = 0 OR p_f = 0 THEN
    RAISE EXCEPTION '0304 P2: staging pin missing (greatest=% default=% max=% floor=%)',
                    p_g, p_d, p_m, p_f;
  END IF;
  IF NOT (p_g < p_d AND p_d < p_m AND p_m < p_f) THEN
    RAISE EXCEPTION '0304 P2: staging reads are no longer between the GREATEST and its '
                    'one-minute floor (greatest=% default=% max=% floor=%)', p_g, p_d, p_m, p_f;
  END IF;
  IF p_f - p_m > 80 THEN
    RAISE EXCEPTION '0304 P2: the one-minute floor is % bytes past the max read -- too far to '
                    'be the same expression; re-read the source', p_f - p_m;
  END IF;

  v_n := (length(v_src) - length(replace(v_src,'v_stage_until := GREATEST(','')))
         / length('v_stage_until := GREATEST(');
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0304 P2: % staging GREATEST sites; the ordering argument assumes one', v_n;
  END IF;
  RAISE NOTICE '0304 P2: both staging reads sit inside the single GREATEST(..., v_clock + 1 minute)';
END $p2$;

-- P3. THE DEFER BUDGET'S PREMISE IS IN THE WRITER, NOT IN THE ROWS.
-- flagged_at is stamped from p_sim_clock by the same function that later
-- compares it to p_sim_clock. Both halves pinned.
DO $p3$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_vehicle_exception_handler';
  IF v_src IS NULL THEN RAISE EXCEPTION '0304 P3: the exception handler does not exist'; END IF;
  IF position('''flagged_at'',p_sim_clock' in v_src) = 0 THEN
    RAISE EXCEPTION '0304 P3: flagged_at is no longer stamped from p_sim_clock; the '
                    'floor of 0 for the two indepot budgets rested on exactly that';
  END IF;
  IF position('<= p_sim_clock - (v_budget || '' minutes'')::interval THEN' in v_src) = 0 THEN
    RAISE EXCEPTION '0304 P3: the defer-budget comparison changed shape';
  END IF;
  IF position('WHEN v_sev=''critical'' THEN v_defer_max_crit' in v_src) = 0 THEN
    RAISE EXCEPTION '0304 P3: the critical arm no longer feeds v_budget';
  END IF;
  RAISE NOTICE '0304 P3: writer stamps flagged_at from p_sim_clock; reader compares to p_sim_clock';
END $p3$;

-- P4. THE L2 ORDERING IS STILL DCFC-ZERO PLUS DISTANCE. The inversion argument
-- for min 0 is an argument about THIS expression.
DO $p4$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_l2_optimize_assignments';
  IF v_src IS NULL THEN RAISE EXCEPTION '0304 P4: ottoq_l2_optimize_assignments does not exist'; END IF;
  IF position('CASE WHEN s.stall_type = ''dcfc'' THEN 0' in v_src) = 0
     OR position('''l2_overflow_penalty'', 100) END )' in v_src) = 0
     OR position('+ COALESCE(s.distance_from_entrance, 50) * 0.1' in v_src) = 0 THEN
    RAISE EXCEPTION '0304 P4: the L2/DCFC sort expression changed; min 0 was derived from it';
  END IF;
  RAISE NOTICE '0304 P4: DCFC scores 0, L2 scores the dial, distance adds 0.1/unit';
END $p4$;

-- P5. THE SIX UNBOUNDED READS ARE STILL THERE. Without this, half two
-- catalogues keys nothing reads.
DO $p5$
DECLARE v_rc text; v_ad text; v_ps text;
BEGIN
  SELECT p.prosrc INTO v_rc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_recall_naive_threshold_v1';
  SELECT p.prosrc INTO v_ad FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_auto_dispatch_tick';
  SELECT p.prosrc INTO v_ps FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_l2_propose_service';
  IF position('''timer_backstop_min'',' in v_rc) = 0
     OR position('''contention_wait_cap_min'',' in v_rc) = 0
     OR position('''timer_backstop_ticks'',48) * 30' in v_rc) = 0
     OR position('''contention_wait_cap_ticks'',4) * 30' in v_rc) = 0 THEN
    RAISE EXCEPTION '0304 P5: a recall-threshold read moved';
  END IF;
  IF position('''overnight_recall_hysteresis'',2)::int' in v_ad) = 0 THEN
    RAISE EXCEPTION '0304 P5: the hysteresis read moved';
  END IF;
  IF position('''service_hold_patience_min'', 120)' in v_ps) = 0 THEN
    RAISE EXCEPTION '0304 P5: the service-hold patience read moved';
  END IF;
  RAISE NOTICE '0304 P5: all six unbounded reads present, both _ticks siblings still nested';
END $p5$;

-- P6. NO LIVE VALUE WOULD BE CLAMPED BY A BOUND THIS FILE INTRODUCES.
-- Only the five floors can bite; the six NULL/NULL rows cannot clamp anything.
DO $p6$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(pp.param_key||'='||pp.param_value||' (scope '||pp.scope_id||')', ', ')
    INTO v_bad
    FROM public.ottoq_policy_params pp
    JOIN (VALUES ('staging_hold_default_min', 1::numeric),
                 ('staging_hold_max_min', 1),
                 ('indepot_defer_max_min', 0),
                 ('indepot_defer_max_min_critical', 0),
                 ('l2_overflow_penalty', 0)) AS f(k, floor_v) ON f.k = pp.param_key
   WHERE pp.param_value < f.floor_v;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0304 P6: live value(s) below a floor this file introduces (%). '
                    'Cataloguing would change what the engine reads. Resolve first.', v_bad;
  END IF;
  RAISE NOTICE '0304 P6: no live value sits below any new floor';
END $p6$;

-- ===========================================================================
-- THE ELEVEN ROWS
-- ===========================================================================

INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, affects)
VALUES
  ('staging_hold_default_min',
   '0304: how long a staging booking is held when the itinerary does not say. '
   'Minutes, sim-domain. FLOOR 1, derived from the enclosing GREATEST in '
   'ottoq_decide_tick -- v_stage_until := GREATEST(LEAST(COALESCE(dflt), max), '
   'v_clock + interval ''1 minute'') -- which floors the RESULT, so every value '
   'at or below 1 is a one-minute hold and they are indistinguishable. No '
   'ceiling: staging_hold_max_min caps it, and a default above that cap is made '
   'inert by the LEAST. THAT IS A RELATION BETWEEN TWO DIALS AND THE CATALOG '
   'CANNOT EXPRESS IT (G61 second class, as 0300 recorded for the deploy gates): '
   'nothing here stops a default larger than the max.',
   30, 1, NULL, 'staging booking duration'),

  ('staging_hold_max_min',
   '0304: the hard cap on a staging booking, so a runaway itinerary cannot '
   'reserve a space indefinitely (the source comment''s own words). Minutes, '
   'sim-domain. FLOOR 1, same enclosing GREATEST as staging_hold_default_min. '
   'No ceiling -- this IS the ceiling. See that dial for the cross-dial '
   'invariant the catalog cannot enforce.',
   480, 1, NULL, 'staging booking duration'),

  ('indepot_defer_max_min',
   '0304: how long a non-critical in-depot vehicle fault may defer service '
   'before the handler resumes it anyway. Minutes, sim-domain. FLOOR 0, derived '
   'from the predicate flagged_at <= p_sim_clock - budget, where flagged_at is '
   'stamped from p_sim_clock by the SAME function: the premise flagged_at <= '
   'p_sim_clock holds by construction, so any budget at or below 0 makes the '
   'predicate unconditionally true and the budget expires on first evaluation. '
   'No ceiling: a budget never reached simply never expires, which is a real '
   'setting. Deliberately NOT given the 10..720 of its sibling '
   'indepot_defer_max_min_immobilizing -- that range is its author''s judgement, '
   'not a property of the engine.',
   45, 0, NULL, 'in-depot exception deferral'),

  ('indepot_defer_max_min_critical',
   '0304: the same budget for a critical-severity fault. Minutes, sim-domain. '
   'FLOOR 0, identical derivation to indepot_defer_max_min. No ceiling. NOT '
   'floored at 10 by copying the immobilizing sibling: this dial''s own default '
   'IS 10, so a floor of 10 would forbid every value below the default, '
   'including a deliberate five-minute critical budget. NOTE the catalog cannot '
   'express that this should stay at or below indepot_defer_max_min -- a '
   'critical fault deferring LONGER than a routine one is not prevented here '
   '(G61 second class).',
   10, 0, NULL, 'in-depot exception deferral'),

  ('l2_overflow_penalty',
   '0304: the score an L2 stall carries in ottoq_l2_optimize_assignments so a '
   'free DCFC plug always outbids it. Score units. The ORDER BY is '
   '(dcfc ? 0 : penalty) + distance_from_entrance * 0.1 ASC. FLOOR 0 BY '
   'INVERSION (0290''s derivation): a negative penalty makes L2 beat DCFC at '
   'equal distance, reversing the documented DCFC-first ordering. At exactly 0 '
   'the two types rank on distance alone -- a real setting, not an error. NO '
   'CEILING, deliberately: the penalty becomes fully dominant once it exceeds '
   'the distance term''s spread, which MEASURED 2026-09-14 is 0..368 units = '
   '0..36.8 score, so every value at or above ~36.8 behaves identically. That '
   'collapse point is derived from MUTABLE DEPOT DATA and sits BELOW this '
   'dial''s own default of 100, so pinning it as a max would clamp a caller '
   'asking for the code default and report a change that is not one.',
   100, 0, NULL, 'stall selection order'),

  ('timer_backstop_min',
   '0304: UNBOUNDED BY DESIGN (min NULL, max NULL) -- this row exists to ADMIT '
   'the key, not to clamp it; see the convention note below. Minutes past '
   'scheduled_return_at at which ottoq_recall_naive_threshold_v1 raises the '
   'timer_backstop recall. The predicate is p_sim_clock_now >= '
   'scheduled_return_at + (value || '' minutes'')::interval with NO enclosing '
   'clamp, so a NEGATIVE value genuinely fires the backstop BEFORE the '
   'scheduled return -- a distinguishable behaviour, not a collapse, so there '
   'is no floor to read. Its caller default is timer_backstop_ticks * 30.',
   1440, NULL, NULL, 'recall threshold'),

  ('timer_backstop_ticks',
   '0304: UNBOUNDED BY DESIGN (min NULL, max NULL) -- admits the key, clamps '
   'nothing. Supplies the CALLER DEFAULT of timer_backstop_min as '
   'get(...,''timer_backstop_ticks'',48) * 30, so it takes effect only when '
   'timer_backstop_min has no row at any scope. Its range is therefore its '
   'sibling''s divided by 30, and its sibling is unbounded.',
   48, NULL, NULL, 'recall threshold'),

  ('contention_wait_cap_min',
   '0304: UNBOUNDED BY DESIGN (min NULL, max NULL) -- admits the key, clamps '
   'nothing. Caps the estimated queue wait in '
   'ottoq_recall_naive_threshold_v1: LEAST(v_wait_ticks * 30.0, this) <= '
   'v_max_wait_min. v_wait_ticks is floored at 0 by its own CASE, so a negative '
   'cap would collapse ONLY IF v_max_wait_min were non-negative -- and '
   'v_max_wait_min reads ottoq_fleet_operator_slas.max_queue_wait_minutes, '
   'which MEASURED 2026-09-14 carries NO CHECK CONSTRAINT. All four live SLA '
   'rows hold 30, but a bound resting on today''s rows is the db/checks/0098 '
   'mistake. Unbounded, and stated as unbounded rather than guessed.',
   120, NULL, NULL, 'recall threshold'),

  ('contention_wait_cap_ticks',
   '0304: UNBOUNDED BY DESIGN (min NULL, max NULL) -- admits the key, clamps '
   'nothing. Supplies the CALLER DEFAULT of contention_wait_cap_min as '
   'get(...,''contention_wait_cap_ticks'',4) * 30, effective only when '
   'contention_wait_cap_min has no row at any scope. Blocked behind its sibling, '
   'which is unbounded for a reason recorded there.',
   4, NULL, NULL, 'recall threshold'),

  ('overnight_recall_hysteresis',
   '0304: UNBOUNDED BY DESIGN (min NULL, max NULL) -- admits the key, clamps '
   'nothing. Vehicles, not minutes. Subtracted from the surplus before the '
   'overnight recall: v_to_recall := GREATEST(0, deployed - desired - this). '
   'The GREATEST floors the RESULT at zero, but that does NOT collapse negative '
   'values the way the staging clamp does: a negative hysteresis recalls MORE '
   'than the surplus, which is a different fleet count at every value. No floor '
   'to read. CAVEAT: see overnight_recall_end_hour and db/checks/0227 -- this '
   'dial sits in a window whose close is a hard-coded literal (G64).',
   2, NULL, NULL, 'overnight recall'),

  ('service_hold_patience_min',
   '0304: UNBOUNDED BY DESIGN (min NULL, max NULL) -- admits the key, clamps '
   'nothing. Sim-minutes a vehicle may wait before ottoq_l2_propose_service '
   'stops holding it for service. The test is COALESCE(v_wait_min,0) <= this, '
   'and the COALESCE makes 0 a reachable wait -- so 0 (hold only a zero-length '
   'wait) and -1 (never hold) are distinguishable and there is no floor.',
   120, NULL, NULL, 'service hold');

-- ===========================================================================
-- A1. THE COUNTS MOVED EXACTLY AS PREDICTED, AND THE GAP IS NOW ZERO.
DO $a1$
DECLARE v_cat int; v_gap int; v_unread int; v_left text;
BEGIN
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog;
  IF v_cat <> 160 THEN
    RAISE EXCEPTION 'A1 FAILED: catalog is % rows, predicted 160', v_cat;
  END IF;
  SELECT count(*) INTO v_gap FROM public.ottoq_policy_catalog_gap
   WHERE status = 'read_uncatalogued';
  IF v_gap <> 0 THEN
    SELECT string_agg(param_key, ', ' ORDER BY param_key) INTO v_left
      FROM public.ottoq_policy_catalog_gap WHERE status = 'read_uncatalogued';
    RAISE EXCEPTION 'A1 FAILED: % dial(s) still uncatalogued (%)', v_gap, v_left;
  END IF;
  SELECT count(*) INTO v_unread FROM public.ottoq_policy_catalog_gap
   WHERE status = 'catalogued_unread';
  IF v_unread <> 8 THEN
    RAISE EXCEPTION 'A1 FAILED: catalogued_unread is %, predicted 8 (unchanged)', v_unread;
  END IF;
  RAISE NOTICE 'A1 OK: catalog 149 -> 160, read_uncatalogued 11 -> 0, catalogued_unread 8';
END $a1$;

-- A2. THE FIVE FLOORS CLAMP AT THEIR FLOOR AND NOWHERE ELSE.
DO $a2$
DECLARE
  v_scope uuid := '00000000-0000-0000-0000-0000030400cc'::uuid;
  v_r jsonb; r record; v_n int := 0;
BEGIN
  BEGIN
    FOR r IN
      SELECT k, floor_v FROM (VALUES
        ('staging_hold_default_min', 1::numeric),
        ('staging_hold_max_min', 1),
        ('indepot_defer_max_min', 0),
        ('indepot_defer_max_min_critical', 0),
        ('l2_overflow_penalty', 0)) AS f(k, floor_v)
    LOOP
      -- below the floor: clamps TO the floor and says so
      v_r := public.ottoq_policy_set('run', v_scope, r.k, r.floor_v - 7, '0304_proof');
      IF COALESCE((v_r->>'applied')::numeric, -999) <> r.floor_v
         OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
        RAISE EXCEPTION 'A2 FAILED: % below floor must clamp to % and say so: %',
                        r.k, r.floor_v, v_r;
      END IF;
      -- at the floor: accepted, not clamped
      v_r := public.ottoq_policy_set('run', v_scope, r.k, r.floor_v, '0304_proof');
      IF COALESCE((v_r->>'applied')::numeric, -999) <> r.floor_v
         OR COALESCE((v_r->>'clamped')::boolean, true) THEN
        RAISE EXCEPTION 'A2 FAILED: % AT its floor % must apply unclamped: %',
                        r.k, r.floor_v, v_r;
      END IF;
      -- far above: no ceiling, so no clamp
      v_r := public.ottoq_policy_set('run', v_scope, r.k, 99999, '0304_proof');
      IF COALESCE((v_r->>'applied')::numeric, -1) <> 99999
         OR COALESCE((v_r->>'clamped')::boolean, true) THEN
        RAISE EXCEPTION 'A2 FAILED: % has no ceiling and must not clamp at 99999: %', r.k, v_r;
      END IF;
      v_n := v_n + 1;
    END LOOP;
    IF v_n <> 5 THEN
      RAISE EXCEPTION 'A2 FAILED: tested % dials, half one inserted 5', v_n;
    END IF;
    RAISE EXCEPTION 'A2_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A2_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A2 OK: five floors clamp below, pass at, and never clamp above';
END $a2$;

-- A3. THE CONVENTION IS REAL: NULL/NULL ADMITS AND DOES NOT CLAMP.
-- This is the claim half two rests on, executed at both extremes rather than
-- argued from LEAST/GREATEST''s NULL handling.
DO $a3$
DECLARE
  v_scope uuid := '00000000-0000-0000-0000-0000030400cc'::uuid;
  v_r jsonb; r record; v_n int := 0;
BEGIN
  BEGIN
    FOR r IN
      SELECT c.param_key FROM public.ottoq_policy_param_catalog c
       WHERE c.description LIKE '0304:%'
         AND c.min_value IS NULL AND c.max_value IS NULL
       ORDER BY c.param_key
    LOOP
      v_r := public.ottoq_policy_set('run', v_scope, r.param_key, -99999, '0304_proof');
      IF NOT COALESCE((v_r->>'ok')::boolean, false)
         OR COALESCE((v_r->>'applied')::numeric, 0) <> -99999
         OR COALESCE((v_r->>'clamped')::boolean, true) THEN
        RAISE EXCEPTION 'A3 FAILED: % is NULL/NULL and must admit -99999 unclamped: %',
                        r.param_key, v_r;
      END IF;
      v_r := public.ottoq_policy_set('run', v_scope, r.param_key, 99999, '0304_proof');
      IF NOT COALESCE((v_r->>'ok')::boolean, false)
         OR COALESCE((v_r->>'applied')::numeric, 0) <> 99999
         OR COALESCE((v_r->>'clamped')::boolean, true) THEN
        RAISE EXCEPTION 'A3 FAILED: % is NULL/NULL and must admit 99999 unclamped: %',
                        r.param_key, v_r;
      END IF;
      v_n := v_n + 1;
    END LOOP;
    IF v_n <> 6 THEN
      RAISE EXCEPTION 'A3 FAILED: % NULL/NULL rows from this file, half two inserted 6', v_n;
    END IF;
    RAISE EXCEPTION 'A3_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A3_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A3 OK: all six NULL/NULL dials admit both extremes and clamp neither';
END $a3$;

-- A4. AN UNCATALOGUED KEY IS STILL REFUSED. The allow-list half of the catalog
-- must still work, or "admitted" means nothing.
DO $a4$
DECLARE v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', '00000000-0000-0000-0000-0000030400cc'::uuid,
                                 'no_such_dial_0304', 1, '0304_proof');
  IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'unknown_param' THEN
    RAISE EXCEPTION 'A4 FAILED: an uncatalogued key was not refused: %', v_r;
  END IF;
  RAISE NOTICE 'A4 OK: the catalog is still the allow-list';
END $a4$;

-- A5. NO EXISTING KEY'S CLAMP MOVED. Regression over every bound in the
-- catalog, the 149 that were there before included.
DO $a5$
DECLARE
  v_scope uuid := '00000000-0000-0000-0000-0000030400cc'::uuid;
  v_r jsonb; r record; v_checks int := 0;
BEGIN
  BEGIN
    FOR r IN
      SELECT param_key, min_value, max_value, min_exclusive, max_exclusive
        FROM public.ottoq_policy_param_catalog ORDER BY param_key
    LOOP
      IF r.min_value IS NOT NULL AND r.min_exclusive IS NULL THEN
        v_r := public.ottoq_policy_set('run', v_scope, r.param_key, r.min_value - 1, '0304_proof');
        IF COALESCE((v_r->>'applied')::numeric, -999999) <> r.min_value THEN
          RAISE EXCEPTION 'A5 FAILED: %''s floor no longer clamps to %: %',
                          r.param_key, r.min_value, v_r;
        END IF;
        v_checks := v_checks + 1;
      END IF;
      IF r.max_value IS NOT NULL AND r.max_exclusive IS NULL THEN
        v_r := public.ottoq_policy_set('run', v_scope, r.param_key, r.max_value + 1, '0304_proof');
        IF COALESCE((v_r->>'applied')::numeric, -999999) <> r.max_value THEN
          RAISE EXCEPTION 'A5 FAILED: %''s ceiling no longer clamps to %: %',
                          r.param_key, r.max_value, v_r;
        END IF;
        v_checks := v_checks + 1;
      END IF;
    END LOOP;
    IF v_checks < 250 THEN
      RAISE EXCEPTION 'A5 FAILED: only % bound checks ran; 0303 ran 250 and this file '
                      'adds five more floors, so a smaller number means bounds vanished', v_checks;
    END IF;
    RAISE EXCEPTION 'A5_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A5_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A5 OK: every catalogued bound still clamps where it did';
END $a5$;

-- A6. NO RESIDUE.
DO $a6$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE scope_id = '00000000-0000-0000-0000-0000030400cc'::uuid
      OR updated_by = '0304_proof';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A6 FAILED: % probe row(s) survived', v_n;
  END IF;
  RAISE NOTICE 'A6 OK: no probe rows survived';
END $a6$;

-- ===========================================================================
-- LINEAGE. Written HERE, in the migration, because five files in a row (0296-
-- 0300) argued forces_recert=false in their headers and never wrote the row --
-- and ottoq_cert_recert_floor reads COALESCE(forces_recert, TRUE), so a
-- missing row says the OPPOSITE of what those headers said. Repaired by 0301.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0304_five_more_floors_and_six_dials_admitted_without_a_clamp', false,
        'Inserts 11 ottoq_policy_param_catalog rows and changes no function. '
        'ottoq_policy_get never reads the catalog (P1 re-executes that proof), so '
        'no value observed by any tick can move. P6 proved no live value sits '
        'below a floor this file introduces, so no in-force value is clamped '
        'either. Completes the dial catalogue: 92 -> 0.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- A7. THE FLOOR DID NOT MOVE.
DO $a7$
DECLARE v_floor timestamptz;
BEGIN
  SELECT public.ottoq_cert_recert_floor() INTO v_floor;
  IF v_floor <> '2026-09-12 16:50:23.319089+00'::timestamptz THEN
    RAISE EXCEPTION 'A7 FAILED: recert floor moved to % -- this file classified itself '
                    'forces_recert=false and must not unstreak any column', v_floor;
  END IF;
  RAISE NOTICE 'A7 OK: recert floor unmoved at %', v_floor;
END $a7$;
