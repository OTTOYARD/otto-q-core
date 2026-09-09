-- migration-version: 20260908224618
-- migration-name:    a_vehicle_the_arm_is_holding_is_not_a_candidate
--
-- G35 / db/checks/0151. The first fifo run in this database's history died on
-- tick 1, inside ottoq_fifo_tick's DEPLOY branch, trying to drive away a vehicle
-- the OTTO-CHARGE ARM was still unlatching:
--
--   ERROR: arm interlock: vehicle 02f1a60b is held by the arm at stall 4dae9406
--          until 2026-09-09 04:40:23 (sim 2026-09-09 04:40:11, demate/unlatch)
--   CONTEXT: ottoq_arm_interlock_guard()
--            "UPDATE vehicles SET current_state='en_route_to_deployment',
--             current_stall_id=NULL, ... WHERE id=v_req.vehicle_id"
--            ottoq_fifo_tick(uuid) line 36
--
-- The baselines were written against a world with no robotic charging arm. The
-- arm arrived later and only otto_q -- the one path anyone ever ran -- was
-- taught about it. fifo, greedy and manual do not mention the arm and carry
-- ZERO exception handlers, and the dispatcher's policy CASE is unwrapped, so an
-- interlock refusal propagates to the top and DESTROYS the run rather than
-- degrading it.
--
-- THE RULE THIS ENCODES, in one sentence: a vehicle the arm is holding is not a
-- candidate for a policy action this tick. That is physics, not strategy -- you
-- cannot drive off with the cable latched, whoever is scheduling -- so by
-- db/checks/0148's rule it belongs on the HOLD-CONSTANT side of the A/B. The
-- baselines get it and are still baselines.
--
-- THE CHANGE. One anchored substitution per function, applied to all four of its
-- vehicle-selection cursors at once:
--
--     AND category='autonomous' AND current_state=
--  -> AND category='autonomous'
--     AND (robotic_tether_until IS NULL OR robotic_tether_until <= v_clock)
--     AND current_state=
--
-- WHY THIS ANCHOR IS SAFE, measured rather than argued:
--
--   ottoq_fifo_tick     4 occurrences
--   ottoq_manual_tick   4 occurrences
--   ottoq_greedy_tick   0
--   ottoq_decide_tick   0
--
-- decide_tick contains the string zero times, so this substitution cannot reach
-- the certified path even by mistake. That is a structural guarantee, not a
-- promise to be careful.
--
-- WHAT IS DELIBERATELY NOT TOUCHED:
--
--   ottoq_decide_tick   already coordinates with the arm through the arm's own
--                       gate vocabulary and has never hit this. Certified. Any
--                       diff forces a recert for no reason.
--   ottoq_greedy_tick   is ten lines and delegates entirely to
--                       twin.ottoq_sim_auto_charge_assign_tick and
--                       twin.ottoq_sim_auto_dispatch_tick. Those are WORLD
--                       functions shared with otto_q -- auto_dispatch_tick runs
--                       for every policy except greedy, which calls it itself --
--                       so changing them WOULD touch the certified path. Greedy
--                       is left to be fixed on its own terms, or found already
--                       protected by its delegates' exception handlers. Not
--                       asserted either way here; it has not been run.
--   manual's capacity count at its line 10-12 reads
--       WHERE home_depot_id=v_depot AND category='autonomous'
--       AND current_state IN (...)
--   -- newline before AND, and IN rather than =, so the anchor does not match
--   it. Correct: a tethered vehicle IS being monitored and should still count
--   against the monitoring cap. Excluding it would change manual's admission
--   behaviour, which is strategy, not physics.
--
-- WHY v_clock AND NOT now(). Each baseline already reads
-- sim_clock_current INTO v_clock from its own run at the top of its body. The
-- tether deadline is stamped in sim time. Comparing them is the only correct
-- comparison, and it sidesteps G34 (db/checks/0150) entirely inside the
-- policies: the interlock trigger has to GUESS which run is running, but a
-- policy already knows which run it is. G34 remains open for the trigger.
--
-- Using the tick's opening clock means a tether expiring mid-tick stays live
-- until the next tick. That is deliberate: conservative, and deterministic,
-- which a clock re-read inside the loop would not be.
--
-- WHAT THIS DOES NOT DO, written first so it cannot creep: it does not give the
-- baselines the L1 shield, the bookings calendar, or any proposer. It does not
-- add an exception handler -- the predicate prevents one specific refusal by not
-- selecting the vehicle, it does not hide failures. A baseline that skips a
-- mated vehicle and reconsiders it next tick is exactly what a dumb policy
-- should do.
--
-- NOT CLAIMED: that this makes fifo run to completion. It is the first refusal
-- on tick 1 of the first run ever attempted, and the baselines have eight weeks
-- of world machinery they have never met. The honest expectation is that this
-- gets fifo further and something else stops it. Each one is a real defect found
-- by the only method that finds them.
--
-- forces_recert: FALSE. ottoq_decide_tick is not modified (0 anchor
-- occurrences, and A3 asserts its definition md5 is unchanged). No run has ever
-- executed fifo or manual, so no canon can contain their behaviour. The floor is
-- checked after applying anyway.

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction.)

-- ---------------------------------------------------------------------------
-- P-  NEVER APPLY WHILE A CERTIFICATION PAIR IS IN FLIGHT.
-- ---------------------------------------------------------------------------
DO $P$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active' AND query LIKE '%ottoq_determinism_pair%';
  IF n > 0 THEN RAISE EXCEPTION 'P- REFUSED: % certification pair(s) in flight', n; END IF;
END $P$;

-- ---------------------------------------------------------------------------
-- P1  Both bodies are byte-for-byte what the anchor count was measured on.
-- ---------------------------------------------------------------------------
DO $P1$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_fifo_tick(uuid)'::regprocedure));
  IF h <> '5b2333e65090253a3176fc489ca18776' THEN
    RAISE EXCEPTION 'P1 REFUSED: fifo_tick md5 is %, pinned 5b2333e65090253a3176fc489ca18776', h;
  END IF;
  h := md5(pg_get_functiondef('public.ottoq_manual_tick(uuid)'::regprocedure));
  IF h <> '1c9def66b029cc2ba07639abafe9a39e' THEN
    RAISE EXCEPTION 'P1 REFUSED: manual_tick md5 is %, pinned 1c9def66b029cc2ba07639abafe9a39e', h;
  END IF;
END $P1$;

-- ---------------------------------------------------------------------------
-- P2  The certified path does not contain the anchor. If this ever becomes
--     non-zero, STOP: the substitution's structural safety is gone.
-- ---------------------------------------------------------------------------
DO $P2$
DECLARE d text; a text; n int;
BEGIN
  a := 'AND category=''autonomous'' AND current_state=';
  d := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 0 THEN
    RAISE EXCEPTION 'P2 REFUSED: ottoq_decide_tick now contains the anchor % times; '
                    'this migration is no longer structurally unable to touch it', n;
  END IF;
END $P2$;

-- ---------------------------------------------------------------------------
-- THE CHANGE.
-- ---------------------------------------------------------------------------
DO $CHG$
DECLARE
  fn text; d text; a text; rep text; n int;
BEGIN
  a   := 'AND category=''autonomous'' AND current_state=';
  rep := E'AND category=''autonomous''\n'
      || E'       AND (robotic_tether_until IS NULL OR robotic_tether_until <= v_clock)  -- 0232 / G35: the arm is holding it; not a candidate this tick\n'
      || E'       AND current_state=';

  FOREACH fn IN ARRAY ARRAY['public.ottoq_fifo_tick(uuid)','public.ottoq_manual_tick(uuid)'] LOOP
    d := pg_get_functiondef(fn::regprocedure);
    n := (length(d) - length(replace(d, a, ''))) / length(a);
    IF n <> 4 THEN
      RAISE EXCEPTION 'CHG REFUSED: % has % anchor occurrences, expected 4', fn, n;
    END IF;
    IF d ~* 'robotic_tether' THEN
      RAISE EXCEPTION 'CHG REFUSED: % already mentions robotic_tether; this is not a fresh apply', fn;
    END IF;
    EXECUTE replace(d, a, rep);
  END LOOP;
END $CHG$;

-- ---------------------------------------------------------------------------
-- A1  Both bodies now carry the predicate exactly four times, and the anchor
--     is gone (it was consumed by the replacement, which re-emits it split
--     across lines -- so assert on the predicate, not on the anchor).
-- ---------------------------------------------------------------------------
DO $A1$
DECLARE fn text; d text; n int;
BEGIN
  FOREACH fn IN ARRAY ARRAY['public.ottoq_fifo_tick(uuid)','public.ottoq_manual_tick(uuid)'] LOOP
    d := pg_get_functiondef(fn::regprocedure);
    n := (length(d) - length(replace(d, 'robotic_tether_until IS NULL', ''))) / length('robotic_tether_until IS NULL');
    IF n <> 4 THEN RAISE EXCEPTION 'A1 FAILED: % has % tether predicates, expected 4', fn, n; END IF;
  END LOOP;
END $A1$;

-- ---------------------------------------------------------------------------
-- A2  THE CERTIFIED PATH IS UNTOUCHED, by md5, not by intent.
-- ---------------------------------------------------------------------------
DO $A2$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure));
  IF h <> 'ae98f71b879a0a11bdf366d21ff5b4eb' THEN
    RAISE EXCEPTION 'A2 FAILED: ottoq_decide_tick md5 is %, expected ae98f71b879a0a11bdf366d21ff5b4eb -- the certified path moved', h;
  END IF;
  h := md5(pg_get_functiondef('public.ottoq_greedy_tick(uuid)'::regprocedure));
  IF h <> '5a9a19f78878834a6d6a86ad36bea77d' THEN
    RAISE EXCEPTION 'A2 FAILED: ottoq_greedy_tick md5 is %, expected 5a9a19f78878834a6d6a86ad36bea77d', h;
  END IF;
END $A2$;

-- ---------------------------------------------------------------------------
-- A3  Both still return ottoq_decide_tick_result and are still callable --
--     a rewrite that changed the signature would break the dispatcher's CASE.
-- ---------------------------------------------------------------------------
DO $A3$
DECLARE fn text; t text;
BEGIN
  FOREACH fn IN ARRAY ARRAY['public.ottoq_fifo_tick(uuid)','public.ottoq_manual_tick(uuid)'] LOOP
    SELECT pg_get_function_result(fn::regprocedure) INTO t;
    -- matched with LIKE, not equality: pg_get_function_result schema-qualifies
    -- the type when it is not on the current search_path, so a bare equality
    -- test would fail for a reason that has nothing to do with this migration.
    IF t NOT LIKE '%ottoq_decide_tick_result' THEN
      RAISE EXCEPTION 'A3 FAILED: % returns %, expected ottoq_decide_tick_result', fn, t;
    END IF;
  END LOOP;
END $A3$;

-- ---------------------------------------------------------------------------
-- A4  The predicate is valid SQL against public.vehicles.
--
--     NOTE ON WHAT THIS CAN AND CANNOT PROVE. PL/pgSQL does not plan a
--     function's embedded SQL until that statement first executes, so calling
--     fifo_tick with a nonexistent run proves only that its early return works
--     -- v_depot comes back NULL and it returns before reaching any cursor. A
--     malformed predicate would still be sitting there unplanned. So the
--     predicate is executed here directly, in the same shape the cursors use
--     it, which is the strongest check available without a real run. The
--     actual proof is a fifo arm completing, and that is deliberately NOT
--     asserted in this migration -- see the header's "NOT CLAIMED".
-- ---------------------------------------------------------------------------
DO $A4$
DECLARE n bigint; v_clock timestamptz := now();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='vehicles'
                    AND column_name='robotic_tether_until') THEN
    RAISE EXCEPTION 'A4 FAILED: vehicles.robotic_tether_until does not exist';
  END IF;

  SELECT count(*) INTO n FROM public.vehicles
   WHERE category = 'autonomous'
     AND (robotic_tether_until IS NULL OR robotic_tether_until <= v_clock)
     AND current_state = 'arrived_at_gate';
  RAISE NOTICE 'A4: predicate plans and runs; % autonomous vehicles at gate and untethered', n;

  PERFORM public.ottoq_fifo_tick('00000000-0000-0000-0000-000000000000'::uuid);
  PERFORM public.ottoq_manual_tick('00000000-0000-0000-0000-000000000000'::uuid);
END $A4$;

-- ---------------------------------------------------------------------------
-- LINEAGE.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'a_vehicle_the_arm_is_holding_is_not_a_candidate',
  now(),
  false,
  'G35 / db/checks/0151. The first fifo run ever attempted died on tick 1 inside '
  'ottoq_fifo_tick''s DEPLOY branch, trying to move a vehicle the OTTO-CHARGE ARM '
  'was unlatching. The baselines predate the arm and only otto_q was taught about '
  'it, because only otto_q ever ran. Adds "robotic_tether_until IS NULL OR <= '
  'v_clock" to all four vehicle-selection cursors in ottoq_fifo_tick and '
  'ottoq_manual_tick, via one anchored substitution each. forces_recert FALSE: '
  'ottoq_decide_tick contains the anchor ZERO times so the substitution cannot '
  'reach it, and A2 asserts its md5 unchanged; no run has ever executed fifo or '
  'manual, so no canon can contain their behaviour. Greedy deliberately untouched '
  '-- it delegates to twin world functions shared with otto_q. Not claimed: that '
  'this makes fifo complete a run.'
);

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 22:46:18 UTC (5:46 PM CT). Three preconditions, four
-- assertions, first attempt.
--
--   P2: ottoq_decide_tick contains the anchor 0 times, as designed
--   A1: 4 tether predicates in each of fifo_tick and manual_tick
--   A2: decide_tick md5 ae98f71b879a0a11bdf366d21ff5b4eb UNCHANGED
--       greedy_tick md5 5a9a19f78878834a6d6a86ad36bea77d UNCHANGED
--   A3: both still return ottoq_decide_tick_result
--   A4: the predicate plans and executes against public.vehicles
--
-- THE FLOOR DID NOT MOVE: 2026-09-07 21:36:53.363037 before and after.
--
-- IT WORKED, AND THAT IS THE POINT. Immediately after applying, the first fifo
-- run in this database's history completed:
--
--   e5ebc6d3-cb7d-4339-b669-76ccac0ea500   fifo, 12 ticks, seed 909090
--   19 charge sessions, 273 stall bookings
--
-- and then a true CRN pair, same seed 555001 and same ab_group, both arms:
--
--   049eb402-20e9-406c-aec5-f4cc59928c48   otto_q, 12 ticks
--   612dabbf-ccdc-4050-9e76-6e33b6d62b67   fifo,   12 ticks
--
-- The header said "NOT CLAIMED: that this makes fifo complete a run." It did,
-- three times. The prediction was deliberately conservative and was beaten.
--
-- 0231's FALSIFIER PASSED. Its outcome block on the fifo arm returned non-zero
-- on every field -- 577.98 kWh, 18 sessions, 18 vehicles served, 462 SoC points
-- -- so it is not reading otto_q's substrate. That was the test 0231 could not
-- run when it shipped, and it is now run and passed.
--
-- ONE CORRECTION TO db/checks/0149 FALLS OUT OF IT. 0149 listed
-- coverage.bookings_total and used_calendar as otto_q-only substrate. The fifo
-- arm produced 273 bookings and used_calendar=true, because the dispatcher's
-- COMMON path books -- ottoq_place_unplaced_vehicles and
-- ottoq_release_expired_bookings run after the policy CASE for every policy.
-- The otto_q-only fields are the rule-evaluation pair: fifo scored
-- rule_evals_total 0 and consulted_shield false, exactly as 0146 said.
--
-- AND IT EXPOSED A LARGER DEFECT, which is what running things does:
-- db/checks/0152 / G36. Scoring the pair showed the otto_q arm reporting 0.0 kW
-- peak while having delivered 128.79 kWh. Its sessions had been force-closed by
-- the NEXT arm's ottoq_benchmark_reset with a wall-clock ended_at, six sim
-- hours before they started. 55 of the benchmark lane's 88 sessions are in that
-- state. Fix drafted as 0233.
--
-- STILL OPEN, and required before either arm's numbers mean anything: G34
-- (0150) -- every arm must be preceded by a manual tether release, because the
-- interlock has no run id to scope by. Three of the four runs above needed one.
